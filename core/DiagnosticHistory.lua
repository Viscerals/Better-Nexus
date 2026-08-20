-- Bounded, session-only diagnostic retention.
--
-- This module owns observations, never gameplay or transport work. A history
-- drops its oldest logical entry in O(1) and only rebuilds the backing array at
-- the configured trim threshold, so hot logs avoid shifting on every append.

Nexus = Nexus or {}

local DiagnosticHistory = {}
Nexus.DiagnosticHistory = DiagnosticHistory

local DEFAULT_CAP = 100
local DEFAULT_TEXT_BYTES = 2048
local DEFAULT_FIELDS = 32
local DEFAULT_DEPTH = 4

local function PositiveInteger(value, fallback)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge
        or number == -math.huge or number < 1 then
        return fallback
    end
    return math.floor(number)
end

function DiagnosticHistory.SafeText(value, maxBytes)
    maxBytes = PositiveInteger(maxBytes, DEFAULT_TEXT_BYTES)
    local ok, text = pcall(tostring, value)
    if not ok then text = "<unprintable:" .. type(value) .. ">" end
    text = tostring(text or ""):gsub("[%c]", " ")
    if #text > maxBytes then text = text:sub(1, maxBytes) end
    return text
end

function DiagnosticHistory.Format(maxBytes, formatText, ...)
    maxBytes = PositiveInteger(maxBytes, DEFAULT_TEXT_BYTES)
    local safeFormat = DiagnosticHistory.SafeText(formatText, maxBytes)
    local ok, text = pcall(string.format, safeFormat, ...)
    if not ok then text = safeFormat end
    return DiagnosticHistory.SafeText(text, maxBytes)
end

local function CopyValue(value, options, depth, seen)
    local kind = type(value)
    if kind == "string" then
        return DiagnosticHistory.SafeText(value, options.maxTextBytes)
    end
    if kind == "nil" or kind == "number" or kind == "boolean" then
        return value
    end
    if kind ~= "table" then
        return DiagnosticHistory.SafeText(value, options.maxTextBytes)
    end
    if seen[value] then return "<cycle>" end
    if depth >= options.maxDepth then return "<depth-limit>" end

    seen[value] = true
    local copy = {}
    local fields = 0
    for key, child in pairs(value) do
        fields = fields + 1
        if fields > options.maxFields then break end
        local keyKind = type(key)
        local copiedKey
        if keyKind == "number" or keyKind == "boolean" then
            copiedKey = key
        elseif keyKind == "string" then
            copiedKey = DiagnosticHistory.SafeText(key, 128)
        else
            copiedKey = DiagnosticHistory.SafeText(key, 128)
        end
        if copy[copiedKey] == nil then
            copy[copiedKey] = CopyValue(child, options, depth + 1, seen)
        end
    end
    seen[value] = nil
    return copy
end

local function DefensiveCopy(value, options)
    local ok, copy = pcall(CopyValue, value, options, 0, {})
    if ok then return copy end
    return DiagnosticHistory.SafeText(value, options.maxTextBytes)
end

function DiagnosticHistory.New(config)
    config = type(config) == "table" and config or {}
    local cap = PositiveInteger(config.cap, DEFAULT_CAP)
    local trimAt = PositiveInteger(config.trimAt, cap + math.max(1, math.floor(cap / 4)))
    if trimAt <= cap then trimAt = cap + 1 end

    local options = {
        maxTextBytes = PositiveInteger(config.maxTextBytes, DEFAULT_TEXT_BYTES),
        maxFields = PositiveInteger(config.maxFields, DEFAULT_FIELDS),
        maxDepth = PositiveInteger(config.maxDepth, DEFAULT_DEPTH),
    }
    local entries = {}
    local head, tail = 1, 0
    local appended, dropped, compactions = 0, 0, 0
    local history = {}

    local function Count()
        if tail < head then return 0 end
        return tail - head + 1
    end

    local function Compact()
        if head == 1 then return end
        local compacted = {}
        for index = head, tail do
            compacted[#compacted + 1] = entries[index]
        end
        entries = compacted
        head, tail = 1, #compacted
        compactions = compactions + 1
    end

    function history.Append(value)
        local copy = DefensiveCopy(value, options)
        tail = tail + 1
        entries[tail] = copy
        appended = appended + 1
        if Count() > cap then
            entries[head] = nil
            head = head + 1
            dropped = dropped + 1
        end
        if tail >= trimAt and head > 1 then Compact() end
        return true
    end

    function history.Snapshot()
        local snapshot = {}
        for index = head, tail do
            snapshot[#snapshot + 1] = DefensiveCopy(entries[index], options)
        end
        return snapshot
    end

    function history.Clear()
        entries = {}
        head, tail = 1, 0
        appended, dropped, compactions = 0, 0, 0
    end

    function history.Stats()
        return {
            cap = cap,
            trimAt = trimAt,
            maxTextBytes = options.maxTextBytes,
            retained = Count(),
            appended = appended,
            dropped = dropped,
            compactions = compactions,
        }
    end

    return history
end
