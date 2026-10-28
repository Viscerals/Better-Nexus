-- First entry routing: the guided setup coach is the primary first-use window.
-- After an explicit first-launch Continue in a healthy session (a durable
-- saved-data owner after local start-up: QuickStart.CanRecordSeen), first use
-- is the actual guided setup coach (ui/GuidedSetup.lua), shown directly with
-- no legacy Welcome. Its deliberate Close or Escape is the first-use
-- dismissal, recorded with the existing durable policy; a raw hide, a coach
-- route that steps aside or a changed character records nothing, and closing
-- leaves guide steps not done. Help reopen retains the first-use Close, while
-- editor/import Cancel and Escape resume without claiming a save. The
-- Wishlist step checks a pasted code in place, read-only; only its separate
-- Open it as a draft reaches the editor's naming dialog (E10-E13). After
-- start-up each Help topic's Open action reaches its real screen (E15). A first-launch No, X or Escape keeps the
-- information-only Welcome (no coach consent, Auto OFF, no acknowledgement).
-- Help's visible primary Setup / Welcome opens or resumes the coach directly;
-- the Setup checklist stays its own window. While an Auto warning waits for
-- its answer, Setup / Welcome says it did not open and to open it again;
-- answering the warning opens nothing (no queue). Read-only saved data keeps
-- the legacy first-time Welcome as its first-use window and writes nothing.
-- EXPECT: the new routing; it fails on f67ba51e, where Continue shows the
-- legacy Welcome and Help's Setup / Welcome opens the information-only one.
-- E14's EXPECTs (Help's start page names each setup route by the ... menu
-- label that opens it) fail on dfcca312, whose page called the
-- information-only view Setup / Welcome and put Guided setup inside it.
-- GUARD: existing durable-owner, no-write, no-consent and warning behaviour.
-- Showing, closing and Help write nothing; navigating the coach writes only
-- its own kept place (E4 compares every other saved byte and the place's
-- fields, with the place's one record in the Store authority bundle mirror of
-- the same row; guided_setup_resume covers the place itself).
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
-- The saved data without the guide's own kept place (core/GuidedSetup.lua
-- PLACE_KEY in the current character's row), that place, and the same key in
-- the Store authority bundle's mirror of that row. Navigating the coach keeps
-- its place there (the guided design's per-character guide record). The
-- bundle's storeData.chars is the same chars table the session admitted
-- (core/Store.lua StoreData.Build), so the one record is serialized twice;
-- every other saved byte must stay as it was.
local function SavedWithoutPlace()
 if type(NexusDB)~='table' then return tostring(NexusDB),nil end
 local copy=assert(loadstring('return '..F.Serialize(NexusDB)))()
 local key=Nexus.GuidedSetup and Nexus.GuidedSetup.PLACE_KEY
 local owner=Nexus.Store.CurrentOwnerKey()
 local function Row(chars) local row=type(chars)=='table' and owner and chars[owner] or nil;return type(row)=='table' and row or nil end
 local data=type(copy.authorityBundle)=='table' and copy.authorityBundle.storeData or nil
 local row,mirror=Row(copy.chars),Row(type(data)=='table' and data.chars or nil)
 local place=row and key and row[key] or nil
 local mirrored=mirror and key and mirror[key] or nil
 if key then
  if row then row[key]=nil end
  if mirror then mirror[key]=nil end
 end
 return F.Serialize(copy),place,mirrored
end
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
local function On(b) return b~=nil and b:IsEnabled() end
-- The designed Welcome records a choice; Continue then moves on.
local function Continue() local b=Coach() and CoachButton('Continue') or nil;if b then b:Click() end end
local function WelcomeButton(text) return Find(NexusQuickStart,text,true) end
local function HelpButton(text) return Find(NexusHelpWindow,text,true) end
local function Note() return NexusHelpWindow and NexusHelpWindow.note and V.Plain(NexusHelpWindow.note:GetText() or '') or '' end
local function Title() return NexusQuickStart and NexusQuickStart.title and V.Plain(NexusQuickStart.title:GetText() or '') or '' end
-- Settles first use through its deliberate Close: the coach (EXPECT) or, only
-- after that EXPECT failed, the legacy Welcome (baseline control).
local function CloseFirstUse(tag)
 local close=Coach() and CoachButton('X') or nil
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
 C.expect(Coach() and Step()=='welcome' and CoachOption('New to Nexus')~=nil and CoachOption('Just look around')~=nil,
  'E1: the coach starts at its Welcome step with one choice per path',Step())
 C.guard(Seen()==nil and Saved()==saved,'E1: showing first use records and writes nothing')
 Quiet('E1',b)
 local close=Coach() and CoachButton('X') or nil
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
 local new=CoachOption('New to Nexus');if new then new:Click() end;Continue()
 local create=CoachButton('Start an empty Wishlist')
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
 local close=CoachButton('X')
 local ok,err=pcall(function() if close then close:Click() end end)
 UnitName=realName
 C.setup(ok,'E3: fixture: the Close under another character ran',err)
 C.expect(not Coach() and Seen()==nil,'E3: a Close after the character changed records nothing')
 Nexus.QuickStart.ShowIfFirstTime()
 C.expect(Coach() and not Welcome(),'E3: first use is still offered as the coach')
 close=CoachButton('X');if close then close:Click() end
 C.expect(not Coach() and Seen()==true,'E3: the matching character Close records it')
 Quiet('E3',b)
end)

