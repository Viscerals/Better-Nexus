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
local function CatalogState()
    for index = 1, 64 do
        local name, value = debug.getupvalue(Catalog().RootState, index)
        if name == "ST" then return value end
        if name == nil then break end
    end
    error("unable to locate module-private catalog state", 2)
end
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

    local ok, why, ticket = catalog.Put(S.LocalBuild("evAtomic", 9,
        {title="Atomic", firstSpell=880000}))
    if ok == nil and why == "ROOT_MUTATION_PENDING" and ticket then
        for _ = 1, catalog.Budget().maximumPumps do
            catalog.PumpRootAdmission()
            if ticket.state ~= "pending" then break end
        end
        ok = ticket.state == "committed" and ticket.committed == true
    end
    Check(ok, "publication refused")

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

-- Wave 2 MASTER-W1-003 expected red. A source-drift refusal may replace the
-- public pointer with the invalid sentinel, but the retained superseded serving
-- graph itself must stay byte- and identity-exact.
Case("ATOM-09",
    "failed maintenance preparation preserves the exact retained serving graph",
function()
    local db = S.Database({
        atomRetire=S.LocalBuild("atomRetire", 2),
        atomBarrier=S.LocalBuild("atomBarrier", 3),
    })
    S.Bind(db)
    local catalog = Catalog()
    Check(catalog.SetTombstone("atomRetire", LocalTomb(), {source="local"}),
        "retirement tombstone fixture refused")
    local evict = catalog.BeginCatalogMaintenance({database=db,
        operation="retention"})
    Check(evict and catalog.MaintenanceEvictOverlay(evict, "atomBarrier"),
        "barrier fixture would not stage")
    Check(catalog.CommitMaintenance(evict), "barrier fixture would not commit")

    now = now + 180 * DAY + 1
    local handle = catalog.BeginCatalogMaintenance({database=db,
        operation="retention"})
    Check(handle and catalog.MaintenanceRetireTombstone(handle, "atomRetire"),
        "expired tombstone would not stage")
    Check(catalog.MaintenanceExpireBarrier(handle, "atomBarrier"),
        "expired barrier would not stage")

    local state = CatalogState()
    local servingBefore = state.currentServingRoot
    local rootBefore = servingBefore.catalogRoot
    local retireKey = assert(Nexus.Identity.TypedKey("atomRetire", 256))
    local barrierKey = assert(Nexus.Identity.TypedKey("atomBarrier", 256))
    local retireSlot = rootBefore.slots[retireKey]
    local retireVerdict = rootBefore.rows[retireKey]
    local barrierSlot = rootBefore.slots[barrierKey]
    local barrierVerdict = rootBefore.rows[barrierKey]
    local tombstoneObject = retireSlot.tombstone
    local barrierObject = barrierSlot.barrier
    local barrierVerdictObject = barrierVerdict.barrier
    local rowsBefore, slotsBefore = rootBefore.rows, rootBefore.slots
    local indexBefore, countsBefore = rootBefore.index, rootBefore.counts
    local vectorBefore = rootBefore.slotVector
    local rootBytes = S.Encode({
        retireSlot=retireSlot, retireVerdict=retireVerdict,
        barrierSlot=barrierSlot, barrierVerdict=barrierVerdict,
    })

    local restore = S.PoisonDurableField(db, "communityRetentionEvictions",
        "occupied-by-an-incompatible-value")
    local ok = catalog.CommitMaintenance(handle)
    restore()

    Check(ok == false, "source-drift candidate unexpectedly committed")
    Check(rawequal(rootBefore.rows, rowsBefore)
            and rawequal(rootBefore.slots, slotsBefore)
            and rawequal(rootBefore.index, indexBefore)
            and rawequal(rootBefore.counts, countsBefore)
            and rawequal(rootBefore.slotVector, vectorBefore),
        "failed preparation replaced a retained root container")
    Check(rawequal(rootBefore.slots[retireKey], retireSlot)
            and rawequal(rootBefore.rows[retireKey], retireVerdict)
            and rawequal(rootBefore.slots[barrierKey], barrierSlot)
            and rawequal(rootBefore.rows[barrierKey], barrierVerdict),
        "failed preparation replaced a retained slot or verdict identity")
    Check(rawequal(retireSlot.tombstone, tombstoneObject)
            and rawequal(barrierSlot.barrier, barrierObject)
            and rawequal(barrierVerdict.barrier, barrierVerdictObject),
        "failed preparation changed retained tombstone or barrier identity")
    Check(S.Encode({
            retireSlot=retireSlot, retireVerdict=retireVerdict,
            barrierSlot=barrierSlot, barrierVerdict=barrierVerdict,
        }) == rootBytes,
        "failed preparation changed retained serving bytes")
end)

