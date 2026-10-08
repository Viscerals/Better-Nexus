-- Nexus: ui/JournalTab.lua
-- An "Nexus Advisor" tab inside ProjectEbonhold's Echo Journal, rendering
-- plain text sections supplied by an injected dataProvider callback.
-- Structures relied on (captured live against this exact client):
--   frame  ProjectEbonholdEchoJournal
--   tabs   ProjectEbonholdEchoJournalTab1..N (CharacterFrameTabButton
--          textures), parent = the journal frame
--   scroll ProjectEbonholdEchoJournalScroll = content area
-- The journal UI is built LAZILY on first open: a login-time install
-- succeeds only after /reload with the journal already built, so
-- "frames not present" is the NORMAL, SILENT state until the hooked
-- EchoJournal.Show/Toggle fires and the install retries. Our tab index
-- is existing-tab-count + 1 (a leftover EchoOptimizer Tab4 shifts us
-- to 5 instead of colliding).
-- SOFT-FAIL CONTRACT: TryInstall pcall-wraps everything and returns
-- false on any failure -- no tab, no error, retried on next Show.
-- All DATA arrives through the provider; this file touches journal
-- FRAMES only (documented presentation-layer exception), never
-- PerkService.

Nexus = Nexus or {}
local M = {}
Nexus.JournalTab = M

local installed = false
local hooked = false
local provider                -- dataProvider() -> { sections={ {title,lines={}} }, version }
local ourTab, panel, scroll, child
local associationPanel
local scanFrame, associationVisible = nil, false
local wishlistPicker, wishlistPickerRows = nil, {}
local HideWishlistPicker
local theirTabCount = 0
local linePool, linesUsed = {}, 0

local ASSET ="Interface\\AddOns\\ProjectEbonhold\\assets\\"
local NOTE1 = "Compares the assigned Wishlist with the ACTIVE Saved Build."
local NOTE2 = "|cff8a8a8aSet associations in My Builds. Saved Build activation requires the server's supported level and state.|r"
-- Assignment only records the target. The automatic save (Auto ON, autoSave,
-- Ratchet.Dominates) is what may replace the active Saved Build. A changed
-- assignment marks the projection dirty, so at level 80 with a finished run
-- the save check runs again at once against the new Wishlist.
local ASSIGN_NOTE = "Assigning by itself does not change any Saved Build."
-- An empty numbered Saved Build holds no Wishlist of its own and refuses an
-- assignment. The name the Journal shows beside it is the retained first-run
-- Wishlist, which the gear opens for editing without a destination. These
-- wordings say that; no action behind them changes.
local EMPTY_SLOT_ASSIGN = "This Saved Build is empty, so assigning a Wishlist to it is refused until it holds Echoes. "
    .. ASSIGN_NOTE
local EMPTY_SLOT_SELECTOR = "This Saved Build is empty, so no Wishlist can be assigned to it until it holds Echoes. "
    .. "A name shown here is the first-run Wishlist, not an assignment to this Saved Build. " .. ASSIGN_NOTE
local AUTO_SAVE_WARNING = "With Auto ON, Nexus may replace the active Saved Build with a finished run that "
    .. "has more overall Wishlist progress, or equal progress after cleanup or an even swap of requested "
    .. "copies. At level 80 after a finished run, Auto checks again right away when you change the assignment. "
    .. "Saving edits to the assigned Wishlist can also lead to a replacement without a new run."
local AUTO_SAVE_ORBS = "The replaced build may hold an Echo you value, even one obtained with Orbs: "
    .. "Orb investment is not compared. Keep Auto OFF to leave the Saved Build unchanged."

------------------------------------------------------------------------
-- Text lines
------------------------------------------------------------------------

local function AcquireLine()
    linesUsed = linesUsed + 1
    local fs = linePool[linesUsed]
    if not fs then
        fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        linePool[linesUsed] = fs
    end
    fs:Show()
    return fs
end

local function DoRefresh()
    local data
    if type(provider) == "function" then
        local okP, res = pcall(provider)
        if okP and type(res) == "table" then data = res end
    end

    linesUsed = 0
    local width = math.floor((scroll and scroll:GetWidth()) or 0)
    if width < 100 then width = 292 end
    width = width - 12
    local cy = -6

    local function AddLine(text, font, indent)
        text=Nexus.UserText and Nexus.UserText.Message(text) or text
        indent = indent or 0
        local fs = AcquireLine()
        fs:SetFontObject(font or "GameFontHighlightSmall")
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", 6 + indent, cy)
        fs:SetWidth(width - indent)
        -- Height 0 + fixed width = word-wrap; GetStringHeight is then
        -- the wrapped height.
        fs:SetHeight(0)
        fs:SetText(text or "")
        local h = fs:GetStringHeight()
        if not h or h < 12 then h = 12 end
        cy = cy - h - 2
    end

    AddLine(NOTE1, "GameFontNormalSmall")
    AddLine(NOTE2)
    cy = cy - 6

    local sections = data and data.sections
    if type(sections) ~= "table" or #sections == 0 then
        AddLine("|cff8a8a8ano data yet|r")
    else
        for i = 1, #sections do
            local sec = sections[i]
            if type(sec) == "table" then
                AddLine(tostring(sec.title or ""), "GameFontNormalSmall")
                local lines = sec.lines
                if type(lines) == "table" then
                    for j = 1, #lines do
                        AddLine(tostring(lines[j] or ""), nil, 8)
                    end
                end
                cy = cy - 4
            end
        end
    end

    if data and data.version ~= nil then
        cy = cy - 2
        AddLine("|cff8a8a8a" .. tostring(data.version) .. "|r")
    end

    for i = linesUsed + 1, #linePool do linePool[i]:Hide() end
    child:SetWidth(width + 12)
    child:SetHeight(-cy + 8)
end

function M.Refresh()
    if not (installed and panel and panel:IsShown()) then return end
    pcall(DoRefresh)
end


