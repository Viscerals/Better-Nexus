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

-- Visible editor copy comes from the reviewed seam (core/Localization.lua,
-- keys "editor.*"), looked up when it is shown, never cached at load: the
-- session language is chosen after this file loads. Names, codes and game
-- data are inserted through template text slots and are never translated.
local function T(key) return (Nexus.Localization.Text(key)) end
local function TF(key, args) return (Nexus.Localization.Format(key, args)) end
local function N(value) return Nexus.Localization.Count(value) end

-- The client formats a StaticPopup's text (SetFormattedText): every "%" a
-- translation holds is made literal, and POPUP_SLOT (a byte no reviewed text
-- may hold) marks where the dialog's own "%s" argument goes.
local POPUP_SLOT = "\127"
local function PopupText(text)
    local escaped = tostring(text):gsub("%%", "%%%%")
    return (escaped:gsub(POPUP_SLOT, "%%s"))
end

-- A dialog whose visible fields are resolved each time the popup reads them,
-- so a popup shown by any caller (the guided setup shows the import one)
-- names the session language. A field the editor assigns directly (a Save
-- confirmation's accept label) is used as assigned.
local function LocalizedDialog(dialog, fields)
    return setmetatable(dialog, {__index = function(_, field)
        local resolve = fields[field]
        if resolve then return resolve() end
    end})
end
local function CancelLabel() return T("editor.button.cancel") end
-- The code-owned names of the five Echo qualities (0..4), as the editor's
-- catalog shows them (WishlistRenderer uses the same keys).
local function QualityNames()
    return {[0]=T("editor.value.quality_common"),[1]=T("editor.value.quality_uncommon"),
        [2]=T("editor.value.quality_rare"),[3]=T("editor.value.quality_epic"),
        [4]=T("editor.value.quality_legendary")}
end

local function DisplayUntrusted(value, maxBytes, allowEmpty, allowLineBreaks)
    local identity = Nexus and Nexus.Identity
    if not (identity and type(identity.DisplaySafeText) == "function") then
        return nil
    end
    return identity.DisplaySafeText(
        value, maxBytes, allowEmpty, allowLineBreaks)
end

-- A pasted EBH1 code is a wire value, not a name: it needs the whole field.
-- The supported envelope is 85 entries of at most "id.quality.stacks.1" plus
-- the class and a 96-letter name, so this bound is far above any code the
-- addon can produce and still bounded.
local IMPORT_MAX_LETTERS = 4096

local function ConfigureSafeNameEditBox(box)
    if not box or box._nexusSafeNameOwner then return end
    box._nexusSafeNameOwner = true
    local priorChanged = box:GetScript("OnTextChanged")
    box._nexusSafeNamePriorChanged = priorChanged
    box:SetMaxLetters(96)
    box._NexusSetRawText = function(self, value)
        local raw = tostring(value or "")
        local display = DisplayUntrusted(raw, 1024, true) or ""
        self._nexusRawText = raw
        self._nexusDisplayText = display
        if self:GetText() ~= display then
            self._nexusNormalizing = true
            self:SetText(display)
            self._nexusNormalizing = nil
        end
        if priorChanged then priorChanged(self) end
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
        self:_NexusSetRawText(tostring(self:GetText() or ""):gsub("||", "|"))
    end)
end

-- StaticPopup frames and their edit boxes are pooled and reused, so a dialog
-- that declares nothing inherits the limit and the handlers the previous
-- dialog left. Both EBH1 dialogs therefore claim the field every time they
-- open: the naming dialog's 96-letter limit and its display-sanitising handler
-- are removed, so a pasted code reaches the importer unchanged and an exported
-- code is shown for copying in full.
local function ClaimWireEditBox(box)
    if not box then return end
    if box._nexusSafeNameOwner then
        box:SetScript("OnTextChanged", box._nexusSafeNamePriorChanged)
        box._nexusSafeNameOwner = nil
        box._nexusSafeNamePriorChanged = nil
        box._NexusSetRawText = nil
        box._NexusRawText = nil
        box._nexusRawText = nil
        box._nexusDisplayText = nil
    end
    box:SetMaxLetters(IMPORT_MAX_LETTERS)
end

local function ConfigureImportEditBox(box)
    if not box then return end
    ClaimWireEditBox(box)
    box:SetText("")
end