C.scenario('E4 Help primary Setup / Welcome opens and resumes the coach directly; the checklist stays separate',function()
 if not FirstBoot('E4') then return end
 NexusOverwriteWarning.yes:Click()
 if not CloseFirstUse('E4') then return end
 local b,saved,full=Counts(),SavedWithoutPlace(),Saved()
 Nexus.Help.Show('start')
 local setup,checklist=HelpButton('Setup / Welcome'),HelpButton('Setup checklist')
 if not C.setup(NexusHelpWindow:IsShown() and setup~=nil and setup:GetScript('OnClick')~=nil and checklist~=nil,
  'E4: fixture: real Help with its primary setup row') then return end
 setup:Click()
 C.expect(Coach() and not Welcome() and not NexusHelpWindow:IsShown(),'E4: Setup / Welcome opens the coach directly, not the information-only Welcome')
 C.guard(Seen()==true and Saved()==full and not Auto(),'E4: the replay keeps the seen flag, writes nothing and keeps Auto OFF')
 local explore=Coach() and CoachOption('Just look around') or nil
 if explore then explore:Click() end
 Continue()
 local close=Coach() and CoachButton('X') or nil
 if close then close:Click() end
 -- Narrowed (not removed) by the persisted guide place: the navigation's one
 -- sanctioned write is the guide's own place record; every other byte is
 -- compared exactly as before, and the record holds no result.
 local rest,place,mirrored=SavedWithoutPlace()
 C.guard(not Coach() and Seen()==true and rest==saved,'E4: closing the replay records nothing new; nothing but the guide\'s own place is written')
 C.guard(mirrored==nil or F.Serialize(mirrored)==F.Serialize(place),
  'E4: the authority bundle mirror of the row holds the same place record, nothing else',F.Serialize(mirrored))
 local fields={}
 for k in pairs(type(place)=='table' and place or {}) do fields[#fields+1]=tostring(k) end
 table.sort(fields)
 C.expect(type(place)=='table' and table.concat(fields,',')=='path,step,version' and place.version==1
  and place.step=='manual' and place.path=='explore','E4: the kept place is the step and the path only, no result',
  F.Serialize(place))
 Nexus.Help.Show('start');setup:Click()
 C.expect(Coach() and Step()=='manual','E4: Setup / Welcome resumes the coach at the step it left',Step())
 Nexus.Help.Show('start');checklist:Click()
 C.guard(NexusSetupChecklist~=nil and NexusSetupChecklist:IsShown() and NexusSetupChecklist~=NexusGuidedSetup,
  'E4: Setup checklist opens its own read-only window')
 C.expect(Coach(),'E4: the coach stays open beside the checklist, not replaced')
 C.guard(SavedWithoutPlace()==saved and Seen()==true,'E4: nothing else is written by Help, the coach or the checklist')
 C.guard(F.Serialize((select(2,SavedWithoutPlace())))==F.Serialize(place),'E4: reopening and the checklist leave the kept place as it was')
 Quiet('E4',b)
end)

C.scenario('E8 a raw hide followed by Help reopening keeps the first-use Close acknowledgement',function()
 if not FirstBoot('E8') then return end
 NexusOverwriteWarning.yes:Click()
 if not C.setup(Coach() and Seen()==nil,'E8: fixture: first-use coach open and unseen') then return end
 Nexus.GuidedSetupUI.Hide()
 C.guard(not Coach() and Seen()==nil,'E8: raw hide does not acknowledge first use')
 Nexus.Help.Show('start')
 local setup=HelpButton('Setup / Welcome')
 if not C.setup(setup~=nil,'E8: fixture: Help primary setup action exists') then return end
 setup:Click()
 C.expect(Coach() and Seen()==nil,'E8: Help reopens the same first-use coach without recording a dismissal')
 local close=CoachButton('X')
 if close then close:Click() end
 C.expect(not Coach() and Seen()==true,'E8: deliberate Close after Help reopen acknowledges first use')
end)

C.scenario('E9 canceling first-use Wishlist creation returns to the same coach',function()
 if not FirstBoot('E9') then return end
 NexusOverwriteWarning.yes:Click()
 if not C.setup(Coach(),'E9: fixture: first-use coach open') then return end
 local b=Counts()
 local new=CoachOption('New to Nexus');if new then new:Click() end;Continue()
 local create=CoachButton('Start an empty Wishlist')
 if not C.setup(Step()=='wishlist' and create~=nil,'E9: fixture: create action on Wishlist step') then return end
 create:Click()
 if not C.setup(not Coach() and NexusEditorFrame and NexusEditorFrame:IsShown(),
  'E9: fixture: editor opened and coach stepped aside') then return end
 NexusEditorFrame:Hide() -- Cancel/close without saving a draft
 C.expect(Coach() and Step()=='wishlist' and Seen()==nil,
  'E9: closing the unsaved editor returns the coach without completing or acknowledging')
 C.expect(Nexus.GuidedSetup.State().awaitSave==nil,
  'E9: an abandoned editor no longer accepts a later unrelated save receipt')
 Quiet('E9',b)
end)

-- E10-E13: the original guided design's Wishlist step (paste field, Check
-- code, inline outcome) over the editor's real read-only check
-- (WishlistEditor.CheckImportCode). Only the separate Open it as a draft
-- enters the editor's guarded import (ImportEBH1String: its naming dialog,
-- then a draft the player saves there). Each scenario keeps the earlier
-- popup route's safety checks: no completion, no first-use acknowledgement
-- and no later unrelated save receipt accepted.
local function Box() return NexusGuidedSetup and NexusGuidedSetup.importBox end
local function CoachText() return V.Plain(Nexus.GuidedSetupUI.VisibleText() or '') end
local function Code() return Nexus.Codec.EncodeEBH1({{spellId=201175,quality=0,stacks=1,locked=false}},'MAGE','Starter') end
local function Paste(text) local box=Box();if box then box:SetText(text) end end
local function Check() local b=CoachButton('Check code');if b then b:Click() end;return b~=nil end
local function Popup(which) return H.popup~=nil and H.popup.which==which end
-- The Wishlist step of a first-use New to Nexus path, with its paste field
-- chosen. Returns false (after a failed SETUP) when it cannot be reached.
local function PasteStep(tag)
 if not FirstBoot(tag) then return false end
 NexusOverwriteWarning.yes:Click()
 if not C.setup(Coach(),tag..': fixture: first-use coach open') then return false end
 local new=CoachOption('New to Nexus');if new then new:Click() end;Continue()
 local import=CoachButton('Paste a Wishlist code')
 if not C.setup(Step()=='wishlist' and import~=nil,tag..': fixture: the Wishlist step offers Paste a Wishlist code') then return false end
 H.popup=nil
 import:Click()
 return true
