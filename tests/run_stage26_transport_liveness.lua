-- Stage 26.1 expected red: request lifetime must begin at actual transport
-- attempt, control traffic needs bounded latency with bulk fairness, throttle
-- notices must not silently lose the just-attempted packet, and packet
-- metadata must be immutable and complete for every chunk.
Nexus = {}
dofile("core/SyncTransport.lua")
dofile("core/SyncSession.lua")
dofile("core/SyncReconciler.lua")

local TransportFactory = assert(Nexus.SyncInternals.Transport)
local SessionFactory = assert(Nexus.SyncInternals.Session)
local ReconcilerFactory = assert(Nexus.SyncInternals.Reconciler)
local failures = {}
local function Check(ok, message)
    if not ok then failures[#failures + 1] = message end
end

local clock = 100
local sent, observed = {}, {}
local session
local transport = TransportFactory.New({
    maxBulk=8192,maxControl=512,responseHeadroom=8,chatLimit=255,
    sendInterval=1.10,slowInterval=1.75,throttlePause=8,
    throttleSlowTime=45,controlBurstLimit=4,maxAttempts=3,
    now=function() return clock end,
    escapedLen=function(value) return #value end,
    log=function() end,stats={},
    resolveChannel=function() return 7 end,
    channelLabel=function() return "wrbuildssync" end,
    sendChat=function(message)
        sent[#sent + 1] = message:gsub("||", "|")
    end,
    addMessageFilter=function() end,
    observe=function(kind, fields, metadata)
        observed[#observed + 1] = {
            kind=kind,fields=fields,metadata=metadata,
        }
        if session and session.HandleTransportEvent then
            session.HandleTransportEvent(kind, fields, metadata)
        end
    end,
})

for index = 1, 8190 do
    assert(transport.Enqueue("BULK-" .. tostring(index)))
end

session = SessionFactory.New({
    receiveWindow=60,inflightGrace=30,requestCooldown=6,
    autoSyncDelay=6,autoSyncMinPass=1,autoSyncQuiet=1,
    maxConvergenceAge=12,maxReceiveAge=8,maxPasses=2,
    joinRetryInterval=10,joinMaxAttempts=2,
    maxRecoveryQueue=8,maxKnownPeers=8,chatLimit=255,
    requestCode="WLRQ",loadoutRequestCode="WLLQ",
    now=function() return clock end,myName=function() return "Alice" end,
    normalizePeerName=function(value) return tostring(value):lower() end,
    log=function() end,validIdentifier=function() return true end,
    catalogGet=function() return nil end,getCatalog=function() return nil end,
    getDpsCapture=function() return nil end,getAdapter=function() return nil end,
    getCodec=function() return nil end,playerLevel=function() return 80 end,
    requestVersion=function() return "1.20.0-beta.1" end,
    statusVersion=function() return "test" end,
    currentBuildHash=function() return "0,0,0,0,0,0,0,0,aa" end,
    currentDpsHash=function() return "0,0,0,0,0,0,0,0" end,
    enqueue=function(message, metadata)
        return transport.Enqueue(message, metadata)
    end,
    enqueueControl=function(message, metadata)
        return transport.EnqueueControl(message, metadata)
    end,
    transportSnapshot=function() return transport.Snapshot() end,
    transportHasPending=function() return transport.HasPending() end,
    inboundHasPending=function() return false end,
    reconcilerHasPending=function() return false end,
    pendingDeleteCount=function() return 0 end,
    isConnected=function() return true end,ensureChannel=function() return true end,
    sendWhisper=function() end,
})

local requested, why = session.RequestSync()
Check(requested and why == nil, "request was not admitted near bulk capacity")
Check(not session.IsReceiving(),
    "receive timer began at queue admission instead of send lifecycle")
Check(transport.Snapshot().control == 1,
    "Sync request did not use reserved control capacity")

clock = clock + 1.1
transport.Pump(1.1)
Check(sent[1] and sent[1]:find("^WLRQ|Alice|", 1, false),
    "request/control packet did not bypass 8,190 queued bulk packets")
Check(session.IsReceiving(),
    "receive timer did not begin after the request send attempt")

-- Continuous control traffic cannot monopolize the transport. With a burst
-- bound of four, one old bulk packet must make progress within five sends.
for index = 1, 8 do
    assert(transport.EnqueueControl("CTRL-" .. tostring(index), {
        queueClass="control",requestId="fair-" .. tostring(index),
    }))
end
local sentBeforeFair = #sent
for _ = 1, 5 do
    clock = clock + 1.1
    transport.Pump(1.1)
end
local fairBulk = false
for index = sentBeforeFair + 1, #sent do
    if sent[index]:find("^BULK%-", 1, false) then fairBulk = true end
end
Check(fairBulk, "continuous control traffic starved bulk progress")

-- A convergence request has an absolute lifetime even if unrelated bulk work
-- remains queued. A later explicit request may recover after expiry.
clock = clock + 20
session.UpdateAutoConvergence()
local recovered, recoveredWhy = session.RequestSync()
Check(recovered and recoveredWhy ~= "already syncing",
    "expired convergence stayed active behind unrelated bulk traffic")

-- A throttle notice after an API-returned send must requeue the exact packet
-- once with a bounded attempt count instead of treating it as completed/lost.
local throttleClock, throttleSent, throttleEvents = 10, {}, {}
local throttleStats = {}
local throttleTransport = TransportFactory.New({
    maxBulk=16,maxControl=8,responseHeadroom=2,chatLimit=255,
    sendInterval=1,slowInterval=1,throttlePause=2,throttleSlowTime=5,
    controlBurstLimit=4,maxAttempts=2,
    now=function() return throttleClock end,
    escapedLen=function(value) return #value end,
    log=function() end,stats=throttleStats,
    resolveChannel=function() return 3 end,
    channelLabel=function() return "wrbuildssync" end,
    sendChat=function(message) throttleSent[#throttleSent + 1] = message end,
    addMessageFilter=function() end,
    observe=function(kind, fields, metadata)
        throttleEvents[#throttleEvents + 1] = {
            kind=kind,fields=fields,metadata=metadata,
        }
    end,
})
local metadata = {
    requestId="immutable-request",transferId="transfer-1",
    buildId="build-1",queueClass="control",enqueuedAt=10,attempts=0,
}
assert(throttleTransport.EnqueueBatch({"SHARE-1", "SHARE-2"}, metadata))
metadata.requestId = "mutated-after-admission"
throttleClock = throttleClock + 1
throttleTransport.Pump(1)
local noticeMatched = throttleTransport.NoteTransportNotice(
    "You are waiting to send another message")
Check(noticeMatched and throttleTransport.Snapshot().outbound == 2,
    "post-send throttle notice silently lost the attempted packet")
throttleClock = throttleClock + 3
throttleTransport.Pump(3)
Check(#throttleSent == 2 and throttleSent[2] == throttleSent[1],
    "throttled packet was not retried idempotently")
Check(throttleStats.sendAttempts == 2 and throttleStats.requeued == 1
        and throttleStats.sent == 2 and throttleStats.sendFailures == nil,
    "transport outcome counters did not distinguish attempts and requeue")

local firstMetadata
for _, event in ipairs(throttleEvents) do
    if event.kind == "send_attempted" then
        firstMetadata = event.metadata
        break
    end
end
Check(firstMetadata and firstMetadata.requestId == "immutable-request"
        and firstMetadata.chunkOrdinal == 1
        and firstMetadata.chunkTotal == 2
        and firstMetadata.queueClass == "control",
    "batch packet metadata was missing, mutable, or lacked chunk geometry")

-- A same-frame admission may consume the slot freed by an API-returned send.
-- Correlated throttle retry must then reject instead of growing past the cap.
local raceClock, raceEvents = 20, {}
local race = TransportFactory.New({
    maxBulk=2,maxControl=2,responseHeadroom=1,chatLimit=255,
    sendInterval=1,slowInterval=1,throttlePause=2,throttleSlowTime=5,
    controlBurstLimit=4,maxAttempts=2,now=function() return raceClock end,
    escapedLen=function(value) return #value end,log=function() end,stats={},
    resolveChannel=function() return 4 end,channelLabel=function() return 4 end,
    sendChat=function() end,addMessageFilter=function() end,
    observe=function(kind, fields)
        raceEvents[#raceEvents + 1] = {kind=kind,fields=fields}
    end,
})
assert(race.Enqueue("RACE-1") and race.Enqueue("RACE-2"))
raceClock = raceClock + 1
race.Pump(1)
assert(race.Enqueue("RACE-3"))
race.NoteTransportNotice("You are waiting to send another message")
local raceDrop = raceEvents[#raceEvents]
Check(race.Snapshot().bulk == 2 and raceDrop.kind == "send_dropped"
        and raceDrop.fields.reason == "retry queue full",
    "throttle retry race exceeded cap or lacked an explicit terminal reason")

-- Priority Shares bypass ordinary controls but remain FIFO among themselves.
local orderClock, order = 30, {}
local ordered = TransportFactory.New({
    maxBulk=2,maxControl=4,responseHeadroom=1,chatLimit=255,
    sendInterval=1,slowInterval=1,throttlePause=2,throttleSlowTime=5,
    controlBurstLimit=4,maxAttempts=2,now=function() return orderClock end,
    escapedLen=function(value) return #value end,log=function() end,stats={},
    resolveChannel=function() return 5 end,channelLabel=function() return 5 end,
    sendChat=function(message) order[#order + 1] = message end,
    addMessageFilter=function() end,
})
assert(ordered.EnqueueControl("CONTROL"))
assert(ordered.EnqueueControl("SHARE-1", {queueClass="share",shareId="s1"}))
assert(ordered.EnqueueControl("SHARE-2", {queueClass="share",shareId="s2"}))
for _ = 1, 3 do orderClock = orderClock + 1; ordered.Pump(1) end
Check(order[1] == "SHARE-1" and order[2] == "SHARE-2"
        and order[3] == "CONTROL",
    "priority Share ordering bypassed or reordered admitted class FIFO")

-- Large responses yield at a fixed per-request admission quota. The next
-- request from the same peer resumes its bounded cursor instead of dumping or
-- restarting the whole library.
local admitted = 0
local function Split(value)
    local out = {}
    for part in tostring(value):gmatch("[^,]+") do out[#out + 1] = part end
    return out
end
local reconciler = ReconcilerFactory.New({
    bucketCount=1,maxPendingResponses=4,maxPendingLoadouts=4,
    pendingTtl=30,pendingMaxAge=300,claimDelayMin=0,
    claimDelayMax=1,bucketClaimMax=1,maxAdmissionsPerRequest=3,
    now=function() return clock end,myName=function() return "Alice" end,
    stableDelay=function() return 0 end,splitHashes=Split,
    deltaBuildHash=function() return "1" end,
    currentBuildHash=function() return "1,cat" end,
    currentDpsHash=function() return "0" end,
    catalogToken=function() return "cat" end,
    buildCandidateSnapshot=function()
        return {complete=true,byBucket={[1]={}}}
    end,
    snapshotCurrent=function() return true end,
    bucketClaimable=function() return false end,
    backpressured=function() return false end,catalogGet=function() end,
    prepareBuild=function() end,admitBuild=function() return true end,
    sendNextBuild=function(bucket)
        bucket.progress.count = (bucket.progress.count or 0) + 1
        admitted = admitted + 1
        return 1, bucket.progress.count >= 40, true, true
    end,
    sendDpsBucket=function() return false end,
    publishLoadoutClaim=function() return true end,
    publishBucketClaim=function() return true end,
    noteSyncStat=function() end,log=function() end,
})
assert(reconciler.ScheduleRequest({requester="Bob",requestId="page-1",
    peerBuildHash="0,cat",peerDpsHash="0"}))
reconciler.Process(0)
for _ = 1, 3 do reconciler.Process(0) end
Check(admitted == 3 and reconciler.Counts().responses == 0
        and reconciler.Stats().quotaYields == 1,
    "large response did not yield at the per-request admission quota")
assert(reconciler.ScheduleRequest({requester="Bob",requestId="page-2",
    peerBuildHash="0,cat",peerDpsHash="0"}))
reconciler.Process(0)
for _ = 1, 3 do reconciler.Process(0) end
Check(admitted == 6 and reconciler.Stats().quotaYields == 2,
    "next request did not resume the bounded response cursor")

if #failures > 0 then
    error("EXPECTED RED [Stage 26.1 transport/session liveness]:\n - "
        .. table.concat(failures, "\n - "))
end

print("Stage 26.1 transport/session liveness -- OK")
