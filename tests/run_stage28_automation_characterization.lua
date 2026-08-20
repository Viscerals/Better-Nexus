-- Stage 28.1/28.2 regression: client-scale Community preview work must not be
-- repeated by board rolls, ordinary level changes, fallback checks, or an
-- Auto-off transition. Counters are deterministic; elapsed time is not proof.
local F = dofile("tests/automation_live_fixture.lua")
local H = F.H
local runtime = assert(F.runtime, "automation runtime fixture did not initialize")

local BUILD_ROWS = 1159
local DPS_ROWS = 595
local ROLLS = 74
local selectedId = "stage28-selected"
local selectedRevision = 1
local selectedVisible = true

local function Echoes(count, seed)
    local out = {}
    local ids = {200100, 200102, 200104}
    for index = 1, count do
        out[index] = {
            spellId=ids[((index + (seed or 0)) - 1) % #ids + 1],
            quality=((index + (seed or 0)) % 4),
            stacks=1,
        }
    end
    return out
end

local builds = {}
for index = 1, BUILD_ROWS - 1 do
    local id = string.format("stage28-%04d", index)
    builds[id] = {
        id=id,title="Stage 28 Library " .. index,description="fixture",
        author="Fixture",ownerKey="fixture" .. index .. "@testrealm",
        class="MAGE",echoes=Echoes(6, index),postedAt=index,
        lastModified=index,
    }
end
local selectedEchoes = Echoes(79, 0)
builds[selectedId] = {
    id=selectedId,title="Stage 28 Selected",description="selected fixture",
    author="Fixture",ownerKey="selected@testrealm",class="MAGE",
    echoes=selectedEchoes,postedAt=BUILD_ROWS,
    lastModified=BUILD_ROWS,
}

NexusDB.communityBuilds = builds
NexusDB.dpsCapture = {
    characterBest={dummy={},lk={}},personalBest={},buildBest={},
}
for index = 1, DPS_ROWS do
    local category = (index % 2 == 0) and "dummy" or "lk"
    NexusDB.dpsCapture.characterBest[category]["fixture" .. index] = {
        fingerprint="stage28-dps-" .. index,dps=100000 + index,
        player="Fixture" .. index,buildId="stage28-dps-build-" .. index,
        class="MAGE",level=80,ts=index,duration=60,
    }
end

dofile("core/DpsCapture.lua")
builds[selectedId].fingerprint = Nexus.DpsCapture.GetEchoKey(selectedEchoes)
builds["stage28-0001"].echoes = Echoes(79, 0)
builds["stage28-0001"].fingerprint = builds[selectedId].fingerprint
builds["stage28-0001"].autoDps = true
builds["stage28-0002"].echoes = Echoes(79, 0)
builds["stage28-0002"].fingerprint = builds[selectedId].fingerprint
-- The live catalog binds once during startup. Rebind through a temporary
-- database so this post-bootstrap client-scale fixture rebuilds every index
-- through the same Init boundary instead of mutating an indexed table behind
-- the module's back.
Nexus.BuildCatalog.Init({}, Nexus.BundledBuilds)
Nexus.BuildCatalog.Init(NexusDB, Nexus.BundledBuilds)

local counts = {
    catalogAll=0,catalogAllRows=0,selectedGets=0,selectedEchoCopies=0,
    selectionKeyReads=0,previewCompiles=0,matchingLookups=0,
    dpsEligibilityScans=0,
}

local realCatalogAll = assert(Nexus.BuildCatalog.All)
Nexus.BuildCatalog.All = function(...)
    counts.catalogAll = counts.catalogAll + 1
    local rows = realCatalogAll(...)
    for _ in pairs(rows or {}) do
        counts.catalogAllRows = counts.catalogAllRows + 1
    end
    return rows
end

Nexus.CommunityBuilds = {
    -- The scalar key is the cheap warm-path contract. The represented build is
    -- materialized only after this identity/revision changes.
    GetSelectedBuildForPanelKey=function()
        counts.selectionKeyReads = counts.selectionKeyReads + 1
        if not selectedVisible then return nil, 0, selectedRevision end
        return selectedId, 0, selectedRevision
    end,
    GetSelectedBuildForPanel=function()
        counts.selectedGets = counts.selectedGets + 1
        if not selectedVisible then return nil end
        local build = Nexus.BuildCatalog.Get(selectedId)
        counts.selectedEchoCopies = counts.selectedEchoCopies
            + #(build and build.echoes or {})
        return build
    end,
}

local realCompile = assert(Nexus.Strategy.Compile)
Nexus.Strategy.Compile = function(catalog, wishlist, ...)
    if type(wishlist) == "table"
        and wishlist.name == "Stage 28 Selected" then
        counts.previewCompiles = counts.previewCompiles + 1
    end
    return realCompile(catalog, wishlist, ...)
end

local lastMatchedBuild
local realMatch = assert(Nexus.DpsCapture.FindMatchingBuildPublic)
Nexus.DpsCapture.FindMatchingBuildPublic = function(...)
    counts.matchingLookups = counts.matchingLookups + 1
    lastMatchedBuild = realMatch(...)
    return lastMatchedBuild
end
local realEligibility = assert(Nexus.DpsCapture.GetCommunityEligibility)
Nexus.DpsCapture.GetCommunityEligibility = function(...)
    counts.dpsEligibilityScans = counts.dpsEligibilityScans + 1
    return realEligibility(...)
end

local function Snapshot()
    local runtimeStats = Nexus.RecomputeStats()
    local fixture = F.Snapshot()
    return {
        fullSteps=runtimeStats.fullSteps or 0,
        pollFailures=runtimeStats.pollFailures or 0,
        staticProbes=runtimeStats.staticProbes or 0,
        planCompiles=runtimeStats.planCompiles or 0,
        fallbackChecks=runtimeStats.fallbackChecks or 0,
        fallbackRepairs=runtimeStats.fallbackRepairs or 0,
        overlayPrepare=(runtimeStats.phaseCounts or {}).overlayPrepare or 0,
        slotPhases=(runtimeStats.phaseCounts or {}).slots or 0,
        ownedPhases=(runtimeStats.phaseCounts or {}).owned or 0,
        lockedPhases=(runtimeStats.phaseCounts or {}).locked or 0,
        leverPhases=(runtimeStats.phaseCounts or {}).levers or 0,
        panelProgress=F.counts.progress or 0,
        panelRenders=F.counts.panelRenders or 0,
        slotReads=F.counts.slots or 0,
        ownedReads=F.counts.owned or 0,
        lockedReads=F.counts.locked or 0,
        leverReads=F.counts.disabled or 0,
        actions=fixture.actions or 0,
        catalogAll=counts.catalogAll,
        catalogAllRows=counts.catalogAllRows,
        selectedGets=counts.selectedGets,
        selectedEchoCopies=counts.selectedEchoCopies,
        selectionKeyReads=counts.selectionKeyReads,
        previewCompiles=counts.previewCompiles,
        matchingLookups=counts.matchingLookups,
        dpsEligibilityScans=counts.dpsEligibilityScans,
    }
end

local function Delta(after, before)
    local out = {}
    for key, value in pairs(after) do
        out[key] = value - (before[key] or 0)
    end
    return out
end

local findings = {}
local function Check(ok, text)
    if not ok then findings[#findings + 1] = text end
end
local function CheckZero(row, names, label)
    local bad = {}
    for _, name in ipairs(names) do
        if (row[name] or 0) ~= 0 then
            bad[#bad + 1] = name .. "=" .. tostring(row[name])
        end
    end
    Check(#bad == 0, label .. " repeated " .. table.concat(bad, ","))
end

-- Establish one selected-preview result before measuring warm behavior.
H.playerLevel = 40
H.FireEvent("PLAYER_LEVEL_UP", 40)
H.DeliverBoard({{spellId=200102,quality=0}})
assert(Nexus.RequestRecompute())
H.Advance(0.2, 0.2)
H.Advance(0.2, 0.2)
assert(Nexus.RequestRecompute())
H.Advance(0.2, 0.2) -- settle the one run-boundary owned revision
local warm = Snapshot()
assert(warm.selectedGets >= 1 and warm.previewCompiles >= 1
    and warm.catalogAll == 0 and warm.catalogAllRows == 0,
    "selected Community preview warm-up retained the full-catalog path")
assert(lastMatchedBuild == "stage28-0002",
    "exact-match duplicate handling did not prefer the deterministic explicit build")
assert(warm.actions == 0 and runtime.AutoEnabled() == false,
    "characterization warm-up submitted an action or enabled Auto")

-- Seventy-four semantic board rolls need fresh board/policy/render work, but
-- no repeated selected-build copy, preview compilation, catalog walk, DPS
-- scan, panel-progress rebuild, or dynamic projection traversal.
local rollsBefore = Snapshot()
for roll = 1, ROLLS do
    H.DeliverBoard({{
        spellId=({200100,200102,200104})[(roll - 1) % 3 + 1],
        quality=roll % 4,
    }})
    H.Advance(0.2, 0.2)
end
local rolls = Delta(Snapshot(), rollsBefore)
Check(rolls.fullSteps == ROLLS,
    string.format("Echo-roll fixture ran %d/%d full decisions", rolls.fullSteps, ROLLS))
CheckZero(rolls, {
    "catalogAll","catalogAllRows","selectedGets","selectedEchoCopies",
    "previewCompiles","matchingLookups","dpsEligibilityScans",
    "panelProgress","slotPhases","ownedPhases","lockedPhases",
    "leverPhases","slotReads","ownedReads","lockedReads","leverReads",
}, "Echo rolls 1-74")
Check(rolls.selectionKeyReads == ROLLS,
    string.format("Echo rolls did not use the cheap selected key: reads=%d/%d",
        rolls.selectionKeyReads, ROLLS))
Check(rolls.actions == 0, "Echo rolls submitted gameplay actions=" .. rolls.actions)

-- Enabling Auto may schedule one coalesced decision. Disabling it before the
-- intent deadline must revoke authorization immediately without another heavy
-- Step, and the old deadline must not later submit or rebuild anything.
local onBefore = Snapshot()
assert(runtime.ToggleAuto() == true, "Auto did not enable")
H.Advance(0.2, 0.2)
local on = Delta(Snapshot(), onBefore)
Check(on.fullSteps <= 1, "Auto-on ran fullSteps=" .. on.fullSteps)
CheckZero(on, {
    "catalogAll","catalogAllRows","selectedGets","selectedEchoCopies",
    "previewCompiles","matchingLookups","dpsEligibilityScans",
    "panelProgress","slotPhases","ownedPhases","lockedPhases",
    "leverPhases","slotReads","ownedReads","lockedReads","leverReads",
    "actions",
}, "Auto-on bounded evaluation")
Check(on.selectionKeyReads <= 1,
    "Auto-on repeated selected-key reads=" .. on.selectionKeyReads)

local offBefore = Snapshot()
assert(runtime.ToggleAuto() == false, "Auto did not disable")
H.Advance(0.8, 0.2)
local off = Delta(Snapshot(), offBefore)
CheckZero(off, {
    "fullSteps","catalogAll","catalogAllRows","selectedGets",
    "selectedEchoCopies","previewCompiles","matchingLookups",
    "dpsEligibilityScans","panelProgress","slotPhases","ownedPhases",
    "lockedPhases","leverPhases","slotReads","ownedReads",
    "lockedReads","leverReads","selectionKeyReads","actions",
}, "Auto-off fail-closed transition")

local rapidBefore = Snapshot()
for _ = 1, 10 do
    assert(runtime.ToggleAuto() == true, "rapid Auto enable failed")
    assert(runtime.ToggleAuto() == false, "rapid Auto disable failed")
end
H.Advance(0.8, 0.2)
local rapid = Delta(Snapshot(), rapidBefore)
CheckZero(rapid, {
    "fullSteps","catalogAll","catalogAllRows","selectedGets",
    "selectedEchoCopies","previewCompiles","matchingLookups",
    "dpsEligibilityScans","panelProgress","slotPhases","ownedPhases",
    "lockedPhases","leverPhases","slotReads","ownedReads",
    "lockedReads","leverReads","selectionKeyReads","actions",
}, "rapid Auto on/off coalescing")

-- Ordinary level progress does not alter the projection semantics. Level 1 is
-- a real run boundary: it may refresh Owned once for ghost-state handling and
-- rebuild panel progress once, while reusing the selected build and its plan.
local ordinaryBefore = Snapshot()
H.playerLevel = 41
H.FireEvent("PLAYER_LEVEL_UP", 41)
H.Advance(0.2, 0.2)
local ordinary = Delta(Snapshot(), ordinaryBefore)
Check(ordinary.fullSteps == 1,
    "ordinary level transition ran fullSteps=" .. ordinary.fullSteps)
CheckZero(ordinary, {
    "catalogAll","catalogAllRows","selectedGets","selectedEchoCopies",
    "previewCompiles","matchingLookups","dpsEligibilityScans",
    "panelProgress","slotPhases","ownedPhases","lockedPhases",
    "leverPhases","slotReads","ownedReads","lockedReads","leverReads",
    "actions",
}, "ordinary level transition")
Check(ordinary.selectionKeyReads <= 1,
    "ordinary level repeated selected-key reads=" .. ordinary.selectionKeyReads)

H.playerLevel = 80
H.FireEvent("PLAYER_LEVEL_UP", 80)
H.Advance(0.2, 0.2)
local boundaryBefore = Snapshot()
H.playerLevel = 1
H.FireEvent("PLAYER_LEVEL_UP", 1)
H.Advance(0.2, 0.2)
local boundary = Delta(Snapshot(), boundaryBefore)
Check(boundary.fullSteps == 1,
    "level-1 boundary ran fullSteps=" .. boundary.fullSteps)
Check(boundary.ownedPhases <= 1 and boundary.ownedReads <= 1
    and boundary.panelProgress <= 1,
    string.format("level-1 boundary exceeded owned/progress bound=%d/%d",
        boundary.ownedReads, boundary.panelProgress))
CheckZero(boundary, {
    "catalogAll","catalogAllRows","selectedGets","selectedEchoCopies",
    "previewCompiles","dpsEligibilityScans","slotPhases","lockedPhases",
    "leverPhases","slotReads","lockedReads","leverReads","actions",
}, "level-1 run boundary")
Check(boundary.matchingLookups <= 1,
    "level-1 boundary repeated matching lookups=" .. boundary.matchingLookups)
Check(boundary.selectionKeyReads <= 1,
    "level-1 boundary repeated selected-key reads=" .. boundary.selectionKeyReads)

-- A selected-record revision is the one permitted cold invalidation. It may
-- materialize/compile/progress exactly once, but exact matching must use an
-- index rather than BuildCatalog.All. The next unchanged fallback check stays
-- status-only and performs no repair or heavy work.
selectedRevision = selectedRevision + 1
local changedBefore = Snapshot()
assert(Nexus.RequestRecompute())
H.Advance(0.2, 0.2)
local changed = Delta(Snapshot(), changedBefore)
Check(changed.fullSteps == 1 and changed.selectedGets == 1
    and changed.selectedEchoCopies == #selectedEchoes
    and changed.selectionKeyReads == 1 and changed.previewCompiles == 1
    and changed.panelProgress == 1,
    string.format("selected revision did not rebuild exactly once: full=%d key=%d get=%d copies=%d compile=%d progress=%d",
        changed.fullSteps, changed.selectionKeyReads, changed.selectedGets,
        changed.selectedEchoCopies,
        changed.previewCompiles, changed.panelProgress))
CheckZero(changed, {"catalogAll","catalogAllRows","dpsEligibilityScans","actions"},
    "selected revision indexed rebuild")
Check(changed.matchingLookups <= 1,
    "selected revision repeated matching lookups=" .. changed.matchingLookups)

local fallbackBefore = Snapshot()
H.Advance(5.2, 0.2)
local fallback = Delta(Snapshot(), fallbackBefore)
Check(fallback.fallbackChecks >= 1 and fallback.fallbackRepairs == 0,
    string.format("unchanged fallback truth drifted: checks=%d repairs=%d",
        fallback.fallbackChecks, fallback.fallbackRepairs))
CheckZero(fallback, {
    "fullSteps","catalogAll","catalogAllRows","selectedGets",
    "selectedEchoCopies","previewCompiles","matchingLookups",
    "dpsEligibilityScans","panelProgress","slotPhases","ownedPhases",
    "lockedPhases","leverPhases","slotReads","ownedReads",
    "lockedReads","leverReads","selectionKeyReads","actions",
}, "status-only fallback")

-- Combined event boundaries must remain one decision with revision-keyed
-- acquisition, not one decision per notification.
local combinedBefore = Snapshot()
H.playerLevel = 42
H.FireEvent("PLAYER_LEVEL_UP", 42)
H.DeliverBoard({{spellId=200102,quality=2}})
H.Advance(0.2, 0.2)
local combined = Delta(Snapshot(), combinedBefore)
Check(combined.fullSteps == 1,
    "same-interval level/board change ran fullSteps=" .. combined.fullSteps)
Check(combined.ownedReads <= 1 and combined.panelProgress <= 1,
    string.format("same-interval level/board exceeded owned/progress=%d/%d",
        combined.ownedReads,combined.panelProgress))
CheckZero(combined, {
    "catalogAll","catalogAllRows","selectedGets","selectedEchoCopies",
    "previewCompiles","dpsEligibilityScans","slotReads","lockedReads",
    "leverReads","actions",
}, "same-interval level and board")

-- Arrange the next board notification on the same 0.2-second tick as the
-- five-second safety fallback. The board owns one Step; unchanged fallback
-- truth remains a check only.
local observedFallbacks = Snapshot().fallbackChecks
local fallbackGuard = 0
repeat
    H.Advance(0.2, 0.2)
    fallbackGuard = fallbackGuard + 1
until Snapshot().fallbackChecks > observedFallbacks or fallbackGuard >= 30
assert(fallbackGuard < 30, "could not observe the fallback cadence boundary")
H.Advance(4.8, 0.2)
local collisionBefore = Snapshot()
H.DeliverBoard({{spellId=200104,quality=3}})
H.Advance(0.2, 0.2)
local collision = Delta(Snapshot(), collisionBefore)
Check(collision.fullSteps == 1 and collision.fallbackChecks >= 1
    and collision.fallbackRepairs == 0,
    string.format("Echo/fallback collision mismatch full=%d checks=%d repairs=%d",
        collision.fullSteps,collision.fallbackChecks,collision.fallbackRepairs))
CheckZero(collision, {
    "catalogAll","catalogAllRows","selectedGets","selectedEchoCopies",
    "previewCompiles","dpsEligibilityScans","panelProgress","slotReads",
    "ownedReads","lockedReads","leverReads","actions",
}, "Echo change during fallback")

-- Unrelated Sync revision traffic overlapping a board change must not add a
-- second automation Step or invalidate its static/projection caches.
local syncBefore = Snapshot()
Nexus.Revisions.Advance(Nexus.Revisions.SYNC_CHANGED,
    {reason="stage28-overlap"})
H.DeliverBoard({{spellId=200100,quality=1}})
H.Advance(0.2, 0.2)
local syncOverlap = Delta(Snapshot(), syncBefore)
Check(syncOverlap.fullSteps == 1,
    "Sync/Echo overlap ran fullSteps=" .. syncOverlap.fullSteps)
CheckZero(syncOverlap, {
    "catalogAll","catalogAllRows","selectedGets","selectedEchoCopies",
    "previewCompiles","dpsEligibilityScans","panelProgress","slotReads",
    "ownedReads","lockedReads","leverReads","actions",
}, "Sync traffic overlapping Echo change")

-- Hidden/visible transitions are scalar selection changes. A hidden panel
-- never materializes the selected build; restoring the same visible revision
-- reuses its preview plan. A stale selected ID is cached as a bounded miss.
selectedVisible = false
local hiddenBefore = Snapshot()
assert(Nexus.RequestRecompute())
H.Advance(0.2, 0.2)
local hidden = Delta(Snapshot(), hiddenBefore)
Check(hidden.fullSteps == 1 and hidden.panelProgress <= 1,
    "hidden transition did not remain one bounded rebuild")
CheckZero(hidden, {
    "catalogAll","catalogAllRows","selectedGets","selectedEchoCopies",
    "previewCompiles","dpsEligibilityScans","actions",
}, "hidden selected preview")

selectedVisible = true
local visibleBefore = Snapshot()
assert(Nexus.RequestRecompute())
H.Advance(0.2, 0.2)
local visible = Delta(Snapshot(), visibleBefore)
Check(visible.fullSteps == 1 and visible.panelProgress <= 1,
    "visible transition did not remain one bounded rebuild")
CheckZero(visible, {
    "catalogAll","catalogAllRows","selectedGets","selectedEchoCopies",
    "previewCompiles","dpsEligibilityScans","actions",
}, "restored selected preview")

selectedId = "stage28-stale-selection"
selectedRevision = selectedRevision + 1
local staleBefore = Snapshot()
assert(Nexus.RequestRecompute())
H.Advance(0.2, 0.2)
local stale = Delta(Snapshot(), staleBefore)
Check(stale.fullSteps == 1 and stale.selectedGets == 1
    and stale.selectedEchoCopies == 0 and stale.previewCompiles == 0
    and stale.panelProgress <= 1,
    string.format("stale selection was not a bounded miss=%d/%d/%d/%d",
        stale.selectedGets,stale.selectedEchoCopies,
        stale.previewCompiles,stale.panelProgress))
CheckZero(stale, {"catalogAll","catalogAllRows","actions"},
    "stale selected build")

-- Missing Project Ebonhold services fail closed. A GameAdapter poll exception
-- is contained before Step and cannot mutate or consume a gameplay deadline.
local savedService = ProjectEbonhold.PerkService
ProjectEbonhold.PerkService = nil
local missingBefore = Snapshot()
assert(Nexus.RequestRecompute())
H.Advance(0.2, 0.2)
local missing = Delta(Snapshot(), missingBefore)
ProjectEbonhold.PerkService = savedService
Check(missing.actions == 0 and missing.pollFailures == 0,
    string.format("missing service did not fail closed actions=%d pollFailures=%d",
        missing.actions,missing.pollFailures))

local originalPoll = Nexus.GameAdapter.Poll
Nexus.GameAdapter.Poll = function() error("stage28 adapter failure") end
local errorBefore = Snapshot()
H.Advance(0.2, 0.2)
local adapterError = Delta(Snapshot(), errorBefore)
Nexus.GameAdapter.Poll = originalPoll
Check(adapterError.pollFailures == 1 and adapterError.fullSteps == 0
    and adapterError.actions == 0,
    string.format("adapter failure containment mismatch polls=%d full=%d actions=%d",
        adapterError.pollFailures,adapterError.fullSteps,adapterError.actions))

print(string.format(
    "stage28 automation characterization: builds=%d dps=%d rolls=%d rollHeavy[all=%d rows=%d selected=%d copies=%d key=%d compile=%d match=%d progress=%d phases=%d/%d/%d/%d reads=%d/%d/%d/%d] auto[onFull=%d offFull=%d offActions=%d] levels[ordinary=%d/%d/%d/%d/%d boundary=%d/%d/%d/%d/%d] selectedChange[all=%d key=%d get=%d compile=%d match=%d progress=%d] fallback=%d/%d",
    BUILD_ROWS,DPS_ROWS,ROLLS,rolls.catalogAll,rolls.catalogAllRows,
    rolls.selectedGets,rolls.selectedEchoCopies,rolls.selectionKeyReads,
    rolls.previewCompiles,rolls.matchingLookups,rolls.panelProgress,
    rolls.slotPhases,rolls.ownedPhases,rolls.lockedPhases,rolls.leverPhases,
    rolls.slotReads,rolls.ownedReads,rolls.lockedReads,rolls.leverReads,
    on.fullSteps,off.fullSteps,off.actions,
    ordinary.slotReads,ordinary.ownedReads,ordinary.lockedReads,
    ordinary.leverReads,ordinary.panelProgress,boundary.slotReads,
    boundary.ownedReads,boundary.lockedReads,boundary.leverReads,
    boundary.panelProgress,changed.catalogAll,changed.selectionKeyReads,
    changed.selectedGets,changed.previewCompiles,changed.matchingLookups,
    changed.panelProgress,fallback.fallbackChecks,fallback.fallbackRepairs))

if #findings > 0 then
    error("Stage 28.2 automation regression:\n - "
        .. table.concat(findings, "\n - "))
end

print("Stage 28 automation, overlay, level, toggle, and fallback bounds -- OK")
