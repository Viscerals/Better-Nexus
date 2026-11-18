-- Issue #163: real Plan/Explore tabs reuse the existing controllers. Navigation
-- must not commit a Wishlist, assign a Saved Build, request Sync, or spend.
local F=dofile('tests/prototype/format5_support.lua')
local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local G=dofile('tests/prototype/layout_geometry_support.lua')
local checks=0
local function check(ok,message) assert(ok,message);checks=checks+1 end
local U=Nexus.FullUIWorkspaces
local realPopupVisible=StaticPopup_Visible
StaticPopup_Visible=function(which)
 return H.popup and H.popup.which==which or false
end
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
local assign,mine=plan._workspaceAssignBtn,plan._workspaceMyBuildsBtn
check(assign and assign:IsShown() and mine and mine:IsShown(),
 'real Plan exposes deliberate Assign Wishlist and game My Builds controls')
check(G.Apart(G.Rect(assign,plan),G.Rect(plan._manageBtn,plan))
 and G.Inside(G.Rect(assign,plan),G.Rect(plan,plan))
 and G.Inside(G.Rect(mine,plan),G.Rect(plan,plan)),
 'Plan actions fit separately from Manage inside the editor')
local originalAssign,originalMine=Nexus.Panel.OpenAssignment,Nexus.Panel.OpenMyBuilds
local assignmentOpens,gameBuildOpens=0,0
Nexus.Panel.OpenAssignment=function() assignmentOpens=assignmentOpens+1 end
Nexus.Panel.OpenMyBuilds=function() gameBuildOpens=gameBuildOpens+1 end
assign:GetScript('OnClick')(assign)
mine:GetScript('OnClick')(mine)
check(assignmentOpens==1 and gameBuildOpens==1 and plan:IsShown(),
 'Plan actions route to the guarded Panel owners without making a choice')
Nexus.Panel.OpenAssignment,Nexus.Panel.OpenMyBuilds=originalAssign,originalMine
local draftName='Unsent Plan tab draft'
NexusWishlistNameInput:SetText(draftName)
for _,f in ipairs(H.frames) do
 if f.kind=='Button' and f:IsVisible() and f.status and f.data and f.data.spellId then
  f:Click();break
 end
end
check(Nexus.WishlistEditor.DebugDraftState().pending>0,
 'the synthetic Plan fixture has a real unsaved Echo draft')
local beforeDraft=F.Serialize(Nexus.WishlistEditor.DebugDraftState())
Nexus.Panel.OpenAssignment=function() return false,'native assignment unavailable' end
local refusedRoute,routeReason=U.OpenPlanAction('assignment')
check(refusedRoute==false and routeReason=='native assignment unavailable'
 and plan:IsShown() and F.Serialize(Nexus.WishlistEditor.DebugDraftState())==beforeDraft,
 'a refused native Plan action reports failure and keeps the unsaved draft')
Nexus.Panel.OpenAssignment=originalAssign
local realCommunityShow=Nexus.CommunityBuilds.Show
Nexus.CommunityBuilds.Show=function() return false,'pending' end
plan._workspaceTabs.builds:GetScript('OnClick')(plan._workspaceTabs.builds)
check(plan:IsShown() and not _G.NexusCommunityBuildsFrame,
 'pending Explore load leaves Plan visible instead of stranding the player')
Nexus.CommunityBuilds.Show=realCommunityShow
local realStartup=Nexus.StartupStatus
Nexus.StartupStatus=function()
 return {state='pending',coreReady=true,phase='catalog'}
end
local loading,loadingReason=U.NavigateFrom(plan,'builds')
check(loading==true and loadingReason=='loading'
 and _G.NexusSharedStartupFrame and NexusSharedStartupFrame:IsShown()
 and not plan:IsShown(),
 'real Community startup gate changes to a visible loading surface, not a hidden failure')
check(_G.NexusSharedLoadingWishlists and NexusSharedLoadingWishlists:IsEnabled(),
 'loading surface offers a usable return to local Plan')
NexusSharedLoadingWishlists:GetScript('OnClick')(NexusSharedLoadingWishlists)
check(plan:IsShown() and not NexusSharedStartupFrame:IsShown(),
 'return from the real Community loading surface restores Plan')
check(NexusWishlistNameInput:GetText()==draftName,
 'return from loading does not reset the unsaved Plan draft')
check(F.Serialize(Nexus.WishlistEditor.DebugDraftState())==beforeDraft,
 'return from loading retains pending Echo and scroll state')
Nexus.StartupStatus=realStartup
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
Nexus.StartupStatus=function()
 return {state='pending',coreReady=true,phase='catalog'}
