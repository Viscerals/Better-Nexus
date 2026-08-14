-- Startup retention must not delete auto-generated build pages before legacy
-- DPS rows have migrated into the current reference-bearing stores.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")
dofile("core/DpsCapture.lua")

UnitName = function() return "Boganic" end
GetNormalizedRealmName = function() return "Ebonhold" end
time = function() return 50000 end

local echoes = {{spellId=200100,quality=3,stacks=1}}
NexusDB = {
    settingsVersion=4, settings={}, chars={}, syncTombstones={},
    communityBuilds={
        ["legacy-auto"]={
            id="legacy-auto", title="Legacy Auto", author="Peer",
            ownerKey="peer@ebonhold", class="MAGE", autoDps=true,
            postedAt=100, lastModified=100, echoes=echoes,
        },
    },
    dpsCapture={
        leaderboard={
            ["200100x1"]={
                dummy={
                    Peer={player="Peer",ownerKey="peer@ebonhold",
                        realm="ebonhold",class="MAGE",dps=25000000,
                        duration=65,ts=100,buildId="legacy-auto",
                        fingerprint="200100x1",echoes=echoes},
                },
            },
        },
    },
}

Nexus.Store.Init()

assert(NexusDB.dpsCapture.leaderboard == nil,
    "legacy leaderboard was not migrated during ADDON_LOADED")
assert(NexusDB.communityBuilds["legacy-auto"] ~= nil,
    "startup retention deleted a build still referenced by legacy DPS")
local found
for _, row in pairs(NexusDB.dpsCapture.characterBest.dummy or {}) do
    if row.buildId == "legacy-auto" then found = row break end
end
assert(found, "legacy DPS row did not enter the current character-best store")

print("legacy DPS migration precedes startup retention -- OK")
