local H=dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua"); dofile("logic/Model.lua"); dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua"); dofile("logic/Policy.lua"); dofile("core/Store.lua")
dofile("core/GameAdapter.lua"); dofile("ui/WishlistOverlay.lua"); dofile("core/WishlistModel.lua"); dofile("core/WishlistController.lua"); dofile("ui/WishlistRenderer.lua"); dofile("ui/WishlistEditor.lua")
local A=Nexus.GameAdapter
H.discovered={[200100]=true}
H.FireEvent("SPELLS_CHANGED"); H.FireEvent("PLAYER_ENTERING_WORLD"); H.Advance(1)
local missing=A.UnknownTomesForEchoes({{spellId=200100},{spellId=200104},{spellId=200700}})
assert(#missing==2,"unknown tome detector should exclude learned tomes and report two unknown gates")
NexusDB=NexusDB or {}
Nexus.WishlistEditor.Init(A,Nexus.Model)
Nexus.WishlistEditor.Show()
-- Native 3.3.5 reproduced DIALOG/50 editor covering StaticPopup1 at
-- DIALOG/1, including its Save Changes button. The editor must stay below
-- the client's confirmation layer; increasing a global popup is not ours.
local strataOrder = {BACKGROUND=1,LOW=2,MEDIUM=3,HIGH=4,DIALOG=5,
    FULLSCREEN=6,FULLSCREEN_DIALOG=7,TOOLTIP=8}
local editor = assert(_G.NexusEditorFrame)
local popupStrata, popupLevel = "DIALOG", 1
assert(strataOrder[editor:GetFrameStrata()] < strataOrder[popupStrata]
    or (editor:GetFrameStrata() == popupStrata
        and editor:GetFrameLevel() < popupLevel),
    "Wishlist editor covers native Save Changes confirmation")
Nexus.WishlistEditor.ToggleDisplayPopup()
local popup=_G.NexusDisplayPopup
assert(popup and popup:IsShown(),"display settings popup did not open")
assert(popup:GetFrameStrata()=="TOOLTIP","display settings must render above the editor")
assert((popup:GetFrameLevel() or 0)>50,"display settings frame level is not above the editor")
print("unknown tome tracking and editor popup z-order -- OK")