end
-- A later save reported by some other editor route: never this step's.
local function Unrelated(tag)
 Nexus.GuidedSetup.Note('save',{kind='kept',name='Unrelated save',key='unrelated'})
 C.expect(Nexus.GuidedSetup.State().wishlist==nil and Nexus.GuidedSetup.Summary().wishlist~='done',
  tag..': a later unrelated save receipt is not taken as this step\'s Wishlist')
end

C.scenario('E10 the in-step paste field checks a code read-only: no popup, draft, save or acknowledgement',function()
 if not PasteStep('E10') then return end
 local b,rest=Counts(),SavedWithoutPlace()
 local G=Nexus.GuidedSetup
 local receipts=#G.Receipts()
 local box=Box()
 C.expect(Coach() and Step()=='wishlist' and box~=nil and box:IsShown() and CoachButton('Check code')~=nil
  and CoachButton('Open it as a draft')==nil and H.popup==nil,
  'E10: Paste a Wishlist code opens the field and Check code inside the step; no popup, the coach stays')
 C.expect(not On(CoachButton('Continue')) and CoachText():find('Paste a code and check it',1,true)~=nil,
  'E10: Continue waits on the code and says what to do',CoachText())
 Check()
 C.expect(Coach() and CoachText():find('Not checked: paste a code first',1,true)~=nil and H.popup==nil,
  'E10: an empty field is said as not checked, never accepted or rejected',CoachText())
 Paste(Code())
 Check()
 local text=CoachText()
 C.expect(text:find('Code read: Starter',1,true)~=nil and text:find('Nothing is imported or saved yet',1,true)~=nil,
  'E10: a valid code reads inline with its name and says nothing is imported yet',text)
 C.expect(CoachButton('Open it as a draft')~=nil and On(CoachButton('Open it as a draft')) and not On(CoachButton('Continue')),
  'E10: the separate Open it as a draft is offered; a checked code is not a Wishlist, so Continue still waits')
 C.expect(Coach() and H.popup==nil and not (NexusEditorFrame and NexusEditorFrame:IsShown()),
  'E10: checking opens no popup and no editor')
 C.expect(G.State().awaitSave==nil and G.State().draft==nil and G.State().wishlist==nil and #G.Receipts()==receipts,
  'E10: checking arms no save, opens no draft, chooses nothing and reports no receipt')
 local escape=box and box:GetScript('OnEscapePressed')
 if escape then escape(box) end
 C.expect(Coach() and Step()=='wishlist' and box:GetText()==Code() and CoachButton('Open it as a draft')~=nil,
  'E10: Escape in the field only gives the keyboard back; the coach and the check stay')
 Paste(Code():sub(1,12))
 C.expect(CoachButton('Open it as a draft')==nil and CoachText():find('Code read:',1,true)==nil,
  'E10: a changed code drops the earlier check, which belonged to the exact text it read',CoachText())
 Unrelated('E10')
 C.guard(Seen()==nil and SavedWithoutPlace()==rest,'E10: the field, its checks and Escape record and write nothing',
  'seen='..tostring(Seen()))
 Quiet('E10',b)
end)

