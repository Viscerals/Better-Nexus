-- Integration of the three Crimson lanes: the real Nexus.SessionPause (#171
-- core), the panel's Options session control, Auto explained and Questions
-- Help (#171 UI, #169) and the attached Orb strip's terminal Hide (#167),
-- all loaded from the real Nexus.toc by orbs_support. Nothing here replaces
-- SessionPause, the panel's lifecycle callbacks or the Orb runtime.
-- I1 Auto OFF: the panel renders; its registered Options button opens the
--    menu; Auto explained, Questions (FAQ) and the session Help answer are
--    reachable; Pause then Resume through the real menu rows move the real
--    owner (Status, IsPaused, epoch) and the panel's title, roll status,
--    Help page and rows follow it; reading and opening change nothing; Auto
--    stays OFF and the saved data (with an unknown field) stays as it was;
-- I2 an approved synthetic Orb run is held by the global Pause; the panel's
--    Resume removes only the global barrier: the run stays PAUSED, not
--    running, with the same run, receipt, maximum and exposure, and nothing
--    is spent, chosen or requested meanwhile;
-- I3 the attached strip of that held run, and of a finished run with two
--    unknown outcomes across a global Pause and Resume, stays shown without
--    Hide; the strip's own Hide callback, kept from before the pause, neither
--    hides nor changes it; a settled run's Hide works (positive control).
-- The Options menu is captured by a read-only EasyMenu observer (as in
-- panel_options_label): it records the rows the real opener passes and draws
-- nothing. This is not the native stock popup; native menus, clicks, pixels
-- and timing are NOT RUN. Categories (view_regression_support): EXPECT is
-- behaviour of the composed lanes (fails before the core lane is merged),
-- GUARD must keep holding, SETUP is the fixture. Synthetic services only.
local V=dofile('tests/prototype/view_regression_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local C=V.Checker('crimson_pause_panel_orb_integration')
local H,M,A,O
local PLAN={{spellId=410002,quality=2,stacks=14}}
local CARDS={{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410008,quality=1}}
local EXPLAIN='Pauses Auto, Orb actions, sharing and DPS recording. An action already sent may still finish.'
local RESUME_NOTE='Auto can continue if it was already on. Orb runs stay paused.'

-- Read-only native-menu observer: what the real Options opener passes.
local menu={opens=0}
local function Observe()
 EasyMenu=function(items,frame,anchor) menu.opens=menu.opens+1;menu.items=items;menu.frame=frame;menu.anchor=anchor end
end
local function Fresh()
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 Nexus=nil;NexusDB=nil;NexusSupportDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil;NexusPanel=nil
 H=dofile('tests/prototype/orbs_support.lua');M,A,O=H.M,H.A,H.O
 UIParent:SetSize(1920,1080)
 H.OrbPlan(PLAN)
 Observe()
end
local function Strip()
 Nexus.Panel.Show();H.Advance(.3)
 return NexusPanel and NexusPanel._orbControls
end
-- The Options menu as the player opens it: the registered OnClick.
local function Options()
 menu.items=nil
 NexusPanel._menuBtn:GetScript('OnClick')(NexusPanel._menuBtn)
 return menu.items or {}
end
local function Find(rows,prefix)
 for _,r in ipairs(rows) do
  if type(r.text)=='string' and V.Plain(r.text):sub(1,#prefix)==prefix then return r end
 end
end
local function Click(row) row.func(row,row.arg1,row.arg2) end
local function Title() return V.Plain(NexusPanel._contextTitle:GetText() or '') end
local function Heading() return V.Plain(NexusPanel._rollStatus:GetText() or '') end
local function HelpText()
 local w=_G.NexusHelpWindow
 return w and w:IsShown() and V.Plain((w.title:GetText() or '')..'\n'..(w.body:GetText() or '')) or ''
end
local function Has(text,s) return tostring(text or ''):find(s,1,true)~=nil end
local function Run()
 local s=M.Status();local c=M.CompactStatus() or {}
 return {state=s.state,running=s.running,pending=s.pending,spent=s.spent,reserved=s.reserved,limit=s.limit,
  uncertain=c.uncertain,unconfirmed=c.unconfirmedResults,remaining=c.remaining,runId=M.RunLog('current',1,0).runId}
end
-- The first saved top-level entry that differs, so a failure names it.
local function SavedKey(a,b)
 for _,root in ipairs({'NexusDB','NexusSupportDB','WishlistRealizerDB'}) do
  local x,y=a[root] or {},b[root] or {}
  for k,v in pairs(x) do if y[k]~=v then return root..'.'..tostring(k) end end
  for k in pairs(y) do if x[k]==nil then return root..'.'..tostring(k) end end
 end
end
local function Saved()
 local out={}
 for _,root in ipairs({'NexusDB','NexusSupportDB','WishlistRealizerDB'}) do
  out[root]={}
  for k,v in pairs(_G[root] or {}) do out[root][k]=F.Serialize(v) end
 end
 return out
end
-- Every host and network call the synthetic services count, Auto, the
-- session pause's epoch and every saved root. The diagnostic-log counters
-- (NexusDB.diagnosticMeta) are apart as logs: an observed offer or tick is
-- logged while paused, as the pause keeps local diagnostics.
local function Effects()
 local logs=NexusDB.diagnosticMeta;NexusDB.diagnosticMeta=nil
 local db=F.Serialize(NexusDB);local saved=Saved()
 NexusDB.diagnosticMeta=logs
 return {spend=H.Count('orb-spend'),take=H.Count('take'),actions=#H.actions,sent=#H.sent,
  charges=O.requests,granted=H.grantedRequests or 0,slots=H.slotRequests or 0,
  auto=Nexus.RecomputeStats().autoEnabled==true,epoch=Nexus.SessionPause.Status().epoch,
  db=db,logs=F.Serialize(logs),support=F.Serialize(NexusSupportDB),wr=F.Serialize(WishlistRealizerDB),saved=saved}
end
-- The Orb counters alone: spends, choices and Orb count requests.
local function OrbCalls() return H.Count('orb-spend')..'/'..H.Count('take')..'/'..O.requests end
local function Diff(a,b,skip)
 for k,v in pairs(a) do
  if not (skip and skip[k]) and b[k]~=v then
   if k=='db' or k=='support' or k=='wr' or k=='logs' then return 'saved: '..tostring(SavedKey(a.saved,b.saved)) end
   if k~='saved' then return k..': '..tostring(v)..' -> '..tostring(b[k]) end
  end
 end
end

C.scenario('I1 Auto OFF: real panel, Options, Help and the real session pause through the menu rows',function()
 Fresh()
 local SP=Nexus.SessionPause
 C.setup(type(SP)=='table' and Nexus.StartupStatus().coreReady==true,'I1: the real TOC loaded SessionPause and start-up is ready')
 NexusDB.integrationUnknown={kept='yes',n=7}
 -- An offer on the board, so the roll block and its status are shown.
 H.Board(CARDS);H.Notify()
 local bar=Strip()
 C.setup(NexusPanel and NexusPanel:IsShown() and NexusPanel._menuBtn~=nil and NexusPanel._rollArea:IsShown(),
  'I1: the real panel is shown with its Options button and roll block',Heading())
 C.guard(Nexus.RecomputeStats().autoEnabled==false and Nexus.Panel.AutoSelectedNow()==false,'I1: ordinary Auto starts OFF')
 local start=Effects()
 local st=SP.Status()
 C.guard(st.paused==false and st.epoch==0 and st.reason==nil and SP.IsPaused()==false,'I1: the session starts unpaused at epoch 0')
 C.expect(Nexus.Panel.PauseStatus().available==true and Nexus.Panel.PauseStatus().paused==false,
  'I1: the panel reads the real session pause as available and not paused')
 local rows=Options()
 C.expect(menu.anchor==NexusPanel._menuBtn and menu.frame==Nexus.Panel._moreMenu and #rows>0,'I1: the registered Options button opens its menu')
 local pause=Find(rows,'Pause Nexus for this session')
 C.expect(pause and not pause.disabled and type(pause.func)=='function' and pause.tooltipText==EXPLAIN,
  'I1: Options offers a working Pause Nexus for this session with its explanation',pause and pause.text)
 C.expect(Find(rows,'Resume Nexus')==nil and Title():sub(1,5)=='Nexus' and not Has(Title(),'paused'),'I1: not paused: no Resume, no paused label',Title())
 -- Deliberate Help routes: Auto explained, Questions (FAQ) and its pause answer.
 Click(Find(rows,'Auto explained'))
 local auto=HelpText()
 C.guard(Has(auto,'Automation and enabled actions') and Has(auto,'Orb runs require separate approval'),'I1: Auto explained opens the complete Auto page')
 C.expect(not Has(auto,'Now: paused for this session') and not Has(auto,'cannot be read'),'I1: unpaused, the Auto page claims no pause and no unknown state')
 Click(Find(Options(),'Questions (FAQ)'))
 local faq=HelpText()
 C.guard(Has(faq,'Pause, hide or Auto OFF?') and Has(faq,'It is kept in memory only'),'I1: the FAQ answers pause versus hide, memory only')
 Nexus.Help.Hide()
 C.guard(Diff(start,Effects())==nil,'I1: rendering, opening Options and reading Help change nothing',Diff(start,Effects()))
 for _=1,3 do Nexus.Panel.PauseStatus();SP.Status();SP.IsPaused() end
 C.guard(Diff(start,Effects())==nil,'I1: status reads change nothing',Diff(start,Effects()))

 Click(Find(Options(),'Pause Nexus for this session'))
 st=SP.Status()
 C.expect(st.paused==true and st.epoch==1 and st.reason=='session_pause' and SP.IsPaused()==true,
  'I1: the Pause row pauses the real owner once',tostring(st.paused)..'/'..tostring(st.epoch))
 C.expect(Has(Title(),'Nexus paused') and Heading()=='Nexus paused','I1: the title and roll status say Nexus paused',Title()..' / '..Heading())
 rows=Options()
 local resume=Find(rows,'Resume Nexus')
 C.expect(resume and type(resume.func)=='function' and resume.tooltipText==RESUME_NOTE and Find(rows,'Pause Nexus')==nil,
  'I1: Options now offers Resume Nexus with its note')
 Click(Find(rows,'Auto explained'))
 C.expect(Has(HelpText(),'Now: paused for this session'),'I1: the Auto page reports the real pause as the current hold')
 Nexus.Help.Hide()
 local summary=table.concat(Nexus.Panel.AutoSummaryLines(),' ')
 C.expect(Has(summary,'Nexus is paused for this session') and Has(summary,'Options > Resume Nexus'),'I1: the Auto hover says paused and how to resume',summary)
 H.Advance(2)
 C.guard(Nexus.RecomputeStats().autoEnabled==false and SP.Status().epoch==1,'I1: paused ticks keep Auto OFF and the epoch')
 C.guard(Diff(start,Effects(),{epoch=true})==nil,'I1: pausing and reading while paused change no saved data, call or send',Diff(start,Effects(),{epoch=true}))

 Click(resume)
 st=SP.Status()
 C.expect(st.paused==false and st.epoch==2 and st.reason==nil and SP.IsPaused()==false,'I1: the Resume row resumes the real owner once',tostring(st.epoch))
 C.expect(not Has(Title(),'paused') and Heading()~='Nexus paused' and Find(Options(),'Pause Nexus for this session')~=nil,
  'I1: the paused labels go and Pause is offered again',Title()..' / '..Heading())
 SP.Resume();SP.Pause();SP.Pause();SP.Resume()
 C.guard(SP.Status().epoch==4,'I1: repeated calls move the epoch only on real transitions',SP.Status().epoch)
 H.Advance(2)
 C.guard(Nexus.RecomputeStats().autoEnabled==false,'I1: Auto OFF stays OFF after Resume')
 local after=Effects()
 C.guard(Diff(start,after,{epoch=true})==nil and Has(after.db,'integrationUnknown'),
  'I1: saved roots, unknown field, Auto and every counted call are unchanged',Diff(start,after,{epoch=true}))
end)

C.scenario('I2 the global Pause holds an approved Orb run; the panel Resume removes only the global barrier',function()
 Fresh()
 local SP=Nexus.SessionPause
 -- Control: on this rig an approved run spends its first Orb.
 H.Approve(3)
 local bar=Strip()
 local run=Run()
 C.setup(run.running and run.pending and H.Count('orb-spend')==1,'I2: control: the approved synthetic run spent one Orb and waits')
 C.setup(bar and bar:IsShown(),'I2: the attached strip shows the run')
 local stale=bar.dismiss:GetScript('OnClick')
 Click(Find(Options(),'Pause Nexus for this session'))
 C.expect(SP.IsPaused() and Has(Title(),'Nexus paused'),'I2: the panel Pause row paused Nexus',Title())
 local held=Run()
 C.expect(held.state=='PAUSED' and not held.running,'I2: the global Pause holds the run',held.state)
 C.guard(held.runId==run.runId and held.pending and held.limit==3 and held.spent==run.spent and held.reserved==run.reserved
  and held.uncertain==run.uncertain,'I2: same run, receipt, maximum and exposure')
 -- The offer of the Orb submitted before the pause arrives while paused: it
-- settles that spend once (an action already sent may finish); the offer
-- waits unchosen and no further Orb is spent or requested.
 local calls=Effects()
 H.Offer(CARDS);H.Advance(5)
 local settled=Run()
 C.expect(Diff(calls,Effects(),{logs=true,db=true})==nil,'I2: while paused the offer and the tickers spend, choose, request and send nothing',
  Diff(calls,Effects(),{logs=true,db=true}))
 C.guard(settled.state=='PAUSED' and not settled.running and settled.runId==held.runId and settled.limit==3
  and settled.spent==held.spent+1 and settled.reserved==held.reserved-1 and settled.uncertain==held.uncertain
  and settled.pending and H.Count('take')==0,
  'I2: the submitted spend settles once; its offer waits unchosen; the run stays held with its maximum',
  F.Serialize(held)..' -> '..F.Serialize(settled))
 local base=Effects()
 C.expect(bar:IsShown() and not bar.dismiss:IsShown(),'I3: the strip of the held run stays shown without Hide')
 stale(bar.dismiss);bar.refresh()
 C.expect(bar:IsShown() and Diff(base,Effects(),{logs=true})==nil,'I3: a direct Hide callback neither hides nor changes it',Diff(base,Effects(),{logs=true}))

 local orb=OrbCalls()
 Click(Find(Options(),'Resume Nexus'))
 C.expect(not SP.IsPaused() and SP.Status().epoch==2,'I2: the panel Resume row removed the global barrier')
 C.expect(Diff(base,Effects(),{epoch=true,logs=true})==nil,'I2: Resume itself spends, chooses, requests, sends and saves nothing',
  Diff(base,Effects(),{epoch=true,logs=true}))
 H.Advance(3)
 local after=Run()
 C.expect(after.state=='PAUSED' and not after.running,'I2: the Orb run stays paused after the global Resume',after.state)
 C.guard(Diff(settled,after)==nil,'I2: same run, receipt, maximum, usage and exposure after Resume',Diff(settled,after))
 C.expect(OrbCalls()==orb,'I2: later turns after Resume spend no Orb, choose and request no Orb count',orb..' -> '..OrbCalls())
 stale(bar.dismiss);bar.refresh();H.Advance(.5)
 C.expect(bar:IsShown() and not bar.dismiss:IsShown(),'I3: after Resume the paused run\'s strip stays shown, without Hide')
end)

-- The bounded-recovery setup used by orb_strip_dismiss D6: real Start and
-- adapter with a quiet synthetic server, so both outcomes stay unknown.
local RS=dofile('tests/prototype/orb_recovery_support.lua')
local function RecoveryFresh(limit)
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 NexusSupportDB=nil;NexusPanel=nil
 H,M,A,O=RS.S.Fresh()
 UIParent:SetSize(1920,1080)
 RS.S.Loadouts(H,A);H.perks.currentChoice={}
 Observe()
 assert(M.Start(limit))
end
local function WaitFor(predicate,seconds)
 for _=1,(seconds or 30)*4 do if predicate() then return true end;H.Advance(.25) end
 return predicate()
end

C.scenario('I3 unknown outcomes stay shown across the global Pause and Resume; a settled run can hide',function()
 -- Positive control: the same setup with both results observed.
 RecoveryFresh(2)
 H.Offer();H.Result(410002,2)
 C.setup(WaitFor(function()return H.Count('orb-spend')==2 end),'I3 control: the run spends its second approved Orb')
 H.Offer();H.Result(410002,2);H.Advance(2)
 local s=M.CompactStatus()
 C.setup(s and not s.pending and s.uncertain==0 and (s.unconfirmedResults or 0)==0,'I3 control: the run settled with both outcomes observed',s and s.state)
 local bar=Strip()
 C.expect(bar and bar:IsShown() and bar.dismiss:IsShown(),'I3 control: a settled run offers Hide')
 bar.dismiss:Click()
 C.expect(not bar:IsShown(),'I3 control: and its Hide hides it')

 RecoveryFresh(2)
 local server=RS.Server(H)
 H.service.RequestChoice=function()
  SendAddonMessage(RS.PREFIX,'16','WHISPER',RS.ME);server.queue[#server.queue+1]={op=16,body=''}
 end
 C.setup(WaitFor(function()return M.Status().state=='FINISHED' end,45),'I3: unknown exposure reaches the approved maximum')
 s=M.CompactStatus()
 C.setup(not s.pending and not s.running and s.uncertain==2 and s.unconfirmedResults==2,'I3: two unknown outcomes retained')
 bar=Strip()
 local SP=Nexus.SessionPause
 C.setup(bar and bar:IsShown() and not bar.dismiss:IsShown(),'I3: shown without Hide before the pause')
 -- The strip's own Hide callback, kept from before the pause.
 local stale=bar.dismiss:GetScript('OnClick')
 local before=Run()
 local base=Effects()
 local archive=F.Serialize(RS.SavedRow('orbRecoveryArchive'))
 Click(Find(Options(),'Pause Nexus for this session'))
 C.expect(SP.IsPaused() and Has(Title(),'Nexus paused'),'I3: the panel Pause row paused Nexus',Title())
 H.Advance(2)
 C.expect(bar:IsShown() and not bar.dismiss:IsShown(),'I3: while paused the strip of unknown outcomes stays shown without Hide')
 stale(bar.dismiss);bar.refresh()
 C.expect(bar:IsShown(),'I3: its kept Hide callback does not hide it while paused')
 local orb=OrbCalls()
 Click(Find(Options(),'Resume Nexus'))
 C.guard(Diff(base,Effects(),{epoch=true,logs=true})==nil and F.Serialize(RS.SavedRow('orbRecoveryArchive'))==archive,
  'I3: pausing and resuming spend, choose, request, send and save nothing',Diff(base,Effects(),{epoch=true,logs=true}))
 H.Advance(2)
 stale(bar.dismiss);bar.refresh()
 C.expect(not SP.IsPaused() and bar:IsShown() and not bar.dismiss:IsShown(),'I3: after Resume it is still shown without Hide')
 C.expect(Diff(before,Run())==nil,'I3: the run, its unknown exposure and remaining copies are unchanged',Diff(before,Run()))
 C.guard(OrbCalls()==orb and F.Serialize(RS.SavedRow('orbRecoveryArchive'))==archive,
  'I3: later turns spend no Orb and leave the recovery archive as it was',orb..' -> '..OrbCalls())
end)

C.finish('real TOC, SessionPause, panel menu rows, Help and attached Orb strip; read-only EasyMenu observer and synthetic services; native NOT RUN')
