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

local now = 2000000000
time = function() return now end
UnitClass = function() return "Mage", "MAGE" end

local MAX = 9007199254740991

local function Catalog() return Nexus.BuildCatalog end
local function Bundle(db) return rawget(db, "authorityBundle") end

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
    Check(catalog.Put(S.LocalBuild("genB", 3)), "the MAX-1 -> MAX commit was refused")
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
    Check(catalog.Put(S.LocalBuild("genB", 3)), "the MAX-1 -> MAX commit was refused")
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
    Check(catalog.Put(S.LocalBuild("genB", 3)), "the MAX-1 -> MAX commit was refused")
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

S.Finish("catalog authority generation exhaustion")
