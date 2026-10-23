-- M7 (M6 NB-1, NB-7, R1, R2): Review target and Cancel review act only on the
-- target the button was drawn for. A click after the target changed under it
-- reviews and cancels nothing, keeps Resume withheld and says to check the
-- target shown now. A target that changed and came back to the run's own
-- Wishlist still needs the review but is called back, not new. The mini panel
-- refuses Resume for a Wishlist that is not ready with that reason. A paused
-- run that no longer owns its action (released at a loading screen) names no
-- target in the full and the compact read and says Stop, then a new approval.
-- Display only: every runtime gate, Resume itself and the spend path are the
-- existing ones.
-- Categories (view_regression_support): EXPECT is behaviour added in M7
-- (predicted to fail on accepted M6 0924d06a; not executed by the author);
-- GUARD already holds there and must keep holding; SETUP is the fixture.
-- Oracles: the real OrbRuntime reads (Status, CompactStatus, Resume), the real
-- Orb window, strip and mini panel handlers and fontstrings, and the spend,
-- take, send and action counters and the saved Orb row. The returned target
-- (R2) is the run's own assignment read, replayed through the adapter's
-- assignment read as a SYNTHETIC genuine-shaped control (a copy of the read
-- the run started with). Real addon boot; synthetic game services only. No
-- native, double-click or spending claim.
local V=dofile('tests/prototype/view_regression_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local C=V.Checker('orb_review_identity')
local H,M,A,O,UI
local PLAN={{spellId=410002,quality=2,stacks=3}}

local function Fresh()
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 Nexus=nil;NexusDB=nil;NexusSupportDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil;NexusPanel=nil
 H=dofile('tests/prototype/orbs_support.lua');M,A,O=H.M,H.A,H.O;UI=Nexus.OrbPanel
 UIParent:SetSize(1920,1080)
end
local function Effects()
 local s=M.Status()
 return {spend=H.Count('orb-spend'),take=H.Count('take'),actions=#H.actions,sent=#H.sent,
  orb=F.Serialize(Nexus.Store.State().orbRefinement),state=s.state,spent=s.spent,reserved=s.reserved,
  limit=s.limit,running=s.running,pending=s.pending,operation=tostring(s.operationName)}
end
local function Same(a,b) for k,v in pairs(a) do if b[k]~=v then return false end end;return true end
local function Direct(b) return b:GetScript('OnClick')(b) end
local function Strip()
 Nexus.Panel.Show();H.Advance(.3)
 local bar=NexusPanel and NexusPanel._orbControls
 if bar then bar.refresh() end
 return bar
end
local function SettledPausedRun()
 H.OrbPlan(PLAN)
 local f=UI.Show();f.limit:SetText('3');f.start:Click()
 C.setup(H.Count('orb-spend')==1 and M.Status().limit==3,'fixture: the full window approved a run of 3')
 f.pause:Click()
 H.Offer();H.service.SelectPerk(410002);H.Result(410002,2)
 local s=M.Status()
 C.setup(s.state=='PAUSED' and not s.pending and s.spent==1,'fixture: the original operation settled while paused',s.state)
 UI.Refresh()
 return f
end
local function Has(text,needle) return tostring(text or ''):find(needle,1,true)~=nil end

C.scenario('I1 a Review target click after the target changed under the button reviews nothing',function()
 Fresh()
 local f=SettledPausedRun()
 C.setup(A.SetFirstLoadoutWishlistIdentity('Target A',{{spellId=410004,quality=3,stacks=2}}),'I1: fixture: a different valid plan A is assigned')
 UI.Refresh()
 local ta=M.Status().resumeTarget
 C.setup(ta and ta.kind=='changed' and ta.name=='Target A' and f.review:IsShown() and f.review:GetText()=='Review target',
  'I1: fixture: the window shows Review target for A',ta and ta.kind)
 -- The assignment changes again before the window redraws.
 C.setup(A.SetFirstLoadoutWishlistIdentity('Target B',{{spellId=410002,quality=2,stacks=2}}),'I1: fixture: plan B is assigned with no redraw')
 local tb=M.Status().resumeTarget
 C.setup(tb and tb.kind=='changed' and tb.name=='Target B' and tb.key~=ta.key,'I1: fixture: the fresh target is B, another key')
 local before=Effects()
 Direct(f.review)
 local notice=f.notice:GetText() or ''
 print('OBSERVED','I1 stale review notice='..notice)
 C.expect(Has(notice,'The target changed after it was shown; nothing was reviewed'),'I1: the click says the target changed and nothing was reviewed',notice)
 UI.Refresh()
 C.expect(not f.resume:IsEnabled() and f.review:GetText()=='Review target','I1: B is not reviewed: Resume stays withheld',f.review:GetText())
 C.guard(Same(before,Effects()),'I1: the stale click adopted, selected, wrote and spent nothing')
 -- Drawn for B now: the review records B. (EXPECT: on M6 the stale click
 -- already reviewed B, so this click cancels it there.)
 Direct(f.review)
 C.expect(f.resume:IsEnabled() and f.review:GetText()=='Cancel review','I1: a click on the redrawn button reviews B')
 C.guard(Same(before,Effects()),'I1: and spends nothing')
end)

C.scenario('I2 a Cancel review click after the target changed under the button reviews nothing',function()
 Fresh()
 local f=SettledPausedRun()
 C.setup(A.SetFirstLoadoutWishlistIdentity('Target A',{{spellId=410004,quality=3,stacks=2}}),'I2: fixture: plan A is assigned')
 UI.Refresh();Direct(f.review)
 C.setup(f.resume:IsEnabled() and f.review:GetText()=='Cancel review','I2: fixture: A is reviewed and the button reads Cancel review')
 C.setup(A.SetFirstLoadoutWishlistIdentity('Target B',{{spellId=410002,quality=2,stacks=2}}),'I2: fixture: plan B is assigned with no redraw')
 local before=Effects()
 Direct(f.review)
 local notice=f.notice:GetText() or ''
 print('OBSERVED','I2 stale cancel notice='..notice)
 C.expect(Has(notice,'nothing was reviewed'),'I2: a Cancel review click drawn for A does not review B',notice)
 UI.Refresh()
 C.expect(not f.resume:IsEnabled() and f.review:GetText()=='Review target','I2: B is withheld until it is reviewed',f.review:GetText())
 C.guard(Same(before,Effects()),'I2: nothing was adopted, written or spent')
end)

C.scenario('I3 a target that changed and came back is called back, and still needs the review',function()
 Fresh()
 H.OrbPlan(PLAN)
 local original=H.Clone(A.AssignedWishlist())
 C.setup(type(original)=='table' and original.state=='ready' and original.name=='Orb test','I3: fixture: the run\'s own assignment read',original and original.state)
 C.setup(M.Start(3),'I3: the run starts')
 H.Offer()
 C.setup(H.Count('take')==1,'I3: the running run selected from the offer')
 C.setup(A.SetFirstLoadoutWishlistIdentity('Changed target',{{spellId=410004,quality=3,stacks=2}}),'I3: the target changes while the result is pending')
 M.Pump()
 C.setup(M.Status().state=='PAUSED' and M.Status().targetChanged,'I3: the runtime paused the original operation')
 H.Result(410002,2)
 C.setup(not M.Status().pending and M.Status().resumeTarget and M.Status().resumeTarget.kind=='changed','I3: settled; a changed target waits for review')
 -- SYNTHETIC control: the adapter's assignment read answers with a copy of
 -- the run's own read, as when the player assigns that same Wishlist again.
 local realRead=A.AssignedWishlist
 A.AssignedWishlist=function() return H.Clone(original) end
 local ok,err=pcall(function()
  local s=M.Status();local t=s.resumeTarget
  C.setup(t and t.kind=='changed' and t.name=='Orb test','I3: fixture: Resume would use the run\'s own Wishlist again',t and t.kind)
  C.expect(t and t.returned==true,'I3: the full read says the target came back',t and tostring(t.returned))
  local f=UI.Show();UI.Refresh()
  local text=f.status:GetText() or ''
  print('OBSERVED','I3 window='..text)
  C.expect(Has(text,"Target changed and is back: Resume would use 'Orb test' again. Review target first."),'I3: the window calls it back, not new',text)
  C.expect(not Has(text,'New target:'),'I3: it is not called a new target',text)
  C.guard(not f.resume:IsEnabled() and f.review:IsShown(),'I3: Resume still waits for Review target')
  local bar=Strip()
  local summary=bar and bar.summary:GetText() or ''
  C.expect(Has(summary,"Target back to 'Orb test'"),'I3: the strip calls it back',summary)
  local mini=UI.ShowMini()
  C.expect(mini.state:GetText()=='Paused - review the target in Open Orbs','I3: the mini panel says where to review it',mini.state:GetText())
  Direct(mini.resume)
  C.expect(mini.notice:GetText()=='Not resumed: review the target in Open Orbs','I3: a mini Resume is refused with where to review',mini.notice:GetText())
  local before=Effects()
  Direct(f.resume)
  C.expect(Has(f.notice:GetText(),'Review the target first: it changed and is back to'),'I3: a window Resume before the review says why',f.notice:GetText())
  C.guard(Same(before,Effects()),'I3: no route resumed, selected, wrote or spent before the review')
  mini:Hide()
 end)
 A.AssignedWishlist=realRead
 C.setup(ok,'I3: fixture: the returned-target checks ran',err)
end)

C.scenario('I4 the mini panel refuses Resume for a Wishlist that is not ready, with that reason',function()
 Fresh()
 SettledPausedRun()
 local slots=H.service.GetServerBuildSlots
 H.service.GetServerBuildSlots=function() return nil end
 local s=M.Status()
 C.setup(s.resumeTarget and s.resumeTarget.kind=='unavailable' and not s.canResume,'I4: fixture: the assignment is not ready; Resume is not offered')
 local mini=UI.ShowMini()
 C.guard(mini.state:GetText()=='Paused - the assigned Wishlist is not ready' and not mini.resume:IsEnabled(),'I4: the mini panel names the reason and offers no Resume')
 local before=Effects()
 Direct(mini.resume)
 local notice=mini.notice:GetText() or ''
 C.expect(notice=='Not resumed: the Wishlist is not ready.','I4: a mini Resume that reaches the handler says the Wishlist is not ready',notice)
 C.expect(not Has(notice,'pending result must settle'),'I4: it does not blame a pending result that does not exist',notice)
 C.guard(Same(before,Effects()),'I4: nothing was resumed or spent')
 H.service.GetServerBuildSlots=slots
 mini:Hide()
end)

C.scenario('I5 a paused run released at a loading screen names no target and says how to go on',function()
 Fresh()
 local f=SettledPausedRun()
 Direct(f.resume)
 C.setup(M.Status().running and M.Status().pending and H.Count('orb-spend')==2,'I5: fixture: the run resumed and requested its next Orb')
 -- The take counter is cumulative: SettledPausedRun's own player pick
 -- (H.service.SelectPerk, line 52) is already one 'take', recorded by the
 -- same harness service the runtime selects through (harness S.SelectPerk;
 -- OrbAdapter O.Select). The witness is therefore the runtime's one new
 -- selection on this offer: exactly one more 'take', for 410002, and the
 -- runtime's own saved receipt marking that selection. Nothing between the
 -- snapshot and the check calls SelectPerk; the offer's own M.Pump is the
 -- transition witnessed.
 local takesBefore,actionsBefore=H.Count('take'),#H.actions
 H.Offer()
 local newTakes={}
 for i=actionsBefore+1,#H.actions do
  local a=H.actions[i]
  if type(a)=='table' and a[1]=='take' then newTakes[#newTakes+1]=a[2] end
 end
 local receipt=Nexus.Store.State().orbRefinement.pending
 C.setup(H.Count('take')==takesBefore+1 and #newTakes==1 and newTakes[1]==410002
  and type(receipt)=='table' and receipt.selectionAttempted==true and receipt.selectedKey=='410002:2',
  'I5: fixture: the running run selected from the offer',
  'takes '..takesBefore..'->'..H.Count('take')..' new='..table.concat(newTakes,',')
   ..' selectionAttempted='..tostring(type(receipt)=='table' and receipt.selectionAttempted)
   ..' selectedKey='..tostring(type(receipt)=='table' and receipt.selectedKey))
 H.Result(410002,2)
 local s=M.Status()
 C.setup(s.running and not s.pending,'I5: fixture: the result settled; the run is running with no unresolved operation',
  tostring(s.state)..' running='..tostring(s.running)..' pending='..tostring(s.pending))
 if not (s.running and not s.pending) then return end
 H.Fire('PLAYER_LEAVING_WORLD');H.Fire('PLAYER_ENTERING_WORLD')
 s=M.Status();local c=M.CompactStatus()
 C.setup(s.state=='PAUSED' and not s.pending and not s.canResume,'I5: fixture: the loading screen paused the run and released its action',s.state)
 C.expect(s.resumeTarget and s.resumeTarget.kind=='blocked' and s.resumeTarget.reason=='authorization' and s.resumeTarget.name==nil,
  'I5: the full read names no target and says why',s.resumeTarget and tostring(s.resumeTarget.kind)..'/'..tostring(s.resumeTarget.reason))
 C.expect(c and c.resumeTarget and c.resumeTarget.kind=='blocked' and c.resumeTarget.reason=='authorization',
  'I5: the compact read says the same',c and c.resumeTarget and tostring(c.resumeTarget.kind))
 f=UI.Show();UI.Refresh()
 local text=f.status:GetText() or ''
 print('OBSERVED','I5 window='..text)
 C.expect(Has(text,'this run no longer owns the action') and Has(text,'Stop, then approve a new run'),'I5: the window says the run can no longer resume and what to do',text)
 C.expect(not Has(text,'Resume would use') and not Has(text,'Resume target unknown'),'I5: it guesses no target and blames no Wishlist',text)
 local mini=UI.ShowMini()
 C.expect(mini.state:GetText()=='Paused - this run can no longer resume','I5: the mini panel says the same',mini.state:GetText())
 Direct(mini.resume)
 C.expect(mini.notice:GetText()=='Not resumed: this run can no longer resume.','I5: a mini Resume is refused with that reason',mini.notice:GetText())
 local before=Effects()
 C.guard(not M.Resume(),'I5: the runtime refuses Resume (unchanged)')
 Direct(f.resume)
 C.expect(Has(f.notice:GetText(),'this run no longer owns the action'),'I5: a window Resume is refused with that reason',f.notice:GetText())
 C.guard(Same(before,Effects()) and f.stop:IsEnabled(),'I5: nothing was spent; Stop stays available')
 mini:Hide()
end)

-- M6 NB-12 (fresh31): a paused run whose selection was already attempted
-- reads the same Resume target in the full and the compact read. The
-- runtime marks a changed assignment (targetChanged) only in its own step
-- (OrbRuntime 2055-2057), so between an assignment change and that step a
-- full read used to compare the fresh assignment ("settle") while the compact
-- read could not ("blocked"). Fixture: real calls only (Start, the synthetic
-- service's offer, the runtime's own selection, Pause, the real assignment
-- writer); the unmarked state is witnessed as SETUP, never forged.
C.scenario('I6 an attempted selection and an unmarked assignment change: full and compact agree',function()
 Fresh()
 H.OrbPlan(PLAN)
 C.setup(M.Start(3),'I6: fixture: the run starts')
 H.Offer()
 C.setup(H.Count('take')==1,'I6: fixture: the running run selected from the offer')
 local receipt=Nexus.Store.State().orbRefinement.pending
 C.setup(receipt and receipt.selectionAttempted==true,'I6: fixture: the saved receipt records the attempted selection')
 C.setup(M.Pause(),'I6: fixture: the run is paused with its result pending')
 C.setup(A.SetFirstLoadoutWishlistIdentity('Unmarked change',{{spellId=410004,quality=3,stacks=2}}),
  'I6: fixture: a different valid plan is assigned with no runtime step')
 local s,c=M.Status(),M.CompactStatus()
 C.setup(s.state=='PAUSED' and s.pending and s.targetChanged~=true,'I6: fixture: paused, pending, and the change not yet marked',
  tostring(s.state)..' targetChanged='..tostring(s.targetChanged))
 if s.targetChanged==true then return end
 local before=Effects()
 local full,compact=s.resumeTarget,c and c.resumeTarget
 print('OBSERVED','I6 unmarked full='..tostring(full and full.kind)..' compact='..tostring(compact and compact.kind))
 C.expect(full~=nil and compact~=nil and full.kind==compact.kind,'I6: the full and the compact read name the same Resume target',
  tostring(full and full.kind)..'/'..tostring(compact and compact.kind))
 C.expect(full and full.kind=='blocked' and full.name==nil,'I6: the attempted selection must resolve first: no target is named or guessed',full and full.kind)
 C.guard(not s.canResume and not (c and c.canResume),'I6: Resume is not offered (unchanged gate)')
 C.guard(not M.Resume() and Same(before,Effects()),'I6: the runtime refuses Resume; nothing is selected, written or spent')
 -- The runtime's own step then marks the change: both reads say the
 -- original must settle (this holds before and after M7).
 M.Pump()
 s,c=M.Status(),M.CompactStatus()
 C.setup(s.targetChanged==true,'I6: fixture: the runtime step marked the changed assignment',tostring(s.targetChanged))
 if s.targetChanged~=true then return end
 C.guard(s.resumeTarget and s.resumeTarget.kind=='settle' and c and c.resumeTarget and c.resumeTarget.kind=='settle',
  'I6: once marked, the full and the compact read both say the original must settle',
  tostring(s.resumeTarget and s.resumeTarget.kind)..'/'..tostring(c and c.resumeTarget and c.resumeTarget.kind))
 C.guard(H.Count('orb-spend')==1,'I6: only the original Orb was spent')
end)

C.finish('real OrbRuntime and Orb window/strip/mini handlers; synthetic services; no native or spending claim')
