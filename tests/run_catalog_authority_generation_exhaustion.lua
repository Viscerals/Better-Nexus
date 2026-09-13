-- Package B / issue #22 Repair Wave 1: generation domain and exhaustion.
--
-- Covers MASTER-RC-007 (generation counters lack a maximum and
-- AUTHORITY_GENERATION_EXHAUSTED).
--
-- Architecture at 3b5de54f, docs/SYNC_TRUST_CATALOG_AUTHORITY_STATE_MACHINE.md:
--   "Every durable generation or revision is an unsigned exact Lua 5.1 integer in
--    `0..9,007,199,254,740,991`."
--   "Before any required durable or session increment at the maximum, the
--    bootstrap coordinator enters the outer deny-only state
--    `AUTHORITY_GENERATION_EXHAUSTED`. This state has precedence over every
--    root/domain/API state. It publishes no candidate, permits no read that can
--    grant authority, mutation, claim, cursor, provider operation, maintenance
--    operation, or network operation, and exposes only the fixed bounded
--    diagnostic result `GENERATION_EXHAUSTED`."
--   "Reload detects a maximum selected durable counter before current-schema
--    admission and re-enters the same state. A negative, fractional, nonfinite, or
--    larger durable value is malformed current-schema evidence."
--   "No exhausted counter can be made current by byte equality."
--
-- The fixture drives the counter through durable SavedVariables state only. It
-- installs no production fault hook and uses no production fault export.
--
-- Expected-red measurement on the rejected candidate e69497d, before any product
-- edit in this wave:
--   GEN-01 RED  no durable generation domain is validated; a forged value is
--               admitted.
--   GEN-02 RED  a reload at the maximum grants full authority.
--   GEN-03 RED  the required increment at the maximum is performed instead of
--               being refused, and no deny-only state is latched.
--   GEN-04 RED  no AUTHORITY_GENERATION_EXHAUSTED state exists, so no API denies.
--   GEN-05 RED  restoring old durable bytes silently restores authority.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Codec.lua")
local S = dofile("tests/catalog_authority_support.lua")
local Case, Check = S.Case, S.Check

local function AwaitMutation(catalog, ok, why, ticket)
    if ok ~= nil then return ok, why end
    if why ~= "ROOT_MUTATION_PENDING" or type(ticket) ~= "table" then
        return false, why
    end
    for _ = 1, catalog.Budget().maximumPumps do
        if ticket.state ~= "pending" then break end
        catalog.PumpRootAdmission()
    end
    return ticket.state == "committed" and ticket.committed == true,
        ticket.reason
end

local now = 2000000000
time = function() return now end
UnitClass = function() return "Mage", "MAGE" end

local MAX = 9007199254740991

local function Catalog() return Nexus.BuildCatalog end
local function Bundle(db) return rawget(db, "authorityBundle") end

local function CatalogState()
    for index = 1, 64 do
        local name, value = debug.getupvalue(Catalog().RootState, index)
        if name == "ST" then return value end
        if name == nil then break end
    end
    error("unable to locate module-private catalog state", 2)
end

local function Fresh(rows)
    S.Reload()
    local db = S.Database(rows or {genSession=S.LocalBuild("genSession", 2)})
    S.Bind(db)
    Check(S.Root().state == "ROOT_ADMITTED", "fresh counter fixture did not admit")
    return db, Catalog(), CatalogState()
end

-- Bind once so the durable bundle exists, then place an exact durable counter
-- value and rebind through a reload. Only SavedVariables bytes are edited.
--
-- The leading reload is required, not cosmetic: the deny-only state is a session
-- latch that no byte edit may clear, so a case that follows a latched case must
-- start from a genuinely fresh session.
local function BoundAt(value, overlay)
    S.Reload()
    local db = S.Database(overlay or {genA=S.LocalBuild("genA", 2)})
    S.Bind(db)
    local bundle = Bundle(db)
    Check(type(bundle) == "table",
        "no durable authority payload slot: MASTER-RC-001 kernel is absent")
    rawset(bundle, "transactionGeneration", value)
    S.Reload()
    S.Bind(db)
    return db, Catalog()
