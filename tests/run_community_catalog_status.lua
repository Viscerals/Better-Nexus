-- Stage 35.8: the immutable baseline, overlay, active filters, and displayed
-- window must remain separate fixed facts through the real Community owners.
local H = dofile("tests/harness.lua")
dofile("data/BundledBuilds.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

UnitName = function() return "StatusMage" end
UnitClass = function() return "Mage", "MAGE" end
GetNormalizedRealmName = function() return "Ebonhold" end

NexusDB = {
    settingsVersion=2,settings={},chars={},dpsCapture={},
    communityBuilds={},syncTombstones={},futureRoot={keep=true},
    buildFilters={
        scope="all",search="",sortMode="title",classFilter="MAGE",
        currentClassOnly=false,qualifiedOnly=false,page=3,pageSize=20,
        category="builds",futureFilter="keep",
    },
}
Nexus.Store.Init()

local eligibilityReads = 0
Nexus.DpsCapture = {
    GetCommunityEligibility=function()
        eligibilityReads = eligibilityReads + 1
        return {}
    end,
    GetLeaderboard=function() return {} end,
    GetLeaderboardForEchoes=function() return {} end,
    GetPersonalBest=function() return nil end,
    GetDpsBoard=function() return {} end,
    IsDetailsAvailable=function() return false end,
}
local receiving = false
Nexus.Sync = {
    IsReceiving=function() return receiving end,
    ReceiveTimeLeft=function() return receiving and 12 or 0 end,
    LastSyncNewCount=function() return 0 end,
    Stats=function() return {received=0} end,
    RequestSync=function() return true end,
}
Nexus.Panel = {
    AttachMenuFrame=function() return true end,
    CloseOtherWindows=function() return true end,
    Refresh=function() return true end,
}

dofile("ui/CommunityBuilds.lua")
local C = Nexus.CommunityBuilds
C.Init(nil,nil)
C.Show()

local frame = assert(H.frames.NexusCommunityBuildsFrame,
    "Community frame did not initialize")
local blank = C.DiagnosticSnapshot()
assert(blank.bundledCount == 504 and blank.overlayCount == 0
    and blank.availableCount == 504 and blank.filterMatchedCount == 504
    and blank.qualifyingCount == 0 and blank.resultCount == 504
    and blank.displayedCount == 20 and not blank.searchActive
    and blank.catalogVersion == "1.19.4-05efb360ae5b"
    and blank.publishedPage == 3,
    string.format("blank status mismatch: bundled=%s overlay=%s available=%s matched=%s qualifying=%s result=%s displayed=%s version=%s page=%s",
        tostring(blank.bundledCount),tostring(blank.overlayCount),
        tostring(blank.availableCount),tostring(blank.filterMatchedCount),
        tostring(blank.qualifyingCount),tostring(blank.resultCount),
        tostring(blank.displayedCount),tostring(blank.catalogVersion),
        tostring(blank.publishedPage)))
assert(frame._syncStatusText.text:find("504 bundled",1,true)
    and frame._syncStatusText.text:find("504 available",1,true)
    and frame._syncStatusText.text:find("1.19.4-05efb360ae5b",1,true),
    "visible Community status did not distinguish baseline/availability/version")
receiving = true
C.Refresh()
assert(frame._syncStatusText.text:find("Listening",1,true)
    and frame._syncStatusText.text:find("504 bundled",1,true)
    and frame._syncStatusText.text:find("20 shown of 504",1,true),
    "active Sync hid the bundled baseline or displayed-result status")
receiving = false
C.Refresh()

local beforeWarm = Nexus.ViewProjections.Stats().builds
local beforeCatalog = Nexus.BuildCatalog.DebugStats()
local beforeEligibility = eligibilityReads
local realCount = Nexus.BuildCatalog.Count
local realStatus = Nexus.BuildCatalog.Status
local warmStatusReads = 0
Nexus.BuildCatalog.Count = function()
    error("warm Community status must use fixed catalog scalars")
end
Nexus.BuildCatalog.Status = function(...)
    warmStatusReads = warmStatusReads + 1
    return realStatus(...)
end
C.Refresh()
local afterWarm = Nexus.ViewProjections.Stats().builds
local afterCatalog = Nexus.BuildCatalog.DebugStats()
assert(afterWarm.catalogWalks == beforeWarm.catalogWalks
    and afterWarm.dpsReads == beforeWarm.dpsReads
    and afterWarm.sorts == beforeWarm.sorts
    and afterCatalog.summarySnapshots == beforeCatalog.summarySnapshots
    and eligibilityReads == beforeEligibility and warmStatusReads == 0,
    "warm Community status repeated catalog/DPS/sort work")
Nexus.BuildCatalog.Count = realCount
Nexus.BuildCatalog.Status = realStatus

-- Qualification narrows the result without pretending the baseline vanished.
frame._qualifiedBtn:GetScript("OnClick")()
local qualified = C.DiagnosticSnapshot()
assert(qualified.availableCount == 504 and qualified.filterMatchedCount == 504
    and qualified.qualifyingCount == 0 and qualified.resultCount == 0
    and qualified.displayedCount == 0,
    "qualification status conflated available, qualifying, and displayed rows")
frame._qualifiedBtn:GetScript("OnClick")()

-- Search through the real edit/filter owner, advance its page, then clear it.
-- The clear action must alter only search while restoring the caller's page.
local search = assert(frame._searchBox)
search:SetText("warrior")
search:GetScript("OnTextChanged")(search)
local narrowed = C.DiagnosticSnapshot()
assert(narrowed.searchActive and narrowed.filterMatchedCount > 20
    and narrowed.filterMatchedCount < 504
    and narrowed.availableCount == 504
    and narrowed.resultCount == narrowed.filterMatchedCount,
    "search status did not narrow honestly")
frame._nextPageBtn:GetScript("OnClick")()
assert(NexusDB.buildFilters.page == 2,
    "search fixture could not establish a non-default page")
C.Hide(); C.Show()
frame = assert(H.frames.NexusCommunityBuildsFrame)
assert(NexusDB.buildFilters.search == "warrior"
    and NexusDB.buildFilters.page == 2
    and frame._searchBox:GetText() == "warrior",
    "reopen reset an active search or its page")
local preserved = {}
for key, value in pairs(NexusDB.buildFilters) do
    if key ~= "search" then preserved[key] = value end
end
local clear = assert(frame._clearSearchBtn,
    "Community did not expose an explicit Clear Search action")
assert(clear:IsShown() and clear:GetText() == "Clear Search",
    "Clear Search action was not visibly bound while search was active")
clear:GetScript("OnClick")()
assert(NexusDB.buildFilters.search == "" and search:GetText() == ""
    and NexusDB.buildFilters.page == 2,
    "Clear Search did not clear through the filter owner and preserve page")
for key, value in pairs(preserved) do
    assert(NexusDB.buildFilters[key] == value,
        "Clear Search changed unrelated filter: " .. tostring(key))
end
local cleared = C.DiagnosticSnapshot()
assert(not cleared.searchActive and cleared.availableCount == 504
    and cleared.resultCount == 504 and cleared.displayedCount == 20,
    "clear action did not restore the visible bundled baseline")

-- A real owner mutation updates the O(1) status and the revision-keyed
-- projection once; it neither copies the bundle into SavedVariables nor
-- changes the immutable baseline count.
assert(Nexus.BuildCatalog.Put({
    id="stage35-overlay",title="Stage 35 Overlay",description="status",
    author="Peer",ownerKey="peer@ebonhold",class="MAGE",
    postedAt=2000000000,lastModified=2000000000,
    echoes={{spellId=990001,quality=3,stacks=1}},
}))
C.MarkDataDirty()
C.Refresh()
local overlaid = C.DiagnosticSnapshot()
assert(overlaid.bundledCount == 504 and overlaid.overlayCount == 1
    and overlaid.availableCount == 505 and overlaid.resultCount == 505
    and NexusDB.communityBuilds["stage35-overlay"] ~= nil,
    "overlay status did not update independently from the bundled baseline")
local bundledRows = 0
for _ in pairs(Nexus.BundledBuilds.builds) do bundledRows = bundledRows + 1 end
assert(bundledRows == 504 and Nexus.BundledBuilds.builds["stage35-overlay"] == nil,
    "status mutation changed or duplicated the immutable baseline")

assert(Nexus.BuildCatalog.PutDeferred({
    id="stage35-deferred",title="Deferred Overlay",author="Peer",
    ownerKey="peer@ebonhold",class="MAGE",postedAt=2000000001,
    lastModified=2000000001,
    echoes={{spellId=990002,quality=3,stacks=1}},
}))
local beforePublish = Nexus.BuildCatalog.Status()
assert(beforePublish.overlayCount == 2 and beforePublish.availableCount == 506,
    "fixed catalog status diverged from deferred storage state")
assert(Nexus.BuildCatalog.PublishDeferred(1,"status fixture"))
local afterPublish = Nexus.BuildCatalog.Status()
assert(afterPublish.overlayCount == 2 and afterPublish.availableCount == 506,
    "deferred publication changed already represented catalog status")
assert(Nexus.BuildCatalog.SetTombstone("stage35-deferred",{stamp=2000000002}))
local tombstoned = Nexus.BuildCatalog.Status()
assert(tombstoned.overlayCount == 1 and tombstoned.tombstoneCount == 1
    and tombstoned.availableCount == 505,
    "tombstone status did not remove overlay availability exactly once")
assert(Nexus.BuildCatalog.ClearTombstone("stage35-deferred"))
local clearedTombstone = Nexus.BuildCatalog.Status()
assert(clearedTombstone.overlayCount == 1
    and clearedTombstone.tombstoneCount == 0
    and clearedTombstone.availableCount == 505,
    "cleared tombstone restored unavailable overlay data")

-- Closing, reopening, and rebuilding the facade retain the same owned filter
-- table and never perform a hidden reset.
local reopenSignature = table.concat({
    NexusDB.buildFilters.scope,tostring(NexusDB.buildFilters.currentClassOnly),
    NexusDB.buildFilters.classFilter,
    tostring(NexusDB.buildFilters.qualifiedOnly),NexusDB.buildFilters.sortMode,
    NexusDB.buildFilters.category,tostring(NexusDB.buildFilters.page),
    NexusDB.buildFilters.search,NexusDB.buildFilters.futureFilter,
}, "|")
C.Hide(); C.Show()
assert(reopenSignature == table.concat({
    NexusDB.buildFilters.scope,tostring(NexusDB.buildFilters.currentClassOnly),
    NexusDB.buildFilters.classFilter,
    tostring(NexusDB.buildFilters.qualifiedOnly),NexusDB.buildFilters.sortMode,
    NexusDB.buildFilters.category,tostring(NexusDB.buildFilters.page),
    NexusDB.buildFilters.search,NexusDB.buildFilters.futureFilter,
}, "|"), "reopen reset an owned or unknown filter")
C.Hide()
dofile("ui/CommunityBuilds.lua")
C = Nexus.CommunityBuilds
C.Init(nil,nil); C.Show()
local reloaded = C.DiagnosticSnapshot()
assert(reloaded.bundledCount == 504 and reloaded.overlayCount == 1
    and reloaded.availableCount == 505 and reloaded.publishedPage == 2
    and NexusDB.futureRoot.keep and NexusDB.buildFilters.futureFilter == "keep",
    "reload lost status, page, or unknown SavedVariables fields")

print(string.format(
    "community catalog status: bundled=%d overlay=%d available=%d displayed=%d page=%d warm_delta=0 -- OK",
    reloaded.bundledCount,reloaded.overlayCount,reloaded.availableCount,
    reloaded.displayedCount,reloaded.publishedPage))
