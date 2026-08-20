local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

local Errors = Nexus.Errors
local wall = 10000
time = function() return wall end

local hostile = setmetatable({}, {
    __tostring = function() error("hostile tostring") end,
})
NexusDB = {
    settingsVersion=1, settings={autoPick=false}, chars={},
    errorHistory={
        [1]={timestamp=1,source="old",message="first"},
        [2]="malformed",
        [4]={t=4,source="line\nbreak",error=hostile},
        [7]={timestamp=7,source={},message="last valid"},
    },
}
Nexus.Store.Init()
local okInit = Errors.Init()
assert(okInit, "malformed saved error history failed initialization")
local initial = Errors.History()
assert(#initial == 3 and initial[1].message == "first"
    and initial[2].message:find("unprintable", 1, true)
    and initial[2].source == "line break"
    and initial[3].message == "last valid",
    "malformed/hostile history was not sanitized deterministically")

assert(Errors.Clear())
assert(Errors.Record("nil-value", nil) and Errors.Latest().message == "nil",
    "nil errors were not stringified safely")
assert(Errors.Record("table-value", {})
    and Errors.Record("hostile-value", hostile)
    and Errors.Latest().message:find("unprintable", 1, true),
    "table/hostile errors were not stringified safely")
local recursiveHostile = setmetatable({}, {
    __tostring = function()
        local nested = Errors.Record("recursive-tostring", "must not persist")
        assert(nested == false, "hostile tostring bypassed the recursion guard")
        return "guarded hostile value"
    end,
})
assert(Errors.Record("guard-test", recursiveHostile)
    and Errors.Latest().message == "guarded hostile value",
    "hostile tostring was not handled without recursive retention")
assert(Errors.Clear())

for i = 1, 25 do
    wall = 10000 + i
    assert(Errors.Record("source-" .. i, "error-" .. i))
end
local retained = Errors.History()
assert(#retained == 20 and retained[1].message == "error-6"
    and retained[20].message == "error-25"
    and retained[1].timestamp < retained[20].timestamp,
    "history did not retain the newest 20 in chronological order")
retained[20].message = "mutated"
assert(Errors.Latest().message == "error-25",
    "history query exposed mutable SavedVariables entries")

-- Reload the module itself while keeping SavedVariables.
dofile("core/Errors.lua")
Errors = Nexus.Errors
assert(Errors.Init() and #Errors.History() == 20
    and Errors.Latest().message == "error-25",
    "bounded error history did not survive module reload")

-- A hostile persistence surface may fail, but must not recursively record.
local savedDB = NexusDB
NexusDB = setmetatable({}, {
    __newindex = function()
        local nested = Errors.Record("recursive", "inner")
        assert(nested == false, "recursion guard admitted a nested record")
        error("storage denied")
    end,
})
local persisted, persistError = Errors.Record("outer", "storage failure")
assert(persisted == false and type(persistError) == "string"
    and Nexus.lastError == "storage failure",
    "persistence failure recursed or lost the compatibility error")
NexusDB = savedDB

-- Boot the real Main/LogViewer integration around the retained history.
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Relay.lua")
dofile("logic/Policy.lua")
dofile("core/GameAdapter.lua")
dofile("ui/Readout.lua")
dofile("ui/Panel.lua")
dofile("ui/JournalTab.lua")
dofile("ui/LogViewer.lua")

local diagnosticProvider, clearProvider, shownTab
local realLogInit, realLogShow = Nexus.LogViewer.Init, Nexus.LogViewer.Show
Nexus.LogViewer.Init = function(provider, clearer)
    diagnosticProvider, clearProvider = provider, clearer
    realLogInit(provider, clearer)
end
Nexus.LogViewer.Show = function(tabKey) shownTab = tabKey end
local updateCountBeforeMain = #H.updateHandlers
dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")
local mainUpdate = H.updateHandlers[updateCountBeforeMain + 1]
assert(type(mainUpdate) == "function", "Main OnUpdate handler was not installed")

