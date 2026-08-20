-- Outbound Sync must revalidate the named channel immediately before every
-- send, retain packets while disconnected, and reject newest packets when a
-- bounded queue is full without overwriting older queued traffic.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")

local Sync = Nexus.Sync
local clock = 1000
GetTime = function() return clock end
UnitName = function() return "Alice" end
NexusDB = { communityBuilds={}, syncTombstones={} }
Sync.Init(Nexus.Codec, {})

local function Pump(steps)
    for _ = 1, steps do
        clock = clock + 0.2
        Sync.OnUpdate(0.2)
    end
end

-- The cached slot began as 1. Before the queued packet is sent, the sync
-- channel moves to 7 and General takes slot 1. Raw Sync traffic must follow
-- wrbuildssync, never the stale numeric slot.
H.sentChatMessages = {}
assert(Sync.BroadcastDps("renumbered", "Alice", 1000, 80, "dummy"))
H.joinedChannels[Sync.ChannelName()] = 7
H.joinedChannels.general = 1
Pump(6)
assert(#H.sentChatMessages == 1, "renumbered packet was not sent")
assert(H.sentChatMessages[1].target == 7,
    "cached Sync slot sent raw traffic to a different channel")

-- If the named channel cannot be found or rejoined, the packet stays queued.
assert(Sync.BroadcastDps("retained", "Alice", 1001, 80, "dummy"))
H.joinedChannels = {}
local oldTemporary, oldNamed = JoinTemporaryChannel, JoinChannelByName
JoinTemporaryChannel = function() end
JoinChannelByName = function() end
local sentBefore = #H.sentChatMessages
Pump(6)
local waiting = Sync.WorkState()
assert(#H.sentChatMessages == sentBefore,
    "packet was sent without a validated wrbuildssync channel")
assert(waiting.outbound == 1,
    "packet was discarded when channel validation/reconnect failed")

-- Discovery of the channel at a new slot releases the retained packet.
H.joinedChannels[Sync.ChannelName()] = 9
JoinTemporaryChannel, JoinChannelByName = oldTemporary, oldNamed
Pump(6)
assert(#H.sentChatMessages == sentBefore + 1
    and H.sentChatMessages[#H.sentChatMessages].target == 9,
    "retained packet did not use the newly validated channel slot")
assert(Sync.WorkState().outbound == 0,
    "retained packet remained queued after a successful send")

-- Saturate the documented bulk queue. The explicit policy is to preserve
-- already queued packets and reject the newest packet/batch with a visible
-- counter and false return value.
Sync.Init(Nexus.Codec, {})
H.sentChatMessages = {}
local limits = Sync.WorkState()
assert(type(limits.maxOutboundQueue) == "number"
    and limits.maxOutboundQueue > 0,
    "Sync does not expose an explicit outbound queue bound")
for i = 1, limits.maxOutboundQueue - 1 do
    assert(Sync.BroadcastDps("queued-" .. i, "Alice", 2000 + i, 80, "dummy"),
        "outbound queue rejected a packet before its documented limit")
end
local batchEchoes = {}
for i = 1, 24 do
    batchEchoes[i] = { spellId=200000 + i, quality=3, stacks=2 }
end
assert(not Sync.BroadcastBuild({ id="atomic-batch", title="Atomic Batch",
    author="Alice", class="MAGE", lastModified=1, postedAt=1,
    description=string.rep("bounded ", 20), echoes=batchEchoes }),
    "multi-chunk batch partially entered a nearly full queue")
assert(Sync.WorkState().sending == limits.maxOutboundQueue - 1,
    "rejected multi-chunk batch partially mutated the queue")
assert(Sync.BroadcastDps("queued-final", "Alice", 999998, 80, "dummy"),
    "final available queue slot was not usable after atomic batch rejection")
assert(not Sync.BroadcastDps("rejected-newest", "Alice", 999999, 80, "dummy"),
    "outbound queue silently exceeded its documented limit")
local full = Sync.WorkState()
assert(full.sending == limits.maxOutboundQueue,
    "outbound overflow changed or overwrote the bounded queue")
assert((Sync.Stats().queueOverflowRejected or 0) >= 1,
    "outbound overflow was not recorded explicitly")

Pump(6)
assert(H.sentChatMessages[1]
    and H.sentChatMessages[1].text:find("queued%-1", 1, false),
    "queue overflow overwrote the oldest retained packet")

-- A responder must never publish a WLLC claim when the corresponding WLRB
-- payload was rejected by bulk backpressure. Keep the response pending until
-- capacity is available instead of suppressing every other responder.
Sync.Init(Nexus.Codec, {})
NexusDB.communityBuilds["claim-build"] = {
    id="claim-build", title="Claim Build", author="Alice", class="MAGE",
    lastModified=10, postedAt=10,
    echoes={{spellId=200100, quality=3, stacks=1}},
}
limits = Sync.WorkState()
for i = 1, limits.maxOutboundQueue do
    assert(Sync.BroadcastDps("claim-fill-" .. i, "Alice", 3000 + i,
        80, "dummy"), "failed to fill claim backpressure queue")
end
assert(Sync.HandleIncoming("WLLQ|Requester|claim-build", "Requester"),
    "valid on-demand loadout request was rejected")
assert(Sync.WorkState().pendingLoadouts == 1,
    "on-demand loadout response was not scheduled")
local oldTemporary2, oldNamed2 = JoinTemporaryChannel, JoinChannelByName
H.joinedChannels = {}
JoinTemporaryChannel = function() end
JoinChannelByName = function() end
Sync.OnUpdate(2)
local rejectedResponse = Sync.WorkState()
assert(rejectedResponse.control == 0,
    "loadout claim was queued without an admitted build payload")
assert(rejectedResponse.pendingLoadouts == 1,
    "backpressured loadout response was not retained for retry")
for _ = 1, 40 do
    clock = clock + 1
    Sync.OnUpdate(1)
end
assert(Sync.WorkState().pendingLoadouts == 0,
    "queue-full retries kept an unproductive loadout alive past its TTL")
JoinTemporaryChannel, JoinChannelByName = oldTemporary2, oldNamed2
H.joinedChannels[Sync.ChannelName()] = 5
for _ = 1, 10 do
    clock = clock + 1.2
    Sync.OnUpdate(1.2)
end
assert(Sync.HandleIncoming("WLLQ|Requester|claim-build", "Requester"),
    "fresh loadout retry was rejected after capacity became available")
for _ = 1, 80 do
    clock = clock + 0.2
    Sync.OnUpdate(0.2)
    if Sync.WorkState().pendingLoadouts == 0 then break end
end
assert(Sync.WorkState().pendingLoadouts == 0,
    "fresh loadout retry did not complete after capacity became available")

-- Bucket election has the same invariant: WLBC may only be published after
-- every WLRB packet in that bucket has been admitted. Leave room for one
-- packet while scheduling two one-packet builds in the same bucket: retain
-- the admitted first payload, then resume with the second without duplication.
Sync.Init(Nexus.Codec, {})
local function TestBuildBucket(id)
    local hash = 5381
    for i = 1, #id do hash = ((hash * 33) + id:byte(i)) % 2147483648 end
    return (hash % 8) + 1
end
local firstBucketId = "bucket-build-a"
local secondBucketId
for i = 1, 100 do
    local candidate = "bucket-build-" .. i
    if TestBuildBucket(candidate) == TestBuildBucket(firstBucketId) then
        secondBucketId = candidate
        break
    end
end
assert(secondBucketId, "test setup could not find two ids in one build bucket")
NexusDB.communityBuilds = {
    [firstBucketId] = {
        id=firstBucketId, title="Bucket Build A", author="Alice", class="MAGE",
        lastModified=11, postedAt=11,
        echoes={{spellId=200101, quality=3, stacks=1}},
    },
    [secondBucketId] = {
        id=secondBucketId, title="Bucket Build B", author="Alice", class="MAGE",
        lastModified=12, postedAt=12,
        echoes={{spellId=200102, quality=3, stacks=1}},
    },
}
limits = Sync.WorkState()
for i = 1, limits.maxOutboundQueue - 1 do
    assert(Sync.BroadcastDps("bucket-fill-" .. i, "Alice", 4000 + i,
        80, "dummy"), "failed to fill bucket backpressure queue")
end
local emptyBuckets = "0,0,0,0,0,0,0,0"
assert(Sync.HandleIncoming("WLRQ|Requester|" .. emptyBuckets .. "|0|req-bucket",
    "Requester"), "valid bucket reconciliation request was rejected")
assert(Sync.WorkState().pendingResponses == 1,
    "bucket reconciliation response was not scheduled")
local oldTemporary3, oldNamed3 = JoinTemporaryChannel, JoinChannelByName
H.joinedChannels = {}
JoinTemporaryChannel = function() end
JoinChannelByName = function() end
Sync.OnUpdate(6)
local rejectedBucket = Sync.WorkState()
assert(rejectedBucket.control == 0,
    "bucket claim was queued without a complete admitted payload")
assert(rejectedBucket.pendingResponses == 1,
    "backpressured bucket response was not retained for retry")
assert(rejectedBucket.sending == limits.maxOutboundQueue - 1,
    "backpressured response changed already admitted queue data")
JoinTemporaryChannel, JoinChannelByName = oldTemporary3, oldNamed3
H.joinedChannels[Sync.ChannelName()] = 6
for _ = 1, 120 do
    clock = clock + 0.2
    Sync.OnUpdate(0.2)
    if Sync.WorkState().pendingResponses == 0 then break end
end
assert(Sync.WorkState().pendingResponses == 0,
    "bucket response did not resume after capacity became available")
assert((Sync.Stats().overlaySent or 0) == 2,
    "bucket response duplicated or omitted admitted build candidates")

-- A permanently invalid legacy row must not roll back or indefinitely block
-- a valid build in the same bucket. Incomplete ordinary evidence is excluded
-- from both the represented hash and candidate set, so the complete control
-- may transmit and claim normally without putting the invalid row on wire.
local validId = "sendable-bucket-build"
local invalidKey
for i = 1, 100 do
    local candidate = "unsendable-bucket-" .. i
    if TestBuildBucket(candidate) == TestBuildBucket(validId) then
        invalidKey = candidate
        break
    end
end
assert(invalidKey, "test setup could not colocate an unsendable row")
NexusDB = {communityBuilds={
    [validId] = {
        id=validId, title="Sendable", author="Alice", class="MAGE",
        lastModified=21, postedAt=21,
        echoes={{spellId=200201, quality=3, stacks=1}},
    },
    [invalidKey] = {
        id="invalid|wire-id", title="Unsendable", author="Alice",
        class="MAGE", lastModified=22, postedAt=22,
        fingerprintHash="1",
    },
},syncTombstones={}}
Sync.Init(Nexus.Codec, {})
H.sentChatMessages = {}
H.joinedChannels = {[Sync.ChannelName()]=8}
assert(Sync.HandleIncoming("WLRQ|Requester|" .. emptyBuckets
    .. "|0|req-unsendable", "Requester"),
    "mixed sendable/unsendable bucket request was rejected")
Pump(80)
local mixedBucket = Sync.WorkState()
local validWire, invalidWire = 0, 0
for _, message in ipairs(H.sentChatMessages) do
    if message.text:find("^WLRB|") then
        if message.text:find("|"..validId.."|",1,true) then
            validWire = validWire + 1
        end
        if message.text:find("invalid|wire%-id",1,false) then
            invalidWire = invalidWire + 1
        end
    end
end
assert(mixedBucket.pendingResponses == 0 and validWire == 1,
    "incomplete row blocked the valid build sharing its bucket")
assert(invalidWire == 0,
    "incomplete ordinary row entered the represented Sync candidate set")

-- A locally authored delete rejected at the outbound queue limit must remain
-- pending and use the first capacity that becomes available. Otherwise the
-- local row is gone before online peers receive its tombstone.
NexusDB.communityBuilds = {}
NexusDB.syncTombstones = {}
Sync.Init(Nexus.Codec, {})
limits = Sync.WorkState()
for i = 1, limits.maxOutboundQueue do
    assert(Sync.BroadcastDps("delete-fill-" .. i, "Alice", 5000 + i,
        80, "dummy"), "failed to fill delete backpressure queue")
end
local immediateDelete, deleteWhy = Sync.BroadcastDelete({
    id="delete-backpressure", title="Delete Backpressure", author="Alice",
    lastModified=30, postedAt=30,
    echoes={{spellId=200301, quality=3, stacks=1}},
})
assert(not immediateDelete and deleteWhy == "queued for retry",
    "full-queue delete was not retained for retry")
assert(Sync.WorkState().pendingDeletes == 1,
    "retained delete was not exposed as pending work")
assert(NexusDB.syncTombstones["delete-backpressure"].pending == true,
    "retained delete was not persisted across reloads")
H.joinedChannels[Sync.ChannelName()] = 7
clock = clock + 1.2
Sync.OnUpdate(1.2) -- observe the full queue, then drain one packet
clock = clock + 1.2
Sync.OnUpdate(1.2) -- admit the pending delete, then drain one packet
local retriedDelete = Sync.WorkState()
assert(retriedDelete.pendingDeletes == 0,
    "retained delete did not clear after queue admission")
assert(retriedDelete.sending == limits.maxOutboundQueue - 1,
    "retained delete did not use the first freed queue slot")
assert(NexusDB.syncTombstones["delete-backpressure"].pending == nil,
    "admitted delete left stale persisted retry state")

-- A delete that never sees a free slot still owns a fixed terminal deadline.
-- Keep the established bulk fixture continuously full by replacing every
-- packet drained by Transport; elapsed wall time, not queue opportunity, must
-- clear both transient and persisted retry ownership after 300 seconds.
while Sync.WorkState().sending < limits.maxOutboundQueue do
    local index = Sync.WorkState().sending + 1
    assert(Sync.BroadcastDps("delete-expiry-fill-" .. index, "Alice",
        6000 + index, 80, "dummy"),
        "failed to restore continuous delete saturation")
end
local expiredBefore = Sync.Stats().operationExpired or 0
local expiryOk, expiryWhy = Sync.BroadcastDelete({
    id="delete-continuous-saturation", title="Delete Continuous Saturation",
    author="Alice", lastModified=31, postedAt=31,
    echoes={{spellId=200302, quality=3, stacks=1}},
})
assert(not expiryOk and expiryWhy == "queued for retry",
    "continuously saturated delete did not enter bounded retry ownership")
local expiryStarted = clock
local refillSequence = 0
while clock - expiryStarted <= 301 do
    clock = clock + 1.2
    Sync.OnUpdate(1.2)
    while Sync.WorkState().sending < limits.maxOutboundQueue do
        refillSequence = refillSequence + 1
        assert(Sync.BroadcastDps("delete-expiry-refill-" .. refillSequence,
            "Alice", 7000 + refillSequence, 80, "dummy"),
            "continuous delete saturation could not refill a freed slot")
    end
end
local expiredDelete = Sync.GetDeleteStatus("delete-continuous-saturation")
assert(expiredDelete and expiredDelete.terminal == true
        and expiredDelete.outcome == "expired"
        and expiredDelete.reason == "delete retry expired",
    "continuously saturated delete did not reach its exact expiry terminal")
assert((Sync.Stats().operationExpired or 0) == expiredBefore + 1,
    "continuously saturated delete expiry was not counted exactly once")
assert(Sync.WorkState().pendingDeletes == 0,
    "expired continuously saturated delete retained transient pending work")
assert(NexusDB.syncTombstones["delete-continuous-saturation"]
        and NexusDB.syncTombstones["delete-continuous-saturation"].pending == nil,
    "expired continuously saturated delete retained its persisted pending marker")

-- Persisted delete discovery is sliced behind the fixed recovery cap. Capture
-- only the public table key returned by Lua's iterator during Init, remove that
-- tombstone through BuildCatalog, then prove the next slice neither feeds a
-- removed key back to Lua 5.1's next() nor strands later persisted work.
local recoveryCap = assert(limits.maxRecoveryQueue,
    "Sync does not expose its persisted delete discovery bound")
local persistedExtra = 40
NexusDB = {communityBuilds={},syncTombstones={}}
for index = 1, recoveryCap + persistedExtra do
    NexusDB.syncTombstones[string.format("persisted-delete-%04d", index)] = {
        stamp=80000 + index,author="Alice",pending=true,
    }
end
local discoveryTable = NexusDB.syncTombstones
local realNext = next
local capturedCursor
next = function(target, key)
    local found, value = realNext(target, key)
    if target == discoveryTable and found ~= nil then capturedCursor = found end
    return found, value
end
local initOk, initError = pcall(Sync.Init, Nexus.Codec, {})
next = realNext
assert(initOk, "persisted delete discovery setup failed: "
    .. tostring(initError))
assert(capturedCursor and discoveryTable[capturedCursor]
        and Sync.WorkState().pendingDeletes == recoveryCap
        and Sync.WorkState().pendingDeleteDiscovery == 1,
    "persisted delete discovery did not stop at its public fixed bound")
assert(Nexus.BuildCatalog.ClearTombstone(capturedCursor),
    "persisted delete cursor fixture could not remove the sliced key")
H.joinedChannels[Sync.ChannelName()] = 7
local discoveryOk, discoveryError = pcall(function()
    local budget = (recoveryCap + persistedExtra) * 2
    for _ = 1, budget do
        clock = clock + 1.2
        Sync.OnUpdate(1.2)
        local work = Sync.WorkState()
        if work.pendingDeletes == 0
            and work.pendingDeleteDiscovery == 0 then return end
    end
end)
assert(discoveryOk, "removed persisted delete cursor broke Lua 5.1 discovery: "
    .. tostring(discoveryError))
local pendingPersisted = 0
for _, tomb in pairs(NexusDB.syncTombstones) do
    if type(tomb) == "table" and tomb.pending then
        pendingPersisted = pendingPersisted + 1
    end
end
local discoveryWork = Sync.WorkState()
assert(discoveryWork.pendingDeletes == 0
        and discoveryWork.pendingDeleteDiscovery == 0
        and pendingPersisted == 0,
    "bounded persisted delete discovery stranded work after cursor removal")

-- DPS bucket broadcasters report partial queue admission separately from the
-- number of records queued. A partial result must retain the pending bucket
-- for retry instead of treating it as complete.
Sync.Init(Nexus.Codec, {})
NexusDB.communityBuilds = {}
local partialCalls = 0
Nexus.DpsCapture = {
    GetSyncHash = function() return "abc,0,0,0,0,0,0,0" end,
    BroadcastAllBuildBests = function()
        partialCalls = partialCalls + 1
        return 1, false
    end,
}
local localBuildHash = Sync.GetCompatibilityHashes()
assert(Sync.HandleIncoming("WLRQ|Requester|" .. localBuildHash .. "|"
    .. emptyBuckets .. "|req-dps-partial", "Requester"),
    "valid DPS reconciliation request was rejected")
Sync.OnUpdate(6)
Sync.OnUpdate(6)
assert(partialCalls >= 1, "DPS bucket broadcaster was not invoked")
assert(Sync.WorkState().pendingResponses == 1,
    "partially admitted DPS bucket was not retained for retry")

print("sync validation, retry retention, overflow, and claim safety -- OK")
