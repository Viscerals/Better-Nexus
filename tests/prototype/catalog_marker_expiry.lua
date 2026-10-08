-- Retention-marker expiry (owner decision of 2026-09-24). A retention marker
-- expires 30 days after its trusted LOCAL age: the saved local creation time
-- of a current-format marker, or the locally recorded first observation of an
-- untimed or legacy marker. The first observation is recorded once by the
-- retention owner, survives reloads, is never taken from the marker's own
-- number, and is never reset by a reload, a read or a repeated observation.
-- Missing, invalid or backward clock evidence never expires anything, removal
-- markers keep their own rules, and opaque, malformed and future markers stay.
-- Real TOC boot, real retention owner and catalog transaction; synthetic data;
-- the local clock is a controlled time() for this test only.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local DAY=86400
local clock=1790000000
local function Clock() time=function() return clock end end
local function Count(t) local n=0;for _ in pairs(t or {})do n=n+1 end;return n end
local function Record(id,extra)
 local r={id=id,title='Synthetic '..id,author='Peer-Realm',class='MAGE',postedAt=1,lastModified=1,
  ordinaryComplete=true,loadoutAvailable=true,lockedEchoes={},lockedComplete=true,
  echoes={{spellId=200001,quality=1,stacks=1},{spellId=200002,quality=2,stacks=1}}}
 for k,v in pairs(extra or {})do r[k]=v end
 return r
end
local H
local function Boot(db) H=F.Boot(db,Clock);return Nexus.BuildCatalog end
local function Reload() H=F.Reload(Clock);return Nexus.BuildCatalog end
local function Run(seconds) for _=1,math.floor((seconds or 20)/0.05) do H.Advance(.05,.05) end end
local function Retention(reason) Nexus.DataRetention.Request(reason or 'test');Run(20) end
local function Bundle() return NexusDB.authorityBundle or {} end
local function FirstSeen() return (Bundle().dataRetention or {}).markerFirstSeen or {} end
local function Markers() return Bundle().communityRetentionEvictions or {} end

-- 1. Recognized legacy numeric markers (upstream 1.96.x / test.18 shape) and
-- a current-format marker written with an untrusted clock (time 0) get one
-- local first observation after the shared catalog is admitted; the marker's
-- own number is not age. Opaque, malformed and future markers get none.
local legacyStamp=clock+500*DAY -- a far-future upstream stamp must not matter
-- A verified saved format 5 carries its account ledger (accountCharacters);
-- without it the profile is read-only and nothing can be written into it.
local db={settingsVersion=5,accountCharacters={},settings={},chars={},communityBuilds={},
 syncTombstones={['both-1']={stamp=1,author='Peer'}},
 communityRetentionEvictions={
  ['legacy-1']=legacyStamp,['legacy-2']=1700000000,['both-1']=1700000001,
  ['untimed-1']={schemaVersion=1,typedId={luaType='string',exactValue='untimed-1'},evictedCatalogGeneration=1,
   evictedSourceIdentity='overlay',evictedProvenanceIdentity='',receiptRevision=1,receiptAtServerTime=0},
  ['opaque-1']={at=1},['malformed-1']='soon',['fraction-1']=1.5,['negative-1']=-3,
  ['future-1']={schemaVersion=2,typedId={luaType='string',exactValue='future-1'},receiptAtServerTime=1},
 }}
local originals=F.Serialize(db.communityRetentionEvictions)
local C=Boot(db)
check(Nexus.StartupStatus().state=='ready','the catalog with 9 retention markers is admitted')
check(Count(FirstSeen())==0,'no first observation is written before the retention owner runs')
local readBefore=F.Serialize(NexusDB)
SlashCmdList.NEXUS('status');Nexus.SupportReport.Summary();C.BarrierState('legacy-1');C.Status()
check(F.Serialize(NexusDB)==readBefore,'status, Copy summary and catalog reads write nothing')
Run(20)
local seen=FirstSeen()
check(seen['legacy-1']==clock and seen['legacy-2']==clock and seen['both-1']==clock and seen['untimed-1']==clock,
 'legacy and untimed markers are first observed now, not at their own number: '..tostring(seen['legacy-1']))
for _,id in ipairs({'opaque-1','malformed-1','fraction-1','negative-1','future-1'})do
 check(seen[id]==nil,id..': an unrecognized marker gets no first observation')
end
check(Count(seen)==4,'the first-observation map holds only the four eligible markers: '..Count(seen))
check(F.Serialize(Markers())==originals,'every original marker value is kept')

-- 2. Reloads and repeated observations never reset the first observation.
clock=clock+DAY
C=Reload();Run(20);Retention('repeat')
check(FirstSeen()['legacy-1']==clock-DAY,'a reload and a repeated observation keep the first observation')

-- 3. Before 30 days nothing expires. A clock that steps backward inside a
-- session is not trusted for the rest of that session, even after it moves
-- past 30 days again.
clock=clock+28*DAY
C=Reload();Retention('day 29')
check(Count(Markers())==9,'nothing expires before 30 days')
clock=clock-2*DAY
Retention('backward')
clock=clock+3*DAY -- 30 days after the first observation, in the same session
Retention('after backward')
check(Count(Markers())==9,'after a backward clock step in the session nothing expires')

