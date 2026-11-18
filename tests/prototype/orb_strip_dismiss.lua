-- #167: the attached main-panel Orb strip (NexusPanel._orbControls) of a
-- settled finished run can be hidden on its own, without hiding Nexus. The
-- Hide is presentation only and session-only: the same run stays hidden on
-- every ticker refresh and panel re-render; a different run (even with the
-- same numbers), or any active, pending, paused or unresolved state, is shown.
-- A stale click never hides a replacement run. A run that ended with unknown
-- outcomes keeps its strip. Nothing is spent, chosen, saved, reset or
-- released by it.
-- Categories (view_regression_support): EXPECT marks behaviour introduced
-- with its check, GUARD marks earlier behaviour that must keep holding, and
-- SETUP marks the fixture.
-- Oracles: the real strip created by Nexus.Panel.Show (UI.AttachMainPanel),
-- its OnUpdate ticker through H.Advance and its button handlers, the real
-- OrbRuntime, and spend, take, send and action counters with the saved data.
-- Synthetic services only. Not a native click, pixel or font-scale proof.
local V=dofile('tests/prototype/view_regression_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local C=V.Checker('orb_strip_dismiss')
local H,M,A,O,UI
-- More copies wanted than one run obtains: the run ends at its limit with
-- target copies still remaining, as in the reported screenshot.
local PLAN={{spellId=410002,quality=2,stacks=14}}
local CARDS={{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410008,quality=1}}

local function Fresh()
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 Nexus=nil;NexusDB=nil;NexusSupportDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil;NexusPanel=nil
 H=dofile('tests/prototype/orbs_support.lua');M,A,O=H.M,H.A,H.O;UI=Nexus.OrbPanel
 UIParent:SetSize(1920,1080)
 H.OrbPlan(PLAN)
end
-- Fresh safe surplus copies, so every replacement really has a source.
local function Sources()
 H.granted={['Disposable A']={},['Disposable B']={}}
 for _=1,6 do
  table.insert(H.granted['Disposable A'],{spellId=410001,quality=1})
  table.insert(H.granted['Disposable B'],{spellId=410003,quality=0})
 end
 O.charges=20;H.Notify();A.Poll()
end
-- The same steps as H.Approve, H.Offer and H.Result, through the current
-- runtime M: those helpers keep the module loaded with orbs_support, and D5
-- loads fresh runtime owners.
local function StartRun(n)
 Sources()
 assert(M.SetLimit(n));assert(M.SetRecycle(false));assert(M.SuggestSources())
 local p,err=M.Prepare('auto');assert(p,err)
 local ok,e=M.Confirm(p.token);assert(ok,e)
end
local function NextOffer()
 for _=1,20 do if M.Status().state=='WAIT_OFFER' then break end M.Pump() end
 H.Offer(CARDS);M.Pump()
end
local function Settle(n) for _=1,n do NextOffer();H.Result(410002,2);M.Pump() end end
local function FinishRun(n) StartRun(n);Settle(n);return M.Status().state=='FINISHED' end
local function Strip()
 Nexus.Panel.Show();H.Advance(.3)
 return NexusPanel and NexusPanel._orbControls
end
local function Direct(b) return b:GetScript('OnClick')(b) end
local function Has(fs,s) return (fs:GetText() or ''):find(s,1,true)~=nil end
local function X(r) local p={r:GetPoint(1)};return type(p[2])=='number' and p[2] or p[4] end
local function Y(r) local p={r:GetPoint(1)};return type(p[2])=='number' and p[3] or p[5] end
-- Everything a presentation-only Hide must leave as it was.
local function Effects()
 local s=M.Status();local log=M.RunLog('current',1,0)
 return {spend=H.Count('orb-spend'),take=H.Count('take'),actions=#H.actions,sent=#H.sent,
  orb=F.Serialize(Nexus.Store.State().orbRefinement),db=F.Serialize(NexusDB),
  state=s.state,spent=s.spent,reserved=s.reserved,limit=s.limit,running=s.running,pending=s.pending,
  canStart=s.canStart,remaining=M.CompactStatus().remaining,auto=Nexus.RecomputeStats().autoEnabled,
  blocks=M.BlocksOrdinary(),runId=log.runId,total=log.total,revision=log.revision}
end
local function Diff(a,b)
 for k,v in pairs(a) do if b[k]~=v then return k..': '..tostring(v)..' -> '..tostring(b[k]) end end
end

C.scenario('D1 a settled finished strip offers Hide; only the strip hides, and it stays hidden',function()
 Fresh()
 C.setup(FinishRun(1),'D1: the run finished at its limit',M.Status().state)
 local bar=Strip()
 C.setup(bar and bar:IsVisible(),'D1: the attached strip is shown below the main panel')
 C.guard(Has(bar.summary,'Finished - limit reached'),'D1: the strip shows the finished run truthfully',bar.summary:GetText())
 -- Independent Spec review of 24a40301: the attached strip is a surface the main panel owns, so it draws no run count (counts only inside expanded Details).
 -- The usage and the remaining copies are its hover.
 local d1Whole=tostring(bar.summary._nexusFullText or '')
 C.expect(not bar.summary:GetText():find('%d') and d1Whole:find('Orbs used: 1 / 1 approved',1,true)~=nil
  and d1Whole:find('target copies remaining',1,true)~=nil and d1Whole:find('Finished - limit reached',1,true)~=nil,
  'D1: the strip draws no count; its hover keeps the usage and the remaining copies',bar.summary:GetText()..' / '..d1Whole)
 C.guard(not bar.pause:IsEnabled() and not bar.resume:IsEnabled() and not bar.stop:IsEnabled(),
  'D1: a finished run offers no run action')
 C.expect(bar.dismiss~=nil and bar.dismiss:IsVisible() and bar.dismiss:IsEnabled()
  and bar.dismiss:GetText()=='Hide until next run','D1: a Hide control is shown on the strip itself')
 C.expect(not bar.pause:IsShown() and not bar.resume:IsShown() and not bar.stop:IsShown(),
  'D1: it takes the place of the disabled Pause, Resume and Stop')
 C.guard(bar.details:IsVisible() and bar.details:IsEnabled(),'D1: Details stays')
 C.expect(X(bar.dismiss)>=8 and Y(bar.dismiss)==Y(bar.details)
  and X(bar.dismiss)+bar.dismiss:GetWidth()+6<=X(bar.details)
  and #'Hide until next run'*7.0+20<=bar.dismiss:GetWidth(),
  'D1: it sits on the action row, apart from Details, and its label fits the 7 px model')
 local before=Effects()
 bar.dismiss:Click()
 C.expect(not bar:IsShown(),'D1: Hide hides the strip')
 C.guard(NexusPanel:IsShown(),'D1: the main panel stays shown')
 H.Advance(2);bar.refresh()
 C.expect(not bar:IsShown(),'D1: the ticker and a direct refresh keep the same run hidden')
 Nexus.Panel.Hide();Nexus.Panel.Show();H.Advance(.5)
 C.expect(not bar:IsShown() and NexusPanel._orbControls==bar,'D1: re-showing the main panel keeps it hidden')
 local after=Effects()
 C.expect(Diff(before,after)==nil,'D1: Hide spends, chooses, saves and changes nothing',Diff(before,after))
 local f=UI.Show()
 C.guard(Has(f.usage,'1 / 1'),'D1: the full window still reports the usage',f.usage:GetText())
end)

C.scenario('D2 a new run with the same numbers is shown again',function()
 Fresh()
 C.setup(FinishRun(1),'D2: the first run finished')
 local bar=Strip()
 C.setup(bar and bar.dismiss~=nil,'D2: the strip and its Hide exist')
 local first=bar.summary:GetText()
 bar.dismiss:Click()
 C.setup(not bar:IsShown(),'D2: the first run is hidden')
 StartRun(1);H.Advance(.3)
 C.expect(bar:IsShown() and not bar.dismiss:IsShown() and bar.pause:IsShown(),
  'D2: an approved new run is shown with its actions and no Hide')
 Settle(1);H.Advance(.3)
 C.setup(M.Status().state=='FINISHED','D2: the new run finished with the same numbers')
 C.expect(bar:IsShown() and bar.summary:GetText()==first,'D2: the new finished run is shown, though its text is identical',bar.summary:GetText())
 C.expect(bar.dismiss:IsShown(),'D2: and can be hidden in its own turn')
 bar.dismiss:Click()
 C.expect(not bar:IsShown(),'D2: Hide hides the new run')
 -- A whole run starts and finishes while the main panel is closed, so the
 -- strip never sees it running: same state, same numbers, another run.
 Nexus.Panel.Hide()
 C.setup(FinishRun(1),'D2: a third run finished while the panel was closed')
 Nexus.Panel.Show();H.Advance(.3)
 C.expect(bar:IsShown() and bar.summary:GetText()==first and bar.dismiss:IsShown(),
  'D2: it is shown, though the strip never saw it running',bar.summary:GetText())
end)

C.scenario('D3 a stale Hide click never hides a replacement run',function()
 Fresh()
 C.setup(FinishRun(1),'D3: the first run finished')
 local bar=Strip()
 C.setup(bar and bar.dismiss and bar.dismiss:IsShown(),'D3: Hide is offered for it')
 -- A new run is approved before the strip refreshes again; the click that
 -- was aimed at the finished run arrives late.
 StartRun(1)
 local before=Effects()
 Direct(bar.dismiss);bar.refresh()
 C.expect(bar:IsShown(),'D3: a late click does not hide the running replacement')
 C.expect(Diff(before,Effects())==nil,'D3: and changes nothing about it',Diff(before,Effects()))
 Settle(1);H.Advance(.3)
 C.setup(M.Status().state=='FINISHED' and bar.dismiss:IsShown(),'D3: that run finished and offers Hide')
 -- The next run finishes with the same numbers without a strip refresh in
 -- between: a click aimed at the earlier run must not hide this one.
 C.setup(FinishRun(1),'D3: a third run finished unseen')
 Direct(bar.dismiss);bar.refresh()
 C.expect(bar:IsShown(),'D3: a click aimed at an earlier finished run does not hide a later one')
end)

C.scenario('D4 work that needs attention is never hidden',function()
 Fresh()
 StartRun(2)
 local bar=Strip()
 C.setup(bar and bar:IsShown() and M.Status().running,'D4: a running run is shown')
 C.expect(bar.dismiss and not bar.dismiss:IsShown(),'D4: no Hide while running')
 local before=Effects()
 Direct(bar.dismiss);bar.refresh();H.Advance(.3)
 C.expect(bar:IsShown() and Diff(before,Effects())==nil,'D4: a direct click hides and changes nothing',Diff(before,Effects()))
 NextOffer();H.Advance(.3)
 C.setup(M.Status().pending,'D4: the submitted Orb is not settled yet')
 C.expect(bar:IsShown() and not bar.dismiss:IsShown(),'D4: no Hide while an Orb is pending')
 Direct(bar.dismiss);bar.refresh()
 C.expect(bar:IsShown(),'D4: a pending Orb is never hidden')
 bar.pause:Click();H.Advance(.3)
 C.setup(M.Status().state=='PAUSED','D4: the run is paused')
 Direct(bar.dismiss);bar.refresh()
 C.expect(bar:IsShown() and not bar.dismiss:IsShown(),'D4: a paused run is never hidden')
 bar.stop:Click();H.Advance(.3)
 C.setup(M.Status().state=='STOPPED' and M.Status().pending,'D4: Stop leaves the submitted Orb unresolved')
 Direct(bar.dismiss);bar.refresh()
 C.expect(bar:IsShown() and not bar.dismiss:IsShown(),'D4: a stopped run with an unresolved Orb is never hidden')
 H.Result(410002,2);H.Advance(.3)
 C.setup(M.Status().state=='STOPPED' and not M.Status().pending,'D4: the result settled passively')
 C.expect(bar:IsShown() and bar.dismiss:IsShown(),'D4: a settled stopped run can be hidden')
 -- A restored unresolved receipt after a reload: fresh owners, passive recovery.
 Fresh()
 StartRun(2);NextOffer()
 H.Fire('PLAYER_LOGOUT')
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:Hide() end
 assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
 assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
 M=Nexus.OrbRuntime;H.M=M
 bar=Strip()
 C.setup(M.Status().state=='RECOVERY' and M.Status().pending,'D4: the receipt restored in passive recovery')
 C.expect(bar and bar:IsShown() and not bar.dismiss:IsShown(),'D4: an unresolved recovery is shown without Hide')
 Direct(bar.dismiss);bar.refresh()
 C.expect(bar:IsShown(),'D4: and a click cannot hide it')
end)

C.scenario('D5 the Hide does not outlive its run or its runtime',function()
 Fresh()
 C.setup(FinishRun(1),'D5: the run finished')
 local bar=Strip()
 local hooks=0
 for _ in pairs(NexusPanel.scripts) do hooks=hooks+1 end
 bar.dismiss:Click()
 C.setup(not bar:IsShown(),'D5: the run is hidden')
 C.guard(UI.AttachMainPanel(NexusPanel)==bar,'D5: attaching again returns the one strip')
 local after=0
 for _ in pairs(NexusPanel.scripts) do after=after+1 end
 C.guard(after==hooks,'D5: and adds no second ticker')
 -- Fresh runtime owners (a reload's run state) while the main panel is
 -- closed, so the strip never sees the idle state in between. Run ids
 -- start again; the first new run carries the same id and numbers.
 Nexus.Panel.Hide()
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:Hide() end
 assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
 assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
 M=Nexus.OrbRuntime;H.M=M
 H.OrbPlan(PLAN)
 C.setup(FinishRun(1),'D5: a run of the fresh runtime finished',M.Status().state..' '..tostring(M.Status().reason)..' spends='..H.Count('orb-spend'))
 C.setup(M.RunLog('current',1,0).runId==1,'D5: its run id starts again')
 Nexus.Panel.Show();H.Advance(.3)
 C.expect(bar:IsShown() and bar.dismiss:IsShown(),'D5: the fresh runtime\'s run is shown')
end)

-- The bounded-recovery setup of orb_bounded_recovery: real Start, real
-- adapter and a quiet synthetic server, so both attempts' outcomes stay
-- unknown and the run ends at its maximum with that exposure retained. Its
-- matched control is the same Start with both results arriving normally.
local RS=dofile('tests/prototype/orb_recovery_support.lua')
local function RecoveryFresh(limit)
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 NexusSupportDB=nil;NexusPanel=nil
 H,M,A,O=RS.S.Fresh();UI=Nexus.OrbPanel
 UIParent:SetSize(1920,1080)
 RS.S.Loadouts(H,A);H.perks.currentChoice={}
 assert(M.Start(limit))
end
local function QuietServer()
 local server=RS.Server(H)
 H.service.RequestChoice=function()
  SendAddonMessage(RS.PREFIX,'16','WHISPER',RS.ME);server.queue[#server.queue+1]={op=16,body=''}
 end
end
local function WaitFor(predicate,seconds)
 for _=1,(seconds or 30)*4 do if predicate() then return true end;H.Advance(.25) end
 return predicate()
end

C.scenario('D6 a finished run with unknown outcomes stays shown; its matched settled control can hide',function()
 -- Control: the same setup and maximum, both results observed.
 RecoveryFresh(2)
 H.Offer();H.Result(410002,2)
 C.setup(WaitFor(function()return H.Count('orb-spend')==2 end),'D6 control: the run spends its second approved Orb')
 H.Offer();H.Result(410002,2);H.Advance(2)
 local s=M.CompactStatus()
 C.setup(s and (s.state=='COMPLETE' or s.state=='FINISHED') and not s.pending and s.uncertain==0
  and (s.unconfirmedResults or 0)==0,'D6 control: the run settled with both outcomes observed',s and s.state)
 local bar=Strip()
 C.expect(bar and bar:IsShown() and bar.dismiss:IsShown(),'D6 control: a settled run without unknown outcomes offers Hide')
 bar.dismiss:Click()
 C.expect(not bar:IsShown(),'D6 control: and Hide hides it')

 RecoveryFresh(2);QuietServer()
 C.setup(WaitFor(function()return M.Status().state=='FINISHED' end,45),'D6: unknown exposure reaches the approved maximum')
 s=M.CompactStatus()
 C.setup(not s.pending and not s.running and s.reserved==0 and s.spent==0 and s.uncertain==2
  and s.unconfirmedResults==2 and s.remaining==2,'D6: settled-looking, with two unknown outcomes retained',
  s.uncertain..'/'..tostring(s.unconfirmedResults)..'/'..tostring(s.remaining))
 bar=Strip()
 -- The exposure is said in words on the strip; its count is the hover.
 C.setup(bar and Has(bar.summary,'spend not confirmed') and not bar.summary:GetText():find('%d')
  and tostring(bar.summary._nexusFullText):find('unknown spend exposure: 2',1,true)~=nil,
  'D6: the strip discloses the exposure in words and its hover the count',bar and bar.summary:GetText())
 C.expect(bar:IsShown() and not bar.dismiss:IsShown(),'D6: a run with unknown outcomes is shown without Hide')
 C.guard(bar.pause:IsShown() and bar.stop:IsShown() and not bar.stop:IsEnabled(),'D6: the row keeps its disabled actions')
 local before=Effects()
 local archive=F.Serialize(RS.SavedRow('orbRecoveryArchive'))
 Direct(bar.dismiss);bar.refresh();H.Advance(1)
 C.expect(bar:IsShown(),'D6: a direct Hide click does not hide it')
 C.expect(Diff(before,Effects())==nil and F.Serialize(RS.SavedRow('orbRecoveryArchive'))==archive,
  'D6: and changes no usage, limit, history, receipt or saved data',Diff(before,Effects()))
end)

C.finish('real attached strip, ticker and OrbRuntime; synthetic services; no native click or scale claim')