end
local pendingRecords,pendingReason=U.NavigateFrom(builds,'records')
check(pendingRecords==true and pendingReason=='loading'
 and NexusSharedStartupFrame:IsShown() and not builds:IsShown(),
 'real Leaderboard startup gate also presents the visible loading surface')
NexusSharedLoadingWishlists:GetScript('OnClick')(NexusSharedLoadingWishlists)
check(plan:IsShown() and not NexusSharedStartupFrame:IsShown(),
 'Leaderboard loading surface can return to local Plan')
Nexus.StartupStatus=realStartup
plan._workspaceTabs.builds:GetScript('OnClick')(plan._workspaceTabs.builds)
builds._workspaceTabs.records:GetScript('OnClick')(builds._workspaceTabs.records)
records._workspaceTabs.plan:GetScript('OnClick')(records._workspaceTabs.plan)
check(plan:IsShown() and not records:IsShown(),
 'returning to Plan restores the real Wishlist editor')
check(NexusWishlistNameInput:GetText()==draftName,
 'Plan/Explore/Records round trip keeps unsaved draft text')
check(F.Serialize(Nexus.WishlistEditor.DebugDraftState())==beforeDraft,
 'Plan/Explore/Records round trip keeps the unsaved Echo draft and scroll state')
local normalVisible=StaticPopup_Visible
StaticPopup_Visible=function(which)
 return which=='WISHLISTREALIZER_CREATE_WISHLIST'
end
local guarded,guardReason=U.NavigateFrom(plan,'builds')
check(guarded==false and guardReason:find('pending Save',1,true)
 and plan:IsShown() and F.Serialize(Nexus.WishlistEditor.DebugDraftState())==beforeDraft,
 'an open Save confirmation blocks tab leave without changing the draft')
StaticPopup_Visible=normalVisible
local normalApply=Nexus.WishlistEditor.IsApplyPending
Nexus.WishlistEditor.IsApplyPending=function() return true end
local retryGuard,retryReason=U.NavigateFrom(plan,'builds')
check(retryGuard==false and retryReason:find('pending Save',1,true)
 and plan:IsShown(),
 'a confirmed Save retry blocks tab leave rather than cancelling it')
Nexus.WishlistEditor.IsApplyPending=normalApply
Nexus.WishlistEditor.OpenFlexiblePlanChooser()
check(NexusFlexiblePlanChooser and NexusFlexiblePlanChooser:IsShown(),
 'the real Flexible Plan chooser remains independently visible on UIParent')
local chooserLeave,chooserReason=U.NavigateFrom(plan,'builds')
check(chooserLeave==false and chooserReason:find('Plan alternatives',1,true)
 and plan:IsShown() and NexusFlexiblePlanChooser:IsShown()
 and F.Serialize(Nexus.WishlistEditor.DebugDraftState())==beforeDraft,
 'leaving Plan with its independent chooser open refuses without losing the draft')
NexusFlexiblePlanHide:Click()
local originalDecode=Nexus.Codec.DecodeEBH1
Nexus.Codec.DecodeEBH1=function() return {entries={{spellId=200001,quality=1,stacks=1}},name=''} end
Nexus.WishlistEditor.ImportEBH1String('synthetic EBH1')
Nexus.Codec.DecodeEBH1=originalDecode
check(H.popup and H.popup.which=='NEXUS_NAME_IMPORTED_WISHLIST',
 'the real nameless import path leaves a deferred name confirmation')
local importPopup=H.popup
local importLeave,importReason=U.NavigateFrom(plan,'builds')
check(importLeave==false and importReason:find('import',1,true)
 and plan:IsShown() and H.popup==importPopup
 and F.Serialize(Nexus.WishlistEditor.DebugDraftState())==beforeDraft,
 'leaving Plan with the imported-name confirmation open refuses without replacing the draft')
StaticPopup_Hide('NEXUS_NAME_IMPORTED_WISHLIST')
plan._workspaceTabs.builds:GetScript('OnClick')(plan._workspaceTabs.builds)
check(builds:IsShown() and not plan:IsShown(),'after guard clears, tab leave opens Explore')
local hiddenChooser,hiddenReason=Nexus.WishlistEditor.OpenFlexiblePlanChooser()
check(hiddenChooser==false and hiddenReason=='Plan draft suspended'
 and not NexusFlexiblePlanChooser:IsShown()
 and F.Serialize(Nexus.WishlistEditor.DebugDraftState())==beforeDraft,
 'a hidden Plan draft cannot open a later chooser over Explore')
