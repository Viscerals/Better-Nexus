local H=dofile('tests/prototype/orbs_support.lua');local M=H.M
dofile('tests/prototype/legacy_editbox_support.lua')(H)
H.OrbPlan({{spellId=410002,quality=2,stacks=3}});assert(M.Start(3))
local ok,f=pcall(Nexus.OrbPanel.Show)
assert(ok,'legacy busy Orb render failed: '..tostring(f))
H.AssertOrbLocked(f,'running pending operation')
local changes=0;local set=M.SetLimit
M.SetLimit=function(...)changes=changes+1;return set(...)end
local function unchanged(reason)
 local before=M.Status();local actions=#H.actions;local limitCalls=changes;f.limit:SetText('999')
 f.limit:GetScript('OnEnterPressed')(f.limit);Nexus.OrbPanel.Refresh()
 local after=M.Status()
 assert(changes==limitCalls,reason..': locked Enter called SetLimit')
 assert(after.limit==before.limit and after.spent==before.spent and after.reserved==before.reserved,reason..': allowance/exposure changed')
 assert(#H.actions==actions and f.limit:GetText()==tostring(after.limit),reason..': Enter submitted an action or retained fake maximum')
 H.AssertOrbLocked(f,reason)
end
unchanged('running')
f.start:Click();assert(M.Status().state=='PAUSED');unchanged('paused pending')
H.Offer();assert(H.Count('take')==0);Nexus.OrbPanel.Refresh();unchanged('paused ready offer')
f.start:Click();assert(H.Count('take')==1);unchanged('submitted selection')
f.stop:Click();assert(M.Status().pending and not M.Status().running);unchanged('stopped unresolved')
H.Result(410002,2);Nexus.OrbPanel.Refresh()
assert(not M.Status().pending and f.limit.mouseEnabled and f.limit.keyboardEnabled,'settled Stop restores idle editing')
assert(H.Count('orb-spend')==1,'Stop/refresh must not submit another spend')
f.limit:SetText('1');f.start:Click();H.Offer();H.Result(410002,2);Nexus.OrbPanel.Refresh()
-- A settled maximum finishes the run: the next run's maximum is editable at
-- once, and Stop is not needed to release the completed budget.
assert(M.Status().state=='FINISHED' and not M.Status().pending,'actual settled completion reached')
assert(f.limit.mouseEnabled and f.limit.keyboardEnabled,'a finished run unlocks the next maximum')
assert(not f.stop:IsEnabled(),'Stop is disabled once the run is finished')
assert(H.Count('orb-spend')==2 and H.Count('take')==2,'only the two explicit synthetic Starts submitted')
print('PASS strict legacy EditBox running/paused/ready/selection/stopped/settled/limit locks and allowance')
