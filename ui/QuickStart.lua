-- Nexus: ui/QuickStart.lua
-- First-launch setup. Presents the three real entry paths without trapping
-- new users in a large tutorial window.

Nexus = Nexus or {}
local M = {}
Nexus.QuickStart = M

local frame
-- Full visible-UI localization (guide family, setup.* keys; the start-up
-- refusals shared with Help use Help's help.error.* keys). Each visible
-- English sentence is a reviewed catalog meaning, looked up through
-- Nexus.Localization when it is shown (never cached here); without the seam
-- or for a key it cannot show, the exact English beside the key is shown.
-- Colour codes, the chat prefix and the joins between sentences stay here.
local function T(key, english)
    local seam = Nexus.Localization
    if type(seam) ~= "table" or type(seam.Text) ~= "function" then return english end
    local text, source = seam.Text(key)
    if source == "unavailable" then return english end
    return text
end
local function TF(key, args, english)
    local seam = Nexus.Localization
    if type(seam) ~= "table" or type(seam.Format) ~= "function" or type(seam.Count) ~= "function" then
        return english
    end
    local text, source = seam.Format(key, args(seam))
    if source == "unavailable" then return english end
    return text
end
-- The saved acknowledgement follows the policy of the release note in
-- ui/Changelog.lua: hasSeenQuickStart is saved data, so it is written only
-- when the saved-data owner reports a durable write for this character and
-- local start-up completed. Deciding whether to show this window, showing it
-- and closing it never create, replace or repair the database: a session that
-- cannot save must not consume the one-time window, and an absent or invalid
-- saved table must stay exactly as it is. Closing still works: the window is
-- dismissed for the rest of that session and is offered again in a later
-- session that can record it.
local dismissedThisSession, recordAttempts = false, 0
local MAX_RECORD_ATTEMPTS = 10
-- Said once per session when a dismissal could not be saved at once.
local unsavedNoticeShown = false
-- The informational replay (M.ShowSetup) states what it is in place of the
-- first-time title and hint; normal opens restore these exact texts.
local function NormalTitle() return T("setup.title.welcome", "Welcome to Nexus") end
local function NormalHint()
    return T("setup.note.reopen_help", "Reopen Help any time with /nexus help. Automation and Orb spending require separate explicit controls.")
end
local function SetupTitle() return T("setup.title.information_only", "Nexus setup (information only)") end
local function SetupHint()
    return T("setup.note.information_only", "Information only: this guide saves nothing and never turns Auto ON.")
end
-- The current Sync mode in the Build Library's and Leaderboard's words. Off
-- and Manual are core/SyncModePolicy.lua's text. Reading the mode writes
-- nothing; this window neither offers nor changes a mode.
local function SyncAutomaticText()
    return T("setup.body.sync_automatic", "Sync is Automatic: may send without a click (login requests, answers to other users, eligible character-best DPS with Echoes and player info).")
end

local function SyncNote(f)
    if not (f and f.sync) then return f end
    local policy = Nexus.SyncModePolicy
    local mode = policy and type(policy.Mode) == "function" and policy.Mode() or nil
    -- The mode's display sentence (SyncModePolicy.DisplayText where its owner
    -- provides it; Text stays raw English for code that compares it).
    local display = policy and (type(policy.DisplayText) == "function" and policy.DisplayText or policy.Text)
    local text = mode == "automatic" and SyncAutomaticText()
        or mode and type(display) == "function" and display(mode) or nil
    f.sync:SetText(text and TF("setup.body.sync_reference", function() return {sync = tostring(text)} end,
        text .. " Reference: Sharing lists what is sent.") or "")
    return f
end

