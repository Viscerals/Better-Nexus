-- Stage 25.2 revision-aware gate: rapid semantic board rolling must not
-- repeatedly reacquire unchanged dynamic projections from ProjectEbonhold.
-- All identities and payloads are generated; diagnostics retain aggregates.
local H = dofile("tests/harness.lua")

local CATALOG_ROWS = 220
local WISHLIST_ROWS = 79
local SLOT_ROWS = 85
local BOARDS = 200
local DUPLICATE_SHOWS = 20

for index = 1, CATALOG_ROWS do
    H.AddEcho(210000 + index, "Generated Echo " .. index, {
        quality=index % 4,
        requiredSpell=310000 + index,
    })
end

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

local wishlistEchoes = {}
local grantedEntries = {}
for index = 1, WISHLIST_ROWS do
    wishlistEchoes[index] = {
        spellId=210000 + index,quality=index % 4,stacks=1,
    }
    grantedEntries[index] = {
        spellId=210000 + index,quality=index % 4,
    }
end

local slots = {}
for slot = 1, 5 do
    local echoes = {}
    for index = 1, SLOT_ROWS do
        echoes[index] = {
            spellId=210000 + ((index - 1) % CATALOG_ROWS) + 1,
            quality=index % 4,stacks=1,locked=false,
        }
    end
    slots[slot] = {
        slot=slot,name="Generated Slot " .. slot,verified=true,echoes=echoes,
    }
end

NexusDB = {
    settings={
        autoPick=false,autoLockEchoes=false,autoDisable=false,
        autoBanish=false,
    },
    chars={},communityBuilds={},buildFilters={},dpsCapture={},
}
H.playerLevel = 5
H.wishlist = {
    name="Generated Wishlist",class="MAGE",echoes=wishlistEchoes,
}
H.granted = {generated=grantedEntries}
H.locked = {
    {spellId=210001,quality=1,stack=1},
    {spellId=210002,quality=2,stack=1},
    {spellId=210003,quality=3,stack=1},
    {spellId=210004,quality=4,stack=1},
    {spellId=210005,quality=0,stack=1},
    {spellId=210006,quality=1,stack=1},
}
H.discovered = {}
for index = 1, CATALOG_ROWS do H.discovered[210000 + index] = true end
H.DeliverSlots(slots, 1)

dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua")
dofile("core/SyncTransport.lua")
dofile("core/SyncCompatibility.lua")
dofile("core/SyncReconciler.lua")
dofile("core/SyncInbound.lua")
dofile("core/SyncDiagnostics.lua")
dofile("core/SyncSession.lua")
dofile("core/Sync.lua")
dofile("core/AutomationRuntime.lua")
local runtime
local runtimeFactory = assert(Nexus.MainInternals.AutomationRuntime.New)
Nexus.MainInternals.AutomationRuntime.New = function(options)
    runtime = runtimeFactory(options)
    return runtime
end
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")

H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(1, 0.2)

local function Number(value) return tonumber(value) or 0 end
local function Delta(after, before, key)
    return Number(after[key]) - Number(before[key])
end
local function ProjectionDelta(after, before, name, field)
    local a = (((after.echoReconcile or {}).projections or {})[name] or {})[field]
    local b = (((before.echoReconcile or {}).projections or {})[name] or {})[field]
    return Number(a) - Number(b)
end
local function PhaseCountDelta(after, before, name)
    return Number((after.phaseCounts or {})[name])
        - Number((before.phaseCounts or {})[name])
end
local function MemoryKB()
    local ok, value = pcall(collectgarbage, "count")
    return ok and Number(value) or 0
end

local capturedSlotCalls, capturedWishlistCalls = 0, 0
local captureSurfaceCalls = false
local originalSurfaceSlots = Nexus.GameAdapter.Slots
local originalSurfaceWishlist = Nexus.GameAdapter.Wishlist
Nexus.GameAdapter.Slots = function(...)
    if captureSurfaceCalls then capturedSlotCalls = capturedSlotCalls + 1 end
    return originalSurfaceSlots(...)
