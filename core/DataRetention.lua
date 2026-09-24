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

-- After bundle occupancy, the legacy PR #68 locations are preserved input and
-- never become a fallback or a write target.
local function DurablePayload(database, field)
    local bundle = type(database) == "table"
        and rawget(database, "authorityBundle") or nil
    if type(bundle) == "table" then return rawget(bundle, field) end
    return type(database) == "table" and rawget(database, field) or nil
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
    local catalog = Nexus and Nexus.BuildCatalog
    if row.ownerVerified == true and catalog and type(catalog.Get) == "function"
        and ValidBuildId(row.buildId)
        and IsLocalBuild(catalog.Get(row.buildId)) then return true end
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
    -- MASTER-RC-012: canonical comparator, never tostring. tostring makes
    -- numeric 1 and string "1" tie and sorts numeric 10 before numeric 2.
    return Identity.CompareTypedIds(left.key, right.key) < 0
end

local function BetterRow(left, right)
    if left.protected ~= right.protected then return left.protected end
    if left.stamp ~= right.stamp then return left.stamp > right.stamp end
    if left.dps ~= right.dps then return left.dps > right.dps end
    -- MASTER-RC-012: canonical comparator, never tostring. tostring makes
    -- numeric 1 and string "1" tie and sorts numeric 10 before numeric 2.
    return Identity.CompareTypedIds(left.key, right.key) < 0
end

-- MASTER-RC-012: the one canonical encoder, shared from core/Identity.lua.
local TypedIdentity = Identity.TypedIdentity

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

    -- Reserve combined-pair inputs from the same deterministic strongest-DPS
    -- owner used by Community and Leaderboard. Category maxima stay independent.
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
                key=pair.identity,dps=pair.bestDps,
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

-- Catalog rows are read and mutated only through the catalog authority bound
-- to this exact database. A detached database receives zero catalog work.
-- MASTER-RC-008 / RAW-01. A detached instance must never fall back to the raw
-- NexusDB global: RAW-01 is RED when "a detached instance falls back to global
-- NexusDB". When no exact database is supplied the only admissible source is
-- the catalog's exact bound authority database, and when there is none the
-- caller receives its fixed empty or refusing result rather than raw storage.
local function AuthorityDatabase(database)
    if type(database) == "table" then return database end
    local catalog = Nexus and Nexus.BuildCatalog
    if catalog and type(catalog.BoundDatabase) == "function" then
        local bound = catalog.BoundDatabase()
        if type(bound) == "table" then return bound end
    end
    return nil
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

local pendingOverlayScans = setmetatable({}, {__mode="k"})

-- Small roots retain the established one-call behavior. Larger roots keep one
-- generation-bound cursor and advance one bounded catalog slice per enforce
-- call. A stale cursor discards the whole unpublished collection.
local function OverlaySummaries(catalog, database)
    local job = pendingOverlayScans[database]
    if not job then
        local all, why = catalog.Summaries()
        if type(all) == "table" then
            local rows = {}
            for id, summary in pairs(all) do
                if type(summary) == "table"
                    and summary.source == "overlay" then
                    rows[id] = summary
                end
            end
            return rows, true
        end
        if why ~= "CURSOR_REQUIRED" then return nil, nil, why end
        local token, cursorWhy = catalog.BeginSummaryCursor()
        if not token then return nil, nil, cursorWhy or "CURSOR_UNAVAILABLE" end
        job = {catalog=catalog, token=token, rows={}, slices=0}
        pendingOverlayScans[database] = job
    elseif job.catalog ~= catalog then
        pendingOverlayScans[database] = nil
        return nil, nil, "CATALOG_OWNER_CHANGED"
    end

    local summary, done, err = catalog.SummaryCursorNext(job.token)
    job.slices = job.slices + 1
    if err then
        pendingOverlayScans[database] = nil
        return nil, nil, err
    end
    if type(summary) == "table" and summary.source == "overlay" then
        job.rows[summary.id] = summary
    end
    if done then
        pendingOverlayScans[database] = nil
        return job.rows, true
    end
    return nil, false, nil, job.slices
end

