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

-- lastChangelogSeen is saved data. It is recorded only when the saved-data
-- owner reports a durable write for this character and local start-up
-- completed: a failed or read-only start-up must not consume the one-time
-- note, because that acknowledgement would be lost with the rest of the
-- session. The note stays viewable and closes normally without it, and it is
-- offered again in a later session that can record it.
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
        if not startup.coreReady or startup.state == "failed" then return false end
    end
    return true
end
M.CanRecordSeen = CanRecordSeen

local function MarkReleaseSeen()
    if not CanRecordSeen() then return false end
    NexusDB.lastChangelogSeen = RELEASE_KEY
    -- The settings table belongs to the Store owner when it is bound.
    local settings = Nexus.Store and Nexus.Store.Settings and Nexus.Store.Settings()
    if type(settings) ~= "table" then
        NexusDB.settings = type(NexusDB.settings) == "table" and NexusDB.settings or {}
        settings = NexusDB.settings
    end
    settings.lastChangelogSeen = RELEASE_KEY
    return true
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
    if HasSeenRelease() then return end
    if shownThisSession then
        -- The note was displayed while the saved-data owner was still not
        -- writable. Record the acknowledgement as soon as it is, without
        -- showing the same note a second time in this session.
        MarkReleaseSeen()
        return
    end
    if not NexusDB.hasSeenQuickStart then
        MarkReleaseSeen()
        return
    end
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
local elapsed, armed, attempts = 0, false, 0
local MAX_ATTEMPTS = 10 -- bounded: about 20 seconds, then it stops for good
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function() armed = true; elapsed = 0; attempts = 0 end)
ev:SetScript("OnUpdate", function(_, dt)
    if not armed then return end
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed < 2 then return end
    elapsed, attempts = 0, attempts + 1
    pcall(M.ShowIfNeeded)
    -- A start-up whose saved-data owner is not writable yet is retried a few
    -- times, so a note displayed early is still recorded once the owner is
    -- ready. A session that cannot record it at all simply stops trying.
    local ok, seen = pcall(HasSeenRelease)
    if attempts >= MAX_ATTEMPTS or (ok and seen) then armed = false end
end)
