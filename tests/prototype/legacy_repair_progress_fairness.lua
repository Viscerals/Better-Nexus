-- Legacy qualification repair and data-view refresh under sustained DPS
-- activity. Real TOC boot, real owners (DpsCapture, BuildCatalog, Revisions,
-- Scheduler, ViewRefresh, LegacyQualificationRepair), real inbound DPS
-- records; synthetic data only. Saved legacy rows (protocol 5, complete
-- evidence, no catalog build) are real recovery candidates.
--
-- A repair pass covers the stored rows captured when it starts. A newer DPS
-- revision does not discard it: every candidate is revalidated before a write,
-- the completion stamp names only the covered revision, and one coalesced
-- follow-up pass, started no sooner than a fairness gap, covers what changed.
-- The data views refresh from committed data while the repair is pending, and
-- a receive window holds them back for a bounded time only.
--
-- Assertions count operations and scheduled work; no wall-clock threshold.
-- Modeled inputs, stated where used: a continuously open Sync receive window
-- (section 8) and a refused catalog publication (section 9, fault injection
-- at the catalog boundary). LRP_N sets the number of filler characters for
-- the main boot (default 240; the preserved large case, 2000, runs outside the
-- inventory because its start-up alone exceeds the per-test time limit).
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local N=tonumber(os.getenv('LRP_N') or '') or 240
local K=6
local FPS=60
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
local function Wishlist(ord) local o={};for i,r in ipairs(ord)do o[i]={spellId=r.spellId,quality=r.quality,stacks=r.stacks}end;return o end

local H,fx,R
local function Frames(n,each) for i=1,n do if each then each(i) end;H.Advance(1/FPS,1/FPS) end end
local function Stats() return R.Stats() end
local function Player(name) for _,p in ipairs(fx.players)do if p.name==name then return p end end end
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
 fx=L.New({players=Players(opts.n or N)})
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
 for _=1,limit or 6000 do
  H.Advance(1/FPS,1/FPS)
  local st=Stats()
  if not st.pending and not st.followUpPending then return true end
 end
 local st=Stats()
 print('LRP settle-timeout','pending',tostring(st.pending),'followUp',tostring(st.followUpPending),'last',tostring(st.lastReason),'jobs',st.jobs)
 return false
end
local alphaDps=48000
local function AlphaImproves(tag)
 alphaDps=alphaDps+500
 local ok,why=fx:Receive('Alpha','dummy',{dps=alphaDps,ts=L.STAMP+900+math.floor(alphaDps/500)})
 assert(ok,'fixture: Alpha record accepted ('..tostring(why)..') '..tostring(tag))
end
local function ShownAlpha()
 local model=Nexus.Panel and Nexus.Panel._lastModel
 local perf=model and model.progress and model.progress.performance
 local row=perf and perf.dummy and perf.dummy.global
 return row and tonumber(row.dps) or nil
end
-- A relevant change, then frames until the pass it causes is running (the
-- view refresh requests it; the fairness gap may delay it).
local function StartPass()
 AlphaImproves('pass start')
 for _=1,20*FPS do if Stats().pending then return true end;Frames(1) end
 return Stats().pending
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
 Frames(8*FPS)
 R.Request('refresh')
 check(Settle(),'9: the next pass settles once publication is accepted')
 r=Stats()
 check(r.completedDpsRevision==CurrentRevision() and r.published>=1 and not Meta().inProgress,
  '9: the staged writes are published by the next pass: published='..r.published)
 check(LegacyRecovered().n==K,'9: every candidate recovered exactly once: '..LegacyRecovered().n)
end

------------------------------------------------------------------------
-- Main boot. 4 + 5 + 12 happen during the start-up pass, while the legacy
-- candidates are still unrecovered: a relevant update during its scan and
-- during its classification, a new stored row after its scope was captured,
-- and a legacy candidate's row replaced by a newer record.
Boot()
local injected={}
local legacy5=Player('Legacy5')
local passRevision
-- Read-only observation of the real cursor: which rows each pass scanned.
local scannedByPass={}
do
 local dps=Nexus.DpsCapture
 local realNext=dps.LegacyQualificationCursorNext
 dps.LegacyQualificationCursorNext=function(cursor)
  local item,done,err=realNext(cursor)
  if item and type(item.row)=='table' then
   local pass=(Stats().passesCompleted or 0)+1
   scannedByPass[pass]=scannedByPass[pass] or {}
   scannedByPass[pass][tostring(item.row.player)]=true
  end
  return item,done,err
 end
