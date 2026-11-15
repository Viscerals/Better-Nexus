-- Nexus: ui/JournalTab.lua
-- A "Nexus Progress" tab (formerly "Nexus Advisor") inside ProjectEbonhold's
-- Echo Journal: a read-only Build Progress summary first, then the sections
-- supplied by an injected dataProvider callback behind Show details: plain
-- text, or icon rows where a section supplies structured tomeRows.
-- Structures relied on (captured live against this exact client):
--   frame  ProjectEbonholdEchoJournal
--   tabs   ProjectEbonholdEchoJournalTab1..N (CharacterFrameTabButton
--          textures), parent = the journal frame
--   scroll ProjectEbonholdEchoJournalScroll = content area
-- The journal UI is built LAZILY on first open: a login-time install
-- succeeds only after /reload with the journal already built, so
-- "frames not present" is the NORMAL, SILENT state until the hooked
-- EchoJournal.Show/Toggle fires and the install retries. Our tab index
-- is existing-tab-count + 1 (a leftover EchoOptimizer Tab4 shifts us
-- to 5 instead of colliding).
-- SOFT-FAIL CONTRACT: TryInstall pcall-wraps everything and returns
-- false on any failure -- no tab, no error, retried on next Show.
-- All DATA arrives through the provider; this file touches journal
-- FRAMES only (documented presentation-layer exception), never
-- PerkService.

Nexus = Nexus or {}
local M = {}
Nexus.JournalTab = M

local installed = false
local hooked = false
local provider                -- dataProvider() -> { sections={ {title,lines={}} }, version }
local ourTab, panel, scroll, child
local associationPanel
local scanFrame, associationVisible = nil, false
local wishlistPicker, wishlistPickerRows = nil, {}
local HideWishlistPicker
local theirTabCount = 0
local linePool, linesUsed = {}, 0

local ASSET ="Interface\\AddOns\\ProjectEbonhold\\assets\\"

