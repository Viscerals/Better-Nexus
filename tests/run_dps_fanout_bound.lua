-- Stage 36.3 expected red: equivalent DPS responders must reuse the existing
-- deterministic bucket-claim/fairness owners so WLD2 traffic stays fixed as
-- the visible peer count grows. Direct-owner publication and the established
-- response-only authorized-relay path remain green controls.

local H = dofile("tests/harness.lua")
local HarnessNexus = Nexus

local clock = 1000
local actor = "FanoutFixture"
GetTime = function() return clock end
time = function() return 50000 end
UnitName = function() return actor end
GetNormalizedRealmName = function() return "Ebonhold" end
UnitClass = function() return "Mage", "MAGE" end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[DeepCopy(key, seen)] = DeepCopy(item, seen)
    end
    return copy
end

local function Boot(name, db)
    actor = name
    NexusDB = db
    Nexus.CommunityBuilds = nil
    dofile("core/Revisions.lua")
    dofile("core/Codec.lua")
    dofile("core/SyncProtocol.lua")
    dofile("core/SyncTransport.lua")
    dofile("core/SyncCompatibility.lua")
    dofile("core/SyncReconciler.lua")
    dofile("core/SyncInbound.lua")
    dofile("core/SyncDiagnostics.lua")
    dofile("core/SyncSession.lua")
    dofile("core/Sync.lua")
    dofile("core/DpsCapture.lua")
    Nexus.DpsCapture.Init({}, Nexus.Sync)
    Nexus.Sync.Init(Nexus.Codec, {})
    H.sentChatMessages = {}
    return Nexus.Sync, Nexus.DpsCapture
end

-- A concurrent cohort needs each simulated client to retain its own module
-- closures, database, transport queue, and diagnostics. The production files
-- still execute unchanged; only their Nexus namespace and WoW globals are
-- activated for the client whose 0.2-second update is being processed.
local function BootPeer(name, db)
    actor = name
    NexusDB = db
    Nexus = setmetatable({SyncInternals={},CommunityBuilds=false}, {
        __index=HarnessNexus,
    })
    dofile("core/Revisions.lua")
    dofile("core/Codec.lua")
    dofile("core/SyncProtocol.lua")
    dofile("core/SyncTransport.lua")
    dofile("core/SyncCompatibility.lua")
    dofile("core/SyncReconciler.lua")
    dofile("core/SyncInbound.lua")
    dofile("core/SyncDiagnostics.lua")
    dofile("core/SyncSession.lua")
    dofile("core/Sync.lua")
    dofile("core/DpsCapture.lua")
    Nexus.DpsCapture.Init({}, Nexus.Sync)
    Nexus.Sync.Init(Nexus.Codec, {})
    H.sentChatMessages = {}
    return {
        name=name,db=NexusDB,nexus=Nexus,sync=Nexus.Sync,
        dps=Nexus.DpsCapture,messages=H.sentChatMessages,messageCursor=0,
    }
end

local function Activate(peer)
    actor = peer.name
    NexusDB = peer.db
    Nexus = peer.nexus
    H.sentChatMessages = peer.messages
end

local function Pump(sync, steps)
    for _ = 1, steps do
        clock = clock + 0.2
        sync.OnUpdate(0.2)
    end
end

local function NonzeroBucket(hash)
    local bucket = 0
    for value in tostring(hash):gmatch("([^,]+)") do
        bucket = bucket + 1
        if value ~= "0" then return bucket, value end
    end
end

local function StableOrdinal(text)
    local hash = 5381
    text = tostring(text or "")
    for index = 1, #text do
        hash = ((hash * 33) + text:byte(index)) % 1000003
    end
    return hash % 1000
end

local REQUESTER = "FanoutRequester"
local REQUEST_ID = "c1-fanout-fixed"
local ZERO_DPS = "0,0,0,0,0,0,0,0"
local echoes = {
    {spellId=360301,stacks=1},
    {spellId=360302,stacks=2},
}

-- Choose the direct owner as the deterministic first D-bucket responder. This
-- lets the bound exercise claim suppression without weakening owner utility.
local peerNames = {}
for index = 1, 20 do
    peerNames[index] = string.format("FanoutPeer%02d", index)
end

-- Seed one exact row through the real direct-owner receiver before computing
-- its bucket and the production fairness order.
local provisionalOwner = peerNames[1]
local Sync, DPS = Boot(provisionalOwner, {
    communityBuilds={},syncTombstones={},dpsCapture={},
})
local fingerprint = DPS.GetEchoKey(echoes)
local loadoutHash = DPS.GetEchoHash(echoes)
local compact = {
    v=7,f=fingerprint,h=loadoutHash,e=echoes,c="dummy",
    d=36030000,u=65,t=49000,p=provisionalOwner,l=80,k="MAGE",
    o=provisionalOwner:lower() .. "@ebonhold",r="ebonhold",
}
assert(DPS.ReceiveRecord(compact, provisionalOwner .. "-Ebonhold"),
    "direct-owner seed was rejected")
local _, provisionalDpsHash = Sync.GetCompatibilityHashes()
local dpsBucket = assert(NonzeroBucket(provisionalDpsHash),
    "seed row did not occupy a DPS bucket")

table.sort(peerNames, function(left, right)
    local prefix = REQUESTER .. ":" .. REQUEST_ID .. ":D:"
        .. tostring(dpsBucket) .. ":"
    local leftRank = StableOrdinal(prefix .. left)
    local rightRank = StableOrdinal(prefix .. right)
    if leftRank == rightRank then return left < right end
    return leftRank < rightRank
end)
local owner = peerNames[1]

-- Reseed with the chosen deterministic winner as the actual row owner.
Sync, DPS = Boot(owner, {
    communityBuilds={},syncTombstones={},dpsCapture={},
})
fingerprint = DPS.GetEchoKey(echoes)
loadoutHash = DPS.GetEchoHash(echoes)
compact = {
    v=7,f=fingerprint,h=loadoutHash,e=echoes,c="dummy",
    d=36030000,u=65,t=49000,p=owner,l=80,k="MAGE",
    o=owner:lower() .. "@ebonhold",r="ebonhold",
}
assert(DPS.ReceiveRecord(compact, owner .. "-Ebonhold"),
    "ranked direct-owner seed was rejected")
