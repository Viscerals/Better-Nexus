-- Opt-in ranked retention (settings.communityRetentionEnabled) and the one
-- shared summary cursor. The ranked run scans the overlay summaries first;
-- the build hash warm-up, the Community view and any commit can end that
-- scan. Retention-marker aging and removal markers do not need the scan:
-- when it cannot complete, a marker-only pass runs in its own transaction and
-- writes only the retention metadata. A busy marker pass is retried inside
-- the bounded busy chain without another scan, so other summary readers are
-- not restarted again. A ranked run writes dpsCapture only when it removed
-- DPS rows, so a DPS record written while its commit is pending is kept.
-- Real TOC boot, real scheduler, catalog, hash warm-up and retention owner;
-- synthetic data; the local clock is a controlled time() for this test only.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local DAY=86400
local clock=1790000000
local offset=0
local Hh
local function Clock(h) Hh=h;time=function() return clock+offset+math.floor(h.now) end end
local function Count(t) local n=0;for _ in pairs(t or {})do n=n+1 end;return n end
local function Record(id)
 return {id=id,title='Synthetic '..id,author='Peer'..id:gsub('%W','')..'-Realm',class='MAGE',postedAt=1,lastModified=1,
  ordinaryComplete=true,loadoutAvailable=true,lockedEchoes={},lockedComplete=true,
  echoes={{spellId=200001,quality=1,stacks=1},{spellId=200002,quality=2,stacks=1}}}
end
local function RankedDb(rows,extra)
 local db={settingsVersion=5,settings={communityRetentionEnabled=true},chars={},communityBuilds={},
  communityRetentionEvictions={['legacy-1']=1700000000,['legacy-2']=1700000001}}
 for i=1,rows do db.communityBuilds['b-'..i]=Record('b-'..i) end
 for k,v in pairs(extra or {})do db[k]=v end
 return db
end
local H
local function Run(seconds,step) step=step or .5;for _=1,math.floor(seconds/step) do H.Advance(step,step) end end
local function Bundle() return NexusDB.authorityBundle or {} end
local function Seen() return (Bundle().dataRetention or {}).markerFirstSeen or {} end
local function Settle(ok,why,ticket)
 if ok==nil and type(ticket)=='table' then
  for _=1,8000 do H.Advance(.05,.05) if ticket.state~='pending' then break end end
  return ticket.committed==true,ticket.reason or why
 end
 return ok,why
end
-- Count summary-cursor starts by the retention owner.
local retentionScans=0
local function HookCursor()
 local C=Nexus.BuildCatalog;local begin=C.BeginSummaryCursor
 C.BeginSummaryCursor=function(...)
  local info=debug.getinfo(2,'S')
  if info and tostring(info.source):find('DataRetention',1,true) then retentionScans=retentionScans+1 end
  return begin(...)
 end
end

-- 1. Start-up: the ranked scan loses the summary cursor to the hash warm-up.
-- The first observations are still recorded; no build is removed.
F.fileHooks={[ [[core\DataRetention.lua]] ]=HookCursor}
H=F.Boot(RankedDb(40),Clock);F.fileHooks=nil
local C,R=Nexus.BuildCatalog,Nexus.DataRetention
Run(120)
check(Count(Seen())==2 and Seen()['legacy-1']~=nil and Seen()['legacy-2']~=nil,
 'ranked start-up records both first observations: '..Count(Seen()))
check(Count(Bundle().communityBuilds)==40,'no build was removed by the marker pass')
local cache=Nexus.BuildHashCache and Nexus.BuildHashCache.Stats and Nexus.BuildHashCache.Stats() or {}
check(cache.phase=='ready' and (cache.warmRestarts or 0)<=1,
 'the hash warm-up completes (restarts '..tostring(cache.warmRestarts)..')')
local last=(Bundle().dataRetention or {}).last or {}
check(last.overlayScanIncomplete~=nil and (last.overlayRemoved or 0)==0,
 'the recorded run is the marker pass after an incomplete scan: '..tostring(last.overlayScanIncomplete))

-- 2. A commit during a later ranked scan ends it ("catalog changed"). The
-- marker pass still runs: after 30 days both markers expire, no build is
-- removed, and the first observations leave with their markers.
offset=31*DAY
local committed,scanSeen=false,false
local enforce=R.Enforce
R.Enforce=function(database,reason)
 local result=enforce(database,reason)
 if reason=='test: scan meets a commit' and type(result)=='table' and result.pending==true
  and result.workDomain=='retention-overlay-scan' and not scanSeen then
  scanSeen=true
  committed=Settle(C.Put(Record('late-1'),{source='sync'}))
 end
 return result
end
check(R.Request('test: scan meets a commit')==true,'fixture: a ranked run is requested after the warm-up')
Run(120)
R.Enforce=enforce
check(scanSeen and committed,'fixture: a real commit landed while the ranked scan was in progress')
check(Count(Bundle().communityRetentionEvictions)==0 and Count(Seen())==0,
 'the marker pass expired both 31-day-old markers and their first observations')