-- One retention transaction evicts every marked overlay row and installs
-- its replay barrier atomically; nothing is removed unless all of it commits.
local function EvictOverlayIds(catalog, database, ids, transaction)
    if #ids == 0 then return 0, 0 end
    table.sort(ids, function(left, right)
        return Identity.CompareTypedIds(left, right) < 0
    end)
    local handle = transaction or catalog.BeginCatalogMaintenance({database=database,
        operation="retention"})
    if not handle then return 0, 0 end
    local staged = 0
    for _, id in ipairs(ids) do
        local ok, why = catalog.MaintenanceEvictOverlay(handle, id)
        if ok and why ~= "BARRIER_REPLAY_NOOP" then staged = staged + 1 end
    end
    if staged == 0 then
        if not transaction then catalog.CancelMaintenance(handle) end
        return 0, 0
    end
    if not transaction then
        local ok, why, ticket = catalog.CommitMaintenance(handle)
        if ok == nil and why == "ROOT_MUTATION_PENDING" then return 0, 0, ticket end
        if not ok then return 0, 0 end
    end
    return staged, staged
end

local function PruneOverlay(database, referenced, limits, transaction, overlay)
    local catalog = CatalogFor(database)
    if not catalog then
        return {before=0, after=0, removed=0, orphaned=0, perClass=0,
            perAuthor=0, global=0, referencedKept=0, markersAdded=0}
    end
    overlay = type(overlay) == "table" and overlay or {}
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
    local removed, markersAdded = EvictOverlayIds(catalog, database, ids, transaction)
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

-- Replay barriers and tombstones are catalog ingress authority. Only the
-- central transaction may expire a current-session barrier or retire a
-- current-session tombstone by trusted local age; reloaded and opaque
-- reservations stay block-all, and capacity pressure never prunes a winner.
local function ExpireReservations(database, stepName, expireName, transaction)
    local catalog = CatalogFor(database)
    if not catalog then return 0 end
    local handle = transaction or catalog.BeginCatalogMaintenance({database=database,
        operation="retention"})
    if not handle then return 0 end
    local cursor, staged = nil, 0
    for _ = 1, DEFAULT_LIMITS.evictionMarkers do
        local id, _, done = catalog[stepName](cursor)
        if done or id == nil then break end
        if catalog[expireName](handle, id) then staged = staged + 1 end
        cursor = id
    end
    if staged == 0 then
        if not transaction then catalog.CancelMaintenance(handle) end
        return 0
    end
    if not transaction and not catalog.CommitMaintenance(handle) then return 0 end
    return staged
end

-- Retention markers (owner decision of 2026-09-24). Suppression stays exact
-- per typed ID; no global floor. A current-format marker carries its trusted
-- local creation time. An untimed current-format marker and a recognized
-- legacy numeric marker carry none: their first local observation is
-- recorded once, here, in this owner's saved metadata (markerFirstSeen: one
-- entry per such marker, never more than the marker limit). A reload, a read
-- or a repeated observation never resets it, and a marker's own number is
-- never used as age. The catalog expires a marker 30 days after its age,
-- inside this transaction; an entry leaves the map with its marker. Opaque,
-- malformed and future markers are never aged or expired, a full catalog is
-- not a reason to expire anything, and removal markers keep their own rules.
local function PruneEvictionMarkers(database, transaction, priorMeta)
    local before = Count(DurablePayload(database,
        "communityRetentionEvictions"))
    local prior = type(priorMeta) == "table"
        and type(priorMeta.markerFirstSeen) == "table"
        and priorMeta.markerFirstSeen or {}
    local result = {before=before, after=before, removed=0, floor=0,
        firstSeen=prior, firstSeenRecorded=0, firstSeenChanged=false}
    local catalog = CatalogFor(database)
    if not (catalog and transaction and type(catalog.BarrierNext) == "function") then
        return result
    end
    local now = type(catalog.TrustedServerTime) == "function"
        and catalog.TrustedServerTime() or nil
    local firstSeen, cursor, complete = {}, nil, false
    for _ = 1, DEFAULT_LIMITS.evictionMarkers + 1 do
        local id, state, done = catalog.BarrierNext(cursor)
        if done or id == nil then
            complete = id == nil and state == nil
            break
        end
        cursor = id
        local kind = type(state) == "table" and state.ageKind or nil
        local seen
        if kind == "untimed" or kind == "legacy" then
            -- The same range as the catalog's age check: an integer from 1
            -- to 2^53 - 1. Anything else is recorded again from the clock.
            seen = tonumber(prior[id])
            if not (seen and seen >= 1 and seen <= 9007199254740991
                and seen == math.floor(seen)) then
                seen = now
                if seen then result.firstSeenRecorded = result.firstSeenRecorded + 1 end
            end
            firstSeen[id] = seen
        end
        if kind and catalog.MaintenanceExpireBarrier(transaction, id, seen) then
            result.removed = result.removed + 1
            firstSeen[id] = nil
        end
    end
    -- An incomplete walk keeps every earlier observation it did not reach.
    if not complete then
        for id, seen in pairs(prior) do
            if firstSeen[id] == nil then firstSeen[id] = seen end
        end
    end
    local changed = result.firstSeenRecorded > 0 or result.removed > 0
    if not changed then
        for id, seen in pairs(prior) do
            if firstSeen[id] ~= seen then changed = true; break end
        end
    end
    if not changed then
        for id in pairs(firstSeen) do
            if prior[id] == nil then changed = true; break end
        end
    end
    result.firstSeen, result.firstSeenChanged = firstSeen, changed
    result.after = math.max(0, before - result.removed)
    return result