end

Case("GEN-01",
    "a durable generation outside the exact integer domain is malformed, not current",
function()
    for _, forged in ipairs({-1, 1.5, MAX + 2, "9", 0 / 0}) do
        local db, catalog = BoundAt(forged)
        local root = S.Root()
        Check(root.state ~= "ROOT_ADMITTED",
            "a forged durable generation " .. tostring(forged)
                .. " was admitted as current authority")
        Check(catalog.Get("genA") == nil,
            "a forged durable generation " .. tostring(forged)
                .. " still served an authority row")
        -- The malformed evidence is preserved, never repaired in place.
        Check(rawget(Bundle(db), "transactionGeneration") == forged
            or (forged ~= forged
                and rawget(Bundle(db), "transactionGeneration") ~= forged),
            "malformed durable evidence was rewritten instead of preserved")
    end
end)

Case("GEN-02",
    "reload at the maximum re-enters the deny-only exhausted state",
function()
    local db, catalog = BoundAt(MAX)
    local root = S.Root()
    Check(root.state == "AUTHORITY_GENERATION_EXHAUSTED",
        "reload at the maximum durable generation did not enter "
            .. "AUTHORITY_GENERATION_EXHAUSTED, got " .. tostring(root.state))
    Check(catalog.Get("genA") == nil and catalog.Count() == 0,
        "the exhausted state served authority rows")
end)

Case("GEN-03",
    "the required increment at the maximum is refused before it is performed",
function()
    local db, catalog = BoundAt(MAX - 1)
    Check(S.Root().state == "ROOT_ADMITTED",
        "MAX-1 must remain a legal current generation, got " .. tostring(S.Root().state))

    -- One more complete durable-bundle replacement reaches exactly MAX.
    Check(AwaitMutation(catalog, catalog.Put(S.LocalBuild("genB", 3))),
        "the MAX-1 -> MAX commit was refused")
    Check(rawget(Bundle(db), "transactionGeneration") == MAX,
        "the MAX-1 -> MAX commit did not land on the exact maximum, got "
            .. tostring(rawget(Bundle(db), "transactionGeneration")))

    local bundleAtMax = Bundle(db)
    local bytesAtMax = S.Encode(rawget(bundleAtMax, "communityBuilds"))

    -- The next required increment must be refused, latched before any increment.
    local ok, why = catalog.Put(S.LocalBuild("genC", 4))
    Check(ok == false, "an increment past the maximum durable generation succeeded")
    Check(why == "GENERATION_EXHAUSTED",
        "the refusal used the reason " .. tostring(why)
            .. " instead of the fixed GENERATION_EXHAUSTED result")
    Check(Bundle(db) == bundleAtMax,
        "the refused increment replaced the durable bundle pointer")
    Check(rawget(Bundle(db), "transactionGeneration") == MAX,
        "the refused increment advanced the durable generation past the maximum")
    Check(S.Encode(rawget(Bundle(db), "communityBuilds")) == bytesAtMax,
        "the refused increment changed durable payload bytes")
end)

