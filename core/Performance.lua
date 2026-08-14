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
    "automation.catalog",
    "automation.wishlist",
    "automation.compile",
    "automation.slots",
    "automation.owned",
    "automation.levers",
    "automation.autolock",
    "automation.progress",
    "automation.hud",
    "decision.policy",
    "sync.update",
    "dps.update",
    "community.open",
    "community.frame",
    "community.refresh",
    "community.import",
    "community.projection",
    "community.bind",
    "community.detail",
    "leaderboard.refresh",
    "panel.render",
    "overlay.refresh",
}
local PATHS = {}
for _, name in ipairs(PATH_ORDER) do PATHS[name] = true end

local enabled = true
local injectedClock = nil
local clockState = "unknown"
local clockFailures = 0
local aggregates = {}
local instrumented = setmetatable({}, {__mode="k"})

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

function Performance.Finish(name, startedAt)
    if not enabled or not PATHS[name] then return false end
    startedAt = FiniteNumber(startedAt)
    if not startedAt then return false end
    local finishedAt = ReadClock()
    if not finishedAt then return false end
    local elapsed = finishedAt - startedAt
    if elapsed < 0 then return false end
    local aggregate = aggregates[name]
    if not aggregate then
        aggregate = {count=0, total=0, maximum=0, last=0}
        aggregates[name] = aggregate
    end
    aggregate.count = aggregate.count + 1
    aggregate.total = aggregate.total + elapsed
    aggregate.maximum = math.max(aggregate.maximum, elapsed)
    aggregate.last = elapsed
    return true
end

local function Complete(name, startedAt, ...)
    Performance.Finish(name, startedAt)
    return ...
end

function Performance.Measure(name, callback, ...)
    if type(callback) ~= "function" then error("callback must be a function", 2) end
    if not enabled or not PATHS[name] or clockState == "unavailable" then
        return callback(...)
    end
    local startedAt = ReadClock()
    if not startedAt then return callback(...) end
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
        return true
    end
    aggregates = {}
    clockFailures = 0
    return true
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
        {"dps.update", Nexus.DpsCapture, "OnUpdate"},
        {"community.open", Nexus.CommunityBuilds, "Show"},
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
