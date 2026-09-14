-- Renderer extraction parity: stable facade/frame identity, bounded pooled rows,
-- and one-way presentation boundaries at a 1,000-build fixture.
local H = dofile("tests/harness.lua")
local S = dofile("tests/catalog_authority_support.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

UnitName = function() return "RendererMage" end
GetNormalizedRealmName = function() return "Ebonhold" end
NexusDB = {
    settingsVersion=2, settings={}, chars={}, dpsCapture={},
    buildFilters={sortMode="title"}, communityBuilds={},
    futureRoot={keep=true},
}
for index = 1, 1000 do
    local id = string.format("renderer-%04d", index)
    NexusDB.communityBuilds[id] = {
        id=id, title=string.format("Build %04d", index), author="Peer",
        ownerKey="peer@ebonhold", class="MAGE",
        postedAt=index, lastModified=index,
        fingerprint=tostring(720000+index).."x1",
        echoes={{spellId=720000 + index, quality=3, stacks=1}},
    }
end
NexusDB.communityBuilds["renderer-0500"].link =
    "https://example.invalid/|Hitem:1|hspoof|h"
-- Admitted durable evidence whose bytes are unsafe to display: the record is
-- represented, but the renderer must refuse to show its link.
NexusDB.communityBuilds["renderer-0501"].link =
    "https://example.invalid/" .. string.char(1) .. "control"
H.BootstrapStoreReady()
local eligibility = {}
Nexus.DpsCapture = {
    GetCommunityEligibility=function()
        return eligibility
    end,
    GetLeaderboard=function() return {} end,
    GetLeaderboardForEchoes=function() return {} end,
    GetPersonalBest=function() return nil end,
    GetDpsBoard=function() return {} end,
    IsDetailsAvailable=function() return false end,
}
local syncRequests = 0
Nexus.Sync = {
    IsReceiving=function() return false end,
    ReceiveTimeLeft=function() return 0 end,
    LastSyncNewCount=function() return 0 end,
    Stats=function() return {received=0} end,
    RequestSync=function()
        syncRequests = syncRequests + 1
        return true
    end,
}

dofile("ui/CommunityBuilds.lua")
local C = Nexus.CommunityBuilds
C.Init(nil, nil)
for _, build in pairs(H.CatalogSummaries()) do
    local index = tonumber(tostring(build.id):match("(%d+)$")) or 0
    eligibility[build.fingerprint] = {
        dummy=index,lk=index+1,best=index+1,average=index+0.5,count=2,
    }
end
local exactReads = 0
local originalGet = Nexus.BuildCatalog.Get
Nexus.BuildCatalog.Get = function(...)
    exactReads = exactReads + 1
    return originalGet(...)
end
C.Show()
-- MASTER-W2-006: the Community list is a retained projection job pumped one
-- bounded slice per real frame; drive the frame until it publishes.
S.PumpCommunityFrame(H.frames.NexusCommunityBuildsFrame,
    function() return C.VirtualStats().results > 0 end, "Community list")

assert(H.frames.NexusCommunityBuildsFrame
    and H.frames.NexusCommunityBuildsFrame:IsShown(),
    "renderer changed the established main frame identity")
local syncClick = H.frames.NexusCommunityBuildsFrame._syncBtn:GetScript("OnClick")
assert(type(syncClick) == "function", "Sync Now lost its click binding")
syncClick()
assert(syncRequests == 1,
    "Sync Now did not route exactly once through the controller intention")
local first = C.VirtualStats()
assert(first.results == 20 and first.active <= 7
    and first.created == first.active
    and exactReads == first.active,
    string.format("renderer result/pool mismatch: results=%s active=%s created=%s",
        tostring(first.results),tostring(first.active),tostring(first.created)))
local created = first.created
assert(C.ScrollTo(10 * 92), "renderer rejected a valid virtual offset")
local middle = C.VirtualStats()
assert(middle.first <= 11 and middle.last >= 11
    and middle.created <= 9 and middle.created >= created,
    "renderer did not bind a bounded middle window")
assert(C.ScrollTo(math.huge), "renderer rejected the ending offset")
local ending = C.VirtualStats()
assert(ending.last == 20 and ending.created == middle.created,
    "renderer did not reuse its visible-row pool")

C.Select("renderer-0500")
assert(C.GetSelectedBuildForPanel().id == "renderer-0500",
    "renderer lost exact stable-ID detail selection")
local linkBox = H.frames.NexusCommunityBuildsFrame._detailPanel.linkBox
local safeLink = "https://example.invalid/||Hitem:1||hspoof||h"
assert(linkBox:GetText() == safeLink
    and linkBox:_NexusRawText()
        == "https://example.invalid/|Hitem:1|hspoof|h",
    "remote build link did not retain raw bytes behind an inert EditBox")
linkBox:GetScript("OnMouseUp")(linkBox)
assert(linkBox:GetText() == safeLink,
    "focusing the remote build link restored unsafe rich text")
C.Select("renderer-0501")
assert(linkBox:GetText() == "" and linkBox:_NexusRawText() == "",
    "invalid legacy link inherited the previously selected record's value")
C.Select("renderer-0500")
local selectedKey, selectedEpoch, selectedRevision =
    C.GetSelectedBuildForPanelKey()
assert(selectedKey == "renderer-0500" and type(selectedEpoch) == "number"
    and type(selectedRevision) == "number",
    "renderer lost the visible scalar selection key")
C.Hide()
assert(not C.IsShown() and C.GetSelectedBuildForPanel() == nil
    and C.GetSelectedBuildForPanelKey() == nil,
    "hidden renderer leaked its Panel detail projection")
assert(NexusDB.futureRoot.keep,
    "renderer/facade damaged an unknown SavedVariables field")

local function Read(path)
    local handle = assert(io.open(path, "rb"))
    local source = handle:read("*a")
    handle:close()
    return source
end

local renderer = Read("ui/CommunityRenderer.lua")
for _, forbidden in ipairs({
    "NexusDB", "BuildCatalog", "BroadcastBuild", "BroadcastDelete",
    "UploadWishlist", "SetTombstone", "ProjectEbonhold",
}) do
    assert(not renderer:find(forbidden, 1, true),
        "renderer owns forbidden persistence/transport/gameplay path: "
            .. forbidden)
end
assert(not renderer:find("BuildDpsSummary", 1, true),
    "renderer retained a per-build DPS lookup fallback")
local facade = Read("ui/CommunityBuilds.lua")
for _, moved in ipairs({
    "local function EnsureFrame", "local function EnsureDetailPanel",
    "local function GetCard", "local function ReleaseCard",
    "renderBuildWindow",
}) do
    assert(not facade:find(moved, 1, true),
        "facade retained renderer implementation: " .. moved)
end
local controller = Read("core/CommunityController.lua")
assert(not controller:find("CreateFrame", 1, true),
    "Community controller gained frame ownership")

print(string.format(
    "community renderer: results=%d created=%d active<=%d stable frames/boundaries -- OK",
    first.results, ending.created, ending.peakActive))

-- Shipped manual entry points must retain intent while the real hash owner is
-- cold. Neither a slash command nor repeated Sync Now clicks may format nil.
local manualRows = {}
for index = 1, 9 do
    local id = "manual-sync-" .. index
    manualRows[id] = S.LocalBuild(id, 1)
end
NexusDB = S.Database(manualRows)
dofile("core/Codec.lua")
dofile("core/BuildHashCache.lua")
for _, module in ipairs({"SyncProtocol", "SyncTransport", "SyncCompatibility",
        "SyncReconciler", "SyncInbound", "SyncDiagnostics", "SyncSession", "Sync"}) do
    dofile("core/" .. module .. ".lua")
end
local realSync = Nexus.Sync
H.AdmitCatalogV1(NexusDB)
realSync.Init(Nexus.Codec, {})
local coldHash = realSync.GetCompatibilityHashes()
assert(coldHash == nil, "manual readiness fixture did not start with a cold hash")
local clickOk, clickWhy = pcall(syncClick)
assert(clickOk, "real Sync Now formatted an unready hash: " .. tostring(clickWhy))
assert(realSync.Stats().preparingRequest == true,
    "cold manual Sync did not expose truthful preparation")
syncClick()
syncClick()
assert(realSync.Stats().preparingRequest == true,
    "repeated Sync Now clicks did not retain one preparing intent")
H.sentChatMessages = {}
for _ = 1, 20000 do
    Nexus.BuildHashCache.Pump()
    realSync.OnUpdate(0.2)
    if realSync.Stats().queueOutcome == "sent" then break end
end
local manualRequests = 0
for _, message in ipairs(H.sentChatMessages) do
    local wire = message.text:gsub("||", "|")
    if wire:find("^WLRQ|") then
        manualRequests = manualRequests + 1
        assert(not wire:find("|nil|", 1, true), "manual request sent a nil hash")
    end
end
assert(manualRequests == 1, "pending manual Sync did not send exactly once")
print("real Sync Now cold-hash readiness -- OK")

-- A changed generation must replace queued request bytes, not send the old
-- digest. The mutation is real and all request traffic uses real transport.
realSync.Init(Nexus.Codec, {})
S.CompatibilityHashes(realSync)
assert(realSync.RequestSync() == true, "warm manual request was not queued")
local changed = Nexus.BuildCatalog.Get("manual-sync-1")
changed.lastModified = changed.lastModified + 1
changed.title = "New manual Sync generation"
assert(S.CatalogMutation(function() return Nexus.BuildCatalog.Put(changed) end,
    "manual Sync generation replacement"))
H.sentChatMessages = {}
for _ = 1, 20000 do
    Nexus.BuildHashCache.Pump()
    realSync.OnUpdate(0.2)
    if realSync.Stats().queueOutcome == "sent" then break end
end
local expectedHash = realSync.GetCompatibilityHashes()
local replacementRequests = 0
for _, message in ipairs(H.sentChatMessages) do
    local wire = message.text:gsub("||", "|")
    if wire:find("^WLRQ|") then
        replacementRequests = replacementRequests + 1
        assert(wire:match("^WLRQ|[^|]+|([^|]+)|") == expectedHash,
            "manual Sync sent the superseded generation hash")
    end
end
assert(replacementRequests == 1, "generation replacement duplicated manual request")

for _, cancelKind in ipairs({"disconnect", "reset"}) do
    dofile("core/BuildHashCache.lua")
    realSync.Init(Nexus.Codec, {})
    local queued, why = realSync.RequestSync()
    assert(queued == nil and why == "preparing sync data", "cancellation fixture not pending")
    H.sentChatMessages = {}
    if cancelKind == "disconnect" then H.joinedChannels = {}
    else realSync.Init(Nexus.Codec, {}) end
    realSync.OnUpdate(0.2)
    assert(not realSync.Stats().preparingRequest,
        cancelKind .. " retained an unintended delayed Sync action")
    assert(#H.sentChatMessages == 0, cancelKind .. " sent a cancelled request")
end
print("manual Sync generation, disconnect and reset -- OK")

-- Real upload button: a saved mirror publishes as one retained transaction.
local savedId = "renderer-saved-upload"
assert(S.CatalogMutation(function()
    return Nexus.BuildCatalog.Put(S.LocalBuild(savedId, 1, {
        title="Saved UI Build",serverTitle="Saved UI Build",author="RendererMage",
        ownerKey="renderermage@ebonhold",realm="ebonhold",ownerVerified=true,
        isMine=true,importedSavedBuild=true,serverSlot=1,class="MAGE"}))
end, "renderer saved upload fixture"))
C.ShowBuild(savedId)
local uploadFrame = H.frames.NexusCommunityBuildsFrame
S.PumpCommunityFrame(uploadFrame, function()
    return uploadFrame._detailPanel:IsShown()
        and uploadFrame._detailPanel.lockBtn:GetText() == "Upload Build"
end, "saved upload detail")
local uploadButton = uploadFrame._detailPanel.lockBtn
local uploadClick = uploadButton:GetScript("OnClick")
local uploadNotices, uploadPrint = {}, print
local uploadBroadcasts, originalBroadcast = 0, realSync.BroadcastBuildSummary
realSync.BroadcastBuildSummary = function(...)
    uploadBroadcasts = uploadBroadcasts + 1
    return originalBroadcast(...)
end
print = function(text) uploadNotices[#uploadNotices + 1] = tostring(text) end
uploadClick()
print = uploadPrint
assert(Nexus.BuildCatalog.RootState().candidate == true,
    "real upload button did not enter pending publication")
assert(#uploadNotices == 1 and not uploadNotices[1]:find("|cffff6060", 1, true)
        and uploadButton:GetText() == "Uploading...",
    "real upload button reported pending publication as a failure")
uploadClick()
C.Hide()
C.ShowBuild(savedId)
assert(uploadButton:GetText() == "Uploading...",
    "reopening the same saved build lost its pending operation")
C.Hide()
C.ShowBuild("manual-sync-2")
print = function(text) uploadNotices[#uploadNotices + 1] = tostring(text) end
S.PumpCatalogToIdle("real upload button transaction")
print = uploadPrint
local uploadedId = Nexus.BuildCatalog.Get(savedId).publishedBuildId
assert(uploadedId and Nexus.BuildCatalog.Get(uploadedId),
    "pending upload did not publish the exact saved build")
local terminalNotices = 0
for _, text in ipairs(uploadNotices) do
    if text:find("uploaded", 1, true) then
        terminalNotices = terminalNotices + 1
        assert(text:find("Saved UI Build", 1, true),
            "completion was attributed to the newly selected build")
    end
end
assert(terminalNotices == 1, "pending upload did not report exactly one completion")
assert(uploadBroadcasts == 1, "pending upload did not broadcast exactly once")
assert(C.GetSelectedBuildForPanel().id == "manual-sync-2", "upload completion changed current selection")
print("real upload button retains exact transaction and completion -- OK")

-- Cancel an actual pending publication by replacing its source identity.
-- The callback must report one failure and must never broadcast that attempt.
C.ShowBuild(savedId)
S.PumpCommunityFrame(uploadFrame, function()
    return uploadButton:GetText() ~= "Uploading..."
end, "completed saved upload detail")
uploadNotices = {}
print = function(text) uploadNotices[#uploadNotices + 1] = tostring(text) end
uploadClick()
local failedSource = NexusDB.authorityBundle
assert(Nexus.BuildCatalog.RootState().candidate,
    "failure fixture did not begin a real publication")
NexusDB.authorityBundle = H.CloneValue(failedSource)
S.PumpCatalogToIdle("source-drift upload failure")
print = uploadPrint
local failedNotices = 0
for _, text in ipairs(uploadNotices) do
    if text:find("|cffff6060", 1, true) then failedNotices = failedNotices + 1 end
end
assert(failedNotices == 1 and uploadBroadcasts == 1,
    "failed upload did not report once or broadcast an uncommitted build")
assert(NexusDB.authorityBundle.communityBuilds[savedId].publishedBuildId == uploadedId,
    "failed upload changed the prior publication identity")
H.AdmitCatalogV1(NexusDB)

-- The same actual button must still report an immediate ownership refusal.
C.ShowBuild(savedId)
S.PumpCommunityFrame(uploadFrame, function()
    return uploadButton:GetText() ~= "Uploading..."
end, "refused upload detail")
local originalName = UnitName
UnitName = function() return "NotTheOwner" end
uploadNotices = {}
print = function(text) uploadNotices[#uploadNotices + 1] = tostring(text) end
uploadClick()
print, UnitName = uploadPrint, originalName
assert(#uploadNotices == 1 and uploadNotices[1]:find("|cffff6060", 1, true)
        and uploadBroadcasts == 1 and not Nexus.BuildCatalog.RootState().candidate,
    "synchronous upload refusal was not truthful and side-effect free")
realSync.BroadcastBuildSummary = originalBroadcast
print("real upload failure and synchronous refusal -- OK")
