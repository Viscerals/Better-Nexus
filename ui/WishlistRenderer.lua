-- Nexus: ui/WishlistRenderer.lua
-- Wishlist editor, display popup, menus, tooltips, and bounded visible-row owner.

Nexus = Nexus or {}
Nexus.WishlistInternals = Nexus.WishlistInternals or {}

local Renderer = {}

-- Visible editor copy comes from the reviewed seam (core/Localization.lua,
-- keys "editor.*" and, for the display popup, "overlay.*"), looked up when it
-- is shown, never cached at load. Names, codes and game data fill template
-- text slots and are never translated. Raw English producer values that other
-- code compares (reason codes, stored names) stay raw; only their display is
-- localized here.
local function T(key) return (Nexus.Localization.Text(key)) end
local function TF(key, args) return (Nexus.Localization.Format(key, args)) end
local function N(value) return Nexus.Localization.Count(value) end

-- The code-owned names of the five Echo qualities (0..4); the editor's role
-- chooser uses the same keys.
local function QualityName(quality)
    local key = ({[0] = "editor.value.quality_common", [1] = "editor.value.quality_uncommon",
        [2] = "editor.value.quality_rare", [3] = "editor.value.quality_epic",
        [4] = "editor.value.quality_legendary"})[quality]
    return key and T(key) or nil
end

local function DisplayUntrusted(value, maxBytes, allowEmpty, allowLineBreaks)
    local identity = Nexus and Nexus.Identity
    if not (identity and type(identity.DisplaySafeText) == "function") then
        return nil
    end
    return identity.DisplaySafeText(
        value, maxBytes, allowEmpty, allowLineBreaks)
end

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
    local PICK_ROWS = 17
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
    -- Renderer reads controller-published projections (View below), with one
    -- narrow, authorized display-fact exception for the destination row. It
    -- reads three approved cached Panel view facts: the current-session
    -- character (Nexus.Panel.CachedDestinationCharacter()), the public
    -- world-session revision (Nexus.Panel.destinationSessionRevision) and
    -- the private session count (Nexus.Panel.DestinationSessionCount()).
    -- The row widget holds the cold refresh's existing Slots and
    -- SelectedSavedBuild observation with a session stamp. The revision
    -- counts only as a finite nonnegative whole number equal to the private
    -- count: the cold refresh binds its new stamp to that count, and
    -- M.Refresh keeps the observation only while the stamp equals both,
    -- passing Controller.DestinationPresentation the character and that
    -- observation only while it is held. A missing count accessor fails
    -- closed (nothing is held); a rolled-back revision is rejected once the
    -- count has advanced, even when it equals the old stamp. Restoring the
    -- revision never reacquires cleared facts; only the next natural cold
    -- observation can. Apart from the pure count accessor, these checks
    -- force no read or refresh and add no extra backend or character read,
    -- event, timer, getter work or action. These are display facts only,
    -- never draft, target or Save authority, and the Panel keeps owning the
    -- character, revision and count. Nexus.Panel stays a hard dependency of
    -- that row: EnsureFrame creates it through
    -- Nexus.Panel.CreateDestinationRow and both refresh paths dereference
    -- Nexus.Panel directly, so an unavailable Panel is outside this module's
    -- contract and raises an error instead of skipping the row. Only the
    -- missing count accessor is the guarded fail-closed case. The controller
    -- remains the sole owner of gameplay, Adapter access, associations,
    -- uploads, Save and assignment, Store
    -- writes, preferences, retries, and mutable draft authority; the
    -- renderer owns its transient presentation caches as before, the held
    -- observation among them.
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
        -- The Saved Build Nexus selects (never a native Wishlist index). A
        -- controller without that projection gives the native active slot only
        -- when it is in the declared range.
        SelectedSavedBuild = function(slots)
            if Controller.SelectedSavedBuild then return Controller.SelectedSavedBuild(slots) end
            local active = slots and tonumber(slots.activeSlot)
            local maxSlots = slots and tonumber(slots.maxSlots) or 5
            return active and active >= 1 and active <= maxSlots and active or nil
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


local function DismissSaveConfirmation()
    Controller.CancelApply()
    if type(StaticPopup_Hide) == "function" then
        StaticPopup_Hide("WISHLISTREALIZER_UPDATE_WISHLIST")
        StaticPopup_Hide("WISHLISTREALIZER_CREATE_WISHLIST")
    end
end

-- `intent`: the control's save intent (Controller.INTENT); the apply button
-- passes the draft's default (Save & assign when this new plan has a captured
-- destination, else Save changes), "Create unassigned" passes Save changes.
local function ApplyPending(intent)
    local text = wishlistNameBox and wishlistNameBox._NexusRawText
        and wishlistNameBox:_NexusRawText()
        or (wishlistNameBox and tostring(wishlistNameBox:GetText() or "") or "")
    if type(intent) ~= "string" then
        intent = Controller.DefaultIntent and Controller.DefaultIntent() or nil
    end
    local data, mode = Controller.PrepareApply(text, intent)
    if not data then
        if mode == "name" and wishlistNameBox then wishlistNameBox:SetFocus() end
        M.RenderSaveResult()
        return
    end
    local displayName = DisplayUntrusted(data.name, 1024, false) or T("editor.value.wishlist_fallback")
    local which = mode == "update" and "WISHLISTREALIZER_UPDATE_WISHLIST" or "WISHLISTREALIZER_CREATE_WISHLIST"
    -- Its accept button names the bound intent (M.ConfirmLabel).
    local dialog = type(StaticPopupDialogs) == "table" and StaticPopupDialogs[which] or nil
    if type(dialog) == "table" then dialog.button1 = M.ConfirmLabel(data, mode) end
    StaticPopup_Show(which, displayName, M.ConfirmationText(data, mode), data)
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

    GameTooltip:AddLine(name or TF("editor.value.echo_id_fallback", {id = tostring(id or "")}), 1, 1, 1)
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
        -- One line; the button's own tooltip adds the full text when shortened.
        if Nexus.LayoutMetrics then Nexus.LayoutMetrics.OneLineLabel(fs, nil, 22) end
    end
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(12,12)
    arrow:SetPoint("RIGHT", button, "RIGHT", -7, 0)
    button._arrow = arrow
end

-- Compact management list. State lives on the menu frame and the function
-- on M, so this adds no upvalue to Renderer.New.
-- A draft row's name: the model's own fallback for an Echo the catalog
-- lacks ("spell <id>", core/WishlistModel.lua) through its key; any other
-- name verbatim.
function M.DraftName(p)
    if type(p) ~= "table" then return nil end
    if p.name ~= nil and p.name == "spell " .. tostring(p.spellId) then
        return TF("editor.value.spell_id_fallback", {id = tostring(p.spellId)})
    end
    return p.name
end

function M.HideManageWishlistsMenu()
    if M._manageMenu then M._manageMenu:Hide() end
end

function M.ShowManageWishlistsMenu(anchor, offset)
    local perMenu = 8
    local plans = Controller.RetainedPlansProjection() or {}
    local support = Controller.ServerDeletionSupportProjection() or {}
    local undone = Controller.ForgottenPlansProjection() or {}
    local menu = M._manageMenu
    if not menu then
        menu = CreateFrame("Frame", "NexusWishlistManageMenu", frame or UIParent)
        menu:SetFrameStrata("TOOLTIP")
        menu:SetFrameLevel((frame and frame:GetFrameLevel() or 50) + 100)
        menu:SetToplevel(true)
        menu:EnableMouse(true)
        menu.rows = {}
        pcall(function()
            menu:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            menu:SetBackdropColor(0.015, 0.02, 0.03, 0.99)
            menu:SetBackdropBorderColor(0.48, 0.42, 0.25, 1)
        end)
        menu.header = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        menu.header:SetPoint("TOPLEFT", 10, -8)
        menu.header:SetPoint("TOPRIGHT", -10, -8)
        menu.header:SetJustifyH("LEFT")
        M._manageMenu = menu
    end
    if frame and menu:GetParent() ~= frame then menu:SetParent(frame) end

    -- Rows: the plans on this page, then the undo row when one is
    -- retained, then the pager when more plans exist than fit.
    local total = #plans
    local paged = total > perMenu
    local perPage = paged and (perMenu - 1) or perMenu
    if offset ~= nil then menu._offset = tonumber(offset) or 0 end
    local first = tonumber(menu._offset) or 0
    if not paged or first >= total or first < 0 then first = 0 end
    menu._offset = first
    local shown = math.min(perPage, total - first)
    local extra = #undone + (paged and 1 or 0)
    local visible = math.max(1, shown + extra)

    menu.header:SetText(TF("editor.heading.manage_count", {count = N(total)})
        .. "  |cff777777" .. (support.supported
            and T("editor.note.manage_removals_local")
            or TF("editor.note.manage_removals_reason",
                {reason = tostring(support.reason and Nexus.UserText.Recognized(support.reason)
                    or T("editor.note.manage_no_deletion_call"))})) .. "|r")
    -- The header wraps to its measured height; the rows start below it.
    local metrics = Nexus.LayoutMetrics
    local top = 8 + (metrics and metrics.WrapHeight(menu.header, 340, 12) or 14) + 4
    menu:SetSize(360, top + visible * 24 + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -3)

    for i = 1, visible do
        local row = menu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, menu)
            row:SetSize(344, 22)
            row:EnableMouse(true)
            row:RegisterForClicks("LeftButtonUp")
            row:SetFrameLevel(menu:GetFrameLevel() + 2)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", 8, 0)
            label:SetPoint("RIGHT", row, "RIGHT", -7, 0)
            label:SetJustifyH("LEFT")
            if metrics then metrics.OneLineLabel(label, row, 22) end
            row._label = label
            menu.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 8, -top - ((i - 1) * 24))
        local plan = (i <= shown) and plans[first + i] or nil
        local undoRow = (i > shown) and undone[i - shown] or nil
        local pagerRow = paged and i == visible
        if plan then
            local planName = DisplayUntrusted(plan.name, 1024, false)
                or TF("editor.value.wishlist_index_fallback", {index = tostring(plan.associationIndex)})
            -- Colour codes are not nested: the client's first |r closes the
            -- run it is in, so a nested one leaves the rest uncoloured and
            -- the trailing marker unmatched.
            local association
            if plan.usable then
                association = "|cff777777" .. TF("editor.menu.manage_row_saved_build",
                    {slot = tostring(plan.associationIndex), rows = N(tonumber(plan.rows) or 0)}) .. "|r"
            else
                association = "|cffff9040" .. TF("editor.menu.manage_row_not_saved_build",
                    {index = tostring(plan.associationIndex)}) .. "|r|cff777777, "
                    .. TF("editor.menu.manage_row_rows", {rows = N(tonumber(plan.rows) or 0)}) .. "|r"
            end
            row._label:SetTextColor(0.92, 0.92, 0.92)
            row._label:SetText(planName .. "  " .. association
                .. "  |cffff6060[" .. T("editor.menu.manage_remove") .. "]|r")
            row:Enable()
            -- The confirmation carries the identity, not the label: two
            -- plans may share a name, and only one is being removed.
            local confirmPlan = {
                associationIndex = plan.associationIndex, key = plan.key,
                assignmentId = plan.assignmentId, mirrorSlot = plan.mirrorSlot,
                name = planName, rows = plan.rows, usable = plan.usable,
                mirrorResolved = plan.mirrorResolved,
                mirrorSlotLive = plan.mirrorSlotLive,
                ordinaryCopies = plan.ordinaryCopies,
                lockedCopies = plan.lockedCopies,
            }
            row:SetScript("OnClick", function()
                M.HideManageWishlistsMenu()
                -- The confirmation repeats the facts this row showed, and
                -- states plainly what is and is not removed.
                -- Whether a server Wishlist survives this is a fact about
                -- the live list, not about the mirror number the record
                -- carries: a stored hint outlives the mirror it names.
                -- Three states, not two: a server Wishlist that holds exactly
                -- this plan, a mirror slot that still exists but no longer
                -- holds these contents, and nothing at all. Merging the last
                -- two is what let the dialog claim a copy that was not there.
                local where
                if confirmPlan.mirrorResolved then
                    where = T("editor.popup.forget_server_kept")
                elseif confirmPlan.mirrorSlotLive then
                    where = T("editor.popup.forget_slot_changed")
                else
                    where = T("editor.popup.forget_only_copy")
                end
                StaticPopup_Show("NEXUS_FORGET_WISHLIST",
                    TF("editor.popup.forget_question", {name = confirmPlan.name}) .. "\n"
                    .. TF("editor.popup.forget_facts", {rows = N(tonumber(confirmPlan.rows) or 0),
                        ordinary = N(tonumber(confirmPlan.ordinaryCopies) or 0),
                        locked = N(tonumber(confirmPlan.lockedCopies) or 0),
                        association = confirmPlan.usable
                            and TF("editor.value.saved_build_number",
                                {slot = tostring(confirmPlan.associationIndex)})
                            or TF("editor.value.association_not_saved_build",
                                {index = tostring(confirmPlan.associationIndex)})})
                    .. "\n" .. where .. "\n" .. T("editor.popup.forget_undo_hint"), nil, {
                    plan = confirmPlan,
                    forget = function(selector)
                        return Controller.ForgetRetainedPlan(selector)
                    end,
                    after = function() requestRefresh() end,
                })
            end)
            row:Show()
        elseif undoRow then
            local undoName = DisplayUntrusted(undoRow.name, 1024, false)
                or T("editor.value.removed_wishlist_fallback")
            row._label:SetTextColor(0.45, 0.95, 0.6)
            row._label:SetText(TF("editor.menu.manage_undo", {name = undoName}) .. "  |cff777777"
                .. TF("editor.menu.manage_undo_from", {index = tostring(undoRow.associationIndex)}) .. "|r")
            row:Enable()
            -- Each row takes back ITS removal, by the identity that row
            -- names, so an older one can be recovered without disturbing a
            -- newer one.
            local take = {position = undoRow.position, key = undoRow.key,
                assignmentId = undoRow.assignmentId}
            row:SetScript("OnClick", function()
                local ok, reason, detail = Controller.RestoreForgottenPlan(take)
                if not ok then
                    print("|cffff9040Nexus:|r " .. tostring(Nexus.UserText.Recognized(reason)))
                elseif type(detail) == "table" and detail.movedFrom ~= nil then
                    print("|cff4dff80Nexus:|r " .. TF("editor.chat.manage_restored_moved",
                        {name = undoName, slot = tostring(detail.loadoutSlot), from = tostring(detail.movedFrom)}))
                end
                requestRefresh()
                M.ShowManageWishlistsMenu(anchor, 0)
            end)
            row:Show()
        elseif pagerRow then
            local nextFirst = first + shown
            if nextFirst >= total then nextFirst = 0 end
            row._label:SetTextColor(0.85, 0.75, 0.45)
            row._label:SetText(TF("editor.menu.manage_more",
                {first = N(first + 1), last = N(first + shown), total = N(total)}) .. "  |cff777777"
                .. TF("editor.menu.pager_next", {count = N(math.min(perPage, total - nextFirst))}) .. "|r")
            row:Enable()
            row:SetScript("OnClick", function()
                M.ShowManageWishlistsMenu(anchor, nextFirst)
            end)
            row:Show()
        else
            row._label:SetTextColor(0.55, 0.55, 0.55)
            row._label:SetText(T("editor.menu.manage_empty"))
            row:SetScript("OnClick", nil)
            row:Disable()
            row:Show()
        end
    end
    for i = visible + 1, #menu.rows do menu.rows[i]:Hide() end
    menu:Show()
    return menu
end

local function HideWishlistSwitchMenu()
    if wishlistSwitchMenu then wishlistSwitchMenu:Hide() end
end

local function CandidateEvidenceSuffix(candidate)
    if type(candidate) == "table"
        and candidate.lockEvidenceStatus == "unavailable" then
        local editor=Nexus.WishlistEditor
        local hint=editor and editor.UnresolvedRoleHint and editor.UnresolvedRoleHint() or T("editor.status.hint_choose_locked_targets")
        return "  |cffff9040("..hint..")|r"
    end
    return ""
end

-- How many rows the menu shows at once, and where the visible window starts.
-- The offset survives between openings so a player who paged forward and
-- clicked a row does not start from the top again.
local WISHLIST_MENU_ROWS = 10
local wishlistSwitchOffset = 0

