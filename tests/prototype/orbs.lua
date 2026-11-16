local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,msg)assert(v,msg);checks=checks+1 end
H.OrbPlan();local initial=M.Status()
check(initial.state=='IDLE' and H.Count('orb-spend')==0,'off by default')
SlashCmdList.NEXUS('orbs');check(NexusOrbPanel:IsShown() and H.Count('orb-spend')==0,'opening panel spends nothing')
check(M.SetRecycle(false),'fallback opt-in')
local preview,err=M.Prepare();check(not preview,'unapproved pool refused')
SlashCmdList.NEXUS('auto')
check(Nexus.RecomputeStats().autoEnabled==true,'control: ordinary master was enabled before approval')
-- W3 revision 2 (reviews W3-S1 / F-3): on a client where no Orb action is
-- admitted, the runtime Start route (readiness, Prepare, Start, Confirm) is
-- refused BEFORE ordinary Auto is switched off. Each refusal leaves ordinary
-- Auto, the Orb ownership, the Orb balance and the choices as they were. The
-- original approval below then runs unchanged on the older provider: that is
-- the positive control, and it shows the refusals left nothing behind.
do
 local Orbs=Nexus.GameAdapter.Orbs
 local svc,perks=ProjectEbonhold.PerkService,ProjectEbonhold.Perks
 local function Design() return 0 end
 local function Wants() return false end
 local function Clear()
  svc.GetServerActiveDesign=nil;svc.WantsMoreOfEcho=nil;perks.currentSpecDraw=nil
  ProjectEbonhold.Perks=perks
 end
 local charges=O.charges
 local function unchanged(name)
  check(Nexus.RecomputeStats().autoEnabled==true,name..': ordinary Auto was switched off by a refused Orb start')
  check(Orbs.IsOwned()==false,name..': a refused Orb start took the Orb ownership')
  check(H.Count('orb-spend')==0 and H.Count('take')==0 and O.charges==charges,
   name..': a refused Orb start sent an Orb or a choice, or changed the balance')
  check(Nexus.Store.State().orbRefinement.pending==nil,name..': a refused Orb start left a receipt')
 end
 check(M.Status().canStart==true,'fixture: the older provider can start an assigned Orb run')
 -- name, installer, whether the display read still works in that state
 local CASES={
  {'updated provider (GetServerActiveDesign)',function() svc.GetServerActiveDesign=Design end,true},
  {'updated provider (WantsMoreOfEcho)',function() svc.WantsMoreOfEcho=Wants end,true},
  {'provider marker of the wrong type',function() svc.GetServerActiveDesign=0 end,true},
  {'initial specialization draw field',function() perks.currentSpecDraw={chosen=0} end,true},
  {'later specialization draw field',function() perks.currentSpecDraw={chosen=2} end,true},
  {'malformed specialization field',function() perks.currentSpecDraw='S' end,true},
  {'unreadable client (no Perks table)',function() ProjectEbonhold.Perks=nil end,false},
 }
 for _,case in ipairs(CASES) do
  local name=case[1]
  case[2]()
  local admitted,reason=Orbs.ClientAdmission()
  check(admitted==false and type(reason)=='string' and reason~='',name..': fixture state is refused by the client admission')
  local plan,planWhy=M.Prepare('assigned')
  local started,startWhy=M.Start()
  local view=case[3] and M.Status() or nil
  Clear()
  check(plan==nil and planWhy==reason,name..': Prepare returned a plan or another reason: '..tostring(planWhy))
  check(not started and startWhy==reason,name..': Start was not refused with the client reason: '..tostring(startWhy))
  if view then
   check(view.canStart==false and view.startReason==reason and view.state=='IDLE',
    name..': the window readiness still offers Start, or gives another reason')
  end
  unchanged(name)
 end
 -- The provider changes between Prepare and Confirm: the plan was reviewed on
 -- the older provider; Confirm reads the client again before any side effect.
 for _,case in ipairs({CASES[2],CASES[5]}) do
  local name=case[1]..' after Prepare'
  local plan,planWhy=M.Prepare('assigned')
  check(plan and plan.token,'older provider: Prepare returns a plan to confirm: '..tostring(planWhy))
  case[2]()
  local _,reason=Orbs.ClientAdmission()
  local confirmed,confirmWhy=M.Confirm(plan.token,plan.historyAcknowledgment)
  Clear()
  check(not confirmed and confirmWhy==reason,name..': Confirm was not refused with the client reason: '..tostring(confirmWhy))
  unchanged(name)
 end
 check(M.Status().state=='IDLE' and M.Status().canStart==true,
  'older provider again: the refusals left the run idle and startable')
end
H.Approve(2,false)
check(H.Count('orb-spend')==1,'one Orb requested after explicit confirmation')
local last=H.actions[#H.actions];check(last[1]=='orb-spend'and last[3]==1,'single Orb boundary')
check(Nexus.RecomputeStats().autoEnabled==false,'ordinary Auto off')
check(M.Status().reserved==1 and M.Status().spent==0,'exposure reserved not falsely billed confirmed')
check(not A.Take(410002) and not A.LockPerk(410007),'ordinary and locked writes gated')
for i=1,5 do M.Pump()end;check(H.Count('orb-spend')==1,'no replay waiting for offer')
H.Offer();check(H.Count('take')==1,'select actual target offer')
check(M.Status().spent==1 and M.Status().reserved==0,'confirmed spend replaces exposure')
local before=H.Count('take');M.Pump();check(H.Count('take')==before,'no duplicate selection')
H.Result(410002,2)
check(M.Status().state=='COMPLETE','exact result completes target')
check(not M.BlocksOrdinary(),'ordinary owner released after settled completion')
check(Nexus.RecomputeStats().autoEnabled==false,'ordinary Auto never restarted')
check(Nexus.Store.State().orbRefinement.pending==nil,'recovery marker cleared only on result')
check(H.Count('orb-spend')==1,'target completion stops next spend')
print('PASS Orb real adapter/runtime/UI single-target loop checks='..checks)
