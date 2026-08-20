-- Nexus: read-only Sync compatibility hashes, summaries, and candidate views.

Nexus = Nexus or {}
if type(Nexus.SyncInternals) ~= "table" then Nexus.SyncInternals = {} end

local Compatibility = {}
Nexus.SyncInternals.Compatibility = Compatibility

function Compatibility.New(options)
    options = options or {}
    local buckets = assert(options.buckets, "buckets required")
    local getCatalog = assert(options.getCatalog, "catalog callback required")
    local getBuildHashCache = assert(options.getBuildHashCache,
        "build hash cache callback required")
    local getBuildRevision = assert(options.getBuildRevision,
        "build revision callback required")
    local getDpsCapture = assert(options.getDpsCapture,
        "DPS callback required")
    local getTombstones = assert(options.getTombstones,
        "tombstone callback required")
    local localOwnsTomb = assert(options.localOwnsTomb,
        "tombstone authority callback required")
    local relayEligible = assert(options.relayEligible,
        "build relay authority callback required")
    local myName = assert(options.myName, "name callback required")
    local currentOwnerKey = assert(options.currentOwnerKey,
        "exact owner callback required")
    local now = assert(options.now, "clock callback required")
    local getCodec = assert(options.getCodec, "Codec callback required")
    local validIdentifier = assert(options.validIdentifier,
        "identifier validator required")
    local validHash = assert(options.validHash, "hash validator required")
    local escapedLen = assert(options.escapedLen,
        "escaped length callback required")
    local codeIndex = assert(options.codeIndex, "index wire code required")
    local maxBuildIdBytes = assert(options.maxBuildIdBytes,
        "build id limit required")
    local chatLimit = assert(options.chatLimit, "chat limit required")
    local chatSafety = assert(options.chatSafety, "chat safety required")
    local noteStat = options.noteStat or function() end
    local candidateCache
    local C = {}

    local function HasCompleteOrdinary(build)
        if type(build) ~= "table" then return false end
        if build.ordinaryComplete ~= nil then
            return build.ordinaryComplete == true
        end
        return type(build.echoes) == "table" and #build.echoes > 0
    end

    function C.BuildBucket(id)
        local text = tostring(id or "")
        local hash = 5381
        for index = 1, #text do
            hash = ((hash * 33) + text:byte(index)) % 2147483648
        end
        return (hash % buckets) + 1
    end

    function C.TombStamp(value)
        if type(value) == "table" then return tonumber(value.stamp) or 0 end
        return tonumber(value) or 0
    end

    function C.TombAuthor(value)
        return type(value) == "table" and tostring(value.author or "") or ""
    end

    function C.LibraryHash(builds, tombstoneSource)
        local grouped = {}
        for bucket = 1, buckets do grouped[bucket] = {} end
        for id, build in pairs(builds or {}) do
            local bucket = C.BuildBucket(id)
            local complete = HasCompleteOrdinary(build) and "F" or "S"
            local fingerprint = tostring(build.fingerprintHash
                or build.fingerprint or "0")
            grouped[bucket][#grouped[bucket] + 1] = id .. ":"
                .. tostring(build.lastModified or build.postedAt or 0)
                .. ":" .. complete .. ":" .. fingerprint
        end
        for id, tombstone in pairs(tombstoneSource or getTombstones() or {}) do
            local bucket = C.BuildBucket(id)
            grouped[bucket][#grouped[bucket] + 1] = "!" .. id .. ":"
                .. tostring(C.TombStamp(tombstone)) .. ":"
                .. C.TombAuthor(tombstone)
        end
        local hashes = {}
        for bucket = 1, buckets do
            table.sort(grouped[bucket])
            local hash = 5381
            for _, text in ipairs(grouped[bucket]) do
                for index = 1, #text do
                    hash = ((hash * 33) + text:byte(index)) % 2147483648
                end
            end
            hashes[bucket] = #grouped[bucket] > 0
                and string.format("%x", hash) or "0"
        end
        return table.concat(hashes, ",")
    end

    function C.CatalogToken()
        local catalog = getCatalog()
        local version = catalog and catalog.CatalogVersion
            and catalog.CatalogVersion() or "unversioned"
        local text, encoded = tostring(version), {}
        for index = 1, #text do
            encoded[index] = string.format("%02x", text:byte(index))
        end
        return table.concat(encoded)
    end

    local function CatalogDelta()
        local catalog = getCatalog()
        return catalog and catalog.DeltaSnapshot
            and catalog.DeltaSnapshot() or {}
    end

    local function CatalogAll()
        local catalog = getCatalog()
        return catalog and catalog.All and catalog.All() or {}
    end

    function C.DeltaBuildHash()
        local cache = getBuildHashCache()
        return cache and cache.Delta and cache.Delta()
            or C.LibraryHash(CatalogDelta())
    end

    function C.LegacyBuildHash()
        local cache = getBuildHashCache()
        return cache and cache.Legacy and cache.Legacy()
            or C.LibraryHash(CatalogAll())
    end

    function C.CurrentBuildHash()
        return C.DeltaBuildHash() .. "," .. C.CatalogToken()
    end

    function C.CurrentDpsHash()
        local dps = getDpsCapture()
        if dps and dps.GetSyncHash then
            local ok, value = pcall(dps.GetSyncHash)
            if ok and value then return tostring(value) end
        end
        return "0"
    end

    function C.CanonicalBuildHashes()
        local canonicalTombstones = getTombstones()
        local catalog = getCatalog()
        if catalog and type(catalog.TombstoneSnapshot) == "function" then
            local ok, snapshot = pcall(catalog.TombstoneSnapshot)
            if ok and type(snapshot) == "table" then
                canonicalTombstones = snapshot
            end
        end
        return C.LibraryHash(CatalogDelta(), canonicalTombstones)
                .. "," .. C.CatalogToken(),
            C.LibraryHash(CatalogAll(), canonicalTombstones)
    end

    function C.HashCacheStats()
        local cache = getBuildHashCache()
        return cache and cache.Stats and cache.Stats() or {available=false}
    end

    function C.HashText(text)
        if type(text) ~= "string" or text == "" then return nil end
        local hash = 5381
        for index = 1, #text do
            hash = ((hash * 33) + text:byte(index)) % 2147483648
        end
        return string.format("%x", hash)
    end

    function C.BuildFingerprint(build)
        if build and build.fingerprint then return tostring(build.fingerprint) end
        local dps = getDpsCapture()
        if dps and dps.GetEchoKey and build
            and type(build.echoes) == "table" then
            local ok, key = pcall(dps.GetEchoKey, build.echoes)
            if ok and key then return key end
        end
        if build and type(build.echoes) == "table" then
            local counts = {}
            for _, echo in ipairs(build.echoes) do
                local id = tonumber(echo and (echo.spellId or echo.id))
                local count = tonumber(echo
                    and (echo.count or echo.stacks or echo.stack)) or 1
                if id and count > 0 then
                    counts[id] = (counts[id] or 0) + count
                end
            end
            local ids = {}
            for id in pairs(counts) do ids[#ids + 1] = id end
            table.sort(ids)
            local values = {}
            for _, id in ipairs(ids) do
                values[#values + 1] = tostring(id) .. "x"
                    .. tostring(counts[id])
            end
            if #values > 0 then return table.concat(values, ",") end
        end
        return nil
    end

    function C.SummaryEncode(build)
        return {
            id=build.id, t=build.title, a=build.author, o=build.ownerKey,
            c=build.class,
            m=tonumber(build.lastModified) or tonumber(build.postedAt) or 0,
            h=build.fingerprintHash or C.HashText(C.BuildFingerprint(build)),
            lh=C.HashText(build.link),
            n=(function()
                if type(build.echoes) == "table" then
                    local total = 0
                    for _, echo in ipairs(build.echoes) do
                        total = total + (tonumber(echo.stacks or echo.count) or 1)
                    end
                    return total
                end
                return tonumber(build.echoCount) or 0
            end)(),
            x=build.autoDps and 1 or nil,
        }
    end

    function C.PrepareSummary(build, responseContext)
        local payload = C.SummaryEncode(build)
        if not validIdentifier(payload.id, maxBuildIdBytes) then
            return nil, "invalid build id"
        end
        if not validHash(tostring(payload.h or "")) then
            return nil, "invalid build hash"
        end
        local codec = getCodec()
        local data = codec.Base64Encode(codec.JSONEncode(payload))
        local suffix = type(responseContext) == "table"
            and type(responseContext.requestId) == "string"
            and responseContext.requestId:sub(1, 3) == "c1-"
            and ("|" .. tostring(responseContext.requester)
                .. "|" .. tostring(responseContext.requestId)) or ""
        local message = string.format("%s|%s|%s%s", codeIndex, myName(),
            data, suffix)
        if escapedLen(message) > chatLimit - chatSafety then
            return nil, "summary too large"
        end
        return {messages={message}, title=build.title, summary=true}
    end

    local function CandidateKey(deltaHash)
        return tostring(deltaHash) .. "|" .. tostring(myName()) .. "|"
            .. tostring(currentOwnerKey() or "") .. "|"
            .. tostring(getBuildRevision())
    end

    function C.BuildCandidateSnapshot(deltaHash)
        local key = CandidateKey(deltaHash)
        if candidateCache and candidateCache.key == key then
            return candidateCache
        end
        local byBucket = {}
        local claimSafeByBucket = {}
        for bucket = 1, buckets do
            byBucket[bucket] = {}
            claimSafeByBucket[bucket] = true
        end
        candidateCache = {
            key=key, deltaHash=tostring(deltaHash), sender=myName(),
            ownerKey=currentOwnerKey(),
            byBucket=byBucket, phase="overlay", cursor=nil,
            claimSafeByBucket=claimSafeByBucket,
            complete=false, createdAt=now(),
        }
        noteStat("candidateSnapshots", 1)
        return candidateCache
    end

    function C.SnapshotCurrent(snapshot)
        return type(snapshot) == "table"
            and snapshot.key == CandidateKey(C.DeltaBuildHash())
    end

    function C.AdvanceCandidateSnapshot(snapshot)
        if not C.SnapshotCurrent(snapshot) then
            return false, "stale candidate snapshot", true
        end
        if snapshot.complete then return true, nil, false end
        noteStat("candidateScans", 1)
        if snapshot.phase == "overlay" then
            local catalog = getCatalog()
            local id, build, done
            if catalog and catalog.SyncDeltaNext then
                id, build, done = catalog.SyncDeltaNext(snapshot.cursor)
            else
                done = true
            end
            if done then
                snapshot.phase, snapshot.cursor = "tombstone", nil
                return false, nil, true
            end
            snapshot.cursor = id
            if build then
                local complete = HasCompleteOrdinary(build) and "F" or "S"
                local token = table.concat({"B", tostring(id),
                    tostring(build.lastModified or build.postedAt or 0),
                    complete, tostring(build.fingerprintHash
                        or build.fingerprint or "0")}, ":")
                local bucket = C.BuildBucket(id)
                if not validIdentifier(tostring(build.id or ""),
                        maxBuildIdBytes) or not relayEligible(build) then
                    snapshot.claimSafeByBucket[bucket] = false
                end
                snapshot.byBucket[bucket][#snapshot.byBucket[bucket] + 1] = {
                    kind="build", id=id, build=build, token=token,
                }
            end
            return false, nil, true
        end

        local id, tombstone = next(getTombstones() or {}, snapshot.cursor)
        if id == nil then
            snapshot.complete = true
            return true, nil, true
        end
        snapshot.cursor = id
        local bucket = C.BuildBucket(id)
        snapshot.claimSafeByBucket[bucket] = false
        if localOwnsTomb(tombstone) then
            local copy = {
                stamp=C.TombStamp(tombstone), author=C.TombAuthor(tombstone),
                ownerKey=tombstone.ownerKey,
                ownerVerified=tombstone.ownerVerified == true,
            }
            snapshot.byBucket[bucket][#snapshot.byBucket[bucket] + 1] = {
                kind="tomb", id=id, tomb=copy,
                token=table.concat({"T", tostring(id),
                    tostring(C.TombStamp(copy)), C.TombAuthor(copy)}, ":"),
            }
        end
        return false, nil, true
    end

    function C.Reset()
        candidateCache = nil
    end

    return C
end
