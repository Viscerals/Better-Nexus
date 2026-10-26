-- Issue #163: real Plan/Explore tabs reuse the existing controllers. Navigation
-- must not commit a Wishlist, assign a Saved Build, request Sync, or spend.
local F=dofile('tests/prototype/format5_support.lua')
local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local G=dofile('tests/prototype/layout_geometry_support.lua')
local checks=0
local function check(ok,message) assert(ok,message);checks=checks+1 end
local U=Nexus.FullUIWorkspaces
check(U and type(U.ShowPlan)=='function' and type(U.ShowExplore)=='function',
 'the workspace API is loaded')
local toc=assert(io.open('Nexus.toc','rb')):read('*a')
check(toc:find('ui\\FullUIWorkspaces.lua',1,true)~=nil,
 'the runtime TOC loads the workspace controller')
local beforeActions,beforeSends=#H.actions,#H.sent
local state=Nexus.Store.State()
local assignments=F.Serialize(state.loadoutWishlists or {})
local auto=Nexus.RecomputeStats().autoEnabled
local sync=Nexus.Sync.RequestSync
local requests=0
Nexus.Sync.RequestSync=function(...) requests=requests+1;return sync(...) end

check(U.ShowPlan()==true,'Plan reports a visible destination to its panel caller')
local plan=_G.NexusEditorFrame
check(plan and plan:IsShown(),'Plan opens the real Wishlist editor')
check(plan._workspaceTabs and plan._workspaceTabs.plan and plan._workspaceTabs.builds
 and plan._workspaceTabs.records,'Plan exposes all three workspace tabs')
check(plan._workspaceTabs.plan:GetText():find('Plan',1,true)~=nil,
 'active Plan tab names the workspace')
local realCommunityShow=Nexus.CommunityBuilds.Show
Nexus.CommunityBuilds.Show=function() return false,'pending' end
plan._workspaceTabs.builds:GetScript('OnClick')(plan._workspaceTabs.builds)
check(plan:IsShown() and not _G.NexusCommunityBuildsFrame,
 'pending Explore load leaves Plan visible instead of stranding the player')
Nexus.CommunityBuilds.Show=realCommunityShow
plan._workspaceTabs.builds:GetScript('OnClick')(plan._workspaceTabs.builds)
local builds=_G.NexusCommunityBuildsFrame
check(builds and builds:IsShown() and not plan:IsShown(),
 'Explore Builds replaces Plan without leaving overlapping dialogs')
check(builds._workspaceTabs and builds._workspaceTabs.records,
 'Build Library has a reachable Records tab')
local longSearch=string.rep('LongBuildName',5)
local search=_G.NexusBuildsSearch
if search then search:SetText(longSearch) end
builds._workspaceTabs.records:GetScript('OnClick')(builds._workspaceTabs.records)
local records=_G.NexusLeaderboardFrame
check(records and records:IsShown() and not builds:IsShown(),
 'Explore Records opens the real leaderboard and closes Builds')
records._workspaceTabs.builds:GetScript('OnClick')(records._workspaceTabs.builds)
check(builds:IsShown() and not records:IsShown(),
 'Records can return to the Build Library tab')
check(search and search:GetText()==longSearch,
 'a long Build Library search is preserved across Explore tabs')
builds._workspaceTabs.records:GetScript('OnClick')(builds._workspaceTabs.records)
records._workspaceTabs.plan:GetScript('OnClick')(records._workspaceTabs.plan)
check(plan:IsShown() and not records:IsShown(),
 'returning to Plan restores the real Wishlist editor')
plan:Hide()
check(not plan:IsShown(),'close still closes the workspace window')
check(Nexus.Panel.ShowHub('plan')==true and plan:IsShown(),
 'the panel Plan hub opens the actual Plan workspace')
plan:Hide()
check(Nexus.Panel.ShowHub('explore')==true and builds:IsShown(),
 'the panel Explore hub opens the actual Explore workspace')
builds:Hide()
local oldWidth,oldHeight=UIParent:GetWidth(),UIParent:GetHeight()
UIParent:SetSize(800,600)
check(U.ShowExplore()==true,'Explore reports a visible destination to its panel caller')
local left=G.Rect(builds._workspaceTabs.builds,builds)
local right=G.Rect(builds._helpNav,builds)
check(builds:GetWidth()<=UIParent:GetWidth() and left[1]>=0
 and right[3]<=builds:GetWidth(),
 'workspace tabs and Help stay inside the narrow real Build Library window')
builds:Hide()
UIParent:SetSize(oldWidth,oldHeight)
check(#H.actions==beforeActions and #H.sent==beforeSends and requests==0,
 'tab navigation never spends, sends, or requests Sync')
check(F.Serialize(Nexus.Store.State().loadoutWishlists or {})==assignments and
 Nexus.RecomputeStats().autoEnabled==auto,
 'navigation does not change Wishlist assignment or enable Auto')
Nexus.Sync.RequestSync=sync
print('full_ui_workspaces '..checks..' checks passed')