Case("GEN-04",
    "the latched state has precedence over every authority-bearing API",
function()
    local db, catalog = BoundAt(MAX - 1)
    Check(AwaitMutation(catalog, catalog.Put(S.LocalBuild("genB", 3))),
        "the MAX-1 -> MAX commit was refused")
    Check(catalog.Put(S.LocalBuild("genC", 4)) == false,
        "an increment past the maximum succeeded")

    Check(S.Root().state == "AUTHORITY_GENERATION_EXHAUSTED",
        "the refused increment did not latch the outer deny-only state, got "
            .. tostring(S.Root().state))

    -- Reads that can grant authority.
    Check(catalog.Get("genA") == nil, "Get served a row while exhausted")
    Check(catalog.Get("genB") == nil, "Get served a committed row while exhausted")
    Check(catalog.Count() == 0, "Count exposed a scalar count while exhausted")
    local all, allWhy = catalog.All()
    Check(all == nil and allWhy == "GENERATION_EXHAUSTED",
        "All exposed rows while exhausted (" .. tostring(allWhy) .. ")")
    Check(catalog.IsAdmittedRecord("genB") == false,
        "IsAdmittedRecord granted authority while exhausted")

    -- Mutation, claim, cursor, and maintenance operations.
    local function Denied(label, ok, why)
        Check(ok == false or ok == nil,
            label .. " succeeded while the exhausted state was latched")
        Check(why == "GENERATION_EXHAUSTED",
            label .. " refused with " .. tostring(why)
                .. " instead of the fixed GENERATION_EXHAUSTED result")
    end
    Denied("Put", catalog.Put(S.LocalBuild("genD", 5)))
    Denied("RemoveOverlay", catalog.RemoveOverlay("genA"))
    Denied("SetTombstone", catalog.SetTombstone("genA",
        {stamp=now, author="Boganic", ownerKey="boganic@ebonhold",
         ownerVerified=true}, {source="local"}))
    Denied("BeginAllocationClaim", catalog.BeginAllocationClaim("genFresh"))
    Denied("BeginRecordCursor", catalog.BeginRecordCursor())
    Denied("BeginCatalogMaintenance", catalog.BeginCatalogMaintenance({
        database=db, operation="retention"}))

    -- Diagnostics expose only the bounded fixed result.
    local state = S.Root()
    Check(state.reason == "GENERATION_EXHAUSTED",
        "RootState exposed the reason " .. tostring(state.reason))
    Check(state.generationMaximum == MAX,
        "diagnostics do not expose the exact fixed maximum, got "
            .. tostring(state.generationMaximum))
end)

Case("GEN-05",
    "restoring old durable bytes does not make an exhausted counter current",
function()
    local db, catalog = BoundAt(MAX - 1)
    local restorePoint = S.DeepCopy(Bundle(db))
    Check(AwaitMutation(catalog, catalog.Put(S.LocalBuild("genB", 3))),
        "the MAX-1 -> MAX commit was refused")
    Check(catalog.Put(S.LocalBuild("genC", 4)) == false,
        "an increment past the maximum succeeded")
    Check(S.Root().state == "AUTHORITY_GENERATION_EXHAUSTED",
        "the exhausted state was not latched")

    -- ABA: an outside writer restores the exact earlier durable bytes.
    rawset(db, "authorityBundle", restorePoint)

    Check(S.Root().state == "AUTHORITY_GENERATION_EXHAUSTED",
        "restoring old durable bytes cleared the latched exhausted state, got "
            .. tostring(S.Root().state))
    Check(catalog.Get("genA") == nil,
        "byte equality restored authority after exhaustion")
    Check(catalog.Put(S.LocalBuild("genE", 6)) == false,
        "byte equality restored mutation authority after exhaustion")
end)

-- Wave 2 MASTER-W1-005 expected-red matrix. Setup uses Lua's debug library only
-- to place otherwise unreachable session counters at their exact boundary. Each
-- observed operation still runs through its real public production seam.
Case("GEN-06", "cursor counter refuses before increment at MAX", function()
    local _, catalog, state = Fresh()
    state.cursorSequence = MAX
    local token, why = catalog.BeginRecordCursor()
    Check(token == nil and why == "GENERATION_EXHAUSTED",
        "cursor creation at MAX was not refused before increment")
    Check(state.cursorSequence == MAX
            and S.Root().state == "AUTHORITY_GENERATION_EXHAUSTED",
        "cursor exhaustion changed the counter or failed to latch")
end)

Case("GEN-07", "binding counter refuses before increment at MAX", function()
    local db, catalog, state = Fresh()
    state.bindingGeneration = MAX
    local result = catalog.BeginRootAdmission(db, Nexus.BundledBuilds)
    Check(type(result) == "table" and result.reason == "GENERATION_EXHAUSTED",
        "root admission incremented a binding counter at MAX")
    Check(state.bindingGeneration == MAX
            and S.Root().state == "AUTHORITY_GENERATION_EXHAUSTED",
        "binding exhaustion changed the counter or failed to latch")
end)

