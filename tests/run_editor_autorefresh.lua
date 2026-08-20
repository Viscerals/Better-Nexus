-- Verifies the editor refreshes itself periodically while open (2026-07-24
-- gap: previously nothing updated the tracking status after an upload's
-- server round-trip finished unless the user happened to click something).
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
-- start with NO wishlist at all
local Adapter, Model = Nexus.GameAdapter, Nexus.Model
local EW = Nexus.WishlistEditor
EW.Init(Adapter, Model)
EW.Show()

local refreshCount = 0
local realRefresh = EW.Refresh
EW.Refresh = function(...)
    refreshCount = refreshCount + 1
    return realRefresh(...)
end

local before = refreshCount
H.Advance(5)  -- 5 seconds of real play time
assert(refreshCount > before, "editor never refreshed itself while open over 5 seconds")
print(string.format("editor auto-refreshed %d times over 5s while open -- OK", refreshCount - before))
