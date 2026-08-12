-- The exact restored TOC boots both wishlist automation and the bounded
-- Community/Sync/DPS feature set.
local H = dofile("tests/harness.lua")

local tocText = type(NEXUS_TEST_TOC) == "string" and NEXUS_TEST_TOC or nil
if not tocText then
    local tocFile = assert(io.open("Nexus.toc", "r"))
    tocText = tocFile:read("*a")
    tocFile:close()
end
for line in (tocText .. "\n"):gmatch("(.-)\n") do
    local path = line:match("^%s*(.-)%s*$")
    if path ~= "" and not path:find("^##") then
        dofile((path:gsub("\\", "/")))
    end
end

NexusDB = {
    communityBuilds={keep={
        id="keep", title="Keep", author="Boganic", isMine=true,
        ownerKey="boganic@ebonhold", class="MAGE", lastModified=1,
        echoes={{spellId=200100,quality=3,stacks=1}},
    }},
    dpsCapture={personalBest={},buildBest={},characterBest={dummy={},lk={}}},
}
H.playerLevel = 5
H.wishlist = {name="Restored Wishlist",class="MAGE",echoes={
    {spellId=200100,quality=3,stacks=1},
}}

H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(3)

assert(Nexus.BuildCatalog and Nexus.DataRetention and Nexus.Sync
    and Nexus.DpsCapture and Nexus.CommunityBuilds and Nexus.Leaderboard,
    "restored TOC did not load the Community runtime")
assert(NexusDB.communityBuilds.keep and NexusDB.communityBuilds.keep.isMine,
    "bounded startup migration removed an owned build")

SlashCmdList.NEXUS("builds")
assert(_G.NexusCommunityBuildsFrame
    and _G.NexusCommunityBuildsFrame:IsShown(),
    "restored builds command did not open Community")
SlashCmdList.NEXUS("leaderboard")
assert(_G.NexusLeaderboardFrame and _G.NexusLeaderboardFrame:IsShown(),
    "restored leaderboard command did not open")
SlashCmdList.NEXUS("editor")
assert(_G.NexusEditorFrame and _G.NexusEditorFrame:IsShown(),
    "Community restoration broke the wishlist editor")

print("exact restored TOC boots wishlist and bounded Community features -- OK")
