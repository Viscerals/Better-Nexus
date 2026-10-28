local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function button(label,parent)
 for _,b in ipairs(H.frames)do if b.kind=='Button' and b:GetText()==label and (not parent or b:GetParent()==parent)then return b end end
 error('button not found: '..label)
end
H.OrbPlan();local before=H.Count('orb-spend')
SlashCmdList.NEXUS('orbs');local f=assert(NexusOrbPanel)
check(f:IsShown() and f:GetWidth()==620 and f:GetHeight()==445,'bounded normal Orb window')
check(f.status:GetHeight()==74 and f.closeNotice:GetHeight()==20,'dedicated result reason and single Close disclosure')
check(H.Count('orb-spend')==before,'show is read-only with respect to gameplay')
check(f.approval:GetText():find('Start approves this maximum',1,true) and f.approval:GetText():find('eligible surplus copies',1,true),'Start discloses maximum and automatic source approval')
button('Advanced',f):Click();check(f.advanced:IsShown(),'optional exclusions and passive recheck')
check(H.Count('orb-spend')==before,'Advanced reading spends nothing')
button('Advanced',f):Click();check(not f.advanced:IsShown(),'normal screen does not require source selection')
f.limit:SetText('1');O.charges=0;button('Start',f):Click()
check(H.Count('orb-spend')==before and not f.start:IsEnabled(),'changed balance rechecked by actual Start handler')
O.charges=10;Nexus.OrbPanel.Refresh();f.limit:SetText('1');button('Start',f):Click()
check(H.Count('orb-spend')==before+1 and M.Status().limit==1,'one Start approves and submits one transaction')
button('Pause',f):Click();check(not M.Status().running,'real Pause handler')
H.Offer();check(H.Count('take')==0,'paused offer remains accessible without auto-selection')
Nexus.OrbPanel.Refresh()
button('Resume',f):Click();check(H.Count('take')==1,'real Resume selects known target')
H.Result(410002,2);check(M.Status().state=='COMPLETE','UI-started operation confirms target')
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
print('PASS real simplified Orb Start/maximum/pause/resume/Advanced/help handlers='..checks)
