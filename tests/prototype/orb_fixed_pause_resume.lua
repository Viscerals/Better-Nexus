-- M6 (UX-08 / LP-08): during an Orb run, Pause and Resume are separate
-- buttons in fixed places in the full Orb window and in the main-panel strip,
-- as in the mini panel. A repeated press of Pause can never become Resume, and
-- a repeated Resume adds nothing. Start, including the two-step Start new run
-- / Confirm new run, returns once the run is no longer active. The mini panel's
-- design is unchanged. The earlier one-button entry points stay only as hidden
-- programmatic controls.
-- Categories (view_regression_support): EXPECT marks behaviour introduced
-- with its check, GUARD marks earlier behaviour that must keep holding, and
-- SETUP marks the fixture.
-- Oracles: the real Orb window, strip and mini panel handlers, their geometry
-- in the 7 px conservative text model of orb_budget_draft, the real OrbRuntime,
-- and spend, take, send and action counters with the saved Orb row.
-- Synthetic services only. Not a native double-click, pixel or keyboard proof.
local V=dofile('tests/prototype/view_regression_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local C=V.Checker('orb_fixed_pause_resume')
local H,M,A,O,UI
local PLAN={{spellId=410002,quality=2,stacks=3}}
local CAPS=20

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
  limit=s.limit,running=s.running,pending=s.pending}
end
local function Same(a,b)
 for k,v in pairs(a) do if b[k]~=v then return false end end
 return true
end
local function Direct(b) return b:GetScript('OnClick')(b) end
local function X(r) local p={r:GetPoint(1)};return type(p[2])=='number' and p[2] or p[4] end
local function Y(r) local p={r:GetPoint(1)};return type(p[2])=='number' and p[3] or p[5] end
local function Fits(label,b)
 return #label*5.5+CAPS<=b:GetWidth() and #label*7.0+CAPS<=b:GetWidth()
end

C.scenario('F1 full window: separate fixed Pause and Resume during a run',function()
 Fresh()
 H.OrbPlan(PLAN)
 local f=UI.Show()
 C.guard(f.start:IsShown() and f.start:GetText()=='Start','F1: before a run Start shows')
 C.expect(not f.pause:IsShown() and not f.resume:IsShown(),'F1: no Pause or Resume before a run')
 f.limit:SetText('3');f.start:Click()
 C.setup(M.Status().running and H.Count('orb-spend')==1,'F1: Start approved the run and submitted one Orb')
 C.expect(not f.start:IsShown() and f.pause:IsShown() and f.resume:IsShown(),'F1: during the run, Pause and Resume replace Start')
 C.expect(f.pause:IsEnabled() and not f.resume:IsEnabled(),'F1: a running run offers Pause only')
 C.guard(f.start:GetText()=='Pause','F1: the hidden legacy entry keeps its label for programmatic callers')
 C.expect(Y(f.pause)==Y(f.start) and Y(f.resume)==Y(f.start) and f.pause:GetHeight()==f.start:GetHeight()
  and f.resume:GetHeight()==f.start:GetHeight(),'F1: both sit on the Start row at its height')
 C.expect(X(f.pause)>=X(f.start) and X(f.resume)+f.resume:GetWidth()<=X(f.start)+f.start:GetWidth(),'F1: both fit in Start\'s place')
 C.expect(X(f.resume)-(X(f.pause)+f.pause:GetWidth())>=6,'F1: Pause and Resume are distinct targets with padding')
 C.expect(X(f.stop)-(X(f.resume)+f.resume:GetWidth())>=6,'F1: Resume and Stop are distinct targets with padding')
 C.expect(Fits('Pause',f.pause) and Fits('Resume',f.resume),'F1: both labels fit in the default and conservative models')
 C.guard(X(f.stop)==470 and f.stop:GetWidth()==120 and X(f.start)==334 and f.start:GetWidth()==126,'F1: Start and Stop keep their places')

 f.pause:Click()
 C.setup(M.Status().state=='PAUSED' and not M.Status().running,'F1: the first Pause paused the run')
 C.expect(f.pause:GetText()=='Pause' and f.resume:GetText()=='Resume','F1: neither button changed its label')
 C.expect(not f.pause:IsEnabled(),'F1: the pressed Pause button is now disabled')
 local before=Effects()
 f.pause:Click();Direct(f.pause);Direct(f.pause)
 C.expect(M.Status().state=='PAUSED' and not M.Status().running,'F1: repeated Pause presses leave the run paused')
 C.expect(f.notice:GetText():find('Not paused',1,true)~=nil,'F1: a press that reaches the handler says it did nothing',f.notice:GetText())
 C.expect(Same(before,Effects()),'F1: repeated Pause sends, selects, writes and spends nothing')
 H.Offer();UI.Refresh()
 C.guard(H.Count('take')==0,'F1: a paused offer is not selected')
 Direct(f.pause);H.Advance(.3)
 C.expect(H.Count('take')==0 and M.Status().state=='PAUSED','F1: Pause pressed after the offer still never resumes')
 C.expect(f.resume:IsEnabled(),'F1: Resume is its own button')

 f.resume:Click()
 C.expect(M.Status().running and H.Count('take')==1 and M.Status().limit==3,'F1: Resume continues with the same maximum and selects once')
 C.expect(f.resume:GetText()=='Resume' and not f.resume:IsEnabled() and f.pause:IsEnabled(),'F1: after Resume only Pause is offered')
 Direct(f.resume)
 C.expect(H.Count('take')==1 and H.Count('orb-spend')==1,'F1: a repeated Resume selects and spends nothing more')
 C.expect(f.notice:GetText():find('already running',1,true)~=nil,'F1: and says why',f.notice:GetText())
 f.stop:Click()
 C.guard(not M.Status().running and M.Status().pending,'F1: Stop keeps the submitted operation unresolved')
 C.expect(f.pause:IsShown() and not f.pause:IsEnabled() and not f.resume:IsEnabled(),'F1: a stopped run with a pending result offers neither')
 C.guard(Nexus.RecomputeStats().autoEnabled==false,'F1: ordinary Automation stays OFF')
end)

