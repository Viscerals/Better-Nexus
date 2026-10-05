-- Revision-aware cache for Sync's established eight build-hash buckets.
-- This module owns no transport state and cannot enqueue or authorize work.

Nexus = Nexus or {}
local Cache = {}
Nexus.BuildHashCache = Cache

local BUCKETS = 8
-- Work per pump (one lifecycle update), stated and counted:
--   WARM_ROWS_PER_PUMP  cursor calls per pump during the collection walk.
--     Each call is bounded by the catalog's own per-call limits (it inspects
--     at most the catalog's one-call row bound and copies at most one bounded
--     summary or one marker). The calls are what this cache bounds; the rows
--     a call inspects are the catalog's bound, reported by the catalog.
--   HASH_WORK_PER_PUMP  units of digest work per pump. One unit is one entry
--     collected from a bucket, one string comparison or one element move of
--     the incremental merge sort, or one hashed byte. A pump stops at the
--     unit that reaches the budget, in whatever bucket, phase or entry it
--     is; the units of every pump are counted (Stats). A collision-heavy
--     bucket (many identities whose IDs share one bucket; removal markers
--     count like builds) takes more pumps, never a larger one.
local WARM_ROWS_PER_PUMP = 32
local HASH_WORK_PER_PUMP = 2048
local MODES = {"delta", "legacy"}
local state = {
    initialized=false,
    deltaEntries={}, legacyEntries={}, deltaHashes={}, legacyHashes={},
    deltaDirty={}, legacyDirty={}, revisionSource=nil, observedRevision=nil,
    warmJob=nil,hashJob=nil,initializing=false,targetRevision=nil,
    -- The source the collected rows were read from: the catalog object, the
    -- database it serves and its binding generation. The rows are valid for
    -- exactly that source. Any other source, or none, answers nothing (and
    -- resets) until a new collection has completed: never old rows, never a
    -- blend of old and new rows.
    source=nil,
    tombstoneCounts={},
    stats={
        hits=0, collectionWalks=0, fullRebuilds=0,
        deltaBucketRebuilds=0, legacyBucketRebuilds=0,
        targetedInvalidations=0, fullInvalidations=0, sourceInvalidations=0,
        buildRows=0,tombstoneRows=0,warmPumps=0,warmRestarts=0,
        hashPumps=0,maxHashWorkPerPump=0,maxWarmRowsPerPump=0,
        -- Digest work units by kind: totals, per-pump maxima, last pump.
        hashCollected=0,hashCompares=0,hashMoves=0,hashBytes=0,sortPasses=0,
        maxCollectedPerPump=0,maxComparesPerPump=0,maxMovesPerPump=0,
        maxBytesPerPump=0,lastPumpWork=0,lastPumpCollected=0,
        lastPumpCompares=0,lastPumpMoves=0,lastPumpBytes=0,
        lastPumpCursorCalls=0,
    },
}

local function Bucket(id)
    local text, hash = tostring(id or ""), 5381
    for i = 1, #text do
        hash = ((hash * 33) + text:byte(i)) % 2147483648
    end
    return (hash % BUCKETS) + 1
end

local function TypedId(id)
    return type(id) .. ":" .. tostring(id)
end

local function TombStamp(value)
    if type(value) == "table" then return tonumber(value.stamp) or 0 end
    return tonumber(value) or 0
end

local function TombAuthor(value)
    return type(value) == "table" and tostring(value.author or "") or ""
end

local function BuildEntry(id, build)
    if type(build) ~= "table" then return nil end
    local complete
    if build.loadoutAvailable ~= nil then
        complete = build.loadoutAvailable == true
    else
        complete = type(build.echoes) == "table" and #build.echoes > 0
    end
    complete = complete and "F" or "S"
    local fingerprint = tostring(build.fingerprintHash or build.fingerprint or "0")
    return TypedId(id) .. ":" .. tostring(build.lastModified or build.postedAt or 0)
        .. ":" .. complete .. ":" .. fingerprint
end

local function TombstoneEntry(id, tombstone)
    if tombstone == nil then return nil end
    return "!" .. TypedId(id) .. ":" .. tostring(TombStamp(tombstone))
        .. ":" .. TombAuthor(tombstone)
