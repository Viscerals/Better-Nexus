-- Live test.2 automation regression: an unchanged five-second fallback must
-- remain a cheap signature check while the direct 0.2-second safety Poll stays
-- exact. This loads the real runtime, Main coordinator, policy, adapter, Store,
-- view-model, and panel owners; wrappers count calls but do not replace work.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Relay.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/Readout.lua")
dofile("ui/Panel.lua")
dofile("ui/JournalTab.lua")

local counts = {
    compiles=0,wishlistKeys=0,catalog=0,wishlist=0,slots=0,owned=0,
    locked=0,disabled=0,boards=0,policy=0,progress=0,hudModels=0,
    panelRenders=0,statusUpdates=0,
}
local statusValue

local function Wrap(owner, name, key)
    local original = assert(owner[name], "missing production owner: " .. name)
    owner[name] = function(...)
        counts[key] = counts[key] + 1
        return original(...)
    end
end

Wrap(Nexus.Strategy, "Compile", "compiles")
Wrap(Nexus.GameAdapter, "WishlistKey", "wishlistKeys")
local realCatalog = assert(Nexus.GameAdapter.Catalog)
Nexus.GameAdapter.Catalog = function(...)
    local trace = debug and debug.traceback and debug.traceback("", 2) or ""
    local runtimeAt = trace:find("AutomationRuntime.lua", 1, true)
    local adapterAt = trace:find("GameAdapter.lua", 1, true)
    if runtimeAt and (not adapterAt or runtimeAt < adapterAt) then
        counts.catalog = counts.catalog + 1
    end
    return realCatalog(...)
end
Wrap(Nexus.GameAdapter, "Wishlist", "wishlist")
Wrap(Nexus.GameAdapter, "Slots", "slots")
Wrap(Nexus.GameAdapter, "Owned", "owned")
Wrap(Nexus.GameAdapter, "LockedOwned", "locked")
Wrap(Nexus.GameAdapter, "DisabledLevers", "disabled")
Wrap(Nexus.GameAdapter, "Board", "boards")
Wrap(Nexus.Policy, "Decide", "policy")
Wrap(Nexus.Panel, "Render", "panelRenders")
local realSetStatus = assert(Nexus.Panel.SetStatus)
Nexus.Panel.SetStatus = function(value, ...)
    counts.statusUpdates = counts.statusUpdates + 1
    statusValue = tostring(value or "")
    return realSetStatus(value, ...)
end

local wishlistEchoes, savedEchoes = {}, {}
for index = 1, 85 do
    local spellId = ({200100,200102,200104})[(index - 1) % 3 + 1]
    wishlistEchoes[index] = {spellId=spellId,quality=3,stacks=1}
    savedEchoes[index] = {spellId=spellId,quality=3,stacks=1}
end

local slots = {}
for slot = 1, 5 do
    local echoes = {}
    for index, echo in ipairs(savedEchoes) do
        echoes[index] = {
            spellId=echo.spellId,quality=echo.quality,stacks=echo.stacks,
        }
    end
    slots[slot] = {
        slot=slot,name="Fallback Slot " .. slot,verified=true,echoes=echoes,
    }
end

NexusDB = {
    settings={autoPick=false,autoLockEchoes=false},
    chars={},communityBuilds={},buildFilters={},dpsCapture={},
}
H.playerLevel = 80
H.wishlist = {name="Live Fallback Fixture",class="MAGE",echoes=wishlistEchoes}
H.granted = {
    ["Alpha Strike"]={{spellId=200100,quality=3}},
    ["Beta Guard"]={{spellId=200102,quality=2}},
}
H.locked = {{spellId=200104,quality=2,stack=1}}
H.DeliverSlots(slots, 1)

dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/WishlistModel.lua")
dofile("core/MainViewModel.lua")
local viewFactory = assert(Nexus.MainInternals
    and Nexus.MainInternals.ViewModel
    and Nexus.MainInternals.ViewModel.New,
    "real Main view-model factory unavailable")
Nexus.MainInternals.ViewModel.New = function(options)
    local viewModel = viewFactory(options)
    local progress = assert(viewModel.BuildProgress)
    viewModel.BuildProgress = function(...)
        counts.progress = counts.progress + 1
        return progress(...)
    end
    local hud = assert(viewModel.BuildHudDisplayModel)
    viewModel.BuildHudDisplayModel = function(...)
        counts.hudModels = counts.hudModels + 1
        return hud(...)
    end
    return viewModel
