-- Package B / issue #22 Repair Wave 1: the protected commit primitive must publish
-- one complete detached replacement through one bundle and serving swap.
--
-- Covers MASTER-RC-002 (a later maintenance-operation failure leaves earlier
-- operations durable and public; live rows mutated inside the protected section)
-- and MASTER-RC-005 (evidence interned into the live pool before the catalog
-- transaction commits).
--
-- MASTER-RC-002 also requires that no production callback runs inside the protected
-- publication section, so these cases do not use the production fault injector.
--
-- Measured on the rejected candidate e69497d: a mid-transaction raw-write fault
-- cannot be induced through ordinary durable state alone. A malformed map present
-- at bind time is refused with ROOT_MAP_MALFORMED, and the same occupant introduced
-- after BeginCatalogMaintenance is caught by the token drift guard before the first
-- write. The multi-operation partial-commit path therefore reaches only the serving
-- root here; MASTER's own reproduction of the durable partial commit used the
-- fault seam that this root requires removing, and is preserved as a synthetic
-- fault-injection characterization of the rejected candidate rather than proof
-- that ordinary malformed durable state reaches the same failure point.
--
-- Evidence chronology for ATOM-02 (not a silent relabel):
--   Original probe on e69497d, pre-repair: a first-handoff note called ATOM-02
--   RED. The probe that actually ran was a two-operation candidate whose second
--   map occupant is a non-table. That is refused at admission/token-drift
--   *before any raw write*. Observed result: no durable byte change. That is a
--   precommit guard, not a mid-commit rollback.
--   Later probe (this file): same occupant still refuses before writes; the
--   case is classified GUARD. ATOM-03/ATOM-04 remain the RED-on-e69497d
--   publication-callback and in-place-row-rewrite proofs.
--   DriftDurableMap / non-table occupants do not prove rollback after an
--   earlier durable write. The postcommit Revisions.Advance probe is a
--   different boundary. After this repair, fallible map-shape checks run
--   off-state; the protected section is callback-free rawset + index install +
--   one serving swap. An unexpected Lua error restores every durable key
--   (collection identity preserved) and fail-closes serving.
--
-- Legacy-to-bundle cutover reclassification (MASTER-RC-001, architecture 3b5de54f
-- state machine lines 394 and 4849; not a silent relabel):
--   The exact PR #68 locations are no longer durable storage, no longer
--   admission input, and no longer serving witnesses, so an incompatible
--   occupant placed in `communityRetentionEvictions` is now correctly inert.
--   The fault surface therefore moves to the one durable payload location that
--   remains: a bundle payload field, hostile-occupied by the fixture through
--   `S.PoisonDurableField` and always restored.
--   The refusal boundary these cases now reach is the serving-witness drift
--   guard, because a foreign replacement of a bundle payload field is exactly
--   what that guard exists to catch. The map-shape refusal survives only at
--   admission (ROOT_MAP_MALFORMED), which ATOM-02 exercises on recovery.
--   This is a strengthening, not a weakening: the claim originally under test
--   was that an earlier operation of a failed multi-operation transaction stays
--   durable. After the cutover a transaction performs exactly one durable
--   payload write, so no prefix of a candidate is representable at all, and
--   ATOM-08 proves that directly.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Codec.lua")
local S = dofile("tests/catalog_authority_support.lua")
local Case, Check = S.Case, S.Check

local DAY = 24 * 60 * 60
local now = 2000000000
time = function() return now end
UnitClass = function() return "Mage", "MAGE" end

local function Catalog() return Nexus.BuildCatalog end
local function LocalTomb(stamp)
    return {stamp=stamp or now, author="Boganic", ownerKey="boganic@ebonhold",
        ownerVerified=true}
end

-- A maintenance candidate with two operations whose second raw write cannot
-- succeed. The first operation must never become durable or public on its own.
local function TwoOperationCandidate()
    local db = S.Database({
        atomKeep=S.LocalBuild("atomKeep", 2),
        atomEvict=S.LocalBuild("atomEvict", 3),
    })
    S.Bind(db)
    local catalog = Catalog()
    Check(catalog.SetTombstone("atomKeep", LocalTomb(), {source="local"}),
        "tombstone fixture refused")
    now = now + 180 * DAY + 1
    local handle = catalog.BeginCatalogMaintenance({database=db,
        operation="retention"})
    Check(handle, "maintenance handle unavailable")
    Check(catalog.MaintenanceRetireTombstone(handle, "atomKeep"),
        "expired tombstone would not stage for retirement")
    Check(catalog.MaintenanceEvictOverlay(handle, "atomEvict"),
        "overlay would not stage for eviction")
    -- The eviction's barrier write targets this payload field. A foreign
    -- occupant in the durable bundle is refused before any durable write.
    local restore = S.PoisonDurableField(db, "communityRetentionEvictions",
        "occupied-by-an-incompatible-value")
    return db, catalog, handle, restore