Case("GEN-08", "reservation counter refuses before increment at MAX", function()
    local _, catalog, state = Fresh()
    state.reservationEpoch = MAX
    local claim, why = catalog.BeginAllocationClaim("genVacant")
    Check(claim == nil and why == "GENERATION_EXHAUSTED",
        "claim issuance incremented a reservation counter at MAX")
    Check(state.reservationEpoch == MAX
            and S.Root().state == "AUTHORITY_GENERATION_EXHAUSTED",
        "reservation exhaustion changed the counter or failed to latch")
end)

Case("GEN-09", "receipt counter refuses before tombstone creation at MAX", function()
    local _, catalog, state = Fresh()
    state.receiptRevision = MAX
    local ok, why = catalog.SetTombstone("genSession", {
        stamp=now, author="Boganic", ownerKey="boganic@ebonhold",
        ownerVerified=true,
    }, {source="local"})
    Check(ok == false and why == "GENERATION_EXHAUSTED",
        "tombstone creation incremented a receipt counter at MAX")
    Check(state.receiptRevision == MAX
            and S.Root().state == "AUTHORITY_GENERATION_EXHAUSTED",
        "receipt exhaustion changed the counter or failed to latch")
end)

Case("GEN-10", "all revision epochs refuse before their MAX increment", function()
    local counters = {"recordEpoch", "exactEpoch", "exactRevisionClock"}
    for _, counter in ipairs(counters) do
        local _, catalog, state = Fresh()
        state[counter] = MAX
        local ok, why
        if counter == "recordEpoch" or counter == "exactEpoch" then
            ok, why = catalog.PublishDeferred(1, "counter boundary")
        else
            ok, why = catalog.Put(S.LocalBuild("genSession", 3,
                {lastModified=3}), {source="local"})
        end
        Check(ok == false and why == "GENERATION_EXHAUSTED",
            counter .. " increment at MAX was not refused")
        Check(state[counter] == MAX
                and S.Root().state == "AUTHORITY_GENERATION_EXHAUSTED",
            counter .. " exhaustion changed the counter or failed to latch")
    end
end)

Case("GEN-11", "per-record revision refuses before increment at MAX", function()
    local _, catalog, state = Fresh()
    state.recordRevisions.genSession = MAX
    local ok, why = catalog.Put(S.LocalBuild("genSession", 3,
        {lastModified=3}), {source="local"})
    Check(ok == false and why == "GENERATION_EXHAUSTED",
        "per-record revision incremented past MAX")
    Check(state.recordRevisions.genSession == MAX
            and S.Root().state == "AUTHORITY_GENERATION_EXHAUSTED",
        "per-record exhaustion changed the counter or failed to latch")
end)

Case("GEN-12", "multi-item commit preflights its complete increment count", function()
    local db, catalog, state = Fresh({
        genBatchA=S.LocalBuild("genBatchA", 2),
        genBatchB=S.LocalBuild("genBatchB", 3),
    })
    state.generation = MAX - 1
    state.committedMutationRevision = MAX - 1
    state.semanticGeneration = MAX - 1
    state.exactRevisionClock = MAX - 1
    state.recordRevisions.genBatchA = MAX - 1
    state.recordRevisions.genBatchB = MAX - 1
    local handle = catalog.BeginCatalogMaintenance({database=db,
        operation="compaction"})
    Check(handle, "multi-item maintenance handle unavailable")
    Check(catalog.MaintenanceReplaceRow(handle, "genBatchA",
        S.LocalBuild("genBatchA", 4, {lastModified=4})),
        "first batch replacement would not stage")
    Check(catalog.MaintenanceReplaceRow(handle, "genBatchB",
        S.LocalBuild("genBatchB", 5, {lastModified=5})),
        "second batch replacement would not stage")
    local ok, why = catalog.CommitMaintenance(handle)
    Check(ok == false and why == "GENERATION_EXHAUSTED",
        "two-item MAX-1 batch was not refused before its first increment")
    Check(state.generation == MAX - 1
            and state.committedMutationRevision == MAX - 1
            and state.semanticGeneration == MAX - 1
            and state.exactRevisionClock == MAX - 1,
        "refused multi-item batch changed a shared counter")
    Check(S.Root().state == "AUTHORITY_GENERATION_EXHAUSTED",
        "multi-item exhaustion did not latch the deny-only state")
end)

