-- Nexus: merged view of the immutable release catalog and SavedVariables
-- community-build overlay.

Nexus = Nexus or {}
local Identity = assert(Nexus.Identity,
    "Nexus Identity must load before BuildCatalog")
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
local relatedIndex = {
    exact={},fingerprints={},titles={},spells={},saved={},ownerClasses={}}
local relatedRows, relatedIndexGeneration = {}, -1
local recordEpoch, exactEpoch, exactRevisionClock = 0, 0, 0
local recordRevisions, exactRevisions = {}, {}
-- Cache only complete verdicts so a pool-only pending row can become complete
-- as soon as its evidence arrives. StoreRecord invalidates a preserved overlay
-- identity before replacing that table's contents in place.
local ordinaryVerdictCache = setmetatable({}, {__mode="k"})
local debugStats = {
    initCalls=0, rebinds=0, fastPathHits=0, revisionSnapshots=0,
    authorIndexRebuilds=0, summarySnapshots=0, relatedIndexRebuilds=0,
    relatedLookups=0, relatedCandidates=0, maxRelatedCandidates=0,
    putCalls=0,putChanges=0,compactionCalls=0,compactionWrites=0,
    referenceCalls=0,referenceStores=0,relatedIndexUpdates=0,
    savedMirrorEnumerations=0,savedMirrorRows=0,
    exactLookups=0,exactCandidates=0,maxExactCandidates=0,
    identityResolutions=0,identityResolutionFailures=0,
    identityRawHits=0,identityFingerprintHits=0,
    ownerClassLookups=0,ownerClassHits=0,ownerClassConflicts=0,
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
    local current = Identity.OwnerKey(name, realm or "unknown")
    return current ~= nil
        and Identity.CanonicalOwnerKey(build.ownerKey) == current
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
        ownerKey=type(build.ownerKey) == "string"
            and Identity.CanonicalOwnerKey(build.ownerKey) or nil,
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

local function HasStringClass(record)
    return type(record) == "table"
        and type(record.class) == "string"
        and record.class ~= ""
end

local VALID_CLASS = {
    WARRIOR=true,PALADIN=true,HUNTER=true,ROGUE=true,PRIEST=true,
    DEATHKNIGHT=true,SHAMAN=true,MAGE=true,WARLOCK=true,DRUID=true,
}

local function NormalizedClass(value)
    value = type(value) == "string" and value:upper() or nil
    return value and VALID_CLASS[value] and value or nil
end

local function OrdinaryComplete(record)
    if type(record) ~= "table" then return false, nil end
    local cached = ordinaryVerdictCache[record]
    if cached then return true, cached end
    local evidence = Nexus and Nexus.LoadoutEvidence
    if not (evidence and type(evidence.OrdinaryCompleteness) == "function") then
        return false, nil
    end
    local resolver = type(evidence.PublicOrdinaryCompleteness) == "function"
        and evidence.PublicOrdinaryCompleteness
        or evidence.OrdinaryCompleteness
    local ok, verdict = pcall(resolver, record)
    local complete = ok and type(verdict) == "table"
        and verdict.complete == true
    if complete then
        ordinaryVerdictCache[record] = {
            complete=true,reason="complete",
            evidenceKey=verdict.evidenceKey,
            fingerprint=verdict.fingerprint,
            echoCount=verdict.echoCount,
            lockedOnly=verdict.lockedOnly,
        }
    end
    return complete, complete and ordinaryVerdictCache[record]
        or (ok and verdict or nil)
end

local function SyncEligible(record)
    if type(record) ~= "table"
        or record.ownerVerified == false
        or (record.legacyRecovered == true
            and record.ownerVerified ~= true) then return false end
    return OrdinaryComplete(record)
end

local function BumpBuild(reason, id)
    libraryGeneration = libraryGeneration + 1
    if id ~= nil then
        recordRevisions[id] = (recordRevisions[id] or 0) + 1
    else
        recordEpoch = recordEpoch + 1
        exactEpoch = exactEpoch + 1
    end
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

local function StatusState(id)
    local overlay = db and type(db.communityBuilds) == "table"
        and db.communityBuilds or {}
    local tombstones = db and type(db.syncTombstones) == "table"
        and db.syncTombstones or {}
    return {
        overlay=overlay[id] ~= nil,
        tombstone=tombstones[id] ~= nil,
        available=SelectedRaw(id) ~= nil,
    }
end

local function ApplyStatusDeltas(overlay, tombstones, available)
    if type(lastInitSummary) ~= "table" then return end
    lastInitSummary.overlay = math.max(0,
        (tonumber(lastInitSummary.overlay) or 0) + overlay)
    lastInitSummary.tombstones = math.max(0,
        (tonumber(lastInitSummary.tombstones) or 0) + tombstones)
    lastInitSummary.merged = math.max(0,
        (tonumber(lastInitSummary.merged) or 0) + available)
end

local function AdjustStatus(before, after)
    before = type(before) == "table" and before or {}
    after = type(after) == "table" and after or {}
    local function Delta(key)
        return (after[key] and 1 or 0) - (before[key] and 1 or 0)
    end
    local overlay, tombstones, available = Delta("overlay"),
        Delta("tombstone"), Delta("available")
    ApplyStatusDeltas(overlay, tombstones, available)
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
    local complete, verdict = OrdinaryComplete(record)
    out.echoCount = complete and (tonumber(verdict.echoCount) or 0) or 0
    out.loadoutAvailable = complete
    out.ordinaryComplete = complete
    out.ordinaryCompletenessReason = type(verdict) == "table"
        and verdict.reason or "unavailable"
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
            if record and (not deltaOnly or source == "overlay")
                and (not deltaOnly or SyncEligible(record)) then
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

local function StoredRecord(id)
    local record, source = SelectedRaw(id)
    return {
        visible=DeepCopy(record),source=source,
        delta=source == "overlay" and DeepCopy(record) or nil,
        tombstone=DeepCopy(db and type(db.syncTombstones) == "table"
            and db.syncTombstones[id] or nil),
    }
end

local function RelatedText(value)
    return tostring(value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function RelatedFingerprint(record)
    if type(record) ~= "table" then return nil end
    local stored = type(record.fingerprint) == "string"
        and record.fingerprint ~= "" and record.fingerprint or nil
    local echoes = record.echoes
    if type(echoes) ~= "table" and not stored then
        -- DataCompaction may replace inline Echoes with an evidence reference.
        -- Resolve it only while maintaining the index; exact hot-path lookup
        -- remains a scalar bucket read and never materializes the catalog.
        local evidence = Nexus and Nexus.LoadoutEvidence
        if evidence and type(evidence.ResolveBuildRow) == "function" then
            local ok, resolved = pcall(evidence.ResolveBuildRow, record)
            if ok and type(resolved) == "table" then echoes = resolved.echoes end
        end
    end
    local counts = {}
    for _, echo in ipairs(type(echoes) == "table" and echoes or {}) do
        if not echo.locked then
            local id = tonumber(echo.spellId or echo.id)
            -- Keep exact identity byte-for-byte aligned with DpsCapture's
            -- established NormalizeEchoes precedence.
            local count = tonumber(echo.count or echo.stacks or echo.stack) or 1
            if id and id == id and id > 0 and id < math.huge
                and id == math.floor(id)
                and count == count and count > 0 and count < math.huge
                and count == math.floor(count) then
                counts[id] = (counts[id] or 0) + count
            end
        end
    end
    local ids = {}
    for id in pairs(counts) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        parts[#parts + 1] = tostring(id) .. "x" .. tostring(counts[id])
    end
    -- Match the established exhaustive scorer: represented Echo rows are
    -- authoritative when present, while compacted/fingerprint-only records
    -- retain their durable stored identity.
    return #parts > 0 and table.concat(parts, ",") or stored
end

local function ExactFingerprint(record)
    if type(record) ~= "table" then return nil end
    -- Preserve DpsCapture's established exhaustive-match precedence for
    -- historical rows: an explicit stored identity wins over reconstructed
    -- Echoes. Rows without one use the same finite canonical reconstruction
    -- as the maintained related index, including compacted evidence.
    local stored = type(record.fingerprint) == "string"
        and record.fingerprint ~= "" and record.fingerprint or nil
    return stored or RelatedFingerprint(record)
end

local function FingerprintSpells(fingerprint)
    local spells, total = {}, 0
    if type(fingerprint) ~= "string" then return spells, total end
    for rawId, rawCount in fingerprint:gmatch("(%d+)x(%d+)") do
        local id, count = tonumber(rawId), tonumber(rawCount)
        if id and count and count > 0 then
            spells[#spells + 1] = id
            total = total + count
        end
    end
    return spells, total
end

local function RelatedKey(author, value)
    author, value = Identity.PlayerKey(author) or RelatedText(author),
        tostring(value or "")
    if author == "" or value == "" then return nil end
    return author .. "\0" .. value
end

local function AddBucket(index, key, id)
    if not key then return end
    local bucket = index[key]
    if not bucket then bucket = {ids={},count=0}; index[key] = bucket end
    local added = false
    if not bucket.ids[id] then
        bucket.ids[id] = true
        bucket.count = bucket.count + 1
        added = true
    end
    return bucket, added
end

local function RemoveBucket(index, key, id)
    local bucket = key and index[key]
    if not bucket then return end
    if bucket.ids[id] then
        bucket.ids[id] = nil
        bucket.count = math.max(0, bucket.count - 1)
    end
    if bucket.count == 0 then index[key] = nil end
end

local function AddOwnerClass(record, id)
    if type(record) ~= "table" or record.ownerVerified ~= true then return nil end
    local key = Identity.CanonicalOwnerKey(record.ownerKey)
    local class = NormalizedClass(record.class)
    if not key or key:match("@unknown$") or not class
        or not Identity.OwnerKeyMatchesAuthor(key, record.author) then
        return nil
    end
    local bucket = relatedIndex.ownerClasses[key]
    if not bucket then
        bucket = {ids={},classes={},count=0}
        relatedIndex.ownerClasses[key] = bucket
    end
    if bucket.ids[id] == nil then
        bucket.ids[id] = class
        bucket.classes[class] = (bucket.classes[class] or 0) + 1
        bucket.count = bucket.count + 1
    end
    return key
end

local function RemoveOwnerClass(key, id)
    local bucket = key and relatedIndex.ownerClasses[key]
    local class = bucket and bucket.ids[id]
    if not class then return end
    bucket.ids[id] = nil
    bucket.count = math.max(0, bucket.count - 1)
    bucket.classes[class] = math.max(0, (bucket.classes[class] or 0) - 1)
    if bucket.classes[class] == 0 then bucket.classes[class] = nil end
    if bucket.count == 0 then relatedIndex.ownerClasses[key] = nil end
end

local function BetterExactCandidate(id, record, currentId, currentRecord)
    if not currentId or type(currentRecord) ~= "table" then return true end
    local auto = record.autoDps and true or false
    local currentAuto = currentRecord.autoDps and true or false
    if auto ~= currentAuto then return not auto end
    return tostring(id) < tostring(currentId)
end

local function ConsiderExactWinner(bucket, id, record, source)
    if not bucket or type(record) ~= "table" then return end
    if BetterExactCandidate(id, record, bucket.winnerId,
        bucket.winnerRecord) then
        bucket.winnerId = id
        bucket.winnerRecord = record
        bucket.winnerSource = source
    end
end

local function RecomputeExactWinner(bucket)
    if not bucket then return end
    bucket.winnerId, bucket.winnerRecord, bucket.winnerSource = nil, nil, nil
    for id in pairs(bucket.ids or {}) do
        local record, source = SelectedRaw(id)
        ConsiderExactWinner(bucket, id, record, source)
    end
end

local function RemoveRelatedRow(id)
    local indexed = relatedRows[id]
    if not indexed then return end
    local exactBucket = indexed.exact and relatedIndex.exact[indexed.exact]
    local removedExactWinner = exactBucket
        and exactBucket.winnerId == id
    if exactBucket and exactBucket.ids[id] then
        local key = indexed.exactAuto and "autoCount" or "explicitCount"
        exactBucket[key] = math.max(0,(exactBucket[key] or 0)-1)
    end
    RemoveBucket(relatedIndex.exact, indexed.exact, id)
    if removedExactWinner and exactBucket.count > 0 then
        RecomputeExactWinner(exactBucket)
    end
    RemoveBucket(relatedIndex.fingerprints, indexed.fingerprint, id)
    RemoveBucket(relatedIndex.titles, indexed.title, id)
    RemoveBucket(relatedIndex.saved, indexed.saved, id)
    RemoveOwnerClass(indexed.classOwner, id)
    for _, key in ipairs(indexed.spells or {}) do
        RemoveBucket(relatedIndex.spells, key, id)
    end
    relatedRows[id] = nil
end

local function AddRelatedRow(id, record)
    if type(record) ~= "table" then return end
    local exact = OrdinaryComplete(record) and ExactFingerprint(record) or nil
    local exactBucket, exactAdded = AddBucket(relatedIndex.exact, exact, id)
    local exactAuto = record.autoDps == true
    if exactBucket and exactAdded then
        local key = exactAuto and "autoCount" or "explicitCount"
        exactBucket[key] = (exactBucket[key] or 0) + 1
    end
    local _, source = SelectedRaw(id)
    ConsiderExactWinner(exactBucket, id, record, source)
    local classOwner = AddOwnerClass(record, id)
    local author = RelatedText(record.author)
    if author == "" then
        relatedRows[id] = {
            exact=exact,exactAuto=exactAuto,classOwner=classOwner}
        return
    end
    if record.importedSavedBuild then
        local saved = RelatedKey(author, "saved")
        AddBucket(relatedIndex.saved, saved, id)
        relatedRows[id] = {
            exact=exact,exactAuto=exactAuto,saved=saved,
            classOwner=classOwner,
        }
        return
    end
    local fingerprint = RelatedFingerprint(record)
    local fingerprintKey = RelatedKey(author, fingerprint)
    local titleKey = RelatedKey(author, RelatedText(record.title or record.serverTitle))
    local spellKeys = {}
    local spells = FingerprintSpells(fingerprint)
    for _, spellId in ipairs(spells) do
        local key = RelatedKey(author, tostring(spellId))
        if key then
            spellKeys[#spellKeys + 1] = key
            AddBucket(relatedIndex.spells, key, id)
        end
    end
    AddBucket(relatedIndex.fingerprints, fingerprintKey, id)
    AddBucket(relatedIndex.titles, titleKey, id)
    relatedRows[id] = {
        exact=exact,exactAuto=exactAuto,
        fingerprint=fingerprintKey,title=titleKey,spells=spellKeys,
        classOwner=classOwner,
    }
end

local function UpdateRelatedRow(id)
    local previous = relatedRows[id] and relatedRows[id].exact or nil
    RemoveRelatedRow(id)
    AddRelatedRow(id, SelectedRaw(id))
    local current = relatedRows[id] and relatedRows[id].exact or nil
    exactRevisionClock = exactRevisionClock + 1
    if previous then exactRevisions[previous] = exactRevisionClock end
    if current then exactRevisions[current] = exactRevisionClock end
    relatedIndexGeneration = libraryGeneration
    debugStats.relatedIndexUpdates = debugStats.relatedIndexUpdates + 1
end

local function RebuildRelatedIndex()
    relatedIndex = {
        exact={},fingerprints={},titles={},spells={},saved={},ownerClasses={}}
    relatedRows = {}
    local seen = {}
    for id in pairs(baseline) do
        seen[id] = true
        AddRelatedRow(id, SelectedRaw(id))
    end
    for id in pairs(db and db.communityBuilds or {}) do
        if not seen[id] then AddRelatedRow(id, SelectedRaw(id)) end
    end
    relatedIndexGeneration = libraryGeneration
    debugStats.relatedIndexRebuilds = debugStats.relatedIndexRebuilds + 1
end

local function BumpIfChanged(before, after, reason, id)
    if DeepEqual(before, after) then return false end
    BumpBuild(reason, id)
    return true
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
        if relatedIndexGeneration ~= libraryGeneration then RebuildRelatedIndex() end
        return summary
    end

    debugStats.rebinds = debugStats.rebinds + 1
    ordinaryVerdictCache = setmetatable({}, {__mode="k"})
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
    RebuildRelatedIndex()
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

function Catalog.GetSummary(id)
    EnsureBound()
    local record = SelectedRaw(id)
    return record and SummaryRecord(record) or nil
end

-- Allocation-free revision tokens for one selected record and one exact Echo
-- fingerprint. Consumers compare the opaque scalar pair; represented rows
-- remain private and every materialized result still crosses PublicRecord.
function Catalog.RecordRevision(id)
    EnsureBound()
    return recordEpoch, recordRevisions[id] or 0
end

function Catalog.ExactFingerprintRevision(fingerprint)
    EnsureBound()
    if type(fingerprint) ~= "string" or fingerprint == "" then
        return exactEpoch, 0
    end
    return exactEpoch, exactRevisions[fingerprint] or 0
end

-- Exact-match consumers previously called Catalog.All and copied every public
-- build. The incrementally maintained bucket preserves explicit-build
-- preference over auto-generated DPS pages, adds deterministic id ordering,
-- and returns at most one defensive represented record.
local function FindExactFingerprintId(fingerprint)
    EnsureBound()
    debugStats.exactLookups = debugStats.exactLookups + 1
    if type(fingerprint) ~= "string" or fingerprint == ""
        or relatedIndexGeneration ~= libraryGeneration then
        return nil, nil
    end
    local bucket = relatedIndex.exact[fingerprint]
    local candidates = bucket and bucket.count or 0
    debugStats.exactCandidates = debugStats.exactCandidates + candidates
    debugStats.maxExactCandidates = math.max(
        debugStats.maxExactCandidates, candidates)
    return bucket and bucket.winnerId or nil,
        bucket and bucket.winnerRecord or nil,
        bucket and bucket.winnerSource or nil
end

function Catalog.FindExactFingerprintId(fingerprint)
    local id = FindExactFingerprintId(fingerprint)
    return id
end

function Catalog.FindExactFingerprint(fingerprint)
    local id, record, source = FindExactFingerprintId(fingerprint)
    return id, PublicRecord(record, source)
end

-- Resolve and validate a protocol-v6 @hash claim only through its exact typed
-- raw build ID and canonical ordinary Echo evidence. Persisted hash metadata is
-- corroborating input, never independent identity authority.
function Catalog.ValidateLegacyFingerprintClaim(rawId, record)
    EnsureBound()
    if rawId == nil or (type(rawId) ~= "string" and type(rawId) ~= "number")
        or tostring(rawId) == "" then
        return nil, "legacy claim requires an exact typed build ID"
    end
    local raw, source = SelectedRaw(rawId)
    if source == "tombstone" then
        return nil, "historical build identity is tombstoned"
    end
    if type(raw) ~= "table" then
        return nil, "exact represented build is unavailable"
    end
    local evidence = Nexus and Nexus.LoadoutEvidence
    if not (evidence
        and type(evidence.ValidateLegacyFingerprintClaim) == "function") then
        return nil, "legacy claim validator is unavailable"
    end
    local claim = type(record) == "table" and record or {
        buildId=rawId,
    }
    local ok, proof, reason = pcall(
        evidence.ValidateLegacyFingerprintClaim, claim, raw)
    if not ok then return nil, "legacy claim validation failed" end
    if type(proof) ~= "table" then return nil, reason end
    return proof
end

-- Resolve a display/navigation identity without rewriting the historical raw
-- build ID. The selected raw row wins only when its exact fingerprint still
-- agrees; otherwise the incrementally maintained exact bucket supplies the
-- current represented identity. This performs no complete catalog traversal
-- and returns no mutable catalog record.
function Catalog.ResolveFingerprintIdentity(rawId, fingerprint, options)
    EnsureBound()
    debugStats.identityResolutions = debugStats.identityResolutions + 1
    if type(fingerprint) ~= "string" or fingerprint == "" then
        debugStats.identityResolutionFailures =
            debugStats.identityResolutionFailures + 1
        return nil, "record fingerprint is unavailable"
    end
    local allowClassOnly = false
    if type(options) == "table" then
        allowClassOnly = options.allowClassOnly == true
            or options.allowIncompleteForClass == true
    elseif type(options) == "boolean" then
        allowClassOnly = options == true
    end
    if fingerprint:sub(1, 1) == "@" then
        local legacyRecord = type(options) == "table"
            and options.legacyRecord or nil
        if type(legacyRecord) ~= "table" then
            legacyRecord = {buildId=rawId,fingerprint=fingerprint}
        end
        local proof, reason =
            Catalog.ValidateLegacyFingerprintClaim(rawId, legacyRecord)
        if proof then
            debugStats.identityRawHits = debugStats.identityRawHits + 1
            return rawId, "legacy-alias", proof.fingerprint
        end
        debugStats.identityResolutionFailures =
            debugStats.identityResolutionFailures + 1
        return nil, reason or "legacy fingerprint identity is unavailable"
    end
    if rawId ~= nil then
        local raw, rawSource = SelectedRaw(rawId)
        if rawSource == "tombstone" then
            debugStats.identityResolutionFailures =
                debugStats.identityResolutionFailures + 1
            return nil, "historical build identity is tombstoned"
        end
        if raw and ExactFingerprint(raw) == fingerprint
            and (OrdinaryComplete(raw) or
                (allowClassOnly and HasStringClass(raw))) then
            debugStats.identityRawHits = debugStats.identityRawHits + 1
            return rawId, "raw"
        end
    end
    local bucket = relatedIndexGeneration == libraryGeneration
        and relatedIndex.exact[fingerprint] or nil
    local explicit = bucket and (bucket.explicitCount or 0) or 0
    local automatic = bucket and (bucket.autoCount or 0) or 0
    if explicit > 1 or (explicit == 0 and automatic > 1) then
        debugStats.identityResolutionFailures =
            debugStats.identityResolutionFailures + 1
        return nil, "exact build identity is ambiguous"
    end
    local id, record = FindExactFingerprintId(fingerprint)
    if id ~= nil and type(record) == "table"
        and ExactFingerprint(record) == fingerprint
        and (OrdinaryComplete(record) or
            (allowClassOnly and HasStringClass(record))) then
        debugStats.identityFingerprintHits =
            debugStats.identityFingerprintHits + 1
        return id, "fingerprint"
    end
    debugStats.identityResolutionFailures =
        debugStats.identityResolutionFailures + 1
    return nil, "exact build identity is unavailable"
end

-- Historical DPS summaries sometimes retain a stale build identity while the
-- catalog still contains other represented builds owned by that character.
-- Recover display/filter class only from an exact, realm-qualified owner whose
-- provenance was verified on both the indexed build and the requesting row.
-- Realm-less author text is deliberately never identity authority.
function Catalog.ResolveOwnerClass(ownerKey, ownerVerified)
    EnsureBound()
    debugStats.ownerClassLookups = debugStats.ownerClassLookups + 1
    if relatedIndexGeneration ~= libraryGeneration then
        return nil, "owner class index stale"
    end
    if ownerVerified ~= true then return nil, "owner identity is unverified" end
    local key = Identity.CanonicalOwnerKey(ownerKey)
    if not key or key:match("@unknown$") then
        return nil, "realm-qualified owner is unavailable"
    end
    local bucket = relatedIndex.ownerClasses[key]
    if not bucket then return nil, "owner class unavailable" end
    local resolved, distinct = nil, 0
    for value in pairs(bucket.classes) do
        resolved = value
        distinct = distinct + 1
        if distinct > 1 then
            debugStats.ownerClassConflicts =
                debugStats.ownerClassConflicts + 1
            return nil, "owner class evidence conflicts"
        end
    end
    if distinct == 1 then
        debugStats.ownerClassHits = debugStats.ownerClassHits + 1
        return resolved, "owner-consensus"
    end
    return nil, "owner class unavailable"
end

-- Saved-loadout reconciliation reads only narrow revision-owned candidate
-- buckets. The index is built alongside Catalog.Init's existing merged walk
-- and maintained per changed record; a stale generation fails closed instead
-- of rebuilding the complete catalog from a UI click.
function Catalog.RelatedCandidates(author, title, fingerprint)
    EnsureBound()
    local rows = {}
    local cursor, err = Catalog.BeginRelatedCursor(author, title, fingerprint)
    if not cursor then return rows, err end
    while true do
        local record, done, nextErr = Catalog.RelatedCursorNext(cursor)
        if nextErr then return {}, nextErr end
        if record then rows[#rows + 1] = record end
        if done then break end
    end
    return rows
end

function Catalog.BeginRelatedCursor(author, title, fingerprint)
    EnsureBound()
    debugStats.relatedLookups = debugStats.relatedLookups + 1
    if relatedIndexGeneration ~= libraryGeneration then
        return nil, "related index stale"
    end
    local authorKey = RelatedText(author)
    if authorKey == "" then return {generation=libraryGeneration,buckets={}} end
    local buckets = {}
    local function AddCandidateBucket(bucket)
        if bucket then buckets[#buckets + 1] = bucket end
    end
    AddCandidateBucket(relatedIndex.fingerprints[
        RelatedKey(authorKey, fingerprint)])
    AddCandidateBucket(relatedIndex.titles[
        RelatedKey(authorKey, RelatedText(title))])

    local spells, total = FingerprintSpells(fingerprint)
    if total >= 6 then
        local smallest
        for _, spellId in ipairs(spells) do
            local bucket = relatedIndex.spells[
                RelatedKey(authorKey, tostring(spellId))]
            if bucket and (not smallest or bucket.count < smallest.count) then
                smallest = bucket
            end
        end
        AddCandidateBucket(smallest)
    end
    return {
        generation=libraryGeneration,buckets=buckets,
        bucketIndex=1,key=nil,seen={},returned=0,
    }
end

function Catalog.RelatedCursorNext(cursor)
    if type(cursor) ~= "table" or type(cursor.buckets) ~= "table" then
        return nil, true, "invalid related cursor"
    end
    EnsureBound()
    if cursor.generation ~= libraryGeneration
        or relatedIndexGeneration ~= libraryGeneration then
        return nil, true, "catalog changed"
    end
    while cursor.bucketIndex <= #cursor.buckets do
        local bucket = cursor.buckets[cursor.bucketIndex]
        local id = next(bucket.ids, cursor.key)
        cursor.key = id
        if id == nil then
            cursor.bucketIndex = cursor.bucketIndex + 1
            cursor.key = nil
        elseif not cursor.seen[id] then
            cursor.seen[id] = true
            local record, source = SelectedRaw(id)
            if record then
                cursor.returned = cursor.returned + 1
                debugStats.relatedCandidates = debugStats.relatedCandidates + 1
                debugStats.maxRelatedCandidates = math.max(
                    debugStats.maxRelatedCandidates, cursor.returned)
                return PublicRecord(record, source), false
            end
            return nil, false
        else
            return nil, false
        end
    end
    return nil, true
end

function Catalog.SavedMirrorIds(author)
    EnsureBound()
    debugStats.savedMirrorEnumerations = debugStats.savedMirrorEnumerations + 1
    if relatedIndexGeneration ~= libraryGeneration then
        return {}, "related index stale"
    end
    local bucket = relatedIndex.saved[RelatedKey(author, "saved")]
    local ids = {}
    for id in pairs(bucket and bucket.ids or {}) do ids[#ids + 1] = id end
    table.sort(ids, function(left, right)
        return tostring(left) < tostring(right)
    end)
    debugStats.savedMirrorRows = debugStats.savedMirrorRows + #ids
    return ids
end

-- UI-only resumable summary reader. Begin is constant-size and each Next call
-- advances over at most one catalog key, so a tombstoned or shadowed library
-- cannot turn one frame into a full snapshot. Existing synchronous readers stay
-- unchanged for compatibility consumers.
function Catalog.BeginSummaryCursor()
    EnsureBound()
    local overlay = db and type(db.communityBuilds) == "table"
        and db.communityBuilds or nil
    return {
        generation=libraryGeneration,
        phase="baseline",
        key=nil,
        baseline=baseline,
        overlayRef=overlay,
        overlay=overlay or {},
    }
end

function Catalog.SummaryCursorNext(cursor)
    if type(cursor) ~= "table" then return nil, true, "invalid cursor" end
    EnsureBound()
    if cursor.generation ~= libraryGeneration
        or cursor.baseline ~= baseline
        or cursor.overlayRef ~= (db and type(db.communityBuilds) == "table"
            and db.communityBuilds or nil) then
        return nil, true, "catalog changed"
    end
    if cursor.phase == "done" then return nil, true end

    local id
    local fromBaseline, fromOverlay = false, false
    if cursor.phase == "baseline" then
        id = next(cursor.baseline, cursor.key)
        cursor.key = id
        if id == nil then
            cursor.phase, cursor.key = "overlay", nil
        else
            fromBaseline = true
            fromOverlay = cursor.overlay[id] ~= nil
        end
    end
    if cursor.phase == "overlay" and id == nil then
        id = next(cursor.overlay, cursor.key)
        cursor.key = id
        if id == nil then
            cursor.phase = "done"
            return nil, true
        end
        if cursor.baseline[id] ~= nil then return nil, false end
        fromOverlay = true
    end
    local record = id ~= nil and SelectedRaw(id) or nil
    return record and SummaryRecord(record) or nil, false, nil,
        fromBaseline, fromOverlay
end

function Catalog.DeltaSummaries()
    return SummarySnapshot(true)
end

local function AuthorKey(value)
    if type(value) ~= "string" or value == "" then return nil end
    return Identity.PlayerKey(value)
        or (value:match("^([^-]+)") or value):lower()
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

function Catalog.Status()
    EnsureBound()
    local summary = type(lastInitSummary) == "table" and lastInitSummary or {}
    return {
        bundledCount=math.max(0,math.floor(tonumber(summary.bundled) or 0)),
        overlayCount=math.max(0,math.floor(tonumber(summary.overlay) or 0)),
        tombstoneCount=math.max(0,math.floor(tonumber(summary.tombstones) or 0)),
        availableCount=math.max(0,math.floor(tonumber(summary.merged) or 0)),
        catalogVersion=tostring(summary.catalogVersion or "unversioned"),
        readOnly=summary.readOnly == true,
    }
end

local function StoreRecord(record)
    debugStats.putCalls = debugStats.putCalls + 1
    local id = record.id
    local statusBefore = StatusState(id)
    -- Compare the durable representation, not its materialized public view.
    -- Pool-only and inline-equivalent rows must not trigger a false rewrite.
    local before = StoredRecord(id)
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
            debugStats.compactionCalls = debugStats.compactionCalls + 1
            local compactOk, compactChanged =
                pcall(compaction.CompactBuildRow, copy)
            -- Preserve the established fallback boundary: a successful
            -- compaction call owns reference handling even when no rewrite is
            -- needed. Diagnostics observe it without changing storage flow.
            compacted = compactOk
            if compactOk and compactChanged then
                debugStats.compactionWrites = debugStats.compactionWrites + 1
            end
        end
        if not compacted and evidence and type(evidence.Reference) == "function"
            and type(copy.echoes) == "table" and #copy.echoes > 0 then
            debugStats.referenceCalls = debugStats.referenceCalls + 1
            local referenceOk, reference, created =
                pcall(evidence.Reference, copy, "echoes", "evidenceKey")
            if referenceOk and reference and created then
                debugStats.referenceStores = debugStats.referenceStores + 1
            end
        end
        local current = overlay[id]
        -- Preserve the legacy overlay table identity for compatibility with
        -- callers that already hold a SavedVariables row, while still storing
        -- only our defensive copy rather than the caller-owned table.
        if type(current) == "table" then
            ordinaryVerdictCache[current] = nil
            for key in pairs(current) do current[key] = nil end
            for key, value in pairs(copy) do current[key] = value end
        else
            overlay[id] = copy
        end
        storedAs = "overlay"
    end
    AdjustStatus(statusBefore, StatusState(id))
    return storedAs, not DeepEqual(before, StoredRecord(id)), id
end

function Catalog.Put(record)
    EnsureBound()
    if catalogReadOnly then
        return false, "future build catalog schema is read-only"
    end
    if type(record) ~= "table" or record.id == nil then
        return false, "build id required"
    end
    local storedAs, changed, id = StoreRecord(record)
    if changed then
        BumpBuild("build put", id)
        debugStats.putChanges = debugStats.putChanges + 1
        UpdateRelatedRow(id)
    end
    return true, storedAs
end

-- Stage one repair record without publishing a represented-data revision.
-- The caller performs at most one of these writes per bounded work unit, then
-- calls PublishDeferred once after the complete set is indexed. Projections
-- therefore retain their last-good snapshot until one atomic revision signal.
function Catalog.PutDeferred(record)
    EnsureBound()
    if catalogReadOnly then
        return false, "future build catalog schema is read-only"
    end
    if type(record) ~= "table" or record.id == nil then
        return false, "build id required"
    end
    -- A malformed or future-owned raw SavedVariables value is still occupied.
    -- Never replace it merely because merged selection cannot materialize it.
    if Overlay()[record.id] ~= nil then
        return false, "deferred build id unavailable"
    end
    local existing, source = SelectedRaw(record.id)
    if existing or source == "tombstone" then
        return false, "deferred build id unavailable"
    end
    local storedAs, changed, id = StoreRecord(record)
    if changed then
        debugStats.putChanges = debugStats.putChanges + 1
        UpdateRelatedRow(id)
    end
    return true, storedAs, changed
end

function Catalog.PublishDeferred(changed, reason)
    EnsureBound()
    changed = math.max(0, math.floor(tonumber(changed) or 0))
    if changed == 0 then return true, 0 end
    BumpBuild(reason or "deferred builds published")
    -- PutDeferred already maintained the exact index after every bounded
    -- write; bind that complete index to the newly published generation.
    relatedIndexGeneration = libraryGeneration
    return true, 1
end

function Catalog.RemoveOverlay(id)
    EnsureBound()
    if catalogReadOnly then
        return false, "future build catalog schema is read-only"
    end
    local before = RevisionRecord(id)
    local statusBefore = StatusState(id)
    local existed = Overlay()[id] ~= nil
    Overlay()[id] = nil
    AdjustStatus(statusBefore, StatusState(id))
    if BumpIfChanged(before, RevisionRecord(id), "overlay removed", id) then
        UpdateRelatedRow(id)
    end
    return existed
end

-- Retention is a local cache operation, not a network-visible delete. Batch
-- removals publish one library revision while keeping the per-record indexes
-- and aggregate status counters consistent for every affected id.
function Catalog.RemoveOverlayBatch(ids)
    EnsureBound()
    if catalogReadOnly then
        return 0, "future build catalog schema is read-only"
    end
    if type(ids) ~= "table" then return 0, "build id list required" end
    local overlay = Overlay()
    local removed, changedIds = 0, {}
    for _, id in ipairs(ids) do
        if overlay[id] ~= nil then
            local statusBefore = StatusState(id)
            overlay[id] = nil
            recordRevisions[id] = (recordRevisions[id] or 0) + 1
            AdjustStatus(statusBefore, StatusState(id))
            changedIds[#changedIds + 1] = id
            removed = removed + 1
        end
    end
    if removed > 0 then
        BumpBuild("overlay retention")
        for _, id in ipairs(changedIds) do UpdateRelatedRow(id) end
    end
    return removed
end

function Catalog.SetTombstone(id, tombstone)
    EnsureBound()
    if catalogReadOnly then
        return false, "future build catalog schema is read-only"
    end
    if id == nil or tombstone == nil then return false end
    local before = RevisionRecord(id)
    local statusBefore = StatusState(id)
    Tombstones()[id] = DeepCopy(tombstone)
    Overlay()[id] = nil
    AdjustStatus(statusBefore, StatusState(id))
    if BumpIfChanged(before, RevisionRecord(id), "build tombstoned", id) then
        UpdateRelatedRow(id)
    end
    return true
end

function Catalog.ClearTombstone(id)
    EnsureBound()
    if catalogReadOnly then
        return false, "future build catalog schema is read-only"
    end
    local before = RevisionRecord(id)
    local statusBefore = StatusState(id)
    local existed = Tombstones()[id] ~= nil
    Tombstones()[id] = nil
    AdjustStatus(statusBefore, StatusState(id))
    if BumpIfChanged(before, RevisionRecord(id), "tombstone cleared", id) then
        UpdateRelatedRow(id)
    end
    return existed
end

-- Tombstones masking immutable bundled rows are permanent: removing one would
-- resurrect the bundled record. Retention may compact only non-baseline ids.
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
    local removed, changedIds = 0, {}
    for _, id in ipairs(ids) do
        if source[id] ~= nil and type(baseline[id]) ~= "table" then
            local statusBefore = StatusState(id)
            source[id] = nil
            recordRevisions[id] = (recordRevisions[id] or 0) + 1
            AdjustStatus(statusBefore, StatusState(id))
            changedIds[#changedIds + 1] = id
            removed = removed + 1
        end
    end
    if removed > 0 then
        BumpBuild("tombstone retention")
        for _, id in ipairs(changedIds) do UpdateRelatedRow(id) end
    end
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
        if source == "overlay" and record and SyncEligible(record) then
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
    if source == "overlay" and record and SyncEligible(record) then
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
        delta=source == "overlay" and SyncEligible(record)
            and PublicRecord(record, source) or nil,
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
