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
    -- guide (700)
    ["consent.body.current_values_route"] = {kind = "text"},
    ["consent.body.keep_auto_off"] = {kind = "text"},
    ["consent.body.onboarding_choices"] = {kind = "block"},
    ["consent.body.overwrite_risk"] = {kind = "block"},
    ["consent.body.replacement_without_run"] = {kind = "block"},
    ["consent.button.no"] = {kind = "text"},
    ["consent.button.onboarding_close"] = {kind = "text"},
    ["consent.button.onboarding_continue"] = {kind = "text"},
    ["consent.button.yes"] = {kind = "text"},
    ["consent.label.dont_warn_again"] = {kind = "text"},
    ["consent.status.read_countdown"] = {kind = "template", fields = {"seconds"}, slots = {"count"}, resultLimit = 200},
    ["consent.status.understand"] = {kind = "text"},
    ["consent.title.overwrite_warning"] = {kind = "text"},
    ["guide.body.assign_cancelled"] = {kind = "text"},
    ["guide.body.assign_cancelled_body"] = {kind = "text"},
    ["guide.body.assign_ev_build"] = {kind = "text"},
    ["guide.body.assign_ev_character"] = {kind = "text"},
    ["guide.body.assign_ev_read"] = {kind = "text"},
    ["guide.body.assign_ev_read_value"] = {kind = "text"},
    ["guide.body.assign_ev_request"] = {kind = "text"},
    ["guide.body.assign_ev_request_value"] = {kind = "template", fields = {"request"}, slots = {"count"}, resultLimit = 132},
    ["guide.body.assign_ev_save"] = {kind = "text"},
    ["guide.body.assign_ev_wishlist"] = {kind = "text"},
    ["guide.body.assign_missing"] = {kind = "text"},
    ["guide.body.assign_observed"] = {kind = "text"},
    ["guide.body.assign_observed_body"] = {kind = "template", fields = {"build", "wishlist"}, slots = {"text", "text"}, resultLimit = 885},
    ["guide.body.assign_open_note"] = {kind = "template", fields = {"wishlist"}, slots = {"text"}, resultLimit = 577},
    ["guide.body.assign_readback"] = {kind = "text"},
    ["guide.body.assign_rejected"] = {kind = "text"},
    ["guide.body.assign_rejected_body"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 500},
    ["guide.body.assign_stale"] = {kind = "text"},
    ["guide.body.assign_stale_body_changed"] = {kind = "template", fields = {"build"}, slots = {"text"}, resultLimit = 582},
    ["guide.body.assign_stale_body_mismatch"] = {kind = "template", fields = {"build", "other"}, slots = {"text", "text"}, resultLimit = 865},
    ["guide.body.assign_stale_body_other"] = {kind = "template", fields = {"other"}, slots = {"text"}, resultLimit = 577},
    ["guide.body.assign_stale_body_outdated"] = {kind = "text"},
    ["guide.body.assign_stale_body_partial"] = {kind = "template", fields = {"build"}, slots = {"text"}, resultLimit = 540},
    ["guide.body.assign_stale_body_stale"] = {kind = "template", fields = {"build"}, slots = {"text"}, resultLimit = 615},
    ["guide.body.assign_unavailable"] = {kind = "text"},
    ["guide.body.assign_unavailable_body"] = {kind = "block"},
    ["guide.body.assign_verified"] = {kind = "text"},
    ["guide.body.assign_waiting"] = {kind = "template", fields = {"wishlist"}, slots = {"text"}, resultLimit = 570},
    ["guide.body.auto_kept_off"] = {kind = "text"},
    ["guide.body.auto_kept_on"] = {kind = "text"},
    ["guide.body.auto_kept_unknown"] = {kind = "text"},
    ["guide.body.auto_lead"] = {kind = "text"},
    ["guide.body.auto_mode_off"] = {kind = "text"},
    ["guide.body.auto_mode_on"] = {kind = "text"},
    ["guide.body.auto_mode_unknown"] = {kind = "text"},
    ["guide.body.auto_more_off"] = {kind = "text"},
    ["guide.body.auto_more_on"] = {kind = "block"},
    ["guide.body.auto_review_note"] = {kind = "text"},
    ["guide.body.auto_sub_read"] = {kind = "text"},
    ["guide.body.auto_sub_unknown"] = {kind = "text"},
    ["guide.body.finish_assign_done"] = {kind = "template", fields = {"build", "wishlist"}, slots = {"text", "text"}, resultLimit = 777},
    ["guide.body.finish_assign_not"] = {kind = "text"},
    ["guide.body.finish_assign_rejected"] = {kind = "text"},
    ["guide.body.finish_assign_skipped"] = {kind = "text"},
    ["guide.body.finish_assign_stale"] = {kind = "text"},
    ["guide.body.finish_assign_true"] = {kind = "template", fields = {"build", "wishlist"}, slots = {"text", "text"}, resultLimit = 832},
    ["guide.body.finish_assign_unknown"] = {kind = "text"},
    ["guide.body.finish_assign_waiting"] = {kind = "text"},
    ["guide.body.finish_auto_mode_off"] = {kind = "text"},
    ["guide.body.finish_auto_mode_on"] = {kind = "text"},
    ["guide.body.finish_auto_not_reviewed_off"] = {kind = "text"},
    ["guide.body.finish_auto_not_reviewed_on"] = {kind = "text"},
    ["guide.body.finish_auto_unknown"] = {kind = "text"},
    ["guide.body.finish_current_note"] = {kind = "template", fields = {"build", "wishlist"}, slots = {"text", "text"}, resultLimit = 890},
    ["guide.body.finish_current_unknown"] = {kind = "text"},
    ["guide.body.finish_explore"] = {kind = "text"},
    ["guide.body.finish_lessons_orbs_lines_1"] = {kind = "text"},
    ["guide.body.finish_lessons_orbs_lines_2"] = {kind = "text"},
    ["guide.body.finish_lessons_orbs_open"] = {kind = "text"},
    ["guide.body.finish_lessons_sharing_lines_1"] = {kind = "text"},
    ["guide.body.finish_lessons_sharing_lines_2"] = {kind = "text"},
    ["guide.body.finish_lessons_sharing_open"] = {kind = "text"},
    ["guide.body.finish_manual_done"] = {kind = "text"},
    ["guide.body.finish_manual_not"] = {kind = "text"},
    ["guide.body.finish_manual_skipped"] = {kind = "text"},
    ["guide.body.finish_more"] = {kind = "text"},
    ["guide.body.finish_more_sub"] = {kind = "text"},
    ["guide.body.finish_rows_assign"] = {kind = "text"},
    ["guide.body.finish_rows_auto"] = {kind = "text"},
    ["guide.body.finish_rows_manual"] = {kind = "text"},
    ["guide.body.finish_rows_target"] = {kind = "text"},
    ["guide.body.finish_rows_wishlist"] = {kind = "text"},
    ["guide.body.finish_sent"] = {kind = "text"},
    ["guide.body.finish_sub_done"] = {kind = "text"},
    ["guide.body.finish_sub_explore"] = {kind = "text"},
    ["guide.body.finish_sub_open"] = {kind = "text"},
    ["guide.body.finish_sub_open_session"] = {kind = "block"},
    ["guide.body.finish_sub_true"] = {kind = "text"},
    ["guide.body.finish_target_not"] = {kind = "text"},
    ["guide.body.finish_target_skipped"] = {kind = "text"},
    ["guide.body.finish_wish_draft"] = {kind = "text"},
    ["guide.body.finish_wish_not"] = {kind = "text"},
    ["guide.body.finish_wish_partial"] = {kind = "text"},
    ["guide.body.finish_wish_skipped"] = {kind = "text"},
    ["guide.body.finish_wish_uncertain"] = {kind = "text"},
    ["guide.body.help_full"] = {kind = "block"},
    ["guide.body.help_lines_assign_1"] = {kind = "text"},
    ["guide.body.help_lines_assign_2"] = {kind = "text"},
    ["guide.body.help_lines_auto_1"] = {kind = "text"},
    ["guide.body.help_lines_auto_2"] = {kind = "text"},
    ["guide.body.help_lines_manual_1"] = {kind = "text"},
    ["guide.body.help_lines_summary_1"] = {kind = "text"},
    ["guide.body.help_lines_summary_2"] = {kind = "text"},
    ["guide.body.help_lines_target_1"] = {kind = "text"},
    ["guide.body.help_lines_target_2"] = {kind = "text"},
    ["guide.body.help_lines_welcome_1"] = {kind = "text"},
    ["guide.body.help_lines_welcome_2"] = {kind = "text"},
    ["guide.body.help_lines_wishlist_1"] = {kind = "text"},
    ["guide.body.help_lines_wishlist_2"] = {kind = "text"},
    ["guide.body.outcome_expect_assign"] = {kind = "text"},
    ["guide.body.outcome_expect_auto"] = {kind = "text"},
    ["guide.body.outcome_expect_label"] = {kind = "text"},
    ["guide.body.outcome_expect_manual"] = {kind = "text"},
    ["guide.body.outcome_expect_summary"] = {kind = "text"},
    ["guide.body.outcome_expect_target"] = {kind = "text"},
    ["guide.body.outcome_expect_welcome"] = {kind = "text"},
    ["guide.body.outcome_expect_wishlist"] = {kind = "text"},
    ["guide.body.outcome_extra_rejected"] = {kind = "text"},
    ["guide.body.outcome_extra_skipped"] = {kind = "text"},
    ["guide.body.outcome_extra_stale"] = {kind = "text"},
    ["guide.body.outcome_extra_unavailable"] = {kind = "text"},
    ["guide.body.outcome_extra_waiting"] = {kind = "text"},
    ["guide.body.outcome_observed_label"] = {kind = "text"},
    ["guide.body.outcome_summary_label"] = {kind = "text"},
    ["guide.body.reference_esc_step"] = {kind = "template", fields = {"step"}, slots = {"count"}, resultLimit = 130},
    ["guide.body.reference_esc_topics"] = {kind = "text"},
    ["guide.body.reference_full"] = {kind = "block"},
    ["guide.body.reference_lead"] = {kind = "text"},
    ["guide.body.reference_tag"] = {kind = "text"},
    ["guide.body.reference_topics_orbs_paras_1"] = {kind = "block"},
    ["guide.body.reference_topics_orbs_paras_2"] = {kind = "block"},
    ["guide.body.reference_topics_rolling_paras_1"] = {kind = "text"},
    ["guide.body.reference_topics_rolling_paras_2"] = {kind = "text"},
    ["guide.body.reference_topics_sharing_paras_1"] = {kind = "block"},
    ["guide.body.reference_topics_sharing_paras_2"] = {kind = "block"},
    ["guide.body.reference_topics_start_paras_1"] = {kind = "block"},
    ["guide.body.reference_topics_start_paras_2"] = {kind = "text"},
    ["guide.body.reference_topics_troubleshooting_paras_1"] = {kind = "block"},
    ["guide.body.reference_topics_troubleshooting_paras_2"] = {kind = "text"},
    ["guide.body.reference_topics_wishlists_paras_1"] = {kind = "block"},
    ["guide.body.reference_topics_wishlists_paras_2"] = {kind = "block"},
    ["guide.body.safety"] = {kind = "text"},
    ["guide.body.sim_auto_on"] = {kind = "text"},
    ["guide.body.sim_banner"] = {kind = "text"},
    ["guide.body.sim_body"] = {kind = "text"},
    ["guide.body.sim_cards_1_desc"] = {kind = "text"},
    ["guide.body.sim_cards_1_name"] = {kind = "text"},
    ["guide.body.sim_cards_2_desc"] = {kind = "text"},
    ["guide.body.sim_cards_2_name"] = {kind = "text"},
    ["guide.body.sim_cards_3_desc"] = {kind = "text"},
    ["guide.body.sim_cards_3_name"] = {kind = "text"},
    ["guide.body.sim_differ"] = {kind = "text"},
    ["guide.body.sim_mark"] = {kind = "text"},
    ["guide.body.sim_match"] = {kind = "text"},
    ["guide.body.sim_picked"] = {kind = "template", fields = {"card"}, slots = {"text"}, resultLimit = 500},
    ["guide.body.sim_why"] = {kind = "text"},
    ["guide.body.target_accepted"] = {kind = "text"},
    ["guide.body.target_active"] = {kind = "text"},
    ["guide.body.target_c_already"] = {kind = "template", fields = {"build", "wishlist"}, slots = {"text", "text"}, resultLimit = 737},
    ["guide.body.target_c_already2"] = {kind = "text"},
    ["guide.body.target_c_auto_on"] = {kind = "text"},
    ["guide.body.target_c_echoes"] = {kind = "text"},
    ["guide.body.target_c_empty"] = {kind = "template", fields = {"build"}, slots = {"text"}, resultLimit = 532},
    ["guide.body.target_c_empty_save"] = {kind = "block"},
    ["guide.body.target_c_first"] = {kind = "block"},
    ["guide.body.target_c_kept"] = {kind = "template", fields = {"wishlist"}, slots = {"text"}, resultLimit = 487},
    ["guide.body.target_c_new"] = {kind = "text"},
    ["guide.body.target_c_replace"] = {kind = "template", fields = {"build", "current", "wishlist"}, slots = {"text", "text", "text"}, resultLimit = 1117},
    ["guide.body.target_c_return"] = {kind = "block"},
    ["guide.body.target_c_select"] = {kind = "template", fields = {"build"}, slots = {"text"}, resultLimit = 637, lines = true},
    ["guide.body.target_c_select_how"] = {kind = "block"},
    ["guide.body.target_c_unknown"] = {kind = "text"},
    ["guide.body.target_empty"] = {kind = "text"},
    ["guide.body.target_empty_offer"] = {kind = "text"},
    ["guide.body.target_first"] = {kind = "text"},
    ["guide.body.target_first_desc"] = {kind = "text"},
    ["guide.body.target_follows"] = {kind = "template", fields = {"wishlist"}, slots = {"text"}, resultLimit = 395},
    ["guide.body.target_follows_none"] = {kind = "text"},
    ["guide.body.target_follows_unknown"] = {kind = "text"},
    ["guide.body.target_if_assign"] = {kind = "template", fields = {"wishlist"}, slots = {"text"}, resultLimit = 422},
    ["guide.body.target_missing"] = {kind = "text"},
    ["guide.body.target_read"] = {kind = "text"},
    ["guide.body.target_short_already"] = {kind = "text"},
    ["guide.body.target_short_new"] = {kind = "text"},
    ["guide.body.target_short_replace"] = {kind = "template", fields = {"wishlist"}, slots = {"text"}, resultLimit = 505},
    ["guide.body.target_slot"] = {kind = "template", fields = {"slot", "name"}, slots = {"count", "text"}, resultLimit = 420},
    ["guide.body.target_slot_unnamed"] = {kind = "template", fields = {"slot"}, slots = {"count"}, resultLimit = 97},
    ["guide.body.target_unavailable"] = {kind = "text"},
    ["guide.body.target_unavailable_body"] = {kind = "text"},
    ["guide.body.welcome_body"] = {kind = "text"},
    ["guide.body.welcome_body_replay"] = {kind = "text"},
    ["guide.body.welcome_paths_existing_desc"] = {kind = "text"},
    ["guide.body.welcome_paths_explore_desc"] = {kind = "text"},
    ["guide.body.welcome_paths_new_desc"] = {kind = "text"},
    ["guide.body.why_assign"] = {kind = "text"},
    ["guide.body.why_auto"] = {kind = "text"},
    ["guide.body.why_manual"] = {kind = "text"},
    ["guide.body.why_summary"] = {kind = "text"},
    ["guide.body.why_target"] = {kind = "text"},
    ["guide.body.why_welcome"] = {kind = "text"},
    ["guide.body.why_wishlist"] = {kind = "text"},
    ["guide.body.wishlist_assigned_now"] = {kind = "template", fields = {"build"}, slots = {"text"}, resultLimit = 407},
    ["guide.body.wishlist_assigned_now_ambiguous"] = {kind = "template", fields = {"build", "wishlist"}, slots = {"text", "text"}, resultLimit = 960, lines = true},
    ["guide.body.wishlist_assigned_now_line"] = {kind = "template", fields = {"build", "wishlist"}, slots = {"text", "text"}, resultLimit = 740},
    ["guide.body.wishlist_assigned_now_unknown"] = {kind = "text"},
    ["guide.body.wishlist_chosen"] = {kind = "template", fields = {"wishlist"}, slots = {"text"}, resultLimit = 397},
    ["guide.body.wishlist_concept_build"] = {kind = "text"},
    ["guide.body.wishlist_concept_build_body"] = {kind = "text"},
    ["guide.body.wishlist_concept_wish"] = {kind = "text"},
    ["guide.body.wishlist_concept_wish_body"] = {kind = "text"},
    ["guide.body.wishlist_create_blocked"] = {kind = "text"},
    ["guide.body.wishlist_create_blocked_desc"] = {kind = "text"},
    ["guide.body.wishlist_create_desc"] = {kind = "text"},
    ["guide.body.wishlist_create_title"] = {kind = "text"},
    ["guide.body.wishlist_draft"] = {kind = "text"},
    ["guide.body.wishlist_import_bad"] = {kind = "text"},
    ["guide.body.wishlist_import_bad_body"] = {kind = "block"},
    ["guide.body.wishlist_import_desc"] = {kind = "text"},
    ["guide.body.wishlist_import_empty"] = {kind = "text"},
    ["guide.body.wishlist_import_label"] = {kind = "text"},
    ["guide.body.wishlist_import_long"] = {kind = "template", fields = {"limit"}, slots = {"count"}, resultLimit = 412, lines = true},
    ["guide.body.wishlist_import_ok"] = {kind = "template", fields = {"name", "entries", "rolled", "locked"}, slots = {"text", "count", "count", "count"}, resultLimit = 647},
    ["guide.body.wishlist_import_ok_body"] = {kind = "block"},
    ["guide.body.wishlist_import_roles"] = {kind = "text"},
    ["guide.body.wishlist_import_suspended"] = {kind = "text"},
    ["guide.body.wishlist_import_title"] = {kind = "text"},
    ["guide.body.wishlist_import_unavailable"] = {kind = "text"},
    ["guide.body.wishlist_import_unnamed"] = {kind = "text"},
    ["guide.body.wishlist_more"] = {kind = "text"},
    ["guide.body.wishlist_needs_roles"] = {kind = "text"},
    ["guide.body.wishlist_none"] = {kind = "text"},
    ["guide.body.wishlist_not_loaded"] = {kind = "text"},
    ["guide.body.wishlist_not_saved"] = {kind = "text"},
    ["guide.body.wishlist_partial"] = {kind = "text"},
    ["guide.body.wishlist_plan_body"] = {kind = "block"},
    ["guide.body.wishlist_plan_context"] = {kind = "block"},
    ["guide.body.wishlist_plan_head"] = {kind = "text"},
    ["guide.body.wishlist_plan_same"] = {kind = "block"},
    ["guide.body.wishlist_reselect"] = {kind = "block"},
    ["guide.body.wishlist_saved"] = {kind = "template", fields = {"wishlist"}, slots = {"text"}, resultLimit = 452},
    ["guide.body.wishlist_selected"] = {kind = "template", fields = {"wishlist"}, slots = {"text"}, resultLimit = 400},
    ["guide.body.wishlist_selected_none"] = {kind = "text"},
    ["guide.body.wishlist_uncertain"] = {kind = "block"},
    ["guide.body.wishlist_yours"] = {kind = "text"},
    ["guide.button.all_topics"] = {kind = "text"},
    ["guide.button.auto_less"] = {kind = "text"},
    ["guide.button.auto_more"] = {kind = "text"},
    ["guide.button.back"] = {kind = "text"},
    ["guide.button.cancel"] = {kind = "text"},
    ["guide.button.check"] = {kind = "text"},
    ["guide.button.check_code"] = {kind = "text"},
    ["guide.button.checklist_hide"] = {kind = "text"},
    ["guide.button.checklist_show"] = {kind = "text"},
    ["guide.button.close_tip"] = {kind = "text"},
    ["guide.button.close_tip_session"] = {kind = "text"},
    ["guide.button.dismiss_draft"] = {kind = "text"},
    ["guide.button.finish"] = {kind = "text"},
    ["guide.button.full_help"] = {kind = "text"},
    ["guide.button.full_reference"] = {kind = "text"},
    ["guide.button.go_step"] = {kind = "text"},
    ["guide.button.go_target"] = {kind = "text"},
    ["guide.button.go_wishlist"] = {kind = "text"},
    ["guide.button.help"] = {kind = "text"},
    ["guide.button.hide"] = {kind = "text"},
    ["guide.button.keep_auto_off"] = {kind = "text"},
    ["guide.button.keep_auto_on"] = {kind = "text"},
    ["guide.button.later"] = {kind = "text"},
    ["guide.button.leave"] = {kind = "text"},
    ["guide.button.next"] = {kind = "text"},
    ["guide.button.open"] = {kind = "text"},
    ["guide.button.open_again"] = {kind = "text"},
    ["guide.button.open_builds"] = {kind = "text"},
    ["guide.button.open_draft"] = {kind = "text"},
    ["guide.button.plan_changed"] = {kind = "text"},
    ["guide.button.read"] = {kind = "text"},
    ["guide.button.ref_back"] = {kind = "template", fields = {"step", "label"}, slots = {"count", "text"}, resultLimit = 447},
    ["guide.button.replace"] = {kind = "text"},
    ["guide.button.replay"] = {kind = "text"},
    ["guide.button.reread"] = {kind = "text"},
    ["guide.button.retry"] = {kind = "text"},
    ["guide.button.return_plan"] = {kind = "text"},
    ["guide.button.review"] = {kind = "text"},
    ["guide.button.scroll_down"] = {kind = "text"},
    ["guide.button.scroll_up"] = {kind = "text"},
    ["guide.button.skip"] = {kind = "text"},
    ["guide.chat.chat_auto_off"] = {kind = "text"},
    ["guide.chat.chat_auto_on"] = {kind = "text"},
    ["guide.chat.chat_auto_unknown"] = {kind = "text"},
    ["guide.chat.chat_complete"] = {kind = "template", fields = {"build", "wishlist"}, slots = {"text", "text"}, resultLimit = 780},
    ["guide.chat.chat_explore"] = {kind = "text"},
    ["guide.chat.chat_incomplete_many"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 250},
    ["guide.chat.chat_incomplete_one"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 247},
    ["guide.chat.chat_paused"] = {kind = "template", fields = {"step"}, slots = {"text"}, resultLimit = 510},
    ["guide.chat.chat_reopen"] = {kind = "block"},
    ["guide.chat.chat_reopen_session"] = {kind = "block"},
    ["guide.heading.checklist_title"] = {kind = "text"},
    ["guide.heading.do_label"] = {kind = "text"},
    ["guide.heading.why_label"] = {kind = "text"},
    ["guide.label.char_line"] = {kind = "template", fields = {"character"}, slots = {"text"}, resultLimit = 455},
    ["guide.label.char_unknown"] = {kind = "text"},
    ["guide.label.character_level"] = {kind = "template", fields = {"level"}, slots = {"count"}, resultLimit = 80},
    ["guide.label.kicker"] = {kind = "template", fields = {"step", "total"}, slots = {"count", "count"}, resultLimit = 145},
    ["guide.label.kicker_optional"] = {kind = "text"},
    ["guide.label.step_assign"] = {kind = "text"},
    ["guide.label.step_auto"] = {kind = "text"},
    ["guide.label.step_manual"] = {kind = "text"},
    ["guide.label.step_summary"] = {kind = "text"},
    ["guide.label.step_target"] = {kind = "text"},
    ["guide.label.step_welcome"] = {kind = "text"},
    ["guide.label.step_wishlist"] = {kind = "text"},
    ["guide.label.word_cancelled"] = {kind = "text"},
    ["guide.label.word_chosen"] = {kind = "text"},
    ["guide.label.word_draft"] = {kind = "text"},
    ["guide.label.word_left_off"] = {kind = "text"},
    ["guide.label.word_left_on"] = {kind = "text"},
    ["guide.label.word_left_unknown"] = {kind = "text"},
    ["guide.label.word_linked"] = {kind = "text"},
    ["guide.label.word_mode_unknown"] = {kind = "text"},
    ["guide.label.word_review"] = {kind = "text"},
    ["guide.label.word_summary"] = {kind = "text"},
    ["guide.label.word_tried"] = {kind = "text"},
    ["guide.status.checking_word"] = {kind = "text"},
    ["guide.status.gate_assign"] = {kind = "text"},
    ["guide.status.gate_assign_rejected"] = {kind = "text"},
    ["guide.status.gate_assign_stale"] = {kind = "text"},
    ["guide.status.gate_assign_unknown"] = {kind = "text"},
    ["guide.status.gate_assign_waiting"] = {kind = "text"},
    ["guide.status.gate_auto"] = {kind = "text"},
    ["guide.status.gate_auto_unknown"] = {kind = "text"},
    ["guide.status.gate_manual"] = {kind = "text"},
    ["guide.status.gate_target"] = {kind = "text"},
    ["guide.status.gate_target_first"] = {kind = "text"},
    ["guide.status.gate_target_replace"] = {kind = "text"},
    ["guide.status.gate_target_save"] = {kind = "text"},
    ["guide.status.gate_target_select"] = {kind = "text"},
    ["guide.status.gate_target_unavailable"] = {kind = "text"},
    ["guide.status.gate_welcome"] = {kind = "text"},
    ["guide.status.gate_wishlist"] = {kind = "text"},
    ["guide.status.gate_wishlist_checked"] = {kind = "text"},
    ["guide.status.gate_wishlist_draft"] = {kind = "text"},
    ["guide.status.gate_wishlist_import"] = {kind = "text"},
    ["guide.status.not_word"] = {kind = "text"},
    ["guide.status.notes_blocked"] = {kind = "text"},
    ["guide.status.notes_builds_unavailable"] = {kind = "block"},
    ["guide.status.notes_builds_unconfirmed"] = {kind = "block"},
    ["guide.status.notes_empty"] = {kind = "text"},
    ["guide.status.notes_gone"] = {kind = "text"},
    ["guide.status.notes_import_changed"] = {kind = "text"},
    ["guide.status.notes_import_suspended"] = {kind = "block"},
    ["guide.status.notes_missing"] = {kind = "text"},
    ["guide.status.notes_no_editor"] = {kind = "text"},
    ["guide.status.notes_not_loaded"] = {kind = "text"},
    ["guide.status.notes_not_ready"] = {kind = "text"},
    ["guide.status.notes_plan_discarded"] = {kind = "block"},
    ["guide.status.notes_plan_refused"] = {kind = "text"},
    ["guide.status.notes_route"] = {kind = "template", fields = {"journal_target", "your_target"}, slots = {"text", "text"}, resultLimit = 1187, lines = true},
    ["guide.status.notes_startup"] = {kind = "text"},
    ["guide.status.notes_unavailable"] = {kind = "text"},
    ["guide.status.notice_epoch"] = {kind = "text"},
    ["guide.status.notice_owner"] = {kind = "text"},
    ["guide.status.notice_reselect"] = {kind = "block"},
    ["guide.status.notice_restored"] = {kind = "text"},
    ["guide.status.notice_session"] = {kind = "text"},
    ["guide.status.observed_word"] = {kind = "text"},
    ["guide.status.rejected_word"] = {kind = "text"},
    ["guide.status.skipped_word"] = {kind = "text"},
    ["guide.status.stale_word"] = {kind = "text"},
    ["guide.status.unavailable_word"] = {kind = "text"},
    ["guide.status.verified_word"] = {kind = "text"},
    ["guide.status.waiting_word"] = {kind = "text"},
    ["guide.title.assign_title"] = {kind = "text"},
    ["guide.title.auto_title"] = {kind = "text"},
    ["guide.title.finish_lessons_orbs_title"] = {kind = "text"},
    ["guide.title.finish_lessons_sharing_title"] = {kind = "text"},
    ["guide.title.finish_title_done"] = {kind = "text"},
    ["guide.title.finish_title_explore"] = {kind = "text"},
    ["guide.title.finish_title_open_many"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 165},
    ["guide.title.finish_title_open_one"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 162},
    ["guide.title.help_title"] = {kind = "template", fields = {"topic"}, slots = {"text"}, resultLimit = 385},
    ["guide.title.reference_title"] = {kind = "text"},
    ["guide.title.reference_topics_orbs_title"] = {kind = "text"},
    ["guide.title.reference_topics_rolling_title"] = {kind = "text"},
    ["guide.title.reference_topics_sharing_title"] = {kind = "text"},
    ["guide.title.reference_topics_start_title"] = {kind = "text"},
    ["guide.title.reference_topics_troubleshooting_title"] = {kind = "text"},
    ["guide.title.reference_topics_wishlists_title"] = {kind = "text"},
    ["guide.title.sim_title"] = {kind = "text"},
    ["guide.title.target_title"] = {kind = "text"},
    ["guide.title.welcome_paths_existing_title"] = {kind = "text"},
    ["guide.title.welcome_paths_explore_title"] = {kind = "text"},
    ["guide.title.welcome_paths_new_title"] = {kind = "text"},
    ["guide.title.welcome_title"] = {kind = "text"},
    ["guide.title.welcome_title_replay"] = {kind = "text"},
    ["guide.title.window"] = {kind = "text"},
    ["guide.title.wishlist_title"] = {kind = "text"},
    ["help.body.about_advanced_commands_1"] = {kind = "block"},
    ["help.body.about_advanced_commands_2"] = {kind = "text"},
    ["help.body.about_compatibility"] = {kind = "block"},
    ["help.body.about_dependency"] = {kind = "block"},
    ["help.body.about_engine"] = {kind = "block"},
    ["help.body.about_prototype_command"] = {kind = "text"},
    ["help.body.about_throttle"] = {kind = "block"},
    ["help.body.faq_auto_answer"] = {kind = "block"},
    ["help.body.faq_auto_off_sync_answer"] = {kind = "text"},
    ["help.body.faq_get_back_answer"] = {kind = "text"},
    ["help.body.faq_next_answer"] = {kind = "block"},
    ["help.body.faq_panel_size_answer"] = {kind = "block"},
    ["help.body.faq_pause_hide_answer_1"] = {kind = "block"},
    ["help.body.faq_pause_hide_answer_2"] = {kind = "block"},
    ["help.body.faq_which_wishlist_answer"] = {kind = "block"},
    ["help.body.orbs_after_run"] = {kind = "block"},
    ["help.body.orbs_before_start"] = {kind = "block"},
    ["help.body.orbs_blocked_1"] = {kind = "block"},
    ["help.body.orbs_blocked_2"] = {kind = "block"},
    ["help.body.orbs_blocked_3"] = {kind = "block"},
    ["help.body.orbs_blocked_4"] = {kind = "block"},
    ["help.body.orbs_blocked_5"] = {kind = "block"},
    ["help.body.orbs_blocked_6"] = {kind = "block"},
    ["help.body.orbs_closing"] = {kind = "block"},
    ["help.body.orbs_continue_exit_1"] = {kind = "block"},
    ["help.body.orbs_continue_exit_2"] = {kind = "block"},
    ["help.body.orbs_continue_exit_3"] = {kind = "block"},
    ["help.body.orbs_continue_exit_4"] = {kind = "block"},
    ["help.body.orbs_manual_confirm"] = {kind = "block"},
    ["help.body.orbs_reloading_1"] = {kind = "block"},
    ["help.body.orbs_reloading_2"] = {kind = "block"},
    ["help.body.orbs_requirements"] = {kind = "block"},
    ["help.body.orbs_run_steps_1"] = {kind = "block"},
    ["help.body.orbs_run_steps_2"] = {kind = "block"},
    ["help.body.orbs_run_steps_3"] = {kind = "block"},
    ["help.body.orbs_run_steps_4"] = {kind = "block"},
    ["help.body.orbs_run_steps_5"] = {kind = "block"},
    ["help.body.orbs_run_steps_6"] = {kind = "block"},
    ["help.body.orbs_unresolved_1"] = {kind = "block"},
    ["help.body.orbs_unresolved_2"] = {kind = "block"},
    ["help.body.rolling_auto_save_1"] = {kind = "block"},
    ["help.body.rolling_auto_save_2"] = {kind = "block"},
    ["help.body.rolling_auto_save_3"] = {kind = "block"},
    ["help.body.rolling_better_means_1"] = {kind = "block"},
    ["help.body.rolling_better_means_2"] = {kind = "block"},
    ["help.body.rolling_blocked_1"] = {kind = "block"},
    ["help.body.rolling_blocked_2"] = {kind = "block"},
    ["help.body.rolling_blocked_3"] = {kind = "block"},
    ["help.body.rolling_blocked_4"] = {kind = "block"},
    ["help.body.rolling_experimental_strategy_1"] = {kind = "block"},
    ["help.body.rolling_experimental_strategy_2"] = {kind = "block"},
    ["help.body.rolling_experimental_strategy_3"] = {kind = "text"},
    ["help.body.rolling_experimental_strategy_4"] = {kind = "block"},
    ["help.body.rolling_experimental_strategy_5"] = {kind = "block"},
    ["help.body.rolling_experimental_strategy_6"] = {kind = "block"},
    ["help.body.rolling_permissions_1"] = {kind = "block"},
    ["help.body.rolling_permissions_2"] = {kind = "block"},
    ["help.body.rolling_reading_panel_1"] = {kind = "block"},
    ["help.body.rolling_reading_panel_2"] = {kind = "block"},
    ["help.body.rolling_released_strategy_1"] = {kind = "block"},
    ["help.body.rolling_released_strategy_2"] = {kind = "block"},
    ["help.body.rolling_released_strategy_3"] = {kind = "block"},
    ["help.body.rolling_released_strategy_4"] = {kind = "block"},
    ["help.body.rolling_tomes_1"] = {kind = "block"},
    ["help.body.rolling_tomes_2"] = {kind = "block"},
    ["help.body.rolling_turn_on_steps_1"] = {kind = "block"},
    ["help.body.rolling_turn_on_steps_2"] = {kind = "template", fields = {"reroll_command", "freeze_command"}, slots = {"text", "text"}, resultLimit = 2048, lines = true},
    ["help.body.sharing_leaderboard"] = {kind = "block"},
    ["help.body.sharing_library_steps_1"] = {kind = "block"},
    ["help.body.sharing_library_steps_2"] = {kind = "block"},
    ["help.body.sharing_library_steps_3"] = {kind = "block"},
    ["help.body.sharing_library_steps_4"] = {kind = "block"},
    ["help.body.sharing_library_steps_5"] = {kind = "block"},
    ["help.body.sharing_locked_targets"] = {kind = "block"},
    ["help.body.sharing_names"] = {kind = "block"},
    ["help.body.sharing_removing"] = {kind = "block"},
    ["help.body.sharing_sync_now"] = {kind = "block"},
    ["help.body.sharing_sync_sends_1"] = {kind = "block"},
    ["help.body.sharing_sync_sends_2"] = {kind = "block"},
    ["help.body.sharing_sync_sends_3"] = {kind = "block"},
    ["help.body.sharing_sync_sends_4"] = {kind = "block"},
    ["help.body.sharing_sync_sends_5"] = {kind = "block"},
    ["help.body.sharing_sync_sends_6"] = {kind = "block"},
    ["help.body.sharing_sync_words"] = {kind = "block"},
    ["help.body.start_before_auto_on"] = {kind = "block"},
    ["help.body.start_counts_1"] = {kind = "block"},
    ["help.body.start_counts_2"] = {kind = "block"},
    ["help.body.start_counts_3"] = {kind = "block"},
    ["help.body.start_experimental_backup"] = {kind = "block"},
    ["help.body.start_first_task"] = {kind = "block"},
    ["help.body.start_guided_steps_1"] = {kind = "block"},
    ["help.body.start_guided_steps_2"] = {kind = "block"},
    ["help.body.start_more_detail"] = {kind = "text"},
    ["help.body.start_other_routes_1"] = {kind = "block"},
    ["help.body.start_other_routes_2"] = {kind = "block"},
    ["help.body.start_purpose"] = {kind = "block"},
    ["help.body.start_reference_later"] = {kind = "block"},
    ["help.body.start_saved_builds_1"] = {kind = "block"},
    ["help.body.start_saved_builds_2"] = {kind = "text"},
    ["help.body.start_setup_steps_1"] = {kind = "block"},
    ["help.body.start_setup_steps_2"] = {kind = "block"},
    ["help.body.start_setup_steps_3"] = {kind = "block"},
    ["help.body.start_words"] = {kind = "block"},
    ["help.body.topic_about_1"] = {kind = "text"},
    ["help.body.topic_about_2"] = {kind = "block"},
    ["help.body.topic_faq_1"] = {kind = "text"},
    ["help.body.topic_faq_2"] = {kind = "text"},
    ["help.body.topic_orbs_1"] = {kind = "block"},
    ["help.body.topic_orbs_2"] = {kind = "text"},
    ["help.body.topic_rolling_1"] = {kind = "block"},
    ["help.body.topic_rolling_2"] = {kind = "block"},
    ["help.body.topic_sharing_1"] = {kind = "block"},
    ["help.body.topic_sharing_2"] = {kind = "block"},
    ["help.body.topic_start_1"] = {kind = "block"},
    ["help.body.topic_start_2"] = {kind = "block"},
    ["help.body.topic_troubleshooting_1"] = {kind = "block"},
    ["help.body.topic_troubleshooting_2"] = {kind = "block"},
    ["help.body.topic_wishlists_1"] = {kind = "block"},
    ["help.body.topic_wishlists_2"] = {kind = "block"},
    ["help.body.troubleshooting_commands_1"] = {kind = "block"},
    ["help.body.troubleshooting_commands_2"] = {kind = "template", fields = {"policy_command"}, slots = {"text"}, resultLimit = 2048, lines = true},
    ["help.body.troubleshooting_diagnostics"] = {kind = "block"},
    ["help.body.troubleshooting_first"] = {kind = "block"},
    ["help.body.troubleshooting_loading"] = {kind = "block"},
    ["help.body.troubleshooting_report_file"] = {kind = "block"},
    ["help.body.troubleshooting_report_steps_1"] = {kind = "block"},
    ["help.body.troubleshooting_report_steps_2"] = {kind = "block"},
    ["help.body.troubleshooting_reporting_fails"] = {kind = "block"},
    ["help.body.troubleshooting_roll_record_1"] = {kind = "block"},
    ["help.body.troubleshooting_roll_record_2"] = {kind = "block"},
    ["help.body.troubleshooting_roll_record_3"] = {kind = "block"},
    ["help.body.troubleshooting_turning_off_1"] = {kind = "block"},
    ["help.body.troubleshooting_turning_off_2"] = {kind = "block"},
    ["help.body.troubleshooting_updates"] = {kind = "block"},
    ["help.body.wishlists_editor_steps_1"] = {kind = "block"},
    ["help.body.wishlists_editor_steps_2"] = {kind = "block"},
    ["help.body.wishlists_editor_steps_3"] = {kind = "block"},
    ["help.body.wishlists_import_locked"] = {kind = "block"},
    ["help.body.wishlists_limits"] = {kind = "block"},
    ["help.body.wishlists_locked_targets"] = {kind = "block"},
    ["help.button.assign_wishlist"] = {kind = "text"},
    ["help.button.close"] = {kind = "text"},
    ["help.button.next"] = {kind = "text"},
    ["help.button.previous"] = {kind = "text"},
    ["help.button.setup_checklist"] = {kind = "text"},
    ["help.button.setup_welcome"] = {kind = "text"},
    ["help.button.start_page"] = {kind = "text"},
    ["help.button.topic_about"] = {kind = "text"},
    ["help.button.topic_faq"] = {kind = "text"},
    ["help.button.topic_orbs"] = {kind = "text"},
    ["help.button.topic_rolling"] = {kind = "text"},
    ["help.button.topic_sharing"] = {kind = "text"},
    ["help.button.topic_start"] = {kind = "text"},
    ["help.button.topic_troubleshooting"] = {kind = "text"},
    ["help.button.topic_wishlists"] = {kind = "text"},
    ["help.button.wishlist_editor"] = {kind = "text"},
    ["help.error.assign_after_startup"] = {kind = "text"},
    ["help.error.assignment_route_unavailable"] = {kind = "text"},
    ["help.error.automation_settings_after_startup"] = {kind = "text"},
    ["help.error.automation_settings_did_not_open"] = {kind = "text"},
    ["help.error.automation_settings_unavailable"] = {kind = "text"},
    ["help.error.checklist_unavailable"] = {kind = "text"},
    ["help.error.editor_after_startup"] = {kind = "text"},
    ["help.error.editor_did_not_open"] = {kind = "text"},
    ["help.error.editor_unavailable"] = {kind = "text"},
    ["help.error.guide_unavailable"] = {kind = "text"},
    ["help.error.guide_unavailable_now"] = {kind = "text"},
    ["help.error.guide_warning_open"] = {kind = "text"},
    ["help.error.journal_route_unavailable"] = {kind = "text"},
    ["help.error.logs_after_startup"] = {kind = "text"},
    ["help.error.logs_did_not_open"] = {kind = "text"},
    ["help.error.logs_unavailable"] = {kind = "text"},
    ["help.error.orbs_did_not_open"] = {kind = "text"},
    ["help.error.orbs_unavailable"] = {kind = "text"},
    ["help.error.progression_button_missing"] = {kind = "text"},
    ["help.error.setup_unavailable_now"] = {kind = "text"},
    ["help.error.setup_unavailable_yet"] = {kind = "text"},
    ["help.error.setup_warning_open"] = {kind = "text"},
    ["help.error.support_did_not_open"] = {kind = "text"},
    ["help.error.support_unavailable"] = {kind = "text"},
    ["help.error.sync_settings_after_startup"] = {kind = "text"},
    ["help.error.sync_settings_did_not_open"] = {kind = "text"},
    ["help.error.sync_settings_unavailable"] = {kind = "text"},
    ["help.error.topic_no_screen"] = {kind = "text"},
    ["help.heading.auto_now"] = {kind = "text"},
    ["help.heading.open_window"] = {kind = "text"},
    ["help.heading.topic_about"] = {kind = "text"},
    ["help.heading.topic_faq"] = {kind = "text"},
    ["help.heading.topic_orbs"] = {kind = "text"},
    ["help.heading.topic_rolling"] = {kind = "text"},
    ["help.heading.topic_sharing"] = {kind = "text"},
    ["help.heading.topic_start"] = {kind = "text"},
    ["help.heading.topic_troubleshooting"] = {kind = "text"},
    ["help.heading.topic_wishlists"] = {kind = "text"},
    ["help.label.faq_auto_off_sync_question"] = {kind = "text"},
    ["help.label.faq_auto_question"] = {kind = "text"},
    ["help.label.faq_get_back_question"] = {kind = "text"},
    ["help.label.faq_next_question"] = {kind = "text"},
    ["help.label.faq_panel_size_question"] = {kind = "text"},
    ["help.label.faq_pause_hide_question"] = {kind = "text"},
    ["help.label.faq_which_wishlist_question"] = {kind = "text"},
    ["help.label.page_position"] = {kind = "template", fields = {"page", "total"}, slots = {"count", "count"}, resultLimit = 100},
    ["help.label.reference_note"] = {kind = "text"},
    ["help.tab.about"] = {kind = "text"},
    ["help.tab.faq"] = {kind = "text"},
    ["help.tab.orbs"] = {kind = "text"},
    ["help.tab.rolling"] = {kind = "text"},
    ["help.tab.sharing"] = {kind = "text"},
    ["help.tab.start"] = {kind = "text"},
    ["help.tab.troubleshooting"] = {kind = "text"},
    ["help.tab.wishlists"] = {kind = "text"},
    ["help.title.page_about"] = {kind = "text"},
    ["help.title.page_faq"] = {kind = "text"},
    ["help.title.page_orbs"] = {kind = "text"},
    ["help.title.page_rolling"] = {kind = "text"},
    ["help.title.page_sharing"] = {kind = "text"},
    ["help.title.page_start"] = {kind = "text"},
    ["help.title.page_troubleshooting"] = {kind = "text"},
    ["help.title.page_wishlists"] = {kind = "text"},
    ["help.title.window"] = {kind = "template", fields = {"page"}, slots = {"text"}, resultLimit = 400},
    ["settings.button.guided_setup"] = {kind = "text"},
    ["settings.button.log_viewer"] = {kind = "text"},
    ["settings.button.next"] = {kind = "text"},
    ["settings.button.open_library_sync"] = {kind = "text"},
    ["settings.button.previous"] = {kind = "text"},
    ["settings.button.support_report"] = {kind = "text"},
    ["settings.button.welcome_information"] = {kind = "text"},
    ["settings.label.category_appearance"] = {kind = "text"},
    ["settings.label.category_automation"] = {kind = "text"},
    ["settings.label.category_display"] = {kind = "text"},
    ["settings.label.category_language"] = {kind = "text"},
    ["settings.label.category_notices"] = {kind = "text"},
    ["settings.label.category_support"] = {kind = "text"},
    ["settings.label.category_sync"] = {kind = "text"},
    ["settings.label.current_sync"] = {kind = "template", fields = {"mode"}, slots = {"text"}, resultLimit = 300},
    ["settings.label.long_setting"] = {kind = "text"},
    ["settings.note.category_appearance"] = {kind = "text"},
    ["settings.note.category_automation"] = {kind = "text"},
    ["settings.note.category_display"] = {kind = "text"},
    ["settings.note.category_language"] = {kind = "text"},
    ["settings.note.category_notices"] = {kind = "text"},
    ["settings.note.category_support"] = {kind = "text"},
    ["settings.note.category_sync"] = {kind = "text"},
    ["settings.note.guided_setup"] = {kind = "text"},
    ["settings.note.hover_explanation"] = {kind = "text"},
    ["settings.note.library_sync_dialog"] = {kind = "text"},
    ["settings.note.welcome_information"] = {kind = "text"},
    ["settings.status.not_available"] = {kind = "text"},
    ["settings.tab.support"] = {kind = "text"},
    ["settings.tab.sync"] = {kind = "text"},
    ["settings.value.sync_automatic"] = {kind = "text"},
    ["settings.value.sync_manual"] = {kind = "text"},
    ["settings.value.sync_off"] = {kind = "text"},
    ["settings.value.sync_unknown"] = {kind = "text"},
    ["setup.body.sync_automatic"] = {kind = "block"},
    ["setup.body.sync_reference"] = {kind = "template", fields = {"sync"}, slots = {"text"}, resultLimit = 1200},
    ["setup.body.welcome_auto_replace"] = {kind = "block"},
    ["setup.body.welcome_existing_build"] = {kind = "text"},
    ["setup.body.welcome_starting_fresh"] = {kind = "text"},
    ["setup.button.assign_wishlist"] = {kind = "text"},
    ["setup.button.browse_community_builds"] = {kind = "text"},
    ["setup.button.close"] = {kind = "text"},
    ["setup.button.help"] = {kind = "text"},
    ["setup.button.help_guided_setup"] = {kind = "text"},
    ["setup.button.import_create_wishlist"] = {kind = "text"},
    ["setup.button.open_leaderboard"] = {kind = "text"},
    ["setup.button.orbs_lost_memories"] = {kind = "text"},
    ["setup.button.reference"] = {kind = "text"},
    ["setup.button.set_up_current_build"] = {kind = "text"},
    ["setup.button.wishlist_editor"] = {kind = "text"},
    ["setup.chat.coach_not_saved"] = {kind = "block"},
    ["setup.chat.welcome_not_saved"] = {kind = "block"},
    ["setup.error.assign_unavailable"] = {kind = "text"},
    ["setup.error.editor_unavailable"] = {kind = "text"},
    ["setup.error.guide_unavailable"] = {kind = "text"},
    ["setup.heading.checklist_status"] = {kind = "text"},
    ["setup.label.checklist_subtitle"] = {kind = "text"},
    ["setup.label.welcome_subtitle"] = {kind = "text"},
    ["setup.note.information_only"] = {kind = "text"},
    ["setup.note.reopen_help"] = {kind = "text"},
    ["setup.status.steps_done"] = {kind = "template", fields = {"done", "total"}, slots = {"count", "count"}, resultLimit = 300},
    ["setup.status.steps_done_open"] = {kind = "template", fields = {"done", "total"}, slots = {"count", "count"}, resultLimit = 400},
    ["setup.title.checklist"] = {kind = "text"},
    ["setup.title.information_only"] = {kind = "text"},
    ["setup.title.welcome"] = {kind = "text"},
    ["setup.value.checklist_row"] = {kind = "template", fields = {"mark", "label", "status"}, slots = {"text", "text", "text"}, resultLimit = 1600},
    ["workspace.error.did_not_open"] = {kind = "text"},
    ["workspace.error.draft_protection_unavailable"] = {kind = "text"},
    ["workspace.error.library_unavailable"] = {kind = "text"},
    ["workspace.error.plan_action_refused"] = {kind = "text"},
    ["workspace.error.plan_action_unavailable"] = {kind = "text"},
    ["workspace.error.plan_unavailable"] = {kind = "text"},
    ["workspace.error.records_unavailable"] = {kind = "text"},
    ["workspace.error.unavailable"] = {kind = "text"},
    ["workspace.error.unknown_explore_view"] = {kind = "text"},
    ["workspace.error.unknown_workspace"] = {kind = "text"},
    ["workspace.tab.explore"] = {kind = "text"},
    ["workspace.tab.plan"] = {kind = "text"},
    ["workspace.tab.records"] = {kind = "text"},
    ["workspace.tooltip.explore"] = {kind = "text"},
    ["workspace.tooltip.plan"] = {kind = "text"},
    ["workspace.tooltip.records"] = {kind = "text"},
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
    -- integration (8)
    ["journal.button.assign_in_my_builds"] = {kind = "text"},
    ["journal.menu.unassign_wishlist"] = {kind = "text"},
    ["library.button.stop_sharing"] = {kind = "text"},
    ["library.status.updating_results"] = {kind = "text"},
    ["log.button.prepare_full_report"] = {kind = "text"},
    ["log.button.select_page"] = {kind = "text"},
    ["support.button.copy_summary"] = {kind = "text"},
    ["support.button.prepare_report_file"] = {kind = "text"},
    -- integration2 (10)
    ["editor.button.confirm_locked_assign"] = {kind = "text"},
    ["editor.button.confirm_locked_edit"] = {kind = "text"},
    ["editor.button.create_and_assign"] = {kind = "text"},
    ["editor.button.create_unassigned"] = {kind = "text"},
    ["editor.button.save_and_assign"] = {kind = "text"},
    ["editor.button.save_changes"] = {kind = "text"},
    ["panel.body.no_echo_choice"] = {kind = "text"},
    ["panel.menu.hide_panel"] = {kind = "text"},
    ["panel.status.auto_on_paused"] = {kind = "text"},
    ["panel.tooltip.menu_status"] = {kind = "template", fields = {"status"}, slots = {"text"}, resultLimit = 1100},
    -- journal (202)
    ["journal.body.assign_note"] = {kind = "text"},
    ["journal.body.change_in_my_builds"] = {kind = "text"},
    ["journal.body.compare_active"] = {kind = "text"},
    ["journal.body.family_coverage"] = {kind = "block"},
    ["journal.body.purpose"] = {kind = "block"},
    ["journal.body.set_in_my_builds"] = {kind = "block"},
    ["journal.button.assign_cancel"] = {kind = "text"},
    ["journal.button.assign_confirm"] = {kind = "text"},
    ["journal.button.help"] = {kind = "text"},
    ["journal.button.hide_details"] = {kind = "text"},
    ["journal.button.new_wishlist"] = {kind = "text"},
    ["journal.button.reference"] = {kind = "text"},
    ["journal.button.show_details"] = {kind = "text"},
    ["journal.chat.assigned"] = {kind = "template", fields = {"wishlist", "target"}, slots = {"text", "text"}, resultLimit = 2048},
    ["journal.chat.associate_first"] = {kind = "text"},
    ["journal.chat.chooser_coach"] = {kind = "block"},
    ["journal.chat.chooser_unconfirmed"] = {kind = "block"},
    ["journal.chat.consent_unavailable"] = {kind = "block"},
    ["journal.chat.editor_unavailable"] = {kind = "text"},
    ["journal.chat.first_run_unavailable"] = {kind = "text"},
    ["journal.chat.owner_changed"] = {kind = "block"},
    ["journal.chat.progression_button_missing"] = {kind = "block"},
    ["journal.chat.select_failed"] = {kind = "text"},
    ["journal.heading.about_page"] = {kind = "text"},
    ["journal.heading.build_progress"] = {kind = "text"},
    ["journal.heading.missing_count"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["journal.heading.off_wishlist_count"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["journal.label.counts_missing"] = {kind = "template", fields = {"open", "close", "count"}, slots = {"text", "text", "count"}, resultLimit = 512},
    ["journal.label.counts_off_listed"] = {kind = "template", fields = {"open", "close", "count"}, slots = {"text", "text", "count"}, resultLimit = 512},
    ["journal.label.counts_off_none"] = {kind = "template", fields = {"open", "close"}, slots = {"text", "text"}, resultLimit = 512},
    ["journal.label.counts_off_unavailable"] = {kind = "template", fields = {"open", "close"}, slots = {"text", "text"}, resultLimit = 512},
    ["journal.label.counts_represented"] = {kind = "template", fields = {"open", "close", "represented", "total"}, slots = {"text", "text", "count", "count"}, resultLimit = 512},
    ["journal.label.empty_saved_build"] = {kind = "text"},
    ["journal.label.intro"] = {kind = "text"},
    ["journal.label.no_saved_build"] = {kind = "text"},
    ["journal.label.picker_role_hint"] = {kind = "text"},
    ["journal.label.saved_build_number"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 256},
    ["journal.label.select_wishlist"] = {kind = "text"},
    ["journal.label.selected_marker"] = {kind = "text"},
    ["journal.label.target_first_run"] = {kind = "text"},
    ["journal.label.target_saved_build"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048},
    ["journal.label.unnamed_wishlist"] = {kind = "text"},
    ["journal.popup.assign_auto_on"] = {kind = "block"},
    ["journal.popup.assign_question"] = {kind = "template", fields = {"wishlist", "target"}, slots = {"text", "text"}, resultLimit = 2048},
    ["journal.status.data_unreadable"] = {kind = "text"},
    ["journal.status.data_unreadable_no_sections"] = {kind = "text"},
    ["journal.status.estimate"] = {kind = "template", fields = {"estimate"}, slots = {"text"}, resultLimit = 1024},
    ["journal.status.estimate_unavailable"] = {kind = "text"},
    ["journal.status.listed_above"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["journal.status.missing_families"] = {kind = "template", fields = {"count", "names"}, slots = {"count", "text"}, resultLimit = 2048},
    ["journal.status.missing_families_more"] = {kind = "template", fields = {"count", "names", "more"}, slots = {"count", "text", "count"}, resultLimit = 2048},
    ["journal.status.missing_one_family"] = {kind = "template", fields = {"count", "names"}, slots = {"count", "text"}, resultLimit = 2048},
    ["journal.status.no_data_yet"] = {kind = "text"},
    ["journal.status.no_families_requested"] = {kind = "text"},
    ["journal.status.no_sections"] = {kind = "text"},
    ["journal.status.no_wishlist"] = {kind = "text"},
    ["journal.status.none_missing"] = {kind = "block"},
    ["journal.status.picker_no_others"] = {kind = "text"},
    ["journal.status.picker_none_found"] = {kind = "text"},
    ["journal.status.row_missing"] = {kind = "text"},
    ["journal.status.row_off_wishlist"] = {kind = "text"},
    ["journal.status.summary_missing"] = {kind = "block"},
    ["journal.status.tome_disable_pending"] = {kind = "text"},
    ["journal.status.tome_enable_pending"] = {kind = "text"},
    ["journal.status.tome_request_pending"] = {kind = "text"},
    ["journal.status.unknown_bad_pending"] = {kind = "block"},
    ["journal.status.unknown_contradictory"] = {kind = "block"},
    ["journal.status.unknown_grammar"] = {kind = "block"},
    ["journal.status.unknown_no_pending"] = {kind = "block"},
    ["journal.tab.nexus_progress"] = {kind = "text"},
    ["journal.title.picker_assign_to"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 512},
    ["journal.title.picker_empty_refused"] = {kind = "text"},
    ["journal.title.picker_first_run"] = {kind = "text"},
    ["journal.title.picker_wishlists"] = {kind = "text"},
    ["journal.tooltip.auto_replace_orbs"] = {kind = "block"},
    ["journal.tooltip.auto_replace_warning"] = {kind = "block"},
    ["journal.tooltip.builds_closes_page"] = {kind = "text"},
    ["journal.tooltip.counts_heading"] = {kind = "text"},
    ["journal.tooltip.details_contents"] = {kind = "block"},
    ["journal.tooltip.edit_assigned"] = {kind = "block"},
    ["journal.tooltip.edit_assigned_heading"] = {kind = "text"},
    ["journal.tooltip.edit_first_run"] = {kind = "block"},
    ["journal.tooltip.edit_first_run_heading"] = {kind = "text"},
    ["journal.tooltip.empty_slot_name_first_run"] = {kind = "block"},
    ["journal.tooltip.empty_slot_no_assign"] = {kind = "block"},
    ["journal.tooltip.empty_slot_refused"] = {kind = "block"},
    ["journal.tooltip.help_opens_guide"] = {kind = "block"},
    ["journal.tooltip.new_wishlist"] = {kind = "text"},
    ["journal.tooltip.off_wishlist_listed"] = {kind = "block"},
    ["journal.tooltip.off_wishlist_none"] = {kind = "block"},
    ["journal.tooltip.off_wishlist_unavailable"] = {kind = "block"},
    ["journal.tooltip.picker_edit_wishlist"] = {kind = "text"},
    ["journal.tooltip.picker_row_heading"] = {kind = "text"},
    ["journal.tooltip.picker_row_sets"] = {kind = "text"},
    ["journal.tooltip.picker_row_target"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048},
    ["journal.tooltip.reference_opens_manual"] = {kind = "block"},
    ["journal.tooltip.row_icon_neutral"] = {kind = "text"},
    ["journal.tooltip.row_missing"] = {kind = "text"},
    ["journal.tooltip.row_off_wishlist"] = {kind = "block"},
    ["journal.tooltip.selector_assigns"] = {kind = "block"},
    ["journal.tooltip.selector_heading"] = {kind = "text"},
    ["journal.tooltip.source_text"] = {kind = "template", fields = {"text"}, slots = {"text"}, resultLimit = 2048},
    ["journal.tooltip.tab_opens_page"] = {kind = "text"},
    ["journal.tooltip.tome_control_id"] = {kind = "template", fields = {"id"}, slots = {"text"}, resultLimit = 256},
    ["journal.tooltip.tome_disable_requested"] = {kind = "text"},
    ["journal.tooltip.tome_echo_many"] = {kind = "template", fields = {"names"}, slots = {"text"}, resultLimit = 2048},
    ["journal.tooltip.tome_echo_one"] = {kind = "template", fields = {"names"}, slots = {"text"}, resultLimit = 2048},
    ["journal.tooltip.tome_enable_requested"] = {kind = "text"},
    ["journal.tooltip.tome_icon_member"] = {kind = "text"},
    ["journal.tooltip.tome_icon_neutral"] = {kind = "text"},
    ["journal.tooltip.tome_icon_spell"] = {kind = "text"},
    ["journal.tooltip.tome_icon_unstated"] = {kind = "text"},
    ["journal.tooltip.tome_last_observed"] = {kind = "template", fields = {"state"}, slots = {"text"}, resultLimit = 1024},
    ["journal.tooltip.tome_mirror"] = {kind = "template", fields = {"state"}, slots = {"text"}, resultLimit = 1024},
    ["journal.tooltip.tome_request_unknown"] = {kind = "block"},
    ["journal.tooltip.tome_scope"] = {kind = "block"},
    ["journal.tooltip.tome_stale"] = {kind = "text"},
    ["journal.tooltip.unassign_empty_slot"] = {kind = "block"},
    ["journal.tooltip.unassign_keeps"] = {kind = "text"},
    ["journal.tooltip.unassign_no_build_change"] = {kind = "text"},
    ["journal.value.tome_unknown"] = {kind = "text"},
    ["plan.button.add"] = {kind = "text"},
    ["plan.button.added"] = {kind = "text"},
    ["plan.button.hide"] = {kind = "text"},
    ["plan.button.load_saved"] = {kind = "text"},
    ["plan.button.open_draft"] = {kind = "text"},
    ["plan.button.popup_cancel"] = {kind = "text"},
    ["plan.button.popup_load_saved"] = {kind = "text"},
    ["plan.button.popup_remove_saved"] = {kind = "text"},
    ["plan.button.remove"] = {kind = "text"},
    ["plan.button.reset_pool"] = {kind = "text"},
    ["plan.button.save_pool"] = {kind = "text"},
    ["plan.button.set"] = {kind = "text"},
    ["plan.button.set_pending"] = {kind = "text"},
    ["plan.heading.catalog"] = {kind = "text"},
    ["plan.heading.pool"] = {kind = "text"},
    ["plan.label.budget"] = {kind = "template", fields = {"alternatives", "chosen"}, slots = {"count", "count"}, resultLimit = 512},
    ["plan.label.catalog_row"] = {kind = "template", fields = {"id", "quality", "name"}, slots = {"text", "text", "text"}, resultLimit = 1024},
    ["plan.label.count_help"] = {kind = "block"},
    ["plan.label.pool_row"] = {kind = "template", fields = {"count", "id", "quality", "max_stack", "name"}, slots = {"text", "text", "text", "text", "text"}, resultLimit = 1024},
    ["plan.note.why_changed_after_asked"] = {kind = "text"},
    ["plan.note.why_count_pending"] = {kind = "text"},
    ["plan.note.why_future"] = {kind = "text"},
    ["plan.note.why_invalid_session"] = {kind = "text"},
    ["plan.note.why_load_invalid"] = {kind = "text"},
    ["plan.note.why_loading"] = {kind = "text"},
    ["plan.note.why_not_observed"] = {kind = "text"},
    ["plan.note.why_read_only"] = {kind = "text"},
    ["plan.note.why_receipt_read_only"] = {kind = "text"},
    ["plan.note.why_saved_data_changed"] = {kind = "text"},
    ["plan.note.why_saved_pool_changed"] = {kind = "text"},
    ["plan.note.why_unavailable"] = {kind = "text"},
    ["plan.note.why_unreadable"] = {kind = "text"},
    ["plan.popup.clear_consequence"] = {kind = "text"},
    ["plan.popup.clear_question"] = {kind = "text"},
    ["plan.popup.load_consequence"] = {kind = "block"},
    ["plan.popup.load_question"] = {kind = "text"},
    ["plan.status.catalog_changed_many"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 1024},
    ["plan.status.catalog_changed_one"] = {kind = "block"},
    ["plan.status.persist_ask_clear"] = {kind = "text"},
    ["plan.status.persist_ask_load"] = {kind = "text"},
    ["plan.status.persist_changed"] = {kind = "text"},
    ["plan.status.persist_cleared"] = {kind = "text"},
    ["plan.status.persist_empty"] = {kind = "block"},
    ["plan.status.persist_future"] = {kind = "block"},
    ["plan.status.persist_has_saved"] = {kind = "text"},
    ["plan.status.persist_loaded"] = {kind = "text"},
    ["plan.status.persist_loading"] = {kind = "text"},
    ["plan.status.persist_matches"] = {kind = "text"},
    ["plan.status.persist_new"] = {kind = "text"},
    ["plan.status.persist_none"] = {kind = "block"},
    ["plan.status.persist_nothing"] = {kind = "text"},
    ["plan.status.persist_pending"] = {kind = "text"},
    ["plan.status.persist_read_only"] = {kind = "text"},
    ["plan.status.persist_read_only_load"] = {kind = "text"},
    ["plan.status.persist_saved"] = {kind = "text"},
    ["plan.status.persist_saved_empty"] = {kind = "text"},
    ["plan.status.persist_stale"] = {kind = "block"},
    ["plan.status.persist_unavailable"] = {kind = "text"},
    ["plan.status.persist_unreadable"] = {kind = "block"},
    ["plan.status.persist_unsaved"] = {kind = "text"},
    ["plan.status.persist_unsaved_empty"] = {kind = "block"},
    ["plan.status.reason_catalog_changed"] = {kind = "text"},
    ["plan.status.reason_catalog_unavailable"] = {kind = "text"},
    ["plan.status.reason_count_pending"] = {kind = "text"},
    ["plan.status.reason_default"] = {kind = "text"},
    ["plan.status.reason_editor_changed"] = {kind = "text"},
    ["plan.status.reason_invalid_alternatives"] = {kind = "text"},
    ["plan.status.reason_invalid_catalog"] = {kind = "block"},
    ["plan.status.reason_invalid_selection"] = {kind = "text"},
    ["plan.status.reason_ordinary_limit"] = {kind = "text"},
    ["plan.status.reason_plan_changed"] = {kind = "text"},
    ["plan.status.reason_stack_limit"] = {kind = "text"},
    ["plan.status.reason_unsupported_role"] = {kind = "text"},
    ["plan.status.refused_clear"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1024},
    ["plan.status.refused_load"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1024},
    ["plan.status.refused_save"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1024},
    ["plan.status.unverified_clear"] = {kind = "block"},
    ["plan.status.unverified_clear_restored"] = {kind = "block"},
    ["plan.status.unverified_save"] = {kind = "block"},
    ["plan.status.unverified_save_restored"] = {kind = "block"},
    ["plan.title.plan_alternatives"] = {kind = "text"},
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
    -- orb (436)
    ["orb.body.copy_report_help"] = {kind = "text"},
    ["orb.body.history_consumed_source"] = {kind = "template", fields = {"echo"}, slots = {"text"}, resultLimit = 386},
    ["orb.body.history_eligible_surplus"] = {kind = "template", fields = {"value"}, slots = {"text"}, resultLimit = 588},
    ["orb.body.history_operation"] = {kind = "template", fields = {"number", "result"}, slots = {"text", "text"}, resultLimit = 696},
    ["orb.body.history_proposed_source"] = {kind = "template", fields = {"echo"}, slots = {"text"}, resultLimit = 490},
    ["orb.body.history_recycle_candidate"] = {kind = "text"},
    ["orb.body.history_select_operation"] = {kind = "text"},
    ["orb.body.history_since_start"] = {kind = "template", fields = {"seconds"}, slots = {"text"}, resultLimit = 404},
    ["orb.body.history_technical"] = {kind = "template", fields = {"serial", "state", "source", "selected", "kind", "obtained"}, slots = {"text", "text", "text", "text", "text", "text"}, resultLimit = 2048},
    ["orb.body.start_approval"] = {kind = "block"},
    ["orb.body.start_approval_history"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 1024, lines = true},
    ["orb.body.start_approval_history_full"] = {kind = "template", fields = {"count", "risk"}, slots = {"count", "text"}, resultLimit = 2048, lines = true},
    ["orb.body.timeline_choice_proposed"] = {kind = "text"},
    ["orb.body.timeline_confirmed"] = {kind = "text"},
    ["orb.body.timeline_offer"] = {kind = "text"},
    ["orb.body.timeline_requested"] = {kind = "text"},
    ["orb.body.timeline_spend_unconfirmed"] = {kind = "text"},
    ["orb.body.timeline_stored"] = {kind = "text"},
    ["orb.body.timeline_unconfirmed"] = {kind = "text"},
    ["orb.button.advanced"] = {kind = "text"},
    ["orb.button.cancel_review"] = {kind = "text"},
    ["orb.button.check_progress"] = {kind = "text"},
    ["orb.button.clear_exclusions"] = {kind = "text"},
    ["orb.button.clear_focus"] = {kind = "text"},
    ["orb.button.close"] = {kind = "text"},
    ["orb.button.confirm_new_run"] = {kind = "text"},
    ["orb.button.continue_cancel"] = {kind = "text"},
    ["orb.button.continue_check"] = {kind = "text"},
    ["orb.button.continue_confirm"] = {kind = "text"},
    ["orb.button.continue_open"] = {kind = "text"},
    ["orb.button.copy_report"] = {kind = "text"},
    ["orb.button.details"] = {kind = "text"},
    ["orb.button.exclude"] = {kind = "text"},
    ["orb.button.help"] = {kind = "text"},
    ["orb.button.hide_until_next_run"] = {kind = "text"},
    ["orb.button.history_current"] = {kind = "text"},
    ["orb.button.history_previous"] = {kind = "text"},
    ["orb.button.max"] = {kind = "text"},
    ["orb.button.mini_panel"] = {kind = "text"},
    ["orb.button.my_builds"] = {kind = "text"},
    ["orb.button.open_orbs"] = {kind = "text"},
    ["orb.button.page_next"] = {kind = "text"},
    ["orb.button.page_previous"] = {kind = "text"},
    ["orb.button.pause"] = {kind = "text"},
    ["orb.button.recheck"] = {kind = "text"},
    ["orb.button.reference"] = {kind = "text"},
    ["orb.button.resume"] = {kind = "text"},
    ["orb.button.review_check"] = {kind = "text"},
    ["orb.button.review_outcome"] = {kind = "text"},
    ["orb.button.review_target"] = {kind = "text"},
    ["orb.button.select_all"] = {kind = "text"},
    ["orb.button.start"] = {kind = "text"},
    ["orb.button.start_new_run"] = {kind = "text"},
    ["orb.button.stop"] = {kind = "text"},
    ["orb.button.why_blocked"] = {kind = "text"},
    ["orb.column.history_replaced"] = {kind = "text"},
    ["orb.column.history_replacement"] = {kind = "text"},
    ["orb.column.history_result"] = {kind = "text"},
    ["orb.column.history_why"] = {kind = "text"},
    ["orb.error.all_rolled_complete"] = {kind = "text"},
    ["orb.error.assign_resolved"] = {kind = "text"},
    ["orb.error.assignment_fixed"] = {kind = "text"},
    ["orb.error.auto_accept_first"] = {kind = "text"},
    ["orb.error.balance_invalid"] = {kind = "text"},
    ["orb.error.balance_server_invalid"] = {kind = "text"},
    ["orb.error.balance_state_unavailable"] = {kind = "text"},
    ["orb.error.balance_unsupported"] = {kind = "text"},
    ["orb.error.balance_waiting"] = {kind = "text"},
    ["orb.error.balance_waiting_recheck"] = {kind = "text"},
    ["orb.error.catalog_not_ready"] = {kind = "text"},
    ["orb.error.changed_while_confirming"] = {kind = "text"},
    ["orb.error.choose_echo"] = {kind = "text"},
    ["orb.error.choose_maximum"] = {kind = "text"},
    ["orb.error.confirmation_expired"] = {kind = "text"},
    ["orb.error.echo_data_waiting"] = {kind = "text"},
    ["orb.error.exclusions_fixed"] = {kind = "text"},
    ["orb.error.limit_range"] = {kind = "text"},
    ["orb.error.max_changed_start"] = {kind = "text"},
    ["orb.error.max_fixed"] = {kind = "text"},
    ["orb.error.max_fixed_unchanged"] = {kind = "text"},
    ["orb.error.max_needs_balance"] = {kind = "text"},
    ["orb.error.new_run_needs_balance"] = {kind = "text"},
    ["orb.error.new_run_needs_finished"] = {kind = "text"},
    ["orb.error.no_confirmed_orbs"] = {kind = "text"},
    ["orb.error.no_safe_surplus"] = {kind = "text"},
    ["orb.error.orb_state_unreadable"] = {kind = "text"},
    ["orb.error.order_follows_wishlist"] = {kind = "text"},
    ["orb.error.recheck_failed"] = {kind = "text"},
    ["orb.error.recheck_session_paused"] = {kind = "text"},
    ["orb.error.recheck_wait"] = {kind = "text"},
    ["orb.error.recycle_fixed"] = {kind = "text"},
    ["orb.error.replaceable_changed"] = {kind = "text"},
    ["orb.error.resume_context_changed"] = {kind = "text"},
    ["orb.error.resume_not_owner"] = {kind = "text"},
    ["orb.error.resume_only_paused"] = {kind = "text"},
    ["orb.error.resume_settle_first"] = {kind = "text"},
    ["orb.error.resume_spend_unknown"] = {kind = "text"},
    ["orb.error.resume_wait_wishlist"] = {kind = "text"},
    ["orb.error.rival_addon"] = {kind = "text"},
    ["orb.error.rolled_complete_locked"] = {kind = "text"},
    ["orb.error.run_owns_action"] = {kind = "text"},
    ["orb.error.session_paused"] = {kind = "text"},
    ["orb.error.source_count_invalid"] = {kind = "text"},
    ["orb.error.source_protected"] = {kind = "text"},
    ["orb.error.source_unsafe"] = {kind = "text"},
    ["orb.error.sources_fixed"] = {kind = "text"},
    ["orb.error.state_unreadable"] = {kind = "text"},
    ["orb.error.wishlist_changed_start"] = {kind = "text"},
    ["orb.heading.copy_report"] = {kind = "text"},
    ["orb.heading.history_timeline"] = {kind = "text"},
    ["orb.label.details"] = {kind = "text"},
    ["orb.label.history_offered"] = {kind = "text"},
    ["orb.label.history_run"] = {kind = "template", fields = {"id"}, slots = {"text"}, resultLimit = 356},
    ["orb.label.history_why"] = {kind = "text"},
    ["orb.label.history_why_selected"] = {kind = "text"},
    ["orb.label.include_technical"] = {kind = "text"},
    ["orb.label.maximum_this_run"] = {kind = "text"},
    ["orb.label.progress_unavailable"] = {kind = "text"},
    ["orb.label.recorded_note"] = {kind = "text"},
    ["orb.label.source_row"] = {kind = "template", fields = {"name", "quality", "count"}, slots = {"text", "count", "count"}, resultLimit = 434},
    ["orb.label.sources_page"] = {kind = "template", fields = {"page", "pages"}, slots = {"count", "count"}, resultLimit = 256},
    ["orb.label.start_reason"] = {kind = "text"},
    ["orb.note.close_keeps_run"] = {kind = "text"},
    ["orb.note.history_reload_cleared"] = {kind = "text"},
    ["orb.note.history_session"] = {kind = "text"},
    ["orb.note.mini_close_keeps_run"] = {kind = "text"},
    ["orb.status.action_continue"] = {kind = "text"},
    ["orb.status.action_finish_check"] = {kind = "text"},
    ["orb.status.action_follow_details"] = {kind = "text"},
    ["orb.status.action_review_check"] = {kind = "text"},
    ["orb.status.action_why_blocked"] = {kind = "text"},
    ["orb.status.assign_to_begin"] = {kind = "text"},
    ["orb.status.assigned_none"] = {kind = "text"},
    ["orb.status.assigned_wishlist"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 390},
    ["orb.status.balance_confirmed"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.balance_loading"] = {kind = "text"},
    ["orb.status.balance_state"] = {kind = "template", fields = {"state", "reason"}, slots = {"text", "text"}, resultLimit = 700},
    ["orb.status.compact_paused_lost"] = {kind = "text"},
    ["orb.status.compact_paused_not_ready"] = {kind = "text"},
    ["orb.status.compact_paused_pending_many"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.compact_paused_pending_one"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.compact_paused_result"] = {kind = "text"},
    ["orb.status.compact_paused_review"] = {kind = "text"},
    ["orb.status.compact_paused_settle"] = {kind = "text"},
    ["orb.status.compact_resume_uses"] = {kind = "template", fields = {"target"}, slots = {"text"}, resultLimit = 382},
    ["orb.status.compact_target_back"] = {kind = "template", fields = {"target"}, slots = {"text"}, resultLimit = 386},
    ["orb.status.compact_target_new"] = {kind = "template", fields = {"target"}, slots = {"text"}, resultLimit = 380},
    ["orb.status.compact_target_unknown"] = {kind = "text"},
    ["orb.status.confirm_new_run_tail"] = {kind = "template", fields = {"amount"}, slots = {"text"}, resultLimit = 530},
    ["orb.status.continue_checking"] = {kind = "text"},
    ["orb.status.continue_held"] = {kind = "text"},
    ["orb.status.continue_ready"] = {kind = "text"},
    ["orb.status.continue_refused"] = {kind = "text"},
    ["orb.status.continue_state_checking"] = {kind = "text"},
    ["orb.status.continue_state_done"] = {kind = "text"},
    ["orb.status.continue_state_ready"] = {kind = "text"},
    ["orb.status.continue_state_refused"] = {kind = "text"},
    ["orb.status.continue_state_unavailable"] = {kind = "text"},
    ["orb.status.continue_state_unchecked"] = {kind = "text"},
    ["orb.status.enter_whole_maximum"] = {kind = "text"},
    ["orb.status.fact_copies_left"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.fact_copy_left"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.fact_not_settled"] = {kind = "text"},
    ["orb.status.fact_pending_many"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.fact_pending_one"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.headline_paused"] = {kind = "text"},
    ["orb.status.headline_paused_continue"] = {kind = "text"},
    ["orb.status.headline_recovery"] = {kind = "text"},
    ["orb.status.headline_recovery_continue"] = {kind = "text"},
    ["orb.status.history_max_increased"] = {kind = "text"},
    ["orb.status.history_new_operations"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.history_none_started"] = {kind = "text"},
    ["orb.status.history_now"] = {kind = "template", fields = {"now", "recorded"}, slots = {"text", "text"}, resultLimit = 716},
    ["orb.status.history_page_bounded"] = {kind = "text"},
    ["orb.status.history_page_none"] = {kind = "text"},
    ["orb.status.history_page_range"] = {kind = "template", fields = {"first", "last", "total"}, slots = {"count", "count", "count"}, resultLimit = 256},
    ["orb.status.history_pending_many"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.history_pending_one"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.history_state_complete"] = {kind = "text"},
    ["orb.status.history_state_finished"] = {kind = "text"},
    ["orb.status.history_state_idle"] = {kind = "text"},
    ["orb.status.history_state_limit"] = {kind = "text"},
    ["orb.status.history_state_no_sources"] = {kind = "text"},
    ["orb.status.history_state_out_of_orbs"] = {kind = "text"},
    ["orb.status.history_state_paused"] = {kind = "text"},
    ["orb.status.history_state_ready"] = {kind = "text"},
    ["orb.status.history_state_recovery"] = {kind = "text"},
    ["orb.status.history_state_rolled_complete"] = {kind = "text"},
    ["orb.status.history_state_stopped"] = {kind = "text"},
    ["orb.status.history_state_wait_offer"] = {kind = "text"},
    ["orb.status.history_state_wait_result"] = {kind = "text"},
    ["orb.status.history_state_wait_world"] = {kind = "text"},
    ["orb.status.history_truncated"] = {kind = "text"},
    ["orb.status.line_awaiting_result"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.line_result_not_settled"] = {kind = "text"},
    ["orb.status.line_run"] = {kind = "template", fields = {"status"}, slots = {"text"}, resultLimit = 2048},
    ["orb.status.line_spend_unconfirmed"] = {kind = "text"},
    ["orb.status.line_usage_limit_unknown"] = {kind = "template", fields = {"spent"}, slots = {"text"}, resultLimit = 422},
    ["orb.status.line_usage_no_max"] = {kind = "template", fields = {"spent"}, slots = {"text"}, resultLimit = 410},
    ["orb.status.line_usage_of"] = {kind = "template", fields = {"spent", "limit"}, slots = {"text", "text"}, resultLimit = 704},
    ["orb.status.line_usage_spent_unknown"] = {kind = "template", fields = {"limit"}, slots = {"text"}, resultLimit = 422},
    ["orb.status.locked_copies_remain"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.max_changed_review"] = {kind = "text"},
    ["orb.status.max_fixed_during_run"] = {kind = "text"},
    ["orb.status.max_follows_balance"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.max_follows_unconfirmed"] = {kind = "text"},
    ["orb.status.max_reached_stop"] = {kind = "text"},
    ["orb.status.mini_loading"] = {kind = "text"},
    ["orb.status.mini_no_run"] = {kind = "text"},
    ["orb.status.mini_not_paused_unread"] = {kind = "text"},
    ["orb.status.mini_not_paused_was_not_running"] = {kind = "text"},
    ["orb.status.mini_not_resumed_lost"] = {kind = "text"},
    ["orb.status.mini_not_resumed_no_run"] = {kind = "text"},
    ["orb.status.mini_not_resumed_not_paused"] = {kind = "text"},
    ["orb.status.mini_not_resumed_not_ready"] = {kind = "text"},
    ["orb.status.mini_not_resumed_reason"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 2048},
    ["orb.status.mini_not_resumed_review_back"] = {kind = "text"},
    ["orb.status.mini_not_resumed_review_new"] = {kind = "text"},
    ["orb.status.mini_not_resumed_settle"] = {kind = "text"},
    ["orb.status.mini_not_resumed_unread"] = {kind = "text"},
    ["orb.status.mini_not_stopped_inactive"] = {kind = "text"},
    ["orb.status.mini_not_stopped_no_run"] = {kind = "text"},
    ["orb.status.mini_not_stopped_reason"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 2048},
    ["orb.status.mini_not_stopped_unread"] = {kind = "text"},
    ["orb.status.mini_open_to_start"] = {kind = "text"},
    ["orb.status.mini_pause_failed"] = {kind = "text"},
    ["orb.status.mini_paused"] = {kind = "text"},
    ["orb.status.mini_paused_not_ready"] = {kind = "text"},
    ["orb.status.mini_paused_review_back"] = {kind = "text"},
    ["orb.status.mini_paused_review_new"] = {kind = "text"},
    ["orb.status.mini_paused_settle"] = {kind = "text"},
    ["orb.status.mini_pending_counts"] = {kind = "template", fields = {"unknown", "reserved", "outcomes"}, slots = {"count", "count", "count"}, resultLimit = 256},
    ["orb.status.mini_pending_many"] = {kind = "template", fields = {"count"}, slots = {"text"}, resultLimit = 440},
    ["orb.status.mini_pending_none"] = {kind = "text"},
    ["orb.status.mini_pending_one"] = {kind = "template", fields = {"count"}, slots = {"text"}, resultLimit = 438},
    ["orb.status.mini_pending_unavailable"] = {kind = "text"},
    ["orb.status.mini_reading_saved"] = {kind = "text"},
    ["orb.status.mini_refused"] = {kind = "text"},
    ["orb.status.mini_result_not_settled"] = {kind = "text"},
    ["orb.status.mini_resume_accepted"] = {kind = "text"},
    ["orb.status.mini_resume_failed"] = {kind = "text"},
    ["orb.status.mini_resume_not_running"] = {kind = "text"},
    ["orb.status.mini_resumed"] = {kind = "text"},
    ["orb.status.mini_rolled_missing"] = {kind = "template", fields = {"value"}, slots = {"text"}, resultLimit = 414},
    ["orb.status.mini_rolled_missing_short"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.mini_running"] = {kind = "template", fields = {"state"}, slots = {"text"}, resultLimit = 374},
    ["orb.status.mini_stop_failed"] = {kind = "text"},
    ["orb.status.mini_stopped"] = {kind = "text"},
    ["orb.status.mini_unavailable"] = {kind = "text"},
    ["orb.status.mini_unknown_state"] = {kind = "template", fields = {"state"}, slots = {"text"}, resultLimit = 384},
    ["orb.status.mini_unread"] = {kind = "text"},
    ["orb.status.mini_unread_error"] = {kind = "text"},
    ["orb.status.mini_unread_malformed"] = {kind = "text"},
    ["orb.status.mini_unread_missing"] = {kind = "text"},
    ["orb.status.mini_usage_limit_unknown"] = {kind = "template", fields = {"spent"}, slots = {"text"}, resultLimit = 434},
    ["orb.status.mini_usage_no_max"] = {kind = "template", fields = {"spent"}, slots = {"text"}, resultLimit = 422},
    ["orb.status.mini_usage_none"] = {kind = "text"},
    ["orb.status.mini_usage_of"] = {kind = "template", fields = {"spent", "limit"}, slots = {"text", "text"}, resultLimit = 716},
    ["orb.status.mini_usage_spent_unknown"] = {kind = "template", fields = {"limit"}, slots = {"text"}, resultLimit = 434},
    ["orb.status.mini_usage_unavailable"] = {kind = "text"},
    ["orb.status.no_change"] = {kind = "text"},
    ["orb.status.not_paused_not_running"] = {kind = "text"},
    ["orb.status.not_resumed_lost_approval"] = {kind = "text"},
    ["orb.status.not_resumed_not_offered"] = {kind = "text"},
    ["orb.status.not_resumed_not_ready"] = {kind = "text"},
    ["orb.status.not_resumed_running"] = {kind = "text"},
    ["orb.status.not_resumed_settle"] = {kind = "text"},
    ["orb.status.original_operation"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 392},
    ["orb.status.phase_complete"] = {kind = "text"},
    ["orb.status.phase_finished"] = {kind = "text"},
    ["orb.status.phase_idle"] = {kind = "text"},
    ["orb.status.phase_limit"] = {kind = "text"},
    ["orb.status.phase_no_sources"] = {kind = "text"},
    ["orb.status.phase_out_of_orbs"] = {kind = "text"},
    ["orb.status.phase_paused"] = {kind = "text"},
    ["orb.status.phase_ready"] = {kind = "text"},
    ["orb.status.phase_recovery"] = {kind = "text"},
    ["orb.status.phase_rolled_complete"] = {kind = "text"},
    ["orb.status.phase_stopped"] = {kind = "text"},
    ["orb.status.phase_wait_offer"] = {kind = "text"},
    ["orb.status.phase_wait_result"] = {kind = "text"},
    ["orb.status.phase_wait_world"] = {kind = "text"},
    ["orb.status.progress_unavailable"] = {kind = "text"},
    ["orb.status.reading_saved_data"] = {kind = "text"},
    ["orb.status.recovery_checking"] = {kind = "text"},
    ["orb.status.recovery_held"] = {kind = "text"},
    ["orb.status.recovery_ready"] = {kind = "text"},
    ["orb.status.recovery_refused"] = {kind = "text"},
    ["orb.status.refresh_failed"] = {kind = "text"},
    ["orb.status.restoring_assignment"] = {kind = "text"},
    ["orb.status.resume_back_held"] = {kind = "template", fields = {"target"}, slots = {"text"}, resultLimit = 502},
    ["orb.status.resume_back_reviewed"] = {kind = "template", fields = {"target"}, slots = {"text"}, resultLimit = 514},
    ["orb.status.resume_lost_approval"] = {kind = "text"},
    ["orb.status.resume_new_held"] = {kind = "template", fields = {"target"}, slots = {"text"}, resultLimit = 458},
    ["orb.status.resume_new_held_instead"] = {kind = "template", fields = {"target", "original"}, slots = {"text", "text"}, resultLimit = 802},
    ["orb.status.resume_new_reviewed"] = {kind = "template", fields = {"target"}, slots = {"text"}, resultLimit = 456},
    ["orb.status.resume_new_reviewed_instead"] = {kind = "template", fields = {"target", "original"}, slots = {"text", "text"}, resultLimit = 800},
    ["orb.status.resume_original"] = {kind = "template", fields = {"target"}, slots = {"text"}, resultLimit = 446},
    ["orb.status.resume_same"] = {kind = "template", fields = {"target"}, slots = {"text"}, resultLimit = 426},
    ["orb.status.resume_settle"] = {kind = "text"},
    ["orb.status.resume_unknown_loading"] = {kind = "text"},
    ["orb.status.resume_unknown_not_ready"] = {kind = "text"},
    ["orb.status.resume_unknown_restoring"] = {kind = "text"},
    ["orb.status.resume_unknown_unassigned"] = {kind = "text"},
    ["orb.status.resume_unknown_unavailable"] = {kind = "text"},
    ["orb.status.review_back_first"] = {kind = "template", fields = {"target"}, slots = {"text"}, resultLimit = 502},
    ["orb.status.review_cancelled"] = {kind = "text"},
    ["orb.status.review_done"] = {kind = "template", fields = {"target"}, slots = {"text"}, resultLimit = 494},
    ["orb.status.review_new_first"] = {kind = "template", fields = {"target"}, slots = {"text"}, resultLimit = 492},
    ["orb.status.review_none"] = {kind = "text"},
    ["orb.status.review_state_changed"] = {kind = "text"},
    ["orb.status.review_target_changed"] = {kind = "text"},
    ["orb.status.rolled_missing"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.run_all_complete"] = {kind = "text"},
    ["orb.status.run_approved"] = {kind = "text"},
    ["orb.status.run_auto_accept"] = {kind = "text"},
    ["orb.status.run_balance_changed"] = {kind = "text"},
    ["orb.status.run_choice_different"] = {kind = "text"},
    ["orb.status.run_choice_sent"] = {kind = "text"},
    ["orb.status.run_confirmed_next"] = {kind = "text"},
    ["orb.status.run_confirmed_paused"] = {kind = "text"},
    ["orb.status.run_context_changed"] = {kind = "text"},
    ["orb.status.run_idle"] = {kind = "text"},
    ["orb.status.run_internal_error"] = {kind = "text"},
    ["orb.status.run_internal_error_stopped"] = {kind = "text"},
    ["orb.status.run_loading_interrupted"] = {kind = "text"},
    ["orb.status.run_locked_changed"] = {kind = "text"},
    ["orb.status.run_locked_changed_resolve"] = {kind = "text"},
    ["orb.status.run_log_offer_observed"] = {kind = "text"},
    ["orb.status.run_log_receipt_failed"] = {kind = "text"},
    ["orb.status.run_log_requested"] = {kind = "text"},
    ["orb.status.run_no_orbs"] = {kind = "text"},
    ["orb.status.run_no_sources"] = {kind = "text"},
    ["orb.status.run_offer_changed"] = {kind = "text"},
    ["orb.status.run_original_confirmed_review"] = {kind = "text"},
    ["orb.status.run_other_action"] = {kind = "text"},
    ["orb.status.run_ownership_mismatch"] = {kind = "text"},
    ["orb.status.run_paused"] = {kind = "text"},
    ["orb.status.run_paused_pending"] = {kind = "text"},
    ["orb.status.run_previous_confirmed"] = {kind = "text"},
    ["orb.status.run_recovery_restored"] = {kind = "text"},
    ["orb.status.run_requested"] = {kind = "text"},
    ["orb.status.run_requested_balance"] = {kind = "text"},
    ["orb.status.run_rival_picker"] = {kind = "text"},
    ["orb.status.run_rolled_changed"] = {kind = "text"},
    ["orb.status.run_rolled_complete"] = {kind = "text"},
    ["orb.status.run_spend_visible"] = {kind = "text"},
    ["orb.status.run_stopped"] = {kind = "text"},
    ["orb.status.run_stopped_pending"] = {kind = "text"},
    ["orb.status.run_waiting_after_loading"] = {kind = "text"},
    ["orb.status.run_wishlist_changed_resolve"] = {kind = "text"},
    ["orb.status.run_wishlist_changed_review"] = {kind = "text"},
    ["orb.status.run_world_unavailable"] = {kind = "text"},
    ["orb.status.segment_awaiting_result"] = {kind = "text"},
    ["orb.status.segment_current_exposure"] = {kind = "template", fields = {"value"}, slots = {"text"}, resultLimit = 390},
    ["orb.status.segment_history_reload"] = {kind = "text"},
    ["orb.status.segment_history_unavailable"] = {kind = "text"},
    ["orb.status.segment_result_not_settled"] = {kind = "text"},
    ["orb.status.segment_unconfirmed_outcomes"] = {kind = "template", fields = {"value"}, slots = {"text"}, resultLimit = 398},
    ["orb.status.segment_unknown_exposure"] = {kind = "template", fields = {"value"}, slots = {"text"}, resultLimit = 402},
    ["orb.status.segment_unknown_spend"] = {kind = "template", fields = {"value"}, slots = {"text"}, resultLimit = 384},
    ["orb.status.start_balance_unavailable"] = {kind = "text"},
    ["orb.status.start_balance_zero"] = {kind = "text"},
    ["orb.status.start_needs_whole_maximum"] = {kind = "text"},
    ["orb.status.strip_copies_remaining"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.strip_not_settled"] = {kind = "text"},
    ["orb.status.strip_pending_many"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.strip_pending_one"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.strip_target_unavailable"] = {kind = "text"},
    ["orb.status.strip_usage_no_max"] = {kind = "template", fields = {"spent"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.usage_head"] = {kind = "template", fields = {"spent", "limit"}, slots = {"count", "text"}, resultLimit = 396},
    ["orb.status.usage_pending_many"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.status.usage_pending_one"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.tab.run_controls"] = {kind = "text"},
    ["orb.tab.run_history"] = {kind = "text"},
    ["orb.title.continue_unconfirmed"] = {kind = "text"},
    ["orb.title.mini"] = {kind = "text"},
    ["orb.title.unresolved_action"] = {kind = "text"},
    ["orb.title.window"] = {kind = "text"},
    ["orb.tooltip.history_replaced"] = {kind = "template", fields = {"echo"}, slots = {"text"}, resultLimit = 382},
    ["orb.tooltip.history_replacement"] = {kind = "template", fields = {"echo"}, slots = {"text"}, resultLimit = 378},
    ["orb.tooltip.history_replacement_proposed"] = {kind = "template", fields = {"echo"}, slots = {"text"}, resultLimit = 428},
    ["orb.tooltip.history_result"] = {kind = "template", fields = {"result"}, slots = {"text"}, resultLimit = 372},
    ["orb.tooltip.history_why_fallback"] = {kind = "text"},
    ["orb.tooltip.max_follow_balance"] = {kind = "text"},
    ["orb.tooltip.mini_close"] = {kind = "text"},
    ["orb.tooltip.mini_drag"] = {kind = "text"},
    ["orb.tooltip.mini_missing"] = {kind = "block"},
    ["orb.tooltip.mini_open"] = {kind = "text"},
    ["orb.tooltip.mini_panel_open"] = {kind = "text"},
    ["orb.tooltip.mini_pause"] = {kind = "text"},
    ["orb.tooltip.mini_pending"] = {kind = "text"},
    ["orb.tooltip.mini_resume"] = {kind = "block"},
    ["orb.tooltip.mini_stop"] = {kind = "text"},
    ["orb.tooltip.mini_usage"] = {kind = "text"},
    ["orb.tooltip.reason_fallback_detail"] = {kind = "text"},
    ["orb.value.balance_loading"] = {kind = "text"},
    ["orb.value.balance_unknown"] = {kind = "text"},
    ["orb.value.balance_unsupported"] = {kind = "text"},
    ["orb.value.echo_no_replacement"] = {kind = "text"},
    ["orb.value.echo_not_recorded"] = {kind = "text"},
    ["orb.value.echo_proposed"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 374},
    ["orb.value.echo_unknown"] = {kind = "template", fields = {"id"}, slots = {"text"}, resultLimit = 378},
    ["orb.value.echo_with_rarity"] = {kind = "template", fields = {"name", "rarity"}, slots = {"text", "text"}, resultLimit = 674},
    ["orb.value.limit_approved"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["orb.value.max_not_recorded"] = {kind = "text"},
    ["orb.value.offer_not_recorded"] = {kind = "text"},
    ["orb.value.offer_received"] = {kind = "template", fields = {"echo"}, slots = {"text"}, resultLimit = 374},
    ["orb.value.offer_selected"] = {kind = "template", fields = {"echo"}, slots = {"text"}, resultLimit = 374},
    ["orb.value.quality_common"] = {kind = "text"},
    ["orb.value.quality_epic"] = {kind = "text"},
    ["orb.value.quality_legendary"] = {kind = "text"},
    ["orb.value.quality_rare"] = {kind = "text"},
    ["orb.value.quality_uncommon"] = {kind = "text"},
    ["orb.value.quality_unknown"] = {kind = "text"},
    ["orb.value.rarity_proposed"] = {kind = "template", fields = {"rarity"}, slots = {"text"}, resultLimit = 378},
    ["orb.value.reason_fallback"] = {kind = "text"},
    ["orb.value.reason_manual"] = {kind = "text"},
    ["orb.value.reason_missing_target"] = {kind = "text"},
    ["orb.value.reason_unavailable"] = {kind = "text"},
    ["orb.value.result_awaiting"] = {kind = "text"},
    ["orb.value.result_choice"] = {kind = "text"},
    ["orb.value.result_confirmed"] = {kind = "text"},
    ["orb.value.result_paused"] = {kind = "text"},
    ["orb.value.result_requested"] = {kind = "text"},
    ["orb.value.result_spend_unconfirmed"] = {kind = "text"},
    ["orb.value.result_unconfirmed"] = {kind = "text"},
    ["orb.value.state_unknown"] = {kind = "text"},
    ["orb.value.target_tag_back"] = {kind = "text"},
    ["orb.value.target_tag_new"] = {kind = "text"},
    ["orb.value.target_tag_same"] = {kind = "text"},
    ["orb.value.target_unknown_short"] = {kind = "text"},
    ["orb.value.unavailable"] = {kind = "text"},
    ["orb.value.unnamed_short"] = {kind = "text"},
    ["orb.value.unnamed_wishlist"] = {kind = "text"},
    ["orb.value.wishlist_none"] = {kind = "text"},
    -- panel (380)
    ["panel.body.auto_detail_heading"] = {kind = "text"},
    ["panel.body.auto_detail_off"] = {kind = "text"},
    ["panel.body.auto_detail_off_wishlist"] = {kind = "text"},
    ["panel.body.auto_detail_paused_because"] = {kind = "text"},
    ["panel.body.auto_detail_separate"] = {kind = "text"},
    ["panel.body.auto_detail_when_on"] = {kind = "text"},
    ["panel.body.complete_named"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 600},
    ["panel.body.complete_unnamed"] = {kind = "text"},
    ["panel.body.extra_list_none"] = {kind = "text"},
    ["panel.body.extra_list_not_known"] = {kind = "text"},
    ["panel.body.extra_list_note"] = {kind = "block"},
    ["panel.body.setup_assign_or_create"] = {kind = "text"},
    ["panel.body.setup_waiting"] = {kind = "text"},
    ["panel.button.auto_off"] = {kind = "text"},
    ["panel.button.auto_on"] = {kind = "text"},
    ["panel.button.auto_unknown"] = {kind = "text"},
    ["panel.button.change_wishlist"] = {kind = "text"},
    ["panel.button.close_extra_list"] = {kind = "text"},
    ["panel.button.details_hide"] = {kind = "text"},
    ["panel.button.details_show"] = {kind = "text"},
    ["panel.button.explore"] = {kind = "text"},
    ["panel.button.open_orbs"] = {kind = "text"},
    ["panel.button.orb_mini"] = {kind = "text"},
    ["panel.button.orb_mini_short"] = {kind = "text"},
    ["panel.button.orb_open"] = {kind = "text"},
    ["panel.button.orbs"] = {kind = "text"},
    ["panel.button.plan"] = {kind = "text"},
    ["panel.button.resume"] = {kind = "text"},
    ["panel.chat.assignment_button_missing"] = {kind = "text"},
    ["panel.chat.language_already_active"] = {kind = "text"},
    ["panel.chat.language_already_session"] = {kind = "text"},
    ["panel.chat.language_refused"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 500},
    ["panel.chat.language_saved"] = {kind = "template", fields = {"language"}, slots = {"text"}, resultLimit = 400},
    ["panel.chat.language_saved_next_reload"] = {kind = "template", fields = {"language"}, slots = {"text"}, resultLimit = 600},
    ["panel.chat.language_session_only"] = {kind = "text"},
    ["panel.chat.language_unchanged"] = {kind = "template", fields = {"language"}, slots = {"text"}, resultLimit = 400},
    ["panel.chat.language_unconfirmed"] = {kind = "text"},
    ["panel.chat.my_builds_button_missing"] = {kind = "text"},
    ["panel.chat.panel_hidden"] = {kind = "text"},
    ["panel.chat.panel_hidden_restore"] = {kind = "template", fields = {"hidden", "command"}, slots = {"text", "text"}, resultLimit = 700},
    ["panel.chat.pause_failed"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 600},
    ["panel.chat.pause_reason_error"] = {kind = "text"},
    ["panel.chat.pause_reason_unavailable"] = {kind = "text"},
    ["panel.chat.pause_reason_unconfirmed"] = {kind = "text"},
    ["panel.chat.plan_action_open"] = {kind = "text"},
    ["panel.chat.plan_not_reopened"] = {kind = "text"},
    ["panel.chat.plan_protection_unavailable"] = {kind = "text"},
    ["panel.chat.plan_resume_draft"] = {kind = "text"},
    ["panel.chat.resume_failed"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 600},
    ["panel.chat.setup_information_unavailable"] = {kind = "text"},
    ["panel.chat.setup_information_warning_open"] = {kind = "text"},
    ["panel.chat.setup_welcome_unavailable"] = {kind = "text"},
    ["panel.chat.setup_welcome_warning_open"] = {kind = "text"},
    ["panel.chat.support_report_not_loaded"] = {kind = "text"},
    ["panel.heading.callboard"] = {kind = "text"},
    ["panel.heading.dps_records"] = {kind = "text"},
    ["panel.heading.lich_king"] = {kind = "text"},
    ["panel.heading.missing_tomes"] = {kind = "text"},
    ["panel.heading.missing_tomes_stacked"] = {kind = "block"},
    ["panel.heading.training_dummy"] = {kind = "text"},
    ["panel.label.active_prefix"] = {kind = "text"},
    ["panel.label.ash_short"] = {kind = "text"},
    ["panel.label.auto_state_off"] = {kind = "text"},
    ["panel.label.auto_state_on"] = {kind = "text"},
    ["panel.label.auto_state_unknown"] = {kind = "text"},
    ["panel.label.best_dps_dummy"] = {kind = "template", fields = {"dps"}, slots = {"text"}, resultLimit = 200},
    ["panel.label.best_dps_lk"] = {kind = "template", fields = {"dps"}, slots = {"text"}, resultLimit = 200},
    ["panel.label.best_dps_none"] = {kind = "text"},
    ["panel.label.best_known"] = {kind = "text"},
    ["panel.label.best_known_same_build"] = {kind = "template", fields = {"best_known"}, slots = {"text"}, resultLimit = 300},
    ["panel.label.callboard_no_details"] = {kind = "text"},
    ["panel.label.callboard_objective"] = {kind = "text"},
    ["panel.label.context_build"] = {kind = "template", fields = {"build"}, slots = {"text"}, resultLimit = 600},
    ["panel.label.context_wishlist"] = {kind = "template", fields = {"wishlist"}, slots = {"text"}, resultLimit = 600},
    ["panel.label.cue_empty"] = {kind = "text"},
    ["panel.label.cue_not_known"] = {kind = "text"},
    ["panel.label.cue_preview"] = {kind = "text"},
    ["panel.label.cue_unconfirmed"] = {kind = "text"},
    ["panel.label.difficulty_fallback"] = {kind = "text"},
    ["panel.label.dummy_best"] = {kind = "text"},
    ["panel.label.extra_list_not_current"] = {kind = "text"},
    ["panel.label.freeze_tag"] = {kind = "text"},
    ["panel.label.lich_king_best"] = {kind = "text"},
    ["panel.label.more_count"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 120},
    ["panel.label.more_count_show_all"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 160},
    ["panel.label.no_extra_copies"] = {kind = "text"},
    ["panel.label.no_remaining_demand"] = {kind = "text"},
    ["panel.label.play_extra_copies"] = {kind = "text"},
    ["panel.label.play_locked_targets"] = {kind = "text"},
    ["panel.label.play_missing_tomes"] = {kind = "text"},
    ["panel.label.play_still_needed"] = {kind = "text"},
    ["panel.label.preview_tag"] = {kind = "text"},
    ["panel.label.slot_number"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 120},
    ["panel.label.soul_ash"] = {kind = "text"},
    ["panel.label.target_build_copies"] = {kind = "template", fields = {"count"}, slots = {"text"}, resultLimit = 300},
    ["panel.label.title_paused"] = {kind = "text"},
    ["panel.label.your_best"] = {kind = "text"},
    ["panel.label.your_best_dps"] = {kind = "text"},
    ["panel.label.your_dummy"] = {kind = "text"},
    ["panel.label.your_lich_king"] = {kind = "text"},
    ["panel.label.yours"] = {kind = "text"},
    ["panel.label.yours_training_dummy"] = {kind = "text"},
    ["panel.menu.appearance"] = {kind = "template", fields = {"summary"}, slots = {"text"}, resultLimit = 400},
    ["panel.menu.assign_wishlist"] = {kind = "text"},
    ["panel.menu.auto_explained"] = {kind = "text"},
    ["panel.menu.automation_settings"] = {kind = "text"},
    ["panel.menu.automation_unavailable"] = {kind = "text"},
    ["panel.menu.build_library"] = {kind = "text"},
    ["panel.menu.dps_records_hide"] = {kind = "text"},
    ["panel.menu.dps_records_show"] = {kind = "text"},
    ["panel.menu.explore_title"] = {kind = "text"},
    ["panel.menu.faq"] = {kind = "text"},
    ["panel.menu.hud_not_known"] = {kind = "text"},
    ["panel.menu.hud_use_nexus_now_server"] = {kind = "text"},
    ["panel.menu.hud_use_nexus_undetected"] = {kind = "text"},
    ["panel.menu.hud_use_server_now_nexus"] = {kind = "text"},
    ["panel.menu.hud_use_server_undetected"] = {kind = "text"},
    ["panel.menu.language"] = {kind = "text"},
    ["panel.menu.language_active"] = {kind = "template", fields = {"language"}, slots = {"text"}, resultLimit = 500},
    ["panel.menu.language_automatic"] = {kind = "template", fields = {"language"}, slots = {"text"}, resultLimit = 300},
    ["panel.menu.language_in_use"] = {kind = "template", fields = {"language"}, slots = {"text"}, resultLimit = 500},
    ["panel.menu.language_row"] = {kind = "template", fields = {"language"}, slots = {"text"}, resultLimit = 400},
    ["panel.menu.language_row_pending"] = {kind = "template", fields = {"language"}, slots = {"text"}, resultLimit = 400},
    ["panel.menu.language_saved_after_reload"] = {kind = "template", fields = {"language"}, slots = {"text"}, resultLimit = 800},
    ["panel.menu.language_title"] = {kind = "text"},
    ["panel.menu.leaderboard"] = {kind = "text"},
    ["panel.menu.log_viewer"] = {kind = "text"},
    ["panel.menu.more_windows"] = {kind = "text"},
    ["panel.menu.my_builds_game_page"] = {kind = "text"},
    ["panel.menu.notices_announce"] = {kind = "text"},
    ["panel.menu.notices_announce_when_on"] = {kind = "text"},
    ["panel.menu.notices_off"] = {kind = "text"},
    ["panel.menu.notices_on"] = {kind = "text"},
    ["panel.menu.notices_row_off"] = {kind = "text"},
    ["panel.menu.notices_row_on_stable"] = {kind = "text"},
    ["panel.menu.notices_row_on_test"] = {kind = "text"},
    ["panel.menu.notices_stable_and_test"] = {kind = "text"},
    ["panel.menu.notices_stable_only"] = {kind = "text"},
    ["panel.menu.notices_title"] = {kind = "text"},
    ["panel.menu.notices_unavailable"] = {kind = "text"},
    ["panel.menu.open_releases"] = {kind = "text"},
    ["panel.menu.open_settings"] = {kind = "text"},
    ["panel.menu.orbs"] = {kind = "text"},
    ["panel.menu.pause_not_available"] = {kind = "text"},
    ["panel.menu.pause_session"] = {kind = "text"},
    ["panel.menu.plan_title"] = {kind = "text"},
    ["panel.menu.reference"] = {kind = "text"},
    ["panel.menu.reset_position"] = {kind = "text"},
    ["panel.menu.resume_nexus"] = {kind = "text"},
    ["panel.menu.section_help"] = {kind = "text"},
    ["panel.menu.section_notices"] = {kind = "text"},
    ["panel.menu.section_panel"] = {kind = "text"},
    ["panel.menu.section_session"] = {kind = "text"},
    ["panel.menu.section_settings"] = {kind = "text"},
    ["panel.menu.session_pause_unreadable"] = {kind = "text"},
    ["panel.menu.setup_checklist"] = {kind = "text"},
    ["panel.menu.setup_information"] = {kind = "text"},
    ["panel.menu.setup_welcome"] = {kind = "text"},
    ["panel.menu.size_larger"] = {kind = "text"},
    ["panel.menu.size_reduced"] = {kind = "template", fields = {"percent"}, slots = {"text"}, resultLimit = 300},
    ["panel.menu.size_reset"] = {kind = "text"},
    ["panel.menu.size_row"] = {kind = "template", fields = {"percent"}, slots = {"text"}, resultLimit = 300},
    ["panel.menu.size_smaller"] = {kind = "text"},
    ["panel.menu.support_report"] = {kind = "text"},
    ["panel.menu.wishlist_editor"] = {kind = "text"},
    ["panel.note.best_known_scope"] = {kind = "text"},
    ["panel.note.language_automatic"] = {kind = "text"},
    ["panel.note.language_changes_unavailable"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 400},
    ["panel.note.language_reload"] = {kind = "text"},
    ["panel.note.language_saved_unsupported"] = {kind = "text"},
    ["panel.note.language_scope"] = {kind = "block"},
    ["panel.note.language_session_only"] = {kind = "text"},
    ["panel.note.pause_scope"] = {kind = "text"},
    ["panel.note.pause_sent_may_finish"] = {kind = "text"},
    ["panel.note.plan_opens_only"] = {kind = "text"},
    ["panel.note.resume_auto_continues"] = {kind = "text"},
    ["panel.note.resume_orb_stays_paused"] = {kind = "text"},
    ["panel.note.shared_records_scope"] = {kind = "text"},
    ["panel.popup.close"] = {kind = "text"},
    ["panel.popup.releases_copy_address"] = {kind = "text"},
    ["panel.status.auto_stayed_off"] = {kind = "template", fields = {"status"}, slots = {"text"}, resultLimit = 1024},
    ["panel.status.extra_list_stale"] = {kind = "text"},
    ["panel.status.language_reason_authority"] = {kind = "text"},
    ["panel.status.language_reason_capacity"] = {kind = "text"},
    ["panel.status.language_reason_drift"] = {kind = "text"},
    ["panel.status.language_reason_failed"] = {kind = "text"},
    ["panel.status.language_reason_invalid"] = {kind = "text"},
    ["panel.status.language_reason_read_only"] = {kind = "text"},
    ["panel.status.language_reason_refused"] = {kind = "text"},
    ["panel.status.language_reason_startup"] = {kind = "text"},
    ["panel.status.orb_action_before_reload"] = {kind = "text"},
    ["panel.status.orb_action_may_settle"] = {kind = "text"},
    ["panel.status.orb_earlier_unresolved"] = {kind = "text"},
    ["panel.status.orb_none_approved"] = {kind = "text"},
    ["panel.status.orb_not_read_session"] = {kind = "text"},
    ["panel.status.orb_not_read_yet"] = {kind = "text"},
    ["panel.status.orb_run"] = {kind = "template", fields = {"state"}, slots = {"text"}, resultLimit = 700},
    ["panel.status.orb_state_not_recorded"] = {kind = "text"},
    ["panel.status.orb_state_undescribed"] = {kind = "template", fields = {"state"}, slots = {"text"}, resultLimit = 300},
    ["panel.status.orb_unreadable"] = {kind = "text"},
    ["panel.status.pause_unknown"] = {kind = "text"},
    ["panel.status.pause_unreadable_banner"] = {kind = "text"},
    ["panel.status.pause_unreadable_note"] = {kind = "text"},
    ["panel.status.paused_banner"] = {kind = "text"},
    ["panel.status.paused_banner_note"] = {kind = "text"},
    ["panel.status.roll_auto_off_you_choose"] = {kind = "text"},
    ["panel.status.roll_auto_rechecking"] = {kind = "text"},
    ["panel.status.roll_auto_waiting"] = {kind = "text"},
    ["panel.status.roll_nexus_paused"] = {kind = "text"},
    ["panel.status.roll_recommendation_preview"] = {kind = "text"},
    ["panel.status.roll_recommendations_active"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 300},
    ["panel.status.roll_status"] = {kind = "text"},
    ["panel.status.roll_you_choose"] = {kind = "text"},
    ["panel.status.setup_assign"] = {kind = "text"},
    ["panel.status.setup_restoring"] = {kind = "text"},
    ["panel.status.setup_unavailable"] = {kind = "text"},
    ["panel.status.shared_data"] = {kind = "text"},
    ["panel.status.shared_data_failed"] = {kind = "template", fields = {"command"}, slots = {"text"}, resultLimit = 300},
    ["panel.status.shared_data_local_ready"] = {kind = "text"},
    ["panel.status.shared_data_local_wait"] = {kind = "text"},
    ["panel.status.shared_data_short"] = {kind = "text"},
    ["panel.status.wishlist_complete"] = {kind = "text"},
    ["panel.title.extra_list_count"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 200},
    ["panel.title.extra_list_none"] = {kind = "text"},
    ["panel.title.extra_list_not_known"] = {kind = "text"},
    ["panel.tooltip.appearance_title"] = {kind = "text"},
    ["panel.tooltip.auto_consequence"] = {kind = "text"},
    ["panel.tooltip.auto_explained_body"] = {kind = "text"},
    ["panel.tooltip.auto_explained_title"] = {kind = "text"},
    ["panel.tooltip.auto_full_details"] = {kind = "text"},
    ["panel.tooltip.auto_now"] = {kind = "template", fields = {"state"}, slots = {"text"}, resultLimit = 300},
    ["panel.tooltip.auto_now_pause_unknown"] = {kind = "text"},
    ["panel.tooltip.auto_now_reason"] = {kind = "template", fields = {"state", "reason"}, slots = {"text", "text"}, resultLimit = 1024},
    ["panel.tooltip.auto_now_session_paused"] = {kind = "text"},
    ["panel.tooltip.auto_off_action"] = {kind = "text"},
    ["panel.tooltip.auto_off_state"] = {kind = "text"},
    ["panel.tooltip.auto_on_action"] = {kind = "text"},
    ["panel.tooltip.auto_on_held"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 600},
    ["panel.tooltip.auto_on_held_action"] = {kind = "text"},
    ["panel.tooltip.auto_on_state"] = {kind = "text"},
    ["panel.tooltip.auto_paused_continue"] = {kind = "text"},
    ["panel.tooltip.auto_paused_session"] = {kind = "text"},
    ["panel.tooltip.auto_refused_action"] = {kind = "text"},
    ["panel.tooltip.auto_refused_last_click"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 600},
    ["panel.tooltip.auto_title"] = {kind = "text"},
    ["panel.tooltip.auto_unknown_action"] = {kind = "text"},
    ["panel.tooltip.auto_unknown_state"] = {kind = "text"},
    ["panel.tooltip.best_dps_heading"] = {kind = "text"},
    ["panel.tooltip.best_dps_how"] = {kind = "text"},
    ["panel.tooltip.best_dps_none"] = {kind = "text"},
    ["panel.tooltip.best_dps_record"] = {kind = "template", fields = {"dps", "target"}, slots = {"text", "text"}, resultLimit = 300},
    ["panel.tooltip.best_known_same_echoes"] = {kind = "template", fields = {"best_known"}, slots = {"text"}, resultLimit = 300},
    ["panel.tooltip.best_known_target_dps"] = {kind = "template", fields = {"target", "dps"}, slots = {"text", "text"}, resultLimit = 300},
    ["panel.tooltip.best_known_target_none"] = {kind = "template", fields = {"target"}, slots = {"text"}, resultLimit = 300},
    ["panel.tooltip.build_library_body"] = {kind = "text"},
    ["panel.tooltip.build_library_title"] = {kind = "text"},
    ["panel.tooltip.change_wishlist_heading"] = {kind = "text"},
    ["panel.tooltip.change_wishlist_plan"] = {kind = "text"},
    ["panel.tooltip.charges_heading"] = {kind = "text"},
    ["panel.tooltip.close_panel"] = {kind = "text"},
    ["panel.tooltip.context_unavailable"] = {kind = "text"},
    ["panel.tooltip.details_body"] = {kind = "block"},
    ["panel.tooltip.difficulty_click"] = {kind = "text"},
    ["panel.tooltip.difficulty_fallback"] = {kind = "text"},
    ["panel.tooltip.dps_best_shared"] = {kind = "template", fields = {"dps"}, slots = {"text"}, resultLimit = 200},
    ["panel.tooltip.dps_duration"] = {kind = "template", fields = {"seconds"}, slots = {"text"}, resultLimit = 120},
    ["panel.tooltip.dps_exact_match"] = {kind = "text"},
    ["panel.tooltip.dps_held_by"] = {kind = "template", fields = {"player"}, slots = {"text"}, resultLimit = 1200},
    ["panel.tooltip.dps_no_personal"] = {kind = "text"},
    ["panel.tooltip.dps_no_shared"] = {kind = "text"},
    ["panel.tooltip.dps_records_body"] = {kind = "text"},
    ["panel.tooltip.dps_records_title"] = {kind = "text"},
    ["panel.tooltip.dps_your_best"] = {kind = "template", fields = {"dps"}, slots = {"text"}, resultLimit = 200},
    ["panel.tooltip.drag_explained"] = {kind = "text"},
    ["panel.tooltip.drag_title"] = {kind = "text"},
    ["panel.tooltip.explore_build_library"] = {kind = "text"},
    ["panel.tooltip.explore_leaderboard"] = {kind = "text"},
    ["panel.tooltip.explore_title"] = {kind = "text"},
    ["panel.tooltip.extra_above_targets"] = {kind = "block"},
    ["panel.tooltip.extra_heading"] = {kind = "text"},
    ["panel.tooltip.extra_locked_protected"] = {kind = "block"},
    ["panel.tooltip.extra_not_delete"] = {kind = "text"},
    ["panel.tooltip.extra_show_all_where"] = {kind = "text"},
    ["panel.tooltip.faq_opening"] = {kind = "text"},
    ["panel.tooltip.faq_reading"] = {kind = "text"},
    ["panel.tooltip.faq_title"] = {kind = "text"},
    ["panel.tooltip.hide_note"] = {kind = "template", fields = {"command"}, slots = {"text"}, resultLimit = 600},
    ["panel.tooltip.hide_panel"] = {kind = "text"},
    ["panel.tooltip.hide_panel_title"] = {kind = "text"},
    ["panel.tooltip.intensity"] = {kind = "template", fields = {"intensity"}, slots = {"text"}, resultLimit = 160},
    ["panel.tooltip.intensity_level"] = {kind = "template", fields = {"level"}, slots = {"text"}, resultLimit = 200},
    ["panel.tooltip.intensity_of_max"] = {kind = "template", fields = {"intensity", "maximum"}, slots = {"text", "text"}, resultLimit = 200},
    ["panel.tooltip.leaderboard_body"] = {kind = "text"},
    ["panel.tooltip.leaderboard_title"] = {kind = "text"},
    ["panel.tooltip.minimap_drag"] = {kind = "text"},
    ["panel.tooltip.minimap_left_click"] = {kind = "text"},
    ["panel.tooltip.minimap_right_click"] = {kind = "text"},
    ["panel.tooltip.minimap_summary"] = {kind = "text"},
    ["panel.tooltip.missing_tomes_check"] = {kind = "text"},
    ["panel.tooltip.missing_tomes_heading"] = {kind = "text"},
    ["panel.tooltip.missing_tomes_list"] = {kind = "text"},
    ["panel.tooltip.missing_tomes_no_source"] = {kind = "text"},
    ["panel.tooltip.missing_tomes_separate"] = {kind = "text"},
    ["panel.tooltip.missing_tomes_undiscovered"] = {kind = "block"},
    ["panel.tooltip.missing_tomes_where"] = {kind = "text"},
    ["panel.tooltip.more_count"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 120},
    ["panel.tooltip.more_windows_body"] = {kind = "text"},
    ["panel.tooltip.more_windows_title"] = {kind = "text"},
    ["panel.tooltip.notices_body"] = {kind = "text"},
    ["panel.tooltip.notices_title"] = {kind = "text"},
    ["panel.tooltip.numbers_hint"] = {kind = "text"},
    ["panel.tooltip.offer_card_passive"] = {kind = "text"},
    ["panel.tooltip.options_contents"] = {kind = "text"},
    ["panel.tooltip.orb_line_open"] = {kind = "text"},
    ["panel.tooltip.orb_mini_heading"] = {kind = "text"},
    ["panel.tooltip.orb_mini_status"] = {kind = "text"},
    ["panel.tooltip.orbs_also_footer"] = {kind = "text"},
    ["panel.tooltip.orbs_closing_continues"] = {kind = "text"},
    ["panel.tooltip.orbs_heading"] = {kind = "text"},
    ["panel.tooltip.orbs_open_inspect"] = {kind = "text"},
    ["panel.tooltip.pause_no_control"] = {kind = "text"},
    ["panel.tooltip.pause_session_title"] = {kind = "text"},
    ["panel.tooltip.paused_reload_ends"] = {kind = "text"},
    ["panel.tooltip.paused_resume_how"] = {kind = "template", fields = {"note"}, slots = {"text"}, resultLimit = 600},
    ["panel.tooltip.paused_title"] = {kind = "text"},
    ["panel.tooltip.plan_contents"] = {kind = "text"},
    ["panel.tooltip.plan_opens_only"] = {kind = "text"},
    ["panel.tooltip.plan_title"] = {kind = "text"},
    ["panel.tooltip.reference_body"] = {kind = "template", fields = {"command"}, slots = {"text"}, resultLimit = 500},
    ["panel.tooltip.reference_title"] = {kind = "text"},
    ["panel.tooltip.resume_nexus_title"] = {kind = "text"},
    ["panel.tooltip.session_pause_title"] = {kind = "text"},
    ["panel.tooltip.settings_body"] = {kind = "text"},
    ["panel.tooltip.settings_title"] = {kind = "text"},
    ["panel.tooltip.setup_information_body"] = {kind = "text"},
    ["panel.tooltip.setup_information_title"] = {kind = "text"},
    ["panel.tooltip.setup_welcome_explained"] = {kind = "template", fields = {"command"}, slots = {"text"}, resultLimit = 600},
    ["panel.tooltip.setup_welcome_title"] = {kind = "text"},
    ["panel.tooltip.show_all_extra_body"] = {kind = "text"},
    ["panel.tooltip.show_all_extra_title"] = {kind = "text"},
    ["panel.tooltip.size_explained"] = {kind = "block"},
    ["panel.tooltip.size_title"] = {kind = "text"},
    ["panel.tooltip.soul_ash"] = {kind = "template", fields = {"ash"}, slots = {"text"}, resultLimit = 200},
    ["panel.tooltip.soul_ash_multiplier"] = {kind = "template", fields = {"multiplier"}, slots = {"text"}, resultLimit = 200},
    ["panel.tooltip.still_needed_heading"] = {kind = "text"},
    ["panel.tooltip.still_needed_list"] = {kind = "text"},
    ["panel.tooltip.still_needed_not_obtained"] = {kind = "text"},
    ["panel.tooltip.still_needed_off_wishlist"] = {kind = "block"},
    ["panel.tooltip.update_available"] = {kind = "template", fields = {"version"}, slots = {"text"}, resultLimit = 400},
    ["panel.tooltip.update_releases_link"] = {kind = "text"},
    ["panel.tooltip.wishlist_editor_also_plan"] = {kind = "text"},
    ["panel.tooltip.wishlist_editor_title"] = {kind = "text"},
    ["panel.value.appearance_default"] = {kind = "text"},
    ["panel.value.auto_now_off"] = {kind = "text"},
    ["panel.value.auto_now_paused"] = {kind = "text"},
    ["panel.value.auto_now_ready"] = {kind = "text"},
    ["panel.value.auto_now_rechecking"] = {kind = "text"},
    ["panel.value.auto_now_waiting"] = {kind = "text"},
    ["panel.value.build_none_captured"] = {kind = "text"},
    ["panel.value.count_copies"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 120},
    ["panel.value.count_copy"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 120},
    ["panel.value.count_echo"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 120},
    ["panel.value.count_echoes"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 120},
    ["panel.value.count_listed"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 120},
    ["panel.value.count_none"] = {kind = "text"},
    ["panel.value.count_to_lock"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 120},
    ["panel.value.intensity_level_unknown"] = {kind = "text"},
    ["panel.value.invalid_title"] = {kind = "text"},
    ["panel.value.no_record_yet"] = {kind = "text"},
    ["panel.value.none_received_yet"] = {kind = "text"},
    ["panel.value.none_to_lock"] = {kind = "text"},
    ["panel.value.records_dps"] = {kind = "template", fields = {"dps"}, slots = {"text"}, resultLimit = 200},
    ["panel.value.records_dummy_and_lk"] = {kind = "template", fields = {"dummy", "lk"}, slots = {"text", "text"}, resultLimit = 300},
    ["panel.value.records_lk"] = {kind = "template", fields = {"dps"}, slots = {"text"}, resultLimit = 200},
    ["panel.value.run_progress"] = {kind = "template", fields = {"owned", "total"}, slots = {"text", "text"}, resultLimit = 300},
    ["panel.value.run_progress_unavailable"] = {kind = "text"},
    ["panel.value.shared_data_loading"] = {kind = "text"},
    ["panel.value.target_lich_king"] = {kind = "text"},
    ["panel.value.target_training_dummy"] = {kind = "text"},
    ["panel.value.unknown_player"] = {kind = "text"},
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
    -- remainder_library (128)
    ["library.chat.catalog_completion_failed"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 2048},
    ["library.chat.catalog_envelope_limits"] = {kind = "template", fields = {"code", "representation", "ordinary", "locked", "total", "max_ordinary", "max_locked"}, slots = {"text", "text", "text", "text", "text", "text", "text"}, resultLimit = 2048},
    ["library.chat.catalog_envelope_nothing_saved"] = {kind = "template", fields = {"code", "representation", "ordinary", "locked", "total"}, slots = {"text", "text", "text", "text", "text"}, resultLimit = 2048},
    ["library.chat.catalog_failed"] = {kind = "template", fields = {"operation", "reason"}, slots = {"text", "text"}, resultLimit = 2048},
    ["library.error.share_count_unreadable"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 2048},
    ["library.error.share_envelope"] = {kind = "template", fields = {"label", "ordinary", "locked", "total", "max_ordinary", "max_locked", "max_total"}, slots = {"text", "count", "count", "count", "count", "count", "count"}, resultLimit = 2048},
    ["library.error.share_locked_list_unreadable"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 2048},
    ["library.error.share_locked_lists_disagree"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 2048},
    ["library.error.share_locked_row_unreadable"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 2048},
    ["library.error.share_no_ordinary"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 2048},
    ["library.error.share_plan_differs"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 2048},
    ["library.error.share_plan_outdated"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 2048},
    ["library.error.share_plan_unbound"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 2048, lines = true},
    ["library.error.share_plan_unreadable"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 2048},
    ["library.error.share_plans_disagree"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 2048},
    ["library.error.share_roles_marked_ordinary_quality"] = {kind = "template", fields = {"label", "total", "max_ordinary", "max_locked", "why"}, slots = {"text", "count", "count", "count", "text"}, resultLimit = 2048, lines = true},
    ["library.error.share_roles_marked_ordinary_saved_build"] = {kind = "template", fields = {"label", "total", "max_ordinary", "max_locked", "why"}, slots = {"text", "count", "count", "count", "text"}, resultLimit = 2048, lines = true},
    ["library.error.share_roles_marked_ordinary_wishlist"] = {kind = "template", fields = {"label", "total", "max_ordinary", "max_locked", "why"}, slots = {"text", "count", "count", "count", "text"}, resultLimit = 2048, lines = true},
    ["library.error.share_roles_unstated_quality"] = {kind = "template", fields = {"label", "total", "max_ordinary", "max_locked", "why"}, slots = {"text", "count", "count", "count", "text"}, resultLimit = 2048, lines = true},
    ["library.error.share_roles_unstated_saved_build"] = {kind = "template", fields = {"label", "total", "max_ordinary", "max_locked", "why"}, slots = {"text", "count", "count", "count", "text"}, resultLimit = 2048, lines = true},
    ["library.error.share_roles_unstated_wishlist"] = {kind = "template", fields = {"label", "total", "max_ordinary", "max_locked", "why"}, slots = {"text", "count", "count", "count", "text"}, resultLimit = 2048, lines = true},
    ["library.error.share_row_unreadable"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 2048},
    ["library.error.share_server_row_unreadable"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 2048},
    ["library.outcome.dropped"] = {kind = "text"},
    ["library.outcome.expired"] = {kind = "text"},
    ["library.outcome.not_queued"] = {kind = "text"},
    ["library.outcome.rejected"] = {kind = "text"},
    ["library.outcome.reset"] = {kind = "text"},
    ["library.outcome.sent_attempted"] = {kind = "text"},
    ["library.outcome.stopped"] = {kind = "text"},
    ["library.outcome.superseded"] = {kind = "text"},
    ["library.outcome.throttle_exhausted"] = {kind = "text"},
    ["library.reason.build_evidence_dense"] = {kind = "text"},
    ["library.reason.candidate_contract_unsupported"] = {kind = "text"},
    ["library.reason.candidate_evidence_unavailable"] = {kind = "text"},
    ["library.reason.copy_authority_unavailable"] = {kind = "text"},
    ["library.reason.evidence_active_unverified"] = {kind = "text"},
    ["library.reason.evidence_choose_in_editor"] = {kind = "text"},
    ["library.reason.evidence_conflicting_quality"] = {kind = "text"},
    ["library.reason.evidence_counts_mismatch"] = {kind = "text"},
    ["library.reason.evidence_envelope"] = {kind = "text"},
    ["library.reason.evidence_loadout_inactive"] = {kind = "text"},
    ["library.reason.evidence_malformed"] = {kind = "text"},
    ["library.reason.evidence_no_role_choice"] = {kind = "text"},
    ["library.reason.evidence_no_verified_active"] = {kind = "text"},
    ["library.reason.evidence_not_exact_match"] = {kind = "text"},
    ["library.reason.evidence_too_many"] = {kind = "text"},
    ["library.reason.evidence_two_qualities"] = {kind = "text"},
    ["library.reason.evidence_waiting_authoritative"] = {kind = "text"},
    ["library.reason.evidence_waiting_sync"] = {kind = "text"},
    ["library.reason.historical_locked_not_authority"] = {kind = "text"},
    ["library.reason.locked_evidence_dense"] = {kind = "text"},
    ["library.reason.locked_evidence_invalid"] = {kind = "text"},
    ["library.reason.locked_fingerprint_mismatch"] = {kind = "text"},
    ["library.reason.locked_record_category_invalid"] = {kind = "text"},
    ["library.reason.locked_record_invalid"] = {kind = "text"},
    ["library.reason.locked_row_too_many_copies"] = {kind = "text"},
    ["library.reason.locked_rows_too_many"] = {kind = "text"},
    ["library.reason.ordinary_evidence_dense"] = {kind = "text"},
    ["library.reason.ordinary_evidence_invalid"] = {kind = "text"},
    ["library.reason.ordinary_evidence_syncing"] = {kind = "text"},
    ["library.reason.ordinary_evidence_unavailable"] = {kind = "text"},
    ["library.reason.ordinary_has_locked_data"] = {kind = "text"},
    ["library.reason.ordinary_over_79"] = {kind = "text"},
    ["library.reason.record_binding_inconsistent"] = {kind = "text"},
    ["library.reason.record_build_identity_invalid"] = {kind = "text"},
    ["library.reason.record_catalog_build_id_mismatch"] = {kind = "text"},
    ["library.reason.record_catalog_identity_mismatch"] = {kind = "text"},
    ["library.reason.record_categories_build_disagree"] = {kind = "text"},
    ["library.reason.record_categories_locked_disagree"] = {kind = "text"},
    ["library.reason.record_echo_evidence_changed"] = {kind = "text"},
    ["library.reason.record_evidence_changed"] = {kind = "text"},
    ["library.reason.record_evidence_is_unavailable"] = {kind = "text"},
    ["library.reason.record_evidence_provider_ambiguous"] = {kind = "text"},
    ["library.reason.record_evidence_provider_invalid"] = {kind = "text"},
    ["library.reason.record_evidence_unavailable"] = {kind = "text"},
    ["library.reason.record_fingerprint_invalid"] = {kind = "text"},
    ["library.reason.record_fingerprint_mismatch"] = {kind = "text"},
    ["library.reason.record_fingerprint_unavailable"] = {kind = "text"},
    ["library.reason.record_identity_changed"] = {kind = "text"},
    ["library.reason.record_projection_changed"] = {kind = "text"},
    ["library.reason.record_projection_unavailable"] = {kind = "text"},
    ["library.reason.record_revision_provider_invalid"] = {kind = "text"},
    ["library.reason.record_revision_unavailable"] = {kind = "text"},
    ["library.reason.record_validation_failed"] = {kind = "text"},
    ["library.reason.record_validation_unavailable"] = {kind = "text"},
    ["library.reason.request_already_waiting"] = {kind = "text"},
    ["library.reason.request_invalid_build_id"] = {kind = "text"},
    ["library.reason.request_manual_mode"] = {kind = "text"},
    ["library.reason.request_not_connected"] = {kind = "text"},
    ["library.reason.request_not_in_library"] = {kind = "text"},
    ["library.reason.request_own_build"] = {kind = "text"},
    ["library.reason.request_owner_unverified"] = {kind = "text"},
    ["library.reason.request_queue_full"] = {kind = "text"},
    ["library.reason.request_roles_known"] = {kind = "text"},
    ["library.reason.roles_validation_unavailable"] = {kind = "text"},
    ["library.reason.share_already_queued"] = {kind = "text"},
    ["library.reason.share_duplicate_suppressed"] = {kind = "text"},
    ["library.reason.share_explicit_reset"] = {kind = "text"},
    ["library.reason.share_invalid_prepared"] = {kind = "text"},
    ["library.reason.share_no_echoes"] = {kind = "text"},
    ["library.reason.share_no_source"] = {kind = "text"},
    ["library.reason.share_queue_full"] = {kind = "text"},
    ["library.reason.share_queued"] = {kind = "text"},
    ["library.reason.share_queued_after_retry"] = {kind = "text"},
    ["library.reason.share_relay_unauthorized"] = {kind = "text"},
    ["library.reason.share_retry_admitted"] = {kind = "text"},
    ["library.reason.share_retry_exhausted"] = {kind = "text"},
    ["library.reason.share_retry_expired"] = {kind = "text"},
    ["library.reason.share_retry_stopped"] = {kind = "text"},
    ["library.reason.share_send_attempt"] = {kind = "text"},
    ["library.reason.share_source_changed"] = {kind = "text"},
    ["library.reason.share_source_empty"] = {kind = "text"},
    ["library.reason.share_stale_prepared"] = {kind = "text"},
    ["library.reason.share_superseded"] = {kind = "text"},
    ["library.reason.share_too_large"] = {kind = "text"},
    ["library.reason.share_transport_admitted"] = {kind = "text"},
    ["library.reason.sync_already_queued"] = {kind = "text"},
    ["library.reason.sync_cooldown"] = {kind = "text"},
    ["library.reason.sync_not_connected"] = {kind = "text"},
    ["library.reason.sync_paused"] = {kind = "text"},
    ["library.reason.sync_paused_resume"] = {kind = "text"},
    ["library.reason.sync_prep_failed"] = {kind = "text"},
    ["library.reason.sync_preparing"] = {kind = "text"},
    ["library.reason.transport_bandwidth"] = {kind = "text"},
    ["library.reason.transport_combat"] = {kind = "text"},
    ["library.status.share_outcome_reason"] = {kind = "template", fields = {"outcome", "reason"}, slots = {"text", "text"}, resultLimit = 2048},
    ["library.value.this_source"] = {kind = "text"},
    -- remainder_misc (10)
    ["command.chat.status_owned_synced"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 512},
    ["command.chat.status_owned_unsynced"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 512},
    ["command.chat.status_target"] = {kind = "template", fields = {"name", "source", "count"}, slots = {"text", "text", "count"}, resultLimit = 2048},
    ["command.chat.status_target_none"] = {kind = "text"},
    ["command.chat.status_target_none_note"] = {kind = "template", fields = {"note"}, slots = {"text"}, resultLimit = 2048},
    ["command.value.target_source_active"] = {kind = "text"},
    ["command.value.target_source_designed"] = {kind = "text"},
    ["command.value.target_source_wishlist"] = {kind = "text"},
    ["leaderboard.status.syncing_receiving"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["panel.value.status_unavailable"] = {kind = "text"},
    -- remainder_orb (307)
    ["orb.adapter.already_owns"] = {kind = "text"},
    ["orb.adapter.assignment_protection_changed"] = {kind = "text"},
    ["orb.adapter.auto_choice_unverifiable"] = {kind = "text"},
    ["orb.adapter.catalog_entry_changed"] = {kind = "text"},
    ["orb.adapter.choice_pending_or_empty"] = {kind = "text"},
    ["orb.adapter.choice_refused"] = {kind = "text"},
    ["orb.adapter.choices_malformed"] = {kind = "text"},
    ["orb.adapter.choices_unavailable"] = {kind = "text"},
    ["orb.adapter.class_unavailable"] = {kind = "text"},
    ["orb.adapter.context_changed_paused"] = {kind = "text"},
    ["orb.adapter.counts_exceed"] = {kind = "text"},
    ["orb.adapter.disable_rival"] = {kind = "text"},
    ["orb.adapter.discovery_unavailable"] = {kind = "text"},
    ["orb.adapter.echo_check_failed"] = {kind = "text"},
    ["orb.adapter.echo_disabled"] = {kind = "text"},
    ["orb.adapter.echo_protection_failed"] = {kind = "text"},
    ["orb.adapter.echo_state_changed"] = {kind = "text"},
    ["orb.adapter.id_only_interface"] = {kind = "text"},
    ["orb.adapter.invalid_source"] = {kind = "text"},
    ["orb.adapter.locked_record_over_limit"] = {kind = "text"},
    ["orb.adapter.locked_records_over_capacity"] = {kind = "template", fields = {"occupied", "capacity"}, slots = {"count", "count"}, resultLimit = 2048},
    ["orb.adapter.manual_choice_unobservable"] = {kind = "text"},
    ["orb.adapter.no_create_frame"] = {kind = "text"},
    ["orb.adapter.no_orbservice"] = {kind = "text"},
    ["orb.adapter.no_perkservice"] = {kind = "text"},
    ["orb.adapter.not_discovered"] = {kind = "text"},
    ["orb.adapter.observer_frame_failed"] = {kind = "text"},
    ["orb.adapter.offer_active_manual"] = {kind = "text"},
    ["orb.adapter.offer_changed"] = {kind = "text"},
    ["orb.adapter.offer_invalid"] = {kind = "text"},
    ["orb.adapter.offer_quality_unknown"] = {kind = "text"},
    ["orb.adapter.ownership_lock_unavailable"] = {kind = "text"},
    ["orb.adapter.ownership_shape"] = {kind = "text"},
    ["orb.adapter.ownership_unavailable"] = {kind = "text"},
    ["orb.adapter.ownership_unreadable"] = {kind = "text"},
    ["orb.adapter.ownership_unverified"] = {kind = "text"},
    ["orb.adapter.passive_diagnostics"] = {kind = "text"},
    ["orb.adapter.paused_not_sent"] = {kind = "text"},
    ["orb.adapter.pending_actions_unverifiable"] = {kind = "text"},
    ["orb.adapter.protection_failed"] = {kind = "text"},
    ["orb.adapter.resolve_current_action"] = {kind = "text"},
    ["orb.adapter.resume_prevented"] = {kind = "text"},
    ["orb.adapter.rival_may_interfere"] = {kind = "text"},
    ["orb.adapter.run_not_owner"] = {kind = "text"},
    ["orb.adapter.selection_unknown"] = {kind = "text"},
    ["orb.adapter.session_paused"] = {kind = "text"},
    ["orb.adapter.source_or_balance_changed"] = {kind = "text"},
    ["orb.adapter.spend_call_failed"] = {kind = "text"},
    ["orb.adapter.spend_refused"] = {kind = "text"},
    ["orb.adapter.state_capability_missing"] = {kind = "text"},
    ["orb.adapter.state_check_failed"] = {kind = "text"},
    ["orb.adapter.state_not_yet_known"] = {kind = "text"},
    ["orb.adapter.state_unavailable"] = {kind = "text"},
    ["orb.adapter.state_unavailable_sentence"] = {kind = "text"},
    ["orb.adapter.state_unknown"] = {kind = "text"},
    ["orb.adapter.target_changed"] = {kind = "text"},
    ["orb.adapter.tome_api_unavailable"] = {kind = "text"},
    ["orb.adapter.tome_api_unknown"] = {kind = "text"},
    ["orb.adapter.turn_off_auto_accept"] = {kind = "text"},
    ["orb.adapter.unreadable_error"] = {kind = "text"},
    ["orb.adapter.waiting_three_choices"] = {kind = "text"},
    ["orb.assignment.choose_or_create"] = {kind = "text"},
    ["orb.assignment.first_run_target"] = {kind = "text"},
    ["orb.assignment.first_run_unavailable"] = {kind = "text"},
    ["orb.assignment.mirror_absent"] = {kind = "text"},
    ["orb.assignment.mirror_not_distinct"] = {kind = "text"},
    ["orb.assignment.needs_locked_targets"] = {kind = "text"},
    ["orb.assignment.waiting_loadout"] = {kind = "text"},
    ["orb.continue.attribution_owned_gain"] = {kind = "block"},
    ["orb.continue.check_explanation"] = {kind = "block"},
    ["orb.continue.checking"] = {kind = "block"},
    ["orb.continue.checking_wait"] = {kind = "text"},
    ["orb.continue.choose_check_confirm"] = {kind = "text"},
    ["orb.continue.confirm"] = {kind = "template", fields = {"spent", "limit"}, slots = {"count", "count"}, resultLimit = 2048, lines = true},
    ["orb.continue.confirm_question"] = {kind = "text"},
    ["orb.continue.done"] = {kind = "block"},
    ["orb.continue.exit_consequences"] = {kind = "block"},
    ["orb.continue.intro"] = {kind = "block"},
    ["orb.continue.live_archive_full"] = {kind = "text"},
    ["orb.continue.live_archive_future"] = {kind = "text"},
    ["orb.continue.live_archive_malformed"] = {kind = "text"},
    ["orb.continue.live_archive_reserved"] = {kind = "block"},
    ["orb.continue.live_auto_accept"] = {kind = "text"},
    ["orb.continue.live_balance_mismatch"] = {kind = "text"},
    ["orb.continue.live_charge_refresh_failed"] = {kind = "text"},
    ["orb.continue.live_choice_query_unavailable"] = {kind = "text"},
    ["orb.continue.live_choice_request_failed"] = {kind = "text"},
    ["orb.continue.live_choice_unreadable"] = {kind = "text"},
    ["orb.continue.live_default"] = {kind = "text"},
    ["orb.continue.live_entry_too_large"] = {kind = "text"},
    ["orb.continue.live_late_choice"] = {kind = "text"},
    ["orb.continue.live_late_result"] = {kind = "text"},
    ["orb.continue.live_loading_transition"] = {kind = "text"},
    ["orb.continue.live_no_choice_observer"] = {kind = "text"},
    ["orb.continue.live_no_empty_choice_reply"] = {kind = "text"},
    ["orb.continue.live_no_observer"] = {kind = "text"},
    ["orb.continue.live_no_ownership"] = {kind = "text"},
    ["orb.continue.live_no_reply"] = {kind = "text"},
    ["orb.continue.live_no_retry_tail"] = {kind = "block"},
    ["orb.continue.live_observer_tainted"] = {kind = "text"},
    ["orb.continue.live_offer_or_action"] = {kind = "text"},
    ["orb.continue.live_own_choice_request"] = {kind = "text"},
    ["orb.continue.live_ownership_refresh_failed"] = {kind = "text"},
    ["orb.continue.live_pending_positive"] = {kind = "text"},
    ["orb.continue.live_receipt_changed"] = {kind = "text"},
    ["orb.continue.live_refresh_unavailable"] = {kind = "text"},
    ["orb.continue.live_rejected_packet"] = {kind = "text"},
    ["orb.continue.live_reply_changed"] = {kind = "text"},
    ["orb.continue.live_reply_unqualified"] = {kind = "text"},
    ["orb.continue.live_request_failed"] = {kind = "text"},
    ["orb.continue.live_rival"] = {kind = "text"},
    ["orb.continue.live_state_changed"] = {kind = "text"},
    ["orb.continue.live_transport_overflow"] = {kind = "text"},
    ["orb.continue.live_unreadable"] = {kind = "text"},
    ["orb.continue.live_write_failed"] = {kind = "text"},
    ["orb.continue.refusal_archive_full"] = {kind = "text"},
    ["orb.continue.refusal_archive_future"] = {kind = "text"},
    ["orb.continue.refusal_archive_malformed"] = {kind = "text"},
    ["orb.continue.refusal_archive_reserved"] = {kind = "text"},
    ["orb.continue.refusal_auto_accept"] = {kind = "text"},
    ["orb.continue.refusal_balance_mismatch"] = {kind = "text"},
    ["orb.continue.refusal_charge_refresh_failed"] = {kind = "text"},
    ["orb.continue.refusal_choice_query_unavailable"] = {kind = "text"},
    ["orb.continue.refusal_choice_recorded"] = {kind = "block"},
    ["orb.continue.refusal_choice_request_failed"] = {kind = "text"},
    ["orb.continue.refusal_choice_unreadable"] = {kind = "text"},
    ["orb.continue.refusal_entry_too_large"] = {kind = "text"},
    ["orb.continue.refusal_late_choice"] = {kind = "text"},
    ["orb.continue.refusal_late_result"] = {kind = "text"},
    ["orb.continue.refusal_loading_transition"] = {kind = "text"},
    ["orb.continue.refusal_no_choice_observer"] = {kind = "text"},
    ["orb.continue.refusal_no_empty_choice_reply"] = {kind = "text"},
    ["orb.continue.refusal_no_observer"] = {kind = "text"},
    ["orb.continue.refusal_no_ownership"] = {kind = "text"},
    ["orb.continue.refusal_no_receipt"] = {kind = "text"},
    ["orb.continue.refusal_no_reply"] = {kind = "text"},
    ["orb.continue.refusal_not_ready"] = {kind = "text"},
    ["orb.continue.refusal_not_restored"] = {kind = "block"},
    ["orb.continue.refusal_observer_tainted"] = {kind = "text"},
    ["orb.continue.refusal_offer_open"] = {kind = "text"},
    ["orb.continue.refusal_offer_or_action"] = {kind = "text"},
    ["orb.continue.refusal_other_character"] = {kind = "text"},
    ["orb.continue.refusal_own_choice_request"] = {kind = "text"},
    ["orb.continue.refusal_ownership_refresh_failed"] = {kind = "text"},
    ["orb.continue.refusal_pending_positive"] = {kind = "text"},
    ["orb.continue.refusal_receipt_changed"] = {kind = "text"},
    ["orb.continue.refusal_refresh_unavailable"] = {kind = "text"},
    ["orb.continue.refusal_rejected_packet"] = {kind = "text"},
    ["orb.continue.refusal_reply_changed"] = {kind = "text"},
    ["orb.continue.refusal_reply_unqualified"] = {kind = "text"},
    ["orb.continue.refusal_request_failed"] = {kind = "text"},
    ["orb.continue.refusal_rival"] = {kind = "text"},
    ["orb.continue.refusal_running"] = {kind = "text"},
    ["orb.continue.refusal_session_paused"] = {kind = "text"},
    ["orb.continue.refusal_spend_unconfirmed"] = {kind = "text"},
    ["orb.continue.refusal_stale_token"] = {kind = "text"},
    ["orb.continue.refusal_state_changed"] = {kind = "text"},
    ["orb.continue.refusal_transport_overflow"] = {kind = "text"},
    ["orb.continue.refusal_unreadable"] = {kind = "text"},
    ["orb.continue.refusal_write_failed"] = {kind = "text"},
    ["orb.guidance.action_not_confirmed"] = {kind = "text"},
    ["orb.guidance.choice_open"] = {kind = "text"},
    ["orb.guidance.finished"] = {kind = "text"},
    ["orb.guidance.finished_no_orbs"] = {kind = "text"},
    ["orb.guidance.finished_unknown"] = {kind = "text"},
    ["orb.guidance.last_action_unconfirmed"] = {kind = "text"},
    ["orb.guidance.locks_only"] = {kind = "text"},
    ["orb.guidance.no_orb_mode"] = {kind = "text"},
    ["orb.guidance.no_plan"] = {kind = "text"},
    ["orb.guidance.state_open_orbs"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 2048},
    ["orb.guidance.waiting_confirm"] = {kind = "text"},
    ["orb.policy.choose_resolved_wishlist"] = {kind = "text"},
    ["orb.policy.name"] = {kind = "text"},
    ["orb.policy.no_safe_target"] = {kind = "text"},
    ["orb.policy.targets_exceed"] = {kind = "text"},
    ["orb.policy.targets_invalid"] = {kind = "text"},
    ["orb.recovery.attribution"] = {kind = "block"},
    ["orb.recovery.board"] = {kind = "block"},
    ["orb.recovery.charges"] = {kind = "template", fields = {"observed", "expected"}, slots = {"text", "text"}, resultLimit = 2048, lines = true},
    ["orb.recovery.checking"] = {kind = "text"},
    ["orb.recovery.host"] = {kind = "text"},
    ["orb.recovery.loadout"] = {kind = "text"},
    ["orb.recovery.loadout_unknown"] = {kind = "block"},
    ["orb.recovery.offer"] = {kind = "template", fields = {"echo", "echo_again"}, slots = {"text", "text"}, resultLimit = 2048, lines = true},
    ["orb.recovery.offer_open"] = {kind = "block"},
    ["orb.recovery.offer_open_blind"] = {kind = "block"},
    ["orb.recovery.offer_open_proposed"] = {kind = "template", fields = {"echo"}, slots = {"text"}, resultLimit = 2048, lines = true},
    ["orb.recovery.offer_unmatched"] = {kind = "block"},
    ["orb.recovery.ownership"] = {kind = "block"},
    ["orb.recovery.permanent_changed"] = {kind = "text"},
    ["orb.recovery.unobservable"] = {kind = "block"},
    ["orb.recovery.wait_fresh_asked"] = {kind = "block"},
    ["orb.recovery.wait_offer"] = {kind = "block"},
    ["orb.recovery.wait_offer_blind"] = {kind = "block"},
    ["orb.recovery.wait_result"] = {kind = "block"},
    ["orb.runtime.assign_before_start"] = {kind = "text"},
    ["orb.runtime.automation_disable_failed"] = {kind = "text"},
    ["orb.runtime.automation_owner_missing"] = {kind = "text"},
    ["orb.runtime.blocked_cannot_confirm"] = {kind = "template", fields = {"subject"}, slots = {"text"}, resultLimit = 2048, lines = true},
    ["orb.runtime.blocked_observes_after_reload"] = {kind = "template", fields = {"subject"}, slots = {"text"}, resultLimit = 2048, lines = true},
    ["orb.runtime.blocked_run_paused"] = {kind = "template", fields = {"subject"}, slots = {"text"}, resultLimit = 2048},
    ["orb.runtime.blocked_submitted_unresolved"] = {kind = "template", fields = {"subject"}, slots = {"text"}, resultLimit = 2048},
    ["orb.runtime.blocked_unattributable_next"] = {kind = "template", fields = {"subject", "next_step"}, slots = {"text", "text"}, resultLimit = 2048},
    ["orb.runtime.blocked_unattributable_refusal"] = {kind = "template", fields = {"subject", "refusal"}, slots = {"text", "text"}, resultLimit = 2048},
    ["orb.runtime.bounded_recovery_stopped"] = {kind = "template", fields = {"why"}, slots = {"text"}, resultLimit = 2048},
    ["orb.runtime.cannot_start_yet"] = {kind = "template", fields = {"causes"}, slots = {"text"}, resultLimit = 2048},
    ["orb.runtime.character_data_not_ready"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 2048},
    ["orb.runtime.choose_echo_first"] = {kind = "text"},
    ["orb.runtime.count_request_pending"] = {kind = "text"},
    ["orb.runtime.different_choice_submitted"] = {kind = "text"},
    ["orb.runtime.different_echo_chosen"] = {kind = "block"},
    ["orb.runtime.earlier_attempt_may_match"] = {kind = "block"},
    ["orb.runtime.earlier_unresolved_unreadable"] = {kind = "template", fields = {"error"}, slots = {"text"}, resultLimit = 2048},
    ["orb.runtime.echo_choice_shown"] = {kind = "text"},
    ["orb.runtime.finish_orb_offer_first"] = {kind = "text"},
    ["orb.runtime.finished_exposure_unconfirmed"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 2048},
    ["orb.runtime.finished_limit_used"] = {kind = "template", fields = {"limit"}, slots = {"text"}, resultLimit = 2048},
    ["orb.runtime.format_marker_invalid"] = {kind = "template", fields = {"marker_type", "marker_text", "supported"}, slots = {"text", "text", "text"}, resultLimit = 2048},
    ["orb.runtime.format_unsupported"] = {kind = "template", fields = {"saved", "supported", "first", "last"}, slots = {"count", "count", "count", "count"}, resultLimit = 2048},
    ["orb.runtime.format_unverified"] = {kind = "template", fields = {"saved", "saved_again", "field", "supported"}, slots = {"count", "count", "text", "count"}, resultLimit = 2048},
    ["orb.runtime.gain_retained_unconfirmed"] = {kind = "text"},
    ["orb.runtime.gain_unattributable_refusal"] = {kind = "template", fields = {"refusal"}, slots = {"text"}, resultLimit = 2048},
    ["orb.runtime.held_choice"] = {kind = "template", fields = {"echo", "echo_again"}, slots = {"text", "text"}, resultLimit = 2048, lines = true},
    ["orb.runtime.history_changed"] = {kind = "text"},
    ["orb.runtime.history_no_reserved_space"] = {kind = "text"},
    ["orb.runtime.history_required"] = {kind = "text"},
    ["orb.runtime.history_risk"] = {kind = "text"},
    ["orb.runtime.history_unverified"] = {kind = "text"},
    ["orb.runtime.history_unverified_kept"] = {kind = "text"},
    ["orb.runtime.kept"] = {kind = "text"},
    ["orb.runtime.kind_needed_target"] = {kind = "text"},
    ["orb.runtime.kind_permitted_fallback"] = {kind = "text"},
    ["orb.runtime.kind_permitted_recycle"] = {kind = "text"},
    ["orb.runtime.last_action_unconfirmed"] = {kind = "text"},
    ["orb.runtime.last_replacement_ended"] = {kind = "text"},
    ["orb.runtime.limit_increased_resume"] = {kind = "text"},
    ["orb.runtime.limit_reached"] = {kind = "text"},
    ["orb.runtime.loadout_or_wishlist_changed"] = {kind = "text"},
    ["orb.runtime.loadout_unverifiable"] = {kind = "block"},
    ["orb.runtime.locked_targets_unchangeable_tail"] = {kind = "text"},
    ["orb.runtime.marker_type_unknown"] = {kind = "text"},
    ["orb.runtime.matched_preparing_next"] = {kind = "text"},
    ["orb.runtime.matched_review_wishlist"] = {kind = "block"},
    ["orb.runtime.matched_wait_continue"] = {kind = "text"},
    ["orb.runtime.missing_target_unavailable"] = {kind = "template", fields = {"echo", "reason"}, slots = {"text", "text"}, resultLimit = 2048},
    ["orb.runtime.next_step_open"] = {kind = "text"},
    ["orb.runtime.next_step_stop_open"] = {kind = "text"},
    ["orb.runtime.no_assigned_wishlist"] = {kind = "text"},
    ["orb.runtime.no_authoritative_result"] = {kind = "text"},
    ["orb.runtime.no_exit"] = {kind = "block"},
    ["orb.runtime.no_wishlist_selected"] = {kind = "text"},
    ["orb.runtime.nothing_changed"] = {kind = "text"},
    ["orb.runtime.orb_offer_shown"] = {kind = "text"},
    ["orb.runtime.pause_before_limit"] = {kind = "text"},
    ["orb.runtime.paused_refinement_owns"] = {kind = "template", fields = {"subject"}, slots = {"text"}, resultLimit = 2048},
    ["orb.runtime.preferences_not_durable"] = {kind = "text"},
    ["orb.runtime.preferences_not_preserved"] = {kind = "text"},
    ["orb.runtime.progress_attribution_ambiguous"] = {kind = "text"},
    ["orb.runtime.receipt_exit_unreserved"] = {kind = "text"},
    ["orb.runtime.receipt_other_character"] = {kind = "text"},
    ["orb.runtime.recovered_past"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 2048},
    ["orb.runtime.recoveries_used"] = {kind = "block"},
    ["orb.runtime.recovery_checking_choice"] = {kind = "text"},
    ["orb.runtime.recovery_context_changed"] = {kind = "text"},
    ["orb.runtime.recovery_epoch_invalidated"] = {kind = "text"},
    ["orb.runtime.recovery_loading_invalidated"] = {kind = "text"},
    ["orb.runtime.recovery_needs_fresh_reply"] = {kind = "text"},
    ["orb.runtime.recovery_observations_lost"] = {kind = "text"},
    ["orb.runtime.recovery_observations_unavailable"] = {kind = "text"},
    ["orb.runtime.recovery_request_invalidated"] = {kind = "text"},
    ["orb.runtime.recovery_retained_unconfirmed"] = {kind = "text"},
    ["orb.runtime.recovery_state_unpreserved"] = {kind = "text"},
    ["orb.runtime.recovery_status_unavailable"] = {kind = "text"},
    ["orb.runtime.recovery_unclassified"] = {kind = "text"},
    ["orb.runtime.refresh_requested"] = {kind = "text"},
    ["orb.runtime.replacement_matched_baseline"] = {kind = "text"},
    ["orb.runtime.required_target_unavailable"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 2048},
    ["orb.runtime.resuming_without_reset"] = {kind = "text"},
    ["orb.runtime.review_increased_limit"] = {kind = "text"},
    ["orb.runtime.rolled_complete_locked_remain"] = {kind = "text"},
    ["orb.runtime.rolled_complete_unresolved"] = {kind = "block"},
    ["orb.runtime.run_already_active"] = {kind = "text"},
    ["orb.runtime.same_id_indistinguishable"] = {kind = "block"},
    ["orb.runtime.saved_data_not_ready"] = {kind = "text"},
    ["orb.runtime.session_interrupted"] = {kind = "text"},
    ["orb.runtime.settle_before_target_change"] = {kind = "text"},
    ["orb.runtime.settle_run_first"] = {kind = "text"},
    ["orb.runtime.spend_refused_after_permit"] = {kind = "text"},
    ["orb.runtime.state_not_sent"] = {kind = "text"},
    ["orb.runtime.subject_new_run"] = {kind = "text"},
    ["orb.runtime.subject_ordinary_rolling"] = {kind = "text"},
    ["orb.runtime.subject_source_change"] = {kind = "text"},
    ["orb.runtime.subject_target_change"] = {kind = "text"},
    ["orb.runtime.subject_this_action"] = {kind = "text"},
    ["orb.runtime.subject_this_change"] = {kind = "text"},
    ["orb.runtime.submitted_unresolved"] = {kind = "block"},
    ["orb.runtime.unobserved"] = {kind = "block"},
    ["orb.runtime.waiting_fresh_confirmation"] = {kind = "text"},
    ["orb.runtime.world_loading"] = {kind = "text"},
    ["orb.runtime.world_settling"] = {kind = "text"},
    ["orb.runtime.write_container"] = {kind = "text"},
    ["orb.runtime.write_database"] = {kind = "text"},
    ["orb.runtime.write_identity"] = {kind = "text"},
    ["orb.runtime.write_lifecycle"] = {kind = "text"},
    ["orb.runtime.write_lifecycle_loading"] = {kind = "text"},
    ["orb.runtime.write_marker"] = {kind = "text"},
    ["orb.runtime.write_row"] = {kind = "text"},
    -- remainder_runtime_chat (24)
    ["adapter.chat.action_pending_released"] = {kind = "template", fields = {"action"}, slots = {"text"}, resultLimit = 2048},
    ["adapter.chat.outside_select_pending"] = {kind = "block"},
    ["adapter.chat.select_unresolved_seen"] = {kind = "block"},
    ["adapter.chat.select_unresolved_seen_competing"] = {kind = "block"},
    ["adapter.chat.select_unresolved_unseen"] = {kind = "block"},
    ["adapter.chat.select_unresolved_unseen_competing"] = {kind = "block"},
    ["adapter.chat.selection_pending_held"] = {kind = "text"},
    ["automation.chat.auto_on_paused"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 2048},
    ["automation.chat.first_run_create_failed"] = {kind = "text"},
    ["automation.chat.first_run_no_slot"] = {kind = "text"},
    ["automation.chat.first_run_not_confirmed"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 2048},
    ["automation.chat.first_run_saved"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 2048},
    ["automation.chat.first_run_storing"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 2048},
    ["automation.chat.first_run_unconfirmed_reset"] = {kind = "block"},
    ["automation.chat.lock_failed"] = {kind = "template", fields = {"echo", "error"}, slots = {"text", "text"}, resultLimit = 2048},
    ["automation.chat.lock_sent"] = {kind = "template", fields = {"echo"}, slots = {"text"}, resultLimit = 2048},
    ["automation.chat.no_active_saved_build"] = {kind = "block"},
    ["automation.chat.no_improvement"] = {kind = "template", fields = {"needed"}, slots = {"text"}, resultLimit = 2048},
    ["automation.chat.save_sent"] = {kind = "template", fields = {"change", "needed"}, slots = {"text", "text"}, resultLimit = 2048},
    ["automation.chat.unlock_failed"] = {kind = "template", fields = {"echo", "error"}, slots = {"text", "text"}, resultLimit = 2048},
    ["automation.chat.unlocked_ready"] = {kind = "template", fields = {"old", "new"}, slots = {"text", "text"}, resultLimit = 2048},
    ["automation.value.first_completed_run"] = {kind = "text"},
    ["automation.value.loadout_improved"] = {kind = "text"},
    ["automation.value.none_needed"] = {kind = "text"},
    -- remainder_runtime_status (35)
    ["automation.status.auto_paused"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1024},
    ["automation.status.banish_refused"] = {kind = "text"},
    ["automation.status.banished_echo"] = {kind = "template", fields = {"open", "close", "index"}, slots = {"text", "text", "count"}, resultLimit = 1024},
    ["automation.status.choose_or_create"] = {kind = "text"},
    ["automation.status.error_see_err"] = {kind = "text"},
    ["automation.status.final_banish_refused"] = {kind = "text"},
    ["automation.status.final_reroll_refused"] = {kind = "text"},
    ["automation.status.finishing_count"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 1024},
    ["automation.status.finishing_count_unsynced"] = {kind = "text"},
    ["automation.status.finishing_final_selections"] = {kind = "text"},
    ["automation.status.first_run_no_free_slot"] = {kind = "text"},
    ["automation.status.first_run_not_confirmed"] = {kind = "text"},
    ["automation.status.first_run_save_activate"] = {kind = "text"},
    ["automation.status.first_run_save_manually"] = {kind = "text"},
    ["automation.status.first_run_save_sent"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 1024},
    ["automation.status.first_run_saved"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 1024},
    ["automation.status.first_run_wishlist_active"] = {kind = "text"},
    ["automation.status.froze_echo"] = {kind = "template", fields = {"open", "close", "index"}, slots = {"text", "text", "count"}, resultLimit = 1024},
    ["automation.status.loadout_changed_cancelled"] = {kind = "text"},
    ["automation.status.no_improvement"] = {kind = "template", fields = {"wishlist", "detail"}, slots = {"text", "text"}, resultLimit = 1024},
    ["automation.status.no_wishlist_advisor"] = {kind = "text"},
    ["automation.status.no_wishlist_not_saving"] = {kind = "text"},
    ["automation.status.orb_keeps_auto_off"] = {kind = "text"},
    ["automation.status.paused_keeps_auto_off"] = {kind = "text"},
    ["automation.status.reroll_refused"] = {kind = "text"},
    ["automation.status.save_confirmed"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 1024},
    ["automation.status.save_matched_loadout_changed"] = {kind = "text"},
    ["automation.status.save_sent_checking"] = {kind = "text"},
    ["automation.status.save_sent_checking_seconds"] = {kind = "template", fields = {"slot", "seconds"}, slots = {"count", "text"}, resultLimit = 1024},
    ["automation.status.save_unconfirmed"] = {kind = "text"},
    ["automation.status.saved_unchanged_no_run"] = {kind = "text"},
    ["automation.status.waiting_board"] = {kind = "text"},
    ["automation.status.waiting_project_ebonhold"] = {kind = "text"},
    ["automation.status.waiting_slot_data"] = {kind = "text"},
    ["automation.status.warning_keeps_auto_off"] = {kind = "text"},
    -- remainder_wishlist_chat (81)
    ["editor.notify.adapter_not_ready"] = {kind = "text"},
    ["editor.notify.added_locked_target"] = {kind = "template", fields = {"echo"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.already_created"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.already_designed_locked"] = {kind = "template", fields = {"echo"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.already_locked"] = {kind = "template", fields = {"echo"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.apply_failed"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.apply_no_echoes"] = {kind = "text"},
    ["editor.notify.apply_no_valid_echoes"] = {kind = "text"},
    ["editor.notify.apply_refused"] = {kind = "text"},
    ["editor.notify.apply_spacing"] = {kind = "text"},
    ["editor.notify.assign_locked_slot"] = {kind = "text"},
    ["editor.notify.assigned_to"] = {kind = "template", fields = {"name", "destination"}, slots = {"text", "text"}, resultLimit = 2048},
    ["editor.notify.assignment_changed_open"] = {kind = "template", fields = {"destination"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.assignment_failed"] = {kind = "text"},
    ["editor.notify.assignment_failed_reason"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.associated_unavailable"] = {kind = "text"},
    ["editor.notify.auto_lock_not_changed"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.auto_lock_session_only"] = {kind = "template", fields = {"state", "note"}, slots = {"text", "text"}, resultLimit = 2048},
    ["editor.notify.cancelled"] = {kind = "text"},
    ["editor.notify.confirmation_used"] = {kind = "text"},
    ["editor.notify.copy_save_refused"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.copy_stale"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.copy_unavailable"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.copy_validation_unavailable"] = {kind = "text"},
    ["editor.notify.design_ambiguous"] = {kind = "block"},
    ["editor.notify.design_invalid"] = {kind = "block"},
    ["editor.notify.design_limit"] = {kind = "template", fields = {"count", "max"}, slots = {"count", "count"}, resultLimit = 2048},
    ["editor.notify.designed_locked"] = {kind = "template", fields = {"echo"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.destination_changed"] = {kind = "block"},
    ["editor.notify.destination_empty"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.first_run_target"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.host_error"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.identity_found_awaiting"] = {kind = "text"},
    ["editor.notify.import_overflow_unassigned"] = {kind = "template", fields = {"max", "count"}, slots = {"count", "count"}, resultLimit = 2048},
    ["editor.notify.intent_unrecognised"] = {kind = "text"},
    ["editor.notify.label_first_run"] = {kind = "text"},
    ["editor.notify.label_saved_build_named"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.label_saved_build_number"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.local_targets_unsaved"] = {kind = "text"},
    ["editor.notify.lock_budget_exceeded"] = {kind = "template", fields = {"count", "max"}, slots = {"count", "count"}, resultLimit = 2048},
    ["editor.notify.lock_design_collisions"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 2048},
    ["editor.notify.lock_designs_full"] = {kind = "template", fields = {"max"}, slots = {"count"}, resultLimit = 2048},
    ["editor.notify.lock_slots_occupied"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 2048},
    ["editor.notify.lock_slots_unstated"] = {kind = "template", fields = {"max"}, slots = {"count"}, resultLimit = 2048},
    ["editor.notify.locked_swaps_many"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 2048, lines = true},
    ["editor.notify.locked_swaps_one"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 2048, lines = true},
    ["editor.notify.maybe_sent"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048, lines = true},
    ["editor.notify.mirror_unresolved"] = {kind = "block"},
    ["editor.notify.name_character_dropped"] = {kind = "template", fields = {"character", "name"}, slots = {"text", "text"}, resultLimit = 2048},
    ["editor.notify.name_listed_renamed"] = {kind = "template", fields = {"name", "unique"}, slots = {"text", "text"}, resultLimit = 2048},
    ["editor.notify.name_required"] = {kind = "text"},
    ["editor.notify.name_taken"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.no_destination"] = {kind = "text"},
    ["editor.notify.no_free_name"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.normal_full_move_back"] = {kind = "text"},
    ["editor.notify.overflow_not_locked"] = {kind = "template", fields = {"max", "count"}, slots = {"count", "count"}, resultLimit = 2048},
    ["editor.notify.pending_empty"] = {kind = "text"},
    ["editor.notify.plan_replacement"] = {kind = "block"},
    ["editor.notify.reason_record_ambiguous"] = {kind = "text"},
    ["editor.notify.reason_record_changed"] = {kind = "text"},
    ["editor.notify.retry_cancelled"] = {kind = "text"},
    ["editor.notify.save_cancelled_changed"] = {kind = "text"},
    ["editor.notify.save_in_progress"] = {kind = "text"},
    ["editor.notify.save_pending_spacing"] = {kind = "text"},
    ["editor.notify.saved"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 2048},
    ["editor.notify.saved_no_destination"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.saved_not_captured"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.saved_not_loaded"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.saved_session_only"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 2048},
    ["editor.notify.saved_unassigned_new"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.saved_unassigned_opened"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.server_slot_stale"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.server_slot_stale_missing"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.uploaded_assignment_kept"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048},
    ["editor.notify.uploaded_draft_changed"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048, lines = true},
    ["editor.notify.value_active_saved_build"] = {kind = "text"},
    ["editor.notify.value_off"] = {kind = "text"},
    ["editor.notify.value_on"] = {kind = "text"},
    ["editor.notify.value_that_echo"] = {kind = "text"},
    ["editor.notify.wishlist_full"] = {kind = "text"},
    ["editor.notify.wishlist_full_use_locked"] = {kind = "text"},
    -- remainder_wishlist_reasons (44)
    ["editor.reason.a_save_is_pending_return_after_it_settles"] = {kind = "text"},
    ["editor.reason.close_plan_alternatives_or_finish_its"] = {kind = "text"},
    ["editor.reason.context_changed_choose_whether_to_discard"] = {kind = "text"},
    ["editor.reason.deletion_support_is_unknown"] = {kind = "text"},
    ["editor.reason.every_saved_build_already_holds_a_plan_this"] = {kind = "text"},
    ["editor.reason.finish_or_cancel_the_imported_wishlist_name"] = {kind = "text"},
    ["editor.reason.finish_or_cancel_the_pending_save_before"] = {kind = "text"},
    ["editor.reason.first_run_association_unavailable"] = {kind = "text"},
    ["editor.reason.imported_echo_evidence_is_invalid"] = {kind = "text"},
    ["editor.reason.imported_echo_evidence_is_unavailable"] = {kind = "text"},
    ["editor.reason.invalid_active_loadout"] = {kind = "text"},
    ["editor.reason.invalid_loadout"] = {kind = "text"},
    ["editor.reason.invalid_wishlist"] = {kind = "text"},
    ["editor.reason.loadout_association_unavailable"] = {kind = "text"},
    ["editor.reason.locked_echo_evidence_is_invalid"] = {kind = "text"},
    ["editor.reason.locked_echo_evidence_validator_is"] = {kind = "text"},
    ["editor.reason.no_plan_was_selected"] = {kind = "text"},
    ["editor.reason.no_workspace_draft"] = {kind = "text"},
    ["editor.reason.nothing_could_be_restored"] = {kind = "text"},
    ["editor.reason.nothing_was_removed_in_a_way_this_can"] = {kind = "text"},
    ["editor.reason.ordinary_echo_evidence_exceeds_the_79_copy"] = {kind = "text"},
    ["editor.reason.ordinary_echo_evidence_is_invalid"] = {kind = "text"},
    ["editor.reason.plan_action_refused"] = {kind = "text"},
    ["editor.reason.plan_action_unavailable"] = {kind = "text"},
    ["editor.reason.plan_draft_protection_is_unavailable"] = {kind = "text"},
    ["editor.reason.plan_is_not_open"] = {kind = "text"},
    ["editor.reason.role_selection_must_preserve_every_original"] = {kind = "text"},
    ["editor.reason.saved_build_context_is_not_known"] = {kind = "text"},
    ["editor.reason.saved_data_is_not_writable_right_now"] = {kind = "text"},
    ["editor.reason.store_unavailable"] = {kind = "text"},
    ["editor.reason.that_exact_plan_is_no_longer_retained"] = {kind = "text"},
    ["editor.reason.that_loadout_slot_is_empty_or_unavailable"] = {kind = "text"},
    ["editor.reason.that_plan_could_not_be_removed"] = {kind = "text"},
    ["editor.reason.the_exact_plan_identity_is_required"] = {kind = "text"},
    ["editor.reason.the_selected_wishlist_is_not_currently"] = {kind = "text"},
    ["editor.reason.the_wishlist_has_no_current_server_slot"] = {kind = "text"},
    ["editor.reason.this_build_cannot_remove_a_saved_wishlist"] = {kind = "text"},
    ["editor.reason.this_build_cannot_restore_a_removed_wishlist"] = {kind = "text"},
    ["editor.reason.this_client_build_exposes_no_wishlist"] = {kind = "text"},
    ["editor.reason.this_wishlist_changed_while_the_role_picker"] = {kind = "text"},
    ["editor.reason.this_wishlist_now_provides_different_locked"] = {kind = "text"},
    ["editor.reason.typed_echo_evidence_is_unavailable"] = {kind = "text"},
    ["editor.reason.wishlist_association_failed"] = {kind = "text"},
    ["editor.reason.wishlist_identity_or_structure_is_invalid"] = {kind = "text"},
    -- usertext (261)
    ["count.copies_progress"] = {kind = "template", fields = {"have", "want"}, slots = {"count", "count"}, resultLimit = 400},
    ["count.copies_unavailable"] = {kind = "text"},
    ["count.echo_families"] = {kind = "text"},
    ["count.families_progress"] = {kind = "template", fields = {"have", "want"}, slots = {"count", "count"}, resultLimit = 400},
    ["count.families_unavailable"] = {kind = "text"},
    ["count.locked_progress"] = {kind = "template", fields = {"have", "want"}, slots = {"count", "count"}, resultLimit = 400},
    ["count.locked_targets"] = {kind = "text"},
    ["count.locked_unavailable"] = {kind = "text"},
    ["count.planned_copies"] = {kind = "text"},
    ["count.planned_progress"] = {kind = "template", fields = {"have", "want"}, slots = {"count", "count"}, resultLimit = 400},
    ["count.planned_unavailable"] = {kind = "text"},
    ["count.rolled_unavailable_compact"] = {kind = "text"},
    ["count.run_copies"] = {kind = "text"},
    ["count.run_progress"] = {kind = "template", fields = {"have", "want"}, slots = {"count", "count"}, resultLimit = 400},
    ["count.run_progress_compact"] = {kind = "template", fields = {"have", "want"}, slots = {"count", "count"}, resultLimit = 400},
    ["count.run_to_lock"] = {kind = "template", fields = {"have", "want", "outstanding"}, slots = {"count", "count", "count"}, resultLimit = 400},
    ["count.run_to_lock_compact"] = {kind = "template", fields = {"have", "want", "outstanding"}, slots = {"count", "count", "count"}, resultLimit = 400},
    ["count.run_unavailable"] = {kind = "text"},
    ["count.saved_build_copies"] = {kind = "text"},
    ["count.saved_build_progress"] = {kind = "template", fields = {"have", "want"}, slots = {"count", "count"}, resultLimit = 400},
    ["count.saved_build_unavailable"] = {kind = "text"},
    ["reason.assign_wishlist_targets"] = {kind = "text"},
    ["reason.banish_find_targets"] = {kind = "text"},
    ["reason.banish_unneeded_before_reroll"] = {kind = "text"},
    ["reason.choose_locked_targets"] = {kind = "template", fields = {"details"}, slots = {"text"}, resultLimit = 2048},
    ["reason.complete_take_outside"] = {kind = "text"},
    ["reason.draft_changed"] = {kind = "template", fields = {"details"}, slots = {"text"}, resultLimit = 2048},
    ["reason.few_selections_remain"] = {kind = "text"},
    ["reason.freeze_needed_before_search"] = {kind = "text"},
    ["reason.freeze_one_needed"] = {kind = "text"},
    ["reason.guaranteed_offer_marked"] = {kind = "text"},
    ["reason.library_preparing"] = {kind = "text"},
    ["reason.no_guarantee_after_activate"] = {kind = "text"},
    ["reason.no_wishlist_advisor"] = {kind = "text"},
    ["reason.not_saved_adds_excess"] = {kind = "text"},
    ["reason.not_saved_coverage_lost"] = {kind = "text"},
    ["reason.not_saved_fewer_copies"] = {kind = "template", fields = {"lost", "gained", "fewer"}, slots = {"count", "count", "count"}, resultLimit = 600},
    ["reason.not_saved_no_gain"] = {kind = "text"},
    ["reason.orb_active_or_unconfirmed"] = {kind = "text"},
    ["reason.orb_knownness_unreported"] = {kind = "text"},
    ["reason.orb_offer_active"] = {kind = "text"},
    ["reason.orb_state_not_confirmed"] = {kind = "text"},
    ["reason.orb_state_unexposed"] = {kind = "text"},
    ["reason.orb_state_unreadable"] = {kind = "text"},
    ["reason.record_key_unsupported"] = {kind = "text"},
    ["reason.removing_expired_requests"] = {kind = "text"},
    ["reason.reroll_no_requested"] = {kind = "text"},
    ["reason.reroll_none_needed"] = {kind = "text"},
    ["reason.reroll_unneeded_guaranteed"] = {kind = "text"},
    ["reason.safety_disablements_cleared"] = {kind = "text"},
    ["reason.saved_build_invalid"] = {kind = "text"},
    ["reason.shared_data_preparing"] = {kind = "text"},
    ["reason.take_available"] = {kind = "text"},
    ["reason.take_held_needed"] = {kind = "text"},
    ["reason.take_needed"] = {kind = "text"},
    ["reason.take_outside_no_search"] = {kind = "text"},
    ["reason.take_outside_wishlist"] = {kind = "text"},
    ["reason.unknown_code"] = {kind = "template", fields = {"code"}, slots = {"text"}, resultLimit = 1400},
    ["reason.use_shown_offer"] = {kind = "text"},
    ["reason.wait_echo_data"] = {kind = "text"},
    ["reason.wait_locked_echo_list"] = {kind = "template", fields = {"details"}, slots = {"text"}, resultLimit = 2048},
    ["reason.wait_remaining_choice_count"] = {kind = "text"},
    ["reason.wait_send_rate"] = {kind = "text"},
    ["reason.wait_server_wishlist"] = {kind = "template", fields = {"details"}, slots = {"text"}, resultLimit = 2048},
    ["reason.wishlist_unusable"] = {kind = "text"},
    ["term.best_known"] = {kind = "text"},
    ["term.echo_availability_controls"] = {kind = "text"},
    ["term.first_run_target"] = {kind = "text"},
    ["term.mine_scope"] = {kind = "text"},
    ["term.my_builds"] = {kind = "text"},
    ["term.options"] = {kind = "text"},
    ["term.saved_build_named"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1400},
    ["term.saved_build_named_slot"] = {kind = "template", fields = {"name", "slot"}, slots = {"text", "text"}, resultLimit = 1400},
    ["term.saved_build_slot"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 200},
    ["term.show_records"] = {kind = "text"},
    ["usertext.body.glossary"] = {kind = "block"},
    ["usertext.label.availability_control"] = {kind = "template", fields = {"id"}, slots = {"text"}, resultLimit = 400},
    ["usertext.label.card_different_quality"] = {kind = "text"},
    ["usertext.label.card_frozen_offer"] = {kind = "text"},
    ["usertext.label.card_held_offer"] = {kind = "text"},
    ["usertext.label.card_needed"] = {kind = "text"},
    ["usertext.label.card_not_on_wishlist"] = {kind = "text"},
    ["usertext.label.card_not_taken_now"] = {kind = "text"},
    ["usertext.label.card_target_met"] = {kind = "text"},
    ["usertext.label.category_both"] = {kind = "text"},
    ["usertext.label.category_lich_king"] = {kind = "text"},
    ["usertext.label.category_training_dummy"] = {kind = "text"},
    ["usertext.label.character_line"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1400},
    ["usertext.label.destination_line"] = {kind = "template", fields = {"destination"}, slots = {"text"}, resultLimit = 1800},
    ["usertext.label.details"] = {kind = "template", fields = {"code"}, slots = {"text"}, resultLimit = 1400},
    ["usertext.label.details_no_code"] = {kind = "text"},
    ["usertext.label.field_character"] = {kind = "text"},
    ["usertext.label.field_saved_build"] = {kind = "text"},
    ["usertext.label.field_state"] = {kind = "text"},
    ["usertext.label.field_wishlist"] = {kind = "text"},
    ["usertext.label.leaderboard_scope"] = {kind = "text"},
    ["usertext.label.mark_done"] = {kind = "text"},
    ["usertext.label.mark_info"] = {kind = "text"},
    ["usertext.label.mark_not_known"] = {kind = "text"},
    ["usertext.label.mark_todo"] = {kind = "text"},
    ["usertext.label.mark_waiting"] = {kind = "text"},
    ["usertext.label.owner_not_established"] = {kind = "text"},
    ["usertext.label.owner_verified"] = {kind = "text"},
    ["usertext.label.setup_destination"] = {kind = "text"},
    ["usertext.label.setup_startup"] = {kind = "text"},
    ["usertext.label.setup_wishlist"] = {kind = "text"},
    ["usertext.label.tome_control"] = {kind = "template", fields = {"name", "id"}, slots = {"text", "text"}, resultLimit = 1400},
    ["usertext.label.wishlist_line"] = {kind = "template", fields = {"wishlist"}, slots = {"text"}, resultLimit = 1800},
    ["usertext.note.record_scope"] = {kind = "text"},
    ["usertext.status.auto_not_known"] = {kind = "text"},
    ["usertext.status.auto_off"] = {kind = "text"},
    ["usertext.status.auto_on"] = {kind = "text"},
    ["usertext.status.auto_on_held"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 2048},
    ["usertext.status.control_detail"] = {kind = "template", fields = {"control", "detail"}, slots = {"text", "text"}, resultLimit = 2048},
    ["usertext.status.disabling_control"] = {kind = "template", fields = {"control"}, slots = {"text"}, resultLimit = 1400},
    ["usertext.status.enabling_control"] = {kind = "template", fields = {"control"}, slots = {"text"}, resultLimit = 1400},
    ["usertext.status.orb_last_reason"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 2048},
    ["usertext.status.orb_line"] = {kind = "template", fields = {"state"}, slots = {"text"}, resultLimit = 2048},
    ["usertext.status.orb_line_pending"] = {kind = "template", fields = {"state"}, slots = {"text"}, resultLimit = 2048},
    ["usertext.status.orb_none_approved"] = {kind = "text"},
    ["usertext.status.orb_not_read"] = {kind = "text"},
    ["usertext.status.orb_operation"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 2048},
    ["usertext.status.orb_review"] = {kind = "text"},
    ["usertext.status.orb_state_code"] = {kind = "template", fields = {"code"}, slots = {"text"}, resultLimit = 2048},
    ["usertext.status.orb_state_complete"] = {kind = "text"},
    ["usertext.status.orb_state_finished"] = {kind = "text"},
    ["usertext.status.orb_state_limit"] = {kind = "text"},
    ["usertext.status.orb_state_no_sources"] = {kind = "text"},
    ["usertext.status.orb_state_not_known"] = {kind = "text"},
    ["usertext.status.orb_state_out_of_orbs"] = {kind = "text"},
    ["usertext.status.orb_state_paused"] = {kind = "text"},
    ["usertext.status.orb_state_rolled_complete"] = {kind = "text"},
    ["usertext.status.orb_state_running"] = {kind = "text"},
    ["usertext.status.orb_state_stopped"] = {kind = "text"},
    ["usertext.status.orb_state_unresolved"] = {kind = "text"},
    ["usertext.status.orb_status_not_known"] = {kind = "text"},
    ["usertext.status.setup_after_startup"] = {kind = "text"},
    ["usertext.status.setup_dest_active"] = {kind = "text"},
    ["usertext.status.setup_dest_active_named"] = {kind = "template", fields = {"build"}, slots = {"text"}, resultLimit = 1600},
    ["usertext.status.setup_dest_empty"] = {kind = "text"},
    ["usertext.status.setup_dest_empty_named"] = {kind = "template", fields = {"build"}, slots = {"text"}, resultLimit = 1600},
    ["usertext.status.setup_dest_first_run"] = {kind = "text"},
    ["usertext.status.setup_dest_not_confirmed"] = {kind = "text"},
    ["usertext.status.setup_dest_not_loaded"] = {kind = "text"},
    ["usertext.status.setup_dest_restoring"] = {kind = "text"},
    ["usertext.status.setup_dest_unavailable"] = {kind = "text"},
    ["usertext.status.setup_dest_unavailable_named"] = {kind = "template", fields = {"build"}, slots = {"text"}, resultLimit = 1600},
    ["usertext.status.setup_dest_unconfirmed"] = {kind = "text"},
    ["usertext.status.setup_no_run_shown"] = {kind = "text"},
    ["usertext.status.setup_startup_loading"] = {kind = "text"},
    ["usertext.status.setup_startup_ready"] = {kind = "text"},
    ["usertext.status.setup_startup_unknown"] = {kind = "text"},
    ["usertext.status.setup_wishlist_assigned"] = {kind = "text"},
    ["usertext.status.setup_wishlist_assigned_named"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1600},
    ["usertext.status.setup_wishlist_needs_build"] = {kind = "text"},
    ["usertext.status.setup_wishlist_none"] = {kind = "text"},
    ["usertext.status.setup_wishlist_not_known"] = {kind = "text"},
    ["usertext.status.setup_wishlist_restoring"] = {kind = "text"},
    ["usertext.status.setup_wishlist_unavailable"] = {kind = "text"},
    ["usertext.status.setup_wishlist_unavailable_named"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1600},
    ["usertext.status.sync_automatic"] = {kind = "text"},
    ["usertext.status.sync_manual"] = {kind = "text"},
    ["usertext.status.sync_not_known"] = {kind = "text"},
    ["usertext.status.sync_not_saved_choice"] = {kind = "template", fields = {"line"}, slots = {"text"}, resultLimit = 2048},
    ["usertext.status.sync_off"] = {kind = "text"},
    ["usertext.tooltip.captured_lead"] = {kind = "text"},
    ["usertext.tooltip.captured_refused"] = {kind = "text"},
    ["usertext.tooltip.captured_stated"] = {kind = "text"},
    ["usertext.tooltip.captured_unchecked"] = {kind = "text"},
    ["usertext.tooltip.field_line"] = {kind = "template", fields = {"label", "value"}, slots = {"text", "text"}, resultLimit = 2048},
    ["usertext.tooltip.preview"] = {kind = "text"},
    ["usertext.value.build_active"] = {kind = "text"},
    ["usertext.value.build_active_cell"] = {kind = "text"},
    ["usertext.value.build_cell_none_captured"] = {kind = "text"},
    ["usertext.value.build_cell_none_in_use"] = {kind = "text"},
    ["usertext.value.build_cell_not_confirmed"] = {kind = "text"},
    ["usertext.value.build_cell_not_known_yet"] = {kind = "text"},
    ["usertext.value.build_cell_not_loaded_yet"] = {kind = "text"},
    ["usertext.value.build_empty"] = {kind = "text"},
    ["usertext.value.build_empty_cell"] = {kind = "text"},
    ["usertext.value.build_inactive"] = {kind = "text"},
    ["usertext.value.build_inactive_cell"] = {kind = "text"},
    ["usertext.value.build_name_slot"] = {kind = "template", fields = {"name", "slot"}, slots = {"text", "text"}, resultLimit = 1400},
    ["usertext.value.build_slot"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 200},
    ["usertext.value.build_state_not_known"] = {kind = "text"},
    ["usertext.value.build_state_not_known_cell"] = {kind = "text"},
    ["usertext.value.build_unavailable"] = {kind = "text"},
    ["usertext.value.build_unavailable_cell"] = {kind = "text"},
    ["usertext.value.build_unconfirmed"] = {kind = "text"},
    ["usertext.value.build_unconfirmed_cell"] = {kind = "text"},
    ["usertext.value.build_with_state"] = {kind = "template", fields = {"build", "state"}, slots = {"text", "text"}, resultLimit = 1600},
    ["usertext.value.character_not_known"] = {kind = "text"},
    ["usertext.value.compact_build_active"] = {kind = "text"},
    ["usertext.value.compact_build_empty"] = {kind = "text"},
    ["usertext.value.compact_build_inactive"] = {kind = "text"},
    ["usertext.value.compact_build_name_slot"] = {kind = "template", fields = {"slot", "name"}, slots = {"text", "text"}, resultLimit = 1400},
    ["usertext.value.compact_build_not_known"] = {kind = "text"},
    ["usertext.value.compact_build_selected"] = {kind = "text"},
    ["usertext.value.compact_build_slot"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 200},
    ["usertext.value.compact_build_unavailable"] = {kind = "text"},
    ["usertext.value.compact_build_unconfirmed"] = {kind = "text"},
    ["usertext.value.compact_dest_build_none"] = {kind = "text"},
    ["usertext.value.compact_dest_first_run"] = {kind = "text"},
    ["usertext.value.compact_dest_none"] = {kind = "text"},
    ["usertext.value.compact_dest_not_loaded"] = {kind = "text"},
    ["usertext.value.compact_dest_restoring"] = {kind = "text"},
    ["usertext.value.compact_dest_unconfirmed"] = {kind = "text"},
    ["usertext.value.compact_state_captured"] = {kind = "template", fields = {"state"}, slots = {"text"}, resultLimit = 400},
    ["usertext.value.compact_state_captured_first_run"] = {kind = "text"},
    ["usertext.value.compact_state_preview"] = {kind = "template", fields = {"state"}, slots = {"text"}, resultLimit = 600},
    ["usertext.value.compact_wishlist_assigned"] = {kind = "text"},
    ["usertext.value.compact_wishlist_none"] = {kind = "text"},
    ["usertext.value.compact_wishlist_refused"] = {kind = "text"},
    ["usertext.value.compact_wishlist_refused_named"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1400},
    ["usertext.value.compact_wishlist_restoring"] = {kind = "text"},
    ["usertext.value.compact_wishlist_unavailable"] = {kind = "text"},
    ["usertext.value.compact_wishlist_unavailable_named"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1400},
    ["usertext.value.compact_wishlist_unknown_named"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1400},
    ["usertext.value.dest_first_run"] = {kind = "text"},
    ["usertext.value.dest_first_run_cell"] = {kind = "text"},
    ["usertext.value.dest_none"] = {kind = "text"},
    ["usertext.value.dest_none_cell"] = {kind = "text"},
    ["usertext.value.dest_not_loaded"] = {kind = "text"},
    ["usertext.value.dest_not_loaded_cell"] = {kind = "text"},
    ["usertext.value.dest_restoring"] = {kind = "text"},
    ["usertext.value.dest_restoring_cell"] = {kind = "text"},
    ["usertext.value.dest_unconfirmed"] = {kind = "text"},
    ["usertext.value.dest_unconfirmed_cell"] = {kind = "text"},
    ["usertext.value.fight_duration"] = {kind = "template", fields = {"duration"}, slots = {"text"}, resultLimit = 200},
    ["usertext.value.minimum_build_active"] = {kind = "text"},
    ["usertext.value.minimum_build_empty"] = {kind = "text"},
    ["usertext.value.minimum_build_inactive"] = {kind = "text"},
    ["usertext.value.minimum_build_unavailable"] = {kind = "text"},
    ["usertext.value.minimum_dest_first_run"] = {kind = "text"},
    ["usertext.value.minimum_dest_none"] = {kind = "text"},
    ["usertext.value.minimum_dest_restoring"] = {kind = "text"},
    ["usertext.value.minimum_state_captured"] = {kind = "template", fields = {"mark"}, slots = {"text"}, resultLimit = 64},
    ["usertext.value.minimum_state_preview"] = {kind = "template", fields = {"mark"}, slots = {"text"}, resultLimit = 64},
    ["usertext.value.minimum_state_preview_captured"] = {kind = "template", fields = {"mark"}, slots = {"text"}, resultLimit = 64},
    ["usertext.value.record_level"] = {kind = "template", fields = {"level"}, slots = {"text"}, resultLimit = 200},
    ["usertext.value.recorded_date"] = {kind = "template", fields = {"date"}, slots = {"text"}, resultLimit = 200},
    ["usertext.value.selected_build"] = {kind = "text"},
    ["usertext.value.selected_build_cell"] = {kind = "text"},
    ["usertext.value.state_captured"] = {kind = "template", fields = {"state"}, slots = {"text"}, resultLimit = 1400},
    ["usertext.value.state_captured_unchecked"] = {kind = "template", fields = {"state"}, slots = {"text"}, resultLimit = 1400},
    ["usertext.value.state_preview"] = {kind = "template", fields = {"state"}, slots = {"text"}, resultLimit = 1600},
    ["usertext.value.wishlist_assigned"] = {kind = "text"},
    ["usertext.value.wishlist_assigned_cell"] = {kind = "text"},
    ["usertext.value.wishlist_assigned_named"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1400},
    ["usertext.value.wishlist_captured_named"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1500},
    ["usertext.value.wishlist_none_assigned"] = {kind = "text"},
    ["usertext.value.wishlist_none_assigned_cell"] = {kind = "text"},
    ["usertext.value.wishlist_not_known"] = {kind = "text"},
    ["usertext.value.wishlist_refused"] = {kind = "text"},
    ["usertext.value.wishlist_refused_named"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1500},
    ["usertext.value.wishlist_restoring"] = {kind = "text"},
    ["usertext.value.wishlist_restoring_cell"] = {kind = "text"},
    ["usertext.value.wishlist_unavailable"] = {kind = "text"},
    ["usertext.value.wishlist_unavailable_cell"] = {kind = "text"},
    ["usertext.value.wishlist_unavailable_named"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1400},
    ["usertext.value.wishlist_unknown_named"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1400},
    -- v5_source86_supplemental (21)
    ["editor.value.imported_wishlist_default"] = {kind = "text"},
    ["guide.body.target_c_active"] = {kind = "text"},
    ["leaderboard.value.generated_build"] = {kind = "text"},
    ["leaderboard.value.generated_player_loadout"] = {kind = "template", fields = {"player"}, slots = {"text"}, resultLimit = 1100},
    ["settings.title.window"] = {kind = "text"},
    ["support.reason.report_chunk_not_text"] = {kind = "template", fields = {"index"}, slots = {"count"}, resultLimit = 1200},
    ["support.reason.report_chunk_too_large"] = {kind = "template", fields = {"index", "limit"}, slots = {"count", "count"}, resultLimit = 1200},
    ["support.reason.report_meta_not_scalar"] = {kind = "template", fields = {"field"}, slots = {"text"}, resultLimit = 1200},
    ["support.reason.report_metatable"] = {kind = "text"},
    ["support.reason.report_no_chunks"] = {kind = "text"},
    ["support.reason.report_no_content"] = {kind = "text"},
    ["support.reason.report_no_meta"] = {kind = "text"},
    ["support.reason.report_not_table"] = {kind = "text"},
    ["support.reason.report_too_large"] = {kind = "template", fields = {"limit"}, slots = {"count"}, resultLimit = 1200},
    ["support.reason.report_too_many_chunks"] = {kind = "text"},
    ["support.reason.storage_earlier_format"] = {kind = "template", fields = {"format"}, slots = {"text"}, resultLimit = 1200},
    ["support.reason.storage_left_untouched"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1200},
    ["support.reason.storage_newer_format"] = {kind = "template", fields = {"format"}, slots = {"text"}, resultLimit = 1200},
    ["support.reason.storage_no_format"] = {kind = "text"},
    ["support.reason.storage_not_table"] = {kind = "text"},
    ["support.reason.storage_unavailable"] = {kind = "text"},
    -- wishlist (381)
    ["editor.body.role_help_plan_only"] = {kind = "text"},
    ["editor.body.role_help_targets"] = {kind = "text"},
    ["editor.button.assign_menu"] = {kind = "text"},
    ["editor.button.assign_now"] = {kind = "text"},
    ["editor.button.build_library_nav"] = {kind = "text"},
    ["editor.button.cancel"] = {kind = "text"},
    ["editor.button.close"] = {kind = "text"},
    ["editor.button.continue"] = {kind = "text"},
    ["editor.button.discard_draft"] = {kind = "text"},
    ["editor.button.display_settings"] = {kind = "text"},
    ["editor.button.editing"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1054},
    ["editor.button.export"] = {kind = "text"},
    ["editor.button.help"] = {kind = "text"},
    ["editor.button.import"] = {kind = "text"},
    ["editor.button.keep_draft"] = {kind = "text"},
    ["editor.button.leaderboard_nav"] = {kind = "text"},
    ["editor.button.manage"] = {kind = "text"},
    ["editor.button.my_builds_game"] = {kind = "text"},
    ["editor.button.new_wishlist"] = {kind = "text"},
    ["editor.button.new_wishlist_choose"] = {kind = "text"},
    ["editor.button.next"] = {kind = "text"},
    ["editor.button.open_imported_draft"] = {kind = "text"},
    ["editor.button.open_new_draft"] = {kind = "text"},
    ["editor.button.plan_alternatives"] = {kind = "text"},
    ["editor.button.previous"] = {kind = "text"},
    ["editor.button.reference"] = {kind = "text"},
    ["editor.button.remove"] = {kind = "text"},
    ["editor.button.role_suggest"] = {kind = "text"},
    ["editor.button.saved"] = {kind = "text"},
    ["editor.button.saved_build_active"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1080},
    ["editor.button.saved_build_choose"] = {kind = "text"},
    ["editor.button.saved_build_inactive"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1088},
    ["editor.button.saved_build_named"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1062},
    ["editor.button.saved_build_none"] = {kind = "text"},
    ["editor.button.saving"] = {kind = "text"},
    ["editor.button.wishlist_choose"] = {kind = "text"},
    ["editor.button.wishlists_nav"] = {kind = "text"},
    ["editor.chat.assign_consent_unavailable"] = {kind = "text"},
    ["editor.chat.assign_now_elsewhere"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 1324},
    ["editor.chat.assign_now_elsewhere_first_run"] = {kind = "text"},
    ["editor.chat.assign_now_empty_target"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 1222},
    ["editor.chat.assign_now_no_route"] = {kind = "text"},
    ["editor.chat.assign_now_not_loaded"] = {kind = "text"},
    ["editor.chat.assign_now_not_opened"] = {kind = "text"},
    ["editor.chat.assign_now_open_yourself"] = {kind = "text"},
    ["editor.chat.assign_now_reopen_continue"] = {kind = "text"},
    ["editor.chat.assign_now_reopen_work"] = {kind = "text"},
    ["editor.chat.assign_now_selector_unavailable"] = {kind = "text"},
    ["editor.chat.assign_now_stale"] = {kind = "text"},
    ["editor.chat.assign_now_try_again"] = {kind = "text"},
    ["editor.chat.assign_saved_build_changed"] = {kind = "text"},
    ["editor.chat.build_library_unavailable"] = {kind = "text"},
    ["editor.chat.candidate_activate_loadout"] = {kind = "text"},
    ["editor.chat.candidate_assigned"] = {kind = "template", fields = {"name", "slot"}, slots = {"text", "text"}, resultLimit = 2048},
    ["editor.chat.candidate_first_run"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1112},
    ["editor.chat.export_name_undisplayable"] = {kind = "text"},
    ["editor.chat.forget_failed_default"] = {kind = "text"},
    ["editor.chat.import_codec_unavailable"] = {kind = "text"},
    ["editor.chat.import_failed"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1110},
    ["editor.chat.import_name_required"] = {kind = "text"},
    ["editor.chat.import_parse_failed"] = {kind = "text"},
    ["editor.chat.import_pipe_dropped"] = {kind = "template", fields = {"character", "name"}, slots = {"text", "text"}, resultLimit = 2048},
    ["editor.chat.imported_draft_many"] = {kind = "template", fields = {"count", "name"}, slots = {"count", "text"}, resultLimit = 2048, lines = true},
    ["editor.chat.imported_draft_one"] = {kind = "template", fields = {"count", "name"}, slots = {"count", "text"}, resultLimit = 2048, lines = true},
    ["editor.chat.manage_restored_moved"] = {kind = "template", fields = {"name", "slot", "from"}, slots = {"text", "text", "text"}, resultLimit = 2048},
    ["editor.chat.nothing_assigned"] = {kind = "text"},
    ["editor.chat.plan_draft_suspended"] = {kind = "text"},
    ["editor.chat.role_confirmed_for"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1174},
    ["editor.chat.role_contents_invalid"] = {kind = "text"},
    ["editor.chat.role_quality_mismatch"] = {kind = "text"},
    ["editor.chat.role_using_current_for"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1192},
    ["editor.error.export_codec_unavailable"] = {kind = "text"},
    ["editor.error.export_envelope"] = {kind = "text"},
    ["editor.error.export_no_echoes"] = {kind = "text"},
    ["editor.error.export_unavailable"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1082},
    ["editor.error.export_unavailable_default"] = {kind = "text"},
    ["editor.error.import_roles_unrepresentable"] = {kind = "text"},
    ["editor.heading.manage_count"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["editor.heading.selected"] = {kind = "text"},
    ["editor.label.autolock_full"] = {kind = "text"},
    ["editor.label.autolock_short"] = {kind = "text"},
    ["editor.label.catalog_footer_names"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["editor.label.catalog_footer_range"] = {kind = "template", fields = {"first", "last", "total"}, slots = {"count", "count", "count"}, resultLimit = 256},
    ["editor.label.class_only"] = {kind = "text"},
    ["editor.label.list_header"] = {kind = "text"},
    ["editor.label.locked_count"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["editor.label.locked_count_max"] = {kind = "template", fields = {"count", "max"}, slots = {"count", "count"}, resultLimit = 256},
    ["editor.label.locked_initial"] = {kind = "text"},
    ["editor.label.pick_entries"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["editor.label.pick_locked"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["editor.label.pick_locked_max"] = {kind = "template", fields = {"count", "max"}, slots = {"count", "count"}, resultLimit = 256},
    ["editor.label.pick_planned"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["editor.label.pick_targets"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["editor.label.role_locked_targets"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["editor.label.role_page"] = {kind = "template", fields = {"page", "pages"}, slots = {"count", "count"}, resultLimit = 256},
    ["editor.label.role_rolled_copies"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["editor.label.role_row"] = {kind = "template", fields = {"name", "quality", "copies"}, slots = {"text", "text", "count"}, resultLimit = 2048},
    ["editor.label.role_row_locked"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["editor.label.role_total"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["editor.label.wishlist_name"] = {kind = "text"},
    ["editor.menu.loadout_empty"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 1074},
    ["editor.menu.loadout_no_wishlist"] = {kind = "text"},
    ["editor.menu.loadout_none"] = {kind = "text"},
    ["editor.menu.manage_empty"] = {kind = "text"},
    ["editor.menu.manage_more"] = {kind = "template", fields = {"first", "last", "total"}, slots = {"count", "count", "count"}, resultLimit = 256},
    ["editor.menu.manage_remove"] = {kind = "text"},
    ["editor.menu.manage_row_not_saved_build"] = {kind = "template", fields = {"index"}, slots = {"text"}, resultLimit = 1078},
    ["editor.menu.manage_row_rows"] = {kind = "template", fields = {"rows"}, slots = {"count"}, resultLimit = 256},
    ["editor.menu.manage_row_saved_build"] = {kind = "template", fields = {"slot", "rows"}, slots = {"text", "count"}, resultLimit = 1120},
    ["editor.menu.manage_undo"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1074},
    ["editor.menu.manage_undo_from"] = {kind = "template", fields = {"index"}, slots = {"text"}, resultLimit = 1064},
    ["editor.menu.pager_next"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["editor.menu.switch_empty"] = {kind = "text"},
    ["editor.menu.switch_index_not_saved_build"] = {kind = "template", fields = {"index"}, slots = {"text"}, resultLimit = 1096},
    ["editor.menu.switch_more"] = {kind = "template", fields = {"first", "last", "total"}, slots = {"count", "count", "count"}, resultLimit = 256},
    ["editor.menu.switch_saved_build"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1062},
    ["editor.menu.switch_saved_build_none"] = {kind = "text"},
    ["editor.note.manage_no_deletion_call"] = {kind = "text"},
    ["editor.note.manage_removals_local"] = {kind = "text"},
    ["editor.note.manage_removals_reason"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1090},
    ["editor.placeholder.search"] = {kind = "text"},
    ["editor.popup.assign_later"] = {kind = "text"},
    ["editor.popup.auto_replace"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 2048, lines = true},
    ["editor.popup.auto_replace_paused"] = {kind = "template", fields = {"reason", "label"}, slots = {"text", "text"}, resultLimit = 2048, lines = true},
    ["editor.popup.auto_save_off"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 1256},
    ["editor.popup.auto_turn_off"] = {kind = "text"},
    ["editor.popup.confirm_assign_afterwards"] = {kind = "text"},
    ["editor.popup.confirm_assigned_after"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 1242},
    ["editor.popup.confirm_becomes_first_run"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 1206},
    ["editor.popup.confirm_existing_keep_names"] = {kind = "text"},
    ["editor.popup.confirm_keeps"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 1240},
    ["editor.popup.confirm_name_taken"] = {kind = "template", fields = {"requested", "name"}, slots = {"text", "text"}, resultLimit = 2048},
    ["editor.popup.confirm_names_unknown"] = {kind = "text"},
    ["editor.popup.confirm_no_capture"] = {kind = "text"},
    ["editor.popup.confirm_no_destination_update"] = {kind = "text"},
    ["editor.popup.confirm_not_loaded"] = {kind = "text"},
    ["editor.popup.confirm_not_overwritten"] = {kind = "text"},
    ["editor.popup.confirm_nothing_activated"] = {kind = "text"},
    ["editor.popup.confirm_nothing_spent"] = {kind = "text"},
    ["editor.popup.confirm_planned"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["editor.popup.confirm_save_only_first_run"] = {kind = "text"},
    ["editor.popup.confirm_save_only_saved_build"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 1206},
    ["editor.popup.confirm_updates"] = {kind = "text"},
    ["editor.popup.confirm_updates_assignment"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 1188},
    ["editor.popup.confirm_updates_first_run"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 1178},
    ["editor.popup.context_changed"] = {kind = "block"},
    ["editor.popup.create_question"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1056},
    ["editor.popup.export_copy_hint"] = {kind = "text"},
    ["editor.popup.export_intro"] = {kind = "text"},
    ["editor.popup.export_intro_note"] = {kind = "template", fields = {"note"}, slots = {"text"}, resultLimit = 1120},
    ["editor.popup.flex_replace_consequence"] = {kind = "block"},
    ["editor.popup.flex_replace_question"] = {kind = "text"},
    ["editor.popup.forget_facts"] = {kind = "template", fields = {"rows", "ordinary", "locked", "association"}, slots = {"count", "count", "count", "text"}, resultLimit = 1256},
    ["editor.popup.forget_only_copy"] = {kind = "text"},
    ["editor.popup.forget_question"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1096},
    ["editor.popup.forget_server_kept"] = {kind = "text"},
    ["editor.popup.forget_slot_changed"] = {kind = "text"},
    ["editor.popup.forget_undo_hint"] = {kind = "text"},
    ["editor.popup.import_new_draft_note"] = {kind = "text"},
    ["editor.popup.import_prompt"] = {kind = "text"},
    ["editor.popup.name_import_prompt"] = {kind = "text"},
    ["editor.popup.save_changes_question"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1074},
    ["editor.status.candidates_click_assign"] = {kind = "text"},
    ["editor.status.candidates_found"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["editor.status.candidates_need_targets"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["editor.status.found_identity"] = {kind = "text"},
    ["editor.status.found_identity_choose"] = {kind = "text"},
    ["editor.status.found_wishlist"] = {kind = "text"},
    ["editor.status.found_wishlist_assign"] = {kind = "text"},
    ["editor.status.hint_choose_locked_targets"] = {kind = "text"},
    ["editor.status.hint_use_current_locks"] = {kind = "text"},
    ["editor.status.no_wishlist_build_one"] = {kind = "text"},
    ["editor.status.no_wishlist_yet"] = {kind = "text"},
    ["editor.status.reason_adapter"] = {kind = "text"},
    ["editor.status.reason_assignment_changed"] = {kind = "template", fields = {"where"}, slots = {"text"}, resultLimit = 1272},
    ["editor.status.reason_design_limit"] = {kind = "text"},
    ["editor.status.reason_destination_changed"] = {kind = "text"},
    ["editor.status.reason_destination_empty"] = {kind = "template", fields = {"where"}, slots = {"text"}, resultLimit = 1150},
    ["editor.status.reason_empty"] = {kind = "text"},
    ["editor.status.reason_error"] = {kind = "text"},
    ["editor.status.reason_expired"] = {kind = "text"},
    ["editor.status.reason_invalid_intent"] = {kind = "text"},
    ["editor.status.reason_invalid_locked_design"] = {kind = "text"},
    ["editor.status.reason_mirror_unresolved"] = {kind = "text"},
    ["editor.status.reason_name"] = {kind = "text"},
    ["editor.status.reason_name_taken"] = {kind = "text"},
    ["editor.status.reason_name_unavailable"] = {kind = "text"},
    ["editor.status.reason_no_destination"] = {kind = "text"},
    ["editor.status.reason_no_echoes"] = {kind = "text"},
    ["editor.status.reason_no_valid_echoes"] = {kind = "text"},
    ["editor.status.reason_not_completed"] = {kind = "text"},
    ["editor.status.reason_partial_draft_changed"] = {kind = "text"},
    ["editor.status.reason_partial_empty"] = {kind = "template", fields = {"where"}, slots = {"text"}, resultLimit = 1084},
    ["editor.status.reason_partial_error"] = {kind = "text"},
    ["editor.status.reason_partial_local_targets"] = {kind = "text"},
    ["editor.status.reason_partial_not_recorded"] = {kind = "text"},
    ["editor.status.reason_partial_not_stored"] = {kind = "text"},
    ["editor.status.reason_partial_outside"] = {kind = "template", fields = {"where"}, slots = {"text"}, resultLimit = 1134},
    ["editor.status.reason_partial_refused"] = {kind = "text"},
    ["editor.status.reason_partial_slot_unknown"] = {kind = "text"},
    ["editor.status.reason_refused"] = {kind = "text"},
    ["editor.status.reason_retry_draft_changed"] = {kind = "text"},
    ["editor.status.reason_stale_candidate"] = {kind = "text"},
    ["editor.status.reason_stale_confirmation"] = {kind = "text"},
    ["editor.status.reason_stale_payload"] = {kind = "text"},
    ["editor.status.reason_stale_slot"] = {kind = "text"},
    ["editor.status.result_assigned"] = {kind = "template", fields = {"plan", "label"}, slots = {"text", "text"}, resultLimit = 2048},
    ["editor.status.result_assigned_session"] = {kind = "template", fields = {"plan", "label"}, slots = {"text", "text"}, resultLimit = 2048},
    ["editor.status.result_first_run"] = {kind = "template", fields = {"plan", "character"}, slots = {"text", "text"}, resultLimit = 2048},
    ["editor.status.result_first_run_session"] = {kind = "template", fields = {"plan", "character"}, slots = {"text", "text"}, resultLimit = 2048},
    ["editor.status.result_kept"] = {kind = "template", fields = {"plan", "label"}, slots = {"text", "text"}, resultLimit = 2048},
    ["editor.status.result_not_confirmed"] = {kind = "text"},
    ["editor.status.result_not_saved"] = {kind = "text"},
    ["editor.status.result_save_only"] = {kind = "template", fields = {"plan"}, slots = {"text"}, resultLimit = 1122},
    ["editor.status.result_saved"] = {kind = "text"},
    ["editor.status.result_saved_not_assigned"] = {kind = "text"},
    ["editor.status.result_send_error"] = {kind = "template", fields = {"plan"}, slots = {"text"}, resultLimit = 1126},
    ["editor.status.result_uploaded_not_assigned"] = {kind = "text"},
    ["editor.status.result_why_no_capture"] = {kind = "text"},
    ["editor.status.result_why_not_loaded"] = {kind = "text"},
    ["editor.status.result_why_unbound"] = {kind = "text"},
    ["editor.status.result_with_reason"] = {kind = "template", fields = {"plan", "reason"}, slots = {"text", "text"}, resultLimit = 2048},
    ["editor.status.role_assign_incomplete"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1132},
    ["editor.status.role_default"] = {kind = "text"},
    ["editor.status.role_loadout_changed"] = {kind = "text"},
    ["editor.status.role_loadout_unavailable"] = {kind = "text"},
    ["editor.status.role_locked_list_incomplete"] = {kind = "text"},
    ["editor.status.role_locked_over_six"] = {kind = "text"},
    ["editor.status.role_matching_over_six"] = {kind = "text"},
    ["editor.status.role_not_preserved"] = {kind = "text"},
    ["editor.status.role_not_representable"] = {kind = "text"},
    ["editor.status.role_select_limit"] = {kind = "text"},
    ["editor.status.role_suggested"] = {kind = "text"},
    ["editor.status.role_using_current"] = {kind = "text"},
    ["editor.status.role_waiting_locked_list"] = {kind = "text"},
    ["editor.status.tracking_detail"] = {kind = "template", fields = {"name", "source", "count"}, slots = {"text", "text", "count"}, resultLimit = 2048},
    ["editor.status.tracking_label"] = {kind = "text"},
    ["editor.title.create"] = {kind = "text"},
    ["editor.title.edit"] = {kind = "text"},
    ["editor.title.editor"] = {kind = "text"},
    ["editor.title.role_picker"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1092},
    ["editor.tooltip.apply_confirmation"] = {kind = "text"},
    ["editor.tooltip.apply_edits_only"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1060},
    ["editor.tooltip.apply_heading_create"] = {kind = "text"},
    ["editor.tooltip.apply_heading_save"] = {kind = "text"},
    ["editor.tooltip.apply_unavailable"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1066},
    ["editor.tooltip.apply_uploads_new"] = {kind = "text"},
    ["editor.tooltip.assign_body"] = {kind = "text"},
    ["editor.tooltip.assign_heading"] = {kind = "text"},
    ["editor.tooltip.assign_later"] = {kind = "text"},
    ["editor.tooltip.assign_now_chooser"] = {kind = "text"},
    ["editor.tooltip.assign_now_heading"] = {kind = "text"},
    ["editor.tooltip.assign_now_route"] = {kind = "text"},
    ["editor.tooltip.assign_now_safe"] = {kind = "text"},
    ["editor.tooltip.autolock_body"] = {kind = "text"},
    ["editor.tooltip.autolock_heading"] = {kind = "text"},
    ["editor.tooltip.autolock_manual"] = {kind = "text"},
    ["editor.tooltip.confirmation_first"] = {kind = "text"},
    ["editor.tooltip.create_unassigned_body"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 1298},
    ["editor.tooltip.create_unassigned_heading"] = {kind = "text"},
    ["editor.tooltip.display_body_end"] = {kind = "text"},
    ["editor.tooltip.display_body_start"] = {kind = "text"},
    ["editor.tooltip.display_heading"] = {kind = "text"},
    ["editor.tooltip.intent_create_another"] = {kind = "text"},
    ["editor.tooltip.intent_create_assign"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 1242},
    ["editor.tooltip.intent_create_unassigned"] = {kind = "text"},
    ["editor.tooltip.intent_possibly_sent"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1172},
    ["editor.tooltip.intent_save_assign_opened"] = {kind = "template", fields = {"where"}, slots = {"text"}, resultLimit = 1246},
    ["editor.tooltip.intent_save_changes_beside"] = {kind = "text"},
    ["editor.tooltip.intent_save_changes_keeps"] = {kind = "template", fields = {"where"}, slots = {"text"}, resultLimit = 1154},
    ["editor.tooltip.intent_sent"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1154},
    ["editor.tooltip.locked_need_icon"] = {kind = "text"},
    ["editor.tooltip.locked_slot_automatic"] = {kind = "text"},
    ["editor.tooltip.locked_slot_cancel"] = {kind = "text"},
    ["editor.tooltip.locked_slot_empty"] = {kind = "text"},
    ["editor.tooltip.locked_slot_empty_click"] = {kind = "text"},
    ["editor.tooltip.locked_slot_find"] = {kind = "text"},
    ["editor.tooltip.locked_slot_planned"] = {kind = "text"},
    ["editor.tooltip.locked_slot_replace"] = {kind = "text"},
    ["editor.tooltip.locked_slot_replacing"] = {kind = "text"},
    ["editor.tooltip.manage_body"] = {kind = "text"},
    ["editor.tooltip.manage_heading"] = {kind = "text"},
    ["editor.tooltip.my_builds_body"] = {kind = "text"},
    ["editor.tooltip.my_builds_heading"] = {kind = "text"},
    ["editor.tooltip.result_assigned_nothing"] = {kind = "text"},
    ["editor.tooltip.result_assignment_refused"] = {kind = "text"},
    ["editor.tooltip.result_check_journal"] = {kind = "text"},
    ["editor.tooltip.result_create_another_anyway"] = {kind = "text"},
    ["editor.tooltip.result_details"] = {kind = "template", fields = {"code"}, slots = {"text"}, resultLimit = 1054},
    ["editor.tooltip.result_draft_kept"] = {kind = "text"},
    ["editor.tooltip.result_editor_changed"] = {kind = "text"},
    ["editor.tooltip.result_journal"] = {kind = "text"},
    ["editor.tooltip.result_later_step_failed"] = {kind = "text"},
    ["editor.tooltip.result_may_have_reached"] = {kind = "text"},
    ["editor.tooltip.result_newer_choice_kept"] = {kind = "text"},
    ["editor.tooltip.result_no_saved_build_changed"] = {kind = "text"},
    ["editor.tooltip.result_no_target_changed"] = {kind = "text"},
    ["editor.tooltip.result_not_sent_again"] = {kind = "text"},
    ["editor.tooltip.result_not_uploaded_again"] = {kind = "text"},
    ["editor.tooltip.result_nothing_activated"] = {kind = "text"},
    ["editor.tooltip.result_nothing_saved"] = {kind = "text"},
    ["editor.tooltip.result_nothing_uploaded_again"] = {kind = "text"},
    ["editor.tooltip.result_nothing_uploaded_from_draft"] = {kind = "text"},
    ["editor.tooltip.result_now_uses"] = {kind = "template", fields = {"label"}, slots = {"text"}, resultLimit = 1100},
    ["editor.tooltip.result_plan_saved"] = {kind = "text"},
    ["editor.tooltip.result_planned"] = {kind = "template", fields = {"count"}, slots = {"count"}, resultLimit = 256},
    ["editor.tooltip.result_press_create_again"] = {kind = "text"},
    ["editor.tooltip.result_review_save_again"] = {kind = "text"},
    ["editor.tooltip.result_save_again_later"] = {kind = "text"},
    ["editor.tooltip.result_session_only"] = {kind = "template", fields = {"reason"}, slots = {"text"}, resultLimit = 1362},
    ["editor.tooltip.result_store_targets"] = {kind = "template", fields = {"plan"}, slots = {"text"}, resultLimit = 1282},
    ["editor.tooltip.result_targets_not_saved"] = {kind = "text"},
    ["editor.tooltip.result_used_until"] = {kind = "text"},
    ["editor.tooltip.save_assign_them"] = {kind = "template", fields = {"where"}, slots = {"text"}, resultLimit = 1148},
    ["editor.tooltip.save_changes_body"] = {kind = "template", fields = {"where"}, slots = {"text"}, resultLimit = 1298},
    ["editor.tooltip.save_changes_heading"] = {kind = "text"},
    ["editor.tooltip.saved_build_body"] = {kind = "text"},
    ["editor.tooltip.saved_build_heading"] = {kind = "text"},
    ["editor.tooltip.step_minus_body"] = {kind = "text"},
    ["editor.tooltip.step_minus_heading"] = {kind = "text"},
    ["editor.tooltip.step_nothing_saved"] = {kind = "text"},
    ["editor.tooltip.step_plus_body"] = {kind = "text"},
    ["editor.tooltip.step_plus_heading"] = {kind = "text"},
    ["editor.tooltip.step_remove_body"] = {kind = "text"},
    ["editor.tooltip.step_remove_heading"] = {kind = "text"},
    ["editor.tooltip.switch_body"] = {kind = "text"},
    ["editor.tooltip.switch_editing"] = {kind = "text"},
    ["editor.tooltip.switch_heading"] = {kind = "text"},
    ["editor.value.a_saved_build"] = {kind = "text"},
    ["editor.value.association_not_saved_build"] = {kind = "template", fields = {"index"}, slots = {"text"}, resultLimit = 1116},
    ["editor.value.captured_destination_fallback"] = {kind = "text"},
    ["editor.value.catalog_locked"] = {kind = "text"},
    ["editor.value.catalog_quality_owned"] = {kind = "template", fields = {"quality"}, slots = {"text"}, resultLimit = 1060},
    ["editor.value.catalog_selected"] = {kind = "text"},
    ["editor.value.catalog_selected_marker"] = {kind = "text"},
    ["editor.value.echo_id_fallback"] = {kind = "template", fields = {"id"}, slots = {"text"}, resultLimit = 1042},
    ["editor.value.first_run_target_for"] = {kind = "template", fields = {"character"}, slots = {"text"}, resultLimit = 1096},
    ["editor.value.its_destination"] = {kind = "text"},
    ["editor.value.its_saved_build"] = {kind = "text"},
    ["editor.value.opened_saved_build_fallback"] = {kind = "text"},
    ["editor.value.pick_currently_locked"] = {kind = "text"},
    ["editor.value.pick_locked_slot"] = {kind = "text"},
    ["editor.value.pick_replaces"] = {kind = "text"},
    ["editor.value.quality_common"] = {kind = "text"},
    ["editor.value.quality_epic"] = {kind = "text"},
    ["editor.value.quality_fallback"] = {kind = "text"},
    ["editor.value.quality_legendary"] = {kind = "text"},
    ["editor.value.quality_rare"] = {kind = "text"},
    ["editor.value.quality_uncommon"] = {kind = "text"},
    ["editor.value.reason_unavailable"] = {kind = "text"},
    ["editor.value.removed_wishlist_fallback"] = {kind = "text"},
    ["editor.value.saved_build_named_slot"] = {kind = "template", fields = {"name", "slot"}, slots = {"text", "text"}, resultLimit = 2048},
    ["editor.value.saved_build_number"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 1060},
    ["editor.value.saved_build_quoted"] = {kind = "template", fields = {"name"}, slots = {"text"}, resultLimit = 1064},
    ["editor.value.slot_fallback"] = {kind = "template", fields = {"slot"}, slots = {"text"}, resultLimit = 1046},
    ["editor.value.spell_id_fallback"] = {kind = "template", fields = {"id"}, slots = {"text"}, resultLimit = 1044},
    ["editor.value.the_one"] = {kind = "text"},
    ["editor.value.the_saved_build"] = {kind = "text"},
    ["editor.value.this_character"] = {kind = "text"},
    ["editor.value.unknown_reason"] = {kind = "text"},
    ["editor.value.unknown_source"] = {kind = "text"},
    ["editor.value.unnamed"] = {kind = "text"},
    ["editor.value.wishlist_fallback"] = {kind = "text"},
    ["editor.value.wishlist_index_fallback"] = {kind = "template", fields = {"index"}, slots = {"text"}, resultLimit = 1056},
    ["overlay.body.lock_hint"] = {kind = "text"},
    ["overlay.body.settings_subtitle"] = {kind = "text"},
    ["overlay.button.lock_position"] = {kind = "text"},
    ["overlay.button.lock_position_settings"] = {kind = "text"},
    ["overlay.button.reset_position"] = {kind = "text"},
    ["overlay.button.unlock_position"] = {kind = "text"},
    ["overlay.button.unlock_to_move"] = {kind = "text"},
    ["overlay.label.position"] = {kind = "text"},
    ["overlay.label.show_overlay"] = {kind = "text"},
    ["overlay.label.size"] = {kind = "text"},
    ["overlay.status.no_wishlist"] = {kind = "text"},
    ["overlay.status.planned_unavailable"] = {kind = "text"},
    ["overlay.title.settings"] = {kind = "text"},
    ["overlay.tooltip.hide"] = {kind = "text"},
    ["overlay.tooltip.show_again"] = {kind = "template", fields = {"command"}, slots = {"text"}, resultLimit = 1076},
    ["overlay.value.locked_target"] = {kind = "text"},
    ["wishlist.status.export_locked_excess"] = {kind = "template", fields = {"held", "max"}, slots = {"count", "count"}, resultLimit = 312},
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

-- Display phrasebook (full visible-UI remainder). A producer that keeps its
-- raw English (it is compared, recorded, queued or sent) is shown through a
-- code-owned book at the display boundary: an exact producer text, or the
-- producer's own string.format pattern ("%d" and "%s" conversions only, "%%"
-- a literal percent), names a reviewed key. L.PhraseBook(spec) compiles
--   spec = {exact = {[raw] = key, ...},
--           formats = {{format = fmt, key = key, fields = {name, ...}}, ...}}
-- into a book; a format entry is kept only when its conversions are all %d
-- or %s and their number equals #fields (a %d field is a count slot, a %s
-- field a text slot, in that order). An entry may add nested = {field =
-- {[exact value] = key}}: that text field's captured value, when it is
-- exactly one of those code-owned values, is shown through its key; any
-- other value (player data) stays verbatim. nested = {field = true} shows
-- the value through the same book instead (an inner reason the same owner
-- produced). spec.segments = true makes the exact texts also segment units:
-- a raw text that consists only of exact texts, one directly after another
-- or separated by one ASCII space, is shown unit by unit (each through its
-- key, the spaces kept); any byte no unit covers leaves the text raw. At
-- most MAX_PHRASE_ENTRIES entries.
-- L.Phrase(raw, book) -> shown, matched: the exact entry, else the first
-- format whose anchored pattern matches, rendered with L.Text / L.Format.
-- A %d capture is used only when it is a whole number >= 0 that tostring
-- gives back byte for byte, so English output never changes; otherwise, or
-- when no entry matches or the key is unavailable, the raw text is returned
-- unchanged (matched = false). Pure display: it reads only its arguments and
-- the seam, keeps nothing and never raises. The patterns are code-owned
-- (made from producer English); a translation is only a template.
local MAX_PHRASE_ENTRIES = 1024
L.MAX_PHRASE_ENTRIES = MAX_PHRASE_ENTRIES

local function CompileFormat(format, fieldCount)
    if type(format) ~= "string" or #format == 0 then return nil end
    -- segments: the format as literal strings and slots, for ParseCount.
    local parts, slots, segments, literal, index, length = {"^"}, {}, {}, {}, 1, #format
    local function Flush()
        if #literal > 0 then segments[#segments + 1] = {literal = table.concat(literal)}; literal = {} end
    end
    while index <= length do
        local c = format:sub(index, index)
        if c == "%" then
            local n = format:sub(index + 1, index + 1)
            if n == "%" then
                parts[#parts + 1] = "%%"; literal[#literal + 1] = "%"
            elseif n == "d" then
                parts[#parts + 1] = "(%d+)"; slots[#slots + 1] = "count"
                Flush(); segments[#segments + 1] = {slot = "count"}
            elseif n == "s" then
                parts[#parts + 1] = "(.-)"; slots[#slots + 1] = "text"
                Flush(); segments[#segments + 1] = {slot = "text"}
            else
                return nil
            end
            index = index + 2
        else
            parts[#parts + 1] = c:find("^[%^%$%(%)%%%.%[%]%*%+%-%?]$") and ("%" .. c) or c
            literal[#literal + 1] = c
            index = index + 1
        end
    end
    Flush()
    if #slots == 0 or #slots ~= fieldCount then return nil end
    parts[#parts + 1] = "$"
    return table.concat(parts), slots, segments
end

-- How many ways raw splits into a format's literals and slots: 0, 1, or 2
-- for "more than one" (a count slot is one or more digits, a text slot any
-- bytes, as the compiled pattern allows). A text value that holds the
-- format's own delimiters makes the split ambiguous: which bytes belong to
-- which field is then unknown, and the text is not recaptured.
local function ParseCount(raw, segments)
    local length, memo = #raw, {}
    local function From(position, index)
        if index > #segments then return position == length + 1 and 1 or 0 end
        local id = position * 256 + index
        if memo[id] then return memo[id] end
        local segment, total = segments[index], 0
        if segment.literal then
            if raw:sub(position, position + #segment.literal - 1) == segment.literal then
                total = From(position + #segment.literal, index + 1)
            end
        elseif segment.slot == "count" then
            local stop = position
            while stop <= length and raw:byte(stop) >= 48 and raw:byte(stop) <= 57 do
                stop = stop + 1
                total = total + From(stop, index + 1)
                if total > 1 then break end
            end
        else
            local nextSegment = segments[index + 1]
            if nextSegment and nextSegment.literal then
                local from = position
                while true do
                    local at = raw:find(nextSegment.literal, from, true)
                    if not at then break end
                    total = total + From(at, index + 1)
                    if total > 1 then break end
                    from = at + 1
                end
            else
                for stop = position, length + 1 do
                    total = total + From(stop, index + 1)
                    if total > 1 then break end
                end
            end
        end
        if total > 1 then total = 2 end
        memo[id] = total
        return total
    end
    return From(1, 1)
end

function L.PhraseBook(spec)
    local book = {exact = {}, formats = {}, size = 0}
    if type(spec) ~= "table" then return book end
    book.segments = spec.segments == true
    if type(spec.exact) == "table" then
        for raw, key in pairs(spec.exact) do
            if book.size < MAX_PHRASE_ENTRIES and type(raw) == "string" and ValidKey(key) then
                book.exact[raw] = key
                book.size = book.size + 1
            end
        end
    end
    if type(spec.formats) == "table" then
        for _, entry in ipairs(spec.formats) do
            local fields = type(entry) == "table" and entry.fields
            if book.size < MAX_PHRASE_ENTRIES and type(fields) == "table" and ValidKey(entry.key) then
                local pattern, slots, segments = CompileFormat(entry.format, #fields)
                if pattern then
                    book.formats[#book.formats + 1] = {pattern = pattern, key = entry.key,
                        fields = fields, slots = slots, format = entry.format, segments = segments,
                        nested = type(entry.nested) == "table" and entry.nested or nil}
                    book.size = book.size + 1
                end
            end
        end
    end
    return book
end

function L.Phrase(raw, book)
    if type(raw) ~= "string" or type(book) ~= "table" then return raw, false end
    local key = type(book.exact) == "table" and book.exact[raw] or nil
    if key then
        local text, source = L.Text(key)
        if source ~= "unavailable" then return text, true end
        return raw, false
    end
    for _, entry in ipairs(type(book.formats) == "table" and book.formats or {}) do
        local captures = {raw:match(entry.pattern)}
        if captures[1] ~= nil then
            -- Two or more slots: recaptured only when the split is unique.
            local args, usable = {}, #entry.slots < 2 or ParseCount(raw, entry.segments) == 1
            for i, name in ipairs(usable and entry.fields or {}) do
                local value = captures[i]
                if entry.slots[i] == "count" then
                    local n = tonumber(value)
                    if not n or n < 0 or n ~= math.floor(n) or tostring(n) ~= value then
                        usable = false
                        break
                    end
                    args[name] = {known = true, value = n}
                else
                    local map = entry.nested and entry.nested[name]
                    local nestedKey = type(map) == "table" and map[value] or nil
                    if nestedKey and ValidKey(nestedKey) then
                        local shown, source = L.Text(nestedKey)
                        if source ~= "unavailable" then value = shown end
                    elseif map == true and value ~= raw then
                        value = (L.Phrase(value, book))
                    end
                    args[name] = value
                end
            end
            if usable then
                local text, source = L.Format(entry.key, args)
                if source ~= "unavailable" then return text, true end
            end
            return raw, false
        end
    end
    if book.segments == true then
        local units = book.units
        if not units then
            -- Exact texts by their first byte, longest first.
            units = {}
            for text in pairs(book.exact) do
                local first = text:sub(1, 1)
                units[first] = units[first] or {}
                table.insert(units[first], text)
            end
            for _, list in pairs(units) do
                table.sort(list, function(a, c) return #a > #c end)
            end
            book.units = units
        end
        local length, failed = #raw, {}
        local function Parse(index)
            if index > length then return {} end
            if failed[index] then return nil end
            local starts = {index}
            if index > 1 and raw:sub(index, index) == " " then starts[2] = index + 1 end
            for s = 1, #starts do
                local at = starts[s]
                for _, unit in ipairs(units[raw:sub(at, at)] or {}) do
                    if raw:sub(at, at + #unit - 1) == unit then
                        local rest = Parse(at + #unit)
                        if rest then
                            local shown, source = L.Text(book.exact[unit])
                            if source == "unavailable" then return nil end
                            table.insert(rest, 1, (at > index and " " or "") .. shown)
                            return rest
                        end
                    end
                end
            end
            failed[index] = true
            return nil
        end
        local parts = length > 0 and Parse(1) or nil
        if parts and #parts > 1 then return table.concat(parts), true end
    end
    return raw, false
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