end

local function PruneTombstones(database, transaction)
    local exactBefore = Count(DurablePayload(database, "syncTombstones"))
    -- As with eviction markers, a deleted build's exact tombstone cannot act
    -- as a namespace-wide watermark. Immutable baseline masks remain exact and
    -- are never candidates here.
    local removed = ExpireReservations(database, "TombstoneNext",
        "MaintenanceRetireTombstone", transaction)
    return {
        before=exactBefore, after=math.max(0, exactBefore - removed),
        removed=removed, floor=0,
    }
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

local pendingEnforcements = setmetatable({}, {__mode="k"})

local function PrepareMetadata(source, summary, now, changed, firstSeen)
    local meta = DeepCopy(type(source) == "table" and source or {})
    meta.schemaVersion = SCHEMA_VERSION
    -- Bounded first-observation map of retention markers without local age.
    if firstSeen ~= nil then
        meta.markerFirstSeen = next(firstSeen) ~= nil and DeepCopy(firstSeen) or nil
    end
    if changed or type(meta.last) ~= "table" then
        local terminal = DeepCopy(summary)
        terminal.pending = false
        meta.lastRun = now
        meta.last = terminal
    end
    if summary.contentUnlimited then
        meta.nextMaintenanceAt = now > 0 and now + 300 or 0
    end
    return meta
end

local function FinishEnforcement(database, catalog, transaction, summary,
                                 changed, overrides)
    local function Finish()
        if changed and (summary.characterBestRemoved or 0)
            + (summary.personalRemoved or 0)
            + (summary.buildBestRemoved or 0) > 0 then
            BumpDpsAndViews(summary.reason)
        end
        local result = Copy(summary)
        result.pending = false
        return result
    end
    if not transaction then return Finish() end
    local committed, why, ticket = catalog.CommitMaintenance(
        transaction, overrides)
    if committed == true then return Finish() end
    if committed ~= nil or why ~= "ROOT_MUTATION_PENDING"
        or type(ticket) ~= "table" then
        return {pending=false, blocked=true, reason=why or "CANDIDATE_FAILED"}
    end
    local job = {ticket=ticket, result={pending=true, mutationTicket=ticket,
        overlayRemoved=0, perAuthorRemoved=0, tombstonesRemoved=0,
        evictionMarkersRemoved=0, evictionMarkersAdded=0}}
    pendingEnforcements[database] = job
    local bound = catalog.BindMutationCompletion(ticket, function(outcome)
        if outcome.committed == true and outcome.state == "committed"
            and outcome.database == database and CatalogFor(database) == catalog
            and rawget(database, "authorityBundle") == outcome.bundle then
            job.result = Finish()
        else
            job.result = {pending=false, blocked=true,
                reason=outcome.reason or "SOURCE_DRIFT"}
        end
    end)
    if not bound then
        job.result = {pending=false, blocked=true, reason="INVALID_MUTATION_TICKET"}
    end
    return Copy(job.result)
