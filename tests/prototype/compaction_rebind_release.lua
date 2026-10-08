-- A coordinator rebind turn that runs while the start-up compaction walk holds
-- its catalog maintenance transaction must not leave the catalog invalidated
-- or the compaction blocked.
--
-- Cause: BeginCatalogMaintenance opens an evidence candidate for the walk. The
-- lifecycle rebind turn re-initialized the evidence pool (LoadoutEvidence.Init
-- discards an open candidate) while the walk stayed open, so the walk's next
-- intern went into the live pool and advanced the append revision the
-- admitted root binds: ROOT_INVALIDATED / SOURCE_DRIFT, no recovery, and the
-- compaction never completed. The #85 wait covers only a mutation candidate.
-- Now the rebind turn releases the open walk with its candidate
-- (BuildCatalog.ReleaseMaintenanceForRebindV1, the same displacement a direct
-- mutation applies), and the compaction restarts a released walk before it
-- interns in the DPS phase or commits.
--
-- The rebind requests here are the public call DataCompaction's ReadmitCatalog
-- makes (SOURCE) and the read gate's owner reason (OWNER), made directly while
-- the transaction is open: this reproduces the order, not a native timing.
-- Section 5 changes the owner identity itself and lets the read gate record
-- the request. Real TOC boot, compaction, catalog, evidence pool and
-- lifecycle; single-slice pacing. Synthetic data only.
local T=dofile('tests/prototype/startup_support.lua')
T.SingleSlicePacing()
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local H,fx
local function NewFixture(extra)
 local players={
  {name='Alpha',class='MAGE',dps={lk=52000},locked=6},
  {name='Kilo',class='PALADIN',dps={lk=41000},locked=0},
 }
 for i=1,extra or 0 do players[#players+1]={name='Extra'..string.char(64+((i-1)%26)+1)..i,class='MAGE',dps={lk=30000+i}} end
 return L.New({players=players})
end
local function Meta() return (NexusDB.authorityBundle or {}).dataCompaction or {} end
local function Completed() return Meta().version~=nil and Meta().inProgress==nil end
local function List(rows)
 local out={}
 for _,r in ipairs(rows or {})do out[#out+1]=tostring(r.spellId)..':'..tostring(r.count or r.stacks) end
 return table.concat(out,',')
end
local function Exact(rows)
 local out={}
 for _,r in ipairs(rows or {})do out[#out+1]=tostring(r.spellId)..':'..tostring(r.quality)..':'..tostring(r.stacks or r.count) end
 return table.concat(out,',')
end

-- One run; `action` runs once inside the named phase occurrence.
local function Run(extra,phase,occurrence,action)
 fx=NewFixture(extra)
 H=F.Boot(fx:Install(F.Database()))
 local E=Nexus.LoadoutEvidence
 local init=E.Init
 local r={initWhileOpen=0,frames=0}
 -- Observer (pass-through): the evidence pool is never re-initialized while
 -- a candidate is open.
 E.Init=function(db)
  if E.CandidateOpen() then r.initWhileOpen=r.initWhileOpen+1 end
  return init(db)
 end
 local seen,last={},nil
 for frame=1,20000 do
  local st=Nexus.DataCompaction.Stats(NexusDB) or {}
  local p=tostring(st.phase)
  if p~=last then seen[p]=(seen[p] or 0)+1;last=p end
  if action and not r.fired and st.pending and p==phase and seen[p]==occurrence then
   r.fired,r.openAtFire=frame,E.CandidateOpen()
   action()
   r.requested=Nexus.BuildCatalog.RebindRequired()
  end
  local s=Nexus.BuildCatalog.Status()
  check(s.state~='ROOT_INVALIDATED','frame '..frame..' ('..p..'): the catalog is not invalidated: '..tostring(s.reason))
  if r.fired and not r.served and not Nexus.BuildCatalog.RebindRequired() then r.served=frame end
  if r.fired and not r.served and phase=='commit-pending' and p=='commit-pending' then r.heldWhilePending=true end
  if frame>10 and Completed() and not Nexus.Scheduler.Pending('data-compaction') then
   r.frames=r.frames>0 and r.frames or frame
   if not r.fired or r.served then break end
  end
  H.Advance(.05,.05)
 end
 E.Init=init
 r.restarts=(Meta().last or {}).restarts
 return r
end

local function Final(tag)
 check(Completed() and Meta().last.phase=='done',tag..': compaction completed and stamped')
 check(Nexus.BuildCatalog.Status().state=='ROOT_ADMITTED',tag..': the catalog is admitted')
 for _,p in ipairs(fx.players)do
  local row=NexusDB.authorityBundle.dpsCapture.characterBest.lk[p.owner]
  check(row and row.dps==p.dps.lk and row.echoes==nil and type(row.evidenceKey)=='string',tag..': '..p.owner..' is kept as an evidence reference')
  local public=Nexus.DpsCapture.GetCharacterBest('lk',p.name,p.owner)
  check(public and List(public.echoes)==List(p.dpsOrdinary) and List(public.lockedEchoes)==List(p.dpsLocked),
   tag..': '..p.owner..' evidence resolves exactly')
  local build=Nexus.BuildCatalog.Get(p.buildId)
  check(build and Exact(build.echoes)==Exact(p.ordinary) and Exact(build.lockedEchoes)==Exact(p.locked),
   tag..': '..p.buildId..' resolves its exact ordinary and locked evidence')
 end
end

local summary={}
local base=Run(0)
Final('no rebind')
local baseRestarts=base.restarts or 0
summary[#summary+1]='none:'..base.frames..'f/'..baseRestarts..'r'

local function Request(reason) return function() Nexus.BuildCatalog.RequestAuthorityRebindV1(reason) end end

-- 1-2. A rebind requested inside every phase occurrence in which the walk
-- holds its evidence transaction, as a run without a request observes them
-- (0 rows: overlay and dps; 60 rows also pool-after, where the release is
-- found at the commit point). commit-pending is section 3. On the defective
-- code the overlay and dps cases invalidated the catalog and never completed.
local function Windows(extra)
 fx=NewFixture(extra)
 H=F.Boot(fx:Install(F.Database()))
 local seen,last,out={},nil,{}
 for frame=1,20000 do
  local st=Nexus.DataCompaction.Stats(NexusDB) or {}
  local p=tostring(st.phase)
  if p~=last then
   seen[p]=(seen[p] or 0)+1;last=p
   if st.pending and p~='commit-pending' and Nexus.LoadoutEvidence.CandidateOpen() then out[#out+1]={p,seen[p]} end
  end
  if frame>10 and Completed() and not Nexus.Scheduler.Pending('data-compaction') then break end
  H.Advance(.05,.05)
 end
 return out
end
local exercised={}
for _,extra in ipairs({0,60})do
 local windows=Windows(extra)
 check(#windows>=4,'rows '..extra..': the walk holds its evidence transaction in '..#windows..' phase occurrences')
 for _,w in ipairs(windows)do
  exercised[w[1]]=true
  for _,reason in ipairs(extra==0 and {'SOURCE_REBIND_REQUIRED','OWNER_REBIND_REQUIRED'} or {'SOURCE_REBIND_REQUIRED'})do
   local tag=w[1]..'#'..w[2]..'/'..extra..' '..reason:match('^%u+')
   local r=Run(extra,w[1],w[2],Request(reason))
   check(r.fired and r.openAtFire and r.requested,tag..': the request was made while the walk held its evidence candidate')
   check(r.served and r.served-r.fired<=2,tag..': the rebind turn ran at once ('..tostring(r.served and r.served-r.fired)..' frames)')
   check(r.initWhileOpen==0,tag..': the evidence pool was not re-initialized under an open candidate')
   Final(tag)
   check((r.restarts or 0)<=baseRestarts+1,tag..': at most one extra restart ('..tostring(r.restarts)..')')
   summary[#summary+1]=tag..':'..r.frames..'f/'..tostring(r.restarts)..'r'
  end
 end
end
check(exercised.overlay and exercised.dps and exercised['pool-after'],'the overlay, dps and pool-after windows were all exercised')
H=F.Reload();Final('last window after reload')

-- 3. Terminal release through the mutation: during commit-pending the #85
-- wait keeps the request until the compaction commit publishes; the next turn
-- serves it.
local r=Run(0,'commit-pending',1,Request('SOURCE_REBIND_REQUIRED'))
check(r.fired and r.heldWhilePending and r.served and r.served-r.frames<=2,'commit-pending: the request waits for the in-flight mutation, then is served: '..tostring(r.fired)..' '..tostring(r.served)..' '..tostring(r.frames))
check(r.initWhileOpen==0,'commit-pending: the evidence pool was not re-initialized under an open candidate')
Final('commit-pending')
summary[#summary+1]='commit-pending:'..r.frames..'f/'..tostring(r.restarts)..'r'

-- 4. A DPS write and a rebind request in the same turn (the write restarts
-- the walk, the rebind turn finds no open walk).
r=Run(0,'overlay',2,function()
 fx:Receive('Kilo','lk',{dps=47000,ts=L.STAMP+300})
 Nexus.BuildCatalog.RequestAuthorityRebindV1('SOURCE_REBIND_REQUIRED')
end)
check(r.fired and r.served and r.initWhileOpen==0,'write+rebind: served, no re-initialization under an open candidate')
Final('write+rebind')
check(NexusDB.authorityBundle.dpsCapture.characterBest.lk['kilo@ebonhold'].dps==47000,'write+rebind: the accepted record is kept')
summary[#summary+1]='write+rebind:'..r.frames..'f/'..tostring(r.restarts)..'r'

-- 5. A genuine owner identity change during the walk: the read gate records
-- the owner rebind. On the defective code the compaction stopped without
-- completing.
local original=UnitName
r=Run(0,'overlay',2,function()
 UnitName=function() return 'OtherTester','Ebonhold' end
 Nexus.BuildCatalog.Status()
end)
check(r.fired and r.requested=='OWNER_REBIND_REQUIRED' and r.served,'owner change: the read gate requested an owner rebind, and it was served')
check(r.initWhileOpen==0,'owner change: the evidence pool was not re-initialized under an open candidate')
Final('owner change')
summary[#summary+1]='owner-change:'..r.frames..'f/'..tostring(r.restarts)..'r'
UnitName=original

print('PASS compaction_rebind_release: a rebind turn during the compaction walk releases the walk with its evidence candidate; no invalidation, the compaction completes with exact evidence ['..table.concat(summary,' ')..'] checks='..checks)
