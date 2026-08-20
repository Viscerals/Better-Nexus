-- Nexus: ui/Panel.lua v2.13
-- Adaptive main HUD. The panel changes shape for setup, active progress,
-- completed builds, and live Echo rolls instead of showing every section
-- at all times.

Nexus = Nexus or {}
local M = {}
Nexus.Panel = M

local frame, minimapBtn, callbacks
local panelWantedVisible = true
local menuSuppressed = false
local menuTransition = false
local attachedMenuFrames = {}
local missingNamesCache, shedNamesCache, unknownTomesCache, toLockNamesCache = {}, {}, {}, {}

local buildHeaderText, switchBtn, wishlistMenu
local rollArea, statusText, cardTexts, recText, rollDivider = nil, nil, {}, nil, nil
local progressLabel, progressValue, needLabel, needText, needHit
local tomesLabel, tomesValue, tomesHit
local shedLabel, shedText, shedHit
local performanceLabel, setLabelText
local dummyLabel, dummyValue, dummyGlobal, dummyGlobalValue, dummyHit
local lkLabel, lkPersonalLabel, lkValue, lkGlobal, lkGlobalValue, lkHit
local completeBadge, completeSubtext
local setupText, setupHint, setupGetStartedBtn, setupImportBtn
local autoBtn, buildsBtn, leaderboardBtn, menuBtn, versionText, worldStatusBox, worldStatusText, worldStatusAsh, worldStatusGain, worldStatusHit, bestDpsText, bestDpsHit
local showPerformance = false
local renderState = {
    committed=false,applying=false,signatures=nil,hadFailure=false,
}
local renderStats = {
    calls=0, layouts=0, skipped=0, statusOnly=0,
    performancePasses=0, noticePasses=0, themeTreeWalks=0,
    commits=0,failures=0,recoveries=0,recoveryRequests=0,
    hiddenUncommitted=0,
}

