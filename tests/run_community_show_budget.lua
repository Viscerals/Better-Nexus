-- Regression coverage for the complete bounded Builds-tab open path.
local H = dofile("tests/harness.lua")
dofile("ui/Theme.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

UnitName = function() return "BudgetMage" end
GetNormalizedRealmName = function() return "Ebonhold" end

NexusDB = {
    communityBuilds={},buildFilters={scope="all",sortMode="title"},
    dpsCapture={characterBest={dummy={},lk={}},personalBest={},buildBest={}},
}
for index = 1, 1000 do
    local id = string.format("show-%04d", index)
    NexusDB.communityBuilds[id] = {
        id=id,title=string.format("Show Build %04d", index),author="BudgetMage",
        ownerKey="budgetmage@ebonhold",class="MAGE",
        postedAt=index,lastModified=index,
        echoes={{spellId=740000+index,quality=3,stacks=1}},
    }
end
for index = 1, 250 do
    local id = string.format("show-%04d", index)
    for _, category in ipairs({"dummy", "lk"}) do
        NexusDB.dpsCapture.characterBest[category]
            [category.."showplayer"..index] = {
                player=category.."ShowPlayer"..index,
                dps=(category == "dummy" and 100000 or 200000)+index,
                level=80,ts=index,duration=60,class="MAGE",buildId=id,
                echoes={{spellId=740000+index,count=1}},protocolVersion=7,
            }
    end
end

Nexus.Store.Init()
dofile("core/DpsCapture.lua")
Nexus.DpsCapture.Init({}, {})

local slots = {activeSlot=1,bySlot={}}
for slot = 1, 3 do
    slots.bySlot[slot] = {
        name="Show Build "..string.format("%04d", slot),class="MAGE",
        echoes={{spellId=740000+slot,quality=3,stacks=1,locked=false}},
    }
end
local Adapter = {
    Slots=function() return slots end,
    GetLoadoutWishlist=function() return nil end,
    Owned=function() return {bySpell={}} end,
}

local receiving, receiveCount = false, 0
Nexus.Sync = {
    IsReceiving=function() return receiving end,
    LastSyncNewCount=function() return receiveCount end,
    ReceiveTimeLeft=function() return receiving and 3 or 0 end,
    Stats=function() return {received=receiveCount} end,
    RequestSync=function() return true end,
}

local allSnapshots, fullWalks, fullCopies = 0, 0, 0
local originalAll = Nexus.BuildCatalog.All
Nexus.BuildCatalog.All = function(...)
    allSnapshots = allSnapshots + 1
    local rows = originalAll(...)
    local count = 0
    for _ in pairs(rows) do count = count + 1 end
    fullWalks = fullWalks + count
    fullCopies = fullCopies + count
    return rows
end

local relatedLookups, relatedChecks = 0, 0
local originalRelatedBegin = Nexus.BuildCatalog.BeginRelatedCursor
Nexus.BuildCatalog.BeginRelatedCursor = function(...)
    relatedLookups = relatedLookups + 1
    return originalRelatedBegin(...)
end
local originalRelatedNext = Nexus.BuildCatalog.RelatedCursorNext
Nexus.BuildCatalog.RelatedCursorNext = function(...)
    local row, done, err = originalRelatedNext(...)
    if row then relatedChecks = relatedChecks + 1 end
    return row, done, err
end

local catalogPuts = 0
local originalPut = Nexus.BuildCatalog.Put
Nexus.BuildCatalog.Put = function(...)
    catalogPuts = catalogPuts + 1
    return originalPut(...)
end

local dpsJoins = 0
local originalEligibilityNext = Nexus.DpsCapture.CommunityEligibilityCursorNext
Nexus.DpsCapture.CommunityEligibilityCursorNext = function(cursor)
    local done, err = originalEligibilityNext(cursor)
    if not done and not err then dpsJoins = dpsJoins + 1 end
    return done, err
end

local originalCreateFrame = CreateFrame
local frameCreations, mainFrameCreations = 0, 0
CreateFrame = function(kind, name, ...)
    frameCreations = frameCreations + 1
    if name == "NexusCommunityBuildsFrame" then
        mainFrameCreations = mainFrameCreations + 1
    end
    return originalCreateFrame(kind, name, ...)
end

dofile("ui/CommunityBuilds.lua")
local C, P, Performance = Nexus.CommunityBuilds,
    Nexus.ViewProjections, Nexus.Performance
C.Init(Adapter, nil)
for _, category in ipairs({"dummy", "lk"}) do
    for _, row in pairs(NexusDB.dpsCapture.characterBest[category]) do
        local build = Nexus.BuildCatalog.Get(row.buildId)
        row.fingerprint = assert(build and build.fingerprint,
            "fixture build fingerprint unavailable")
    end
end

allSnapshots, fullWalks, fullCopies = 0, 0, 0
relatedLookups, relatedChecks, catalogPuts = 0, 0, 0
dpsJoins = 0
frameCreations, mainFrameCreations = 0, 0
P.Reset()
Performance.Reset()
local profileClock = 0
Performance.SetClock(function()
    profileClock = profileClock + 2
    return profileClock
end)

local function Snapshot()
    local projection, work = P.Stats().builds, P.WorkStats()
    local catalog = Nexus.BuildCatalog.DebugStats()
    return {
        snapshots=allSnapshots,walks=fullWalks,copies=fullCopies,
        relatedLookups=relatedLookups,relatedChecks=relatedChecks,
        catalogPuts=catalogPuts,dpsJoins=dpsJoins,frames=frameCreations,
        mainFrames=mainFrameCreations,rebuilds=projection.rebuilds,
        sorts=projection.sorts,publications=work.publications,
        buildRevision=Nexus.Revisions.Get(
            Nexus.Revisions.BUILD_LIBRARY_CHANGED) or 0,
        indexRebuilds=catalog.relatedIndexRebuilds or 0,
        maxRelatedCandidates=catalog.maxRelatedCandidates or 0,
        sourceRows=work.sourceRows,comparisons=work.comparisons,
        sortMoves=work.sortMoves,maxSource=work.maxSourceRowsPerPump,
        maxComparisons=work.maxComparisonsPerPump,
        maxSortMoves=work.maxSortMovesPerPump,
        maxJoins=work.maxJoinsPerPump,maxCopies=work.maxCopiesPerPump,
    }
end

local function Delta(after, before)
    local out = {}
    for key, value in pairs(after) do
        out[key] = value - (before[key] or 0)
    end
    return out
end

local function PumpUntilBinds(frame, target)
    local onUpdate = assert(frame and frame:GetScript("OnUpdate"),
        "Community frame did not install an update handler")
    for _ = 1, 160 do
        if (C.VirtualStats().dataBinds or 0) >= target then return end
        onUpdate(frame, 0.05)
    end
    error("Community projection did not publish within the fixture pump bound")
end

local zero = Snapshot()
C.Show()
local frame = assert(NexusCommunityBuildsFrame,
    "real CommunityBuilds.Show did not create the established frame")
PumpUntilBinds(frame, 1)
local afterCold = Snapshot()
local cold = Delta(afterCold, zero)

C.Show()
local afterWarm = Snapshot()
local warm = Delta(afterWarm, afterCold)

receiving, receiveCount = true, 1
assert(C.MarkDataDirty())
Nexus.Revisions.Advance(Nexus.Revisions.BUILD_LIBRARY_CHANGED,
    {scope="community",reason="show-budget-sync"})
C.Show()
local onUpdate = frame:GetScript("OnUpdate")
onUpdate(frame, 8.1)
local duringSync = Snapshot()
assert(duringSync.publications == afterWarm.publications
    and duringSync.rebuilds == afterWarm.rebuilds
    and duringSync.relatedLookups == afterWarm.relatedLookups
    and duringSync.relatedChecks == afterWarm.relatedChecks
    and duringSync.catalogPuts == afterWarm.catalogPuts
    and duringSync.dpsJoins == afterWarm.dpsJoins
    and duringSync.snapshots == afterWarm.snapshots
    and duringSync.walks == afterWarm.walks
    and duringSync.copies == afterWarm.copies
    and frame._syncBtn:GetText() == "Listening..."
    and C.VirtualStats().refreshDirty,
    "active Sync performed Builds work or stopped updating its status")

receiving = false
onUpdate(frame, 0.25)
PumpUntilBinds(frame, (C.VirtualStats().dataBinds or 0) + 1)
local afterSync = Snapshot()
local sync = Delta(afterSync, duringSync)

local definitions = {}
for _, name in ipairs(Performance.Definitions()) do definitions[name] = true end
local recentNames = {}
for _, operation in ipairs(Performance.RecentOperations(999, 1001, H.now)) do
    recentNames[operation.name] = true
end
for _, name in ipairs({
    "community.show","community.saved-import","community.related-lookup",
    "community.frame.ensure","community.projection","community.render",
}) do
    assert(definitions[name] and recentNames[name],
        "missing bounded Builds-path breadcrumb: "..name)
end

assert(Nexus.BuildCatalog.Count() == 1003,
    "large fixture or imported saved mirrors were capped")
assert(cold.dpsJoins >= 500 and cold.rebuilds == 1
    and cold.publications == 1 and cold.mainFrames == 1
    and cold.snapshots == 0 and cold.walks == 0 and cold.copies == 0
    and cold.relatedLookups == 3 and cold.relatedChecks <= 3
    and cold.catalogPuts == 3 and cold.indexRebuilds == 0
    and cold.maxSource <= 25 and cold.maxComparisons <= 500
    and cold.maxSortMoves <= 500 and cold.maxJoins <= 25
    and cold.maxCopies <= 25,
    string.format("cold fixture mismatch: snapshots=%d walks=%d copies=%d lookups=%d candidates=%d puts=%d indexRebuilds=%d joins=%d rebuilds=%d publications=%d mainFrames=%d sourceMax=%d compareMax=%d sortMax=%d joinMax=%d copyMax=%d",
        cold.snapshots,cold.walks,cold.copies,cold.relatedLookups,
        cold.relatedChecks,cold.catalogPuts,cold.indexRebuilds,
        cold.dpsJoins,cold.rebuilds,cold.publications,cold.mainFrames,
        cold.maxSource,cold.maxComparisons,cold.maxSortMoves,
        cold.maxJoins,cold.maxCopies))
assert(warm.rebuilds == 0 and warm.publications == 0
    and warm.frames == 0 and warm.mainFrames == 0 and warm.snapshots == 0
    and warm.walks == 0 and warm.copies == 0
    and warm.relatedLookups == 0 and warm.relatedChecks == 0
    and warm.catalogPuts == 0 and warm.dpsJoins == 0
    and warm.sorts == 0 and warm.buildRevision == 0
    and warm.indexRebuilds == 0,
    "warm Show repeated catalog, DPS, projection, write, revision, publication, or frame work")
assert(sync.rebuilds == 1 and sync.publications == 1,
    "quiet Sync completion did not publish exactly one Builds projection")
local importStats = C.VirtualStats().savedImport
assert(importStats.maxCandidatesPerPump <= 25 and not importStats.pending,
    "saved-slot reconciliation exceeded its fixed candidate pump or stayed pending")

print(string.format(
    "community show budget: cold snapshots=%d walks=%d copies=%d lookups=%d candidates=%d puts=%d dpsJoins=%d rebuilds=%d sorts=%d sortMoves=%d frames=%d mainFrames=%d publications=%d sourceMax=%d compareMax=%d; warm snapshots=%d walks=%d copies=%d lookups=%d candidates=%d puts=%d revisions=%d rebuilds=%d publications=%d; sync rebuilds=%d publications=%d maxCandidates=%d",
    cold.snapshots,cold.walks,cold.copies,cold.relatedLookups,
    cold.relatedChecks,cold.catalogPuts,cold.dpsJoins,
    cold.rebuilds,cold.sorts,cold.sortMoves,cold.frames,cold.mainFrames,
    cold.publications,cold.maxSource,cold.maxComparisons,
    warm.snapshots,warm.walks,warm.copies,warm.relatedLookups,
    warm.relatedChecks,warm.catalogPuts,warm.buildRevision,
    warm.rebuilds,warm.publications,sync.rebuilds,sync.publications,
    afterSync.maxRelatedCandidates))

assert(cold.snapshots == 0 and cold.walks == 0 and cold.copies == 0
    and warm.snapshots == 0 and warm.walks == 0 and warm.copies == 0,
    string.format("CommunityBuilds.Show regressed to full-catalog amplification (cold=%d/%d/%d warm=%d/%d/%d)",
        cold.snapshots,cold.walks,cold.copies,
        warm.snapshots,warm.walks,warm.copies))
