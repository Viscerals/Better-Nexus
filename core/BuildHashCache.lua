-- Revision-aware cache for Sync's established eight build-hash buckets.
-- This module owns no transport state and cannot enqueue or authorize work.

Nexus = Nexus or {}
local Cache = {}
Nexus.BuildHashCache = Cache

local BUCKETS = 8
local state = {
    initialized=false,
    deltaEntries={}, legacyEntries={}, deltaHashes={}, legacyHashes={},
    deltaDirty={}, legacyDirty={}, revisionSource=nil, observedRevision=nil,
    stats={
        hits=0, collectionWalks=0, fullRebuilds=0,
        deltaBucketRebuilds=0, legacyBucketRebuilds=0,
        targetedInvalidations=0, fullInvalidations=0,
        buildRows=0,tombstoneRows=0,
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

local function Warm()
    local catalog = Catalog()
    if not (catalog and catalog.DeltaSnapshot and catalog.All
        and catalog.TombstoneSnapshot) then return false end
    local deltaReader = catalog.DeltaSummaries or catalog.DeltaSnapshot
    local legacyReader = catalog.Summaries or catalog.All
    local okDelta, delta = pcall(deltaReader)
    local okLegacy, legacy = pcall(legacyReader)
    local okTombs, tombstones = pcall(catalog.TombstoneSnapshot)
    if not okDelta or not okLegacy or not okTombs then return false end

    local deltaEntries, legacyEntries = NewBuckets(), NewBuckets()
    state.stats.collectionWalks = state.stats.collectionWalks + 2
    Fill(deltaEntries, delta, tombstones)
    Fill(legacyEntries, legacy, tombstones)
    local buildRows, tombstoneRows = 0, 0
    for bucket = 1, BUCKETS do
        for key, value in pairs(legacyEntries[bucket]) do
            if value ~= nil then
                if tostring(key):find("^b:") then
                    buildRows = buildRows + 1
                elseif tostring(key):find("^t:") then
                    tombstoneRows = tombstoneRows + 1
                end
            end
        end
    end
    state.stats.buildRows, state.stats.tombstoneRows =
        buildRows, tombstoneRows

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
    if state.initialized then
        state.initialized = false
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
    state.deltaDirty[bucket], state.legacyDirty[bucket] = true, true
    state.stats.targetedInvalidations = state.stats.targetedInvalidations + 1
end

local function OnRevision(_, revision, detail)
    state.observedRevision = revision
    if type(detail) == "table" and detail.scope == "record" and detail.id ~= nil then
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

local function Get(mode)
    EnsureSubscription()
    local revisions = Nexus and Nexus.Revisions
    local current = revisions and revisions.Get
        and revisions.Get(revisions.BUILD_LIBRARY_CHANGED) or nil
    if state.initialized and current ~= nil and state.observedRevision ~= nil
        and current ~= state.observedRevision then
        InvalidateAll()
    end
    if not state.initialized and not Warm() then return nil end

    local dirty = mode == "delta" and state.deltaDirty or state.legacyDirty
    local hashes = mode == "delta" and state.deltaHashes or state.legacyHashes
    local rebuilt = false
    for bucket = 1, BUCKETS do
        if dirty[bucket] then RebuildBucket(mode, bucket); rebuilt = true end
    end
    if not rebuilt then state.stats.hits = state.stats.hits + 1 end
    return table.concat(hashes, ",")
end

function Cache.Delta() return Get("delta") end
function Cache.Legacy() return Get("legacy") end

function Cache.Stats()
    local out = {}
    for key, value in pairs(state.stats) do out[key] = value end
    out.available, out.initialized = true, state.initialized
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
