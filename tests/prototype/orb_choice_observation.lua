-- Diagnostic choice presence is separate from Orb execution and action latches.
-- Real TOC, adapter, runtime and report builder; synthetic services only.
local S=dofile('tests/prototype/orb_loadout_hold_support.lua')
do
-- Keep every pre-existing Orb section ahead of the new passive context when
-- a summary is full. Each scenario uses Fresh to isolate its runtime and data.
local budgetH,budgetM=S.Fresh()
budgetH.OrbPlan();budgetH.Approve(1,false);budgetM.Stop()
local budgetStatus=budgetM.Status()
assert(budgetStatus.pending and budgetStatus.state=='STOPPED' and budgetStatus.reserved==1,
 'budget fixture: a deliberate Stop retains one unresolved fake operation')
local boundary=budgetM.BoundaryDiagnostics()
assert(boundary.receiptPresent and boundary.snapshot and boundary.snapshot.chargesBefore==10
 and boundary.snapshot.chargesNow==10 and boundary.snapshot.chargeRelation=='equal'
 and boundary.snapshot.offerPresent==false and boundary.snapshot.pickInFlight==false,
 'budget fixture: the actual operation retains its receipt and charge/offer/pick comparisons')
Nexus.SupportIncidents.Clear()
local readiness={}
for i=1,12 do readiness['source'..i]=string.rep('d',47)end
for i=1,20 do
 Nexus.SupportIncidents.Record('catalog-refusal',{
  reason=string.rep('r',96)..i,producer=string.rep('p',96),
  operation='budget fixture',counts={ordinary=80,locked=0,total=80},
  readiness=readiness,committed=false})
end
local summary=Nexus.SupportReport.Summary()
assert(#summary>7500 and #summary<=Nexus.SupportReport.SUMMARY_MAX_BYTES
 and (summary:find('context line(s) omitted',1,true)
  or summary:find('summary shortened to stay under',1,true)),
 'fixture reaches the summary budget and reports omitted context')
assert(summary:find('Orb action: unresolved in this session; state=STOPPED',1,true)
 and summary:find('client-observed spend=no; choice=none',1,true),
 'near-budget summary keeps the unresolved receipt and spend evidence before passive choice context')
assert(summary:find('Orb boundary diagnostics:',1,true)
 and summary:find('receipt_present=yes',1,true)
 and summary:find('Orb comparisons: before=10; now=10; charge_relation=equal',1,true),
 'near-budget summary keeps existing receipt presence and retained comparisons')
local passiveOmitted=0
for _,prefix in ipairs({'Echo choice:','Orb service:','Orb runner:'})do
 if not summary:find(prefix,1,true)then passiveOmitted=passiveOmitted+1 end
end
assert(passiveOmitted>=1,
 'the full summary omits passive context after retaining the existing Orb evidence')
assert(budgetH.Count('orb-spend')==1 and budgetH.Count('take')==0,
 'preparing the near-budget summary adds no action to the single fixture spend')
end

local H=S.Fresh()
local initial=assert(Nexus.SupportReport.Prepare({}))
assert(table.concat(initial.chunks,''):find('Echo choice: presence=unknown',1,true),
 'a never-observed choice is explicitly unknown in the report')
H.OrbPlan()
H.Board({{spellId=410001,quality=1},{spellId=410003,quality=0},{spellId=410004,quality=3}})
H.O.offer=false
H.perks.pendingSelectSpellId=nil
local status=H.M.Status()
assert(status.state=='IDLE' and status.running==false and status.pending==false,
 'fixture: an ordinary choice can exist while the Orb runner is idle')
local view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='present',
 'an open ordinary choice must be reported as present even with an idle runner')
assert(view.choiceCount==3,'the observation reports the three actual choices')
local report=assert(Nexus.SupportReport.Prepare({}))
assert(table.concat(report.chunks,''):find('Echo choice: presence=present',1,true),
 'the prepared support report exposes observed choice presence')
H.perks.currentChoice={}
H.M.Status()
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='absent' and view.choiceCount==0,
 'an explicit valid empty choice table is observed absence')
local service=ProjectEbonhold.PerkService
local getter=service.GetCurrentChoice
H.perks.currentChoice=nil
H.M.Status()
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='unknown' and view.choiceCount==nil,
 'a nil API result is not a confirmed empty choice table')
service.GetCurrentChoice=function()error('SYNTHETIC_PRIVATE_CHOICE_ERROR')end
H.M.Status()
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='unknown' and view.choiceCount==nil and H.M.ReadinessView().stage=='choice',
 'a failed choice getter reports unknown and its refusal stage')
