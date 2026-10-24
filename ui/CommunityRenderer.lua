-- Nexus: ui/CommunityRenderer.lua
-- Community main/detail frame, virtual-row pool, and binding owner.

Nexus = Nexus or {}
Nexus.CommunityInternals = Nexus.CommunityInternals or {}

local Renderer = {}

-- Shown in a detail view when the record's owner is not established (the
-- name itself carries no provenance text). A statement about identity only:
-- it says nothing about the record's Echoes, locked targets or DPS.
local OWNER_NOT_ESTABLISHED = "|cff999999Owner identity not established.|r"

-- The current Sync mode, in the words Help, the Welcome and the Leaderboard
-- use. Off and Manual are core/SyncModePolicy.lua's own text. Automatic names
-- what that mode may send without a click (traced in
-- docs/9020_SYNC_AND_NO_GUARANTEE.md). Reading the mode writes nothing.
local SYNC_AUTOMATIC_TEXT = "Sync is Automatic: Nexus may send without a click (login requests, answers to other users, your new DPS bests with your character name)."
local function SyncModeLine()
    local policy = Nexus and Nexus.SyncModePolicy
    if not (policy and type(policy.Mode) == "function") then return nil end
    local mode = policy.Mode()
    if mode == "automatic" then return SYNC_AUTOMATIC_TEXT end
    return type(policy.Text) == "function" and policy.Text(mode) or nil
end

-- The one optional Sync mode choice (beside Sync Now). Opening it makes an
-- uncommitted draft of the current effective mode; selecting an option
-- changes only the draft. Cancel, X, Escape (UISpecialFrames), closing the
-- Build Library, reopening it and a stale draft discard the draft and write
-- nothing. Only Apply calls SyncModePolicy.ApplyChoice, which saves through
-- the Store owner and reports the result read back from the Store. Neither
-- opening nor Apply starts, flushes or pumps any Sync work.
local SyncModeDialog = {
    MODES = {"automatic", "manual", "off"},
    LABEL = {automatic="Automatic", manual="Manual", off="Off"},
    HELP = {
        automatic="May send without a click: login requests, answers and newly eligible character-best DPS on Training Dummy or Lich King (Echoes, any locked Echoes, player info).",
        manual="Sends only what you start: Sync Now, and a Share with the answers to players who fetch it.",
        off="Sends nothing. Nexus still receives, and local records are kept.",
    },
    REASON = {
        database="no saved data is loaded",
        ["saved-format"]="this saved data uses a format this version keeps read-only",
        loading="saved data is still loading",
        lifecycle="saved data is not usable right now",
        settings="the saved settings are not usable",
        stale="the saved data changed after this window opened; open Sync mode again",
        replaced="saved data was replaced after loading; reload the interface first",
        ["invalid-value"]="that is not a Sync mode",
        unavailable="saving is not available",
        ["not read back"]="the saved choice could not be read back",
    },
}

function SyncModeDialog.Describe(status)
    if type(status) ~= "table" then
        return "Current: unknown (the saved-data owner is not available)."
    end
    local label = SyncModeDialog.LABEL[status.effective] or "Automatic"
    if status.explicit then return "Current: " .. label .. ", your saved choice." end
    if status.inheritedSource == "legacy" then
        return "Current: " .. label .. ", from accepted saved settings of another Nexus version (no choice of yours saved)."
    end
    return "Current: " .. label .. ", the default (no choice saved)."
end

function SyncModeDialog.Select(mode)
    local d = SyncModeDialog.frame
    if not (d and d._draft and SyncModeDialog.LABEL[mode]) then return end
    d._draft.mode = mode
    for _, option in ipairs(d.options) do option:SetChecked(option.mode == mode) end
end

function SyncModeDialog.Ensure()
    local d = SyncModeDialog.frame
    if d then return d end
    d = CreateFrame("Frame", "NexusSyncModeDialog", UIParent)
    SyncModeDialog.frame = d
    d:SetSize(460, 430)
    d:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:EnableMouse(true)
    d:Hide()
    pcall(function()
        d:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
            tile=true, tileSize=32, edgeSize=32,
            insets={left=11, right=12, top=12, bottom=11}})
    end)
    d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.title:SetPoint("TOP", 0, -16)
    d.title:SetText("Sync mode")
    local function Text(name, template, y, height)
        local fs = d:CreateFontString(nil, "OVERLAY", template)
        fs:SetPoint("TOPLEFT", 24, y)
        fs:SetSize(412, height)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        d[name] = fs
        return fs
    end
    Text("current", "GameFontHighlightSmall", -44, 34)
    d.options = {}
    for index, mode in ipairs(SyncModeDialog.MODES) do
        local top = -86 - (index - 1) * 74
        local option = CreateFrame("CheckButton", nil, d, "UIRadioButtonTemplate")
        option:SetSize(20, 20)
        option:SetPoint("TOPLEFT", 24, top)
        option.mode = mode
        option.label = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        option.label:SetPoint("TOPLEFT", 50, top - 2)
        option.label:SetSize(386, 17)
        option.label:SetJustifyH("LEFT")
        option.label:SetText(SyncModeDialog.LABEL[mode])
        option.help = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        option.help:SetPoint("TOPLEFT", 50, top - 20)
        option.help:SetSize(386, 51)
        option.help:SetJustifyH("LEFT")
        option.help:SetJustifyV("TOP")
        option.help:SetText(SyncModeDialog.HELP[mode])
        option:SetScript("OnClick", function(self) SyncModeDialog.Select(self.mode) end)
        d.options[index] = option
    end
    Text("note", "GameFontDisableSmall", -312, 34):SetText(
        "Apply saves only your choice. It sends nothing by itself, and messages already sent stay sent.")
    Text("result", "GameFontHighlightSmall", -350, 34)
    d.apply = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    d.apply:SetSize(84, 22)
    d.apply:SetPoint("BOTTOMRIGHT", -112, 16)
    d.apply:SetText("Apply")
    d.apply:SetScript("OnClick", function() SyncModeDialog.Apply() end)
    d.cancel = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    d.cancel:SetSize(84, 22)
    d.cancel:SetPoint("BOTTOMRIGHT", -20, 16)
    d.cancel:SetText("Cancel")
    d.cancel:SetScript("OnClick", function() d:Hide() end)
    d.close = CreateFrame("Button", nil, d, "UIPanelCloseButton")
    d.close:SetSize(32, 32)
    d.close:SetPoint("TOPRIGHT", -4, -4)
    d.close:SetScript("OnClick", function() d:Hide() end)
    -- Every way the window goes away discards the draft; nothing is saved.
    d:SetScript("OnHide", function(self) self._draft = nil; self._onApplied = nil end)
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "NexusSyncModeDialog")
    end
    local theme = Nexus.Theme
    if theme and theme.StyleWindow then pcall(theme.StyleWindow, d, 0.97) end
    return d
end

function SyncModeDialog.Open(owner, onApplied)
    local d = SyncModeDialog.Ensure()
    -- Reopening replaces the draft: the earlier one is discarded unsaved.
    if d:IsShown() then d:Hide() end
    if owner and not owner._nexusSyncModeHooked then
        owner._nexusSyncModeHooked = true
        owner:HookScript("OnHide", function()
            local dialog = SyncModeDialog.frame
            if dialog and dialog:IsShown() then dialog:Hide() end
        end)
    end
    local policy = Nexus.SyncModePolicy
    local status = policy and type(policy.Choice) == "function" and policy.Choice() or nil
    d._draft = {mode=status and status.effective or "automatic",
        token=status and status.token or nil}
    d._onApplied = onApplied
    d.current:SetText(SyncModeDialog.Describe(status))
    if status and status.writable then
        d.apply:Enable()
        d.result:SetText("")
    else
        d.apply:Disable()
        d.result:SetText("Sync mode cannot be changed here: "
            .. (SyncModeDialog.REASON[status and status.reason] or "saving is not available")
            .. ". Nothing will be saved.")
    end
    SyncModeDialog.Select(d._draft.mode)
    d:Show()
    return d
end

function SyncModeDialog.Apply()
    local d = SyncModeDialog.frame
    local draft = d and d:IsShown() and d._draft
    if not draft then return false, "no-draft" end
    local policy = Nexus.SyncModePolicy
    if not (policy and type(policy.ApplyChoice) == "function") then
        d.result:SetText("Not saved: saving is not available.")
        return false, "unavailable"
    end
    local ok, result, status = policy.ApplyChoice(draft.mode, draft.token)
    local chosen = SyncModeDialog.LABEL[draft.mode]
    local now = type(status) == "table" and SyncModeDialog.LABEL[status.effective] or "unknown"
    local line
    if ok then
        line = result == "unchanged"
            and ("Unchanged: " .. chosen .. " was already your saved choice. Nothing was written or sent.")
            or ("Saved: your Sync mode is now " .. now .. ". Nothing was sent by this change.")
        d.current:SetText(SyncModeDialog.Describe(status))
        d._draft = {mode=status.effective, token=status.token}
        local applied = d._onApplied
        if type(applied) == "function" then pcall(applied, result, status) end
    else
        line = "Not saved: " .. (SyncModeDialog.REASON[result] or tostring(result))
            .. ". Your Sync mode is still " .. now .. "."
        if result == "stale" then
            d._draft = nil
            d.apply:Disable()
        end
    end
    d.result:SetText(line)
    print("|cff7fd5ffNexus:|r Sync mode: " .. line)
    return ok, result, status
end

local function DisplayRemoteText(value, maxBytes, allowEmpty, allowLineBreaks)
    local identity = Nexus and Nexus.Identity
    if not (identity and type(identity.DisplaySafeText) == "function") then
        return nil
    end
    return identity.DisplaySafeText(
        value, maxBytes, allowEmpty, allowLineBreaks)
end

local function IsSavedMirror(build)
    local identity = Nexus and Nexus.Identity
    return identity and type(identity.SavedMirrorKind) == "function"
        and identity.SavedMirrorKind(build) == "saved" or false
end

local function InstallPopupDragHandle(parent)
    parent:SetMovable(true)
    local handle = CreateFrame("Frame", nil, parent)
    handle:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -6)
    handle:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -38, -6)
    handle:SetHeight(28)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() parent:StartMoving() end)
    handle:SetScript("OnDragStop", function() parent:StopMovingOrSizing() end)
    return handle
end

local function ConfigureDescriptionEdit(box, scroll, width, minimumHeight)
    box:SetMultiLine(true)
    box:SetWidth(width)
    box:SetHeight(minimumHeight)
    box:SetAutoFocus(false)
    box:SetFontObject(Nexus.LayoutMetrics
        and Nexus.LayoutMetrics.FontObject("normal")
        or "GameFontHighlightSmall")
    box:SetMaxLetters(2000)
    box:EnableMouse(true)
    box:EnableKeyboard(true)
    box._nexusDescriptionScroll = scroll
    box._nexusDescriptionMinHeight = minimumHeight
    box._nexusDescriptionWrap = math.max(1, math.floor(width / 7))
    box:SetScript("OnMouseDown", function(self, button)
        if button == nil or button == "LeftButton" then self:SetFocus() end
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self)
        local measured
        if type(self.GetStringHeight) == "function" then
            local ok, height = pcall(self.GetStringHeight, self)
            if ok and tonumber(height) and tonumber(height) > 0 then
                measured = tonumber(height) + 8
            end
        end
        if not measured then
            local lines, wrap = 0, self._nexusDescriptionWrap
            for line in (tostring(self:GetText() or "") .. "\n"):gmatch("(.-)\n") do
                lines = lines + math.max(1, math.ceil(#line / wrap))
            end
            measured = lines * 14 + 8
        end
        self:SetHeight(math.max(self._nexusDescriptionMinHeight, measured))
    end)
    box:SetScript("OnCursorChanged", function(self, _, y, _, height)
        local owner = self._nexusDescriptionScroll
        if not owner then return end
        local offset = tonumber(owner:GetVerticalScroll()) or 0
        local viewport = tonumber(owner:GetHeight()) or 0
        local cursorTop = math.max(0, -(tonumber(y) or 0))
        local cursorBottom = cursorTop + (tonumber(height) or 0)
        if cursorTop < offset then
            owner:SetVerticalScroll(cursorTop)
        elseif viewport > 0 and cursorBottom > offset + viewport then
            owner:SetVerticalScroll(cursorBottom - viewport)
        end
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = tonumber(self:GetVerticalScroll()) or 0
        self:SetVerticalScroll(math.max(0,
            current - (tonumber(delta) or 0) * 24))
    end)
    scroll:SetScrollChild(box)
end

local function ConfigureSafeEditableText(box, maxBytes, allowLineBreaks)
    local priorChanged = box:GetScript("OnTextChanged")
    box._nexusRawMaxBytes = maxBytes
    box:SetMaxLetters(maxBytes * 2)
    local function CommitRaw(self, raw, display)
        self._nexusRawText = raw
        self._nexusDisplayText = display
        if self:GetText() ~= display then
            self._nexusNormalizing = true
            self:SetText(display)
            self._nexusNormalizing = nil
        end
        if priorChanged then priorChanged(self) end
        return raw
    end
    box._NexusSetRawText = function(self, value)
        local raw = tostring(value or "")
        local display = DisplayRemoteText(raw, maxBytes, true, allowLineBreaks)
        if display == nil then
            CommitRaw(self, "", "")
            return nil
        end
        return CommitRaw(self, raw, display)
    end
    box._NexusRawText = function(self)
        local current = tostring(self:GetText() or "")
        if current ~= self._nexusDisplayText then
            local changed = self:GetScript("OnTextChanged")
            if changed then changed(self) end
        end
        return self._nexusRawText or current
    end
    box:SetScript("OnTextChanged", function(self)
        if self._nexusNormalizing then return end
        local raw = tostring(self:GetText() or ""):gsub("||", "|")
        local display = DisplayRemoteText(raw, maxBytes, true, allowLineBreaks)
        if display == nil then
            CommitRaw(self, self._nexusRawText or "",
                self._nexusDisplayText or "")
            return
        end
        CommitRaw(self, raw, display)
    end)
end

-- Detail panel geometry for its current size and font line: a fixed header,
-- the action row at the bottom (wrapping to a second row when the labels do
-- not fit one), and between them a scrolled body whose child is exactly as
-- tall as its flowed, measured content.
local function LayoutDetailPanel(p)
    local metrics = Nexus.LayoutMetrics
    if not (p and p.body and metrics) then return end
    local width = math.max(200, math.floor(tonumber(p:GetWidth()) or 500))
    local height = math.max(120, math.floor(tonumber(p:GetHeight()) or 570))
    local line = math.max(12, tonumber(p._nexusLine) or 14)
    local gap = math.max(4, tonumber(p._nexusGap) or 6)
    local inner = width - 20

    -- Clear of the class icon on the left and the close button on the right,
    -- each a full line also of a wider, taller face at the same font size.
    local _, safeLine = metrics.ConservativeText(p._nexusScale or 1)
    local titleH = math.max(20, line + 4, safeLine + 2)
    local authorH = math.max(12, line, safeLine)
    p.title:SetSize(math.max(80, inner - 82), titleH)
    p.author:SetSize(math.max(80, inner - 82), authorH)
    local headerBottom = math.max(44, 10 + titleH + 2 + authorH) + gap

    local buttonH = math.max(22, line + 8)
    for _, button in ipairs({p.lockBtn, p.retryShareBtn, p.editBtn}) do
        button:SetHeight(buttonH)
    end
    metrics.FitButtonWidth(p.lockBtn, 130, inner)
    metrics.FitButtonWidth(p.retryShareBtn, 130, inner)
    metrics.FitButtonWidth(p.editBtn, 96, inner)
    -- A Saved Build mirror hides Copy (lockBtn); its Share stands apart on
    -- the right, where Stop Sharing stands for other own builds.
    local left = {}
    if p.retryShareBtn:IsShown() then left[1] = p.retryShareBtn
    elseif p.lockBtn:IsShown() then left[1] = p.lockBtn end
    if p.editBtn:IsShown() then left[#left+1] = p.editBtn end
    local x, rows = 8, 1
    for _, button in ipairs(left) do
        local w = button:GetWidth()
        if x > 8 and x + w > width - 8 then x, rows = 8, rows + 1 end
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", x, 8 + (rows-1)*(buttonH+gap))
        x = x + w + 6
    end
    local right = p.deleteBtn:IsShown() and p.deleteBtn
        or p.shareBtn and p.shareBtn:IsShown() and p.shareBtn or nil
    if right then
        right:SetHeight(buttonH)
        local w = metrics.FitButtonWidth(right,
            right == p.deleteBtn and 104 or 130, inner)
        if x + w > width - 8 then rows = rows + 1 end
        right:ClearAllPoints()
        right:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -8,
            8 + (rows-1)*(buttonH+gap))
    end
    local footer = 8 + rows*buttonH + (rows-1)*gap + gap

    -- The template's scroll bar sits to the right of the scroll frame.
    local scroll, body = p.bodyScroll, p.body
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -headerBottom)
    scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -30, footer)
    local bodyW = math.max(120, width - 40)
    body:SetWidth(bodyW)

    local y = 0
    local function Place(region, h, indent)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", body, "TOPLEFT", indent or 0, -y)
        y = y + h
    end
    local function Text(fontString, minimum)
        if not fontString:IsShown() then return end
        Place(fontString, metrics.WrapHeight(fontString, bodyW, minimum))
        y = y + gap
    end
    local function Label(fontString)
        Place(fontString, metrics.WrapHeight(fontString, bodyW, 12) + 2)
    end
    Text(p.desc, 50)
    if p.linkBox:IsShown() then
        Label(p.linkLabel)
        local save = 0
        if p.linkSaveBtn:IsShown() then
            p.linkSaveBtn:SetHeight(math.max(18, line + 4))
            save = metrics.FitButtonWidth(p.linkSaveBtn, 72, 140) + 8
        end
        p.linkBox:SetSize(math.max(80, bodyW - 8 - save), math.max(18, line + 4))
        Place(p.linkBox, p.linkBox:GetHeight(), 6)
        y = y + gap
    end
    local iconSize = p.echoIcons[1]:GetWidth()
    if p.lockedLabel:IsShown() then
        Label(p.lockedLabel)
        for i, ic in ipairs(p.lockedIcons) do
            ic:ClearAllPoints()
            ic:SetPoint("TOPLEFT", body, "TOPLEFT", (i-1)*(iconSize+6), -y)
        end
        y = y + iconSize + 4 + gap
    else
        Label(p.echoLabel)
    end
    local columns = math.max(1, math.floor((bodyW + 2) / (iconSize + 2)))
    local shown = 0
    for _, ic in ipairs(p.echoIcons) do
        if ic:IsShown() then
            local col, row = shown % columns, math.floor(shown / columns)
            ic:ClearAllPoints()
            ic:SetPoint("TOPLEFT", body, "TOPLEFT", col*(iconSize+2),
                -(y + row*(iconSize+2)))
            shown = shown + 1
        end
    end
    y = y + math.ceil(shown / columns) * (iconSize + 2) + gap
    Text(p.missingText, 14)
    y = y + gap
    Text(p.recordsTitle, 12)
    Text(p.dummyRecord, 16)
    Text(p.lkRecord, 16)
    Text(p.editState, 12)
    Text(p.detailsNote, 12)
    -- The record rows are always shown, so the last text added a trailing gap.
    y = y - gap
    body:SetHeight(math.max(1, y))

    local viewport = math.max(0, height - headerBottom - footer)
    local range = math.max(0, y - viewport)
    if (tonumber(scroll:GetVerticalScroll()) or 0) > range then
        scroll:SetVerticalScroll(range)
    end
end

local function Measure(name, callback, ...)
    local performance = Nexus and Nexus.Performance
    if performance and type(performance.Measure) == "function" then
        return performance.Measure(name, callback, ...)
    end
    return callback(...)
end

local function ClockNow()
    if type(GetTime) ~= "function" then return nil end
    local ok, value = pcall(GetTime)
    value = ok and tonumber(value) or nil
    if not value or value ~= value or value >= math.huge
        or value <= -math.huge then return nil end
    return value
end

local function PublicationAge(publishedAt)
    local now = ClockNow()
    if not now or not publishedAt then return -1 end
    local age = math.max(0, math.min(2147483647, now - publishedAt))
    return math.floor(age * 10 + 0.5) / 10
end

