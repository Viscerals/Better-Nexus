-- Same defense-in-depth check applied to Panel.lua and WishlistEditor.lua
-- after hitting this exact bug class twice: a cosmetic SetBackdrop
-- failure must never prevent functional widgets (Lock In, Delete) from
-- being created.
local H = dofile("tests/harness.lua")
local S = dofile("tests/catalog_authority_support.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/CommunityBuilds.lua")

local realCreateFrame = CreateFrame
CreateFrame = function(kind, name, parent, ...)
    local f = realCreateFrame(kind, name, parent, ...)
    if kind == "Frame" and name == "NexusCommunityBuildsFrame" then
        f.SetBackdrop = function() error("SetBackdrop not supported on this client") end
    end
    return f
end

NexusDB = {}
H.wishlist = { name = "MyBuild", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 },
} }
H.playerLevel = 5

local Adapter, Model = Nexus.GameAdapter, Nexus.Model
local CB = Nexus.CommunityBuilds
CB.Init(Adapter, Model)

local ok, err = pcall(CB.Show)
assert(ok, "Show() threw despite SetBackdrop failing: " .. tostring(err))

local ok2, id = S.PostWishlist(CB.PostCurrentWishlist, "Test", "desc", H.wishlist)
assert(ok2, "PostCurrentWishlist failed after the backdrop failure")
local ok3 = pcall(CB.Select, id)
assert(ok3, "Select() failed after the backdrop failure")

local ok4 = pcall(CB.LockInSelected)
assert(ok4, "LockInSelected() failed after the backdrop failure -- Lock In button must still exist")
assert(H.lastStaticPopup, "Lock In button did not actually function after the backdrop failure")

print("Nexus Builds survives a SetBackdrop-style failure with all functional widgets intact")
