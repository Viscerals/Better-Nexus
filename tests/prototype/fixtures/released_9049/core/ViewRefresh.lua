-- Coalesced refreshes for noncritical data-browser views. Main HUD status and
-- all automation work remain direct and are intentionally not scheduled here.

Nexus = Nexus or {}
local ViewRefresh = {}
Nexus.ViewRefresh = ViewRefresh

local REFRESH_KEY = "ui.data-views.refresh"
local initialized = false
local schedulerReady = false
local deferredCommunity = false
local communityOwnsDeferred = false
local deferredLeaderboard = false
local deferredPanel = false
local RefreshViews

local function RecordError(source, err)
    local errors = Nexus and Nexus.Errors
    if errors and type(errors.Record) == "function" then
        pcall(errors.Record, source, err)
    end
end

local function SafeRefresh(source, callback)
    if type(callback) ~= "function" then return false end
    local ok, err = pcall(callback)
    if not ok then RecordError(source, err) end
    return ok
end

local function RequestLegacyRepair(reason)
    local repair = Nexus and Nexus.LegacyQualificationRepair
    if not (repair and type(repair.Request) == "function") then
        return true, "unavailable"
    end
    local ok, ready, err = pcall(repair.Request, reason)
    if not ok or ready == false then
        RecordError("ViewRefresh.LegacyQualificationRepair",
            ok and err or ready)
        return false, "failed"
    end
    return true, err
end

local function ReceiveState()
    local sync = Nexus.Sync
    if not (sync and type(sync.IsReceiving) == "function") then
        return false, 0
    end
    local ok, receiving = pcall(sync.IsReceiving)
    if not ok then
        RecordError("ViewRefresh.Sync.IsReceiving", receiving)
        return false, 0
    end
    local remaining = 0
    if receiving and type(sync.ReceiveTimeLeft) == "function" then
        local okRemaining, raw = pcall(sync.ReceiveTimeLeft)
        local value = okRemaining and tonumber(raw) or nil
        if value and value == value and value < math.huge and value > -math.huge then
            remaining = math.max(0, value)
        else RecordError("ViewRefresh.Sync.ReceiveTimeLeft", raw) end
    end
    return receiving and true or false, remaining
end

local function CanDefer()
    local scheduler = Nexus.Scheduler
    return initialized and schedulerReady and scheduler
        and type(scheduler.After) == "function"
end

local function ScheduleAfterReceive(remaining)
    if not CanDefer() then return false end
    remaining = tonumber(remaining)
    if not remaining or remaining ~= remaining or remaining >= math.huge
        or remaining <= -math.huge then remaining = 0 end
    local delay = math.max(0.05, remaining + 0.05)
    return Nexus.Scheduler.After(REFRESH_KEY, delay, RefreshViews)
end

local function RefreshCommunity(receiving)
    local community = Nexus.CommunityBuilds
    if not community then return false end
    if receiving and type(community.MarkDataDirty) == "function" then
        return SafeRefresh("ViewRefresh.CommunityBuilds.MarkDataDirty",
            community.MarkDataDirty)
    end
    return SafeRefresh("ViewRefresh.CommunityBuilds", community.Refresh)
end

local function RunRefreshViews()
    -- A sync burst may commit many individually valid build/DPS revisions.
    -- Keep direct status paths live, but publish noncritical data once after
    -- the receive window closes instead of rebuilding the same represented
    -- state for every packet group.
    local receiving, remaining = ReceiveState()
    if receiving and CanDefer() then
        local community = Nexus.CommunityBuilds
        if community and (type(community.MarkDataDirty) == "function"
            or type(community.Refresh) == "function") then
            deferredCommunity = true
            if type(community.MarkDataDirty) == "function" then
                communityOwnsDeferred = RefreshCommunity(true)
                    or communityOwnsDeferred
            end
        end
        if Nexus.Leaderboard and (type(Nexus.Leaderboard.Refresh) == "function"
            or type(Nexus.Leaderboard.MarkDataDirty) == "function") then
            deferredLeaderboard = true
            if type(Nexus.Leaderboard.MarkDataDirty) == "function" then
                SafeRefresh("ViewRefresh.Leaderboard.MarkDataDirty",
                    Nexus.Leaderboard.MarkDataDirty)
            end
        end
        if Nexus.Panel and type(Nexus.Panel.Refresh) == "function" then
            deferredPanel = true
        end
        ScheduleAfterReceive(remaining)
        return true
    end

    local hadDeferred = deferredCommunity or deferredLeaderboard or deferredPanel
    local repairReady, repairState = RequestLegacyRepair(
        hadDeferred and "sync" or "refresh")
    if repairReady and (repairState == "scheduled"
        or repairState == "coalesced") and CanDefer() then
        ScheduleAfterReceive(0)
        return true
    end
    if hadDeferred then
        local refreshCommunity = deferredCommunity and not communityOwnsDeferred
        local refreshLeaderboard, refreshPanel = deferredLeaderboard, deferredPanel
        -- Community owns its dirty bit and open-frame post-window publication.
        -- Calling it again here can race that publication into a duplicate.
        deferredCommunity = false
        communityOwnsDeferred = false
        deferredLeaderboard = false
        deferredPanel = false
        if refreshCommunity then
            SafeRefresh("ViewRefresh.CommunityBuilds",
                Nexus.CommunityBuilds and Nexus.CommunityBuilds.Refresh)
        end
        if refreshLeaderboard then
            SafeRefresh("ViewRefresh.Leaderboard",
                Nexus.Leaderboard and Nexus.Leaderboard.Refresh)
        end
        if refreshPanel then
            SafeRefresh("ViewRefresh.Panel",
                Nexus.Panel and Nexus.Panel.Refresh)
        end
        return true
    end

    RefreshCommunity(receiving)
    SafeRefresh("ViewRefresh.Leaderboard",
        Nexus.Leaderboard and Nexus.Leaderboard.Refresh)
    SafeRefresh("ViewRefresh.Panel",
        Nexus.Panel and Nexus.Panel.Refresh)
    return true
end

RefreshViews = function()
    local performance = Nexus and Nexus.Performance
    if performance and type(performance.Measure) == "function" then
        return performance.Measure("views.refresh", RunRefreshViews)
    end
    return RunRefreshViews()
end

function ViewRefresh.Request()
    local scheduler = Nexus.Scheduler
    if initialized and schedulerReady and scheduler
        and type(scheduler.After) == "function" then
        return scheduler.After(REFRESH_KEY, 0.05, RefreshViews)
    end
    RefreshViews()
    return true
end

function ViewRefresh.Init()
    if initialized then return true end
    initialized = true
    local scheduler = Nexus.Scheduler
    if scheduler and scheduler.Init then
        schedulerReady = scheduler.Init() ~= nil
    end
    local revisions = Nexus.Revisions
    if revisions and type(revisions.Subscribe) == "function" then
        revisions.Subscribe(revisions.BUILD_LIBRARY_CHANGED, ViewRefresh.Request)
        revisions.Subscribe(revisions.DPS_CHANGED, ViewRefresh.Request)
    end
    return true
end

function ViewRefresh.Key()
    return REFRESH_KEY
end
