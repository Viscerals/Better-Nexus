-- Nexus: durable outbound Sync queue admission and paced channel transport.

Nexus = Nexus or {}
if type(Nexus.SyncInternals) ~= "table" then Nexus.SyncInternals = {} end

local Transport = {}
Nexus.SyncInternals.Transport = Transport

function Transport.New(options)
    options = options or {}
    local maxBulk = assert(options.maxBulk, "maxBulk required")
    local maxControl = assert(options.maxControl, "maxControl required")
    local responseHeadroom = assert(options.responseHeadroom,
        "responseHeadroom required")
    local chatLimit = assert(options.chatLimit, "chatLimit required")
    local sendInterval = assert(options.sendInterval, "sendInterval required")
    local slowInterval = options.slowInterval or 1.75
    local throttlePause = assert(options.throttlePause,
        "throttlePause required")
    local throttleSlowTime = assert(options.throttleSlowTime,
        "throttleSlowTime required")
    local controlBurstLimit = tonumber(options.controlBurstLimit) or 4
    local maxAttempts = tonumber(options.maxAttempts) or 3
    local cleanupBudget = math.max(1,
        math.floor(tonumber(options.cleanupBudget) or 32))
    local now = assert(options.now, "now callback required")
    local escapedLen = assert(options.escapedLen,
        "escapedLen callback required")
    local log = assert(options.log, "log callback required")
    local stats = assert(options.stats, "stats table required")
    local resolveChannel = assert(options.resolveChannel,
        "resolveChannel callback required")
    local channelLabel = assert(options.channelLabel,
        "channelLabel callback required")
    local sendChat = assert(options.sendChat, "sendChat callback required")
    local addMessageFilter = assert(options.addMessageFilter,
        "addMessageFilter callback required")
    local observe = type(options.observe) == "function"
        and options.observe or function() end

    local bulk, bulkHead, bulkTail = {}, 1, 0
    local control, controlHead, controlTail = {}, 1, 0
    local ticker = 0
    local throttlePauseUntil, throttleSlowUntil = 0, 0
    local lastAttempt = -math.huge
    local lastSent = nil
    local consecutiveControl = 0
    local filtersInstalled = false
    local throttleNoticeWindow = 4
    local identityCounts, identityContexts = {}, {}
    local requestIdCounts, requestTransferCounts, cancelledRequests = {}, {}, {}
    local operationOwners = {}
    local outstandingTransfers, requestOutstandingTransfers, requestPackets =
        0, 0, 0
    local T = {}

    local scalarMetadata = {
        "requester", "requestId", "transferId", "shareId", "buildId", "dpsId",
        "queueClass", "enqueuedAt", "expiresAt", "attempts",
        "chunkOrdinal", "chunkTotal", "category",
        "operationKind", "operationId", "operationVersion", "operationKey",
    }
    local controlPriority = {share=1,request=2,claim=3,control=4}

    local function RequestScope(metadata)
        if type(metadata) ~= "table" then return "" end
        local requestId = tostring(metadata.requestId or "")
        if requestId == "" then return "" end
        local requester = tostring(metadata.requester or "")
        return tostring(#requester) .. ":" .. requester
            .. tostring(#requestId) .. ":" .. requestId
    end

    local function KeyPart(value)
        value = tostring(value or "")
        return tostring(#value) .. ":" .. value
    end

    local function CopyMetadata(source, queueClass, ordinal, total)
        local copy = {}
        if type(source) == "table" then
            for _, key in ipairs(scalarMetadata) do
                local value = source[key]
                local kind = type(value)
                if kind == "string" or kind == "number"
                    or kind == "boolean" then
                    copy[key] = value
                end
            end
        end
        copy.queueClass = queueClass
        copy.enqueuedAt = tonumber(copy.enqueuedAt) or now()
        copy.attempts = tonumber(copy.attempts) or 0
        copy.chunkOrdinal = tonumber(ordinal) or tonumber(copy.chunkOrdinal) or 1
        copy.chunkTotal = tonumber(total) or tonumber(copy.chunkTotal) or 1
        return copy
    end

    local function EventMetadata(packet)
        return CopyMetadata(packet and packet.metadata,
            packet and packet.metadata and packet.metadata.queueClass or "bulk",
            packet and packet.metadata and packet.metadata.chunkOrdinal or 1,
            packet and packet.metadata and packet.metadata.chunkTotal or 1)
    end

    local function IdentityKey(metadata, queueClass, payload, transferScoped)
        if type(metadata) ~= "table" then return nil end
        local requestId = tostring(metadata.requestId or "")
        local transferId = tostring(metadata.transferId or "")
        local shareId = tostring(metadata.shareId or "")
        local requester = tostring(metadata.requester or "")
        local operationKey = tostring(metadata.operationKey or "")
        if operationKey ~= "" then
            return KeyPart(queueClass) .. KeyPart("operation")
                .. KeyPart(operationKey)
        end
        if transferScoped and transferId ~= "" then
            return KeyPart(queueClass) .. KeyPart(requester)
                .. KeyPart(requestId) .. KeyPart(transferId)
        end
        if shareId ~= "" then
            return KeyPart(queueClass) .. KeyPart("share") .. KeyPart(shareId)
        end
        if transferId ~= "" or requestId ~= "" then
            return KeyPart(queueClass) .. KeyPart(requester)
                .. KeyPart(requestId) .. KeyPart(transferId)
                .. KeyPart(payload)
        end
        return nil
    end

    local function OperationContext(metadata)
        if type(metadata) ~= "table" then return nil end
        local status = metadata.operationStatus or metadata.shareStatus
        if type(status) ~= "table" then return nil end
        local state = operationOwners[status]
        if not state then
            state = {terminal=false}
            operationOwners[status] = state
        end
        return {
            operationStatus=status,
            -- Preserve the established Share callback while Sync moves to the
            -- generic Share/delete operation owner.
            shareStatus=metadata.shareStatus,
            _operationState=state,
        }
    end

    local function NewPacket(payload, metadata, queueClass, ordinal, total,
        identityKey)
        return {
            payload=payload,
            metadata=CopyMetadata(metadata, queueClass, ordinal, total),
            identityKey=identityKey,
            -- Only admitted Share/delete operations retain an opaque owner
            -- reference. Wire text and represented payloads stay queue-owned.
            context=OperationContext(metadata),
        }
    end

    local function TrackAdmit(packet)
        local key = packet and packet.identityKey
        local newIdentity = false
        if key then
            local count = tonumber(identityCounts[key]) or 0
            if count == 0 then
                outstandingTransfers = outstandingTransfers + 1
                newIdentity = true
            end
            identityCounts[key] = count + 1
            if packet.context and not identityContexts[key] then
                identityContexts[key] = packet.context
            end
        end
        local requestScope = packet and RequestScope(packet.metadata) or ""
        if requestScope ~= "" then
            if newIdentity then
                requestOutstandingTransfers = requestOutstandingTransfers + 1
                requestTransferCounts[requestScope] =
                    (tonumber(requestTransferCounts[requestScope]) or 0) + 1
            end
            requestIdCounts[requestScope] =
                (tonumber(requestIdCounts[requestScope]) or 0) + 1
            requestPackets = requestPackets + 1
        end
    end

    local function TrackRemove(packet)
        local key = packet and packet.identityKey
        local removedIdentity = false
        if key and identityCounts[key] then
            local count = identityCounts[key] - 1
            if count <= 0 then
                identityCounts[key] = nil
                identityContexts[key] = nil
                outstandingTransfers = math.max(0, outstandingTransfers - 1)
                removedIdentity = true
            else
                identityCounts[key] = count
            end
        end
        local requestScope = packet and RequestScope(packet.metadata) or ""
        if requestScope ~= "" and requestIdCounts[requestScope] then
            if removedIdentity then
                requestOutstandingTransfers = math.max(0,
                    requestOutstandingTransfers - 1)
                local transfers = (tonumber(requestTransferCounts[requestScope])
                    or 0) - 1
                if transfers <= 0 then
                    requestTransferCounts[requestScope] = nil
                else
                    requestTransferCounts[requestScope] = transfers
                end
            end
            local count = requestIdCounts[requestScope] - 1
            requestPackets = math.max(0, requestPackets - 1)
            if count <= 0 then
                requestIdCounts[requestScope] = nil
                local attemptedScope = lastSent and lastSent.packet
                    and RequestScope(lastSent.packet.metadata) or ""
                if attemptedScope ~= requestScope then
                    cancelledRequests[requestScope] = nil
                end
            else
                requestIdCounts[requestScope] = count
            end
        end
    end

    local function OperationState(packet)
        local context = packet and packet.context
        local state = type(context) == "table" and context._operationState
            or nil
        if type(context) ~= "table" or type(context.operationStatus) ~= "table"
            or type(state) ~= "table" then return nil end
        return state
    end

    local function CopyFields(fields)
        local copy = {}
        for key, value in pairs(type(fields) == "table" and fields or {}) do
            copy[key] = value
        end
        return copy
    end

    local function ObserveOperation(kind, fields, packet)
        local state = OperationState(packet)
        if not state or state.terminal then return false end
        observe(kind, fields, EventMetadata(packet), packet.context)
        return true
    end

    local function MarkOperationTerminal(packet)
        local state = OperationState(packet)
        if not state or state.terminal then return false end
        state.terminal = true
        local status = packet.context and packet.context.operationStatus
        if status then operationOwners[status] = nil end
        return true
    end

    local function ObserveOperationTerminal(packet, outcome, fields)
        if not MarkOperationTerminal(packet) then return false end
        local event = CopyFields(fields)
        event.outcome = tostring(outcome or "reset")
        observe("operation_terminal", event, EventMetadata(packet),
            packet.context)
        return true
    end

    local function ObserveDropped(packet, fields)
        local state = OperationState(packet)
        if state then
            if not MarkOperationTerminal(packet) then return false end
        end
        observe("send_dropped", fields, EventMetadata(packet),
            packet and packet.context)
        return true
    end

    local function ObserveSettled(packet, fields)
        if not MarkOperationTerminal(packet) then return false end
        observe("send_settled", fields, EventMetadata(packet), packet.context)
        return true
    end

    local function ExistingOperation(identityKey)
        if not identityKey then return nil end
        local context = identityContexts[identityKey]
        if not context and lastSent and lastSent.packet
            and lastSent.packet.identityKey == identityKey
            and not lastSent.requeued then
            local state = OperationState(lastSent.packet)
            if state and not state.terminal then
                context = lastSent.packet.context
            end
        end
        return context and context.operationStatus or nil
    end

    local function Depth(head, tail)
        return math.max(0,
            (tonumber(tail) or 0) - (tonumber(head) or 1) + 1)
    end

    local function QueueDepth(isControl)
        if isControl then return Depth(controlHead, controlTail) end
        return Depth(bulkHead, bulkTail)
    end

    function T.Snapshot()
        local bulkDepth = Depth(bulkHead, bulkTail)
        local controlDepth = Depth(controlHead, controlTail)
        local current = now()
        local bulkPacket, controlPacket = bulk[bulkHead], control[controlHead]
        local function Stale(packet)
            if not packet then return false end
            local requestScope = RequestScope(packet.metadata)
            local expiresAt = tonumber(packet.metadata.expiresAt)
            return (requestScope ~= ""
                    and cancelledRequests[requestScope] == true)
                or (expiresAt and current >= expiresAt) or false
        end
        local bulkStale, controlStale = Stale(bulkPacket), Stale(controlPacket)
        local estimatedStale = (bulkStale and bulkDepth or 0)
            + (controlStale and controlDepth or 0)
        local oldestValidAge = 0
        local function ConsiderValidAge(packet)
            if packet and not Stale(packet) then
                oldestValidAge = math.max(oldestValidAge,
                    math.max(0, current - (tonumber(packet.metadata.enqueuedAt)
                        or current)))
            end
        end
        ConsiderValidAge(controlPacket)
        ConsiderValidAge(bulkPacket)
        local headQueueClass = "none"
        if controlPacket and not controlStale
            and (not bulkPacket or bulkStale
                or consecutiveControl < controlBurstLimit) then
            headQueueClass = tostring(controlPacket.metadata.queueClass
                or "control")
        elseif bulkPacket and not bulkStale then
            headQueueClass = "bulk"
        elseif controlStale then
            headQueueClass = "stale-control"
        elseif bulkStale then
            headQueueClass = "stale-bulk"
        end
        return {
            bulk=bulkDepth, control=controlDepth,
            outbound=bulkDepth + controlDepth,
            maxBulk=maxBulk, maxControl=maxControl,
            responseHeadroom=responseHeadroom,
            throttlePauseUntil=throttlePauseUntil,
            controlBurst=consecutiveControl,
            outstandingTransfers=outstandingTransfers,
            requestOutstandingTransfers=requestOutstandingTransfers,
            requestRelated=requestPackets,
            estimatedStaleBacklog=estimatedStale,
            estimatedStaleBulk=bulkStale and bulkDepth or 0,
            estimatedStaleControl=controlStale and controlDepth or 0,
            oldestValidAge=oldestValidAge,
            headQueueClass=headQueueClass,
            expiredInspected=tonumber(stats.expiredInspected) or 0,
            cleanupInspected=tonumber(stats.cleanupInspected) or 0,
            expiredRemoved=tonumber(stats.expiredRemoved) or 0,
            supersededRemoved=tonumber(stats.supersededRemoved) or 0,
            cleanupBatches=tonumber(stats.cleanupBatches) or 0,
            admissionRejected=tonumber(stats.admissionRejected) or 0,
            duplicateSuppressed=tonumber(stats.duplicateSuppressed) or 0,
        }
    end

    -- Exact, bounded projection for one immutable request identity. This uses
    -- queue-owned scalar counters; status polling never scans or retains wire
    -- payloads and unrelated maintenance traffic cannot become request work.
    function T.RequestSnapshot(requester, requestId)
        local scope = RequestScope({requester=requester,requestId=requestId})
        if scope == "" then
            return {packets=0,outstandingTransfers=0,requestRelated=0}
        end
        local packets = math.max(0, tonumber(requestIdCounts[scope]) or 0)
        return {
            packets=packets,
            outstandingTransfers=math.max(0,
                tonumber(requestTransferCounts[scope]) or 0),
            requestRelated=packets,
        }
    end

    function T.BulkFree()
        return math.max(0, maxBulk - Depth(bulkHead, bulkTail))
    end

    function T.Backpressured()
        return T.BulkFree() < responseHeadroom
    end

    function T.CanAdmit(count)
        return tonumber(count) ~= nil and count >= 1
            and count <= T.BulkFree()
    end

    function T.HasPending()
        return bulk[bulkHead] ~= nil or control[controlHead] ~= nil
    end

    local function ValidatePayload(payload)
        if type(payload) ~= "string" or payload == "" then return false end
        local wireLength = escapedLen(payload)
        if wireLength > chatLimit then
            stats.oversizeDropped = (stats.oversizeDropped or 0) + 1
            log("TX", "REJECT oversize queued msg (%d>%d): %s",
                wireLength, chatLimit, payload:sub(1, 40))
            return false
        end
        return true
    end

    local function RejectOverflow(kind, need, depth, cap)
        stats.queueOverflowRejected =
            (stats.queueOverflowRejected or 0) + 1
        stats.admissionRejected = (stats.admissionRejected or 0) + 1
        log("TX", "REJECT newest %s packet(s): queue full (%d+%d>%d)",
            tostring(kind), tonumber(depth) or 0, tonumber(need) or 1,
            tonumber(cap) or 0)
        observe("queue_rejected", {outcome="queue full",chunks=need,
            queue=depth,reason=tostring(kind)})
        return false, "sync queue full"
    end

    local function Admit(packet, isControl)
        if isControl then
            controlTail = controlTail + 1
            control[controlTail] = packet
        else
            bulkTail = bulkTail + 1
            bulk[bulkTail] = packet
        end
        TrackAdmit(packet)
        local key = packet.metadata.queueClass == "share"
            and "admittedShare" or isControl and "admittedControl"
            or "admittedBulk"
        stats[key] = (stats[key] or 0) + 1
    end

    function T.Enqueue(payload, metadata)
        if not ValidatePayload(payload) then return false, "invalid packet" end
        -- A single-packet enqueue is packet-scoped. Some compatibility paths
        -- legitimately enqueue distinct chunks one at a time under one transfer
        -- ID; only an identical packet is a duplicate here.
        local identityKey = IdentityKey(metadata, "bulk", payload, false)
        local existingOperation = ExistingOperation(identityKey)
        if identityKey and (identityCounts[identityKey] or existingOperation) then
            stats.duplicateSuppressed = (stats.duplicateSuppressed or 0) + 1
            observe("queue_deduplicated", {outcome="suppressed",chunks=1,
                queue=T.Snapshot().bulk,queueClass="bulk"})
            return true, "duplicate", existingOperation
        end
        local depth = Depth(bulkHead, bulkTail)
        if depth >= maxBulk then
            return RejectOverflow("bulk", 1, depth, maxBulk)
        end
        local packet = NewPacket(payload, metadata, "bulk", 1, 1, identityKey)
        Admit(packet, false)
        stats.admittedPackets = (stats.admittedPackets or 0) + 1
        stats.admittedBytes = (stats.admittedBytes or 0) + escapedLen(payload)
        return true, nil, packet.context and packet.context.operationStatus
    end

    function T.EnqueueBatch(payloads, metadata)
        if type(payloads) ~= "table" or #payloads == 0 then
            return false, "empty batch"
        end
        for index = 1, #payloads do
            if not ValidatePayload(payloads[index]) then
                return false, "invalid packet"
            end
        end
        local isControl = type(metadata) == "table"
            and (metadata.queueClass == "control"
                or metadata.queueClass == "share"
                or metadata.queueClass == "request"
                or metadata.queueClass == "claim")
        local depth = QueueDepth(isControl)
        local cap = isControl and maxControl or maxBulk
        local queueClass = isControl and tostring(metadata.queueClass)
            or "bulk"
        -- A validated batch is one immutable transfer, so its request/transfer
        -- identity is sufficient to suppress a second outstanding copy.
        local identityKey = IdentityKey(metadata, queueClass, payloads[1], true)
        local existingOperation = ExistingOperation(identityKey)
        if identityKey and (identityCounts[identityKey] or existingOperation) then
            stats.duplicateSuppressed = (stats.duplicateSuppressed or 0) + 1
            observe("queue_deduplicated", {outcome="suppressed",
                chunks=#payloads,queue=depth,queueClass=queueClass})
            return true, "duplicate", existingOperation
        end
        if depth + #payloads > cap then
            return RejectOverflow(isControl and "control batch" or "bulk batch",
                #payloads, depth, cap)
        end
        local admittedBytes = 0
        local operationStatus
        for index = 1, #payloads do
            admittedBytes = admittedBytes + escapedLen(payloads[index])
            local packet = NewPacket(payloads[index], metadata, queueClass,
                index, #payloads, identityKey)
            operationStatus = operationStatus
                or packet.context and packet.context.operationStatus
            Admit(packet, isControl)
        end
        stats.admittedPackets = (stats.admittedPackets or 0) + #payloads
        stats.admittedBytes = (stats.admittedBytes or 0) + admittedBytes
        observe("queue_admitted", {outcome="admitted",chunks=#payloads,
            queue=QueueDepth(isControl),queueClass=queueClass})
        return true, nil, operationStatus
    end

    function T.EnqueueControl(payload, metadata)
        if not ValidatePayload(payload) then return false, "invalid packet" end
        local requestedClass = type(metadata) == "table"
            and tostring(metadata.queueClass or "control") or "control"
        local queueClass = requestedClass == "share" and "share"
            or requestedClass == "request" and "request"
            or requestedClass == "claim" and "claim" or "control"
        local identityKey = IdentityKey(metadata, queueClass, payload, true)
        local existingOperation = ExistingOperation(identityKey)
        if identityKey and (identityCounts[identityKey] or existingOperation) then
            stats.duplicateSuppressed = (stats.duplicateSuppressed or 0) + 1
            observe("queue_deduplicated", {outcome="suppressed",chunks=1,
                queue=Depth(controlHead, controlTail),queueClass=queueClass})
            return true, "duplicate", existingOperation
        end
        local depth = Depth(controlHead, controlTail)
        if depth >= maxControl then
            return RejectOverflow("control", 1, depth, maxControl)
        end
        local packet = NewPacket(payload, metadata, queueClass, 1, 1,
            identityKey)
        if queueClass ~= "control" and depth > 0 then
            -- Explicit Share, requests, and claims have stable bounded priority
            -- while retaining FIFO order within their class. They still consume
            -- the same fixed control cap and never overwrite older entries.
            local insertion = controlHead
            while insertion <= controlTail
                and (controlPriority[control[insertion].metadata.queueClass]
                        or 4)
                    <= (controlPriority[queueClass] or 4) do
                insertion = insertion + 1
            end
            controlTail = controlTail + 1
            for index = controlTail, insertion + 1, -1 do
                control[index] = control[index - 1]
            end
            control[insertion] = packet
            TrackAdmit(packet)
        else
            Admit(packet, true)
        end
        stats.admittedPackets = (stats.admittedPackets or 0) + 1
        stats.admittedBytes = (stats.admittedBytes or 0) + escapedLen(payload)
        return true, nil, packet.context and packet.context.operationStatus
    end

    local function IsWaitingNotice(text)
        text = type(text) == "string" and text:lower() or ""
        return text:find("waiting to send", 1, true)
            or text:find("wait to send", 1, true)
            or text:find("message is queued", 1, true)
    end

    local function IsThrottleNotice(text)
        text = type(text) == "string" and text:lower() or ""
        return IsWaitingNotice(text)
            or text:find("sending messages too quickly", 1, true)
            or text:find("too many messages", 1, true)
            or text:find("chat thrott", 1, true)
    end

    local function PushFront(packet, isControl)
        if isControl then
            if Depth(controlHead, controlTail) == 0 then
                control, controlHead, controlTail = {[1]=packet}, 1, 1
            else
                controlHead = controlHead - 1
                control[controlHead] = packet
            end
        elseif Depth(bulkHead, bulkTail) == 0 then
            bulk, bulkHead, bulkTail = {[1]=packet}, 1, 1
        else
            bulkHead = bulkHead - 1
            bulk[bulkHead] = packet
        end
        TrackAdmit(packet)
    end

    function T.NoteTransportNotice(text)
        if not IsThrottleNotice(text) then return false end
        local current = now()
        if current - lastAttempt > throttleNoticeWindow then return false end
        throttlePauseUntil = math.max(throttlePauseUntil or 0,
            current + throttlePause)
        throttleSlowUntil = math.max(throttleSlowUntil or 0,
            current + throttleSlowTime)
        ticker = 0
        local attempted = lastSent
        if attempted and not attempted.requeued then
            attempted.requeued = true
            local packet = attempted.packet
            local expiresAt = tonumber(packet.metadata.expiresAt)
            local requestScope = RequestScope(packet.metadata)
            local superseded = requestScope ~= ""
                and cancelledRequests[requestScope] == true
            local cap = attempted.isControl and maxControl or maxBulk
            local queueHasRoom = QueueDepth(attempted.isControl) < cap
            if packet.metadata.attempts < maxAttempts and queueHasRoom
                and (not expiresAt or current < expiresAt) and not superseded then
                PushFront(packet, attempted.isControl)
                stats.requeued = (stats.requeued or 0) + 1
                observe("send_requeued", {outcome="requeued",
                    reason="server throttle",attempts=packet.metadata.attempts,
                    queue=T.Snapshot().outbound}, EventMetadata(packet),
                    packet.context)
            else
                if superseded then
                    stats.supersededAfterAttempt =
                        (stats.supersededAfterAttempt or 0) + 1
                    if not requestIdCounts[requestScope] then
                        cancelledRequests[requestScope] = nil
                    end
                else
                    stats.retryExhausted = (stats.retryExhausted or 0) + 1
                end
                ObserveDropped(packet, {outcome="dropped",
                    reason=superseded and "superseded"
                        or expiresAt and current >= expiresAt and "expired"
                        or not queueHasRoom and "retry queue full"
                        or "throttle exhausted",
                    attempts=packet.metadata.attempts,
                    queue=T.Snapshot().outbound})
            end
        end
        log("TX", "server throttle detected; transport paused %.0fs",
            throttlePause)
        return IsWaitingNotice(text) and true or false
    end

    function T.InstallFilters()
        if filtersInstalled then return end
        filtersInstalled = true
        local function QuietWaitNotice(_, _, text, ...)
            if T.NoteTransportNotice(text) then return true end
            return false, text, ...
        end
        pcall(addMessageFilter, "CHAT_MSG_SYSTEM", QuietWaitNotice)
        pcall(addMessageFilter, "UI_ERROR_MESSAGE", QuietWaitNotice)
    end

    local function Pop(isControl)
        local packet
        if isControl then packet = control[controlHead]
        else packet = bulk[bulkHead] end
        if isControl then
            control[controlHead] = nil
            controlHead = controlHead + 1
            if controlHead > controlTail then
                control, controlHead, controlTail = {}, 1, 0
            end
        else
            bulk[bulkHead] = nil
            bulkHead = bulkHead + 1
            if bulkHead > bulkTail then
                bulk, bulkHead, bulkTail = {}, 1, 0
            end
        end
        TrackRemove(packet)
        return packet
    end

    local function StaleReason(packet, current)
        if not packet then return nil end
        local requestScope = RequestScope(packet.metadata)
        if requestScope ~= "" and cancelledRequests[requestScope] == true then
            return "superseded"
        end
        local expiresAt = tonumber(packet.metadata.expiresAt)
        if expiresAt and current >= expiresAt then return "expired" end
        return nil
    end

    local function PruneQueue(isControl, current)
        local inspected, expired, superseded = 0, 0, 0
        for _ = 1, cleanupBudget do
            local packet
            if isControl then packet = control[controlHead]
            else packet = bulk[bulkHead] end
            if not packet then break end
            inspected = inspected + 1
            local reason = StaleReason(packet, current)
            if not reason then break end
            Pop(isControl)
            if OperationState(packet) then
                ObserveOperationTerminal(packet, reason, {reason=reason,
                    attempts=packet.metadata.attempts,
                    queue=QueueDepth(true) + QueueDepth(false)})
            end
            if reason == "expired" then expired = expired + 1
            else superseded = superseded + 1 end
        end
        return inspected, expired, superseded
    end

    local function PruneStaleHeads(current)
        local controlInspected, controlExpired, controlSuperseded =
            PruneQueue(true, current)
        local bulkInspected, bulkExpired, bulkSuperseded =
            PruneQueue(false, current)
        local inspected = controlInspected + bulkInspected
        local expired = controlExpired + bulkExpired
        local superseded = controlSuperseded + bulkSuperseded
        local removed = expired + superseded
        stats.cleanupInspected = (stats.cleanupInspected or 0) + inspected
        stats.expiredInspected = (stats.expiredInspected or 0) + expired
        if removed > 0 then
            stats.cleanupBatches = (stats.cleanupBatches or 0) + 1
            stats.expiredRemoved = (stats.expiredRemoved or 0) + expired
            stats.supersededRemoved = (stats.supersededRemoved or 0)
                + superseded
            -- Preserve the established aggregate while adding exact cleanup
            -- outcomes. One bounded event replaces per-packet trace churn.
            stats.expiredDropped = (stats.expiredDropped or 0) + expired
            observe("queue_cleanup", {outcome="removed",chunks=removed,
                expired=expired,superseded=superseded,
                queue=T.Snapshot().outbound,queueClass="heads"})
        end
    end

    local function ExpireAttemptCancellation(current)
        if not lastSent
            or current - lastAttempt <= throttleNoticeWindow then return end
        if not lastSent.requeued and OperationState(lastSent.packet) then
            ObserveSettled(lastSent.packet, {outcome="sent-attempted",
                reason="attribution window elapsed",
                attempts=lastSent.packet.metadata.attempts,
                queue=QueueDepth(true) + QueueDepth(false)})
        end
        local requestScope = lastSent.packet
            and RequestScope(lastSent.packet.metadata) or ""
        if requestScope ~= "" and not requestIdCounts[requestScope] then
            cancelledRequests[requestScope] = nil
        end
        lastSent = nil
    end

    local function SelectPacket(current)
        local controlPacket = control[controlHead]
        local bulkPacket = bulk[bulkHead]
        if StaleReason(controlPacket, current) then controlPacket = nil end
        if StaleReason(bulkPacket, current) then bulkPacket = nil end
        if controlPacket and (not bulkPacket
            or consecutiveControl < controlBurstLimit) then
            return controlPacket, true
        end
        if bulkPacket then return bulkPacket, false end
        return controlPacket, controlPacket ~= nil
    end

    function T.Pump(elapsed)
        local current = now()
        ExpireAttemptCancellation(current)
        PruneStaleHeads(current)
        if current < (throttlePauseUntil or 0) then return end
        ticker = ticker + (elapsed or 0)
        local interval = current < (throttleSlowUntil or 0)
            and slowInterval or sendInterval
        if ticker < interval then return end
        ticker = 0

        local packet, isControl = SelectPacket(current)
        if not packet then return end

        local channel = resolveChannel()
        if not channel then return end
        local escaped = packet.payload:gsub("|", "||")
        if #escaped > chatLimit then
            log("TX", "DROPPED oversize msg (%d>%d): %s",
                #escaped, chatLimit, packet.payload:sub(1, 40))
            stats.oversizeDropped = (stats.oversizeDropped or 0) + 1
            Pop(isControl)
            ObserveDropped(packet, {outcome="dropped",reason="oversize",
                queue=T.Snapshot().outbound})
            return
        end

        if lastSent and lastSent.packet then
            if not lastSent.requeued and OperationState(lastSent.packet) then
                ObserveSettled(lastSent.packet, {outcome="sent-attempted",
                    reason="later send",
                    attempts=lastSent.packet.metadata.attempts,
                    queue=QueueDepth(true) + QueueDepth(false)})
            end
            local priorScope = RequestScope(lastSent.packet.metadata)
            if priorScope ~= "" and not requestIdCounts[priorScope] then
                cancelledRequests[priorScope] = nil
            end
        end
        lastAttempt = current
        lastSent = nil
        packet.metadata.attempts = packet.metadata.attempts + 1
        stats.sendAttempts = (stats.sendAttempts or 0) + 1
        stats.attempted = (stats.attempted or 0) + 1
        if OperationState(packet) then
            ObserveOperation("send_attempting", {outcome="attempting",
                attempts=packet.metadata.attempts,
                queue=QueueDepth(true) + QueueDepth(false)}, packet)
        end
        local ok = pcall(sendChat, escaped, "CHANNEL", nil, channel)
        if ok then
            Pop(isControl)
            if isControl then
                consecutiveControl = consecutiveControl + 1
            else
                consecutiveControl = 0
            end
            lastSent = {packet=packet,isControl=isControl,sentAt=current,
                requeued=false}
            stats.sent = (stats.sent or 0) + 1
            log("TX", "attempted %d chars ch=%s: %s",
                #escaped, tostring(channel), packet.payload:sub(1, 44))
            observe("send_attempted", {outcome="api returned",bytes=#escaped,
                attempts=packet.metadata.attempts,queue=T.Snapshot().outbound},
                EventMetadata(packet), packet.context)
        else
            stats.sendFailures = (stats.sendFailures or 0) + 1
            throttlePauseUntil = math.max(throttlePauseUntil or 0, current + 2)
            if packet.metadata.attempts >= maxAttempts then
                Pop(isControl)
                stats.retryExhausted = (stats.retryExhausted or 0) + 1
                log("TX", "SendChatMessage FAILED ch=%s; retry exhausted",
                    tostring(channelLabel()))
                ObserveDropped(packet, {outcome="dropped",
                    reason="retry exhausted",attempts=packet.metadata.attempts,
                    queue=T.Snapshot().outbound})
            else
                log("TX", "SendChatMessage FAILED ch=%s; retained for retry",
                    tostring(channelLabel()))
                observe("send_retry", {outcome="retained",reason="send failed",
                    attempts=packet.metadata.attempts,
                    queue=T.Snapshot().outbound}, EventMetadata(packet),
                    packet.context)
            end
        end
    end

    function T.ThrottleRemaining()
        return math.max(0, (throttlePauseUntil or 0) - now())
    end

    function T.CancelRequest(requestId, requester)
        requestId = tostring(requestId or "")
        if requestId == "" then return false end
        local requestScope = RequestScope({requestId=requestId,
            requester=requester})
        local attemptedScope = lastSent and lastSent.packet
            and RequestScope(lastSent.packet.metadata) or ""
        if not requestIdCounts[requestScope]
            and attemptedScope ~= requestScope then return false end
        cancelledRequests[requestScope] = true
        stats.requestsCancelled = (stats.requestsCancelled or 0) + 1
        return true
    end

    function T.Reset()
        for index = bulkHead, bulkTail do
            local packet = bulk[index]
            if OperationState(packet) then
                ObserveOperationTerminal(packet, "reset", {reason="reset",
                    attempts=packet.metadata.attempts,
                    queue=QueueDepth(true) + QueueDepth(false)})
            end
        end
        for index = controlHead, controlTail do
            local packet = control[index]
            if OperationState(packet) then
                ObserveOperationTerminal(packet, "reset", {reason="reset",
                    attempts=packet.metadata.attempts,
                    queue=QueueDepth(true) + QueueDepth(false)})
            end
        end
        if lastSent and not lastSent.requeued
            and OperationState(lastSent.packet) then
            ObserveOperationTerminal(lastSent.packet, "reset", {reason="reset",
                attempts=lastSent.packet.metadata.attempts,
                queue=QueueDepth(true) + QueueDepth(false)})
        end
        bulk, bulkHead, bulkTail = {}, 1, 0
        control, controlHead, controlTail = {}, 1, 0
        ticker = 0
        throttlePauseUntil, throttleSlowUntil = 0, 0
        lastAttempt = -math.huge
        lastSent = nil
        consecutiveControl = 0
        identityCounts, identityContexts = {}, {}
        requestIdCounts, requestTransferCounts, cancelledRequests = {}, {}, {}
        operationOwners = {}
        outstandingTransfers, requestOutstandingTransfers, requestPackets =
            0, 0, 0
    end

    return T
end
