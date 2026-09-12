-- Package B / issue #22 Repair Wave 1: the durable authority kernel.
--
-- Covers MASTER-RC-001 (the accepted complete durable-bundle, sole serving-root
-- authority kernel is absent) and the row-identity element of MASTER-RC-002 that
-- depends on it.
--
-- Architecture at 3b5de54f, docs/SYNC_TRUST_CATALOG_AUTHORITY_STATE_MACHINE.md:
--   "The only durable authority payload slot is `authorityDatabase.authorityBundle`."
--   "`AuthorityCommitCoordinatorV1` is the sole durable writer and accepts only a
--    complete detached bundle."
--   "Replace the complete bundle pointer once. Never mutate a live nested bundle
--    field."
--   "`currentServingRoot` is the sole public authority pointer."
--   "The first bundle produced from legacy input has `transactionGeneration=1`.
--    Every later complete durable-bundle replacement increments that field exactly
--    once. Candidate construction, failure, cancellation, descriptor-only serving
--    rebase, and notification retry do not allocate or change it."
--   "A serving root binds the exact selected bundle generation in
--    `durableBundleGeneration`."
--   "Durable counters never reset."
--
-- Expected-red measurement on the rejected candidate e69497d, before any product
-- edit in this wave (`node tools/run-lua.js tests/run_catalog_authority_bootstrap.lua`):
--   KRN-01 RED  no authorityBundle slot is ever created.
--   KRN-02 RED  no bundle pointer, so no bundle replacement and no
--               transactionGeneration.
--   KRN-03 RED  a refused transaction cannot be compared against a bundle that
--               does not exist.
--   KRN-04 RED  RootState() exposes no durableBundleGeneration/servingGeneration,
--               so the sole-serving-pointer swap is unobservable and unproven.
--   KRN-05 RED  a published bundle is not carried across a reload, because none is
--               written.
--   KRN-06 RED  the live nested payload map is the same table the catalog rawsets
--               into, so a retained bundle cannot stay byte-exact.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Codec.lua")
local S = dofile("tests/catalog_authority_support.lua")
-- MASTER-RC-001 character-migration cases need the Store coordinator.
dofile("core/Store.lua")
-- MASTER-RC-001 DpsAuthorityOwnerV1 cases need the DPS owner.
dofile("core/Revisions.lua")
dofile("core/DpsCapture.lua")
local Case, Check = S.Case, S.Check

local now = 2000000000
time = function() return now end
UnitClass = function() return "Mage", "MAGE" end

local function Catalog() return Nexus.BuildCatalog end

local BUNDLE_FIELDS = {
    "communityBuilds", "syncTombstones", "buildCatalog",
    "communityRetentionEvictions", "loadoutEvidence", "dpsCapture",
    "dpsAuthority", "storeData", "dataRetention", "dataCompaction",
}

local function Bundle(db)
    return rawget(db, "authorityBundle")
end

Case("KRN-01",
    "root admission publishes one complete AuthorityDurableBundleV1 payload slot",
function()
    local db = S.Database({krnA=S.LocalBuild("krnA", 2)})
    S.Bind(db)
    local bundle = Bundle(db)
    Check(type(bundle) == "table",
        "no durable authority payload slot: db.authorityBundle is "
            .. type(bundle))
    Check(getmetatable(bundle) == nil, "the durable bundle is metatable-backed")
    Check(rawget(bundle, "schemaVersion") == 1,
        "the durable bundle carries no schemaVersion=1 discriminator")
    Check(rawget(bundle, "transactionGeneration") == 1,
        "the first bundle built from legacy input must have transactionGeneration=1, got "
            .. tostring(rawget(bundle, "transactionGeneration")))
    -- The bundle is complete: every accepted field name is present as a key, so
    -- no domain can be published through a separate slot.
    for _, field in ipairs(BUNDLE_FIELDS) do
        Check(rawget(bundle, field) ~= nil,
            "the durable bundle omits the accepted field " .. field)
    end
    -- No unknown top-level field: an unknown field is AUTHORITY_BUNDLE_INVALID.
    local known = {schemaVersion=true, transactionGeneration=true}
    for _, field in ipairs(BUNDLE_FIELDS) do known[field] = true end
    for key in pairs(bundle) do
        Check(known[key], "the durable bundle carries the unknown field "
            .. tostring(key))
    end
    Check(rawget(bundle, "communityBuilds").krnA ~= nil,
        "the durable bundle does not carry the admitted overlay row")
end)

Case("KRN-02",
    "one commit replaces the complete bundle pointer exactly once",
function()
    local db = S.Database({krnA=S.LocalBuild("krnA", 2)})
    S.Bind(db)
    local catalog = Catalog()
    local before = Bundle(db)
    Check(type(before) == "table", "no durable bundle to replace")
    local generationBefore = rawget(before, "transactionGeneration")
    local beforeBytes = S.Encode(before)

    Check(catalog.Put(S.LocalBuild("krnB", 3)), "commit fixture refused")

    local after = Bundle(db)
    Check(after ~= before,
        "a successful commit did not replace the complete bundle pointer")
    Check(rawget(after, "transactionGeneration") == generationBefore + 1,
        "a complete durable-bundle replacement did not increment transactionGeneration "
            .. "exactly once (" .. tostring(generationBefore) .. " -> "
            .. tostring(rawget(after, "transactionGeneration")) .. ")")
    -- Never mutate a live nested bundle field: the superseded bundle graph is
    -- byte-exact after the replacement.
    Check(S.Encode(before) == beforeBytes,
        "the superseded bundle was mutated in place by the replacement")
    Check(rawget(before, "communityBuilds").krnB == nil,
        "the superseded bundle's nested payload map received the new row")
    Check(rawget(after, "communityBuilds").krnB ~= nil,
        "the replacement bundle does not carry the committed row")
end)

Case("KRN-03",
    "a refused transaction replaces no bundle pointer and allocates no generation",
function()
    local db = S.Database({krnA=S.LocalBuild("krnA", 2)})
    S.Bind(db)
    local catalog = Catalog()
    local before = Bundle(db)
    Check(type(before) == "table", "no durable bundle to compare")
    local generationBefore = rawget(before, "transactionGeneration")
    local beforeBytes = S.Encode(before)

    -- A candidate refused before protected commit: an invalid typed ID never
    -- reaches raw preparation.
    Check(catalog.Put({id=false, title="refused"}) == false,
        "an invalid typed id was admitted")

    Check(Bundle(db) == before,
        "a refused candidate replaced the durable bundle pointer")
    Check(rawget(Bundle(db), "transactionGeneration") == generationBefore,
        "a refused candidate advanced transactionGeneration")
    Check(S.Encode(Bundle(db)) == beforeBytes,
        "a refused candidate changed durable bundle bytes")
end)

Case("KRN-04",
    "currentServingRoot is the sole public pointer and swaps once per publication",
function()
    local db = S.Database({krnA=S.LocalBuild("krnA", 2)})
    S.Bind(db)
    local catalog = Catalog()
    local root = S.Root()
    Check(type(root.servingGeneration) == "number",
        "RootState() exposes no servingGeneration: the serving pointer is unobservable")
    Check(type(root.durableBundleGeneration) == "number",
        "RootState() exposes no durableBundleGeneration: the serving root does not "
            .. "bind the selected bundle generation")
    Check(root.durableBundleGeneration
        == rawget(Bundle(db), "transactionGeneration"),
        "the serving root does not bind the exact selected bundle generation")
    local servingBefore = root.servingGeneration

    Check(catalog.Put(S.LocalBuild("krnB", 3)), "commit fixture refused")

    local after = S.Root()
    Check(after.servingGeneration == servingBefore + 1,
        "a successful publication did not perform exactly one serving swap ("
            .. tostring(servingBefore) .. " -> "
            .. tostring(after.servingGeneration) .. ")")
    Check(after.durableBundleGeneration
        == rawget(Bundle(db), "transactionGeneration"),
        "the replacement serving root does not bind the new bundle generation")

    -- A refused candidate performs no swap.
    Check(catalog.Put({id=false}) == false, "an invalid typed id was admitted")
    Check(S.Root().servingGeneration == after.servingGeneration,
        "a refused candidate swapped the serving root")
end)

Case("KRN-05",
    "durable counters never reset: a reload continues the selected bundle generation",
function()
    local db = S.Database({krnA=S.LocalBuild("krnA", 2)})
    S.Bind(db)
    local catalog = Catalog()
    Check(catalog.Put(S.LocalBuild("krnB", 3)), "commit fixture refused")
    local generationBefore = rawget(Bundle(db), "transactionGeneration")
    Check(generationBefore >= 2,
        "fixture did not produce a replaced bundle before the reload")

    S.Reload()
    S.Bind(db)

    local reloaded = Bundle(db)
    Check(type(reloaded) == "table", "the durable bundle did not survive a reload")
    Check(rawget(reloaded, "transactionGeneration") >= generationBefore,
        "a reload reset the durable transaction generation ("
            .. tostring(generationBefore) .. " -> "
            .. tostring(rawget(reloaded, "transactionGeneration")) .. ")")
    Check(Catalog().Get("krnB") ~= nil,
        "the reloaded bundle did not serve the committed row")
end)