C.scenario('E11 Open it as a draft hands the checked code to the naming dialog; its Cancel and Escape return the unfinished coach',function()
 if not PasteStep('E11') then return end
 local b=Counts()
 local G=Nexus.GuidedSetup
 Paste(Code());Check()
 local open=CoachButton('Open it as a draft')
 if not C.setup(open~=nil,'E11: fixture: the checked code offers Open it as a draft') then return end
 open:Click()
 local dialog=StaticPopupDialogs.NEXUS_NAME_IMPORTED_WISHLIST
 if not C.setup(Popup('NEXUS_NAME_IMPORTED_WISHLIST') and dialog and not Coach(),
  'E11: fixture: the editor\'s own naming dialog opened and the coach stepped aside') then return end
 C.expect(not Popup('NEXUS_IMPORT_WISHLIST') and G.State().awaitSave~=nil and G.State().wishlist==nil,
  'E11: the draft action goes straight to naming (no second paste popup); only now does the step wait for a save')
 C.expect(H.popup.data and H.popup.data.name=='Starter' and #H.popup.data.entries==1,
  'E11: the naming dialog holds the very code that was checked')
 if dialog.OnCancel then dialog.OnCancel(H.popup.frame) end
 C.expect(Coach() and Step()=='wishlist' and Seen()==nil and G.State().awaitSave==nil,
  'E11: canceling the naming popup returns the unfinished coach with no pending save')
 C.expect(not On(CoachButton('Continue')) and CoachButton('Open it as a draft')~=nil,
  'E11: back in the step the checked code can be opened again; nothing counts as done')
 Unrelated('E11 cancel')
 open=CoachButton('Open it as a draft')
 if open then H.popup=nil;open:Click() end
 if C.setup(Popup('NEXUS_NAME_IMPORTED_WISHLIST') and not Coach(),
  'E11: fixture: naming popup reopened from the same checked code') then
  dialog.EditBoxOnEscapePressed(H.popup.frame.editBox)
  C.expect(Coach() and Step()=='wishlist' and Seen()==nil and G.State().awaitSave==nil,
   'E11: naming Escape also returns the unfinished coach without acknowledgement')
  Unrelated('E11 Escape')
 end
 Quiet('E11',b)
end)

