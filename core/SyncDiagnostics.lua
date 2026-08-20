-- Nexus: core/SyncDiagnostics.lua
-- Bounded Sync history, live session counters, and defensive aggregate views.

Nexus = Nexus or {}
if type(Nexus.SyncInternals) ~= "table" then Nexus.SyncInternals = {} end

local Diagnostics = {}
Nexus.SyncInternals.Diagnostics = Diagnostics

local DEFAULT_STATS = {
    sent=0, received=0, duplicatesSkipped=0,
    malformedRejected=0, storageRejected=0, ignoredOutsideWindow=0,
    oversizeDropped=0, updated=0, skippedUpToDate=0,
    queueOverflowRejected=0, pendingOverflowRejected=0,
    baselineSkipped=0, overlaySent=0,
    dpsRequestsReceived=0, dpsDirectAccepted=0, dpsDirectRejected=0,
    dpsRelayOffered=0, dpsRelayAccepted=0, dpsRelayRejected=0,
    requestId="none", useful=false,
    requestNew=0, requestUpdated=0, requestShares=0,
    requestDuplicates=0, requestRejected=0,
    requestBaseline=0, requestUnrelated=0,
    requestLastReason="none", terminalReason="none",
    queueOutcome="none",
    operationQueued=0, operationAttempted=0, operationRequeued=0,
    operationSentAttempted=0, operationExpired=0, operationDropped=0,
    operationSuperseded=0, operationReset=0,
    operationThrottleExhausted=0, operationAccepted=0,
    operationRejected=0,
}

local function Number(value)
    return tonumber(value) or 0
end

local function BoundedCount(value)
    return math.min(9999, math.max(0, math.floor(Number(value))))
end

local REASONS = {
    none=true,accepted=true,bundled=true,duplicate=true,malformed=true,
    schema=true,integrity=true,ownership=true,tombstone=true,stale=true,
    request_auth=true,storage=true,queue=true,timeout=true,disconnect=true,
}

local TERMINALS = {
    none=true,stable=true,expired=true,no_useful_progress=true,
    peer_state_unconfirmed=true,pass_limit=true,queue_rejected=true,
    send_dropped=true,disconnected=true,superseded=true,
}

local QUEUE_OUTCOMES = {
    none=true,queued=true,sent=true,full=true,dropped=true,
    requeued=true,retry=true,disconnected=true,superseded=true,
}

local function BoundedToken(value, allowed, fallback)
    value = tostring(value or fallback or "none")
    if not allowed[value] then return fallback or "none" end
    return value
end

local function BoundedRequestId(value)
    value = tostring(value or "none"):gsub("[%c|]", "")
    if value == "" then return "none" end
    return value:sub(1, 64)
end

