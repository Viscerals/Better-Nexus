-- M6 (UX-07 / LP-07): a paused Orb run names what an explicit Resume would act
-- on, on every Orb surface. That is the ready assignment a settled run would
-- adopt, or the original operation a pending run would continue, kept apart
-- from the original operation's own name. An assignment that is not ready is
-- never named. After a changed target, Resume is offered only in the full
-- window and only after a deliberate review of that exact assignment. Review
-- and Cancel review spend nothing. The review is cleared by another assignment
-- or by closing the window, and it never weakens a runtime gate.
-- Categories (view_regression_support): EXPECT is behaviour added in M6 (it
-- fails on frozen M5 299d10b5 by design); GUARD already holds there and must
-- keep holding; SETUP is the fixture.
-- Rebased onto accepted M5 9deaa526: its Orb runtime, panels, history, Help
-- Orbs page and these test helpers are byte-identical to 299d10b5, so the same
-- categories are predicted there (not executed by the author).
-- Oracles:
--  * the real OrbRuntime reads (Status, CompactStatus, Resume);
--  * the real Orb window, main-panel strip and mini panel handlers and fontstrings;
--  * spend, take, send and action counters and the saved Orb row.
-- Real addon boot; synthetic game services only. No native, double-click or
-- spending claim.
local V=dofile('tests/prototype/view_regression_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local C=V.Checker('orb_target_review')
local H,M,A,O,UI
local PLAN={{spellId=410002,quality=2,stacks=3}}

local function Fresh()
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 Nexus=nil;NexusDB=nil;NexusSupportDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil;NexusPanel=nil
 H=dofile('tests/prototype/orbs_support.lua');M,A,O=H.M,H.A,H.O;UI=Nexus.OrbPanel
 UIParent:SetSize(1920,1080)
end
-- Everything a review or a refused Resume must leave exactly as it was.
local function Effects()
 local s=M.Status()
 return {spend=H.Count('orb-spend'),take=H.Count('take'),actions=#H.actions,sent=#H.sent,
  orb=F.Serialize(Nexus.Store.State().orbRefinement),state=s.state,spent=s.spent,reserved=s.reserved,
  limit=s.limit,running=s.running,pending=s.pending,operation=tostring(s.operationName)}
end
local function Same(a,b)
 for k,v in pairs(a) do if b[k]~=v then return false end end
 return true
end
local function Direct(b) return b:GetScript('OnClick')(b) end
local function Strip()
 Nexus.Panel.Show();H.Advance(.3)
 local bar=NexusPanel and NexusPanel._orbControls
 if bar then bar.refresh() end
 return bar
end
-- A run started from the full window, paused there, and its first operation
-- settled while paused (the synthetic player resolves the offer).
local function SettledPausedRun()
 H.OrbPlan(PLAN)
 local f=UI.Show();f.limit:SetText('3');f.start:Click()
 C.setup(H.Count('orb-spend')==1 and M.Status().limit==3,'fixture: the full window approved a run of 3')
 f.pause:Click()
 C.setup(M.Status().state=='PAUSED' and M.Status().pending,'fixture: the fixed Pause paused the pending run')
 H.Offer();H.service.SelectPerk(410002);H.Result(410002,2)
 local s=M.Status()
 C.setup(s.state=='PAUSED' and not s.pending and s.spent==1,'fixture: the original operation settled while paused',s.state)
 UI.Refresh()
 return f
end

C.scenario('A changed ready target after settlement: named everywhere, reviewed in the full window',function()
 Fresh()
 local f=SettledPausedRun()
 local s=M.Status();local t=s.resumeTarget
 C.expect(type(t)=='table' and t.kind=='same' and t.name=='Orb test' and t.original=='Orb test',
  'A: an unchanged target is named as the Resume target',t and t.kind)
 C.expect(f.status:GetText():find("Resume would use 'Orb test'",1,true)~=nil,'A: the full window names it',f.status:GetText())
 C.expect(s.canResume and f.resume:IsEnabled() and not f.review:IsShown(),'A: an unchanged target resumes without a review')

 C.setup(A.SetFirstLoadoutWishlistIdentity('New legitimate target',{{spellId=410004,quality=3,stacks=2}}),
  'A: the real writer assigns a different valid plan')
 UI.Refresh()
 s=M.Status();t=s.resumeTarget;local c=M.CompactStatus()
 C.guard(s.canResume and c.canResume,'A: the runtime still offers this legitimate Resume (contract unchanged)')
 C.expect(t and t.kind=='changed' and t.name=='New legitimate target' and t.original=='Orb test' and t.key~=nil,
  'A: the full read names the assignment Resume would adopt, apart from the original',t and t.kind)
 C.expect(c.resumeTarget and c.resumeTarget.kind=='changed' and c.resumeTarget.name=='New legitimate target'
  and c.resumeTarget.key==t.key,'A: the compact read names the same assignment with the same key')
 local text=f.status:GetText()
 C.expect(text:find("New target: Resume would use 'New legitimate target' instead of 'Orb test'",1,true)~=nil,
  'A: the full window names the new and the original target',text)
 C.guard(f.plan:GetText():find('New legitimate target',1,true)~=nil,'A: the plan line still names the current assignment')
 C.expect(not f.resume:IsEnabled() and f.review:IsShown() and f.review:IsEnabled() and f.review:GetText()=='Review target',
  'A: Resume waits for Review target')

 local bar=Strip()
 C.setup(bar~=nil,'A: the main-panel strip exists')
 local summary=bar.summary:GetText()
 C.expect(summary:find("New target: 'New legitimate target'",1,true)~=nil and summary:find('review it in the Orb window',1,true)~=nil,
  'A: the strip names the new target and where to review it',summary)
 C.expect(not bar.resume:IsEnabled() and not bar.primary:IsEnabled(),'A: the strip offers no Resume for a changed target')
 local mini=UI.ShowMini()
 C.expect(mini.state:GetText()=='Paused - review the new target in Open Orbs','A: the mini panel says where to review',mini.state:GetText())
 C.expect(mini.reason:GetText():find("New target: 'New legitimate target'",1,true)~=nil,'A: the mini panel names the new target',mini.reason:GetText())
 C.expect(not mini.resume:IsEnabled() and mini.stop:IsEnabled(),'A: the mini panel withholds Resume and keeps Stop')

 -- Every Resume route before the review: refused with the reason, no effect.
 local before=Effects()
 Direct(f.resume)
 C.expect(f.notice:GetText():find('Review the new target first',1,true)~=nil,'A: a Resume click that reaches the handler is refused with the reason',f.notice:GetText())
 Direct(f.start);Direct(bar.resume);Direct(bar.primary);Direct(mini.resume)
 -- A mini line is one line of at most MINI_CHARS (47) characters under the 7 px
 -- model, cut with "..." and complete on hover (orb_mini_panel). The refusal
 -- must fit whole, so the line itself says why and names the real button to
 -- use; a cut or a different destination does not count.
 local function whyAndWhere(text)
  return text:find('review the new target in '..mini.open:GetText(),1,true)~=nil and not text:find('...',1,true)
 end
 C.setup(not whyAndWhere('Not resumed: review the new target in Open O...') and not whyAndWhere('Not resumed: review the new target in the Orb window'),
  'A: oracle: a cut destination and a different destination are both rejected')
 local notice=mini.notice:GetText()
 C.expect(whyAndWhere(notice) and mini.notice._nexusFullText==nil,'A: the mini panel says why and where to review, unshortened',notice)
 local visible=notice:gsub('||','|');local _,chars=visible:gsub('[^\128-\191]','')
 C.guard(chars*7<=mini.notice:GetWidth(),'A: the notice stays within the one-line model',chars)
 GameTooltip:SetText('sentinel');mini.noticeHit:GetScript('OnEnter')(mini.noticeHit)
 local tip=GameTooltip:GetText()
 C.guard(tip==(mini.notice._nexusFullText or notice),'A: hovering the notice gives its complete text',tip)
 mini.noticeHit:GetScript('OnLeave')(mini.noticeHit)
 C.expect(Same(before,Effects()),'A: no Resume route adopted, selected, wrote or spent before the review')

 -- Review, Cancel review: memory only.
 f.review:Click()
 C.expect(f.resume:IsEnabled() and f.review:GetText()=='Cancel review','A: after Review target, Resume is offered and the review can be cancelled')
 C.expect(f.status:GetText():find("Reviewed: Resume would use 'New legitimate target'",1,true)~=nil,'A: the window says what was reviewed',f.status:GetText())
 C.expect(f.notice:GetText():find('Nothing was spent',1,true)~=nil,'A: the review says it spent nothing',f.notice:GetText())
 C.expect(Same(before,Effects()),'A: Review target adopts, selects, writes and spends nothing')
 bar.refresh();UI.ShowMini()
 C.expect(not bar.resume:IsEnabled() and not mini.resume:IsEnabled(),'A: the compact views still leave a changed target to the full window')
 f.review:Click()
 C.expect(not f.resume:IsEnabled() and f.review:GetText()=='Review target','A: Cancel review withholds Resume again')
 C.expect(Same(before,Effects()),'A: Cancel review spends nothing')

 -- A review belongs to one exact assignment.
 f.review:Click();C.setup(f.resume:IsEnabled(),'A: reviewed again')
 C.setup(A.SetFirstLoadoutWishlistIdentity('Third target',{{spellId=410002,quality=2,stacks=2}}),'A: the assignment changes again after the review')
 UI.Refresh()
 local t3=M.Status().resumeTarget
 C.expect(t3 and t3.kind=='changed' and t3.name=='Third target' and t3.key~=t.key,'A: another assignment has another key')
 C.expect(not f.resume:IsEnabled() and f.review:GetText()=='Review target'
  and f.status:GetText():find("New target: Resume would use 'Third target'",1,true)~=nil,'A: a review never carries over to another assignment')
 local before3=Effects();Direct(f.resume)
 C.expect(Same(before3,Effects()),'A: a click after the target changed again resumes nothing')

 -- Closing the window clears the review.
 f.review:Click();C.setup(f.resume:IsEnabled(),'A: the third target is reviewed')
 f:Hide();UI.Show()
 C.expect(not f.resume:IsEnabled() and f.review:GetText()=='Review target','A: closing the window clears the review')

 -- The reviewed Resume is the existing runtime Resume, with its own checks.
 f.review:Click()
 local spends=H.Count('orb-spend')
 f.resume:Click()
 s=M.Status()
 C.guard(H.Count('orb-spend')==spends+1 and s.limit==3 and s.spent==1,'A: the reviewed Resume keeps the same maximum and usage',s.spent)
 C.guard(s.operationName=='Third target' and s.config.name=='Third target','A: Resume adopted exactly the reviewed assignment',s.operationName)
 C.expect(s.resumeTarget==nil and M.CompactStatus().resumeTarget==nil,'A: a running run has no Resume target')
 C.guard(Nexus.RecomputeStats().autoEnabled==false,'A: ordinary Automation stays OFF')
end)

C.scenario('B pending operation: a changed target waits for settlement; the original stays named',function()
 Fresh()
 H.OrbPlan(PLAN)
 C.setup(M.Start(3),'B: the run starts')
 H.Offer()
 C.setup(H.Count('take')==1,'B: the running run selected from the offer')
 C.setup(A.SetFirstLoadoutWishlistIdentity('Changed target',{{spellId=410004,quality=3,stacks=2}}),'B: the target changes while the result is pending')
 M.Pump()
 local s=M.Status()
 C.setup(s.state=='PAUSED' and s.pending and s.targetChanged,'B: the runtime paused the original submitted operation')
 local f=UI.Show()
 local t=s.resumeTarget
 C.expect(t and t.kind=='settle' and t.name==nil and t.original=='Orb test','B: no new Resume target while the original is pending',t and t.kind)
 local text=f.status:GetText()
 C.expect(text:find('Resume waits: the original operation must settle',1,true)~=nil,'B: the window says the original must settle first',text)
 C.guard(text:find('Original operation: Orb test',1,true)~=nil and f.plan:GetText():find('Changed target',1,true)~=nil,
  'B: the original operation and the current assignment are both still named',text)
 C.expect(not f.resume:IsEnabled() and not f.review:IsShown() and f.stop:IsEnabled(),'B: no Resume and no review before settlement; Stop stays')
 local bar=Strip()
 C.setup(bar~=nil,'B: the strip exists')
 C.expect(bar.summary:GetText():find('Paused - original must settle first',1,true)~=nil,'B: the strip says the original must settle',bar.summary:GetText())
 C.expect(not bar.resume:IsEnabled(),'B: the strip offers no Resume')
 local mini=UI.ShowMini()
 C.guard(mini.state:GetText()=='Paused - a pending result must settle first' and not mini.resume:IsEnabled(),'B: the mini panel keeps its settle-first state')
 local before=Effects()
 local resumed=M.Resume()
 C.guard(not resumed and Same(before,Effects()),'B: the runtime refuses Resume before settlement and nothing changes')
 H.Result(410002,2)
 s=M.Status()
 C.setup(not s.pending and s.state=='PAUSED' and s.spent==1,'B: the original operation settled')
 UI.Refresh()
 t=s.resumeTarget
 C.expect(t and t.kind=='changed' and t.name=='Changed target' and t.original=='Orb test','B: after settlement the assignment Resume would adopt is named',t and t.kind)
 C.expect(not f.resume:IsEnabled() and f.review:IsShown(),'B: and Resume waits for the review')
 C.guard(f.status:GetText():find('Original operation: Orb test',1,true)~=nil,'B: the settled original is still named')
end)

C.scenario('C assignment not ready: Resume names no guessed target',function()
 Fresh()
 SettledPausedRun()
 local slots=H.service.GetServerBuildSlots
 H.service.GetServerBuildSlots=function() return nil end
 local a=A.AssignedWishlist()
 C.setup(a.state~='ready','C: with no build-slot data the real assignment read is not ready',a.state)
 local s,c=M.Status(),M.CompactStatus()
 C.expect(s.resumeTarget and s.resumeTarget.kind=='unavailable' and s.resumeTarget.name==nil and s.resumeTarget.key==nil,
  'C: the full read names no target',s.resumeTarget and s.resumeTarget.kind)
 C.expect(c.resumeTarget and c.resumeTarget.kind=='unavailable' and c.resumeTarget.name==nil,'C: the compact read names no target')
 C.guard(not s.canResume and not c.canResume,'C: Resume is not offered')
 local f=UI.Show();local text=f.status:GetText()
 C.expect(text:find('Resume target unknown',1,true)~=nil and not text:find('Resume would use',1,true),'C: the window says the target is unknown and guesses none',text)
 C.expect(not f.resume:IsEnabled() and not f.review:IsShown(),'C: no Resume and no review')
 local bar=Strip()
 C.setup(bar~=nil,'C: the strip exists')
 local summary=bar.summary:GetText()
 C.expect(summary:find('Resume target unknown',1,true)~=nil and not summary:find('Resume uses',1,true),'C: the strip guesses no target',summary)
 local mini=UI.ShowMini()
 C.expect(mini.state:GetText()=='Paused - the assigned Wishlist is not ready' and not mini.reason:GetText():find('Resume uses',1,true),
  'C: the mini panel guesses no target',mini.state:GetText())
 local before=Effects();local ok=M.Resume()
 C.guard(not ok and Same(before,Effects()),'C: the runtime refuses Resume and nothing changes')
 H.service.GetServerBuildSlots=slots
 UI.Refresh()
 C.expect(M.Status().resumeTarget and M.Status().resumeTarget.kind=='same','C: the restored assignment is named again')
end)

C.scenario('D pending original: every surface names the operation Resume continues',function()
 Fresh()
 H.OrbPlan(PLAN)
 local f=UI.Show();f.limit:SetText('3');f.start:Click();f.pause:Click();H.Offer();UI.Refresh()
 local s=M.Status()
 C.setup(s.state=='PAUSED' and s.pending and s.canResume and H.Count('take')==0,'D: paused with an ordinary pending spend that can resume')
 C.expect(s.resumeTarget and s.resumeTarget.kind=='original' and s.resumeTarget.name=='Orb test','D: the original operation is named')
 C.expect(f.status:GetText():find("Resume continues the original operation for 'Orb test'",1,true)~=nil,'D: the full window names it',f.status:GetText())
 local bar=Strip()
 C.setup(bar~=nil,'D: the strip exists')
 C.expect(bar.summary:GetText():find("Resume uses: 'Orb test'",1,true)~=nil,'D: the strip names it',bar.summary:GetText())
 local mini=UI.ShowMini()
 C.expect(mini.reason:GetText():find("Resume uses: 'Orb test'",1,true)~=nil,'D: the mini panel names it',mini.reason:GetText())
 C.expect(f.resume:IsEnabled() and bar.resume:IsEnabled() and mini.resume:IsEnabled() and not f.review:IsShown(),
  'D: continuing the original operation needs no review')
 bar.resume:Click()
 C.expect(M.Status().running and H.Count('take')==1 and M.Status().limit==3 and H.Count('orb-spend')==1,
  'D: the strip Resume continues the original once with the same maximum')
end)

C.scenario('E owner/context gate: a withheld compact Resume names nothing',function()
 Fresh()
 SettledPausedRun()
 local trust=A.OwnershipTrustView;A.OwnershipTrustView=nil
 local c=M.CompactStatus()
 C.guard(not c.canResume,'E: missing passive owner context withholds the compact Resume')
 C.expect(c.resumeTarget and c.resumeTarget.kind=='blocked' and c.resumeTarget.name==nil,'E: and no target is named for it',c.resumeTarget and c.resumeTarget.kind)
 local mini=UI.ShowMini()
 C.guard(not mini.resume:IsEnabled(),'E: the mini panel offers no Resume')
 A.OwnershipTrustView=trust
 local again=M.CompactStatus()
 C.expect(again.canResume and again.resumeTarget and again.resumeTarget.kind=='same','E: the restored context offers it again, unchanged')
end)

C.finish('real OrbRuntime and Orb window/strip/mini handlers; synthetic services; no native or spending claim')
