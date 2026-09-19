local H=dofile('tests/prototype/orbs_support.lua');local M,O=H.M,H.O
local f=Nexus.OrbPanel.Show();local recheck,close
for _,b in ipairs(H.frames)do if b:GetParent()==f then
 if b:GetText()=='Recheck' then recheck=b elseif b:GetText()=='Close' then close=b end end end
assert(recheck and close)
local function readOnly()
 local count=#H.actions;H.now=H.now+3.1;recheck:Click()
 assert(#H.actions==count,'I1: actual Recheck handler submits no mutation in any state')
end
readOnly();H.OrbPlan({{spellId=410002,quality=2,stacks=2}});H.Approve(3,false)
readOnly()
O.charges=O.charges-1;O.offer=true
H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
-- Synchronous refresh notifications must not re-enter an active Pump either.
local refresh=ProjectEbonhold.OrbService.RequestCharges
ProjectEbonhold.OrbService.RequestCharges=function()refresh();M.Pump()end
readOnly();assert(H.Count('take')==0,'ready offer remains unselected during Recheck')
ProjectEbonhold.OrbService.RequestCharges=refresh
assert(f.notice:GetText():find('No Orb or choice was submitted.',1,true))
close:Click();assert(not f:IsShown() and M.Status().running,'Close keeps approved run active')
M.Pump();assert(H.Count('take')==1,'ordinary runtime still submits once after read-only handler')
readOnly();M.Pause();readOnly();H.Result(410002,2);readOnly()
assert(not M.Status().pending and H.Count('orb-spend')==1,'passive settlement does not spend next Orb')
M.Resume();M.Stop();readOnly();assert(H.Count('orb-spend')==2)
print('PASS actual Recheck handler idle/pending/ready/submitted/paused/stopped, reentrant refresh and Close')