-- Full UI localization (issues #143-#148): every code-owned visible text of
-- this page and its Journal controls is a reviewed key of the "journal."
-- family, looked up through Nexus.Localization when it is shown (never cached
-- at load, so the session's language applies). Code-owned colour codes,
-- separators and line joins stay here around the translated text. Provider
-- section titles and lines, Wishlist, Saved Build and Echo names stay as
-- supplied. TF falls back to the exact English legacy bytes the caller passes
-- when the seam cannot format a template (for example an over-long name).
local function T(key) return (Nexus.Localization.Text(key)) end
local function TF(key, args, english)
    local text, source = Nexus.Localization.Format(key, args)
    if source == "unavailable" and english ~= nil then return english end
    return text
end
local function N(value) return Nexus.Localization.Count(value) end
local function Gray(text) return "|cff8a8a8a" .. text .. "|r" end

-- Build Progress (the tab was "Nexus Advisor"): a short read-only intro, the
-- takeaway and display-only Echo rows first, every provider section unchanged
-- behind Show details. The full explanations sit in the intro tooltip and in
-- the details. The page only reads.
-- The off-Wishlist list is filled only from an active Saved Build whose
-- contents are confirmed, and it arrives empty when none was. An empty list
-- therefore shows nothing about the Saved Build, so it is never shown as 0
-- (journal.tooltip.off_wishlist_none).
local NEUTRAL_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local ROW_H, TILE = 26, 24
local detailsShown = false
-- Set by M.Invalidate after a semantic change; cleared by every page refresh.
local refreshPending = false
local detailsButton, buildsButton, introHover, countsHover
local rowPool, rowsUsed = {}, 0
-- Tome state rows behind Show details have their own pool, so their theme
-- colours and tooltip entries never carry over into the Missing rows.
local tomePool, tomesUsed = {}, 0
local TOME_STATUS_W = 120
-- The provider's request section. Its title does not begin with "Pending",
-- which Summarize reads as the Wishlist's missing-family list.
-- The provider's request section title: an identity matched against the
-- provider's own English title, never shown from here (not translated).
local TOME_REQUESTS = "Tome requests awaiting confirmation"
local PENDING_BADGE = { enable = "journal.status.tome_enable_pending", disable = "journal.status.tome_disable_pending" }
local DeselectOurTab
-- Assignment only records the target. The automatic save (Auto ON, autoSave,
-- Ratchet.Dominates) is what may replace the active Saved Build. A changed
-- assignment marks the adapter's data dirty (MarkWishlistProjectionDirty);
-- Auto's next update step (AutomationRuntime RunUpdate -> StepSave) then
-- checks a finished level-80 run not yet saved this visit against the newly
-- assigned Wishlist. M4 (FN7): the copy states that trigger, not a latency
-- (journal.body.assign_note).
local function AssignNote() return T("journal.body.assign_note") end
-- An empty numbered Saved Build holds no Wishlist of its own and refuses an
-- assignment. The name the Journal shows beside it is the retained first-run
-- Wishlist, which the gear opens for editing without a destination. These
-- wordings say that; no action behind them changes.
local function EmptySlotAssign() return T("journal.tooltip.empty_slot_refused") .. " " .. AssignNote() end
local function EmptySlotSelector()
    return T("journal.tooltip.empty_slot_no_assign") .. " " .. T("journal.tooltip.empty_slot_name_first_run")
        .. " " .. AssignNote()
end

-- UX-05: an assignment to a numbered Saved Build while Auto is selected (ON,
-- also while held) asks first, naming the Wishlist, the target captured when
-- the player chose it and the conditional replacement (no timing promise).
-- Cancel changes nothing; nothing here changes Auto. With Auto OFF the choice
-- assigns at once. Used by the Journal picker and the editor's candidates.
-- At load its text is the format form ("Assign '%s' to %s?" and the
-- consequence, in the language active at load: English, since the session
-- language is chosen later). Its text and buttons are set again by
-- AssignDialogText just before each Show.
local ASSIGN_POPUP = "NEXUS_ASSIGN_WISHLIST_AUTO_ON"
-- The refusal reason the guide receipt records when the adapter has no
-- first-run assignment (raw, never shown; chat shows its reviewed key).
local FIRST_RUN_UNAVAILABLE = "first-run association unavailable"
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs[ASSIGN_POPUP] = {
    text = TF("journal.popup.assign_question", {wishlist = "%s", target = "%s"}) .. "\n"
        .. (T("journal.popup.assign_auto_on"):gsub("%%", "%%%%")),
    button1 = T("journal.button.assign_confirm"),
    button2 = T("journal.button.assign_cancel"),
    OnAccept = function(_, data)
        if type(data) == "table" and type(data.assign) == "function" then data.assign() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- The complete question for one Show: the names are inserted once, here, and
-- every "%" is escaped, so the client's own formatting of the dialog text with
-- the same two names (still passed as its arguments) shows these exact bytes.
local function AssignDialogText(dialog, wishlistName, targetLabel)
    local name, target = tostring(wishlistName or ""), tostring(targetLabel or "")
    local question = TF("journal.popup.assign_question", {wishlist = name, target = target},
        "Assign '" .. name .. "' to " .. target .. "?")
    dialog.text = (question .. "\n" .. T("journal.popup.assign_auto_on")):gsub("%%", "%%%%")
    dialog.button1, dialog.button2 = T("journal.button.assign_confirm"), T("journal.button.assign_cancel")
end

-- Whether Auto is selected (ON, also while held), from the runtime's
-- counters (memory only).
function M.AutoSelected()
    if type(Nexus.RecomputeStats) ~= "function" then return false end
    local ok, stats = pcall(Nexus.RecomputeStats)
    return ok and type(stats) == "table" and stats.autoEnabled == true
end

-- A Wishlist or Saved Build name as it may be shown in chat or a dialog.
function M.SafeName(text, fallback)
    local display = Nexus.Identity and Nexus.Identity.DisplaySafeText
    local shown = display and display(tostring(text or ""), 1024, false) or nil
    if type(shown) ~= "string" or shown == "" then shown = tostring(fallback or "") end
    return shown
end

local function OwnerKeyNow()
    local store = Nexus.Store
    if not (store and type(store.CurrentOwnerKey) == "function") then return nil end
    local ok, owner = pcall(store.CurrentOwnerKey)
    return ok and owner or nil
end

-- One assignment the player chose. `assign` performs it (and every role
-- choice it starts) for the target captured when the player chose it. A
-- numbered, non-empty target with Auto selected asks first; the first-run
-- target has no Saved Build to replace, and an empty one is refused by the
-- assignment itself. When the confirmation cannot be shown, nothing is
-- assigned (never assigned unasked while Auto is selected). One accept
-- performs it once; an accept after the character's saved data changed
-- assigns nothing. Returns true when it asked, false when it assigned at
-- once, nil and a reason when it refused.
function M.AssignWithConsent(wishlistName, targetLabel, numbered, assign)
    if not numbered or not M.AutoSelected() then
        assign()
        return false
    end
    if type(StaticPopup_Show) ~= "function" or type(StaticPopupDialogs) ~= "table"
        or type(StaticPopupDialogs[ASSIGN_POPUP]) ~= "table" then
        print("|cffff6060Nexus:|r " .. T("journal.chat.consent_unavailable"))
        return nil, "consent_unavailable"
    end
    local owner, answered = OwnerKeyNow(), false
    AssignDialogText(StaticPopupDialogs[ASSIGN_POPUP], wishlistName, targetLabel)
    StaticPopup_Show(ASSIGN_POPUP, wishlistName, targetLabel, {assign = function()
        if answered then return end
        answered = true
        if OwnerKeyNow() ~= owner then
            print("|cffff6060Nexus:|r " .. T("journal.chat.owner_changed"))
            return
        end
        assign()
    end})
    return true
end

------------------------------------------------------------------------
-- Auto-pick by rarity instead of a Wishlist (Plan's alternative; the optional
-- leveling pick, settings.autoPickLeveling, "Random Roll" in Options). This
-- file owns the assignment routes, so the choice is made here: it only ever
-- removes the assignment of the one destination the adapter positively
-- verifies (GameAdapter.NoWishlistTarget / ClearAssignmentVerified, the
-- existing Unassign underneath) and turns the existing option on through its
-- existing command. It never selects Auto, never resumes a pause and never
-- touches autoPick or any other permission. An Auto that is selected ON when
-- the choice is accepted is turned OFF first, through the stop-only route
-- (Nexus.DisableOrdinaryAutomation), so the mode never starts picking without
-- the player's own later Auto start. Words: Readout.RarityText.
------------------------------------------------------------------------
local RARITY_POPUP = "NEXUS_USE_RARITY_AUTO_PICK"
StaticPopupDialogs[RARITY_POPUP] = {
    text = "%s", button1 = "", button2 = "",
    OnAccept = function(_, data)
        if type(data) == "table" and type(data.accept) == "function" then data.accept() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- The exact destination as words: the Saved Build with its name and slot, or
-- the first run.
function M.RarityTargetLabel(destination)
    local words = Nexus.Readout.RarityText
    if type(destination) ~= "table" then return words("target_unknown") end
    if destination.kind == "firstRun" then return words("target_first_run") end
    local slot = tostring(tonumber(destination.slot) or "?")
    local name = M.SafeName(destination.name, "")
    if name == "" then return words("target_slot", {slot = slot}) end
    return words("target_saved_build", {name = name, slot = slot})
end

-- Everything the choice and its display rest on, read now and read only:
-- the two settings, the adapter's verified destination and assignment, the
-- level, whether Auto is selected, the session pause, and whether the panel
-- currently admits the runtime's own "it is picking" fact. `mode` is
-- Readout.RarityMode over them. A read that fails leaves its fact unknown.
function M.RarityAutoPickStatus()
    local out = {assignment = "unknown", reason = "unreadable"}
    local store, policy, adapter, panel = Nexus.Store, Nexus.Policy, Nexus.GameAdapter, Nexus.Panel
    local okSettings, settings = pcall(function() return store.Settings() end)
    settings = okSettings and type(settings) == "table" and settings or {}
    out.option, out.autoPick = settings.autoPickLeveling == true, settings.autoPick == true
    local okTarget, target = pcall(function() return adapter.NoWishlistTarget() end)
    if okTarget and type(target) == "table" then
        out.assignment, out.reason = target.state, target.reason
        out.destination, out.wishlist, out.bound = target.destination, target.name, target.bound
    end
    local okLevel, level = pcall(function() return adapter.Level() end)
    out.level = okLevel and tonumber(level) or nil
    out.levelOk = out.level ~= nil and policy and type(policy.LevelingLevel) == "function"
        and policy.LevelingLevel(out.level) == true or false
    out.auto = M.AutoSelected()
    local pause = Nexus.SessionPause
    local okPause, paused = pcall(function() return pause and pause.IsPaused() end)
    out.sessionPaused = okPause and paused and true or false
    local okRun, running = pcall(function() return panel.RandomRollShown(panel._lastModel) end)
    out.running = okRun and running == true
    out.target = M.RarityTargetLabel(out.destination)
    out.mode = Nexus.Readout.RarityMode(out)
    return out
end

-- Turns the existing option on or off through its existing command (the
-- route Options uses), and answers whether the settings now say so.
local function SetRarityOption(on)
    local slash = SlashCmdList and SlashCmdList.NEXUS
    if type(slash) ~= "function" then return false end
    slash(on and "leveling on" or "leveling off")
    local ok, settings = pcall(function() return Nexus.Store.Settings() end)
    return ok and type(settings) == "table" and (settings.autoPickLeveling == true) == (on == true)
end

-- The player chose Auto-pick by rarity (Plan's button or its row in the
-- Wishlist chooser). `done` (optional) is called after anything that changed
-- or refused, so the caller can redraw. Outcomes, each said in chat:
--   a Save is pending, or the destination's assignment is not positively
--     known: nothing changes;
--   it is already what this destination uses: the option is turned off
--     (nothing is assigned or unassigned);
--   nothing is assigned and Auto is OFF: the option is turned on, at once;
--   a Wishlist is assigned, or Auto is selected ON: it asks first, naming the
--     Wishlist and the exact destination. Cancel changes nothing. On accept,
--     in this order: the owner, the pending Save and the destination are
--     checked again (AssignmentBindingHolds); an Auto selected ON by then is
--     turned OFF by the stop-only route and confirmed OFF, else nothing more
--     happens; the assignment is removed only if it is the one that was
--     asked about (ClearAssignmentVerified); only then is the option turned
--     on. Auto stays OFF until the player starts it.
-- Returns true when it asked, false when it acted at once, nil and a reason
-- when it refused.
function M.UseRarityAutoPick(done)
    local words = Nexus.Readout.RarityText
    local function Say(colour, id, args) print(colour .. "Nexus:|r " .. words(id, args)) end
    local function Finish() if type(done) == "function" then pcall(done) end end
    local function SavePending()
        local editor = Nexus.WishlistEditor
        return editor and type(editor.SavePendingNow) == "function" and editor.SavePendingNow() == true
    end
    local function Selected(target, stopped)
        local now = M.RarityAutoPickStatus()
        if now.assignment == "unassigned" then
            Say("|cffffd200", "chat_selected", {target = target, status = now.mode.reason})
        else
            Say("|cffffd200", "chat_unconfirmed", {target = target})
        end
        if stopped then Say("|cffffd200", "chat_auto_stopped") end
    end
    local status = M.RarityAutoPickStatus()
    if SavePending() then
        Say("|cffff6060", "chat_pending_save")
        Finish()
        return nil, "pending_save"
    end
    if status.assignment ~= "unassigned" and status.assignment ~= "assigned" then
        Say("|cffff6060", "chat_unknown", {target = status.target,
            reason = words("reason_" .. tostring(status.reason))})
        Finish()
        return nil, status.reason or "unknown"
    end
    if status.assignment == "unassigned" and status.option then
        if SetRarityOption(false) then Say("|cffffd200", "chat_deselected") end
        Finish()
        return false, "deselected"
    end
    if status.assignment == "unassigned" and not status.auto then
        if SetRarityOption(true) then Selected(status.target) else Say("|cffff6060", "chat_option_failed") end
        Finish()
        return false
    end
    local dialog = type(StaticPopupDialogs) == "table" and StaticPopupDialogs[RARITY_POPUP] or nil
    if type(StaticPopup_Show) ~= "function" or type(dialog) ~= "table" then
        Say("|cffff6060", "chat_consent_unavailable")
        Finish()
        return nil, "consent_unavailable"
    end
    local question = status.assignment == "assigned"
        and (words("popup_unassign", {wishlist = M.SafeName(status.wishlist, "?"), target = status.target})
            .. "\n" .. words("popup_keep"))
        or words("popup_select", {target = status.target})
    question = question .. "\n" .. words(status.auto and "popup_auto_on" or "popup_auto_off")
    dialog.text = question:gsub("%%", "%%%%")
    dialog.button1, dialog.button2 = words("button_confirm"), words("button_cancel")
    local owner, bound, target, answered = OwnerKeyNow(), status.bound, status.target, false
    StaticPopup_Show(RARITY_POPUP, nil, nil, {accept = function()
        if answered then return end
        answered = true
        if OwnerKeyNow() ~= owner then
            Say("|cffff6060", "chat_owner_changed")
        elseif SavePending() then
            Say("|cffff6060", "chat_pending_save")
        elseif not Nexus.GameAdapter.AssignmentBindingHolds(bound) then
            Say("|cffff6060", "chat_changed")
        else
            -- Consent given and the destination verified: stop Auto before
            -- anything is removed or enabled, and go on only once it is OFF.
            local stopped = false
            if M.AutoSelected() then
                local stop = Nexus.DisableOrdinaryAutomation
                local off = type(stop) == "function" and stop() == true
                if not off or M.AutoSelected() then
                    Say("|cffff6060", "chat_auto_not_stopped")
                    Finish()
                    return
                end
                stopped = true
            end
            local ok, why = Nexus.GameAdapter.ClearAssignmentVerified(bound)
            if not ok then
                Say("|cffff6060", why == "write_failed" and "chat_write_failed" or "chat_changed")
                if stopped then Say("|cffffd200", "chat_auto_stopped") end
            elseif SetRarityOption(true) then
                pcall(M.RefreshAssociations)
                Selected(target, stopped)
            else
                pcall(M.RefreshAssociations)
                Say("|cffff6060", why == "already" and "chat_option_failed" or "chat_option_failed_removed")
                if stopped then Say("|cffffd200", "chat_auto_stopped") end
            end
        end
        Finish()
    end})
    return true
end

-- Guided setup receipt (core/GuidedSetup.lua): reports the outcome of an
-- assignment the player chose in this chooser. It records only; it writes,
-- requests and changes nothing, and a missing guide changes nothing.
local function GuideAssign(numbered, active, ok, reason, snapshot, origin)
    local guide = Nexus.GuidedSetup
    if not (guide and type(guide.Note) == "function") then return end
    pcall(guide.Note, "assign", {origin = "journal",
        destination = numbered and tonumber(active) or "first", ok = ok == true, reason = reason,
        key = type(snapshot) == "table" and snapshot.key or nil,
        slot = type(snapshot) == "table" and snapshot.slot or nil,
        name = type(snapshot) == "table" and snapshot.name or nil, guide = origin})
end

-- The guide request this chooser operation began under: an opaque token the
-- guide issues as the player clicks, before any confirmation or role choice
-- (nil when none is armed for this target), carried unchanged to every result
-- of that operation. It reads guide state only and changes nothing here.
local function GuideOrigin(numbered, active, snapshot)
    local guide = Nexus.GuidedSetup
    if not (guide and type(guide.BeginAssign) == "function") then return nil end
    local ok, origin = pcall(guide.BeginAssign, numbered and tonumber(active) or "first",
        type(snapshot) == "table" and snapshot.key or nil)
    return ok and origin or nil
end

------------------------------------------------------------------------
-- Text lines
------------------------------------------------------------------------

local function AcquireLine()
    linesUsed = linesUsed + 1
    local fs = linePool[linesUsed]
    if not fs then
        fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        linePool[linesUsed] = fs
    end
    fs:Show()
    return fs
end

-- The provider section with this title (or title prefix), if any.
local function Section(sections, title, prefix)
    for i = 1, #sections do
        local sec = sections[i]
        local t = type(sec) == "table" and tostring(sec.title or "") or ""
        if t == title or (prefix and t:sub(1, #title) == title) then return sec end
    end
end

-- The provider's Target line, read only in the exact form JournalData writes
-- it. Counts are taken from the anchored end, never from the Wishlist name.
local TARGET_COUNTS = ": (%d+) Echo families %-%- (%d+) represented, (%d+) missing, "
    .. "(%d+) off%-Wishlist families in the saved build$"
local TARGET_TAGS = { [""] = true, [" (Echo Wishlist build)"] = true, [" (active loadout)"] = true }
-- The explanations JournalData appends to an off-Wishlist family name.
local OFF_SUFFIXES = { "  (not on the target plan; compare after the next run)",
    "  (a later run may reduce these extras)" }
local NOTES_FIRST = "Compares the assigned Wishlist with the active Saved Build; "
    .. "planned locked targets are not proof of ownership."
-- The estimate texts JournalData and Ratchet.RunsEstimate write when there is
-- nothing to estimate: no Wishlist, no requested family, or no result.
local NO_ESTIMATE = { ["no estimate (advisor mode)"] = true, ["estimate unavailable"] = true,
    ["no wishlist target - advisor mode"] = true }
-- Why family progress is unknown: a code-owned identity (s.problem), shown as
-- its complete reviewed sentence by Takeaway.
local UNKNOWN_NO_PENDING = "journal.status.unknown_no_pending"
local UNKNOWN_BAD_PENDING = "journal.status.unknown_bad_pending"
local UNKNOWN_CONTRADICTORY = "journal.status.unknown_contradictory"
local UNKNOWN_GRAMMAR = "journal.status.unknown_grammar"

-- A provider list, or nil unless it is a plain sequence of non-empty strings.
local function TextLines(lines)
    if type(lines) ~= "table" then return nil end
    local count = 0
    for _ in pairs(lines) do count = count + 1 end
    if count ~= #lines then return nil end
    for i = 1, #lines do
        if type(lines[i]) ~= "string" or lines[i] == "" then return nil end
    end
    return lines
end

-- What the provider's sections establish, and nothing more. `known` needs the
-- Target counts in their exact form, one Pending list matching its title and
-- those counts, and an off-Wishlist list that does not contradict them. Any
-- gap or disagreement leaves the family progress unknown. A family is
-- represented when one copy is known; copies are never compared here.
local function Summarize(sections)
    local s = {}
    local target = Section(sections, "Target")
    local first = target and type(target.lines) == "table" and target.lines[1]
    if type(first) ~= "string" or first == "" then return s end
    if first:find("No wishlist set", 1, true) == 1 then s.noTarget = true return s end
    s.targetLine = first

    local pendingSec, pendingSections = nil, 0
    for i = 1, #sections do
        local sec = sections[i]
        if type(sec) == "table" and tostring(sec.title or ""):sub(1, 7) == "Pending" then
            pendingSec = pendingSec or sec
            pendingSections = pendingSections + 1
        end
    end
    local pending, n
    if pendingSec then
        n = tonumber(tostring(pendingSec.title):match("^Pending %((%d+)%)$"))
        pending = TextLines(pendingSec.lines)
    end
    local offSec = Section(sections, "Extra copies compared with the plan")
    local off = offSec and TextLines(offSec.lines)

    local at, _, total, rep, miss, offN = first:find(TARGET_COUNTS)
    local head = at and first:sub(1, at - 1)
    local name, tag
    if head then name, tag = head:match("^Wishlist '(.*)'(.*)$") end
    total, rep, miss, offN = tonumber(total), tonumber(rep), tonumber(miss), tonumber(offN)
    if pendingSections > 1 then s.problem = UNKNOWN_CONTRADICTORY
    elseif not pendingSec then s.problem = UNKNOWN_NO_PENDING
    elseif not (n and pending and #pending == n) then s.problem = UNKNOWN_BAD_PENDING
    elseif not (name and TARGET_TAGS[tag]) then s.problem = UNKNOWN_GRAMMAR
    elseif total ~= rep + miss or miss ~= n or (off and #off ~= offN) then
        s.problem = UNKNOWN_CONTRADICTORY
    else
        s.known, s.title, s.pending, s.off = true, head, pending, off
        s.total, s.represented, s.missing, s.offCount = total, rep, miss, offN
        -- The one section these Missing rows were validated from (Show
        -- details draws it without repeating them).
        s.pendingSection = pendingSec
    end
    return s
end

-- The first line of the page: what is still missing, or why that is unknown.
local function Takeaway(s)
    if s.noTarget then return T("journal.status.no_wishlist") end
    if not s.targetLine then return T("journal.status.summary_missing") end
    -- One complete sentence per reason; the reason is an identity, not text.
    if not s.known then return T(s.problem) end
    -- A Wishlist that requests no family has no family progress, so nothing
    -- is said to be represented or missing.
    if s.total == 0 then return T("journal.status.no_families_requested") end
    local names = s.pending
    if #names == 0 then return T("journal.status.none_missing") end
    local shown = {}
    for i = 1, math.min(3, #names) do shown[i] = names[i] end
    -- The provider's family names are data, joined with the code-owned ", ".
    -- English chooses between three wordings; so does this code (no plural
    -- grammar): one family, up to three, or three named and the rest counted.
    local list = table.concat(shown, ", ")
    local english = "Still missing " .. #names .. (#names == 1 and " Echo family: " or " Echo families: ")
        .. list .. (#names > 3 and (" and " .. (#names - 3) .. " more") or "") .. "."
    if #names == 1 then
        return TF("journal.status.missing_one_family", {count = N(1), names = list}, english)
    elseif #names <= 3 then
        return TF("journal.status.missing_families", {count = N(#names), names = list}, english)
    end
    return TF("journal.status.missing_families_more", {count = N(#names), names = list, more = N(#names - 3)},
        english)
end

-- The Notes estimate, only in the exact two-line form JournalData writes. The
-- raw Notes section stays unchanged in the details either way.
local function EstimateLine(sections)
    local notes = Section(sections, "Notes")
    local lines = notes and TextLines(notes.lines)
    if not (lines and #lines == 2 and lines[1] == NOTES_FIRST) then return nil end
    local est = lines[2]
    if NO_ESTIMATE[est] then return T("journal.status.estimate_unavailable") end
    -- The estimate itself is the provider's text, said through the Journal
    -- book when it is one of its own forms (M.JournalShown), else as supplied.
    return TF("journal.status.estimate", {estimate = (M.JournalShown(est))}, "Estimate, not a prediction: " .. est
        .. ". Based only on what is known to be missing; no future offer is assumed.")
end

-- An off-Wishlist line is a family name plus one of the provider's known
-- explanations. With any other ending the whole line is the label.
local function SplitOffLine(line)
    for i = 1, #OFF_SUFFIXES do
        local suffix = OFF_SUFFIXES[i]
        if #line > #suffix and line:sub(-#suffix) == suffix then
            return line:sub(1, #line - #suffix)
        end
    end
    return line
end

local function CurrentCatalog()
    local A = Nexus.GameAdapter
    if not (A and type(A.Catalog) == "function") then return nil end
    local ok, catalog = pcall(A.Catalog)
    return ok and type(catalog) == "table" and catalog or nil
end

-- Row icons. A name resolves only when it is exactly one catalog family's
-- name; the icon is the GetSpellInfo texture of a member linked back to that
-- family. The name index is built once per catalog table (a rebuilt catalog
-- is a new table), not on each refresh. Anything else, including a name two
-- families share, gets the neutral tile. Nothing here requests or changes
-- anything.
local iconIndex = {}

local function FamilyIcon(catalog, name)
    if type(catalog) ~= "table" or type(name) ~= "string" or name == "" then return nil end
    local names, members = catalog.familyName, catalog.familyMembers
    local familyOf, rows = catalog.familyOf, catalog.rows
    if type(names) ~= "table" or type(members) ~= "table" or type(familyOf) ~= "table"
        or type(rows) ~= "table" then return nil end
    if iconIndex.catalog ~= catalog then
        local byName = {}
        for key, familyName in pairs(names) do
            if type(familyName) == "string" and familyName ~= "" then
                byName[familyName] = byName[familyName] == nil and key or false
            end
        end
        iconIndex.catalog, iconIndex.byName, iconIndex.icons = catalog, byName, {}
    end
    local icon = iconIndex.icons[name]
    if icon == nil then
        icon = false
        local key = iconIndex.byName[name]
        local list = key and members[key]
        if type(list) == "table" and type(GetSpellInfo) == "function" then
            for i = 1, #list do
                local id = list[i]
                local row = rows[id]
                if type(id) == "number" and familyOf[id] == key and type(row) == "table" and row.spellId == id then
                    local ok, _, _, texture = pcall(GetSpellInfo, id)
                    if ok and ((type(texture) == "string" and texture ~= "") or type(texture) == "number") then
                        icon = texture
                        break
                    end
                end
            end
        end
        iconIndex.icons[name] = icon
    end
    return icon or nil
end

-- Display-only Echo rows in the Orb history's visual language: a subtle
-- separator, the icon tile on the left, the family text and a short status
-- word. Frames and scripts are created once and reused on every refresh; the
-- complete text is always in the row tooltip.
local function RowEnter(self)
    if self.hover then self.hover:Show() end
    if not (GameTooltip and self.tipName) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.tipName, 1, 1, 1, true)
    GameTooltip:AddLine(self.tipStatus, 0.82, 0.82, 0.82, true)
    if self.tipRaw then
        GameTooltip:AddLine(TF("journal.tooltip.source_text", {text = self.tipRaw}, "Source text: " .. self.tipRaw),
            0.82, 0.82, 0.82, true)
    end
    if self.tipIcon then GameTooltip:AddLine(self.tipIcon, 0.6, 0.6, 0.6, true) end
    GameTooltip:Show()
end

local function RowLeave(self)
    if self.hover then self.hover:Hide() end
    if GameTooltip then GameTooltip:Hide() end
end

-- A provider string worth showing, or nil.
-- The automation runtime's Journal sections (core/AutomationRuntime.lua
-- JournalData, with logic/Ratchet.lua's estimate and core/GameAdapter.lua's
-- tome-state reasons) keep their raw English: Summarize and EstimateLine
-- classify that raw text. Only the display says it in the active language:
-- exact titles and lines, and the provider's own formats (%d a count, %s a
-- name or code value; nested: a value through this same book). Any other
-- text (a family or tome name, an unknown reason) is shown as before.
-- JOURNAL-PROVIDER BEGIN (generated from the fragment)
local JOURNAL_PHRASES = {exact = {
    ["Target"] = "journal.provider.title_target",
    ["Extra copies compared with the plan"] = "journal.provider.title_extra_copies",
    ["Tome state coverage"] = "journal.provider.title_tome_coverage",
    ["Disabled tomes (client mirror)"] = "journal.provider.title_tomes_disabled",
    ["Tome requests awaiting confirmation"] = "journal.provider.title_tome_requests",
    ["Unknown or mixed tome state"] = "journal.provider.title_tomes_unknown",
    ["Enabled tomes (client mirror)"] = "journal.provider.title_tomes_enabled",
    ["Notes"] = "journal.provider.title_notes",
    ["No wishlist set -- advisor only."] = "journal.provider.no_wishlist",
    ["Design a build with 'New Wishlist' (the Echo Wishlist section)."] = "journal.provider.design_hint",
    ["Client mirror observed when this page was refreshed; server freshness and current server state are unverified."] = "journal.provider.mirror_observed",
    ["Missing Tomes means undiscovered Wishlist requirements; disabled tomes and pending requests are separate below."] = "journal.provider.missing_tomes_meaning",
    ["Catalog unavailable; no complete tome list can be shown."] = "journal.provider.catalog_unavailable",
    ["No pending requests recorded for tomes in the known catalog."] = "journal.provider.no_tome_requests",
    ["None observed; state may be stale."] = "journal.provider.none_observed_stale",
    ["None observed in this client catalog."] = "journal.provider.none_observed",
    ["Compares the assigned Wishlist with the active Saved Build; planned locked targets are not proof of ownership."] = "journal.provider.compares_plan",
    ["no estimate (advisor mode)"] = "journal.provider.estimate_advisor",
    ["estimate unavailable"] = "journal.provider.estimate_unavailable",
    ["no wishlist target - advisor mode"] = "journal.provider.estimate_no_target",
    ["wishlist complete - 0 wanted echoes pending"] = "journal.provider.estimate_complete",
    ["catalog is unavailable"] = "journal.provider.stale_catalog_unavailable",
    ["character data is not ready"] = "journal.provider.stale_character_not_ready",
    ["discovery mirror is unsynced"] = "journal.provider.stale_mirror_unsynced",
    ["client mirror update is awaiting reconciliation"] = "journal.provider.stale_awaiting_reconciliation",
    ["discovery state is unavailable"] = "journal.provider.stale_discovery_unavailable",
    ["world transition in progress"] = "journal.provider.stale_world_transition",
    ["character data is settling after a world transition"] = "journal.provider.stale_settling",
    ["Disabled"] = "journal.provider.tome_disabled",
    ["Enabled"] = "journal.provider.tome_enabled",
    ["Mixed"] = "journal.provider.tome_mixed",
    ["Undiscovered"] = "journal.provider.tome_undiscovered",
    ["Unknown"] = "journal.provider.tome_unknown_state",
    ["plan: disable"] = "journal.provider.plan_disable",
    ["plan: keep enabled (a Wishlist family uses it)"] = "journal.provider.plan_keep_wishlist",
    ["plan: keep enabled (opted out of automatic disabling)"] = "journal.provider.plan_keep_opted_out",
    ["automatic toggle skipped: unsupported availability data"] = "journal.provider.plan_skipped_unsupported",
    ["undiscovered in the client mirror"] = "journal.provider.reason_undiscovered",
    ["discovery state unavailable"] = "journal.provider.reason_discovery_unavailable",
    ["members have different disable states"] = "journal.provider.reason_members_mixed",
    ["member state unavailable or unreadable"] = "journal.provider.reason_member_unreadable",
}, formats = {
    {format = "Pending (%d)", key = "journal.provider.title_pending", fields = {"count"}},
    {format = "Known client catalog: %d tomes; coverage of the whole game is unverified.", key = "journal.provider.catalog_known", fields = {"count"}},
    {format = "State may be stale: %s.", key = "journal.provider.state_stale", fields = {"reasons"}, nested = {reasons = true}},
    {format = "catalog may be stale (%s)", key = "journal.provider.catalog_stale", fields = {"state"}},
    {format = "Wishlist '%s' (Echo Wishlist build): %d Echo families -- %d represented, %d missing, %d off-Wishlist families in the saved build", key = "journal.provider.target_designed", fields = {"name", "families", "represented", "missing", "off"}},
    {format = "Wishlist '%s' (active loadout): %d Echo families -- %d represented, %d missing, %d off-Wishlist families in the saved build", key = "journal.provider.target_active", fields = {"name", "families", "represented", "missing", "off"}},
    {format = "Wishlist '%s': %d Echo families -- %d represented, %d missing, %d off-Wishlist families in the saved build", key = "journal.provider.target_plain", fields = {"name", "families", "represented", "missing", "off"}},
    {format = "%s  (not on the target plan; compare after the next run)", key = "journal.provider.extra_compare_next_run", fields = {"family"}},
    {format = "%s  (a later run may reduce these extras)", key = "journal.provider.extra_later_run", fields = {"family"}},
    {format = "~%d wishlist echo pending; no future random roll is assumed (rate unmeasured)", key = "journal.provider.estimate_one", fields = {"count"}},
    {format = "~%d wishlist echoes pending; no future random roll is assumed (rate unmeasured)", key = "journal.provider.estimate_many", fields = {"count"}},
    {format = "%s (stale)", key = "journal.provider.tome_status_stale", fields = {"status"}, nested = {status = true}},
}}
-- JOURNAL-PROVIDER END
-- Tome-state reasons are code-owned lists: core/GameAdapter.lua
-- TomeStateObservation gives a tome's member reason and the stale reasons,
-- the runtime adds a discovery reason and joins them with "; ". Each list
-- component that is exactly one of these reasons is said through its key;
-- the "; " separators and any other component (an unknown or later detail)
-- stay byte for byte. Only these lists are split, never other text.
local REASON_SEPARATOR = "; "
local REASON_TEXTS = {"catalog is unavailable", "character data is not ready", "discovery mirror is unsynced",
    "client mirror update is awaiting reconciliation", "discovery state is unavailable", "world transition in progress",
    "character data is settling after a world transition", "undiscovered in the client mirror",
    "discovery state unavailable", "members have different disable states", "member state unavailable or unreadable"}
local REASON_PHRASES = {exact = {}, formats = {
    {format = "catalog may be stale (%s)", key = "journal.provider.catalog_stale", fields = {"state"}},
}}
for _, text in ipairs(REASON_TEXTS) do REASON_PHRASES.exact[text] = JOURNAL_PHRASES.exact[text] end
local STALE_PREFIX = "State may be stale: "
local journalBook, reasonBook
local function ReasonShown(raw)
    local L = Nexus.Localization
    if type(raw) ~= "string" or raw == "" or type(L) ~= "table" or type(L.PhraseBook) ~= "function" then return raw, false end
    if not reasonBook or reasonBook.seam ~= L then
        reasonBook = L.PhraseBook(REASON_PHRASES)
        reasonBook.seam = L
    end
    local parts, from, said = {}, 1, false
    while true do
        local at = raw:find(REASON_SEPARATOR, from, true)
        local shown, known = L.Phrase(raw:sub(from, (at or (#raw + 1)) - 1), reasonBook)
        parts[#parts + 1] = shown
        said = said or known
        if not at then break end
        from = at + #REASON_SEPARATOR
    end
    return table.concat(parts, REASON_SEPARATOR), said
end
M.ReasonShown = ReasonShown
local function JournalShown(raw)
    local L = Nexus.Localization
    if type(raw) ~= "string" or type(L) ~= "table" or type(L.PhraseBook) ~= "function" then return raw, false end
    if not journalBook or journalBook.seam ~= L then
        journalBook = L.PhraseBook(JOURNAL_PHRASES)
        journalBook.seam = L
    end
    -- The coverage line's reasons, said one by one inside the outer key; when
    -- the active language has no valid outer candidate the whole line is the
    -- runtime's exact English.
    if #raw > #STALE_PREFIX + 1 and raw:sub(1, #STALE_PREFIX) == STALE_PREFIX and raw:sub(-1) == "." then
        local text, source = L.Format("journal.provider.state_stale",
            {reasons = (ReasonShown(raw:sub(#STALE_PREFIX + 1, -2)))})
        if source == "candidate" then return text, true end
        return raw, source ~= "unavailable"
    end
    return L.Phrase(raw, journalBook)
end
M.JournalShown = JournalShown

-- A tome row's names as shown: the tome name and its Echo names. Only names
-- the adapter generated (core/GameAdapter.lua A.TomeNameFacts, bound to
-- exactly this row's name and Echo names) are said through their keys; a
-- supplied name stays as given, however it reads. A generated name keeps its
-- exact English when the active language has no valid candidate for it.
local function TomeNames(t)
    local adapter, L = Nexus.GameAdapter, Nexus.Localization
    local echoes = type(t) == "table" and type(t.echoNames) == "table" and t.echoNames or {}
    local name = type(t) == "table" and t.name or nil
    local facts = type(adapter) == "table" and type(adapter.TomeNameFacts) == "function"
        and adapter.TomeNameFacts(t.leverId, name, echoes) or nil
    local canFormat = type(L) == "table" and type(L.Format) == "function"
    local shown = {}
    for i = 1, #echoes do
        local echo, id = echoes[i], facts and facts.memberIds[i]
        if id ~= nil and canFormat then
            local text, source = L.Format("journal.provider.generated_echo_name", {id = tostring(id)})
            if source == "candidate" then echo = text end
        end
        shown[i] = echo
    end
    if facts and facts.nameGenerated and canFormat then
        local text, source = L.Format("journal.provider.generated_tome_name", {echoes = table.concat(shown, ", ")})
        if source == "candidate" then name = text end
    end
    return name, shown
end
M.TomeNames = TomeNames

local function Filled(value)
    return type(value) == "string" and value ~= "" and value or nil
end

local function RequestText(pending)
    return T(pending == "enable" and "journal.tooltip.tome_enable_requested"
        or pending == "disable" and "journal.tooltip.tome_disable_requested"
        or "journal.tooltip.tome_request_unknown")
end

-- The complete tome entry: the observation and any request kept apart, the
-- supplied reason and plan, its Echoes, the raw control ID and where the icon
-- came from. Only the supplied entry is read.
local function TomeRowEnter(self)
    if self.hover then self.hover:Show() end
    local t = self.tome
    if not (GameTooltip and type(t) == "table") then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local tomeName, echoNames = TomeNames(t)
    GameTooltip:AddLine(tomeName, 1, 1, 1, true)
    -- The observation (t.status), reason, plan and names are the provider's
    -- text, shown as supplied; only the words around them are reviewed keys.
    local observed = (Filled(t.status) and (JournalShown(t.status))) or T("journal.value.tome_unknown")
    if self.tomeRequest then
        GameTooltip:AddLine(RequestText(t.pending), 1, 0.82, 0, true)
        GameTooltip:AddLine(TF("journal.tooltip.tome_last_observed", {state = observed},
            "Last observed in the client mirror: " .. observed), 0.82, 0.82, 0.82, true)
    else
        GameTooltip:AddLine(TF("journal.tooltip.tome_mirror", {state = observed}, "Client mirror: " .. observed),
            0.82, 0.82, 0.82, true)
        if t.pending ~= nil then GameTooltip:AddLine(RequestText(t.pending), 1, 0.82, 0, true) end
    end
    if Filled(t.reason) then GameTooltip:AddLine((ReasonShown(t.reason)), 0.82, 0.82, 0.82, true) end
    if Filled(t.plan) then GameTooltip:AddLine((JournalShown(t.plan)), 0.82, 0.82, 0.82, true) end
    local names = {}
    for i = 1, #echoNames do names[#names + 1] = Filled(echoNames[i]) end
    if #names > 0 then
        -- English chooses Echo or Echoes; so does this code (two keys).
        local list = table.concat(names, ", ")
        GameTooltip:AddLine(#names == 1 and TF("journal.tooltip.tome_echo_one", {names = list}, "Echo: " .. list)
            or TF("journal.tooltip.tome_echo_many", {names = list}, "Echoes: " .. list),
            0.82, 0.82, 0.82, true)
    end
    if t.leverId ~= nil then
        local id = tostring(t.leverId)
        GameTooltip:AddLine(TF("journal.tooltip.tome_control_id", {id = id}, "Control ID: " .. id),
            0.6, 0.6, 0.6, true)
    end
    local icon = not self.tomeIcon and "journal.tooltip.tome_icon_neutral"
        or t.iconSource == "tome spell" and "journal.tooltip.tome_icon_spell"
        or t.iconSource == "representative Echo spell" and "journal.tooltip.tome_icon_member"
        or "journal.tooltip.tome_icon_unstated"
    GameTooltip:AddLine(T(icon), 0.6, 0.6, 0.6, true)
    if t.stale == true then GameTooltip:AddLine(T("journal.tooltip.tome_stale"), 1, 0.63, 0.25, true) end
    GameTooltip:AddLine(T("journal.tooltip.tome_scope"), 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

-- A section's structured tome rows, or nil so that its text lines are shown:
-- a plain non-empty sequence whose every entry carries a readable name.
local function TomeRows(list)
    if type(list) ~= "table" or #list == 0 then return nil end
    local count = 0
    for _ in pairs(list) do count = count + 1 end
    if count ~= #list then return nil end
    for i = 1, #list do
        if type(list[i]) ~= "table" or not Filled(list[i].name) then return nil end
    end
    return list
end

-- One row frame for either pool. A striped row (the tome rows) also gets a
-- background whose faint shade alternates with its neighbours.
local function NewRow(statusWidth, striped)
    local row = CreateFrame("Frame", nil, child)
    row:SetHeight(ROW_H)
    row:EnableMouse(true)
    if striped then
        row.background = row:CreateTexture(nil, "BACKGROUND")
        row.background:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.background:SetAllPoints(row)
    end
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.hover:SetAllPoints(row)
    row.hover:SetVertexColor(0.30, 0.40, 0.52, 0.18)
    row.separator = row:CreateTexture(nil, "BORDER")
    row.separator:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.separator:SetHeight(1)
    row.separator:SetPoint("BOTTOMLEFT", 0, 0)
    row.separator:SetPoint("BOTTOMRIGHT", 0, 0)
    row.separator:SetVertexColor(0.22, 0.24, 0.28, 0.55)
    row.tile = row:CreateTexture(nil, "ARTWORK")
    row.tile:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.tile:SetSize(TILE, TILE)
    row.tile:SetPoint("LEFT", 2, 0)
    row.tile:SetVertexColor(0.08, 0.10, 0.13, 0.95)
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(TILE - 4, TILE - 4)
    row.icon:SetPoint("CENTER", row.tile, "CENTER", 0, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.status:SetPoint("RIGHT", -4, 0)
    row.status:SetWidth(statusWidth)
    row.status:SetJustifyH("RIGHT")
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.tile, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
    row.label:SetJustifyH("LEFT")
    -- Both texts keep one line at the row's height, so neither can grow
    -- into the next row; the row tooltip has the complete name.
    if Nexus.LayoutMetrics then
        pcall(Nexus.LayoutMetrics.OneLineLabel, row.label, nil, ROW_H - 6)
        pcall(Nexus.LayoutMetrics.OneLineLabel, row.status, nil, ROW_H - 6)
    end
    return row
end

local function AcquireRow()
    rowsUsed = rowsUsed + 1
    local row = rowPool[rowsUsed]
    if not row then
        row = NewRow(78)
        row:SetScript("OnEnter", RowEnter)
        row:SetScript("OnLeave", RowLeave)
        rowPool[rowsUsed] = row
    end
    row.hover:Hide()
    row:Show()
    return row
end

local function AcquireTomeRow()
    tomesUsed = tomesUsed + 1
    local row = tomePool[tomesUsed]
    if not row then
        row = NewRow(TOME_STATUS_W, true)
        -- Names take the style's readable text colour; each badge's role is
        -- set per entry. The theme repaints both when either choice changes.
        if Nexus.Theme then pcall(Nexus.Theme.StyleLabel, row.label, "text") end
        row:SetScript("OnEnter", TomeRowEnter)
        row:SetScript("OnLeave", RowLeave)
        tomePool[tomesUsed] = row
    end
    row.hover:Hide()
    row:Show()
    return row
end

-- The short intro keeps the full purpose and notes in its tooltip.
local function IntroHover()
    if introHover then return introHover end
    introHover = CreateFrame("Frame", nil, child)
    introHover:EnableMouse(true)
    introHover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(T("journal.heading.build_progress"), 1, 0.82, 0)
        GameTooltip:AddLine(T("journal.body.purpose"), 0.82, 0.82, 0.82, true)
        GameTooltip:AddLine(T("journal.body.compare_active"), 0.82, 0.82, 0.82, true)
        GameTooltip:AddLine(Gray(T("journal.body.set_in_my_builds")), 0.82, 0.82, 0.82, true)
        GameTooltip:AddLine(T("journal.body.family_coverage"), 0.82, 0.82, 0.82, true)
        GameTooltip:Show()
    end)
    introHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return introHover
end

-- The counts line explains itself in a tooltip, including what an empty or
-- unreadable off-Wishlist list does and does not show.
local function CountsHover()
    if countsHover then return countsHover end
    countsHover = CreateFrame("Frame", nil, child)
    countsHover:EnableMouse(true)
    countsHover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(T("journal.tooltip.counts_heading"), 1, 0.82, 0)
        GameTooltip:AddLine(T("journal.body.family_coverage"), 0.82, 0.82, 0.82, true)
        if self.offTip then GameTooltip:AddLine(self.offTip, 0.82, 0.82, 0.82, true) end
        GameTooltip:Show()
    end)
    countsHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return countsHover
end

-- The page's buttons, created once in the scrolled content.
local function PageButton(kind)
    local b = kind == "details" and detailsButton or kind == "help" and M._pageHelpButton
        or kind == "reference" and M._pageReferenceButton
        or kind == "builds" and buildsButton or nil
    if b then return b end
    b = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
    if kind == "help" then
        -- Help is the guided setup coach (Help.OpenHelp; native QA
        -- test.163008), above the Journal. Passive: it assigns, saves, sends,
        -- rolls, spends and turns nothing on. Kept on the module table.
        M._pageHelpButton = b
        b:SetSize(56, 22)
        b:SetText(T("journal.button.help"))
        b:SetScript("OnClick", function()
            if Nexus.Help and Nexus.Help.OpenHelp then Nexus.Help.OpenHelp("wishlists") end
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(T("journal.button.help"), 1, 1, 1)
            GameTooltip:AddLine(T("journal.tooltip.help_opens_guide"), 0.82, 0.82, 0.82, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    elseif kind == "reference" then
        -- The manual's Wishlists and locked targets page, above the Journal,
        -- under its own name. Passive, as Help.
        M._pageReferenceButton = b
        b:SetSize(80, 22)
        b:SetText(T("journal.button.reference"))
        b:SetScript("OnClick", function()
            if Nexus.Help and Nexus.Help.OpenReference then Nexus.Help.OpenReference("wishlists") end
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(T("journal.button.reference"), 1, 1, 1)
            GameTooltip:AddLine(T("journal.tooltip.reference_opens_manual"), 0.82, 0.82, 0.82, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    elseif kind == "details" then
        detailsButton = b
        b:SetSize(112, 22)
        b:SetScript("OnClick", function()
            detailsShown = not detailsShown
            M.Refresh()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(T(detailsShown and "journal.button.hide_details" or "journal.button.show_details"),
                1, 1, 1)
            GameTooltip:AddLine(T("journal.tooltip.details_contents"), 0.82, 0.82, 0.82, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        buildsButton = b
        b:SetSize(150, 22)
        -- My Builds names the game's own page (ux_record_scope_terms
        -- GAME_PAGE_LABELS checks this binding and its exact English).
        b:SetText(T("journal.button.assign_in_my_builds"))
        b:SetScript("OnClick", function()
            pcall(function() if panel and panel:IsShown() then DeselectOurTab(true) end end)
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(T("journal.button.assign_in_my_builds"), 1, 1, 1)
            GameTooltip:AddLine(T("journal.tooltip.builds_closes_page") .. " " .. AssignNote(),
                0.82, 0.82, 0.82, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return b
end

local function DoRefresh()
    local data, failed
    if type(provider) == "function" then
        local okP, res = pcall(provider)
        if okP and type(res) == "table" then data = res elseif not okP then failed = true end
    end

    -- Pooled family and tome rows may be rebound below to other entries, and
    -- the counts hover's off-Wishlist note may change; a tooltip one of them
    -- owns would keep describing the old entry. The static intro and any
    -- other owner's tooltip stay.
    if GameTooltip and type(GameTooltip.GetOwner) == "function" then
        local okOwner, owner = pcall(GameTooltip.GetOwner, GameTooltip)
        if okOwner and owner ~= nil then
            local owned = countsHover ~= nil and owner == countsHover
            for i = 1, #rowPool do
                if owned then break end
                owned = rowPool[i] == owner
            end
            for i = 1, #tomePool do
                if owned then break end
                owned = tomePool[i] == owner
            end
            if owned then GameTooltip:Hide() end
        end
    end

    linesUsed, rowsUsed, tomesUsed = 0, 0, 0
    local width = math.floor((scroll and scroll:GetWidth()) or 0)
    if width < 100 then width = 292 end
    width = width - 12
    local cy = -6
    local catalog, catalogRead = nil, false

    -- `plain` keeps provider names exactly as supplied (no public rewording).
    local function AddLine(text, font, indent, plain)
        if not plain then text = Nexus.UserText and Nexus.UserText.Message(text) or text end
        indent = indent or 0
        local fs = AcquireLine()
        fs:SetFontObject(font or "GameFontHighlightSmall")
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", 6 + indent, cy)
        fs:SetWidth(width - indent)
        -- Height 0 + fixed width = word-wrap; GetStringHeight is then
        -- the wrapped height.
        fs:SetHeight(0)
        fs:SetText(text or "")
        local h = fs:GetStringHeight()
        if not h or h < 12 then h = 12 end
        cy = cy - h - 2
        return fs
    end

    -- One display-only row for a supplied family name. `name` is looked up
    -- for an icon by exact family name only; `raw` is the provider's line.
    -- `missing` (true for a Missing row, false for an Off Wishlist row) is the
    -- row's identity: its colour follows it, never the shown word.
    local function AddRow(name, missing, raw)
        if not catalogRead then catalog, catalogRead = CurrentCatalog(), true end
        local icon = FamilyIcon(catalog, name)
        local row = AcquireRow()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 6, cy)
        row:SetWidth(width)
        row.icon:SetTexture(icon or NEUTRAL_ICON)
        row.icon:SetAlpha(icon and 1 or 0.5)
        row.label:SetText(name)
        row.status:SetText(T(missing and "journal.status.row_missing" or "journal.status.row_off_wishlist"))
        if missing then row.status:SetTextColor(1, 0.63, 0.25)
        else row.status:SetTextColor(0.62, 0.70, 0.80) end
        row.tipName = name
        row.tipStatus = T(missing and "journal.tooltip.row_missing" or "journal.tooltip.row_off_wishlist")
        row.tipRaw = raw ~= name and raw or nil
        row.tipIcon = not icon and T("journal.tooltip.row_icon_neutral") or nil
        cy = cy - ROW_H
    end

    -- One tome row from the supplied entry only: its icon, name and
    -- observation, or in the request section the request direction. Nothing
    -- here reads the catalog or the game; the tooltip has the full entry.
    local function AddTomeRow(t, index, requests)
        local row = AcquireTomeRow()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 14, cy)
        row:SetWidth(width - 8)
        local icon = t.icon
        if not ((type(icon) == "string" and icon ~= "") or type(icon) == "number") then icon = nil end
        row.icon:SetTexture(icon or NEUTRAL_ICON)
        row.icon:SetAlpha(icon and 1 or 0.5)
        row.background:SetVertexColor(0.55, 0.60, 0.68, index % 2 == 1 and 0.08 or 0.03)
        local request = requests and t.pending ~= nil
        row.label:SetText((TomeNames(t)))
        -- A request shows its reviewed badge; an observation shows the
        -- provider's status text as supplied, or Unknown without one.
        row.status:SetText(request and T(PENDING_BADGE[t.pending] or "journal.status.tome_request_pending")
            or (Filled(t.status) and (JournalShown(t.status))) or T("journal.value.tome_unknown"))
        -- Requests and clean observations take the palette accent; mixed,
        -- unknown, undiscovered and possibly stale readings are muted.
        local clean = t.stale ~= true and (t.observed == "disabled"
            or (t.observed == "enabled" and t.known == true))
        local role = (request or clean) and "accent" or "muted"
        if row.badgeRole ~= role and Nexus.Theme then
            row.badgeRole = role
            pcall(Nexus.Theme.StyleLabel, row.status, role)
        end
        row.tome, row.tomeRequest, row.tomeIcon = t, request, icon ~= nil
        cy = cy - ROW_H
    end

    -- Reviewed text is shown as resolved (plain): it never passes through the
    -- English rewrite of UserText.Message, which leaves these English bytes
    -- unchanged. Provider titles and lines below still go through it.
    AddLine(T("journal.heading.build_progress"), "GameFontNormal", nil, true)
    local intro = AddLine(T("journal.label.intro"), nil, nil, true)
    local hover = IntroHover()
    hover:ClearAllPoints()
    hover:SetPoint("TOPLEFT", intro, "TOPLEFT", 0, 0)
    hover:SetPoint("BOTTOMRIGHT", intro, "BOTTOMRIGHT", 0, 0)
    hover:Show()
    cy = cy - 4

    local sections = data and data.sections
    local hasSections = type(sections) == "table" and #sections > 0
    local s = hasSections and Summarize(sections) or {}
    local noTarget = s.noTarget == true
    local countsShown = false
    if hasSections then
        AddLine(Takeaway(s), "GameFontNormalSmall", nil, true)
        if s.known and #s.pending > 0 then AddLine(Gray(T("journal.body.family_coverage")), nil, nil, true) end
        if s.known then
            AddLine(s.title, nil, 8, true)
            -- A listed count is shown as supplied; an empty list is "none
            -- listed", never 0 (see journal.tooltip.off_wishlist_none). Each
            -- segment keeps its code-owned colour around the reviewed label
            -- (open/close slots) and the code-owned three-space separators.
            local OFF, REP, MISS = "|cff9eb2c8", "|cff7fd17f", "|cffffa040"
            local off = TF("journal.label.counts_off_unavailable", {open = OFF, close = "|r"})
            local offTip = T("journal.tooltip.off_wishlist_unavailable")
            if s.off and #s.off > 0 then
                off = TF("journal.label.counts_off_listed", {open = OFF, close = "|r", count = N(s.offCount)})
                offTip = T("journal.tooltip.off_wishlist_listed")
            elseif s.off then
                off = TF("journal.label.counts_off_none", {open = OFF, close = "|r"})
                offTip = T("journal.tooltip.off_wishlist_none")
            end
            local counts = AddLine(TF("journal.label.counts_represented", {open = REP, close = "|r",
                represented = N(s.represented), total = N(s.total)})
                .. "   " .. TF("journal.label.counts_missing", {open = MISS, close = "|r", count = N(s.missing)})
                .. "   " .. off, nil, 8, true)
            local hit = CountsHover()
            hit:ClearAllPoints()
            hit:SetPoint("TOPLEFT", counts, "TOPLEFT", 0, 0)
            hit:SetPoint("BOTTOMRIGHT", counts, "BOTTOMRIGHT", 0, 0)
            hit.offTip = offTip
            hit:Show()
            countsShown = true
        elseif s.targetLine then
            -- Unknown form or contradicted counts: the raw line, as supplied.
            AddLine(s.targetLine, nil, 8, true)
        end
    elseif failed then
        AddLine(Gray(T("journal.status.data_unreadable")), nil, nil, true)
    else
        AddLine(Gray(T("journal.status.no_data_yet")), nil, nil, true)
    end
    if countsHover and not countsShown then countsHover:Hide() end

    -- Only the families the provider names. The represented families are a
    -- count in the line above: the provider does not list them.
    if s.known and #s.pending > 0 then
        cy = cy - 4
        AddLine(TF("journal.heading.missing_count", {count = N(#s.pending)}), "GameFontNormalSmall", nil, true)
        for i = 1, #s.pending do AddRow(s.pending[i], true, s.pending[i]) end
    end
    if s.known and s.off and #s.off > 0 then
        cy = cy - 4
        AddLine(TF("journal.heading.off_wishlist_count", {count = N(#s.off)}), "GameFontNormalSmall", nil, true)
        for i = 1, #s.off do AddRow(SplitOffLine(s.off[i]), false, s.off[i]) end
    end
    local estimate = s.targetLine and EstimateLine(sections)
    if estimate then
        cy = cy - 4
        AddLine("|cff8a8a8a" .. estimate .. "|r", nil, nil, true)
    end
    cy = cy - 4

    -- Show details keeps the full notes, every provider section, the estimate
    -- and the version; Assign in My Builds closes this page onto the Journal's
    -- own assignment controls, exactly like a second click on the tab.
    local toggle = PageButton("details")
    toggle:ClearAllPoints()
    toggle:SetPoint("TOPLEFT", child, "TOPLEFT", 6, cy)
    toggle:SetText(T(detailsShown and "journal.button.hide_details" or "journal.button.show_details"))
    toggle:Show()
    local builds = PageButton("builds")
    if noTarget then
        builds:ClearAllPoints()
        builds:SetPoint("TOPLEFT", child, "TOPLEFT", 124, cy)
        builds:Show()
    else
        builds:Hide()
    end
    -- Help joins the same row after the shown buttons; where the row is too
    -- narrow for it (content width + 12, at least 292), it takes a row of its
    -- own below, so it never covers another button or line.
    local help = PageButton("help")
    local helpX, helpY = noTarget and 280 or 124, cy
    if helpX + 56 > width + 6 then
        helpX, helpY = 6, cy - 26
        cy = cy - 26
    end
    help:ClearAllPoints()
    help:SetPoint("TOPLEFT", child, "TOPLEFT", helpX, helpY)
    help:Show()
    -- Reference follows Help on the same terms.
    local reference = PageButton("reference")
    local refX, refY = helpX + 60, helpY
    if refX + 80 > width + 6 then
        refX, refY = 6, helpY - 26
        cy = cy - 26
    end
    reference:ClearAllPoints()
    reference:SetPoint("TOPLEFT", child, "TOPLEFT", refX, refY)
    reference:Show()
    cy = cy - 30

    if detailsShown then
        AddLine(T("journal.heading.about_page"), "GameFontNormalSmall", nil, true)
        AddLine(T("journal.body.purpose"), nil, 8, true)
        AddLine(T("journal.body.compare_active"), nil, 8, true)
        AddLine(Gray(T("journal.body.set_in_my_builds")), nil, 8, true)
        AddLine(T("journal.body.family_coverage"), nil, 8, true)
        AddLine(T("journal.body.change_in_my_builds"), nil, 8, true)
        cy = cy - 6
        if not hasSections then
            AddLine(Gray(T(failed and "journal.status.data_unreadable_no_sections"
                or "journal.status.no_sections")), nil, nil, true)
        end
        if hasSections then
            for i = 1, #sections do
                local sec = sections[i]
                if type(sec) == "table" then
                    -- Classified above from the raw title; said here.
                    local title, titled = JournalShown(tostring(sec.title or ""))
                    AddLine(title, "GameFontNormalSmall", nil, titled)
                    -- Structured tome rows stand in for the same entries'
                    -- text lines; every other section keeps its lines.
                    local tomes = TomeRows(sec.tomeRows)
                    if tomes then
                        local requests = sec.title == TOME_REQUESTS
                        for j = 1, #tomes do AddTomeRow(tomes[j], j, requests) end
                    elseif s.known and sec == s.pendingSection and #s.pending > 0 then
                        -- This exact section validated the summary, so its
                        -- families are already the Missing rows above; they
                        -- are not listed twice. Any other section, or a
                        -- Pending list the summary did not validate, keeps
                        -- its lines as received. The data is not changed.
                        AddLine(Gray(TF("journal.status.listed_above", {count = N(#s.pending)})), nil, 8, true)
                    else
                        local lines = sec.lines
                        if type(lines) == "table" then
                            for j = 1, #lines do
                                local line, said = JournalShown(tostring(lines[j] or ""))
                                AddLine(line, nil, 8, said)
                            end
                        end
                    end
                    cy = cy - 4
                end
            end
        end

        if data and data.version ~= nil then
            cy = cy - 2
            AddLine("|cff8a8a8a" .. tostring(data.version) .. "|r")
        end
    end

    for i = linesUsed + 1, #linePool do linePool[i]:Hide() end
    for i = rowsUsed + 1, #rowPool do rowPool[i]:Hide() end
    for i = tomesUsed + 1, #tomePool do
        tomePool[i]:Hide()
        tomePool[i].tome = nil
    end
    child:SetWidth(width + 12)
    child:SetHeight(-cy + 8)
end

function M.Refresh()
    if not (installed and panel and panel:IsShown()) then return end
    -- Consumed first: a change marked during this refresh is kept for the next.
    refreshPending = false
    pcall(DoRefresh)
end

-- A semantic change (GameAdapter) marks the page. Only a bit: no provider,
-- adapter or service read and no frame work here. The association scanner
-- refreshes a visible page with its details open on its next beat; a hidden
-- or collapsed page reads nothing until its normal refresh on opening. A
-- newer client mirror shown this way is still no server acknowledgment.
function M.Invalidate()
    refreshPending = true
end


local function MenuOpen(items, anchor)
    if type(EasyMenu) ~= "function" then return end
    M._menuFrame = M._menuFrame or CreateFrame("Frame", "NexusJournalAssociationMenu", UIParent, "UIDropDownMenuTemplate")
    -- Theme.OpenMenu: the same EasyMenu call, with the shared list opaque
    -- while it shows this Nexus menu.
    local theme = Nexus.Theme
    if theme and type(theme.OpenMenu) == "function" then
        theme.OpenMenu(items, M._menuFrame, anchor, 0, 0)
    else
        EasyMenu(items, M._menuFrame, anchor, 0, 0, "MENU")
    end
end

local function FrameText(frame)
    local out = {}
    local function Walk(f, depth)
        if not f or depth > 5 then return end
        if f.GetText then
            local ok, v = pcall(f.GetText, f)
            if ok and type(v) == "string" and v ~= "" then out[#out + 1] = v end
        end
        if f.GetRegions then
            local regs = { f:GetRegions() }
            for i = 1, #regs do
                local r = regs[i]
                if r and r.GetText then
                    local ok, v = pcall(r.GetText, r)
                    if ok and type(v) == "string" and v ~= "" then out[#out + 1] = v end
                end
            end
        end
        if f.GetChildren then
            local kids = { f:GetChildren() }
            for i = 1, #kids do Walk(kids[i], depth + 1) end
        end
    end
    Walk(frame, 0)
    return table.concat(out, "\n")
end

local function NormalizedText(frame)
    return FrameText(frame):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function HasVisibleText(root, wanted)
    local found = false
    local function Walk(f, depth)
        if found or not f or depth > 16 then return end
        local shown = true
        if f.IsShown then
            local ok, v = pcall(f.IsShown, f)
            if ok then shown = v and true or false end
        end
        if shown then
            if f.GetText then
                local ok, text = pcall(f.GetText, f)
                if ok and type(text) == "string" then
                    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                    if text:find(wanted, 1, true) then found = true return end
                end
            end
            if f.GetRegions then
                local regs = { f:GetRegions() }
                for i = 1, #regs do
                    local r = regs[i]
                    if r and r.GetText then
                        local ok, text = pcall(r.GetText, r)
                        if ok and type(text) == "string" then
                            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                            if text:find(wanted, 1, true) then found = true return end
                        end
                    end
                end
            end
            -- Nothing inside a hidden frame is visible, even a child that is
            -- itself shown (a journal page hidden by another tab).
            if f.GetChildren then
                local kids = { f:GetChildren() }
                for i = 1, #kids do Walk(kids[i], depth + 1) end
            end
        end
    end
    Walk(root, 0)
    return found
end

local function IsLoadoutsVisible(journal)
    if not journal or not journal.IsShown or not journal:IsShown() then return false end
    -- The stock page always exposes this section title. This is intentionally
    -- independent of card frame names, dimensions, verification flags, and
    -- Project Ebonhold client revisions.
    if HasVisibleText(journal, "Your loadouts") then return true end
    if HasVisibleText(journal, "Empty slot 2") or HasVisibleText(journal, "Empty slot 3") then return true end
    return false
end

local function FindLoadoutsTab(journal)
    local function IsWantedButton(f)
        if not f or not f.GetObjectType or f:GetObjectType() ~= "Button" then return false end
        local txt = NormalizedText(f)
        for line in txt:gmatch("[^\n]+") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line == "Loadouts" then return true end
        end
        return false
    end

    -- Prefer the stock named tabs when present. On the current client the
    -- Loadouts button is Tab3, but validate the visible label rather than
    -- assuming the index.
    for i = 1, 12 do
        local t = _G["ProjectEbonholdEchoJournalTab" .. tostring(i)]
        if IsWantedButton(t) then return t end
    end

    local exact
    local function Walk(f, depth)
        if exact or not f or depth > 18 then return end
        if IsWantedButton(f) then exact = f return end
        if f.GetChildren then
            local kids = { f:GetChildren() }
            for i = 1, #kids do Walk(kids[i], depth + 1) end
        end
    end
    Walk(journal, 0)
    if not exact and UIParent and UIParent ~= journal then Walk(UIParent, 0) end
    return exact
end

local function ShortName(name, maxLen)
    name = tostring(name or "")
    maxLen = tonumber(maxLen) or 28
    if #name <= maxLen then return name end
    -- Cut on a UTF-8 character boundary: translated labels and player names
    -- are UTF-8, so a byte count alone could end inside a character. ASCII
    -- text is cut exactly as before.
    local cut = name:sub(1, maxLen - 3)
    local lead = cut:find("[\192-\255][\128-\191]*$")
    if lead then
        local first = cut:byte(lead)
        local width = first >= 240 and 4 or first >= 224 and 3 or 2
        if #cut - lead + 1 < width then cut = cut:sub(1, lead - 1) end
    end
    return cut .. "..."
end

-- The strip (360 x 56, backdrop inset 3) and its label's side column: 145 px
-- wide at (10, -9), left of the selector (x 160..329) and of New Wishlist
-- (x 203..353), down to the strip's 5 px bottom padding: 56 - 9 - 5 = 42 px.
local STRIP_H = 56
local STRIP_LABEL_X, STRIP_LABEL_Y = 10, -9
local STRIP_LABEL_W, STRIP_LABEL_MAX_H = 145, 42
-- Scales tried, largest first. 0.75 is the hard floor: the lowest runtime
-- font scale LayoutMetrics itself accepts. Only the label's holder is ever
-- scaled (the strip stays at scale 1) and its font object is never changed,
-- so the holder scale is the label's effective presentation scale.
local STRIP_LABEL_SCALES = { 1, 0.9, 0.8, 0.75 }
-- Stacked layout, for a state text the side column cannot show at any scale
-- down to the floor: the label takes a band across the strip's inner width
-- (x 10..350) above the unchanged control block, which moves down by the
-- band. The band is at most 52 px tall plus a 6 px gap, so the strip is at
-- most 56 + 58 = 114 px tall. Its width, TOP anchor and controls' sizes and
-- relative places do not change.
local STRIP_STACK_W, STRIP_STACK_MAX_H, STRIP_STACK_GAP = 340, 52, 6

-- The label lives in a plain child frame of the strip (no name, no mouse,
-- no scripts) at the label's own place. A scaled frame's offsets and size
-- are in its own units, so they are divided by the scale: on the strip the
-- holder's top left is always (10, -9) and its box width x height strip px.
-- Scale 1 with the side column is the label's original place and size.
local function PlaceStripLabel(host, scale, width, height)
    local holder = host.labelHolder
    holder:SetScale(scale)
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", STRIP_LABEL_X / scale, STRIP_LABEL_Y / scale)
    holder:SetSize(width / scale, height / scale)
end

-- The strip's own layout for a label band of `band` strip px above the
-- controls (0: the original layout). Only Nexus-owned frames move: the strip
-- grows downward from its unchanged TOP anchor, the selector and Design keep
-- their TOPRIGHT offsets shifted down by the band, New Wishlist keeps its
-- BOTTOMRIGHT offset. Nothing of the game's own UI is touched.
local function StripLayout(host, band)
    band = band or 0
    if host.stackBand == band then return end
    host.stackBand = band
    host:SetHeight(STRIP_H + band)
    host.selector:ClearAllPoints()
    host.selector:SetPoint("TOPRIGHT", -31, -5 - band)
    host.design:ClearAllPoints()
    host.design:SetPoint("TOPRIGHT", -7, -6 - band)
end

-- The label in a box of width x maxHeight strip px: for each scale in turn,
-- WrapHeight at (width / s) x (maxHeight / s) label units. Returns the first
-- scale whose wrapped height is not capped and that height (label units);
-- false and the capped height when even the floor is capped (the label is
-- left at the floor); nil when the helper failed.
local function FitStripLabel(host, width, maxHeight, wrap)
    local height
    for i = 1, #STRIP_LABEL_SCALES do
        local scale = STRIP_LABEL_SCALES[i]
        PlaceStripLabel(host, scale, width, maxHeight)
        local ok, h, capped = pcall(wrap, host.label, width / scale, 12, maxHeight / scale)
        if not ok then return nil end
        height = h
        if not capped then
            host.labelHolder:SetHeight(h)
            return scale, h
        end
    end
    host.labelHolder:SetHeight(height)
    return false, height
end

-- A code-owned state label (the no-selection text) is shown whole and
-- visible: its qualifier is its meaning, so it is never cut to a byte count
-- or capped out of sight. It wraps and takes the height its text needs,
-- measured by the client (LayoutMetrics.WrapHeight: height 0 at a fixed
-- width, then GetStringHeight; its conservative model stands in without a
-- measurement), at least one 12 px line. First the side column is tried,
-- largest scale first down to the floor. When none fits (WrapHeight reports
-- it capped), the stacked band is tried the same way and the strip takes its
-- stacked layout. Returns true when the complete text fits; host.labelFits
-- says the same. Only past the floor of the band is the text capped at the
-- band's bound (a text no required case reaches); without the helper the side
-- column is used at full size. Display only: nothing is written or sent.
local function WrapStripStateLabel(host)
    local label = host.label
    label:SetJustifyV("TOP")
    local metrics = Nexus.LayoutMetrics
    local wrap = metrics and type(metrics.WrapHeight) == "function" and metrics.WrapHeight
    if wrap then
        StripLayout(host, 0)
        local scale = FitStripLabel(host, STRIP_LABEL_W, STRIP_LABEL_MAX_H, wrap)
        if scale then host.labelFits = true return true end
        if scale == false then
            local stackScale, height = FitStripLabel(host, STRIP_STACK_W, STRIP_STACK_MAX_H, wrap)
            if stackScale ~= nil then
                local shown = stackScale or STRIP_LABEL_SCALES[#STRIP_LABEL_SCALES]
                StripLayout(host, height * shown + STRIP_STACK_GAP)
                host.labelFits = stackScale and true or false
                return host.labelFits
            end
        end
    end
    StripLayout(host, 0)
    PlaceStripLabel(host, 1, STRIP_LABEL_W, STRIP_LABEL_MAX_H)
    label:SetWidth(STRIP_LABEL_W)
    label:SetHeight(STRIP_LABEL_MAX_H)
    host.labelFits = false
    return false
end


-- The selector sits in the Journal header near the screen top, so its tall
-- ANCHOR_TOP tooltip does not fit above it and the screen clamp moves it down
-- over the picker area. The open picker (TOOLTIP strata, higher level) then
-- covers the warning. While the picker is open, place the tooltip beside the
-- picker instead: right when there is room, else on the side with more room.
-- GameTooltip strata, level and parent are not changed.
local function ShowSelectorTooltip(selector)
    local besidePicker = wishlistPicker and wishlistPicker:IsShown()
    GameTooltip:SetOwner(selector, besidePicker and "ANCHOR_NONE" or "ANCHOR_TOP")
    GameTooltip:AddLine(T("journal.tooltip.selector_heading"), 0.35, 0.8, 1)
    GameTooltip:AddLine(associationPanel and associationPanel.emptySlot and EmptySlotSelector()
        or (T("journal.tooltip.selector_assigns") .. " " .. AssignNote()), 0.82, 0.82, 0.82, true)
    GameTooltip:AddLine(T("journal.tooltip.auto_replace_warning"), 1, 0.82, 0.25, true)
    GameTooltip:AddLine(T("journal.tooltip.auto_replace_orbs"), 1, 0.82, 0.25, true)
    GameTooltip:Show()
    if not besidePicker then return end
    local gap = 4
    local left, right = wishlistPicker:GetLeft(), wishlistPicker:GetRight()
    if not (left and right) then
        -- Picker layout not resolved yet (it was just shown). Its TOPLEFT is
        -- the selector's BOTTOMLEFT, and the hovered selector is laid out.
        local selectorLeft = selector:GetLeft()
        if selectorLeft then
            left = selectorLeft * (selector:GetEffectiveScale() or 1) / (wishlistPicker:GetEffectiveScale() or 1)
            right = left + (wishlistPicker:GetWidth() or 0)
        end
    end
    local screenRight = UIParent:GetRight() or UIParent:GetWidth() or 0
    -- Tooltip width in UIParent units (the picker is a scale-1 UIParent child).
    local width = (GameTooltip:GetWidth() or 0) * (GameTooltip:GetEffectiveScale() or 1)
        / (UIParent:GetEffectiveScale() or 1)
    local roomRight = right and (screenRight - right) or math.huge
    local roomLeft = left or 0
    GameTooltip:ClearAllPoints()
    if roomRight < width + gap and roomLeft > roomRight then
        GameTooltip:SetPoint("TOPRIGHT", wishlistPicker, "TOPLEFT", -gap, 0)
    else
        GameTooltip:SetPoint("TOPLEFT", wishlistPicker, "TOPRIGHT", gap, 0)
    end
end

-- The picker opens and closes on a selector click while the mouse stays on
-- the selector: place its shown tooltip again for the new picker state.
local function RefreshSelectorTooltip()
    local selector = associationPanel and associationPanel.selector
    if selector and selector:IsVisible() and GameTooltip:IsShown()
        and GameTooltip:GetOwner() == selector then
        ShowSelectorTooltip(selector)
    end
end

local function EnsureAssociationPanel(journal)
    if not journal then return nil end
    if not associationPanel then
        associationPanel = CreateFrame("Frame", "NexusLoadoutAssociationPanel", journal)
        associationPanel:SetSize(360, 56)
        associationPanel:SetFrameStrata("DIALOG")
        associationPanel:SetFrameLevel((journal:GetFrameLevel() or 0) + 24)
        associationPanel:EnableMouse(true)
        associationPanel:SetClampedToScreen(true)
        if associationPanel.SetBackdrop then
            associationPanel:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 11,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            associationPanel:SetBackdropColor(0.018, 0.024, 0.032, 0.97)
            associationPanel:SetBackdropBorderColor(0.28, 0.58, 0.76, 0.95)
        end

        -- The label's holder (PlaceStripLabel): at scale 1 the label is at
        -- its original (10, -9) with its original 145 px width.
        associationPanel.labelHolder = CreateFrame("Frame", nil, associationPanel)
        PlaceStripLabel(associationPanel, 1, STRIP_LABEL_W, STRIP_LABEL_MAX_H)
        associationPanel.label = associationPanel.labelHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        associationPanel.label:SetPoint("TOPLEFT", 0, 0)
        associationPanel.label:SetWidth(STRIP_LABEL_W)
        associationPanel.label:SetJustifyH("LEFT")
        associationPanel.label:SetTextColor(0.72, 0.72, 0.72)

        associationPanel.selector = CreateFrame("Button", "NexusActiveWishlistSelector", associationPanel)
        associationPanel.selector:SetSize(169, 21)
        associationPanel.selector:SetPoint("TOPRIGHT", -31, -5)
        associationPanel.selector:RegisterForClicks("LeftButtonUp")
        if associationPanel.selector.SetBackdrop then
            associationPanel.selector:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false, edgeSize = 9,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            associationPanel.selector:SetBackdropColor(0.035, 0.045, 0.06, 0.99)
            associationPanel.selector:SetBackdropBorderColor(0.25, 0.31, 0.38, 0.95)
        end
        associationPanel.selector.text = associationPanel.selector:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        associationPanel.selector.text:SetPoint("LEFT", 9, 0)
        associationPanel.selector.text:SetPoint("RIGHT", -25, 0)
        associationPanel.selector.text:SetJustifyH("LEFT")
        -- One line inside the 21 px selector; the picker lists complete names.
        if Nexus.LayoutMetrics then Nexus.LayoutMetrics.OneLineLabel(associationPanel.selector.text, nil, 21) end
        associationPanel.selector.arrow = associationPanel.selector:CreateTexture(nil, "ARTWORK")
        associationPanel.selector.arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
        associationPanel.selector.arrow:SetSize(16, 16)
        associationPanel.selector.arrow:SetPoint("RIGHT", -5, 0)

        associationPanel.design = CreateFrame("Button", "NexusAssociatedWishlistDesignButton", associationPanel)
        associationPanel.design:SetSize(20, 20)
        associationPanel.design:SetPoint("TOPRIGHT", -7, -6)
        associationPanel.design:RegisterForClicks("LeftButtonUp")
        associationPanel.design.icon = associationPanel.design:CreateTexture(nil, "ARTWORK")
        associationPanel.design.icon:SetAllPoints()
        associationPanel.design.icon:SetTexture("Interface\\Buttons\\WHITE8X8")
        associationPanel.design.icon:SetVertexColor(0.08, 0.11, 0.15, 0.98)
        associationPanel.design.glyph = associationPanel.design:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        associationPanel.design.glyph:SetPoint("CENTER", 0, 1)
        associationPanel.design.glyph:SetText("...")
        associationPanel.design.glyph:SetTextColor(1, 0.82, 0.2)
        associationPanel.design:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        associationPanel.newWishlist = CreateFrame("Button", nil, associationPanel, "UIPanelButtonTemplate")
        associationPanel.newWishlist:SetSize(150, 19)
        associationPanel.newWishlist:SetPoint("BOTTOMRIGHT", -7, 5)
        associationPanel.newWishlist:SetText(T("journal.button.new_wishlist"))
        associationPanel.newWishlist:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(T("journal.button.new_wishlist"), 0.35, 0.8, 1)
            GameTooltip:AddLine(T("journal.tooltip.new_wishlist"), 0.82, 0.82, 0.82, true)
            GameTooltip:Show()
        end)
        associationPanel.newWishlist:SetScript("OnLeave", function() GameTooltip:Hide() end)

        associationPanel.design:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if associationPanel and associationPanel.emptySlot then
                GameTooltip:AddLine(T("journal.tooltip.edit_first_run_heading"), 0.35, 0.8, 1)
                GameTooltip:AddLine(T("journal.tooltip.edit_first_run"), 0.82, 0.82, 0.82, true)
            else
                GameTooltip:AddLine(T("journal.tooltip.edit_assigned_heading"), 0.35, 0.8, 1)
                GameTooltip:AddLine(T("journal.tooltip.edit_assigned"), 0.82, 0.82, 0.82, true)
            end
            GameTooltip:Show()
        end)
        associationPanel.design:SetScript("OnLeave", function() GameTooltip:Hide() end)
        associationPanel.selector:SetScript("OnEnter", function(self)
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.42, 0.72, 0.95, 1) end
            ShowSelectorTooltip(self)
        end)
        associationPanel.selector:SetScript("OnLeave", function(self)
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.25, 0.31, 0.38, 0.95) end
            GameTooltip:Hide()
        end)

        associationPanel:SetScript("OnHide", function()
            HideWishlistPicker()
            if M._menuFrame then M._menuFrame:Hide() end
        end)
    end

    associationPanel:SetParent(journal)
    associationPanel:ClearAllPoints()
    -- Keep the control centered in the unused top header strip. This avoids
    -- the Echo row, search field, and the server loadout dropdown/menu.
    associationPanel:SetPoint("TOP", journal, "TOP", 85, 2)
    return associationPanel
end

local function HideRowButtons()
    if associationPanel then associationPanel:Hide() end
end

HideWishlistPicker = function()
    if wishlistPicker and wishlistPicker:IsShown() then
        wishlistPicker:Hide()
        RefreshSelectorTooltip()
    end
end

-- Display only: which picker row is the resolved assignment. The resolver
-- copies the stored assignmentId onto the live server row it found, but the
-- picker lists fresh live rows that carry none. So: equal assignmentIds on both
-- sides decide; a row stamped with another assignment is never selected;
-- otherwise the current resolved server slot and content key must both match.
-- Equal contents in another slot, or a name, identify nothing.
local function IsAssignedPickerRow(linked, c)
    if type(linked) ~= "table" or type(c) ~= "table" then return false end
    if linked.assignmentId and c.assignmentId then
        return linked.assignmentId == c.assignmentId
    end
    if c.assignmentId then return false end
    local slot = tonumber(linked.slot)
    return slot ~= nil and slot == tonumber(c.slot)
        and type(linked.key) == "string" and linked.key ~= "" and linked.key == c.key
end

-- `emptySlot` is the empty-Saved-Build context `active` and `loadoutName` were taken
-- in. The picker's tooltips use it, not the live Journal context, so their words
-- always describe the target its click handlers act on while it stays open.
-- `loadoutName` is the raw value handed on to the editor unchanged;
-- `loadoutLabel` is what the picker shows for it (the same name, or the
-- reviewed text for a code-owned placeholder such as "Saved Build N").
local function ShowWishlistPicker(anchor, wishes, linked, active, loadoutName, A, emptySlot, loadoutLabel)
    loadoutLabel = loadoutLabel or tostring(loadoutName or "")
    if not wishlistPicker then
        wishlistPicker = CreateFrame("Frame", "NexusWishlistOnlyPicker", UIParent)
        wishlistPicker:SetFrameStrata("TOOLTIP")
        -- Native high-level rendering put this opaque parent above Unassign.
        -- TOOLTIP supplies the overlay order; keep its child levels low.
        wishlistPicker:SetFrameLevel(50)
        wishlistPicker:SetToplevel(true)
        wishlistPicker:SetClampedToScreen(true)
        wishlistPicker:EnableMouse(true)
        if wishlistPicker.SetBackdrop then
            wishlistPicker:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=12, insets={left=3,right=3,top=3,bottom=3} })
            wishlistPicker:SetBackdropColor(0.02,0.025,0.035,0.99)
            wishlistPicker:SetBackdropBorderColor(0.25,0.55,0.75,1)
        end
        wishlistPicker.bg = wishlistPicker:CreateTexture(nil, "BACKGROUND")
        wishlistPicker.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        wishlistPicker.bg:SetAllPoints()
        wishlistPicker.bg:SetVertexColor(0.02, 0.025, 0.035, 0.99)
        wishlistPicker.border = CreateFrame("Frame", nil, wishlistPicker)
        wishlistPicker.border:SetAllPoints()
        wishlistPicker.border:SetFrameLevel(wishlistPicker:GetFrameLevel() + 1)
        wishlistPicker.title = wishlistPicker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        wishlistPicker.title:SetPoint("TOPLEFT", 10, -8)
        wishlistPicker.title:SetText(T("journal.title.picker_wishlists"))
    end
    -- The title names the target this picker's clicks act on (the context
    -- captured with it), not only that these are Wishlists.
    local shortTarget = ShortName(loadoutLabel, 24)
    wishlistPicker.title:SetText(emptySlot and T("journal.title.picker_empty_refused")
        or ((tonumber(active) or 0) < 1 and T("journal.title.picker_first_run"))
        or TF("journal.title.picker_assign_to", {name = shortTarget}, "Assign to: " .. shortTarget))
    for i=1,#wishlistPickerRows do wishlistPickerRows[i]:Hide() end
    if wishlistPicker.emptyRow then wishlistPicker.emptyRow:Hide() end
    if wishlistPicker.clearRow then wishlistPicker.clearRow:Hide() end
    wishlistPicker:ClearAllPoints()
    wishlistPicker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    -- The selector already names the selected Wishlist, so the list offers
    -- only the others. Only that one identity (IsAssignedPickerRow) is left
    -- out: a row with the same name or contents is another Wishlist and stays.
    -- With no name on the selector the selection stays listed and marked.
    local shown = wishes
    if linked and tostring(linked.name or "") ~= "" then
        shown = {}
        for i=1,#wishes do
            if not IsAssignedPickerRow(linked, wishes[i]) then shown[#shown+1] = wishes[i] end
        end
    end
    local width, rowH = 245, 24
    wishlistPicker:SetWidth(width)
    local count = math.max(1, #shown)
    wishlistPicker:SetHeight(26 + count * rowH + (linked and 24 or 0) + 6)

    if #shown == 0 then
        local row = wishlistPicker.emptyRow
        if not row then
            row = wishlistPicker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            wishlistPicker.emptyRow = row
        end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 10, -28)
        row:SetText(T(#wishes == 0 and "journal.status.picker_none_found" or "journal.status.picker_no_others"))
        row:Show()
    else
        for i=1,#shown do
            local c = shown[i]
            local cSlot = c.slot
            local cName = c.name
            local cKey = c.key
            local row = wishlistPickerRows[i]
            if not row or not row.nameButton then
                row = CreateFrame("Frame", nil, wishlistPicker)
                row:SetFrameLevel(wishlistPicker:GetFrameLevel() + 2)
                row:EnableMouse(true)
                row:SetSize(width-12, rowH)
                row.nameButton = CreateFrame("Button", nil, row)
                row.nameButton:SetFrameLevel(row:GetFrameLevel() + 1)
                row.nameButton:RegisterForClicks("LeftButtonUp")
                row.nameButton:EnableMouse(true)
                row.nameButton:SetPoint("LEFT", 0, 0); row.nameButton:SetPoint("RIGHT", -28, 0); row.nameButton:SetHeight(rowH-2)
                row.nameButton.text = row.nameButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.nameButton.text:SetPoint("LEFT", 6, 0); row.nameButton.text:SetPoint("RIGHT", -4, 0); row.nameButton.text:SetJustifyH("LEFT")
                -- One line per row; a shortened name is complete in the row tooltip.
                if Nexus.LayoutMetrics then Nexus.LayoutMetrics.OneLineLabel(row.nameButton.text, nil, rowH-2) end
                row.nameButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                row.gear = CreateFrame("Button", nil, row)
                row.gear:SetFrameLevel(row:GetFrameLevel() + 2)
                row.gear:RegisterForClicks("LeftButtonUp")
                row.gear:EnableMouse(true)
                row.gear:SetSize(20,20); row.gear:SetPoint("RIGHT", -2, 0)
                row.gear.icon = row.gear:CreateTexture(nil, "ARTWORK"); row.gear.icon:SetAllPoints(); row.gear.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
                row.gear.glyph = row.gear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.gear.glyph:SetPoint("CENTER", 0, 1)
                row.gear.glyph:SetText("...")
                row.gear.glyph:SetTextColor(1, 0.82, 0.2)
                row.gear:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
                row.gear:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(T("journal.tooltip.picker_edit_wishlist"), .35,.8,1); GameTooltip:Show()
                end)
                row.gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
                wishlistPickerRows[i] = row
            end
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 6, -24 - (i-1)*rowH)
            local selected = IsAssignedPickerRow(linked, c)
            local editor=Nexus.WishlistEditor
            -- The editor's hint is the editor's own text; only the fallback is ours.
            local hint=editor and editor.UnresolvedRoleHint and editor.UnresolvedRoleHint()
                or T("journal.label.picker_role_hint")
            local evidenceSuffix = c.lockEvidenceStatus == "unavailable"
                and ("  |cffff9040("..hint..")|r") or ""
            -- The marker is display only: `selected` is the row's identity
            -- (IsAssignedPickerRow), never this text.
            row.nameButton.text:SetText((selected and ("|cff55ff55" .. T("journal.label.selected_marker") .. " |r") or "")
                .. ((cName ~= "" and cName) or T("journal.label.unnamed_wishlist"))
                .. evidenceSuffix)
            local cEchoes = c.echoes
            local cSnapshot = {
                slot=cSlot, name=cName, key=cKey,
                lockEvidenceVersion=c.lockEvidenceVersion,
                lockEvidenceStatus=c.lockEvidenceStatus,
                evidenceSource=c.evidenceSource,
                assignmentId=c.assignmentId,designTargets=c.designTargets,
                echoes={},
            }
            for echoIndex = 1, #(cEchoes or {}) do
                local echo = cEchoes[echoIndex]
                cSnapshot.echoes[echoIndex] = {
                    spellId=echo.spellId, quality=echo.quality,
                    stacks=echo.stacks, locked=echo.locked,
                }
            end
            local function AssociateWishlistOnly()
                local numbered = tonumber(active) and tonumber(active) > 0
                local shownName = M.SafeName(cName, T("journal.label.unnamed_wishlist"))
                -- The target as shown in the question and the receipt (display
                -- only; the assignment itself uses `active` and the snapshot).
                local buildName = M.SafeName(loadoutLabel, tostring(active))
                local target = numbered and TF("journal.label.target_saved_build", {name = buildName},
                    "Saved Build '" .. buildName .. "'") or T("journal.label.target_first_run")
                -- The guide request this operation began under, taken now, before
                -- any confirmation or role choice, and carried to every result.
                local origin = GuideOrigin(numbered, active, cSnapshot)
                if cSnapshot.lockEvidenceStatus=="unavailable" and Nexus.WishlistEditor
                    and Nexus.WishlistEditor.ResolveAndAssignWishlist then
                    -- A Wishlist without lock evidence: its role choice (the
                    -- current-lock default or the role picker) and the
                    -- assignment it ends in wait for the same Auto-ON
                    -- confirmation; Cancel writes neither.
                    local asked, why = M.AssignWithConsent(shownName, target, numbered and not emptySlot, function()
                        HideWishlistPicker()
                        Nexus.WishlistEditor.ResolveAndAssignWishlist(cSnapshot,tonumber(active) or 0,origin)
                    end)
                    if asked == nil then GuideAssign(numbered, active, false, why, cSnapshot, origin) end
                    return
                end
                -- The captured target, candidate and empty-slot refusal as
                -- before; Auto selected asks first (M.AssignWithConsent).
                local asked, why = M.AssignWithConsent(shownName, target, numbered and not emptySlot, function()
                    local ok, err
                    if numbered then
                        ok, err = A.SetLoadoutWishlist(active, cSlot, cSnapshot)
                    elseif type(A.SetFirstRunWishlist) == "function" then
                        ok, err = A.SetFirstRunWishlist(cSlot, cSnapshot)
                    else
                        ok, err = false, FIRST_RUN_UNAVAILABLE
                    end
                    if not ok then
                        -- The guide records the raw reason; chat shows it: the
                        -- adapter's reason through its key when known (as
                        -- supplied otherwise), or a reviewed key.
                        GuideAssign(numbered, active, false, err, cSnapshot, origin)
                        local shownErr = err == FIRST_RUN_UNAVAILABLE and T("journal.chat.first_run_unavailable")
                            or err and tostring(Nexus.UserText.Recognized(tostring(err))) or T("journal.chat.select_failed")
                        print("|cffff6060Nexus:|r " .. shownErr)
                        return
                    end
                    GuideAssign(numbered, active, true, nil, cSnapshot, origin)
                    HideWishlistPicker()
                    M.RefreshAssociations()
                    if Nexus.Panel and Nexus.Panel.Refresh then pcall(Nexus.Panel.Refresh) end
                    -- A visible confirmation of what changed, and only that.
                    print("|cff4dff80Nexus:|r " .. TF("journal.chat.assigned", {wishlist = shownName, target = target},
                        "'" .. shownName .. "' is now the Wishlist for " .. target
                        .. ". No Saved Build was changed or activated."))
                end)
                if asked == nil then GuideAssign(numbered, active, false, why, cSnapshot, origin) end
            end
            local function OpenWishlistEditorOnly()
                HideWishlistPicker()
                local editor = Nexus and Nexus.WishlistEditor
                if editor and type(editor.OpenForWishlist) == "function" then
                    editor.OpenForWishlist({
                        slot = cSlot,
                        name = cName,
                        key = cKey,
                        echoes = cEchoes,
                        lockEvidenceVersion = c.lockEvidenceVersion,
                        lockEvidenceStatus = c.lockEvidenceStatus,
                        evidenceSource=c.evidenceSource,
                        assignmentId=c.assignmentId,designTargets=c.designTargets,
                        loadoutName = loadoutName,
                    }, (tonumber(active) and tonumber(active) > 0) and active or nil)
                else
                    print("|cffff6060Nexus:|r " .. T("journal.chat.editor_unavailable"))
                end
            end
            row.nameButton:SetScript("OnClick", AssociateWishlistOnly)
            row.nameButton:SetScript("OnEnter", function(self)
                -- Anchor at the row edge: the name button ends 28 px inside
                -- the picker, which shares the TOOLTIP strata.
                GameTooltip:SetOwner(self:GetParent() or self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(T("journal.tooltip.picker_row_heading"), .35, .8, 1)
                GameTooltip:AddLine(TF("journal.tooltip.picker_row_target", {name = loadoutLabel},
                    "Target: " .. loadoutLabel), 1, 1, 1, true)
                GameTooltip:AddLine(emptySlot and EmptySlotAssign()
                    or (T("journal.tooltip.picker_row_sets") .. " " .. AssignNote()),
                    .82, .82, .82, true)
                GameTooltip:AddLine(T("journal.tooltip.auto_replace_warning"), 1, .82, .25, true)
                GameTooltip:AddLine(T("journal.tooltip.auto_replace_orbs"), 1, .82, .25, true)
                if Nexus.LayoutMetrics and Nexus.LayoutMetrics.Shortened(self.text) then
                    GameTooltip:AddLine(self.text:GetText(), 1, 1, 1, true)
                end
                GameTooltip:Show()
            end)
            row.nameButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.gear:SetScript("OnClick", OpenWishlistEditorOnly)
            row:Show()
        end
    end

    if linked then
        local row = wishlistPicker.clearRow
        if not row then
            row = CreateFrame("Button", nil, wishlistPicker)
            row:SetHeight(20)
            row.text = row:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
            -- Help quotes "Unassign Wishlist"; help_action_first finds it as
            -- this reviewed key bound here with the exact English.
            row.text:SetPoint("LEFT",6,0); row.text:SetText(T("journal.menu.unassign_wishlist"))
            row:SetScript("OnEnter",function(self)
                GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                GameTooltip:AddLine(T("journal.menu.unassign_wishlist"),1,1,1)
                GameTooltip:AddLine(T(self.emptySlot and "journal.tooltip.unassign_empty_slot"
                    or "journal.tooltip.unassign_keeps"),.8,.8,.8,true)
                GameTooltip:AddLine(T("journal.tooltip.unassign_no_build_change"),.8,.8,.8,true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave",function()GameTooltip:Hide()end)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            wishlistPicker.clearRow = row
        end
        row:SetFrameLevel(wishlistPicker:GetFrameLevel() + 2)
        row.emptySlot = emptySlot
        row:ClearAllPoints(); row:SetPoint("TOPLEFT",6,-24-count*rowH); row:SetPoint("RIGHT",-6,0)
        row:SetScript("OnClick", function()
            if tonumber(active) and tonumber(active) > 0 then A.ClearLoadoutWishlist(active)
            elseif A.ClearFirstRunWishlist then A.ClearFirstRunWishlist() end
            HideWishlistPicker(); M.RefreshAssociations()
        end)
        row:Show()
    end
    wishlistPicker:Show()
    RefreshSelectorTooltip()
end

local function RefreshAssociationRows()
    local journal = _G["ProjectEbonholdEchoJournal"]
    if not journal or not journal.IsShown or not journal:IsShown() then HideRowButtons(); return end
    if installed and panel and panel:IsShown() then HideRowButtons(); return end

    local A = Nexus and Nexus.GameAdapter
    local slots = A and A.Slots and A.Slots()
    if not slots then HideRowButtons(); return end

    -- The Saved Build this panel targets (GameAdapter.SelectedSavedBuild): the
    -- native active slot when it is a Saved Build, or the Saved Build Nexus kept
    -- while a Wishlist is natively active. 0 when there is none, so a Wishlist
    -- number above the Saved Build range never reaches a callback below.
    local active = A.SelectedSavedBuild and A.SelectedSavedBuild(slots) or 0
    local maxSlots = tonumber(slots.maxSlots) or 5
    local activeRow = slots.bySlot and slots.bySlot[active]
    local populated = activeRow and type(activeRow.echoes) == "table" and #activeRow.echoes > 0
    local firstRun = active < 1 or active > maxSlots or not populated
    -- A numbered Saved Build that holds no Echoes (see journal.tooltip.empty_slot_*).
    local emptySlot = firstRun and active >= 1 and active <= maxSlots

    local host = EnsureAssociationPanel(journal)
    host.emptySlot = emptySlot
    -- The scanner calls this every 0.75 s while the Journal is open. The
    -- Wishlist candidates are the most expensive adapter read of a refresh
    -- and only the picker shows them, so they are read when the picker
    -- opens (below), as the store is at that moment. The slots and the
    -- assignment are still read on every refresh: the label and the
    -- selector follow every change, announced or not.
    local linked = firstRun and (A.GetFirstRunWishlist and A.GetFirstRunWishlist())
        or (A.GetLoadoutWishlist and A.GetLoadoutWishlist(active))
    -- `loadoutName` keeps its raw value (the editor receives it unchanged);
    -- `loadoutLabel` is what this strip and the picker show for it.
    local loadoutName, loadoutLabel
    -- No Saved Build is selected: a code-owned state (from `active`, never
    -- from a name).
    local noSelection = active < 1 or active > maxSlots
    if noSelection then
        loadoutName, loadoutLabel = "No Saved Build selected", T("journal.label.no_saved_build")
    elseif not populated then
        loadoutName, loadoutLabel = "Empty Saved Build slot", T("journal.label.empty_saved_build")
    else
        loadoutName = tostring(activeRow.name or "")
        loadoutLabel = loadoutName
    end
    if not firstRun and loadoutName == "" then
        loadoutName = "Saved Build " .. tostring(active)
        loadoutLabel = TF("journal.label.saved_build_number", {slot = tostring(active)}, loadoutName)
    end
    if noSelection then
        -- The whole state text, wrapped in the label's column
        -- (WrapStripStateLabel). A player's name that reads the same is still
        -- a name and keeps the abbreviation below.
        host.label:SetText("|cffffffff" .. loadoutLabel .. ":|r")
        WrapStripStateLabel(host)
        host.labelWrapped = true
    else
        -- Names and the other states: one line cut at 21 bytes as before;
        -- after the wrapped state the label gets its original scale, width
        -- and automatic height back, and the strip its original layout.
        if host.labelWrapped then
            host.labelWrapped, host.labelFits = nil, nil
            PlaceStripLabel(host, 1, STRIP_LABEL_W, STRIP_LABEL_MAX_H)
            StripLayout(host, 0)
            host.label:SetWidth(STRIP_LABEL_W)
            host.label:SetHeight(0)
        end
        host.label:SetText("|cffffffff" .. ShortName(loadoutLabel, 21) .. ":|r")
    end

    local linkedName = linked and tostring(linked.name or "") or ""
    if linkedName ~= "" then
        host.selector.text:SetText("|cffffffff" .. ShortName(linkedName, 20) .. "|r")
        host.design:Enable()
        if host.design.icon then host.design.icon:SetDesaturated(false); host.design.icon:SetAlpha(1) end
    else
        host.selector.text:SetText(Gray(T("journal.label.select_wishlist")))
        host.design:Disable()
        if host.design.icon then host.design.icon:SetDesaturated(true); host.design.icon:SetAlpha(0.45) end
    end
    host.design:SetScript("OnClick", function()
        local editor = Nexus and Nexus.WishlistEditor
        if not linked then
            print("|cffff6060Nexus:|r " .. T("journal.chat.associate_first"))
        elseif editor and type(editor.OpenForWishlist) == "function" then
            HideWishlistPicker()
            -- Zero/empty slots use the first-run assignment. Lua's
            -- `firstRun and nil or active` would pass slot 0 as a loadout.
            editor.OpenForWishlist({
                slot = linked.slot,
                name = linked.name,
                key = linked.key,
                echoes = linked.echoes,
                lockEvidenceVersion=linked.lockEvidenceVersion,
                lockEvidenceStatus=linked.lockEvidenceStatus,
                evidenceSource=linked.evidenceSource,
                assignmentId=linked.assignmentId,designTargets=linked.designTargets,
                loadoutName = loadoutName,
            }, not firstRun and active or nil)
        else
            print("|cffff6060Nexus:|r " .. T("journal.chat.editor_unavailable"))
        end
    end)

    host.selector:SetScript("OnClick", function(self)
        if wishlistPicker and wishlistPicker:IsShown() then HideWishlistPicker(); return end
        local wishes = A.GetWishlistCandidates and A.GetWishlistCandidates() or {}
        ShowWishlistPicker(self, wishes, linked, active, loadoutName, A, emptySlot, loadoutLabel)
    end)
    host.newWishlist:SetScript("OnClick", function()
        HideWishlistPicker()
        local editor = Nexus and Nexus.WishlistEditor
        if editor and type(editor.NewWishlist) == "function" then editor.NewWishlist()
        else print("|cffff6060Nexus:|r " .. T("journal.chat.editor_unavailable")) end
    end)
    host:Show()
end

function M.RefreshAssociations()
    pcall(RefreshAssociationRows)
end

local function EnsureAssociationScanner()
    if scanFrame then return end
    scanFrame = CreateFrame("Frame", "NexusLoadoutAssociationScanner", UIParent)
    local elapsed = 0
    scanFrame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (tonumber(dt) or 0)
        if elapsed < 0.75 then return end
        elapsed = 0
        pcall(function()
            local journal = _G["ProjectEbonholdEchoJournal"]
            if journal and journal.IsShown and journal:IsShown() then
                RefreshAssociationRows()
            else
                HideRowButtons()
            end
        end)
        -- At most one coalesced page refresh per beat, and only for a marked
        -- page that is visible (ancestor-aware) with its details open.
        if refreshPending and detailsShown and installed and panel then
            local okVisible, visible = pcall(panel.IsVisible, panel)
            if okVisible and visible then pcall(M.Refresh) end
        end
    end)
end

------------------------------------------------------------------------
-- Tab select / deselect
------------------------------------------------------------------------

local function SelectOurTab()
    if PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, ourTab) end
    for i = 1, theirTabCount do
        local t = _G["ProjectEbonholdEchoJournalTab" .. i]
        if t and PanelTemplates_DeselectTab then
            pcall(PanelTemplates_DeselectTab, t)
        end
    end
    panel:Show()
    associationVisible = false
    HideRowButtons()
    M.Refresh()
end

function DeselectOurTab(showAssociation)
    if ourTab and PanelTemplates_DeselectTab then
        pcall(PanelTemplates_DeselectTab, ourTab)
    end
    if panel then panel:Hide() end
    associationVisible = showAssociation ~= false
    if associationVisible then pcall(RefreshAssociationRows) else HideRowButtons() end
    if ourTab then ourTab:Show() end
end
------------------------------------------------------------------------
-- Install
------------------------------------------------------------------------

-- Advisor tab attachment. The tab is always anchored to another frame, never
-- to screen coordinates, so it moves with whatever window carries the journal.
-- Client evidence (echo_journal.lua): the journal is reparented into
-- CollectionsJournal on first embed, that reparenting resets its children's
-- frame levels, and the hub hides the journal's own numbered tabs there. The
-- hub's replacement navigation is not in the available client evidence, so no
-- hub control is named or searched for here.
local Attach = {mode = "none", hookedTabs = {}, hookedJournal = nil}

-- The last numbered tab the client still shows, else the journal frame, which
-- is the one host known to be on screen whenever the Advisor tab is.
function Attach.Resolve(journal)
    local last
    for i = 1, theirTabCount do
        local t = _G["ProjectEbonholdEchoJournalTab" .. i]
        if t and t.IsShown and t:IsShown() then last = t end
    end
    if last then return last, "journal-tabs" end
    return journal, "journal-frame"
end

-- Idempotent. Changes the anchor only when the resolved target changed, and
-- reasserts the frame levels every time because a reparent resets them.
function Attach.Apply()
    local journal = _G["ProjectEbonholdEchoJournal"]
    if not (journal and ourTab) then return false end
    local target, mode = Attach.Resolve(journal)
    if Attach.target ~= target or Attach.mode ~= mode then
        ourTab:ClearAllPoints()
        if mode == "journal-tabs" then
            -- Same row as their tabs, standard -16 overlap after the last one.
            ourTab:SetPoint("TOPLEFT", target, "TOPRIGHT", -16, 0)
        else
            -- Their tab row hangs 12 below the journal's bottom edge and starts
            -- at its left. The right end of that same edge is used instead.
            ourTab:SetPoint("RIGHT", journal, "BOTTOMRIGHT", -12, -12)
        end
        Attach.target, Attach.mode = target, mode
    end
    ourTab:SetFrameLevel(mode == "journal-tabs" and target:GetFrameLevel()
        or journal:GetFrameLevel() + 2)
    if panel then panel:SetFrameLevel(journal:GetFrameLevel() + 10) end
    return true
end

-- For the diagnostic snapshot and the native drag/reopen check.
function M.AttachmentStatus()
    local journal = _G["ProjectEbonholdEchoJournal"]
    local parent = journal and journal.GetParent and journal:GetParent() or nil
    return {
        installed = installed, mode = Attach.mode,
        anchor = Attach.target and Attach.target.GetName and Attach.target:GetName() or "none",
        journalParent = parent and parent.GetName and parent:GetName() or "none",
        hubNavigation = "not in client evidence; not used",
    }
end

local function Install()
    local journal = _G["ProjectEbonholdEchoJournal"]
    local jScroll = _G["ProjectEbonholdEchoJournalScroll"]
    local tab1 = _G["ProjectEbonholdEchoJournalTab1"]
    if not (journal and jScroll and tab1) then
        error("journal frames not present")
    end
    EnsureAssociationScanner()

    local n = 0
    while _G["ProjectEbonholdEchoJournalTab" .. (n + 1)] do
        n = n + 1
    end
    theirTabCount = n

    -- A second Install after a partial failure reuses every frame and hook.
    ourTab = ourTab or CreateFrame("Button", "NexusJournalTab",
        journal, "CharacterFrameTabButtonTemplate")
    ourTab:SetText(T("journal.tab.nexus_progress"))
    Attach.target, Attach.mode = nil, "none"
    Attach.Apply()
    -- A fresh template tab shows BOTH texture sets until its state is
    -- set; without this it renders as a mangled sliver.
    pcall(function() PanelTemplates_TabResize(ourTab, 0) end)
    pcall(function() PanelTemplates_DeselectTab(ourTab) end)
    -- CharacterFrameTabButtonTemplate (3.3.5a export, CharacterFrameTemplates
    -- .xml L51-68) resizes the tab again on every Show and DISPLAY_SIZE_CHANGED
    -- to the host's maxTabWidth or 88, which can cut "Nexus Progress". These
    -- post-hooks run after the inherited handlers and size this tab alone to
    -- its whole label again; the host's own maxTabWidth and its tabs are left
    -- as they are. The full name is also on hover. Once per tab.
    if not ourTab._nexusTabLifecycle and ourTab.HookScript then
        ourTab._nexusTabLifecycle = true
        local function Fit() pcall(function() PanelTemplates_TabResize(ourTab, 0) end) end
        ourTab:HookScript("OnShow", Fit)
        ourTab:HookScript("OnEvent", function(_, event) if event == "DISPLAY_SIZE_CHANGED" then Fit() end end)
        ourTab:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(T("journal.tab.nexus_progress"), 1, 0.82, 0)
            GameTooltip:AddLine(T("journal.tooltip.tab_opens_page"), 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        ourTab:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    ourTab:Show()
    -- A second click closes the Advisor again. When the host hides the
    -- numbered tabs, no stock tab click is left to do that.
    ourTab:SetScript("OnClick", function()
        pcall(function()
            if panel and panel:IsShown() then DeselectOurTab(true) else SelectOurTab() end
        end)
    end)

    -- Their tab numbering differs between client revisions. Never assume
    -- Tab1 is Loadouts: inspect the clicked tab after the stock handler runs.
    for i = 1, theirTabCount do
        local t = _G["ProjectEbonholdEchoJournalTab" .. i]
        if t then
            if t.HookScript and not Attach.hookedTabs[t] then
                Attach.hookedTabs[t] = true
                -- The host hides or restores these tabs at its own time.
                -- Event-driven: no scan and no per-frame work.
                t:HookScript("OnHide", function() pcall(Attach.Apply) end)
                t:HookScript("OnShow", function() pcall(Attach.Apply) end)
                t:HookScript("OnClick", function()
                    pcall(function()
                        DeselectOurTab(false)
                        associationVisible = true
                        if associationVisible then RefreshAssociationRows() else HideRowButtons() end
                    end)
                end)
            end
        end
    end
    -- Some client builds use bottom navigation buttons that are not named
    -- ProjectEbonholdEchoJournalTabN. The scanner determines visibility from
    -- actual loadout cards, so opening/rebuilding the journal remains safe.
    if journal.HookScript and Attach.hookedJournal ~= journal then
        Attach.hookedJournal = journal
        journal:HookScript("OnShow", function()
            pcall(function()
                -- The host may have embedded the journal or hidden its tabs
                -- since the last open.
                Attach.Apply()
                DeselectOurTab(false)
                associationVisible = true
            end)
        end)
        journal:HookScript("OnHide", function() associationVisible = false; HideRowButtons() end)
    end

    -- Our panel covers the journal's ENTIRE content region below the
    -- title bar: the per-tab top sections belong to THEIR tabs and
    -- their switcher rightly ignores our tab -- so we occlude rather
    -- than fight their state. EnableMouse blocks click-through.
    if not panel then
        panel = CreateFrame("Frame", "NexusJournalPanel", journal)
        panel:SetPoint("TOPLEFT", journal, "TOPLEFT", 10, -32)
        panel:SetPoint("BOTTOMRIGHT", journal, "BOTTOMRIGHT", -8, 8)
        panel:EnableMouse(true)
        local bg = panel:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(ASSET .. "UI-Background-Rock")
    end
    panel:SetFrameLevel(journal:GetFrameLevel() + 10)

    if not scroll then
        scroll = CreateFrame("ScrollFrame", "NexusJournalScroll",
            panel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -6)
        scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)
        child = CreateFrame("Frame", nil, scroll)
        child:SetSize(292, 100)
        scroll:SetScrollChild(child)
    end

    panel:Hide()
end

-- Runs inside the client's own (pcall'd) handler paths: body must be
-- pcall-wrapped and minimal, or an error here aborts the remainder of
-- THEIR handler and gets misattributed to ProjectEbonhold.
local function OnJournalLifecycle()
    pcall(function()
        if not installed and pcall(Install) then
            installed = true
        end
        if installed then
            Attach.Apply()
            DeselectOurTab(true)
        end
    end)
end

local function EnsureLifecycleHooks()
    if hooked then return end
    if type(hooksecurefunc) ~= "function" then return end
    local pe = _G["ProjectEbonhold"]
    local ej = pe and pe.EchoJournal
    if type(ej) ~= "table" then return end
    local any = false
    if type(ej.Show) == "function" then
        hooksecurefunc(ej, "Show", OnJournalLifecycle)
        any = true
    end
    if type(ej.Toggle) == "function" then
        hooksecurefunc(ej, "Toggle", OnJournalLifecycle)
        any = true
    end
    hooked = any
end

-- The live menu-bar button that opens Character Progression -> Echoes, or nil.
-- Read-only: it finds the button and clicks nothing.
local function FindEchoesMicroButton()
    local button = _G["EchoJournalMicroButton"]
    if button and type(button.Click) == "function" then return button end
    local function walk(frame, depth)
        if not frame or depth > 6 then return nil end
        local name = frame.GetName and frame:GetName() or nil
        if type(name) == "string" then
            local lower = string.lower(name)
            if string.find(lower, "echojournalmicrobutton", 1, true)
                and type(frame.Click) == "function" then
                return frame
            end
        end
        local children = { frame.GetChildren and frame:GetChildren() }
        for i = 1, #children do
            local found = walk(children[i], depth + 1)
            if found then return found end
        end
        return nil
    end
    return walk(_G["UIParent"], 0)
end

-- Whether the Echoes page can be opened now (read-only). Callers check this
-- before closing their own window for the route, so a missing button loses
-- nothing.
function M.CanOpenBuilds()
    local ok, button = pcall(FindEchoesMicroButton)
    return ok and button ~= nil
end

-- The Echoes page as the player sees it, read-only. Ancestor-aware: an
-- embedded journal whose host window is closed is not visible. The client
-- answers 1 or nil (Theme.ClientBool); an open page must read as open, or
-- the toggling menu-bar button would be clicked and close it.
local function EchoesPageVisible()
    local journal = _G["ProjectEbonholdEchoJournal"]
    if not (journal and journal.IsVisible) then return false end
    local ok, visible = pcall(journal.IsVisible, journal)
    return ok and Nexus.Theme.ClientBool(visible) == true
end

-- My Builds as the player sees it, read-only: the Echoes page visible with the
-- stock Loadouts section shown (IsLoadoutsVisible) and not covered by the
-- Nexus Progress page.
local function MyBuildsVisible()
    if not EchoesPageVisible() then return false end
    if installed and panel and panel:IsShown() then return false end
    local ok, seen = pcall(IsLoadoutsVisible, _G["ProjectEbonholdEchoJournal"])
    return ok and seen == true
end

-- The journal's own Loadouts tab, clicked when the visible Echoes page shows
-- another of its pages. A tab click selects that page; it does not toggle the
-- window. A hidden or missing tab is never clicked.
local function SelectLoadoutsTab()
    local ok, tab = pcall(FindLoadoutsTab, _G["ProjectEbonholdEchoJournal"])
    if not (ok and tab and type(tab.Click) == "function" and tab.IsVisible) then return false end
    local okVisible, visible = pcall(tab.IsVisible, tab)
    if not (okVisible and visible) then return false end
    return (pcall(tab.Click, tab))
end

local function ClickCurrentEchoesMicroButton()
    -- The server update moved Echoes into Character Progression. Calling the
    -- legacy ProjectEbonhold.EchoJournal.Show() still opens the retired
    -- standalone journal, so always enter through the live menu-bar button.
    local button = _G["EchoJournalMicroButton"]
    if button and type(button.Click) == "function" then
        local ok = pcall(button.Click, button)
        if ok then return true end
    end

    -- Be tolerant of a renamed/reparented button while still refusing to open
    -- the obsolete standalone frame. Search only actual clickable buttons.
    local function walk(frame, depth)
        if not frame or depth > 6 then return nil end
        local name = frame.GetName and frame:GetName() or nil
        if type(name) == "string" then
            local lower = string.lower(name)
            if string.find(lower, "echojournalmicrobutton", 1, true)
                and type(frame.Click) == "function" then
                return frame
            end
        end
        local children = { frame.GetChildren and frame:GetChildren() }
        for i = 1, #children do
            local found = walk(children[i], depth + 1)
            if found then return found end
        end
        return nil
    end

    local found = walk(_G["UIParent"], 0)
    if found and type(found.Click) == "function" then
        local ok = pcall(found.Click, found)
        if ok then return true end
    end
    return false
end

-- The Wishlist chooser of the attached strip, opened through the selector's
-- own click handler (the same candidates, target and checks as a player's
-- click). Opening it assigns nothing; only a row click does. True when the
-- chooser is open.
local function OpenChooserNow()
    local host = associationPanel
    if not (host and host:IsVisible() and host.selector and host.selector:IsVisible()) then
        return false
    end
    if wishlistPicker and wishlistPicker:IsShown() then return true end
    local click = host.selector:GetScript("OnClick")
    if type(click) ~= "function" then return false end
    click(host.selector)
    return wishlistPicker ~= nil and wishlistPicker:IsShown()
end

-- OpenBuilds' delayed settles when the client offers no C_Timer.After: one
-- parentless frame whose OnUpdate counts each queued settle down by the
-- elapsed time it is given. Each settle is taken off the queue before it
-- runs, so it runs once; the frame hides itself when nothing is queued, so
-- it does no per-frame work while idle. A full queue refuses, and the caller
-- then settles at once as before.
local settleFrame
local settleQueue = {}
local MAX_QUEUED_SETTLES = 32

local function RunDueSettles(_, elapsed)
    local step = tonumber(elapsed) or 0
    local due, kept = {}, {}
    for i = 1, #settleQueue do
        local entry = settleQueue[i]
        entry.remaining = entry.remaining - step
        if entry.remaining <= 1e-6 then due[#due + 1] = entry else kept[#kept + 1] = entry end
    end
    settleQueue = kept
    if #settleQueue == 0 and settleFrame then settleFrame:Hide() end
    for i = 1, #due do pcall(due[i].fn) end
end

local function AfterFrames(delay, fn)
    if #settleQueue >= MAX_QUEUED_SETTLES then return false end
    if not settleFrame then
        local ok, f = pcall(CreateFrame, "Frame", "NexusJournalSettleDriver")
        if not ok or type(f) ~= "table" then return false end
        f:Hide()
        f:SetScript("OnUpdate", RunDueSettles)
        settleFrame = f
    end
    settleQueue[#settleQueue + 1] = { remaining = delay, fn = fn }
    settleFrame:Show()
    return true
end

-- `openChooser`: also open the Wishlist chooser once the strip is attached
-- (Assign Wishlist, Set up current build, Help and the editor's Assign now);
-- when the strip cannot be shown, say what to click instead. Without it the
-- existing behaviour is unchanged. Returns true when the Echoes page opened.
-- `beforeOpen` (optional): the caller's own step before the page opens (the
-- HUD's Assign Wishlist closes its other windows). It runs only when the
-- game's Character Progression entry is there; otherwise nothing runs and
-- false, "unavailable" is returned, so the caller says why and loses nothing.
-- The open is idempotent: the game's button toggles the page, so it is
-- clicked only while the Echoes page is not visible; an open page is kept
-- and never clicked closed. Without `openChooser` the destination is My
-- Builds: another journal page gives way to its own Loadouts tab (one click
-- per open), and `onSettled` (optional) is called once with true when My
-- Builds is seen (MyBuildsVisible), or with false when the last settle still
-- does not see it. It is told nothing else, and nothing is sent or assigned.
function M.OpenBuilds(openChooser, beforeOpen, onSettled)
    if type(beforeOpen) == "function" then
        if not M.CanOpenBuilds() then return false, "unavailable" end
        beforeOpen()
    end
    EnsureAssociationScanner()

    if not EchoesPageVisible() and not ClickCurrentEchoesMicroButton() then
        print("|cffff6060Nexus:|r " .. T("journal.chat.progression_button_missing"))
        return false
    end

    local chooserPending = openChooser == true
    local buildsPending, tabTried = openChooser ~= true, false
    local settled = openChooser ~= true and type(onSettled) == "function" and onSettled or nil
    local function report(seen)
        local fn = settled
        settled = nil
        if fn then pcall(fn, seen) end
    end
    -- Let the server finish constructing/selecting its new Echoes page before
    -- attaching Nexus beside the live loadout dropdown.
    local function finish(last)
        pcall(function()
            if not installed and pcall(Install) then installed = true end
            if installed then
                Attach.Apply()
                DeselectOurTab(false)
            end
            RefreshAssociationRows()
            if buildsPending then
                if not tabTried and EchoesPageVisible() and not MyBuildsVisible() then
                    tabTried = true
                    SelectLoadoutsTab()
                end
                if MyBuildsVisible() then
                    buildsPending = false
                    report(true)
                elseif last then
                    buildsPending = false
                    report(false)
                end
            end
            if chooserPending then
                if OpenChooserNow() then
                    chooserPending = false
                elseif last then
                    chooserPending = false
                    -- Truthful about the page: "open" only when Nexus sees its
                    -- strip there. An open page is not clicked, but a host
                    -- window open on another of its pages may still close on
                    -- the click (native behaviour, not observed offline); then
                    -- no claim is made.
                    local strip = associationPanel
                    local shown = strip and strip.IsVisible and strip:IsVisible()
                    print("|cffffd200Nexus:|r " .. T(shown and "journal.chat.chooser_coach"
                        or "journal.chat.chooser_unconfirmed"))
                end
            end
        end)
        -- A failed read is not a sighting.
        if last then report(false) end
    end
    -- A pass now, then, only while this request still waits for My Builds
    -- or the chooser, two later ones at 0.10 s and the last at 0.35 s, with
    -- or without C_Timer (without it the settle frame above drives them; if
    -- it cannot, the pass now is the last, as before). A later pass of a
    -- request that has settled does nothing, so it never changes a page or
    -- tab the player chose since (with or without `onSettled`).
    local function pending() return buildsPending or chooserPending end
    local timers = C_Timer and C_Timer.After
    local function later(delay, fn)
        if timers then
            C_Timer.After(delay, fn)
            return true
        end
        return AfterFrames(delay, fn)
    end
    finish(false)
    if pending() then
        later(0.10, function() if pending() then finish(false) end end)
        if not later(0.35, function() if pending() then finish(true) end end) then finish(true) end
    end
    return true
end

function M.DebugSnapshot()
    local journal = _G["ProjectEbonholdEchoJournal"]
    local A = Nexus and Nexus.GameAdapter
    local slots = A and A.Slots and A.Slots()
    local visible = journal and IsLoadoutsVisible(journal) or false
    local tab = journal and FindLoadoutsTab(journal) or nil
    local tabText = tab and NormalizedText(tab) or "none"
    local lines = {}
    lines[#lines + 1] = "journal=" .. tostring(journal ~= nil) .. " shown=" .. tostring(journal and journal:IsShown() or false)
    lines[#lines + 1] = "loadoutsVisible=" .. tostring(visible) .. " tab=" .. tostring(tabText)
    local attachment = M.AttachmentStatus()
    lines[#lines + 1] = "advisorTab mode=" .. tostring(attachment.mode) .. " anchor=" .. tostring(attachment.anchor)
        .. " journalParent=" .. tostring(attachment.journalParent) .. " hubNavigation=" .. attachment.hubNavigation
    lines[#lines + 1] = "associationPanel=" .. tostring(associationPanel ~= nil)
        .. " shown=" .. tostring(associationPanel and associationPanel:IsShown() or false)
    if slots then
        lines[#lines + 1] = "activeSlot=" .. tostring(slots.activeSlot) .. " maxSlots=" .. tostring(slots.maxSlots)
        for i = 1, tonumber(slots.maxSlots or 5) do
            local r = slots.bySlot and slots.bySlot[i]
            lines[#lines + 1] = "slot" .. i .. " echoes=" .. tostring(r and r.echoes and #r.echoes or 0) .. " linked=" .. tostring(A.GetLoadoutWishlistSlot and A.GetLoadoutWishlistSlot(i) or "none")
        end
    else
        lines[#lines + 1] = "slots=nil"
    end
    return lines
end

-- Attach to the live journal (or arm the lazy Show/Toggle hooks and
-- attach on first open). Safe to call repeatedly; never errors.
function M.TryInstall(dataProvider)
    local ok = pcall(function()
        if type(dataProvider) == "function" then
            provider = dataProvider
        end
        EnsureAssociationScanner()
        EnsureLifecycleHooks()
        if not installed and pcall(Install) then
            installed = true
        end
    end)
    if not ok then return false end
    return installed and true or false
end

-- Dark-theme Nexus controls embedded in the server Echo Journal.
do
    local originalRefreshAssociations = M.RefreshAssociations
    M.RefreshAssociations = function(...)
        local result = originalRefreshAssociations(...)
        if associationPanel and Nexus.Theme then Nexus.Theme.StyleTree(associationPanel) end
        return result
    end
end