check(Count(Bundle().communityBuilds)==41 and C.Get('late-1')~=nil,'no build was removed; the committed build is kept')
last=(Bundle().dataRetention or {}).last or {}
check(last.overlayScanIncomplete~=nil and last.evictionMarkersRemoved==2,
 'the expiry came from the marker pass: '..tostring(last.overlayScanIncomplete))

-- 3. A DPS record written into the live DPS store while a ranked retention
-- commit is pending is kept (the run removed no DPS rows, so it writes no
-- dpsCapture). The complete ranked run has a change to commit: 31 days
-- later it expires both markers.
offset=0
H=F.Boot(RankedDb(40),Clock)
C,R=Nexus.BuildCatalog,Nexus.DataRetention
Run(90)
check(Count(Seen())==2,'fixture: the first observations are recorded at start-up')
offset=31*DAY
local wrote=false
enforce=R.Enforce
R.Enforce=function(database,reason)
 local result=enforce(database,reason)
 if reason=='test: pending commit' and not wrote and type(result)=='table' and result.pending==true and result.mutationTicket then
  local live=rawget(NexusDB.authorityBundle,'dpsCapture')
  live.characterBest=live.characterBest or {}
  live.characterBest.probeRow={probe=true}
  wrote=true
 end
 return result
end
check(R.Request('test: pending commit')==true,'fixture: a ranked run is requested')
Run(120)
R.Enforce=enforce
local dps=rawget(Bundle(),'dpsCapture') or {}
check(wrote,'fixture: a DPS row was written while the retention commit was pending')
check(type(dps.characterBest)=='table' and dps.characterBest.probeRow~=nil,
 'the DPS row written during the pending retention commit is kept')
check(Count(Bundle().communityRetentionEvictions)==0 and ((Bundle().dataRetention or {}).last or {}).overlayScanIncomplete==nil,
 'fixture: the committed run was a complete ranked run that expired both markers')
offset=0

-- 4. A busy catalog during the marker pass: the busy retry repeats the marker
-- pass without starting another overlay scan, and records once the catalog is
-- free.
local busyUntil
F.fileHooks={[ [[core\DataRetention.lua]] ]=function()
 HookCursor()
 local catalog=Nexus.BuildCatalog;local begin=catalog.BeginCatalogMaintenance
 catalog.BeginCatalogMaintenance=function(request)
  if Hh and busyUntil and Hh.now<busyUntil and type(request)=='table' and request.operation=='retention' then
   return nil,'ROOT_MUTATION_PENDING'
  end
  return begin(request)
 end
end}
retentionScans=0
H=F.Boot(RankedDb(40),function(h) Clock(h);busyUntil=h.now+400 end);F.fileHooks=nil
C,R=Nexus.BuildCatalog,Nexus.DataRetention
Run(380)
check(Count(Seen())==0,'fixture: nothing is recorded while the catalog stays busy')
local scansWhileBusy=retentionScans
check(scansWhileBusy<=2,'busy retries start no new overlay scans: '..scansWhileBusy..' scans')
Run(200)
check(Count(Seen())==2,'after the busy period the retried marker pass records both first observations: '..Count(Seen()))
check(retentionScans==scansWhileBusy,'the retried marker pass started no scan: '..retentionScans)

-- 5. Positive control: a complete ranked run that removes DPS rows still
-- writes them. 20 personal-best fingerprints with a limit of 16 keep 16,
-- also after a reload.
local personal={}
for i=1,20 do personal['fp-'..i]={lk={dps=1000+i,recordedAt=1700000000+i}} end
local db5=RankedDb(10,{dpsCapture={personalBest=personal,buildBest={},characterBest={}}})
db5.settings.communityRetentionPersonalFingerprints=16
db5.communityRetentionEvictions=nil
H=F.Boot(db5,Clock)
C,R=Nexus.BuildCatalog,Nexus.DataRetention
local before=Count((rawget(Bundle(),'dpsCapture') or {}).personalBest)
check(before==20,'fixture: 20 personal-best fingerprints are loaded: '..before)
Run(90)
-- The start-up run leaves its scan job open (a known, separate behavior), so
-- the first request can end as a marker pass; a later request scans afresh.
local stats,requests={},0
repeat
 requests=requests+1
 check(R.Request('test: complete ranked run')==true,'fixture: a ranked run is requested')
 Run(120)
 stats=R.Stats(NexusDB) or {}
until (stats.overlayScanIncomplete==nil and stats.personalRemoved~=nil) or requests>=3
check(requests<=2,'a complete ranked run happens by the second request: '..requests)
check((stats.personalRemoved or 0)==4 and stats.overlayScanIncomplete==nil,
 'a complete ranked run removed 4 fingerprints: '..tostring(stats.personalRemoved))
check(Count((rawget(Bundle(),'dpsCapture') or {}).personalBest)==16,'the removal is written to the saved DPS store')
H=F.Reload(Clock)
check(Count((rawget(Bundle(),'dpsCapture') or {}).personalBest)==16,'the removal persists after a reload')
print('PASS retention_ranked_marker_pass: marker pass after a lost scan (start-up contention, commit during scan), busy retry without new scans, DPS write during a pending commit kept, DPS trimming still written checks='..checks)