-- 4. After 30 days: exactly the four aged markers expire. The removal marker
-- on the same ID stays in force, no build or row is restored, and the
-- opaque, malformed and future markers stay with their evidence.
clock=clock+DAY -- a new session on day 31 (after the 300 s retention fast path)
C=Reload();Retention('day 31')
local left=Markers()
check(left['legacy-1']==nil and left['legacy-2']==nil and left['both-1']==nil and left['untimed-1']==nil,
 'the four aged retention markers expired')
check(Count(left)==5 and left['opaque-1'] and left['malformed-1']=='soon' and left['fraction-1']==1.5
 and left['negative-1']==-3 and left['future-1'],'the five unrecognized markers are kept unchanged')
check(Count(FirstSeen())==0,'the first-observation map shrinks with the expired markers')
check(C.TombstoneState('both-1').state~='NONE' and Bundle().syncTombstones['both-1'],
 'the removal marker on the same ID is kept and still blocks it')
check(C.Get('legacy-1')==nil and C.Status().availableCount==0,'no row was restored by the expiry')
local stats=Nexus.DataRetention.Stats()
check(stats and stats.evictionMarkersRemoved==4,'the retention summary counts four expiries: '..tostring(stats and stats.evictionMarkersRemoved))

-- 5. An expired suppression permits only normal validated consideration of a
-- later candidate: the build is admitted through the ordinary route, while a
-- removal-marked ID stays refused.
local ok,why=C.Put(Record('legacy-2'),{source='sync'})
Run(5)
local okBlocked,whyBlocked=C.Put(Record('both-1'),{source='sync'})
Run(5)
check((ok==true or ok==nil) and C.Get('legacy-2')~=nil,'a later candidate for an expired marker is admitted normally: '..tostring(why))
check(okBlocked==false and whyBlocked=='TOMBSTONE_RESERVATION','a removal-marked ID stays refused: '..tostring(whyBlocked))

-- 6. A marker the eviction writer creates now carries its own local time and
-- expires 30 days after it, across reloads, without a first observation.
local db6={settingsVersion=5,accountCharacters={},settings={},chars={},communityBuilds={}}
for i=1,3 do db6.communityBuilds['auto-'..i]=Record('auto-'..i,{autoDps=true}) end
clock=1800000000
C=Boot(db6);Run(600)
local released,releaseWhy=Nexus.DataRetention.ReleaseSupersededAutoBuild('auto-1')
Run(20)
check((released==true or released==nil) and Markers()['auto-1']~=nil and Bundle().communityBuilds['auto-1']==nil,
 'the real eviction writer evicts an unreferenced received automatic build: '..tostring(released)..' '..tostring(releaseWhy))
local written=Markers()['auto-1']
check(type(written)=='table' and written.receiptAtServerTime==clock,'the new marker carries its local creation time')
C=Reload();Retention('new marker')
check(FirstSeen()['auto-1']==nil,'a marker with its own local time gets no first observation')
clock=clock+30*DAY-60;C=Reload();Retention('almost')
check(Markers()['auto-1']~=nil,'it is kept until 30 days after its local creation time')
clock=clock+600;C=Reload();Retention('expired') -- past the 300 s retention fast path
check(Markers()['auto-1']==nil and Bundle().communityBuilds['auto-2']~=nil,
 'it expires after 30 days; unrelated builds stay')

-- 7. Interrupted maintenance commits nothing: a staged expiry that is
-- cancelled leaves the marker, the first observation and the bundle as they
-- were.
local db7={settingsVersion=5,accountCharacters={},settings={},chars={},communityBuilds={},
 communityRetentionEvictions={['legacy-9']=1700000000}}
clock=1810000000
C=Boot(db7);Run(20)
local firstSeen9=FirstSeen()['legacy-9']
check(firstSeen9==clock,'fixture: the legacy marker was first observed')
clock=clock+31*DAY
C=Reload() -- stage before the automatic retention run of this session
local bundleBefore=F.Serialize(Bundle())
local handle,handleWhy=C.BeginCatalogMaintenance({database=NexusDB,operation='retention'})
local staged,stagedWhy=false,handleWhy
if handle then staged,stagedWhy=C.MaintenanceExpireBarrier(handle,'legacy-9',firstSeen9) end
check(handle and staged,'an expiry is staged: '..tostring(stagedWhy))
check(C.CancelMaintenance(handle),'the maintenance is cancelled before it commits')
check(F.Serialize(Bundle())==bundleBefore,'nothing was committed: marker, first observation and bundle unchanged')
local late,lateWhy=C.CommitMaintenance(handle)
check(late~=true and F.Serialize(Bundle())==bundleBefore,'the cancelled handle cannot commit later: '..tostring(lateWhy))
Run(20)
check(Markers()['legacy-9']==nil and FirstSeen()['legacy-9']==nil,
 'the session retention run expires it through its own transaction')

-- 8. A clock that is not trusted at the first observation records nothing,
-- and nothing expires without age.
local db8={settingsVersion=5,accountCharacters={},settings={},chars={},communityBuilds={},
 communityRetentionEvictions={['legacy-8']=1700000000}}
clock=1820000000
C=Boot(db8)
time=function() return nil end
Run(20)
check(FirstSeen()['legacy-8']==nil and Markers()['legacy-8']~=nil,'an untrusted clock records no first observation and expires nothing')
print('PASS catalog_marker_expiry: local first observation, reload and repeat stability, 30-day boundary, backward and untrusted clocks, removal marker kept, no restore, unrecognized markers kept, writer-dated markers, cancelled maintenance checks='..checks)
