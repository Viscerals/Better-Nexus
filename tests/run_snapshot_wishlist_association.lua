-- Regression coverage for the combined Snapshot-specific wishlist resolution.
-- Run from the Nexus addon root with Lua 5.1/LuaJIT:
--   luajit tests/run_snapshot_wishlist_association.lua

local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")

NexusDB = {}
H.playerLevel = 1
Nexus.Store.Init()

local A = Nexus.GameAdapter
A.Init({}, Nexus.Store)
H.DeliverSlots({
    [1] = { slot=1, name="Snapshot A", verified=true, echoes={
        { spellId=200100, quality=3, stacks=1, locked=false },
    } },
    [6] = { slot=6, name="Wishlist A", verified=false, echoes={
        { spellId=200100, quality=3, stacks=1, locked=false },
    } },
    [7] = { slot=7, name="Wishlist B", verified=false, echoes={
        { spellId=200102, quality=2, stacks=1, locked=false },
        { spellId=200104, quality=2, stacks=3, locked=false },
    } },
}, 1)

local ok, err = A.SetLoadoutWishlist(1, 7)
assert(ok, "failed to associate active Snapshot: " .. tostring(err))
local linked = A.Wishlist()
assert(linked and linked.name == "Wishlist B"
    and linked.source == "loadout-association",
    "active Snapshot association did not override an ambiguous designed list")
assert(linked.byFamily.s200104
    and linked.byFamily.s200104.targetStacks == 3,
    "associated wishlist lost requested stack quantity")

-- Read paths must preserve the exact association through nil, empty, and
-- partial eventually-consistent mirrors, then recover on the next full view.
local state = Nexus.Store.State()
local stored = state.loadoutWishlists[1]
stored.futureAssociationField = {keep=true}
H.Perks.serverBuildSlots = nil
assert(A.GetLoadoutWishlist(1) == nil
    and state.loadoutWishlists[1] == stored,
    "nil slot snapshot cleared the stored association")
H.DeliverSlots({}, 0)
assert(A.GetLoadoutWishlist(1) == nil
    and state.loadoutWishlists[1] == stored,
    "empty slot snapshot cleared the stored association")
H.DeliverSlots({
    [1]={slot=1,name="Snapshot A",verified=true,echoes={
        {spellId=200100,quality=3,stacks=1,locked=false},
    }},
    [8]={slot=8,name="Unrelated",verified=false,echoes={
        {spellId=200200,quality=1,stacks=1,locked=false},
    }},
}, 1)
linked = A.GetLoadoutWishlist(1)
assert(linked and linked.name == "Wishlist B"
    and linked.key == stored.key and state.loadoutWishlists[1] == stored,
    "partial slot snapshot lost the immutable association")
H.DeliverSlots({
    [1]={slot=1,name="Snapshot A",verified=true,echoes={
        {spellId=200100,quality=3,stacks=1,locked=false},
    }},
    [7]={slot=7,name="Wishlist B",verified=false,echoes={
        {spellId=200102,quality=2,stacks=1,locked=false},
        {spellId=200104,quality=2,stacks=3,locked=false},
    }},
}, 1)
linked = A.GetLoadoutWishlist(1)
assert(linked and linked.name == "Wishlist B"
    and state.loadoutWishlists[1] == stored
    and stored.futureAssociationField.keep,
    "full snapshot did not recover table identity or future fields")
Nexus.Store.Init()
assert(Nexus.Store.State().loadoutWishlists[1] == stored
    and stored.futureAssociationField.keep,
    "repeat Store initialization replaced the association record")

A.ClearLoadoutWishlist(1)
assert(A.Wishlist() == nil,
    "multiple unassociated designed wishlists should remain ambiguous")

H.DeliverSlots({
    [1] = { slot=1, name="Snapshot A", verified=true, echoes={
        { spellId=200100, quality=3, stacks=1, locked=false },
    } },
    [7] = { slot=7, name="Wishlist B", verified=false, echoes={
        { spellId=200102, quality=2, stacks=1, locked=false },
    } },
}, 1)
assert(A.Wishlist() == nil,
    "1.19.3 must not guess even when only one unassociated wishlist remains")

H.DeliverSlots({
    [1] = { slot=1, name="Empty", verified=true, echoes={} },
    [7] = { slot=7, name="Wishlist B", verified=false, echoes={
        { spellId=200102, quality=2, stacks=1, locked=false },
    } },
}, 1)
ok = A.SetLoadoutWishlist(1, 7)
assert(ok == false,
    "an empty Snapshot must not acquire a usable wishlist association")

print("Snapshot wishlist association regression OK")
