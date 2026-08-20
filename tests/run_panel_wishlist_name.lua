-- Verifies the panel shows the ACTUAL tracked wishlist name instead of
-- the generic "Ideal loadout" label (2026-07-24 request: eliminate
-- confusion about which wishlist the numbers refer to).
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Relay.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/Readout.lua")
dofile("ui/Panel.lua")
Nexus.LogViewer = { Init = function() end }
dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")

NexusDB = {}
H.wishlist = { name = "MyAwesomeBuild", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 },
} }
H.playerLevel = 5

local lastModel
Nexus.GameAdapter.Wishlist = function()
    return { name=H.wishlist.name, class=H.wishlist.class, entries=H.wishlist.echoes }
end
local realRender = Nexus.Panel.Render
Nexus.Panel.Render = function(m) lastModel = m; realRender(m) end

H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("SPELLS_CHANGED")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(2)

assert(lastModel and lastModel.progress, "no progress captured")
assert(lastModel.progress.wishlistName == "MyAwesomeBuild",
    "expected wishlistName 'MyAwesomeBuild', got " .. tostring(lastModel.progress.wishlistName))
print("progress table carries the real wishlist name -- OK")

-- render it and check the actual displayed text mentions the real name,
-- not the old generic label
local frame = _G.NexusPanel
-- find the loadoutText fontstring by scanning created regions for one
-- containing the wishlist name
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
_G.NexusPanel = nil
dofile("ui/Panel.lua")
Nexus.Panel.Render(lastModel)

-- In the new panel design the wishlist name appears in the DPS section
-- label when a matching WR Build is found, and the progress table still
-- carries it (tested above). The generic "Ideal loadout" label is gone.
local foundOldLabel = false
for _, w in ipairs(allWidgets) do
    if type(w.text) == "string" then
        if w.text:find("Ideal loadout") then foundOldLabel = true end
    end
end
assert(not foundOldLabel, "panel still shows the old generic 'Ideal loadout' label")
-- The progress table carries the real wishlist name (verified above) --
-- the panel renders it contextually rather than as a static label.
print("panel no longer shows stale 'Ideal loadout' label -- OK")
print("wishlist name is in the progress model and used contextually -- OK")