end

Case("ATOM-01",
    "GUARD: a failed multi-operation transaction leaves no durable byte changed",
function()
    local db, catalog, handle, restore = TwoOperationCandidate()
    -- Not vacuous: both operations staged before the fault was introduced, so this
    -- exercises a genuine two-operation candidate.
    Check(S.Durable(db, "syncTombstones").atomKeep ~= nil
        and S.Durable(db).atomEvict ~= nil,
        "fixture did not stage two durable targets")
    local before = S.Encode(db)
    local generationBefore = catalog.RecordRevision("atomEvict")
    local bundleBefore = rawget(db, "authorityBundle")

    local ok, why = catalog.CommitMaintenance(handle)

    Check(ok == false, "a candidate with an impossible write reported success")
    Check(S.Encode(db) == before,
        "partial commit: the transaction failed but durable bytes changed ("
            .. tostring(why) .. ")")
    Check(rawget(db, "authorityBundle") == bundleBefore,
        "a failed transaction replaced the durable bundle pointer")
    Check(S.Durable(db, "syncTombstones").atomKeep ~= nil,
        "the earlier retirement became durable although the transaction failed")
    Check(S.Durable(db).atomEvict ~= nil,
        "the eviction target was removed although the transaction failed")
    Check(catalog.RecordRevision("atomEvict") == generationBefore,
        "a failed transaction advanced a published revision")
    restore()
end)

Case("ATOM-02",
    "GUARD: a precommit refusal leaves durable bytes and applies no operation",
function()
    local db, catalog, handle, restore = TwoOperationCandidate()
    local before = S.Encode(db)

    Check(catalog.CommitMaintenance(handle) == false,
        "a candidate with an impossible write reported success")

    -- Fail closed: the root refuses service rather than serving a partial
    -- application. Reads must not expose an intermediate state.
    Check(S.Root().state == "ROOT_INVALIDATED",
        "a refused transaction did not publish the invalid sentinel")
    Check(catalog.Get("atomEvict") == nil and catalog.Count() == 0,
        "the invalid sentinel served rows from a refused transaction")
    Check(S.Encode(db) == before,
        "a refused transaction changed durable bytes")

    -- Recovery readmits the complete unchanged durable state: neither staged
    -- operation was applied. The harness occupant is withdrawn first, because a
    -- non-table durable map is correctly refused at admission.
    restore()
    S.Bind(db)
    Check(Catalog().Get("atomEvict") ~= nil,
        "the eviction target was lost although the transaction was refused")
    Check(S.Durable(db, "syncTombstones").atomKeep ~= nil,
        "the retirement target was lost although the transaction was refused")

    -- The map-shape refusal itself survives at admission, which is the only
    -- boundary that can still observe a malformed selected payload map.
    local shapeRestore = S.PoisonDurableField(db, "communityRetentionEvictions",
        "occupied-by-an-incompatible-value")
    S.Bind(db)
    Check(S.Root().state ~= "ROOT_ADMITTED",
        "a malformed selected payload map was admitted")
    shapeRestore()
    S.Bind(db)
    Check(S.Root().state == "ROOT_ADMITTED",
        "withdrawing the malformed occupant did not restore admission")
end)

Case("ATOM-03", "RED: the protected section runs no production callback", function()
    local db = S.Database({atomCb=S.LocalBuild("atomCb", 2)})
    S.Bind(db)
    local catalog = Catalog()
    Check(type(catalog.InstallFaultInjector) ~= "function",
        "a test-only fault injector is exported on the production authority; the "
            .. "protected publication section must invoke no production callback")
end)

