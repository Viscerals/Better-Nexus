local H=dofile('tests/prototype/harness.lua')
local function plan(id)return {{spellId=id,quality=id%4,stacks=1,locked=false}}end
H.perks.serverActiveSlot=1
H.perks.serverBuildSlots={[1]={name='Owned one',verified=true,echoes=plan(200001)},[2]={name='Owned two',verified=true,echoes=plan(200002)},
 [101]={name='Duplicate',verified=false,echoes=plan(200003)},[102]={name='Duplicate',verified=false,echoes=plan(200004)}}
H.Boot();local A=Nexus.GameAdapter
local chosen;for _,c in ipairs(A.GetWishlistCandidates())do if c.slot==102 then chosen=c end end
assert(A.SetLoadoutWishlist(1,102,chosen))
local before=Nexus.Store.State().loadoutWishlists[1]
assert(A.Wishlist().entries[1].spellId==200004,'duplicate names resolve by exact identity')
H.perks.serverBuildSlots[101],H.perks.serverBuildSlots[102]=H.perks.serverBuildSlots[102],H.perks.serverBuildSlots[101]
H.Notify();A.Poll();assert(A.Wishlist().entries[1].spellId==200004,'reordered slots preserve exact target')
H.perks.serverBuildSlots[101]=nil;H.perks.serverBuildSlots[102].name='Duplicate'
H.Notify();A.Poll();local a=A.AssignedWishlist()
assert(a.entries[1].spellId==200004 and a.mirrorNote,'missing target preserves local contents and explains current-list absence')
assert(Nexus.Store.State().loadoutWishlists[1].key==before.key,'no name-only reassignment')
H.perks.serverActiveSlot=2;H.Notify();A.Poll()
assert(A.Wishlist()==nil and Nexus.Store.State().loadoutWishlists[2]==nil,'another active loadout cannot borrow the only known assignment')
H.perks.serverActiveSlot=nil;H.Notify();A.Poll()
assert(A.Wishlist()==nil and A.AssignedWishlist().state=='restoring','known list with unknown active identity stays restoring')
assert(#H.actions==0,'identity recovery does not activate or upload')
print('PASS duplicate names, reordered/reused slots, absent mirrors and unassigned active loadouts')
