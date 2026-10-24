-- CX-04 Orb run pump assignment reads (stutter review, 2026-10-15). On the
-- current source (3d52b0ed7044 plus NX-03, NX-02, NX-01) one running,
-- non-passive Orb pump (OrbRuntime.Pump, every 0.2 s) reads the assigned
-- Wishlist twice outside any action callback: assigned() and then
-- entriesStillMatch() with no argument, in the pending branch and in the
-- nonpending branch. Each read builds one full slot projection over every Echo
-- of every raw build-slot row.
--
-- Required: one pump makes at most one assignment read, so at most one slot
-- projection, outside the Select and Spend precondition callbacks. Each of
-- those callbacks still makes its own fresh read. Passive and settling pumps
-- keep their single read.
--
-- SETUP and GUARD checks pass on the current source. The BOUND check runs last;
-- it is EXPECTED RED until the CX-04 fix. Work units: calls of the public
-- GameAdapter.AssignedWishlist inside a public OrbRuntime.Pump call, split by
-- whether an Orb action precondition callback is running, and the Echoes those
-- reads projected (public EchoReconcileStats projection counter). Every
-- instrument delegates to the real function. Semantic controls:
-- stutter_orb_pump_authority.lua.
local H=dofile('tests/prototype/orbs_support.lua')
local A,M=H.A,H.M
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

-- The assigned plan: three copies of 410002 (quality 2), one per single-step run.
H.OrbPlan({{spellId=410002,quality=2,stacks=3}})
-- A second Disposable A copy: three surplus sources for the three runs.
H.granted['Disposable A'][2]={spellId=410001,quality=1}
H.Notify();A.Poll()

-- Instruments.
local work={pumps=0,nested=0,outside=0,echoes=0,inside=0,inEchoes=0,direct=0,directEchoes=0,slots=0}
local pumpDepth,guardDepth,readDepth=0,0,0
local function Walked() return A.EchoReconcileStats().projections.slots.echoes end
local rawPump=M.Pump
local function LeavePump(ok,...) pumpDepth=pumpDepth-1;if not ok then error((...),0) end return ... end
-- A pump counts only when no pump is running. The pump's own Select reaches
-- SelectPerk; the adapter's choice observer then notifies the runtime, which
-- calls OrbRuntime.Pump(true) again inside the running pump. That call is
-- nested, not a second pump. Any read it makes stays in the running pump's
-- window and counts against that pump's bound.
M.Pump=function(...)
 if pumpDepth>0 then work.nested=work.nested+1 else work.pumps=work.pumps+1 end
 pumpDepth=pumpDepth+1;return LeavePump(pcall(rawPump,...))
end
local rawAssigned=A.AssignedWishlist
local function LeaveRead(inPump,inGuard,before,ok,...)
 readDepth=readDepth-1
 local walked=Walked()-before
 if not inPump then work.direct=work.direct+1;work.directEchoes=work.directEchoes+walked
 elseif inGuard then work.inside=work.inside+1;work.inEchoes=work.inEchoes+walked
 else work.outside=work.outside+1;work.echoes=work.echoes+walked end
 if not ok then error((...),0) end
 return ...
end
A.AssignedWishlist=function(...)
 local before=Walked();readDepth=readDepth+1
 return LeaveRead(pumpDepth>0,guardDepth>0,before,pcall(rawAssigned,...))
end
local rawSlots=A.Slots
A.Slots=function(...) if readDepth>0 then work.slots=work.slots+1 end return rawSlots(...) end
local rawSpend,rawSelect=A.Orbs.Spend,A.Orbs.Select
local function LeaveGuard(ok,...) guardDepth=guardDepth-1;if not ok then error((...),0) end return ... end
local function Counted(guard)
 if type(guard)~='function' then return guard end
 return function(...) guardDepth=guardDepth+1;return LeaveGuard(pcall(guard,...)) end
end
A.Orbs.Spend=function(token,key,expected,guard) return rawSpend(token,key,expected,Counted(guard)) end
A.Orbs.Select=function(token,index,board,id,guard) return rawSelect(token,index,board,id,Counted(guard)) end
local function Measure(fn,...)
 for k in pairs(work) do work[k]=0 end
 fn(...)
 local w={};for k,v in pairs(work) do w[k]=v end
 return w