end
Nexus.GameAdapter.Wishlist = function(...)
    if captureSurfaceCalls then
        capturedWishlistCalls = capturedWishlistCalls + 1
    end
    return originalSurfaceWishlist(...)
end

local baseline = Nexus.RecomputeStats()
local memoryBefore = MemoryKB()
captureSurfaceCalls = true
for index = 1, BOARDS do
    H.DeliverBoard({
        {spellId=210000 + index,quality=index % 4},
        {spellId=210201,quality=1},
        {spellId=210202,quality=2},
    })
    H.Advance(0.2, 0.2)
end
captureSurfaceCalls = false
local rolled = Nexus.RecomputeStats()
local memoryAfter = MemoryKB()

local fullSteps = Delta(rolled, baseline, "fullSteps")
local staticProbes = Delta(rolled, baseline, "staticProbes")
local planCompiles = Delta(rolled, baseline, "planCompiles")
local decisions = PhaseCountDelta(rolled, baseline, "policy")
local automationSlotCalls = PhaseCountDelta(rolled, baseline, "slots")
local automationOwnedCalls = PhaseCountDelta(rolled, baseline, "owned")
local automationLeverCalls = PhaseCountDelta(rolled, baseline, "levers")
local slotCalls = ProjectionDelta(rolled, baseline, "slots", "calls")
local slotEchoes = ProjectionDelta(rolled, baseline, "slots", "echoes")
local ownedCalls = ProjectionDelta(rolled, baseline, "owned", "calls")
local ownedEntries = ProjectionDelta(rolled, baseline, "owned", "entries")
local lockedCalls = ProjectionDelta(rolled, baseline, "locked", "calls")
local leverCalls = ProjectionDelta(rolled, baseline, "levers", "calls")
local leverChecks = ProjectionDelta(rolled, baseline, "levers", "memberChecks")
local boardCalls = ProjectionDelta(rolled, baseline, "board", "calls")
local boardCards = ProjectionDelta(rolled, baseline, "board", "cards")

assert(fullSteps == BOARDS and decisions == BOARDS
    and boardCalls == BOARDS and boardCards == BOARDS * 3,
    string.format("semantic board fixture drifted: boards=%d full=%d policy=%d boardCalls=%d cards=%d",
        BOARDS,fullSteps,decisions,boardCalls,boardCards))
assert(staticProbes == 0 and planCompiles == 0
    and PhaseCountDelta(rolled, baseline, "catalog") == 0
    and PhaseCountDelta(rolled, baseline, "wishlist") == 0
    and PhaseCountDelta(rolled, baseline, "wishlistFingerprint") == 0
    and PhaseCountDelta(rolled, baseline, "plan") == 0,
    "board-only rolling rebuilt static catalog/wishlist/plan work")
assert(Delta(rolled, baseline, "fallbackRepairs") == 0,
    "matching five-second fallback repaired during semantic board rolling")
assert(#H.selectCalls == 0 and #H.banishCalls == 0
    and #H.freezeCalls == 0 and H.rerollCalls == 0,
    "manual-mode characterization attempted a gameplay action")

-- PerkUI.Show can repeat the same semantic board during event/chat churn.
-- Distinguish those notifications from the 200 real board generations above:
-- the duplicate burst must not be mistaken for 20 new decisions/renders.
local duplicateBefore = Nexus.RecomputeStats()
for _ = 1, DUPLICATE_SHOWS do
    H.DeliverBoard({
        {spellId=210200,quality=0},
        {spellId=210201,quality=1},
        {spellId=210202,quality=2},
    })
    H.Advance(0.2, 0.2)
end
local duplicateAfter = Nexus.RecomputeStats()
local duplicateFullSteps = Delta(duplicateAfter, duplicateBefore, "fullSteps")
local duplicateDecisions = PhaseCountDelta(
    duplicateAfter, duplicateBefore, "policy")
local duplicateRenders = PhaseCountDelta(
    duplicateAfter, duplicateBefore, "overlayRender")
