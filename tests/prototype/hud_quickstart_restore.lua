-- F-S4-4 (P3) HUD restoration regression. The attached Wishlist editor
-- suppresses the HUD while shown. Current Panel excludes the unattached
-- informational Welcome and first-use coach from its menu-suppression test,
-- so closing the editor restores a wanted HUD even if either remains open.
-- Q1 and Q1b check that immediate restoration and that later Close keeps it;
-- reversed order, a deliberately hidden HUD, and /nexus panel are also
-- guarded. This is the current invariant, not a claim that the old failing
-- first-run QuickStart sequence still exists. Real TOC boot and controls,
-- synthetic Saved Build, offline only; no native popup timing claim.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('hud_quickstart_restore')
local H=F.Boot(F.Database({}),function(h) h.playerLevel=80 end)
local function HideQuickStart() if NexusQuickStart and NexusQuickStart:IsShown() then NexusQuickStart:Hide() end end
HideQuickStart()
H.perks.serverBuildSlots[2]={name='Artificial active build',verified=true,
 echoes={{spellId=200001,quality=0,stacks=1}}}
H.perks.serverActiveSlot=2;H.Notify();Nexus.GameAdapter.Poll()
Nexus.Panel.Show()
for _=1,300 do H.Advance(.05,.05) end
HideQuickStart()
local function Facts() return Nexus.Panel.VisibilityFacts() end
local function FactText()
 local f=Facts()
 return 'wanted='..printable(f.wanted)..' shown='..printable(f.shown)..' suppressed='..printable(f.menuSuppressed)
  ..' committed='..printable(f.committed)
end
local function Stock()
 local s=Nexus.ServerStatus.VisibilityFacts()
 return printable(s.mode)..'/'..printable(s.replacementAvailable)..'/'..printable(s.replacing)
end
local f=Facts()
C.setup(f.ready and f.committed and f.wanted and f.shown and not f.menuSuppressed,'fixture: the runtime committed and shows the wanted HUD',
 FactText())
C.setup(not rawget(NexusDB,'hasSeenQuickStart'),'fixture: the first-run profile has not acknowledged QuickStart')
local stock=Stock()

local editor
-- The real minimap right-click opens the attached Wishlist editor.
local function OpenEditor(tag)
 local minimap=NexusMinimapButton
 if minimap then minimap:GetScript('OnClick')(minimap,'RightButton') end
 H.Advance(.2)
 editor=NexusEditorFrame
 return C.setup(editor~=nil and editor:IsShown() and Facts().menuSuppressed and not Facts().shown,
  tag..': fixture: the minimap right-click opens the editor and suppresses the HUD',FactText())
end
local function CloseQuickStart(tag)
 local quick=NexusQuickStart
 local function Control(caption)
  return quick and V.Frame(H,function(x)
   return x:GetParent()==quick and x:GetText()==caption and x:GetScript('OnClick')~=nil
  end) or nil
 end
 -- The exact "Close" caption is healthy behaviour (EXPECT). Only after that
 -- EXPECT fails may the real legacy "Later" control (same parent, its own
 -- OnClick) dismiss QuickStart, so the original checks still run; the failed
 -- EXPECT stays in the final failure set.
 local later=Control('Close')
 if quick and not C.expect(later~=nil,tag..': the QuickStart dismiss control reads exactly "Close"') then
  later=Control('Later')
 end
 C.setup(later~=nil,tag..': fixture: the real Close control exists (legacy Later only after the failed Close EXPECT)')
 if later then later:Click() end
 H.Advance(.5)
 return C.setup(quick~=nil and not quick:IsShown(),tag..': fixture: that real control dismisses QuickStart')
end
-- Back to a shown, wanted, unsuppressed HUD: an attached window opened and
-- closed with no QuickStart shown, as a player would recover.
local function Reset(tag)
 HideQuickStart()
 Nexus.WishlistEditor.Show()
 if NexusEditorFrame then NexusEditorFrame:Hide() end
 Nexus.Panel.Show()
 H.Advance(.5)
 local x=Facts()
 return C.setup(x.wanted and x.shown and not x.menuSuppressed,tag..': fixture: the HUD is shown and wanted again',FactText())
end

