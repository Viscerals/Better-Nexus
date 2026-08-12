-- The Beta 3 stock-HUD correction remains active after Community is restored.
local H = dofile("tests/harness.lua")
dofile("data/Release.lua")

local stock = H.NewRegion()
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

stock:Show()
assert(stock:IsShown(),
    "restored Community OnShow hook re-hid the stock server HUD")

print("restored Community build retains Beta 3 stock server HUD -- OK")
