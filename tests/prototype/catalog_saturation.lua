-- Saturation of an admitted catalog (capacity envelope V2). When a category is
-- full, existing data and the Leaderboard stay usable; a change that needs a
-- new identity or marker is refused explicitly and before any catalog mutation;
-- an eviction that cannot keep its retention marker is not staged at all (no
-- partial eviction); the refusals are retained as one bounded record with one
-- chat line per session. Nothing expires early because a category is full.
-- Real TOC boot, real catalog, real retention owner; synthetic data; the local
-- clock is a controlled time() for this test only.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local DAY=86400
local clock=1790000000
local function Clock() time=function() return clock end end
local function Count(t) local n=0;for _ in pairs(t or {})do n=n+1 end;return n end
local function Record(id,extra)
 local r={id=id,title='Synthetic '..id,author='Peer'..(#id%40)..'-Realm',class='MAGE',postedAt=1,lastModified=1,
  ordinaryComplete=true,loadoutAvailable=true,lockedEchoes={},lockedComplete=true,
  echoes={{spellId=200001,quality=1,stacks=1},{spellId=200002,quality=2,stacks=1}}}
 for k,v in pairs(extra or {})do r[k]=v end
 return r
end
local function Marker(id,at)
 return {schemaVersion=1,typedId={luaType='string',exactValue=id},evictedCatalogGeneration=1,
  evictedSourceIdentity='overlay',evictedProvenanceIdentity='',receiptRevision=1,receiptAtServerTime=at}
end
local H
local function Boot(db) H=F.Boot(db,Clock);return Nexus.BuildCatalog end
local function Reload() H=F.Reload(Clock);return Nexus.BuildCatalog end
local function Run(seconds) for _=1,math.floor((seconds or 20)/0.05) do H.Advance(.05,.05) end end
local function Bundle() return NexusDB.authorityBundle or {} end
local function Settle(ok,why,ticket)
 if ok==nil and type(ticket)=='table' then
  for _=1,8000 do H.Advance(.05,.05) if ticket.state~='pending' then break end end
  return ticket.committed==true,ticket.reason or why
 end
 return ok,why
end
local function Full(C) return C.SaturationSummary() or {} end
local function ChatCount(text)
 local n=0;for _,line in ipairs(H.chat)do if tostring(line):find(text,1,true) then n=n+1 end end;return n
end

-- 1. 2048 different builds: a record for a new build is refused before any mutation,
-- explicitly; an update of an existing build still commits; the Leaderboard
-- and Community stay available; one chat line per session.
local db={settingsVersion=5,settings={},chars={},communityBuilds={}}
for i=1,2048 do db.communityBuilds['full-'..i]=Record('full-'..i) end
local C=Boot(db)
check(Nexus.StartupStatus().state=='ready' and C.Status().buildIdentityCount==2048,'a catalog with 2048 builds is admitted')
Run(5)
local ok,why,ticket=C.Put(Record('new-1'),{source='sync'})
check(ok==false and why=='ROOT_SLOT_LIMIT' and ticket==nil,'a new build is refused before any catalog mutation: '..tostring(why))
check(C.ManualPreparationStatus().ready,'no catalog candidate was started')
local updated=Record('full-7',{title='Updated title',lastModified=5})
check(Settle(C.Put(updated,{source='sync'})),'an update of an existing build still commits')
check(C.Get('full-7') and C.Get('full-7').title=='Updated title','the update is visible')
for i=2,6 do C.Put(Record('new-'..i),{source='sync'}) end
local rec=Full(C)
check(rec.reason=='ROOT_SLOT_LIMIT' and rec.counter=='distinct-builds' and rec.limit==2048 and rec.refused==6,
 'the refusals are one retained record: '..tostring(rec.refused))
Run(5)
check(ChatCount('Community catalog full')==1,'one chat line for the session')
for i=7,12 do C.Put(Record('new-'..i),{source='sync'}) end
Run(60)
check(ChatCount('Community catalog full')==1,'no repeated chat line for further refusals')
local at=#H.chat;SlashCmdList.NEXUS('status')
local said=table.concat(H.chat,'\n',at+1)
check(said:find('catalog capacity: different builds 2048/2048',1,true) and said:find('catalog full: 12 new change(s) refused',1,true),
 '/nexus status states capacity and saturation: '..said)
local summary=Nexus.SupportReport.Summary()
check(type(summary)=='string' and summary:find('catalog full: 12',1,true),'the Copy summary carries the saturation facts')
Nexus.Leaderboard.Show('lk');Run(2)
check(Nexus.Leaderboard.VirtualStats().dataReady==true and Nexus.StartupStatus().state=='ready',
 'the Leaderboard stays available and Community stays ready')
Nexus.Leaderboard.Hide()
check(Count(Bundle().communityBuilds)==2048,'the saved catalog is unchanged in size')
C=Reload()
check(Nexus.StartupStatus().state=='ready' and C.SaturationSummary()==nil and C.Status().buildIdentityCount==2048,
 'after a reload the catalog is admitted and the session record starts empty')

-- 2. 2048 retention markers: an eviction that needs a new marker is refused
-- before it is staged, so the build stays; nothing expires early.
local db2={settingsVersion=5,settings={},chars={},communityBuilds={},communityRetentionEvictions={}}
for i=1,2048 do db2.communityRetentionEvictions['gone-'..i]=Marker('gone-'..i,clock-DAY) end
for i=1,20 do db2.communityBuilds['auto-'..i]=Record('auto-'..i,{autoDps=true}) end
C=Boot(db2);Run(600)
check(C.Status().barrierCount==2048,'fixture: 2048 recent retention markers')
local released,releaseWhy=Nexus.DataRetention.ReleaseSupersededAutoBuild('auto-3')
Run(5)
check(released~=true and C.Get('auto-3')~=nil and Bundle().communityBuilds['auto-3']~=nil
 and Count(Bundle().communityRetentionEvictions)==2048,'the eviction is not staged: the build stays and no marker is added')
rec=Full(C)
check(rec.reason=='BARRIER_SET_LIMIT' and rec.limit==2048,'the refusal is retained: '..tostring(rec.reason))
Nexus.DataRetention.Request('full');Run(20)
check(Count(Bundle().communityRetentionEvictions)==2048,'a full marker map expires nothing early')

-- 3. 2048 removal markers: a removal by the build's owner that needs a new
-- marker is refused explicitly and the build stays.
local db3={settingsVersion=5,settings={},chars={},
 communityBuilds={['keep-1']=Record('keep-1',{author='Peer-Realm',ownerKey='Peer@Realm'})},syncTombstones={}}
for i=1,2048 do db3.syncTombstones['del-'..i]={stamp=1,author='OldPeer'} end
C=Boot(db3);Run(5)
local removed,removeWhy=C.SetTombstone('keep-1',{stamp=5,author='Peer-Realm'},{source='remote',sender='Peer-Realm'})
check(removed==false and removeWhy=='TOMBSTONE_SET_LIMIT' and C.Get('keep-1')~=nil,
 'a removal that needs a new marker is refused and the build stays: '..tostring(removeWhy))

-- 4. Saturated before migrated legacy markers age: 2048 legacy markers and
-- 2048 builds. The data stays usable, new data is refused, and after the
-- markers age out an eviction and a new build succeed again.
local db4={settingsVersion=5,settings={},chars={},communityBuilds={},communityRetentionEvictions={}}
for i=1,2048 do db4.communityRetentionEvictions['old-'..i]=1700000000+i end
for i=1,2048 do db4.communityBuilds['b-'..i]=Record('b-'..i,{autoDps=i<=10}) end
C=Boot(db4);Run(30)
check(Nexus.StartupStatus().state=='ready' and C.Status().barrierCount==2048 and C.Status().buildIdentityCount==2048,
 'fixture: both categories are full and the catalog is admitted')
check(Count((Bundle().dataRetention or {}).markerFirstSeen)==2048,'every legacy marker is first observed now')
ok,why=C.Put(Record('fresh-1'),{source='sync'})
check(ok==false and why=='ROOT_SLOT_LIMIT','a new build is refused while full')
clock=clock+31*DAY
C=Reload();Run(30)
check(C.Status().barrierCount==0 and Count((Bundle().dataRetention or {}).markerFirstSeen)==0,
 'after 30 days the legacy markers aged out and their first observations left with them')
released=Nexus.DataRetention.ReleaseSupersededAutoBuild('b-1')
Run(20)
check(Bundle().communityBuilds['b-1']==nil and Bundle().communityRetentionEvictions['b-1']~=nil,
 'an eviction now succeeds and keeps its marker')
check(Settle(C.Put(Record('fresh-1'),{source='sync'})) and C.Get('fresh-1')~=nil,'a new build is admitted into the freed slot')

-- 5. Long-running churn stays bounded: every day new received automatic
-- builds replace older ones, each eviction adds a dated marker, and markers
-- expire after 30 days. Builds, markers and first observations stay bounded.
local db5={settingsVersion=5,settings={},chars={},communityBuilds={}}
C=Boot(db5);Run(600)
local serial,maxMarkers,maxBuilds=0,0,0
local alive={}
for day=1,45 do
 for k=1,4 do
  serial=serial+1
  local id='churn-'..serial
  if Settle(C.Put(Record(id,{autoDps=true,lastModified=serial}),{source='sync'})) then alive[#alive+1]=id end
 end
 while #alive>8 do
  local victim=table.remove(alive,1)
  Settle(Nexus.DataRetention.ReleaseSupersededAutoBuild(victim))
 end
 clock=clock+DAY
 Nexus.DataRetention.Request('day');Run(10)
 local st=C.Status()
 maxMarkers=math.max(maxMarkers,st.barrierCount);maxBuilds=math.max(maxBuilds,st.buildIdentityCount)
end
local st=C.Status()
check(serial==180 and st.buildIdentityCount<=8+4 and maxBuilds<=12,'builds stay bounded by the churn: '..st.buildIdentityCount..' max '..maxBuilds)
check(maxMarkers<=4*31 and st.barrierCount<=4*31,'retention markers stay bounded by the 30-day age: max '..maxMarkers..' now '..st.barrierCount)
check(Count((Bundle().dataRetention or {}).markerFirstSeen)==0,'writer-dated markers need no first observations')
print(string.format('PASS catalog_saturation: explicit refusal before any mutation, updates and Leaderboard usable when full, one chat line, no partial eviction, no early expiry, recovery after aging, bounded churn (markers max %d) checks=%d',maxMarkers,checks))