end

function Retention.Enforce(database, reason)
    -- MASTER-RC-008 / RAW-01: an unsupplied database resolves to the exact
    -- bound authority, never to the raw NexusDB global. A database supplied
    -- explicitly by the coordinator is operated on as given; what is forbidden
    -- is the silent global fallback, and deciding ADMISSION from raw fields of
    -- a table that was never proven to be the authority -- see
    -- AllowsRemoteRevision.
    database = AuthorityDatabase(database)
    if type(database) ~= "table" then return nil, "database required" end
    local pending = pendingEnforcements[database]
    if pending then
        local result = Copy(pending.result)
        if not result.pending then pendingEnforcements[database] = nil end
        return result
    end
    local priorMeta = DurablePayload(database, "dataRetention")
    local storedVersion = priorMeta and tonumber(priorMeta.schemaVersion) or nil
    if storedVersion and storedVersion > SCHEMA_VERSION then
        return { readOnly=true, schemaVersion=storedVersion, reason="future retention schema" }
    end
    local catalog = Nexus and Nexus.BuildCatalog
    local catalogSchema = catalog and type(catalog.SchemaVersion) == "function"
        and tonumber(catalog.SchemaVersion()) or 1
    local catalogMeta = DurablePayload(database, "buildCatalog")
    if type(catalogMeta) == "table"
        and tonumber(catalogMeta.schemaVersion)
        and tonumber(catalogMeta.schemaVersion) > catalogSchema then
        return { readOnly=true, schemaVersion=storedVersion,
            reason="future build catalog schema" }
    end
    local evidence = Nexus and Nexus.LoadoutEvidence
    local evidenceSchema = evidence and type(evidence.SchemaVersion) == "function"
        and tonumber(evidence.SchemaVersion()) or 1
    local evidenceStore = DurablePayload(database, "loadoutEvidence")
    if type(evidenceStore) == "table"
        and tonumber(evidenceStore.schemaVersion)
        and tonumber(evidenceStore.schemaVersion) > evidenceSchema then
        return { readOnly=true, schemaVersion=storedVersion,
            reason="future evidence schema" }
    end
    local compactionMeta = DurablePayload(database, "dataCompaction")
    if type(compactionMeta) == "table"
        and tonumber(compactionMeta.schemaVersion)
        and tonumber(compactionMeta.schemaVersion) > 1 then
        return { readOnly=true, schemaVersion=storedVersion,
            reason="future compaction schema" }
    end
    local limits = ResolveLimits(database)
    -- Every run samples the catalog's trusted clock, the fast path too, so a
    -- backward step inside the session is noticed before any marker expiry.
    local clockOwner = Nexus and Nexus.BuildCatalog
    if clockOwner and type(clockOwner.TrustedServerTime) == "function" then
        pcall(clockOwner.TrustedServerTime)
    end
    if not limits.enabled then
        pendingOverlayScans[database] = nil
        local now = EpochNow()
        local prior = priorMeta and priorMeta.last
        local nextMaintenanceAt = tonumber(
            priorMeta and priorMeta.nextMaintenanceAt) or 0
        if type(prior) == "table" and prior.contentUnlimited == true
            and now > 0 and nextMaintenanceAt > now then
            local summary = Copy(prior)
            summary.reason = tostring(reason or "maintenance"):sub(1,80)
            summary.fastPath = true
            return summary
        end
        -- A busy catalog is found before any payload is copied.
        local owner = CatalogFor(database)
        local transaction = owner and owner.BeginCatalogMaintenance({database=database,
            operation="retention"})
        if owner and not transaction then
            return {pending=false, blocked=true, reason="ROOT_MUTATION_PENDING"}
        end
        local dpsSource = DurablePayload(database, "dpsCapture")
        local dps = type(dpsSource) == "table" and DeepCopy(dpsSource) or nil
        local overlaySource = DurablePayload(database, "communityBuilds")
        overlaySource = type(overlaySource) == "table" and overlaySource or {}
        local character = type(dps) == "table" and dps.characterBest or nil
        local dummyCount = Count(type(character) == "table"
            and character.dummy or nil)
        local lkCount = Count(type(character) == "table" and character.lk or nil)
        local personalCount = Count(type(dps) == "table" and dps.personalBest or nil)
        local buildBestCount = Count(type(dps) == "table" and dps.buildBest or nil)
        local overlayCount = Count(overlaySource)
        local evictionCount = Count(DurablePayload(database,
            "communityRetentionEvictions"))
        local tombstoneCount = Count(DurablePayload(database,
            "syncTombstones"))
        local evictions = PruneEvictionMarkers(database, transaction, priorMeta)
        local tombstones = PruneTombstones(database, transaction)
        local evidenceRemoved, evidenceBlocked = 0, false
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
            evictionMarkersFirstSeenRecorded=evictions.firstSeenRecorded,
            buildRetentionFloor=evictions.floor,
            tombstonesBefore=tombstoneCount,
            tombstonesAfter=tombstones.after,
            tombstonesRemoved=tombstones.removed,
            tombstoneFloor=tombstones.floor,
            evidenceRemoved=evidenceRemoved,evidenceGcBlocked=evidenceBlocked,
            fastPath=evictions.removed == 0 and tombstones.removed == 0,
        }
        local prior = priorMeta and priorMeta.last
        local modeChanged = type(prior) ~= "table"
            or prior.contentUnlimited ~= true
        local changed = modeChanged or evictions.removed > 0
            or tombstones.removed > 0
        local nextMaintenanceAt = now > 0 and now + 300 or 0
        local metadataChanged = changed or type(priorMeta) ~= "table"
            or rawget(priorMeta, "nextMaintenanceAt") ~= nextMaintenanceAt
            or evictions.firstSeenChanged
        local overrides = transaction and metadataChanged and {
            dataRetention=PrepareMetadata(priorMeta, summary, now, changed,
                evictions.firstSeen),
        } or nil
        return FinishEnforcement(database, owner, transaction, summary,
            changed, overrides)
    end
    local owner = CatalogFor(database)
    local overlayRows = {}
    if owner then
        local complete, scanWhy, slices
        overlayRows, complete, scanWhy, slices =
            OverlaySummaries(owner, database)
        if complete == false then
            return {pending=true, workDomain="retention-overlay-scan",
                scanSlices=slices or 0, overlayRemoved=0,
                perAuthorRemoved=0, tombstonesRemoved=0,
                evictionMarkersRemoved=0, evictionMarkersAdded=0}
        end
        if complete ~= true then
            return {pending=false, blocked=true,
                reason=scanWhy or "CATALOG_SCAN_FAILED"}
        end
    end
    local transaction = owner and owner.BeginCatalogMaintenance({database=database,
        operation="retention"})
    if owner and not transaction then
        return {pending=false, blocked=true, reason="ROOT_MUTATION_PENDING"}
    end
    local dpsSource = DurablePayload(database, "dpsCapture")
    local dps = type(dpsSource) == "table" and DeepCopy(dpsSource) or nil
    local overlaySource = DurablePayload(database, "communityBuilds")
    overlaySource = type(overlaySource) == "table" and overlaySource or {}
    local selected, fingerprints, selectedBuildIds, categoryCounts =
        SelectCharacterBest(dps, limits, overlaySource)
    local characterRemoved = TrimCharacterBest(dps, selected)
    local personalRemoved = dps and TrimFingerprintMap(
        dps.personalBest, limits.personalFingerprints, fingerprints) or 0
    local buildBestRemoved = dps and TrimFingerprintMap(
        dps.buildBest, limits.buildBestFingerprints, fingerprints) or 0
    local referenced = CollectBuildReferences(dps, selectedBuildIds)
    local evictions = PruneEvictionMarkers(database, transaction, priorMeta)
    local overlay = PruneOverlay(
        database, referenced, limits, transaction, overlayRows)
    local now = EpochNow()
    local tombstones = PruneTombstones(database, transaction)
    local dpsRemoved = characterRemoved + personalRemoved + buildBestRemoved
    local evidenceRemoved, evidenceBlocked = 0, false

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
        evictionMarkersFirstSeenRecorded=evictions.firstSeenRecorded,
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
    local metadataChanged = changed or type(priorMeta) ~= "table"
        or type(priorMeta.last) ~= "table" or evictions.firstSeenChanged
    local overrides = transaction and metadataChanged and {
        dataRetention=PrepareMetadata(priorMeta, summary, now, changed,
            evictions.firstSeen),
        dpsCapture=dps or {},
    } or nil
    return FinishEnforcement(database, owner, transaction, summary,
        changed, overrides)
