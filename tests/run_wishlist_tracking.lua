-- Regression for the exact live bug (2026-07-24): two designed wishlist
-- slots existed (from a community import + a raw-string import), neither
-- marked active, so Adapter.Wishlist() correctly returned nil -- but the
-- UI just said "no wishlist" with no explanation, reading as "you have
-- none" when really it meant "you have two, pick one."
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("core/WishlistModel.lua")
dofile("core/WishlistController.lua")
dofile("ui/WishlistRenderer.lua")
dofile("ui/WishlistEditor.lua")

NexusDB = {}
H.playerLevel = 1

-- One active Snapshot plus two designed wishlists, with no association yet.
H.DeliverSlots({
    [1] = { slot = 1, name = "Snapshot", verified = true, echoes = {
        { spellId = 200100, quality = 3, stacks = 1, locked = false },
    } },
    [6] = { slot = 6, name = "WISHLIST", verified = false, echoes = {
        { spellId = 200100, quality = 3, stacks = 1, locked = false },
    } },
    [7] = { slot = 7, name = "WISHLIST2", verified = false, echoes = {
        { spellId = 200102, quality = 2, stacks = 1, locked = false },
    } },
}, 1)

local Adapter, Model = Nexus.GameAdapter, Nexus.Model

-- 1. Adapter.Wishlist() correctly returns nil (genuinely ambiguous)
local wl = Adapter.Wishlist()
assert(wl == nil, "expected nil (ambiguous) wishlist, got one anyway")
print("Adapter.Wishlist() correctly returns nil when ambiguous -- OK")

-- 2. But GetWishlistCandidates() must surface BOTH real candidates
local candidates = Adapter.GetWishlistCandidates()
assert(#candidates == 2, "expected 2 candidates, got " .. #candidates)
local names = {}
for _, c in ipairs(candidates) do names[c.name] = true end
assert(names["WISHLIST"] and names["WISHLIST2"],
    "candidate list is missing one of the two real designed slots")
print("GetWishlistCandidates() surfaces both real candidates -- OK")

-- 3. The editor's tracking display must show the ambiguous-count
-- message, not a bare "no wishlist"
local EW = Nexus.WishlistEditor
EW.Init(Adapter, Model)
EW.Show()

-- find the tracking text and candidate buttons via a CreateFrame/
-- CreateFontString interceptor installed retroactively isn't possible
-- post-hoc, so re-open with fresh interception instead
local allWidgets = {}
local realCreateFrame = CreateFrame
CreateFrame = function(...)
    local f = realCreateFrame(...)
    allWidgets[#allWidgets + 1] = f
    local realCFS = f.CreateFontString
    f.CreateFontString = function(self, ...)
        local fs = realCFS(self, ...)
        allWidgets[#allWidgets + 1] = fs
        return fs
    end
    return f
end
_G.NexusEditorFrame = nil
dofile("ui/WishlistRenderer.lua")
dofile("ui/WishlistEditor.lua")
local EW2 = Nexus.WishlistEditor
EW2.Init(Adapter, Model)
EW2.Show()

local foundTrackingMsg, foundCandidateBtn = false, false
local associatedLoadout, associatedWishlist
local realAssociate = Adapter.SetLoadoutWishlist
Adapter.SetLoadoutWishlist = function(loadoutSlot, wishlistSlot)
    associatedLoadout, associatedWishlist = loadoutSlot, wishlistSlot
    return realAssociate(loadoutSlot, wishlistSlot)
end

for _, w in ipairs(allWidgets) do
    if type(w.text) == "string" and w.text:find("2 wishlists found") then
        foundTrackingMsg = true
    end
    if type(w.text) == "string" and (w.text:find("WISHLIST2") or w.text == "WISHLIST (1)") then
        foundCandidateBtn = true
        if w.scripts and w.scripts.OnClick then w.scripts.OnClick(w) end
    end
end
assert(foundTrackingMsg, "editor did not show the '2 wishlists found' message")
print("editor shows the ambiguous-wishlist count instead of a bare 'no wishlist' -- OK")
assert(foundCandidateBtn, "no candidate picker button was rendered")
assert(associatedLoadout == 1 and (associatedWishlist == 6 or associatedWishlist == 7),
    "clicking a candidate did not associate it with the active Snapshot")
print("clicking a candidate associates the correct active Snapshot -- OK")
