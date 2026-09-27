-- Legacy qualification repair: cases that each boot their own session.
-- Real TOC boot, real owners (DpsCapture, BuildCatalog, Revisions,
-- Scheduler, ViewRefresh, LegacyQualificationRepair); synthetic data only.
-- Saved legacy rows (protocol 5, complete evidence, no catalog build) are
-- real recovery candidates. Sections: 1 initial repair, 9 catalog refusal
-- and automatic retry, 11b reload with staged writes, 13 store replaced
-- during classification, 9c exhausted catalog authority, 9d incomplete
-- cursor, 9e saved root replaced after completion, 12b removal markers,
-- 10 read-only profile. The main-session sections
-- are in legacy_repair_progress_fairness.lua; the two files share this
-- helper block.
--
-- Assertions count operations and scheduled work; no wall-clock threshold.
-- Modeled inputs, stated where used: a refused catalog publication (sections
-- 9 and 11b, fault injection at the catalog boundary), a replaced DPS store
-- (13), a saved counter one step below its maximum (9c), a withheld cursor
-- result (9d, defensive injection), a replaced saved root (9e, defensive
-- injection; the catalog rebinds through its real path) and saved removal
-- markers (12b). LRP_N sets the number of filler characters for section 13
-- (default 240).
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local N=tonumber(os.getenv('LRP_N') or '') or 240
local K=6
local FPS=60
-- Time windows scale with the data size (1 at the default size): passes,
-- fairness gaps and catalog admission all grow with the number of rows.
local S=math.max(1,N/240)
local FOLLOWUP='legacy-qualification-repair.follow-up'
local checks=0
local function check(v,m) if not v then error(m,2) end;checks=checks+1 end

