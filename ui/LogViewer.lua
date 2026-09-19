-- Nexus: ui/LogViewer.lua
-- The data-handoff window: /nexus log opens a tabbed, copy-friendly text
-- view of everything the addon knows -- recorded boards, manual-vs-
-- proposal mismatches, the parsed wishlist, and live state. Dumb view:
-- Main supplies a provider function(tabKey) -> text; this file only
-- renders. Select All + Ctrl-C is the intended workflow.

Nexus = Nexus or {}
local M = {}
Nexus.LogViewer = M

local TABS = {
    { key = "boards",   label = "Recent choices" },
    { key = "mismatch", label = "Manual overrides" },
    { key = "wishlist", label = "Wishlist" },
    { key = "locked",   label = "Permanent Echoes" },
    { key = "state",    label = "Status" },
    { key = "sync",     label = "Sync" },
    { key = "dps",      label = "DPS" },
    { key = "autolock", label = "Slot actions" },
    { key = "perf",     label = "Performance" },
    { key = "errors",   label = "Errors" },
    { key = "peer",     label = "Advanced peer" },
}

local frame, editBox, scroll, tabButtons, statusFS, exportButton
local peerLabel, peerEdit, peerStart, peerStop
local repaintRunner, exportRunner, exportFinisher, clearResetRunner
local exportJob, exportGeneration = nil, 0
local provider, clearProvider
local activeTab = "state"
local repaintPending = false
local clearResetButton, clearResetGeneration = nil, 0
local peerRefreshElapsed, peerRefreshActive = 0, false
local MAX_TEXT_CHARS = 60000
local COPY_PAGE_BYTES = 16000
local copyText, copyPage, copyPages = "", 1, 1
local copyRanges={{1,0}}
local pagePrevious, pageNext

