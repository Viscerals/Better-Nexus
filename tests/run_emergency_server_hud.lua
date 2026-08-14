-- The Beta 3 stock-HUD preference remains a safe default after Community is
-- restored, but an explicit menu choice can merge PEH status into Nexus.
local H = dofile("tests/harness.lua")
dofile("data/Release.lua")

local stock = H.NewRegion()
stock:SetText("HC3  Soul Ash: 12,345  +25%")
stock.hooks = {}
function stock:HookScript(which, fn) self.hooks[which] = fn end
function stock:Show()
    self.shown = true
    if self.hooks.OnShow then self.hooks.OnShow(self) end
end
_G.ProjectEbonholdPlayerRunFrame = stock

NexusDB = { soulAshHudMode = "nexus" }
dofile("ui/ServerStatus.lua")
Nexus.ServerStatus.Init()

stock:Show()
H.Advance(1.1)
assert(stock:IsShown(),
    "restored Community build hid the stock Ashes / Intensity HUD")
assert(Nexus.ServerStatus.IsUsingNexusHud() == false,
    "restored Community build did not retain the stock server HUD")
assert(NexusDB.soulAshHudMode == "nexus",
    "emergency HUD fallback overwrote the user's saved preference")

local refreshes = 0
Nexus.Panel = {Refresh=function() refreshes=refreshes+1 end}
assert(Nexus.ServerStatus.SetMode("nexus") == "nexus"
    and NexusDB.soulAshHudModeExplicit == true
    and Nexus.ServerStatus.IsUsingNexusHud() == true
    and not stock:IsShown() and refreshes == 1,
    "explicit Nexus HUD choice did not hide and merge the PEH HUD")
stock:Show()
assert(not stock:IsShown(),
    "PEH OnShow escaped the explicit Nexus HUD choice")

assert(Nexus.ServerStatus.SetMode("server") == "server"
    and Nexus.ServerStatus.IsUsingNexusHud() == false
    and stock:IsShown() and refreshes == 2,
    "explicit server HUD choice did not restore PEH")

-- Exercise the real settings-menu action reported by the player, not merely
-- the controller API behind it.
local menuItems, mergedSummary
EasyMenu = function(items) menuItems=items end
CloseDropDownMenus = function() end
dofile("ui/Panel.lua")
Nexus.Panel.Init({RefreshDisplay=function()
    mergedSummary = Nexus.ServerStatus.IsUsingNexusHud()
        and Nexus.ServerStatus.GetSummary() or nil
    return true
end})
Nexus.Panel.Render({progress={},cards={},recommendation="",auto=false})
local panel = _G.NexusPanel
panel._menuBtn:GetScript("OnClick")(panel._menuBtn)
assert(menuItems and menuItems[5]
    and menuItems[5].text == "Use Nexus Difficulty / Soul Ash HUD"
    and not menuItems[5].disabled,
    "detected PEH HUD did not expose an enabled Nexus merge action")
menuItems[5].func()
assert(Nexus.ServerStatus.IsUsingNexusHud() == true
    and not stock:IsShown() and mergedSummary
    and mergedSummary.tier == "HC3" and mergedSummary.ash == "12,345",
    "settings-menu click did not merge current PEH status into Nexus")

print("stock HUD default and explicit PEH/Nexus HUD switching -- OK")
