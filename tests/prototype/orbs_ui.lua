local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function button(label,parent)
 for _,b in ipairs(H.frames)do if b.kind=='Button' and b:GetText()==label and (not parent or b:GetParent()==parent)then return b end end
 error('button not found: '..label)
end
H.OrbPlan();local before=H.Count('orb-spend')
SlashCmdList.NEXUS('orbs');local f=assert(NexusOrbPanel)
-- Stale presentation pin updated (finish pass item D): the rows under Start
-- now take the height their text needs (OrbPanel flowBands), so the window is
-- at most the former 445 high, never a fixed 445 with blank bands; the status
-- box is measured (at most its former 74, the whole text on hover).
check(f:IsShown() and f:GetWidth()==620 and f:GetHeight()<=445 and f._bandsBottom~=nil and f._bandsBottom<=f:GetHeight(),'bounded normal Orb window')
check(f.status:GetHeight()>=12 and f.status:GetHeight()<=74 and f.statusHit~=nil and f.closeNotice:GetHeight()==20,'dedicated result reason and single Close disclosure')
check(H.Count('orb-spend')==before,'show is read-only with respect to gameplay')
-- Start/Stop rework (2026-11-19): no maximum, approval text, Advanced
-- exclusions, Pause or Resume; Start and Stop only.
for _,k in ipairs({'limit','max','approval','advancedToggle','pause','resume','cont'}) do
 check(not (f[k] and f[k]:IsShown()),'no '..k..' control')
end
O.charges=0;Nexus.OrbPanel.Refresh()
check(not f.start:IsEnabled() and f.startWhy:GetText():find('No confirmed Orbs',1,true),'zero balance: Start is unavailable and says why')
f.start:Click();check(H.Count('orb-spend')==before and not Nexus.OrbAuto.Active(),'a click on the unavailable Start starts nothing')
O.charges=10;Nexus.OrbPanel.Refresh()
check(f.start:IsEnabled(),'Start is available again')
O.charges=0;button('Start',f):Click()
check(H.Count('orb-spend')==before and not Nexus.OrbAuto.Active(),'changed balance rechecked by the actual Start handler')
O.charges=10;Nexus.OrbPanel.Refresh();button('Start',f):Click();H.Advance(.5)
check(H.Count('orb-spend')==before+1 and Nexus.OrbAuto.Active(),'one Start spends one Orb to open a draw')
H.Offer();H.Advance(.5);check(H.Count('take')==1,'the needed Echo is chosen from the offer')
H.Result(410002,2);H.Advance(.5)
check(not Nexus.OrbAuto.Active() and Nexus.OrbAuto.Status().state=='DONE','UI-started run completes the target and ends')
-- Help is the guided setup coach in this window's place; Reference is the
-- manual's Orbs page. Neither spends, sends nor acts.
local acts,sent=#H.actions,#H.sent
button('Help',f):Click()
check(NexusGuidedSetup and NexusGuidedSetup:IsShown() and not f:IsShown()
 and not(NexusHelpWindow and NexusHelpWindow:IsShown()),'Orb Help opens the guided setup coach, not the manual')
Nexus.GuidedSetupUI.Hide();Nexus.OrbPanel.Show();check(f:IsShown(),'Orb window reopens after the coach')
button('Reference',f):Click()
check(NexusHelpWindow and NexusHelpWindow:IsShown() and NexusHelpWindow.title:GetText()=='Nexus Reference - Orbs / Lost Memories'
 and not NexusGuidedSetup:IsShown(),'Orb Reference opens the manual at the Orbs page')
check(#H.actions==acts and #H.sent==sent,'Help and Reference act on nothing and send nothing')
Nexus.Help.Hide();f:Hide();check(H.Count('orb-spend')==before+1,'closing panel/help creates no action')
-- Ordinary auto must remain off through the actual session owner.
check(Nexus.RecomputeStats().autoEnabled==false,'UI-run completion leaves ordinary Auto OFF')
print('PASS real Orb Start/Stop window (no maximum), Help and Reference handlers='..checks)
