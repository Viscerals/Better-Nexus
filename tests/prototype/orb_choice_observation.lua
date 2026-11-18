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
-- (GetServerActiveDesign present) the specialization choice is the player's;
-- a board that shows a memory card (flag 3) admits only a Take of that card;
-- an ordinary three-card draw admits the ordinary actions once the native
-- pick window has passed (restored 2026-11-17). Real TOC, adapter
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
 -- Ordinary offers on the updated provider (restored 2026-11-17): a
 -- three-card board that shows no souvenir admits the ordinary Take, Reroll,
 -- Banish and Freeze and the leveling pick, as on the older provider. Each
 -- waits until the choice is actionable: observed for the settle period and
 -- then a later frame, so a native auto-accept timer armed at the parse has
 -- fired first. The pending-select checks stay.
 local function Settled(FH)
  Nexus.GameAdapter.Board() -- first observation of this choice table
  FH.Advance(1.1)
 end
 FH=FreshBoot(20)
 FH.Board(ORDINARY)
 FH.perks.pendingSelectSpellId=nil
 assert(Nexus.GameAdapter.OrdinaryBoardAllowed()==true,'updated provider: the ordinary gate is open on an ordinary draw')
 accepted,reason=Nexus.GameAdapter.Take(200002)
 assert(accepted==false and Sent(FH,'take')==0 and tostring(reason):find('pick window',1,true),
  'updated provider: a Take before the native pick window has passed: '..tostring(reason))
 Settled(FH)
 accepted,reason=Nexus.GameAdapter.Take(200002)
 assert(accepted==false and Sent(FH,'take')==0,'updated provider: no Take on the first settled frame: '..tostring(reason))
 FH.Advance(0.05)
 assert(Nexus.GameAdapter.Board().strictObservation==true,'updated provider: the leveling pick reads an ordinary draw')
 accepted,reason=Nexus.GameAdapter.Take(200002)
 assert(accepted==true and Sent(FH,'take')==1,'updated provider: an ordinary Take is admitted and sent once: '..tostring(reason))
 for _,try in ipairs({
  {'reroll',function() return Nexus.GameAdapter.Reroll() end},
  {'banish',function() return Nexus.GameAdapter.Banish(0) end},
  {'freeze',function() return Nexus.GameAdapter.Freeze(0) end},
 }) do
  FH=FreshBoot(20)
  FH.Board(ORDINARY)
  FH.perks.pendingSelectSpellId=nil
  Settled(FH)
  -- The runtime's poll: the settled frame is observed, then a later one.
  assert(Nexus.GameAdapter.Board().revealSettling==true,'fixture: the draw is settling on its first settled frame')
  FH.Advance(0.05)
  assert(Nexus.GameAdapter.Board().revealSettling==nil,'the draw is actionable on a later frame')
  local ok,why=try[2]()
  assert(ok==true and Sent(FH,try[1])==1,'updated provider: an ordinary '..try[1]..' is admitted and sent once: '..tostring(why))
 end
 -- The game's own auto-accept timer, armed at the parse, fires 0.18 s later
 -- and takes its card: Nexus then sends nothing (the client's Select latch is
 -- pending), for a Take or a Reroll.
 FH=FreshBoot(20)
 FH.Board(ORDINARY)
 FH.perks.pendingSelectSpellId=nil
 do
  local native=CreateFrame('Frame');native.t=0
  native:SetScript('OnUpdate',function(self,elapsed)
   self.t=self.t+elapsed
   if self.t>=0.18 then self:Hide();FH.service.SelectPerk(200003) end
  end)
  native:Show()
 end
 Settled(FH);FH.Advance(0.05)
 assert(FH.perks.pendingSelectSpellId==200003 and Sent(FH,'take')==1,'fixture: the native timer took its card')
 accepted,reason=Nexus.GameAdapter.Take(200002)
 assert(accepted==false and Sent(FH,'take')==1,'updated provider: no Take while the native pick is pending: '..tostring(reason))
 accepted,reason=Nexus.GameAdapter.Reroll()
 assert(accepted==false and Sent(FH,'reroll')==0,'updated provider: no Reroll while the native pick is pending: '..tostring(reason))
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
 print('PASS updated client: specialization draw refused; a shown memory card admits only its own Take; ordinary draws admit ordinary actions after the native pick window')
