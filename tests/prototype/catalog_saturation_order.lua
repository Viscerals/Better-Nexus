-- Capacity refusals keep the right reason, and only a change that would
-- otherwise be accepted is counted as refused because a category is full.
-- A full category never hides a reservation, malformed-record or owner
-- refusal. A receiver batch counts the new builds of its earlier members. A
-- build that has only a shipped copy is an update, not a new build. Markers
-- that expire in a retention transaction make room for evictions staged after
-- them in the same transaction. An imported build is refused before staging
-- when the catalog is full. The chat line names the full category. A retention
-- request made during a long busy period still records first observations.
-- Real TOC boot, real catalog, real retention owner; synthetic data; the local
-- clock is a controlled time() for this test only.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local DAY=86400
local clock=1790000000
local function Clock() time=function() return clock end end
local function Count(t) local n=0;for _ in pairs(t or {})do n=n+1 end;return n end
local function Record(id,extra)
 local r={id=id,title='Synthetic '..tostring(id),author='Peer-Realm',class='MAGE',postedAt=1,lastModified=1,
  ordinaryComplete=true,loadoutAvailable=true,lockedEchoes={},lockedComplete=true,
  echoes={{spellId=200001,quality=1,stacks=1},{spellId=200002,quality=2,stacks=1}}}
 for k,v in pairs(extra or {})do r[k]=v end
 return r
end
local function Marker(id,at)
 return {schemaVersion=1,typedId={luaType=type(id),exactValue=id},evictedCatalogGeneration=1,
  evictedSourceIdentity='overlay',evictedProvenanceIdentity='',receiptRevision=1,receiptAtServerTime=at}
end
local H
local function Boot(db,shipped)
 F.fileHooks=shipped and {[ [[data\BundledBuilds.lua]] ]=function()Nexus.BundledBuilds.builds=shipped end} or nil
 H=F.Boot(db,Clock);F.fileHooks=nil
 return Nexus.BuildCatalog
end
local function Run(seconds) for _=1,math.floor((seconds or 20)/0.05) do H.Advance(.05,.05) end end
local function Bundle() return NexusDB.authorityBundle or {} end
local function Settle(ok,why,ticket)
 if ok==nil and type(ticket)=='table' then
  for _=1,8000 do H.Advance(.05,.05) if ticket.state~='pending' then break end end
  return ticket.committed==true,ticket.reason or why
 end
 return ok,why
end
local function Refused(C) return (C.SaturationSummary() or {}).refused or 0 end
local function ChatCount(text)
 local n=0;for _,line in ipairs(H.chat)do if tostring(line):find(text,1,true) then n=n+1 end end;return n
end
local function Maintenance(C,operation)
 for _=1,4000 do
  local handle=C.BeginCatalogMaintenance({database=NexusDB,operation=operation})
  if handle then return handle end
  H.Advance(.05,.05)
 end
end

-- 1. 2047 saved builds and one shipped-only build are 2048 builds. A record
-- for an ID held by a retention marker or a removal marker, and a malformed
-- record for a new ID, keep their own reasons and are not counted as "full".
-- An update of the shipped-only build is not a new build. Only a valid new
-- build is refused as full, and that refusal is counted.
local db={settingsVersion=5,settings={},chars={},communityBuilds={},
 syncTombstones={['del-1']={stamp=1,author='OldPeer'}},
 communityRetentionEvictions={['gone-1']=Marker('gone-1',clock-DAY)}}
for i=1,2047 do db.communityBuilds['b-'..i]=Record('b-'..i) end
local C=Boot(db,{['ship-1']=Record('ship-1')})
Run(5)
check(Nexus.StartupStatus().state=='ready' and C.Status().buildIdentityCount==2048,
 'fixture: 2047 saved builds and one shipped-only build are 2048 builds: '..tostring(C.Status().buildIdentityCount))
local ok,why=C.Put(Record('gone-1'),{source='sync'})
check(ok==false and why=='BARRIER_RESERVATION','an ID held by a retention marker keeps its reason: '..tostring(why))
ok,why=C.Put(Record('del-1'),{source='sync'})
check(ok==false and why=='TOMBSTONE_RESERVATION','an ID held by a removal marker keeps its reason: '..tostring(why))
ok,why=C.Put({id='bad-1',title=5},{source='sync'})
check(ok==false and why=='MALFORMED_ROW','a malformed record for a new ID keeps its reason: '..tostring(why))
check(Refused(C)==0 and C.SaturationSummary()==nil,'none of them is counted as refused because the catalog is full')
check(C.ManualPreparationStatus().ready,'no catalog candidate was left behind')
check(Settle(C.Put(Record('ship-1',{title='Changed shipped build',lastModified=5}),{source='sync'})),
 'an update of the shipped-only build is not a new build and commits')