local duplicateSlotCalls = ProjectionDelta(
    duplicateAfter, duplicateBefore, "slots", "calls")
local duplicateBoardCalls = ProjectionDelta(
    duplicateAfter, duplicateBefore, "board", "calls")
assert(duplicateFullSteps == 0
    and duplicateDecisions == 0
    and duplicateRenders == 0
    and duplicateBoardCalls == 0,
    string.format("identical-board delivery was not coalesced: shows=%d full=%d policy=%d renders=%d boardCalls=%d",
        DUPLICATE_SHOWS,duplicateFullSteps,duplicateDecisions,
        duplicateRenders,duplicateBoardCalls))

-- Adversarial semantic-boundary probes: quality is policy input, rapid
-- distinct Shows settle to the final board once, and a malformed read fails
-- open into the existing waiting-for-board step instead of being deduplicated.
local qualityBefore = Nexus.RecomputeStats()
H.DeliverBoard({
    {spellId=210200,quality=3},
    {spellId=210201,quality=1},
    {spellId=210202,quality=2},
})
H.Advance(0.2, 0.2)
local qualityAfter = Nexus.RecomputeStats()
assert(Delta(qualityAfter, qualityBefore, "fullSteps") == 1
    and PhaseCountDelta(qualityAfter, qualityBefore, "policy") == 1,
    "quality-only semantic board change was incorrectly coalesced")

local burstBefore = Nexus.RecomputeStats()
for index = 1, 20 do
    H.DeliverBoard({
        {spellId=210100 + index,quality=index % 4},
        {spellId=210201,quality=1},
        {spellId=210202,quality=2},
    })
end
H.Advance(0.2, 0.2)
local burstAfter = Nexus.RecomputeStats()
assert(Delta(burstAfter, burstBefore, "fullSteps") == 1
    and PhaseCountDelta(burstAfter, burstBefore, "policy") == 1,
    "rapid distinct board burst did not settle to one final-board decision")

local malformedBefore = Nexus.RecomputeStats()
H.Perks.currentChoice = {{quality=1}}
ProjectEbonhold.PerkUI.Show(H.Perks.currentChoice)
H.Advance(0.2, 0.2)
local malformedAfter = Nexus.RecomputeStats()
assert(Delta(malformedAfter, malformedBefore, "fullSteps") == 1
    and ProjectionDelta(malformedAfter, malformedBefore, "board", "calls") == 1
    and PhaseCountDelta(malformedAfter, malformedBefore, "policy") == 0,
    "malformed board notification did not fail open through Board validation")
H.DeliverBoard({
    {spellId=210120,quality=0},
    {spellId=210201,quality=1},
    {spellId=210202,quality=2},
})
H.Advance(0.2, 0.2)

-- Equivalent notifications coalesce into one semantic scan and no full step.
local equivalentBefore = Nexus.RecomputeStats()
for _ = 1, 20 do H.NotifyEchoDataChanged() end
H.Advance(0.2, 0.2)
local equivalentAfter = Nexus.RecomputeStats()
assert(Delta(equivalentAfter, equivalentBefore, "fullSteps") == 0
    and Delta(equivalentAfter, equivalentBefore, "fallbackRepairs") == 0,
    "equivalent Echo notification burst scheduled automation work")

-- Accepted, rejected, unrecognized, and unrelated traffic remain correlation
-- context only. They may advance Sync state but cannot schedule automation.
local trafficBefore = Nexus.RecomputeStats()
local accepted, rejected = 0, 0
for _ = 1, 20 do
    if Nexus.Sync.HandleIncoming("WLNP|PeerA|1.20.0-beta.1", "PeerA") then
        accepted = accepted + 1
    end
    if not Nexus.Sync.HandleIncoming("WLXX|generated", "PeerA") then
        rejected = rejected + 1
    end
    H.FireEvent("CHAT_MSG_CHANNEL", "generated unrelated", "PeerB",
        "Common", "UnrelatedChannel")
    H.Advance(0.2, 0.2)
