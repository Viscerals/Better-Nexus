-- Verifies the editor's "Display..." button opens the on-screen-wishlist
-- popup, and that popup's Lock/Unlock button genuinely drives the
-- overlay's real lock state (not a decoy local flag).
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/WishlistOverlay.lua")
dofile("core/WishlistModel.lua")
dofile("core/WishlistController.lua")
dofile("ui/WishlistRenderer.lua")
dofile("ui/WishlistEditor.lua")

NexusDB = {}
H.wishlist = { name = "MyBuild", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 },
} }
H.playerLevel = 5

local Adapter, Model = Nexus.GameAdapter, Nexus.Model
local OV, EW = Nexus.WishlistOverlay, Nexus.WishlistEditor
OV.Init(Adapter, Model)
EW.Init(Adapter, Model)

assert(OV.IsLocked(), "overlay should default to locked")
OV.ToggleLock()
assert(not OV.IsLocked() and NexusDB.overlayLocked == false,
    "ToggleLock() did not unlock / persist")
OV.ToggleLock()
assert(OV.IsLocked(), "ToggleLock() did not re-lock")
print("WishlistOverlay.IsLocked()/ToggleLock() public API works -- OK")

-- Open the editor, then explicitly open the Display popup the same way
-- the "Display..." button does, then find ITS Lock/Unlock button and
-- confirm clicking it genuinely flips the overlay's real lock state.
EW.Show()
local ok = pcall(EW.ToggleDisplayPopup)
assert(ok, "ToggleDisplayPopup() threw")

local popup = _G.NexusDisplayPopup
assert(popup and popup:IsShown(), "Display popup did not open")

-- walk the popup's own children looking for the lock button by behavior
local lockBtn = nil
local function ScanChildren(f)
    if f.scripts and f.scripts.OnClick then
        local before = OV.IsLocked()
        local ok2 = pcall(f.scripts.OnClick, f)
        if ok2 and OV.IsLocked() ~= before then
            lockBtn = f
            return true
        end
    end
    return false
end
-- the harness doesn't track parent/child relationships explicitly, so
-- intercept CreateFrame during a FRESH popup open to enumerate exactly
-- what the popup creates
popup:Hide()
local created = {}
local realCreateFrame = CreateFrame
CreateFrame = function(...)
    local f = realCreateFrame(...)
    created[#created + 1] = f
    return f
end
_G.NexusDisplayPopup = nil
dofile("ui/WishlistRenderer.lua")
dofile("ui/WishlistEditor.lua")
local EW2 = Nexus.WishlistEditor
EW2.Init(Adapter, Model)
EW2.ToggleDisplayPopup()

for _, f in ipairs(created) do
    if ScanChildren(f) then break end
end
assert(lockBtn, "no widget in the Display popup actually toggles the overlay's lock state")
print("Display popup's Lock/Unlock button genuinely drives the overlay's lock state -- OK")

-- The checkbox inside the popup must genuinely show/hide the overlay.
-- Every harness widget technically exposes SetChecked (shared metatable
-- fallback), so detect the real checkbox by OBSERVED behavior instead of
-- by which methods happen to exist.
OV.Hide()
local checkBtn = nil
for _, f in ipairs(created) do
    if f.scripts and f.scripts.OnClick then
        f:SetChecked(true)
        local ok3 = pcall(f.scripts.OnClick, f)
        if ok3 and OV.IsShown() then
            checkBtn = f
            break
        end
    end
end
assert(checkBtn, "no widget in the Display popup actually shows the overlay when checked")
print("Display popup's checkbox genuinely shows the overlay -- OK")
