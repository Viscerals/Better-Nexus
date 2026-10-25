-- Nexus: core/Localization.lua
-- Issue #140 (parent #123), first slice (English only): the Nexus-owned presentation
-- seam for reviewed player-facing text. A caller asks for a stable semantic
-- key ("reason.save_in_progress") and gets text. This file reads no game
-- API, client locale, saved data or setting, and it prints, sends, schedules
-- or saves nothing. Its only state is the English base copied at load and
-- the fixed-size diagnostic record below.
--
-- Text/data contract, for the English base and for an injected candidate:
--  * key: a string of 3 to MAX_KEY_BYTES bytes made of two or more
--    dot-separated segments of lower-case letters, digits and "_", each
--    segment starting with a letter ("area.meaning"). A key names a
--    meaning; it is never made from English, player or game text.
--  * text: a Lua string of 1 to MAX_TEXT_BYTES bytes, well-formed UTF-8
--    (the shortest-form encoding of Unicode scalar values only; see
--    WellFormedUtf8), with at least one byte outside ASCII whitespace, no control
--    byte (0-31, 127) and no "|" (so no colour, link or texture escape).
--    Static text is shown exactly as stored; formatted meanings use the
--    named count-template grammar below.
--    Whitespace here means ASCII bytes 9-13 and 32, not Unicode White_Space,
--    grapheme or visibility classification. This is localized text, not an
--    identifier or user-authored identity: Identity.ValidDisplayText is a
--    different policy. Language punctuation, combining sequences, C1,
--    zero-width/bidi scalars and noncharacters are not newly excluded here.
--    No normalization is done; Unicode scalars retain their exact bytes.
--    Acceptance does not prove native glyph, font, locale or visibility
--    behavior.
--  * entries table: used only when it is a plain table without a
--    metatable. It is read with next/rawget, never through a metamethod,
--    and nothing in it is called.
--
-- English base: data/LocalizationEnglish.lua, loaded just before this file
-- by Nexus.toc, sets Nexus.LocalizationEnglish. Its valid entries are copied
-- once, here; a later change to that table changes nothing. An absent,
-- non-table or metatable base is not adopted: present=false, zero counts
-- (no entry count is invented). A plain base sets present=true; above
-- MAX_BASE_ENTRIES it adopts nothing, sets oversized=true and rejected to
-- the whole entry count. In an admitted plain base, invalid entries are
-- excluded and each is counted once as rejected.
--
-- L.Resolve(key, pack) -> text, source, reason. It never raises and records
-- nothing. In this order:
--  1. key outside the key contract -> UNAVAILABLE, "unavailable", "invalid_key"
--  A valid formatted key is checked next: UNAVAILABLE, "unavailable",
--     "format_requires_arguments"; it cannot resolve as static text.
--  2. key not in the English base  -> UNAVAILABLE, "unavailable", "unknown_key"
--  3. pack == nil                  -> English text, "base", nil
--  4. pack not a plain table (a pack name, number, boolean, function, or a
--     table with a metatable)      -> English text, "base", "unsupported_pack"
--  5. no entry for the key         -> English text, "base", "missing_candidate"
--  6. entry outside the text contract (not a string, empty, only ASCII whitespace,
--     control byte, "|", too long, malformed or non-scalar UTF-8)
--                                  -> English text, "base", "invalid_candidate"
--  7. otherwise                    -> the entry, "candidate", nil
-- A candidate can only replace a reviewed English key, never add one. There
-- is no language choice, preference or client-locale lookup: the English
-- base is the only real pack; a candidate is injected data (offline tests).
--
-- L.Text(key, pack) is Resolve plus the diagnostic record: each result with
-- a reason is counted by reason, and the first MAX_DIAGNOSTIC_KEYS distinct
-- invalid or unknown sanitized shown keys are kept. Once full, keysNotKept
-- counts each miss occurrence whose shown key is unkept, including repeats
-- of the ninth key; it does not count distinct unkept identities. The record
-- has a fixed size, is never printed to chat, and Diagnostics() returns a
-- programmatic copy; no diagnostic UI is added here.
--
-- Formatted meanings (issue #142). A code-owned schema (SCHEMAS below) names
-- a key's placeholder names; every current slot has the count type defined
-- below, never a translation-defined type. Its English
-- entry is a template under the same text contract, in which "{name}" is a
-- schema placeholder (each exactly once, in any order), "{{" and "}}" are a
-- literal brace and every other byte, "%" included, is literal. Anything else
-- ("{1}", "{name:d}", an unknown, missing or repeated name, a lone brace)
-- makes the template invalid. A formatted key is never static text: Resolve
-- and Text answer it with UNAVAILABLE, "unavailable",
-- "format_requires_arguments". L.Format(key, arguments, pack) -> text,
-- source, reason never raises and, like Text, records each reason:
--  1. key outside the key contract  -> UNAVAILABLE, "unavailable", "invalid_key"
--  2. a static text key             -> UNAVAILABLE, "unavailable", "wrong_key_kind"
--  3. no valid English template     -> UNAVAILABLE, "unavailable", "unknown_key"
--  4. arguments outside the schema  -> UNAVAILABLE, "unavailable", "invalid_arguments"
--  5. pack nil, not a plain table, without an entry or with an invalid
--     template -> the English template, same arguments, "base", and nil,
--     "unsupported_pack", "missing_candidate" or "invalid_candidate"
--  6. candidate output above the schema's result limit -> the English
--     template, same arguments, "base", "output_limit"
--  7. otherwise                     -> the candidate output, "candidate", nil
-- English output above the limit is UNAVAILABLE, "unavailable", "output_limit";
-- a result is never cut. Arguments: a plain table with exactly the schema's
-- names, each a plain record {known = true, value = N} (N a finite whole
-- number >= 0, shown with tostring) or {known = false} (shown as "?").
-- Substitution is one pass: an inserted value is never parsed again.

Nexus = Nexus or {}
local L = {}
Nexus.Localization = L

local MAX_KEY_BYTES = 64
local MAX_TEXT_BYTES = 256
local MAX_BASE_ENTRIES = 64
local MAX_DIAGNOSTIC_KEYS = 8
L.MAX_KEY_BYTES = MAX_KEY_BYTES
L.MAX_TEXT_BYTES = MAX_TEXT_BYTES
L.MAX_BASE_ENTRIES = MAX_BASE_ENTRIES
L.MAX_DIAGNOSTIC_KEYS = MAX_DIAGNOSTIC_KEYS

-- The documented safe status for a key without reviewed text: nonempty and
-- inside the text contract. Resolve returns this local, not the field.
local UNAVAILABLE = "This status cannot be shown right now."
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
    -- Byte-explicit ASCII whitespace, independent of pattern locale classes.
    if not text:find("[^\9-\13\32]") then return false end
    if text:find("[%z\1-\31\127|]") then return false end
    return WellFormedUtf8(text)
end

-- The same scalar-text check for the owned UserText presentation boundary.
-- This is not an identifier validator; it does not normalize Unicode.
function L.IsText(value) return ValidText(value) end

-- Code-owned schemas of the formatted meanings (issue #142). A schema, not a
-- translation, names each placeholder. All current slots have the same
-- typed known/unknown count contract (SlotText). A charge row is at most
-- MAX_TEXT_BYTES - 2 bytes, so the " ~" estimate marker its consumer may
-- append keeps the whole row within MAX_TEXT_BYTES.
local CHARGE_RESULT_LIMIT = MAX_TEXT_BYTES - 2
L.CHARGE_RESULT_LIMIT = CHARGE_RESULT_LIMIT
local SCHEMAS = {
    ["readout.charge_counts"] = {fields = {"banish", "reroll", "freeze"},
        resultLimit = CHARGE_RESULT_LIMIT},
}
for _, schema in pairs(SCHEMAS) do
    schema.index = {}
    for _, name in ipairs(schema.fields) do schema.index[name] = true end
end

-- A template under the text contract compiled to literal strings and
-- {field = name} parts, or nil (grammar above). One pass over at most
-- MAX_TEXT_BYTES bytes; braces are ASCII, so UTF-8 is split only between
-- characters.
local function CompileTemplate(text, schema)
    if not ValidText(text) then return nil end
    local parts, literal, seen, used = {}, {}, {}, 0
    local index, length = 1, #text
    while index <= length do
        local byte = text:byte(index)
        if byte == 123 then -- "{"
            if text:byte(index + 1) == 123 then
                literal[#literal + 1] = "{"
                index = index + 2
            else
                local close = text:find("}", index + 1, true)
                if not close then return nil end
                local name = text:sub(index + 1, close - 1)
                if not schema.index[name] or seen[name] then return nil end
                seen[name], used = true, used + 1
                if #literal > 0 then
                    parts[#parts + 1] = table.concat(literal)
                    literal = {}
                end
                parts[#parts + 1] = {field = name}
                index = close + 1
            end
        elseif byte == 125 then -- "}"
            if text:byte(index + 1) ~= 125 then return nil end
            literal[#literal + 1] = "}"
            index = index + 2
        else
            local stop = text:find("[{}]", index) or (length + 1)
            literal[#literal + 1] = text:sub(index, stop - 1)
            index = stop
        end
    end
    if used ~= #schema.fields then return nil end
    if #literal > 0 then parts[#parts + 1] = table.concat(literal) end
    return parts
end

-- The shown text of one argument slot, or nil. Only a plain record that is
-- exactly {known = true, value = N} (N a finite whole number >= 0, shown
-- with tostring) or exactly {known = false} (shown as "?") is admitted, and
-- at most three of its fields are looked at.
local function SlotText(slot)
    if type(slot) ~= "table" or getmetatable(slot) ~= nil then return nil end
    local fields, key = 0, next(slot)
    while key ~= nil do
        fields = fields + 1
        if fields > 2 then return nil end
        key = next(slot, key)
    end
    local known = rawget(slot, "known")
    if known == true then
        local value = rawget(slot, "value")
        if fields ~= 2 or type(value) ~= "number" or value ~= value or value < 0
            or value >= math.huge or value ~= math.floor(value) then return nil end
        return tostring(value)
    elseif known == false and fields == 1 then
        return "?"
    end
    return nil
end

-- The shown text of each placeholder, or nil unless the arguments are a
-- plain table holding exactly the schema's names, each a valid slot.
local function ArgumentValues(arguments, schema)
    if type(arguments) ~= "table" or getmetatable(arguments) ~= nil then return nil end
    local limit, fields, key = #schema.fields, 0, next(arguments)
    while key ~= nil do
        fields = fields + 1
        if fields > limit or not schema.index[key] then return nil end
        key = next(arguments, key)
    end
    if fields ~= limit then return nil end
    local values = {}
    for _, name in ipairs(schema.fields) do
        local shown = SlotText(rawget(arguments, name))
        if not shown then return nil end
        values[name] = shown
    end
    return values
end

-- One substitution pass; nil when the result is above the limit.
local function Render(parts, values, limit)
    local out = {}
    for index = 1, #parts do
        local part = parts[index]
        out[index] = type(part) == "table" and values[part.field] or part
    end
    local text = table.concat(out)
    if #text > limit then return nil end
    return text
end

-- The English base, copied once from the plain data table (see above). A key
-- with a schema is admitted only as a valid template, never as static text.
local base, baseKeys, templates = {}, {}, {}
local baseLoad = {present = false, accepted = 0, rejected = 0, oversized = false,
    formatted = 0}
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
                local schema = ValidKey(key) and SCHEMAS[key] or nil
                local parts = schema and CompileTemplate(text, schema) or nil
                if parts then
                    templates[key] = parts
                    baseKeys[#baseKeys + 1] = key
                    baseLoad.accepted = baseLoad.accepted + 1
                    baseLoad.formatted = baseLoad.formatted + 1
                elseif not schema and ValidKey(key) and ValidText(text) then
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
    if templates[key] ~= nil then return UNAVAILABLE, "unavailable", "format_requires_arguments" end
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

-- The fixed-size diagnostic record (see above). Local memory only.
local REASONS = {"invalid_key", "unknown_key", "unsupported_pack",
    "missing_candidate", "invalid_candidate", "format_requires_arguments",
    "wrong_key_kind", "invalid_arguments", "output_limit"}
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

-- The text a player-facing consumer shows: Resolve plus the record.
function L.Text(key, pack)
    local text, source, reason = Resolve(key, pack)
    if reason then Note(key, reason) end
    return text, source, reason
end

-- Formatted meanings: order and contract documented at the top of the file.
local function FormatResolve(key, arguments, pack)
    if not ValidKey(key) then return UNAVAILABLE, "unavailable", "invalid_key" end
    if base[key] ~= nil then return UNAVAILABLE, "unavailable", "wrong_key_kind" end
    local english, schema = templates[key], SCHEMAS[key]
    if english == nil or schema == nil then return UNAVAILABLE, "unavailable", "unknown_key" end
    local values = ArgumentValues(arguments, schema)
    if not values then return UNAVAILABLE, "unavailable", "invalid_arguments" end
    local reason
    if pack ~= nil then
        if type(pack) ~= "table" or getmetatable(pack) ~= nil then
            reason = "unsupported_pack"
        else
            local raw = rawget(pack, key)
            local parts = raw ~= nil and CompileTemplate(raw, schema) or nil
            if raw == nil then
                reason = "missing_candidate"
            elseif not parts then
                reason = "invalid_candidate"
            else
                local text = Render(parts, values, schema.resultLimit)
                if text then return text, "candidate", nil end
                reason = "output_limit"
            end
        end
    end
    local text = Render(english, values, schema.resultLimit)
    if text then return text, "base", reason end
    return UNAVAILABLE, "unavailable", "output_limit"
end

function L.Format(key, arguments, pack)
    local text, source, reason = FormatResolve(key, arguments, pack)
    if reason then Note(key, reason) end
    return text, source, reason
end

-- Whether the English base holds a reviewed text or template for the key.
function L.Has(key)
    return ValidKey(key) and (base[key] ~= nil or templates[key] ~= nil)
end

-- "text" for a reviewed static text, "format" for a template, else nil.
function L.Kind(key)
    if not ValidKey(key) then return nil end
    if base[key] ~= nil then return "text" end
    if templates[key] ~= nil then return "format" end
    return nil
end

-- The reviewed English keys of both kinds, sorted (a copy).
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
    return {
        base = {present = baseLoad.present, accepted = baseLoad.accepted,
            rejected = baseLoad.rejected, oversized = baseLoad.oversized,
            formatted = baseLoad.formatted},
        misses = diagnostics.misses, byReason = byReason, keys = keys,
        keysNotKept = diagnostics.keysNotKept, last = diagnostics.last,
    }
end