function Renderer.New(options)
    options = type(options) == "table" and options or {}
    local M = {}
    -- Read-only: the current Sync mode line (status and Sync Now tooltip).
    M.SyncModeLine = SyncModeLine

    local Controller = assert(options.controller,
        "CommunityRenderer requires controller intentions")
    local projectionFactory = assert(options.projection,
        "CommunityRenderer requires Community projection")
    local CandidateEvidence = assert(Nexus.CandidateEvidence,
        "CandidateEvidence must load before CommunityRenderer")

    local function ControllerInstance()
        return Controller
    end

    local function LoadBuild(id)
        return ControllerInstance().Build(id)
    end

    local function Store()
        return ControllerInstance().Builds()
    end

    local function FilterSettings()
        return ControllerInstance().Filters()
    end

    local function ProjectionContext()
        return ControllerInstance().ProjectionContext()
    end

    local function IsOwnBuild(build)
        return ControllerInstance().IsOwnBuild(build)
    end

    local function IsAdmin()
        return ControllerInstance().IsAdmin()
    end

    local function SpellIcon(spellId)
        if not spellId then
            return "Interface\\Icons\\INV_Misc_QuestionMark"
        end
        local ok, _, _, icon = pcall(GetSpellInfo, spellId)
        return (ok and icon and icon ~= "") and icon
            or "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    local function DpsText(value)
        value = tonumber(value) or 0
        if value >= 1000000 then
            return string.format("%.2fM", value / 1000000)
        end
        if value >= 1000 then
            return string.format("%dk", math.floor(value / 1000))
        end
        return tostring(math.floor(value))
    end

    local function RecordBuildId(build)
        return ControllerInstance().RecordBuildId(build)
    end

    local function PublishedBuildId(build)
        local controller = ControllerInstance()
        if type(controller.PublishedBuildId) ~= "function" then return nil end
        local ok, publishedId = pcall(controller.PublishedBuildId, build)
        return ok and publishedId or nil
    end

    local function IsBuildFullyLoaded(build)
        return build and type(build.echoes) == "table"
            and #build.echoes > 0
    end

    local function DeleteBuild(id, onComplete)
        return ControllerInstance().DeleteBuild(id, onComplete)
    end

    local function EditBuild(id, title, description, link)
        return ControllerInstance().EditBuild(
            id, title, description, link)
    end

    local pendingUploads = {}
    local function PublishImportedBuild(id, onComplete)
        return ControllerInstance().PublishImportedBuild(id, onComplete)
    end

    local function PumpPendingLockIn()
        return ControllerInstance()._PumpPendingLockIn()
    end

    local function PrepareData(force)
        local controller = ControllerInstance()
        if force and type(controller.BeginSavedLoadoutImport) == "function" then
            controller.BeginSavedLoadoutImport(true)
        end
        if type(controller.HasPendingSavedLoadoutImport) == "function"
            and controller.HasPendingSavedLoadoutImport() then
            return controller.PumpSavedLoadoutImport(25)
        end
        return controller.ImportCurrentSavedLoadouts(false)
    end

    local function SelectedId()
        return ControllerInstance().SelectedId()
    end

    local function EnsureCommunityProjection()
        return projectionFactory()
    end

    local function SortedBuilds()
        local projection = EnsureCommunityProjection()
        if not (projection and type(projection.List) == "function") then
            error("Community projection unavailable")
        end
        local rows, summary, err = projection.List(FilterSettings())
        if type(rows) == "table" then return rows, summary end
        return nil, nil, err or "Community projection failed"
    end

    StaticPopupDialogs["NEXUS_LOCKIN_BUILD"] = {
        text = "Lock in '%s'?\nThis overwrites your current active wishlist.",
        button1 = "Lock In", button2 = "Cancel",
        OnAccept = function(_, data)
            ControllerInstance().AcceptLockIn(data)
        end,
        timeout=0, whileDead=true, hideOnEscape=true,
    }

    local function StopSharingReason(value)
        if value == "ROOT_MUTATION_PENDING" or value == "ROOT_ADMISSION_PENDING" then
            return "the shared build catalog is still preparing"
        elseif value == "REMOTE_TOMBSTONE_ORDER_UNPROVEN" then
            return "remote withdrawal is not supported by the available Sync protocol"
        end
        return type(value) == "string" and value ~= "" and value
            or "local removal was not confirmed"
    end

    local function ShowStopSharingResult(ok, result)
        local outcome = type(result) == "table" and result or {}
        if outcome.localRemoved == true then
            if outcome.queueAdmitted then
                print("|cff4dff80Nexus:|r Build stopped sharing locally; withdrawal queued. Peer removal is not confirmed.")
            elseif outcome.retryPending then
                print("|cffffc040Nexus:|r Build stopped sharing locally; the Sync queue is full. Withdrawal retry is pending. Peer removal is not confirmed.")
            else
                print("|cffffc040Nexus:|r Build stopped sharing locally; withdrawal not queued: "
                    .. StopSharingReason(outcome.queueReason or "Sync unavailable") .. ". Peer removal is not confirmed.")
            end
        elseif ok and outcome.localPending == true then
            print("|cffffc040Nexus:|r Stop Sharing accepted. Waiting for local removal; the shared record is still present. Peer removal is not confirmed.")
        elseif not ok then
            print("|cffff6060Nexus:|r Stop Sharing refused: "
                .. StopSharingReason(outcome.storageReason or outcome.queueReason or result) .. ".")
        else
            print("|cffffc040Nexus:|r Stop Sharing: local removal is not confirmed. Peer removal is not confirmed.")
        end
    end

    local function FinishStopSharing(id)
        local build = LoadBuild(id)
        if not build or not IsOwnBuild(build) then
            print("|cffff6060Nexus:|r Stop Sharing refused: this is not your shared build.")
            M.Refresh()
            return
        end
        local ok, result = DeleteBuild(id, ShowStopSharingResult)
        ShowStopSharingResult(ok, result)
        M.Refresh()
    end

    local function CandidateIdentity(build)
        if type(build) ~= "table" or build.id == nil
            or type(build.fingerprint) ~= "string"
            or build.fingerprint == "" then return nil end
        return type(build.id) .. ":" .. tostring(build.id)
            .. "|" .. build.fingerprint
    end

    local function CandidatePart(value)
        local text = tostring(value == nil and "" or value)
        return type(value) .. ":" .. tostring(#text) .. ":" .. text
    end

    local function CandidateSource(build)
        local identity = CandidateIdentity(build)
        if not identity then return nil, "record identity is unavailable" end
        local authoritative, lockedReason, resolution =
            ControllerInstance().LockedEchoesForBuild(build, true)
        if lockedReason and lockedReason ~= "" then return nil,lockedReason end
        if type(resolution) ~= "table" then
            resolution = {
                status=type(authoritative)=="table" and "ok" or "none",
                reason="",source=type(authoritative)=="table" and "record" or "none",
                fingerprint=type(authoritative)=="table" and "legacy" or "0",
            }
        end
        if resolution.status ~= "ok" and resolution.status ~= "none" then
            return nil,resolution.reason ~= "" and resolution.reason
                or "locked Echo evidence is unavailable"
        end
        local ordinary, locked = {}, {}
        for _, echo in ipairs(type(build.echoes) == "table"
            and build.echoes or {}) do
            if echo and not echo.locked then ordinary[#ordinary + 1] = echo end
        end
        for _, echo in ipairs(type(authoritative) == "table"
            and authoritative or {}) do
            locked[#locked + 1] = echo
        end
        local parts = {
            CandidatePart(identity),CandidatePart(resolution.fingerprint),
            CandidatePart(resolution.status),CandidatePart(build.ownerKey),
            CandidatePart(build.ownerVerified),CandidatePart(build.isMine),
            CandidatePart(build.relaySender),CandidatePart(build.sourceSavedBuildId),
            CandidatePart(build.publishedBuildId),CandidatePart(build.recordBuildId),
            CandidatePart(build.autoDps),CandidatePart(build.importedSavedBuild),
        }
        return {
            identity=identity,ordinary=ordinary,locked=locked,
            selected=table.concat(parts,"|"),title=build.title,
        }
    end

    local function BuildCandidateEvidence(build)
        local source, sourceReason = CandidateSource(build)
        if not source then return nil,sourceReason end
        local sourceId = build.id
        return CandidateEvidence.Build({
            title=source.title,
            ordinaryEchoes=source.ordinary,
            lockedEchoes=source.locked,
            sourceIdentity=source.identity,
            selectedEvidence=source.selected,
            currentEvidence=function()
                local current = LoadBuild(sourceId)
                local now = current and CandidateSource(current) or nil
                return now and now.selected or nil
            end,
        })
    end

    StaticPopupDialogs["NEXUS_STOP_SHARING_BUILD"] = {
        text = "Stop sharing '%s'?\nThis removes only the shared Nexus record. Server Saved Builds and Wishlists are unchanged.",
        button1 = "Stop Sharing", button2 = "Cancel",
        OnShow = function(self)
            -- StaticPopup slots are shared. Raise only this confirmation above
            -- the DIALOG Library, and retain the slot's layer for later reuse.
            if self._nexusStopSharingStrata == nil then
                self._nexusStopSharingStrata = self:GetFrameStrata()
            end
            self:SetFrameStrata("FULLSCREEN_DIALOG")
        end,
        OnHide = function(self)
            local strata = self._nexusStopSharingStrata
            if strata then
                self._nexusStopSharingStrata = nil
                self:SetFrameStrata(strata)
            end
        end,
        OnAccept = function(_, data)
            if type(data) == "table" and data.id then
                FinishStopSharing(data.id)
            end
        end,
        timeout=0, whileDead=true, hideOnEscape=true, preferredIndex=3,
    }

    function M.LockInSelected()
        local payload = ControllerInstance().PrepareLockInSelected()
        if not payload then return end
        local displayTitle = DisplayRemoteText(payload.title, 1024, false)
            or "this build"
        return StaticPopup_Show(
            "NEXUS_LOCKIN_BUILD", displayTitle, nil, payload)
    end

    local CARD_HEIGHT = 88
    local ICON_SIZE = 26
    local MAX_ROW_ICONS = 12
    local ECHO_ICON_SIZE = 22

    local CLASS_COLOR = {
        DEATHKNIGHT={0.77,0.12,0.23},DRUID={1.00,0.49,0.04},
        HUNTER={0.67,0.83,0.45},MAGE={0.25,0.78,0.92},
        PALADIN={0.96,0.55,0.73},PRIEST={1.00,1.00,1.00},
        ROGUE={1.00,0.96,0.41},SHAMAN={0.00,0.44,0.87},
        WARLOCK={0.53,0.53,0.93},WARRIOR={0.78,0.61,0.43},
    }
    local CLASS_LABEL = {
        DEATHKNIGHT="Death Knight",DRUID="Druid",HUNTER="Hunter",
        MAGE="Mage",PALADIN="Paladin",PRIEST="Priest",ROGUE="Rogue",
        SHAMAN="Shaman",WARLOCK="Warlock",WARRIOR="Warrior",
        UNKNOWN="Unknown",
    }
    local CLASS_ICON = {
        DEATHKNIGHT="Interface\\Icons\\Spell_DeathKnight_IceboundFortitude",
        DRUID="Interface\\Icons\\Spell_Nature_NaturesBlessing",
        HUNTER="Interface\\Icons\\Ability_Hunter_BeastCall",
        MAGE="Interface\\Icons\\Spell_Frost_Frostbolt02",
        PALADIN="Interface\\Icons\\Spell_Holy_HolyBolt",
        PRIEST="Interface\\Icons\\Spell_Holy_PowerInfusion",
        ROGUE="Interface\\Icons\\Ability_BackStab",
        SHAMAN="Interface\\Icons\\Spell_Nature_Lightning",
        WARLOCK="Interface\\Icons\\Spell_Shadow_ShadowBolt",
        WARRIOR="Interface\\Icons\\Ability_Warrior_Charge",
    }

    local frame, scrollChild, scrollFrame, scrollBar
    local detailPanel
    local searchBox, clearSearchBtn, classDropBtn, qualifiedBtn, dropPanel
    local sortToggle, sortPanel
    local scopeBtn, myBuildsBtn, syncStatusText, syncBtn, dropdownShield
    local leaderboardBtn, wishlistBtn, resultText
    local prevPageBtn, nextPageBtn, pageText
    local RenderSyncStatus
    local renderBuildWindow, virtualBinding = nil, false
    local lastPublishedPageCount = 1
    local refreshDirty = false
    local viewDiagnostic = {
        publishedAt=nil,publishedPage=0,
        projectionCurrent=false,projectionPending=false,projectionError=false,
        bundledCount=0,overlayCount=0,availableCount=0,
        filterMatchedCount=0,qualifyingCount=0,resultCount=0,
        displayedCount=0,searchActive=false,catalogVersion="unversioned",
    }
    local suppressSearchChange = false
    local virtualStats = {
        created=0,peakActive=0,active=0,results=0,
        dataRefreshes=0,dataFailures=0,
        dataBinds=0,scrollBinds=0,resizeBinds=0,
        dirtyMarks=0,deferredRefreshes=0,periodicSkips=0,
        first=1,last=0,offset=0,maxOffset=0,
    }

    -- Laid-out widgets live in the window's scrolled content (EnsureFrame), so
    -- the client clips them to the window and scrolling moves them together.
    -- At scroll 0 the content's top-left is the window's: the same places.
    local function PlaceCommunityBox(widget, box)
        if not (widget and box) then return end
        local content = frame._content or frame
        if widget:GetParent() ~= content then widget:SetParent(content) end
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT",content,"TOPLEFT",box.x,-box.y)
        widget:SetSize(box.w,box.h)
    end

    local function AvailableSize()
        local width, height = 1040, 640
        if UIParent and type(UIParent.GetWidth) == "function" then
            local ok, value = pcall(UIParent.GetWidth,UIParent)
            value = ok and tonumber(value) or nil
            if value and value >= 700 then
                width = math.max(760,math.min(1040,value-40))
            end
        end
        if UIParent and type(UIParent.GetHeight) == "function" then
            local ok, value = pcall(UIParent.GetHeight,UIParent)
            value = ok and tonumber(value) or nil
            if value and value >= 520 then
                height = math.max(520,math.min(640,value-60))
            end
        end
        return width, height
    end

    -- The visible UI the whole window must stay inside (nil when it cannot
    -- be read). LayoutMetrics.Community gives the window height for it.
    local function ViewportSize()
        if not (UIParent and type(UIParent.GetWidth) == "function"
            and type(UIParent.GetHeight) == "function") then return nil, nil end
        local okWidth, viewportWidth = pcall(UIParent.GetWidth,UIParent)
        local okHeight, viewportHeight = pcall(UIParent.GetHeight,UIParent)
        viewportWidth = okWidth and tonumber(viewportWidth) or nil
        viewportHeight = okHeight and tonumber(viewportHeight) or nil
        if not (viewportWidth and viewportHeight and viewportWidth > 0
            and viewportHeight > 0) then return nil, nil end
        return viewportWidth, viewportHeight
    end

    -- The one route that moves the window's content: the mouse wheel over the
    -- window or its scroll bar, and dragging the bar, all come here. The
    -- offset stays inside the current layout's scroll range (0 when the
    -- whole layout fits), and the bar follows it.
    local function SetContentScroll(offset)
        local scroll = frame and frame._contentScroll
        if not scroll then return 0 end
        local layout = frame._responsiveLayout
        local range = type(layout) == "table"
            and math.max(0, tonumber(layout.scrollRange) or 0) or 0
        offset = math.floor((tonumber(offset) or 0) + 0.5)
        offset = math.max(0, math.min(range, offset))
        frame._contentOffset = offset
        scroll:SetVerticalScroll(offset)
        local bar = frame._contentBar
        if bar and bar:GetValue() ~= offset then bar:SetValue(offset) end
        return offset
    end

    -- One wheel notch: two status lines at the current font scale.
    local function ContentWheelStep()
        local layout = frame and frame._responsiveLayout
        local line = type(layout) == "table" and tonumber(layout.statusLine) or 17
        return math.max(24, 2 * line)
    end

    local function ApplyCommunityLayout(layout)
        -- The window is as tall as the layout allows on screen; the content
        -- keeps the whole layout and scrolls inside it.
        local windowHeight = tonumber(layout.windowHeight) or layout.height
        frame:SetSize(layout.width,windowHeight)
        local contentScroll, content = frame._contentScroll, frame._content
        if contentScroll and content then
            contentScroll:SetSize(layout.width,windowHeight)
            content:SetSize(layout.width,layout.height)
            pcall(function() contentScroll:UpdateScrollChildRect() end)
        end

        local boxes = layout.boxes
        PlaceCommunityBox(frame._titleText,boxes.title)
        PlaceCommunityBox(frame._navBar,boxes.nav)
        PlaceCommunityBox(frame._browseLabel,boxes.browseLabel)
        PlaceCommunityBox(searchBox,boxes.search)
        PlaceCommunityBox(scopeBtn,boxes.scope)
        PlaceCommunityBox(myBuildsBtn,boxes.mine)
        PlaceCommunityBox(classDropBtn,boxes.class)
        PlaceCommunityBox(frame._qualifiedBox,boxes.qualified)
        PlaceCommunityBox(sortToggle,boxes.sort)
        PlaceCommunityBox(frame._actionLabel,boxes.actionLabel)
        PlaceCommunityBox(syncBtn,boxes.sync)
        PlaceCommunityBox(frame._modeBtn,boxes.mode)
        PlaceCommunityBox(frame._postBtn,boxes.share)
        PlaceCommunityBox(resultText,boxes.result)
        PlaceCommunityBox(prevPageBtn,boxes.prev)
        PlaceCommunityBox(pageText,boxes.page)
        PlaceCommunityBox(nextPageBtn,boxes.next)
        PlaceCommunityBox(syncStatusText,boxes.status)
        PlaceCommunityBox(frame._listClip,boxes.list)
        PlaceCommunityBox(frame._emptyState,boxes.emptyState)
        PlaceCommunityBox(detailPanel,boxes.detail)
        if frame._searchLabel and frame._content
            and frame._searchLabel:GetParent() ~= frame._content then
            frame._searchLabel:SetParent(frame._content)
        end
        if detailPanel then detailPanel:SetFrameLevel(frame:GetFrameLevel() + 10) end
        local contentBar = frame._contentBar
        if contentBar then
            local range = math.max(0, tonumber(layout.scrollRange) or 0)
            contentBar:SetMinMaxValues(0,range)
            if range > 0 then contentBar:Show() else contentBar:Hide() end
        end

        if detailPanel and boxes.detail then
            local inner = math.max(120,boxes.detail.w-20)
            detailPanel._nexusLine, detailPanel._nexusGap = layout.normal, layout.gap
            detailPanel._nexusScale = layout.scale
            LayoutDetailPanel(detailPanel)
            for _, row in ipairs(detailPanel.lbDummyRows) do row:SetWidth(inner) end
            for _, row in ipairs(detailPanel.lbLKRows) do row:SetWidth(inner) end
            detailPanel.lbDummyEmpty:SetWidth(inner)
            detailPanel.lbDummyPersonal:SetWidth(inner)
            detailPanel.lbLKEmpty:SetWidth(inner)
            detailPanel.lbLKPersonal:SetWidth(inner)
        end
        if scrollChild then scrollChild:SetWidth(layout.card.width) end
        return true
    end

    function M.ApplyResponsiveLayout(force)
        local owner = Nexus.LayoutMetrics
        if not (frame and owner) then return false end
        local width, height = AvailableSize()
        local keyOk, runtimeKey = pcall(owner.RuntimeKey,
            "community",width,height)
        if not keyOk then return false end
        -- The status region's measured rows are part of the geometry: a
        -- change of rows re-lays the window once; equal rows reuse it.
        local statusRows = tonumber(frame._nexusStatusRows)
        runtimeKey = runtimeKey .. "/s" .. tostring(statusRows or 0)
        -- The UI size sets the window height and scroll range
        -- (LayoutMetrics.Community), so a new UI size re-lays the window
        -- once; an unchanged one reuses it.
        local viewportWidth, viewportHeight = ViewportSize()
        runtimeKey = runtimeKey .. "/v" .. tostring(viewportWidth or 0)
            .. "x" .. tostring(viewportHeight or 0)
        if not force and frame._nexusRuntimeLayoutKey == runtimeKey then
            return false
        end
        local metricsOk, fontScale, uiScale, revision =
            pcall(owner.RuntimeMetrics)
        if not metricsOk then return false end
        local layoutOk, layout = pcall(owner.Community,{
            width=width,height=height,fontScale=fontScale,uiScale=uiScale,
            revision=revision,empty=virtualStats.results == 0,
            syncActive=Nexus.Sync and Nexus.Sync.IsReceiving
                and Nexus.Sync.IsReceiving() or false,
            results=virtualStats.results,
            statusRows=statusRows,
            viewportWidth=viewportWidth,viewportHeight=viewportHeight,
            labels={
                search="Search title, author, or description",
                scope="All Shared",mine="Mine",
                class="Current Class Only",qualified="Require both DPS records",
                sort="Sort: Highest DPS",sync="Listening...",
                mode="Sync mode...",share="Share Build",
            },
        })
        if not layoutOk or type(layout) ~= "table" then return false end
        local previousLayout = frame._responsiveLayout
        local applied = pcall(ApplyCommunityLayout,layout)
        if not applied then
            if type(previousLayout) == "table" then
                pcall(ApplyCommunityLayout,previousLayout)
            end
            return false
        end
        frame._nexusRuntimeLayoutKey = runtimeKey
        frame._nexusLayoutKey = layout.key
        frame._responsiveLayout = layout
        -- A new size, font or status keeps the scrolled place inside the new
        -- range (back to 0 when everything fits).
        SetContentScroll(frame._contentOffset or 0)
        return true
    end

------------------------------------------------------------------------
-- Post popup
------------------------------------------------------------------------

local postPopup, editPopup
local postTitleBox, postDescBox, editTitleBox, editDescBox
local postPreviewIcons = {}
local postWishlistBtn, postClassBtn, postWishlistMenu, postClassMenu
local RefreshPostPopupPreview

local function ClearPostDescriptionFocus()
    if postDescBox and postDescBox.ClearFocus then postDescBox:ClearFocus() end
end

local function ClearEditDescriptionFocus()
    if editDescBox and editDescBox.ClearFocus then editDescBox:ClearFocus() end
end

local CLASS_PICK_ORDER = {
    "DEATHKNIGHT", "DRUID", "HUNTER", "MAGE", "PALADIN",
    "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}

local function MakeDropdownMenu(parent, width)
    local menu = CreateFrame("Frame", nil, parent)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetWidth(width)
    menu:SetBackdrop({
        bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=12,
        insets={left=3,right=3,top=3,bottom=3},
    })
    menu:SetBackdropColor(0.03,0.03,0.03,0.98)
    menu:Hide()
    return menu
end

-- owner: the menu to close when the row is in a scrolled list inside it.
local function AddMenuButton(menu, text, onClick, index, owner)
    local b = CreateFrame("Button", nil, menu)
    b:SetHeight(22); b:SetPoint("TOPLEFT",6,-6-(index-1)*22); b:SetPoint("TOPRIGHT",-6,-6-(index-1)*22)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    local fs = b:CreateFontString(nil,"OVERLAY",Nexus.LayoutMetrics
        and Nexus.LayoutMetrics.FontObject("normal")
        or "GameFontHighlightSmall")
    fs:SetPoint("LEFT",6,0); fs:SetPoint("RIGHT",-6,0); fs:SetJustifyH("LEFT"); fs:SetText(text)
    -- One line per row; a shortened label is complete in the row tooltip.
    if Nexus.LayoutMetrics then Nexus.LayoutMetrics.OneLineLabel(fs, b, 22) end
    b:SetScript("OnClick", function() (owner or menu):Hide(); onClick() end)
    return b
end

local function HidePostMenus()
    if postWishlistMenu then postWishlistMenu:Hide() end
    if postClassMenu then postClassMenu:Hide() end
end

local function BuildWishlistCandidates()
    return ControllerInstance().PostSourceCandidates()
end

local function WishlistLabel(wl)
    local kind = DisplayRemoteText(
        (wl and wl.sourceKind) or "Wishlist", 128, false) or "Wishlist"
    local name = wl and DisplayRemoteText(wl.name, 1024, false) or nil
    if not name then name = "Unnamed " .. kind end
    -- Stated permanent copies are not part of the 79 ordinary copies.
    local count,permanent=0,0
    for _,e in ipairs((wl and wl.echoes) or {}) do
        local copies=tonumber(e.stacks or e.count) or 1
        if e.locked==true or e.locked==1 then permanent=permanent+copies else count=count+copies end
    end
    if permanent==0 then
        for _,e in ipairs((wl and type(wl.lockedEchoes)=="table" and wl.lockedEchoes) or {}) do permanent=permanent+(tonumber(e.stacks or e.count) or 1) end
    end
    -- The counts a Share of this source would really carry (for example the
    -- saved permanent targets of an editor-made Wishlist). Read-only.
    local controller=ControllerInstance()
    local roles=type(controller.ShareSourceRoles)=="function" and controller.ShareSourceRoles(wl) or nil
    if roles then count,permanent=roles.ordinary,roles.permanent end
    if permanent>0 then
        return string.format("[%s] %s  —  %d / 79 + %d / 6 locked", kind, name, count, permanent)
    end
    return string.format("[%s] %s  —  %d / 79", kind, name, count)
end

-- The controller's one sentence for the latest Share, coloured by its state.
local function ShareStatusLine()
    local controller = ControllerInstance()
    if type(controller.ShareStatusText) ~= "function" then return nil end
    local ok, state, text = pcall(controller.ShareStatusText)
    if not ok or type(text) ~= "string" then return nil end
    -- The role counts that this Share carries, so that a lost role is visible.
    local okStatus, s = pcall(controller.ShareStatus)
    if state ~= "refused" and okStatus and type(s) == "table"
        and type(s.ordinaryCopies) == "number" and type(s.permanentCopies) == "number" then
        text = text .. string.format(" Roles: %d ordinary + %d locked Echo copies.",
            s.ordinaryCopies, s.permanentCopies)
    end
    local colour = state == "refused" and "|cffff6060"
        or (state == "preparing" or state == "stopped" or state == "saved") and "|cffffc040"
        or "|cff4dff80"
    return colour .. text .. "|r", state
end

-- The result of the user's own last Share click belongs to the form. A refusal
-- stays there through every ordinary view refresh. Only a legitimate next step
-- replaces it: another Share click, another source or class, or reopening the
-- form. The latest Share of the session is shown when no refusal is held.
local postRefusal
local function SetPostRefusal(text)
    postRefusal = type(text) == "string" and text ~= "" and text or nil
end
local function PostStatusText()
    if postRefusal then return "|cffff6060" .. postRefusal .. "|r" end
    return ShareStatusLine() or ""
end

local function RefreshPostWishlistMenu()
    if not postWishlistMenu then return end
    local menu = postWishlistMenu
    -- The rows live in a list that scrolls with the mouse wheel inside the
    -- menu, so more sources than fit its 300 px never spill below it.
    if not menu._list then
        menu._scroll = CreateFrame("ScrollFrame", nil, menu)
        menu._scroll:SetPoint("TOPLEFT", 0, 0); menu._scroll:SetPoint("BOTTOMRIGHT", 0, 6)
        menu._list = CreateFrame("Frame", nil, menu._scroll)
        menu._list:SetWidth(menu:GetWidth()); menu._scroll:SetScrollChild(menu._list)
        menu._scroll:EnableMouseWheel(true)
        menu._scroll:SetScript("OnMouseWheel", function(self, delta)
            local range = math.max(0, menu._list:GetHeight() - (menu:GetHeight() - 6))
            local offset = (tonumber(self:GetVerticalScroll()) or 0) - (tonumber(delta) or 0) * 22
            self:SetVerticalScroll(math.max(0, math.min(range, offset)))
        end)
    end
    for _, child in ipairs({menu._list:GetChildren()}) do child:Hide(); child:SetParent(nil) end
    menu._scroll:SetVerticalScroll(0)
    local candidates = BuildWishlistCandidates()
    menu._list:SetHeight(12 + math.max(1, #candidates) * 22)
    postWishlistMenu:SetHeight(math.min(300, 12 + math.max(1, #candidates) * 22))
    for i, c in ipairs(candidates) do
        AddMenuButton(menu._list, WishlistLabel(c), function()
            ControllerInstance().SetPostWishlist(c)
            SetPostRefusal(nil)                         -- another source: the refusal was about the earlier one
            postWishlistBtn:SetText("Source: "
                .. (DisplayRemoteText(c.name, 1024, false) or "Unnamed"))
            RefreshPostPopupPreview()
        end, i, menu)
    end
    if #candidates == 0 then
        AddMenuButton(menu._list, "No saved builds or wishlists found", function() end, 1, menu)
        postWishlistMenu:SetHeight(40)
    end
end

local function RefreshPostClassMenu()
    if not postClassMenu then return end
    for _, child in ipairs({postClassMenu:GetChildren()}) do child:Hide(); child:SetParent(nil) end
    postClassMenu:SetHeight(12 + #CLASS_PICK_ORDER * 24)
    for i, token in ipairs(CLASS_PICK_ORDER) do
        AddMenuButton(postClassMenu, CLASS_LABEL[token], function()
            ControllerInstance().SetPostClass(token)
            SetPostRefusal(nil)
            local cc = CLASS_COLOR[token] or {1,1,1}
            postClassBtn:SetText("Class: " .. CLASS_LABEL[token])
            postClassBtn:GetFontString():SetTextColor(cc[1],cc[2],cc[3])
            RefreshPostPopupPreview()
        end, i)
    end
end

local function EnsurePostPopup()
    if postPopup then return postPopup end
    local p = CreateFrame("Frame","NexusPostPopup",UIParent)
    p:SetSize(760, 560)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:EnableMouse(true)
    p._dragHandle = InstallPopupDragHandle(p)
    p:Hide()
    pcall(function() p:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=32,insets={left=11,right=12,top=12,bottom=11}}) end)

    local titleBar = p:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    titleBar:SetPoint("TOP",0,-14); titleBar:SetText("Share a Nexus Build")
    local close = CreateFrame("Button",nil,p,"UIPanelCloseButton")
    close:SetPoint("TOPRIGHT",-2,-2); close:SetScript("OnClick",function()
        HidePostMenus(); ClearPostDescriptionFocus(); p:Hide()
    end)

    local tl = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); tl:SetPoint("TOPLEFT",16,-38); tl:SetText("Build Title:")
    postTitleBox = CreateFrame("EditBox",nil,p,"InputBoxTemplate"); postTitleBox:SetSize(330,20); postTitleBox:SetPoint("TOPLEFT",16,-54); postTitleBox:SetAutoFocus(false)
    ConfigureSafeEditableText(postTitleBox, 80, false)
    p._postTitleBox = postTitleBox

    local dl = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); dl:SetPoint("TOPLEFT",16,-88); dl:SetText("Description (what makes this build stand out):")
    local descBg = CreateFrame("Frame",nil,p); descBg:SetPoint("TOPLEFT",14,-104); descBg:SetSize(334,180)
    pcall(function() descBg:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}}); descBg:SetBackdropColor(0,0,0,0.5) end)
    local descScroll = CreateFrame("ScrollFrame","NexusPostDescriptionScroll",descBg,
        "UIPanelScrollFrameTemplate")
    descScroll:SetPoint("TOPLEFT",6,-6)
    descScroll:SetPoint("BOTTOMRIGHT",-24,6)
    postDescBox = CreateFrame("EditBox",nil,descScroll)
    ConfigureDescriptionEdit(postDescBox, descScroll, 286, 168)
    ConfigureSafeEditableText(postDescBox, 2000, true)
    p._postDescScroll = descScroll
    p._postDescBox = postDescBox

    local chooseLabel = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); chooseLabel:SetPoint("TOPLEFT",16,-302); chooseLabel:SetText("1. Choose the exact server loadout or wishlist to share:")
    postWishlistBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate"); postWishlistBtn:SetSize(334,26); postWishlistBtn:SetPoint("TOPLEFT",16,-320); postWishlistBtn:SetText("Source: Select a saved build or wishlist")
    p._postWishlistBtn = postWishlistBtn
    postWishlistMenu = MakeDropdownMenu(p,334); postWishlistMenu:SetPoint("TOPLEFT",16,-348)
    postWishlistBtn:SetScript("OnClick",function() HidePostMenus(); RefreshPostWishlistMenu(); postWishlistMenu:Show() end)

    postClassBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate"); postClassBtn:SetSize(334,26); postClassBtn:SetPoint("TOPLEFT",16,-360); postClassBtn:SetText("Class: Select a class")
    p._postClassBtn = postClassBtn
    postClassMenu = MakeDropdownMenu(p,334); postClassMenu:SetPoint("TOPLEFT",16,-388)
    postClassBtn:SetScript("OnClick",function() HidePostMenus(); RefreshPostClassMenu(); postClassMenu:Show() end)

    local previewLabel = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); previewLabel:SetPoint("TOPLEFT",380,-38); previewLabel:SetText("Exact Echo Loadout Preview:")
    local previewWishlist = p:CreateFontString(nil,"OVERLAY","GameFontHighlight"); previewWishlist:SetPoint("TOPLEFT",380,-54); previewWishlist:SetSize(350,16); previewWishlist:SetJustifyH("LEFT"); p._previewWishlist=previewWishlist
    local previewClass = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); previewClass:SetPoint("TOPLEFT",380,-74); previewClass:SetSize(350,14); previewClass:SetJustifyH("LEFT"); p._previewClass=previewClass
    local previewSummary = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); previewSummary:SetPoint("TOPLEFT",380,-92); previewSummary:SetSize(350,14); previewSummary:SetJustifyH("LEFT"); p._previewSummary=previewSummary
    local previewClip=CreateFrame("Frame",nil,p); previewClip:SetPoint("TOPLEFT",374,-112); previewClip:SetSize(370,390); pcall(function() previewClip:SetClipsChildren(true) end); p._previewClip=previewClip
    local previewScroll=CreateFrame("ScrollFrame",nil,previewClip); previewScroll:SetAllPoints(previewClip); previewScroll:EnableMouseWheel(true); p._previewScroll=previewScroll
    local previewChild=CreateFrame("Frame",nil,previewScroll); previewChild:SetWidth(360); previewChild:SetHeight(1); previewScroll:SetScrollChild(previewChild); p._previewChild=previewChild
    p._previewRows={}
    for i=1,100 do
        local row=CreateFrame("Frame",nil,previewChild); row:SetSize(355,22)
        local icon=row:CreateTexture(nil,"ARTWORK"); icon:SetSize(20,20); icon:SetPoint("LEFT",0,0); row.icon=icon
        local text=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); text:SetPoint("LEFT",26,0); text:SetSize(325,20); text:SetJustifyH("LEFT"); row.text=text; row:Hide(); p._previewRows[i]=row
    end
    local noWishlistNote=p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); noWishlistNote:SetPoint("TOPLEFT",380,-112); noWishlistNote:SetSize(350,80); noWishlistNote:SetJustifyH("LEFT"); noWishlistNote:SetJustifyV("TOP"); p._noWishlistNote=noWishlistNote

    local postGoBtn=CreateFrame("Button",nil,p,"UIPanelButtonTemplate"); postGoBtn:SetSize(150,28); postGoBtn:SetPoint("BOTTOM",0,16); postGoBtn:SetText("Share Build"); p._postGoBtn=postGoBtn
    postGoBtn:SetScript("OnClick",function()
        local wishlist, class = ControllerInstance().PostDraft()
        if not wishlist or not class then print("|cffff6060Nexus:|r Select a source loadout and class before sharing."); return end
        local ok,value,outcome=ControllerInstance().PostCurrentWishlist(
            postTitleBox:_NexusRawText(), postDescBox:_NexusRawText(),
            wishlist, class)
        if not ok then
            -- The form, its draft and its source stay. A retained earlier
            -- Share keeps its own sentence; a refusal states its reason.
            print("|cffff6060Nexus:|r "..tostring(value))
            SetPostRefusal(not outcome and tostring(value) or nil)
            p._shareStatus:SetText(PostStatusText())
            return
        end
        SetPostRefusal(nil)
        -- One sentence, from the same owner that the status line reads.
        print("Nexus: "..(ShareStatusLine() or "Share accepted."))
        ClearPostDescriptionFocus(); p:Hide(); M.Refresh()
    end)
    -- The open form follows its Share by itself: queued -> sent, a retry, a
    -- terminal stop. A passive read twice a second, only while the form is
    -- shown; it does not depend on the Community window, a view refresh, Sync
    -- housekeeping or a receive window.
    local statusElapsed=0
    p:SetScript("OnUpdate",function(_,elapsed)
        statusElapsed=statusElapsed+(tonumber(elapsed) or 0)
        if statusElapsed<0.5 then return end
        statusElapsed=0
        if p._shareStatus then
            local text=PostStatusText()
            if p._shareStatus:GetText()~=text then p._shareStatus:SetText(text) end
        end
    end)
    local shareStatus=p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); shareStatus:SetPoint("TOPLEFT",16,-396); shareStatus:SetSize(334,96); shareStatus:SetJustifyH("LEFT"); shareStatus:SetJustifyV("TOP"); p._shareStatus=shareStatus
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.ApplyFontTree then
        Nexus.LayoutMetrics.ApplyFontTree(p,"normal")
    end
    postPopup=p; return p