end
dofile("core/MainDiagnostics.lua")
local stutterProvider, stutterRegistrations = nil, 0
_G.StutterAlert = {
    DIAGNOSTIC_PROVIDER_API=1,
    RegisterDiagnosticProvider=function(addonName, provider)
        assert(addonName=="Nexus" and type(provider)=="function",
            "Nexus registered an invalid StutterAlert provider")
        stutterRegistrations = stutterRegistrations + 1
        stutterProvider = provider
        return true
    end,
    UnregisterDiagnosticProvider=function(addonName)
        return addonName=="Nexus"
    end,
}
dofile("core/Main.lua")
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")
assert(stutterRegistrations==1 and type(stutterProvider)=="function",
    "initialized Nexus did not register its optional diagnostic provider")

-- Establish one current static context immediately before the measured window.
H.Advance(1, 0.2)
assert(Nexus.RequestRecompute())
H.Advance(0.2, 0.2)

local function Snapshot()
    local out = {}
    for key, value in pairs(counts) do out[key] = value end
    local recompute = Nexus.RecomputeStats()
    for _, key in ipairs({
        "polls","fullSteps","fallbacks","staticProbes","planCompiles",
        "wishlistFingerprints","lockContextRebuilds","autoLockEvaluations",
    }) do
        out[key] = tonumber(recompute[key]) or 0
    end
    out.actions = #H.selectCalls + #H.banishCalls + #H.freezeCalls
        + H.rerollCalls + #H.activateCalls + #H.saveCalls
    out.statusValue = statusValue
    return out
end

local before = Snapshot()
local fallbackChecksBefore = Nexus.Performance.Stats(
    "automation.fallback.check").count
local fallbackRepairsBefore = Nexus.Performance.Stats(
    "automation.fallback.repair").count
local intervals = 20
for _ = 1, intervals do H.Advance(5, 0.2) end
local after = Snapshot()

local function Delta(key) return after[key] - before[key] end
local expectedPolls = intervals * 25
local unchangedFallbackChecks = Nexus.Performance.Stats(
    "automation.fallback.check").count - fallbackChecksBefore
local unchangedFallbackRepairs = Nexus.Performance.Stats(
    "automation.fallback.repair").count - fallbackRepairsBefore
assert(Delta("polls") == expectedPolls,
    string.format("direct Poll cadence changed: expected=%d actual=%d",
        expectedPolls, Delta("polls")))
assert(Delta("policy") == 0 and Delta("actions") == 0,
    string.format("unchanged manual/no-board fixture reached Policy or actions: policy=%d actions=%d",
        Delta("policy"), Delta("actions")))
assert(NexusDB.settings.autoPick == false and H.Perks.currentChoice == nil,
    "fixture lost auto=false or unexpectedly gained a board")
assert(after.statusValue == before.statusValue,
    "unchanged fallback changed the visible status output")
assert(unchangedFallbackChecks == intervals
    and unchangedFallbackRepairs == 0,
    "fallback aggregate metrics did not isolate cheap checks from repairs")

print(string.format(
    "live fallback characterization: intervals=%d polls=%d checks=%d repairs=%d full=%d fallbacks=%d probes=%d compiles=%d fingerprints=%d catalog=%d wishlist=%d slots=%d owned=%d locked=%d lockContext=%d autoLock=%d progress=%d hud=%d panel=%d statusUpdates=%d policy=%d actions=%d",
    intervals,Delta("polls"),unchangedFallbackChecks,
    unchangedFallbackRepairs,Delta("fullSteps"),Delta("fallbacks"),
    Delta("staticProbes"),Delta("compiles"),Delta("wishlistKeys"),
    Delta("catalog"),Delta("wishlist"),Delta("slots"),Delta("owned"),
    Delta("locked"),Delta("lockContextRebuilds"),
    Delta("autoLockEvaluations"),Delta("progress"),
    Delta("hudModels"),Delta("panelRenders"),Delta("statusUpdates"),
    Delta("policy"),Delta("actions")))

