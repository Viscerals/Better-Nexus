-- Nexus: pure Sync wire validation and compact payload transforms.
-- Owns no transport, peer, catalog, SavedVariables, diagnostic, or gameplay state.

Nexus = Nexus or {}
if type(Nexus.SyncInternals) ~= "table" then Nexus.SyncInternals = {} end

local Protocol = {}
Nexus.SyncInternals.Protocol = Protocol

function Protocol.New(options)
    options = options or {}
    local limits = options.limits or {}
    local maxTransferIdBytes = limits.maxTransferIdBytes
    local maxHashBytes = limits.maxHashBytes
    local maxVersionBytes = limits.maxVersionBytes
    local maxBuildIdBytes = limits.maxBuildIdBytes
    local maxBuildEchoes = limits.maxBuildEchoes
    local maxRequestIdBytes = limits.maxRequestIdBytes or 80
    local bucketCount = limits.bucketCount or 8
    local maxWireFields = limits.maxWireFields or 8
    local parseVersion = assert(options.parseVersion,
        "parseVersion callback required")
    local ownerKeyMatchesAuthor = assert(options.ownerKeyMatchesAuthor,
        "ownerKeyMatchesAuthor callback required")
    local isSafeTree = assert(options.isSafeTree,
        "isSafeTree callback required")
    local identity = Nexus and Nexus.Identity
    local validText = options.validText
        or (identity and identity.ValidWireText)
    local validPeerName = options.validPeerName
        or (identity and identity.ValidPlayer)
    local canonicalOwnerKey = options.canonicalOwnerKey
        or (identity and identity.CanonicalOwnerKey)
    local P = {}

    local function OwnerIdentityMatches(ownerKey, author)
        if not ownerKeyMatchesAuthor(ownerKey, author) then return false end
        if ownerKey == nil or type(author) ~= "string"
            or not author:find("-", 1, true) then return true end
        if not canonicalOwnerKey then return true end
        local name, realm = author:match("^([^-]+)%-(.+)$")
        if not name or not realm then return false end
        local owner = canonicalOwnerKey(ownerKey)
        local qualifiedAuthor = canonicalOwnerKey(name .. "@" .. realm)
        return owner ~= nil and owner == qualifiedAuthor
    end

    function P.EscapedLen(value)
        return #value + select(2, value:gsub("|", ""))
    end

    function P.FiniteNumber(value)
        return type(value) == "number" and value == value
            and value < math.huge and value > -math.huge
    end

    function P.ValidText(value, maxBytes, allowEmpty)
        if validText then return validText(value, maxBytes, allowEmpty) end
        return type(value) == "string"
            and (allowEmpty or value ~= "")
            and #value <= maxBytes
            and not value:find("[%c]")
    end

    function P.ValidMultilineText(value, maxBytes, allowEmpty)
        if validText then
            return validText(value, maxBytes, allowEmpty, true)
        end
        if type(value) ~= "string" or (not allowEmpty and value == "")
            or #value > maxBytes then return false end
        for index = 1, #value do
            local byte = value:byte(index)
            if (byte < 0x20 and byte ~= 0x0A and byte ~= 0x0D)
                or byte == 0x7F then return false end
        end
        return true
    end

    function P.ValidField(value, maxBytes, allowEmpty)
        return P.ValidText(value, maxBytes, allowEmpty)
            and not value:find("|", 1, true)
    end

    function P.ValidIdentifier(value, maxBytes)
        return P.ValidField(value, maxBytes, false)
            and value:match("^[%w%._:@%+%-]+$") ~= nil
    end

    function P.ValidTransferIdentifier(value)
        return P.ValidField(value, maxTransferIdBytes, false)
            and not value:find("%s")
    end

    function P.ValidPeerName(value)
        if validPeerName then return validPeerName(value) end
        return P.ValidField(value, 80, false) and not value:find("%s")
    end

    function P.ValidHash(value)
        return P.ValidField(value, maxHashBytes, false)
            and value:match("^[%x,]+$") ~= nil
    end

    function P.ValidVersion(value)
        if not P.ValidField(value, maxVersionBytes, false)
            or value:match("^[%w%.%+%-]+$") == nil then return false end
        local ok, parsed = pcall(parseVersion, value)
        return ok and parsed ~= nil
    end

    function P.ValidIntegerText(value, minimum)
        if not P.ValidField(value, 24, false)
            or value:match("^%-?%d+$") == nil then return false end
        local number = tonumber(value)
        return P.FiniteNumber(number) and number == math.floor(number)
            and number >= (minimum or 0)
    end

    function P.SplitHashes(value)
        local out, index = {}, 1
        for part in tostring(value or ""):gmatch("([^,]+)") do
            out[index], index = part, index + 1
        end
        return out
    end

    function P.CompactEncode(build)
        local echoes = {}
        for _, echo in ipairs(build.echoes or {}) do
            -- Slot 4 is optional. A trailing nil keeps ordinary Echoes on the
            -- established three-value wire shape; older peers ignore slot 4.
            echoes[#echoes + 1] = {
                tonumber(echo.spellId), tonumber(echo.quality) or 0,
                math.max(1, tonumber(echo.stacks) or 1),
                echo.locked and 1 or nil,
            }
        end
        return {
            id=build.id, t=build.title, a=build.author, o=build.ownerKey,
            c=build.class,
            m=tonumber(build.lastModified) or tonumber(build.postedAt) or 0,
            d=(type(build.description) == "string" and build.description ~= "")
                and build.description or nil,
            e=echoes,
            x=build.autoDps and 1 or nil,
            lk=(type(build.link) == "string" and build.link ~= "")
                and build.link or nil,
        }
    end

    function P.CompactDecode(data)
        if type(data) ~= "table" then return nil end
        local title = data.t or data.title
        local author = data.a or data.author
        local ownerKey = data.o or data.ownerKey
        local class = data.c or data.class
        local lastModified = tonumber(
            data.m or data.lastModified or data.postedAt) or 0
        local rawEchoes = data.e or data.echoes
        if not (P.ValidIdentifier(data.id, maxBuildIdBytes)
            and type(title) == "string" and title ~= ""
            and type(author) == "string" and P.ValidPeerName(author)
            and type(rawEchoes) == "table" and #rawEchoes <= maxBuildEchoes) then
            return nil
        end
        if not OwnerIdentityMatches(ownerKey, author) then return nil end

        local echoes = {}
        for _, echo in ipairs(rawEchoes) do
            local spellId, quality, stacks, locked
            if type(echo) == "table" then
                if echo[1] then
                    -- Current compact array form.
                    spellId = tonumber(echo[1])
                    quality = tonumber(echo[2]) or 0
                    stacks = math.max(1, tonumber(echo[3]) or 1)
                    locked = (echo[4] == 1) or nil
                else
                    -- Accepted legacy verbose object form.
                    spellId = tonumber(echo.spellId)
                    quality = tonumber(echo.quality) or 0
                    stacks = math.max(1, tonumber(echo.stacks) or 1)
                    locked = echo.locked and true or nil
                end
            end
            if spellId and spellId > 0 then
                echoes[#echoes + 1] = {
                    spellId=spellId, quality=quality, stacks=stacks, locked=locked,
                }
            end
        end
        if #echoes == 0 then return nil end
        return {
            id=tostring(data.id),
            title=tostring(title):sub(1, 120),
            author=type(author) == "string" and author:sub(1, 80) or "Unknown",
            ownerKey=type(ownerKey) == "string"
                and (canonicalOwnerKey and canonicalOwnerKey(ownerKey)
                    or ownerKey:lower()) or nil,
            class=type(class) == "string" and class or nil,
            description=type(data.d or data.description) == "string"
                and (data.d or data.description):sub(1, 4000) or "",
            lastModified=lastModified,
            postedAt=tonumber(data.postedAt) or lastModified,
            echoes=echoes,
            autoDps=data.x == 1 or data.autoDps == true,
            link=(type(data.lk) == "string" and data.lk ~= "")
                and data.lk or nil,
        }
    end

    function P.ValidatePayload(data)
        if type(data) ~= "table" then return nil end
        if not isSafeTree(data, 6, 2000) then return nil end
        return P.CompactDecode(data)
    end

    local function DenseArray(value, maximum)
        if type(value) ~= "table" then return false end
        local count, highest = 0, 0
        for key in pairs(value) do
            if type(key) ~= "number" or key < 1
                or key ~= math.floor(key) then return false end
            count = count + 1
            if key > highest then highest = key end
        end
        return count > 0 and count == highest and count <= maximum
    end

    local function NetworkEcho(echo)
        if type(echo) ~= "table" then return false end
        local spellId, quality, stacks, locked
        if echo[1] ~= nil then
            local count = 0
            for key in pairs(echo) do
                if type(key) ~= "number" or key < 1 or key > 4
                    or key ~= math.floor(key) then return false end
                count = count + 1
            end
            if count < 3 or count > 4 or echo[2] == nil
                or echo[3] == nil then return false end
            spellId, quality, stacks, locked = echo[1], echo[2], echo[3], echo[4]
            if locked ~= nil and locked ~= 1 then return false end
        else
            spellId, quality, stacks, locked = echo.spellId,
                echo.quality, echo.stacks, echo.locked
            if locked ~= nil and type(locked) ~= "boolean" then return false end
        end
        local valid = P.FiniteNumber(spellId) and spellId >= 1
            and spellId <= 2147483647 and spellId == math.floor(spellId)
            and P.FiniteNumber(quality) and quality >= 0 and quality <= 255
            and quality == math.floor(quality)
            and P.FiniteNumber(stacks) and stacks >= 1 and stacks <= 120
            and stacks == math.floor(stacks)
        return valid, stacks, spellId, quality,
            locked == true or locked == 1
    end

    local function ScalarAliasesAgree(compact, verbose, normalize)
        if compact == nil or verbose == nil then return true end
        if normalize then
            local left, right = normalize(compact), normalize(verbose)
            return left ~= nil and left == right
        end
        return type(compact) == type(verbose) and compact == verbose
    end

    local function EchoAliasesAgree(compact, verbose)
        if compact == nil or verbose == nil then return true end
        if not DenseArray(compact, maxBuildEchoes)
            or not DenseArray(verbose, maxBuildEchoes)
            or #compact ~= #verbose then return false end
        for index = 1, #compact do
            local lv, ls, li, lq, ll = NetworkEcho(compact[index])
            local rv, rs, ri, rq, rl = NetworkEcho(verbose[index])
            if not lv or not rv or ls ~= rs or li ~= ri or lq ~= rq
                or ll ~= rl then return false end
        end
        return true
    end

    local function NetworkAliasesAgree(data)
        return ScalarAliasesAgree(data.t, data.title)
            and ScalarAliasesAgree(data.a, data.author)
            and ScalarAliasesAgree(data.o, data.ownerKey,
                canonicalOwnerKey)
            and ScalarAliasesAgree(data.c, data.class)
            and ScalarAliasesAgree(data.m, data.lastModified)
            and ScalarAliasesAgree(data.d, data.description)
            and ScalarAliasesAgree(data.lk, data.link)
            and (data.x == nil or data.autoDps == nil
                or data.x == 1 and data.autoDps == true)
            and EchoAliasesAgree(data.e, data.echoes)
    end

    local unsupportedNetworkAuthority = {
        player=true,p=true,realm=true,r=true,claimedOwnerKey=true,
        relaySender=true,ownerVerified=true,isMine=true,
        importedSavedBuild=true,
    }

    function P.ValidateNetworkPayload(data)
        if type(data) ~= "table" or not isSafeTree(data, 6, 2000) then
            return nil
        end
        if not NetworkAliasesAgree(data) then return nil end
        for field in pairs(unsupportedNetworkAuthority) do
            if data[field] ~= nil then return nil end
        end
        local title, author = data.t or data.title, data.a or data.author
        local ownerKey, class = data.o or data.ownerKey, data.c or data.class
        local modified = data.m
        if modified == nil then modified = data.lastModified end
        if modified == nil then modified = data.postedAt end
        local description = data.d
        if description == nil then description = data.description end
        local link = data.lk
        if link == nil then link = data.link end
        local echoes = data.e or data.echoes
        if not P.ValidIdentifier(data.id, maxBuildIdBytes)
            or not P.ValidText(title, 120, false)
            or not P.ValidPeerName(author)
            or (ownerKey ~= nil and not P.ValidField(ownerKey, 160, false))
            or not OwnerIdentityMatches(ownerKey, author)
            or (class ~= nil and not P.ValidField(class, 32, false))
            or not P.FiniteNumber(modified) or modified < 0
            or modified > 9007199254740991
            or modified ~= math.floor(modified)
            or (description ~= nil
                and not P.ValidMultilineText(description, 4000, true))
            or (link ~= nil and not P.ValidText(link, 2048, false))
            or (data.x ~= nil and data.x ~= 1)
            or (data.autoDps ~= nil and type(data.autoDps) ~= "boolean")
            or not DenseArray(echoes, maxBuildEchoes) then
            return nil
        end
        local total = 0
        for index = 1, #echoes do
            local valid, stacks = NetworkEcho(echoes[index])
            if not valid then return nil end
            total = total + stacks
            if total > maxBuildEchoes * 120 then return nil end
        end
        return P.CompactDecode(data)
    end

    -- WLBI is a compact scalar summary, not a permissive JSON object.  Keep
    -- its wire contract exact so coercible strings, truthy flags, collections,
    -- and future/unknown fields cannot be normalized into represented data.
    local summaryFields = {
        id=true,t=true,a=true,o=true,c=true,m=true,
        h=true,lh=true,n=true,x=true,
    }
    local function ValidSummaryHash(value)
        return type(value) == "string" and #value >= 1 and #value <= 8
            and value:match("^[%x]+$") ~= nil
    end

    function P.ValidateNetworkSummary(data)
        if type(data) ~= "table" or not isSafeTree(data, 4, 80) then
            return nil, "schema"
        end
        for key in pairs(data) do
            if type(key) ~= "string" or not summaryFields[key] then
                return nil, "schema"
            end
        end
        local class = data.c
        local validClass = class == nil or class == "UNKNOWN"
            or class == "WARRIOR" or class == "PALADIN"
            or class == "HUNTER" or class == "ROGUE"
            or class == "PRIEST" or class == "DEATHKNIGHT"
            or class == "SHAMAN" or class == "MAGE"
            or class == "WARLOCK" or class == "DRUID"
        if not P.ValidIdentifier(data.id, maxBuildIdBytes)
            or not P.ValidText(data.t, 120, false)
            or not P.ValidPeerName(data.a)
            or (data.o ~= nil and not P.ValidField(data.o, 160, false))
            or not validClass
            or not P.FiniteNumber(data.m) or data.m < 0
            or data.m > 9007199254740991
            or data.m ~= math.floor(data.m)
            or not ValidSummaryHash(data.h)
            or (data.lh ~= nil and not ValidSummaryHash(data.lh))
            or (data.n ~= nil and (not P.FiniteNumber(data.n)
                or data.n < 0 or data.n > maxBuildEchoes * 120
                or data.n ~= math.floor(data.n)))
            or (data.x ~= nil and data.x ~= 1) then
            return nil, "schema"
        end
        if not OwnerIdentityMatches(data.o, data.a) then
            return nil, "ownership"
        end
        return data
    end

    local function DpsEcho(echo)
        if type(echo) ~= "table" then return false end
        if not ScalarAliasesAgree(echo.spellId, echo.id)
            or not ScalarAliasesAgree(echo.count, echo.stacks)
            or not ScalarAliasesAgree(echo.count, echo.stack)
            or not ScalarAliasesAgree(echo.stacks, echo.stack) then
            return false
        end
        local spellId = echo.spellId
        if spellId == nil then spellId = echo.id end
        local stacks = echo.count
        if stacks == nil then stacks = echo.stacks end
        if stacks == nil then stacks = echo.stack end
        local quality = echo.quality
        local locked = echo.locked
        if locked ~= nil and locked ~= true and locked ~= false
            and locked ~= 0 and locked ~= 1 then return false end
        return P.FiniteNumber(spellId) and spellId >= 1
            and spellId <= 2147483647 and spellId == math.floor(spellId)
            and P.FiniteNumber(stacks) and stacks >= 1 and stacks <= 120
            and stacks == math.floor(stacks)
            and (quality == nil or (P.FiniteNumber(quality)
                and quality >= 0 and quality <= 255
                and quality == math.floor(quality))), stacks, spellId, quality,
            locked == true or locked == 1
    end

    local function DpsEchoList(echoes)
        if not DenseArray(echoes, maxBuildEchoes) then return false end
        local total = 0
        for index = 1, #echoes do
            local valid, stacks = DpsEcho(echoes[index])
            if not valid then return false end
            total = total + stacks
            if total > maxBuildEchoes then return false end
        end
        return true
    end

    local function DpsEchoAliasesAgree(compact, verbose)
        if compact == nil or verbose == nil then return true end
        if not DenseArray(compact, maxBuildEchoes)
            or not DenseArray(verbose, maxBuildEchoes)
            or #compact ~= #verbose then return false end
        for index = 1, #compact do
            local lv, ls, li, lq, ll = DpsEcho(compact[index])
            local rv, rs, ri, rq, rl = DpsEcho(verbose[index])
            if not lv or not rv or ls ~= rs or li ~= ri or lq ~= rq
                or ll ~= rl then
                return false
            end
        end
        return true
    end

    local function LowerText(value)
        return type(value) == "string" and value:lower() or nil
    end

    local function RealmText(value)
        return type(value) == "string"
            and value:lower():gsub("%s+", "") or nil
    end

    local function DpsAliasesAgree(data)
        return ScalarAliasesAgree(data.v, data.protocolVersion)
            and ScalarAliasesAgree(data.c, data.category)
            and ScalarAliasesAgree(data.d, data.dps)
            and ScalarAliasesAgree(data.u, data.duration)
            and ScalarAliasesAgree(data.t, data.ts)
            and ScalarAliasesAgree(data.p, data.player)
            and ScalarAliasesAgree(data.l, data.level)
            and ScalarAliasesAgree(data.k, data.class, LowerText)
            and ScalarAliasesAgree(data.o, data.ownerKey,
                canonicalOwnerKey)
            and ScalarAliasesAgree(data.r, data.realm, RealmText)
            and ScalarAliasesAgree(data.b, data.buildId)
            and ScalarAliasesAgree(data.f, data.fingerprint)
            and ScalarAliasesAgree(data.h, data.loadoutHash, LowerText)
            and DpsEchoAliasesAgree(data.e, data.echoes)
            and DpsEchoAliasesAgree(data.lk, data.lockedEchoes)
    end

    local unsupportedDpsAuthority = {
        claimedOwnerKey=true,relaySender=true,ownerVerified=true,isMine=true,
        importedSavedBuild=true,_originVerified=true,
    }

    local function Prefer(data, compact, verbose)
        local value = data[compact]
        if value == nil then value = data[verbose] end
        return value
    end

    function P.ValidateNetworkDpsPayload(data)
        if type(data) ~= "table" or not isSafeTree(data, 6, 2000) then
            return nil, "schema"
        end
        if not DpsAliasesAgree(data) then return nil, "schema" end
        for field in pairs(unsupportedDpsAuthority) do
            if data[field] ~= nil then return nil, "schema" end
        end
        local version = Prefer(data, "v", "protocolVersion")
        local category = Prefer(data, "c", "category")
        local dps = Prefer(data, "d", "dps")
        local duration = Prefer(data, "u", "duration")
        local stamp = Prefer(data, "t", "ts")
        local player = Prefer(data, "p", "player")
        local level = Prefer(data, "l", "level")
        local class = Prefer(data, "k", "class")
        local ownerKey = Prefer(data, "o", "ownerKey")
        local realm = Prefer(data, "r", "realm")
        local echoes = Prefer(data, "e", "echoes")
        local locked = Prefer(data, "lk", "lockedEchoes")
        local buildId = Prefer(data, "b", "buildId")
        local fingerprint = Prefer(data, "f", "fingerprint")
        local hash = Prefer(data, "h", "loadoutHash")
        if category ~= "dummy" and category ~= "lk" then
            return nil, "invalid_category"
        end
        if not P.FiniteNumber(version) or version < 1 or version > 255
            or version ~= math.floor(version)
            or not P.FiniteNumber(dps) or dps <= 0 or dps > 500000000
            or not P.FiniteNumber(duration) or duration < 0
            or not P.FiniteNumber(stamp) or stamp <= 0
            or stamp > 9007199254740991 or stamp ~= math.floor(stamp)
            or not P.ValidPeerName(player) or #player > 64
            or not P.FiniteNumber(level) or level < 1 or level > 80
            or level ~= math.floor(level)
            or not P.ValidField(class, 32, false)
            or (ownerKey ~= nil and not P.ValidField(ownerKey, 160, false))
            or not OwnerIdentityMatches(ownerKey, player)
            or (realm ~= nil and not P.ValidField(realm, 96, false))
            or (buildId ~= nil
                and not P.ValidIdentifier(buildId, maxBuildIdBytes))
            or (fingerprint ~= nil
                and not P.ValidField(fingerprint, 4096, false))
            or (hash ~= nil and not P.ValidHash(hash))
            or not DpsEchoList(echoes)
            or (locked ~= nil and not DpsEchoList(locked)) then
            return nil, "schema"
        end
        local context = data.x
        if context ~= nil and (type(context) ~= "table"
            or not P.ValidPeerName(context.n)
            or not P.ValidIdentifier(context.i, maxRequestIdBytes)
            or not P.FiniteNumber(context.b) or context.b < 1
            or context.b > bucketCount or context.b ~= math.floor(context.b)) then
            return nil, "schema"
        end
        return data
    end

    function P.SplitWire(text)
        local parts, start = {}, 1
        while true do
            if #parts >= maxWireFields then return nil end
            local position = text:find("|", start, true)
            if not position then
                parts[#parts + 1] = text:sub(start)
                return parts
            end
            parts[#parts + 1] = text:sub(start, position - 1)
            start = position + 1
        end
    end

    return P
end