function Diagnostics.New(options)
    options = options or {}
    local History = options.history
    if not (History and type(History.New) == "function") then
        error("Nexus DiagnosticHistory must load before SyncDiagnostics")
    end

    local history = History.New({
        cap=tonumber(options.logCap) or 160,
        trimAt=tonumber(options.logTrimAt) or 200,
        maxTextBytes=tonumber(options.logTextBytes) or 2048,
    })
    local maxTextBytes = tonumber(options.logTextBytes) or 2048
    local now = options.now or function() return 0 end
    local stats = {}
    local sequence = 0
    local M = {}

    function M.ResetStats()
        for key in pairs(stats) do stats[key] = 0 end
        for key, value in pairs(DEFAULT_STATS) do stats[key] = value end
    end

    function M.Stats()
        return stats
    end

    -- Copy only fixed scalar request outcomes into the live diagnostic view.
    -- Lifetime counters such as updated/duplicatesSkipped remain independent.
    function M.UpdateRequestOutcome(snapshot)
        snapshot = type(snapshot) == "table" and snapshot or {}
        stats.requestId = BoundedRequestId(snapshot.requestId)
        stats.useful = snapshot.useful == true
        stats.requestNew = BoundedCount(snapshot.new)
        stats.requestUpdated = BoundedCount(snapshot.updated)
        stats.requestShares = BoundedCount(snapshot.shares)
        stats.requestDuplicates = BoundedCount(snapshot.duplicates)
        stats.requestRejected = BoundedCount(snapshot.rejected)
        stats.requestBaseline = BoundedCount(snapshot.baseline)
        stats.requestUnrelated = BoundedCount(snapshot.unrelated)
        stats.requestLastReason = BoundedToken(snapshot.lastReason,
            REASONS, "none")
        stats.terminalReason = BoundedToken(snapshot.terminalReason,
            TERMINALS, "none")
        stats.queueOutcome = BoundedToken(snapshot.queueOutcome,
            QUEUE_OUTCOMES, "none")
        return stats
    end

    function M.LogEvent(category, formatText, ...)
        sequence = sequence + 1
        local stamp = 0
        local okTime, current = pcall(now)
        if okTime and type(current) == "number" then stamp = current end
        history.Append({
            seq=sequence,
            t=stamp,
            cat=History.SafeText(category, 32),
            text=History.Format(maxTextBytes, formatText, ...),
        })
    end

    function M.EventLog()
        return history.Snapshot()
    end

    function M.ClearLog()
        history.Clear()
        sequence = 0
    end

    function M.LogRaw(value)
        M.LogEvent("RX", "%s", History.SafeText(value, maxTextBytes))
    end

    function M.LogStats()
        return history.Stats()
    end

    -- Aggregate only scalar snapshots supplied by the coordinator. No component
    -- is called or mutated here, so diagnostics cannot admit transport or touch
    -- represented data, SavedVariables, or gameplay state.
    function M.ProjectWorkState(input)
        input = input or {}
        local transport = input.transport or {}
        local reconciliation = input.reconciliation or {}
        local incoming = input.incoming or {}
        local session = input.session or {}
        local limits = input.limits or {}
        local sending = Number(transport.bulk)
        local control = Number(transport.control)
        local recovery = Number(session.recovery)
        local receivingBuilds = Number(incoming.builds)
        local receivingRecords = Number(incoming.dps)
        return {
            buildInflight=receivingBuilds,
            buildBytes=Number(incoming.buildBytes),
            dpsInflight=receivingRecords,
            dpsBytes=Number(incoming.dpsBytes),
            maxGlobal=Number(limits.maxGlobal),
            maxPerSender=Number(limits.maxPerSender),
            maxEncodedBytes=Number(limits.maxEncodedBytes),
            sending=sending,
            control=control,
            outbound=sending + control,
            recovery=recovery,
            pendingReplacements=Number(session.pendingReplacements),
            pendingResponses=Number(reconciliation.responses),
            pendingLoadouts=Number(reconciliation.loadouts),
            pendingDeletes=Number(input.pendingDeletes),
            pendingDeleteDiscovery=Number(input.pendingDeleteDiscovery),
            pendingShares=Number(input.pendingShares),
            knownPeers=Number(session.knownPeers),
            maxOutboundQueue=Number(limits.maxOutboundQueue),
            maxControlQueue=Number(limits.maxControlQueue),
            maxRecoveryQueue=Number(limits.maxRecoveryQueue),
            maxPendingResponses=Number(limits.maxPendingResponses),
            maxPendingLoadouts=Number(limits.maxPendingLoadouts),
            maxKnownPeers=Number(limits.maxKnownPeers),
            responseHeadroom=Number(limits.responseHeadroom),
            stale=Number(transport.estimatedStaleBacklog),
            staleBulk=Number(transport.estimatedStaleBulk),
            staleControl=Number(transport.estimatedStaleControl),
            oldestValidAge=Number(transport.oldestValidAge),
            headQueueClass=tostring(transport.headQueueClass or "none"),
            expiredInspected=Number(transport.expiredInspected),
            cleanupInspected=Number(transport.cleanupInspected),
            expiredRemoved=Number(transport.expiredRemoved),
            supersededRemoved=Number(transport.supersededRemoved),
            cleanupBatches=Number(transport.cleanupBatches),
            outstandingTransfers=Number(transport.outstandingTransfers),
            requestOutstandingTransfers=Number(
                input.requestOutstandingTransfers ~= nil
                    and input.requestOutstandingTransfers
                    or transport.requestOutstandingTransfers),
            requestRelated=Number(input.requestRelated ~= nil
                and input.requestRelated or transport.requestRelated),
            admissionRejected=Number(transport.admissionRejected),
            duplicateSuppressed=Number(transport.duplicateSuppressed),
        }
    end

    function M.ProjectSyncWork(input)
        input = input or {}
        local transport = input.transport or {}
        local reconciliation = input.reconciliation or {}
        local incoming = input.incoming or {}
        local session = input.session or {}
        local stale = Number(transport.estimatedStaleBacklog)
        local staleBulk = math.min(Number(transport.bulk),
            Number(transport.estimatedStaleBulk))
        local staleControl = math.min(Number(transport.control),
            Number(transport.estimatedStaleControl))
        if stale > 0 and staleBulk + staleControl == 0 then
            staleBulk = math.min(Number(transport.bulk), stale)
            staleControl = math.min(Number(transport.control),
                math.max(0, stale - staleBulk))
        elseif stale <= 0 then
            stale = staleBulk + staleControl
        end
        local work = {
            control=math.max(0, Number(transport.control) - staleControl),
            sending=math.max(0, Number(transport.bulk) - staleBulk),
            stale=stale,
            receivingBuilds=Number(incoming.builds),
            receivingRecords=Number(incoming.dps),
            preparing=Number(reconciliation.total)
                + Number(input.pendingDeletes)
                + Number(input.pendingDeleteDiscovery)
                + Number(input.pendingShares),
            recovery=Number(session.recovery),
            pass=Number(session.pass),
            outstandingTransfers=Number(transport.outstandingTransfers),
            requestOutstandingTransfers=Number(
                input.requestOutstandingTransfers ~= nil
                    and input.requestOutstandingTransfers
                    or transport.requestOutstandingTransfers),
            oldestValidAge=Number(transport.oldestValidAge),
            headQueueClass=tostring(transport.headQueueClass or "none"),
        }
        work.outbound = work.control + work.sending
        work.receiving = work.receivingBuilds + work.receivingRecords
        work.requestRelated = Number(input.requestRelated ~= nil
            and input.requestRelated or transport.requestRelated)
        work.total = work.outbound + work.stale + work.receiving
            + work.preparing + work.recovery
        return work
    end

    function M.ProjectLeaderboardStatus(input)
        input = input or {}
        local work = input.work or {}
        local throttleRemaining = Number(input.throttleRemaining)
        if throttleRemaining > 0 then
            return "throttled", math.max(1, math.ceil(throttleRemaining)),
                Number(work.total), work
        end
        if input.converging or input.receiving then
            return "syncing", 0, Number(work.total), work
        end
        if Number(work.stale) > 0 then
            return "cleaning", 0, Number(work.total), work
        end
        if Number(work.requestRelated) > 0 then
            return "syncing", 0, Number(work.total), work
        end
        if Number(work.total) > 0 then
            return "sending", 0, Number(work.total), work
        end
        return "idle", 0, 0, work
    end

    M.ResetStats()
    return M
end
