-- The follow-up to the emergency hotfix restores the feature modules while
-- retaining the user's existing SavedVariables for bounded migration.
local H = dofile("tests/harness.lua")

local toc = type(NEXUS_TEST_TOC) == "string" and NEXUS_TEST_TOC or nil
if not toc then
    local tocFile = assert(io.open("Nexus.toc", "r"))
    toc = tocFile:read("*a")
    tocFile:close()
end

assert(not toc:find("core\\EmergencyCommunity.lua", 1, true),
    "emergency disabled facade remains in the runtime manifest")
for _, required in ipairs({
    "data\\BundledBuilds.lua", "core\\LoadoutEvidence.lua",
    "core\\DataCompaction.lua", "core\\BuildCatalog.lua",
    "core\\DataRetention.lua", "core\\BuildHashCache.lua", "core\\Sync.lua",
    "core\\DpsCapture.lua", "core\\ViewProjections.lua",
    "ui\\CommunityBuilds.lua", "ui\\Leaderboard.lua", "ui\\Nameplate.lua",
}) do
    assert(toc:find(required, 1, true),
        "restored runtime module is absent from Nexus.toc: " .. required)
end

dofile("data/Release.lua")
assert(Nexus.Release.version == "1.20.0-beta.5"
    and Nexus.Release.emergencyCommunityOff == false,
    "release identity still advertises the community-off hotfix")

print("full Community runtime restored after emergency hotfix -- OK")
