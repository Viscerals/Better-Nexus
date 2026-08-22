-- Nexus: ui/WishlistRenderer.lua
-- Wishlist editor, display popup, menus, tooltips, and bounded visible-row owner.

Nexus = Nexus or {}
Nexus.WishlistInternals = Nexus.WishlistInternals or {}

local Renderer = {}

function Renderer.New(options)
    options = type(options) == "table" and options or {}
    local M = {}
    local Controller = assert(options.controller,
        "WishlistRenderer requires controller projections and intentions")
    local PendingFamily = assert(options.family,
        "WishlistRenderer requires Wishlist family identity")
    local DraftKey = assert(options.draftKey,
        "WishlistRenderer requires exact draft identity")
    local EchoListTotal = assert(options.echoListTotal,
        "WishlistRenderer requires Echo totals")
    local MaskMatch = type(options.maskMatch) == "function"
        and options.maskMatch or function() return true end
    local EntryProgress = type(options.entryProgress) == "function"
        and options.entryProgress or nil

    local syncFulfilled = type(options.syncFulfilled) == "function"
        and options.syncFulfilled or function() end
    local hideServerEchoUI = type(options.hideServerEchoUI) == "function"
        and options.hideServerEchoUI or function() end
    local overlayProvider = type(options.overlay) == "function"
        and options.overlay or function() return nil end
    local newWishlist = type(options.newWishlist) == "function"
        and options.newWishlist or function() end
    local openForWishlist = type(options.openForWishlist) == "function"
        and options.openForWishlist or function() end
    local pumpApplyRetry = type(options.pumpApplyRetry) == "function"
        and options.pumpApplyRetry or nil
    local requestRefresh = type(options.refresh) == "function"
        and options.refresh or function() return M.Refresh() end

    local MAX_ROWS = 19
    local PICK_ROWS = 18
    local ROW_HEIGHT = 24
    local MAX_WISHLIST_ECHOES = 79
    local MAX_LOCK_SLOTS = 6

    local QUALITY_COLORS = {
        [0] = { 1, 1, 1 },
        [1] = { 0.12, 1, 0.12 },
        [2] = { 0.2, 0.6, 1 },
        [3] = { 0.72, 0.36, 0.98 },
        [4] = { 1, 0.65, 0 },
    }

    local frame, rows, pickRows
    local searchBox, classCheck, applyBtn, footerText, pickFooterText
    local trackingText, candidateButtons
    local titleText, editContextText
    local wishlistNameLabel, wishlistNameBox
    local wishlistSwitchBtn, newWishlistBtn, wishlistSwitchMenu
    local loadoutSwitchBtn, loadoutSwitchMenu
    local lockedLabel, lockedIcons, lockedNeedIcons
    local autoLockCheck
    local displayPopup, displayCheck, displayLockBtn
    local refreshCache = {known=false}
    -- Renderer reads only controller-published projections. The controller
    -- remains the sole owner of Adapter access, associations, uploads, Store
    -- writes, preferences, retries, and mutable draft/session state.
    local View = {
        Catalog = function() return Controller.CatalogProjection() end,
        Owned = function() return Controller.OwnedProjection() end,
        LockedOwned = function() return Controller.LockedProjection() end,
        Wishlist = function() return Controller.WishlistProjection() end,
        GetWishlistCandidates = function()
            return Controller.WishlistCandidatesProjection()
        end,
        Slots = function() return Controller.SlotsProjection() end,
        GetLoadoutWishlist = function(slot)
            return Controller.LoadoutWishlistProjection(slot)
        end,
    }

    local function PendingRows() return Controller.PendingRows() end
    local function PendingLockRows() return Controller.PendingLockRows() end
    local function EditingContext() return Controller.EditingContext() end
    local function CreateTargetContext() return Controller.CreateTargetContext() end
    local function SyncFulfilledDraftTargets() return syncFulfilled() end

    local function PendingTotal()
        return Controller.PendingTotal()
    end

    local function SeedPendingFromWishlist()
        local result = Controller.SeedPendingFromWishlist()
        SyncFulfilledDraftTargets()
        return result
    end

    local function BuildAvailableList(catalog, catalogRevision)
        local filters = Controller.FilterState()
        local search = filters.search:lower()
        local classOnly = filters.classOnly
        if catalogRevision ~= nil and refreshCache.available
            and refreshCache.availableCatalog == catalogRevision
            and refreshCache.availableSearch == search
            and refreshCache.availableClassOnly == classOnly then
            return refreshCache.available
        end
        local out = {}
        local playerMask = catalog and catalog.playerMask
        for _, row in pairs((catalog and catalog.rows) or {}) do
            local okClass = (not classOnly)
                or MaskMatch(row.classMask, playerMask)
            local name = tostring(row.name or ""):lower()
            if okClass and (search == ""
                or name:find(search, 1, true)) then
                out[#out + 1] = row
            end
        end
        table.sort(out, function(a, b)
            return tostring(a.name or "") < tostring(b.name or "")
        end)
        if catalogRevision ~= nil then
            refreshCache.available = out
            refreshCache.availableCatalog = catalogRevision
            refreshCache.availableSearch = search
            refreshCache.availableClassOnly = classOnly
        else
            refreshCache.available = nil
        end
        return out
    end

    local function AddPending(row)
        return Controller.AddPending(row)
    end

    local function RemovePending(rowKey)
        return Controller.RemovePending(rowKey)
    end

    local function ToggleDesignLock(rowKey)
        local outcome = Controller.ToggleDesignLock(rowKey)
        SyncFulfilledDraftTargets()
        return outcome
    end

    local function AdjustStacks(rowKey, delta)
        return Controller.AdjustStacks(rowKey, delta)
    end

    local function AssignLockSlotFromData(data)
        local outcome = Controller.AssignLockSlot(data)
        SyncFulfilledDraftTargets()
        return outcome
    end


local function ApplyPending()
    local text = wishlistNameBox and tostring(wishlistNameBox:GetText() or "") or ""
    local data, mode = Controller.PrepareApply(text)
    if not data then
        if mode == "name" and wishlistNameBox then wishlistNameBox:SetFocus() end
        return
    end
    if mode == "update" then
        StaticPopup_Show("WISHLISTREALIZER_UPDATE_WISHLIST",
            EchoListTotal(data.echoes), data.name, data)
    else
        StaticPopup_Show("WISHLISTREALIZER_CREATE_WISHLIST",
            data.name, EchoListTotal(data.echoes), data)
    end
end


local function ShowEchoTooltip(owner, spellId, anchor)
    if not owner or not GameTooltip then return end

    local id = tonumber(spellId)
    GameTooltip:Hide()
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")

    -- Project Ebonhold runs on the 3.3.5 client. SetSpellByID is not a
    -- reliable tooltip API there; spell hyperlinks provide the complete
    -- server tooltip without breaking the row's mouse scripts.
    if id and GameTooltip.SetHyperlink then
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. tostring(id))
        if ok then
            GameTooltip:Show()
            return
        end
    end

    local name, _, icon = nil, nil, nil
    if id and GetSpellInfo then
        local ok, spellName, _, spellIcon = pcall(GetSpellInfo, id)
        if ok then
            name, icon = spellName, spellIcon
        end
    end

    GameTooltip:AddLine(name or ("Echo " .. tostring(id or "")), 1, 1, 1)
    if icon then
        GameTooltip:AddTexture(icon)
    end
    GameTooltip:Show()
end

