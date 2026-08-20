-- Stage 36.2 real-owner regression for nondestructive world transitions and
-- terminal Share/delete ownership. The pre-repair source must reach every
-- named failure instead of stopping after the missing revalidation entrypoint.
local H = dofile("tests/harness.lua")
dofile("core/PeerDebug.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua")
dofile("core/SyncTransport.lua")
dofile("core/SyncCompatibility.lua")
dofile("core/SyncReconciler.lua")
dofile("core/SyncInbound.lua")
dofile("core/SyncDiagnostics.lua")
dofile("core/SyncSession.lua")
dofile("core/Sync.lua")

local Sync = Nexus.Sync
local failures = {}
local checks = 0
local function Check(ok, name)
    checks = checks + 1
    if not ok then failures[#failures + 1] = name end
end

local STATUS_FIELDS = {
    kind=true,id=true,version=true,operationKey=true,generation=true,
    attempt=true,outcome=true,terminal=true,reason=true,accepted=true,
    queueAdmitted=true,queueReason=true,retryPending=true,
    retryAttempts=true,retryOutcome=true,retrySecondsLeft=true,
    sent=true,sendCompleted=true,sendState=true,confirmation=true,
    createdAt=true,queuedAt=true,attemptedAt=true,sentAt=true,
    resolvedAt=true,expiresAt=true,expired=true,superseded=true,owner=true,
}
local function ScalarOnly(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for key, item in pairs(value) do
        count = count + 1
        if not STATUS_FIELDS[key] or count > 30 then return false end
        local kind = type(item)
        if kind ~= "string" and kind ~= "number"
            and kind ~= "boolean" and kind ~= "nil" then
            return false
        end
        if kind == "string" then
            local limit = key == "id" and 96
                or key == "operationKey" and 192 or 128
            if #item > limit or item:find("[%c|]") then return false end
        end
    end
    return true
end

local clock = 1000
local player = "Alice"
GetTime = function() return clock end
time = function() return 50000 + math.floor(clock) end
UnitName = function() return player end
H.joinedChannels = {wrbuildssync=7}
H.sentChatMessages = {}

local scheduleCalls = 0
local maintenanceCallback
local viewRefreshes = 0
Nexus.Scheduler = {
    IsInitialized=function() return true end,
    Every=function(key, interval, callback)
        scheduleCalls = scheduleCalls + 1
        maintenanceCallback = callback
        return key == "sync.pending-deletes" and interval == 1
            and type(callback) == "function"
    end,
}
Nexus.ViewRefresh = {
    Request=function()
        viewRefreshes = viewRefreshes + 1
        return true
    end,
}

local function FreshDb()
    NexusDB = {communityBuilds={},syncTombstones={},dpsCapture={}}
    H.sentChatMessages = {}
    H.joinedChannels = {wrbuildssync=7}
    Sync.Init(Nexus.Codec, {})
end

local function WorldEntry()
    if type(Sync.OnWorldEntry) == "function" then
        return Sync.OnWorldEntry(Nexus.Codec, {})
    end
    -- This is the destructive route used by Main before the repair.
    return Sync.Init(Nexus.Codec, {})
end

local function Pump(delta, count)
    for _ = 1, count or 1 do
        clock = clock + delta
        Sync.OnUpdate(delta)
    end
end

local function ShareStatus(id)
    return Sync.GetShareStatus(id)
end

local function DeleteStatus(id)
    return Sync.GetDeleteStatus(id)
end

local function ShareBuild(id)
    return {
        id=id,title="Stage 36 Share " .. id,description="terminal fixture",
        author=player,ownerKey=player:lower() .. "@ebonhold",class="MAGE",
        echoes={{spellId=730001,quality=3,stacks=1}},
        postedAt=50001,lastModified=50001,isMine=true,
    }
end

local function AdmitShare(id)
    local ok, why, status = Sync.BroadcastBuildSummary(
        ShareBuild(id), {retryOnFull=true})
    Check(ok == true and why == "queued" and type(status) == "table"
        and status.queueAdmitted == true,
        id .. " did not enter the admitted Share owner")
    return status
end

-- First initialization remains destructive and constant-shape, while an
-- ordinary repeated world entry preserves the active manual request and does
-- not reinstall the keyed maintenance task.
FreshDb()
local scheduledAfterInit = scheduleCalls
local clean = Sync.WorkState()
Check(clean.outbound == 0 and clean.buildInflight == 0
        and clean.dpsInflight == 0,
    "first initialization did not start with clean transient work")
local manualQueued = Sync.RequestSync()
Pump(1.2, 1)
Check(manualQueued == true and Sync.IsReceiving() == true,
    "manual Sync fixture did not open its bounded receive window after send")
local requestBefore = Sync.Stats().requestId
local requestWorkBefore = Sync.WorkState()
clock = clock + 7
local requestTimeBefore = Sync.ReceiveTimeLeft()
WorldEntry()
H.joinedChannels = {wrbuildssync=9}
WorldEntry()
local requestAfter = Sync.WorkState()
Check(type(Sync.OnWorldEntry) == "function",
    "Sync has no nondestructive world-entry owner")
Check(Sync.IsReceiving() == true
        and Sync.Stats().requestId == requestBefore
        and requestAfter.control == requestWorkBefore.control
        and requestTimeBefore > 0
        and Sync.ReceiveTimeLeft() == requestTimeBefore
        and Sync.ChannelIndex() == 9,
    "world entry destroyed or replaced the active manual request")
Check(scheduleCalls == scheduledAfterInit,
    "repeated world entry duplicated the Sync maintenance task")

-- A request that has not reached SendChatMessage also survives zoning. The
-- same immutable request ID is attempted once after the transition.
FreshDb()
H.sentChatMessages = {}
local pendingRequestOk = Sync.RequestSync()
local pendingRequestId = Sync.Stats().requestId
local pendingRequestDepth = Sync.WorkState().control
clock = clock + 5
WorldEntry(); WorldEntry()
local pendingRequestAfter = Sync.WorkState()
Check(pendingRequestOk == true and pendingRequestDepth == 1
        and pendingRequestAfter.control == 1
        and Sync.Stats().requestId == pendingRequestId
        and #H.sentChatMessages == 0,
    "world entry replaced or attempted a still-pending manual request")
Pump(1.2, 1)
local requestMessages = 0
for _, message in ipairs(H.sentChatMessages) do
    if message.text:find("^WLRQ|") then
        requestMessages = requestMessages + 1
    end
end
Check(requestMessages == 1 and Sync.IsReceiving() == true
        and Sync.Stats().requestId == pendingRequestId,
    "pending manual request did not resume exactly once after world entry")

-- Mixed control/bulk ownership keeps its queue classes and FIFO order through
-- repeated zoning. Zone after three control sends so resetting the private
-- fairness cursor would visibly delay the first bulk packet.
FreshDb()
-- Consume login auto-sync ownership and reset the transport burst cursor with
-- one ordinary warm-up packet before recording the exact mixed sequence.
Check(Sync.RequestSync() == true,
    "mixed world-entry queue could not suppress login auto-sync")
Pump(1.2, 1)
Check(Sync.BroadcastDps("fifo-warmup", player, 71000, 80, "dummy"),
    "mixed world-entry fairness warm-up was not admitted")
Pump(1.2, 1)
H.sentChatMessages = {}
Check(Sync.BroadcastDps("fifo-bulk-a", player, 71001, 80, "dummy")
        and Sync.BroadcastDps("fifo-bulk-b", player, 71002, 80, "dummy"),
    "mixed world-entry queue fixture was not admitted")
local priorityShares = {}
for index = 1, 5 do
    priorityShares[index] = AdmitShare("fifo-control-" .. index)
end
Pump(1.2, 3)
local mixedBefore = Sync.WorkState()
WorldEntry(); WorldEntry()
local mixedAfter = Sync.WorkState()
Check(mixedAfter.control == mixedBefore.control
        and mixedAfter.sending == mixedBefore.sending
        and mixedAfter.headQueueClass == mixedBefore.headQueueClass,
    "world entry changed queue ownership or fairness state")
Pump(1.2, 4)
local priorityFour = ShareStatus("fifo-control-4")
local priorityFive = ShareStatus("fifo-control-5")
local mixedOrder = {}
for _, message in ipairs(H.sentChatMessages) do
    local wire = tostring(message.text or ""):gsub("||", "|")
    if wire:find("^WLBI|") then
        local encoded = wire:match("^WLBI|[^|]+|(.+)$")
        local payload = encoded and Nexus.Codec.JSONDecode(
            Nexus.Codec.Base64Decode(encoded)) or nil
        mixedOrder[#mixedOrder + 1] = "C:" .. tostring(
            payload and payload.id or "invalid")
    elseif wire:find("fifo%-bulk%-a") then
        mixedOrder[#mixedOrder + 1] = "B:a"
    elseif wire:find("fifo%-bulk%-b") then
        mixedOrder[#mixedOrder + 1] = "B:b"
    else
        mixedOrder[#mixedOrder + 1] = "other:" .. wire:sub(1, 80)
    end
end
local expectedMixedOrder = table.concat({
    "C:fifo-control-1", "C:fifo-control-2", "C:fifo-control-3",
    "C:fifo-control-4", "B:a", "C:fifo-control-5", "B:b",
}, ",")
local actualMixedOrder = table.concat(mixedOrder, ",")
Check(#H.sentChatMessages == 7
        and actualMixedOrder == expectedMixedOrder
        and priorityFour and priorityFour.outcome == "sent-attempted"
        and priorityFive and priorityFive.outcome == "sent-attempted",
    "world entry reordered mixed FIFO work or broke bounded control priority: "
        .. actualMixedOrder)

-- An admitted immutable Share remains queued through zoning, then reports
-- only a successful API attempt. It must never invent peer receipt.
FreshDb()
local shareScheduled = scheduleCalls
local zonedShare = AdmitShare("zone-share")
local zonedGeneration = zonedShare.generation
zonedShare.outcome = "caller-mutated"
zonedShare.operationKey = "caller-mutated"
local shareQueueBefore = Sync.WorkState().control
WorldEntry()
local shareCopy = ShareStatus("zone-share")
Check(Sync.WorkState().control == shareQueueBefore
        and shareCopy and shareCopy.outcome == "queued"
        and shareCopy.terminal == false
        and shareCopy.generation == zonedGeneration
        and shareCopy.operationKey ~= "caller-mutated",
    "world entry discarded or falsely terminalized an admitted Share")
Check(scheduleCalls == shareScheduled,
    "Share zoning installed a duplicate maintenance task")
Pump(1.2, 1)
shareCopy = ShareStatus("zone-share")
Check(shareCopy and shareCopy.outcome == "attempted"
        and shareCopy.terminal == false
        and shareCopy.sent == true
        and shareCopy.sendCompleted == true,
    "successful Share API return did not enter the throttle-attribution window")
Pump(4.1, 1)
shareCopy = ShareStatus("zone-share")
Check(shareCopy and shareCopy.outcome == "sent-attempted"
        and shareCopy.terminal == true
        and shareCopy.accepted == false
        and shareCopy.peerStored == nil
        and zonedShare.outcome == "caller-mutated",
    "successful Share API return was not truthfully settled as sent-attempted")
Check(ScalarOnly(shareCopy),
    "Share status retained payload or variable-shape ownership data")
shareCopy.outcome = "mutated-copy"
Check(ShareStatus("zone-share").outcome == "sent-attempted",
    "Share status getter exposed its live mutable owner")
Check((Sync.Stats().operationAccepted or 0) == 0,
    "sender API success invented peer acceptance")

-- A malformed legacy relay attempt for an already-active immutable Share ID
-- is independently rejected. Its receipt must not steal the queryable owner
-- from the valid queued operation, even though both attempts use the same ID
-- and version.
FreshDb()
local protectedShare = AdmitShare("protected-same-id")
local protectedBefore = ShareStatus("protected-same-id")
local hostileShare = ShareBuild("protected-same-id")
hostileShare.legacyRecovered = true
hostileShare.ownerVerified = false
hostileShare.echoes = "malformed relay payload"
local hostileOk, hostileWhy, hostileReceipt =
    Sync.BroadcastBuildSummary(hostileShare, {retryOnFull=true})
local protectedAfter = ShareStatus("protected-same-id")
Check(hostileOk == false and hostileWhy == "relay unauthorized"
        and hostileReceipt and hostileReceipt.outcome == "rejected"
        and hostileReceipt.terminal == true
        and protectedBefore and protectedAfter
        and protectedAfter.operationKey == protectedBefore.operationKey
        and protectedAfter.generation == protectedBefore.generation
        and protectedAfter.operationKey == protectedShare.operationKey
        and protectedAfter.outcome == "queued"
        and protectedAfter.terminal == false
        and ScalarOnly(hostileReceipt) and ScalarOnly(protectedAfter),
    "same-ID relay rejection replaced or terminalized the valid Share owner")
hostileReceipt.outcome = "caller-mutated"
local protectedReread = ShareStatus("protected-same-id")
Check(protectedReread and protectedReread.outcome == "queued"
        and protectedReread.generation == protectedBefore.generation,
    "mutating a same-ID rejected receipt corrupted the active Share owner")

-- The destructive reset owner must terminalize an admitted operation before
-- clearing its queues. Ordinary world entry above must never use this path.
FreshDb()
local resetShare = AdmitShare("reset-share")
resetShare.reason = "caller-mutated"
Sync.Init(Nexus.Codec, {})
local resetShareVisible = ShareStatus("reset-share")
Check(resetShareVisible and resetShareVisible.terminal == true
        and resetShareVisible.outcome == "reset"
        and resetShareVisible.reason == "reset"
        and resetShare.reason == "caller-mutated"
        and ScalarOnly(resetShareVisible),
    "queue reset silently orphaned an admitted Share")
Check((Sync.Stats().operationReset or 0) == 1,
    "reset Share terminal was not counted exactly once")

-- Aggregate stale-head cleanup retains just enough immutable operation
-- identity to terminate the exact Share without preserving raw wire bytes.
FreshDb()
H.joinedChannels = {}
local expiredShare = AdmitShare("expired-share")
local refreshesBeforeExpiry = viewRefreshes
Pump(121, 1)
local expiredShareVisible = ShareStatus("expired-share")
Check(expiredShareVisible and expiredShareVisible.terminal == true
        and expiredShareVisible.outcome == "expired"
        and expiredShareVisible.id == "expired-share"
        and expiredShare.outcome == "queued",
    "expired aggregate cleanup left the Share perpetually queued")
Check((Sync.Stats().operationExpired or 0) == 1,
    "expired Share terminal was absent from fixed Sync diagnostics")
Check(viewRefreshes == refreshesBeforeExpiry + 1,
    "terminal Share failure did not request one coalesced UI refresh")

-- Repeated local send failures retain the packet only through the fixed
-- transport attempt bound, then expose one dropped terminal.
FreshDb()
local realSendChatMessage = SendChatMessage
SendChatMessage = function() error("stage36 send failure") end
local droppedShare = AdmitShare("dropped-share")
Pump(2.2, 1); Pump(2.2, 1); Pump(2.2, 1)
SendChatMessage = realSendChatMessage
local droppedShareVisible = ShareStatus("dropped-share")
Check(droppedShareVisible and droppedShareVisible.terminal == true
        and droppedShareVisible.outcome == "dropped"
        and droppedShareVisible.reason == "retry exhausted"
        and droppedShare.outcome == "queued",
    "bounded send failure did not terminalize the admitted Share")
Check((Sync.Stats().operationDropped or 0) == 1,
    "dropped Share terminal was absent from fixed Sync diagnostics")

-- A server throttle notice may requeue a successful API attempt, but after
-- the transport attempt cap the same exact owner must end as
-- throttle-exhausted instead of remaining requeued forever.
FreshDb()
local throttledShare = AdmitShare("throttled-share")
Pump(1.2, 1)
Sync.NoteTransportNotice("Sending messages too quickly")
local firstRequeue = ShareStatus("throttled-share")
local firstThrottleStats = Sync.Stats()
Check(firstRequeue and firstRequeue.outcome == "requeued"
        and firstRequeue.terminal == false
        and firstThrottleStats.operationQueued == 1
        and firstThrottleStats.operationAttempted == 1
        and firstThrottleStats.operationRequeued == 1
        and firstThrottleStats.operationSentAttempted == 0
        and firstThrottleStats.operationAccepted == 0,
    "first throttle did not expose one exact nonterminal requeue")
for _ = 2, 3 do
    Pump(8.2, 1)
    Sync.NoteTransportNotice("Sending messages too quickly")
end
local throttledTerminal = ShareStatus("throttled-share")
local throttleStats = Sync.Stats()
Check(throttledTerminal and throttledTerminal.terminal == true
        and throttledTerminal.outcome == "throttle-exhausted"
        and throttledShare.outcome == "queued"
        and throttleStats.operationQueued == 1
        and throttleStats.operationAttempted == 3
        and throttleStats.operationRequeued == 2
        and throttleStats.operationSentAttempted == 0
        and throttleStats.operationThrottleExhausted == 1
        and throttleStats.operationAccepted == 0,
    "throttle retry exhaustion did not terminalize the exact Share")
Check((Sync.Stats().operationThrottleExhausted or 0) == 1,
    "throttle-exhausted Share was absent from fixed Sync diagnostics")

-- A later explicit user Share after terminal failure creates one new bounded
-- owner. Repeating the same action while that owner is active is idempotent.
H.joinedChannels = {wrbuildssync=7}
local retryOk, retryWhy, retryShare = Sync.BroadcastBuildSummary(
    ShareBuild("throttled-share"), {retryOnFull=true})
local controlAfterRetry = Sync.WorkState().control
local duplicateOk, duplicateWhy, duplicateShare = Sync.BroadcastBuildSummary(
    ShareBuild("throttled-share"), {retryOnFull=true})
Check(retryOk == true and retryWhy == "queued"
        and retryShare.generation ~= throttledTerminal.generation
        and retryShare.attempt == throttledTerminal.attempt + 1
        and retryShare.terminal == false,
    "explicit Share retry did not create a fresh bounded owner")
Check(duplicateOk == true and duplicateWhy == "already queued"
        and duplicateShare.generation == retryShare.generation
        and duplicateShare.operationKey == retryShare.operationKey
        and Sync.WorkState().control == controlAfterRetry,
    "repeated explicit Share retry was not idempotent")
duplicateShare.outcome = "caller-mutated"
Check(ShareStatus("throttled-share").outcome == "queued",
    "duplicate Share receipt mutated the active retry owner")
-- The prior throttle terminal still owns the established eight-second global
-- pacing pause. A user retry is admitted immediately but may not bypass it.
Pump(8.2, 1)
Pump(4.1, 1)
local retryShareVisible = ShareStatus("throttled-share")
Check(retryShareVisible and retryShareVisible.terminal == true
        and retryShareVisible.outcome == "sent-attempted"
        and retryShare.outcome == "queued",
    "explicit Share retry did not reach a truthful terminal attempt")

-- Pre-admission ownership is bounded too: a newer explicit Share may
-- supersede only the one unadmitted retry owner, malformed work is rejected,
-- and the final pending owner expires through the keyed maintenance callback.
FreshDb()
local limits = Sync.WorkState()
local filled = true
for index = 1, limits.maxControlQueue do
    local ok, why = Sync.BroadcastBuildSummary(
        ShareBuild("control-fill-" .. index), {retryOnFull=true})
    if not ok or why ~= "queued" then filled = false break end
end
Check(filled and Sync.WorkState().control == limits.maxControlQueue,
    "Share saturation fixture did not reach the fixed control cap")
local pendingOk, pendingWhy, supersededShare = Sync.BroadcastBuildSummary(
    ShareBuild("pending-superseded"), {retryOnFull=true})
local newerOk, newerWhy, newerPending = Sync.BroadcastBuildSummary(
    ShareBuild("pending-newer"), {retryOnFull=true})
local supersededVisible = ShareStatus("pending-superseded")
local newerPendingVisible = ShareStatus("pending-newer")
Check(pendingOk == false and pendingWhy == "sync queue full"
        and supersededShare.outcome == "retry-pending"
        and supersededVisible and supersededVisible.outcome == "superseded"
        and supersededVisible.terminal == true
        and newerOk == false and newerWhy == "sync queue full"
        and newerPending.outcome == "retry-pending"
        and newerPendingVisible
        and newerPendingVisible.outcome == "retry-pending",
    "unadmitted Share supersession was not exact and bounded")
local rejectedOk, _, rejectedShare = Sync.BroadcastBuildSummary({
    id="rejected-share",title="Rejected Share",author=player,
    ownerKey=player:lower() .. "@ebonhold",class="MAGE",
    postedAt=50001,lastModified=50001,isMine=true,
}, {retryOnFull=true})
local rejectedVisible = ShareStatus("rejected-share")
Check(rejectedOk == false and rejectedShare
        and rejectedShare.outcome == "rejected"
        and rejectedShare.terminal == true
        and rejectedVisible and rejectedVisible.outcome == "rejected"
        and ScalarOnly(rejectedVisible),
    "invalid explicit Share did not reach a rejected terminal")
local finalPendingOk, finalPendingWhy, finalPending =
    Sync.BroadcastBuildSummary(ShareBuild("pending-expiry"),
        {retryOnFull=true})
clock = clock + 121
if type(maintenanceCallback) == "function" then maintenanceCallback() end
local finalPendingVisible = ShareStatus("pending-expiry")
Check(finalPendingOk == false and finalPendingWhy == "sync queue full"
        and finalPending.outcome == "retry-pending"
        and finalPendingVisible
        and finalPendingVisible.outcome == "expired"
        and finalPendingVisible.terminal == true
        and (Sync.Stats().operationSuperseded or 0) == 2
        and (Sync.Stats().operationRejected or 0) == 1
        and (Sync.Stats().operationExpired or 0) == 1,
    "pending Share owners did not terminate through fixed outcomes")

-- Delete ownership uses the same terminal transport boundary. Zoning keeps
-- the tombstone packet admitted, expiry names the exact ID, and no raw packet
-- is retained in the defensive status.
FreshDb()
local deleteBuild = ShareBuild("zone-delete")
local deleteOk, deleteWhy, deleteStatus = Sync.BroadcastDelete(deleteBuild)
local deleteGeneration = deleteStatus and deleteStatus.generation
if deleteStatus then
    deleteStatus.outcome = "caller-mutated"
    deleteStatus.operationKey = "caller-mutated"
end
local deleteQueue = Sync.WorkState().sending
WorldEntry()
local deleteCopy = DeleteStatus("zone-delete")
Check(deleteOk == true and deleteWhy == "queued"
        and type(deleteStatus) == "table",
    "admitted delete did not return bounded ownership metadata")
Check(Sync.WorkState().sending == deleteQueue
        and deleteCopy and deleteCopy.outcome == "queued"
        and deleteCopy.generation == deleteGeneration
        and deleteCopy.operationKey ~= "caller-mutated",
    "world entry discarded or falsely terminalized admitted delete traffic")
H.joinedChannels = {}
Pump(301, 1)
deleteCopy = DeleteStatus("zone-delete")
Check(deleteStatus and deleteStatus.outcome == "caller-mutated"
        and deleteCopy and deleteCopy.terminal == true
        and deleteCopy.outcome == "expired"
        and deleteCopy.id == "zone-delete"
        and ScalarOnly(deleteCopy),
    "delete expiry lost exact bounded terminal ownership")
deleteCopy.outcome = "mutated-copy"
Check(DeleteStatus("zone-delete").outcome == "expired",
    "delete status getter exposed its live mutable owner")

-- Delete packets share the same generic terminal boundary for active
-- duplicates, explicit reset, successful attempts, and local retry exhaustion.
FreshDb()
local resetDeleteBuild = ShareBuild("reset-delete")
local resetDeleteOk, _, resetDelete = Sync.BroadcastDelete(resetDeleteBuild)
local resetDeleteDepth = Sync.WorkState().sending
local duplicateDeleteOk, duplicateDeleteWhy, duplicateDelete =
    Sync.BroadcastDelete(resetDeleteBuild)
Check(resetDeleteOk == true and duplicateDeleteOk == true
        and duplicateDeleteWhy == "already queued"
        and duplicateDelete.generation == resetDelete.generation
        and duplicateDelete.operationKey == resetDelete.operationKey
        and Sync.WorkState().sending == resetDeleteDepth,
    "active delete retry was not idempotent")
duplicateDelete.outcome = "caller-mutated"
Check(DeleteStatus("reset-delete").outcome == "queued",
    "duplicate delete receipt mutated the active owner")
Sync.Init(Nexus.Codec, {})
local resetDeleteVisible = DeleteStatus("reset-delete")
Check(resetDeleteVisible and resetDeleteVisible.outcome == "reset"
        and resetDeleteVisible.terminal == true
        and resetDelete.outcome == "queued"
        and duplicateDelete.outcome == "caller-mutated"
        and ScalarOnly(resetDeleteVisible)
        and (Sync.Stats().operationReset or 0) == 1,
    "admitted delete reset did not terminalize exactly once")

FreshDb()
local sentDeleteOk, _, sentDelete = Sync.BroadcastDelete(
    ShareBuild("sent-delete"))
Pump(1.2, 1)
local sentDeleteVisible = DeleteStatus("sent-delete")
Check(sentDeleteOk == true and sentDeleteVisible
        and sentDeleteVisible.outcome == "attempted"
        and sentDeleteVisible.terminal == false
        and sentDeleteVisible.sent == true
        and sentDelete.outcome == "queued",
    "delete API return skipped the bounded attribution window")
Pump(4.1, 1)
sentDeleteVisible = DeleteStatus("sent-delete")
Check(sentDeleteVisible and sentDeleteVisible.outcome == "sent-attempted"
        and sentDeleteVisible.terminal == true
        and sentDeleteVisible.accepted == false,
    "delete API return invented receipt or failed to settle")

FreshDb()
SendChatMessage = function() error("stage36 delete send failure") end
local failedDeleteOk, _, failedDelete = Sync.BroadcastDelete(
    ShareBuild("dropped-delete"))
Pump(2.2, 1); Pump(2.2, 1); Pump(2.2, 1)
SendChatMessage = realSendChatMessage
local failedDeleteVisible = DeleteStatus("dropped-delete")
Check(failedDeleteOk == true and failedDeleteVisible
        and failedDeleteVisible.outcome == "dropped"
        and failedDeleteVisible.reason == "retry exhausted"
        and failedDeleteVisible.terminal == true
        and failedDelete.outcome == "queued"
        and (Sync.Stats().operationDropped or 0) == 1,
    "delete retry exhaustion did not retain its exact terminal")

-- Multiple exact owners retain their original absolute expiry through world
-- transitions. Per-ID receipts remain independently queryable, and retrying A
-- after A/B terminalization cannot replace B's retained status.
FreshDb()
local savedJoinTemporary, savedJoinNamed =
    JoinTemporaryChannel, JoinChannelByName
JoinTemporaryChannel = function() end
JoinChannelByName = function() end
H.joinedChannels = {}
local multiShareA = AdmitShare("multi-share-a")
local multiShareB = AdmitShare("multi-share-b")
local multiDeleteAOk, _, multiDeleteA = Sync.BroadcastDelete(
    ShareBuild("multi-delete-a"))
local multiDeleteBOk, _, multiDeleteB = Sync.BroadcastDelete(
    ShareBuild("multi-delete-b"))
Check(multiDeleteAOk == true and multiDeleteBOk == true
        and ScalarOnly(multiShareA) and ScalarOnly(multiShareB)
        and ScalarOnly(multiDeleteA) and ScalarOnly(multiDeleteB),
    "multi-owner expiry fixture was not admitted as bounded receipts")

clock = clock + 60
WorldEntry()
Pump(61, 1)
local multiShareAExpired = ShareStatus("multi-share-a")
local multiShareBExpired = ShareStatus("multi-share-b")
local multiDeleteAQueued = DeleteStatus("multi-delete-a")
local multiDeleteBQueued = DeleteStatus("multi-delete-b")
Check(multiShareAExpired and multiShareAExpired.outcome == "expired"
        and multiShareBExpired and multiShareBExpired.outcome == "expired"
        and multiDeleteAQueued and multiDeleteAQueued.outcome == "queued"
        and multiDeleteBQueued and multiDeleteBQueued.outcome == "queued"
        and (Sync.Stats().operationExpired or 0) == 2,
    "world entry extended Share expiry or crossed exact operation owners")

clock = clock + 100
WorldEntry()
Pump(80, 1)
local multiDeleteAExpired = DeleteStatus("multi-delete-a")
local multiDeleteBExpired = DeleteStatus("multi-delete-b")
local multiExpiryStats = Sync.Stats()
Check(multiDeleteAExpired and multiDeleteAExpired.outcome == "expired"
        and multiDeleteBExpired and multiDeleteBExpired.outcome == "expired"
        and multiExpiryStats.operationQueued == 4
        and multiExpiryStats.operationAttempted == 0
        and multiExpiryStats.operationExpired == 4
        and multiExpiryStats.operationAccepted == 0
        and ScalarOnly(multiShareAExpired)
        and ScalarOnly(multiShareBExpired)
        and ScalarOnly(multiDeleteAExpired)
        and ScalarOnly(multiDeleteBExpired),
    "aggregate expiry lost exact multi-owner identities or counters")

JoinTemporaryChannel, JoinChannelByName =
    savedJoinTemporary, savedJoinNamed
H.joinedChannels = {wrbuildssync=7}
local retryAOk, retryAWhy, retryAReceipt = Sync.BroadcastBuildSummary(
    ShareBuild("multi-share-a"), {retryOnFull=true})
local multiShareBRetained = ShareStatus("multi-share-b")
Check(retryAOk == true and retryAWhy == "queued"
        and retryAReceipt.attempt == multiShareAExpired.attempt + 1
        and retryAReceipt.generation ~= multiShareAExpired.generation
        and multiShareBRetained
        and multiShareBRetained.generation == multiShareBExpired.generation
        and multiShareBRetained.outcome == "expired",
    "interleaved A/B retry did not retain exact per-ID attempt ownership")
retryAReceipt.reason = "caller-mutated"
Check(ShareStatus("multi-share-a").reason == "transport admitted",
    "explicit A retry receipt mutated its live operation owner")
Pump(1.2, 1); Pump(4.1, 1)
local retryAVisible = ShareStatus("multi-share-a")
multiShareBRetained = ShareStatus("multi-share-b")
Check(retryAVisible and retryAVisible.outcome == "sent-attempted"
        and retryAVisible.attempt == 2
        and multiShareBRetained
        and multiShareBRetained.outcome == "expired"
        and multiShareBRetained.generation == multiShareBExpired.generation,
    "retry-A completion overwrote retained B ownership")

-- The opt-in Peer Test surface receives only sanitized scalar operation
-- outcomes. It never receives the Share title, description, or wire text.
FreshDb()
local peerDebug = Nexus.PeerDebug
local peerStarted = peerDebug and peerDebug.Start()
local peerReceipt = AdmitShare("peer-diag")
Pump(1.2, 1); Pump(4.1, 1)
local peerStatus = ShareStatus("peer-diag")
local peerStats = peerDebug and peerDebug.Stats() or {}
local peerCounters = peerStats.counters or {}
local peerReport = peerDebug and peerDebug.Report() or ""
Check(peerStarted == true and peerStatus
        and peerStatus.outcome == "sent-attempted"
        and ScalarOnly(peerReceipt) and ScalarOnly(peerStatus)
        and peerCounters.operation_queued == 1
        and peerCounters.operation_attempted == 1
        and peerCounters.operation_sent_attempted == 1
        and peerReport:find("operation=share", 1, true)
        and peerReport:find("id=peer-diag", 1, true)
        and peerReport:find("outcome=sent-attempted", 1, true)
        and not peerReport:find("Stage 36 Share", 1, true)
        and not peerReport:find("terminal fixture", 1, true)
        and not peerReport:find("WLBI|", 1, true),
    "Peer Test operation outcome was absent, unbounded, or retained payload")
if peerDebug then peerDebug.Stop() end

-- A partially received real WLRB transfer survives an ordinary world entry
-- and commits after the remaining encoded chunks arrive.
FreshDb()
player = "ChunkSender"
local echoes = {}
for index = 1, 60 do
    echoes[index] = {spellId=740000 + index,quality=index % 4,stacks=1}
end
local chunkBuild = {
    id="zoned-chunks",title="Zoned Chunks",author="ChunkSender",
    ownerKey="chunksender@ebonhold",class="MAGE",echoes=echoes,
    postedAt=60001,lastModified=60001,isMine=true,
}
H.sentChatMessages = {}
Check(Sync.BroadcastBuild(chunkBuild) == true,
    "chunked sender fixture was not admitted")
Pump(1.2, 120)
local chunks = {}
for _, message in ipairs(H.sentChatMessages) do
    if message.text:find("^WLRB|") then chunks[#chunks + 1] = message end
end
Check(#chunks > 1, "chunked world-transition fixture was not multi-packet")

player = "ChunkReceiver"
FreshDb()
Sync.RequestSync()
Pump(1.2, 1)
if chunks[1] then Sync.HandleIncoming(chunks[1].text, "ChunkSender") end
local inflightBefore = Sync.WorkState().buildInflight
WorldEntry()
local inflightAfter = Sync.WorkState().buildInflight
for index = 2, #chunks do
    Sync.HandleIncoming(chunks[index].text, "ChunkSender")
end
local received = Nexus.BuildCatalog.Get("zoned-chunks")
Check(inflightBefore == 1 and inflightAfter == 1,
    "world entry discarded the admitted partial WLRB transfer")
Check(received and received.echoes and #received.echoes == 60,
    "remaining WLRB chunks did not complete after world entry")

if #failures > 0 then
    error("EXPECTED RED [Stage 36.2 Sync lifecycle terminals]:\n - "
        .. table.concat(failures, "\n - "))
end

print(string.format(
    "Stage 36.2 Sync world transitions and terminals: checks=%d -- OK",
    checks))
