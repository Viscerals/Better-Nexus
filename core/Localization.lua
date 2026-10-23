-- Nexus: core/Localization.lua
-- Issue #123: the one Nexus-owned presentation seam for reviewed
-- player-facing text. A caller asks for a stable semantic key
-- ("reason.save_in_progress") and gets text. This file reads no game API,
-- client locale, saved data or setting, and it prints, sends, schedules or
-- saves nothing. Its state is the English base and the optional packs copied
-- at load, the session's active language (set once, see below) and the
-- fixed-size diagnostic record below.
--
-- Text/data contract, for the English base and for an injected candidate:
--  * key: a string of 3 to MAX_KEY_BYTES bytes made of two or more
--    dot-separated segments of lower-case letters, digits and "_", each
--    segment starting with a letter ("area.meaning"). A key names a
--    meaning; it is never made from English, player or game text.
--  * text: a Lua string of 1 to MAX_TEXT_BYTES bytes, well-formed UTF-8
--    (the shortest-form encoding of Unicode scalar values only; see
--    WellFormedUtf8), with at least one non-space character, no control
--    byte (0-31, 127) and no "|" (so no colour, link or texture escape). It
--    is shown exactly as stored: no placeholder or formatting.
--  * entries table: used only when it is a plain table without a
--    metatable. It is read with next/rawget, never through a metamethod,
--    and nothing in it is called.
--
-- English base: data/LocalizationEnglish.lua, loaded just before this file
-- by Nexus.toc, sets Nexus.LocalizationEnglish. Its valid entries are copied
-- once, here; a later change to that table changes nothing. A base that is
-- absent, not a plain table or larger than MAX_BASE_ENTRIES is not used at
-- all; an invalid entry is left out. Both are counted in Diagnostics().base.
--
-- L.Resolve(key, pack) -> text, source, reason. It never raises and records
-- nothing. In this order:
--  1. key outside the key contract -> UNAVAILABLE, "unavailable", "invalid_key"
--  2. key not in the English base  -> UNAVAILABLE, "unavailable", "unknown_key"
--  3. pack == nil                  -> English text, "base", nil
--  4. pack not a plain table (a pack name, number, boolean, function, or a
--     table with a metatable)      -> English text, "base", "unsupported_pack"
--  5. no entry for the key         -> English text, "base", "missing_candidate"
--  6. entry outside the text contract (not a string, empty, only spaces,
--     control byte, "|", too long, malformed or non-scalar UTF-8)
--                                  -> English text, "base", "invalid_candidate"
--  7. otherwise                    -> the entry, "candidate", nil
-- A candidate can only replace a reviewed English key, never add one.
-- Resolve is pure: it reads only its arguments and the English base copied
-- at load, so Resolve(key) without a pack is always the English base,
-- whatever language is active.
--
-- Optional packs (data/LocalizationPacks.lua, loaded just before this file
-- by Nexus.toc). The language IDs are the Nexus preference enum of
-- data/DefaultProfile.lua (uiLanguages): Nexus presentation choices, not
-- client locales or GetLocale() values. The default ID is the English base;
-- every other ID names one pack. A pack is adopted only when it is a plain
-- table whose name (its autonym: the text contract, at most MAX_NAME_BYTES)
-- and plain entries table (at most MAX_BASE_ENTRIES entries) pass; an entry
-- is copied only when its key is a reviewed English key and its text passes
-- the text contract. Anything else is left out and counted in
-- Diagnostics().packs: a missing or invalid entry falls back to English for
-- its key, and a refused or absent pack is not offered. Packs are read with
-- next/rawget only and copied once, here; a later change to the data table
-- changes nothing.
--
-- Active language. core/MainLifecycle.lua calls InitializeActiveLanguage(id)
-- once per Lua session, after Store admission and before the ordinary UI is
-- initialized, with the saved preference. An ID without an adopted pack
-- (unknown, malformed or refused) gives English. Any later call returns the
-- language already active and changes nothing, so a changed preference
-- applies at the next reload or login. Until the call English is active.
--
-- L.Text(key, pack) is Resolve plus the diagnostic record: each result with
-- a reason is counted by reason, and the first MAX_DIAGNOSTIC_KEYS distinct
-- invalid or unknown keys are kept (a later one is only counted in
-- keysNotKept). The record has a fixed size, is never printed to chat, and
-- Diagnostics() returns a copy of it. CHANGED CONTRACT (issue #123): with
-- no pack, Text uses the active language's copied pack (none for English),
-- so an ordinary consumer such as core/UserText.lua shows the active
-- language. An explicit pack still decides alone, exactly as in Resolve.

Nexus = Nexus or {}
local L = {}
Nexus.Localization = L

local MAX_KEY_BYTES = 64
local MAX_TEXT_BYTES = 256
local MAX_BASE_ENTRIES = 64
local MAX_DIAGNOSTIC_KEYS = 8
local MAX_NAME_BYTES = 64
local MAX_LANGUAGES = 16
L.MAX_KEY_BYTES = MAX_KEY_BYTES
L.MAX_TEXT_BYTES = MAX_TEXT_BYTES
L.MAX_BASE_ENTRIES = MAX_BASE_ENTRIES
L.MAX_DIAGNOSTIC_KEYS = MAX_DIAGNOSTIC_KEYS
L.MAX_NAME_BYTES = MAX_NAME_BYTES

-- The documented safe status for a key without reviewed text: nonempty and
-- inside the text contract. Resolve returns this local, not the field.
local UNAVAILABLE = "This status cannot be shown right now. Check the diagnostics."
L.UNAVAILABLE = UNAVAILABLE

local function ValidKey(key)
    if type(key) ~= "string" then return false end
    local length = #key
    if length < 3 or length > MAX_KEY_BYTES then return false end
    if not key:find("^[a-z][a-z0-9_]*%.[a-z0-9_.]*[a-z0-9_]$") then return false end
    -- Every segment is nonempty and starts with a letter.
    return not key:find("%.[^a-z]")
end

-- UTF-8 as the text contract accepts it, checked byte by byte: only the
-- shortest-form encoding of a Unicode scalar value (U+0000..U+D7FF and
-- U+E000..U+10FFFF). An overlong form, a surrogate (U+D800..U+DFFF), a value
-- above U+10FFFF, an invalid lead byte, a stray continuation byte and a
-- truncated sequence are refused. The second byte's range depends on the
-- lead; every later continuation byte is 80..BF:
--   C2..DF -> 80..BF   E0 -> A0..BF   E1..EC -> 80..BF   ED -> 80..9F
--   EE..EF -> 80..BF   F0 -> 90..BF   F1..F3 -> 80..BF   F4 -> 80..8F
-- Noncharacters such as U+FFFF and U+10FFFF are scalar values and pass.
-- Nothing is normalized; the control-byte, "|", space and length rules are
-- ValidText's own, applied to the same bytes.
local function WellFormedUtf8(text)
    local index, length = 1, #text
    while index <= length do
        local byte = text:byte(index)
        local width, low, high
        if byte < 0x80 then width = 1
        elseif byte >= 0xC2 and byte <= 0xDF then width, low, high = 2, 0x80, 0xBF
        elseif byte == 0xE0 then width, low, high = 3, 0xA0, 0xBF
        elseif byte >= 0xE1 and byte <= 0xEC then width, low, high = 3, 0x80, 0xBF
        elseif byte == 0xED then width, low, high = 3, 0x80, 0x9F
        elseif byte == 0xEE or byte == 0xEF then width, low, high = 3, 0x80, 0xBF
        elseif byte == 0xF0 then width, low, high = 4, 0x90, 0xBF
        elseif byte >= 0xF1 and byte <= 0xF3 then width, low, high = 4, 0x80, 0xBF
        elseif byte == 0xF4 then width, low, high = 4, 0x80, 0x8F
        else return false end
        if index + width - 1 > length then return false end
        if width > 1 then
            local second = text:byte(index + 1)
            if second < low or second > high then return false end
            for offset = 2, width - 1 do
                local continuation = text:byte(index + offset)
                if continuation < 0x80 or continuation > 0xBF then return false end
            end
        end
        index = index + width
    end
    return true
end

local function ValidText(text)
    if type(text) ~= "string" then return false end
    local length = #text
    if length < 1 or length > MAX_TEXT_BYTES then return false end
    if not text:find("%S") then return false end
    if text:find("[%z\1-\31\127|]") then return false end
    return WellFormedUtf8(text)
end

-- The English base, copied once from the plain data table (see above).
local base, baseKeys = {}, {}
local baseLoad = {present = false, accepted = 0, rejected = 0, oversized = false}
do
    local source = Nexus.LocalizationEnglish
    if type(source) == "table" and getmetatable(source) == nil then
        baseLoad.present = true
        local count = 0
        for _ in next, source do count = count + 1 end
        if count > MAX_BASE_ENTRIES then
            baseLoad.oversized, baseLoad.rejected = true, count
        else
            for key, text in next, source do
                if ValidKey(key) and ValidText(text) then
                    base[key] = text
                    baseKeys[#baseKeys + 1] = key
                    baseLoad.accepted = baseLoad.accepted + 1
                else
                    baseLoad.rejected = baseLoad.rejected + 1
                end
            end
            table.sort(baseKeys)
        end
    end
end

local function Resolve(key, pack)
    if not ValidKey(key) then return UNAVAILABLE, "unavailable", "invalid_key" end
    local english = base[key]
    if english == nil then return UNAVAILABLE, "unavailable", "unknown_key" end
    if pack == nil then return english, "base", nil end
    if type(pack) ~= "table" or getmetatable(pack) ~= nil then
        return english, "base", "unsupported_pack"
    end
    local candidate = rawget(pack, key)
    if candidate == nil then return english, "base", "missing_candidate" end
    if not ValidText(candidate) then return english, "base", "invalid_candidate" end
    return candidate, "candidate", nil
end
L.Resolve = Resolve

-- The language IDs and the copied packs (see "Optional packs" above).
local DEFAULT_LANGUAGE = "enUS"
local ENGLISH_NAME = "English"
L.DEFAULT_LANGUAGE = DEFAULT_LANGUAGE
local languageIds = {DEFAULT_LANGUAGE}
local packs = {}
local packLoad = {present = false, adopted = 0, refused = 0, rows = {}}
do
    local profile = Nexus.DefaultProfile
    local enum = type(profile) == "table" and rawget(profile, "uiLanguages") or nil
    local ids = type(enum) == "table" and getmetatable(enum) == nil
        and rawget(enum, "ids") or nil
    local seen = {[DEFAULT_LANGUAGE] = true}
    if type(ids) == "table" and getmetatable(ids) == nil then
        for index = 1, MAX_LANGUAGES do
            local id = rawget(ids, index)
            if id == nil then break end
            if type(id) == "string" and id:find("^[a-z][a-z][A-Z][A-Z]$")
                and not seen[id] then
                seen[id] = true
                languageIds[#languageIds + 1] = id
            end
        end
    end
    local source = Nexus.LocalizationPacks
    if type(source) == "table" and getmetatable(source) == nil then
        packLoad.present = true
    else
        source = nil
    end
    for index = 2, #languageIds do
        local id = languageIds[index]
        local pack = source and rawget(source, id) or nil
        local plain = type(pack) == "table" and getmetatable(pack) == nil
        local name = plain and rawget(pack, "name") or nil
        local entries = plain and rawget(pack, "entries") or nil
        local count = 0
        if ValidText(name) and #name <= MAX_NAME_BYTES
            and type(entries) == "table" and getmetatable(entries) == nil then
            for _ in next, entries do count = count + 1 end
        else
            entries = nil
        end
        if entries and count <= MAX_BASE_ENTRIES then
            local copy, accepted = {}, 0
            for key, text in next, entries do
                if ValidKey(key) and base[key] ~= nil and ValidText(text) then
                    copy[key] = text
                    accepted = accepted + 1
                end
            end
            packs[id] = {name = name, entries = copy}
            packLoad.adopted = packLoad.adopted + 1
            packLoad.rows[#packLoad.rows + 1] = {id = id, accepted = accepted,
                rejected = count - accepted}
        else
            packLoad.refused = packLoad.refused + 1
        end
    end
end

-- The session's active language (see "Active language" above).
local active = {id = DEFAULT_LANGUAGE, entries = nil, initialized = false}

local function Available(id)
    return id == DEFAULT_LANGUAGE or (type(id) == "string" and packs[id] ~= nil)
end

-- The fixed-size diagnostic record (see above). Local memory only.
local REASONS = {"invalid_key", "unknown_key", "unsupported_pack",
    "missing_candidate", "invalid_candidate"}
local diagnostics = {misses = 0, byReason = {}, keys = {}, keysNotKept = 0, last = nil}
for _, reason in ipairs(REASONS) do diagnostics.byReason[reason] = 0 end

-- A key as it is kept: at most MAX_KEY_BYTES bytes of key characters, or
-- the type of a value that is not a string.
local function DiagnosticKey(key)
    if type(key) ~= "string" then return "<" .. type(key) .. ">" end
    return (key:sub(1, MAX_KEY_BYTES):gsub("[^%w_.%-]", "?"))
end

local function Note(key, reason)
    diagnostics.misses = diagnostics.misses + 1
    diagnostics.byReason[reason] = diagnostics.byReason[reason] + 1
    diagnostics.last = reason
    if reason ~= "invalid_key" and reason ~= "unknown_key" then return end
    local shown, keys = DiagnosticKey(key), diagnostics.keys
    for index = 1, #keys do
        if keys[index] == shown then return end
    end
    if #keys < MAX_DIAGNOSTIC_KEYS then
        keys[#keys + 1] = shown
    else
        diagnostics.keysNotKept = diagnostics.keysNotKept + 1
    end
end

-- The text a player-facing consumer shows: Resolve plus the record. Without
-- a pack it uses the active language's pack (see CHANGED CONTRACT above).
function L.Text(key, pack)
    if pack == nil then pack = active.entries end
    local text, source, reason = Resolve(key, pack)
    if reason then Note(key, reason) end
    return text, source, reason
end

-- Whether the English base holds a reviewed text for the key.
function L.Has(key)
    return ValidKey(key) and base[key] ~= nil
end

-- The reviewed English keys, sorted (a copy).
function L.Keys()
    local out = {}
    for index = 1, #baseKeys do out[index] = baseKeys[index] end
    return out
end

-- A copy of the base load facts and the diagnostic record.
function L.Diagnostics()
    local byReason, keys = {}, {}
    for _, reason in ipairs(REASONS) do byReason[reason] = diagnostics.byReason[reason] end
    for index = 1, #diagnostics.keys do keys[index] = diagnostics.keys[index] end
    local rows = {}
    for index, row in ipairs(packLoad.rows) do
        rows[index] = {id = row.id, accepted = row.accepted, rejected = row.rejected}
    end
    return {
        base = {present = baseLoad.present, accepted = baseLoad.accepted,
            rejected = baseLoad.rejected, oversized = baseLoad.oversized},
        packs = {present = packLoad.present, adopted = packLoad.adopted,
            refused = packLoad.refused, rows = rows},
        language = {active = active.id, initialized = active.initialized},
        misses = diagnostics.misses, byReason = byReason, keys = keys,
        keysNotKept = diagnostics.keysNotKept, last = diagnostics.last,
    }
end

-- The offered languages in enum order, English first: the default and each
-- adopted pack, as {id=, name=, available=true} copies. The name is the
-- language's own name. Reads only.
function L.Languages()
    local out = {}
    for _, id in ipairs(languageIds) do
        if id == DEFAULT_LANGUAGE then
            out[#out + 1] = {id = id, name = ENGLISH_NAME, available = true}
        elseif packs[id] then
            out[#out + 1] = {id = id, name = packs[id].name, available = true}
        end
    end
    return out
end

-- Whether a value is one of the enum IDs, adopted or not.
function L.IsLanguage(id)
    if type(id) ~= "string" then return false end
    for _, known in ipairs(languageIds) do
        if known == id then return true end
    end
    return false
end

-- The language a saved preference shows: the ID itself when it is the
-- default or an adopted pack, English otherwise. Pure: the saved value is
-- never rewritten.
function L.EffectiveLanguage(id)
    if Available(id) then return id end
    return DEFAULT_LANGUAGE
end

-- The active language ID, and whether it was initialized this session.
function L.ActiveLanguage()
    return active.id, active.initialized
end

-- Once per Lua session (see "Active language" above). Returns the active ID
-- and whether this call set it; a later call changes nothing.
function L.InitializeActiveLanguage(id)
    if active.initialized then return active.id, false end
    active.initialized = true
    if id ~= DEFAULT_LANGUAGE and Available(id) then
        active.id, active.entries = id, packs[id].entries
    end
    return active.id, true
end