Case("KRN-06",
    "a retained bundle stays byte-exact across a whole maintenance transaction",
function()
    local db = S.Database({
        krnA=S.LocalBuild("krnA", 2),
        krnB=S.LocalBuild("krnB", 3),
    })
    S.Bind(db)
    local catalog = Catalog()
    local retained = Bundle(db)
    Check(type(retained) == "table", "no durable bundle to retain")
    local retainedBytes = S.Encode(retained)

    local handle = catalog.BeginCatalogMaintenance({database=db,
        operation="retention"})
    Check(handle, "maintenance handle unavailable")
    Check(catalog.MaintenanceEvictOverlay(handle, "krnA"),
        "overlay would not stage for eviction")
    local ok = catalog.CommitMaintenance(handle)
    Check(ok, "maintenance commit refused")

    Check(S.Encode(retained) == retainedBytes,
        "the retained bundle graph was mutated by a later transaction")
    Check(Bundle(db) ~= retained,
        "the maintenance transaction did not replace the bundle pointer")
    Check(rawget(Bundle(db), "communityBuilds").krnA == nil,
        "the replacement bundle still carries the evicted overlay row")
    Check(rawget(retained, "communityBuilds").krnA ~= nil,
        "the superseded bundle lost the row it was published with")
end)

-- ---------------------------------------------------------------------------
-- MASTER-RC-001, incremental character migration.
--
-- Architecture line 1349: "Numeric tomeTogglePending migration is incremental.
-- No synchronous PR #68 pairs(db.chars) path remains."
-- Architecture line 1364: "One pump admits at most 8 rows, 64 edges, 64 nodes,
-- 2,048 graph bytes, 64 cursor entries, 64 comparisons, or 2,048 compared
-- bytes."
--
-- The defect: core/Store.lua walks the whole chars map synchronously in two
-- places -- MigratePendingToggleRecords and the STORE_CHAR_MIGRATION_PENDING
-- slice -- so one coordinator slice does unbounded work proportional to the
-- number of characters.
--
-- STO-03 and STO-04 are guards: they pass before the repair and after it, so
-- the fix cannot change what the migration produces.
local function CharState(picks)
    local state = {tomeTogglePending={}, flagDemotions={}, recordedPicks={},
        loadoutWishlists={}}
    for i = 1, picks do state.recordedPicks[200000 + i] = i end
    -- A PR #68 numeric pending toggle that must migrate to {t=,want=}.
    state.tomeTogglePending[300001] = 1700000000
    return state
end

local function DatabaseWithChars(count, picks)
    -- settingsVersion 1 so the numeric tomeTogglePending migration (MIGRATIONS[2])
    -- actually runs; at the current SETTINGS_VERSION of 2 a stored 2 migrates
    -- nothing and the guard would assert behaviour that never happens.
    local db = {settingsVersion=1, settings={autoPick=false, anchorNames={}},
        chars={}, communityBuilds={}, syncTombstones={}}
    for i = 1, count do db.chars["Char" .. i] = CharState(picks or 2) end
    return db
end

-- Drive one coordinator and report how many slices it spent in each state.
local function SliceProfile(db)
    NexusDB, WishlistRealizerDB = db, nil
    local coordinator = Nexus.MainInternals.AuthorityBootstrap.New()
    local counts, order = {}, {}
    Nexus.Store.Init(coordinator)
    for _ = 1, 4096 do
        local state = coordinator:State()
        counts[state] = (counts[state] or 0) + 1
        if #order == 0 or order[#order] ~= state then order[#order+1] = state end
        if coordinator:IsReady() or coordinator:Result().state == "failed" then
            break
        end
        coordinator:PumpAuthorityBootstrap()
    end
    return counts, order, coordinator
end

Case("STO-01",
    "no synchronous whole-map pairs(db.chars) path remains",
function()
    local handle = assert(io.open("core/Store.lua", "rb"))
    local source = handle:read("*a")
    handle:close()
    -- Count CODE sites only. The clause itself is quoted in a comment in
    -- core/Store.lua, and a scan that counted comment text would report a
    -- permanent false positive and could never go green honestly.
    local sites = 0
    for line in source:gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if not trimmed:find("^%-%-") and trimmed:find("pairs%(db%.chars%)") then
            sites = sites + 1
        end
    end
    Check(sites == 0,
        "core/Store.lua still walks the whole chars map synchronously at "
            .. sites .. " site(s); line 1349 forbids it")
end)

Case("STO-02",
    "character migration is resumable across coordinator slices",
function()
    local counts = SliceProfile(DatabaseWithChars(40, 2))
    local slices = counts["STORE_CHAR_MIGRATION_PENDING"] or 0
    -- 40 chars is 40 rows; at most 8 rows per pump requires at least 5 slices.
    Check(slices >= 5,
        "STORE_CHAR_MIGRATION_PENDING occupied " .. slices
            .. " slice(s) for 40 character rows; at most 8 rows per pump "
            .. "requires at least 5")
end)

Case("STO-03",
    "GUARD: migration still fills shape and converts numeric pending toggles",
function()
    local db = DatabaseWithChars(3, 2)
    local _, _, coordinator = SliceProfile(db)
    Check(coordinator:IsReady(),
        "the migration fixture did not reach STORE_READY")
    for name, state in pairs(db.chars) do
        Check(type(state.tomeTogglePending) == "table",
            name .. " lost its tomeTogglePending table")
        local migrated = state.tomeTogglePending[300001]
        Check(type(migrated) == "table" and migrated.want == true
                and migrated.t == 1700000000,
            name .. " did not migrate its numeric pending toggle: "
                .. tostring(migrated))
        Check(type(state.flagDemotions) == "table"
                and type(state.recordedPicks) == "table"
                and type(state.loadoutWishlists) == "table",
            name .. " lost a required state field")
    end
end)

Case("STO-04",
    "GUARD: a single-character database still converges to STORE_READY",
function()
    local _, _, coordinator = SliceProfile(DatabaseWithChars(1, 1))
    Check(coordinator:IsReady(),
        "a one-character database did not reach STORE_READY")
end)

-- ---------------------------------------------------------------------------
-- MASTER-RC-001, the detached StoreDataV1 wrapper.
--
-- Architecture line 289 gives the bundle payload field `storeData`, and the
-- StoreDataV1 shape: schemaVersion, storeRevision, settingsRevision,
-- accountRevision, settingsVersion, settings, chars, accountCharacters,
-- migrationMarker.
-- Line 1346: "STORE_CHAR_MIGRATION_PENDING builds one detached StoreDataV1."
-- Line 1379-1383: "The detached StoreDataV1 wrapper is separately metered.
--   SOE=9, SON=6, SOK=117, SOB=18*9+8*5=202, and SOP=18 charge its nine fields,
--   table plus five numeric scalar nodes, exact field-name bytes, edge storage,
--   and construction/verification. Its settings, chars, and account-character
--   child graphs are the already charged admitted candidates and are
--   referenced, not rebuilt."
-- RAW-01 (line 4849) is RED if "authorityDatabase.storeData survives".
--
-- STO-08 is a guard: it passes before the repair and after it.
local STORE_DATA_FIELDS = {
    "schemaVersion", "storeRevision", "settingsRevision", "accountRevision",
    "settingsVersion", "settings", "chars", "accountCharacters",
    "migrationMarker",
}

local function BundleOf(db)
    return rawget(db, "authorityBundle")
end

local function BuiltDatabase()
    local db = {settingsVersion=2, settings={autoPick=false, anchorNames={}},
        chars={Hero={tomeTogglePending={}, flagDemotions={}, recordedPicks={},
            loadoutWishlists={}}},
        accountCharacters={{name="Hero", realm="ebonhold"}},
        communityBuilds={}, syncTombstones={}}
    NexusDB, WishlistRealizerDB = db, nil
    H.BootstrapStore()
    return db
end

