-- Nexus: core/CommunityProjection.lua
-- Pure Community list/detail preparation over established defensive readers.

Nexus = Nexus or {}
if type(Nexus.CommunityInternals) ~= "table" then
    Nexus.CommunityInternals = {}
end

local Projection = {}
Nexus.CommunityInternals.Projection = Projection

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[Copy(key, seen)] = Copy(child, seen)
    end
    return out
end

local function Part(value)
    local kind = type(value)
    local text = tostring(value == nil and "" or value)
    return kind .. ":" .. tostring(#text) .. ":" .. text
end

local function NormalizeFilters(filters)
    filters = type(filters) == "table" and filters or {}
    local mode = filters.sortMode
    if mode ~= "recent" and mode ~= "title" then mode = "dps" end
    local classFilter = type(filters.classFilter) == "string"
        and filters.classFilter:upper() or nil
    if classFilter == "" then classFilter = nil end
    local page = tonumber(filters.page)
    page = page and page >= 1 and math.floor(page) or 1
    return {
        search=tostring(filters.search or ""):lower()
            :gsub("^%s+", ""):gsub("%s+$", ""),
        classFilter=classFilter,
        scope=filters.scope == "mine" and "mine" or "all",
        sortMode=mode,
        currentClassOnly=filters.currentClassOnly ~= false,
        qualifiedOnly=filters.qualifiedOnly ~= false,
        page=page,pageSize=20,
    }
end

local function FilterKey(filters)
    return table.concat({
        Part(filters.search), Part(filters.classFilter),
        Part(filters.scope), Part(filters.sortMode),
        Part(filters.currentClassOnly), Part(filters.qualifiedOnly),
        Part(filters.page), Part(filters.pageSize),
    }, "|")
end

local function RevisionKey(snapshot)
    snapshot = type(snapshot) == "table" and snapshot or {}
    return Part(snapshot.build or snapshot.builds or 0)
        .. "|" .. Part(snapshot.dps or 0)
end

local function IsOwnBuild(build, context)
    if type(build) ~= "table" then return false end
    local ownerKey = tostring(context.ownerKey or ""):lower()
    if build.ownerKey then
        return ownerKey ~= ""
            and tostring(build.ownerKey):lower() == ownerKey
    end
    local player = tostring(context.player or ""):lower()
    return build.isMine == true and player ~= ""
        and tostring(build.author or ""):lower() == player
end

local function PublicOrdinaryComplete(build)
    local evidence = Nexus and Nexus.LoadoutEvidence
    if not (evidence and type(evidence.OrdinaryCompleteness) == "function") then
        return false
    end
    local resolver = type(evidence.PublicOrdinaryCompleteness) == "function"
        and evidence.PublicOrdinaryCompleteness
        or evidence.OrdinaryCompleteness
    local ok, verdict = pcall(resolver, build)
    return ok and type(verdict) == "table" and verdict.complete == true
end

local function RecordBuildId(build)
    return build and (build.recordBuildId
        or build.publishedBuildId or build.id) or nil
end

local function DpsText(value)
    value = tonumber(value) or 0
    if value >= 1000000 then
        return string.format("%.2fM", value / 1000000)
    end
    if value >= 1000 then
        return string.format("%dk", math.floor(value / 1000))
    end
    return tostring(math.floor(value))
end

local DASH = "\226\128\148"
local function RecordText(label, rows, personal)
    local top = rows and rows[1]
    local best = top and DpsText(top.dps) or DASH
    local holder = top and tostring(top.player or "Unknown") or "No record yet"
    local yours = personal and DpsText(personal.dps) or DASH
    return string.format(
        "|cffffffff%s|r  |cffffd200%s|r |cff888888%s|r   |cff66ff99Your best %s|r",
        label, best, holder, yours)
end

local function RelevantOwnedKey(build, context)
    local bySpell = type(context.ownedBySpell) == "table"
        and context.ownedBySpell or {}
    local parts = {}
    for index, echo in ipairs(type(build) == "table"
        and type(build.echoes) == "table" and build.echoes or {}) do
        local spellId = echo and echo.spellId
        parts[index] = Part(spellId) .. "=" .. Part(bySpell[spellId])
    end
    return table.concat(parts, ",")
end

local function DetailKey(id, revisions, context, build)
    return table.concat({
        Part(id), RevisionKey(revisions),
        Part(tostring(context.ownerKey or ""):lower()),
        Part(tostring(context.player or ""):lower()),
        Part(context.isAdmin == true), Part(context.detailsAvailable == true),
        RelevantOwnedKey(build, context),
    }, "|")
end

local function SafeRows(callback, ...)
    if type(callback) ~= "function" then return {} end
    local rows = callback(...)
    return type(rows) == "table" and rows or {}
end

local function EvidenceFingerprint(rows)
    local counts, ids = {}, {}
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        if type(row) == "table" and not row.locked then
            local id = tonumber(row.spellId or row.id)
            local stacks = tonumber(row.stacks or row.count) or 1
            if id then
                if counts[id] == nil then ids[#ids + 1] = id end
                counts[id] = (counts[id] or 0) + stacks
            end
        end
    end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        parts[#parts + 1] = tostring(id) .. "x" .. tostring(counts[id])
    end
    return #parts > 0 and table.concat(parts, ",") or "0"
end

function Projection.New(options)
    options = type(options) == "table" and options or {}
    local builds = assert(options.builds,
        "CommunityProjection requires a build projection reader")
    local buildsCurrent = assert(options.buildsCurrent,
        "CommunityProjection requires a build currentness reader")
    local loadBuild = assert(options.loadBuild,
        "CommunityProjection requires an exact build reader")
    local revisionSnapshot = type(options.revisionSnapshot) == "function"
        and options.revisionSnapshot or function() return {} end
    local listCache, detailCache
    local stats = {
        list={hits=0,rebuilds=0,failures=0,currentChecks=0,readerCalls=0},
        detail={hits=0,rebuilds=0,failures=0,loadCalls=0,
            boardReads=0,leaderboardReads=0,personalReads=0},
    }
    local M = {}

    local function LockedEvidence(build)
        local dummy, lk
        local resolver = Nexus and Nexus.CandidateEvidence
        if not (resolver and type(resolver.ResolveLocked) == "function") then
            return {status="unavailable",
                reason="locked Echo resolver is unavailable",
                fingerprint="0",lockedEchoes={}}
        end

        if type(options.dpsRecord) == "function" then
            -- Always compare both exact category records.  Stopping after the
            -- first hit made Community disagree with combined Leaderboard
            -- evidence and hid category conflicts.
            stats.detail.boardReads = stats.detail.boardReads + 2
            local okDummy, dummyResult = pcall(
                options.dpsRecord, build, "dummy")
            local okLk, lkResult = pcall(options.dpsRecord, build, "lk")
            if not okDummy or not okLk then
                return {status="unavailable",
                    reason="locked Echo record lookup failed",
                    fingerprint="0",lockedEchoes={}}
            end
            dummy, lk = dummyResult, lkResult
        elseif type(options.dpsBoard) == "function" then
            -- Compatibility for older injected projection readers.  Product
            -- assembly supplies dpsRecord; this branch never runs on its hot
            -- path and still compares both categories through the shared
            -- resolver.
            local legacy = {}
            for _, category in ipairs({"dummy", "lk"}) do
                stats.detail.boardReads = stats.detail.boardReads + 1
                for _, row in ipairs(SafeRows(options.dpsBoard, category)) do
                    if type(row) == "table" and row.buildId == build.id
                        and type(row.lockedEchoes) == "table" then
                        legacy[category] = Copy(row)
                        break
                    end
                end
            end
            local fingerprint = EvidenceFingerprint(build.echoes)
            local ordinary = {}
            for _, row in ipairs(type(build.echoes) == "table"
                and build.echoes or {}) do
                if type(row) == "table" and not row.locked then
                    ordinary[#ordinary + 1] = Copy(row)
                end
            end
            for category, row in pairs(legacy) do
                row.category, row.buildId = category, build.id
                row.resolvedBuildId, row.fingerprint = build.id, fingerprint
                row.echoes, row.lockedFingerprint = Copy(ordinary), nil
            end
            dummy, lk = legacy.dummy, legacy.lk
            build = Copy(build)
            build.fingerprint = fingerprint
        end

        local ok, result = pcall(resolver.ResolveLocked, {
            build=build,dummyRecord=dummy,lkRecord=lk,
        })
        if not ok or type(result) ~= "table" then
            return {status="unavailable",reason="locked Echo resolution failed",
                fingerprint="0",lockedEchoes={}}
        end
        result.status = tostring(result.status or "unavailable"):sub(1, 24)
        result.reason = tostring(result.reason or ""):sub(1, 96)
        result.fingerprint = tostring(result.fingerprint or "0"):sub(1, 96)
        return result
    end

    local function Current(filters, key)
        stats.list.currentChecks = stats.list.currentChecks + 1
        local ok, current = pcall(buildsCurrent, filters)
        return ok and current == true
            and listCache and listCache.key == key
    end

    function M.NormalizeFilters(filters)
        return NormalizeFilters(filters)
    end

    function M.ListCurrent(filters)
        local normalized = NormalizeFilters(filters)
        return Current(normalized, FilterKey(normalized)) and true or false
    end

    function M.List(filters)
        local normalized = NormalizeFilters(filters)
        local key = FilterKey(normalized)
        if Current(normalized, key) then
            stats.list.hits = stats.list.hits + 1
            return listCache.rows, listCache.summary
        end

        stats.list.rebuilds = stats.list.rebuilds + 1
        stats.list.readerCalls = stats.list.readerCalls + 1
        local ok, rows, summary, err = pcall(builds, normalized)
        if ok and rows == nil and err == "pending" then
            return nil, nil, "pending"
        end
        if not ok or type(rows) ~= "table" then
            stats.list.failures = stats.list.failures + 1
            return nil, nil, tostring(ok and (err or summary)
                or rows or "Community list projection failed")
        end
        listCache = {key=key,rows=rows,summary=summary}
        return listCache.rows, listCache.summary
    end

    local function BuildDetail(build, context)
        local lockedResult = LockedEvidence(build)
        local lockedEchoes = lockedResult.status == "ok"
            and Copy(lockedResult.lockedEchoes) or nil

        local bySpell = type(context.ownedBySpell) == "table"
            and context.ownedBySpell or {}
        local echoes, missing, totalSlots = {}, 0, 0
        for _, echo in ipairs(type(build.echoes) == "table"
            and build.echoes or {}) do
            local copy = Copy(echo)
            local have = tonumber(bySpell[echo.spellId]) or 0
            local want = tonumber(echo.stacks or echo.count) or 1
            copy.have, copy.want, copy.missing = have, want, have < want
            if copy.missing then missing = missing + 1 end
            totalSlots = totalSlots + want
            echoes[#echoes + 1] = copy
        end
        local hasLoadout = #echoes > 0
        local mine = IsOwnBuild(build, context)
        local admin = context.isAdmin == true
        local recordId = RecordBuildId(build)

        stats.detail.leaderboardReads = stats.detail.leaderboardReads + 2
        local dummy = SafeRows(options.leaderboard, recordId, "dummy")
        local lk = SafeRows(options.leaderboard, recordId, "lk")
        stats.detail.personalReads = stats.detail.personalReads + 2
        local dummyPersonal = type(options.personalBest) == "function"
            and options.personalBest(recordId, "dummy") or nil
        local lkPersonal = type(options.personalBest) == "function"
            and options.personalBest(recordId, "lk") or nil
        local lockDummy, lockLk = dummy, lk
        if recordId ~= build.id then
            stats.detail.leaderboardReads = stats.detail.leaderboardReads + 2
            lockDummy = SafeRows(options.leaderboard, build.id, "dummy")
            lockLk = SafeRows(options.leaderboard, build.id, "lk")
        end
        local loadoutLocked = build.autoDps == true
            or #lockDummy > 0 or #lockLk > 0

        local editState
        if build.importedSavedBuild then
            editState = build.publishedBuildId
                and "Uploaded. Upload Build again to publish title/description or loadout changes."
                or "Local server loadout. Edit its title/description, then Upload Build when ready."
        elseif mine and loadoutLocked then
            editState = "|cffffd200Leaderboard loadout locked.|r Title and description may still be edited."
        elseif mine then
            editState = "You own this build. Edit can also replace its Echoes from your active wishlist."
        end

        local hasLink = type(build.link) == "string" and build.link ~= ""
        local ownThis = mine or admin
        return {
            build=Copy(build), echoes=echoes,
            lockedEchoes=lockedEchoes,
            lockedEvidenceStatus=lockedResult.status,
            lockedEvidenceReason=lockedResult.reason ~= ""
                and lockedResult.reason or nil,
            lockedEvidenceFingerprint=lockedResult.fingerprint,
            hasLoadout=hasLoadout, needsLoadout=not hasLoadout,
            missing=missing,totalSlots=totalSlots,
            mine=mine,admin=admin,loadoutLocked=loadoutLocked,
            hasLink=hasLink,showLink=hasLink or ownThis,
            canSaveLink=ownThis,
            showEdit=mine,
            showDelete=(mine and not build.importedSavedBuild)
                or (not mine and admin),
            deleteText=admin and not mine and "Remove" or "Stop Sharing",
            editState=editState,
            actionText=build.importedSavedBuild
                and (build.publishedBuildId and "Update Upload" or "Upload Build")
                or (hasLoadout and "Copy into Editor" or "Request Loadout"),
            detailsAvailable=context.detailsAvailable == true,
            dummyRows=Copy(dummy),lkRows=Copy(lk),
            dummyPersonal=Copy(dummyPersonal),lkPersonal=Copy(lkPersonal),
            dummyRecord=RecordText("Training Dummy", dummy, dummyPersonal),
            lkRecord=RecordText("Lich King", lk, lkPersonal),
        }
    end

    function M.Detail(id, context)
        if id == nil then return nil end
        context = type(context) == "table" and context or {}
        local okRevision, revisions = pcall(revisionSnapshot)
        if not okRevision then revisions = {} end
        local cachedBuild = detailCache and detailCache.id == id
            and detailCache.value and detailCache.value.build or nil
        local key = DetailKey(id, revisions, context, cachedBuild)
        if cachedBuild and detailCache.key == key then
            stats.detail.hits = stats.detail.hits + 1
            return detailCache.value
        end

        stats.detail.rebuilds = stats.detail.rebuilds + 1
        stats.detail.loadCalls = stats.detail.loadCalls + 1
        local okLoad, build = pcall(loadBuild, id)
        if not okLoad then
            stats.detail.failures = stats.detail.failures + 1
            return nil, tostring(build)
        end
        if not PublicOrdinaryComplete(build) then return nil end
        key = DetailKey(id, revisions, context, build)
        if detailCache and detailCache.id == id and detailCache.key == key then
            stats.detail.hits = stats.detail.hits + 1
            return detailCache.value
        end
        local ok, value = pcall(BuildDetail, build, context)
        if not ok or type(value) ~= "table" then
            stats.detail.failures = stats.detail.failures + 1
            return nil, tostring(value or "Community detail projection failed")
        end
        detailCache = {id=id,key=key,value=value}
        return detailCache.value
    end

    function M.Stats()
        return Copy(stats)
    end

    return M
end
