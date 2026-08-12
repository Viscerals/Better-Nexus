-- Nexus: core/Store.lua
-- SavedVariables ownership ONLY (global: NexusDB): settings
-- plus per-character safety state. core/ may touch SavedVariables and
-- UnitName; nothing else. Main calls Store.Init() at ADDON_LOADED --
-- never earlier (the client replaces the global when the file loads).

Nexus = Nexus or {}
local Store = {}
Nexus.Store = Store

-- Versioned shape changes are additive and ordered. User preferences,
-- per-character safety state, and unknown/future fields are never rebuilt
-- merely because the shipped defaults or schema version changed.
local SETTINGS_VERSION = 2

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

local function MigratePendingToggleRecords(db)
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
end

local MIGRATIONS = {
    [1] = function() end, -- baseline for previously unversioned saves
    [2] = MigratePendingToggleRecords,
}

local function ApplyMigrations(db)
    local version = NormalizeVersion(db.settingsVersion)
    if version > SETTINGS_VERSION then return end -- future owner wins
    while version < SETTINGS_VERSION do
        local nextVersion = version + 1
        local migrate = MIGRATIONS[nextVersion]
        if migrate then migrate(db) end
        version = nextVersion
        -- Stamp only after the idempotent migration completed successfully.
        db.settingsVersion = version
    end
    if db.settingsVersion ~= SETTINGS_VERSION then
        db.settingsVersion = SETTINGS_VERSION
    end
end

function Store.Init()
    -- ── One-time rename migration ─────────────────────────────────────
    -- The addon was renamed from WishlistRealizer to Nexus in 2.0.
    -- WoW tracks SavedVariables by the name declared in the .toc, so
    -- WishlistRealizerDB (the old name) still exists on disk after the
    -- update while NexusDB is brand-new and empty.  Copy everything
    -- across exactly once, then clear the old variable so it doesn't
    -- accumulate stale duplicates across future logins.
    if type(WishlistRealizerDB) == "table"
        and (type(NexusDB) ~= "table" or next(NexusDB) == nil) then
        NexusDB = WishlistRealizerDB
        WishlistRealizerDB = nil   -- release; WoW won't persist nil vars
    end
    -- ── End rename migration ──────────────────────────────────────────

    NexusDB = type(NexusDB) == "table" and NexusDB or {}
    local db = NexusDB
    if type(db.chars) ~= "table" then db.chars = {} end
    if type(db.settings) ~= "table" then db.settings = {} end

    local profile = Nexus.DefaultProfile
    local defaults = profile and profile.defaultSettings or {}

    ApplyMigrations(db)
    FillMissing(db.settings, defaults)

    -- Per-character shape drift is filled recursively without replacing the
    -- state table, its safety latches, or fields owned by newer builds.
    for name, state in pairs(db.chars) do
        state = EnsureStateShape(state)
        db.chars[name] = state
        FillMissing(state, FreshState())
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
    if Nexus.DataCompaction and Nexus.DataCompaction.Init
        and not (catalogSummary and catalogSummary.readOnly) then
        Nexus.DataCompaction.Init(db)
    end
    if Nexus.DataRetention and Nexus.DataRetention.Init
        and not (catalogSummary and catalogSummary.readOnly) then
        Nexus.DataRetention.Init(db)
    end
end

function Store.SettingsVersion()
    return SETTINGS_VERSION
end

-- Live subtable; callers re-fetch rather than caching so rename migration and
-- invalid pre-init globals are never latched.
function Store.Settings()
    local db = NexusDB
    if db and type(db.settings) == "table" then return db.settings end
    if not transientSettings then
        local profile = Nexus.DefaultProfile
        transientSettings = DeepCopy(profile and profile.defaultSettings or {})
    end
    return transientSettings
end

-- Per-char live subtable. The key is re-read from UnitName on EVERY
-- call: while it reads nil/"Unknown" (login order) a transient table is
-- returned instead, and the first call with a real name switches to the
-- persisted one -- a bad key is never latched (addendum B5).
function Store.State()
    local name = UnitName and UnitName("player") or nil
    local db = NexusDB
    if not name or name == "" or name == "Unknown"
        or not db or type(db.chars) ~= "table" then
        transientState = transientState or FreshState()
        return transientState
    end
    local state = db.chars[name]
    state = EnsureStateShape(state)
    db.chars[name] = state
    return state
end