report=assert(Nexus.SupportReport.Prepare({}))
local text=table.concat(report.chunks,'')
assert(text:find('Echo choice: presence=unknown',1,true)
 and not text:find('SYNTHETIC_PRIVATE_CHOICE_ERROR',1,true),
 'the report retains unknown without leaking raw getter errors')
service.GetCurrentChoice=nil
H.M.Status()
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='unknown' and view.choiceCount==nil and H.M.ReadinessView().stage=='capability',
 'an unavailable API cannot become observed absence')
service.GetCurrentChoice=getter
H.perks.currentChoice={unexpected={spellId=410001,quality=1}}
H.M.Status()
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='unknown' and view.choiceCount==nil,
 'a non-array choice response is not confirmed empty just because ipairs skipped it')
H.perks.currentChoice={}
H.M.Status()
local sample=Nexus.GameAdapter.ChoicePresenceView()
H.now=H.now+2
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='unknown' and view.lastChoicePresence=='absent'
 and view.choiceFreshness=='stale' and view.at==sample.at,
 'an aging frozen sample retains history but must not report current absence')
H.M.Status()
sample=Nexus.GameAdapter.ChoicePresenceView()
H.Fire('PLAYER_LEAVING_WORLD')
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='unknown' and view.choiceFreshness=='transition'
 and view.at==sample.at and view.lastChoicePresence=='absent',
 'loading invalidates current absence even when no Orb run ever started')
H.Fire('PLAYER_ENTERING_WORLD')
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='unknown' and view.choiceFreshness=='transition',
 'world entry does not refresh the old captured choice observation')
H.M.Status()
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='absent' and view.choiceFreshness=='recent'
 and view.choiceSampleEpoch==view.choiceCurrentEpoch,
 'a new ordinary read belongs to the new client epoch, without claiming server freshness')
local clock=H.now
for _,badClock in ipairs({1/0,0/0,clock-1}) do
 H.now=badClock
 view=Nexus.GameAdapter.ChoicePresenceView()
 assert(view.choicePresence=='unknown' and view.choiceFreshness=='unknown',
  'an unavailable or regressed client clock cannot assert recent absence or a known stale age')
end
H.now=clock
local getTime=GetTime
GetTime=nil
H.M.Status()
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='unknown' and view.choiceFreshness=='unknown'
 and view.choiceObservedAt==nil,
 'an absent client clock is unavailable rather than an invented time zero')
GetTime=getTime
H.M.Status()
H.Board({{spellId=410001,quality=1},{spellId=410003,quality=0},{spellId=410004,quality=3}})
H.O.offer=false
H.M.Status()
local assignment=Nexus.GameAdapter.AssignedWishlist
Nexus.GameAdapter.AssignedWishlist=function()error('SYNTHETIC_PRE_OBSERVATION_ERROR')end
local success=pcall(H.M.Status)
Nexus.GameAdapter.AssignedWishlist=assignment
view=Nexus.GameAdapter.ChoicePresenceView()
assert(not success and view.choicePresence=='unknown' and view.lastChoicePresence=='present',
 'a failed ordinary read cannot leave a prior choice asserted as current')
H.M.Status()
H.M.Stop()
status=H.M.Status()
view=Nexus.GameAdapter.ChoicePresenceView()
assert(status.state=='STOPPED' and not status.running and view.choicePresence=='present',
 'a deliberate Orb Stop does not resolve an ordinary open choice')
assert(H.Count('orb-spend')==0 and H.Count('take')==0,
 'observing and preparing a report sends no Orb or choice')
