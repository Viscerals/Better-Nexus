-- Stage 28.5 expected red: mixed legacy/current DPS rows must have one
-- sanitized convergence outcome, and Peer Test must describe its peer field as
-- an observation filter rather than directed transport.
local H = dofile("tests/harness.lua")

local clock, actor = 1000, "LocalOwner"
GetTime = function() return clock end
time = function() return 50000 end
UnitName = function() return actor end
UnitLevel = function() return 80 end
UnitClass = function() return "Mage", "MAGE" end
GetNormalizedRealmName = function() return "Ebonhold" end

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

local Sync, DPS = Nexus.Sync, Nexus.DpsCapture
NexusDB = {communityBuilds={},syncTombstones={},dpsCapture={}}
Sync.Init(Nexus.Codec, {})
DPS.Init({}, Sync)

local failures = {}
local function Check(ok, message)
    if not ok then failures[#failures + 1] = message end
end

local echoes = {{spellId=410001,stacks=1}}
local fingerprint = DPS.GetEchoKey(echoes)
local loadoutHash = DPS.GetEchoHash(echoes)
local baseRecord = {
    protocolVersion=7,fingerprint=fingerprint,loadoutHash=loadoutHash,
    echoes=echoes,category="dummy",dps=250000,duration=30,ts=40000,
    player="LocalOwner",level=80,class="MAGE",
}
local function Variant(changes)
    local out = {}
    for key, value in pairs(baseRecord) do out[key] = value end
    for key, value in pairs(changes or {}) do out[key] = value end
    return out
end
local function CheckOutboundReason(expected, changes, responseMode, context)
    local admitted, reason = Sync.BroadcastDpsRecord(
        Variant(changes), nil, responseMode, context)
    Check(admitted == false and reason == expected, string.format(
        "outbound %s boundary was not classified (got %s)",
        expected, tostring(reason)))
end

-- These are all terminal record decisions, not queue-pressure deferrals.
CheckOutboundReason("duration", {duration=29})
CheckOutboundReason("invalid_category", {category="other"})
CheckOutboundReason("schema", {level=0})
CheckOutboundReason("owner_sender", {player="RemoteOwner"})
CheckOutboundReason("relay_authorization", {
    player="RemoteRelay",_originVerified=false,
}, true, {requester="Requester",requestId="diagnostic",bucket=1})
CheckOutboundReason("outside_request", {
    player="RemoteOutside",_originVerified=true,
}, true, nil)
CheckOutboundReason("integrity", {fingerprint="different"})
local firstDirect, firstWhy = Sync.BroadcastDpsRecord(Variant())
local duplicateDirect, duplicateWhy = Sync.BroadcastDpsRecord(Variant())
Check(firstDirect == true and firstWhy == nil
        and duplicateDirect == true and duplicateWhy == "duplicate",
    "equivalent outbound transfer did not report duplicate suppression")

local function StoredRow(player, duration, score, verified)
    return {
        fingerprint=fingerprint,loadoutHash=loadoutHash,echoes=echoes,
        category="dummy",dps=score,duration=duration,ts=30000,
        player=player,level=80,class="MAGE",ownerVerified=verified,
    }
end

-- The responder fixture deliberately includes current owner evidence, verified
-- relay evidence, legacy duration/score rows, and every terminal admission
-- boundary that can occur after an otherwise eligible row is selected.
NexusDB = {communityBuilds={},syncTombstones={},dpsCapture={
    characterBest={dummy={
        direct=StoredRow("LocalOwner",30,250001,true),
        relay=StoredRow("RemoteRelay",30,250002,true),
        schema=StoredRow("BadSchema",30,250003,true),
        owner=StoredRow("BadOwner",30,250004,true),
        authority=StoredRow("BadAuthority",30,250005,false),
        integrity=StoredRow("BadIntegrity",30,250006,true),
        outside=StoredRow("BadOutside",30,250007,true),
        duplicate=StoredRow("Duplicate",30,250008,true),
        legacyduration=StoredRow("LegacyDuration",29,250009,true),
        legacyscore=StoredRow("LegacyScore",30,0,true),
    },lk={}},personalBest={},buildBest={},
}}
local terminalReasons = {
    BadSchema="schema",BadOwner="owner_sender",
    BadAuthority="relay_authorization",BadIntegrity="integrity",
    BadOutside="outside_request",Duplicate="duplicate_not_better",
}
local deferAll = false
local responder = {
    BroadcastDpsRecord=function(record)
        if deferAll then return false, "sync queue full" end
        local reason = terminalReasons[record.player]
        if reason == "relay_authorization"
            and record._originVerified == true then reason = nil end
        if reason then return false, reason end
        return true
    end,
}
DPS.Init({}, responder)
local digestBefore = DPS.GetSyncHash()
local cache = DPS.HashCacheStats()
Check(cache.storedRows == 10 and cache.rows == 8
        and cache.durationIneligibleRows == 1
        and cache.scoreIneligibleRows == 1,
    "hash cache did not distinguish stored, eligible, duration, and score rows")

local progress = {}
local offered, complete = DPS.BroadcastAllBuildBests(
    nil, nil, progress, 100, {
        requester="Requester",requestId="mixed-current",bucket=1,
    })
Check(complete == true and offered == 2,
    "mixed responder fixture did not admit exactly direct plus verified relay")

local outbound = type(DPS.OutboundStats) == "function"
    and DPS.OutboundStats() or {}
local expectedOutbound = {
    considered=10,eligible=8,offered_direct=1,offered_relay=1,
    duration=1,score=1,schema=1,owner_sender=1,
    relay_authorization=1,integrity=1,outside_request=1,
    duplicate_not_better=1,
}
for key, expected in pairs(expectedOutbound) do
    Check(outbound[key] == expected, string.format(
        "mixed outbound counter %s expected %d got %s",
        key, expected, tostring(outbound[key])))
end
local terminalTotal = 0
for _, key in ipairs({"offered_direct","offered_relay","peer_current",
        "outside_bucket","score","duration","owner_sender",
        "relay_authorization","schema","stale_record",
        "duplicate_not_better","invalid_category","integrity",
        "outside_request","other"}) do
    terminalTotal = terminalTotal + (tonumber(outbound[key]) or 0)
end
Check(outbound.considered == terminalTotal,
    "outbound terminal counters do not sum to considered rows")
local outboundShape = 0
for key, value in pairs(outbound) do
    outboundShape = outboundShape + 1
    Check(type(key) == "string" and type(value) == "number",
        "outbound diagnostics retained non-scalar row data")
end
Check(outboundShape == 19,
    "outbound diagnostics changed their fixed scalar shape")
local consideredBeforeMutation = outbound.considered
outbound.considered = 999999
Check(DPS.OutboundStats().considered == consideredBeforeMutation,
    "outbound diagnostics did not return a defensive copy")

-- An exact digest match is still a bounded logical outbound decision. Explain
-- it from the warm scalar cache without walking the DPS store again.
local beforeExact = DPS.OutboundStats()
local walksBeforeExact = DPS.HashCacheStats().collectionWalks
local exactOffered, exactComplete = DPS.BroadcastAllBuildBests(
    digestBefore,nil,{},100,{
        requester="Requester",requestId="exact-current",bucket=1,
    })
local afterExact = DPS.OutboundStats()
Check(exactOffered == 0 and exactComplete == true
        and afterExact.peer_current - beforeExact.peer_current == cache.rows
        and afterExact.considered - beforeExact.considered == cache.rows
        and DPS.HashCacheStats().collectionWalks == walksBeforeExact,
    "exact digest match did not explain warm peer-current rows in O(1)")

-- Targeted bucket responses must distinguish rows omitted because the bucket
-- is outside the request from rows omitted because the peer already proved the
-- exact bucket digest.
local localBuckets = {}
for part in tostring(digestBefore):gmatch("([^,]+)") do
    localBuckets[#localBuckets + 1] = part
end
local selectedBucket = DPS.SyncBucket("dummy", "direct")
local peerBuckets, selectedRows = {}, 0
for index=1,#localBuckets do peerBuckets[index] = "peer-different" end
peerBuckets[selectedBucket] = localBuckets[selectedBucket]
for playerKey in pairs(NexusDB.dpsCapture.characterBest.dummy) do
    if DPS.SyncBucket("dummy", playerKey) == selectedBucket then
        selectedRows = selectedRows + 1
    end
end
local beforeScope = type(DPS.OutboundStats) == "function"
    and DPS.OutboundStats() or {}
local scopedOffered, scopedComplete = DPS.BroadcastAllBuildBests(
    table.concat(peerBuckets, ","), selectedBucket, {}, 100, {
        requester="Requester",requestId="mixed-current",bucket=selectedBucket,
    })
local afterScope = type(DPS.OutboundStats) == "function"
    and DPS.OutboundStats() or {}
Check(scopedComplete == true and scopedOffered == 0
        and (afterScope.peer_current or 0) - (beforeScope.peer_current or 0)
            == selectedRows
        and (afterScope.outside_bucket or 0)
            - (beforeScope.outside_bucket or 0) == 10 - selectedRows,
    "targeted response did not classify peer-current and outside-bucket rows")

-- Accepted input advances revision/digest exactly once; duplicate, stale, and
-- rejected inputs leave both projections stable while incrementing only their
-- bounded rejection reason.
local revisionKind = Nexus.Revisions.DPS_CHANGED
local revisionBefore = Nexus.Revisions.Get(revisionKind)
local inbound = {
    v=7,f=fingerprint,h=loadoutHash,e=echoes,c="dummy",d=350000,u=30,
    t=41000,p="Inbound",l=80,k="MAGE",
}
Check(DPS.ReceiveRecord(inbound,"Inbound") == true,
    "valid current inbound row was not accepted")
local revisionAccepted = Nexus.Revisions.Get(revisionKind)
local digestAccepted = DPS.GetSyncHash()
Check(revisionAccepted == revisionBefore + 1
        and digestAccepted ~= digestBefore,
    "accepted row did not advance one DPS revision and digest")
Check(DPS.ReceiveRecord(inbound,"Inbound") == false,
    "exact duplicate inbound row was not rejected")
local stale = Variant({
    v=7,protocolVersion=nil,f=fingerprint,h=loadoutHash,e=echoes,
    c="dummy",d=340000,u=30,t=40000,p="Inbound",l=80,k="MAGE",
    fingerprint=nil,loadoutHash=nil,echoes=nil,category=nil,dps=nil,
    duration=nil,ts=nil,player=nil,level=nil,class=nil,
})
Check(DPS.ReceiveRecord(stale,"Inbound") == false,
    "stale inbound row was not rejected")
Check(Nexus.Revisions.Get(revisionKind) == revisionAccepted
        and DPS.GetSyncHash() == digestAccepted,
    "duplicate or stale inbound row changed revision/digest state")
local rejects = DPS.RejectionStats()
Check(rejects.duplicate_not_better == 1 and rejects.stale_record == 1,
    "duplicate and stale inbound outcomes were not classified exactly once")
local acceptedCache = DPS.HashCacheStats()
Check(acceptedCache.storedRows == 11 and acceptedCache.rows == 9
        and acceptedCache.durationIneligibleRows == 1
        and acceptedCache.scoreIneligibleRows == 1,
    "targeted revision update desynchronized DPS cache classifications")
local published = DPS.GetDpsBoard("dummy")
Check(#published == 9,
    "publication projection disagreed with eligible stored DPS rows")

-- Peer Test is a read-only observer: the optional name filters peer-tagged
-- events, global transport events remain, and no line may imply routing.
Nexus.Sync = {
    WorkState=function() return {outbound=4,buildInflight=1,dpsInflight=1} end,
    Stats=function() return {sent=2,received=3,dpsRequestsReceived=1,
        dpsRelayOffered=2,dpsDirectAccepted=1,dpsRelayAccepted=1,
        dpsDirectRejected=1,dpsRelayRejected=1} end,
    ChannelName=function() return "wrbuildssync" end,
    ChannelIndex=function() return 1 end,
    IsConnected=function() return true end,
    IsReceiving=function() return true end,
    ReceiveTimeLeft=function() return 4 end,
}
Nexus.BuildHashCache = {Stats=function() return {
    initialized=true,buildRows=4,tombstoneRows=0,buckets=8,
    dirtyBuckets=0,digest="1,2,3,4,5,6,7,8",
} end}
Nexus.Leaderboard = {VirtualStats=function() return {
    publishedRows=6,displayedRows=5,
} end}
dofile("core/PeerDebug.lua")
local Peer = Nexus.PeerDebug
Check(Peer.Start("Peer-Realm") == true
        and Peer.Record("peer_event",{peer="Other",outcome="ignored"}) == false
        and Peer.Record("peer_event",{peer="Peer",outcome="included"}) == true
        and Peer.Record("global_event",{outcome="included"}) == true,
    "peer/global observation fixture did not retain the intended event scope")
local report = Peer.Report()
Check(report:find(
        "event_scope=observation peer_filter=Peer peer_events=filtered global_events=included routing=unchanged",
        1, true) ~= nil,
    "Peer Test does not explicitly distinguish filtering from routing")
Check(report:find(
        "counter_scope=addon_session event_history=peer_test_session",
        1, true) ~= nil,
    "Peer Test does not distinguish provider counters from retained history")
Check(report:find("dps_counts stored=11 hash_eligible=9 published_board=6 displayed_rows=5",1,true) ~= nil,
    "Peer Test does not distinguish stored DPS rows from hash-eligible rows")
Check(report:find("dps_local_ineligible duration=1 score=1 schema=0",1,true) ~= nil,
    "Peer Test does not explain locally ineligible DPS rows")
Check(report:find("dps_outbound",1,true)
        and report:find("duration=1",1,true)
        and report:find("owner_sender=1",1,true)
        and report:find("relay_auth=1",1,true)
        and report:find("duplicate=1",1,true),
    "Peer Test omits bounded responder-side DPS outcomes")
Check(report:find("peer=Other",1,true) == nil
        and report:find("global_event",1,true) ~= nil,
    "Peer Test target filter hid global state or retained a mismatched peer")

local viewer = assert(io.open("ui/LogViewer.lua","rb"))
local viewerText = viewer:read("*a")
viewer:close()
Check(viewerText:find('peerLabel:SetText("Peer event filter (optional)")',1,true),
    "Peer Test input label still implies a directed peer target")

-- A local revision can supersede an already-scanned response even when its
-- digest is unchanged. Its pending rows are classified in O(1) as stale before
-- the replacement snapshot proceeds; none disappear from the terminal
-- accounting invariant, and refreshed relay authority is used on retry.
deferAll = true
local staleProgress = {}
local beforeDeferred = DPS.OutboundStats()
local _, deferredComplete, _, deferredWhy = DPS.BroadcastAllBuildBests(
    nil,nil,staleProgress,100,{
        requester="Requester",requestId="stale-snapshot",bucket=1,
    })
local afterDeferred = DPS.OutboundStats()
local pendingRows = afterDeferred.eligible - beforeDeferred.eligible
Check(deferredComplete == false and deferredWhy == "sync queue full"
        and pendingRows == 9
        and afterDeferred.queue_deferred
            == beforeDeferred.queue_deferred + 1,
    "deferred response did not retain exactly its eligible pending rows")
NexusDB.dpsCapture.characterBest.dummy.badauthority.ownerVerified = true
Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED, {
    scope="metadata",category="dummy",player="authority",
})
local beforeStale = DPS.OutboundStats()
DPS.BroadcastAllBuildBests(nil,nil,staleProgress,1,{
    requester="Requester",requestId="stale-snapshot",bucket=1,
})
local afterStale = DPS.OutboundStats()
Check(afterStale.stale_record - beforeStale.stale_record == pendingRows
        and afterStale.considered - beforeStale.considered == pendingRows,
    "metadata-only revision did not supersede pending rows exactly once as stale")
deferAll = false
local _, replacementComplete = DPS.BroadcastAllBuildBests(
    nil,nil,staleProgress,100,{
        requester="Requester",requestId="stale-snapshot",bucket=1,
    })
local finalOutbound = DPS.OutboundStats()
local finalTerminal = 0
for _, key in ipairs({"offered_direct","offered_relay","peer_current",
        "outside_bucket","score","duration","owner_sender",
        "relay_authorization","schema","stale_record",
        "duplicate_not_better","invalid_category","integrity",
        "outside_request","other"}) do
    finalTerminal = finalTerminal + (tonumber(finalOutbound[key]) or 0)
end
Check(replacementComplete == true
        and finalOutbound.offered_relay > afterStale.offered_relay
        and finalOutbound.considered == finalTerminal,
    "replacement response did not refresh relay authority or terminal rows")

if #failures > 0 then
    error("EXPECTED RED [Stage 28.5 DPS diagnostic characterization]:\n - "
        .. table.concat(failures, "\n - "))
end
print(string.format(
    "Stage 28.5 DPS diagnostics: stored=%d eligible=%d offered=%d peer=%d outside=%d publication=6 -- OK",
    cache.storedRows,cache.rows,offered,selectedRows,10-selectedRows))
