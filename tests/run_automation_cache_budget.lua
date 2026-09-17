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
dofile("core/WishlistModel.lua")
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

-- BN-PR71-REVIEW-002: current-request confirmation must reach cached consumers.
-- Services are synthetic. Notification installation, adapter reconciliation,
-- fallback comparison, projection cache and Policy are production functions.
-- Read-only upvalue inspection locates the existing cache functions; no private
-- state is injected and no production testing export is added.
do
    local function Setup(initial, level)
        Nexus, NexusDB = {}, {}
        local clock, granted, requests = 100, initial, 0
        GetTime = function() return clock end
        UnitLevel = function() return level end
        UnitName = function() return "Synthetic" end
        GetRealmName = function() return "Review" end
        UnitClass = function() return "Mage", "MAGE", 8 end
        local svc = {
            GetGrantedPerks=function() return granted end,
            RequestGrantedPerks=function() requests=requests+1 end,
            GetServerBuildSlots=function() return {} end,
            GetServerMaxSlots=function() return 5 end,
            GetServerActiveSlot=function() return 0 end,
            GetLockedPerks=function() return {} end,
            GetDiscoveredEchoes=function() return {} end,
            IsTomeEchoDisabled=function() return false end,
        }
        ProjectEbonhold = {PerkService=svc,EchoJournal={OnDataChanged=function() end}}
        hooksecurefunc = function(owner, key, callback)
            local original = owner[key]
            owner[key] = function(...)
                local value = original(...)
                callback(...)
                return value
            end
        end
        dofile("core/GameAdapter.lua")
        dofile("logic/Model.lua")
        dofile("logic/Policy.lua")
        local A = Nexus.GameAdapter
        local catalog = {rows={},familyOf={},levers={}}
        for id=1001,1030 do
            catalog.rows[id] = {spellId=id,name="Echo"..id,quality=3,maxStack=1}
            catalog.familyOf[id] = "family:"..id
        end
        A.Catalog = function() return catalog end
        local state, settings = {}, {}
        local store = {State=function() return state end,Settings=function() return settings end}
        A.Init({},store)
        A.OnEvent("PLAYER_ENTERING_WORLD")
        local signature = assert(A.AutomationSignature())
        A.ConsumeDirty()
        dofile("core/AutomationRuntime.lua")
        local noop = function() end
        local runtime = Nexus.MainInternals.AutomationRuntime.New({nexus=Nexus,
            model=Nexus.Model,policy=Nexus.Policy,ratchet={},strategy={},store=store,
            adapter=A,readout={},defaultProfile={},viewModel={},wishlistModel={},
            renderPanel=noop,renderIdlePanel=noop,buildProgress=noop,
            buildPanelProgress=noop,appendAudit=noop,appendAutoLockEvent=noop,
            print=noop,recordError=noop,now=GetTime})
        local functions, seen = {}, {}
        local function Inspect(fn)
            if type(fn)~="function" or seen[fn] then return end
            seen[fn] = true
            local index = 1
            while true do
                local name, value = debug.getupvalue(fn,index)
                if not name then break end
                if name=="ReadProjection" or name=="UpdateProjectionRevisions"
                    or name=="SameFallbackSignature" then functions[name]=value end
                if type(value)=="function" then Inspect(value) end
                index = index + 1
            end
        end
        for _, fn in pairs(runtime) do Inspect(fn) end
        assert(functions.ReadProjection and functions.UpdateProjectionRevisions
            and functions.SameFallbackSignature, "real consumer closures missing")
        local calls = 0
        local function Read()
            local r = {A.PresentationRevisions()}
            functions.UpdateProjectionRevisions(r[1],r[2],r[3],r[4],r[7],r[8],r[9],r[10])
            return functions.ReadProjection("owned",r[6],level,function()
                calls = calls + 1
                return A.Owned()
            end)
        end
        local function Reason(owned)
            return Nexus.Policy.Decide({board={cards={{spellId=1001,
                family=catalog.familyOf[1001],quality=3}}},owned=owned,
                plan={advisorOnly=true},level=level,catalog=catalog}).reason
        end
        return {adapter=A,read=Read,reason=Reason,signature=signature,
            same=functions.SameFallbackSignature,
            calls=function() return calls end,
            requests=function() return requests end,
            replace=function(value) granted=value end,
            advance=function(delta) clock=clock+delta end,
            level=function(value) level=value end,
            notify=function() ProjectEbonhold.EchoJournal.OnDataChanged() end}
    end

    for _, route in ipairs({"notification","fallback","getter-first"}) do
        local f = Setup({},20)
        local A = f.adapter
        local first = f.read()
        assert(not first.synced and f.calls()==1 and f.reason(first)=="unsynced")
        assert(not A.Owned().synced, "unchanged pre-request empty table became trusted")
        f.advance(6)
        assert(f.same(f.signature,assert(A.AutomationSignature())),
            "elapsed time alone changed ownership evidence")
        assert(f.read()==first and f.calls()==1)
        f.replace({})
        f.advance(1)
        if route=="getter-first" then
            assert(A.Owned().synced, "supported fresh empty reply was not confirmed")
        end
        if route~="fallback" then f.notify(); A.Poll() end
        local after = assert(A.AutomationSignature())
        assert(not f.same(f.signature,after),
            "fresh confirmation must change the actual automation fallback signature: "..route)
        local _, _, dirty = A.ConsumeDirty()
        if route~="fallback" then assert(dirty, "notified readiness transition was not dirty") end
        local ready = f.read()
        assert(ready.synced and ready.total==0 and f.calls()==2,
            "legitimate confirmation did not refresh the actual owned projection")
        assert(f.reason(ready)=="advisor", "Policy still waits for ownership after confirmation")
        local settledCalls = f.calls()
        for _=1,5 do
            f.advance(1); f.replace({}); f.notify(); A.Poll()
            assert(f.same(after,assert(A.AutomationSignature())),
                "equivalent fresh replies caused confirmation churn")
            local _, _, again = A.ConsumeDirty()
            assert(not again and f.read()==ready and f.calls()==settledCalls,
                "equivalent confirmed replies caused dirty/cache churn")
        end
        -- A run reset invalidates both confirmation and its cached projection.
        f.advance(1); A.RunBoundaryReset()
        local waiting = f.read()
        assert(not waiting.synced and f.reason(waiting)=="unsynced",
            "previous-generation confirmation survived the reset")
        local resetSig = assert(A.AutomationSignature())
        f.advance(20); f.notify(); A.Poll()
        assert(f.same(resetSig,assert(A.AutomationSignature())) and not f.read().synced,
            "old unchanged response was accepted in a new generation")
        f.advance(1); f.replace({}); f.notify(); A.Poll()
        assert(f.read().synced, "fresh new-generation empty reply did not recover")
        print("PR71 owned confirmation route="..route.." -- OK")
    end

    -- Late legitimate responses remain useful after the existing finite retries.
    do
        local f = Setup({},20)
        assert(not f.read().synced)
        for _=1,8 do f.advance(6); f.adapter.Poll(); assert(not f.read().synced) end
        assert(f.requests()==5, "ownership acquisition must retain its five-attempt bound")
        f.advance(1); f.replace({}); f.notify(); f.adapter.Poll()
        assert(f.read().synced and f.requests()==5,
            "late confirmed-empty response needs another request or reload")
        print("PR71 response after bounded retry exhaustion -- OK")
    end

    -- Content can be unchanged while the current-run response identity changes.
    do
        local old = {group={{spellId=1001}}}
        local f = Setup(old,20)
        f.adapter.RunBoundaryReset()
        assert(not f.read().synced, "unchanged previous-run contents became trusted")
        local before = assert(f.adapter.AutomationSignature())
        f.advance(1); f.replace({group={{spellId=1001}}}); f.notify(); f.adapter.Poll()
        local ready = f.read()
        assert(ready.synced and ready.bySpell[1001]==1
            and not f.same(before,assert(f.adapter.AutomationSignature())),
            "fresh equal nonempty response did not invalidate the untrusted cache")
        print("PR71 same-content new-generation response -- OK")
    end

    -- Malformed snapshots remain unpublished; level-one ghost protection stays.
    do
        local f = Setup({},20)
        assert(not f.read().synced)
        f.advance(1); f.replace({group="malformed"}); f.notify(); f.adapter.Poll()
        assert(f.adapter.AutomationSignature()==nil and not f.read().synced,
            "malformed reply published a trusted projection")
        f.advance(1); f.replace({}); f.notify(); f.adapter.Poll()
        assert(f.read().synced, "valid response failed after a malformed snapshot")
        local ghost = {group={}}
        for id=1001,1025 do ghost.group[#ghost.group+1]={spellId=id} end
        f = Setup({},1)
        assert(not f.read().synced)
        f.advance(1); f.replace(ghost); f.notify(); f.adapter.Poll()
        local refused = f.read()
        assert(not refused.synced and refused.ghostSuspect,
            "response fingerprint bypassed the level-one ghost guard")
        print("PR71 malformed-response and ghost controls -- OK")
    end
    print("PR71 ownership notification/fallback/cache/Policy regressions: 6 groups -- OK")
end
