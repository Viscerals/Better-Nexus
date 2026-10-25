-- M6 (UX-16 / LP-16): an unresolved earlier Orb result reads in layers in the
-- Orb window. First what it blocks, then what the player can do now (the
-- Continue state actually shown), then the runtime's own reason, unshortened,
-- so recorded Echo names and earlier facts stay exact. Usage reads in one form
-- on the window, strip, mini panel and history. The Continue window says when
-- the session history before a reload is gone. Help gives reload advice by
-- state: no universal reload fix, no retry, refund, deletion or automatic
-- continuation.
-- Categories (view_regression_support): EXPECT marks behaviour introduced
-- with its check, GUARD marks earlier behaviour that must keep holding, and
-- SETUP marks the fixture.
-- F1 successor against 752b91fe: L1b's former Paused+reason GUARD is
-- replaced by restored-record layer EXPECTs. Its strip pending/block EXPECT
-- also fails there; navigation, hover, geometry and action gates are GUARDs.
-- Oracles:
--  * the real Orb window, Continue window, strip, mini panel and history page;
--  * the real OrbRuntime (Status, ContinueView, RunLog, BlocksOrdinary);
--  * the Help pages and the runtime source as shipped;
--  * spend, send and saved-receipt checks.
-- Real Store/OrbRuntime/OrbAdapter/GameAdapter; synthetic game services only.
-- No native recovery, reload or historical-cause claim.
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('orb_recovery_layers')
local R=dofile('tests/prototype/orb_recovery_support.lua');local S=R.S
local HEADLINE='Previous result is unresolved: no new Orb run or ordinary roll until it settles.'

local function Lines(text) local out={};for l in (text..'\n'):gmatch('(.-)\n') do out[#out+1]=l end;return out end
local function Fresh()
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 Nexus=nil;NexusDB=nil;NexusSupportDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil;NexusPanel=nil
 local H=dofile('tests/prototype/orbs_support.lua')
 UIParent:SetSize(1920,1080)
 return H,H.M,H.A,H.O
end
-- The second reported RDF case (orb_rdf_recovery_followups): Nexus's choice was
-- sent and observed, then a loading screen lost the game's reply.
local function LostReply()
 local H,M,A,O=Fresh()
 H.perks.serverBuildSlots={[1]={name='One',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}},
  [2]={name='Two',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}}}
 H.perks.serverActiveSlot=1;H.Notify();A.Poll()
 assert(A.SetLoadoutWishlistIdentity(1,'First',{{spellId=410002,quality=2,stacks=2}}))
 assert(M.Start(3))
 H.Offer();H.Advance(.5)
 local r=Nexus.Store.State().orbRefinement.pending
 C.setup(r and r.spendConfirmed and r.choiceObserved and r.selectedKey=='410002:2','fixture: confirmed spend, choice sent and observed')
 H.Fire('PLAYER_LEAVING_WORLD');H.Advance(.5);H.Fire('PLAYER_ENTERING_WORLD')
 return H,M,A,O
end
local function Reload(H)
 H.Fire('PLAYER_LOGOUT')
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 H.perks.pendingSelectSpellId=nil
 assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
 assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
 return Nexus.OrbRuntime
end
-- The layered status: headline, the action line, then exactly the reason. The
-- window is refreshed and the runtime read at the same moment.
local function Layered(f,M,label)
 Nexus.OrbPanel.Refresh()
 local s=M.Status()
 local text=f.status:GetText();local lines=Lines(text)
 C.expect(lines[1]==HEADLINE,label..': what is blocked comes first',lines[1])
 C.expect(lines[2] and lines[2]:find('^What you can do: ')~=nil,label..': what the player can do comes second',lines[2])
 C.expect(text==lines[1]..'\n'..lines[2]..'\nDetails: '..s.reason,label..': the runtime reason follows as the details, unchanged',text)
 C.guard(f.status._nexusFullText==nil,label..': nothing in the status was shortened')
 return lines
end

