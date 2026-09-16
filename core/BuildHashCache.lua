-- Revision-aware cache for Sync's established eight build-hash buckets.
-- This module owns no transport state and cannot enqueue or authorize work.

Nexus = Nexus or {}
local Cache = {}
Nexus.BuildHashCache = Cache

local BUCKETS = 8
local HASH_WORK_PER_PUMP = 64
local state = {
    initialized=false,
    deltaEntries={}, legacyEntries={}, deltaHashes={}, legacyHashes={},
    deltaDirty={}, legacyDirty={}, revisionSource=nil, observedRevision=nil,
    warmJob=nil,hashJob=nil,initializing=false,targetRevision=nil,
    tombstoneCounts={},
    stats={
        hits=0, collectionWalks=0, fullRebuilds=0,
        deltaBucketRebuilds=0, legacyBucketRebuilds=0,
        targetedInvalidations=0, fullInvalidations=0,
        buildRows=0,tombstoneRows=0,warmPumps=0,warmRestarts=0,
        hashPumps=0,maxHashWorkPerPump=0,
    },
}

local function Bucket(id)
    local text, hash = tostring(id or ""), 5381
    for i = 1, #text do
        hash = ((hash * 33) + text:byte(i)) % 2147483648
    end
    return (hash % BUCKETS) + 1
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
    return tostring(id) .. ":" .. tostring(build.lastModified or build.postedAt or 0)
        .. ":" .. complete .. ":" .. fingerprint
end

local function TombstoneEntry(id, tombstone)
    if tombstone == nil then return nil end
    return "!" .. tostring(id) .. ":" .. tostring(TombStamp(tombstone))
        .. ":" .. TombAuthor(tombstone)
end

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
    local cursorOk = pcall(catalog.BeginSummaryCursor)
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
    if wasInitialized then
        state.stats.fullInvalidations = state.stats.fullInvalidations + 1
    end
end

local function UpdateRecord(id)
    if not state.initialized then return end
    local catalog = Catalog()
    if not (catalog and catalog.SyncState) then InvalidateAll(); return end
    local ok, record = pcall(catalog.SyncState, id)
    if not ok or type(record) ~= "table" then InvalidateAll(); return end

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
    state.stats.targetedInvalidations = state.stats.targetedInvalidations + 1
end

