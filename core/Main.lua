-- Nexus: core/Main.lua
-- Thin bootstrap/coordinator. Internal owners retain diagnostics, display
-- projection, commands, automation, and lifecycle/event state.
-- SCOPING RULE: every closure-captured local is declared here, before
-- any closure that reads it.

Nexus = Nexus or {}
Nexus.VERSION = (Nexus.Release and Nexus.Release.version) or "1.20.0-beta.1"

local Model, Policy, Ratchet, Strategy, Store, Adapter
local Readout, Panel, JournalTab, DefaultProfile
local AutomationRuntime, MainLifecycle, MainCommands, MainDiagnostics, MainViewModel
local EnsureAutomationRuntime, EnsureMainLifecycle, EnsureMainCommands
local EnsureMainDiagnostics, EnsureMainViewModel

-- ARM state
local EH  -- event frame
local lastPanelInput = nil
local panelProgressCache = {valid=false}
local selectedPreviewCache = {valid=false}
local activeFingerprintCache = {valid=false}

local CHAT_PREFIX = "|cff7fd5ffNexus:|r "

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. (Nexus.UserText and Nexus.UserText.Message(msg) or tostring(msg)))
end

-- Full-UI localization (v3): the /nexus status lines below that Print
-- composes from raw English (TARGET: ..., OWNED this run: ...) are said
-- through this UserText phrase source. Their English is the line UserText's
-- legacy rewrite showed before (TARGET: -> WISHLIST:, synced -> server
-- confirmed); the composition here is unchanged.
local TARGET_SOURCES = {["Echo Wishlist build"] = "command.value.target_source_designed",
    ["active loadout"] = "command.value.target_source_active", ["wishlist"] = "command.value.target_source_wishlist"}
local ASSIGNMENT_NOTES = {["Restoring assigned Wishlist..."] = "orb.status.restoring_assignment",
    ["Waiting for loadout data..."] = "orb.assignment.waiting_loadout",
    ["Wishlist needs locked targets. Open the Wishlist Editor to choose and confirm them."] = "orb.assignment.needs_locked_targets",
    ["First-run wishlist target"] = "orb.assignment.first_run_target",
    ["First-run wishlist data is temporarily unavailable; waiting for the server mirror."] = "orb.assignment.first_run_unavailable",
    ["Choose or create a wishlist to begin your first run."] = "orb.assignment.choose_or_create"}
