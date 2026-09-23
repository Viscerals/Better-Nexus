-- Obtain only the synthetic harness from the unchanged independent R1 regression.
local originalDofile=dofile
local H
dofile=function(path)
 local result=originalDofile(path)
 if path=='tests/prototype/orbs_support.lua' then H=result end
 return result
end
dofile('tests/prototype/assignment_distinct_designs.lua')
dofile=originalDofile
assert(H)
local A,W=Nexus.GameAdapter,Nexus.WishlistEditor
local rolled=A.GetLoadoutWishlist(1).echoes
H.perks.serverBuildSlots[101]={name='Plan A',verified=false,echoes=H.Clone(rolled)}
H.perks.serverBuildSlots[102]={name='Plan B',verified=false,echoes=H.Clone(rolled)}
H.perks.serverActiveSlot=2;H.Notify();A.Poll()
assert(A.AssignedWishlist().name=='Plan B' and A.AssignedWishlist().wishlist.designTargets[200081])

local journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
journal:Show();Nexus.JournalTab.RefreshAssociations()
assert(NexusActiveWishlistSelector,'normal Journal assignment selector exists'):Click()
local chosen
for _,row in ipairs(NexusWishlistOnlyPicker.children)do
 if row.nameButton and row.nameButton.text:GetText():find('Plan B',1,true)then chosen=row;break end
end
assert(chosen,'normal assignment picker has Plan B');chosen.nameButton:Click()
local a=A.AssignedWishlist()
local hasA,hasB=false,false
for _,e in ipairs(a.entries)do if e.locked then
 if e.spellId==200080 then hasA=true end
 if e.spellId==200081 then hasB=true end
end end
print('NORMAL_JOURNAL_PICK_PLAN_B','name',a.name,'hasA',hasA,'hasB',hasB)
assert(a.name=='Plan B' and hasB and not hasA,'normal Journal picker must assign exact Plan B locked design')
print('PASS normal Journal assignment preserves complete selected plan')

