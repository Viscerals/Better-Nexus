-- Nexus: ui/QuickStart.lua
-- First-launch setup. Presents the three real entry paths without trapping
-- new users in a large tutorial window.

Nexus = Nexus or {}
local M = {}
Nexus.QuickStart = M

local frame

local function CloseOtherSetupWindows()
    local names = { "NexusCommunityBuildsFrame", "NexusLeaderboardFrame", "NexusEditorFrame", "NexusLogViewer", "NexusChangelogPopup" }
    for i = 1, #names do
        local f = _G[names[i]]
        if f and f.Hide then pcall(f.Hide, f) end
    end
end

local function Finish()
    NexusDB = NexusDB or {}
    NexusDB.hasSeenQuickStart = true
    if frame then frame:Hide() end
end

local function EnsureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "NexusQuickStart", UIParent)
    frame:SetSize(420, 332)
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
    body:SetPoint("TOPLEFT", 24, -62)
    body:SetSize(372, 58)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetText(
        "Already have a Saved Build? Assign the Wishlist you want it to follow.\n" ..
        "Starting fresh? Import a Wishlist code or copy a Community build into an editable draft."
    )

    local current = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    current:SetSize(174, 26)
    current:SetPoint("TOPLEFT", 24, -132)
    current:SetText("Set up current build")
    current:SetScript("OnClick", function()
        Finish()
        CloseOtherSetupWindows()
        if Nexus.JournalTab and Nexus.JournalTab.OpenBuilds then Nexus.JournalTab.OpenBuilds() end
    end)

    local import = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    import:SetSize(174, 26)
    import:SetPoint("TOPRIGHT", -24, -132)
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
    help:SetSize(174,26);help:SetPoint("TOPLEFT",24,-206);help:SetText("Help / Getting Started")
    help:SetScript("OnClick",function() Finish();if Nexus.Help then Nexus.Help.Show("start") end end)
    local orbs = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    orbs:SetSize(174,26);orbs:SetPoint("TOPRIGHT",-24,-206);orbs:SetText("Orbs / Lost Memories")
    orbs:SetScript("OnClick",function() Finish();if Nexus.OrbPanel then Nexus.OrbPanel.Show() end end)
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 24, 22)
    hint:SetSize(290, 30)
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

function M.ShowIfFirstTime()
    NexusDB = NexusDB or {}
    if NexusDB.hasSeenQuickStart then return end
    EnsureFrame():Show()
end

return M
