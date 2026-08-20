-- Leaderboard virtualization and status-only refresh separation at scale.
local H=dofile("tests/harness.lua")

NexusDB={communityBuilds={},buildFilters={},dpsCapture={}}
local function EchoKey(echoes)
    local counts, ids = {}, {}
    for _, echo in ipairs(echoes) do
        local id = assert(tonumber(echo.spellId))
        counts[id] = (counts[id] or 0)
            + (tonumber(echo.stacks or echo.count) or 1)
    end
    for id in pairs(counts) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        parts[#parts + 1] = tostring(id).."x"..tostring(counts[id])
    end
    return table.concat(parts, ",")
end
local boards={dummy={},lk={}}
for index=1,150 do
    local player=string.format("Player%03d",index)
    local buildId=string.format("ranked-%03d",index)
    local class=index%2==0 and "MAGE" or "ROGUE"
    local echoes={{spellId=720000+index,stacks=2},{spellId=730000+index,stacks=1}}
    local fingerprint=EchoKey(echoes)
    local locked=index==80 and {{spellId=740080,stacks=1}} or nil
    local build={id=buildId,title=string.format("Ranked Build %03d",index),
        author=player,class=class,fingerprint=fingerprint}
    boards.dummy[index]={player=player,dps=30000000-index*1000,duration=60,level=80,ts=index,
        ownerKey=player:lower().."@ebonhold",ownerVerified=true,realm="ebonhold",
        category="dummy",fingerprint=fingerprint,buildId=buildId,echoes=echoes,
        lockedEchoes=locked,build=build}
    boards.lk[index]={player=player,dps=28000000-index*1000,duration=90,level=80,ts=index,
        ownerKey=player:lower().."@ebonhold",ownerVerified=true,realm="ebonhold",
        category="lk",fingerprint=fingerprint,buildId=buildId,echoes=echoes,
        lockedEchoes=locked,build=build}
end

local boardReads=0
Nexus.DpsCapture={
    GetDpsBoard=function(category)
        boardReads=boardReads+1
        return boards[category] or {}
    end,
}
local statusReads=0
Nexus.Sync={
    GetLeaderboardSyncStatus=function()
        statusReads=statusReads+1
        return "idle",0,0,{}
    end,
}
dofile("ui/Theme.lua")
dofile("core/CandidateEvidence.lua")
dofile("ui/Leaderboard.lua")
local L=Nexus.Leaderboard
L.Init(nil)
L.Show("dummy")
local initial=L.VirtualStats()
local themeInitial=Nexus.Theme.Stats()
assert(initial.results==150 and initial.active<=5
    and initial.created==initial.active and initial.first==1,
    "Leaderboard created or bound one row per record")

-- Ten periodic ticks may repaint status text only.
local projectionBefore=Nexus.ViewProjections.Stats().leaderboard
local tickBefore=L.VirtualStats()
local rawBoardReadsBefore=boardReads
local onUpdate=NexusLeaderboardFrame:GetScript("OnUpdate")
for _=1,10 do onUpdate(NexusLeaderboardFrame,1.1) end
local projectionAfter=Nexus.ViewProjections.Stats().leaderboard
local tickAfter=L.VirtualStats()
local themeAfterTicks=Nexus.Theme.Stats()
assert(tickAfter.statusRefreshes==tickBefore.statusRefreshes+10
    and tickAfter.dataRefreshes==tickBefore.dataRefreshes
    and tickAfter.dataBinds==tickBefore.dataBinds
    and tickAfter.detailRenders==tickBefore.detailRenders
    and tickAfter.themeTreeWalks==tickBefore.themeTreeWalks
    and projectionAfter.rebuilds==projectionBefore.rebuilds
    and projectionAfter.hits==projectionBefore.hits
    and projectionAfter.boardReads==projectionBefore.boardReads
    and boardReads==rawBoardReadsBefore
    and themeAfterTicks.treeWalks==themeInitial.treeWalks
    and themeAfterTicks.hooks==themeInitial.hooks
    and themeAfterTicks.textures==themeInitial.textures
    and statusReads>=11,
    "status ticks rebuilt Leaderboard data, detail, projection, or theme")

local virtualScroll=NexusLeaderboardFrame._virtualListScrollFrame
local onSizeChanged=virtualScroll and virtualScroll:GetScript("OnSizeChanged")
assert(type(onSizeChanged)=="function","Leaderboard viewport resize did not install a rebind")
virtualScroll:SetHeight(200)
onSizeChanged(virtualScroll,590,200)
local resized=L.VirtualStats()
assert(resized.active==7 and resized.resizeBinds==1
    and resized.dataBinds==tickAfter.dataBinds,
    "Leaderboard viewport growth rebuilt data or escaped its bounded window")
virtualScroll:SetHeight(100)
onSizeChanged(virtualScroll,590,100)
assert(L.VirtualStats().active<=5 and L.VirtualStats().resizeBinds==2,
    "Leaderboard viewport shrink did not clamp the bounded window")

-- Every exact rank is reachable with one bounded reusable row pool.
local dataBinds=tickAfter.dataBinds
for index=1,150 do
    assert(L.ScrollTo((index-1)*40))
    local window=L.VirtualStats()
    assert(window.first<=index and window.last>=index and window.active<=7,
        "rank was not reachable at its exact offset: "..index)
end
local ending=L.VirtualStats()
assert(ending.last==150 and ending.created<=7
    and ending.dataBinds==dataBinds,
    "scrolling rebuilt data or grew an unbounded row pool")

-- Stable-key selection survives offscreen scrolling and a data revision.
local selectedKey="player080@ebonhold|string:"..boards.dummy[80].fingerprint
assert(L.SelectKey(selectedKey),"stable Leaderboard key was not selectable")
L.ScrollTo((80-1)*40)
assert(L.VirtualStats().selectedVisible,"selected rank did not show its highlight")
local selectedDetailRenders=L.VirtualStats().detailRenders
L.ScrollTo(math.huge)
assert(L.VirtualStats().selectedKey==selectedKey
    and not L.VirtualStats().selectedVisible
    and L.VirtualStats().detailRenders==selectedDetailRenders,
    "offscreen scroll lost selection identity or rerendered detail")
boards.dummy[80].dps=boards.dummy[80].dps+500
Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{source="fixture"})
local rebuildBefore=Nexus.ViewProjections.Stats().leaderboard.rebuilds
L.RefreshData()
assert(L.VirtualStats().selectedKey==selectedKey
    and Nexus.ViewProjections.Stats().leaderboard.rebuilds==rebuildBefore+1,
    "data revision did not rebuild once while preserving stable selection")

