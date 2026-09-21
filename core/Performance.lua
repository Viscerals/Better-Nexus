-- Bounded, session-only aggregate timings for known Nexus hot paths.
--
-- Timings are observational. They never enter SavedVariables, retain samples,
-- or influence gameplay. The default clock reports milliseconds; tests may
-- inject another millisecond clock. A failed/unavailable clock is tried once,
-- then the measured callback takes a constant cheap bypass until SetClock.

Nexus = Nexus or {}

local Performance = {}
Nexus.Performance = Performance

local PATH_ORDER = {
    "automation.step",
    "automation.fallback.check",
    "automation.fallback.repair",
    "automation.phase.static",
    "automation.phase.catalog",
    "automation.phase.wishlist",
    "automation.phase.wishlist-fingerprint",
    "automation.phase.plan",
    "automation.phase.slots",
    "automation.phase.owned",
    "automation.phase.levers",
    "automation.phase.board",
    "automation.phase.board-prepare",
    "automation.phase.policy",
    "automation.phase.autolock",
    "automation.phase.preauthorize",
    "automation.phase.overlay-prepare",
    "automation.phase.overlay-render",
    "decision.policy",
    "sync.update",
    "sync.incoming",
    "dps.update",
    "views.refresh",
    "hud.prepare",
    "community.show",
    "community.saved-import",
    "community.related-lookup",
    "community.frame.ensure",
    "community.projection",
    "community.render",
    "community.refresh",
    "leaderboard.refresh",
    "panel.render",
    "overlay.refresh",
    "lifecycle.update",
    "automation.update",
    "gameadapter.poll",
}
local PATHS = {}
for _, name in ipairs(PATH_ORDER) do PATHS[name] = true end
local AGGREGATE_ONLY = {}
for _, name in ipairs(PATH_ORDER) do
    if name:find("automation.phase.", 1, true) == 1 then
        AGGREGATE_ONLY[name] = true
    end
end

local enabled = true
local injectedClock = nil
local clockState = "unknown"
local clockFailures = 0
local aggregates = {}
local instrumented = setmetatable({}, {__mode="k"})
local operations = {}

local OPERATION_CAPACITY = 32
local OPERATION_MAX_AGE_SECONDS = 15
local OPERATION_MINIMUM_MS = 1
local SLOW_STEP_MINIMUM_MS = 16
local OPERATION_FIELD_ORDER = {"trigger", "mismatch", "mode", "outcome"}
local activeAutomationStep = false
local activeStepDominantName = "none"
local activeStepDominantMs = 0
local stepClassifications = {mode="none",outcome=0}
local lastSlowStep = {
    present=false,durationMs=0,dominantPhase="none",
    dominantPhaseMs=0,endTime=0,retainedScalarFields=5,
}

