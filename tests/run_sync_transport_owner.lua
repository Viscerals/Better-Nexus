-- Characterize the extracted durable outbound Sync transport owner.
Nexus = {}
NexusDB = { sentinel = "keep" }
ProjectEbonhold = { sentinel = "keep" }

dofile("core/SyncTransport.lua")

local Factory = assert(Nexus.SyncInternals.Transport)
local originalDb = NexusDB
local originalGame = ProjectEbonhold

local function NewHarness(options)
    options = options or {}
    local clock = options.clock or 100
    local channel = options.channel
    if channel == nil then channel = 7 end
    local sent, logs, filters, observed = {}, {}, {}, {}
    local failSends = tonumber(options.failSends) or 0
    local attempts = 0
    local stats = {}
    local transport = Factory.New({
        maxBulk=options.maxBulk or 8192,
        maxControl=options.maxControl or 512,
        responseHeadroom=options.responseHeadroom or 8,
        chatLimit=options.chatLimit or 255,
        sendInterval=options.sendInterval or 0,
        slowInterval=options.slowInterval or 1.75,
        throttlePause=options.throttlePause or 8,
        throttleSlowTime=options.throttleSlowTime or 45,
        now=function() return clock end,
        escapedLen=function(payload)
            return #(payload:gsub("|", "||"))
        end,
        log=function(category, formatText, ...)
            logs[#logs + 1] = {
                category=category,
                text=string.format(formatText, ...),
            }
        end,
        stats=stats,
        resolveChannel=function() return channel end,
        channelLabel=function() return channel end,
        sendChat=function(payload, kind, language, target)
            attempts = attempts + 1
            if attempts <= failSends then error("temporary send failure") end
            sent[#sent + 1] = {
                payload=payload, kind=kind, language=language, target=target,
            }
        end,
        addMessageFilter=function(event, filter)
            filters[#filters + 1] = { event=event, filter=filter }
        end,
        observe=function(kind, fields, metadata)
            observed[#observed + 1] = {
                kind=kind,fields=fields,metadata=metadata,
            }
        end,
    })
    return {
        transport=transport, sent=sent, logs=logs, filters=filters,
        observed=observed,stats=stats,
        SetClock=function(value) clock = value end,
        SetChannel=function(value) channel = value end,
        Attempts=function() return attempts end,
    }
end

-- Production caps: reach the reported 8190/8192 boundary without draining.
local full = NewHarness()
local T = full.transport
for index = 1, 8190 do
    local ok, why = T.Enqueue(string.format("B|%05d", index))
    assert(ok == true and why == nil, "bulk admission failed before saturation")
end
local snapshot = T.Snapshot()
assert(snapshot.bulk == 8190 and snapshot.control == 0
    and snapshot.maxBulk == 8192 and snapshot.maxControl == 512,
    "production queue snapshot drifted near saturation")
assert(T.BulkFree() == 2 and T.Backpressured() == true,
    "8190/8192 does not activate responder backpressure")
assert(T.CanAdmit(2) == true and T.CanAdmit(3) == false,
    "pre-work atomic admission probe drifted")

local accepted, why = T.EnqueueBatch({ "B|08191", "B|08192" })
assert(accepted == true and why == nil and T.Snapshot().bulk == 8192,
    "final exact-capacity batch was not admitted atomically")
local overflow, overflowWhy = T.Enqueue("B|overflow")
assert(overflow == false and overflowWhy == "sync queue full",
    "full bulk queue did not reject newest packet")
overflow, overflowWhy = T.EnqueueBatch({ "B|extra1", "B|extra2" })
assert(overflow == false and overflowWhy == "sync queue full",
    "full bulk queue did not reject newest batch")
assert(T.Snapshot().bulk == 8192
    and full.stats.queueOverflowRejected == 2,
    "overflow changed admitted queue data or counters")

-- The independent control cap remains durable. Control gets bounded priority,
-- while one old bulk packet progresses after every four control attempts.
for index = 1, 512 do
    assert(T.EnqueueControl(string.format("C|%03d", index)) == true,
        "control admission failed before its independent cap")
end
local controlOverflow, controlWhy = T.EnqueueControl("C|overflow")
assert(controlOverflow == false and controlWhy == "sync queue full",
    "full control queue did not reject newest packet")
snapshot = T.Snapshot()
assert(snapshot.bulk == 8192 and snapshot.control == 512
    and snapshot.outbound == 8704,
    "saturated bulk/control snapshot drifted")

for _ = 1, 8704 do T.Pump(0) end
assert(#full.sent == 8704 and T.HasPending() == false,
    "accepted saturated queue did not drain exactly once")
assert(full.sent[1].payload == "C||001"
    and full.sent[4].payload == "C||004"
    and full.sent[5].payload == "B||00001"
    and full.sent[640].payload == "B||00128"
    and full.sent[641].payload == "B||00129"
    and full.sent[8704].payload == "B||08192",
    "control priority or FIFO order drifted")
assert(full.stats.sent == 8704,
    "successful transport counter drifted")

-- Invalid batches are rejected atomically before any member is admitted.
local invalid = NewHarness({ maxBulk=4, maxControl=2, chatLimit=12 })
local invalidT = invalid.transport
assert(invalidT.Enqueue("ok|1") == true)
local depthBefore = invalidT.Snapshot().bulk
local invalidOk, invalidWhy = invalidT.EnqueueBatch({ "ok|2", "||||||||" })
assert(invalidOk == false and invalidWhy == "invalid packet"
    and invalidT.Snapshot().bulk == depthBefore,
    "invalid batch partially entered the durable queue")
assert(invalid.stats.oversizeDropped == 1,
    "oversize admission rejection counter drifted")

-- Missing channels and send failures retain the exact head for later retry.
local retry = NewHarness({ maxBulk=4, maxControl=2, failSends=1 })
local retryT = retry.transport
retry.SetChannel(false)
assert(retryT.Enqueue("R|one") == true)
retryT.Pump(0)
assert(retry.Attempts() == 0 and retryT.Snapshot().bulk == 1,
    "missing channel attempted or dropped queued data")
retry.SetChannel(7)
retryT.Pump(0)
assert(retry.Attempts() == 1 and retryT.Snapshot().bulk == 1
    and retryT.ThrottleRemaining() == 2,
    "send failure did not retain the exact queue head")
retryT.Pump(0)
assert(retry.Attempts() == 1 and retryT.Snapshot().bulk == 1,
    "failure pause retried before its deadline")
retry.SetClock(102.1)
retryT.Pump(0)
assert(retry.Attempts() == 2 and #retry.sent == 1
    and retry.sent[1].payload == "R||one"
    and retryT.Snapshot().bulk == 0,
    "retained packet did not resume exactly once")

-- Control priority must not borrow metadata from the bulk head. Every packet
-- receives immutable transport metadata owned by the exact selected packet.
local metadataOrder = NewHarness({ maxBulk=2, maxControl=2 })
local metadataMarker = { requestId="bulk-owner" }
assert(metadataOrder.transport.Enqueue("M|bulk", metadataMarker))
assert(metadataOrder.transport.EnqueueControl("M|control"))
metadataOrder.transport.Pump(0)
metadataOrder.transport.Pump(0)
assert(metadataOrder.observed[1].metadata.queueClass == "control"
    and metadataOrder.observed[1].metadata.requestId == nil
    and metadataOrder.observed[2].metadata.requestId == "bulk-owner"
    and metadataOrder.observed[2].metadata ~= metadataMarker,
    "control priority attributed completion to the bulk packet metadata")

-- Notices apply only after this transport attempted a send. Waiting notices
-- are hidden; other throttle notices pause transport but remain visible.
local notices = NewHarness({ maxBulk=4, maxControl=2 })
local noticeT = notices.transport
assert(noticeT.NoteTransportNotice("Waiting to send") == false,
    "unattributed waiting notice was hidden")
assert(noticeT.Enqueue("N|one") == true)
noticeT.Pump(0)
assert(noticeT.NoteTransportNotice("Sending messages too quickly") == false
    and noticeT.ThrottleRemaining() == 8,
    "attributed visible throttle notice semantics drifted")
assert(noticeT.NoteTransportNotice("Message is queued") == true,
    "attributed waiting notice was not hidden")

-- Filter installation remains process-idempotent across session resets.
noticeT.InstallFilters()
noticeT.InstallFilters()
assert(#notices.filters == 2,
    "transport filters were not installed exactly once per event")
noticeT.Reset()
noticeT.InstallFilters()
snapshot = noticeT.Snapshot()
assert(#notices.filters == 2 and snapshot.bulk == 0
    and snapshot.control == 0 and noticeT.ThrottleRemaining() == 0,
    "reset changed filter ownership or retained session queue state")

-- Pacing remains one packet per eligible pump.
local paced = NewHarness({ maxBulk=4, maxControl=2, sendInterval=1.1 })
assert(paced.transport.Enqueue("P|one") == true)
assert(paced.transport.Enqueue("P|two") == true)
paced.transport.Pump(1.0)
assert(#paced.sent == 0, "pacing sent before the interval")
paced.transport.Pump(0.1)
assert(#paced.sent == 1 and paced.transport.Snapshot().bulk == 1,
    "pacing did not send exactly one eligible packet")
paced.transport.Pump(1.1)
assert(#paced.sent == 2 and paced.transport.Snapshot().bulk == 0,
    "pacing did not resume FIFO progress")

local function Read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local syncSource = Read("core/Sync.lua")
local transportSource = Read("core/SyncTransport.lua")
for _, stale in ipairs({
    "local sendQueue", "local controlQueue", "local ticker",
    "local throttlePauseUntil", "local throttleSlowUntil",
    "local lastTransportAttempt", "local transportFilterInstalled",
}) do
    assert(not syncSource:find(stale, 1, true),
        "Sync retained old transport owner: " .. stale)
end
for _, owned in ipairs({
    "local bulk, bulkHead, bulkTail",
    "local control, controlHead, controlTail",
    "local function NewPacket(", "local function CopyMetadata(",
    "function T.Enqueue(", "function T.EnqueueBatch(",
    "function T.EnqueueControl(", "function T.Pump(",
    "function T.NoteTransportNotice(", "function T.Reset(",
}) do
    assert(transportSource:find(owned, 1, true),
        "SyncTransport does not own " .. owned)
end
for _, forbidden in ipairs({
    "BuildCatalog", "BuildHashCache", "Codec.JSON", "Base64",
    "ChunkBuild", "ownerKey", "tombstone", "NexusDB",
    "ProjectEbonhold", "GameAdapter",
}) do
    assert(not transportSource:find(forbidden, 1, true),
        "SyncTransport crossed frozen owner boundary: " .. forbidden)
end
assert(syncSource:find("Transport.EnqueueBatch(prepared.messages,", 1, true),
    "responder admissions do not use the sole transport owner")
assert(syncSource:find("Transport.BulkFree()", 1, true),
    "pre-work backpressure does not use the sole transport owner")
assert(NexusDB == originalDb and NexusDB.sentinel == "keep"
    and ProjectEbonhold == originalGame and ProjectEbonhold.sentinel == "keep",
    "transport tests mutated persistence or gameplay state")

print("durable Sync transport ownership, saturation, order, and retry -- OK")
