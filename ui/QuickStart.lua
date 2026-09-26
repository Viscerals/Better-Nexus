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
    dismissedThisSession = true
    if not RecordSeen() then StartRecordRetry() end
    if frame then frame:Hide() end
end

local function EnsureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "NexusQuickStart", UIParent)
    -- Height fits the body and hint at a 16 px replacement font such as the
    -- ElvUI font measured natively (6 body lines, 3 hint lines); the default
    -- font needs 5 and 2. tests/prototype/quickstart_layout_fit.lua models both.
    frame:SetSize(420, 360)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 55)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()

    pcall(function()
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("|cff7fd5ffWelcome to Nexus|r")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", 0, -37)
    subtitle:SetTextColor(0.7, 0.7, 0.7)
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
        Finish()
        CloseOtherSetupWindows()
        if Nexus.JournalTab and Nexus.JournalTab.OpenBuilds then Nexus.JournalTab.OpenBuilds() end
    end)

    local import = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    import:SetSize(174, 26)
    import:SetPoint("TOPRIGHT", -24, -176)
    import:SetText("Import / Create Wishlist")
    import:SetScript("OnClick", function()
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
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 24, 22)
    hint:SetSize(290, 54)
    hint:SetJustifyH("LEFT")
    hint:SetText("Reopen Help any time with /nexus help. Automation and Orb spending require separate explicit controls.")

    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(74, 24)
    close:SetPoint("BOTTOMRIGHT", -24, 20)
    close:SetText("Later")
    close:SetScript("OnClick", Finish)

    return frame
end

function M.Show() EnsureFrame():Show() end

-- Returns true when this window needs no further attention in this session.
function M.ShowIfFirstTime()
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
    EnsureFrame():Show()
    return false
end

return M