local function FiniteNumber(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge
        or number == -math.huge then return nil end
    return number
end

local function DefaultClock()
    if type(debugprofilestop) == "function" then
        return debugprofilestop()
    end
    if type(GetTime) == "function" then
        return GetTime() * 1000
    end
    return nil
end

local function ReadClock()
    if clockState == "unavailable" then return nil end
    local clock = injectedClock or DefaultClock
    local ok, value = pcall(clock)
    value = ok and FiniteNumber(value) or nil
    if not value then
        clockState = "unavailable"
        clockFailures = clockFailures + 1
        return nil
    end
    clockState = "available"
    return value
end

local function ReadSessionTime()
    if type(GetTime) ~= "function" then return nil end
    local ok, value = pcall(GetTime)
    return ok and FiniteNumber(value) or nil
end

local function ControlledScalar(value)
    local kind = type(value)
    if kind == "number" then return FiniteNumber(value) end
    if kind == "boolean" then return value end
    if kind ~= "string" then return nil end
    value = value:gsub("[%z\1-\31\127]", " "):gsub("|", "")
    if #value > 48 then value = value:sub(1, 48) end
    return value ~= "" and value or nil
end

local function CopyControlledFields(classifications)
    local fields = {}
    if type(classifications) ~= "table" then return fields end
    for _, key in ipairs(OPERATION_FIELD_ORDER) do
        local value = ControlledScalar(classifications[key])
        if value ~= nil then
            fields[#fields + 1] = {key=key, value=value}
        end
    end
    return fields
end

local function PruneOperations(now)
    local cutoff = now - OPERATION_MAX_AGE_SECONDS
    local writeAt = 1
    for readAt = 1, #operations do
        local operation = operations[readAt]
        if operation.endTime >= cutoff then
            operations[writeAt] = operation
            writeAt = writeAt + 1
        end
    end
    for index = writeAt, #operations do operations[index] = nil end
end

local function RecordOperation(name, elapsed, classifications)
    if elapsed < OPERATION_MINIMUM_MS then return false end
    local endedAt = ReadSessionTime()
    if not endedAt then return false end
    PruneOperations(endedAt)
    operations[#operations + 1] = {
        name=name,
        startTime=math.max(0, endedAt - (elapsed / 1000)),
        endTime=endedAt,
        durationMs=elapsed,
        fields=CopyControlledFields(classifications),
    }
    if #operations > OPERATION_CAPACITY then table.remove(operations, 1) end
    return true
end

local function CopyOperation(operation)
    local fields = {}
    for index, field in ipairs(operation.fields or {}) do
        fields[index] = {key=field.key, value=field.value}
    end
    return {
        name=operation.name,
        startTime=operation.startTime,
        endTime=operation.endTime,
        durationMs=operation.durationMs,
        fields=fields,
    }
end

local function CopyAggregate(name)
    local value = aggregates[name] or {}
    return {
        name=name,
        count=tonumber(value.count) or 0,
        total=tonumber(value.total) or 0,
        maximum=tonumber(value.maximum) or 0,
        last=tonumber(value.last) or 0,
    }
end

function Performance.SetEnabled(value)
    enabled = value ~= false
    return enabled
end

function Performance.IsEnabled()
    return enabled
end

function Performance.SetClock(clock)
    if clock ~= nil and type(clock) ~= "function" then
        return false, "clock must be a function or nil"
    end
    injectedClock = clock
    clockState = "unknown"
    return true
end

function Performance.Begin(name)
    if not enabled or not PATHS[name] or clockState == "unavailable" then
        return nil
    end
    return ReadClock()
end

function Performance.Finish(name, startedAt, classifications)
    if not enabled or not PATHS[name] then return false end
    startedAt = FiniteNumber(startedAt)
    if not startedAt then return false end
    local finishedAt = ReadClock()
    if not finishedAt then return false end
    local elapsed = finishedAt - startedAt
    if elapsed < 0 then return false end
    if activeAutomationStep and AGGREGATE_ONLY[name]
        and elapsed > activeStepDominantMs then
        activeStepDominantName = name
        activeStepDominantMs = elapsed
    end
    if name == "automation.step" and activeAutomationStep then
        stepClassifications.mode = activeStepDominantName
        stepClassifications.outcome = activeStepDominantMs
        classifications = stepClassifications
        if elapsed >= SLOW_STEP_MINIMUM_MS then
            lastSlowStep.present = true
            lastSlowStep.durationMs = elapsed
            lastSlowStep.dominantPhase = activeStepDominantName
            lastSlowStep.dominantPhaseMs = activeStepDominantMs
            lastSlowStep.endTime = ReadSessionTime() or 0
        end
    end
    local aggregate = aggregates[name]
    if not aggregate then
        aggregate = {count=0, total=0, maximum=0, last=0}
        aggregates[name] = aggregate
    end
    aggregate.count = aggregate.count + 1
    aggregate.total = aggregate.total + elapsed
    aggregate.maximum = math.max(aggregate.maximum, elapsed)
    aggregate.last = elapsed
    -- Fine-grained automation phases are exported as bounded aggregates but
    -- never enter the 32-entry recent-operation ring. A single outer Step must
    -- remain the useful StutterAlert correlation breadcrumb instead of being
    -- displaced by its own internal children.
    if elapsed >= OPERATION_MINIMUM_MS and not AGGREGATE_ONLY[name] then
        pcall(RecordOperation, name, elapsed, classifications)
    end
    return true
end

local function Complete(name, startedAt, ...)
    Performance.Finish(name, startedAt)
    if name == "automation.step" then activeAutomationStep = false end
    return ...
end

function Performance.Measure(name, callback, ...)
    if type(callback) ~= "function" then error("callback must be a function", 2) end
    if not enabled or not PATHS[name] or clockState == "unavailable" then
        return callback(...)
    end
    local startedAt = ReadClock()
    if not startedAt then return callback(...) end
    if name == "automation.step" then
        activeAutomationStep = true
        activeStepDominantName = "none"
        activeStepDominantMs = 0
    end
    -- Callback errors intentionally propagate unchanged. In that case there is
    -- no completed sample to aggregate, and no result-packing allocation.
    return Complete(name, startedAt, callback(...))
end

function Performance.Stats(name)
    if not PATHS[name] then return nil end
    return CopyAggregate(name)
end

function Performance.Snapshot()
    local rows = {}
    for index, name in ipairs(PATH_ORDER) do rows[index] = CopyAggregate(name) end
    return {
        enabled=enabled,
        clockAvailable=clockState ~= "unavailable",
        clockFailures=clockFailures,
        units="ms",
        rows=rows,
    }
end

function Performance.Reset(name)
    if name ~= nil then
        if not PATHS[name] then return false end
        aggregates[name] = nil
        local writeAt = 1
        for readAt = 1, #operations do
            local operation = operations[readAt]
            if operation.name ~= name then
                operations[writeAt] = operation
                writeAt = writeAt + 1
            end
        end
        for index = writeAt, #operations do operations[index] = nil end
        if name == "automation.step" then
            activeAutomationStep = false
            activeStepDominantName = "none"
            activeStepDominantMs = 0
            lastSlowStep.present = false
            lastSlowStep.durationMs = 0
            lastSlowStep.dominantPhase = "none"
            lastSlowStep.dominantPhaseMs = 0
            lastSlowStep.endTime = 0
        end
        return true
    end
    aggregates = {}
    operations = {}
    clockFailures = 0
    activeAutomationStep = false
    activeStepDominantName = "none"
    activeStepDominantMs = 0
    lastSlowStep.present = false
    lastSlowStep.durationMs = 0
    lastSlowStep.dominantPhase = "none"
    lastSlowStep.dominantPhaseMs = 0
    lastSlowStep.endTime = 0
    return true
end

function Performance.CancelAutomationStep()
    activeAutomationStep = false
    activeStepDominantName = "none"
    activeStepDominantMs = 0
    return true
end

function Performance.LastSlowStep()
    return {
        present=lastSlowStep.present,durationMs=lastSlowStep.durationMs,
        dominantPhase=lastSlowStep.dominantPhase,
        dominantPhaseMs=lastSlowStep.dominantPhaseMs,
        endTime=lastSlowStep.endTime,
        retainedScalarFields=lastSlowStep.retainedScalarFields,
    }
end

function Performance.RecentOperations(windowStart, windowEnd, now)
    windowStart = FiniteNumber(windowStart)
    windowEnd = FiniteNumber(windowEnd)
    if not windowStart or not windowEnd or windowEnd < windowStart then return {} end
    now = FiniteNumber(now) or ReadSessionTime() or windowEnd
    PruneOperations(now)
    local recent = {}
    for index = #operations, 1, -1 do
        local operation = operations[index]
        if operation.endTime >= windowStart and operation.startTime <= windowEnd then
            recent[#recent + 1] = CopyOperation(operation)
        end
    end
    return recent
end

function Performance.OperationLimits()
    return {
        capacity=OPERATION_CAPACITY,
        maxAgeSeconds=OPERATION_MAX_AGE_SECONDS,
        minimumDurationMs=OPERATION_MINIMUM_MS,
        slowStepMinimumMs=SLOW_STEP_MINIMUM_MS,
        maxFields=#OPERATION_FIELD_ORDER,
    }
end

function Performance.Definitions()
    local names = {}
    for index, name in ipairs(PATH_ORDER) do names[index] = name end
    return names
end

function Performance.Instrument(name, owner, key)
    if not PATHS[name] then return false, "unknown performance path" end
    if type(owner) ~= "table" or type(key) ~= "string" then
        return false, "instrumentation target must be a table field"
    end
    local callback = owner[key]
    if type(callback) ~= "function" then return false, "target is not callable" end
    local targets = instrumented[owner]
    if not targets then targets = {}; instrumented[owner] = targets end
    local current = targets[key]
    if current and current.name == name and owner[key] == current.wrapper then
        return true
    end
    if current and callback == current.wrapper then callback = current.original end
    local wrapper = function(...)
        return Performance.Measure(name, callback, ...)
    end
    targets[key] = {name=name, original=callback, wrapper=wrapper}
    owner[key] = wrapper
    return true
end

function Performance.InstallDefaults()
    local targets = {
        {"decision.policy", Nexus.Policy, "Decide"},
        {"sync.update", Nexus.Sync, "OnUpdate"},
        {"sync.incoming", Nexus.Sync, "HandleIncoming"},
        {"dps.update", Nexus.DpsCapture, "OnUpdate"},
        {"community.refresh", Nexus.CommunityBuilds, "Refresh"},
        {"leaderboard.refresh", Nexus.Leaderboard, "RefreshData"},
        {"panel.render", Nexus.Panel, "Render"},
        {"overlay.refresh", Nexus.WishlistOverlay, "Refresh"},
    }
    local installed = 0
    for _, target in ipairs(targets) do
        if type(target[2]) == "table" and type(target[2][target[3]]) == "function" then
            local ok = Performance.Instrument(target[1], target[2], target[3])
            if ok then installed = installed + 1 end
        end
    end
    return installed
end