end
local function Later() H.now=H.now+.2 end
local function State() return M.CompactStatus() or {} end

-- Workload: filler Wishlist mirror rows (above the 5 Saved Builds, unverified),
-- 79 Echoes each. None matches the plan, so the assignment is unchanged.
local PER=79
local function Filler(rows)
 local mirror={}
 for r=1,rows do
  local echoes={}
  for j=1,PER do echoes[j]={spellId=200000+j,quality=j%4,stacks=1} end
  mirror[5+r]={name='Filler '..r,verified=false,echoes=echoes}
 end
 return mirror
end
-- Literal: rows x 79 Echoes per projection; the third run completes the plan.
local SIZES={{rows=1,echoes=79,final='FINISHED'},{rows=5,echoes=395,final='FINISHED'},{rows=15,echoes=1185,final='COMPLETE'}}

local over={}
local function Bound(label,w,E)
 print(string.format('CX04_MEASURE %s pumps=%d assignment_reads=%d projected_echoes=%d guard_reads=%d guard_echoes=%d',
  label,w.pumps,w.outside,w.echoes,w.inside,w.inEchoes))
 if w.outside>1 or w.echoes>E then
  over[#over+1]=label..' assignment_reads='..w.outside..' projected_echoes='..w.echoes..' (bound 1 read, '..E..' Echoes)'
 end
end

for _,size in ipairs(SIZES) do
 local R,E=size.rows,size.echoes
 local tag=R..' rows'
 H.perks.serverBuildSlots=Filler(R)
 Later()

 -- SETUP: one direct assignment read is ready, makes one slot projection and
 -- walks exactly rows x 79 Echoes.
 local a
 local w=Measure(function() a=A.AssignedWishlist() end)
 check(type(a)=='table' and a.state=='ready' and w.direct==1 and w.slots==1 and w.directEchoes==E,
  'SETUP '..tag..': one direct assignment read is ready with one projection of '..E..' Echoes: state='
  ..tostring(a and a.state)..' slots='..w.slots..' echoes='..w.directEchoes)

 -- 1. Nonpending branch: the Confirm pump spends one Orb.
 local spends,takes=H.Count('orb-spend'),H.Count('take')
 w=Measure(H.Approve,1,false,true)
 local label=tag..' nonpending Spend pump'
 local c=State()
 check(w.pumps==1,'SETUP '..label..': Confirm runs one pump: '..w.pumps)
 check(H.Count('orb-spend')==spends+1 and c.state=='WAIT_OFFER' and c.pending==true,
  'GUARD '..label..': one Orb spend, waiting for the offer: spends='..(H.Count('orb-spend')-spends)..' state='..tostring(c.state))
 check(w.inside==1 and w.inEchoes==E,
  'GUARD '..label..': the Spend precondition makes its own fresh read: guard reads='..w.inside..' echoes='..w.inEchoes)
 Bound(label,w,E)

 -- 2. Pending branch: a pump while the offer has not appeared.
 Later();spends,takes=H.Count('orb-spend'),H.Count('take')
 w=Measure(M.Pump)
 label=tag..' pending wait pump'
 c=State()
 check(w.pumps==1 and w.inside==0,'SETUP '..label..': one pump, no action callback: '..w.pumps..' '..w.inside)
 check(c.state=='WAIT_OFFER' and c.pending==true and H.Count('orb-spend')==spends and H.Count('take')==takes,
  'GUARD '..label..': still waiting, nothing sent: state='..tostring(c.state))
 Bound(label,w,E)

 -- 3. Passive pump: one read, no action (unchanged by the fix).
 Later()
 w=Measure(M.Pump,true)
 c=State()
 check(w.pumps==1 and w.outside==1 and w.echoes==E and w.inside==0,
  'GUARD '..tag..' passive pending pump reads the assignment once: reads='..w.outside..' echoes='..w.echoes)
 check(c.state=='WAIT_OFFER' and H.Count('take')==takes,'GUARD '..tag..' passive pump selects nothing: '..tostring(c.state))

 -- 4. Pending branch: the offer appears and the pump selects the target.
 Later();takes=H.Count('take')
 w=Measure(H.Offer)
 label=tag..' pending Select pump'
 c=State()
 local last=H.actions[#H.actions]
 check(w.pumps==1,'SETUP '..label..': one pump: '..w.pumps..' (nested '..w.nested..')')
 check(H.Count('take')==takes+1 and last and last[1]=='take' and last[2]==410002 and c.state=='WAIT_RESULT',
  'GUARD '..label..': one selection of 410002: takes='..(H.Count('take')-takes)..' state='..tostring(c.state))
 check(w.inside==1 and w.inEchoes==E,
  'GUARD '..label..': the Select precondition makes its own fresh read: guard reads='..w.inside..' echoes='..w.inEchoes)
 Bound(label,w,E)

 -- 5. Settling pump: one read (unchanged by the fix).
 Later()
 w=Measure(H.Result,410002,2)
 c=State()
 check(w.pumps==1 and w.outside==1 and w.echoes==E and w.inside==0,
  'GUARD '..tag..' settling pump reads the assignment once: pumps='..w.pumps..' reads='..w.outside..' echoes='..w.echoes)
 check(c.state==size.final and c.pending==false and c.running==false,
  'GUARD '..tag..' the result settles the run: state='..tostring(c.state)..' (expected '..size.final..')')
end
check(H.Count('orb-spend')==3 and H.Count('take')==3,'GUARD three runs, three spends, three selections')

M.Pump,A.AssignedWishlist,A.Slots,A.Orbs.Spend,A.Orbs.Select=rawPump,rawAssigned,rawSlots,rawSpend,rawSelect
-- A real archived ambiguous source/pair, followed by its live successor gain.
-- The first matrix above still proves fresh reads inside both host guards.
do
 local R=dofile('tests/prototype/orb_recovery_support.lua')
 local HH,MM,AA,OO=R.S.Fresh();R.S.Loadouts(HH,AA);HH.perks.currentChoice={}
 local server=R.Server(HH)
 HH.service.RequestChoice=function()
  SendAddonMessage(R.PREFIX,'16','WHISPER',R.ME);server.queue[#server.queue+1]={op=16,body=''}
 end
 assert(MM.Start(6),'SETUP approved ambiguous successor run')
 HH.Offer();HH.perks.pendingSelectSpellId=nil;HH.perks.currentChoice=nil;OO.offer=false
 for _=1,120 do if HH.Count('orb-spend')==2 then break end;HH.Advance(.25)end
 check(HH.Count('orb-spend')==2 and #R.SavedRow('orbRecoveryArchive')==1,'SETUP real bounded automatic archive and successor')
 server.mode='hold';HH.Offer();HH.Result(410002,2)
 check(R.Saved() and R.Saved().attributionAmbiguous and R.Saved().selectedKey=='410002:2',
  'SETUP current real chosen gain is held for attribution')
 HH.perks.serverBuildSlots=Filler(15);HH.now=HH.now+.25
 local reads=0;local raw=AA.AssignedWishlist
 AA.AssignedWishlist=function(...)reads=reads+1;return raw(...)end
 local function Probe(label)
  reads=0;local before=AA.EchoReconcileStats().projections.slots.echoes
  local spends,takes=HH.Count('orb-spend'),HH.Count('take')
  MM.Pump(true)
  local projected=AA.EchoReconcileStats().projections.slots.echoes-before
  check(R.Saved() and HH.Count('orb-spend')==spends and HH.Count('take')==takes,'GUARD '..label..' retains receipt and submits nothing')
  Bound(label,{pumps=1,outside=reads,echoes=projected,inside=0,inEchoes=0},15*PER)
 end
 Probe('ambiguous pending passive pump')
 assert(MM.Pause() and MM.ContinueBegin(),'SETUP actual explicit attribution check')
 check(MM.ContinueView().stage=='checking','SETUP strict attribution check is active')
 HH.now=HH.now+.25;Probe('ambiguous checking passive pump')
 AA.AssignedWishlist=raw
end
if #over>0 then
 error('BOUND (expected RED until the CX-04 fix): one Orb pump read the assigned Wishlist more than once outside the action callbacks: '
  ..table.concat(over,'; ')..' ('..#over..' pumps over bound; '..checks..' SETUP/GUARD checks passed)',0)
end
print('PASS Orb pump: at most one assignment projection per pump outside the Select/Spend preconditions, which still read fresh; '..checks..' checks')
