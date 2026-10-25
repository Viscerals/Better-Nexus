-- M7 (Root condition restoredPaused; M6 NB-3, NB-4, NB-11, D9): the Orb window
-- states an unresolved record in one vocabulary.
--  * A restored record the runtime keeps PAUSED reads in the same layers as
--    RECOVERY (what it blocks, what the player can do now, the details) under
--    its own "Paused - ..." label. It stays PAUSED; its history, receipt,
--    Continue, limit, authorization and spend gates are unchanged.
--  * Where Continue is offered, the headline says the result blocks until it
--    settles or the player continues past it.
--  * A restored receipt without its approved maximum keeps the configured
--    fallback as its gate, but no surface names that fallback as approved.
--  * The current run's history pairs its live usage with the state recorded at
--    its last event; when the run moved on (Pause records no event) the header
--    says both, and the copied report uses the same usage words.
-- Categories (view_regression_support): EXPECT is behaviour added in M7
-- (predicted to fail on accepted M6 0924d06a; not executed by the author);
-- GUARD already holds there and must keep holding; SETUP is the fixture.
-- Oracles: the real Orb window, strip, mini panel and history page, the real
-- OrbRuntime reads, the OrbHistory projection, the saved receipt, and the
-- spend and send counters. The receipt without a recorded maximum is the
-- reported restored class with its saved `limit` removed before the reload
-- (a SYNTHETIC genuine-shaped older receipt). Real Store/OrbRuntime/OrbAdapter;
-- synthetic game services only. No native recovery or reload claim.
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('orb_recovery_vocabulary')
local R=dofile('tests/prototype/orb_recovery_support.lua')
local HEADLINE='Previous result is unresolved: no new Orb run or ordinary roll until it settles.'
local HEADLINE_CONTINUE='Previous result is unresolved: no new Orb run or ordinary roll until it settles or you continue past it.'
local PAUSED_CONTINUE='Paused - a result restored after a reload is unresolved: no new Orb run or ordinary roll until it settles or you continue past it.'
local function Lines(text) local out={};for l in (text..'\n'):gmatch('(.-)\n') do out[#out+1]=l end;return out end
local function Has(text,needle) return tostring(text or ''):find(needle,1,true)~=nil end
local function Fresh()
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 Nexus=nil;NexusDB=nil;NexusSupportDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil;NexusPanel=nil
 local H=dofile('tests/prototype/orbs_support.lua')
 UIParent:SetSize(1920,1080)
 return H,H.M,H.A,H.O
end

C.scenario('W1 a restored record kept PAUSED reads in layers under its own label; nothing else changes',function()
 local H,M,A=R.Class();R.Server(H);R.S.Pass(H,M,A,2)
 local s=M.Status();local cv=M.ContinueView()
 C.setup(s.state=='PAUSED' and s.pending and s.recovery and s.recovery.kind=='PAUSED' and cv.eligible==true,
  'W1: fixture: the restored record with the loadout hold is paused and eligible for Continue',s.state)
 local saved=H.Clone(R.Saved());local sent,spend=#H.sent,H.Count('orb-spend')
 local recovery=H.Clone(M.RecoveryView())
 SlashCmdList.NEXUS('orbs');local f=assert(NexusOrbPanel);H.Advance(.5)
 Nexus.OrbPanel.Refresh()
 s=M.Status()
 local text=f.status:GetText() or '';local lines=Lines(text)
 print('OBSERVED','W1 status='..text)
 C.expect(lines[1]==PAUSED_CONTINUE,'W1: the headline says Paused, what is blocked and that Continue is a way on',lines[1])
 C.expect(lines[2]=='What you can do: Continue... below checks the game, then asks you to confirm.','W1: what the player can do comes second',lines[2])
 C.expect(text==lines[1]..'\n'..lines[2]..'\nDetails: '..s.reason,'W1: the runtime reason follows whole as the details',text)
 C.guard(not Has(text,'Resume would use') and not Has(text,'Resume uses'),'W1: no Resume target is guessed',text)
 C.guard(M.Status().state=='PAUSED' and M.Status().recovery and M.Status().recovery.kind=='PAUSED','W1: it stays PAUSED; it is not turned into RECOVERY')
 C.guard(f.cont:IsShown() and f.cont:GetText()=='Continue...' and not f.resume:IsEnabled() and M.BlocksOrdinary(),
  'W1: Continue stays the explicit way on; no Resume; ordinary rolling stays blocked')
 C.guard(R.Same(R.Saved(),saved) and #H.sent==sent and H.Count('orb-spend')==spend,'W1: the receipt is unchanged; nothing was sent or spent')
 local after=M.RecoveryView()
 C.guard(after.state==recovery.state and after.recovery==recovery.recovery and after.restored==recovery.restored,
  'W1: the recovery view is unchanged by the display',tostring(after.state)..'/'..tostring(after.recovery))
end)

C.scenario('W2 the headline names continuing only where Continue is offered',function()
 local H,M,A=R.Class({latch=false});R.Server(H);R.S.Pass(H,M,A,2)
 local cv=M.ContinueView()
 C.setup(M.Status().state=='RECOVERY' and cv.eligible==true,'W2: fixture: an eligible restored record in RECOVERY',M.Status().state)
 SlashCmdList.NEXUS('orbs');local f=assert(NexusOrbPanel);H.Advance(.5);Nexus.OrbPanel.Refresh()
 local first=Lines(f.status:GetText() or '')[1]
 C.expect(first==HEADLINE_CONTINUE,'W2: with Continue offered, the result blocks until it settles or you continue past it',first)
 C.guard(Has(first,'Previous result is unresolved: no new Orb run or ordinary roll until it settles'),'W2: the blocking clause is kept',first)
 -- The unobservable class has no Continue: the headline says settling only.
 H,M,A=R.Class({latch=false,edit=function(row,state)row.spendConfirmed=false;state.spendConfirmed=false end})
 R.S.Pass(H,M,A,1)
 H.granted[H.names[500001]]={{spellId=500001,quality=1}};H.Notify();A.Poll();M.Pump()
 cv=M.ContinueView()
 C.setup(M.RecoveryView().recovery=='UNOBSERVABLE' and cv.eligible~=true,'W2: fixture: the unobservable record offers no Continue')
 Nexus.OrbPanel.Show();Nexus.OrbPanel.Refresh()
 first=Lines(NexusOrbPanel.status:GetText() or '')[1]
 C.guard(first==HEADLINE,'W2: without Continue the headline says it blocks until it settles',first)
end)

C.scenario('W3 a restored receipt without its approved maximum: the fallback gates it, no surface calls it approved',function()
 local configured
 local H,M,A=R.Class({latch=false,edit=function(row,state)row.limit=nil;state.limit=nil end})
 R.Server(H);R.S.Pass(H,M,A,2)
 local s=M.Status()
 local sent,spend=#H.sent,H.Count('orb-spend')
 configured=s.config and s.config.maxOrbs
 C.setup(s.pending and (s.state=='RECOVERY' or s.state=='PAUSED'),'W3: fixture: the restored receipt without a saved limit is held',s.state)
 C.guard(s.limit==(configured or 0),'W3: its gate is the configured fallback, as before',tostring(s.limit)..' vs '..tostring(configured))
 C.expect(s.limitKnown==false and M.CompactStatus().limitKnown==false,'W3: the reads say the approved maximum is not recorded',tostring(s.limitKnown))
 SlashCmdList.NEXUS('orbs');local f=assert(NexusOrbPanel);H.Advance(.5);Nexus.OrbPanel.Refresh()
 local usage=f.usage:GetText() or ''
 print('OBSERVED','W3 usage='..usage)
 C.expect(Has(usage,'maximum not recorded') and not Has(usage,'approved'),'W3: the window says the maximum is not recorded',usage)
 Nexus.Panel.Show();H.Advance(.3)
 local bar=NexusPanel and NexusPanel._orbControls
 if bar then bar.refresh() end
 local first=bar and Lines(bar.summary:GetText() or '')[1] or ''
 C.expect(Has(first,'max not recorded') and not Has(first,'approved'),'W3: the strip says so',first)
 local mini=Nexus.OrbPanel.ShowMini()
 C.expect(Has(mini.usage:GetText(),'(maximum not recorded)') and not Has(mini.usage:GetText(),'approved'),'W3: the mini panel says so',mini.usage:GetText())
 mini:Hide()
 C.guard(H.Count('orb-spend')==spend and M.Status().limit==s.limit,'W3: the display spent nothing and changed no gate',H.Count('orb-spend'))
 C.setup(#H.sent>=sent,'W3: (passive recovery reads may request read-only refreshes)',#H.sent-sent)
end)

C.scenario('W4 a receipt with its maximum keeps the approved form',function()
 local H,M,A=R.Class({latch=false});R.Server(H);R.S.Pass(H,M,A,2)
 local s=M.Status()
 C.setup(s.pending,'W4: fixture: a restored receipt with its saved limit')
 C.expect(s.limitKnown==true,'W4: its approved maximum is known',tostring(s.limitKnown))
 SlashCmdList.NEXUS('orbs');local f=assert(NexusOrbPanel);H.Advance(.5);Nexus.OrbPanel.Refresh()
 C.guard(Has(f.usage:GetText(),s.limit..' approved'),'W4: the window keeps "N approved"',f.usage:GetText())
end)

C.scenario('W5 history: the live state beside the recorded one; the same usage words in the report',function()
 local H,M=Fresh()
 H.OrbPlan({{spellId=410002,quality=2,stacks=3}})
 C.setup(M.Start(3) and M.Status().reserved==1,'W5: an approved run with one requested Orb')
 H.Offer();C.setup(M.Pause(),'W5: the run is paused (Pause records no history event)')
 local view=M.RunLog('current')
 C.setup(view.runId~=nil and M.Status().state=='PAUSED','W5: fixture: the current run has history',tostring(view.state))
 print('OBSERVED','W5 recorded state='..tostring(view.state)..' live='..tostring(view.liveState))
 local history=Nexus.OrbHistory
 if view.state~='PAUSED' then
  C.expect(view.liveState=='PAUSED','W5: the view carries the live state apart from the recorded one',tostring(view.liveState))
  local header=history.Header(view)
  C.expect(Has(header.status,'Now: Paused') and Has(header.status,'last recorded:'),'W5: the header says the current and the last recorded state',header.status)
  local log=Nexus.OrbPanel.ShowLog()
  C.expect(Has(log.header:GetText(),'Now: Paused'),'W5: the history page shows it',log.header:GetText())
  log:Hide()
 else
  C.setup(true,'W5: (the runtime recorded the pause; nothing to pair)')
 end
 local report=history.Report(view,nil,false)
 C.expect(Has(report,'; Orbs used: ') and Has(report,'pending (requested, not confirmed): '),'W5: the report uses the Orb usage words',report)
 C.expect(not Has(report,'confirmed usage') and not Has(report,'unresolved exposure'),'W5: the older words are gone',report)
 C.guard(Has(report,'Approved maximum: 3') and Has(report,'Stopping state: '),'W5: the approved maximum and the stopping state are kept',report)
 C.guard(history.Header({runId=1,spent=14,limit=15,reserved=0,state='FINISHED'}).status=='Finished - Orb limit reached',
  'W5: a log with no live state keeps its recorded state alone')
 C.guard(H.Count('orb-spend')==1,'W5: reading the history spent nothing more')
end)

C.finish('real Orb windows, strip, mini and history; synthetic services; no native recovery claim')
