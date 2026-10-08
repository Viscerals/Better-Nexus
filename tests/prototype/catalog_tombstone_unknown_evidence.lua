-- A removal marker this build writes for a LOCAL removal (Stop Sharing) is an
-- exact V1 marker that carries the removed row's unknown evidence
-- (MASTER-RC-016). After a reload that marker is still an EXACT reloaded
-- marker (RELOADED_BLOCK_ALL, source kind "local"), not an opaque one; both
-- deny admission, so this is about truthful classification. Real boot, the
-- local character's own saved shared builds, real local removal, offline
-- module reload; synthetic data only.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local unknownId,cleanId='local-unknown','local-clean'
local fx=L.New({players={
 {name='PrototypeTester',class='MAGE',isLocal=true,buildId=unknownId,variant=3},
 {name='PrototypeTester',class='MAGE',isLocal=true,buildId=cleanId,variant=4},
}})
-- One row carries a field this build does not know; the other is clean.
fx.builds[unknownId].customUnknown={keep=1}
local H=F.Boot(fx:Install(F.Database({version=2})))
for _=1,200 do H.Advance(.05,.05) end
local C=Nexus.BuildCatalog
local function Settle(ticket)
 if type(ticket)=='table' then
  for _=1,4000 do if ticket.state~='pending' then break end;H.Advance(.05,.05) end
  return ticket.committed==true,ticket.reason or ticket.state
 end
 return true
end
for _,id in ipairs({unknownId,cleanId}) do
 local build=C.Get(id)
 check(build~=nil and build.isMine==true,id..': fixture: the local character\'s shared build is admitted as its own')
end
for _,id in ipairs({unknownId,cleanId}) do
 local removed,removeWhy,removeTicket=C.SetTombstone(id,{stamp=5,author='PrototypeTester'},{source='local'})
 if removed==nil and type(removeTicket)=='table' then removed,removeWhy=Settle(removeTicket) end
 check(removed==true,id..': the local removal is accepted: '..tostring(removeWhy))
 check(C.Get(id)==nil and C.TombstoneState(id).state=='CURRENT_DENY',id..': this session the marker is a current denial')
end
local saved=NexusDB.authorityBundle.syncTombstones
check(type(saved[unknownId])=='table' and saved[unknownId].unknownEvidence~=nil,
 'fixture: the marker of the row with the unknown field carries that evidence')
check(type(saved[cleanId])=='table' and saved[cleanId].unknownEvidence==nil,
 'fixture: the marker of the clean row carries none')
H=F.Reload()
C=Nexus.BuildCatalog
for _=1,200 do H.Advance(.05,.05) end
local clean=C.TombstoneState(cleanId)
check(clean.state=='RELOADED_BLOCK_ALL' and clean.sourceKind=='local',
 'control: the clean marker reloads as an exact reloaded marker: '..tostring(clean.state))
local carried=C.TombstoneState(unknownId)
check(carried.state=='RELOADED_BLOCK_ALL' and carried.sourceKind=='local',
 'a marker that carries unknown evidence reloads as an exact reloaded marker too: '..tostring(carried.state))
-- Fail-closed either way: the marked IDs stay refused and no row is restored.
for _,id in ipairs({unknownId,cleanId}) do
 local record=L.Copy(fx.builds[id])
 local put,putWhy=C.Put(record,{source='local'})
 check(put==false and putWhy=='TOMBSTONE_RESERVATION' and C.Get(id)==nil,id..': still refused after the reload: '..tostring(putWhy))
end
check(NexusDB.authorityBundle.syncTombstones[unknownId].unknownEvidence~=nil,'the carried evidence is kept in the saved marker')
print('PASS catalog_tombstone_unknown_evidence checks='..checks)
