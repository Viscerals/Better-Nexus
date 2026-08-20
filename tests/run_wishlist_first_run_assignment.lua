-- activeSlot=0 is unresolved server state, not permission to weaken numbered
-- loadout validation or a character-level conclusion.
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

local wishlist = {
    slot=7, name="First Run Mage", verified=false,
    echoes={{spellId=200100,quality=3,stacks=1}},
}

local function SelectAtLevel(level)
    H.playerLevel = level
    H.DeliverSlots({[7]=wishlist}, 0)
    local candidate = assert(A.GetWishlistCandidates()[1],
        "zero-slot wishlist candidate was unavailable")
    local ok, err, active, firstRun = controller.AssociateCandidate(candidate)
    assert(ok and err == nil and active == nil and firstRun == true,
        "activeSlot=0 did not use first-run routing at level "
            .. tostring(level) .. ": " .. tostring(err))
    local selected = A.Wishlist()
    assert(selected and selected.name == wishlist.name
        and selected.source == "first-run-wishlist",
        "zero-slot selection was not immediately resolvable")
end

SelectAtLevel(80)
A.ClearFirstRunWishlist()
Nexus.Store.State().loadoutWishlists = {}
SelectAtLevel(20)

-- The explicitly selected target promotes exactly once when a real populated
-- active loadout becomes visible.
H.playerLevel = 80
H.DeliverSlots({
    [1]={slot=1,name="Saved Mage",verified=true,
        echoes={{spellId=200102,quality=2,stacks=1}}},
    [7]=wishlist,
}, 1)
local promoted = A.Wishlist()
assert(promoted and promoted.name == wishlist.name
    and promoted.source == "loadout-association"
    and Nexus.Store.State().loadoutWishlists[1]
    and Nexus.Store.State().firstRunWishlist == nil,
    "zero-slot selection did not promote to the real active loadout")

-- Numbered slots retain strict range and population validation.
H.DeliverSlots({
    [1]={slot=1,name="Empty",verified=true,echoes={}},
    [7]=wishlist,
}, 1)
local candidate = assert(A.GetWishlistCandidates()[1])
local ok, err = controller.AssociateCandidate(candidate)
assert(ok == false and err == "that loadout slot is empty or unavailable",
    "empty numbered slot bypassed strict validation")
assert(A.SetLoadoutWishlist(0, 7, candidate) == false
    and A.SetLoadoutWishlist(6, 7, candidate) == false,
    "out-of-range numbered validation changed")

-- One stored identity is safe while activeSlot is unresolved; multiple
-- different identities remain ambiguous.
local state = Nexus.Store.State()
state.firstRunWishlist = nil
state.loadoutWishlists = {
    [1]={slot=7,name=wishlist.name,key="200100:1",
        echoes={{spellId=200100,quality=3,stacks=1}}},
}
H.DeliverSlots({}, 0)
assert(A.Wishlist() and A.Wishlist().name == wishlist.name,
    "one stored association was not recovered while activeSlot=0")
state.loadoutWishlists[2] = {
    slot=8,name="Other",key="200102:1",
    echoes={{spellId=200102,quality=2,stacks=1}},
}
assert(A.Wishlist() == nil,
    "multiple stored identities were guessed while activeSlot=0")

print("wishlist zero-slot selection, promotion, ambiguity, and strict slots -- OK")
