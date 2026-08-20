-- Stage 28.4 regression: the test.11 stale-head, multi-responder, wire-cost,
-- and session-truth failures stay bounded without changing protocol/storage.
Nexus = {}
dofile("core/DiagnosticHistory.lua")
dofile("core/SyncTransport.lua")
dofile("core/SyncReconciler.lua")
dofile("core/SyncSession.lua")
dofile("core/SyncDiagnostics.lua")

local TransportFactory = assert(Nexus.SyncInternals.Transport)
local ReconcilerFactory = assert(Nexus.SyncInternals.Reconciler)
local SessionFactory = assert(Nexus.SyncInternals.Session)
local DiagnosticsFactory = assert(Nexus.SyncInternals.Diagnostics)

local failures = {}
local function Check(ok, message)
    if not ok then failures[#failures + 1] = message end
end

local function Split(value)
    local out = {}
    for part in tostring(value):gmatch("[^,]+") do
        out[#out + 1] = part
    end
    return out
end

local function NewTransport(options)
    options = options or {}
    local state = {
        clock=tonumber(options.clock) or 400,
        channel=options.channel == nil and 7 or options.channel,
        sent={},observed={},stats={},
    }
    state.transport = TransportFactory.New({
        maxBulk=options.maxBulk or 8192,
        maxControl=options.maxControl or 512,
        responseHeadroom=options.responseHeadroom or 8,
        chatLimit=255,sendInterval=options.sendInterval or 1.10,
        slowInterval=1.75,throttlePause=8,throttleSlowTime=45,
        controlBurstLimit=4,maxAttempts=3,
        now=function() return state.clock end,
        escapedLen=function(value) return #(value:gsub("|", "||")) end,
        log=function() end,stats=state.stats,
        resolveChannel=function() return state.channel end,
        channelLabel=function() return "wrbuildssync" end,
        sendChat=function(payload, kind, language, target)
            state.sent[#state.sent + 1] = {
                payload=payload:gsub("||", "|"),target=target,
            }
        end,
        addMessageFilter=function() end,
        observe=function(kind, fields, metadata)
            state.observed[#state.observed + 1] = {
                kind=kind,fields=fields,metadata=metadata,
            }
        end,
    })
    function state.Pump(elapsed)
        state.clock = state.clock + elapsed
        state.transport.Pump(elapsed)
    end
    return state
end

------------------------------------------------------------------------
-- Stale queue: mirror the live 4,101+ packet head and prove cleanup is a
-- small per-frame batch independent of the 1.10-second send gate.
------------------------------------------------------------------------

local stale = NewTransport()
for index = 1, 4096 do
    assert(stale.transport.Enqueue("OLD|" .. tostring(index), {
        transferId="stale-transfer",expiresAt=stale.clock - 1,
    }))
end
assert(stale.transport.Enqueue("VALID|later", {
    transferId="valid-transfer",expiresAt=stale.clock + 600,
}))
for index = 1, 7 do
    assert(stale.transport.EnqueueControl("CONTROL|" .. tostring(index), {
        requestId="control-" .. tostring(index),queueClass="control",
        expiresAt=stale.clock + 600,
    }))
end
assert(stale.transport.EnqueueControl("CLAIM|priority", {
    requestId="claim-priority",queueClass="claim",
    expiresAt=stale.clock + 600,
}))
assert(stale.transport.EnqueueControl("REQUEST|manual", {
    requestId="request-priority",queueClass="request",
    expiresAt=stale.clock + 600,
}))
assert(stale.transport.EnqueueControl("SHARE|explicit", {
    shareId="share-1",queueClass="share",
    expiresAt=stale.clock + 600,
}))

stale.Pump(0.2)
local beforeCadenceRemoved = stale.stats.expiredRemoved or 0
local beforeCadence = stale.transport.Snapshot()
for _ = 1, 10 do stale.Pump(1.1) end
local afterTen = stale.transport.Snapshot()
local afterTenRemoved = stale.stats.expiredRemoved or 0

assert(beforeCadenceRemoved == 32 and beforeCadence.bulk == 4065,
    "first frame did not remove exactly one bounded stale batch")
assert(#stale.sent == 10 and afterTenRemoved == 352
        and afterTen.bulk == 3745 and afterTen.control == 0,
    string.format("bounded cleanup or control priority drifted during ten send intervals: sent=%d removed=%d bulk=%d control=%d",
        #stale.sent, afterTenRemoved, afterTen.bulk, afterTen.control))

local projectedCurrentClearSeconds =
    math.ceil((afterTen.bulk - 1) / 32) * 0.2
Check((stale.stats.expiredRemoved or 0) >= 16,
    "expired-head cleanup did not run in a bounded batch independent of send cadence")
Check((stale.stats.cleanupBatches or 0) >= 1,
    "transport exposes no bounded stale-cleanup batch counter")
Check(afterTen.control == 0,
    "expired bulk heads starved later request/control traffic after the control burst")
Check(stale.sent[1] and stale.sent[1].payload == "SHARE|explicit",
    "explicit Share did not retain bounded priority over automatic control work")
Check(stale.sent[2] and stale.sent[2].payload == "REQUEST|manual"
        and stale.sent[3] and stale.sent[3].payload == "CLAIM|priority",
    "manual request/claim priority did not remain deterministic behind Share")
Check(type(afterTen.oldestValidAge) == "number"
        and type(afterTen.estimatedStaleBacklog) == "number"
        and type(afterTen.headQueueClass) == "string",
    "transport snapshot omits oldest-valid-age, stale-backlog, or queue-class truth")

-- At a 0.2-second frame cadence, 140 bounded updates are ample for a small
-- cleanup budget to clear 4,096 stale heads without one unbounded frame.
for _ = 1, 140 do stale.Pump(0.2) end
local afterFrames = stale.transport.Snapshot()
Check(afterFrames.bulk <= 1 and afterFrames.control == 0,
    "thousands of stale heads did not clear in bounded per-frame batches")
assert((stale.stats.expiredInspected or 0) == 4096
        and (stale.stats.expiredRemoved or 0) == 4096
        and (stale.stats.cleanupBatches or 0) == 128,
    "stale cleanup counters do not match exact bounded removals")

-- Immutable outstanding identity suppresses a duplicate batch without
-- overwriting the admitted bytes. Manual request cancellation is lazy and the
-- same bounded cleanup path removes the exact superseded packets.
local identity = NewTransport()
local identityMetadata = {requestId="request-one",transferId="build-one",
    expiresAt=identity.clock + 60}
assert(identity.transport.EnqueueBatch({"BATCH|1", "BATCH|2"},
    identityMetadata))
local duplicateOK, duplicateWhy = identity.transport.EnqueueBatch(
    {"BATCH|1", "BATCH|2"}, identityMetadata)
local identityBefore = identity.transport.Snapshot()
assert(duplicateOK and duplicateWhy == "duplicate"
        and identityBefore.bulk == 2
        and identityBefore.outstandingTransfers == 1
        and identityBefore.requestOutstandingTransfers == 1
        and identityBefore.requestRelated == 2,
    "outstanding immutable transfer identity was duplicated or misreported")
assert(identity.transport.CancelRequest("request-one"),
    "active request-scoped transfer could not be superseded")
identity.Pump(0.2)
local identityAfter = identity.transport.Snapshot()
assert(identityAfter.outbound == 0
        and identityAfter.outstandingTransfers == 0
        and identityAfter.requestOutstandingTransfers == 0
        and (identity.stats.supersededRemoved or 0) == 2
        and (identity.stats.duplicateSuppressed or 0) == 1,
    "superseded request packets did not leave through bounded cleanup")

local fullIdentity = NewTransport({maxBulk=2,responseHeadroom=1})
assert(fullIdentity.transport.EnqueueBatch({"FULL|1", "FULL|2"},
    identityMetadata))
local fullDuplicateOK, fullDuplicateWhy =
    fullIdentity.transport.EnqueueBatch({"FULL|1", "FULL|2"},
        identityMetadata)
assert(fullDuplicateOK and fullDuplicateWhy == "duplicate"
        and fullIdentity.transport.Snapshot().bulk == 2,
    "a full queue rejected an already-outstanding immutable transfer")

local collision = NewTransport({maxBulk=8,responseHeadroom=1})
local collisionA = {requester="Alice",requestId="same-request",
    transferId="same-transfer",expiresAt=collision.clock + 60}
local collisionB = {requester="Bob",requestId="same-request",
    transferId="same-transfer",expiresAt=collision.clock + 60}
assert(collision.transport.EnqueueBatch({"COLLIDE|1", "COLLIDE|2"},
    collisionA))
assert(collision.transport.EnqueueBatch({"COLLIDE|1", "COLLIDE|2"},
    collisionB))
assert(collision.transport.CancelRequest("same-request", "Alice"))
collision.Pump(0.2)
local collisionSnapshot = collision.transport.Snapshot()
assert(collisionSnapshot.bulk == 2
        and collisionSnapshot.outstandingTransfers == 1
        and collisionSnapshot.requestOutstandingTransfers == 1,
    "same request ID from another requester was deduplicated or cancelled")

local attemptedCancel = NewTransport()
assert(attemptedCancel.transport.Enqueue("ATTEMPT|old", {
    requester="Alice",requestId="attempted-request",
    transferId="attempted-transfer",
    expiresAt=attemptedCancel.clock + 60,
}))
attemptedCancel.Pump(1.1)
assert(attemptedCancel.transport.CancelRequest(
    "attempted-request", "Alice"))
attemptedCancel.transport.NoteTransportNotice(
    "You are sending messages too quickly")
assert(attemptedCancel.transport.Snapshot().outbound == 0
        and (attemptedCancel.stats.supersededAfterAttempt or 0) == 1,
    "superseded attempted request was restored by a later throttle notice")

local attemptedWithTail = NewTransport()
assert(attemptedWithTail.transport.EnqueueBatch(
    {"ATTEMPT-TAIL|1", "ATTEMPT-TAIL|2"}, {
        requester="Alice",requestId="attempted-tail-request",
        transferId="attempted-tail-transfer",
        expiresAt=attemptedWithTail.clock + 60,
    }))
attemptedWithTail.Pump(1.1)
assert(attemptedWithTail.transport.CancelRequest(
    "attempted-tail-request", "Alice"))
attemptedWithTail.Pump(0.2)
attemptedWithTail.transport.NoteTransportNotice(
    "You are sending messages too quickly")
Check(attemptedWithTail.transport.Snapshot().outbound == 0
        and (attemptedWithTail.stats.supersededAfterAttempt or 0) == 1,
    "purging a superseded request tail revived its attempted packet")

local expiredAttemptMarker = NewTransport()
local expiredAttemptMetadata = {
    requester="Alice",requestId="expired-attempt-marker",
    transferId="expired-attempt-transfer",
    expiresAt=expiredAttemptMarker.clock + 60,
}
assert(expiredAttemptMarker.transport.Enqueue(
    "ATTEMPT-EXPIRY|old", expiredAttemptMetadata))
expiredAttemptMarker.Pump(1.1)
assert(expiredAttemptMarker.transport.CancelRequest(
    "expired-attempt-marker", "Alice"))
expiredAttemptMarker.Pump(4.1)
assert(expiredAttemptMarker.transport.Enqueue(
    "ATTEMPT-EXPIRY|new", expiredAttemptMetadata))
expiredAttemptMarker.Pump(0.2)
Check(expiredAttemptMarker.transport.Snapshot().outbound == 1,
    "attempt cancellation survived beyond the throttle-correlation window")

-- Disconnect/reconnect and channel renumbering retain valid data and resolve
-- the named channel immediately before send.
local route = NewTransport({channel=false})
assert(route.transport.Enqueue("ROUTE|one", {
    expiresAt=route.clock + 60,
}))
route.Pump(1.1)
assert(#route.sent == 0 and route.transport.Snapshot().bulk == 1,
    "disconnected route dropped or attempted valid work")
route.channel = 9
route.Pump(1.1)
assert(#route.sent == 1 and route.sent[1].target == 9
        and route.transport.Snapshot().bulk == 0,
    "reconnected route did not use the current channel number")

------------------------------------------------------------------------
-- Fanout and wire cost: five valid peers see one public request. Existing WLRC
-- receipts elect one same-hash responder before record serialization, and that
-- winner is bounded by projected transport cost rather than logical rows.
------------------------------------------------------------------------

local zeroBuckets = "0,0,0,0,0,0,0,0"
local localBuckets = "1,0,0,0,0,0,0,0"
local currentWireHash = zeroBuckets .. ",catalog"
local localWireHash = localBuckets .. ",catalog"
local responders, responseClaims = {}, {}
local responderClock = 500

local function NewResponder(name, options)
    options = options or {}
    local row = {name=name,logical=0,chunks=0,bytes=0,claims=0,
        cancelled=nil,claimQueueOpen=true,
        claimAttemptOnPublish=options.claimAttemptOnPublish ~= false}
    row.snapshot = {complete=true,byBucket={[1]={}},
        claimSafeByBucket={[1]=true}}
    local reconciler
    reconciler = ReconcilerFactory.New({
        bucketCount=8,maxPendingResponses=16,maxPendingLoadouts=16,
        pendingTtl=30,pendingMaxAge=300,claimDelayMin=0,
        claimDelayMax=1,bucketClaimMax=1,maxAdmissionsPerRequest=32,
        maxChunksPerRequest=64,maxBytesPerRequest=16384,
        maxSendSecondsPerRequest=75,maxTransfersPerRequest=8,
        sendInterval=1.10,responseElectionDelay=2.5,
        now=function() return responderClock end,myName=function() return name end,
        stableDelay=function() return 0 end,splitHashes=Split,
        deltaBuildHash=function() return localBuckets end,
        currentBuildHash=function() return localBuckets .. ",catalog" end,
        currentDpsHash=function() return zeroBuckets end,
        catalogToken=function() return "catalog" end,
        buildCandidateSnapshot=function()
            return row.snapshot
        end,
        snapshotCurrent=function() return true end,
        bucketClaimable=function() return true end,
        backpressured=function() return false end,
        catalogGet=function() return nil end,
        prepareBuild=function() return nil end,
        admitBuild=function() return true end,
        sendNextBuild=function(bucket, budget)
            local ordinal = (tonumber(bucket.progress.count) or 0) + 1
            row.lastOrdinal = ordinal
            local chunks = ordinal <= 14 and 9 or 8
            local bytes = chunks * 220
            reconciler.NoteStat("buildSerializations", 1)
            reconciler.NoteStat("chunkMessagesBuilt", chunks)
            reconciler.NoteStat("encodedBytesBuilt", bytes)
            if chunks > (tonumber(budget and budget.chunks) or 0)
                or bytes > (tonumber(budget and budget.bytes) or 0)
                or chunks * 1.10 > (tonumber(budget and budget.seconds) or 0)
                or (tonumber(budget and budget.transfers) or 0) < 1 then
                return 0, false, true, false, "response wire budget",
                    chunks, bytes, 1
            end
            bucket.progress.count = ordinal
            row.logical = row.logical + 1
            row.chunks = row.chunks + chunks
            row.bytes = row.bytes + bytes
            reconciler.NoteStat("buildAdmissions", 1)
            return 1, ordinal >= 40, true, true, nil, chunks, bytes, 1
        end,
        sendDpsBucket=function() return false end,
        publishLoadoutClaim=function() return true end,
        publishResponseClaim=function(entry)
            if not row.claimQueueOpen then return false, "sync queue full" end
            responseClaims[#responseClaims + 1] = {
                responder=name,requester=entry.requester,
                requestId=entry.requestId,buildHash=entry.localBuildWireHash,
                dpsHash=entry.localDpsHash,
            }
            return true, row.claimAttemptOnPublish and "attempted" or "queued"
        end,
        publishBucketClaim=function()
            row.claims = row.claims + 1
            return true
        end,
        outstandingTransfers=function() return row.logical end,
        cancelRequest=function(requestId)
            row.cancelled = requestId
            return true
        end,
        noteSyncStat=function() end,log=function() end,
    })
    row.reconciler = reconciler
    return row
end

for index = 1, 5 do
    local row = NewResponder("Responder" .. tostring(index))
    responders[#responders + 1] = row
    assert(row.reconciler.ScheduleRequest({
        requester="Requester",requestId="public-request-1",
        peerBuildHash=currentWireHash,peerDpsHash=zeroBuckets,
    }))
    -- Equivalent delivery while active is idempotent.
    assert(row.reconciler.ScheduleRequest({
        requester="Requester",requestId="public-request-1",
        peerBuildHash=currentWireHash,peerDpsHash=zeroBuckets,
    }))
    assert(row.reconciler.Counts().responses == 1,
        "active duplicate request created a second pending response")
    row.reconciler.Process(0) -- prepare
end

assert(#responseClaims == #responders,
    "equivalent responders did not publish one bounded election receipt")
for _, claim in ipairs(responseClaims) do
    for _, row in ipairs(responders) do
        row.reconciler.HandleLegacyClaim(claim)
    end
end
local electionSuppressions = 0
for index, row in ipairs(responders) do
    if index > 1 and row.reconciler.Counts().responses == 0 then
        electionSuppressions = electionSuppressions + 1
    end
end
assert(electionSuppressions == #responders - 1,
    "deterministic same-hash election did not suppress overlapping responders")

responderClock = responderClock + 3
local first = responders[1]
for _ = 1, 8 do first.reconciler.Process(0) end
assert(first.logical == 7 and first.chunks == 63
        and first.bytes == 13860
        and first.reconciler.Stats().wireBudgetYields == 1,
    "wire budget did not stop before the eighth nine-chunk transfer")

local fanoutLogical, fanoutChunks, fanoutBytes = 0, 0, 0
for _, row in ipairs(responders) do
    fanoutLogical = fanoutLogical + row.logical
    fanoutChunks = fanoutChunks + row.chunks
    fanoutBytes = fanoutBytes + row.bytes
end
local fanoutSeconds = fanoutChunks * 1.10
assert(fanoutLogical == 7 and fanoutChunks == 63
        and fanoutBytes == 13860 and math.abs(fanoutSeconds - 69.3) < 0.001,
    string.format("multi-responder fixture drifted: %d/%d/%d/%.3f",
        fanoutLogical, fanoutChunks, fanoutBytes, fanoutSeconds))

Check(fanoutLogical <= 32,
    "one public request caused every visible responder to serialize overlapping rows")
Check(responders[1].chunks <= 64 and responders[1].bytes <= 16384
        and responders[1].chunks * 1.10 <= 75,
    "32-record quota ignored projected chunks, bytes, and send duration")
local firstStats = first.reconciler.Stats()
Check(type(firstStats.projectedChunks) == "number"
        and type(firstStats.projectedBytes) == "number"
        and type(firstStats.projectedSendSeconds) == "number"
        and type(firstStats.outstandingTransfers) == "number",
    "response diagnostics omit wire-cost and outstanding-transfer accounting")

-- Once the wire-budget entry disappears, the same immutable request receipt
-- suppresses retransmission before another serialization can begin.
assert(first.reconciler.ScheduleLoadout({
    requester="Requester",buildId="one-loadout",
}))
assert(first.reconciler.ScheduleLoadout({
    requester="Requester",buildId="one-loadout",
}))
assert(first.reconciler.Counts().loadouts == 1,
    "duplicate loadout request created overlapping pending work")
assert(first.reconciler.HandleLoadoutClaim({
    responder="OtherResponder",requester="Requester",
    buildId="one-loadout",
}) and first.reconciler.Counts().loadouts == 0,
    "loadout claim did not suppress the pending duplicate response")

assert(first.reconciler.ScheduleRequest({
    requester="Requester",requestId="public-request-1",
    peerBuildHash=currentWireHash,peerDpsHash=zeroBuckets,
}))
first.reconciler.Process(0)
for _ = 1, 8 do first.reconciler.Process(0) end
local retransmittedLogical = first.logical - 7
assert(first.reconciler.Counts().responses == 0,
    "completed request identity recreated pending response work")
Check(retransmittedLogical == 0
        and (first.reconciler.Stats().equivalentSuppressed or 0) >= 1,
    "completed/yielded immutable request identity admitted equivalent work again")

local strandedBucketClaims = 0
for index = 2, #responders do
    if responders[index].reconciler.HandleBucketClaim({
        responder=first.name,requester="Requester",
        requestId="public-request-1",kind="B",bucket=1,hash="1",
    }) then
        strandedBucketClaims = strandedBucketClaims + 1
    end
end
assert(strandedBucketClaims == 0,
    "elected-away responders retained bucket work for a later claim")
local lateClaimSuppressions = electionSuppressions
Check(lateClaimSuppressions == #responders - 1,
    "same-hash claim did not suppress other responders before payload work")

local supersede = NewResponder("SupersedeResponder")
assert(supersede.reconciler.ScheduleRequest({requester="ManualRequester",
    requestId="automatic-old",peerBuildHash=currentWireHash,
    peerDpsHash=zeroBuckets}))
supersede.reconciler.Process(0)
assert(supersede.reconciler.ScheduleRequest({requester="ManualRequester",
    requestId="manual-new",peerBuildHash=currentWireHash,
    peerDpsHash=zeroBuckets}))
assert(supersede.reconciler.Counts().responses == 1
        and supersede.cancelled == "automatic-old"
        and supersede.reconciler.Stats().requestsSuperseded == 1,
    "new request identity overlapped equivalent responder work")

local supersedeAfterAdmission = NewResponder("SupersedeAfterAdmission")
assert(supersedeAfterAdmission.reconciler.ScheduleRequest({
    requester="ManualRequester2",requestId="automatic-admitted",
    peerBuildHash=currentWireHash,peerDpsHash=zeroBuckets}))
supersedeAfterAdmission.reconciler.Process(0)
responderClock = responderClock + 3
supersedeAfterAdmission.reconciler.Process(3)
assert(supersedeAfterAdmission.logical == 1
        and supersedeAfterAdmission.lastOrdinal == 1,
    "supersession fixture did not admit its first old-request response")
assert(supersedeAfterAdmission.reconciler.ScheduleRequest({
    requester="ManualRequester2",requestId="manual-after-admission",
    peerBuildHash=currentWireHash,peerDpsHash=zeroBuckets}))
supersedeAfterAdmission.reconciler.Process(0)
responderClock = responderClock + 3
supersedeAfterAdmission.reconciler.Process(3)
Check(supersedeAfterAdmission.logical == 2
        and supersedeAfterAdmission.lastOrdinal == 1,
    "new request resumed progress from response packets it had cancelled")

local claimBlocked = NewResponder("ClaimBlockedResponder")
claimBlocked.claimQueueOpen = false
assert(claimBlocked.reconciler.ScheduleRequest({requester="ClaimRequester",
    requestId="claim-retry",peerBuildHash=currentWireHash,
    peerDpsHash=zeroBuckets}))
claimBlocked.reconciler.Process(0)
for _ = 1, 3 do
    responderClock = responderClock + 1.1
    claimBlocked.reconciler.Process(1.1)
end
assert(claimBlocked.logical == 0
        and claimBlocked.reconciler.Counts().responses == 1
        and claimBlocked.reconciler.Stats().claimQueueDeferrals >= 1,
    "payload work bypassed a saturated deterministic claim queue")
claimBlocked.claimQueueOpen = true
responderClock = responderClock + 1.1
claimBlocked.reconciler.Process(1.1)
responderClock = responderClock + 3
claimBlocked.reconciler.Process(3)
assert(claimBlocked.logical == 1,
    "claim-queue recovery did not resume bounded payload work")

local queuedClaim = NewResponder("QueuedClaimResponder", {
    claimAttemptOnPublish=false,
})
assert(queuedClaim.reconciler.ScheduleRequest({requester="QueuedRequester",
    requestId="queued-claim",peerBuildHash=currentWireHash,
    peerDpsHash=zeroBuckets}))
queuedClaim.reconciler.Process(0)
responderClock = responderClock + 10
queuedClaim.reconciler.Process(10)
assert(queuedClaim.logical == 0,
    "payload started before the queued election claim was attempted")
assert(queuedClaim.reconciler.HandleTransportEvent("send_attempted", {}, {
    requester="QueuedRequester",requestId="queued-claim",
    transferId="response-claim:QueuedRequester:queued-claim",
    queueClass="claim",
}))
responderClock = responderClock + 3
queuedClaim.reconciler.Process(3)
assert(queuedClaim.logical == 1,
    "attempted election claim did not release bounded payload work")

local expiredClaim = NewResponder("ExpiredClaimResponder", {
    claimAttemptOnPublish=false,
})
assert(expiredClaim.reconciler.ScheduleRequest({requester="ExpiredRequester",
    requestId="expired-claim",peerBuildHash=currentWireHash,
    peerDpsHash=zeroBuckets}))
expiredClaim.reconciler.Process(0)
responderClock = responderClock + 31
expiredClaim.reconciler.Process(31)
assert(expiredClaim.reconciler.Counts().responses == 0
        and expiredClaim.cancelled == "expired-claim",
    "expired response left its unseen election claim queued")

-- A shared candidate snapshot can become complete while a response entry is
-- waiting. An already-received better claim must win before either a local
-- election receipt or the first payload admission.
local delayedClaim = NewResponder("ZedResponder")
delayedClaim.snapshot.complete = false
assert(delayedClaim.reconciler.ScheduleRequest({requester="DelayedRequester",
    requestId="delayed-claim",peerBuildHash=currentWireHash,
    peerDpsHash=zeroBuckets}))
delayedClaim.reconciler.Process(0)
assert(delayedClaim.reconciler.HandleLegacyClaim({responder="AbleResponder",
    requester="DelayedRequester",requestId="delayed-claim",
    buildHash=localWireHash,dpsHash=zeroBuckets}))
local claimsBeforeDelayed = #responseClaims
delayedClaim.snapshot.complete = true
delayedClaim.reconciler.Process(0)
responderClock = responderClock + 3
delayedClaim.reconciler.Process(3)
assert(delayedClaim.logical == 0
        and delayedClaim.reconciler.Counts().responses == 0
        and #responseClaims == claimsBeforeDelayed,
    "cached snapshot completion admitted work before an earlier winning claim")

-- Older protocol-7 peers without the additive catalog token retain the
-- established compatibility path.
local legacy = NewResponder("LegacyResponder")
assert(legacy.reconciler.ScheduleRequest({
    requester="LegacyRequester",requestId="legacy-request",
    peerBuildHash=zeroBuckets,peerDpsHash=zeroBuckets,
}))
legacy.reconciler.Process(0)
assert(legacy.reconciler.Stats().compatRequests == 1,
    "older protocol-7 request lost compatibility routing")

------------------------------------------------------------------------
-- Session truth: manual intent must supersede stale automatic work, and an
-- unchanged local hash without peer validation must not prove convergence.
------------------------------------------------------------------------

local function NewSession(options)
    options = options or {}
    local state = {
        clock=tonumber(options.clock) or 100,
        queued={},cancelled={},buildHash=options.buildHash or "local-build",
        dpsHash=options.dpsHash or "local-dps",
    }
    state.session = SessionFactory.New({
        receiveWindow=2,inflightGrace=1,requestCooldown=1,
        autoSyncDelay=6,autoSyncMinPass=1,autoSyncQuiet=1,
        maxConvergenceAge=options.maxConvergenceAge or 20,
        maxReceiveAge=10,maxPasses=3,
        joinRetryInterval=10,joinMaxAttempts=2,
        maxRecoveryQueue=8,maxKnownPeers=8,chatLimit=255,
        requestCode="WLRQ",loadoutRequestCode="WLLQ",
        now=function() return state.clock end,
        myName=function() return "Alice" end,
        normalizePeerName=function(value) return tostring(value):lower() end,
        log=function() end,validIdentifier=function() return true end,
        catalogGet=function() return nil end,getCatalog=function() return nil end,
        getDpsCapture=function() return nil end,getAdapter=function() return nil end,
        getCodec=function() return nil end,playerLevel=function() return 80 end,
        requestVersion=function() return "1.20.0-beta.1" end,
        statusVersion=function() return "test" end,
        currentBuildHash=function() return state.buildHash end,
        currentClaimBuildHash=function() return state.buildHash end,
        currentDpsHash=function() return state.dpsHash end,
        enqueue=function(message, metadata)
            state.queued[#state.queued + 1] = {message=message,metadata=metadata}
            return true
        end,
        enqueueControl=function(message, metadata)
            state.queued[#state.queued + 1] = {message=message,metadata=metadata}
            return true
        end,
        cancelRequest=function(requestId)
            state.cancelled[#state.cancelled + 1] = requestId
            return true
        end,
        transportSnapshot=function() return {bulk=4096,control=0} end,
        transportHasPending=function() return true end,
        inboundHasPending=function() return false end,
        reconcilerHasPending=function() return false end,
        pendingDeleteCount=function() return 0 end,
        isConnected=function() return true end,ensureChannel=function() return true end,
        sendWhisper=function() end,
    })
    return state
end

local automatic = NewSession()
automatic.session.Reset()
automatic.session.UpdateAutoSync(6)
assert(#automatic.queued == 1,
    "automatic convergence fixture did not queue its login request")
local manualOK, manualWhy = automatic.session.RequestSync()
Check(manualOK and manualWhy ~= "already syncing"
        and #automatic.queued == 2 and #automatic.cancelled == 1
        and automatic.session.StatusSnapshot().mode == "manual",
    "manual Sync did not supersede stale automatic request ownership")

local noPeer = NewSession()
assert(noPeer.session.RequestSync())
local firstRequest = noPeer.queued[#noPeer.queued]
noPeer.session.HandleTransportEvent("send_attempted", {},
    firstRequest.metadata)
noPeer.clock = noPeer.clock + 3
noPeer.session.UpdateAutoConvergence()
local secondRequest = noPeer.queued[#noPeer.queued]
assert(secondRequest ~= firstRequest,
    "no-peer convergence fixture did not start its second pass")
noPeer.session.HandleTransportEvent("send_attempted", {},
    secondRequest.metadata)
noPeer.clock = noPeer.clock + 3
noPeer.session.UpdateAutoConvergence()
local thirdRequest = noPeer.queued[#noPeer.queued]
assert(thirdRequest ~= secondRequest,
    "no-peer convergence fixture did not reach its bounded third pass")
noPeer.session.HandleTransportEvent("send_attempted", {},
    thirdRequest.metadata)
noPeer.clock = noPeer.clock + 3
noPeer.session.UpdateAutoConvergence()
local noPeerStatus = noPeer.session.StatusSnapshot()
Check(noPeerStatus.terminal ~= "stable",
    "unchanged local snapshots reported stable without peer receipt/validation proof")
assert(noPeerStatus.terminal == "no peer progress",
    "no-peer request did not stop with a truthful bounded terminal reason")

local proven = NewSession()
assert(proven.session.RequestSync())
local provenFirst = proven.queued[#proven.queued]
proven.session.HandleTransportEvent("send_attempted", {}, provenFirst.metadata)
assert(proven.session.NotePeerClaim(provenFirst.metadata.requestId,
    proven.buildHash, proven.dpsHash), "matching peer receipt was rejected")
assert(proven.session.NotePeerClaim(provenFirst.metadata.requestId,
    "different-build", "different-dps")
        and proven.session.StatusSnapshot().peerEquivalent,
    "later divergent peer made matching-peer proof order-dependent")
proven.clock = proven.clock + 3
proven.session.UpdateAutoConvergence()
local provenSecond = proven.queued[#proven.queued]
proven.session.HandleTransportEvent("send_attempted", {}, provenSecond.metadata)
assert(proven.session.NotePeerClaim(provenSecond.metadata.requestId,
    "different-build", "different-dps"),
    "divergent peer progress was rejected instead of recorded")
assert(proven.session.NotePeerClaim(provenSecond.metadata.requestId,
    proven.buildHash, proven.dpsHash), "second matching peer receipt was rejected")
proven.clock = proven.clock + 3
proven.session.UpdateAutoConvergence()
assert(proven.session.StatusSnapshot().terminal == "stable",
    "two peer-proven unchanged passes did not converge")

local catalogMismatch = NewSession({
    buildHash="1,0,0,0,0,0,0,0,catalog-a",
})
assert(catalogMismatch.session.RequestSync())
local catalogRequest = catalogMismatch.queued[#catalogMismatch.queued]
catalogMismatch.session.HandleTransportEvent("send_attempted", {},
    catalogRequest.metadata)
assert(catalogMismatch.session.NotePeerClaim(
    catalogRequest.metadata.requestId,
    "1,0,0,0,0,0,0,0,catalog-b", catalogMismatch.dpsHash)
        and not catalogMismatch.session.StatusSnapshot().peerEquivalent,
    "matching deltas with a different bundled catalog proved false convergence")

local expiring = NewSession({maxConvergenceAge=5})
assert(expiring.session.RequestSync())
expiring.clock = expiring.clock + 6
expiring.session.UpdateAutoConvergence()
local retryOK, retryWhy = expiring.session.RequestSync()
assert(retryOK and retryWhy ~= "already syncing",
    "absolute request expiry did not release later manual Sync")

local diagnostics = DiagnosticsFactory.New({
    history=Nexus.DiagnosticHistory,now=function() return 500 end,
})
local staleWork = diagnostics.ProjectSyncWork({
    transport={bulk=4096,control=0,estimatedStaleBacklog=4096},
    reconciliation={},incoming={},
    session={converging=false,receiving=false,terminal="expired",pass=1},
})
local phase = diagnostics.ProjectLeaderboardStatus({
    work=staleWork,throttleRemaining=0,
    converging=false,receiving=false,
})
Check(phase == "cleaning" and staleWork.requestRelated == 0
        and staleWork.stale == 4096 and staleWork.total == 4096,
    "expired unrelated transport work was reported as an active Sync request")

print(string.format(
    "stage28 sync characterization: stale pre=%d ten=%d final=%d control=%d clear=%.1fs fanout=%d/%d/%d/%.1fs retransmit=%d lateClaims=%d manual=%s terminal=%s phase=%s",
    beforeCadenceRemoved,afterTenRemoved,afterFrames.bulk,afterFrames.control,
    projectedCurrentClearSeconds,fanoutLogical,fanoutChunks,fanoutBytes,
    fanoutSeconds,retransmittedLogical,lateClaimSuppressions,
    tostring(manualWhy),tostring(noPeerStatus.terminal),tostring(phase)))

if #failures > 0 then
    error("Stage 28.4 Sync convergence regression:\n - "
        .. table.concat(failures, "\n - "))
end

print("Stage 28.4 stale cleanup, fanout, wire budget, and session truth -- OK")
