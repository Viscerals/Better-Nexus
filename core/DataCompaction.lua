-- Nexus: ordered, idempotent SavedVariables exact-evidence compaction.
--
-- Compaction is conservative: an inline array is removed only after the pool
-- round trip is deeply identical to the established public shape. Malformed,
-- conflicting, or merely noncanonical rows keep their inline evidence.

Nexus = Nexus or {}
local Compaction = {}
Nexus.DataCompaction = Compaction

local SCHEMA_VERSION = 1
local MIGRATION_VERSION = 1
local PUMP_KEY = "data-compaction"
local PUMP_INTERVAL = 0.05
local MAX_WORK_PER_PUMP = 32
local active
local garbageJobs = setmetatable({}, {__mode="k"})

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[DeepCopy(key, seen)] = DeepCopy(child, seen)
    end
    return out
end

local function DeepEqual(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    seen = seen or {}
    if seen[left] then return seen[left] == right end
    seen[left] = right
    for key, value in pairs(left) do
        if not DeepEqual(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function Count(source)
    local n = 0
    for _ in pairs(source or {}) do n = n + 1 end
    return n
end

local function Add(stats, key, amount)
    if type(stats) ~= "table" then return end
    stats[key] = (tonumber(stats[key]) or 0) + (amount or 1)
end

local function Evidence()
    return Nexus and Nexus.LoadoutEvidence
end

-- After authority-bundle occupancy, every legacy field is preserved input.
-- The complete bundle is the only selected durable payload.
local function DurablePayload(database, field)
    if type(database) ~= "table" then return nil end
    local bundle = rawget(database, "authorityBundle")
    if type(bundle) == "table" then return rawget(bundle, field) end
    return rawget(database, field)
end

local function AuthorityDatabase(database)
    if type(database) == "table" then return database end
    local catalog = Nexus and Nexus.BuildCatalog
    if catalog and type(catalog.BoundDatabase) == "function" then
        local bound = catalog.BoundDatabase()
        if type(bound) == "table" then return bound end
    end
    return type(NexusDB) == "table" and NexusDB or nil
end

local function CatalogFor(database)
    local catalog = Nexus and Nexus.BuildCatalog
    if not (catalog and type(catalog.BoundDatabase) == "function"
        and catalog.BoundDatabase() == database
        and type(catalog.BeginCatalogMaintenance) == "function") then
        return nil
    end
    return catalog
end

-- The selected durable evidence payload after the accepted legacy-to-bundle
-- cutover. State machine line 394 keeps the exact PR #68 `loadoutEvidence`
-- location "Preserved legacy input when the bundle is absent. Never used as
-- fallback after bundle occupancy", and RAW-01 (line 4849) makes one complete
-- `authorityBundle` pointer the sole durable payload write. Reading the legacy
-- location directly silently disabled this owner's future-schema guard once a
-- bundle existed, so the selection is asked for here exactly as the evidence
-- owner performs it. A detached database that is not the evidence owner's bound
-- one falls through to its own bundle, never to this module's global state.
local function DurableEvidenceStore(database)
    return DurablePayload(database, "loadoutEvidence")
end

local function DetachedMeta(database)
    local source = DurablePayload(database, "dataCompaction")
    local meta = DeepCopy(type(source) == "table" and source or {})
    if meta.schemaVersion == nil then meta.schemaVersion = SCHEMA_VERSION end
    return meta
end

function Compaction.Enabled(database)
    database = AuthorityDatabase(database)
    local meta = DurablePayload(database, "dataCompaction")
    return type(meta) == "table"
        and tonumber(meta.schemaVersion) == SCHEMA_VERSION
        and (tonumber(meta.version) or 0) >= MIGRATION_VERSION
end

local function LoadoutFingerprint(source)
    local counts = {}
    for _, echo in ipairs(type(source) == "table" and source or {}) do
        if not (echo and echo.locked) then
            local spellId = tonumber(echo and (echo.spellId or echo.id))
            local stacks = tonumber(echo
                and (echo.stacks or echo.count or echo.stack)) or 1
            if spellId and stacks > 0 then
                counts[spellId] = (counts[spellId] or 0) + stacks
            end
        end
    end
    local ids = {}
    for spellId in pairs(counts) do ids[#ids + 1] = spellId end
    table.sort(ids)
    local parts = {}
    for _, spellId in ipairs(ids) do
        parts[#parts + 1] = tostring(spellId) .. "x"
            .. tostring(counts[spellId])
    end
    return #parts > 0 and table.concat(parts, ",") or nil
end

local function CompactField(row, inlineField, referenceField, options,
                            style, force, stats)
    if type(row) ~= "table" then return false, false end
    if not force and not Compaction.Enabled() then return false, false end
    local inline = row[inlineField]
    if type(inline) ~= "table" or next(inline) == nil then
        return false, false
    end
    local evidence = Evidence()
    if not (evidence and evidence.Fingerprint and evidence.Intern) then
        Add(stats, "retainedUnavailable")
        return false, false
    end

    Add(stats, "arraysSeen")
    Add(stats, "beforeInlineEchoRows", #inline)
    local claimed = row[referenceField]
    local exact = evidence.Fingerprint(inline, options)
    if not exact then
        Add(stats, "retainedMalformed")
        Add(stats, "afterInlineEchoRows", #inline)
        return false, false
    end
    local claimConflict = claimed ~= nil and tostring(claimed) ~= exact
    local semanticFingerprint = inlineField == "echoes"
        and LoadoutFingerprint(inline) or nil
    local fingerprintConflict = type(row.fingerprint) == "string"
        and row.fingerprint ~= "" and row.fingerprint:sub(1, 1) ~= "@"
        and semanticFingerprint ~= nil
        and tostring(row.fingerprint) ~= semanticFingerprint
    local reference, internWhy = evidence.Intern(inline, claimed, options)
    if not reference then
        if internWhy == "EVIDENCE_CANDIDATE_PENDING" then
            return false, false, internWhy
        end
        Add(stats, "retainedConflicts")
        Add(stats, "afterInlineEchoRows", #inline)
        return false, false
    end
    if claimConflict or fingerprintConflict then
        Add(stats, "retainedConflicts")
        Add(stats, "afterInlineEchoRows", #inline)
        return false, false
    end

    local resolved
    if style == "build" then
        local materialized = evidence.ResolveBuildRow({
            evidenceKey=reference,
        }, {useCandidate=true})
        resolved = materialized and materialized.echoes
    else
        resolved = evidence.ResolveDpsEchoes({
            [referenceField]=reference,
        }, inlineField == "lockedEchoes", true)
    end
    if not DeepEqual(inline, resolved) then
        Add(stats, "retainedNonCanonical")
        Add(stats, "afterInlineEchoRows", #inline)
        return false, false
    end

    if row[referenceField] ~= reference then
        row[referenceField] = reference
        Add(stats, "referencesWritten")
    end
    row[inlineField] = nil
    Add(stats, "arraysCompacted")
    Add(stats, "removedInlineEchoRows", #inline)
    return true, true
end

function Compaction.CompactBuildRow(row, force, stats)
    return CompactField(row, "echoes", "evidenceKey", nil,
        "build", force == true, stats)
end

function Compaction.CompactDpsRow(row, force, stats)
    if type(row) ~= "table" then return false, 0 end
    local changed, compacted = false, 0
    local fieldChanged, fieldCompacted, fieldWhy = CompactField(
        row, "echoes", "evidenceKey", nil, "dps", force == true, stats)
    if fieldWhy then return false, 0, fieldWhy end
    changed = fieldChanged or changed
    if fieldCompacted then compacted = compacted + 1 end
    fieldChanged, fieldCompacted, fieldWhy = CompactField(
        row, "lockedEchoes", "lockedEvidenceKey", {forceLocked=true},
        "dps", force == true, stats)
    if fieldWhy then return changed, compacted, fieldWhy end
    changed = fieldChanged or changed
    if fieldCompacted then compacted = compacted + 1 end
    return changed, compacted
end

local function Advance(event, reason)
    local revisions = Nexus and Nexus.Revisions
    if revisions and revisions.Advance and event then
        pcall(revisions.Advance, event, {scope="all", reason=reason})
    end
end

local function CancelPump()
    local scheduler = Nexus and Nexus.Scheduler
    if scheduler and type(scheduler.Cancel) == "function" then
        pcall(scheduler.Cancel, PUMP_KEY)
    end
end

local function ProviderHealth()
    local evidence = Evidence()
    if not evidence then error("loadout evidence pool unavailable") end
    local checker = evidence.ReferenceProvidersHealthy
    if type(checker) ~= "function" then return true end
    local healthy, failures, stable, generation = checker()
    if not healthy then
        error("runtime reference provider failed: " .. tostring(failures))
    end
    if stable == false then
        error("runtime reference providers changed during health check")
    end
    return generation
end

local function RefreshProviderGeneration(state)
    if not state.providersChecked then return false end
    local evidence = Evidence()
    local getter = evidence and evidence.ReferenceProviderGeneration
    if type(getter) ~= "function" then return false end
    local generation = getter()
    if generation == state.providerGeneration then return false end
    state.providersChecked,state.providerGeneration = false,nil
    return true
end

local function Revision(event)
    local revisions = Nexus and Nexus.Revisions
    if revisions and type(revisions.Get) == "function" and event then
        return tonumber(revisions.Get(event)) or 0
    end
    return 0
end

local function FutureCatalogReason(database)
    local owner = DurablePayload(database, "buildCatalog")
    if type(owner) ~= "table" then return nil end
    local catalog = Nexus and Nexus.BuildCatalog
    local schema = catalog and type(catalog.SchemaVersion) == "function"
        and tonumber(catalog.SchemaVersion()) or nil
    local stored = tonumber(rawget(owner,"schemaVersion"))
    if schema and stored and stored > schema then
        return "future catalog schema is read-only"
    end
    return nil
end

local function NewState(database, meta)
    local evidence = Evidence()
    if not (evidence and type(evidence.SchemaVersion) == "function") then
        error("loadout evidence pool unavailable")
    end
    local emptyOverlay, emptyDps, emptyEntries, emptyMeta = {}, {}, {}, {}
    local rawEvidenceStore = DurableEvidenceStore(database)
    local evidenceStore = type(rawEvidenceStore) == "table"
        and rawEvidenceStore or nil
    if evidenceStore and tonumber(evidenceStore.schemaVersion)
        and tonumber(evidenceStore.schemaVersion) > evidence.SchemaVersion() then
        error("future evidence schema is read-only")
    end
    local selectedOverlay = DurablePayload(database, "communityBuilds")
    local overlay = type(selectedOverlay) == "table"
        and selectedOverlay or emptyOverlay
    local selectedDps = DurablePayload(database, "dpsCapture")
    local sourceDps = type(selectedDps) == "table" and selectedDps or emptyDps
    local selectedMeta = DurablePayload(database, "dataCompaction")
    local sourceMeta = type(selectedMeta) == "table" and selectedMeta or emptyMeta
    local entries = evidenceStore and type(evidenceStore.entries) == "table"
        and evidenceStore.entries or emptyEntries
    local state = {
        database=database,meta=meta,phase="pool-before",cursor=nil,
        overlay=overlay,dps=DeepCopy(sourceDps),entries=entries,
        sourceDps=sourceDps,sourceMeta=sourceMeta,
        dpsStack=nil,dpsSeen=nil,
        evidenceStore=evidenceStore,maintenance=nil,pendingCommit=nil,
        pendingOverlay=nil,pendingDpsRow=nil,candidateEntries=nil,
        sourceVerificationPending=false,
        catalogOwner=DurablePayload(database, "buildCatalog"),
        emptyOverlay=emptyOverlay,emptyDps=emptyDps,emptyEntries=emptyEntries,
        emptyMeta=emptyMeta,
        buildChanged=false,dpsChanged=false,providersChecked=false,
        providerGeneration=nil,done=false,
    }
    local revisions = Nexus and Nexus.Revisions
    state.buildRevision = Revision(
        revisions and revisions.BUILD_LIBRARY_CHANGED)
    state.dpsRevision = Revision(revisions and revisions.DPS_CHANGED)
    -- The DPS revision and source table the private copy state.dps was taken
    -- from; the publication guard compares them with the live source.
    state.dpsSnapshotRevision, state.dpsSnapshotSource =
        state.dpsRevision, sourceDps
    state.stats = {
        migrationVersion=MIGRATION_VERSION,
        overlayRecordsBefore=0,overlayRecordsAfter=0,
        dpsRecordsBefore=0,dpsRecordsAfter=0,
        poolEntriesBefore=0,poolEntriesAfter=0,
        arraysSeen=0, arraysCompacted=0, referencesWritten=0,
        beforeInlineEchoRows=0, afterInlineEchoRows=0,
        removedInlineEchoRows=0, retainedMalformed=0,
        retainedConflicts=0, retainedNonCanonical=0,
        retainedUnavailable=0,
        gcRemoved=0,gcRetained=0,gcReferences=0,
        recordCountsUnchanged=false,pending=true,phase="pool-before",
        pumps=0,lastPumpWork=0,maxPumpWork=0,
        workBudget=MAX_WORK_PER_PUMP,restarts=0,
    }
    return state
end

-- Every pump re-resolves the canonical SavedVariables owners. A subsystem may
-- legitimately replace one of these tables while a bounded migration is
-- yielding; continuing through the captured table would compact stale data and
-- then falsely stamp the replacement complete. Future owners are never
-- normalized or annotated by this older migration.
local function RefreshOwners(state)
    local database = state.database
    local selectedMeta = DurablePayload(database, "dataCompaction")
    if selectedMeta ~= nil and type(selectedMeta) ~= "table" then
        return "blocked","compaction metadata is incompatible",false
    end
    local meta = type(selectedMeta) == "table" and selectedMeta
        or state.emptyMeta
    if tonumber(meta.schemaVersion)
        and tonumber(meta.schemaVersion) > SCHEMA_VERSION then
        return "blocked","future compaction schema is read-only",false
    end
    if (tonumber(meta.version) or 0) >= MIGRATION_VERSION then
        return "complete",meta,false
    end

    local catalogOwner = DurablePayload(database, "buildCatalog")
    local catalogReason = FutureCatalogReason(database)
    if catalogReason then return "blocked",catalogReason,false end

    local evidence = Evidence()
    if not (evidence and type(evidence.SchemaVersion) == "function") then
        return "blocked","loadout evidence pool unavailable",false
    end
    local evidenceStore = DurableEvidenceStore(database)
    if type(evidenceStore) == "table"
        and tonumber(evidenceStore.schemaVersion)
        and tonumber(evidenceStore.schemaVersion) > evidence.SchemaVersion() then
        return "blocked","future evidence schema is read-only",false
    end

    local selectedOverlay = DurablePayload(database, "communityBuilds")
    local overlay = type(selectedOverlay) == "table" and selectedOverlay
        or state.emptyOverlay
    local selectedDps = DurablePayload(database, "dpsCapture")
    local dps = type(selectedDps) == "table" and selectedDps
        or state.emptyDps
    local entries = type(evidenceStore) == "table"
        and type(evidenceStore.entries) == "table"
        and evidenceStore.entries or state.emptyEntries
    local changed = meta ~= state.sourceMeta or catalogOwner ~= state.catalogOwner
        or evidenceStore ~= state.evidenceStore or overlay ~= state.overlay
        or dps ~= state.sourceDps or entries ~= state.entries
    -- Only a replaced catalog backing table is current-source drift for the
    -- catalog root; evidence or DPS owner changes are not.
    state.catalogOwnerChanged = overlay ~= state.overlay
        or catalogOwner ~= state.catalogOwner
    state.sourceMeta,state.catalogOwner,state.evidenceStore =
        meta,catalogOwner,evidenceStore
    state.overlay,state.sourceDps,state.entries = overlay,dps,entries
    return "ok",nil,changed
end

-- Overlay rows are never mutated in place. The catalog maintenance handle
-- collects every compacted replacement off-state and commits them together;
-- any restart discards the uncommitted candidate before a new walk begins.
local function CancelOverlayCandidate(state)
    local handle = state.maintenance
    state.maintenance = nil
    if handle then
        local catalog = Nexus and Nexus.BuildCatalog
        if catalog and type(catalog.CancelMaintenance) == "function" then
            catalog.CancelMaintenance(handle)
        end
    end
end

local function OverlayCatalog(state)
    local catalog = CatalogFor(state.database)
    if not (catalog
        and type(catalog.MaintenanceOverlayNext) == "function") then
        return nil
    end
    return catalog
end

-- Replacing a bound SavedVariables owner is current-source drift for the
-- catalog root. The maintenance owner performs one explicit readmission from
-- cursor zero so its next walk sees the exact new selected rows.
local function ReadmitCatalog()
    -- MASTER-RC-001, dependent-side prohibition of architecture lines
    -- 1207-1211. This previously called catalog.BeginRootAdmission and then
    -- drained catalog.PumpRootAdmission in an unbounded loop -- the literal
    -- "call a domain recovery pump ... directly" the clause forbids, from a
    -- maintenance owner that owns no part of the catalog root. It now
    -- registers one idempotent dependency; the startup coordinator or the
    -- MainLifecycle scheduler-turn rebind pump performs the readmission
    -- inside its own bounded slice.
    local catalog = Nexus and Nexus.BuildCatalog
    if not (catalog
        and type(catalog.RequestAuthorityRebindV1) == "function") then
        return
    end
    catalog.RequestAuthorityRebindV1("SOURCE_REBIND_REQUIRED")
end

local function RestartForExternalChange(state, ownersChanged)
    local revisions = Nexus and Nexus.Revisions
    local buildRevision = Revision(
        revisions and revisions.BUILD_LIBRARY_CHANGED)
    local dpsRevision = Revision(revisions and revisions.DPS_CHANGED)
    if not ownersChanged and buildRevision == state.buildRevision
        and dpsRevision == state.dpsRevision then return false end
    local dpsChanged = dpsRevision ~= state.dpsRevision
    state.buildRevision,state.dpsRevision = buildRevision,dpsRevision
    -- In pool-before no build row has been visited, so a build-only change
    -- needs no restart. The private DPS copy already exists, though: a DPS
    -- change must never be absorbed while that older copy is kept.
    if not ownersChanged and state.phase == "pool-before"
        and not dpsChanged then return false end
    CancelOverlayCandidate(state)
    state.meta = DeepCopy(type(state.sourceMeta) == "table"
        and state.sourceMeta or {})
    if state.meta.schemaVersion == nil then
        state.meta.schemaVersion = SCHEMA_VERSION
    end
    state.dps = DeepCopy(type(state.sourceDps) == "table"
        and state.sourceDps or {})
    state.dpsSnapshotRevision, state.dpsSnapshotSource =
        dpsRevision, state.sourceDps
    state.candidateEntries,state.pendingOverlay,state.pendingDpsRow = nil,nil,nil
    state.buildChanged,state.dpsChanged = false,false
    if ownersChanged and state.catalogOwnerChanged then
        state.catalogOwnerChanged = false
        ReadmitCatalog()
    end
    state.phase,state.cursor,state.done = "pool-before",nil,false
    state.dpsStack,state.dpsSeen = nil,nil
    state.stats.overlayRecordsBefore,state.stats.overlayRecordsAfter = 0,0
    state.stats.dpsRecordsBefore,state.stats.dpsRecordsAfter = 0,0
    state.stats.poolEntriesAfter = 0
    if ownersChanged then state.stats.poolEntriesBefore = 0 end
    state.stats.restarts = state.stats.restarts + 1
    state.stats.pending,state.stats.phase = true,state.phase
    return true
end

-- True while the live DPS source is the one state.dps was copied from and no
-- DPS change was represented since. Checked by the catalog at the actual
-- publication of the compaction commit (the dpsCapture override replaces the
-- live table there), so a DPS record accepted after the copy restarts the
-- migration instead of being overwritten by the older copy. An absent or
-- malformed payload is selected as the empty table, as RefreshOwners does.
local function DpsSnapshotCurrent(state)
    local revisions = Nexus and Nexus.Revisions
    local live = DurablePayload(state.database, "dpsCapture")
    if type(live) ~= "table" then live = state.emptyDps end
    return Revision(revisions and revisions.DPS_CHANGED)
            == state.dpsSnapshotRevision
        and live == state.dpsSnapshotSource
end

local function BeginDps(state)
    state.dpsStack = {{value=state.dps,key=nil}}
    state.dpsSeen = {[state.dps]=true}
end

-- SavedVariables owners may accept a user edit while the migration is between
-- pumps. Lua 5.1 rejects next(table, removedKey), so a deleted cursor restarts
-- that one phase instead of aborting or retaining an unbounded key snapshot.
-- Every repeated visit still consumes the fixed pump budget and row rewrites
-- are idempotent.
local function SafeNext(source, cursor)
    local ok, key, value = pcall(next,source,cursor)
    if ok then return key,value end
    return next(source,nil)
end

local function DpsStep(state)
    if state.pendingDpsRow then
        local changed, _, why = Compaction.CompactDpsRow(
            state.pendingDpsRow, true, state.stats)
        if why == "EVIDENCE_CANDIDATE_PENDING" then return true, true end
        state.dpsChanged = changed or state.dpsChanged
        state.stats.dpsRecordsAfter = state.stats.dpsRecordsAfter + 1
        state.pendingDpsRow = nil
        return true
    end
    local frame = state.dpsStack[#state.dpsStack]
    if not frame then
        state.phase,state.cursor = "pool-after",nil
        state.stats.phase = state.phase
        return false
    end
    local key, child = SafeNext(frame.value, frame.key)
    frame.key = key
    if key == nil then
        state.dpsStack[#state.dpsStack] = nil
        if #state.dpsStack == 0 then
            state.phase,state.cursor = "pool-after",nil
            state.stats.phase = state.phase
        end
        return true
    end
    if key ~= "echoes" and key ~= "lockedEchoes"
        and type(child) == "table"
        and not state.dpsSeen[child] then
        state.dpsSeen[child] = true
        state.dpsStack[#state.dpsStack + 1] = {value=child,key=nil}
        if tonumber(child.dps) ~= nil then
            state.stats.dpsRecordsBefore =
                state.stats.dpsRecordsBefore + 1
            state.pendingDpsRow = child
            return DpsStep(state)
        end
    end
    return true
end

local function CompactOverlayRow(state, catalog, id, row)
    local changed, _, why = Compaction.CompactBuildRow(
        row, true, state.stats)
    if why then return false, why end
    if changed then
        local staged = catalog.MaintenanceReplaceRow(
            state.maintenance, id, row)
        if staged then
            state.buildChanged = true
        else
            Add(state.stats, "retainedUnavailable")
        end
    end
    state.stats.overlayRecordsAfter =
        state.stats.overlayRecordsAfter + 1
    return true
end

local function Step(state)
    if state.phase == "pool-before" then
        local key = SafeNext(state.entries,state.cursor)
        state.cursor = key
        if key ~= nil then
            state.stats.poolEntriesBefore =
                state.stats.poolEntriesBefore + 1
            return true
        end
        state.phase,state.cursor = "candidate",nil
        state.stats.phase = state.phase
        return true
    elseif state.phase == "candidate" then
        local catalog = OverlayCatalog(state)
        if state.maintenance and state.maintenance.state ~= "open" then
            state.maintenance = nil
        end
        if catalog and not state.maintenance then
            local handle, why = catalog.BeginCatalogMaintenance({
                database=state.database, operation="compaction"})
            if not handle then
                if why == "ROOT_MUTATION_PENDING"
                    or why == "ROOT_ADMISSION_PENDING"
                    or why == "MAINTENANCE_ACTIVE" then
                    state.stats.phase = "catalog-wait"
                    return true, true
                end
                error(why or "catalog authority unavailable")
            end
            state.maintenance = handle
        end
        if not (catalog and state.maintenance) then
            error("catalog authority unavailable")
        end
        local evidence = Evidence()
        local store, why
        if evidence and type(evidence.CandidateStore) == "function" then
            store, why = evidence.CandidateStore()
        end
        if not store then
            if why == "EVIDENCE_CANDIDATE_PENDING" then
                state.stats.phase = "evidence-copy"
                return true, true
            end
            error(why or "loadout evidence candidate unavailable")
        end
        state.candidateEntries = type(store.entries) == "table"
            and store.entries or state.emptyEntries
        state.phase,state.cursor = "overlay",nil
        state.stats.phase = state.phase
        return true
    elseif state.phase == "overlay" then
        local catalog = OverlayCatalog(state)
        if state.maintenance and state.maintenance.state ~= "open" then
            state.maintenance = nil
            state.phase = "candidate"
            state.stats.phase = "catalog-wait"
            return true, true
        end
        if not (catalog and state.maintenance) then
            -- Overlay rows can be compacted only through the catalog
            -- authority bound to this exact database. An unbound, pending,
            -- invalidated, or future root blocks the migration instead of
            -- stamping unvisited rows complete.
            error("catalog authority unavailable")
        end
        if catalog and state.maintenance then
            if state.pendingOverlay then
                local pending = state.pendingOverlay
                local complete, why = CompactOverlayRow(
                    state, catalog, pending.id, pending.row)
                if not complete then
                    if why == "EVIDENCE_CANDIDATE_PENDING" then
                        return true, true
                    end
                    error(why)
                end
                state.pendingOverlay = nil
                return true
            end
            local id, row, done, why = catalog.MaintenanceOverlayNext(
                state.maintenance, state.cursor)
            if why == "COPY_PENDING" then return true, true end
            if why then error(why) end
            if not done and id ~= nil then
                state.cursor = id
                state.stats.overlayRecordsBefore =
                    state.stats.overlayRecordsBefore + 1
                local complete, compactWhy = CompactOverlayRow(
                    state, catalog, id, row)
                if not complete then
                    if compactWhy == "EVIDENCE_CANDIDATE_PENDING" then
                        state.pendingOverlay = {id=id,row=row}
                        return true, true
                    end
                    error(compactWhy)
                end
                return true
            end
        end
        state.phase,state.cursor = "dps",nil
        BeginDps(state)
        state.stats.phase = state.phase
        return true
    elseif state.phase == "dps" then
        -- A released walk (displaced by a direct mutation or a rebind turn)
        -- has lost its evidence candidate, so an intern now would go into the
        -- live pool. The partly compacted private copy refers to the
        -- discarded candidate: restart from a fresh copy.
        if state.maintenance and state.maintenance.state ~= "open" then
            RestartForExternalChange(state,true)
            return true, true
        end
        return DpsStep(state)
    elseif state.phase == "pool-after" then
        local entries = state.candidateEntries or state.entries
        local key = SafeNext(entries,state.cursor)
        state.cursor = key
        if key ~= nil then
            state.stats.poolEntriesAfter =
                state.stats.poolEntriesAfter + 1
            return true
        end
        state.phase,state.done = "done",true
        state.stats.phase = state.phase
        return true
    end
    state.stats.phase = state.phase
    return false
end

local function PreparePublication(state)
    local stats = state.stats
    stats.gcRetained = stats.poolEntriesAfter
    stats.recordCountsUnchanged =
        stats.overlayRecordsBefore == stats.overlayRecordsAfter
        and stats.dpsRecordsBefore == stats.dpsRecordsAfter
    if state.meta.schemaVersion == nil then
        state.meta.schemaVersion = SCHEMA_VERSION
    end
    state.meta.version = MIGRATION_VERSION
    local terminal = DeepCopy(stats)
    terminal.pending,terminal.phase = false,"done"
    state.meta.last = terminal
    state.meta.lastError = nil
    state.meta.inProgress = nil
    return {dpsCapture=state.dps,dataCompaction=state.meta}
end

local function Finish(state)
    local stats = state.stats
    stats.pending,stats.phase = false,"done"
    active = nil
    CancelPump()
    -- Completion ownership is settled before synchronous revision subscribers
    -- run. A subscriber may legitimately replace a canonical table or install
    -- a future schema; no compaction write occurs after that boundary.
    local revisions = Nexus and Nexus.Revisions
    if state.buildChanged then
        Advance(revisions and revisions.BUILD_LIBRARY_CHANGED,
            "exact evidence compaction")
    end
    if state.dpsChanged then
        Advance(revisions and revisions.DPS_CHANGED,
            "exact evidence compaction")
    end
    return DeepCopy(stats), true
end

local function Fail(state, err)
    local message = tostring(err):sub(1,500)
    CancelOverlayCandidate(state)
    state.meta.lastError = message
    state.meta.inProgress = nil
    active = nil
    CancelPump()
    return {blocked=true,reason=message,pending=false}, false
end

local function StopWithoutWrite(reason)
    if active then CancelOverlayCandidate(active) end
    active = nil
    CancelPump()
    return {blocked=true,reason=reason,pending=false},false
end

local function CompleteWithoutWrite(meta)
    if active then CancelOverlayCandidate(active) end
    active = nil
    CancelPump()
    return DeepCopy(meta.last or {migrationVersion=MIGRATION_VERSION}),false
end

local function SchedulePump()
    local scheduler = Nexus and Nexus.Scheduler
    if not (scheduler and type(scheduler.Every) == "function") then
        return false
    end
    local ok, scheduled = pcall(scheduler.Every,
        PUMP_KEY,PUMP_INTERVAL,function() Compaction.Pump() end)
    return ok and scheduled == true
end

local function RunWork(state, work)
    while work < MAX_WORK_PER_PUMP and not state.done do
        local worked, mustYield = Step(state)
        if worked then work = work + 1 end
        if mustYield then break end
    end
    return work
end

local function UpdatePumpStats(state, work, increment)
    if increment then state.stats.pumps = state.stats.pumps + 1 end
    state.stats.lastPumpWork = work
    state.stats.maxPumpWork = math.max(state.stats.maxPumpWork,work)
    state.stats.pending = not state.done
    state.stats.phase = state.phase
end

function Compaction.Pump()
    local state = active
    if not state then return Compaction.Stats(), false end
    if state.pendingCommit then
        local ticket = state.pendingCommit
        if ticket.state == "pending" then
            state.stats.pending, state.stats.phase = true, "commit-pending"
            local result = DeepCopy(state.stats)
            result.mutationTicket = ticket
            return result, false
        end
        state.pendingCommit = nil
        if ticket.state ~= "committed" or ticket.committed ~= true then
            local why = ticket.reason or "catalog maintenance unavailable"
            if why == "SOURCE_DRIFT" or why == "CANDIDATE_FAILED"
                or why == "PUBLICATION_SOURCE_CHANGED" then
                RestartForExternalChange(state,true)
                return DeepCopy(state.stats),false
            end
            return Fail(state,why)
        end
        if ticket.database ~= state.database or NexusDB ~= state.database
            or rawget(state.database, "authorityBundle") ~= ticket.bundle then
            return StopWithoutWrite("SOURCE_DRIFT")
        end
        local finishOk, result, changed = pcall(Finish,state)
        if not finishOk then return Fail(state,result) end
        return result,changed
    end
    if state.sourceVerificationPending then
        local catalog = Nexus and Nexus.BuildCatalog
        if not (catalog
            and type(catalog.PumpSourceVerificationV1) == "function") then
            return Fail(state,"catalog source verification unavailable")
        end
        local verified = catalog.PumpSourceVerificationV1({
            edges=MAX_WORK_PER_PUMP,
            nodes=MAX_WORK_PER_PUMP,
            bytes=2048,
        })
        if type(verified) ~= "table" or verified.state == "pending" then
            state.stats.pending,state.stats.phase = true,"source-verification"
            return DeepCopy(state.stats),false
        end
        state.sourceVerificationPending = false
        if verified.state ~= "current" then
            return StopWithoutWrite(verified.reason or "SOURCE_DRIFT")
        end
        state.stats.pending,state.stats.phase = true,state.phase
        return DeepCopy(state.stats),false
    end
    local ownerStatus, ownerValue, ownersChanged = RefreshOwners(state)
    if ownerStatus == "blocked" then return StopWithoutWrite(ownerValue) end
    if ownerStatus == "complete" then return CompleteWithoutWrite(ownerValue) end
    RestartForExternalChange(state,ownersChanged)
    RefreshProviderGeneration(state)
    local work = 0
    local ok, result = pcall(RunWork,state,work)
    if ok then work = result end
    UpdatePumpStats(state,work,true)
    if not ok then return Fail(state,result) end
    ownerStatus,ownerValue,ownersChanged = RefreshOwners(state)
    if ownerStatus == "blocked" then return StopWithoutWrite(ownerValue) end
    if ownerStatus == "complete" then return CompleteWithoutWrite(ownerValue) end
    RefreshProviderGeneration(state)
    if RestartForExternalChange(state,ownersChanged) then
        return DeepCopy(state.stats),false
    end
    if state.done then
        if RestartForExternalChange(state,false) then
            return DeepCopy(state.stats),false
        end
        if not state.providersChecked then
            local healthOk, healthGeneration = pcall(ProviderHealth)
            if not healthOk then
                -- A provider is an external callback and may replace or
                -- promote a SavedVariables owner before it fails. Recheck the
                -- ownership boundary before writing our supported-schema
                -- diagnostic fields into what may now be future metadata.
                ownerStatus,ownerValue = RefreshOwners(state)
                if ownerStatus == "blocked" then
                    return StopWithoutWrite(ownerValue)
                end
                if ownerStatus == "complete" then
                    return CompleteWithoutWrite(ownerValue)
                end
                return Fail(state,healthGeneration)
            end
            state.providersChecked = true
            state.providerGeneration = healthGeneration
            ownerStatus,ownerValue,ownersChanged = RefreshOwners(state)
            if ownerStatus == "blocked" then
                return StopWithoutWrite(ownerValue)
            end
            if ownerStatus == "complete" then
                return CompleteWithoutWrite(ownerValue)
            end
            -- Provider callbacks are expected to be read-only, but they are an
            -- external boundary. One final bounded verification traversal also
            -- captures a provider that inserted data without advancing the
            -- represented revisions or replacing an owner table.
            state.stats.afterInlineEchoRows = 0
            state.stats.retainedMalformed = 0
            state.stats.retainedConflicts = 0
            state.stats.retainedNonCanonical = 0
            state.stats.retainedUnavailable = 0
            RestartForExternalChange(state,true)
            -- A provider callback is an external event boundary. Yield before
            -- the verification walk and let the catalog's bounded exact source
            -- verifier reach a terminal result. A raw change behind the
            -- published root must invalidate it before compaction can stamp
            -- completion.
            state.sourceVerificationPending = true
            state.stats.pending,state.stats.phase = true,"source-verification"
            return DeepCopy(state.stats),false
        end
        ownerStatus,ownerValue,ownersChanged = RefreshOwners(state)
        if ownerStatus == "blocked" then return StopWithoutWrite(ownerValue) end
        if ownerStatus == "complete" then return CompleteWithoutWrite(ownerValue) end
        if RestartForExternalChange(state,ownersChanged) then
            return DeepCopy(state.stats),false
        end
        -- Publish every compacted overlay replacement as one catalog
        -- transaction before the migration stamp; a drifted candidate is
        -- discarded and the bounded walk restarts from cursor zero. A walk
        -- released before its commit restarts the same way.
        if state.maintenance and state.maintenance.state ~= "open" then
            RestartForExternalChange(state,true)
            return DeepCopy(state.stats),false
        end
        local handle = state.maintenance
        state.maintenance = nil
        if handle then
            local catalog = Nexus and Nexus.BuildCatalog
            local overrides = PreparePublication(state)
            local committed, commitWhy, ticket = catalog.CommitMaintenance(
                handle, overrides, function() return DpsSnapshotCurrent(state) end)
            if committed == nil and commitWhy == "ROOT_MUTATION_PENDING"
                and type(ticket) == "table" then
                state.pendingCommit = ticket
                state.stats.pending, state.stats.phase = true, "commit-pending"
                local result = DeepCopy(state.stats)
                result.mutationTicket = ticket
                return result,false
            end
            if not committed then
                if commitWhy == "SOURCE_DRIFT" or commitWhy == "CANDIDATE_FAILED"
                    or commitWhy == "PUBLICATION_SOURCE_CHANGED" then
                    RestartForExternalChange(state,true)
                    return DeepCopy(state.stats),false
                end
                return Fail(state,commitWhy)
            end
        end
        local finishOk, result, changed = pcall(Finish,state)
        if not finishOk then return Fail(state,result) end
        return result,changed
    end
    return DeepCopy(state.stats), false
end

function Compaction.Init(database)
    database = AuthorityDatabase(database) or {}
    local catalogReason = FutureCatalogReason(database)
    if catalogReason then
        return {blocked=true,reason=catalogReason},false
    end
    local rawMeta = DurablePayload(database, "dataCompaction")
    if rawMeta ~= nil and type(rawMeta) ~= "table" then
        return {blocked=true,reason="compaction metadata is incompatible"},false
    end
    if type(rawMeta) == "table" and tonumber(rawMeta.schemaVersion)
        and tonumber(rawMeta.schemaVersion) > SCHEMA_VERSION then
        return {blocked=true, reason="future compaction schema is read-only"},false
    end
    local evidenceStore = DurableEvidenceStore(database)
    local evidence = Evidence()
    if type(evidenceStore) == "table" and tonumber(evidenceStore.schemaVersion)
        and evidence and type(evidence.SchemaVersion) == "function"
        and tonumber(evidenceStore.schemaVersion) > evidence.SchemaVersion() then
        return {blocked=true,reason="future evidence schema is read-only"},false
    end
    local meta = DetachedMeta(database)
    if (tonumber(meta.version) or 0) >= MIGRATION_VERSION then
        return DeepCopy(meta.last or {migrationVersion=MIGRATION_VERSION}), false
    end
    if active and active.database ~= database then
        CancelOverlayCandidate(active)
        CancelPump()
        active = nil
    end
    if not active then
        local ok, state = pcall(NewState,database,meta)
        if not ok then
            return {blocked=true,reason=tostring(state):sub(1,500)},false
        end
        active = state
        state.meta.inProgress = {version=MIGRATION_VERSION}
        SchedulePump()
    end
    return Compaction.Pump()
end

function Compaction.CollectGarbage(database, dryRun)
    local evidence = Evidence()
    if not (evidence and evidence.CollectGarbage) then
        return {blocked=true, reason="loadout evidence pool unavailable"}
    end
    database = AuthorityDatabase(database)
    if type(database) ~= "table" then
        return {blocked=true, reason="database required"}
    end
    if dryRun == true then return evidence.CollectGarbage(database, true) end
    if active and active.database == database then
        return {blocked=true, reason="compaction already active"}
    end
    local catalog = CatalogFor(database)
    if not catalog then
        return {blocked=true, reason="catalog authority unavailable"}
    end

    local job = garbageJobs[database]
    if job and job.ticket then
        local ticket = job.ticket
        if ticket.state == "pending" then
            return {pending=true, phase="commit-pending",
                mutationTicket=ticket, removed=0}
        end
        garbageJobs[database] = nil
        if ticket.state ~= "committed" or ticket.committed ~= true
            or ticket.database ~= database
            or rawget(database, "authorityBundle") ~= ticket.bundle then
            return {blocked=true, pending=false,
                reason=ticket.reason or "SOURCE_DRIFT", removed=0}
        end
        local result = DeepCopy(job.summary)
        result.pending = false
        return result
    end

    if not job then
        local handle, why = catalog.BeginCatalogMaintenance({
            database=database, operation="evidence-gc"})
        if not handle then
            return {blocked=true, reason=why or "catalog maintenance unavailable",
                removed=0}
        end
        job = {handle=handle,catalog=catalog}
        garbageJobs[database] = job
    elseif job.handle.state ~= "open" then
        garbageJobs[database] = nil
        return {blocked=true, reason="SOURCE_DRIFT", removed=0}
    end

    local store, storeWhy = evidence.CandidateStore()
    if not store then
        if storeWhy == "EVIDENCE_CANDIDATE_PENDING" then
            return {pending=true, phase="evidence-copy", removed=0}
        end
        catalog.CancelMaintenance(job.handle)
        garbageJobs[database] = nil
        return {blocked=true,
            reason=storeWhy or "loadout evidence candidate unavailable",
            removed=0}
    end
    local summary = evidence.CollectGarbage(database, false)
    if type(summary) ~= "table" or summary.blocked then
        catalog.CancelMaintenance(job.handle)
        garbageJobs[database] = nil
        return type(summary) == "table" and summary
            or {blocked=true, reason="evidence garbage collection failed",
                removed=0}
    end
    job.summary = DeepCopy(summary)
    local committed, why, ticket = catalog.CommitMaintenance(job.handle)
    job.handle = nil
    if committed == true then
        garbageJobs[database] = nil
        summary.pending = false
        return summary
    end
    if committed == nil and why == "ROOT_MUTATION_PENDING"
        and type(ticket) == "table" then
        job.ticket = ticket
        return {pending=true, phase="commit-pending",
            mutationTicket=ticket, removed=0}
    end
    garbageJobs[database] = nil
    return {blocked=true, reason=why or "CANDIDATE_FAILED", removed=0}
end

function Compaction.Stats(database)
    database = AuthorityDatabase(database) or {}
    if active and active.database == database then
        return DeepCopy(active.stats)
    end
    local selected = DurablePayload(database, "dataCompaction")
    local meta = type(selected) == "table" and selected or {}
    if type(meta.last) == "table" then return DeepCopy(meta.last) end
    return meta.inProgress and {migrationVersion=MIGRATION_VERSION,
        pending=true,phase="restart"} or {}
end

function Compaction.Version()
    return MIGRATION_VERSION
end