local function Players(n)
 local list={{name='PrototypeTester',class='MAGE',dps={lk=39000,dummy=38000},isLocal=true,variant=30,ordinary=60},
  {name='Alpha',class='MAGE',dps={lk=52000,dummy=48000},variant=10,ordinary=60}}
 for i=1,K do list[#list+1]={name='Legacy'..i,class='MAGE',build='missing',variant=400+i,ordinary=60,dps={lk=30000+i,dummy=29000+i}} end
 for i=1,n do list[#list+1]={name='Filler'..i,class='PRIEST',variant=100+i,dps={lk=20000+i,dummy=19000+i}} end
 return list
end
local function DeepCopy(v,seen)
 if type(v)~='table' then return v end
 seen=seen or {};if seen[v] then return seen[v] end
 local o={};seen[v]=o
 for k,x in pairs(v)do o[DeepCopy(k,seen)]=DeepCopy(x,seen) end
 return o
end
local H,fx,R
local function Frames(n,each) for i=1,n do if each then each(i) end;H.Advance(1/FPS,1/FPS) end end
local function Stats() return R.Stats() end
-- Legacy characters whose exact loadout resolves to a recovered legacy build.
local function LegacyRecovered()
 local out,cat={n=0},Nexus.BuildCatalog
 for _,p in ipairs(fx.players)do if p.name:match('^Legacy') then
  local id=cat.FindExactFingerprintId(p.fingerprint)
  if id and tostring(id):match('^legacy%-dps%-') then out[p.name]=id;out.n=out.n+1 end
 end end
 return out
end
local function CurrentRevision() return Nexus.Revisions.Get(Nexus.Revisions.DPS_CHANGED) end
local function Meta() return NexusDB.legacyQualificationRepair or {} end
local function Boot(opts)
 opts=opts or {}
 fx=L.New({players=opts.players or Players(opts.n or N)})
 for _,cat in ipairs({'lk','dummy'})do for owner,row in pairs(fx.rows[cat])do if owner:match('^legacy') then row.protocolVersion=5 end end end
 local db=fx:Install(F.Database({version=2}))
 if opts.mutate then opts.mutate(db) end
 F.fileHooks=opts.fileHooks
 H=F.Boot(db,function(h) h.playerLevel=60 end)
 F.fileHooks=nil
 R=Nexus.LegacyQualificationRepair
end
-- Until the repair is idle with no follow-up pending.
local function Settle(limit)
 for _=1,math.floor((limit or 6000)*S) do
  H.Advance(1/FPS,1/FPS)
  local st=Stats()
  if not st.pending and not st.followUpPending then return true end
 end
 local st=Stats()
 print('LRP settle-timeout','pending',tostring(st.pending),'followUp',tostring(st.followUpPending),'last',tostring(st.lastReason),'jobs',st.jobs)
 return false
end

------------------------------------------------------------------------
-- 1. Initial repair, no incoming changes: one pass recovers every legacy
-- candidate once, publishes once, stamps the covered revision, then idles;
-- repeated requests at the current revision start nothing.
Boot({n=40})
check(Settle(),'1: the start-up repair settles')
local s=Stats()
check(s.recovered==K and LegacyRecovered().n==K,'1: every legacy candidate is recovered once: '..s.recovered..' / '..LegacyRecovered().n)
check(s.restarts==0 and s.published==1 and s.jobs==1,'1: one pass, one publication: restarts='..s.restarts..' published='..s.published..' jobs='..s.jobs)
check(s.completedDpsRevision==CurrentRevision() and Meta().completedDpsRevision==CurrentRevision(),'1: the completed revision is the current one')
local jobs,pumps=s.jobs,s.pumps
Frames(10*FPS)
s=Stats()
check(s.jobs==jobs and s.pumps==pumps and not s.pending,'1: idle: no pass and no pump without changes')
for key,value in pairs(Stats())do
 check(type(value)~='table' and type(value)~='function','1: Stats() reports scalars only (it is copied on every read): '..tostring(key))
end
for _=1,20 do R.Request('refresh') end
check(Stats().jobs==jobs and Stats().lastReason=='current','6: repeated requests at the current revision start nothing')

------------------------------------------------------------------------
-- 9. Catalog refusal (fault injection: PublishDeferred refuses). The pass
-- stages its writes but publishes nothing and stamps nothing; the next pass
-- after the refusal is lifted publishes the staged writes, and nothing is
-- recovered twice.
do
 local refuse=true
 Boot({n=40,fileHooks={[ [[core\BuildCatalog.lua]] ]=function()
  local publish=Nexus.BuildCatalog.PublishDeferred
  Nexus.BuildCatalog.PublishDeferred=function(...)
   if refuse then return false,'REFUSED (test)' end
   return publish(...)
  end
 end}})
 for _=1,20*FPS do if Stats().failures>0 or (Stats().passesCompleted or 0)>0 then break end;Frames(1) end
 local r=Stats()
 check(r.failures>=1 and r.completedDpsRevision==nil and Meta().inProgress==true,
  '9: a refused publication stamps nothing: failures='..r.failures..' completed='..tostring(r.completedDpsRevision))
 refuse=false
 check(Stats().followUpPending and Nexus.Scheduler.Pending(FOLLOWUP)~=nil,'9: the refused pass schedules its own retry')
 check(Settle(),'9: the retry settles once publication is accepted (no manual request)')
 r=Stats()
 check(r.completedDpsRevision==CurrentRevision() and r.published>=1 and not Meta().inProgress,
  '9: the staged writes are published by the next pass: published='..r.published)
 check(LegacyRecovered().n==K,'9: every candidate recovered exactly once: '..LegacyRecovered().n)
end

------------------------------------------------------------------------
-- 11b. Reload while the refused pass's writes are staged but unpublished: the
-- next session publishes them once and recovers nothing twice.
do
 Boot({n=40,fileHooks={[ [[core\BuildCatalog.lua]] ]=function()
  Nexus.BuildCatalog.PublishDeferred=function() return false,'REFUSED (test)' end
 end}})
 for _=1,20*FPS do if Stats().failures>0 then break end;Frames(1) end
 check(Meta().inProgress==true and (tonumber(Meta().pendingWrites) or 0)==K,'11b: setup: K writes staged, none published: '..tostring(Meta().pendingWrites))
 H.Fire('PLAYER_LOGOUT')
 H=L.Reload(F,function(h) h.playerLevel=60 end)
 R=Nexus.LegacyQualificationRepair
 check(Settle(),'11b: the next session settles')
 local r=Stats()
 check(r.published>=1 and not Meta().inProgress and LegacyRecovered().n==K,'11b: the staged writes are published once: published='..r.published..' recovered '..LegacyRecovered().n)
 check(r.completedDpsRevision==CurrentRevision(),'11b: and the new session completes its own revision')
end

------------------------------------------------------------------------
-- 13. The DPS store is replaced during classification without a DPS revision
-- (modeled: the saved dpsCapture payload is replaced by a deep copy, as a
-- compaction commit with no changed row does). The pass starts over on the
-- current store; it does not skip every candidate and stamp itself complete.
-- (Default size: at 40 fillers the start-up pass finishes during boot.)
do
 Boot()
 for _=1,20000 do
  local root=Nexus.BuildCatalog.RootState and Nexus.BuildCatalog.RootState() or nil
  if not (type(root)=='table' and root.candidate==true) then break end
  H.Advance(1,.05)
 end
 local swapped=false
 for _=1,math.floor(60*FPS*S) do
  if not swapped and Stats().pending and Meta().phase=='classify' then
   local bundle=rawget(NexusDB,'authorityBundle')
   local rev=CurrentRevision()
   if type(bundle)=='table' and type(rawget(bundle,'dpsCapture'))=='table' then
    rawset(bundle,'dpsCapture',DeepCopy(rawget(bundle,'dpsCapture')))
   else
    NexusDB.dpsCapture=DeepCopy(NexusDB.dpsCapture)
   end
   swapped=CurrentRevision()==rev
  end
  if swapped and not Stats().pending and not Stats().followUpPending then break end
  Frames(1)
 end
 check(swapped,'13: setup: the store was replaced during classification without a DPS revision')
 check(Settle(),'13: the repair settles after the store replacement')
 local r=Stats()
 check(LegacyRecovered().n==K,'13: every legacy candidate is still recovered: '..LegacyRecovered().n)
 check(r.completedDpsRevision==CurrentRevision() and (r.restarts or 0)>=1,'13: the pass started over and then completed: restarts='..tostring(r.restarts))
end

------------------------------------------------------------------------
-- 9c. Exhausted catalog authority (a saved durable counter one step below
-- its maximum: the repair's own catalog write exhausts it). Every later write
-- is refused until a fresh session, so the repair fails closed: at most one
-- failed pass, no stamp, no follow-up loop, the catalog state names the
-- cause. The first session only prepares the saved root (repair held back by
-- a load hook on the repair owner).
do
 Boot({n=40,fileHooks={[ [[core\LegacyQualificationRepair.lua]] ]=function()
  Nexus.LegacyQualificationRepair.Request=function() return true,'held (test)' end
 end}})
 Frames(10*FPS)
 local bundle=rawget(NexusDB,'authorityBundle')
 check(type(bundle)=='table','9c: setup: the saved authority bundle exists')
 bundle.transactionGeneration=9007199254740991-1
 H.Fire('PLAYER_LOGOUT')
 H=L.Reload(F,function(h) h.playerLevel=60 end)
 R=Nexus.LegacyQualificationRepair
 Frames(120*FPS)
 local r=Stats()
 local root=Nexus.BuildCatalog.RootState()
 print('LRP exhausted','catalog',tostring(root.state),'jobs',r.jobs,'failures',r.failures,'followUps',r.followUps,'last',tostring(r.lastReason))
 check(root.state=='AUTHORITY_GENERATION_EXHAUSTED','9c: setup: the catalog authority is exhausted: '..tostring(root.state))
 check(r.jobs<=2 and (r.passesCompleted or 0)==0,'9c: an exhausted authority is not retried pass after pass: jobs='..r.jobs)
 check(r.completedDpsRevision==nil and Meta().completedDpsRevision==nil,'9c: nothing is stamped complete')
 check(not r.pending and not r.followUpPending and Nexus.Scheduler.Pending(FOLLOWUP)==nil,'9c: no pass and no follow-up remain scheduled')
 check(r.lastReason=='GENERATION_EXHAUSTED','9c: the cause is reported: '..tostring(r.lastReason))
 check(LegacyRecovered().n==0,'9c: nothing is recovered into an exhausted catalog')
 local jobs=r.jobs
 for _=1,5 do R.Request('refresh');Frames(FPS) end
 check(Stats().jobs==jobs and select(2,R.Request('refresh'))=='catalog-exhausted','9c: later requests start nothing')
end

------------------------------------------------------------------------
-- 9d. Incomplete cursor (defensive injection: the cursor result is withheld
-- once; no product route reaches this exit, because the scan's last step and
-- the result read happen in one call). The pass stamps nothing, one follow-up
-- is scheduled, and the repair converges once the fault is gone.
do
 local withhold=true
 Boot({n=40,fileHooks={[ [[core\DpsCapture.lua]] ]=function()
  local result=Nexus.DpsCapture.LegacyQualificationCursorResult
  Nexus.DpsCapture.LegacyQualificationCursorResult=function(...)
   if withhold then withhold=false;return nil end
   return result(...)
  end
 end}})
 for _=1,60*FPS do if not withhold then break end;Frames(1) end
 local r=Stats()
 check(not withhold and r.lastReason=='cursor-incomplete','9d: setup: the start-up pass hit the incomplete cursor: '..tostring(r.lastReason))
 check(r.completedDpsRevision==nil and (r.passesCompleted or 0)==0,'9d: an incomplete pass stamps nothing')
 local scheduled=0;for _,task in ipairs(Nexus.Scheduler.Pending())do if task.key==FOLLOWUP then scheduled=scheduled+1 end end
 check(r.followUpPending and scheduled==1,'9d: exactly one follow-up is scheduled: '..scheduled)
 check(Settle(),'9d: the follow-up runs and the repair settles')
 r=Stats()
 check(r.completedDpsRevision==CurrentRevision() and LegacyRecovered().n==K,'9d: converged: every candidate recovered, current revision stamped: '..LegacyRecovered().n)
end

------------------------------------------------------------------------
-- 9e. The saved root is replaced after a completed pass (defensive injection:
-- no product writer replaces NexusDB after the start-up binding) and the
-- catalog rebinds to it through its real rebind path, with the DPS revision
-- number unchanged. The completion of the old root does not count for the
-- new one: a pass runs on the new root and recovers its candidates.
do
 Boot({n=40})
 check(Settle(),'9e: setup: the first root is repaired')
 local rev=CurrentRevision()
 local fx2=L.New({players=Players(40)})
 for _,cat in ipairs({'lk','dummy'})do for owner,row in pairs(fx2.rows[cat])do if owner:match('^legacy') then row.protocolVersion=5 end end end
 local second=fx2:Install(F.Database({version=2}))
 NexusDB=second
 for _=1,20*FPS do
  local cat=Nexus.BuildCatalog
  if cat.BoundDatabase()==second and cat.RootState().state=='ROOT_ADMITTED' and not cat.RootState().candidate then break end
  Frames(1)
 end
 check(Nexus.BuildCatalog.BoundDatabase()==second,'9e: setup: the catalog is bound to the new root')
 print('LRP rootswap','revisionBefore',rev,'revisionAfter',CurrentRevision())
 fx=fx2
 R.Request('refresh')
 check(Settle(),'9e: the repair settles on the new root')
 check(LegacyRecovered().n==K,'9e: the new root\'s candidates are recovered: '..LegacyRecovered().n)
 check(Stats().completedDpsRevision==CurrentRevision(),'9e: the new root completes its own revision')
end

------------------------------------------------------------------------
-- 12b. Removal markers (the durable outcome of a deletion) for one
-- candidate's referenced build and for another candidate's historical build
-- ID. Neither is recovered by the start-up pass, by a later pass, or after a
-- reload; the markers stay. (No supported path can add such a marker during a
-- pass: a recovered build has no owner and a candidate's referenced build is
-- absent, so the catalog refuses a local or remote removal of either.)
do
 local function HashText(value,seed)
  local hash=seed
  for i=1,#value do hash=(hash*33+value:byte(i))%2147483648 end
  return string.format('%x',hash)
 end
 local function HistoricalId(fingerprint)
  return 'legacy-dps-'..HashText(fingerprint,5381)..'-'..HashText(fingerprint,216613626)
 end
 local players=Players(40)
 for _,p in ipairs(players)do if p.name=='Legacy1' then p.build='tombstone' end end
 local removedRef,removedId,second
 Boot({players=players,mutate=function(db)
  for _,p in ipairs(fx.players)do
   if p.name=='Legacy1' then removedRef=p.buildId end
   if p.name=='Legacy2' then second=p end
  end
  removedId=HistoricalId(second.fingerprint)
  db.syncTombstones=db.syncTombstones or {}
  db.syncTombstones[removedId]={stamp=L.STAMP-7200,author='Legacy2'}
 end})
 local function Markers()
  local bundle=rawget(NexusDB,'authorityBundle')
  return type(bundle)=='table' and rawget(bundle,'syncTombstones') or NexusDB.syncTombstones or {}
 end
 local function NotResurrected(tag)
  local rec=LegacyRecovered()
  local cat=Nexus.BuildCatalog
  check(rec.Legacy1==nil and rec.Legacy2==nil and rec.n==K-2,
   tag..': neither removed identity is recovered: '..rec.n)
  local suffixed=false
  for i=1,64 do if cat.Get(removedId..'-'..i) then suffixed=true end end
  check(cat.Get(removedId)==nil and not suffixed and cat.FindExactFingerprintId(second.fingerprint)==nil,
   tag..': the removed historical ID is not re-created under any ID')
  local markers=Markers()
  check(markers[removedRef]~=nil and markers[removedId]~=nil,tag..': both removal markers remain')
 end
 check(Settle(),'12b: the start-up repair settles')
 check((Stats().deferredStaleOrSuperseded or 0)>=2,'12b: both candidates are left as removed: '..tostring(Stats().deferredStaleOrSuperseded))
 NotResurrected('12b start-up pass')
 local filler
 for _,p in ipairs(fx.players)do if p.name=='Filler1' then filler=p end end
 filler.dps.dummy=filler.dps.dummy+1
 assert(fx:Receive('Filler1','dummy',{dps=filler.dps.dummy,ts=time()-1}),'fixture: record accepted')
 Frames(10*FPS)
 check(Settle(),'12b: the later pass settles')
 check((Stats().passesCompleted or 0)>=2,'12b: a later pass ran: '..tostring(Stats().passesCompleted))
 NotResurrected('12b later pass')
 H.Fire('PLAYER_LOGOUT')
 H=L.Reload(F,function(h) h.playerLevel=60 end)
 R=Nexus.LegacyQualificationRepair
 check(Settle(),'12b: the next session settles')
 check(Stats().jobs>=1,'12b: the next session ran its own pass')
 NotResurrected('12b after reload')
end

------------------------------------------------------------------------
-- 10. A protected (read-only) saved profile is never repaired.
do
 Boot({n=40,mutate=function(db) db.settingsVersion=6 end})
 Frames(10*FPS)
 local r=Stats()
 check(r.jobs==0 and r.lastReason=='read-only-saved-data','10: a read-only profile is not repaired: '..tostring(r.lastReason))
 check(LegacyRecovered().n==0,'10: nothing is written into a read-only profile')
end

print('PASS legacy_repair_boot_cases: initial repair, catalog refusal and retry, reload with staged writes, store replacement during classification, exhausted authority, incomplete cursor, root replacement, removal markers, read-only profile checks='..checks)
