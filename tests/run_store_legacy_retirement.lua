-- Store owns the Package B authority bootstrap kernel: the exhaustive ordered
-- selection table, StoreLegacyBindingTokenV1 / StoreLegacyBindingWriterV1, the
-- terminal legacy class, and AuthorityBootstrapCoordinatorV1.
--
-- Repair Wave 1, MASTER-RC-001 kernel placement. Architecture 3b5de54f,
-- docs/SYNC_TRUST_CATALOG_AUTHORITY_STATE_MACHINE.md:
--   1200-1330  AuthorityBootstrapCoordinatorV1; the fifteen-row ordered
--              decision table, exhaustive and stopping at the first matching
--              row; the fixed binding token and writer; and the terminal
--              legacy class ABSENT | SELECTED_ALIAS | DISTINCT_EMPTY_PRESERVE
--              | FOREIGN_BLOCK.
--   1206       Store.Init(coordinator) returns the explicit detached result
--              {state="pending"} until the coordinator reaches STORE_READY;
--              "a successful pcall is never interpreted as readiness".
--   1519       "Only after the disposition completes does
--              STORE_SERVING_PUBLICATION_PENDING ... Then Store enters
--              STORE_READY and releases dependents."
--   1646       The PR #68 Store.lua fall-through is removed; Store.Init itself
--              performs no dependent initialization.
--
-- ===================== INTENTIONAL COMPATIBILITY BREAKS =====================
-- Each is declared by the architecture, is fail-closed, and destroys nothing.
-- 1. Metatable-backed current/legacy database tables and coercible or
--    metatable-backed marker forms are rejected (1200-1330). PR #68 accepted
--    them. A metatable can forge presence, emptiness, or a decision.
-- 2. An occupied migration namespace or marker that is neither the exact
--    future discriminator nor the strict current V1 shape is STORE_INVALID
--    (row 5 / row 12). PR #68 preserved unknown namespace and marker fields
--    and continued; V1 cannot prove such an owner holds no migration
--    authority, so it refuses without writing.
-- 3. Only SELECTED_ALIAS performs a verified nil write. PR #68 cleared
--    WishlistRealizerDB unconditionally. A distinct empty legacy table is
--    preserved with NO write; a distinct nonempty one is FOREIGN_BLOCK and
--    requires explicit reauthorization instead of silent deletion.
-- 4. Store.Init returns an explicit result and never raises. PR #68 raised on
--    malformed input.
-- 5. The terminal legacy disposition now precedes serving publication and
--    dependent release (line 1519), where PR #68 completed it last. A
--    dependent-release fault therefore occurs after the disposition; the
--    authority owners that build the durable bundle still run before it, and
--    a fault there still retains the recovery reference (proved below).
-- ============================================================================
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

local Store = Nexus.Store

local function Marker(db)
    local migrations = type(db) == "table" and db.nexusStoreMigrations
    return type(migrations) == "table" and migrations.wishlistRealizerDB or nil
end

local activeCoordinator = nil
local ownerStates = {}

