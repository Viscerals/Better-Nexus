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
Nexus.LogViewer = { Init = function() end, Show = function() end }
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
H.playerLevel = 5
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("SPELLS_CHANGED")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(2)

-- The 1.19.3 player build does not include the temporary developer sniffer.
-- Its compatibility commands must not pause normal background ownership work.
SlashCmdList["NEXUS"]("sniff")
local countAfterSniffStart = 0
H.Perks.probeCount = 0
local realGetGranted = ProjectEbonhold.PerkService.GetGrantedPerks
ProjectEbonhold.PerkService.GetGrantedPerks = function(...)
    H.Perks.probeCount = H.Perks.probeCount + 1
    return realGetGranted(...)
end

H.Advance(3)  -- several poll intervals worth of time
assert(H.Perks.probeCount > 0,
    "public /nexus sniff command paused normal ownership polling")
local beforeDump = H.Perks.probeCount
print("public build keeps polling active when /nexus sniff is requested")

SlashCmdList["NEXUS"]("sniffdump")
H.Advance(3)
assert(H.Perks.probeCount > beforeDump,
    "normal ownership polling stopped after /nexus sniffdump")
print("public diagnostic compatibility commands never pause polling")
