-- Nexus: ui/QuickStart.lua
-- First-launch setup. Presents the three real entry paths without trapping
-- new users in a large tutorial window.

Nexus = Nexus or {}
local M = {}
Nexus.QuickStart = M

local frame
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
local NORMAL_TITLE = "Welcome to Nexus"
local NORMAL_HINT = "Reopen Help any time with /nexus help. Automation and Orb spending require separate explicit controls."
local SETUP_TITLE = "Nexus setup (information only)"
local SETUP_HINT = "Information only: this guide saves nothing and never turns Auto ON."
-- The current Sync mode in the Build Library's and Leaderboard's words. Off
-- and Manual are core/SyncModePolicy.lua's text. Reading the mode writes
-- nothing; this window neither offers nor changes a mode.
local SYNC_AUTOMATIC_TEXT = "Sync is Automatic: may send without a click (login requests, answers to other users, eligible character-best DPS with Echoes and player info)."

local function SyncNote(f)
    if not (f and f.sync) then return f end
    local policy = Nexus.SyncModePolicy
    local mode = policy and type(policy.Mode) == "function" and policy.Mode() or nil
    local text = mode == "automatic" and SYNC_AUTOMATIC_TEXT
        or mode and type(policy.Text) == "function" and policy.Text(mode) or nil
    f.sync:SetText(text and (text .. " Help: Sharing lists what is sent.") or "")
    return f
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
            and "Assign Wishlist opens after start-up finishes (see the loading panel). Nothing was opened or assigned."
            or "The Wishlist Editor opens after start-up finishes (see the loading panel). Nothing was opened."))
        return false
    end
    local journal = Nexus.JournalTab
    if kind == "assign" and journal and type(journal.CanOpenBuilds) == "function" and not journal.CanOpenBuilds() then
        print("|cffffd200Nexus:|r The game's Character Progression button was not found. Nothing was opened or assigned.")
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

local function Finish()
    -- The informational replay is not the first-time window: closing it or
    -- following one of its buttons records nothing and dismisses nothing.
    if frame and frame._informational then
        frame._informational = nil
        frame:Hide()
        return
    end
    dismissedThisSession = true
    if not RecordSeen() then
        StartRecordRetry()
        -- Truthful about a dismissal that is not saved (yet): nothing is
        -- claimed complete, and the window may be offered again later.
        if not unsavedNoticeShown then
            unsavedNoticeShown = true
            print("|cffffd200Nexus:|r The Welcome is closed, but this cannot be saved right now "
                .. "(saved data is still loading or is read-only). If it cannot be saved this session, "
                .. "the Welcome is offered again next time. Setup / Welcome in the ... menu reopens it.")
        end
    end
    if frame then frame:Hide() end
end

-- Normal (first-time or deliberate) presentation: the exact first-time texts.
local function NormalTexts(f)
    f._informational = nil
    if f.title then f.title:SetText(NORMAL_TITLE) end
    if f.hint then f.hint:SetText(NORMAL_HINT) end
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
    frame:SetSize(420, 440)
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
    title:SetText("Welcome to Nexus")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.subtitle = subtitle
    subtitle:SetPoint("TOP", 0, -37)
    subtitle:SetText("Plan your Echoes, then choose what to automate.")

    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.body = body
    body:SetPoint("TOPLEFT", 24, -56)
    body:SetSize(372, 112)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetText(
        "Already have a Saved Build? Assign the Wishlist you want it to follow. " ..
        "|cffffd100With Auto ON, Nexus may replace the active Saved Build with a better finished run. " ..
        "Keep Auto OFF to leave that slot unchanged.|r\n" ..
        "Starting fresh? Import a Wishlist code or copy a Community build into an editable draft."
    )

    local current = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    current:SetSize(174, 26)
    current:SetPoint("TOPLEFT", 24, -176)
    current:SetText("Set up current build")
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
    import:SetText("Import / Create Wishlist")
    import:SetScript("OnClick", function()
        if frame and frame._informational and not ReplayRouteReady("editor") then return end
        Finish()
        CloseOtherSetupWindows()
        if Nexus.WishlistEditor then Nexus.WishlistEditor.Show() end
    end)

    local builds = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    builds:SetSize(174, 26)
    builds:SetPoint("TOPLEFT", current, "BOTTOMLEFT", 0, -10)
    builds:SetText("Browse Community builds")
    builds:SetScript("OnClick", function()
        Finish()
        CloseOtherSetupWindows()
        if Nexus.CommunityBuilds then Nexus.CommunityBuilds.Show() end
    end)

    local leaderboard = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    leaderboard:SetSize(174, 26)
    leaderboard:SetPoint("TOPRIGHT", import, "BOTTOMRIGHT", 0, -10)
    leaderboard:SetText("Open Leaderboard")
    leaderboard:SetScript("OnClick", function()
        Finish()
        CloseOtherSetupWindows()
        if Nexus.Leaderboard then Nexus.Leaderboard.Show() end
    end)

    local help = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    help:SetSize(174,26);help:SetPoint("TOPLEFT",24,-250);help:SetText("Help / Getting Started")
    help:SetScript("OnClick",function() Finish();if Nexus.Help then Nexus.Help.Show("start") end end)
    local orbs = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    orbs:SetSize(174,26);orbs:SetPoint("TOPRIGHT",-24,-250);orbs:SetText("Orbs / Lost Memories")
    orbs:SetScript("OnClick",function() Finish();if Nexus.OrbPanel then Nexus.OrbPanel.Show() end end)
    local sync = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.sync = sync
    sync:SetPoint("TOPLEFT", 24, -284)
    sync:SetSize(372, 72)
    sync:SetJustifyH("LEFT")
    sync:SetJustifyV("TOP")
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.hint = hint
    hint:SetPoint("BOTTOMLEFT", 24, 22)
    hint:SetSize(290, 54)
    hint:SetJustifyH("LEFT")
    hint:SetText("Reopen Help any time with /nexus help. Automation and Orb spending require separate explicit controls.")

    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(74, 24)
    close:SetPoint("BOTTOMRIGHT", -24, 20)
    close:SetText("Later")
    close:SetScript("OnClick", Finish)

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

    return frame
end

function M.Show()
    if Nexus.OverwriteWarning and Nexus.OverwriteWarning.EnsureOnboarding() ~= "accepted" then return false end
    NormalTexts(EnsureFrame()):Show()
end

-- Setup / Welcome replay (the ... menu and Help). Information only, and not
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
    if f.title then f.title:SetText(SETUP_TITLE) end
    if f.hint then f.hint:SetText(SETUP_HINT) end
    SyncNote(f):Show()
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
    NormalTexts(EnsureFrame()):Show()
    return false
end

return M
