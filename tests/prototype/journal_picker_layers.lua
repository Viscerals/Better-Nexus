-- NATIVE-04: drive the real Journal selector and Unassign controls.
-- Check the demonstrated ordering invariant, not native pixels or API clamps.
local originalDofile=dofile
local H
dofile=function(path)
 local result=originalDofile(path)
 if path=='tests/prototype/orbs_support.lua' then H=result end
 return result
end
dofile('tests/prototype/assignment_journal_picker.lua')
dofile=originalDofile
assert(H)
local T=dofile('tests/prototype/startup_support.lua')
local A=Nexus.GameAdapter
local actions=#H.actions
local sources=H.Clone(H.perks.serverBuildSlots)
local designs=H.Clone(Nexus.Store.State().lockDesignTargetsBySlot)
local function open()
 ProjectEbonholdEchoJournal:Show();Nexus.JournalTab.RefreshAssociations()
 if NexusWishlistOnlyPicker:IsShown() then NexusActiveWishlistSelector:Click() end
 NexusActiveWishlistSelector:Click()
 assert(NexusWishlistOnlyPicker:IsShown(),'actual selector opens its picker')
 return NexusWishlistOnlyPicker
end
local function layers(p)
 local r=assert(p.clearRow,'actual Unassign row')
 assert(r:IsVisible() and r.text:IsVisible() and r.text:GetText()=='Unassign Wishlist','Unassign text exists in the real row')
 print('NATIVE04_LAYERS','picker',p:GetFrameLevel(),'row',r:GetFrameLevel())
 assert(r:GetFrameLevel()>p:GetFrameLevel(),'NATIVE-04: Unassign must render above its opaque picker')
 assert(p:GetFrameStrata()=='TOOLTIP','picker retains its overlay strata')
 assert(p:GetFrameLevel()<100 and r:GetFrameLevel()<128,'avoid the observed high-level parent/child failure band')
 assert(p.border:GetFrameLevel()>p:GetFrameLevel(),'border remains above the background')
 for _,row in ipairs(p.children)do
  if row.nameButton and row:IsVisible() then
   assert(row:GetFrameLevel()>p:GetFrameLevel(),'candidate row above picker')
   assert(row.nameButton:GetFrameLevel()>row:GetFrameLevel(),'candidate label above row')
   assert(row.gear:GetFrameLevel()>row:GetFrameLevel(),'edit control above row')
   assert(row.gear:GetFrameLevel()<128,'candidate controls remain in the low band')
  end
 end
 return r
end
local p=open();local clear=layers(p)
for i=1,3 do assert(layers(open())==clear,'reopening reuses a correctly ordered Unassign control')end
local first=H.Clone(A.GetLoadoutWishlist(1))
clear:Click()
assert(not p:IsShown() and A.AssignedWishlist().state=='unassigned','actual numbered Unassign closes the picker and clears only the active association')
assert(T.Equal(first,A.GetLoadoutWishlist(1)),'unrelated numbered association stays exact')
open();assert(not clear:IsShown(),'unlinked state hides the old Unassign row')
-- Deliberate selection through the actual zero-slot picker creates first-run context.
H.perks.serverActiveSlot=0;H.Notify();A.Poll();open()
local selected
for _,row in ipairs(p.children)do
 if row.nameButton and row:IsVisible() and row.nameButton.text:GetText():find('Plan B',1,true)then selected=row;break end
end
assert(selected,'same retained source appears in first-run picker');selected.nameButton:Click()
assert(A.AssignedWishlist().state=='ready' and A.AssignedWishlist().activeSlot==0,'normal first-run selection resolves')
assert(layers(open())==clear,'reused row remains above picker after context change')
clear:Click()
assert(A.AssignedWishlist().state=='unassigned','actual first-run Unassign resolves immediately')
open();assert(not clear:IsShown(),'first-run unlinked state hides Unassign')
assert(T.Equal(sources,H.perks.serverBuildSlots),'Unassign preserves all server Wishlist sources')
assert(T.Equal(designs,Nexus.Store.State().lockDesignTargetsBySlot),'Unassign preserves permanent-target designs')
assert(T.Equal(first,A.GetLoadoutWishlist(1)),'unrelated Saved Build survives first-run Unassign')
assert(#H.actions==actions and H.Count('orb-spend')==0 and H.Count('take')==0,'selector, edits and Unassign submit no gameplay or service mutation')
local status=Nexus.OrbRuntime.Status()
assert(not status.running and not status.pending and status.spent==0 and status.reserved==0,'UI work creates no Orb exposure')
print('PASS actual Journal low-layer ordering, reuse, numbered and first-run Unassign, preserved source/design and zero mutation')