local STATUS_PHRASES = {exact = {["TARGET: none -- advisor only"] = "command.chat.status_target_none"}, formats = {
    {format = "TARGET: %s (your %s) -- %d echoes", key = "command.chat.status_target",
        fields = {"name", "source", "count"}, nested = {source = TARGET_SOURCES}},
    {format = "TARGET: none -- advisor only  (%s)", key = "command.chat.status_target_none_note",
        fields = {"note"}, nested = {note = ASSIGNMENT_NOTES}},
    {format = "OWNED this run: %d echoes (synced).", key = "command.chat.status_owned_synced", fields = {"count"}},
    {format = "OWNED this run: %d echoes (not synced yet).", key = "command.chat.status_owned_unsynced", fields = {"count"}},
}}
local statusBook
local NOTE_HEAD = "TARGET: none -- advisor only  ("
local function StatusPhrase(text)
    local L = Nexus.Localization
    if type(text) ~= "string" or type(L) ~= "table" or type(L.PhraseBook) ~= "function" then return text, false end
    if not statusBook or statusBook.seam ~= L then
        statusBook = L.PhraseBook(STATUS_PHRASES)
        statusBook.seam = L
    end
    -- The adapter's identity-found note inside the advisor-only line: said
    -- from the adapter's own facts, whole, as this line always showed it
    -- (UserText.IdentityNote). Any other note keeps the book's route below.
    if #text > #NOTE_HEAD + 1 and text:sub(1, #NOTE_HEAD) == NOTE_HEAD and text:sub(-1) == ")" then
        local user = Nexus.UserText
        local note = user and type(user.IdentityNote) == "function" and user.IdentityNote(text:sub(#NOTE_HEAD + 1, -2), true)
        if note then
            local line, source = L.Format("command.chat.status_target_none_note", {note = note})
            if source == "candidate" then return line, true end
        end
    end
    return L.Phrase(text, statusBook)
end
Nexus.MainStatusPhrase = StatusPhrase
-- The chat lines core/AutomationRuntime.lua and core/GameAdapter.lua print
-- through Print (options.print / OnStatus), after an optional coloured
-- "Nexus:" tag of their own that stays code-owned. An Auto hold reason is
-- shown through UserText.Recognized (its words otherwise).
-- RUNTIME-CHAT BEGIN (generated from the fragment)
local RUNTIME_PHRASES = {exact = {
    ["select: the client's pending flag is still set after 10s with no result observed; it no longer holds other Echo actions, and Nexus sends no Select while it is set."] = "adapter.chat.outside_select_pending",
    ["Select still unresolved after 10s: the client's pending flag is still set although a matching grant is visible. Nexus sends nothing new and waits for the flag to clear. The game gives no receipt for a selection, so this wait can last until a new run."] = "adapter.chat.select_unresolved_seen",
    ["Select still unresolved after 10s: the client's pending flag is still set although a matching grant is visible. Nexus sends nothing new and waits; another selection of the same Echo was seen, so no grant can settle it. The game gives no receipt for a selection, so this wait can last until a new run."] = "adapter.chat.select_unresolved_seen_competing",
    ["Select still unresolved after 10s: the client's pending flag is still set and its grant is not visible yet. Nexus sends nothing new and waits; while Auto is ON it re-reads the granted Echoes. The game gives no receipt for a selection, so this wait can last until a new run."] = "adapter.chat.select_unresolved_unseen",
    ["Select still unresolved after 10s: the client's pending flag is still set and its grant is not visible yet. Nexus sends nothing new and waits; another selection of the same Echo was seen, so no grant can settle it. The game gives no receipt for a selection, so this wait can last until a new run."] = "adapter.chat.select_unresolved_unseen_competing",
    ["Select: the game still shows a selection pending after 10s with no result observed; Nexus sends no Echo action until it clears."] = "adapter.chat.selection_pending_held",
    ["I couldn't create the first Saved Build automatically. Open Echo Journal > My Builds and save this finished run into a Saved Build slot before resetting."] = "automation.chat.first_run_create_failed",
    ["your first run is finished, but Nexus found no free Saved Build slot. Save this loadout manually in Echo Journal > My Builds before resetting."] = "automation.chat.first_run_no_slot",
    ["the first-run Saved Build write was not confirmed before the reset. Open Echo Journal > My Builds and verify/save the loadout manually before relying on automated convergence."] = "automation.chat.first_run_unconfirmed_reset",
    ["Nexus cannot safely choose or overwrite a Saved Build while none is active. Open Echo Journal > My Builds, save this finished run into a slot, and activate that slot before resetting."] = "automation.chat.no_active_saved_build",
}, formats = {
    {format = "unlocked %s -- %s is acquired and ready to replace it.",
        key = "automation.chat.unlocked_ready", fields = {"old", "new"}},
    {format = "couldn't unlock %s: %s",
        key = "automation.chat.unlock_failed", fields = {"echo", "error"}},
    {format = "lock request sent for %s; waiting for server confirmation.",
        key = "automation.chat.lock_sent", fields = {"echo"}},
    {format = "couldn't lock %s: %s",
        key = "automation.chat.lock_failed", fields = {"echo", "error"}},
    {format = "Save sent — %s. Checking the Saved Build now. Still needed: %s.",
        key = "automation.chat.save_sent", fields = {"change", "needed"}, nested = {change = {["loadout improved"]="automation.value.loadout_improved", ["first completed run"]="automation.value.first_completed_run"}, needed = {["none"]="automation.value.none_needed"}}},
    {format = "No improvement run — not saving. Still needed: %s.",
        key = "automation.chat.no_improvement", fields = {"needed"}, nested = {needed = {["none"]="automation.value.none_needed"}}},
    {format = "first run complete. Nexus is attempting to store it in Saved Build %s. Wait for the confirmation message before resetting; if it does not confirm, save this finished loadout manually in Echo Journal > My Builds.",
        key = "automation.chat.first_run_storing", fields = {"slot"}},
    {format = "first run saved to Saved Build %s. Activate that slot in My Builds before starting the next run.",
        key = "automation.chat.first_run_saved", fields = {"slot"}},
    {format = "I couldn't confirm that your first completed run was stored in Saved Build %s. Open Echo Journal > My Builds and save this finished loadout into a slot before resetting.",
        key = "automation.chat.first_run_not_confirmed", fields = {"slot"}},
    {format = "Auto is ON but paused: %s",
        key = "automation.chat.auto_on_paused", fields = {"reason"}, nested = {reason = true}},
    {format = "%s: the client's pending flag is still set after 10s with no result observed -- no longer waited on (it is honoured again if the flag clears)",
        key = "adapter.chat.action_pending_released", fields = {"action"}},
}}
-- RUNTIME-CHAT END
local runtimeBook
local function RuntimePhrase(text)
    local L = Nexus.Localization
    if type(text) ~= "string" or type(L) ~= "table" or type(L.PhraseBook) ~= "function" then return text, false end
    local tag, body = text:match("^(|c%x%x%x%x%x%x%x%xNexus:|r )(.*)$")
    tag, body = tag or "", body or text
    local reason = body:match("^Auto is ON but paused: (.*)$")
    if reason then
        local user = Nexus.UserText
        local shown, source = L.Format("automation.chat.auto_on_paused",
            {reason = user and type(user.Recognized) == "function" and user.Recognized(reason) or reason})
        if source == "unavailable" then return text, false end
        return tag .. shown, true
    end
    if not runtimeBook or runtimeBook.seam ~= L then
        runtimeBook = L.PhraseBook(RUNTIME_PHRASES)
        runtimeBook.seam = L
    end
    local shown, known = L.Phrase(body, runtimeBook)
    if known then return tag .. shown, true end
    return text, false
end
Nexus.MainRuntimePhrase = RuntimePhrase
function Nexus.MainRuntimeBook()
    RuntimePhrase("")
    return runtimeBook
end
-- The main panel's status lines core/AutomationRuntime.lua sets
-- (SetStatus); the panel says model.status through UserText.Message. "auto
-- paused: <reason>" shows its reason through UserText.Recognized.
-- RUNTIME-STATUS BEGIN (generated from the fragment)
local RUNTIME_STATUS = {exact = {
    ["Banish refused -- trying another action"] = "automation.status.banish_refused",
    ["Choose or create a wishlist to begin your first run"] = "automation.status.choose_or_create",
    ["error (see /nexus err)"] = "automation.status.error_see_err",
    ["final-search Banish refused -- re-evaluating"] = "automation.status.final_banish_refused",
    ["final-search Reroll refused -- taking held Echo"] = "automation.status.final_reroll_refused",
    ["finishing run — Echo count not synchronized yet"] = "automation.status.finishing_count_unsynced",
    ["finishing final Echo selections"] = "automation.status.finishing_final_selections",
    ["First run complete — no free Saved Build slot; save manually before resetting"] = "automation.status.first_run_no_free_slot",
    ["First run not confirmed — save it manually in My Builds before resetting"] = "automation.status.first_run_not_confirmed",
    ["First run complete — save/activate it in My Builds before resetting"] = "automation.status.first_run_save_activate",
    ["First run complete — save it manually in My Builds before resetting"] = "automation.status.first_run_save_manually",
    ["First-run wishlist active — Saved Build will be created by normal server progression"] = "automation.status.first_run_wishlist_active",
    ["active loadout changed before save -- write cancelled"] = "automation.status.loadout_changed_cancelled",
    ["No wishlist set -- advisor only"] = "automation.status.no_wishlist_advisor",
    ["No wishlist set -- not saving"] = "automation.status.no_wishlist_not_saving",
    ["Ordinary Automation stays OFF while the Orb operation is active or unresolved."] = "automation.status.orb_keeps_auto_off",
    ["Auto stays OFF while Nexus is paused. Resume Nexus first."] = "automation.status.paused_keeps_auto_off",
    ["Reroll refused -- taking the least-harmful Echo"] = "automation.status.reroll_refused",
    ["save data matched, but active loadout changed — not claiming overwrite"] = "automation.status.save_matched_loadout_changed",
    ["Save sent — checking server"] = "automation.status.save_sent_checking",
    ["Save request sent; server confirmation not received. Check My Builds before resetting."] = "automation.status.save_unconfirmed",
    ["saved loadout unchanged — no current run observed"] = "automation.status.saved_unchanged_no_run",
    ["waiting for board"] = "automation.status.waiting_board",
    ["waiting for ProjectEbonhold"] = "automation.status.waiting_project_ebonhold",
    ["waiting for slot data"] = "automation.status.waiting_slot_data",
    ["Auto stays OFF: its overwrite warning is unavailable."] = "automation.status.warning_keeps_auto_off",
}, formats = {
    {format = "%sBanished%s echo #%d", key = "automation.status.banished_echo", fields = {"open", "close", "index"}},
    {format = "%sFroze%s echo #%d -- waiting for board to update", key = "automation.status.froze_echo", fields = {"open", "close", "index"}},
    {format = "Working toward '%s' — run complete, no improvement (%s)", key = "automation.status.no_improvement", fields = {"wishlist", "detail"}},
    {format = "First run saved to Saved Build %s — activate it in My Builds before resetting", key = "automation.status.first_run_saved", fields = {"slot"}},
    {format = "Save complete — server confirmed Active Loadout %s", key = "automation.status.save_confirmed", fields = {"slot"}},
    {format = "first-run save sent to Saved Build %s -- confirming", key = "automation.status.first_run_save_sent", fields = {"slot"}},
    {format = "Save sent to Active Loadout %d — checking server (+%ss)", key = "automation.status.save_sent_checking_seconds", fields = {"slot", "seconds"}},
    {format = "finishing run — %d/79 Echoes", key = "automation.status.finishing_count", fields = {"count"}},
}}
-- RUNTIME-STATUS END
local runtimeStatusBook
local function RuntimeStatusPhrase(text)
    local L = Nexus.Localization
    if type(text) ~= "string" or type(L) ~= "table" or type(L.PhraseBook) ~= "function" then return text, false end
    local reason = text:match("^auto paused: (.*)$")
    if reason then
        local user = Nexus.UserText
        local shown, source = L.Format("automation.status.auto_paused",
            {reason = user and type(user.Recognized) == "function" and user.Recognized(reason) or reason})
        if source == "unavailable" then return text, false end
        return shown, true
    end
    if not runtimeStatusBook or runtimeStatusBook.seam ~= L then
        runtimeStatusBook = L.PhraseBook(RUNTIME_STATUS)
        runtimeStatusBook.seam = L
    end
    return L.Phrase(text, runtimeStatusBook)
end
Nexus.MainRuntimeStatusPhrase = RuntimeStatusPhrase
function Nexus.MainRuntimeStatusBook()
    RuntimeStatusPhrase("")
    return runtimeStatusBook
end
if Nexus.UserText and type(Nexus.UserText.AddPhraseSource) == "function" then
    Nexus.UserText.AddPhraseSource(StatusPhrase)
    Nexus.UserText.AddPhraseSource(RuntimePhrase)
    Nexus.UserText.AddPhraseSource(RuntimeStatusPhrase)
end

-- Full-UI localization, chat family. A reviewed chat line resolves through
-- the Nexus.Localization seam, looked up at call time. Its English (base)
-- text takes Print's path exactly as the former literal did, the
-- UserText.Message rewrite included, so English output keeps its bytes. A
-- translated (candidate) text follows the same code-owned prefix and never
-- runs through that English-only rewrite. Slash command words, setting
-- values, codes, versions and names enter only through text slots or as
-- literal command text and are never translated.
local function PrintText(text, source)
    if source == "candidate" then
        DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. tostring(text))
    else
        Print(text)
    end
end

-- The seam's text for a key (and its source), or the key itself when the
-- seam is absent (it is loaded by the TOC before this file).
local function UiText(key)
    local localization = Nexus.Localization
    if type(localization) ~= "table" then return key, "base" end
    local text, source = localization.Text(key)
    return text, source
end

local function UiFormat(key, arguments)
    local localization = Nexus.Localization
    if type(localization) ~= "table" then return key, "unavailable" end
    local text, source = localization.Format(key, arguments)
    return text, source
end

-- A count slot record; unknown (never 0) without the seam.
local function Count(value)
    local localization = Nexus.Localization
    if type(localization) ~= "table" then return {known=false} end
    return localization.Count(value)
end

local function Say(key) PrintText(UiText(key)) end

-- `legacy`, when given, is the exact English line for a slot value the
-- template cannot carry (a name above the text-slot bound): it keeps the
-- line instead of the seam's unavailable status.
local function SayFormat(key, arguments, legacy)
    local text, source = UiFormat(key, arguments)
    if source == "unavailable" and legacy ~= nil then return Print(legacy) end
    PrintText(text, source)
end

-- A colour code owned here around one reviewed line.
local function SayColored(key, color)
    local text, source = UiText(key)
    PrintText(color .. text .. "|r", source)
end

-- A reviewed text of several chat lines (block): one chat line per line.
local function SayLines(key)
    local text, source = UiText(key)
    for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do PrintText(line, source) end
end

-- One reviewed line, then the reviewed session-only sentence when the saved
-- root is read-only: two whole sentences on one chat line, joined here.
local function SayWithSessionNote(text, source, sessionOnly)
    if sessionOnly then
        local note, noteSource = UiText("command.chat.session_only_note")
        text = text .. " " .. note
        if noteSource == "candidate" then source = "candidate" end
    end
    PrintText(text, source)
end

-- "candidate" while a translation is active, for data lines (names) that
-- may hold translated labels; "base" (Print's path) in English.
local function ActiveSource()
    local localization = Nexus.Localization
    local active = type(localization) == "table" and type(localization.ActiveLanguage) == "function"
        and localization.ActiveLanguage() or nil
    return (active ~= nil and active ~= localization.DEFAULT_LANGUAGE) and "candidate" or "base"
end

local function DisplayUntrusted(value, maxBytes, allowEmpty, allowLineBreaks)
    local identity = Nexus and Nexus.Identity
    if not (identity and type(identity.DisplaySafeText) == "function") then
        return nil
    end
    return identity.DisplaySafeText(
        value, maxBytes, allowEmpty, allowLineBreaks)
end

local function ErrorText(value)
    local errors = Nexus and Nexus.Errors
    if errors and type(errors.SafeText) == "function" then
        local ok, text = pcall(errors.SafeText, value)
        if ok and type(text) == "string" then return text end
    end
    local ok, text = pcall(tostring, value)
    return ok and text or "<unprintable error>"
end

local function RecordError(source, value)
    local errors = Nexus and Nexus.Errors
    if errors and type(errors.Record) == "function" then
        local ok = pcall(errors.Record, source, value)
        if ok then return end
    end
    Nexus.lastError = ErrorText(value)
end

-- Store failure means persistence authority is unresolved. Keep that error in
-- session memory only: persistent diagnostic fallbacks may otherwise replace a
-- malformed root before Store can preserve it for recovery.
local function RecordStoreError(value)
    Nexus.lastError = ErrorText(value)
end

EnsureMainViewModel = function()
    if MainViewModel then return MainViewModel end
    local internals = Nexus.MainInternals
    local factory = internals and internals.ViewModel
    if not (factory and type(factory.New) == "function") then return nil end
    local ratchet = Ratchet or Nexus.Ratchet
    if not ratchet then return nil end
    MainViewModel = factory.New({ratchet=ratchet,model=Model or Nexus.Model,
        wishlistModel=assert(Nexus.WishlistModel,
            "WishlistModel unavailable").New()})
    return MainViewModel
end

local function Automation()
    return EnsureAutomationRuntime and EnsureAutomationRuntime()
end

local function Lifecycle()
    return EnsureMainLifecycle and EnsureMainLifecycle()
end

local function StatusLine()
    local runtime = Automation()
    return runtime and runtime.StatusLine() or "loading"
end

local function RequestRecompute()
    local runtime = Automation()
    return runtime and runtime.RequestRecompute() or false
end

Nexus.RequestRecompute = RequestRecompute

local function RetryAutoLock()
    local runtime = Automation()
    return runtime and runtime.RetryAutoLock() or false
end

Nexus.RetryAutoLock = RetryAutoLock

-- Read-only: the automation runtime's own record of an automatic action that
-- has no confirmed result ("submitted", "uncertain" or "expired"), or nil.
-- It authorizes nothing; the Orb window uses it for wording only.
function Nexus.PendingIntentState()
    local runtime = Automation()
    return runtime and runtime.PendingIntentState and runtime.PendingIntentState() or nil
end

-- Only disables the existing session master switch. It never enables actions.
function Nexus.DisableOrdinaryAutomation()
    local runtime=Automation()
    if not runtime then return false,"Ordinary automation owner is not ready." end
    if Nexus.OverwriteWarning and Nexus.OverwriteWarning.CancelAuto then
        Nexus.OverwriteWarning.CancelAuto(runtime)
    end
    if runtime.AutoEnabled() then runtime.ToggleAuto() end
    if Panel and Panel.SetAuto then Panel.SetAuto(false) end
    return runtime.AutoEnabled()==false
end


function Nexus.RecomputeStats()
    local runtime = Automation()
    return runtime and runtime.RecomputeStats()
        or {polls=0,fullSteps=0,skipped=0,forced=0,dirty=0,
            deadlines=0,fallbacks=0,explicit=0,nextStepAt=nil,
            nextAutoLockAt=nil,lastFullStepAt=-math.huge,
            lastStaticProbeAt=-math.huge,fallbackSeconds=5,
            planCompiles=0,planReuses=0,staticProbes=0,
            wishlistFingerprints=0,lockContextRebuilds=0,
            autoLockEvaluations=0,pollFailures=0,autoEnabled=false,
            autoLockLifecycle={prepared=0,submitted=0,
                awaitingConfirmation=0,confirmed=0,rejected=0,expired=0,
                superseded=0,spacingRetries=0,explicitRetries=0,
                postExpiryBlocked=0},
            lastAutoLockLifecycle={state="idle",reason="none",error="none",
                spellId=0,replaces=0,lockedRevision=0,adapterAttempts=0,
                preparedAt=0,submittedAt=0,expiresAt=0,resolvedAt=0},
            autoLockCapacity={used=0,maximum=0,known=false,
                source="unavailable",synced=false}}
end

local function AppendAudit(kind, fields)
    local diagnostics = EnsureMainDiagnostics and EnsureMainDiagnostics()
    return diagnostics and diagnostics.AppendAudit(kind, fields) or false
end
Nexus.AppendAudit = AppendAudit

local function AppendAutoLockEvent(fields)
    local diagnostics = EnsureMainDiagnostics and EnsureMainDiagnostics()
    return diagnostics and diagnostics.AppendAutoLockEvent(fields) or false
end

local function EffectiveFlags()
    local runtime = Automation()
    return runtime and runtime.EffectiveFlags() or {}
end

local function AutoAllowed()
    local runtime = Automation()
    if not runtime then return false, "manual mode" end
    return runtime.AutoAllowed()
end

local function LockDesignTargetsFor(wishlist)
    local runtime = Automation()
    return runtime and runtime.LockDesignTargetsFor(wishlist) or nil
end

local function WishlistWithLockTargets(wishlist, catalog)
    local runtime = Automation()
    return runtime and runtime.WishlistWithLockTargets(wishlist, catalog)
        or wishlist
end

local function WishlistProgress(plan, owned, catalog, lockOnlyFamilies, wishlist)
    local runtime = Automation()
    if not runtime then return 0, 0, {}, {} end
    return runtime.WishlistProgress(plan, owned, catalog, lockOnlyFamilies, wishlist)
end

local function LoadoutCoverage(activeRow, plan, catalog)
    local viewModel = EnsureMainViewModel and EnsureMainViewModel()
    if not viewModel then return {}, nil, {} end
    return viewModel.LoadoutCoverage(activeRow, plan, catalog)
end

-- Builds the one progress table every render site feeds to the panel:
-- this run's gains, the active loadout's convergence toward the ideal
-- wishlist, and the loadout's specific missing echoes (what "close to
-- ideal" actually means, not just a percentage).
local function BuildProgress(plan, owned, slots, catalog, wishlistOverride,
    previewBuildId, staticContext, lockedOverride)
    local viewModel = EnsureMainViewModel and EnsureMainViewModel()
    if not viewModel then return {} end
    -- A static snapshot may intentionally contain no wishlist. Preserve that
    -- known-nil result instead of turning it into an uncached Adapter read on
    -- every panel render.
    local wishlist = wishlistOverride
    if wishlist == nil then
        if type(staticContext) == "table" then
            wishlist = staticContext.wishlist
        else
            wishlist = Adapter.Wishlist()
        end
    end
    local lockedOwned = lockedOverride
    if lockedOwned == nil and Adapter.LockedOwned then
        lockedOwned = Adapter.LockedOwned()
    end
    local designTargets
    if not wishlistOverride and type(staticContext) == "table" then
        designTargets = staticContext.targets
    else
        designTargets = LockDesignTargetsFor(wishlist)
    end
    local matchedBuildId = nil
    local capture = Nexus.DpsCapture
    if capture and capture.FindMatchingBuildPublic and wishlist then
        matchedBuildId = capture.FindMatchingBuildPublic(wishlist)
    end
    local wishlistEchoes = wishlist and (wishlist.echoes or wishlist.entries) or nil
    local tomeEchoes = viewModel.TomeEchoes(wishlistEchoes, designTargets, catalog)
    local unknownTomes = Adapter.UnknownTomesForEchoes
        and Adapter.UnknownTomesForEchoes(tomeEchoes) or {}
    return viewModel.BuildProgress({
        plan=plan,owned=owned,slots=slots,catalog=catalog,wishlist=wishlist,
        lockedOwned=lockedOwned,designTargets=designTargets,
        unknownTomes=unknownTomes,matchedBuildId=matchedBuildId,
        previewBuildId=previewBuildId,
    })
end

local function ExactEchoFingerprint(echoes)
    local capture = Nexus and Nexus.DpsCapture
    if not (capture and type(capture.GetEchoKey) == "function") then
        return nil
    end
    local ok, fingerprint = pcall(capture.GetEchoKey, echoes)
    return ok and type(fingerprint) == "string" and fingerprint or nil
end

local function ReadSelectedPanelKey()
    local community = Nexus and Nexus.CommunityBuilds
    local reader = community and community.GetSelectedBuildForPanelKey
    if type(reader) ~= "function" then return false end
    local ok, id, epoch, revision = pcall(reader)
    if not ok or type(epoch) ~= "number" then return false end
    return true, id, epoch, tonumber(revision) or 0
end

local function ReadPanelRevisions()
    local reader = Adapter and Adapter.PresentationRevisions
    if type(reader) ~= "function" then return false end
    local ok, slotsRevision, activeRevision, grantedRevision,
        ownedRevision, wishlistRevision, catalogRevision,
        lockedRevision, lockedLocalRevision, discoveryRevision,
        leverRevision, levelBoundary = pcall(reader)
    if not ok then return false end
    if type(slotsRevision) ~= "number"
        or type(activeRevision) ~= "number"
        or type(grantedRevision) ~= "number"
        or type(ownedRevision) ~= "number"
        or type(wishlistRevision) ~= "number"
        or type(catalogRevision) ~= "number"
        or type(lockedRevision) ~= "number"
        or type(lockedLocalRevision) ~= "number"
        or type(discoveryRevision) ~= "number"
        or type(leverRevision) ~= "number"
        or type(levelBoundary) ~= "number" then
        return false
    end
    return true,slotsRevision,activeRevision,grantedRevision,ownedRevision,
        wishlistRevision,catalogRevision,lockedRevision,lockedLocalRevision,
        discoveryRevision,leverRevision,levelBoundary
end

local function ReadExactRevision(fingerprint)
    local catalogOwner = Nexus and Nexus.BuildCatalog
    local reader = catalogOwner and catalogOwner.ExactFingerprintRevision
    if type(reader) ~= "function" then return false end
    local ok, epoch, revision = pcall(reader, fingerprint)
    if not ok or type(epoch) ~= "number" or type(revision) ~= "number" then
        return false
    end
    return true, epoch, revision
end

local function ActiveFingerprint(staticContext)
    if type(staticContext) ~= "table" or staticContext.key == nil then
        return nil
    end
    if activeFingerprintCache.valid
        and activeFingerprintCache.key == staticContext.key then
        return activeFingerprintCache.fingerprint
    end
    local wishlist = staticContext.wishlist
    local echoes = wishlist and (wishlist.echoes or wishlist.entries) or nil
    activeFingerprintCache.valid = true
    activeFingerprintCache.key = staticContext.key
    activeFingerprintCache.fingerprint = ExactEchoFingerprint(echoes)
    return activeFingerprintCache.fingerprint
end

local function SelectedPreview(selectionId, selectionEpoch,
    selectionRevision, catalog, staticContext)
    if selectionId == nil then return nil, nil, nil end
    local staticKey = type(staticContext) == "table" and staticContext.key or nil
    if selectedPreviewCache.valid
        and selectedPreviewCache.id == selectionId
        and selectedPreviewCache.epoch == selectionEpoch
        and selectedPreviewCache.revision == selectionRevision
        and selectedPreviewCache.catalog == catalog
        and selectedPreviewCache.staticKey == staticKey then
        return selectedPreviewCache.plan, selectedPreviewCache.wishlist,
            selectedPreviewCache.fingerprint
    end
    local community = Nexus and Nexus.CommunityBuilds
    local getter = community and community.GetSelectedBuildForPanel
    local build = type(getter) == "function" and getter() or nil
    local wishlist, plan, fingerprint
    if build and type(build.echoes) == "table" and #build.echoes > 0 then
        wishlist = {
            name=build.title or "Community Build", entries=build.echoes,
        }
        plan = Strategy.Compile(catalog, wishlist, Store.Settings())
        fingerprint = ExactEchoFingerprint(build.echoes)
    end
    selectedPreviewCache.valid = true
    selectedPreviewCache.id = selectionId
    selectedPreviewCache.epoch = selectionEpoch
    selectedPreviewCache.revision = selectionRevision
    selectedPreviewCache.catalog = catalog
    selectedPreviewCache.staticKey = staticKey
    selectedPreviewCache.plan = plan
    selectedPreviewCache.wishlist = wishlist
    selectedPreviewCache.fingerprint = fingerprint
    return plan, wishlist, fingerprint
end

local function SamePanelProgressKey(cache, activePlan, catalog, staticKey,
    selectionId, selectionEpoch, selectionRevision,
    slotsRevision, activeRevision, grantedRevision, ownedRevision,
    wishlistRevision, catalogRevision, lockedRevision, lockedLocalRevision,
    discoveryRevision, leverRevision, levelBoundary,
    exactEpoch, exactRevision)
    return cache.valid and cache.activePlan == activePlan
        and cache.catalog == catalog and cache.staticKey == staticKey
        and cache.selectionId == selectionId
        and cache.selectionEpoch == selectionEpoch
        and cache.selectionRevision == selectionRevision
        and cache.slotsRevision == slotsRevision
        and cache.activeRevision == activeRevision
        and cache.grantedRevision == grantedRevision
        and cache.ownedRevision == ownedRevision
        and cache.wishlistRevision == wishlistRevision
        and cache.catalogRevision == catalogRevision
        and cache.lockedRevision == lockedRevision
        and cache.lockedLocalRevision == lockedLocalRevision
        and cache.discoveryRevision == discoveryRevision
        and cache.leverRevision == leverRevision
        and cache.levelBoundary == levelBoundary
        and cache.exactEpoch == exactEpoch
        and cache.exactRevision == exactRevision
end

local function StorePanelProgressKey(cache, value, activePlan, catalog,
    staticKey, selectionId, selectionEpoch, selectionRevision,
    slotsRevision, activeRevision, grantedRevision, ownedRevision,
    wishlistRevision, catalogRevision, lockedRevision, lockedLocalRevision,
    discoveryRevision, leverRevision, levelBoundary,
    exactEpoch, exactRevision)
    cache.valid, cache.value = true, value
    cache.activePlan, cache.catalog, cache.staticKey = activePlan, catalog, staticKey
    cache.selectionId = selectionId
    cache.selectionEpoch, cache.selectionRevision = selectionEpoch, selectionRevision
    cache.slotsRevision, cache.activeRevision = slotsRevision, activeRevision
    cache.grantedRevision, cache.ownedRevision = grantedRevision, ownedRevision
    cache.wishlistRevision, cache.catalogRevision = wishlistRevision, catalogRevision
    cache.lockedRevision, cache.lockedLocalRevision = lockedRevision, lockedLocalRevision
    cache.discoveryRevision, cache.leverRevision = discoveryRevision, leverRevision
    cache.levelBoundary = levelBoundary
    cache.exactEpoch, cache.exactRevision = exactEpoch, exactRevision
end

local function BuildPanelProgress(activePlan, owned, slots, catalog,
    staticContext, lockedOverride)
    local selectedOK, selectionId, selectionEpoch, selectionRevision =
        ReadSelectedPanelKey()
    local revisionsOK, slotsRevision, activeRevision, grantedRevision,
        ownedRevision, wishlistRevision, catalogRevision,
        lockedRevision, lockedLocalRevision, discoveryRevision,
        leverRevision, levelBoundary = ReadPanelRevisions()
    local staticKey = type(staticContext) == "table" and staticContext.key or nil
    if selectedOK and revisionsOK and staticKey ~= nil then
        local previewPlan, previewWishlist, fingerprint = SelectedPreview(
            selectionId, selectionEpoch, selectionRevision, catalog,
            staticContext)
        fingerprint = fingerprint or ActiveFingerprint(staticContext)
        local exactOK, exactEpoch, exactRevision =
            ReadExactRevision(fingerprint)
        if exactOK and SamePanelProgressKey(panelProgressCache,
            activePlan, catalog, staticKey, selectionId, selectionEpoch,
            selectionRevision, slotsRevision, activeRevision,
            grantedRevision, ownedRevision, wishlistRevision,
            catalogRevision, lockedRevision, lockedLocalRevision,
            discoveryRevision, leverRevision, levelBoundary,
            exactEpoch, exactRevision) then
            return panelProgressCache.value
        end
        if exactOK then
            local value
            if previewPlan and previewWishlist then
                value = BuildProgress(previewPlan, owned, slots, catalog,
                    previewWishlist, selectionId, nil, lockedOverride)
            else
                value = BuildProgress(activePlan, owned, slots, catalog,
                    nil, nil, staticContext, lockedOverride)
            end
            StorePanelProgressKey(panelProgressCache, value,
                activePlan, catalog, staticKey, selectionId, selectionEpoch,
                selectionRevision, slotsRevision, activeRevision,
                grantedRevision, ownedRevision, wishlistRevision,
                catalogRevision, lockedRevision, lockedLocalRevision,
                discoveryRevision, leverRevision, levelBoundary,
                exactEpoch, exactRevision)
            return value
        end
    end

    -- Compatibility path for partial/injected facades without the complete
    -- scalar revision contract. It retains the established defensive reads.
    local community = Nexus.CommunityBuilds
    local build = community and community.GetSelectedBuildForPanel
        and community.GetSelectedBuildForPanel()
    if build and type(build.echoes) == "table" and #build.echoes > 0 then
        local wishlist = {
            name=build.title or "Community Build", entries=build.echoes,
        }
        local previewPlan = Strategy.Compile(catalog, wishlist, Store.Settings())
        return BuildProgress(previewPlan, owned, slots, catalog, wishlist,
            build.id, nil, lockedOverride)
    end
    return BuildProgress(activePlan, owned, slots, catalog,
        nil, nil, staticContext, lockedOverride)
end

local function CopyDisplay(value)
    local viewModel = EnsureMainViewModel and EnsureMainViewModel()
    return viewModel and viewModel.Copy(value) or value
end

local function DisplayCall(callback, ...)
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, ...)
    return ok and value or nil
end

-- Inclusive sub-step timers inside hud.prepare (Performance paths
-- hud.phase.*, aggregate-only). Nil while Performance is off or has no clock.
local function HudPhaseBegin(name)
    local performance = Nexus.Performance
    return performance and performance.Begin and performance.Begin(name) or nil
end
local function HudPhaseFinish(name, startedAt)
    local performance = startedAt ~= nil and Nexus.Performance
    if performance and performance.Finish then performance.Finish(name, startedAt) end
end

-- Main owns every service read used by the adaptive HUD. Panel receives only
-- this defensive display snapshot and never reaches back into data services
-- while rendering it.
-- `base` is always lastPanelInput: Main's private copy of the panel input,
-- which nothing mutates, so it is read here without another copy. The view
-- model takes its own snapshot of the complete input.
local function BuildHudDisplayModel(base)
    local viewModel = EnsureMainViewModel and EnsureMainViewModel()
    if not viewModel then return type(base) == "table" and base or {} end
    local baseSnapshot = type(base) == "table" and base or {}
    local input = {base=baseSnapshot,status=StatusLine()}
    local phaseStarted = HudPhaseBegin("hud.phase.assignment")
    local assignment=Adapter.AssignedWishlist and DisplayCall(Adapter.AssignedWishlist)
    HudPhaseFinish("hud.phase.assignment", phaseStarted)
    if assignment then
        input.assignment={state=assignment.state,note=assignment.note,name=assignment.name,emptySlot=assignment.emptySlot}
    end
    if baseSnapshot.level == nil then
        input.level = DisplayCall(Adapter and Adapter.Level) or 0
    end

    local updates = Nexus.Updates
    input.updateNotice = viewModel.Copy(
        updates and DisplayCall(updates.GetVisibleNotice))
    if input.updateNotice and updates then input.releaseUrl = DisplayCall(updates.ReleaseUrl) end

    local server = Nexus.ServerStatus
    input.useServerStatus = server and DisplayCall(server.IsUsingNexusHud) and true or false
    if input.useServerStatus then
        input.serverStatus = viewModel.Copy(DisplayCall(server.GetSummary))
    end

    local capture = Nexus.DpsCapture
    local player = UnitName and UnitName("player") or nil
    -- Display only: the name this same read returned, kept when it is a
    -- nonempty string other than the client's Unknown placeholder. It grants
    -- no identity, owner or Store authority; no other game read is made.
    if type(player) == "string" and player ~= "" and player ~= "Unknown"
        and not (type(UNKNOWNOBJECT) == "string"
            and player == UNKNOWNOBJECT) then
        input.character = player
    end
    -- Presentation fact only: this same validated capture (nil included)
    -- for the HUD's session-scoped destination cache. No other read; no
    -- model, Store or assignment change.
    local destinationPanel = Panel or Nexus.Panel
    if destinationPanel then
        DisplayCall(destinationPanel.ObserveDestinationCharacter, input.character, "capture")
    end
    local progress = type(baseSnapshot.progress) == "table"
        and baseSnapshot.progress or {}
    local echoes = type(progress.dpsEchoes) == "table" and progress.dpsEchoes or nil
    phaseStarted = HudPhaseBegin("hud.phase.projection")
    local projection = capture
        and type(capture.GetSharedHudProjection) == "function"
        and DisplayCall(capture.GetSharedHudProjection, player, echoes) or nil
    HudPhaseFinish("hud.phase.projection", phaseStarted)
    if type(projection) == "table" then
        -- Detached, read-only records retained by DpsCapture for the current
        -- DPS state; the view model copies them into its snapshot.
        input.bestDps = projection.bestDps
        input.performance = {dummy={},lk={}}
        local performance = type(projection.performance) == "table"
            and projection.performance or nil
        if echoes and performance then
            local dummy = performance.dummy or {}
            local lk = performance.lk or {}
            input.performance.dummy.personal = dummy.personal
            input.performance.lk.personal = lk.personal
            input.performance.dummy.global = dummy.global
            input.performance.lk.global = lk.global
        end
        phaseStarted = HudPhaseBegin("hud.phase.view-model")
        local model = viewModel.BuildHudDisplayModel(input)
        HudPhaseFinish("hud.phase.view-model", phaseStarted)
        return model
    end
    -- Compatibility path for injected facades without the projection. They
    -- receive a copy of the Echo set, never Main's private panel input.
    echoes = echoes and viewModel.Copy(echoes)
    input.bestDps = {
        dummy=viewModel.Copy(capture and DisplayCall(
            capture.GetCharacterBest, "dummy", player)),
        lk=viewModel.Copy(capture and DisplayCall(
            capture.GetCharacterBest, "lk", player)),
        info=viewModel.Copy(capture and DisplayCall(capture.GetPlayerInfo, player)),
    }
    input.performance = {dummy={},lk={}}
    if capture and echoes then
        input.performance.dummy.personal = viewModel.Copy(DisplayCall(
            capture.GetPersonalBestForEchoes, echoes, "dummy"))
        input.performance.lk.personal = viewModel.Copy(DisplayCall(
            capture.GetPersonalBestForEchoes, echoes, "lk"))
        local dummyRows = DisplayCall(capture.GetLeaderboardForEchoes, echoes, "dummy")
        local lkRows = DisplayCall(capture.GetLeaderboardForEchoes, echoes, "lk")
        input.performance.dummy.global = viewModel.Copy(
            type(dummyRows) == "table" and dummyRows[1] or nil)
        input.performance.lk.global = viewModel.Copy(
            type(lkRows) == "table" and lkRows[1] or nil)
    end
    return viewModel.BuildHudDisplayModel(input)
end

local function PrepareHudDisplayModel(base)
    local performance = Nexus and Nexus.Performance
    if performance and type(performance.Measure) == "function" then
        return performance.Measure("hud.prepare", BuildHudDisplayModel, base)
    end
    return BuildHudDisplayModel(base)
end

local function PreparePanelModel(base, source)
    local ok, prepared = pcall(PrepareHudDisplayModel, base)
    if not ok then
        RecordError(source .. ".Prepare", prepared)
        return nil, prepared
    end
    return prepared
end

local function RenderPreparedPanel(prepared, source)
    local ok, result = pcall(Panel.Render, prepared)
    if not ok then
        RecordError(source .. ".Render", result)
        return false, result
    end
    return result ~= false
end

local function RenderPanel(base)
    lastPanelInput = CopyDisplay(base)
    local prepared, prepareError = PreparePanelModel(
        lastPanelInput, "Main.RenderPanel")
    if not prepared then error(prepareError, 0) end
    local rendered, renderError = RenderPreparedPanel(
        prepared, "Main.RenderPanel")
    if renderError then error(renderError, 0) end
    return rendered
end

function Nexus.RefreshHudView()
    if not Panel or type(Panel.Render) ~= "function" then
        return false
    end
    if not lastPanelInput then return false end
    local viewModel = EnsureMainViewModel and EnsureMainViewModel()
    if viewModel then viewModel.NoteRefresh() end
    local prepared = PreparePanelModel(lastPanelInput, "Main.RefreshHudView")
    if not prepared then return false end
    return RenderPreparedPanel(prepared, "Main.RefreshHudView")
end

local function RequestFirstHudView()
    if lastPanelInput then return Nexus.RefreshHudView() end
    -- Manual Show/Toggle can precede the first ordinary automation snapshot.
    -- Request that existing bounded owner and keep Panel hidden; never run a
    -- second provider loop or a stateful full Step from a visibility callback.
    RequestRecompute()
    return false
end

function Nexus.HudSnapshotStats()
    local viewModel = EnsureMainViewModel and EnsureMainViewModel()
    return viewModel and viewModel.Stats()
        or {builds=0,refreshes=0,rebuilds=0,skipped=0,copiedTables=0}
end

-- Renders the panel with just status + progress, no board cards. Used at
-- every point in Step() where StepRun isn't running this tick (level 1,
-- level 80 with no board, or catalog not yet loaded) -- otherwise the
-- panel only ever refreshes while an echo board is live and freezes
-- showing stale leveling-era content the rest of the time, which breaks
-- both "check status at level 80" and "alt-tab between characters".
-- All args may be nil; WishlistProgress/LoadoutCoverage are null-safe.
local function RenderIdlePanel(plan, owned, slots, catalog, staticContext,
    lockedOverride)
    local settings = Store.Settings()
    local okAuto, autoWhy = AutoAllowed()
    local runtime = Automation()
    local auto = (runtime and runtime.AutoEnabled()) or false
    -- What Auto is doing now, as on the board path: from the accessor the
    -- runtime publishes for passive readers (memory only; it creates and
    -- steps no runtime, calls no gate and reads nothing from the game).
    local accessor, okEffective, effective = Nexus.AutomationEffectiveState, false, nil
    if type(accessor) == "function" then okEffective, effective = pcall(accessor) end
    if not okEffective or type(effective) ~= "table" then effective = nil end
    local model = {
        status = StatusLine(),
        cards = {},
        recommendation = "",
        progress = BuildPanelProgress(plan, owned, slots, catalog,
            staticContext, lockedOverride),
        level = Adapter.Level(),
        auto = auto,
        -- A wait that is not a normal short answer is named, not hidden.
        paused = auto and (not okAuto and autoWhy and tostring(autoWhy)
            or effective and effective.hold and effective.reason) or nil,
        effective = effective and { state = effective.state,
            reason = effective.reason, hold = effective.hold } or nil,
        version = Nexus.VERSION,
    }
    if Nexus.OrbGuidance then
        model.orbGuidance = Nexus.OrbGuidance.Project(Nexus.OrbGuidance.Observe(
            model.progress, runtime and runtime.PendingIntentState and runtime.PendingIntentState(),
            plan and not plan.advisorOnly,
            {skipHorizon = runtime and runtime.WorldLeaving and runtime.WorldLeaving() or false}))
    end
    RenderPanel(model)