Case("STO-05",
    "the durable bundle carries a detached StoreDataV1 of exactly nine fields",
function()
    local db = BuiltDatabase()
    local bundle = BundleOf(db)
    Check(type(bundle) == "table", "no durable bundle was committed")
    local wrapper = bundle and bundle.storeData
    Check(type(wrapper) == "table", "the bundle carries no storeData payload")
    if type(wrapper) ~= "table" then return end
    Check(wrapper.schemaVersion == 1,
        "StoreDataV1 schemaVersion is " .. tostring(wrapper.schemaVersion))
    local present, extra = {}, {}
    for key in pairs(wrapper) do present[key] = true end
    for _, field in ipairs(STORE_DATA_FIELDS) do
        Check(wrapper[field] ~= nil, "StoreDataV1 is missing " .. field)
        present[field] = nil
    end
    for key in pairs(present) do extra[#extra + 1] = tostring(key) end
    Check(#extra == 0,
        "StoreDataV1 carries unlisted fields: " .. table.concat(extra, ","))
end)

Case("STO-06",
    "the StoreDataV1 wrapper meters exactly SOE=9 SON=6 SOK=117 SOB=202",
function()
    local db = BuiltDatabase()
    local wrapper = BundleOf(db) and BundleOf(db).storeData
    Check(type(wrapper) == "table", "no StoreDataV1 wrapper to meter")
    if type(wrapper) ~= "table" then return end
    local edges, keyBytes, numericNodes = 0, 0, 0
    for key, value in pairs(wrapper) do
        edges = edges + 1
        keyBytes = keyBytes + #tostring(key)
        if type(value) == "number" then numericNodes = numericNodes + 1 end
    end
    local nodes = 1 + numericNodes
    Check(edges == 9, "SOE is " .. edges .. ", required 9")
    Check(nodes == 6, "SON is " .. nodes .. ", required 6 (table + 5 scalars)")
    Check(keyBytes == 117, "SOK is " .. keyBytes .. ", required 117")
    Check(18 * edges + 8 * numericNodes == 202,
        "SOB is " .. (18 * edges + 8 * numericNodes) .. ", required 202")
end)

Case("STO-07",
    "child graphs are referenced, not rebuilt, and the marker meters SMOK=24",
function()
    local db = BuiltDatabase()
    local wrapper = BundleOf(db) and BundleOf(db).storeData
    Check(type(wrapper) == "table", "no StoreDataV1 wrapper")
    if type(wrapper) ~= "table" then return end
    Check(rawequal(wrapper.settings, db.settings),
        "StoreDataV1 rebuilt the settings graph instead of referencing it")
    Check(rawequal(wrapper.chars, db.chars),
        "StoreDataV1 rebuilt the chars graph instead of referencing it")
    Check(rawequal(wrapper.accountCharacters, db.accountCharacters),
        "StoreDataV1 rebuilt the account-character graph instead of "
            .. "referencing it")
    local marker = wrapper.migrationMarker
    Check(type(marker) == "table", "StoreDataV1 carries no migration marker")
    if type(marker) ~= "table" then return end
    local edges, keyBytes = 0, 0
    for key in pairs(marker) do
        edges = edges + 1
        keyBytes = keyBytes + #tostring(key)
    end
    Check(edges == 3, "SMOE is " .. edges .. ", required 3")
    Check(keyBytes == 24, "SMOK is " .. keyBytes .. ", required 24")
end)

Case("STO-08",
    "GUARD: authorityDatabase.storeData never survives (RAW-01)",
function()
    local db = BuiltDatabase()
    Check(rawget(db, "storeData") == nil,
        "authorityDatabase.storeData survived as a top-level field")
end)

-- ---------------------------------------------------------------------------
-- MASTER-RC-001, DpsAuthorityOwnerV1.
--
-- Architecture line 2839: "All DPS candidate construction moves behind one
-- DpsAuthorityOwnerV1 ... The module-private dpsPreparationEpoch advances once
-- before a protected replacement of the complete detached DPS field set or
-- durable sidecar ... The implementation test names every former direct write
-- site and proves the inventory is exclusive."
-- Line 2835: durable `dpsAuthority.migrationCompletionVersion` is a bounded
-- recovery gate.
--
-- The three DPS owner roots are personalBest, buildBest and characterBest.
-- Before the repair they were created lazily by three separate accessors and
-- replaced directly by the locked-migration restore, with no owner, no epoch
-- and no durable sidecar; the bundle's dpsAuthority payload field existed but
-- was filled with an empty snapshot.
--
-- DPA-04 is a guard: it passes before the repair and after it.
local DPS_WRITE_FIELDS = {"personalBest", "buildBest", "characterBest"}

local function DpsSource()
    local handle = assert(io.open("core/DpsCapture.lua", "rb"))
    local text = handle:read("*a")
    handle:close()
    return text
end

local function DpsDatabase()
    local db = {settingsVersion=2, settings={autoPick=false, anchorNames={}},
        chars={}, communityBuilds={}, syncTombstones={},
        dpsCapture={characterBest={dummy={}, lk={}}, personalBest={},
            buildBest={}}}
    NexusDB, WishlistRealizerDB = db, nil
    H.BootstrapStore()
    return db
end

Case("DPA-01",
    "the durable bundle carries a DpsAuthorityOwnerV1 sidecar",
function()
    local db = DpsDatabase()
    local bundle = rawget(db, "authorityBundle")
    Check(type(bundle) == "table", "no durable bundle was committed")
    local sidecar = bundle and bundle.dpsAuthority
    Check(type(sidecar) == "table", "the bundle carries no dpsAuthority payload")
    if type(sidecar) ~= "table" then return end
    Check(sidecar.schemaVersion == 1,
        "DPS sidecar schemaVersion is " .. tostring(sidecar.schemaVersion))
    Check(type(sidecar.preparationEpoch) == "number",
        "DPS sidecar carries no preparation epoch")
    Check(sidecar.migrationCompletionVersion ~= nil,
        "DPS sidecar carries no migrationCompletionVersion recovery gate")
end)

Case("DPA-02",
    "the DPS root writer inventory is exclusive",
function()
    local source = DpsSource()
    local beginAt = source:find("DPS%-AUTHORITY%-WRITER%-INVENTORY BEGIN")
    local endAt = source:find("DPS%-AUTHORITY%-WRITER%-INVENTORY END")
    Check(beginAt ~= nil and endAt ~= nil and endAt > beginAt,
        "core/DpsCapture.lua declares no DPS authority writer inventory region")
    if not (beginAt and endAt and endAt > beginAt) then return end
    -- Every assignment to a DPS owner root must lie inside the declared region.
    local offenders, offset = {}, 0
    for line in source:gmatch("[^\r\n]+") do
        local at = offset + 1
        offset = offset + #line + 2
        local trimmed = line:match("^%s*(.-)%s*$")
        if not trimmed:find("^%-%-") then
            for _, field in ipairs(DPS_WRITE_FIELDS) do
                if trimmed:find("db%." .. field .. "%s*=") then
                    if at < beginAt or at > endAt then
                        offenders[#offenders + 1] = field .. " @" .. at
                    end
                end
            end
        end
    end
    Check(#offenders == 0,
        "DPS owner roots are assigned outside the exclusive writer inventory: "
            .. table.concat(offenders, ", "))
end)

Case("DPA-03",
    "the module-private preparation epoch advances once per replacement",
function()
    local internals = Nexus.MainInternals
    local owner = type(internals) == "table" and internals.DpsAuthority or nil
    Check(type(owner) == "table",
        "no module-private DpsAuthority owner is published on the seam")
    if type(owner) ~= "table" then return end
    Check(type(owner.Epoch) == "function",
        "the DPS authority owner exposes no preparation epoch")
    if type(owner.Epoch) ~= "function" then return end
    local db = DpsDatabase()
    local before = owner.Epoch()
    Check(type(owner.ReplaceRoots) == "function",
        "the DPS authority owner exposes no protected replacement")
    if type(owner.ReplaceRoots) ~= "function" then return end
    owner.ReplaceRoots(db, {}, {}, {dummy={}, lk={}})
    Check(owner.Epoch() == before + 1,
        "the preparation epoch advanced " .. (owner.Epoch() - before)
            .. " times for one protected replacement, required exactly 1")
end)

Case("DPA-04",
    "GUARD: DPS owner roots remain readable after bootstrap",
function()
    local db = DpsDatabase()
    local dps = Nexus.DpsCapture
    Check(type(dps) == "table", "DpsCapture is not loaded")
    if type(dps) ~= "table" then return end
    local ok, eligibility = pcall(dps.GetCommunityEligibility)
    Check(ok and type(eligibility) == "table",
        "the DPS eligibility read failed after bootstrap: "
            .. tostring(eligibility))
    Check(type(db.dpsCapture) == "table",
        "the DPS capture payload vanished from the database")
end)

-- ---------------------------------------------------------------------------
-- MASTER-RC-001, source-bound and per-pump metering enforcement.
--
-- Architecture lines 1356-1366 fix the complete Store source bounds and give
-- their exact derivations:
--   4,096 map entries
--   SGE = 4,096*16,384 + 4,096 + 16,384 + 2*16,384          = 67,162,112
--   SGN = 4,096*2,000 + 4,096 + 2 + 2,000 + 2*2,000         =  8,202,098
--   SGB = 4,096*32,768 + 749,568 + 32,768 + 2*32,768        = 135,065,600
--         where key bytes are 749,568 = 4,096*183
--   SM  = 4,096 + 4,096 + 64 + 32 + 2*16,384 + 2*16,384     =     73,824
--   SSC = 2*(2,048*11) + 64*6                               =     45,440
--   SSB = 2*183*((2*2,048*11) + (64*6))                     = 16,631,040
-- Line 1364: "One pump admits at most 8 rows, 64 edges, 64 nodes, 2,048 graph
-- bytes, 64 cursor entries, 64 comparisons, or 2,048 compared bytes."
--
-- The arithmetic is ASSERTED rather than assumed, so a later drift in any
-- factor breaks a test instead of silently violating the metering contract.
--
-- MET-04 is a guard: it passes before the repair and after it.
local function Seam()
    local internals = Nexus.MainInternals
    return type(internals) == "table" and internals.AuthorityBootstrap or nil
end

Case("MET-01",
    "the published source bounds equal their exact stated derivations",
function()
    local owner = Seam()
    Check(type(owner) == "table" and type(owner.SourceBounds) == "function",
        "no source bounds are published on the internals seam")
    if not (owner and type(owner.SourceBounds) == "function") then return end
    local bounds = owner.SourceBounds()
    local keyBytes = 4096 * 183
    local expected = {
        mapEntries = 4096,
        SGE = 4096 * 16384 + 4096 + 16384 + 2 * 16384,
        SGN = 4096 * 2000 + 4096 + 2 + 2000 + 2 * 2000,
        SGB = 4096 * 32768 + keyBytes + 32768 + 2 * 32768,
        SM  = 4096 + 4096 + 64 + 32 + 2 * 16384 + 2 * 16384,
        SSC = 2 * (2048 * 11) + 64 * 6,
        SSB = 2 * 183 * ((2 * 2048 * 11) + (64 * 6)),
    }
    local stated = {mapEntries=4096, SGE=67162112, SGN=8202098,
        SGB=135065600, SM=73824, SSC=45440, SSB=16631040}
    for name, value in pairs(expected) do
        Check(value == stated[name],
            name .. " derivation yields " .. value .. ", architecture states "
                .. tostring(stated[name]))
        Check(bounds[name] == value,
            name .. " is published as " .. tostring(bounds[name])
                .. ", required " .. value)
    end
    Check(keyBytes == 749568, "key bytes derivation is " .. keyBytes)
end)

Case("MET-02",
    "every per-pump dimension of line 1364 is enforced",
function()
    local owner = Seam()
    Check(type(owner) == "table" and type(owner.PumpCaps) == "function",
        "no per-pump caps are published on the internals seam")
    if not (owner and type(owner.PumpCaps) == "function") then return end
    local caps = owner.PumpCaps()
    local required = {rows=8, edges=64, nodes=64, graphBytes=2048,
        cursorEntries=64, comparisons=64, comparedBytes=2048}
    for name, value in pairs(required) do
        Check(caps[name] == value,
            "per-pump cap " .. name .. " is " .. tostring(caps[name])
                .. ", required " .. value)
    end
end)

Case("MET-03",
    "a source past the map-entry bound fails closed instead of admitting",
function()
    local db = {settingsVersion=2, settings={autoPick=false, anchorNames={}},
        chars={}, communityBuilds={}, syncTombstones={}}
    -- 4,097 rows is one past the stated 4,096 map-entry bound.
    for i = 1, 4097 do
        db.chars["C" .. i] = {tomeTogglePending={}, flagDemotions={},
            recordedPicks={}, loadoutWishlists={}}
    end
    NexusDB, WishlistRealizerDB = db, nil
    local coordinator = Nexus.MainInternals.AuthorityBootstrap.New()
    Nexus.Store.Init(coordinator)
    local result
    for _ = 1, 8192 do
        result = coordinator:PumpAuthorityBootstrap()
        if result.state ~= "pending" then break end
    end
    Check(type(result) == "table" and result.state == "failed",
        "an over-bound source was admitted instead of failing closed: "
            .. tostring(type(result) == "table" and result.state or result))
    Check(type(result) == "table" and result.reason == "STORE_INVALID",
        "an over-bound source failed with " ..
            tostring(type(result) == "table" and result.reason or "?")
            .. ", required STORE_INVALID")
end)

Case("MET-04",
    "GUARD: a source inside every bound still reaches STORE_READY",
function()
    local db = {settingsVersion=2, settings={autoPick=false, anchorNames={}},
        chars={}, communityBuilds={}, syncTombstones={}}
    for i = 1, 12 do
        db.chars["Ok" .. i] = {tomeTogglePending={}, flagDemotions={},
            recordedPicks={}, loadoutWishlists={}}
    end
    NexusDB, WishlistRealizerDB = db, nil
    local coordinator = Nexus.MainInternals.AuthorityBootstrap.New()
    Nexus.Store.Init(coordinator)
    for _ = 1, 512 do
        if coordinator:PumpAuthorityBootstrap().state ~= "pending" then break end
    end
    Check(coordinator:IsReady(),
        "an in-bounds source did not reach STORE_READY: "
            .. tostring(coordinator:State()))
end)

-- ---------------------------------------------------------------------------
-- MASTER-RC-001, intra-row resumption and the settings graph.
--
-- Line 1346 permits ONE row to carry up to 16,384 edges; line 1364 admits at
-- most 64 edges per pump. No pump can therefore charge a maximal row
-- atomically, so the architecture requires intra-row resumption for the general
-- graph exactly as it does for the tomeTogglePending levers. This is not
-- theoretical: the measured typical profile is ~66 edges per character row,
-- already past the per-pump edge cap for a single row.
--
-- Line 1347: "The settings graph has the same per-graph bounds", so it is
-- charged through the same frontier rather than left uncharged.
--
-- Both cases count STORE_CHAR_MIGRATION_PENDING slices, which is the only
-- externally observable consequence of the frontier stopping AT a cap.

local function WideCharDatabase(edges)
    local picks = {}
    for i = 1, edges do picks[200000 + i] = i end
    return {settingsVersion=2, settings={autoPick=false, anchorNames={}},
        chars={Wide={tomeTogglePending={}, flagDemotions={},
            recordedPicks=picks, loadoutWishlists={}}},
        communityBuilds={}, syncTombstones={}}
end

local function WideSettingsDatabase(edges)
    local settings = {autoPick=false, anchorNames={}}
    for i = 1, edges do settings["future" .. i] = i end
    return {settingsVersion=2, settings=settings, chars={},
        communityBuilds={}, syncTombstones={}}
end

Case("MET-05",
    "one oversized row is charged across pumps, never atomically",
function()
    -- 512 recorded picks is far past the 64-edge per-pump cap for one row.
    local counts = SliceProfile(WideCharDatabase(512))
    local slices = counts["STORE_CHAR_MIGRATION_PENDING"] or 0
    -- 512 edges at 64 per pump needs at least 8 charge slices for this row.
    Check(slices >= 8,
        "a single 512-edge row occupied " .. slices
            .. " STORE_CHAR_MIGRATION_PENDING slice(s); the 64-edge per-pump "
            .. "cap requires at least 8, so the row was charged atomically")
end)

Case("MET-06",
    "the settings graph is charged through the same bounded frontier",
function()
    -- No character rows at all, so every slice past the first can only come
    -- from charging the settings graph.
    local counts = SliceProfile(WideSettingsDatabase(512))
    local slices = counts["STORE_CHAR_MIGRATION_PENDING"] or 0
    Check(slices >= 8,
        "a 512-edge settings graph with zero character rows occupied "
            .. slices .. " slice(s); line 1347 gives settings the same "
            .. "per-graph bounds, so it must be charged like a row")
end)

Case("MET-07",
    "GUARD: an oversized row still converges and keeps its content",
function()
    local db = WideCharDatabase(512)
    local _, _, coordinator = SliceProfile(db)
    Check(coordinator:IsReady(),
        "an oversized row did not reach STORE_READY: "
            .. tostring(coordinator:State()))
    local picks = db.chars.Wide and db.chars.Wide.recordedPicks
    Check(type(picks) == "table" and picks[200001] == 1 and picks[200512] == 512,
        "resumable charging lost or altered the row content")
end)


-- ---------------------------------------------------------------------------
-- MASTER-RC-001, the DEPENDENT-SIDE prohibition of lines 1207-1211.
--
-- Architecture wave1-fixups/arch/state_machine.md lines 1207-1211, verbatim:
--   "`MainLifecycle` does not initialize ordinary account registration,
--    compaction, retention, Sync network handlers/egress, HUD, or renderer
--    consumers while that result is pending. `Store`, `DpsCapture`,
--    `LoadoutEvidence`, `BuildCatalog`, and every dependent initializer
--    register one idempotent dependency with this coordinator; they do not
--    call a domain recovery pump or raw writer directly."
--
-- The clause carries TWO independent obligations: registration (coordinator
-- side) and the prohibition (dependent side). Line 1715 makes `Init` such a
-- pump -- it "schedules or pumps one complete root admission" and "cannot be
-- called outside the startup coordinator or an explicit supported rebind."
--
-- The wave earlier evidenced RC-001 with run_store_legacy_retirement.lua:445-470,
-- which proved only that the coordinator RELEASES dependents in order. No case
-- anywhere asserted the dependent-side prohibition and no node ID referenced
-- 1207. MASTER-RC-001 was closed on incomplete evidence by the coordinator and
-- reopened on the worker finding. DEP-01 is the missing assertion.
--
-- SCOPE, stated explicitly so this check cannot narrow silently:
--   * A module driving its OWN domain pump is NOT a cross-domain drive. That
--     is MASTER-RC-006 one-slice concern and is deliberately not flagged here
--     (core/BuildCatalog.lua:2118 and :2705 are self-drives).
--   * Sync.Init and DpsCapture.Init called from core/MainLifecycle.lua via
--     RunIsolatedOwner are the accepted owner-start path and are NOT in the
--     drive inventory below. Adding them would widen RC-001 past the four
--     confirmed sites. This exclusion is deliberate and is recorded for the
--     coordinator judgement rather than decided here.
--
-- DEP-01 source-scan oracle. DEP-02 negative control. DEP-03 both-sides guard.

-- Each entry names a domain pump or raw writer and the core file that OWNS it.
-- The surface is matched as a REFERENCE, not only as a call: capturing
-- `Catalog().Init` as a value and invoking it later is the same direct drive
-- with one indirection. The coordinator hands these surfaces to OwnerCall by
-- reference, so core/Store.lua declares an explicit region instead.
local DOMAIN_DRIVES = {
    {pattern="LoadoutEvidence%s*%.%s*Init",
        owner="core/LoadoutEvidence.lua", surface="LoadoutEvidence.Init"},
    {pattern="Catalog%s*%(%s*%)%s*%.%s*Init",
        owner="core/BuildCatalog.lua", surface="Catalog().Init"},
    {pattern="BuildCatalog%s*%.%s*Init",
        owner="core/BuildCatalog.lua", surface="BuildCatalog.Init"},
    {pattern="[%w_]+%s*%.%s*BeginRootAdmission",
        owner="core/BuildCatalog.lua", surface="BeginRootAdmission"},
    {pattern="[%w_]+%s*%.%s*PumpRootAdmission",
        owner="core/BuildCatalog.lua", surface="PumpRootAdmission"},
    {pattern="DataCompaction%s*%.%s*Init",
        owner="core/DataCompaction.lua", surface="DataCompaction.Init"},
    {pattern="DataRetention%s*%.%s*Init",
        owner="core/DataRetention.lua", surface="DataRetention.Init"},
    {pattern="LegacyDataMigration%s*%.%s*Init",
        owner="core/LegacyDataMigration.lua",
        surface="LegacyDataMigration.Init"},
    {pattern="DpsCapture%s*%.%s*MigrateLegacyLeaderboard",
        owner="core/DpsCapture.lua",
        surface="DpsCapture.MigrateLegacyLeaderboard"},
}

local DRIVE_BEGIN = "AUTHORITY%-COORDINATOR%-DRIVE BEGIN"
local DRIVE_END = "AUTHORITY%-COORDINATOR%-DRIVE END"

-- Split preserving empty lines so reported line numbers are the real ones.
local function SourceLines(text)
    local out = {}
    for piece in (text .. "\n"):gmatch("(.-)\r?\n") do out[#out + 1] = piece end
    return out
end

-- Pure over (path, text) so DEP-02 can drive it with synthetic sources.
local function ScanForDirectDrives(path, text)
    local offenders, seen, inRegion = {}, {}, false
    for lineNo, line in ipairs(SourceLines(text)) do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed:find("^%-%-") then
            if trimmed:find(DRIVE_BEGIN) then inRegion = true
            elseif trimmed:find(DRIVE_END) then inRegion = false end
        elseif not inRegion then
            for _, drive in ipairs(DOMAIN_DRIVES) do
                if drive.owner ~= path and trimmed:find(drive.pattern) then
                    local key = path .. ":" .. lineNo
                    if not seen[key] then
                        seen[key] = true
                        offenders[#offenders + 1] =
                            key .. " -> " .. drive.surface
                    end
                end
            end
        end
    end
    return offenders
end

-- Enumerate from the addon manifest, not a hand-written list, so a new core
-- module is covered the moment it ships.
local function ManifestCoreFiles()
    local handle = assert(io.open("Nexus.toc", "rb"))
    local text = handle:read("*a")
    handle:close()
    local files = {}
    for _, line in ipairs(SourceLines(text)) do
        local trimmed = line:match("^%s*(.-)%s*$")
        if not trimmed:find("^#") then
            local path = trimmed:match("^(core[\\/][%w_]+%.lua)$")
            if path then files[#files + 1] = (path:gsub("\\", "/")) end
        end
    end
    return files
end

local function ReadSource(path)
    local handle = assert(io.open(path, "rb"), "cannot open " .. path)
    local text = handle:read("*a")
    handle:close()
    return text
end

Case("DEP-01",
    "no non-coordinator module drives another domain pump or raw writer",
function()
    local files = ManifestCoreFiles()
    -- Enumeration guard: a manifest parse failure must not read as a clean
    -- tree. The addon ships far more than 30 core modules.
    Check(#files >= 30,
        "the manifest enumeration returned only " .. #files
            .. " core modules, so DEP-01 would scan almost nothing")
    if #files < 30 then return end
    local offenders = {}
    for _, path in ipairs(files) do
        for _, offender in ipairs(ScanForDirectDrives(path, ReadSource(path))) do
            offenders[#offenders + 1] = offender
        end
    end
    Check(#offenders == 0,
        "architecture 1207-1211 forbids a dependent from calling a domain "
            .. "recovery pump or raw writer directly; " .. #offenders
            .. " reference(s) to another domain pump or raw writer sit "
            .. "outside a declared AUTHORITY-COORDINATOR-DRIVE region "
            .. "(guards and captures count: an indirected call is still a "
            .. "drive): "
            .. table.concat(offenders, ", "))
end)

Case("DEP-02",
    "NEGATIVE CONTROL: the direct-drive scanner still fails on a violation",
function()
    -- If DEP-01 ever goes green because the scanner stopped detecting rather
    -- than because the tree is clean, these assertions fail first.
    local planted = table.concat({
        "local function Start(db)",
        "    Nexus.LoadoutEvidence.Init(db)",
        "    Catalog().Init(db, Nexus.BundledBuilds)",
        "end",
    }, "\n")
    local caught = ScanForDirectDrives("core/DpsCapture.lua", planted)
    Check(#caught == 2,
        "the scanner found " .. #caught
            .. " of 2 planted cross-domain drives; it has stopped detecting")

    -- A self-drive must NOT be reported: that is RC-006 concern, and a
    -- scanner that flags it would make DEP-01 unfalsifiable for RC-001.
    local selfDrive = "    local summary = Catalog.Init(nextDb, nextBundle)"
    Check(#ScanForDirectDrives("core/BuildCatalog.lua", selfDrive) == 0,
        "the scanner reported a module driving its own domain pump")

    -- A declared coordinator region must suppress, and only within its bounds.
    local regioned = table.concat({
        "-- AUTHORITY-COORDINATOR-DRIVE BEGIN",
        "    Nexus.LoadoutEvidence.Init(db)",
        "-- AUTHORITY-COORDINATOR-DRIVE END",
        "    Nexus.LoadoutEvidence.Init(db)",
    }, "\n")
    local escaped = ScanForDirectDrives("core/Store.lua", regioned)
    Check(#escaped == 1 and escaped[1]:find(":4 ") ~= nil,
        "the declared region did not suppress exactly the drive inside it: "
            .. table.concat(escaped, ", "))

    -- A commented-out drive is not a drive.
    Check(#ScanForDirectDrives("core/Sync.lua",
        "    -- Catalog().Init(NexusDB, Nexus.BundledBuilds)") == 0,
        "the scanner reported a commented-out drive as a violation")
end)

Case("DEP-03",
    "GUARD: dependents still reach a serving catalog root after bootstrap",
function()
    -- Passes before the repair and after it. Removing the direct drives must
    -- not become a blanket refusal that leaves dependents unserved.
    local db = DpsDatabase()
    local catalog = Nexus.BuildCatalog
    Check(type(catalog) == "table", "BuildCatalog is not loaded")
    if type(catalog) ~= "table" then return end
    Check(catalog.BoundDatabase() == db,
        "the catalog is not bound to the coordinator-selected database")
    local evidence = Nexus.LoadoutEvidence
    Check(type(evidence) == "table", "LoadoutEvidence is not loaded")
    local ok, count = pcall(catalog.Count)
    Check(ok and type(count) == "number",
        "the catalog count read failed after bootstrap: " .. tostring(count))
end)

-- ---------------------------------------------------------------------------
-- MASTER-RC-001 REOPENED ELEMENT: catalog serving publication order.
-- MASTER-RC-006 element R: the bootstrap owner-rebind path must not drop
-- pending.
--
-- Architecture wave1-fixups/arch/state_machine.md lines 1517-1519, verbatim:
--   "Only after the disposition completes does
--    `STORE_SERVING_PUBLICATION_PENDING` construct/verify the replacement
--    serving pair and perform the final `currentServingRoot` swap. Then Store
--    enters `STORE_READY` and releases dependents. Thus a committed bundle is
--    not public authority during legacy disposition"
-- and line 1715: during initial bootstrap a completed `Init` call returns
--   "only a detached bounded summary of the privately sealed generation; it
--    becomes public only in the final all-domain serving publication."
--
-- WHY THIS FIXTURE HAD TO BE BUILT. The wave's structural coverage gap was
-- that NO fixture held both a live AuthorityBootstrapCoordinatorV1 and a live
-- BuildCatalog and read RootState() between pumps: every coordinator test
-- stubs BuildCatalog, and every real-catalog test has no coordinator. That is
-- why the defect below survived a 241/241 green suite, and it is the same
-- half-evidence shape that let MASTER-RC-001's first closure through. This
-- family closes that gap.
--
-- Expected-red measured on this tree immediately before the product edit:
--   PUB-01 RED  the catalog is publicly readable in STORE_COMPACTION_PENDING,
--               four coordinator states before
--               STORE_SERVING_PUBLICATION_PENDING.
--   PUB-02 PASS negative control -- publication is observable at all.
--   PUB-03 PASS both-sides guard -- a completed bootstrap serves every row.
--   PUB-04 ...  MASTER-RC-006 element R, measured here on the current tree.

local PUB_ROW = "pub-base"

local function PublicationDatabase(rows)
    local builds = {}
    builds[PUB_ROW] = {id=PUB_ROW, title="Publication base", author="A",
        postedAt=10, lastModified=10, echoes={{spellId=410000, stacks=1}}}
    for i = 2, (rows or 1) do
        builds["pub" .. i] = {id="pub" .. i, title="Row " .. i, author="A",
            postedAt=i, lastModified=i, echoes={{spellId=410000 + i, stacks=1}}}
    end
    return {settingsVersion=2, settings={autoPick=false, anchorNames={}},
        chars={}, communityBuilds=builds, syncTombstones={}, dpsCapture={}}
end

-- Holds a LIVE coordinator and a LIVE catalog and samples the catalog's public
-- surface between pumps. `interceptor` runs after each pump so a case can
-- perturb the source mid-bootstrap.
local function PublicationTrace(db, interceptor, turnBound)
    NexusDB, WishlistRealizerDB = db, nil
    local Store = Nexus.Store
    local coordinator = Nexus.MainInternals.AuthorityBootstrap.New()
    local catalog = Nexus.BuildCatalog
    local trace, turns = {}, 0
    local function Sample()
        local okCount, count = pcall(catalog.Count)
        local okGet, record = pcall(catalog.Get, PUB_ROW)
        local okStatus, status = pcall(catalog.Status)
        trace[#trace + 1] = {
            turn = turns,
            storeState = tostring(coordinator:State()),
            rootState = okStatus and tostring(status.state) or "?",
            count = okCount and count or -1,
            readable = (okGet and type(record) == "table") or false,
        }
    end
    local result = Store.Init(coordinator)
    Sample()
    while type(result) == "table" and result.state == "pending"
        and turns < (turnBound or H.BOOTSTRAP_TURN_BOUND) do
        turns = turns + 1
        result = coordinator:PumpAuthorityBootstrap()
        Sample()
        if interceptor then interceptor(turns, coordinator, catalog) end
    end
    return trace, result, coordinator
end

local function FirstPublicSample(trace)
    for _, sample in ipairs(trace) do
        if sample.readable or sample.count > 0 then return sample end
    end
    return nil
end

local function TraceText(trace)
    local parts = {}
    for _, s in ipairs(trace) do
        parts[#parts + 1] = s.turn .. ":" .. s.storeState .. "/" .. s.rootState
            .. "/count=" .. s.count .. (s.readable and "/READABLE" or "")
    end
    return table.concat(parts, "  ")
end

-- Coordinator states at or after which public catalog authority is permitted.
local PUBLICATION_ALLOWED = {
    STORE_SERVING_PUBLICATION_PENDING = true,
    STORE_READY = true,
}

Case("PUB-01",
    "catalog authority is not public before STORE_SERVING_PUBLICATION_PENDING",
function()
    local trace = PublicationTrace(PublicationDatabase(3))
    local first = FirstPublicSample(trace)
    Check(first ~= nil,
        "the catalog never became publicly readable during bootstrap, so this "
            .. "case cannot distinguish early publication from no publication")
    if not first then return end
    Check(PUBLICATION_ALLOWED[first.storeState] == true,
        "catalog authority became public at coordinator state "
            .. first.storeState .. " (turn " .. first.turn .. ", rootState "
            .. first.rootState .. "); architecture 1517-1519 permits the final "
            .. "currentServingRoot swap only in "
            .. "STORE_SERVING_PUBLICATION_PENDING, after legacy disposition, "
            .. "and line 1715 seals the bootstrap generation privately until "
            .. "then. Trace: " .. TraceText(trace))
end)

Case("PUB-02",
    "NEGATIVE CONTROL: catalog publication is observable by this fixture",
function()
    -- If the probe could not observe publication at all, PUB-01 would pass
    -- vacuously on any tree, including one that never publishes anything.
    local trace, result = PublicationTrace(PublicationDatabase(3))
    Check(type(result) == "table" and result.state == "ready",
        "the coordinator did not reach STORE_READY, so this fixture cannot "
            .. "observe a completed publication")
    local published = false
    for _, sample in ipairs(trace) do
        if sample.readable and sample.count > 0 then published = true end
    end
    Check(published,
        "this fixture observed no publicly readable catalog at any turn; the "
            .. "PUB-01 assertion would be vacuous. Trace: " .. TraceText(trace))
end)

Case("PUB-03",
    "GUARD: a completed bootstrap serves every admitted row",
function()
    -- Passes before the repair and after it. Moving the public swap later must
    -- not become a blanket refusal that never publishes.
    local trace, result = PublicationTrace(PublicationDatabase(3))
    Check(type(result) == "table" and result.state == "ready",
        "the coordinator did not reach STORE_READY: "
            .. tostring(type(result) == "table" and result.state or result))
    local catalog = Nexus.BuildCatalog
    Check(catalog.Status().state == "ROOT_ADMITTED",
        "the catalog root is not admitted after a completed bootstrap: "
            .. tostring(catalog.Status().state))
    Check(catalog.Count() == 3,
        "a completed bootstrap served " .. tostring(catalog.Count())
            .. " of 3 rows")
    local record = catalog.Get(PUB_ROW)
    Check(type(record) == "table" and record.title == "Publication base",
        "the served row lost its content after bootstrap")
    Check(trace[#trace].storeState == "STORE_READY",
        "the final sampled coordinator state was "
            .. tostring(trace[#trace].storeState))
end)

Case("PUB-04",
    "MASTER-RC-006 element R: no STORE_READY with a rebind outstanding",
function()
    -- Architecture 1205-1208 and 1519. The coordinator must not reach
    -- STORE_READY and release dependents while catalog rebind work is still
    -- outstanding. Only a fixture holding BOTH a live coordinator and a live
    -- catalog can perturb the source mid-bootstrap and observe this.
    local swapped = false
    local trace, result, coordinator = PublicationTrace(PublicationDatabase(3),
        function(_, _, catalog)
            -- Once the catalog has bound, replace the raw source behind it.
            -- A READ then records one explicit rebind request; it never binds.
            if not swapped and catalog.BoundDatabase() == NexusDB then
                swapped = true
                NexusDB = PublicationDatabase(2)
                pcall(catalog.Status)
            end
        end)
    Check(swapped, "the fixture never reached a bound catalog to perturb")
    local outstanding = Nexus.BuildCatalog.RebindRequired()
    Check(not (type(result) == "table" and result.state == "ready"
            and outstanding ~= nil),
        "the coordinator reached STORE_READY with catalog rebind work still "
            .. "outstanding (" .. tostring(outstanding) .. "); architecture "
            .. "1205-1208 and 1519 forbid releasing dependents while an "
            .. "initialization dependency is pending. Trace: "
            .. TraceText(trace))
    Check(coordinator ~= nil, "no coordinator was returned")
end)
-- Post-ready Store mutation pipeline (SMT) --------------------------------
--
-- MASTER-RC-001, second reopening. Architecture lines 1538-1540 open
-- core/Store.lua's own exhaustive transition table; its post-ready rows
-- (1580-1602) define a closed sub-machine that every post-ready mutation must
-- traverse:
--
--   STORE_READY | valid RegisterCurrentCharacter, Retention, or Compaction with
--                 no active input/candidate
--       -> capture one exact StoreMutationTokenV1;
--          STORE_MUTATION_BUILD_PENDING, pending
--   STORE_MUTATION_BUILD_PENDING | bounded slice incomplete   -> same, pending
--   STORE_MUTATION_BUILD_PENDING | candidate complete, token exact
--       -> STORE_MUTATION_FINAL_COMMIT_PENDING, pending
--   STORE_MUTATION_FINAL_COMMIT_PENDING | complete bundle/serving success
--       -> STORE_READY, {state="ready", result="MUTATION_COMMITTED"};
--          advance the bundle generation exactly once
--   STORE_MUTATION_FINAL_COMMIT_PENDING | post-publication notification fault
--       -> STORE_READY, {state="ready", result="MUTATION_COMMITTED",
--          notification="PENDING"}
--   STORE_MUTATION_BUILD_PENDING or _FINAL_COMMIT_PENDING | second request
--       -> same state, {state="failed", reason="STORE_MUTATION_BUSY"}
--
-- Acceptance ID: line 4850, DPS-01, whose RED list names this literally --
-- "a post-ready mutation has no closed result/route ledger".
--
-- ENTRY CONDITION, easy to get wrong and guarded explicitly below: the
-- sub-machine is reachable only FROM STORE_READY. The bootstrap coordinator's
-- own call to Store.RegisterCurrentCharacter from STORE_COMPACTION_PENDING is a
-- bootstrap finalizer step, not a post-ready mutation, and must NOT enter it.
--
-- EXPORT CEILING, likewise binding on the repair: architecture RAW-01 fixes the
-- inventories at "exact Store 9, Retention 8, and Compaction 8 API inventories
-- plus two counted private Store mutation entries". core/Store.lua has exactly
-- nine public Store.* exports today (measured). The pipeline therefore adds NO
-- public Store export; it is entered through two private coordinator entries on
-- Nexus.MainInternals.AuthorityBootstrap, which is where the accepted
-- architecture puts the machine and where these cases look for it.
--
-- SCOPE, disclosed rather than silently skipped. The table is exhaustive and
-- these three cases do not cover all of it. Deliberately NOT covered here, and
-- still owed by MASTER-RC-001 before the root can close: the
-- STORE_MUTATION_BUILD_PENDING rows for caller/request/current-character drift
-- (SOURCE_DRIFT), explicit cancellation (CANCELLED), coordinator supersession
-- (SUPERSEDED), candidate graph/limit fault (CANDIDATE_FAILED), and the
-- selected bundle/StoreData/serving/authorityDatabase drift row that enters
-- STORE_INVALID. They are named here so a reader cannot mistake this set for
-- the whole contract.

-- The two private coordinator entries the repair must provide. Resolved
-- through the coordinator object so a case reports the exact missing surface
-- rather than dying on a nil call.
local function StoreMutationEntries(coordinator)
    if type(coordinator) ~= "table" then return nil, nil end
    local begin = coordinator.BeginStoreMutationV1
    local pump = coordinator.PumpStoreMutationV1
    return type(begin) == "function" and begin or nil,
        type(pump) == "function" and pump or nil
end

local SMT_ROW = "smtRetention"

-- Drives the fixture to STORE_READY and asserts it got there, so no case below
-- can pass or fail for the wrong reason. Accepts either a row count (the shared
-- PublicationDatabase) or an explicit database, so a case needing special rows
-- does not have to perturb the fixture PUB-01..04 assert against.
local function ReadyCoordinator(rowsOrDb, turnBound)
    local db = type(rowsOrDb) == "table" and rowsOrDb
        or PublicationDatabase(rowsOrDb or 3)
    local trace, result, coordinator = PublicationTrace(db, nil, turnBound)
    Check(type(result) == "table" and result.state == "ready"
        and coordinator ~= nil
        and tostring(coordinator:State()) == "STORE_READY",
        "the fixture did not reach STORE_READY, so no post-ready mutation "
            .. "assertion below can mean anything. Trace: " .. TraceText(trace))
    return coordinator, trace
end

-- CORRECTED after the sixth consultation. The previous SMT-01 was internally
-- contradictory: it demanded the public Store.RegisterCurrentCharacter() call
-- write durably AND synchronously, and then separately called the private begin
-- entry. Once registration is properly asynchronous those two demands cannot
-- both hold. Architecture ~1888 classifies Store.RegisterCurrentCharacter as
-- DURABLE_MUTATION and 1897-1899 says it "submits one StoreAuthorityOwnerV1
-- mutation and can complete only through a complete bundle replacement" -- so
-- the public call SUBMITS, and scheduler turns complete it.
Case("SMT-01",
    "the public registration call submits and scheduler turns commit it",
function()
    local coordinator = ReadyCoordinator(3)
    Check(tostring(coordinator:State()) == "STORE_READY",
        "the fixture is not at STORE_READY, so the post-ready entry row cannot "
            .. "be exercised")

    -- The submission itself: zero synchronous durable effect.
    local db = NexusDB
    local ownerKey = Nexus.Store.CurrentOwnerKey()
    Check(ownerKey ~= nil,
        "the fixture identity has no owner key, so this case would be vacuous")
    local accountsBefore = db.accountCharacters
    local rowBefore = type(accountsBefore) == "table"
        and accountsBefore[ownerKey] or nil
    local lastSeenBefore = type(rowBefore) == "table" and rowBefore.lastSeen or nil

    local submitted = Nexus.Store.RegisterCurrentCharacter()
    Check(type(submitted) == "table" and submitted.state == "pending",
        "the public post-ready registration call did not SUBMIT a pending "
            .. "mutation; got " .. tostring(type(submitted) == "table"
                and submitted.state or submitted))
    Check(tostring(coordinator:State()) == "STORE_MUTATION_BUILD_PENDING",
        "submission did not capture a StoreMutationTokenV1 and enter "
            .. "STORE_MUTATION_BUILD_PENDING; state is "
            .. tostring(coordinator:State()))

    -- Scheduler turns complete it: ONE slice per turn, never a synchronous
    -- drain inside the submitting call.
    local _, pump = StoreMutationEntries(coordinator)
    Check(pump ~= nil, "the coordinator exposes no mutation pump")
    local settled, turns = nil, 0
    while turns < H.BOOTSTRAP_TURN_BOUND do
        turns = turns + 1
        settled = pump(coordinator)
        if type(settled) == "table" and settled.state ~= "pending" then break end
    end
    Check(turns >= 2,
        "the mutation completed in a single slice, so it was drained rather "
            .. "than sliced across turns; turns=" .. tostring(turns))
    Check(type(settled) == "table" and settled.state == "ready"
        and settled.result == "MUTATION_COMMITTED",
        "the committed post-ready mutation did not return the literal "
            .. "{state=\"ready\", result=\"MUTATION_COMMITTED\"}; got "
            .. tostring(type(settled) == "table" and settled.state)
            .. "/" .. tostring(type(settled) == "table" and settled.result))
    Check(tostring(coordinator:State()) == "STORE_READY",
        "the coordinator did not return to STORE_READY after committing")

    -- The durable effect landed exactly once, at commit, not at submission.
    local accountsAfter = NexusDB.accountCharacters
    Check(type(accountsAfter) == "table" and accountsAfter[ownerKey] ~= nil,
        "the committed registration wrote no durable account row")
    Check(accountsAfter[ownerKey].lastSeen ~= nil,
        "the committed registration captured no observation")
    if lastSeenBefore ~= nil then
        Check(accountsAfter[ownerKey].lastSeen >= lastSeenBefore,
            "the committed registration moved lastSeen backwards")
    end
end)

Case("SMT-W2-01", "Store waits for each pending maintenance owner", function()
    for _, route in ipairs({"Retention", "Compaction"}) do
        local coordinator = ReadyCoordinator(3)
        local begin, pump = StoreMutationEntries(coordinator)
        local field = route == "Retention" and "DataRetention" or "DataCompaction"
        local saved, calls = Nexus[field], 0
        S.pendingRestores[#S.pendingRestores + 1] = function() Nexus[field] = saved end
        local function OwnerStep()
            calls = calls + 1
            return {pending=calls < 3}, calls == 3
        end
        Nexus[field] = {Enforce=OwnerStep, Pump=OwnerStep}
        Check(begin(coordinator, {route=route}).state == "pending",
            route .. " did not submit")
        Check(pump(coordinator).state == "pending" and calls == 0,
            route .. " build phase ran the commit owner")
        for expected = 1, 2 do
            local result = pump(coordinator)
            Check(result.state == "pending" and calls == expected
                    and coordinator:State() == "STORE_MUTATION_FINAL_COMMIT_PENDING",
                route .. " acknowledged pcall success before terminal owner completion")
            Check(begin(coordinator, {route=route}).reason == "STORE_MUTATION_BUSY",
                route .. " released the pending mutation to a second request")
        end
        local result = pump(coordinator)
        Check(calls == 3 and result.state == "ready"
                and result.result == "MUTATION_COMMITTED",
            route .. " did not settle its terminal owner result")
        pump(coordinator)
        Check(calls == 3, route .. " repeated a terminal owner action")
        Nexus[field] = saved
    end
end)

Case("SMT-W2-02", "Store refuses failed maintenance owner results", function()
    for _, route in ipairs({"Retention", "Compaction"}) do
        local coordinator = ReadyCoordinator(3)
        local begin, pump = StoreMutationEntries(coordinator)
        local field = route == "Retention" and "DataRetention" or "DataCompaction"
        local saved = Nexus[field]
        S.pendingRestores[#S.pendingRestores + 1] = function() Nexus[field] = saved end
        local function Refuse() return {pending=false, blocked=true, reason="CANDIDATE_FAILED"}, false end
        Nexus[field] = {Enforce=Refuse, Pump=Refuse}
        begin(coordinator, {route=route})
        pump(coordinator)
        local result = pump(coordinator)
        Check(result.state == "ready" and result.result == "CANDIDATE_FAILED",
            route .. " acknowledged a refused owner result as committed")
        Nexus[field] = saved
    end
end)

Case("SMT-W2-03", "Store binds the exact terminal retention bundle", function()
    S.pendingRestores[#S.pendingRestores + 1] = function() S.Reload() end
    for _, tamper in ipairs({false, true}) do
        S.Reload()
        local db = PublicationDatabase(96)
        db.communityBuilds[SMT_ROW] = {id=SMT_ROW, title="Pending retention row",
            author="Boganic", class="MAGE", ownerKey="boganic@ebonhold",
            realm="ebonhold", ownerVerified=true, isMine=true,
            postedAt=10, lastModified=10, echoes={{spellId=410099, stacks=1}}}
        local coordinator = ReadyCoordinator(db, 20000)
        local catalog = Nexus.BuildCatalog
        local ok, why, ticket = catalog.SetTombstone(SMT_ROW,
            {stamp=now, author="Boganic", ownerKey="boganic@ebonhold", ownerVerified=true},
            {source="local"})
        if ok == nil and why == "ROOT_MUTATION_PENDING" then
            for _ = 1, 20000 do
                if ticket.state ~= "pending" then break end
                catalog.PumpRootAdmission()
            end
            ok = ticket.committed
        end
        Check(ok == true, "pending retention fixture could not create its tombstone")
        local originalNow = now
        S.pendingRestores[#S.pendingRestores + 1] = function() now = originalNow end
        now = now + 180 * 24 * 60 * 60 + 1
        local before = rawget(db, "authorityBundle")
        local begin, pump = StoreMutationEntries(coordinator)
        begin(coordinator, {route="Retention"})
        pump(coordinator)
        local pending = pump(coordinator)
        Check(pending.state == "pending" and rawget(db, "authorityBundle") == before,
            "Store did not retain the real pending retention transaction: "
                .. tostring(pending.state) .. "/" .. tostring(pending.result)
                .. " root=" .. tostring(catalog.RootState().state))
        local observed
        for _ = 1, 20000 do
            observed = catalog.PumpRootAdmission()
            if type(observed) == "table" and observed.state ~= "pending" then break end
        end
        Check(observed.committed == true and observed.bundle == rawget(db, "authorityBundle")
                and observed.database == db and observed.bundle ~= before,
            "retention did not settle one exact bundle receipt")
        if tamper then
            local replacement = {}
            for key, value in pairs(observed.bundle) do replacement[key] = value end
            rawset(db, "authorityBundle", replacement)
        end
        local result = pump(coordinator)
        Check(result.result == (tamper and "SOURCE_DRIFT" or "MUTATION_COMMITTED"),
            "Store accepted the wrong bundle or refused its own completed owner")
        Check(observed.bundle.transactionGeneration == before.transactionGeneration + 1,
            "retention advanced the bundle generation more than once")
        now = originalNow
    end
end)

Case("SMT-02",
    "a second post-ready mutation request refuses as STORE_MUTATION_BUSY",
function()
    local coordinator = ReadyCoordinator(3)
    local begin = StoreMutationEntries(coordinator)
    Check(begin ~= nil,
        "the coordinator exposes no private post-ready mutation entry, so the "
            .. "STORE_MUTATION_BUSY row cannot be reached at all")

    local first = begin(coordinator, {route="RegisterCurrentCharacter"})
    Check(type(first) == "table" and first.state == "pending",
        "the first request did not open a candidate")
    local second = begin(coordinator, {route="Retention"})
    Check(type(second) == "table" and second.state == "failed"
        and second.reason == "STORE_MUTATION_BUSY",
        "a second mutation request while a candidate is open did not return "
            .. "{state=\"failed\", reason=\"STORE_MUTATION_BUSY\"}; got "
            .. tostring(type(second) == "table" and second.state)
            .. "/" .. tostring(type(second) == "table" and second.reason))
end)

-- Why this case uses the Retention route and not RegisterCurrentCharacter.
-- Measured, and it is a finding in its own right: RegisterCurrentCharacter has
-- NO notification path at all -- it never calls NotifyBuild or any notification
-- surface -- so a post-publication notification fault cannot occur on that
-- route and asserting one there would be unfalsifiable. The notification row at
-- 1598 belongs to the routes that publish through the catalog owner: Retention
-- and Compaction, both of which reach BuildCatalog's NotifyBuild through
-- Catalog.CommitMaintenance (core/DataRetention.lua:470,575 and
-- core/DataCompaction.lua:725).
Case("SMT-03",
    "a post-publication notification fault commits and replays notification only",
function()
    -- This case needs a LOCALLY OWNED row, because only a local owner may set
    -- the current-session tombstone Retention later retires
    -- (SetTombstone refuses a foreign row with LOCAL_OWNER_REQUIRED, measured).
    -- It therefore builds its own database rather than perturbing the shared
    -- PublicationDatabase that PUB-01..04 assert against.
    local db = PublicationDatabase(3)
    db.communityBuilds[SMT_ROW] = {id=SMT_ROW, title="Retention row",
        author="Boganic", class="MAGE", ownerKey="boganic@ebonhold",
        realm="ebonhold", ownerVerified=true, isMine=true,
        postedAt=10, lastModified=10, echoes={{spellId=410099, stacks=1}}}
    local coordinator = ReadyCoordinator(db)
    local begin, pump = StoreMutationEntries(coordinator)
    Check(begin ~= nil and pump ~= nil,
        "the coordinator exposes no private post-ready mutation entries, so "
            .. "the 1598 notification row cannot be reached at all")

    -- REAL maintenance work, so the route genuinely publishes and genuinely
    -- notifies: a current-session tombstone aged past the 180-day trusted
    -- retirement bound, which Retention retires through
    -- ExpireReservations -> Catalog.CommitMaintenance -> NotifyBuild.
    local catalog = Nexus.BuildCatalog
    local DAY = 24 * 60 * 60
    local restoreNow = now
    S.pendingRestores[#S.pendingRestores + 1] = function() now = restoreNow end
    local tombstoned, tombWhy = catalog.SetTombstone(SMT_ROW,
        {stamp=now, author="Boganic", ownerKey="boganic@ebonhold",
            ownerVerified=true}, {source="local"})
    Check(tombstoned,
        "the fixture could not create the tombstone this case retires: "
            .. tostring(tombWhy))
    now = now + 180 * DAY + 1

    -- Harness-only counting collaborator, the exact shape NTF-01 uses. Only the
    -- notification collaborator is swapped; no production fault-injection
    -- export exists or is added. Installed AFTER the tombstone above, so the
    -- first counted attempt is the Retention commit's own notification.
    local attempts = {}
    local realAdvance = Nexus.Revisions.Advance
    S.pendingRestores[#S.pendingRestores + 1] = function()
        Nexus.Revisions.Advance = realAdvance
    end
    Nexus.Revisions.Advance = function(event, detail)
        attempts[#attempts + 1] = {event=event, reason=detail and detail.reason,
            scope=detail and detail.scope, id=detail and detail.id}
        if #attempts == 1 then error("notification collaborator failed") end
        return realAdvance(event, detail)
    end

    local entered = begin(coordinator, {route="Retention"})
    Check(type(entered) == "table" and entered.state == "pending",
        "the Retention route did not open a candidate")
    local settled, turns = nil, 0
    while turns < H.BOOTSTRAP_TURN_BOUND do
        turns = turns + 1
        settled = pump(coordinator)
        if type(settled) == "table" and settled.state ~= "pending" then break end
    end

    -- NON-VACUITY: the route must actually have notified, or every assertion
    -- below is about nothing.
    Check(#attempts >= 1,
        "the Retention route published nothing and notified nothing, so this "
            .. "case cannot observe a post-publication notification fault")
    Check(type(settled) == "table" and settled.state == "ready"
        and settled.result == "MUTATION_COMMITTED",
        "a post-publication notification fault did not leave the mutation "
            .. "committed and final; got "
            .. tostring(type(settled) == "table" and settled.state) .. "/"
            .. tostring(type(settled) == "table" and settled.result))
    Check(settled.notification == "PENDING",
        "architecture line 1598 requires {state=\"ready\", "
            .. "result=\"MUTATION_COMMITTED\", notification=\"PENDING\"} for a "
            .. "post-publication notification fault; notification was "
            .. tostring(settled.notification))
    Check(catalog.TombstoneState(SMT_ROW).state == "NONE",
        "the notification fault undid the committed retention mutation")

    -- REAL REPLAY, to NTF-01's standard: dispatched by a later ordinary
    -- scheduler turn through the shared NotifyBuild mechanism, carrying the
    -- exact failed notification, with no duplicate afterwards.
    local delivered = #attempts
    Nexus.Scheduler.Tick(GetTime())
    Check(#attempts == delivered + 1,
        "the scheduler turn dispatched no notification replay; attempts="
            .. tostring(#attempts))
    local replay = attempts[#attempts]
    Check(replay.event == attempts[1].event
        and replay.reason == attempts[1].reason
        and replay.scope == attempts[1].scope
        and replay.id == attempts[1].id,
        "the replay did not carry the exact failed notification: "
            .. tostring(replay.reason) .. "/" .. tostring(replay.scope)
            .. "/" .. tostring(replay.id) .. " vs "
            .. tostring(attempts[1].reason) .. "/" .. tostring(attempts[1].scope)
            .. "/" .. tostring(attempts[1].id))
    Nexus.Scheduler.Tick(GetTime())
    Nexus.Scheduler.Tick(GetTime())
    Check(#attempts == delivered + 1,
        "a later scheduler turn delivered a duplicate notification; attempts="
            .. tostring(#attempts))
end)

-- SRP-STORE-STATE-01 (MASTER-RC-001, sixth consultation + amendment 10).
--
-- Store.State is classified DURABLE_READ at architecture line ~1888 and must be
-- a pure read. Three separate violations were repaired:
--   1. it called Store.RegisterCurrentCharacter (a DURABLE_MUTATION);
--   2. EnsureStateShape mutated the durable row in place;
--   3. `db.chars[ownerKey] = state` was a direct durable write outside the sole
--      authorized payload-write path (line 392, "Never mutate a live nested
--      bundle field"; RAW-01's RED condition for writing a nested/live
--      authority field), and the live table was returned.
--
-- The write path is now StoreAuthorityOwnerV1.UpdateStateV1 (lines 1907-1912),
-- and all 32 former write-through call sites were migrated to it under
-- amendment 10 before the read was made defensive.
Case("SRP-STORE-STATE-01",
    "Store.State is a pure defensive read that performs no mutation",
function()
    local coordinator = ReadyCoordinator(3)
    Check(tostring(coordinator:State()) == "STORE_READY",
        "the fixture did not reach STORE_READY")
    local db = NexusDB
    local ownerKey = Nexus.Store.CurrentOwnerKey()
    Check(ownerKey ~= nil, "no owner key, so this case would be vacuous")

    -- Seed a durable row through the AUTHORIZED entry, so there is real state
    -- to read and the case is not measuring an empty table.
    local owner = Nexus.MainInternals.StoreAuthorityOwner
    Check(type(owner) == "table" and type(owner.UpdateStateV1) == "function",
        "StoreAuthorityOwnerV1.UpdateStateV1 is unavailable")
    owner.UpdateStateV1(function(state) state.srpProbe = "seeded" end)
    Check(type(db.chars) == "table" and type(db.chars[ownerKey]) == "table"
        and db.chars[ownerKey].srpProbe == "seeded",
        "the authorized write path did not reach the durable row")

    -- 1. DETACHED: the read never hands back the live durable table.
    local first = Nexus.Store.State()
    Check(type(first) == "table", "Store.State returned no table")
    Check(first ~= db.chars[ownerKey],
        "Store.State returned the LIVE durable row; a caller could mutate "
            .. "durable authority through a DURABLE_READ")
    Check(first.srpProbe == "seeded",
        "the defensive copy lost the durable content it is meant to report")

    -- 2. STABLE IDENTITY across unchanged reads. Checked BEFORE anything
    --    mutates the copy, so it measures the snapshot contract and nothing
    --    else. Returning a freshly allocated table on every read is not
    --    required by the architecture (which asks only for a bounded defensive
    --    copy) and actively breaks the product's identity-based change
    --    detection -- measured: 2 fixtures failed on exactly that, e.g.
    --    "five-second fallback rebuilt unchanged static automation". The
    --    earlier revision of this case asserted the opposite ("two reads
    --    returned the same mutable table" was treated as a failure); that
    --    expectation was superseded by the coordinator's ruling and is recorded
    --    here as withdrawn so it is not reintroduced. The property that
    --    matters -- durable state is unreachable through the return -- is
    --    asserted in full at 1 and 3.
    Check(Nexus.Store.State() == first,
        "two reads with no intervening write returned different tables; "
            .. "identity-based change detection would rebuild on every read")

    -- 3. A caller mutating the copy cannot reach durable state.
    first.srpProbe = "mutated-through-the-read"
    first.flagDemotions = {injected=true}
    Check(db.chars[ownerKey].srpProbe == "seeded",
        "mutating Store.State's return changed the durable row")
    Check(db.chars[ownerKey].flagDemotions == nil
        or db.chars[ownerKey].flagDemotions.injected == nil,
        "mutating Store.State's return injected a durable field")

    -- 4. INVALIDATION: an authorized write must be visible to the next read.
    --    A stale cache here would be a silent correctness defect, so this is
    --    measured rather than assumed.
    owner.UpdateStateV1(function(state) state.srpProbe = "rewritten" end)
    local afterWrite = Nexus.Store.State()
    Check(afterWrite ~= first,
        "the read snapshot survived an authorized write; the cache is stale")
    Check(afterWrite.srpProbe == "rewritten",
        "a read after an authorized write did not observe the write")
    owner.UpdateStateV1(function(state) state.srpProbe = "seeded" end)

    -- 5. Row REPLACEMENT by any other path must also invalidate.
    db.chars[ownerKey] = {srpProbe="replaced-underneath"}
    Check(Nexus.Store.State().srpProbe == "replaced-underneath",
        "the read snapshot survived a replacement of the durable row itself")

    -- 4. The read performs NO mutation of any kind: no durable byte moves and
    --    no Store mutation is admitted or requested by reading.
    local encoded = Nexus.Codec.JSONEncode(db.chars)
    for _ = 1, 5 do Nexus.Store.State() end
    Check(Nexus.Codec.JSONEncode(db.chars) == encoded,
        "repeated Store.State reads changed durable per-character state")
    Check(tostring(coordinator:State()) == "STORE_READY",
        "Store.State admitted a Store mutation; the coordinator left "
            .. "STORE_READY on a pure read")

    -- 5. A read on a character with NO durable row must not create one.
    local absent = {}
    for key, value in pairs(db.chars) do absent[key] = value end
    db.chars[ownerKey] = nil
    local fresh = Nexus.Store.State()
    Check(type(fresh) == "table", "Store.State returned no table for a new character")
    Check(db.chars[ownerKey] == nil,
        "a pure read CREATED a durable per-character row; only "
            .. "StoreAuthorityOwnerV1.UpdateStateV1 may write one")
    db.chars[ownerKey] = absent[ownerKey]
end)

S.Finish("catalog authority durable kernel")
