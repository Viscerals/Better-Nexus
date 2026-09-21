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

local function DisplayUntrusted(value, maxBytes, allowEmpty, allowLineBreaks)
    local identity = Nexus and Nexus.Identity
    if not (identity and type(identity.DisplaySafeText) == "function") then
        return nil
    end
    return identity.DisplaySafeText(
        value, maxBytes, allowEmpty, allowLineBreaks)
end

local function ConfigureSafeNameEditBox(box)
    if not box or box._nexusSafeNameOwner then return end
    box._nexusSafeNameOwner = true
    local priorChanged = box:GetScript("OnTextChanged")
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

local function SetExplicitCopyText(box, value)
    -- EBH1 is an explicit copy/paste wire boundary. The selected bytes must be
    -- retained exactly, but an EditBox is still a WoW rich-text surface. Keep
    -- the exact wire value separate and select its reversible inert projection.
    if not box then return end
    box._nexusExplicitExportText = tostring(value or "")
    box:SetText(DisplayUntrusted(box._nexusExplicitExportText,
        #box._nexusExplicitExportText, true, true) or "")
end

local Model, Adapter
local RolePicker
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
    notify = function(message) print(Nexus.UserText and Nexus.UserText.Message(message) or message) end,
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
        print("|cffff6060Nexus:|r Build Library unavailable")
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
    text = "Save %d/79 rolled copies to '%s'?\nUpdates this server Wishlist. Planned permanent targets are saved separately.",
    button1 = "Save Changes",
    button2 = "Cancel",
    OnCancel = function(_, data) wishlistController.CancelApply(data) end,
    OnAccept = function(self, data)
        AcceptApply(data)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["WISHLISTREALIZER_CREATE_WISHLIST"] = {
    text = "Create '%s' with %d/79 rolled copies?\nSaves a new server Wishlist and assigns it to the loadout shown in the editor after successful saving. Existing Wishlists are not overwritten.",
    button1 = "Create Wishlist",
    button2 = "Cancel",
    OnCancel = function(_, data) wishlistController.CancelApply(data) end,
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
    if parsed and parsed.needsRoleSelection then
        return RolePicker.Begin(parsed.entries,{kind="import",name=TrimWishlistName(chosenName),class=parsed.class})
    end
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
    local displayName = DisplayUntrusted(name, 1024, false) or "Wishlist"
    print(string.format(
        "|cff4dff80Nexus:|r imported %d Echo entr%s as new wishlist '%s'. Review this draft; Create Wishlist saves it. Assignment follows the loadout shown by the editor.",
        count, count == 1 and "y" or "ies", displayName))
    return true
end

-- P1.4: for an explicit open/import action, default untagged plans to the
-- exact matching current permanent copies when the complete 79/6 split fits.
-- No source entries are dropped, and an already confirmed plan is not replaced.
-- Missing/mismatched evidence leaves a cancelable explicit fallback draft.
RolePicker = { visibleRows=10 }

function RolePicker.Hide()
    local restore = RolePicker.state and RolePicker.state.restoreEditor
    RolePicker.state=nil
    if RolePicker.frame then RolePicker.frame:Hide() end
    if restore and wishlistRenderer then wishlistRenderer.ShowFrame() end
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
    f.title:SetText("Choose permanent targets: " ..
        (DisplayUntrusted(state.name,1024,false) or "Wishlist"))
    f.count:SetText(string.format("Rolled copies %d/79  |  Permanent targets %d/6  |  %d total",total-locked,locked,total))
    f.pageLabel:SetText(string.format("Page %d / %d",state.page,pages))
    if state.page>1 then f.prev:Enable() else f.prev:Disable() end
    if state.page<pages then f.next:Enable() else f.next:Disable() end
    if total-locked<=79 and total-locked>0 and locked<=6 then
        f.confirm:Enable()
    else f.confirm:Disable() end
    f.confirm:SetText(state.assign and "Confirm permanent targets & assign" or "Confirm permanent targets & edit")
    local qualityNames={[0]="Common",[1]="Uncommon",[2]="Rare",[3]="Epic",[4]="Legendary"}
    for n,view in ipairs(f.rows) do
        local index=(state.page-1)*RolePicker.visibleRows+n
        local row=state.rows[index]
        view.index=index
        if row then
            view.label:SetText((DisplayUntrusted(row.name,256,false) or tostring(row.id))
                .. " (" .. tostring(qualityNames[row.quality] or row.quality) .. ") x" .. row.copies)
            view.count:SetText(tostring(row.selected) .. " permanent")
            if row.selected>0 then view.minus:Enable() else view.minus:Disable() end
            if row.selected<row.copies and locked<6 then view.plus:Enable() else view.plus:Disable() end
            view.frame:Show()
        else view.frame:Hide() end
    end
    f.message:SetText(state.message or "Choose permanent targets. This changes the plan, not owned Echoes or resources.")
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
        RolePicker.Message("Waiting for the server's current permanent Echo list. You can choose the intended targets manually.")
        return
    end
    local catalog=wishlistController.CatalogProjection()
    local selected,remaining={},{}
    for id,copies in pairs(locked.bySpell) do
        id=tonumber(id)
        if not id or id<1 or id~=math.floor(id) or type(copies)~="number" or copies<1 or copies~=math.floor(copies) or copies>6 then
            RolePicker.Message("The current permanent Echo list is incomplete. Choose the intended targets manually.")
            return false
        end
        remaining[id]=(remaining[id] or 0)+copies
    end
    local ownedTotal=0
    for _,copies in pairs(remaining) do ownedTotal=ownedTotal+copies end
    if ownedTotal>6 then
        RolePicker.Message("The server reports more than six permanent copies. No targets were guessed.")
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
    if count>6 then RolePicker.Message("More than six matching copies; choose the six intended targets manually.");return end
    for i,row in ipairs(state.rows) do row.selected=selected[i] end
    state.usedCurrentLocks=automatic==true
    state.message=automatic==true
        and "Using matching current permanent Echoes. The plan must fit 79 rolled copies / 6 permanent targets."
        or "Matching current permanent Echoes suggested as targets. Review them, then confirm your plan."
    RolePicker.Render()
    local total=RolePicker.Count()
    return count>0 and total-count>0 and total-count<=79 and count<=6
end

function RolePicker.Accept()
    local state=RolePicker.state
    if not state then return false end
    local total,locked=RolePicker.Count()
    if locked>6 or total-locked>79 or total-locked<1 then
        RolePicker.Message("Select up to six permanent-slot copies so no more than 79 rolled copies remain.")
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
    if not prepared then RolePicker.Message(why or "These targets are not representable.");return false end
    if state.kind=="import" then
        local name,class=state.name,state.class
        RolePicker.Hide()
        return LoadImportedWishlist({entries=echoes,name=name,class=class},name)
    end
    if state.assign then
        local slots=Adapter and Adapter.Slots and Adapter.Slots()
        if not slots or tonumber(slots.activeSlot or 0)~=state.activeSlot then
            RolePicker.Message("The active loadout changed. Cancel and select the intended loadout again.")
            return false
        end
    end
    local resolved,reason
    if Adapter and Adapter.ConfirmWishlistRoles then
        resolved,reason=Adapter.ConfirmWishlistRoles(state.candidate,echoes,
            state.usedCurrentLocks and "current-locks" or "user-confirmed")
    end
    if not resolved then RolePicker.Message(reason or "Could not preserve this role choice; reopen the Wishlist.");return false end
    local loadoutSlot=state.loadoutSlot
    if state.assign then
        local ok,err
        if state.activeSlot==0 then ok,err=Adapter.SetFirstRunWishlist(resolved.slot,resolved)
        else ok,err=Adapter.SetLoadoutWishlist(state.activeSlot,resolved.slot,resolved) end
        if not ok then
            RolePicker.Message("Roles saved, but assignment did not complete: " .. tostring(err or "unavailable"))
            return false
        end
        loadoutSlot=state.activeSlot>0 and state.activeSlot or nil
    end
    local name,usedCurrentLocks=resolved.name,state.usedCurrentLocks
    resolved.loadoutName=state.candidate.loadoutName
    RolePicker.Hide()
    local opened=M.OpenForWishlist(resolved,loadoutSlot)
    if opened then
        print("|cff4dff80Nexus:|r " .. (usedCurrentLocks and "Using matching current permanent Echoes for '" or "Permanent-slot targets confirmed for '") ..
            (DisplayUntrusted(name,1024,false) or "Wishlist") .. "'. Permanent Echoes were not changed.")
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
        RolePicker.state=nil
        if restore and wishlistRenderer then wishlistRenderer.ShowFrame() end
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
    help:SetText("Choose which copies are planned for the six permanent slots.\nThis edits only the Wishlist plan; your character's Echoes are unchanged.")
    f.count=label("GameFontNormal",20,-83,570)
    f.rows={}
    for n=1,RolePicker.visibleRows do
        local rf=CreateFrame("Frame",nil,p);rf:SetSize(570,28);rf:SetPoint("TOPLEFT",20,-109-(n-1)*28)
        rf:SetFrameStrata("FULLSCREEN_DIALOG");rf:SetFrameLevel(41)
        local row={frame=rf};f.rows[n]=row
        row.label=rf:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        row.label:SetPoint("LEFT",0,0);row.label:SetWidth(390);row.label:SetJustifyH("LEFT")
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
    f.prev=button("NexusWishlistRolePrevious","Previous",20,-394,82,function()
        if RolePicker.state then RolePicker.state.page=RolePicker.state.page-1;RolePicker.Render() end end)
    f.next=button("NexusWishlistRoleNext","Next",188,-394,70,function()
        if RolePicker.state then RolePicker.state.page=RolePicker.state.page+1;RolePicker.Render() end end)
    f.pageLabel=label("GameFontHighlightSmall",108,-401,78)
    f.owned=button("NexusWishlistRoleUseOwned","Suggest matching permanent targets",318,-394,270,function() RolePicker.UseOwned(false) end)
    f.message=label("GameFontHighlightSmall",20,-430,570)
    f.message:SetHeight(30)
    f.confirm=button("NexusWishlistRoleConfirm","Confirm permanent targets & edit",210,-470,278,RolePicker.Accept)
    f.cancel=button("NexusWishlistRoleCancel","Cancel",498,-470,90,RolePicker.Hide)
    f:Hide()
    return f
end

function RolePicker.Begin(entries,context)
    local candidate={echoes=entries,lockEvidenceStatus="unavailable"}
    local evidence=Adapter and Adapter.WishlistEvidenceState and Adapter.WishlistEvidenceState(candidate)
    if evidence~="evidence-pending" and evidence~="actionable" then
        print("|cffff6060Nexus:|r Wishlist contents are invalid; no draft or saved data was changed.")
        return false
    end
    local rows,byKey={},{}
    local catalog=wishlistController.CatalogProjection()
    for _,e in ipairs(entries) do
        local id,q,copies=tonumber(e.spellId),tonumber(e.quality or 0),tonumber(e.stacks)
        local cat=catalog and catalog.rows and catalog.rows[id]
        if q>255 or (cat and tonumber(cat.quality)~=q) then
            print("|cffff6060Nexus:|r An Echo's quality does not match its exact ID; no data was changed.")
            return false
        end
        local key=tostring(id)..":"..tostring(q)
        local row=byKey[key]
        if not row then
            row={id=id,quality=q,copies=0,selected=0,name=cat and cat.name or ("Echo "..id)}
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
        assign=context.assign,activeSlot=context.activeSlot}
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
    return settings and settings.useCurrentLocksForUntagged==false
        and "choose permanent targets" or "use current locks"
end

function M.ResolveAndAssignWishlist(candidate, activeSlot)
    local resolved,status,_,why=Adapter.ResolveWishlistEvidence(candidate)
    if status=="evidence-pending" then
        return RolePicker.Begin(resolved.echoes,{kind="existing",name=resolved.name,
            candidate=resolved,loadoutSlot=tonumber(activeSlot),assign=true,
            activeSlot=tonumber(activeSlot) or 0})
    end
    if status~="actionable" then return false,why end
    if tonumber(activeSlot)==0 then return Adapter.SetFirstRunWishlist(resolved.slot,resolved) end
    return Adapter.SetLoadoutWishlist(activeSlot,resolved.slot,resolved)
end

function M.ImportEBH1String(text, chosenName)
    local Codec = Nexus and Nexus.Codec
    if not (Codec and Codec.DecodeEBH1) then
        print("|cffff6060Nexus:|r import codec unavailable")
        return
    end
    local parsed = Codec.DecodeEBH1(text, true)
    if not parsed or #parsed.entries == 0 then
        print("|cffff6060Nexus:|r couldn't parse that as an EBH1 string.")
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

StaticPopupDialogs["NEXUS_EXPORT_WISHLIST"] = {
    text = "Your current wishlist + locked Echoes, as an EBH1 string.\nCtrl+A, Ctrl+C to copy:",
    button1 = "Close",
    hasEditBox = true,
    editBoxWidth = 350,
    OnShow = function(self)
        SetExplicitCopyText(self.editBox, (ExportEBH1String()) or "")
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["NEXUS_NAME_IMPORTED_WISHLIST"] = {
    text = "Choose a name for this imported wishlist:\n%s",
    button1 = "Open imported draft",
    button2 = "Cancel",
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
        local name = TrimWishlistName(
            self.editBox and self.editBox._NexusRawText
                and self.editBox:_NexusRawText()
                or (self.editBox and self.editBox:GetText()))
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
    text = "Paste a Wishlist import code (EBH1):\nThe import will be loaded as a new wishlist and will not overwrite the one currently open.",
    button1 = "Continue",
    button2 = "Cancel",
    hasEditBox = true,
    editBoxWidth = 350,
    OnAccept = function(self)
        -- Explicit EBH1 input is a lossless wire value, not ordinary display.
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

function M.OpenForCandidate(candidate)
    RolePicker.Hide()
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
    if Adapter and Adapter.ResolveWishlistEvidence then
        local resolved,status=Adapter.ResolveWishlistEvidence(wishlist)
        if status=="evidence-pending" and type(resolved)=="table" then
            return RolePicker.Begin(resolved.echoes,{kind="existing",name=resolved.name,
                candidate=resolved,loadoutSlot=loadoutSlot})
        end
        if status=="actionable" then wishlist=resolved end
    end
    RolePicker.Hide()
    if not wishlistController.BeginWishlist(wishlist, loadoutSlot) then
        SyncFulfilledDraftTargets()
        return false
    end
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

function M.Show()
    local slots=Adapter and Adapter.Slots and Adapter.Slots()
    local active=slots and tonumber(slots.activeSlot) or 0
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
