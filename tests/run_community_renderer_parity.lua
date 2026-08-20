-- Renderer extraction parity: stable facade/frame identity, bounded pooled rows,
-- and one-way presentation boundaries at a 1,000-build fixture.
local H = dofile("tests/harness.lua")
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
Nexus.Store.Init()
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
for _, build in pairs(Nexus.BuildCatalog.Summaries()) do
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
