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
    -- NEXUS-L10N-FULL-UI BEGIN (generated from reviewed fragments; see header)
    -- chat (160)
    ["command.chat.anchor_cleared"] = {kind = "text"},
    ["command.chat.anchor_cleared_session"] = {kind = "text"},
    ["command.chat.anchor_set"] = {kind = "template", fields = {"spell"}, slots = {"text"}, resultLimit = 154},
    ["command.chat.anchor_set_session"] = {kind = "template", fields = {"spell"}, slots = {"text"}, resultLimit = 288},
    ["command.chat.auto_accept_restored"] = {kind = "text"},
    ["command.chat.auto_blocked_by_orb"] = {kind = "text"},
    ["command.chat.auto_blocked_by_pause"] = {kind = "text"},
    ["command.chat.automation_off"] = {kind = "text"},
    ["command.chat.automation_on"] = {kind = "text"},
    ["command.chat.builds_unavailable"] = {kind = "text"},
    ["command.chat.current_locks_off"] = {kind = "text"},
    ["command.chat.current_locks_on"] = {kind = "text"},
    ["command.chat.dps_active"] = {kind = "text"},
    ["command.chat.dps_current_key"] = {kind = "template", fields = {"key"}, slots = {"text"}, resultLimit = 372},
    ["command.chat.dps_details_missing"] = {kind = "text"},
    ["command.chat.dps_install_details"] = {kind = "text"},
    ["command.chat.dps_last_session"] = {kind = "template", fields = {"note"}, slots = {"text"}, resultLimit = 2048},
    ["command.chat.dps_log_hint"] = {kind = "text"},
    ["command.chat.dps_module_missing"] = {kind = "text"},
    ["command.chat.dps_record_hint"] = {kind = "text"},
    ["command.chat.dps_selected_key"] = {kind = "template", fields = {"key"}, slots = {"text"}, resultLimit = 366},
    ["command.chat.editor_unavailable"] = {kind = "text"},
    ["command.chat.guide_not_opened"] = {kind = "text"},
    ["command.chat.guide_opened"] = {kind = "text"},
    ["command.chat.help_not_opened"] = {kind = "text"},
    ["command.chat.help_opened"] = {kind = "text"},
    ["command.chat.help_unavailable"] = {kind = "text"},
    ["command.chat.leaderboard_unavailable"] = {kind = "text"},
    ["command.chat.legacy_already_preserved"] = {kind = "text"},
    ["command.chat.legacy_blocked"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1400},
    ["command.chat.legacy_current_code"] = {kind = "text"},
    ["command.chat.legacy_input_drift"] = {kind = "text"},
    ["command.chat.legacy_not_changed"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 900},
    ["command.chat.legacy_not_waiting"] = {kind = "text"},
    ["command.chat.legacy_offer_confirm"] = {kind = "template", fields = {"command"}, slots = {"text"}, resultLimit = 252},
    ["command.chat.legacy_offer_effect"] = {kind = "text"},
    ["command.chat.legacy_offer_found"] = {kind = "text"},
    ["command.chat.legacy_offer_reload"] = {kind = "text"},
    ["command.chat.legacy_offer_size"] = {kind = "template", fields = {"tables", "bytes", "code"}, slots = {"text", "text", "text"}, resultLimit = 252},
    ["command.chat.legacy_preserved_code"] = {kind = "template", fields = {"code"}, slots = {"text"}, resultLimit = 348},
    ["command.chat.legacy_preserved_reload"] = {kind = "text"},
    ["command.chat.legacy_rollback_incomplete"] = {kind = "text"},
    ["command.chat.legacy_usage"] = {kind = "text"},
    ["command.chat.legacy_waiting"] = {kind = "text"},
    ["command.chat.log_viewer_unavailable"] = {kind = "text"},
    ["command.chat.logclear_done"] = {kind = "text"},
    ["command.chat.logclear_failed"] = {kind = "text"},
    ["command.chat.nameplate_active"] = {kind = "text"},
    ["command.chat.nameplate_missing"] = {kind = "text"},
    ["command.chat.nameplate_tagging"] = {kind = "text"},
    ["command.chat.not_initialized"] = {kind = "text"},
    ["command.chat.nothing_to_restore"] = {kind = "text"},
    ["command.chat.overlay_unavailable"] = {kind = "text"},
    ["command.chat.pause_already"] = {kind = "text"},
    ["command.chat.pause_started"] = {kind = "text"},
    ["command.chat.pause_status_paused"] = {kind = "text"},
    ["command.chat.pause_status_running"] = {kind = "text"},
    ["command.chat.pause_unavailable"] = {kind = "text"},
    ["command.chat.performance_unavailable"] = {kind = "text"},
    ["command.chat.policy_selected"] = {kind = "template", fields = {"strategy"}, slots = {"text"}, resultLimit = 310},
    ["command.chat.policy_values"] = {kind = "text"},
    ["command.chat.progress_no_wishlist"] = {kind = "text"},
    ["command.chat.progress_this_run"] = {kind = "template", fields = {"progress", "percent", "short"}, slots = {"text", "text", "count"}, resultLimit = 198},
    ["command.chat.prototype_backup"] = {kind = "text"},
    ["command.chat.prototype_intro"] = {kind = "text"},
    ["command.chat.reference_commands"] = {kind = "template", fields = {"commands"}, slots = {"text"}, resultLimit = 226},
    ["command.chat.reference_rolling_permissions"] = {kind = "template", fields = {"reroll", "freeze"}, slots = {"text", "text"}, resultLimit = 258},
    ["command.chat.reference_rolling_strategy"] = {kind = "template", fields = {"policy", "trace"}, slots = {"text", "text"}, resultLimit = 216},
    ["command.chat.reference_session_pause"] = {kind = "text"},
    ["command.chat.report_view_missing"] = {kind = "text"},
    ["command.chat.resume_done"] = {kind = "text"},
    ["command.chat.resume_not_paused"] = {kind = "text"},
    ["command.chat.roll_recording_off"] = {kind = "template", fields = {"saved", "limit", "failed", "dropped"}, slots = {"text", "text", "text", "text"}, resultLimit = 254},
    ["command.chat.roll_recording_on"] = {kind = "template", fields = {"saved", "limit", "failed", "dropped"}, slots = {"text", "text", "text", "text"}, resultLimit = 278},
    ["command.chat.rolling_last_decision"] = {kind = "template", fields = {"policy"}, slots = {"text"}, resultLimit = 192},
    ["command.chat.rolling_last_decision_fallback"] = {kind = "template", fields = {"policy", "reason"}, slots = {"text", "text"}, resultLimit = 394},
    ["command.chat.rolling_option_usage"] = {kind = "template", fields = {"reroll", "freeze", "currentlocks"}, slots = {"text", "text", "text"}, resultLimit = 190},
    ["command.chat.rolling_permission"] = {kind = "template", fields = {"option", "value"}, slots = {"text", "text"}, resultLimit = 198},
    ["command.chat.rolling_strategy"] = {kind = "template", fields = {"strategy"}, slots = {"text"}, resultLimit = 132},
    ["command.chat.rolling_strategy_pending"] = {kind = "template", fields = {"strategy", "selected"}, slots = {"text", "text"}, resultLimit = 274},
    ["command.chat.session_only_note"] = {kind = "text"},
    ["command.chat.startup_preparing"] = {kind = "text"},
    ["command.chat.startup_stopped"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1200},
    ["command.chat.status_activation_candidate"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 222},
    ["command.chat.status_active_desired_plan"] = {kind = "template", fields = {"slot", "name", "count"}, slots = {"text", "text", "count"}, resultLimit = 2048},
    ["command.chat.status_active_none"] = {kind = "text"},
    ["command.chat.status_active_saved_build"] = {kind = "template", fields = {"slot", "name", "count"}, slots = {"text", "text", "count"}, resultLimit = 2048},
    ["command.chat.status_loadouts_waiting"] = {kind = "text"},
    ["command.chat.status_no_saved_build"] = {kind = "text"},
    ["command.chat.status_readable"] = {kind = "template", fields = {"saved", "plans"}, slots = {"count", "count"}, resultLimit = 212},
    ["command.chat.status_shared_failed"] = {kind = "text"},
    ["command.chat.status_shared_preparing"] = {kind = "text"},
    ["command.chat.status_version_auto_off"] = {kind = "template", fields = {"version", "build", "level"}, slots = {"text", "text", "text"}, resultLimit = 296},
    ["command.chat.status_version_auto_on"] = {kind = "template", fields = {"version", "build", "level"}, slots = {"text", "text", "text"}, resultLimit = 294},
    ["command.chat.sync_preparing"] = {kind = "text"},
    ["command.chat.sync_requested"] = {kind = "text"},
    ["command.chat.sync_unavailable"] = {kind = "text"},
    ["command.chat.trace_clear_failed"] = {kind = "text"},
    ["command.chat.trace_cleared"] = {kind = "text"},
    ["command.chat.trace_now_off"] = {kind = "text"},
    ["command.chat.trace_now_on"] = {kind = "text"},
    ["command.chat.trace_recorder_missing"] = {kind = "text"},
    ["command.chat.trace_tab_hint"] = {kind = "text"},
    ["command.chat.update_releases_page"] = {kind = "template", fields = {"url"}, slots = {"text"}, resultLimit = 254},
    ["command.chat.update_unavailable"] = {kind = "text"},
    ["command.chat.usage"] = {kind = "template", fields = {"usage"}, slots = {"text"}, resultLimit = 136},
    ["command.chat.wishlist_design_hint"] = {kind = "block"},
    ["command.chat.wishlist_none_detected"] = {kind = "text"},
    ["command.chat.wishlist_reading"] = {kind = "template", fields = {"name", "source", "echoes", "families"}, slots = {"text", "text", "count", "count"}, resultLimit = 2048},
    ["command.value.rolling_decision_none"] = {kind = "text"},
    ["command.value.startup_validation_failed"] = {kind = "text"},
    ["command.value.wishlist_source_active"] = {kind = "text"},
    ["command.value.wishlist_source_designed"] = {kind = "text"},
    ["command.value.wishlist_source_other"] = {kind = "text"},
    ["main.chat.auto_off"] = {kind = "text"},
    ["main.chat.auto_on"] = {kind = "text"},
    ["main.chat.echo_optimizer_conflict"] = {kind = "text"},
    ["main.chat.loaded"] = {kind = "template", fields = {"version", "build"}, slots = {"text", "text"}, resultLimit = 298},
    ["main.chat.saturation_barriers"] = {kind = "text"},
    ["main.chat.saturation_builds"] = {kind = "text"},
    ["main.chat.saturation_catalog"] = {kind = "text"},
    ["main.chat.saturation_still_available"] = {kind = "text"},
    ["main.chat.saturation_tombstones"] = {kind = "text"},
    ["main.chat.update_notice_fallback"] = {kind = "template", fields = {"version"}, slots = {"text"}, resultLimit = 240},
    ["main.value.quality_common"] = {kind = "text"},
    ["main.value.quality_epic"] = {kind = "text"},
    ["main.value.quality_legendary"] = {kind = "text"},
    ["main.value.quality_rare"] = {kind = "text"},
    ["main.value.quality_uncommon"] = {kind = "text"},
    ["main.value.unknown_spell"] = {kind = "template", fields = {"id"}, slots = {"text"}, resultLimit = 88},
    ["main.value.unnamed_wishlist"] = {kind = "text"},
    ["update.body.hint_also_reported"] = {kind = "template", fields = {"build"}, slots = {"text"}, resultLimit = 268},
    ["update.body.hint_check_releases"] = {kind = "text"},
    ["update.body.hint_reported"] = {kind = "template", fields = {"build"}, slots = {"text"}, resultLimit = 186},
    ["update.body.hint_unverified"] = {kind = "text"},
    ["update.body.installed"] = {kind = "template", fields = {"build", "channel"}, slots = {"text", "text"}, resultLimit = 222},
    ["update.body.installed_label"] = {kind = "template", fields = {"build", "channel", "label"}, slots = {"text", "text", "text"}, resultLimit = 322},
    ["update.body.no_hint_received"] = {kind = "text"},
    ["update.body.no_verified_info"] = {kind = "text"},
    ["update.body.not_proof_latest"] = {kind = "text"},
    ["update.body.notices_off"] = {kind = "text"},
    ["update.body.notices_off_all"] = {kind = "text"},
    ["update.body.notices_off_stable_only"] = {kind = "text"},
    ["update.body.notices_on_all"] = {kind = "text"},
    ["update.body.notices_on_stable_only"] = {kind = "text"},
    ["update.body.peer_versions_not_release"] = {kind = "text"},
    ["update.body.release_available"] = {kind = "template", fields = {"build"}, slots = {"text"}, resultLimit = 188},
    ["update.body.test_build_available"] = {kind = "template", fields = {"build"}, slots = {"text"}, resultLimit = 194},
    ["update.body.test_hidden_stable_only"] = {kind = "template", fields = {"build"}, slots = {"text"}, resultLimit = 302},
    ["update.chat.hint_reported"] = {kind = "template", fields = {"build"}, slots = {"text"}, resultLimit = 532},
    ["update.chat.release_available"] = {kind = "template", fields = {"build", "installed"}, slots = {"text", "text"}, resultLimit = 400},
    ["update.chat.test_build_available"] = {kind = "template", fields = {"build", "installed"}, slots = {"text", "text"}, resultLimit = 406},
    ["update.menu.available"] = {kind = "template", fields = {"build"}, slots = {"text"}, resultLimit = 164},
    ["update.menu.hint_reported"] = {kind = "template", fields = {"build"}, slots = {"text"}, resultLimit = 210},
    ["update.menu.no_verified_info"] = {kind = "text"},
    ["update.menu.notices_off"] = {kind = "text"},
    ["update.value.channel_development"] = {kind = "text"},
    ["update.value.channel_internal"] = {kind = "text"},
    ["update.value.channel_public_test"] = {kind = "text"},
    ["update.value.channel_stable"] = {kind = "text"},
    -- hud (166)
    ["callboard.heading.rewards_by_difficulty"] = {kind = "text"},
    ["callboard.label.difficulty_hc1"] = {kind = "text"},
    ["callboard.label.difficulty_hc2"] = {kind = "text"},
    ["callboard.label.difficulty_hc3"] = {kind = "text"},
    ["callboard.label.difficulty_hc4"] = {kind = "text"},
    ["callboard.label.difficulty_hc5"] = {kind = "text"},
    ["callboard.label.difficulty_normal"] = {kind = "text"},
    ["callboard.status.failed"] = {kind = "text"},
    ["callboard.status.ready_turn_in"] = {kind = "text"},
    ["callboard.tooltip.higher_difficulty_rewards"] = {kind = "text"},
    ["callboard.tooltip.rewards_unavailable"] = {kind = "text"},
    ["callboard.value.reward_ash"] = {kind = "template", fields = {"ash"}, slots = {"text"}, resultLimit = 256},
    ["callboard.value.reward_xp"] = {kind = "template", fields = {"xp"}, slots = {"text"}, resultLimit = 256},
    ["layout.button.orb_mini_panel"] = {kind = "text"},
    ["layout.button.orb_mini_short"] = {kind = "text"},
    ["readout.body.recommendation_target"] = {kind = "template", fields = {"recommendation", "target"}, slots = {"text", "text"}, resultLimit = 1614},
    ["readout.body.scope_activate"] = {kind = "template", fields = {"setting", "value"}, slots = {"text", "text"}, resultLimit = 513},
    ["readout.body.scope_auto_off"] = {kind = "text"},
    ["readout.body.scope_auto_on"] = {kind = "text"},
    ["readout.body.scope_banish"] = {kind = "template", fields = {"setting", "value"}, slots = {"text", "text"}, resultLimit = 256},
    ["readout.body.scope_freeze"] = {kind = "template", fields = {"setting", "value", "command"}, slots = {"text", "text", "text"}, resultLimit = 278},
    ["readout.body.scope_intro"] = {kind = "text"},
    ["readout.body.scope_lock"] = {kind = "template", fields = {"setting", "value"}, slots = {"text", "text"}, resultLimit = 390},
    ["readout.body.scope_orbs"] = {kind = "text"},
    ["readout.body.scope_paused_because"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 672},
    ["readout.body.scope_read_only"] = {kind = "text"},
    ["readout.body.scope_reroll"] = {kind = "template", fields = {"setting", "value", "command"}, slots = {"text", "text", "text"}, resultLimit = 278},
    ["readout.body.scope_save"] = {kind = "template", fields = {"setting", "value"}, slots = {"text", "text"}, resultLimit = 477},
    ["readout.body.scope_take"] = {kind = "template", fields = {"setting", "value"}, slots = {"text", "text"}, resultLimit = 256},
    ["readout.body.scope_tomes"] = {kind = "template", fields = {"setting", "value"}, slots = {"text", "text"}, resultLimit = 429},
    ["readout.body.take_target"] = {kind = "template", fields = {"target"}, slots = {"text"}, resultLimit = 554},
    ["readout.body.tome_permission"] = {kind = "block"},
    ["readout.heading.auto_on"] = {kind = "text"},
    ["readout.heading.offer"] = {kind = "text"},
    ["readout.heading.offer_auto_on"] = {kind = "text"},
    ["readout.heading.offer_auto_on_short"] = {kind = "text"},
    ["readout.heading.offer_short"] = {kind = "text"},
    ["readout.heading.offer_you_choose"] = {kind = "text"},
    ["readout.heading.offer_you_choose_short"] = {kind = "text"},
    ["readout.heading.waiting_offer_data"] = {kind = "text"},
    ["readout.heading.you_choose"] = {kind = "text"},
    ["readout.label.guaranteed_offer"] = {kind = "text"},
    ["readout.label.offer_freeze"] = {kind = "text"},
    ["readout.label.offer_pick"] = {kind = "text"},
    ["readout.label.offer_recommended"] = {kind = "text"},
    ["readout.menu.activate_never"] = {kind = "template", fields = {"setting"}, slots = {"text"}, resultLimit = 256},
    ["readout.menu.allow_freeze"] = {kind = "template", fields = {"setting", "value"}, slots = {"text", "text"}, resultLimit = 256},
    ["readout.menu.allow_reroll"] = {kind = "template", fields = {"setting", "value"}, slots = {"text", "text"}, resultLimit = 256},
    ["readout.menu.auto_reference"] = {kind = "text"},
    ["readout.menu.auto_selected_off"] = {kind = "text"},
    ["readout.menu.auto_selected_on"] = {kind = "text"},
    ["readout.menu.auto_settings_title"] = {kind = "text"},
    ["readout.menu.banish"] = {kind = "template", fields = {"setting", "value"}, slots = {"text", "text"}, resultLimit = 256},
    ["readout.menu.lock_echoes"] = {kind = "template", fields = {"setting", "value"}, slots = {"text", "text"}, resultLimit = 312},
    ["readout.menu.orb_never"] = {kind = "text"},
    ["readout.menu.read_only"] = {kind = "text"},
    ["readout.menu.save_run"] = {kind = "template", fields = {"setting", "value"}, slots = {"text", "text"}, resultLimit = 435},
    ["readout.menu.take_needed"] = {kind = "template", fields = {"setting", "value"}, slots = {"text", "text"}, resultLimit = 270},
    ["readout.menu.tomes"] = {kind = "template", fields = {"setting", "value"}, slots = {"text", "text"}, resultLimit = 279},
    ["readout.note.auto_on_scope"] = {kind = "text"},
    ["readout.note.waiting_offer_data"] = {kind = "text"},
    ["readout.status.auto_refused"] = {kind = "text"},
    ["readout.status.auto_refused_orb"] = {kind = "text"},
    ["readout.status.auto_refused_status"] = {kind = "template", fields = {"status"}, slots = {"text"}, resultLimit = 1099},
    ["readout.status.auto_refused_warning"] = {kind = "template", fields = {"command"}, slots = {"text"}, resultLimit = 428},
    ["readout.status.charges_estimated"] = {kind = "template", fields = {"charges"}, slots = {"text"}, resultLimit = 319},
    ["readout.status.charges_full"] = {kind = "template", fields = {"banish", "reroll", "freeze"}, slots = {"text", "text", "text"}, resultLimit = 256},
    ["readout.status.help_client_auto_accept"] = {kind = "text"},
    ["readout.status.help_continues"] = {kind = "text"},
    ["readout.status.help_disable_addon"] = {kind = "text"},
    ["readout.status.help_orb"] = {kind = "text"},
    ["readout.status.help_point_auto"] = {kind = "text"},
    ["readout.status.help_wait_without_choosing"] = {kind = "text"},
    ["readout.status.hold_client_auto_accept"] = {kind = "text"},
    ["readout.status.hold_loading_screen"] = {kind = "text"},
    ["readout.status.hold_manual"] = {kind = "text"},
    ["readout.status.hold_other_addon"] = {kind = "text"},
    ["readout.status.hold_settling"] = {kind = "text"},
    ["readout.status.hold_user_acting"] = {kind = "text"},
    ["readout.status.idle"] = {kind = "text"},
    ["readout.status.level_prefixed"] = {kind = "template", fields = {"level", "status"}, slots = {"text", "text"}, resultLimit = 1099},
    ["readout.status.no_wishlist_advisor"] = {kind = "text"},
    ["readout.status.paused_reason"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 648},
    ["readout.status.paused_with_hint"] = {kind = "template", fields = {"reason", "hint"}, slots = {"text", "text"}, resultLimit = 925},
    ["readout.status.state_awaiting"] = {kind = "text"},
    ["readout.status.state_choice"] = {kind = "text"},
    ["readout.status.state_confirmed"] = {kind = "text"},
    ["readout.status.state_estimated"] = {kind = "text"},
    ["readout.status.state_loading"] = {kind = "text"},
    ["readout.status.state_not_sent"] = {kind = "text"},
    ["readout.status.state_offer"] = {kind = "text"},
    ["readout.status.state_paused"] = {kind = "text"},
    ["readout.status.state_ready"] = {kind = "text"},
    ["readout.status.state_refused"] = {kind = "text"},
    ["readout.status.state_requested"] = {kind = "text"},
    ["readout.status.state_sent"] = {kind = "text"},
    ["readout.status.state_spend_unconfirmed"] = {kind = "text"},
    ["readout.status.state_stale"] = {kind = "text"},
    ["readout.status.state_stored"] = {kind = "text"},
    ["readout.status.state_unavailable"] = {kind = "text"},
    ["readout.status.state_unconfirmed"] = {kind = "text"},
    ["readout.status.state_unknown"] = {kind = "text"},
    ["readout.status.state_with_detail"] = {kind = "template", fields = {"state", "detail"}, slots = {"text", "text"}, resultLimit = 1139},
    ["readout.status.waiting_echo_data"] = {kind = "text"},
    ["readout.tooltip.charges_legend_auto"] = {kind = "text"},
    ["readout.tooltip.charges_legend_estimated"] = {kind = "text"},
    ["readout.tooltip.charges_legend_letters"] = {kind = "text"},
    ["readout.tooltip.charges_legend_unknown"] = {kind = "text"},
    ["readout.value.echo_with_quality"] = {kind = "template", fields = {"name", "quality"}, slots = {"text", "text"}, resultLimit = 374},
    ["readout.value.quality_common"] = {kind = "text"},
    ["readout.value.quality_epic"] = {kind = "text"},
    ["readout.value.quality_guaranteed"] = {kind = "template", fields = {"quality"}, slots = {"text"}, resultLimit = 256},
    ["readout.value.quality_legendary"] = {kind = "text"},
    ["readout.value.quality_rare"] = {kind = "text"},
    ["readout.value.quality_uncommon"] = {kind = "text"},
    ["readout.value.quality_unknown"] = {kind = "text"},
    ["readout.value.queue_entry"] = {kind = "template", fields = {"index", "name"}, slots = {"text", "text"}, resultLimit = 345},
    ["readout.value.queue_wanted"] = {kind = "template", fields = {"index", "name"}, slots = {"text", "text"}, resultLimit = 372},
    ["readout.value.setting_not_set"] = {kind = "text"},
    ["readout.value.setting_off"] = {kind = "text"},
    ["readout.value.setting_on"] = {kind = "text"},
    ["readout.value.setting_unset_acts_off"] = {kind = "text"},
    ["readout.value.setting_unset_acts_on"] = {kind = "text"},
    ["server.chat.hardcore_menu_unavailable"] = {kind = "text"},
    ["theme.chat.appearance_applied"] = {kind = "template", fields = {"summary", "outcome"}, slots = {"text", "text"}, resultLimit = 512},
    ["theme.chat.colour_unavailable"] = {kind = "text"},
    ["theme.chat.style_unavailable"] = {kind = "text"},
    ["theme.label.palette_amethyst"] = {kind = "text"},
    ["theme.label.palette_auric"] = {kind = "text"},
    ["theme.label.palette_ember"] = {kind = "text"},
    ["theme.label.palette_emerald"] = {kind = "text"},
    ["theme.label.palette_graphite"] = {kind = "text"},
    ["theme.label.palette_sapphire"] = {kind = "text"},
    ["theme.label.style_slate"] = {kind = "text"},
    ["theme.label.style_vista"] = {kind = "text"},
    ["theme.menu.colour_choice"] = {kind = "template", fields = {"palette", "hue"}, slots = {"text", "text"}, resultLimit = 256},
    ["theme.menu.colour_default"] = {kind = "template", fields = {"palette", "hue"}, slots = {"text", "text"}, resultLimit = 256},
    ["theme.menu.colour_title"] = {kind = "text"},
    ["theme.menu.style_default"] = {kind = "template", fields = {"style"}, slots = {"text"}, resultLimit = 256},
    ["theme.menu.style_title"] = {kind = "text"},
    ["theme.menu.unknown_colour"] = {kind = "template", fields = {"value"}, slots = {"text"}, resultLimit = 256},
    ["theme.menu.unknown_style"] = {kind = "template", fields = {"value"}, slots = {"text"}, resultLimit = 256},
    ["theme.status.outcome_database_loading"] = {kind = "text"},
    ["theme.status.outcome_owner_unavailable"] = {kind = "text"},
    ["theme.status.outcome_saved"] = {kind = "text"},
    ["theme.status.outcome_session_read_only"] = {kind = "text"},
    ["theme.tooltip.appearance_help"] = {kind = "block"},
    ["theme.tooltip.style_slate"] = {kind = "text"},
    ["theme.tooltip.style_vista"] = {kind = "text"},
    ["theme.value.hue_blue"] = {kind = "text"},
    ["theme.value.hue_gold"] = {kind = "text"},
    ["theme.value.hue_gray"] = {kind = "text"},
    ["theme.value.hue_green"] = {kind = "text"},
    ["theme.value.hue_orange"] = {kind = "text"},
    ["theme.value.hue_purple"] = {kind = "text"},
    ["theme.value.summary"] = {kind = "template", fields = {"style", "palette"}, slots = {"text", "text"}, resultLimit = 256},
    ["unit_tooltip.label.build_author"] = {kind = "text"},
    ["unit_tooltip.label.leaderboard_rank"] = {kind = "template", fields = {"rank", "dps", "category"}, slots = {"text", "text", "text"}, resultLimit = 256},
    ["unit_tooltip.label.network_peer"] = {kind = "text"},
    ["unit_tooltip.label.nexus_user"] = {kind = "text"},
    ["unit_tooltip.value.category_dummy"] = {kind = "text"},
    ["unit_tooltip.value.category_lk"] = {kind = "text"},
    ["unit_tooltip.value.rank_nd"] = {kind = "template", fields = {"rank"}, slots = {"text"}, resultLimit = 256},
    ["unit_tooltip.value.rank_rd"] = {kind = "template", fields = {"rank"}, slots = {"text"}, resultLimit = 256},
    ["unit_tooltip.value.rank_st"] = {kind = "template", fields = {"rank"}, slots = {"text"}, resultLimit = 256},
    ["unit_tooltip.value.rank_th"] = {kind = "template", fields = {"rank"}, slots = {"text"}, resultLimit = 256},
    -- library (358)
    ["library.body.detail_incomplete"] = {kind = "text"},
    ["library.body.detail_invalid"] = {kind = "text"},
    ["library.body.detail_loading"] = {kind = "text"},
    ["library.body.detail_not_in_library"] = {kind = "text"},
    ["library.body.list_empty"] = {kind = "text"},
    ["library.body.no_selection"] = {kind = "block"},
    ["library.body.share_choose_source"] = {kind = "text"},
    ["library.button.class_all"] = {kind = "text"},
    ["library.button.class_current"] = {kind = "text"},
    ["library.button.class_loading"] = {kind = "text"},
    ["library.button.class_named"] = {kind = "template", fields = {"class"}, slots = {"text"}, resultLimit = 300},
    ["library.button.clear_search"] = {kind = "text"},
    ["library.button.copy_into_editor"] = {kind = "text"},
    ["library.button.delete"] = {kind = "text"},
    ["library.button.edit_build"] = {kind = "text"},
    ["library.button.edit_save_details"] = {kind = "text"},
    ["library.button.edit_use_active_wishlist"] = {kind = "text"},
    ["library.button.help"] = {kind = "text"},
    ["library.button.lockin_confirm"] = {kind = "text"},
    ["library.button.page_next"] = {kind = "text"},
    ["library.button.page_prev"] = {kind = "text"},
    ["library.button.popup_cancel"] = {kind = "text"},
    ["library.button.reference"] = {kind = "text"},
    ["library.button.remove_shared_record"] = {kind = "text"},
    ["library.button.request_full_echo_list"] = {kind = "text"},
    ["library.button.retry_share"] = {kind = "text"},
    ["library.button.save_link"] = {kind = "text"},
    ["library.button.scope_all"] = {kind = "text"},
    ["library.button.scope_mine"] = {kind = "text"},
    ["library.button.share_build"] = {kind = "text"},
    ["library.button.share_confirm"] = {kind = "text"},
    ["library.button.share_form_submit"] = {kind = "text"},
    ["library.button.share_saved_build"] = {kind = "text"},
    ["library.button.sharing_pending"] = {kind = "text"},
    ["library.button.sort_label"] = {kind = "template", fields = {"sort"}, slots = {"text"}, resultLimit = 200},
    ["library.button.source_named"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1200},
    ["library.button.startup_local_wishlists"] = {kind = "text"},
    ["library.button.stop_sharing_confirm"] = {kind = "text"},
    ["library.button.sync_listening"] = {kind = "text"},
    ["library.button.sync_mode"] = {kind = "text"},
    ["library.button.sync_now"] = {kind = "text"},
    ["library.button.sync_preparing"] = {kind = "text"},
    ["library.button.update_shared_build"] = {kind = "text"},
    ["library.button.view_build"] = {kind = "text"},
    ["library.chat.build_still_syncing"] = {kind = "text"},
    ["library.chat.copy_unavailable_arriving"] = {kind = "text"},
    ["library.chat.copy_unavailable_reason"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1200},
    ["library.chat.edit_description_unseeded"] = {kind = "block"},
    ["library.chat.edit_echoes_replaced"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 300},
    ["library.chat.edit_saved_locally"] = {kind = "text"},
    ["library.chat.edit_saved_not_queued"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1200},
    ["library.chat.edit_saved_queued"] = {kind = "text"},
    ["library.chat.edit_update_failed"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1200},
    ["library.chat.edit_update_pending"] = {kind = "text"},
    ["library.chat.lockin_done"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1200},
    ["library.chat.lockin_failed"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1200},
    ["library.chat.lockin_nothing_left"] = {kind = "text"},
    ["library.chat.lockin_partial"] = {kind = "template", fields = {"count", "locked", "overflow", "action"}, slots = {"count", "count", "count", "text"}, resultLimit = 1200},
    ["library.chat.retry_failed"] = {kind = "template", fields = {"name", "reason"}, slots = {"text", "text"}, resultLimit = 1200},
    ["library.chat.retry_mode_refused"] = {kind = "template", fields = {"name", "reason"}, slots = {"text", "text"}, resultLimit = 1200},
    ["library.chat.retry_queued"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1200},
    ["library.chat.retry_waiting"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1200},
    ["library.chat.share_accepted"] = {kind = "text"},
    ["library.chat.share_cancelled_changed"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1200},
    ["library.chat.share_cancelled_retired"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1200},
    ["library.chat.share_linked_dps_queued"] = {kind = "text"},
    ["library.chat.share_linked_dps_unknown"] = {kind = "text"},
    ["library.chat.share_needs_source_class"] = {kind = "text"},
    ["library.chat.share_not_own_saved_build"] = {kind = "text"},
    ["library.chat.share_not_shared"] = {kind = "template", fields = {"name", "reason"}, slots = {"text", "text"}, resultLimit = 1600},
    ["library.chat.share_preparing"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1200},
    ["library.chat.share_saved_mode_off"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1200},
    ["library.chat.share_saved_not_queued"] = {kind = "template", fields = {"name", "reason"}, slots = {"text", "text"}, resultLimit = 1600},
    ["library.chat.share_saved_queued"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1200},
    ["library.chat.share_saved_unreported"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1200},
    ["library.chat.stop_sharing_not_queued"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1200},
    ["library.chat.stop_sharing_not_yours"] = {kind = "text"},
    ["library.chat.stop_sharing_pending"] = {kind = "block"},
    ["library.chat.stop_sharing_queued"] = {kind = "text"},
    ["library.chat.stop_sharing_refused"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1200},
    ["library.chat.stop_sharing_retry_pending"] = {kind = "block"},
    ["library.chat.stop_sharing_unconfirmed"] = {kind = "text"},
    ["library.chat.sync_asking"] = {kind = "text"},
    ["library.chat.sync_preparing"] = {kind = "text"},
    ["library.error.adapter_not_ready"] = {kind = "text"},
    ["library.error.build_evidence_unavailable"] = {kind = "text"},
    ["library.error.build_no_echoes"] = {kind = "text"},
    ["library.error.build_no_ordinary_echoes"] = {kind = "text"},
    ["library.error.build_not_found"] = {kind = "text"},
    ["library.error.build_storage_refused"] = {kind = "text"},
    ["library.error.catalog_maintenance_unavailable"] = {kind = "text"},
    ["library.error.catalog_unavailable"] = {kind = "text"},
    ["library.error.description_too_long"] = {kind = "text"},
    ["library.error.description_unsafe"] = {kind = "text"},
    ["library.error.discord_link_hint"] = {kind = "text"},
    ["library.error.echo_list_read_only"] = {kind = "text"},
    ["library.error.echo_roles_unreadable"] = {kind = "text"},
    ["library.error.invalid_discord_link"] = {kind = "text"},
    ["library.error.local_removal_refused"] = {kind = "text"},
    ["library.error.local_save_failed"] = {kind = "text"},
    ["library.error.locked_evidence_unavailable"] = {kind = "text"},
    ["library.error.locked_lookup_failed"] = {kind = "text"},
    ["library.error.locked_resolution_failed"] = {kind = "text"},
    ["library.error.locked_resolver_unavailable"] = {kind = "text"},
    ["library.error.lockin_no_valid_echoes"] = {kind = "text"},
    ["library.error.lockin_server_busy"] = {kind = "text"},
    ["library.error.lockin_server_refused"] = {kind = "text"},
    ["library.error.no_active_wishlist"] = {kind = "text"},
    ["library.error.no_source_selected"] = {kind = "text"},
    ["library.error.not_found"] = {kind = "text"},
    ["library.error.not_retryable"] = {kind = "text"},
    ["library.error.not_saved_loadout"] = {kind = "text"},
    ["library.error.not_your_build"] = {kind = "text"},
    ["library.error.player_or_catalog_changed"] = {kind = "text"},
    ["library.error.queue_rejected"] = {kind = "text"},
    ["library.error.record_identity_unavailable"] = {kind = "text"},
    ["library.error.retry_saved_build_listing"] = {kind = "block"},
    ["library.error.saved_build_not_deletable"] = {kind = "text"},
    ["library.error.saved_loadout_echoes_from_server"] = {kind = "text"},
    ["library.error.saved_loadout_storage_refused"] = {kind = "text"},
    ["library.error.share_already_waiting"] = {kind = "text"},
    ["library.error.share_build_changed"] = {kind = "text"},
    ["library.error.share_not_retryable"] = {kind = "text"},
    ["library.error.share_not_terminal"] = {kind = "text"},
    ["library.error.share_semantic_envelope"] = {kind = "template", fields = {"ordinary", "locked", "max_ordinary", "max_locked", "max_total"}, slots = {"text", "text", "text", "text", "text"}, resultLimit = 800},
    ["library.error.share_stopped_owner_changed"] = {kind = "text"},
    ["library.error.share_too_large"] = {kind = "text"},
    ["library.error.stop_sharing_catalog_preparing"] = {kind = "text"},
    ["library.error.stop_sharing_not_confirmed"] = {kind = "text"},
    ["library.error.stop_sharing_remote_unsupported"] = {kind = "text"},
    ["library.error.storage_refused"] = {kind = "text"},
    ["library.error.sync_retry_failed"] = {kind = "text"},
    ["library.error.sync_status_unavailable"] = {kind = "text"},
    ["library.error.sync_unavailable"] = {kind = "text"},
    ["library.error.title_too_long"] = {kind = "text"},
    ["library.error.title_unsafe"] = {kind = "text"},
    ["library.error.withdrawal_failed"] = {kind = "text"},
    ["library.error.withdrawal_rejected"] = {kind = "text"},
    ["library.heading.actions"] = {kind = "text"},
    ["library.heading.best_records"] = {kind = "text"},
    ["library.heading.browse_builds"] = {kind = "text"},
    ["library.heading.detail_incomplete"] = {kind = "text"},
    ["library.heading.detail_loading"] = {kind = "text"},
    ["library.heading.detail_unavailable"] = {kind = "text"},
    ["library.heading.list_empty"] = {kind = "text"},
    ["library.heading.no_selection"] = {kind = "text"},
    ["library.label.by_owner"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1200},
    ["library.label.category_dummy"] = {kind = "text"},
    ["library.label.category_lich_king"] = {kind = "text"},
    ["library.label.class_death_knight"] = {kind = "text"},
    ["library.label.class_druid"] = {kind = "text"},
    ["library.label.class_hunter"] = {kind = "text"},
    ["library.label.class_mage"] = {kind = "text"},
    ["library.label.class_paladin"] = {kind = "text"},
    ["library.label.class_priest"] = {kind = "text"},
    ["library.label.class_rogue"] = {kind = "text"},
    ["library.label.class_shaman"] = {kind = "text"},
    ["library.label.class_unknown"] = {kind = "text"},
    ["library.label.class_warlock"] = {kind = "text"},
    ["library.label.class_warrior"] = {kind = "text"},
    ["library.label.detail_echoes"] = {kind = "text"},
    ["library.label.detail_locked_echoes"] = {kind = "text"},
    ["library.label.detail_locked_echoes_more"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 200},
    ["library.label.discord_link"] = {kind = "text"},
    ["library.label.edit_description"] = {kind = "text"},
    ["library.label.edit_title"] = {kind = "text"},
    ["library.label.lockin_load_into_editor"] = {kind = "text"},
    ["library.label.preview_locked_suffix"] = {kind = "text"},
    ["library.label.require_both_records"] = {kind = "text"},
    ["library.label.row_assigned_wishlist"] = {kind = "text"},
    ["library.label.row_best_dps"] = {kind = "template", fields = {"dps"}, slots = {"text"}, resultLimit = 200},
    ["library.label.row_both_records"] = {kind = "text"},
    ["library.label.row_category_dummy"] = {kind = "text"},
    ["library.label.row_class_not_supplied"] = {kind = "text"},
    ["library.label.row_dps"] = {kind = "template", fields = {"dps"}, slots = {"text"}, resultLimit = 200},
    ["library.label.row_dps_average"] = {kind = "template", fields = {"dps"}, slots = {"text"}, resultLimit = 200},
    ["library.label.row_dps_dummy"] = {kind = "template", fields = {"dps"}, slots = {"text"}, resultLimit = 200},
    ["library.label.row_dps_lich_king"] = {kind = "template", fields = {"dps"}, slots = {"text"}, resultLimit = 200},
    ["library.label.row_missing_dps_record"] = {kind = "text"},
    ["library.label.row_no_dps_record"] = {kind = "text"},
    ["library.label.row_no_wishlist_assigned"] = {kind = "text"},
    ["library.label.row_owner_not_established"] = {kind = "text"},
    ["library.label.row_saved_build"] = {kind = "text"},
    ["library.label.row_your_build"] = {kind = "text"},
    ["library.label.share_build_title"] = {kind = "text"},
    ["library.label.share_choose_source"] = {kind = "text"},
    ["library.label.share_description"] = {kind = "text"},
    ["library.label.share_posting_as"] = {kind = "template", fields = {"class"}, slots = {"text"}, resultLimit = 300},
    ["library.label.share_preview"] = {kind = "text"},
    ["library.label.sort_dps"] = {kind = "text"},
    ["library.label.sort_recent"] = {kind = "text"},
    ["library.label.sort_title"] = {kind = "text"},
    ["library.label.source_kind_saved_build"] = {kind = "text"},
    ["library.label.source_kind_wishlist"] = {kind = "text"},
    ["library.label.source_unnamed"] = {kind = "template", fields = {"kind"}, slots = {"text"}, resultLimit = 300},
    ["library.label.your_best"] = {kind = "template", fields = {"dps"}, slots = {"text"}, resultLimit = 200},
    ["library.menu.no_sources"] = {kind = "text"},
    ["library.menu.source_row"] = {kind = "template", fields = {"kind", "name", "count"}, slots = {"text", "text", "count"}, resultLimit = 1600},
    ["library.menu.source_row_locked"] = {kind = "template", fields = {"kind", "name", "count", "locked"}, slots = {"text", "text", "count", "count"}, resultLimit = 1600},
    ["library.note.edit_can_replace_echoes"] = {kind = "text"},
    ["library.note.edit_share_new_for_echoes"] = {kind = "text"},
    ["library.note.install_details"] = {kind = "text"},
    ["library.placeholder.search"] = {kind = "text"},
    ["library.popup.lockin_overwrites"] = {kind = "text"},
    ["library.popup.lockin_question"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1200},
    ["library.popup.share_note_automatic_dps"] = {kind = "block"},
    ["library.popup.share_note_listed_with"] = {kind = "text"},
    ["library.popup.share_note_mode_off"] = {kind = "text"},
    ["library.popup.share_note_no_recall"] = {kind = "block"},
    ["library.popup.share_note_no_receipt"] = {kind = "text"},
    ["library.popup.share_note_saves_new"] = {kind = "block"},
    ["library.popup.share_note_saves_update"] = {kind = "block"},
    ["library.popup.share_note_summary"] = {kind = "block"},
    ["library.popup.share_saved_question"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1200},
    ["library.popup.stop_sharing_question"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1200},
    ["library.popup.stop_sharing_scope"] = {kind = "text"},
    ["library.status.detail_echo_missing"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 120},
    ["library.status.detail_echo_total"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 120},
    ["library.status.detail_receiving_echoes"] = {kind = "text"},
    ["library.status.echo_list_read_only"] = {kind = "text"},
    ["library.status.edit_state_own_build"] = {kind = "text"},
    ["library.status.edit_state_saved_build"] = {kind = "block"},
    ["library.status.edit_state_shared_listing"] = {kind = "block"},
    ["library.status.edit_state_title_editable"] = {kind = "text"},
    ["library.status.list_no_match"] = {kind = "text"},
    ["library.status.list_unreadable"] = {kind = "text"},
    ["library.status.owner_not_established"] = {kind = "text"},
    ["library.status.retry_last_share"] = {kind = "template", fields = {"why", "mode"}, slots = {"text", "text"}, resultLimit = 1500},
    ["library.status.retry_mode_automatic"] = {kind = "text"},
    ["library.status.retry_mode_manual"] = {kind = "text"},
    ["library.status.retry_mode_off"] = {kind = "text"},
    ["library.status.retry_mode_unknown"] = {kind = "text"},
    ["library.status.retry_why_mode"] = {kind = "template", fields = {"outcome"}, slots = {"text"}, resultLimit = 300},
    ["library.status.retry_why_reason"] = {kind = "template", fields = {"outcome", "reason"}, slots = {"text", "text"}, resultLimit = 1200},
    ["library.status.row_syncing_loadout"] = {kind = "text"},
    ["library.status.row_waiting_for_echoes"] = {kind = "text"},
    ["library.status.row_wishlist_copies_unavailable"] = {kind = "text"},
    ["library.status.share_form_kept"] = {kind = "text"},
    ["library.status.share_no_source"] = {kind = "text"},
    ["library.status.share_not_queued"] = {kind = "template", fields = {"name", "reason"}, slots = {"text", "text"}, resultLimit = 1600},
    ["library.status.share_not_shared"] = {kind = "template", fields = {"name", "reason"}, slots = {"text", "text"}, resultLimit = 1600},
    ["library.status.share_ordinary_only_many"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 600},
    ["library.status.share_ordinary_only_one"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 600},
    ["library.status.share_preparing"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1200},
    ["library.status.share_preparing_catalog"] = {kind = "text"},
    ["library.status.share_preparing_continues"] = {kind = "text"},
    ["library.status.share_preparing_mode_off"] = {kind = "text"},
    ["library.status.share_preparing_saving"] = {kind = "text"},
    ["library.status.share_preview_roles"] = {kind = "template", fields = {"ordinary", "locked"}, slots = {"count", "count"}, resultLimit = 300},
    ["library.status.share_queue_full"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1200},
    ["library.status.share_queued"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1200},
    ["library.status.share_roles"] = {kind = "template", fields = {"ordinary", "locked"}, slots = {"count", "count"}, resultLimit = 300},
    ["library.status.share_roles_unsettled"] = {kind = "text"},
    ["library.status.share_sent"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1200},
    ["library.status.share_stopped"] = {kind = "template", fields = {"name", "reason"}, slots = {"text", "text"}, resultLimit = 1600},
    ["library.status.share_stopped_retryable"] = {kind = "template", fields = {"name", "reason"}, slots = {"text", "text"}, resultLimit = 1600},
    ["library.status.showing_range"] = {kind = "template", fields = {"first", "last", "total"}, slots = {"count", "count", "count"}, resultLimit = 200},
    ["library.status.startup_loading"] = {kind = "text"},
    ["library.status.startup_local_available"] = {kind = "text"},
    ["library.status.startup_preparing"] = {kind = "text"},
    ["library.status.startup_shared_failed"] = {kind = "block"},
    ["library.status.startup_validating"] = {kind = "text"},
    ["library.status.startup_validation_stopped"] = {kind = "text"},
    ["library.status.sync_counts_added"] = {kind = "template", fields = {"bundled", "overlay", "available", "shown", "results", "added"}, slots = {"count", "count", "count", "count", "count", "count"}, resultLimit = 600},
    ["library.status.sync_counts_idle"] = {kind = "template", fields = {"bundled", "overlay", "available", "shown", "results"}, slots = {"count", "count", "count", "count", "count"}, resultLimit = 600},
    ["library.status.sync_listening"] = {kind = "template", fields = {"seconds", "new", "bundled", "overlay", "available", "shown", "results"}, slots = {"count", "count", "count", "count", "count", "count", "count"}, resultLimit = 600},
    ["library.status.sync_preparing"] = {kind = "text"},
    ["library.title.edit_form"] = {kind = "text"},
    ["library.title.share_form"] = {kind = "text"},
    ["library.title.startup"] = {kind = "template", fields = {"view"}, slots = {"text"}, resultLimit = 300},
    ["library.title.startup_view_community"] = {kind = "text"},
    ["library.title.startup_view_leaderboard"] = {kind = "text"},
    ["library.title.window"] = {kind = "text"},
    ["library.tooltip.catalog_version"] = {kind = "template", fields = {"version"}, slots = {"text"}, resultLimit = 200},
    ["library.tooltip.class_filter"] = {kind = "text"},
    ["library.tooltip.copy_draft_only"] = {kind = "text"},
    ["library.tooltip.copy_locked_slots"] = {kind = "text"},
    ["library.tooltip.copy_opens_draft"] = {kind = "text"},
    ["library.tooltip.copy_title"] = {kind = "text"},
    ["library.tooltip.require_both_records"] = {kind = "block"},
    ["library.tooltip.require_both_records_scope"] = {kind = "block"},
    ["library.tooltip.retry_click_only"] = {kind = "text"},
    ["library.tooltip.retry_mode_decides"] = {kind = "text"},
    ["library.tooltip.retry_title"] = {kind = "text"},
    ["library.tooltip.row_open_for_full"] = {kind = "text"},
    ["library.tooltip.save_link_copy_hint"] = {kind = "text"},
    ["library.tooltip.save_link_title"] = {kind = "text"},
    ["library.tooltip.scope_all"] = {kind = "text"},
    ["library.tooltip.scope_mine"] = {kind = "text"},
    ["library.tooltip.scope_mine_not_my_builds"] = {kind = "block"},
    ["library.tooltip.share_build_body"] = {kind = "text"},
    ["library.tooltip.share_build_title"] = {kind = "text"},
    ["library.tooltip.share_saved_body"] = {kind = "block"},
    ["library.tooltip.share_saved_not_copy"] = {kind = "text"},
    ["library.tooltip.share_saved_title"] = {kind = "text"},
    ["library.tooltip.sort_body"] = {kind = "text"},
    ["library.tooltip.sort_title"] = {kind = "text"},
    ["library.tooltip.sync_mode"] = {kind = "block"},
    ["library.tooltip.sync_now"] = {kind = "text"},
    ["library.tooltip.sync_now_automatic_dps"] = {kind = "block"},
    ["library.tooltip.sync_now_terms"] = {kind = "block"},
    ["library.tooltip.view_build_body"] = {kind = "text"},
    ["library.tooltip.view_build_title"] = {kind = "text"},
    ["library.value.class_select"] = {kind = "text"},
    ["library.value.invalid_title"] = {kind = "text"},
    ["library.value.no_description"] = {kind = "text"},
    ["library.value.no_record_yet"] = {kind = "text"},
    ["library.value.owner_unknown"] = {kind = "text"},
    ["library.value.player_unknown"] = {kind = "text"},
    ["library.value.saved_build"] = {kind = "text"},
    ["library.value.share_outcome_dropped"] = {kind = "text"},
    ["library.value.share_outcome_expired"] = {kind = "text"},
    ["library.value.share_outcome_rejected"] = {kind = "text"},
    ["library.value.share_outcome_reset"] = {kind = "text"},
    ["library.value.share_outcome_stopped"] = {kind = "text"},
    ["library.value.share_outcome_throttle_exhausted"] = {kind = "text"},
    ["library.value.source_select"] = {kind = "text"},
    ["library.value.source_unnamed"] = {kind = "text"},
    ["library.value.this_build"] = {kind = "text"},
    ["library.value.unnamed_wishlist"] = {kind = "text"},
    ["library.value.wishlist"] = {kind = "text"},
    ["sync.body.mode_automatic_help"] = {kind = "block"},
    ["sync.body.mode_manual_help"] = {kind = "text"},
    ["sync.body.mode_off_help"] = {kind = "text"},
    ["sync.button.apply"] = {kind = "text"},
    ["sync.button.cancel"] = {kind = "text"},
    ["sync.chat.mode_result"] = {kind = "template", fields = {"result"}, slots = {"text"}, resultLimit = 1200},
    ["sync.error.choice_invalid_value"] = {kind = "text"},
    ["sync.error.choice_lifecycle"] = {kind = "text"},
    ["sync.error.choice_loading"] = {kind = "text"},
    ["sync.error.choice_no_database"] = {kind = "text"},
    ["sync.error.choice_not_read_back"] = {kind = "text"},
    ["sync.error.choice_replaced"] = {kind = "text"},
    ["sync.error.choice_saved_format"] = {kind = "text"},
    ["sync.error.choice_settings"] = {kind = "text"},
    ["sync.error.choice_stale"] = {kind = "text"},
    ["sync.error.choice_unavailable"] = {kind = "text"},
    ["sync.label.mode_automatic"] = {kind = "text"},
    ["sync.label.mode_manual"] = {kind = "text"},
    ["sync.label.mode_off"] = {kind = "text"},
    ["sync.note.apply_saves_only"] = {kind = "text"},
    ["sync.status.choice_not_saved"] = {kind = "template", fields = {"reason", "mode"}, slots = {"text", "text"}, resultLimit = 700},
    ["sync.status.choice_not_writable"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 600},
    ["sync.status.choice_saved"] = {kind = "template", fields = {"mode"}, slots = {"text"}, resultLimit = 400},
    ["sync.status.choice_unchanged"] = {kind = "template", fields = {"mode"}, slots = {"text"}, resultLimit = 400},
    ["sync.status.current_choice_invalid"] = {kind = "template", fields = {"mode"}, slots = {"text"}, resultLimit = 400},
    ["sync.status.current_choice_not_applied"] = {kind = "template", fields = {"mode", "choice"}, slots = {"text", "text"}, resultLimit = 400},
    ["sync.status.current_choice_unknown"] = {kind = "template", fields = {"mode"}, slots = {"text"}, resultLimit = 400},
    ["sync.status.current_default"] = {kind = "template", fields = {"mode"}, slots = {"text"}, resultLimit = 400},
    ["sync.status.current_explicit"] = {kind = "template", fields = {"mode"}, slots = {"text"}, resultLimit = 400},
    ["sync.status.current_legacy"] = {kind = "template", fields = {"mode"}, slots = {"text"}, resultLimit = 500},
    ["sync.status.current_unknown"] = {kind = "text"},
    ["sync.status.mode_automatic"] = {kind = "block"},
    ["sync.status.mode_manual"] = {kind = "text"},
    ["sync.status.mode_off"] = {kind = "text"},
    ["sync.status.not_saved_unavailable"] = {kind = "text"},
    ["sync.title.mode_dialog"] = {kind = "text"},
    ["sync.value.mode_unknown"] = {kind = "text"},
    -- records (276)
    ["leaderboard.body.both_records_order"] = {kind = "text"},
    ["leaderboard.body.no_both_records"] = {kind = "text"},
    ["leaderboard.body.no_dummy_records"] = {kind = "text"},
    ["leaderboard.body.no_lk_records"] = {kind = "text"},
    ["leaderboard.body.select_prompt"] = {kind = "text"},
    ["leaderboard.body.syncs_on_login"] = {kind = "text"},
    ["leaderboard.button.copy_into_editor"] = {kind = "text"},
    ["leaderboard.button.nav_builds"] = {kind = "text"},
    ["leaderboard.button.nav_help"] = {kind = "text"},
    ["leaderboard.button.nav_leaderboard"] = {kind = "text"},
    ["leaderboard.button.nav_reference"] = {kind = "text"},
    ["leaderboard.button.nav_wishlists"] = {kind = "text"},
    ["leaderboard.button.open_build"] = {kind = "text"},
    ["leaderboard.button.preparing_shared_data"] = {kind = "text"},
    ["leaderboard.button.request_full_build"] = {kind = "text"},
    ["leaderboard.button.requesting"] = {kind = "text"},
    ["leaderboard.button.sync_now"] = {kind = "text"},
    ["leaderboard.chat.asking_for_builds"] = {kind = "text"},
    ["leaderboard.chat.new_best"] = {kind = "template", fields = {"build", "category", "dps"}, slots = {"text", "text", "text"}, resultLimit = 2048},
    ["leaderboard.chat.new_best_session_only"] = {kind = "text"},
    ["leaderboard.chat.preparing_sync_data"] = {kind = "text"},
    ["leaderboard.chat.sync_unavailable"] = {kind = "text"},
    ["leaderboard.column.character_loadout"] = {kind = "text"},
    ["leaderboard.column.rank"] = {kind = "text"},
    ["leaderboard.column.result"] = {kind = "text"},
    ["leaderboard.heading.exact_loadout"] = {kind = "text"},
    ["leaderboard.heading.locked_echoes"] = {kind = "text"},
    ["leaderboard.heading.locked_echoes_more"] = {kind = "template", fields = {"count"}, slots = {"text"}, resultLimit = 400},
    ["leaderboard.label.all_classes"] = {kind = "text"},
    ["leaderboard.label.by_owner"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048},
    ["leaderboard.label.by_owner_class_missing"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048},
    ["leaderboard.label.class_death_knight"] = {kind = "text"},
    ["leaderboard.label.class_druid"] = {kind = "text"},
    ["leaderboard.label.class_hunter"] = {kind = "text"},
    ["leaderboard.label.class_mage"] = {kind = "text"},
    ["leaderboard.label.class_paladin"] = {kind = "text"},
    ["leaderboard.label.class_priest"] = {kind = "text"},
    ["leaderboard.label.class_rogue"] = {kind = "text"},
    ["leaderboard.label.class_shaman"] = {kind = "text"},
    ["leaderboard.label.class_warlock"] = {kind = "text"},
    ["leaderboard.label.class_warrior"] = {kind = "text"},
    ["leaderboard.placeholder.search"] = {kind = "text"},
    ["leaderboard.reason.build_authority_unavailable"] = {kind = "text"},
    ["leaderboard.reason.categories_disagree"] = {kind = "text"},
    ["leaderboard.reason.categories_disagree_resolved"] = {kind = "text"},
    ["leaderboard.reason.community_builds_unavailable"] = {kind = "text"},
    ["leaderboard.reason.current_identity_changed"] = {kind = "text"},
    ["leaderboard.reason.current_identity_unavailable"] = {kind = "text"},
    ["leaderboard.reason.echo_list_arriving"] = {kind = "text"},
    ["leaderboard.reason.exact_identity_changed"] = {kind = "text"},
    ["leaderboard.reason.exact_identity_unavailable"] = {kind = "text"},
    ["leaderboard.reason.exact_revision_unavailable"] = {kind = "text"},
    ["leaderboard.reason.locked_evidence_unavailable"] = {kind = "text"},
    ["leaderboard.reason.record_catalog_id_mismatch"] = {kind = "text"},
    ["leaderboard.reason.record_catalog_mismatch"] = {kind = "text"},
    ["leaderboard.reason.record_evidence_changed"] = {kind = "text"},
    ["leaderboard.reason.record_evidence_unavailable"] = {kind = "text"},
    ["leaderboard.reason.record_list_mismatch"] = {kind = "text"},
    ["leaderboard.reason.record_missing"] = {kind = "text"},
    ["leaderboard.reason.record_missing_list_identity"] = {kind = "text"},
    ["leaderboard.reason.record_unavailable"] = {kind = "text"},
    ["leaderboard.reason.validation_failed"] = {kind = "text"},
    ["leaderboard.status.combined_breakdown"] = {kind = "template", fields = {"average", "dummy", "lk"}, slots = {"text", "text", "text"}, resultLimit = 600},
    ["leaderboard.status.copy_unavailable"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 2048},
    ["leaderboard.status.echo_slots"] = {kind = "template", fields = {"count"}, slots = {"text"}, resultLimit = 200},
    ["leaderboard.status.level"] = {kind = "template", fields = {"level"}, slots = {"text"}, resultLimit = 200},
    ["leaderboard.status.loading_both_records"] = {kind = "text"},
    ["leaderboard.status.loading_dummy_records"] = {kind = "text"},
    ["leaderboard.status.loading_lk_records"] = {kind = "text"},
    ["leaderboard.status.loadout_syncing"] = {kind = "text"},
    ["leaderboard.status.more_below"] = {kind = "text"},
    ["leaderboard.status.no_description"] = {kind = "text"},
    ["leaderboard.status.open_unavailable"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 2048},
    ["leaderboard.status.owner_not_established"] = {kind = "text"},
    ["leaderboard.status.preparing_sync_data"] = {kind = "text"},
    ["leaderboard.status.ranked_both_records"] = {kind = "template", fields = {"count"}, slots = {"text"}, resultLimit = 600},
    ["leaderboard.status.ranked_dummy_records"] = {kind = "template", fields = {"count"}, slots = {"text"}, resultLimit = 600},
    ["leaderboard.status.ranked_lk_records"] = {kind = "template", fields = {"count"}, slots = {"text"}, resultLimit = 600},
    ["leaderboard.status.record_facts_missing"] = {kind = "text"},
    ["leaderboard.status.removing_expired_requests"] = {kind = "text"},
    ["leaderboard.status.request_not_sent"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1200},
    ["leaderboard.status.roles_no_reply"] = {kind = "text"},
    ["leaderboard.status.roles_not_received"] = {kind = "text"},
    ["leaderboard.status.roles_requested"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048},
    ["leaderboard.status.sending_queued_work"] = {kind = "text"},
    ["leaderboard.status.strongest_dps"] = {kind = "template", fields = {"dps"}, slots = {"text"}, resultLimit = 400},
    ["leaderboard.status.sync_resumes_in"] = {kind = "template", fields = {"seconds"}, slots = {"text"}, resultLimit = 200},
    ["leaderboard.status.syncing"] = {kind = "text"},
    ["leaderboard.tab.both_records"] = {kind = "text"},
    ["leaderboard.tab.lich_king"] = {kind = "text"},
    ["leaderboard.tab.training_dummy"] = {kind = "text"},
    ["leaderboard.title.records"] = {kind = "text"},
    ["leaderboard.tooltip.both_records_rank"] = {kind = "text"},
    ["leaderboard.tooltip.both_records_title"] = {kind = "text"},
    ["leaderboard.tooltip.class_not_supplied"] = {kind = "text"},
    ["leaderboard.tooltip.owner_not_established"] = {kind = "text"},
    ["leaderboard.tooltip.owner_verified"] = {kind = "text"},
    ["leaderboard.tooltip.realm"] = {kind = "template", fields = {"realm"}, slots = {"text"}, resultLimit = 600},
    ["leaderboard.tooltip.realm_not_stated"] = {kind = "text"},
    ["leaderboard.tooltip.realm_stated"] = {kind = "template", fields = {"realm"}, slots = {"text"}, resultLimit = 600},
    ["leaderboard.tooltip.sync_automatic_record_sends"] = {kind = "block"},
    ["leaderboard.tooltip.sync_automatic_sends"] = {kind = "text"},
    ["leaderboard.tooltip.sync_now_asks"] = {kind = "text"},
    ["leaderboard.tooltip.sync_now_title"] = {kind = "text"},
    ["leaderboard.tooltip.sync_sent_received_stored"] = {kind = "text"},
    ["leaderboard.value.category_dummy"] = {kind = "text"},
    ["leaderboard.value.category_lk"] = {kind = "text"},
    ["leaderboard.value.combined_row_breakdown"] = {kind = "template", fields = {"average", "dummy", "lk"}, slots = {"text", "text", "text"}, resultLimit = 600},
    ["leaderboard.value.current_echo_set"] = {kind = "text"},
    ["leaderboard.value.dps"] = {kind = "template", fields = {"dps"}, slots = {"text"}, resultLimit = 200},
    ["leaderboard.value.invalid_title"] = {kind = "text"},
    ["leaderboard.value.realm_unknown"] = {kind = "text"},
    ["leaderboard.value.reason_unavailable"] = {kind = "text"},
    ["leaderboard.value.recorded_build"] = {kind = "text"},
    ["leaderboard.value.title_class_missing"] = {kind = "template", fields = {"title"}, slots = {"text"}, resultLimit = 2048},
    ["leaderboard.value.unknown_player"] = {kind = "text"},
    ["loading.body.local_controls_wait"] = {kind = "text"},
    ["loading.body.local_tools_remain_available"] = {kind = "text"},
    ["loading.body.see_status_keep_backup"] = {kind = "template", fields = {"command"}, slots = {"text"}, resultLimit = 400},
    ["loading.body.shared_views_unavailable"] = {kind = "text"},
    ["loading.body.wishlist_ready_shared_loading"] = {kind = "text"},
    ["loading.body.wishlist_unlocks_after_check"] = {kind = "text"},
    ["loading.button.wishlists"] = {kind = "text"},
    ["loading.status.applying_library_update"] = {kind = "text"},
    ["loading.status.checking_character_data"] = {kind = "text"},
    ["loading.status.checking_library_records"] = {kind = "text"},
    ["loading.status.collecting_library_records"] = {kind = "text"},
    ["loading.status.community_data_ready"] = {kind = "text"},
    ["loading.status.community_leaderboard_ready"] = {kind = "text"},
    ["loading.status.community_unavailable_refused"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1600},
    ["loading.status.current_step_counted"] = {kind = "template", fields = {"step", "done", "total", "percent"}, slots = {"text", "text", "text", "text"}, resultLimit = 800},
    ["loading.status.current_step_in_progress"] = {kind = "template", fields = {"step"}, slots = {"text"}, resultLimit = 800},
    ["loading.status.current_step_records_read"] = {kind = "template", fields = {"step", "records"}, slots = {"text", "text"}, resultLimit = 800},
    ["loading.status.elapsed"] = {kind = "template", fields = {"time"}, slots = {"text"}, resultLimit = 200},
    ["loading.status.finishing_library_update"] = {kind = "text"},
    ["loading.status.finishing_saved_data_checks"] = {kind = "text"},
    ["loading.status.indexing_library_records"] = {kind = "text"},
    ["loading.status.preparing_build_library"] = {kind = "text"},
    ["loading.status.preparing_community_data"] = {kind = "text"},
    ["loading.status.preparing_library_save"] = {kind = "text"},
    ["loading.status.preparing_library_update"] = {kind = "text"},
    ["loading.status.preparing_shared_build_info"] = {kind = "text"},
    ["loading.status.reading_community_builds"] = {kind = "text"},
    ["loading.status.reading_local_data"] = {kind = "text"},
    ["loading.status.reading_older_community_records"] = {kind = "text"},
    ["loading.status.reading_saved_data"] = {kind = "text"},
    ["loading.status.ready"] = {kind = "text"},
    ["loading.status.records_markers_over_total"] = {kind = "text"},
    ["loading.status.refreshing_changed_community"] = {kind = "text"},
    ["loading.status.removal_markers_over_limit"] = {kind = "template", fields = {"limit"}, slots = {"text"}, resultLimit = 600},
    ["loading.status.removing_redundant_copies"] = {kind = "text"},
    ["loading.status.retention_markers_over_limit"] = {kind = "template", fields = {"limit"}, slots = {"text"}, resultLimit = 600},
    ["loading.status.saved_and_shipped_over_distinct_builds"] = {kind = "template", fields = {"limit"}, slots = {"text"}, resultLimit = 600},
    ["loading.status.saved_and_shipped_over_entries"] = {kind = "template", fields = {"limit"}, slots = {"text"}, resultLimit = 600},
    ["loading.status.saved_builds_over_entries"] = {kind = "template", fields = {"limit"}, slots = {"text"}, resultLimit = 600},
    ["loading.status.saved_community_data_too_large"] = {kind = "text"},
    ["loading.status.saved_list_over_build_limit"] = {kind = "template", fields = {"limit"}, slots = {"text"}, resultLimit = 600},
    ["loading.status.saved_list_over_distinct_builds"] = {kind = "template", fields = {"limit"}, slots = {"text"}, resultLimit = 600},
    ["loading.status.saved_markers_over_entries"] = {kind = "template", fields = {"limit"}, slots = {"text"}, resultLimit = 600},
    ["loading.status.saved_removals_over_entries"] = {kind = "template", fields = {"limit"}, slots = {"text"}, resultLimit = 600},
    ["loading.status.saved_shipped_markers_over_entries"] = {kind = "template", fields = {"limit"}, slots = {"text"}, resultLimit = 600},
    ["loading.status.saved_shipped_removals_over_entries"] = {kind = "template", fields = {"limit"}, slots = {"text"}, resultLimit = 600},
    ["loading.status.see_status_for_reason"] = {kind = "template", fields = {"command"}, slots = {"text"}, resultLimit = 400},
    ["loading.status.shared_data_unavailable_reason"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 800},
    ["loading.status.shipped_builds_over_limit"] = {kind = "template", fields = {"limit"}, slots = {"text"}, resultLimit = 600},
    ["loading.status.sorting_library_records"] = {kind = "text"},
    ["loading.status.starting_local_tools"] = {kind = "text"},
    ["loading.status.startup_stopped_reason"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 800},
    ["loading.status.updating_build_library"] = {kind = "text"},
    ["loading.status.verifying_checked_records"] = {kind = "text"},
    ["loading.status.verifying_library_data"] = {kind = "text"},
    ["loading.status.wishlist_ready_shared_may_load"] = {kind = "text"},
    ["loading.title.loading"] = {kind = "text"},
    ["loading.title.ready"] = {kind = "text"},
    ["loading.title.stopped"] = {kind = "text"},
    ["loading.tooltip.local_tools_available"] = {kind = "text"},
    ["loading.tooltip.local_tools_unlock"] = {kind = "text"},
    ["loading.tooltip.view_loading"] = {kind = "template", fields = {"view"}, slots = {"text"}, resultLimit = 400},
    ["loading.tooltip.view_unavailable"] = {kind = "template", fields = {"view"}, slots = {"text"}, resultLimit = 400},
    ["loading.value.reason_unavailable"] = {kind = "text"},
    ["log.body.large_report_cancel"] = {kind = "text"},
    ["log.body.page_refused"] = {kind = "block"},
    ["log.body.preparing_report_steps"] = {kind = "text"},
    ["log.button.clear_failed"] = {kind = "text"},
    ["log.button.clear_log"] = {kind = "text"},
    ["log.button.cleared"] = {kind = "text"},
    ["log.button.next_page"] = {kind = "text"},
    ["log.button.peer_start"] = {kind = "text"},
    ["log.button.peer_stop"] = {kind = "text"},
    ["log.button.previous_page"] = {kind = "text"},
    ["log.button.refresh"] = {kind = "text"},
    ["log.error.export_builder_unavailable"] = {kind = "text"},
    ["log.error.export_failed"] = {kind = "template", fields = {"error"}, slots = {"text"}, resultLimit = 2048},
    ["log.error.export_start_failed"] = {kind = "template", fields = {"error"}, slots = {"text"}, resultLimit = 2048},
    ["log.label.peer_event_filter"] = {kind = "text"},
    ["log.status.building_full_log"] = {kind = "text"},
    ["log.status.clear_failed"] = {kind = "text"},
    ["log.status.collecting_history"] = {kind = "template", fields = {"history", "done", "total"}, slots = {"text", "text", "text"}, resultLimit = 1600},
    ["log.status.copy_pages_in_order"] = {kind = "text"},
    ["log.status.diagnostic_history_cleared"] = {kind = "text"},
    ["log.status.error_history_cleared"] = {kind = "text"},
    ["log.status.export_failed"] = {kind = "text"},
    ["log.status.export_progress"] = {kind = "template", fields = {"progress"}, slots = {"text"}, resultLimit = 2048},
    ["log.status.loading_tab"] = {kind = "template", fields = {"tab"}, slots = {"text"}, resultLimit = 400},
    ["log.status.page_of"] = {kind = "template", fields = {"page", "pages"}, slots = {"text", "text"}, resultLimit = 200},
    ["log.status.preparing_export"] = {kind = "text"},
    ["log.status.total_bytes"] = {kind = "template", fields = {"bytes"}, slots = {"text"}, resultLimit = 200},
    ["log.tab.advanced_peer"] = {kind = "text"},
    ["log.tab.dps"] = {kind = "text"},
    ["log.tab.errors"] = {kind = "text"},
    ["log.tab.locked_echoes"] = {kind = "text"},
    ["log.tab.manual_overrides"] = {kind = "text"},
    ["log.tab.performance"] = {kind = "text"},
    ["log.tab.recent_choices"] = {kind = "text"},
    ["log.tab.roll_trace"] = {kind = "text"},
    ["log.tab.slot_actions"] = {kind = "text"},
    ["log.tab.status"] = {kind = "text"},
    ["log.tab.sync"] = {kind = "text"},
    ["log.tab.wishlist"] = {kind = "text"},
    ["log.title.data_log"] = {kind = "text"},
    ["log.tooltip.clear_history_scope"] = {kind = "block"},
    ["log.tooltip.clear_history_title"] = {kind = "text"},
    ["log.tooltip.prepare_report_pages"] = {kind = "text"},
    ["log.tooltip.prepare_report_title"] = {kind = "text"},
    ["release_note.body.close_keeps_run"] = {kind = "text"},
    ["release_note.body.experimental_offline"] = {kind = "text"},
    ["release_note.body.help_seven_topics"] = {kind = "text"},
    ["release_note.body.orb_same_wishlist"] = {kind = "text"},
    ["release_note.body.real_resource_decision"] = {kind = "text"},
    ["release_note.body.start_once_approves"] = {kind = "text"},
    ["release_note.body.target_change_pauses"] = {kind = "text"},
    ["release_note.body.targets_protected"] = {kind = "text"},
    ["release_note.body.unproven_completion_paused"] = {kind = "text"},
    ["release_note.button.acknowledge"] = {kind = "text"},
    ["release_note.heading.assigned_wishlist_help"] = {kind = "text"},
    ["release_note.heading.optional_orb_refinement"] = {kind = "text"},
    ["release_note.title.prototype_release"] = {kind = "text"},
    ["support.body.copy_or_prepare"] = {kind = "text"},
    ["support.button.clear_focus"] = {kind = "text"},
    ["support.button.close"] = {kind = "text"},
    ["support.button.inspect_prepared"] = {kind = "text"},
    ["support.button.next_incident"] = {kind = "text"},
    ["support.button.previous_incident"] = {kind = "text"},
    ["support.label.advanced_private"] = {kind = "text"},
    ["support.reason.cannot_load_on_demand"] = {kind = "text"},
    ["support.reason.component_no_answer"] = {kind = "text"},
    ["support.reason.component_not_installed"] = {kind = "text"},
    ["support.reason.component_not_loaded"] = {kind = "text"},
    ["support.reason.component_refused"] = {kind = "text"},
    ["support.reason.report_not_completed"] = {kind = "text"},
    ["support.reason.step_budget"] = {kind = "text"},
    ["support.reason.storage_not_registered"] = {kind = "text"},
    ["support.status.attach_file"] = {kind = "template", fields = {"path"}, slots = {"text"}, resultLimit = 800},
    ["support.status.builder_unavailable"] = {kind = "text"},
    ["support.status.copy_summary_note"] = {kind = "template", fields = {"bytes", "max"}, slots = {"text", "text"}, resultLimit = 800},
    ["support.status.incidents_none"] = {kind = "template", fields = {"count"}, slots = {"text"}, resultLimit = 400},
    ["support.status.incidents_showing"] = {kind = "template", fields = {"count", "id"}, slots = {"text", "text"}, resultLimit = 1600},
    ["support.status.no_prepared_report"] = {kind = "text"},
    ["support.status.not_prepared_build_failed"] = {kind = "template", fields = {"error"}, slots = {"text"}, resultLimit = 2048},
    ["support.status.not_prepared_component_refused"] = {kind = "template", fields = {"error"}, slots = {"text"}, resultLimit = 2048},
    ["support.status.not_prepared_kept"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1200},
    ["support.status.not_prepared_left_untouched"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1200},
    ["support.status.not_prepared_use_copy"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1200},
    ["support.status.report_partial"] = {kind = "template", fields = {"omissions"}, slots = {"text"}, resultLimit = 1600},
    ["support.status.report_prepared"] = {kind = "template", fields = {"id"}, slots = {"text"}, resultLimit = 1200},
    ["support.status.storage_holds_report"] = {kind = "template", fields = {"id", "bytes", "chunks", "checksum"}, slots = {"text", "text", "text", "text"}, resultLimit = 1200},
    ["support.status.storage_left_untouched"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1200},
    ["support.status.storage_not_loaded"] = {kind = "text"},
    ["support.status.storage_not_ready"] = {kind = "text"},
    ["support.status.storage_not_ready_reason"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1200},
    ["support.status.storage_ready_none"] = {kind = "text"},
    ["support.status.stored_report"] = {kind = "template", fields = {"id", "bytes", "chunks", "checksum"}, slots = {"text", "text", "text", "text"}, resultLimit = 1600},
    ["support.status.stored_report_matches"] = {kind = "template", fields = {"id", "bytes", "chunks", "checksum"}, slots = {"text", "text", "text", "text"}, resultLimit = 1600},
    ["support.status.stored_report_mismatch"] = {kind = "template", fields = {"id", "bytes", "chunks", "checksum"}, slots = {"text", "text", "text", "text"}, resultLimit = 1600},
    ["support.title.support_report"] = {kind = "text"},
    ["support.value.unavailable"] = {kind = "text"},
    -- NEXUS-L10N-FULL-UI END
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
