local H=dofile('tests/prototype/harness.lua')
local E={};for i=1,85 do E[i]={spellId=200000+i,quality=i%4,stacks=1,locked=false}end
H.perks.serverBuildSlots={[1]={name='Active',verified=true,echoes={{spellId=200090,quality=2,stacks=1}}},[101]={name='Different desired locks',verified=false,echoes=H.Clone(E)}}
H.perks.serverActiveSlot=1
H.locked={};for i=90,95 do H.locked[#H.locked+1]={spellId=200000+i,stacks=1}end
H.Boot()
Nexus.Store.Settings().useCurrentLocksForUntagged=false -- Explicit manual-choice control; automatic path has separate tests.
local A,W=Nexus.GameAdapter,Nexus.WishlistEditor
local c=A.GetWishlistCandidates()[1]
assert(W.OpenForWishlist(c,1))
for i=1,6 do _G['NexusWishlistRolePlus'..i]:Click()end
assert(NexusWishlistRoleConfirm:Click())
local box=CreateFrame('EditBox',nil,UIParent)
StaticPopupDialogs.NEXUS_EXPORT_WISHLIST.OnShow({editBox=box})
local export=box._nexusExplicitExportText
local parsed=Nexus.Codec.DecodeEBH1(export)
assert(parsed,'explicit six desired locks must export without appending unrelated owned locks')
local ordinary,locked=0,0;for _,e in ipairs(parsed.entries)do if e.locked then locked=locked+e.stacks else ordinary=ordinary+e.stacks end end
assert(ordinary==79 and locked==6)
for _,e in ipairs(parsed.entries)do assert(e.spellId<200090,'no unrelated owned row appended')end
local before=#H.actions
W.ImportEBH1String(export,'Export round-trip')
assert(not NexusWishlistRolePicker:IsShown(),'explicit export round trip needs no chooser')
local draft=W.DebugDraftState()
assert(draft.pending==79 and draft.pendingLock==6 and draft.fulfilled==0,'round-trip preserves unowned planned locks')
assert(#H.actions==before,'export/import draft does not spend or change locked Echoes')
assert(#H.locked==6 and H.locked[1].spellId==200090,'actual ownership unchanged')
print('PASS explicit-target export/import with different locked Echoes, no extra copies or actions')