end

function Retention.Init(database)
    return Retention.Enforce(database, "startup")
end

local ScheduleRetention
-- A run that finds the catalog busy with another change is tried again with a
-- growing delay (5, 10, 20 and 40 s, then every 60 s) for about one hour
-- (64 attempts, 3675 s), so a request made during a long first compaction or
-- identity repair is not lost and never becomes an endless retry. A busy
-- attempt stops before it copies any payload.
local BUSY_RETRY_DELAY, BUSY_RETRY_MAX_DELAY, BUSY_RETRY_LIMIT = 5, 60, 64
ScheduleRetention = function(scheduler, reason, delay, busyAttempts)
    return scheduler.After("data-retention.enforce", delay, function()
        -- Resolve the exact bound authority at run time; never the raw global.
        local result = Retention.Enforce(nil, reason)
        local attempts = busyAttempts or 0
        if type(result) == "table" and result.pending == true then
            -- A new scheduler generation runs this continuation on a later
            -- turn, so one callback cannot drain a retained catalog cursor.
            ScheduleRetention(scheduler, reason, 0, busyAttempts)
        elseif type(result) == "table" and result.blocked == true
            and result.reason == "ROOT_MUTATION_PENDING"
            and attempts < BUSY_RETRY_LIMIT then
            ScheduleRetention(scheduler, reason, math.min(BUSY_RETRY_MAX_DELAY,
                BUSY_RETRY_DELAY * 2 ^ attempts), attempts + 1)
        end
    end)
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
    return ScheduleRetention(scheduler, reason or "scheduled", 3)
