-- Bounded retention for durable Community and DPS mesh state.
--
-- Account-owned builds are never removed automatically. Remote DPS rows are
-- ranked per category: keep the overall leaders plus a minimum representation
-- from every class. The derived Average board reserves both of its underlying
-- Dummy/LK records. Unranked remote pages have a separate small recency budget.

Nexus = Nexus or {}
local Identity = assert(Nexus.Identity,
    "Nexus Identity must load before DataRetention")
local CandidateEvidence = assert(Nexus.CandidateEvidence,
    "CandidateEvidence must load before DataRetention")
local Retention = {}
Nexus.DataRetention = Retention

local SCHEMA_VERSION = 4
local DEFAULT_LIMITS = {
    topPerCategory = 100,
    minPerClassPerCategory = 15,
    topAverage = 50,
    minAveragePerClass = 10,
    otherRemoteBuilds = 75,
    remotePerAuthor = 12,
    personalFingerprints = 128,
    buildBestFingerprints = 128,
    evictionMarkers = 2048,
    evictionMarkerAge = 30 * 24 * 60 * 60,
    exactTombstones = 2048,
    tombstoneAge = 180 * 24 * 60 * 60,
}

local CONFIGURED_LIMITS = {
    topPerCategory={ key="communityRetentionTopPerCategory", min=25, max=1000 },
    minPerClassPerCategory={ key="communityRetentionMinPerClassPerCategory", min=1, max=100 },
    topAverage={ key="communityRetentionTopAverage", min=10, max=1000 },
    minAveragePerClass={ key="communityRetentionMinAveragePerClass", min=1, max=100 },
    otherRemoteBuilds={ key="communityRetentionOtherRemoteBuilds", min=0, max=1000 },
    remotePerAuthor={ key="communityRetentionMaxPerAuthor", min=1, max=250 },
    personalFingerprints={ key="communityRetentionPersonalFingerprints", min=16, max=1000 },
    buildBestFingerprints={ key="communityRetentionBuildFingerprints", min=16, max=1000 },
}

local function Count(source)
    local total = 0
    for _ in pairs(type(source) == "table" and source or {}) do
        total = total + 1
    end
    return total
end

local function Copy(source)
    local out = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        out[key] = value
    end
    return out
end

local function ResolveLimits(database)
    local limits = Copy(DEFAULT_LIMITS)
    local settings = type(database) == "table" and database.settings or nil
    -- Ranked content pruning is opt-in. Future-owned settings are deliberately
    -- not filled by Store, so absence must remain the shipped unlimited mode.
    local enabled = type(settings) == "table"
        and settings.communityRetentionEnabled == true
    for name, spec in pairs(CONFIGURED_LIMITS) do
        local value = type(settings) == "table" and tonumber(settings[spec.key]) or nil
        if value and value == value and value < math.huge and value > -math.huge then
            value = math.floor(value)
            limits[name] = math.max(spec.min, math.min(spec.max, value))
        end
    end
    limits.enabled = enabled
    -- Retain the user's configured numbers while disabled so opting in later
    -- restores the same policy. No build or DPS content limit is applied in
    -- this mode; only bounded deletion/eviction metadata maintenance remains.
    limits.contentUnlimited = not enabled
    limits.minPerClassPerCategory = math.min(
        limits.minPerClassPerCategory, limits.topPerCategory)
    limits.minAveragePerClass = math.min(
        limits.minAveragePerClass, limits.topAverage)
    limits.remotePerAuthor = math.min(
        limits.remotePerAuthor, math.max(1, limits.otherRemoteBuilds))
    return limits
end

local function EpochNow()
    if type(time) ~= "function" then return 0 end
    local ok, value = pcall(time)
    value = ok and tonumber(value) or 0
    return value and value > 0 and value or 0
end

local function PlayerKey(value)
    return Identity.PlayerKey(value) or ""
end

local function CharacterKey(row, fallback)
    row = type(row) == "table" and row or {}
    local canonical = Identity.CanonicalOwnerKey(row.ownerKey)
    if canonical and not canonical:match("@unknown$") then return canonical end
    local realm = tostring(row.realm or "")
    if realm ~= "" and realm:lower() ~= "unknown" then
        local inferred = Identity.OwnerKey(row.player or fallback, realm)
        if inferred and not inferred:match("@unknown$") then return inferred end
    end
    return PlayerKey(row.player or fallback)
