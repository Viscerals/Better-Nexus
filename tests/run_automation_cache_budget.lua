-- Large-fixture automation cache budget: direct 0.2s polling stays live while
-- unchanged and board-only work reuses static plan/lock context.
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

local compileCalls, fingerprintCalls = 0, 0
local automationCatalogCalls = 0
local realCompile = Nexus.Strategy.Compile
Nexus.Strategy.Compile = function(...)
    compileCalls = compileCalls + 1
    return realCompile(...)
end
local realWishlistKey = Nexus.GameAdapter.WishlistKey
Nexus.GameAdapter.WishlistKey = function(...)
    fingerprintCalls = fingerprintCalls + 1
    return realWishlistKey(...)
end
local realCatalog = Nexus.GameAdapter.Catalog
Nexus.GameAdapter.Catalog = function(...)
    local trace = debug and debug.traceback and debug.traceback("", 2) or ""
    local runtimeAt = trace:find("AutomationRuntime.lua", 1, true)
    local adapterAt = trace:find("GameAdapter.lua", 1, true)
    if runtimeAt and (not adapterAt or runtimeAt < adapterAt) then
        automationCatalogCalls = automationCatalogCalls + 1
    end
    return realCatalog(...)
end

local wishlistEchoes, savedEchoes = {}, {}
for index = 1, 71 do
    wishlistEchoes[index] = {
        spellId=200100 + (index % 3),quality=3,stacks=1,
    }
end
for index = 1, 85 do
    savedEchoes[index] = {
        spellId=200100 + (index % 3),quality=3,stacks=1,
    }
end
NexusDB = {settings={autoPick=false,autoLockEchoes=false},chars={}}
H.playerLevel = 5
H.wishlist = {name="Cache Fixture",class="MAGE",echoes=wishlistEchoes}
H.granted = {}

dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(1)

local baseline = Nexus.RecomputeStats()
assert(baseline.planCompiles and baseline.wishlistFingerprints
    and baseline.autoLockEvaluations,
    "automation cache counters are unavailable")
local stableCompile, stableFingerprint, stableCatalog =
    compileCalls, fingerprintCalls, automationCatalogCalls
H.Advance(1)
local stable = Nexus.RecomputeStats()
assert(stable.polls >= baseline.polls + 5
    and stable.fullSteps == baseline.fullSteps
    and compileCalls == stableCompile
    and fingerprintCalls == stableFingerprint
    and automationCatalogCalls == stableCatalog,
    "stable safety polls rebuilt static automation state")

-- A board change still enters the decision FSM, but must reuse the static
-- plan and must not rebuild the independent auto-lock trace.
local boardBefore = Nexus.RecomputeStats()
local boardCompile, boardFingerprint, boardCatalog =
    compileCalls, fingerprintCalls, automationCatalogCalls
H.DeliverBoard({{spellId=200100,quality=3}})
H.Advance(0.2)
local boardAfter = Nexus.RecomputeStats()
assert(boardAfter.fullSteps == boardBefore.fullSteps + 1
    and boardAfter.planCompiles == boardBefore.planCompiles
    and boardAfter.autoLockEvaluations == boardBefore.autoLockEvaluations
    and compileCalls == boardCompile
    and fingerprintCalls == boardFingerprint
    and automationCatalogCalls == boardCatalog,
    "board-only dirtiness recompiled or reevaluated auto-lock")

-- Strategy settings invalidate once. With automatic locking enabled but no
-- lock targets, the explicit step evaluates the lock gate once; later board
-- changes still do not repeat it.
NexusDB.settings.anchorSpellId = 200100
NexusDB.settings.autoLockEchoes = true
local settingsBefore = Nexus.RecomputeStats()
assert(Nexus.RequestRecompute())
H.Advance(0.2)
local settingsAfter = Nexus.RecomputeStats()
assert(settingsAfter.planCompiles == settingsBefore.planCompiles + 1
    and settingsAfter.autoLockEvaluations
        == settingsBefore.autoLockEvaluations + 1,
    "explicit settings invalidation did not rebuild exactly once")
