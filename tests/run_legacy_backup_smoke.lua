-- Optional read-only smoke test for a real SavedVariables backup.
-- Usage: luajit tests/run_legacy_backup_smoke.lua <Nexus backup.lua>
--
-- AUTHORIZATION GATE. This file is never part of the runnable suite: it is
-- listed in `manualTests` in tools/Run-LuaSuite.js and reported as an explicit
-- manual skip. It runs only when an operator passes an explicitly authorized
-- SavedVariables path, and the assert below is that gate. Nothing here
-- discovers a path, reads live SavedVariables, installs or runs the addon, or
-- writes anything back: the backup chunk is evaluated in its own environment
-- and the fixture only reads and asserts.
--
-- Legacy-to-bundle cutover (MASTER-RC-001; architecture 3b5de54f,
-- docs/SYNC_TRUST_CATALOG_AUTHORITY_STATE_MACHINE.md):
--   line 374   `authorityBundle` absent -> LEGACY_BUNDLE_MIGRATION_REQUIRED;
--              admit the exact PR #68 legacy inputs and build the first
--              complete bundle.
--   line 394   Those locations have no Package B writer. They are legacy
--              admission only, preserved input while the bundle is absent, and
--              "Never used as fallback after bundle occupancy."
--   line 4849  RAW-01: one complete `authorityBundle` pointer is the sole
--              durable payload write; legacy payload locations are read-only
--              inputs.
-- The backup contract this file characterizes is therefore now: a real v1.19.5
-- save is migrated into one complete bundle, every legacy byte it came from is
-- preserved untouched, public reads are served from the bundle, and a repeated
-- startup adopts the same bundle with no write and no generation advance.
--
-- The migration and backup assertions below are kept, not replaced. State
-- machine lines 2983-2985 (and partition audit 752-755) now retire the exact
-- PR #68 `LegacyDataMigration.Init/Pump/Finish` writer: it is inert until
-- `AuthorityBootstrapCoordinatorV1` classifies the recovery input and
-- authorizes one exact database. Both blocks were therefore moved onto that
-- replacement bootstrap contract, not deleted:
--   * the v1.19.5 block drives the writer through `Nexus.Store.Init()`, which
--     is the coordinator route and arms it as part of bootstrap;
--   * the v3-v5 converter block, which has no bootstrap of its own, performs
--     the same explicit `ClassifyLegacyWriterV1` classification the
--     coordinator performs before it drives a single pump.
-- Every convergence, preservation and budget assertion is unchanged.
local path = arg and arg[1]
assert(type(path) == "string" and path ~= "", "SavedVariables path required")

local chunk = assert(loadfile(path))
local loaded = {}
setfenv(chunk, loaded)
assert(pcall(chunk), "SavedVariables backup could not be evaluated")
assert(type(loaded.NexusDB) == "table", "backup did not contain NexusDB")

local H = dofile("tests/harness.lua")
UnitName = function() return "Ogie" end
GetNormalizedRealmName = function() return "Rogue-Lite(Live)" end
GetRealmName = GetNormalizedRealmName
UnitClass = function() return "Paladin", "PALADIN" end

local function Count(source)
    local total = 0
    for _ in pairs(type(source) == "table" and source or {}) do total=total+1 end
    return total
end

-- Deterministic structural encoding, used only to prove that a location was not
-- written. Sorted keys make the comparison order-independent.
local function StableEncode(value, depth)
    depth = depth or 0
    local kind = type(value)
    if kind ~= "table" then return kind .. ":" .. tostring(value) end
    if depth > 12 then return "table:deep" end
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = tostring(key) .. "\1" .. type(key)
    end
    table.sort(keys)
    local parts = {}
    for index, encoded in ipairs(keys) do
        local name = encoded:match("^(.*)\1")
        local key = value[name]
        if key == nil then key = value[tonumber(name)] end
        parts[index] = encoded .. "=" .. StableEncode(key, depth + 1)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function UniqueScalarConstants(source)
    local seen, constants = {}, {}
    local function Visit(value)
        local kind = type(value)
        if kind == "table" then
            if seen[value] then return end
            seen[value] = true
            for key, child in pairs(value) do Visit(key); Visit(child) end
        elseif kind == "string" or kind == "number" then
            constants[kind .. ":" .. tostring(value)] = true
        end
    end
    Visit(source)
    return Count(constants)
end

NexusDB = loaded.NexusDB
local root = NexusDB
local settings, builds = root.settings, root.communityBuilds
local chars = root.chars
local retention, catalog = root.dataRetention, root.buildCatalog
local dps = assert(root.dpsCapture, "backup had no DPS store")
local before = {
    accounts=Count(root.accountCharacters),
    personal=Count(dps.personalBest),build=Count(dps.buildBest),
    dummy=Count(dps.characterBest and dps.characterBest.dummy),
    lk=Count(dps.characterBest and dps.characterBest.lk),
}