local function SpellIcon(spellId)
    if not spellId then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    local ok, _, _, icon = pcall(GetSpellInfo, spellId)
    return (ok and icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function CandidateAssignment(candidate)
    return Controller.CandidateAssignment(candidate)
end

local function StyleWishlistSelector(button)
    button:SetNormalFontObject("GameFontHighlightSmall")
    button:SetHighlightFontObject("GameFontNormalSmall")
    button:SetPushedTextOffset(0, -1)
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
    local fs = button:GetFontString()
    if fs then
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", button, "LEFT", 9, 0)
        fs:SetPoint("RIGHT", button, "RIGHT", -22, 0)
        fs:SetJustifyH("LEFT")
    end
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(12,12)
    arrow:SetPoint("RIGHT", button, "RIGHT", -7, 0)
    button._arrow = arrow
end

local function HideWishlistSwitchMenu()
    if wishlistSwitchMenu then wishlistSwitchMenu:Hide() end
end

local function CandidateEvidenceSuffix(candidate)
    if type(candidate) == "table"
        and candidate.lockEvidenceStatus == "unavailable" then
        return "  |cffff9040(awaiting lock evidence)|r"
    end
    return ""
end

local function ShowWishlistSwitchMenu(anchor)
    if wishlistSwitchMenu and frame and wishlistSwitchMenu:GetParent() ~= frame then wishlistSwitchMenu:SetParent(frame) end
    local candidates = (View and View.GetWishlistCandidates and View.GetWishlistCandidates()) or {}
    local editingContext = EditingContext()
    if not wishlistSwitchMenu then
        wishlistSwitchMenu = CreateFrame("Frame", "NexusWishlistEditorSwitchMenu", frame or UIParent)
        wishlistSwitchMenu:SetFrameStrata("TOOLTIP")
        wishlistSwitchMenu:SetFrameLevel((frame and frame:GetFrameLevel() or 50) + 100)
        wishlistSwitchMenu:SetToplevel(true)
        wishlistSwitchMenu:EnableMouse(true)
        wishlistSwitchMenu.rows = {}
        pcall(function()
            wishlistSwitchMenu:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            wishlistSwitchMenu:SetBackdropColor(0.015, 0.02, 0.03, 0.99)
            wishlistSwitchMenu:SetBackdropBorderColor(0.48, 0.42, 0.25, 1)
        end)
    end
    local visible = math.min(#candidates, 10)
    wishlistSwitchMenu:SetSize(286, 18 + math.max(1, visible) * 24)
    wishlistSwitchMenu:ClearAllPoints()
    wishlistSwitchMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -3)
    for i = 1, math.max(1, visible) do
        local row = wishlistSwitchMenu.rows[i]
        if not row then
            -- Real template buttons stay visibly enabled and reliably clickable
            -- above the editor on 3.3.5 clients.
            row = CreateFrame("Button", nil, wishlistSwitchMenu)
            row:SetSize(270, 22)
            row:SetPoint("TOPLEFT", 8, -8 - ((i - 1) * 24))
            row:EnableMouse(true)
            row:RegisterForClicks("LeftButtonUp")
            row:SetFrameLevel(wishlistSwitchMenu:GetFrameLevel() + 2)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            local check = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            check:SetPoint("LEFT", 7, 0)
            check:SetText("+")
            check:Hide()
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", check, "RIGHT", 7, 0)
            label:SetPoint("RIGHT", row, "RIGHT", -7, 0)
            label:SetJustifyH("LEFT")
            row._check = check
            row._label = label
            wishlistSwitchMenu.rows[i] = row
        end
        local c = candidates[i]
        if c then
            local assignedSlot, assignedName = CandidateAssignment(c)
            local current = editingContext and ((editingContext.key and c.key == editingContext.key)
                or tonumber(editingContext.slot) == tonumber(c.slot))
            local wishlistLabel = tostring(c.name ~= "" and c.name or ("Wishlist " .. tostring(c.slot)))
            local suffix = assignedName and ("  |cff777777Assigned: " .. tostring(assignedName) .. "|r") or "  |cff666666Unassigned|r"
            row._label:SetText(wishlistLabel
                .. CandidateEvidenceSuffix(c) .. suffix)
            if current then
                row._check:SetText("+")
                row._check:SetTextColor(0.3,1,0.5)
                row._check:Show()
                row._label:SetTextColor(1,0.82,0.2)
            else
                row._check:Hide()
                row._label:SetTextColor(0.92,0.92,0.92)
            end
            row:Enable()
            -- Snapshot this row's values so each click opens the intended wishlist.
            local openCandidate = {
                slot = c.slot, name = c.name, key = c.key, echoes = c.echoes,
                lockEvidenceVersion = c.lockEvidenceVersion,
                lockEvidenceStatus = c.lockEvidenceStatus,
                loadoutName = assignedName or "Not assigned",
            }
            local openAssignedSlot = assignedSlot
            row:SetScript("OnClick", function()
                HideWishlistSwitchMenu()
                openForWishlist(openCandidate, openAssignedSlot)
            end)
            row:Show()
        else
            row._label:SetText("No saved wishlists found")
            row._label:SetTextColor(0.55,0.55,0.55)
            row._check:Hide()
            row:SetScript("OnClick", nil)
            row:SetScript("OnMouseDown", nil)
            row:Disable()
            row:Show()
        end
    end
    for i = math.max(1, visible) + 1, #wishlistSwitchMenu.rows do
        wishlistSwitchMenu.rows[i]:Hide()
    end
    wishlistSwitchMenu:Show()
end


local function HideLoadoutSwitchMenu()
    if loadoutSwitchMenu then loadoutSwitchMenu:Hide() end
end

local function LoadEditorForLoadout(slot)
    slot = tonumber(slot)
    if not slot then return end
    local ok, mode = Controller.SelectLoadout(slot)
    if not ok then return end
    SyncFulfilledDraftTargets()
    if mode == "wishlist" then
        hideServerEchoUI()
        if Nexus.Panel and Nexus.Panel.CloseOtherWindows then
            Nexus.Panel.CloseOtherWindows("NexusEditorFrame")
        end
        frame:Show()
        requestRefresh()
        return
    end
    if wishlistNameBox then wishlistNameBox:SetText("") end
    -- M.Show delegates here whenever a real Saved Build is active. An
    -- unassociated build is a valid new-wishlist destination, so this branch
    -- must show the editor just like OpenForWishlist does for linked builds.
    -- Without this, the Panel remains menu-suppressed while no editor appears.
    frame:Show()
    requestRefresh()
end

local function ShowLoadoutSwitchMenu(anchor)
    if loadoutSwitchMenu and frame and loadoutSwitchMenu:GetParent() ~= frame then loadoutSwitchMenu:SetParent(frame) end
    -- Saved Builds are the server's fixed slots 1-5. Build this selector
    -- directly from those slots instead of relying on inferred candidates.
    local slots = View and View.Slots and View.Slots()
    local active = slots and tonumber(slots.activeSlot) or 0
    local candidates = {}
    for slot = 1, 5 do
        local data = slots and slots.bySlot and slots.bySlot[slot]
        local name = data and tostring(data.name or "") or ""
        if name == "" then name = "Loadout " .. tostring(slot) end
        local linked = View and View.GetLoadoutWishlist and View.GetLoadoutWishlist(slot)
        candidates[#candidates + 1] = {
            slot = slot,
            name = name,
            active = active == slot,
            available = data ~= nil,
            wishlist = linked,
        }
    end
    if not loadoutSwitchMenu then
        loadoutSwitchMenu = CreateFrame("Frame", "NexusWishlistEditorLoadoutMenu", frame or UIParent)
        loadoutSwitchMenu:SetFrameStrata("TOOLTIP")
        loadoutSwitchMenu:SetFrameLevel((frame and frame:GetFrameLevel() or 50) + 101)
        loadoutSwitchMenu:SetToplevel(true)
        loadoutSwitchMenu:EnableMouse(true)
        loadoutSwitchMenu.rows = {}
        pcall(function()
            loadoutSwitchMenu:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            loadoutSwitchMenu:SetBackdropColor(0.015, 0.02, 0.03, 0.99)
            loadoutSwitchMenu:SetBackdropBorderColor(0.48, 0.42, 0.25, 1)
        end)
    end
    local visible = 5
    loadoutSwitchMenu:SetSize(230, 18 + math.max(1, visible) * 24)
    loadoutSwitchMenu:ClearAllPoints()
    loadoutSwitchMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -3)
    for i = 1, math.max(1, visible) do
        local row = loadoutSwitchMenu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, loadoutSwitchMenu)
            row:SetSize(214, 22)
            row:SetPoint("TOPLEFT", 8, -8 - ((i - 1) * 24))
            row:EnableMouse(true)
            row:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
            row:SetFrameLevel(loadoutSwitchMenu:GetFrameLevel() + 2)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", 8, 0)
            label:SetPoint("RIGHT", -8, 0)
            label:SetJustifyH("LEFT")
            row._label = label
            loadoutSwitchMenu.rows[i] = row
        end
        local c = candidates[i]
        if c then
            local label = tostring(c.name or "")
            if label == "" then label = "Saved Build " .. tostring(c.slot) end
            local suffix = c.wishlist and ("  |cff777777" .. tostring(c.wishlist.name or "Wishlist") .. "|r")
                or "  |cff666666No wishlist|r"
            row._label:SetText((c.active and "|cffffd200" or "|cffffffff") .. label .. "|r" .. suffix)
            local targetSlot = tonumber(c.slot)
            local alreadyActive = c.active == true
            if c.available then
                row:Enable()
                local function SelectLoadoutRow()
                    -- This selector chooses which Saved Build's association is
                    -- being edited. It intentionally does not activate the server
                    -- loadout; that action is level-gated and not required here.
                    HideLoadoutSwitchMenu()
                    HideWishlistSwitchMenu()
                    Controller.ClearPendingLoadoutOpen()
                    LoadEditorForLoadout(targetSlot)
                end
                row:SetScript("OnMouseDown", function(_, button)
                    if button == "LeftButton" then SelectLoadoutRow() end
                end)
                row:SetScript("OnClick", nil)
            else
                row:Disable()
                row:SetScript("OnClick", nil)
                row:SetScript("OnMouseDown", nil)
                row._label:SetText("|cff666666Loadout " .. tostring(targetSlot) .. "  Empty|r")
            end
            row:Show()
        else
            row._label:SetText("No saved loadouts found")
            row._label:SetTextColor(0.55,0.55,0.55)
            row:SetScript("OnClick", nil)
            row:Disable()
            row:Show()
        end
    end
    for i = math.max(1, visible) + 1, #loadoutSwitchMenu.rows do
        loadoutSwitchMenu.rows[i]:Hide()
    end
    loadoutSwitchMenu:Show()
end

------------------------------------------------------------------------
-- Display popup construction
------------------------------------------------------------------------

local function Overlay()
    return overlayProvider()
end

local function RefreshDisplayControls()
    local overlay = Overlay()
    if displayCheck and overlay then
        displayCheck:SetChecked(overlay.IsShown() == true)
        if displayLockBtn then
            displayLockBtn:SetText(overlay.IsLocked()
                and "Unlock to Move" or "Lock Position")
        end
    end
end

