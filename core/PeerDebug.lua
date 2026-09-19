-- Opt-in, session-only peer convergence trace. This owner stores only bounded
-- sanitized outcomes; it never retains wire text, payloads, Echo lists, or
-- SavedVariables state and performs no polling while disabled.

Nexus = Nexus or {}
local Identity = assert(Nexus.Identity,
    "Nexus Identity must load before PeerDebug")
local PeerDebug = {}
Nexus.PeerDebug = PeerDebug

local MAX_EVENTS = 160
local MAX_AGE = 900
local MAX_TEXT = 96
local MAX_EVENT_REPORT = 220
local events, first, count = {}, 1, 0
local enabled, startedAt, stoppedAt, intendedPeer = false, 0, 0, nil
local dropped, expired, revisionSource = 0, 0, nil
local counters = {}
local selectedBuildId

local ALLOWED_FIELDS = {
    id=true,class=true,echoes=true,outcome=true,reason=true,chunks=true,
    bytes=true,queue=true,revision=true,scope=true,page=true,rows=true,
    peer=true,category=true,builds=true,dps=true,quiet=true,sent=true,
    received=true,duplicate=true,tombstone=true,
    operation=true,attempts=true,
}

local function Now()
    local ok, value = pcall(function()
        return (GetTime and GetTime()) or 0
    end)
    value = ok and tonumber(value) or 0
    return value and value == value and value < math.huge
        and value > -math.huge and value or 0
end

local function CleanText(value, limit)
    return Identity.SanitizeText(value, limit or MAX_TEXT)
end

local function CleanPeer(value)
    return Identity.DisplayPlayer(value)
end

local function ResetEvents()
    events, first, count, dropped, expired, counters = {}, 1, 0, 0, 0, {}
    selectedBuildId = nil
end

local function Append(event)
    local position
    if count < MAX_EVENTS then
        position = ((first + count - 1) % MAX_EVENTS) + 1
        count = count + 1
    else
        position = first
        first = (first % MAX_EVENTS) + 1
        dropped = dropped + 1
    end
    events[position] = event
end

local function CheckAge()
    local current = Now()
    if startedAt > 0 and current - startedAt > MAX_AGE
        and (enabled or count > 0 or selectedBuildId ~= nil) then
        events, first, count, dropped, counters = {}, 1, 0, 0, {}
        selectedBuildId = nil
        enabled, stoppedAt, expired = false, current, expired + 1
        return false
    end
    return enabled
end

local function SafeCall(target, name, default, ...)
    local callback = type(target) == "table" and target[name]
    if type(callback) ~= "function" then return default end
    local ok, value = pcall(callback, ...)
    return ok and value ~= nil and value or default
end

function PeerDebug.IsEnabled()
    return CheckAge()
end

function PeerDebug.SetPeer(value)
    intendedPeer = CleanPeer(value)
    return intendedPeer
end

function PeerDebug.Start(peer)
    local cleaned = CleanPeer(peer)
    if peer ~= nil and peer ~= "" and not cleaned then
        return false
    end
    ResetEvents()
    intendedPeer = cleaned
    startedAt, stoppedAt, enabled = Now(), 0, true
    PeerDebug.Record("session_start", {
        peer=intendedPeer or "any",outcome="active",
    })
    return true
end

function PeerDebug.Stop()
    if not CheckAge() then return false end
    PeerDebug.Record("session_stop", {outcome="stopped"})
    enabled, stoppedAt = false, Now()
    return true
end

function PeerDebug.Clear()
    ResetEvents()
    enabled, startedAt, stoppedAt, intendedPeer = false, 0, 0, nil
    return true
end

function PeerDebug.Record(kind, fields)
    if not CheckAge() then return false end
    kind = CleanText(kind, 40)
    if kind == "" then return false end
    if intendedPeer and type(fields) == "table" and fields.peer ~= nil then
        local eventPeer = CleanPeer(fields.peer)
        if not eventPeer or not Identity.SamePlayer(eventPeer, intendedPeer) then
            return false
        end
    end
    local event = {at=Now(),kind=kind,fields={}}
    if type(fields) == "table" then
        for key, value in pairs(fields) do
            if ALLOWED_FIELDS[key] then
                local valueType = type(value)
                if valueType == "number" then
                    if value == value and value < math.huge
                        and value > -math.huge then event.fields[key] = value end
                elseif valueType == "boolean" then
                    event.fields[key] = value
                elseif valueType == "string" then
                    if key == "peer" then
                        event.fields[key] = CleanPeer(value)
                    else
                        event.fields[key] = CleanText(value,
                            key == "id" and 56 or MAX_TEXT)
                    end
                end
            end
        end
    end
    if event.fields.id and (kind == "share_created" or not selectedBuildId) then
        selectedBuildId = event.fields.id
    end
    counters[kind] = (counters[kind] or 0) + 1
    Append(event)
    return true
