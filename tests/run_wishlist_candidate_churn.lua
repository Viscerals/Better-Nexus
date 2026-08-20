-- A rendered candidate retains its immutable identity through one transient
-- mirror change, while slot recycling and malformed snapshots fail safely.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("core/WishlistModel.lua")
dofile("core/WishlistController.lua")

NexusDB = {}
Nexus.Store.Init()
local A = Nexus.GameAdapter
A.Init({}, Nexus.Store)
local controller = Nexus.WishlistInternals.Controller.New({
    model=Nexus.WishlistModel.New(), store=Nexus.Store,
    accountRoot=function() return NexusDB end,
    notify=function() end,
})
controller.Initialize(A)

local loadout = {slot=1,name="Saved Mage",verified=true,
    echoes={{spellId=200102,quality=2,stacks=1}}}
local original = {slot=7,name="Stable",verified=false,
    echoes={{spellId=200100,quality=3,stacks=1}}}

H.DeliverSlots({[1]=loadout,[7]=original}, 1)
local rendered = assert(A.GetWishlistCandidates()[1])
H.DeliverSlots({[1]=loadout}, 1)
local ok, err = controller.AssociateCandidate(rendered)
assert(ok and err == nil and A.Wishlist()
    and A.Wishlist().name == "Stable",
    "rendered candidate was invalidated by a transient disappearance")

-- The same server slot now represents different content. The stale rendered
-- snapshot must not transfer its association to that recycled slot.
Nexus.Store.State().loadoutWishlists = {}
local recycled = {slot=7,name="Stable",verified=false,
    echoes={{spellId=200104,quality=2,stacks=2}}}
H.DeliverSlots({[1]=loadout,[7]=recycled}, 1)
ok, err = controller.AssociateCandidate(rendered)
assert(ok == false and err == "wishlist changed; refresh and try again"
    and Nexus.Store.State().loadoutWishlists[1] == nil,
    "slot recycling transferred a stale rendered association")

-- Stable content may move and be renamed; the exact key wins over slot/name.
local renamed = {slot=8,name="Renamed",verified=false,
    echoes={{spellId=200100,quality=3,stacks=1}}}
H.DeliverSlots({[1]=loadout,[8]=renamed}, 1)
ok, err = controller.AssociateCandidate(rendered)
local saved = Nexus.Store.State().loadoutWishlists[1]
assert(ok and err == nil and saved and saved.slot == 8
    and saved.name == "Renamed" and saved.key == rendered.key,
    "stable identity did not survive a safe move/rename")

local malformed = {
    slot=8,name="Malformed",key="different",
    echoes=rendered.echoes,
}
ok, err = controller.AssociateCandidate(malformed)
assert(ok == false and err == "invalid wishlist",
    "malformed rendered identity reached association storage")

-- Immutable snapshots still obey the ordinary Wishlist slot and 79-copy
-- validation boundary; the snapshot path is not a validation bypass.
ok, err = controller.AssociateCandidate({
    slot=0,name="Invalid Slot",key="200100:1",
    echoes={{spellId=200100,quality=3,stacks=1}},
})
assert(ok == false and err == "invalid wishlist",
    "nonpositive rendered slot bypassed Wishlist validation")
ok, err = controller.AssociateCandidate({
    slot=7.5,name="Fractional Slot",key="200100:1",
    echoes={{spellId=200100,quality=3,stacks=1}},
})
assert(ok == false and err == "invalid wishlist",
    "fractional rendered slot bypassed Wishlist validation")
ok, err = controller.AssociateCandidate({
    slot=7,name="Over Budget",key="200100:40,200102:40",
    echoes={
        {spellId=200100,quality=3,stacks=40},
        {spellId=200102,quality=2,stacks=40},
    },
})
assert(ok == false and err == "invalid wishlist",
    "immutable snapshot bypassed the 79-copy Wishlist budget")
local preserved = Nexus.Store.State().loadoutWishlists[1]
assert(A.SetLoadoutWishlistIdentity(1, "Over Budget Identity", {
    {spellId=200100,quality=3,stacks=40},
    {spellId=200102,quality=2,stacks=40},
}) == false and Nexus.Store.State().loadoutWishlists[1] == preserved,
    "invalid exact-identity write replaced the prior association")
ok, err = controller.AssociateCandidate({
    slot=7,name="Exact Budget",key="200100:79",
    echoes={{spellId=200100,quality=3,stacks=79}},
})
assert(ok and err == nil,
    "exactly 79 Wishlist copies were incorrectly rejected")

-- Duplicate names never override the exact stable identity.
Nexus.Store.State().loadoutWishlists = {}
H.DeliverSlots({
    [1]=loadout,
    [8]={slot=8,name="Duplicate",verified=false,
        echoes={{spellId=200102,quality=2,stacks=1}}},
    [9]={slot=9,name="Duplicate",verified=false,
        echoes={{spellId=200104,quality=2,stacks=1}}},
}, 1)
ok, err = controller.AssociateCandidate(rendered)
saved = Nexus.Store.State().loadoutWishlists[1]
assert(ok and err == nil and saved and saved.key == rendered.key
    and saved.name == rendered.name and saved.slot == rendered.slot,
    "duplicate display names selected an unrelated live candidate")

print("wishlist rendered-candidate churn and stable identity safety -- OK")