end
for _=1,60*FPS do
 local phase=Meta().phase
 if Stats().pending and phase=='scan' and not injected.scan then
  injected.scan=true
  passRevision=Meta().requestedDpsRevision
  AlphaImproves('during scan')
  injected.newcomer=Nexus.DpsCapture.ReceiveRecord({v=7,c='dummy',d=33333,u=180,t=time()-5,p='Newcomer',l=80,k='MAGE',
   o='newcomer@ebonhold',r='Ebonhold',e=L.Copy(fx.players[2].dpsOrdinary),f=fx.players[2].fingerprint,
   lk=L.Copy(fx.players[2].dpsLocked)},'Newcomer-Ebonhold')
  injected.replaced=fx:Receive('Legacy5','dummy',{dps=legacy5.dps.dummy+1000,ts=time()-4})
 elseif Stats().pending and phase=='classify' and injected.scan and not injected.classify then
  injected.classify=true
  AlphaImproves('during classification')
 end
 if injected.classify and not Stats().pending then break end
 Frames(1)
end
s=Stats()
print('LRP startup-pass','scan',tostring(injected.scan),'classify',tostring(injected.classify),'newcomer',tostring(injected.newcomer),
 'replaced',tostring(injected.replaced),'skippedChanged',s.changedSkipped,'stalePasses',s.stalePasses,
 'completed',tostring(s.completedDpsRevision),'passRevision',tostring(passRevision),'current',CurrentRevision())
check(injected.scan and injected.classify and injected.newcomer and injected.replaced,'4: updates arrived during scan and classification')
check(s.restarts==0 and s.passesCompleted==1,'4: the pass completes without a restart: restarts='..s.restarts)
check(scannedByPass[1] and scannedByPass[1].Alpha and not scannedByPass[1].Newcomer,
 '5: a row stored after the pass began is outside its scope')
check(s.completedDpsRevision==passRevision and s.completedDpsRevision~=CurrentRevision(),
 '4: the stamp names the covered revision, not the latest: '..tostring(s.completedDpsRevision)..' vs '..tostring(CurrentRevision()))
check((s.changedSkipped or 0)>=1,'12: the replaced candidate was left to the follow-up: '..s.changedSkipped)
local rec=LegacyRecovered()
check(rec.n==K-1 and rec.Legacy5==nil,'12: nothing is recovered from the replaced row: '..rec.n..' Legacy5='..tostring(rec.Legacy5))
check(s.followUpPending and Nexus.Scheduler.Pending(FOLLOWUP)~=nil,'5: one follow-up pass is scheduled for the newer rows')
check(Settle(40*FPS),'5: the follow-up pass runs and completes')
s=Stats()
check(s.completedDpsRevision==CurrentRevision() and s.passesCompleted==2,'5: the follow-up covers the newer rows: passes='..s.passesCompleted)
check(scannedByPass[2] and scannedByPass[2].Newcomer,'5: the follow-up scans the newer row')
rec=LegacyRecovered()
check(rec.n==K-1 and rec.Legacy5==nil,'12: no stale recovery after the follow-up either: '..rec.n)
check(s.published==1,'12: one publication; nothing published twice: '..s.published)