-- The eligible class with the original slot still live (latch=false): no
-- loadout hold in the receipt, so the restored record stays in RECOVERY. The
-- default R.Class() keeps the reported loadout hold and is paused by it; L1b
-- covers that record.
C.scenario('L1 eligible restored record: layered status; Continue stays explicit; cleared history said',function()
 local H,M,A,O=R.Class({latch=false});R.Server(H);S.Pass(H,M,A,2)
 local receipt=R.Saved()
 C.setup(receipt and receipt.spendConfirmed and receipt.loadoutChanged==nil and receipt.originalSlot==H.perks.serverActiveSlot,
  'L1: fixture: the saved receipt holds no loadout hold and its slot is the live one')
 local s=M.Status();local cv=M.ContinueView()
 C.setup(s.state=='RECOVERY' and s.pending and cv.eligible==true,'L1: a restored record eligible for Continue',s.state)
 local saved=H.Clone(R.Saved());local sent=#H.sent
 SlashCmdList.NEXUS('orbs');local f=assert(NexusOrbPanel);H.Advance(.5)
 local lines=Layered(f,M,'L1')
 C.expect(lines[2]=='What you can do: Continue... below checks the game, then asks you to confirm.','L1: the action names the eligible Continue',lines[2])
 C.guard(f.cont:IsShown() and f.cont:GetText()=='Continue...','L1: the Continue button is the one named')
 C.guard(M.BlocksOrdinary(),'L1: ordinary rolling is blocked, as the headline says')
 f.cont:Click();local w=assert(NexusOrbContinue);H.Advance(.5)
 C.setup(M.RunLog('current').runId==nil,'L1: fixture: this session has no run history')
 C.expect(w.history:GetText()==Nexus.OrbHistory.RELOAD_CLEARED_NOTE,'L1: the Continue window says the earlier steps are not listed',w.history:GetText())
 C.guard(w.body:GetText()==M.ContinueView().text and #w.body:GetText()<1500,'L1: the Continue explanation itself is the runtime text, bounded')
 C.guard(w.check:IsEnabled() and not w.go:IsEnabled(),'L1: Continue still needs its read-only check and an explicit confirmation')
 C.guard(#H.sent==sent and H.Count('orb-spend')==0 and R.Same(R.Saved(),saved),'L1: reading and opening sent, spent and changed nothing')
 w:Hide()
end)

-- The reported class as built (R.Class() default): its saved receipt keeps the
-- loadout hold, so the passive recovery read pauses it (the original loadout
-- cannot be verified). It is still eligible for an explicit Continue
-- (orb_recovery_continue). A restored record has no assignment to compare, so
-- no Resume target is guessed for it.
C.scenario('L1b loadout-uncertain restored record: paused, no guessed target, nothing retried',function()
 local H,M,A,O=R.Class();R.Server(H);S.Pass(H,M,A,2)
 local receipt=R.Saved()
 local s=M.Status();local cv=M.ContinueView()
 C.setup(receipt and receipt.loadoutChanged==true and s.state=='PAUSED' and s.pending and s.recovery and s.recovery.kind=='PAUSED' and cv.eligible==true,
  'L1b: the restored record with the loadout hold is paused and still eligible for Continue',s.state)
 C.guard(s.reason:find('original loadout cannot be verified',1,true)~=nil and s.reason:find('no retry is allowed',1,true)~=nil,
  'L1b: the runtime states the loadout uncertainty and that nothing is retried',s.reason)
 local saved=H.Clone(R.Saved());local sent=#H.sent
 SlashCmdList.NEXUS('orbs');local f=assert(NexusOrbPanel);H.Advance(.5)
 Nexus.OrbPanel.Refresh()
 s=M.Status();local c=M.CompactStatus()
 C.expect(s.resumeTarget and s.resumeTarget.kind=='blocked' and c.resumeTarget and c.resumeTarget.kind=='blocked',
  'L1b: Resume names nothing for a restored record, in the full and the compact read',s.resumeTarget and s.resumeTarget.kind)
 local lines=Layered(f,M,'L1b')
 C.expect(lines[2]=='What you can do: Continue... below checks the game, then asks you to confirm.',
  'L1b: the paused restored record names its actual explicit Continue action',lines[2])
 C.guard(cv.explanation==true and not s.running and not s.canResume and not c.canResume,
  'L1b: restored explanation is independent of the blocked Resume target')
 C.guard(f.cont:IsShown() and f.cont:GetText()=='Continue...' and not f.resume:IsEnabled() and M.BlocksOrdinary(),
  'L1b: Continue stays the explicit way on; no Resume; ordinary rolling stays blocked')
 local mini=Nexus.OrbPanel.ShowMini()
 C.guard(mini.state:GetText()=='Paused - a pending result must settle first' and not mini.resume:IsEnabled(),'L1b: the mini panel offers no Resume',mini.state:GetText())
 C.guard(mini.pending:GetText()=='Last Orb result is not settled' and s.spent>0 and s.reserved==0,
  'L1b: a spent unsettled action is not an unconfirmed request',mini.pending:GetText())
 local complete=mini.reason._nexusFullText or mini.reason:GetText()
 C.guard(complete==s.reason,'L1b: the mini retains the complete runtime reason',complete)
 local hovered,hoverOK=V.TooltipLines(function()mini.reasonHit:GetScript('OnEnter')(mini.reasonHit)end)
 C.guard(hoverOK and hovered[1]==s.reason,'L1b: actual mini hover exposes that complete reason',hovered[1])
 mini.reasonHit:GetScript('OnLeave')(mini.reasonHit)
 C.guard(f:GetWidth()==620 and f:GetHeight()==445 and f.status:GetWidth()==580 and f.status:GetHeight()==74
  and mini:GetWidth()==356 and mini:GetHeight()==196,'L1b: the existing full and mini geometry is retained')
 -- Supply font measurement only: the actual fixed-box tooltip owns the
 -- overflow decision and must expose the exact rendered text when needed.
 local measured=G.Rows(f.status:GetText(),f.status:GetWidth(),G.MODELS.px16.char)*G.MODELS.px16.line
 local realHeight=f.status.GetStringHeight
 f.status.GetStringHeight=function()return measured end
 local detail,detailOK=V.TooltipLines(function()f.statusHit:GetScript('OnEnter')(f.statusHit)end)
 f.status.GetStringHeight=realHeight
 C.guard(detailOK and (measured<=f.status:GetHeight() or detail[1]==f.status:GetText()),
  'L1b: overflow in the stated 16px model has actual full-status hover access',detail[1])
 f.statusHit:GetScript('OnLeave')(f.statusHit)
 f:Hide();C.setup(not f:IsVisible(),'L1b: the full window is closed before Open Orbs')
 mini.open:Click()
 C.guard(f:IsVisible() and f.cont:IsVisible() and f.cont:GetText()=='Continue...',
  'L1b: actual Open Orbs opens the full window and explicit Continue')
 Layered(f,M,'L1b Open Orbs')
 f:Hide();Nexus.Panel.Show();H.Advance(.3)
 local bar=NexusPanel and NexusPanel._orbControls
 C.setup(bar and bar:IsVisible() and not f:IsVisible(),'L1b: the real main panel shows its strip with the full window closed')
 bar.refresh()
 local strip=Lines(bar.summary._nexusFullText or bar.summary:GetText())
 C.expect(strip[2]=='Last Orb action is not settled' and strip[3]=='Paused - result must settle',
  'L1b: the strip shows a truthful generic pending/block cue without guessing Continue',bar.summary:GetText())
 C.guard(bar.details:IsVisible() and bar.details:GetText()=='Details' and not bar.resume:IsEnabled()
  and bar:GetHeight()==100 and bar.summary:GetHeight()==52,'L1b: existing Details, blocked Resume and strip geometry remain')
 bar.details:Click()
 C.guard(f:IsVisible() and f.cont:IsVisible() and f.cont:GetText()=='Continue...',
  'L1b: actual Details opens the full window and explicit Continue')
 Layered(f,M,'L1b Details')
 mini.resume:GetScript('OnClick')(mini.resume)
 C.guard(mini.notice:GetText()=='Not resumed: a pending result must settle.','L1b: a mini Resume that reaches the handler is refused',mini.notice:GetText())
 C.guard(not M.Resume(),'L1b: the runtime refuses Resume for the restored record')
 C.guard(#H.sent==sent and H.Count('orb-spend')==0 and R.Same(R.Saved(),saved) and M.Status().state=='PAUSED',
  'L1b: reading and the refused Resumes sent, spent and changed nothing')
 mini:Hide()
end)

C.scenario('L2 unobservable record: layered status keeps every earlier fact',function()
 local H,M,A,O=R.Class({latch=false,edit=function(row,state)row.spendConfirmed=false;state.spendConfirmed=false end})
 S.Pass(H,M,A,1)
 H.granted[H.names[500001]]={{spellId=500001,quality=1}};H.Notify();A.Poll();M.Pump()
 C.setup(M.RecoveryView().recovery=='UNOBSERVABLE' and M.Status().state=='RECOVERY','L2: the unobservable class is reached')
 local saved=H.Clone(R.Saved())
 Nexus.OrbPanel.Show()
 local f=NexusOrbPanel
 local lines=Layered(f,M,'L2')
 C.expect(lines[2]=='What you can do: follow the details; Why blocked... below explains this record.','L2: the action names the explanation shown',lines[2])
 C.guard(f.cont:IsShown() and f.cont:GetText()=='Why blocked...','L2: the explanation button is the one named')
 local text=f.status:GetText()
 C.guard(text:find('does not prove that the server spent nothing',1,true)~=nil and text:find('Nothing is retried, refunded or deleted',1,true)~=nil,
  'L2: no invented conclusion; never retried, refunded or deleted',text)
 C.guard(M.Status().pending and M.Status().reserved==1 and R.Same(R.Saved(),saved),'L2: the record and its exposure are kept')
end)

C.scenario('L3 recorded Echo after a reload: the exact name stays visible',function()
 local H,M,A,O=LostReply()
 H.Advance(2)
 M=Reload(H)
 H.Advance(1)
 local s=M.Status()
 C.setup(s.state=='RECOVERY' and s.recovery and s.recovery.gate and s.recovery.gate.gate=='offer','L3: the recorded offer is still open after the reload',s.state)
 C.setup(s.reason:find('Desired A',1,true)~=nil,'L3: fixture: the runtime reason names the recorded Echo',s.reason)
 local f=Nexus.OrbPanel.Show()
 local lines=Layered(f,M,'L3')
 C.guard(f.status:GetText():find('Desired A',1,true)~=nil and f.status:GetText():find('different Echo',1,true)~=nil,
  'L3: the shown status keeps the exact Echo name and its condition')
 C.expect(lines[2]:find(f.cont:GetText(),1,true)~=nil,'L3: the action line names the button actually shown',lines[2])
 C.guard(H.Count('orb-spend')==1,'L3: only the original Orb spend reached the game')
end)

C.scenario('L4 held game choice in this session: state-specific reload advice, no cleared-history note',function()
 local H,M,A,O=LostReply()
 H.Advance(2);H.Advance(6)
 local s=M.Status()
 C.setup(s.state=='PAUSED' and s.pending and s.reason:find('/reload',1,true)~=nil and s.reason:find('Desired A',1,true)~=nil,
  'L4: the runtime names the held choice, the Echo and /reload',s.reason)
 local f=Nexus.OrbPanel.Show()
 s=M.Status()
 local text=f.status:GetText()
 C.guard(text=='Paused\n'..s.reason,'L4: the window shows the runtime instruction whole, with no guessed Resume target',text)
 C.expect(s.resumeTarget and s.resumeTarget.kind=='blocked','L4: Resume names nothing while the choice is held')
 local w=Nexus.OrbPanel.ShowContinue()
 C.expect(w.history:GetText()=='','L4: an action of this session gets no cleared-history note')
 C.guard(not M.ContinueView().explanation,'L4: fixture: the record is not a restored one')
 w:Hide()
 f:Hide();Nexus.Panel.Show();H.Advance(.3)
 local bar=NexusPanel and NexusPanel._orbControls
 C.setup(bar and bar:IsVisible(),'L4: the actual current-session strip is visible')
 bar.refresh()
 C.expect(bar.summary:GetText():find('Last Orb action is not settled',1,true)~=nil
  and bar.summary:GetText():find('Paused - result must settle',1,true)~=nil,
  'L4: the same compact cue states the current unresolved action without claiming restoration',bar.summary:GetText())
 bar.details:Click()
 C.guard(f:IsVisible() and f.status:GetText()=='Paused\n'..M.Status().reason,
  'L4: Details keeps the current-session runtime instruction without a restored headline')
 C.guard(H.Count('orb-spend')==1 and H.Count('take')==1,'L4: nothing more was sent')
end)

C.scenario('L5 one usage form on the window, strip, mini panel and history',function()
 local H,M,A,O=Fresh()
 H.OrbPlan({{spellId=410002,quality=2,stacks=3}})
 local f=Nexus.OrbPanel.Show()
 local idle=f.usage:GetText()
 C.guard(idle:find('^Orbs used: 0 / ')~=nil and not idle:find('approved',1,true),'L5: before a run the draft is not called approved',idle)
 C.setup(M.Start(3) and M.Status().reserved==1,'L5: an approved run with one requested Orb')
 Nexus.OrbPanel.Refresh()
 C.expect(f.usage:GetText()=='Orbs used: 0 / 3 approved; pending: 1 Orb requested, not confirmed yet','L5: the window',f.usage:GetText())
 Nexus.Panel.Show();H.Advance(.3)
 local bar=NexusPanel and NexusPanel._orbControls
 C.setup(bar~=nil,'L5: the strip exists')
 bar.refresh()
 local lines=Lines(bar.summary:GetText())
 C.expect(lines[1]=='Orbs used: 0 / 3 approved' and lines[2]=='1 Orb pending, not confirmed yet','L5: the strip',bar.summary:GetText())
 local mini=Nexus.OrbPanel.ShowMini()
 C.guard(mini.usage:GetText()=='Orbs used: 0 of 3 approved' and mini.pending:GetText()=='Pending: 1 Orb requested, not confirmed yet',
  'L5: the mini panel keeps its words',mini.usage:GetText())
 local log=Nexus.OrbPanel.ShowLog()
 local view,live=M.RunLog('current'),M.Status()
 C.setup(view.runId~=nil and log.header:GetText():find('Run '..tostring(view.runId),1,true)~=nil,'L5: the history shows the current run',log.header:GetText())
 C.expect(log.header:GetText():find('Orbs used: 0 / 3 approved',1,true)~=nil,'L5: the history header',log.header:GetText())
 -- The request was logged just before its Orb was reserved; the current run's
 -- history carries the run's own usage and exposure, not that earlier copy.
 -- (EXPECT: before this repair the history said nothing here, on M5 too.)
 C.expect(view.reserved==live.reserved and view.spent==live.spent,'L5: the current history carries the run usage and exposure',
  tostring(view.spent)..'/'..tostring(view.reserved)..' vs '..tostring(live.spent)..'/'..tostring(live.reserved))
 C.expect(log.warning:GetText()=='Pending (requested, not confirmed): 1 Orb; the run has an unresolved operation and is not settled.','L5: the history states the unresolved operation',log.warning:GetText())
 C.expect(Nexus.OrbHistory.Header({runId=1,spent=14,limit=15,reserved=0,state='FINISHED'}).usage=='Orbs used: 14 / 15 approved','L5: the history projection')
 C.guard(H.Count('orb-spend')==1,'L5: reading every surface spent nothing more')
 -- Settled: the result arrives while the run is paused (as orb_finished_run_log
 -- section 8). The same history then counts the Orb as used and states no
 -- unresolved operation.
 log:Hide()
 H.Offer();C.setup(M.Pause(),'L5: the run is paused before its result arrives')
 H.Result(410002,2)
 live=M.Status()
 C.setup(not live.pending and live.spent==1 and live.reserved==0,'L5: the result settled while paused',live.state)
 log=Nexus.OrbPanel.ShowLog();view=M.RunLog('current')
 C.guard(view.spent==1 and view.reserved==0 and log.warning:GetText()=='','L5: a settled history states no unresolved operation',log.warning:GetText())
 C.expect(log.header:GetText():find('Orbs used: 1 / 3 approved',1,true)~=nil,'L5: the settled history header',log.header:GetText())
 -- The open page keys on the shown usage and exposure as well as the revision:
 -- a change of exposure at the same revision is shown, and so is its return.
 local realRunLog=M.RunLog
 M.RunLog=function(...) local v=realRunLog(...);if v.runId then v.reserved=1 end;return v end
 log:GetScript('OnUpdate')(log,1)
 C.expect(log.warning:GetText()=='Pending (requested, not confirmed): 1 Orb; the run has an unresolved operation and is not settled.','L5: an open history follows exposure at the same revision',log.warning:GetText())
 M.RunLog=realRunLog
 log:GetScript('OnUpdate')(log,1)
 C.guard(log.warning:GetText()=='','L5: and shows it settled again',log.warning:GetText())
 log:Hide()
 C.guard(H.Count('orb-spend')==1 and not M.Status().running,'L5: settling while paused spent nothing more')
end)

C.scenario('L6 Help: fixed controls, target review, usage words and state-specific reload advice',function()
 Fresh()
 local orbs,trouble
 for _,p in ipairs(Nexus.Help.Pages) do
  if p.id=='orbs' then orbs=p.text elseif p.id=='troubleshooting' then trouble=p.text end
 end
 C.setup(orbs and trouble,'L6: the Orb and troubleshooting pages exist')
 local function has(t,s) return t:find(s,1,true)~=nil end
 for _,s in ipairs({'Pause and Resume are separate buttons in fixed places','name the Wishlist that Resume would use',
  'click Review target in the Orb window and Resume there','Review target spends nothing',
  'Orbs used counts spent Orbs against the approved maximum','pending means an Orb was requested and its spend is not confirmed yet',
  'what is blocked, then what you can do now, then the details','a reload never clears the record','Otherwise do not reload',
  'before any reload','Run history clears on reload or logout'}) do
  C.expect(has(orbs,s),'L6: the Orb page says: '..s)
 end
 for _,s in ipairs({'do not clear it','Nexus never retries or refunds it, and never deletes the record','Nexus never continues by itself',
  'Resume adopts the new target and keeps the same maximum','The approved maximum does not change during the run',
  'Closing the window does not stop an approved run. Use Pause or Stop.'}) do
  C.guard(has(orbs,s),'L6: the Orb page keeps: '..s)
 end
 C.guard(not orbs:lower():find('try again',1,true) and not orbs:lower():find('choose again if',1,true),'L6: no retry advice')
 C.guard(not orbs:lower():find('reload fixes',1,true) and not orbs:lower():find('reload to fix',1,true)
  and not orbs:lower():find('reloading fixes',1,true),'L6: no universal reload fix')
 C.guard(has(trouble,'before any reload') and has(trouble,'do not reload'),'L6: troubleshooting keeps its report-first advice')
 -- Each reload case Help names is one the runtime actually states.
 local handle=assert(io.open('core/OrbRuntime.lua','rb'));local src=handle:read('*a');handle:close()
 C.guard(has(src,'/reload ends that wait') and has(src,'reload the game: Continue') and has(src,'A reload usually clears it')
  and has(src,'/reload may restore it'),'L6: the runtime states each reload case that Help lists')
end)

C.finish('real Orb windows, strip, mini and history; synthetic services; no native recovery claim')
