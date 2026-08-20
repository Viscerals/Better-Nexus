-- Freeze CommunityBuilds facade, retry, ownership, frame, popup, and navigation
-- behavior across the separated projection/controller/renderer owners.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/CommunityBuilds.lua")

UnitName = function() return "Owner" end
H.playerLevel = 80
H.wishlist = {name="Active Wishlist", class="MAGE", echoes={
    {spellId=200100, quality=3, stacks=1},
    {spellId=200104, quality=2, stacks=2},
}}
UISpecialFrames = {}
NexusDB = {
    settingsVersion=2, settings={}, chars={Owner={futureSafety={keep=true}}},
    communityBuilds={
        ["saved-owner-1"]={
            id="saved-owner-1", title="Server Mirror", serverTitle="Server Mirror",
            author="Owner", class="MAGE", isMine=true, importedSavedBuild=true,
            serverSlot=1, echoes={{spellId=200100, quality=3, stacks=1}},
            lockedEchoes={{spellId=200104, quality=2, stacks=1, locked=true}},
            postedAt=1, lastModified=1,
        },
        remote={id="remote", title="Remote", author="Other", class="MAGE",
            echoes={{spellId=200102, quality=2, stacks=1}}, postedAt=1, lastModified=1},
        pending={id="pending", title="Pending", author="Other", class="MAGE",
            loadoutAvailable=false, needsFullBuild=true, postedAt=1, lastModified=1},
    },
    futureRoot={keep=true},
}

local Store, Adapter = Nexus.Store, Nexus.GameAdapter
Store.Init()
Adapter.Init({}, Store)
H.DeliverSlots({
    [1]={slot=1, name="Server Mirror", verified=true,
        echoes={{spellId=200100, quality=3, stacks=1, locked=true}}},
    [6]={slot=6, name="Active Wishlist", verified=false,
        echoes=H.wishlist.echoes},
}, 1)

local broadcasts, deletes, loadoutRequests, syncRequests = {}, {}, {}, 0
local shareStatuses, retryCalls, retryBuildVersion, retryOptions = {}, 0
local retryMode = "queue"
local function CopyScalars(value)
    local copy = {}
    for key, field in pairs(type(value) == "table" and value or {}) do
        local kind = type(field)
        if kind == "string" or kind == "number" or kind == "boolean" then
            copy[key] = field
        end
    end
    return copy
