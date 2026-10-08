-- F-S4-4 (P3), regression-first: the HUD comes back when the last Nexus popup
-- closes, also when the first-run QuickStart outlives an attached window. An
-- attached window (here the Wishlist editor) suppresses the HUD while shown
-- and restores it on hide unless another Nexus window is shown
-- (ui/Panel.lua AttachMenuFrame/RestoreHudAfterMenus). QuickStart counts as
-- such a window but is never attached, so when the editor closes first the
-- restore is skipped, and QuickStart's own close never retries it: the HUD
-- stays hidden for the session (wanted, committed, suppressed), and neither
-- Panel.Show nor /nexus panel brings it back.
-- Healthy behaviour (EXPECT, fails at the baseline): with the editor closed
-- first and QuickStart dismissed last ("Later"), the wanted and committed HUD
-- is shown again; Panel.Show and two /nexus panel toggles leave it shown; a
-- player who had hidden the HUD keeps it hidden after the popups close, and
-- their next /nexus panel shows it.
-- Unchanged (GUARD, holds at the baseline): in the reversed order (QuickStart
-- dismissed first) the HUD stays hidden while the editor, another attached
-- window, is still open, and returns when it closes; a hidden (unwanted) HUD
-- stays hidden when the popups close; QuickStart alone does not hide the HUD;
-- the panel stays ready and committed and the stock HUD handoff facts are
-- unchanged; no game action.
-- Real TOC boot, runtime, Panel, minimap button, editor, QuickStart controls
-- and /nexus panel; artificial Saved Build. The first popup is shown through
-- the real first-run gate (ShowIfFirstTime) instead of the native start-up
-- race; later ones through the public QuickStart.Show. This revives no
-- retracted tester report.
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
local function Later(tag)
 local quick=NexusQuickStart
 local later=quick and V.Frame(H,function(x)
  return x:GetParent()==quick and x:GetText()=='Later' and x:GetScript('OnClick')~=nil
 end)
 C.setup(later~=nil,tag..': fixture: the real Later control exists')
 if later then later:Click() end
 H.Advance(.5)
 return C.setup(quick~=nil and not quick:IsShown(),tag..': fixture: Later dismisses QuickStart')
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

C.scenario('Q1 the editor closes first, QuickStart last',function()
 if not OpenEditor('Q1') then return end
 C.setup(Nexus.QuickStart.ShowIfFirstTime()==false and NexusQuickStart:IsShown(),
  'Q1: fixture: the real first-run gate shows QuickStart over the editor')
 editor:Hide()
 print('OBSERVED','Q1 after the editor closed',FactText())
 if not Later('Q1') then return end
 print('OBSERVED','Q1 after Later',FactText())
 local x=Facts()
 C.expect(x.wanted and x.committed and x.shown and not x.menuSuppressed,
  'Q1: when the last popup closes, the wanted and committed HUD is shown again',FactText())
 Nexus.Panel.Show()
 C.expect(Facts().shown,'Q1: Panel.Show leaves the HUD shown',FactText())
 SlashCmdList.NEXUS('panel');SlashCmdList.NEXUS('panel')
 C.expect(Facts().wanted and Facts().shown,'Q1: two /nexus panel toggles leave the wanted HUD shown',FactText())
 C.guard(Facts().ready and Facts().committed,'Q1: the panel stays ready and committed',FactText())
end)

C.scenario('G1 reversed order: QuickStart first, the editor last',function()
 if not Reset('G1') or not OpenEditor('G1') then return end
 Nexus.QuickStart.Show()
 C.setup(NexusQuickStart:IsShown(),'G1: fixture: QuickStart is shown over the editor')
 if not Later('G1') then return end
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
 if not Later('W1') then return end
 print('OBSERVED','W1 after Later',FactText())
 C.guard(not Facts().wanted and not Facts().shown,'W1: the unwanted HUD stays hidden when the popups close',FactText())
 SlashCmdList.NEXUS('panel')
 C.expect(Facts().wanted and Facts().shown,'W1: the player\'s next /nexus panel shows the HUD',FactText())
end)

C.scenario('G2 QuickStart alone',function()
 if not Reset('G2') then return end
 Nexus.QuickStart.Show()
 C.setup(NexusQuickStart:IsShown(),'G2: fixture: QuickStart is shown with no attached window')
 C.guard(Facts().shown and not Facts().menuSuppressed,'G2: QuickStart alone does not hide the HUD',FactText())
 if not Later('G2') then return end
 C.guard(Facts().wanted and Facts().shown and not Facts().menuSuppressed,'G2: and the HUD is still shown after Later',FactText())
end)

C.guard(Facts().ready and Facts().committed,'the panel is still ready and committed',FactText())
C.guard(Stock()==stock,'the stock HUD handoff facts are unchanged',Stock()..' vs '..stock)
C.guard(#H.actions==0,'no game action',#H.actions)
C.finish('(the HUD returns when the last Nexus popup closes, in either order; an unwanted HUD stays hidden)')
