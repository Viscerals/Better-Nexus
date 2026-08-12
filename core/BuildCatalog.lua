-- Nexus: merged view of the immutable release catalog and SavedVariables
-- community-build overlay.

Nexus = Nexus or {}
local Catalog = {}
Nexus.BuildCatalog = Catalog

local STORAGE_SCHEMA_VERSION = 1
local db
local bundled
local baseline = {}
local initialized = false
local catalogReadOnly = false
local lastInitSummary
local libraryGeneration = 0
local authorIndex, authorIndexGeneration = {}, -1
local debugStats = {
    initCalls=0, rebinds=0, fastPathHits=0, revisionSnapshots=0,
    authorIndexRebuilds=0, summarySnapshots=0,
}

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

local function Revision(build)
    if type(build) ~= "table" then return -math.huge end
    return tonumber(build.lastModified or build.postedAt) or 0
end

local function HasLocalMarker(build)
    return type(build) == "table"
        and (build.isMine == true or build.importedSavedBuild == true)
end

local function IsPersonal(build)
    if type(build) ~= "table" then return false end
    if HasLocalMarker(build) then return true end
    if type(build.ownerKey) ~= "string" then return false end
    local name = UnitName and UnitName("player") or nil
    if not name or name == "" or name == "Unknown" then return false end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then realm = GetRealmName and GetRealmName() end
    realm = tostring(realm or "unknown"):lower():gsub("%s+", "")
    local current = tostring(name):lower():gsub("^%s+", ""):gsub("%s+$", "")
        .. "@" .. realm
    return build.ownerKey:lower() == current
end

