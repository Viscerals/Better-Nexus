-- Issue #171, UI slice: the Options session control over the frozen
-- Nexus.SessionPause API (IsPaused, Status, Pause, Resume; owned by the
-- pauseC lane). This fixture replaces that module with a boundary double that
-- follows the frozen contract and counts its calls; it is not evidence of a
-- whole-addon pause.
-- U1 without the API (or with a malformed one) the control is shown
--    unavailable and nothing is ever labelled paused;
-- U2 rendering, opening Options and opening Help call no Pause or Resume;
--    Options offers "Pause Nexus for this session" with its explanation;
-- U3 the Pause row calls Pause once; "Nexus paused" shows in the title and
--    the roll status; Options offers "Resume Nexus" with its note; Auto's
--    selection is untouched and no refresh step or Auto toggle runs;
-- U4 the Resume row calls Resume once; the paused labels go; no refresh
--    step, Auto toggle or Orb action runs;
-- U5 a Pause that throws, or answers a malformed or unpaused status, is not
--    shown as paused and says it did not pause; repeated Pause/Resume in the
--    owner never makes a local paused flag.
-- Categories (view_regression_support): EXPECT fails at e1183fd (no session
-- control), GUARD already held, SETUP is the fixture. Native NOT RUN.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('crimson_panel_pause')

local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local P=Nexus.Panel
local function Model()
 return {status='ready',level=40,auto=false,cards={{text='Frostwake Sigil (Rare)'}},recommendation='Take Frostwake Sigil.',
  progress={wishlistName='Pause plan',total=6,owned=2,missing={'Hollow Bell'},shed={},toLock={},unknownTomes={}}}
end
local function Effects()
 -- Outbound ownership and slot refreshes are counted apart from H.sent.
 return table.concat({'actions='..#H.actions,'sent='..#H.sent,'granted='..tostring(H.grantedRequests or 0),
  'slots='..tostring(H.slotRequests or 0),'saved='..F.Serialize(NexusDB),
  'auto='..tostring(Nexus.RecomputeStats().autoEnabled==true)},' ')
end
-- The frozen API as a boundary double: pure reads, idempotent transitions.
local D
local function Double()
 D={paused=false,epoch=0,pauses=0,resumes=0,reads=0}
 Nexus.SessionPause={
  IsPaused=function() D.reads=D.reads+1;return D.paused end,
  Status=function() D.reads=D.reads+1;return {paused=D.paused,epoch=D.epoch,reason=D.paused and 'session_pause' or nil} end,
  Pause=function() D.pauses=D.pauses+1;if not D.paused then D.paused=true;D.epoch=D.epoch+1 end
   return {paused=D.paused,epoch=D.epoch,reason='session_pause'} end,
  Resume=function() D.resumes=D.resumes+1;if D.paused then D.paused=false;D.epoch=D.epoch+1 end
   return {paused=D.paused,epoch=D.epoch} end,
 }
end
-- The lifecycle callbacks the panel holds, counted (UI / lifecycle boundary).
local CB={refresh=0,toggle=0,first=0}
P.Init({RefreshDisplay=function() CB.refresh=CB.refresh+1;return true end,
 ToggleAuto=function() CB.toggle=CB.toggle+1;return false end,
 RequestFirstDisplay=function() CB.first=CB.first+1;return true end})
