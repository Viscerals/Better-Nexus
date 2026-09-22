local H=dofile('tests/prototype/harness.lua')
local T=dofile('tests/prototype/startup_support.lua');T.Load()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local permit=false
local realInit=Nexus.CommunityBuilds.Init
local calls=0
Nexus.CommunityBuilds.Init=function(...)
 calls=calls+1
 if not permit then return {state='pending',phase='identities',progressDone=1,progressTotal=4}end
 return realInit(...)
end
local syncCalls,dpsCalls=0,0
local si,di=Nexus.Sync.Init,Nexus.DpsCapture.Init
Nexus.Sync.Init=function(...)syncCalls=syncCalls+1;return si(...)end
Nexus.DpsCapture.Init=function(...)dpsCalls=dpsCalls+1;return di(...)end
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
SlashCmdList.NEXUS('loading')
local f=assert(NexusLoadingStatusFrame,'EXPECTED RED: read-only loading panel available before core readiness')
check(f:IsShown() and f:GetWidth()==430,'small non-fullscreen panel shown')
check(not NexusLoadingOpenWishlist:IsEnabled(),'local controls not falsely unlocked before Store readiness')
check(Nexus.LoadingStatus.Progress({state='pending',phase='scan',recordsSeen=9})==nil,'no invented total percentage')
local pct,txt=Nexus.LoadingStatus.Progress({state='pending',step='identities',stepDone=1,stepTotal=4})
check(pct==25 and txt:find('Current step: Preparing shared build information; 1 / 4 (25%)',1,true),'measured percentage explicitly current-step')
local pct2=Nexus.LoadingStatus.Progress({state='pending',stepDone=5,stepTotal=4})
check(pct2==nil,'invalid progress cannot display over100 percent')
H.Advance(5)
local s=Nexus.StartupStatus()
check(s.coreReady and s.state=='pending','local ready while real shared gate remains pending')
check(s.progressDone==1 and s.progressTotal==4 and s.step=='identities' and s.stepDone==1 and s.stepTotal==4,'read-only current-owner progress retained')
check(NexusLoadingOpenWishlist:IsEnabled(),'local navigation unlocks after real local readiness')
check(f.bar:GetValue()==25 and f.bar:IsShown() and f.detail:GetText():find('25%%'),'actual panel renders measured phase percent')
local before=calls
for i=1,100 do local x=Nexus.StartupStatus();Nexus.LoadingStatus.Update(x,true)end
check(calls==before and #H.sent==0,'status reads do not pump or send')
check(syncCalls==0 and dpsCalls==0,'unready shared services stay gated')
local chat=#H.chat;H.Advance(2)
check(#H.chat==chat,'no progress chat flood')
NexusLoadingOpenWishlist:Click()
check(NexusEditorFrame and NexusEditorFrame:IsShown(),'real local editor available while database loads')
local gray=0
for _,button in ipairs(H.frames)do
 if button.kind=='Button' and type(button:GetText())=='string' and button:GetText():find('|cff888888',1,true)then gray=gray+1 end
end
check(gray>=2,'data navigation shows gray loading labels')
Nexus.CommunityBuilds.Show()
check(NexusSharedStartupFrame:IsShown(),'guarded shared placeholder visible')
check(not NexusCommunityBuildsFrame or not NexusCommunityBuildsFrame:IsShown(),'no premature shared browser')
NexusSharedLoadingWishlists:Click()
check(not NexusSharedStartupFrame:IsShown() and NexusEditorFrame:IsShown(),'local return action cancels deferred shared focus')
NexusLoadingDismiss:Click();H.Advance(1)
check(not f:IsShown(),'dismissed loader stays dismissed while work continues')
check(calls>before,'dismissing status does not cancel work')
SlashCmdList.NEXUS('loading')
check(f:IsShown(),'read-only command reopens progress')
Nexus.Leaderboard.Show('lk')
check(NexusSharedStartupFrame:IsShown(),'Leaderboard withheld with same guarded placeholder')
permit=true;H.Advance(12)
s=Nexus.StartupStatus()
check(s.state=='ready' and s.syncReady and s.dpsReady,'real completion releases all shared services')
check(syncCalls==1 and dpsCalls==1,'each shared owner initialized once')
check(not NexusSharedStartupFrame:IsShown() and NexusLeaderboardFrame:IsShown(),'requested view opens after true completion')
H.Advance(4)
check(not f:IsShown(),'status automatically hides after ready without repeat frame creation')
SlashCmdList.NEXUS('loading')
check(f:IsShown() and f.bar:GetValue()==100,'explicit final status available')
local state=Nexus.StartupStatus();state.coreReady=false;state.state='pending'
check(Nexus.StartupStatus().state=='ready','presentation snapshot cannot mutate lifecycle authority')
SlashCmdList.NEXUS('status')
check(table.concat(H.chat,'\n'):find('auto OFF',1,true),'status work does not enable automation')
print('PASS loading phase progress, early local controls, shared gating, cancellation and no chat spam checks='..checks)