local function MenuOpen(items, anchor)
    if type(EasyMenu) ~= "function" then return end
    M._menuFrame = M._menuFrame or CreateFrame("Frame", "NexusJournalAssociationMenu", UIParent, "UIDropDownMenuTemplate")
    EasyMenu(items, M._menuFrame, anchor, 0, 0, "MENU")
end

local function FrameText(frame)
    local out = {}
    local function Walk(f, depth)
        if not f or depth > 5 then return end
        if f.GetText then
            local ok, v = pcall(f.GetText, f)
            if ok and type(v) == "string" and v ~= "" then out[#out + 1] = v end
        end
        if f.GetRegions then
            local regs = { f:GetRegions() }
            for i = 1, #regs do
                local r = regs[i]
                if r and r.GetText then
                    local ok, v = pcall(r.GetText, r)
                    if ok and type(v) == "string" and v ~= "" then out[#out + 1] = v end
                end
            end
        end
        if f.GetChildren then
            local kids = { f:GetChildren() }
            for i = 1, #kids do Walk(kids[i], depth + 1) end
        end
    end
    Walk(frame, 0)
    return table.concat(out, "\n")
end

local function NormalizedText(frame)
    return FrameText(frame):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function HasVisibleText(root, wanted)
    local found = false
    local function Walk(f, depth)
        if found or not f or depth > 16 then return end
        local shown = true
        if f.IsShown then
            local ok, v = pcall(f.IsShown, f)
            if ok then shown = v and true or false end
        end
        if shown then
            if f.GetText then
                local ok, text = pcall(f.GetText, f)
                if ok and type(text) == "string" then
                    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                    if text:find(wanted, 1, true) then found = true return end
                end
            end
            if f.GetRegions then
                local regs = { f:GetRegions() }
                for i = 1, #regs do
                    local r = regs[i]
                    if r and r.GetText then
                        local ok, text = pcall(r.GetText, r)
                        if ok and type(text) == "string" then
                            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                            if text:find(wanted, 1, true) then found = true return end
                        end
                    end
                end
            end
        end
        if f.GetChildren then
            local kids = { f:GetChildren() }
            for i = 1, #kids do Walk(kids[i], depth + 1) end
        end
    end
    Walk(root, 0)
    return found
end

local function IsLoadoutsVisible(journal)
    if not journal or not journal.IsShown or not journal:IsShown() then return false end
    -- The stock page always exposes this section title. This is intentionally
    -- independent of card frame names, dimensions, verification flags, and
    -- Project Ebonhold client revisions.
    if HasVisibleText(journal, "Your loadouts") then return true end
    if HasVisibleText(journal, "Empty slot 2") or HasVisibleText(journal, "Empty slot 3") then return true end
    return false
end

local function FindLoadoutsTab(journal)
    local function IsWantedButton(f)
        if not f or not f.GetObjectType or f:GetObjectType() ~= "Button" then return false end
        local txt = NormalizedText(f)
        for line in txt:gmatch("[^\n]+") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line == "Loadouts" then return true end
        end
        return false
    end

    -- Prefer the stock named tabs when present. On the current client the
    -- Loadouts button is Tab3, but validate the visible label rather than
    -- assuming the index.
    for i = 1, 12 do
        local t = _G["ProjectEbonholdEchoJournalTab" .. tostring(i)]
        if IsWantedButton(t) then return t end
    end

    local exact
    local function Walk(f, depth)
        if exact or not f or depth > 18 then return end
        if IsWantedButton(f) then exact = f return end
        if f.GetChildren then
            local kids = { f:GetChildren() }
            for i = 1, #kids do Walk(kids[i], depth + 1) end
        end
    end
    Walk(journal, 0)
    if not exact and UIParent and UIParent ~= journal then Walk(UIParent, 0) end
    return exact
end

local function ShortName(name, maxLen)
    name = tostring(name or "")
    maxLen = tonumber(maxLen) or 28
    if #name <= maxLen then return name end
    return name:sub(1, maxLen - 3) .. "..."
end



-- The selector sits in the Journal header near the screen top, so its tall
-- ANCHOR_TOP tooltip does not fit above it and the screen clamp moves it down
-- over the picker area. The open picker (TOOLTIP strata, higher level) then
-- covers the warning. While the picker is open, place the tooltip beside the
-- picker instead: right when there is room, else on the side with more room.
-- GameTooltip strata, level and parent are not changed.
local function ShowSelectorTooltip(selector)
    local besidePicker = wishlistPicker and wishlistPicker:IsShown()
    GameTooltip:SetOwner(selector, besidePicker and "ANCHOR_NONE" or "ANCHOR_TOP")
    GameTooltip:AddLine("Automation Wishlist", 0.35, 0.8, 1)
    GameTooltip:AddLine(associationPanel and associationPanel.emptySlot and EMPTY_SLOT_SELECTOR
        or ("Assigns a wishlist reference to the Saved Build currently selected in the server dropdown. "
        .. ASSIGN_NOTE), 0.82, 0.82, 0.82, true)
    GameTooltip:AddLine(AUTO_SAVE_WARNING, 1, 0.82, 0.25, true)
    GameTooltip:AddLine(AUTO_SAVE_ORBS, 1, 0.82, 0.25, true)
    GameTooltip:Show()
    if not besidePicker then return end
    local gap = 4
    local left, right = wishlistPicker:GetLeft(), wishlistPicker:GetRight()
    if not (left and right) then
        -- Picker layout not resolved yet (it was just shown). Its TOPLEFT is
        -- the selector's BOTTOMLEFT, and the hovered selector is laid out.
        local selectorLeft = selector:GetLeft()
        if selectorLeft then
            left = selectorLeft * (selector:GetEffectiveScale() or 1) / (wishlistPicker:GetEffectiveScale() or 1)
            right = left + (wishlistPicker:GetWidth() or 0)
        end
    end
    local screenRight = UIParent:GetRight() or UIParent:GetWidth() or 0
    -- Tooltip width in UIParent units (the picker is a scale-1 UIParent child).
    local width = (GameTooltip:GetWidth() or 0) * (GameTooltip:GetEffectiveScale() or 1)
        / (UIParent:GetEffectiveScale() or 1)
    local roomRight = right and (screenRight - right) or math.huge
    local roomLeft = left or 0
    GameTooltip:ClearAllPoints()
    if roomRight < width + gap and roomLeft > roomRight then
        GameTooltip:SetPoint("TOPRIGHT", wishlistPicker, "TOPLEFT", -gap, 0)
    else
        GameTooltip:SetPoint("TOPLEFT", wishlistPicker, "TOPRIGHT", gap, 0)
    end
end

-- The picker opens and closes on a selector click while the mouse stays on
-- the selector: place its shown tooltip again for the new picker state.
local function RefreshSelectorTooltip()
    local selector = associationPanel and associationPanel.selector
    if selector and selector:IsVisible() and GameTooltip:IsShown()
        and GameTooltip:GetOwner() == selector then
        ShowSelectorTooltip(selector)
    end
end

local function EnsureAssociationPanel(journal)
    if not journal then return nil end
    if not associationPanel then
        associationPanel = CreateFrame("Frame", "NexusLoadoutAssociationPanel", journal)
        associationPanel:SetSize(360, 56)
        associationPanel:SetFrameStrata("DIALOG")
        associationPanel:SetFrameLevel((journal:GetFrameLevel() or 0) + 24)
        associationPanel:EnableMouse(true)
        associationPanel:SetClampedToScreen(true)
        if associationPanel.SetBackdrop then
            associationPanel:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 11,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            associationPanel:SetBackdropColor(0.018, 0.024, 0.032, 0.97)
            associationPanel:SetBackdropBorderColor(0.28, 0.58, 0.76, 0.95)
        end

        associationPanel.label = associationPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        associationPanel.label:SetPoint("TOPLEFT", 10, -9)
        associationPanel.label:SetWidth(145)
        associationPanel.label:SetJustifyH("LEFT")
        associationPanel.label:SetTextColor(0.72, 0.72, 0.72)

        associationPanel.selector = CreateFrame("Button", "NexusActiveWishlistSelector", associationPanel)
        associationPanel.selector:SetSize(169, 21)
        associationPanel.selector:SetPoint("TOPRIGHT", -31, -5)
        associationPanel.selector:RegisterForClicks("LeftButtonUp")
        if associationPanel.selector.SetBackdrop then
            associationPanel.selector:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false, edgeSize = 9,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            associationPanel.selector:SetBackdropColor(0.035, 0.045, 0.06, 0.99)
            associationPanel.selector:SetBackdropBorderColor(0.25, 0.31, 0.38, 0.95)
        end
        associationPanel.selector.text = associationPanel.selector:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        associationPanel.selector.text:SetPoint("LEFT", 9, 0)
        associationPanel.selector.text:SetPoint("RIGHT", -25, 0)
        associationPanel.selector.text:SetJustifyH("LEFT")
        -- One line inside the 21 px selector; the picker lists complete names.
        if Nexus.LayoutMetrics then Nexus.LayoutMetrics.OneLineLabel(associationPanel.selector.text, nil, 21) end
        associationPanel.selector.arrow = associationPanel.selector:CreateTexture(nil, "ARTWORK")
        associationPanel.selector.arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
        associationPanel.selector.arrow:SetSize(16, 16)
        associationPanel.selector.arrow:SetPoint("RIGHT", -5, 0)

        associationPanel.design = CreateFrame("Button", "NexusAssociatedWishlistDesignButton", associationPanel)
        associationPanel.design:SetSize(20, 20)
        associationPanel.design:SetPoint("TOPRIGHT", -7, -6)
        associationPanel.design:RegisterForClicks("LeftButtonUp")
        associationPanel.design.icon = associationPanel.design:CreateTexture(nil, "ARTWORK")
        associationPanel.design.icon:SetAllPoints()
        associationPanel.design.icon:SetTexture("Interface\\Buttons\\WHITE8X8")
        associationPanel.design.icon:SetVertexColor(0.08, 0.11, 0.15, 0.98)
        associationPanel.design.glyph = associationPanel.design:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        associationPanel.design.glyph:SetPoint("CENTER", 0, 1)
        associationPanel.design.glyph:SetText("...")
        associationPanel.design.glyph:SetTextColor(1, 0.82, 0.2)
        associationPanel.design:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        associationPanel.newWishlist = CreateFrame("Button", nil, associationPanel, "UIPanelButtonTemplate")
        associationPanel.newWishlist:SetSize(150, 19)
        associationPanel.newWishlist:SetPoint("BOTTOMRIGHT", -7, 5)
        associationPanel.newWishlist:SetText("New Wishlist")
        associationPanel.newWishlist:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("New Wishlist", 0.35, 0.8, 1)
            GameTooltip:AddLine("Open a blank Nexus Wishlist Editor for a new run.", 0.82, 0.82, 0.82, true)
            GameTooltip:Show()
        end)
        associationPanel.newWishlist:SetScript("OnLeave", function() GameTooltip:Hide() end)

        associationPanel.design:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if associationPanel and associationPanel.emptySlot then
                GameTooltip:AddLine("Edit first-run Wishlist", 0.35, 0.8, 1)
                GameTooltip:AddLine("Open the first-run Wishlist for editing. This Saved Build is empty and has no Wishlist of its own, so nothing is assigned to it. This does not activate another build.", 0.82, 0.82, 0.82, true)
            else
                GameTooltip:AddLine("Edit assigned Wishlist", 0.35, 0.8, 1)
                GameTooltip:AddLine("Open the Wishlist assigned to this Saved Build. This does not activate another build.", 0.82, 0.82, 0.82, true)
            end
            GameTooltip:Show()
        end)
        associationPanel.design:SetScript("OnLeave", function() GameTooltip:Hide() end)
        associationPanel.selector:SetScript("OnEnter", function(self)
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.42, 0.72, 0.95, 1) end
            ShowSelectorTooltip(self)
        end)
        associationPanel.selector:SetScript("OnLeave", function(self)
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.25, 0.31, 0.38, 0.95) end
            GameTooltip:Hide()
        end)

        associationPanel:SetScript("OnHide", function()
            HideWishlistPicker()
            if M._menuFrame then M._menuFrame:Hide() end
        end)
    end

    associationPanel:SetParent(journal)
    associationPanel:ClearAllPoints()
    -- Keep the control centered in the unused top header strip. This avoids
    -- the Echo row, search field, and the server loadout dropdown/menu.
    associationPanel:SetPoint("TOP", journal, "TOP", 85, 2)
    return associationPanel
