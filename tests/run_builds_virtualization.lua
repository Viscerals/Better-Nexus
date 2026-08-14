-- Community Builds fixed-height virtualization at live-library scale.
local H = dofile("tests/harness.lua")
dofile("ui/Theme.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

local V = Nexus.VirtualList
local Store = Nexus.Store
local top = V.Window(1000, 92, 458, 0, 2)
local middle = V.Window(1000, 92, 458, 500*92, 2)
local ending = V.Window(1000, 92, 458, math.huge, 2)
local tiny = V.Window(1000, 92, 0, 0, 2)
assert(top.first == 1 and top.last <= 7 and top.active <= 7,
    "top virtual window was not viewport bounded")
assert(middle.first <= 501 and middle.last >= 501 and middle.active <= 9,
    "middle virtual window did not cover the requested row")
assert(ending.last == 1000 and ending.offset == ending.maxOffset,
    "end virtual window did not clamp to the final row")
assert(tiny.active <= 3 and V.Window(0,92,458,99,2).active == 0,
    "tiny or empty virtual window was not bounded")
for index = 1, 1000 do
    local window = V.Window(1000, 92, 458, (index-1)*92, 2)
    assert(window.firstVisible <= index and window.lastVisible >= index
        and window.active <= 9,
        "virtual window could not reach an exact row offset: "..index)
end

UnitName = function() return "VirtualMage" end
GetNormalizedRealmName = function() return "Ebonhold" end
NexusDB = {communityBuilds={},buildFilters={sortMode="title"},dpsCapture={}}
for index = 1, 1000 do
    local id = string.format("virtual-%04d", index)
    NexusDB.communityBuilds[id] = {
        id=id, title=string.format("Build %04d", index), author="Peer",
        ownerKey="peer@ebonhold", class="MAGE",
        postedAt=index, lastModified=index,
        echoes={{spellId=710000+index,quality=3,stacks=1}},
    }
end
local Retention = Nexus.DataRetention
Nexus.DataRetention = nil
Store.Init()
Nexus.DataRetention = Retention
local detailBoardReads, detailIdentityReads = 0, 0
Nexus.DpsCapture = {
    GetLeaderboard=function() return {} end,
    GetLeaderboardForEchoes=function() return {} end,
    GetPersonalBest=function() return nil end,
    GetDpsBoard=function() detailBoardReads=detailBoardReads+1; return {} end,
    GetBestRecordForIdentity=function(buildId, _, _, category)
        detailIdentityReads=detailIdentityReads+1
        if buildId=="virtual-0010" and category=="dummy" then
            return {lockedEchoes={{spellId=710010,stacks=1}}}
        end
        return nil
    end,
    IsDetailsAvailable=function() return false end,
}
dofile("ui/CommunityBuilds.lua")
local C = Nexus.CommunityBuilds
C.Init(nil,nil)
C.Show()
local initial = C.VirtualStats()
assert(initial.results == 20 and initial.active <= 5
    and initial.created == initial.active and initial.first == 1,
    "Community Builds did not enforce its emergency result limit")

local dataBinds = initial.dataBinds
local virtualScroll = NexusCommunityBuildsFrame._virtualListScrollFrame
local onSizeChanged = virtualScroll and virtualScroll:GetScript("OnSizeChanged")
assert(type(onSizeChanged) == "function", "viewport resize did not install a virtual rebind")
virtualScroll:SetHeight(276)
onSizeChanged(virtualScroll, 460, 276)
local resized = C.VirtualStats()
assert(resized.active == 5 and resized.resizeBinds == 1
    and resized.dataBinds == dataBinds,
    "viewport growth did not rebind only the bounded visible window")
virtualScroll:SetHeight(100)
onSizeChanged(virtualScroll, 460, 100)
assert(C.VirtualStats().active <= 4 and C.VirtualStats().resizeBinds == 2,
    "viewport shrink did not clamp the bounded visible window")
assert(C.ScrollTo(10*92))
local mid = C.VirtualStats()
assert(mid.first <= 11 and mid.last >= 11
    and mid.active <= 7 and mid.created <= 7
    and mid.dataBinds == dataBinds and mid.scrollBinds == 1,
    "scroll movement rebuilt projection or allocated unbounded cards")
local created = mid.created
C.ScrollTo(math.huge)
local last = C.VirtualStats()
assert(last.last == 20 and last.created == created,
    "final Community Builds row was not reachable with fixed card pool")

C.Select("virtual-0010")
local offscreen = C.VirtualStats()
assert(offscreen.selectedId == "virtual-0010" and not offscreen.selectedVisible
    and C.GetSelectedBuildForPanel().id == "virtual-0010",
    "offscreen selection lost exact detail identity")
assert(detailBoardReads==0 and detailIdentityReads==1,
    "selected build detail scanned a full DPS board instead of its indexed identity")
C.ScrollTo((10-1)*92)
assert(C.VirtualStats().selectedVisible,
    "returning selected card onscreen did not restore its highlight identity")

-- A bad row may abort a render, but the checked-out card must be reclaimed so
-- a corrected data revision can retry without growing or retaining stale UI.
C.ScrollTo(0)
local original = Nexus.BuildCatalog.Get("virtual-0001")
local broken = {}
for key, value in pairs(original) do broken[key] = value end
broken.author = {}
assert(Nexus.BuildCatalog.Put(broken))
local beforeFailure = C.VirtualStats().created
local badOk = pcall(C.Refresh)
assert(not badOk and C.VirtualStats().active == 0
    and C.VirtualStats().created == beforeFailure,
    "failed row binding leaked or retained a checked-out card")
broken.author = "Peer"
assert(Nexus.BuildCatalog.Put(broken))
C.Refresh()
local recovered = C.VirtualStats()
assert(recovered.active <= 4 and recovered.created == beforeFailure,
    "corrected data could not reuse the reclaimed card pool")

NexusDB.buildFilters.search = "Build 0005"
C.Refresh()
local shrunk = C.VirtualStats()
assert(shrunk.results == 1 and shrunk.active == 1
    and shrunk.offset == 0 and shrunk.first == 1 and shrunk.last == 1,
    "filter shrink did not clamp scroll or remove stale cards")
NexusDB.buildFilters.search = "no-such-build"
C.Refresh()
local empty = C.VirtualStats()
assert(empty.results == 0 and empty.active == 0 and empty.offset == 0,
    "empty virtualized build result retained stale cards")
local themeStats = Nexus.Theme.Stats()
assert(themeStats.virtualRows == created,
    "Community virtual cards did not receive one-shot theme styling")

print(string.format(
    "build virtualization: results=%d active<=%d created=%d scrollBinds=%d -- OK",
    initial.results, C.VirtualStats().peakActive, created,
    C.VirtualStats().scrollBinds))
