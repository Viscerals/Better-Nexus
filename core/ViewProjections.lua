-- Nexus: revision/filter-cached defensive data-browser projections.
--
-- This module owns no frames, timers, SavedVariables, transport, or gameplay
-- actions. It reads only the public BuildCatalog/DpsCapture surfaces and keeps
-- one last-good build and leaderboard projection per view kind.

Nexus = Nexus or {}
local Identity = assert(Nexus.Identity,
    "Nexus Identity must load before ViewProjections")
local CandidateEvidence = assert(Nexus.CandidateEvidence,
    "CandidateEvidence must load before ViewProjections")
local Projections = {}
Nexus.ViewProjections = Projections

local caches = {builds={}, leaderboard={}}
local counters = {
    builds={hits=0,rebuilds=0,failures=0,catalogWalks=0,dpsReads=0,
        sorts=0,defensiveCopies=0},
    leaderboard={hits=0,rebuilds=0,failures=0,boardReads=0,sorts=0,
        defensiveCopies=0},
}
local jobs = {builds=nil,leaderboard=nil}
local savedRelationResolver
local savedRelationGeneration = 0
local workStats = {
    acquisitions=0,sourceRows=0,joins=0,comparisons=0,copies=0,
    sortMoves=0,publications=0,cancellations=0,binds=0,
    communityPumps=0,leaderboardPumps=0,
    maxSourceRowsPerPump=0,maxComparisonsPerPump=0,
    maxSortMovesPerPump=0,maxJoinsPerPump=0,maxCopiesPerPump=0,
    classFromRecord=0,classFromBuild=0,classFromCurrentPlayer=0,
    classFromOwner=0,
    classUnavailable=0,classConflicts=0,
}
local MAX_SOURCE_PER_PUMP = 25
local MAX_COMPARISONS_PER_PUMP = 500
local MAX_SORT_MOVES_PER_PUMP = 500

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

local function Count(source)
    local n = 0
    for _ in pairs(type(source) == "table" and source or {}) do n = n + 1 end
    return n
end

