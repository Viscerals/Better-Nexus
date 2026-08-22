-- Active Sync and unchanged safety ticks never rebuild Community data.
local H = dofile("tests/harness.lua")
dofile("ui/Theme.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

UnitName = function() return "BudgetMage" end
GetNormalizedRealmName = function() return "Ebonhold" end
NexusDB = {
    communityBuilds={},buildFilters={sortMode="title"},
    dpsCapture={characterBest={dummy={},lk={}},personalBest={},buildBest={}},
}
for index = 1, 1000 do
    local id = string.format("budget-%04d", index)
    local fingerprint = tostring(720000+index) .. "x1"
    NexusDB.communityBuilds[id] = {
        id=id,title=string.format("Build %04d", index),author="Peer",
        ownerKey="peer@ebonhold",class="MAGE",
        postedAt=index,lastModified=index,fingerprint=fingerprint,
        echoes={{spellId=720000+index,quality=3,stacks=1}},
    }
    if index <= 250 then
        for _, category in ipairs({"dummy", "lk"}) do
            NexusDB.dpsCapture.characterBest[category]
                [category.."player"..index] = {
                player="Player"..index,
                ownerKey="player"..index.."@ebonhold",
                ownerVerified=true,realm="ebonhold",lockedEchoes={},
                dps=(category == "dummy" and 100000 or 200000)+index,
                level=80,ts=index,duration=60,class="MAGE",
                buildId=id,fingerprint=fingerprint,
                echoes={{spellId=720000+index,count=1}},protocolVersion=7,
            }
        end
    end
end
Nexus.Store.Init()
local fullCatalogReads = 0
local originalAll = Nexus.BuildCatalog.All
Nexus.BuildCatalog.All = function(...)
    fullCatalogReads = fullCatalogReads + 1
    return originalAll(...)
end
dofile("core/DpsCapture.lua")
Nexus.DpsCapture.Init({}, {})

local receiving, receiveCount = false, 0
Nexus.Sync = {
    IsReceiving=function() return receiving end,
    LastSyncNewCount=function() return receiveCount end,
    ReceiveTimeLeft=function() return receiving and 3 or 0 end,
    Stats=function() return {received=receiveCount} end,
}

dofile("ui/CommunityBuilds.lua")
local C, P = Nexus.CommunityBuilds, Nexus.ViewProjections
C.Init(nil,nil)
for _, category in ipairs({"dummy", "lk"}) do
    for _, row in pairs(NexusDB.dpsCapture.characterBest[category]) do
        local build = Nexus.BuildCatalog.Get(row.buildId)
        row.fingerprint = build and build.fingerprint or row.fingerprint
    end
end
fullCatalogReads = 0
C.Show()
local frame = NexusCommunityBuildsFrame
local onUpdate = frame and frame:GetScript("OnUpdate")
assert(type(onUpdate) == "function", "Community frame did not install update handler")
local function PumpUntilBinds(target)
    for _ = 1, 100 do
        if (C.VirtualStats().dataBinds or 0) >= target then return end
        onUpdate(frame, 0.05)
    end
    error("Community resumable projection did not publish")
end
PumpUntilBinds(1)

local initialVirtual = C.VirtualStats()
local initialProjection = P.Stats().builds
local initialIdentity = Nexus.DpsCapture.IdentityLookupStats()
assert(initialIdentity.rebuilds == 1 and initialIdentity.rowsScanned == 500
    and initialIdentity.lookups == 0 and initialIdentity.candidateChecks == 0
    and initialIdentity.eligibilityReads == 1
    and initialIdentity.intersections == 1
    and initialVirtual.results == 20
    and fullCatalogReads == 0
    and Nexus.BuildCatalog.Count() == 1000,
    string.format("Community budget mismatch: results=%s rebuilds=%s scans=%s indexed=%s lookups=%s candidates=%s eligibility=%s intersections=%s full=%s count=%s",
        tostring(initialVirtual.results),tostring(initialIdentity.rebuilds),
        tostring(initialIdentity.rowsScanned),tostring(initialIdentity.indexedRows),
        tostring(initialIdentity.lookups),tostring(initialIdentity.candidateChecks),
        tostring(initialIdentity.eligibilityReads),tostring(initialIdentity.intersections),
        tostring(fullCatalogReads),tostring(Nexus.BuildCatalog.Count())))

-- The actual Next/Prev control path must slice the retained query. It may bind
-- a different 20-row window, but cannot reacquire, republish, re-sort, or
-- advance represented data merely because the page number changed.
local beforePageWork = P.WorkStats()
local beforePageProjection = P.Stats().builds
local beforeBuildRevision = Nexus.Revisions.Get(
    Nexus.Revisions.BUILD_LIBRARY_CHANGED)
local beforeDpsRevision = Nexus.Revisions.Get(Nexus.Revisions.DPS_CHANGED)
local nextPage = assert(frame._nextPageBtn and
    frame._nextPageBtn:GetScript("OnClick"),
    "Community Next page control is unavailable")
nextPage(frame._nextPageBtn)
local pageTwoVirtual = C.VirtualStats()
local pageTwoWork = P.WorkStats()
local pageTwoProjection = P.Stats().builds
assert(pageTwoVirtual.dataBinds == initialVirtual.dataBinds + 1
    and NexusDB.buildFilters.page == 2
    and frame._pageText:GetText() == "2 / 13"
    and frame._resultText:GetText():find("Showing 21-40 of 250", 1, true)
    and pageTwoWork.acquisitions == beforePageWork.acquisitions
    and pageTwoWork.publications == beforePageWork.publications
    and pageTwoProjection.rebuilds == beforePageProjection.rebuilds
    and pageTwoProjection.sorts == beforePageProjection.sorts
    and Nexus.Revisions.Get(Nexus.Revisions.BUILD_LIBRARY_CHANGED)
        == beforeBuildRevision
    and Nexus.Revisions.Get(Nexus.Revisions.DPS_CHANGED) == beforeDpsRevision,
    "page-two UI navigation rebuilt or mutated the represented query")
local previousPage = assert(frame._prevPageBtn:GetScript("OnClick"))
previousPage(frame._prevPageBtn)
assert(NexusDB.buildFilters.page == 1
    and frame._pageText:GetText() == "1 / 13"
    and C.VirtualStats().dataBinds == initialVirtual.dataBinds + 2
    and P.WorkStats().acquisitions == beforePageWork.acquisitions
    and P.WorkStats().publications == beforePageWork.publications,
    "returning to page one did not reuse the retained query")
initialVirtual = C.VirtualStats()
onUpdate(frame, 8.1)
local unchangedVirtual = C.VirtualStats()
local unchangedProjection = P.Stats().builds
assert(unchangedVirtual.dataBinds == initialVirtual.dataBinds
    and unchangedVirtual.periodicSkips == initialVirtual.periodicSkips + 1
    and unchangedProjection.catalogWalks == initialProjection.catalogWalks
    and unchangedProjection.dpsReads == initialProjection.dpsReads
    and unchangedProjection.sorts == initialProjection.sorts
    and unchangedProjection.defensiveCopies == initialProjection.defensiveCopies
    and Nexus.DpsCapture.IdentityLookupStats().rowsScanned
        == initialIdentity.rowsScanned,
    "unchanged eight-second tick performed Community projection work")

receiving, receiveCount = true, 1
assert(C.MarkDataDirty())
Nexus.Revisions.Advance(Nexus.Revisions.BUILD_LIBRARY_CHANGED, {scope="record"})
onUpdate(frame, 8.1)
local activeVirtual = C.VirtualStats()
assert(activeVirtual.dataBinds == initialVirtual.dataBinds
    and activeVirtual.refreshDirty,
    "active Sync dirty state rebuilt Community data")

receiving = false
onUpdate(frame, 0.25)
PumpUntilBinds(initialVirtual.dataBinds + 1)
local finalVirtual = C.VirtualStats()
local finalProjection = P.Stats().builds
local finalIdentity = Nexus.DpsCapture.IdentityLookupStats()
assert(finalVirtual.dataBinds == initialVirtual.dataBinds + 1
    and finalVirtual.deferredRefreshes == 1
    and not finalVirtual.refreshDirty
    and finalProjection.rebuilds == initialProjection.rebuilds + 1
    and finalProjection.catalogWalks == initialProjection.catalogWalks
    and finalProjection.sorts == initialProjection.sorts + 1
    and finalIdentity.rebuilds == initialIdentity.rebuilds
    and finalIdentity.rowsScanned == initialIdentity.rowsScanned
    and finalIdentity.lookups == initialIdentity.lookups
    and finalIdentity.eligibilityReads == initialIdentity.eligibilityReads + 1
    and finalIdentity.intersections == initialIdentity.intersections,
    "post-Sync dirty data did not publish exactly one complete projection")

onUpdate(frame, 8.1)
local finalNoop = C.VirtualStats()
local finalNoopProjection = P.Stats().builds
assert(finalNoop.dataBinds == finalVirtual.dataBinds
    and finalNoop.periodicSkips == finalVirtual.periodicSkips + 1
    and finalNoopProjection.catalogWalks == finalProjection.catalogWalks
    and finalNoopProjection.dpsReads == finalProjection.dpsReads
    and finalNoopProjection.sorts == finalProjection.sorts
    and finalNoopProjection.defensiveCopies == finalProjection.defensiveCopies,
    "post-publish unchanged tick repeated Community work")

-- A failed cheap probe falls back to the established refresh path instead of
-- silently declaring an unknown cache state current forever.
local originalCurrent = P.BuildsCurrent
P.BuildsCurrent = function() error("dirty probe failure") end
onUpdate(frame, 8.1)
P.BuildsCurrent = originalCurrent
local fallbackVirtual = C.VirtualStats()
assert(fallbackVirtual.dataBinds == finalNoop.dataBinds + 1
    and fallbackVirtual.periodicSkips == finalNoop.periodicSkips,
    "failed dirty probe suppressed the periodic safety refresh")

print(string.format(
    "community refresh budget: rows=1000 dpsRows=%d lookups=%d scans=%d deferred=%d periodicSkips=%d -- OK",
    finalIdentity.indexedRows, finalIdentity.lookups,
    finalIdentity.rowsScanned,
    finalVirtual.deferredRefreshes,
    finalNoop.periodicSkips))