end

local function CurrentOwnerKey()
    local name = UnitName and UnitName("player") or nil
    if not name or name == "" or name == "Unknown" then return nil end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then realm = GetRealmName and GetRealmName() end
    realm = tostring(realm or ""):gsub("%s+", "")
    if realm == "" or realm:lower() == "unknown" then return nil end
    return Identity.OwnerKey(name, realm)
end

local function IsLocalBuild(build)
    if type(build) ~= "table" then return false end
    local store = Nexus and Nexus.Store
    if store and type(store.IsAccountBuild) == "function" then
        local ok, value = pcall(store.IsAccountBuild, build)
        if ok and value then return true end
    end
    if build.isMine == true or build.importedSavedBuild == true then return true end
    local owner = CurrentOwnerKey()
    return owner ~= nil
        and Identity.CanonicalOwnerKey(build.ownerKey) == owner
end

local function ValidBuildId(value)
    return (type(value) == "string" or type(value) == "number")
        and tostring(value) ~= ""
end

local function IsLocalDpsRow(row)
    if type(row) ~= "table" then return false end
    local store = Nexus and Nexus.Store
    if row.ownerVerified == true
        and store and type(store.IsAccountOwnerKey) == "function"
        and type(row.ownerKey) == "string" then
        local ok, value = pcall(store.IsAccountOwnerKey, row.ownerKey)
        if ok and value then return true end
    end
    local overlay = NexusDB and NexusDB.communityBuilds
    if row.ownerVerified == true and type(overlay) == "table"
        and ValidBuildId(row.buildId)
        and IsLocalBuild(overlay[row.buildId]) then return true end
    local owner = CurrentOwnerKey()
    if row.ownerVerified == true and owner ~= nil
        and CharacterKey(row) == owner then return true end
    return false
end

local function RowStamp(row)
    if type(row) ~= "table" then return 0 end
    return tonumber(row.ts or row.lastModified or row.postedAt) or 0
end

local function EntryStamp(value, seen)
    if type(value) ~= "table" then return 0 end
    seen = seen or {}
    if seen[value] then return 0 end
    seen[value] = true
    local newest = RowStamp(value)
    for _, child in pairs(value) do
        if type(child) == "table" then
            newest = math.max(newest, EntryStamp(child, seen))
        end
    end
    return newest
end

local function BetterDps(left, right)
    if left.dps ~= right.dps then return left.dps > right.dps end
    if left.stamp ~= right.stamp then return left.stamp > right.stamp end
    return tostring(left.key) < tostring(right.key)
end

local function BetterRow(left, right)
    if left.protected ~= right.protected then return left.protected end
    if left.stamp ~= right.stamp then return left.stamp > right.stamp end
    if left.dps ~= right.dps then return left.dps > right.dps end
    return tostring(left.key) < tostring(right.key)
end

local function TypedIdentity(value)
    return type(value) .. ":" .. tostring(value == nil and "" or value)
end

local function RowIdentity(row)
    if type(row) ~= "table" then return nil end
    if row.fingerprint ~= nil then return TypedIdentity(row.fingerprint) end
    if row.buildId ~= nil then return TypedIdentity(row.buildId) end
    return nil
end

local function ClassKey(value)
    local key = tostring(value or "UNKNOWN"):upper():gsub("%s+", "")
    return key ~= "" and key or "UNKNOWN"
end

local function RowClass(row, overlay)
    if type(row) ~= "table" then return "UNKNOWN" end
    local build = type(overlay) == "table" and ValidBuildId(row.buildId)
        and overlay[row.buildId] or nil
    return ClassKey(row.class or (type(build) == "table" and build.class))
end

local function SelectRanked(rows, overall, perClass, keep)
    table.sort(rows, BetterDps)
    local overallKept = 0
    for _, entry in ipairs(rows) do
        if not entry.localRow and overallKept < overall then
            keep(entry)
            overallKept = overallKept + 1
        end
    end
    local classCounts = {}
    for _, entry in ipairs(rows) do
        local count = classCounts[entry.class] or 0
        if not entry.localRow and entry.class ~= "UNKNOWN" and count < perClass then
            keep(entry)
            classCounts[entry.class] = count + 1
        end
    end
end