C.scenario('E12 a malformed, cut-off or changed code never leaves the step or opens anything',function()
 if not PasteStep('E12') then return end
 local b=Counts()
 local G=Nexus.GuidedSetup
 Paste('not an EBH1 code');Check()
 C.expect(Coach() and Step()=='wishlist' and CoachText():find("That code didn't work",1,true)~=nil
  and CoachText():find('Nothing was imported',1,true)~=nil and CoachButton('Open it as a draft')==nil and H.popup==nil,
  'E12: a malformed code is refused inline; no draft action, no popup',CoachText())
 C.expect(Seen()==nil and G.State().awaitSave==nil and G.State().wishlist==nil,
  'E12: the refused code completes nothing and arms no save')
 local limit=Nexus.WishlistEditor.IMPORT_MAX_LETTERS
 Paste(string.rep('A',limit+10));Check()
 C.expect(Box():GetText()==string.rep('A',limit) and CoachText():find(limit..'-letter limit',1,true)~=nil
  and CoachButton('Open it as a draft')==nil,'E12: a code cut at the field\'s limit is refused as possibly cut off',CoachText())
 -- The draft action reads the field again: a text the field did not report
 -- (set under it, modelled; native field events are NOT_RUN) is checked anew.
 Paste(Code());Check()
 local open=CoachButton('Open it as a draft')
 if C.setup(open~=nil,'E12: fixture: a valid code offers Open it as a draft') then
  Box().text='not an EBH1 code'
  open:Click()
  C.expect(Coach() and H.popup==nil and CoachText():find('no longer reads as a Wishlist code',1,true)~=nil
   and G.State().awaitSave==nil,'E12: a code that changed after its check opens nothing and says so',CoachText())
 end
 Unrelated('E12')
 Quiet('E12',b)
end)

