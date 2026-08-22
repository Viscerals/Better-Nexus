-- Aggregate performance diagnostics stay bounded, preserve callback behavior,
-- and remain observational through real Main/log/export integration.
local H = dofile("tests/harness.lua")
local Performance = Nexus.Performance

local definitions = Performance.Definitions()
local definitionSet = {}
for _, name in ipairs(definitions) do definitionSet[name] = true end
assert(#definitions == 37 and definitions[1] == "automation.step"
    and definitions[2] == "automation.fallback.check"
    and definitions[3] == "automation.fallback.repair"
    and definitions[37] == "gameadapter.poll"
    and definitionSet["automation.phase.static"]
    and definitionSet["automation.phase.catalog"]
    and definitionSet["automation.phase.wishlist"]
    and definitionSet["automation.phase.wishlist-fingerprint"]
    and definitionSet["automation.phase.plan"]
    and definitionSet["automation.phase.slots"]
    and definitionSet["automation.phase.owned"]
    and definitionSet["automation.phase.levers"]
    and definitionSet["automation.phase.board"]
    and definitionSet["automation.phase.board-prepare"]
    and definitionSet["automation.phase.policy"]
    and definitionSet["automation.phase.autolock"]
    and definitionSet["automation.phase.preauthorize"]
    and definitionSet["automation.phase.overlay-prepare"]
    and definitionSet["automation.phase.overlay-render"],
    "performance path registry is not fixed and ordered")

Performance.Reset()
Performance.SetEnabled(true)
local clockValue, clockCalls = 0, 0
assert(Performance.SetClock(function()
    clockCalls = clockCalls + 1
    clockValue = clockValue + 2.5
    return clockValue
end))

local resultCount, resultA, resultB, resultC
local function CaptureResults(...)
    resultCount = select("#", ...)
    resultA, resultB, resultC = ...
end
CaptureResults(Performance.Measure("automation.step", function()
    return "first", nil, "third"
end))
assert(resultCount == 3 and resultA == "first" and resultB == nil
    and resultC == "third",
    "measured callback changed multiple/trailing-nil return behavior")
local aggregate = Performance.Stats("automation.step")
assert(aggregate.count == 1 and aggregate.total == 2.5
    and aggregate.maximum == 2.5 and aggregate.last == 2.5,
    "fake-clock aggregate values are incorrect")
assert(Performance.Measure("automation.phase.static", function() return true end))
local phaseAggregate = Performance.Stats("automation.phase.static")
local recentAfterPhase = Performance.RecentOperations(H.now - 1, H.now + 1, H.now)
assert(phaseAggregate.count == 1 and phaseAggregate.total == 2.5
    and #recentAfterPhase == 1
    and recentAfterPhase[1].name == "automation.step",
    "phase aggregate was missing or displaced the outer operation breadcrumb")

local revisionBefore = {
    build=Nexus.Revisions.Get(Nexus.Revisions.BUILD_LIBRARY_CHANGED),
    dps=Nexus.Revisions.Get(Nexus.Revisions.DPS_CHANGED),
    sync=Nexus.Revisions.Get(Nexus.Revisions.SYNC_CHANGED),
    catalog=Nexus.Revisions.Get(Nexus.Revisions.CATALOG_CHANGED),
}
for index = 1, 5000 do
    assert(Performance.Measure("automation.step", function(value) return value end, index) == index)
end
local snapshot = Performance.Snapshot()
assert(#snapshot.rows == #definitions and snapshot.rows[1].count == 5001
    and snapshot.rows[1].total == 12502.5
    and snapshot.rows[1].samples == nil and snapshot.samples == nil,
    "high-volume timing retained samples or produced wrong bounded aggregates")
snapshot.rows[1].count = -1
assert(Performance.Stats("automation.step").count == 5001,
    "performance snapshot leaked mutable aggregate state")
