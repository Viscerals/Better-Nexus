local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua');T.Load()
local calls=0
Nexus.CommunityBuilds.Init=function()calls=calls+1;error('synthetic shared preparation failure')end
local syncInit,dpsInit=0,0
Nexus.Sync.Init=function()syncInit=syncInit+1 end
Nexus.DpsCapture.Init=function()dpsInit=dpsInit+1 end
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD');H.Advance(10)
local st=Nexus.StartupStatus()
assert(st.coreReady and st.state=='failed','shared failure must not hold local controls hostage')
assert(calls==1 and syncInit==0 and dpsInit==0,'failed owner must not be retried/spawn dependents')
Nexus.WishlistEditor.Show();SlashCmdList.NEXUS('status')
assert(table.concat(H.chat,'\n'):find('shared data preparation failed',1,true),'clear failure status')
Nexus.CommunityBuilds.Show()
assert(NexusSharedStartupFrame:IsShown(),'failed shared feature shows status rather than importing')
local frames=#H.frames;H.Advance(20)
assert(calls==1 and #H.frames==frames,'failure cannot make an initialization retry/frame storm')
local ok=Nexus.Sync.RequestSync()
assert(ok==false and #H.sent==0,'failure cannot admit manual network work')
local holder=Nexus.StartupStatus();holder.reason=nil;holder.state='ready'
assert(Nexus.StartupStatus().state=='failed','status writes cannot grant readiness')
print('PASS shared startup fault isolation and no silent auto-retry')