local function ShowWishlistSwitchMenu(anchor, offset)
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
    -- More candidates than rows: the last row becomes the pager, so nine are
    -- listed per page and every one of them is reachable by paging.
    local total = #candidates
    local paged = total > WISHLIST_MENU_ROWS
    local perPage = paged and (WISHLIST_MENU_ROWS - 1) or WISHLIST_MENU_ROWS
    if offset ~= nil then wishlistSwitchOffset = tonumber(offset) or 0 end
    if not paged or wishlistSwitchOffset >= total or wishlistSwitchOffset < 0 then
        wishlistSwitchOffset = 0
    end
    local first = wishlistSwitchOffset
    local shown = math.min(perPage, total - first)
    local visible = shown + (paged and 1 or 0)
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
            if Nexus.LayoutMetrics then Nexus.LayoutMetrics.OneLineLabel(label, row, 22) end
            row._check = check
            row._label = label
            wishlistSwitchMenu.rows[i] = row
        end
        -- The pager occupies the last row when there is more than one page.
        local pagerRow = paged and i == visible
        local c = (not pagerRow) and candidates[first + i] or nil
        if pagerRow then
            local nextFirst = first + shown
            if nextFirst >= total then nextFirst = 0 end
            row._check:Hide()
            row._label:SetTextColor(0.85, 0.75, 0.45)
            row._label:SetText(TF("editor.menu.switch_more",
                {first = N(first + 1), last = N(first + shown), total = N(total)}) .. "  |cff777777"
                .. TF("editor.menu.pager_next", {count = N(math.min(perPage, total - nextFirst))}) .. "|r")
            row:Enable()
            row:SetScript("OnClick", function()
                ShowWishlistSwitchMenu(anchor, nextFirst)
            end)
            row:Show()
        elseif c then
            local assignedSlot, assignedName = CandidateAssignment(c)
            local current=editingContext and ((editingContext.assignmentId and c.assignmentId
                and editingContext.assignmentId==c.assignmentId) or (not editingContext.assignmentId
                and not c.assignmentId and ((editingContext.key and c.key==editingContext.key)
                    or (c.slot and tonumber(editingContext.slot)==tonumber(c.slot)))))
            local wishlistLabel = DisplayUntrusted(c.name, 1024, false)
                or TF("editor.value.wishlist_index_fallback", {index = tostring(c.slot)})
            local displayAssignedName = assignedName
                and DisplayUntrusted(assignedName, 1024, false) or nil
            local suffix = displayAssignedName
                and ("  |cff777777" .. TF("editor.menu.switch_saved_build", {name = displayAssignedName}) .. "|r")
                or ("  |cff666666" .. T("editor.menu.switch_saved_build_none") .. "|r")
            -- A stored record whose map index names no Saved Build is
            -- shown and labelled here too, not only in the management
            -- list: it can be opened and saved, but it cannot be an
            -- assignment target.
            if c.associationUsable == false then
                suffix = suffix .. "  |cffff9040" .. TF("editor.menu.switch_index_not_saved_build",
                    {index = tostring(c.associationIndex)}) .. "|r"
            end
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
                evidenceSource=c.evidenceSource,
                assignmentId=c.assignmentId,designTargets=c.designTargets,
                loadoutName = assignedName or "None",
            }
            local openAssignedSlot = assignedSlot
            row:SetScript("OnClick", function()
                HideWishlistSwitchMenu()
                openForWishlist(openCandidate, openAssignedSlot)
            end)
            row:Show()
        else
            row._label:SetText(T("editor.menu.switch_empty"))
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
    DismissSaveConfirmation()
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
    if wishlistNameBox and wishlistNameBox._NexusSetRawText then
        wishlistNameBox:_NexusSetRawText("")
    end
    -- M.Show delegates here whenever a real Saved Build is active. An
    -- unassociated build is a valid new-wishlist destination, so this branch
    -- must show the editor just like OpenForWishlist does for linked builds.
    -- Without this, the Panel remains menu-suppressed while no editor appears.
    frame:Show()
    requestRefresh()
end

local function ShowLoadoutSwitchMenu(anchor)
    if loadoutSwitchMenu and frame and loadoutSwitchMenu:GetParent() ~= frame then loadoutSwitchMenu:SetParent(frame) end
    -- Saved Builds are the server's slots 1..maxSlots, as the server declares
    -- them (Slots() reports 5 when it declares nothing). Slots above that are
    -- Wishlist mirrors, never Saved Builds. A declaration that is not a whole
    -- number from 1 up is not trusted, and the selector keeps its five rows;
    -- a very large one is limited to MAX_SELECTOR_SLOTS rows (a display
    -- limit, not a statement about the server). Build this selector directly
    -- from those slots instead of relying on inferred candidates.
    local slots = View and View.Slots and View.Slots()
    -- The highlighted row is the Saved Build Nexus selects: the native active
    -- slot when it is one, never a native Wishlist index.
    local active = View.SelectedSavedBuild(slots) or 0
    local MAX_SELECTOR_SLOTS = 10
    local declared = slots and tonumber(slots.maxSlots)
    local count = 5
    if declared and declared >= 1 and declared < math.huge
        and declared == math.floor(declared) then
        count = math.min(declared, MAX_SELECTOR_SLOTS)
    end
    local candidates = {}
    for slot = 1, count do
        local data = slots and slots.bySlot and slots.bySlot[slot]
        local name = data and tostring(data.name or "") or ""
        if name == "" then name = TF("editor.value.saved_build_number", {slot = tostring(slot)}) end
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
    local visible = #candidates
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
            if Nexus.LayoutMetrics then Nexus.LayoutMetrics.OneLineLabel(label, row, 22) end
            row._label = label
            loadoutSwitchMenu.rows[i] = row
        end
        local c = candidates[i]
        if c then
            local label = DisplayUntrusted(c.name, 1024, false) or ""
            if label == "" then label = TF("editor.value.saved_build_number", {slot = tostring(c.slot)}) end
            local wishlistName = c.wishlist
                and DisplayUntrusted(c.wishlist.name, 1024, false) or nil
            local suffix = wishlistName and ("  |cff777777" .. wishlistName .. "|r")
                or ("  |cff666666" .. T("editor.menu.loadout_no_wishlist") .. "|r")
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
                row._label:SetText("|cff666666" .. TF("editor.menu.loadout_empty",
                    {slot = tostring(targetSlot)}) .. "|r")
            end
            row:Show()
        else
            row._label:SetText(T("editor.menu.loadout_none"))
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
            displayLockBtn:SetText(T(overlay.IsLocked()
                and "overlay.button.unlock_to_move" or "overlay.button.lock_position_settings"))
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
    title:SetText(T("overlay.title.settings"))

    local subtitle = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetSize(245, 28)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(T("overlay.body.settings_subtitle"))

    local close = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetFrameLevel(p:GetFrameLevel() + 5)
    -- Retain the compact themed glyph while restoring the old 32 px target.
    if close.SetHitRectInsets then close:SetHitRectInsets(-5, -5, -5, -5) end
    close:SetText("X")
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
    displayCheck.text:SetText(T("overlay.label.show_overlay"))
    displayCheck:SetScript("OnClick", function(self)
        local overlay = Overlay()
        if overlay then
            if self:GetChecked() then overlay.Show() else overlay.Hide() end
        end
    end)

    local moveLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    moveLabel:SetPoint("TOPLEFT", 18, -102)
    moveLabel:SetText(T("overlay.label.position"))

    displayLockBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    displayLockBtn:SetSize(92, 22)
    displayLockBtn:SetPoint("LEFT", moveLabel, "RIGHT", 16, 0)
    displayLockBtn:SetFrameLevel(p:GetFrameLevel() + 5)
    displayLockBtn:EnableMouse(true)
    displayLockBtn:SetScript("OnClick", function()
        local overlay = Overlay()
        if overlay then
            overlay.ToggleLock()
            displayLockBtn:SetText(T(overlay.IsLocked()
                and "overlay.button.unlock_to_move" or "overlay.button.lock_position_settings"))
        end
    end)

    local resetBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    resetBtn:SetSize(100, 22)
    resetBtn:SetPoint("LEFT", displayLockBtn, "RIGHT", 10, 0)
    resetBtn:SetFrameLevel(p:GetFrameLevel() + 5)
    resetBtn:EnableMouse(true)
    resetBtn:SetText(T("overlay.button.reset_position"))
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
    hint:SetText(T("overlay.body.lock_hint"))

    local sizeLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizeLabel:SetPoint("TOPLEFT", 18, -164)
    sizeLabel:SetText(T("overlay.label.size"))

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

    -- The two explanatory texts take their measured height (a wider face
    -- needs more lines); the controls below them move down by the extra.
    local function LayoutDisplayPopup()
        local metrics = Nexus.LayoutMetrics
        if not metrics then return end
        local extra = metrics.WrapHeight(subtitle, 245, 28) - 28
        displayCheck:ClearAllPoints(); displayCheck:SetPoint("TOPLEFT", 16, -68 - extra)
        moveLabel:ClearAllPoints(); moveLabel:SetPoint("TOPLEFT", 18, -102 - extra)
        hint:ClearAllPoints(); hint:SetPoint("TOPLEFT", 18, -128 - extra)
        extra = extra + metrics.WrapHeight(hint, 260, 24) - 24
        sizeLabel:ClearAllPoints(); sizeLabel:SetPoint("TOPLEFT", 18, -164 - extra)
        scaleSlider:ClearAllPoints(); scaleSlider:SetPoint("TOPLEFT", 20, -195 - extra)
        -- Room below the slider for its Low/High labels, clear of the border.
        p:SetHeight(236 + extra)
    end

    local theme = Nexus.Theme
    if theme then
        if theme.StyleWindow then theme.StyleWindow(p, 0.98) end
        if theme.StyleTree then theme.StyleTree(p) end
        if theme.StyleLabel then
            theme.StyleLabel(title, "accent")
            theme.StyleLabel(subtitle, "muted")
            theme.StyleLabel(displayCheck.text, "text")
            theme.StyleLabel(moveLabel, "text")
            theme.StyleLabel(hint, "muted")
            theme.StyleLabel(sizeLabel, "text")
            theme.StyleLabel(scaleValueText, "text")
            local sliderName = scaleSlider:GetName()
            for _, suffix in ipairs({"Low", "High", "Text"}) do
                theme.StyleLabel(sliderName and _G[sliderName .. suffix], "muted")
            end
        end
    end

    p:SetScript("OnShow", function(self)
        self:SetFrameStrata("TOOLTIP")
        self:SetFrameLevel(100)
        self:EnableMouse(true)
        LayoutDisplayPopup()
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

-- Where the Display Settings popup opens, relative to the editor (native QA
-- test.163008). Anchored under its button, the 300 px TOOLTIP-strata popup
-- covered the editor's upper-right control band (Import / Export, My Builds,
-- the locked Echo slots with their Auto-manage checkbox and Plan
-- alternatives), so those could not be clicked while it was open. It now
-- opens beside the editor where the screen has room for it, else inside the
-- editor with its top below that band (over the Selected Echoes list). Pure:
-- spec.editor {left, top, right, bottom} in UIParent units (y up, as
-- GetLeft/GetTop report scaled to UIParent), spec.ratio editor units to
-- UIParent units (a FitToScreen-scaled editor is below 1), spec.screenW,
-- spec.width the popup width. Returns {where, point, relativePoint, x, y}
-- for popup:SetPoint(point, editor, relativePoint, x, y); offsets are in the
-- popup's own (UIParent) units.
M.DISPLAY_POPUP_BAND_BOTTOM = 182 -- editor units: Plan alternatives' bottom (154 + 22) and a 6 px gap
M.DISPLAY_POPUP_BUTTON_BOTTOM = 94 -- editor units: Display Settings' bottom (66 + 22) and a 6 px gap
function M.DisplayPopupPlacement(spec)
    local e, ratio = spec.editor, tonumber(spec.ratio) or 1
    local width, gap = tonumber(spec.width) or 300, 6
    local screenW = tonumber(spec.screenW) or 0
    local beside = -M.DISPLAY_POPUP_BUTTON_BOTTOM * ratio
    if e and screenW > 0 then
        if e.right + gap + width <= screenW then
            return {where="right", point="TOPLEFT", relativePoint="TOPRIGHT", x=gap, y=beside}
        end
        if e.left - gap - width >= 0 then
            return {where="left", point="TOPRIGHT", relativePoint="TOPLEFT", x=-gap, y=beside}
        end
    end
    return {where="inside", point="TOPRIGHT", relativePoint="TOPRIGHT", x=-34 * ratio,
        y=-M.DISPLAY_POPUP_BAND_BOTTOM * ratio}
end

local function ToggleDisplayPopup(anchorTo)
    local p = EnsureDisplayPopup()
    if p:IsShown() then
        p:Hide()
        return
    end
    p:ClearAllPoints()
    if frame and frame:IsVisible() then
        local parentScale = UIParent:GetEffectiveScale()
        local ratio = (parentScale and parentScale > 0)
            and (frame:GetEffectiveScale() / parentScale) or 1
        local left, top, right, bottom = frame:GetLeft(), frame:GetTop(), frame:GetRight(), frame:GetBottom()
        local edges = (left and top and right and bottom) and {left=left * ratio, top=top * ratio,
            right=right * ratio, bottom=bottom * ratio} or nil
        local place = M.DisplayPopupPlacement({editor=edges, ratio=ratio,
            screenW=UIParent:GetWidth(), width=p:GetWidth()})
        p:SetPoint(place.point, frame, place.relativePoint, place.x, place.y)
        p._nexusPlacement = place.where
    elseif anchorTo and anchorTo.IsVisible and anchorTo:IsVisible() then
        p:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 0, -6)
    else
        p:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    p:Show()
end

------------------------------------------------------------------------
-- Frame construction
------------------------------------------------------------------------

local function HideEditorTransients()
    DismissSaveConfirmation()
    HideDisplayPopup()
    HideWishlistSwitchMenu()
    HideLoadoutSwitchMenu()
    -- The Manage list, and a removal confirmation opened from it, state the
    -- facts read when the list was drawn. They close with the editor, so a
    -- reopened editor needs a new Manage click and shows current facts.
    M.HideManageWishlistsMenu()
    if type(StaticPopup_Hide) == "function" then
        StaticPopup_Hide("NEXUS_FORGET_WISHLIST")
    end
end

