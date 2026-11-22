-- Start/Stop wording (2026-11-19, user/coordinator-approved scoped correction):
-- closing the window does not stop a run, and the one control that ends it is
-- Stop. The same sentence is in Help and the packaged guide; the Orb window no
-- longer shows the obsolete "Use Pause or Stop" notice or a maximum approval.
local H=dofile('tests/prototype/orbs_support.lua')
local sentence='Closing the window does not stop a run. Use Stop in the Orb window, on the main Nexus panel or in the mini panel.'
local f=Nexus.OrbPanel.Show()
assert(not f.closeNotice:IsShown(),'I2 panel: no obsolete close notice')
H.OrbPlan();Nexus.OrbPanel.Refresh()
assert(not f.approval:IsShown() and f.start:IsShown(),'Start is the control; no maximum approval text is shown')
Nexus.Help.Show('orbs')
assert(NexusHelpWindow.body:GetText():find(sentence,1,true),'I2 Help disclosure')
local file=assert(io.open('README-PROTOTYPE.md','rb'));local guide=file:read('*a');file:close()
assert(guide:find(sentence,1,true),'I2 packaged instructions disclosure')
assert(not guide:find('Use Pause or Stop',1,true) and not guide:find('Set the maximum',1,true),'the packaged guide names no Pause or maximum')
assert(H.Count('orb-spend')==0 and H.Count('take')==0,'reading all disclosures submits nothing')
print('PASS Close disclosure: Stop in Help and packaged guide; no obsolete notice in the actual panel')