local function InertCopyText(value, maxBytes)
    value = tostring(value or "")
    local displayText = Nexus and Nexus.Identity
        and Nexus.Identity.DisplaySafeText
    return displayText and displayText(
        value, tonumber(maxBytes) or #value, true, true) or ""
end

local function RenderCopyPage()
    if not editBox then return end
    local range=copyRanges[copyPage]
    local chunk = copyText:sub(range[1],range[2])
    editBox:SetText(InertCopyText(chunk,#chunk))
    editBox:SetCursorPosition(0)
    if pagePrevious then if copyPage>1 then pagePrevious:Enable() else pagePrevious:Disable() end end
    if pageNext then if copyPage<copyPages then pageNext:Enable() else pageNext:Disable() end end
    if statusFS then statusFS:SetText(string.format("Page %d/%d | %d total bytes | copy pages in order (no inserted separators)",copyPage,copyPages,#copyText)) end
end

local function SetCopyText(text)
    copyText=tostring(text or "")
    copyPage,copyRanges=1,{}
    local first=1
    while first<=#copyText do
        local last=math.min(#copyText,first+COPY_PAGE_BYTES-1)
        -- Do not split a multibyte character between individually validated
        -- pages. Escaping pipes is compositional, so concatenating pages is
        -- lossless and does not create executable rich-text sequences.
        while last<#copyText do
            local following=copyText:byte(last+1)
            if following<128 or following>=192 then break end
            last=last-1
            if last<first then last=math.min(#copyText,first+COPY_PAGE_BYTES-1);break end
        end
        copyRanges[#copyRanges+1]={first,last};first=last+1
    end
    if #copyRanges==0 then copyRanges={{1,0}} end
    copyPages=#copyRanges
    RenderCopyPage()
end

function M.PageInfo()
    return {page=copyPage,pages=copyPages,bytes=#copyText,pageBytes=COPY_PAGE_BYTES}
end
function M.SetPage(index)
    index=tonumber(index)
    if not index or index~=math.floor(index) or index<1 or index>copyPages then return false end
    copyPage=index;RenderCopyPage();return true
end

local function SyncPeerRefreshState()
    peerRefreshElapsed, peerRefreshActive = 0, false
    if activeTab ~= "peer" then return false end
    local debugOwner = Nexus and Nexus.PeerDebug
    if not (debugOwner and type(debugOwner.IsEnabled) == "function") then
        return false
    end
    local ok, active = pcall(debugOwner.IsEnabled)
    peerRefreshActive = ok and active == true
    return peerRefreshActive
end

local function UpdatePeerControls()
    local shown = activeTab == "peer"
    for _, control in ipairs({peerLabel,peerEdit,peerStart,peerStop}) do
        if control then
            if shown then control:Show() else control:Hide() end
        end
    end
end

local function Repaint()
    repaintPending = false
    if not (frame and editBox and frame:IsShown()) then return end
    local text = "no data provider"
    if type(provider) == "function" then
        local ok, result = pcall(provider, activeTab)
        text = ok and tostring(result or "") or ("provider error: " .. tostring(result))
    end
    -- Preserve the complete diagnostic. The visible EditBox is paged; no
    -- silent truncation and no hundreds-of-kilobytes SetText/focus operation.
    SetCopyText(text)
    for _, b in ipairs(tabButtons or {}) do
        if b.tabKey == activeTab then b:LockHighlight() else b:UnlockHighlight() end
    end
    UpdatePeerControls()
    if activeTab == "ai_export" and editBox then
        editBox:SetFocus()
        editBox:HighlightText()
    end
end

local function ScheduleRepaint()
    if repaintPending then return end
    repaintPending = true
    if not repaintRunner then
        repaintRunner = CreateFrame("Frame")
        repaintRunner:Hide()
    end
    local elapsed = 0
    repaintRunner:Show()
    repaintRunner:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + (tonumber(dt) or 0)
        if elapsed < 0.05 then return end
        self:SetScript("OnUpdate", nil)
        self:Hide()
        Repaint()
    end)
end

local function StopExport()
    exportGeneration = exportGeneration + 1
    exportJob = nil
    if exportRunner then
        exportRunner:SetScript("OnUpdate", nil)
        exportRunner:Hide()
    end
    if exportFinisher then
        exportFinisher:SetScript("OnUpdate", nil)
        exportFinisher:Hide()
    end
end

local function FinishExport(text)
    exportJob = nil
    if exportRunner then exportRunner:SetScript("OnUpdate", nil); exportRunner:Hide() end
    SetCopyText(text)
    editBox:SetFocus()
    editBox:HighlightText()
end

local function StartExport()
    StopExport()
    activeTab = "ai_export"
    for _, b in ipairs(tabButtons or {}) do b:UnlockHighlight() end
    editBox:SetText("Preparing the diagnostic report in steps.\n\nLarge reports may take a moment. You can cancel preparation.")
    statusFS:SetText("Preparing export...")
    local factory = Nexus and Nexus.NewAIExportCoroutine
    if type(factory) ~= "function" then
        editBox:SetText("Diagnostic export builder is unavailable.")
        return
    end
    local ok, job = pcall(factory)
    if not ok or type(job) ~= "thread" then
        editBox:SetText("Could not start diagnostic export: " .. tostring(job))
        return
    end
    exportJob = job
    exportGeneration = exportGeneration + 1
    local myGeneration = exportGeneration
    if not exportRunner then exportRunner = CreateFrame("Frame") end
    exportRunner:Show()
    local updateElapsed = 0
    exportRunner:SetScript("OnUpdate", function(self, elapsed)
        if myGeneration ~= exportGeneration or not exportJob then self:SetScript("OnUpdate", nil); self:Hide(); return end
        updateElapsed = updateElapsed + (tonumber(elapsed) or 0)
        -- Exactly one small coroutine slice per rendered frame. Each slice
        -- encodes only a handful of boards/audits, keeping frame time bounded
        -- even on low-end clients while combat or sync traffic is active.
        for _ = 1, 1 do
            local okResume, value = coroutine.resume(exportJob)
            if not okResume then
                exportJob = nil
                self:SetScript("OnUpdate", nil); self:Hide()
                editBox:SetText("Diagnostic export failed: " .. tostring(value))
                statusFS:SetText("export failed")
                return
            end
            if coroutine.status(exportJob) == "dead" then
                exportJob = nil
                self:SetScript("OnUpdate", nil)
                self:Hide()
                local finalText = value
                if not exportFinisher then
                    exportFinisher = CreateFrame("Frame")
                    exportFinisher:Hide()
                end
                local waited = false
                exportFinisher:Show()
                exportFinisher:SetScript("OnUpdate", function(f)
                    if not waited then waited = true; return end
                    f:SetScript("OnUpdate", nil)
                    f:Hide()
                    if myGeneration ~= exportGeneration then return end
                    FinishExport(finalText)
                    finalText = nil
                end)
                return
            end
            if updateElapsed >= 0.12 then
                statusFS:SetText(tostring(value or "Building full diagnostic log...") .. " -- large reports may take a moment")
                updateElapsed = 0
            end
        end
    end)
end

local function EnsureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "NexusLogViewer", UIParent)
    frame:SetClampedToScreen(true)
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "NexusLogViewer")
    end
    frame:SetSize(700, 440)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetFrameStrata("DIALOG")
    frame:SetScript("OnHide", function()
        StopExport()
        repaintPending = false
        if repaintRunner then
            repaintRunner:SetScript("OnUpdate", nil)
            repaintRunner:Hide()
        end
        clearResetGeneration = clearResetGeneration + 1
        if clearResetRunner then
            clearResetRunner:SetScript("OnUpdate", nil)
            clearResetRunner:Hide()
        end
        if clearResetButton then
            clearResetButton:SetText("Clear Log")
            clearResetButton = nil
        end
    end)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.92)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
    title:SetText("Nexus -- data log")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    tabButtons = {}
    local prev
    for i, tab in ipairs(TABS) do
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(math.max(56, #tab.label * 6 + 18), 22)
        if i == 6 then
            b:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -56)
        elseif prev then
            b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else
            b:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30)
        end
        b:SetText(tab.label)
        b.tabKey = tab.key
        b:SetScript("OnClick", function(self)
            StopExport()
            activeTab = self.tabKey
            SyncPeerRefreshState()
            ScheduleRepaint()
        end)
        tabButtons[i] = b
        prev = b
    end

    local selectAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    selectAll:SetSize(116, 22)
    selectAll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -82)
    selectAll:SetText("Select this page")
    selectAll:SetScript("OnClick", function()
        if editBox then
            editBox:SetFocus()
            editBox:HighlightText()
        end
    end)

    local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refresh:SetSize(70, 22)
    refresh:SetPoint("RIGHT", selectAll, "LEFT", -4, 0)
    refresh:SetText("Refresh")
    refresh:SetScript("OnClick", function()
        if activeTab == "ai_export" then StartExport() else ScheduleRepaint() end
    end)

    pagePrevious=CreateFrame("Button", "NexusLogPreviousPage", frame, "UIPanelButtonTemplate")
    pagePrevious:SetSize(48,22)
    pagePrevious:SetPoint("RIGHT",refresh,"LEFT",-4,0)
    pagePrevious:SetText("< Page")
    pagePrevious:SetScript("OnClick",function() M.SetPage(copyPage-1) end)
    pageNext=CreateFrame("Button", "NexusLogNextPage", frame, "UIPanelButtonTemplate")
    pageNext:SetSize(48,22)
    pageNext:SetPoint("RIGHT",pagePrevious,"LEFT",-4,0)
    pageNext:SetText("Page >")
    pageNext:SetScript("OnClick",function() M.SetPage(copyPage+1) end)

    peerLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    peerLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 42)
    peerLabel:SetText("Peer event filter (optional)")

    peerEdit = CreateFrame("EditBox", "NexusPeerTestTarget", frame,
        "InputBoxTemplate")
    peerEdit:SetSize(118, 22)
    peerEdit:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 150, 36)
    peerEdit:SetAutoFocus(false)
    peerEdit:SetMaxLetters(40)
    peerEdit:SetText("")

    peerStart = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    peerStart:SetSize(62, 22)
    peerStart:SetPoint("LEFT", peerEdit, "RIGHT", 4, 0)
    peerStart:SetText("Start")
    peerStart:SetScript("OnClick", function()
        local debugOwner = Nexus and Nexus.PeerDebug
        if debugOwner and type(debugOwner.Start) == "function" then
            local ok, started = pcall(debugOwner.Start, peerEdit:GetText())
            peerRefreshActive = ok and started ~= false
            peerRefreshElapsed = 0
        end
        ScheduleRepaint()
    end)

    peerStop = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    peerStop:SetSize(62, 22)
    peerStop:SetPoint("LEFT", peerStart, "RIGHT", 4, 0)
    peerStop:SetText("Stop")
    peerStop:SetScript("OnClick", function()
        local debugOwner = Nexus and Nexus.PeerDebug
        if debugOwner and type(debugOwner.Stop) == "function" then
            pcall(debugOwner.Stop)
        end
        peerRefreshActive, peerRefreshElapsed = false, 0
        ScheduleRepaint()
    end)
    UpdatePeerControls()

    exportButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportButton:SetSize(220, 22)
    exportButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 7)
    exportButton:SetText("Prepare full diagnostic report")
    exportButton:SetScript("OnClick", StartExport)
    exportButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Prepare the retained diagnostic report")
        GameTooltip:AddLine("The report is displayed in pages. Use Select this page and Ctrl-C, then copy each page in order without adding separators. Normal tabs show shorter views.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    exportButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearButton:SetSize(86, 22)
    clearButton:SetPoint("RIGHT", exportButton, "LEFT", -6, 0)
    clearButton:SetText("Clear Log")
    clearButton:SetScript("OnClick", function(self)
        StopExport()
        local errorsOnly = activeTab == "errors"
        local ok, result = false, nil
        if type(clearProvider) == "function" then
            ok, result = pcall(clearProvider, activeTab)
        end
        if activeTab ~= "errors" and activeTab ~= "peer" then
            activeTab = "state"
        end
        if ok and result ~= false then
            self:SetText("Cleared")
            if statusFS then
                statusFS:SetText(errorsOnly and "Error history cleared"
                    or "Diagnostic history cleared")
            end
        else
            self:SetText("Clear Failed")
            if statusFS then statusFS:SetText("Could not clear diagnostic history") end
        end
        ScheduleRepaint()
        clearResetGeneration = clearResetGeneration + 1
        local myResetGeneration = clearResetGeneration
        clearResetButton = self
        if not clearResetRunner then
            clearResetRunner = CreateFrame("Frame")
            clearResetRunner:Hide()
        end
        local elapsed = 0
        clearResetRunner:Show()
        clearResetRunner:SetScript("OnUpdate", function(f, dt)
            elapsed = elapsed + (tonumber(dt) or 0)
            if elapsed < 1.2 then return end
            f:SetScript("OnUpdate", nil)
            f:Hide()
            if myResetGeneration ~= clearResetGeneration then return end
            if self then self:SetText("Clear Log") end
            clearResetButton = nil
        end)
    end)
    clearButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Clear diagnostic history")
        GameTooltip:AddLine("On Errors, clears only retained errors. On Advanced peer diagnostics, clears only that session. Other tabs clear retained boards, audits, UI probes, sync events, DPS debug lines, and errors. Settings, builds, and automation are unchanged.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    clearButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    scroll = CreateFrame("ScrollFrame", "NexusLogScroll", frame,
        "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -112)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 64)

    editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetMaxLetters(0)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(646)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- read-only in spirit: typing is harmless (nothing reads it back),
    -- but keep the text restorable via Refresh
    scroll:SetScrollChild(editBox)

    statusFS = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusFS:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 10)
    statusFS:SetJustifyH("LEFT")

    -- Active Peer Test age/counters repaint once per second only while this
    -- visible tab is selected. Hidden, stopped, and disabled diagnostics do
    -- no recurring provider work.
    frame:SetScript("OnUpdate", function(self, elapsed)
        if not self:IsShown() or activeTab ~= "peer"
            or not peerRefreshActive then
            peerRefreshElapsed = 0
            return
        end
        peerRefreshElapsed = peerRefreshElapsed + (tonumber(elapsed) or 0)
        if peerRefreshElapsed < 1 then return end
        peerRefreshElapsed = 0
        local debugOwner = Nexus and Nexus.PeerDebug
        local ok, active = pcall(debugOwner.IsEnabled)
        if not ok or active ~= true then peerRefreshActive = false end
        Repaint()
    end)

    frame:Hide()
    return frame
end

function M.Init(providerFn, clearFn)
    if providerFn ~= nil then provider = providerFn end
    if clearFn ~= nil then clearProvider = clearFn end
end

function M.Show(tabKey)
    EnsureFrame()
    if Nexus.Panel and Nexus.Panel.AttachMenuFrame then Nexus.Panel.AttachMenuFrame(frame) end
    if Nexus.Theme and Nexus.Theme.StyleWindow then Nexus.Theme.StyleWindow(frame, 0.96) end
    if Nexus.Panel and Nexus.Panel.CloseOtherWindows then Nexus.Panel.CloseOtherWindows("NexusLogViewer") end
    if tabKey then activeTab = tabKey end
    SyncPeerRefreshState()
    frame:Show()
    if editBox then editBox:SetText("Loading " .. tostring(activeTab) .. " log...") end
    ScheduleRepaint()
end

function M.Toggle(tabKey)
    EnsureFrame()
    if frame:IsShown() then frame:Hide() else M.Show(tabKey) end
end