end

-- The canonical digest of one bucket: its entries sorted, djb2 over their
-- bytes. The one-call path below computes it at once (at most the one-call
-- row bound of entries); the pumped path computes exactly the same bytes in
-- bounded steps (HashJobStep).
local function HashEntries(entries)
    local ordered, hash = {}, 5381
    for _, value in pairs(entries or {}) do ordered[#ordered + 1] = value end
    table.sort(ordered)
    for _, value in ipairs(ordered) do
        for i = 1, #value do
            hash = ((hash * 33) + value:byte(i)) % 2147483648
        end
    end
    return #ordered > 0 and string.format("%x", hash) or "0"
end

local function NewBuckets()
    local buckets = {}
    for bucket = 1, BUCKETS do buckets[bucket] = {} end
    return buckets
end

local function EntryKey(kind, id)
    return kind .. ":" .. type(id) .. ":" .. tostring(id)
end

local function Fill(buckets, builds, tombstones)
    for id, build in pairs(builds or {}) do
        buckets[Bucket(id)][EntryKey("b", id)] = BuildEntry(id, build)
    end
    for id, tombstone in pairs(tombstones or {}) do
        buckets[Bucket(id)][EntryKey("t", id)] = TombstoneEntry(id, tombstone)
    end
end

local function Catalog()
    return Nexus and Nexus.BuildCatalog
end

------------------------------------------------------------------------
-- Source identity
------------------------------------------------------------------------

-- A catalog this cache can read at all: the retained walk and the targeted
-- record read both need these entry points.
local function CatalogUsable(catalog)
    return type(catalog) == "table"
        and type(catalog.BeginSummaryCursor) == "function"
        and type(catalog.SummaryCursorNext) == "function"
        and type(catalog.TombstoneNext) == "function"
        and type(catalog.SyncState) == "function"
end

-- The identity of the source a collection reads: the catalog object, the
-- database it serves and its binding generation (a rebind of the same
-- object to another root or another binding changes the latter two), and
-- the catalog's own agreement that this root still serves for the current
-- database and owner (ManualPreparationStatus().ownerAgrees). That agreement
-- is the catalog's documented owner/source refusal: it is false once the
-- saved root, one of its maps, the local owner, the binding or another
-- admitted identity drifted from the admitted token
-- (OWNER_OR_GENERATION_MISMATCH), including a saved root replaced underneath
-- the catalog before any rebind was requested, while the bound database the
-- catalog reports is still the old one. It stays true while a same-source
-- transaction is pending (ready=false, CATALOG_COMMIT_PENDING): that root
-- still serves and the cache keeps answering for it. The ready flag alone
-- is therefore not the test. nil, with the refusal reason, when the source
-- cannot be used now.
local function SourceOf(catalog)
    if not CatalogUsable(catalog) then return nil, "CATALOG_UNUSABLE" end
    local database, binding
    if type(catalog.BoundDatabase) == "function" then
        local ok, value = pcall(catalog.BoundDatabase)
        if not ok then return nil, "CATALOG_UNUSABLE" end
        database = value
    end
    if type(catalog.ManualPreparationStatus) == "function" then
        local ok, status = pcall(catalog.ManualPreparationStatus)
        if not ok or type(status) ~= "table" then return nil, "CATALOG_UNUSABLE" end
        if status.ownerAgrees ~= true then
            return nil, tostring(status.reason or "OWNER_OR_GENERATION_MISMATCH")
        end
        binding = status.binding
    end
    return {catalog=catalog, database=database, binding=binding}
end

local function SameSource(source)
    if type(source) ~= "table" then return false end
    local current = SourceOf(Catalog())
    return current ~= nil and current.catalog == source.catalog
        and current.database == source.database
        and current.binding == source.binding
end

local function RebuildBucket(mode, bucket)
    local entries = mode == "delta" and state.deltaEntries or state.legacyEntries
    local hashes = mode == "delta" and state.deltaHashes or state.legacyHashes
    local dirty = mode == "delta" and state.deltaDirty or state.legacyDirty
    hashes[bucket] = HashEntries(entries[bucket])
    dirty[bucket] = nil
    local key = mode == "delta" and "deltaBucketRebuilds"
        or "legacyBucketRebuilds"
    state.stats[key] = state.stats[key] + 1
end

-- The compatibility fast path is legal only when both catalog collections fit
-- their strict one-call bounds. Larger roots are owned by the retained warm
-- job below; this helper never returns a partial collection.
local function CollectRows(catalog)
    if not (catalog and type(catalog.BeginSummaryCursor) == "function"
        and type(catalog.Summaries) == "function"
        and type(catalog.TombstoneSnapshot) == "function") then return nil end
    -- Preserve the established availability/failure probe without consuming
    -- the cursor. The bounded collection calls below own the actual read.
    -- The probe uses this cache's own named slot, so it never supersedes a
    -- multi-frame walk another reader holds on the shared slot.
    local cursorOk = pcall(catalog.BeginSummaryCursor, "build-hash-cache")
    if not cursorOk then return nil end
    local summaries = catalog.Summaries()
    local tombstones = catalog.TombstoneSnapshot()
    if type(summaries) ~= "table" or type(tombstones) ~= "table" then
        return nil
    end
    local delta, legacy = {}, {}
    local total, bytes = 0, 0
    for id, summary in pairs(summaries) do
        total = total + 1
        bytes = bytes + #tostring(BuildEntry(id, summary) or "")
        if total > 8 or bytes > 2048 then return nil end
        legacy[id] = summary
        if summary.syncDelta then delta[id] = summary end
    end
    for id, tombstone in pairs(tombstones) do
        total = total + 1
        bytes = bytes + #tostring(TombstoneEntry(id, tombstone) or "")
        if total > 8 or bytes > 2048 then return nil end
    end
    return delta, legacy, tombstones
end

local function Warm()
    local catalog = Catalog()
    local source = SourceOf(catalog)
    if not source then return false end
    local ok, delta, legacy, tombstones = pcall(CollectRows, catalog)
    if not ok or not delta then return false end

    local deltaEntries, legacyEntries = NewBuckets(), NewBuckets()
    state.stats.collectionWalks = state.stats.collectionWalks + 2
    Fill(deltaEntries, delta, tombstones)
    Fill(legacyEntries, legacy, tombstones)
    local buildRows, tombstoneRows = 0, 0
    local tombstoneCounts = {}
    for bucket = 1, BUCKETS do
        tombstoneCounts[bucket] = 0
        for key, value in pairs(legacyEntries[bucket]) do
            if value ~= nil then
                if tostring(key):find("^b:") then
                    buildRows = buildRows + 1
                elseif tostring(key):find("^t:") then
                    tombstoneRows = tombstoneRows + 1
                    tombstoneCounts[bucket] = tombstoneCounts[bucket] + 1
                end
            end
        end
    end
    state.stats.buildRows, state.stats.tombstoneRows =
        buildRows, tombstoneRows
    state.tombstoneCounts = tombstoneCounts

    state.deltaEntries, state.legacyEntries = deltaEntries, legacyEntries
    state.deltaHashes, state.legacyHashes = {}, {}
    state.deltaDirty, state.legacyDirty = {}, {}
    for bucket = 1, BUCKETS do
        state.deltaDirty[bucket], state.legacyDirty[bucket] = true, true
        RebuildBucket("delta", bucket)
        RebuildBucket("legacy", bucket)
    end
    state.source = source
    state.initialized = true
    state.stats.fullRebuilds = state.stats.fullRebuilds + 1
    local revisions = Nexus and Nexus.Revisions
    state.observedRevision = revisions and revisions.Get
        and revisions.Get(revisions.BUILD_LIBRARY_CHANGED) or nil
    return true
end

local function InvalidateAll()
    local wasInitialized = state.initialized
    state.initialized = false
    state.initializing = false
    state.warmJob = nil
    state.hashJob = nil
    state.targetRevision = nil
    state.source = nil
    if wasInitialized then
        state.stats.fullInvalidations = state.stats.fullInvalidations + 1
    end
end

-- The source the retained rows came from no longer serves, or is not the
-- source serving now: nothing collected is kept.
local function InvalidateSource()
    if state.initialized or state.initializing or state.warmJob then
        state.stats.sourceInvalidations = state.stats.sourceInvalidations + 1
    end
    InvalidateAll()
end

-- One record's entries re-read from the source's current root into the
-- collected buckets (initialized or still hashing), its buckets marked
-- dirty. False when the catalog cannot answer for it; the caller then
-- resets. Only called once SameSource holds.
local function ApplyRecord(id)
    local catalog = state.source and state.source.catalog
    if not (catalog and type(catalog.SyncState) == "function") then return false end
    local ok, record = pcall(catalog.SyncState, id)
    if not ok or type(record) ~= "table" then return false end

    local bucket = Bucket(id)
    local buildKey, tombstoneKey = EntryKey("b", id), EntryKey("t", id)
    local hadBuild = state.legacyEntries[bucket][buildKey] ~= nil
    local hadTombstone = state.legacyEntries[bucket][tombstoneKey] ~= nil
    state.deltaEntries[bucket][buildKey] = BuildEntry(id, record.delta)
    state.legacyEntries[bucket][buildKey] = BuildEntry(id, record.visible)
    local tombstone = TombstoneEntry(id, record.tombstone)
    state.deltaEntries[bucket][tombstoneKey] = tombstone
    state.legacyEntries[bucket][tombstoneKey] = tombstone
    local hasBuild = state.legacyEntries[bucket][buildKey] ~= nil
    local hasTombstone = state.legacyEntries[bucket][tombstoneKey] ~= nil
    state.stats.buildRows = math.max(0,
        (tonumber(state.stats.buildRows) or 0)
            + (hasBuild and 1 or 0) - (hadBuild and 1 or 0))
    state.stats.tombstoneRows = math.max(0,
        (tonumber(state.stats.tombstoneRows) or 0)
            + (hasTombstone and 1 or 0) - (hadTombstone and 1 or 0))
    state.tombstoneCounts[bucket] = math.max(0,
        (tonumber(state.tombstoneCounts[bucket]) or 0)
            + (hasTombstone and 1 or 0) - (hadTombstone and 1 or 0))
    state.deltaDirty[bucket], state.legacyDirty[bucket] = true, true
    -- A hash job on another bucket keeps its place; one on this bucket
    -- would hash stale material (its collection iterates this very table)
    -- and starts over on the next pump.
    if state.hashJob and state.hashJob.bucket == bucket then
        state.hashJob = nil
    end
    state.stats.targetedInvalidations = state.stats.targetedInvalidations + 1
    return true
end

local function UpdateRecord(id)
    if not state.initialized then return end
    if not ApplyRecord(id) then InvalidateAll() end
end

-- A revision while the warm walk reads the catalog: the walk's cursor is
-- stale on the new root, so the walk restarts (counted). The restart itself
-- happens on the next pump, never inside the revision callback.
local function AbandonWarmWalk()
    state.warmJob = nil
    state.hashJob = nil
    state.initializing = false
    state.targetRevision = nil
    state.source = nil
    state.stats.warmRestarts = state.stats.warmRestarts + 1
end

local function OnRevision(_, revision, detail)
    state.observedRevision = revision
    if state.warmJob then
        AbandonWarmWalk()
    elseif state.initializing or state.initialized then
        -- Collected rows exist (being hashed, or ready). A record-scope
        -- revision that names its record, from the same source the rows came
        -- from, is absorbed: that record is re-read from the current root
        -- and only its buckets are hashed again. Anything else (an all-scope
        -- revision, an unnamed record, a source that is not the one the rows
        -- came from, a record the catalog cannot answer for) is unknown
        -- change and resets the preparation: old and new rows never mix.
        local named = type(detail) == "table" and detail.scope == "record"
            and detail.id ~= nil
        if not named or not SameSource(state.source) then
            InvalidateAll()
        elseif state.initializing then
            if ApplyRecord(detail.id) then
                state.targetRevision = revision
            else
                InvalidateAll()
            end
        else
            state.hashJob = nil
            UpdateRecord(detail.id)
        end
    else
        InvalidateAll()
    end
end

local function EnsureSubscription()
    local revisions = Nexus and Nexus.Revisions
    if not (revisions and revisions.Subscribe) then return end
    if state.revisionSource ~= revisions then
        state.revisionSource = revisions
        state.observedRevision = revisions.Get
            and revisions.Get(revisions.BUILD_LIBRARY_CHANGED) or nil
        revisions.Subscribe(revisions.BUILD_LIBRARY_CHANGED, OnRevision)
        InvalidateAll()
    end
end

local function CurrentBuildRevision()
    local revisions = Nexus and Nexus.Revisions
    return revisions and revisions.Get
        and revisions.Get(revisions.BUILD_LIBRARY_CHANGED) or nil
end

local function StartWarmJob()
    local catalog = Catalog()
    local source = SourceOf(catalog)
    if not source then return false end
    -- Its own named slot, so the warm-up and the Community list walk never
    -- cancel each other's cursor.
    local ok, token = pcall(catalog.BeginSummaryCursor, "build-hash-cache")
    if not ok or type(token) ~= "table" then return false end
    local tombstoneCounts = {}
    for bucket = 1, BUCKETS do tombstoneCounts[bucket] = 0 end
    state.warmJob = {
        source=source,catalog=catalog,phase="summary",summaryCursor=token,
        tombstoneCursor=nil,deltaEntries=NewBuckets(),
        legacyEntries=NewBuckets(),buildRows=0,tombstoneRows=0,
        tombstoneCounts=tombstoneCounts,revision=CurrentBuildRevision(),
    }
    state.initializing = true
    state.targetRevision = state.warmJob.revision
    state.stats.collectionWalks = state.stats.collectionWalks + 2
    return true
end

local function RestartWarmJob()
    state.warmJob = nil
    state.hashJob = nil
    state.initializing = false
    state.targetRevision = nil
    state.source = nil
    state.stats.warmRestarts = state.stats.warmRestarts + 1
    return StartWarmJob()
end

local function FinishWarmCollection(job)
    state.deltaEntries, state.legacyEntries =
        job.deltaEntries, job.legacyEntries
    state.deltaHashes, state.legacyHashes = {}, {}
    state.deltaDirty, state.legacyDirty = {}, {}
    for bucket = 1, BUCKETS do
        state.deltaDirty[bucket], state.legacyDirty[bucket] = true, true
    end
    state.stats.buildRows = job.buildRows
    state.stats.tombstoneRows = job.tombstoneRows
    state.tombstoneCounts = job.tombstoneCounts
    state.targetRevision = job.revision
    state.source = job.source
    state.warmJob = nil
end

-- Up to WARM_ROWS_PER_PUMP cursor calls per pump. Each summary call inspects
-- at most the catalog's one-call row bound and copies one bounded summary;
-- each tombstone call reads one marker. The walk finishes, restarts, or
-- yields; it never hands out a partial collection.
local function PumpWarmJob()
    local job = state.warmJob
    if not job then return false end
    state.stats.warmPumps = state.stats.warmPumps + 1
    if not SameSource(job.source) or CurrentBuildRevision() ~= job.revision then
        RestartWarmJob()
        return false
    end
    local steps, progressed = 0, false
    while steps < WARM_ROWS_PER_PUMP do
        steps = steps + 1
        if job.phase == "summary" then
            local summary, done, err, progress =
                job.catalog.SummaryCursorNext(job.summaryCursor)
            if err then
                RestartWarmJob()
                return false
            end
            if type(summary) == "table" then
                local bucket = Bucket(summary.id)
                local key = EntryKey("b", summary.id)
                job.legacyEntries[bucket][key] = BuildEntry(summary.id, summary)
                if summary.syncDelta then
                    job.deltaEntries[bucket][key] = BuildEntry(summary.id, summary)
                end
                job.buildRows = job.buildRows + 1
                progressed = true
            elseif progress == "COPY_PENDING" then
                progressed = true
            end
            if done then job.phase = "tombstone" end
        else
            -- Its own named walk slot, so the synchronous retention sweep
            -- (the shared slot) never invalidates this multi-frame walk.
            local id, tombstone, done =
                job.catalog.TombstoneNext(job.tombstoneCursor, "build-hash-cache")
            if done and id == nil and tombstone ~= nil then
                RestartWarmJob()
                return false
            end
            if done or id == nil then
                FinishWarmCollection(job)
                state.stats.lastPumpCursorCalls = steps
                state.stats.maxWarmRowsPerPump = math.max(
                    state.stats.maxWarmRowsPerPump, steps)
                return false, true
            end
            local bucket = Bucket(id)
            local key = EntryKey("t", id)
            local entry = TombstoneEntry(id, tombstone)
            job.deltaEntries[bucket][key] = entry
            job.legacyEntries[bucket][key] = entry
            job.tombstoneRows = job.tombstoneRows + 1
            job.tombstoneCounts[bucket] = job.tombstoneCounts[bucket] + 1
            job.tombstoneCursor = id
            progressed = true
        end
    end
    state.stats.lastPumpCursorCalls = steps
    state.stats.maxWarmRowsPerPump = math.max(
        state.stats.maxWarmRowsPerPump, steps)
    return false, progressed
end

------------------------------------------------------------------------
-- Bounded digest work
------------------------------------------------------------------------

local function StartHashJob()
    for _, mode in ipairs(MODES) do
        local dirty = mode == "delta" and state.deltaDirty or state.legacyDirty
        local entries = mode == "delta"
            and state.deltaEntries or state.legacyEntries
        for bucket = 1, BUCKETS do
            if dirty[bucket] then
                state.hashJob = {
                    mode=mode,bucket=bucket,entries=entries[bucket],
                    phase="collect",key=nil,values={},count=0,
                }
                return true
            end
        end
    end
    return false
end

local function FinishHashJob(job)
    local hashes = job.mode == "delta"
        and state.deltaHashes or state.legacyHashes
    local dirty = job.mode == "delta"
        and state.deltaDirty or state.legacyDirty
    hashes[job.bucket] = job.count > 0
        and string.format("%x", job.hash) or "0"
    dirty[job.bucket] = nil
    local stat = job.mode == "delta"
        and "deltaBucketRebuilds" or "legacyBucketRebuilds"
    state.stats[stat] = state.stats[stat] + 1
    state.hashJob = nil
end

-- The merge of the pair of runs that starts at `left` in the current pass.
local function StartMerge(job, left)
    local n, width = job.count, job.width
    job.left, job.leftEnd = left, math.min(left + width - 1, n)
    job.right, job.rightEnd = left + width, math.min(left + 2 * width - 1, n)
    job.out = left
    job.take = nil
end

local function StartSort(job)
    job.width = 1
    job.src, job.dst = job.values, {}
    job.sorted = false
    StartMerge(job, 1)
end

local function StartHash(job)
    job.phase = "hash"
    job.hash = 5381
    job.index, job.pos = 1, 0
end

-- One unit of the bottom-up merge sort: one string comparison (which side
-- supplies the next element; the left side on equal strings, so the sort
-- is stable) or one element move into the pass's output. Runs double every
-- pass; the pass's output becomes the next pass's input. The result is the
-- ascending order of the entry strings, the canonical order of the digest.
-- Returns the units spent (always 1).
local function SortUnit(job, counters)
    local src, dst = job.src, job.dst
    if job.take == nil then
        if job.left > job.leftEnd then
            job.take = "right"
        elseif job.right > job.rightEnd then
            job.take = "left"
        else
            counters.compares = counters.compares + 1
            job.take = src[job.right] < src[job.left] and "right" or "left"
            return 1
        end
    end
    if job.take == "left" then
        dst[job.out] = src[job.left]
        job.left = job.left + 1
    else
        dst[job.out] = src[job.right]
        job.right = job.right + 1
    end
    job.out = job.out + 1
    job.take = nil
    counters.moves = counters.moves + 1
    if job.out > job.rightEnd then
        local nextLeft = job.rightEnd + 1
        if nextLeft > job.count then
            -- Pass complete: its output is the next pass's input.
            job.src, job.dst = dst, src
            job.width = job.width * 2
            state.stats.sortPasses = state.stats.sortPasses + 1
            if job.width >= job.count then
                job.sorted = true
                job.values = job.src
            else
                StartMerge(job, 1)
            end
        else
            StartMerge(job, nextLeft)
        end
    end
    return 1
end

-- One pump's share of one bucket's digest: at most `budget` units, each one
-- counted in `counters`. Phases, each resumable at any unit:
--   collect  one entry per unit, the bucket's entries in table order (a
--            targeted update of this bucket discards the job, ApplyRecord);
--   sort     the incremental merge sort above, one compare or move per unit;
--   hash     one byte per unit, djb2 over the sorted entries, resumable
--            inside an entry string.
-- Returns the units spent and whether the bucket's digest is finished.
local function HashJobStep(job, budget, counters)
    local consumed = 0
    while consumed < budget do
        if job.phase == "collect" then
            local key, value = next(job.entries, job.key)
            if key == nil then
                if job.count > 1 then
                    job.phase = "sort"
                    StartSort(job)
                else
                    StartHash(job)
                end
            else
                job.key = key
                if value ~= nil then
                    job.count = job.count + 1
                    job.values[job.count] = value
                end
                consumed = consumed + 1
                counters.collected = counters.collected + 1
            end
        elseif job.phase == "sort" then
            consumed = consumed + SortUnit(job, counters)
            if job.sorted then StartHash(job) end
        else
            local value = job.values[job.index]
            if value == nil then
                FinishHashJob(job)
                return consumed, true
            end
            local hash = job.hash
            local last = math.min(#value, job.pos + (budget - consumed))
            for i = job.pos + 1, last do
                hash = ((hash * 33) + value:byte(i)) % 2147483648
            end
            job.hash = hash
            consumed = consumed + (last - job.pos)
            counters.bytes = counters.bytes + (last - job.pos)
            job.pos = last
            if job.pos >= #value then
                job.index, job.pos = job.index + 1, 0
            end
        end
    end
    return consumed, false
end

local function HashesCurrent()
    for bucket = 1, BUCKETS do
        if state.deltaDirty[bucket] or state.legacyDirty[bucket] then
            return false
        end
    end
    return true
end

local function RecordPumpWork(work, counters)
    local stats = state.stats
    stats.lastPumpWork = work
    stats.lastPumpCollected, stats.lastPumpCompares = counters.collected, counters.compares
    stats.lastPumpMoves, stats.lastPumpBytes = counters.moves, counters.bytes
    stats.hashCollected = stats.hashCollected + counters.collected
    stats.hashCompares = stats.hashCompares + counters.compares
    stats.hashMoves = stats.hashMoves + counters.moves
    stats.hashBytes = stats.hashBytes + counters.bytes
    stats.maxHashWorkPerPump = math.max(stats.maxHashWorkPerPump, work)
    stats.maxCollectedPerPump = math.max(stats.maxCollectedPerPump, counters.collected)
    stats.maxComparesPerPump = math.max(stats.maxComparesPerPump, counters.compares)
    stats.maxMovesPerPump = math.max(stats.maxMovesPerPump, counters.moves)
    stats.maxBytesPerPump = math.max(stats.maxBytesPerPump, counters.bytes)
end

-- Fail closed before any answer: no readable catalog, a source the catalog
-- refuses now (owner/source/generation mismatch), or retained rows from a
-- source that is not the one serving now, leave nothing to serve. A refused
-- source also starts no collection: the next collection waits until the
-- catalog agrees again (the root restored, or the requested rebind done).
local function CheckSource()
    local current, refusal = SourceOf(Catalog())
    state.stats.sourceRefusal = refusal
    if not current then
        InvalidateSource()
        return false
    end
    if (state.initialized or state.initializing) and not state.warmJob
        and not SameSource(state.source) then
        InvalidateSource()
    end
    return true
end

function Cache.Pump()
    EnsureSubscription()
    state.stats.lastPumpWork, state.stats.lastPumpCursorCalls = 0, 0
    state.stats.lastPumpCollected, state.stats.lastPumpCompares = 0, 0
    state.stats.lastPumpMoves, state.stats.lastPumpBytes = 0, 0
    if not CheckSource() then return false end
    if state.initialized and HashesCurrent() then return true end
    if not state.warmJob and not state.initializing and not state.initialized then
        if not StartWarmJob() then return false end
    end
    if state.warmJob then return PumpWarmJob() end
    local work = 0
    local counters = {collected=0, compares=0, moves=0, bytes=0}
    state.stats.hashPumps = state.stats.hashPumps + 1
    while work < HASH_WORK_PER_PUMP do
        if not state.hashJob and not StartHashJob() then break end
        local consumed = HashJobStep(state.hashJob, HASH_WORK_PER_PUMP - work, counters)
        work = work + consumed
    end
    RecordPumpWork(work, counters)
    if not HashesCurrent() then return false, work > 0 end
    if state.initializing then
        if CurrentBuildRevision() ~= state.targetRevision then
            InvalidateAll()
            return false
        end
        state.initializing = false
        state.initialized = true
        state.observedRevision = state.targetRevision
        state.targetRevision = nil
        state.stats.fullRebuilds = state.stats.fullRebuilds + 1
    end
    return state.initialized, work > 0
end

local function BucketWithinOneCall(entries)
    local count, bytes = 0, 0
    for _, value in pairs(entries or {}) do
        count = count + 1
        bytes = bytes + #tostring(value)
        if count > 8 or bytes > 2048 then return false end
    end
    return true
end

local function Get(mode)
    EnsureSubscription()
    if not CheckSource() then return nil end
    local revisions = Nexus and Nexus.Revisions
    local current = revisions and revisions.Get
        and revisions.Get(revisions.BUILD_LIBRARY_CHANGED) or nil
    if state.initialized and current ~= nil and state.observedRevision ~= nil
        and current ~= state.observedRevision then
        InvalidateAll()
    end
    if not state.initialized then
        if state.initializing or state.warmJob then return nil end
        if not Warm() then
            StartWarmJob()
            return nil
        end
    end

    local dirty = mode == "delta" and state.deltaDirty or state.legacyDirty
    local entries = mode == "delta" and state.deltaEntries or state.legacyEntries
    local hashes = mode == "delta" and state.deltaHashes or state.legacyHashes
    local rebuilt = false
    for bucket = 1, BUCKETS do
        if dirty[bucket] then
            if not BucketWithinOneCall(entries[bucket]) then return nil end
            RebuildBucket(mode, bucket)
            rebuilt = true
        end
    end
    if not rebuilt then state.stats.hits = state.stats.hits + 1 end
    return table.concat(hashes, ",")
end

function Cache.Delta() return Get("delta") end
function Cache.Legacy() return Get("legacy") end

function Cache.BucketHasTombstone(bucket)
    bucket = tonumber(bucket)
    if not state.initialized or not bucket or bucket < 1
        or bucket > BUCKETS then return nil end
    if not CheckSource() or not state.initialized then return nil end
    return (tonumber(state.tombstoneCounts[bucket]) or 0) > 0
end

function Cache.Stats()
    local out = {}
    for key, value in pairs(state.stats) do out[key] = value end
    out.available, out.initialized = true, state.initialized
    out.pending = state.initializing or state.warmJob ~= nil
    out.phase = state.warmJob and state.warmJob.phase
        or state.hashJob and state.hashJob.phase
        or state.initializing and "hashing"
        or state.initialized and "ready" or "cold"
    out.preparedRows = state.warmJob and state.warmJob.buildRows or state.stats.buildRows
    out.revision = state.observedRevision
    out.buckets = BUCKETS
    out.warmRowBudget, out.hashWorkBudget = WARM_ROWS_PER_PUMP, HASH_WORK_PER_PUMP
    out.sourceAgrees = state.source ~= nil and SameSource(state.source)
    -- The catalog's current refusal of its source, if any (a passive read).
    local _, refusal = SourceOf(Catalog())
    out.sourceRefusal = refusal
    out.dirtyBuckets = 0
    if state.initialized then
        for bucket = 1, BUCKETS do
            if state.deltaDirty[bucket] then
                out.dirtyBuckets = out.dirtyBuckets + 1
            end
        end
    end
    -- The delta digest as hashed (no computation here; nil until ready).
    out.digest = state.initialized
        and table.concat(state.deltaHashes or {}, ",") or nil
    return out
end

function Cache.Bucket(id) return Bucket(id) end