local function Part(value)
    local kind = type(value)
    local text = tostring(value == nil and "" or value)
    return kind .. ":" .. tostring(#text) .. ":" .. text
end

local function TypedIdentity(value)
    return type(value) .. ":" .. tostring(value == nil and "" or value)
end

local function CacheKey(parts)
    local out = {}
    for index, value in ipairs(parts) do out[index] = Part(value) end
    return table.concat(out, "|")
end

local function Revision(event)
    local revisions = Nexus and Nexus.Revisions
    return revisions and revisions.Get and (revisions.Get(event) or 0) or 0
end

local function CurrentIdentity()
    local name = UnitName and UnitName("player") or nil
    if not name or name == "" then return "", "" end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then realm = GetRealmName and GetRealmName() end
    local player = Identity.PlayerKey(name)
    local owner = Identity.OwnerKey(name, realm or "unknown")
    return player or "", owner or ""
end

local VALID_CLASS = {
    WARRIOR=true,PALADIN=true,HUNTER=true,ROGUE=true,PRIEST=true,
    DEATHKNIGHT=true,SHAMAN=true,MAGE=true,WARLOCK=true,DRUID=true,
}

local function NormalizeClass(value)
    value = type(value) == "string" and value:upper() or nil
    return value and VALID_CLASS[value] and value or nil
end

local function CurrentClass()
    if type(UnitClass) ~= "function" then return nil end
    local ok, _, token = pcall(UnitClass, "player")
    token = ok and type(token) == "string" and token:upper() or nil
    return NormalizeClass(token)
end

local function NormalizeBuildFilters(filters)
    filters = type(filters) == "table" and filters or {}
    local player, ownerKey = CurrentIdentity()
    local search = tostring(filters.search or ""):lower()
        :gsub("^%s+", ""):gsub("%s+$", "")
    local currentClassOnly = filters.currentClassOnly ~= false
    local currentClass = CurrentClass() or ""
    local classFilter = currentClassOnly and currentClass or "ALL"
    local scope = filters.scope == "mine" and "mine" or "all"
    local sortMode = filters.sortMode
    if sortMode ~= "recent" and sortMode ~= "title" then sortMode = "dps" end
    local page = tonumber(filters.page)
    page = page and page >= 1 and math.floor(page) or 1
    return {
        search=search, classFilter=classFilter, scope=scope,
        sortMode=sortMode, player=player, ownerKey=ownerKey,
        currentClassOnly=currentClassOnly,currentClass=currentClass,
        qualifiedOnly=filters.qualifiedOnly ~= false,
        page=page,pageSize=20,
    }
end

local function NormalizeLeaderboardFilters(category, filters)
    filters = type(filters) == "table" and filters or {}
    category = category == "dummy" and "dummy"
        or category == "combined" and "combined" or "lk"
    local classFilter = type(filters.classFilter) == "string"
        and filters.classFilter:upper() or "ALL"
    if classFilter == "" then classFilter = "ALL" end
    local player, ownerKey = CurrentIdentity()
    return {
        category=category,
        search=tostring(filters.search or ""):lower(),
        classFilter=classFilter,
        player=player,ownerKey=ownerKey,currentClass=CurrentClass() or "",
    }
end

local function BuildKey(filters)
    local revisions = Nexus and Nexus.Revisions or {}
    return CacheKey({
        Revision(revisions.BUILD_LIBRARY_CHANGED),
        Revision(revisions.DPS_CHANGED),
        filters.scope, filters.classFilter, filters.search, filters.sortMode,
        filters.player, filters.ownerKey,
        filters.currentClassOnly,filters.currentClass,filters.qualifiedOnly,
        savedRelationGeneration,
    })
end

local function LeaderboardKey(filters)
    local revisions = Nexus and Nexus.Revisions or {}
    return CacheKey({
        Revision(revisions.BUILD_LIBRARY_CHANGED),
        Revision(revisions.DPS_CHANGED),
        filters.category, filters.classFilter, filters.search,
        filters.player, filters.ownerKey, filters.currentClass,
    })
end

local function Cached(kind, keyBuilder, builder)
    local cache = caches[kind]
    local stats = counters[kind]
    local initialKey = keyBuilder()
    if cache.key == initialKey and type(cache.rows) == "table" then
        stats.hits = stats.hits + 1
        stats.defensiveCopies = stats.defensiveCopies + 1
        return DeepCopy(cache.rows), DeepCopy(cache.summary)
    end
    for _ = 1, 2 do
        local beforeKey = keyBuilder()
        stats.rebuilds = stats.rebuilds + 1
        local ok, rows, summary = pcall(builder)
        local afterKey = keyBuilder()
        if not ok or type(rows) ~= "table" then
            stats.failures = stats.failures + 1
            return nil, nil, tostring(rows or "projection failed")
        end
        if beforeKey == afterKey then
            cache.key = afterKey
            -- Builders return private snapshots. Keep that object as the
            -- immutable cache and make exactly one defensive copy for the
            -- caller; the old path copied every row three times on rebuild.
            cache.rows = rows
            cache.summary = summary
            stats.defensiveCopies = stats.defensiveCopies + 1
            return DeepCopy(cache.rows), DeepCopy(cache.summary)
        end
    end
    stats.failures = stats.failures + 1
    return nil, nil, "represented data changed during projection"
end

local function IsOwnBuild(build, filters)
    return Identity.LocalOwnsBuild(build, filters.ownerKey)
end

local function ProjectSavedBuild(build, unit)
    if Identity.SavedMirrorKind(build) ~= "saved"
        or type(savedRelationResolver) ~= "function" then return nil end
    workStats.joins = workStats.joins + 1
    if type(unit) == "table" then
        unit.joins = (unit.joins or 0) + 1
    end
    local ok, projected, relation = pcall(savedRelationResolver, build)
    if not ok or type(projected) ~= "table"
        or tostring(projected.id or "") ~= tostring(build.id or "") then
        return nil, nil
    end
    if type(relation) ~= "table"
        or type(relation.buildId) ~= "string"
        or type(relation.fingerprint) ~= "string" then
        relation = nil
    end
    projected.recordBuildId = relation and relation.buildId or nil
    projected.publishedBuildId = type(projected.publishedBuildId) == "string"
        and projected.publishedBuildId or nil
    projected.class = NormalizeClass(projected.class) or "UNKNOWN"
    return projected, relation
end

local function PrepareSavedBuild(build, filters, unit)
    if Identity.SavedMirrorKind(build) ~= "saved" then return build, nil end
    local projected, relation = ProjectSavedBuild(build, unit)
    if projected then return projected, relation end
    build.recordBuildId, build.publishedBuildId = nil, nil
    build.class = "UNKNOWN"
    return build, nil
end

local function BuildDpsSummary(build, eligibility, relation)
    local fingerprint
    local savedKind = Identity.SavedMirrorKind(build)
    if savedKind == "saved" then
        fingerprint = relation and relation.fingerprint or nil
    elseif savedKind == "ordinary" then
        fingerprint = type(build) == "table"
            and type(build.fingerprint) == "string" and build.fingerprint or nil
    end
    return fingerprint and eligibility[fingerprint] or nil
end

local function IsLoaded(build)
    if type(build) ~= "table" then return false end
    local evidence = Nexus and Nexus.LoadoutEvidence
    if evidence and type(evidence.HasPublicOrdinaryConflict) == "function"
        and evidence.HasPublicOrdinaryConflict(build) then return false end
    if build.ordinaryComplete ~= nil then return build.ordinaryComplete == true end
    if not (evidence and type(evidence.OrdinaryCompleteness) == "function") then
        return false
    end
    local resolver = type(evidence.PublicOrdinaryCompleteness) == "function"
        and evidence.PublicOrdinaryCompleteness
        or evidence.OrdinaryCompleteness
    local ok, verdict = pcall(resolver, build)
    return ok and type(verdict) == "table" and verdict.complete == true
end

local function BuildPage(rows, baseSummary, filters)
    rows = type(rows) == "table" and rows or {}
    baseSummary = type(baseSummary) == "table" and baseSummary or {}
    local pageSize = 20
    local filteredTotal = #rows
    local pageCount = math.max(1, math.ceil(filteredTotal / pageSize))
    local page = math.min(math.max(1, tonumber(filters.page) or 1), pageCount)
    page = math.floor(page)
    local first = filteredTotal > 0 and ((page - 1) * pageSize + 1) or 0
    local last = filteredTotal > 0
        and math.min(filteredTotal, first + pageSize - 1) or 0
    local pageRows = {}
    if filteredTotal > 0 then
        for index = first, last do
            local row = rows[index]
            pageRows[#pageRows + 1] = row
        end
    end
    local summary = {}
    for key, value in pairs(baseSummary) do summary[key] = value end
    summary.filteredTotal = filteredTotal
    summary.filtered = #pageRows
    summary.resultCount = filteredTotal
    summary.displayedCount = #pageRows
    summary.searchActive = type(filters.search) == "string"
        and filters.search ~= "" or false
    summary.ready = math.max(0, tonumber(baseSummary.ready) or filteredTotal)
    summary.pending = math.max(0, tonumber(baseSummary.pending) or 0)
    summary.page, summary.pageSize, summary.pageCount = page, pageSize, pageCount
    summary.first, summary.last = first, last
    return pageRows, summary
end

local function NewBuildSummary(filters, catalog)
    local status = {}
    if catalog and type(catalog.Status) == "function" then
        local ok, value = pcall(catalog.Status)
        if ok and type(value) == "table" then status = value end
    end
    local catalogVersion = status.catalogVersion
    if catalogVersion == nil and catalog
        and type(catalog.CatalogVersion) == "function" then
        local ok, value = pcall(catalog.CatalogVersion)
        if ok then catalogVersion = value end
    end
    return {
        total=0,mine=0,savedLoadouts=0,uploaded=0,
        ready=0,pending=0,filtered=0,qualifying=0,
        bundledCount=math.max(0,tonumber(status.bundledCount) or 0),
        overlayCount=math.max(0,tonumber(status.overlayCount) or 0),
        availableCount=math.max(0,tonumber(status.availableCount) or 0),
        filterMatchedCount=0,qualifyingCount=0,resultCount=0,
        displayedCount=0,searchActive=type(filters.search) == "string"
            and filters.search ~= "" or false,
        catalogVersion=tostring(catalogVersion or "unversioned"),
    }
end

local function CommunityEligibility()
    local stats = counters.builds
    local dps = Nexus and Nexus.DpsCapture
    if not (dps and type(dps.GetCommunityEligibility) == "function") then
        return {}
    end
    stats.dpsReads = stats.dpsReads + 1
    local ok, result = pcall(dps.GetCommunityEligibility)
    if not ok then error("DPS eligibility read failed: " .. tostring(result)) end
    if type(result) ~= "table" then
        error("DPS eligibility reader returned invalid data")
    end
    return result
end

local function BuildProjection(filters)
    local catalog = Nexus and Nexus.BuildCatalog
    local summary = NewBuildSummary(filters, catalog)
    -- UnitClass is briefly unavailable during some login transitions. Publish
    -- an empty/loading projection and let the class-bearing cache key recover;
    -- never interpret that state as an all-class request.
    if filters.classFilter == "" then return {}, summary end

    local reader = catalog and (catalog.Summaries or catalog.All)
    if type(reader) ~= "function" then
        error("BuildCatalog projection reader unavailable")
    end
    counters.builds.catalogWalks = counters.builds.catalogWalks + 1
    local all = reader()
    if type(all) ~= "table" then error("BuildCatalog projection reader returned invalid data") end
    local eligibility = CommunityEligibility()
    local out = {}
    local presentation = Identity.NewPublicPresentation("author")
    for _, build in pairs(all) do
        if type(build) == "table" and IsLoaded(build) then
            local indexed = Identity.IndexPublicRecord(presentation, build)
            build = indexed and Identity.PresentPublicRecord(
                presentation, build) or nil
        end
        if type(build) == "table" and IsLoaded(build) then
            local savedKind = Identity.SavedMirrorKind(build)
            summary.total = summary.total + 1
            summary.ready = summary.ready + 1
            local own = IsOwnBuild(build, filters)
            if own then summary.mine = summary.mine + 1 end
            if savedKind == "saved" then
                summary.savedLoadouts = summary.savedLoadouts + 1
            elseif savedKind == "ordinary" and own then
                summary.uploaded = summary.uploaded + 1
            end
            local scopeMatch = filters.scope == "mine"
                and own
                or filters.scope ~= "mine" and savedKind == "ordinary"
            local searchMatch = filters.search == ""
                or tostring(build.title or ""):lower():find(filters.search, 1, true)
                or tostring(build.author or ""):lower():find(filters.search, 1, true)
                or tostring(build.description or ""):lower():find(filters.search, 1, true)
            local relation
            if scopeMatch and searchMatch and savedKind == "saved" then
                build, relation = PrepareSavedBuild(build, filters)
            end
            local classMatch = not filters.currentClassOnly
                or tostring(build.class or ""):upper() == filters.classFilter
            local matched = classMatch and scopeMatch and searchMatch
            local dpsSummary = matched
                and BuildDpsSummary(build, eligibility, relation) or nil
            local dummy = type(dpsSummary) == "table"
                and (tonumber(dpsSummary.dummy) or 0) or 0
            local lk = type(dpsSummary) == "table"
                and (tonumber(dpsSummary.lk) or 0) or 0
            local dpsCount = (dummy > 0 and 1 or 0) + (lk > 0 and 1 or 0)
            local eligible = dummy > 0 and lk > 0 and dpsCount == 2
            if matched then
                summary.filterMatchedCount = summary.filterMatchedCount + 1
                if eligible then summary.qualifying = summary.qualifying + 1 end
            end
            if matched and (eligible or not filters.qualifiedOnly) then
                -- BuildCatalog readers return fresh public snapshots. This
                -- projection owns the row and may attach derived DPS fields
                -- without another full-table copy.
                local copy = build
                copy._nexusDps = {
                    dummy=dummy,lk=lk,best=math.max(dummy,lk),
                    average=dpsCount > 0 and (dummy+lk)/dpsCount or 0,
                    count=dpsCount,
                }
                copy._nexusQualified = eligible
                copy._nexusQualification = eligible and "qualified"
                    or dummy <= 0 and lk <= 0 and "missing both"
                    or dummy <= 0 and "missing Dummy" or "missing Lich King"
                copy._nexusBestDps = copy._nexusDps.best
                out[#out + 1] = copy
            end
        elseif type(build) == "table" then
            summary.pending = summary.pending + 1
        end
    end
    counters.builds.sorts = counters.builds.sorts + 1
    table.sort(out, function(left, right)
        if filters.sortMode == "recent" then
            local lt = left.lastModified or left.postedAt or 0
            local rt = right.lastModified or right.postedAt or 0
            if lt ~= rt then return lt > rt end
        elseif filters.sortMode == "dps" then
            local ld = left._nexusDps and left._nexusDps.average or 0
            local rd = right._nexusDps and right._nexusDps.average or 0
            if ld ~= rd then return ld > rd end
        end
        local ln, rn = tostring(left.title or ""):lower(),
            tostring(right.title or ""):lower()
        if ln ~= rn then return ln < rn end
        return TypedIdentity(left.id) < TypedIdentity(right.id)
    end)
    summary.filtered = #out
    summary.qualifyingCount = summary.qualifying
    summary.resultCount = #out
    summary.availableCount = summary.total
    return out, summary
end

local function EvidenceIdentityKey(row)
    if type(row) ~= "table" then return "invalid" end
    local ownerKey = Identity.VerifiedOwnerKey(row)
    if ownerKey then return ownerKey end
    local player = type(row.player) == "string" and row.player:lower() or ""
    local realm = type(row.realm) == "string" and row.realm:lower() or ""
    local claimed = type(row.claimedOwnerKey) == "string"
        and row.claimedOwnerKey:lower() or ""
    local relay = type(row.relaySender) == "string"
        and row.relaySender:lower() or ""
    local owner = type(row.ownerKey) == "string"
        and row.ownerKey:lower() or ""
    if realm == "" and claimed == "" and relay == "" and owner == "" then
        return Identity.PlayerKey(row.player) or "invalid"
    end
    return "evidence:" .. TypedIdentity(player)
        .. ":" .. TypedIdentity(realm)
        .. ":" .. TypedIdentity(owner)
        .. ":" .. TypedIdentity(claimed)
        .. ":" .. TypedIdentity(relay)
end

local function RecordKey(row)
    return EvidenceIdentityKey(row)
        .. "|" .. TypedIdentity(row and (row.fingerprint or row.buildId))
end

local function CombinedRecordKey(row)
    if type(row) ~= "table" or type(row.fingerprint) ~= "string"
        or row.fingerprint == "" then return nil end
    local ownerKey = Identity.VerifiedOwnerKey(row)
    if not ownerKey then return nil end
    return ownerKey .. "|" .. TypedIdentity(row.fingerprint)
end

local function CommonTypedIdentity(left, right)
    return left ~= nil and right ~= nil and type(left) == type(right)
        and tostring(left) == tostring(right) and left or nil
end

local function EvidenceRecord(row)
    row = type(row) == "table" and row or {}
    return {
        player=row.player,fingerprint=row.fingerprint,
        buildId=row.buildId,resolvedBuildId=row.resolvedBuildId,
        ownerKey=row.ownerKey,ownerVerified=row.ownerVerified == true,
        claimedOwnerKey=row.claimedOwnerKey,relaySender=row.relaySender,
        buildIdentityMismatch=row.buildIdentityMismatch,
        recordIdentityMismatch=row.recordIdentityMismatch,
        resolvedIdentityMismatch=row.resolvedIdentityMismatch,
    }
end

local function CombinedLockedEvidence(drow, lrow, ordinary)
    local resolvedId = CommonTypedIdentity(
        drow and drow.resolvedBuildId, lrow and lrow.resolvedBuildId)
    local rawId = CommonTypedIdentity(
        drow and drow.buildId, lrow and lrow.buildId)
    return CandidateEvidence.ResolveLocked({
        ordinaryEchoes=ordinary,
        allowOrdinaryOverflow=true,
        buildId=resolvedId or rawId,
        fingerprint=(lrow and lrow.fingerprint)
            or (drow and drow.fingerprint),
        dummyRecord=drow,lkRecord=lrow,
    })
end

local function Board(category)
    local dps = Nexus and Nexus.DpsCapture
    if not (dps and type(dps.GetDpsBoard) == "function") then return {} end
    counters.leaderboard.boardReads = counters.leaderboard.boardReads + 1
    local ok, rows = pcall(dps.GetDpsBoard, category)
    if not ok then error("DPS board read failed: " .. tostring(rows)) end
    if type(rows) ~= "table" then error("DPS board returned invalid data") end
    return rows
end

local function CombinedRows()
    local dummy, lk = Board("dummy"), Board("lk")
    local out = {}
    for _, pair in ipairs(CandidateEvidence.RealDpsPairs(dummy, lk)) do
        local drow, lrow, average = pair.dummy, pair.lk, pair.average
            local ordinary = lrow.echoes or drow.echoes
            local locked = CombinedLockedEvidence(drow, lrow, ordinary)
            local dummyClass = NormalizeClass(drow.resolvedClass or drow.class)
            local lkClass = NormalizeClass(lrow.resolvedClass or lrow.class)
            local classConflict = dummyClass and lkClass
                and dummyClass ~= lkClass
            local resolvedBuildId = CommonTypedIdentity(
                drow.resolvedBuildId, lrow.resolvedBuildId)
            local resolvedFingerprintEpoch = CommonTypedIdentity(
                drow.resolvedFingerprintEpoch, lrow.resolvedFingerprintEpoch)
            local resolvedFingerprintRevision = CommonTypedIdentity(
                drow.resolvedFingerprintRevision,
                lrow.resolvedFingerprintRevision)
            local ownerKey = Identity.VerifiedOwnerKey(lrow)
            out[#out + 1] = {
                player=lrow.player,displayPlayer=lrow.displayPlayer,
                publicIdentityKey=lrow.publicIdentityKey,
                publicIdentityVerified=lrow.publicIdentityVerified,
                dps=average, average=average,
                dummyDps=drow.dps, lkDps=lrow.dps,
                dummyDuration=drow.duration, lkDuration=lrow.duration,
                level=math.max(tonumber(drow.level) or 0,
                    tonumber(lrow.level) or 0),
                ts=math.min(tonumber(drow.ts) or 0, tonumber(lrow.ts) or 0),
                category="combined",
                fingerprint=lrow.fingerprint or drow.fingerprint,
                class=not classConflict and (lkClass or dummyClass) or nil,
                classEvidenceMismatch=classConflict or nil,
                ownerKey=ownerKey,ownerVerified=true,
                dummyEvidence=EvidenceRecord(drow),
                lkEvidence=EvidenceRecord(lrow),
                echoes=ordinary,
                lockedEchoes=locked.status == "ok"
                    and locked.lockedEchoes or nil,
                lockedEvidenceStatus=locked.status,
                lockedEvidenceReason=locked.reason,
                lockedEvidenceSource=locked.source,
                lockedFingerprint=locked.fingerprint,
                buildId=lrow.buildId or drow.buildId,
                build=lrow.build or drow.build,
                protocolVersion=lrow.protocolVersion or drow.protocolVersion,
                resolvedBuildId=resolvedBuildId,
                resolvedFingerprintEpoch=resolvedFingerprintEpoch,
                resolvedFingerprintRevision=resolvedFingerprintRevision,
                resolvedIdentityMismatch=resolvedBuildId == nil
                    and (lrow.resolvedBuildId ~= nil
                        or drow.resolvedBuildId ~= nil)
                    or resolvedFingerprintEpoch == nil
                    and (lrow.resolvedFingerprintEpoch ~= nil
                        or drow.resolvedFingerprintEpoch ~= nil)
                    or resolvedFingerprintRevision == nil
                    and (lrow.resolvedFingerprintRevision ~= nil
                        or drow.resolvedFingerprintRevision ~= nil)
                    or nil,
                buildIdentityMismatch=lrow.buildIdentityMismatch
                    or drow.buildIdentityMismatch or nil,
                recordIdentityMismatch=lrow.recordIdentityMismatch
                    or drow.recordIdentityMismatch or nil,
                lockedEvidenceMismatch=locked.status == "conflict" or nil,
            }
    end
    counters.leaderboard.sorts = counters.leaderboard.sorts + 1
    table.sort(out, function(left, right)
        if left.average ~= right.average then return left.average > right.average end
        local leftPlayer, rightPlayer = tostring(left.player):lower(),
            tostring(right.player):lower()
        if leftPlayer ~= rightPlayer then return leftPlayer < rightPlayer end
        return tostring(left.publicIdentityKey or "")
            < tostring(right.publicIdentityKey or "")
    end)
    return out
end

local PrepareLeaderboardRow, LeaderboardRowMatches

local function LeaderboardProjection(filters)
    local source = filters.category == "combined"
        and CombinedRows() or Board(filters.category)
    local out = {}
    for _, row in ipairs(source) do
        local copied = PrepareLeaderboardRow(row, filters)
        if copied.ordinaryComplete == true
            and LeaderboardRowMatches(copied, filters) then
            out[#out + 1] = copied
        end
    end
    -- GetDpsBoard and CombinedRows already establish rank order. Count this as
    -- a projection order operation without re-sorting category boards.
    if filters.category ~= "combined" then
        counters.leaderboard.sorts = counters.leaderboard.sorts + 1
    end
    return out, {filtered=#out, category=filters.category}
end

local function BuildBefore(left, right, filters, countComparison)
    if countComparison then countComparison() end
    if filters.sortMode == "recent" then
        local lt = left.lastModified or left.postedAt or 0
        local rt = right.lastModified or right.postedAt or 0
        if lt ~= rt then return lt > rt end
    elseif filters.sortMode == "dps" then
        local ld = left._nexusDps and left._nexusDps.average or 0
        local rd = right._nexusDps and right._nexusDps.average or 0
        if ld ~= rd then return ld > rd end
    end
    local ln, rn = tostring(left.title or ""):lower(),
        tostring(right.title or ""):lower()
    if ln ~= rn then return ln < rn end
    return TypedIdentity(left.id) < TypedIdentity(right.id)
end

local function LeaderboardBefore(left, right, combined, countComparison)
    if countComparison then countComparison() end
    if combined then
        if left.average ~= right.average then return left.average > right.average end
        local leftPlayer, rightPlayer = tostring(left.player):lower(),
            tostring(right.player):lower()
        if leftPlayer ~= rightPlayer then return leftPlayer < rightPlayer end
        return tostring(left.publicIdentityKey or "")
            < tostring(right.publicIdentityKey or "")
    end
    if left.dps ~= right.dps then return left.dps > right.dps end
    if left.ts ~= right.ts then return left.ts < right.ts end
    local leftPlayer, rightPlayer = tostring(left.player):lower(),
        tostring(right.player):lower()
    if leftPlayer ~= rightPlayer then return leftPlayer < rightPlayer end
    return tostring(left.publicIdentityKey or "")
        < tostring(right.publicIdentityKey or "")
end

local function InsertOrdered(rows, row, before, limit, countComparison)
    local position = #rows + 1
    for index = 1, #rows do
        if before(row, rows[index], countComparison) then
            position = index
            break
        end
    end
    if limit and position > limit then return false end
    local last = limit and math.min(#rows + 1, limit) or (#rows + 1)
    for index = last, position + 1, -1 do rows[index] = rows[index - 1] end
    rows[position] = row
    if limit and #rows > limit then rows[#rows] = nil end
    return true
end

local function NewBuildJob(filters, key)
    local dps = Nexus and Nexus.DpsCapture
    local catalog = Nexus and Nexus.BuildCatalog
    if not (dps and type(dps.BeginCommunityEligibilityCursor) == "function"
        and type(dps.CommunityEligibilityCursorNext) == "function"
        and type(dps.CommunityEligibilityCursorResult) == "function"
        and catalog and type(catalog.BeginSummaryCursor) == "function"
        and type(catalog.SummaryCursorNext) == "function") then
        return nil, "resumable Community readers unavailable"
    end
    local cursor = dps.BeginCommunityEligibilityCursor()
    if type(cursor) ~= "table" then return nil, "DPS eligibility cursor unavailable" end
    local summary = NewBuildSummary(filters, catalog)
    -- The resumable cursor supplies exact baseline/overlay provenance without
    -- adding a second catalog walk. Reset the O(1) snapshot counts so the
    -- published projection proves what this cursor actually represented.
    summary.bundledCount, summary.overlayCount, summary.availableCount = 0, 0, 0
    return {
        key=key,filters=filters,state="eligibility",eligibilityCursor=cursor,
        rows={},summary=summary,
        presentation=Identity.NewPublicPresentation("author"),
    }
end

local function NewLeaderboardJob(filters, key)
    local dps = Nexus and Nexus.DpsCapture
    if not (dps and type(dps.BeginDpsBoardCursor) == "function"
        and type(dps.DpsBoardCursorNext) == "function"
        and type(dps.DpsBoardCursorResult) == "function") then
        return nil, "resumable Leaderboard readers unavailable"
    end
    local categories = filters.category == "combined"
        and {"dummy","lk"} or {filters.category}
    local cursor = dps.BeginDpsBoardCursor(categories[1])
    if type(cursor) ~= "table" then return nil, "DPS board cursor unavailable" end
    return {
        key=key,filters=filters,state="acquire",categories=categories,
        categoryIndex=1,boardCursor=cursor,boards={},rows={},rowByKey={},
        sourceIndex=1,
    }
end

local function CancelJob(kind)
    if jobs[kind] then
        jobs[kind] = nil
        workStats.cancellations = workStats.cancellations + 1
    end
end

local function Publish(kind, job, summary)
    caches[kind].key = job.key
    if kind == "builds" then
        caches[kind].allRows = job.rows
        caches[kind].rows = nil
    else
        caches[kind].rows = job.rows
    end
    caches[kind].summary = summary
    jobs[kind] = nil
    workStats.publications = workStats.publications + 1
    counters[kind].rebuilds = counters[kind].rebuilds + 1
    return true
end

local function PumpBuildJob(job, unit)
    local dps, catalog = Nexus.DpsCapture, Nexus.BuildCatalog
    local sourceRows, comparisons = 0, 0
    local function CountComparison()
        comparisons = comparisons + 1
        workStats.comparisons = workStats.comparisons + 1
    end
    if job.state == "eligibility" then
        while sourceRows < MAX_SOURCE_PER_PUMP do
            local done, err = dps.CommunityEligibilityCursorNext(
                job.eligibilityCursor)
            sourceRows = sourceRows + 1
            if err then return nil, err end
            if done then
                job.eligibility = dps.CommunityEligibilityCursorResult(
                    job.eligibilityCursor)
                if type(job.eligibility) ~= "table" then
                    return nil, "DPS eligibility cursor completed without data"
                end
                job.catalogCursor = catalog.BeginSummaryCursor()
                job.state = "catalog"
                break
            end
        end
    elseif job.state == "catalog" then
        while sourceRows < MAX_SOURCE_PER_PUMP do
            local build, done, err, fromBaseline, fromOverlay =
                catalog.SummaryCursorNext(job.catalogCursor)
            sourceRows = sourceRows + 1
            if err then return nil, err end
            if done then
                job.summary.filtered = #job.rows
                job.summary.qualifyingCount = job.summary.qualifying
                job.summary.resultCount = #job.rows
                if #job.rows <= 1 then
                    unit.sourceRows, unit.comparisons = sourceRows, comparisons
                    return Publish("builds", job, job.summary)
                end
                job.state, job.sortWidth, job.sortLeft = "sort", 1, 1
                job.sortSource, job.sortTarget, job.merge = job.rows, {}, nil
                break
            end
            if fromBaseline then
                job.summary.bundledCount = job.summary.bundledCount + 1
            end
            if fromOverlay then
                job.summary.overlayCount = job.summary.overlayCount + 1
            end
            if type(build) == "table" and IsLoaded(build) then
                local indexed = Identity.IndexPublicRecord(
                    job.presentation, build)
                build = indexed and Identity.PresentPublicRecord(
                    job.presentation, build) or nil
            end
            if type(build) == "table" and IsLoaded(build) then
                local filters, summary = job.filters, job.summary
                summary.total = summary.total + 1
                summary.availableCount = summary.availableCount + 1
                summary.ready = summary.ready + 1
                local savedKind = Identity.SavedMirrorKind(build)
                local own = IsOwnBuild(build, filters)
                if own then summary.mine = summary.mine + 1 end
                if savedKind == "saved" then
                    summary.savedLoadouts = summary.savedLoadouts + 1
                elseif savedKind == "ordinary" and own then
                    summary.uploaded = summary.uploaded + 1
                end
                local scopeMatch = filters.scope == "mine"
                    and own
                    or filters.scope ~= "mine" and savedKind == "ordinary"
                local searchMatch = filters.search == ""
                    or tostring(build.title or ""):lower():find(filters.search,1,true)
                    or tostring(build.author or ""):lower():find(filters.search,1,true)
                    or tostring(build.description or ""):lower():find(filters.search,1,true)
                local relation
                if scopeMatch and searchMatch and savedKind == "saved" then
                    build, relation = PrepareSavedBuild(build, filters, unit)
                end
                local classMatch = not filters.currentClassOnly
                    or tostring(build.class or ""):upper() == filters.classFilter
                local matched = classMatch and scopeMatch and searchMatch
                local dpsSummary = matched
                    and BuildDpsSummary(build, job.eligibility, relation) or nil
                local dummy = type(dpsSummary) == "table"
                    and (tonumber(dpsSummary.dummy) or 0) or 0
                local lk = type(dpsSummary) == "table"
                    and (tonumber(dpsSummary.lk) or 0) or 0
                local dpsCount = (dummy > 0 and 1 or 0) + (lk > 0 and 1 or 0)
                local eligible = dummy > 0 and lk > 0 and dpsCount == 2
                if matched then
                    summary.filterMatchedCount = summary.filterMatchedCount + 1
                    if eligible then summary.qualifying = summary.qualifying + 1 end
                end
                if matched and (eligible or not filters.qualifiedOnly) then
                    build._nexusDps = {
                        dummy=dummy,lk=lk,best=math.max(dummy,lk),
                        average=dpsCount > 0 and (dummy+lk)/dpsCount or 0,
                        count=dpsCount,
                    }
                    build._nexusQualified = eligible
                    build._nexusQualification = eligible and "qualified"
                        or dummy <= 0 and lk <= 0 and "missing both"
                        or dummy <= 0 and "missing Dummy" or "missing Lich King"
                    build._nexusBestDps = build._nexusDps.best
                    job.rows[#job.rows + 1] = build
                    workStats.copies = workStats.copies + 1
                    unit.copies = (unit.copies or 0) + 1
                end
            elseif type(build) == "table" then
                job.summary.pending = job.summary.pending + 1
            end
        end
    elseif job.state == "sort" then
        while unit.sortMoves < MAX_SORT_MOVES_PER_PUMP do
            if not job.merge then
                local total = #job.sortSource
                if job.sortLeft > total then
                    job.sortSource, job.sortTarget = job.sortTarget, job.sortSource
                    job.rows = job.sortSource
                    job.sortWidth = job.sortWidth * 2
                    job.sortLeft = 1
                    if job.sortWidth >= total then
                        unit.sourceRows, unit.comparisons = sourceRows, comparisons
                        counters.builds.sorts = counters.builds.sorts + 1
                        return Publish("builds", job, job.summary)
                    end
                else
                    local left = job.sortLeft
                    local middle = math.min(left + job.sortWidth - 1, total)
                    local right = math.min(left + 2 * job.sortWidth - 1, total)
                    job.merge = {
                        left=left,leftEnd=middle,right=middle+1,
                        rightEnd=right,out=left,
                    }
                end
            end
            local merge = job.merge
            if merge then
                local takeLeft
                if merge.left > merge.leftEnd then
                    takeLeft = false
                elseif merge.right > merge.rightEnd then
                    takeLeft = true
                else
                    takeLeft = BuildBefore(job.sortSource[merge.left],
                        job.sortSource[merge.right], job.filters, CountComparison)
                end
                local sourceIndex = takeLeft and merge.left or merge.right
                job.sortTarget[merge.out] = job.sortSource[sourceIndex]
                if takeLeft then merge.left = merge.left + 1
                else merge.right = merge.right + 1 end
                merge.out = merge.out + 1
                unit.sortMoves = unit.sortMoves + 1
                workStats.sortMoves = workStats.sortMoves + 1
                if merge.left > merge.leftEnd
                    and merge.right > merge.rightEnd then
                    job.sortLeft = merge.rightEnd + 1
                    job.merge = nil
                end
            end
        end
    end
    unit.sourceRows, unit.comparisons = sourceRows, comparisons
    return false
end

local function CombinedRow(drow, lrow)
    local average = ((tonumber(drow.dps) or 0)
        + (tonumber(lrow.dps) or 0)) / 2
    local ordinary = lrow.echoes or drow.echoes
    local locked = CombinedLockedEvidence(drow, lrow, ordinary)
    local dummyClass = NormalizeClass(drow.resolvedClass or drow.class)
    local lkClass = NormalizeClass(lrow.resolvedClass or lrow.class)
    local classConflict = dummyClass and lkClass and dummyClass ~= lkClass
    local ownerKey = Identity.VerifiedOwnerKey(lrow)
    return {
        player=lrow.player,displayPlayer=lrow.displayPlayer,
        publicIdentityKey=lrow.publicIdentityKey,
        publicIdentityVerified=lrow.publicIdentityVerified,
        dps=average,average=average,
        dummyDps=drow.dps,lkDps=lrow.dps,
        dummyDuration=drow.duration,lkDuration=lrow.duration,
        level=math.max(tonumber(drow.level) or 0,tonumber(lrow.level) or 0),
        ts=math.min(tonumber(drow.ts) or 0,tonumber(lrow.ts) or 0),
        category="combined",fingerprint=lrow.fingerprint or drow.fingerprint,
        class=not classConflict and (lkClass or dummyClass) or nil,
        classEvidenceMismatch=classConflict or nil,
        ownerKey=ownerKey,ownerVerified=true,
        dummyEvidence=EvidenceRecord(drow),
        lkEvidence=EvidenceRecord(lrow),
        echoes=ordinary,
        lockedEchoes=locked.status == "ok" and locked.lockedEchoes or nil,
        lockedEvidenceStatus=locked.status,
        lockedEvidenceReason=locked.reason,
        lockedEvidenceSource=locked.source,
        lockedFingerprint=locked.fingerprint,
        buildId=lrow.buildId or drow.buildId,build=lrow.build or drow.build,
        protocolVersion=lrow.protocolVersion or drow.protocolVersion,
        resolvedBuildId=lrow.resolvedBuildId==drow.resolvedBuildId
            and lrow.resolvedBuildId or nil,
        resolvedFingerprintEpoch=
            lrow.resolvedFingerprintEpoch==drow.resolvedFingerprintEpoch
            and lrow.resolvedFingerprintEpoch or nil,
        resolvedFingerprintRevision=
            lrow.resolvedFingerprintRevision==drow.resolvedFingerprintRevision
            and lrow.resolvedFingerprintRevision or nil,
        resolvedIdentityMismatch=lrow.resolvedBuildId~=drow.resolvedBuildId
            and (lrow.resolvedBuildId~=nil or drow.resolvedBuildId~=nil)
            or lrow.resolvedFingerprintEpoch~=drow.resolvedFingerprintEpoch
            or lrow.resolvedFingerprintRevision~=
                drow.resolvedFingerprintRevision or nil,
        buildIdentityMismatch=lrow.buildIdentityMismatch
            or drow.buildIdentityMismatch or nil,
        recordIdentityMismatch=lrow.recordIdentityMismatch
            or drow.recordIdentityMismatch or nil,
        lockedEvidenceMismatch=locked.status == "conflict" or nil,
    }
end

LeaderboardRowMatches = function(row, filters)
    local build = type(row.build) == "table" and row.build or {}
    local class = NormalizeClass(row.resolvedClass)
    return (filters.classFilter == "ALL" or class == filters.classFilter)
        and (filters.search == ""
            or tostring(row.player or ""):lower():find(filters.search,1,true)
            or tostring(build.title or ""):lower():find(filters.search,1,true)
            or tostring(build.author or ""):lower():find(filters.search,1,true))
end

-- Summary-only DPS rows can carry a bounded exact catalog identity while
-- retaining their complete inline ordinary evidence. Hydrate only the class
-- scalar from that represented identity: the summary must never become the row's
-- display build or replace either historical identity field.
local function RecoveredInlineClass(row, buildId, enforceRevision,
    verifiedFingerprint)
    if type(row) ~= "table" or row.recordIdentityMismatch
        or row.resolvedIdentityMismatch or row.classEvidenceMismatch then
        return nil
    end
    if buildId == nil or (type(buildId) ~= "string" and type(buildId) ~= "number")
        then return nil end
    local catalog = Nexus and Nexus.BuildCatalog
    if not (catalog and type(catalog.GetSummary) == "function") then
        return nil
    end
    local ok, summary = pcall(catalog.GetSummary, buildId)
    if not ok or type(summary) ~= "table" then return nil end
    if type(summary.id) ~= type(buildId) or summary.id ~= buildId then return nil end

    local comparisonFingerprint = verifiedFingerprint
        or (type(row.fingerprint) == "string" and row.fingerprint or nil)
    if type(summary.fingerprint) == "string"
        and type(comparisonFingerprint) == "string"
        and comparisonFingerprint ~= summary.fingerprint then
        return nil
    end

    if enforceRevision and type(summary.fingerprint) == "string"
        and type(catalog.ExactFingerprintRevision) == "function"
        and row.resolvedFingerprintEpoch ~= nil
        and row.resolvedFingerprintRevision ~= nil then
        local revisionOk, epoch, revision = pcall(
            catalog.ExactFingerprintRevision, summary.fingerprint)
        if not revisionOk
            or row.resolvedFingerprintEpoch ~= epoch
            or row.resolvedFingerprintRevision ~= revision then
            return nil
        end
    end
    return NormalizeClass(summary.class)
end

local function ResolveLeaderboardOrdinary(row)
    local evidence = Nexus and Nexus.LoadoutEvidence
    if not (evidence and type(evidence.OrdinaryCompleteness) == "function") then
        return nil, nil, "ordinary evidence owner unavailable"
    end
    local resolver = type(evidence.PublicOrdinaryCompleteness) == "function"
        and evidence.PublicOrdinaryCompleteness
        or evidence.OrdinaryCompleteness
    local ok, verdict = pcall(resolver, row)
    if ok and type(verdict) == "table" and verdict.complete == true then
        local completeBuildId = type(row.resolvedBuildId) == "string"
            and row.resolvedBuildId
            or (type(row.resolvedBuildId) == "number" and row.resolvedBuildId)
            or row.buildId
        local recoveredInlineClass = RecoveredInlineClass(row, completeBuildId, true)
        return verdict, nil, "record", nil, recoveredInlineClass
    end
    if type(verdict) == "table" and verdict.reason == "identity-conflict" then
        return nil, nil, verdict.reason
    end

    local catalog = Nexus and Nexus.BuildCatalog
    if not (catalog and type(catalog.ResolveFingerprintIdentity) == "function"
        and type(catalog.Get) == "function") then
        return nil, nil, type(verdict) == "table" and verdict.reason
            or "ordinary evidence unavailable"
    end
    local resolvedId, resolvedSource, resolvedFingerprint =
        catalog.ResolveFingerprintIdentity(
            row and row.buildId, row and row.fingerprint, {
                allowClassOnly=true,legacyRecord=row,
            })
    if resolvedId == nil then
        return nil, nil, type(verdict) == "table" and verdict.reason
            or "ordinary evidence unavailable"
    end
    local build = catalog.Get(resolvedId)
    local recovered = nil
    if type(build) == "table" then
        local ordinaryOk, ordinaryVerdict = pcall(evidence.OrdinaryCompleteness, build)
        if ordinaryOk and type(ordinaryVerdict) == "table"
            and ordinaryVerdict.complete == true then
            recovered = ordinaryVerdict
        end
    end
    local recoveredInlineClass = nil
    if not row.classEvidenceMismatch and not row.recordIdentityMismatch
        and not row.resolvedIdentityMismatch then
        local enforceRevision = row.resolvedFingerprintEpoch ~= nil
            and row.resolvedFingerprintRevision ~= nil
        recoveredInlineClass = RecoveredInlineClass(
            row, resolvedId, enforceRevision, resolvedFingerprint)
    end
    if recovered ~= nil then
        return recovered, resolvedId, resolvedSource or "catalog", build,
            recoveredInlineClass
    end
    return nil, resolvedId, resolvedSource or "catalog identity unavailable",
        nil, recoveredInlineClass
end

local function IsCurrentPlayerRow(row, context)
    if type(row) ~= "table" then return false end
    local owner = type(context) == "table" and context.ownerKey or ""
    return owner ~= "" and Identity.VerifiedOwnerKey(row) == owner
end

local function ResolveLeaderboardClass(row, resolvedBuild, context,
    recoveredInlineClass)
    if type(row) ~= "table" then return nil, "unavailable", "invalid row" end
    if row.classEvidenceMismatch then
        return nil, "unavailable", "record categories disagree"
    end
    local rowClass = NormalizeClass(row.class)
    if rowClass then return rowClass, "record" end
    if recoveredInlineClass then
        return recoveredInlineClass, "exact-build"
    end

    if not row.buildIdentityMismatch and not row.recordIdentityMismatch
        and not row.resolvedIdentityMismatch then
        local build = type(resolvedBuild) == "table" and resolvedBuild
            or type(row.build) == "table" and row.build or nil
        local rowFingerprint = type(row.fingerprint) == "string"
            and row.fingerprint or nil
        local buildFingerprint = build and type(build.fingerprint) == "string"
            and build.fingerprint or nil
        local buildClass = buildFingerprint == rowFingerprint
            and NormalizeClass(build.class) or nil
        if buildClass then return buildClass, "exact-build" end
    end

    -- A legacy summary can outlive its exact build reference. Recover only a
    -- display/filter class when verified records for the exact realm-qualified
    -- owner agree. Short author names and unverified relay claims never grant
    -- class authority.
    local catalog = Nexus and Nexus.BuildCatalog
    if catalog and type(catalog.ResolveOwnerClass) == "function" then
        local ok, recovered, source = pcall(
            catalog.ResolveOwnerClass, row)
        recovered = ok and NormalizeClass(recovered) or nil
        if recovered then return recovered, source or "owner-consensus" end
        if ok and source == "owner class evidence conflicts" then
            return nil, "unavailable", source
        end
    end

    if IsCurrentPlayerRow(row, context) then
        local current = NormalizeClass(context and context.currentClass)
        if current then return current, "current-player" end
    end
    return nil, "unavailable", "class unavailable"
end

local function CountLeaderboardClass(source, reason)
    if source == "record" then
        workStats.classFromRecord = workStats.classFromRecord + 1
    elseif source == "exact-build" then
        workStats.classFromBuild = workStats.classFromBuild + 1
    elseif source == "current-player" then
        workStats.classFromCurrentPlayer = workStats.classFromCurrentPlayer + 1
    elseif source == "owner-consensus" then
        workStats.classFromOwner = workStats.classFromOwner + 1
    else
        workStats.classUnavailable = workStats.classUnavailable + 1
        if reason == "record categories disagree"
            or reason == "owner class evidence conflicts" then
            workStats.classConflicts = workStats.classConflicts + 1
        end
    end
end

local function AttachLeaderboardLocked(row, ordinary, resolvedId)
    if row.category == "combined" and row.lockedEvidenceStatus then return end
    local options = {
        ordinaryEchoes=ordinary and ordinary.echoes or row.echoes,
        ordinaryComplete=ordinary ~= nil,
        allowOrdinaryOverflow=true,
        buildId=resolvedId or row.resolvedBuildId or row.buildId,
        fingerprint=ordinary and ordinary.fingerprint or row.fingerprint,
        inlineLockedEchoes=row.lockedEchoes,
        inlineLockedFingerprint=row.lockedFingerprint,
    }
    if row.category == "dummy" then
        options.dummyRecord = row
    elseif row.category == "lk" then
        options.lkRecord = row
    end
    local locked = CandidateEvidence.ResolveLocked(options)
    row.lockedEvidenceStatus = locked.status
    row.lockedEvidenceReason = locked.reason
    row.lockedEvidenceSource = locked.source
    row.lockedFingerprint = locked.fingerprint
    row.lockedEvidenceMismatch = locked.status == "conflict" or nil
    row.lockedEchoes = locked.status == "ok" and locked.lockedEchoes or nil
end

PrepareLeaderboardRow = function(row, context)
    local copied = DeepCopy(row)
    local ordinary, resolvedId, ordinarySource, resolvedBuild,
        recoveredInlineClass =
        ResolveLeaderboardOrdinary(copied)
    copied.ordinaryComplete = ordinary ~= nil
    copied.ordinaryCompletenessReason = ordinary and "complete"
        or ordinarySource or "ordinary evidence is still syncing"
    if ordinary then
        copied.echoes = ordinary.echoes
        copied.fingerprint = ordinary.fingerprint
    else
        copied.echoes = nil
    end
    if resolvedId ~= nil then
        copied.resolvedBuildId = resolvedId
        copied.build = resolvedBuild
        if type(Nexus.BuildCatalog.ExactFingerprintRevision) == "function" then
            copied.resolvedFingerprintEpoch,
                copied.resolvedFingerprintRevision =
                Nexus.BuildCatalog.ExactFingerprintRevision(copied.fingerprint)
        end
    end
    copied.ordinaryEvidenceSource = ordinarySource
    AttachLeaderboardLocked(copied, ordinary, resolvedId)
    copied.resolvedClass, copied.classSource, copied.classUnavailableReason =
        ResolveLeaderboardClass(copied, resolvedBuild, context,
            recoveredInlineClass)
    copied.classUnavailable = copied.resolvedClass == nil
    CountLeaderboardClass(copied.classSource, copied.classUnavailableReason)
    return copied
end

local function PumpLeaderboardJob(job, unit)
    local dps = Nexus.DpsCapture
    local sourceRows, comparisons, sortMoves = 0, 0, 0
    local function CountComparison()
        comparisons = comparisons + 1
        workStats.comparisons = workStats.comparisons + 1
    end
    if job.state == "acquire" then
        while sourceRows < MAX_SOURCE_PER_PUMP do
            local done, err = dps.DpsBoardCursorNext(job.boardCursor)
            sourceRows = sourceRows + 1
            if err then return nil, err end
            if done then
                local category = job.categories[job.categoryIndex]
                job.boards[category] = dps.DpsBoardCursorResult(job.boardCursor)
                job.categoryIndex = job.categoryIndex + 1
                local nextCategory = job.categories[job.categoryIndex]
                if nextCategory then
                    job.boardCursor = dps.BeginDpsBoardCursor(nextCategory)
                elseif job.filters.category == "combined" then
                    job.state, job.sourceIndex = "index", 1
                    job.dummyByKey = {}
                else
                    job.state, job.sourceIndex = "rank", 1
                    job.source = job.boards[job.filters.category] or {}
                end
                break
            end
        end
    elseif job.state == "index" then
        local dummy = job.boards.dummy or {}
        while sourceRows < MAX_SOURCE_PER_PUMP and job.sourceIndex <= #dummy do
            local row = dummy[job.sourceIndex]
            job.sourceIndex = job.sourceIndex + 1
            sourceRows = sourceRows + 1
            local key = CandidateEvidence.DpsPairIdentity(row)
            local current = key and job.dummyByKey[key]
            if key and (not current
                or CandidateEvidence.DpsRowBefore(row, current)) then
                job.dummyByKey[key] = row
            end
        end
        if job.sourceIndex > #dummy then
            job.state, job.sourceIndex = "rank", 1
            job.source = job.boards.lk or {}
        end
    elseif job.state == "rank" then
        local combined = job.filters.category == "combined"
        while sourceRows < MAX_SOURCE_PER_PUMP
            and job.sourceIndex <= #job.source do
            local raw = job.source[job.sourceIndex]
            job.sourceIndex = job.sourceIndex + 1
            sourceRows = sourceRows + 1
            local row = raw
            if combined then
                local key = CandidateEvidence.DpsPairIdentity(raw)
                local drow = key and job.dummyByKey[key]
                if drow then
                    row = CombinedRow(drow, raw)
                    workStats.joins = workStats.joins + 1
                    unit.joins = (unit.joins or 0) + 1
                else row = nil end
            end
            if row then
                local copied = PrepareLeaderboardRow(row, job.filters)
                workStats.copies = workStats.copies + 1
                unit.copies = (unit.copies or 0) + 1
                if copied.ordinaryComplete == true
                    and LeaderboardRowMatches(copied, job.filters) then
                    job.rows[#job.rows + 1] = copied
                    job.rowByKey[RecordKey(copied)] = copied
                end
            end
        end
        if job.sourceIndex > #job.source then
            if #job.rows <= 1 then
                unit.sourceRows, unit.comparisons, unit.sortMoves =
                    sourceRows, comparisons, sortMoves
                return Publish("leaderboard", job,
                    {filtered=#job.rows,category=job.filters.category,
                        rowByKey=job.rowByKey})
            end
            job.state, job.sortWidth, job.sortLeft = "sort", 1, 1
            job.sortSource, job.sortTarget, job.merge = job.rows, {}, nil
        end
    elseif job.state == "sort" then
        local combined = job.filters.category == "combined"
        while sortMoves < MAX_SORT_MOVES_PER_PUMP do
            if not job.merge then
                local total = #job.sortSource
                if job.sortLeft > total then
                    job.sortSource, job.sortTarget =
                        job.sortTarget, job.sortSource
                    job.rows = job.sortSource
                    job.sortWidth = job.sortWidth * 2
                    job.sortLeft = 1
                    if job.sortWidth >= total then
                        unit.sourceRows, unit.comparisons, unit.sortMoves =
                            sourceRows, comparisons, sortMoves
                        return Publish("leaderboard", job,
                            {filtered=#job.rows,
                                category=job.filters.category,
                                rowByKey=job.rowByKey})
                    end
                else
                    local left = job.sortLeft
                    local middle = math.min(left + job.sortWidth - 1, total)
                    local right = math.min(left + 2 * job.sortWidth - 1, total)
                    job.merge = {
                        left=left,leftEnd=middle,right=middle+1,
                        rightEnd=right,out=left,
                    }
                end
            end
            local merge = job.merge
            if merge then
                local takeLeft
                if merge.left > merge.leftEnd then
                    takeLeft = false
                elseif merge.right > merge.rightEnd then
                    takeLeft = true
                else
                    takeLeft = LeaderboardBefore(
                        job.sortSource[merge.left],
                        job.sortSource[merge.right], combined,
                        CountComparison)
                end
                local sourceIndex = takeLeft and merge.left or merge.right
                job.sortTarget[merge.out] = job.sortSource[sourceIndex]
                if takeLeft then merge.left = merge.left + 1
                else merge.right = merge.right + 1 end
                merge.out = merge.out + 1
                sortMoves = sortMoves + 1
                workStats.sortMoves = workStats.sortMoves + 1
                if merge.left > merge.leftEnd
                    and merge.right > merge.rightEnd then
                    job.sortLeft = merge.rightEnd + 1
                    job.merge = nil
                end
            end
        end
    end
    unit.sourceRows, unit.comparisons, unit.sortMoves =
        sourceRows, comparisons, sortMoves
    return false
end

local function Pump(kind)
    local job = jobs[kind]
    if not job then return false end
    local currentKey = kind == "builds"
        and BuildKey(job.filters) or LeaderboardKey(job.filters)
    if currentKey ~= job.key then CancelJob(kind); return false end
    local unit = {
        sourceRows=0,comparisons=0,sortMoves=0,joins=0,copies=0,
    }
    local published, err
    if kind == "builds" then
        published, err = PumpBuildJob(job, unit)
    else
        published, err = PumpLeaderboardJob(job, unit)
    end
    workStats.acquisitions = workStats.acquisitions + 1
    workStats.sourceRows = workStats.sourceRows + unit.sourceRows
    workStats.maxSourceRowsPerPump = math.max(
        workStats.maxSourceRowsPerPump, unit.sourceRows)
    workStats.maxComparisonsPerPump = math.max(
        workStats.maxComparisonsPerPump, unit.comparisons)
    workStats.maxSortMovesPerPump = math.max(
        workStats.maxSortMovesPerPump, unit.sortMoves)
    workStats.maxJoinsPerPump = math.max(
        workStats.maxJoinsPerPump, unit.joins)
    workStats.maxCopiesPerPump = math.max(
        workStats.maxCopiesPerPump, unit.copies)
    if kind == "builds" then
        workStats.communityPumps = workStats.communityPumps + 1
    else
        workStats.leaderboardPumps = workStats.leaderboardPumps + 1
    end
    if err then
        counters[kind].failures = counters[kind].failures + 1
        CancelJob(kind)
        return false, err
    end
    return published == true
end

function Projections.BindSavedRelationResolver(resolver)
    if resolver ~= nil and type(resolver) ~= "function" then
        return false, "Saved relation resolver must be a function or nil"
    end
    if savedRelationResolver == resolver then return false end
    savedRelationResolver = resolver
    savedRelationGeneration = savedRelationGeneration + 1
    CancelJob("builds")
    caches.builds = {}
    return true
end

function Projections.Builds(filters)
    local normalized = NormalizeBuildFilters(filters)
    local cache, stats = caches.builds, counters.builds
    local initialKey = BuildKey(normalized)
    if cache.key == initialKey and type(cache.allRows) == "table" then
        stats.hits = stats.hits + 1
        stats.defensiveCopies = stats.defensiveCopies + 1
        local pageRows, summary = BuildPage(
            cache.allRows, cache.summary, normalized)
        return DeepCopy(pageRows), DeepCopy(summary)
    end
    for _ = 1, 2 do
        local beforeKey = BuildKey(normalized)
        stats.rebuilds = stats.rebuilds + 1
        local ok, rows, summary = pcall(BuildProjection, normalized)
        local afterKey = BuildKey(normalized)
        if not ok or type(rows) ~= "table" then
            stats.failures = stats.failures + 1
            return nil, nil, tostring(rows or "projection failed")
        end
        if beforeKey == afterKey then
            cache.key, cache.allRows, cache.rows = afterKey, rows, nil
            cache.summary = summary
            stats.defensiveCopies = stats.defensiveCopies + 1
            local pageRows, pageSummary = BuildPage(rows, summary, normalized)
            return DeepCopy(pageRows), DeepCopy(pageSummary)
        end
    end
    stats.failures = stats.failures + 1
    return nil, nil, "represented data changed during projection"
end

function Projections.RequestBuilds(filters)
    local normalized = NormalizeBuildFilters(filters)
    local key = BuildKey(normalized)
    if caches.builds.key == key and type(caches.builds.allRows) == "table" then
        -- Async UI projections are immutable after atomic publication. Return
        -- only the requested 20-row window; changing pages neither reacquires
        -- the catalog nor changes the represented-data cache key.
        return BuildPage(caches.builds.allRows,
            caches.builds.summary, normalized)
    end
    if normalized.classFilter == "" then
        CancelJob("builds")
        caches.builds = {key=key,allRows={},summary=
            NewBuildSummary(normalized, Nexus and Nexus.BuildCatalog)}
        workStats.publications = workStats.publications + 1
        return BuildPage(caches.builds.allRows,
            caches.builds.summary, normalized)
    end
    if not jobs.builds or jobs.builds.key ~= key then
        CancelJob("builds")
        local job, err = NewBuildJob(normalized, key)
        if not job then return Projections.Builds(filters) end
        jobs.builds = job
    end
    return nil, nil, "pending"
end

function Projections.PumpBuilds()
    return Pump("builds")
end

-- Cheap dirty probe for view timers. It intentionally returns no cached rows,
-- so an unchanged safety tick cannot copy the full projection merely to learn
-- that the already rendered data is current.
function Projections.BuildsCurrent(filters)
    local normalized = NormalizeBuildFilters(filters)
    return type(caches.builds.allRows) == "table"
        and caches.builds.key == BuildKey(normalized)
end

-- Explain one selected catalog row on demand. This deliberately keeps no
-- per-row reason map or payload cache: Peer Debug and troubleshooting pay the
-- narrow lookup cost only for the selected build.
function Projections.ExplainBuild(id, filters)
    local normalized = NormalizeBuildFilters(filters)
    local catalog = Nexus and Nexus.BuildCatalog
    local build
    if catalog and type(catalog.GetSummary) == "function" then
        local ok, result = pcall(catalog.GetSummary, id)
        if ok and type(result) == "table" then build = result end
    end
    if not build and catalog and type(catalog.GetSummary) ~= "function"
        and type(catalog.Summaries) == "function" then
        -- Compatibility for projection-only test/older providers. The shipped
        -- catalog always takes the O(1) GetSummary path above.
        local ok, rows = pcall(catalog.Summaries)
        if ok and type(rows) == "table" then build = rows[id] end
    end
    if type(build) ~= "table" then return "build unavailable" end

    local savedKind = Identity.SavedMirrorKind(build)
    local own = IsOwnBuild(build, normalized)
    local scopeMatch = normalized.scope == "mine"
        and own
        or normalized.scope ~= "mine" and savedKind == "ordinary"
    if not scopeMatch then
        return normalized.scope == "mine"
            and "scope filter: not mine" or "scope filter: saved loadout"
    end
    local relation
    if savedKind == "saved" then
        build, relation = PrepareSavedBuild(build, normalized)
    end
    if normalized.currentClassOnly then
        if normalized.classFilter == "" then
            return "projection pending: current class unavailable"
        end
        local buildClass = tostring(build.class or ""):upper()
        if buildClass == "" or buildClass == "UNKNOWN" then
            return "unknown class"
        end
        if buildClass ~= normalized.classFilter then
            return "current class filter"
        end
    end
    if normalized.qualifiedOnly then
        local dpsOwner = Nexus and Nexus.DpsCapture
        local ok, dps = false, nil
        local lookupId = relation and relation.buildId or build.id
        local lookupFingerprint = relation and relation.fingerprint
            or build.fingerprint
        local lookupHash = relation and relation.fingerprintHash
            or build.fingerprintHash
        if savedKind == "invalid"
            or savedKind == "saved" and not relation then
            return "qualification unavailable"
        elseif dpsOwner
            and type(dpsOwner.GetCachedCommunityQualification) == "function" then
            ok, dps = pcall(dpsOwner.GetCachedCommunityQualification,
                lookupId, lookupFingerprint, lookupHash)
        elseif dpsOwner and type(dpsOwner.GetCommunityEligibility) == "function" then
            -- Compatibility for injected/older projection providers. The
            -- shipped DPS owner always supplies the narrow current-cache API,
            -- so Peer Debug never enters this full-snapshot fallback.
            local eligibility
            ok, eligibility = pcall(CommunityEligibility)
            dps = ok and type(eligibility) == "table"
                and (eligibility[lookupFingerprint] or {}) or nil
        end
        if not ok or type(dps) ~= "table" then
            return "qualification unavailable"
        end
        local dummy = type(dps) == "table" and (tonumber(dps.dummy) or 0) or 0
        local lk = type(dps) == "table" and (tonumber(dps.lk) or 0) or 0
        if dummy <= 0 and lk <= 0 then
            return "missing Dummy and Lich King records"
        elseif dummy <= 0 then
            return "missing Dummy record"
        elseif lk <= 0 then
            return "missing Lich King record"
        end
    end
    if normalized.search ~= ""
        and not tostring(build.title or ""):lower():find(normalized.search,1,true)
        and not tostring(build.author or ""):lower():find(normalized.search,1,true)
        and not tostring(build.description or ""):lower():find(normalized.search,1,true) then
        return "search filter"
    end

    if caches.builds.key == BuildKey(normalized)
        and type(caches.builds.allRows) == "table" then
        local pageRows = BuildPage(caches.builds.allRows,
            caches.builds.summary, normalized)
        for _, row in ipairs(pageRows) do
            if TypedIdentity(row.id) == TypedIdentity(id) then
                return "included on current page"
            end
        end
        return "outside current page"
    end
    return "projection pending"
end

function Projections.Leaderboard(category, filters)
    local normalized = NormalizeLeaderboardFilters(category, filters)
    return Cached("leaderboard", function() return LeaderboardKey(normalized) end,
        function() return LeaderboardProjection(normalized) end)
end

function Projections.RequestLeaderboard(category, filters)
    local normalized = NormalizeLeaderboardFilters(category, filters)
    local key = LeaderboardKey(normalized)
    if caches.leaderboard.key == key
        and type(caches.leaderboard.rows) == "table" then
        return caches.leaderboard.rows, caches.leaderboard.summary
    end
    if not jobs.leaderboard or jobs.leaderboard.key ~= key then
        CancelJob("leaderboard")
        local job, err = NewLeaderboardJob(normalized, key)
        if not job then return Projections.Leaderboard(category, filters) end
        jobs.leaderboard = job
    end
    return nil, nil, "pending"
end

function Projections.PumpLeaderboard()
    return Pump("leaderboard")
end

function Projections.RecordBind()
    workStats.binds = workStats.binds + 1
end

function Projections.WorkStats()
    return DeepCopy(workStats)
end

-- Cheap dirty probe for Leaderboard publication. As with BuildsCurrent, this
-- never returns or copies cached rows merely to establish currentness.
function Projections.LeaderboardCurrent(category, filters)
    local normalized = NormalizeLeaderboardFilters(category, filters)
    return type(caches.leaderboard.rows) == "table"
        and caches.leaderboard.key == LeaderboardKey(normalized)
end

function Projections.Reset()
    caches = {builds={}, leaderboard={}}
    jobs = {builds=nil,leaderboard=nil}
    workStats = {
        acquisitions=0,sourceRows=0,joins=0,comparisons=0,copies=0,
        sortMoves=0,publications=0,cancellations=0,binds=0,
        communityPumps=0,leaderboardPumps=0,
        maxSourceRowsPerPump=0,maxComparisonsPerPump=0,
        maxSortMovesPerPump=0,maxJoinsPerPump=0,maxCopiesPerPump=0,
        classFromRecord=0,classFromBuild=0,classFromCurrentPlayer=0,
        classFromOwner=0,
        classUnavailable=0,classConflicts=0,
    }
end

function Projections.Stats()
    return DeepCopy(counters)
end

function Projections.CacheKeys()
    return {builds=caches.builds.key, leaderboard=caches.leaderboard.key}
end