local seedBuildHash, seedDpsHash = Sync.GetCompatibilityHashes()
dpsBucket = assert(NonzeroBucket(seedDpsHash),
    "ranked seed row did not occupy a DPS bucket")
local seedDb = DeepCopy(NexusDB)
local verboseRecord = {
    protocolVersion=7,fingerprint=fingerprint,loadoutHash=loadoutHash,
    echoes=echoes,category="dummy",dps=compact.d,duration=compact.u,
    ts=compact.t,player=owner,level=80,class="MAGE",
    ownerKey=compact.o,realm=compact.r,
}

-- SendChatMessage receives doubled pipe escapes; the shared channel delivers
-- the corresponding single-pipe wire text to SyncInbound.
local function WireText(message)
    return tostring(message or ""):gsub("||", "|")
end

local function ClaimSender(message)
    return tostring(message):match("^[^|]+|([^|]+)|")
end

local function MatchingClaim(message)
    if message:find("^WLRC|", 1, false)
        and message:find("|" .. REQUESTER .. "|" .. REQUEST_ID .. "|",
            1, true) then
        return true
    end
    return message:find("^WLBC|", 1, false)
        and message:find("|" .. REQUESTER .. "|" .. REQUEST_ID
            .. "|D|" .. tostring(dpsBucket) .. "|", 1, true) ~= nil
end

local function TransferStats(messages)
    local transfers, chunks, seen = 0, 0, {}
    for _, item in ipairs(messages) do
        local wire = WireText(item.text)
        local sender, transfer = wire:match("^WLD2|([^|]+)|([^|]+)|")
        if sender and transfer then
            chunks = chunks + 1
            local key = sender .. "|" .. transfer
            if not seen[key] then
                seen[key] = true
                transfers = transfers + 1
            end
        end
    end
    return transfers, chunks
end

local function IsBucketClaim(message, requestId, bucket)
    local responder, requester, incomingId, kind, incomingBucket =
        tostring(message):match("^WLBC|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|")
    return responder ~= nil and requester == REQUESTER
        and incomingId == requestId and kind == "D"
        and tonumber(incomingBucket) == tonumber(bucket)
end

local function IsResponseClaim(message, requestId)
    local responder, requester, incomingId = tostring(message):match(
        "^WLRC|([^|]+)|([^|]+)|([^|]+)|")
    return responder ~= nil and requester == REQUESTER
        and incomingId == requestId
end

