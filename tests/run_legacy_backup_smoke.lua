-- Optional read-only smoke test for a real SavedVariables backup.
-- Usage: luajit tests/run_legacy_backup_smoke.lua <Nexus backup.lua>
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
    for _, id in ipairs(buildIds) do
        assert(Nexus.BuildCatalog.Get(id) ~= nil,
            "v1.19.5 build became unreachable after catalog migration: "
                .. tostring(id))
    end
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
    Nexus.Store.Init()
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
        "real v1.19.5 backup migration: builds=%d personal=%d build=%d DPS=%d/%d accounts=%d evidence=%d constants=%d jsonBytes=%d migrationPumps=%d compactionPumps=%d visible=%d buildPumps=%d classes=%d/%d,%d/%d classPumps=%d/%d elapsed=%.3fs -- OK",
        #buildIds,after.personal,after.build,after.dummy,after.lk,
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