end

local function EchoDisplayName(spellId)
    return ControllerInstance().EchoDisplayName(spellId)
end

RefreshPostPopupPreview = function()
    if not postPopup or not postPopup:IsShown() then return end
    postPopup._shareStatus:SetText(PostStatusText())
    local wl, selectedClass = ControllerInstance().PostDraft()
    local echoes = ControllerInstance().WishlistEchoes(wl)
    if not wl or not echoes or #echoes==0 then
        for _,row in ipairs(postPopup._previewRows or {}) do row:Hide() end
        postPopup._noWishlistNote:SetText("|cffff6060No source selected.|r\n\nChoose a server Saved Build or Wishlist to share.")
        postPopup._noWishlistNote:Show(); postPopup._previewWishlist:SetText(""); postPopup._previewSummary:SetText(""); postPopup._previewClass:SetText(""); postPopup._postGoBtn:Disable(); return
    end
    postPopup._noWishlistNote:Hide(); postPopup._postGoBtn:Enable()
    local wishlistName = DisplayRemoteText(wl.name, 1024, false)
        or "Unnamed Echo Wishlist"
    local classToken=selectedClass or ControllerInstance().InferBuildClass(echoes) or ""
    postPopup._previewWishlist:SetText("|cffffd200"..wishlistName.."|r")
    -- The rows and role counts that a Share of this source carries. The
    -- permanent rows of an editor-made Wishlist are not in its server copy.
    local roles, rolesWhy = nil, nil
    if type(ControllerInstance().ShareSourceRoles) == "function" then
        roles, rolesWhy = ControllerInstance().ShareSourceRoles(wl)
    end
    if roles then
        postPopup._previewSummary:SetText(string.format("|cff888888Shares %d ordinary + %d locked Echo copies|r",
            roles.ordinary, roles.permanent))
        -- The settled lists, not the raw source rows: on the >79 path the
        -- source rows also contain the copies that become permanent.
        local shown = {}
        for _, e in ipairs(roles.ordinaryEchoes or {}) do
            shown[#shown + 1] = {spellId=e.spellId, stacks=e.stacks}
        end
        for _, e in ipairs(roles.lockedEchoes or {}) do
            shown[#shown + 1] = {spellId=e.spellId, stacks=e.stacks, locked=true}
        end
        echoes = shown
    else
        postPopup._previewSummary:SetText("|cffff6060Roles not settled: Share Build states the reason|r")
    end
    local cc=CLASS_COLOR[(classToken or ""):upper()] or {1,1,1}; postPopup._previewClass:SetTextColor(cc[1],cc[2],cc[3]); postPopup._previewClass:SetText("Posting as: "..(CLASS_LABEL[(classToken or ""):upper()] or classToken or "Select a class"))
    local child=postPopup._previewChild
    for i,row in ipairs(postPopup._previewRows or {}) do
        local e=echoes[i]
        if e then row:ClearAllPoints(); row:SetPoint("TOPLEFT",child,"TOPLEFT",0,-(i-1)*22); row.icon:SetTexture(SpellIcon(e.spellId)); local stacks=tonumber(e.stacks) or 1; local suffix=(stacks>1 and ("  x"..stacks) or "")..((e.locked==true or e.locked==1) and "  (locked)" or ""); row.text:SetText(string.format("%02d. %s%s",i,EchoDisplayName(e.spellId),suffix)); row:Show() else row:Hide() end
    end
    child:SetHeight(math.max(1,#echoes*22)); pcall(function() postPopup._previewScroll:SetVerticalScroll(0) end)
end

function M.ShowPostBuild()
    EnsurePostPopup()
    if postPopup:IsShown() then
        HidePostMenus(); ClearPostDescriptionFocus(); postPopup:Hide(); return
    end
    SetPostRefusal(nil)                                 -- reopening the form is a new start
    local candidates=BuildWishlistCandidates(); local wl=candidates[1]
    -- Auto-detect class from echo catalog, then fall back to player's own class
    local selectedClass = ControllerInstance().InferBuildClass(
        ControllerInstance().WishlistEchoes(wl) or {}) or ""
    if selectedClass == "" and UnitClass then
        local _, classToken = UnitClass("player")
        selectedClass = (classToken and classToken ~= "UNKNOWN") and tostring(classToken) or ""
    end
    -- A Share whose local save failed gives its approved draft back unchanged.
    local failedTitle, failedDescription, failedSource, failedClass
    if type(ControllerInstance().FailedShareDraft) == "function" then
        failedTitle, failedDescription, failedSource, failedClass =
            ControllerInstance().FailedShareDraft()
    end
    if failedTitle then
        wl, selectedClass = failedSource or wl, failedClass or selectedClass
    end
    ControllerInstance().BeginPostDraft(wl, selectedClass)
    postTitleBox:_NexusSetRawText(failedTitle
        or ((wl and wl.name and wl.name~="") and wl.name or ""))
    postDescBox:_NexusSetRawText(failedDescription or "")
    postDescBox:SetCursorPosition(0)
    postPopup._postDescScroll:SetVerticalScroll(0)
    local displayWishlistName = wl and DisplayRemoteText(
        wl.name, 1024, false) or nil
    postWishlistBtn:SetText("Source: " .. (displayWishlistName
        or "Select a saved build or wishlist"))
    if selectedClass ~= "" then
        local cc = CLASS_COLOR[selectedClass:upper()] or {1,1,1}
        postClassBtn:SetText("Class: "..(CLASS_LABEL[selectedClass:upper()] or selectedClass))
        pcall(function() postClassBtn:GetFontString():SetTextColor(cc[1],cc[2],cc[3]) end)
    else
        postClassBtn:SetText("Class: Select a class")
    end
    postPopup:ClearAllPoints(); postPopup:SetPoint("CENTER"); postPopup:Show(); RefreshPostPopupPreview()
end

function M.TogglePostPopup(anchor) M.ShowPostBuild() end

------------------------------------------------------------------------
-- Edit popup
------------------------------------------------------------------------

local editEchoBtn, editLockText

local function EnsureEditPopup()
    if editPopup then return editPopup end
    local p = CreateFrame("Frame","NexusEditPopup",UIParent)
    p:SetSize(360,282); p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:EnableMouse(true); p:Hide()
    p._dragHandle = InstallPopupDragHandle(p)

    local title = p:CreateFontString(nil,"OVERLAY","GameFontNormal")
    title:SetPoint("TOP",0,-12); title:SetText("Edit Build")

    local close = CreateFrame("Button",nil,p,"UIPanelCloseButton")
    close:SetPoint("TOPRIGHT",-2,-2); close:SetScript("OnClick",function()
        ClearEditDescriptionFocus()
        p:Hide()
        ControllerInstance().ClearEditDraft()
    end)

    local tl = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    tl:SetPoint("TOPLEFT",16,-36); tl:SetText("Title:")
    editTitleBox = CreateFrame("EditBox",nil,p,"InputBoxTemplate")
    editTitleBox:SetSize(310,20); editTitleBox:SetPoint("TOPLEFT",20,-52); editTitleBox:SetAutoFocus(false)
    ConfigureSafeEditableText(editTitleBox, 80, false)
    p._editTitleBox = editTitleBox

    local dl = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    dl:SetPoint("TOPLEFT",16,-80); dl:SetText("Description:")
    local descBg = CreateFrame("Frame",nil,p)
    descBg:SetPoint("TOPLEFT",18,-96); descBg:SetSize(324,86)
    pcall(function()
        descBg:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true,tileSize=16,edgeSize=12, insets={left=3,right=3,top=3,bottom=3} })
        descBg:SetBackdropColor(0,0,0,0.5)
    end)
    local descScroll = CreateFrame("ScrollFrame","NexusEditDescriptionScroll",descBg,
        "UIPanelScrollFrameTemplate")
    descScroll:SetPoint("TOPLEFT",6,-6)
    descScroll:SetPoint("BOTTOMRIGHT",-24,6)
    editDescBox = CreateFrame("EditBox",nil,descScroll)
    ConfigureDescriptionEdit(editDescBox, descScroll, 278, 74)
    ConfigureSafeEditableText(editDescBox, 2000, true)
    p._editDescScroll = descScroll
    p._editDescBox = editDescBox

    editLockText = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    editLockText:SetPoint("TOPLEFT",18,-190)
    -- Up to three lines of a 16 px face, above the action row.
    editLockText:SetSize(324,52)
    editLockText:SetJustifyH("LEFT")
    editLockText:SetJustifyV("TOP")
    p._editLockText = editLockText

    editEchoBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    -- The two actions stay 10 px apart (they used to overlap by 4 px).
    editEchoBtn:SetSize(202,22)
    editEchoBtn:SetPoint("BOTTOMLEFT",18,16)
    editEchoBtn:SetText("Use Active Wishlist Echoes")
    p._editEchoBtn = editEchoBtn
    editEchoBtn:SetScript("OnClick",function()
        local draft = ControllerInstance().EditDraft()
        if not draft then return end
        local ok, result = ControllerInstance().UpdateFromWishlist(draft.id)
        if ok then
            print(string.format("|cff4dff80Nexus:|r Echo list replaced with the active wishlist (%d Echoes).", result))
            ControllerInstance().ClearEditDraft()
            ClearEditDescriptionFocus(); p:Hide(); M.Refresh()
        else
            print("|cffff6060Nexus:|r " .. tostring(result))
        end
    end)

    local saveBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    saveBtn:SetSize(112,22); saveBtn:SetPoint("BOTTOMRIGHT",-18,16); saveBtn:SetText("Save Details")
    p._saveBtn = saveBtn
    saveBtn:SetScript("OnClick",function()
        local description = editDescBox:_NexusRawText()
        -- A stored description the box could not seed is unchanged while the
        -- box stays empty: no description is submitted and the stored one is
        -- kept. Text the owner types replaces it under the usual rules.
        if p._nexusDescriptionUnseeded and description == "" then
            description = nil
        end
        if not ControllerInstance().UpdateEditDraft(
            editTitleBox:_NexusRawText(), description) then return end
        local ok, err, outcome = ControllerInstance().CommitEditDraft()
        if ok then print("|cff4dff80Nexus:|r " .. tostring(outcome and outcome.message or "Build details saved locally.")); ClearEditDescriptionFocus(); p:Hide(); M.Refresh()
        else print("|cffff6060Nexus:|r "..tostring(err)) end
    end)
    pcall(function()
        p:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
            tile=true,tileSize=32,edgeSize=32, insets={left=11,right=12,top=12,bottom=11} })
    end)
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.ApplyFontTree then
        Nexus.LayoutMetrics.ApplyFontTree(p,"normal")
    end
    editPopup = p; return p
