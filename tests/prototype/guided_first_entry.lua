-- First entry routing: the guided setup coach is the primary first-use window.
-- After an explicit first-launch Continue in a healthy session (a durable
-- saved-data owner after local start-up: QuickStart.CanRecordSeen), first use
-- is the actual guided setup coach (ui/GuidedSetup.lua), shown directly with
-- no legacy Welcome. Its deliberate Close or Escape is the first-use
-- dismissal, recorded with the existing durable policy; a raw hide, a coach
-- route that steps aside or a changed character records nothing, and closing
-- leaves guide steps not done. A first-launch No, X or Escape keeps the
-- information-only Welcome (no coach consent, Auto OFF, no acknowledgement).
-- Help's visible primary Setup / Welcome opens or resumes the coach directly;
-- the Setup checklist stays its own window. While an Auto warning waits for
-- its answer, Setup / Welcome says it did not open and to open it again;
-- answering the warning opens nothing (no queue). Read-only saved data keeps
-- the legacy first-time Welcome as its first-use window and writes nothing.
-- EXPECT: the new routing; it fails on f67ba51e, where Continue shows the
-- legacy Welcome and Help's Setup / Welcome opens the information-only one.
-- GUARD: existing durable-owner, no-write, no-consent and warning behaviour.
-- SETUP: fixture state only, healthy on f67ba51e too: where the coach is not
-- the first-use window there, its failed EXPECT is followed by the legacy
-- Welcome's own Close as a baseline control, so later checks still run.
-- Escape is modelled as the client does it (the listed UISpecialFrames frame
-- hidden, or the warning's registered key script called directly); native
-- dispatch is NOT_RUN. Real TOC boot and real warning, coach, Welcome and Help
-- controls; synthetic host services and saved data only. No native claim.
local V=dofile('tests/prototype/view_regression_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local C=V.Checker('guided_first_entry')
local H
local NAMES={'NexusQuickStart','NexusQuickStartEscape','NexusOverwriteWarning','NexusOverwriteWarningScroll',
 'NexusGuidedSetup','NexusGuidedSetupEscape','NexusHelpWindow','NexusSetupChecklist','NexusEditorFrame','NexusPanel'}
local function Clear() for _,n in ipairs(NAMES) do _G[n]=nil end end

-- Real first boot with no saved data and its real unread first-launch warning.
local function FirstBoot(tag)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;Clear()
 H=dofile('tests/prototype/harness.lua');H.keepOverwriteWarningPrompts=true
 H.Boot()
 local w=NexusOverwriteWarning
 return C.setup(Nexus.StartupStatus().coreReady==true and Nexus.OverwriteWarning.IsOpen()
  and w~=nil and w:IsShown() and w.yes:IsEnabled() and Nexus.QuickStart.CanRecordSeen()==true,
  tag..': fixture: real first boot, a durable owner and the unread first-launch warning past its reading period')
end
local function Coach() local g=NexusGuidedSetup;return g~=nil and g:IsShown() end
local function Welcome() local w=NexusQuickStart;return w~=nil and w:IsShown() end
local function Seen() return type(NexusDB)=='table' and rawget(NexusDB,'hasSeenQuickStart') or nil end
local function Auto() return Nexus.RecomputeStats().autoEnabled==true end
local function Saved() return type(NexusDB)=='table' and F.Serialize(NexusDB) or tostring(NexusDB) end
local function Step() local g=Nexus.GuidedSetup;return g and g.StepId() or nil end
local function Counts() return {actions=#H.actions,sent=#H.sent} end
local function Quiet(tag,b)
 C.guard(#H.actions==b.actions and #H.sent==b.sent and not Auto(),tag..': no game action, no send, Auto OFF',
  'actions='..#H.actions..' sent='..#H.sent)
end
local function Find(parent,text,exact)
 for _,c in ipairs(parent and parent.children or {}) do
  if c.kind=='Button' and c:IsShown() then
   local t=V.Plain(c:GetText() or '')
   if (exact and t==text) or (not exact and t:find(text,1,true)) then return c end
  end
 end
end
local function CoachButton(text) return Find(NexusGuidedSetup,text,true) end
local function CoachOption(text) return Find(NexusGuidedSetup,text,false) end
local function WelcomeButton(text) return Find(NexusQuickStart,text,true) end
local function HelpButton(text) return Find(NexusHelpWindow,text,true) end
local function Note() return NexusHelpWindow and NexusHelpWindow.note and V.Plain(NexusHelpWindow.note:GetText() or '') or '' end
local function Title() return NexusQuickStart and NexusQuickStart.title and V.Plain(NexusQuickStart.title:GetText() or '') or '' end
-- Settles first use through its deliberate Close: the coach (EXPECT) or, only
-- after that EXPECT failed, the legacy Welcome (baseline control).
local function CloseFirstUse(tag)
 local close=Coach() and CoachButton('Close') or nil
 if C.expect(close~=nil,tag..': first use is the coach, with its Close') then close:Click()
 else local legacy=Welcome() and WelcomeButton('Close') or nil;if legacy then legacy:Click() end end
 return C.setup(Seen()==true and not Coach() and not Welcome(),tag..': fixture: first use closed and recorded')
end

C.scenario('E1 explicit first-launch Continue opens the coach directly; its Close acknowledges first use only',function()
 if not FirstBoot('E1') then return end
 C.guard(not Coach() and not Welcome(),'E1: nothing opens over the unread warning')
 local b,saved=Counts(),Saved()
 NexusOverwriteWarning.yes:Click()
 C.guard(not Nexus.OverwriteWarning.IsOpen() and Nexus.OverwriteWarning.EnsureOnboarding()=='accepted','E1: Continue answers the warning')
 C.expect(Coach(),'E1: first use is the guided setup coach, shown directly')
 C.expect(not Welcome(),'E1: no legacy Welcome is shown')
 C.expect(Coach() and Step()=='welcome' and CoachOption('I am new')~=nil and CoachOption('Just explore')~=nil,
  'E1: the coach starts at its Welcome step with one choice per path',Step())
 C.guard(Seen()==nil and Saved()==saved,'E1: showing first use records and writes nothing')
 Quiet('E1',b)
 local close=Coach() and CoachButton('Close') or nil
 if not C.expect(close~=nil,'E1: the first-use coach offers Close') then return end
 close:Click()
 C.expect(not Coach() and Seen()==true,'E1: Close is the deliberate first-use dismissal, recorded through the durable owner')
 NexusDB.hasSeenQuickStart=nil
 C.guard(Saved()==saved,'E1: the acknowledgement is the only change')
 NexusDB.hasSeenQuickStart=true
 local sm=Nexus.GuidedSetup.Summary()
 C.guard(sm.complete==false and sm.trueNow==false and sm.wishlist=='todo' and sm.target=='todo' and sm.assign=='todo',
  'E1: closing completes no guide step')
 C.guard(Nexus.QuickStart.ShowIfFirstTime()==true and not Coach() and not Welcome(),'E1: first use is settled; nothing is offered again')
 Quiet('E1 close',b)
end)

C.scenario('E2 Escape on the first-use coach acknowledges first use as Close does',function()
 if not FirstBoot('E2') then return end
 NexusOverwriteWarning.yes:Click()
 local listed,coachListed=0,0
 for _,n in ipairs(UISpecialFrames) do
  if n=='NexusGuidedSetupEscape' then listed=listed+1 elseif n=='NexusGuidedSetup' then coachListed=coachListed+1 end
 end
 local escape=NexusGuidedSetupEscape
 C.expect(Coach() and escape~=nil and escape:IsShown() and listed==1 and coachListed==0,
  'E2: the coach is shown with its one listed Escape child (the coach itself is not listed)',listed..'/'..coachListed)
 if not (Coach() and escape) then return end
 local saved=Saved()
 escape:Hide() -- the client Escape: the listed frame is hidden
 C.expect(not Coach() and Seen()==true,'E2: Escape closes the coach and records first use')
 NexusDB.hasSeenQuickStart=nil
 C.guard(Saved()==saved,'E2: the acknowledgement is the only change')
 NexusDB.hasSeenQuickStart=true
 C.guard(not Welcome() and not Auto(),'E2: no Welcome; Auto stays OFF')
end)

C.scenario('E3 raw hides, a route that steps aside and a changed character do not acknowledge first use',function()
 if not FirstBoot('E3') then return end
 NexusOverwriteWarning.yes:Click()
 if not C.expect(Coach(),'E3: first use is the coach') then return end
 local b=Counts()
 NexusGuidedSetup:Hide() -- another window or a warning hides it: a raw hide
 C.expect(not Coach() and Seen()==nil,'E3: a raw hide records nothing')
 Nexus.QuickStart.ShowIfFirstTime()
 C.expect(Coach() and not Welcome(),'E3: the next first-use check offers the coach again, with no Welcome')
 local new=CoachOption('I am new');if new then new:Click() end
 local create=CoachButton('Create a new Wishlist')
 if not C.setup(Step()=='wishlist' and create~=nil,'E3: fixture: the Wishlist step offers Create a new Wishlist') then return end
 create:Click()
 C.setup(not Coach() and NexusEditorFrame~=nil and NexusEditorFrame:IsShown(),'E3: fixture: the coach stepped aside for the real Wishlist Editor')
 C.expect(Seen()==nil,'E3: stepping aside records nothing')
 Nexus.QuickStart.ShowIfFirstTime()
 C.expect(not Coach() and not Welcome(),'E3: a later first-use check opens nothing over the editor')
 Nexus.Help.Show('start')
 local setup=HelpButton('Setup / Welcome')
 C.setup(setup~=nil,'E3: fixture: Help shows its primary Setup / Welcome')
 if setup then setup:Click() end
 C.expect(Coach() and Step()=='wishlist' and not NexusHelpWindow:IsShown(),'E3: Help resumes the coach at the same step')
 local realName=UnitName
 UnitName=function() return 'SyntheticOther','Ebonhold' end
 local close=CoachButton('Close')
 local ok,err=pcall(function() if close then close:Click() end end)
 UnitName=realName
 C.setup(ok,'E3: fixture: the Close under another character ran',err)
 C.expect(not Coach() and Seen()==nil,'E3: a Close after the character changed records nothing')
 Nexus.QuickStart.ShowIfFirstTime()
 C.expect(Coach() and not Welcome(),'E3: first use is still offered as the coach')
 close=CoachButton('Close');if close then close:Click() end
 C.expect(not Coach() and Seen()==true,'E3: the matching character Close records it')
 Quiet('E3',b)
end)

C.scenario('E4 Help primary Setup / Welcome opens and resumes the coach directly; the checklist stays separate',function()
 if not FirstBoot('E4') then return end
 NexusOverwriteWarning.yes:Click()
 if not CloseFirstUse('E4') then return end
 local b,saved=Counts(),Saved()
 Nexus.Help.Show('start')
 local setup,checklist=HelpButton('Setup / Welcome'),HelpButton('Setup checklist')
 if not C.setup(NexusHelpWindow:IsShown() and setup~=nil and setup:GetScript('OnClick')~=nil and checklist~=nil,
  'E4: fixture: real Help with its primary setup row') then return end
 setup:Click()
 C.expect(Coach() and not Welcome() and not NexusHelpWindow:IsShown(),'E4: Setup / Welcome opens the coach directly, not the information-only Welcome')
 C.guard(Seen()==true and Saved()==saved and not Auto(),'E4: the replay keeps the seen flag, writes nothing and keeps Auto OFF')
 local explore=Coach() and CoachOption('Just explore') or nil
 if explore then explore:Click() end
 local close=Coach() and CoachButton('Close') or nil
 if close then close:Click() end
 C.guard(not Coach() and Seen()==true and Saved()==saved,'E4: closing the replay records nothing new and writes nothing')
 Nexus.Help.Show('start');setup:Click()
 C.expect(Coach() and Step()=='manual','E4: Setup / Welcome resumes the coach at the step it left',Step())
 Nexus.Help.Show('start');checklist:Click()
 C.guard(NexusSetupChecklist~=nil and NexusSetupChecklist:IsShown() and NexusSetupChecklist~=NexusGuidedSetup,
  'E4: Setup checklist opens its own read-only window')
 C.expect(Coach(),'E4: the coach stays open beside the checklist, not replaced')
 C.guard(Saved()==saved and Seen()==true,'E4: nothing is written by Help, the coach or the checklist')
 Quiet('E4',b)
end)

C.scenario('E5 an open Auto warning refuses Setup / Welcome truthfully; nothing is queued; an explicit retry opens the coach',function()
 if not FirstBoot('E5') then return end
 NexusOverwriteWarning.yes:Click()
 if not CloseFirstUse('E5') then return end
 local owner,accepted={},0
 Nexus.OverwriteWarning.RequestAuto(owner,function() accepted=accepted+1;return true end)
 local w=NexusOverwriteWarning
 if not C.setup(Nexus.OverwriteWarning.IsOpen() and w:IsShown() and w.yes:GetText()=='Yes','E5: fixture: a genuine Auto warning waits for its answer') then return end
 Nexus.Help.Show('start')
 local setup=HelpButton('Setup / Welcome')
 if not C.setup(setup~=nil and NexusHelpWindow:IsShown(),'E5: fixture: Help shows its primary Setup / Welcome') then return end
 local b=Counts()
 setup:Click()
 local note=Note()
 C.guard(not Coach() and not Welcome() and accepted==0 and Nexus.OverwriteWarning.IsOpen() and NexusHelpWindow:IsShown(),
  'E5: nothing opens over the warning, which keeps waiting; Help stays open')
 C.expect(note:find('did not open',1,true)~=nil and note:find('again',1,true)~=nil and note:find('opens after',1,true)==nil,
  'E5: the refusal says it did not open and to open it again, promising nothing after the answer',note)
 local ok,text=Nexus.Help.OpenGuide()
 C.expect(ok==false and type(text)=='string' and text:find('did not open',1,true)~=nil and text:find('opens after',1,true)==nil,
  'E5: OpenGuide returns the same truthful refusal',tostring(text))
 C.guard(not Coach() and accepted==0,'E5: the refused OpenGuide opens nothing and grants nothing')
 w.no:Click()
 C.guard(not Nexus.OverwriteWarning.IsOpen() and accepted==0 and not Auto(),'E5: explicit No declines the genuine Auto request')
 C.guard(not Coach() and not Welcome(),'E5: answering the warning opens no guide: nothing was queued')
 Quiet('E5',b)
 H.Advance(1,.05)
 C.guard(not Coach() and not Welcome(),'E5: nor after a bounded runtime continuation (1 s)')
 setup:Click()
 C.expect(Coach() and not Welcome() and not NexusHelpWindow:IsShown(),'E5: the explicit retry opens the coach')
 C.guard(Seen()==true and not Auto(),'E5: the retry keeps the seen flag and Auto OFF')
end)

for _,how in ipairs({'No','X','Escape'}) do
 C.scenario('E6 '..how..' declines first use to the information-only Welcome; no coach consent, no acknowledgement',function()
  local tag='E6 '..how
  if not FirstBoot(tag) then return end
  local w=NexusOverwriteWarning
  local b,saved=Counts(),Saved()
  if how=='No' then w.no:Click() elseif how=='X' then w.close:Click() else w:GetScript('OnKeyDown')(w,'ESCAPE') end
  C.guard(Nexus.OverwriteWarning.EnsureOnboarding()=='declined' and not w:IsShown(),tag..': the warning is declined')
  C.guard(Welcome() and Title()=='Nexus setup (information only)',tag..': the information-only Welcome opens',Title())
  C.guard(not Coach(),tag..': the decline opens no coach')
  C.guard(Seen()==nil and Saved()==saved,tag..': nothing is recorded or written')
  local close=WelcomeButton('Close')
  if close then close:Click() end
  C.guard(not Welcome() and Seen()==nil and Saved()==saved,tag..': closing it records and writes nothing')
  C.guard(Nexus.QuickStart.ShowIfFirstTime()==true and not Coach() and not Welcome(),tag..': the first-use check after the decline opens nothing')
  Nexus.Help.Show('start')
  local setup=HelpButton('Setup / Welcome')
  if setup then setup:Click() end
  C.expect(Coach() and not Welcome(),tag..': Help Setup / Welcome then opens the coach as a replay')
  C.guard(not Auto() and Nexus.OverwriteWarning.EnsureOnboarding()=='declined',tag..': opening it consents to nothing; Auto stays OFF')
  local coachClose=Coach() and CoachButton('Close') or nil
  if coachClose then coachClose:Click() end
  C.guard(not Coach() and Seen()==nil and Saved()==saved,tag..': closing that replay records no acknowledgement and writes nothing')
  Quiet(tag,b)
 end)
end

C.scenario('E7 read-only saved data keeps the legacy first-time Welcome; Help opens the coach; nothing is written',function()
 Clear()
 H=F.Boot(F.Database({mutate=function(db) db.settingsVersion={version=5} end}))
 local status=Nexus.Store.StateWriteStatus()
 if not C.setup(status.mode~='durable' and Nexus.QuickStart.CanRecordSeen()==false
  and Nexus.OverwriteWarning.EnsureOnboarding()=='accepted','E7: fixture: read-only owner; the saved onboarding answer is accepted',status.mode) then return end
 local b,saved=Counts(),Saved()
 Nexus.QuickStart.ShowIfFirstTime()
 C.guard(Welcome() and Title()=='Welcome to Nexus' and not Coach(),'E7: without a durable owner the first-time Welcome stays the first-use window',Title())
 local close=WelcomeButton('Close')
 if close then close:Click() end
 C.guard(not Welcome() and Seen()==nil and Saved()==saved,'E7: its Close writes nothing')
 Nexus.Help.Show('start')
 local setup=HelpButton('Setup / Welcome')
 if setup then setup:Click() end
 C.expect(Coach() and not Welcome(),'E7: Help Setup / Welcome opens the coach')
 local coachClose=Coach() and CoachButton('Close') or nil
 if coachClose then coachClose:Click() end
 C.guard(not Coach() and Seen()==nil and Saved()==saved,'E7: closing it records and writes nothing')
 Quiet('E7',b)
end)

C.finish('(first entry: a healthy first use is the coach; legacy Welcome secondary; no consent, no queue; offline only, native NOT_RUN)')
