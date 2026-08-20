-- Bounded, non-recursive error retention. Diagnostic state only: this module
-- never authorizes or performs gameplay mutations.

Nexus = Nexus or {}
local Errors = {}
Nexus.Errors = Errors

local MAX_ENTRIES = 20
local MAX_SOURCE_BYTES = 64
local MAX_MESSAGE_BYTES = 2000
local recording = false

local function SafeText(value, fallback)
    if value == nil then return "nil" end
    if type(value) == "string" then
        if #value <= MAX_MESSAGE_BYTES then return value end
        return value:sub(1, MAX_MESSAGE_BYTES) .. "..."
    end
    local ok, text = pcall(tostring, value)
    if not ok or type(text) ~= "string" then
        return fallback or ("<unprintable " .. type(value) .. ">")
    end
    if #text > MAX_MESSAGE_BYTES then
        text = text:sub(1, MAX_MESSAGE_BYTES) .. "..."
    end
    return text
end

local function SourceText(value)
    if value == nil then return "unknown" end
    local text = SafeText(value, "unknown")
    text = text:gsub("[%c]", " ")
    if text == "" then text = "unknown" end
    if #text > MAX_SOURCE_BYTES then text = text:sub(1, MAX_SOURCE_BYTES) end
    return text
end

local function Timestamp(value, useCurrent)
    local number = tonumber(value)
    if number and number >= 0 then return number end
    if not useCurrent then return 0 end
    if type(time) == "function" then
        local ok, result = pcall(time)
        number = ok and tonumber(result) or nil
        if number and number >= 0 then return number end
    end
    if type(GetTime) == "function" then
        local ok, result = pcall(GetTime)
        number = ok and tonumber(result) or nil
        if number and number >= 0 then return number end
    end
    return 0
end

local function SanitizeEntry(entry)
    if type(entry) ~= "table" then return nil end
    local message = entry.message
    if message == nil then message = entry.error end
    if message == nil then return nil end
    return {
        timestamp = Timestamp(entry.timestamp or entry.t, false),
        source = SourceText(entry.source),
        message = SafeText(message, "<unprintable error>"),
    }
end

local function SanitizeHistory(value)
    local history = {}
    if type(value) == "table" then
        local indices = {}
        for key in pairs(value) do
            if type(key) == "number" and key >= 1 and key == math.floor(key) then
                indices[#indices + 1] = key
            end
        end
        table.sort(indices)
        for _, index in ipairs(indices) do
            local entry = SanitizeEntry(value[index])
            if entry then history[#history + 1] = entry end
        end
    end
    local first = math.max(1, #history - MAX_ENTRIES + 1)
    if first == 1 then return history end
    local trimmed = {}
    for i = first, #history do trimmed[#trimmed + 1] = history[i] end
    return trimmed
end

local function StoredHistory()
    if type(NexusDB) ~= "table" then return {} end
    return type(NexusDB.errorHistory) == "table" and NexusDB.errorHistory or {}
end

function Errors.Init()
    if recording then return false, "recursion blocked" end
    recording = true
    local ok, err = pcall(function()
        NexusDB = type(NexusDB) == "table" and NexusDB or {}
        NexusDB.errorHistory = SanitizeHistory(NexusDB.errorHistory)
        local latest = NexusDB.errorHistory[#NexusDB.errorHistory]
        if latest then Nexus.lastError = latest.message end
    end)
    recording = false
    if not ok then return false, SafeText(err, "error history initialization failed") end
    return true
end

function Errors.Record(source, value)
    if recording then return false, "recursion blocked" end
    recording = true
    local message = SafeText(value, "<unprintable error>")
    Nexus.lastError = message -- compatibility for existing integrations
    local ok, err = pcall(function()
        NexusDB = type(NexusDB) == "table" and NexusDB or {}
        local history = SanitizeHistory(NexusDB.errorHistory)
        history[#history + 1] = {
            timestamp = Timestamp(nil, true),
            source = SourceText(source),
            message = message,
        }
        while #history > MAX_ENTRIES do table.remove(history, 1) end
        NexusDB.errorHistory = history
    end)
    recording = false
    if not ok then return false, SafeText(err, "error history write failed") end
    return true
end

function Errors.History()
    if recording then return {} end
    local copy = {}
    recording = true
    local ok = pcall(function()
        local sanitized = SanitizeHistory(StoredHistory())
        for i, entry in ipairs(sanitized) do
            copy[i] = {
                timestamp = entry.timestamp,
                source = entry.source,
                message = entry.message,
            }
        end
    end)
    recording = false
    return ok and copy or {}
end

function Errors.Latest()
    local history = Errors.History()
    return history[#history]
end

function Errors.Clear()
    if recording then return false, "recursion blocked" end
    recording = true
    local ok, err = pcall(function()
        NexusDB = type(NexusDB) == "table" and NexusDB or {}
        NexusDB.errorHistory = {}
        Nexus.lastError = nil
    end)
    recording = false
    if not ok then return false, SafeText(err, "error history clear failed") end
    return true
end

function Errors.Format()
    local history = Errors.History()
    local out = { "ERRORS -- newest last (20 retained)", "" }
    if #history == 0 then
        out[#out + 1] = "(no errors recorded)"
    else
        for i, entry in ipairs(history) do
            out[#out + 1] = string.format("%02d  [%s] %s: %s", i,
                tostring(entry.timestamp), entry.source, entry.message)
        end
    end
    return table.concat(out, "\n")
end

function Errors.Limit()
    return MAX_ENTRIES
end

function Errors.SafeText(value)
    if recording then return "<unprintable " .. type(value) .. ">" end
    recording = true
    local text = SafeText(value, "<unprintable value>")
    recording = false
    return text
end