end

function M.ToggleEditPopup(id)
    EnsureEditPopup()
    if editPopup:IsShown() then
        ClearEditDescriptionFocus()
        editPopup:Hide()
        ControllerInstance().ClearEditDraft()
        return
    end
    local prepared = ControllerInstance().PrepareEditDraft(id)
    if not prepared then return end
    -- Retain the established frame projection for compatibility; the
    -- controller draft remains the sole authoritative edit-session state.
    editPopup._editingId = id
    if prepared.locked then
        editEchoBtn:Disable()
        editLockText:SetText("|cffffd200Echo list is read-only: a DPS record is attached.|r Share a new build to use different Echoes.")
    else
        editEchoBtn:Enable()
        editLockText:SetText("Change title/description, or replace the Echo list with your current active wishlist.")
    end
    editTitleBox:_NexusSetRawText(prepared.title)
    editTitleBox:HighlightText(0, 0)
    -- The box holds 2000 bytes; a longer stored description is not seeded.
    editPopup._nexusDescriptionUnseeded = editDescBox:_NexusSetRawText(
        prepared.description) == nil and prepared.description ~= "" or nil
    editDescBox:SetCursorPosition(#editDescBox:GetText())
    editPopup._editDescScroll:SetVerticalScroll(0)
    editPopup:ClearAllPoints(); editPopup:SetPoint("CENTER")
    editPopup:Show()
    if editPopup._nexusDescriptionUnseeded then
        print("|cffffd200Nexus:|r The stored description is not shown here: the Edit dialog holds 2000 bytes. Save Details keeps it unless you type a new description.")
    end
end

local function EnsureDetailPanel(parent)
    if detailPanel then return detailPanel end
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(500, 570)
    p:SetPoint("TOPLEFT", parent, "TOPLEFT", 520, -60)
    p:SetFrameLevel(parent:GetFrameLevel() + 2)
    p:Hide()

    pcall(function()
        p:SetBackdrop({
            bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true, tileSize=16, edgeSize=12,
            insets={left=3,right=3,top=3,bottom=3},
        })
        p:SetBackdropColor(0,0,0,0.9)
    end)

    p.classIcon = p:CreateTexture(nil,"ARTWORK")
    p.classIcon:SetSize(34,34)
    p.classIcon:SetPoint("TOPLEFT",10,-10)
    p.classIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    p.title = p:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT",p.classIcon,"TOPRIGHT",8,-1)
    p.title:SetSize(390,20)
    p.title:SetJustifyH("LEFT")

    p.closeBtn = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    p.closeBtn:SetPoint("TOPRIGHT", -2, -2)
    p.closeBtn:SetScript("OnClick", function()
        ControllerInstance().ClearSelection()
        M.Refresh()
    end)

    p.author = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    p.author:SetPoint("TOPLEFT",p.title,"BOTTOMLEFT",0,-2)
    p.author:SetSize(350,12)
    p.author:SetJustifyH("LEFT")

    -- The title and byline keep one line each; a shortened one is read in
    -- full from this tooltip.
    p.headerHit = CreateFrame("Frame", nil, p)
    p.headerHit:SetPoint("TOPLEFT", p.title, "TOPLEFT")
    p.headerHit:SetPoint("BOTTOMRIGHT", p.author, "BOTTOMRIGHT")
    p.headerHit:EnableMouse(true)
    p.headerHit:SetScript("OnEnter", function(self)
        local title, author = p.title:GetText(), p.author:GetText()
        local metrics = Nexus.LayoutMetrics
        if not (metrics and (metrics.Shortened(p.title)
            or metrics.Shortened(p.author))) then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine(tostring(title or ""), 1, 0.82, 0, true)
        GameTooltip:AddLine(tostring(author or ""), 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    p.headerHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Everything between the header and the action row scrolls in a
    -- measured body (LayoutDetailPanel), so a short responsive panel keeps
    -- the records and the Details! note inside it.
    local bodyScroll = CreateFrame("ScrollFrame", "NexusCommunityDetailScroll", p,
        "UIPanelScrollFrameTemplate")
    bodyScroll.scrollBarHideable = 1
    local body = CreateFrame("Frame", nil, bodyScroll)
    body:SetSize(440, 1)
    bodyScroll:SetScrollChild(body)
    p.bodyScroll, p.body = bodyScroll, body

    p.desc = body:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.desc:SetSize(350,50)
    p.desc:SetJustifyH("LEFT")
    p.desc:SetJustifyV("TOP")

    -- "Build Link" — a copyable URL field. The admin (or original author)
    -- can paste a URL (EbonBuilds page, video, sim link, etc.) and viewers
    -- get a box they can copy out in one click. Field is hidden when empty.
    local linkLabel = body:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    linkLabel:SetText("|cff888888DISCORD BUILD LINK|r")
    p.linkLabel = linkLabel

    local linkBox = CreateFrame("EditBox",nil,body,"InputBoxTemplate")
    linkBox:SetSize(382,18)
    linkBox:SetAutoFocus(false)
    ConfigureSafeEditableText(linkBox, 2048, true)
    linkBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    linkBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if p.linkSaveBtn and p.linkSaveBtn:IsShown() then p.linkSaveBtn:Click() end
    end)
    -- Make the link reliably copyable on 3.3.5: click focuses and selects all.
    linkBox:SetScript("OnMouseUp", function(self)
        self:SetFocus()
        pcall(function() self:HighlightText() end)
    end)
    linkBox:SetScript("OnEditFocusGained", function(self)
        pcall(function() self:HighlightText() end)
    end)
    p.linkBox = linkBox

    -- Owner-only Save button for the link
    local linkSaveBtn = CreateFrame("Button",nil,body,"UIPanelButtonTemplate")
    linkSaveBtn:SetSize(72,18)
    linkSaveBtn:SetPoint("LEFT",linkBox,"RIGHT",8,0)
    linkSaveBtn:SetText("Save Link")
    linkSaveBtn:SetScript("OnClick", function()
        local link = linkBox:_NexusRawText():gsub("^%s+",""):gsub("%s+$","")
        local selected = SelectedId()
        if linkBox._nexusBoundBuildId ~= selected then return end
        local build = selected and LoadBuild(selected)
        if not build or not IsOwnBuild(build) then return end
        local ok, err, outcome = EditBuild(
            selected, build.title, build.description, link)
        if ok then
            print("|cff4dff80Nexus:|r " .. tostring(outcome and outcome.message or "Build details saved locally."))
            M.Refresh()
        else
            print("|cffff6060Nexus:|r " .. tostring(err))
        end
    end)
    linkSaveBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Save this link to the build",0.9,0.9,0.9,true)
        GameTooltip:AddLine("Viewers can click the field and press Ctrl+C to copy it.",0.7,0.7,0.7,true)
        GameTooltip:Show()
    end)
    linkSaveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.linkSaveBtn = linkSaveBtn

    p.echoLabel = body:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    p.echoLabel:SetText("Echoes:")

    -- Locked echo row (permanent baseline): six icons; the label counts any
    -- further locked rows
    p.lockedLabel = body:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    p.lockedLabel:SetText("LOCKED ECHOES")

    p.lockedIcons = {}
    for i = 1, 6 do
        local ic = body:CreateTexture(nil,"ARTWORK")
        ic:SetSize(ECHO_ICON_SIZE+4, ECHO_ICON_SIZE+4)
        ic:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        ic:Hide()
        p.lockedIcons[i] = ic
    end

    -- echo icon grid: up to 80 icons, as many columns as the body width holds
    p.echoIcons = {}
    for i = 1, 80 do
        local ic = body:CreateTexture(nil,"ARTWORK")
        ic:SetSize(ECHO_ICON_SIZE, ECHO_ICON_SIZE)
        ic:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        ic:Hide()
        p.echoIcons[i] = ic
    end

    p.missingText = body:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.missingText:SetSize(470,14)
    p.missingText:SetJustifyH("LEFT")
    p.missingText:SetJustifyV("TOP")

    -- Compact record summary. Full rankings live in the dedicated Leaderboard.
    p.recordsTitle = body:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    p.recordsTitle:SetJustifyH("LEFT")
    p.recordsTitle:SetText("BEST RECORDS FOR THIS LOADOUT")

    p.dummyRecord = body:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.dummyRecord:SetSize(470,16)
    p.dummyRecord:SetJustifyH("LEFT")
    p.dummyRecord:SetJustifyV("TOP")

    p.lkRecord = body:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.lkRecord:SetSize(470,16)
    p.lkRecord:SetJustifyH("LEFT")
    p.lkRecord:SetJustifyV("TOP")

    -- Legacy row widgets are retained but hidden for saved UI compatibility.
    -- DPS section: Training Dummy
    local dummyHeader = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    dummyHeader:SetPoint("TOPLEFT",10,-302)
    dummyHeader:SetText("|cffffd200Training Dummy - Best DPS|r")

    p.lbDummyRows = {}
    for i = 1, 5 do
        local row = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        row:SetPoint("TOPLEFT",10,-318-(i-1)*16)
        row:SetSize(440,14); row:SetJustifyH("LEFT"); row:Hide()
        p.lbDummyRows[i] = row
    end
    p.lbDummyEmpty = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    p.lbDummyEmpty:SetPoint("TOPLEFT",10,-318)
    p.lbDummyEmpty:SetSize(440,14)
    p.lbDummyEmpty:SetText("|cff666666No recorded DPS yet -- hit a training dummy|r")

    p.lbDummyPersonal = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.lbDummyPersonal:SetPoint("TOPLEFT",10,-402)
    p.lbDummyPersonal:SetSize(440,14); p.lbDummyPersonal:SetJustifyH("LEFT")
    p.lbDummyPersonal:Hide()

    -- DPS section: Lich King
    local lkHeader = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    lkHeader:SetPoint("TOPLEFT",10,-422)
    lkHeader:SetText("|cffffd200Lich King - Best DPS|r")

    p.lbLKRows = {}
    for i = 1, 5 do
        local row = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        row:SetPoint("TOPLEFT",10,-438-(i-1)*16)
        row:SetSize(440,14); row:SetJustifyH("LEFT"); row:Hide()
        p.lbLKRows[i] = row
    end
    p.lbLKEmpty = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    p.lbLKEmpty:SetPoint("TOPLEFT",10,-438)
    p.lbLKEmpty:SetSize(440,14)
    p.lbLKEmpty:SetText("|cff666666No Lich King results yet|r")

    p.lbLKPersonal = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.lbLKPersonal:SetPoint("TOPLEFT",10,-522)
    p.lbLKPersonal:SetSize(440,14); p.lbLKPersonal:SetJustifyH("LEFT")
    p.lbLKPersonal:Hide()

    dummyHeader:Hide()
    lkHeader:Hide()
    p.lbDummyEmpty:Hide()
    p.lbDummyPersonal:Hide()
    p.lbLKEmpty:Hide()
    p.lbLKPersonal:Hide()
    for _, row in ipairs(p.lbDummyRows) do row:Hide() end
    for _, row in ipairs(p.lbLKRows) do row:Hide() end

    -- Details! availability note (shown once at bottom if not installed)
    p.detailsNote = body:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    p.detailsNote:SetSize(470,12)
    p.detailsNote:SetJustifyH("LEFT")
    p.detailsNote:SetJustifyV("TOP")
    p.detailsNote:SetText("|cff666666Install Details! damage meter to enable DPS tracking.|r")

    p.editState = body:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    p.editState:SetSize(470,26)
    p.editState:SetJustifyH("LEFT")
    p.editState:SetJustifyV("TOP")
    p.editState:Hide()

    -- buttons row
    -- Single consolidated action for the common case: opens the build as a
    -- draft in the Wishlist Editor (name pre-filled from the build's title)
    -- instead of applying immediately -- WishlistEditor.OpenForCandidate ->
    -- LoadPendingEchoes already knows how to split a build's Echoes into
    -- normal picks vs. designed locked slots (using each echo's `locked`
    -- flag). b.echoes' own flags aren't always reliable ground truth though
    -- (see the OnClick handler below), so this resolves against the DPS
    -- record's own lockedEchoes first, same as the display just above it --
    -- carrying locked-Echo intent over whether the source was another
    -- player's build or your own. It only ever makes a draft: a mirror of
    -- your OWN server Saved Build hides it and offers Share as a separate,
    -- confirmed action instead (p.shareBtn below).
    p.lockBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    p.lockBtn:SetSize(130,22)
    p.lockBtn:SetPoint("BOTTOMLEFT",8,8)
    p.lockBtn:SetText("Copy into Editor")
    p.lockBtn:SetScript("OnClick", function()
        local selected = SelectedId()
        local projection = EnsureCommunityProjection()
        local detail = selected and projection
            and projection.Detail(selected, ProjectionContext()) or nil
        local b = detail and detail.build or nil
        if not b then
            print("|cffff6060Nexus:|r Copy unavailable: the full rolled Echo list is still arriving.")
            return
        end
        -- Copy never shares. A mirror's Share is p.shareBtn and its confirmation.
        if IsSavedMirror(b) then return end
        if type(b.echoes) ~= "table" or #b.echoes == 0 then
            ControllerInstance().RequestLoadout(selected)
            print("|cff7fd5ffNexus:|r this build is still completing its background sync. Try again shortly.")
            return
        end
        if Nexus.WishlistEditor and Nexus.WishlistEditor.OpenForCandidate then
            local candidate, candidateReason = BuildCandidateEvidence(b)
            if not candidate then
                print("|cffff6060Nexus:|r Copy unavailable: "
                    .. tostring(candidateReason) .. ".")
                return
            end
            local validated, validationReason =
                CandidateEvidence.Validate(candidate)
            if not validated then
                print("|cffff6060Nexus:|r Copy unavailable: "
                    .. tostring(validationReason) .. ".")
                return
            end
            local opened = Nexus.WishlistEditor.OpenForCandidate(validated)
            if opened ~= false then parent:Hide() end
        end
    end)
    p.lockBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Review before applying",0.9,0.9,0.9,true)
        GameTooltip:AddLine("Opens this build as a draft in the Wishlist Editor, name pre-filled. Any",0.7,0.7,0.7,true)
        GameTooltip:AddLine("Echoes it had locked show up as designed locked slots you can adjust.",0.7,0.7,0.7,true)
        GameTooltip:AddLine("A draft only: it does not activate, spend or share anything.",0.7,0.7,0.7,true)
        GameTooltip:Show()
    end)
    p.lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    p.editBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    p.editBtn:SetSize(96,22)
    p.editBtn:SetPoint("LEFT",p.lockBtn,"RIGHT",6,0)
    p.editBtn:SetText("Edit Build")
    p.editBtn:SetScript("OnClick", function()
        local selected = SelectedId()
        if selected then M.ToggleEditPopup(selected) end
    end)

    p.retryShareBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    p.retryShareBtn:SetSize(130,22)
    p.retryShareBtn:SetPoint("BOTTOMLEFT",8,8)
    p.retryShareBtn:SetText("Retry Share")
    p.retryShareBtn:Hide()
    p.retryShareBtn:SetScript("OnClick", function(self)
        if self._nexusRetryConsumed then return end
        local selected = SelectedId()
        if not selected then return end
        self._nexusRetryConsumed = true
        self:Disable()
        local controller = ControllerInstance()
        local ok, why, outcome
        if type(controller.RetryShare) == "function" then
            ok, why, outcome = controller.RetryShare(selected)
        else
            ok, why = false, "not retryable"
        end
        outcome = type(outcome) == "table" and outcome or {}
        if ok and outcome.retryPending then
            print("|cffffc040Nexus:|r Share retry is waiting for one bounded Sync queue slot.")
        elseif ok then
            print("|cff4dff80Nexus:|r Share retry queued. Peer storage confirmation is unavailable.")
        else
            print("|cffff6060Nexus:|r Share retry failed: "
                .. tostring(why or "not retryable") .. ".")
            self._nexusRetryConsumed = false
            M.Refresh()
        end
    end)
    p.retryShareBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Retry this failed Share",0.9,0.9,0.9,true)
        GameTooltip:AddLine("Resends the exact saved build only after you click; no automatic terminal retry occurs.",0.7,0.7,0.7,true)
        GameTooltip:Show()
    end)
    p.retryShareBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    p.deleteBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    p.deleteBtn:SetSize(104,22)
    p.deleteBtn:SetPoint("BOTTOMRIGHT",-8,8)
    p.deleteBtn:SetText("Delete")
    p.deleteBtn:SetScript("OnClick", function()
        local selected = SelectedId()
        local build = selected and LoadBuild(selected)
        if build and IsOwnBuild(build) then
            local displayTitle = build.displayTitle or DisplayRemoteText(
                build.title or "this build", 1024, false) or "this build"
            StaticPopup_Show("NEXUS_STOP_SHARING_BUILD",
                displayTitle, nil, {id=selected})
        elseif selected then
            local ok, err = DeleteBuild(selected)
            if not ok then print("|cffff6060Nexus:|r " .. tostring(err)) end
            M.Refresh()
        end
    end)

    -- Share of your own Saved Build: a separate action at the right of the
    -- action row, never the draft-only Copy button, and only after a
    -- confirmation that says a shared build cannot be recalled. The
    -- confirmation approves one exact build: the owner and the content that
    -- PublishImportedBuild sends (title, description, Echoes and locked
    -- Echoes, publication). Accept re-reads it and shares nothing when any of
    -- that changed, or when the Library was closed; Cancel and Escape do
    -- nothing. One approval starts at most one Share; it is not a guarantee
    -- that the Share is sent exactly once, and it does not stop Sync.
    local function ShareIdentity(build)
        if not (IsSavedMirror(build) and IsOwnBuild(build)) then return nil end
        local parts = {CandidatePart(build.id), CandidatePart(build.ownerKey),
            CandidatePart(build.title),
            CandidatePart(build.userDescription or build.description),
            CandidatePart(build.publishedBuildId)}
        for _, list in ipairs({build.echoes, build.lockedEchoes}) do
            parts[#parts + 1] = "#"
            for _, e in ipairs(type(list) == "table" and list or {}) do
                parts[#parts + 1] = CandidatePart(e.spellId or e.id)
                    .. CandidatePart(e.quality)
                    .. CandidatePart(e.stacks or e.count or 1)
                    .. CandidatePart(e.locked == true)
            end
        end
        return table.concat(parts, "|")
    end

    local function ConfirmedShare(data)
        if type(data) ~= "table" or data.id == nil or data.used then return end
        data.used = true
        local id = data.id
        if pendingUploads[id] then return end
        local displayTitle = tostring(data.title or "Saved Build")
        if not parent:IsShown() or ShareIdentity(LoadBuild(id)) ~= data.identity then
            print("|cffffc040Nexus:|r Share cancelled: '" .. displayTitle
                .. "' changed, or the Build Library was closed, after the confirmation opened. Nothing was shared.")
            M.Refresh()
            return
        end
        local operation = {id=id,done=false}
        -- `admission` is the controller's actual queue result for the saved
        -- listing: queued (not sent), or the final refusal and its reason.
        local function Finish(ok, value, ticket, admission)
            if operation.done then return end
            if ticket and (pendingUploads[id] ~= operation
                or operation.ticket ~= ticket) then return end
            operation.done = true
            if pendingUploads[id] == operation then pendingUploads[id] = nil end
            if ok then
                local saved = "Saved '" .. displayTitle .. "' locally as your shared listing"
                local policy = Nexus.SyncModePolicy
                local reason = type(admission) == "table" and admission.queueReason or nil
                if type(admission) ~= "table" then
                    -- A completion that reports no queue result claims none.
                    print("|cff4dff80Nexus:|r " .. saved
                        .. ". Whether Sync queued it was not reported. Sending and receipt by other players are not confirmed.")
                elseif admission.queueAdmitted == true then
                    print("|cff4dff80Nexus:|r " .. saved
                        .. " and queued its summary. Queued is not sent: sending and receipt by other players are not confirmed.")
                elseif policy and type(policy.Text) == "function"
                    and reason ~= nil and reason == policy.Text("off") then
                    print("|cffffc040Nexus:|r " .. saved
                        .. " — not sent: your saved Sync mode is Off.")
                else
                    print("|cffffc040Nexus:|r " .. saved
                        .. " — not queued, so nothing was sent: "
                        .. tostring(reason or "Sync unavailable"):gsub("%.+$", "") .. ".")
                end
            else
                print("|cffff6060Nexus:|r Not shared: '" .. displayTitle
                    .. "' — " .. tostring(value):gsub("%.+$", "")
                    .. ". Nothing was saved or sent.")
            end
            M.Refresh()
        end
        local ok, value, ticket, admission = PublishImportedBuild(id, Finish)
        if ok == nil and value == "ROOT_MUTATION_PENDING" and type(ticket) == "table" then
            operation.ticket = ticket
            pendingUploads[id] = operation
            if SelectedId() == id then
                p.shareBtn:SetText("Sharing...")
                p.shareBtn:Disable()
            end
            print("|cff7fd5ffNexus:|r Preparing '" .. displayTitle
                .. "' to share — not sent yet. The local catalog is finishing earlier work first.")
        else
            Finish(ok == true, value, nil, admission)
        end
    end

    StaticPopupDialogs["NEXUS_SHARE_SAVED_BUILD"] = {
        text = "Share '%s' with other Nexus users?\n%s",
        button1 = "Share", button2 = "Cancel",
        OnShow = function(self)
            -- Above the DIALOG Library, as Stop Sharing; the shared slot's
            -- own layer returns on hide.
            if self._nexusShareStrata == nil then
                self._nexusShareStrata = self:GetFrameStrata()
            end
            self:SetFrameStrata("FULLSCREEN_DIALOG")
        end,
        OnHide = function(self)
            local strata = self._nexusShareStrata
            if strata then
                self._nexusShareStrata = nil
                self:SetFrameStrata(strata)
            end
        end,
        OnAccept = function(_, data) ConfirmedShare(data) end,
        timeout=0, whileDead=true, hideOnEscape=true, preferredIndex=3,
    }
    parent:HookScript("OnHide", function()
        if type(StaticPopup_Visible) == "function"
            and StaticPopup_Visible("NEXUS_SHARE_SAVED_BUILD") then
            StaticPopup_Hide("NEXUS_SHARE_SAVED_BUILD")
        end
    end)

    p.shareBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    p.shareBtn:SetSize(130,22)
    p.shareBtn:SetPoint("BOTTOMRIGHT",-8,8)
    p.shareBtn:SetText("Share Build...")
    p.shareBtn:Hide()
    p.shareBtn:SetScript("OnClick", function()
        local selected = SelectedId()
        if selected == nil or pendingUploads[selected] then return end
        local build = LoadBuild(selected)
        local identity = ShareIdentity(build)
        if not identity then
            print("|cffff6060Nexus:|r Share unavailable: this is not your own Saved Build. Nothing was shared.")
            M.Refresh()
            return
        end
        local displayTitle = build.displayTitle or DisplayRemoteText(
            build.title or "Saved Build", 1024, false) or "Saved Build"
        local policy = Nexus.SyncModePolicy
        local off = policy and type(policy.Mode) == "function"
            and policy.Mode() == "off"
        -- What Share does, in order: the local save, then a summary queued
        -- only if the saved mode and its size admit it. The summary carries
        -- no Echo list or description; the full listing can be sent in
        -- answers, by addon whisper when one was negotiated, otherwise on the
        -- shared Sync channel, where other Nexus users may keep a valid copy.
        -- After the local commit the controller also hands the listing ID to
        -- DpsCapture.BroadcastBestForBuild, whether or not the summary was
        -- queued: in Automatic a linked character-best record may be sent.
        -- The note states these paths; it changes none of them.
        local note = (build.publishedBuildId and "This saves its current title, description and Echo list as an update of your shared listing on this client, "
            or "This saves its title, description and Echo list as your shared listing on this client, ")
            .. "then queues a short summary for other Nexus users if your saved Sync mode and its size allow. The summary has no Echo list or description; the full listing can be sent in answers to other Nexus users' requests, and an answer on the shared Sync channel may be kept by any Nexus user who receives it. In Automatic, if your character's best Training Dummy or Lich King DPS is linked to this listing, Nexus may also send each such DPS record with its Echoes, any locked Echoes and your player info (character name, realm, class, level) without an additional request, even if the summary is not queued. "
            .. "A shared build cannot be recalled: players who receive it keep their copy, and Stop Sharing removes only the listing on this client. "
            .. "Nexus cannot confirm who received it."
            .. (off and " Your saved Sync mode is Off: the listing is saved on this client and not sent." or "")
        StaticPopup_Show("NEXUS_SHARE_SAVED_BUILD", displayTitle, note,
            {id=selected,identity=identity,title=displayTitle})
    end)
    p.shareBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Share this Saved Build",0.9,0.9,0.9,true)
        GameTooltip:AddLine("Asks you to confirm, then saves it as your shared listing and queues a summary (no Echo list) for other Nexus users if your Sync mode and its size allow. Its full Echo list can be sent in answers, and an answer on the shared Sync channel may be kept by any Nexus user who receives it. In Automatic, your character's best Training Dummy or Lich King DPS, if linked to it, may also be sent with its Echoes, any locked Echoes and player info, without an additional request. A shared build cannot be recalled.",0.7,0.7,0.7,true)
        GameTooltip:AddLine("Not Copy into Editor, and not saving or activating a server Saved Build.",0.7,0.7,0.7,true)
        GameTooltip:Show()
    end)
    p.shareBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    parent._detailPanel = p
    detailPanel = p
    return p
end

-- A selected build that cannot be shown gets an explicit state in place of
-- the detail, never a blank panel: still loading, or why it is unavailable.
local DETAIL_STATUS = {
    pending={"Loading build details...",
        "The build library is still being prepared. The selected build appears here when it is ready."},
    unavailable={"Build not available",
        "This build is not in your build library. It may have been removed, not received yet, or not accepted."},
    invalid={"Build not available",
        "The selected build record is invalid and cannot be shown."},
    incomplete={"Build not available yet",
        "The full Echo list for this build is still arriving."},
}

local function ShowDetailStatus(kind)
    local p = detailPanel
    if not p then return end
    local status = p._nexusStatus
    if not status then
        status = CreateFrame("Frame", nil, p:GetParent())
        status:SetAllPoints(p)
        status:SetFrameLevel(p:GetFrameLevel())
        pcall(function()
            status:SetBackdrop({
                bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
                tile=true, tileSize=16, edgeSize=12,
                insets={left=3,right=3,top=3,bottom=3},
            })
            status:SetBackdropColor(0.04,0.04,0.06,0.95)
        end)
        status.title = status:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        status.title:SetPoint("TOPLEFT", 16, -16)
        status.title:SetPoint("TOPRIGHT", -16, -16)
        status.title:SetJustifyH("LEFT")
        status.text = status:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        status.text:SetPoint("TOPLEFT", status.title, "BOTTOMLEFT", 0, -10)
        status.text:SetPoint("TOPRIGHT", status.title, "BOTTOMRIGHT", 0, -10)
        status.text:SetJustifyH("LEFT")
        p._nexusStatus = status
    end
    local text = DETAIL_STATUS[kind] or DETAIL_STATUS.unavailable
    status.kind = DETAIL_STATUS[kind] and kind or "unavailable"
    status.title:SetText(text[1])
    status.text:SetText(text[2])
    p._nexusShownId = nil
    p:Hide()
    status:Show()
end

local function HideDetailStatus()
    local status = detailPanel and detailPanel._nexusStatus
    if status then status.kind = nil; status:Hide() end
end

-- listPending: the build list is not published yet, so an unavailable
-- selected build is reported as loading (or keeps its shown detail).
local function RefreshDetailPanel(buildId, listPending)
    if not detailPanel then return end
    if buildId == nil then
        detailPanel._nexusShownId = nil
        detailPanel:Hide(); HideDetailStatus(); return
    end
    local projection = EnsureCommunityProjection()
    local detail, build
    if projection then
        local err, why
        detail, err, why = projection.Detail(buildId, ProjectionContext())
        if not detail then
            if err then error(err) end
            if listPending and detailPanel:IsShown()
                and detailPanel._nexusShownId == buildId then return end
            ShowDetailStatus(listPending and "pending" or why or "unavailable")
            return
        end
        build = detail.build
    else
        build = LoadBuild(buildId)
    end
    if not build then
        ShowDetailStatus(listPending and "pending" or "unavailable")
        return
    end
    HideDetailStatus()
    if detailPanel._nexusShownId ~= buildId and detailPanel.bodyScroll then
        detailPanel.bodyScroll:SetVerticalScroll(0)
    end
    detailPanel._nexusShownId = buildId

    local c = CLASS_COLOR[(build.class or ""):upper()] or {1,1,1}
    detailPanel.title:SetTextColor(c[1],c[2],c[3])
    detailPanel.title:SetText(build.displayTitle
        or DisplayRemoteText(build.title or "", 1024, true) or "Invalid title")
    if detailPanel.classIcon then
        detailPanel.classIcon:SetTexture(CLASS_ICON[(build.class or ""):upper()] or "Interface\\Icons\\INV_Misc_QuestionMark")
    end
    local displayAuthor = build.displayAuthor or DisplayRemoteText(
        build.author or "?", 1024, false) or "Unknown"
    detailPanel.author:SetText("by " .. displayAuthor)
    local displayDescription = build.displayDescription
        or DisplayRemoteText(build.description or "", 4000, true, true)
    displayDescription = (displayDescription ~= "" and displayDescription)
        or "|cff666666(no description)|r"
    -- The byline carries no provenance text; the detail says it.
    if build.publicIdentityVerified == false then
        displayDescription = OWNER_NOT_ESTABLISHED .. "\n" .. displayDescription
    end
    detailPanel.desc:SetText(displayDescription)

    -- Link field: always show the box so anyone can copy; only show Save
    -- button for the build's owner. Hide label/box entirely when there's no
    -- link and the viewer isn't the owner (avoids empty-box clutter).
    local hasLink, ownThis
    if detail then
        hasLink, ownThis = detail.hasLink, detail.canSaveLink
    else
        hasLink = type(build.link) == "string" and build.link ~= ""
        ownThis = IsOwnBuild(build) or IsAdmin()
    end
    if detailPanel.linkBox then
        if hasLink or ownThis then
            local linkBox = detailPanel.linkBox
            local stored = build.link or ""
            -- An unsaved owner edit of this same build's link survives a
            -- refresh: the field still holds neither the link it was last
            -- given nor the stored link. Another build, or a build this
            -- character may no longer edit, gets the stored link.
            local current = linkBox._nexusBoundBuildId == build.id
                and linkBox:_NexusRawText() or nil
            local draft = ownThis and current ~= nil
                and current ~= linkBox._nexusSeededLink and current ~= stored
            detailPanel.linkLabel:Show()
            linkBox:Show()
            linkBox._nexusBoundBuildId = build.id
            if not draft then
                linkBox._nexusSeededLink = linkBox:_NexusSetRawText(stored) or ""
            end
            if ownThis then
                detailPanel.linkSaveBtn:Show()
            else
                detailPanel.linkSaveBtn:Hide()
            end
        else
            detailPanel.linkBox._nexusBoundBuildId = nil
            detailPanel.linkLabel:Hide()
            detailPanel.linkBox:Hide()
            detailPanel.linkSaveBtn:Hide()
        end
    end

    -- Locked echoes come from the same category-aware resolver used by Copy.
    -- That owner already handles an inline build fallback when no DPS record
    -- exists; bypassing it here would hide a conflict or malformed claim.
    local lockedEchoes = detail and detail.lockedEchoes or nil
    if not detail then
        lockedEchoes = ControllerInstance().LockedEchoesForBuild(build)
    end
    if detailPanel.lockedIcons then
        if lockedEchoes and #lockedEchoes > 0 then
            -- A record can hold more locked rows (occupied records) than the
            -- six icons; the label counts the ones not drawn.
            local more = #lockedEchoes - #detailPanel.lockedIcons
            detailPanel.lockedLabel:SetText(more > 0
                and ("LOCKED ECHOES  +" .. more .. " more locked") or "LOCKED ECHOES")
            detailPanel.lockedLabel:Show()
            detailPanel.echoLabel:Hide()
            for i, ic in ipairs(detailPanel.lockedIcons) do
                local e = lockedEchoes[i]
                if e then ic:SetTexture(SpellIcon(e.spellId or e.id)); ic:Show()
                else ic:Hide() end
            end
        else
            detailPanel.lockedLabel:Hide()
            detailPanel.echoLabel:Show()
            for _, ic in ipairs(detailPanel.lockedIcons) do ic:Hide() end
        end
    end

    -- echo icons
    local echoes = detail and detail.echoes or build.echoes or {}
    local hasLoadout = detail and detail.hasLoadout or false
    if not detail then
        hasLoadout = type(build.echoes) == "table" and #build.echoes > 0
    end
    local missing = detail and detail.missing or 0
    local totalSlots = detail and detail.totalSlots or 0
    local bySpell = {}
    if not detail then
        bySpell = ProjectionContext().ownedBySpell or {}
    end
    if not hasLoadout then
        ControllerInstance().RequestLoadout(build.id)
    end
    for i, ic in ipairs(detailPanel.echoIcons) do
        local e = echoes[i]
        if e then
            ic:SetTexture(SpellIcon(e.spellId))
            local isMissing
            if detail then
                isMissing = e.missing
            else
                isMissing = (tonumber(bySpell[e.spellId]) or 0)
                    < (tonumber(e.stacks) or 1)
            end
            if isMissing then
                if not detail then missing=missing+1 end
                pcall(function() ic:SetVertexColor(0.4,0.4,0.4) end)
            else
                pcall(function() ic:SetVertexColor(1,1,1) end)
            end
            ic:Show()
        else ic:Hide() end
    end
    if hasLoadout then
        if not detail then
            for _, e in ipairs(echoes) do
                totalSlots = totalSlots
                    + (tonumber(e.stacks or e.count) or 1)
            end
        end
        detailPanel.missingText:SetText(string.format(
            "|cff888888%d echoes|r  --  |cffff9040%d missing|r", totalSlots, missing))
    else
        detailPanel.missingText:SetText("|cffffd200Receiving the full Echo list...|r")
    end

    local mine, admin, loadoutLocked
    if detail then
        mine, admin, loadoutLocked = detail.mine,
            detail.admin, detail.loadoutLocked
    else
        mine, admin, loadoutLocked = IsOwnBuild(build),
            IsAdmin(), HasLeaderboardRecord(build)
    end
    if mine then
        detailPanel.editBtn:Show()
        if IsSavedMirror(build) then
            detailPanel.deleteBtn:Hide()
        else
            detailPanel.deleteBtn:Show()
            detailPanel.deleteBtn:SetText("Stop Sharing")
        end
    elseif admin then
        detailPanel.editBtn:Hide()
        detailPanel.deleteBtn:Show()
        detailPanel.deleteBtn:SetText("Remove Shared Record")
    else
        detailPanel.editBtn:Hide()
        detailPanel.deleteBtn:Hide()
    end

    if detail then
        if detail.editState then
            detailPanel.editState:SetText(detail.editState)
            detailPanel.editState:Show()
        else
            detailPanel.editState:Hide()
        end
    elseif IsSavedMirror(build) then
        local state = PublishedBuildId(build)
            and "Shared listing saved on this client. Update Shared Build... sends the current title, description and Echo list after you confirm; receipt by other players is not confirmed."
            or "Your server Saved Build. Edit its title/description, then use Share Build... to send it to other Nexus users after you confirm."
        detailPanel.editState:SetText(state)
        detailPanel.editState:Show()
    elseif mine and loadoutLocked then
        detailPanel.editState:SetText("|cffffd200Echo list is read-only: a DPS record is attached.|r Title/description remain editable. Share a new build to use different Echoes.")
        detailPanel.editState:Show()
    elseif mine then
        detailPanel.editState:SetText("You own this build. Edit can also replace its Echoes from your active wishlist.")
        detailPanel.editState:Show()
    else
        detailPanel.editState:Hide()
    end

    local controller = ControllerInstance()
    local retryable, _, retryStatus = false, nil, nil
    if mine and type(controller.CanRetryShare) == "function" then
        retryable, _, retryStatus = controller.CanRetryShare(build.id)
    end
    if retryable then
        local generation = retryStatus and retryStatus.generation or 0
        if detailPanel.retryShareBtn._nexusRetryGeneration ~= generation then
            detailPanel.retryShareBtn._nexusRetryGeneration = generation
            detailPanel.retryShareBtn._nexusRetryConsumed = false
        end
        if detailPanel.retryShareBtn._nexusRetryConsumed then
            detailPanel.retryShareBtn:Disable()
        else
            detailPanel.retryShareBtn:Enable()
        end
        detailPanel.lockBtn:Hide()
        detailPanel.shareBtn:Hide()
        detailPanel.retryShareBtn:Show()
    else
        detailPanel.retryShareBtn:Hide()
        -- A mirror offers no draft Copy; your own mirror offers Share apart.
        if IsSavedMirror(build) then
            detailPanel.lockBtn:Hide()
            if mine then detailPanel.shareBtn:Show() else detailPanel.shareBtn:Hide() end
        else
            detailPanel.shareBtn:Hide()
            detailPanel.lockBtn:Show()
        end
        detailPanel.retryShareBtn._nexusRetryGeneration = nil
        detailPanel.retryShareBtn._nexusRetryConsumed = false
    end
    if IsSavedMirror(build) then
        local pending = pendingUploads[SelectedId()] ~= nil
        detailPanel.shareBtn:SetText(pending and "Sharing..."
            or detail and detail.shareText
            or (PublishedBuildId(build) and "Update Shared Build..." or "Share Build..."))
        if pending then detailPanel.shareBtn:Disable() else detailPanel.shareBtn:Enable() end
    elseif detail then
        detailPanel.lockBtn:SetText(detail.actionText)
    else
        detailPanel.lockBtn:SetText(not hasLoadout and "Request full Echo list" or "Copy into Editor")
    end

    -- DPS leaderboards
    local hasDetails = detail and detail.detailsAvailable or false
    if not detail then
        hasDetails = ProjectionContext().detailsAvailable
    end

    local function RecordText(label, rows, personal)
        local top = rows and rows[1]
        local best = top and DpsText(top.dps) or "—"
        local holder = top and (top.displayPlayer or DisplayRemoteText(
            tostring(top.player or "Unknown"), 1024, false) or "Unknown")
            or "No record yet"
        local yours = personal and DpsText(personal.dps) or "—"
        return string.format("|cffffffff%s|r  |cffffd200%s|r |cff888888%s|r   |cff66ff99Your best %s|r",
            label, best, holder, yours)
    end

    if detail then
        detailPanel.dummyRecord:SetText(detail.dummyRecord)
        detailPanel.lkRecord:SetText(detail.lkRecord)
    else
        local recordId = RecordBuildId(build)
        local dummyLb = ControllerInstance().Leaderboard(
            recordId, "dummy") or {}
        local dummyPB = ControllerInstance().PersonalBest(
            recordId, "dummy")
        local lkLb = ControllerInstance().Leaderboard(
            recordId, "lk") or {}
        local lkPB = ControllerInstance().PersonalBest(recordId, "lk")
        detailPanel.dummyRecord:SetText(RecordText("Training Dummy", dummyLb, dummyPB))
        detailPanel.lkRecord:SetText(RecordText("Lich King", lkLb, lkPB))
    end

    for _, row in ipairs(detailPanel.lbDummyRows) do row:Hide() end
    for _, row in ipairs(detailPanel.lbLKRows) do row:Hide() end
    detailPanel.lbDummyEmpty:Hide(); detailPanel.lbDummyPersonal:Hide()
    detailPanel.lbLKEmpty:Hide(); detailPanel.lbLKPersonal:Hide()

    -- Show/hide the "install Details!" note
    if detailPanel.detailsNote then
        if hasDetails then detailPanel.detailsNote:Hide()
        else detailPanel.detailsNote:Show() end
    end

    LayoutDetailPanel(detailPanel)
    detailPanel:Show()
end

------------------------------------------------------------------------
-- Card pool (reuse pre-built frames to avoid GC churn during scroll)
------------------------------------------------------------------------

local cardPool = {}   -- reusable card frames
local activeCards = {}  -- currently visible cards

local function GetCard(parent)
    if #cardPool > 0 then
        local c = table.remove(cardPool)
        c:SetParent(parent)
        c:Show()
        return c
    end

    local card = CreateFrame("Button", nil, parent)
    virtualStats.created = virtualStats.created + 1
    card:SetHeight(CARD_HEIGHT)
    card:EnableMouse(true)

    pcall(function()
        card:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 10,
            insets = { left=3, right=3, top=3, bottom=3 },
        })
        card:SetBackdropColor(0.035, 0.035, 0.045, 0.94)
        card:SetBackdropBorderColor(0.24, 0.24, 0.28, 0.9)
    end)

    card.selectedHighlight = card:CreateTexture(nil, "BACKGROUND")
    card.selectedHighlight:SetAllPoints(card)
    pcall(function() card.selectedHighlight:SetTexture(0.18, 0.38, 0.62, 0.22) end)
    card.selectedHighlight:Hide()

    card.classIcon = card:CreateTexture(nil, "ARTWORK")
    card.classIcon:SetSize(30, 30)
    card.classIcon:SetPoint("TOPLEFT", 10, -9)
    card.classIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.title:SetPoint("TOPLEFT", card.classIcon, "TOPRIGHT", 8, 0)
    card.title:SetSize(250, 16)
    card.title:SetJustifyH("LEFT")

    card.author = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.author:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -2)
    card.author:SetSize(245, 12)
    card.author:SetJustifyH("LEFT")

    card.destination = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.destination:SetPoint("TOPLEFT", card.author, "BOTTOMLEFT", 0, -2)
    card.destination:SetSize(310, 12)
    card.destination:SetJustifyH("LEFT")

    card.echoCount = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.echoCount:SetPoint("TOPRIGHT", -12, -9)
    card.echoCount:SetSize(178, 14)
    card.echoCount:SetJustifyH("RIGHT")

    card.dpsBreakdown = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.dpsBreakdown:SetPoint("TOPRIGHT", card.echoCount, "BOTTOMRIGHT", 0, -2)
    card.dpsBreakdown:SetSize(220, 12)
    card.dpsBreakdown:SetJustifyH("RIGHT")
    card.dpsBreakdown:SetText("")

    card.icons = {}
    for i = 1, MAX_ROW_ICONS do
        local ic = card:CreateTexture(nil, "ARTWORK")
        ic:SetSize(ICON_SIZE, ICON_SIZE)
        ic:SetPoint("BOTTOMLEFT", 10 + (i-1)*(ICON_SIZE+2), 9)
        ic:Hide()
        card.icons[i] = ic
    end

    card.moreText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.moreText:SetPoint("LEFT", card.icons[MAX_ROW_ICONS], "RIGHT", 6, 0)
    card.moreText:SetText("")

    card.mineBadge = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.mineBadge:SetPoint("BOTTOMRIGHT", -64, 13)
    card.mineBadge:SetSize(70, 12)
    card.mineBadge:SetJustifyH("RIGHT")
    card.mineBadge:Hide()

    card.addBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    card.addBtn:SetSize(52, 22)
    card.addBtn:SetPoint("BOTTOMRIGHT", -8, 7)
    card.addBtn:SetText("View")
    card.addBtn:SetScript("OnClick", function(self)
        local parent = self:GetParent()
        if parent.buildId then
            ControllerInstance().Select(parent.buildId)
            M.Refresh()
        end
    end)
    card.addBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Open build details", 1,1,1)
        GameTooltip:AddLine("Inspect records, exact Echoes, and copy the loadout.", 0.8,0.8,0.8, true)
        GameTooltip:Show()
    end)
    card.addBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    card:SetScript("OnEnter", function(self)
        if not self.buildId then return end
        pcall(function()
            self:SetBackdropColor(0.07, 0.08, 0.11, 0.98)
            self:SetBackdropBorderColor(0.45, 0.55, 0.7, 1)
        end)
        if self._fullTitle and self._displayTitle ~= self._fullTitle then
            GameTooltip:SetOwner(self,"ANCHOR_TOP")
            GameTooltip:AddLine(self._fullTitle,1,0.82,0,true)
            GameTooltip:AddLine(
                "Open build details for the complete title and records.",
                0.8,0.8,0.8,true)
            GameTooltip:Show()
        end
    end)
    card:SetScript("OnLeave", function(self)
        pcall(function()
            self:SetBackdropColor(0.035, 0.035, 0.045, 0.94)
            self:SetBackdropBorderColor(0.24, 0.24, 0.28, 0.9)
        end)
        GameTooltip:Hide()
    end)
    card:SetScript("OnClick", function(self)
        if not self.buildId then return end
        ControllerInstance().Select(self.buildId)
        M.Refresh()
    end)
    if Nexus.Theme and Nexus.Theme.StyleVirtualRow then
        Nexus.Theme.StyleVirtualRow(card, {card.addBtn})
    end
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.ApplyFontTree then
        Nexus.LayoutMetrics.ApplyFontTree(card,"normal")
    end
    return card