end
-- W3, Orb admission on the updated client. Every Echo choice reaches the client
-- through one parser, an Orb draw included. On the updated provider that parser
-- marks a memory card (flag 3), drops a fourth card before it publishes the
-- choice and keeps Perks.currentSpecDraw on a specialization draw; nothing
-- readable binds the shown cards to the Orb that was spent. Orb mode therefore
-- starts nothing, spends nothing and chooses nothing there, nor while the
-- specialization field is present on any provider, and the older provider keeps
-- its admission (positive controls). Real TOC, OrbAdapter and OrbRuntime;
-- synthetic services only. No assertion above is changed.
do
 local function Design() return 0 end
 local function Wants() return false end
 local TARGET={{spellId=410002,quality=2,stacks=2}}
 local OFFER={{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}}
 -- The same three Echoes with the updated parser's memory card fields.
 local MEMORY_FIRST={{spellId=410002,quality=2,isGuaranteed=true,memoryRemaining=1},{spellId=410003,quality=0},{spellId=410004,quality=3}}
 local MEMORY_LAST={{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3,isGuaranteed=true,memoryRemaining=1}}
 -- name, installer(PerkService, Perks), the fixed admission code
 local CASES={
  {'updated provider (GetServerActiveDesign)',function(svc) svc.GetServerActiveDesign=Design end,'updated_client'},
  {'updated provider (WantsMoreOfEcho)',function(svc) svc.WantsMoreOfEcho=Wants end,'updated_client'},
  {'provider marker of the wrong type',function(svc) svc.GetServerActiveDesign=0 end,'updated_client'},
  {'initial specialization draw',function(_,perks) perks.currentSpecDraw={chosen=0} end,'spec_draw'},
  {'later specialization draw',function(_,perks) perks.currentSpecDraw={chosen=2} end,'spec_draw'},
  {'malformed specialization field',function(_,perks) perks.currentSpecDraw='S' end,'spec_draw'},
  {'updated provider showing a specialization draw',function(svc,perks) svc.WantsMoreOfEcho=Wants;perks.currentSpecDraw={chosen=2} end,'updated_client'},
 }
 local function Clear(svc,perks)
  svc.GetServerActiveDesign=nil;svc.WantsMoreOfEcho=nil;perks.currentSpecDraw=nil
 end

 -- World 1: the adapter boundary itself (Acquire, Spend, Select), one owner.
 local H=S.Fresh()
 H.OrbPlan(TARGET)
 local O=Nexus.GameAdapter.Orbs
 local svc,perks=ProjectEbonhold.PerkService,ProjectEbonhold.Perks
 for _,case in ipairs(CASES) do
  case[2](svc,perks)
  local token,why=O.Acquire(assert(O.Read()))
  local owned=O.IsOwned()
  if token then O.Release(token) end
  Clear(svc,perks)
  assert(token==nil and owned==false and type(why)=='string' and why~='',
   case[1]..': Orb mode took ownership of a run on a client where no Orb action is admitted')
 end
 local token,fresh=O.Acquire(assert(O.Read()))
 assert(token and type(fresh)=='table' and O.IsOwned(),
  'legacy positive control: the older provider still starts Orb mode: '..tostring(fresh))
 local key
 for k,n in pairs(fresh.granted) do if n>0 and (not key or k<key) then key=k end end
 assert(key,'fixture: one rolled Echo copy is available as the Orb source')
 for _,case in ipairs(CASES) do
  case[2](svc,perks)
  local ok,kind,why,code=O.Spend(token,key,fresh)
  Clear(svc,perks)
  assert(ok==nil and kind=='REJECTED' and H.Count('orb-spend')==0,
   case[1]..': an Orb spend reached the game')
  assert(code=='CLIENT_CONTRACT' and type(why)=='string' and why:find('No Orb or choice was sent',1,true),
   case[1]..': the spend refusal names the client contract')
 end
 -- Boundary drift: the provider marker, or the specialization field, appears
 -- inside the final guard, after the fresh read; the host is not called.
 for _,drift in ipairs({CASES[2],CASES[5]}) do
  local ok,kind,_,code=O.Spend(token,key,fresh,function() drift[2](svc,perks);return true end)
  Clear(svc,perks)
  assert(ok==nil and kind=='REJECTED' and H.Count('orb-spend')==0 and code=='CLIENT_CONTRACT',
   drift[1]..' installed inside the final guard reached ConfirmSpend')
 end
 local spent,spendKind=O.Spend(token,key,fresh,function() return true end)
 assert(spent==true and spendKind=='SUBMITTED' and H.Count('orb-spend')==1,
  'legacy positive control: the older provider still sends exactly one Orb')
 H.O.charges=H.O.charges-1;H.O.offer=true
 H.Board(OFFER)
 local boardKey=assert(O.Read()).boardKey
 for _,case in ipairs(CASES) do
  case[2](svc,perks)
  local ok,kind,why,code=O.Select(token,1,boardKey,410002)
  Clear(svc,perks)
  assert(ok==nil and kind=='REJECTED' and H.Count('take')==0,
   case[1]..': an automatic Orb choice reached SelectPerk')
  assert(code=='CLIENT_CONTRACT' and type(why)=='string' and why:find('No Orb or choice was sent',1,true),
   case[1]..': the choice refusal names the client contract')
 end
 -- A visible memory card is no authority for an Orb choice either: neither
 -- the card itself nor another card is taken; a trimmed list (the plain
 -- three-card OFFER above) is not proof that no memory card was offered.
 for _,memory in ipairs({{'the visible memory card',MEMORY_FIRST},{'a card beside the memory card',MEMORY_LAST}}) do
  svc.GetServerActiveDesign=Design
  H.Board(memory[2])
  local ok,kind,_,code=O.Select(token,1,assert(O.Read()).boardKey,410002)
  Clear(svc,perks)
  assert(ok==nil and kind=='REJECTED' and H.Count('take')==0 and code=='CLIENT_CONTRACT',
   'updated provider: '..memory[1]..' was taken as an Orb choice')
 end
 H.Board(OFFER)
 for _,drift in ipairs({CASES[1],CASES[4]}) do
  local ok,kind,_,code=O.Select(token,1,boardKey,410002,function() drift[2](svc,perks);return true end)
  Clear(svc,perks)
  assert(ok==nil and kind=='REJECTED' and H.Count('take')==0 and code=='CLIENT_CONTRACT',
   drift[1]..' installed inside the final guard reached SelectPerk')
 end
 local picked,pickKind=O.Select(token,1,boardKey,410002,function() return true end)
 assert(picked==true and pickKind=='SUBMITTED' and H.Count('take')==1,
  'legacy positive control: the older provider still sends exactly one Orb choice')
 assert(H.Count('orb-spend')==1,'the refusals and the controls sent one Orb in all')
 -- The classifier itself: fixed codes, and an unreadable Perks table refuses.
 assert(O.ClientAdmission()==true,'older provider, no specialization field: admitted')
 for _,case in ipairs(CASES) do
  case[2](svc,perks)
  local admitted,why,code=O.ClientAdmission()
  Clear(svc,perks)
  assert(admitted==false and code==case[3] and type(why)=='string',case[1]..': admission code '..tostring(code))
 end
 ProjectEbonhold.Perks=nil
 local admitted,_,code=O.ClientAdmission()
 ProjectEbonhold.Perks=perks
 assert(admitted==false and code=='unreadable','an unreadable Perks table is not the older provider')
 O.Release(token)

 -- World 2: the real runtime. The older provider starts and spends one Orb;
 -- the updated marker then appears before its offer.
 local M
 H,M=S.Fresh()
 O=Nexus.GameAdapter.Orbs
 svc,perks=ProjectEbonhold.PerkService,ProjectEbonhold.Perks
 H.OrbPlan(TARGET);H.Approve(3,false)
 assert(H.Count('orb-spend')==1 and M.Status().running,
  'legacy positive control: an approved run on the older provider requests one Orb')
 svc.WantsMoreOfEcho=Wants
 H.O.charges=H.O.charges-1;H.O.offer=true
 H.Board(OFFER)
 M.Pump()
 local status=M.Status()
 assert(H.Count('take')==0,'updated provider: the runtime sent an automatic Orb choice')
 assert(status.state=='PAUSED' and status.pending and not status.running and status.spent==1,
  'the refused choice pauses the run and keeps the confirmed spend and its receipt')
 assert(status.reason==select(2,O.ClientAdmission()),'the pause reason is the client admission reason')
 local receipt=Nexus.Store.State().orbRefinement.pending
 assert(receipt and receipt.spendConfirmed and not receipt.selectionAttempted
  and not receipt.selectionRefused and receipt.selectedKey==nil,
  'no selection attempt or proposed Echo is recorded for a choice that was never admitted')
 -- W3 revision 2: Resume of this kept receipt, with its offer open, is refused
 -- by the same client admission before any side effect (ordinary Auto OFF,
 -- the receipt, the run state), not started and then paused again.
 local function AutoNow() local stats=Nexus.RecomputeStats();return stats and stats.autoEnabled end
 -- W3 revision 4 (Standards N-3): ordinary Auto is already OFF here (Confirm
 -- switched it off, and the Auto command is refused while an Orb run holds),
 -- so the unchanged-Auto comparison below is a state check only. It cannot
 -- show that the refusal comes before the switch. The order is observed
 -- directly instead: OrbRuntime's turnAutoOff looks
 -- Nexus.DisableOrdinaryAutomation up at each call, and this forwarding
 -- wrapper (every argument, return and error passes through) counts each
 -- invocation without changing what the action does.
 local autoOff={n=0,own=rawget(Nexus,'DisableOrdinaryAutomation'),original=Nexus.DisableOrdinaryAutomation}
 assert(type(autoOff.original)=='function','fixture: the ordinary Auto turn-off action exists')
 Nexus.DisableOrdinaryAutomation=function(...) autoOff.n=autoOff.n+1;return autoOff.original(...) end
 local function ResumeRefused(name)
  local autoBefore,reasonBefore=AutoNow(),M.Status().reason
  local offBefore=autoOff.n
  local resumedNow,why=M.Resume()
  local after=M.Status()
  assert(autoOff.n==offBefore,
   name..': a refused Resume invoked the ordinary Auto turn-off action ('..tostring(autoOff.n-offBefore)..' call)')
  assert(not resumedNow and why==select(2,O.ClientAdmission()),
   name..': Resume was not refused with the client admission reason: '..tostring(why))
  assert(AutoNow()==autoBefore and after.state=='PAUSED' and after.pending and not after.running
   and after.reason==reasonBefore and after.spent==1,
   name..': a refused Resume changed ordinary Auto, the run state or the kept receipt')
  assert(H.Count('take')==0 and H.Count('orb-spend')==1,name..': a refused Resume sent an Orb or a choice')
 end
 ResumeRefused('updated provider, offer open')
 M.Resume();M.Pump()
 assert(H.Count('take')==0 and H.Count('orb-spend')==1 and M.Status().state=='PAUSED',
  'Resume on the updated provider sends no choice and no second Orb')
 -- The same receipt under a specialization draw on a provider without the readers.
 svc.WantsMoreOfEcho=nil;perks.currentSpecDraw={chosen=2}
 ResumeRefused('specialization draw, offer open')
 M.Resume();M.Pump()
 assert(H.Count('take')==0 and H.Count('orb-spend')==1 and M.Status().state=='PAUSED',
  'a specialization draw is not chosen as an Orb offer')
 -- Positive control on the same receipt: the older contract is admitted again.
 perks.currentSpecDraw=nil
 assert(autoOff.n==0,'no refused Resume of the kept receipt invoked the ordinary Auto turn-off action')
 M.Resume();M.Pump()
 assert(H.Count('take')==1 and H.Count('orb-spend')==1,
  'legacy positive control: the same receipt is chosen once on the older provider')
 assert(autoOff.n==1,
  'control: the admitted Resume of the kept receipt invokes the ordinary Auto turn-off action once ('..tostring(autoOff.n)..')')
 -- The next Orb: the marker appears before the result settles the first.
 svc.GetServerActiveDesign=Design
 H.Result(410002,2)
 for _=1,3 do M.Pump() end
 status=M.Status()
 assert(H.Count('orb-spend')==1 and not status.pending,
  'updated provider: the settled run requested a second Orb')
 M.Pause()
 local resumed,resumeWhy=M.Resume()
 assert(not resumed and type(resumeWhy)=='string' and H.Count('orb-spend')==1,
  'updated provider: Resume toward a next spend is refused and sends nothing')
 assert(autoOff.n==1,'updated provider: the refused Resume toward a next spend invoked the ordinary Auto turn-off action')
 svc.GetServerActiveDesign=nil
 H.now=H.now+3.1
 M.Resume();M.Pump()
 assert(H.Count('orb-spend')==2 and H.Count('take')==1,
  'legacy positive control: the same run spends its next single Orb on the older provider')
 assert(autoOff.n==2,
  'control: the admitted Resume toward the next spend invokes the ordinary Auto turn-off action once ('..tostring(autoOff.n)..')')
 rawset(Nexus,'DisableOrdinaryAutomation',autoOff.own)
 assert(Nexus.DisableOrdinaryAutomation==autoOff.original,'the turn-off counter was removed')
 M.Stop()
 print('PASS W3 updated-client Orb admission: no start, spend or choice on the updated provider or a specialization draw; older provider unchanged')
end
print('PASS orb_choice_observation')
