-- Regression for the live bug (2026-07-24): the overlay used MEDIUM
-- strata while the editor uses DIALOG, so it was structurally guaranteed
-- to render behind the editor regardless of frame level. Verifies the
-- overlay now outranks the editor using Blizzard's real strata ordering.
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

OV.Show()
EW.Show()

local ovFrame = _G.NexusOverlay
local edFrame = _G.NexusEditorFrame
assert(ovFrame and edFrame, "both frames must exist")

local STRATA_RANK = { BACKGROUND=1, LOW=2, MEDIUM=3, HIGH=4, DIALOG=5,
    FULLSCREEN=6, FULLSCREEN_DIALOG=7, TOOLTIP=8 }

local ovStrata, edStrata = ovFrame:GetFrameStrata(), edFrame:GetFrameStrata()
local ovLevel, edLevel = ovFrame:GetFrameLevel(), edFrame:GetFrameLevel()
print(string.format("overlay: strata=%s level=%d | editor: strata=%s level=%d",
    tostring(ovStrata), ovLevel, tostring(edStrata), edLevel))

local ovRank = STRATA_RANK[ovStrata] or 0
local edRank = STRATA_RANK[edStrata] or 0

local overlayOnTop = (ovRank > edRank) or (ovRank == edRank and ovLevel > edLevel)
assert(overlayOnTop,
    "overlay does NOT render above the editor -- this is the exact live bug")
print("overlay correctly renders ABOVE the editor -- OK")
