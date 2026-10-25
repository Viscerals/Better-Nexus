-- M2 (UX-01): informational setup stays reachable after the first-launch
-- warning is answered No or closed, through a normal Setup / Welcome replay
-- (the ... menu and Help), and is never Auto consent. The replay records no
-- acknowledgement, writes no saved data, enables nothing and never opens over
-- a warning that waits for its answer; the warning keeps its reading delay
-- and its explicit Yes; Auto keeps its own warning. A first-time Welcome
-- dismissal that cannot be saved (read-only or failed start-up) says so.
-- UX01 (adopted: "Fresh profile: No -> Welcome shown, Auto OFF, no
-- overwriteWarnings write"): an explicit No (after the reading delay), Close
-- (X) or Escape of the first-launch warning opens the Welcome at once as the
-- same information-only setup (no acknowledgement, no consent, Auto stays
-- OFF). No other warning answer opens it:
--  - a Hide from another route declines the warning only (S8);
--  - an early No, before the reading delay ends, answers nothing: the warning
--    stays open and its answer stays pending, as after an early Yes (S1);
--  - the Auto warning's No, Close, Escape and CancelAuto decline it, accept
--    nothing and open nothing (S1). An Auto Yes keeps its original
--    consent-bound acceptance (pinned by overwrite_warning_clock); this
--    fixture exercises only a stale Auto Yes, which accepts nothing (S10);
--  - an answer given after the saved root or the character changed is stale:
--    it declines and opens nothing for the other context (S9, S10).
-- Closing the informational Welcome reopens nothing. Button labels and the
-- rest of UX01 are outside this fixture.
-- Escape here is always the warning's registered OnKeyDown script called
-- directly with "ESCAPE" (S7, and S1's repeated and Auto answers); no native
-- key is pressed. Native Escape capture by the keyboard-enabled warning, the
-- client's UISpecialFrames dispatch and its order, and whether that same
-- Escape also closes the Welcome it opens are NOT_RUN. A raw UISpecialFrames
-- hide is MODELLED offline as a plain Hide reaching the warning's OnHide,
-- which declines only and opens nothing (S8); the native raw hide path is
-- NOT_RUN. That native boundary is unverified, not
-- a proven defect.
-- EXPECT: behaviour added in M2 (fails on the accepted M1 cut, which has no
-- replay entry) or by UX01. UX01's direct EXPECTs are the three openings
-- (S1 No, S2 Close, S7 Escape); they fail where an explicit answer opens no
-- Welcome. Four more are DEPENDENT on those openings and say so in their
-- labels, with the direct result in their detail (S1: the refused Show
-- leaves it open; S1, S2, S7: closing it). Where no Welcome opened they fail
-- with their direct opening: three opening failures and four consequences of
-- them, not seven separate defects. A DEPENDENT failure whose detail shows
-- its direct opening held is a distinct fault. Their no-write, no-reopen and
-- no-consent conditions are also checked by GUARDs that do not depend on it.
-- GUARD: existing warning/Welcome/seen-state behaviour that must keep holding
-- (pinned also by overwrite_warning_*, quickstart_* tests). After a genuine
-- informational Close, S1, S2 and S7 end with a bounded runtime continuation
-- (one second of harness time) after their effects were compared, and read
-- only the navigation's own state after it. In S1 and S2 it runs at the
-- end of the scenario, after the Close and the replays, Help and (S1) Auto
-- answers that follow it, so it is end-of-scenario evidence, not evidence
-- attributable only to the initial Close. G1-G5 cover the existing
-- fail-closed informational route for the real No (after reading) and Close
-- (X) controls: the optional Nexus.QuickStart unavailable or not a table, or
-- its ShowSetup missing, not a function or throwing. They are added coverage
-- of current behaviour, not a reproduced defect; no failing-before result is
-- claimed for them.
-- SETUP: fixture state. Real TOC boot, real warning, Welcome, Panel menu and
-- Help controls; synthetic saved data and host services only.
local V=dofile('tests/prototype/view_regression_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local C=V.Checker('ux_setup_replay')
local H

-- F.Boot returns as soon as start-up leaves 'pending'. The first-launch
-- warning is raised by the runtime's first Step after that (ShowQuickStartOnce
-- -> QuickStart.ShowIfFirstTime -> OverwriteWarning.EnsureOnboarding), as
-- overwrite_warning_welcome.lua waits for after F.Reload. Request that Step
-- (the runtime's own recompute request) and advance the harness clock in small
-- steps until the real entry has shown it (bounded), and no further, so its
-- reading delay starts from that moment.
local function Fresh(mutate,keepPrompts)
 NexusOverwriteWarning=nil;NexusQuickStart=nil;NexusHelpWindow=nil;NexusPanel=nil
 local h=F.Boot(F.Database({mutate=function(db)
  db.overwriteWarnings=nil
  if mutate then mutate(db) end
 end}),function(h) h.keepOverwriteWarningPrompts=keepPrompts~=false end)
 if Nexus.RequestRecompute then Nexus.RequestRecompute() end
 for _=1,40 do
  if NexusOverwriteWarning and NexusOverwriteWarning:IsShown() then break end
  h.Advance(.05,.05)
 end
 return h
end
local function Warning() return NexusOverwriteWarning end
local function Welcome() return NexusQuickStart end
local function Shown() local w=Welcome();return w~=nil and w:IsShown() end
local function WelcomeButton(text)
 local w=Welcome();if not w then return nil end
 for _,c in ipairs(w.children or {})do if c.kind=='Button' and c:GetText()==text then return c end end
end
local function Title() return Welcome() and Welcome().title and V.Plain(Welcome().title:GetText() or '') or '' end
local function Hint() return Welcome() and Welcome().hint and V.Plain(Welcome().hint:GetText() or '') or '' end
local function Auto() return Nexus.RecomputeStats().autoEnabled==true end
local function Seen() return type(NexusDB)=='table' and rawget(NexusDB,'hasSeenQuickStart') or nil end
local function Saved() return type(NexusDB)=='table' and F.Serialize(NexusDB) or tostring(NexusDB) end
local function Heard(fn)
 local heard,realPrint={},print
 print=function(...) heard[#heard+1]=tostring((...));realPrint(...) end
 local ok,err=pcall(fn)
 print=realPrint
 assert(ok,err)
 return table.concat(heard,' / ')
end
-- The replay entry, called as the menu and Help call it; nil on a cut
-- without it (then the window simply is not shown).
local function Replay()
 local quick=Nexus.QuickStart
 if not (quick and type(quick.ShowSetup)=='function') then return nil,'no replay entry' end
 return quick.ShowSetup()
end
local function Counters() return {actions=#H.actions,sent=#H.sent,auto=Auto()} end
local function Quiet(tag,before)
 C.guard(#H.actions==before.actions and #H.sent==before.sent and Auto()==before.auto,
  tag..': no game action, no send, Auto unchanged','actions='..#H.actions..' sent='..#H.sent..' auto='..tostring(Auto()))
end
local function Informational() return Shown() and Title():find('information only',1,true)~=nil end
-- Presses a Welcome button only while the Welcome is shown; false otherwise,
-- so a cut that opens no Welcome reports its expectation instead of raising
-- or recording a first-time dismissal.
local function Press(text)
 local b=WelcomeButton(text)
 if not (b and Shown()) then return false end
 b:Click()
 return true
end

C.scenario('S1 No after reading: the informational Welcome opens at once; Setup / Welcome replays it',function()
 H=Fresh()
 local w=Warning()
 C.setup(w and w:IsShown(),'S1: fixture: the first-launch warning is shown')
 local before=Counters()
 -- While the warning waits for its answer, the replay does not open over it.
 local shown,why=Replay()
 C.expect(shown==false and why=='warning-open' and not Shown(),
  'S1: Setup / Welcome waits for the open warning instead of opening over it',tostring(shown)..'/'..tostring(why))
 -- The reading delay is intact: no choice before it, an early Yes or No does nothing.
 C.guard(not w.yes:IsEnabled() and not w.no:IsEnabled(),'S1: no choice before the reading delay')
 w.yes:GetScript('OnClick')(w.yes)
 C.guard(w:IsShown() and Nexus.OverwriteWarning.EnsureOnboarding()=='pending','S1: an early Yes accepts nothing')
 w.no:GetScript('OnClick')(w.no)
 C.guard(w:IsShown() and Nexus.OverwriteWarning.EnsureOnboarding()=='pending' and not Shown(),
  'S1: an early No handler declines nothing and opens no Welcome')
 H.Advance(5.01)
 C.setup(w.yes:IsEnabled() and w.no:IsEnabled(),'S1: fixture: choices enabled after reading')
 C.guard(#H.actions==before.actions and not Auto(),'S1: reading the warning takes no action and enables nothing')
 before=Counters() -- from here on no time passes, so sends are comparable
 local savedBefore=Saved()
 w.no:Click()
 C.guard(Nexus.OverwriteWarning.EnsureOnboarding()=='declined' and not w:IsShown(),'S1: No declines the warning')
 C.guard(NexusDB.overwriteWarnings==nil and Seen()==nil and Saved()==savedBefore,'S1: No saves no suppression and no seen state')
 -- DIRECT UX01 opening. The two EXPECTs marked DEPENDENT below can hold only
 -- when this one held; their detail reports its result, so a cut that opens
 -- no Welcome shows them as consequences of this one failure.
 local opened=C.expect(Informational() and Hint():find('never turns Auto ON',1,true)~=nil,
  'S1: No opens the Welcome at once, as information only that never turns Auto ON',Title()..' | '..Hint())
 C.guard(not Auto() and Nexus.OverwriteWarning.EnsureOnboarding()=='declined' and not w:IsShown(),
  'S1: the Welcome after No changes neither Auto nor the warning answer')
 C.guard(Nexus.QuickStart.Show()==false,'S1: the consent-bound Show still requires the warning to be accepted')
 C.expect(Informational(),'S1: DEPENDENT on the S1 No opening above: the refused Show leaves the informational Welcome as it is',
  Title()..' | direct opening held='..tostring(opened))
 local closed=Press('Close')
 C.expect(closed and not Shown() and not w:IsShown() and Seen()==nil and Saved()==savedBefore
  and Nexus.OverwriteWarning.EnsureOnboarding()=='declined',
  'S1: DEPENDENT on the S1 No opening above: closing it records nothing, writes nothing and reopens nothing',
  'direct opening held='..tostring(opened)..' closed='..tostring(closed))
 -- The answered warning is one-shot: its repeated callbacks open nothing.
 w.no:GetScript('OnClick')(w.no)
 w.close:GetScript('OnClick')(w.close)
 w:GetScript('OnKeyDown')(w,'ESCAPE')
 w:GetScript('OnHide')(w)
 C.guard(not Shown() and not w:IsShown() and Seen()==nil and Saved()==savedBefore
  and Nexus.OverwriteWarning.EnsureOnboarding()=='declined',
  'S1: repeated No, Close, Escape and Hide callbacks of the answered warning open nothing')
 shown,why=Replay()
 print('OBSERVED','S1 replay',tostring(shown),tostring(why),'title='..Title())
 C.expect(shown==true and Shown(),'S1: after No, Setup / Welcome opens the setup window',why)
 C.expect(Title():find('information only',1,true)~=nil and Hint():find('never turns Auto ON',1,true)~=nil,
  'S1: the replay says it is information only and never turns Auto ON',Title()..' | '..Hint())
 C.guard(not Auto() and Nexus.OverwriteWarning.EnsureOnboarding()=='declined','S1: opening it changes neither Auto nor the warning answer')
 if Shown() then
  WelcomeButton('Close'):Click()
  C.expect(not Shown() and Seen()==nil and Saved()==savedBefore,'S1: closing the replay records nothing and writes nothing')
  shown=Replay()
  C.expect(shown==true and Shown(),'S1: it can be replayed again in the same session')
  WelcomeButton('Help / Getting Started'):Click()
  C.expect(not Shown() and NexusHelpWindow and NexusHelpWindow:IsShown() and Seen()==nil and Saved()==savedBefore,
   'S1: an entry button of the replay opens its view and records nothing')
  if NexusHelpWindow then NexusHelpWindow:Hide() end
 end
 -- Auto keeps its own warning after No and the replay, and no Auto answer
 -- opens the closed Welcome, whichever way it is given.
 SlashCmdList.NEXUS('auto')
 w=Warning()
 C.guard(w:IsShown() and not Auto(),'S1: Auto still asks its own warning; nothing is enabled by asking')
 w.no:Click()
 C.guard(not Auto(),'S1: declining it keeps Auto OFF')
 C.guard(not w:IsShown() and not Shown(),'S1: Auto No opens no Welcome')
 local owner,accepted,savedAuto={},0,Saved()
 local function accept() accepted=accepted+1;return true end
 for _,way in ipairs({'Close','Escape','CancelAuto'}) do
  local asked=Nexus.OverwriteWarning.RequestAuto(owner,accept)
  C.setup(asked==false and w:IsShown() and Nexus.OverwriteWarning.IsOpen()==true,'S1: fixture: the Auto warning is open for '..way)
  if way=='Close' then w.close:Click()
  elseif way=='Escape' then w:GetScript('OnKeyDown')(w,'ESCAPE')
  else C.guard(Nexus.OverwriteWarning.CancelAuto(owner)==true,'S1: CancelAuto cancels its own Auto request') end
  C.guard(not w:IsShown() and not Shown() and accepted==0 and not Auto() and Saved()==savedAuto
   and Nexus.OverwriteWarning.EnsureOnboarding()=='declined',
   'S1: Auto '..way..' declines, accepts nothing, saves nothing and opens no Welcome')
 end
 Quiet('S1',before)
 -- Bounded runtime continuation, only after a genuine informational Close
 -- above: the effects were compared just now (Quiet); one second of harness
 -- time then lets the runtime's own steps run, and only the navigation's own
 -- state is read after it, so background work is not attributed to it.
 if closed then
  H.Advance(1,.05)
  C.guard(not Shown() and not Warning():IsShown() and Seen()==nil and NexusDB.overwriteWarnings==nil
   and not Auto() and Nexus.OverwriteWarning.EnsureOnboarding()=='declined',
   'S1: at the end of the scenario, after the informational Close, the repeated warning callbacks, the replays, Help and the Auto answers (not attributable to the Close alone), a bounded runtime continuation (1 s) reopens neither window, saves no seen state or suppression and keeps Auto OFF')
 end
end)

C.scenario('S2 Close (X) during the delay opens the informational Welcome; the Panel menu replays it',function()
 H=Fresh()
 local w=Warning()
 C.setup(w and w:IsShown(),'S2: fixture: the warning is shown')
 local before,savedClose=Counters(),Saved()
 w.close:Click()
 C.guard(Nexus.OverwriteWarning.EnsureOnboarding()=='declined' and NexusDB.overwriteWarnings==nil
  and Seen()==nil and Saved()==savedClose and not w:IsShown(),'S2: closing declines and saves nothing')
 -- DIRECT UX01 opening; the closing EXPECT below is DEPENDENT on it.
 local opened=C.expect(Informational(),'S2: Close opens the informational Welcome at once',Title())
 C.guard(Nexus.QuickStart.Show()==false and not Auto(),'S2: the consent-bound Show is still refused')
 local closed=Press('Close')
 C.expect(closed and not Shown() and not w:IsShown() and Seen()==nil and Saved()==savedClose,
  'S2: DEPENDENT on the S2 Close opening above: closing it records nothing and it stays closed',
  'direct opening held='..tostring(opened)..' closed='..tostring(closed))
 w.close:GetScript('OnClick')(w.close)
 C.guard(not Shown() and not w:IsShown() and Saved()==savedClose,'S2: a second Close of the answered warning opens nothing')
 -- The ... menu's real items (EasyMenu observed, not executed by the client).
 local items
 local realMenu=EasyMenu
 EasyMenu=function(list) items=list end
 Nexus.Panel.Show()
 local menu=NexusPanel and NexusPanel._menuBtn
 C.setup(menu~=nil,'S2: fixture: the Nexus panel menu button exists')
 if menu then menu:Click() end
 EasyMenu=realMenu
 local setup,help
 for _,item in ipairs(items or {}) do
  if item.text=='Setup / Welcome' then setup=item end
  if item.text=='Help / Getting Started' then help=item end
 end
 C.setup(help~=nil,'S2: fixture: the menu lists Help / Getting Started')
 C.expect(setup~=nil and type(setup.func)=='function','S2: the ... menu offers Setup / Welcome')
 local savedBefore=Saved()
 if setup then
  setup.func()
  C.expect(Shown() and Title():find('information only',1,true)~=nil,'S2: the menu item opens the informational setup',Title())
  if Shown() then WelcomeButton('Close'):Click() end
  C.expect(Seen()==nil and Saved()==savedBefore,'S2: and records nothing')
 end
 -- Help / Getting Started opens the first page directly.
 if help then
  Nexus.Help.Show('orbs');Nexus.Help.Hide()
  help.func()
  local page=NexusHelpWindow and NexusHelpWindow.page and NexusHelpWindow.page:GetText() or ''
  C.expect(NexusHelpWindow and NexusHelpWindow:IsShown() and page=='Page 1 / 7',
   'S2: Help / Getting Started opens page 1, not the page last shown',page)
  if NexusHelpWindow then NexusHelpWindow:Hide() end
 end
 Quiet('S2',before)
 -- Bounded runtime continuation after the genuine informational Close above,
 -- as at the end of S1: the effects were compared just now (Quiet), and only
 -- the navigation's own state is read after one second of harness time.
 if closed then
  H.Advance(1,.05)
  C.guard(not Shown() and not w:IsShown() and Seen()==nil and NexusDB.overwriteWarnings==nil
   and not Auto() and Nexus.OverwriteWarning.EnsureOnboarding()=='declined',
   'S2: at the end of the scenario, after the informational Close, the repeated warning Close, the menu replay and Help (not attributable to the Close alone), a bounded runtime continuation (1 s) reopens neither window, saves no seen state or suppression and keeps Auto OFF')
 end
end)

C.scenario('S3 Yes after reading: the first-time Welcome, then the replay and normal texts',function()
 H=Fresh()
 local w=Warning()
 C.setup(w and w:IsShown(),'S3: fixture: the first-launch warning is shown')
 H.Advance(5.01)
 local before=Counters()
 w.yes:Click()
 C.guard(Shown() and Title()=='Welcome to Nexus','S3: Yes resumes the first-time Welcome with its own title')
 C.guard(NexusDB.overwriteWarnings==nil and Seen()==nil,'S3: unchecked Yes saves neither acknowledgement')
 WelcomeButton('Close'):Click()
 C.guard(Seen()==true and not Shown(),'S3: Close records the first-time acknowledgement through the durable owner')
 local savedBefore=Saved()
 local shown=Replay()
 C.expect(shown==true and Shown() and Title():find('information only',1,true)~=nil,'S3: the seen Welcome can still be replayed',Title())
 if Shown() then WelcomeButton('Close'):Click() end
 C.expect(shown==true and Seen()==true and Saved()==savedBefore,'S3: the replay leaves the saved data exactly as it was')
 Nexus.QuickStart.Show()
 C.guard(Shown() and Title()=='Welcome to Nexus'
  and Hint()=='Reopen Help any time with /nexus help. Automation and Orb spending require separate explicit controls.',
  'S3: a deliberate Show presents the exact first-time title and hint',Title()..' | '..Hint())
 WelcomeButton('Close'):Click()
 Quiet('S3',before)
end)

C.scenario('S4 saved warning suppression: replay without any warning',function()
 NexusOverwriteWarning=nil;NexusQuickStart=nil
 H=F.Boot(F.Database({mutate=function(db) db.hasSeenQuickStart=true end}))
 C.setup(not (Warning() and Warning():IsShown()) and Nexus.OverwriteWarning.EnsureOnboarding()=='accepted',
  'S4: fixture: the saved suppression skips the warning')
 local before,savedBefore=Counters(),Saved()
 local shown=Replay()
 C.expect(shown==true and Shown(),'S4: Setup / Welcome opens with the saved suppression')
 if Shown() then WelcomeButton('Close'):Click() end
 C.guard(Saved()==savedBefore and NexusDB.overwriteWarnings.onboarding.suppressed==true,
  'S4: the suppression and every saved value are unchanged')
 Quiet('S4',before)
end)

C.scenario('S5 read-only saved data: the dismissal is not saved and says so',function()
 NexusOverwriteWarning=nil;NexusQuickStart=nil
 H=F.Boot(F.Database({mutate=function(db) db.settingsVersion={version=5} end}))
 C.setup(Nexus.Store.StateWriteStatus().mode~='durable','S5: fixture: the saved data is read-only')
 local before,savedBefore=Counters(),Saved()
 Nexus.QuickStart.ShowIfFirstTime()
 C.setup(Shown(),'S5: fixture: the first-time Welcome is shown')
 local said=Heard(function() WelcomeButton('Close'):Click() end)
 C.guard(not Shown() and Seen()==nil and Saved()==savedBefore,'S5: nothing is written for the dismissal')
 C.expect(said:find('cannot be saved right now',1,true)~=nil and said:find('offered again',1,true)~=nil,
  'S5: the dismissal says it is not saved and the Welcome may be offered again',said)
 local shown=Replay()
 said=Heard(function() if Shown() then WelcomeButton('Close'):Click() end end)
 C.expect(shown==true and Saved()==savedBefore and not said:find('cannot be saved',1,true),
  'S5: the replay opens and closes with no write and no unsaved notice (it records nothing)',said)
 Quiet('S5',before)
end)

C.scenario('S6 failed start-up: the Welcome is usable, nothing is claimed saved',function()
 NexusOverwriteWarning=nil;NexusQuickStart=nil
 local bad={settingsVersion=2,settings={autoPick=false},chars={},
  communityBuilds={ok={id='ok',title='Synthetic ok',author='Other-Realm',class='MAGE',postedAt=1,lastModified=1,
   ordinaryComplete=true,loadoutAvailable=true,lockedEchoes={},lockedComplete=true,
   echoes={{spellId=200001,quality=1,stacks=1}}}},
  buildCatalog={schemaVersion=1,catalogVersion='x',sourceVersion='x',unexpected='field'},
  overwriteWarnings={onboarding={version=1,suppressed=true},auto={version=1,suppressed=true}}}
 H=F.Boot(bad)
 C.setup(not Nexus.StartupStatus().coreReady,'S6: fixture: local start-up is withheld')
 local before,savedBefore=Counters(),Saved()
 Nexus.QuickStart.ShowIfFirstTime()
 C.setup(Shown(),'S6: fixture: the Welcome is shown')
 local said=Heard(function() WelcomeButton('Close'):Click() end)
 C.guard(Seen()==nil and Saved()==savedBefore,'S6: no acknowledgement is written')
 C.expect(said:find('cannot be saved right now',1,true)~=nil,'S6: the unsaved dismissal is stated',said)
 local shown=Replay()
 C.expect(shown==true and Shown(),'S6: Setup / Welcome still opens while start-up is withheld')
 if Shown() then WelcomeButton('Close'):Click() end
 C.guard(Saved()==savedBefore,'S6: still nothing written')
 Quiet('S6',before)
end)

-- S7 calls the warning's registered OnKeyDown script directly, as key(w,...),
-- and presses no native key. Native Escape capture by the warning, the
-- client's UISpecialFrames dispatch and its order, and whether that same
-- Escape also closes the Welcome it opens are NOT_RUN. A raw UISpecialFrames
-- hide is MODELLED offline (S8) as a plain Hide reaching the warning's
-- OnHide, which declines only; the native raw hide path is NOT_RUN. This is an
-- unverified native boundary, not a proven defect.
C.scenario('S7 Escape on the first-launch warning, as its registered OnKeyDown script called directly (native Escape NOT_RUN), opens the informational Welcome; other keys answer nothing',function()
 H=Fresh()
 local w=Warning()
 local key=w and w:GetScript('OnKeyDown')
 C.setup(w and w:IsShown() and type(key)=='function','S7: fixture: the warning is shown with its key handler')
 if type(key)~='function' then return end
 local before,savedBefore=Counters(),Saved()
 key(w,'ENTER')
 C.guard(w:IsShown() and Nexus.OverwriteWarning.EnsureOnboarding()=='pending' and not Shown(),
  'S7: another key answers nothing and opens nothing')
 key(w,'ESCAPE')
 C.guard(Nexus.OverwriteWarning.EnsureOnboarding()=='declined' and not w:IsShown()
  and NexusDB.overwriteWarnings==nil and Seen()==nil and Saved()==savedBefore,'S7: Escape (the key script called directly) declines and saves nothing')
 -- DIRECT UX01 opening; the closing EXPECT below is DEPENDENT on it.
 local opened=C.expect(Informational(),'S7: Escape (the key script called directly) opens the informational Welcome at once',Title())
 local closed=Press('Close')
 C.expect(closed and not Shown() and Seen()==nil and Saved()==savedBefore,
  'S7: DEPENDENT on the S7 Escape opening above: closing it records nothing and it stays closed',
  'direct opening held='..tostring(opened)..' closed='..tostring(closed))
 -- Not dependent on the opening: nothing is written after Escape either way.
 C.guard(Seen()==nil and Saved()==savedBefore,
  'S7: after Escape, whether or not a Welcome opened and closed, no seen state is saved and the saved data is unchanged')
 C.guard(Nexus.QuickStart.ShowIfFirstTime()==true and not Shown() and not w:IsShown(),
  'S7: the first-time check after the decline opens neither window')
 Quiet('S7',before)
 -- Bounded runtime continuation after the genuine informational Close above,
 -- as at the end of S1: the effects were compared just now (Quiet), and only
 -- the navigation's own state is read after one second of harness time.
 if closed then
  H.Advance(1,.05)
  C.guard(not Shown() and not w:IsShown() and Seen()==nil and NexusDB.overwriteWarnings==nil
   and not Auto() and Nexus.OverwriteWarning.EnsureOnboarding()=='declined',
   'S7: a bounded runtime continuation (1 s) after the informational Close reopens neither window, saves no seen state or suppression and keeps Auto OFF')
 end
end)

C.scenario('S8 a Hide from another route only declines the warning; the manual replay still opens',function()
 H=Fresh()
 local w=Warning()
 C.setup(w and w:IsShown(),'S8: fixture: the first-launch warning is shown')
 if not w then return end
 H.Advance(5.01)
 C.setup(w.no:IsEnabled(),'S8: fixture: choices enabled after reading')
 local before,savedBefore=Counters(),Saved()
 w:Hide()
 C.guard(Nexus.OverwriteWarning.EnsureOnboarding()=='declined' and not w:IsShown()
  and NexusDB.overwriteWarnings==nil and Seen()==nil and Saved()==savedBefore,'S8: the Hide declines and saves nothing')
 C.guard(not Shown(),'S8: the Hide opens no Welcome')
 w.no:GetScript('OnClick')(w.no)
 w:GetScript('OnHide')(w)
 C.guard(not Shown() and not w:IsShown(),'S8: later No or Hide callbacks of the hidden warning open nothing')
 local shown=Replay()
 C.guard(shown==true and Informational(),'S8: Setup / Welcome still replays the informational setup',Title())
 Press('Close')
 C.guard(not Shown() and Seen()==nil and Saved()==savedBefore,'S8: closing the replay writes nothing')
 Quiet('S8',before)
end)

C.scenario('S9 a No given after the saved root changed opens nothing and writes nothing',function()
 H=Fresh()
 local w=Warning()
 C.setup(w and w:IsShown(),'S9: fixture: the first-launch warning is shown')
 if not w then return end
 H.Advance(5.01)
 C.setup(w.no:IsEnabled(),'S9: fixture: choices enabled after reading')
 local before,root=Counters(),NexusDB
 local other=F.Database({mutate=function(db) db.overwriteWarnings=nil end})
 local rootBefore,otherBefore=F.Serialize(root),F.Serialize(other)
 NexusDB=other
 w.no:Click()
 local answer,hidden,welcome=Nexus.OverwriteWarning.EnsureOnboarding(),not w:IsShown(),Shown()
 local rootAfter,otherAfter=F.Serialize(root),F.Serialize(other)
 NexusDB=root
 C.guard(answer=='declined' and hidden,'S9: the stale No declines the warning')
 C.guard(not welcome,'S9: it opens no Welcome for the replacement saved root')
 C.guard(rootAfter==rootBefore and otherAfter==otherBefore,'S9: it writes neither saved root')
 Quiet('S9',before)
end)

C.scenario('S10 answers given after the character changed open nothing, accept nothing and save nothing',function()
 H=Fresh()
 local w=Warning()
 C.setup(w and w:IsShown(),'S10: fixture: the first-launch warning is shown')
 if not w then return end
 local store,realName=Nexus.Store,UnitName
 local function Owner()
  local ok,key=pcall(function() return store.CurrentOwnerKey() end)
  return ok and key or nil
 end
 local function Other() return 'SyntheticOther','Ebonhold' end
 local before,savedBefore,ownerBefore=Counters(),Saved(),Owner()
 UnitName=Other
 local ownerAfter=Owner()
 UnitName=realName
 if not C.setup(ownerBefore~=nil and ownerAfter~=ownerBefore,'S10: fixture: the harness UnitName seam changes the current owner key',
  tostring(ownerBefore)..' -> '..tostring(ownerAfter)) then return end
 UnitName=Other
 w.close:Click()
 local answer,hidden,welcome,saved=Nexus.OverwriteWarning.EnsureOnboarding(),not w:IsShown(),Shown(),Saved()
 UnitName=realName
 C.guard(answer=='declined' and hidden and saved==savedBefore,'S10: a Close given after the character changed declines and saves nothing')
 C.guard(not welcome,'S10: it opens no Welcome for the other character')
 local owner,accepted={},0
 local asked=Nexus.OverwriteWarning.RequestAuto(owner,function() accepted=accepted+1;return true end)
 C.setup(asked==false and w:IsShown() and w.yes:IsEnabled(),'S10: fixture: the Auto warning is open')
 local savedAuto=Saved()
 w.suppress:SetChecked(true)
 UnitName=Other
 w.yes:Click()
 local autoHidden,autoWelcome,autoSaved=not w:IsShown(),Shown(),Saved()
 UnitName=realName
 C.guard(accepted==0 and autoHidden and not autoWelcome and autoSaved==savedAuto and not Auto(),
  'S10: a stale Auto Yes with its opt-out ticked accepts nothing, saves nothing and opens no Welcome')
 Quiet('S10',before)
end)

-- G1-G5 (GUARD coverage): the informational route after an explicit No or
-- Close (X) fails closed when the optional QuickStart dependency is not
-- usable. Each case is its own real TOC boot with the real warning controls.
-- Only the public Nexus.QuickStart reference that the warning reads is
-- replaced, and only for the one real No (after a completed reading delay,
-- run with the real module) or Close click; the real module is put back at
-- once, also when that click raises (pcall). The warning, its upvalues and
-- the real QuickStart table are never changed. A table stand-in copies the
-- real module's public members, sets ShowSetup as the case says, and records
-- any call of ShowIfFirstTime or Show (the consent-bound continuation of a
-- Yes) while opening nothing. No time passes after the click, so effects are
-- compared at once. Added coverage of current behaviour; no failing-before
-- result is claimed.
local function StandIn(real,showSetup,calls)
 local quick={}
 for key,value in pairs(real) do quick[key]=value end
 quick.ShowSetup=showSetup
 quick.ShowIfFirstTime=function() calls.consent=calls.consent+1;return false end
 quick.Show=function() calls.consent=calls.consent+1;return false end
 return quick
end
local FAULTS={
 {name='Nexus.QuickStart unavailable (nil)',make=function() return nil end},
 {name='Nexus.QuickStart not a table (a number)',make=function() return 42 end},
 {name='QuickStart.ShowSetup missing',make=function(real,calls) return StandIn(real,nil,calls) end},
 {name='QuickStart.ShowSetup not a function (a string)',make=function(real,calls)
  return StandIn(real,'synthetic ShowSetup text',calls) end},
 {name='QuickStart.ShowSetup throwing',throws=true,make=function(real,calls)
  return StandIn(real,function() calls.thrown=calls.thrown+1;error('synthetic ShowSetup failure',0) end,calls) end},
}
for index,fault in ipairs(FAULTS) do
 for _,control in ipairs({'No','Close'}) do
  local tag='G'..index..' '..control
  C.scenario(tag..' with '..fault.name..': the real '..control..' declines, opens nothing, raises nothing and writes nothing',function()
   H=Fresh()
   local w=Warning()
   C.setup(w and w:IsShown(),tag..': fixture: the first-launch warning is shown')
   if not w then return end
   local button=control=='No' and w.no or w.close
   if control=='No' then
    H.Advance(5.01)
    if not C.setup(w.no:IsEnabled(),tag..': fixture: choices enabled after reading') then return end
   end
   local real=Nexus.QuickStart
   local realShowSetup=type(real)=='table' and real.ShowSetup or nil
   if not C.setup(type(realShowSetup)=='function',tag..': fixture: the real QuickStart module and its ShowSetup are loaded') then return end
   local calls={consent=0,thrown=0}
   local injected=fault.make(real,calls)
   local before,savedBefore=Counters(),Saved()
   Nexus.QuickStart=injected
   local ok,err=pcall(function() button:Click() end)
   Nexus.QuickStart=real
   C.setup(Nexus.QuickStart==real and real.ShowSetup==realShowSetup,tag..': fixture: the real QuickStart module is restored unchanged')
   if fault.throws then
    C.setup(calls.thrown==1,tag..': fixture: the injected ShowSetup failure is reached once',calls.thrown)
   end
   C.guard(ok,tag..': the click raises no error',err)
   C.guard(Nexus.OverwriteWarning.EnsureOnboarding()=='declined' and not w:IsShown() and Nexus.OverwriteWarning.IsOpen()==false,
    tag..': '..control..' declines the warning and hides it')
   C.guard(not Shown(),tag..': no Welcome opens')
   if type(injected)=='table' then
    C.guard(calls.consent==0,tag..': the consent-bound ShowIfFirstTime and Show are not called',calls.consent)
   end
   C.guard(NexusDB.overwriteWarnings==nil and Seen()==nil and Saved()==savedBefore,
    tag..': no suppression and no seen state are saved; the saved data is exactly unchanged')
   C.guard(not Auto(),tag..': Auto stays OFF')
   Quiet(tag,before)
  end)
 end
end

C.finish('(informational setup after an explicit No/Close/Escape and on replay; no consent, no saved write, no Auto change)')