local boardTwoCompile, boardTwoFingerprint, boardTwoCatalog =
    compileCalls, fingerprintCalls, automationCatalogCalls
local boardTwoAuto = settingsAfter.autoLockEvaluations
H.DeliverBoard({{spellId=200101,quality=3}})
H.Advance(0.2)
assert(compileCalls == boardTwoCompile
    and fingerprintCalls == boardTwoFingerprint
    and automationCatalogCalls == boardTwoCatalog
    and Nexus.RecomputeStats().autoLockEvaluations == boardTwoAuto,
    "board-only change repeated enabled auto-lock or fingerprint work")

-- Slot/data changes trigger one static probe; the 85-Echo fixture is not
-- walked again on subsequent stable polls.
local slotBefore = Nexus.RecomputeStats()
H.DeliverSlots({
    [1]={slot=1,name="Cache Fixture",verified=true,echoes=savedEchoes},
}, 1)
H.Advance(0.2)
local slotAfter = Nexus.RecomputeStats()
assert(slotAfter.fullSteps == slotBefore.fullSteps + 1
    and slotAfter.planCompiles <= slotBefore.planCompiles + 1,
    "slot invalidation repeated static plan compilation")
local slotCompile, slotFingerprint = compileCalls, fingerprintCalls
H.Advance(1)
assert(compileCalls == slotCompile and fingerprintCalls == slotFingerprint,
    "stable ticks repeated the large slot/wishlist fingerprint")

-- A represented catalog revision invalidates once. The slow fallback remains
-- a bounded identity check even during continuous board activity; it
-- must not recompile unchanged static state.
local catalogBefore = Nexus.RecomputeStats()
Nexus.Revisions.Advance(Nexus.Revisions.CATALOG_CHANGED, "cache fixture")
H.Advance(0.2)
local catalogAfter = Nexus.RecomputeStats()
assert(catalogAfter.planCompiles == catalogBefore.planCompiles + 1,
    "catalog revision did not invalidate static plan exactly once")
local fallbackFingerprint, fallbackCatalog =
    fingerprintCalls, automationCatalogCalls
for index=1,23 do
    H.DeliverBoard({{spellId=200100+(index%2),quality=3}})
    H.Advance(0.2)
end
assert(Nexus.RecomputeStats().planCompiles == catalogAfter.planCompiles
    and automationCatalogCalls == fallbackCatalog,
    "board activity caused an early fallback rebuild")
for index=24,26 do
    H.DeliverBoard({{spellId=200100+(index%2),quality=3}})
    H.Advance(0.2)
end
local fallbackAfter = Nexus.RecomputeStats()
assert(fallbackAfter.planCompiles == catalogAfter.planCompiles
    and fallbackAfter.fallbacks == catalogAfter.fallbacks
    and fallbackAfter.fallbackChecks >= catalogAfter.fallbackChecks + 1
    and automationCatalogCalls == fallbackCatalog
    and fingerprintCalls == fallbackFingerprint,
    string.format("five-second fallback rebuilt unchanged static automation state: compiles=%d/%d fallbacks=%d/%d checks=%d/%d catalog=%d/%d",
        fallbackAfter.planCompiles,catalogAfter.planCompiles,
        fallbackAfter.fallbacks,catalogAfter.fallbacks,
        fallbackAfter.fallbackChecks,catalogAfter.fallbackChecks,
        automationCatalogCalls,fallbackCatalog))
assert(#H.selectCalls == 0 and #H.banishCalls == 0
    and #H.freezeCalls == 0 and H.rerollCalls == 0
    and #H.activateCalls == 0 and #H.saveCalls == 0,
    "cache characterization submitted an unauthorized gameplay action")
print(string.format(
    "automation cache budget: wishlist=71 saved=85 polls=%d catalog=%d compiles=%d fingerprints=%d autoLock=%d actions=0 -- OK",
    fallbackAfter.polls, automationCatalogCalls,
    fallbackAfter.planCompiles,
    fallbackAfter.wishlistFingerprints,
    fallbackAfter.autoLockEvaluations))