-- Help on the setup surfaces is the guided setup coach at its current step
-- (design/current "Nexus Setup Alternative": Help and Setup open the coach,
-- Reference on request), through Help's own guarded route as the Options
-- menu and /nexus help take it. While an Auto warning waits for its answer
-- the coach does not open and Help.OpenGuide says why; nothing else opens
-- (Reference stays the player's own separate choice), and the reason is
-- returned so the caller can keep it in view for a retry. Returns true only
-- when the coach opened, else false and the reason. Opening it assigns,
-- saves, sends, spends and changes Auto nothing.
local function OpenHelpCoach()
    local help = Nexus.Help
    if type(help) == "table" and type(help.OpenGuide) == "function" then
        local opened, why = help.OpenGuide()
        if opened == true then return true end
        return false, why
    end
    local ui = Nexus.GuidedSetupUI
    if not (type(ui) == "table" and type(ui.Show) == "function") then return false end
    local opened, why = ui.Show()
    if opened == true then return true end
    return false, why
end
M.OpenHelpCoach = OpenHelpCoach

-- The optional long manual (ui/Help.lua pages, also /nexus reference), from
-- its first page. Read only; its own buttons only navigate.
local function OpenReference()
    local help = Nexus.Help
    if type(help) == "table" and type(help.Show) == "function" then help.Show("start") end
end

-- Unlike the release note in ui/Changelog.lua, this acknowledgement does not
-- require the shared catalog. A start-up that refused an oversized catalog
-- still runs its local tools with a durable saved-data owner (decision C), so
-- the user's dismissal is recorded there exactly as in any healthy session.
-- What is required is a real durable owner and completed local start-up: a
-- read-only saved format, an unusable database and a start-up that never
-- reached its local tools all keep the window unconsumed.
local function CanRecordSeen()
    if type(NexusDB) ~= "table" then return false end
    local Store = Nexus.Store
    if type(Store) ~= "table" or type(Store.StateWriteStatus) ~= "function" then
        return false
    end
    local ok, status = pcall(Store.StateWriteStatus)
    if not ok or type(status) ~= "table" or status.mode ~= "durable" then
        return false
    end
    if type(Nexus.StartupStatus) == "function" then
        local okStatus, startup = pcall(Nexus.StartupStatus)
        if not okStatus or type(startup) ~= "table" then return false end
        if not startup.coreReady then return false end
    end
    return true
end
M.CanRecordSeen = CanRecordSeen

local function RecordSeen()
    if not CanRecordSeen() then return false end
    NexusDB.hasSeenQuickStart = true
    return true
end

-- True when nothing is left to do for this window in this session: either the
-- acknowledgement is saved, or the window was never dismissed, or the bounded
-- retries are used up. The caller uses it to stop asking.
function M.Settled()
    if type(NexusDB) == "table" and rawget(NexusDB, "hasSeenQuickStart") then
        return true
    end
    if not dismissedThisSession then return false end
    return recordAttempts >= MAX_RECORD_ATTEMPTS
end

-- The informational replay's routes wait for local start-up as Help's own
-- routes do (ui/Help.lua H.OpenAssignment/H.OpenEditor): the same rule and
-- the same words, said before any window is closed. Returns false after
-- saying why; the replay then stays open.
local function ReplayRouteReady(kind)
    local ready = false
    if type(Nexus.StartupStatus) == "function" then
        local ok, s = pcall(Nexus.StartupStatus)
        ready = ok and type(s) == "table" and s.coreReady == true
    end
    if not ready then
        print("|cffffd200Nexus:|r " .. (kind == "assign"
            and T("help.error.assign_after_startup", "Assign Wishlist opens after start-up finishes (see the loading panel). Nothing was opened or assigned.")
            or T("help.error.editor_after_startup", "The Wishlist Editor opens after start-up finishes (see the loading panel). Nothing was opened.")))
        return false
    end
    local journal = Nexus.JournalTab
    if kind == "assign" and journal and type(journal.CanOpenBuilds) == "function" and not journal.CanOpenBuilds() then
        print("|cffffd200Nexus:|r " .. T("help.error.progression_button_missing", "The game's Character Progression button was not found. Nothing was opened or assigned."))
        return false
    end
    return true
end

local function CloseOtherSetupWindows()
    local names = { "NexusCommunityBuildsFrame", "NexusLeaderboardFrame", "NexusEditorFrame", "NexusLogViewer", "NexusChangelogPopup" }
    for i = 1, #names do
        local f = _G[names[i]]
        if f and f.Hide then pcall(f.Hide, f) end
    end
end

local retryFrame
local function StartRecordRetry()
    if M.Settled() or retryFrame then return end
    retryFrame = CreateFrame("Frame")
    local elapsed = 0
    retryFrame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (tonumber(dt) or 0)
        if elapsed < 2 then return end
        elapsed = 0
        recordAttempts = recordAttempts + 1
        RecordSeen()
        -- Bounded: about twenty seconds, then this session stops trying and
        -- the window is offered again in a later one.
        if M.Settled() then retryFrame:SetScript("OnUpdate", nil) end
    end)
end

-- The first-use dismissal: the first-time Welcome's Close, Escape or entry
-- buttons, or the first-use guided setup coach's Close or Escape (see
-- ShowFirstUseCoach below). One durable policy for both: recorded only through
-- CanRecordSeen, otherwise retried within its bound and said once. Truthful
-- about a dismissal that is not saved (yet): nothing is claimed complete, and
-- the first-use window may be offered again later.
local UNSAVED_NOTICE = {
    welcome = {key = "setup.chat.welcome_not_saved", english = "The Welcome is closed, but this cannot be saved right now "
        .. "(saved data is still loading or is read-only). If it cannot be saved this session, "
        .. "the Welcome is offered again next time. Setup information (read only) in the Options menu shows it again."},
    coach = {key = "setup.chat.coach_not_saved", english = "Guided setup is closed, but this cannot be saved right now "
        .. "(saved data is still loading or is read-only). If it cannot be saved this session, "
        .. "Guided setup is offered again next time. /nexus help or Setup / Welcome in the Options menu reopens it."},
}
local function Dismiss(kind)
    dismissedThisSession = true
    if not RecordSeen() then
        StartRecordRetry()
        if not unsavedNoticeShown then
            unsavedNoticeShown = true
            local notice = UNSAVED_NOTICE[kind] or UNSAVED_NOTICE.welcome
            print("|cffffd200Nexus:|r " .. T(notice.key, notice.english))
        end
    end
end

local function Finish()
    -- The informational replay is not the first-time window: closing it or
    -- following one of its buttons records nothing and dismisses nothing.
    if frame and frame._informational then
        frame._informational = nil
        frame:Hide()
        return
    end
    Dismiss("welcome")
    if frame then frame:Hide() end