-- Updated client (2026-11 capture): Root probes probe_spec_admission.lua and
-- probe_spec_drift.lua, and the second Spec review. On the updated provider
-- (GetServerActiveDesign present) the specialization choice is the player's,
-- and the only automatic choice action Nexus admits is a Take of the memory
-- card (flag 3) the published choice shows: a hidden fourth memory card and
-- an armed native automatic pick cannot be observed, so every other Take and
-- every Reroll, Banish and Freeze is unavailable there. Real TOC, adapter
-- Take/Reroll/Banish/Freeze and Board; synthetic services only.
do
 local function FreshBoot(level)
  Nexus=nil;NexusDB=nil;SlashCmdList=nil
  local FH=dofile('tests/prototype/harness.lua')
  FH.playerLevel=level or 10
  FH.service.GetServerMaxSlots=function() return 10 end
  FH.service.GetServerActiveDesign=function() return 0 end
  FH.perks.serverActiveSlot=1
  FH.perks.serverActiveDesign=0
  FH.perks.serverBuildSlots={[1]={name='Live',verified=true,memoryTotal=3,memoryRemaining=0,echoes={}}}
  ProjectEbonhold.OrbService={IsStateKnown=function() return true end,GetCharges=function() return 0 end,
   IsOfferPending=function() return false end,RequestCharges=function() end}
  FH.Boot()
  return FH
 end
 local function Sent(FH,kind) local n=0;for _,a in ipairs(FH.actions) do if a[1]==kind then n=n+1 end end;return n end
 local ORDINARY={{spellId=200001,quality=1},{spellId=200002,quality=2},{spellId=200003,quality=3}}
 local MEMORY={{spellId=200001,quality=1,isGuaranteed=true},{spellId=200002,quality=2},{spellId=200003,quality=3}}
 -- The initial specialization draw (chosen 0): no Take (Root probe), no Reroll.
 local FH=FreshBoot(10)
 FH.Board(ORDINARY)
 FH.perks.currentSpecDraw={chosen=0}
 FH.perks.pendingSelectSpellId=nil
 local accepted,reason=Nexus.GameAdapter.Take(200001)
 assert(accepted==false,'initial specialization reached SelectPerk instead of refusing automatic admission')
 assert(Sent(FH,'take')==0,'specialization must not be selected')
 accepted=Nexus.GameAdapter.Reroll()
 assert(accepted==false and Sent(FH,'reroll')==0,'no reroll on the specialization choice')
 assert(Nexus.GameAdapter.Board().strictObservation==false,'the leveling pick refuses the specialization choice')
 FH.perks.currentSpecDraw={chosen=2}
 assert(Nexus.GameAdapter.Board().strictObservation==false,'the leveling pick refuses a specialization draw')
 -- Ordinary offers on the updated provider: no automatic action at all, even
 -- with live rows that look settled (cached rows are no draw authority).
 FH=FreshBoot(20)
 FH.Board(ORDINARY)
 for _,try in ipairs({
  {'take',function() return Nexus.GameAdapter.Take(200002) end},
  {'reroll',function() return Nexus.GameAdapter.Reroll() end},
  {'banish',function() return Nexus.GameAdapter.Banish(0) end},
  {'freeze',function() return Nexus.GameAdapter.Freeze(0) end},
 }) do
  local ok,why=try[2]()
  assert(ok==false and Sent(FH,try[1])==0,'updated provider: an ordinary '..try[1]..' is unavailable: '..tostring(why))
 end
 assert(Nexus.GameAdapter.Board().strictObservation==false,'updated provider: the leveling pick is unavailable')
 -- The memory card: another card is refused; the card itself is the positive
 -- control; no Reroll on that board.
 FH=FreshBoot(20)
 FH.Board(MEMORY)
 accepted=Nexus.GameAdapter.Take(200002)
 assert(accepted==false and Sent(FH,'take')==0,'taking another card would give up the memory card')
 accepted=Nexus.GameAdapter.Reroll()
 assert(accepted==false and Sent(FH,'reroll')==0,'no reroll on a memory board')
 assert(Nexus.GameAdapter.Board().strictObservation==false,'the leveling pick refuses a memory board')
 accepted=Nexus.GameAdapter.Take(200001)
 assert(accepted==true and Sent(FH,'take')==1,'positive control: the memory card itself stays admitted')
 -- Root probe_spec_drift on the admitted path: the specialization draw, or a
 -- cleared memory flag, installed inside the granted read after admission is
 -- refused at the send boundary (the only remaining Take path).
 for _,drift in ipairs({
  {'specialization draw',function(P) P.currentSpecDraw={chosen=0} end},
  {'memory flag cleared',function(P) P.currentChoice[1].isGuaranteed=false end},
 }) do
  FH=FreshBoot(20)
  FH.Board(MEMORY)
  FH.perks.pendingSelectSpellId=nil
  local oldGranted=FH.service.GetGrantedPerks
  FH.service.GetGrantedPerks=function(...) drift[2](FH.perks);FH.service.GetGrantedPerks=oldGranted;return oldGranted(...) end
  accepted=Nexus.GameAdapter.Take(200001)
  assert(accepted==false and Sent(FH,'take')==0,drift[1]..' installed inside a callout reached SelectPerk')
 end
 print('PASS updated client: specialization draw and memory card refuse automatic admission; ordinary actions unavailable: '..tostring(reason))
end
print('PASS orb_choice_observation')