end
local trafficAfter = Nexus.RecomputeStats()
assert(accepted == 20 and rejected == 20
    and Delta(trafficAfter, trafficBefore, "fullSteps") == 0
    and Delta(trafficAfter, trafficBefore, "fallbackRepairs") == 0,
    "accepted/rejected/unrecognized traffic escaped into automation")

-- Each represented dependency is distinguishable and settles once. These
-- checks characterize invalidation; they do not prescribe checkpoint 25.2's
-- repair structure.
local revisionMatrix = {}
local function ObserveRevision(name, mutate)
    local before = Nexus.RecomputeStats()
    mutate()
    H.Advance(0.2, 0.2)
    local after = Nexus.RecomputeStats()
    revisionMatrix[name] = {
        full=Delta(after, before, "fullSteps"),
        probes=Delta(after, before, "staticProbes"),
        compiles=Delta(after, before, "planCompiles"),
        slots=ProjectionDelta(after, before, "slots", "calls"),
        owned=ProjectionDelta(after, before, "owned", "calls"),
        locked=ProjectionDelta(after, before, "locked", "calls"),
        levers=ProjectionDelta(after, before, "levers", "calls"),
        slotPhases=PhaseCountDelta(after, before, "slots"),
        ownedPhases=PhaseCountDelta(after, before, "owned"),
        leverPhases=PhaseCountDelta(after, before, "levers"),
    }
    assert(revisionMatrix[name].full == 1,
        name .. " revision did not settle in one full step")
end

ObserveRevision("slots", function()
    local changed = H.CloneValue(slots)
    changed[1].echoes[1].spellId = 210210
    slots = changed
    H.DeliverSlots(slots, 1)
end)
ObserveRevision("owned", function()
    H.granted.generated[#H.granted.generated + 1] = {
        spellId=210210,quality=0,
    }
    H.NotifyEchoDataChanged()
end)
ObserveRevision("locked", function()
    H.locked[#H.locked + 1] = {
        spellId=210210,quality=0,stack=1,
    }
    H.NotifyEchoDataChanged()
end)
ObserveRevision("lever", function()
    H.DeliverDiscovery({210001})
end)
ObserveRevision("catalog", function()
    H.AddEcho(210500, "Generated Catalog Revision", {
        quality=1,requiredSpell=310500,
    })
    Nexus.Revisions.Advance(Nexus.Revisions.CATALOG_CHANGED,
        "generated Stage 25 catalog revision")
end)
ObserveRevision("settings", function()
    NexusDB.settings.anchorSpellId = 210001
    assert(Nexus.RequestRecompute())
end)
ObserveRevision("wishlist", function()
    local changed = H.CloneValue(wishlistEchoes)
    changed[1].spellId = 210210
    assert(Nexus.GameAdapter.SetLoadoutWishlistIdentity(
        1, "Generated Wishlist Revision", changed))
end)

assert(revisionMatrix.slots.slotPhases == 1
    and revisionMatrix.slots.ownedPhases == 0
    and revisionMatrix.slots.locked == 0
    and revisionMatrix.slots.leverPhases == 0,
    string.format("slot revision invalidated dynamic projections: slotPhases=%d calls=%d owned=%d locked=%d levers=%d",
        revisionMatrix.slots.slotPhases,revisionMatrix.slots.slots,revisionMatrix.slots.owned,
        revisionMatrix.slots.locked,revisionMatrix.slots.levers))
assert(revisionMatrix.owned.ownedPhases == 1
    and revisionMatrix.owned.slotPhases == 0
    and revisionMatrix.owned.locked == 0
    and revisionMatrix.owned.leverPhases == 0,
    string.format("owned revision invalidated dynamic projections: ownedPhases=%d slots=%d owned=%d locked=%d levers=%d",
        revisionMatrix.owned.ownedPhases,revisionMatrix.owned.slots,revisionMatrix.owned.owned,
        revisionMatrix.owned.locked,revisionMatrix.owned.levers))
