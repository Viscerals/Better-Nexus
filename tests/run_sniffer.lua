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
local provider
Nexus.LogViewer = { Init = function(p) provider = p end,
    Show = function() end, Toggle = function() end }
dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/WishlistModel.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")
NexusDB = {}
H.wishlist = { name = "MyBuild", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 },
} }
H.playerLevel = 1
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("SPELLS_CHANGED")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(1)

-- the target function already exists on PerkService (as it would in the
-- real game) BEFORE the sniffer gets installed -- InstallSniffer can only
-- hook what's already present on the table at call time
ProjectEbonhold.PerkService.AddDesignedPerkStub = function(slot, spellId, quality)
    return true
end
local original = ProjectEbonhold.PerkService.AddDesignedPerkStub

SlashCmdList["NEXUS"]("sniff")

-- simulate the real Echo Journal UI calling it
ProjectEbonhold.PerkService.AddDesignedPerkStub(3, 200672, 1)

local text = provider("sniffer")
assert(ProjectEbonhold.PerkService.AddDesignedPerkStub == original,
    "public command wrapped a protected service function")
assert(not text:find("AddDesignedPerkStub%(3, 200672, 1%)"),
    "temporary developer sniffer leaked into the 1.19.3 player build")
print("public build leaves PerkService functions untouched -- OK")
