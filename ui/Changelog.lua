-- Nexus: ui/Changelog.lua
-- One-time, dismissible release note for meaningful user-facing changes.
Nexus = Nexus or {}
local M = {}
Nexus.Changelog = M

local VERSION = "1.20.0-beta.1"
local RELEASE_KEY = "prototype-P1.6-assigned-orbs"
local frame
local shownThisSession = false

local function HasSeenRelease()
    if type(NexusDB) ~= "table" then return false end
    if NexusDB.lastChangelogSeen == RELEASE_KEY then return true end
    if type(NexusDB.settings) == "table" and (NexusDB.settings.lastChangelogSeen == RELEASE_KEY) then return true end
    return false
end

local function MarkReleaseSeen()
    if type(NexusDB) ~= "table" then return end
    NexusDB.lastChangelogSeen = RELEASE_KEY
    NexusDB.settings = NexusDB.settings or {}
    NexusDB.settings.lastChangelogSeen = RELEASE_KEY
end

local function Create()
    if frame then return frame end
    frame = CreateFrame("Frame", "NexusChangelogPopup", UIParent)
    frame:SetSize(520, 330)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 90)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("Nexus prototype P1.6")

    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", 28, -52)
    body:SetPoint("RIGHT", -28, 0)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetText([[|cffffd200Assigned Wishlist and visible Help|r
- Orb mode uses the same assigned Wishlist as the main panel.
- Enter a maximum and Start once to approve safe surplus copies and recycling.
- Required rolled copies and future permanent targets remain protected.
- Help retains seven topics with corrected text and navigation layering.

|cffffd200Optional Orb refinement|r
- Target changes pause the run. Resume retains its used and pending budget.
- Close keeps an approved run active; main-panel Pause/Stop remain available.
- Same-ID, same-quality results remain paused when completion cannot be proved.

Experimental: native gameplay is not verified by offline tests.
Real-resource Orb testing requires a separate user decision.]])

    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(92, 24)
    close:SetPoint("BOTTOM", 0, 14)
    close:SetText("Got it")
    close:SetScript("OnClick", function()
        MarkReleaseSeen()
        frame:Hide()
    end)
    frame:Hide()
    return frame
end

function M.ShowIfNeeded()
    if type(NexusDB) ~= "table" then return end
    if not NexusDB.hasSeenQuickStart then
        MarkReleaseSeen()
        return
    end
    if shownThisSession or HasSeenRelease() then return end
    -- Mark it seen when displayed, not only when the button is clicked. This
    -- prevents reloads, disconnects, or another popup covering it from causing
    -- the same release note to appear on every login.
    shownThisSession = true
    MarkReleaseSeen()
    local popup = Create()
    if Nexus.Panel and Nexus.Panel.AttachMenuFrame then Nexus.Panel.AttachMenuFrame(popup) end
    if Nexus.Theme and Nexus.Theme.StyleWindow then Nexus.Theme.StyleWindow(popup, 0.96) end
    if Nexus.Panel and Nexus.Panel.CloseOtherWindows then Nexus.Panel.CloseOtherWindows("NexusChangelogPopup") end
    popup:Show()
end

local ev = CreateFrame("Frame")
local elapsed, armed = 0, false
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function() armed = true; elapsed = 0 end)
ev:SetScript("OnUpdate", function(_, dt)
    if not armed then return end
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed >= 2 then
        armed = false
        pcall(M.ShowIfNeeded)
    end
end)