end

local function SnapshotEvents()
    local out = {}
    for offset = 0, count - 1 do
        local index = ((first + offset - 1) % MAX_EVENTS) + 1
        local source = events[index]
        local copy = {at=source.at,kind=source.kind,fields={}}
        for key, value in pairs(source.fields or {}) do copy.fields[key] = value end
        out[#out + 1] = copy
    end
    return out
end

function PeerDebug.Stats()
    local counterCopy = {}
    for key, value in pairs(counters) do counterCopy[key] = value end
    return {
        enabled=PeerDebug.IsEnabled(),startedAt=startedAt,stoppedAt=stoppedAt,
        peer=intendedPeer,retained=count,dropped=dropped,expired=expired,
        selectedBuild=selectedBuildId,
        cap=MAX_EVENTS,maxAge=MAX_AGE,counters=counterCopy,
    }
end

function PeerDebug.SelectBuild(id)
    id = CleanText(id, 96)
    selectedBuildId = id ~= "" and id or nil
    return selectedBuildId
end

function PeerDebug.SelectedBuild()
    return selectedBuildId
end

function PeerDebug.ExplainBuild(id, filters)
    id = CleanText(id, 96)
    if id == "" then return "no selected build" end
    local projections = Nexus and Nexus.ViewProjections
    if not (projections and type(projections.ExplainBuild) == "function") then
        return "projection explanation unavailable"
    end
    filters = type(filters) == "table" and filters
        or (type(NexusDB) == "table" and type(NexusDB.buildFilters) == "table"
            and NexusDB.buildFilters) or {}
    local ok, result = pcall(projections.ExplainBuild, id, filters)
    if not ok then return "projection explanation failed" end
    return CleanText(result or "projection explanation unavailable", MAX_TEXT)
end

function PeerDebug.ExplainLockedEvidence(id)
    id = CleanText(id, 96)
    if id == "" then return "unavailable", "no selected build" end
    local catalog = Nexus and Nexus.BuildCatalog
    if not (catalog and type(catalog.GetSummary) == "function") then
        return "unavailable", "build summary unavailable"
    end
    local okSummary, summary = pcall(catalog.GetSummary, id)
    if not okSummary or type(summary) ~= "table" then
        return "unavailable", okSummary and "build unavailable"
            or "build summary failed"
    end

    local dps = Nexus and Nexus.DpsCapture
    if not (dps and type(dps.GetCachedLockedEvidence) == "function") then
        return "unavailable", "locked evidence cache unavailable"
    end
    local okCached, cached, cacheReason = pcall(
        dps.GetCachedLockedEvidence, summary.id or id,
        summary.fingerprint, summary.fingerprintHash)
    if not okCached or type(cached) ~= "table" then
        return "unavailable", CleanText(okCached
            and (cacheReason or "locked evidence unavailable")
            or "locked evidence lookup failed", MAX_TEXT)
    end

    local resolver = Nexus and Nexus.CandidateEvidence
    if not (resolver and type(resolver.ResolveLocked) == "function") then
        return "unavailable", "locked Echo resolver unavailable"
    end
    local ordinary = cached.ordinaryEchoes
        or (type(cached.dummy) == "table" and cached.dummy.echoes)
        or (type(cached.lk) == "table" and cached.lk.echoes)
    local okResolve, result = pcall(resolver.ResolveLocked, {
        buildId=summary.id or id,fingerprint=summary.fingerprint,
        ordinaryEchoes=ordinary,dummyRecord=cached.dummy,lkRecord=cached.lk,
    })
    if not okResolve or type(result) ~= "table" then
        return "unavailable", "locked Echo resolution failed"
    end
    return CleanText(result.status or "unavailable", 24),
        CleanText(result.reason or "", MAX_TEXT)
end

local function FormatFields(fields)
    local keys = {}
    for key in pairs(fields or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    local out, used = {}, 0
    for _, key in ipairs(keys) do
        local part = key .. "=" .. CleanText(fields[key], MAX_TEXT)
        local separator = #out > 0 and 1 or 0
        if used + separator + #part > MAX_EVENT_REPORT then
            local remaining = MAX_EVENT_REPORT - used - separator
            if remaining >= 4 then
                out[#out + 1] = part:sub(1, remaining - 3) .. "..."
            end
            break
        end
        out[#out + 1] = part
        used = used + separator + #part
    end
    return table.concat(out, " ")
end

function PeerDebug.Report()
    local runtimeBuild = CleanText(
        SafeCall(Nexus, "RuntimeBuildLabel", "source"), 48)
    if not PeerDebug.IsEnabled() and startedAt == 0 then
        return table.concat({
            "NEXUS PEER TEST REPORT",
            "status=disabled (zero collection work)",
            string.format("version=%s build=%s",
                CleanText(Nexus.VERSION or "?", 40), runtimeBuild),
            "Use Start on the Peer Test tab to begin a bounded session.",
        }, "\n")
    end

    local sync = Nexus.Sync
    local work = SafeCall(sync, "WorkState", {})
    local transport = type(work) == "table" and work or {}
    local syncStats = SafeCall(sync, "Stats", {})
    local buildCache = SafeCall(Nexus.BuildHashCache, "Stats", {})
    local dpsCache = SafeCall(Nexus.DpsCapture, "HashCacheStats", {})
    local dpsRejects = SafeCall(Nexus.DpsCapture, "RejectionStats", {})
    local dpsOutbound = SafeCall(Nexus.DpsCapture, "OutboundStats", {})
    local leaderboard = SafeCall(Nexus.Leaderboard, "VirtualStats", nil)
    local revisions = Nexus.Revisions
    local buildRevision = SafeCall(revisions, "Get", 0,
        revisions and revisions.BUILD_LIBRARY_CHANGED)
    local dpsRevision = SafeCall(revisions, "Get", 0,
        revisions and revisions.DPS_CHANGED)
    local protocol = SafeCall(Nexus.DpsCapture, "ProtocolVersion", "unknown")
    local rows = SnapshotEvents()
    local lockedStatus, lockedReason = "unavailable", "no selected build"
    if selectedBuildId then
        lockedStatus, lockedReason =
            PeerDebug.ExplainLockedEvidence(selectedBuildId)
    end
    local out = {
        "NEXUS PEER TEST REPORT",
        string.format("status=%s age=%.1fs retained=%d/%d dropped=%d expired=%d peer=%s",
            enabled and "active" or "stopped", math.max(0, Now() - startedAt),
            count, MAX_EVENTS, dropped, expired, intendedPeer or "any"),
        string.format("event_scope=observation peer_filter=%s peer_events=%s global_events=included routing=unchanged",
            intendedPeer or "any", intendedPeer and "filtered" or "all"),
        "counter_scope=addon_session event_history=peer_test_session",
        string.format("version=%s build=%s protocol=%s channel=%s index=%s connected=%s receiving=%s quiet_in=%.1fs",
            CleanText(Nexus.VERSION or "?", 40),
            runtimeBuild,
            CleanText(protocol, 12),
            CleanText(SafeCall(sync, "ChannelName", "unavailable"), 40),
            CleanText(SafeCall(sync, "ChannelIndex", "unavailable"), 12),
            tostring(SafeCall(sync, "IsConnected", false)),
            tostring(SafeCall(sync, "IsReceiving", false)),
            tonumber(SafeCall(sync, "ReceiveTimeLeft", 0)) or 0),
        string.format("queue=%s sent=%s received=%s build_rows_cached=%s dps_rows_hash_eligible=%s",
            CleanText(type(transport) == "table" and transport.outbound or 0, 16),
            CleanText(type(syncStats) == "table" and syncStats.sent or 0, 16),
            CleanText(type(syncStats) == "table" and syncStats.received or 0, 16),
            buildCache.initialized and CleanText(buildCache.buildRows or 0, 16)
                or "unknown",
            dpsCache.initialized and CleanText(dpsCache.rows or 0, 16)
                or "unknown"),
        string.format("sync_request id=%s useful=%s new=%s updated=%s share=%s duplicate=%s rejected=%s baseline=%s unrelated=%s",
            CleanText(type(syncStats) == "table" and syncStats.requestId or "none", 64),
            tostring(type(syncStats) == "table" and syncStats.useful == true),
            CleanText(type(syncStats) == "table" and syncStats.requestNew or 0, 16),
            CleanText(type(syncStats) == "table" and syncStats.requestUpdated or 0, 16),
            CleanText(type(syncStats) == "table" and syncStats.requestShares or 0, 16),
            CleanText(type(syncStats) == "table" and syncStats.requestDuplicates or 0, 16),
            CleanText(type(syncStats) == "table" and syncStats.requestRejected or 0, 16),
            CleanText(type(syncStats) == "table" and syncStats.requestBaseline or 0, 16),
            CleanText(type(syncStats) == "table" and syncStats.requestUnrelated or 0, 16)),
        string.format("sync_terminal reason=%s queue=%s last_reason=%s",
            CleanText(type(syncStats) == "table" and syncStats.terminalReason or "none", 32),
            CleanText(type(syncStats) == "table" and syncStats.queueOutcome or "none", 24),
            CleanText(type(syncStats) == "table" and syncStats.requestLastReason or "none", 32)),
        string.format("dps_sync requested=%s offered=%s direct_ok=%s relay_ok=%s rejected=%s",
            CleanText(type(syncStats) == "table"
                and syncStats.dpsRequestsReceived or 0, 16),
            CleanText(type(syncStats) == "table"
                and syncStats.dpsRelayOffered or 0, 16),
            CleanText(type(syncStats) == "table"
                and syncStats.dpsDirectAccepted or 0, 16),
            CleanText(type(syncStats) == "table"
                and syncStats.dpsRelayAccepted or 0, 16),
            CleanText(type(syncStats) == "table"
                and ((tonumber(syncStats.dpsDirectRejected) or 0)
                    + (tonumber(syncStats.dpsRelayRejected) or 0)) or 0, 16)),
        string.format("dps_reject duration=%s owner_sender=%s relay_auth=%s schema=%s stale=%s duplicate=%s category=%s integrity=%s outside_request=%s",
            CleanText(dpsRejects.duration or 0, 16),
            CleanText(dpsRejects.owner_sender or 0, 16),
            CleanText(dpsRejects.relay_authorization or 0, 16),
            CleanText(dpsRejects.schema or 0, 16),
            CleanText(dpsRejects.stale_record or 0, 16),
            CleanText(dpsRejects.duplicate_not_better or 0, 16),
            CleanText(dpsRejects.invalid_category or 0, 16),
            CleanText(dpsRejects.integrity or 0, 16),
            CleanText(dpsRejects.outside_request or 0, 16)),
        string.format("dps_outbound considered=%s eligible=%s direct=%s relay=%s peer_current=%s outside_bucket=%s",
            CleanText(dpsOutbound.considered or 0, 16),
            CleanText(dpsOutbound.eligible or 0, 16),
            CleanText(dpsOutbound.offered_direct or 0, 16),
            CleanText(dpsOutbound.offered_relay or 0, 16),
            CleanText(dpsOutbound.peer_current or 0, 16),
            CleanText(dpsOutbound.outside_bucket or 0, 16)),
        string.format("dps_outbound_skip duration=%s score=%s owner_sender=%s relay_auth=%s schema=%s stale=%s duplicate=%s category=%s integrity=%s outside_request=%s other=%s",
            CleanText(dpsOutbound.duration or 0, 16),
            CleanText(dpsOutbound.score or 0, 16),
            CleanText(dpsOutbound.owner_sender or 0, 16),
            CleanText(dpsOutbound.relay_authorization or 0, 16),
            CleanText(dpsOutbound.schema or 0, 16),
            CleanText(dpsOutbound.stale_record or 0, 16),
            CleanText(dpsOutbound.duplicate_not_better or 0, 16),
            CleanText(dpsOutbound.invalid_category or 0, 16),
            CleanText(dpsOutbound.integrity or 0, 16),
            CleanText(dpsOutbound.outside_request or 0, 16),
            CleanText(dpsOutbound.other or 0, 16)),
        string.format("dps_outbound_deferred queue=%s wire=%s",
            CleanText(dpsOutbound.queue_deferred or 0, 16),
            CleanText(dpsOutbound.wire_deferred or 0, 16)),
        string.format("build_revision=%s dps_revision=%s build_cache=%s dps_cache=%s",
            CleanText(buildRevision, 16),CleanText(dpsRevision, 16),
            buildCache.initialized and "warm" or "cold",
            dpsCache.initialized and "warm" or "cold"),
        string.format("dps_counts stored=%s hash_eligible=%s published_board=%s displayed_rows=%s",
            dpsCache.initialized and CleanText(
                dpsCache.storedRows or dpsCache.rows or 0, 16)
                or "unknown",
            dpsCache.initialized and CleanText(dpsCache.rows or 0, 16)
                or "unknown",
            type(leaderboard) == "table"
                and CleanText(leaderboard.publishedRows or 0, 16) or "unknown",
            type(leaderboard) == "table"
                and CleanText(leaderboard.displayedRows or 0, 16) or "unknown"),
        string.format("dps_local_ineligible duration=%s score=%s schema=%s",
            dpsCache.initialized
                and CleanText(dpsCache.durationIneligibleRows or 0, 16)
                or "unknown",
            dpsCache.initialized
                and CleanText(dpsCache.scoreIneligibleRows or 0, 16)
                or "unknown",
            dpsCache.initialized
                and CleanText(dpsCache.schemaIneligibleRows or 0, 16)
                or "unknown"),
        string.format("build_digest=%s buckets=%s state=%s dps_digest=%s buckets=%s state=%s",
            CleanText(buildCache.digest or "unknown", MAX_TEXT),
            CleanText(buildCache.buckets or "unknown", 8),
            buildCache.initialized and ((tonumber(buildCache.dirtyBuckets) or 0) > 0
                and ("dirty:" .. CleanText(buildCache.dirtyBuckets, 8)) or "current")
                or "cold",
            CleanText(dpsCache.digest or "unknown", MAX_TEXT),
            CleanText(dpsCache.buckets or "unknown", 8),
            dpsCache.initialized and ((tonumber(dpsCache.dirtyBuckets) or 0) > 0
                and ("dirty:" .. CleanText(dpsCache.dirtyBuckets, 8)) or "current")
                or "cold"),
        string.format("selected_build=%s community=%s",
            CleanText(selectedBuildId or "none", 56),
            CleanText(selectedBuildId and PeerDebug.ExplainBuild(selectedBuildId)
                or "no selected build", MAX_TEXT)),
        string.format("locked_evidence=%s locked_reason=%s",
            CleanText(lockedStatus or "unavailable", 24),
            CleanText(lockedReason or "", MAX_TEXT)),
        "events (oldest first; sanitized scalar outcomes only):",
    }
    if #rows == 0 then out[#out + 1] = "  (none)" end
    for _, event in ipairs(rows) do
        out[#out + 1] = string.format("  +%.2fs %-28s %s",
            math.max(0, (tonumber(event.at) or startedAt) - startedAt),
            event.kind, FormatFields(event.fields))
    end
    return table.concat(out, "\n")
end

function PeerDebug.Init()
    local revisions = Nexus.Revisions
    if revisionSource == revisions then return true end
    revisionSource = revisions
    if revisions and type(revisions.Subscribe) == "function" then
        revisions.Subscribe(revisions.BUILD_LIBRARY_CHANGED,
            function(_, revision, detail)
                if not PeerDebug.IsEnabled() then return end
                PeerDebug.Record("build_revision", {
                    revision=revision,scope=type(detail) == "table"
                        and detail.scope or "unknown",
                    id=type(detail) == "table" and detail.id or nil,
                })
            end)
        revisions.Subscribe(revisions.DPS_CHANGED,
            function(_, revision, detail)
                if not PeerDebug.IsEnabled() then return end
                PeerDebug.Record("dps_revision", {
                    revision=revision,scope=type(detail) == "table"
                        and detail.scope or "unknown",
                    category=type(detail) == "table" and detail.category or nil,
                })
            end)
    end
    return true
end

function PeerDebug.Limits()
    return {events=MAX_EVENTS,age=MAX_AGE,text=MAX_TEXT,
        eventReport=MAX_EVENT_REPORT}
end
