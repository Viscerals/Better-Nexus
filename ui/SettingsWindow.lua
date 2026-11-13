-- Issue #163: one discoverable Settings surface over the existing owners.
-- This window never owns a preference or writes one when opened. Its action
-- buttons invoke the same guarded menu callbacks that were already shipped.
Nexus = Nexus or {}
local M = {}
Nexus.SettingsWindow = M

local frame, title, explanation, pageLabel, previous, nextPage
local categoryButtons, rowButtons = {}, {}
local selected, page = "automation", 1
-- Three tall rows leave a bounded text area above paging, even on the
-- 420px compact viewport. Every row also exposes its complete copy on hover.
local PAGE_SIZE = 3
-- Full visible-UI localization (guide family, settings.* keys). Each visible
-- English label below is a reviewed catalog meaning, looked up through
-- Nexus.Localization when it is shown (never cached here); without the seam
-- or for a key it cannot show, the exact English beside the key is shown.
-- Category ids and Sync mode values are identities and are never shown or
-- translated. Rows from other owners (Panel, Theme, SyncModePolicy) arrive
-- already worded by them. The row thresholds below (#label > 100, #detail >
-- 56) count bytes: a translated label may reach them earlier, and its full
-- text stays available on hover. The window title is "Nexus Options"
-- (settings.title.window), the same word as the Options menu button.
local function T(key, english)
    local seam = Nexus.Localization
    if type(seam) ~= "table" or type(seam.Text) ~= "function" then return english end
    local text, source = seam.Text(key)
    if source == "unavailable" then return english end
    return text
end
local function TF(key, args, english)
    local seam = Nexus.Localization
    if type(seam) ~= "table" or type(seam.Format) ~= "function" then return english end
    local text, source = seam.Format(key, args)
    if source == "unavailable" then return english end
    return text
end
local categories = {
    {id="automation", label="Automation", labelKey="settings.label.category_automation", note="Changing a permission uses Nexus's existing controls. Opening this page never starts Auto or spends Orbs.",
        noteKey="settings.note.category_automation"},
    {id="sync", label="Share & Sync", labelKey="settings.label.category_sync", tab="Sync", tabKey="settings.tab.sync", note="The library's Sync choices and Share use their existing explicit controls.",
        noteKey="settings.note.category_sync"},
    {id="appearance", label="Appearance", labelKey="settings.label.category_appearance", note="Style and colour change only how Nexus windows look; they do not change gameplay.",
        noteKey="settings.note.category_appearance"},
    {id="language", label="Language", labelKey="settings.label.category_language", note="A language choice applies after reload or login. Some text remains English in this build.",
        noteKey="settings.note.category_language"},
    {id="display", label="Display", labelKey="settings.label.category_display", note="Display choices affect the local HUD. Server Difficulty is available only when detected.",
        noteKey="settings.note.category_display"},
    {id="notices", label="Notices", labelKey="settings.label.category_notices", note="Choose which update notices to show; this does not install or download an update.",
        noteKey="settings.note.category_notices"},
    {id="support", label="Help & Support", labelKey="settings.label.category_support", tab="Support", tabKey="settings.tab.support", note="These views read information. Preparing a report remains a separate action inside Support.",
        noteKey="settings.note.category_support"},
}
local byId = {}
for _, entry in ipairs(categories) do byId[entry.id] = entry end

