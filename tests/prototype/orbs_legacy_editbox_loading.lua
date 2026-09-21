local H=dofile('tests/prototype/orbs_support.lua');local M=H.M
dofile('tests/prototype/legacy_editbox_support.lua')(H)
H.OrbPlan();local startup=Nexus.StartupStatus
Nexus.StartupStatus=function()return {coreReady=false}end
local count=#H.actions;local f=Nexus.OrbPanel.Show()
local function closed(reason)
 H.AssertOrbLocked(f,reason)
 assert(not f.advanced:IsShown() and f:GetHeight()==445,reason..': incomplete Advanced controls exposed')
 assert(not f.start:IsEnabled() and not f.stop:IsEnabled() and not f.assigned:IsEnabled(),reason..': main mutations exposed')
 assert(not f.clearExclusions:IsEnabled(),reason..': exclusion reset exposed')
 for _,row in ipairs(f.sourceRows)do assert(not row.exclude:IsEnabled(),reason..': source exclusion exposed')end
end
closed('local loading');H.OrbButton('Advanced',f):Click();closed('Advanced during loading')
assert(f.status:GetText():find('Reading local saved data',1,true))
Nexus.StartupStatus=startup;Nexus.OrbPanel.Refresh()
assert(f.limit.mouseEnabled and f.limit.keyboardEnabled and f.start:IsEnabled(),'local readiness restores real controls')
assert(f.advanced:IsShown(),'requested Advanced view appears only after a complete refresh')
f.limit:SetFocus();assert(H.TypeLimit(f,'7'))
local status=M.Status;M.Status=function()error('injected Orb snapshot failure')end
local ok,err=pcall(Nexus.OrbPanel.Refresh)
assert(not ok and tostring(err):find('injected Orb snapshot failure',1,true),'refresh error remains observable')
closed('failed refresh');f.start:Click();f.stop:Click()
assert(f.status:GetText():find('Controls are unavailable',1,true),'failed refresh has an explicit inactive explanation')
M.Status=status;Nexus.OrbPanel.Refresh()
assert(f.start:IsEnabled() and f.limit.mouseEnabled and f.advanced:IsShown(),'successful refresh restores controls')
Nexus.StartupStatus=function()return {coreReady=false}end
Nexus.OrbPanel.Refresh();closed('loading after ready')
assert(#H.actions==count,'loading/failed/passive refresh and disabled clicks submit no gameplay action')
H.OrbButton('Close',f):Click();assert(not f:IsShown(),'Close remains available during loading')
print('PASS strict legacy EditBox loading/failure defaults, hidden Advanced, recovery and zero mutations')