local function EnsureDisplayPopup()
    if displayPopup then return displayPopup end

    -- Always parent this dialog directly to UIParent. Parenting it to the
    -- editor made its visibility and mouse state depend on a much larger
    -- window, which could leave the popup visible but unable to receive
    -- clicks after the editor was hidden.
    local p = CreateFrame("Frame", "NexusDisplayPopup", UIParent)
    p:SetSize(300, 218)
    p:SetFrameStrata("TOOLTIP")
    p:SetFrameLevel(100)
    p:EnableMouse(true)
    if p.SetClampedToScreen then p:SetClampedToScreen(true) end
    p:Hide()

    pcall(function()
        p:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 24,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
        p:SetBackdropColor(0.04, 0.04, 0.04, 0.98)
    end)

    -- Only the title bar drags the dialog. Making the entire popup a drag
    -- target can steal mouse-down events from checkboxes, sliders and
    -- buttons on older clients.
    local dragBar = CreateFrame("Frame", nil, p)
    dragBar:SetPoint("TOPLEFT", 10, -8)
    dragBar:SetPoint("TOPRIGHT", -34, -8)
    dragBar:SetHeight(30)
    dragBar:SetFrameLevel(p:GetFrameLevel() + 1)
    dragBar:EnableMouse(true)
    dragBar:RegisterForDrag("LeftButton")
    p:SetMovable(true)
    dragBar:SetScript("OnDragStart", function() p:StartMoving() end)
    dragBar:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText("On-Screen Wishlist")

    local subtitle = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetSize(245, 28)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Show, position, and resize the wishlist list used while playing.")

    local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetFrameLevel(p:GetFrameLevel() + 5)
    close:SetScript("OnClick", function() p:Hide() end)

    displayCheck = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    displayCheck:SetPoint("TOPLEFT", 16, -68)
    displayCheck:SetFrameLevel(p:GetFrameLevel() + 5)
    displayCheck:EnableMouse(true)
    local initialOverlay = Overlay()
    displayCheck:SetChecked(initialOverlay
        and initialOverlay.IsShown() == true or false)
    displayCheck.text = displayCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    displayCheck.text:SetPoint("LEFT", displayCheck, "RIGHT", -2, 1)
    displayCheck.text:SetText("Show on-screen wishlist")
    displayCheck:SetScript("OnClick", function(self)
        local overlay = Overlay()
        if overlay then
            if self:GetChecked() then overlay.Show() else overlay.Hide() end
        end
    end)

    local moveLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    moveLabel:SetPoint("TOPLEFT", 18, -102)
    moveLabel:SetText("Position")

    displayLockBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    displayLockBtn:SetSize(92, 22)
    displayLockBtn:SetPoint("LEFT", moveLabel, "RIGHT", 16, 0)
    displayLockBtn:SetFrameLevel(p:GetFrameLevel() + 5)
    displayLockBtn:EnableMouse(true)
    displayLockBtn:SetScript("OnClick", function()
        local overlay = Overlay()
        if overlay then
            overlay.ToggleLock()
            displayLockBtn:SetText(overlay.IsLocked()
                and "Unlock to Move" or "Lock Position")
        end
    end)

    local resetBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    resetBtn:SetSize(100, 22)
    resetBtn:SetPoint("LEFT", displayLockBtn, "RIGHT", 10, 0)
    resetBtn:SetFrameLevel(p:GetFrameLevel() + 5)
    resetBtn:EnableMouse(true)
    resetBtn:SetText("Reset Position")
    resetBtn:SetScript("OnClick", function()
        local overlay = Overlay()
        if overlay and overlay.ResetPosition then
            overlay.ResetPosition()
            displayCheck:SetChecked(true)
        end
    end)

    local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 18, -128)
    hint:SetSize(260, 24)
    hint:SetJustifyH("LEFT")
    hint:SetText("Unlock to drag the list. Lock it when placed so the list does not block gameplay clicks.")

    local sizeLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizeLabel:SetPoint("TOPLEFT", 18, -164)
    sizeLabel:SetText("Size")

    local scaleMinus = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    scaleMinus:SetSize(22, 22)
    scaleMinus:SetPoint("LEFT", sizeLabel, "RIGHT", 22, 0)
    scaleMinus:SetFrameLevel(p:GetFrameLevel() + 5)
    scaleMinus:EnableMouse(true)
    scaleMinus:SetText("-")

    local scaleValueText = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scaleValueText:SetPoint("LEFT", scaleMinus, "RIGHT", 7, 0)
    scaleValueText:SetSize(48, 22)
    scaleValueText:SetJustifyH("CENTER")

    local scalePlus = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    scalePlus:SetSize(22, 22)
    scalePlus:SetPoint("LEFT", scaleValueText, "RIGHT", 7, 0)
    scalePlus:SetFrameLevel(p:GetFrameLevel() + 5)
    scalePlus:EnableMouse(true)
    scalePlus:SetText("+")

    local scaleSlider = CreateFrame("Slider", "NexusScaleSlider", p,
        "OptionsSliderTemplate")
    scaleSlider:SetSize(250, 16)
    scaleSlider:SetPoint("TOPLEFT", 20, -195)
    scaleSlider:SetFrameLevel(p:GetFrameLevel() + 5)
    scaleSlider:EnableMouse(true)
    pcall(function()
        scaleSlider:SetMinMaxValues(0.5, 1.6)
        scaleSlider:SetValueStep(0.02)
    end)

    local updatingDisplay = false
    local function RefreshScaleDisplay()
        local overlay = Overlay()
        if not overlay then return end
        local value = overlay.GetScale()
        updatingDisplay = true
        pcall(function() scaleSlider:SetValue(value) end)
        scaleValueText:SetText(string.format("%d%%",
            math.floor(value * 100 + 0.5)))
        updatingDisplay = false
    end

    scaleSlider:SetScript("OnValueChanged", function(_, value)
        if updatingDisplay then return end
        local overlay = Overlay()
        if overlay then overlay.SetScale(value) end
        RefreshScaleDisplay()
    end)
    scaleMinus:SetScript("OnClick", function()
        local overlay = Overlay()
        if overlay then overlay.SetScale(overlay.GetScale() - 0.02) end
        RefreshScaleDisplay()
    end)
    scalePlus:SetScript("OnClick", function()
        local overlay = Overlay()
        if overlay then overlay.SetScale(overlay.GetScale() + 0.02) end
        RefreshScaleDisplay()
    end)

    p:SetScript("OnShow", function(self)
        self:SetFrameStrata("TOOLTIP")
        self:SetFrameLevel(100)
        self:EnableMouse(true)
        RefreshDisplayControls()
        RefreshScaleDisplay()
    end)

    p.RefreshScaleDisplay = RefreshScaleDisplay
    displayPopup = p
    return p
end

local function HideDisplayPopup()
    if displayPopup then displayPopup:Hide() end
end

local function ToggleDisplayPopup(anchorTo)
    local p = EnsureDisplayPopup()
    if p:IsShown() then
        p:Hide()
        return
    end
    p:ClearAllPoints()
    if anchorTo and anchorTo.IsVisible and anchorTo:IsVisible() then
        p:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 0, -6)
    else
        p:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    p:Show()
end

------------------------------------------------------------------------
-- Frame construction
------------------------------------------------------------------------