assert(Delta("fullSteps") == 0
    and Delta("staticProbes") == 0
    and Delta("compiles") == 0
    and Delta("wishlistKeys") == 0
    and Delta("catalog") == 0
    and Delta("wishlist") == 0
    and Delta("slots") == 0
    and Delta("owned") == 0
    and Delta("locked") == 0
    and Delta("autoLockEvaluations") == 0
    and Delta("progress") == 0
    and Delta("hudModels") == 0
    and Delta("panelRenders") == 0,
    "unchanged five-second fallback entered expensive pre-Policy work")

-- Replace one dependency without firing an adapter hook. The bounded
-- identity fallback must repair it once, then return to cheap checks.
local repairBefore = Snapshot()
local repairClock = 100
assert(Nexus.Performance.SetClock(function() return repairClock end))
local originalBegin, originalFinish = Nexus.Performance.Begin,
    Nexus.Performance.Finish
Nexus.Performance.Begin = function(name, ...)
    if name == "automation.fallback.repair" then repairClock = 100 end
    return originalBegin(name, ...)
end
Nexus.Performance.Finish = function(name, startedAt, fields)
    if name == "automation.fallback.repair" then repairClock = 602.7 end
    return originalFinish(name, startedAt, fields)
end
H.Perks.serverBuildSlots[1].name = "Fallback Slot 1 updated"
H.Advance(5.2, 0.2)
local repairAfter = Snapshot()
assert(repairAfter.fullSteps - repairBefore.fullSteps == 1
    and repairAfter.staticProbes - repairBefore.staticProbes == 1,
    string.format("missed slot-content change did not repair exactly once: full=%d probes=%d reason=%s",
        repairAfter.fullSteps - repairBefore.fullSteps,
        repairAfter.staticProbes - repairBefore.staticProbes,
        tostring(Nexus.RecomputeStats().lastFallbackReason)))
assert(Nexus.Performance.Stats("automation.fallback.repair").count
        - fallbackRepairsBefore == 1,
    "missed-signal repair was not recorded exactly once")
local repairStats = Nexus.RecomputeStats()
assert(repairStats.lastFallbackReason=="fallback:slots"
    and repairStats.fallbackMismatchFields.slots==1,
    "real slot-signature mismatch was not the repair classification source")
local capture = stutterProvider({
    addonName="Nexus",
    hitchStartTime=H.now - 1,
    hitchEndTime=H.now,
    profilingTimestamp=H.now,
    profileWindowMs=1000,
    frameDurationMs=600,
    addonCpuDeltaMs=550,
    totalAddonCpuDeltaMs=570,
    addonShare=0.91,
    attributionConfidence=0.91,
    attributionMode="sampled",
})
assert(type(capture)=="table" and type(capture.operations)=="table"
    and capture.operations[1].name=="automation.fallback.repair"
    and math.abs(capture.operations[1].durationMs - 502.7) < 0.0001,
    "real fallback repair did not produce the correlated 502.7 ms operation")
local repairFields = {}
for _, field in ipairs(capture.operations[1].fields or {}) do
    repairFields[field.key] = field.value
end
assert(repairFields.trigger=="fallback" and repairFields.mismatch=="slots",
    "provider did not expose the real fallback trigger/slot mismatch")
Nexus.Performance.Begin, Nexus.Performance.Finish = originalBegin, originalFinish
assert(Nexus.Performance.SetClock(nil))
H.Advance(5.2, 0.2)
local repairSettled = Snapshot()
assert(repairSettled.fullSteps == repairAfter.fullSteps
    and repairSettled.staticProbes == repairAfter.staticProbes
    and repairSettled.compiles == repairAfter.compiles,
    "repaired fallback dependency repeated expensive work")

print(string.format("live fallback repair: checks=%d repairs=%d full=%d probes=%d compiles=%d",
    Nexus.Performance.Stats("automation.fallback.check").count
        - fallbackChecksBefore,
    Nexus.Performance.Stats("automation.fallback.repair").count
        - fallbackRepairsBefore,
    repairSettled.fullSteps - repairBefore.fullSteps,
    repairSettled.staticProbes - repairBefore.staticProbes,
    repairSettled.compiles - repairBefore.compiles))

print("live automation fallback budget: exact Poll cadence, cheap unchanged checks, and one-shot missed-signal repair -- OK")