end

------------------------------------------------------------------------
-- Init + events + slash
------------------------------------------------------------------------


EnsureAutomationRuntime = function()
    if AutomationRuntime then return AutomationRuntime end
    local internals = Nexus.MainInternals
    local factory = internals and internals.AutomationRuntime
    if not (factory and type(factory.New) == "function") then return nil end
    local viewModel = EnsureMainViewModel and EnsureMainViewModel()
    if not viewModel then return nil end
    AutomationRuntime = factory.New({
        nexus=Nexus,model=Model or Nexus.Model,policy=Policy or Nexus.Policy,
        ratchet=Ratchet or Nexus.Ratchet,strategy=Strategy or Nexus.Strategy,
        store=Store or Nexus.Store,adapter=Adapter or Nexus.GameAdapter,
        readout=Readout or Nexus.Readout,
        defaultProfile=DefaultProfile or Nexus.DefaultProfile,
        wishlistModel=assert(Nexus.WishlistModel,
            "WishlistModel unavailable").New(),
        viewModel=viewModel,renderPanel=RenderPanel,renderIdlePanel=RenderIdlePanel,
        buildProgress=BuildProgress,buildPanelProgress=BuildPanelProgress,
        appendAudit=AppendAudit,appendAutoLockEvent=AppendAutoLockEvent,
        print=Print,recordError=RecordError,now=GetTime,
        -- The raw status line: Panel owns its user-text presentation and
        -- converts it once (UserText.Message is not idempotent).
        onStatus=function(value)
            if Panel and Panel.SetStatus then Panel.SetStatus(value) end
        end,
    })
    return AutomationRuntime
