-- Nexus: core/Store.lua
-- SavedVariables ownership ONLY (global: NexusDB): settings
-- plus per-character safety state. core/ may touch SavedVariables and
-- UnitName; nothing else. Main calls Store.Init() at ADDON_LOADED --
-- never earlier (the client replaces the global when the file loads).

Nexus = Nexus or {}
local Identity = assert(Nexus.Identity,
    "Nexus Identity must load before Store")
local Store = {}
Nexus.Store = Store

-- Versioned shape changes are additive and ordered. User preferences,
-- per-character safety state, and unknown/future fields are never rebuilt
-- merely because the shipped defaults or schema version changed.
local SETTINGS_VERSION = 2
local LEGACY_MIGRATION_NAMESPACE = "nexusStoreMigrations"
local LEGACY_MIGRATION_KEY = "wishlistRealizerDB"
local LEGACY_MIGRATION_VERSION = 1

local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = DeepCopy(v) end
    return out
end

local function FillMissing(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then return end
    for key, default in pairs(defaults) do
        local current = target[key]
        if current == nil then
            target[key] = DeepCopy(default)
        elseif type(current) == "table" and type(default) == "table" then
            -- Lists are atomic user choices: an explicitly empty anchorNames
            -- list must not be repopulated from shipped numeric entries.
            local isList = false
            for defaultKey in pairs(default) do
                if type(defaultKey) == "number" then isList = true; break end
            end
            if not isList then FillMissing(current, default) end
        end
    end
end

local function FreshState()
    return {
        tomeTogglePending = {}, -- [leverId] = { t=sentAtTime, want=bool }
        priorAutoAccept = nil,  -- autoAcceptLoadoutEchoes before we touched it
        flagDemotions = {},     -- [flagName] = reason (runtime self-check)
        recordedPicks = {},     -- [spellId] = count (session; adapter-managed)
        loadoutWishlists = {},  -- [numbered loadout slot] = stable designed-wishlist identity
    }
end

local function EnsureStateShape(state)
    if type(state) ~= "table" then return FreshState() end
    for _, field in ipairs({
        "tomeTogglePending", "flagDemotions", "recordedPicks", "loadoutWishlists",
    }) do
        if type(state[field]) ~= "table" then state[field] = {} end
    end
    return state
end

-- Returned while the real store is unusable (pre-Init call, or
-- UnitName not yet real -- addendum B5: never latch a bad char key).
-- Deliberately never merged into the persisted store.
local transientState
local transientSettings

local function NormalizeVersion(value)
    value = tonumber(value)
    if not value or value ~= value or value < 0 or value >= math.huge
        or value ~= math.floor(value) then
        return 0
    end
    return value
end

local function HasFutureSettingsOwner(db)
    return type(db) == "table"
        and NormalizeVersion(rawget(db, "settingsVersion")) > SETTINGS_VERSION
end

local function AccountWritesAllowed(database)
    if HasFutureSettingsOwner(database) then return false end
    local migration = Nexus and Nexus.LegacyDataMigration
    if migration and type(migration.AccountWritesAllowed) == "function" then
        local ok, allowed = pcall(migration.AccountWritesAllowed, database)
        return ok and allowed == true
    end
    return true
end

local function ReadLegacyMigrationMarker(db)
    local migrations = rawget(db, LEGACY_MIGRATION_NAMESPACE)
    if migrations == nil then return nil, nil end
    if type(migrations) ~= "table" then
        error("NexusDB legacy migration namespace is owned by an incompatible value")
    end

    local marker = rawget(migrations, LEGACY_MIGRATION_KEY)
    if marker == nil then return nil, migrations end
    local version = type(marker) == "table" and tonumber(marker.version) or nil
    if type(marker) ~= "table" or marker.completed ~= true
        or not version or version ~= version or version >= math.huge
        or version ~= math.floor(version) or version < 1 then
        error("NexusDB legacy migration marker is malformed")
    end
    return marker, migrations
end

-- Select an authority without clearing either SavedVariables name. A shared
-- table is an interrupted adoption retry: once NexusDB is rebound, the next
-- call must finish against that exact root instead of reclassifying it.
local function SelectDatabaseForLegacyMigration()
    local current = NexusDB
    local legacy = WishlistRealizerDB

    if current ~= nil and type(current) ~= "table" then
        error("NexusDB is malformed; preserving it for recovery")
    end

    if type(current) == "table" then
        local marker = ReadLegacyMigrationMarker(current)
        if marker then return current, marker.decision or "completed" end
    end

    if legacy ~= nil and type(legacy) ~= "table" then
        error("WishlistRealizerDB is malformed; preserving it for recovery")
    end

    if type(current) == "table" and current == legacy then
        return current, "adoptedLegacy"
    end

    if type(current) == "table" and next(current) ~= nil then
        return current, "keptCurrent"
    end

    if type(legacy) == "table" and next(legacy) ~= nil then
        ReadLegacyMigrationMarker(legacy)
        return legacy, "adoptedLegacy"
    end

    local db = type(current) == "table" and current or {}
    ReadLegacyMigrationMarker(db)
    return db, legacy == nil and "noLegacy" or "ignoredEmptyLegacy"
end

local function CompleteLegacyMigration(db, decision)
    -- Re-read after every ordered owner. A future owner or interrupted write
    -- that occupied this namespace must block legacy release, not be replaced.
    local marker, migrations = ReadLegacyMigrationMarker(db)
    if not marker then
        if not migrations then
            migrations = {}
            db[LEGACY_MIGRATION_NAMESPACE] = migrations
        end
        marker = {
            version=LEGACY_MIGRATION_VERSION,
            completed=true,
            decision=decision,
        }
        migrations[LEGACY_MIGRATION_KEY] = marker
    end

    -- The durable marker is visible before the old global is released. If a
    -- later load sees the marker and a reintroduced legacy value, current wins.
    WishlistRealizerDB = nil
end

local function MigratePendingToggleRecords(db, sourceVersion)
    for _, state in pairs(db.chars) do
        local pending = type(state) == "table" and state.tomeTogglePending
        if type(pending) == "table" then
            for lever, value in pairs(pending) do
                if type(value) == "number" and value == value
                    and value < math.huge and value > -math.huge then
                    pending[lever] = { t=value, want=true }
                end
            end
        end
    end

    -- v1.19.x had no qualification toggle.  Defaulting that newly introduced
    -- filter on during an upgrade can make a successfully migrated library
    -- appear empty when the legacy cache has only one DPS category per
    -- loadout.  Preserve an explicit newer preference, but let legacy users
    -- see their converted builds on first open.
    local legacyBuildFilters = type(db.buildFilters) == "table"
        and db.buildFilters or nil
    if sourceVersion == 1 and legacyBuildFilters
        and legacyBuildFilters.qualifiedOnly == nil then
        legacyBuildFilters.qualifiedOnly = false
    end
end

local MIGRATIONS = {
    [1] = function() end, -- baseline for previously unversioned saves
    [2] = MigratePendingToggleRecords,
}

local function ApplyMigrations(db)
    local version = NormalizeVersion(db.settingsVersion)
    local sourceVersion = version
    if version > SETTINGS_VERSION then return end -- future owner wins
    while version < SETTINGS_VERSION do
        local nextVersion = version + 1
        local migrate = MIGRATIONS[nextVersion]
        if migrate then migrate(db, sourceVersion) end
        version = nextVersion
        -- Stamp only after the idempotent migration completed successfully.
        db.settingsVersion = version
    end
    if db.settingsVersion ~= SETTINGS_VERSION then
        db.settingsVersion = SETTINGS_VERSION
    end
end

function Store.Init()
    -- Binding is the first half of the legacy rename migration. Completion is
    -- deliberately last so dependency failures retain the recovery reference.
    local db, legacyDecision = SelectDatabaseForLegacyMigration()
    NexusDB = db
    local futureSettingsOwner = HasFutureSettingsOwner(db)
    if not futureSettingsOwner then
        if type(db.chars) ~= "table" then db.chars = {} end
        if type(db.settings) ~= "table" then db.settings = {} end

        local profile = Nexus.DefaultProfile
        local defaults = profile and profile.defaultSettings or {}

        ApplyMigrations(db)
        FillMissing(db.settings, defaults)

        -- Per-character shape drift is filled recursively without replacing
        -- the state table, its safety latches, or newer fields.
        for name, state in pairs(db.chars) do
            state = EnsureStateShape(state)
            db.chars[name] = state
            FillMissing(state, FreshState())
        end
    end

    -- The evidence pool is bound before BuildCatalog so overlay writes can
    -- attach content-addressed references without ever touching the immutable
    -- release bundle.
    if Nexus.LoadoutEvidence and Nexus.LoadoutEvidence.Init then
        Nexus.LoadoutEvidence.Init(db)
    end

    -- BuildCatalog owns the versioned release-baseline migration. During the
    -- staged cutover, communityBuilds remains the single canonical overlay
    -- table so existing runtime consumers keep working without duplicating the
    -- same records under two SavedVariables keys.
    local catalogSummary
    if Nexus.BuildCatalog and Nexus.BuildCatalog.Init then
        catalogSummary = Nexus.BuildCatalog.Init(db, Nexus.BundledBuilds)
    end
    if AccountWritesAllowed(db)
        and not (catalogSummary and catalogSummary.readOnly) then
        db.accountCharacters = type(db.accountCharacters) == "table"
            and db.accountCharacters or {}
        Store.RegisterCurrentCharacter()
    end
    local migrationSummary
    if Nexus.LegacyDataMigration and Nexus.LegacyDataMigration.Init
        and not futureSettingsOwner
        and not (catalogSummary and catalogSummary.readOnly) then
        migrationSummary = Nexus.LegacyDataMigration.Init(db)
    end
    local dataReady = not migrationSummary
        or migrationSummary.complete == true
    -- DPS migration owns generated build references. It must finish before
    -- compaction/retention can classify an automatic page as unreferenced.
    if Nexus.DpsCapture
        and type(Nexus.DpsCapture.MigrateLegacyLeaderboard) == "function"
        and not (catalogSummary and catalogSummary.readOnly)
        and dataReady then
        Nexus.DpsCapture.MigrateLegacyLeaderboard()
    end
    if Nexus.DataCompaction and Nexus.DataCompaction.Init
        and not (catalogSummary and catalogSummary.readOnly)
        and dataReady then
        Nexus.DataCompaction.Init(db)
    end
    if Nexus.DataRetention and Nexus.DataRetention.Init
        and not (catalogSummary and catalogSummary.readOnly)
        and dataReady then
        Nexus.DataRetention.Init(db)
    end

    CompleteLegacyMigration(db, legacyDecision)
end

local function CurrentIdentity()
    local name = UnitName and UnitName("player") or nil
    if not name or name == "" or name == "Unknown" then return nil end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then realm = GetRealmName and GetRealmName() end
    realm = tostring(realm or ""):gsub("%s+", "")
    if realm == "" or realm:lower() == "unknown" then return nil end
    local ownerKey = Identity.OwnerKey(name, realm)
    if not ownerKey then return nil end
    return ownerKey, tostring(name), ownerKey:match("@(.+)$")
end

function Store.CurrentOwnerKey()
    return CurrentIdentity()
end

local function AccountRowMatchesCurrent(row, ownerKey, name)
    if row == nil then return true end
    if type(row) ~= "table" then return false end
    if row.ownerKey ~= nil
        and Identity.CanonicalOwnerKey(row.ownerKey) ~= ownerKey then return false end
    if row.name ~= nil then
        if type(row.name) ~= "string"
            or not Identity.OwnerKeyMatchesAuthor(ownerKey, row.name) then
            return false
        end
        if row.name:find("-", 1, true)
            and Identity.CanonicalOwnerFromTransport(row.name) ~= ownerKey then
            return false
        end
    end
    if row.realm ~= nil then
        if type(row.realm) ~= "string" then return false end
        local rowRealm = row.realm:lower()
        if rowRealm ~= "" and rowRealm ~= "unknown"
            and Identity.CanonicalOwnerKey(Identity.OwnerKey(name, row.realm))
                ~= ownerKey then return false end
    end
    return true
end

function Store.RegisterCurrentCharacter()
    local ownerKey, name, realm = CurrentIdentity()
    local database = NexusDB
    if not ownerKey or type(database) ~= "table"
        or not AccountWritesAllowed(database) then return nil end
    local characters = type(database.accountCharacters) == "table"
        and database.accountCharacters or {}
    database.accountCharacters = characters
    local row = characters[ownerKey]
    if not AccountRowMatchesCurrent(row, ownerKey, name) then return nil end
    row = type(row) == "table" and row or {}
    row.name, row.realm = name, realm
    local class = UnitClass and select(2, UnitClass("player")) or nil
    if class and class ~= "" then row.class = tostring(class):upper() end
    local ok, stamp = pcall(function() return time and time() or 0 end)
    if ok and tonumber(stamp) and tonumber(stamp) > 0 then
        row.lastSeen = math.floor(tonumber(stamp))
    end
    characters[ownerKey] = row
    return ownerKey, row
end

function Store.IsAccountOwnerKey(ownerKey)
    local canonical = Identity.CanonicalOwnerKey(ownerKey)
    if not canonical or canonical:match("@unknown$") then return false end
    local database = NexusDB
    local characters = type(database) == "table"
        and database.accountCharacters or nil
    return type(characters) == "table"
        and type(characters[canonical]) == "table"
end

function Store.IsAccountBuild(build)
    if type(build) ~= "table" then return false end
    if build.isMine == true or build.importedSavedBuild == true then return true end
    return Store.IsAccountOwnerKey(build.ownerKey)
end

function Store.AccountCharacters()
    local database = NexusDB
    return type(database) == "table"
        and type(database.accountCharacters) == "table"
        and database.accountCharacters or {}
end

function Store.SettingsVersion()
    return SETTINGS_VERSION
end

-- Live subtable; callers re-fetch rather than caching so rename migration and
-- invalid pre-init globals are never latched.
function Store.Settings()
    local db = NexusDB
    if db and not HasFutureSettingsOwner(db)
        and type(db.settings) == "table" then return db.settings end
    if not transientSettings then
        local profile = Nexus.DefaultProfile
        transientSettings = DeepCopy(profile and profile.defaultSettings or {})
    end
    return transientSettings
end

-- Per-character live subtable. The full local identity is re-read on every
-- call. Until both name and realm are proven, callers share only the transient
-- session table; transient or ambiguous short-key state is never promoted.
function Store.State()
    local ownerKey = CurrentIdentity()
    local db = NexusDB
    if not ownerKey or not db or HasFutureSettingsOwner(db)
        or type(db.chars) ~= "table" then
        transientState = transientState or FreshState()
        return transientState
    end
    local state = db.chars[ownerKey]
    state = EnsureStateShape(state)
    db.chars[ownerKey] = state
    Store.RegisterCurrentCharacter()
    return state
end