Case("ATOM-10", "cancelled, superseded, and invalidated candidates settle once", function()
    for _, action in ipairs({"cancel", "supersede", "invalidate"}) do
        S.Reload()
        local rows = {}
        for index = 1, 9 do
            local id = "pendingFault" .. tostring(index)
            rows[id] = S.LocalBuild(id, 1)
        end
        local db = S.Database(rows)
        S.Bind(db)
        local catalog = Catalog()
        local bundle = rawget(db, "authorityBundle")
        local bytes = S.Encode(bundle)
        local ok, why, ticket = catalog.Put(S.LocalBuild("pendingFault1", 2), {source="local"})
        Check(ok == nil and why == "ROOT_MUTATION_PENDING", "fixture did not open a pending mutation")
        local callbacks = 0
        catalog.BindMutationCompletion(ticket, function(outcome)
            callbacks = callbacks + 1
            Check(outcome == ticket and outcome.committed == false,
                "abandoned mutation callback claimed a commit")
        end)
        if action == "cancel" then catalog.CancelRootAdmission()
        elseif action == "supersede" then catalog.BeginRootAdmission(db, Nexus.BundledBuilds)
        else
            local restore = S.PoisonDurableField(db, "communityBuilds", {})
            catalog.Get("pendingFault1")
            restore()
        end
        Check(ticket.state == "failed" and ticket.committed == false and callbacks == 1,
            action .. " abandoned the pending owner without a terminal receipt")
        Check(rawget(db, "authorityBundle") == bundle and S.Encode(bundle) == bytes,
            action .. " changed the retained durable bundle")
    end
end)

Case("ATOM-11", "pending publication faults settle once and fail closed", function()
    for _, afterWrite in ipairs({false, true}) do
        S.Reload()
        local rows = {}
        for index = 1, 9 do
            local id = "publishFault" .. tostring(index)
            rows[id] = S.LocalBuild(id, 1)
        end
        local db = S.Database(rows)
        S.Bind(db)
        local catalog = Catalog()
        local before = rawget(db, "authorityBundle")
        local beforeBytes = S.Encode(before)
        local ok, why, ticket = catalog.Put(
            S.LocalBuild("publishFault1", 2), {source="local"})
        Check(ok == nil and why == "ROOT_MUTATION_PENDING" and ticket,
            "publication fixture did not retain a pending ticket")
        local completions = 0
        catalog.BindMutationCompletion(ticket, function()
            completions = completions + 1
        end)
        local originalRawset, injected = rawset, false
        _G.rawset = function(target, key, value)
            if target == db and key == "authorityBundle" then
                injected = true
                if afterWrite then originalRawset(target, key, value) end
                error("test pending publication fault", 0)
            end
            return originalRawset(target, key, value)
        end
        local pumpOk, pumpError = pcall(function()
            for _ = 1, catalog.Budget().maximumPumps do
                catalog.PumpRootAdmission()
                if ticket.state ~= "pending" then break end
            end
        end)
        _G.rawset = originalRawset
        Check(injected, "fixture never reached the durable publication")
        Check(pumpOk, "publication error escaped: " .. tostring(pumpError))
        Check(ticket.state == "failed" and ticket.committed == false
                and completions == 1,
            "publication fault did not settle its owner once")
        Check(catalog.RootState().state == "ROOT_INVALIDATED"
                and catalog.Get("publishFault1") == nil,
            "publication fault left serving authority live")
        Check(S.Encode(before) == beforeBytes,
            "publication fault changed the retained old bundle")
        local selected = rawget(db, "authorityBundle")
        Check(afterWrite and selected ~= before or not afterWrite and selected == before,
            "publication fault restored or replaced the selected bundle")
        if afterWrite then
            Check(selected.transactionGeneration == before.transactionGeneration + 1
                    and selected.communityBuilds.publishFault1 ~= nil
                    and selected.communityBuilds.publishFault9 ~= nil,
                "publication fault left an incomplete new bundle")
        end
        catalog.PumpRootAdmission()
        Check(completions == 1, "publication failure callback repeated")
    end
end)

Case("ATOM-12", "notification rebind cannot replace the completed mutation ticket", function()
    S.Reload()
    local rows = {}
    for index = 1, 9 do
        local id = "reentrant" .. index
        rows[id] = S.LocalBuild(id, 1)
    end
    local db = S.Database(rows)
    S.Bind(db)
    local catalog = Catalog()
    local before = rawget(db, "authorityBundle")
    local ok, why, ticket = catalog.Put(S.LocalBuild("reentrant1", 2), {source="local"})
    Check(ok == nil and why == "ROOT_MUTATION_PENDING", "reentrant fixture did not pend")
    local callbacks, completedDatabase, completedBundle = 0, nil, nil
    catalog.BindMutationCompletion(ticket, function(result)
        callbacks = callbacks + 1
        completedDatabase, completedBundle = result.database, result.bundle
    end)
    local replacement = S.Database({nextRoot=S.LocalBuild("nextRoot", 3)})
    local advance, triggered = Nexus.Revisions.Advance, false
    Nexus.Revisions.Advance = function(event, payload)
        if event == Nexus.Revisions.BUILD_LIBRARY_CHANGED and not triggered then
            triggered = true
            NexusDB = replacement
            catalog.BeginRootAdmission(replacement, S.Bundle())
        end
        return advance(event, payload)
    end
    local pumpOk, pumpError = pcall(function()
        for _ = 1, catalog.Budget().maximumPumps do
            catalog.PumpRootAdmission()
            if ticket.state ~= "pending" then break end
        end
    end)
    Nexus.Revisions.Advance = advance
    Check(pumpOk, tostring(pumpError))
    Check(triggered and rawget(db, "authorityBundle") ~= before,
        "notification did not rebind after durable publication")
    Check(ticket.state == "committed" and ticket.committed == true and callbacks == 1
            and completedDatabase == db and completedBundle == rawget(db, "authorityBundle"),
        "notification rebind changed the old commit's terminal receipt")
    Check(catalog.RootState().candidate == true,
        "old completion consumed the newly started admission candidate")
    local result
    for _ = 1, catalog.Budget().maximumPumps do
        result = catalog.PumpRootAdmission()
        if result.state ~= "pending" then break end
    end
    Check(result.state == "ROOT_ADMITTED" and catalog.Get("nextRoot") ~= nil,
        "replacement admission did not complete independently")
end)

