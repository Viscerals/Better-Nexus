-- Regression for the live 2026-07-24 crash: WishlistEditor called
-- SetColorTexture (a retail-only API absent on this WotLK 3.3.5 client),
-- which threw INSIDE EnsureFrame before pickRows/applyBtn/footers were
-- created -- and because EnsureFrame memoizes, every later Toggle()/
-- Show() call silently returned the half-built frame forever after.
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

-- Simulate the exact live failure: make SetColorTexture throw, exactly
-- like calling a nonexistent method would on the real client, on ANY
-- texture this window creates.
local realCreateFrame = CreateFrame
CreateFrame = function(kind, name, parent, ...)
    local f = realCreateFrame(kind, name, parent, ...)
    local realCreateTexture = f.CreateTexture
    f.CreateTexture = function(self, ...)
        local tex = realCreateTexture(self, ...)
        tex.SetColorTexture = function() error("SetColorTexture not supported on this client") end
        return tex
    end
    return f
end

NexusDB = {}
H.wishlist = { name = "MyBuild", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 },
} }
H.playerLevel = 5

local Adapter, Model = Nexus.GameAdapter, Nexus.Model
Adapter.Wishlist = function()
    return { name=H.wishlist.name, class=H.wishlist.class, entries=H.wishlist.echoes }
end
local EW = Nexus.WishlistEditor
EW.Init(Adapter, Model)

local ok, err = pcall(EW.OpenForCandidate, {title=H.wishlist.name, echoes=H.wishlist.echoes})
assert(ok, "Show() threw despite SetColorTexture being unavailable: " .. tostring(err))

-- The actual regression: every functional widget must exist, not just
-- the frame itself. DebugPendingCount() exercises Refresh() internals
-- which touch the pending list built from real widgets.
assert(EW.DebugPendingCount() == 1, "pending list wasn't built correctly")

local ok2 = pcall(EW.Refresh)
assert(ok2, "Refresh() failed after the cosmetic texture failure")

local ok3 = pcall(EW.Toggle)
assert(ok3, "Toggle() failed -- this is exactly what crashed live")
local ok4 = pcall(EW.Toggle)
assert(ok4, "second Toggle() failed")

print("editor survives a SetColorTexture-style failure with all widgets intact")