C.scenario('F2 main-panel strip: fixed Pause and Resume; the one-button entry is not shown',function()
 Fresh()
 H.OrbPlan(PLAN)
 C.setup(M.Start(3),'F2: the run started')
 Nexus.Panel.Show();H.Advance(.3)
 local bar=NexusPanel and NexusPanel._orbControls
 C.setup(bar~=nil,'F2: the strip exists')
 bar.refresh()
 C.expect(bar.pause:IsShown() and bar.resume:IsShown() and not bar.primary:IsShown(),'F2: separate buttons show; the one-button entry is hidden')
 C.expect(bar.pause:IsEnabled() and not bar.resume:IsEnabled(),'F2: a running run offers Pause only')
 local row={bar.pause,bar.resume,bar.stop,bar.details}
 local labels={'Pause','Resume','Stop','Details'}
 local ordered=true
 for i=1,#row do
  if Y(row[i])~=Y(bar.pause) or not Fits(labels[i],row[i]) then ordered=false end
  if i>1 and X(row[i])-(X(row[i-1])+row[i-1]:GetWidth())<6 then ordered=false end
 end
 C.expect(ordered,'F2: Pause, Resume, Stop and Details are on one row, distinct, padded and readable')
 C.expect(X(bar.details)+bar.details:GetWidth()<=262,'F2: the row stays within the earlier strip width')
 local summary=bar.summary:GetText()
 C.expect(summary:find('Orbs used: 0 / 3 approved',1,true)~=nil and summary:find('1 Orb pending, not confirmed yet',1,true)~=nil,
  'F2: the strip uses the one usage form',summary)

 bar.pause:Click()
 C.setup(M.Status().state=='PAUSED','F2: the strip Pause paused the run')
 local before=Effects()
 bar.pause:Click();Direct(bar.pause);Direct(bar.pause)
 C.expect(M.Status().state=='PAUSED' and Same(before,Effects()),'F2: repeated Pause leaves the run paused and does nothing')
 C.expect(bar.pause:GetText()=='Pause' and bar.resume:GetText()=='Resume','F2: labels never change')
 H.Offer();bar.refresh()
 C.expect(H.Count('take')==0 and bar.resume:IsEnabled(),'F2: a paused offer is not selected; Resume is offered')
 bar.resume:Click()
 C.expect(M.Status().running and H.Count('take')==1 and M.Status().limit==3,'F2: the strip Resume continues once with the same maximum')
 Direct(bar.resume)
 C.expect(H.Count('take')==1 and H.Count('orb-spend')==1,'F2: a repeated Resume does nothing more')
end)

C.scenario('F3 a finished run: Start new run returns with its two steps; the mini panel is unchanged',function()
 Fresh()
 H.OrbPlan(PLAN)
 H.Approve(1,false);H.Offer();H.Result(410002,2)
 C.setup(M.Status().state=='FINISHED','F3: the settled maximum finished the run')
 local f=UI.Show()
 C.guard(f.start:IsShown() and f.start:GetText()=='Start new run','F3: Start new run is offered')
 C.expect(not f.pause:IsShown() and not f.resume:IsShown(),'F3: no Pause or Resume once the run is finished')
 C.expect(f.usage:GetText()=='Orbs used: 1 / 1 approved','F3: the finished usage in the one form',f.usage:GetText())
 local spends=H.Count('orb-spend')
 f.start:Click()
 C.guard(f.start:GetText()=='Confirm new run' and H.Count('orb-spend')==spends,'F3: the first press only arms the review')
 f:Hide();UI.Show()
 C.guard(f.start:GetText()=='Start new run' and H.Count('orb-spend')==spends,'F3: closing cancels it and starts nothing')
 C.guard(M.Status().resumeTarget==nil and M.CompactStatus().resumeTarget==nil,'F3: a finished run has no Resume target')
 local mini=UI.ShowMini()
 C.guard(mini.usage:GetText()=='Orbs used: 1 of 1 approved','F3: the mini panel keeps its usage form')
 local function P(b) return X(b),Y(b),b:GetWidth() end
 local x,y,w=P(mini.pause);local ok=x==12 and y==-164 and w==66
 x,y,w=P(mini.resume);ok=ok and x==84 and y==-164 and w==74
 x,y,w=P(mini.stop);ok=ok and x==164 and y==-164 and w==60
 C.guard(ok,'F3: the mini Pause, Resume and Stop keep their places and sizes')
 C.guard(not mini.pause:IsEnabled() and not mini.resume:IsEnabled() and not mini.stop:IsEnabled(),'F3: the finished mini panel offers no run action')
end)

C.finish('real Orb window/strip/mini handlers and OrbRuntime; synthetic services; no native double-click claim')
