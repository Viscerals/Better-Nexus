-- An accepted DPS record must survive the first start-up exact-evidence
-- compaction, whatever compaction phase it arrives in, through publication and
-- a reload. Compaction may change the representation (inline Echo arrays become
-- evidence references) but never remove or regress an accepted record.
--
-- Cause fixed here: compaction works on a private copy of dpsCapture and
-- publishes it as a bundle override. (1) A DPS change during pool-before was
-- absorbed: the remembered revision advanced while the older copy was kept
-- (this also covered writes during source-verification, which ends in
-- pool-before). (2) A write after the copy was prepared for publication
-- (commit-pending) was overwritten when the pending commit published the copy.
-- Now a DPS change in pool-before restarts from a fresh copy, and the catalog
-- refuses the compaction publication (PUBLICATION_SOURCE_CHANGED) unless the
-- live DPS source is still the one the copy was taken from; compaction then
-- restarts.
--
-- Real TOC boot, real compaction, catalog and evidence pool; accepted writes
-- come through the real receive path (DpsCapture.ReceiveRecord). Phases are
-- observed on frame boundaries (compaction yields per pump) under single-slice
-- pacing (no profile clock, so the schedule is deterministic); every case
-- checks that its writes actually landed inside the named phase. Synthetic
-- data only.
local T=dofile('tests/prototype/startup_support.lua')
T.SingleSlicePacing()
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local H,fx
local function NewFixture(extra)
 local players={
  {name='Alpha',class='MAGE',dps={lk=52000},locked=6},     -- existing record, explicit locked
  {name='Kilo',class='PALADIN',locked=0},                  -- no record yet, known-zero locked
  {name='Lima',class='PRIEST',locked=3},                   -- no record yet, explicit locked
  {name='November',class='DRUID',locked=2,build='missing'},-- new owner and no build yet
 }
 for i=1,extra or 0 do players[#players+1]={name='Extra'..string.char(64+((i-1)%26)+1)..i,class='MAGE',dps={lk=30000+i}} end
 return L.New({players=players})
end
local function Player(name) for _,p in ipairs(fx.players)do if p.name==name then return p end end end
local function Stats() return Nexus.DataCompaction.Stats(NexusDB) or {} end
local function Meta() return (NexusDB.authorityBundle or {}).dataCompaction or {} end
local function Completed() return Meta().version~=nil and Meta().inProgress==nil end
local function Bucket() return (((NexusDB.authorityBundle or {}).dpsCapture or {}).characterBest or {}).lk or {} end
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

-- One run. inject: {{phase=,occurrence=,writes={{name,values},...}},...};
-- burst: {phase=,occurrence=,frames=} sends a strictly better Kilo record on
-- every frame of that window. Every accepted write must stay present in the
-- durable bundle on every later frame.
local function Run(extra,inject,burst)
 fx=NewFixture(extra)
 H=F.Boot(fx:Install(F.Database()))
 local seen,last={},nil
 local result={landed={},accepted={},frames=0,maxTurnRestarts=0,lastWrite=0}
 local restarts=0
 local burstLeft,burstValue
 local function Accept(name,values,tag)
  local p=Player(name)
  local before={p.dps.lk,p.ts.lk,p.duration.lk}
  local ok,why=fx:Receive(name,'lk',values)
  -- The fixture records the sent values; a refused record changes nothing.
  if ok~=true then p.dps.lk,p.ts.lk,p.duration.lk=before[1],before[2],before[3] end
  result.lastWrite=result.frame
  result.landed[#result.landed+1]={key=tag..':'..name..'='..values.dps,ok=ok==true,why=why,phase=tostring(Stats().phase)}
  if ok==true then result.accepted[Player(name).owner]={name=name,dps=values.dps} end
  return ok==true
 end
 -- Observe (pass through unchanged) every compaction publication request: a
 -- prepared DPS copy must already contain every write accepted before the
 -- pump that prepared it. Keeping an older copy while the remembered revision
 -- advances fails here even when the publication guard later refuses it.
 local catalog=Nexus.BuildCatalog
 local commit=catalog.CommitMaintenance
 result.prepared,result.stale=0,{}
 catalog.CommitMaintenance=function(handle,overrides,guard)
  local dps=type(overrides)=='table' and overrides.dpsCapture or nil
  if dps then
   result.prepared=result.prepared+1
   local lk=((dps.characterBest or {}).lk or {})
   for owner,a in pairs(result.accepted)do
    if not (lk[owner] and tonumber(lk[owner].dps)==a.dps) and #result.stale<4 then
     result.stale[#result.stale+1]=owner..'@'..tostring(result.frame)
    end
   end
  end
  return commit(handle,overrides,guard)
 end
 for frame=1,30000 do
  result.frame=frame
  local st=Stats()
  local phase=tostring(st.phase)
  result.maxTurnRestarts=math.max(result.maxTurnRestarts,(st.restarts or restarts)-restarts)
  restarts=st.restarts or restarts
  if phase~=last then seen[phase]=(seen[phase] or 0)+1;last=phase end
  local pending=Nexus.Scheduler.Pending('data-compaction') and st.pending
  for _,inj in ipairs(inject or {})do
   if not inj.frame and pending and phase==inj.phase and seen[phase]==inj.occurrence then
    inj.frame=frame
    for _,w in ipairs(inj.writes)do Accept(w[1],w[2],inj.phase..'#'..inj.occurrence) end
   end
  end
  if burst and pending and not burstLeft and phase==burst.phase and seen[phase]==burst.occurrence then
   burstLeft,burstValue=burst.frames,47000
   result.burstStart=frame
  end
  if burstLeft and burstLeft>0 then
   burstValue=burstValue+1
   check(Accept('Kilo',{dps=burstValue,ts=L.STAMP+400+(burstValue-47000)},'burst'),'burst: a better record is accepted at frame '..frame)
   burstLeft=burstLeft-1
   if burstLeft==0 then result.burstEnd=frame end
  end
  for owner,a in pairs(result.accepted)do
   local r=Bucket()[owner]
   check(r~=nil and tonumber(r.dps)==a.dps,'frame '..frame..' ('..phase..'): the accepted '..owner..' record is in the durable bundle ('..tostring(r and r.dps)..' / '..a.dps..')')
  end
  if frame>10 and Completed() and not Nexus.Scheduler.Pending('data-compaction') then result.frames=frame;break end
  H.Advance(.05,.05)
 end
 catalog.CommitMaintenance=commit
 check(#result.stale==0,'no compaction publication is prepared from a DPS copy older than an accepted write: '..table.concat(result.stale,' '))
 check(result.maxTurnRestarts<=1,'at most one compaction restart per scheduler turn: '..result.maxTurnRestarts)
 result.restarts=(Meta().last or {}).restarts
 result.pumps=(Meta().last or {}).pumps
 return result
end

-- Durable row, public read and evidence resolution for every accepted write,
-- and the representation change for every stored row.
local function Final(result,tag)
 check(Completed(),tag..': compaction completed and stamped')
 check(Meta().last and Meta().last.pending==false and Meta().last.phase=='done',tag..': the stamp is terminal')
 for owner,a in pairs(result.accepted)do
  local p,r=Player(a.name),Bucket()[owner]
  check(r~=nil and tonumber(r.dps)==a.dps,tag..': '..owner..' record '..tostring(r and r.dps)..' / '..a.dps)
  check(r.ownerKey==owner and r.ownerVerified==true and r.player==a.name and r.class==p.class
   and r.fingerprint==p.fingerprint and r.ts==p.ts.lk and r.duration==p.duration.lk,tag..': '..owner..' keeps its exact identity and record fields')
  local public=Nexus.DpsCapture.GetCharacterBest('lk',a.name,owner)
  check(public~=nil and tonumber(public.dps)==a.dps,tag..': the public DPS read returns '..owner)
  check(List(public.echoes)==List(p.dpsOrdinary),tag..': '..owner..' ordinary evidence resolves exactly: '..List(public.echoes))
  check(List(public.lockedEchoes)==List(p.dpsLocked),tag..': '..owner..' locked evidence resolves exactly: '..List(public.lockedEchoes))
  if p.build=='present' then
   check(r.buildId==p.buildId,tag..': '..owner..' keeps build '..tostring(r.buildId))
  else
   -- A record page created for the new owner must stay linked. Product
   -- behaviour outside compaction: a record received while any catalog
   -- mutation is in flight gets no page (the catalog refuses the Put with
   -- ROOT_MUTATION_PENDING and no ticket), so it keeps no build identity.
   local pages=0
   for _,b in pairs(NexusDB.authorityBundle.communityBuilds or {})do if b.ownerKey==owner then pages=pages+1 end end
   check(pages<=1 and (pages==0)==(r.buildId==nil),tag..': '..owner..' page and link agree: '..pages..' page(s), buildId '..tostring(r.buildId))
   if r.buildId~=nil then check(Nexus.BuildCatalog.Get(r.buildId)~=nil,tag..': '..owner..' links its created build') end
   result.links=(result.links or '')..(r.buildId and 'L' or '-')
  end
 end
 for owner,r in pairs(Bucket())do
  check(r.echoes==nil and type(r.evidenceKey)=='string',tag..': '..owner..' is stored as an evidence reference')
  check(r.lockedEchoes==nil,tag..': '..owner..' has no inline locked array')
 end
end

-- The rendered Leaderboard row and its detail pane show the exact record.
local function Board(result,tag)
 L.Open(H,'lk')
 local rows=L.RenderedRows(H)
 for owner,a in pairs(result.accepted)do
  local p=Player(a.name)
  local index
  for i,row in ipairs(rows)do if row.data.ownerKey==owner then index=i end end
  check(index~=nil and rows[index].data.dps==a.dps,tag..': '..owner..' is a rendered Leaderboard row')
  local det=L.Select(H,index)
  check(det.row and det.row.ownerKey==owner,tag..': selecting '..owner..' shows its detail')
  check(List(det.ordinary)==List(p.dpsOrdinary),tag..': '..owner..' detail shows the exact ordinary Echoes and copies')
  local spells={};for _,x in ipairs(det.locked)do spells[#spells+1]={spellId=x.spellId,count=1} end
  local want={};for _,x in ipairs(p.dpsLocked or {})do want[#want+1]={spellId=x.spellId,count=1} end
  check(List(spells)==List(want) and det.lockedTitle==(#p.locked>0),tag..': '..owner..' detail shows the exact locked Echoes')
  if p.build=='present' and #p.locked>0 then
   local validated,why=Nexus.CandidateEvidence.Validate(det.copyCandidate)
   check(validated and det.copyEnabled,tag..': '..owner..' Copy is available: '..tostring(det.copyReason or why))
   -- The existing Copy contract (leaderboard_recovery_rows) compares ordinary
   -- spell and stacks; the build keeps the exact ordinary qualities, and the
   -- locked copies keep theirs.
   local stacks={};for i,x in ipairs(validated.ordinaryEchoes or {})do stacks[i]={spellId=x.spellId,stacks=x.stacks} end
   check(List(stacks)==List(p.ordinary) and Exact(validated.lockedEchoes)==Exact(p.locked),
    tag..': '..owner..' Copy carries the exact ordinary copies and the exact locked qualities and stacks')
   local build=Nexus.BuildCatalog.Get(p.buildId)
   check(build and Exact(build.echoes)==Exact(p.ordinary),tag..': '..owner..' build keeps the exact ordinary qualities and stacks')
  end
 end
 Nexus.Leaderboard.Hide()
end

-- Evidence cleanup after compaction removes nothing an accepted row uses.
local function Cleanup(result,tag)
 local summary
 for _=1,4000 do
  summary=Nexus.DataCompaction.CollectGarbage(NexusDB)
  -- Cleanup refuses to start while other catalog work is in flight.
  local busy=summary and summary.blocked and (summary.reason=='ROOT_MUTATION_PENDING' or summary.reason=='ROOT_ADMISSION_PENDING')
  if not (summary and (summary.pending or busy)) then break end
  H.Advance(.05,.05)
 end
 check(summary and not summary.pending and not summary.blocked,tag..': evidence cleanup completes: '..tostring(summary and summary.reason))
 for owner,a in pairs(result.accepted)do
  local p=Player(a.name)
  local public=Nexus.DpsCapture.GetCharacterBest('lk',a.name,owner)
  check(public and List(public.echoes)==List(p.dpsOrdinary) and List(public.lockedEchoes)==List(p.dpsLocked),
   tag..': '..owner..' evidence still resolves after cleanup')
 end
end

local function Writes(...)
 local out={}
 for _,name in ipairs({...})do
  if name=='Kilo' then out[#out+1]={'Kilo',{dps=47000,ts=L.STAMP+300}}          -- new record
  elseif name=='Alpha' then out[#out+1]={'Alpha',{dps=56000,ts=L.STAMP+301}}    -- improvement
  elseif name=='Lima' then out[#out+1]={'Lima',{dps=51000,ts=L.STAMP+302}}
  elseif name=='November' then out[#out+1]={'November',{dps=49000,ts=L.STAMP+303}} end -- new owner and build
 end
 return out
end
local summary={}

-- 0. No writes: the restart baseline.
local base=Run(0,{})
Final(base,'no writes')
local baseRestarts=base.restarts or 0
summary[#summary+1]='none:'..base.frames..'f/'..baseRestarts..'r/'..base.maxTurnRestarts..'t'

-- 1. Phase matrix: a new record (known-zero locked), an improvement of an
-- existing record (explicit locked) and a new owner whose build does not
-- exist yet, accepted inside each observable window. On the defective code
-- source-verification, pool-before and commit-pending lost them; overlay and
-- pool-after are adjacent controls.
local CASES={{'overlay',1},{'pool-after',1},{'source-verification',1},{'pool-before',1},
 {'overlay',2},{'pool-after',2},{'commit-pending',1}}
for _,c in ipairs(CASES)do
 local tag=c[1]..'#'..c[2]
 local r=Run(0,{{phase=c[1],occurrence=c[2],writes=Writes('Kilo','Alpha','November')}})
 check(#r.landed==3,tag..': three writes were submitted')
 for _,w in ipairs(r.landed)do
  check(w.ok,tag..': '..w.key..' was accepted: '..tostring(w.why))
  check(w.phase==c[1],tag..': '..w.key..' landed in phase '..w.phase)
 end
 Final(r,tag)
 summary[#summary+1]=tag..':'..r.frames..'f/'..tostring(r.restarts)..'r/'..r.maxTurnRestarts..'t/'..(r.frames-r.lastWrite)..'s'
 if c[1]=='commit-pending' then Board(r,tag) end
 H=F.Reload()
 Final(r,tag..' after reload')
 if c[1]=='commit-pending' then
  Board(r,tag..' after reload')
  Cleanup(r,tag)
 end
end

-- 2. The dps phase itself (it spans pumps only with more DPS rows).
local r=Run(60,{{phase='dps',occurrence=1,writes=Writes('Kilo','Alpha')}})
check(#r.landed==2 and r.landed[1].ok and r.landed[2].ok and r.landed[1].phase=='dps','dps#1: the writes were accepted inside the dps phase')
Final(r,'dps#1')
H=F.Reload()
Final(r,'dps#1 after reload')
summary[#summary+1]='dps#1(60 rows):'..r.frames..'f/'..tostring(r.restarts)..'r'

-- 3. Accepted writes across separate yields.
r=Run(0,{{phase='source-verification',occurrence=1,writes=Writes('Kilo')},
 {phase='commit-pending',occurrence=1,writes=Writes('Lima')}})
check(#r.landed==2 and r.landed[1].ok and r.landed[2].ok,'multi-yield: both writes were accepted')
check(r.landed[1].phase=='source-verification' and r.landed[2].phase=='commit-pending','multi-yield: the writes landed in separate windows')
Final(r,'multi-yield')
check(Bucket()[Player('Lima').owner].lockedEvidenceKey~=nil,'multi-yield: Lima keeps its explicit locked evidence reference')
check(Bucket()[Player('Kilo').owner].lockedEvidenceKey==nil,'multi-yield: Kilo keeps known-zero locked evidence')
H=F.Reload()
Final(r,'multi-yield after reload')
summary[#summary+1]='multi-yield:'..r.frames..'f/'..tostring(r.restarts)..'r'

-- 4. Worse and duplicate records keep the existing comparison rules: the
-- outcome equals the same writes made after compaction completed.
local WORSE={'Alpha',{dps=50000,ts=L.STAMP+304}}
local NEW=Writes('Kilo')[1]
r=Run(0,{{phase='source-verification',occurrence=1,writes={WORSE,NEW,NEW}}})
local during={r.landed[1].ok,r.landed[2].ok,r.landed[3].ok}
local stored={Bucket()['alpha@ebonhold'].dps,Bucket()['kilo@ebonhold'].dps}
Final({accepted={['alpha@ebonhold']={name='Alpha',dps=52000},['kilo@ebonhold']={name='Kilo',dps=47000}}},'worse/duplicate')
Run(0,{})
local after={fx:Receive(WORSE[1],'lk',WORSE[2])==true,fx:Receive(NEW[1],'lk',NEW[2])==true,fx:Receive(NEW[1],'lk',NEW[2])==true}
check(during[1]==after[1] and during[2]==after[2] and during[3]==after[3] and not during[1] and during[2] and not during[3],
 'worse/duplicate: acceptance matches the post-compaction control: '..tostring(during[1])..','..tostring(during[2])..','..tostring(during[3]))
check(stored[1]==Bucket()['alpha@ebonhold'].dps and stored[2]==Bucket()['kilo@ebonhold'].dps,
 'worse/duplicate: the stored results match the control ('..tostring(stored[1])..' '..tostring(stored[2])..')')

-- 5. A finite burst (a better Kilo record on every frame for 40 frames from
-- the second pool-after) settles: every accepted write stays present, each
-- turn costs at most one restart, and compaction completes after the burst.
r=Run(0,nil,{phase='pool-after',occurrence=2,frames=40})
check(r.burstStart and r.burstEnd,'burst: the writes ran inside the second walk')
Final(r,'burst')
check(r.accepted['kilo@ebonhold'].dps==47040,'burst: the last accepted record is kept')
check((r.restarts or 0)<=baseRestarts+40,'burst: at most one restart per accepted write ('..tostring(r.restarts)..')')
check(r.frames-r.burstEnd<=base.frames,'burst: compaction completed '..(r.frames-r.burstEnd)..' frames after the burst ended')
H=F.Reload()
Final(r,'burst after reload')
summary[#summary+1]='burst40:'..r.frames..'f/'..tostring(r.restarts)..'r/'..r.maxTurnRestarts..'t/'..(r.frames-r.lastWrite)..'s'

-- 6. The publication guard selects an absent or malformed DPS payload as the
-- empty table, as compaction does: a saved bundle without a usable dpsCapture
-- (and no compaction stamp) still completes in a bounded number of restarts.
for _,case in ipairs({{'absent',nil},{'malformed','malformed'}})do
 local saved=assert(loadstring('return '..F.Serialize(NexusDB)))()
 saved.authorityBundle.dataCompaction=nil
 saved.authorityBundle.dpsCapture=case[2]
 H=F.Boot(saved)
 local frames
 for i=1,2000 do
  if i>10 and Completed() and not Nexus.Scheduler.Pending('data-compaction') then frames=i break end
  H.Advance(.05,.05)
 end
 check(frames~=nil,case[1]..' DPS payload: compaction completes')
 check((Meta().last.restarts or 0)<=2,case[1]..' DPS payload: bounded restarts ('..tostring(Meta().last.restarts)..')')
 check(type(NexusDB.authorityBundle.dpsCapture)=='table',case[1]..' DPS payload: a table is published')
 summary[#summary+1]=case[1]..':'..frames..'f/'..tostring(Meta().last.restarts)..'r'
end

-- 7. A DPS writer that calls the catalog before it stores its row (a new
-- owner's record creates a build page through Catalog.Put) while a rebind
-- request is pending during commit-pending. MutationGate used to drive that
-- rebind, which resumed the compaction mutation inside the write and could
-- publish the older copy before the row was stored and DPS_CHANGED advanced;
-- the guard then passed. Every offset of the window is scanned.
local landedOffsets=0
for k=0,200 do
 fx=NewFixture(0)
 H=F.Boot(fx:Install(F.Database()))
 local inWindow,requested,info=0,false,nil
 for frame=1,6000 do
  local st=Nexus.DataCompaction.Stats(NexusDB) or {}
  if st.pending and st.phase=='commit-pending' then
   if not requested then Nexus.BuildCatalog.RequestAuthorityRebindV1('SOURCE_REBIND_REQUIRED');requested=true end
   if not info and inWindow==k then
    local bundle=NexusDB.authorityBundle
    local ok=fx:Receive('November','lk',{dps=49000,ts=L.STAMP+303})
    info={ok=ok==true,phase=tostring((Nexus.DataCompaction.Stats(NexusDB) or {}).phase),inside=NexusDB.authorityBundle~=bundle}
   end
   inWindow=inWindow+1
  end
  if frame>10 and Completed() and not Nexus.Scheduler.Pending('data-compaction') then break end
  H.Advance(.05,.05)
 end
 if not info then break end
 landedOffsets=landedOffsets+1
 local tag='rebind pending, commit-pending+'..k
 check(info.ok and info.phase=='commit-pending',tag..': the record of the new owner was accepted inside commit-pending')
 check(not info.inside,tag..': no catalog publication happened inside the write')
 check(Completed(),tag..': compaction completed')
 local row=Bucket()['november@ebonhold']
 check(row and row.dps==49000,tag..': the accepted record is in the durable bundle ('..tostring(row and row.dps)..')')
 H=F.Reload()
 row=Bucket()['november@ebonhold']
 check(row and row.dps==49000,tag..': the accepted record is kept after reload')
end
check(landedOffsets>=10,'the commit-pending window was scanned at '..landedOffsets..' offsets')
summary[#summary+1]='rebind-pending-window:'..landedOffsets..'offsets'

print('PASS dps_compaction_preservation: accepted DPS writes survive every exercised compaction window through publication, evidence cleanup and reload; worse/duplicate rules kept; finite burst settles; absent or malformed DPS payload completes; no publication inside a write under a pending rebind ['..table.concat(summary,' ')..'] checks='..checks)
