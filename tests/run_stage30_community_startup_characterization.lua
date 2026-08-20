-- Stage 30 persisted-view regression: Community and Leaderboard rows must be
-- readable during an active receive window, while a personal Saved-Build
-- import remains an independent lane. Cached page changes must bind new IDs.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")
dofile("ui/Theme.lua")

UnitName = function() return "StageThirtyMage" end
GetNormalizedRealmName = function() return "Ebonhold" end
UnitClass = function() return "Mage", "MAGE" end

NexusDB = {
    settingsVersion=2,settings={},chars={},
    buildFilters={
        scope="all",classFilter="MAGE",currentClassOnly=true,
        qualifiedOnly=false,search="",sortMode="title",page=1,pageSize=20,
        futureFilter={keep=true},
    },
    communityBuilds={},
    dpsCapture={characterBest={dummy={},lk={}},personalBest={},buildBest={}},
    futureRoot={keep=true},
}

for index = 1, 45 do
    local id = string.format("stage30-public-%02d", index)
    local fingerprint = tostring(760000+index) .. "x1"
    NexusDB.communityBuilds[id] = {
        id=id,title=string.format("%02d Persisted Mage", index),
        description="persisted before Sync",author="Peer" .. index,
        ownerKey=("peer" .. index .. "@ebonhold"),class="MAGE",
        postedAt=index,lastModified=index,fingerprint=fingerprint,
        echoes={{spellId=760000+index,quality=3,stacks=1}},
        futureBuildField={keep=true},
    }
end

for index = 1, 4 do
    local id = string.format("stage30-public-%02d", index)
    local fingerprint = tostring(760000+index) .. "x1"
    for _, category in ipairs({"dummy", "lk"}) do
        local player = string.format("PersistedMage%02d", index)
        NexusDB.dpsCapture.characterBest[category][player:lower()] = {
            player=player,dps=(category == "dummy" and 90000 or 80000)+index,
            level=80,ts=index,duration=(category == "dummy" and 60 or 90),
            category=category,class="MAGE",buildId=id,
            fingerprint=fingerprint,echoes={{spellId=760000+index,count=1}},
            protocolVersion=7,
        }
    end
end

Nexus.Store.Init()
dofile("core/DpsCapture.lua")
Nexus.DpsCapture.Init({}, {})

local receiving = true
local receivedMessages = 0
Nexus.Sync = {
    IsReceiving=function() return receiving end,
    ReceiveTimeLeft=function() return receiving and 30 or 0 end,
    LastSyncNewCount=function() return receivedMessages end,
    Stats=function() return {received=receivedMessages} end,
    GetLeaderboardSyncStatus=function()
        return receiving and "syncing" or "idle",0,0,
            {receiving=receiving and 1 or 0}
    end,
    RequestSync=function() error("manual Sync is forbidden in this fixture") end,
}

local personalSlot = {
    slot=1,name="Personal Saved Build",class="MAGE",verified=true,
    echoes={{spellId=760001,quality=3,stacks=1,locked=false}},
}
local Adapter = {
    Slots=function()
        return {bySlot={[1]=personalSlot},activeSlot=1,maxSlots=5}
    end,
    GetLoadoutWishlist=function() return nil end,
    GetWishlistCandidates=function() return {} end,
    Catalog=function() return {rows={}} end,
    Owned=function() return {bySpell={}} end,
    LockedOwned=function() return {bySpell={}} end,
    Wishlist=function() return nil end,
    PresentationRevisions=function() return 1,1,1,1,1,1,1,1,1,1,0 end,
}

