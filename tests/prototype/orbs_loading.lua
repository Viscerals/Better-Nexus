local H=dofile('tests/prototype/harness.lua');local T=dofile('tests/prototype/startup_support.lua');T.Load()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local gateCalls=0
Nexus.CommunityBuilds.Init=function()gateCalls=gateCalls+1;return {state='pending',phase='scan'}end
SlashCmdList.NEXUS('orbs');local f=assert(NexusOrbPanel)
check(f:IsShown(),'Orb panel opens before readiness')
check(not f.assigned:IsEnabled(),'no target interaction before local readiness')
check(#H.actions==0 and #H.sent==0,'early panel spends and sends nothing')
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD');H.Advance(5)
check(Nexus.StartupStatus().coreReady and Nexus.StartupStatus().state=='pending','local ready but shared preparation pending')
SlashCmdList.NEXUS('orbs');check(f.assigned:IsEnabled(),'local target control no longer waits for Community')
local _,err=Nexus.GameAdapter.Orbs.Read()
check(type(err)=='string' and err:find('OrbService',1,true),'missing capability specifically reported')
check(not Nexus.OrbRuntime.BlocksOrdinary(),'unsupported Orb mode does not claim ordinary ownership')
SlashCmdList.NEXUS('editor');check(NexusEditorFrame and NexusEditorFrame:IsShown(),'ordinary local editor remains available')
local calls=gateCalls
for i=1,20 do Nexus.OrbPanel.Refresh()end
check(gateCalls==calls and #H.actions==0 and #H.sent==0,'Orb panel does not pump shared readiness or submit mutations')
check(not Nexus.OrbRuntime.Status().running,'Orb feature remains OFF by default')
print('PASS optional Orb capability and independent local/shared readiness='..checks)