assert(Nexus.Revisions.Get(Nexus.Revisions.BUILD_LIBRARY_CHANGED) == revisionBefore.build
    and Nexus.Revisions.Get(Nexus.Revisions.DPS_CHANGED) == revisionBefore.dps
    and Nexus.Revisions.Get(Nexus.Revisions.SYNC_CHANGED) == revisionBefore.sync
    and Nexus.Revisions.Get(Nexus.Revisions.CATALOG_CHANGED) == revisionBefore.catalog,
    "performance aggregation advanced represented-data revisions")

local bypassCalls = 0
assert(Performance.SetClock(function()
    bypassCalls = bypassCalls + 1
    return bypassCalls
end))
Performance.SetEnabled(false)
assert(Performance.Measure("automation.step", function() return "disabled" end) == "disabled"
    and bypassCalls == 0,
    "disabled timing touched the clock or changed callback behavior")
Performance.SetEnabled(true)
assert(Performance.Measure("unknown.path", function() return "unknown" end) == "unknown"
    and bypassCalls == 0,
    "unknown timing path touched the clock or changed callback behavior")

local failureCalls = 0
Performance.Reset()
Performance.SetClock(function()
    failureCalls = failureCalls + 1
    error("clock unavailable")
end)
assert(Performance.Measure("automation.step", function() return "safe" end) == "safe"
    and Performance.Measure("automation.step", function() return "still safe" end) == "still safe"
    and failureCalls == 1 and Performance.Stats("automation.step").count == 0
    and Performance.Snapshot().clockFailures == 1,
    "unavailable clock did not enter the one-failure cheap bypass")

local finishFailureCalls = 0
Performance.SetClock(function()
    finishFailureCalls = finishFailureCalls + 1
    if finishFailureCalls == 1 then return 10 end
    error("finish clock failed")
end)
assert(Performance.Measure("automation.step", function() return 42 end) == 42
    and Performance.Stats("automation.step").count == 0,
    "finish-clock failure changed work or published a partial aggregate")

local callbackClock = 0
Performance.SetClock(function() callbackClock = callbackClock + 1; return callbackClock end)
local okCallback, callbackError = pcall(Performance.Measure,
    "automation.step", function() error("callback failed") end)
assert(not okCallback and tostring(callbackError):find("callback failed", 1, true)
    and callbackClock == 1 and Performance.Stats("automation.step").count == 0,
    "callback error was hidden, rewritten, or counted as a completed timing")

local owner = {
    Run=function(prefix, value) return prefix .. value, nil, value end,
}
Performance.Reset()
clockValue = 0
Performance.SetClock(function() clockValue = clockValue + 1; return clockValue end)
assert(Performance.Instrument("community.refresh", owner, "Run"))
local wrapperIdentity = owner.Run
assert(Performance.Instrument("community.refresh", owner, "Run")
    and owner.Run == wrapperIdentity,
    "instrumentation was not idempotent")
CaptureResults(owner.Run("row-", 7))
assert(resultCount == 3 and resultA == "row-7" and resultB == nil and resultC == 7
    and Performance.Stats("community.refresh").count == 1,
    "instrumented callback changed results or missed its aggregate")
assert(Performance.Reset("community.refresh")
    and Performance.Stats("community.refresh").count == 0
    and not Performance.Reset("unknown.path"),
    "targeted aggregate reset is incorrect")
Performance.Reset()
local reverseClock = {20, 10}
Performance.SetClock(function() return table.remove(reverseClock, 1) end)
assert(Performance.Measure("automation.step", function() return "reverse-safe" end) == "reverse-safe"
    and Performance.Stats("automation.step").count == 0,
    "backward clock published a negative timing or changed callback behavior")
print("fake clock, bounded aggregates, bypass, errors, reset, instrumentation -- OK")

-- Boot Main with real automation/Sync/DPS/Panel and small optional UI probes.
NexusDB = {settings={autoPick=false}, chars={}, communityBuilds={}}
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Relay.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
dofile("core/DpsCapture.lua")
dofile("core/GameAdapter.lua")
dofile("ui/Readout.lua")
dofile("ui/Panel.lua")
dofile("ui/JournalTab.lua")
dofile("ui/LogViewer.lua")

