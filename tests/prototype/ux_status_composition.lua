-- M7 (UX status composition): the destination, Auto, Sync and Orb status the
-- setup checklist states are composed from the same facts the panel already
-- shows. Panel.DestinationFacts is the one source of the destination lines:
-- the My Builds tooltip, Panel.DestinationLines and the checklist read it. The
-- status lines follow the committed HUD model (Auto selection and its hold),
-- SyncModePolicy.Mode and the passive OrbRuntime.ReasonView; a read that
-- fails is "not known", never OFF, Automatic or "no run", and an Orb owner not
-- yet read this session is "not known" (an unresolved saved receipt is not
-- ruled out). Reading the facts changes neither the model nor anything else.
-- The Build Library's receive window reads "listening for answers";
-- "receiving" is reserved for reception in progress.
-- UX-09/LP-09 Orb reason (C6-C8): the checklist's Orb line shows the reason
-- the real Orb owner last recorded for its run (paused, stopped, recovery),
-- said as recorded, and points to Open Orbs; it states no Resume, Continue,
-- reload or refund. Repeated SetupFacts and checklist show/refresh are
-- measured at pass-through counters (saved state, assignment, context,
-- adapter read, capture, transport, observer, pump, refresh, spend, select,
-- durable write) against the same path without the Orb owner; the oracle
-- itself calls neither Status nor CompactStatus inside a measured interval.
-- Categories (view_regression_support): EXPECT is behaviour added in M7
-- (C1-C5: predicted to fail on accepted M6 0924d06a; C6-C8 on e8e74693, where
-- the operator executed the C6 visible-reason omission red; otherwise not
-- executed by the author); missing functions are a failed EXPECT, not a raised
-- scenario. GUARD already holds there and must keep holding; SETUP is the
-- fixture (and the oracle discriminators).
-- Oracles: the real panel model and tooltip, Panel/UserText functions, the
-- policy and runtime reads (stubbed only to inject an unreadable or a given
-- mode or view, restored at once), the real OrbRuntime lifecycle (Start,
-- Pause, Stop, a fresh owner load, its own recovery read), the visible
-- checklist fontstrings, the renderer source for the vocabulary lint, and the
-- counted writers, actions and sends. Real TOC boot; synthetic services;
-- offline evidence only, no native claim.
local S=dofile('tests/prototype/orb_loadout_hold_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('ux_status_composition')
local H,A
local E2={{spellId=201175,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}

local function Boot(active,slots)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 NexusEditorFrame=nil;NexusPanel=nil;NexusHelpWindow=nil;NexusSetupChecklist=nil
 H=dofile('tests/prototype/harness.lua')
 H.playerLevel=80
 wipe(H.db)
 H.AddEcho(201174,'Echo Free',0,5);H.AddEcho(201175,'Echo Fire',0,5)
 H.service.GetServerMaxSlots=function() return 6 end
 H.perks.serverBuildSlots=slots or {[2]={name='Fire PvE',verified=true,echoes=E2},[107]={name='W-Free',verified=false,echoes=EF}}
 H.perks.serverActiveSlot=active
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,GetCharges=function()return 0 end,
  IsOfferPending=function()return false end,RequestCharges=function()end,
  ConfirmSpend=function() error('reading status must not spend') end}
 H.Boot();A=Nexus.GameAdapter
 H.Notify();A.Poll();H.Advance(1)
 if NexusQuickStart and NexusQuickStart:IsShown() then NexusQuickStart:Hide() end
end
local function Refresh()
 Nexus.Panel.Show()
 if Nexus.RequestRecompute then Nexus.RequestRecompute() end
 H.Notify();A.Poll();H.Advance(1)
 return Nexus.Panel._lastModel
end
local function HeaderTip()
 local button=NexusPanel and NexusPanel._switchBtn
 if not (button and button:GetScript('OnEnter')) then return '' end
 return V.Plain(table.concat(V.TooltipLines(function() button:GetScript('OnEnter')(button) end),'\n'))
end
local function Has(text,needle) return tostring(text or ''):find(needle,1,true)~=nil end
local function Serialize(v,seen)
 seen=seen or {}
 if type(v)~='table' then return tostring(v) end
 if seen[v] then return '<cycle>' end
 seen[v]=true
 local keys={}
 for k in pairs(v) do keys[#keys+1]=tostring(k) end
 table.sort(keys)
 local out={}
 for _,k in ipairs(keys) do
  local value=v[k];if value==nil then value=v[tonumber(k)] end
  out[#out+1]=k..'='..Serialize(value,seen)
 end
 seen[v]=nil
 return '{'..table.concat(out,',')..'}'
end

-- Orb reason fixtures (C6-C8): the real Orb owner and lifecycle from the
-- existing synthetic Orb helpers (orbs_support through S.Fresh).
local PLAN={{spellId=410002,quality=2,stacks=3}}
local PAUSED_REASON='Paused. An accepted spend cannot be undone; the native offer remains available.'
local STOPPED_REASON='Stopped. A submitted operation may still finish; resolve any pending offer manually.'
local RECOVERY_REASON='An earlier Orb action is unresolved. Nothing will restart. Nexus is checking, read-only, whether its offer is still open.'
-- The visible line at e8e74693 for a paused run with a pending spend (the omission red).
local PREIMAGE_PAUSED='Orbs (optional): run paused; a result is pending.'
local function OrbBoot()
 NexusPanel=nil;NexusSetupChecklist=nil;NexusHelpWindow=nil;NexusEditorFrame=nil
 local h,m,a,o=S.Fresh()
 H,A=h,a
 if NexusQuickStart and NexusQuickStart:IsShown() then NexusQuickStart:Hide() end
 return h,m,a,o
end
-- The visible Orb line of the shared checklist (its third status fontstring).
local function OrbLineShown()
 local f=_G.NexusSetupChecklist
 local fs=f and f.status and f.status[3]
 return fs and V.Plain(fs:GetText() or '') or ''
end
-- The actual consumer: repeated SetupFacts, the checklist shown and refreshed,
-- and its own twice-a-second update handler (no other frame is advanced).
local function ConsumerPath()
 for _=1,3 do Nexus.Panel.SetupFacts() end
 local f=Nexus.QuickStart.ShowChecklist()
 Nexus.QuickStart.RefreshChecklist()
 local update=f and f:GetScript('OnUpdate')
 if update then update(f,0.6);update(f,0.6) end
 return OrbLineShown()
end
-- The visible consumer oracle: the owner's reason, shown as recorded.
local function ShowsReason(line,reason)
 return type(reason)=='string' and reason~='' and Has(line,'Last reason Nexus recorded: '..reason)
end
local function Without(text,needle)
 text=tostring(text or '')
 if type(needle)~='string' or needle=='' then return text end
 local s,e=text:find(needle,1,true)
 if not s then return text end
 return text:sub(1,s-1)..text:sub(e+1)
end
-- Outside the owner's own reason, the line offers no action and no reload promise.
local function Promises(line,reason)
 local rest=Without(line,reason)
 return Has(rest,'Resume') or Has(rest,'Continue') or Has(rest,'reload') or Has(rest,'refund')
end
local function Utf8Valid(s)
 local i,n=1,#s
 while i<=n do
  local c=s:byte(i)
  local w=(c<0x80 and 1) or (c>=0xC2 and c<0xE0 and 2) or (c>=0xE0 and c<0xF0 and 3) or (c>=0xF0 and c<0xF5 and 4) or nil
  if not w or i+w-1>n then return false end
  for j=i+1,i+w-1 do local d=s:byte(j);if d<0x80 or d>0xBF then return false end end
  i=i+w
 end
 return true
end
-- Pass-through counters at the work seams a passive read must not reach;
-- the returned function restores every wrapped field. Behaviour is unchanged.
local ZERO={'assignment','context','poll','adapterRead','balance','capture','transport','observer',
 'refresh','spend','select','pump','durable'}
local function Seams()
 local counts,saved={},{}
 local function wrap(t,k,label)
  local real=type(t)=='table' and t[k]
  if type(real)~='function' then return end
  saved[#saved+1]={t,k,real}
  t[k]=function(...) counts[label]=(counts[label] or 0)+1;return real(...) end
 end
 local G=Nexus.GameAdapter;local B=G and G.Orbs
 wrap(Nexus.Store,'State','storeState')
 wrap(G,'AssignedWishlist','assignment');wrap(G,'OwnershipTrustView','context');wrap(G,'Poll','poll')
 wrap(B,'Read','adapterRead');wrap(B,'Balance','balance');wrap(B,'CaptureStart','capture')
 wrap(B,'TransportStart','transport');wrap(B,'Watch','observer');wrap(B,'RequestRefresh','refresh')
 wrap(B,'Spend','spend');wrap(B,'Select','select')
 wrap(Nexus.OrbRuntime,'Pump','pump')
 wrap(Nexus.MainInternals and Nexus.MainInternals.StoreAuthorityOwner,'UpdateStateV1','durable')
 return counts,function() for i=#saved,1,-1 do local s=saved[i];s[1][s[2]]=s[3] end end
end
local function Count(fn)
 local counts,restore=Seams()
 local ok,value=pcall(fn)
 restore()
 if not ok then error(value,0) end
 return counts,value
end
local function WithoutRuntime(fn)
 local runtime=Nexus.OrbRuntime
 Nexus.OrbRuntime=nil
 local ok,value=pcall(fn)
 Nexus.OrbRuntime=runtime
 if not ok then error(value,0) end
 return value
end
-- fn's counts, with the same path's counts without the Orb owner as the
-- baseline (other status facts may read saved settings; only the Orb fact's
-- share is measured). The first pass only creates the checklist widgets.
local function Measure(fn)
 WithoutRuntime(fn)
 local base=WithoutRuntime(function() return (Count(fn)) end)
 local counts,value=Count(fn)
 return counts,value,base
end
local function NoWork(counts,base)
 for _,k in ipairs(ZERO) do if counts[k] then return false end end
 return (counts.storeState or 0)==((base and base.storeState) or 0)
end
-- What a passive read must leave exactly as it was (RunnerView is the owner's
-- passive session view: it initializes nothing).
local function Effects(h)
 local runtime=Nexus.OrbRuntime
 local view=runtime and type(runtime.RunnerView)=='function' and runtime.RunnerView() or {}
 return table.concat({#h.actions,#h.sent,h.orbs and h.orbs.requests or 0,tostring(view.initialized),
  tostring(view.state),tostring(view.pending),tostring(_G.NexusOrbRuntime),Serialize(NexusDB)},'|')
end

C.scenario('C1 one source of destination facts for the tooltip, the panel lines and the checklist',function()
 Boot(2)
 C.setup(A.SetLoadoutWishlist(2,107)==true,'C1: fixture: Saved Build 2 is assigned W-Free')
 local model=Refresh()
 C.setup(type(model)=='table','C1: fixture: the runtime published a panel model')
 local P,T=Nexus.Panel,Nexus.UserText
 C.expect(type(P.DestinationFacts)=='function' and type(P.SetupFacts)=='function','C1: the panel exposes its destination and setup facts')
 if type(P.DestinationFacts)~='function' or type(P.SetupFacts)~='function' then return end
 local facts=P.DestinationFacts(model)
 local lines=P.DestinationLines(model)
 C.expect(type(facts)=='table' and facts.kind=='savedBuild' and facts.slot==2 and facts.active==true and facts.wishlistState=='assigned',
  'C1: the facts are the active Saved Build 2 with an assigned Wishlist',Serialize(facts))
 C.expect(table.concat(T.DestinationLines(facts),'\n')==table.concat(lines,'\n'),'C1: the panel lines are the wording of those facts')
 local tip=HeaderTip()
 for _,line in ipairs(lines) do C.guard(Has(tip,line),'C1: the My Builds tooltip still shows: '..line,tip) end
 local setup=P.SetupFacts()
 C.expect(type(setup.destination)=='table' and Serialize(setup.destination)==Serialize(facts),
  'C1: the checklist reads the same destination facts',Serialize(setup.destination))
 C.guard(P.DestinationFacts(nil)==nil and #P.DestinationLines(nil)==0,'C1: without a model nothing is captured or claimed')
end)

C.scenario('C2 the Auto line follows the committed model, including its hold',function()
 Boot(2)
 C.setup(A.SetLoadoutWishlist(2,107)==true,'C2: fixture: Saved Build 2 is assigned W-Free')
 local model=Refresh()
 local P,T=Nexus.Panel,Nexus.UserText
 if type(P.SetupFacts)~='function' or type(T.StatusLines)~='function' then
  C.expect(false,'C2: setup facts and status lines exist');return
 end
 local f=P.SetupFacts()
 C.expect(f.auto==false and Has(T.StatusLines(f)[1],'Auto: OFF'),'C2: Auto OFF in the model reads OFF',tostring(f.auto))
 local held=H.Clone(model);held.auto=true;held.paused='Synthetic hold for the status test.'
 C.setup(P.Render(held)==true,'C2: fixture: the panel renders a selected Auto with a hold')
 f=P.SetupFacts()
 local line=T.StatusLines(f)[1]
 C.expect(f.auto==true and Has(line,'Auto: ON') and Has(line,'not acting now'),'C2: a selected Auto with a hold says it is not acting now',line)
 C.guard(Nexus.RecomputeStats().autoEnabled==false,'C2: reading the status turns nothing ON')
end)

C.scenario('C3 the Sync line states the saved mode, and an unreadable mode as not known',function()
 Boot(2)
 local P,T,policy=Nexus.Panel,Nexus.UserText,Nexus.SyncModePolicy
 if type(P.SetupFacts)~='function' or type(T.StatusLines)~='function' then
  C.expect(false,'C3: setup facts and status lines exist');return
 end
 Refresh()
 local realMode=policy.Mode
 local seen={}
 for _,mode in ipairs({'automatic','manual','off'}) do
  policy.Mode=function() return mode end
  local f=P.SetupFacts();seen[mode]=T.StatusLines(f)[2]
  policy.Mode=realMode
 end
 C.expect(Has(seen.automatic,'Sync: Automatic') and Has(seen.manual,'Sync: Manual') and Has(seen.off,'Sync: Off'),
  'C3: each saved mode is stated as itself',table.concat({seen.automatic,seen.manual,seen.off},' / '))
 policy.Mode=function() error('synthetic unreadable mode') end
 local okFacts,f=pcall(P.SetupFacts)
 policy.Mode=realMode
 C.expect(okFacts and f.syncMode==nil and Has(T.StatusLines(f)[2],'not known'),'C3: an unreadable mode is not known, not Automatic',okFacts and tostring(f.syncMode))
 C.guard(policy.Mode()==realMode(),'C3: the policy is restored and unchanged')
end)

C.scenario('C4 the Orb line: no run, a failed read and the model stay distinct; reading changes nothing',function()
 Boot(2)
 C.setup(A.SetLoadoutWishlist(2,107)==true,'C4: fixture: Saved Build 2 is assigned W-Free')
 local model=Refresh()
 local P,T,runtime=Nexus.Panel,Nexus.UserText,Nexus.OrbRuntime
 if type(P.SetupFacts)~='function' or type(T.StatusLines)~='function' then
  C.expect(false,'C4: setup facts and status lines exist');return
 end
 -- An intentional owner read before the measured reads: CompactStatus
 -- initializes the idle owner (the checklist itself never does).
 C.setup(runtime.CompactStatus()==nil,'C4: fixture: the Orb owner is initialized by its own read and holds no approved run')
 local before=Serialize(model);local sent,actions=#H.sent,#H.actions
 local f=P.SetupFacts()
 C.expect(f.orb==false and f.orbObserved==true and Has(T.StatusLines(f)[3],'no Orb run approved'),'C4: an observed owner with no approved run is stated as such',tostring(f.orb))
 local realView=runtime.ReasonView
 runtime.ReasonView=function() error('synthetic unreadable run') end
 local okFacts;okFacts,f=pcall(P.SetupFacts)
 runtime.ReasonView=realView
 C.expect(okFacts and f.orb==nil and Has(T.StatusLines(f)[3],'not known'),'C4: a failed Orb view read is not known, not "no run"',okFacts and tostring(f.orb))
 local realCompact=runtime.CompactStatus
 runtime.CompactStatus=function() error('the checklist must not need CompactStatus') end
 okFacts,f=pcall(P.SetupFacts)
 runtime.CompactStatus=realCompact
 C.expect(okFacts and f.orb==false,'C4: the Orb fact comes from the passive view, not from CompactStatus (which can initialize and read)',okFacts and tostring(f.orb))
 C.guard(Serialize(Nexus.Panel._lastModel)==before and #H.sent==sent and #H.actions==actions,
  'C4: reading the facts changed neither the model nor anything else')
end)

-- M5R-NB18 (fresh31 reconciliation): Sync.IsReceiving is the window in which
-- answers are accepted, not evidence that any arrive, so the Build Library
-- says "listening for answers"; only inbound transfers in flight are called
-- "receiving" (the Leaderboard's count). A vocabulary lint of the sources.
C.scenario('C5 listening is not called receiving; receiving is only reception in progress',function()
 local handle=assert(io.open('ui/CommunityRenderer.lua','rb'));local src=handle:read('*a');handle:close()
 local lb=assert(io.open('ui/Leaderboard.lua','rb'));local board=lb:read('*a');lb:close()
 C.expect(Has(src,'Listening for answers %ds (%d new)'),'C5: the receive window is stated as listening for answers, with the stored new count')
 C.guard(Has(src,'sync="Listening..."') and Has(src,'receiving and "Listening..."'),'C5: the measured label and the button keep "Listening..."')
 C.guard(not Has(src,'sync="Receiving..."') and not Has(src,'receiving and "Receiving..."') and not Has(src,'Receiving %ds'),
  'C5: no Library text claims reception from the receive window alone')
 C.guard(Has(board,'local receiving=tonumber(work.receiving) or 0') and Has(board,'receiving.." receiving"'),
  'C5: the Leaderboard says "receiving" only from its count of inbound transfers in flight')
end)

C.scenario('C6 a paused Orb run: the shared checklist shows its current reason; reading it starts no Orb work',function()
 local h,M=OrbBoot()
 C.setup(ShowsReason('Orbs (optional): run paused; a result is pending. Last reason Nexus recorded: '..PAUSED_REASON,PAUSED_REASON)
  and not ShowsReason(PREIMAGE_PAUSED,PAUSED_REASON),
  'C6: oracle self-check (not product evidence): it accepts the reason as recorded and rejects the e8e74693 omission line')
 h.OrbPlan(PLAN)
 C.setup(M.Start(3)==true and h.Count('orb-spend')==1,'C6: fixture: a real run of 3 starts and submits one spend')
 C.setup(M.Pause()==true,'C6: fixture: the run is explicitly paused with that spend pending')
 C.setup(Nexus.StartupStatus().coreReady==true,'C6: fixture: local start-up is ready')
 local hasView=type(M.ReasonView)=='function'
 C.expect(hasView,'C6: the Orb owner exposes a passive reason view')
 local view=hasView and M.ReasonView() or {}
 C.expect(view.observed==true and view.run==true and view.state=='PAUSED' and view.running==false and view.pending==true
  and view.restored==false and view.reason==PAUSED_REASON and view.operation=='Orb test',
  'C6: the view copies the paused state, the owner\'s recorded reason and the recorded operation name',Serialize(view))
 if hasView then
  local again=M.ReasonView();local plain=again~=view
  for _,v in pairs(again) do if type(v)=='table' or type(v)=='function' then plain=false end end
  again.reason='changed by the caller'
  C.expect(plain and M.ReasonView().reason==PAUSED_REASON,'C6: each read is a new table of plain scalars; changing it changes nothing in the owner')
 end
 local compact=M.CompactStatus()
 C.guard(type(compact)=='table' and compact.reason==PAUSED_REASON,'C6: the owner still exports the same reason (read before the measured interval)',compact and compact.reason)
 local before,frame=Effects(h),_G.NexusOrbRuntime
 local counts,line,base=Measure(ConsumerPath)
 print('OBSERVED','C6 paused line='..line..' counts='..Serialize(counts)..' base='..Serialize(base))
 C.expect(ShowsReason(line,PAUSED_REASON),'C6: the visible checklist Orb line shows the paused run\'s current reason, as recorded',line)
 C.guard(Has(line,PREIMAGE_PAUSED),'C6: it keeps the paused and pending state words first',line)
 C.expect(Has(line,"Original operation (as recorded): 'Orb test'") and not Has(line,'Resume would'),
  'C6: the recorded operation is named as recorded, never as a Resume target',line)
 C.expect(Has(line,'Open Orbs'),'C6: it points to Open Orbs for the current review and the actions available there',line)
 C.guard(not Promises(line,PAUSED_REASON),'C6: outside the owner\'s reason it offers no Resume, Continue, reload or refund',line)
 local f=_G.NexusSetupChecklist
 local s1=f and V.Plain(f.status[1]:GetText() or '') or ''
 local s2=f and V.Plain(f.status[2]:GetText() or '') or ''
 C.guard(Has(s1,'Auto:') and Has(s2,'Sync:') and Has(line,'Orbs (optional):'),'C6: the three status lines keep their order',s1..' / '..s2)
 C.expect(NoWork(counts,base),'C6: repeated SetupFacts and checklist show/refresh read no saved, assignment, context or adapter state and start no capture, transport, observer, pump, request, write, spend or choice',
  Serialize(counts)..' base='..Serialize(base))
 C.guard(Effects(h)==before and _G.NexusOrbRuntime==frame,'C6: actions, sends, Orb requests, the owner\'s state and saved data are exactly unchanged')
 if hasView then
  local real=M.ReasonView
  M.ReasonView=function() local v=real();v.reason=nil;return v end
  local okMutated,mutated=pcall(function() Nexus.QuickStart.RefreshChecklist();return OrbLineShown() end)
  M.ReasonView=real
  C.setup(okMutated and not ShowsReason(mutated,PAUSED_REASON) and Has(mutated,PREIMAGE_PAUSED) and not Has(mutated,'Last reason'),
   'C6: discriminator: with the reason omitted at the public producer boundary, the visible oracle rejects the line',mutated)
  Nexus.QuickStart.RefreshChecklist()
 end
 C.setup(M.Stop()==true,'C6: fixture: the real Stop ends the run with its result still pending')
 view=hasView and M.ReasonView() or {}
 C.expect(view.state=='STOPPED' and view.pending==true and view.running==false and view.reason==STOPPED_REASON,
  'C6: after Stop the view carries the stopped state and its recorded reason',Serialize(view))
 before,frame=Effects(h),_G.NexusOrbRuntime
 counts,line,base=Measure(ConsumerPath)
 print('OBSERVED','C6 stopped line='..line..' counts='..Serialize(counts))
 C.expect(ShowsReason(line,STOPPED_REASON) and Has(line,'Orbs (optional): run stopped; a result is pending.'),
  'C6: the visible line says stopped with the result pending and shows the Stop reason as recorded',line)
 C.guard(not Promises(line,STOPPED_REASON),'C6: after Stop it still offers no Resume, Continue, reload or refund',line)
 C.guard(NoWork(counts,base) and Effects(h)==before and _G.NexusOrbRuntime==frame,'C6: reading the stopped run starts no work and changes nothing',Serialize(counts))
end)

C.scenario('C7 an Orb owner not read this session is not known (a saved receipt is not ruled out); after its own recovery read the recorded reason shows',function()
 local h,M=OrbBoot()
 h.OrbPlan(PLAN)
 C.setup(M.Start(3)==true and M.Pause()==true,'C7: fixture: a real run submits one spend and is paused')
 C.setup(type(S.Receipt())=='table','C7: fixture: its unresolved receipt is saved')
 -- Explicit harness cleanup and a fresh load of the real owner (S.Reload: the
 -- old runtime frame is silenced, then OrbAdapter and OrbRuntime load again).
 local M2=S.Reload(h)
 C.setup(M2~=M and Nexus.OrbRuntime==M2 and M2.RunnerView().initialized==false,'C7: fixture: the fresh owner is loaded and not initialized')
 C.setup(type(S.Receipt())=='table' and Nexus.StartupStatus().coreReady==true,'C7: fixture: the saved receipt is still there and local start-up is ready')
 local hasView=type(M2.ReasonView)=='function'
 local viewCounts,view={},{}
 if hasView then viewCounts,view=Count(M2.ReasonView) end
 C.expect(type(view)=='table' and view.observed==false and view.run==nil and view.state==nil and view.reason==nil,
  'C7: the view says not observed and claims neither a run nor its absence',Serialize(view))
 C.expect(hasView and NoWork(viewCounts,nil) and not viewCounts.storeState and M2.RunnerView().initialized==false,
  'C7: the view itself reads no saved state and initializes nothing',Serialize(viewCounts))
 local before,frame=Effects(h),_G.NexusOrbRuntime
 local counts,line,base=Measure(ConsumerPath)
 print('OBSERVED','C7 not-read line='..line..' counts='..Serialize(counts)..' base='..Serialize(base))
 C.expect(Has(line,'not known') and Has(line,'not ruled out') and not Has(line,'no Orb run approved'),
  'C7: the visible line says not known and does not say that no run or receipt exists',line)
 C.expect(M2.RunnerView().initialized==false and _G.NexusOrbRuntime==frame,
  'C7: showing and refreshing the checklist initialized no owner and created no recovery pump frame')
 C.expect(NoWork(counts,base) and Effects(h)==before,
  'C7: it read no saved, assignment, context or adapter state, started no capture, transport, observer, pump, request or write, and changed nothing',
  Serialize(counts)..' base='..Serialize(base))
 local recovery=M2.RecoveryView()
 C.setup(type(recovery)=='table' and recovery.pending==true and recovery.restored==true and M2.RunnerView().initialized==true,
  'C7: fixture: the owner\'s own recovery read (an intentional initialization, outside the measured reads) restores the receipt')
 view=hasView and M2.ReasonView() or {}
 C.expect(view.observed==true and view.run==true and view.state=='RECOVERY' and view.restored==true and view.pending==true
  and view.running==false and view.reason==RECOVERY_REASON and view.operation==nil,
  'C7: the view carries the recorded recovery reason and no operation name (none is recorded for a restored receipt)',Serialize(view))
 before,frame=Effects(h),_G.NexusOrbRuntime
 counts,line,base=Measure(ConsumerPath)
 print('OBSERVED','C7 recovery line='..line..' counts='..Serialize(counts))
 C.expect(Has(line,'Orbs (optional): an earlier Orb action is unresolved.') and ShowsReason(line,RECOVERY_REASON),
  'C7: the visible line says an earlier action is unresolved and shows the recovery reason as recorded',line)
 C.expect(not Has(line,'Original operation') and not Promises(line,RECOVERY_REASON) and Has(line,'Open Orbs'),
  'C7: it names no operation or Resume target, offers no Resume, Continue, reload or refund, and points to Open Orbs',line)
 C.expect(NoWork(counts,base) and Effects(h)==before and _G.NexusOrbRuntime==frame,
  'C7: repeated reads during recovery start no read, pump, observer, request or write and change nothing',Serialize(counts))
end)

C.scenario('C8 a missing, throwing, malformed or reasonless Orb view stays unknown or omitted; nothing is stringified or guessed',function()
 Boot(2)
 Refresh()
 local P,T,runtime=Nexus.Panel,Nexus.UserText,Nexus.OrbRuntime
 if type(P.SetupFacts)~='function' or type(T.StatusLines)~='function' then
  C.expect(false,'C8: setup facts and status lines exist');return
 end
 local real=runtime.ReasonView
 local function Read(view)
  runtime.ReasonView=view
  local ok,f=pcall(P.SetupFacts)
  runtime.ReasonView=real
  if not ok or type(f)~='table' then return {},'' end
  return f,V.Plain(T.StatusLines(f)[3] or '')
 end
 for _,case in ipairs({
  {'missing',nil},
  {'throwing',function() error('synthetic unreadable view') end},
  {'non-table',function() return 'PAUSED' end},
  {'observed-not-boolean',function() return {observed='yes',run=true,state='PAUSED',reason='Synthetic.'} end},
  {'run-not-boolean',function() return {observed=true,run='yes',state='PAUSED',reason='Synthetic.'} end},
 }) do
  local f,line=Read(case[2])
  C.expect(f.orb==nil and Has(line,'not known') and not Has(line,'no Orb run') and not Has(line,'paused') and not Has(line,'Synthetic'),
   'C8: a '..case[1]..' view reads not known',line)
 end
 local f,line=Read(function() return {observed=true,run=true,state={},running='yes',pending=1,restored={},reason={},operation={}} end)
 local orb=type(f.orb)=='table' and f.orb or {}
 C.expect(type(f.orb)=='table' and orb.state==nil and orb.running==nil and orb.pending==nil and orb.restored==nil
  and orb.reason==nil and orb.operation==nil,'C8: malformed fields are left out, not copied or converted',Serialize(f.orb))
 C.expect(Has(line,'run state not known') and not Has(line,'table:') and not Has(line,'pending')
  and not Has(line,'Last reason') and not Has(line,'Original operation'),'C8: and the line guesses no state, result or reason',line)
 f,line=Read(function() return {observed=true,run=true,state='Paused now',running=false,pending=false,reason='Synthetic reason.'} end)
 C.expect(type(f.orb)=='table' and f.orb.state==nil and Has(line,'run state not known') and ShowsReason(line,'Synthetic reason.'),
  'C8: a state that is not a code is not shown; a valid reason still is',line)
 f,line=Read(function() return {observed=true,run=true,state='PAUSED',running=false,pending=true,restored=false} end)
 C.expect(Has(line,PREIMAGE_PAUSED) and not Has(line,'Last reason') and Has(line,'Open Orbs'),
  'C8: a run with no recorded reason states its state, invents no reason and points to Open Orbs',line)
 f,line=Read(function() return {observed=true,run=true,state='PAUSED',running=false,pending=false,reason=string.rep('x',5000)} end)
 C.expect(type(f.orb)=='table' and f.orb.reason==nil and not Has(line,'Last reason') and #line<400,
  'C8: an over-long reason is left out',#line)
 local long=string.rep('\195\169t\195\169 ',200)
 f,line=Read(function() return {observed=true,run=true,state='STOPPED',running=false,pending=false,reason=long} end)
 C.expect(Has(line,'Last reason Nexus recorded:') and Utf8Valid(line) and #line<#long,
  'C8: a long reason is shown bounded and cut on a UTF-8 character boundary',#line)
 runtime.ReasonView=function() return {observed=true,run=true,state={},reason={},operation={}} end
 local okShow,shown=pcall(function() Nexus.QuickStart.ShowChecklist();Nexus.QuickStart.RefreshChecklist();return OrbLineShown() end)
 runtime.ReasonView=real
 C.expect(okShow and Has(shown,'run state not known') and not Has(shown,'table:'),'C8: the visible checklist line shows no stringified table',shown)
 Nexus.QuickStart.HideChecklist()
 C.guard(runtime.ReasonView==real,'C8: the producer boundary is restored')
end)

C.finish('(one fact source for destination and status; unknown stays unknown; reading changes nothing)')
