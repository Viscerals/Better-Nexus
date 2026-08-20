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

local function Meta(database)
    database.dataCompaction = type(database.dataCompaction) == "table"
        and database.dataCompaction or {}
    local meta = database.dataCompaction
    if meta.schemaVersion == nil then meta.schemaVersion = SCHEMA_VERSION end
    return meta
end

function Compaction.Enabled(database)
    database = type(database) == "table" and database
        or type(NexusDB) == "table" and NexusDB or nil
    local meta = database and database.dataCompaction
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
    local reference = evidence.Intern(inline, claimed, options)
    if not reference then
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
        })
        resolved = materialized and materialized.echoes
    else
        resolved = evidence.ResolveDpsEchoes({
            [referenceField]=reference,
        }, inlineField == "lockedEchoes")
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
    local fieldChanged, fieldCompacted = CompactField(
        row, "echoes", "evidenceKey", nil, "dps", force == true, stats)
    changed = fieldChanged or changed
    if fieldCompacted then compacted = compacted + 1 end
    fieldChanged, fieldCompacted = CompactField(
        row, "lockedEchoes", "lockedEvidenceKey", {forceLocked=true},
        "dps", force == true, stats)
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
    local owner = rawget(database,"buildCatalog")
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
    local emptyOverlay, emptyDps, emptyEntries = {}, {}, {}
    local evidenceStore = type(database.loadoutEvidence) == "table"
        and database.loadoutEvidence or nil
    if evidenceStore and tonumber(evidenceStore.schemaVersion)
        and tonumber(evidenceStore.schemaVersion) > evidence.SchemaVersion() then
        error("future evidence schema is read-only")
    end
    local overlay = type(database.communityBuilds) == "table"
        and database.communityBuilds or emptyOverlay
    local dps = type(database.dpsCapture) == "table"
        and database.dpsCapture or emptyDps
    local entries = evidenceStore and type(evidenceStore.entries) == "table"
        and evidenceStore.entries or emptyEntries
    local state = {
        database=database,meta=meta,phase="pool-before",cursor=nil,
        overlay=overlay,dps=dps,entries=entries,dpsStack=nil,dpsSeen=nil,
        evidenceStore=evidenceStore,
        catalogOwner=type(database.buildCatalog) == "table"
            and database.buildCatalog or nil,
        emptyOverlay=emptyOverlay,emptyDps=emptyDps,emptyEntries=emptyEntries,
        buildChanged=false,dpsChanged=false,providersChecked=false,
        providerGeneration=nil,done=false,
    }
    local revisions = Nexus and Nexus.Revisions
    state.buildRevision = Revision(
        revisions and revisions.BUILD_LIBRARY_CHANGED)
    state.dpsRevision = Revision(revisions and revisions.DPS_CHANGED)
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
    local meta = rawget(database,"dataCompaction")
    if type(meta) ~= "table" then
        return "blocked","compaction metadata is incompatible",false
    end
    if tonumber(meta.schemaVersion)
        and tonumber(meta.schemaVersion) > SCHEMA_VERSION then
        return "blocked","future compaction schema is read-only",false
    end
    if (tonumber(meta.version) or 0) >= MIGRATION_VERSION then
        return "complete",meta,false
    end

    local catalogOwner = rawget(database,"buildCatalog")
    local catalogReason = FutureCatalogReason(database)
    if catalogReason then return "blocked",catalogReason,false end

    local evidence = Evidence()
    if not (evidence and type(evidence.SchemaVersion) == "function") then
        return "blocked","loadout evidence pool unavailable",false
    end
    local evidenceStore = rawget(database,"loadoutEvidence")
    if type(evidenceStore) == "table"
        and tonumber(evidenceStore.schemaVersion)
        and tonumber(evidenceStore.schemaVersion) > evidence.SchemaVersion() then
        return "blocked","future evidence schema is read-only",false
    end

    local overlay = type(rawget(database,"communityBuilds")) == "table"
        and database.communityBuilds or state.emptyOverlay
    local dps = type(rawget(database,"dpsCapture")) == "table"
        and database.dpsCapture or state.emptyDps
    local entries = type(evidenceStore) == "table"
        and type(evidenceStore.entries) == "table"
        and evidenceStore.entries or state.emptyEntries
    local changed = meta ~= state.meta or catalogOwner ~= state.catalogOwner
        or evidenceStore ~= state.evidenceStore or overlay ~= state.overlay
        or dps ~= state.dps or entries ~= state.entries
    state.meta,state.catalogOwner,state.evidenceStore =
        meta,catalogOwner,evidenceStore
    state.overlay,state.dps,state.entries = overlay,dps,entries
    return "ok",nil,changed
end