C.scenario('Q1 the editor closes first, secondary QuickStart last',function()
 if not OpenEditor('Q1') then return end
 Nexus.QuickStart.ShowSetup() -- informational secondary Welcome; does not acknowledge first use
 C.setup(NexusQuickStart and NexusQuickStart:IsShown(),
  'Q1: fixture: the secondary Welcome is shown over the editor')
 editor:Hide()
 print('OBSERVED','Q1 after the editor closed',FactText())
 C.expect(Facts().wanted and Facts().shown and not Facts().menuSuppressed,
  'Q1: the unattached informational Welcome does not prevent immediate HUD restoration',FactText())
 if not CloseQuickStart('Q1') then return end
 print('OBSERVED','Q1 after Close',FactText())
 local x=Facts()
 C.expect(x.wanted and x.committed and x.shown and not x.menuSuppressed,
  'Q1: when the last popup closes, the wanted and committed HUD is shown again',FactText())
 Nexus.Panel.Show()
 C.expect(Facts().shown,'Q1: Panel.Show leaves the HUD shown',FactText())
 SlashCmdList.NEXUS('panel');SlashCmdList.NEXUS('panel')
 C.expect(Facts().wanted and Facts().shown,'Q1: two /nexus panel toggles leave the wanted HUD shown',FactText())
 C.guard(Facts().ready and Facts().committed,'Q1: the panel stays ready and committed',FactText())
end)

C.scenario('Q1b the first-use coach leaves the HUD restored when the editor closes',function()
 if not Reset('Q1b') or not OpenEditor('Q1b') then return end
 local offered=Nexus.QuickStart.ShowIfFirstTime()
 local coach=_G.NexusGuidedSetup
 if not C.setup(offered==false and coach and coach:IsShown(),
  'Q1b: fixture: the first-use coach opens over the editor',
  'offered='..tostring(offered)..' shown='..tostring(coach and coach:IsShown())
   ..' seen='..tostring(rawget(NexusDB,'hasSeenQuickStart'))) then return end
 editor:Hide();H.Advance(.2)
 C.guard(Facts().wanted and Facts().shown and not Facts().menuSuppressed,
  'Q1b: the unattached coach does not hold the HUD suppressed after editor close',FactText())
 -- The design's close control: a visible "X" whose hover names Close.
 local close=V.Frame(H,function(x)
  return x:GetParent()==coach and x:GetText()=='X' and type(x.tip)=='string'
   and x.tip:find('^Close')~=nil and x:GetScript('OnClick')~=nil
 end)
 if close then close:Click() end
 C.expect(close~=nil and not coach:IsShown() and Facts().shown,
  'Q1b: deliberate coach Close preserves the already restored HUD',FactText())
end)

C.scenario('G1 reversed order: QuickStart first, the editor last',function()
 if not Reset('G1') or not OpenEditor('G1') then return end
 Nexus.QuickStart.Show()
 C.setup(NexusQuickStart:IsShown(),'G1: fixture: QuickStart is shown over the editor')
 if not CloseQuickStart('G1') then return end
 C.guard(editor:IsShown() and Facts().menuSuppressed and not Facts().shown,
  'G1: while the editor (another attached window) is still open, the HUD stays hidden',FactText())
 editor:Hide()
 H.Advance(.2)
 C.guard(Facts().wanted and Facts().shown and not Facts().menuSuppressed,'G1: when the editor closes, the HUD is shown again',
  FactText())
end)

C.scenario('W1 a player who hid the HUD',function()
 if not Reset('W1') then return end
 SlashCmdList.NEXUS('panel')
 C.setup(not Facts().wanted and not Facts().shown,'W1: fixture: /nexus panel hides the HUD (not wanted)',FactText())
 if not OpenEditor('W1') then return end
 Nexus.QuickStart.Show()
 editor:Hide()
 if not CloseQuickStart('W1') then return end
 print('OBSERVED','W1 after Close',FactText())
 C.guard(not Facts().wanted and not Facts().shown,'W1: the unwanted HUD stays hidden when the popups close',FactText())
 SlashCmdList.NEXUS('panel')
 C.expect(Facts().wanted and Facts().shown,'W1: the player\'s next /nexus panel shows the HUD',FactText())
end)

C.scenario('G2 QuickStart alone',function()
 if not Reset('G2') then return end
 Nexus.QuickStart.Show()
 C.setup(NexusQuickStart:IsShown(),'G2: fixture: QuickStart is shown with no attached window')
 C.guard(Facts().shown and not Facts().menuSuppressed,'G2: QuickStart alone does not hide the HUD',FactText())
 if not CloseQuickStart('G2') then return end
 C.guard(Facts().wanted and Facts().shown and not Facts().menuSuppressed,'G2: and the HUD is still shown after Close',FactText())
end)

C.guard(Facts().ready and Facts().committed,'the panel is still ready and committed',FactText())
C.guard(Stock()==stock,'the stock HUD handoff facts are unchanged',Stock()..' vs '..stock)
C.guard(#H.actions==0,'no game action',#H.actions)
C.finish('(the HUD returns when the last Nexus popup closes, in either order; an unwanted HUD stays hidden)')
