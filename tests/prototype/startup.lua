-- Local controls become usable only after Store validation, independently of
-- the retained Community job. All external services are synthetic.
local H=dofile('tests/prototype/harness.lua')
local checks=0
local function check(v,m)assert(v,m);checks=checks+1 end
for line in io.lines('Nexus.toc') do
 line=line:gsub('\r','');if line~='' and not line:match('^#') then
  local path=line:gsub('\\','/');assert(loadfile(path))('Nexus',{})
 end
end
local permit=false;local sharedCalls=0
local actualCommunity=Nexus.CommunityBuilds.Init
Nexus.CommunityBuilds.Init=function(...)
 sharedCalls=sharedCalls+1
 if not permit then return {state='pending',phase='synthetic-pause'} end
 return actualCommunity(...)
end
local syncCalls,dpsCalls=0,0
local syncInit,dpsInit=Nexus.Sync.Init,Nexus.DpsCapture.Init
Nexus.Sync.Init=function(...)syncCalls=syncCalls+1;return syncInit(...)end
Nexus.DpsCapture.Init=function(...)dpsCalls=dpsCalls+1;return dpsInit(...)end
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
check(not Nexus.startupTiming.readyAt,'core must wait for validation')
H.Advance(10)
check(Nexus.startupTiming.readyAt~=nil,'EXPECTED RED: local readiness held behind pending Community')
local st=Nexus.StartupStatus()
check(st.coreReady and st.state=='pending','local readiness cannot wait for Community')
check(sharedCalls>0,'background job must continue')
check(syncCalls==0 and dpsCalls==0,'shared services stay gated')
check(#H.sent==0,'no startup network messages before shared readiness')
local start=#H.chat;SlashCmdList.NEXUS('status')
check(#H.chat>start and table.concat(H.chat,'\n'):find('Local controls ready',1,true),'status describes phased readiness')
Nexus.WishlistEditor.Show();check(Nexus.WishlistEditor~=nil,'local editor remains accessible')
local state=Nexus.Store.State();local authority=Nexus.MainInternals.StoreAuthorityOwner
local ok=authority.UpdateStateV1(function(row)row.startupProof='retained' end)
check(ok,'safe local state writer available after core validation')
local requested=sharedCalls
Nexus.CommunityBuilds.Show()
check(NexusSharedStartupFrame and NexusSharedStartupFrame:IsShown(),'Community loading window')
check(sharedCalls==requested,'opening view must not pump initialization')
Nexus.WishlistEditor.Show()
check(not NexusSharedStartupFrame:IsShown(),'opening local editor cancels pending view; no focus stealing')
Nexus.Leaderboard.Show('dummy')
check(NexusSharedStartupFrame:IsShown(),'Leaderboard loading window')
check(not NexusLeaderboardFrame or not NexusLeaderboardFrame:IsShown(),'actual leaderboard withheld')
local sent=#H.sent;local syncOK,why=Nexus.Sync.RequestSync()
check(syncOK==false and tostring(why):find('preparing',1,true),'manual Sync clearly refused until service init')
check(#H.sent==sent,'no premature Sync send')
H.Fire('PLAYER_ENTERING_WORLD');H.Advance(.5)
check(syncCalls==0 and dpsCalls==0,'world entry does not bypass shared gate')
check(Nexus.Store.State().startupProof=='retained','world transition preserves local edits')
permit=true
H.Advance(15)
st=Nexus.StartupStatus()
check(st.state=='ready' and st.coreReady and st.syncReady and st.dpsReady,'background completion releases services')
check(syncCalls==1 and dpsCalls==1,'services initialized exactly once')
check(not NexusSharedStartupFrame:IsShown(),'loading window closes after readiness')
check(NexusLeaderboardFrame and NexusLeaderboardFrame:IsShown(),'requested view automatically opens once')
check(Nexus.Store.State().startupProof=='retained','local edits survive background completion')
local c=sharedCalls;H.Advance(1)
check(sharedCalls==c,'completed job is not initialized again')
H.Fire('PLAYER_ENTERING_WORLD');H.Advance(1)
check(syncCalls==1 and dpsCalls==1,'world reentry does not repeat service Init')
-- No mutable status snapshot can grant readiness to another call.
local copy=Nexus.StartupStatus();copy.state='fake'
check(Nexus.StartupStatus().state=='ready','readiness result is detached')
print('PASS phased startup and actual view/command controls='..checks)