StaticPopupDialogs["NEXUS_UPDATE_RELEASES"] = {
    text = "Nexus %s was reported as available. Installation is manual. Copy the releases page below:",
    button1 = "Close",
    hasEditBox = true,
    editBoxWidth = 380,
    OnShow = function(self)
        local url = Nexus.Updates and Nexus.Updates.ReleaseUrl
            and Nexus.Updates.ReleaseUrl() or "https://github.com/Viscerals/Better-Nexus/releases"
        if self.editBox then
            self.editBox:SetText(url)
            self.editBox:HighlightText()
            self.editBox:SetFocus()
        end
    end,
    EditBoxOnEnterPressed = function(self) self:HighlightText() end,
    EditBoxOnEscapePressed = function(self) self:ClearFocus() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function SafeText(v) return v ~= nil and tostring(v) or "" end

local function DefensiveCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[DefensiveCopy(key, seen)] = DefensiveCopy(child, seen)
    end
    return out
end

local function Signature(value, seen)
    local kind = type(value)
    if kind ~= "table" then
        local text = SafeText(value)
        return kind .. ":" .. tostring(#text) .. ":" .. text
    end
    seen = seen or { _nextId=0 }
    if seen[value] then return "cycle:" .. tostring(seen[value]) end
    seen._nextId = seen._nextId + 1
    seen[value] = seen._nextId
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        return type(left) .. ":" .. tostring(left)
            < type(right) .. ":" .. tostring(right)
    end)
    local out = {"{"}
    for _, key in ipairs(keys) do
        out[#out + 1] = Signature(key, seen)
        out[#out + 1] = "="
        out[#out + 1] = Signature(value[key], seen)
        out[#out + 1] = ";"
    end
    out[#out + 1] = "}"
    return table.concat(out)
end

local function ModelSignatures(model)
    local source = type(model.progress) == "table" and model.progress or {}
    local layoutKey = "legacy"
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.RuntimeKey then
        local ok, key = pcall(Nexus.LayoutMetrics.RuntimeKey,"panel",272,0)
        if ok then layoutKey = key end
    end
    local progress = {
        wishlistName=source.wishlistName,
        owned=source.owned,
        total=source.total,
        missing=source.missing,
        shed=source.shed,
        unknownTomes=source.unknownTomes,
        toLock=source.toLock,
        activeSlot=source.activeSlot,
        isCommunityPreview=source.isCommunityPreview,
    }
    return {
        layout = Signature({
            progress=progress,
            cards=model.cards,
            recommendation=model.recommendation,
            level=model.level,
            serverStatus=model.serverStatus,
            showPerformance=showPerformance,
            layoutRevision=layoutKey,
        }),
        performance = Signature({
            performance=type(model.progress) == "table" and model.progress.performance or nil,
            bestDps=model.bestDps,
        }),
        notice = Signature(model.updateNotice),
        status = Signature(model.status),
        auto = Signature(model.auto),
    }
end

local function ShortName(v, maxChars)
    local s = SafeText(v)
    maxChars = maxChars or 30
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.Truncate then
        return Nexus.LayoutMetrics.Truncate(s, maxChars)
    end
    if #s <= maxChars then return s end
    return s:sub(1, math.max(1, maxChars - 3)) .. "..."
end

local function AutoLabel(auto)
    if auto == nil then return "Auto: --" end
    if auto then return "|cff2ee62eAuto: ON|r" end
    return "|cffe63c3cAuto: OFF|r"
end

local function FmtDps(dps)
    dps = tonumber(dps)
    if not dps or dps <= 0 then return "—" end
    if dps >= 1000000 then return string.format("%.2fM", dps / 1000000) end
    if dps >= 1000 then return string.format("%dk", math.floor(dps / 1000)) end
    return tostring(math.floor(dps))
end

local function HitFrame(parent, fs)
    local hit = CreateFrame("Frame", nil, parent)
    hit:SetAllPoints(fs)
    hit:EnableMouse(true)
    return hit
end

-- Split out of EnsureFrame() to keep that giant widget-builder function
-- under WoW 3.3.5's 60-upvalue-per-function limit. Stores the widgets as
-- fields on the frame itself (f.toLockLabel etc.) instead of new module
-- locals, so EnsureFrame only pays one upvalue (this function reference)
-- to wire them in, and M.Render/ShowCoreProgress read them off `frame`
-- (already a heavily-used upvalue there) instead of adding their own.
local function CreateToLockWidgets(f)
    local layout = Nexus.LayoutMetrics
    f.toLockLabel = f:CreateFontString(nil, "OVERLAY",
        layout and layout.FontObject("small") or "GameFontDisableSmall")
    f.toLockLabel:SetText("TO LOCK")
    f.toLockLabel:SetTextColor(0.7, 0.45, 1)
    f.toLockText = f:CreateFontString(nil, "OVERLAY",
        layout and layout.FontObject("small") or "GameFontHighlightSmall")
    f.toLockText:SetJustifyH("LEFT")
    f.toLockText:SetJustifyV("TOP")
    f.toLockText:SetTextColor(0.72, 0.45, 1)
    f.toLockHit = HitFrame(f, f.toLockText)
    f.toLockHit:SetScript("OnEnter", function(self)
        if #toLockNamesCache == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Locked-slot targets to acquire", 1, 1, 1)
        GameTooltip:AddLine("These are designed for one of your 6 locked slots.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("They still get rolled for like any other wished Echo,", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("but only need to be acquired ONCE -- once locked in,", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("they never need to be rolled again.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Still need to acquire:", 0.85, 0.6, 1)
        for i, name in ipairs(toLockNamesCache) do
            GameTooltip:AddLine("  • " .. name, 0.85, 0.7, 1)
            if i >= 25 then
                if #toLockNamesCache > 25 then
                    GameTooltip:AddLine("  +" .. (#toLockNamesCache - 25) .. " more", 0.6, 0.6, 0.6)
                end
                break
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to open Wishlist Editor", 0.4, 0.8, 1)
        GameTooltip:Show()
    end)
    f.toLockHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.toLockHit:SetScript("OnMouseUp", function() if Nexus.WishlistEditor then Nexus.WishlistEditor.Show() end end)
end

local function SetVisible(widget, shown)
    if not widget then return end
    if shown then widget:Show() else widget:Hide() end
end

local function SetPoint(widget, point, relative, relativePoint, x, y)
    widget:ClearAllPoints()
    widget:SetPoint(point, relative or frame, relativePoint or point, x or 0, y or 0)
end

local function SetOwnedFont(widget, font)
    if widget and type(widget.SetFontObject) == "function" then
        pcall(widget.SetFontObject, widget, font)
    end
end

local function SetOwnedButtonFont(widget, font)
    if not widget then return end
    if type(widget.SetNormalFontObject) == "function" then
        pcall(widget.SetNormalFontObject, widget, font)
    end
    if type(widget.SetHighlightFontObject) == "function" then
        pcall(widget.SetHighlightFontObject, widget, font)
    end
    if type(widget.SetDisabledFontObject) == "function" then
        pcall(widget.SetDisabledFontObject, widget, font)
    end
end

function M.ApplyOwnedFonts()
    local layout = Nexus.LayoutMetrics
    if not (layout and frame) then return false end
    local small = layout.FontObject("small")
    local normal = layout.FontObject("normal")
    local large = layout.FontObject("large")
    if not frame._nexusOwnedFonts then
        frame._nexusOwnedFonts = true
        for _, widget in ipairs({
            statusText,recText,progressLabel,needLabel,needText,tomesLabel,
            tomesValue,shedLabel,shedText,performanceLabel,setLabelText,
            dummyLabel,dummyGlobal,lkLabel,lkPersonalLabel,lkGlobal,
            completeSubtext,setupHint,bestDpsText,versionText,
            worldStatusGain,worldStatusBox and worldStatusBox.intensityText,
        }) do SetOwnedFont(widget, small) end
        for _, widget in ipairs(cardTexts) do SetOwnedFont(widget, small) end
        for _, widget in ipairs({
            buildHeaderText,worldStatusText,worldStatusAsh,progressValue,
            dummyValue,dummyGlobalValue,lkValue,lkGlobalValue,completeBadge,
        }) do SetOwnedFont(widget, normal) end
        SetOwnedFont(setupText, large)
        for _, widget in ipairs({
            switchBtn,setupGetStartedBtn,setupImportBtn,autoBtn,buildsBtn,
            leaderboardBtn,menuBtn,
        }) do SetOwnedButtonFont(widget, normal) end
    end
    if frame.toLockLabel and not frame.toLockLabel._nexusOwnedFont then
        SetOwnedFont(frame.toLockLabel, small)
        SetOwnedFont(frame.toLockText, small)
        frame.toLockLabel._nexusOwnedFont = true
    end
    return true
end

local function AddDpsTooltip(widget, title, personal, global)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, 1, 1, 1)
        if personal then
            GameTooltip:AddLine("Your best: " .. FmtDps(personal.dps), 0.35, 1, 0.45)
            if personal.duration then GameTooltip:AddLine("Duration: " .. tostring(personal.duration) .. "s", 0.75, 0.75, 0.75) end
        else
            GameTooltip:AddLine("No personal record for this exact loadout.", 0.65, 0.65, 0.65, true)
        end
        if global then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Global best: " .. FmtDps(global.dps), 1, 0.82, 0)
            GameTooltip:AddLine("Held by " .. tostring(global.player or "Unknown"), 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Records only match identical Echo IDs and stack quantities.", 0.45, 0.75, 1, true)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function CloseOtherNexusWindows(exceptName)
    local names = {
        "NexusCommunityBuildsFrame", "NexusLeaderboardFrame", "NexusEditorFrame",
        "NexusLogViewer", "NexusQuickStart", "NexusChangelogPopup",
        "ProjectEbonholdEchoJournal",
    }
    for i = 1, #names do
        local f = _G[names[i]]
        if names[i] ~= exceptName and f and f.Hide then pcall(f.Hide, f) end
    end
    if _G.DropDownList1 and _G.DropDownList1.Hide then pcall(_G.DropDownList1.Hide, _G.DropDownList1) end
    if _G.DropDownList2 and _G.DropDownList2.Hide then pcall(_G.DropDownList2.Hide, _G.DropDownList2) end
end

local function AnyNexusMenuShown()
    local names = {
        "NexusCommunityBuildsFrame", "NexusLeaderboardFrame", "NexusEditorFrame",
        "NexusLogViewer", "NexusQuickStart", "NexusChangelogPopup",
    }
    for i = 1, #names do
        local f = _G[names[i]]
        if f and f.IsShown and f:IsShown() then return true end
    end
    return false
end

local function ApplyWantedVisibility()
    if not frame then return false end
    if panelWantedVisible and not menuSuppressed
        and renderState.committed and not renderState.applying then
        frame:Show()
        return true
    end
    if panelWantedVisible and not menuSuppressed and not renderState.committed then
        renderStats.hiddenUncommitted = renderStats.hiddenUncommitted + 1
    end
    frame:Hide()
    return false
end

local function RequestDisplayRecovery()
    if renderState.committed or not panelWantedVisible or not callbacks
        then
        return false
    end
    local request = type(callbacks.RequestFirstDisplay) == "function"
        and callbacks.RequestFirstDisplay or callbacks.RefreshDisplay
    if type(request) ~= "function" then return false end
    renderStats.recoveryRequests = renderStats.recoveryRequests + 1
    local ok, result = pcall(request)
    return ok and result ~= false
end

local function RestoreHudAfterMenus()
    if menuTransition or AnyNexusMenuShown() then return end
    menuSuppressed = false
    RequestDisplayRecovery()
    ApplyWantedVisibility()
end

function M.AttachMenuFrame(menuFrame)
    if not menuFrame or attachedMenuFrames[menuFrame] then return end
    attachedMenuFrames[menuFrame] = true
    local oldShow = menuFrame:GetScript("OnShow")
    local oldHide = menuFrame:GetScript("OnHide")
    menuFrame:SetScript("OnShow", function(self, ...)
        if oldShow then oldShow(self, ...) end
        menuSuppressed = true
        if frame and frame:IsShown() then frame:Hide() end
    end)
    menuFrame:SetScript("OnHide", function(self, ...)
        if oldHide then oldHide(self, ...) end
        RestoreHudAfterMenus()
    end)
end

function M.CloseOtherWindows(exceptName)
    menuTransition = true
    menuSuppressed = true
    if frame then frame:Hide() end
    CloseOtherNexusWindows(exceptName)
    menuTransition = false
end

local function EnsureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "NexusPanel", UIParent)
    frame:SetSize(272, 210)
    frame:SetClampedToScreen(true)
    NexusDB = NexusDB or {}
    if tonumber(NexusDB.panelX) and tonumber(NexusDB.panelY) then
        frame:SetPoint("CENTER", UIParent, "CENTER", NexusDB.panelX, NexusDB.panelY)
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
    end
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if x and y and ux and uy then
            NexusDB.panelX, NexusDB.panelY = math.floor(x - ux + 0.5), math.floor(y - uy + 0.5)
        end
    end)
    frame:Hide()

    buildHeaderText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame._buildHeaderText = buildHeaderText
    buildHeaderText:SetPoint("TOP", 0, -8)
    buildHeaderText:SetSize(244, 17)
    buildHeaderText:SetJustifyH("CENTER")
    buildHeaderText:SetTextColor(0.45, 0.84, 1)

    switchBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame._switchBtn = switchBtn
    switchBtn:SetSize(90, 19)
    switchBtn:SetPoint("TOPLEFT", 10, -26)
    switchBtn:SetText("Swap")
    switchBtn:SetScript("OnClick", function()
        CloseOtherNexusWindows()
        if Nexus.JournalTab and Nexus.JournalTab.OpenBuilds then
            Nexus.JournalTab.OpenBuilds()
        else
            local pe = _G["ProjectEbonhold"]
            if pe and pe.EchoJournal and pe.EchoJournal.Show then
                pcall(pe.EchoJournal.Show, pe.EchoJournal)
            end
        end
    end)
    switchBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Swap", 1, 1, 1)
        GameTooltip:AddLine("Open the server Echoes page to swap the active Saved Build.", 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    switchBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Clickable compact replacement for Project Ebonhold's difficulty / Soul
    -- Ash HUD. In-progress builds use a slim header treatment. Completed builds
    -- expand this into the primary status card so the familiar server metrics
    -- remain the most visible information.
    worldStatusBox = CreateFrame("Frame", nil, frame)
    worldStatusBox:SetFrameLevel(frame:GetFrameLevel() + 3)
    pcall(function()
        worldStatusBox:SetBackdrop({
            bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true, tileSize=16, edgeSize=10,
            insets={left=2,right=2,top=2,bottom=2},
        })
        worldStatusBox:SetBackdropColor(0.018, 0.035, 0.045, 0.96)
        worldStatusBox:SetBackdropBorderColor(0.16, 0.34, 0.40, 0.9)
    end)

    worldStatusText = worldStatusBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    worldStatusText:SetJustifyH("LEFT")
    worldStatusText:SetText("")

    worldStatusAsh = worldStatusBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    worldStatusAsh:SetJustifyH("LEFT")
    worldStatusAsh:SetText("")

    worldStatusGain = worldStatusBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    worldStatusGain:SetJustifyH("RIGHT")
    worldStatusGain:SetText("")

    -- Live server Intensity meter. Keep these widgets attached to the status
    -- box instead of adding more module upvalues; WoW 3.3.5 Lua has a strict
    -- 60-upvalue compiler limit for functions.
    worldStatusBox.intensityBar = CreateFrame("StatusBar", nil, worldStatusBox)
    worldStatusBox.intensityBar:SetMinMaxValues(0, 500)
    worldStatusBox.intensityBar:SetValue(0)
    worldStatusBox.intensityBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    worldStatusBox.intensityBar:SetStatusBarColor(0.86, 0.24, 0.16, 1)
    worldStatusBox.intensityBar:SetFrameLevel(worldStatusBox:GetFrameLevel() + 2)

    worldStatusBox.intensityTrack = worldStatusBox.intensityBar:CreateTexture(nil, "BACKGROUND")
    worldStatusBox.intensityTrack:SetAllPoints()
    worldStatusBox.intensityTrack:SetTexture(0.07, 0.08, 0.09, 0.95)

    worldStatusBox.intensityText = worldStatusBox.intensityBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    worldStatusBox.intensityText:SetPoint("CENTER", worldStatusBox.intensityBar, "CENTER", 0, 0)
    worldStatusBox.intensityText:SetTextColor(1, 0.88, 0.72)
    worldStatusBox.intensityText:Hide()
    worldStatusBox.intensityText:SetText("")

    worldStatusBox.intensityTicks = {}
    for i = 1, 4 do
        local tick = worldStatusBox.intensityBar:CreateTexture(nil, "OVERLAY")
        tick:SetTexture(1, 1, 1, 0.28)
        tick:SetWidth(1)
        worldStatusBox.intensityTicks[i] = tick
    end

    local function PositionIntensityTicks()
        local bar = worldStatusBox and worldStatusBox.intensityBar
        if not bar then return end
        local width = tonumber(bar:GetWidth()) or 0
        if width <= 0 then return end
        for i = 1, 4 do
            local tick = worldStatusBox.intensityTicks[i]
            tick:ClearAllPoints()
            local x = math.floor((width * i / 5) + 0.5)
            tick:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
            tick:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
        end
    end
    worldStatusBox.PositionIntensityTicks = PositionIntensityTicks
    worldStatusBox.intensityBar:SetScript("OnSizeChanged", PositionIntensityTicks)

    worldStatusHit = CreateFrame("Button", nil, worldStatusBox)
    worldStatusHit:SetAllPoints(worldStatusBox)
    worldStatusHit:SetFrameLevel(worldStatusBox:GetFrameLevel() + 5)
    worldStatusHit:RegisterForClicks("LeftButtonUp")
    local statusHighlight = worldStatusHit:CreateTexture(nil, "HIGHLIGHT")
    statusHighlight:SetAllPoints()
    pcall(function() statusHighlight:SetTexture(1, 1, 1, 0.06) end)
    worldStatusHit:SetScript("OnClick", function()
        if Nexus.ServerStatus and Nexus.ServerStatus.OpenHardcoreMenu then
            Nexus.ServerStatus.OpenHardcoreMenu()
        end
    end)
    worldStatusHit:SetScript("OnEnter", function(self)
        local ss = worldStatusBox._summary or {}
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ss.tier or ss.mode or "Difficulty", 1, 0.25, 0.25)
        if ss.ash then GameTooltip:AddLine("Soul Ash: " .. tostring(ss.ash):gsub(",",""), 1, 1, 1) end
        if ss.gain then GameTooltip:AddLine("Soul Ash Multiplier: " .. tostring(ss.gain), 0.2, 1, 0.2) end
        if ss.intensity ~= nil then
            GameTooltip:AddLine("Intensity: " .. tostring(math.floor(tonumber(ss.intensity) or 0)) .. " / 500", 1, 0.55, 0.25)
            GameTooltip:AddLine("Intensity Level: " .. tostring(tonumber(ss.intensityLevel) or 0), 0.85, 0.75, 0.65)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to open the Hardcore difficulty panel.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    worldStatusHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    worldStatusBox:Hide()

    rollArea = CreateFrame("Frame", nil, frame)
    frame._rollArea = rollArea
    rollArea:SetPoint("TOPLEFT", 10, -98)
    rollArea:SetSize(280, 104)

    statusText = rollArea:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", 2, -1)
    statusText:SetSize(276, 14)
    statusText:SetJustifyH("LEFT")

    for i = 1, 3 do
        local fs = rollArea:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 2, -19 - (i - 1) * 14)
        fs:SetSize(276, 13)
        fs:SetJustifyH("LEFT")
        cardTexts[i] = fs
    end

    recText = rollArea:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recText:SetPoint("TOPLEFT", 2, -64)
    recText:SetSize(276, 30)
    recText:SetJustifyH("LEFT")
    recText:SetJustifyV("TOP")
    recText:SetTextColor(1, 0.82, 0)

    rollDivider = rollArea:CreateTexture(nil, "ARTWORK")
    rollDivider:SetSize(278, 1)
    rollDivider:SetPoint("BOTTOMLEFT", 1, 0)
    pcall(function() rollDivider:SetTexture(0.3, 0.3, 0.3, 0.65) end)

    progressLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    progressLabel:SetText("PROGRESS")
    progressValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    progressValue:SetTextColor(1, 0.5, 0.2)

    needLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    needLabel:SetText("STILL NEEDED")

    tomesLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tomesLabel:SetText("MISSING\nTOMES")
    tomesLabel:SetJustifyH("RIGHT")
            tomesLabel:SetJustifyV("TOP")
    tomesValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tomesValue:SetJustifyH("RIGHT")
    tomesValue:SetTextColor(1, 0.4, 0.4)
    tomesHit = CreateFrame("Frame", nil, frame)
    tomesHit:EnableMouse(true)
    tomesHit:SetScript("OnEnter", function(self)
        if #unknownTomesCache == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Missing Tomes", 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("These Echoes are on your wishlist but CANNOT appear", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("in your rolls yet because you have not learned their", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("corresponding Unlearn Tome.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("This is NOT an addon error. The addon is correct.", 0.6, 1, 0.6, true)
        GameTooltip:AddLine("Obtain and use the Unlearn Tome for each Echo below", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("to unlock it. They drop from world content and vendors.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Echoes blocked by missing tomes:", 1, 0.8, 0.4)
        for i, name in ipairs(unknownTomesCache) do
            GameTooltip:AddLine("  • " .. name, 1, 0.45, 0.45)
            if i >= 25 then
                if #unknownTomesCache > i then
                    GameTooltip:AddLine("  +" .. (#unknownTomesCache - i) .. " more", 0.7, 0.7, 0.7)
                end
                break
            end
        end
        GameTooltip:Show()
    end)
    tomesHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    needText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    needText:SetSize(136, 52)
    needText:SetJustifyH("LEFT")
    needText:SetJustifyV("TOP")
    needText:SetTextColor(1, 0.5, 0.2)
    needHit = HitFrame(frame, needText)
    needHit:SetScript("OnEnter", function(self)
        if #missingNamesCache == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Still needed this run", 1, 1, 1)
        GameTooltip:AddLine("These wishlist Echoes have not been obtained yet.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("When your wishlist Echoes are not on the board,", 0.75, 0.75, 0.75, true)
        GameTooltip:AddLine("the addon picks filler. Filler is intentional —", 0.75, 0.75, 0.75, true)
        GameTooltip:AddLine("it will be replaced in a future run once your", 0.75, 0.75, 0.75, true)
        GameTooltip:AddLine("wished Echoes become available to roll.", 0.75, 0.75, 0.75, true)
        GameTooltip:AddLine(" ")
        if #missingNamesCache > 0 then
            GameTooltip:AddLine("Missing Echoes:", 1, 0.65, 0.25)
            for i, name in ipairs(missingNamesCache) do
                -- Split "Echo Name ×N (Quality:×N ...)" into label and detail
                local label, detail = name:match("^(.-)%s+(%b())$")
                if label and detail then
                    GameTooltip:AddLine("  • " .. label, 0.9, 0.9, 0.9)
                    -- Strip outer parens and show quality breakdown indented
                    local inner = detail:sub(2, -2)
                    GameTooltip:AddLine("      " .. inner, 0.7, 0.7, 0.7)
                else
                    GameTooltip:AddLine("  • " .. name, 0.9, 0.9, 0.9)
                end
                if i >= 25 then
                    if #missingNamesCache > 25 then
                        GameTooltip:AddLine("  +" .. (#missingNamesCache - 25) .. " more", 0.6, 0.6, 0.6)
                    end
                    break
                end
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to open Wishlist Editor", 0.4, 0.8, 1)
        GameTooltip:Show()
    end)
    needHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    needHit:SetScript("OnMouseUp", function() if Nexus.WishlistEditor then Nexus.WishlistEditor.Show() end end)

    shedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    shedLabel:SetText("TO SHED")
    shedText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    shedText:SetSize(136, 46)
    shedText:SetJustifyH("LEFT")
    shedText:SetJustifyV("TOP")
    shedText:SetTextColor(0.72, 0.52, 1)
    shedHit = HitFrame(frame, shedText)
    shedHit:SetScript("OnEnter", function(self)
        if #shedNamesCache == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Echoes to shed", 1, 1, 1)
        GameTooltip:AddLine("These Echoes are in your current loadout but are", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Copies above your wishlist target, plus removable", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("off-wishlist filler that Nexus will replace.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Locked Echoes (pinned in your build slot) are", 0.75, 0.75, 0.75, true)
        GameTooltip:AddLine("never listed here, even if off-wishlist.", 0.75, 0.75, 0.75, true)
        GameTooltip:AddLine(" ")
        for i, name in ipairs(shedNamesCache) do
            GameTooltip:AddLine("  • " .. name, 0.75, 0.6, 1)
            if i >= 25 then
                if #shedNamesCache > 25 then
                    GameTooltip:AddLine("  +" .. (#shedNamesCache - 25) .. " more", 0.6, 0.6, 0.6)
                end
                break
            end
        end
        GameTooltip:Show()
    end)
    shedHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- The TO LOCK row's widgets are built lazily by M.Render (via
    -- CreateToLockWidgets), not here -- EnsureFrame is already at Lua
    -- 3.3.5's 60-upvalue ceiling (see the note on menuBtn's tooltip above),
    -- and even a single extra reference to that function tips it over.

    performanceLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    performanceLabel:SetText("PERFORMANCE")
    setLabelText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    setLabelText:SetSize(164, 14)
    setLabelText:SetJustifyH("LEFT")

    dummyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dummyLabel:SetText("Dummy Best")
    dummyValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dummyValue:SetJustifyH("RIGHT")
    dummyGlobal = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dummyGlobal:SetJustifyH("LEFT")
    dummyGlobalValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dummyGlobalValue:SetJustifyH("RIGHT")

    lkLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lkLabel:SetText("Lich King Best")
    lkPersonalLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lkPersonalLabel:SetText("Your Best")
    lkPersonalLabel:SetJustifyH("LEFT")
    lkValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lkValue:SetJustifyH("RIGHT")
    lkGlobal = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lkGlobal:SetJustifyH("LEFT")
    lkGlobalValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lkGlobalValue:SetJustifyH("RIGHT")

    dummyHit = CreateFrame("Frame", nil, frame)
    dummyHit:EnableMouse(true)
    lkHit = CreateFrame("Frame", nil, frame)
    lkHit:EnableMouse(true)

    completeBadge = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    completeBadge:SetTextColor(0.35, 1, 0.45)
    completeBadge:SetJustifyH("CENTER")
    completeSubtext = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    completeSubtext:SetJustifyH("CENTER")
    completeSubtext:SetTextColor(0.72, 0.72, 0.72)

    setupText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    setupText:SetJustifyH("CENTER")
    setupText:SetTextColor(0.45, 0.84, 1)
    setupHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    setupHint:SetSize(272, 34)
    setupHint:SetJustifyH("CENTER")
    setupHint:SetJustifyV("TOP")

    -- First-run primary action. Assignment used to be hidden behind the
    -- top-right Swap button while "Choose Build" opened an unrelated browser.
    -- Use the same server-backed assignment flow as Swap so the next required
    -- step is explicit and immediately reachable from onboarding.
    setupGetStartedBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    setupGetStartedBtn:SetSize(126, 24)
    setupGetStartedBtn:SetText("Assign Wishlist")
    setupGetStartedBtn:SetScript("OnClick", function()
        CloseOtherNexusWindows()
        if Nexus.JournalTab and Nexus.JournalTab.OpenBuilds then
            Nexus.JournalTab.OpenBuilds()
        else
            local pe = _G["ProjectEbonhold"]
            if pe and pe.EchoJournal and pe.EchoJournal.Show then
                pcall(pe.EchoJournal.Show, pe.EchoJournal)
            end
        end
    end)
    setupGetStartedBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Assign Wishlist", 1, 1, 1)
        GameTooltip:AddLine("Choose an existing server wishlist and associate it with this loadout.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    setupGetStartedBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    setupImportBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    setupImportBtn:SetSize(126, 24)
    setupImportBtn:SetText("Create Wishlist")
    setupImportBtn:SetScript("OnClick", function()
        CloseOtherNexusWindows()
        if Nexus.WishlistEditor then Nexus.WishlistEditor.Show() end
    end)
    setupImportBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Import or create a wishlist", 1, 1, 1)
        GameTooltip:AddLine("Paste a wishlist string or build one directly in Nexus.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    setupImportBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    autoBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame._autoBtn = autoBtn
    autoBtn:SetSize(72, 22)
    autoBtn:SetPoint("BOTTOMLEFT", 8, 7)
    autoBtn:SetText(AutoLabel(nil))
    autoBtn:SetScript("OnClick", function()
        if callbacks and type(callbacks.ToggleAuto) == "function" then
            local ok, state = pcall(callbacks.ToggleAuto)
            if ok and state ~= nil then autoBtn:SetText(AutoLabel(state and true or false)) end
        end
    end)
    autoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Auto Mode", 1, 1, 1)
        GameTooltip:AddLine("When ON: automatically picks Echoes, banishes, and rerolls", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("based on your wishlist. The addon plays the board for you.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Filler picks are correct behavior.", 0.6, 1, 0.6, true)
        GameTooltip:AddLine("When your wished Echoes aren't on the board, the addon", 0.75, 0.75, 0.75, true)
        GameTooltip:AddLine("takes the least-harmful filler to fill your slots.", 0.75, 0.75, 0.75, true)
        GameTooltip:AddLine("It will be replaced in a future run.", 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    autoBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    buildsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    buildsBtn:SetSize(104, 22)
    buildsBtn:SetText("Builds")
    buildsBtn:SetScript("OnClick", function()
        CloseOtherNexusWindows()
        if Nexus.CommunityBuilds then Nexus.CommunityBuilds.Show() end
    end)
    buildsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Builds", 1, 1, 1)
        GameTooltip:AddLine("Open My Builds and browse shared community builds.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    buildsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    leaderboardBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    leaderboardBtn:SetSize(104, 22)
    leaderboardBtn:SetText("Leaderboard")
    leaderboardBtn:SetScript("OnClick", function()
        CloseOtherNexusWindows()
        if Nexus.Leaderboard then Nexus.Leaderboard.Show() end
    end)
    leaderboardBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Leaderboard", 1, 1, 1)
        GameTooltip:AddLine("Compare Training Dummy and Lich King records.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    leaderboardBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Compact settings control. Navigation stays visible in the footer while
    -- infrequent tools live behind this single unobtrusive button.
    menuBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    menuBtn:SetSize(30, 20)
    menuBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -6)
    menuBtn:SetText("...")
    frame._menuBtn = menuBtn
    menuBtn:SetFrameLevel(frame:GetFrameLevel() + 8)
    menuBtn:SetScript("OnClick", function(self)
        if type(EasyMenu) ~= "function" then return end
        if type(CloseDropDownMenus) == "function" then CloseDropDownMenus() end
        NexusDB = NexusDB or {}
        local function MenuAction(fn)
            return function()
                if type(CloseDropDownMenus) == "function" then CloseDropDownMenus() end
                fn()
            end
        end
        local items = {
            {
                text = (Nexus.Updates and Nexus.Updates.GetVisibleNotice
                    and Nexus.Updates.GetVisibleNotice())
                    and ("Update available: v" .. tostring(Nexus.Updates.GetVisibleNotice().version))
                    or "No published update reported",
                notCheckable = true,
                disabled = not (Nexus.Updates and Nexus.Updates.GetVisibleNotice
                    and Nexus.Updates.GetVisibleNotice()),
                func = MenuAction(function()
                    local notice = Nexus.Updates and Nexus.Updates.GetVisibleNotice
                        and Nexus.Updates.GetVisibleNotice()
                    if notice then
                        StaticPopup_Show("NEXUS_UPDATE_RELEASES", notice.version,
                            Nexus.Updates.ReleaseUrl())
                    end
                end),
            },
            {
                text = (Nexus.Updates and Nexus.Updates.IsEnabled
                    and Nexus.Updates.IsEnabled())
                    and "Disable Update Notices" or "Enable Update Notices",
                notCheckable = true,
                func = MenuAction(function()
                    if Nexus.Updates and Nexus.Updates.SetEnabled then
                        Nexus.Updates.SetEnabled(not Nexus.Updates.IsEnabled())
                    end
                end),
            },
            {
                text = showPerformance and "Hide Performance" or "Show Performance",
                notCheckable = true,
                func = MenuAction(function()
                    showPerformance = not showPerformance
                    NexusDB.uiShowPerformance = showPerformance
                    if M.Refresh then M.Refresh() end
                end),
            },
            {
                text = "Wishlist Editor",
                notCheckable = true,
                func = MenuAction(function() CloseOtherNexusWindows(); if Nexus.WishlistEditor then Nexus.WishlistEditor.Show() end end),
            },
            {
                text = (Nexus.ServerStatus and Nexus.ServerStatus.IsUsingNexusHud and Nexus.ServerStatus.IsUsingNexusHud())
                    and "Use Server Difficulty / Soul Ash HUD" or "Use Nexus Difficulty / Soul Ash HUD",
                notCheckable = true,
                disabled = not (Nexus.ServerStatus and Nexus.ServerStatus.IsDetected and Nexus.ServerStatus.IsDetected()),
                func = MenuAction(function()
                    if Nexus.ServerStatus then
                        Nexus.ServerStatus.SetMode(Nexus.ServerStatus.IsUsingNexusHud() and "server" or "nexus")
                    end
                end),
            },
            {
                text = "Reset Panel Position",
                notCheckable = true,
                func = MenuAction(function()
                    NexusDB.panelX, NexusDB.panelY = nil, nil
                    frame:ClearAllPoints()
                    frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
                end),
            },
            {
                text = "Hide Nexus Panel",
                notCheckable = true,
                func = MenuAction(function() M.Hide() end),
            },
        }
        M._moreMenu = M._moreMenu or CreateFrame("Frame", "NexusPanelMoreMenu", UIParent, "UIDropDownMenuTemplate")
        EasyMenu(items, M._moreMenu, self, 0, 0, "MENU")
    end)
    menuBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Nexus Settings", 1, 1, 1)
        GameTooltip:AddLine("Performance display, wishlist tools, HUD mode, and panel settings.", 0.8, 0.8, 0.8, true)
        -- model.status (Main.lua's statusLine, including "error (see /nexus
        -- err)") was set on every render but never read anywhere in this file --
        -- surfaced here so a real error is visible without knowing the slash
        -- command exists. Inlined with tostring (a global, not an upvalue)
        -- rather than the SafeText helper -- EnsureFrame sits right at Lua
        -- 3.3.5's 60-upvalue-per-function ceiling; SafeText was a new one.
        local lastModel = M._lastModel
        local st = lastModel and lastModel.status
        if st ~= nil and tostring(st) ~= "" then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Status: " .. tostring(st), 0.6, 0.85, 1, true)
        end
        local notice = M._lastModel and M._lastModel.updateNotice
        if notice then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Update available: v" .. tostring(notice.version), 1, 0.82, 0, true)
            GameTooltip:AddLine("Click to copy the manual releases-page link.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    menuBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    bestDpsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bestDpsText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 33)
    bestDpsText:SetSize(280, 14)
    bestDpsText:SetJustifyH("CENTER")
    bestDpsText:SetText("|cff888888Best DPS: hit a training dummy to record|r")
    bestDpsHit = HitFrame(frame, bestDpsText)
    bestDpsHit:SetScript("OnEnter", function(self)
        local info = M._lastModel and M._lastModel.bestDps
            and M._lastModel.bestDps.info
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Character Best DPS", 1, 1, 1)
        if info then
            GameTooltip:AddLine(FmtDps(info.dps) .. " DPS · " .. (info.category == "lk" and "Lich King" or "Training Dummy"), 0.35, 1, 0.45)
            if info.title then GameTooltip:AddLine(info.title, 0.65, 0.85, 1) end
        else
            GameTooltip:AddLine("No recorded DPS yet.", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Fight a training dummy for at least 10 seconds to establish your first record.", 0.9, 0.9, 0.9, true)
        end
        GameTooltip:Show()
    end)
    bestDpsHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    versionText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    versionText:Hide() -- version remains in /nexus and tooltips; avoids bottom-row overlap

    NexusDB = NexusDB or {}
    showPerformance = NexusDB.uiShowPerformance == true

    pcall(function()
        frame:SetBackdrop({
            bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true, tileSize=16, edgeSize=12,
            insets={left=3,right=3,top=3,bottom=3},
        })
        frame:SetBackdropColor(0.035, 0.035, 0.05, 0.94)
        frame:SetBackdropBorderColor(0.28, 0.28, 0.34, 0.9)
    end)

    frame._footerButtons = {
        auto=autoBtn,builds=buildsBtn,leaderboard=leaderboardBtn,
    }
    M.ApplyOwnedFonts()
    return frame
end

local function EnsureMinimapButton()
    if minimapBtn then return minimapBtn end
    NexusDB = NexusDB or {}
    NexusDB.minimapAngle = NexusDB.minimapAngle or 220

    local btn = CreateFrame("Button", "NexusMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20); icon:SetPoint("CENTER"); icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    pcall(function()
        local border = btn:CreateTexture(nil, "OVERLAY")
        border:SetSize(54,54); border:SetPoint("TOPLEFT",-3,3); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    end)

    local function Reposition()
        local angle = math.rad(NexusDB.minimapAngle or 220)
        local r = 80
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", r * math.cos(angle), r * math.sin(angle))
    end
    Reposition()

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            NexusDB.minimapAngle = math.deg(math.atan2(py - my, px - mx))
            Reposition()
        end)
    end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" and Nexus.WishlistEditor then Nexus.WishlistEditor.Show() else M.Toggle() end
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff7fd5ffNexus|r  |cff888888" .. SafeText(Nexus.VERSION) .. "|r")
        GameTooltip:AddLine("Echo build automation · Community Builds · DPS Leaderboard", 0.6,0.8,1,true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: HUD  |  Right-click: Wishlists  |  Drag to reposition", 0.7,0.7,0.7,true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    minimapBtn = btn
    return btn
end

local function PositionPerformance(topY, completed, metrics)
    local small = metrics and metrics.small or 11
    local normal = metrics and metrics.normal or 14
    local gap = metrics and metrics.gap or 6
    if completed then
        -- Compact centered record table sized to stay inside the narrower HUD.
        -- Keep headings centered while pulling value columns inward so long DPS
        -- values do not hang off the right edge.
        local left, width = 24, 224
        local labelW, valueW = 120, 72

        local dummyTop = topY - small - gap
        local dummyGlobalTop = dummyTop - normal - math.max(3,math.floor(gap/2))
        local lkHeadingTop = dummyGlobalTop - normal - gap
        local lkTop = lkHeadingTop - small - gap
        local lkGlobalTop = lkTop - normal - math.max(3,math.floor(gap/2))

        SetPoint(performanceLabel, "TOP", frame, "TOP", 0, topY)
        performanceLabel:SetSize(width, small)
        performanceLabel:SetJustifyH("CENTER")

        SetPoint(dummyLabel, "TOPLEFT", frame, "TOPLEFT", left, dummyTop)
        dummyLabel:SetSize(labelW, normal); dummyLabel:SetJustifyH("LEFT")
        SetPoint(dummyValue, "TOPLEFT", frame, "TOPLEFT", left + labelW, dummyTop)
        dummyValue:SetSize(valueW, normal); dummyValue:SetJustifyH("RIGHT")
        SetPoint(dummyGlobal, "TOPLEFT", frame, "TOPLEFT", left, dummyGlobalTop)
        dummyGlobal:SetSize(labelW, normal); dummyGlobal:SetJustifyH("LEFT")
        SetPoint(dummyGlobalValue, "TOPLEFT", frame, "TOPLEFT", left + labelW, dummyGlobalTop)
        dummyGlobalValue:SetSize(valueW, normal); dummyGlobalValue:SetJustifyH("RIGHT")

        SetPoint(lkPersonalLabel, "TOP", frame, "TOP", 0, lkHeadingTop)
        lkPersonalLabel:SetSize(width, small); lkPersonalLabel:SetJustifyH("CENTER")
        SetPoint(lkLabel, "TOPLEFT", frame, "TOPLEFT", left, lkTop)
        lkLabel:SetSize(labelW, normal); lkLabel:SetJustifyH("LEFT")
        SetPoint(lkValue, "TOPLEFT", frame, "TOPLEFT", left + labelW, lkTop)
        lkValue:SetSize(valueW, normal); lkValue:SetJustifyH("RIGHT")
        SetPoint(lkGlobal, "TOPLEFT", frame, "TOPLEFT", left, lkGlobalTop)
        lkGlobal:SetSize(labelW, normal); lkGlobal:SetJustifyH("LEFT")
        SetPoint(lkGlobalValue, "TOPLEFT", frame, "TOPLEFT", left + labelW, lkGlobalTop)
        lkGlobalValue:SetSize(valueW, normal); lkGlobalValue:SetJustifyH("RIGHT")
    else
        -- Expanded active-build performance is a separate section below progress.
        -- Keeping it out of the progress columns prevents every optional state
        -- (tomes, shed Echoes, live rolls) from competing for the same space.
        local left, right = 20, 160
        local colW = 120
        local setTop = topY - small - math.max(3,math.floor(gap/2))
        local rowTop = setTop - small - gap
        local globalTop = rowTop - normal - math.max(3,math.floor(gap/2))
        SetPoint(performanceLabel, "TOP", frame, "TOP", 0, topY)
        performanceLabel:SetSize(260, small)
        performanceLabel:SetJustifyH("CENTER")
        SetPoint(setLabelText, "TOP", frame, "TOP", 0, setTop)
        setLabelText:SetSize(260, small)
        setLabelText:SetJustifyH("CENTER")

        SetPoint(dummyLabel, "TOPLEFT", frame, "TOPLEFT", left, rowTop)
        dummyLabel:SetSize(70, normal); dummyLabel:SetJustifyH("LEFT")
        SetPoint(dummyValue, "TOPLEFT", frame, "TOPLEFT", left + 70, rowTop)
        dummyValue:SetSize(50, normal); dummyValue:SetJustifyH("RIGHT")
        SetPoint(dummyGlobal, "TOPLEFT", frame, "TOPLEFT", left, globalTop)
        dummyGlobal:SetSize(colW, normal); dummyGlobal:SetJustifyH("LEFT")

        SetPoint(lkLabel, "TOPLEFT", frame, "TOPLEFT", right, rowTop)
        lkLabel:SetSize(70, normal); lkLabel:SetJustifyH("LEFT")
        SetPoint(lkValue, "TOPLEFT", frame, "TOPLEFT", right + 70, rowTop)
        lkValue:SetSize(50, normal); lkValue:SetJustifyH("RIGHT")
        SetPoint(lkGlobal, "TOPLEFT", frame, "TOPLEFT", right, globalTop)
        lkGlobal:SetSize(colW, normal); lkGlobal:SetJustifyH("LEFT")
    end

    dummyHit:ClearAllPoints()
    dummyHit:SetPoint("TOPLEFT", dummyLabel, "TOPLEFT", 0, 2)
    dummyHit:SetPoint("BOTTOMRIGHT", completed and dummyGlobalValue or dummyGlobal, "BOTTOMRIGHT", 0, -2)
    lkHit:ClearAllPoints()
    lkHit:SetPoint("TOPLEFT", completed and lkPersonalLabel or lkLabel, "TOPLEFT", 0, 2)
    lkHit:SetPoint("BOTTOMRIGHT", completed and lkGlobalValue or lkGlobal, "BOTTOMRIGHT", 0, -2)
end

local function RenderPerformance(pr, completed)
    local performance = type(pr.performance) == "table" and pr.performance or {}
    local dummy = type(performance.dummy) == "table" and performance.dummy or {}
    local lk = type(performance.lk) == "table" and performance.lk or {}
    local myDummy, myLK = dummy.personal, lk.personal
    local topDummy, topLK = dummy.global, lk.global

    local count = tonumber(pr.total) or 0
    if completed then
        performanceLabel:SetText("TRAINING DUMMY")
        setLabelText:SetText("")
        dummyLabel:SetText("Your Best")
        dummyGlobal:SetText("Global Best")
        lkPersonalLabel:SetText("LICH KING")
        lkLabel:SetText("Your Best")
        lkGlobal:SetText("Global Best")
    else
        performanceLabel:SetText("PERFORMANCE")
        setLabelText:SetText("Target build · " .. count .. " Echoes")
        dummyLabel:SetText("Your Dummy")
        lkLabel:SetText("Your Lich King")
    end
    dummyValue:SetText(myDummy and ("|cff4dff80" .. FmtDps(myDummy.dps) .. "|r") or "|cff777777—|r")
    lkValue:SetText(myLK and ("|cff4dff80" .. FmtDps(myLK.dps) .. "|r") or "|cff777777—|r")
    if completed then
        dummyGlobalValue:SetText(topDummy and ("|cffffd200" .. FmtDps(topDummy.dps) .. "|r") or "|cff777777—|r")
        lkGlobalValue:SetText(topLK and ("|cffffd200" .. FmtDps(topLK.dps) .. "|r") or "|cff777777—|r")
    else
        dummyGlobal:SetText(topDummy and ("Global  |cffffd200" .. FmtDps(topDummy.dps) .. "|r") or "Global  —")
        lkGlobal:SetText(topLK and ("Global  |cffffd200" .. FmtDps(topLK.dps) .. "|r") or "Global  —")
    end

    AddDpsTooltip(dummyHit, "Training Dummy", myDummy, topDummy)
    AddDpsTooltip(lkHit, "Lich King", myLK, topLK)
end

local function ShowCoreProgress(show)
    SetVisible(progressLabel, show); SetVisible(progressValue, show)
    SetVisible(needLabel, show); SetVisible(needText, show); SetVisible(needHit, show)
    local showTomes = show and #unknownTomesCache > 0
    SetVisible(tomesLabel, showTomes); SetVisible(tomesValue, showTomes); SetVisible(tomesHit, showTomes)
    SetVisible(shedLabel, show); SetVisible(shedText, show); SetVisible(shedHit, show)
    local showToLock = show and #toLockNamesCache > 0
    if frame then
        SetVisible(frame.toLockLabel, showToLock); SetVisible(frame.toLockText, showToLock); SetVisible(frame.toLockHit, showToLock)
    end
end

local function ShowPerformance(show)
    SetVisible(performanceLabel, show); SetVisible(setLabelText, show)
    SetVisible(dummyLabel, show); SetVisible(dummyValue, show); SetVisible(dummyGlobal, show); SetVisible(dummyGlobalValue, show); SetVisible(dummyHit, show)
    SetVisible(lkLabel, show); SetVisible(lkPersonalLabel, show); SetVisible(lkValue, show); SetVisible(lkGlobal, show); SetVisible(lkGlobalValue, show); SetVisible(lkHit, show)
end

local function RenderPerformanceState(pr, completed, enabled)
    ShowPerformance(enabled)
    if enabled then RenderPerformance(pr, completed) end
end

function M.Init(cb)
    if cb ~= nil then callbacks = cb end
    pcall(EnsureMinimapButton)
end

function M.SetAuto(auto)
    if autoBtn then autoBtn:SetText(AutoLabel(auto and true or false)) end
end

function M.Toggle()
    local f = EnsureFrame()
    if f:IsShown() then
        panelWantedVisible = false
        f:Hide()
    else
        panelWantedVisible = true
        RequestDisplayRecovery()
        ApplyWantedVisibility()
    end
end

local function LayoutServerStatus(completed)
    worldStatusBox:ClearAllPoints()
    worldStatusText:ClearAllPoints()
    worldStatusAsh:ClearAllPoints()
    worldStatusGain:ClearAllPoints()
    worldStatusBox.intensityBar:ClearAllPoints()

    if completed then
        worldStatusBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -33)
        worldStatusBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -33)
        worldStatusBox:SetHeight(66)

        worldStatusText:SetPoint("TOPLEFT", worldStatusBox, "TOPLEFT", 9, -5)
        worldStatusText:SetSize(156, 18)
        worldStatusText:SetJustifyH("LEFT")

        worldStatusAsh:SetPoint("BOTTOMLEFT", worldStatusBox, "BOTTOMLEFT", 9, 5)
        worldStatusAsh:SetSize(164, 17)
        worldStatusAsh:SetJustifyH("LEFT")

        worldStatusGain:SetPoint("TOPRIGHT", worldStatusBox, "TOPRIGHT", -9, -7)
        worldStatusGain:SetSize(66, 13)
        worldStatusGain:SetJustifyH("RIGHT")

        worldStatusAsh:ClearAllPoints()
        worldStatusAsh:SetPoint("TOPLEFT", worldStatusText, "BOTTOMLEFT", 0, -1)
        worldStatusAsh:SetSize(188, 17)

        worldStatusBox.intensityBar:ClearAllPoints()
        worldStatusBox.intensityBar:SetPoint("BOTTOMLEFT", worldStatusBox, "BOTTOMLEFT", 9, 5)
        worldStatusBox.intensityBar:SetPoint("BOTTOMRIGHT", worldStatusBox, "BOTTOMRIGHT", -9, 5)
        worldStatusBox.intensityBar:SetHeight(13)
        worldStatusBox.PositionIntensityTicks()
    else
        -- Give active builds the same readable status-card treatment as the
        -- completed HUD.  The old compressed strip made Soul Ash and Intensity
        -- feel secondary even though they are the player's live run state.
        worldStatusBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -33)
        worldStatusBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -33)
        worldStatusBox:SetHeight(56)

        worldStatusText:SetPoint("TOPLEFT", worldStatusBox, "TOPLEFT", 9, -5)
        worldStatusText:SetSize(104, 16)
        worldStatusText:SetJustifyH("LEFT")

        worldStatusAsh:SetPoint("TOPLEFT", worldStatusText, "BOTTOMLEFT", 0, -2)
        worldStatusAsh:SetSize(172, 17)
        worldStatusAsh:SetJustifyH("LEFT")

        worldStatusGain:SetPoint("TOPRIGHT", worldStatusBox, "TOPRIGHT", -9, -7)
        worldStatusGain:SetSize(70, 14)
        worldStatusGain:SetJustifyH("RIGHT")

        worldStatusBox.intensityBar:ClearAllPoints()
        worldStatusBox.intensityBar:SetPoint("BOTTOMLEFT", worldStatusBox, "BOTTOMLEFT", 9, 5)
        worldStatusBox.intensityBar:SetPoint("BOTTOMRIGHT", worldStatusBox, "BOTTOMRIGHT", -9, 5)
        worldStatusBox.intensityBar:SetHeight(10)
        worldStatusBox.PositionIntensityTicks()
    end
end

local function LayoutFooter(showAuto, completed)
    menuBtn:Show()
    menuBtn:ClearAllPoints()
    menuBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -6)

    autoBtn:ClearAllPoints()
    buildsBtn:ClearAllPoints()
    leaderboardBtn:ClearAllPoints()

    if showAuto then
        autoBtn:Show()
        autoBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 7)
        autoBtn:SetSize(72, 22)

        buildsBtn:SetPoint("LEFT", autoBtn, "RIGHT", 4, 0)
        buildsBtn:SetSize(84, 22)

        leaderboardBtn:SetPoint("LEFT", buildsBtn, "RIGHT", 4, 0)
        leaderboardBtn:SetSize(84, 22)
    else
        autoBtn:Hide()

        -- At level 80 / completed build, records are the primary destination.
        -- Builds remains equally accessible without hiding either behind a menu.
        if completed then
            leaderboardBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 7)
            leaderboardBtn:SetSize(96, 20)
            buildsBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 7)
            buildsBtn:SetSize(96, 20)
        else
            buildsBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 7)
            buildsBtn:SetSize(96, 20)
            leaderboardBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 7)
            leaderboardBtn:SetSize(96, 20)
        end
    end

    buildsBtn:Show()
    leaderboardBtn:Show()
end

local function PlacePanelRect(widget, x, y, width, height, relative)
    if not widget then return end
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT",relative or frame,"TOPLEFT",x,-y)
    widget:SetSize(width,height)
end

local function PlacePanelBox(widget, box, relative)
    if not box then return end
    PlacePanelRect(widget,box.x,box.y,box.w,box.h,relative)
end

-- Apply one cached geometry snapshot after the state renderer has populated
-- text and visibility. This final pass owns positions; model rendering remains
-- free to update content without rebuilding or measuring the frame tree.
local function ApplyPanelLayout(layout, completed)
    if not (layout and frame) then return end
    local boxes = layout.boxes
    frame._responsiveLayout = layout
    frame:SetSize(layout.width, layout.height)

    if boxes.status then PlacePanelBox(worldStatusBox, boxes.status) end
    if boxes.roll then
        PlacePanelBox(rollArea, boxes.roll)
        local inset = 2
        local y = 1
        statusText:ClearAllPoints()
        statusText:SetPoint("TOPLEFT", rollArea, "TOPLEFT", inset, -y)
        statusText:SetSize(boxes.roll.w-inset*2, layout.small)
        y = y + layout.small + math.max(3,math.floor(layout.gap/2))
        for index = 1, 3 do
            local text = cardTexts[index]
            text:ClearAllPoints()
            text:SetPoint("TOPLEFT", rollArea, "TOPLEFT", inset, -y)
            text:SetSize(boxes.roll.w-inset*2, layout.small)
            y = y + layout.small + math.max(2,math.floor(layout.gap/3))
        end
        recText:ClearAllPoints()
        recText:SetPoint("TOPLEFT", rollArea, "TOPLEFT", inset, -y)
        recText:SetSize(boxes.roll.w-inset*2,
            math.max(layout.small*2,boxes.roll.h-y-layout.gap))
        rollDivider:ClearAllPoints()
        rollDivider:SetPoint("BOTTOMLEFT", rollArea, "BOTTOMLEFT", 1, 0)
        rollDivider:SetSize(boxes.roll.w-2,1)
    end

    PlacePanelBox(setupText, boxes.setupTitle)
    PlacePanelBox(setupHint, boxes.setupHint)
    PlacePanelBox(setupGetStartedBtn, boxes.setupAssign)
    PlacePanelBox(setupImportBtn, boxes.setupCreate)
    PlacePanelBox(completeBadge, boxes.completeTitle)
    PlacePanelBox(completeSubtext, boxes.completeText)
    PlacePanelBox(progressLabel, boxes.progressHeader)
    PlacePanelBox(progressValue, boxes.progressValue)

    if boxes.tomes then
        tomesLabel:SetText("MISSING TOMES")
        PlacePanelRect(tomesLabel,boxes.tomes.x,boxes.tomes.y,
            boxes.tomes.w-28,boxes.tomes.h)
        tomesLabel:SetJustifyH("LEFT")
        PlacePanelRect(tomesValue,boxes.tomes.x+boxes.tomes.w-24,
            boxes.tomes.y,24,boxes.tomes.h)
    end

    local labelGap = math.max(3,math.floor(layout.gap/2))
    if boxes.needed then
        PlacePanelRect(needLabel,boxes.needed.x,boxes.needed.y,
            boxes.needed.w,layout.small)
        PlacePanelRect(needText,boxes.needed.x,
            boxes.needed.y+layout.small+labelGap,boxes.needed.w,
            boxes.needed.h-layout.small-labelGap)
    end
    if boxes.shed then
        PlacePanelRect(shedLabel,boxes.shed.x,boxes.shed.y,
            boxes.shed.w,layout.small)
        PlacePanelRect(shedText,boxes.shed.x,
            boxes.shed.y+layout.small+labelGap,boxes.shed.w,
            boxes.shed.h-layout.small-labelGap)
    end
    if boxes.toLock and frame.toLockLabel then
        PlacePanelRect(frame.toLockLabel,boxes.toLock.x,boxes.toLock.y,
            boxes.toLock.w,layout.small)
        PlacePanelRect(frame.toLockText,boxes.toLock.x,
            boxes.toLock.y+layout.small+labelGap,boxes.toLock.w,
            boxes.toLock.h-layout.small-labelGap)
        frame.toLockHit:ClearAllPoints()
        frame.toLockHit:SetPoint("TOPLEFT",frame.toLockLabel,"TOPLEFT",-2,2)
        frame.toLockHit:SetPoint("BOTTOMRIGHT",frame.toLockText,"BOTTOMRIGHT",2,-2)
    end
    if boxes.performance then
        PositionPerformance(-boxes.performance.y,completed,layout)
    end
    PlacePanelBox(bestDpsText, boxes.bestDps)
end

local function RenderBestDps(model, complete, noBuild, activeRoll, statusVisible)
    local best = type(model.bestDps) == "table" and model.bestDps or {}
    local dummyBest, lkBest = best.dummy, best.lk
    if dummyBest or lkBest then
        local dummyText = dummyBest and ("|cff4dff80" .. FmtDps(dummyBest.dps) .. "|r") or "|cff777777—|r"
        local lkText = lkBest and ("|cff4dff80" .. FmtDps(lkBest.dps) .. "|r") or "|cff777777—|r"
        bestDpsText:SetText("|cffb8b8b8Best DPS:|r  Dummy " .. dummyText .. "  |cff666666•|r  Lich King " .. lkText)
    else
        bestDpsText:SetText("|cff888888Best DPS: hit a training dummy to record|r")
    end
    if not noBuild then
        bestDpsText:Show()
        bestDpsHit:Show()
    else
        bestDpsText:Hide()
        bestDpsHit:Hide()
    end
end

local function ApplyModel(model, signatures)
    local previousSignatures = renderState.signatures
    if previousSignatures and signatures.layout == previousSignatures.layout then
        local changed = false
        if signatures.notice ~= previousSignatures.notice then
            frame._menuBtn:SetText(model.updateNotice and "!" or "...")
            renderStats.noticePasses = renderStats.noticePasses + 1
            changed = true
        end
        if signatures.performance ~= previousSignatures.performance then
            local pr = type(model.progress) == "table" and model.progress or {}
            local total, owned = tonumber(pr.total) or 0, tonumber(pr.owned) or 0
            local complete = total > 0 and owned >= total
                and #(type(pr.toLock) == "table" and pr.toLock or {}) == 0
            local cards = type(model.cards) == "table" and model.cards or {}
            local activeRoll = #cards > 0 or SafeText(model.recommendation) ~= ""
            local noBuild = total <= 0 or not pr.wishlistName
            local ss = type(model.serverStatus) == "table" and model.serverStatus or nil
            local statusVisible = ss and (ss.tier or ss.mode or ss.ash
                or ss.gain or ss.intensity ~= nil) and true or false
            RenderPerformanceState(pr, complete, not noBuild and showPerformance)
            RenderBestDps(model, complete, noBuild, activeRoll, statusVisible)
            renderStats.performancePasses = renderStats.performancePasses + 1
            changed = true
        end
        if signatures.auto ~= previousSignatures.auto
            and frame._autoBtn:IsShown() then
            frame._autoBtn:SetText(AutoLabel(model.auto))
            changed = true
        end
        if signatures.status ~= previousSignatures.status then
            renderStats.statusOnly = renderStats.statusOnly + 1
            changed = true
        end
        if not changed then renderStats.skipped = renderStats.skipped + 1 end
        return true
    end
    renderStats.layouts = renderStats.layouts + 1
    if frame._menuBtn then
        frame._menuBtn:SetText(model.updateNotice and "!" or "...")
    end

    local pr = type(model.progress) == "table" and model.progress or {}
    local name = pr.wishlistName
    local total = tonumber(pr.total) or 0
    local owned = tonumber(pr.owned) or 0
    -- A build is not complete while one of its designed permanent slots is
    -- still unresolved. This keeps the TO LOCK row visible at 79/79 until the
    -- server confirms the exact Echo in GetLockedPerks().
    local complete = total > 0 and owned >= total
        and #(type(pr.toLock) == "table" and pr.toLock or {}) == 0
    local cards = type(model.cards) == "table" and model.cards or {}
    local recommendation = SafeText(model.recommendation)
    local activeRoll = #cards > 0 or recommendation ~= ""
    local noBuild = total <= 0 or not name
    local ss = type(model.serverStatus) == "table" and model.serverStatus or nil
    local statusVisible = ss and (ss.tier or ss.mode or ss.ash or ss.gain or ss.intensity ~= nil) and true or false
    local playerLevel = tonumber(model.level) or 0
    -- Auto controls are useful only while actively progressing a build. At level
    -- 80 or once the destination is complete, the button is removed entirely
    -- instead of presenting an action that can no longer help the player.
    -- Keep the master Auto control visible for every active offering,
    -- including level 80 and completed-target boards. Toggling Auto off must
    -- never make the control used to turn it back on disappear.
    local showAutoControl = not noBuild and (activeRoll or (not complete and playerLevel < 80))
    local responsiveLayout
    if Nexus.LayoutMetrics then
        local metricsOk, fontScale, uiScale, revision =
            pcall(Nexus.LayoutMetrics.RuntimeMetrics)
        if metricsOk then
            local layoutOk, candidate = pcall(Nexus.LayoutMetrics.Panel,{
                width=272,fontScale=fontScale,uiScale=uiScale,
                revision=revision,activeRoll=activeRoll,
                statusVisible=statusVisible,noBuild=noBuild,
                complete=complete,showPerformance=showPerformance,
                toLockCount=type(pr.toLock) == "table" and #pr.toLock or 0,
                unknownTomes=type(pr.unknownTomes) == "table"
                    and #pr.unknownTomes or 0,
            })
            if layoutOk and type(candidate) == "table" then
                responsiveLayout = candidate
            end
        end
        if not responsiveLayout and frame then
            responsiveLayout = frame._responsiveLayout
        end
    end
    LayoutFooter(showAutoControl, complete and not noBuild)

    frame._buildHeaderText:SetText(name and ("|cff7fd5ff" .. ShortName(name, 29) .. "|r" .. (pr.isCommunityPreview and " |cff888888[Preview]|r" or "")) or "|cff7fd5ffNexus|r")
    frame._switchBtn:SetText("Swap")

    SetVisible(frame._rollArea, activeRoll)
    frame._rollArea:ClearAllPoints()
    frame._rollArea:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, statusVisible and -98 or -39)
    if activeRoll then
        local activeSlot = tonumber(pr.activeSlot) or 0
        statusText:SetText(activeSlot > 0 and ("|cff4dff80Active:|r Roll recommendations active — Slot " .. activeSlot) or "|cff888888Preview: Roll recommendation preview|r")
        for i = 1, 3 do
            local c = cards[i]
            cardTexts[i]:SetText(type(c) == "table" and SafeText(c.text) or "")
        end
        recText:SetText(recommendation)
    end

    missingNamesCache = type(pr.missing) == "table" and pr.missing or {}
    shedNamesCache = type(pr.shed) == "table" and pr.shed or {}
    unknownTomesCache = type(pr.unknownTomes) == "table" and pr.unknownTomes or {}
    toLockNamesCache = type(pr.toLock) == "table" and pr.toLock or {}

    SetVisible(setupText, noBuild); SetVisible(setupHint, noBuild)
    SetVisible(setupGetStartedBtn, noBuild); SetVisible(setupImportBtn, noBuild)
    SetVisible(completeBadge, complete and not noBuild); SetVisible(completeSubtext, complete and not noBuild)
    ShowCoreProgress(not noBuild and not complete)
    ShowPerformance(not noBuild and showPerformance)

    -- Collapse the space reserved for Nexus' Soul Ash card whenever the player
    -- uses the server HUD. Live-roll content still gets its own fixed block.
    local contentTop
    if activeRoll then
        contentTop = statusVisible and -220 or -161
    else
        contentTop = statusVisible and -103 or -44
    end
    local statusHeightReduction = statusVisible and 0 or 59

    if not complete then
        frame._switchBtn:ClearAllPoints()
        frame._switchBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -7)
        frame._switchBtn:SetSize(68, 19)
        frame._buildHeaderText:ClearAllPoints()
        frame._buildHeaderText:SetPoint("TOPLEFT", frame, "TOPLEFT", 40, -8)
        frame._buildHeaderText:SetPoint("RIGHT", frame._switchBtn, "LEFT", -5, 0)
        frame._buildHeaderText:SetJustifyH("CENTER")
    end

    if noBuild then
        SetVisible(dummyGlobalValue, false)
        SetVisible(lkGlobalValue, false)
        -- Stacked, centered, and ordered by what actually needs to happen:
        -- Assign Wishlist is the one button that gets Nexus running at all
        -- (Create Wishlist is only needed first if no wishlist exists yet),
        -- so it sits right under the instructions instead of sharing a row
        -- with an equally-weighted second option.
        frame:SetHeight((activeRoll and 428 or 278) - statusHeightReduction)
        SetPoint(setupText, "TOP", frame, "TOP", 0, contentTop - 18)
        setupText:SetText("Assign a wishlist to this loadout")
        SetPoint(setupHint, "TOP", frame, "TOP", 0, contentTop - 48)
        setupHint:SetText("Assign an existing wishlist to this loadout, or create a new one. No Saved Build is required.")
        setupGetStartedBtn:ClearAllPoints()
        setupGetStartedBtn:SetPoint("TOP", frame, "TOP", 0, contentTop - 96)
        setupImportBtn:ClearAllPoints()
        setupImportBtn:SetPoint("TOP", frame, "TOP", 0, contentTop - 128)
    elseif complete then
        -- Once a build is complete, progress text stops being the purpose of the
        -- HUD. The panel becomes a compact replacement for the stock difficulty /
        -- Soul Ash tracker, with Nexus navigation and the player's best DPS.
        frame:SetHeight((showPerformance and (activeRoll and 430 or 286) or (activeRoll and 292 or 168)) - statusHeightReduction)
        -- completeBadge/completeSubtext were created and toggled everywhere but
        -- never given text anywhere in this file -- when the server-status HUD
        -- has nothing to show (statusVisible false) and Performance is off, the
        -- panel had nothing left to render at all. Use them as the fallback so
        -- "complete" is never a blank frame.
        if statusVisible then
            SetVisible(completeBadge, false)
            SetVisible(completeSubtext, false)
        else
            SetPoint(completeBadge, "TOP", frame, "TOP", 0, contentTop - 8)
            completeBadge:SetText("Wishlist complete")
            SetPoint(completeSubtext, "TOP", frame, "TOP", 0, contentTop - 30)
            completeSubtext:SetSize(252, 32)
            completeSubtext:SetJustifyV("TOP")
            completeSubtext:SetText(name
                and ("'" .. ShortName(name, 34) .. "' is fully covered -- add more Echoes to keep rolling.")
                or "Add more Echoes to your wishlist to keep rolling.")
            SetVisible(completeBadge, true)
            SetVisible(completeSubtext, true)
        end
        frame._switchBtn:ClearAllPoints()
        frame._switchBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -7)
        frame._switchBtn:SetSize(68, 19)
        frame._buildHeaderText:ClearAllPoints()
        frame._buildHeaderText:SetPoint("TOPLEFT", frame, "TOPLEFT", 40, -8)
        frame._buildHeaderText:SetPoint("RIGHT", frame._switchBtn, "LEFT", -5, 0)
        frame._buildHeaderText:SetJustifyH("CENTER")
        SetVisible(setLabelText, false)
        SetVisible(lkPersonalLabel, showPerformance)
        SetVisible(dummyGlobalValue, true)
        SetVisible(lkGlobalValue, true)
    else
        SetVisible(dummyGlobalValue, false)
        SetVisible(lkGlobalValue, false)
        SetVisible(setLabelText, true)
        -- The TO LOCK row only exists when there's something to report --
        -- most wishlists design zero locked-slot targets, so the extra
        -- height stays reserved only while it's actually needed.
        local toLockExtra = #toLockNamesCache > 0 and 34 or 0
        frame:SetHeight((showPerformance and (activeRoll and 448 or 325) or (activeRoll and 388 or 267)) - statusHeightReduction + toLockExtra)
        SetPoint(progressLabel, "TOPLEFT", frame, "TOPLEFT", 12, contentTop)
        SetPoint(progressValue, "TOPLEFT", frame, "TOPLEFT", 12, contentTop - 17)
        progressValue:SetText(string.format("%d / %d complete", owned, total))

        SetPoint(needLabel, "TOPLEFT", frame, "TOPLEFT", 12, contentTop - 42)
        needLabel:SetText("STILL NEEDED")

        if #unknownTomesCache > 0 then
            -- Tomes are metadata for the run, not a third content column.
            -- Keep them on the progress line and preserve two clean Echo columns.
            tomesLabel:SetText("MISSING\nTOMES")
            SetPoint(tomesLabel, "TOPRIGHT", frame, "TOPRIGHT", -26, contentTop - 18)
            tomesLabel:SetSize(58, 24)
            tomesLabel:SetJustifyH("RIGHT")
            tomesLabel:SetJustifyV("TOP")
            SetPoint(tomesValue, "TOPRIGHT", frame, "TOPRIGHT", -10, contentTop - 18)
            tomesValue:SetSize(18, 14)
            tomesValue:SetJustifyH("RIGHT")
            tomesValue:SetText(tostring(#unknownTomesCache))
            tomesLabel:SetTextColor(0.85, 0.7, 0.55)
            tomesValue:SetTextColor(1, 0.4, 0.4)
            tomesLabel:Show()
            tomesValue:Show()
            tomesHit:ClearAllPoints()
            tomesHit:SetPoint("TOPLEFT", tomesLabel, "TOPLEFT", -2, 2)
            tomesHit:SetPoint("BOTTOMRIGHT", tomesValue, "BOTTOMRIGHT", 2, -2)
            tomesHit:Show()
        else
            tomesLabel:Hide()
            tomesValue:Hide()
            tomesHit:Hide()
        end
        needText:SetWidth(112)

        SetPoint(needText, "TOPLEFT", frame, "TOPLEFT", 12, contentTop - 58)
        local needLines = {}
        local shown = math.min(#missingNamesCache, 2)
        for i = 1, shown do
            -- Strip " (Poor:×N Common:×N ...)" from HUD label — quality
            -- breakdown is in the tooltip on mouseover instead.
            needLines[#needLines + 1] = missingNamesCache[i]:gsub("%s+%b()", "")
        end
        if #missingNamesCache > shown then needLines[#needLines + 1] = "+" .. (#missingNamesCache - shown) .. " more" end
        needText:SetText(#needLines > 0 and table.concat(needLines, "\n") or "|cff888888No remaining demand|r")

        SetPoint(shedLabel, "TOPLEFT", frame, "TOPLEFT", 142, contentTop - 42)
        SetPoint(shedText, "TOPLEFT", frame, "TOPLEFT", 142, contentTop - 58)
        shedText:SetWidth(108)
        local shedLines = {}
        local shedShown = math.min(#shedNamesCache, 2)
        for i = 1, shedShown do shedLines[#shedLines + 1] = shedNamesCache[i] end
        if #shedNamesCache > shedShown then shedLines[#shedLines + 1] = "+" .. (#shedNamesCache - shedShown) .. " more" end
        shedText:SetText(#shedLines > 0 and table.concat(shedLines, "\n") or "|cff888888None|r")

        if #toLockNamesCache > 0 then
            SetPoint(frame.toLockLabel, "TOPLEFT", frame, "TOPLEFT", 12, contentTop - 90)
            SetPoint(frame.toLockText, "TOPLEFT", frame, "TOPLEFT", 12, contentTop - 106)
            frame.toLockText:SetWidth(238)
            local toLockLines = {}
            local toLockShown = math.min(#toLockNamesCache, 2)
            for i = 1, toLockShown do toLockLines[#toLockLines + 1] = toLockNamesCache[i] end
            if #toLockNamesCache > toLockShown then
                toLockLines[#toLockLines + 1] = "+" .. (#toLockNamesCache - toLockShown) .. " more"
            end
            frame.toLockText:SetText(table.concat(toLockLines, ", "))
            frame.toLockLabel:Show()
            frame.toLockText:Show()
            frame.toLockHit:ClearAllPoints()
            frame.toLockHit:SetPoint("TOPLEFT", frame.toLockLabel, "TOPLEFT", -2, 2)
            frame.toLockHit:SetPoint("BOTTOMRIGHT", frame.toLockText, "BOTTOMRIGHT", 2, -2)
            frame.toLockHit:Show()
        else
            frame.toLockLabel:Hide()
            frame.toLockText:Hide()
            frame.toLockHit:Hide()
        end

        SetVisible(lkPersonalLabel, false)
    end

    if not noBuild then RenderPerformanceState(pr, complete, showPerformance) end

    LayoutServerStatus(complete and not noBuild)
    worldStatusBox._summary = DefensiveCopy(ss)
    if ss and (ss.tier or ss.mode or ss.ash or ss.gain or ss.intensity ~= nil) then
        local difficulty = ss.tier or ss.mode or "Difficulty"
        -- Parse and format the ash number for compact display
        local function FmtAsh(raw)
            if not raw then return "—" end
            local stripped = tostring(raw):gsub(",", "")
            local n = tonumber(stripped)
            if not n then return tostring(raw) end
            if n >= 1000000 then
                local m = n / 1000000
                local ms = string.format("%.1f", m); return (ms:match("%.0$") and ms:gsub("%.0$","") or ms) .. "M"
            elseif n >= 1000 then
                local k = n / 1000
                local ks = string.format("%.1f", k); return (ks:match("%.0$") and ks:gsub("%.0$","") or ks) .. "k"
            end
            return tostring(math.floor(n))
        end
        local ashFmt = FmtAsh(ss.ash)
        -- Tooltip keeps full unformatted value
        local ashFull = ss.ash and tostring(ss.ash):gsub(",","") or "—"
        worldStatusText:SetText("|cffff6b5f" .. difficulty .. "|r")
        worldStatusAsh:SetText((complete and "|cff8ec9d6Soul Ash  |r" or "|cffb8b8b8Ash |r") .. "|cffffffff" .. ashFmt .. "|r")
        worldStatusGain:SetText(ss.gain and ("|cff35e635" .. ss.gain .. "|r") or "")
        local intensity = math.max(0, math.min(500, tonumber(ss.intensity) or 0))
        local intensityLevel = tonumber(ss.intensityLevel) or math.floor(intensity / 100)
        worldStatusBox.intensityBar:SetMinMaxValues(0, 500)
        worldStatusBox.intensityBar:SetValue(intensity)
        worldStatusBox.intensityText:SetText("")
        worldStatusBox.intensityBar:Show()
        worldStatusBox:Show()
    else
        worldStatusText:SetText("")
        worldStatusAsh:SetText("")
        worldStatusGain:SetText("")
        worldStatusBox.intensityText:SetText("")
        worldStatusBox.intensityBar:Hide()
        worldStatusBox:Hide()
    end

    RenderBestDps(model, complete, noBuild, activeRoll, statusVisible)
    ApplyPanelLayout(responsiveLayout,complete)
    if frame._autoBtn:IsShown() then
        frame._autoBtn:SetText(AutoLabel(model.auto))
    end
    if frame and Nexus.Theme and Nexus.Theme.StyleTree
        and not frame._nexusHudTreeStyled then
        Nexus.Theme.StyleTree(frame)
        frame._nexusHudTreeStyled = true
        renderStats.themeTreeWalks = renderStats.themeTreeWalks + 1
    end
    return true
end

local function ApplyCandidate(model, signatures)
    if not frame.toLockLabel then CreateToLockWidgets(frame) end
    M.ApplyOwnedFonts()
    return ApplyModel(model, signatures)
end

function M.Render(model)
    if type(model) ~= "table" then return false end
    local candidate = DefensiveCopy(model)
    local signatures = ModelSignatures(candidate)
    renderStats.calls = renderStats.calls + 1
    EnsureFrame()

    -- A widget tree is a mutable object, so the visibility boundary is the
    -- transaction: hide while applying, and publish commit/model/signature
    -- state only after every required step succeeds.  On failure the prior
    -- immutable model remains the sole last-good owner and no partial tree is
    -- exposed.  Main retains the current input for the next ordinary retry.
    local previousModel = M._lastModel
    renderState.applying = true
    frame:Hide()
    local ok, result = pcall(ApplyCandidate, candidate, signatures)
    renderState.applying = false
    if not ok or result == false then
        M._lastModel = previousModel
        -- A mutating widget can fail after changing itself, so the old
        -- signature cannot certify the tree anymore.  Retain only the prior
        -- immutable model, keep the frame hidden, and force a complete apply
        -- on the next ordinary refresh.
        renderState.signatures = nil
        renderState.committed = false
        renderState.hadFailure = true
        renderStats.failures = renderStats.failures + 1
        frame:Hide()
        if not ok then error(result, 0) end
        return false
    end

    M._lastModel = candidate
    renderState.signatures = signatures
    renderState.committed = true
    renderStats.commits = renderStats.commits + 1
    if renderState.hadFailure then
        renderStats.recoveries = renderStats.recoveries + 1
        renderState.hadFailure = false
    end
    ApplyWantedVisibility()
    return true
end

function M.Refresh()
    if callbacks and type(callbacks.RefreshDisplay) == "function" then
        return callbacks.RefreshDisplay()
    end
    if M._lastModel then return M.Render(M._lastModel) end
    return false
end
function M.SetStatus(status)
    if not M._lastModel then return false end
    local nextStatus = SafeText(status)
    if SafeText(M._lastModel.status) == nextStatus then return false end
    M._lastModel.status = nextStatus
    if renderState.signatures then
        renderState.signatures.status = Signature(nextStatus)
    end
    renderStats.statusOnly = renderStats.statusOnly + 1
    return true
end
function M.RenderStats() return DefensiveCopy(renderStats) end
function M.Show()
    panelWantedVisible = true
    EnsureFrame()
    RequestDisplayRecovery()
    ApplyWantedVisibility()
end
function M.Hide() panelWantedVisible = false; if frame then frame:Hide() end end
function M.IsShown() return frame and frame:IsShown() or false end

return M