assert(revisionMatrix.locked.locked == 1
    and revisionMatrix.locked.slotPhases == 0
    and revisionMatrix.locked.ownedPhases == 0
    and revisionMatrix.locked.leverPhases == 0,
    string.format("locked revision invalidated dynamic projections: slots=%d owned=%d locked=%d levers=%d",
        revisionMatrix.locked.slots,revisionMatrix.locked.owned,
        revisionMatrix.locked.locked,revisionMatrix.locked.levers))
assert(revisionMatrix.lever.leverPhases == 1
    and revisionMatrix.lever.slotPhases == 0
    and revisionMatrix.lever.ownedPhases == 0
    and revisionMatrix.lever.locked == 0,
    string.format("lever revision invalidated dynamic projections: leverPhases=%d slots=%d owned=%d locked=%d levers=%d",
        revisionMatrix.lever.leverPhases,revisionMatrix.lever.slots,revisionMatrix.lever.owned,
        revisionMatrix.lever.locked,revisionMatrix.lever.levers))
for _, name in ipairs({"owned", "locked", "lever"}) do
    assert(revisionMatrix[name].probes == 0,
        name .. " revision unnecessarily rebuilt static context")
end
for _, name in ipairs({"catalog", "settings", "wishlist"}) do
    assert(revisionMatrix[name].probes == 1,
        name .. " revision did not rebuild static context exactly once")
end
for _, name in ipairs({"settings", "wishlist"}) do
    local row = revisionMatrix[name]
    assert(row.slotPhases == 0 and row.ownedPhases == 0
        and row.locked == 0 and row.leverPhases == 0,
        name .. " revision invalidated dynamic projections")
end

-- Required intent deadline versus confirmation transition. The follow-up is
-- deliberately measured separately from duplicate dirty/event work.
H.optSettings.autoAcceptLoadoutEchoes = false
NexusDB.settings.autoPick = true
assert(runtime and runtime.ToggleAuto() == true)
assert(Nexus.RequestRecompute())
H.Perks.currentChoice = nil
H.Advance(0.2, 0.2)
local actionsBefore = #H.selectCalls
local deadlineBefore = Nexus.RecomputeStats()
H.DeliverBoard({{spellId=210001,quality=1}})
H.Advance(0.2, 0.2)
assert(#H.selectCalls == actionsBefore,
    "intent beat acted before its deadline")
H.Advance(0.4, 0.2)
local deadlineAfter = Nexus.RecomputeStats()
assert(#H.selectCalls == actionsBefore + 1
    and Delta(deadlineAfter, deadlineBefore, "deadlines") >= 1
    and deadlineAfter.lastStepContext.actionAttempted == true,
    string.format("required intent deadline drifted: selects=%d/%d deadlines=%d attempted=%s type=%s trigger=%s",
        #H.selectCalls,actionsBefore,
        Delta(deadlineAfter,deadlineBefore,"deadlines"),
        tostring(deadlineAfter.lastStepContext.actionAttempted),
        tostring(deadlineAfter.lastStepContext.actionType),
        tostring(deadlineAfter.lastStepContext.trigger)))
H.ResolveSelect(true)
NexusDB.settings.autoPick = false
H.DeliverBoard({{spellId=210002,quality=2}})
H.Advance(0.2, 0.2)

-- A missed semantic update is repaired once by the five-second fallback and
-- reports its bounded component rather than treating every fallback as static.
local fallbackBefore = Nexus.RecomputeStats()
H.granted.generated[#H.granted.generated + 1] = {
    spellId=210211,quality=1,
}
H.Advance(5.2, 0.2)
local fallbackAfter = Nexus.RecomputeStats()
assert(Delta(fallbackAfter, fallbackBefore, "fallbackRepairs") == 1
    and Delta(fallbackAfter, fallbackBefore, "fullSteps") == 1
    and Delta(fallbackAfter, fallbackBefore, "staticProbes") == 0
    and PhaseCountDelta(fallbackAfter, fallbackBefore, "owned") == 1
    and fallbackAfter.lastStepContext.fallbackComponent == "granted",
    string.format("targeted fallback characterization drifted: repairs=%d full=%d probes=%d owned=%d component=%s",
        Delta(fallbackAfter,fallbackBefore,"fallbackRepairs"),
        Delta(fallbackAfter,fallbackBefore,"fullSteps"),
        Delta(fallbackAfter,fallbackBefore,"staticProbes"),
        PhaseCountDelta(fallbackAfter,fallbackBefore,"owned"),
        tostring(fallbackAfter.lastStepContext.fallbackComponent)))