local realCreateFrame = CreateFrame
local created = {}
CreateFrame = function(kind, name, parent, template)
    local frame = realCreateFrame(kind, name, parent, template)
    frame._stage30Kind, frame._stage30Parent = kind, parent
    created[#created + 1] = frame
    return frame
end

dofile("ui/CommunityBuilds.lua")
dofile("ui/Leaderboard.lua")
local Community = Nexus.CommunityBuilds
local Projections = Nexus.ViewProjections
Community.Init(Adapter, nil)
Projections.Reset()

local failures = {}
local function Expect(name, condition, detail)
    if not condition then failures[#failures + 1] = name .. ": " .. detail end
end

local function ActiveBuildIds()
    local ids = {}
    for _, frame in ipairs(created) do
        if frame.buildId then ids[#ids + 1] = frame.buildId end
    end
    table.sort(ids)
    return ids
end

local function SameIds(left, right)
    if #left ~= #right then return false end
    for index = 1, #left do
        if left[index] ~= right[index] then return false end
    end
    return true
end

Community.Show()
local communityFrame = assert(NexusCommunityBuildsFrame,
    "Community frame was not assembled")
local communityUpdate = assert(communityFrame:GetScript("OnUpdate"),
    "Community update path was not installed")
communityUpdate(communityFrame, 0.5)
for _ = 1, 160 do
    communityUpdate(communityFrame, 0.05)
    if Community.VirtualStats().dataBinds >= 1 then break end
end
local coldStats = Community.VirtualStats()
local coldView = Community.DiagnosticSnapshot()
Expect("community_cold_persisted_rows_publish_during_receive",
    coldStats.dataBinds == 1 and coldStats.results == 20
        and #ActiveBuildIds() > 0 and coldStats.savedImport.pending,
    string.format("binds=%d rows=%d import=%s phase=%s",
        coldStats.dataBinds or 0,#ActiveBuildIds(),
        tostring(coldStats.savedImport and coldStats.savedImport.pending),
        tostring(coldStats.savedImport and coldStats.savedImport.pendingPhase)))
Expect("community_cold_diagnostic_snapshot_is_current_and_bounded",
    coldView.schema == 1 and coldView.view == "community"
        and coldView.catalogCount >= 45 and coldView.catalogCount <= 46
        and coldView.requestedPage == 1 and coldView.publishedPage == 1
        and coldView.pageCount == 3 and coldView.publishedRows == 20
        and coldView.filterSearchActive == false
        and coldView.projectionCurrent and not coldView.projectionPending
        and not coldView.projectionDirty and coldView.syncReceiving
        and coldView.lastPublicationAge >= 0
        and coldView.blockedReason == "none",
    string.format("catalog=%s page=%s/%s/%s rows=%s projection=%s/%s/%s receive=%s age=%s blocked=%s",
        tostring(coldView.catalogCount),tostring(coldView.requestedPage),
        tostring(coldView.publishedPage),tostring(coldView.pageCount),
        tostring(coldView.publishedRows),tostring(coldView.projectionCurrent),
        tostring(coldView.projectionPending),tostring(coldView.projectionDirty),
        tostring(coldView.syncReceiving),tostring(coldView.lastPublicationAge),
        tostring(coldView.blockedReason)))

-- Ending the receive window lets the independent personal import finish. The
-- public persisted rows must already be usable before this lane resumes.
receiving = false
for _ = 1, 160 do
    communityUpdate(communityFrame, 0.05)
    local stats = Community.VirtualStats()
    if not stats.savedImport.pending and not stats.refreshDirty
        and stats.results == 20 then break end
end
local pageOneIds = ActiveBuildIds()
assert(Community.VirtualStats().results == 20 and #pageOneIds > 0,
    "personal-import completion lost the persisted first page")
assert(NexusDB.buildFilters.futureFilter.keep and NexusDB.futureRoot.keep,
    "characterization replaced unknown SavedVariables fields")

-- Reopen a warm view during receive. Show starts another personal import; a
-- page click must still rebind directly from the retained public projection.
Community.Hide()
receiving = true
Community.Show()
local beforePageWork = Projections.WorkStats()
local beforePageProjection = Projections.Stats().builds
local beforePageImport = Community.VirtualStats().savedImport
local beforePageIds = ActiveBuildIds()
assert(SameIds(beforePageIds, pageOneIds),
    "warm reopen did not retain the known first page")
local nextPage = assert(communityFrame._nextPageBtn:GetScript("OnClick"))
nextPage(communityFrame._nextPageBtn)
local directPageRows, directPageSummary, directPageError =
    Projections.RequestBuilds(NexusDB.buildFilters)
assert(type(directPageRows) == "table"
    and directPageRows[1] and directPageRows[1].id == "stage30-public-21"
    and directPageSummary.page == 2,
    string.format("retained projection did not expose cached page two: rows=%s first=%s page=%s error=%s current=%s dirty=%s",
        tostring(type(directPageRows) == "table" and #directPageRows or nil),
        tostring(type(directPageRows) == "table" and directPageRows[1]
            and directPageRows[1].id),
        tostring(type(directPageSummary) == "table" and directPageSummary.page),
        tostring(directPageError),
        tostring(Projections.BuildsCurrent(NexusDB.buildFilters)),
        tostring(Community.VirtualStats().refreshDirty)))
local afterPageIds = ActiveBuildIds()
local pageView = Community.DiagnosticSnapshot()
local afterPageWork = Projections.WorkStats()
local afterPageProjection = Projections.Stats().builds
local afterPageImport = Community.VirtualStats().savedImport
local pageText = communityFrame._pageText:GetText()
Expect("community_cached_page_changes_actual_rows_during_receive",
    pageText == "2 / 3" and #afterPageIds > 0
        and afterPageIds[1] == "stage30-public-21"
        and not SameIds(afterPageIds, pageOneIds),
    string.format("label=%s rows_same=%s first=%s",
        tostring(pageText),tostring(SameIds(afterPageIds,pageOneIds)),
        tostring(afterPageIds[1]) .. " result="
            .. tostring(communityFrame._resultText:GetText())
            .. " binds=" .. tostring(Community.VirtualStats().dataBinds)))
Expect("personal_import_does_not_block_cached_page_slice",
    not (Community.VirtualStats().savedImport or {}).pending
        or not SameIds(afterPageIds, pageOneIds),
    "a pending personal mirror left page-one cards behind page-two controls")
Expect("community_cached_page_diagnostic_tracks_publication",
    pageView.requestedPage == 2 and pageView.publishedPage == 2
        and pageView.pageCount == 3 and pageView.publishedRows == 20
        and pageView.projectionCurrent and not pageView.projectionPending
        and not pageView.projectionDirty and pageView.syncReceiving
        and pageView.blockedReason == "none",
    string.format("page=%s/%s/%s rows=%s projection=%s/%s/%s receive=%s blocked=%s",
        tostring(pageView.requestedPage),tostring(pageView.publishedPage),
        tostring(pageView.pageCount),tostring(pageView.publishedRows),
        tostring(pageView.projectionCurrent),tostring(pageView.projectionPending),
        tostring(pageView.projectionDirty),tostring(pageView.syncReceiving),
        tostring(pageView.blockedReason)))
assert(afterPageWork.acquisitions == beforePageWork.acquisitions
    and afterPageWork.publications == beforePageWork.publications
    and afterPageProjection.rebuilds == beforePageProjection.rebuilds
    and afterPageProjection.sorts == beforePageProjection.sorts
    and afterPageImport.jobStarts == beforePageImport.jobStarts
    and afterPageImport.pumps == beforePageImport.pumps
    and afterPageImport.workUnits == beforePageImport.workUnits
    and afterPageImport.restarts == beforePageImport.restarts
    and afterPageImport.syncDeferrals == beforePageImport.syncDeferrals,
    "active receive page click performed projection or personal-import work")

-- Quiet lets the independent personal mirror finish without changing the
-- already-bound cached public page.
receiving = false
for _ = 1, 160 do
    communityUpdate(communityFrame, 0.05)
    local stats, ids = Community.VirtualStats(), ActiveBuildIds()
    if not stats.savedImport.pending and not stats.refreshDirty
        and ids[1] == "stage30-public-21" then break end
end
local pageTwoAfterWait = ActiveBuildIds()
assert(Community.VirtualStats().results == 20 and #pageTwoAfterWait > 0
    and pageTwoAfterWait[1] == "stage30-public-21"
    and not SameIds(pageTwoAfterWait, pageOneIds)
    and NexusDB.buildFilters.page == 2,
    string.format("personal-import completion lost cached page two: rows=%s ids=%d same=%s page=%s first=%s",
        tostring(Community.VirtualStats().results),#pageTwoAfterWait,
        tostring(SameIds(pageTwoAfterWait,pageOneIds)),
        tostring(NexusDB.buildFilters.page),tostring(pageTwoAfterWait[1])))

-- A represented-data revision during receive leaves the last-good page bound.
-- Diagnostics must identify Sync deferral, not the independent import lane.
receiving = true
Community.MarkDataDirty()
local deferredView = Community.DiagnosticSnapshot()
Expect("community_diagnostic_explains_receive_deferred_publication",
    deferredView.publishedPage == 2 and deferredView.publishedRows == 20
        and not deferredView.projectionCurrent
        and deferredView.projectionDirty and deferredView.syncReceiving
        and deferredView.blockedReason == "sync-receiving",
    string.format("published=%s rows=%s projection=%s/%s receive=%s blocked=%s",
        tostring(deferredView.publishedPage),tostring(deferredView.publishedRows),
        tostring(deferredView.projectionCurrent),
        tostring(deferredView.projectionDirty),
        tostring(deferredView.syncReceiving),
        tostring(deferredView.blockedReason)))
receiving = false
Community.Refresh()

-- If a normal view invalidation is missed, the existing eight-second safety
-- probe already learns that the represented-data key changed. Persist that
-- result for diagnostics without making diagnostic acquisition run the probe.
assert(Community.DiagnosticSnapshot().projectionCurrent,
    "fixture did not restore a current Community publication")
Nexus.Revisions.Advance(Nexus.Revisions.BUILD_LIBRARY_CHANGED,
    {reason="stage30-missed-view-notification"})
receiving = true
communityUpdate(communityFrame, 8.1)
local safetyProbeView = Community.DiagnosticSnapshot()
Expect("community_diagnostic_records_existing_safety_probe_result",
    not safetyProbeView.projectionCurrent
        and safetyProbeView.projectionDirty and safetyProbeView.syncReceiving
        and safetyProbeView.blockedReason == "sync-receiving",
    string.format("projection=%s/%s receive=%s blocked=%s",
        tostring(safetyProbeView.projectionCurrent),
        tostring(safetyProbeView.projectionDirty),
        tostring(safetyProbeView.syncReceiving),
        tostring(safetyProbeView.blockedReason)))

-- Leaderboard uses the real DpsCapture reader over rows that existed before
-- the receive window and observes zero incoming messages. Its cold projection
-- must publish while later receive-time revisions remain coalesced.
assert(#Nexus.DpsCapture.GetDpsBoard("dummy") == 4
    and #Nexus.DpsCapture.GetDpsBoard("lk") == 4,
    "fixture could not read its persisted DPS rows through DpsCapture")
Projections.Reset()
receiving = true
Nexus.Leaderboard.Init(Adapter)
Nexus.Leaderboard.Show("combined")
local leaderboardFrame = assert(NexusLeaderboardFrame,
    "Leaderboard frame was not assembled")
local leaderboardUpdate = assert(leaderboardFrame:GetScript("OnUpdate"),
    "Leaderboard update path was not installed")
for _ = 1, 80 do
    leaderboardUpdate(leaderboardFrame, 0.05)
    if Nexus.Leaderboard.VirtualStats().results == 4 then break end
end
local coldLeaderboard = Nexus.Leaderboard.VirtualStats()
local coldLeaderboardView = Nexus.Leaderboard.DiagnosticSnapshot()
Expect("leaderboard_cold_persisted_rows_publish_during_receive",
    coldLeaderboard.results == 4 and coldLeaderboard.dataBinds == 1,
    string.format("results=%d binds=%d receiving=%s",
        coldLeaderboard.results or 0,coldLeaderboard.dataBinds or 0,
        tostring(receiving)))
Expect("leaderboard_cold_diagnostic_snapshot_is_current_and_bounded",
    coldLeaderboardView.schema == 1
        and coldLeaderboardView.view == "leaderboard"
        and coldLeaderboardView.catalogCount >= 45
        and coldLeaderboardView.catalogCount <= 46
        and coldLeaderboardView.requestedPage == 1
        and coldLeaderboardView.publishedPage == 1
        and coldLeaderboardView.pageCount == 1
        and coldLeaderboardView.publishedRows == 4
        and coldLeaderboardView.filterCategory == "combined"
        and coldLeaderboardView.projectionCurrent
        and not coldLeaderboardView.projectionPending
        and not coldLeaderboardView.projectionDirty
        and coldLeaderboardView.syncReceiving
        and coldLeaderboardView.lastPublicationAge >= 0
        and coldLeaderboardView.blockedReason == "none",
    string.format("catalog=%s page=%s/%s/%s rows=%s category=%s projection=%s/%s/%s receive=%s age=%s blocked=%s",
        tostring(coldLeaderboardView.catalogCount),
        tostring(coldLeaderboardView.requestedPage),
        tostring(coldLeaderboardView.publishedPage),
        tostring(coldLeaderboardView.pageCount),
        tostring(coldLeaderboardView.publishedRows),
        tostring(coldLeaderboardView.filterCategory),
        tostring(coldLeaderboardView.projectionCurrent),
        tostring(coldLeaderboardView.projectionPending),
        tostring(coldLeaderboardView.projectionDirty),
        tostring(coldLeaderboardView.syncReceiving),
        tostring(coldLeaderboardView.lastPublicationAge),
        tostring(coldLeaderboardView.blockedReason)))
receiving = false
for _ = 1, 80 do
    leaderboardUpdate(leaderboardFrame, 0.05)
    if Nexus.Leaderboard.VirtualStats().results == 4 then break end
end
assert(Nexus.Leaderboard.VirtualStats().results == 4,
    "quiet transition did not retain persisted Leaderboard rows")
assert(receivedMessages == 0,
    "fixture relied on incoming records instead of persisted data")

if #failures > 0 then
    error("Stage 30 Community/Leaderboard regression ("
        .. #failures .. "):\n - " .. table.concat(failures, "\n - "))
end

print("Stage 30 Community startup, cached paging, and Leaderboard characterization -- OK")