local optionalCalls = {community=0, leaderboard=0, overlay=0}
Nexus.CommunityBuilds = {
    Init=function() end,
    Refresh=function(value) optionalCalls.community = optionalCalls.community + 1; return value end,
}
Nexus.Leaderboard = {
    Init=function() end,
    RefreshData=function(value) optionalCalls.leaderboard = optionalCalls.leaderboard + 1; return value end,
}
Nexus.WishlistOverlay = {
    Init=function() end,
    Refresh=function(value) optionalCalls.overlay = optionalCalls.overlay + 1; return value end,
}

local diagnosticProvider, clearProvider
local realLogInit = Nexus.LogViewer.Init
Nexus.LogViewer.Init = function(provider, clearer)
    diagnosticProvider, clearProvider = provider, clearer
    return realLogInit(provider, clearer)
end

Performance.Reset()
clockValue = 0
Performance.SetEnabled(true)
Performance.SetClock(function() clockValue = clockValue + 0.5; return clockValue end)
H.wishlist = {name="Performance",class="MAGE",echoes={
    {spellId=200100,quality=3,stacks=1},
}}
H.playerLevel = 5
dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/WishlistModel.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("SPELLS_CHANGED")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(1)

local incomingBefore = Performance.Stats("sync.incoming").count
H.FireEvent("CHAT_MSG_CHANNEL", "WLNP|PerfPeer|1.20.0", "PerfPeer",
    "Common", Nexus.Sync.ChannelName())
assert(Performance.Stats("sync.incoming").count == incomingBefore + 1
    and Nexus.Sync.IsKnownPeer("PerfPeer"),
    "CHAT_MSG_CHANNEL did not attribute the complete incoming Sync handler")
assert(Nexus.ViewRefresh.Request())
H.Advance(0.10)

local malformedDecision = Nexus.Policy.Decide(nil)
assert(type(malformedDecision) == "table" and malformedDecision.type == "wait"
    and malformedDecision.reason == "no board",
    "decision instrumentation changed malformed-input failure behavior")
local optionalBefore = {
    community=optionalCalls.community,
    leaderboard=optionalCalls.leaderboard,
    overlay=optionalCalls.overlay,
}
assert(Nexus.CommunityBuilds.Refresh("community") == "community"
    and Nexus.Leaderboard.RefreshData("leaderboard") == "leaderboard"
    and Nexus.WishlistOverlay.Refresh("overlay") == "overlay"
    and optionalCalls.community == optionalBefore.community + 1
    and optionalCalls.leaderboard == optionalBefore.leaderboard + 1
    and optionalCalls.overlay == optionalBefore.overlay + 1,
    "installed optional UI instrumentation changed callback behavior")
for _, name in ipairs({"automation.step", "decision.policy", "sync.update",
    "sync.incoming", "dps.update", "views.refresh", "hud.prepare",
    "community.refresh", "leaderboard.refresh", "panel.render",
    "overlay.refresh", "lifecycle.update", "automation.update",
    "gameadapter.poll"}) do
    assert(Performance.Stats(name).count > 0,
        "real instrumentation did not observe " .. name)
end

-- Real Panel/HUD preparation is absent during active Sync and attributed once
-- after quiet, whether the frame is open or hidden.
local originalReceiving = Nexus.Sync.IsReceiving
local originalReceiveTimeLeft = Nexus.Sync.ReceiveTimeLeft
local testReceiving = true
Nexus.Sync.IsReceiving = function() return testReceiving end
Nexus.Sync.ReceiveTimeLeft = function() return testReceiving and 1 or 0 end
Nexus.Panel.Show()
local openHudBefore = Performance.Stats("hud.prepare").count
assert(Nexus.ViewRefresh.Request())
H.now = H.now + 0.05
assert(Nexus.Scheduler.Tick(H.now) == 1
    and Performance.Stats("hud.prepare").count == openHudBefore,
    "open Panel prepared a HUD model during active Sync")