Case("ATOM-04",
    "RED: a published snapshot is immutable once served",
function()
    -- The accepted architecture requires that all public authority use the
    -- detached canonical snapshot rather than the mutable raw row. That is the
    -- invariant available today. Replacement of the durable payload itself moves
    -- to authorityDatabase.authorityBundle with MASTER-RC-001; until that slot
    -- exists, communityBuilds remains the legacy compatibility mirror that
    -- existing consumers hold references into.
    local db = S.Database({atomRow=S.LocalBuild("atomRow", 2)})
    S.Bind(db)
    local catalog = Catalog()
    local servedBefore = catalog.Get("atomRow")
    local servedBytes = S.Encode(servedBefore)

    local replacement = S.LocalBuild("atomRow", 4, {title="Replacement"})
    Check(catalog.Put(replacement, {source="local"}), "replacement refused")

    Check(S.Encode(servedBefore) == servedBytes,
        "a previously served snapshot was mutated by a later publication")
    Check(catalog.Get("atomRow") ~= servedBefore,
        "the serving root returned the same snapshot object after a replacement")
    Check(catalog.Get("atomRow").title == "Replacement",
        "the replacement was not served after publication")
end)

Case("ATOM-05",
    "GUARD: a failed compaction leaves no interned evidence durable",
function()
    local db = S.Database({
        evKeep=S.LocalBuild("evKeep", 2),
        evReplace=S.LocalBuild("evReplace", 3),
    })
    S.Bind(db)
    local catalog = Catalog()
    Check(catalog.SetTombstone("evKeep", LocalTomb(), {source="local"}),
        "tombstone fixture refused")
    now = now + 180 * DAY + 1
    local handle = catalog.BeginCatalogMaintenance({database=db,
        operation="compaction"})
    Check(handle, "maintenance handle unavailable")
    Check(catalog.MaintenanceReplaceRow(handle, "evReplace",
        S.LocalBuild("evReplace", 5, {title="Compacted"})),
        "compaction replacement would not stage")
    Check(catalog.MaintenanceRetireTombstone(handle, "evKeep"),
        "expired tombstone would not stage for retirement")
    local restore = S.PoisonDurableField(db, "communityRetentionEvictions",
        "occupied-by-an-incompatible-value")
    local before = S.Encode(db)

    local ok = catalog.CommitMaintenance(handle)

    Check(ok == false, "a candidate with an impossible write reported success")
    Check(S.Encode(db) == before,
        "a failed compaction left interned evidence or a replaced row durable")
    restore()
end)

-- MASTER-RC-005: "Evidence is interned into the live durable pool before the
-- catalog transaction commits." Reproduction from the MASTER packet: "Fault
-- before the row commit after compaction preparation. Catalog bytes stay
-- unchanged but evidence entries increase."
--
-- Architecture at 3b5de54f: "`core/DataCompaction.lua`: 32-unit shadow work,
-- readmission, and complete-bundle candidate publication; it has no direct
-- durable metadata or nested authority write." "`EvidenceCoordinator` builds only
-- evidence fields. They never write SavedVariables."
--
-- ATOM-05 above is a guard: its fixture drifts the durable maps that the drift
-- check reads, and it compares whole-database bytes after the occupant is
-- already in place. These two cases measure the evidence pool itself, which is
-- where the preparation-time write lands.
local function EvidencePool(db)
    local store = rawget(db, "loadoutEvidence")
    return type(store) == "table" and type(store.entries) == "table"
        and store.entries or {}
end

Case("ATOM-06",
    "RED: a refused transaction interns no evidence into the durable pool",
function()
    local db = S.Database({
        evPrep=S.LocalBuild("evPrep", 3),
        evOther=S.LocalBuild("evOther", 2),
    })
    S.Bind(db)
    local catalog = Catalog()
    local handle = catalog.BeginCatalogMaintenance({database=db,
        operation="compaction"})
    Check(handle, "maintenance handle unavailable")
    -- A replacement row carrying evidence the pool has never seen.
    Check(catalog.MaintenanceReplaceRow(handle, "evPrep",
        S.LocalBuild("evPrep", 7, {title="Compacted", firstSpell=770000})),
        "compaction replacement would not stage")
    Check(catalog.MaintenanceEvictOverlay(handle, "evOther"),
        "overlay would not stage for eviction")

    -- The fault is introduced after both operations staged and before the
    -- commit, exactly as MASTER's reproduction describes.
    local restore = S.PoisonDurableField(db, "communityRetentionEvictions",
        "occupied-by-an-incompatible-value")
    local catalogBytes = S.Encode(S.Durable(db))
    local poolBytes = S.Encode(EvidencePool(db))
    local poolCount = S.Count(EvidencePool(db))

    local ok = catalog.CommitMaintenance(handle)

    restore()
    Check(ok == false, "a candidate with an impossible write reported success")
    Check(S.Encode(S.Durable(db)) == catalogBytes,
        "the refused transaction changed durable catalog bytes")
    Check(S.Count(EvidencePool(db)) == poolCount,
        "the refused transaction interned " ..
            tostring(S.Count(EvidencePool(db)) - poolCount)
            .. " evidence entries into the live durable pool during preparation")
    Check(S.Encode(EvidencePool(db)) == poolBytes,
        "the refused transaction changed durable evidence bytes")
end)

