-- Residual freeze attribution stays aggregate-only while active-Sync view work
-- is coalesced. No inbound FIFO is introduced: accepted messages still finish
-- synchronously and in arrival order.
local H = dofile("tests/harness.lua")
Nexus.Errors.Init()

NexusDB = {communityBuilds={}, syncTombstones={}}
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
local Sync = Nexus.Sync
Sync.Init(Nexus.Codec, {})

local builds, dpsRows = {}, {}
for index = 1, 1000 do
    builds[index] = {id="freeze-build-" .. index, title="Build " .. index}
end
for index = 1, 500 do
    dpsRows[index] = {player="Player" .. index, dps=100000 + index}
end

local shown = {community=false, leaderboard=false, panel=false}
local calls = {community=0, leaderboard=0, panel=0}
local publications = {community=0, leaderboard=0, panel=0}
local statusCalls = {leaderboard=0, panel=0}
local heavyRows, communityDirty, dirtyMarks = 0, false, 0
local function ConsumeLargeFixture()
    for index = 1, #builds do
        heavyRows = heavyRows + (builds[index].id and 1 or 0)
    end
    for index = 1, #dpsRows do
        heavyRows = heavyRows + (dpsRows[index].player and 1 or 0)
    end
end

Nexus.CommunityBuilds = {
    MarkDataDirty=function()
        if not communityDirty then
            communityDirty, dirtyMarks = true, dirtyMarks + 1
        end
        return true
    end,
    Refresh=function()
        calls.community = calls.community + 1
        if not shown.community then return end
        communityDirty = false
        publications.community = publications.community + 1
        ConsumeLargeFixture()
        return true
    end,
}
Nexus.Leaderboard = {
    RefreshStatus=function()
        statusCalls.leaderboard = statusCalls.leaderboard + 1
        return true
    end,
    RefreshData=function()
        calls.leaderboard = calls.leaderboard + 1
        if not shown.leaderboard then return end
        publications.leaderboard = publications.leaderboard + 1
        ConsumeLargeFixture()
        return true
    end,
}
Nexus.Leaderboard.Refresh = function()
    return Nexus.Leaderboard.RefreshData()
end
Nexus.Panel = {
    SetStatus=function()
        statusCalls.panel = statusCalls.panel + 1
        return true
    end,
    Refresh=function()
        calls.panel = calls.panel + 1
        if not shown.panel then return end
        publications.panel = publications.panel + 1
        ConsumeLargeFixture()
        return true
    end,
}

local receiving, remaining = true, 3
Sync.IsReceiving = function() return receiving end
Sync.ReceiveTimeLeft = function() return receiving and remaining or 0 end

local Performance = Nexus.Performance
Performance.Reset()
Performance.SetEnabled(true)
local clock = 0
Performance.SetClock(function()
    clock = clock + 0.25
    return clock
end)
Performance.InstallDefaults()

assert(Nexus.ViewRefresh.Init())
assert(Nexus.Scheduler.IsInitialized())

-- One hidden and 100 open invalidations still become one cheap active callback.
assert(Nexus.ViewRefresh.Request())
shown.community, shown.leaderboard, shown.panel = true, true, true
for _ = 1, 100 do assert(Nexus.ViewRefresh.Request()) end
local pending = Nexus.Scheduler.Pending()
assert(#pending == 1 and pending[1].key == Nexus.ViewRefresh.Key(),
    "active view invalidations did not coalesce")
H.now = H.now + 0.05
assert(Nexus.Scheduler.Tick(H.now) == 1)
assert(calls.community == 0 and calls.leaderboard == 0 and calls.panel == 0
    and heavyRows == 0 and dirtyMarks == 1,
    "active Sync performed a heavy Community, Leaderboard, or Panel rebuild")
assert(Nexus.Leaderboard.RefreshStatus() and Nexus.Panel.SetStatus("syncing")
    and statusCalls.leaderboard == 1 and statusCalls.panel == 1
    and heavyRows == 0,
    "status-only UI stopped updating while data views were deferred")
