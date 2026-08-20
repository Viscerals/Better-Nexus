-- Leaderboard publication budget at 1,000-build/500-DPS scale.
local H = dofile("tests/harness.lua")

NexusDB={communityBuilds={},buildFilters={},dpsCapture={}}
for index=1,1000 do
    NexusDB.communityBuilds[string.format("catalog-%04d",index)]={
        id=string.format("catalog-%04d",index),title="Catalog "..index,
    }
end
Nexus.BuildCatalog.Init(NexusDB,{schemaVersion=1,catalogVersion="budget",
    sourceVersion="test",builds={}})
local boards={dummy={},lk={}}
for index=1,250 do
    local player=string.format("BudgetPlayer%03d",index)
    local buildId=string.format("ranked-%03d",index)
    local fingerprint=tostring(720000 + index) .. "x1"
    local ownerKey=player:lower() .. "@ebonhold"
    local build={id=buildId,title="Ranked "..index,author=player,class="MAGE",
        ownerKey=ownerKey,ownerVerified=true,realm="ebonhold"}
    boards.dummy[index]={player=player,dps=30000000-index,duration=60,
        level=80,ts=index,category="dummy",class="MAGE",fingerprint=fingerprint,
        ownerKey=ownerKey,ownerVerified=true,realm="ebonhold",
        buildId=buildId,build=build,echoes={{spellId=720000+index,stacks=1}}}
    boards.lk[index]={player=player,dps=28000000-index,duration=90,
        level=80,ts=index,category="lk",class="MAGE",fingerprint=fingerprint,
        ownerKey=ownerKey,ownerVerified=true,realm="ebonhold",
        buildId=buildId,build=build,echoes={{spellId=720000+index,stacks=1}}}
end
local boardReads=0
Nexus.DpsCapture={GetDpsBoard=function(category)
    boardReads=boardReads+1
    return boards[category] or {}
end}
local receiving, remaining=false,0
Nexus.Sync={
    IsReceiving=function() return receiving end,
    ReceiveTimeLeft=function() return receiving and remaining or 0 end,
    GetLeaderboardSyncStatus=function() return receiving and "syncing" or "idle",0,0,{} end,
}
dofile("ui/Theme.lua")
dofile("ui/Leaderboard.lua")
dofile("core/ViewRefresh.lua")
Nexus.Scheduler.Init()
Nexus.ViewRefresh.Init()
local L,P=Nexus.Leaderboard,Nexus.ViewProjections
L.Init(nil)
L.Show("combined")
local initialVirtual=L.VirtualStats()
local initialProjection=P.Stats().leaderboard
assert(initialVirtual.results==250 and initialVirtual.active<=7
    and initialVirtual.created==initialVirtual.active
    and boardReads==2,
    "large Leaderboard initial projection/pool is not bounded: results="
        ..tostring(initialVirtual.results).." active="
        ..tostring(initialVirtual.active).." created="
        ..tostring(initialVirtual.created).." reads="..tostring(boardReads))

-- Repeated unchanged publication requests must be status-only: no cached
-- defensive copy, board scan/join/sort, detail render, or row binding.
for _=1,100 do assert(L.Refresh()) end
local unchangedVirtual=L.VirtualStats()
local unchangedProjection=P.Stats().leaderboard
assert(boardReads==2
    and unchangedProjection.rebuilds==initialProjection.rebuilds
    and unchangedProjection.boardReads==initialProjection.boardReads
    and unchangedProjection.sorts==initialProjection.sorts
    and unchangedProjection.defensiveCopies==initialProjection.defensiveCopies
    and unchangedVirtual.dataBinds==initialVirtual.dataBinds
    and unchangedVirtual.detailRenders==initialVirtual.detailRenders
    and unchangedVirtual.dataSkips==initialVirtual.dataSkips+100,
    "unchanged Leaderboard publication copied or rebound ranked data")

-- One hundred represented revisions during active Sync coalesce into a cheap
-- dirty mark. The real visible Leaderboard publishes exactly once afterward.
receiving,remaining=true,3
for index=1,100 do
    boards.dummy[1].dps=boards.dummy[1].dps+1
    Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{source=index})
end
assert(#Nexus.Scheduler.Pending()==1,
    "Leaderboard revision burst did not coalesce")
H.now=H.now+0.05
assert(Nexus.Scheduler.Tick(H.now)==1)
local activeVirtual=L.VirtualStats()
assert(boardReads==2 and activeVirtual.dataBinds==initialVirtual.dataBinds
    and activeVirtual.refreshDirty and activeVirtual.dirtyMarks==1,
    "active Sync performed heavy Leaderboard work")
receiving,remaining=false,0
H.now=H.now+3.10
assert(Nexus.Scheduler.Tick(H.now)==1)
local quietVirtual=L.VirtualStats()
local quietProjection=P.Stats().leaderboard
assert(boardReads==4
    and quietProjection.rebuilds==initialProjection.rebuilds+1
    and quietVirtual.dataBinds==initialVirtual.dataBinds+1
    and quietVirtual.deferredRefreshes==1
    and not quietVirtual.refreshDirty,
    "post-Sync Leaderboard did not publish exactly once")
assert(Nexus.Scheduler.Tick(H.now+1)==0 and boardReads==4,
    "quiet Leaderboard publication duplicated")

-- Hidden receive/quiet work stays projection-free; showing later publishes one
-- current view through the existing fixed pool.
L.Hide()
receiving,remaining=true,2
Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{source="hidden"})
H.now=H.now+0.05
assert(Nexus.Scheduler.Tick(H.now)==1)
receiving,remaining=false,0
H.now=H.now+2.10
assert(Nexus.Scheduler.Tick(H.now)==1 and boardReads==4,
    "hidden Leaderboard performed heavy post-Sync work")
L.Show("combined")
local shownVirtual=L.VirtualStats()
assert(boardReads==6 and shownVirtual.created==initialVirtual.created
    and shownVirtual.active<=7,
    "showing dirty Leaderboard lost fixed-pool bounded publication")

local catalogCount=0
for _ in pairs(NexusDB.communityBuilds) do catalogCount=catalogCount+1 end
assert(catalogCount==1000 and #boards.dummy+#boards.lk==500,
    "publication budget capped source catalog or DPS data")
print(string.format(
    "leaderboard refresh budget: builds=%d dps=%d rows=%d boardReads=%d created=%d activeSyncHeavy=0 publications=1 -- OK",
    catalogCount,#boards.dummy+#boards.lk,shownVirtual.results,
    boardReads,shownVirtual.created))