Case("ATOM-07",
    "RED: a successful transaction publishes evidence inside the same bundle",
function()
    local db = S.Database({evAtomic=S.LocalBuild("evAtomic", 3)})
    S.Bind(db)
    local catalog = Catalog()
    local bundleBefore = rawget(db, "authorityBundle")
    Check(type(bundleBefore) == "table",
        "no durable authority payload slot: MASTER-RC-001 kernel is absent, so "
            .. "evidence cannot be published atomically with the catalog root")
    local evidenceBefore = rawget(bundleBefore, "loadoutEvidence")
    local evidenceBytes = S.Encode(evidenceBefore)

    Check(catalog.Put(S.LocalBuild("evAtomic", 9,
        {title="Atomic", firstSpell=880000})), "publication refused")

    local bundleAfter = rawget(db, "authorityBundle")
    Check(bundleAfter ~= bundleBefore,
        "the publication did not replace the complete bundle pointer")
    Check(rawget(bundleAfter, "loadoutEvidence") ~= evidenceBefore,
        "the evidence store was mutated in the live pool instead of being "
            .. "published as a detached candidate inside the replacement bundle")
    Check(S.Encode(evidenceBefore) == evidenceBytes,
        "the superseded bundle's evidence store was mutated in place")
    Check(S.Count(rawget(bundleAfter, "loadoutEvidence").entries)
        > S.Count(evidenceBefore.entries or {}),
        "the replacement bundle carries no newly interned evidence")
end)

Case("ATOM-08",
    "one durable payload write per transaction: no candidate prefix exists",
function()
    -- The acceptance requirement of MASTER-RC-002 after the cutover: a
    -- multi-operation transaction replaces one complete bundle pointer once, so
    -- no prefix of the candidate is representable in durable state and the
    -- superseded graph stays byte-exact.
    local db = S.Database({
        atomOne=S.LocalBuild("atomOne", 2),
        atomTwo=S.LocalBuild("atomTwo", 3),
    })
    S.Bind(db)
    local catalog = Catalog()
    Check(catalog.SetTombstone("atomOne", LocalTomb(), {source="local"}),
        "tombstone fixture refused")
    now = now + 180 * DAY + 1
    local handle = catalog.BeginCatalogMaintenance({database=db,
        operation="retention"})
    Check(handle, "maintenance handle unavailable")
    Check(catalog.MaintenanceRetireTombstone(handle, "atomOne"),
        "expired tombstone would not stage for retirement")
    Check(catalog.MaintenanceEvictOverlay(handle, "atomTwo"),
        "overlay would not stage for eviction")

    local bundleBefore = rawget(db, "authorityBundle")
    local generationBefore = bundleBefore.transactionGeneration
    local supersededBytes = S.Encode(bundleBefore)
    local legacyBytes = S.Encode(rawget(db, "communityBuilds"))

    Check(catalog.CommitMaintenance(handle) ~= false,
        "the two-operation maintenance transaction was refused")

    local bundleAfter = rawget(db, "authorityBundle")
    Check(bundleAfter ~= bundleBefore,
        "the transaction did not replace the complete bundle pointer")
    Check(bundleAfter.transactionGeneration == generationBefore + 1,
        "one complete bundle replacement did not advance the generation once")
    Check(S.Encode(bundleBefore) == supersededBytes,
        "the superseded bundle graph was mutated by its own replacement")
    Check(S.Durable(db, "syncTombstones").atomOne == nil
        and S.Durable(db).atomTwo == nil,
        "both staged operations did not become durable together")
    Check(S.Encode(rawget(db, "communityBuilds")) == legacyBytes,
        "the transaction wrote a legacy payload location")
end)

S.Finish("catalog authority commit fault matrix")
