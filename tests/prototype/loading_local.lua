-- Real local editor/automation calls while Community owner is deliberately
-- held pending. Status display and screen gating cannot grant shared readiness.
local H=dofile('tests/prototype/harness.lua')
local T=dofile('tests/prototype/startup_support.lua');T.Load()
H.pendingRolls=2
local sharedCalls=0
Nexus.CommunityBuilds.Init=function()sharedCalls=sharedCalls+1;return{state='pending',phase='scan',recordsSeen=sharedCalls}end
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().coreReady end)
local st=Nexus.StartupStatus();assert(st.state=='pending')
local A,E=Nexus.GameAdapter,Nexus.WishlistEditor
assert(A.SetFirstLoadoutWishlistIdentity('Local planned',{{spellId=200001,quality=1,stacks=2}}))
E.Show()
assert(NexusEditorFrame:IsShown(),'actual Wishlist editor usable before shared ready')
local before=sharedCalls
H.Board({{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200021,quality=1}})
H.Notify();H.Advance(.5)
assert(A.Wishlist()~=nil and A.Owned().synced==true,'local plan and owned evidence real')
SlashCmdList.NEXUS('auto');H.Advance(1.2)
local freezes=0
for _,a in ipairs(H.actions)do if a[1]=='freeze' then assert(a[2]==0);freezes=freezes+1 end end
assert(freezes==1,'actual rolling submission is not blocked by Community loading')
H.Advance(1);local actions=#H.actions
assert(Nexus.StartupStatus().state=='pending' and sharedCalls>before,'shared loading continues independently')
assert(#H.sent==0,'no shared Sync transport before its readiness')
local ok=Nexus.Sync.RequestSync();assert(ok==false,'shared manual Sync still gated')
SlashCmdList.NEXUS('auto')
assert(#H.actions==actions,'status and readiness gates do not add resource actions')
-- A shared failure is displayed without destroying a usable local draft.
local load=Nexus.LoadingStatus
load.Update({state='failed',coreReady=true,reason='synthetic shared fault',phase='commit'},true)
assert(NexusLoadingStatusFrame.title:GetText():find('stopped',1,true))
assert(NexusLoadingOpenWishlist:IsEnabled())
local report=NexusLoadingStatusFrame.progress:GetText()
assert(not report:find('100%%'),'failure is not 100 percent success')
print('PASS real editor and one confirmed-input rolling submission while shared preparation remains pending')
