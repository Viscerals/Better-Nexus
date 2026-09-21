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

assert(W.OpenForWishlist(A.GetLoadoutWishlist(2),2))
local switch
for _,f in ipairs(H.frames)do
 if f.kind=='Button' and f:IsVisible() and type(f:GetText())=='string' and f:GetText():find('Editing:',1,true) then switch=f;break end
end
assert(switch,'normal Editing selector is visible');switch:Click()
local chosen
for _,row in ipairs(NexusWishlistEditorSwitchMenu.rows)do
 if row._label and row._label:GetText():find('Plan B',1,true)then chosen=row;break end
end
assert(chosen,'normal menu has Plan B');chosen:Click()
local box=CreateFrame('EditBox',nil,UIParent)
StaticPopupDialogs.NEXUS_EXPORT_WISHLIST.OnShow({editBox=box})
local parsed=assert(Nexus.Codec.DecodeEBH1(box._nexusExplicitExportText))
local a,b=false,false
for _,e in ipairs(parsed.entries)do if e.locked then
 if e.spellId==200080 then a=true end
 if e.spellId==200081 then b=true end
end end
print('NORMAL_EDITING_MENU_PLAN_B','hasA',a,'hasB',b)
assert(b and not a,'normal Editing dropdown must preserve Plan B complete design, not inherit legacy Plan A')
print('PASS normal Editing dropdown retains complete assignment design')