local function RestartForExternalChange(state, ownersChanged)
    local revisions = Nexus and Nexus.Revisions
    local buildRevision = Revision(
        revisions and revisions.BUILD_LIBRARY_CHANGED)
    local dpsRevision = Revision(revisions and revisions.DPS_CHANGED)
    if not ownersChanged and buildRevision == state.buildRevision
        and dpsRevision == state.dpsRevision then return false end
    state.buildRevision,state.dpsRevision = buildRevision,dpsRevision
    if not ownersChanged and state.phase == "pool-before" then return false end
    state.phase,state.cursor,state.done =
        ownersChanged and "pool-before" or "overlay",nil,false
    state.dpsStack,state.dpsSeen = nil,nil
    state.stats.overlayRecordsBefore,state.stats.overlayRecordsAfter = 0,0
    state.stats.dpsRecordsBefore,state.stats.dpsRecordsAfter = 0,0
    state.stats.poolEntriesAfter = 0
    if ownersChanged then state.stats.poolEntriesBefore = 0 end
    state.stats.restarts = state.stats.restarts + 1
    state.stats.pending,state.stats.phase = true,state.phase
    return true
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
            local changed = Compaction.CompactDpsRow(
                child, true, state.stats)
            state.dpsChanged = changed or state.dpsChanged
            state.stats.dpsRecordsAfter =
                state.stats.dpsRecordsAfter + 1
        end
    end
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
        state.phase,state.cursor = "overlay",nil
        state.stats.phase = state.phase
        return true
    elseif state.phase == "overlay" then
        local key, row = SafeNext(state.overlay,state.cursor)
        state.cursor = key
        if key ~= nil then
            state.stats.overlayRecordsBefore =
                state.stats.overlayRecordsBefore + 1
            local changed = Compaction.CompactBuildRow(
                row, true, state.stats)
            state.buildChanged = changed or state.buildChanged
            state.stats.overlayRecordsAfter =
                state.stats.overlayRecordsAfter + 1
            return true
        end
        state.phase,state.cursor = "dps",nil
        BeginDps(state)
        state.stats.phase = state.phase
        return true
    elseif state.phase == "dps" then
        return DpsStep(state)
    elseif state.phase == "pool-after" then
        local key = SafeNext(state.entries,state.cursor)
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

local function Finish(state)
    local stats = state.stats
    stats.gcRetained = stats.poolEntriesAfter
    stats.recordCountsUnchanged =
        stats.overlayRecordsBefore == stats.overlayRecordsAfter
        and stats.dpsRecordsBefore == stats.dpsRecordsAfter
    stats.pending,stats.phase = false,"done"
    if state.meta.schemaVersion == nil then
        state.meta.schemaVersion = SCHEMA_VERSION
    end
    state.meta.version = MIGRATION_VERSION
    state.meta.last = DeepCopy(stats)
    state.meta.lastError = nil
    state.meta.inProgress = nil
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
    state.meta.lastError = message
    state.meta.inProgress = nil
    active = nil
    CancelPump()
    return {blocked=true,reason=message,pending=false}, false
end

local function StopWithoutWrite(reason)
    active = nil
    CancelPump()
    return {blocked=true,reason=reason,pending=false},false
end

local function CompleteWithoutWrite(meta)
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
        if Step(state) then work = work + 1 end
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
            local verifyOk, verifyResult = pcall(RunWork,state,work)
            if not verifyOk then return Fail(state,verifyResult) end
            work = verifyResult
            UpdatePumpStats(state,work,false)
            if not state.done then return DeepCopy(state.stats),false end
        end
        ownerStatus,ownerValue,ownersChanged = RefreshOwners(state)
        if ownerStatus == "blocked" then return StopWithoutWrite(ownerValue) end
        if ownerStatus == "complete" then return CompleteWithoutWrite(ownerValue) end
        if RestartForExternalChange(state,ownersChanged) then
            return DeepCopy(state.stats),false
        end
        local finishOk, result, changed = pcall(Finish,state)
        if not finishOk then return Fail(state,result) end
        return result,changed
    end
    return DeepCopy(state.stats), false
end

function Compaction.Init(database)
    database = type(database) == "table" and database or {}
    local catalogReason = FutureCatalogReason(database)
    if catalogReason then
        return {blocked=true,reason=catalogReason},false
    end
    local rawMeta = rawget(database,"dataCompaction")
    if rawMeta ~= nil and type(rawMeta) ~= "table" then
        return {blocked=true,reason="compaction metadata is incompatible"},false
    end
    if type(rawMeta) == "table" and tonumber(rawMeta.schemaVersion)
        and tonumber(rawMeta.schemaVersion) > SCHEMA_VERSION then
        return {blocked=true, reason="future compaction schema is read-only"},false
    end
    local evidenceStore = rawget(database,"loadoutEvidence")
    local evidence = Evidence()
    if type(evidenceStore) == "table" and tonumber(evidenceStore.schemaVersion)
        and evidence and type(evidence.SchemaVersion) == "function"
        and tonumber(evidenceStore.schemaVersion) > evidence.SchemaVersion() then
        return {blocked=true,reason="future evidence schema is read-only"},false
    end
    local meta = Meta(database)
    if (tonumber(meta.version) or 0) >= MIGRATION_VERSION then
        return DeepCopy(meta.last or {migrationVersion=MIGRATION_VERSION}), false
    end
    if active and active.database ~= database then
        CancelPump()
        active = nil
    end
    if not active then
        local ok, state = pcall(NewState,database,meta)
        if not ok then
            meta.lastError = tostring(state):sub(1,500)
            return {blocked=true,reason=meta.lastError},false
        end
        active = state
        meta.inProgress = {version=MIGRATION_VERSION}
        SchedulePump()
    end
    return Compaction.Pump()
end

function Compaction.CollectGarbage(database, dryRun)
    local evidence = Evidence()
    if not (evidence and evidence.CollectGarbage) then
        return {blocked=true, reason="loadout evidence pool unavailable"}
    end
    return evidence.CollectGarbage(database, dryRun == true)
end

function Compaction.Stats(database)
    database = type(database) == "table" and database
        or type(NexusDB) == "table" and NexusDB or {}
    if active and active.database == database then
        return DeepCopy(active.stats)
    end
    local meta = type(database.dataCompaction) == "table"
        and database.dataCompaction or {}
    if type(meta.last) == "table" then return DeepCopy(meta.last) end
    return meta.inProgress and {migrationVersion=MIGRATION_VERSION,
        pending=true,phase="restart"} or {}
end

function Compaction.Version()
    return MIGRATION_VERSION
end