Case("ATOM-13", "evidence publication faults settle once before and after release", function()
    for _, afterRelease in ipairs({false,true}) do
        S.Reload()
        local rows={}
        for index=1,9 do local id="evidenceFault"..index; rows[id]=S.LocalBuild(id,1) end
        local db=S.Database(rows); S.Bind(db); local catalog=Catalog()
        local before=rawget(db,"authorityBundle"); local bytes=S.Encode(before)
        local ok,why,ticket=catalog.Put(S.LocalBuild("evidenceFault1",2),{source="local"})
        Check(ok==nil and why=="ROOT_MUTATION_PENDING" and ticket,"fixture did not pend")
        local callbacks=0
        catalog.BindMutationCompletion(ticket,function() callbacks=callbacks+1 end)
        local original=Nexus.LoadoutEvidence.PublishCandidate; local injected=false
        Nexus.LoadoutEvidence.PublishCandidate=function()
            injected=true
            if afterRelease then original() end
            error("test evidence publication fault",0)
        end
        local pumpOk,pumpError=pcall(function()
            for _=1,catalog.Budget().maximumPumps do
                catalog.PumpRootAdmission(); if ticket.state~="pending" then break end
            end
        end)
        Nexus.LoadoutEvidence.PublishCandidate=original
        Check(injected,"publication hook was not reached")
        Check(pumpOk,"publication error escaped: "..tostring(pumpError))
        Check(ticket.state=="failed" and ticket.committed==false and callbacks==1,
            "publication fault did not settle its owner once")
        Check(catalog.RootState().state=="ROOT_INVALIDATED" and catalog.Get("evidenceFault1")==nil,
            "publication fault left serving authority live")
        Check(S.Encode(before)==bytes,"publication fault changed the retained old bundle")
        local selected=rawget(db,"authorityBundle")
        Check(selected~=before and selected.transactionGeneration==before.transactionGeneration+1
                and selected.communityBuilds.evidenceFault1 and selected.communityBuilds.evidenceFault9,
            "publication fault left an incomplete new bundle")
        Check(not Nexus.LoadoutEvidence.CandidateOpen(),"failed publication retained evidence candidate")
        catalog.PumpRootAdmission(); Check(callbacks==1,"publication failure callback repeated")
    end
end)

Case("ATOM-14", "failure callback rebind cannot consume the replacement candidate", function()
    S.Reload()
    local rows={}
    for index=1,9 do local id="failedRebind"..index; rows[id]=S.LocalBuild(id,1) end
    local db=S.Database(rows); S.Bind(db); local catalog=Catalog()
    local ok,why,ticket=catalog.Put(S.LocalBuild("failedRebind1",2),{source="local"})
    Check(ok==nil and why=="ROOT_MUTATION_PENDING" and ticket,"fixture did not pend")
    local replacement=S.Database({nextRoot=S.LocalBuild("nextRoot",3)})
    local callbacks=0
    catalog.BindMutationCompletion(ticket,function()
        callbacks=callbacks+1
        NexusDB=replacement
        catalog.BeginRootAdmission(replacement,S.Bundle())
    end)
    local original=Nexus.LoadoutEvidence.PublishCandidate; local injected=false
    Nexus.LoadoutEvidence.PublishCandidate=function() injected=true; error("test rebind publication fault",0) end
    local pumpOk,pumpError=pcall(function()
        for _=1,catalog.Budget().maximumPumps do
            catalog.PumpRootAdmission(); if ticket.state~="pending" then break end
        end
    end)
    Nexus.LoadoutEvidence.PublishCandidate=original
    Check(injected and pumpOk,"failure escaped or never injected: "..tostring(pumpError))
    Check(ticket.state=="failed" and callbacks==1,"failed owner receipt was not stable")
    local result
    for _=1,catalog.Budget().maximumPumps do
        result=catalog.PumpRootAdmission()
        if result.state~="pending" then break end
    end
    Check(result.state=="ROOT_ADMITTED" and catalog.Get("nextRoot")~=nil,
        "failed owner consumed its callback's replacement candidate")
    Check(callbacks==1 and ticket.state=="failed","replacement replayed old failure completion")
end)

S.Finish("catalog authority commit fault matrix")