end

-- Main retains the public facades while one passive internal owner constructs
-- diagnostic pages, retained audit entries, clear routing, and export jobs.
EnsureMainDiagnostics = function()
    if MainDiagnostics then return MainDiagnostics end
    local internals = Nexus.MainInternals
    local factory = internals and internals.Diagnostics
    if not (factory and type(factory.New) == "function") then return nil end
    MainDiagnostics = factory.New({
        nexus=Nexus,
        adapter={
            Catalog=function(...) return (Adapter or Nexus.GameAdapter).Catalog(...) end,
            Wishlist=function(...) return (Adapter or Nexus.GameAdapter).Wishlist(...) end,
            WishlistNote=function(...) return (Adapter or Nexus.GameAdapter).WishlistNote(...) end,
            LockedOwned=function(...) return (Adapter or Nexus.GameAdapter).LockedOwned(...) end,
            Owned=function(...) return (Adapter or Nexus.GameAdapter).Owned(...) end,
            Slots=function(...) return (Adapter or Nexus.GameAdapter).Slots(...) end,
            Charges=function(...) return (Adapter or Nexus.GameAdapter).Charges(...) end,
            Level=function(...) return (Adapter or Nexus.GameAdapter).Level(...) end,
            LevelBurstStats=function(...)
                local owner = Adapter or Nexus.GameAdapter
                return owner.LevelBurstStats and owner.LevelBurstStats(...) or nil
            end,
        },
        model=Model or Nexus.Model,
        strategy=Strategy or Nexus.Strategy,
        store=Store or Nexus.Store,
        wishlistWithLockTargets=WishlistWithLockTargets,
        lockDesignTargetsFor=LockDesignTargetsFor,
        effectiveFlags=EffectiveFlags,
        errorText=ErrorText,
        now=GetTime,
        getAutoEnabled=function() local r=Automation(); return r and r.AutoEnabled() or false end,
        getAutoLockTrace=function() local r=Automation(); return r and r.LastAutoLockTrace() or {at=0,lines={}} end,
        getAuditRunId=function() local r=Automation(); return r and r.AuditRunId() or 0 end,
        -- Only the run-status keys are read and cleared through these. A
        -- read-only saved root keeps its own; the session's live in the Store
        -- owner's session-only table.
        getDatabase=function()
            local writable = Nexus.MainInternals and Nexus.MainInternals.WritableRootV1
            if type(writable) ~= "function" then return NexusDB end
            return writable(nil, {"lastSaveRefusal", "lastSaveStatus", "auditRunCounter"})
        end,
        ensureDatabase=function()
            NexusDB = NexusDB or {}
            local writable = Nexus.MainInternals and Nexus.MainInternals.WritableRootV1
            if type(writable) ~= "function" then return NexusDB end
            return writable(NexusDB, {"lastSaveRefusal", "lastSaveStatus", "auditRunCounter"})
        end,
        resetAuditState=function()
            local runtime=Automation(); if runtime then runtime.ResetAuditState() end
        end,
        getPageProvider=function() return Nexus.GetDiagnosticPageText end,
    })
    return MainDiagnostics
