-- Nexus: revision/filter-cached defensive data-browser projections.
--
-- This module owns no frames, timers, SavedVariables, transport, or gameplay
-- actions. It reads only the public BuildCatalog/DpsCapture surfaces and keeps
-- bounded last-good projections for the build and leaderboard views.

Nexus = Nexus or {}
local Projections = {}
Nexus.ViewProjections = Projections

local caches = {builds={}, leaderboard={}, leaderboardSources={}}
local MAX_REQUESTED_BUILD_ROWS = 100
local counters = {
    builds={hits=0,rebuilds=0,failures=0,catalogWalks=0,dpsReads=0,
        sorts=0,defensiveCopies=0},
    leaderboard={hits=0,rebuilds=0,failures=0,boardReads=0,sorts=0,
        defensiveCopies=0,sourceHits=0,sourceRebuilds=0},
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
    realm = tostring(realm or "unknown"):lower():gsub("%s+", "")
    local player = tostring(name):lower():gsub("^%s+", ""):gsub("%s+$", "")
    return player, player .. "@" .. realm
end

local function NormalizeBuildFilters(filters)
    filters = type(filters) == "table" and filters or {}
    local player, ownerKey = CurrentIdentity()
    local search = tostring(filters.search or ""):lower()
        :gsub("^%s+", ""):gsub("%s+$", "")
    local classFilter = type(filters.classFilter) == "string"
        and filters.classFilter:upper() or ""
    local scope = filters.scope == "mine" and "mine" or "all"
    local sortMode = filters.sortMode
    if sortMode ~= "recent" and sortMode ~= "title" then sortMode = "dps" end
    local resultLimit = math.floor(tonumber(filters.resultLimit) or 0)
    if resultLimit < 1 then resultLimit = 0 end
    if resultLimit > MAX_REQUESTED_BUILD_ROWS then
        resultLimit = MAX_REQUESTED_BUILD_ROWS
    end
    return {
        search=search, classFilter=classFilter, scope=scope,
        sortMode=sortMode, player=player, ownerKey=ownerKey,
        resultLimit=resultLimit, skipDps=filters.skipDps == true,
    }
end

local function NormalizeLeaderboardFilters(category, filters)
    filters = type(filters) == "table" and filters or {}
    category = category == "dummy" and "dummy"
        or category == "combined" and "combined" or "lk"
    local classFilter = type(filters.classFilter) == "string"
        and filters.classFilter:upper() or "ALL"
    if classFilter == "" then classFilter = "ALL" end
    return {
        category=category,
        search=tostring(filters.search or ""):lower(),
        classFilter=classFilter,
    }
end

local function BuildKey(filters)
    local revisions = Nexus and Nexus.Revisions or {}
    return CacheKey({
        Revision(revisions.BUILD_LIBRARY_CHANGED),
        Revision(revisions.DPS_CHANGED),
        filters.scope, filters.classFilter, filters.search, filters.sortMode,
        filters.player, filters.ownerKey, filters.resultLimit, filters.skipDps,
    })
end

local function LeaderboardKey(filters)
    local revisions = Nexus and Nexus.Revisions or {}
    return CacheKey({
        Revision(revisions.BUILD_LIBRARY_CHANGED),
        Revision(revisions.DPS_CHANGED),
        filters.category, filters.classFilter, filters.search,
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
    if type(build) ~= "table" then return false end
    local store = Nexus and Nexus.Store
    if store and type(store.IsAccountBuild) == "function" then
        local ok, value = pcall(store.IsAccountBuild, build)
        if ok then return value == true end
    end
    if build.isMine == true or build.importedSavedBuild == true then return true end
    if build.ownerKey then
        return filters.ownerKey ~= ""
            and tostring(build.ownerKey):lower() == filters.ownerKey
    end
    return false
end

local function IsLoaded(build)
    if type(build) ~= "table" then return false end
    if build.loadoutAvailable ~= nil then return build.loadoutAvailable == true end
    if tonumber(build.echoCount) then return tonumber(build.echoCount) > 0 end
    return type(build.echoes) == "table" and #build.echoes > 0
end

local function BuildDpsSummary(build)
    local stats = counters.builds
    local dps = Nexus and Nexus.DpsCapture
    local summary = {dummy=0,lk=0,best=0,average=0,count=0}
    if not (dps and type(build) == "table") then return summary end
    local recordId = build.recordBuildId or build.publishedBuildId or build.id
    for _, category in ipairs({"dummy", "lk"}) do
        local rows
        if recordId and type(dps.GetLeaderboardForIdentity) == "function" then
            stats.dpsReads = stats.dpsReads + 1
            local ok, result = pcall(dps.GetLeaderboardForIdentity,
                recordId, build.fingerprint, build.fingerprintHash, category)
            if not ok then error("DPS identity read failed: " .. tostring(result)) end
            rows = result
        elseif recordId and type(dps.GetLeaderboard) == "function" then
            stats.dpsReads = stats.dpsReads + 1
            local ok, result = pcall(dps.GetLeaderboard, recordId, category)
            if not ok then error("DPS leaderboard read failed: " .. tostring(result)) end
            rows = result
        end
        if (type(rows) ~= "table" or #rows == 0)
            and type(dps.GetLeaderboardForEchoes) == "function"
            and type(build.echoes) == "table" then
            stats.dpsReads = stats.dpsReads + 1
            local ok, result = pcall(
                dps.GetLeaderboardForEchoes, build.echoes, category)
            if not ok then error("DPS loadout read failed: " .. tostring(result)) end
            rows = result
        end
        for _, row in ipairs(type(rows) == "table" and rows or {}) do
            local value = tonumber(row and (row.dps or row.value or row.amount)) or 0
            if value > summary[category] then summary[category] = value end
        end
    end
    if summary.dummy > 0 then summary.count = summary.count + 1 end
    if summary.lk > 0 then summary.count = summary.count + 1 end
    summary.best = math.max(summary.dummy, summary.lk)
    if summary.count == 2 then
        summary.average = (summary.dummy + summary.lk) / 2
    elseif summary.count == 1 then
        summary.average = summary.best
    end
    return summary
end

local function BuildProjection(filters)
    local catalog = Nexus and Nexus.BuildCatalog
    local reader = catalog and (catalog.Summaries or catalog.All)
    if type(reader) ~= "function" then
        error("BuildCatalog projection reader unavailable")
    end
    counters.builds.catalogWalks = counters.builds.catalogWalks + 1
    local all = reader()
    if type(all) ~= "table" then error("BuildCatalog projection reader returned invalid data") end
    local out = {}
    local summary = {
        total=0, mine=0, savedLoadouts=0, uploaded=0,
        ready=0, pending=0,
    }
    for _, build in pairs(all) do
        if type(build) == "table" then
            summary.total = summary.total + 1
            local own = IsOwnBuild(build, filters)
            if own then summary.mine = summary.mine + 1 end
            if build.importedSavedBuild then
                summary.savedLoadouts = summary.savedLoadouts + 1
            elseif own then
                summary.uploaded = summary.uploaded + 1
            end
            local classMatch = filters.classFilter == ""
                or tostring(build.class or ""):upper() == filters.classFilter
            local scopeMatch = filters.scope == "mine"
                and (build.importedSavedBuild or own)
                or filters.scope ~= "mine" and not build.importedSavedBuild
            local searchMatch = filters.search == ""
                or tostring(build.title or ""):lower():find(filters.search, 1, true)
                or tostring(build.author or ""):lower():find(filters.search, 1, true)
                or tostring(build.description or ""):lower():find(filters.search, 1, true)
            if classMatch and scopeMatch and searchMatch then
                -- BuildCatalog readers return fresh public snapshots. This
                -- projection owns the row and may attach derived DPS fields
                -- without another full-table copy.
                local copy = build
                if filters.skipDps then
                    -- Emergency browser safe mode. The dedicated Leaderboard
                    -- remains the DPS surface; opening Builds must not join
                    -- every catalog row to DPS data on the main thread.
                    copy._nexusDps = {
                        dummy=0,lk=0,best=0,average=0,count=0,
                    }
                    copy._nexusDpsDeferred = true
                else
                    copy._nexusDps = BuildDpsSummary(copy)
                end
                copy._nexusBestDps = copy._nexusDps.best
                out[#out + 1] = copy
                if IsLoaded(copy) then summary.ready = summary.ready + 1
                else summary.pending = summary.pending + 1 end
            end
        end
    end
    counters.builds.sorts = counters.builds.sorts + 1
    table.sort(out, function(left, right)
        local leftLoaded, rightLoaded = IsLoaded(left), IsLoaded(right)
        if leftLoaded ~= rightLoaded then return leftLoaded end
        local leftCount = left._nexusDps and left._nexusDps.count or 0
        local rightCount = right._nexusDps and right._nexusDps.count or 0
        if leftCount ~= rightCount then return leftCount > rightCount end
        if filters.sortMode == "recent"
            or (filters.skipDps and filters.sortMode == "dps") then
            local lt = left.lastModified or left.postedAt or 0
            local rt = right.lastModified or right.postedAt or 0
            if lt ~= rt then return lt > rt end
        elseif filters.sortMode == "dps" then
            local ld = leftCount == 2 and left._nexusDps.average
                or left._nexusDps.best or 0
            local rd = rightCount == 2 and right._nexusDps.average
                or right._nexusDps.best or 0
            if ld ~= rd then return ld > rd end
        end
        local ln, rn = tostring(left.title or ""):lower(),
            tostring(right.title or ""):lower()
        if ln ~= rn then return ln < rn end
        return TypedIdentity(left.id) < TypedIdentity(right.id)
    end)
    summary.matched = #out
    if filters.resultLimit > 0 and #out > filters.resultLimit then
        for index = #out, filters.resultLimit + 1, -1 do
            out[index] = nil
        end
        summary.limited = true
        summary.limit = filters.resultLimit
    end
    summary.filtered = #out
    return out, summary
end

local function PlayerKey(value)
    return tostring(value or "?"):lower():gsub("%s+", "")
end

local function CharacterKey(row)
    row = type(row) == "table" and row or {}
    if type(row.ownerKey) == "string" then
        local name, realm = row.ownerKey:match("^([^@]+)@([^@]+)$")
        name = PlayerKey(name)
        realm = tostring(realm or ""):lower():gsub("%s+", "")
        if name ~= "?" and realm ~= "" and realm ~= "unknown" then
            return name .. "@" .. realm
        end
    end
    local realm = tostring(row.realm or ""):lower():gsub("%s+", "")
    if realm ~= "" and realm ~= "unknown" then
        local name = PlayerKey(row.player):match("^([^-]+)")
            or PlayerKey(row.player)
        return name .. "@" .. realm
    end
    return PlayerKey(row.player)
end

local function RecordKey(row)
    return CharacterKey(row)
        .. "|" .. TypedIdentity(row and (row.fingerprint or row.buildId))
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

local LeaderboardSource

local function CombinedRows()
    local dummy, lk = LeaderboardSource("dummy"), LeaderboardSource("lk")
    local dummyByKey, dummyByBuild = {}, {}
    for _, row in ipairs(dummy) do
        dummyByKey[RecordKey(row)] = row
        if row.buildId then
            dummyByBuild[CharacterKey(row) .. "|"
                .. TypedIdentity(row.buildId)] = row
        end
    end
    local out = {}
    for _, lrow in ipairs(lk) do
        local drow = dummyByKey[RecordKey(lrow)]
        if not drow and lrow.buildId then
            drow = dummyByBuild[CharacterKey(lrow)
                .. "|" .. TypedIdentity(lrow.buildId)]
        end
        if drow then
            local average = ((tonumber(drow.dps) or 0)
                + (tonumber(lrow.dps) or 0)) / 2
            out[#out + 1] = {
                player=lrow.player, dps=average, average=average,
                dummyDps=drow.dps, lkDps=lrow.dps,
                dummyDuration=drow.duration, lkDuration=lrow.duration,
                level=math.max(tonumber(drow.level) or 0,
                    tonumber(lrow.level) or 0),
                ts=math.min(tonumber(drow.ts) or 0, tonumber(lrow.ts) or 0),
                category="combined",
                ownerKey=lrow.ownerKey or drow.ownerKey,
                realm=lrow.realm or drow.realm,
                fingerprint=lrow.fingerprint or drow.fingerprint,
                echoes=lrow.echoes or drow.echoes,
                lockedEchoes=lrow.lockedEchoes or drow.lockedEchoes,
                buildId=lrow.buildId or drow.buildId,
                build=lrow.build or drow.build,
            }
        end
    end
    counters.leaderboard.sorts = counters.leaderboard.sorts + 1
    table.sort(out, function(left, right)
        if left.average ~= right.average then return left.average > right.average end
        return tostring(left.player):lower() < tostring(right.player):lower()
    end)
    return out
end

local function LeaderboardSourceKey(category)
    local revisions = Nexus and Nexus.Revisions or {}
    return CacheKey({
        Revision(revisions.BUILD_LIBRARY_CHANGED),
        Revision(revisions.DPS_CHANGED),
        category,
    })
end

LeaderboardSource = function(category)
    local key = LeaderboardSourceKey(category)
    local cache = caches.leaderboardSources[category]
    if cache and cache.key == key and type(cache.rows) == "table" then
        counters.leaderboard.sourceHits =
            counters.leaderboard.sourceHits + 1
        return cache.rows
    end
    local rows = category == "combined" and CombinedRows() or Board(category)
    caches.leaderboardSources[category] = {key=key, rows=rows}
    counters.leaderboard.sourceRebuilds =
        counters.leaderboard.sourceRebuilds + 1
    return rows
end

local function LeaderboardProjection(filters)
    local source = LeaderboardSource(filters.category)
    local out = {}
    for _, row in ipairs(source) do
        local build = type(row.build) == "table" and row.build or {}
        local class = tostring(build.class or row.class or "UNKNOWN"):upper()
        local classMatch = filters.classFilter == "ALL"
            or class == filters.classFilter
        local searchMatch = filters.search == ""
            or tostring(row.player or ""):lower():find(filters.search, 1, true)
            or tostring(build.title or ""):lower():find(filters.search, 1, true)
            or tostring(build.author or ""):lower():find(filters.search, 1, true)
        if classMatch and searchMatch then out[#out + 1] = DeepCopy(row) end
    end
    -- GetDpsBoard and CombinedRows already establish rank order. Count this as
    -- a projection order operation without re-sorting category boards.
    if filters.category ~= "combined" then
        counters.leaderboard.sorts = counters.leaderboard.sorts + 1
    end
    return out, {filtered=#out, category=filters.category}
end

function Projections.Builds(filters)
    local normalized = NormalizeBuildFilters(filters)
    return Cached("builds", function() return BuildKey(normalized) end,
        function() return BuildProjection(normalized) end)
end

-- Cheap dirty probe for view timers. It intentionally returns no cached rows,
-- so an unchanged safety tick cannot copy the full projection merely to learn
-- that the already rendered data is current.
function Projections.BuildsCurrent(filters)
    local normalized = NormalizeBuildFilters(filters)
    return type(caches.builds.rows) == "table"
        and caches.builds.key == BuildKey(normalized)
end

function Projections.Leaderboard(category, filters)
    local normalized = NormalizeLeaderboardFilters(category, filters)
    return Cached("leaderboard", function() return LeaderboardKey(normalized) end,
        function() return LeaderboardProjection(normalized) end)
end

function Projections.Reset()
    caches = {builds={}, leaderboard={}, leaderboardSources={}}
end

function Projections.Stats()
    return DeepCopy(counters)
end

function Projections.CacheKeys()
    return {builds=caches.builds.key, leaderboard=caches.leaderboard.key}
end