end

local function HideRowButtons()
    if associationPanel then associationPanel:Hide() end
end

HideWishlistPicker = function()
    if wishlistPicker and wishlistPicker:IsShown() then
        wishlistPicker:Hide()
        RefreshSelectorTooltip()
    end
end

-- Display only: which picker row is the resolved assignment. The resolver
-- copies the stored assignmentId onto the live server row it found, but the
-- picker lists fresh live rows that carry none. So: equal assignmentIds on both
-- sides decide; a row stamped with another assignment is never selected;
-- otherwise the current resolved server slot and content key must both match.
-- Equal contents in another slot, or a name, identify nothing.
local function IsAssignedPickerRow(linked, c)
    if type(linked) ~= "table" or type(c) ~= "table" then return false end
    if linked.assignmentId and c.assignmentId then
        return linked.assignmentId == c.assignmentId
    end
    if c.assignmentId then return false end
    local slot = tonumber(linked.slot)
    return slot ~= nil and slot == tonumber(c.slot)
        and type(linked.key) == "string" and linked.key ~= "" and linked.key == c.key
end

-- `emptySlot` is the empty-Saved-Build context `active` and `loadoutName` were taken
-- in. The picker's tooltips use it, not the live Journal context, so their words
-- always describe the target its click handlers act on while it stays open.
local function ShowWishlistPicker(anchor, wishes, linked, active, loadoutName, A, emptySlot)
    if not wishlistPicker then
        wishlistPicker = CreateFrame("Frame", "NexusWishlistOnlyPicker", UIParent)
        wishlistPicker:SetFrameStrata("TOOLTIP")
        -- Native high-level rendering put this opaque parent above Unassign.
        -- TOOLTIP supplies the overlay order; keep its child levels low.
        wishlistPicker:SetFrameLevel(50)
        wishlistPicker:SetToplevel(true)
        wishlistPicker:SetClampedToScreen(true)
        wishlistPicker:EnableMouse(true)
        if wishlistPicker.SetBackdrop then
            wishlistPicker:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=12, insets={left=3,right=3,top=3,bottom=3} })
            wishlistPicker:SetBackdropColor(0.02,0.025,0.035,0.99)
            wishlistPicker:SetBackdropBorderColor(0.25,0.55,0.75,1)
        end
        wishlistPicker.bg = wishlistPicker:CreateTexture(nil, "BACKGROUND")
        wishlistPicker.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        wishlistPicker.bg:SetAllPoints()
        wishlistPicker.bg:SetVertexColor(0.02, 0.025, 0.035, 0.99)
        wishlistPicker.border = CreateFrame("Frame", nil, wishlistPicker)
        wishlistPicker.border:SetAllPoints()
        wishlistPicker.border:SetFrameLevel(wishlistPicker:GetFrameLevel() + 1)
        wishlistPicker.title = wishlistPicker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        wishlistPicker.title:SetPoint("TOPLEFT", 10, -8)
        wishlistPicker.title:SetText("Wishlists")
    end
    for i=1,#wishlistPickerRows do wishlistPickerRows[i]:Hide() end
    if wishlistPicker.emptyRow then wishlistPicker.emptyRow:Hide() end
    if wishlistPicker.clearRow then wishlistPicker.clearRow:Hide() end
    wishlistPicker:ClearAllPoints()
    wishlistPicker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    local width, rowH = 245, 24
    wishlistPicker:SetWidth(width)
    local count = math.max(1, #wishes)
    wishlistPicker:SetHeight(26 + count * rowH + (linked and 24 or 0) + 6)

    if #wishes == 0 then
        local row = wishlistPicker.emptyRow
        if not row then
            row = wishlistPicker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            wishlistPicker.emptyRow = row
        end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 10, -28); row:SetText("No server wishlists found"); row:Show()
    else
        for i=1,#wishes do
            local c = wishes[i]
            local cSlot = c.slot
            local cName = c.name
            local cKey = c.key
            local row = wishlistPickerRows[i]
            if not row or not row.nameButton then
                row = CreateFrame("Frame", nil, wishlistPicker)
                row:SetFrameLevel(wishlistPicker:GetFrameLevel() + 2)
                row:EnableMouse(true)
                row:SetSize(width-12, rowH)
                row.nameButton = CreateFrame("Button", nil, row)
                row.nameButton:SetFrameLevel(row:GetFrameLevel() + 1)
                row.nameButton:RegisterForClicks("LeftButtonUp")
                row.nameButton:EnableMouse(true)
                row.nameButton:SetPoint("LEFT", 0, 0); row.nameButton:SetPoint("RIGHT", -28, 0); row.nameButton:SetHeight(rowH-2)
                row.nameButton.text = row.nameButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.nameButton.text:SetPoint("LEFT", 6, 0); row.nameButton.text:SetPoint("RIGHT", -4, 0); row.nameButton.text:SetJustifyH("LEFT")
                -- One line per row; a shortened name is complete in the row tooltip.
                if Nexus.LayoutMetrics then Nexus.LayoutMetrics.OneLineLabel(row.nameButton.text, nil, rowH-2) end
                row.nameButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                row.gear = CreateFrame("Button", nil, row)
                row.gear:SetFrameLevel(row:GetFrameLevel() + 2)
                row.gear:RegisterForClicks("LeftButtonUp")
                row.gear:EnableMouse(true)
                row.gear:SetSize(20,20); row.gear:SetPoint("RIGHT", -2, 0)
                row.gear.icon = row.gear:CreateTexture(nil, "ARTWORK"); row.gear.icon:SetAllPoints(); row.gear.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
                row.gear.glyph = row.gear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.gear.glyph:SetPoint("CENTER", 0, 1)
                row.gear.glyph:SetText("...")
                row.gear.glyph:SetTextColor(1, 0.82, 0.2)
                row.gear:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
                row.gear:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Edit wishlist", .35,.8,1); GameTooltip:Show()
                end)
                row.gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
                wishlistPickerRows[i] = row
            end
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 6, -24 - (i-1)*rowH)
            local selected = IsAssignedPickerRow(linked, c)
            local editor=Nexus.WishlistEditor
            local hint=editor and editor.UnresolvedRoleHint and editor.UnresolvedRoleHint() or "choose locked targets"
            local evidenceSuffix = c.lockEvidenceStatus == "unavailable"
                and ("  |cffff9040("..hint..")|r") or ""
            row.nameButton.text:SetText((selected and "|cff55ff55[Selected] |r" or "")
                .. ((cName ~= "" and cName) or "Unnamed Wishlist")
                .. evidenceSuffix)
            local cEchoes = c.echoes
            local cSnapshot = {
                slot=cSlot, name=cName, key=cKey,
                lockEvidenceVersion=c.lockEvidenceVersion,
                lockEvidenceStatus=c.lockEvidenceStatus,
                evidenceSource=c.evidenceSource,
                assignmentId=c.assignmentId,designTargets=c.designTargets,
                echoes={},
            }
            for echoIndex = 1, #(cEchoes or {}) do
                local echo = cEchoes[echoIndex]
                cSnapshot.echoes[echoIndex] = {
                    spellId=echo.spellId, quality=echo.quality,
                    stacks=echo.stacks, locked=echo.locked,
                }
            end
            local function AssociateWishlistOnly()
                if cSnapshot.lockEvidenceStatus=="unavailable" and Nexus.WishlistEditor
                    and Nexus.WishlistEditor.ResolveAndAssignWishlist then
                    HideWishlistPicker()
                    Nexus.WishlistEditor.ResolveAndAssignWishlist(cSnapshot,tonumber(active) or 0)
                    return
                end
                local ok, err
                if tonumber(active) and tonumber(active) > 0 then
                    ok, err = A.SetLoadoutWishlist(active, cSlot, cSnapshot)
                elseif type(A.SetFirstRunWishlist) == "function" then
                    ok, err = A.SetFirstRunWishlist(cSlot, cSnapshot)
                else
                    ok, err = false, "first-run association unavailable"
                end
                if not ok then
                    print("|cffff6060Nexus:|r " .. tostring(err or "could not select wishlist"))
                    return
                end
                HideWishlistPicker()
                M.RefreshAssociations()
                if Nexus.Panel and Nexus.Panel.Refresh then pcall(Nexus.Panel.Refresh) end
            end
            local function OpenWishlistEditorOnly()
                HideWishlistPicker()
                local editor = Nexus and Nexus.WishlistEditor
                if editor and type(editor.OpenForWishlist) == "function" then
                    editor.OpenForWishlist({
                        slot = cSlot,
                        name = cName,
                        key = cKey,
                        echoes = cEchoes,
                        lockEvidenceVersion = c.lockEvidenceVersion,
                        lockEvidenceStatus = c.lockEvidenceStatus,
                        evidenceSource=c.evidenceSource,
                        assignmentId=c.assignmentId,designTargets=c.designTargets,
                        loadoutName = loadoutName,
                    }, (tonumber(active) and tonumber(active) > 0) and active or nil)
                else
                    print("|cffff6060Nexus:|r Nexus Wishlist Editor is unavailable.")
                end
            end
            row.nameButton:SetScript("OnClick", AssociateWishlistOnly)
            row.nameButton:SetScript("OnEnter", function(self)
                -- Anchor at the row edge: the name button ends 28 px inside
                -- the picker, which shares the TOOLTIP strata.
                GameTooltip:SetOwner(self:GetParent() or self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Assign Wishlist", .35, .8, 1)
                GameTooltip:AddLine("Target: " .. tostring(loadoutName or ""), 1, 1, 1, true)
                GameTooltip:AddLine(emptySlot and EMPTY_SLOT_ASSIGN
                    or ("Sets this Wishlist as the target for this loadout. " .. ASSIGN_NOTE),
                    .82, .82, .82, true)
                GameTooltip:AddLine(AUTO_SAVE_WARNING, 1, .82, .25, true)
                GameTooltip:AddLine(AUTO_SAVE_ORBS, 1, .82, .25, true)
                if Nexus.LayoutMetrics and Nexus.LayoutMetrics.Shortened(self.text) then
                    GameTooltip:AddLine(self.text:GetText(), 1, 1, 1, true)
                end
                GameTooltip:Show()
            end)
            row.nameButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.gear:SetScript("OnClick", OpenWishlistEditorOnly)
            row:Show()
        end
    end

    if linked then
        local row = wishlistPicker.clearRow
        if not row then
            row = CreateFrame("Button", nil, wishlistPicker)
            row:SetHeight(20)
            row.text = row:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
            row.text:SetPoint("LEFT",6,0); row.text:SetText("Unassign Wishlist")
            row:SetScript("OnEnter",function(self)
                GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                GameTooltip:AddLine("Unassign Wishlist",1,1,1)
                GameTooltip:AddLine(self.emptySlot
                    and "This Saved Build has no Wishlist of its own. This does not remove the first-run Wishlist."
                    or "Keeps the Wishlist; stops using it for this loadout.",.8,.8,.8,true)
                GameTooltip:AddLine("Does not change or restore the Saved Build.",.8,.8,.8,true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave",function()GameTooltip:Hide()end)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            wishlistPicker.clearRow = row
        end
        row:SetFrameLevel(wishlistPicker:GetFrameLevel() + 2)
        row.emptySlot = emptySlot
        row:ClearAllPoints(); row:SetPoint("TOPLEFT",6,-24-#wishes*rowH); row:SetPoint("RIGHT",-6,0)
        row:SetScript("OnClick", function()
            if tonumber(active) and tonumber(active) > 0 then A.ClearLoadoutWishlist(active)
            elseif A.ClearFirstRunWishlist then A.ClearFirstRunWishlist() end
            HideWishlistPicker(); M.RefreshAssociations()
        end)
        row:Show()
    end
    wishlistPicker:Show()
    RefreshSelectorTooltip()
end

local function RefreshAssociationRows()
    local journal = _G["ProjectEbonholdEchoJournal"]
    if not journal or not journal.IsShown or not journal:IsShown() then HideRowButtons(); return end
    if installed and panel and panel:IsShown() then HideRowButtons(); return end

    local A = Nexus and Nexus.GameAdapter
    local slots = A and A.Slots and A.Slots()
    if not slots then HideRowButtons(); return end

    local active = tonumber(slots.activeSlot) or 0
    local maxSlots = tonumber(slots.maxSlots) or 5
    local activeRow = slots.bySlot and slots.bySlot[active]
    local populated = activeRow and type(activeRow.echoes) == "table" and #activeRow.echoes > 0
    local firstRun = active < 1 or active > maxSlots or not populated
    -- A numbered Saved Build that holds no Echoes (see EMPTY_SLOT_*).
    local emptySlot = firstRun and active >= 1 and active <= maxSlots

    local host = EnsureAssociationPanel(journal)
    host.emptySlot = emptySlot
    -- The scanner calls this every 0.75 s while the Journal is open. The
    -- Wishlist candidates are the most expensive adapter read of a refresh
    -- and only the picker shows them, so they are read when the picker
    -- opens (below), as the store is at that moment. The slots and the
    -- assignment are still read on every refresh: the label and the
    -- selector follow every change, announced or not.
    local linked = firstRun and (A.GetFirstRunWishlist and A.GetFirstRunWishlist())
        or (A.GetLoadoutWishlist and A.GetLoadoutWishlist(active))
    local loadoutName = (active < 1 or active > maxSlots) and "No Saved Build selected"
        or not populated and "Empty Saved Build slot" or tostring(activeRow.name or "")
    if not firstRun and loadoutName == "" then loadoutName = "Saved Build " .. tostring(active) end
    host.label:SetText("|cffffffff" .. ShortName(loadoutName, 21) .. ":|r")

    local linkedName = linked and tostring(linked.name or "") or ""
    if linkedName ~= "" then
        host.selector.text:SetText("|cffffffff" .. ShortName(linkedName, 20) .. "|r")
        host.design:Enable()
        if host.design.icon then host.design.icon:SetDesaturated(false); host.design.icon:SetAlpha(1) end
    else
        host.selector.text:SetText("|cff8a8a8aSelect wishlist...|r")
        host.design:Disable()
        if host.design.icon then host.design.icon:SetDesaturated(true); host.design.icon:SetAlpha(0.45) end
    end
    host.design:SetScript("OnClick", function()
        local editor = Nexus and Nexus.WishlistEditor
        if not linked then
            print("|cffff6060Nexus:|r Associate a wishlist first.")
        elseif editor and type(editor.OpenForWishlist) == "function" then
            HideWishlistPicker()
            -- Zero/empty slots use the first-run assignment. Lua's
            -- `firstRun and nil or active` would pass slot 0 as a loadout.
            editor.OpenForWishlist({
                slot = linked.slot,
                name = linked.name,
                key = linked.key,
                echoes = linked.echoes,
                lockEvidenceVersion=linked.lockEvidenceVersion,
                lockEvidenceStatus=linked.lockEvidenceStatus,
                evidenceSource=linked.evidenceSource,
                assignmentId=linked.assignmentId,designTargets=linked.designTargets,
                loadoutName = loadoutName,
            }, not firstRun and active or nil)
        else
            print("|cffff6060Nexus:|r Nexus Wishlist Editor is unavailable.")
        end
    end)

    host.selector:SetScript("OnClick", function(self)
        if wishlistPicker and wishlistPicker:IsShown() then HideWishlistPicker(); return end
        local wishes = A.GetWishlistCandidates and A.GetWishlistCandidates() or {}
        ShowWishlistPicker(self, wishes, linked, active, loadoutName, A, emptySlot)
    end)
    host.newWishlist:SetScript("OnClick", function()
        HideWishlistPicker()
        local editor = Nexus and Nexus.WishlistEditor
        if editor and type(editor.NewWishlist) == "function" then editor.NewWishlist()
        else print("|cffff6060Nexus:|r Nexus Wishlist Editor is unavailable.") end
    end)
    host:Show()
end

function M.RefreshAssociations()
    pcall(RefreshAssociationRows)
end

local function EnsureAssociationScanner()
    if scanFrame then return end
    scanFrame = CreateFrame("Frame", "NexusLoadoutAssociationScanner", UIParent)
    local elapsed = 0
    scanFrame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (tonumber(dt) or 0)
        if elapsed < 0.75 then return end
        elapsed = 0
        pcall(function()
            local journal = _G["ProjectEbonholdEchoJournal"]
            if journal and journal.IsShown and journal:IsShown() then
                RefreshAssociationRows()
            else
                HideRowButtons()
            end
        end)
    end)
end

------------------------------------------------------------------------
-- Tab select / deselect
------------------------------------------------------------------------

local function SelectOurTab()
    if PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, ourTab) end
    for i = 1, theirTabCount do
        local t = _G["ProjectEbonholdEchoJournalTab" .. i]
        if t and PanelTemplates_DeselectTab then
            pcall(PanelTemplates_DeselectTab, t)
        end
    end
    panel:Show()
    associationVisible = false
    HideRowButtons()
    M.Refresh()
end

local function DeselectOurTab(showAssociation)
    if ourTab and PanelTemplates_DeselectTab then
        pcall(PanelTemplates_DeselectTab, ourTab)
    end
    if panel then panel:Hide() end
    associationVisible = showAssociation ~= false
    if associationVisible then pcall(RefreshAssociationRows) else HideRowButtons() end
    if ourTab then ourTab:Show() end
end
------------------------------------------------------------------------
-- Install
------------------------------------------------------------------------

-- Advisor tab attachment. The tab is always anchored to another frame, never
-- to screen coordinates, so it moves with whatever window carries the journal.
-- Client evidence (echo_journal.lua): the journal is reparented into
-- CollectionsJournal on first embed, that reparenting resets its children's
-- frame levels, and the hub hides the journal's own numbered tabs there. The
-- hub's replacement navigation is not in the available client evidence, so no
-- hub control is named or searched for here.
local Attach = {mode = "none", hookedTabs = {}, hookedJournal = nil}

-- The last numbered tab the client still shows, else the journal frame, which
-- is the one host known to be on screen whenever the Advisor tab is.
function Attach.Resolve(journal)
    local last
    for i = 1, theirTabCount do
        local t = _G["ProjectEbonholdEchoJournalTab" .. i]
        if t and t.IsShown and t:IsShown() then last = t end
    end
    if last then return last, "journal-tabs" end
    return journal, "journal-frame"
end

-- Idempotent. Changes the anchor only when the resolved target changed, and
-- reasserts the frame levels every time because a reparent resets them.
function Attach.Apply()
    local journal = _G["ProjectEbonholdEchoJournal"]
    if not (journal and ourTab) then return false end
    local target, mode = Attach.Resolve(journal)
    if Attach.target ~= target or Attach.mode ~= mode then
        ourTab:ClearAllPoints()
        if mode == "journal-tabs" then
            -- Same row as their tabs, standard -16 overlap after the last one.
            ourTab:SetPoint("TOPLEFT", target, "TOPRIGHT", -16, 0)
        else
            -- Their tab row hangs 12 below the journal's bottom edge and starts
            -- at its left. The right end of that same edge is used instead.
            ourTab:SetPoint("RIGHT", journal, "BOTTOMRIGHT", -12, -12)
        end
        Attach.target, Attach.mode = target, mode
    end
    ourTab:SetFrameLevel(mode == "journal-tabs" and target:GetFrameLevel()
        or journal:GetFrameLevel() + 2)
    if panel then panel:SetFrameLevel(journal:GetFrameLevel() + 10) end
    return true
end

-- For the diagnostic snapshot and the native drag/reopen check.
function M.AttachmentStatus()
    local journal = _G["ProjectEbonholdEchoJournal"]
    local parent = journal and journal.GetParent and journal:GetParent() or nil
    return {
        installed = installed, mode = Attach.mode,
        anchor = Attach.target and Attach.target.GetName and Attach.target:GetName() or "none",
        journalParent = parent and parent.GetName and parent:GetName() or "none",
        hubNavigation = "not in client evidence; not used",
    }
end

local function Install()
    local journal = _G["ProjectEbonholdEchoJournal"]
    local jScroll = _G["ProjectEbonholdEchoJournalScroll"]
    local tab1 = _G["ProjectEbonholdEchoJournalTab1"]
    if not (journal and jScroll and tab1) then
        error("journal frames not present")
    end
    EnsureAssociationScanner()

    local n = 0
    while _G["ProjectEbonholdEchoJournalTab" .. (n + 1)] do
        n = n + 1
    end
    theirTabCount = n

    -- A second Install after a partial failure reuses every frame and hook.
    ourTab = ourTab or CreateFrame("Button", "NexusJournalTab",
        journal, "CharacterFrameTabButtonTemplate")
    ourTab:SetText("Nexus Advisor")
    Attach.target, Attach.mode = nil, "none"
    Attach.Apply()
    -- A fresh template tab shows BOTH texture sets until its state is
    -- set; without this it renders as a mangled sliver.
    pcall(function() PanelTemplates_TabResize(ourTab, 0) end)
    pcall(function() PanelTemplates_DeselectTab(ourTab) end)
    ourTab:Show()
    -- A second click closes the Advisor again. When the host hides the
    -- numbered tabs, no stock tab click is left to do that.
    ourTab:SetScript("OnClick", function()
        pcall(function()
            if panel and panel:IsShown() then DeselectOurTab(true) else SelectOurTab() end
        end)
    end)

    -- Their tab numbering differs between client revisions. Never assume
    -- Tab1 is Loadouts: inspect the clicked tab after the stock handler runs.
    for i = 1, theirTabCount do
        local t = _G["ProjectEbonholdEchoJournalTab" .. i]
        if t then
            if t.HookScript and not Attach.hookedTabs[t] then
                Attach.hookedTabs[t] = true
                -- The host hides or restores these tabs at its own time.
                -- Event-driven: no scan and no per-frame work.
                t:HookScript("OnHide", function() pcall(Attach.Apply) end)
                t:HookScript("OnShow", function() pcall(Attach.Apply) end)
                t:HookScript("OnClick", function()
                    pcall(function()
                        DeselectOurTab(false)
                        associationVisible = true
                        if associationVisible then RefreshAssociationRows() else HideRowButtons() end
                    end)
                end)
            end
        end
    end
    -- Some client builds use bottom navigation buttons that are not named
    -- ProjectEbonholdEchoJournalTabN. The scanner determines visibility from
    -- actual loadout cards, so opening/rebuilding the journal remains safe.
    if journal.HookScript and Attach.hookedJournal ~= journal then
        Attach.hookedJournal = journal
        journal:HookScript("OnShow", function()
            pcall(function()
                -- The host may have embedded the journal or hidden its tabs
                -- since the last open.
                Attach.Apply()
                DeselectOurTab(false)
                associationVisible = true
            end)
        end)
        journal:HookScript("OnHide", function() associationVisible = false; HideRowButtons() end)
    end

    -- Our panel covers the journal's ENTIRE content region below the
    -- title bar: the per-tab top sections belong to THEIR tabs and
    -- their switcher rightly ignores our tab -- so we occlude rather
    -- than fight their state. EnableMouse blocks click-through.
    if not panel then
        panel = CreateFrame("Frame", "NexusJournalPanel", journal)
        panel:SetPoint("TOPLEFT", journal, "TOPLEFT", 10, -32)
        panel:SetPoint("BOTTOMRIGHT", journal, "BOTTOMRIGHT", -8, 8)
        panel:EnableMouse(true)
        local bg = panel:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(ASSET .. "UI-Background-Rock")
    end
    panel:SetFrameLevel(journal:GetFrameLevel() + 10)

    if not scroll then
        scroll = CreateFrame("ScrollFrame", "NexusJournalScroll",
            panel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -6)
        scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)
        child = CreateFrame("Frame", nil, scroll)
        child:SetSize(292, 100)
        scroll:SetScrollChild(child)
    end

    panel:Hide()
end

-- Runs inside the client's own (pcall'd) handler paths: body must be
-- pcall-wrapped and minimal, or an error here aborts the remainder of
-- THEIR handler and gets misattributed to ProjectEbonhold.
local function OnJournalLifecycle()
    pcall(function()
        if not installed and pcall(Install) then
            installed = true
        end
        if installed then
            Attach.Apply()
            DeselectOurTab(true)
        end
    end)