H.wishlist = {name="Errors",class="MAGE",echoes={
    {spellId=200100,quality=3,stacks=1},
}}
H.playerLevel = 5
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("SPELLS_CHANGED")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(1)

assert(type(diagnosticProvider) == "function" and type(clearProvider) == "function",
    "Main did not wire diagnostic providers")
local errorPage = diagnosticProvider("errors")
assert(errorPage:find("ERRORS -- newest last", 1, true)
    and errorPage:find("error-25", 1, true)
    and not errorPage:find("error-5", 1, true),
    "Errors log page omitted or misordered retained history")

local exportJob = Nexus.NewAIExportCoroutine()
local exportText
while coroutine.status(exportJob) ~= "dead" do
    local okResume, value = coroutine.resume(exportJob)
    assert(okResume, "comprehensive diagnostic export failed: " .. tostring(value))
    exportText = value
end
assert(type(exportText) == "string"
    and exportText:find("|errors=20", 1, true)
    and exportText:find("E|index|time|sourceRef|messageRef", 1, true)
    and exportText:find("E|20|", 1, true),
    "comprehensive export omitted structured errors")

-- A Step exception remains fail-closed and is retained with its source.
local function MutationCounts()
    return {#H.selectCalls,#H.banishCalls,#H.freezeCalls,H.rerollCalls,
        #H.saveCalls,#H.activateCalls}
end
local before = MutationCounts()
local originalCompile = Nexus.Strategy.Compile
Nexus.Strategy.Compile = function() error("forced compile failure") end
assert(Nexus.RefreshPanel() == false, "forced Step exception was reported as success")
Nexus.Strategy.Compile = originalCompile
local after = MutationCounts()
for i, count in ipairs(after) do
    assert(count == before[i], "Step exception authorized a gameplay mutation")
end
local latest = Errors.Latest()
assert(latest and latest.source == "RefreshPanel.Step"
    and latest.message:find("forced compile failure", 1, true),
    "Step exception was not retained with a structured source")

-- A polling exception must stop the tick before Step can use stale state.
local originalPoll = Nexus.GameAdapter.Poll
local compileCalls = 0
Nexus.GameAdapter.Poll = function() error("forced poll failure") end
Nexus.Strategy.Compile = function(...)
    compileCalls = compileCalls + 1
    return originalCompile(...)
end
before = MutationCounts()
mainUpdate(nil, 1)
after = MutationCounts()
Nexus.GameAdapter.Poll = originalPoll
Nexus.Strategy.Compile = originalCompile
assert(compileCalls == 0, "poll failure still ran Step against stale state")
for i, count in ipairs(after) do
    assert(count == before[i], "poll failure authorized a gameplay mutation")
end
latest = Errors.Latest()
assert(latest and latest.source == "GameAdapter.Poll"
    and latest.message:find("forced poll failure", 1, true),
    "poll exception was not retained with its structured source")

H.chat = {}
SlashCmdList["NEXUS"]("err")
assert(H.ChatContains("forced poll failure"),
    "/nexus err did not report the newest retained message")
SlashCmdList["NEXUS"]("log errors")
assert(shownTab == "errors", "/nexus log errors did not route to the Errors view")

-- Clearing from the Errors view is deliberately selective.
local decisions = {{marker="keep"}}
local settings = NexusDB.settings
NexusDB.decisionLog = decisions
assert(clearProvider("errors") and #Errors.History() == 0,
    "Errors-view clear did not remove error history")
assert(NexusDB.decisionLog == decisions and NexusDB.settings == settings,
    "Errors-view clear changed unrelated logs or settings")

-- The real view can create and render its wrapped tab layout without error.
Nexus.LogViewer.Show = realLogShow
assert(pcall(realLogShow, "errors"), "real Errors tab failed to open")
assert(_G.NexusLogViewer and _G.NexusLogViewer:IsShown(),
    "real Errors view was not shown")

print("bounded structured error retention, export, routing, clear, and fail-closed behavior -- OK")
