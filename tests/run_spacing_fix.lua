-- Regression for the live "lock in failed: spacing" bug (2026-07-24).
-- Root cause: A.RequestSlots() is a READ but stamped the same
-- lastBuildOpAt guard that throttles WRITES. The background loop calls
-- it every ~5s and the write guard is 3s, so a manual Lock In / Apply
-- was refused roughly 60% of the time.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")

local A = Nexus.GameAdapter
local clock = 1000
GetTime = function() return clock end

NexusDB = {}
H.wishlist = { name = "W", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 } } }
H.playerLevel = 5
H.FireEvent("SPELLS_CHANGED")
H.FireEvent("PLAYER_ENTERING_WORLD")

local uploaded = nil
ProjectEbonhold.PerkService.UploadServerBuildSlot = function(slot, name, echoes)
    uploaded = { slot = slot, name = name, echoes = echoes }
    return true
end

local echoes = { { spellId = 200100, quality = 3, stacks = 1 } }

-- THE BUG: a read-only slot refresh immediately before a write must NOT
-- block that write.
clock = clock + 100
A.RequestSlots()                       -- background refresh (a READ)
clock = clock + 0.1                    -- essentially immediately after
local ok, err = A.UploadWishlist(0, "Test", echoes)
assert(ok, "a read-only RequestSlots() blocked a user-initiated write: " .. tostring(err))
assert(uploaded, "upload never reached the server call")
print("a background slot refresh no longer blocks a manual write -- OK")

-- The genuine write-vs-write guard must still work (two real writes
-- back-to-back are still correctly spaced).
uploaded = nil
local ok2, err2 = A.UploadWishlist(0, "Test2", echoes)
assert(not ok2 and err2 == "spacing",
    "two real writes back-to-back should still be spacing-guarded")
print("genuine write-vs-write spacing protection still intact -- OK")

-- ...and clears once enough time passes.
clock = clock + 5
local ok3 = A.UploadWishlist(0, "Test3", echoes)
assert(ok3, "write should succeed once the spacing window has passed")
print("write spacing correctly clears after the guard window -- OK")

-- Simulate the REAL failure pattern: the background loop refreshing
-- every 5s while the user clicks Lock In at an arbitrary moment. Before
-- the fix this failed ~60% of the time; now it must always succeed.
local failures = 0
for i = 1, 40 do
    clock = clock + 5
    A.RequestSlots()                   -- background refresh tick
    clock = clock + (i % 5) * 0.5      -- user clicks at varying offsets
    local okN = A.UploadWishlist(0, "Repeated", echoes)
    if not okN then failures = failures + 1 end
    clock = clock + 5                  -- spacing clears before next iteration
end
assert(failures == 0,
    failures .. "/40 manual writes were still blocked by background refreshes")
print("40/40 manual writes succeed against a live background refresh loop -- OK")

------------------------------------------------------------------------
-- Safety net: even if a genuine collision happens (the automation just
-- performed a real write), a user-initiated Lock In should RETRY rather
-- than failing outright.
------------------------------------------------------------------------
dofile("ui/CommunityBuilds.lua")
local CB = Nexus.CommunityBuilds
CB.Init(A, Nexus.Model)

-- Legacy-to-bundle cutover (architecture 3b5de54f state machine lines 374,
-- 394, 4849): the durable authority payload is `authorityBundle`; the exact
-- PR #68 locations are read-only preserved bootstrap input.
-- Seeded as exact PR #68 legacy input on a fresh database, so bootstrap admits
-- it and builds the first complete bundle (line 374).
NexusDB = { syncTombstones = {}, dpsCapture = NexusDB.dpsCapture,
    buildFilters = NexusDB.buildFilters }
NexusDB.communityBuilds = { ["b1"] = { id = "b1", title = "Retry Test",
    description = "d", author = "Bob", class = "MAGE",
    echoes = { { spellId = 200100, quality = 3, stacks = 1 } },
    postedAt = 1, lastModified = 1, isMine = false } }
Nexus.BuildCatalog.Init(NexusDB, Nexus.BundledBuilds)
CB.Show()
CB.Select("b1")

-- force a genuine collision: a real write immediately before
clock = clock + 10
A.UploadWishlist(0, "Occupier", echoes)
uploaded = nil

CB.LockInSelected()
H.AcceptLastStaticPopup()
assert(CB.IsLockInPending(), "a spacing collision should have queued a retry, not failed outright")
assert(uploaded == nil, "should not have uploaded yet -- still spacing-blocked")
print("a genuine spacing collision queues a retry instead of failing -- OK")

-- let time pass and pump the retry
clock = clock + 5
CB._PumpPendingLockIn()
assert(uploaded, "the queued retry never completed the upload")
assert(uploaded.name == "Retry Test", "retry uploaded the wrong build")
assert(not CB.IsLockInPending(), "pending state should clear after a successful retry")
print("the queued retry completes automatically once the window clears -- OK")