Case("GEN-13", "exhaustion settles a retained pending mutation once", function()
    local rows = {}
    for index = 1, 9 do
        local id = "genPending" .. tostring(index)
        rows[id] = S.LocalBuild(id, 1)
    end
    local db, catalog, state = Fresh(rows)
    local bundle = Bundle(db)
    local ok, why, ticket = catalog.Put(S.LocalBuild("genPending1", 2), {source="local"})
    Check(ok == nil and why == "ROOT_MUTATION_PENDING", "fixture did not open a pending mutation")
    local callbacks = 0
    Check(catalog.BindMutationCompletion(ticket, function(outcome)
        callbacks = callbacks + 1
        Check(outcome == ticket and outcome.committed == false,
            "exhaustion callback changed the retained ticket or claimed a commit")
    end), "pending mutation refused its callback")
    state.cursorSequence = MAX
    catalog.BeginRecordCursor()
    Check(ticket.state == "failed" and ticket.reason == "GENERATION_EXHAUSTED"
            and callbacks == 1 and Bundle(db) == bundle,
        "exhaustion abandoned the pending ticket or changed the durable bundle")
    catalog.PumpRootAdmission()
    Check(callbacks == 1, "exhaustion repeated the terminal callback")
end)

-- Wave 3 MASTER-W2-009. Receipt revisions belong to the complete transaction
-- plan. Staging, cancellation, drift, and refusal allocate no receipt prefix.
Case("GEN-14", "maintenance receipt ranges allocate only at terminal publication", function()
    local db, catalog, state = Fresh({
        genReceiptA=S.LocalBuild("genReceiptA", 2),
        genReceiptB=S.LocalBuild("genReceiptB", 3),
    })
    local bundle, bytes = Bundle(db), S.Encode(Bundle(db))
    state.receiptRevision = MAX - 1
    local handle = assert(catalog.BeginCatalogMaintenance({database=db,
        operation="retention"}))
    Check(catalog.MaintenanceEvictOverlay(handle, "genReceiptA"),
        "first receipt operation would not stage")
    Check(catalog.MaintenanceEvictOverlay(handle, "genReceiptB"),
        "second receipt operation consumed a receipt before complete preflight")
    Check(state.receiptRevision == MAX - 1,
        "receipt authority advanced while the transaction was only staged")
    local ok, why = catalog.CommitMaintenance(handle)
    Check(ok == false and why == "GENERATION_EXHAUSTED",
        "complete MAX-1 receipt range was not refused before allocation")
    Check(state.receiptRevision == MAX - 1 and Bundle(db) == bundle
            and S.Encode(Bundle(db)) == bytes,
        "refused receipt range changed its counter, bundle identity, or bytes")

    db, catalog, state = Fresh({
        genCancelA=S.LocalBuild("genCancelA", 2),
        genCancelB=S.LocalBuild("genCancelB", 3),
    })
    state.receiptRevision = 17
    handle = assert(catalog.BeginCatalogMaintenance({database=db,
        operation="retention"}))
    Check(catalog.MaintenanceEvictOverlay(handle, "genCancelA"),
        "cancel receipt operation would not stage")
    Check(state.receiptRevision == 17 and catalog.CancelMaintenance(handle),
        "staging allocated a receipt before cancellation")
    Check(state.receiptRevision == 17,
        "cancellation consumed unpublished receipt authority")

    handle = assert(catalog.BeginCatalogMaintenance({database=db,
        operation="retention"}))
    Check(catalog.MaintenanceEvictOverlay(handle, "genCancelA")
            and catalog.MaintenanceEvictOverlay(handle, "genCancelB"),
        "successful receipt range would not stage")
    local committed, commitWhy, ticket = catalog.CommitMaintenance(handle)
    Check(committed == nil and commitWhy == "ROOT_MUTATION_PENDING"
            and type(ticket) == "table",
        "successful receipt range did not retain one pending transaction")
    Check(state.receiptRevision == 17,
        "pending transaction allocated receipts before publication")
    for _ = 1, catalog.Budget().maximumPumps do
        if ticket.state ~= "pending" then break end
        catalog.PumpRootAdmission()
    end
    Check(ticket.state == "committed" and state.receiptRevision == 19,
        "terminal two-item publication did not allocate its exact receipt range")
end)

