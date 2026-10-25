-- M6 (UX-07 / LP-07): a paused Orb run names what an explicit Resume would act
-- on, on every Orb surface. That is the ready assignment a settled run would
-- adopt, or the original operation a pending run would continue, kept apart
-- from the original operation's own name. An assignment that is not ready is
-- never named. After a changed target, Resume is offered only in the full
-- window and only after a deliberate review of that exact assignment. Review
-- and Cancel review spend nothing. The review is cleared by another assignment
-- or by closing the window, and it never weakens a runtime gate.
-- Categories (view_regression_support): EXPECT marks behaviour introduced
-- with its check, GUARD marks earlier behaviour that must keep holding, and
-- SETUP marks the fixture.
-- Oracles:
--  * the real OrbRuntime reads (Status, CompactStatus, Resume);
--  * the real Orb window, main-panel strip and mini panel handlers and fontstrings;
--  * spend, take, send and action counters and the saved Orb row.
-- Real addon boot; synthetic game services only. No native, double-click or
-- spending claim.
local V=dofile('tests/prototype/view_regression_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
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

-- F5 current-contract oracles (the strip and mini rows of A, D and G). They
-- test what a shown line means against the runtime's own facts, not the
-- product's wording or cut: a target is named by its quoted name, whole or
-- its quoted start (at least three characters) cut with "..."; a count is
-- the actual whole number tied to its noun ('?' when the runtime has none);
-- the kind word (new, back or same) stands outside the name. A row needs all
-- of its parts together; one of them alone never counts.
local function NameToken(line,name)
 line,name=tostring(line or ''),tostring(name or '')
 if name=='' then return nil end
 local a,b=line:find("'"..name.."'",1,true)
 for keep=#name-1,math.min(3,#name),-1 do
  if a then break end
  a,b=line:find("'"..name:sub(1,keep).."...",1,true)
 end
 return a,b
end
local function Lines(text)
 local out={};for l in (tostring(text or '')..'\n'):gmatch('(.-)\n') do out[#out+1]=l end;return out
end
-- The shown line that names the target, and its words outside the name.
local function TargetRow(text,name)
 for _,line in ipairs(Lines(text)) do
  local a,b=NameToken(line,name)
  if a then return line,line:sub(1,a-1)..' '..line:sub(b+1) end
 end
 return nil,''
end
-- The strip's fact for a compact read: the requested Orbs pending, the
-- unsettled last action, or the rolled copies left.
local function StripFact(text,c)
 local t=tostring(text or ''):lower()
 if (c.reserved or 0)>0 then return t:find('%f[%d]'..c.reserved..'%f[%D][^;%c]-pending')~=nil end
 if c.pending then return t:find('not settled',1,true)~=nil end
 local n=c.remaining~=nil and ('%f[%d]'..c.remaining..'%f[%D]') or '%?'
 return t:find(n..'[^;%c]-cop')~=nil and not t:find('not settled',1,true)
end
local function KindOnly(text,word)
 for _,w in ipairs({'new','back','same'}) do
  if V.Names(text,w)~=(w==word) then return false end
 end
 return true
end
local function StripRow(text,name,c,word)
 local row,outside=TargetRow(text,name)
 return row~=nil and StripFact(outside,c) and KindOnly(outside,word)
end
-- The mini missing row: the rolled copies missing, tied to "missing".
local function MiniCount(text,n)
 local v=n~=nil and tostring(n) or '%?'
 return tostring(text or ''):lower():find('missing:?%s*'..v..'%f[%D]')~=nil
end
local function MiniRow(text,name,n)
 local row,outside=TargetRow(text,name)
 return row~=nil and MiniCount(outside,n)
end
-- A shown reason is the actual one as displayed (controls as spaces, pipes
-- doubled): whole, or its start (at least ten characters) cut with "...".
local function Flat(s) return (tostring(s or ''):gsub('%c',' '):gsub('|','||')) end
local function ReasonShown(shown,reason)
 local whole=Flat(reason);shown=tostring(shown or '')
 if whole=='' then return false end
 if shown==whole then return true end
 local head=shown:match('^(.*)%.%.%.$')
 return head~=nil and #head>=math.min(10,#whole) and whole:sub(1,#head)==head
end
local function Chars(text) return G.Length(G.Visible(text)) end
-- The lines an actual hover area writes; its OnLeave then runs.
local function Hover(hit)
 local lines,ok=V.TooltipLines(function()hit:GetScript('OnEnter')(hit)end)
 hit:GetScript('OnLeave')(hit)
 return ok and lines or {}
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
 -- F5 current-contract adaptation: the strip row keeps the actual fact
 -- (copies left, pending or not settled) beside the bounded name and its
 -- short kind; the complete "New target: ..." caption and the complete fact
 -- are on the strip's actual hover; the review instruction stays shown.
 local sc=M.CompactStatus() or {}
 local srow=TargetRow(summary,'New legitimate target')
 C.expect(StripRow(summary,'New legitimate target',sc,'new') and Chars(srow)*7<=bar.summary:GetWidth()
  and summary:find('review it in the Orb window',1,true)~=nil,
  'A: the strip names the new target and where to review it',summary)
 local swhole=Hover(bar.summaryHit)[1] or ''
 C.expect(swhole==bar.summary._nexusFullText and swhole:find("New target: 'New legitimate target'",1,true)~=nil
  and StripFact(swhole,sc) and swhole:find('review it in the Orb window',1,true)~=nil,
  'A: hovering the strip gives the complete new target, its fact and where to review it',swhole)
 C.guard(bar.stop:IsEnabled(),'A: the strip keeps Stop')
 C.expect(not bar.resume:IsEnabled() and not bar.primary:IsEnabled(),'A: the strip offers no Resume for a changed target')
 local mini=UI.ShowMini()
 C.expect(mini.state:GetText()=='Paused - review the new target in Open Orbs','A: the mini panel says where to review',mini.state:GetText())
 -- F5 current-contract adaptation: the reason row shows the run's actual
 -- reason (complete on its hover); the target moved to the missing row
 -- beside the rolled copies the runtime counts, and the complete count and
 -- "New target: ..." caption to that row's actual hover.
 local mc=M.CompactStatus() or {}
 local mp=M.Status().progress
 C.setup(mc.remaining~=nil and mp~=nil and mc.remaining==mp.rolledMissing,'A: fixture: the compact read carries the rolled copies of the full read',mc.remaining)
 local missing=mini.missing:GetText() or ''
 C.expect(MiniRow(missing,'New legitimate target',mc.remaining) and Chars(missing)*7<=mini.missing:GetWidth(),
  'A: the mini panel names the new target',missing)
 local missFull=Hover(mini.missingHit)[1] or ''
 C.expect(missFull==mini.missing._nexusFullText and missFull:find("New target: 'New legitimate target'",1,true)~=nil
  and MiniCount(missFull,mc.remaining) and not missFull:find('...',1,true),
  'A: hovering the missing row gives the complete new target and its count',missFull)
 C.setup(type(mc.reason)=='string' and mc.reason~='','A: fixture: the runtime reports a current reason',mc.reason)
 local reasonShown=mini.reason:GetText() or ''
 local reasonFull=Hover(mini.reasonHit)[1] or ''
 C.expect(ReasonShown(reasonShown,mc.reason) and Chars(reasonShown)*7<=mini.reason:GetWidth()
  and reasonFull==Flat(mc.reason) and (mini.reason._nexusFullText or reasonShown)==reasonFull,
  'A: the mini reason row keeps the actual reason, complete on hover',reasonShown)
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
 -- F5 current-contract adaptation, as in A: the strip row keeps the actual
 -- fact beside the bounded name and its kind (same: the original operation),
 -- the mini missing row the rolled copies beside the name, and the reason
 -- row the actual reason; the complete "Resume uses: ..." caption and the
 -- facts are on the actual hovers.
 local dc=M.CompactStatus() or {}
 local dsum=bar.summary:GetText() or ''
 local drow=TargetRow(dsum,'Orb test')
 C.expect(StripRow(dsum,'Orb test',dc,'same') and Chars(drow)*7<=bar.summary:GetWidth(),'D: the strip names it',dsum)
 local dwhole=Hover(bar.summaryHit)[1] or ''
 C.expect(dwhole==bar.summary._nexusFullText and dwhole:find("Resume uses: 'Orb test'",1,true)~=nil and StripFact(dwhole,dc),
  'D: hovering the strip gives the complete original target and its fact',dwhole)
 local mini=UI.ShowMini()
 local dmiss=mini.missing:GetText() or ''
 C.expect(MiniRow(dmiss,'Orb test',dc.remaining) and Chars(dmiss)*7<=mini.missing:GetWidth(),'D: the mini panel names it',dmiss)
 local dmissFull=Hover(mini.missingHit)[1] or ''
 C.expect(dmissFull==mini.missing._nexusFullText and dmissFull:find("Resume uses: 'Orb test'",1,true)~=nil
  and MiniCount(dmissFull,dc.remaining),'D: hovering the missing row gives the complete count and original target',dmissFull)
 C.setup(type(dc.reason)=='string' and dc.reason~='','D: fixture: the runtime reports a current reason',dc.reason)
 local dreason=mini.reason:GetText() or ''
 local dreasonFull=Hover(mini.reasonHit)[1] or ''
 C.expect(ReasonShown(dreason,dc.reason) and Chars(dreason)*7<=mini.reason:GetWidth() and dreasonFull==Flat(dc.reason),
  'D: the mini reason row keeps the actual reason, complete on hover',dreason)
 C.guard(bar.stop:IsEnabled() and mini.stop:IsEnabled(),'D: the strip and the mini panel keep Stop')
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

-- F: the changed-target Review race at 4f38ff95. The window renders target
-- B; the real writer assigns C before the next 0.25 s refresh; the player
-- clicks the button that still shows B. A click may act only on the exact
-- target (key) and the action that button showed. EXPECT is the race
-- behaviour 4f38ff95 lacks (predicted there, not executed by the author);
-- SETUP and GUARD hold there too. Closing the window clears any review (A),
-- so the Cancel race starts from the same state with or without the fix.
C.scenario('F stale Review/Cancel: a click acts only on the target the window showed',function()
 Fresh()
 local f=SettledPausedRun()
 C.setup(A.SetFirstLoadoutWishlistIdentity('Shown target B',{{spellId=410004,quality=3,stacks=2}}),'F: the real writer assigns B')
 UI.Refresh()
 local s=M.Status();local targetB=s.resumeTarget or {}
 C.setup(s.canResume and targetB.kind=='changed' and targetB.name=='Shown target B' and targetB.key~=nil,
  'F: the runtime offers the changed-target Resume for B',targetB.kind)
 local statusB=f.status:GetText()
 C.setup(statusB:find("New target: Resume would use 'Shown target B'",1,true)~=nil and f.review:IsShown()
  and f.review:GetText()=='Review target' and not f.resume:IsEnabled(),'F: the window displayed B with Review target and Resume withheld',statusB)

 -- C replaces B before the next refresh: no UI.Refresh and no H.Advance
 -- until the click.
 C.setup(A.SetFirstLoadoutWishlistIdentity('Unseen target C',{{spellId=410002,quality=2,stacks=2}}),'F: the real writer assigns C')
 s=M.Status();local targetC=s.resumeTarget or {}
 C.setup(targetC.kind=='changed' and targetC.name=='Unseen target C' and targetC.key~=nil and targetC.key~=targetB.key,
  'F: C is a changed target with another key',targetC.kind)
 C.setup(s.canResume and M.CompactStatus().canResume,'F: the runtime still legitimately offers the changed-target Resume')
 C.setup(f.status:GetText()==statusB and f.review:GetText()=='Review target' and not f.resume:IsEnabled(),
  'F: the window still displays B: nothing refreshed it',f.status:GetText())
 local before=Effects()
 f.review:Click()
 local text,notice=f.status:GetText(),f.notice:GetText()
 C.expect(not f.resume:IsEnabled() and f.review:GetText()=='Review target',
  'F: a stale Review click reviews no unseen C: Resume stays withheld',f.review:GetText())
 C.expect(text:find("New target: Resume would use 'Unseen target C'",1,true)~=nil and not text:find('Reviewed:',1,true),
  'F: the refreshed window shows C, not reviewed',text)
 C.expect(notice:find('target changed after it was shown',1,true)~=nil and notice:find('review it again',1,true)~=nil,
  'F: the notice says the target changed and needs another review',notice)
 C.guard(Same(before,Effects()),'F: the stale Review click adopted, selected, wrote and spent nothing')

 -- A passive refresh, then one deliberate Review of the C now shown.
 UI.Refresh()
 local now=M.Status().resumeTarget or {}
 C.setup(now.key~=nil and now.key==targetC.key,'F: C is still the target the runtime names')
 f.review:Click()
 C.expect(f.resume:IsEnabled() and f.review:GetText()=='Cancel review'
  and f.status:GetText():find("Reviewed: Resume would use 'Unseen target C'",1,true)~=nil,
  'F: a deliberate Review of the shown C reviews exactly C',f.status:GetText())
 C.guard(Same(before,Effects()),'F: the deliberate review spends nothing')
 f.review:Click()
 C.expect(not f.resume:IsEnabled() and f.review:GetText()=='Review target'
  and f.notice:GetText():find('Review cancelled',1,true)~=nil,'F: Cancel review of the shown C withholds Resume again',f.notice:GetText())
 C.guard(Same(before,Effects()),'F: Cancel review spends nothing')

 -- The same race on Cancel review. Closing the window clears any review;
 -- C is then reviewed deliberately and D replaces it before the next refresh.
 f:Hide();UI.Show();f.review:Click()
 C.setup(f.resume:IsEnabled() and f.review:GetText()=='Cancel review','F: C is reviewed and Cancel review is displayed')
 C.setup(A.SetFirstLoadoutWishlistIdentity('Third target D',{{spellId=410004,quality=3,stacks=1}}),'F: the real writer assigns D')
 s=M.Status();local targetD=s.resumeTarget or {}
 C.setup(targetD.kind=='changed' and targetD.name=='Third target D' and targetD.key~=nil
  and targetD.key~=targetC.key and targetD.key~=targetB.key,'F: D is a changed target with a third key',targetD.kind)
 C.setup(s.canResume,'F: the runtime still offers the changed-target Resume')
 C.setup(f.review:GetText()=='Cancel review' and f.resume:IsEnabled()
  and f.status:GetText():find("Reviewed: Resume would use 'Unseen target C'",1,true)~=nil,
  'F: the window still displays the review of C: nothing refreshed it',f.status:GetText())
 before=Effects()
 f.review:Click()
 text,notice=f.status:GetText(),f.notice:GetText()
 C.expect(not f.resume:IsEnabled() and f.review:GetText()=='Review target',
  'F: a stale Cancel review click reviews no unseen D: Resume stays withheld',f.review:GetText())
 C.expect(text:find("New target: Resume would use 'Third target D'",1,true)~=nil and not text:find('Reviewed:',1,true),
  'F: the refreshed window shows D, not reviewed',text)
 C.expect(notice:find('target changed after it was shown',1,true)~=nil and notice:find('review it again',1,true)~=nil,
  'F: the notice says the target changed and needs another review',notice)
 C.guard(Same(before,Effects()),'F: the stale Cancel click adopted, selected, wrote and spent nothing')
end)

-- G (F5): a short ready new target, read through the real runtime and the
-- actual strip and mini fontstrings and hover areas. Beside the target the
-- strip keeps the true copies left and the kind, the mini panel the true
-- rolled copies missing, and its reason row keeps the run's actual reason;
-- each hover is complete. Resume stays withheld for the review and Stop
-- stays on every surface; rendering, ticking and hovering change nothing.
-- EXPECT is the F5 composition, GUARD earlier behaviour, SETUP the fixture
-- and its oracle controls. The column checks use the offline horizontal
-- model only (layout_geometry_support's doubled-model 11 px per character as
-- synthetic columns): no native, vertical or doubled-font fit is claimed.
C.scenario('G short new target: the actual reason and the true copies stay visible beside it',function()
 Fresh()
 local f=SettledPausedRun()
 C.setup(A.SetFirstLoadoutWishlistIdentity('Main',{{spellId=410004,quality=3,stacks=2}}),
  'G: the real writer assigns a short valid plan: two copies of an Echo not owned')
 UI.Refresh()
 local s,c=M.Status(),M.CompactStatus() or {}
 local t,ct=s.resumeTarget or {},c.resumeTarget or {}
 C.setup(s.state=='PAUSED' and not s.pending and s.spent==1 and s.reserved==0 and s.limit==3 and s.canResume
  and t.kind=='changed' and t.name=='Main' and not t.returned and ct.kind=='changed' and ct.name=='Main' and ct.key==t.key,
  'G: fixture: the settled paused run of 3 would adopt Main, after its review',t.kind)
 C.setup(s.progress~=nil and s.progress.rolledMissing==2 and c.remaining==2,
  'G: fixture: the runtime counts the two rolled copies still missing',c.remaining)
 C.setup(type(c.reason)=='string' and c.reason~='','G: fixture: the runtime reports a current reason',c.reason)
 -- Oracle controls: the target with no count, the reason alone or the count
 -- alone is rejected; only a row with both (and, on the strip, the kind) counts.
 C.setup(not MiniRow("New target: 'Main'",'Main',2) and not MiniRow(c.reason,'Main',2)
  and not MiniRow('Rolled target copies missing: 2','Main',2) and not MiniRow("Missing: 3 for 'Main'",'Main',2)
  and MiniRow("Missing: 2 for 'Main'",'Main',2),'G: oracle: the mini row needs the target and its true count together')
 C.setup(not StripRow("'Main' (new)",'Main',c,'new') and not StripRow(c.reason,'Main',c,'new')
  and not StripRow('2 copies left','Main',c,'new') and not StripRow("2 copies left; 'Main' (same)",'Main',c,'new')
  and StripRow("new 'Main': 2 copies left",'Main',c,'new'),'G: oracle: the strip row needs the target, its true fact and its kind together')
 C.setup(not ReasonShown("New target: 'Main'",c.reason) and not ReasonShown('',c.reason) and ReasonShown(c.reason,c.reason),
  'G: oracle: a target caption or an empty row is not the reason')
 local bar=Strip()
 C.setup(bar~=nil,'G: the main-panel strip exists')
 local before=Effects()
 bar.refresh()
 local mini=UI.ShowMini()
 mini:GetScript('OnUpdate')(mini,1)
 UI.Refresh()
 local summary=bar.summary:GetText() or ''
 local row=TargetRow(summary,'Main')
 C.expect(StripRow(summary,'Main',c,'new') and row~=nil and row:find("'Main'",1,true)~=nil and Chars(row)*7<=bar.summary:GetWidth(),
  'G: the strip shows the whole short target, its kind and the two copies left on one bounded line',summary)
 C.guard(summary:find('review it in the Orb window',1,true)~=nil,'G: the strip still says where to review it',summary)
 local missing=mini.missing:GetText() or ''
 C.expect(MiniRow(missing,'Main',2) and missing:find("'Main'",1,true)~=nil and Chars(missing)*7<=mini.missing:GetWidth(),
  'G: the mini missing row shows the whole short target beside the two rolled copies missing',missing)
 local reasonShown=mini.reason:GetText() or ''
 C.expect(ReasonShown(reasonShown,c.reason) and Chars(reasonShown)*7<=mini.reason:GetWidth(),
  'G: the mini reason row keeps the actual runtime reason, bounded',reasonShown)
 C.guard(mini.state:GetText()=='Paused - review the new target in Open Orbs','G: the mini state says where to review',mini.state:GetText())
 local whole=Hover(bar.summaryHit)[1] or ''
 local wl,sl=Lines(whole),Lines(summary)
 C.expect(whole==bar.summary._nexusFullText and whole:find("New target: 'Main'",1,true)~=nil and StripFact(whole,c)
  and wl[1]==sl[1] and wl[#wl]==sl[#sl] and whole:find('review it in the Orb window',1,true)~=nil,
  'G: hovering the strip gives the complete target and fact with the usage and where to review',whole)
 local missFull=Hover(mini.missingHit)[1] or ''
 C.expect(missFull==mini.missing._nexusFullText and missFull:find("New target: 'Main'",1,true)~=nil and MiniCount(missFull,2)
  and not missFull:find('...',1,true),'G: hovering the missing row gives the complete count and target',missFull)
 local reasonFull=Hover(mini.reasonHit)[1] or ''
 C.expect(reasonFull==Flat(c.reason) and (mini.reason._nexusFullText or reasonShown)==reasonFull,
  'G: hovering the reason row gives the complete actual reason',reasonFull)
 C.guard(not f.resume:IsEnabled() and f.review:IsShown() and f.review:GetText()=='Review target'
  and not bar.resume:IsEnabled() and not bar.primary:IsEnabled() and not mini.resume:IsEnabled()
  and f.stop:IsEnabled() and bar.stop:IsEnabled() and mini.stop:IsEnabled(),
  'G: the changed target withholds Resume on every surface until its review; Stop stays')
 C.guard(Same(before,Effects()),'G: rendering, ticking and hovering adopted, selected, wrote, sent and spent nothing')
 -- Horizontal synthetic columns only (see the scenario note).
 local cols=math.floor(bar.summary:GetWidth()/G.MODELS.double.char)
 local lead=G.Visible(row or ''):sub(1,cols)
 local la,lb=lead:find("'Main'",1,true)
 C.expect(la~=nil and StripFact(lead:sub(1,la-1)..' '..lead:sub(lb+1),c),
  'G: the short target and its copies left lie within the first '..cols..' synthetic columns of the strip line',lead)
 C.expect(Chars(missing)*G.MODELS.double.char<=mini.missing:GetWidth(),
  'G: the short mini missing row lies within its width in the same synthetic columns',Chars(missing))
 local sumRect,miniRect=G.Rect(bar.summary,bar),G.Rect(mini,mini)
 local missRect,reasonRect=G.Rect(mini.missing,mini),G.Rect(mini.reason,mini)
 local clear=G.Inside(missRect,miniRect) and G.Inside(reasonRect,miniRect) and G.Apart(missRect,reasonRect)
 for _,b in ipairs({bar.pause,bar.resume,bar.stop,bar.details}) do clear=clear and G.Apart(G.Rect(b,bar),sumRect) end
 for _,b in ipairs({mini.pause,mini.resume,mini.stop,mini.open}) do
  local r=G.Rect(b,mini);clear=clear and G.Inside(r,miniRect) and G.Apart(r,missRect) and G.Apart(r,reasonRect)
 end
 C.guard(clear and bar:GetHeight()==100 and bar.summary:GetWidth()==252 and bar.summary:GetHeight()==52
  and mini:GetWidth()==356 and mini:GetHeight()==196 and mini.missing:GetWidth()==332 and mini.missing:GetHeight()==17
  and mini.reason:GetWidth()==332 and mini.reason:GetHeight()==17,
  'G: the strip, the mini lines and their buttons keep their boxes, inside and apart',G.Text(sumRect)..' '..G.Text(missRect))
 mini:Hide()
end)

C.finish('real OrbRuntime and Orb window/strip/mini handlers; synthetic services; no native or spending claim')