end

-- Every non-none replay barrier vetoes every inbound row for its exact typed
-- ID. No sender-controlled revision, stamp, clock, or arrival order can clear
-- it; only trusted local expiry inside the central catalog transaction can.
function Retention.AllowsRemoteRevision(_, _, database, buildId)
    local catalog = CatalogFor(AuthorityDatabase(database))
    if not catalog then
        -- No bound authority proves this table, so it holds no admitted rows
        -- and no barrier of its own. A raw communityRetentionEvictions marker
        -- in an unbound table is not authority and never vetoes (MASTER-RC-008;
        -- architecture line 188 makes such fields claims, not proof).
        return true
    end
    local barrier = catalog.BarrierState(buildId)
    return not (type(barrier) == "table" and barrier.blocked == true)
end

function Retention.ReleaseSupersededAutoBuild(buildId, database)
    if not ValidBuildId(buildId) then return false end
    database = AuthorityDatabase(database)
    local catalog = type(database) == "table" and CatalogFor(database) or nil
    if not catalog then return false end
    local build = catalog.Get(buildId)
    if type(build) ~= "table" or build.autoDps ~= true or IsLocalBuild(build) then
        return false
    end
    if CollectBuildReferences(DurablePayload(database, "dpsCapture"))[buildId] then
        return false
    end
    local removed, _, ticket = EvictOverlayIds(catalog, database, { buildId })
    if ticket then return nil, "ROOT_MUTATION_PENDING", ticket end
    if removed > 0 then return true end
    return false
end

function Retention.Limits(database)
    return ResolveLimits(AuthorityDatabase(database))
end

function Retention.Stats(database)
    database = AuthorityDatabase(database)
    local meta = DurablePayload(database, "dataRetention")
    return type(meta) == "table" and Copy(meta.last) or nil
end

-- Read-only count of retention markers that wait for their locally recorded
-- first observation to age. Starts no work and writes nothing.
function Retention.MarkerFirstSeenCount(database)
    local meta = DurablePayload(AuthorityDatabase(database), "dataRetention")
    return Count(type(meta) == "table" and meta.markerFirstSeen or nil)
end

function Retention.SchemaVersion()
    return SCHEMA_VERSION
end
