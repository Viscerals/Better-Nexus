-- Removal markers (tombstones) are catalog ingress authority. A reloaded
-- marker is never retired by age: 181 days after a removal, across a reload,
-- the marker is in force, the ID stays refused, no row is restored and the
-- retention pass retires nothing. The budget (2048 markers per saved profile)
-- is therefore a lifetime count, which Status() states. This pins the
-- shipped policy; it grants no readmission. Real boot, real remote admission
-- and owner removal, real retention owner, controlled clock; synthetic data.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local DAY=86400
local clock=1790000000
local function Clock() time=function() return clock end end
local SENDER,OWNER='Peer-Realm','peer@realm'
local function Record(id)
 local echoes={}
 for j=1,79 do echoes[j]={spellId=200000+j,quality=j%4,stacks=1} end
 return {id=id,title='Synthetic '..id,author=SENDER,ownerKey=OWNER,realm='realm',class='MAGE',
  postedAt=2,lastModified=2,description='Synthetic',echoes=echoes,loadoutAvailable=true}
end
local H=F.Boot(F.Database({version=2}),Clock)
local function Run(seconds) for _=1,math.floor((seconds or 20)/0.05) do H.Advance(.05,.05) end end
local function Settle(ticket)
 if type(ticket)=='table' then
  for _=1,4000 do if ticket.state~='pending' then break end;H.Advance(.05,.05) end
  return ticket.committed==true,ticket.reason or ticket.state
 end
 return true
end
local function Retention(reason) Nexus.DataRetention.Request(reason);Run(20) end
local C=Nexus.BuildCatalog
Run(5)
local ok,why,ticket=C.Put(Record('peer-1'),{source='remote',sender=SENDER})
if ok==nil and type(ticket)=='table' then ok,why=Settle(ticket) end
check(ok==true and C.Get('peer-1')~=nil,'fixture: the build is admitted: '..tostring(why))
local removed,removeWhy,removeTicket=C.SetTombstone('peer-1',{stamp=1,author=SENDER},{source='remote',sender=SENDER})
if removed==nil and type(removeTicket)=='table' then removed,removeWhy=Settle(removeTicket) end
check(removed==true,'fixture: the owner removal is accepted: '..tostring(removeWhy))
check(C.TombstoneState('peer-1').state~='NONE' and C.Get('peer-1')==nil,'this session: the marker is in force')
local status=C.Status()
check(status.tombstoneCount==1 and status.tombstoneLimit==2048,
 'Status states the marker count and the lifetime budget: '..tostring(status.tombstoneCount)..'/'..tostring(status.tombstoneLimit))
-- 181 days later, a new session.
clock=clock+181*DAY
H=F.Reload(Clock);C=Nexus.BuildCatalog
Run(5)
check(type(NexusDB.authorityBundle.syncTombstones['peer-1'])=='table','fixture: the marker was saved')
Retention('day 181')
local state=C.TombstoneState('peer-1')
check(state.state~='NONE' and NexusDB.authorityBundle.syncTombstones['peer-1']~=nil,
 '181 days later the reloaded marker is still in force: '..tostring(state.state))
local put,putWhy=C.Put(Record('peer-1'),{source='remote',sender=SENDER})
check(put==false and putWhy=='TOMBSTONE_RESERVATION' and C.Get('peer-1')==nil,'the ID stays refused and no row is restored: '..tostring(putWhy))
local stats=Nexus.DataRetention.Stats()
check(type(stats)=='table','fixture: the retention pass ran')
check((stats.tombstonesRemoved or 0)==0,'the retention pass retired nothing: '..tostring(stats.tombstonesRemoved))
check(C.Status().tombstoneCount==1,'the marker still counts against the lifetime budget')
print('PASS tombstone_retirement_policy checks='..checks)