C.scenario('E13 an opened imported draft is not a saved Wishlist; closing it returns the same unfinished coach',function()
 if not PasteStep('E13') then return end
 local b=Counts()
 local G=Nexus.GuidedSetup
 Paste(Code());Check()
 local open=CoachButton('Open it as a draft')
 if not C.setup(open~=nil,'E13: fixture: the checked code offers Open it as a draft') then return end
 open:Click()
 if not C.setup(Popup('NEXUS_NAME_IMPORTED_WISHLIST'),'E13: fixture: the naming dialog opened') then return end
 StaticPopupDialogs.NEXUS_NAME_IMPORTED_WISHLIST.OnAccept(H.popup.frame,H.popup.data)
 if not C.setup(NexusEditorFrame and NexusEditorFrame:IsShown() and not Coach(),
  'E13: fixture: naming it opened an unsaved draft editor') then return end
 C.expect(G.State().draft~=nil and G.State().wishlist==nil and G.Summary().wishlist=='draft',
  'E13: the open draft is reported as a draft, not as a chosen or saved Wishlist')
 NexusEditorFrame:Hide()
 C.expect(Coach() and Step()=='wishlist' and Seen()==nil and G.State().awaitSave==nil,
  'E13: abandoning the imported draft returns the coach without claiming a save or dismissal')
 C.expect(not On(CoachButton('Continue')) and G.Summary().wishlist~='done',
  'E13: the step stays unfinished after the draft is closed')
 Unrelated('E13')
 Quiet('E13',b)
end)

-- The Options menu decides which label opens which window: each Setup item of
-- its real top level (direct choices since native QA test.163008) is run once
-- with the three window owners spied, so the labels come from the menu's own
-- handlers, not from this file.
C.scenario('E14 Help Getting started names the coach and the information-only view by their menu labels',function()
 if not FirstBoot('E14') then return end
 NexusOverwriteWarning.yes:Click()
 if not CloseFirstUse('E14') then return end
 local b,saved=Counts(),Saved()
 local ok,top=pcall(Nexus.Panel.MoreMenuItems)
 local items=ok and type(top)=='table' and top or nil
 if not C.setup(items~=nil,'E14: fixture: the real Options menu lists its items',tostring(top)) then return end
 local quick,ui=Nexus.QuickStart,Nexus.GuidedSetupUI
 local realSetup,realList,realShow=quick.ShowSetup,quick.ShowChecklist,ui.Show
 local coachLabel,infoLabel
 for _,item in ipairs(items) do
  if type(item.text)=='string' and item.text:find('Setup',1,true) and type(item.func)=='function' then
   local opened
   quick.ShowSetup=function() opened='info';return true end
   quick.ShowChecklist=function() opened='checklist' end
   ui.Show=function() opened='coach';return true end
   local ran=pcall(item.func)
   quick.ShowSetup,quick.ShowChecklist,ui.Show=realSetup,realList,realShow
   if ran and opened=='coach' then coachLabel=item.text elseif ran and opened=='info' then infoLabel=item.text end
  end
 end
 if not C.setup(coachLabel~=nil and infoLabel~=nil,'E14: fixture: the menu has a coach entry and an information-only entry',
  tostring(coachLabel)..' / '..tostring(infoLabel)) then return end
 Nexus.Help.Show('start')
 local text=V.Plain(NexusHelpWindow.body:GetText() or '')
 NexusHelpWindow:Hide()
 C.expect(text:find(coachLabel..' opens Guided setup',1,true)~=nil,'E14: the start page says '..coachLabel..' opens Guided setup',text)
 C.expect(text:find(infoLabel,1,true)~=nil,'E14: the start page names the information-only view '..infoLabel,text)
 C.expect(not text:find('as '..coachLabel,1,true) and not text:find('button in '..coachLabel,1,true),
  'E14: the start page neither calls the information-only view '..coachLabel..' nor puts Guided setup inside it',text)
 C.guard(Saved()==saved and Seen()==true and not Coach() and not Welcome(),'E14: reading the menu and Help writes and opens nothing')
 Quiet('E14',b)
end)

