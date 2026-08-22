-- Nexus: ui/WishlistEditor.lua
-- Stable Wishlist facade and popup assembly over one model, controller, and
-- complete virtual editor renderer.

Nexus = Nexus or {}
local M = {}
Nexus.WishlistEditor = M

local WishlistModelFactory = assert(Nexus.WishlistModel,
    "WishlistModel must load before WishlistEditor")
local DraftModel = assert(WishlistModelFactory.New(),
    "WishlistModel.New failed")
local WishlistControllerFactory = assert(Nexus.WishlistInternals
    and Nexus.WishlistInternals.Controller,
    "WishlistController must load before WishlistEditor")
local WishlistRendererFactory = assert(Nexus.WishlistInternals
    and Nexus.WishlistInternals.Renderer,
    "WishlistRenderer must load before WishlistEditor")

local MAX_WISHLIST_ECHOES = 79
local EchoListTotal = DraftModel.EchoListTotal
local TrimWishlistName = DraftModel.TrimName

local Model
local wishlistRenderer
local HideServerEchoUI
local serverHideHooks = {}
local wishlistController

local function SyncFulfilledDraftTargets()
    M._fulfilledDraftTargets =
        wishlistController and wishlistController.FulfilledDraftTargets() or {}
end

wishlistController = WishlistControllerFactory.New({
    model = DraftModel,
    store = assert(Nexus.Store,
        "Store must load before WishlistController"),
    accountRoot = function() return NexusDB end,
    notify = function(message) print(message) end,
    requestRecompute = function()
        if Nexus.RequestRecompute then Nexus.RequestRecompute() end
    end,
    retryAutoLock = function()
        return Nexus.RetryAutoLock and Nexus.RetryAutoLock() or false
    end,
    openCommunity = function()
        if Nexus.CommunityBuilds then
            Nexus.CommunityBuilds.Show()
            return true
        end
        print("|cffff6060Nexus:|r Nexus Builds unavailable")
        return false
    end,
})
SyncFulfilledDraftTargets()

local function EnsureWishlistRenderer()
    if wishlistRenderer then return wishlistRenderer end
    wishlistRenderer = WishlistRendererFactory.New({
        controller = wishlistController,
        family = DraftModel.Family,
        draftKey = DraftModel.DraftKey,
        echoListTotal = DraftModel.EchoListTotal,
        maskMatch = function(classMask, playerMask)
            return Model and Model.MaskMatch
                and Model.MaskMatch(classMask, playerMask)
        end,
        entryProgress = function(entries, owned, locked)
            return Model and Model.WishlistEntryProgress
                and Model.WishlistEntryProgress(entries, owned, locked) or nil
        end,
        syncFulfilled = SyncFulfilledDraftTargets,
        hideServerEchoUI = function()
            if HideServerEchoUI then HideServerEchoUI() end
        end,
        overlay = function()
            return Nexus.WishlistOverlay
        end,
        newWishlist = function() return M.NewWishlist() end,
        openForWishlist = function(wishlist, loadoutSlot)
            return M.OpenForWishlist(wishlist, loadoutSlot)
        end,
        pumpApplyRetry = function() return M._PumpApplyRetry() end,
        refresh = function() return M.Refresh() end,
    })
    return wishlistRenderer
end

local function RendererInstance()
    return assert(EnsureWishlistRenderer(),
        "Wishlist renderer unavailable")
end

function M._PumpApplyRetry()
    local ok = wishlistController.PumpApplyRetry()
    SyncFulfilledDraftTargets()
    if ok and wishlistRenderer then wishlistRenderer.SetApplySaved() end
end

function M.IsApplyPending()
    return wishlistController.IsApplyPending()
end

local function AcceptApply(data)
    local ok, err = wishlistController.AcceptApply(data)
    SyncFulfilledDraftTargets()
    if ok and wishlistRenderer then wishlistRenderer.SetApplySaved() end
    return ok, err
end