local function PrivateUpvalue(callback, expected)
    for index = 1, 64 do
        local name, value = debug.getupvalue(callback, index)
        if name == expected then return value end
        if name == nil then break end
    end
    error("unable to locate module-private " .. tostring(expected), 2)
end

-- Wave 3 MASTER-W2-010. These resettable module-private counters must use the
-- same fail-closed exhaustion guard as the catalog owner. The tests place each
-- exact counter at MAX, then call its real construction/replacement seam.
Case("GEN-15", "StoreData revision refuses before construction at MAX", function()
    Fresh()
    dofile("core/Store.lua")
    local bootstrap = assert(Nexus.MainInternals.AuthorityBootstrap)
    local storeData = PrivateUpvalue(bootstrap.__storeData, "StoreData")
    storeData.revision = MAX
    local current = storeData.current
    local value, why = storeData.Build({settings={},chars={},accountCharacters={}},
        {decision="current"})
    Check(value == nil and why == "GENERATION_EXHAUSTED",
        "StoreData construction advanced an exhausted revision")
    Check(storeData.revision == MAX and storeData.current == current
            and S.Root().state == "AUTHORITY_GENERATION_EXHAUSTED",
        "StoreData exhaustion changed state or failed to latch")
end)

Case("GEN-16", "DPS preparation epoch refuses before root replacement at MAX", function()
    Fresh()
    dofile("core/DpsCapture.lua")
    local owner = assert(Nexus.MainInternals.DpsAuthority)
    local db = {personalBest={old=true},buildBest={old=true},
        characterBest={dummy={},lk={}}}
    local personal, build, character = db.personalBest, db.buildBest,
        db.characterBest
    owner.epoch = MAX
    local value, why = owner.ReplaceRoots(db, {new=true}, {new=true},
        {dummy={},lk={}})
    Check(value == nil and why == "GENERATION_EXHAUSTED",
        "DPS root replacement advanced an exhausted epoch")
    Check(owner.epoch == MAX and db.personalBest == personal
            and db.buildBest == build and db.characterBest == character
            and S.Root().state == "AUTHORITY_GENERATION_EXHAUSTED",
        "DPS exhaustion changed roots or failed to latch")
end)

Case("GEN-17", "Sync operation sequence refuses before receipt creation at MAX", function()
    Fresh()
    dofile("core/SyncProtocol.lua")
    dofile("core/SyncTransport.lua")
    dofile("core/SyncCompatibility.lua")
    dofile("core/SyncReconciler.lua")
    dofile("core/SyncInbound.lua")
    dofile("core/SyncDiagnostics.lua")
    dofile("core/SyncSession.lua")
    dofile("core/Sync.lua")
    local operation = PrivateUpvalue(Nexus.Sync.GetShareStatus, "Operation")
    operation.sequence = MAX
    local value, why = operation.New("share", "gen-sync", "1", nil, true)
    Check(value == nil and why == "GENERATION_EXHAUSTED",
        "Sync operation construction advanced an exhausted sequence")
    Check(operation.sequence == MAX and next(operation.active) == nil
            and S.Root().state == "AUTHORITY_GENERATION_EXHAUSTED",
        "Sync exhaustion registered an operation or failed to latch")
end)

S.Finish("catalog authority generation exhaustion")
