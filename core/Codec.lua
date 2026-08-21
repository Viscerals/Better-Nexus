-- Nexus: core/Codec.lua
-- Self-contained base64 + minimal JSON encode/decode, adapted from
-- EbonBuilds' own ExportImport.lua (confirmed via direct inspection of
-- their source, 2026-07-24) -- same standard base64 alphabet, same
-- minimal JSON grammar. No external library dependency either way.
--
-- Used for two things: (1) our own sync wire format (peer-shared posted
-- builds), and (2) decoding a manually-pasted EbonBuilds export string,
-- since their format uses this exact same encoding.

Nexus = Nexus or {}
local Codec = {}
Nexus.Codec = Codec

------------------------------------------------------------------------
-- Base64
------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local MAX_ENCODED_BYTES = 98304
local MAX_DECODED_BYTES = 65536
local BASE64_CHUNK = 2000

function Codec.Base64Encode(data)
    local out = {}
    local len = #data
    for i = 1, len, 3 do
        local a, b, c = data:byte(i, i + 2)
        a, b, c = a or 0, b or 0, c or 0
        local n = a * 65536 + b * 256 + c
        out[#out + 1] = B64:byte(math.floor(n / 262144) + 1)
        out[#out + 1] = B64:byte(math.floor((n % 262144) / 4096) + 1)
        out[#out + 1] = i + 1 <= len and B64:byte(math.floor((n % 4096) / 64) + 1) or 61
        out[#out + 1] = i + 2 <= len and B64:byte(math.floor(n % 64) + 1) or 61
    end
    local chunks = {}
    for i = 1, #out, BASE64_CHUNK do
        chunks[#chunks + 1] = string.char(unpack(out, i, math.min(i + BASE64_CHUNK - 1, #out)))
    end
    return table.concat(chunks)
end

function Codec.Base64Decode(s)
    if type(s) ~= "string" or #s > MAX_ENCODED_BYTES or #s % 4 ~= 0 then return nil end
    if s == "" then return "" end
    if s:find("[^A-Za-z0-9+/=]") then return nil end
    local rev = {}
    for i = 1, #B64 do rev[B64:byte(i)] = i - 1 end
    rev[61] = 0
    local out = {}
    local len = #s
    for i = 1, len, 4 do
        local a = rev[s:byte(i)] or 0
        local b = rev[s:byte(i + 1)] or 0
        local c = rev[s:byte(i + 2)] or 0
        local d = rev[s:byte(i + 3)] or 0
        local n = a * 262144 + b * 4096 + c * 64 + d
        out[#out + 1] = string.char(math.floor(n / 65536))
        if s:byte(i + 2) ~= 61 then
            out[#out + 1] = string.char(math.floor((n % 65536) / 256))
        end
        if s:byte(i + 3) ~= 61 then
            out[#out + 1] = string.char(math.floor(n % 256))
        end
        if #out > MAX_DECODED_BYTES then return nil end
    end
    local decoded = table.concat(out)
    if #decoded > MAX_DECODED_BYTES then return nil end
    return decoded
end

-- Network payloads require one canonical spelling. Manual imports retain the
-- permissive decoder above for historical compatibility.
function Codec.Base64DecodeNetwork(s)
    local decoded = Codec.Base64Decode(s)
    if decoded == nil or Codec.Base64Encode(decoded) ~= s then return nil end
    return decoded
end

------------------------------------------------------------------------
-- Minimal JSON encoder
------------------------------------------------------------------------

local function IsArray(tbl)
    if type(tbl) ~= "table" then return false end
    local count, maxIdx = 0, 0
    for k in pairs(tbl) do
        if type(k) ~= "number" or k < 1 then return false end
        count = count + 1
        if k > maxIdx then maxIdx = k end
    end
    return count == maxIdx
end

function Codec.JSONEncode(value)
    local t = type(value)
    if t == "nil" then return "null"
    elseif t == "boolean" then return value and "true" or "false"
    elseif t == "number" then
        if value ~= value then return "null" end
        if value == math.huge or value == -math.huge then return "null" end
        return tostring(value)
    elseif t == "string" then
        local parts = {}
        for index = 1, #value do
            local byte = value:byte(index)
            if byte == 34 then parts[#parts + 1] = '\\"'
            elseif byte == 92 then parts[#parts + 1] = "\\\\"
            elseif byte == 8 then parts[#parts + 1] = "\\b"
            elseif byte == 9 then parts[#parts + 1] = "\\t"
            elseif byte == 10 then parts[#parts + 1] = "\\n"
            elseif byte == 12 then parts[#parts + 1] = "\\f"
            elseif byte == 13 then parts[#parts + 1] = "\\r"
            elseif byte < 32 then parts[#parts + 1] = string.format("\\u%04X", byte)
            else parts[#parts + 1] = string.char(byte) end
        end
        return '"' .. table.concat(parts) .. '"'
    elseif t == "table" then
        local parts = {}
        if IsArray(value) then
            for i = 1, #value do parts[#parts + 1] = Codec.JSONEncode(value[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            -- Lua table iteration is deliberately unspecified. Canonical key
            -- order keeps wire bytes, hashes, diagnostics, and migration
            -- snapshots stable across clients and reloads.
            local keys = {}
            for key, child in pairs(value) do
                if child ~= nil then keys[#keys + 1] = key end
            end
            table.sort(keys, function(left, right)
                local leftType, rightType = type(left), type(right)
                if leftType ~= rightType then return leftType < rightType end
                return tostring(left) < tostring(right)
            end)
            for _, k in ipairs(keys) do
                local v = value[k]
                if v ~= nil then
                    parts[#parts + 1] = Codec.JSONEncode(tostring(k)) .. ":" .. Codec.JSONEncode(v)
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

------------------------------------------------------------------------
-- Minimal JSON decoder
------------------------------------------------------------------------

local function SkipWhitespace(s, pos)
    while pos <= #s do
        local c = s:byte(pos)
        if c ~= 32 and c ~= 9 and c ~= 10 and c ~= 13 then break end
        pos = pos + 1
    end
    return pos
end

local function CodepointToUTF8(code)
    if not code then return "" end
    if code <= 0x7F then
        return string.char(code)
    elseif code <= 0x7FF then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + (code % 0x40))
    elseif code <= 0xFFFF then
        return string.char(
            0xE0 + math.floor(code / 0x1000),
            0x80 + (math.floor(code / 0x40) % 0x40),
            0x80 + (code % 0x40)
        )
    end
    return ""
end

local MAX_JSON_DEPTH = 12
local function ParseValue(s, pos, depth)
    depth = depth or 0
    if depth > MAX_JSON_DEPTH then return nil, pos end
    pos = SkipWhitespace(s, pos)
    if pos > #s then return nil, pos end
    local c = s:byte(pos)
    if c == 110 then return nil, pos + 4
    elseif c == 116 then return true, pos + 4
    elseif c == 102 then return false, pos + 5
    elseif c == 34 then
        local out = {}
        pos = pos + 1
        while pos <= #s do
            local cc = s:byte(pos)
            if cc == 34 then
                return table.concat(out), pos + 1
            elseif cc == 92 then
                pos = pos + 1
                local ec = s:byte(pos)
                if ec == 98 then out[#out + 1] = string.char(8)
                elseif ec == 102 then out[#out + 1] = string.char(12)
                elseif ec == 110 then out[#out + 1] = "\n"
                elseif ec == 114 then out[#out + 1] = "\r"
                elseif ec == 116 then out[#out + 1] = "\t"
                elseif ec == 92 then out[#out + 1] = "\\"
                elseif ec == 34 then out[#out + 1] = '"'
                elseif ec == 117 then
                    local hex = s:sub(pos + 1, pos + 4)
                    local code = hex:match("^%x%x%x%x$") and tonumber(hex, 16) or nil
                    if code then
                        out[#out + 1] = CodepointToUTF8(code)
                        pos = pos + 4
                    else
                        out[#out + 1] = "u"
                    end
                else out[#out + 1] = s:sub(pos, pos) end
            else
                out[#out + 1] = s:sub(pos, pos)
            end
            pos = pos + 1
        end
        return table.concat(out), pos
    elseif c == 91 then
        local arr = {}
        pos = pos + 1
        pos = SkipWhitespace(s, pos)
        if s:byte(pos) == 93 then return arr, pos + 1 end
        while true do
            if pos > #s then return arr, pos end
            local val
            val, pos = ParseValue(s, pos, depth + 1)
            arr[#arr + 1] = val
            pos = SkipWhitespace(s, pos)
            if s:byte(pos) == 93 then return arr, pos + 1 end
            pos = pos + 1
        end
    elseif c == 123 then
        local obj = {}
        pos = pos + 1
        pos = SkipWhitespace(s, pos)
        if s:byte(pos) == 125 then return obj, pos + 1 end
        while true do
            if pos > #s then return obj, pos end
            local key
            key, pos = ParseValue(s, pos, depth + 1)
            pos = SkipWhitespace(s, pos)
            pos = pos + 1
            local val
            val, pos = ParseValue(s, pos, depth + 1)
            if key ~= nil then
                if type(key) == "string" and key:match("^%-?%d+$") then
                    obj[tonumber(key)] = val
                else
                    obj[key] = val
                end
            end
            pos = SkipWhitespace(s, pos)
            if s:byte(pos) == 125 then return obj, pos + 1 end
            pos = pos + 1
        end
    else
        local startPos = pos
        if c == 45 then pos = pos + 1 end
        while pos <= #s do
            local nc = s:byte(pos)
            if nc >= 48 and nc <= 57 or nc == 46 or nc == 101 or nc == 69 or nc == 43 then
                pos = pos + 1
            else
                break
            end
        end
        return tonumber(s:sub(startPos, pos - 1)), pos
    end
end

function Codec.JSONDecode(s)
    if not s or s == "" then return nil end
    if #s > MAX_DECODED_BYTES then return nil end
    local ok, val = pcall(ParseValue, s, 1, 0)
    if not ok then return nil end
    return val
end

-- Strict network-only JSON grammar. The historical decoder remains available
-- to manual imports, while Sync rejects partial values and syntax recovery.
local function StrictJsonString(s, pos)
    if s:byte(pos) ~= 34 then return nil end
    local start = pos
    pos = pos + 1
    while pos <= #s do
        local byte = s:byte(pos)
        if byte == 34 then
            return pos + 1, Codec.JSONDecode(s:sub(start, pos))
        end
        if byte < 32 then return nil end
        if byte == 92 then
            pos = pos + 1
            local escaped = s:byte(pos)
            if escaped == 117 then
                local hex = s:sub(pos + 1, pos + 4)
                local code = hex:match("^%x%x%x%x$") and tonumber(hex, 16)
                    or nil
                if not code or (code >= 0xD800 and code <= 0xDFFF) then
                    return nil
                end
                pos = pos + 4
            elseif escaped ~= 34 and escaped ~= 47 and escaped ~= 92
                and escaped ~= 98 and escaped ~= 102 and escaped ~= 110
                and escaped ~= 114 and escaped ~= 116 then
                return nil
            end
        end
        pos = pos + 1
    end
    return nil
end

local function StrictJsonNumber(s, pos)
    local start = pos
    if s:byte(pos) == 45 then pos = pos + 1 end
    local first = s:byte(pos)
    if first == 48 then
        pos = pos + 1
        local nextByte = s:byte(pos)
        if nextByte and nextByte >= 48 and nextByte <= 57 then return nil end
    elseif first and first >= 49 and first <= 57 then
        repeat pos = pos + 1; first = s:byte(pos)
        until not first or first < 48 or first > 57
    else
        return nil
    end
    if s:byte(pos) == 46 then
        pos = pos + 1
        local digit = s:byte(pos)
        if not digit or digit < 48 or digit > 57 then return nil end
        repeat pos = pos + 1; digit = s:byte(pos)
        until not digit or digit < 48 or digit > 57
    end
    local exponent = s:byte(pos)
    if exponent == 69 or exponent == 101 then
        pos = pos + 1
        local sign = s:byte(pos)
        if sign == 43 or sign == 45 then pos = pos + 1 end
        local digit = s:byte(pos)
        if not digit or digit < 48 or digit > 57 then return nil end
        repeat pos = pos + 1; digit = s:byte(pos)
        until not digit or digit < 48 or digit > 57
    end
    local number = tonumber(s:sub(start, pos - 1))
    if type(number) ~= "number" or number ~= number
        or number == math.huge or number == -math.huge then return nil end
    return pos, number
end

local StrictJsonValue
StrictJsonValue = function(s, pos, depth, state)
    if depth > MAX_JSON_DEPTH or state.nodes >= state.maxNodes then return nil end
    state.nodes = state.nodes + 1
    pos = SkipWhitespace(s, pos)
    local byte = s:byte(pos)
    if byte == 34 then
        local nextPos, value = StrictJsonString(s, pos)
        return nextPos, value, nextPos ~= nil
    end
    if byte == 45 or (byte and byte >= 48 and byte <= 57) then
        local nextPos, value = StrictJsonNumber(s, pos)
        return nextPos, value, nextPos ~= nil
    end
    if s:sub(pos, pos + 3) == "true" then return pos + 4, true, true end
    if s:sub(pos, pos + 4) == "false" then return pos + 5, false, true end
    if s:sub(pos, pos + 3) == "null" then
        state.hasNull = true
        return pos + 4, nil, true
    end
    if byte == 91 then
        local array = {}
        pos = SkipWhitespace(s, pos + 1)
        if s:byte(pos) == 93 then return pos + 1, array, true end
        while true do
            local value, ok
            pos, value, ok = StrictJsonValue(s, pos, depth + 1, state)
            if not ok then return nil end
            array[#array + 1] = value
            pos = SkipWhitespace(s, pos)
            if s:byte(pos) == 93 then return pos + 1, array, true end
            if s:byte(pos) ~= 44 then return nil end
            pos = SkipWhitespace(s, pos + 1)
        end
    end
    if byte == 123 then
        local keys = {}
        local object = {}
        pos = SkipWhitespace(s, pos + 1)
        if s:byte(pos) == 125 then return pos + 1, object, true end
        while true do
            local key
            pos, key = StrictJsonString(s, pos)
            if not pos then return nil end
            if type(key) ~= "string" or keys[key] then return nil end
            keys[key] = true
            pos = SkipWhitespace(s, pos)
            if s:byte(pos) ~= 58 then return nil end
            local value, ok
            pos, value, ok = StrictJsonValue(s, pos + 1, depth + 1, state)
            if not ok then return nil end
            object[key] = value
            pos = SkipWhitespace(s, pos)
            if s:byte(pos) == 125 then return pos + 1, object, true end
            if s:byte(pos) ~= 44 then return nil end
            pos = SkipWhitespace(s, pos + 1)
        end
    end
    return nil
end

function Codec.JSONDecodeNetwork(s, maxNodes)
    if type(s) ~= "string" or s == "" or #s > MAX_DECODED_BYTES then
        return nil
    end
    local state = {nodes=0,maxNodes=tonumber(maxNodes) or 4000}
    local finish, value, ok = StrictJsonValue(s, 1, 0, state)
    if not ok or state.hasNull or SkipWhitespace(s, finish) <= #s then
        return nil
    end
    return value
end

------------------------------------------------------------------------
-- Safety check for decoded trees (bounded depth/breadth so a malicious
-- or corrupted payload from a peer can't hang the client)
------------------------------------------------------------------------

function Codec.IsSafeTree(root, maxDepth, maxNodes)
    maxDepth = maxDepth or 8
    maxNodes = maxNodes or 5000
    local nodes = 0
    local function Visit(value, depth)
        nodes = nodes + 1
        if nodes > maxNodes or depth > maxDepth then return false end
        local kind = type(value)
        if kind ~= "table" then
            return kind == "nil" or kind == "boolean" or kind == "number" or kind == "string"
        end
        for key, child in pairs(value) do
            if type(key) ~= "number" and type(key) ~= "string" then return false end
            if not Visit(child, depth + 1) then return false end
        end
        return true
    end
    local ok, result = pcall(Visit, root, 0)
    return ok and result
end

------------------------------------------------------------------------
-- EBH1 wishlist string format (reverse-engineered from live exports via
-- the server's native ImportEchoLoadout/export feature):
--   EBH1:<spellId>.<quality>.<stacks>,<spellId>.<quality>.<stacks>,...:<CLASS>:<Name>
-- The entry list has no colons in it (only digits, dots, commas), so the
-- first remaining colon after the entries is unambiguously the class
-- separator, and everything after the second is the name (which may itself
-- contain characters but not a leading colon in practice).
--
-- Three-component entries are the established EBH1 shape. Nexus uses one
-- deliberately scoped four-component extension (a trailing ".1") to preserve
-- a locked-role tag across its own export/import round trip. We do not claim
-- that the server's native importer understands that Nexus-only extension.
------------------------------------------------------------------------

function Codec.EncodeEBH1(entries, classToken, name)
    local parts = {}
    for _, e in ipairs(entries or {}) do
        local id = tonumber(e and e.spellId)
        if id then
            local base = string.format("%d.%d.%d", id,
                tonumber(e.quality) or 0, math.max(1, tonumber(e.stacks) or 1))
            parts[#parts + 1] = e.locked and (base .. ".1") or base
        end
    end
    return "EBH1:" .. table.concat(parts, ",") .. ":" .. tostring(classToken or "")
        .. ":" .. tostring(name or "")
end

function Codec.DecodeEBH1(str)
    if type(str) ~= "string" then return nil end
    if #str == 0 or #str > 8192 or str:find("[%c]") then return nil end
    str = str:match("^%s*(.-)%s*$") or ""
    if #str == 0 then return nil end
    local body, class, name = str:match("^EBH1:([^:]*):([^:]*):(.*)$")
    if not body or body == "" or #class > 32 or #name > 120 then return nil end
    local validClass = class == "" or class == "UNKNOWN"
        or class == "WARRIOR" or class == "PALADIN"
        or class == "HUNTER" or class == "ROGUE"
        or class == "PRIEST" or class == "DEATHKNIGHT"
        or class == "SHAMAN" or class == "MAGE"
        or class == "WARLOCK" or class == "DRUID"
    if not validClass or class:find("[%c|]") or name:find("[%c]")
        or body:sub(1, 1) == "," or body:sub(-1) == ","
        or body:find(",,", 1, true) then return nil end

    local entries, ordinarySeen = {}, {}
    local ordinaryTotal, lockedCount = 0, 0
    for chunk in body:gmatch("[^,]+") do
        local id, quality, stacks, marker =
            chunk:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
        local locked = marker ~= nil
        if not id then
            id, quality, stacks = chunk:match("^(%d+)%.(%d+)%.(%d+)$")
        end
        if not id or (locked and marker ~= "1") then return nil end
        id, quality, stacks = tonumber(id), tonumber(quality), tonumber(stacks)
        if not id or id < 1 or id > 2147483647
            or not quality or quality < 0 or quality > 255
            or not stacks or stacks < 1 or stacks > 120 then return nil end
        if locked then
            lockedCount = lockedCount + stacks
            if lockedCount > 6 then return nil end
        else
            if ordinarySeen[id] then return nil end
            ordinarySeen[id] = true
            ordinaryTotal = ordinaryTotal + stacks
            if ordinaryTotal > 79 then return nil end
        end
        entries[#entries + 1] = {
            spellId=id,quality=quality,stacks=stacks,
            locked=locked and true or nil,
        }
        if #entries > 85 then return nil end
    end
    if #entries == 0 then return nil end
    return { entries = entries, class = class, name = name }
end
