-- Verifies the Nexus Builds tab end-to-end: posting your active wishlist,
-- browsing the list, selecting a build to see its full echo list with
-- owned/missing status, and locking one in via the real confirmed
-- UploadWishlist path.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/CommunityBuilds.lua")

NexusDB = {}
H.wishlist = { name = "MyBuild", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 },
    { spellId = 200104, quality = 2, stacks = 3 },
} }
H.playerLevel = 5
H.granted = { ["Alpha Strike"] = { { spellId = 200100, stack = 1, maxStack = 1, quality = 3 } } }
UnitName = function() return "Boganic" end

local Adapter, Model = Nexus.GameAdapter, Nexus.Model
local CB = Nexus.CommunityBuilds
CB.Init(Adapter, Model)

-- 1. Posting with no wishlist active must fail cleanly (edge case)
H.wishlist = nil
local ok0, err0 = CB.PostCurrentWishlist("Test", "desc")
assert(not ok0 and err0, "posting with no active wishlist should fail cleanly")
print("posting with no active wishlist fails cleanly -- OK")

-- 2. Restore wishlist, post it for real
H.wishlist = { name = "MyBuild", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 },
    { spellId = 200104, quality = 2, stacks = 3 },
} }
local rawBuildTitle = "|cffff0000Fire|r"
local ok1, id1 = CB.PostCurrentWishlist("Fire Mage AoE", "Great for farming, easy to play.", H.wishlist)
assert(ok1, "PostCurrentWishlist should have succeeded")
local stored = H.DurableBuilds()[id1]
assert(stored, "posted build not found in the store")
assert(stored.title == "Fire Mage AoE", "wrong title stored")
assert(stored.description == "Great for farming, easy to play.", "wrong description stored")
assert(#stored.echoes == 2, "expected 2 echoes captured, got " .. #stored.echoes)
assert(stored.isMine == true, "own posted build should be tagged isMine")
print("PostCurrentWishlist correctly snapshots the active wishlist -- OK")
-- Incoming wire records admit literal pipes even though locally authored titles
-- remain plain. Model that remote/storage boundary before the lock-in popup.
stored.title = rawBuildTitle
assert(Nexus.BuildCatalog.Put(stored), "raw title update was not readmitted")

-- 3. Show the window, select the build, verify detail rendering
CB.Show()
local frame = _G.NexusCommunityBuildsFrame
assert(frame and frame:IsShown(), "CommunityBuilds window did not open")

-- select via the public API path (simulate clicking the list row)
-- (Refresh populates row.buildId; we drive selection the same way the
-- row's own OnClick would, then Refresh)
CB.Select(id1)

-- 4. Detail panel must show correct owned/missing counts. We granted
-- Alpha Strike (200100, owns 1/1) but not Double Strike (200104, owns
-- 0/3) -- expect 1 missing echo out of 2 total.
local allTexts = {}
local realCreateFrame = CreateFrame
CreateFrame = function(...)
    local f = realCreateFrame(...)
    local realCFS = f.CreateFontString
    f.CreateFontString = function(self, ...)
        local fs = realCFS(self, ...)
        allTexts[#allTexts + 1] = fs
        return fs
    end
    return f
end
_G.NexusCommunityBuildsFrame = nil
dofile("ui/CommunityBuilds.lua")
local CB2 = Nexus.CommunityBuilds
CB2.Init(Adapter, Model)
CB2.Show()
CB2.Select(id1)

local foundMissingCount = false
for _, fs in ipairs(allTexts) do
    local t = fs.text
    if type(t) == "string" then
        -- New detail panel shows "N echoes -- M missing" as a missingText line
        if t:find("1 missing") then foundMissingCount = true end
    end
end
assert(foundMissingCount, "detail panel did not show the correct missing count (expected 1 missing)")
print("detail panel shows correct owned/missing status -- OK")

-- 5. Lock-in must go through confirmation, then call the REAL upload path
local captured = nil
ProjectEbonhold.PerkService.UploadServerBuildSlot = function(slot, name, echoes)
    captured = { slot = slot, name = name, echoes = echoes }
    return true
end
CB2.LockInSelected()
assert(H.lastStaticPopup and H.lastStaticPopup.which == "NEXUS_LOCKIN_BUILD",
    "Lock In did not show a confirmation popup")
assert(H.lastStaticPopup.arg1 == rawBuildTitle:gsub("|", "||")
    and H.lastStaticPopup.data.title == rawBuildTitle,
    "Lock In popup did not project the title while retaining raw action data")
H.AcceptLastStaticPopup()
assert(captured, "accepting the confirmation did not call the real upload function")
assert(captured.name == rawBuildTitle, "wrong build name uploaded")
assert(#captured.echoes == 2, "wrong echo count uploaded")
print("Lock In goes through confirmation then calls the real, confirmed upload path -- OK")

-- 6. Delete removes it from the store and the list
CB2.DeleteBuild(id1)
assert(H.DurableBuilds()[id1] == nil, "DeleteBuild did not remove the entry")
print("DeleteBuild correctly removes a posted build -- OK")
