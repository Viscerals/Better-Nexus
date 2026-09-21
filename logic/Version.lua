-- Pure deterministic semantic-version parsing and comparison for Lua 5.1.

Nexus = Nexus or {}
local Version = {}
Nexus.Version = Version

local MAX_VERSION_BYTES = 32
local MAX_COMPONENT = 2147483647

local function SplitIdentifiers(value, prerelease)
    if type(value) ~= "string" or value == ""
        or value:sub(1, 1) == "." or value:sub(-1) == "."
        or value:find("..", 1, true) then return nil end
    local out = {}
    for identifier in value:gmatch("([^.]+)") do
        if not identifier:match("^[%w%-]+$") then return nil end
        local numeric = identifier:match("^%d+$") ~= nil
        if prerelease and numeric and #identifier > 1
            and identifier:sub(1, 1) == "0" then return nil end
        out[#out + 1] = {
            text = identifier,
            numeric = numeric,
            value = numeric and tonumber(identifier) or nil,
        }
    end
    return #out > 0 and out or nil
end

local function ParseCore(value)
    if value == "" or value:sub(1, 1) == "." or value:sub(-1) == "."
        or value:find("..", 1, true) then return nil end
    local components = {}
    for component in value:gmatch("([^.]+)") do
        if not component:match("^%d+$")
            or (#component > 1 and component:sub(1, 1) == "0") then
            return nil
        end
        local number = tonumber(component)
        if not number or number > MAX_COMPONENT then return nil end
        components[#components + 1] = number
    end
    if #components < 1 or #components > 3 then return nil end
    while #components < 3 do components[#components + 1] = 0 end
    return components
end

function Version.Parse(value)
    if type(value) ~= "string" or value == "" or #value > MAX_VERSION_BYTES
        or value:find("%s") then return nil, "invalid version" end
    local raw = value
    if value:sub(1, 1) == "v" or value:sub(1, 1) == "V" then
        value = value:sub(2)
    end
    if value == "" then return nil, "missing version" end

    local buildText
    local plus = value:find("+", 1, true)
    if plus then
        if value:find("+", plus + 1, true) then return nil, "multiple build separators" end
        buildText = value:sub(plus + 1)
        value = value:sub(1, plus - 1)
    end

    local prereleaseText
    local dash = value:find("-", 1, true)
    if dash then
        prereleaseText = value:sub(dash + 1)
        value = value:sub(1, dash - 1)
    end

    local components = ParseCore(value)
    local prerelease = prereleaseText
        and SplitIdentifiers(prereleaseText, true) or nil
    local build = buildText and SplitIdentifiers(buildText, false) or nil
    if not components or (prereleaseText and not prerelease)
        or (buildText and not build) then return nil, "invalid version" end

    local normalized = string.format("%d.%d.%d",
        components[1], components[2], components[3])
    if prereleaseText then normalized = normalized .. "-" .. prereleaseText end
    if buildText then normalized = normalized .. "+" .. buildText end
    return {
        raw = raw,
        normalized = normalized,
        major = components[1], minor = components[2], patch = components[3],
        prerelease = prerelease, prereleaseText = prereleaseText,
        build = build, buildText = buildText,
        publishedCandidate = prerelease == nil and build == nil,
    }
end

local function Parsed(value)
    if type(value) == "table" and type(value.major) == "number" then return value end
    return Version.Parse(value)
end

function Version.Compare(left, right)
    left, right = Parsed(left), Parsed(right)
    if not left or not right then return nil, "invalid version" end
    for _, key in ipairs({ "major", "minor", "patch" }) do
        if left[key] < right[key] then return -1 end
        if left[key] > right[key] then return 1 end
    end
    if not left.prerelease and not right.prerelease then return 0 end
    if not left.prerelease then return 1 end
    if not right.prerelease then return -1 end
    local count = math.max(#left.prerelease, #right.prerelease)
    for i = 1, count do
        local a, b = left.prerelease[i], right.prerelease[i]
        if not a then return -1 end
        if not b then return 1 end
        if a.numeric and b.numeric then
            if a.value < b.value then return -1 end
            if a.value > b.value then return 1 end
        elseif a.numeric ~= b.numeric then
            return a.numeric and -1 or 1
        elseif a.text < b.text then
            return -1
        elseif a.text > b.text then
            return 1
        end
    end
    return 0
end

function Version.IsPublishedCandidate(value)
    local parsed = Parsed(value)
    return parsed ~= nil and parsed.publishedCandidate == true
end

function Version.MaxBytes()
    return MAX_VERSION_BYTES
end