end

local function ReleaseCard(card)
    card:Hide()
    card:ClearAllPoints()
    card:SetParent(nil)
    cardPool[#cardPool+1] = card
end

local function ReleaseAllCards()
    for _, c in ipairs(activeCards) do ReleaseCard(c) end
    activeCards = {}
end

------------------------------------------------------------------------
-- Class header frames
------------------------------------------------------------------------

local headerPool = {}
local activeHeaders = {}

local function GetHeader(parent)
    if #headerPool > 0 then
        local h = table.remove(headerPool)
        h:SetParent(parent); h:Show(); return h
    end
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(22)
    h.label = h:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    h.label:SetPoint("BOTTOMLEFT",2,-2)
    h.sep = h:CreateTexture(nil,"ARTWORK")
    h.sep:SetHeight(1)
    h.sep:SetPoint("BOTTOMLEFT",h,"BOTTOMLEFT",0,0)
    h.sep:SetPoint("BOTTOMRIGHT",h,"BOTTOMRIGHT",0,0)
    pcall(function() h.sep:SetTexture(0.4,0.4,0.4,0.6) end)
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.ApplyFontTree then
        Nexus.LayoutMetrics.ApplyFontTree(h,"normal")
    end
    return h
end
local function ReleaseHeader(h)
    h:Hide(); h:ClearAllPoints(); h:SetParent(nil)
    headerPool[#headerPool+1] = h
end
local function ReleaseAllHeaders()
    for _, h in ipairs(activeHeaders) do ReleaseHeader(h) end
    activeHeaders = {}
end

------------------------------------------------------------------------
-- Main frame construction
------------------------------------------------------------------------

local function EnsureFrame()
    if frame then return frame end

    -- Main browser window: list and detail panel live together in one surface.
    frame = CreateFrame("Frame","NexusCommunityBuildsFrame",UIParent)
    frame:SetClampedToScreen(true)
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "NexusCommunityBuildsFrame")
    end
    frame:SetSize(1040,640)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(50)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart",function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local retryTicker, statusTicker, dataTicker = 0, 0, 0
    local lastReceiving = false
    frame:SetScript("OnUpdate",function(self,elapsed)
        if not self:IsShown() then return end
        local controller = ControllerInstance()
        local receivingNow = Nexus.Sync and Nexus.Sync.IsReceiving
            and Nexus.Sync.IsReceiving() or false
        retryTicker = retryTicker + elapsed
        if retryTicker >= 0.5 then
            retryTicker = 0
            PumpPendingLockIn()
        end

        -- Keep the live sync label responsive without rebuilding and sorting
        -- the entire build library every half second. The old full refresh was
        -- especially expensive with 100+ builds because it also resolved DPS
        -- records, recreated every card and recursively restyled the frame.
        local receiveEnded = false
        statusTicker = statusTicker + elapsed
        if statusTicker >= 0.25 then
            statusTicker = 0
            local receiveCount = Nexus.Sync and Nexus.Sync.LastSyncNewCount and Nexus.Sync.LastSyncNewCount() or 0
            if receivingNow and syncStatusText and Nexus.Sync
                and RenderSyncStatus then
                RenderSyncStatus(receiveCount)
            end

            -- Build/DPS revisions mark the view dirty while Sync is active.
            -- Publish once when that burst ends; changing the live count alone
            -- is status work and must not rebuild the catalog.
            receiveEnded = lastReceiving and not receivingNow
            lastReceiving = receivingNow
        end

        if type(controller.HasPendingSavedLoadoutImport) == "function"
            and controller.HasPendingSavedLoadoutImport() then
            local _, pending = PrepareData(false)
            if not pending then M.Refresh() end
        end
        if receiveEnded and refreshDirty then
            virtualStats.deferredRefreshes =
                virtualStats.deferredRefreshes + 1
            M.Refresh()
            return
        end
        local projections = Nexus and Nexus.ViewProjections
        local coldStart = virtualStats.dataBinds == 0
        if projections and (not receivingNow or coldStart)
            and type(projections.PumpBuilds) == "function" then
            -- A receive window may already be active when the browser first
            -- opens. Keep that cold persisted projection moving, but retain an
            -- existing last-good publication until the burst becomes quiet.
            if receivingNow and coldStart then M.Refresh() end
            local ok, published, pumpError = pcall(projections.PumpBuilds)
            if ok and published then M.Refresh() end
            if ok and pumpError then M.Refresh() end
        end

        -- Cheap safety probe for missed invalidations. An unchanged tick does
        -- not request/copy the cached projection or sort/rebind any rows.
        dataTicker = dataTicker + elapsed
        if dataTicker >= 8.0 then
            dataTicker = 0
            local projection = EnsureCommunityProjection()
            local current = nil
            if projection and type(projection.ListCurrent) == "function" then
                local ok, result = pcall(projection.ListCurrent,
                    FilterSettings())
                if ok then current = result end
            else
                local projections = Nexus and Nexus.ViewProjections
                if projections and type(projections.BuildsCurrent) == "function" then
                    local ok, result = pcall(projections.BuildsCurrent,
                        FilterSettings())
                    if ok then current = result end
                end
            end
            local receiving = Nexus.Sync and Nexus.Sync.IsReceiving
                and Nexus.Sync.IsReceiving() or false
            -- Preserve the result of work the safety probe already performed.
            -- This keeps diagnostics truthful during a receive window even if
            -- the normal revision notification was missed, without adding a
            -- second currentness read to DiagnosticSnapshot.
            if current ~= true then
                viewDiagnostic.projectionCurrent = false
            end
            -- A missing/failing dirty probe must retain the old safe behavior:
            -- attempt the refresh instead of treating an unknown state as
            -- current forever.
            if not receiving and (refreshDirty or current ~= true) then
                M.Refresh()
            else
                virtualStats.periodicSkips = virtualStats.periodicSkips + 1
            end
        end
    end)
    frame:Hide()
    frame:HookScript("OnHide",function()
        if dropPanel then dropPanel:Hide() end
        if sortPanel then sortPanel:Hide() end
        if dropdownShield then dropdownShield:Hide() end
    end)

    pcall(function()
        frame:SetBackdrop({
            bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
            tile=true, tileSize=32, edgeSize=32,
            insets={left=11,right=12,top=12,bottom=11},
        })
    end)
    pcall(function() frame:SetBackdropColor(0.16,0.165,0.175,0.90) end)

    -- Scrolled content ----------------------------------------------------
    -- Every laid-out widget is placed in this content (PlaceCommunityBox).
    -- It is as tall as the layout; the window is as tall as the visible UI
    -- allows (LayoutMetrics.Community windowHeight), and when the layout is
    -- taller the content scrolls: the mouse wheel over the window and the bar
    -- at its right edge move it (SetContentScroll). The bar is shown only
    -- while there is something to scroll.
    local contentScroll = CreateFrame("ScrollFrame",nil,frame)
    contentScroll:SetPoint("TOPLEFT",frame,"TOPLEFT",0,0)
    contentScroll:SetSize(1040,640)
    contentScroll:EnableMouseWheel(true)
    local content = CreateFrame("Frame",nil,contentScroll)
    content:SetSize(1040,640)
    contentScroll:SetScrollChild(content)
    frame._contentScroll, frame._content, frame._contentOffset = contentScroll, content, 0
    local contentBar = CreateFrame("Slider",nil,frame)
    contentBar:SetOrientation("VERTICAL")
    contentBar:SetWidth(16)
    contentBar:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-4,-40)
    contentBar:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-4,12)
    contentBar:SetMinMaxValues(0,0)
    contentBar:SetValueStep(1)
    contentBar:SetValue(0)
    contentBar:EnableMouseWheel(true)
    contentBar:SetFrameLevel(frame:GetFrameLevel() + 20)
    pcall(function()
        contentBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
        local thumb = contentBar:GetThumbTexture()
        if thumb then thumb:SetSize(16,24) end
        contentBar:SetBackdrop({
            bgFile="Interface\\Buttons\\UI-SliderBar-Background",
            edgeFile="Interface\\Buttons\\UI-SliderBar-Border",
            tile=true, tileSize=8, edgeSize=8,
            insets={left=3,right=3,top=6,bottom=6},
        })
    end)
    contentBar:Hide()
    frame._contentBar = contentBar
    contentBar:SetScript("OnValueChanged",function(_,value)
        SetContentScroll(value)
    end)
    local function WheelContent(_,delta)
        SetContentScroll((frame._contentOffset or 0)
            - (tonumber(delta) or 0) * ContentWheelStep())
    end
    contentScroll:SetScript("OnMouseWheel",WheelContent)
    contentBar:SetScript("OnMouseWheel",WheelContent)

    -- Title bar ---------------------------------------------------------
    local titleText = frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    titleText:SetPoint("TOP",0,-12)
    titleText:SetJustifyH("CENTER")
    frame._titleText = titleText
    titleText:SetText("Nexus  —  Build Library")

    local closeBtn = CreateFrame("Button",nil,frame,"UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT",-6,-6)
    -- It stays at the window's corner, above the scrolled content.
    closeBtn:SetFrameLevel(frame:GetFrameLevel() + 20)

    -- A single click-away layer and one-open-menu rule make every selector
    -- behave like the same control instead of three unrelated popup frames.
    dropdownShield = CreateFrame("Button","NexusBuildDropdownShield",UIParent)
    dropdownShield:SetAllPoints(UIParent)
    dropdownShield:SetFrameStrata("DIALOG")
    dropdownShield:SetFrameLevel(frame:GetFrameLevel() - 1)
    dropdownShield:EnableMouse(true)
    dropdownShield:Hide()

    local function CloseDropdowns()
        if dropPanel then dropPanel:Hide() end
        if sortPanel then sortPanel:Hide() end
        if dropdownShield then dropdownShield:Hide() end
    end
    dropdownShield:SetScript("OnClick", CloseDropdowns)

    local function OpenDropdown(panel, anchor)
        local wasShown = panel and panel:IsShown()
        CloseDropdowns()
        if wasShown or not panel then return end
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -3)
        panel:SetFrameStrata("TOOLTIP")
        panel:SetFrameLevel(dropdownShield:GetFrameLevel() + 2)
        dropdownShield:Show()
        panel:Show()
    end

    local function StyleDropdownPanel(panel)
        panel:EnableMouse(true)
        panel:Hide()
        pcall(function()
            panel:SetBackdrop({
                bgFile="Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
                tile=true, tileSize=16, edgeSize=12,
                insets={left=4,right=4,top=4,bottom=4},
            })
            panel:SetBackdropColor(0.02,0.02,0.025,0.99)
            panel:SetBackdropBorderColor(0.55,0.45,0.22,1)
        end)
    end

    local function AddDropdownRow(panel, entry, index, width, selectedFn, onSelect, color)
        local item = entry
        local row = CreateFrame("Button",nil,panel)
        row:SetSize(width - 10,24)
        row:SetPoint("TOPLEFT",5,-(5+(index-1)*24))
        row:EnableMouse(true)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        local check = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        check:SetPoint("LEFT",7,0)
        check:SetText(">")
        local label = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        label:SetPoint("LEFT",check,"RIGHT",7,0)
        label:SetPoint("RIGHT",row,"RIGHT",-8,0)
        label:SetJustifyH("LEFT")
        label:SetText(item.label)
        if color then label:SetTextColor(color[1],color[2],color[3]) end
        row._entry, row._check, row._label = item, check, label
        row:SetScript("OnClick",function()
            onSelect(item)
            CloseDropdowns()
            M.Refresh()
        end)
        panel._rows = panel._rows or {}
        panel._rows[#panel._rows+1] = row
        row._selectedFn = selectedFn
        return row
    end

    local function RefreshDropdown(panel)
        if not panel or not panel._rows then return end
        for _, row in ipairs(panel._rows) do
            local selected = row._selectedFn and row._selectedFn(row._entry)
            if selected then
                row._check:Show()
                row._label:SetTextColor(1,0.82,0.2)
            else
                row._check:Hide()
                local key = row._entry and row._entry.key
                local c = key and CLASS_COLOR[key]
                if c then row._label:SetTextColor(c[1],c[2],c[3])
                else row._label:SetTextColor(0.92,0.92,0.92) end
            end
        end
    end
    frame._CloseDropdowns = CloseDropdowns
    frame._RefreshDropdown = RefreshDropdown

    local function StyleSelectorButton(button)
        button:SetNormalFontObject("GameFontHighlightSmall")
        button:SetHighlightFontObject("GameFontNormalSmall")
        button:SetPushedTextOffset(0, -1)
        if not button._arrow then
            local arrow = button:CreateTexture(nil, "OVERLAY")
            arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
            arrow:SetSize(12, 12)
            arrow:SetPoint("RIGHT", button, "RIGHT", -7, 0)
            arrow:SetTexCoord(0, 1, 0, 1)
            button._arrow = arrow
        end
        local fs = button:GetFontString()
        if fs then
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", button, "LEFT", 9, 0)
            fs:SetPoint("RIGHT", button, "RIGHT", -22, 0)
            fs:SetJustifyH("CENTER")
        end
        pcall(function()
            button:SetBackdrop({
                bgFile="Interface\\Buttons\\WHITE8X8",
                edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
                tile=false, edgeSize=10,
                insets={left=2,right=2,top=2,bottom=2},
            })
            button:SetBackdropColor(0.025,0.03,0.04,0.96)
            button:SetBackdropBorderColor(0.38,0.38,0.42,0.95)
        end)
        button:SetScript("OnEnter", function(self)
            pcall(function() self:SetBackdropBorderColor(0.9,0.72,0.25,1) end)
        end)
        button:SetScript("OnLeave", function(self)
            pcall(function() self:SetBackdropBorderColor(0.38,0.38,0.42,0.95) end)
            GameTooltip:Hide()
        end)
    end

    -- Primary navigation is centered and visually separate from filtering.
    local navBar = CreateFrame("Frame",nil,frame)
    navBar:SetSize(332,24)
    navBar:SetPoint("TOPLEFT",18,-12)
    frame._navBar = navBar

    local buildsTab = CreateFrame("Button",nil,navBar,"UIPanelButtonTemplate")
    buildsTab:SetSize(110,22)
    buildsTab:SetPoint("LEFT",0,0)
    buildsTab:SetText("|cffffd200Build Library|r")
    buildsTab:Disable()

    leaderboardBtn = CreateFrame("Button",nil,navBar,"UIPanelButtonTemplate")
    leaderboardBtn:SetSize(112,22)
    leaderboardBtn:SetPoint("LEFT",buildsTab,"RIGHT",4,0)
    leaderboardBtn:SetText("Leaderboard")
    leaderboardBtn:SetScript("OnClick",function()
        CloseDropdowns()
        frame:Hide()
        if Nexus.Leaderboard then Nexus.Leaderboard.Show() end
    end)

    wishlistBtn = CreateFrame("Button",nil,navBar,"UIPanelButtonTemplate")
    wishlistBtn:SetSize(98,22)
    wishlistBtn:SetPoint("LEFT",leaderboardBtn,"RIGHT",4,0)
    wishlistBtn:SetText("Wishlists")
    wishlistBtn:SetScript("OnClick",function()
        CloseDropdowns()
        frame:Hide()
        if Nexus.WishlistEditor then Nexus.WishlistEditor.Show() end
    end)

    -- Browse toolbar ----------------------------------------------------
    local browseLabel = frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    browseLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -64)
    frame._browseLabel = browseLabel
    browseLabel:SetText("BROWSE BUILDS")

    local actionLabel = frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    actionLabel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -64)
    frame._actionLabel = actionLabel
    actionLabel:SetText("ACTIONS")

    searchBox = CreateFrame("EditBox","NexusBuildsSearch",frame,"InputBoxTemplate")
    frame._searchBox = searchBox
    searchBox:SetSize(165,22)
    searchBox:SetPoint("TOPLEFT",20,-78)
    searchBox:SetAutoFocus(false)
    searchBox:SetText(FilterSettings().search or "")
    searchBox:SetScript("OnTextChanged",function(self)
        if clearSearchBtn then
            if (self:GetText() or "") ~= "" then clearSearchBtn:Show()
            else clearSearchBtn:Hide() end
        end
        if suppressSearchChange then return end
        ControllerInstance().SetFilter("search", self:GetText() or "")
        M.Refresh()
    end)
    local searchLabel = frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    frame._searchLabel = searchLabel
    searchLabel:SetPoint("LEFT",searchBox,"LEFT",6,0)
    searchLabel:SetText("Search title, author, or description...")
    searchBox:SetScript("OnEditFocusGained",function() searchLabel:Hide(); CloseDropdowns() end)
    searchBox:SetScript("OnEditFocusLost",function(self)
        if self:GetText() == "" then searchLabel:Show() end
    end)
    if (FilterSettings().search or "") ~= "" then searchLabel:Hide() end

    clearSearchBtn = CreateFrame("Button",nil,searchBox,"UIPanelButtonTemplate")
    frame._clearSearchBtn = clearSearchBtn
    clearSearchBtn:SetSize(82,18)
    clearSearchBtn:SetPoint("RIGHT",searchBox,"RIGHT",-2,0)
    clearSearchBtn:SetText("Clear Search")
    pcall(function() searchBox:SetTextInsets(6,86,0,0) end)
    if (FilterSettings().search or "") == "" then clearSearchBtn:Hide() end
    clearSearchBtn:SetScript("OnClick",function()
        local filters = FilterSettings()
        local requestedPage = math.max(1,math.floor(tonumber(filters.page) or 1))
        ControllerInstance().SetFilter("search", "")
        suppressSearchChange = true
        searchBox:SetText("")
        suppressSearchChange = false
        ControllerInstance().SetFilter("page", requestedPage)
        searchLabel:Show()
        clearSearchBtn:Hide()
        M.Refresh()
    end)

    -- Library scope is a direct two-button selector instead of a hidden dropdown.
    scopeBtn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    frame._scopeBtn = scopeBtn
    scopeBtn:SetSize(84,22)
    scopeBtn:SetPoint("LEFT",searchBox,"RIGHT",8,0)
    scopeBtn:SetText("All Shared")
    scopeBtn:SetScript("OnClick",function()
        ControllerInstance().SetFilter("scope", "all")
        ControllerInstance().ClearSelection()
        CloseDropdowns()
        M.Refresh()
    end)
    scopeBtn:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("All Shared",1,0.82,0.2)
        GameTooltip:AddLine("Browse shared community builds.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    scopeBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)

    myBuildsBtn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    frame._myBuildsBtn = myBuildsBtn
    myBuildsBtn:SetSize(84,22)
    myBuildsBtn:SetPoint("LEFT",scopeBtn,"RIGHT",4,0)
    -- M4 (UX-15): the scope is Mine, so the words My Builds keep one meaning,
    -- the game's own page of Saved Builds. The internal scope key stays mine.
    myBuildsBtn:SetText("Mine")
    myBuildsBtn:SetScript("OnClick",function()
        ControllerInstance().SetFilter("scope", "mine")
        ControllerInstance().ClearSelection()
        CloseDropdowns()
        M.Refresh()
    end)
    myBuildsBtn:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Mine",1,0.82,0.2)
        GameTooltip:AddLine("Browse your Saved Builds and shared listings.",0.8,0.8,0.8,true)
        GameTooltip:AddLine("This is a Build Library scope. The game's own My Builds page (Nexus panel button) is where a Saved Build is chosen or assigned.",0.65,0.65,0.65,true)
        GameTooltip:Show()
    end)
    myBuildsBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)

    classDropBtn = CreateFrame("Button",nil,frame)
    classDropBtn:SetSize(128,22)
    classDropBtn:SetPoint("LEFT",myBuildsBtn,"RIGHT",6,0)
    frame._classDropBtn = classDropBtn
    StyleSelectorButton(classDropBtn)
    classDropBtn:SetScript("OnClick",function()
        local filters = FilterSettings()
        ControllerInstance().SetFilter("currentClassOnly",
            filters.currentClassOnly == false)
        ControllerInstance().ClearSelection()
        CloseDropdowns()
        M.Refresh()
    end)
    classDropBtn:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Current Class Only",1,0.82,0.2)
        GameTooltip:AddLine("Turn off to include every class; missing class data is shown as Unknown.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    classDropBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)
    -- Preserve the established named frame for compatibility. The class
    -- choice is now a direct two-state control, so the shell stays hidden.
    dropPanel = CreateFrame("Frame","NexusClassDropPanel",UIParent)
    dropPanel:SetSize(138,10)
    StyleDropdownPanel(dropPanel)
    dropPanel:Hide()

    -- The DPS-record qualifier: one check box with a fixed label. Checked
    -- requires both records; unchecked imposes no DPS-record requirement.
    -- The browsing scope stays on the All Shared / Mine buttons. The
    -- check always shows the saved filter (M.Refresh), never a guess.
    local qualifiedBox = CreateFrame("Button",nil,frame)
    qualifiedBox:SetSize(196,22)
    qualifiedBox:SetPoint("LEFT",classDropBtn,"RIGHT",6,0)
    frame._qualifiedBox = qualifiedBox
    qualifiedBtn = CreateFrame("CheckButton",nil,qualifiedBox,"UICheckButtonTemplate")
    qualifiedBtn:SetSize(22,22)
    qualifiedBtn:SetPoint("LEFT",qualifiedBox,"LEFT",0,0)
    frame._qualifiedBtn = qualifiedBtn
    local qualifiedLabel = qualifiedBox:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    qualifiedLabel:SetPoint("LEFT",qualifiedBtn,"RIGHT",2,0)
    qualifiedLabel:SetJustifyH("LEFT")
    qualifiedLabel:SetText("Require both DPS records")
    frame._qualifiedLabel = qualifiedLabel
    local function ToggleQualified()
        local filters = FilterSettings()
        ControllerInstance().SetFilter("qualifiedOnly",
            filters.qualifiedOnly == false)
        ControllerInstance().ClearSelection()
        CloseDropdowns()
        M.Refresh()
    end
    local function QualifiedTip(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Require both DPS records",1,0.82,0.2)
        GameTooltip:AddLine("Checked: show only builds with both a Training Dummy and a Lich King record that this client has. Unchecked: no DPS-record requirement.",0.8,0.8,0.8,true)
        GameTooltip:AddLine("This is record availability, not proof of build quality, not verified outside the game, and not a sign that Sync has finished.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end
    for _, control in ipairs({qualifiedBtn,qualifiedBox}) do
        control:SetScript("OnClick",ToggleQualified)
        control:SetScript("OnEnter",QualifiedTip)
        control:SetScript("OnLeave",function() GameTooltip:Hide() end)
    end

    local sorts={{key="dps",label="Highest DPS"},{key="recent",label="Newest"},{key="title",label="Name"}}
    sortToggle = CreateFrame("Button",nil,frame)
    sortToggle:SetSize(126,22)
    sortToggle:SetPoint("LEFT",frame._qualifiedBox,"RIGHT",6,0)
    frame._sortToggle = sortToggle
    StyleSelectorButton(sortToggle)
    sortPanel = CreateFrame("Frame","NexusBuildSortPanel",UIParent)
    sortPanel:SetSize(134,#sorts*24+10)
    StyleDropdownPanel(sortPanel)
    for i,entry in ipairs(sorts) do
        AddDropdownRow(sortPanel,entry,i,134,
            function(item) return (FilterSettings().sortMode or "dps") == item.key end,
            function(item)
                ControllerInstance().SetFilter("sortMode", item.key)
            end)
    end
    sortToggle:SetScript("OnClick",function(self) OpenDropdown(sortPanel,self) end)
    sortToggle:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Sort builds",1,1,1)
        GameTooltip:AddLine("Eligible builds use only the selected order.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    sortToggle:SetScript("OnLeave",function() GameTooltip:Hide() end)

    syncBtn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    syncBtn:SetSize(88,22)
    syncBtn:SetPoint("TOPRIGHT",-132,-78)
    frame._syncBtn = syncBtn
    syncBtn:SetText("Sync Now")
    syncBtn:SetScript("OnClick",function()
        CloseDropdowns()
        local ok, err, available = ControllerInstance().RequestSync()
        if not available then return end
        if ok == nil then
            syncBtn:SetText("Preparing...")
            print("|cff7fd5ffNexus:|r " .. tostring(err or "preparing sync data"))
        elseif ok then print("|cff7fd5ffNexus:|r asking other players for their builds...")
        else print("|cffff6060Nexus:|r "..tostring(err)) end
    end)
    syncBtn:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Sync Now",1,1,1)
        GameTooltip:AddLine("Asks other Nexus users for shared builds and DPS records.",0.8,0.8,0.8,true)
        local modeText = M.SyncModeLine()
        if modeText then GameTooltip:AddLine(modeText,1,0.82,0,true) end
        GameTooltip:AddLine("With Automatic, a new personal DPS best (with its Echo list) and its Record Loadout build page may be sent, each only if this client admits it: the page as a summary first, its Echo list only in later answers to players who ask. Sending is not delivery.",0.7,0.7,0.7,true)
        GameTooltip:AddLine("Sent means it left this client, not that anyone stored it. Received means it arrived here; stored means this client kept it.",0.7,0.7,0.7,true)
        GameTooltip:Show()
    end)
    syncBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)

    -- The one Sync mode choice, beside Sync Now. Opening it is a draft only.
    frame._modeBtn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    frame._modeBtn:SetSize(96,22)
    frame._modeBtn:SetPoint("TOPRIGHT",-128,-104)
    frame._modeBtn:SetText("Sync mode...")
    frame._modeBtn:SetScript("OnClick",function()
        CloseDropdowns()
        M.OpenSyncModeChoice()
    end)
    frame._modeBtn:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Sync mode",1,1,1)
        GameTooltip:AddLine("Choose Automatic, Manual or Off. Opening it shows the current mode and changes nothing; only Apply saves your choice.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    frame._modeBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)

    local postBtn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    postBtn:SetSize(110,22)
    postBtn:SetPoint("TOPRIGHT",-15,-78)
    frame._postBtn = postBtn
    postBtn:SetText("Share Build")
    postBtn:SetScript("OnClick",function() CloseDropdowns(); M.ShowPostBuild() end)
    postBtn:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Share a build",1,1,1)
        GameTooltip:AddLine("Choose a saved loadout or wishlist, then add its title and description.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    postBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)

    resultText = frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    resultText:SetPoint("TOPLEFT",20,-108)
    resultText:SetSize(180,16)
    resultText:SetJustifyH("LEFT")
    frame._resultText = resultText

    prevPageBtn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    prevPageBtn:SetSize(48,20)
    prevPageBtn:SetPoint("TOPLEFT",202,-104)
    prevPageBtn:SetText("Prev")
    frame._prevPageBtn = prevPageBtn
    prevPageBtn:SetScript("OnClick",function()
        local filters = FilterSettings()
        if (filters.page or 1) <= 1 then return end
        ControllerInstance().SetFilter("page", (filters.page or 1) - 1)
        if scrollBar then scrollBar.value = 0 end
        M.Refresh()
    end)

    pageText = frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    pageText:SetPoint("TOPLEFT",254,-108)
    pageText:SetSize(62,16)
    pageText:SetJustifyH("CENTER")
    frame._pageText = pageText

    nextPageBtn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    nextPageBtn:SetSize(48,20)
    nextPageBtn:SetPoint("TOPLEFT",320,-104)
    nextPageBtn:SetText("Next")
    frame._nextPageBtn = nextPageBtn
    nextPageBtn:SetScript("OnClick",function()
        local filters = FilterSettings()
        ControllerInstance().SetFilter("page", (filters.page or 1) + 1)
        if scrollBar then scrollBar.value = 0 end
        M.Refresh()
    end)

    syncStatusText = frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    frame._syncStatusText = syncStatusText
    syncStatusText:SetPoint("TOPLEFT",378,-108)
    syncStatusText:SetSize(632,14)
    syncStatusText:SetJustifyH("LEFT")
    -- The responsive layout sizes this region to the rows its text needs.
    syncStatusText:SetJustifyV("TOP")

    -- Left: scrollable card list -----------------------------------------
    -- Clip region (SetClipsChildren is retail-only on 3.3.5 -- same class
    -- of API as SetColorTexture; wrap defensively so everything below still
    -- gets created even if this call throws)
    local listClip = CreateFrame("Frame",nil,frame)
    listClip:SetPoint("TOPLEFT",20,-130)
    listClip:SetPoint("BOTTOMLEFT",20,20)
    listClip:SetWidth(480)
    frame._listClip = listClip
    pcall(function() listClip:SetClipsChildren(true) end)

    scrollFrame = CreateFrame("ScrollFrame",nil,listClip)
    scrollFrame:SetAllPoints(listClip)
    scrollFrame:EnableMouseWheel(true)

    scrollChild = CreateFrame("Frame",nil,scrollFrame)
    scrollChild:SetWidth(460)
    scrollChild:SetHeight(1)     -- set dynamically in Refresh
    scrollFrame:SetScrollChild(scrollChild)

    -- Simple scroll offset tracking -- no template, no SetVerticalScroll,
    -- just keep an offset and SetVerticalScroll via pcall (different API
    -- names across WoW versions).
    scrollBar = { value = 0, min = 0, max = 0 }  -- plain table, no template
    local function SetScroll(val)
        val = math.max(scrollBar.min, math.min(scrollBar.max, val))
        scrollBar.value = val
        pcall(function() scrollFrame:SetVerticalScroll(val) end)
        if renderBuildWindow and frame and frame:IsShown()
            and not virtualBinding then
            Measure("community.render", renderBuildWindow, "scroll")
        end
    end
    scrollBar.SetValue = function(_, val) SetScroll(val) end
    scrollBar.GetValue = function(_) return scrollBar.value end
    scrollBar.SetMinMaxValues = function(_, mn, mx) scrollBar.min = mn; scrollBar.max = mx end
    scrollBar.GetMinMaxValues = function(_) return scrollBar.min, scrollBar.max end

    scrollFrame:SetScript("OnMouseWheel",function(_,delta)
        SetScroll(scrollBar.value - delta * CARD_HEIGHT * 3)
    end)
    scrollFrame:SetScript("OnSizeChanged", function()
        if renderBuildWindow and frame and frame:IsShown()
            and not virtualBinding then
            Measure("community.render", renderBuildWindow, "resize")
        end
    end)
    frame._virtualListScrollFrame = scrollFrame

    local emptyState = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyState:SetPoint("TOPLEFT", listClip, "TOPLEFT", 20, 34)
    emptyState:SetSize(400, 80)
    emptyState:SetJustifyH("CENTER")
    emptyState:SetJustifyV("TOP")
    emptyState:Hide()
    frame._emptyState = emptyState

    -- Right: detail panel ------------------------------------------------
    EnsureDetailPanel(frame)
    frame._detailPanel = detailPanel
    detailPanel:ClearAllPoints()
    detailPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 520, -130)
    detailPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 20)
    detailPanel:SetFrameLevel(frame:GetFrameLevel() + 10)

    -- Style the static browser controls once. Dynamic cards are created from
    -- an already dark template and do not need a full recursive restyle on
    -- every refresh.
    if Nexus.Theme then Nexus.Theme.StyleTree(frame) end
    M.ApplyResponsiveLayout(true)
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.ApplyFontTree then
        Nexus.LayoutMetrics.ApplyFontTree(frame,"normal")
        Nexus.LayoutMetrics.ApplyFontTree(dropPanel,"normal")
        Nexus.LayoutMetrics.ApplyFontTree(sortPanel,"normal")
        frame._nexusOwnedFonts = true
    end
    return frame
end


function M.GetSelectedBuildForPanel()
    if not frame or not frame:IsShown() then return nil end
    return ControllerInstance().SelectedBuild()
end

function M.GetSelectedBuildForPanelKey()
    if not frame or not frame:IsShown() then return nil, 0, 0 end
    return ControllerInstance().SelectedBuildKey()
end

function M.VirtualStats()
    local out = {}
    for key, value in pairs(virtualStats) do out[key] = value end
    out.selectedId = SelectedId()
    out.refreshDirty = refreshDirty
    out.savedImport = ControllerInstance().SavedImportStats()
    return out
end

local function ReadViewStatus()
    local controller = ControllerInstance()
    if not (controller and type(controller.ViewDiagnosticState) == "function") then
        return {}
    end
    local ok, value = pcall(controller.ViewDiagnosticState)
    return ok and type(value) == "table" and value or {}
end

RenderSyncStatus = function(receiveCount)
    if not (syncStatusText and Nexus and Nexus.Sync) then return end
    local sync = Nexus.Sync
    local published = viewDiagnostic.publishedPage > 0
    local base = published and {} or ReadViewStatus()
    local bundled = published and viewDiagnostic.bundledCount
        or (base.bundledCount or 0)
    local overlay = published and viewDiagnostic.overlayCount
        or (base.overlayCount or 0)
    local available = published and viewDiagnostic.availableCount
        or (base.availableCount or 0)
    local shown = viewDiagnostic.displayedCount or 0
    local results = viewDiagnostic.resultCount or 0
    local version = published and viewDiagnostic.catalogVersion
        or (base.catalogVersion or "unversioned")
    local receiving = type(sync.IsReceiving) == "function"
        and sync.IsReceiving() == true
    if receiving then
        receiveCount = tonumber(receiveCount)
            or (type(sync.LastSyncNewCount) == "function"
                and tonumber(sync.LastSyncNewCount())) or 0
        local remaining = type(sync.ReceiveTimeLeft) == "function"
            and tonumber(sync.ReceiveTimeLeft()) or 0
        syncStatusText:SetText(string.format(
            "|cff4dff80Listening %ds (%d new); %d bundled + %d overlay; %d available; %d shown of %d results|r",
            math.ceil(math.max(0,remaining)),receiveCount,bundled,overlay,
            available,shown,results))
    else
        local stats = type(sync.Stats) == "function" and sync.Stats() or {}
        local received = type(stats) == "table"
            and (tonumber(stats.received) or 0) or 0
        local added = type(sync.LastSyncNewCount) == "function"
            and (tonumber(sync.LastSyncNewCount()) or 0) or 0
        if received > 0 then
            syncStatusText:SetText(string.format(
                "|cff888888%d bundled + %d overlay; %d available; %d shown of %d results. Last sync added %d; catalog %s.|r",
                bundled,overlay,available,shown,results,added,version))
        else
            syncStatusText:SetText(string.format(
                "|cff888888%d bundled + %d overlay; %d available; %d shown of %d results; catalog %s. Sync Now asks other Nexus users.|r",
                bundled,overlay,available,shown,results,version))
        end
    end
    local syncStats = type(sync.Stats) == "function" and sync.Stats() or {}
    local preparing = syncStats.preparingRequest == true
    if preparing then syncStatusText:SetText("|cff7fd5ffPreparing sync data...|r") end
    -- The latest Share of this session keeps its own line here, so its state
    -- is still stated after the form or this window is closed and reopened.
    local shareLine = ShareStatusLine()
    if shareLine then
        syncStatusText:SetText((syncStatusText:GetText() or "") .. "\n" .. shareLine)
    end
    -- The current Sync mode is stated in every mode, with what it does.
    local modeText = SyncModeLine()
    if modeText then
        syncStatusText:SetText((syncStatusText:GetText() or "") .. "\n|cffffd100" .. modeText .. "|r")
    end
    if syncBtn then syncBtn:SetText(preparing and "Preparing..."
        or receiving and "Listening..." or "Sync Now") end
    -- The status region holds every row of this text. Its rows are measured
    -- against the width the layout gave it; only a change of rows re-lays
    -- the window (once), so ordinary refreshes reuse the current geometry.
    local metrics = Nexus.LayoutMetrics
    local layout = frame and frame._responsiveLayout
    local box = type(layout) == "table" and layout.boxes and layout.boxes.status
    if box and metrics and type(metrics.CommunityStatusRows) == "function" then
        local rows = metrics.CommunityStatusRows(syncStatusText:GetText(),
            box.w, layout.scale)
        if rows ~= frame._nexusStatusRows then
            frame._nexusStatusRows = rows
            M.ApplyResponsiveLayout(true)
        end
    end
end

-- The Sync mode choice beside Sync Now. A successful Apply only re-renders
-- this view's status line so it states the new mode; it requests nothing.
function M.OpenSyncModeChoice()
    return SyncModeDialog.Open(frame, function()
        if frame and frame:IsShown() then RenderSyncStatus() end
    end)
end

function M.DiagnosticSnapshot()
    local base = ReadViewStatus()
    local current = viewDiagnostic.projectionCurrent == true
    local receiving = false
    local sync = Nexus and Nexus.Sync
    if sync and type(sync.IsReceiving) == "function" then
        local ok, value = pcall(sync.IsReceiving)
        receiving = ok and value == true
    end
    local shown = frame and frame:IsShown() or false
    local dirty = refreshDirty or not current
    local reason
    if not shown then reason = "hidden"
    elseif base.filterScope == "mine" and base.savedImportPending then
        reason = "saved-import"
    elseif viewDiagnostic.projectionPending then reason = "projection-pending"
    elseif viewDiagnostic.projectionError then reason = "projection-error"
    elseif dirty and receiving and viewDiagnostic.publishedPage > 0 then
        reason = "sync-receiving"
    elseif dirty then reason = "dirty"
    elseif viewDiagnostic.publishedPage == 0 then reason = "not-published"
    else reason = "none" end
    return {
        schema=1,view="community",
        catalogCount=base.catalogCount or 0,
        bundledCount=viewDiagnostic.publishedPage > 0
            and viewDiagnostic.bundledCount or (base.bundledCount or 0),
        overlayCount=viewDiagnostic.publishedPage > 0
            and viewDiagnostic.overlayCount or (base.overlayCount or 0),
        availableCount=viewDiagnostic.publishedPage > 0
            and viewDiagnostic.availableCount or (base.availableCount or 0),
        filterMatchedCount=viewDiagnostic.filterMatchedCount,
        qualifyingCount=viewDiagnostic.qualifyingCount,
        resultCount=viewDiagnostic.resultCount,
        displayedCount=viewDiagnostic.displayedCount,
        searchActive=viewDiagnostic.publishedPage > 0
            and viewDiagnostic.searchActive or base.filterSearchActive == true,
        catalogVersion=viewDiagnostic.publishedPage > 0
            and viewDiagnostic.catalogVersion
            or (base.catalogVersion or "unversioned"),
        requestedPage=base.requestedPage or 1,
        publishedPage=viewDiagnostic.publishedPage,
        pageCount=viewDiagnostic.publishedPage > 0
            and lastPublishedPageCount or 0,
        publishedRows=viewDiagnostic.publishedPage > 0
            and virtualStats.results or 0,
        filterScope=base.filterScope or "all",
        filterClass=base.filterClass or "UNAVAILABLE",
        filterCurrentClassOnly=base.filterCurrentClassOnly ~= false,
        filterQualifiedOnly=base.filterQualifiedOnly ~= false,
        filterSearchActive=base.filterSearchActive == true,
        filterSort=base.filterSort or "dps",filterCategory="builds",
        projectionCurrent=current,projectionPending=
            viewDiagnostic.projectionPending == true,
        projectionDirty=dirty,savedImportPending=
            base.savedImportPending == true,
        savedImportPhase=base.savedImportPhase or "unknown",
        syncReceiving=receiving,
        lastPublicationAge=PublicationAge(viewDiagnostic.publishedAt),
        blockedReason=reason,
    }
end

function M.MarkDataDirty()
    if not refreshDirty then
        refreshDirty = true
        virtualStats.dirtyMarks = virtualStats.dirtyMarks + 1
    end
    viewDiagnostic.projectionPending = false
    viewDiagnostic.projectionError = false
    viewDiagnostic.projectionCurrent = false
    return true
end

function M.ScrollTo(offset)
    if not scrollBar then return false end
    scrollBar:SetValue(tonumber(offset) or 0)
    return true
end

------------------------------------------------------------------------
-- Refresh  (called every tick while open, and whenever data changes)
------------------------------------------------------------------------

function M.Refresh()
    -- An open Share form follows its Share when that settles, also when the
    -- Community window is closed.
    if postPopup and postPopup:IsShown() and postPopup._shareStatus then
        postPopup._shareStatus:SetText(PostStatusText())
    end
    if not frame or not frame:IsShown() then return end
    M.ApplyResponsiveLayout(false)

    -- Update control labels
    local fs = FilterSettings()
    if classDropBtn then
        if fs.currentClassOnly == false then
            classDropBtn:SetText("All Classes")
        elseif fs.classFilter then
            classDropBtn:SetText("Current Class Only")
        else
            classDropBtn:SetText("Class Loading...")
        end
    end
    if qualifiedBtn then
        qualifiedBtn:SetChecked(fs.qualifiedOnly ~= false)
    end
    if scopeBtn and myBuildsBtn then
        if fs.scope == "mine" then
            scopeBtn:Enable()
            myBuildsBtn:Disable()
        else
            scopeBtn:Disable()
            myBuildsBtn:Enable()
        end
    end
    if sortToggle then
        if fs.sortMode == "class" or not fs.sortMode then fs.sortMode = "dps" end
        local labels={dps="Highest DPS",recent="Newest",title="Name"}
        sortToggle:SetText("Sort: "..(labels[fs.sortMode] or "Highest DPS"))
        sortToggle:Show()
    end
    if frame._RefreshDropdown then
        frame._RefreshDropdown(dropPanel)
        frame._RefreshDropdown(sortPanel)
    end

    -- A page click is cheap state too. Show the requested page immediately
    -- while retaining both the last-good rows and their last published bound
    -- until the deferred projection can clamp and publish the new result.
    local requestedPage = math.max(1, math.floor(tonumber(fs.page) or 1))
    local visiblePageCount = math.max(requestedPage, lastPublishedPageCount)
    if pageText then
        pageText:SetText(string.format("%d / %d", requestedPage,
            visiblePageCount))
    end
    if prevPageBtn and nextPageBtn then
        if requestedPage > 1 then prevPageBtn:Enable()
        else prevPageBtn:Disable() end
        if requestedPage < visiblePageCount then nextPageBtn:Enable()
        else nextPageBtn:Disable() end
    end

    -- Import/projection work may be deferred for many frames. Keep the cheap
    -- filter, scope, sort, and page controls truthful before that gate so the
    -- visible browser never looks frozen while its last-good rows stay bound.
    local controller = ControllerInstance()
    local importPending = fs.scope == "mine"
        and type(controller.HasPendingSavedLoadoutImport) == "function"
        and controller.HasPendingSavedLoadoutImport()
    if importPending then
        refreshDirty = true
        -- The rows still shown are the last published ones, not the result
        -- of the current filters.
        if resultText then resultText:SetText("|cff7fd5ffUpdating results...|r") end
        if frame._emptyState then frame._emptyState:Hide() end
        frame._resultsStale = true
        viewDiagnostic.projectionPending = false
        viewDiagnostic.projectionError = false
        viewDiagnostic.projectionCurrent = false
        RenderSyncStatus()
        RefreshDetailPanel(SelectedId(), true)
        return false, "pending"
    end

    -- Build browser contains builds only. DPS rankings are rendered in the
    -- dedicated Leaderboard window.
    local boardRows = nil
    local builds, projectionSummary, projectionError =
        Measure("community.projection", SortedBuilds)
    if type(builds) ~= "table" then
        if projectionError == "pending" then
            refreshDirty = true
            if resultText then resultText:SetText("|cff7fd5ffUpdating results...|r") end
            -- "No builds match the current ... filters" belongs to the last
            -- published result, not to the filters now being prepared.
            if frame._emptyState then frame._emptyState:Hide() end
            -- Until the next publication (a scroll or resize re-binds the
            -- last rows, but must not show their empty text again).
            frame._resultsStale = true
            viewDiagnostic.projectionPending = true
            viewDiagnostic.projectionError = false
            viewDiagnostic.projectionCurrent = false
            RenderSyncStatus()
            RefreshDetailPanel(SelectedId(), true)
            return false, "pending"
        end
        refreshDirty = true
        viewDiagnostic.projectionPending = false
        viewDiagnostic.projectionError = true
        viewDiagnostic.projectionCurrent = false
        virtualStats.dataFailures = virtualStats.dataFailures + 1
        RenderSyncStatus()
        return false, projectionError
    end
    if projectionSummary and fs.page ~= projectionSummary.page then
        ControllerInstance().SetFilter("page", projectionSummary.page)
        fs.page = projectionSummary.page
    end
    if projectionSummary then
        viewDiagnostic.bundledCount = math.max(0,math.floor(tonumber(
            projectionSummary.bundledCount) or 0))
        viewDiagnostic.overlayCount = math.max(0,math.floor(tonumber(
            projectionSummary.overlayCount) or 0))
        viewDiagnostic.availableCount = math.max(0,math.floor(tonumber(
            projectionSummary.availableCount) or 0))
        viewDiagnostic.filterMatchedCount = math.max(0,math.floor(tonumber(
            projectionSummary.filterMatchedCount) or 0))
        viewDiagnostic.qualifyingCount = math.max(0,math.floor(tonumber(
            projectionSummary.qualifyingCount) or 0))
        viewDiagnostic.resultCount = math.max(0,math.floor(tonumber(
            projectionSummary.resultCount) or 0))
        viewDiagnostic.displayedCount = math.max(0,math.floor(tonumber(
            projectionSummary.displayedCount) or #builds))
        viewDiagnostic.searchActive = projectionSummary.searchActive == true
        viewDiagnostic.catalogVersion = tostring(
            projectionSummary.catalogVersion or "unversioned"):sub(1,64)
    end
    RenderSyncStatus()
    lastPublishedPageCount = math.max(1,
        tonumber(projectionSummary and projectionSummary.pageCount) or 1)
    if pageText and projectionSummary then
        pageText:SetText(string.format("%d / %d",
            projectionSummary.page or 1, projectionSummary.pageCount or 1))
    end
    if prevPageBtn and nextPageBtn then
        local page = projectionSummary and projectionSummary.page or 1
        local pageCount = projectionSummary and projectionSummary.pageCount or 1
        if page > 1 then prevPageBtn:Enable() else prevPageBtn:Disable() end
        if page < pageCount then nextPageBtn:Enable() else nextPageBtn:Disable() end
    end
    frame._resultsStale = false
    if resultText then
        local first = projectionSummary and projectionSummary.first or 0
        local last = projectionSummary and projectionSummary.last or #builds
        local total = projectionSummary and projectionSummary.filteredTotal or #builds
        resultText:SetText(string.format("|cffd8c7a0Showing %d-%d of %d|r",
            first, last, total))
    end
    renderBuildWindow = function(reason)
        if virtualBinding then return end
        virtualBinding = true
        local ok, err = pcall(function()
    ReleaseAllCards()
    ReleaseAllHeaders()
    local cardLayout = frame and frame._responsiveLayout
        and frame._responsiveLayout.card or {
            width=460,titleWidth=250,dpsWidth=178,contentWidth=428,
            gap=6,iconCapacity=12,
        }

    local rowHeight = CARD_HEIGHT + 4
    local visibleH = math.max(100,
        (scrollFrame and scrollFrame:GetHeight()) or 458)
    local virtual = Nexus.VirtualList.Window(
        #builds, rowHeight, visibleH,
        scrollBar and scrollBar.value or 0, 2)
    local yOffset = (virtual.first - 1) * rowHeight
    local lastClass = "__none__"
    local showHeaders = false

    for index = virtual.first, virtual.last do
        local projected = builds[index]
        local b = LoadBuild(projected.id) or projected
        b.displayAuthor = projected.displayAuthor
        b.displayTitle = projected.displayTitle
        b.displayDescription = projected.displayDescription
        b.publicIdentityKey = projected.publicIdentityKey
        b.publicIdentityVerified = projected.publicIdentityVerified
        b._nexusDps = projected._nexusDps
        b._nexusBestDps = projected._nexusBestDps
        b._nexusQualified = projected._nexusQualified
        b._nexusQualification = projected._nexusQualification
        local bClass = (b.class or "UNKNOWN"):upper()
        if bClass == "" then bClass = "UNKNOWN" end

        -- Class header when sorted by class and not filtered
        if showHeaders and bClass ~= lastClass then
            lastClass = bClass
            local h = GetHeader(scrollChild)
            h:SetWidth(cardLayout.width)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
            local c = CLASS_COLOR[bClass] or {0.8,0.8,0.8}
            h.label:SetTextColor(c[1],c[2],c[3])
            h.label:SetText(CLASS_LABEL[bClass] or bClass)
            activeHeaders[#activeHeaders+1] = h
            yOffset = yOffset + 26
        end

        -- Build card
        local card = GetCard(scrollChild)
        -- Check cards into the active set before binding data so the failure
        -- path can always reclaim a partially bound card.
        activeCards[#activeCards+1] = card
        card:SetWidth(cardLayout.width)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
        card.buildId = b.id

        -- Selection highlight
        if b.id == SelectedId() then
            card.selectedHighlight:Show()
        else
            card.selectedHighlight:Hide()
        end

        -- Use a stable class-themed icon instead of a question mark.
        pcall(function() card.classIcon:SetTexture(CLASS_ICON[bClass] or "Interface\\Icons\\INV_Misc_QuestionMark") end)

        -- Title (class colored)
        local c = CLASS_COLOR[bClass] or {1,1,1}
        card.title:SetTextColor(c[1],c[2],c[3])
        card.title:SetWidth(cardLayout.titleWidth)
        card.author:SetWidth(cardLayout.titleWidth)
        card.destination:SetWidth(math.max(80,cardLayout.width-80))
        card.echoCount:SetWidth(cardLayout.dpsWidth)
        card.dpsBreakdown:SetWidth(cardLayout.dpsWidth)
        local rawTitle = tostring(b.title or "")
        local fullTitle = b.displayTitle
            or (Nexus.Identity and Nexus.Identity.DisplaySafeText
                and Nexus.Identity.DisplaySafeText(rawTitle, 1024, true))
            or "Invalid title"
        local titleChars = math.max(12,math.floor(cardLayout.titleWidth
            / (6 * ((frame._responsiveLayout and frame._responsiveLayout.scale)
                or 1))))
        local truncatedTitle = Nexus.LayoutMetrics
            and Nexus.LayoutMetrics.Truncate(rawTitle,titleChars) or rawTitle
        local displayTitle = Nexus.Identity and Nexus.Identity.DisplaySafeText
            and Nexus.Identity.DisplaySafeText(truncatedTitle, 1024, true)
            or "Invalid title"
        card._fullTitle,card._displayTitle = fullTitle,displayTitle
        card.title:SetText(displayTitle)
        do
            local ownerTag = ""
            if IsSavedMirror(b) then ownerTag = "  |cff66ccffSaved Build|r"
            elseif IsOwnBuild(b) then ownerTag = "  |cffffd200Your build|r" end
            local qualityTag = ""
            if b._nexusQualified == false then
                qualityTag = qualityTag .. "  |cffffa040Missing a DPS record|r"
            end
            if bClass == "UNKNOWN" then
                qualityTag = qualityTag .. "  |cffaaaaaaClass not supplied|r"
            end
            -- M4 (UX-14): a shared row whose owner the presentation layer did
            -- not establish says so on the row itself (the detail already
            -- carries the same note). Display only; no owner inference.
            if b.publicIdentityVerified == false and ownerTag == "" then
                qualityTag = qualityTag .. "  |cff999999Owner not established|r"
            end
            local displayAuthor = b.displayAuthor
                or (Nexus.Identity and Nexus.Identity.DisplaySafeText
                    and Nexus.Identity.DisplaySafeText(
                        b.author or "?", 1024, false))
                or "Unknown"
            card.author:SetText("by "..displayAuthor..ownerTag..qualityTag)
        end
        if IsSavedMirror(b) then
            if b.destinationWishlistName then
                local displayText = Nexus and Nexus.Identity
                    and Nexus.Identity.DisplaySafeText
                local destinationName = displayText
                    and displayText(b.destinationWishlistName, 1024, false)
                    or "Wishlist"
                -- M4 (UX-13): the Wishlist's copies found in this Saved
                -- Build (CommunityController EchoProgress), a different unit
                -- from run or planned copies. An unknown total is said as
                -- unavailable, never replaced by a guessed 79.
                local userText = Nexus and Nexus.UserText
                local count = userText and userText.CountText
                    and userText.CountText("savedBuild", b.destinationProgress, b.destinationTotal)
                    or "Wishlist copies in this Saved Build: unavailable"
                card.destination:SetText(string.format("|cffffd200Assigned Wishlist:|r %s  |cff66ff99%s|r", destinationName, count))
            else
                card.destination:SetText("|cff999999No Wishlist assigned|r")
            end
            card.destination:Show()
        else
            card.destination:SetText("")
            card.destination:Hide()
        end

        -- Echo icons
        local echoes = b.echoes or {}
        local shown = math.min(#echoes,MAX_ROW_ICONS,
            cardLayout.iconCapacity or MAX_ROW_ICONS)
        for i, ic in ipairs(card.icons) do
            if i <= shown then
                ic:SetTexture(SpellIcon(echoes[i].spellId))
                pcall(function() ic:SetVertexColor(1,1,1) end)
                ic:Show()
            else
                ic:Hide()
            end
        end
        local extra = #echoes - shown
        card.moreText:ClearAllPoints()
        card.moreText:SetPoint("LEFT",card.icons[math.max(1,shown)],"RIGHT",6,0)
        card.moreText:SetText(extra > 0 and ("|cffff9040+"..extra.."|r") or "")
        if #echoes > 0 then
            do
                -- Public Community rows already carry the revision-scoped
                -- dual-record summary. Never fall back to per-build DPS reads
                -- from the renderer if that projection invariant is broken.
                local dps = b._nexusDps or {
                    dummy=0,lk=0,best=0,average=0,count=0,
                }
                if dps.count == 2 then
                    -- M4 (UX-14): the headline is one category's record, so it
                    -- names that category (the best single record decides it).
                    local headline = dps.lk > dps.dummy and "Lich King"
                        or dps.dummy > dps.lk and "Dummy" or "both records"
                    card.echoCount:SetText(string.format(
                        "|cff4dff80Best %s DPS|r |cff999999(%s)|r", DpsText(dps.best), headline))
                    card.dpsBreakdown:SetText(string.format(
                        "Dummy %s  |cff777777•|r  LK %s  |cff777777•|r  Avg %s",
                        DpsText(dps.dummy), DpsText(dps.lk),
                        DpsText(dps.average)))
                elseif dps.dummy > 0 then
                    card.echoCount:SetText(string.format("|cff4dff80%s DPS|r", DpsText(dps.dummy)))
                    card.dpsBreakdown:SetText("Training Dummy")
                elseif dps.lk > 0 then
                    card.echoCount:SetText(string.format("|cff4dff80%s DPS|r", DpsText(dps.lk)))
                    card.dpsBreakdown:SetText("Lich King")
                else
                    card.echoCount:SetText("|cff777777No DPS record|r")
                    card.dpsBreakdown:SetText("")
                end
            end
        else
            card.echoCount:SetText("|cffffd200Syncing full loadout...|r")
            card.dpsBreakdown:SetText("")
            card.title:SetTextColor(0.65,0.65,0.65)
            local displayAuthor = b.displayAuthor
                or (Nexus.Identity and Nexus.Identity.DisplaySafeText
                    and Nexus.Identity.DisplaySafeText(
                        b.author or "?", 1024, false))
                or "Unknown"
            card.author:SetText("by "..displayAuthor
                .."  |cff777777- waiting for Echoes|r")
        end

        card.mineBadge:Hide()
        card.addBtn:SetText("View")
        card.addBtn:SetSize(52,22)
        card.addBtn:Show()
        card.record = nil

        yOffset = yOffset + rowHeight
    end

    -- Empty state
    if #builds == 0 then
        local total = projectionSummary and projectionSummary.total or 0
        if not projectionSummary then
            -- The bounded whole-collection read says whether it is complete;
            -- an incomplete read is not a count of zero.
            local map, complete = Store()
            if complete then
                for _ in pairs(map) do total=total+1 end
            else
                total = nil
            end
        end
        local msg
        if total == nil then
            msg = "The build library could not be read completely. Try again shortly."
        elseif total == 0 then
            msg = "No builds yet.\n\nPost a build from your active Echo Wishlist, or press Sync Now to find builds from other players."
        else
            msg = "No builds match the current scope, class, DPS-record, or search filters."
        end
        if frame._emptyState and not frame._resultsStale then
            frame._emptyState:SetText(msg)
            frame._emptyState:Show()
        end
        scrollChild:SetHeight(80)
        scrollBar:SetMinMaxValues(0,0)
        scrollBar.value = 0
        pcall(function() scrollFrame:SetVerticalScroll(0) end)
        RefreshDetailPanel(nil)
    else
        if frame._emptyState then frame._emptyState:Hide() end
        scrollChild:SetHeight(math.max(virtual.contentHeight, 10))
        scrollBar:SetMinMaxValues(0, virtual.maxOffset)
        scrollBar.value = virtual.offset
        pcall(function() scrollFrame:SetVerticalScroll(virtual.offset) end)
    end
    virtualStats.results = #builds
    virtualStats.active = #activeCards
    virtualStats.peakActive = math.max(virtualStats.peakActive, #activeCards)
    virtualStats.first, virtualStats.last = virtual.first, virtual.last
    virtualStats.offset, virtualStats.maxOffset = virtual.offset, virtual.maxOffset
    virtualStats.selectedVisible = false
    for index = virtual.first, virtual.last do
        if builds[index] and builds[index].id == SelectedId() then
            virtualStats.selectedVisible = true
            break
        end
    end
    if reason == "scroll" then
        virtualStats.scrollBinds = virtualStats.scrollBinds + 1
    elseif reason == "resize" then
        virtualStats.resizeBinds = virtualStats.resizeBinds + 1
    else
        virtualStats.dataBinds = virtualStats.dataBinds + 1
    end
        end)
        virtualBinding = false
        if not ok then
            pcall(ReleaseAllCards)
            pcall(ReleaseAllHeaders)
            virtualStats.active = 0
            virtualStats.first, virtualStats.last = 1, 0
            virtualStats.selectedVisible = false
            error(err)
        end
    end
    Measure("community.render", renderBuildWindow, "data")
    virtualStats.dataRefreshes = virtualStats.dataRefreshes + 1
    local projections = Nexus and Nexus.ViewProjections
    if projections and type(projections.RecordBind) == "function" then
        projections.RecordBind("builds")
    end
    local peerDebug = Nexus and Nexus.PeerDebug
    if peerDebug and type(peerDebug.IsEnabled) == "function"
        and peerDebug.IsEnabled() and type(peerDebug.Record) == "function" then
        pcall(peerDebug.Record, "community_publication", {
            outcome="published",rows=#builds,
            page=projectionSummary and projectionSummary.page or 1,
        })
        local selected = type(peerDebug.SelectedBuild) == "function"
            and peerDebug.SelectedBuild() or nil
        if selected then
            local included = false
            for index = 1, math.min(#builds, 200) do
                if builds[index] and builds[index].id == selected then
                    included = true
                    break
                end
            end
            local reason
            if not included and type(projections.ExplainBuild) == "function" then
                local ok, explained = pcall(projections.ExplainBuild,
                    selected, FilterSettings())
                if ok then reason = explained end
            end
            pcall(peerDebug.Record, "community_result", {
                id=selected,outcome=included and "included" or "outside_page",
                rows=#builds,page=projectionSummary and projectionSummary.page or 1,
                reason=reason,
            })
        end
    end

    -- Detail panel
    RefreshDetailPanel(SelectedId())

    viewDiagnostic.publishedAt = ClockNow()
    viewDiagnostic.publishedPage = math.max(1, math.floor(tonumber(
        projectionSummary and projectionSummary.page) or requestedPage))
    viewDiagnostic.projectionPending = false
    viewDiagnostic.projectionError = false
    viewDiagnostic.projectionCurrent = true
    refreshDirty = false
    return true
end


    function M.SetViewMode(mode)
        if mode == "dummy" or mode == "lk" then
            if frame then frame:Hide() end
            if Nexus.Leaderboard then Nexus.Leaderboard.Show(mode) end
            return
        end
        M.Refresh()
    end

    function M.Show()
        Measure("community.frame.ensure", EnsureFrame)
        M.ApplyResponsiveLayout(false)
        if Nexus.Panel and Nexus.Panel.AttachMenuFrame then
            Nexus.Panel.AttachMenuFrame(frame)
        end
        if Nexus.Theme and Nexus.Theme.StyleWindow then
            Nexus.Theme.StyleWindow(frame, 0.96)
        end
        if Nexus.Panel and Nexus.Panel.CloseOtherWindows then
            Nexus.Panel.CloseOtherWindows("NexusCommunityBuildsFrame")
        end
        frame:Show()
        M.Refresh()
    end

    function M.Hide()
        if frame then frame:Hide() end
    end

    function M.IsShown()
        return frame and frame:IsShown() or false
    end

    return M
end

Nexus.CommunityInternals.Renderer = Renderer