testReceiving = false
H.now = H.now + 1.10
assert(Nexus.Scheduler.Tick(H.now) >= 1
    and Performance.Stats("hud.prepare").count == openHudBefore + 1,
    string.format("open Panel post-Sync HUD count mismatch: before=%d after=%d",
        openHudBefore, Performance.Stats("hud.prepare").count))

Nexus.Panel.Hide()
testReceiving = true
local hiddenHudBefore = Performance.Stats("hud.prepare").count
assert(Nexus.ViewRefresh.Request())
H.now = H.now + 0.05
assert(Nexus.Scheduler.Tick(H.now) == 1
    and Performance.Stats("hud.prepare").count == hiddenHudBefore,
    "hidden Panel prepared a HUD model during active Sync")
testReceiving = false
H.now = H.now + 1.10
assert(Nexus.Scheduler.Tick(H.now) >= 1
    and Performance.Stats("hud.prepare").count == hiddenHudBefore + 1,
    string.format("hidden Panel post-Sync HUD count mismatch: before=%d after=%d",
        hiddenHudBefore, Performance.Stats("hud.prepare").count))
Nexus.Sync.IsReceiving = originalReceiving
Nexus.Sync.ReceiveTimeLeft = originalReceiveTimeLeft

assert(type(diagnosticProvider) == "function" and type(clearProvider) == "function",
    "Main did not wire performance diagnostics into LogViewer")
local performanceText = diagnosticProvider("perf")
assert(performanceText:find("PERFORMANCE AGGREGATES", 1, true)
    and performanceText:find("automation.step", 1, true)
    and performanceText:find("no per-call samples", 1, true)
    and performanceText == diagnosticProvider("perf"),
    "performance log page is missing stable aggregate context")

local Logs = Nexus.DiagnosticLogs
assert(Logs.ClearAll() and Logs.Append("decision", {
    t="01:02:03",level=5,horizon=2,charges={},
    proposal={type="wait",reason="performance"},cards={},user={},queueHead={},
}))
local syncStateBefore = Nexus.Sync.WorkState()
assert(clearProvider("perf") and #Logs.Snapshot("decision") == 1,
    "performance reset cleared durable diagnostics")
local syncStateAfter = Nexus.Sync.WorkState()
for key, value in pairs(syncStateBefore) do
    assert(syncStateAfter[key] == value,
        "performance reset changed Sync work state: " .. tostring(key))
end
assert(Performance.Measure("automation.step", function() return true end))

local exportJob = Nexus.NewAIExportCoroutine()
local exportText
while coroutine.status(exportJob) ~= "dead" do
    local okResume, value = coroutine.resume(exportJob)
    assert(okResume, "performance diagnostic export failed: " .. tostring(value))
    exportText = value
end
local exportJobAgain = Nexus.NewAIExportCoroutine()
local exportTextAgain
while coroutine.status(exportJobAgain) ~= "dead" do
    local okResume, value = coroutine.resume(exportJobAgain)
    assert(okResume, "repeated performance diagnostic export failed: " .. tostring(value))
    exportTextAgain = value
end
local performanceRows = 0
for line in (exportText .. "\n"):gmatch("(.-)\n") do
    if line:match("^F|%d+|") then performanceRows = performanceRows + 1 end
end
assert(exportText:find("NEXUS_DIAGNOSTIC_LOG_5", 1, true)
    and exportText:find("F|pathRef|count|totalMs|maximumMs|lastMs", 1, true)
    and exportText:find("\nF|", 1, true)
    and exportText:find("|automation.step", 1, true)
    and exportText:find("END|boards=1", 1, true)
    and performanceRows == #Performance.Definitions()
    and exportText == exportTextAgain,
    "aggregate-only export section is missing or prior export sections changed")
assert(NexusDB.performance == nil and NexusDB.performanceHistory == nil,
    "performance diagnostics leaked into SavedVariables")
print("real hot paths, log view, reset isolation, export, SavedVariables safety -- OK")