check(C.Get('ship-1').title=='Changed shipped build' and C.Status().buildIdentityCount==2048,
 'the saved copy of the shipped build is still one build')
local ticket
ok,why,ticket=C.Put(Record('new-1'),{source='sync'})
check(ok==false and why=='ROOT_SLOT_LIMIT' and ticket==nil,'a valid new build is refused as full: '..tostring(why))
local rec=C.SaturationSummary() or {}
check(rec.refused==1 and rec.refusedBuilds==1 and rec.refusedTombstones==0 and rec.refusedBarriers==0,
 'exactly that refusal is counted, as a build refusal')
check(C.ManualPreparationStatus().ready,'no catalog candidate was started for it')
Run(2)
check(ChatCount('Community catalog full: new shared builds are refused.')==1
 and ChatCount('removal markers full')==0 and ChatCount('retention markers full')==0,
 'the chat line names the full category: builds')

-- 2. A receiver batch at 2047 builds: the first new build fits and commits,
-- the second new build is refused as full, an update of an existing build
-- commits, and the number 5 (a new typed ID) is refused as full.
local db2={settingsVersion=5,settings={},chars={},communityBuilds={}}
for i=1,2047 do db2.communityBuilds['full-'..i]=Record('full-'..i) end
C=Boot(db2);Run(5)
check(C.Status().buildIdentityCount==2047 and C.ManualPreparationStatus().ready,'fixture: 2047 builds, catalog idle')
local okBatch,whyBatch,tickets=C.PutBatch({
 {record=Record('new-A'),options={source='sync'}},
 {record=Record('new-B'),options={source='sync'}},
 {record=Record('full-7',{title='Updated',lastModified=5}),options={source='sync'}},
 {record=Record(5),options={source='sync'}},
})
check(okBatch==nil and type(tickets)=='table' and #tickets==4,'the batch is accepted for preparation: '..tostring(whyBatch))
for _=1,20000 do
 H.Advance(.05,.05)
 local pending=false
 for _,t in ipairs(tickets)do if t.state=='pending' then pending=true end end
 if not pending then break end
end
local function Member(i) local t=tickets[i];return t.committed==true,tostring(t.reason) end
local a,aWhy=Member(1);local b,bWhy=Member(2);local u,uWhy=Member(3);local n,nWhy=Member(4)
check(a and C.Get('new-A')~=nil,'the first new build fits and commits: '..aWhy)
check(not b and bWhy=='ROOT_SLOT_LIMIT' and C.Get('new-B')==nil,'the second new build is refused as full: '..bWhy)
check(u and C.Get('full-7').title=='Updated','the update of an existing build commits: '..uWhy)
check(not n and nWhy=='ROOT_SLOT_LIMIT' and C.Get(5)==nil,'the number 5 is a new typed ID and is refused as full: '..nWhy)
check(C.Status().buildIdentityCount==2048 and Count(Bundle().communityBuilds)==2048,
 'the catalog holds exactly 2048 builds')
rec=C.SaturationSummary() or {}
check(rec.refused==2 and rec.refusedBuilds==2,'two build refusals are counted: '..tostring(rec.refused))

-- 3. 2048 removal markers: a removal from a sender who does not own the build
-- keeps its owner reason and is not counted; the owner's removal is refused
-- because the map is full, is counted, and the build stays.
local db3={settingsVersion=5,settings={},chars={},
 communityBuilds={['keep-1']=Record('keep-1',{ownerKey='Peer@Realm'})},syncTombstones={}}
for i=1,2048 do db3.syncTombstones['del-'..i]={stamp=1,author='OldPeer'} end
C=Boot(db3);Run(5)
check(C.Status().tombstoneCount==2048 and C.Get('keep-1')~=nil,'fixture: 2048 removal markers and one owned build')
local removed,removeWhy=C.SetTombstone('keep-1',{stamp=5,author='Other-Realm'},{source='remote',sender='Other-Realm'})
check(removed==false and removeWhy=='REMOTE_OWNER_REQUIRED' and Refused(C)==0,
 'a removal from a sender who does not own the build keeps its reason and is not counted: '..tostring(removeWhy))
removed,removeWhy=C.SetTombstone('keep-1',{stamp=5,author='x'},{source='local'})
check(removed==false and removeWhy=='LOCAL_OWNER_REQUIRED' and Refused(C)==0,
 'a local removal of another player\'s build keeps its owner reason and is not counted: '..tostring(removeWhy))
removed,removeWhy=C.SetTombstone('keep-1',{stamp=5,author='Peer-Realm'},{source='remote',sender='Peer-Realm'})
check(removed==false and removeWhy=='TOMBSTONE_SET_LIMIT' and C.Get('keep-1')~=nil,
 'the owner removal is refused because the map is full and the build stays: '..tostring(removeWhy))
rec=C.SaturationSummary() or {}
check(rec.refused==1 and rec.refusedTombstones==1 and rec.refusedBuilds==0,'the removal refusal is counted as a removal-marker refusal')
Run(2)
check(ChatCount('Community removal markers full: new build removals are refused.')==1
 and ChatCount('new shared builds are refused')==0,'the chat line names the full category: removal markers')

-- 4. 2048 retention markers, 30 of them older than 30 days. In one
-- maintenance transaction an expiry makes room for exactly one eviction; the
-- next eviction is refused and counted. The commit keeps 2048 markers.
local function MarkerDb(ranked)
 local d={settingsVersion=5,settings={communityRetentionEnabled=ranked or nil},chars={},communityBuilds={},
  communityRetentionEvictions={}}
 for i=1,2048 do d.communityRetentionEvictions['r-'..i]=Marker('r-'..i,i<=30 and clock-31*DAY or clock-DAY) end
 for i=1,100 do d.communityBuilds['auto-'..i]=Record('auto-'..i,{autoDps=true,lastModified=i}) end
 return d
end
C=Boot(MarkerDb(false));Run(1)
local handle=Maintenance(C,'retention')
check(handle~=nil,'fixture: a retention transaction is open')
local e1,e1Why=C.MaintenanceExpireBarrier(handle,'r-1')
local v1,v1Why=C.MaintenanceEvictOverlay(handle,'auto-1')
local v2,v2Why=C.MaintenanceEvictOverlay(handle,'auto-2')
check(e1==true,'the aged marker expires: '..tostring(e1Why))
check(v1==true,'the expiry makes room for one eviction in the same transaction: '..tostring(v1Why))
check(v2==false and v2Why=='BARRIER_SET_LIMIT','the next eviction is refused as full: '..tostring(v2Why))
check(Settle(C.CommitMaintenance(handle)),'the transaction commits')
local marks=Bundle().communityRetentionEvictions
check(marks['r-1']==nil and marks['auto-1']~=nil and Bundle().communityBuilds['auto-1']==nil
 and Bundle().communityBuilds['auto-2']~=nil and Count(marks)==2048,
 'the expired marker is gone, the evicted build left with its marker, the refused build stays, 2048 markers')
rec=C.SaturationSummary() or {}
check(rec.refused==1 and rec.refusedBarriers==1,'the refused eviction is counted as a retention-marker refusal')
-- The ranked retention run (opt-in) expires the 30 aged markers first, so up
-- to 30 evictions fit in the same run; the marker map never exceeds 2048.
-- (The run is requested explicitly after start-up work settles: a ranked
-- scan that meets other catalog work can end with a stale summary cursor, a
-- separate known defect; a later request starts a fresh scan.)
C=Boot(MarkerDb(true));Run(90)
Nexus.DataRetention.Request('test: ranked run');Run(120)
marks=Bundle().communityRetentionEvictions
local aged,evicted=0,0
for i=1,30 do if marks['r-'..i]~=nil then aged=aged+1 end end
for i=1,100 do if Bundle().communityBuilds['auto-'..i]==nil then evicted=evicted+1 end end
check(aged==0,'the ranked run expired all 30 aged markers: '..aged..' left')
check(evicted>=1 and evicted<=30 and Count(marks)==2048-30+evicted and Count(marks)<=2048,
 'a ranked run uses the room its own expiries free: evicted '..evicted..', markers '..Count(marks))

-- 5. An imported build is a new build: at 2048 builds it is refused before it
-- is staged (a malformed one keeps its own reason first); at 2047 builds one
-- insert is staged and a second insert in the same transaction is refused.
local db5={settingsVersion=5,settings={},chars={},communityBuilds={}}
for i=1,2048 do db5.communityBuilds['b-'..i]=Record('b-'..i) end
C=Boot(db5);Run(5)
handle=Maintenance(C,'publish-imported')
local s1,s1Why=C.MaintenanceReplaceRow(handle,'bad-x',{id='bad-x',title=5},{allowInsert=true})
check(s1==false and s1Why=='MALFORMED_ROW' and Refused(C)==0,'a malformed insert keeps its reason: '..tostring(s1Why))
C.CancelMaintenance(handle)
handle=Maintenance(C,'publish-imported')
local s2,s2Why=C.MaintenanceReplaceRow(handle,'new-x',Record('new-x'),{allowInsert=true})
check(s2==false and s2Why=='ROOT_SLOT_LIMIT' and Refused(C)==1,'an insert at 2048 builds is refused before staging: '..tostring(s2Why))
C.CancelMaintenance(handle)
check(C.ManualPreparationStatus().ready and C.Get('new-x')==nil and Count(Bundle().communityBuilds)==2048,
 'nothing was staged or committed')
local db5b={settingsVersion=5,settings={},chars={},communityBuilds={}}
for i=1,2047 do db5b.communityBuilds['b-'..i]=Record('b-'..i) end
C=Boot(db5b);Run(5)
check(C.Status().buildIdentityCount==2047,'fixture: 2047 builds')
handle=Maintenance(C,'publish-imported')
local s3,s3Why=C.MaintenanceReplaceRow(handle,'new-y',Record('new-y'),{allowInsert=true})
local s4,s4Why=C.MaintenanceReplaceRow(handle,'new-z',Record('new-z'),{allowInsert=true})
check(s3==true,'at 2047 builds the first insert is staged: '..tostring(s3Why))
check(s4==false and s4Why=='ROOT_SLOT_LIMIT','the second insert in the same transaction is refused: '..tostring(s4Why))
C.CancelMaintenance(handle)

-- 6. The catalog refuses retention runs for 400 s after load (a long busy
-- period such as a first compaction). The request made when the catalog is
-- ready is retried with a growing delay and still records the first
-- observations of legacy markers once the catalog is free.
local db6={settingsVersion=5,settings={},chars={},communityBuilds={},
 communityRetentionEvictions={['legacy-1']=1700000000,['legacy-2']=1700000001}}
local busyUntil,busyRefusals,Hh=nil,0,nil
F.fileHooks={[ [[core\DataRetention.lua]] ]=function()
 local catalog=Nexus.BuildCatalog;local begin=catalog.BeginCatalogMaintenance
 catalog.BeginCatalogMaintenance=function(request)
  if Hh and busyUntil and Hh.now<busyUntil and type(request)=='table' and request.operation=='retention' then
   busyRefusals=busyRefusals+1
   return nil,'ROOT_MUTATION_PENDING'
  end
  return begin(request)
 end
end}
H=F.Boot(db6,function(h) Hh=h;busyUntil=h.now+400;time=function() return clock+math.floor(h.now) end end)
F.fileHooks=nil
Run(380)
local seen=(Bundle().dataRetention or {}).markerFirstSeen
check(Count(seen)==0 and busyRefusals>=1,'fixture: nothing is recorded while the catalog stays busy ('..busyRefusals..' busy attempts)')
check(busyRefusals<=16,'the retry delay grows: '..busyRefusals..' attempts in 380 s')
Run(120)
seen=(Bundle().dataRetention or {}).markerFirstSeen or {}
check(Count(seen)==2 and seen['legacy-1']~=nil and seen['legacy-1']>=clock+math.floor(busyUntil),
 'after the busy period the first observations are recorded from the clock: '..Count(seen))

-- 7. A saved first observation outside the catalog's range (1 to 2^53 - 1),
-- here infinity, is not kept: the next full retention run records it again
-- from the clock. The other marker's first observation is not reset.
local keep2=seen['legacy-2']
Bundle().dataRetention.markerFirstSeen['legacy-1']=math.huge
-- The local clock continues across the reload.
local base=time()
H=F.Reload(function(h) local start=h.now;time=function() return base+math.floor(h.now-start) end end)
-- Runs inside the 300 s maintenance interval take the fast path; the next
-- requested run after it walks the markers.
Run(320)
Nexus.DataRetention.Request('test: after the maintenance interval');Run(20)
seen=(Bundle().dataRetention or {}).markerFirstSeen or {}
check(seen['legacy-1']~=nil and seen['legacy-1']~=math.huge and seen['legacy-1']>=base,
 'an infinite first observation is recorded again from the clock: '..tostring(seen['legacy-1']))
check(seen['legacy-2']==keep2,'the valid first observation is kept across the reload')
print('PASS catalog_saturation_order: reservation, malformed and owner reasons before full; batch, shipped-copy and insert accounting; same-transaction expiry room; per-category chat; busy retry; first-observation range checks='..checks)