-- Exact loadout actions continue to use the selected defensive row.
local copied
Nexus.WishlistEditor={OpenForCandidate=function(candidate) copied=candidate end}
local detail=NexusLeaderboardFrame._leaderboardDetail
detail.copy:GetScript("OnClick")()
assert(copied and copied.evidenceKind=="candidate-typed-v1"
    and #copied.ordinaryEchoes==2 and copied.ordinaryEchoes[1].spellId==720080
    and #copied.lockedEchoes==1 and copied.lockedEchoes[1].spellId==740080,
    "copy action flattened or lost typed Echo evidence")
L.Show("dummy")
assert(L.SelectKey(selectedKey))
local opened
Nexus.CommunityBuilds={ShowBuild=function(id) opened=id end}
detail.open:GetScript("OnClick")()
assert(opened=="ranked-080","open action lost exact build identity")

-- A malformed projected row can fail binding, but cannot strand the checked-
-- out widget; a corrected revision must reuse the same bounded pool.
L.Show("dummy")
L.ScrollTo(0)
local healthyBuild=boards.dummy[1].build
boards.dummy[1].build=7
Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{source="malformed fixture"})
local beforeFailure=L.VirtualStats()
local createdBeforeFailure=beforeFailure.created
local activeBeforeFailure=beforeFailure.active
local badOk=L.RefreshData()
assert(not badOk and L.VirtualStats().active==activeBeforeFailure
    and L.VirtualStats().results==beforeFailure.results
    and L.VirtualStats().dataFailures==beforeFailure.dataFailures+1
    and L.VirtualStats().refreshDirty
    and L.VirtualStats().created==createdBeforeFailure,
    "failed Leaderboard row binding did not retain the last-good bounded view")
boards.dummy[1].build=healthyBuild
Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{source="corrected fixture"})
L.RefreshData()
assert(L.VirtualStats().active<=5
    and L.VirtualStats().created==createdBeforeFailure,
    "corrected Leaderboard data did not reuse the reclaimed row pool")

-- Categories, search, class filters, and empty state each rebuild once.
L.Show("lk")
assert(L.VirtualStats().results==150 and L.VirtualStats().category=="lk")
boards.lk[80].lockedEchoes={{spellId=740081,stacks=1}}
Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,
    {source="combined locked conflict"})
L.SetCategory("combined")
assert(L.VirtualStats().results==150 and L.VirtualStats().category=="combined")
assert(L.SelectKey(selectedKey))
detail=NexusLeaderboardFrame._leaderboardDetail
copied=nil
assert(not detail.copy:IsEnabled()
    and detail.more:GetText():find("disagree on locked Echo evidence",1,true),
    "combined locked-evidence conflict did not remain visible and fail closed")
detail.copy:GetScript("OnClick")()
assert(copied==nil,"combined locked-evidence conflict opened the editor")
boards.lk[80].lockedEchoes={{spellId=740080,stacks=1}}
Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,
    {source="combined locked recovery"})
L.RefreshData()
assert(L.SelectKey(selectedKey)
    and NexusLeaderboardFrame._leaderboardDetail.copy:IsEnabled(),
    "matching combined locked evidence did not recover actionability")
NexusLeaderboardSearch:SetText("Player001")
L.RefreshData()
assert(L.VirtualStats().results==1 and L.VirtualStats().offset==0,
    "search shrink did not rebuild and clamp the Leaderboard")
NexusLeaderboardSearch:SetText("")
L.SetClassFilter("PRIEST")
assert(L.VirtualStats().results==0 and L.VirtualStats().active==0,
    "empty class filter retained stale Leaderboard rows")
L.SetClassFilter("MAGE")
assert(L.VirtualStats().results==75 and L.VirtualStats().active<=5,
    "class filter did not rebuild one bounded Leaderboard window")
local themeFinal=Nexus.Theme.Stats()
assert(themeFinal.treeWalks==themeInitial.treeWalks
    and themeFinal.virtualRows==ending.created
    and themeFinal.hooks==themeInitial.hooks
    and themeFinal.textures==themeInitial.textures,
    "repeat data/show paths traversed the tree or restyled virtual rows")

print(string.format(
    "leaderboard virtualization: rows=150 created=%d statusTicks=10 boardReads=%d -- OK",
    ending.created,boardReads))