local function OnRevision(_, revision, detail)
    state.observedRevision = revision
    if state.initializing or state.warmJob then
        InvalidateAll()
    elseif type(detail) == "table" and detail.scope == "record"
        and detail.id ~= nil then
        state.hashJob = nil
        UpdateRecord(detail.id)
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
    if not (catalog and type(catalog.BeginSummaryCursor) == "function"
        and type(catalog.SummaryCursorNext) == "function"
        and type(catalog.TombstoneNext) == "function") then return false end
    local ok, token = pcall(catalog.BeginSummaryCursor)
    if not ok or type(token) ~= "table" then return false end
    local tombstoneCounts = {}
    for bucket = 1, BUCKETS do tombstoneCounts[bucket] = 0 end
    state.warmJob = {
        catalog=catalog,phase="summary",summaryCursor=token,
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
    state.warmJob = nil
end

local function PumpWarmJob()
    local job = state.warmJob
    if not job then return false end
    state.stats.warmPumps = state.stats.warmPumps + 1
    if job.catalog ~= Catalog() or CurrentBuildRevision() ~= job.revision then
        RestartWarmJob()
        return false
    end
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
        end
        if done then job.phase = "tombstone" end
        return false, type(summary) == "table" or done == true
            or progress == "COPY_PENDING"
    end
    local id, tombstone, done =
        job.catalog.TombstoneNext(job.tombstoneCursor)
    if done and id == nil and tombstone ~= nil then
        RestartWarmJob()
        return false
    end
    if done or id == nil then
        FinishWarmCollection(job)
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
    return false, true
end

local function StartHashJob()
    for _, mode in ipairs({"delta", "legacy"}) do
        local dirty = mode == "delta" and state.deltaDirty or state.legacyDirty
        local entries = mode == "delta"
            and state.deltaEntries or state.legacyEntries
        for bucket = 1, BUCKETS do
            if dirty[bucket] then
                state.hashJob = {
                    mode=mode,bucket=bucket,entries=entries[bucket],
                    phase="collect",key=nil,values={},
                }
                return true
            end
        end
    end
    return false
end

local function BeginHashCharacters(job, values)
    job.phase = "hash"
    job.values = values
    job.hash = 5381
    job.valueIndex = 1
    job.characterIndex = 1
end

local function FinishHashJob(job)
    local hashes = job.mode == "delta"
        and state.deltaHashes or state.legacyHashes
    local dirty = job.mode == "delta"
        and state.deltaDirty or state.legacyDirty
    hashes[job.bucket] = #job.values > 0
        and string.format("%x", job.hash) or "0"
    dirty[job.bucket] = nil
    local stat = job.mode == "delta"
        and "deltaBucketRebuilds" or "legacyBucketRebuilds"
    state.stats[stat] = state.stats[stat] + 1
    state.hashJob = nil
end

local function HashJobStep(job)
    if job.phase == "collect" then
        local key, value = next(job.entries, job.key)
        job.key = key
        if key ~= nil then
            if value ~= nil then job.values[#job.values + 1] = value end
            return false
        end
        if #job.values <= 1 then
            BeginHashCharacters(job, job.values)
        else
            job.phase, job.width, job.left = "sort", 1, 1
            job.source, job.target, job.merge = job.values, {}, nil
        end
        return false
    end
    if job.phase == "sort" then
        if not job.merge then
            if job.left > #job.source then
                if job.width >= #job.source then
                    BeginHashCharacters(job, job.source)
                else
                    job.source, job.target = job.target, {}
                    job.width, job.left = job.width * 2, 1
                end
                return false
            end
            local leftEnd = math.min(job.left + job.width - 1, #job.source)
            local rightStart = leftEnd + 1
            job.merge = {
                left=job.left,leftEnd=leftEnd,right=rightStart,
                rightEnd=math.min(job.left + job.width * 2 - 1,
                    #job.source),
            }
        end
        local merge = job.merge
        local takeLeft = merge.right > merge.rightEnd
            or (merge.left <= merge.leftEnd
                and job.source[merge.left] <= job.source[merge.right])
        if takeLeft then
            job.target[#job.target + 1] = job.source[merge.left]
            merge.left = merge.left + 1
        else
            job.target[#job.target + 1] = job.source[merge.right]
            merge.right = merge.right + 1
        end
        if merge.left > merge.leftEnd and merge.right > merge.rightEnd then
            job.left = merge.rightEnd + 1
            job.merge = nil
        end
        return false
    end
    local value = job.values[job.valueIndex]
    if value == nil then
        FinishHashJob(job)
        return true
    end
    if job.characterIndex > #value then
        job.valueIndex = job.valueIndex + 1
        job.characterIndex = 1
        return false
    end
    job.hash = ((job.hash * 33) + value:byte(job.characterIndex))
        % 2147483648
    job.characterIndex = job.characterIndex + 1
    return false
end

local function HashesCurrent()
    for bucket = 1, BUCKETS do
        if state.deltaDirty[bucket] or state.legacyDirty[bucket] then
            return false
        end
    end
    return true
end

function Cache.Pump()
    EnsureSubscription()
    if state.initialized and HashesCurrent() then return true end
    if not state.warmJob and not state.initializing and not state.initialized then
        if not StartWarmJob() then return false end
    end
    if state.warmJob then return PumpWarmJob() end
    local work = 0
    state.stats.hashPumps = state.stats.hashPumps + 1
    while work < HASH_WORK_PER_PUMP do
        if not state.hashJob and not StartHashJob() then break end
        HashJobStep(state.hashJob)
        work = work + 1
    end
    state.stats.maxHashWorkPerPump = math.max(
        state.stats.maxHashWorkPerPump, work)
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
    return (tonumber(state.tombstoneCounts[bucket]) or 0) > 0
end

function Cache.Stats()
    local out = {}
    for key, value in pairs(state.stats) do out[key] = value end
    out.available, out.initialized = true, state.initialized
    out.pending = state.initializing or state.warmJob ~= nil
    out.phase = state.warmJob and state.warmJob.phase
        or state.hashJob and state.hashJob.phase or state.initialized and "ready" or "cold"
    out.preparedRows = state.warmJob and state.warmJob.buildRows or state.stats.buildRows
    out.revision = state.observedRevision
    out.buckets = BUCKETS
    out.dirtyBuckets = 0
    if state.initialized then
        for bucket = 1, BUCKETS do
            if state.deltaDirty[bucket] then
                out.dirtyBuckets = out.dirtyBuckets + 1
            end
        end
    end
    out.digest = state.initialized
        and table.concat(state.deltaHashes or {}, ",") or nil
    return out
end

function Cache.Bucket(id) return Bucket(id) end