local function SetExplicitCopyText(box, value)
    -- EBH1 is an explicit copy/paste wire boundary, and the player copies
    -- whatever this field holds. The field is still a WoW rich-text surface, so
    -- the value is shown through the inert projection and never as raw bytes.
    -- The projection doubles a literal pipe; a wishlist name no longer carries
    -- one, because TrimName removes it where a name is accepted, so for every
    -- code this addon produces the projection is the identity and the field
    -- holds the code exactly.
    -- The field is claimed first: a name limit inherited from the naming dialog
    -- would cut the code that the player is about to copy.
    if not box then return end
    ClaimWireEditBox(box)
    local raw = tostring(value or "")
    box._nexusExplicitExportText = raw
    local shown = DisplayUntrusted(raw, #raw, true, true)
    if not shown then
        -- Nothing showable, so nothing is shown. Say so instead of leaving an
        -- empty box under a "copy this" label.
        box:SetText("")
        print("|cffff6060Nexus:|r " .. T("editor.chat.export_name_undisplayable"))
        return
    end
    box:SetText(shown)
end

local Model, Adapter
local RolePicker
local wishlistRenderer
local HideServerEchoUI
local serverHideHooks = {}
local wishlistController
local flexiblePlanChooser
local flexiblePlanRequest
-- A workspace tab change is navigation, not a new editor open. Keep this
-- controller draft only for the same character and selected Saved Build.
local workspaceResume
local function RefuseSuspendedDraftReplacement()
    if not workspaceResume then return false end
    print("|cffffd200Nexus:|r " .. T("editor.chat.plan_draft_suspended"))
    return true
end

local function SyncFulfilledDraftTargets()
    M._fulfilledDraftTargets =
        wishlistController and wishlistController.FulfilledDraftTargets() or {}
end

wishlistController = WishlistControllerFactory.New({
    model = DraftModel,
    store = assert(Nexus.Store,
        "Store must load before WishlistController"),
    -- The editor's own saved keys. A read-only saved root is never written:
    -- the Store owner hands back a session-only table for it instead.
    accountRoot = function()
        local writable = Nexus.MainInternals and Nexus.MainInternals.WritableRootV1
        if type(writable) == "function" then
            return writable(nil, {"editorSearch", "editorClassOnly", "lockDesignTargets"})
        end
        return NexusDB
    end,
    -- The controller already says its line through UserText.Message once.
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
        print("|cffff6060Nexus:|r " .. T("editor.chat.build_library_unavailable"))
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

-- Guided setup receipts (core/GuidedSetup.lua): passive reports of real
-- outcomes of this editor. They record only; nothing here writes, uploads
-- or assigns, and a missing guide changes nothing.
local guideSeen = 0
local function GuideNote(kind, fields)
    local guide = Nexus.GuidedSetup
    if guide and type(guide.Note) == "function" then pcall(guide.Note, kind, fields) end
end
local function GuideSave()
    local read = wishlistController.SaveReceipt
    local receipt = type(read) == "function" and read() or nil
    if type(receipt) == "table" and (tonumber(receipt.serial) or 0) > guideSeen then
        guideSeen = receipt.serial
        GuideNote("save", receipt)
    end
end

function M._PumpApplyRetry()
    local ok = wishlistController.PumpApplyRetry()
    SyncFulfilledDraftTargets()
    if ok and wishlistRenderer then wishlistRenderer.SetApplySaved() end
    -- A finished retry (not an idle pump) shows its result at once.
    if ok ~= nil and wishlistRenderer then wishlistRenderer.RenderSaveResult() end
    if ok ~= nil then GuideSave() end
end

function M.IsApplyPending()
    return wishlistController.IsApplyPending()
end

local function AcceptApply(data)
    local ok, err = wishlistController.AcceptApply(data)
    SyncFulfilledDraftTargets()
    if ok and wishlistRenderer then wishlistRenderer.SetApplySaved() end
    if wishlistRenderer then wishlistRenderer.RenderSaveResult() end
    GuideSave()
    return ok, err
end

-- The second argument of both confirmations is composed by the renderer
-- (ConfirmationText): the planned count, the destination this editor
-- captured and, only when it applies, the Auto line. The renderer sets each
-- accept button to the action that opened it (ConfirmLabel) before showing.
StaticPopupDialogs["WISHLISTREALIZER_UPDATE_WISHLIST"] = LocalizedDialog({
    -- The accept label stays a source literal (localization pending, see
    -- WishlistRenderer M.ApplyAction); the renderer sets it before each show.
    button1 = "Save changes",
    OnCancel = function(_, data) wishlistController.CancelApply(data) end,
    OnAccept = function(self, data)
        AcceptApply(data)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}, {
    text = function()
        return PopupText(TF("editor.popup.save_changes_question", {name = POPUP_SLOT})) .. "\n%s"
    end,
    button2 = CancelLabel,
})

StaticPopupDialogs["WISHLISTREALIZER_CREATE_WISHLIST"] = LocalizedDialog({
    button1 = "Create & assign",
    OnCancel = function(_, data) wishlistController.CancelApply(data) end,
    OnAccept = function(self, data)
        AcceptApply(data)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}, {
    text = function()
        return PopupText(TF("editor.popup.create_question", {name = POPUP_SLOT})) .. "\n%s"
    end,
    button2 = CancelLabel,
})

-- The code of the open draft, or nil and why there is none. The second value
-- of a code is what it leaves out (the controller's note), or nil.
local function ExportEBH1String()
    local Codec = Nexus and Nexus.Codec
    if not (Codec and Codec.EncodeEBH1) then
        return nil, T("editor.error.export_codec_unavailable")
    end
    local entries, note = wishlistController.ExportEntries()
    local classToken = ""
    if UnitClass then
        local _, eng = UnitClass("player")
        classToken = eng or ""
    end
    local nameText = wishlistRenderer and wishlistRenderer.NameText()
    local name = wishlistController.ExportName(nameText)
    local code = Codec.EncodeEBH1(entries, classToken, name)
    -- EncodeEBH1 empties the Echo list of a plan outside the code's envelope
    -- (79 rolled copies, 6 locked target copies, 85 entries) and of a plan
    -- with no Echo; such a code imports nowhere, so none is offered.
    if type(code) ~= "string" or code:sub(1, 6) == "EBH1::" then
        return nil, #(entries or {}) == 0 and T("editor.error.export_no_echoes")
            or T("editor.error.export_envelope")
    end
    return code, note
end

-- The export dialog's prompt says what this code is. The client's StaticPopup
-- dialog keeps its prompt in a font string (`text`, which the native dialogs'
-- own OnShow handlers rewrite); without one only the chat line is given.
local function ExportPrompt(dialog, text)
    local label = type(dialog) == "table" and dialog.text or nil
    if type(label) == "table" and type(label.SetText) == "function" then
        label:SetText(text)
    end
end

-- No importable code: the copy box is claimed and left empty, and the dialog
-- and the chat say why instead of offering text that imports nowhere.
local function RefuseExplicitCopy(dialog, reason)
    local box = type(dialog) == "table" and dialog.editBox or nil
    if box then
        ClaimWireEditBox(box)
        box._nexusExplicitExportText = ""
        box:SetText("")
    end
    local text = TF("editor.error.export_unavailable",
        {reason = tostring(reason or T("editor.error.export_unavailable_default"))})
    ExportPrompt(dialog, text)
    print("|cffff6060Nexus:|r " .. text)
end

local function EndGuidedImport()
    if Nexus.GuidedSetupUI and Nexus.GuidedSetupUI.RouteEnded then
        Nexus.GuidedSetupUI.RouteEnded('import')
    end
end

local function LoadImportedWishlist(parsed, chosenName)
    -- A naming popup can outlive the editor window. A delayed Accept must
    -- never replace a Plan draft protected by workspace navigation; a guided
    -- import waiting on it comes back unfinished, as for its other refusals.
    if RefuseSuspendedDraftReplacement() then EndGuidedImport(); return false, "Plan draft suspended" end
    if parsed and parsed.needsRoleSelection then
        local opened = RolePicker.Begin(parsed.entries,{kind="import",name=TrimWishlistName(chosenName),class=parsed.class})
        if not opened then EndGuidedImport() end
        return opened
    end
    local ok, name, count, why =
        wishlistController.LoadImported(parsed, chosenName)
    if not ok then
        print("|cffff6060Nexus:|r " .. TF("editor.chat.import_failed",
            {reason = tostring(why and Nexus.UserText.Recognized(why) or T("editor.error.import_roles_unrepresentable"))}))
        EndGuidedImport()
        return false
    end
    SyncFulfilledDraftTargets()
    HideServerEchoUI()
    local renderer = RendererInstance()
    renderer.Prepare({attach=true, style=true, close=true})
    renderer.SetNameText(name)
    renderer.ShowFrame()
    if Nexus.GuidedSetupUI and Nexus.GuidedSetupUI.WatchEditor then
        Nexus.GuidedSetupUI.WatchEditor('import')
    end
    M.Refresh()
    local displayName = DisplayUntrusted(name, 1024, false) or T("editor.value.wishlist_fallback")
    -- One entry or several: the English chose "entry" or "entries" by count.
    print("|cff4dff80Nexus:|r " .. TF(count == 1 and "editor.chat.imported_draft_one"
        or "editor.chat.imported_draft_many", {count = N(count), name = displayName}))
    -- An opened draft, not a saved plan.
    GuideNote("draft", {origin = "import", name = name})
    return true
end

-- P1.4: for an explicit open/import action, default untagged plans to the
-- exact matching current permanent copies when the complete 79/6 split fits.
-- No source entries are dropped, and an already confirmed plan is not replaced.
-- Missing/mismatched evidence leaves a cancelable explicit fallback draft.
RolePicker = { visibleRows=10 }

function RolePicker.Hide(continuing)
    local restore = RolePicker.state and RolePicker.state.restoreEditor
    local wasImport = RolePicker.state and RolePicker.state.kind == "import"
    RolePicker.state=nil
    if RolePicker.frame then RolePicker.frame:Hide() end
    if restore and wishlistRenderer then wishlistRenderer.ShowFrame() end
    if wasImport and not continuing then EndGuidedImport() end
end

function RolePicker.Count()
    local total,locked=0,0
    for _,row in ipairs(RolePicker.state and RolePicker.state.rows or {}) do
        total=total+row.copies;locked=locked+row.selected
    end
    return total,locked
end

function RolePicker.Message(text)
    if RolePicker.state then RolePicker.state.message=tostring(text or "") end
    if RolePicker.frame then RolePicker.frame.message:SetText(text or "") end
end

function RolePicker.Render()
    local f,state=RolePicker.frame,RolePicker.state
    if not f or not state then return end
    local total,locked=RolePicker.Count()
    local pages=math.max(1,math.ceil(#state.rows/RolePicker.visibleRows))
    state.page=math.max(1,math.min(pages,state.page or 1))
    f.title:SetText(TF("editor.title.role_picker",
        {name=DisplayUntrusted(state.name,1024,false) or T("editor.value.wishlist_fallback")}))
    f.count:SetText(TF("editor.label.role_rolled_copies",{count=N(total-locked)}).."  |  "
        ..TF("editor.label.role_locked_targets",{count=N(locked)}).."  |  "
        ..TF("editor.label.role_total",{count=N(total)}))
    f.pageLabel:SetText(TF("editor.label.role_page",{page=N(state.page),pages=N(pages)}))
    if state.page>1 then f.prev:Enable() else f.prev:Disable() end
    if state.page<pages then f.next:Enable() else f.next:Disable() end
    if total-locked<=79 and total-locked>0 and locked<=6 then
        f.confirm:Enable()
    else f.confirm:Disable() end
    -- Help quotes this pair; both are reviewed keys, so they stay in one
    -- language together.
    f.confirm:SetText(state.assign and T("editor.button.confirm_locked_assign") or T("editor.button.confirm_locked_edit"))
    local qualityNames=QualityNames()
    for n,view in ipairs(f.rows) do
        local index=(state.page-1)*RolePicker.visibleRows+n
        local row=state.rows[index]
        view.index=index
        if row then
            view.label:SetText(TF("editor.label.role_row",{name=DisplayUntrusted(row.name,256,false) or tostring(row.id),
                quality=tostring(qualityNames[row.quality] or row.quality),copies=N(row.copies)}))
            view.count:SetText(TF("editor.label.role_row_locked",{count=N(row.selected)}))
            if row.selected>0 then view.minus:Enable() else view.minus:Disable() end
            if row.selected<row.copies and locked<6 then view.plus:Enable() else view.plus:Disable() end
            view.frame:Show()
        else view.frame:Hide() end
    end
    f.message:SetText(state.message or T("editor.status.role_default"))
end

function RolePicker.Adjust(index,delta)
    local state=RolePicker.state
    local row=state and state.rows[index]
    if not row then return end
    local _,locked=RolePicker.Count()
    if delta>0 and locked>=6 then return end
    row.selected=math.max(0,math.min(row.copies,row.selected+delta))
    state.message=nil
    state.usedCurrentLocks=nil
    RolePicker.Render()
end

function RolePicker.UseOwned(automatic)
    local state=RolePicker.state
    if not state then return end
    local locked=wishlistController.LockedProjection()
    if not locked or locked.synced~=true or type(locked.bySpell)~="table" then
        RolePicker.Message(T("editor.status.role_waiting_locked_list"))
        return
    end
    local catalog=wishlistController.CatalogProjection()
    local selected,remaining={},{}
    for id,copies in pairs(locked.bySpell) do
        id=tonumber(id)
        if not id or id<1 or id~=math.floor(id) or type(copies)~="number" or copies<1 or copies~=math.floor(copies) then
            RolePicker.Message(T("editor.status.role_locked_list_incomplete"))
            return false
        end
        remaining[id]=(remaining[id] or 0)+copies
    end
    local ownedTotal=0
    for _,copies in pairs(remaining) do ownedTotal=ownedTotal+copies end
    -- Held copies beyond the plan envelope are valid ownership, not incomplete
    -- data; the suggestion just cannot use them.
    if ownedTotal>6 then
        RolePicker.Message(T("editor.status.role_locked_over_six"))
        return false
    end
    local count=0
    for i,row in ipairs(state.rows) do
        local cat=catalog and catalog.rows and catalog.rows[row.id]
        local exactQuality=cat and tonumber(cat.quality)==row.quality
        local copies=exactQuality and math.min(row.copies,remaining[row.id] or 0) or 0
        selected[i]=copies;remaining[row.id]=(remaining[row.id] or 0)-copies
        count=count+copies
    end
    if count>6 then RolePicker.Message(T("editor.status.role_matching_over_six"));return end
    for i,row in ipairs(state.rows) do row.selected=selected[i] end
    state.usedCurrentLocks=automatic==true
    state.message=automatic==true
        and T("editor.status.role_using_current")
        or T("editor.status.role_suggested")
    RolePicker.Render()
    local total=RolePicker.Count()
    return count>0 and total-count>0 and total-count<=79 and count<=6
end

function RolePicker.Accept()
    local state=RolePicker.state
    if not state then return false end
    local total,locked=RolePicker.Count()
    if locked>6 or total-locked>79 or total-locked<1 then
        RolePicker.Message(T("editor.status.role_select_limit"))
        return false
    end
    local echoes,ordinary,lockedRows={},{},{}
    for _,row in ipairs(state.rows) do
        if row.copies-row.selected>0 then
            local e={spellId=row.id,quality=row.quality,stacks=row.copies-row.selected,locked=false}
            echoes[#echoes+1]=e;ordinary[#ordinary+1]=e
        end
        if row.selected>0 then
            local e={spellId=row.id,quality=row.quality,stacks=row.selected,locked=true}
            echoes[#echoes+1]=e;lockedRows[#lockedRows+1]=e
        end
    end
    local prepared,why=DraftModel.NormalizeCandidateEvidence(ordinary,lockedRows,
        {catalog=wishlistController.CatalogProjection(),lockedBySpell={}})
    if not prepared then RolePicker.Message(why and Nexus.UserText.Recognized(why) or T("editor.status.role_not_representable"));return false end
    if state.kind=="import" then
        local name,class=state.name,state.class
        RolePicker.Hide(true)
        return LoadImportedWishlist({entries=echoes,name=name,class=class},name)
    end
    if state.assign then
        -- One slots read. An unknown or missing read proves no target, so it
        -- refuses before roles are confirmed or anything is written; it is
        -- never taken as "no Saved Build" (first run). A known read is
        -- compared through the Saved Build Nexus selects, projected from this
        -- same read (0 = none): the authority the Journal captured
        -- state.activeSlot from. The raw native slot can be a Wishlist index
        -- and is not compared. state.activeSlot stays the destination; a
        -- different current selection refuses and never retargets it.
        local slots=Adapter and Adapter.Slots and Adapter.Slots()
        if type(slots)~="table" or slots.activeKnown==false then
            RolePicker.Message(T("editor.status.role_loadout_unavailable"))
            return false
        end
        if (wishlistController.SelectedSavedBuild(slots) or 0)~=state.activeSlot then
            RolePicker.Message(T("editor.status.role_loadout_changed"))
            return false
        end
    end
    local resolved,reason
    if Adapter and Adapter.ConfirmWishlistRoles then
        resolved,reason=Adapter.ConfirmWishlistRoles(state.candidate,echoes,
            state.usedCurrentLocks and "current-locks" or "user-confirmed")
    end
    if not resolved then RolePicker.Message(reason and Nexus.UserText.Recognized(reason) or T("editor.status.role_not_preserved"));return false end
    local loadoutSlot=state.loadoutSlot
    if state.assign then
        local ok,err
        if state.activeSlot==0 then ok,err=Adapter.SetFirstRunWishlist(resolved.slot,resolved)
        else ok,err=Adapter.SetLoadoutWishlist(state.activeSlot,resolved.slot,resolved) end
        GuideNote("assign",{origin="rolepicker",destination=state.activeSlot==0 and "first" or state.activeSlot,
            ok=ok==true,reason=err,key=resolved.key,slot=resolved.slot,name=resolved.name,guide=state.guide})
        if not ok then
            RolePicker.Message(TF("editor.status.role_assign_incomplete",
                {reason=tostring(err and Nexus.UserText.Recognized(err) or T("editor.value.reason_unavailable"))}))
            return false
        end
        loadoutSlot=state.activeSlot>0 and state.activeSlot or nil
    end
    local name,usedCurrentLocks=resolved.name,state.usedCurrentLocks
    resolved.loadoutName=state.candidate.loadoutName
    RolePicker.Hide()
    local opened=M.OpenForWishlist(resolved,loadoutSlot)
    if opened then
        print("|cff4dff80Nexus:|r " .. TF(usedCurrentLocks and "editor.chat.role_using_current_for"
            or "editor.chat.role_confirmed_for",
            {name=DisplayUntrusted(name,1024,false) or T("editor.value.wishlist_fallback")}))
    end
    if Nexus.JournalTab and Nexus.JournalTab.RefreshAssociations then Nexus.JournalTab.RefreshAssociations() end
    if Nexus.Panel and Nexus.Panel.Refresh then Nexus.Panel.Refresh() end
    return opened
end

function RolePicker.Ensure()
    if RolePicker.frame then return RolePicker.frame end
    local f=CreateFrame("Frame","NexusWishlistRolePicker",UIParent)
    RolePicker.frame=f
    f:Hide() -- before OnHide is installed; do not discard the new role draft
    f:SetSize(610,510);f:SetPoint("CENTER",UIParent,"CENTER",0,0)
    f:SetFrameStrata("FULLSCREEN_DIALOG");f:SetFrameLevel(40)
    f:SetClampedToScreen(true);f:EnableMouse(true);f:SetToplevel(true)
    f:SetScript("OnHide",function()
        local restore=RolePicker.state and RolePicker.state.restoreEditor
        local wasImport=RolePicker.state and RolePicker.state.kind=="import"
        RolePicker.state=nil
        if restore and wishlistRenderer then wishlistRenderer.ShowFrame() end
        if wasImport then EndGuidedImport() end
    end)
    UISpecialFrames[#UISpecialFrames+1]="NexusWishlistRolePicker"
    local p=f
    p:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=32,
        insets={left=10,right=10,top=10,bottom=10}})
    p:SetBackdropColor(0.035,0.035,0.045,1);p:EnableMouse(true)
    -- A solid background, not the semi-transparent dialog tile. No editor
    -- controls or text should show through this interactive fallback.
    local bg=p:CreateTexture(nil,"BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetPoint("TOPLEFT",10,-10);bg:SetPoint("BOTTOMRIGHT",-10,10)
    bg:SetVertexColor(0.025,0.025,0.035,1)
    f.opaqueBackground=bg
    local function label(font,x,y,w)
        local t=p:CreateFontString(nil,"OVERLAY",font)
        t:SetPoint("TOPLEFT",p,"TOPLEFT",x,y);t:SetWidth(w);t:SetJustifyH("LEFT")
        return t
    end
    f.title=label("GameFontNormal",20,-18,570)
    local help=label("GameFontHighlightSmall",20,-44,570)
    help:SetHeight(40)
    help:SetText(T("editor.body.role_help_targets").."\n"..T("editor.body.role_help_plan_only"))
    f.count=label("GameFontNormal",20,-83,570)
    f.rows={}
    for n=1,RolePicker.visibleRows do
        local rf=CreateFrame("Frame",nil,p);rf:SetSize(570,28);rf:SetPoint("TOPLEFT",20,-109-(n-1)*28)
        rf:SetFrameStrata("FULLSCREEN_DIALOG");rf:SetFrameLevel(41)
        local row={frame=rf};f.rows[n]=row
        row.label=rf:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        row.label:SetPoint("LEFT",0,0);row.label:SetWidth(390);row.label:SetJustifyH("LEFT")
        -- One line per row; a shortened Echo name is complete in the row tooltip.
        if Nexus.LayoutMetrics then rf:EnableMouse(true);Nexus.LayoutMetrics.OneLineLabel(row.label,rf,28) end
        row.count=rf:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        row.count:SetPoint("RIGHT",-32,0);row.count:SetWidth(66)
        row.minus=CreateFrame("Button","NexusWishlistRoleMinus"..n,rf,"UIPanelButtonTemplate")
        row.minus:SetFrameStrata("FULLSCREEN_DIALOG");row.minus:SetFrameLevel(42);row.minus:EnableMouse(true)
        row.minus:SetSize(26,23);row.minus:SetPoint("RIGHT",-104,0);row.minus:SetText("-")
        row.plus=CreateFrame("Button","NexusWishlistRolePlus"..n,rf,"UIPanelButtonTemplate")
        row.plus:SetFrameStrata("FULLSCREEN_DIALOG");row.plus:SetFrameLevel(42);row.plus:EnableMouse(true)
        row.plus:SetSize(26,23);row.plus:SetPoint("RIGHT",0,0);row.plus:SetText("+")
        row.minus:SetScript("OnClick",function() RolePicker.Adjust(row.index,-1) end)
        row.plus:SetScript("OnClick",function() RolePicker.Adjust(row.index,1) end)
    end
    local function button(name,text,x,y,w,fn)
        local b=CreateFrame("Button",name,p,"UIPanelButtonTemplate")
        b:SetFrameStrata("FULLSCREEN_DIALOG");b:SetFrameLevel(42);b:EnableMouse(true)
        b:SetSize(w,24);b:SetPoint("TOPLEFT",x,y);b:SetText(text);b:SetScript("OnClick",fn);return b
    end
    f.prev=button("NexusWishlistRolePrevious",T("editor.button.previous"),20,-394,82,function()
        if RolePicker.state then RolePicker.state.page=RolePicker.state.page-1;RolePicker.Render() end end)
    f.next=button("NexusWishlistRoleNext",T("editor.button.next"),188,-394,70,function()
        if RolePicker.state then RolePicker.state.page=RolePicker.state.page+1;RolePicker.Render() end end)
    f.pageLabel=label("GameFontHighlightSmall",108,-401,78)
    f.owned=button("NexusWishlistRoleUseOwned",T("editor.button.role_suggest"),318,-394,270,function() RolePicker.UseOwned(false) end)
    -- Two lines of a 16 px face (the longest message wraps to two at 570 px).
    f.message=label("GameFontHighlightSmall",20,-430,570)
    f.message:SetHeight(44);f.message:SetJustifyV("TOP")
    f.confirm=button("NexusWishlistRoleConfirm",T("editor.button.confirm_locked_edit"),210,-476,278,RolePicker.Accept)
    f.cancel=button("NexusWishlistRoleCancel",T("editor.button.cancel"),498,-476,90,function()
        local pending=RolePicker.state
        if pending and pending.assign then
            GuideNote("assign",{origin="rolepicker",destination=pending.activeSlot==0 and "first" or pending.activeSlot,
                ok=false,cancelled=true,reason="cancelled",guide=pending.guide})
        end
        RolePicker.Hide()
    end)
    f:Hide()
    return f
end

function RolePicker.Begin(entries,context)
    local candidate={echoes=entries,lockEvidenceStatus="unavailable"}
    local evidence=Adapter and Adapter.WishlistEvidenceState and Adapter.WishlistEvidenceState(candidate)
    if evidence~="evidence-pending" and evidence~="actionable" then
        print("|cffff6060Nexus:|r " .. T("editor.chat.role_contents_invalid"))
        return false
    end
    local rows,byKey={},{}
    local catalog=wishlistController.CatalogProjection()
    for _,e in ipairs(entries) do
        local id,q,copies=tonumber(e.spellId),tonumber(e.quality or 0),tonumber(e.stacks)
        local cat=catalog and catalog.rows and catalog.rows[id]
        if q>255 or (cat and tonumber(cat.quality)~=q) then
            print("|cffff6060Nexus:|r " .. T("editor.chat.role_quality_mismatch"))
            return false
        end
        local key=tostring(id)..":"..tostring(q)
        local row=byKey[key]
        if not row then
            row={id=id,quality=q,copies=0,selected=0,name=cat and cat.name or TF("editor.value.echo_id_fallback",{id=tostring(id)})}
            byKey[key]=row;rows[#rows+1]=row
        end
        row.copies=row.copies+copies
        if e.locked==true then row.selected=row.selected+copies end
    end
    table.sort(rows,function(a,b) if a.id~=b.id then return a.id<b.id end;return a.quality<b.quality end)
    wishlistController.CancelApply()
    -- No modal frame is constructed on the normal automatic-current-lock path.
    local state={kind=context.kind,name=context.name,rows=rows,page=1,
        class=context.class,loadoutSlot=context.loadoutSlot,
        assign=context.assign,activeSlot=context.activeSlot,guide=context.guide}
    if context.candidate then
        state.candidate={slot=context.candidate.slot,name=context.candidate.name,
            key=context.candidate.key,lockEvidenceStatus="unavailable",echoes={},
            loadoutName=context.candidate.loadoutName}
        for i,e in ipairs(entries) do state.candidate.echoes[i]={spellId=e.spellId,
            quality=e.quality,stacks=e.stacks,locked=nil} end
    end
    RolePicker.state=state
    local settings=Nexus.Store and Nexus.Store.Settings and Nexus.Store.Settings()
    local preferCurrent=not settings or settings.useCurrentLocksForUntagged~=false
    if preferCurrent and RolePicker.UseOwned(true) then
        local opened=RolePicker.Accept()
        if opened then return true end
        -- A real identity/storage refusal is not bypassed. Show the same
        -- reason in the usable fallback rather than looping or dropping data.
    end
    if not RolePicker.state then return false end
    local f=RolePicker.Ensure()
    if wishlistRenderer then
        state.restoreEditor=wishlistRenderer.IsShown()
        if wishlistRenderer.DismissTransients then wishlistRenderer.DismissTransients() end
        wishlistRenderer.Hide()
    end
    local journalPicker=_G.NexusWishlistOnlyPicker
    if journalPicker then journalPicker:Hide() end
    RolePicker.Render();f:Show()
    return true
end

-- Explicit assignment clicks use this same editor flow; unresolved evidence
-- never silently becomes action authority simply because a button was pressed.
function M.UnresolvedRoleHint()
    local settings=Nexus.Store and Nexus.Store.Settings and Nexus.Store.Settings()
    return T(settings and settings.useCurrentLocksForUntagged==false
        and "editor.status.hint_choose_locked_targets" or "editor.status.hint_use_current_locks")
end

function M.ResolveAndAssignWishlist(candidate, activeSlot, guide)
    -- guide (optional, passive): the guided setup origin its caller took as
    -- the player started this operation; it is only carried to the result.
    local resolved,status,_,why=Adapter.ResolveWishlistEvidence(candidate)
    if status=="evidence-pending" then
        return RolePicker.Begin(resolved.echoes,{kind="existing",name=resolved.name,
            candidate=resolved,loadoutSlot=tonumber(activeSlot),assign=true,
            activeSlot=tonumber(activeSlot) or 0,guide=guide})
    end
    if status~="actionable" then return false,why end
    local first=tonumber(activeSlot)==0
    local ok,err
    if first then ok,err=Adapter.SetFirstRunWishlist(resolved.slot,resolved)
    else ok,err=Adapter.SetLoadoutWishlist(activeSlot,resolved.slot,resolved) end
    GuideNote("assign",{origin="editor",destination=first and "first" or activeSlot,ok=ok==true,
        reason=err,key=resolved.key,slot=resolved.slot,name=resolved.name,guide=guide})
    return ok,err
end

-- The editor's Wishlist candidates (when nothing is tracked) assign the clicked
-- one to the active Saved Build. With Auto selected and a numbered Saved Build
-- with Echoes as that target, the Journal's Auto-ON confirmation names it
-- first (UX-05); `perform` (the click's own role choice and assignment) runs
-- only after Assign, and only while the active Saved Build is still the one
-- named. Cancel changes nothing; Auto is never changed here. Auto OFF, the
-- first-run target and an empty or unknown Saved Build keep their behaviour.
-- Returns what the consent call returned, or what `perform` returned.
function M.ConfirmCandidateAssignment(candidate, perform)
    local adapter = Adapter or Nexus.GameAdapter
    local slots = adapter and adapter.Slots and adapter.Slots()
    local active = type(slots) == "table" and tonumber(slots.activeSlot) or 0
    local maxSlots = type(slots) == "table" and (tonumber(slots.maxSlots) or 5) or 5
    local row = type(slots) == "table" and type(slots.bySlot) == "table" and slots.bySlot[active] or nil
    local numbered = active >= 1 and active <= maxSlots and type(row) == "table"
        and type(row.echoes) == "table" and #row.echoes > 0
    if not numbered then return perform() end
    local journal = Nexus.JournalTab
    if not (journal and type(journal.AssignWithConsent) == "function") then
        local stats = type(Nexus.RecomputeStats) == "function" and Nexus.RecomputeStats() or nil
        if type(stats) == "table" and stats.autoEnabled == true then
            print("|cffff6060Nexus:|r " .. T("editor.chat.assign_consent_unavailable"))
            return nil, "consent_unavailable"
        end
        return perform()
    end
    local name = DisplayUntrusted(candidate and candidate.name, 1024, false)
    if not name or name == "" then
        name = TF("editor.value.slot_fallback", {slot = tostring(candidate and candidate.slot or "?")})
    end
    local label = DisplayUntrusted(row.name, 1024, false)
    if not label or label == "" then label = tostring(active) end
    return journal.AssignWithConsent(name, TF("editor.value.saved_build_quoted", {name = label}), true, function()
        local now = adapter and adapter.Slots and adapter.Slots()
        if type(now) ~= "table" or tonumber(now.activeSlot) ~= active then
            print("|cffff6060Nexus:|r " .. T("editor.chat.assign_saved_build_changed"))
            return
        end
        return perform()
    end)
end

function M.ImportEBH1String(text, chosenName)
    if RefuseSuspendedDraftReplacement() then EndGuidedImport(); return false, "Plan draft suspended" end
    local Codec = Nexus and Nexus.Codec
    if not (Codec and Codec.DecodeEBH1) then
        print("|cffff6060Nexus:|r " .. T("editor.chat.import_codec_unavailable"))
        EndGuidedImport()
        return
    end
    local parsed = Codec.DecodeEBH1(text, true)
    if not parsed or #parsed.entries == 0 then
        print("|cffff6060Nexus:|r " .. T("editor.chat.import_parse_failed"))
        EndGuidedImport()
        return
    end

    local name = TrimWishlistName(chosenName)
    if name ~= "" then
        LoadImportedWishlist(parsed, name)
        return
    end
    local suggested = TrimWishlistName(parsed.name)
    if suggested == "" then suggested = "Imported Wishlist" end
    local displaySuggested = DisplayUntrusted(suggested, 1024, false)
        or "Imported Wishlist"
    StaticPopup_Show("NEXUS_NAME_IMPORTED_WISHLIST",
        displaySuggested, nil, parsed)
end

-- The import field's own limit, for another field that takes the same code
-- (the guided setup's paste field).
M.IMPORT_MAX_LETTERS = IMPORT_MAX_LETTERS

-- A read-only check of a pasted EBH1 code through the same decoder the import
-- uses (ImportEBH1String). It reads the text and nothing else: no draft, no
-- popup, no save, no assignment and no receipt. A code that fills the field's
-- whole limit may have been cut by it, so it is refused as possibly cut off.
-- The decoder checks the code's form and envelope only; the editor checks its
-- Echoes again when the draft is opened. Returns {state=...}:
--   "empty"       nothing was pasted
--   "unavailable" the decoder is not loaded
--   "rejected"    reason "long" (limit = the field's letters) or "invalid"
--   "accepted"    name (trimmed, or nil), entries, rolled and locked copies,
--                 needsRoles (more than 79 rolled copies: the editor asks for
--                 locked targets first) and suspended (an unsaved Plan draft in
--                 another workspace refuses the import until it is resolved)
function M.CheckImportCode(text)
    if type(text) ~= "string" or not text:find("%S") then return {state = "empty"} end
    if #(text:gsub("[\128-\191]", "")) >= IMPORT_MAX_LETTERS then
        return {state = "rejected", reason = "long", limit = IMPORT_MAX_LETTERS}
    end
    local Codec = Nexus and Nexus.Codec
    if not (Codec and type(Codec.DecodeEBH1) == "function") then return {state = "unavailable"} end
    local ok, parsed = pcall(Codec.DecodeEBH1, text, true)
    if not ok or type(parsed) ~= "table" or type(parsed.entries) ~= "table" or #parsed.entries == 0 then
        return {state = "rejected", reason = "invalid"}
    end
    local rolled, locked = 0, 0
    for _, e in ipairs(parsed.entries) do
        local copies = tonumber(e.stacks) or 0
        if e.locked then locked = locked + copies else rolled = rolled + copies end
    end
    local name = TrimWishlistName(parsed.name)
    return {state = "accepted", name = name ~= "" and name or nil, entries = #parsed.entries,
        rolled = rolled, locked = locked, needsRoles = parsed.needsRoleSelection == true,
        suspended = workspaceResume ~= nil}
end

StaticPopupDialogs["NEXUS_EXPORT_WISHLIST"] = LocalizedDialog({
    hasEditBox = true,
    editBoxWidth = 350,
    maxLetters = IMPORT_MAX_LETTERS,
    OnShow = function(self)
        local code, why = ExportEBH1String()
        if not code then
            RefuseExplicitCopy(self, why)
            return
        end
        SetExplicitCopyText(self.editBox, code)
        if why then
            -- What the code leaves out (current locked Echoes above the plan's
            -- six locked target copies).
            ExportPrompt(self, TF("editor.popup.export_intro_note", {note = why})
                .. "\n" .. T("editor.popup.export_copy_hint"))
            print("|cffff9040Nexus:|r " .. why .. ".")
        end
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}, {
    text = function()
        return PopupText(T("editor.popup.export_intro") .. "\n" .. T("editor.popup.export_copy_hint"))
    end,
    button1 = function() return T("editor.button.close") end,
})

StaticPopupDialogs["NEXUS_NAME_IMPORTED_WISHLIST"] = LocalizedDialog({
    hasEditBox = true,
    editBoxWidth = 300,
    OnShow = function(self)
        local suggested = TrimWishlistName(self.data and self.data.name)
        if suggested == "" then suggested = "Imported Wishlist" end
        ConfigureSafeNameEditBox(self.editBox)
        self.editBox:_NexusSetRawText(suggested)
        self.editBox:SetFocus()
        self.editBox:HighlightText()
    end,
    OnAccept = function(self, parsed)
        local typed = tostring(self.editBox and self.editBox._NexusRawText
                and self.editBox:_NexusRawText()
                or (self.editBox and self.editBox:GetText()) or "")
        local name = TrimWishlistName(typed)
        -- Said only when something really was dropped, so the message cannot
        -- outlive the rule that produces it.
        if name ~= "" and name ~= typed:gsub("^%s+", ""):gsub("%s+$", "") then
            -- The dropped character itself is code-owned (a reviewed text
            -- cannot hold it), so it fills a slot of the sentence.
            print("|cffff6060Nexus:|r " .. TF("editor.chat.import_pipe_dropped",
                {character = "|", name = name}))
        end
        if name == "" then
            print("|cffff6060Nexus:|r " .. T("editor.chat.import_name_required"))
            EndGuidedImport()
            return
        end
        LoadImportedWishlist(parsed, name)
    end,
    OnCancel = function(self)
        if self and self.Hide then self:Hide() end
        EndGuidedImport()
    end,
    EditBoxOnEnterPressed = function(self)
        self:GetParent().button1:Click()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide(); EndGuidedImport() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}, {
    text = function() return PopupText(T("editor.popup.name_import_prompt")) .. "\n%s" end,
    button1 = function() return T("editor.button.open_imported_draft") end,
    button2 = CancelLabel,
})

StaticPopupDialogs["NEXUS_IMPORT_WISHLIST"] = LocalizedDialog({
    hasEditBox = true,
    editBoxWidth = 350,
    maxLetters = IMPORT_MAX_LETTERS,
    OnShow = function(self)
        ConfigureImportEditBox(self and self.editBox)
        if self and self.editBox and self.editBox.SetFocus then
            self.editBox:SetFocus()
        end
    end,
    OnAccept = function(self)
        -- Explicit EBH1 input is a lossless wire value, not ordinary display.
        -- The field was claimed by OnShow, so its text is the pasted bytes.
        M.ImportEBH1String(self and self.editBox and self.editBox:GetText())
    end,
    OnCancel = function(self)
        if self and self.Hide then self:Hide() end
        EndGuidedImport()
    end,
    EditBoxOnEnterPressed = function(self)
        self:GetParent().button1:Click()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
        EndGuidedImport()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}, {
    text = function()
        return PopupText(T("editor.popup.import_prompt") .. "\n" .. T("editor.popup.import_new_draft_note"))
    end,
    button1 = function() return T("editor.button.continue") end,
    button2 = CancelLabel,
})

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

-- Where Display Settings opens relative to the editor (pure; the renderer's
-- DisplayPopupPlacement).
function M.DisplayPopupPlacement(spec)
    return RendererInstance().DisplayPopupPlacement(spec)
end

function M.Init(adapter, model)
    Adapter = adapter
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

StaticPopupDialogs["NEXUS_FLEXIBLE_PLAN_REPLACE"] = LocalizedDialog({
    -- Accepting installs through the controller's single-use intent; its new
    -- draft cancels the current Save confirmation and any confirmed Save waiting
    -- to retry (WishlistController CancelApply). The consent says so, and that
    -- Cancel keeps both.
    -- OnAccept returns nothing, like the other Nexus confirmations. Its data
    -- is one owned, single-use request. An install attempt (installed or
    -- refused) or its own Cancel retires it; a newer request passes the older
    -- one as StaticPopup_Hide data, so only that popup is asked to hide. A
    -- late or replayed old Accept or Cancel is rejected by request identity
    -- alone: it installs nothing and asks no popup to hide, so a newer
    -- replacement and other dialogs such as Save are kept. Popup lifetime
    -- is modelled only by the offline synthetic host of the handoff fixture:
    -- a true OnAccept return keeps a dialog shown; nil or false lets the
    -- click hide it. No versioned client or FrameXML export backs that model,
    -- so native return handling, pooling, reuse and timing are NOT_RUN.
    OnAccept = function(_, request) if request then request.Install() end end,
    OnCancel = function(_, request) if request then request.Cancel() end end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}, {
    text = function()
        return PopupText(T("editor.popup.flex_replace_question") .. "\n"
            .. T("editor.popup.flex_replace_consequence"))
    end,
    button1 = function() return T("editor.button.open_new_draft") end,
    button2 = CancelLabel,
})

function M.OpenFlexiblePlanChooser()
    if RefuseSuspendedDraftReplacement() then return false, "Plan draft suspended" end
    if not flexiblePlanChooser then
        flexiblePlanChooser = Nexus.FlexiblePlanChooser.New({
            catalog=wishlistController.CatalogProjection,
            -- #151: the local pool owner; the chooser reads it only on first Show
            -- and explicit Save/Load (no automatic Save or Load).
            persistence=(Nexus.FlexiblePlanStore and Nexus.FlexiblePlanStore.New
                and Nexus.FlexiblePlanStore.New({store=Nexus.Store})) or nil,
            openDraft=function(draft, alternatives, planCurrent, installed, refuse)
                if workspaceResume then return refuse("EDITOR_CHANGED") end
                local renderer = RendererInstance()
                local name = renderer.NameText()
                local intent, why = wishlistController.PrepareNewExactDraft(draft, alternatives)
                if not intent then return refuse(why) end
                local request, former = {}, flexiblePlanRequest
                flexiblePlanRequest = request
                -- This request supersedes an older one, whether it asks again or
                -- installs directly. The older popup is retired by its own request
                -- identity, so no newer replacement or other dialog is dismissed.
                if former then StaticPopup_Hide("NEXUS_FLEXIBLE_PLAN_REPLACE", former) end
                -- The replacement popup can be accepted while the chooser is hidden:
                -- a current request's refusal shows the chooser (pool, choice and
                -- pending input kept) and then states the same reason in it.
                local function RevealRefusal(code)
                    flexiblePlanChooser.Show()
                    return refuse(code)
                end
                local function Install()
                    if flexiblePlanRequest ~= request then return refuse("EDITOR_CHANGED") end
                    -- Single use: the attempt retires the request before any check. A
                    -- refused request therefore cannot install when the former name,
                    -- count or context is restored and its old callback is replayed.
                    flexiblePlanRequest = nil
                    -- A native popup may deliver Accept after its Plan window was
                    -- suspended. Do not reveal the chooser over another workspace.
                    if workspaceResume then return refuse("EDITOR_CHANGED") end
                    local current, countReason = planCurrent()
                    if not current then return RevealRefusal(countReason or "PLAN_CHANGED") end
                    if renderer.NameText() ~= name then return RevealRefusal("EDITOR_CHANGED") end
                    local ok, reason = intent.Install()
                    if not ok then return RevealRefusal(reason) end
                    RolePicker.Hide()
                    SyncFulfilledDraftTargets()
                    renderer.Prepare({attach=true, style=true, close=true})
                    renderer.SetNameText("")
                    HideServerEchoUI()
                    renderer.ShowFrame()
                    installed()
                    M.Refresh()
                    return true
                end
                request.Install = Install
                request.Cancel = function()
                    if flexiblePlanRequest == request then flexiblePlanRequest = nil end
                end
                if intent.replaces or name ~= "" then
                    StaticPopup_Show("NEXUS_FLEXIBLE_PLAN_REPLACE",nil,nil,request)
                    return true
                end
                return Install()
            end,
        })
    end
    flexiblePlanChooser.Show()
end

function M.OpenForCandidate(candidate)
    if RefuseSuspendedDraftReplacement() then return false, "Plan draft suspended" end
    RolePicker.Hide()
    local name, reason = wishlistController.BeginCandidate(candidate)
    if name == nil then
        SyncFulfilledDraftTargets()
        return false, reason
    end
    workspaceResume = nil -- an accepted explicit Copy replaces the old draft
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
    if RefuseSuspendedDraftReplacement() then return false, "Plan draft suspended" end
    -- The record the player selected (a Journal row, an assignment, a confirmed
    -- role choice): its name and content as the server slot showed them when it
    -- was built. Taken before any resolution, so the controller compares the
    -- slot service with the selection, never with a record re-read from it.
    local selectedToken = Adapter and Adapter.ServerWishlistTokenFor
        and type(wishlist) == "table" and tonumber(wishlist.slot)
        and Adapter.ServerWishlistTokenFor(tostring(wishlist.name or ""), wishlist.echoes) or nil
    if Adapter and Adapter.ResolveWishlistEvidence then
        local resolved,status=Adapter.ResolveWishlistEvidence(wishlist)
        if status=="evidence-pending" and type(resolved)=="table" then
            return RolePicker.Begin(resolved.echoes,{kind="existing",name=resolved.name,
                candidate=resolved,loadoutSlot=loadoutSlot})
        end
        if status=="actionable" then wishlist=resolved end
    end
    RolePicker.Hide()
    if not wishlistController.BeginWishlist(wishlist, loadoutSlot, selectedToken) then
        SyncFulfilledDraftTargets()
        return false
    end
    workspaceResume = nil -- an accepted explicit open chooses a new draft
    SyncFulfilledDraftTargets()
    local renderer = RendererInstance()
    -- This can be the first editor entry after reload. Install the same menu
    -- hide/restore hooks as Show/NewWishlist before suppressing the main HUD.
    renderer.Prepare({attach=true})
    HideServerEchoUI()
    renderer.Prepare({close=true})
    renderer.ShowFrame()
    M.Refresh()
    return true
end

function M.NewWishlist()
    if RefuseSuspendedDraftReplacement() then return false, "Plan draft suspended" end
    workspaceResume = nil
    RolePicker.Hide()
    HideServerEchoUI()
    wishlistController.BeginNewWishlist()
    SyncFulfilledDraftTargets()
    local renderer = RendererInstance()
    renderer.Prepare({attach=true, style=true, close=true})
    renderer.SetNameText("")
    renderer.ShowFrame()
    M.Refresh()
end

local function WorkspaceContext()
    local guid = type(UnitGUID) == "function" and UnitGUID("player") or nil
    local slots = Adapter and type(Adapter.Slots) == "function" and Adapter.Slots() or nil
    if type(guid) ~= "string" or guid == ""
        or type(slots) ~= "table" or slots.activeKnown == false then
        return nil
    end
    return {
        guid = guid,
        nativeSlot = tonumber(slots.activeSlot) or 0,
        selectedSavedBuild = wishlistController.SelectedSavedBuild(slots) or 0,
        maxSlots = tonumber(slots.maxSlots) or 0,
    }
end

local function SameWorkspaceContext(left, right)
    return left and right and left.guid == right.guid
        and left.nativeSlot == right.nativeSlot
        and left.selectedSavedBuild == right.selectedSavedBuild
        and left.maxSlots == right.maxSlots
end

local function SaveConfirmationOpen()
    -- StaticPopup_Visible is part of the native FrameXML. Minimal offline
    -- hosts that omit it also omit real interactive popup visibility.
    if type(StaticPopup_Visible) ~= "function" then return false end
    return StaticPopup_Visible("WISHLISTREALIZER_UPDATE_WISHLIST")
        or StaticPopup_Visible("WISHLISTREALIZER_CREATE_WISHLIST")
end

function M.SuspendForWorkspace()
    local renderer = RendererInstance()
    if not renderer.IsShown() then return false, "Plan is not open" end
    local confirmation = SaveConfirmationOpen()
    if confirmation or M.IsApplyPending() then
        return false, "finish or cancel the pending Save before leaving Plan"
    end
    local chooser = _G.NexusFlexiblePlanChooser
    if flexiblePlanRequest or (chooser and chooser.IsShown and chooser:IsShown()) then
        return false, "close Plan alternatives or finish its replacement before leaving Plan"
    end
    if type(StaticPopup_Visible) == "function"
        and StaticPopup_Visible("NEXUS_NAME_IMPORTED_WISHLIST") then
        return false, "finish or cancel the imported Wishlist name before leaving Plan"
    end
    local context = WorkspaceContext()
    if not context then return false, "Saved Build context is not known" end
    workspaceResume = context
    return true
end

function M.CancelWorkspaceSuspend()
    workspaceResume = nil
end

-- A read-only fact for the guided setup (ui/GuidedSetup.lua): nil while no
-- unsaved Plan draft is set aside in another workspace, else whether the
-- character and Saved Build it was set aside under are still the current ones
-- (sameContext: ResumeWorkspaceDraft reopens it as it is; otherwise it asks
-- before anything is discarded). It prints, shows, resumes and changes nothing.
function M.SuspendedPlanDraft()
    if not workspaceResume then return nil end
    return {sameContext = SameWorkspaceContext(workspaceResume, WorkspaceContext()) and true or false}
end

-- The caller of the latest changed-context question that asked to hear about
-- its Discard draft (the guided setup steps aside for the Plan it opens).
-- Every ask replaces it and any hide of the question drops it, so an earlier
-- caller never answers for a later question. Keep draft calls nothing.
local contextChangedOpened

StaticPopupDialogs["NEXUS_WORKSPACE_CONTEXT_CHANGED"] = LocalizedDialog({
    OnAccept = function()
        local opened = contextChangedOpened
        contextChangedOpened = nil
        workspaceResume = nil
        M.Show()
        if type(opened) == "function" then pcall(opened) end
    end,
    OnCancel = function() contextChangedOpened = nil end,
    OnHide = function() contextChangedOpened = nil end,
}, {
    text = function() return PopupText(T("editor.popup.context_changed")) end,
    button1 = function() return T("editor.button.discard_draft") end,
    button2 = function() return T("editor.button.keep_draft") end,
})

-- onDiscardOpened (optional): called once, after Plan was shown for the
-- current context, if the player answers this very changed-context question
-- with Discard draft. Nothing else calls it.
function M.ResumeWorkspaceDraft(onDiscardOpened)
    if not workspaceResume then return false, "no workspace draft" end
    if not SameWorkspaceContext(workspaceResume, WorkspaceContext()) then
        contextChangedOpened = type(onDiscardOpened) == "function" and onDiscardOpened or nil
        if type(StaticPopup_Show) == "function"
            and not (type(StaticPopup_Visible) == "function"
                and StaticPopup_Visible("NEXUS_WORKSPACE_CONTEXT_CHANGED")) then
            StaticPopup_Show("NEXUS_WORKSPACE_CONTEXT_CHANGED")
        end
        return false, "context changed; choose whether to discard the draft"
    end
    if M.IsApplyPending() then
        return false, "a Save is pending; return after it settles"
    end
    local renderer = RendererInstance()
    renderer.Prepare({attach=true, style=true, close=true})
    renderer.ShowFrame()
    M.Refresh()
    workspaceResume = nil
    return true
end

function M.Show()
    if workspaceResume then return M.ResumeWorkspaceDraft() end
    local slots=Adapter and Adapter.Slots and Adapter.Slots()
    -- The selected Saved Build, never a native Wishlist index: an association
    -- stored under one stays stored but is not opened as a loadout here.
    local active=wishlistController.SelectedSavedBuild(slots) or 0
    if active>0 and Adapter.GetLoadoutWishlistState then
        local candidate,status=Adapter.GetLoadoutWishlistState(active)
        if status=="evidence-pending" and candidate then return M.OpenForWishlist(candidate,active) end
    end
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