StaticPopupDialogs.NEXUS_NAME_IMPORTED_WISHLIST.OnAccept(importPopup.frame,importPopup.data)
check(F.Serialize(Nexus.WishlistEditor.DebugDraftState())==beforeDraft
 and not plan:IsShown(),
 'a delayed import confirmation cannot replace the suspended draft')
local replacement,replacementReason=Nexus.WishlistEditor.NewWishlist()
check(replacement==false and replacementReason=='Plan draft suspended'
 and F.Serialize(Nexus.WishlistEditor.DebugDraftState())==beforeDraft,
 'an unrelated New Wishlist request cannot silently replace the hidden draft')
local normalGuid=UnitGUID
UnitGUID=function() return '0xOTHERCHARACTER' end
local mismatch,mismatchReason=U.ShowPlan()
check(mismatch==false and mismatchReason:find('context changed',1,true)
 and builds:IsShown() and H.popup
 and H.popup.which=='NEXUS_WORKSPACE_CONTEXT_CHANGED',
 'a character switch asks before discarding the hidden draft')
check(F.Serialize(Nexus.WishlistEditor.DebugDraftState())==beforeDraft,
 'context mismatch leaves the original unsaved Echo draft intact')
UnitGUID=normalGuid
StaticPopup_Hide('NEXUS_WORKSPACE_CONTEXT_CHANGED')
check(U.ShowPlan()==true and plan:IsShown() and not builds:IsShown(),
 'returning to original character restores the suspended draft')
plan._workspaceTabs.builds:GetScript('OnClick')(plan._workspaceTabs.builds)
local adapter=Nexus.GameAdapter
local selectedSavedBuild=adapter.SelectedSavedBuild
adapter.SelectedSavedBuild=function() return 2 end
local changedBuild,buildReason=U.ShowPlan()
check(changedBuild==false and buildReason:find('context changed',1,true)
 and builds:IsShown() and H.popup
 and H.popup.which=='NEXUS_WORKSPACE_CONTEXT_CHANGED',
 'a changed selected Saved Build also asks before discarding the draft')
adapter.SelectedSavedBuild=selectedSavedBuild
StaticPopup_Hide('NEXUS_WORKSPACE_CONTEXT_CHANGED')
check(U.ShowPlan()==true and plan:IsShown(),
 'returning to the original Saved Build restores the same draft')
plan:Hide()
check(not plan:IsShown(),'close still closes the workspace window')
check(Nexus.Panel.ShowHub('plan')==true and plan:IsShown(),
 'the panel Plan hub opens the actual Plan workspace')
plan:Hide()
check(Nexus.Panel.ShowHub('explore')==true and builds:IsShown(),
 'the panel Explore hub opens the actual Explore workspace')
builds:Hide()
check(U.ShowPlan()==true and plan:IsShown(),'Plan can reopen before a game-page route')
local realCanOpen=Nexus.JournalTab.CanOpenBuilds
Nexus.JournalTab.CanOpenBuilds=function() return false end
Nexus.Panel.OpenMyBuilds()
check(plan:IsShown(),'unavailable game My Builds keeps the Plan workspace visible')
Nexus.JournalTab.CanOpenBuilds=realCanOpen
plan:Hide()
local oldWidth,oldHeight=UIParent:GetWidth(),UIParent:GetHeight()
UIParent:SetSize(800,600)
check(U.ShowExplore()==true,'Explore reports a visible destination to its panel caller')
local left=G.Rect(builds._workspaceTabs.builds,builds)
local right=G.Rect(builds._helpNav,builds)
-- Native QA test.163008: Reference (the manual) sits after Help on the row.
local reference=G.Rect(builds._referenceNav,builds)
check(builds:GetWidth()<=UIParent:GetWidth() and left[1]>=0
 and right[3]<=builds:GetWidth() and reference[3]<=builds:GetWidth() and G.Apart(right,reference),
 'workspace tabs, Help and Reference stay inside the narrow real Build Library window')
builds:Hide()
UIParent:SetSize(oldWidth,oldHeight)
check(#H.actions==beforeActions and #H.sent==beforeSends and requests==0,
 'tab navigation never spends, sends, or requests Sync')
check(F.Serialize(Nexus.Store.State().loadoutWishlists or {})==assignments and
 Nexus.RecomputeStats().autoEnabled==auto,
 'navigation does not change Wishlist assignment or enable Auto')
Nexus.Sync.RequestSync=sync
StaticPopup_Visible=realPopupVisible
print('full_ui_workspaces '..checks..' checks passed')