local function StubOwners(options)
    options = options or {}
    local calls = options.calls
    ownerStates = {}
    Nexus.BundledBuilds = options.bundle or {}
    local function Record(name)
        if calls then calls[#calls + 1] = name end
        ownerStates[name] = activeCoordinator and activeCoordinator:State() or nil
    end
    Nexus.LoadoutEvidence = {Init=function(db)
        Record("evidence")
        if options.fail == "evidence" then error("injected evidence failure") end
        return db
    end}
    Nexus.BuildCatalog = {Init=function(db)
        Record("catalog")
        if options.fail == "catalog" then error("injected catalog failure") end
        return {readOnly=options.readOnly == true}
    end}
    Nexus.DataCompaction = {Init=function(db)
        Record("compaction")
        if options.fail == "compaction" then error("injected compaction failure") end
        return db
    end}
end

local function BasicRoot(label, version)
    return {
        settingsVersion=version or 2,
        settings={autoPick=false,owner=label,anchorNames={}},
        chars={Hero={
            tomeTogglePending={}, flagDemotions={}, recordedPicks={},
            loadoutWishlists={}, futureSafety={owner=label},
        }},
        communityBuilds={one={author=label}},
        dpsCapture={owner=label},
        syncTombstones={one={author=label,stamp=1}},
        diagnosticLogs={owner=label},
        loadoutEvidence={owner=label},
        futureRoot={owner=label},
    }
end

local function CurrentV1Marker(decision)
    return {wishlistRealizerDB={version=1,completed=true,decision=decision}}
end

-- Drive one complete bootstrap and return its terminal result.
-- Architecture line 1715: Store.Init advances no more than one V1 slice, and
-- repeated calls with the same exact token pump the same private handle rather
-- than restarting. Lines 1203-1204 place continuation scheduling in the
-- caller's scheduler; this fixture is that scheduler. It dispatches one slice
-- per turn under a closed bound and never treats bound exhaustion as
-- readiness -- an unfinished drive returns its honest pending result.
-- Each Bootstrap models ONE process start: a fresh coordinator reclassifying
-- from the exact durable source, exactly as a reload does. That matters after
-- a terminal fault, because a terminal state never retries automatically
-- (line 1519 region) -- only a new process start may re-drive the same root.
local BOOTSTRAP_TURN_BOUND = 32
local function Bootstrap(options)
    activeCoordinator = nil
    StubOwners(options)
    local coordinator = Nexus.MainInternals.AuthorityBootstrap.New()
    local result = Store.Init(coordinator)
    local turns = 0
    while type(result) == "table" and result.state == "pending"
        and turns < BOOTSTRAP_TURN_BOUND do
        turns = turns + 1
        result = coordinator:PumpAuthorityBootstrap()
    end
    return result
end

local function Failed(result, reason, row)
    return type(result) == "table" and result.state == "failed"
        and result.reason == reason
        and (row == nil or result.row == row)
end

--===========================================================================
-- The ordered decision table, one case per row. It is exhaustive and stops at
-- the first matching row.
--===========================================================================

-- Row 1: an occupied NexusDB that is not a plain table. Legacy is never
-- inspected and neither global is written.
local preservedLegacy = BasicRoot("preserved-legacy")
NexusDB, WishlistRealizerDB = "malformed current", preservedLegacy
local row1 = Bootstrap()
assert(Failed(row1, "STORE_INVALID", 1)
    and NexusDB == "malformed current" and WishlistRealizerDB == preservedLegacy
    and Marker(preservedLegacy) == nil,
    "row 1 replaced, marked, or released a malformed current database")

NexusDB, WishlistRealizerDB = 42, nil
local row1b = Bootstrap()
assert(Failed(row1b, "STORE_INVALID", 1) and NexusDB == 42
    and WishlistRealizerDB == nil,
    "row 1 replaced malformed current-only data with a fresh database")

-- COMPATIBILITY BREAK 1: a metatable-backed current database is refused.
local metatableCurrent = setmetatable({settings={}}, {__index=function() end})
NexusDB, WishlistRealizerDB = metatableCurrent, nil
assert(Failed(Bootstrap(), "STORE_INVALID", 1) and NexusDB == metatableCurrent,
    "row 1 admitted a metatable-backed current database")

-- Row 2: a plain current with a nonnil raw authorityBundle is selected before
-- any marker or legacy location is inspected. The malformed namespace below
-- would be row 5 if it were read at all, and the nonempty legacy would be
-- row 8's FOREIGN_BLOCK; neither is consulted.
-- MASTER-W2-010: an occupied bundle carries its own complete StoreDataV1
-- wrapper, which the guarded store counters read back exactly instead of
-- rebuilding. A bundle without that wrapper is foreign and fails closed.
local function OccupiedBundle()
    return {schemaVersion=1, communityBuilds={}, storeData={
        schemaVersion=1, storeRevision=1, settingsRevision=1,
        accountRevision=1, settingsVersion=1, settings={}, chars={},
        accountCharacters={},
        migrationMarker={version=1, completed=true, decision="keptCurrent"},
    }}
end
local bundledCurrent = BasicRoot("bundle-current")
bundledCurrent.authorityBundle = OccupiedBundle()
bundledCurrent.nexusStoreMigrations = {futureOwner={keep=true}}
local bundleNamespace = bundledCurrent.nexusStoreMigrations
NexusDB, WishlistRealizerDB = bundledCurrent, nil
local row2 = Bootstrap()
assert(row2.state == "ready" and NexusDB == bundledCurrent
    and bundledCurrent.nexusStoreMigrations == bundleNamespace
    and bundleNamespace.futureOwner.keep and Marker(bundledCurrent) == nil,
    "row 2 inspected or rewrote a marker location behind an occupied bundle")

-- Row 3: the exact bounded future-marker discriminator on the current
-- database. Both globals are preserved and no current field is read.
local futureCurrent = BasicRoot("future-marker-current")
futureCurrent.nexusStoreMigrations = {wishlistRealizerDB={version=2}}
local futureNamespace = futureCurrent.nexusStoreMigrations
NexusDB, WishlistRealizerDB = futureCurrent, BasicRoot("stale")
local staleLegacy = WishlistRealizerDB
local row3 = Bootstrap()
assert(Failed(row3, "FUTURE_SCHEMA", 3) and NexusDB == futureCurrent
    and WishlistRealizerDB == staleLegacy
    and futureCurrent.nexusStoreMigrations == futureNamespace
    and futureNamespace.wishlistRealizerDB.version == 2,
    "row 3 downgraded, replaced, or released a future migration owner")

-- Row 4: an admitted exact completed V1 marker selects current and reuses its
-- decision. Legacy is never inspected.
local markedCurrent = BasicRoot("marked-current")
markedCurrent.nexusStoreMigrations = CurrentV1Marker("keptCurrent")
local markedMarker = markedCurrent.nexusStoreMigrations.wishlistRealizerDB
NexusDB, WishlistRealizerDB = markedCurrent, nil
local row4 = Bootstrap()
assert(row4.state == "ready" and row4.decision == "keptCurrent"
    and Marker(markedCurrent) == markedMarker,
    "row 4 rewrote an admitted current marker or lost its decision")

-- Row 5, COMPATIBILITY BREAK 2: an occupied namespace or marker that is
-- neither the exact future discriminator nor the strict current V1 shape.
for _, shape in ipairs({
    {label="non-table namespace", namespace="future-owner"},
    {label="unknown namespace owner", namespace={futureOwner={keep=true}}},
    {label="namespace with a second key",
        namespace={wishlistRealizerDB={version=1,completed=true},
            futureOwner={keep=true}}},
    {label="unknown marker field",
        namespace={wishlistRealizerDB={version=1,completed=true,
            futureField="keep"}}},
    {label="incomplete marker",
        namespace={wishlistRealizerDB={version=1,completed=false}}},
    {label="unknown marker decision",
        namespace={wishlistRealizerDB={version=1,completed=true,
            decision="futureDecision"}}},
    {label="metatable-backed marker",
        namespace={wishlistRealizerDB=setmetatable({version=1,completed=true},
            {})}},
}) do
    local root = BasicRoot("row5-" .. shape.label)
    root.nexusStoreMigrations = shape.namespace
    local legacy = BasicRoot("row5-legacy")
    NexusDB, WishlistRealizerDB = root, legacy
    local result = Bootstrap()
    assert(Failed(result, "STORE_INVALID", 5) and NexusDB == root
        and WishlistRealizerDB == legacy
        and root.nexusStoreMigrations == shape.namespace
        and Marker(legacy) == nil,
        "row 5 accepted or overwrote an occupied namespace: " .. shape.label)
end

-- Row 6: no current row selected and an occupied WishlistRealizerDB that is
-- not a plain table.
local emptyCurrentForRow6 = {}
NexusDB, WishlistRealizerDB = emptyCurrentForRow6, "malformed legacy"
local row6 = Bootstrap()
assert(Failed(row6, "STORE_INVALID", 6) and NexusDB == emptyCurrentForRow6
    and WishlistRealizerDB == "malformed legacy"
    and Marker(emptyCurrentForRow6) == nil,
    "row 6 cleared, marked, or accepted a malformed legacy database")

local metatableLegacy = setmetatable({owner="mt"}, {})
NexusDB, WishlistRealizerDB = nil, metatableLegacy
assert(Failed(Bootstrap(), "STORE_INVALID", 6)
    and WishlistRealizerDB == metatableLegacy,
    "row 6 admitted a metatable-backed legacy database")

-- Row 7: current and legacy are the same plain table.
local sharedRoot = BasicRoot("shared")
NexusDB, WishlistRealizerDB = sharedRoot, sharedRoot
local row7 = Bootstrap()
assert(row7.state == "ready" and row7.decision == "adoptedLegacy"
    and NexusDB == sharedRoot and WishlistRealizerDB == nil
    and Marker(sharedRoot).decision == "adoptedLegacy",
    "row 7 did not adopt the shared root and release its alias")

-- Row 8: a nonempty plain current keeps authority and no legacy location is
-- inspected. With legacy absent the run reaches STORE_READY.
local keptRoot = BasicRoot("kept")
local keptSettings, keptHero = keptRoot.settings, keptRoot.chars.Hero
local keptUnknown = keptRoot.futureRoot
NexusDB, WishlistRealizerDB = keptRoot, nil
local row8 = Bootstrap()
assert(row8.state == "ready" and row8.decision == "keptCurrent"
    and NexusDB == keptRoot and keptRoot.settings == keptSettings
    and keptRoot.chars.Hero == keptHero and keptRoot.futureRoot == keptUnknown
    and keptRoot.settings.autoPick == false
    and #keptRoot.settings.anchorNames == 0
    and Marker(keptRoot).decision == "keptCurrent",
    "row 8 replaced preferences, subsystem data, or unknown fields")

-- Row 9: current absent/empty and a nonempty plain legacy carrying a bundle.
local bundledLegacy = BasicRoot("bundle-legacy")
bundledLegacy.authorityBundle = OccupiedBundle()
NexusDB, WishlistRealizerDB = nil, bundledLegacy
local row9 = Bootstrap()
assert(row9.state == "ready" and row9.decision == "adoptedLegacy"
    and NexusDB == bundledLegacy and WishlistRealizerDB == nil,
    "row 9 did not select the bundled legacy database")

-- Row 10: the exact future discriminator on the selected legacy database.
local futureLegacy = BasicRoot("future-legacy")
futureLegacy.nexusStoreMigrations = {wishlistRealizerDB={version=7}}
NexusDB, WishlistRealizerDB = nil, futureLegacy
assert(Failed(Bootstrap(), "FUTURE_SCHEMA", 10)
    and NexusDB == nil and WishlistRealizerDB == futureLegacy,
    "row 10 adopted or released a future-owned legacy database")

-- Row 11: an admitted completed V1 marker on the legacy database.
local markedLegacy = BasicRoot("marked-legacy")
markedLegacy.nexusStoreMigrations = CurrentV1Marker("completed")
local markedLegacyMarker = markedLegacy.nexusStoreMigrations.wishlistRealizerDB
NexusDB, WishlistRealizerDB = nil, markedLegacy
local row11 = Bootstrap()
assert(row11.state == "ready" and row11.decision == "adoptedLegacy"
    and NexusDB == markedLegacy and WishlistRealizerDB == nil
    and Marker(markedLegacy) == markedLegacyMarker,
    "row 11 rewrote an admitted legacy marker")

-- Row 12: an occupied but malformed legacy namespace.
local malformedLegacyNamespace = BasicRoot("row12")
malformedLegacyNamespace.nexusStoreMigrations = {futureOwner={keep=true}}
NexusDB, WishlistRealizerDB = nil, malformedLegacyNamespace
assert(Failed(Bootstrap(), "STORE_INVALID", 12)
    and WishlistRealizerDB == malformedLegacyNamespace,
    "row 12 accepted or overwrote a malformed legacy namespace")

-- Row 13: a nonempty plain legacy with no marker is adopted by identity, its
-- subsystem data and unknown fields intact, and its alias released.
local legacyOnly = BasicRoot("legacy")
local legacySettings, legacyHero = legacyOnly.settings, legacyOnly.chars.Hero
local legacyBuilds, legacyDps = legacyOnly.communityBuilds, legacyOnly.dpsCapture
local legacyTombstones = legacyOnly.syncTombstones
local legacyDiagnostics, legacyEvidence = legacyOnly.diagnosticLogs, legacyOnly.loadoutEvidence
local legacyUnknown = legacyOnly.futureRoot
local calls = {}
NexusDB, WishlistRealizerDB = nil, legacyOnly
local row13 = Bootstrap({calls=calls})
assert(row13.state == "ready" and row13.decision == "adoptedLegacy"
    and NexusDB == legacyOnly and WishlistRealizerDB == nil,
    "row 13 did not adopt the legacy save by identity then release it")
assert(table.concat(calls, ",") == "evidence,catalog,compaction",
    "legacy completion did not follow ordered Store owners")
local adoptedMarker = Marker(NexusDB)
assert(adoptedMarker and adoptedMarker.version == 1
    and adoptedMarker.completed == true
    and adoptedMarker.decision == "adoptedLegacy",
    "legacy adoption did not publish the durable completed marker")
assert(NexusDB.settings == legacySettings and NexusDB.chars.Hero == legacyHero
    and NexusDB.communityBuilds == legacyBuilds and NexusDB.dpsCapture == legacyDps
    and NexusDB.syncTombstones == legacyTombstones
    and NexusDB.diagnosticLogs == legacyDiagnostics
    and NexusDB.loadoutEvidence == legacyEvidence
    and NexusDB.futureRoot == legacyUnknown
    and NexusDB.settings.autoPick == false and #NexusDB.settings.anchorNames == 0,
    "legacy adoption replaced preferences, subsystem data, or unknown fields")

-- Rows 14 and 15: an empty or absent current with an absent or distinct empty
-- legacy. `noLegacy` and `ignoredEmptyLegacy` are distinguished.
local emptyCurrent = {}
NexusDB, WishlistRealizerDB = emptyCurrent, nil
local row14a = Bootstrap()
assert(row14a.state == "ready" and row14a.decision == "noLegacy"
    and NexusDB == emptyCurrent
    and Marker(emptyCurrent).decision == "noLegacy",
    "row 14 did not record an absent legacy database")

local emptyCurrent2, emptyLegacy = {}, {}
NexusDB, WishlistRealizerDB = emptyCurrent2, emptyLegacy
local row14b = Bootstrap()
assert(row14b.state == "ready" and row14b.decision == "ignoredEmptyLegacy"
    and NexusDB == emptyCurrent2
    and Marker(emptyCurrent2).decision == "ignoredEmptyLegacy",
    "row 14 did not record a distinct empty legacy database")

NexusDB, WishlistRealizerDB = nil, nil
local row15a = Bootstrap()
assert(row15a.state == "ready" and row15a.decision == "noLegacy"
    and type(NexusDB) == "table",
    "row 15 did not allocate one fresh database when both names were absent")

local freshEmptyLegacy = {}
NexusDB, WishlistRealizerDB = nil, freshEmptyLegacy
local row15b = Bootstrap()
assert(row15b.state == "ready" and row15b.decision == "ignoredEmptyLegacy"
    and type(NexusDB) == "table" and NexusDB ~= freshEmptyLegacy,
    "row 15 adopted or replaced a distinct empty legacy database")

--===========================================================================
-- The terminal legacy class. Exactly one verified nil write exists, and only
-- SELECTED_ALIAS performs it.
--===========================================================================

-- ABSENT verifies absence and writes nothing (rows 8/14a/15a above).
-- SELECTED_ALIAS releases and verifies (rows 7/13 above).

-- DISTINCT_EMPTY_PRESERVE: COMPATIBILITY BREAK 3. The exact table is
-- preserved without a write and grants no migration, fallback, read, mutation
-- or deletion authority.
assert(WishlistRealizerDB == freshEmptyLegacy
    and next(freshEmptyLegacy) == nil
    and getmetatable(freshEmptyLegacy) == nil,
    "DISTINCT_EMPTY_PRESERVE deleted or mutated the preserved legacy table")
assert(emptyLegacy ~= nil and next(emptyLegacy) == nil,
    "a distinct empty legacy table was cleared by the terminal disposition")

-- FOREIGN_BLOCK: a distinct nonempty legacy value is preserved and the run
-- fails closed for explicit reauthorization. PR #68 deleted it silently.
local foreignCurrent = BasicRoot("foreign-current")
local foreignLegacy = BasicRoot("foreign-legacy")
local foreignLegacySettings = foreignLegacy.settings
local foreignCalls = {}
NexusDB, WishlistRealizerDB = foreignCurrent, foreignLegacy
local foreign = Bootstrap({calls=foreignCalls})
assert(Failed(foreign, "LEGACY_DISPOSITION_REAUTH_REQUIRED")
    and foreign.legacyClass == "FOREIGN_BLOCK"
    and NexusDB == foreignCurrent and WishlistRealizerDB == foreignLegacy
    and foreignLegacy.settings == foreignLegacySettings
    and foreignLegacy.settings.owner == "foreign-legacy",
    "a distinct nonempty legacy database was deleted or merged")
assert(table.concat(foreignCalls, ",") == "evidence,catalog",
    "a dependent was released after a blocked terminal legacy disposition: "
    .. table.concat(foreignCalls, ","))
-- Deep equality never grants merge or deletion authority either.
local identicalCurrent, identicalLegacy = BasicRoot("same"), BasicRoot("same")
NexusDB, WishlistRealizerDB = identicalCurrent, identicalLegacy
assert(Failed(Bootstrap(), "LEGACY_DISPOSITION_REAUTH_REQUIRED")
    and NexusDB == identicalCurrent and WishlistRealizerDB == identicalLegacy,
    "two deep-equal distinct roots granted deletion authority")

--===========================================================================
-- AuthorityBootstrapCoordinatorV1: bounded, resumable, and the sole readiness
-- authority. Dependents are released at STORE_READY and nowhere earlier.
--===========================================================================
local adoptRoot = BasicRoot("coordinated")
local sliceCalls = {}
NexusDB, WishlistRealizerDB = nil, adoptRoot
local coordinator = Nexus.MainInternals.AuthorityBootstrap.New()
activeCoordinator = coordinator
StubOwners({calls=sliceCalls})

assert(coordinator:State() == "STORE_UNBOUND"
    and coordinator:Result().state == "pending" and NexusDB == nil,
    "a fresh coordinator was not unbound and pending")

-- Store.Init binds the exact database and reports pending. A successful call
-- is never readiness.
local okInit, bindResult = pcall(Store.Init, coordinator)
assert(okInit and type(bindResult) == "table" and bindResult.state == "pending"
    and coordinator:IsReady() == false,
    "a successful Store.Init call reported readiness")
assert(NexusDB == adoptRoot and WishlistRealizerDB == adoptRoot
    and #sliceCalls == 0,
    "Store.Init released a dependent or dispositioned the legacy alias")

-- Repeating Store.Init with the same coordinator never restarts bootstrap.
local boundState = coordinator:State()
Store.Init(coordinator)
assert(coordinator:State() == boundState and #sliceCalls == 0,
    "a repeated Store.Init restarted authority bootstrap")

-- One slice per pump, bounded, and no dependent before STORE_READY.
local slices = 0
while coordinator:Result().state == "pending" do
    local stateBefore = coordinator:State()
    coordinator:PumpAuthorityBootstrap()
    slices = slices + 1
    assert(slices <= 32,
        "bootstrap did not converge under its closed slice bound")
    assert(coordinator:State() ~= stateBefore,
        "a pump performed no slice from " .. tostring(stateBefore))
    if coordinator:State() ~= "STORE_READY" then
        assert(sliceCalls[#sliceCalls] ~= "compaction",
            "a dependent was released before STORE_READY, at "
            .. coordinator:State())
    end
end
assert(slices >= 2, "the whole bootstrap collapsed into a single slice")
assert(coordinator:IsReady() and coordinator:Result().state == "ready"
    and coordinator:Result().result == "BOOTSTRAP_COMMITTED"
    and coordinator:Database() == adoptRoot,
    "the coordinator did not reach STORE_READY with a sealed result")
assert(table.concat(sliceCalls, ",") == "evidence,catalog,compaction",
    "coordinated bootstrap changed its ordered owner sequence: "
    .. table.concat(sliceCalls, ","))
-- The authority owners run during admission; the dependent runs at readiness.
assert(ownerStates.evidence == "STORE_AUTHORITY_PENDING"
    and ownerStates.catalog == "STORE_AUTHORITY_PENDING"
    and ownerStates.compaction == "STORE_READY",
    "an owner ran in the wrong lifecycle state: evidence="
    .. tostring(ownerStates.evidence) .. " catalog="
    .. tostring(ownerStates.catalog) .. " compaction="
    .. tostring(ownerStates.compaction))
assert(WishlistRealizerDB == nil and Marker(adoptRoot).decision == "adoptedLegacy",
    "the terminal disposition did not complete before readiness")

-- Additional pumps after readiness perform no slice and release nothing again.
for _ = 1, 5 do coordinator:PumpAuthorityBootstrap() end
assert(coordinator:State() == "STORE_READY"
    and table.concat(sliceCalls, ",") == "evidence,catalog,compaction",
    "additional pumps re-released dependents")

-- Withheld on the future-schema path, however many pumps run.
local futurePumpRoot = BasicRoot("future-pump")
futurePumpRoot.nexusStoreMigrations = {wishlistRealizerDB={version=4}}
local futureCalls = {}
NexusDB, WishlistRealizerDB = futurePumpRoot, nil
local futureCoordinator = Nexus.MainInternals.AuthorityBootstrap.New()
activeCoordinator = futureCoordinator
StubOwners({calls=futureCalls})
local futureResult = Store.Init(futureCoordinator)
for _ = 1, 12 do futureCoordinator:PumpAuthorityBootstrap() end
assert(Failed(futureResult, "FUTURE_SCHEMA", 3)
    and futureCoordinator:State() == "STORE_READ_ONLY_FUTURE_SCHEMA"
    and futureCoordinator:IsReady() == false and #futureCalls == 0,
    "a dependent initializer ran on the future-schema path")

-- Withheld on the invalid path.
local invalidCalls = {}
NexusDB, WishlistRealizerDB = "not a table", nil
local invalidCoordinator = Nexus.MainInternals.AuthorityBootstrap.New()
activeCoordinator = invalidCoordinator
StubOwners({calls=invalidCalls})
local invalidResult = Store.Init(invalidCoordinator)
for _ = 1, 12 do invalidCoordinator:PumpAuthorityBootstrap() end
assert(Failed(invalidResult, "STORE_INVALID", 1)
    and invalidCoordinator:State() == "STORE_INVALID"
    and invalidCoordinator:IsReady() == false and #invalidCalls == 0,
    "a dependent initializer ran on the invalid path")
activeCoordinator = nil

-- An authority-owner fault before the durable bundle keeps the recovery
-- reference: no marker is published and the legacy alias is not released.
local interrupted = BasicRoot("interrupted")
NexusDB, WishlistRealizerDB = nil, interrupted
local interruptedResult = Bootstrap({fail="catalog"})
assert(Failed(interruptedResult, "STORE_INVALID")
    and interruptedResult.owner == "BuildCatalog.Init"
    and tostring(interruptedResult.error):find("injected catalog failure", 1, true)
    and NexusDB == interrupted and WishlistRealizerDB == interrupted
    and Marker(interrupted) == nil,
    "a failed authority owner published completion or lost the recovery reference")
-- Retry recognizes the shared adopted root and finishes against the same table.
local resumeCalls = {}
local resumed = Bootstrap({calls=resumeCalls})
assert(resumed.state == "ready" and NexusDB == interrupted
    and WishlistRealizerDB == nil
    and Marker(interrupted).decision == "adoptedLegacy"
    and table.concat(resumeCalls, ",") == "evidence,catalog,compaction",
    "interrupted same-root adoption did not resume idempotently")

-- A read-only catalog verdict withholds the account and dependent owners
-- without failing the run.
local readOnlyRoot = BasicRoot("read-only")
local readOnlyCalls = {}
NexusDB, WishlistRealizerDB = readOnlyRoot, nil
local readOnly = Bootstrap({calls=readOnlyCalls, readOnly=true})
assert(readOnly.state == "ready"
    and table.concat(readOnlyCalls, ",") == "evidence,catalog"
    and readOnlyRoot.accountCharacters == nil,
    "a read-only catalog verdict still released account or dependent owners")

--===========================================================================
-- Sole-writer inventory. Store remains the only legacy/marker/bind owner
-- across every TOC-loaded runtime file.
--===========================================================================
local tocFile = assert(io.open("Nexus.toc", "r"))
local toc = tocFile:read("*a")
tocFile:close()
assert(toc:find("## SavedVariables: NexusDB WishlistRealizerDB", 1, true),
    "Nexus.toc no longer declares both SavedVariables names")

local storeFile = assert(io.open("core/Store.lua", "r"))
local source = storeFile:read("*a")
storeFile:close()
local runtimeSource = ""
local runtimeFiles = {}
for line in toc:gmatch("[^\r\n]+") do
    local path = line:match("^%s*(.-%.lua)%s*$")
    if path then
        path = path:gsub("\\", "/")
        local runtimeFile = assert(io.open(path, "r"))
        local runtimeText = runtimeFile:read("*a")
        runtimeFiles[path] = runtimeText
        runtimeSource = runtimeSource .. "\n" .. runtimeText
        runtimeFile:close()
    end
end
local _, legacyClearWrites = runtimeSource:gsub(
    "WishlistRealizerDB%s*=%s*[^=]", "")
-- The bind writer's target is the selected database chosen by the ordered
-- table, not an implicit `db` upvalue. The count is unchanged at one.
local _, storeCurrentBindWrites = source:gsub("NexusDB%s*=%s*selected", "")
local _, markerNamespaceWrites = runtimeSource:gsub(
    "db%[LEGACY_MIGRATION_NAMESPACE%]%s*=%s*[^=]", "")
local _, markerKeyWrites = runtimeSource:gsub(
    "migrations%[LEGACY_MIGRATION_KEY%]%s*=%s*[^=]", "")
assert(legacyClearWrites == 1 and storeCurrentBindWrites == 1
    and markerNamespaceWrites == 1 and markerKeyWrites == 1,
    "runtime acquired another bind, marker, or legacy-clear owner")
-- Per-file direct NexusDB write counts are unchanged by the kernel: Store
-- still owns exactly one, and no other file gained or lost any.
local expectedCurrentWrites = {
    ["core/DiagnosticLogs.lua"]=1, ["core/DpsCapture.lua"]=2,
    ["core/Errors.lua"]=3, ["core/LoadoutEvidence.lua"]=1,
    ["core/Main.lua"]=1, ["core/Store.lua"]=1, ["core/Sync.lua"]=1,
    ["core/Updates.lua"]=2, ["ui/Panel.lua"]=4, ["ui/QuickStart.lua"]=2,
    ["ui/ServerStatus.lua"]=3,
}
for path, runtimeText in pairs(runtimeFiles) do
    local _, writes = runtimeText:gsub("NexusDB%s*=%s*[^=]", "")
    assert(writes == (expectedCurrentWrites[path] or 0),
        "unexpected direct NexusDB write count in " .. path)
end
-- COMPATIBILITY BREAK 5, line 1519: the terminal disposition now sits between
-- authority admission and dependent release, where PR #68 completed it last.
local catalogAt = assert(source:find("Nexus.BuildCatalog.Init,", 1, true),
    "the coordinator no longer admits the catalog authority owner")
local dispositionAt = assert(source:find("DisposeLegacyBinding(C.token)", 1, true),
    "the coordinator no longer performs one terminal legacy disposition")
local readyAt = assert(source:find('C.state = SS.READY', 1, true),
    "the coordinator no longer reaches STORE_READY")
local compactionAt = assert(source:find("Nexus.DataCompaction.Init,", 1, true),
    "the coordinator no longer releases the compaction dependent")
assert(catalogAt < dispositionAt and dispositionAt < readyAt
    and readyAt < compactionAt,
    "authority admission, terminal disposition, readiness and dependent "
    .. "release are no longer in the accepted order")
-- Line 1646: Store.Init itself performs no dependent initialization.
local initAt = assert(source:find("function Store.Init(coordinator)", 1, true))
local initBody = source:sub(initAt)
for _, owner in ipairs({"Nexus.LoadoutEvidence", "Nexus.BuildCatalog",
    "Nexus.DataCompaction", "Nexus.DataRetention"}) do
    assert(not initBody:find(owner, 1, true),
        "the PR #68 Store.Init fall-through returned: " .. owner)
end

--===========================================================================
-- Real bootstrap honours the failure boundary. These overwrite-capable stubs
-- prove neither persistent error nor diagnostic ownership runs after the
-- malformed-current decision fails during either lifecycle event.
--===========================================================================
local errorWrites, diagnosticWrites = 0, 0
Nexus.Errors = {
    SafeText=function(value) return tostring(value) end,
    Record=function()
        errorWrites = errorWrites + 1
        NexusDB = {}
        return true
    end,
}
Nexus.DiagnosticLogs = {Init=function()
    diagnosticWrites = diagnosticWrites + 1
    NexusDB = {}
    return true
end}
Nexus.Model, Nexus.Policy, Nexus.Ratchet, Nexus.Strategy = {}, {}, {}, {}
Nexus.GameAdapter, Nexus.Readout, Nexus.Panel, Nexus.JournalTab = {}, {}, {}, {}
dofile("ui/Changelog.lua")
local changelogEvent = H.eventHandlers[#H.eventHandlers]
local changelogUpdate = H.updateHandlers[#H.updateHandlers]
dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")
local mainEvent = H.eventHandlers[#H.eventHandlers]
assert(type(changelogEvent) == "function" and type(changelogUpdate) == "function"
    and type(mainEvent) == "function", "bootstrap handlers were not registered")
local bootstrapCurrent = false
local bootstrapLegacy = BasicRoot("bootstrap-legacy")
NexusDB = bootstrapCurrent
WishlistRealizerDB = bootstrapLegacy
mainEvent(nil, "ADDON_LOADED", "Nexus")
changelogEvent(nil, "PLAYER_ENTERING_WORLD")
mainEvent(nil, "PLAYER_ENTERING_WORLD")
changelogUpdate(nil, 2.1)
assert(NexusDB == bootstrapCurrent and WishlistRealizerDB == bootstrapLegacy
    and Marker(bootstrapLegacy) == nil
    and errorWrites == 0 and diagnosticWrites == 0
    and tostring(Nexus.lastError):find("STORE_INVALID", 1, true),
    "bootstrap diagnostics or delayed Changelog bypassed Store failure preservation")

print("Store authority bootstrap kernel: ordered selection, terminal legacy disposition, bounded coordinator, and sole-writer inventory -- OK")