end

function Nexus.NewAIExportCoroutine()
    local diagnostics = EnsureMainDiagnostics()
    if diagnostics then return diagnostics.NewAIExportCoroutine() end
    return coroutine.create(function() return "" end)
end

local function LogViewerProvider(tabKey)
    local diagnostics = EnsureMainDiagnostics()
    return diagnostics and diagnostics.GetPageText(tabKey)
        or ("unknown tab: " .. tostring(tabKey))
end

local function ClearDiagnosticLogs(tabKey)
    local diagnostics = EnsureMainDiagnostics()
    return diagnostics and diagnostics.Clear(tabKey) or false
end

function Nexus.GetDiagnosticPageText(tabKey)
    return LogViewerProvider(tabKey)
end

function Nexus.RefreshPanel()
    local lifecycle = Lifecycle()
    return lifecycle and lifecycle.RefreshPanel() or false
end

local function BindLifecycleDependencies()
    Model = Nexus.Model
    Policy = Nexus.Policy
    Ratchet = Nexus.Ratchet
    Strategy = Nexus.Strategy
    Store = Nexus.Store
    Adapter = Nexus.GameAdapter
    Readout = Nexus.Readout
    Panel = Nexus.Panel
    JournalTab = Nexus.JournalTab
    DefaultProfile = Nexus.DefaultProfile
    local internals = Nexus.MainInternals
    local automationFactory = internals and internals.AutomationRuntime
    local commandsFactory = internals and internals.Commands
    local diagnosticsFactory = internals and internals.Diagnostics
    local viewModelFactory = internals and internals.ViewModel
    if not (Model and Policy and Ratchet and Strategy and Store
        and Adapter and Readout and Panel and DefaultProfile
        and Nexus.DiagnosticLogs and diagnosticsFactory
        and type(diagnosticsFactory.New) == "function"
        and automationFactory and type(automationFactory.New) == "function"
        and commandsFactory and type(commandsFactory.New) == "function"
        and viewModelFactory and type(viewModelFactory.New) == "function") then
        return nil
    end
    return {
        Model=Model, Policy=Policy, Ratchet=Ratchet, Strategy=Strategy,
        Store=Store, Adapter=Adapter, Readout=Readout, Panel=Panel,
        JournalTab=JournalTab, DefaultProfile=DefaultProfile,
    }
end

EnsureMainLifecycle = function()
    if MainLifecycle then return MainLifecycle end
    local internals = Nexus.MainInternals
    local factory = internals and internals.Lifecycle
    if not (factory and type(factory.New) == "function") then return nil end
    MainLifecycle = factory.New({
        nexus=Nexus,
        bindDependencies=BindLifecycleDependencies,
        ensureAutomation=function() return Automation() end,
        print=Print,
        printText=PrintText,
        recordError=RecordError,
        recordStoreError=RecordStoreError,
        errorText=ErrorText,
        requestRecompute=RequestRecompute,
        refreshHud=function() return Nexus.RefreshHudView() end,
        requestFirstHud=RequestFirstHudView,
        database=function() return NexusDB end,
        logViewerProvider=LogViewerProvider,
        clearDiagnosticLogs=ClearDiagnosticLogs,
        now=GetTime,
    })
    return MainLifecycle
end