end

local function EnsureLifecycleHooks()
    if hooked then return end
    if type(hooksecurefunc) ~= "function" then return end
    local pe = _G["ProjectEbonhold"]
    local ej = pe and pe.EchoJournal
    if type(ej) ~= "table" then return end
    local any = false
    if type(ej.Show) == "function" then
        hooksecurefunc(ej, "Show", OnJournalLifecycle)
        any = true
    end
    if type(ej.Toggle) == "function" then
        hooksecurefunc(ej, "Toggle", OnJournalLifecycle)
        any = true
    end
    hooked = any
end

local function ClickCurrentEchoesMicroButton()
    -- The server update moved Echoes into Character Progression. Calling the
    -- legacy ProjectEbonhold.EchoJournal.Show() still opens the retired
    -- standalone journal, so always enter through the live menu-bar button.
    local button = _G["EchoJournalMicroButton"]
    if button and type(button.Click) == "function" then
        local ok = pcall(button.Click, button)
        if ok then return true end
    end

    -- Be tolerant of a renamed/reparented button while still refusing to open
    -- the obsolete standalone frame. Search only actual clickable buttons.
    local function walk(frame, depth)
        if not frame or depth > 6 then return nil end
        local name = frame.GetName and frame:GetName() or nil
        if type(name) == "string" then
            local lower = string.lower(name)
            if string.find(lower, "echojournalmicrobutton", 1, true)
                and type(frame.Click) == "function" then
                return frame
            end
        end
        local children = { frame.GetChildren and frame:GetChildren() }
        for i = 1, #children do
            local found = walk(children[i], depth + 1)
            if found then return found end
        end
        return nil
    end

    local found = walk(_G["UIParent"], 0)
    if found and type(found.Click) == "function" then
        local ok = pcall(found.Click, found)
        if ok then return true end
    end
    return false