end
Nexus.Sync = {
    BroadcastBuildSummary=function(build, options)
        broadcasts[#broadcasts + 1] = build.id
        if type(options) == "table" and options.retryOnFull == true then
            retryCalls = retryCalls + 1
            if retryMode == "throw" then
                error("fixture retry transport failure")
            end
            retryBuildVersion = tostring(tonumber(build.lastModified)
                or tonumber(build.postedAt) or 0)
            retryOptions = options
            local prior = shareStatuses[build.id]
            local status = {
                kind="share",id=build.id,version=retryBuildVersion,
                operationKey="share:" .. build.id,
                generation=(prior and prior.generation or 0) + 1,
                attempt=(prior and prior.attempt or 0) + 1,
                outcome="queued",terminal=false,queueAdmitted=true,
                retryPending=false,accepted=false,
                confirmation="unavailable",
            }
            shareStatuses[build.id] = status
            return true, "queued", CopyScalars(status)
        end
        return true
    end,
    GetShareStatus=function(id)
        return CopyScalars(shareStatuses[id])
    end,
    BroadcastDelete=function(build)
        deletes[#deletes + 1] = build.id
        return true
    end,
    RequestLoadout=function(id)
        loadoutRequests[#loadoutRequests + 1] = id
        return true
    end,
    RequestSync=function() syncRequests = syncRequests + 1 return true end,
    IsReceiving=function() return false end,
    ReceiveTimeLeft=function() return 0 end,
    LastSyncNewCount=function() return 0 end,
    Stats=function() return {received=0} end,
}
local leaderboardMode
Nexus.Leaderboard = {Show=function(mode) leaderboardMode = mode end}
Nexus.Panel = {
    AttachMenuFrame=function() end,
    CloseOtherWindows=function() end,
}

local CB = Nexus.CommunityBuilds
CB.Init(Adapter, Nexus.Model)
for _, name in ipairs({
    "IsOwnBuild", "EnsureDpsBuildForEchoes", "PostCurrentWishlist",
    "ShareStatus", "CanRetryShare", "RetryShare",
    "PublishImportedBuild", "EditBuild", "UpdateFromWishlist", "DeleteBuild",
    "_PumpPendingLockIn", "IsLockInPending", "LockInSelected",
    "GetSelectedBuildForPanel", "GetSelectedBuildForPanelKey", "VirtualStats",
    "MarkDataDirty", "ScrollTo", "Refresh", "ShowPostBuild",
    "TogglePostPopup", "ToggleEditPopup", "Init", "Select", "SetViewMode",
    "GetViewMode", "Show", "ShowBuild", "Hide", "IsShown", "Toggle",
}) do
    assert(type(CB[name]) == "function", "Community facade lost " .. name)
end

-- Publishing a local Saved Build mirror uses one stable public identity,
-- preserves locked Echo intent, and broadcasts only the admitted record.
local ok, publishedId = CB.PublishImportedBuild("saved-owner-1")
assert(ok and publishedId == "published-saved-owner-1",
    "saved-loadout publication identity changed")
local published = Nexus.BuildCatalog.Get(publishedId)
assert(published and published.sourceSavedBuildId == "saved-owner-1"
    and published.echoes[1].locked ~= true
    and published.lockedEchoes[1].locked == true
    and broadcasts[1] == publishedId,
    "published mirror lost provenance, lock intent, or admission ordering")
local okAgain, sameId = CB.PublishImportedBuild("saved-owner-1")
assert(okAgain and sameId == publishedId
    and Nexus.BuildCatalog.Get("saved-owner-1").publishedBuildId == publishedId,
    "re-publishing a mirror created a second public identity")
published = Nexus.BuildCatalog.Get(publishedId)
assert(not CB.PublishImportedBuild("remote"),
    "non-owned/non-mirror build passed imported publication validation")

-- Public frames retain their established names and toggle behavior.
CB.Show()
assert(CB.IsShown() and H.frames.NexusCommunityBuildsFrame
    and H.frames.NexusCommunityBuildsFrame:IsShown(),
    "Community main frame name/show contract changed")
assert(UISpecialFrames[1] == "NexusCommunityBuildsFrame",
    "Community escape-close frame registration changed")

-- The explicit terminal retry is a dedicated owned-build action. Passive
-- reads never resend, the click preserves exact ID/version, and an immediate
-- second invocation cannot fall through to Copy/Upload or duplicate work.
local failedVersion = tostring(published.lastModified)
shareStatuses[publishedId] = {
    kind="share",id=publishedId,version=failedVersion,
    operationKey="share:" .. publishedId,generation=1,attempt=1,
    outcome="expired",terminal=true,queueAdmitted=true,
    accepted=false,confirmation="unavailable",
}
local retryCallsBefore = retryCalls
assert(CB.CanRetryShare(publishedId) == true
        and retryCalls == retryCallsBefore,
    "passive terminal Share eligibility triggered a resend")
CB.Select(publishedId)
local detail = assert(H.frames.NexusCommunityBuildsFrame._detailPanel)
local retryButton = assert(detail.retryShareBtn)
local retryPoint, retryRelative, retryRelativePoint, retryX, retryY =
    retryButton:GetPoint()
local lockPoint, lockRelative, lockRelativePoint, lockX, lockY =
    detail.lockBtn:GetPoint()
assert(retryButton:IsShown() and not detail.lockBtn:IsShown()
        and detail.editBtn:IsShown()
        and retryCalls == retryCallsBefore
        and retryButton:GetWidth() == detail.lockBtn:GetWidth()
        and retryPoint == lockPoint and retryRelative == lockRelative
        and retryRelativePoint == lockRelativePoint
        and retryX == lockX and retryY == lockY,
    "exact terminal owned Share did not expose its dedicated Retry action")
local retryClick = assert(retryButton:GetScript("OnClick"))
retryClick(retryButton)
assert(retryCalls == retryCallsBefore + 1
    and retryBuildVersion == failedVersion
    and retryOptions.retryOnFull == true
    and shareStatuses[publishedId].outcome == "queued"
    and retryButton:IsShown() and not retryButton:IsEnabled()
    and not detail.lockBtn:IsShown() and detail.editBtn:IsShown(),
    "Retry Share changed identity/version or swapped controls after its click")
retryClick(retryButton)
assert(retryCalls == retryCallsBefore + 1,
    "repeated active Retry Share duplicated work or fell through")
CB.Refresh()
assert(not retryButton:IsShown() and detail.lockBtn:IsShown()
        and detail.editBtn:IsShown(),
    "deliberate refresh did not replace the completed retry intention")
shareStatuses[publishedId] = {
    kind="share",id=publishedId,version=failedVersion,
    operationKey="share:" .. publishedId,generation=3,attempt=2,
    outcome="sent-attempted",terminal=true,accepted=false,
}
CB.Refresh()
assert(not retryButton:IsShown(),
    "successful sent-attempted Share exposed a retry action")
shareStatuses[publishedId] = {
    kind="share",id=publishedId,version="stale",
    operationKey="share:" .. publishedId,generation=4,attempt=3,
    outcome="dropped",terminal=true,accepted=false,
}
CB.Refresh()
assert(not retryButton:IsShown(),
    "stale-version terminal Share exposed a retry action")
shareStatuses.remote = {
    kind="share",id="remote",version="1",operationKey="share:remote",
    generation=5,attempt=1,outcome="expired",terminal=true,
}
CB.Select("remote")
assert(not retryButton:IsShown(),
    "non-owner terminal Share exposed a retry action")
shareStatuses[publishedId] = {
    kind="share",id=publishedId,version=failedVersion,
    operationKey="share:" .. publishedId,generation=6,attempt=4,
    outcome="dropped",terminal=true,accepted=false,
}
retryMode = "throw"
CB.Select(publishedId)
local failedRetryCalls = retryCalls
local failedGeneration = shareStatuses[publishedId].generation
retryClick(retryButton)
assert(retryCalls == failedRetryCalls + 1
        and shareStatuses[publishedId].generation == failedGeneration
        and retryButton:IsShown() and retryButton:IsEnabled(),
    "transport exception permanently consumed the explicit Retry action")
retryMode = "queue"
retryClick(retryButton)
assert(retryCalls == failedRetryCalls + 2
        and shareStatuses[publishedId].outcome == "queued",
    "recovered explicit Retry action did not admit exactly once")
shareStatuses[publishedId] = {
    kind="share",id=publishedId,version=failedVersion,
    operationKey="share:" .. publishedId,generation=8,attempt=5,
    outcome="dropped",terminal=true,accepted=false,
}
local facadeRetryBefore = retryCalls
local facadeRetried, _, facadeReceipt = CB.RetryShare(publishedId)
assert(facadeRetried and retryCalls == facadeRetryBefore + 1
        and facadeReceipt.id == publishedId
        and facadeReceipt.version == failedVersion,
    "Community facade did not delegate the exact explicit retry intention")
CB.ShowPostBuild()
assert(H.frames.NexusPostPopup and H.frames.NexusPostPopup:IsShown(),
    "post controller did not create/show NexusPostPopup")
CB.TogglePostPopup()
assert(not H.frames.NexusPostPopup:IsShown(),
    "post popup toggle did not hide the established frame")
CB.ToggleEditPopup(publishedId)
assert(H.frames.NexusEditPopup and H.frames.NexusEditPopup:IsShown()
    and H.frames.NexusEditPopup._editingId == publishedId,
    "owned edit controller did not bind NexusEditPopup")
CB.ToggleEditPopup(publishedId)
assert(not H.frames.NexusEditPopup:IsShown(), "edit popup toggle did not hide")
CB.ToggleEditPopup("remote")
assert(not H.frames.NexusEditPopup:IsShown(),
    "non-owner edit controller exposed an editable popup")
for _, name in ipairs({
    "NexusCommunityBuildsFrame", "NexusBuildDropdownShield",
    "NexusBuildsSearch", "NexusClassDropPanel", "NexusBuildSortPanel",
    "NexusPostPopup", "NexusEditPopup",
}) do
    assert(H.frames[name], "Community named frame lost: " .. name)
end

-- Compatibility navigation preserves the Builds facade while routing DPS
-- modes to Leaderboard and exact missing loadouts to Sync once per request.
assert(CB.GetViewMode() == "builds", "Community compatibility view changed")
CB.SetViewMode("dummy")
assert(leaderboardMode == "dummy" and not CB.IsShown(),
    "dummy compatibility route did not hand off to Leaderboard")
CB.ShowBuild("pending")
assert(CB.IsShown() and loadoutRequests[#loadoutRequests] == "pending",
    "ShowBuild did not request the selected incomplete loadout")
local selected = CB.GetSelectedBuildForPanel()
assert(selected and selected.id == "pending",
    "offscreen/incomplete stable-ID selection was not projected to Panel")
local selectedKey, selectedEpoch, selectedRevision =
    CB.GetSelectedBuildForPanelKey()
assert(selectedKey == "pending" and type(selectedEpoch) == "number"
    and type(selectedRevision) == "number",
    "visible selected Panel key lost its scalar revision contract")
CB.Hide()
assert(CB.GetSelectedBuildForPanel() == nil
    and CB.GetSelectedBuildForPanelKey() == nil,
    "hidden Community frame leaked its selected Panel projection")

-- Lock-in retries preserve the selected payload and clear on success. The
-- approved Stage 14.2 repair counts spacing responses against one bounded
-- pending record instead of recreating its retry lifetime.
CB.ShowBuild(publishedId)
local uploadCalls, alwaysSpacing = 0, false
Adapter.UploadWishlist = function(slot, title, echoes)
    uploadCalls = uploadCalls + 1
    assert(slot == 0 and title == published.title and #echoes == #published.echoes,
        "lock-in retry changed the selected payload")
    if alwaysSpacing or uploadCalls == 1 then return false, "spacing" end
    return true
end
CB.LockInSelected()
assert(H.lastStaticPopup and H.lastStaticPopup.which == "NEXUS_LOCKIN_BUILD",
    "lock-in skipped confirmation")
H.AcceptLastStaticPopup()
assert(CB.IsLockInPending(), "spacing did not retain pending lock-in")
CB._PumpPendingLockIn()
assert(not CB.IsLockInPending() and uploadCalls == 2,
    "pending lock-in did not resume exactly once after capacity returned")

alwaysSpacing, uploadCalls = true, 0
CB.LockInSelected()
H.AcceptLastStaticPopup()
for _ = 1, 13 do CB._PumpPendingLockIn() end
assert(not CB.IsLockInPending() and uploadCalls == 13,
    "bounded repeated-spacing expiry changed: pending="
        .. tostring(CB.IsLockInPending()) .. " calls=" .. tostring(uploadCalls))
alwaysSpacing = false
CB._PumpPendingLockIn()
assert(not CB.IsLockInPending() and uploadCalls == 13,
    "expired lock-in performed an extra retry upload")

local stats = CB.VirtualStats()
stats.created = -1
assert(CB.VirtualStats().created ~= -1 and NexusDB.futureRoot.keep
    and Store.State().futureSafety.keep,
    "Community diagnostics or rendering leaked state ownership")

print("Community facade, frames, ownership, navigation, publication, and retry parity -- OK")