local function EnsureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "NexusEditorFrame", UIParent)
    frame:SetClampedToScreen(true)
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "NexusEditorFrame")
    end
    frame:SetSize(1040, 680)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(50)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local refreshTicker = 0
    local applyTicker = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        applyTicker = applyTicker + (elapsed or 0)
        if applyTicker >= 0.5 then
            applyTicker = 0
            if pumpApplyRetry then pumpApplyRetry() end
        end
        refreshTicker = refreshTicker + (elapsed or 0)
        if refreshTicker >= 0.5 then
            refreshTicker = 0
            -- Go quiet during a PerkService sniff (/nexus sniff): this
            -- ticker's own View.Slots() polling (both the check below and
            -- inside M.Refresh() itself) would otherwise keep calling
            -- GetServerBuildSlots/GetServerActiveSlot/GetServerMaxSlots every
            -- half second regardless of Main.lua's own poll pause, flooding
            -- the 200-call ring buffer with noise unrelated to whatever the
            -- player is actually doing in the native lock UI.
            if not (Nexus and Nexus.sniffPaused) then
                hideServerEchoUI()
                local pendingLoadoutOpen = Controller.PendingLoadoutOpen()
                if pendingLoadoutOpen then
                    local slots = View and View.Slots and View.Slots()
                    local active = slots and tonumber(slots.activeSlot)
                    if active == tonumber(pendingLoadoutOpen.slot)
                        or (GetTime() - (pendingLoadoutOpen.at or 0)) >= 1.5 then
                        local target = pendingLoadoutOpen.slot
                        Controller.ClearPendingLoadoutOpen()
                        LoadEditorForLoadout(target)
                    end
                end
                local promoted, wishlistName =
                    Controller.RefreshWishlistEvidence(
                        wishlistNameBox and wishlistNameBox:GetText() or "")
                if promoted then
                    if wishlistNameBox then
                        wishlistNameBox:SetText(wishlistName or "")
                    end
                end
                requestRefresh()
            end
        end
    end)
    frame:SetScript("OnShow", function() hideServerEchoUI() end)
    frame:SetScript("OnHide", function()
        HideDisplayPopup()
        HideWishlistSwitchMenu()
        HideLoadoutSwitchMenu()
    end)
    frame:Hide()

    titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOP", 0, -14)
    titleText:SetText("Nexus Wishlist Editor")

    editContextText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    editContextText:SetPoint("TOP", titleText, "BOTTOM", 0, -4)
    editContextText:SetSize(900, 18)
    editContextText:SetJustifyH("CENTER")
    editContextText:SetText("Creating a new wishlist")

    wishlistNameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wishlistNameLabel:SetPoint("TOPLEFT", 34, -96)
    wishlistNameLabel:SetText("Wishlist name:")

    wishlistNameBox = CreateFrame("EditBox", "NexusWishlistNameInput", frame, "InputBoxTemplate")
    wishlistNameBox:SetSize(260, 22)
    wishlistNameBox:SetPoint("LEFT", wishlistNameLabel, "RIGHT", 10, 0)
    wishlistNameBox:SetAutoFocus(false)
    wishlistNameBox:SetMaxLetters(48)
    wishlistNameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    wishlistNameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local buildsNav = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    buildsNav:SetSize(88, 22)
    buildsNav:SetPoint("TOPLEFT", 18, -12)
    buildsNav:SetText("Builds")
    buildsNav:SetScript("OnClick", function()
        frame:Hide()
        if Nexus.CommunityBuilds then Nexus.CommunityBuilds.Show() end
    end)
    local boardNav = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    boardNav:SetSize(102, 22)
    boardNav:SetPoint("LEFT", buildsNav, "RIGHT", 4, 0)
    boardNav:SetText("Leaderboard")
    boardNav:SetScript("OnClick", function()
        frame:Hide()
        if Nexus.Leaderboard then Nexus.Leaderboard.Show() end
    end)
    local wishNav = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    wishNav:SetSize(92, 22)
    wishNav:SetPoint("LEFT", boardNav, "RIGHT", 4, 0)
    wishNav:SetText("|cffffd200Wishlists|r")
    wishNav:Disable()

    loadoutSwitchBtn = CreateFrame("Button", nil, frame)
    loadoutSwitchBtn:SetSize(230, 22)
    loadoutSwitchBtn:SetPoint("TOPLEFT", 34, -66)
    loadoutSwitchBtn:SetText("Loadout: choose build")
    StyleWishlistSelector(loadoutSwitchBtn)
    loadoutSwitchBtn:Enable()
    local loadoutFont = loadoutSwitchBtn:GetFontString()
    if loadoutFont then loadoutFont:SetTextColor(0.92, 0.92, 0.92) end
    loadoutSwitchBtn:SetScript("OnClick", function(self)
        HideWishlistSwitchMenu()
        if loadoutSwitchMenu and loadoutSwitchMenu:IsShown() then
            HideLoadoutSwitchMenu()
        else
            ShowLoadoutSwitchMenu(self)
        end
    end)
    loadoutSwitchBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Swap Saved Build", 1, 0.8, 0.3)
        GameTooltip:AddLine("Activate another server loadout and immediately edit its associated wishlist.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    loadoutSwitchBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    wishlistSwitchBtn = CreateFrame("Button", nil, frame)
    wishlistSwitchBtn:SetSize(270, 22)
    wishlistSwitchBtn:SetPoint("LEFT", loadoutSwitchBtn, "RIGHT", 8, 0)
    wishlistSwitchBtn:SetText("Choose wishlist to edit")
    StyleWishlistSelector(wishlistSwitchBtn)
    wishlistSwitchBtn:SetScript("OnClick", function(self)
        HideLoadoutSwitchMenu()
        if wishlistSwitchMenu and wishlistSwitchMenu:IsShown() then
            HideWishlistSwitchMenu()
        else
            ShowWishlistSwitchMenu(self)
        end
    end)
    wishlistSwitchBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Switch wishlist", 1, 0.8, 0.3)
        GameTooltip:AddLine("Open a different saved wishlist in this editor.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    wishlistSwitchBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    newWishlistBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    newWishlistBtn:SetSize(112, 22)
    newWishlistBtn:SetPoint("LEFT", wishlistSwitchBtn, "RIGHT", 8, 0)
    newWishlistBtn:SetText("+ New Wishlist")
    newWishlistBtn:SetScript("OnClick", function()
        HideWishlistSwitchMenu()
        newWishlist()
    end)

    -- Locked Echoes strip: the account's up to 6 permanent picks, PLUS an
    -- editable picker for slots that aren't really locked yet. Nexus has no
    -- server API to lock/unlock -- a real slot stays read-only (click jumps
    -- the search to it) -- but an empty or designed slot is fully editable
    -- right here: click empty to assign a target, click a gold (designed)
    -- slot to un-assign it. This is the dedicated slot picker requested in
    -- place of a lock toggle scattered across every row of the pick list.
    lockedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lockedLabel:SetPoint("TOPLEFT", 540, -130)
    lockedLabel:SetText("Locked:")
    lockedLabel:Hide()

    lockedIcons = {}
    for i = 1, 6 do
        local btn = CreateFrame("Button", nil, frame)
        btn:SetSize(18, 18)
        if i == 1 then
            btn:SetPoint("LEFT", lockedLabel, "RIGHT", 8, 0)
        else
            btn:SetPoint("LEFT", lockedIcons[i - 1], "RIGHT", 4, 0)
        end
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetAllPoints(btn)
        btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnEnter", function(self)
            if self.slotState == "empty" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Empty locked slot", 1, 1, 1)
                GameTooltip:AddLine("Click to choose an Echo to pursue for it.", 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            elseif self.spellId then
                ShowEchoTooltip(self, self.spellId, "ANCHOR_RIGHT")
                if self.slotState == "designed" then
                    GameTooltip:AddLine("Designed, not locked yet -- click to un-assign.", 1, 0.85, 0.3, true)
                    GameTooltip:Show()
                elseif self.slotState == "locked" then
                    if self.beingReplaced then
                        GameTooltip:AddLine("A replacement is designed for this slot (the gold icon) "
                            .. "-- Nexus will unlock this one and lock the new one in automatically "
                            .. "once it's acquired. Un-assign the gold Echo to cancel.", 1, 0.6, 0.4, true)
                    else
                        GameTooltip:AddLine("Left-click: find in catalog", 0.8, 0.8, 0.8, true)
                        GameTooltip:AddLine("Right-click: design a replacement for this slot", 0.8, 0.8, 0.8, true)
                    end
                    GameTooltip:Show()
                end
            end
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- GameAdapter.LockPerk/UnlockPerk (confirmed live via /nexus sniff,
        -- 2026-08-01) actually perform the lock/unlock -- this only lets
        -- the player START pursuing a replacement now, while the current
        -- one stays locked and useful; Main.lua's TryAutoLock unlocks the
        -- old one and locks the new one in automatically once it's owned.
        btn:SetScript("OnClick", function(self, mouseButton)
            if self.slotState == "locked" and mouseButton == "RightButton" then
                if self.spellId then
                    Controller.ToggleReplacementAssignment(self.spellId)
                    requestRefresh()
                end
                return
            end
            if self.slotState == "empty" then
                Controller.ToggleEmptyAssignment()
                requestRefresh()
                return
            end
            if self.slotState == "designed" then
                if self.draftKey then ToggleDesignLock(self.draftKey); requestRefresh() end
                return
            end
            if not self.spellId then return end
            local cat = View and View.Catalog and View.Catalog()
            local row = cat and cat.rows and cat.rows[self.spellId]
            if row and row.name and searchBox then
                searchBox:SetText(row.name)
            end
        end)
        btn:Hide()
        lockedIcons[i] = btn
    end

    -- "Needed" row: directly above each locked-slot icon (anchored to its
    -- TOP, not a same-row neighbor) -- only shown for a column whose
    -- current Echo has an active replacement designed, so "what you have
    -- vs. what you're working toward" reads as a simple stacked pair
    -- instead of two unrelated icons sitting side by side.
    lockedNeedIcons = {}
    for i = 1, 6 do
        local btn = CreateFrame("Button", nil, frame)
        btn:SetSize(14, 14)
        btn:SetPoint("BOTTOM", lockedIcons[i], "TOP", 0, 2)
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetAllPoints(btn)
        btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        btn.icon:SetVertexColor(1, 0.85, 0.3)
        btn:SetScript("OnEnter", function(self)
            if not self.spellId then return end
            ShowEchoTooltip(self, self.spellId, "ANCHOR_TOP")
            GameTooltip:AddLine("Designed to replace the Echo below -- click to un-assign.", 1, 0.85, 0.3, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:SetScript("OnClick", function(self)
            if self.draftKey then ToggleDesignLock(self.draftKey); requestRefresh() end
        end)
        btn:Hide()
        lockedNeedIcons[i] = btn
    end

    -- Auto-lock opt-in: off by default (controller-owned preference,
    -- see DefaultProfile.lua and Main.lua's TryAutoLock). Deliberately
    -- separate from the main automation switch -- a player may want full
    -- board automation without also handing Nexus this specific, more
    -- consequential write action (LockPerk/UnlockPerk). Sits in the open
    -- space to the right of the locked-slot icon strip.
    autoLockCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    autoLockCheck:SetSize(22, 22)
    autoLockCheck:SetPoint("LEFT", lockedIcons[6], "RIGHT", 26, 0)
    autoLockCheck:SetScript("OnClick", function(self)
        Controller.SetAutoLockEnabled(self:GetChecked() and true or false)
    end)
    autoLockCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Automate locked Echo slots", 1, 0.8, 0.3)
        GameTooltip:AddLine("Checked: Nexus locks/unlocks Echoes for your designed locked slots "
            .. "automatically once each is acquired.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Unchecked (default): Nexus only designs and pursues them -- you lock "
            .. "them in yourself in the character progression UI.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    autoLockCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local autoLockLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoLockLabel:SetPoint("LEFT", autoLockCheck, "RIGHT", 2, 0)
    autoLockLabel:SetText("Automate locked Echo slots")

    -- Nexus-native EBH1 import/export. Closures deliberately reference only
    -- the global StaticPopup_Show and a string literal -- no module-level
    -- upvalues added to this function (see the EnsureFrame upvalue-limit
    -- crash, Dev Test 17; Create() gets the same treatment on principle).
    local exportBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportBtn:SetSize(70, 22)
    exportBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, -100)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function() StaticPopup_Show("NEXUS_EXPORT_WISHLIST") end)

    local importBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importBtn:SetSize(70, 22)
    importBtn:SetPoint("RIGHT", exportBtn, "LEFT", -4, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function() StaticPopup_Show("NEXUS_IMPORT_WISHLIST") end)

    -- Tracking status: shows EXACTLY what the addon currently believes
    -- the active wishlist is, rather than a bare "no wishlist" that reads
    -- as "you have none" when really it can also mean "you have several
    -- and none is marked active" (2026-07-24 -- this was silently
    -- swallowed before; A.GetWishlistCandidates() surfaces it properly).
    trackingText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    trackingText:SetPoint("TOP", 0, -96)
    trackingText:SetSize(900, 16)
    trackingText:SetJustifyH("CENTER")

    -- Shown only when multiple designed wishlists exist and none is
    -- active -- one button per candidate, click to make it the active one.
    candidateButtons = {}
    for i = 1, 4 do
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(115, 20)
        b:SetPoint("TOP", frame, "TOP", -180 + ((i - 1) * 121), -112)
        b:Hide()
        candidateButtons[i] = b
    end

    -- Overlay controls, moved to the top-right where they're actually
    -- visible instead of buried at the bottom of a long window.
    local displayBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    displayBtn:SetSize(150, 22)
    displayBtn:SetPoint("TOPRIGHT", -34, -66)
    displayBtn:SetText("Display Settings")
    displayBtn:SetScript("OnClick", function(self) ToggleDisplayPopup(self) end)
    displayBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("On-screen wishlist settings", 1, 1, 1)
        GameTooltip:AddLine("Show/hide the always-on-screen list, and lock/unlock", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("it for moving.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    displayBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    searchBox = CreateFrame("EditBox", "NexusEditorSearch", frame,
        "InputBoxTemplate")
    searchBox:SetSize(330, 22)
    searchBox:SetPoint("TOPLEFT", 34, -126)
    searchBox:SetAutoFocus(false)
    searchBox:SetText(Controller.FilterState().search)
    searchBox:SetScript("OnTextChanged", function(self)
        Controller.SetSearch(self:GetText() or "")
        requestRefresh()
    end)

    classCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    classCheck:SetPoint("LEFT", searchBox, "RIGHT", 18, 0)
    classCheck:SetChecked(Controller.FilterState().classOnly)
    classCheck.text = classCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    classCheck.text:SetPoint("LEFT", classCheck, "RIGHT", -2, 1)
    classCheck.text:SetText("Current class only")
    classCheck:SetScript("OnClick", function(self)
        Controller.SetClassOnly(self:GetChecked() and true or false)
        requestRefresh()
    end)

    -- Opens Nexus Builds directly -- our own working community-sharing
    -- system (core/Sync.lua), not a best-effort guess at the game's own
    -- UI. That guess-based version is retired now that we have a real one.
    local communityBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    communityBtn:SetSize(140, 22)
    communityBtn:SetPoint("TOPRIGHT", -34, -126)
    communityBtn:SetText("Nexus Builds")
    communityBtn:SetScript("OnClick", function()
        Controller.OpenCommunity()
    end)
    communityBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Browse and post shared wishlists", 1, 1, 1)
        GameTooltip:AddLine("Opens Nexus Builds -- see what other players running", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Nexus have posted, or share your own.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    communityBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    communityBtn:Hide()

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header:SetPoint("TOPLEFT", 34, -158)
    header:SetText("Choose Echoes from the catalog. A wishlist can contain up to 79 total Echoes; + / - adjusts stack copies.")

    -- Left: browsable catalog -----------------------------------------
    local leftArea = CreateFrame("Frame", nil, frame)
    leftArea:SetPoint("TOPLEFT", 34, -180)
    leftArea:SetSize(600, MAX_ROWS * ROW_HEIGHT)
    leftArea:EnableMouseWheel(true)
    leftArea:SetScript("OnMouseWheel", function(_, delta)
        Controller.AdjustScroll(delta)
        requestRefresh()
    end)

    rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, leftArea)
        row:SetSize(600, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))
        row:EnableMouse(true)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            Controller.AdjustScroll(delta)
            requestRefresh()
        end)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 0, 0)
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.text:SetSize(420, ROW_HEIGHT)
        row.text:SetJustifyH("LEFT")

        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.status:SetPoint("RIGHT", row, "RIGHT", -12, 0)
        row.status:SetSize(110, ROW_HEIGHT)
        row.status:SetJustifyH("RIGHT")

        row:SetScript("OnEnter", function(self)
            if not self.data then return end
            ShowEchoTooltip(self, self.data.spellId, "ANCHOR_RIGHT")
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            if not self.data then return end
            if Controller.IsAssigningLockSlot() then
                AssignLockSlotFromData(self.data)
                Controller.EndAssignment()
            else
                AddPending(self.data)
            end
            requestRefresh()
        end)

        rows[i] = row
    end

    footerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footerText:SetPoint("BOTTOMLEFT", 34, 26)
    footerText:SetJustifyH("LEFT")

    -- Right: pending picks ----------------------------------------------
    local pickTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pickTitle:SetPoint("TOPLEFT", 674, -158)
    pickTitle:SetText("Selected Echoes")

    local pickArea = CreateFrame("Frame", nil, frame)
    pickArea:SetPoint("TOPLEFT", 674, -180)
    pickArea:SetSize(332, PICK_ROWS * ROW_HEIGHT)
    pickArea:EnableMouseWheel(true)
    pickArea:SetScript("OnMouseWheel", function(_, delta)
        Controller.AdjustPick(delta)
        requestRefresh()
    end)

    pickRows = {}
    for i = 1, PICK_ROWS do
        local row = CreateFrame("Button", nil, pickArea)
        row:SetSize(332, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))
        row:EnableMouse(true)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            Controller.AdjustPick(delta)
            requestRefresh()
        end)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 0, 0)
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetSize(224, ROW_HEIGHT)
        row.text:SetJustifyH("LEFT")

        row.minus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.minus:SetSize(22, 20); row.minus:SetPoint("RIGHT", -48, 0); row.minus:SetText("-")
        row.plus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.plus:SetSize(22, 20); row.plus:SetPoint("RIGHT", -24, 0); row.plus:SetText("+")
        row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        row.remove:SetSize(22, 22); row.remove:SetPoint("RIGHT", 0, 0)
        row.minus:SetScript("OnClick", function(self)
            local d = self:GetParent().data
            if d and not d.ghost then AdjustStacks(d.draftKey, -1); requestRefresh() end
        end)
        row.plus:SetScript("OnClick", function(self)
            local d = self:GetParent().data
            if d and not d.ghost then AdjustStacks(d.draftKey, 1); requestRefresh() end
        end)
        row.remove:SetScript("OnClick", function(self)
            local d = self:GetParent().data
            if d and not d.ghost then
                RemovePending(d.draftKey or d.family)
                requestRefresh()
            end
        end)

        row:SetScript("OnEnter", function(self)
            if not self.data then return end
            ShowEchoTooltip(self, self.data.spellId, "ANCHOR_LEFT")
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Only meaningful while assign mode is active (see the locked-slot
        -- strip): assigns an already-selected, not-yet-designed Echo to the
        -- open slot. A no-op otherwise, so clicking here normally still
        -- does nothing -- adjustment stays on the +/-/X buttons.
        row:SetScript("OnClick", function(self)
            if not Controller.IsAssigningLockSlot() then return end
            local d = self.data
            if not d or d.ghost or d.toLock or d.lockIntent then return end
            ToggleDesignLock(d.draftKey or d.family)
            Controller.EndAssignment()
            requestRefresh()
        end)

        pickRows[i] = row
    end

    pickFooterText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pickFooterText:SetPoint("BOTTOMLEFT", 674, 56)
    pickFooterText:SetJustifyH("LEFT")

    -- Apply remains a presentation binding: the controller prepares and
    -- submits only after the established confirmation popup is accepted.
    applyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    applyBtn:SetSize(332, 26)
    applyBtn:SetPoint("BOTTOMLEFT", 674, 24)
    applyBtn:SetText("Create Wishlist")
    applyBtn:SetScript("OnClick", ApplyPending)
    applyBtn:SetScript("OnEnter", function(self)
        local editingContext = EditingContext()
        local blocked = Controller.ApplyBlockReason()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(editingContext and "Save this associated wishlist" or "Create a server wishlist", 1, 0.8, 0.3)
        GameTooltip:AddLine(blocked and ("Unavailable: " .. tostring(blocked)) or (editingContext and
            ("Edits only: " .. tostring(editingContext.name or "Wishlist")) or
            "Uploads the pending Echo list as a new server wishlist."), 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("A confirmation is shown before anything is replaced.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    applyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Cosmetic only, deliberately last: every functional widget above
    -- already exists regardless of whether this succeeds (this exact
    -- ordering mistake -- a cosmetic call sitting BEFORE pickRows/
    -- applyBtn -- was why they never got created when SetColorTexture
    -- threw, live 2026-07-24).
    pcall(function()
        local divider = frame:CreateTexture(nil, "ARTWORK")
        divider:SetTexture(0.35, 0.35, 0.35, 0.65)
        divider:SetSize(1, 456)
        divider:SetPoint("TOPLEFT", 652, -180)
    end)

    -- Background -- this was simply never added (not a crash, just an
    -- oversight, 2026-07-24). Separate pcall from the divider above so
    -- either one failing can't take out the other.
    pcall(function()
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end)

    return frame
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------

local function RefreshView(catalogRevision)
    if not frame then return end
    SeedPendingFromWishlist()

    local catalog = View and View.Catalog and View.Catalog()
    local owned = View and View.Owned and View.Owned()
    local ownedBySpell = (owned and owned.bySpell) or {}

    -- Read once per refresh, reused by the strip below, the catalog row
    -- loop further down (so an already-locked Echo shows "Locked" instead
    -- of an addable status there too), and the footer count -- one live
    -- source of truth instead of the load-time-only lastLockedSkipped.
    local lockedBySpell = {}
    if View and View.LockedOwned then
        local locked = View.LockedOwned()
        if locked and locked.synced == true
            and type(locked.bySpell) == "table" then
            lockedBySpell = locked.bySpell
        end
    end
    local lockedCount = 0
    for _, count in pairs(lockedBySpell) do
        count = tonumber(count)
        if not count or count <= 0 or count >= math.huge
            or count ~= math.floor(count) then
            lockedBySpell = {}
            lockedCount = 0
            break
        end
        lockedCount = lockedCount + count
    end

    -- Reconcile "awaiting lock" against reality: the moment LockedOwned()
    -- confirms one of these is actually locked, it belongs in the strip
    -- above instead, not here anymore -- drop it from the DRAFT (pendingLock/
    -- pending) so the UI stops showing it as still needing a lock.
    --
    -- Deliberately NOT clearing it from the COMMITTED store anymore (this
    -- used to also do `designTargets[id] = nil` here). Confirmed live: once
    -- TryAutoLock's own per-tick "wanted" check (core/Main.lua) is computed
    -- FROM the committed store, deleting a fulfilled entry from that store
    -- makes it invisible to that check on the very next tick -- so a design
    -- that had just been successfully locked in immediately looked like an
    -- Echo the wishlist doesn't want at all, and the eager shed pass
    -- unlocked it right back out again 10-20s later. Repeated for every
    -- design in turn: lock, vanish from the committed set, get shed, lock
    -- something else, repeat -- never converging on a stable 6 locked
    -- Echoes. Leaving fulfilled entries in the committed store is harmless
    -- (isLocked already skips re-processing them everywhere that reads it)
    -- and the table gets a full, clean replace on every real Save anyway
    -- (CommitLockDesignTargets), so there was never a real need to prune it
    -- here at all.
    Controller.ReconcileLocked(lockedBySpell)
    SyncFulfilledDraftTargets()
    local pending = PendingRows()
    local pendingLock = PendingLockRows()
    local editingContext = EditingContext()
    local createTargetContext = CreateTargetContext()
    local pendingLoadoutOpen = Controller.PendingLoadoutOpen()
    local scrollOffset = Controller.ScrollOffset()
    local pickOffset = Controller.PickOffset()

    -- Locked-slot targets remain separate from the ordinary 79-copy list.
    -- core/Main.lua injects every committed target into the live plan, so no
    -- promotion into `pending` is required when wishlist room opens.

    -- Locked Echoes strip: the dedicated slot picker. Real locked slots
    -- come from View.LockedOwned/GetLockedPerks; when both automation
    -- switches are enabled, core/Main.lua reconciles them with LockPerk and
    -- UnlockPerk. Each real-locked column gets its
    -- own STABLE position; a designed replacement for it (right-click, or
    -- auto-paired on import -- see LoadPendingEchoes) renders directly
    -- ABOVE that exact column in lockedNeedIcons, not beside it, so
    -- current-vs-needed reads as one stacked pair instead of two icons
    -- that happen to sit in the same row. A designed target that ISN'T
    -- replacing anything (bound for a genuinely open slot) fills the next
    -- open column in the bottom row instead.
    if lockedLabel and lockedIcons then
        local realIds, realSlots = {}, {}
        for id in pairs(lockedBySpell) do realIds[#realIds + 1] = id end
        table.sort(realIds)
        for _, id in ipairs(realIds) do
            for _ = 1, lockedBySpell[id] do
                realSlots[#realSlots + 1] = id
            end
        end

        -- Replacement pairing reads straight off each draft entry's own
        -- .replaces field now (set by LoadPendingEchoes/ToggleDesignLock/
        -- AssignLockSlotFromData) -- no separate committed-store lookup
        -- needed for what's still just being designed in this session.
        local designed = {}
        local function AddDesigned(p, rowKey, copies)
            copies = math.max(1, tonumber(copies) or 1)
            for copyIndex = 1, copies do
                local row = catalog and catalog.rows and catalog.rows[p.spellId]
                designed[#designed + 1] = {
                    spellId=p.spellId,family=p.family,draftKey=rowKey,
                    name=(row and row.name) or p.name
                        or ("spell " .. tostring(p.spellId)),
                    replaces=copyIndex == 1 and p.replaces or nil,
                }
            end
        end
        for rowKey, p in pairs(pending) do
            if p.lockIntent then
                AddDesigned(p, rowKey, 1)
            end
        end
        for fam, p in pairs(pendingLock) do
            AddDesigned(p, fam, p.stacks)
        end
        table.sort(designed, function(a, b)
            local left, right = tostring(a.name), tostring(b.name)
            if left ~= right then return left < right end
            return (tonumber(a.spellId) or 0) < (tonumber(b.spellId) or 0)
        end)

        local replacementFor, freshDesigned = {}, {}
        for _, d in ipairs(designed) do
            if type(d.replaces) == "number" then
                replacementFor[d.replaces] = d
            else
                freshDesigned[#freshDesigned + 1] = d
            end
        end

        -- Always show all MAX_LOCK_SLOTS slots, not just however many are
        -- currently locked -- an account with 5/6 locked was rendering as
        -- "Locked (5):" with no visible hint a 6th slot even existed.
        lockedLabel:SetText(string.format("Locked (%d/%d):", lockedCount, MAX_LOCK_SLOTS))
        lockedLabel:Show()
        local fi = 1
        for i = 1, MAX_LOCK_SLOTS do
            local btn, needBtn = lockedIcons[i], lockedNeedIcons[i]
            local id = realSlots[i]
            if id then
                local row = catalog and catalog.rows and catalog.rows[id]
                local replacement = replacementFor[id]
                replacementFor[id] = nil
                btn.spellId = id
                btn.draftKey = nil
                btn.slotState = "locked"
                btn.beingReplaced = replacement and true or nil
                btn.icon:SetTexture(SpellIcon(id))
                if replacement then
                    -- Dimmed: a replacement is already designed, directly above.
                    btn.icon:SetVertexColor(0.42, 0.42, 0.42)
                    needBtn.spellId = replacement.spellId
                    needBtn.draftKey = replacement.draftKey
                    needBtn.icon:SetTexture(SpellIcon(replacement.spellId))
                    needBtn:Show()
                else
                    if row then
                        local c = QUALITY_COLORS[tonumber(row.quality) or 0] or { 1, 1, 1 }
                        btn.icon:SetVertexColor(c[1], c[2], c[3])
                    else
                        btn.icon:SetVertexColor(1, 1, 1)
                    end
                    needBtn.spellId = nil
                    needBtn.draftKey = nil
                    needBtn:Hide()
                end
                btn:Show()
            elseif freshDesigned[fi] then
                local d = freshDesigned[fi]
                fi = fi + 1
                btn.spellId = d.spellId
                btn.draftKey = d.draftKey
                btn.slotState = "designed"
                btn.beingReplaced = nil
                btn.icon:SetTexture(SpellIcon(d.spellId))
                btn.icon:SetVertexColor(1, 0.85, 0.3)
                btn:Show()
                needBtn.spellId = nil
                needBtn.draftKey = nil
                needBtn:Hide()
            else
                -- An open, unused locked slot -- shown as an empty outline
                -- and directly clickable to assign a pursuit target.
                btn.spellId = nil
                btn.draftKey = nil
                btn.slotState = "empty"
                btn.beingReplaced = nil
                btn.icon:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Transparent")
                btn.icon:SetVertexColor(1, 1, 1)
                btn:Show()
                needBtn.spellId = nil
                needBtn.draftKey = nil
                needBtn:Hide()
            end
        end
    end

    if autoLockCheck then
        autoLockCheck:SetChecked(Controller.AutoLockEnabled())
    end

    -- Tracking status: show EXACTLY what's active, or why nothing is,
    -- rather than a bare "no wishlist" that reads as "you have none"
    -- when it might really mean "you have several, pick one".
    local wl = View and View.Wishlist and View.Wishlist()
    if wl then
        trackingText:SetText(string.format("|cff4dff80Tracking:|r '%s' (%s, %d echoes)",
            (wl.name ~= "" and wl.name) or "(unnamed)", tostring(wl.source), EchoListTotal(wl.entries)))
        for _, b in ipairs(candidateButtons) do b:Hide() end
    else
        local candidates = (View and View.GetWishlistCandidates
            and View.GetWishlistCandidates()) or {}
        if #candidates > 1 then
            local awaiting = 0
            for _, candidate in ipairs(candidates) do
                if candidate.lockEvidenceStatus == "unavailable" then
                    awaiting = awaiting + 1
                end
            end
            trackingText:SetText(awaiting > 0 and string.format(
                "|cffff9040%d wishlists found|r -- %d awaiting lock evidence; choose an available one to assign:",
                #candidates, awaiting) or string.format(
                "|cffff9040%d wishlists found|r -- click one to assign it to the active loadout:",
                #candidates))
            for i, b in ipairs(candidateButtons) do
                local c = candidates[i]
                if c then
                    b:SetText(string.format("%s (%d)%s",
                        (c.name ~= "" and c.name) or ("Slot " .. tostring(c.slot)),
                        c.count, CandidateEvidenceSuffix(c)))
                    b:SetScript("OnClick", function()
                        local ok, err, active, firstRun =
                            Controller.AssociateCandidate(c)
                        if ok then
                            if firstRun then
                                print("|cff4dff80Nexus:|r selected '" .. tostring(c.name)
                                    .. "' as the first-run wishlist.")
                            else
                                print("|cff4dff80Nexus:|r associated '" .. tostring(c.name)
                                    .. "' with Loadout " .. tostring(active) .. ".")
                            end
                            requestRefresh()
                        else
                            print("|cffff6060Nexus:|r " .. tostring(err or
                                "activate a real saved loadout first"))
                        end
                    end)
                    b:Show()
                else
                    b:Hide()
                end
            end
        elseif #candidates == 1 then
            -- Exactly one candidate but not yet flagged active by the
            -- server. Identity-only content stays visible without implying
            -- that it is safe to assign before lock evidence arrives.
            trackingText:SetText(candidates[1].lockEvidenceStatus == "unavailable"
                and "|cffff9040Found a wishlist identity|r -- awaiting lock evidence before it can be assigned:"
                or "|cffff9040Found a wishlist|r -- click to assign it to the active loadout:")
            candidateButtons[1]:SetText((candidates[1].name ~= "" and candidates[1].name
                or ("Slot " .. tostring(candidates[1].slot)))
                .. CandidateEvidenceSuffix(candidates[1]))
            candidateButtons[1]:SetScript("OnClick", function()
                local ok, err, active, firstRun =
                    Controller.AssociateCandidate(candidates[1])
                if ok then
                    if firstRun then
                        print("|cff4dff80Nexus:|r selected '"
                            .. tostring(candidates[1].name)
                            .. "' as the first-run wishlist.")
                    else
                        print("|cff4dff80Nexus:|r associated '"
                            .. tostring(candidates[1].name)
                            .. "' with Loadout " .. tostring(active) .. ".")
                    end
                    requestRefresh()
                else
                    print("|cffff6060Nexus:|r " .. tostring(err or
                        "activate a real saved loadout first"))
                end
            end)
            candidateButtons[1]:Show()
            for i = 2, #candidateButtons do candidateButtons[i]:Hide() end
        else
            trackingText:SetText("|cff888888No wishlist yet|r -- build one below, or check Nexus Builds.")
            for _, b in ipairs(candidateButtons) do b:Hide() end
        end
    end

    if titleText and editContextText then
        if editingContext then
            titleText:SetText("Edit Wishlist")
            local buildLabel = editingContext.loadoutName
                or (editingContext.loadoutSlot and ("Saved Build " .. tostring(editingContext.loadoutSlot)))
                or "Not assigned"
            editContextText:SetText("Wishlist: |cff7fd5ff" .. tostring(editingContext.name or "Wishlist") .. "|r   •   Assigned to: |cffffffff" .. tostring(buildLabel) .. "|r")
        else
            titleText:SetText("Create New Wishlist")
            if createTargetContext then
                editContextText:SetText("New destination for |cffffffff"
                    .. tostring(createTargetContext.loadoutName or "Active Saved Build")
                    .. "|r — it will be associated automatically after saving")
            else
                editContextText:SetText("Create a new destination wishlist for your first run")
            end
        end
    end

    if loadoutSwitchBtn and not pendingLoadoutOpen then
        local slots = View and View.Slots and View.Slots()
        local selected = editingContext and tonumber(editingContext.loadoutSlot)
            or (createTargetContext and tonumber(createTargetContext.loadoutSlot))
            or (slots and tonumber(slots.activeSlot))
        local selectedRow = selected and slots and slots.bySlot and slots.bySlot[selected]
        local selectedName = selectedRow and tostring(selectedRow.name or "") or ""
        if selected and selected > 0 then
            if selectedName == "" then selectedName = "Saved Build " .. tostring(selected) end
            loadoutSwitchBtn:SetText("Loadout: " .. selectedName)
        else
            loadoutSwitchBtn:SetText("Loadout: choose build")
        end
    end

    if wishlistSwitchBtn then
        if editingContext then
            wishlistSwitchBtn:SetText("Editing: " .. tostring(editingContext.name or "Wishlist"))
        else
            wishlistSwitchBtn:SetText("New Wishlist  -  choose another")
        end
    end

    if wishlistNameLabel and wishlistNameBox then
        if editingContext then
            wishlistNameLabel:Hide()
            wishlistNameBox:Hide()
            trackingText:Hide()
            for _, b in ipairs(candidateButtons or {}) do b:Hide() end
        else
            wishlistNameLabel:Show()
            wishlistNameBox:Show()
            trackingText:Hide()
            for _, b in ipairs(candidateButtons or {}) do b:Hide() end
        end
    end

    RefreshDisplayControls()

    local available = BuildAvailableList(catalog, catalogRevision)
    scrollOffset = Controller.ClampScroll(#available, MAX_ROWS)
    for i, row in ipairs(rows) do
        local data = available[scrollOffset + i]
        row.data = data
        if data then
            row:Show()
            row.icon:SetTexture(SpellIcon(data.spellId))
            local c = QUALITY_COLORS[data.quality] or QUALITY_COLORS[0]
            row.text:SetTextColor(c[1], c[2], c[3])
            local chosen = pending[DraftKey(data.spellId, catalog)]
            local suffix = ""
            if chosen and tonumber(chosen.spellId) == tonumber(data.spellId) then
                suffix = "  |cff4dff80(selected)|r"
            end
            row.text:SetText(data.name .. suffix)
            local exactProgress = EntryProgress and EntryProgress({{
                spellId=data.spellId,quality=data.quality,stacks=1,locked=false,
            }}, owned, nil) or nil
            local ownedCount = exactProgress and exactProgress.rows
                and exactProgress.rows[1] and exactProgress.rows[1].have
                or ownedBySpell[data.spellId] or 0
            local isLocked = (tonumber(lockedBySpell[data.spellId]) or 0) > 0
            local qualityName = ({ [0] = "Common", [1] = "Uncommon", [2] = "Rare", [3] = "Epic", [4] = "Legendary" })[tonumber(data.quality) or 0] or "Echo"
            if isLocked then
                -- Permanently secured -- never needs a wishlist slot again.
                -- Distinct from RollStatus's unrelated "locked" (tome-gated).
                row.status:SetText("|cffb266ffLocked|r")
            elseif chosen and tonumber(chosen.spellId) == tonumber(data.spellId) then
                row.status:SetText("|cff4dff80Selected|r")
            elseif ownedCount > 0 then
                row.status:SetText("|cffffd200" .. qualityName .. " · Owned|r")
            else
                row.status:SetText("|cffb8b8b8" .. qualityName .. "|r")
            end
        else
            row:Hide()
        end
    end
    local availableFamilies = {}
    for _, r in ipairs(available) do
        availableFamilies[PendingFamily(r.spellId, catalog)] = true
    end
    local uniqueAvailable = 0
    for _ in pairs(availableFamilies) do uniqueAvailable = uniqueAvailable + 1 end
    footerText:SetText(string.format("Showing %d-%d of %d variants  •  %d Echo names",
        math.min(scrollOffset + 1, #available), math.min(#available, scrollOffset + MAX_ROWS),
        #available, uniqueAvailable))

    local list = {}
    local designedCount = 0
    for rowKey, p in pairs(pending) do
        local row = catalog and catalog.rows and catalog.rows[p.spellId]
        list[#list + 1] = { spellId = p.spellId, family = p.family, stacks = p.stacks,
            draftKey = rowKey,
            maxStack = p.maxStack, quality = p.quality, lockIntent = p.lockIntent,
            name = (row and row.name) or ("spell " .. p.spellId), replaces = p.replaces }
        if p.lockIntent then designedCount = designedCount + 1 end
    end
    table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
    -- Locked-slot designs are listed separately after the ordinary 79-copy
    -- wishlist. They are committed locally and injected into automation, not
    -- uploaded as ordinary server-wishlist entries.
    local toLockList, toLockCount = {}, 0
    for key, p in pairs(pendingLock) do
        local copies = math.max(1, tonumber(p.stacks) or 1)
        toLockList[#toLockList + 1] = { spellId = p.spellId, family = p.family,
            draftKey = key,
            stacks = copies, maxStack = copies, quality = p.quality, name = p.name, toLock = true,
            replaces = p.replaces }
        toLockCount = toLockCount + copies
    end
    table.sort(toLockList, function(a, b)
        local left, right = tostring(a.name), tostring(b.name)
        if left ~= right then return left < right end
        return (tonumber(a.spellId) or 0) < (tonumber(b.spellId) or 0)
    end)
    for _, e in ipairs(toLockList) do list[#list + 1] = e end
    local realEntryCount = #list
    -- An entry designed to REPLACE a specific currently-real-locked Echo
    -- (.replaces -- see LoadPendingEchoes/ToggleDesignLock/
    -- AssignLockSlotFromData) got no visual pairing here at all before --
    -- just an easy-to-miss "(locked slot)"/"(awaiting lock)" tag, with
    -- nothing showing WHICH real slot it targets. Splice a read-only row for
    -- the Echo being replaced directly after it, mirroring the Locked strip
    -- above (which already stacks the replacement directly above the real
    -- slot it targets) so the pairing reads as one adjacent pair here too.
    do
        local withGhosts = {}
        for _, e in ipairs(list) do
            withGhosts[#withGhosts + 1] = e
            if type(e.replaces) == "number" then
                local oldRow = catalog and catalog.rows and catalog.rows[e.replaces]
                withGhosts[#withGhosts + 1] = {
                    spellId = e.replaces,
                    quality = oldRow and tonumber(oldRow.quality) or 0,
                    name = (oldRow and oldRow.name) or ("spell " .. tostring(e.replaces)),
                    ghost = true,
                }
            end
        end
        list = withGhosts
    end
    -- The same search box that filters the catalog on the left also filters
    -- this list -- typing an Echo's name shows immediately whether it's
    -- already selected instead of needing to scroll the whole wishlist.
    -- designedCount/toLockCount above are already fixed (computed from the
    -- full, unfiltered pending/pendingLock) so the lock-budget checks and
    -- footer counts stay correct while a search is active.
    local searchTerm = Controller.FilterState().search:lower()
    if searchTerm ~= "" then
        local filtered = {}
        for _, e in ipairs(list) do
            if tostring(e.name or ""):lower():find(searchTerm, 1, true) then
                filtered[#filtered + 1] = e
            end
        end
        list = filtered
    end
    pickOffset = Controller.ClampPick(#list, PICK_ROWS)
    for i, row in ipairs(pickRows) do
        local data = list[pickOffset + i]
        row.data = data
        if data and data.ghost then
            -- Read-only pairing row for the real-locked Echo a design above
            -- it replaces -- not a wishlist entry, so no stack controls, no
            -- remove button, and clicks on it (minus/plus/remove/OnClick,
            -- guarded by d.ghost below) do nothing.
            row:Show()
            row.icon:SetTexture(SpellIcon(data.spellId))
            row.icon:SetVertexColor(0.5, 0.5, 0.5)
            row.text:SetTextColor(0.6, 0.6, 0.6)
            row.text:SetText("    |cff8a8a8a-> replaces|r " .. data.name
                .. "  |cff8a8a8a(currently locked)|r")
            if row.minus then row.minus:Hide() end
            if row.plus then row.plus:Hide() end
            if row.remove then row.remove:Hide() end
        elseif data then
            row:Show()
            row.icon:SetTexture(SpellIcon(data.spellId))
            row.icon:SetVertexColor(1, 1, 1)
            if row.remove then row.remove:Show() end
            -- Same quality color scheme as the left catalog list, so an
            -- Epic pick still reads as Epic once it's selected instead of
            -- going flat white. Queued (toLock) entries fully override this
            -- with their own orange wrap below -- that's intentional, the
            -- "still needs acquiring" state is the more useful signal there.
            local pc = QUALITY_COLORS[data.quality] or QUALITY_COLORS[0]
            row.text:SetTextColor(pc[1], pc[2], pc[3])
            if data.toLock then
                -- Separate locked-slot target: core/Main.lua injects it into
                -- automation without consuming or uploading a normal slot.
                row.text:SetText("|cffff9040" .. data.name .. "  (locked slot)|r")
            elseif data.lockIntent then
                -- Same separate locked-slot intent, represented on a pending
                -- row for compatibility with an in-progress editor session.
                -- It is excluded from the 79-copy upload and automated by its
                -- committed exact spellId.
                row.text:SetText(data.name .. "  |cffffd200x" .. tostring(data.stacks or 1)
                    .. "|r  |cff40c0ff(locked slot)|r")
            else
                row.text:SetText(data.name .. "  |cffffd200x" .. tostring(data.stacks or 1) .. "|r")
            end
            -- An Echo that can only ever hold 1 stack has nothing to adjust --
            -- hiding +/- entirely for it instead of leaving inert-looking
            -- buttons that appear clickable but never do anything.
            local canStack = not data.toLock and not data.lockIntent
                and (tonumber(data.maxStack) or 1) > 1
            if row.minus then
                if canStack then
                    row.minus:Show()
                    if (data.stacks or 1) > 1 then row.minus:Enable() else row.minus:Disable() end
                else
                    row.minus:Hide()
                end
            end
            if row.plus then
                if canStack then
                    row.plus:Show()
                    if (data.stacks or 1) < (data.maxStack or 1)
                        and PendingTotal() < MAX_WISHLIST_ECHOES then
                        row.plus:Enable()
                    else
                        row.plus:Disable()
                    end
                else
                    row.plus:Hide()
                end
            end
        else
            row:Hide()
        end
    end
    local footerParts = {}
    if lockedCount > 0 then footerParts[#footerParts + 1] = lockedCount .. " locked" end
    footerParts[#footerParts + 1] = PendingTotal() .. " / 79 wishlist"
    local totalDesigned = designedCount + toLockCount
    if totalDesigned > 0 then footerParts[#footerParts + 1] = totalDesigned .. " designed locks" end
    -- realEntryCount, not #list -- the spliced-in "replaces" ghost rows are
    -- a display aid, not separate wishlist entries, and shouldn't inflate
    -- this count.
    footerParts[#footerParts + 1] = realEntryCount .. " entries"
    pickFooterText:SetText(table.concat(footerParts, "  •  "))
end

    local function RefreshKeyMatches(known,controllerRevision,slots,active,
        granted,owned,wishlist,catalog,locked,lockedProjection,discovery,
        lever,firstRun)
        return known and refreshCache.known
            and refreshCache.controller == controllerRevision
            and refreshCache.slots == slots
            and refreshCache.active == active
            and refreshCache.granted == granted
            and refreshCache.owned == owned
            and refreshCache.wishlist == wishlist
            and refreshCache.catalog == catalog
            and refreshCache.locked == locked
            and refreshCache.lockedProjection == lockedProjection
            and refreshCache.discovery == discovery
            and refreshCache.lever == lever
            and refreshCache.firstRun == firstRun
    end

    local function StoreRefreshKey(known,controllerRevision,slots,active,
        granted,owned,wishlist,catalog,locked,lockedProjection,discovery,
        lever,firstRun)
        refreshCache.known = known and true or false
        refreshCache.controller = controllerRevision
        refreshCache.slots = slots
        refreshCache.active = active
        refreshCache.granted = granted
        refreshCache.owned = owned
        refreshCache.wishlist = wishlist
        refreshCache.catalog = catalog
        refreshCache.locked = locked
        refreshCache.lockedProjection = lockedProjection
        refreshCache.discovery = discovery
        refreshCache.lever = lever
        refreshCache.firstRun = firstRun
    end

    local function RefreshTimerStatus()
        if not applyBtn then return end
        local saving = Controller.IsApplyPending()
        local blocked = Controller.ApplyBlockReason()
        applyBtn:SetText(saving and "Saving..." or
            (Controller.IsEditing() and "Save Wishlist" or "Create Wishlist"))
        if saving or blocked then applyBtn:Disable() else applyBtn:Enable() end
    end

    local function RefreshTheme()
        local theme = Nexus and Nexus.Theme
        local style = theme and theme.StyleTree
        if frame and type(style) == "function"
            and style ~= refreshCache.styleTree then
            style(frame)
            refreshCache.styleTree = style
        end
    end

    function M.Refresh(...)
        local known,controllerRevision,slots,active,granted,owned,wishlist,
            catalog,locked,lockedProjection,discovery,lever,firstRun =
            Controller.RefreshState()
        local result
        if not RefreshKeyMatches(known,controllerRevision,slots,active,
            granted,owned,wishlist,catalog,locked,lockedProjection,discovery,
            lever,firstRun) then
            result = RefreshView(catalog)
            known,controllerRevision,slots,active,granted,owned,wishlist,
                catalog,locked,lockedProjection,discovery,lever,firstRun =
                Controller.RefreshState()
            StoreRefreshKey(known,controllerRevision,slots,active,granted,
                owned,wishlist,catalog,locked,lockedProjection,discovery,
                lever,firstRun)
        end
        RefreshTimerStatus()
        RefreshTheme()
        return result
    end

    function M.SetApplySaved()
        if applyBtn then applyBtn:SetText("Saved") end
    end

    function M.SetNameText(value)
        EnsureFrame()
        if wishlistNameBox then wishlistNameBox:SetText(value or "") end
    end

    function M.NameText()
        return wishlistNameBox and wishlistNameBox:GetText() or nil
    end

    function M.Prepare(config)
        EnsureFrame()
        config = type(config) == "table" and config or {}
        if config.attach and Nexus.Panel and Nexus.Panel.AttachMenuFrame then
            Nexus.Panel.AttachMenuFrame(frame)
        end
        if config.style and Nexus.Theme and Nexus.Theme.StyleWindow then
            Nexus.Theme.StyleWindow(frame, 0.96)
        end
        if config.close and Nexus.Panel and Nexus.Panel.CloseOtherWindows then
            Nexus.Panel.CloseOtherWindows("NexusEditorFrame")
        end
        return frame
    end

    function M.ShowFrame()
        EnsureFrame()
        frame:Show()
    end

    function M.Hide()
        if frame then frame:Hide() end
    end

    function M.IsShown()
        return frame and frame:IsShown() or false
    end

    function M.ToggleDisplayPopup(anchorTo)
        return ToggleDisplayPopup(anchorTo)
    end

    return M
end

Nexus.WishlistInternals.Renderer = Renderer