-- Show the HUD on Alpha's exact set (Auto OFF), so its global row is visible.
assert(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Alpha set',Wishlist(fx.players[2].ordinary)))
H.Board({{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200021,quality=1}});H.Notify()
for _=1,4 do Nexus.RequestRecompute();Frames(20) end
for _=1,10*FPS do if ShownAlpha()==alphaDps then break end;Frames(1) end
check(ShownAlpha()==alphaDps,'setup: the HUD shows Alpha\'s current global row: '..tostring(ShownAlpha()))

------------------------------------------------------------------------
-- 2 + 7. Sustained relevant DPS updates, one every second (faster than one
-- pass): passes complete, nothing restarts, at most one follow-up is ever
-- scheduled, and the HUD catches up with each new value within a bounded lag,
-- also while the repair is pending. The Sync session opens its own receive
-- window during this period, so the bound is the receive deferral (5 s) plus
-- one refresh.
local base=Stats()
local passFrames=0
local changes,maxLag,refreshedWhilePending={},0,0
local lastShown=ShownAlpha()
local maxScheduled=0
local function Observe(i)
 if Stats().pending then passFrames=passFrames+1 end
 local shown=ShownAlpha()
 if shown~=lastShown then
  lastShown=shown
  if Stats().pending then refreshedWhilePending=refreshedWhilePending+1 end
 end
 for _,c in ipairs(changes)do
  if not c.seen and shown and shown>=c.value then c.seen=i;local lag=i-c.at;if lag>maxLag then maxLag=lag end end
 end
 local n=0;for _,task in ipairs(Nexus.Scheduler.Pending())do if task.key==FOLLOWUP then n=n+1 end end
 if n>maxScheduled then maxScheduled=n end
end
-- Every view refresh requests the repair; during a burst that is every few
-- frames, modeled here as one request per frame.
Frames(30*FPS,function(i)
 if i%FPS==1 then AlphaImproves('2');changes[#changes+1]={value=alphaDps,at=i} end
 R.Request('refresh')
 Observe(i)
end)
Frames(6*FPS,function(i) Observe(30*FPS+i) end)
for _,c in ipairs(changes)do if not c.seen then maxLag=math.huge end end
s=Stats()
local completed=(s.passesCompleted or 0)-(base.passesCompleted or 0)
print('LRP sustained','N',N,'passes',completed,'restarts',s.restarts-base.restarts,'jobs',s.jobs-base.jobs,
 'activeFrames',passFrames,'of',36*FPS,'maxLagFrames',maxLag,'refreshedWhilePending',refreshedWhilePending,
 'maxScheduledFollowUps',maxScheduled,'coalesced',s.followUpsCoalesced,'deferred',s.deferredRequests,
 'lastPassActive',string.format('%.2f',s.lastPassDuration or -1))
check(s.restarts==base.restarts,'2: a newer DPS revision does not discard the pass: restarts '..(s.restarts-base.restarts))
check(completed>=2,'2: passes complete under sustained updates: '..tostring(completed))
check(maxScheduled<=1,'6: at most one follow-up is ever scheduled: '..maxScheduled)
check(passFrames<=0.6*36*FPS,'4: the fairness gap keeps the repair off most frames under sustained input: '..passFrames..'/'..36*FPS)
check(maxLag<=math.floor(5.5*FPS),'7: the HUD shows each new DPS value within the bounded lag (frames): '..tostring(maxLag))
check(refreshedWhilePending>=1,'7: including while the repair is pending: '..refreshedWhilePending)
check(LegacyRecovered().n==K-1,'2: no duplicate legacy build: '..LegacyRecovered().n)

-- Convergence after the input stops: the follow-up runs, then idle.
check(Settle(40*FPS),'2: the repair converges after the input stops')
s=Stats()
check(not s.pending and not s.followUpPending and s.completedDpsRevision==CurrentRevision(),
 '2: converged: the completed revision is the current one, no follow-up pending')
jobs,pumps=s.jobs,s.pumps
Frames(10*FPS)
check(Stats().jobs==jobs and Stats().pumps==pumps,'2: quiescent after convergence')

------------------------------------------------------------------------
-- 3. Unrelated updates (a received build, a duplicate DPS record) do not start
-- or restart a pass.
local before=Stats()
local okBuild=Nexus.BuildCatalog.Put({id='lrp-remote-1',title='Remote build',author='Remote',ownerKey='remote@ebonhold',
 realm='ebonhold',class='MAGE',postedAt=L.STAMP+700,lastModified=L.STAMP+700,description='Synthetic',
 echoes=L.Copy(L.OrdinaryRows(3001)),lockedEchoes=L.Copy(L.LockedRows(3001))},{source='remote',sender='Remote-Ebonhold'})
local filler=Player('Filler1')
local dup=fx:Receive('Filler1','dummy',{dps=filler.dps.dummy,ts=filler.ts.dummy})
Frames(8*FPS)
s=Stats()
check(dup==false and s.jobs==before.jobs and s.restarts==before.restarts,'3: unrelated updates start or restart nothing: jobs+'
 ..(s.jobs-before.jobs)..' (build '..tostring(okBuild)..', duplicate '..tostring(dup)..')')

------------------------------------------------------------------------
-- 8b. A burst of accepted DPS records every frame (real inbound records for
-- other characters) with no receive window open (modeled: Sync reports a
-- closed window): the pending view refresh is not pushed later by each
-- revision, so the HUD shows a new value within a few frames.
do
 local sync=Nexus.Sync
 local isReceiving,timeLeft=sync.IsReceiving,sync.ReceiveTimeLeft
 sync.IsReceiving=function() return false end
 sync.ReceiveTimeLeft=function() return 0 end
 Frames(FPS)
 AlphaImproves('burst')
 local target,seenAt=alphaDps,nil
 local fillers={};for _,p in ipairs(fx.players)do if p.name:match('^Filler') then fillers[#fillers+1]=p end end
 Frames(3*FPS,function(i)
  local p=fillers[1+(i%#fillers)]
  p.dps.dummy=p.dps.dummy+1
  assert(fx:Receive(p.name,'dummy',{dps=p.dps.dummy,ts=time()-1}),'fixture: burst record accepted')
  if not seenAt and ShownAlpha()==target then seenAt=i end
 end)
 sync.IsReceiving,sync.ReceiveTimeLeft=isReceiving,timeLeft
 print('LRP burst','seenAt',tostring(seenAt))
 check(seenAt and seenAt<=30,'8b: a revision burst does not postpone the view refresh: shown at frame '..tostring(seenAt))
end
check(Settle(40*FPS),'8b: repair settles')

------------------------------------------------------------------------
-- 8. A continuous receive window (modeled: Sync reports an open window for
-- the whole period) holds the views back for a bounded time only.
do
 local sync=Nexus.Sync
 local isReceiving,timeLeft=sync.IsReceiving,sync.ReceiveTimeLeft
 sync.IsReceiving=function() return true end
 sync.ReceiveTimeLeft=function() return 60 end
 local updated,firstAt=0,nil
 local expectReceive
 Frames(20*FPS,function(i)
  if i%(2*FPS)==1 then AlphaImproves('receive');expectReceive=alphaDps end
  if expectReceive and ShownAlpha()==expectReceive then updated=updated+1;firstAt=firstAt or i;expectReceive=nil end
 end)
 sync.IsReceiving,sync.ReceiveTimeLeft=isReceiving,timeLeft
 print('LRP receive','updates',updated,'firstAt',tostring(firstAt))
 check(updated>=2 and firstAt and firstAt<=math.floor(5.5*FPS),'8: views refresh within the bounded deferral during continuous receiving: '
  ..updated..' first at '..tostring(firstAt))
 for _=1,6*FPS do if ShownAlpha()==alphaDps then break end;Frames(1) end
 check(ShownAlpha()==alphaDps,'8: after the window: the HUD shows the current value')
end
check(Settle(40*FPS),'8: repair settles')

------------------------------------------------------------------------
-- 9b. The saved root is replaced mid-pass: the pass is abandoned, nothing is
-- stamped for the old root, and the one follow-up starts over on the current
-- root.
do
 check(StartPass(),'9b: setup: a pass is running')
 local stamp=Stats().completedDpsRevision
 local original=NexusDB
 NexusDB=setmetatable({},{__index=original})
 Frames(2)
 local r=Stats()
 NexusDB=original
 check(not r.pending and r.lastReason=='SOURCE_DRIFT' and r.completedDpsRevision==stamp and r.followUpPending,
  '9b: a replaced saved root abandons the pass without a stamp: '..tostring(r.lastReason))
 check(Settle(40*FPS) and Stats().completedDpsRevision==CurrentRevision(),'9b: the follow-up completes on the current root')
end

------------------------------------------------------------------------
-- 11. Reload in the middle of a pass: the next session repairs from the saved
-- rows again, recovers nothing twice and settles on its own revision.
do
 check(StartPass(),'11: setup: a pass is running')
 local recoveredBefore=LegacyRecovered().n
 H.Fire('PLAYER_LOGOUT')
 H=L.Reload(F,function(h) h.playerLevel=60 end)
 R=Nexus.LegacyQualificationRepair
 check(Settle(),'11: the next session repairs and settles')
 check(LegacyRecovered().n==recoveredBefore and Stats().recovered==0,'11: nothing is recovered twice after the reload: '
  ..LegacyRecovered().n..' recovered+'..Stats().recovered)
 check(Stats().completedDpsRevision==CurrentRevision(),'11: the new session completes its own revision')
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

print('PASS legacy_repair_progress_fairness: finite passes complete under sustained DPS input, covered-revision stamps, one coalesced follow-up, views refresh while the repair is pending checks='..checks)