end

-- Close fits its whole label at the current font. The fit is measured again
-- on every presentation (first-time, deliberate and informational). Width
-- comes from LayoutMetrics' FitButtonWidth: the client's text width or its
-- conservative model, plus end caps. Without LayoutMetrics, the same rule
-- runs here with that model scaled by the runtime font scale, read from
-- NexusFontNormal as LayoutMetrics does: 7 px per visible character, 14 px
-- at scale 2. Height holds one conservative line, 13 px per unit of font
-- scale as LayoutMetrics' status line (26 px at scale 2). Close is never
-- below the original 74x24. The window stays 420 px unless a wider Close
-- needs room to keep its original 8 px gap from the 290 px hint
-- (x 24..314). Hint, Sync, body and other buttons keep their sizes. The controls on
-- the right (Import, Leaderboard, Orbs and Close) are anchored to the right
-- edge, directly or through Import, so they follow a widened right edge; the
-- centred title and subtitle stay centred. This is an
-- offline model only; native NOT_RUN.
local CLOSE_W, CLOSE_H, WELCOME_W, HINT_RIGHT, CLOSE_GAP, CLOSE_EDGE = 74, 24, 420, 314, 8, 24
local function FitClose(f)
    local close = f and f.close
    if not close then return end
    local scale, font = 1, _G.NexusFontNormal
    if type(font) == "table" and type(font.GetFont) == "function" then
        local ok, _, size = pcall(font.GetFont, font)
        size = ok and tonumber(size) or nil
        if size and size > 0 then scale = math.min(2, math.max(0.75, size / 12)) end
    end
    local metrics, width = Nexus.LayoutMetrics, nil
    if type(metrics) == "table" and type(metrics.FitButtonWidth) == "function" then
        local ok, value = pcall(metrics.FitButtonWidth, close, CLOSE_W)
        value = ok and tonumber(value) or nil
        if value and value >= CLOSE_W and value < math.huge then width = value end
    end
    if not width then
        local measured
        if type(close.GetTextWidth) == "function" then
            local ok, value = pcall(close.GetTextWidth, close)
            value = ok and tonumber(value) or nil
            if value and value > 0 and value < math.huge then measured = value end
        end
        if not measured then
            local text = tostring(close:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            measured = #(text:gsub("[\128-\191]", "")) * math.max(7, 7 * scale)
        end
        width = math.max(CLOSE_W, math.ceil(measured + 24))
        close:SetWidth(width)
    end
    close:SetHeight(math.max(CLOSE_H, math.ceil(13 * scale)))
    f:SetWidth(math.max(WELCOME_W, HINT_RIGHT + CLOSE_GAP + width + CLOSE_EDGE))
end

-- Normal (first-time or deliberate) presentation: the exact first-time texts.
local function NormalTexts(f)
    f._informational = nil
    if f.title then f.title:SetText(NormalTitle()) end
    if f.hint then f.hint:SetText(NormalHint()) end
    FitClose(f)
    return SyncNote(f)
end

local function EnsureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "NexusQuickStart", UIParent)
    -- Height fits the body and hint at a 16 px replacement font such as the
    -- ElvUI font measured natively (6 body lines, 3 hint lines); the default
    -- font needs 5 and 2. tests/prototype/quickstart_layout_fit.lua models both.
    -- The Sync line below the buttons (4 lines at that font, 3 at the
    -- default) adds 80 px; tests/prototype/ux_sync_disclosure.lua models it.
    -- 36 px above the earlier 440 for the Guided setup row.
    frame:SetSize(420, 476)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 55)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()

    -- Fallback if an older installation lacks the Theme module; StyleWindow
    -- replaces this backdrop when the themed client is present.
    pcall(function()
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title = title
    title:SetPoint("TOP", 0, -16)
    title:SetText(NormalTitle())

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.subtitle = subtitle
    subtitle:SetPoint("TOP", 0, -37)
    subtitle:SetText(T("setup.label.welcome_subtitle", "Plan your Echoes, then choose what to automate."))

    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.body = body
    body:SetPoint("TOPLEFT", 24, -56)
    body:SetSize(372, 112)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    -- Three sentences joined here; the Auto consequence keeps its gold colour.
    body:SetText(
        T("setup.body.welcome_existing_build", "Already have a Saved Build? Assign the Wishlist you want it to follow.") .. " " ..
        "|cffffd100" .. T("setup.body.welcome_auto_replace", "With Auto ON, Nexus may replace the active Saved Build with a better finished run. " ..
        "Keep Auto OFF to leave that slot unchanged.") .. "|r\n" ..
        T("setup.body.welcome_starting_fresh", "Starting fresh? Import a Wishlist code or copy a Community build into an editable draft.")
    )

    local current = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    current:SetSize(174, 26)
    current:SetPoint("TOPLEFT", 24, -176)
    current:SetText(T("setup.button.set_up_current_build", "Set up current build"))
    current:SetScript("OnClick", function()
        if frame and frame._informational and not ReplayRouteReady("assign") then return end
        Finish()
        CloseOtherSetupWindows()
        -- The Echo Journal with its Wishlist chooser opened for the Saved
        -- Build it targets; nothing is assigned until a Wishlist is chosen.
        if Nexus.JournalTab and Nexus.JournalTab.OpenBuilds then Nexus.JournalTab.OpenBuilds(true) end
    end)

    local import = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    import:SetSize(174, 26)
    import:SetPoint("TOPRIGHT", -24, -176)
    import:SetText(T("setup.button.import_create_wishlist", "Import / Create Wishlist"))
    import:SetScript("OnClick", function()
        if frame and frame._informational and not ReplayRouteReady("editor") then return end
        Finish()
        CloseOtherSetupWindows()
        if Nexus.WishlistEditor then Nexus.WishlistEditor.Show() end
    end)

    local builds = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    builds:SetSize(174, 26)
    builds:SetPoint("TOPLEFT", current, "BOTTOMLEFT", 0, -10)
    builds:SetText(T("setup.button.browse_community_builds", "Browse Community builds"))
    builds:SetScript("OnClick", function()
        Finish()
        CloseOtherSetupWindows()
        if Nexus.CommunityBuilds then Nexus.CommunityBuilds.Show() end
    end)

    local leaderboard = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    leaderboard:SetSize(174, 26)
    leaderboard:SetPoint("TOPRIGHT", import, "BOTTOMRIGHT", 0, -10)
    leaderboard:SetText(T("setup.button.open_leaderboard", "Open Leaderboard"))
    leaderboard:SetScript("OnClick", function()
        Finish()
        CloseOtherSetupWindows()
        if Nexus.Leaderboard then Nexus.Leaderboard.Show() end
    end)

    -- The optional long manual under its own name, Reference (the design's
    -- separately named view); Help itself is the coach row below.
    local reference = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reference:SetSize(174,26);reference:SetPoint("TOPLEFT",24,-250);reference:SetText(T("setup.button.reference", "Reference"))
    reference:SetScript("OnClick",function() Finish();OpenReference() end)
    frame.reference = reference
    local orbs = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    orbs:SetSize(174,26);orbs:SetPoint("TOPRIGHT",-24,-250);orbs:SetText(T("setup.button.orbs_lost_memories", "Orbs / Lost Memories"))
    orbs:SetScript("OnClick",function() Finish();if Nexus.OrbPanel then Nexus.OrbPanel.Show() end end)
    -- Help: the step-by-step coach (ui/GuidedSetup.lua), the prominent full
    -- row, through the guarded route above (OpenHelpCoach). Like the other
    -- entry buttons it only navigates: it records no setup fact, grants no
    -- consent and never turns Auto ON. The coach is asked first: only once it
    -- opened does it take this window's place (and the other setup windows
    -- close). A refused coach has said why in chat; this window, and any
    -- other open window with its draft, then stay for a retry, and nothing
    -- else opens. The Sync line moves down.
    local guide = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    guide:SetSize(372, 26)
    guide:SetPoint("TOPLEFT", 24, -284)
    guide:SetText(T("setup.button.help_guided_setup", "Help: Guided setup"))
    guide:SetScript("OnClick", function()
        if not OpenHelpCoach() then return end
        Finish()
        CloseOtherSetupWindows()
    end)
    frame.guide = guide
    local sync = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.sync = sync
    sync:SetPoint("TOPLEFT", 24, -318)
    sync:SetSize(372, 72)
    sync:SetJustifyH("LEFT")
    sync:SetJustifyV("TOP")
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.hint = hint
    hint:SetPoint("BOTTOMLEFT", 24, 22)
    hint:SetSize(290, 54)
    hint:SetJustifyH("LEFT")
    hint:SetText(NormalHint())

    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(74, 24)
    close:SetPoint("BOTTOMRIGHT", -24, 20)
    close:SetText(T("setup.button.close", "Close"))
    close:SetScript("OnClick", Finish)
    frame.close = close

    local theme = Nexus.Theme
    if theme then
        if theme.StyleWindow then theme.StyleWindow(frame, 0.97) end
        if theme.StyleTree then theme.StyleTree(frame) end
        if theme.StyleLabel then
            theme.StyleLabel(title, "accent")
            theme.StyleLabel(subtitle, "muted")
            theme.StyleLabel(body, "text")
            theme.StyleLabel(sync, "text")
            theme.StyleLabel(hint, "muted")
        end
    end

    -- UX-18: Escape closes the Welcome exactly as Close does (Finish: the
    -- first-time dismissal and its durable acknowledgement policy; for the
    -- informational replay, a hide with no write). The client's Escape
    -- handler hides each shown frame named in UISpecialFrames. The Welcome
    -- itself is not listed, because other routes hide it without recording
    -- a dismissal (the HUD's CloseOtherNexusWindows) and must stay that way;
    -- this invisible child is listed instead. It is shown exactly while the
    -- Welcome is, and its own hide finishes the Welcome only while the
    -- Welcome is still visible (IsVisible, parent-aware). The Escape handler
    -- hides only this child, so the Welcome is still visible and finishes. An
    -- explicit hide of the Welcome clears its own flag first, and a hidden
    -- ancestor (the UI hidden, a cinematic) makes it not visible, so neither
    -- records nor closes anything; no stale entry is left to take a later
    -- Escape. (Review36 M7R-01; offline model only, native NOT_RUN.)
    local escape = CreateFrame("Frame", "NexusQuickStartEscape", frame)
    escape:SetScript("OnHide", function()
        if frame and frame:IsVisible() then Finish() end
    end)
    frame:HookScript("OnShow", function() escape:Show() end)
    frame:HookScript("OnHide", function() escape:Hide() end)
    escape:Hide()
    UISpecialFrames = UISpecialFrames or {}
    UISpecialFrames[#UISpecialFrames + 1] = "NexusQuickStartEscape"

    return frame
end

function M.Show()
    if Nexus.OverwriteWarning and Nexus.OverwriteWarning.EnsureOnboarding() ~= "accepted" then return false end
    NormalTexts(EnsureFrame()):Show()
end

-- The informational replay (the ... menu's "Setup information (read only)"
-- and Help.OpenSetup; Setup / Welcome in Help and in the ... menu opens the
-- guided setup coach instead). A secondary route. Information only, and not
-- the warning's consent: it opens after the warning was answered Yes or No,
-- after the first-time window was seen, and while saved data is read-only or
-- loading. It records no acknowledgement, writes no saved data, enables
-- nothing and asks the warning nothing; its buttons only open their views.
-- While a warning is open and waiting for its answer it does not open over
-- it. Returns true when shown, else false and why.
function M.ShowSetup()
    local warning = Nexus.OverwriteWarning
    if warning and type(warning.IsOpen) == "function" and warning.IsOpen() then
        return false, "warning-open"
    end
    -- The first-time Welcome is open already: it stays the first-time window
    -- (closing it is still the first-time dismissal); the replay never turns
    -- it into information only.
    if frame and frame:IsShown() and not frame._informational then
        return true, "first-time-open"
    end
    local f = EnsureFrame()
    f._informational = true
    if f.title then f.title:SetText(SetupTitle()) end
    if f.hint then f.hint:SetText(SetupHint()) end
    FitClose(f)
    -- The one-time release note (ui/Changelog.lua) is a dialog of this
    -- window's strata and level, so the two would draw through each other
    -- (each one's buttons over the other's body). Showing the note already
    -- closes this window; asking for this window now hides a shown note, as
    -- this window's own buttons do (CloseOtherSetupWindows). Display only:
    -- the hide records nothing (the note is recorded when it is displayed,
    -- and only where that can be saved), and the note is not offered again
    -- in this session.
    local note = _G.NexusChangelogPopup
    if note and note.IsShown and note:IsShown() then pcall(note.Hide, note) end
    -- The rest of the setup family gives way too (M.SetupFamilyGiveWay).
    M.SetupFamilyGiveWay("info")
    SyncNote(f):Show()
    return true
end

-- M7: Setup checklist and status (Help's Setup checklist and the ... menu).
-- A separate read-only window, not the Welcome: every row is worded by
-- UserText from Panel.SetupFacts, read again while it is shown (twice a
-- second). Unknown, loading and unavailable stay apart from done; the Welcome
-- being seen, closed or answered is not a setup fact and is never read. Its
-- buttons only navigate through Help's routes (which say why when they cannot
-- open); none assigns, saves, sends, turns Auto ON, starts or resumes an Orb
-- run or spends. Close and Escape only hide it.
local checklist
-- 34 px above the earlier 400 for the Reference row above the buttons, so the
-- fixed boxes below still end above it without LayoutMetrics.
local CHECK_W, CHECK_H, CHECK_TEXT_W = 460, 434, 412
local CHECK_ROW_Y = { -70, -114, -158 }
local CHECK_STATUS_Y = { -242, -276, -310 }
-- UX-18: each text block flows below the previous one at the height its
-- wrapped text needs (LayoutMetrics.WrapHeight: the client's measurement, or
-- the conservative model), so a long Saved Build name, a larger font or a
-- long reason is not cut. A block taller than CHECK_BLOCK_MAX keeps that
-- height and shows its complete text on hover (LayoutMetrics.FullTextTooltip).
-- The window grows to its content (never below CHECK_H) and is kept on screen
-- (LayoutMetrics.FitToScreen). Without LayoutMetrics the fixed boxes above stay.
-- The footer holds the button row and the Reference row 6 px above it.
local CHECK_TOP, CHECK_GAP, CHECK_BLOCK_MAX, CHECK_FOOTER = -38, 4, 120, 86
local CHECK_REFERENCE_Y, CHECK_REFERENCE_W = 50, 90

local function ChecklistText(parent, y, h, template)
    local s = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    s:SetPoint("TOPLEFT", 24, y)
    s:SetSize(CHECK_TEXT_W, h)
    s:SetJustifyH("LEFT")
    s:SetJustifyV("TOP")
    return s
end

-- Flows the blocks top to bottom (see CHECK_BLOCK_MAX above).
local function LayoutChecklist(f)
    local metrics = Nexus.LayoutMetrics
    if not (metrics and type(metrics.WrapHeight) == "function") then return end
    local y = CHECK_TOP
    local function place(fs, gap)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 24, y)
        local height = metrics.WrapHeight(fs, CHECK_TEXT_W, 12, CHECK_BLOCK_MAX)
        y = y - height - (gap or CHECK_GAP)
    end
    place(f.subtitle, 8)
    for _, fs in ipairs(f.rows) do place(fs) end
    place(f.summary, 10)
    place(f.statusTitle, 2)
    for _, fs in ipairs(f.status) do place(fs) end
    place(f.notice)
    -- Reference holds its whole label at the current font, never wider than
    -- the text column (right-aligned, so it grows to the left).
    if f.reference and type(metrics.FitButtonWidth) == "function" then
        metrics.FitButtonWidth(f.reference, CHECK_REFERENCE_W, CHECK_TEXT_W)
    end
    local height = math.max(CHECK_H, math.ceil(-y + CHECK_FOOTER))
    if math.abs((tonumber(f:GetHeight()) or 0) - height) > 0.5 then f:SetHeight(height) end
    if type(metrics.FitToScreen) == "function" then metrics.FitToScreen(f) end
end

local function RefreshChecklist()
    if not (checklist and checklist:IsShown()) then return end
    local text, panel = Nexus.UserText, Nexus.Panel
    local facts = {}
    if panel and type(panel.SetupFacts) == "function" then
        local ok, read = pcall(panel.SetupFacts)
        facts = ok and type(read) == "table" and read or {}
    end
    local steps = text and text.SetupChecklist and text.SetupChecklist(facts) or { rows = {}, complete = false }
    local marks = text and text.CHECK_MARKS or {}
    local done = 0
    for i, line in ipairs(checklist.rows) do
        local row = steps.rows[i]
        if row and row.status == "done" then done = done + 1 end
        -- The mark, label and status words are UserText's; this file owns the join.
        line:SetText(row and TF("setup.value.checklist_row", function()
            return {mark = tostring(marks[row.status] or ""), label = tostring(row.label), status = tostring(row.text)}
        end, (marks[row.status] or "") .. " " .. row.label .. ": " .. row.text) or "")
    end
    checklist.steps = steps
    local function counts(seam) return {done = seam.Count(done), total = seam.Count(#steps.rows)} end
    checklist.summary:SetText(steps.complete
        and TF("setup.status.steps_done", counts, "Setup steps done now: " .. done .. " of " .. #steps.rows .. ".")
        or TF("setup.status.steps_done_open", counts,
            "Setup steps done now: " .. done .. " of " .. #steps.rows .. ". Nothing here completes a step for you."))
    local status = text and text.StatusLines and text.StatusLines(facts) or {}
    for i, line in ipairs(checklist.status) do line:SetText(status[i] or "") end
    LayoutChecklist(checklist)
end
M.RefreshChecklist = RefreshChecklist

local function EnsureChecklist()
    if checklist then return checklist end
    local f = CreateFrame("Frame", "NexusSetupChecklist", UIParent)
    checklist = f
    f:SetSize(CHECK_W, CHECK_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:Hide()
    pcall(function()
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -16)
    f.title:SetText(T("setup.title.checklist", "Setup checklist and status"))
    f.subtitle = ChecklistText(f, -38, 28)
    f.subtitle:SetText(T("setup.label.checklist_subtitle", "Read-only: what Nexus can read now. A step is done only when it is true now."))
    f.rows = {}
    for i, y in ipairs(CHECK_ROW_Y) do f.rows[i] = ChecklistText(f, y, 40) end
    f.summary = ChecklistText(f, -202, 16)
    f.statusTitle = ChecklistText(f, -224, 16, "GameFontNormalSmall")
    f.statusTitle:SetText(T("setup.heading.checklist_status", "Status"))
    f.status = {}
    for i, y in ipairs(CHECK_STATUS_Y) do f.status[i] = ChecklistText(f, y, 32) end
    -- Why the last button did not open its window, in this window (not only
    -- in chat), so no reason depends on a tooltip or a disabled control.
    f.notice = ChecklistText(f, -344, 16)
    -- Complete text on hover for any block kept at its maximum height.
    local metrics = Nexus.LayoutMetrics
    if metrics and type(metrics.FullTextTooltip) == "function" then
        f.textHits = {}
        for _, fs in ipairs({f.rows[1], f.rows[2], f.rows[3], f.summary, f.status[1], f.status[2], f.status[3], f.notice}) do
            f.textHits[#f.textHits + 1] = metrics.FullTextTooltip(fs, f)
        end
    end
    local function button(x, w, label, fn)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(w, 24)
        b:SetPoint("BOTTOMLEFT", x, 20)
        b:SetText(label)
        b:SetScript("OnClick", fn)
        return b
    end
    -- Help's own routes: each says why when it cannot open, and opens nothing.
    -- The reason is also shown here.
    -- Returns true when the route opened its window.
    local function route(open, missing)
        local help = Nexus.Help
        local fn = help and help[open]
        if type(fn) ~= "function" then
            f.notice:SetText(missing);LayoutChecklist(f);return false
        end
        local opened, why = fn()
        if opened then f.notice:SetText("");f:Hide();return true end
        f.notice:SetText(type(why) == "string" and why or missing)
        LayoutChecklist(f)
        return false
    end
    f.assign = button(24, 130, T("setup.button.assign_wishlist", "Assign Wishlist..."), function()
        route("OpenAssignment", T("setup.error.assign_unavailable", "Assign Wishlist is not available. Nothing was opened or assigned."))
    end)
    f.editor = button(160, 120, T("setup.button.wishlist_editor", "Wishlist Editor"), function()
        route("OpenEditor", T("setup.error.editor_unavailable", "The Wishlist Editor is not available. Nothing was opened."))
    end)
    -- Help is the guided setup coach at its current step (Help.OpenGuide, as
    -- OpenHelpCoach above), which takes this window's place. When it cannot
    -- open (an Auto warning waits for its answer) the reason is shown here,
    -- this window stays for a retry and nothing else opens: Reference, below,
    -- is the player's own separate choice.
    f.help = button(286, 70, T("setup.button.help", "Help"), function()
        route("OpenGuide", T("setup.error.guide_unavailable", "Guided setup is not available. Nothing was opened."))
    end)
    f.close = button(362, 74, T("setup.button.close", "Close"), function() f:Hide() end)
    -- Reference, the optional long manual, on its own row above Help and
    -- Close. It opens above this window (Help's own layer); this window stays.
    f.reference = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.reference:SetSize(CHECK_REFERENCE_W, 24)
    f.reference:SetPoint("BOTTOMRIGHT", -24, CHECK_REFERENCE_Y)
    f.reference:SetText(T("setup.button.reference", "Reference"))
    f.reference:SetScript("OnClick", OpenReference)
    local elapsed = 0
    f:SetScript("OnShow", function() elapsed = 0; f.notice:SetText(""); RefreshChecklist() end)
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (tonumber(dt) or 0)
        if elapsed < 0.5 then return end
        elapsed = 0
        RefreshChecklist()
    end)
    local theme = Nexus.Theme
    if theme then
        if theme.StyleWindow then theme.StyleWindow(f, 0.97) end
        if theme.StyleTree then theme.StyleTree(f) end
        if theme.StyleLabel then theme.StyleLabel(f.title, "accent") end
    end
    UISpecialFrames = UISpecialFrames or {}
    UISpecialFrames[#UISpecialFrames + 1] = "NexusSetupChecklist"
    return f
end

function M.ShowChecklist()
    local f = EnsureChecklist()
    -- Opened over the guided setup coach (from Help or the coach's own
    -- step), the checklist stands beside the coach rather than replacing it.
    -- The two would otherwise draw through each other (one strata, the same
    -- level), so the checklist's whole window is drawn above the coach's
    -- whole tree: its Theme base (one level under the window) at least two
    -- levels above the coach's highest frame, every checklist frame at its
    -- own offset above its parent. The raise is bounded: with the window at
    -- most 26, the checklist's frames (its base and two levels of buttons and
    -- hover areas) stay under the Orb window (30, its base 29), Help (40)
    -- and Community (50), far inside the low band the journal layers keep
    -- (under 100 and 128). A coach whose tree reaches above that bound is not
    -- an ordinary geometry; the checklist then lets the coach give way, as
    -- every other family member does. Not over a coach, the checklist keeps
    -- its own default level, and every other shown family member gives way.
    local coachFrame = _G.NexusGuidedSetup
    local overCoach = coachFrame ~= nil and type(coachFrame.IsShown) == "function" and coachFrame:IsShown() and true or false
    local function Level(w)
        if type(w) ~= "table" or type(w.GetFrameLevel) ~= "function" then return nil end
        local ok, value = pcall(w.GetFrameLevel, w)
        return ok and tonumber(value) or nil
    end
    local function Children(w)
        if type(w) ~= "table" or type(w.GetChildren) ~= "function" then return {} end
        local ok, kids = pcall(function() return {w:GetChildren()} end)
        return ok and kids or {}
    end
    local target
    if overCoach then
        local top = Level(coachFrame) or 0
        local function Highest(w, depth)
            for _, child in ipairs(Children(w)) do
                local value = Level(child)
                if value and value > top then top = value end
                if depth < 8 then Highest(child, depth + 1) end
            end
        end
        Highest(coachFrame, 1)
        target = top + 3
        if target > 26 then overCoach, target = false, nil end
    end
    M.SetupFamilyGiveWay("checklist", overCoach)
    if f._nexusDefaultLevel == nil then f._nexusDefaultLevel = Level(f) or 1 end
    local base = f._nexusWindowBase
    local function Keep(w, depth)
        local at = Level(w) or 0
        for _, child in ipairs(Children(w)) do
            if child ~= base and type(child) == "table" and type(child.SetFrameLevel) == "function" then
                if child._nexusLevelOffset == nil then
                    child._nexusLevelOffset = math.max(1, (Level(child) or (at + 1)) - at)
                end
                pcall(child.SetFrameLevel, child, at + child._nexusLevelOffset)
                if depth < 8 then Keep(child, depth + 1) end
            end
        end
    end
    local want = target or f._nexusDefaultLevel
    if Level(f) ~= want then
        -- Each frame's offset is taken once, at the default level, before
        -- any raise, so the order inside the window never changes.
        if not f._nexusLevelOffsetsKept then Keep(f, 1); f._nexusLevelOffsetsKept = true end
        pcall(f.SetFrameLevel, f, want)
        Keep(f, 1)
    end
    f:Show()
    -- The Theme base follows the window's level (also when it was shown).
    local theme = Nexus.Theme
    if theme and type(theme._SyncWindowBase) == "function" then pcall(theme._SyncWindowBase, f) end
    RefreshChecklist()
    return f
end

function M.HideChecklist()
    if checklist then checklist:Hide() end
end

-- The setup family: Settings, the guided setup coach, this window as the
-- information-only replay (ShowSetup) and the setup checklist. All four are
-- dialogs of one strata at the same level, so two shown together draw
-- through each other (each one's buttons over the other's body). The one
-- about to be shown (`keep`: "settings", "coach", "info" or "checklist")
-- calls this just before its own show, after its own refusals, and every
-- other shown member gives way through its own display-only hide:
--   * Settings: SettingsWindow.Hide.
--   * The coach: GuidedSetupUI.Hide, its raw hide, and only while it is
--     shown. It records no first use and keeps its first-use callback; a
--     coach that stepped aside and waits (for Help or a route) is hidden
--     already and is left waiting, so its own return still applies.
--   * This window: only while shown as information only (_informational).
--     A plain frame hide; the flag is left as it is, so its own Finish still
--     treats it as information only (no first-use dismissal). The first-time
--     Welcome, which is the same frame without that flag, is not touched.
--   * The checklist: its own hide.
-- `keepCoach` (the checklist opened over the coach, ShowChecklist) keeps a
-- shown coach; the checklist is then drawn above it instead.
-- Nothing is recorded, saved, asked or reopened; no other window is touched.
function M.SetupFamilyGiveWay(keep, keepCoach)
    if keep ~= "settings" then
        local settings = Nexus.SettingsWindow
        if settings and type(settings.IsShown) == "function" and type(settings.Hide) == "function"
            and settings.IsShown() then
            pcall(settings.Hide)
        end
    end
    if keep ~= "coach" and not keepCoach then
        local coach, coachFrame = Nexus.GuidedSetupUI, _G.NexusGuidedSetup
        if coach and type(coach.Hide) == "function" and coachFrame and coachFrame.IsShown and coachFrame:IsShown() then
            pcall(coach.Hide)
        end
    end
    if keep ~= "info" and frame and frame:IsShown() and frame._informational == true then
        pcall(frame.Hide, frame)
    end
    if keep ~= "checklist" and checklist and checklist:IsShown() then
        pcall(checklist.Hide, checklist)
    end
end

-- First use is the guided setup coach (ui/GuidedSetup.lua) in a healthy
-- session: the coach is loaded and the acknowledgement can be recorded now
-- (CanRecordSeen: a durable saved-data owner after local start-up). Any other
-- session keeps the first-time Welcome above as its first-use window,
-- unchanged: an absent, invalid or read-only saved table, a start-up that has
-- not finished or failed, or no coach. Only the coach's deliberate Close or
-- Escape is the first-use dismissal (Dismiss: the same durable policy, bounded
-- retries and notice), and only for the character and saved root it was
-- shown for. A hide by a route the coach opens, a warning or another window
-- records nothing, and a dismissal records only that first use was seen:
-- guide steps keep their own state.
local coachOffer
local function OwnerKey()
    local store = Nexus.Store
    if type(store) ~= "table" or type(store.CurrentOwnerKey) ~= "function" then return nil end
    local ok, key = pcall(store.CurrentOwnerKey)
    return ok and key or nil
end
local function CoachClosed()
    local offer = coachOffer
    coachOffer = nil
    if not offer or offer.database ~= NexusDB or offer.owner ~= OwnerKey() then return end
    Dismiss("coach")
end
local function ShowFirstUseCoach()
    local ui = Nexus.GuidedSetupUI
    if type(ui) ~= "table" or type(ui.ShowFirstUse) ~= "function" or not CanRecordSeen() then return false end
    local owner = OwnerKey()
    if owner == nil then return false end
    local ok, shown = pcall(ui.ShowFirstUse, CoachClosed)
    if not (ok and shown == true) then return false end
    coachOffer = {owner = owner, database = NexusDB}
    return true
end

-- Returns true when this window needs no further attention in this session.
function M.ShowIfFirstTime()
    if Nexus.OverwriteWarning then
        local outcome = Nexus.OverwriteWarning.EnsureOnboarding()
        if outcome == "pending" then return false end
        if outcome == "declined" then return true end
    end
    if dismissedThisSession then
        -- Closed earlier in this session, possibly before the saved-data
        -- owner was writable. Record it now if that is allowed by then. The
        -- attempts are bounded, so a session that can never save stops.
        if not M.Settled() then
            recordAttempts = recordAttempts + 1
            RecordSeen()
        end
        return M.Settled()
    end
    local db = NexusDB
    if type(db) == "table" and rawget(db, "hasSeenQuickStart") then return true end
    if ShowFirstUseCoach() then
        -- No first-time Welcome beside the coach (a plain hide records nothing).
        if frame and frame:IsShown() and not frame._informational then frame:Hide() end
        return false
    end
    NormalTexts(EnsureFrame()):Show()
    return false
end

return M
