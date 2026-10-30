-- Nexus: core/Localization.lua
-- Issue #140 (parent #123), with the optional packs of issue #123: the one
-- Nexus-owned presentation seam for reviewed player-facing text. A caller
-- asks for a stable semantic key ("reason.save_in_progress") and gets text.
-- This file reads no game API, client locale, saved data or setting, and it
-- prints, sends, schedules or saves nothing. Its state is the English base
-- and the optional packs copied at load (draft text, pending fluent and
-- native review, for reviewed English keys only; a key without a valid pack
-- entry shows its English), the
-- session's active language (set once from the ID its caller supplies, see
-- below) and the fixed-size diagnostic record below.
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
--    Static text is shown exactly as stored: no placeholder or formatting.
--    Formatted meanings use the named count-template grammar below, whose
--    placeholders and typed counts are owned by a code schema, never by a
--    translation and never by printf-style formatting.
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
-- Declarations (issue #147): DECLARATIONS below is the code-owned registry
-- of every reviewed English meaning: its key, its kind ("text", or "format"
-- with its count fields in order, slot type and result limit) and so its
-- placeholders. Content is plain: the text contract above, never markup.
-- It is one literal table between two marker lines, so the offline tool
-- (tools/l10n_catalog.py parse_registry_declarations) reads exactly these
-- bytes without running them. At load each declaration is admitted only
-- when its key passes the key contract and it is exactly {kind = "text"} or
-- exactly {kind = "format", fields = {...}, slot = "count", resultLimit =
-- CHARGE_RESULT_LIMIT} with one or more distinct field names, or exactly
-- {kind = "block"} or a template declaration (see "Full-UI kinds" below);
-- any other declaration is left out. More than MAX_BASE_ENTRIES
-- declarations, or a value that is not a plain table, declares nothing
-- (fail closed). SCHEMAS is derived from the admitted format and template
-- declarations.
--
-- English base: data/LocalizationEnglish.lua, loaded just before this file
-- by Nexus.toc, sets Nexus.LocalizationEnglish. Its valid entries are copied
-- once, here; a later change to that table changes nothing. An absent,
-- non-table or metatable base is not adopted: present=false, zero counts
-- (no entry count is invented). A plain base sets present=true; above
-- MAX_BASE_ENTRIES it adopts nothing, sets oversized=true and rejected to
-- the whole entry count. In an admitted plain base, invalid entries are
-- excluded and each is counted once as rejected. An entry is admitted only
-- for a declared key and in its declared kind: a declared text as static
-- text, a declared format only as a valid template under its schema
-- (counted in both accepted and formatted), never as static text. An entry
-- whose key is not declared is rejected and also counted in undeclared
-- (complete English, issue #147). missingDeclared counts the declared
-- meanings left without admitted English (absent, invalid, or the whole base
-- refused); such a meaning resolves as an unknown key.
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
--     control byte, "|", too long, malformed or non-scalar UTF-8; a block key
--     uses the block contract of "Full-UI kinds")
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
-- is copied only when its key is a reviewed English static key and its text
-- passes the text contract, or its key holds an admitted English template
-- (issue #142) and its text compiles under that key's code-owned schema
-- (CompileTemplate). Anything else is left out and counted in
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
-- invalid or unknown sanitized shown keys are kept. Once full, keysNotKept
-- counts each miss occurrence whose shown key is unkept, including repeats
-- of the ninth key; it does not count distinct unkept identities. The record
-- has a fixed size, is never printed to chat, and Diagnostics() returns a
-- programmatic copy; no diagnostic UI is added here. That copy also holds
-- the base load facts (base.formatted counts the admitted templates, which
-- base.accepted also counts; base.undeclared and base.missingDeclared are
-- the declaration facts above), the copied-pack facts (packs.present,
-- adopted, refused and a row of id, accepted and rejected per adopted
-- pack) and the active-language facts (language.active, initialized).
-- CHANGED CONTRACT (issue #123): with no pack, Text uses the active
-- language's copied pack (none for English), so an ordinary consumer such as
-- core/UserText.lua shows the active language. An explicit pack still
-- decides alone, exactly as in Resolve.
--
-- Formatted meanings (issue #142). A code-owned schema (SCHEMAS below,
-- derived from DECLARATIONS) names a key's placeholder names; every current
-- slot has the count type defined
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
--  5. pack nil with no active pack (English active or not yet initialized),
--     pack not a plain table, without an entry or with an invalid template
--     -> the English template, same arguments, "base", and nil,
--     "unsupported_pack", "missing_candidate" or "invalid_candidate"
--  6. candidate output above the schema's result limit -> the English
--     template, same arguments, "base", "output_limit"
--  7. otherwise                     -> the candidate output, "candidate", nil
-- English output above the limit is UNAVAILABLE, "unavailable", "output_limit";
-- a result is never cut. Arguments: a plain table with exactly the schema's
-- names, each a plain record {known = true, value = N} (N a finite whole
-- number >= 0, shown with tostring) or {known = false} (shown as "?").
-- Substitution is one pass: an inserted value is never parsed again.
-- CHANGED CONTRACT (issue #142): as with Text, a nil pack selects the active
-- language's copied pack, which may hold a template copied at load, so an
-- ordinary consumer such as ui/Readout.lua shows the active language. An
-- explicit pack (including {} or an invalid candidate) still decides alone,
-- and Resolve and FormatResolve stay pure supplied-pack owners.
--
-- Full-UI kinds (issues #143-#148, full visible-UI scope). The "text" and
-- "format" rules above are unchanged. Two more declared kinds exist, and the
-- cap MAX_BASE_ENTRIES (declarations, English base and each pack) is the
-- bounded 4096 instead of the 64-entry pilot cap; above it the same
-- fail-closed rules apply.
--  * {kind = "block"}: one static meaning that needs several lines (a Help
--    or FAQ paragraph). The text contract with two differences: at most
--    MAX_BLOCK_BYTES bytes, and the line feed (byte 10) is allowed. Carriage
--    return, every other control byte and "|" stay refused. Resolve and Text
--    answer it exactly as static text; an English or candidate block that
--    fails this contract is refused or falls back exactly as text does.
--  * {kind = "template", fields = {...}, slots = {...}, resultLimit = N}
--    (optionally lines = true): a named template under the grammar above.
--    slots is a plain list as long as fields giving each field's code-owned
--    slot type: "count" (the typed count record above) or "text" (a Lua
--    string of at most MAX_SLOT_TEXT_BYTES bytes that the calling code
--    supplies: a name, a formatted number, a code-owned marker). A text slot
--    value is inserted verbatim in the one substitution pass and is never
--    parsed again, so a value may hold bytes a template may not (a player
--    name's escaped "||", a code-owned colour); a translation can never add
--    them. N is a whole number from 1 to MAX_TEMPLATE_RESULT_BYTES. Without
--    lines the template is single-line text (MAX_TEXT_BYTES); with
--    lines = true it follows the block contract. L.Format resolves it in the
--    order given for formats above, with its own result limit.
--  * L.Count(value) builds a count slot record from an observation:
--    {known = true, value = N} for a finite whole number N >= 0, otherwise
--    {known = false}. Unknown is never zero.
-- No plural, gender, date or number grammar exists: where English chooses
-- between two wordings (one copy, several copies) the calling code chooses
-- between two reviewed keys exactly as the English did.

Nexus = Nexus or {}
local L = {}
Nexus.Localization = L

local MAX_KEY_BYTES = 64
local MAX_TEXT_BYTES = 256
-- Full visible-UI scope (issues #143-#148): the cap bounds the declarations,
-- the English base and each pack. It was 64 for the pilot cohort; 4096 holds
-- the complete measured UI catalog with headroom and still fails closed
-- above it (see "Full-UI kinds" below).
local MAX_BASE_ENTRIES = 4096
local MAX_DIAGNOSTIC_KEYS = 8
local MAX_NAME_BYTES = 64
local MAX_LANGUAGES = 16
local MAX_BLOCK_BYTES = 1024
local MAX_TEMPLATE_RESULT_BYTES = 2048
local MAX_SLOT_TEXT_BYTES = 1024
L.MAX_KEY_BYTES = MAX_KEY_BYTES
L.MAX_TEXT_BYTES = MAX_TEXT_BYTES
L.MAX_BASE_ENTRIES = MAX_BASE_ENTRIES
L.MAX_DIAGNOSTIC_KEYS = MAX_DIAGNOSTIC_KEYS
L.MAX_NAME_BYTES = MAX_NAME_BYTES
L.MAX_BLOCK_BYTES = MAX_BLOCK_BYTES
L.MAX_TEMPLATE_RESULT_BYTES = MAX_TEMPLATE_RESULT_BYTES
L.MAX_SLOT_TEXT_BYTES = MAX_SLOT_TEXT_BYTES

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

-- A block (see "Full-UI kinds"): the text contract with MAX_BLOCK_BYTES and
-- one exception, the line feed (byte 10). Every other control byte, carriage
-- return included, and "|" stay refused.
local function ValidBlock(text)
    if type(text) ~= "string" then return false end
    local length = #text
    if length < 1 or length > MAX_BLOCK_BYTES then return false end
    if not text:find("[^\9-\13\32]") then return false end
    if text:find("[%z\1-\9\11-\31\127|]") then return false end
    return WellFormedUtf8(text)
end

-- Code-owned schemas of the formatted meanings (issue #142), derived from
-- the declarations below (issue #147). A schema, not a translation, names
-- each placeholder. All current slots have the same typed known/unknown
-- count contract (SlotText). A charge row is at most MAX_TEXT_BYTES - 2
-- bytes, so the " ~" estimate marker its consumer may append keeps the
-- whole row within MAX_TEXT_BYTES; a format declaration with any other
-- result limit is left out.
local CHARGE_RESULT_LIMIT = MAX_TEXT_BYTES - 2
L.CHARGE_RESULT_LIMIT = CHARGE_RESULT_LIMIT
local SLOT_TYPE = "count"

-- The declarations of every reviewed English meaning (see "Declarations"
-- above). Literal strings, whole numbers and plain tables only, between
-- the two marker lines; the key order follows data/LocalizationEnglish.lua.
-- NEXUS-L10N-REGISTRY BEGIN
local DECLARATIONS = {
    ["reason.save_in_progress"] = {kind = "text"},
    ["reason.list_preparing"] = {kind = "text"},
    ["reason.saved_data_reading"] = {kind = "text"},
    ["reason.wait_three_choices"] = {kind = "text"},
    ["reason.wait_pending_pick_count"] = {kind = "text"},
    ["readout.charge_counts"] = {fields = {"banish", "reroll", "freeze"},
        kind = "format", slot = "count", resultLimit = 254},
    ["panel.button.my_builds"] = {kind = "text"},
    ["panel.tooltip.open_my_builds"] = {kind = "text"},
    ["panel.tooltip.my_builds_destination"] = {kind = "text"},
    ["panel.button.assign_wishlist"] = {kind = "text"},
    ["panel.tooltip.assignment_heading"] = {kind = "text"},
    ["panel.tooltip.assignment_chooser"] = {kind = "text"},
    ["panel.button.create_wishlist"] = {kind = "text"},
    ["panel.tooltip.create_wishlist_heading"] = {kind = "text"},
    ["panel.tooltip.create_wishlist_source"] = {kind = "text"},
    ["panel.tooltip.create_wishlist_draft"] = {kind = "text"},
    ["panel.heading.locked_targets"] = {kind = "text"},
    ["panel.tooltip.locked_remaining"] = {kind = "text"},
    ["panel.tooltip.locked_plan"] = {kind = "text"},
    ["panel.tooltip.locked_acquire"] = {kind = "text"},
    ["panel.tooltip.locked_placement"] = {kind = "text"},
    ["panel.tooltip.locked_not_freeze"] = {kind = "text"},
    ["panel.tooltip.locked_acquire_list"] = {kind = "text"},
    ["panel.tooltip.open_wishlist_editor"] = {kind = "text"},
    ["panel.heading.progress"] = {kind = "text"},
    ["panel.heading.still_needed"] = {kind = "text"},
    ["panel.heading.extra_copies"] = {kind = "text"},
    ["panel.button.options"] = {kind = "text"},
}
-- NEXUS-L10N-REGISTRY END

-- The number of fields of a plain table, read with next only.
local function FieldCount(value)
    local count, key = 0, next(value)
    while key ~= nil do
        count = count + 1
        key = next(value, key)
    end
    return count
end

local function Plain(value)
    return type(value) == "table" and getmetatable(value) == nil
end

-- The schema of an admitted format declaration, or nil: exactly the four
-- fields kind, fields, slot and resultLimit; one or more distinct field
-- names, each a lower-case word of at most MAX_KEY_BYTES bytes, as a plain
-- list without holes; the count slot type; and CHARGE_RESULT_LIMIT.
local function FormatSchema(declaration)
    if FieldCount(declaration) ~= 4 or rawget(declaration, "slot") ~= SLOT_TYPE
        or rawget(declaration, "resultLimit") ~= CHARGE_RESULT_LIMIT then return nil end
    local fields = rawget(declaration, "fields")
    if not Plain(fields) then return nil end
    local count = FieldCount(fields)
    if count < 1 then return nil end
    local schema = {fields = {}, index = {}, slots = {}, resultLimit = CHARGE_RESULT_LIMIT}
    for index = 1, count do
        local name = rawget(fields, index)
        if type(name) ~= "string" or #name > MAX_KEY_BYTES or not name:find("^[a-z][a-z0-9_]*$")
            or schema.index[name] then return nil end
        schema.fields[index], schema.index[name], schema.slots[name] = name, true, SLOT_TYPE
    end
    return schema
end

-- The slot types a template field may declare (see "Full-UI kinds").
local TEMPLATE_SLOTS = {count = true, text = true}

-- The schema of an admitted template declaration, or nil: exactly kind,
-- fields, slots and resultLimit, and optionally lines = true; one or more
-- distinct field names as for a format; slots a plain list of the same
-- length naming each field's slot type; resultLimit a whole number from 1 to
-- MAX_TEMPLATE_RESULT_BYTES.
local function TemplateSchema(declaration)
    local lines = rawget(declaration, "lines")
    if lines ~= nil and lines ~= true then return nil end
    if FieldCount(declaration) ~= (lines and 5 or 4) then return nil end
    local limit, fields, slots = rawget(declaration, "resultLimit"), rawget(declaration, "fields"),
        rawget(declaration, "slots")
    if type(limit) ~= "number" or limit ~= math.floor(limit) or limit < 1
        or limit > MAX_TEMPLATE_RESULT_BYTES then return nil end
    if not Plain(fields) or not Plain(slots) then return nil end
    local count = FieldCount(fields)
    if count < 1 or FieldCount(slots) ~= count then return nil end
    local schema = {fields = {}, index = {}, slots = {}, resultLimit = limit, lines = lines == true}
    for index = 1, count do
        local name, slot = rawget(fields, index), rawget(slots, index)
        if type(name) ~= "string" or #name > MAX_KEY_BYTES or not name:find("^[a-z][a-z0-9_]*$")
            or schema.index[name] or type(slot) ~= "string" or not TEMPLATE_SLOTS[slot] then return nil end
        schema.fields[index], schema.index[name], schema.slots[name] = name, true, slot
    end
    return schema
end

-- The admitted declarations: declared[key] is "text", "block", "format" or
-- "template", and SCHEMAS[key] is the schema of each admitted format or
-- template declaration.
local declared, SCHEMAS, declaredCount = {}, {}, 0
if Plain(DECLARATIONS) and FieldCount(DECLARATIONS) <= MAX_BASE_ENTRIES then
    for key, declaration in next, DECLARATIONS do
        if ValidKey(key) and Plain(declaration) then
            local kind = rawget(declaration, "kind")
            if (kind == "text" or kind == "block") and FieldCount(declaration) == 1 then
                declared[key], declaredCount = kind, declaredCount + 1
            elseif kind == "template" then
                local schema = TemplateSchema(declaration)
                if schema then
                    declared[key], SCHEMAS[key], declaredCount = kind, schema, declaredCount + 1
                end
            elseif kind == "format" then
                local schema = FormatSchema(declaration)
                if schema then
                    declared[key], SCHEMAS[key], declaredCount = kind, schema, declaredCount + 1
                end
            end
        end
    end
end

-- A template under the text contract compiled to literal strings and
-- {field = name} parts, or nil (grammar above). One pass over at most
-- MAX_TEXT_BYTES bytes; braces are ASCII, so UTF-8 is split only between
-- characters.
local function CompileTemplate(text, schema)
    if schema.lines then
        if not ValidBlock(text) then return nil end
    elseif not ValidText(text) then
        return nil
    end
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

-- The shown text of one argument slot, or nil. A "text" slot admits a Lua
-- string of at most MAX_SLOT_TEXT_BYTES bytes, shown verbatim. A "count"
-- slot admits only a plain record that is exactly {known = true, value = N}
-- (N a finite whole number >= 0, shown with tostring) or exactly
-- {known = false} (shown as "?"), and at most three of its fields are
-- looked at.
local function SlotText(slot, slotType)
    if slotType == "text" then
        if type(slot) == "string" and #slot <= MAX_SLOT_TEXT_BYTES then return slot end
        return nil
    end
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
        local shown = SlotText(rawget(arguments, name), schema.slots[name])
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

-- The English base, copied once from the plain data table (see above). Only
-- a declared key is admitted, in its declared kind: a format key only as a
-- valid template, never as static text.
local base, baseKeys, templates = {}, {}, {}
local baseLoad = {present = false, accepted = 0, rejected = 0, oversized = false,
    formatted = 0, undeclared = 0, missingDeclared = 0}
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
                local kind = declared[key]
                local parts = SCHEMAS[key] and CompileTemplate(text, SCHEMAS[key]) or nil
                if parts then
                    templates[key] = parts
                    baseKeys[#baseKeys + 1] = key
                    baseLoad.accepted = baseLoad.accepted + 1
                    baseLoad.formatted = baseLoad.formatted + 1
                elseif (kind == "text" and ValidText(text)) or (kind == "block" and ValidBlock(text)) then
                    base[key] = text
                    baseKeys[#baseKeys + 1] = key
                    baseLoad.accepted = baseLoad.accepted + 1
                else
                    baseLoad.rejected = baseLoad.rejected + 1
                    if kind == nil then baseLoad.undeclared = baseLoad.undeclared + 1 end
                end
            end
            table.sort(baseKeys)
        end
    end
    -- Each declared key holds at most one admitted entry.
    baseLoad.missingDeclared = declaredCount - baseLoad.accepted
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
    if not (declared[key] == "block" and ValidBlock(candidate) or ValidText(candidate)) then
        return english, "base", "invalid_candidate"
    end
    return candidate, "candidate", nil
end
L.Resolve = Resolve

-- The language IDs and the copied packs (see "Optional packs" above).
local DEFAULT_LANGUAGE = "enUS"
local ENGLISH_NAME = "English"
L.DEFAULT_LANGUAGE = DEFAULT_LANGUAGE
-- Issue #141: the saved value of the Automatic preference, read from the
-- profile below. It is never a language ID and never a pack.
local AUTOMATIC = "automatic"
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
    -- Issue #141: the profile's Automatic value (uiLanguages.automatic)
    -- when it is a short lower-case word, so it can never match a language
    -- ID; "automatic" otherwise.
    local automatic = type(enum) == "table" and getmetatable(enum) == nil
        and rawget(enum, "automatic") or nil
    if type(automatic) == "string" and #automatic <= 32
        and automatic:find("^[a-z]+$") then
        AUTOMATIC = automatic
    end
    L.AUTOMATIC_PREFERENCE = AUTOMATIC
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
                -- Issue #142: a key holding an admitted English template is
                -- copied only as a template that compiles under its schema.
                local schema = ValidKey(key) and templates[key] ~= nil and SCHEMAS[key] or nil
                if schema then
                    if CompileTemplate(text, schema) then
                        copy[key] = text
                        accepted = accepted + 1
                    end
                elseif ValidKey(key) and base[key] ~= nil
                    and (declared[key] == "block" and ValidBlock(text) or ValidText(text)) then
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
-- Issue #141: `automatic` is true when this session started on the
-- Automatic preference (an absent or Automatic saved value).
local active = {id = DEFAULT_LANGUAGE, entries = nil, initialized = false,
    automatic = false}

local function Available(id)
    return id == DEFAULT_LANGUAGE or (type(id) == "string" and packs[id] ~= nil)
end

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

-- The text a player-facing consumer shows: Resolve plus the record. Without
-- a pack it uses the active language's pack (see CHANGED CONTRACT above).
function L.Text(key, pack)
    if pack == nil then pack = active.entries end
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

-- The row a player-facing consumer shows: FormatResolve plus the record.
-- Without a pack it uses the active language's pack, as Text does (see the
-- issue #142 CHANGED CONTRACT at the top of the file).
function L.Format(key, arguments, pack)
    if pack == nil then pack = active.entries end
    local text, source, reason = FormatResolve(key, arguments, pack)
    if reason then Note(key, reason) end
    return text, source, reason
end

-- The typed record of a "count" slot: {known = true, value = N} for a
-- finite whole number N >= 0, otherwise {known = false}. An absent or
-- invalid observation is unknown, never filled with 0. Pure.
function L.Count(value)
    if type(value) == "number" and value == value and value >= 0 and value < math.huge
        and value == math.floor(value) then
        return {known = true, value = value}
    end
    return {known = false}
end

-- Whether the English base holds a reviewed text or template for the key.
function L.Has(key)
    return ValidKey(key) and (base[key] ~= nil or templates[key] ~= nil)
end

-- The declared kind of a reviewed key: "text" or "block" for static text,
-- "format" or "template" for a template, else nil.
function L.Kind(key)
    if not ValidKey(key) then return nil end
    if base[key] ~= nil or templates[key] ~= nil then return declared[key] end
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
    local rows = {}
    for index, row in ipairs(packLoad.rows) do
        rows[index] = {id = row.id, accepted = row.accepted, rejected = row.rejected}
    end
    return {
        base = {present = baseLoad.present, accepted = baseLoad.accepted,
            rejected = baseLoad.rejected, oversized = baseLoad.oversized,
            formatted = baseLoad.formatted, undeclared = baseLoad.undeclared,
            missingDeclared = baseLoad.missingDeclared},
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

-- Issue #141: the Automatic preference. It is a preference, not a language:
-- Languages and IsLanguage never list it, and DEFAULT_LANGUAGE stays the
-- English fallback. A saved preference is Automatic when it is absent (nil)
-- or exactly the Automatic value (L.AUTOMATIC_PREFERENCE). Nothing else is
-- an alias of it.
function L.IsAutomaticPreference(value)
    return value == nil or value == AUTOMATIC
end

-- The pure Automatic resolver. Automatic may select an installed optional
-- pack only for an evidenced raw client code or alias. This build holds no
-- such evidence (no client code or alias is cited to an authorized versioned
-- reference) and reads no client locale, game API or saved data, so
-- production calls pass nothing and get English. `raw` and `mappings` exist
-- for deterministic synthetic tests only; injected facts prove this pure
-- function, not native automatic-language integration. A mapping is read
-- with getmetatable/rawget only (a table with a metatable is refused unread,
-- so no metamethod runs) and is never kept. Unknown or malformed input, no
-- mapping, and a target that is not an adopted pack (unsupported, missing
-- or refused) or is the English base give English. Never raises.
local function ResolveAutomatic(raw, mappings)
    if type(raw) ~= "string" or #raw < 1 or #raw > 32 then return DEFAULT_LANGUAGE end
    if type(mappings) ~= "table" or getmetatable(mappings) ~= nil then
        return DEFAULT_LANGUAGE
    end
    local target = rawget(mappings, raw)
    if type(target) == "string" and target ~= DEFAULT_LANGUAGE and packs[target] ~= nil then
        return target
    end
    return DEFAULT_LANGUAGE
end
L.ResolveAutomaticLanguage = ResolveAutomatic

-- The language a saved preference shows: the ID itself when it is the
-- default or an adopted pack, what Automatic resolves to (with this build's
-- evidence: English) for the Automatic preference, English otherwise. Pure:
-- the saved value is never rewritten.
function L.EffectiveLanguage(id)
    if id == nil or id == AUTOMATIC then return ResolveAutomatic() end
    if Available(id) then return id end
    return DEFAULT_LANGUAGE
end

-- The active language ID, whether it was initialized this session, and
-- whether this session started on the Automatic preference.
function L.ActiveLanguage()
    return active.id, active.initialized, active.automatic
end

-- Once per Lua session (see "Active language" above). Returns the active ID
-- and whether this call set it; a later call changes nothing. An absent or
-- Automatic preference starts Automatic, resolved without evidence: English.
function L.InitializeActiveLanguage(id)
    if active.initialized then return active.id, false end
    active.initialized = true
    if id == nil or id == AUTOMATIC then
        active.automatic = true
        id = ResolveAutomatic()
    end
    if id ~= DEFAULT_LANGUAGE and Available(id) then
        active.id, active.entries = id, packs[id].entries
    end
    return active.id, true
end
