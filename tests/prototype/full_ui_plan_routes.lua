-- Issue #163: every visible Plan exit must protect an unsaved editor draft.
local F=dofile('tests/prototype/format5_support.lua')
local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local function check(ok,why) assert(ok,why) end
local editor=Nexus.WishlistEditor
local panel=Nexus.Panel
local journal=Nexus.JournalTab
check(editor and panel and journal and Nexus.FullUIWorkspaces,
    'the composed UI and existing route owners load from Nexus.toc')
local originalOpen=journal.OpenBuilds
local originalCan=journal.CanOpenBuilds
local originalSuspend=editor.SuspendForWorkspace
local suspended=0
editor.SuspendForWorkspace=function(...)
    suspended=suspended+1
    return originalSuspend(...)
end
journal.CanOpenBuilds=function() return true end
journal.OpenBuilds=function(_,beforeOpen)
    if beforeOpen then beforeOpen() end
    return true
end

check(Nexus.FullUIWorkspaces.ShowPlan()==true,'Plan opens for a direct header route')
local plan=assert(_G.NexusEditorFrame)
local name=assert(_G.NexusWishlistNameInput)
name:SetText('Unsaved header route draft')
panel.OpenMyBuilds()
check(suspended==1,'direct My Builds route suspends the visible Plan draft')
check(not plan:IsShown(),'successful game-page route closes Plan')
check(Nexus.FullUIWorkspaces.ShowPlan()==true and plan:IsShown()
    and name:GetText()=='Unsaved header route draft',
    'returning from direct My Builds restores unsaved Plan text')

name:SetText('Unsaved failed-click draft')
journal.OpenBuilds=function(_,beforeOpen)
    if beforeOpen then beforeOpen() end
    return false,'click-failed'
end
panel.OpenMyBuilds()
check(suspended==2 and plan:IsShown()
    and name:GetText()=='Unsaved failed-click draft',
    'a game button click failure restores the visible Plan and its draft')
journal.OpenBuilds=function(_,beforeOpen)
    if beforeOpen then beforeOpen() end
    return true
end

name:SetText('Unsaved assignment route draft')
panel.OpenAssignment()
check(suspended==3,'direct assignment route suspends the visible Plan draft')
check(Nexus.FullUIWorkspaces.ShowPlan()==true and plan:IsShown()
    and name:GetText()=='Unsaved assignment route draft',
    'returning from direct assignment restores unsaved Plan text')

name:SetText('Unsaved failed assignment draft')
journal.OpenBuilds=function(_,beforeOpen)
    if beforeOpen then beforeOpen() end
    return false,'click-failed'
end
panel.OpenAssignment()
check(suspended==4 and plan:IsShown()
    and name:GetText()=='Unsaved failed assignment draft',
    'a failed assignment page click restores the visible Plan and draft')
journal.OpenBuilds=function(_,beforeOpen)
    if beforeOpen then beforeOpen() end
    return true
end

name:SetText('Unsaved Help route draft')
check(Nexus.Help.OpenAssignment()==true,'Help exposes its existing assignment route')
check(suspended==5,'Help assignment uses the same Plan draft guard')
check(Nexus.FullUIWorkspaces.ShowPlan()==true and plan:IsShown()
    and name:GetText()=='Unsaved Help route draft',
    'returning from Help assignment restores unsaved Plan text')

editor.SuspendForWorkspace=originalSuspend
journal.CanOpenBuilds=originalCan
journal.OpenBuilds=originalOpen
check(#H.actions==0 and #H.sent==0,
    'opening guarded routes does not execute game actions or send data')
print('PASS full UI direct Plan routes protect unsaved drafts')
