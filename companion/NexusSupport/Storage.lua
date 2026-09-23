-- NexusSupport: storage only.
--
-- This companion exists for ONE reason: WoW writes a SavedVariables file per
-- addon, so a report that a player can attach as a single small file needs its
-- own addon name. It has no gameplay logic, no frames, no events beyond its own
-- ADDON_LOADED, no dependency on Nexus, and it never reads or writes NexusDB.
-- Nexus runs normally when this component is missing or disabled; the copy
-- route stays available.
--
-- The file WoW creates is:
--   WTF/Account/<ACCOUNT>/SavedVariables/NexusSupport.lua
-- NOT the Interface/AddOns/NexusSupport/NexusSupport.lua that ships in the ZIP.
--
-- Two rules this file must not break:
--   1. It never assigns a default over saved data at load. A saved table is
--      adopted as it is found, and data this version does not understand is
--      kept untouched and reported as incompatible instead of being reset.
--   2. A report is replaced only when a COMPLETE one is handed over. A failed
--      or cancelled preparation leaves the previous report in place.

local FORMAT = 1
local MAX_CHUNK_BYTES = 8 * 1024
local MAX_TOTAL_BYTES = 1024 * 1024
local MAX_CHUNKS = 512

local Storage = {}
_G.NexusSupportStorage = Storage
Storage.FORMAT = FORMAT
Storage.MAX_CHUNK_BYTES = MAX_CHUNK_BYTES
Storage.MAX_TOTAL_BYTES = MAX_TOTAL_BYTES

local loaded = false
local incompatible = nil

local function db()
    return _G.NexusSupportDB
end

-- Adopt whatever is on disk. An empty variable becomes an empty container with
-- this format; a table from a version this file does not know is LEFT ALONE and
-- marked incompatible.
local function adopt()
    local saved = db()
    if saved == nil then
        _G.NexusSupportDB = {format = FORMAT}
        return true
    end
    if type(saved) ~= "table" then
        incompatible = "the saved value is not a table"
        return false
    end
    local savedFormat = tonumber(saved.format)
    if savedFormat == nil then
        -- Unknown shape: keep every byte of it and refuse to write, rather
        -- than deciding that somebody else's data was worthless.
        incompatible = "the saved data has no known format marker"
        return false
    end
    if savedFormat > FORMAT then
        incompatible = "the saved data was written by a newer version ("
            .. tostring(savedFormat) .. ")"
        return false
    end
    return true
end

local function scalar(value)
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then
        return value
    end
    return nil
end

-- A report is plain data or it is not stored: no frames, no functions, no
-- userdata, no cycles, no metatables.
local function validate(report)
    if type(report) ~= "table" then return nil, "report must be a table" end
    if getmetatable(report) ~= nil then return nil, "report carries a metatable" end
    local meta = report.meta
    if type(meta) ~= "table" then return nil, "report has no meta section" end
    local chunks = report.chunks
    if type(chunks) ~= "table" then return nil, "report has no chunks" end
    if #chunks < 1 then return nil, "report has no content" end
    if #chunks > MAX_CHUNKS then return nil, "report has too many chunks" end
    local out = {meta = {}, chunks = {}}
    for key, value in pairs(meta) do
        if type(key) == "string" then
            local kept = scalar(value)
            if kept == nil then return nil, "meta field is not a scalar: " .. key end
            out.meta[key] = kept
        end
    end
    local total = 0
    for index = 1, #chunks do
        local chunk = chunks[index]
        if type(chunk) ~= "string" then
            return nil, "chunk " .. index .. " is not text"
        end
        if #chunk > MAX_CHUNK_BYTES then
            return nil, "chunk " .. index .. " is larger than the supported "
                .. MAX_CHUNK_BYTES .. " bytes"
        end
        total = total + #chunk
        if total > MAX_TOTAL_BYTES then
            return nil, "the report is larger than the supported "
                .. MAX_TOTAL_BYTES .. " bytes"
        end
        out.chunks[index] = chunk
    end
    out.meta.chunkCount = #out.chunks
    out.meta.bytes = total
    out.meta.format = FORMAT
    return out
end

function Storage.Status()
    return {
        loaded = loaded,
        ready = loaded and incompatible == nil,
        incompatible = incompatible,
        format = FORMAT,
        hasReport = loaded and incompatible == nil
            and type(db()) == "table" and type(db().report) == "table" or false,
    }
end

-- The header only: enough to say which report is stored and how big it is,
-- without building its text again.
function Storage.Latest()
    if not loaded or incompatible then return nil end
    local saved = db()
    local report = type(saved) == "table" and saved.report or nil
    if type(report) ~= "table" or type(report.meta) ~= "table" then return nil end
    local header = {}
    for key, value in pairs(report.meta) do header[key] = value end
    return header
end

function Storage.Read()
    if not loaded or incompatible then return nil end
    local saved = db()
    local report = type(saved) == "table" and saved.report or nil
    if type(report) ~= "table" then return nil end
    local copy = {meta = {}, chunks = {}}
    for key, value in pairs(report.meta or {}) do copy.meta[key] = value end
    for index, chunk in ipairs(report.chunks or {}) do copy.chunks[index] = chunk end
    return copy
end

-- Replace the stored report with a COMPLETE one. The previous report stays
-- until this validates, so a failed preparation cannot leave half a report
-- behind or destroy the one the player already had.
function Storage.Replace(report)
    if not loaded then return nil, "the support component is not loaded" end
    if incompatible then return nil, "existing support data was left untouched: " .. incompatible end
    local validated, why = validate(report)
    if not validated then return nil, why end
    local saved = db()
    if type(saved) ~= "table" then return nil, "support storage is unavailable" end
    saved.format = FORMAT
    saved.report = validated
    return true, validated.meta
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, addon)
    if addon ~= "NexusSupport" then return end
    loaded = true
    adopt()
    frame:UnregisterEvent("ADDON_LOADED")
end)