local function DurableBuild(build)
    if type(build) ~= "table" then return nil end
    -- Overlay rows may be pool-only after DataCompaction. Release-baseline
    -- comparisons still operate on the established materialized build shape
    -- so a later catalog version can prune an exact redundant overlay.
    if type(build.echoes) ~= "table" then
        local evidence = Nexus and Nexus.LoadoutEvidence
        if evidence and type(evidence.ResolveBuildRow) == "function" then
            local ok, resolved = pcall(evidence.ResolveBuildRow, build)
            if ok and type(resolved) == "table" then build = resolved end
        end
    end
    local echoes = {}
    local echoCount = 0
    for _, echo in ipairs(type(build.echoes) == "table" and build.echoes or {}) do
        if type(echo) ~= "table" then return nil end
        echoes[#echoes + 1] = {
            spellId=tonumber(echo.spellId or echo.id),
            quality=tonumber(echo.quality) or 0,
            stacks=tonumber(echo.stacks or echo.count) or 1,
            locked=echo.locked and true or nil,
        }
        echoCount = echoCount + (tonumber(echo.stacks or echo.count) or 1)
    end
    table.sort(echoes, function(left, right)
        if left.spellId ~= right.spellId then
            return (left.spellId or 0) < (right.spellId or 0)
        end
        if left.quality ~= right.quality then
            return left.quality < right.quality
        end
        if left.locked ~= right.locked then return left.locked ~= true end
        return left.stacks < right.stacks
    end)
    local function HashText(text)
        if type(text) ~= "string" or text == "" then return nil end
        local hash = 5381
        for i = 1, #text do
            hash = ((hash * 33) + text:byte(i)) % 2147483648
        end
        return string.format("%x", hash)
    end
    local fingerprintHash = build.fingerprintHash
        or HashText(build.fingerprint)
    local linkHash = build.link
        and (build.linkHash or HashText(build.link)) or nil
    return {
        id=build.id,
        title=build.title,
        description=build.description or "",
        author=build.author,
        ownerKey=type(build.ownerKey) == "string" and build.ownerKey:lower() or nil,
        class=type(build.class) == "string" and build.class:upper() or build.class,
        echoes=echoes,
        postedAt=tonumber(build.postedAt or build.lastModified),
        lastModified=tonumber(build.lastModified or build.postedAt),
        autoDps=build.autoDps and true or nil,
        fingerprint=build.fingerprint,
        fingerprintHash=type(fingerprintHash) == "string"
            and fingerprintHash:lower() or fingerprintHash,
        echoCount=tonumber(build.echoCount) or echoCount,
        loadoutAvailable=(build.loadoutAvailable == true or #echoes > 0)
            and true or nil,
        link=build.link,
        linkHash=linkHash,
    }
end

local function BaselineEquivalent(record, base)
    if DeepEqual(record, base) then return true end
    return DeepEqual(DurableBuild(record), DurableBuild(base))
end

local function Count(source)
    local count = 0
    for _ in pairs(source or {}) do count = count + 1 end
    return count
end

local function BumpBuild(reason, id)
    libraryGeneration = libraryGeneration + 1
    local revisions = Nexus and Nexus.Revisions
    if revisions and type(revisions.Advance) == "function" then
        pcall(revisions.Advance, revisions.BUILD_LIBRARY_CHANGED, {
            reason=reason,
            scope=id ~= nil and "record" or "all",
            id=id,
        })
    end
end

local function EnsureBound()
    if not db or (type(NexusDB) == "table" and NexusDB ~= db) then
        Catalog.Init(NexusDB or {}, Nexus.BundledBuilds)
    end
end

local function Overlay()
    EnsureBound()
    if type(db.communityBuilds) == "table" then return db.communityBuilds end
    if catalogReadOnly then return {} end
    db.communityBuilds = {}
    return db.communityBuilds
end

local function Tombstones()
    EnsureBound()
    if type(db.syncTombstones) == "table" then return db.syncTombstones end
    if catalogReadOnly then return {} end
    db.syncTombstones = {}
    return db.syncTombstones
end

local function SelectedRaw(id)
    local tombstones = db and type(db.syncTombstones) == "table"
        and db.syncTombstones or {}
    local overlay = db and type(db.communityBuilds) == "table"
        and db.communityBuilds or {}
    if tombstones[id] ~= nil then return nil, "tombstone" end
    local base = baseline[id]
    local over = overlay[id]
    if type(over) == "table" then
        if type(base) ~= "table" or IsPersonal(over)
            or Revision(over) >= Revision(base) then
            return over, "overlay"
        end
    end
    if type(base) == "table" then return base, "bundled" end
    if type(over) == "table" then return over, "overlay" end
    return nil, nil
end


local function Selected(id)
    EnsureBound()
    return SelectedRaw(id)
end

local function PublicRecord(record, source)
    if type(record) ~= "table" then return nil end
    local evidence = Nexus and Nexus.LoadoutEvidence
    if source == "overlay" and evidence
        and type(evidence.ResolveBuildRow) == "function" then
        local ok, resolved = pcall(evidence.ResolveBuildRow, record)
        if ok and type(resolved) == "table" then return resolved end
    end
    return DeepCopy(record)
end

local function RevisionRecord(id)
    local record, source = SelectedRaw(id)
    local tombstones = db and type(db.syncTombstones) == "table"
        and db.syncTombstones or {}
    return {
        visible=PublicRecord(record, source),
        source=source,
        delta=source == "overlay" and PublicRecord(record, source) or nil,
        tombstone=DeepCopy(tombstones[id]),
    }
end

local function RevisionSnapshot()
    debugStats.revisionSnapshots = debugStats.revisionSnapshots + 1
    local rows, seen = {}, {}
    for id in pairs(baseline or {}) do
        seen[id] = true
        rows[id] = RevisionRecord(id)
    end
    local overlay = db and type(db.communityBuilds) == "table"
        and db.communityBuilds or {}
    for id in pairs(overlay) do
        if not seen[id] then
            seen[id] = true
            rows[id] = RevisionRecord(id)
        end
    end
    local tombstones = db and type(db.syncTombstones) == "table"
        and db.syncTombstones or {}
    for id in pairs(tombstones) do
        if not seen[id] then rows[id] = RevisionRecord(id) end
    end
    return {
        catalogVersion=bundled and tostring(bundled.catalogVersion or "unversioned") or nil,
        rows=rows,
    }
end

local function SummaryValue(value)
    if type(value) == "table" then return DeepCopy(value) end
    return value
end

local SUMMARY_FIELDS = {
    "id", "title", "description", "author", "ownerKey", "class",
    "postedAt", "lastModified", "importedSavedBuild", "isMine",
    "destinationWishlistName", "destinationProgress", "destinationTotal",
    "recordBuildId", "publishedBuildId", "autoDps", "fingerprint",
    "fingerprintHash", "needsFullBuild", "ownerVerified",
}

-- Browser/hash consumers need identity and display metadata, not tens of
-- thousands of nested Echo rows. Keep this projection defensive while
-- deliberately excluding `echoes`; visible cards hydrate exact rows via Get.
local function SummaryRecord(record)
    if type(record) ~= "table" then return nil end
    local out = {}
    for _, key in ipairs(SUMMARY_FIELDS) do
        if record[key] ~= nil then out[key] = SummaryValue(record[key]) end
    end
    local count = tonumber(record.echoCount)
    local hasEchoes = type(record.echoes) == "table" and #record.echoes > 0
    if count == nil and hasEchoes then
        count = 0
        for _, echo in ipairs(record.echoes) do
            count = count + (tonumber(echo.stacks or echo.count) or 1)
        end
    end
    out.echoCount = count or 0
    if record.loadoutAvailable ~= nil then
        out.loadoutAvailable = record.loadoutAvailable == true
    else
        out.loadoutAvailable = hasEchoes
            or (type(record.evidenceKey) == "string" and record.evidenceKey ~= "")
    end
    return out
end

local function SummarySnapshot(deltaOnly)
    EnsureBound()
    debugStats.summarySnapshots = debugStats.summarySnapshots + 1
    local out, seen = {}, {}
    if not deltaOnly then
        for id in pairs(baseline) do
            seen[id] = true
            local record = SelectedRaw(id)
            if record then out[id] = SummaryRecord(record) end
        end
    end
    local overlay = db and type(db.communityBuilds) == "table"
        and db.communityBuilds or {}
    for id in pairs(overlay) do
        if deltaOnly or not seen[id] then
            local record, source = SelectedRaw(id)
            if record and (not deltaOnly or source == "overlay") then
                out[id] = SummaryRecord(record)
            end
        end
    end
    return out
end

local function MergedCountRaw()
    local count, seen = 0, {}
    for id in pairs(baseline) do
        seen[id] = true
        if SelectedRaw(id) then count = count + 1 end
    end
    local overlay = db and type(db.communityBuilds) == "table"
        and db.communityBuilds or {}
    for id in pairs(overlay) do
        if not seen[id] and SelectedRaw(id) then count = count + 1 end
    end
    return count
end

local function BumpIfChanged(before, after, reason, id)
    if not DeepEqual(before, after) then BumpBuild(reason, id) end
end

local function PruneOverlay(overlay)
    local redundant = 0
    for id, record in pairs(overlay) do
        local base = baseline[id]
        if type(record) == "table" and type(base) == "table"
            and not HasLocalMarker(record)
            and BaselineEquivalent(record, base) then
            overlay[id] = nil
            redundant = redundant + 1
        end
    end
    return redundant
end

function Catalog.Init(database, bundle)
    debugStats.initCalls = debugStats.initCalls + 1
    local nextDb = type(database) == "table" and database or {}
    local nextBundled = type(bundle) == "table" and bundle
        or type(Nexus.BundledBuilds) == "table" and Nexus.BundledBuilds
        or {}
    local nextBaseline = type(nextBundled.builds) == "table"
        and nextBundled.builds or {}
    if initialized and db == nextDb and bundled == nextBundled
        and baseline == nextBaseline then
        debugStats.fastPathHits = debugStats.fastPathHits + 1
        local summary = DeepCopy(lastInitSummary)
        summary.migrated = false
        summary.redundantRemoved = 0
        return summary
    end

    debugStats.rebinds = debugStats.rebinds + 1
    local before = initialized and RevisionSnapshot() or nil
    db, bundled, baseline = nextDb, nextBundled, nextBaseline
    local existingMeta = type(db.buildCatalog) == "table"
        and db.buildCatalog or nil
    local storedSchemaVersion = existingMeta
        and tonumber(existingMeta.schemaVersion) or nil
    catalogReadOnly = storedSchemaVersion ~= nil
        and storedSchemaVersion > STORAGE_SCHEMA_VERSION

    -- A future schema may attach meaning to fields this build does not know.
    -- Keep its metadata and overlay byte-for-byte and expose only read access;
    -- downgrading must never prune or restamp data owned by a newer client.
    if not catalogReadOnly then
        db.communityBuilds = type(db.communityBuilds) == "table"
            and db.communityBuilds or {}
        db.syncTombstones = type(db.syncTombstones) == "table"
            and db.syncTombstones or {}
        db.buildCatalog = type(db.buildCatalog) == "table"
            and db.buildCatalog or {}
    end
    if Nexus.LoadoutEvidence and Nexus.LoadoutEvidence.Init then
        Nexus.LoadoutEvidence.Init(db)
    end

    local meta = type(db.buildCatalog) == "table" and db.buildCatalog or {}
    local catalogVersion = tostring(bundled.catalogVersion or "unversioned")
    local needsMigration = not catalogReadOnly
        and (tonumber(meta.schemaVersion) ~= STORAGE_SCHEMA_VERSION
            or tostring(meta.catalogVersion or "") ~= catalogVersion)
    local redundant = 0
    if needsMigration then
        redundant = PruneOverlay(db.communityBuilds)
        meta.schemaVersion = STORAGE_SCHEMA_VERSION
        meta.catalogVersion = catalogVersion
        meta.sourceVersion = tostring(bundled.sourceVersion or "unknown")
    end

    local overlay = type(db.communityBuilds) == "table"
        and db.communityBuilds or {}
    local tombstones = type(db.syncTombstones) == "table"
        and db.syncTombstones or {}
    local bundledCount = Count(baseline)
    local overlayCount = Count(overlay)
    local tombstoneCount = Count(tombstones)
    local merged = MergedCountRaw()
    initialized = true
    if before then
        BumpIfChanged(before, RevisionSnapshot(), "catalog initialized")
    elseif bundledCount > 0 or overlayCount > 0 or tombstoneCount > 0 then
        BumpBuild("catalog initialized")
    end
    lastInitSummary = {
        migrated = needsMigration,
        bundled = bundledCount,
        overlay = overlayCount,
        tombstones = tombstoneCount,
        merged = merged,
        redundantRemoved = redundant,
        schemaVersion = catalogReadOnly
            and meta.schemaVersion or STORAGE_SCHEMA_VERSION,
        catalogVersion = catalogVersion,
        readOnly = catalogReadOnly,
    }
    return DeepCopy(lastInitSummary)
end

function Catalog.Get(id)
    EnsureBound()
    local record, source = Selected(id)
    return PublicRecord(record, source), source
end

function Catalog.All()
    EnsureBound()
    local out = {}
    for id in pairs(baseline) do
        local record, source = Selected(id)
        if record then out[id] = PublicRecord(record, source) end
    end
    for id in pairs(Overlay()) do
        if out[id] == nil then
            local record, source = Selected(id)
            if record then out[id] = PublicRecord(record, source) end
        end
    end
    return out
end

function Catalog.Summaries()
    return SummarySnapshot(false)
end

function Catalog.DeltaSummaries()
    return SummarySnapshot(true)
end

local function AuthorKey(value)
    if type(value) ~= "string" or value == "" then return nil end
    local name = value:match("^([^%-]+)") or value
    name = name:lower()
    return name ~= "" and name or nil
end

local function RebuildAuthorIndex()
    local nextIndex, seen = {}, {}
    for id in pairs(baseline) do
        seen[id] = true
        local record = SelectedRaw(id)
        local key = record and AuthorKey(record.author)
        if key then nextIndex[key] = true end
    end
    for id in pairs(db and db.communityBuilds or {}) do
        if not seen[id] then
            local record = SelectedRaw(id)
            local key = record and AuthorKey(record.author)
            if key then nextIndex[key] = true end
        end
    end
    authorIndex = nextIndex
    authorIndexGeneration = libraryGeneration
    debugStats.authorIndexRebuilds = debugStats.authorIndexRebuilds + 1
end

function Catalog.IsAuthor(name)
    EnsureBound()
    local key = AuthorKey(name)
    if not key then return false end
    if authorIndexGeneration ~= libraryGeneration then RebuildAuthorIndex() end
    return authorIndex[key] == true
end

function Catalog.DebugStats()
    return DeepCopy(debugStats)
end

function Catalog.ForEach(visitor)
    if type(visitor) ~= "function" then return 0 end
    local all = Catalog.All()
    local count = 0
    for id, record in pairs(all) do
        count = count + 1
        visitor(id, record)
    end
    return count
end

function Catalog.Count()
    EnsureBound()
    return MergedCountRaw()
end

function Catalog.Put(record)
    EnsureBound()
    if catalogReadOnly then
        return false, "future build catalog schema is read-only"
    end
    if type(record) ~= "table" or record.id == nil then
        return false, "build id required"
    end
    local id = record.id
    local before = RevisionRecord(id)
    local copy = DeepCopy(record)
    local storedAs
    if type(baseline[id]) == "table" and not IsPersonal(copy)
        and BaselineEquivalent(copy, baseline[id]) then
        Overlay()[id] = nil
        storedAs = "baseline"
    else
        local overlay = Overlay()
        local evidence = Nexus and Nexus.LoadoutEvidence
        local compaction = Nexus and Nexus.DataCompaction
        local compacted = false
        if compaction and type(compaction.Enabled) == "function"
            and compaction.Enabled(db)
            and type(compaction.CompactBuildRow) == "function" then
            compacted = pcall(compaction.CompactBuildRow, copy)
        end
        if not compacted and evidence and type(evidence.Reference) == "function"
            and type(copy.echoes) == "table" and #copy.echoes > 0 then
            pcall(evidence.Reference, copy, "echoes", "evidenceKey")
        end
        local current = overlay[id]
        -- Preserve the legacy overlay table identity for compatibility with
        -- callers that already hold a SavedVariables row, while still storing
        -- only our defensive copy rather than the caller-owned table.
        if type(current) == "table" then
            for key in pairs(current) do current[key] = nil end
            for key, value in pairs(copy) do current[key] = value end
        else
            overlay[id] = copy
        end
        storedAs = "overlay"
    end
    BumpIfChanged(before, RevisionRecord(id), "build put", id)
    return true, storedAs
end

function Catalog.RemoveOverlay(id)
    EnsureBound()
    if catalogReadOnly then
        return false, "future build catalog schema is read-only"
    end
    local before = RevisionRecord(id)
    local existed = Overlay()[id] ~= nil
    Overlay()[id] = nil
    BumpIfChanged(before, RevisionRecord(id), "overlay removed", id)
    return existed
end

-- Retention removes only SavedVariables overlay rows; it never creates a
-- network-visible delete or touches the immutable release catalog.  Batch the
-- revision notification so pruning hundreds of stale rows does not rebuild
-- hash/view projections once per row during login.
function Catalog.RemoveOverlayBatch(ids)
    EnsureBound()
    if catalogReadOnly then
        return 0, "future build catalog schema is read-only"
    end
    if type(ids) ~= "table" then return 0, "build id list required" end
    local overlay = Overlay()
    local removed = 0
    for _, id in ipairs(ids) do
        if overlay[id] ~= nil then
            overlay[id] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then BumpBuild("overlay retention", nil) end
    return removed
end

function Catalog.SetTombstone(id, tombstone)
    EnsureBound()
    if catalogReadOnly then
        return false, "future build catalog schema is read-only"
    end
    if id == nil or tombstone == nil then return false end
    local before = RevisionRecord(id)
    Tombstones()[id] = DeepCopy(tombstone)
    Overlay()[id] = nil
    BumpIfChanged(before, RevisionRecord(id), "build tombstoned", id)
    return true
end

function Catalog.ClearTombstone(id)
    EnsureBound()
    if catalogReadOnly then
        return false, "future build catalog schema is read-only"
    end
    local before = RevisionRecord(id)
    local existed = Tombstones()[id] ~= nil
    Tombstones()[id] = nil
    BumpIfChanged(before, RevisionRecord(id), "tombstone cleared", id)
    return existed
end

-- A tombstone that masks an immutable bundled row cannot be compacted without
-- making that row visible again.  DataRetention uses this query to keep those
-- exact tombstones indefinitely.
function Catalog.HasBaseline(id)
    EnsureBound()
    return type(baseline[id]) == "table"
end

function Catalog.RemoveTombstonesBatch(ids)
    EnsureBound()
    if catalogReadOnly then
        return 0, "future build catalog schema is read-only"
    end
    if type(ids) ~= "table" then return 0, "tombstone id list required" end
    local source = Tombstones()
    local removed = 0
    for _, id in ipairs(ids) do
        if source[id] ~= nil and type(baseline[id]) ~= "table" then
            source[id] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then BumpBuild("tombstone retention", nil) end
    return removed
end

function Catalog.OverlaySnapshot()
    local out = {}
    for id, record in pairs(Overlay()) do
        out[id] = PublicRecord(record, "overlay")
    end
    return out
end

-- Only rows that currently win merged selection belong in release-aware sync
-- deltas. A stale SavedVariables row hidden by a newer bundled row must not
-- make same-release peers exchange obsolete data.
function Catalog.DeltaSnapshot()
    EnsureBound()
    local out = {}
    for id in pairs(Overlay()) do
        local record, source = Selected(id)
        if source == "overlay" and record then
            out[id] = PublicRecord(record, source)
        end
    end
    return out
end

-- Sync-facing bounded cursor. Each call examines at most one overlay row and
-- returns a defensive, evidence-resolved record only when that row currently
-- wins merged selection. Callers keep the opaque id cursor and never reach
-- into SavedVariables or the bundled baseline directly.
function Catalog.SyncDeltaNext(cursor)
    EnsureBound()
    local id = next(Overlay(), cursor)
    if id == nil then return nil, nil, true end
    local record, source = Selected(id)
    if source == "overlay" and record then
        return id, PublicRecord(record, source), false
    end
    return id, nil, false
end

function Catalog.TombstoneSnapshot()
    return DeepCopy(Tombstones())
end

-- One-record Sync-facing state for incremental hash maintenance. Consumers
-- receive defensive copies and cannot mutate the baseline or SavedVariables.
function Catalog.SyncState(id)
    EnsureBound()
    local record, source = Selected(id)
    return {
        id=id,
        visible=PublicRecord(record, source),
        delta=source == "overlay" and PublicRecord(record, source) or nil,
        tombstone=DeepCopy(Tombstones()[id]),
        catalogVersion=tostring(bundled.catalogVersion or "unversioned"),
    }
end

function Catalog.CatalogVersion()
    EnsureBound()
    return tostring(bundled.catalogVersion or "unversioned")
end

function Catalog.SchemaVersion()
    return STORAGE_SCHEMA_VERSION
end
