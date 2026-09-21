-- Inspect the actual normal header after the retained create/reload/edit path.
local originalDofile=dofile
local H
dofile=function(path)
 local result=originalDofile(path)
 if path=='tests/prototype/harness.lua' then H=result end
 return result
end
dofile('tests/prototype/assignment_first_run_edit.lua')
dofile=originalDofile
assert(H)
local T=dofile('tests/prototype/startup_support.lua')
local A=Nexus.GameAdapter
local saved=H.Clone(Nexus.Store.State());local actions=#H.actions
local assigned=A.AssignedWishlist()
assert(assigned.state=='ready' and assigned.activeSlot==0,'real edited first-run assignment is ready')
local function header()
 for _,r in ipairs(NexusEditorFrame.regions)do
  local text=r:GetText()
  if r:IsVisible() and text and text:find('Wishlist: ',1,true) then return text end
 end
 error('actual editor context fontstring missing')
end
local function check()
 local text=header();print('EDITOR_CONTEXT',text)
 assert(text:find('Saved Build: ',1,true),'header must qualify the numbered Saved Build context')
 assert(not text:find('Assigned to:',1,true),'header must not contradict a ready first-run assignment')
 assert(A.AssignedWishlist().identity==assigned.identity,'header cannot change the resolved assignment')
end
ProjectEbonholdEchoJournal:Show();Nexus.JournalTab.RefreshAssociations()
NexusAssociatedWishlistDesignButton:Click();check()
-- The normal editor switch menu uses the same numbered-context terminology.
local switch
for _,f in ipairs(H.frames)do
 if f.kind=='Button' and f:IsVisible() and f:GetText():find('Editing:',1,true)then switch=f;break end
end
assert(switch,'normal Editing selector');switch:Click()
local row
for _,r in ipairs(NexusWishlistEditorSwitchMenu.rows)do
 if r._label and r._label:GetText():find(assigned.name,1,true)then row=r;break end
end
assert(row,'same first-run source in Editing menu')
assert(row._label:GetText():find('Saved Build:',1,true),'menu must qualify its numbered association status')
assert(not row._label:GetText():find('Unassigned',1,true),'menu must not call the ready first-run Wishlist unassigned')
row:Click();check()
assert(T.Equal(saved,Nexus.Store.State()),'context text does not alter stored assignment or targets')
assert(#H.actions==actions,'reading the editor does not submit services')
-- A real numbered context must still name its Saved Build.
NexusEditorFrame:Hide()
H.perks.serverBuildSlots[1]={name='Owned numbered build',verified=true,echoes=H.Clone(H.perks.serverBuildSlots[102].echoes)}
H.perks.serverActiveSlot=1;H.Notify();A.Poll();H.Advance(1)
assert(A.AssignedWishlist().state=='ready' and A.AssignedWishlist().activeSlot==1,'normal first-Saved-Build handoff resolves')
local numbered=H.Clone(Nexus.Store.State())
ProjectEbonholdEchoJournal:Show();Nexus.JournalTab.RefreshAssociations()
NexusAssociatedWishlistDesignButton:Click()
local text=header();print('NUMBERED_EDITOR_CONTEXT',text)
assert(text:find('Saved Build: ',1,true) and text:find('Owned numbered build',1,true),'actual numbered header retains its precise build name')
switch:Click()
local found=false
for _,r in ipairs(NexusWishlistEditorSwitchMenu.rows)do
 local label=r._label and r._label:GetText() or ''
 if label:find(assigned.name,1,true) and label:find('Saved Build: Owned numbered build',1,true)then found=true end
end
assert(found,'actual Editing menu retains numbered association name')
assert(T.Equal(numbered,Nexus.Store.State()) and #H.actions==actions,'numbered presentation makes no state or service mutation')
print('PASS actual header and Editing menu state the Saved Build context while first-run authority remains exact')