local function ConcurrentCohort(names, db, expectedBuildHash,
        expectedDpsHash, requestId, bucket, steps)
    local peers, result = {}, {
        responders=0,transfers=0,chunks=0,claims=0,electionClaims=0,
        directSenders={},relaySenders={},transferOwners={},
        responseStats={},outboundStats={},work={},codes={},
    }
    for _, name in ipairs(names) do
        local peer = BootPeer(name, DeepCopy(db))
        Activate(peer)
        local buildHash, dpsHash = peer.sync.GetCompatibilityHashes()
        assert(buildHash == expectedBuildHash and dpsHash == expectedDpsHash,
            "concurrent responder hashes drifted")
        local request = table.concat({
            "WLRQ", REQUESTER, buildHash, ZERO_DPS, requestId,
        }, "|")
        assert(peer.sync.HandleIncoming(request, REQUESTER),
            "concurrent encoded mismatch request was rejected")
        peers[#peers + 1] = peer
    end

    -- Every participant is scheduled before any response work runs. Updates
    -- then advance in shared 0.2-second rounds, and channel claims emitted in a
    -- round are fanned out only after all participants received that round.
    -- This prevents the serialized-fixture shortcut where later clients do not
    -- even exist until an earlier responder has fully drained.
    for _ = 1, (steps or 200) do
        clock = clock + 0.2
        for _, peer in ipairs(peers) do
            Activate(peer)
            peer.sync.OnUpdate(0.2)
        end
        local claims = {}
        for _, peer in ipairs(peers) do
            for index = peer.messageCursor + 1, #peer.messages do
                local wire = WireText(peer.messages[index].text)
                if IsBucketClaim(wire, requestId, bucket)
                    or IsResponseClaim(wire, requestId) then
                    claims[#claims + 1] = {
                        wire=wire,sender=assert(ClaimSender(wire)),
                    }
                end
            end
            peer.messageCursor = #peer.messages
        end
        for _, claim in ipairs(claims) do
            for _, peer in ipairs(peers) do
                if peer.name ~= claim.sender then
                    Activate(peer)
                    peer.sync.HandleIncoming(claim.wire, claim.sender)
                end
            end
        end
    end

    for _, peer in ipairs(peers) do
        local peerTransfers, peerChunks = TransferStats(peer.messages)
        if peerTransfers > 0 then result.responders = result.responders + 1 end
        result.transfers = result.transfers + peerTransfers
        result.chunks = result.chunks + peerChunks
        for _, item in ipairs(peer.messages) do
            local wire = WireText(item.text)
            local code = wire:match("^([^|]+)") or "?"
            result.codes[code] = (result.codes[code] or 0) + 1
            if code == "WLBC" and not result.firstBucketClaim then
                result.firstBucketClaim = wire
            end
            if IsBucketClaim(wire, requestId, bucket) then
                result.claims = result.claims + 1
            end
            if IsResponseClaim(wire, requestId) then
                result.electionClaims = result.electionClaims + 1
            end
            local sender, transfer = wire:match("^WLD2|([^|]+)|([^|]+)|")
            if sender and transfer then
                local transferKey = sender .. "|" .. transfer
                if not result.transferOwners[transferKey] then
                    result.transferOwners[transferKey] = true
                    local recordOwner = transfer:match("^([^:]+):")
                    if recordOwner and recordOwner:lower() == sender:lower() then
                        result.directSenders[sender] = true
                    else
                        result.relaySenders[sender] = true
                    end
                end
            end
        end
        Activate(peer)
        result.responseStats[peer.name] = peer.sync.ResponseStats()
        result.outboundStats[peer.name] = peer.dps.OutboundStats()
        result.work[peer.name] = peer.sync.WorkState()
    end
    return result
end

local function BackpressureResumeControl(name, db, expectedBuildHash,
        expectedDpsHash, requestId, bucket)
    local peer = BootPeer(name, DeepCopy(db))
    Activate(peer)
    local limits = peer.sync.WorkState()
    local fill = limits.maxOutboundQueue - 2
    for index = 1, fill do
        assert(peer.sync.BroadcastDps("preload-" .. tostring(index), name,
            100000 + index, 80, "dummy"))
    end
    -- Preloaded packets are old enough to expire shortly after the cheap
    -- backpressure probe, while the actual request remains newly scheduled.
    clock = clock + 295
    local request = table.concat({"WLRQ", REQUESTER, expectedBuildHash,
        ZERO_DPS, requestId}, "|")
    assert(peer.sync.HandleIncoming(request, REQUESTER),
        "backpressure request was rejected")
    local before = peer.sync.ResponseStats()
    clock = clock + 0.2
    peer.sync.OnUpdate(0.2)
    local blocked = peer.sync.ResponseStats()
    local blockedQueue = peer.sync.WorkState().sending

    -- The bounded cleanup loop expires only the synthetic preload. Keeping the
    -- clock fixed while it drains proves the fresh request itself remains live.
    clock = clock + 5
    for _ = 1, 270 do peer.sync.OnUpdate(0) end
    assert(peer.sync.WorkState().sending == 0,
        "expired backpressure preload did not drain")
    peer.messages = {}
    H.sentChatMessages = peer.messages
    for _ = 1, 220 do
        clock = clock + 0.2
        Activate(peer)
        peer.sync.OnUpdate(0.2)
    end
    local transfers, chunks = TransferStats(peer.messages)
    local claims = 0
    for _, item in ipairs(peer.messages) do
        if IsBucketClaim(WireText(item.text), requestId, bucket) then
            claims = claims + 1
        end
    end
    return {
        fill=fill,blockedQueue=blockedQueue,
        beforeWork=before.workUnits,blockedWork=blocked.workUnits,
        beforeBuild=before.chunkMessagesBuilt,
        blockedBuild=blocked.chunkMessagesBuilt,
        deferrals=(blocked.backpressureDeferrals or 0)
            - (before.backpressureDeferrals or 0),
        transfers=transfers,chunks=chunks,claims=claims,
        final=peer.sync.ResponseStats(),
    }
end

local function AdmissionBoundaryControl()
    local Factory = assert(Nexus.SyncInternals.Reconciler)
    local calls, current = 0, 0
    local function Split(value)
        local out = {}
        for item in tostring(value or ""):gmatch("([^,]+)") do
            out[#out + 1] = item
        end
        return out
    end
    local reconciler = Factory.New({
        bucketCount=8,maxPendingResponses=4,maxPendingLoadouts=4,
        pendingTtl=300,pendingMaxAge=600,
        claimDelayMin=0,claimDelayMax=1,bucketClaimMax=0,
        maxChunksPerRequest=100,maxBytesPerRequest=100000,
        maxSendSecondsPerRequest=1000,
        maxTransfersPerRequest=100,maxConcurrentTransfers=100,
        sendInterval=0.01,responseElectionDelay=0.01,
        now=function() return current end,myName=function() return "BoundaryPeer" end,
        stableDelay=function() return 0 end,splitHashes=Split,
        deltaBuildHash=function() return ZERO_DPS end,
        currentBuildHash=function() return ZERO_DPS end,
        currentDpsHash=function() return "1,0,0,0,0,0,0,0" end,
        catalogToken=function() return "catalog" end,
        buildCandidateSnapshot=function() return {complete=true,candidates={}} end,
        snapshotCurrent=function() return true end,
        bucketClaimable=function() return true end,
        backpressured=function() return false end,
        catalogGet=function() return nil end,
        prepareBuild=function() return nil end,
        admitBuild=function() return false end,
        sendNextBuild=function() return 0,true,true,false end,
        sendDpsBucket=function()
            calls = calls + 1
            return true,true,1,false,true,nil,1,16,1
        end,
        publishLoadoutClaim=function() return true end,
        publishBucketClaim=function() return true end,
        supportsRequestContext=function() return true end,
        localOwnsDpsBucket=function() return false end,
        outstandingTransfers=function() return 0 end,
        cancelRequest=function() return true end,
        noteSyncStat=function() end,log=function() end,
    })
    assert(reconciler.ScheduleRequest({requester=REQUESTER,
        requestId="c1-admission-32",peerBuildHash=ZERO_DPS,
        peerDpsHash=ZERO_DPS}))
    for _ = 1, 40 do
        current = current + 0.1
        reconciler.Process(0.1)
    end
    return calls, reconciler.Stats(), reconciler.Counts()
end

local function PrepareResponse(sync)
    for _ = 1, 20 do
        Pump(sync, 1)
        if (sync.ResponseStats().entryPreparations or 0) > 0 then
            return true
        end
    end
    return false
end

-- Run responders in the exact deterministic D-bucket order. Each responder
-- prepares through the real Sync owner, then receives every already-emitted
-- encoded WLRC/WLBC claim through the real SyncInbound path before its bucket
-- delay elapses. The first completed response therefore has the same chance to
-- suppress later equivalent work that it has on the live shared channel.
local function RunCohort(names)
    local claimBus, claimSeen = {}, {}
    local result = {
        responders=0,chunks=0,claims=0,directSent=false,relaySent=false,
    }
    for _, name in ipairs(names) do
        local peerSync = Boot(name, DeepCopy(seedDb))
        local buildHash, dpsHash = peerSync.GetCompatibilityHashes()
        assert(buildHash == seedBuildHash and dpsHash == seedDpsHash,
            "equivalent responder hashes drifted")
        local request = table.concat({
            "WLRQ", REQUESTER, buildHash, ZERO_DPS, REQUEST_ID,
        }, "|")
        assert(peerSync.HandleIncoming(request, REQUESTER),
            "encoded mismatch request was rejected")
        assert(PrepareResponse(peerSync),
            "responder did not reach deterministic preparation")
        for _, claim in ipairs(claimBus) do
            local sender = assert(ClaimSender(claim),
                "captured claim lost its sender")
            if sender ~= name then
                -- Current red rejects D-bucket suppression. The future green
                -- must admit whichever established claim form owns the bound.
                peerSync.HandleIncoming(claim, sender)
            end
        end
        Pump(peerSync, 160)
        local transfers, chunks = TransferStats(H.sentChatMessages)
        if transfers > 0 then
            result.responders = result.responders + 1
            result.chunks = result.chunks + chunks
            if name == owner then
                result.directSent = true
            else
                result.relaySent = true
            end
        end
        for _, item in ipairs(H.sentChatMessages) do
            local wire = WireText(item.text)
            if MatchingClaim(wire) and not claimSeen[wire] then
                claimSeen[wire] = true
                claimBus[#claimBus + 1] = wire
            end
        end
        result.lastResponseStats = peerSync.ResponseStats()
        result.lastOutboundStats = Nexus.DpsCapture.OutboundStats()
        result.lastWork = peerSync.WorkState()
    end
    result.claims = #claimBus
    return result
end

-- Green controls: the actual named owner still creates a WLD2 transfer, and
-- one peer holding directly verified origin evidence can still relay it when
-- the owner is absent. An unverified relay remains fail-closed.
local direct = RunCohort({owner})
assert(direct.responders == 1 and direct.directSent,
    string.format("direct-owner DPS response path was not preserved: responders=%d chunks=%d claims=%d dpsSerial=%s considered=%s direct=%s pending=%s",
        direct.responders, direct.chunks, direct.claims,
        tostring(direct.lastResponseStats and direct.lastResponseStats.dpsSerializations),
        tostring(direct.lastOutboundStats and direct.lastOutboundStats.considered),
        tostring(direct.lastOutboundStats and direct.lastOutboundStats.offered_direct),
        tostring(direct.lastWork and direct.lastWork.reconciliation and direct.lastWork.reconciliation.responses)))

local authorizedRelay = RunCohort({"AuthorizedRelay"})
assert(authorizedRelay.responders == 1 and authorizedRelay.relaySent,
    "authorized response-only DPS relay path was not preserved")

Sync = Boot("UnverifiedRelay", DeepCopy(seedDb))
local rejected, rejectWhy = Sync.BroadcastDpsRecord(
    verboseRecord, nil, true, {
        requester=REQUESTER,requestId="unverified-control",bucket=dpsBucket,
    }, {chunks=64,bytes=16384,seconds=75,transfers=8})
assert(rejected == false and rejectWhy == "relay_authorization",
    "unverified relay crossed the response-only authorization boundary")

-- A caller-supplied origin hint is not durable owner evidence. In particular,
-- it cannot override an explicit unverified verdict on the public relay seam.
Sync = Boot("ForgeryRelay", DeepCopy(seedDb))
local forged = DeepCopy(verboseRecord)
forged.ownerVerified = false
forged._originVerified = true
local forgedRejected, forgedWhy = Sync.BroadcastDpsRecord(
    forged, nil, true, {
        requester=REQUESTER,requestId="c1-forged-relay",bucket=dpsBucket,
    }, {chunks=64,bytes=16384,seconds=75,transfers=8})
assert(forgedRejected == false and forgedWhy == "relay_authorization",
    "EXPECTED RED: caller-supplied DPS origin hint overrode unverified authority")

-- Prepared response bytes are only a private serialization cache. A caller
-- cannot manufacture the cache object, nor can an earlier verified response
-- survive an explicit authority revocation on the supplied durable record.
local preparedContext = {
    requester=REQUESTER,requestId="c1-forged-prepared",bucket=dpsBucket,
}
local forgedPayload = {
    v=7,f=fingerprint,h=loadoutHash,e=echoes,c="dummy",
    d=verboseRecord.dps,u=verboseRecord.duration,t=verboseRecord.ts,
    p=verboseRecord.player,l=verboseRecord.level,k=verboseRecord.class,
    o=verboseRecord.ownerKey,r=verboseRecord.realm,
    x={n=preparedContext.requester,i=preparedContext.requestId,
        b=preparedContext.bucket},
}
local callerPrepared = {
    messages={"WLD2|ForgeryRelay|forged:1:1|1/1|forged"},
    payload=forgedPayload,context=preparedContext,originVerified=true,
}
local preparedRejected, preparedWhy = Sync.BroadcastDpsRecord(
    nil, callerPrepared, true, nil,
    {chunks=64,bytes=16384,seconds=75,transfers=8})
assert(preparedRejected == false and preparedWhy == "relay_authorization",
    "EXPECTED RED: caller-built prepared DPS cache bypassed durable authority")

local revocable = DeepCopy(verboseRecord)
revocable.ownerVerified = true
revocable._originVerified = true
local messageDeferred, messageDeferredWhy, messagePrepared =
    Sync.BroadcastDpsRecord(revocable, nil, true, preparedContext,
        {chunks=0,bytes=0,seconds=0,transfers=0})
assert(messageDeferred == false
    and messageDeferredWhy == "response wire budget"
    and type(messagePrepared) == "table",
    "verified relay did not expose its private prepared cache for integrity testing")
messagePrepared.messages[1] = "WLD2|ForgeryRelay|swapped:1:1|1/1|swapped"
local swappedAdmitted, swappedWhy = Sync.BroadcastDpsRecord(
    revocable, messagePrepared, true, preparedContext,
    {chunks=64,bytes=16384,seconds=75,transfers=8})
assert(swappedAdmitted == false and swappedWhy == "relay_authorization",
    "EXPECTED RED: prepared DPS cache admitted substituted wire bytes")

local firstPrepared, firstPreparedWhy, retainedPrepared =
    Sync.BroadcastDpsRecord(revocable, nil, true, preparedContext,
        {chunks=0,bytes=0,seconds=0,transfers=0})
assert(firstPrepared == false and firstPreparedWhy == "response wire budget"
    and type(retainedPrepared) == "table",
    "verified relay did not reach the prepared-response deferral boundary")
revocable.ownerVerified = false
revocable._originVerified = false
local revokedAdmitted, revokedWhy = Sync.BroadcastDpsRecord(
    revocable, retainedPrepared, true, preparedContext,
    {chunks=64,bytes=16384,seconds=75,transfers=8})
assert(revokedAdmitted == false and revokedWhy == "relay_authorization",
    "EXPECTED RED: prepared DPS cache restored revoked owner authority")

local retryableRelay = DeepCopy(verboseRecord)
retryableRelay.ownerVerified = true
retryableRelay._originVerified = true
local relayDeferred, relayDeferredWhy, relayPrepared =
    Sync.BroadcastDpsRecord(retryableRelay, nil, true, preparedContext,
        {chunks=0,bytes=0,seconds=0,transfers=0})
assert(relayDeferred == false and relayDeferredWhy == "response wire budget"
    and type(relayPrepared) == "table",
    "verified relay did not expose a retryable prepared response")
local relayRetried, relayRetryWhy = Sync.BroadcastDpsRecord(
    retryableRelay, relayPrepared, true, preparedContext,
    {chunks=64,bytes=16384,seconds=75,transfers=8})
assert(relayRetried == true and relayRetryWhy == nil,
    "verified relay could not reuse its unchanged prepared response")

local costDeferred, costDeferredWhy, costPrepared =
    Sync.BroadcastDpsRecord(retryableRelay, nil, true, preparedContext,
        {chunks=0,bytes=0,seconds=0,transfers=0})
assert(costDeferred == false and costDeferredWhy == "response wire budget"
    and type(costPrepared) == "table",
    "verified relay did not expose a prepared cost-control response")
costPrepared.wireCost = {chunks=0,bytes=0,seconds=0,transfers=0}
local costBypassed, costBypassWhy = Sync.BroadcastDpsRecord(
    retryableRelay, costPrepared, true, preparedContext,
    {chunks=0,bytes=0,seconds=0,transfers=0})
assert(costBypassed == false and costBypassWhy == "response wire budget",
    "EXPECTED RED: prepared DPS cache bypassed its wire budget")

local durableRows = NexusDB.dpsCapture.characterBest.dummy
local durableRecord = durableRows[verboseRecord.ownerKey]
assert(type(durableRecord) == "table",
    "prepared-response fixture could not locate its durable owner row")
local Catalog = Nexus.BuildCatalog
local function PutRelatedBuild(id)
    assert(Catalog.Put({
        id=id,title=id,author=owner,ownerKey=verboseRecord.ownerKey,
        ownerVerified=true,realm=verboseRecord.realm,isMine=false,
        class="MAGE",postedAt=49000,lastModified=49000,
        echoes=DeepCopy(echoes),fingerprint=fingerprint,
    }), "prepared-response relation fixture could not store " .. id)
end
local relationA = "fanout-prepared-relation-a"
local relationB = "fanout-prepared-relation-b"
PutRelatedBuild(relationA)
PutRelatedBuild(relationB)
local originalBuildId = durableRecord.buildId
durableRecord.buildId = relationA
local relationRecord = DeepCopy(retryableRelay)
relationRecord.buildId = relationA
local relationDeferred, relationDeferredWhy, relationPrepared =
    Sync.BroadcastDpsRecord(relationRecord, nil, true, preparedContext,
        {chunks=0,bytes=0,seconds=0,transfers=0})
assert(relationDeferred == false
    and relationDeferredWhy == "response wire budget"
    and type(relationPrepared) == "table"
    and relationPrepared.payload.b == relationA,
    "verified relation did not reach prepared-response deferral")
durableRecord.buildId = relationB
local staleRelationSent, staleRelationWhy = Sync.BroadcastDpsRecord(
    relationRecord, relationPrepared, true, preparedContext,
    {chunks=64,bytes=16384,seconds=75,transfers=8})
assert(staleRelationSent == false and staleRelationWhy == "stale prepared DPS",
    "EXPECTED RED: prepared DPS cache retained a stale build association")
durableRecord.buildId = originalBuildId

local lockedA = {{spellId=360399,count=1}}
local lockedB = {{spellId=360399,count=2}}
local originalLocked = durableRecord.lockedEchoes
durableRecord.lockedEchoes = DeepCopy(lockedA)
local lockedRecord = DeepCopy(retryableRelay)
lockedRecord.lockedEchoes = DeepCopy(lockedA)
local lockedDeferred, lockedDeferredWhy, lockedPrepared =
    Sync.BroadcastDpsRecord(lockedRecord, nil, true, preparedContext,
        {chunks=0,bytes=0,seconds=0,transfers=0})
assert(lockedDeferred == false and lockedDeferredWhy == "response wire budget"
    and type(lockedPrepared) == "table",
    "locked-evidence response did not reach prepared deferral")
durableRecord.lockedEchoes = DeepCopy(lockedB)
local staleLockedSent, staleLockedWhy = Sync.BroadcastDpsRecord(
    lockedRecord, lockedPrepared, true, preparedContext,
    {chunks=64,bytes=16384,seconds=75,transfers=8})
assert(staleLockedSent == false and staleLockedWhy == "stale prepared DPS",
    "EXPECTED RED: prepared DPS cache retained stale locked evidence")
durableRecord.lockedEchoes = originalLocked

durableRecord.buildId = relationA
durableRecord.ownerVerified = true
local removedRecord = DeepCopy(retryableRelay)
removedRecord.buildId = relationA
local removedDeferred, removedDeferredWhy, removedPrepared =
    Sync.BroadcastDpsRecord(removedRecord, nil, true, preparedContext,
        {chunks=0,bytes=0,seconds=0,transfers=0})
assert(removedDeferred == false
    and removedDeferredWhy == "response wire budget"
    and type(removedPrepared) == "table"
    and removedPrepared.payload.b == relationA,
    "removal control did not reach prepared-response deferral")
durableRecord.ownerVerified = false
assert(Catalog.RemoveOverlay(relationA),
    "removal control could not remove the prepared relation")
local removedRetried, removedRetryWhy = Sync.BroadcastDpsRecord(
    removedRecord, removedPrepared, true, preparedContext,
    {chunks=64,bytes=16384,seconds=75,transfers=8})
assert(removedRetried == false and removedRetryWhy == "stale prepared DPS",
    "EXPECTED RED: invalid relation rebuilt from a stale caller DPS record")
durableRecord.ownerVerified = true
durableRecord.buildId = originalBuildId

Sync = Boot(owner, DeepCopy(seedDb))
local retryableDirect = DeepCopy(verboseRecord)
retryableDirect.ownerVerified = true
local directDeferred, directDeferredWhy, directPrepared =
    Sync.BroadcastDpsRecord(retryableDirect, nil, true, nil,
        {chunks=0,bytes=0,seconds=0,transfers=0})
assert(directDeferred == false and directDeferredWhy == "response wire budget"
    and type(directPrepared) == "table",
    "direct owner did not expose a retryable prepared response")
local directRetried, directRetryWhy = Sync.BroadcastDpsRecord(
    retryableDirect, directPrepared, true, nil,
    {chunks=64,bytes=16384,seconds=75,transfers=8})
assert(directRetried == true and directRetryWhy == nil,
    "direct owner could not reuse its unchanged prepared response")

local directContextA = {
    requester=REQUESTER,requestId="c1-direct-prepared-a",bucket=dpsBucket,
}
local directContextB = {
    requester=REQUESTER,requestId="c1-direct-prepared-b",bucket=dpsBucket,
}
local contextDeferred, contextDeferredWhy, contextPrepared =
    Sync.BroadcastDpsRecord(retryableDirect, nil, true, directContextA,
        {chunks=0,bytes=0,seconds=0,transfers=0})
assert(contextDeferred == false
    and contextDeferredWhy == "response wire budget"
    and type(contextPrepared) == "table",
    "direct response did not expose its context-bound prepared cache")
local changedContextSent, changedContextWhy = Sync.BroadcastDpsRecord(
    retryableDirect, contextPrepared, true, directContextB,
    {chunks=64,bytes=16384,seconds=75,transfers=8})
assert(changedContextSent == false and changedContextWhy == "relay_authorization",
    "EXPECTED RED: direct prepared DPS cache changed response association")
local exactContextSent, exactContextWhy = Sync.BroadcastDpsRecord(
    retryableDirect, contextPrepared, true, directContextA,
    {chunks=64,bytes=16384,seconds=75,transfers=8})
assert(exactContextSent == true and exactContextWhy == nil,
    "direct prepared DPS cache rejected its exact response association")

local responseDeferred, responseDeferredWhy, responsePrepared =
    Sync.BroadcastDpsRecord(retryableDirect, nil, true, directContextA,
        {chunks=0,bytes=0,seconds=0,transfers=0})
assert(responseDeferred == false
    and responseDeferredWhy == "response wire budget"
    and type(responsePrepared) == "table",
    "direct response did not expose its mode-bound prepared cache")
local responseBecameDirect, responseBecameDirectWhy = Sync.BroadcastDpsRecord(
    retryableDirect, responsePrepared, false, nil,
    {chunks=64,bytes=16384,seconds=75,transfers=8})
assert(responseBecameDirect == false
    and responseBecameDirectWhy == "relay_authorization",
    "EXPECTED RED: response prepared DPS cache became a direct broadcast")

local broadcastDeferred, broadcastDeferredWhy, broadcastPrepared =
    Sync.BroadcastDpsRecord(retryableDirect, nil, false, nil,
        {chunks=0,bytes=0,seconds=0,transfers=0})
assert(broadcastDeferred == false
    and broadcastDeferredWhy == "response wire budget"
    and type(broadcastPrepared) == "table",
    "direct broadcast did not expose its mode-bound prepared cache")
local broadcastBecameResponse, broadcastBecameResponseWhy =
    Sync.BroadcastDpsRecord(retryableDirect, broadcastPrepared, true,
        directContextA,
        {chunks=64,bytes=16384,seconds=75,transfers=8})
assert(broadcastBecameResponse == false
    and broadcastBecameResponseWhy == "relay_authorization",
    "EXPECTED RED: direct prepared DPS cache became a response")

-- The ranked seed can move to another bucket when its player identity changes.
-- Reorder the final cohorts by the exact final bucket delay, and explicitly
-- retain the direct owner in both populations.
table.sort(peerNames, function(left, right)
    local prefix = REQUESTER .. ":" .. REQUEST_ID .. ":D:"
        .. tostring(dpsBucket) .. ":"
    local leftRank = StableOrdinal(prefix .. left)
    local rightRank = StableOrdinal(prefix .. right)
    if leftRank == rightRank then return left < right end
    return leftRank < rightRank
end)
local smallNames, largeNames = {owner}, {}
for _, name in ipairs(peerNames) do
    largeNames[#largeNames + 1] = name
    if name ~= owner and #smallNames < 4 then
        smallNames[#smallNames + 1] = name
    end
end
table.sort(smallNames, function(left, right)
    local prefix = REQUESTER .. ":" .. REQUEST_ID .. ":D:"
        .. tostring(dpsBucket) .. ":"
    local leftRank = StableOrdinal(prefix .. left)
    local rightRank = StableOrdinal(prefix .. right)
    if leftRank == rightRank then return left < right end
    return leftRank < rightRank
end)
local small = RunCohort(smallNames)
local large = RunCohort(largeNames)
local relayFirst = RunCohort({"AuthorizedRelay", owner, "SecondRelay"})

local function FindCollidingOwners(dpsModule)
    local byBucket = {}
    for index = 1, 200 do
        local name = string.format("DpsOwner%03d", index)
        local bucket = assert(dpsModule.SyncBucket("dummy", name))
        if byBucket[bucket] then return byBucket[bucket], name, bucket end
        byBucket[bucket] = name
    end
    error("could not find two deterministic DPS owners in one bucket")
end

local function CompactRecord(dpsModule, player, spellId, score, stamp)
    local recordEchoes = {{spellId=spellId,stacks=1}}
    return {
        v=7,f=dpsModule.GetEchoKey(recordEchoes),
        h=dpsModule.GetEchoHash(recordEchoes),e=recordEchoes,c="dummy",
        d=score,u=65,t=stamp,p=player,l=80,k="MAGE",
        o=player:lower() .. "@ebonhold",r="ebonhold",
    }
end

local function SeedRecordSet(localName, records)
    local seedSync, seedDps = Boot(localName, {
        communityBuilds={},syncTombstones={},dpsCapture={},
    })
    for _, item in ipairs(records) do
        local sender = item.verified
            and (item.record.p .. "-Ebonhold") or nil
        assert(seedDps.ReceiveRecord(item.record, sender),
            "multi-record seed was rejected")
    end
    local buildHash, dpsHash = seedSync.GetCompatibilityHashes()
    return DeepCopy(NexusDB), buildHash, dpsHash
end

local ownerA, ownerB, sharedBucket = FindCollidingOwners(DPS)
local recordA = CompactRecord(DPS, ownerA, 360311, 36031000, 49001)
local recordB = CompactRecord(DPS, ownerB, 360312, 36032000, 49002)
local verifiedDb, verifiedBuildHash, verifiedDpsHash = SeedRecordSet(ownerA, {
    {record=recordA,verified=true}, {record=recordB,verified=true},
})
local actualSharedBucket = assert(NonzeroBucket(verifiedDpsHash),
    "multi-record seed did not occupy a DPS bucket")
assert(actualSharedBucket == sharedBucket,
    "two colliding records did not remain in their expected bucket")

local relayNames = {}
for index = 1, 20 do
    relayNames[index] = string.format("ConcurrentRelay%03d", index)
end
local ownersSmall = {ownerA, ownerB, relayNames[1], relayNames[2]}
local ownersLarge = {ownerA, ownerB}
for _, name in ipairs(relayNames) do ownersLarge[#ownersLarge + 1] = name end
while #ownersLarge > 20 do table.remove(ownersLarge) end
local relaySmall = {relayNames[1],relayNames[2],relayNames[3],relayNames[4]}

local concurrentOwnersSmall = ConcurrentCohort(ownersSmall, verifiedDb,
    verifiedBuildHash, verifiedDpsHash, "c1-fanout-owners-4",
    sharedBucket, 220)
local concurrentOwnersLarge = ConcurrentCohort(ownersLarge, verifiedDb,
    verifiedBuildHash, verifiedDpsHash, "c1-fanout-owners-20",
    sharedBucket, 220)
local concurrentRelaySmall = ConcurrentCohort(relaySmall, verifiedDb,
    verifiedBuildHash, verifiedDpsHash, "c1-fanout-relay-4",
    sharedBucket, 220)
local concurrentRelayLarge = ConcurrentCohort(relayNames, verifiedDb,
    verifiedBuildHash, verifiedDpsHash, "c1-fanout-relay-20",
    sharedBucket, 220)

local function PeerDebug(result, name)
    local response = result.responseStats[name] or {}
    local work = result.work[name] or {}
    return string.format("admit=%s progress=%s claims=%s pending=%s sending=%s codes=%s/%s/%s sample=%s",
        tostring(response.dpsAdmissions),
        tostring(response.successfulProgress),
        tostring(response.responseClaims),
        tostring(work.pendingResponses), tostring(work.sending),
        tostring(result.codes.WLD2), tostring(result.codes.WLBC),
        tostring(result.codes.WLRC), tostring(result.firstBucketClaim))
end

-- A relay that cannot authenticate every represented row must never publish a
-- whole-bucket claim. Otherwise its partial response can suppress a later peer
-- that holds direct evidence for the row this relay correctly refused.
local mixedDb, mixedBuildHash, mixedDpsHash = SeedRecordSet("MixedSeeder", {
    {record=recordA,verified=true}, {record=recordB,verified=false},
})
assert(mixedDpsHash == verifiedDpsHash,
    "verification provenance changed the represented DPS digest")
local mixed = ConcurrentCohort({"MixedRelay"}, mixedDb,
    mixedBuildHash, mixedDpsHash, "c1-fanout-mixed",
    sharedBucket, 220)
local backpressure = BackpressureResumeControl("PressureRelay", verifiedDb,
    verifiedBuildHash, verifiedDpsHash, "c1-fanout-pressure",
    sharedBucket)
local admissionCalls, admissionStats, admissionCounts =
    AdmissionBoundaryControl()

-- Direct plus at most one authorized relay is a fixed conservative bound. The
-- exact winner remains owned by the existing deterministic claim/fairness
-- machinery; this test introduces no new message code, rate, or queue cap.
local responseBound = 2
local perResponseChunks = math.max(direct.chunks, authorizedRelay.chunks)
local failures = {}
local function Expect(name, condition, detail)
    if not condition then failures[#failures + 1] = name .. ": " .. detail end
end

Expect("equivalent_dps_small_cohort_is_fixed_bound",
    small.responders <= responseBound
        and small.chunks <= perResponseChunks * responseBound,
    string.format("responders=%d chunks=%d claims=%d bound=%d/%d",
        small.responders, small.chunks, small.claims,
        responseBound, perResponseChunks * responseBound))
Expect("equivalent_dps_large_cohort_is_fixed_bound",
    large.responders <= responseBound
        and large.chunks <= perResponseChunks * responseBound,
    string.format("responders=%d chunks=%d claims=%d bound=%d/%d",
        large.responders, large.chunks, large.claims,
        responseBound, perResponseChunks * responseBound))
Expect("relay_first_never_suppresses_direct_owner",
    relayFirst.responders <= responseBound
        and relayFirst.directSent and relayFirst.relaySent
        and relayFirst.chunks <= perResponseChunks * responseBound,
    string.format("responders=%d chunks=%d claims=%d direct=%s relay=%s",
        relayFirst.responders, relayFirst.chunks, relayFirst.claims,
        tostring(relayFirst.directSent), tostring(relayFirst.relaySent)))

local concurrentBound = 3 -- two direct owners plus at most one relay
local concurrentTransferBound = 2 * concurrentBound
Expect("concurrent_two_owner_small_cohort_is_fixed_bound",
    concurrentOwnersSmall.responders <= concurrentBound
        and concurrentOwnersSmall.transfers <= concurrentTransferBound,
    string.format("responders=%d transfers=%d chunks=%d claims=%d bound=%d/%d",
        concurrentOwnersSmall.responders, concurrentOwnersSmall.transfers,
        concurrentOwnersSmall.chunks, concurrentOwnersSmall.claims,
        concurrentBound, concurrentTransferBound))
Expect("concurrent_two_owner_large_cohort_is_fixed_bound",
    concurrentOwnersLarge.responders <= concurrentBound
        and concurrentOwnersLarge.transfers <= concurrentTransferBound,
    string.format("responders=%d transfers=%d chunks=%d claims=%d bound=%d/%d",
        concurrentOwnersLarge.responders, concurrentOwnersLarge.transfers,
        concurrentOwnersLarge.chunks, concurrentOwnersLarge.claims,
        concurrentBound, concurrentTransferBound))
Expect("concurrent_direct_owners_are_never_suppressed",
    concurrentOwnersSmall.directSenders[ownerA]
        and concurrentOwnersSmall.directSenders[ownerB]
        and concurrentOwnersLarge.directSenders[ownerA]
        and concurrentOwnersLarge.directSenders[ownerB],
    string.format("small=%s/%s large=%s/%s",
        tostring(concurrentOwnersSmall.directSenders[ownerA]),
        tostring(concurrentOwnersSmall.directSenders[ownerB]),
        tostring(concurrentOwnersLarge.directSenders[ownerA]),
        tostring(concurrentOwnersLarge.directSenders[ownerB])))
Expect("concurrent_relay_only_small_cohort_has_one_responder",
    concurrentRelaySmall.responders == 1
        and concurrentRelaySmall.transfers == 2,
    string.format("responders=%d transfers=%d chunks=%d claims=%d first={%s}",
        concurrentRelaySmall.responders, concurrentRelaySmall.transfers,
        concurrentRelaySmall.chunks, concurrentRelaySmall.claims,
        PeerDebug(concurrentRelaySmall, relaySmall[1])))
Expect("concurrent_relay_only_large_cohort_has_one_responder",
    concurrentRelayLarge.responders == 1
        and concurrentRelayLarge.transfers == 2,
    string.format("responders=%d transfers=%d chunks=%d claims=%d",
        concurrentRelayLarge.responders, concurrentRelayLarge.transfers,
        concurrentRelayLarge.chunks, concurrentRelayLarge.claims))
Expect("mixed_verified_unverified_never_claims_partial_bucket",
    mixed.transfers == 1 and mixed.claims == 0
        and mixed.electionClaims == 0,
    string.format("responders=%d transfers=%d chunks=%d claims=%d/%d",
        mixed.responders, mixed.transfers, mixed.chunks, mixed.claims,
        mixed.electionClaims))
Expect("backpressure_defers_without_preparing_or_claiming",
    backpressure.blockedQueue >= backpressure.fill - 1
        and backpressure.blockedWork == backpressure.beforeWork
        and backpressure.blockedBuild == backpressure.beforeBuild
        and backpressure.deferrals > 0,
    string.format("fill=%d blocked=%d work=%d/%d chunks=%d/%d deferrals=%d",
        backpressure.fill, backpressure.blockedQueue,
        backpressure.beforeWork, backpressure.blockedWork,
        backpressure.beforeBuild, backpressure.blockedBuild,
        backpressure.deferrals))
Expect("backpressured_request_resumes_once_pressure_clears",
    backpressure.transfers == 2 and backpressure.claims == 1
        and (backpressure.final.dpsAdmissions or 0) == 2,
    string.format("transfers=%d chunks=%d claims=%d admissions=%s",
        backpressure.transfers, backpressure.chunks, backpressure.claims,
        tostring(backpressure.final.dpsAdmissions)))
Expect("response_admission_boundary_is_exactly_32",
    admissionCalls == 32 and admissionStats.quotaYields == 1
        and admissionCounts.responses == 0,
    string.format("calls=%d quotaYields=%s pending=%s",
        admissionCalls, tostring(admissionStats.quotaYields),
        tostring(admissionCounts.responses)))

assert(small.directSent and large.directSent,
    "fanout suppression removed the deterministic direct owner")

local controls = string.format(
    "controls direct=1 relay=1 unverified=refused serialized=%d/%d relay_first=%d direct_owners=yes mixed=%d/%d/%d pressure=%d/%d admissions=%d",
    small.responders, large.responders, relayFirst.responders,
    mixed.transfers, mixed.claims, mixed.electionClaims,
    backpressure.transfers, backpressure.claims, admissionCalls)
if #failures > 0 then
    error("EXPECTED RED: Stage 36.3 DPS fanout bound:\n - "
        .. table.concat(failures, "\n - ") .. "\n" .. controls)
end

print(string.format(
    "DPS fanout bound: peers=4/%d responders=%d/%d concurrent_owners=%d/%d owner_bound=%d concurrent_relays=%d/%d relay_bound=1 %s -- OK",
    #largeNames, small.responders, large.responders,
    concurrentOwnersSmall.responders, concurrentOwnersLarge.responders,
    concurrentBound, concurrentRelaySmall.responders,
    concurrentRelayLarge.responders, controls))