local function Plain(value)
    return tostring(value or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function AddMenuRows(out, items)
    for _, item in ipairs(items or {}) do
        if type(item) == "table" and not item.isTitle and type(item.text) == "string"
            and (type(item.func) == "function" or item.disabled) then
            out[#out+1] = {id=item.nexusId, text=Plain(item.text), action=not item.disabled and item.func or nil,
                checked=item.checked == true, disabled=item.disabled == true,
                detail=Plain(item.tooltipText or "")}
        end
    end
end

-- The rows under one Options menu section, chosen by the section's stable
-- identity (Panel's nexusSection), never by its shown, possibly translated,
-- title.
local function MoreSection(section)
    local panel = Nexus.Panel
    if not (panel and type(panel.MoreMenuItems) == "function") then return {} end
    local out, current = {}, nil
    for _, item in ipairs(panel.MoreMenuItems()) do
        if item.isTitle then current = item.nexusSection
        elseif current == section then AddMenuRows(out, {item}) end
    end
    return out
end

local function Route(label, fn, detail)
    return {text=label, action=fn, detail=detail or ""}
end

function M.Categories()
    local ids = {}
    for _, entry in ipairs(categories) do ids[#ids+1] = entry.id end
    return ids
end

-- The shown words of a category (its stable id stays the identity).
local function CategoryLabel(entry) return T(entry.labelKey, entry.label) end
local function CategoryTab(entry)
    if entry.tab then return T(entry.tabKey, entry.tab) end
    return CategoryLabel(entry)
end
local function CategoryNote(entry) return T(entry.noteKey, entry.note) end
local SYNC_MODE_KEYS = {automatic="settings.value.sync_automatic", manual="settings.value.sync_manual",
    off="settings.value.sync_off"}

-- A fresh, read-only model. No callback is invoked while it is assembled.
function M.Rows(category)
    local out, panel = {}, Nexus.Panel
    local identity = function(fn) return fn end
    if category == "automation" then
        if panel and type(panel.AutomationMenuItems) == "function" then
            AddMenuRows(out, panel.AutomationMenuItems(identity))
        end
    elseif category == "sync" then
        local policy = Nexus.SyncModePolicy
        local mode = policy and type(policy.Mode) == "function" and policy.Mode() or "unknown"
        local names = {automatic="Automatic", manual="Manual", off="Off"}
        local modeName = names[mode] and T(SYNC_MODE_KEYS[mode], names[mode])
            or T("settings.value.sync_unknown", "Unknown")
        local english = "Current Sync: " .. (names[mode] or "Unknown")
        -- The detail is the mode owner's display sentence (DisplayText where
        -- provided; Text stays raw English for code that compares it).
        local display = policy and (type(policy.DisplayText) == "function" and policy.DisplayText or policy.Text)
        out[#out+1] = {text=TF("settings.label.current_sync", {mode=modeName}, english), disabled=true,
            detail=type(display) == "function" and display(mode) or ""}
        out[#out+1] = Route(T("settings.button.open_library_sync", "Open Build Library / Sync choices"), function()
            if Nexus.CommunityBuilds and type(Nexus.CommunityBuilds.Show) == "function" then
                Nexus.CommunityBuilds.Show()
            end
        end, T("settings.note.library_sync_dialog", "The library's own Sync dialog asks before applying a choice."))
    elseif category == "appearance" then
        local theme = Nexus.Theme
        if theme and type(theme.MenuItems) == "function" then AddMenuRows(out, theme.MenuItems()) end
    elseif category == "language" then
        if panel and type(panel.LanguageMenuItems) == "function" then
            AddMenuRows(out, panel.LanguageMenuItems(identity))
        end
    elseif category == "display" then
        -- The two local HUD choices, by their stable row identities.
        for _, item in ipairs(MoreSection("settings")) do
            if item.id == "dps_records" or item.id == "hud_mode" then
                out[#out+1] = item
            end
        end
    elseif category == "notices" then
        out = MoreSection("notices")
    elseif category == "support" then
        out[#out+1] = Route(T("settings.button.guided_setup", "Guided setup"), function()
            if Nexus.Help and Nexus.Help.OpenGuide then Nexus.Help.OpenGuide() end
        end, T("settings.note.guided_setup", "Opens or resumes the step-by-step coach; it never enables Auto by navigation."))
        out[#out+1] = Route(T("settings.button.welcome_information", "Welcome information"), function()
            if Nexus.QuickStart and Nexus.QuickStart.ShowSetup then Nexus.QuickStart.ShowSetup() end
        end, T("settings.note.welcome_information", "Secondary information-only Welcome; the guided coach is the separate row above."))
        out[#out+1] = Route(T("settings.button.support_report", "Support report"), function()
            if Nexus.SupportReportUI and Nexus.SupportReportUI.Show then Nexus.SupportReportUI.Show() end
        end)
        out[#out+1] = Route(T("settings.button.log_viewer", "Log viewer"), function()
            if Nexus.LogViewer and Nexus.LogViewer.Show then Nexus.LogViewer.Show() end
        end)
    end
    if #out == 0 then
        out[1] = {text=T("settings.status.not_available", "This setting is not available yet."), disabled=true}
    end
    return out
end

-- Re-read at click time; a row that changed while the window was open is
-- refreshed rather than accidentally invoking the next option in its slot.
function M.Activate(index, expectedText)
    local row = M.Rows(selected)[index]
    if not row or not row.action or (expectedText and row.text ~= expectedText) then
        M.Refresh()
        return false
    end
    row.action()
    M.Refresh()
    return true
end

local function StyledButton(parent, text, width, height, point, x, y)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetPoint(point, x, y)
    button:SetText(text)
    if Nexus.Theme and Nexus.Theme.StyleButton then Nexus.Theme.StyleButton(button, true) end
    return button
end

local function ShowRowTooltip(button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:AddLine(button._nexusFullText or "", 1, 1, 1, true)
    if button._nexusFullDetail and button._nexusFullDetail ~= "" then
        GameTooltip:AddLine(button._nexusFullDetail, 0.85, 0.85, 0.85, true)
    end
    GameTooltip:Show()
end

local function EnsureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "NexusSettingsWindow", UIParent)
    frame:SetSize(396, 548)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()
    if Nexus.Theme and Nexus.Theme.StyleWindow then Nexus.Theme.StyleWindow(frame, 0.96) end
    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -17)
    title:SetText(T("settings.title.window", "Nexus Options"))
    if Nexus.Theme and Nexus.Theme.StyleLabel then Nexus.Theme.StyleLabel(title, "accent") end
    local close = StyledButton(frame, "X", 30, 25, "TOPRIGHT", -12, -10)
    close:SetScript("OnClick", function() M.Hide() end)
    for index, entry in ipairs(categories) do
        local column, row = (index-1)%3, math.floor((index-1)/3)
        local button = StyledButton(frame, CategoryLabel(entry), 118, 29, "TOPLEFT",
            16 + column*124, -54 - row*33)
        button:SetScript("OnClick", function() M.Select(entry.id) end)
        button:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(CategoryLabel(entry), 1, 1, 1, true)
            GameTooltip:AddLine(CategoryNote(entry), 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        categoryButtons[index] = button
    end
    explanation = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    explanation:SetPoint("TOPLEFT", 18, -163)
    explanation:SetWidth(360)
    explanation:SetHeight(54)
    explanation:SetJustifyH("LEFT")
    explanation:SetJustifyV("TOP")
    if explanation.SetWordWrap then explanation:SetWordWrap(true) end
    if Nexus.Theme and Nexus.Theme.StyleLabel then Nexus.Theme.StyleLabel(explanation, "muted") end
    for index=1,PAGE_SIZE do
        local y = -223 - (index-1)*94
        local button = StyledButton(frame, "", 358, 54, "TOPLEFT", 18, y)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", button, "LEFT", 11, 0)
        label:SetWidth(334)
        label:SetHeight(50)
        label:SetJustifyH("LEFT")
        label:SetJustifyV("MIDDLE")
        if label.SetWordWrap then label:SetWordWrap(true) end
        if Nexus.Theme and Nexus.Theme.StyleLabel then Nexus.Theme.StyleLabel(label, "text") end
        button._nexusFullLabel = label
        button:SetScript("OnEnter", ShowRowTooltip)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        local detail = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        detail:SetPoint("TOPLEFT", 22, y-56)
        detail:SetWidth(346)
        detail:SetHeight(34)
        detail:SetJustifyH("LEFT")
        if detail.SetWordWrap then detail:SetWordWrap(true) end
        if Nexus.Theme and Nexus.Theme.StyleLabel then Nexus.Theme.StyleLabel(detail, "muted") end
        button._nexusDetail = detail
        -- Disabled stock buttons may not deliver OnEnter. This independent
        -- overlay makes their full informational text inspectable on hover.
        local infoHover = CreateFrame("Frame", nil, frame)
        infoHover:SetAllPoints(button)
        infoHover:EnableMouse(true)
        infoHover:SetScript("OnEnter", function() ShowRowTooltip(button) end)
        infoHover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        infoHover:Hide()
        button._nexusInfoHover = infoHover
        rowButtons[index] = {button=button, detail=detail, infoHover=infoHover}
    end
    previous = StyledButton(frame, T("settings.button.previous", "Previous"), 92, 25, "BOTTOMLEFT", 16, 13)
    previous:SetScript("OnClick", function() page=math.max(1,page-1);M.Refresh() end)
    pageLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pageLabel:SetPoint("BOTTOM", 0, 20)
    nextPage = StyledButton(frame, T("settings.button.next", "Next"), 92, 25, "BOTTOMRIGHT", -16, 13)
    nextPage:SetScript("OnClick", function() page=page+1;M.Refresh() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "NexusSettingsWindow") end
    return frame
end

function M.Refresh()
    if not frame then return end
    local entry = byId[selected]
    local rows = M.Rows(selected)
    local pages = math.max(1, math.ceil(#rows/PAGE_SIZE))
    page = math.max(1, math.min(page, pages))
    title:SetText(T("settings.title.window", "Nexus Options"))
    explanation:SetText(CategoryNote(entry))
    for index, button in ipairs(categoryButtons) do
        button:SetText(CategoryTab(categories[index]))
        if categories[index].id == selected then
            if button.LockHighlight then button:LockHighlight() end
        elseif button.UnlockHighlight then button:UnlockHighlight() end
    end
    for slot, widget in ipairs(rowButtons) do
        local index = (page-1)*PAGE_SIZE + slot
        local row = rows[index]
        if row then
            local label = (row.checked and "[x] " or "") .. row.text
            widget.button._nexusFullText = label
            widget.button._nexusFullDetail = row.detail or ""
            -- The rendered label is bounded to the two-line action area;
            -- the complete original text remains available on hover.
            widget.button._nexusFullLabel:SetText(#label > 100
                and T("settings.label.long_setting", "Long setting — hover for full label") or label)
            widget.button:SetScript("OnClick", function() M.Activate(index, row.text) end)
            if row.action then
                widget.button:Enable();widget.infoHover:Hide()
            else
                widget.button:Disable();widget.infoHover:Show()
            end
            widget.detail:SetText(#(row.detail or "") > 56
                and T("settings.note.hover_explanation", "Hover for the full explanation.") or (row.detail or ""))
            widget.button:Show();widget.detail:Show()
        else
            widget.button:Hide();widget.detail:Hide();widget.infoHover:Hide()
        end
    end
    if page > 1 then previous:Enable() else previous:Disable() end
    if page < pages then nextPage:Enable() else nextPage:Disable() end
    pageLabel:SetText(page .. " / " .. pages)
    if Nexus.Theme and Nexus.Theme.Refresh then Nexus.Theme.Refresh() end
end

function M.Select(category)
    if not byId[category] then return false end
    selected, page = category, 1
    M.Refresh()
    return true
end

function M.Show(category)
    EnsureFrame()
    if category and not M.Select(category) then M.Select("automation") end
    if not category then M.Refresh() end
    -- 396px wide is intentionally usable at a 420px viewport. Larger screens
    -- keep the same readable width; smaller ones use the shared fit helper.
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.FitToScreen then
        Nexus.LayoutMetrics.FitToScreen(frame, 20)
    end
    -- The guided setup coach (ui/GuidedSetup.lua) is a dialog of this
    -- window's strata and level, so the two would draw through each other.
    -- It gives way through its own raw hide (GuidedSetupUI.Hide): that
    -- records no first use and keeps its first-use callback, so only its
    -- deliberate Close still acknowledges first use, and first use is
    -- offered again as for any other hide. Display only.
    local coach, coachFrame = Nexus.GuidedSetupUI, _G.NexusGuidedSetup
    if coach and type(coach.Hide) == "function" and coachFrame and coachFrame.IsShown and coachFrame:IsShown() then
        pcall(coach.Hide)
    end
    frame:Show()
    return true
end

-- The Options menu can ask for a section without depending on window internals.
function M.ShowSection(category) return M.Show(category) end

function M.Hide() if frame then frame:Hide() end end
function M.IsShown() return frame and frame:IsShown() or false end
