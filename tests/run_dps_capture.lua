-- DPS capture: always-on, two categories (dummy / LK), target detection,
-- personal best tracking, leaderboard sorting, peer submission.
local H = dofile("tests/harness.lua")
local S = dofile("tests/catalog_authority_support.lua")
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
-- MASTER-RC-001 (architecture 1207-1211): Sync.Init and DpsCapture.Init no
-- longer admit the catalog root as a side effect. The same admission is
-- performed explicitly here, before the call, because the removed side
-- effect ran inside Init ahead of Init's own dependent steps. No assertion
-- or expected value in this fixture is changed.
H.AdmitCatalogV1(NexusDB)
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
S.PumpCatalogToIdle("dummy session exact-build admission")
local lb = DPS.GetLeaderboard(buildId,"dummy")
local currentDummy = DPS.GetCurrentPersonalBest("dummy")
assert(#lb == 1 and lb[1].dps == 75000,
    "dummy session not recorded: " .. (#lb > 0 and lb[1].dps or "empty")
        .. " currentBuildId=" .. tostring(currentDummy and currentDummy.buildId)
        .. " candidate="
        .. tostring(Nexus.BuildCatalog.RootState().candidate))
assert(#DPS.GetLeaderboard(buildId,"lk") == 0, "LK leaderboard should be empty after dummy session")
print("dummy session recorded correctly, LK leaderboard untouched -- OK")

-- 3. Lich King session recorded in separate category
UnitGUID = function(unit) return unit == "target" and LK_GUID or nil end
stubDps = 90000
DPS.OnCombatStart()
clock = clock + 40; DPS.OnUpdate(10); DPS.OnUpdate(10); DPS.OnUpdate(10)
DPS.OnCombatEnd()
S.PumpCatalogToIdle("LK session exact-build admission")
local lkLb = DPS.GetLeaderboard(buildId,"lk")
assert(#lkLb == 1 and lkLb[1].dps == 90000, "LK session not recorded")
assert(#DPS.GetLeaderboard(buildId,"dummy") == 1, "dummy leaderboard should be unchanged")
print("LK session recorded in its own category -- OK")

-- 4. Personal best: lower doesn't replace, higher does
UnitGUID = function(unit) return unit == "target" and DUMMY_GUID or nil end
stubDps = 60000  -- lower
DPS.OnCombatStart(); clock = clock + 40; DPS.OnUpdate(10); DPS.OnUpdate(10); DPS.OnCombatEnd()
S.PumpCatalogToIdle("lower dummy session catalog work")
assert(DPS.GetLeaderboard(buildId,"dummy")[1].dps == 75000, "lower DPS must not replace best")

stubDps = 100000  -- higher
local rawBuildTitle = "Rogue |cffff0000Test|r"
NexusDB.communityBuilds[buildId].title = rawBuildTitle
local savedCommunity = Nexus.CommunityBuilds
Nexus.CommunityBuilds = {
    EnsureDpsBuildForEchoes=function()
        return buildId, NexusDB.communityBuilds[buildId]
    end,
}
local savedPrint, printed = print, {}
print = function(...)
    local values = {}
    for index = 1, select("#", ...) do
        values[index] = tostring(select(index, ...))
    end
    printed[#printed + 1] = table.concat(values, "\t")
end
DPS.OnCombatStart(); clock = clock + 40; DPS.OnUpdate(10); DPS.OnUpdate(10); DPS.OnCombatEnd()
S.PumpCatalogToIdle("higher dummy session exact-build admission")
print = savedPrint
Nexus.CommunityBuilds = savedCommunity
local safeBuildTitle = rawBuildTitle:gsub("|", "||")
local foundSafeNotice = false
for _, line in ipairs(printed) do
    if line:find("New best for '" .. safeBuildTitle .. "'", 1, true) then
        foundSafeNotice = true
    end
end
assert(foundSafeNotice and NexusDB.communityBuilds[buildId].title == rawBuildTitle,
    "DPS new-best notice did not project the remote title without rewriting it")
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

-- Real maintenance replaces the durable graph. Later public DPS writes must
-- reach that graph, not the superseded legacy alias or a warmed identity index.
NexusDB = S.Database({[buildId]=S.LocalBuild(buildId, 1, {author="Remote",
    ownerKey="remote@ebonhold",isMine=false,class="ROGUE"})}, nil, {settings={communityRetentionEnabled=true,
    communityRetentionTopPerCategory=25,communityRetentionMinPerClassPerCategory=1},
    dpsCapture={lockedMigrationVersion=1,
    personalBest={},buildBest={},characterBest={dummy={},lk={}}}})
for index = 1, 26 do
    local player = "Maintenance" .. index
    NexusDB.dpsCapture.characterBest.dummy[player:lower() .. "@ebonhold"] = {
        player=player,ownerKey=player:lower() .. "@ebonhold",realm="ebonhold",
        ownerVerified=true,class="ROGUE",buildId=buildId,fingerprint="100000x1",
        echoes={{spellId=100000,quality=3,stacks=1}},lockedEchoes={},
        dps=100+index,duration=30,category="dummy",ts=wall}
end
H.BootstrapStoreReady()
DPS.Init(Adapter, nil)
S.PumpCatalogToIdle("DPS maintenance fixture startup")
local startupCompaction
for _ = 1, 20000 do
    startupCompaction = Nexus.DataCompaction.Pump()
    if not startupCompaction.pending then break end
    Nexus.BuildCatalog.PumpRootAdmission()
end
assert(not startupCompaction.pending and not startupCompaction.blocked,
    "startup compaction failed to settle: " .. tostring(startupCompaction.reason))
local beforeMaintenance = NexusDB.authorityBundle.dpsCapture
DPS.GetSyncHash()
DPS.GetLeaderboard(buildId, "dummy")
local retainedBoard = DPS.BeginDpsBoardCursor("dummy")
local retainedEligibility = DPS.BeginCommunityEligibilityCursor()
local maintenance = Nexus.DataRetention.Enforce(NexusDB, "tester DPS adoption")
for _ = 1, 20000 do
    if not maintenance.pending then break end
    Nexus.BuildCatalog.PumpRootAdmission()
    maintenance = Nexus.DataRetention.Enforce(NexusDB, "tester DPS adoption")
end
assert(not maintenance.pending and not maintenance.blocked,
    "public retention failed to settle: " .. tostring(maintenance.reason))
local currentDps = NexusDB.authorityBundle.dpsCapture
assert(currentDps ~= beforeMaintenance, "retention did not replace DPS graph")
assert(maintenance.characterBestRemoved == 1,
    "retention did not remove the supported lowest DPS row: "
        .. tostring(maintenance.characterBestRemoved) .. "/"
        .. tostring(maintenance.selectedDummy))
assert(#DPS.GetDpsBoard("dummy") == 25,
    "public board still includes the removed row")
local staleDone, staleWhy = DPS.DpsBoardCursorNext(retainedBoard)
assert(staleDone and staleWhy == "DPS changed",
    "retained board cursor accepted the superseded graph")
local eligibilityDone, eligibilityWhy = DPS.CommunityEligibilityCursorNext(retainedEligibility)
assert(eligibilityDone and eligibilityWhy == "DPS changed",
    "retained eligibility cursor accepted the superseded graph")
assert(DPS.ReceiveSubmission(buildId, "Tester", 130000, 80, "dummy", wall, 30),
    "post-maintenance public submission refused")
local durableTester
for _, row in pairs(currentDps.characterBest.dummy) do
    if row.player == "Tester" then durableTester = row end
end
assert(durableTester and durableTester.dps == 130000,
    "post-maintenance DPS write missed the authoritative bundle")
assert(DPS.GetLeaderboard(buildId, "dummy")[1].player == "Tester",
    "post-maintenance leaderboard retained the superseded graph")
local republished = Nexus.BuildCatalog.Get(buildId)
republished.title = "Maintenance publication"
republished.lastModified = republished.lastModified + 1
assert(S.AwaitCatalogMutation(Nexus.BuildCatalog.Put(republished)),
    "post-maintenance catalog publication failed")
assert(Nexus.BuildCatalog.Get(buildId).title == republished.title,
    "post-maintenance catalog update was not applied")
assert(NexusDB.authorityBundle.dpsCapture.characterBest.dummy["maintenance1@ebonhold"] == nil,
    "later catalog publication revived a pruned legacy DPS row")
assert(DPS.GetLeaderboard(buildId, "dummy")[1].player == "Tester",
    "later catalog publication lost a new DPS result")

-- Cancelled and refused maintenance must not replace any accepted DPS row.
local preservedBundle = NexusDB.authorityBundle
local cancelled = assert(Nexus.BuildCatalog.BeginCatalogMaintenance({database=NexusDB,
    operation="tester cancellation"}))
assert(Nexus.BuildCatalog.CancelMaintenance(cancelled), "maintenance cancellation refused")
assert(Nexus.BuildCatalog.CommitMaintenance(cancelled) == false,
    "cancelled maintenance committed")
assert(NexusDB.authorityBundle == preservedBundle
        and DPS.GetLeaderboard(buildId, "dummy")[1].player == "Tester",
    "cancelled maintenance changed accepted DPS data")

-- Synthetic serialization destroys session identities. Keep durable bytes,
-- reload the real domain modules, and bootstrap through the Store coordinator.
local savedEpoch = NexusDB.authorityBundle.dpsAuthority.preparationEpoch
local savedBytes = Nexus.Codec.JSONEncode(NexusDB)
NexusDB = assert(Nexus.Codec.JSONDecode(savedBytes))
S.Reload()
dofile("core/DpsCapture.lua")
DPS = Nexus.DpsCapture
H.BootstrapStoreReady()
DPS.Init(Adapter, nil)
assert(NexusDB.authorityBundle.dpsAuthority.preparationEpoch == savedEpoch,
    "ordinary reload unexpectedly changed the persisted sidecar epoch")
assert(DPS.GetLeaderboard(buildId, "dummy")[1].player == "Tester"
        and #DPS.GetDpsBoard("dummy") == 26,
    "synthetic reload lost the post-maintenance result or revived the removed row")
assert(NexusDB.authorityBundle.dpsCapture.characterBest.dummy["maintenance1@ebonhold"] == nil,
    "synthetic reload used preserved legacy DPS as fallback")
print("DPS public retention and later submission share the durable graph -- OK")

-- A restarted session must also complete later maintenance without adopting
-- the serialized epoch as session authority or falling back to legacy rows.
for _ = 1, 20000 do
    startupCompaction = Nexus.DataCompaction.Pump()
    if not startupCompaction.pending then break end
    Nexus.BuildCatalog.PumpRootAdmission()
end
assert(not startupCompaction.pending and not startupCompaction.blocked,
    "post-reload compaction did not settle")
local reloadMaintenance = Nexus.DataRetention.Enforce(NexusDB, "tester reload assessment")
for _ = 1, 20000 do
    if not reloadMaintenance.pending then break end
    Nexus.BuildCatalog.PumpRootAdmission()
    reloadMaintenance = Nexus.DataRetention.Enforce(NexusDB, "tester reload assessment")
end
assert(not reloadMaintenance.pending and not reloadMaintenance.blocked
        and #DPS.GetDpsBoard("dummy") == 25
        and DPS.GetLeaderboard(buildId, "dummy")[1].player == "Tester",
    "persisted sidecar metadata changed later maintenance or DPS results")
print("synthetic sidecar reload and later maintenance -- OK")

-- Catalog class repair must retain a pending write and publish its metadata
-- revision only after that exact write commits.
local classRows = {}
for index = 1, 9 do
    local id = string.format("pending-class-%02d", index)
    classRows[id] = S.LocalBuild(id, 1, {author="Solkr",
        ownerKey="solkr@ebonhold", realm="ebonhold", class="ROGUE",
        autoDps=true, title="Rogue Record Loadout"})
end
NexusDB = S.Database(classRows)
GetNormalizedRealmName = function() return "Ebonhold" end
UnitClass = function() return "Rogue", "ROGUE" end
H.AdmitCatalogV1(NexusDB, Nexus.BundledBuilds)
DPS.Init(Adapter, nil)
local classRow = {player="Solkr", ownerKey="solkr@ebonhold", realm="ebonhold",
    ownerVerified=true, class="MAGE", buildId="pending-class-01",
    fingerprint="100000x1", echoes={{spellId=100000,quality=3,stacks=1}},
    lockedEchoes={}, dps=100, duration=30, category="dummy", ts=wall}
S.Durable(NexusDB, "dpsCapture").characterBest.dummy["solkr@ebonhold"] = classRow
UnitClass = function() return "Mage", "MAGE" end
local revisions, revisionKey = Nexus.Revisions, Nexus.Revisions.DPS_CHANGED
local revisionBefore = revisions.Get(revisionKey)
DPS.GetDpsBoard("dummy")
assert(Nexus.BuildCatalog.RootState().candidate == true
        and Nexus.BuildCatalog.Get("pending-class-01").class == "ROGUE",
    "DPS class repair did not enter its real pending catalog path")
assert(revisions.Get(revisionKey) == revisionBefore,
    "DPS published class repair before the catalog mutation committed")
local outcome
for _ = 1, Nexus.BuildCatalog.Budget().maximumPumps do
    outcome = Nexus.BuildCatalog.PumpRootAdmission()
    if outcome.state ~= "pending" then break end
end
assert(outcome.committed == true
        and Nexus.BuildCatalog.Get("pending-class-01").class == "MAGE"
        and revisions.Get(revisionKey) == revisionBefore + 1,
    "DPS did not publish its terminal class repair exactly once")
print("DPS pending class repair settles once -- OK")
print("All DPS capture tests passed.")