end

function M.OpenBuilds()
    EnsureAssociationScanner()

    local opened = ClickCurrentEchoesMicroButton()
    if not opened then
        print("|cffff6060Nexus:|r Could not find the server Character Progression button. Open Character Progression → Echoes manually.")
        return
    end

    -- Let the server finish constructing/selecting its new Echoes page before
    -- attaching Nexus beside the live loadout dropdown.
    local function finish()
        pcall(function()
            if not installed and pcall(Install) then installed = true end
            if installed then
                Attach.Apply()
                DeselectOurTab(false)
            end
            RefreshAssociationRows()
        end)
    end
    finish()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.10, finish)
        C_Timer.After(0.35, finish)
    end
end

function M.DebugSnapshot()
    local journal = _G["ProjectEbonholdEchoJournal"]
    local A = Nexus and Nexus.GameAdapter
    local slots = A and A.Slots and A.Slots()
    local visible = journal and IsLoadoutsVisible(journal) or false
    local tab = journal and FindLoadoutsTab(journal) or nil
    local tabText = tab and NormalizedText(tab) or "none"
    local lines = {}
    lines[#lines + 1] = "journal=" .. tostring(journal ~= nil) .. " shown=" .. tostring(journal and journal:IsShown() or false)
    lines[#lines + 1] = "loadoutsVisible=" .. tostring(visible) .. " tab=" .. tostring(tabText)
    local attachment = M.AttachmentStatus()
    lines[#lines + 1] = "advisorTab mode=" .. tostring(attachment.mode) .. " anchor=" .. tostring(attachment.anchor)
        .. " journalParent=" .. tostring(attachment.journalParent) .. " hubNavigation=" .. attachment.hubNavigation
    lines[#lines + 1] = "associationPanel=" .. tostring(associationPanel ~= nil)
        .. " shown=" .. tostring(associationPanel and associationPanel:IsShown() or false)
    if slots then
        lines[#lines + 1] = "activeSlot=" .. tostring(slots.activeSlot) .. " maxSlots=" .. tostring(slots.maxSlots)
        for i = 1, tonumber(slots.maxSlots or 5) do
            local r = slots.bySlot and slots.bySlot[i]
            lines[#lines + 1] = "slot" .. i .. " echoes=" .. tostring(r and r.echoes and #r.echoes or 0) .. " linked=" .. tostring(A.GetLoadoutWishlistSlot and A.GetLoadoutWishlistSlot(i) or "none")
        end
    else
        lines[#lines + 1] = "slots=nil"
    end
    return lines
end

-- Attach to the live journal (or arm the lazy Show/Toggle hooks and
-- attach on first open). Safe to call repeatedly; never errors.
function M.TryInstall(dataProvider)
    local ok = pcall(function()
        if type(dataProvider) == "function" then
            provider = dataProvider
        end
        EnsureAssociationScanner()
        EnsureLifecycleHooks()
        if not installed and pcall(Install) then
            installed = true
        end
    end)
    if not ok then return false end
    return installed and true or false
end

-- Dark-theme Nexus controls embedded in the server Echo Journal.
do
    local originalRefreshAssociations = M.RefreshAssociations
    M.RefreshAssociations = function(...)
        local result = originalRefreshAssociations(...)
        if associationPanel and Nexus.Theme then Nexus.Theme.StyleTree(associationPanel) end
        return result
    end
end