assert(Performance.Stats("views.refresh").count == 1,
    "complete scheduled view callback was not attributed")

-- The keyed quiet callback publishes each deferred noncritical view once.
receiving, remaining = false, 0
H.now = H.now + 3.10
assert(Nexus.Scheduler.Tick(H.now) == 1)
assert(calls.community == 0 and calls.leaderboard == 1 and calls.panel == 1,
    "deferred Leaderboard/Panel work did not publish exactly once")
assert(communityDirty, "ViewRefresh consumed Community's owned dirty state")
assert(Nexus.CommunityBuilds.Refresh()) -- Community owns its post-window publish.
assert(publications.community == 1 and publications.leaderboard == 1
    and publications.panel == 1 and heavyRows == 4500,
    "post-Sync views did not each publish the 1000-build/500-DPS fixture once")
assert(Nexus.Scheduler.Tick(H.now + 1) == 0
    and publications.community == 1 and publications.leaderboard == 1
    and publications.panel == 1,
    "quiet view publication duplicated without another invalidation")

-- Hidden views remain cheap during another complete receive/quiet cycle.
shown.community, shown.leaderboard, shown.panel = false, false, false
receiving, remaining = true, 2
assert(Nexus.ViewRefresh.Request())
H.now = H.now + 0.05
assert(Nexus.Scheduler.Tick(H.now) == 1)
local callsBeforeQuiet = calls.community + calls.leaderboard + calls.panel
receiving, remaining = false, 0
H.now = H.now + 2.10
assert(Nexus.Scheduler.Tick(H.now) == 1)
assert(heavyRows == 4500 and calls.community + calls.leaderboard + calls.panel
    == callsBeforeQuiet + 2,
    "hidden Community, Leaderboard, or Panel performed heavy deferred work")

-- The complete real Sync handler is measured for a sustained validated burst.
local viewSamples = Performance.Stats("views.refresh").count
Performance.Reset()
local mutationBefore = {
    wire=#H.wire, select=#H.selectCalls, banish=#H.banishCalls,
    freeze=#H.freezeCalls, reroll=H.rerollCalls,
    activate=#H.activateCalls, save=#H.saveCalls,
}
for index = 1, 100 do
    local sender = string.format("Peer%03d", index)
    assert(Sync.HandleIncoming("WLNP|" .. sender .. "|1.20.0", sender),
        "validated incoming message was lost at " .. index)
    assert(Sync.IsKnownPeer(sender),
        "incoming message did not complete synchronously in arrival order")
end
local incoming = Performance.Stats("sync.incoming")
assert(incoming.count == 100 and incoming.total == 25
    and incoming.maximum == 0.25 and incoming.last == 0.25,
    "complete incoming Sync handler aggregate is incomplete")
assert(Sync.WorkState().knownPeers == 100 and Sync.WorkState().outbound == 0,
    "incoming burst lost/reordered peers or created outbound payload work")
assert(#H.wire == mutationBefore.wire and #H.selectCalls == mutationBefore.select
    and #H.banishCalls == mutationBefore.banish
    and #H.freezeCalls == mutationBefore.freeze
    and H.rerollCalls == mutationBefore.reroll
    and #H.activateCalls == mutationBefore.activate
    and #H.saveCalls == mutationBefore.save,
    "incoming diagnostics or deferred views submitted gameplay mutations")
local snapshot = Performance.Snapshot()
assert(incoming.samples == nil and snapshot.samples == nil
    and NexusDB.performance == nil and NexusDB.performanceHistory == nil,
    "freeze attribution retained samples or entered SavedVariables")

print(string.format(
    "freeze attribution: incoming=%d views=%d builds=%d dps=%d heavyActive=0 publications=1/1/1 -- OK",
    incoming.count, viewSamples,
    #builds, #dpsRows))
