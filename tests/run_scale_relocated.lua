-- Verifies the scale control was actually MOVED (not duplicated): no
-- slider on the overlay itself, and the editor's popup genuinely drives
-- WishlistOverlay's real scale with fine (0.02) steps via +/- and slider.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")

local overlayWidgets = {}
local realCreateFrame1 = CreateFrame
CreateFrame = function(...)
    local f = realCreateFrame1(...)
    overlayWidgets[#overlayWidgets + 1] = f
    return f
end
dofile("ui/WishlistOverlay.lua")

NexusDB = {}
H.wishlist = { name = "MyBuild", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 },
} }
H.playerLevel = 5

local Adapter, Model = Nexus.GameAdapter, Nexus.Model
local OV = Nexus.WishlistOverlay
OV.Init(Adapter, Model)
OV.Show()

-- no Slider-kind frame should exist among anything the overlay created
local foundSliderOnOverlay = false
for _, f in ipairs(overlayWidgets) do
    if f.kind == "Slider" then foundSliderOnOverlay = true end
end
-- (harness doesn't track "kind" explicitly -- check via the known global
-- name the old slider used to register under instead, which is the
-- reliable signal here)
assert(_G.NexusOverlayScale == nil,
    "the old overlay-mounted scale slider still exists -- should be removed")
print("no scale slider remains on the overlay itself -- OK")

-- default scale, GetScale/SetScale round-trip
assert(OV.GetScale() == 1.0, "default scale should be 1.0, got " .. tostring(OV.GetScale()))
OV.SetScale(1.2)
assert(OV.GetScale() == 1.2, "SetScale/GetScale round-trip failed")
assert(NexusDB.overlayScale == 1.2, "scale not persisted to SavedVariables")
print("WishlistOverlay.GetScale()/SetScale() public API works -- OK")

-- clamping: out-of-range values must be clamped, not silently broken
OV.SetScale(5.0)
assert(OV.GetScale() <= 1.6, "scale was not clamped to a sane maximum")
OV.SetScale(-1.0)
assert(OV.GetScale() >= 0.5, "scale was not clamped to a sane minimum")
print("scale is safely clamped to a sane range -- OK")

-- Now verify the EDITOR's popup genuinely drives this real overlay.
dofile("core/WishlistModel.lua")
dofile("core/WishlistController.lua")
dofile("ui/WishlistRenderer.lua")
dofile("ui/WishlistEditor.lua")
local EW = Nexus.WishlistEditor
EW.Init(Adapter, Model)

local popupWidgets = {}
local realCreateFrame2 = CreateFrame
CreateFrame = function(...)
    local f = realCreateFrame2(...)
    popupWidgets[#popupWidgets + 1] = f
    return f
end
EW.ToggleDisplayPopup()

assert(_G.NexusScaleSlider ~= nil,
    "expected a scale slider inside the editor's Display popup")
print("scale slider now lives in the editor's popup -- OK")

OV.SetScale(1.0)
-- find the +/- nudge buttons by observed behavior (fine +/-0.02 steps)
local plusBtn, minusBtn = nil, nil
for _, f in ipairs(popupWidgets) do
    if f.scripts and f.scripts.OnClick and f.text == "+" then plusBtn = f end
    if f.scripts and f.scripts.OnClick and f.text == "-" then minusBtn = f end
end
assert(plusBtn and minusBtn, "could not find both +/- nudge buttons in the popup")

plusBtn.scripts.OnClick(plusBtn)
local afterPlus = OV.GetScale()
assert(math.abs(afterPlus - 1.02) < 0.001,
    string.format("expected fine +0.02 nudge (1.02), got %.4f", afterPlus))
print("'+' nudge button applies a FINE 0.02 step -- OK")

minusBtn.scripts.OnClick(minusBtn)
minusBtn.scripts.OnClick(minusBtn)
local afterMinus = OV.GetScale()
assert(math.abs(afterMinus - 0.98) < 0.001,
    string.format("expected fine -0.02 steps back to 0.98, got %.4f", afterMinus))
print("'-' nudge button applies a FINE 0.02 step -- OK")