-- E15: after start-up, each Help topic's one Open action (Help.Topics) is
-- clicked for real. Owners without a fixture-named frame are wrapped and pass
-- through to their real Show, so the call, its section and its result are
-- observed; the windows themselves open for real. help.lua covers the routes
-- that wait during loading. Native window drawing is NOT_RUN.
C.scenario('E15 after start-up each Help topic opens its real screen in Help\'s place; nothing is assigned, sent or turned on',function()
 if not FirstBoot('E15') then return end
 NexusOverwriteWarning.yes:Click()
 if not CloseFirstUse('E15') then return end
 local b,G=Counts(),Nexus.GuidedSetup
 local function Assignments()
  local st=Nexus.Store.State() or {}
  return F.Serialize(type(st.loadoutWishlists)=='table' and st.loadoutWishlists or {})
 end
 local assigned,summary=Assignments(),F.Serialize(G.Summary())
 local function Settings() return _G.NexusSettingsWindow~=nil and NexusSettingsWindow:IsShown() end
 local cases={
  {id='start',shown=Coach,close=function() NexusGuidedSetup:Hide() end},
  {id='wishlists',shown=function() return _G.NexusEditorFrame~=nil and NexusEditorFrame:IsShown() end,
   close=function() NexusEditorFrame:Hide() end},
  {id='rolling',owner=Nexus.SettingsWindow,arg='automation',shown=Settings,close=function() Nexus.SettingsWindow.Hide() end},
  {id='sharing',owner=Nexus.SettingsWindow,arg='sync',shown=Settings,close=function() Nexus.SettingsWindow.Hide() end},
  {id='orbs',shown=function() return _G.NexusOrbPanel~=nil and NexusOrbPanel:IsShown() end,
   close=function() NexusOrbPanel:Hide() end},
  {id='troubleshooting',owner=Nexus.SupportReportUI},
  {id='about',owner=Nexus.LogViewer},
 }
 for _,case in ipairs(cases) do
  local topic=Nexus.Help.Topics[case.id]
  Nexus.Help.Show(case.id)
  local help=NexusHelpWindow
  if not C.setup(topic and help:IsShown() and help.topicOpen:GetText()==topic.open,'E15: fixture: Help shows the '..case.id..' topic card') then return end
  local seen,real={n=0},nil
  if case.owner then
   real=case.owner.Show
   case.owner.Show=function(...) seen.n=seen.n+1;seen.arg=(...);return real(...) end
  end
  local ok,err=pcall(function() help.topicOpen:Click() end)
  if case.owner then case.owner.Show=real end
  C.expect(ok and not help:IsShown() and (not case.shown or case.shown())
   and (not case.owner or (seen.n==1 and (case.arg==nil or seen.arg==case.arg))),
   'E15: '..topic.open..' opens its real screen in Help\'s place',tostring(err)..' note='..Note()..' calls='..seen.n
   ..' arg='..tostring(seen.arg))
  if case.close then pcall(case.close) end
 end
 C.guard(Seen()==true and Assignments()==assigned and F.Serialize(G.Summary())==summary,
  'E15: the topic routes record, assign and complete nothing')
 Quiet('E15',b)
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
  local coachClose=Coach() and CoachButton('X') or nil
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
 local coachClose=Coach() and CoachButton('X') or nil
 if coachClose then coachClose:Click() end
 C.guard(not Coach() and Seen()==nil and Saved()==saved,'E7: closing it records and writes nothing')
 Quiet('E7',b)
end)

C.finish('(first entry: a healthy first use is the coach; legacy Welcome secondary; no consent, no queue; offline only, native NOT_RUN)')