-- Diagnostic snapshots are defensive and fixed-shape. They contain no board
-- signatures, spell IDs, payloads, names, or per-board history.
local defensive = Nexus.RecomputeStats()
defensive.phaseCounts.slots = -1
defensive.lastStepContext.trigger = "mutated"
defensive.echoReconcile.projections.slots.calls = -1
local fresh = Nexus.RecomputeStats()
local phaseKeys, contextKeys, projectionKeys = 0, 0, 0
for _ in pairs(fresh.phaseCounts or {}) do phaseKeys = phaseKeys + 1 end
for _ in pairs(fresh.lastStepContext or {}) do contextKeys = contextKeys + 1 end
for _ in pairs((fresh.echoReconcile or {}).projections or {}) do
    projectionKeys = projectionKeys + 1
end
assert(fresh.phaseCounts.slots >= 0
    and fresh.lastStepContext.trigger ~= "mutated"
    and fresh.echoReconcile.projections.slots.calls >= 0
    and phaseKeys == 15 and contextKeys == 16 and projectionKeys == 6,
    "bounded diagnostic snapshot leaked mutable or variable-shape state")

print(string.format(
    "stage25 revision-aware: boards=%d full=%d decisions=%d staticProbes=%d compiles=%d automation[slots=%d owned=%d locked=%d levers=%d] allSurfaceSlots[calls=%d echoes=%d] owned[calls=%d entries=%d] levers[calls=%d checks=%d] board[calls=%d cards=%d] duplicates[shows=%d full=%d policy=%d renders=%d slots=%d] equivalent=20 accepted=%d rejected=%d memoryDeltaKB=%.1f retained[phases=%d context=%d projections=%d]",
    BOARDS,fullSteps,decisions,staticProbes,planCompiles,
    automationSlotCalls,automationOwnedCalls,lockedCalls,automationLeverCalls,
    slotCalls,slotEchoes,ownedCalls,ownedEntries,
    leverCalls,leverChecks,boardCalls,boardCards,DUPLICATE_SHOWS,
    duplicateFullSteps,duplicateDecisions,duplicateRenders,
    duplicateSlotCalls,accepted,rejected,
    memoryAfter-memoryBefore,phaseKeys,contextKeys,projectionKeys))

-- Semantic board changes need fresh Board and Policy work, but unchanged
-- generation-backed automation projections stay reusable. A known-nil static
-- Wishlist is a cached answer too: rendering and run-start audit metadata must
-- not fall through to Wishlist/Slots traversal for every board.
assert(automationSlotCalls <= 1 and automationOwnedCalls <= 1
    and lockedCalls <= 1 and automationLeverCalls <= 1
    and capturedSlotCalls == 0 and capturedWishlistCalls == 0
    and slotCalls == 0 and slotEchoes == 0
    and duplicateFullSteps == 0 and duplicateDecisions == 0
    and duplicateRenders == 0 and duplicateSlotCalls == 0,
    string.format("revision-aware projection bounds failed: boards=%d automation=%d/%d/%d/%d allSurfaceSlots=%d/%d duplicates=%d/%d/%d/%d",
        BOARDS,automationSlotCalls,automationOwnedCalls,lockedCalls,
        automationLeverCalls,slotCalls,slotEchoes,duplicateFullSteps,
        duplicateDecisions,duplicateRenders,duplicateSlotCalls))

print("revision-aware dynamic projections and duplicate-board coalescing -- OK")
