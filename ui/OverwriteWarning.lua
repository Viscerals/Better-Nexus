-- Explicit UI consent. This module never performs a game/save action.
Nexus = Nexus or {}
local M = { VERSION = 1 }
Nexus.OverwriteWarning = M
local frame, active, onboardingOutcome
local TEXT_HEAD = "Auto can overwrite your active game Saved Build. It may replace Echoes you value, including Echoes obtained with Orbs. Nexus cannot undo that save or recover spent Orbs.\n\nAfter a finished run at level 80, changing the assignment or saving edits to its assigned Wishlist can cause replacement without a new run.\n\n"
local TEXT_TAIL = "Choose No to keep Auto OFF. Opening this warning does not enable Auto."
local TEXT = TEXT_HEAD .. TEXT_TAIL
-- The first-launch warning's answers are Continue / Close (BindAnswers), so its
-- closing choice names Close. The Auto warning and any other kind keep TEXT_TAIL.
local ONBOARDING_TEXT = TEXT_HEAD .. "Choose Close to keep Auto OFF. Opening this warning does not enable Auto."

-- The Auto warning (kind "auto") also lists what Auto may do, from the
-- current permissions (Readout.AutomationScopeLines, read only), and what it
-- does to tomes (Readout.TOME_PARAGRAPH), before the closing choice. The
-- first-launch warning keeps TEXT_HEAD and ends with its own Close choice
-- (ONBOARDING_TEXT), with or without Readout. Reading changes nothing.
local function BodyText(kind)
    if kind == "onboarding" then return ONBOARDING_TEXT end
    local readout = Nexus.Readout
    if kind ~= "auto" or not (readout and type(readout.AutomationScopeLines) == "function") then return TEXT end
    local store, internals = Nexus.Store, Nexus.MainInternals
    local okSettings, settings = false, nil
    if store and type(store.Settings) == "function" then okSettings, settings = pcall(store.Settings) end
    local okRead, readOnly = false, nil
    if internals and type(internals.SavedRootReadOnlyV1) == "function" then
        okRead, readOnly = pcall(internals.SavedRootReadOnlyV1)
    end
    local lines = readout.AutomationScopeLines({selected = false, settings = okSettings and settings or nil,
        readOnly = okRead and readOnly ~= nil and readOnly ~= false})
    -- Without its first line ("Auto: OFF ..."): this warning is the step that turns it ON.
    local scope = {}
    for index = 2, #lines do scope[#scope + 1] = lines[index] end
    scope[#scope + 1] = "Current values: ... menu on the Nexus panel, Automation settings."
    return TEXT_HEAD .. table.concat(scope, "\n") .. "\n\n"
        .. (type(readout.TOME_PARAGRAPH) == "string" and (readout.TOME_PARAGRAPH .. "\n\n") or "")
        .. TEXT_TAIL
end

local function CurrentOwner()
    local store = Nexus.Store
    if not store or type(store.CurrentOwnerKey) ~= "function" then return nil end
    local ok, owner = pcall(store.CurrentOwnerKey)
    return ok and owner or nil
end

local function Suppressed(kind)
    local prefs = type(NexusDB) == "table" and rawget(NexusDB, "overwriteWarnings")
    local entry = type(prefs) == "table" and rawget(prefs, kind)
    return type(entry) == "table" and rawget(entry, "version") == M.VERSION
        and rawget(entry, "suppressed") == true
end

local function SaveSuppression(request)
    if type(NexusDB) ~= "table" or NexusDB ~= request.database then return false end
    local store = Nexus.Store
    if type(store) ~= "table" or type(store.StateWriteStatus) ~= "function" then return false end
    local ok, status = pcall(store.StateWriteStatus)
    if not ok or type(status) ~= "table" or status.mode ~= "durable" then return false end
    if type(Nexus.StartupStatus) ~= "function" then return false end
    local ready, startup = pcall(Nexus.StartupStatus)
    if not ready or type(startup) ~= "table" or not startup.coreReady then return false end
    local prefs = rawget(NexusDB, "overwriteWarnings")
    if prefs ~= nil and type(prefs) ~= "table" then return false end
    local entry = prefs and rawget(prefs, request.kind)
    -- Preserve unknown/future saved values rather than repairing them here.
    if entry ~= nil then
        if type(entry) ~= "table" then return false end
        local version, suppressed = rawget(entry,"version"), rawget(entry,"suppressed")
        if type(version) ~= "number" or version ~= version or version < 0
            or version > M.VERSION or version ~= math.floor(version)
            or type(suppressed) ~= "boolean" then return false end
    end
    if not prefs then prefs = {}; NexusDB.overwriteWarnings = prefs end
    entry = entry or {}
    entry.version = M.VERSION; entry.suppressed = true
    prefs[request.kind] = entry
    return true
end

local function ReadingClock()
    if type(GetTime) ~= "function" then return nil end
    local ok, now = pcall(GetTime)
    if not ok or type(now) ~= "number" or now ~= now or now < 0
        or now >= math.huge then return nil end
    return now
end

local function Remaining()
    if not active or active.kind ~= "onboarding" then return 0 end
    local now = ReadingClock()
    if not now then
        active.startedAt, active.lastClock = nil, nil
        return 5
    end
    -- An unavailable or reversed clock proves no reading interval. Recover
    -- from the first valid sample instead of inventing a time-zero deadline.
    if not active.startedAt or (active.lastClock and now < active.lastClock) then
        active.startedAt = now
    end
    active.lastClock = now
    return math.max(0, math.ceil(5 - (now - active.startedAt)))
end

-- An explicit No, Close (X) or Escape of the first-launch warning continues
-- to the existing informational setup (QuickStart.ShowSetup), opened after
-- this request is revoked and hidden so that it finds no open warning. That
-- route records no acknowledgement, grants no consent and never turns Auto
-- ON. A missing or failing route opens nothing; there is no consent fallback.
local function ShowInformation()
    local quick = Nexus.QuickStart
    if type(quick) ~= "table" or type(quick.ShowSetup) ~= "function" then return false end
    return (pcall(quick.ShowSetup))
end

local UpdateCountdown
-- explicit: true only from the No and Close (X) buttons and the Escape key
-- handler. A raw OnHide (the frame hidden by another route) and CancelAuto
-- pass none, so they decline only.
local function Finish(yes, closing, explicit)
    if not active then return false end
    if not closing and Remaining() > 0 then
        UpdateCountdown()
        return false
    end
    local request, value = active, frame.suppress:GetChecked()
    local checked = value == true or value == 1 -- legacy CheckButton return contract
    active = nil -- revoke before Hide/callbacks so reentrancy cannot accept twice
    frame:SetScript("OnUpdate", nil)
    frame:Hide()
    yes = yes == true and request.database == NexusDB and request.ownerKey == CurrentOwner()
    if request.kind == "onboarding" then onboardingOutcome = yes and "accepted" or "declined" end
    if yes then
        if checked then SaveSuppression(request) end
        -- The runtime's original welcome check runs once. Resume that existing
        -- first-time navigation after reading; this grants no Auto permission.
        if request.kind == "onboarding" and Nexus.QuickStart then Nexus.QuickStart.ShowIfFirstTime() end
        if request.accept then return request.accept() end
    end
    -- A declined first-launch warning continues to information only, and only
    -- for the saved root and character it was opened for: a stale answer
    -- opens nothing for another context. Auto answers never navigate.
    if not yes and explicit == true and request.kind == "onboarding"
        and request.database == NexusDB and request.ownerKey == CurrentOwner() then
        ShowInformation()
    end
    return false
end

UpdateCountdown = function()
    local remaining = Remaining()
    if remaining ~= frame.lastCountdown then
        frame.lastCountdown = remaining
        frame.countdown:SetText(remaining > 0 and ("Read the warning: " .. remaining .. " seconds")
            or "Do you understand?")
    end
    if remaining == 0 then
        frame.yes:Enable(); frame.no:Enable(); frame.suppress:Enable()
        frame.suppress:EnableMouse(true)
        frame:SetScript("OnUpdate", nil)
    else
        frame.yes:Disable(); frame.no:Disable(); frame.suppress:Disable()
        frame.suppress:SetChecked(false); frame.suppress:EnableMouse(false)
        frame:SetScript("OnUpdate", UpdateCountdown)
    end
end

local function EnsureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "NexusOverwriteWarning", UIParent)
    frame:SetSize(520, 410); frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG"); frame:SetFrameLevel(100)
    frame:SetClampedToScreen(true); frame:EnableMouse(true); frame:EnableKeyboard(true)
    frame:Hide()
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=false,edgeSize=16,insets={left=5,right=5,top=5,bottom=5}})
    frame:SetBackdropColor(.055,.065,.09,1)
    local heading = frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    heading:SetPoint("TOPLEFT",24,-22); heading:SetWidth(472)
    heading:SetJustifyH("LEFT"); heading:SetText("Saved Build overwrite warning")
    local scroll = CreateFrame("ScrollFrame","NexusOverwriteWarningScroll",frame,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",24,-58); scroll:SetSize(446,230)
    local content = CreateFrame("Frame",nil,scroll); content:SetWidth(446)
    scroll:SetScrollChild(content)
    local body = content:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    body:SetPoint("TOPLEFT"); body:SetWidth(446); body:SetJustifyH("LEFT")
    body:SetText(TEXT); body:SetHeight(math.max(220,body:GetStringHeight()))
    content:SetHeight(body:GetHeight()); frame.body = body; frame.scroll = scroll; frame.content = content
    frame.suppress = CreateFrame("CheckButton",nil,frame,"UICheckButtonTemplate")
    frame.suppress:SetSize(24,24); frame.suppress:SetPoint("TOPLEFT",24,-298)
    local label = frame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    label:SetPoint("LEFT",frame.suppress,"RIGHT",4,0); label:SetText("Don't warn again")
    frame.suppress:SetScript("OnClick",function(self)
        if not active then
            self:SetChecked(false)
        elseif Remaining() > 0 then
            self:SetChecked(false)
            UpdateCountdown()
        end
    end)
    frame.countdown = frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    frame.countdown:SetPoint("TOPLEFT",24,-332); frame.countdown:SetWidth(472)
    frame.countdown:SetJustifyH("LEFT")
    frame.yes = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    frame.no = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    frame.yes:SetSize(110,28); frame.no:SetSize(110,28)
    frame.yes:SetPoint("BOTTOMRIGHT",-148,20); frame.no:SetPoint("BOTTOMRIGHT",-24,20)
    frame.yes:SetText("Yes"); frame.no:SetText("No")
    frame.yes:SetScript("OnClick",function() return Finish(true,false) end)
    frame.no:SetScript("OnClick",function() return Finish(false,false,true) end)
    frame.close = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    frame.close:SetSize(24,24); frame.close:SetPoint("TOPRIGHT",-14,-14); frame.close:SetText("X")
    frame.close:SetScript("OnClick",function() return Finish(false,true,true) end)
    -- Hidden by another route: decline only, with no navigation. A raw
    -- client UISpecialFrames close (this frame's name is listed below) is
    -- MODELLED in offline coverage as a plain Hide of the frame, which
    -- reaches only this OnHide; it is deliberately not an explicit answer
    -- and opens nothing. The explicit Escape route is the OnKeyDown script
    -- below. Offline, tests/prototype/ux_setup_replay.lua S7 (and S1) call
    -- that registered key script directly with "ESCAPE" and press no native
    -- key. The native client's dispatch (whether it delivers an Escape press
    -- to this keyboard-enabled frame and how its UISpecialFrames close hides
    -- it), the order of the two, and whether that same Escape also closes
    -- the Welcome opened here are NOT_RUN and were not checked against a
    -- client export: an unverified native boundary, not a proven runtime
    -- defect.
    frame:SetScript("OnHide",function() if active then Finish(false,true) end end)
    frame:SetScript("OnKeyDown",function(_,key) if key == "ESCAPE" then Finish(false,true,true) end end)
    UISpecialFrames[#UISpecialFrames+1] = "NexusOverwriteWarning"
    if Nexus.Theme and Nexus.Theme.StyleButton then
        Nexus.Theme.StyleButton(frame.yes); Nexus.Theme.StyleButton(frame.no)
        Nexus.Theme.StyleButton(frame.close)
    end
    return frame
end

-- Answer labels, bound again on every Show for that warning's kind. The
-- first-launch warning names what its answers do: Continue is the existing
-- Yes (reading, affirmation, optional checked opt-out, first-time Welcome;
-- it grants no Auto) and Close is the existing No (disabled until the
-- reading interval ends, then information only). The Auto warning keeps
-- Yes / No with its explicit Auto acceptance and refusal. Labels and fit
-- only: frame.yes and frame.no keep their callbacks. "Close (X)" elsewhere
-- in this file is the X button.
local ONBOARDING_YES = "Continue \226\128\148 Auto stays OFF" -- U+2014 em dash
local ANSWER_W, ANSWER_GAP, ANSWER_EDGE, WINDOW_W = 110, 14, 24, 520

-- Width for a button's current label: never below the original 110 px and
-- never capped, so the only copy of a label is not cut. That no-cut claim is
-- an offline-model result (tests/prototype/quickstart_layout_fit.lua, with
-- the 24 px end-cap allowance of FitButtonWidth, not a measurement of the
-- native button template); native pixel fit is NOT_RUN. LayoutMetrics
-- (FitButtonWidth: the client's text width or its conservative model, plus a
-- stated 24 px end-cap allowance) loads after this module and standalone tests
-- omit it; without it the same rule runs here: the client's text width, or
-- LayoutMetrics' conservative model (7 px per visible character, or 0.70 em
-- of the 10 px font at the runtime font scale read from NexusFontNormal as
-- LayoutMetrics does: 14 px at scale 2). An unavailable or invalid text
-- width uses that model; an unavailable or invalid font size reads as scale 1.
local function FitAnswer(button)
    local metrics = Nexus.LayoutMetrics
    if type(metrics) == "table" and type(metrics.FitButtonWidth) == "function" then
        local ok, width = pcall(metrics.FitButtonWidth, button, ANSWER_W)
        width = ok and tonumber(width) or nil
        if width and width >= ANSWER_W and width < math.huge then return width end
    end
    local width
    if type(button.GetTextWidth) == "function" then
        local ok, value = pcall(button.GetTextWidth, button)
        value = ok and tonumber(value) or nil
        if value and value > 0 and value < math.huge then width = value end
    end
    if not width then
        local text = tostring(button:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local scale, font = 1, _G.NexusFontNormal
        if type(font) == "table" and type(font.GetFont) == "function" then
            local ok, _, size = pcall(font.GetFont, font)
            size = ok and tonumber(size) or nil
            if size and size > 0 then scale = math.min(2, math.max(0.75, size / 12)) end
        end
        width = #(text:gsub("[\128-\191]", "")) * math.max(7, 7 * scale)
    end
    width = math.max(ANSWER_W, math.ceil(width + 24))
    button:SetWidth(width)
    return width
end

-- No keeps its anchor (BOTTOMRIGHT -24/20); Yes sits 14 px left of it at its
-- fitted width, so 110 px answers give the original row. The window stays
-- 520 px and grows only if both answers would not otherwise fit inside it.
local function BindAnswers(kind)
    local onboarding = kind == "onboarding"
    frame.yes:SetText(onboarding and ONBOARDING_YES or "Yes")
    frame.no:SetText(onboarding and "Close" or "No")
    local noWidth, yesWidth = FitAnswer(frame.no), FitAnswer(frame.yes)
    frame:SetWidth(math.max(WINDOW_W, 2 * ANSWER_EDGE + noWidth + ANSWER_GAP + yesWidth))
    frame.yes:ClearAllPoints()
    frame.yes:SetPoint("BOTTOMRIGHT", -(ANSWER_EDGE + noWidth + ANSWER_GAP), 20)
end

local function Show(kind, owner, accept)
    if active then return false end
    EnsureFrame()
    active = {kind=kind,owner=owner,accept=accept,database=NexusDB,ownerKey=CurrentOwner()}
    -- This kind's text, measured again for the scroll area (text only).
    local body = frame.body
    body:SetText(BodyText(kind)); body:SetHeight(0)
    body:SetHeight(math.max(220, tonumber(body:GetStringHeight()) or 0))
    frame.content:SetHeight(body:GetHeight())
    frame.suppress:SetChecked(false); frame.lastCountdown = nil
    frame.yes:Disable(); frame.no:Disable(); frame.suppress:Disable()
    frame.suppress:EnableMouse(false); frame.scroll:SetVerticalScroll(0)
    BindAnswers(kind)
    frame:Show(); UpdateCountdown()
    return false
end

function M.EnsureOnboarding()
    -- Reading the same warning once is session-wide; rebinding saved data
    -- does not undo that reading. Active requests still reject a changed root.
    if Suppressed("onboarding") then onboardingOutcome = "accepted"; return "accepted" end
    if onboardingOutcome then return onboardingOutcome end
    Show("onboarding")
    return "pending"
end

function M.RequestAuto(owner, accept)
    if active then return false end
    -- An Auto control cannot bypass the first-open reading delay.
    if M.EnsureOnboarding() == "pending" then return false end
    if Suppressed("auto") then return accept() end
    return Show("auto",owner,accept)
end

function M.CancelAuto(owner)
    if active and active.kind == "auto" and active.owner == owner then Finish(false,true); return true end
    return false
end

-- Read-only: whether a warning is open and waiting for its answer now. The
-- informational setup replay waits for that answer instead of opening over
-- it; asking changes nothing.
function M.IsOpen() return active ~= nil end

return M