-- The exact PR #68 payload locations as they existed before any Package B code
-- ran. After the cutover nothing may write them again.
local legacyOverlayBytes = StableEncode(root.communityBuilds)
local legacyTombstoneBytes = StableEncode(root.syncTombstones)
local legacyCatalogBytes = StableEncode(root.buildCatalog)
local legacyOverlayIdentity = root.communityBuilds
local legacyTombstoneIdentity = root.syncTombstones
assert(rawget(root, "authorityBundle") == nil,
    "the backup already contains a durable authority bundle; this fixture "
        .. "characterizes the first migration from legacy-only bytes")

local sourceSettingsVersion = tonumber(root.settingsVersion) or 0
if sourceSettingsVersion <= 2 then
    -- Main v1.19.5 saves take the coordinated current-owner path rather than
    -- the v3-v5 transactional conversion. Exercise the same startup order:
    -- Store migrates preferences/state, BuildCatalog binds the old overlay,
    -- and DpsCapture realm-qualifies represented character rows.
    dofile("core/Codec.lua")
    dofile("data/DefaultProfile.lua")
    dofile("data/BundledBuilds.lua")
    dofile("core/Store.lua")
    dofile("core/DpsCapture.lua")

    local buildIds = {}
    for id, row in pairs(type(builds) == "table" and builds or {}) do
        if type(row) == "table" then buildIds[#buildIds + 1] = id end
    end
    local started = os.clock()
    Nexus.Store.Init()
    local migrationPumps = 0
    local migrationStatus = Nexus.LegacyDataMigration.Status(root)
    while migrationStatus.pending do
        Nexus.LegacyDataMigration.Pump(32)
        migrationPumps = migrationPumps + 1
        assert(migrationPumps < 10000,
            "v1.19.5 staged class migration did not converge")
        migrationStatus = Nexus.LegacyDataMigration.Status(root)
    end
    local compactionPumps = 0
    while Nexus.DataCompaction.Stats(root).pending do
        Nexus.DataCompaction.Pump()
        compactionPumps = compactionPumps + 1
        assert(compactionPumps < 100000,
            "v1.19.5 evidence compaction did not converge")
    end
    Nexus.DataRetention.Init(root)
    local elapsed = os.clock() - started
    local after = {
        accounts=Count(root.accountCharacters),
        personal=Count(dps.personalBest),build=Count(dps.buildBest),
        dummy=Count(dps.characterBest and dps.characterBest.dummy),
        lk=Count(dps.characterBest and dps.characterBest.lk),
    }

    assert(root == NexusDB and root.settings == settings
            and root.chars == chars and root.communityBuilds == builds,
        "v1.19.5 startup replaced a table owned by another subsystem")
    assert(root.settingsVersion == Nexus.Store.SettingsVersion()
            and type(root.legacyDataMigration) == "table"
            and root.legacyDataMigration.state == "complete"
            and root.legacyDataMigration.version == 2,
        "v1.19.5 save did not take the guarded current-owner migration path")
    assert(type(root.buildFilters) == "table"
            and root.buildFilters.qualifiedOnly == false,
        "v1.19.5 upgrade defaulted to an empty Qualified Only view")
    -- One complete bundle is the sole durable payload write, and every legacy
    -- build is reachable through it rather than through the retired locations.
    local bundle = rawget(root, "authorityBundle")
    assert(type(bundle) == "table" and bundle.schemaVersion == 1
            and type(bundle.transactionGeneration) == "number"
            and bundle.transactionGeneration >= 1
            and type(bundle.communityBuilds) == "table"
            and bundle.communityBuilds ~= root.communityBuilds,
        "v1.19.5 startup did not publish one complete detached authority bundle")
    local migratedOverlayRows = 0
    for _, id in ipairs(buildIds) do
        local record, source = Nexus.BuildCatalog.Get(id)
        assert(record ~= nil,
            "v1.19.5 build became unreachable after catalog migration: "
                .. tostring(id))
        if source == "overlay" then
            migratedOverlayRows = migratedOverlayRows + 1
            assert(rawget(root, "authorityBundle").communityBuilds[id] ~= nil,
                "a served legacy build is not present in the durable bundle: "
                    .. tostring(id))
        end
    end
    -- Preservation: the exact PR #68 locations are byte-identical to the backup
    -- and keep their table identities. They took no Package B write at all.
    assert(root.communityBuilds == legacyOverlayIdentity
            and root.syncTombstones == legacyTombstoneIdentity
            and StableEncode(root.communityBuilds) == legacyOverlayBytes
            and StableEncode(root.syncTombstones) == legacyTombstoneBytes
            and StableEncode(root.buildCatalog) == legacyCatalogBytes,
        "v1.19.5 startup wrote or rewrote a legacy payload location")
    for _, category in ipairs({"dummy", "lk"}) do
        for key, row in pairs(type(dps.characterBest) == "table"
            and type(dps.characterBest[category]) == "table"
            and dps.characterBest[category] or {}) do
            if type(row) == "table" then
                local owner = Nexus.Identity.CanonicalOwnerKey(row.ownerKey)
                if owner and not owner:match("@unknown$") then
                    assert(key == owner,
                        "represented DPS row was not realm-qualified")
                end
            end
        end
    end
    assert(after.personal == before.personal and after.build == before.build
            and after.dummy == before.dummy and after.lk == before.lk
            and after.accounts >= 1,
        "v1.19.5 startup unexpectedly lost a DPS map or account identity")
    local retentionLimits = Nexus.DataRetention.Limits(root)
    assert(retentionLimits.enabled == false
            and retentionLimits.contentUnlimited == true,
        "v1.19.5 migration unexpectedly enabled content retention limits")

    Nexus.DpsCapture.Init({}, {})
    Nexus.ViewProjections.Reset()
    local visibleBuilds, visibleSummary, visibleReason =
        Nexus.ViewProjections.RequestBuilds(root.buildFilters)
    local buildPumps = 0
    while type(visibleBuilds) ~= "table" do
        assert(visibleReason == "pending", tostring(visibleReason))
        local published, pumpError = Nexus.ViewProjections.PumpBuilds()
        assert(not pumpError, tostring(pumpError))
        buildPumps = buildPumps + 1
        assert(buildPumps < 10000, "legacy Builds projection did not converge")
        if published then
            visibleBuilds, visibleSummary, visibleReason =
                Nexus.ViewProjections.RequestBuilds(root.buildFilters)
        end
    end
    assert(#visibleBuilds > 0
            and (tonumber(visibleSummary and visibleSummary.availableCount) or 0) > 0,
        "v1.19.5 upgrade opened on an empty migrated Builds projection")

    local function ProjectLeaderboard(category)
        Nexus.ViewProjections.Reset()
        local rows, _, reason = Nexus.ViewProjections.RequestLeaderboard(
            category, {classFilter="ALL",search=""})
        local pumps = 0
        while type(rows) ~= "table" do
            assert(reason == "pending", tostring(reason))
            local published, pumpError = Nexus.ViewProjections.PumpLeaderboard()
            assert(not pumpError, tostring(pumpError))
            pumps = pumps + 1
            assert(pumps < 10000, "legacy leaderboard projection did not converge")
            if published then
                rows, _, reason = Nexus.ViewProjections.RequestLeaderboard(
                    category, {classFilter="ALL",search=""})
            end
        end
        local classified = 0
        for _, row in ipairs(rows) do
            if type(row.resolvedClass) == "string" then
                classified = classified + 1
            end
        end
        return #rows, classified, pumps
    end
    local dummyRows, dummyClasses, dummyPumps = ProjectLeaderboard("dummy")
    local lkRows, lkClasses, lkPumps = ProjectLeaderboard("lk")
    assert(dummyRows > 0 and lkRows > 0
            and dummyClasses > 0 and lkClasses > 0,
        "v1.19.5 leaderboard lost exact build-id/hash class recovery")

    local encoded = assert(Nexus.Codec.JSONEncode(root))
    local evidenceEntries = Nexus.LoadoutEvidence.Snapshot()
    local evidenceCount = Count(evidenceEntries)
    local constantCount = UniqueScalarConstants(root)
    assert(constantCount < 60000,
        "converted v1.19.5 state approaches Lua's 65536-constant chunk limit")
    local topLevel = {}
    for key, value in pairs(root) do
        topLevel[key] = Nexus.Codec.JSONEncode(value)
    end
    -- Restart is idempotent and takes the architecture's zero-delta route: the
    -- occupied bundle is adopted with no bundle allocation, no bundle write and
    -- no transaction-generation advance.
    local bundleBeforeRestart = rawget(root, "authorityBundle")
    local generationBeforeRestart = bundleBeforeRestart.transactionGeneration
    Nexus.Store.Init()
    assert(rawget(root, "authorityBundle") == bundleBeforeRestart
            and bundleBeforeRestart.transactionGeneration
                == generationBeforeRestart,
        "a repeated v1.19.5 startup replaced, wrote, or advanced the bundle")
    assert(root.communityBuilds == legacyOverlayIdentity
            and StableEncode(root.communityBuilds) == legacyOverlayBytes,
        "a repeated v1.19.5 startup wrote a legacy payload location")
    if Nexus.Codec.JSONEncode(root) ~= encoded then
        local changed = {}
        for key, value in pairs(root) do
            if topLevel[key] ~= Nexus.Codec.JSONEncode(value) then
                changed[#changed + 1] = tostring(key)
            end
        end
        table.sort(changed)
        error("repeated v1.19.5 startup migration changed owners: "
            .. table.concat(changed, ","))
    end
    print(string.format(
        "real v1.19.5 backup migration: builds=%d migratedOverlay=%d bundleGeneration=%d personal=%d build=%d DPS=%d/%d accounts=%d evidence=%d constants=%d jsonBytes=%d migrationPumps=%d compactionPumps=%d visible=%d buildPumps=%d classes=%d/%d,%d/%d classPumps=%d/%d elapsed=%.3fs -- OK",
        #buildIds,migratedOverlayRows,generationBeforeRestart,
        after.personal,after.build,after.dummy,after.lk,
        after.accounts,evidenceCount,constantCount,#encoded,
        migrationPumps,compactionPumps,#visibleBuilds,buildPumps,
        dummyClasses,dummyRows,lkClasses,lkRows,
        dummyPumps,lkPumps,elapsed))
    return
end

Nexus.DataCompaction = {Init=function() return {} end}
Nexus.DataRetention = {Request=function() return true end}
Nexus.ViewRefresh = {Request=function() return true end}

local started = os.clock()
-- The retired direct entry point is inert until the coordinator authorizes
-- this exact database (state machine 2983-2985). Prove that first, then take
-- the replacement bootstrap route.
local retiredResult = Nexus.LegacyDataMigration.Init(root)
assert(retiredResult.retired == true and retiredResult.pending ~= true
    and rawget(root, "legacyDataMigration") == nil,
    "the retired converter began a migration without coordinator authority")
local authorized = Nexus.LegacyDataMigration.ClassifyLegacyWriterV1(root,
    {owner="authority-bootstrap-coordinator"})
assert(authorized.armed, "the coordinator refused to authorize the backup "
    .. "conversion: " .. tostring(authorized.classification))
local result = Nexus.LegacyDataMigration.Init(root)
assert(result.pending, "known v5 backup did not enter migration")
local pumps = 0
while not Nexus.LegacyDataMigration.Pump(32) do
    pumps = pumps + 1
    assert(pumps < 10000, "backup migration did not converge")
end
local elapsed = os.clock() - started
local after = {
    accounts=Count(root.accountCharacters),
    personal=Count(dps.personalBest),build=Count(dps.buildBest),
    dummy=Count(dps.characterBest and dps.characterBest.dummy),
    lk=Count(dps.characterBest and dps.characterBest.lk),
}
local status = Nexus.LegacyDataMigration.Status(root)

assert(root == NexusDB and root.settings == settings
    and root.communityBuilds == builds and root.dataRetention == retention
    and root.buildCatalog == catalog,
    "converter replaced a table owned by another subsystem")
-- The v3-v5 converter is not an authority writer. It never publishes a durable
-- bundle and never rewrites a legacy payload location: only the authorized
-- bootstrap route does that (state machine lines 374, 394, 4849).
assert(rawget(root, "authorityBundle") == nil,
    "the legacy converter published a durable authority bundle")
assert(StableEncode(root.communityBuilds) == legacyOverlayBytes
    and StableEncode(root.syncTombstones) == legacyTombstoneBytes
    and StableEncode(root.buildCatalog) == legacyCatalogBytes,
    "the legacy converter rewrote a PR #68 payload location")
assert(root.legacyDataMigration.state == "complete"
    and root.legacyDataMigration.staging == nil,
    "backup migration did not commit cleanly")
assert(after.accounts >= before.accounts
    and after.personal == before.personal and after.build == before.build,
    "backup migration unexpectedly lost valid account or fingerprint maps")
assert(after.dummy > 0 and after.lk > 0
    and status.runtime.maxWork <= Nexus.LegacyDataMigration.BatchSize(),
    "backup migration lost a DPS category or exceeded its batch budget")

print(string.format(
    "real backup migration: accounts=%d/%d personal=%d build=%d DPS=%d/%d -> %d/%d pumps=%d elapsed=%.3fs quarantined=%d -- OK",
    before.accounts,after.accounts,after.personal,after.build,
    before.dummy,before.lk,after.dummy,after.lk,pumps,elapsed,
    tonumber(root.legacyDataMigration.lastResult.quarantined) or 0))
