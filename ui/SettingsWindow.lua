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
local categories = {
    {id="automation", label="Automation", note="Changing a permission uses Nexus's existing controls. Opening this page never starts Auto or spends Orbs."},
    {id="sync", label="Share & Sync", tab="Sync", note="The library's Sync choices and Share use their existing explicit controls."},
    {id="appearance", label="Appearance", note="Style and colour change only how Nexus windows look; they do not change gameplay."},
    {id="language", label="Language", note="A language choice applies after reload or login. Some text remains English in this build."},
    {id="display", label="Display", note="Display choices affect the local HUD. Server Difficulty is available only when detected."},
    {id="notices", label="Notices", note="Choose which update notices to show; this does not install or download an update."},
    {id="support", label="Help & Support", tab="Support", note="These views read information. Preparing a report remains a separate action inside Support."},
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
            out[#out+1] = {text=Plain(item.text), action=not item.disabled and item.func or nil,
                checked=item.checked == true, disabled=item.disabled == true,
                detail=Plain(item.tooltipText or "")}
        end
    end
end

local function MoreSection(section)
    local panel = Nexus.Panel
    if not (panel and type(panel.MoreMenuItems) == "function") then return {} end
    local out, current = {}, nil
    for _, item in ipairs(panel.MoreMenuItems()) do
        if item.isTitle then current = item.text
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
        out[#out+1] = {text="Current Sync: " .. (names[mode] or "Unknown"), disabled=true,
            detail=policy and type(policy.Text) == "function" and policy.Text(mode) or ""}
        out[#out+1] = Route("Open Build Library / Sync choices", function()
            if Nexus.CommunityBuilds and type(Nexus.CommunityBuilds.Show) == "function" then
                Nexus.CommunityBuilds.Show()
            end
        end, "The library's own Sync dialog asks before applying a choice.")
    elseif category == "appearance" then
        local theme = Nexus.Theme
        if theme and type(theme.MenuItems) == "function" then AddMenuRows(out, theme.MenuItems()) end
    elseif category == "language" then
        if panel and type(panel.LanguageMenuItems) == "function" then
            AddMenuRows(out, panel.LanguageMenuItems(identity))
        end
    elseif category == "display" then
        for _, item in ipairs(MoreSection("Settings")) do
            if item.text:find("DPS records", 1, true)
                or item.text:find("Difficulty / Soul Ash HUD", 1, true) then
                out[#out+1] = item
            end
        end
    elseif category == "notices" then
        out = MoreSection("Notices")
    elseif category == "support" then
        out[#out+1] = Route("Guided setup", function()
            if Nexus.Help and Nexus.Help.OpenGuide then Nexus.Help.OpenGuide() end
        end, "Opens or resumes the step-by-step coach; it never enables Auto by navigation.")
        out[#out+1] = Route("Welcome information", function()
            if Nexus.QuickStart and Nexus.QuickStart.ShowSetup then Nexus.QuickStart.ShowSetup() end
        end, "Secondary information-only Welcome; the guided coach is the separate row above.")
        out[#out+1] = Route("Support report", function()
            if Nexus.SupportReportUI and Nexus.SupportReportUI.Show then Nexus.SupportReportUI.Show() end
        end)
        out[#out+1] = Route("Log viewer", function()
            if Nexus.LogViewer and Nexus.LogViewer.Show then Nexus.LogViewer.Show() end
        end)
    end
    if #out == 0 then out[1] = {text="This setting is not available yet.", disabled=true} end
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
    title:SetText("Nexus Settings")
    if Nexus.Theme and Nexus.Theme.StyleLabel then Nexus.Theme.StyleLabel(title, "accent") end
    local close = StyledButton(frame, "X", 30, 25, "TOPRIGHT", -12, -10)
    close:SetScript("OnClick", function() M.Hide() end)
    for index, entry in ipairs(categories) do
        local column, row = (index-1)%3, math.floor((index-1)/3)
        local button = StyledButton(frame, entry.label, 118, 29, "TOPLEFT",
            16 + column*124, -54 - row*33)
        button:SetScript("OnClick", function() M.Select(entry.id) end)
        button:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(entry.label, 1, 1, 1, true)
            GameTooltip:AddLine(entry.note, 0.85, 0.85, 0.85, true)
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
    previous = StyledButton(frame, "Previous", 92, 25, "BOTTOMLEFT", 16, 13)
    previous:SetScript("OnClick", function() page=math.max(1,page-1);M.Refresh() end)
    pageLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pageLabel:SetPoint("BOTTOM", 0, 20)
    nextPage = StyledButton(frame, "Next", 92, 25, "BOTTOMRIGHT", -16, 13)
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
    title:SetText("Nexus Settings")
    explanation:SetText(entry.note)
    for index, button in ipairs(categoryButtons) do
        button:SetText(categories[index].tab or categories[index].label)
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
                and "Long setting — hover for full label" or label)
            widget.button:SetScript("OnClick", function() M.Activate(index, row.text) end)
            if row.action then
                widget.button:Enable();widget.infoHover:Hide()
            else
                widget.button:Disable();widget.infoHover:Show()
            end
            widget.detail:SetText(#(row.detail or "") > 56
                and "Hover for the full explanation." or (row.detail or ""))
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
    frame:Show()
    return true
end

-- The Options menu can ask for a section without depending on window internals.
function M.ShowSection(category) return M.Show(category) end

function M.Hide() if frame then frame:Hide() end end
function M.IsShown() return frame and frame:IsShown() or false end
