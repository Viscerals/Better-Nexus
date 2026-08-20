-- DPS capture: always-on, two categories (dummy / LK), target detection,
-- personal best tracking, leaderboard sorting, peer submission.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
dofile("data/DefaultProfile.lua"); dofile("logic/Model.lua"); dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua"); dofile("logic/Policy.lua"); dofile("core/Store.lua")
dofile("core/GameAdapter.lua")

local DPS = Nexus.DpsCapture
local Adapter = Nexus.GameAdapter
local clock = 1000; GetTime = function() return clock end
local wall = 50000; time = function() return wall end
UnitName = function() return "Solkr" end
UnitLevel = function() return 80 end

-- Stub Details!
local stubDps = 0
Details = {
    GetCurrentCombat = function()
        return {
            GetActor = function(_, attr, name)
                if stubDps <= 0 then return nil end
                return { total = stubDps * 30, Tempo = function(_) return 30 end }
            end,
            GetCombatTime = function(_) return 30 end,
        }
    end
}
DETAILS_ATTRIBUTE_DAMAGE = 1

-- Training dummy GUID
local DUMMY_GUID = "Creature-0-1823-0-28-36476-000095AF5E"  -- NPC 36476
local LK_GUID    = "Creature-0-631-0-28-36597-0000ABCDEF"   -- NPC 36597
UnitGUID = function(unit) return unit == "target" and DUMMY_GUID or nil end
UnitExists = function(unit) return unit == "target" end

NexusDB = { communityBuilds={}, syncTombstones={}, dpsCapture={} }
H.playerLevel = 5
H.wishlist = { name="W", class="ROGUE", echoes={{spellId=200100,quality=3,stacks=1}} }
H.granted = { ["Alpha Strike"]={{spellId=200100,stack=1,maxStack=1,quality=3}} }
H.FireEvent("SPELLS_CHANGED"); H.FireEvent("PLAYER_ENTERING_WORLD"); H.Advance(2)

local buildId = "test-build-1"
NexusDB.communityBuilds[buildId] = {
    id=buildId, title="Rogue Test", author="explore", class="ROGUE",
    echoes={{spellId=200100,quality=3,stacks=1}},
    postedAt=50000, lastModified=50000, isMine=false,
}
DPS.Init(Adapter, nil)
assert(DPS.IsEnabled(), "DPS capture should always be enabled")
print("DPS capture is always-on -- OK")

-- 1. Short dummy session: not committed
stubDps = 50000
UnitGUID = function(unit) return unit == "target" and DUMMY_GUID or nil end
DPS.OnCombatStart()
clock = clock + 10  -- only 10s
DPS.OnCombatEnd()
assert(#DPS.GetLeaderboard(buildId,"dummy") == 0, "short session must not commit")
print("short session correctly ignored -- OK")

-- 2. Valid dummy session
DPS.OnCombatStart()
clock = clock + 20; DPS.OnUpdate(10); DPS.OnUpdate(10)
stubDps = 75000
clock = clock + 15; DPS.OnCombatEnd()
local lb = DPS.GetLeaderboard(buildId,"dummy")
assert(#lb == 1 and lb[1].dps == 75000, "dummy session not recorded: "..(#lb > 0 and lb[1].dps or "empty"))
assert(#DPS.GetLeaderboard(buildId,"lk") == 0, "LK leaderboard should be empty after dummy session")
print("dummy session recorded correctly, LK leaderboard untouched -- OK")

-- 3. Lich King session recorded in separate category
UnitGUID = function(unit) return unit == "target" and LK_GUID or nil end
stubDps = 90000
DPS.OnCombatStart()
clock = clock + 40; DPS.OnUpdate(10); DPS.OnUpdate(10); DPS.OnUpdate(10)
DPS.OnCombatEnd()
local lkLb = DPS.GetLeaderboard(buildId,"lk")
assert(#lkLb == 1 and lkLb[1].dps == 90000, "LK session not recorded")
assert(#DPS.GetLeaderboard(buildId,"dummy") == 1, "dummy leaderboard should be unchanged")
print("LK session recorded in its own category -- OK")

-- 4. Personal best: lower doesn't replace, higher does
UnitGUID = function(unit) return unit == "target" and DUMMY_GUID or nil end
stubDps = 60000  -- lower
DPS.OnCombatStart(); clock = clock + 40; DPS.OnUpdate(10); DPS.OnUpdate(10); DPS.OnCombatEnd()
assert(DPS.GetLeaderboard(buildId,"dummy")[1].dps == 75000, "lower DPS must not replace best")

stubDps = 100000  -- higher
DPS.OnCombatStart(); clock = clock + 40; DPS.OnUpdate(10); DPS.OnUpdate(10); DPS.OnCombatEnd()
local pb = DPS.GetPersonalBest(buildId,"dummy")
assert(pb and pb.dps == 100000, "higher DPS should replace best")
assert(#DPS.GetLeaderboard(buildId,"dummy") == 1, "still one entry per player")
print("personal best updates correctly (lower ignored, higher replaces) -- OK")

-- 5. Peer submission: only the highest record for each exact build/category is retained
DPS.ReceiveSubmission(buildId,"Alice",120000,80,"dummy",12345,30)
local lb2 = DPS.GetLeaderboard(buildId,"dummy")
assert(#lb2 == 1 and lb2[1].player=="Alice" and lb2[1].dps==120000, "Alice should hold the single dummy record")
DPS.ReceiveSubmission(buildId,"Alice",85000,80,"lk",12345,20)
local lk2 = DPS.GetLeaderboard(buildId,"lk")
assert(#lk2 == 1 and lk2[1].player=="Solkr" and lk2[1].dps==90000, "lower LK data must not replace the record")
DPS.ReceiveSubmission(buildId,"Alice",125000,80,"lk",12346,20)
lk2 = DPS.GetLeaderboard(buildId,"lk")
assert(#lk2 == 1 and lk2[1].player=="Alice" and lk2[1].dps==125000, "higher LK data should replace the record")
print("peer submissions retain only the highest exact-build record -- OK")

-- 6. Submission for unknown build: silently ignored
DPS.ReceiveSubmission("no-such-build","Bob",999999,80,"dummy",0,30)
assert(#DPS.GetLeaderboard("no-such-build","dummy") == 0,
    "unknown build submission must be silently ignored")
print("unknown build submission ignored -- OK")

-- 7. Lower remote data cannot replace the single record
DPS.ReceiveSubmission(buildId,"Carol",110000,80,"dummy",12345,30)
DPS.ReceiveSubmission(buildId,"Dave",95000,80,"dummy",12345,30)
local lb3 = DPS.GetLeaderboard(buildId,"dummy")
assert(#lb3 == 1 and lb3[1].player == "Alice" and lb3[1].dps == 120000,
    "lower remote submissions must not replace the record")
print("single-record leaderboard rejects lower data -- OK")

print("All DPS capture tests passed.")