local function Session()
 local out={}
 for _,item in ipairs(P.MoreMenuItems(NexusPanel._menuBtn)) do
  local t=type(item.text)=='string' and V.Plain(item.text) or ''
  if t:find('Pause Nexus',1,true) or t:find('Resume Nexus',1,true) or t:find('Pauses Auto',1,true)
   or t:find('Session pause',1,true)
   or t:find('Auto can continue',1,true) or t:find('An action already sent',1,true)
   or t:find('Orb runs stay paused',1,true) then out[#out+1]=item end
 end
 return out
end
-- The visible note rows (disabled rows without an action), joined in order.
local function Notes(rows)
 local out={}
 for _,r in ipairs(rows) do if r.disabled and r.func==nil then out[#out+1]=V.Plain(r.text) end end
 return table.concat(out,' ')
end
local function Find(rows,prefix)
 for _,r in ipairs(rows) do if V.Plain(r.text):sub(1,#prefix)==prefix then return r end end
end
local function Title() return V.Plain(NexusPanel._contextTitle:GetText() or '') end
local function Heading() return V.Plain(NexusPanel._rollStatus:GetText() or '') end
local function Click(row) row.func(row,row.arg1,row.arg2) end
local EXPLAIN='Pauses Auto, Orb actions, sharing and DPS recording. An action already sent may still finish.'
local RESUME_NOTE='Auto can continue if it was already on. Orb runs stay paused.'

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: local start-up is ready')
Nexus.DisableOrdinaryAutomation()
P.Show()

C.scenario('U1 without a usable API the control is unavailable and nothing says paused',function()
 for _,case in ipairs({{'no module',nil},{'a module without Status',{IsPaused=function() return true end}},
  {'a Status that throws',{IsPaused=function() return true end,Status=function() error('x') end,Pause=function() end,Resume=function() end}},
  {'a malformed Status',{IsPaused=function() return true end,Status=function() return {paused='yes',epoch=-1} end,
   Pause=function() end,Resume=function() end}}}) do
  Nexus.SessionPause=case[2]
  C.setup(P.Render(Model())==true,'U1: fixture: the panel renders with '..case[1])
  local rows=Session()
  -- Review of 2578d17: a Status that fails or is malformed is unknown, not
  -- unpaused; no module (or no Status) is a build without the control.
  local unknown=case[2]~=nil and type(case[2].Status)=='function'
  local pause=unknown and Find(rows,'Session pause: cannot be read') or Find(rows,'Pause Nexus for this session')
  local word=unknown and 'cannot be read' or 'not available'
  C.expect(pause~=nil and pause.disabled==true and pause.func==nil and V.Plain(pause.text):find(word,1,true)~=nil
   and not tostring(pause.tooltipText):find('nothing is paused',1,true),
   'U1: with '..case[1]..' the control is shown disabled as '..word,pause and pause.text)
  C.expect(Find(rows,'Resume Nexus')==nil and not Title():find('paused',1,true) and not Heading():find('Nexus paused',1,true),
   'U1: with '..case[1]..' nothing is labelled paused',Title()..' / '..Heading())
 end
end)

C.scenario('U2 rendering, Options and Help call no Pause or Resume; Options offers Pause with its explanation',function()
 Double()
 local before=Effects()
 P.Render(Model())
 local rows=Session()
 if Nexus.Help and Nexus.Help.Show then Nexus.Help.Show('faq');Nexus.Help.Show('rolling');Nexus.Help.Hide() end
 C.expect(D.pauses==0 and D.resumes==0,'U2: rendering, Options and Help call no Pause or Resume',D.pauses..'/'..D.resumes)
 local pause=Find(rows,'Pause Nexus for this session')
 C.expect(pause~=nil and not pause.disabled and type(pause.func)=='function','U2: Options offers Pause Nexus for this session')
 C.expect(pause and pause.tooltipText==EXPLAIN and Notes(rows)==EXPLAIN,
  'U2: its explanation is its hover and the visible note rows below it',Notes(rows))
 C.expect(Find(rows,'Resume Nexus')==nil and Title():sub(1,5)=='Nexus' and not Title():find('paused',1,true),'U2: not paused: no Resume, title is Nexus',Title())
 C.guard(Effects()==before,'U2: reading changes no saved data, Auto, action or send',Effects())
end)

C.scenario('U3 Pause: once through the API; Nexus paused shown; Resume offered; Auto untouched',function()
 Double()
 P.Render(Model())
 local before=Effects()
 local cb={refresh=CB.refresh,toggle=CB.toggle}
 Click(Find(Session(),'Pause Nexus for this session'))
 C.expect(D.pauses==1 and D.resumes==0,'U3: the Pause row calls Pause once',D.pauses)
 C.expect(Title():find('Nexus paused',1,true)==1,'U3: the title says Nexus paused',Title())
 C.expect(Heading()=='Nexus paused','U3: the roll status says Nexus paused',Heading())
 local rows=Session()
 local resume=Find(rows,'Resume Nexus')
 C.expect(resume~=nil and type(resume.func)=='function' and Find(rows,'Pause Nexus')==nil,'U3: Options now offers Resume Nexus instead')
 C.expect(resume and resume.tooltipText==RESUME_NOTE and Notes(rows)==RESUME_NOTE,
  'U3: Resume carries its note beside it (hover and the note rows below it)',Notes(rows))
 C.guard(CB.refresh==cb.refresh and CB.toggle==cb.toggle,'U3: no refresh step and no Auto toggle ran',CB.refresh..'/'..CB.toggle)
 C.guard(Effects()==before,'U3: the panel itself changes no saved data, Auto, action or send',Effects())
 P.Render(Model())
 C.expect(D.pauses==1 and Heading()=='Nexus paused','U3: a later render keeps the label and pauses nothing again')
end)

C.scenario('U4 Resume: once through the API; labels go; no refresh step, Auto toggle or action',function()
 local before=Effects()
 local cb={refresh=CB.refresh,toggle=CB.toggle}
 local resume=Find(Session(),'Resume Nexus')
 if not C.setup(resume~=nil,'U4: fixture: paused, Resume offered') then return end
 Click(resume)
 C.expect(D.resumes==1 and D.pauses==1,'U4: the Resume row calls Resume once',D.resumes)
 C.expect(not Title():find('paused',1,true) and Heading()~='Nexus paused','U4: the paused labels go',Title()..' / '..Heading())
 C.expect(Find(Session(),'Pause Nexus for this session')~=nil,'U4: Pause is offered again')
 C.guard(CB.refresh==cb.refresh and CB.toggle==cb.toggle,'U4: Resume runs no refresh step and no Auto toggle',CB.refresh..'/'..CB.toggle)
 C.guard(Effects()==before,'U4: Resume through the panel takes no action and sends nothing',Effects())
end)

C.scenario('U5 a failing or unconfirmed Pause is not shown as paused',function()
 for _,case in ipairs({{'throws',function() error('owner failed') end},
  {'answers unpaused',function() return {paused=false,epoch=0} end},
  {'answers malformed',function() return 'paused' end}}) do
  Double()
  Nexus.SessionPause.Pause=case[2]
  P.Render(Model())
  local said={}
  local real=print
  print=function(...) said[#said+1]=tostring((...)) end
  local ok=pcall(Click,Find(Session(),'Pause Nexus for this session'))
  print=real
  C.expect(ok and not Title():find('paused',1,true) and Heading()~='Nexus paused' and Find(Session(),'Resume Nexus')==nil,
   'U5: a Pause that '..case[1]..' is not shown as paused',Title())
  C.expect(table.concat(said,' '):find('did not pause',1,true)~=nil,'U5: a Pause that '..case[1]..' says it did not pause',table.concat(said,' '))
 end
 Nexus.SessionPause=nil
 P.Render(Model())
end)

Nexus.DisableOrdinaryAutomation()
C.finish('(Options session pause control over a boundary double of the frozen SessionPause API; whole-addon pause and native NOT RUN)')
