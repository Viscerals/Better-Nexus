-- Verifies: (1) mouse-wheel scrolling replaces Prev/Next, (2) real spell
-- icons are set instead of the hardcoded question-mark placeholder.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")

local allFrames = {}
local realCreateFrame = CreateFrame
CreateFrame = function(...)
    local f = realCreateFrame(...)
    allFrames[#allFrames + 1] = f
    -- also capture every texture this frame creates -- the icon regions
    -- are textures, not frames, so CreateFrame alone never sees them
    local realCreateTexture = f.CreateTexture
    f.CreateTexture = function(self, ...)
        local tex = realCreateTexture(self, ...)
        allFrames[#allFrames + 1] = tex
        return tex
    end
    return f
end

dofile("core/WishlistModel.lua")
dofile("core/WishlistController.lua")
dofile("ui/WishlistRenderer.lua")
dofile("ui/WishlistEditor.lua")

-- fake GetSpellInfo returning a distinct icon per spellId
GetSpellInfo = function(id)
    return "Echo " .. id, nil, "Interface\\Icons\\Ability_Fake_" .. id
end

NexusDB = {}
H.wishlist = { name = "MyBuild", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 },
} }
H.playerLevel = 5

local Adapter, Model = Nexus.GameAdapter, Nexus.Model
local EW = Nexus.WishlistEditor
EW.Init(Adapter, Model)
EW.Show()

-- no Prev/Next buttons should exist anymore
for _, f in ipairs(allFrames) do
    local t = f.text
    assert(t ~= "Prev" and t ~= "Next",
        "a Prev/Next button still exists -- should be wheel-scroll only")
end
print("Prev/Next buttons are gone -- OK")

-- some frame must have wheel-scroll wired
local wheelFrames = 0
for _, f in ipairs(allFrames) do
    if f.scripts and f.scripts.OnMouseWheel then wheelFrames = wheelFrames + 1 end
end
assert(wheelFrames > 0, "no OnMouseWheel handlers found anywhere in the editor")
print(string.format("found %d wheel-scrollable regions -- OK", wheelFrames))

-- icons: the left-list row for Alpha Strike (200100) must show its real icon
local foundRealIcon = false
for _, f in ipairs(allFrames) do
    if type(f.texture) == "string" and f.texture:find("Ability_Fake_200100") then foundRealIcon = true end
end
assert(foundRealIcon, "left-list row did not get the real spell icon (still showing placeholder?)")
print("real spell icons are being set instead of the placeholder -- OK")