StaticPopupDialogs["WISHLISTREALIZER_UPDATE_WISHLIST"] = {
    text = "Save %d / 79 Echoes to '%s'?\nThis updates the associated server wishlist in place.",
    button1 = "Save Changes",
    button2 = "Cancel",
    OnAccept = function(self, data)
        AcceptApply(data)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["WISHLISTREALIZER_CREATE_WISHLIST"] = {
    text = "Create '%s' with %d / 79 Echoes?\nThis saves to a new server wishlist slot and automatically assigns it to the active Saved Build. Existing wishlists will not be overwritten.",
    button1 = "Create Wishlist",
    button2 = "Cancel",
    OnAccept = function(self, data)
        AcceptApply(data)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function ExportEBH1String()
    local Codec = Nexus and Nexus.Codec
    if not (Codec and Codec.EncodeEBH1) then
        return nil, "export codec unavailable"
    end
    local entries = wishlistController.ExportEntries()
    local classToken = ""
    if UnitClass then
        local _, eng = UnitClass("player")
        classToken = eng or ""
    end
    local nameText = wishlistRenderer and wishlistRenderer.NameText()
    local name = wishlistController.ExportName(nameText)
    return Codec.EncodeEBH1(entries, classToken, name)
end

local function LoadImportedWishlist(parsed, chosenName)
    local ok, name, count, why =
        wishlistController.LoadImported(parsed, chosenName)
    if not ok then
        print("|cffff6060Nexus:|r couldn't import that EBH1 string: "
            .. tostring(why or "the Echo roles could not be represented exactly") .. ".")
        return false
    end
    SyncFulfilledDraftTargets()
    HideServerEchoUI()
    local renderer = RendererInstance()
    renderer.Prepare({attach=true, style=true, close=true})
    renderer.SetNameText(name)
    renderer.ShowFrame()
    M.Refresh()
    print(string.format(
        "|cff4dff80Nexus:|r imported %d Echo entr%s as new wishlist '%s'. Review and Create Wishlist when ready.",
        count, count == 1 and "y" or "ies", name))
    return true
end

function M.ImportEBH1String(text, chosenName)
    local Codec = Nexus and Nexus.Codec
    if not (Codec and Codec.DecodeEBH1) then
        print("|cffff6060Nexus:|r import codec unavailable")
        return
    end
    local parsed = Codec.DecodeEBH1(text)
    if not parsed or #parsed.entries == 0 then
        print("|cffff6060Nexus:|r couldn't parse that as an EBH1 string.")
        return
    end

    local name = TrimWishlistName(chosenName)
    if name ~= "" then
        LoadImportedWishlist(parsed, name)
        return
    end
    StaticPopup_Show("NEXUS_NAME_IMPORTED_WISHLIST",
        TrimWishlistName(parsed.name) ~= ""
            and TrimWishlistName(parsed.name) or "Imported Wishlist",
        nil, parsed)
end

StaticPopupDialogs["NEXUS_EXPORT_WISHLIST"] = {
    text = "Your current wishlist + locked Echoes, as an EBH1 string.\nCtrl+A, Ctrl+C to copy:",
    button1 = "Close",
    hasEditBox = true,
    editBoxWidth = 350,
    OnShow = function(self)
        self.editBox:SetText((ExportEBH1String()) or "")
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["NEXUS_NAME_IMPORTED_WISHLIST"] = {
    text = "Choose a name for this imported wishlist:\n%s",
    button1 = "Load Import",
    button2 = "Cancel",
    hasEditBox = true,
    editBoxWidth = 300,
    OnShow = function(self)
        local suggested = TrimWishlistName(self.data and self.data.name)
        if suggested == "" then suggested = "Imported Wishlist" end
        self.editBox:SetText(suggested)
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    OnAccept = function(self, parsed)
        local name = TrimWishlistName(
            self.editBox and self.editBox:GetText())
        if name == "" then
            print("|cffff6060Nexus:|r Enter a name for the imported wishlist.")
            return
        end
        LoadImportedWishlist(parsed, name)
    end,
    EditBoxOnEnterPressed = function(self)
        self:GetParent().button1:Click()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["NEXUS_IMPORT_WISHLIST"] = {
    text = "Paste an EBH1 wishlist string:\nThe import will be loaded as a new wishlist and will not overwrite the one currently open.",
    button1 = "Continue",
    button2 = "Cancel",
    hasEditBox = true,
    editBoxWidth = 350,
    OnAccept = function(self)
        M.ImportEBH1String(self.editBox and self.editBox:GetText())
    end,
    EditBoxOnEnterPressed = function(self)
        self:GetParent().button1:Click()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

HideServerEchoUI = function()
    local journal = _G["ProjectEbonholdEchoJournal"]
    local editorFrame = _G["NexusEditorFrame"]
    local targets = {}
    local frame = journal
    for _ = 1, 4 do
        if not frame or frame == UIParent or frame == editorFrame then break end
        targets[#targets + 1] = frame
        frame = frame.GetParent and frame:GetParent() or nil
    end
    for _, target in ipairs(targets) do
        if HideUIPanel then pcall(HideUIPanel, target) end
        if target.Hide then pcall(target.Hide, target) end
        if target.HookScript and not serverHideHooks[target] then
            serverHideHooks[target] = true
            pcall(target.HookScript, target, "OnShow", function(self)
                if wishlistRenderer and wishlistRenderer.IsShown() then
                    if HideUIPanel then pcall(HideUIPanel, self) end
                    pcall(self.Hide, self)
                end
            end)
        end
    end
end



function M.ToggleDisplayPopup(anchorTo)
    return RendererInstance().ToggleDisplayPopup(anchorTo)
end

function M.Init(adapter, model)
    Model = model
    wishlistController.Initialize(adapter)
    SyncFulfilledDraftTargets()
    EnsureWishlistRenderer()
end

function M.DebugPendingCount()
    return wishlistController.DebugDraftState().pending
end

function M.DebugDraftState()
    return wishlistController.DebugDraftState()
end

function M.OpenForCandidate(candidate)
    local name, reason = wishlistController.BeginCandidate(candidate)
    if name == nil then
        SyncFulfilledDraftTargets()
        return false, reason
    end
    SyncFulfilledDraftTargets()
    local renderer = RendererInstance()
    renderer.Prepare()
    if type(candidate) == "table" and candidate.title then
        renderer.SetNameText(name)
    end
    renderer.ShowFrame()
    M.Refresh()
    return true
end

function M.OpenForWishlist(wishlist, loadoutSlot)
    if not wishlistController.BeginWishlist(wishlist, loadoutSlot) then
        SyncFulfilledDraftTargets()
        return false
    end
    SyncFulfilledDraftTargets()
    local renderer = RendererInstance()
    renderer.Prepare()
    HideServerEchoUI()
    renderer.Prepare({close=true})
    renderer.ShowFrame()
    M.Refresh()
    return true
end

function M.NewWishlist()
    HideServerEchoUI()
    wishlistController.BeginNewWishlist()
    SyncFulfilledDraftTargets()
    local renderer = RendererInstance()
    renderer.Prepare({attach=true, style=true, close=true})
    renderer.SetNameText("")
    renderer.ShowFrame()
    M.Refresh()
end

function M.Show()
    local ok, mode, clearName = wishlistController.BeginShow()
    if not ok then return ok, mode, clearName end
    SyncFulfilledDraftTargets()

    local renderer = RendererInstance()
    renderer.Prepare({attach=true, style=true})
    if clearName then renderer.SetNameText("") end
    HideServerEchoUI()
    renderer.Prepare({close=true})
    renderer.ShowFrame()
    M.Refresh()
end

function M.Refresh()
    local result = RendererInstance().Refresh()
    SyncFulfilledDraftTargets()
    return result
end

function M.Toggle()
    local renderer = RendererInstance()
    renderer.Prepare()
    if renderer.IsShown() then renderer.Hide() else M.Show() end
end