-- Locked strip slot `i`, made once (fields on M, so Renderer.New and the
-- frame builder gain no local or upvalue). The strip holds the six authored
-- target cells; RefreshView adds a slot for each occupied record, or live
-- capacity, beyond them.
function M.EnsureLockedIcon(i)
    if lockedIcons[i] then return lockedIcons[i] end
    -- Each slot sits right of the one before it, which is made first.
    local previous = i > 1 and M.EnsureLockedIcon(i - 1) or nil
    local btn = CreateFrame("Button", nil, frame)
    btn:SetSize(18, 18)
    if i == 1 then
        btn:SetPoint("LEFT", lockedLabel, "RIGHT", 8, 0)
    else
        btn:SetPoint("LEFT", previous, "RIGHT", 4, 0)
    end
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints(btn)
    btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnEnter", function(self)
        if self.slotState == "empty" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(T("editor.tooltip.locked_slot_empty"), 1, 1, 1)
            GameTooltip:AddLine(T("editor.tooltip.locked_slot_empty_click"), 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        elseif self.spellId then
            ShowEchoTooltip(self, self.spellId, "ANCHOR_RIGHT")
            if self.slotState == "designed" then
                GameTooltip:AddLine(T("editor.tooltip.locked_slot_planned"), 1, 0.85, 0.3, true)
                GameTooltip:Show()
            elseif self.slotState == "locked" then
                if self.beingReplaced then
                    GameTooltip:AddLine(T("editor.tooltip.locked_slot_replacing") .. " "
                        .. T("editor.tooltip.locked_slot_automatic") .. " "
                        .. T("editor.tooltip.locked_slot_cancel"), 1, 0.6, 0.4, true)
                else
                    GameTooltip:AddLine(T("editor.tooltip.locked_slot_find"), 0.8, 0.8, 0.8, true)
                    GameTooltip:AddLine(T("editor.tooltip.locked_slot_replace"), 0.8, 0.8, 0.8, true)
                end
                GameTooltip:Show()
            end
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Right-click on a real slot only starts (or cancels) planning its
    -- replacement; nothing is locked or unlocked here and the current Echo
    -- stays locked. Only the optional locked-Echo slot automation
    -- (AutomationRuntime TryAutoLock: Automation and its separate option ON,
    -- the replacement owned, a stable Saved Build association for the unlock,
    -- and its other checks) may later unlock the old Echo and lock the new
    -- one through GameAdapter.LockPerk/UnlockPerk.
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
    return btn
end

-- "Needed" icon of locked slot `i`: directly above that slot's icon
-- (anchored to its TOP, not a same-row neighbor) -- only shown for a column
-- whose current Echo has an active replacement designed, so "what you have
-- vs. what you're working toward" reads as a simple stacked pair instead of
-- two unrelated icons sitting side by side.
function M.EnsureLockedNeedIcon(i)
    if lockedNeedIcons[i] then return lockedNeedIcons[i] end
    local btn = CreateFrame("Button", nil, frame)
    btn:SetSize(14, 14)
    btn:SetPoint("BOTTOM", M.EnsureLockedIcon(i), "TOP", 0, 2)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints(btn)
    btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    btn.icon:SetVertexColor(1, 0.85, 0.3)
    btn:SetScript("OnEnter", function(self)
        if not self.spellId then return end
        ShowEchoTooltip(self, self.spellId, "ANCHOR_TOP")
        GameTooltip:AddLine(T("editor.tooltip.locked_need_icon"), 1, 0.85, 0.3, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function(self)
        if self.draftKey then ToggleDesignLock(self.draftKey); requestRefresh() end
    end)
    btn:Hide()
    lockedNeedIcons[i] = btn
    return btn
end

local function EnsureFrame()
    if frame then return frame end
    local function SafeDisplay(value, maxBytes, allowEmpty, allowLineBreaks)
        local identity = Nexus and Nexus.Identity
        if not (identity and type(identity.DisplaySafeText) == "function") then
            return nil
        end
        return identity.DisplaySafeText(value, maxBytes, allowEmpty,
            allowLineBreaks)
    end
    frame = CreateFrame("Frame", "NexusEditorFrame", UIParent)
    frame:SetClampedToScreen(true)
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "NexusEditorFrame")
    end
    frame:SetSize(1040, 680)
    frame:SetPoint("CENTER")
    -- StaticPopup confirmations use DIALOG in the native 3.3.5 client.
    -- Keep this editor below them so Save/Cancel remain visible and clickable.
    frame:SetFrameStrata("HIGH")
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
                        wishlistNameBox and wishlistNameBox._NexusRawText
                            and wishlistNameBox:_NexusRawText()
                            or (wishlistNameBox and wishlistNameBox:GetText() or ""))
                if promoted then
                    if wishlistNameBox and wishlistNameBox._NexusSetRawText then
                        wishlistNameBox:_NexusSetRawText(wishlistName or "")
                    end
                end
                requestRefresh()
            end
        end
    end)
    frame:SetScript("OnShow", function(self)
        -- 1040 px is wider than a 4:3 UI at scale 1; keep the edges on screen.
        if Nexus.LayoutMetrics then Nexus.LayoutMetrics.FitToScreen(self) end
        hideServerEchoUI()
    end)
    frame:SetScript("OnHide", HideEditorTransients)
    frame:Hide()

    titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOP", 0, -14)
    titleText:SetText(Nexus.Localization.Text("editor.title.editor"))

    -- The 972x18 context row under the header is the destination row:
    -- editContextText is its first visible cell (character), and the row,
    -- not that cell, is centred under the shared workspace header (the title
    -- is placed in the header row, FullUIWorkspaces.ApplyHeader). It spans
    -- the content width (1040 less 34 on each side; it was 900), so the
    -- shared formatter can show more of the destination before shortening
    -- (displayed item 6, #173). M.Refresh fills it.
    editContextText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    editContextText:SetJustifyH("LEFT")
    frame._destinationRow = Nexus.Panel.CreateDestinationRow(frame, editContextText)
    frame._destinationRow:SetPoint("TOP", frame, "TOP", 0, -38)
    frame._destinationRow:SetSize(972, 18)

    wishlistNameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wishlistNameLabel:SetPoint("TOPLEFT", 34, -96)
    wishlistNameLabel:SetText(Nexus.Localization.Text("editor.label.wishlist_name"))

    wishlistNameBox = CreateFrame("EditBox", "NexusWishlistNameInput", frame, "InputBoxTemplate")
    wishlistNameBox:SetSize(260, 22)
    wishlistNameBox:SetPoint("LEFT", wishlistNameLabel, "RIGHT", 10, 0)
    wishlistNameBox:SetAutoFocus(false)
    -- M4 (PRIORITY.N14): the field admits 96 letters; a display-only
    -- projection can double every pipe, so it must admit the full inert form.
    -- A typed name is not shortened by Nexus. A generated copy name is capped
    -- at 96 letters / 120 bytes at a whole UTF-8 letter (WishlistModel
    -- UniqueName), the name size an EBH1 code carries (Codec). The server's
    -- own Wishlist name limit is not known here and is not assumed.
    wishlistNameBox:SetMaxLetters(96)
    wishlistNameBox._NexusSetRawText = function(self, value)
        local raw = tostring(value or "")
        local identity = Nexus and Nexus.Identity
        local display = identity and identity.DisplaySafeText
            and identity.DisplaySafeText(raw, 1024, true) or ""
        self._nexusRawText = raw
        self._nexusDisplayText = display
        if self:GetText() ~= display then
            self._nexusNormalizing = true
            self:SetText(display)
            self._nexusNormalizing = nil
        end
    end
    wishlistNameBox._NexusRawText = function(self)
        local current = tostring(self:GetText() or "")
        if current ~= self._nexusDisplayText then
            local changed = self:GetScript("OnTextChanged")
            if changed then changed(self) end
        end
        return self._nexusRawText or current
    end
    wishlistNameBox:SetScript("OnTextChanged", function(self)
        if self._nexusNormalizing then return end
        local display = tostring(self:GetText() or "")
        local cursor = self:GetCursorPosition()
        local raw = display:gsub("||", "|")
        local rawPrefix = cursor and display:sub(1, cursor):gsub("||", "|")
        self:_NexusSetRawText(raw)
        if cursor and self.SetCursorPosition then
            local identity = Nexus and Nexus.Identity
            local displayPrefix = identity and identity.DisplaySafeText
                and identity.DisplaySafeText(rawPrefix, 1024, true)
            self:SetCursorPosition(displayPrefix and #displayPrefix or cursor)
        end
    end)
    wishlistNameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    wishlistNameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local buildsNav = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    buildsNav:SetSize(108, 22)
    buildsNav:SetPoint("TOPLEFT", 18, -12)
    buildsNav:SetText(Nexus.Localization.Text("editor.button.build_library_nav"))
    if Nexus.LoadingStatus then Nexus.LoadingStatus.BindSharedButton(buildsNav,buildsNav:GetText()) end
    buildsNav:SetScript("OnClick", function()
        frame:Hide()
        if Nexus.CommunityBuilds then Nexus.CommunityBuilds.Show() end
    end)
    local boardNav = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    boardNav:SetSize(102, 22)
    boardNav:SetPoint("LEFT", buildsNav, "RIGHT", 4, 0)
    boardNav:SetText(Nexus.Localization.Text("editor.button.leaderboard_nav"))
    if Nexus.LoadingStatus then Nexus.LoadingStatus.BindSharedButton(boardNav,boardNav:GetText()) end
    boardNav:SetScript("OnClick", function()
        frame:Hide()
        if Nexus.Leaderboard then Nexus.Leaderboard.Show() end
    end)
    local wishNav = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    wishNav:SetSize(92, 22)
    wishNav:SetPoint("LEFT", boardNav, "RIGHT", 4, 0)
    wishNav:SetText("|cffffd200" .. Nexus.Localization.Text("editor.button.wishlists_nav") .. "|r")
    wishNav:Disable()
    -- Help is the guided setup coach (Help.OpenHelp; native QA test.163008);
    -- Reference, at the top right clear of the centred title, is the manual's
    -- Wishlists page. The editor stays open below either (HIGH under their
    -- DIALOG); nothing is saved or discarded.
    frame._helpNav = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame._helpNav:SetSize(56, 22)
    frame._helpNav:SetPoint("LEFT", wishNav, "RIGHT", 4, 0)
    frame._helpNav:SetText(Nexus.Localization.Text("editor.button.help"))
    frame._helpNav:SetScript("OnClick", function()
        if Nexus.Help and Nexus.Help.OpenHelp then Nexus.Help.OpenHelp("wishlists") end
    end)
    frame._referenceNav = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame._referenceNav:SetSize(84, 22)
    frame._referenceNav:SetPoint("TOPRIGHT", -40, -12)
    frame._referenceNav:SetText(Nexus.Localization.Text("editor.button.reference"))
    frame._referenceNav:SetScript("OnClick", function()
        if Nexus.Help and Nexus.Help.OpenReference then Nexus.Help.OpenReference("wishlists") end
    end)
    if Nexus.FullUIWorkspaces then
        Nexus.FullUIWorkspaces.BindTabs(frame, "plan", {
            plan = wishNav, builds = buildsNav, records = boardNav,
        })
        -- LoadingStatus can repaint these labels after construction. Keep its
        -- guarded buttons and pending-state tooltips, with the workspace names
        -- BindTabs just painted (FullUIWorkspaces owns them and their wording).
        if Nexus.LoadingStatus then
            local exploreLabel, recordsLabel = buildsNav:GetText(), boardNav:GetText()
            Nexus.LoadingStatus.BindSharedButton(buildsNav,
                (exploreLabel ~= nil and exploreLabel ~= "") and exploreLabel or "Explore")
            Nexus.LoadingStatus.BindSharedButton(boardNav,
                (recordsLabel ~= nil and recordsLabel ~= "") and recordsLabel or "Records")
        end
        -- The tabs, Help, Reference and the title at the shared header's
        -- anchors, as in Explore and Records.
        Nexus.FullUIWorkspaces.ApplyHeader(frame, frame, {
            title = titleText, help = frame._helpNav, reference = frame._referenceNav,
        })
    end

    loadoutSwitchBtn = CreateFrame("Button", nil, frame)
    loadoutSwitchBtn:SetSize(230, 22)
    loadoutSwitchBtn:SetPoint("TOPLEFT", 34, -66)
    loadoutSwitchBtn:SetText(Nexus.Localization.Text("editor.button.saved_build_choose"))
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
        if Nexus.LayoutMetrics and Nexus.LayoutMetrics.Shortened(self:GetFontString()) then
            GameTooltip:AddLine(self:GetText(), 1, 1, 1, true)
        end
        GameTooltip:AddLine(Nexus.Localization.Text("editor.tooltip.saved_build_heading"), 1, 0.8, 0.3)
        GameTooltip:AddLine(Nexus.Localization.Text("editor.tooltip.saved_build_body"), 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    loadoutSwitchBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Named like the other editor controls, so the switch list can be driven
    -- by the prototype suite the way a player drives it.
    wishlistSwitchBtn = CreateFrame("Button", "NexusWishlistEditorSwitchButton", frame)
    wishlistSwitchBtn:SetSize(270, 22)
    wishlistSwitchBtn:SetPoint("LEFT", loadoutSwitchBtn, "RIGHT", 8, 0)
    wishlistSwitchBtn:SetText(Nexus.Localization.Text("editor.button.wishlist_choose"))
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
        if Nexus.LayoutMetrics and Nexus.LayoutMetrics.Shortened(self:GetFontString()) then
            GameTooltip:AddLine(self:GetText(), 1, 1, 1, true)
        end
        GameTooltip:AddLine(Nexus.Localization.Text("editor.tooltip.switch_heading"), 1, 0.8, 0.3)
        GameTooltip:AddLine(Nexus.Localization.Text("editor.tooltip.switch_body"), 0.8, 0.8, 0.8, true)
        -- Displayed item 6 (#173): Editing names what this editor opened and
        -- holds; it is not a statement about the current assignment, which
        -- this hover does not read.
        if Controller.EditingContext and Controller.EditingContext() then
            GameTooltip:AddLine(Nexus.Localization.Text("editor.tooltip.switch_editing"), 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    wishlistSwitchBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame._manageBtn = CreateFrame("Button", "NexusWishlistEditorManageButton",
        frame, "UIPanelButtonTemplate")
    frame._manageBtn:SetSize(88, 22)
    frame._manageBtn:SetText(Nexus.Localization.Text("editor.button.manage"))
    frame._manageBtn:SetScript("OnClick", function(self)
        HideWishlistSwitchMenu()
        if M._manageMenu and M._manageMenu:IsShown() then
            M.HideManageWishlistsMenu()
        else
            M.ShowManageWishlistsMenu(self)
        end
    end)
    frame._manageBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(Nexus.Localization.Text("editor.tooltip.manage_heading"), 1, 0.8, 0.3)
        GameTooltip:AddLine(Nexus.Localization.Text("editor.tooltip.manage_body"), 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame._manageBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    newWishlistBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    newWishlistBtn:SetSize(112, 22)
    newWishlistBtn:SetPoint("LEFT", wishlistSwitchBtn, "RIGHT", 8, 0)
    frame._manageBtn:SetPoint("LEFT", newWishlistBtn, "RIGHT", 6, 0)
    newWishlistBtn:SetText("+ " .. Nexus.Localization.Text("editor.button.new_wishlist"))
    newWishlistBtn:SetScript("OnClick", function()
        HideWishlistSwitchMenu()
        newWishlist()
    end)
    -- Plan's deliberate game routes remain visible alongside the editor.
    -- The assignment chooser makes no choice on opening, and navigation is
    -- refused while a Save confirmation/retry could be cancelled by OnHide.
    frame._workspaceAssignBtn = CreateFrame("Button", nil, frame,
        "UIPanelButtonTemplate")
    frame._workspaceAssignBtn:SetSize(94, 22)
    frame._workspaceAssignBtn:SetPoint("LEFT", frame._manageBtn, "RIGHT", 4, 0)
    frame._workspaceAssignBtn:SetText(Nexus.Localization.Text("editor.button.assign_menu"))
    frame._workspaceAssignBtn:SetScript("OnClick", function()
        if Nexus.FullUIWorkspaces then
            local ok, reason = Nexus.FullUIWorkspaces.OpenPlanAction("assignment")
            if not ok then print("|cffffd200Nexus:|r " .. tostring(Nexus.UserText.Recognized(reason))) end
        end
    end)
    frame._workspaceAssignBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(Nexus.Localization.Text("editor.tooltip.assign_heading"), 1, .82, .2)
        GameTooltip:AddLine(Nexus.Localization.Text("editor.tooltip.assign_body"), .8, .8, .8, true)
        GameTooltip:Show()
    end)
    frame._workspaceAssignBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Locked Echoes strip: one slot per occupied locked record the game
    -- reports (RefreshView shows at least the six authored target cells, and
    -- more, up to eight, for more records or a higher live capacity), plus an
    -- editable picker for slots that are not locked yet. The strip never
    -- locks or unlocks: a real slot's left-click jumps the search to it and
    -- its right-click plans a replacement; click an empty slot to assign a
    -- target and a gold (designed) slot to un-assign it. Lock/unlock writes
    -- happen only in the optional locked-Echo slot automation
    -- (AutomationRuntime TryAutoLock, through GameAdapter.LockPerk/UnlockPerk)
    -- and its checks. This is the dedicated slot picker requested in place of
    -- a lock toggle scattered across every row of the pick list.
    lockedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lockedLabel:SetPoint("TOPLEFT", 540, -130)
    lockedLabel:SetText(Nexus.Localization.Text("editor.label.locked_initial"))
    lockedLabel:Hide()

    lockedIcons = {}
    for i = 1, 6 do M.EnsureLockedIcon(i) end
    lockedNeedIcons = {}
    for i = 1, 6 do M.EnsureLockedNeedIcon(i) end
    -- RefreshView reaches the slot builders through the frame (no upvalue).
    frame._nexusLockedSlot = function(i)
        return M.EnsureLockedIcon(i), M.EnsureLockedNeedIcon(i)
    end

    -- Auto-lock opt-in: off by default (controller-owned preference,
    -- see DefaultProfile.lua and AutomationRuntime.lua's TryAutoLock). Deliberately
    -- separate from the main automation switch -- a player may want full
    -- board automation without also handing Nexus this specific, more
    -- consequential write action (LockPerk/UnlockPerk). Sits in the open
    -- space to the right of the locked-slot icon strip.
    autoLockCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    autoLockCheck:SetSize(22, 22)
    autoLockCheck:SetPoint("LEFT", lockedIcons[6], "RIGHT", 26, 0)
    autoLockCheck._nexusAnchorSlot = 6
    autoLockCheck:SetScript("OnClick", function(self)
        Controller.SetAutoLockEnabled(self:GetChecked() and true or false)
    end)
    autoLockCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Nexus.Localization.Text("editor.tooltip.autolock_heading"), 1, 0.8, 0.3)
        GameTooltip:AddLine(Nexus.Localization.Text("editor.tooltip.autolock_body"), 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(Nexus.Localization.Text("editor.tooltip.autolock_manual"), 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    autoLockCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local autoLockLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoLockLabel:SetPoint("LEFT", autoLockCheck, "RIGHT", 2, 0)
    autoLockLabel:SetJustifyH("LEFT")
    autoLockLabel:SetText(Nexus.Localization.Text("editor.label.autolock_full"))
    frame._autoLockLabel = autoLockLabel

    -- Nexus-native EBH1 import/export. Closures deliberately reference only
    -- the global StaticPopup_Show and a string literal -- no module-level
    -- upvalues added to this function (see the EnsureFrame upvalue-limit
    -- crash, Dev Test 17; Create() gets the same treatment on principle).
    local exportBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportBtn:SetSize(70, 22)
    exportBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, -100)
    exportBtn:SetText(Nexus.Localization.Text("editor.button.export"))
    exportBtn:SetScript("OnClick", function() StaticPopup_Show("NEXUS_EXPORT_WISHLIST") end)

    local importBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importBtn:SetSize(70, 22)
    importBtn:SetPoint("RIGHT", exportBtn, "LEFT", -4, 0)
    importBtn:SetText(Nexus.Localization.Text("editor.button.import"))
    importBtn:SetScript("OnClick", function() StaticPopup_Show("NEXUS_IMPORT_WISHLIST") end)

    local planBtn = CreateFrame("Button", "NexusFlexiblePlanEntry", frame, "UIPanelButtonTemplate")
    planBtn:SetSize(148, 22)
    -- Above the Selected Echoes list it can replace, right-aligned with that
    -- pane and Export: clear of the save-result line, its hover area, Assign
    -- now, Import and Export in the row above.
    planBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, -154)
    planBtn:SetText(Nexus.Localization.Text("editor.button.plan_alternatives"))
    planBtn:SetScript("OnClick", function() Nexus.WishlistEditor.OpenFlexiblePlanChooser() end)

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
        -- A wishlist name stays inside its button; the full label is in a tooltip.
        local label = b:GetFontString()
        if label and Nexus.LayoutMetrics then
            label:SetWidth(103)
            Nexus.LayoutMetrics.OneLineLabel(label, b, 20, "ANCHOR_BOTTOM")
        end
        b:Hide()
        candidateButtons[i] = b
    end

    -- Overlay controls, moved to the top-right where they're actually
    -- visible instead of buried at the bottom of a long window.
    local displayBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    displayBtn:SetSize(150, 22)
    displayBtn:SetPoint("TOPRIGHT", -34, -66)
    displayBtn:SetText(Nexus.Localization.Text("editor.button.display_settings"))
    displayBtn:SetScript("OnClick", function(self) ToggleDisplayPopup(self) end)
    displayBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(Nexus.Localization.Text("editor.tooltip.display_heading"), 1, 1, 1)
        GameTooltip:AddLine(Nexus.Localization.Text("editor.tooltip.display_body_start"), 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(Nexus.Localization.Text("editor.tooltip.display_body_end"), 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    displayBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    searchBox = CreateFrame("EditBox", "NexusEditorSearch", frame,
        "InputBoxTemplate")
    -- 250 units (was 330) leave the locked-slot strip and its automation
    -- caption room to the left of My Builds; see frame._fitAutoLock.
    searchBox:SetSize(250, 22)
    searchBox:SetPoint("TOPLEFT", 34, -126)
    searchBox:SetAutoFocus(false)
    searchBox:SetText(Controller.FilterState().search)
    searchBox:SetScript("OnTextChanged", function(self)
        Controller.SetSearch(self:GetText() or "")
        requestRefresh()
    end)
    -- The design's "Search Echoes" placeholder: shown while the box is empty
    -- and not being typed in; the filter itself is unchanged.
    searchBox._nexusHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchBox._nexusHint:SetPoint("LEFT", searchBox, "LEFT", 6, 0)
    searchBox._nexusHint:SetText(Nexus.Localization.Text("editor.placeholder.search"))
    local function SyncSearchHint(self)
        local empty = (self:GetText() or "") == ""
        if empty and not self._nexusFocused then self._nexusHint:Show() else self._nexusHint:Hide() end
    end
    searchBox:HookScript("OnTextChanged", SyncSearchHint)
    searchBox:HookScript("OnEditFocusGained", function(self) self._nexusFocused = true; SyncSearchHint(self) end)
    searchBox:HookScript("OnEditFocusLost", function(self) self._nexusFocused = nil; SyncSearchHint(self) end)
    SyncSearchHint(searchBox)

    classCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    classCheck:SetPoint("LEFT", searchBox, "RIGHT", 12, 0)
    classCheck:SetChecked(Controller.FilterState().classOnly)
    classCheck.text = classCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    classCheck.text:SetPoint("LEFT", classCheck, "RIGHT", -2, 1)
    classCheck.text:SetText(Nexus.Localization.Text("editor.label.class_only"))
    classCheck:SetScript("OnClick", function(self)
        Controller.SetClassOnly(self:GetChecked() and true or false)
        requestRefresh()
    end)

    -- The native My Builds route is distinct from the Nexus Build Library
    -- (the Explore tab above). It used to be hidden here, which made the
    -- Plan footer's promise unreachable inside the real workspace.
    frame._workspaceMyBuildsBtn = CreateFrame("Button", nil, frame,
        "UIPanelButtonTemplate")
    frame._workspaceMyBuildsBtn:SetSize(140, 22)
    frame._workspaceMyBuildsBtn:SetPoint("TOPRIGHT", -34, -126)
    frame._workspaceMyBuildsBtn:SetText(Nexus.Localization.Text("editor.button.my_builds_game"))
    frame._workspaceMyBuildsBtn:SetScript("OnClick", function()
        if Nexus.FullUIWorkspaces then
            local ok, reason = Nexus.FullUIWorkspaces.OpenPlanAction("mybuilds")
            if not ok then print("|cffffd200Nexus:|r " .. tostring(Nexus.UserText.Recognized(reason))) end
        end
    end)
    frame._workspaceMyBuildsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(Nexus.Localization.Text("editor.tooltip.my_builds_heading"), 1, .82, .2)
        GameTooltip:AddLine(Nexus.Localization.Text("editor.tooltip.my_builds_body"), .8, .8, .8, true)
        GameTooltip:Show()
    end)
    frame._workspaceMyBuildsBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    -- Displayed item 3 (#173): the separate, default-OFF locked-slot
    -- automation option says what it is for without a hover. Its caption
    -- ends 8 units left of My Builds (game) in the closed state, at every
    -- slot count and Locked (n/m) width; its room is worked out from the same
    -- anchors (18-unit slots 4 apart, the checkbox 12 right of the last). The
    -- strip starts 12 units after the "Current class only" caption (never
    -- right of the former x 540), so the caption has the room the narrower
    -- search box leaves. The whole caption is shown on one line, else on up
    -- to three measured lines (as many 14-unit-high lines as fit 42 units
    -- beside the strip), else "Auto-manage locked slots" the same way; each
    -- shown form names locked slots. With no room for either beside the
    -- strip (the largest text sizes), the box and caption take their own
    -- line under it (see below). The complete name stays on hover
    -- over the label and the checkbox. Presentation only; the checkbox, its
    -- setting and its guards are unchanged.
    local autoLockHit = Nexus.LayoutMetrics and Nexus.LayoutMetrics.FullTextTooltip
        and Nexus.LayoutMetrics.FullTextTooltip(autoLockLabel, frame) or nil
    -- The check box itself is placed here too: 12 units after the last slot
    -- while that leaves it 8 units left of My Builds, otherwise closer (never
    -- nearer than 6), so a long Locked (n/m) text or larger font cannot push
    -- the box under My Builds while only its label is hidden. The Locked
    -- (n/m) caption itself is the one part that grows with text: it is cut
    -- (whole on its own hover) where the box would come nearer than 6 units
    -- to the last slot, so the box ends 8 units left of My Builds at every
    -- slot count and font size. _autoLockClear says whether it does.
    -- The caption's hover always repeats the whole current caption, cut or
    -- not: whether a cut shows depends on the client's width measurement,
    -- which is not relied on to decide whether the hover has the text.
    frame._lockedLabelHit = Nexus.LayoutMetrics and Nexus.LayoutMetrics.FullTextTooltip
        and Nexus.LayoutMetrics.FullTextTooltip(lockedLabel, frame) or nil
    frame._fitAutoLock = function(slots)
        local full = Nexus.Localization.Text("editor.label.autolock_full")
        local short = Nexus.Localization.Text("editor.label.autolock_short")
        local n = math.max(1, math.min(8, math.floor(tonumber(slots) or 6)))
        local right = (tonumber(frame:GetWidth()) or 1040) - 34 - 140 - 8
        -- The strip's left edge: after the class filter's caption, as that
        -- caption is anchored (search box, 12, check box, -2), never right of
        -- the former fixed x 540.
        local origin = 540
        local okC, cw = pcall(classCheck.text.GetStringWidth, classCheck.text)
        cw = okC and tonumber(cw) or nil
        local sw, bw = tonumber(searchBox:GetWidth()), tonumber(classCheck:GetWidth())
        if cw and sw and bw then
            origin = math.min(540, math.ceil(34 + sw + 12 + bw - 2 + cw + 12))
        end
        lockedLabel:ClearAllPoints()
        lockedLabel:SetPoint("TOPLEFT", origin, -130)
        local okL, lw = pcall(lockedLabel.GetStringWidth, lockedLabel)
        lw = okL and tonumber(lw) or 60
        local cap = math.floor(right - 22 - 6 - (22 * n - 4) - 8 - origin)
        local caption = lockedLabel:GetText() or ""
        lockedLabel._nexusFullText = caption ~= "" and caption or nil
        if lw > cap then
            lw = math.max(1, cap)
        else
            lw = math.ceil(lw)
        end
        -- The hover area is offered only while the caption itself is.
        local hit = frame._lockedLabelHit
        if hit then if lockedLabel:IsShown() then hit:Show() else hit:Hide() end end
        if type(lockedLabel.SetWordWrap) == "function" then pcall(lockedLabel.SetWordWrap, lockedLabel, false) end
        lockedLabel:SetJustifyH("LEFT")
        lockedLabel:SetWidth(lw)
        local slotsRight = origin + lw + 8 + (22 * n - 4)
        local gap = math.max(6, math.min(12, right - 22 - slotsRight))
        autoLockCheck:ClearAllPoints()
        autoLockCheck:SetPoint("LEFT", frame._nexusLockedSlot(n), "RIGHT", gap, 0)
        autoLockCheck._nexusAnchorSlot = n
        frame._autoLockClear = slotsRight + gap + 22 <= right
        local left = slotsRight + gap + 22 + 2
        local room = math.floor(right - left)
        if type(autoLockLabel.SetWordWrap) == "function" then pcall(autoLockLabel.SetWordWrap, autoLockLabel, false) end
        -- One line's height and each candidate line's width, measured on
        -- one unwrapped line at a time.
        autoLockLabel:SetSize(1000, 14)
        local function Measure(text)
            autoLockLabel:SetText(text)
            local ok, w = pcall(autoLockLabel.GetStringWidth, autoLockLabel)
            return ok and tonumber(w) or (#text * 6)
        end
        Measure("Auto-manage")
        local okH, lineHeight = pcall(autoLockLabel.GetStringHeight, autoLockLabel)
        lineHeight = math.max(1, okH and tonumber(lineHeight) or 14)
        local maxLines = math.max(1, math.min(3, math.floor(42 / lineHeight)))
        local function Wrap(text)
            local lines, current = {}, nil
            for word in text:gmatch("%S+") do
                local joined = current and (current .. " " .. word) or word
                if Measure(joined) <= room then
                    current = joined
                elseif current and Measure(word) <= room then
                    lines[#lines + 1] = current
                    current = word
                else
                    return nil
                end
            end
            lines[#lines + 1] = current
            if #lines > maxLines then return nil end
            return lines
        end
        local lines = room >= 24 and (Wrap(full) or Wrap(short)) or nil
        local drop = 0
        if not lines then
            -- No room beside the strip (the largest text sizes): the box and
            -- its caption take their own line under the strip, from the
            -- strip's left edge, and the lists and their titles move down
            -- by that line (frame._applyContentDrop). The caption still
            -- follows its box and ends 8 units left of My Builds.
            local top = 130 + math.max(22, lineHeight) + 4
            room = math.floor(right - (origin + 22 + 2))
            maxLines = 3
            lines = room >= 24 and (Wrap(full) or Wrap(short)) or nil
            local lineBox = math.max(22, lineHeight * (lines and #lines or 1))
            autoLockCheck:ClearAllPoints()
            autoLockCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", origin, -(top + math.floor((lineBox - 22) / 2)))
            frame._autoLockClear = origin + 22 <= right
            drop = math.max(0, top + lineBox + 4 - 154)
        end
        autoLockLabel:SetText(lines and table.concat(lines, "\n") or full)
        autoLockLabel:SetSize(math.max(1, room), lineHeight * (lines and #lines or 1))
        autoLockLabel._nexusFullText = full
        if lines then autoLockLabel:Show() else autoLockLabel:Hide() end
        if autoLockHit then if lines then autoLockHit:Show() else autoLockHit:Hide() end end
        frame._contentDrop = drop
        if frame._applyContentDrop then frame._applyContentDrop(drop) end
        return room
    end
    frame._fitAutoLock(6)

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header:SetPoint("TOPLEFT", 34, -158)
    header:SetText(Nexus.Localization.Text("editor.label.list_header"))

    -- Left: browsable catalog -----------------------------------------
    local leftArea = CreateFrame("Frame", nil, frame)
    leftArea:SetPoint("TOPLEFT", 34, -180)
    leftArea:SetSize(600, MAX_ROWS * ROW_HEIGHT)
    frame._leftArea = leftArea
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
            -- The status column (quality, Owned, Selected, Locked) is as wide
            -- as its text (M.FitCatalogStatus, up to 260 units); the row's
            -- tooltip still repeats it whole.
            local status = self.status and self.status:GetText()
            if status and status ~= "" and GameTooltip:IsShown() then
                GameTooltip:AddLine(status, 1, 1, 1, true)
                GameTooltip:Show()
            end
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
    pickTitle:SetText(Nexus.Localization.Text("editor.heading.selected"))

    local pickArea = CreateFrame("Frame", nil, frame)
    pickArea:SetPoint("TOPLEFT", 674, -180)
    pickArea:SetSize(332, PICK_ROWS * ROW_HEIGHT)
    frame._pickArea = pickArea
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
        -- The planned copies (x2) and locked-slot notes end the name's 224
        -- units on their own, so a long name cannot hide them
        -- (M.SetPickRowText, displayed item 4, #173).
        row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.count:SetPoint("RIGHT", row, "LEFT", 250, 0)
        row.count:SetSize(1, ROW_HEIGHT)
        row.count:SetJustifyH("RIGHT")

        row.minus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.minus:SetSize(22, 20); row.minus:SetPoint("RIGHT", -48, 0); row.minus:SetText("-")
        row.plus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.plus:SetSize(22, 20); row.plus:SetPoint("RIGHT", -24, 0); row.plus:SetText("+")
        row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        row.remove:SetSize(22, 22); row.remove:SetPoint("RIGHT", 0, 0)
        -- Legible controls, same click areas: - and + are 22x22 with the
        -- large template fonts for their glyphs; the remove X keeps its 22x22
        -- click area and draws its art at 28 units centred on it (the close
        -- art has a wide transparent margin). Each says what it does on
        -- hover; the draft changes only as before, and nothing is saved.
        for _, stepper in ipairs({row.minus, row.plus}) do
            stepper:SetHeight(22)
            pcall(stepper.SetNormalFontObject, stepper, "GameFontNormalLarge")
            pcall(stepper.SetHighlightFontObject, stepper, "GameFontHighlightLarge")
            pcall(stepper.SetDisabledFontObject, stepper, "GameFontDisableLarge")
        end
        for _, getter in ipairs({"GetNormalTexture", "GetPushedTexture",
            "GetHighlightTexture", "GetDisabledTexture"}) do
            local art = type(row.remove[getter]) == "function"
                and row.remove[getter](row.remove) or nil
            if art then
                art:ClearAllPoints()
                art:SetPoint("CENTER", row.remove, "CENTER", 0, 0)
                art:SetSize(28, 28)
            end
        end
        row.remove._nexusArtSize = 28
        for _, hint in ipairs({
            {row.minus, "editor.tooltip.step_minus_heading", "editor.tooltip.step_minus_body"},
            {row.plus, "editor.tooltip.step_plus_heading", "editor.tooltip.step_plus_body"},
            {row.remove, "editor.tooltip.step_remove_heading", "editor.tooltip.step_remove_body"},
        }) do
            hint[1]:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(Nexus.Localization.Text(hint[2]), 1, 0.82, 0.2)
                GameTooltip:AddLine(Nexus.Localization.Text(hint[3]) .. " "
                    .. Nexus.Localization.Text("editor.tooltip.step_nothing_saved"), 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end)
            hint[1]:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
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
    pickFooterText:SetSize(332, 28)
    pickFooterText:SetWordWrap(true)
    pickFooterText:SetJustifyH("LEFT")
    pickFooterText:SetJustifyV("TOP")
    -- The planned-copy counts stay readable when the two lines need more
    -- room (a longer locked count, larger text): hovering the footer shows
    -- its whole text. The box and the counts are unchanged.
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.FullTextTooltip then
        frame._pickFooterHit = Nexus.LayoutMetrics.FullTextTooltip(pickFooterText, frame)
    end

    -- Apply remains a presentation binding: the controller prepares and
    -- submits only after the established confirmation popup is accepted.
    applyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    applyBtn:SetSize(332, 26)
    applyBtn:SetPoint("BOTTOMLEFT", 674, 24)
    applyBtn:SetText((M.ApplyAction()))
    -- The click's own arguments are not an intent: the intent of the label
    -- shown (set with it by RefreshTimerStatus) is named, else the default.
    applyBtn:SetScript("OnClick", function() ApplyPending(frame and frame._applyIntent) end)
    applyBtn:SetScript("OnEnter", function(self)
        local editingContext = EditingContext()
        local blocked = Controller.ApplyBlockReason()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        -- M4 (UX-15): one word, Wishlist (it is kept on the server).
        local L = Nexus.Localization
        GameTooltip:AddLine(L.Text(editingContext and "editor.tooltip.apply_heading_save"
            or "editor.tooltip.apply_heading_create"), 1, 0.8, 0.3)
        GameTooltip:AddLine(blocked and (L.Format("editor.tooltip.apply_unavailable",
            {reason = SafeDisplay(Nexus.UserText.Recognized(blocked), 1024, false) or L.Text("editor.value.unknown_reason")}))
            or (editingContext and (L.Format("editor.tooltip.apply_edits_only",
                {name = SafeDisplay(editingContext.name, 1024, false) or L.Text("editor.value.wishlist_fallback")}))
            or L.Text("editor.tooltip.apply_uploads_new")), 0.8, 0.8, 0.8, true)
        for _, line in ipairs(M.ApplyIntentLines()) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
        GameTooltip:AddLine(L.Text("editor.tooltip.apply_confirmation"), 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    applyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    M.EnsureIntentControls(applyBtn, ApplyPending)
    M.EnsureSaveResultRow()

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
        frame._divider = divider
    end)

    -- The lists, their titles, Plan alternatives and the divider move down
    -- by `drop` units while the locked-slot caption has its own line
    -- (frame._fitAutoLock; 0 otherwise, the original places). Both lists
    -- are sized at refresh: the catalog to the whole rows above its former
    -- bottom edge, the Selected Echoes list to those above its footer.
    frame._applyContentDrop = function(drop)
        drop = math.max(0, math.floor(tonumber(drop) or 0))
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", 34, -158 - drop)
        pickTitle:ClearAllPoints()
        pickTitle:SetPoint("TOPLEFT", 674, -158 - drop)
        planBtn:ClearAllPoints()
        planBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, -154 - drop)
        leftArea:ClearAllPoints()
        leftArea:SetPoint("TOPLEFT", 34, -180 - drop)
        local pitch = frame._rowPitch or ROW_HEIGHT
        leftArea:SetHeight(math.max(1, math.min(MAX_ROWS, math.floor(
            (MAX_ROWS * ROW_HEIGHT - drop) / pitch))) * pitch)
        pickArea:ClearAllPoints()
        pickArea:SetPoint("TOPLEFT", 674, -180 - drop)
        if frame._divider then
            frame._divider:ClearAllPoints()
            frame._divider:SetPoint("TOPLEFT", 652, -180 - drop)
            frame._divider:SetHeight(MAX_ROWS * ROW_HEIGHT - drop)
        end
    end
    frame._applyContentDrop(frame._contentDrop or 0)

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
    -- Current locked ownership is OCCUPIED RECORDS: one slot per record,
    -- each holding its own locked stack. lockedCount counts records, never
    -- copies. The stated maximum is the live capacity when the game reports
    -- one; otherwise the six authored target cells, and none once more
    -- records than that are occupied.
    local lockedBySpell, lockedRecords, lockedCapacity = {}, {}, nil
    if View and View.LockedOwned then
        local locked = View.LockedOwned()
        if locked and locked.synced == true
            and type(locked.bySpell) == "table"
            and type(locked.records) == "table" then
            lockedBySpell = locked.bySpell
            lockedRecords = locked.records
            lockedCapacity = tonumber(locked.capacity)
        end
    end
    local lockedCount = #lockedRecords
    for _, count in pairs(lockedBySpell) do
        count = tonumber(count)
        if not count or count <= 0 or count >= math.huge
            or count ~= math.floor(count) then
            lockedBySpell, lockedRecords = {}, {}
            lockedCount = 0
            break
        end
    end
    local lockedMaximum = lockedCapacity
        or (lockedCount <= MAX_LOCK_SLOTS and MAX_LOCK_SLOTS or nil)

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
    -- switches are enabled, core/AutomationRuntime.lua (TryAutoLock) may
    -- reconcile them with LockPerk and UnlockPerk, within its checks. Each
    -- real-locked column gets its
    -- own STABLE position; a designed replacement for it (right-click, or
    -- auto-paired on import -- see LoadPendingEchoes) renders directly
    -- ABOVE that exact column in lockedNeedIcons, not beside it, so
    -- current-vs-needed reads as one stacked pair instead of two icons
    -- that happen to sit in the same row. A designed target that ISN'T
    -- replacing anything (bound for a genuinely open slot) fills the next
    -- open column in the bottom row instead.
    if lockedLabel and lockedIcons then
        -- One slot per occupied record (the records come ordered by spell).
        local realSlots = {}
        for _, record in ipairs(lockedRecords) do
            realSlots[#realSlots + 1] = record.spellId
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
                    name=(row and row.name) or M.DraftName(p)
                        or TF("editor.value.spell_id_fallback", {id = tostring(p.spellId)}),
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

        -- Always show at least the MAX_LOCK_SLOTS authored target cells, not
        -- just however many are currently locked -- an account with 5/6
        -- locked was rendering as "Locked (5):" with no visible hint a 6th
        -- slot even existed. More occupied records, or a higher live
        -- capacity, add slots; eight fit beside the AutoLock option.
        local slotCount = math.min(8, math.max(MAX_LOCK_SLOTS, #realSlots,
            lockedCapacity or 0))
        lockedLabel:SetText(lockedMaximum
            and TF("editor.label.locked_count_max", {count = N(lockedCount), max = N(lockedMaximum)})
            or TF("editor.label.locked_count", {count = N(lockedCount)}))
        lockedLabel:Show()
        for i = slotCount + 1, #lockedIcons do
            lockedIcons[i]:Hide()
            if lockedNeedIcons[i] then lockedNeedIcons[i]:Hide() end
        end
        if autoLockCheck and autoLockCheck._nexusAnchorSlot ~= slotCount then
            frame._nexusLockedSlot(slotCount)
            autoLockCheck:ClearAllPoints()
            autoLockCheck:SetPoint("LEFT", lockedIcons[slotCount], "RIGHT", 26, 0)
            autoLockCheck._nexusAnchorSlot = slotCount
        end
        -- The Locked (n/m) text and the slot count move the label's room.
        if frame._fitAutoLock then frame._fitAutoLock(slotCount) end
        local fi = 1
        for i = 1, slotCount do
            local btn, needBtn = lockedIcons[i], lockedNeedIcons[i]
            if not btn or not needBtn then
                btn, needBtn = frame._nexusLockedSlot(i)
            end
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
        trackingText:SetText("|cff4dff80" .. T("editor.status.tracking_label") .. "|r "
            .. TF("editor.status.tracking_detail", {
                name = DisplayUntrusted(wl.name, 1024, false) or T("editor.value.unnamed"),
                source = DisplayUntrusted(wl.source, 256, false) or T("editor.value.unknown_source"),
                count = N(EchoListTotal(wl.entries))}))
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
            trackingText:SetText("|cffff9040" .. TF("editor.status.candidates_found", {count = N(#candidates)})
                .. "|r -- " .. (awaiting > 0
                    and TF("editor.status.candidates_need_targets", {count = N(awaiting)})
                    or T("editor.status.candidates_click_assign")))
            for i, b in ipairs(candidateButtons) do
                local c = candidates[i]
                if c then
                    b:SetText(string.format("%s (%d)%s",
                        DisplayUntrusted(c.name, 1024, false)
                            or TF("editor.value.slot_fallback", {slot = tostring(c.slot)}),
                        c.count, CandidateEvidenceSuffix(c)))
                    b:SetScript("OnClick", function()
                        -- With Auto selected the Auto-ON confirmation comes
                        -- first (WishlistEditor.ConfirmCandidateAssignment).
                        Nexus.WishlistEditor.ConfirmCandidateAssignment(c, function()
                        if c.lockEvidenceStatus=="unavailable" and Nexus.WishlistEditor
                            and Nexus.WishlistEditor.ResolveAndAssignWishlist then
                            local slots=View.Slots()
                            Nexus.WishlistEditor.ResolveAndAssignWishlist(c,slots and slots.activeSlot or 0)
                            return
                        end
                        local ok, err, active, firstRun =
                            Controller.AssociateCandidate(c)
                        if ok then
                            M.PrintCandidateAssigned(c.name, firstRun, active)
                            requestRefresh()
                        else
                            print("|cffff6060Nexus:|r " .. tostring(err and Nexus.UserText.Recognized(err) or
                                T("editor.chat.candidate_activate_loadout")))
                        end
                        end)
                    end)
                    b:Show()
                else
                    b:Hide()
                end
            end
        elseif #candidates == 1 then
            -- Exactly one candidate but not yet flagged active by the
            -- server. Identity-only content stays visible without implying
            -- that it is safe to assign before its target roles are confirmed.
            trackingText:SetText(candidates[1].lockEvidenceStatus == "unavailable"
                and ("|cffff9040" .. T("editor.status.found_identity") .. "|r -- "
                    .. T("editor.status.found_identity_choose"))
                or ("|cffff9040" .. T("editor.status.found_wishlist") .. "|r -- "
                    .. T("editor.status.found_wishlist_assign")))
            candidateButtons[1]:SetText((DisplayUntrusted(
                candidates[1].name, 1024, false)
                or TF("editor.value.slot_fallback", {slot = tostring(candidates[1].slot)}))
                .. CandidateEvidenceSuffix(candidates[1]))
            candidateButtons[1]:SetScript("OnClick", function()
                -- With Auto selected the Auto-ON confirmation comes first
                -- (WishlistEditor.ConfirmCandidateAssignment).
                Nexus.WishlistEditor.ConfirmCandidateAssignment(candidates[1], function()
                if candidates[1].lockEvidenceStatus=="unavailable" and Nexus.WishlistEditor
                    and Nexus.WishlistEditor.ResolveAndAssignWishlist then
                    local slots=View.Slots()
                    Nexus.WishlistEditor.ResolveAndAssignWishlist(candidates[1],slots and slots.activeSlot or 0)
                    return
                end
                local ok, err, active, firstRun =
                    Controller.AssociateCandidate(candidates[1])
                if ok then
                    M.PrintCandidateAssigned(candidates[1].name, firstRun, active)
                    requestRefresh()
                else
                    print("|cffff6060Nexus:|r " .. tostring(err and Nexus.UserText.Recognized(err) or
                        T("editor.chat.candidate_activate_loadout")))
                end
                end)
            end)
            candidateButtons[1]:Show()
            for i = 2, #candidateButtons do candidateButtons[i]:Hide() end
        else
            trackingText:SetText("|cff888888" .. T("editor.status.no_wishlist_yet") .. "|r -- "
                .. T("editor.status.no_wishlist_build_one"))
            for _, b in ipairs(candidateButtons) do b:Hide() end
        end
    end

    -- The context line under the title is the destination row (its first
    -- cell is editContextText); M.Refresh words it from the controller's
    -- captured descriptor. Only the title is set here.
    if titleText then
        titleText:SetText(T(editingContext and "editor.title.edit"
            or "editor.title.create"))
    end

    -- The destination row's view observation: this refresh's one existing
    -- Slots read below and the result of its one existing SelectedSavedBuild
    -- before the editing/create overrides (nil as 0; nil itself, i.e.
    -- unobserved, without a Slots table whose active slot is known). It is
    -- cleared first, then held only when the Panel's public revision is a
    -- finite nonnegative whole number equal to its private count
    -- (DestinationSessionCount()), with the new held stamp bound to that
    -- count; else none (nil, never an earlier stale read or another
    -- session's), as with a missing accessor or a rolled-back revision.
    if frame._destinationRow then
        frame._destinationRow._nexusEditorSlots = nil
        frame._destinationRow._nexusEditorSelected = nil
        frame._destinationRow._nexusEditorSession = nil
    end
    if loadoutSwitchBtn and not pendingLoadoutOpen then
        local slots = View and View.Slots and View.Slots()
        local active = slots and tonumber(slots.activeSlot)
        -- The Saved Build of the Wishlist being edited, else the one a new
        -- Wishlist is created for; the selected one only with neither (never a
        -- native Wishlist index; `active` stays the native fact for the
        -- "(active)" state below). An edited Wishlist that no Saved Build has
        -- selects none.
        local selected = View.SelectedSavedBuild(slots)
        -- Held as the observed current role only: never captured draft,
        -- target or Save authority.
        if frame._destinationRow then
            local destinationRow, panel = frame._destinationRow, Nexus.Panel
            local session = panel.destinationSessionRevision
            if type(session) == "number" and session >= 0
                and session < math.huge and session == math.floor(session)
                and type(panel.DestinationSessionCount) == "function"
                and panel.DestinationSessionCount() == session then
                destinationRow._nexusEditorSlots = slots
                destinationRow._nexusEditorSelected =
                    (type(slots) == "table" and slots.activeKnown ~= false)
                    and (selected or 0) or nil
                destinationRow._nexusEditorSession = session
            end
        end
        if editingContext then
            selected = tonumber(editingContext.loadoutSlot)
        elseif createTargetContext then
            selected = tonumber(createTargetContext.loadoutSlot)
        end
        local selectedRow = selected and slots and slots.bySlot and slots.bySlot[selected]
        local selectedName = selectedRow
            and (DisplayUntrusted(selectedRow.name, 1024, false) or "") or ""
        -- The selector picks whose assigned Wishlist is edited and activates
        -- nothing, so the label names that Saved Build and says whether it is
        -- the server's active one.
        if selected and selected > 0 then
            if selectedName == "" then
                selectedName = TF("editor.value.saved_build_number", {slot = tostring(selected)})
            end
            local stateKey = "editor.button.saved_build_named"
            if active and active > 0 then
                stateKey = active == selected and "editor.button.saved_build_active"
                    or "editor.button.saved_build_inactive"
            end
            loadoutSwitchBtn:SetText(TF(stateKey, {name = selectedName}))
        elseif editingContext then
            -- As the context line and the switch list say: none.
            loadoutSwitchBtn:SetText(T("editor.button.saved_build_none"))
        else
            loadoutSwitchBtn:SetText(T("editor.button.saved_build_choose"))
        end
    end

    if wishlistSwitchBtn then
        if editingContext then
            wishlistSwitchBtn:SetText(TF("editor.button.editing",
                {name = DisplayUntrusted(editingContext.name, 1024, false) or T("editor.value.wishlist_fallback")}))
        else
            wishlistSwitchBtn:SetText(T("editor.button.new_wishlist_choose"))
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
    -- Fewer whole rows while the lists sit lower (frame._applyContentDrop).
    -- Row pitch: at least ROW_HEIGHT, else one measured text line and 2
    -- units, so a larger text size never runs a row into its neighbour.
    local rowPitch = M.RowPitch(rows, pickRows)
    frame._rowPitch = rowPitch
    M.ApplyRowPitch(rows, rowPitch)
    M.ApplyRowPitch(pickRows, rowPitch)
    local catalogVisible = math.max(1, math.min(MAX_ROWS, math.floor(
        (MAX_ROWS * ROW_HEIGHT - (frame._contentDrop or 0)) / rowPitch)))
    if frame._leftArea then frame._leftArea:SetHeight(catalogVisible * rowPitch) end
    scrollOffset = Controller.ClampScroll(#available, catalogVisible)
    for i, row in ipairs(rows) do
        local data = i <= catalogVisible and available[scrollOffset + i] or nil
        row.data = data
        if data then
            row:Show()
            row.icon:SetTexture(SpellIcon(data.spellId))
            local c = QUALITY_COLORS[data.quality] or QUALITY_COLORS[0]
            row.text:SetTextColor(c[1], c[2], c[3])
            local chosen = pending[DraftKey(data.spellId, catalog)]
            local suffix = ""
            if chosen and tonumber(chosen.spellId) == tonumber(data.spellId) then
                suffix = "  |cff4dff80" .. T("editor.value.catalog_selected_marker") .. "|r"
            end
            row.text:SetText(data.name .. suffix)
            local exactProgress = EntryProgress and EntryProgress({{
                spellId=data.spellId,quality=data.quality,stacks=1,locked=false,
            }}, owned, nil) or nil
            local ownedCount = exactProgress and exactProgress.rows
                and exactProgress.rows[1] and exactProgress.rows[1].have
                or ownedBySpell[data.spellId] or 0
            local isLocked = (tonumber(lockedBySpell[data.spellId]) or 0) > 0
            local qualityName = QualityName(tonumber(data.quality) or 0) or T("editor.value.quality_fallback")
            if isLocked then
                -- Permanently secured -- never needs a wishlist slot again.
                -- Distinct from RollStatus's unrelated "locked" (tome-gated).
                row.status:SetText("|cffb266ff" .. T("editor.value.catalog_locked") .. "|r")
            elseif chosen and tonumber(chosen.spellId) == tonumber(data.spellId) then
                row.status:SetText("|cff4dff80" .. T("editor.value.catalog_selected") .. "|r")
            elseif ownedCount > 0 then
                row.status:SetText("|cffffd200" .. TF("editor.value.catalog_quality_owned",
                    {quality = qualityName}) .. "|r")
            else
                row.status:SetText("|cffb8b8b8" .. qualityName .. "|r")
            end
            M.FitCatalogStatus(row)
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
    footerText:SetText(TF("editor.label.catalog_footer_range", {
        first = N(math.min(scrollOffset + 1, #available)),
        last = N(math.min(#available, scrollOffset + catalogVisible)), total = N(#available)})
        .. "  \226\128\162  " .. TF("editor.label.catalog_footer_names", {count = N(uniqueAvailable)}))

    local list = {}
    local designedCount = 0
    for rowKey, p in pairs(pending) do
        local row = catalog and catalog.rows and catalog.rows[p.spellId]
        list[#list + 1] = { spellId = p.spellId, family = p.family, stacks = p.stacks,
            draftKey = rowKey,
            maxStack = p.maxStack, quality = p.quality, lockIntent = p.lockIntent,
            name = (row and row.name) or TF("editor.value.spell_id_fallback", {id = tostring(p.spellId)}),
            replaces = p.replaces }
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
            stacks = copies, maxStack = copies, quality = p.quality, name = M.DraftName(p), toLock = true,
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
    -- just an easy-to-miss "(current locked Echo slot)"/"(awaiting lock)" tag, with
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
                    name = (oldRow and oldRow.name)
                        or TF("editor.value.spell_id_fallback", {id = tostring(e.replaces)}),
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
    -- M4 (UX-13): the editor counts a plan, so its rolled copies are planned.
    -- Displayed item 4 (#173): that total is what a player checks before
    -- saving, so it leads the first line (M.PackFooterText).
    local footerParts = { TF("editor.label.pick_planned", {count = N(PendingTotal())}) }
    if lockedCount > 0 then
        footerParts[#footerParts + 1] = lockedMaximum
            and TF("editor.label.pick_locked_max", {count = N(lockedCount), max = N(lockedMaximum)})
            or TF("editor.label.pick_locked", {count = N(lockedCount)})
    end
    local totalDesigned = designedCount + toLockCount
    local targetParts = { TF("editor.label.pick_targets", {count = N(totalDesigned)}) }
    -- realEntryCount, not #list -- the spliced-in "replaces" ghost rows are
    -- a display aid, not separate wishlist entries, and shouldn't inflate
    -- this count.
    targetParts[#targetParts + 1] = TF("editor.label.pick_entries", {count = N(realEntryCount)})
    -- The footer is packed first: when its counts need more lines than its
    -- 28 units, it grows upward and the list above shows fewer whole rows
    -- (at least 8 units above the footer; exactly 8 at 28), so no count is
    -- under a row.
    local footerHeight = M.PackFooterText(pickFooterText, footerParts, targetParts)
    local pickVisible = math.max(1, math.min(PICK_ROWS, math.floor((
        PICK_ROWS * ROW_HEIGHT + 28 - footerHeight - (frame._contentDrop or 0)) / rowPitch)))
    if frame._pickArea then frame._pickArea:SetHeight(pickVisible * rowPitch) end
    pickOffset = Controller.ClampPick(#list, pickVisible)
    for i, row in ipairs(pickRows) do
        local data = i <= pickVisible and list[pickOffset + i] or nil
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
            M.SetPickRowText(row, "    |cff8a8a8a-> " .. T("editor.value.pick_replaces") .. "|r " .. data.name,
                "|cff8a8a8a" .. T("editor.value.pick_currently_locked") .. "|r", true)
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
                M.SetPickRowText(row, "|cffff9040" .. data.name .. "|r",
                    "|cffff9040" .. T("editor.value.pick_locked_slot") .. "|r")
            elseif data.lockIntent then
                -- Same separate locked-slot intent, represented on a pending
                -- row for compatibility with an in-progress editor session.
                -- It is excluded from the 79-copy upload and automated by its
                -- committed exact spellId.
                M.SetPickRowText(row, data.name, "|cffffd200x" .. tostring(data.stacks or 1)
                    .. "|r  |cff40c0ff" .. T("editor.value.pick_locked_slot") .. "|r")
            else
                M.SetPickRowText(row, data.name, "|cffffd200x" .. tostring(data.stacks or 1) .. "|r")
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
        -- The label names the action and the click carries that same intent
        -- (M.ApplyAction), so the button never does other than it says.
        local label, intent = M.ApplyAction()
        if frame then frame._applyIntent = intent end
        applyBtn:SetText(saving and T("editor.button.saving") or label)
        if saving or blocked then applyBtn:Disable() else applyBtn:Enable() end
        M.RenderIntentControls(applyBtn, saving, blocked)
        -- Every refresh, warm or not: the result row survives it unchanged.
        M.RenderSaveResult()
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
            -- Whether this draft offers the Save changes alternative, read
            -- only when the draft, slots or active Saved Build changed (all in
            -- the refresh key), never on the warm path.
            M.UpdateIntentChoice()
            known,controllerRevision,slots,active,granted,owned,wishlist,
                catalog,locked,lockedProjection,discovery,lever,firstRun =
                Controller.RefreshState()
            StoreRefreshKey(known,controllerRevision,slots,active,granted,
                owned,wishlist,catalog,locked,lockedProjection,discovery,
                lever,firstRun)
        end
        RefreshTimerStatus()
        RefreshTheme()
        -- Row-only update, warm or cold, after the one-time theme pass so it
        -- measures final fonts. Pure: the captured descriptor from the held
        -- Slots and selected-role observation (nil when none) and the
        -- session's cached character; a settled update is a no-op in the
        -- helper. The held observation counts only in the world session it
        -- was made in: it is kept only while the public revision is a finite
        -- nonnegative whole number, DestinationSessionCount() returns that
        -- value and the held stamp equals both, with a held Slots table.
        -- Otherwise it is dropped, as for a missing accessor, a changed,
        -- missing or malformed revision, or a rolled-back one once the count
        -- has advanced, even when it equals the old stamp. Restoring the
        -- revision never reacquires it; it stays unknown until the next
        -- natural cold observation. Apart from the pure
        -- DestinationSessionCount() call, no read or refresh is forced, and no
        -- extra backend or character read, event, timer, getter work or
        -- action is added for it here.
        local destinationRow = frame and frame._destinationRow
        if destinationRow then
            local panel = Nexus.Panel
            local session = panel.destinationSessionRevision
            if not (type(session) == "number" and session >= 0
                and session < math.huge and session == math.floor(session)
                and type(panel.DestinationSessionCount) == "function"
                and panel.DestinationSessionCount() == session
                and destinationRow._nexusEditorSession == session
                and type(destinationRow._nexusEditorSlots) == "table") then
                destinationRow._nexusEditorSlots = nil
                destinationRow._nexusEditorSelected = nil
                destinationRow._nexusEditorSession = nil
            end
            panel.UpdateDestinationRow(destinationRow,
                Controller.DestinationPresentation(
                    destinationRow._nexusEditorSlots,
                    panel.CachedDestinationCharacter(),
                    destinationRow._nexusEditorSelected),
                972, 18)
        end
        return result
    end

    -- A catalog row's status column (quality, Owned, Selected, Locked) is as
    -- wide as its text, at least the former 110 units and at most 260, so
    -- "Uncommon · Owned" is not cut at a larger text size (displayed item 4,
    -- #173). The name keeps the rest of the row up to its former 420 units;
    -- it is never under the status. The row's tooltip still repeats both.
    function M.FitCatalogStatus(row)
        local ok, w = pcall(row.status.GetStringWidth, row.status)
        w = ok and tonumber(w) or 110
        local statusWidth = math.max(110, math.min(260, math.ceil(w) + 2))
        row.status:SetWidth(statusWidth)
        -- 28 units of icon and gap before the name, 12 after the status, 8
        -- between them.
        local rowWidth = tonumber(row:GetWidth()) or 600
        row.text:SetWidth(math.max(1, math.min(420, rowWidth - 28 - 8 - statusWidth - 12)))
    end

    -- One text line's measured height in the list fonts (the catalog status
    -- and a Selected row's copies), and the row pitch that leaves 2 units
    -- between lines: ROW_HEIGHT (24) at the default sizes, more only when a
    -- larger text size needs it (displayed item 4, #173).
    function M.RowPitch(catalogRows, selectedRows)
        local tallest = 0
        for _, fs in ipairs({ catalogRows[1] and catalogRows[1].status,
            catalogRows[1] and catalogRows[1].text,
            selectedRows[1] and selectedRows[1].count }) do
            local text, width = fs:GetText(), fs:GetWidth()
            fs:SetWidth(1000)
            fs:SetText("Xg")
            local ok, h = pcall(fs.GetStringHeight, fs)
            fs:SetText(text)
            fs:SetWidth(width)
            tallest = math.max(tallest, ok and tonumber(h) or 0)
        end
        return math.max(ROW_HEIGHT, math.ceil(tallest) + 2)
    end

    -- Rows placed `pitch` apart, each `pitch` high, with its name (and the
    -- catalog status) as high as the row; buttons keep their sizes, centred.
    function M.ApplyRowPitch(list, pitch)
        for i, row in ipairs(list) do
            if row._nexusPitch ~= pitch then
                row._nexusPitch = pitch
                row:SetHeight(pitch)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -((i - 1) * pitch))
                row.text:SetHeight(pitch)
                if row.status then row.status:SetHeight(pitch) end
            end
        end
    end

    -- A Selected Echoes row: the name, then its copies or locked-slot note
    -- right-aligned on one line. On a normal row the note ends the name's
    -- 224 units, left of the - / + / remove controls; on the read-only
    -- pairing row (`controlsHidden`, which has none of them) it ends 4 units
    -- inside the row, so "(currently locked)" fits whole at larger text. The
    -- note is as wide as its text and at least one line high; the name keeps
    -- the rest (the client shortens a long one, whose whole name is on the
    -- row's Echo tooltip).
    function M.SetPickRowText(row, name, note, controlsHidden)
        local count = row.count
        if not count then
            row.text:SetText(name .. "  " .. note)
            return
        end
        local textRight = controlsHidden and ((tonumber(row:GetWidth()) or 332) - 4) or 250
        count:ClearAllPoints()
        count:SetPoint("RIGHT", row, "LEFT", textRight, 0)
        if type(count.SetWordWrap) == "function" then pcall(count.SetWordWrap, count, false) end
        count:SetText(note)
        local ok, w = pcall(count.GetStringWidth, count)
        local room = textRight - 26 - 24 - 6
        w = math.min(room, math.ceil(ok and tonumber(w) or 40))
        count:SetWidth(math.max(1, w + 2))
        local okH, h = pcall(count.GetStringHeight, count)
        count:SetHeight(math.max(1, math.ceil(okH and tonumber(h) or 14)))
        row.text:SetWidth(math.max(24, textRight - 26 - (w + 2) - 6))
        row.text:SetText(name)
    end

    -- The Selected Echoes footer (displayed item 4, #173). The counts are
    -- unchanged. The parts are packed into lines that fit the 332-unit
    -- width, measured one line at a time: the first part of `first` (the
    -- planned rolled copies total) always leads line 1, the rest of `first`
    -- joins it while it fits, else starts the next lines with `rest`. The box
    -- (bottom-anchored above Save) is at least its former 28 units and as
    -- high as all its lines, so every count is shown; the caller gives the
    -- list above the remaining room, and the existing hover still repeats
    -- the text if the client measures it taller. Returns the box height.
    function M.PackFooterText(fontString, first, rest)
        local sep = "  •  "
        local width = tonumber(fontString:GetWidth()) or 332
        local function Fits(text)
            fontString:SetText(text)
            local ok, w = pcall(fontString.GetStringWidth, fontString)
            w = ok and tonumber(w) or nil
            return w ~= nil and w <= width
        end
        local lines, line, carry = {}, first[1], {}
        for i = 2, #first do
            if Fits(line .. sep .. first[i]) then
                line = line .. sep .. first[i]
            else
                carry[#carry + 1] = first[i]
            end
        end
        lines[1] = line
        for _, part in ipairs(rest) do carry[#carry + 1] = part end
        line = nil
        for _, part in ipairs(carry) do
            if line and Fits(line .. sep .. part) then
                line = line .. sep .. part
            else
                if line then lines[#lines + 1] = line end
                line = part
            end
        end
        if line then lines[#lines + 1] = line end
        fontString:SetText(lines[1])
        local ok, lineHeight = pcall(fontString.GetStringHeight, fontString)
        lineHeight = math.max(1, ok and tonumber(lineHeight) or 14)
        fontString._nexusFullText = nil
        fontString:SetText(table.concat(lines, "\n"))
        -- The whole text's own measured height, or one measured line each,
        -- whichever is more.
        fontString:SetHeight(0)
        local okAll, measured = pcall(fontString.GetStringHeight, fontString)
        measured = okAll and tonumber(measured) or 0
        local height = math.ceil(math.max(28, measured, lineHeight * #lines))
        fontString:SetHeight(height)
        return height
    end

    -- The chat line after a candidate button assigned its Wishlist.
    function M.PrintCandidateAssigned(name, firstRun, active)
        local shown = DisplayUntrusted(name, 1024, false) or T("editor.value.wishlist_fallback")
        if firstRun then
            print("|cff4dff80Nexus:|r " .. TF("editor.chat.candidate_first_run", {name = shown}))
        else
            print("|cff4dff80Nexus:|r " .. TF("editor.chat.candidate_assigned",
                {name = shown, slot = tostring(active)}))
        end
    end

    function M.SetApplySaved()
        if applyBtn then applyBtn:SetText(T("editor.button.saved")) end
    end

    ------------------------------------------------------------------------
    -- Save result row and named confirmations (UX-03, UX-04). Presentation
    -- only: the controller's SaveResult says what the last save actually
    -- did; nothing here uploads, assigns, activates or changes Auto. The
    -- functions live on M (Renderer.New and EnsureFrame are near the Lua 5.1
    -- local/upvalue limits).
    ------------------------------------------------------------------------

    -- The destination a descriptor names, for display: a Saved Build by its
    -- captured name with the slot as second identity, or the first-run
    -- target of the character. Nil when there is no destination.
    function M.DestinationLabel(destination)
        if type(destination) ~= "table" then return nil end
        if destination.kind == "savedBuild" then
            local slot = tonumber(destination.slot)
            -- The controller stores this English default as a captured
            -- name; it is compared raw and only the shown fallback is
            -- localized.
            local raw = "Saved Build " .. tostring(slot or "?")
            local fallback = TF("editor.value.saved_build_number", {slot = tostring(slot or "?")})
            local name = DisplayUntrusted(destination.name, 1024, false)
            if not name or name == raw then return fallback end
            return TF("editor.value.saved_build_named_slot", {name = name, slot = tostring(slot)})
        elseif destination.kind == "firstRun" then
            return TF("editor.value.first_run_target_for", {character =
                DisplayUntrusted(destination.character, 1024, false) or T("editor.value.this_character")})
        end
        return nil
    end

    -- Auto's current state, read only for wording.
    function M.AutoIsOn()
        if type(Nexus.RecomputeStats) ~= "function" then return false end
        local ok, stats = pcall(Nexus.RecomputeStats)
        return ok and type(stats) == "table" and stats.autoEnabled == true
    end

    -- Why a selected Auto is not acting, in plain words, from memory only:
    -- the HUD's last committed model, else the runtime's passive effective
    -- state. Calls no gate and reads nothing from the game. Nil when Auto
    -- was not held at its last update.
    function M.AutoHeldReason()
        local reason
        local panel = Nexus.Panel
        local model = panel and type(panel._lastModel) == "table" and panel._lastModel or nil
        if model and model.auto and type(model.paused) == "string" and model.paused ~= "" then
            reason = model.paused
        end
        if not reason and type(Nexus.AutomationEffectiveState) == "function" then
            local ok, effective = pcall(Nexus.AutomationEffectiveState)
            if ok and type(effective) == "table" and effective.selected and effective.hold
                and type(effective.reason) == "string" then
                reason = effective.reason
            end
        end
        if not reason then return nil end
        local readout = Nexus.Readout
        local plain = readout and type(readout.AutoHoldText) == "function"
            and readout.AutoHoldText(reason) or tostring(reason)
        return DisplayUntrusted(plain, 600, false) or tostring(plain)
    end

    -- The Auto line of a confirmation that writes a Saved Build destination,
    -- from the existing permissions (no new consequence): with Auto OFF none;
    -- with its finished-run save permission (autoSave) off, that Auto does not
    -- replace the Saved Build; otherwise the conditional replacement, and,
    -- when Auto was held at its last update, why it was not acting then.
    function M.AutoConsentLine(label)
        if not M.AutoIsOn() then return nil end
        local store = Nexus.Store
        local okSettings, settings = false, nil
        if store and type(store.Settings) == "function" then okSettings, settings = pcall(store.Settings) end
        if okSettings and type(settings) == "table" and not settings.autoSave then
            return TF("editor.popup.auto_save_off", {label = label})
        end
        local held = M.AutoHeldReason()
        return (held and TF("editor.popup.auto_replace_paused", {reason = held, label = label})
            or TF("editor.popup.auto_replace", {label = label}))
            .. " " .. T("editor.popup.auto_turn_off")
    end

    -- What the apply button does for this draft (its tooltip): the captured
    -- destination it assigns, the alternative, or that this draft was sent.
    function M.ApplyIntentLines()
        local lines = {}
        local sent, uncertain
        if Controller.SentDraft then sent, uncertain = Controller.SentDraft() end
        if sent then
            lines[#lines + 1] = TF(uncertain and "editor.tooltip.intent_possibly_sent"
                or "editor.tooltip.intent_sent", {name = DisplayUntrusted(sent, 1024, false) or "?"})
                .. " " .. T("editor.tooltip.intent_create_another")
            return lines
        end
        if Controller.IsEditing() then
            -- An opened Wishlist: the Saved Build it was opened for, if any.
            local destination = Controller.SaveDestinationDescriptor and Controller.SaveDestinationDescriptor() or nil
            local where = destination and destination.kind == "savedBuild" and M.DestinationLabel(destination) or nil
            if where and Controller.SaveAssignsOpened and Controller.SaveAssignsOpened() then
                lines[#lines + 1] = TF("editor.tooltip.intent_save_assign_opened", {where = where})
                    .. " " .. T("editor.tooltip.intent_save_changes_beside")
            elseif where then
                lines[#lines + 1] = TF("editor.tooltip.intent_save_changes_keeps", {where = where})
            end
            return lines
        end
        local target = Controller.SaveAndAssignTarget and Controller.SaveAndAssignTarget() or nil
        local label = target and M.DestinationLabel(target) or nil
        if label then
            lines[#lines + 1] = TF("editor.tooltip.intent_create_assign", {label = label})
            lines[#lines + 1] = T("editor.tooltip.intent_create_unassigned")
        end
        return lines
    end

    -- "Create unassigned": the Save changes intent of a new plan that could be
    -- assigned. It shares the apply row (the apply button narrows) and is
    -- shown only while that choice exists. Kept on the frame (Renderer.New is
    -- near the Lua 5.1 local limit).
    function M.EnsureIntentControls(apply, applyIntent)
        if not frame or frame._saveOnlyBtn then return end
        local button = CreateFrame("Button", "NexusWishlistSaveOnlyButton", frame, "UIPanelButtonTemplate")
        button:SetSize(140, 26)
        button:SetPoint("BOTTOMLEFT", 866, 24)
        button:SetText(T("editor.button.create_unassigned"))
        button:SetScript("OnClick", function()
            applyIntent(Controller.INTENT and Controller.INTENT.SAVE_CHANGES or "saveChanges")
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if Controller.IsEditing() then
                -- An opened Wishlist whose Saved Build does not hold it.
                local destination = Controller.SaveDestinationDescriptor and Controller.SaveDestinationDescriptor()
                local where = destination and M.DestinationLabel(destination)
                    or T("editor.value.opened_saved_build_fallback")
                GameTooltip:AddLine(T("editor.tooltip.save_changes_heading"), 1, 0.8, 0.3)
                GameTooltip:AddLine(TF("editor.tooltip.save_changes_body", {where = where}), 0.8, 0.8, 0.8, true)
                GameTooltip:AddLine(TF("editor.tooltip.save_assign_them", {where = where}) .. " "
                    .. T("editor.tooltip.confirmation_first"), 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
                return
            end
            local target = Controller.SaveAndAssignTarget and Controller.SaveAndAssignTarget() or nil
            local label = target and M.DestinationLabel(target) or T("editor.value.captured_destination_fallback")
            GameTooltip:AddLine(T("editor.tooltip.create_unassigned_heading"), 1, 0.8, 0.3)
            GameTooltip:AddLine(TF("editor.tooltip.create_unassigned_body", {label = label}), 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(T("editor.tooltip.assign_later") .. " "
                .. T("editor.tooltip.confirmation_first"), 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button:Hide()
        frame._saveOnlyBtn = button
    end

    -- Read on the cold refresh path only (M.Refresh): a new plan with a
    -- captured, assignable destination offers the Save changes alternative.
    -- Whether the draft has the two actions (an assigning one and a Save
    -- changes beside it): a new plan with a captured destination, or a
    -- Wishlist opened for a Saved Build that does not hold it.
    function M.UpdateIntentChoice()
        if not frame then return end
        if Controller.IsEditing() then
            frame._saveChoice = Controller.SaveAssignsOpened ~= nil and Controller.SaveAssignsOpened() == true
        else
            frame._saveChoice = Controller.SaveAndAssignTarget ~= nil and Controller.SaveAndAssignTarget() ~= nil
        end
    end

    -- The primary action, as a label and the intent its click carries. A new
    -- plan with a captured destination is created and assigned there; any
    -- other new plan is created unassigned. An opened Wishlist saves its
    -- changes and keeps the assignment it has; one opened for a Saved Build
    -- that does not hold it is saved and assigned there. Where both exist the
    -- Save changes alternative stands beside it (M.SecondaryAction). Reads the
    -- cold-path choice only (UpdateIntentChoice).
    function M.ApplyAction()
        local intent = Controller.INTENT or {}
        local choice = frame and frame._saveChoice == true
        -- Help quotes these four action labels; they are reviewed keys bound
        -- here with their exact English. The click carries the intent, not
        -- the label.
        if Controller.IsEditing() then
            if choice then return T("editor.button.save_and_assign"), intent.SAVE_AND_ASSIGN or "saveAndAssign" end
            return T("editor.button.save_changes"), intent.SAVE_CHANGES or "saveChanges"
        end
        if choice then
            return T("editor.button.create_and_assign"), intent.SAVE_AND_ASSIGN or "saveAndAssign"
        end
        return T("editor.button.create_unassigned"), intent.SAVE_CHANGES or "saveChanges"
    end

    -- The Save changes alternative shown beside an assigning action.
    function M.SecondaryAction()
        return Controller.IsEditing() and T("editor.button.save_changes") or T("editor.button.create_unassigned")
    end

    -- The accept button of a confirmation names the same action as the
    -- control that opened it.
    function M.ConfirmLabel(data, mode)
        local assigns = type(data) == "table" and data.intent == "saveAndAssign"
        if mode == "update" then
            return assigns and T("editor.button.save_and_assign") or T("editor.button.save_changes")
        end
        return assigns and T("editor.button.create_and_assign") or T("editor.button.create_unassigned")
    end

    function M.RenderIntentControls(apply, saving, blocked)
        -- The window's one primary action (design: filled primary Save); a
        -- disabled one is drawn as any disabled button (Theme.SetPrimary).
        -- Presentation only: the action and its confirmation are unchanged.
        local theme = Nexus.Theme
        if apply and theme and type(theme.SetPrimary) == "function" then theme.SetPrimary(apply, true) end
        local button = frame and frame._saveOnlyBtn
        if not (apply and button) then return end
        local choice = not saving and frame._saveChoice == true
        if choice then
            apply:SetWidth(188)
            button:SetText(M.SecondaryAction())
            button:Show()
            if blocked then button:Disable() else button:Enable() end
        else
            apply:SetWidth(332)
            button:Hide()
        end
    end

    -- The second line of the Save/Create confirmation: the planned count,
    -- the destination this editor captured (never the Saved Build active
    -- now) and, for a Saved Build destination with Auto ON, its conditional
    -- consequence. An unbound Save names no Saved Build and promises nothing
    -- about one.
    function M.ConfirmationText(data, mode)
        local destination = type(data) == "table" and data.destination or nil
        local kind = type(destination) == "table" and destination.kind or "unknown"
        local label = M.DestinationLabel(destination)
        local parts = {TF("editor.popup.confirm_planned",
            {count = N(EchoListTotal(type(data) == "table" and data.echoes or {}))})}
        -- Save changes of a new plan that could have been assigned: named as
        -- saved without an assignment (the captured destination is untouched).
        local saveOnly = mode ~= "update" and type(data) == "table" and data.intent == "saveChanges"
            and (kind == "savedBuild" or kind == "firstRun")
        if mode == "update" then
            parts[#parts + 1] = T("editor.popup.confirm_updates")
            if kind == "savedBuild" and type(data) == "table" and data.keepsAssignment then
                -- Save changes of a Wishlist opened for a Saved Build that
                -- does not hold it: nothing is written for that Saved Build.
                parts[#parts + 1] = TF("editor.popup.confirm_keeps", {label = label})
            elseif kind == "savedBuild" then
                parts[#parts + 1] = TF("editor.popup.confirm_updates_assignment", {label = label})
                    .. " " .. T("editor.popup.confirm_nothing_activated")
            elseif kind == "firstRun" then
                parts[#parts + 1] = TF("editor.popup.confirm_updates_first_run", {label = label})
            else
                -- Scoped to this editor and this save: no claim about what
                -- other Saved Builds use, and no promise about assignments.
                parts[#parts + 1] = T("editor.popup.confirm_no_destination_update")
            end
        else
            -- The name this Create will really use (the title names it too):
            -- a copy name when the typed one is taken, or that existing names
            -- could not be checked yet. Existing Wishlists are never renamed.
            local requested = type(data) == "table" and data.requestedName or nil
            if requested ~= nil and requested ~= data.name then
                -- "Exists" here means listed where the player can see it.
                parts[#parts + 1] = TF("editor.popup.confirm_name_taken", {
                    requested = DisplayUntrusted(requested, 1024, false) or "?",
                    name = DisplayUntrusted(data.name, 1024, false) or "?"})
                    .. " " .. T("editor.popup.confirm_existing_keep_names")
            end
            -- Also beside a copy name: that name was chosen without the
            -- server's list, so it could not be checked against it either.
            if type(data) == "table" and data.namesUnknown then
                parts[#parts + 1] = T("editor.popup.confirm_names_unknown")
            end
            if saveOnly then
                parts[#parts + 1] = (kind == "savedBuild"
                    and TF("editor.popup.confirm_save_only_saved_build", {label = label})
                    or T("editor.popup.confirm_save_only_first_run"))
                    .. " " .. T("editor.popup.assign_later")
            elseif kind == "savedBuild" then
                parts[#parts + 1] = TF("editor.popup.confirm_assigned_after", {label = label})
            elseif kind == "firstRun" then
                parts[#parts + 1] = TF("editor.popup.confirm_becomes_first_run", {label = label})
            elseif kind == "unknown" then
                parts[#parts + 1] = T("editor.popup.confirm_not_loaded")
            else
                -- What the editor captured, not what was open in the game: a
                -- copied draft can begin while a Saved Build is selected.
                parts[#parts + 1] = T("editor.popup.confirm_no_capture") .. " "
                    .. T("editor.popup.confirm_assign_afterwards")
            end
            parts[#parts + 1] = T("editor.popup.confirm_not_overwritten") .. " "
                .. T("editor.popup.confirm_nothing_spent")
        end
        -- Only a save that writes a Saved Build destination carries Auto's
        -- consequence (M.AutoConsentLine): ON, held ON, or its save permission off.
        if kind == "savedBuild" and not saveOnly and not (type(data) == "table" and data.keepsAssignment) then
            local line = M.AutoConsentLine(label)
            if line then parts[#parts + 1] = line end
        end
        return table.concat(parts, "\n")
    end

    -- Plain words for a refusal or a failed assignment; the code itself is
    -- kept only as a hover detail when no plain wording is known.
    function M.PlainSaveReason(kind, reason, detail, label)
        -- Reason and detail codes stay raw (they are matched here and kept
        -- as the hover detail); only the plain words are localized.
        local where = label or T("editor.value.the_saved_build")
        if kind == "partial" then
            local refused = {
                ["that loadout slot is empty or unavailable"] = "editor.status.reason_partial_empty",
                ["invalid loadout"] = "editor.status.reason_partial_outside",
                ["store unavailable"] = "editor.status.reason_partial_not_stored",
                ["unavailable"] = "editor.status.reason_partial_not_stored",
                ["invalid wishlist"] = "editor.status.reason_partial_not_recorded",
                ["invalid slot"] = "editor.status.reason_partial_slot_unknown",
            }
            if reason == "draftChanged" then return T("editor.status.reason_partial_draft_changed") end
            if reason == "localTargets" then return T("editor.status.reason_partial_local_targets") end
            if reason == "error" then return T("editor.status.reason_partial_error") end
            -- A writer that gave no reason is shown neutrally, not as a guess.
            if detail == nil then return T("editor.status.reason_partial_refused") end
            local plainKey = refused[tostring(detail)]
            if plainKey == "editor.status.reason_partial_empty"
                or plainKey == "editor.status.reason_partial_outside" then
                return TF(plainKey, {where = where})
            end
            if plainKey then return T(plainKey) end
            return T("editor.status.reason_partial_refused"), detail
        end
        local words = {
            stale_confirmation = "editor.status.reason_stale_confirmation",
            retry_draft_changed = "editor.status.reason_retry_draft_changed",
            assignment_changed = "editor.status.reason_assignment_changed",
            destination_empty = "editor.status.reason_destination_empty",
            stale_slot = "editor.status.reason_stale_slot",
            design_limit = "editor.status.reason_design_limit",
            mirror_unresolved = "editor.status.reason_mirror_unresolved",
            stale_candidate = "editor.status.reason_stale_candidate",
            stale_payload = "editor.status.reason_stale_payload",
            empty = "editor.status.reason_empty",
            name = "editor.status.reason_name",
            adapter = "editor.status.reason_adapter",
            expired = "editor.status.reason_expired",
            refused = "editor.status.reason_refused",
            ["no echoes"] = "editor.status.reason_no_echoes",
            ["no valid echoes"] = "editor.status.reason_no_valid_echoes",
            invalid_locked_design = "editor.status.reason_invalid_locked_design",
            name_taken = "editor.status.reason_name_taken",
            name_unavailable = "editor.status.reason_name_unavailable",
            destination_changed = "editor.status.reason_destination_changed",
            no_destination = "editor.status.reason_no_destination",
            invalid_intent = "editor.status.reason_invalid_intent",
            error = "editor.status.reason_error",
        }
        local plainKey = words[tostring(reason or "")]
        if plainKey == "editor.status.reason_assignment_changed"
            or plainKey == "editor.status.reason_destination_empty" then
            return TF(plainKey, {where = where})
        end
        if plainKey then return T(plainKey) end
        return T("editor.status.reason_not_completed"), reason
    end

    -- The row's one line and its hover lines for a SaveResult copy.
    function M.SaveResultLines(result)
        local plan = "'" .. (DisplayUntrusted(result.name, 1024, false) or T("editor.value.wishlist_fallback")) .. "'"
        local destination = type(result.destination) == "table" and result.destination or {}
        local label = M.DestinationLabel(destination)
        local copies = tonumber(result.copies)
        local planned = copies and TF("editor.tooltip.result_planned", {count = N(copies)}) or nil
        local journal = T("editor.tooltip.result_journal")
        -- The colored state word of the row, then the rest of its line.
        local function Head(color, key) return color .. T(key) .. "|r" end
        local kind, reason = result.kind, result.reason
        -- Hover lines without the ones that do not apply (no gaps for ipairs).
        local function Lines(...)
            local out = {}
            for index = 1, select("#", ...) do
                local line = select(index, ...)
                if line ~= nil then out[#out + 1] = line end
            end
            return out
        end
        -- What this save wrote on this character was accepted for this session
        -- only (saved data cannot be written now): said, never shown as kept.
        local session = result.sessionOnly and (TF("editor.tooltip.result_session_only", {reason =
            tostring(DisplayUntrusted(result.writeReason or result.sessionOnly, 140, false)
                or T("editor.value.reason_unavailable"))})
            .. " " .. T("editor.tooltip.result_not_uploaded_again")) or nil
        if kind == "assigned" then
            local where = label or T("editor.value.its_saved_build")
            if session then
                return Head("|cffffd200", "editor.status.result_saved") .. " "
                    .. TF("editor.status.result_assigned_session", {plan = plan, label = where}),
                    Lines(session, T("editor.tooltip.result_nothing_activated"), planned)
            end
            return Head("|cff4dff80", "editor.status.result_saved") .. " "
                .. TF("editor.status.result_assigned", {plan = plan, label = where}),
                {TF("editor.tooltip.result_now_uses", {label = where}) .. " "
                    .. T("editor.tooltip.result_nothing_activated"), planned}
        elseif kind == "firstRun" then
            local who = DisplayUntrusted(destination.character, 1024, false) or T("editor.value.this_character")
            if session then
                return Head("|cffffd200", "editor.status.result_saved") .. " "
                    .. TF("editor.status.result_first_run_session", {plan = plan, character = who}),
                    Lines(session, T("editor.tooltip.result_no_saved_build_changed"), planned)
            end
            return Head("|cff4dff80", "editor.status.result_saved") .. " "
                .. TF("editor.status.result_first_run", {plan = plan, character = who}),
                {T("editor.tooltip.result_used_until") .. " "
                    .. T("editor.tooltip.result_no_saved_build_changed"), planned}
        elseif kind == "unassigned" and reason == "saveOnly" then
            -- Save changes of a plan that could have been assigned: as chosen.
            return Head("|cffffd200", "editor.status.result_saved_not_assigned") .. " "
                .. TF("editor.status.result_save_only", {plan = plan}),
                Lines(T("editor.tooltip.result_plan_saved") .. " " .. T("editor.tooltip.result_no_target_changed"),
                    journal, session, planned)
        elseif kind == "unassigned" then
            -- What this editor captured for this save, not a claim about what
            -- other Saved Builds use.
            local why = T(reason == "notLoaded" and "editor.status.result_why_not_loaded"
                or reason == "unboundPlan" and "editor.status.result_why_unbound"
                or "editor.status.result_why_no_capture")
            return Head("|cffffd200", "editor.status.result_saved_not_assigned") .. " "
                .. TF("editor.status.result_with_reason", {plan = plan, reason = why}),
                Lines(T("editor.tooltip.result_plan_saved") .. " " .. T("editor.tooltip.result_assigned_nothing"),
                    journal, session, planned)
        elseif kind == "uncertain" then
            -- The host call ended in an error: whether it arrived is unknown.
            return Head("|cffff6060", "editor.status.result_not_confirmed") .. " "
                .. TF("editor.status.result_send_error", {plan = plan}),
                Lines(T("editor.tooltip.result_may_have_reached") .. " " .. T("editor.tooltip.result_not_sent_again"),
                 T("editor.tooltip.result_check_journal") .. " " .. T("editor.tooltip.result_create_another_anyway"),
                 planned)
        elseif kind == "kept" then
            return Head("|cffffd200", "editor.status.result_saved_not_assigned") .. " "
                .. TF("editor.status.result_kept", {plan = plan,
                    label = label or T("editor.value.its_destination")}),
                {T("editor.tooltip.result_plan_saved") .. " " .. T("editor.tooltip.result_newer_choice_kept"),
                    journal, planned}
        elseif kind == "partial" then
            local plain, code = M.PlainSaveReason(kind, reason, result.detail, label)
            local lines = {}
            -- The safe next step never uploads again (F7): pressing Create for
            -- this draft sends nothing, while a changed plan or name would
            -- create another Wishlist.
            local again = result.create and T("editor.tooltip.result_press_create_again") or nil
            if reason == "association" then
                lines[1] = T("editor.tooltip.result_assignment_refused") .. " "
                    .. T("editor.tooltip.result_nothing_uploaded_again")
                lines[2] = journal
                lines[#lines + 1] = again
            elseif reason == "draftChanged" then
                lines[1] = T("editor.tooltip.result_editor_changed") .. " "
                    .. T("editor.tooltip.result_review_save_again")
            elseif reason == "error" then
                lines[1] = T("editor.tooltip.result_later_step_failed") .. " "
                    .. T("editor.tooltip.result_nothing_uploaded_from_draft")
                lines[2] = again
            else
                lines[1] = T("editor.tooltip.result_targets_not_saved") .. " "
                    .. T("editor.tooltip.result_draft_kept")
                lines[2] = result.create
                    and (TF("editor.tooltip.result_store_targets", {plan = plan}) .. " " .. again)
                    or T("editor.tooltip.result_save_again_later")
            end
            if code then
                lines[#lines + 1] = TF("editor.tooltip.result_details",
                    {code = tostring(DisplayUntrusted(code, 140, false) or "")})
            end
            return Head("|cffff6060", "editor.status.result_uploaded_not_assigned") .. " "
                .. TF("editor.status.result_with_reason", {plan = plan, reason = plain}), lines
        end
        local plain, code = M.PlainSaveReason("notSaved", reason, nil, label)
        local lines = {T("editor.tooltip.result_nothing_saved")}
        if code then
            lines[2] = TF("editor.tooltip.result_details", {code = tostring(DisplayUntrusted(code, 140, false) or "")})
        end
        return Head("|cffff6060", "editor.status.result_not_saved") .. ": " .. plain, lines
    end

    function M.EnsureSaveResultRow()
        if not frame or frame._saveResultText then return end
        -- Between the name field (create mode) and Import/Export, above the
        -- locked strip; clear of the fixed list, footer and Save geometry.
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", 400, -92)
        text:SetSize(456, 18)
        text:SetJustifyH("LEFT")
        if type(text.SetWordWrap) == "function" then pcall(text.SetWordWrap, text, false) end
        text:SetText("")
        text:Hide()
        frame._saveResultText = text
        local hover = CreateFrame("Frame", nil, frame)
        hover:SetPoint("TOPLEFT", text, "TOPLEFT", 0, 0)
        hover:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", 0, 0)
        hover:EnableMouse(true)
        -- The one-line result is cut at its width with longer or larger
        -- text, so its hover always repeats the whole line (then any detail
        -- lines), not only when details exist.
        hover:SetScript("OnEnter", function(self)
            local whole = frame and frame._saveResultText and frame._saveResultText:GetText() or ""
            if not GameTooltip or whole == "" then return end
            local lines = frame._saveResultDetail
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(tostring(whole), 1, 1, 1, true)
            for _, line in ipairs(type(lines) == "table" and lines or {}) do
                GameTooltip:AddLine(line, 0.82, 0.82, 0.82, true)
            end
            GameTooltip:Show()
        end)
        hover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        hover:Hide()
        frame._saveResultHover = hover
        local button = CreateFrame("Button", "NexusWishlistAssignNowButton", frame, "UIPanelButtonTemplate")
        button:SetSize(120, 20)
        button:SetPoint("TOPLEFT", 736, -91)
        button:SetText(T("editor.button.assign_now"))
        button:SetScript("OnClick", function() M.AssignNow() end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(T("editor.tooltip.assign_now_heading"), 1, 0.8, 0.3)
            GameTooltip:AddLine(T("editor.tooltip.assign_now_route") .. " "
                .. T("editor.tooltip.assign_now_chooser"), 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(T("editor.tooltip.assign_now_safe"),
                0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button:Hide()
        frame._assignNowBtn = button
    end

    -- Draw the current result (or none). Reading it changes nothing; a
    -- result the controller no longer considers current is not shown.
    function M.RenderSaveResult()
        if not frame or not frame._saveResultText then return end
        local result = Controller.SaveResult and Controller.SaveResult(M.NameText()) or nil
        local text, hover, button = frame._saveResultText, frame._saveResultHover, frame._assignNowBtn
        if not result then
            frame._saveResultDetail = nil
            text:SetText("")
            text:Hide(); hover:Hide(); button:Hide()
            return
        end
        local line, detail = M.SaveResultLines(result)
        frame._saveResultDetail = detail
        text:SetWidth(result.assignNow and 330 or 456)
        text:SetText(line)
        text:Show(); hover:Show()
        if result.assignNow then button:Show() else button:Hide() end
    end

    -- Assign now: the established Journal assignment route for a saved plan
    -- that no destination uses. The controller refuses when the result is
    -- no longer current, slot data is not loaded, or the Journal would
    -- assign somewhere other than the captured destination; the editor is
    -- then left as it is.
    function M.AssignNowRefusal(why, destination)
        local label = M.DestinationLabel(destination)
        if why == "not_loaded" then
            return T("editor.chat.assign_now_not_loaded") .. " " .. T("editor.chat.assign_now_try_again")
        elseif why == "elsewhere" then
            if type(destination) == "table" and destination.kind == "firstRun" then
                return T("editor.chat.assign_now_elsewhere_first_run") .. " "
                    .. T("editor.chat.assign_now_reopen_continue")
            end
            -- No advice to switch Saved Builds: that is a game action with
            -- its own consequences, and Nexus never does it for the player.
            return TF("editor.chat.assign_now_elsewhere", {label = label or T("editor.value.the_one")})
                .. " " .. T("editor.chat.assign_now_reopen_work")
        elseif why == "empty_target" then
            return TF("editor.chat.assign_now_empty_target", {label = label or T("editor.value.a_saved_build")})
                .. " " .. T("editor.chat.assign_now_not_opened")
        elseif why == "route_unavailable" then
            return T("editor.chat.assign_now_no_route") .. " " .. T("editor.chat.assign_now_open_yourself")
        end
        return T("editor.chat.assign_now_stale")
    end

    function M.AssignNow()
        local ok, why, destination = Controller.AssignNowCheck(M.NameText())
        if not ok then
            print("|cffff6060Nexus:|r " .. M.AssignNowRefusal(why, destination))
            M.RenderSaveResult()
            return false
        end
        local journal = Nexus.JournalTab
        if not (journal and type(journal.OpenBuilds) == "function") then
            print("|cffff6060Nexus:|r " .. T("editor.chat.assign_now_selector_unavailable") .. " "
                .. T("editor.chat.nothing_assigned"))
            return false
        end
        -- The route must be able to open before the editor (and its result)
        -- is closed for it.
        if type(journal.CanOpenBuilds) == "function" and not journal.CanOpenBuilds() then
            print("|cffff6060Nexus:|r " .. M.AssignNowRefusal("route_unavailable"))
            M.RenderSaveResult()
            return false
        end
        -- As the main panel's Assign Wishlist: the editor closes first, since
        -- the Echo Journal is kept hidden while the editor is shown; the
        -- Journal then opens its Wishlist chooser for the target it shows.
        M.Hide()
        journal.OpenBuilds(true)
        return true
    end

    function M.SetNameText(value)
        EnsureFrame()
        if wishlistNameBox then wishlistNameBox:_NexusSetRawText(value) end
    end

    function M.NameText()
        return wishlistNameBox and wishlistNameBox:_NexusRawText() or nil
    end

    function M.Prepare(config)
        EnsureFrame()
        DismissSaveConfirmation()
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

    function M.DismissTransients()
        HideEditorTransients()
    end

    function M.Hide()
        M.HideManageWishlistsMenu()
        HideEditorTransients()
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

-- Confirmation for removing one retained wishlist. Everything it needs comes
-- in as data, so this registration holds no editor state and the dialog
-- cannot act on a plan other than the one the clicked row named.
-- The accept and cancel labels resolve when the popup reads them (the
-- session language is chosen after this file loads).
StaticPopupDialogs["NEXUS_FORGET_WISHLIST"] = setmetatable({
    text = "%s",
    OnAccept = function(self, data)
        data = type(data) == "table" and data
            or (type(self) == "table" and self.data) or nil
        local plan = type(data) == "table" and data.plan or nil
        if not (plan and type(data.forget) == "function") then return end
        local ok, reason = data.forget({
            associationIndex = plan.associationIndex,
            key = plan.key, assignmentId = plan.assignmentId,
        })
        if not ok then
            print("|cffff9040Nexus:|r " .. tostring(reason and Nexus.UserText.Recognized(reason)
                or T("editor.chat.forget_failed_default")))
        end
        if type(data.after) == "function" then data.after() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}, {__index = function(_, field)
    if field == "button1" then return T("editor.button.remove") end
    if field == "button2" then return T("editor.button.cancel") end
end})

Nexus.WishlistInternals.Renderer = Renderer