EH = CreateFrame("Frame")
EH:RegisterEvent("ADDON_LOADED")
EH:RegisterEvent("PLAYER_ENTERING_WORLD")
EH:RegisterEvent("PLAYER_LEAVING_WORLD")
EH:RegisterEvent("PLAYER_LOGOUT")
EH:RegisterEvent("PLAYER_LEVEL_UP")
EH:RegisterEvent("CHAT_MSG_CHANNEL")
EH:RegisterEvent("PLAYER_REGEN_DISABLED")
EH:RegisterEvent("PLAYER_REGEN_ENABLED")
EH:SetScript("OnEvent", function(_, event, ...)
    if event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_LEAVING_WORLD" or event=="PLAYER_LOGOUT" then
        local adapter=Adapter or Nexus.GameAdapter
        local observe=adapter and adapter.ObserveChoiceWorldEvent
        if type(observe)=="function" then pcall(observe,event) end
        -- The HUD's cached destination character holds only inside this
        -- world session: leave/logout block it, entering admits a fresh
        -- existing capture. Presentation only.
        local panel=Panel or Nexus.Panel
        local observeDestination=panel and panel.ObserveDestinationCharacter
        if type(observeDestination)=="function" then pcall(observeDestination,nil,event) end
        -- A loading screen inside this session keeps Auto selected and holds
        -- actions; logout or an unclassified entry turns it OFF.
        if AutomationRuntime and AutomationRuntime.OnWorldEvent(event)=="revoked" and Panel.SetAuto then
            Panel.SetAuto(false)
        end
    end
    local lifecycle = Lifecycle()
    if lifecycle then return lifecycle.OnEvent(event, ...) end
end)
-- CHAT_MSG_WHISPER is not registered here: no handler reads it (the addon
-- whisper handshake is CHAT_MSG_ADDON in SyncWire's own frame), and the
-- registration made every incoming whisper run this dispatcher for nothing.
EH:SetScript("OnUpdate", function(_, elapsed)
    local lifecycle = Lifecycle()
    if lifecycle then return lifecycle.OnUpdate(elapsed) end
end)

local function CommandAuto()
    if Nexus.OrbRuntime and Nexus.OrbRuntime.BlocksOrdinary() then
        Say("command.chat.auto_blocked_by_orb")
        return false
    end
    local runtime = Automation()
    local enabled = runtime and runtime.ToggleAuto() or false
    if not enabled and Nexus.SessionPause and Nexus.SessionPause.IsPaused() then
        Say("command.chat.auto_blocked_by_pause")
        if Panel.SetAuto then Panel.SetAuto(enabled) end
        return
    end
    Say(enabled and "command.chat.automation_on" or "command.chat.automation_off")
    if Panel.SetAuto then Panel.SetAuto(enabled) end
end

local function CommandRestore()
    Say(Adapter.RestoreAutoAccept() and "command.chat.auto_accept_restored"
        or "command.chat.nothing_to_restore")
    RequestRecompute()
end

local function CommandFlags()
    for k, v in pairs(EffectiveFlags()) do Print(k .. " = " .. tostring(v)) end
    local state = Store.State()
    for k, why in pairs(state.flagDemotions or {}) do
        Print("demoted " .. k .. ": " .. tostring(why))
    end
end

-- One bounded line of the retained start-up failure facts, or nil.
local function StartupFailureLine(status)
    local f = type(status) == "table" and status.failure or nil
    if type(f) ~= "table" then return nil end
    local parts = {}
    local function Add(label, value)
        if value ~= nil then parts[#parts + 1] = label .. "=" .. tostring(value) end
    end
    Add("component", f.component); Add("phase", f.phase); Add("map", f.map)
    Add("counter", f.counter)
    if f.count then Add("count at refusal", tostring(f.count) .. " (limit " .. tostring(f.limit) .. "; counting stopped here)") end
    if type(f.counted) == "table" and f.counted.builds ~= nil then
        Add("different builds counted (at least)", f.counted.builds)
    end
    -- The maps are read in this order; counting stops in f.map, so the maps
    -- after it were not read and have no count.
    local counted = type(f.counted) == "table" and f.counted or nil
    if counted then
        local listed, stopped = {}, false
        for _, entry in ipairs({{"overlay", "builds"}, {"bundled", "shipped"},
            {"tombstone", "removal markers"}, {"barrier", "retention markers"}}) do
            listed[#listed + 1] = entry[2] .. " "
                .. (stopped and "not read" or tostring(counted[entry[1]] or 0))
            if entry[1] == f.map then stopped = true end
        end
        Add("keys counted before the stop (at least)", table.concat(listed, ", "))
    end
    Add("source", f.source)
    Add("stage", f.stage); Add("cause", f.cause); Add("detail", f.detail)
    Add("owner", f.owner); Add("row", f.row); Add("legacy", f.legacyClass); Add("error", f.error)
    if f.formatClass then
        Add("saved format", tostring(f.formatClass)
            .. (f.formatVersion and (" " .. tostring(f.formatVersion)) or "")
            .. (f.formatField and (" (" .. tostring(f.formatField) .. ")") or ""))
    end
    if #parts == 0 then return nil end
    return "Startup failure: " .. table.concat(parts, "; ")
end

-- The facts of Nexus.RollingStatusLines (defined below; the diagnostic page
-- keeps its English lines) said in chat through the seam: /nexus status,
-- /nexus policy and /nexus trace. Strategy and policy names are data.
-- Read-only, like the lines.
local function SayRollingStatus()
    local runtime = Automation()
    local status = runtime and runtime.RollingPolicyStatus and runtime.RollingPolicyStatus()
    if status then
        if status.changePending then
            SayFormat("command.chat.rolling_strategy_pending",
                {strategy=tostring(status.inForce), selected=tostring(status.requested)})
        else
            SayFormat("command.chat.rolling_strategy", {strategy=tostring(status.inForce)})
        end
        local policy = status.lastPolicy and tostring(status.lastPolicy)
            or UiText("command.value.rolling_decision_none")
        if status.lastFallback then
            SayFormat("command.chat.rolling_last_decision_fallback",
                {policy=policy, reason=tostring(status.lastFallback)})
        else
            SayFormat("command.chat.rolling_last_decision", {policy=policy})
        end
    end
    local recorder = Nexus.RollRecorder
    local trace = recorder and recorder.Status and recorder.Status()
    if trace then
        SayFormat(trace.enabled and "command.chat.roll_recording_on" or "command.chat.roll_recording_off",
            {saved=tostring(trace.retained or 0), limit=tostring(trace.cap or "?"),
                failed=tostring(trace.failed), dropped=tostring(trace.dropped)})
    end
end

local function CommandStatus()
    local startup=type(Nexus.StartupStatus)=="function" and Nexus.StartupStatus()
    if startup and startup.state~="ready" then
        Say(startup.state=="failed"
            and "command.chat.status_shared_failed"
            or "command.chat.status_shared_preparing")
        local capacity = Nexus.LoadingStatus and type(Nexus.LoadingStatus.CapacityText)=="function"
            and Nexus.LoadingStatus.CapacityText(startup) or nil
        if capacity then Print(capacity) end
        local line = StartupFailureLine(startup)
        if line then Print(line) end
    end
    -- Capacity use of the admitted shared catalog and its saturation record
    -- (read-only, the same lines the Copy summary carries).
    local report = Nexus.SupportReport
    if report and type(report.CatalogCapacityLines) == "function" then
        local ok, lines = pcall(report.CatalogCapacityLines)
        if ok and type(lines) == "table" then
            for _, text in ipairs(lines) do Print((tostring(text):gsub("^%s+", ""))) end
        end
    end
    local catalog = Adapter.Catalog()
    local wishlist = Adapter.Wishlist()
    local slots = Adapter.Slots()
    local owned = Adapter.Owned()
    -- The version, build label and level are data; only the words around
    -- them are reviewed text. Concatenation keeps the former conversions.
    local version, build = "" .. Nexus.VERSION, "" .. Nexus.RuntimeBuildLabel()
    local level = "" .. Adapter.Level()
    SayFormat((Automation() and Automation().AutoEnabled())
        and "command.chat.status_version_auto_on" or "command.chat.status_version_auto_off",
        {version=version, build=build, level=level})
    if wishlist then
        local source = (wishlist.source == "designed" and "Echo Wishlist build")
            or (wishlist.source == "active" and "active loadout") or "wishlist"
        local displayName = DisplayUntrusted(
            (wishlist.name ~= "" and wishlist.name) or "(unnamed)",
            1024, false) or "(unnamed)"
        Print(string.format("TARGET: |cff7fff7f'%s'|r (your %s) -- %d echoes",
            displayName, source, #wishlist.entries))
    else
        local note = Adapter.WishlistNote and Adapter.WishlistNote()
        Print("TARGET: none -- advisor only" .. (note and ("  (" .. note .. ")") or ""))
    end
    if not slots then
        Say("command.chat.status_loadouts_waiting")
    else
        local snapshots, designs = 0, 0
        for _, slot in pairs(slots.bySlot) do
            if type(slot.echoes) == "table" and #slot.echoes > 0 then
                if slot.verified then snapshots = snapshots + 1 else designs = designs + 1 end
            end
        end
        local active = slots.activeSlot
        if active ~= 0 and slots.bySlot[active] then
            local slot = slots.bySlot[active]
            local slotName = (slot.name ~= "" and slot.name) or "?"
            local legacy = string.format("ACTIVE slot %d '%s': %s, %d echoes", active,
                slotName,
                slot.verified and "Saved Build with confirmed saved-run behavior"
                    or "desired plan (not a saved-run guarantee)",
                #slot.echoes)
            SayFormat(slot.verified and "command.chat.status_active_saved_build"
                or "command.chat.status_active_desired_plan",
                {slot=string.format("%d", active), name=string.format("%s", slotName),
                    count=Count(#slot.echoes)}, legacy)
        else
            Say("command.chat.status_active_none")
        end
        SayFormat("command.chat.status_readable", {saved=Count(snapshots),
            plans=Count(designs)})
        if wishlist and Ratchet and Ratchet.BestSlot then
            local plan = Strategy.Compile(catalog, wishlist, Store.Settings())
            local best = Ratchet.BestSlot(slots, plan, catalog)
            if best then
                SayFormat("command.chat.status_activation_candidate", {slot="" .. best})
            else
                Say("command.chat.status_no_saved_build")
            end
        end
    end
    Print(string.format("OWNED this run: %d echoes (%s).", owned.distinct or 0,
        owned.synced and "synced" or "not synced yet"))
    SayRollingStatus()
end

local function CommandWishlist()
    local wishlist = Adapter.Wishlist()
    if not wishlist then
        local note = Adapter.WishlistNote and Adapter.WishlistNote()
        if note then
            Print(note)
        else
            Say("command.chat.wishlist_none_detected")
            SayLines("command.chat.wishlist_design_hint")
        end
        return
    end
    local catalog = Adapter.Catalog()
    local source = UiText((wishlist.source == "designed" and "command.value.wishlist_source_designed")
        or (wishlist.source == "active" and "command.value.wishlist_source_active")
        or "command.value.wishlist_source_other")
    local families = {}
    for _, echo in ipairs(wishlist.entries) do families[echo.family] = true end
    local familyCount = 0
    for _ in pairs(families) do familyCount = familyCount + 1 end
    local unnamed = UiText("main.value.unnamed_wishlist")
    local displayName = DisplayUntrusted(
        (wishlist.name ~= "" and wishlist.name) or unnamed,
        1024, false) or unnamed
    -- The name keeps its code-owned colour and quotes around it (a slot).
    SayFormat("command.chat.wishlist_reading",
        {name="|cff7fff7f'" .. displayName .. "'|r", source=source,
            echoes=Count(#wishlist.entries), families=Count(familyCount)},
        string.format("reading |cff7fff7f'%s'|r (from %s) -- %d echoes, %d families",
            displayName, source, #wishlist.entries, familyCount))
    local names = {}
    for _, echo in ipairs(wishlist.entries) do
        local row = catalog and catalog.rows[echo.spellId]
        names[#names + 1] = (row and row.name
            or UiFormat("main.value.unknown_spell", {id="" .. echo.spellId}))
            .. (echo.stacks > 1 and (" x" .. echo.stacks) or "")
    end
    table.sort(names)
    -- Data (Echo names); in a translation they may hold translated labels.
    PrintText("  " .. table.concat(names, ", "), ActiveSource())
end

local function CommandProgress(showMissing)
    local catalog = Adapter.Catalog()
    local wishlist = Adapter.Wishlist()
    local owned = Adapter.Owned()
    if not wishlist then
        Say("command.chat.progress_no_wishlist")
        return
    end
    local plan = Strategy.Compile(catalog,
        WishlistWithLockTargets(wishlist, catalog), Store.Settings())
    local have, total, missing = WishlistProgress(plan, owned, catalog)
    local percent = (total > 0) and math.floor(have / total * 100 + 0.5) or 0
    -- The coloured have/total pair is a code-owned slot.
    SayFormat("command.chat.progress_this_run",
        {progress=string.format("|cff7fff7f%d/%d|r", have, total),
            percent=string.format("%d", percent), short=Count(#missing)})
    if showMissing and #missing > 0 then
        PrintText("  " .. table.concat(missing, ", "), ActiveSource())
    end
end

local function CommandDps()
    local capture = Nexus.DpsCapture
    if not capture then Say("command.chat.dps_module_missing"); return end
    if capture.IsDetailsAvailable() then
        SayColored("command.chat.dps_active", "|cff4dff80")
        Say("command.chat.dps_record_hint")
    else
        SayColored("command.chat.dps_details_missing", "|cffff9040")
        Say("command.chat.dps_install_details")
    end
    if Nexus.lastDpsNote then
        local identity = Nexus and Nexus.Identity
        local displayNote = identity and identity.DisplaySafeText
            and identity.DisplaySafeText(
                Nexus.lastDpsNote, 2048, true, true) or nil
        if displayNote then
            SayFormat("command.chat.dps_last_session", {note=displayNote},
                "Last session: " .. displayNote)
        end
    end
    local wishlist = Adapter.Wishlist()
    if wishlist and capture.GetEchoKey then
        local key = tostring(capture.GetEchoKey(wishlist.entries))
        SayFormat("command.chat.dps_selected_key", {key=key}, "Selected wishlist key: " .. key)
    end
    if capture.GetCurrentEchoKey then
        local key = tostring(capture.GetCurrentEchoKey())
        SayFormat("command.chat.dps_current_key", {key=key}, "Current tracked Echo key: " .. key)
    end
    Say("command.chat.dps_log_hint")
end

local function CommandSync()
    if Nexus.Sync then
        local ok, err = Nexus.Sync.RequestSync()
        -- A reason Sync returns is its own text and is shown as before.
        if ok == nil and not err then
            Say("command.chat.sync_preparing")
        elseif ok == nil or not ok then
            Print(tostring(err))
        else
            Say("command.chat.sync_requested")
        end
    else
        Say("command.chat.sync_unavailable")
    end
end

-- MASTER-RC-001 (amendment 10). Store.State() is a DURABLE_READ returning a
-- defensive copy; writes must go through StoreAuthorityOwnerV1.UpdateStateV1,
-- the architecture's counted private mutation entry (lines 1907-1912).
local function UpdateStoreState(mutator)
    local internals = Nexus and Nexus.MainInternals
    local owner = type(internals) == "table" and internals.StoreAuthorityOwner
    -- Honour the INJECTED Store. A stub Store must never resolve the real
    -- durable writer -- writing through the global owner would bypass
    -- dependency injection, which tests/run_wishlist_controller_parity.lua
    -- exists to catch. A stub exposes only the surface it needs (typically
    -- State/Settings); a real Store module exposes the full nine-export facade.
    -- Identity alone is not usable here: fixtures re-`dofile` core/Store.lua,
    -- which rebinds Nexus.Store and the owner while an already-initialized
    -- consumer still holds the previous module, so a real Store legitimately
    -- fails an identity check.
    local realStore = type(Store) == "table"
        and type(Store.Init) == "function"
        and type(Store.CurrentOwnerKey) == "function"
    if realStore and type(owner) == "table"
        and type(owner.UpdateStateV1) == "function" then
        return owner.UpdateStateV1(mutator)
    end
    -- No authorized owner for THIS Store. Fall back to whatever state table the
    -- injected facade exposes, which is exactly the pre-migration behaviour for
    -- such a Store.
    local injected = Store and Store.State and Store.State()
    if type(injected) ~= "table" then return nil end
    return true, mutator(injected)
end

local function CommandErr()
    local latest
    if Nexus.Errors and type(Nexus.Errors.Latest) == "function" then
        local ok, retained = pcall(Nexus.Errors.Latest)
        if ok then latest = retained end
    end
    Print(latest and latest.message or ErrorText(Nexus.lastError))
end

-- `settings` is the Store owner's settings (Store.Settings). For a read-only
-- saved root that is the session's own validated copy, so the change is real
-- for this session and the reply says it is not saved.
local function CommandAnchor(settings, argument)
    local readOnly = Nexus.MainInternals and Nexus.MainInternals.SavedRootReadOnlyV1
    local sessionOnly = type(readOnly) == "function" and readOnly() and true or false
    if argument == "off" or argument == nil then
        settings.anchorSpellId = nil
        Say(sessionOnly and "command.chat.anchor_cleared_session" or "command.chat.anchor_cleared")
    else
        settings.anchorSpellId = tonumber(argument)
        SayFormat(sessionOnly and "command.chat.anchor_set_session" or "command.chat.anchor_set",
            {spell=tostring(settings.anchorSpellId)})
    end
    RequestRecompute()
end

-- Rolling strategy and local recording lines (status page, /nexus policy,
-- /nexus trace). Read-only; nothing here changes a setting.
function Nexus.RollingStatusLines()
    local lines = {}
    local runtime = Automation()
    local status = runtime and runtime.RollingPolicyStatus and runtime.RollingPolicyStatus()
    if status then
        local text = "rolling strategy: " .. tostring(status.inForce)
        if status.changePending then
            text = text .. " (selected: " .. tostring(status.requested) .. ", applies at the next safe action boundary)"
        end
        lines[#lines + 1] = text
        lines[#lines + 1] = "rolling strategy last decision: " .. tostring(status.lastPolicy or "none")
            .. (status.lastFallback and (" (fell back to the released policy: " .. tostring(status.lastFallback) .. ")") or "")
    end
    local recorder = Nexus.RollRecorder
    local trace = recorder and recorder.Status and recorder.Status()
    if trace then
        lines[#lines + 1] = string.format("roll recording: %s, %s saved records (limit %s), %s failed, %s dropped",
            trace.enabled and "on (local only)" or "off", tostring(trace.retained or 0), tostring(trace.cap or "?"),
            tostring(trace.failed), tostring(trace.dropped))
    end
    return lines
end

-- /nexus reference (and any unknown command): the full reference pages, the
-- optional manual, with the command summary. Read-only, also during loading.
local function CommandReference()
    if Nexus.Help then Nexus.Help.Show() end
    -- The command syntax is protocol: it is a code-owned slot, never translated.
    SayFormat("command.chat.reference_commands",
        {commands="/nexus help | guide | reference | editor | panel | status | loading | orbs | policy | trace"})
    SayFormat("command.chat.reference_rolling_permissions",
        {reroll="/nexus reroll on|off", freeze="/nexus freeze on|off"})
    SayFormat("command.chat.reference_rolling_strategy",
        {policy="/nexus policy adaptive|released", trace="/nexus trace"})
    Say("command.chat.reference_session_pause")
end

-- /nexus help and /nexus tutorial (design/current "Nexus Setup Alternative":
-- Help and Setup open the coach at the step you were on): Guided setup
-- through Help's own route (Help.OpenGuide), also during loading. Opening it
-- changes nothing. The reply says where the full manual moved, as the design
-- asks for this changed habit. When the coach does not open (an Auto warning
-- waits for its answer, or it is not loaded), Help.OpenGuide has printed why
-- and nothing else opens: the reply only names the retry and the separate
-- /nexus reference, which stays the player's own choice.
local function CommandHelp()
    local help = Nexus.Help
    if not (help and type(help.OpenGuide) == "function") then
        Say("command.chat.help_unavailable")
        return
    end
    if help.OpenGuide() == true then
        Say("command.chat.help_opened")
        return
    end
    Say("command.chat.help_not_opened")
end

EnsureMainCommands = function()
    if MainCommands then return MainCommands end
    local internals = Nexus.MainInternals
    local factory = internals and internals.Commands
    if not (factory and type(factory.New) == "function") then return nil end
    MainCommands = factory.New({
        isInitialized=function()
            local lifecycle = Lifecycle()
            return lifecycle and lifecycle.IsInitialized() or false
        end,
        notInitialized=function()
            local status=type(Nexus.StartupStatus)=="function" and Nexus.StartupStatus()
            if status and status.state=="failed" then
                -- The reason is a code (data); its absent default is reviewed text.
                local reason = status.reason and tostring(status.reason)
                    or UiText("command.value.startup_validation_failed")
                SayFormat("command.chat.startup_stopped", {reason=reason},
                    "Startup stopped: "..reason)
            else
                Say("command.chat.startup_preparing")
            end
            local line = status and status.state=="failed" and StartupFailureLine(status)
            if line then Print(line) end
            if status and status.reason=="LEGACY_DISPOSITION_REAUTH_REQUIRED" then
                local lifecycle=Lifecycle()
                local recovery=lifecycle and lifecycle.LegacyRecoveryStatus and lifecycle.LegacyRecoveryStatus()
                if recovery and recovery.state=="preserved" then
                    Say("command.chat.legacy_preserved_reload")
                elseif recovery and recovery.state=="waiting" then
                    Say("command.chat.legacy_waiting")
                end
            end
        end,
        prepare=function() return Store.Settings() end,
        callbacks={
            -- Explicit keep-current / preserve-legacy recovery. Answered before
            -- the initialization gate (see MainCommands). The coordinator owns
            -- every decision; this only words the result.
            legacy=function(_,normalized)
                local lifecycle=Lifecycle()
                if not (lifecycle and lifecycle.LegacyRecoveryOffer) then
                    Say("command.chat.legacy_not_waiting")
                    return
                end
                local code=normalized:match("^legacy%s+keep%s+(%S+)%s*$")
                if normalized~="legacy" and not normalized:match("^legacy%s+keep%s*$") and not code then
                    Say("command.chat.legacy_usage")
                    return
                end
                local result
                if code then
                    result=lifecycle.ConfirmLegacyRecovery(code)
                else
                    result=lifecycle.LegacyRecoveryOffer()
                end
                local state=result.state
                if state=="notWaiting" then
                    Say("command.chat.legacy_not_waiting")
                elseif state=="offer" then
                    Say("command.chat.legacy_offer_found")
                    local resultCode = tostring(result.code)
                    SayFormat("command.chat.legacy_offer_size",
                        {tables=string.format("%d", tonumber(result.tables) or 0),
                            bytes=string.format("%d", tonumber(result.bytes) or 0), code=resultCode},
                        string.format("Found: %d tables, about %d bytes of data. Code: %s",
                            tonumber(result.tables) or 0, tonumber(result.bytes) or 0, resultCode))
                    Say("command.chat.legacy_offer_effect")
                    -- The command with its code is protocol: a code-owned slot.
                    local command = "/nexus legacy keep "..resultCode
                    SayFormat("command.chat.legacy_offer_confirm", {command=command},
                        "To keep your current setup and do this, type: "..command)
                    Say("command.chat.legacy_offer_reload")
                elseif state=="blocked" then
                    local reason = tostring(result.reason)
                        ..(result.detail and (": "..tostring(result.detail)) or "")
                    SayFormat("command.chat.legacy_blocked", {reason=reason},
                        "The older saved data cannot be kept automatically ("..reason
                            .."). Nothing was changed. Your current setup is unchanged.")
                elseif state=="alreadyPreserved" or (state=="preserved" and not code) then
                    Say("command.chat.legacy_already_preserved")
                elseif state=="preserved" then
                    local resultCode = tostring(result.code)
                    SayFormat("command.chat.legacy_preserved_code", {code=resultCode},
                        "Older data preserved separately (code "..resultCode.."). Your current setup is unchanged. Type /reload to start Nexus with it.")
                else
                    if result.reason=="ROLLBACK_INCOMPLETE" then
                        Say("command.chat.legacy_rollback_incomplete")
                    else
                        local reason = tostring(result.reason)
                        SayFormat("command.chat.legacy_not_changed", {reason=reason},
                            "Older data was not changed: "..reason..".")
                    end
                    if result.reason=="INPUT_DRIFT" then
                        Say("command.chat.legacy_input_drift")
                    elseif result.reason=="NO_OFFER" or result.reason=="CODE_MISMATCH" then
                        Say("command.chat.legacy_current_code")
                    end
                end
            end,
            orbs=function() if Nexus.OrbPanel then Nexus.OrbPanel.Show() end end,
            report=function()
                -- This command exists for a broken install, so it says
                -- something even when its own view did not load.
                if Nexus.SupportReportUI then
                    Nexus.SupportReportUI.Show()
                else
                    -- Without the seam (a broken install) the English stays.
                    local text = Nexus.Localization
                        and UiText("command.chat.report_view_missing")
                        or ("the support report view is not "
                        .. "loaded. Reinstall the addon folder, or send the "
                        .. "text of the error you are seeing.")
                    print("|cffff6060Nexus:|r " .. text)
                end
            end,
            loading=function()
                if Nexus.LoadingStatus then Nexus.LoadingStatus.Show() end
            end,
            -- Session pause (answered before the initialization gate). Only
            -- the session barrier changes: no step, save, send or toggle.
            sessionPause=function(_,normalized)
                local pause=Nexus.SessionPause
                if not pause then Say("command.chat.pause_unavailable");return end
                local was=pause.IsPaused()
                if normalized=="pause" then
                    pause.Pause()
                    Say(was and "command.chat.pause_already" or "command.chat.pause_started")
                elseif normalized=="resume" then
                    pause.Resume()
                    Say(was and "command.chat.resume_done" or "command.chat.resume_not_paused")
                elseif pause.IsPaused() then
                    Say("command.chat.pause_status_paused")
                else
                    Say("command.chat.pause_status_running")
                end
            end,
            auto=function() CommandAuto() end,
            -- Rolling strategy selector. The saved setting is written at once;
            -- the runtime applies it at the next safe action boundary.
            policy=function(settings,_,value)
                if value=="adaptive" or value=="released" then
                    settings.rollingPolicy=value
                    RequestRecompute()
                    local readOnly=Nexus.MainInternals and Nexus.MainInternals.SavedRootReadOnlyV1
                    local sessionOnly=type(readOnly)=="function" and readOnly() and true or false
                    local text, source = UiFormat("command.chat.policy_selected", {strategy=value})
                    SayWithSessionNote(text, source, sessionOnly)
                elseif value~=nil then
                    SayFormat("command.chat.usage", {usage="/nexus policy adaptive|released"})
                end
                SayRollingStatus()
                if value==nil then
                    Say("command.chat.policy_values")
                end
            end,
            -- Automatic local roll record: open it, switch it, or clear it.
            trace=function(settings,_,value)
                local recorder=Nexus.RollRecorder
                if not recorder then Say("command.chat.trace_recorder_missing") return end
                if value=="off" or value=="on" then
                    settings.rollTrace=(value=="on")
                    local readOnly=Nexus.MainInternals and Nexus.MainInternals.SavedRootReadOnlyV1
                    local sessionOnly=type(readOnly)=="function" and readOnly() and true or false
                    local text, source = UiText(value=="on" and "command.chat.trace_now_on" or "command.chat.trace_now_off")
                    SayWithSessionNote(text, source, sessionOnly)
                elseif value=="clear" then
                    local ok=Nexus.DiagnosticLogs and Nexus.DiagnosticLogs.Clear(recorder.HISTORY)
                    Say(ok and "command.chat.trace_cleared" or "command.chat.trace_clear_failed")
                elseif value~=nil then
                    SayFormat("command.chat.usage", {usage="/nexus trace, /nexus trace on|off|clear"})
                    return
                end
                SayRollingStatus()
                if value==nil then
                    if Nexus.LogViewer then
                        Nexus.LogViewer.Show("trace")
                        Say("command.chat.trace_tab_hint")
                    else
                        Say("command.chat.log_viewer_unavailable")
                    end
                end
            end,
            rollingOption=function(settings,_,argument)
                if not argument or (argument.value~="on" and argument.value~="off") then
                    SayFormat("command.chat.rolling_option_usage", {reroll="/nexus reroll on|off",
                        freeze="/nexus freeze on|off", currentlocks="/nexus currentlocks on|off"})
                    return
                end
                local key=argument.option=="currentlocks" and "useCurrentLocksForUntagged"
                    or argument.option=="reroll" and "autoReroll" or "autoFreeze"
                settings[key]=argument.value=="on"
                RequestRecompute()
                local readOnly=Nexus.MainInternals and Nexus.MainInternals.SavedRootReadOnlyV1
                local sessionOnly=type(readOnly)=="function" and readOnly() and true or false
                local text, source
                if argument.option=="currentlocks" then
                    text, source = UiText(argument.value=="on" and "command.chat.current_locks_on"
                        or "command.chat.current_locks_off")
                else
                    -- The option and its value are the command's own words (protocol).
                    text, source = UiFormat("command.chat.rolling_permission",
                        {option=argument.option, value=argument.value})
                end
                SayWithSessionNote(text, source, sessionOnly)
            end,
            prototype=function()
                Say("command.chat.prototype_intro")
                Print("/nexus reroll on|off | /nexus freeze on|off | /nexus log errors")
                local wire=Nexus.SyncWire and Nexus.SyncWire.Stats()
                if wire then Print("Wire: "..tostring(wire.policy).."; CTL="..tostring(wire.available).."; suspended="..tostring(wire.suspended)) end
                Say("command.chat.prototype_backup")
            end,
            panel=function() Panel.Toggle() end,
            restore=function() CommandRestore() end,
            flags=function() CommandFlags() end,
            status=function() CommandStatus() end,
            wishlist=function() CommandWishlist() end,
            progress=function() CommandProgress(false) end,
            missing=function() CommandProgress(true) end,
            editor=function()
                if Nexus.WishlistEditor then Nexus.WishlistEditor.Toggle()
                else Say("command.chat.editor_unavailable") end
            end,
            syncdebug=function()
                if Nexus.LogViewer then Nexus.LogViewer.Show("sync")
                else Say("command.chat.log_viewer_unavailable") end
            end,
            probe=function(_, _, target)
                if target ~= "" and Nexus.Sync and Nexus.Sync.SendStatusTo then
                    -- A saved Sync mode refusal is reported, never silent.
                    local ok, first, second, third = pcall(Nexus.Sync.SendStatusTo, target)
                    local why = ok and (first == false and second
                        or first == true and second == false and third) or nil
                    if why then Print(tostring(why)) end
                end
            end,
            nameplate=function()
                if Nexus.Nameplate then
                    Say("command.chat.nameplate_active")
                    Say("command.chat.nameplate_tagging")
                else Say("command.chat.nameplate_missing") end
            end,
            dps=function() CommandDps() end,
            sync=function() CommandSync() end,
            builds=function()
                if Nexus.CommunityBuilds then Nexus.CommunityBuilds.Toggle()
                else Say("command.chat.builds_unavailable") end
            end,
            leaderboard=function()
                if Nexus.Leaderboard then Nexus.Leaderboard.Toggle()
                else Say("command.chat.leaderboard_unavailable") end
            end,
            errors=function()
                if Nexus.LogViewer then Nexus.LogViewer.Show("errors")
                else Say("command.chat.log_viewer_unavailable") end
            end,
            performance=function()
                if Nexus.LogViewer then Nexus.LogViewer.Show("perf")
                else Say("command.chat.performance_unavailable") end
            end,
            logclear=function()
                local ok, cleared = pcall(ClearDiagnosticLogs, "state")
                Say(ok and cleared and "command.chat.logclear_done"
                    or "command.chat.logclear_failed")
            end,
            log=function()
                if Nexus.LogViewer then Nexus.LogViewer.Toggle()
                else Say("command.chat.log_viewer_unavailable") end
            end,
            err=function() CommandErr() end,
            undemote=function()
                UpdateStoreState(function(state) state.flagDemotions = {} end)
                RequestRecompute()
                Print("flag demotions cleared (they re-arm on fresh evidence)")
            end,
            overlay=function()
                if Nexus.WishlistOverlay then Nexus.WishlistOverlay.Toggle()
                else Say("command.chat.overlay_unavailable") end
            end,
            anchor=function(settings, _, argument)
                CommandAnchor(settings, argument)
            end,
            help=function() CommandHelp() end,
            reference=function() CommandReference() end,
            -- /nexus guide: the guided setup coach through Help's own route
            -- (Help.OpenGuide), which refuses in chat while an Auto warning
            -- waits. /nexus help and /nexus tutorial open the same coach
            -- (CommandHelp); /nexus reference opens the reference pages.
            guide=function()
                local help = Nexus.Help
                local opened = help and type(help.OpenGuide) == "function"
                    and help.OpenGuide() == true
                Say(opened and "command.chat.guide_opened"
                    or "command.chat.guide_not_opened")
            end,
            update=function()
                local status = Nexus.Updates and Nexus.Updates.Status and Nexus.Updates.Status()
                if not status then Say("command.chat.update_unavailable"); return end
                -- Updates.Status words its detail through the seam and says
                -- whether a translation is in it (detailSource).
                PrintText(status.detail, status.detailSource)
                SayFormat("command.chat.update_releases_page", {url="" .. status.url},
                    "Releases page: " .. status.url)
                if Nexus.Panel and Nexus.Panel.ShowUpdateStatus then Nexus.Panel.ShowUpdateStatus() end
            end,
        },
    })
    return MainCommands
end

SLASH_NEXUS1 = "/nexus"
SLASH_NEXUS2 = "/nx"
SLASH_NEXUS3 = "/wr"   -- legacy alias kept for muscle memory
SlashCmdList["NEXUS"] = function(message)
    local commands = EnsureMainCommands and EnsureMainCommands()
    if commands then return commands.Dispatch(message) end
    Say("command.chat.not_initialized")
end