local function SelectCharacterBest(dps, limits, overlay)
    local source = type(dps) == "table" and dps.characterBest or nil
    local selected = {dummy={},lk={}}
    local fingerprints, buildIds = {}, {}
    local categoryCounts = {dummy=0,lk=0,average=0}
    if type(source) ~= "table" then
        return selected, fingerprints, buildIds, categoryCounts
    end

    local entries = {dummy={},lk={}}
    for _, category in ipairs({"dummy", "lk"}) do
        for key, row in pairs(type(source[category]) == "table" and source[category] or {}) do
            if type(row) == "table" then
                local entry = {
                    key=key, row=row, category=category,
                    dps=tonumber(row.dps) or 0, stamp=RowStamp(row),
                    class=RowClass(row, overlay), localRow=IsLocalDpsRow(row),
                }
                entries[category][#entries[category] + 1] = entry
                if entry.localRow then selected[category][key] = true end
            end
        end
        SelectRanked(entries[category], limits.topPerCategory,
            limits.minPerClassPerCategory, function(entry)
                selected[category][entry.key] = true
            end)
    end

    -- Reserve Average inputs from the same deterministic real-pair owner used
    -- by Community and Leaderboard. Category maxima remain independent.
    local entryByRow, dummyRows, lkRows = {}, {}, {}
    for _, entry in ipairs(entries.dummy) do
        entryByRow[entry.row] = entry
        dummyRows[#dummyRows + 1] = entry.row
    end
    for _, entry in ipairs(entries.lk) do
        entryByRow[entry.row] = entry
        lkRows[#lkRows + 1] = entry.row
    end
    local averages = {}
    local function PairEntry(row, sources)
        local best = entryByRow[row]
        for _, sourceRow in ipairs(type(sources) == "table" and sources or {}) do
            local candidate = entryByRow[sourceRow]
            if candidate and (not best
                or tostring(candidate.key) < tostring(best.key)) then
                best = candidate
            end
        end
        return best
    end
    for _, pair in ipairs(CandidateEvidence.RealDpsPairs(dummyRows, lkRows)) do
        local dummyEntry = PairEntry(pair.dummy, pair.dummySources)
        local lkEntry = PairEntry(pair.lk, pair.lkSources)
        if dummyEntry and lkEntry then
            averages[#averages + 1] = {
                key=pair.identity,dps=pair.average,
                stamp=math.min(dummyEntry.stamp, lkEntry.stamp),
                class=lkEntry.class ~= "UNKNOWN" and lkEntry.class or dummyEntry.class,
                dummy=dummyEntry, lk=lkEntry,
                localRow=dummyEntry.localRow or lkEntry.localRow,
            }
        end
    end
    for _, entry in ipairs(averages) do
        if entry.localRow then
            selected.dummy[entry.dummy.key] = true
            selected.lk[entry.lk.key] = true
            entry.averageSelected = true
        end
    end
    SelectRanked(averages, limits.topAverage, limits.minAveragePerClass,
        function(entry)
            selected.dummy[entry.dummy.key] = true
            selected.lk[entry.lk.key] = true
            entry.averageSelected = true
        end)

    for _, entry in ipairs(averages) do
        if entry.averageSelected then categoryCounts.average = categoryCounts.average + 1 end
    end
    for _, category in ipairs({"dummy", "lk"}) do
        for _, entry in ipairs(entries[category]) do
            if selected[category][entry.key] then
                categoryCounts[category] = categoryCounts[category] + 1
                local row = entry.row
                if type(row.fingerprint) == "string" then fingerprints[row.fingerprint] = true end
                if ValidBuildId(row.buildId) then buildIds[row.buildId] = true end
            end
        end
    end
    return selected, fingerprints, buildIds, categoryCounts
end

local function TrimCharacterBest(dps, selected)
    local removed = 0
    local source = type(dps) == "table" and dps.characterBest or nil
    if type(source) ~= "table" then return removed end
    for _, category in ipairs({"dummy", "lk"}) do
        local bucket = type(source[category]) == "table" and source[category] or {}
        for key in pairs(bucket) do
            if not (selected[category] and selected[category][key]) then
                bucket[key] = nil
                removed = removed + 1
            end
        end
    end
    return removed
end

local function TrimFingerprintMap(source, limit, protected)
    if type(source) ~= "table" then return 0 end
    local rows = {}
    for key, value in pairs(source) do
        rows[#rows + 1] = {
            key=key, protected=protected and protected[key] == true or false,
            stamp=EntryStamp(value), dps=0,
        }
    end
    table.sort(rows, BetterRow)
    local removed, kept = 0, 0
    for _, entry in ipairs(rows) do
        if entry.protected or kept < limit then
            kept = kept + 1
        else
            source[entry.key] = nil
            removed = removed + 1
        end
    end
    return removed
end

local function CollectBuildReferences(dps, seed)
    local referenced, seen = Copy(seed), {}
    local function Scan(value)
        if type(value) ~= "table" or seen[value] then return end
        seen[value] = true
        if ValidBuildId(value.buildId) then
            referenced[value.buildId] = true
        end
        for _, child in pairs(value) do
            if type(child) == "table" then Scan(child) end
        end
    end
    if type(dps) == "table" then
        Scan(dps.personalBest)
        Scan(dps.buildBest)
        Scan(dps.characterBest)
    end
    return referenced
end

local function BuildStamp(build)
    return tonumber(build and (build.lastModified or build.postedAt)) or 0
end

local function CompleteBuild(build)
    if type(build) ~= "table" then return false end
    if build.loadoutAvailable ~= nil then return build.loadoutAvailable == true end
    return (type(build.echoes) == "table" and next(build.echoes) ~= nil)
        or (type(build.evidenceKey) == "string" and build.evidenceKey ~= "")
end

local function BetterBuild(left, right)
    if left.referenced ~= right.referenced then return left.referenced end
    if left.complete ~= right.complete then return left.complete end
    if left.stamp ~= right.stamp then return left.stamp > right.stamp end
    return tostring(left.id) < tostring(right.id)
end

local function AuthorKey(value)
    local key = PlayerKey(value)
    return key ~= "" and key or "<unknown>"
end

local function RemoveOverlayIds(database, ids)
    if #ids == 0 then return 0 end
    table.sort(ids, function(left, right)
        return TypedIdentity(left) < TypedIdentity(right)
    end)
    local catalog = Nexus and Nexus.BuildCatalog
    if catalog and type(catalog.RemoveOverlayBatch) == "function" then
        local ok, removed = pcall(catalog.RemoveOverlayBatch, ids)
        if ok then return tonumber(removed) or 0 end
    end
    local overlay = type(database.communityBuilds) == "table"
        and database.communityBuilds or {}
    local removed = 0
    for _, id in ipairs(ids) do
        if overlay[id] ~= nil then overlay[id] = nil; removed = removed + 1 end
    end
    return removed
end

local function MarkEvictions(database, overlay, ids)
    if #ids == 0 then return 0 end
    database.communityRetentionEvictions =
        type(database.communityRetentionEvictions) == "table"
        and database.communityRetentionEvictions or {}
    local markers, changed = database.communityRetentionEvictions, 0
    local recordedAt = math.max(1, EpochNow())
    for _, id in ipairs(ids) do
        local revision = math.max(1, BuildStamp(overlay[id]))
        local prior = markers[id]
        local priorRevision = type(prior) == "table"
            and tonumber(prior.revision or prior.stamp) or tonumber(prior) or 0
        if revision > priorRevision or type(prior) ~= "table" then
            markers[id] = {
                revision=math.max(revision, priorRevision),
                recordedAt=recordedAt,
            }
            changed = changed + 1
        end
    end
    return changed
end

local function PruneOverlay(database, referenced, limits)
    local overlay = type(database.communityBuilds) == "table"
        and database.communityBuilds or {}
    local marked, orphaned = {}, 0
    local remoteBefore = 0
    for id, build in pairs(overlay) do
        if not IsLocalBuild(build) then
            remoteBefore = remoteBefore + 1
            if type(build) == "table" and build.autoDps == true and not referenced[id] then
                marked[id] = true
                orphaned = orphaned + 1
            end
        end
    end

    -- Ranked pages are already selected from DPS rows. Apply author/global
    -- budgets only to unrelated community pages so representation guarantees
    -- cannot be undone by a second, contradictory cap.
    local groups = {}
    for id, build in pairs(overlay) do
        if not marked[id] and not referenced[id] and not IsLocalBuild(build) then
            local author = AuthorKey(type(build) == "table" and build.author)
            groups[author] = groups[author] or {}
            groups[author][#groups[author] + 1] = {
                id=id, referenced=referenced[id] == true,
                stamp=BuildStamp(build), complete=CompleteBuild(build),
            }
        end
    end
    local perAuthorRemoved = 0
    for _, rows in pairs(groups) do
        table.sort(rows, BetterBuild)
        for index = limits.remotePerAuthor + 1, #rows do
            local id = rows[index].id
            if not marked[id] then marked[id] = true; perAuthorRemoved = perAuthorRemoved + 1 end
        end
    end

    local candidates = {}
    for id, build in pairs(overlay) do
        if not marked[id] and not referenced[id] and not IsLocalBuild(build) then
            candidates[#candidates + 1] = {
                id=id, referenced=referenced[id] == true,
                stamp=BuildStamp(build), complete=CompleteBuild(build),
            }
        end
    end
    table.sort(candidates, BetterBuild)
    local globalRemoved = 0
    for index = limits.otherRemoteBuilds + 1, #candidates do
        local id = candidates[index].id
        if not marked[id] then marked[id] = true; globalRemoved = globalRemoved + 1 end
    end

    local referencedKept = 0
    for id in pairs(referenced) do
        if not marked[id] and not IsLocalBuild(overlay[id])
            and overlay[id] ~= nil then referencedKept = referencedKept + 1 end
    end

    local ids = {}
    for id in pairs(marked) do ids[#ids + 1] = id end
    local markersAdded = MarkEvictions(database, overlay, ids)
    local removed = RemoveOverlayIds(database, ids)
    return {
        before=remoteBefore,
        after=math.max(0, remoteBefore - removed),
        removed=removed,
        orphaned=orphaned,
        perClass=0,
        perAuthor=perAuthorRemoved,
        global=globalRemoved,
        referencedKept=referencedKept,
        markersAdded=markersAdded,
    }
end

local function PruneEvictionMarkers(database, now)
    local source = type(database.communityRetentionEvictions) == "table"
        and database.communityRetentionEvictions or {}
    local before = Count(source)
    -- Retention suppression is exact-ID authority. Older schema versions
    -- compacted removed markers into a global timestamp floor, which allowed
    -- build B's history to reject an unrelated older build A. Forget the
    -- obsolete floor; once an exact marker is deliberately removed, that one
    -- build may re-enter and converge normally.
    database.communityBuildRetentionFloor = nil
    local cutoff = now > DEFAULT_LIMITS.evictionMarkerAge
        and now - DEFAULT_LIMITS.evictionMarkerAge or 0
    local rows = {}
    for id, value in pairs(source) do
        local revision = type(value) == "table"
            and tonumber(value.revision or value.stamp) or tonumber(value) or 0
        local recordedAt = type(value) == "table"
            and tonumber(value.recordedAt or value.evictedAt) or nil
        -- Numeric v3 markers mixed the remote revision with marker age. Start
        -- their age clock now instead of expiring suppression evidence early.
        if not recordedAt or recordedAt <= 0 then
            recordedAt = math.max(1, now)
            source[id] = {revision=revision,recordedAt=recordedAt}
        end
        rows[#rows + 1] = {
            id=id, revision=revision, recordedAt=recordedAt,
            expired=cutoff > 0 and recordedAt <= cutoff,
        }
    end
    table.sort(rows, function(left, right)
        if left.recordedAt ~= right.recordedAt then
            return left.recordedAt < right.recordedAt
        end
        return TypedIdentity(left.id) < TypedIdentity(right.id)
    end)
    local removed, remaining = 0, before
    for _, row in ipairs(rows) do
        if row.expired then
            source[row.id] = nil
            removed, remaining = removed + 1, remaining - 1
        end
    end
    if remaining > DEFAULT_LIMITS.evictionMarkers then
        for _, row in ipairs(rows) do
            if remaining <= DEFAULT_LIMITS.evictionMarkers then break end
            if source[row.id] ~= nil then
                source[row.id] = nil
                removed, remaining = removed + 1, remaining - 1
            end
        end
    end
    return {
        before=before, after=math.max(0, before - removed), removed=removed,
        floor=0,
    }
end

local function TombStamp(value)
    if type(value) == "table" then return tonumber(value.stamp) or 0 end
    return tonumber(value) or 0
end

local function PruneTombstones(database, now)
    local source = type(database.syncTombstones) == "table"
        and database.syncTombstones or {}
    local exactBefore = Count(source)
    -- As with eviction markers, a deleted build's exact tombstone cannot act
    -- as a namespace-wide watermark. Immutable baseline masks and pending
    -- deletes remain exact and are never candidates here; forgotten remote
    -- tombstones permit only their own IDs to re-enter.
    database.syncTombstoneFloor = nil
    local cutoff = now > DEFAULT_LIMITS.tombstoneAge
        and now - DEFAULT_LIMITS.tombstoneAge or 0
    local candidates = {}
    local catalog = Nexus and Nexus.BuildCatalog
    for id, tomb in pairs(source) do
        local stamp = TombStamp(tomb)
        local pending = type(tomb) == "table" and tomb.pending == true
        local bundled = catalog and type(catalog.HasBaseline) == "function"
            and catalog.HasBaseline(id) or false
        if stamp > 0 and not pending and not bundled then
            candidates[#candidates + 1] = {
                id=id, stamp=stamp,
                expired=cutoff > 0 and stamp <= cutoff,
            }
        end
    end
    table.sort(candidates, function(left, right)
        if left.stamp ~= right.stamp then return left.stamp < right.stamp end
        return tostring(left.id) < tostring(right.id)
    end)

    local marked, countAfter = {}, exactBefore
    for _, entry in ipairs(candidates) do
        if entry.expired then
            marked[entry.id] = true
            countAfter = countAfter - 1
        end
    end
    if countAfter > DEFAULT_LIMITS.exactTombstones then
        for _, entry in ipairs(candidates) do
            if countAfter <= DEFAULT_LIMITS.exactTombstones then break end
            if not marked[entry.id] then
                marked[entry.id] = true
                countAfter = countAfter - 1
            end
        end
    end

    local ids = {}
    for id in pairs(marked) do ids[#ids + 1] = id end
    table.sort(ids, function(left, right) return tostring(left) < tostring(right) end)
    local removed = 0
    if #ids > 0 then
        if catalog and type(catalog.RemoveTombstonesBatch) == "function" then
            local ok, value = pcall(catalog.RemoveTombstonesBatch, ids)
            if ok then removed = tonumber(value) or 0 end
        else
            for _, id in ipairs(ids) do
                if source[id] ~= nil then source[id] = nil; removed = removed + 1 end
            end
        end
    end
    return {
        before=exactBefore, after=math.max(0, exactBefore - removed),
        removed=removed, floor=0,
    }
end

local function CollectEvidence(database)
    local evidence = Nexus and Nexus.LoadoutEvidence
    if not (evidence and type(evidence.CollectGarbage) == "function") then
        return 0, false
    end
    local ok, summary = pcall(evidence.CollectGarbage, database, false)
    return ok and type(summary) == "table" and tonumber(summary.removed) or 0,
        ok and type(summary) == "table" and summary.blocked == true or false
end

local function BumpDpsAndViews(reason)
    local revisions = Nexus and Nexus.Revisions
    if revisions and type(revisions.Advance) == "function" then
        pcall(revisions.Advance, revisions.DPS_CHANGED, {
            scope="retention", reason=reason,
        })
    end
    local refresh = Nexus and Nexus.ViewRefresh
    if refresh and type(refresh.Request) == "function" then pcall(refresh.Request) end
end

function Retention.Enforce(database, reason)
    database = type(database) == "table" and database or NexusDB
    if type(database) ~= "table" then return nil, "database required" end
    local priorMeta = type(database.dataRetention) == "table"
        and database.dataRetention or nil
    local storedVersion = priorMeta and tonumber(priorMeta.schemaVersion) or nil
    if storedVersion and storedVersion > SCHEMA_VERSION then
        return { readOnly=true, schemaVersion=storedVersion, reason="future retention schema" }
    end
    local catalog = Nexus and Nexus.BuildCatalog
    local catalogSchema = catalog and type(catalog.SchemaVersion) == "function"
        and tonumber(catalog.SchemaVersion()) or 1
    if type(database.buildCatalog) == "table"
        and tonumber(database.buildCatalog.schemaVersion)
        and tonumber(database.buildCatalog.schemaVersion) > catalogSchema then
        return { readOnly=true, schemaVersion=storedVersion,
            reason="future build catalog schema" }
    end
    local evidence = Nexus and Nexus.LoadoutEvidence
    local evidenceSchema = evidence and type(evidence.SchemaVersion) == "function"
        and tonumber(evidence.SchemaVersion()) or 1
    if type(database.loadoutEvidence) == "table"
        and tonumber(database.loadoutEvidence.schemaVersion)
        and tonumber(database.loadoutEvidence.schemaVersion) > evidenceSchema then
        return { readOnly=true, schemaVersion=storedVersion,
            reason="future evidence schema" }
    end
    if type(database.dataCompaction) == "table"
        and tonumber(database.dataCompaction.schemaVersion)
        and tonumber(database.dataCompaction.schemaVersion) > 1 then
        return { readOnly=true, schemaVersion=storedVersion,
            reason="future compaction schema" }
    end
    database.dataRetention = priorMeta or {}
    database.dataRetention.schemaVersion = SCHEMA_VERSION

    local limits = ResolveLimits(database)
    local dps = type(database.dpsCapture) == "table" and database.dpsCapture or nil
    if not limits.enabled then
        local now = EpochNow()
        local prior = database.dataRetention.last
        local nextMaintenanceAt = tonumber(
            database.dataRetention.nextMaintenanceAt) or 0
        if type(prior) == "table" and prior.contentUnlimited == true
            and now > 0 and nextMaintenanceAt > now then
            local summary = Copy(prior)
            summary.reason = tostring(reason or "maintenance"):sub(1,80)
            summary.fastPath = true
            return summary
        end
        local character = type(dps) == "table" and dps.characterBest or nil
        local dummyCount = Count(type(character) == "table"
            and character.dummy or nil)
        local lkCount = Count(type(character) == "table" and character.lk or nil)
        local personalCount = Count(type(dps) == "table" and dps.personalBest or nil)
        local buildBestCount = Count(type(dps) == "table" and dps.buildBest or nil)
        local overlayCount = Count(database.communityBuilds)
        local evictionCount = Count(database.communityRetentionEvictions)
        local tombstoneCount = Count(database.syncTombstones)
        local evictions = PruneEvictionMarkers(database, now)
        local tombstones = PruneTombstones(database, now)
        local evidenceRemoved, evidenceBlocked = 0, false
        if tombstones.removed > 0 then
            evidenceRemoved, evidenceBlocked = CollectEvidence(database)
        end
        local summary = {
            schemaVersion=SCHEMA_VERSION,
            reason=tostring(reason or "maintenance"):sub(1,80),
            contentUnlimited=true,
            characterBestRemoved=0,selectedDummy=dummyCount,
            selectedLk=lkCount,selectedAverage=0,personalRemoved=0,
            buildBestRemoved=0,overlayBefore=overlayCount,
            overlayAfter=overlayCount,overlayRemoved=0,
            orphanAutoBuildsRemoved=0,perClassRemoved=0,
            perAuthorRemoved=0,globalRemoved=0,referencedBuildsKept=0,
            limits=Copy(limits),evictionMarkersAdded=0,
            evictionMarkersBefore=evictionCount,
            evictionMarkersAfter=evictions.after,
            evictionMarkersRemoved=evictions.removed,
            buildRetentionFloor=evictions.floor,
            tombstonesBefore=tombstoneCount,
            tombstonesAfter=tombstones.after,
            tombstonesRemoved=tombstones.removed,
            tombstoneFloor=tombstones.floor,
            evidenceRemoved=evidenceRemoved,evidenceGcBlocked=evidenceBlocked,
            fastPath=evictions.removed == 0 and tombstones.removed == 0,
        }
        local prior = database.dataRetention.last
        local modeChanged = type(prior) ~= "table"
            or prior.contentUnlimited ~= true
        if modeChanged or evictions.removed > 0 or tombstones.removed > 0
            or evidenceRemoved > 0 then
            database.dataRetention.lastRun = now
            database.dataRetention.last = Copy(summary)
        end
        database.dataRetention.nextMaintenanceAt = now > 0 and now + 300 or 0
        return summary
    end
    local selected, fingerprints, selectedBuildIds, categoryCounts =
        SelectCharacterBest(dps, limits, database.communityBuilds)
    local characterRemoved = TrimCharacterBest(dps, selected)
    local personalRemoved = dps and TrimFingerprintMap(
        dps.personalBest, limits.personalFingerprints, fingerprints) or 0
    local buildBestRemoved = dps and TrimFingerprintMap(
        dps.buildBest, limits.buildBestFingerprints, fingerprints) or 0
    local referenced = CollectBuildReferences(dps, selectedBuildIds)
    local overlay = PruneOverlay(database, referenced, limits)
    local now = EpochNow()
    local evictions = PruneEvictionMarkers(database, now)
    local tombstones = PruneTombstones(database, now)
    local dpsRemoved = characterRemoved + personalRemoved + buildBestRemoved
    local evidenceRemoved, evidenceBlocked = 0, false
    if dpsRemoved > 0 or overlay.removed > 0 or tombstones.removed > 0 then
        evidenceRemoved, evidenceBlocked = CollectEvidence(database)
    end
    if dpsRemoved > 0 then BumpDpsAndViews(reason or "data retention") end

    local summary = {
        schemaVersion=SCHEMA_VERSION,
        reason=tostring(reason or "maintenance"):sub(1, 80),
        characterBestRemoved=characterRemoved,
        selectedDummy=categoryCounts.dummy,
        selectedLk=categoryCounts.lk,
        selectedAverage=categoryCounts.average,
        personalRemoved=personalRemoved,
        buildBestRemoved=buildBestRemoved,
        overlayBefore=overlay.before,
        overlayAfter=overlay.after,
        overlayRemoved=overlay.removed,
        orphanAutoBuildsRemoved=overlay.orphaned,
        perClassRemoved=overlay.perClass,
        perAuthorRemoved=overlay.perAuthor,
        globalRemoved=overlay.global,
        referencedBuildsKept=overlay.referencedKept,
        limits=Copy(limits),
        evictionMarkersAdded=overlay.markersAdded,
        evictionMarkersBefore=evictions.before,
        evictionMarkersAfter=evictions.after,
        evictionMarkersRemoved=evictions.removed,
        buildRetentionFloor=evictions.floor,
        tombstonesBefore=tombstones.before,
        tombstonesAfter=tombstones.after,
        tombstonesRemoved=tombstones.removed,
        tombstoneFloor=tombstones.floor,
        evidenceRemoved=evidenceRemoved,
        evidenceGcBlocked=evidenceBlocked,
    }
    local changed = dpsRemoved > 0 or overlay.removed > 0
        or evictions.removed > 0 or tombstones.removed > 0
        or evidenceRemoved > 0
    if changed or type(database.dataRetention.last) ~= "table" then
        database.dataRetention.lastRun = now
        database.dataRetention.last = Copy(summary)
    end
    return summary
end

function Retention.Init(database)
    return Retention.Enforce(database, "startup")
end

function Retention.Request(reason)
    local scheduler = Nexus and Nexus.Scheduler
    if not (scheduler and scheduler.IsInitialized and scheduler.IsInitialized()
        and type(scheduler.After) == "function") then
        return false, "scheduler unavailable"
    end
    if type(scheduler.Pending) == "function"
        and scheduler.Pending("data-retention.enforce") then
        return true
    end
    return scheduler.After("data-retention.enforce", 3, function()
        Retention.Enforce(NexusDB, reason or "scheduled")
    end)
end

function Retention.AllowsRemoteRevision(_, stamp, database, buildId)
    database = type(database) == "table" and database or NexusDB
    local marker = type(database) == "table"
        and type(database.communityRetentionEvictions) == "table"
        and database.communityRetentionEvictions[buildId] or nil
    local revision = type(marker) == "table"
        and tonumber(marker.revision or marker.stamp) or tonumber(marker) or 0
    return (tonumber(stamp) or 0) > (revision or 0)
end

function Retention.ReleaseSupersededAutoBuild(buildId, database)
    if not ValidBuildId(buildId) then return false end
    database = type(database) == "table" and database or NexusDB
    if type(database) ~= "table" then return false end
    local overlay = type(database.communityBuilds) == "table"
        and database.communityBuilds or {}
    local build = overlay[buildId]
    if type(build) ~= "table" or build.autoDps ~= true or IsLocalBuild(build) then
        return false
    end
    if CollectBuildReferences(database.dpsCapture)[buildId] then return false end
    MarkEvictions(database, overlay, { buildId })
    local removed = RemoveOverlayIds(database, { buildId })
    if removed > 0 then CollectEvidence(database); return true end
    return false
end

function Retention.Limits(database)
    database = type(database) == "table" and database or NexusDB
    return ResolveLimits(database)
end

function Retention.Stats(database)
    database = type(database) == "table" and database or NexusDB
    local meta = type(database) == "table" and database.dataRetention or nil
    return type(meta) == "table" and Copy(meta.last) or nil
end

function Retention.SchemaVersion()
    return SCHEMA_VERSION
end
