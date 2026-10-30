-- Ordinary planning pool with explicit local Save/Load (#151). Membership never supplies a choice.
Nexus = Nexus or {}
local Factory = {}
Nexus.FlexiblePlanChooser = Factory

local ROWS, HEIGHT = 12, 32
-- The pool row's Set button keeps its original 52 px and widens to fit its
-- changing label ("Set *" marks pending input) up to 81 px: in the 495 px
-- row the count box ends at 322, and Set, two 4 px gaps and the 84 px
-- Remove button must end by 495.
local SET_MIN, SET_MAX = 52, 81
local function Plain(value) return type(value) == "table" and getmetatable(value) == nil end
-- Full UI localization (issues #143-#148): every code-owned visible text of
-- the chooser is a reviewed "plan." key, looked up through Nexus.Localization
-- when shown (never cached at load). Echo names, IDs and counts are data and
-- stay as supplied; refusal and persistence codes stay codes and are mapped to
-- their text only here, at display. TF falls back to the exact English legacy
-- bytes the caller passes when the seam cannot format a template.
local function T(key) return (Nexus.Localization.Text(key)) end
local function TF(key, args, english)
    local text, source = Nexus.Localization.Format(key, args)
    if source == "unavailable" and english ~= nil then return english end
    return text
end
local function N(value) return Nexus.Localization.Count(value) end
local function Display(value)
    local identity = Nexus.Identity
    return identity and identity.DisplaySafeText
        and identity.DisplaySafeText(value or "", 256, true) or ""
end
-- A button whose label changes is sized to that label (LayoutMetrics
-- FitButtonWidth, docs/UI_TEXT_LAYOUT.md).
local function SetActionLabel(button, text)
    button:SetText(text)
    local metrics = Nexus.LayoutMetrics
    if metrics and metrics.FitButtonWidth then metrics.FitButtonWidth(button, SET_MIN, SET_MAX) end
end
-- Refusal code -> its reviewed sentence (the code is the identity).
local REASONS = {
    INVALID_SELECTION="plan.status.reason_invalid_selection",
    INVALID_ALTERNATIVES="plan.status.reason_invalid_alternatives",
    STACK_LIMIT="plan.status.reason_stack_limit",
    ORDINARY_LIMIT="plan.status.reason_ordinary_limit",
    CATALOG_UNAVAILABLE="plan.status.reason_catalog_unavailable",
    INVALID_CATALOG="plan.status.reason_invalid_catalog",
    UNSUPPORTED_ROLE="plan.status.reason_unsupported_role",
    CATALOG_CHANGED="plan.status.reason_catalog_changed",
    EDITOR_CHANGED="plan.status.reason_editor_changed",
    PLAN_CHANGED="plan.status.reason_plan_changed",
    COUNT_PENDING="plan.status.reason_count_pending",
}
-- #151 explicit local pool consent. Each dialog's data is one owned single-use
-- request. OnAccept returns nil, like NEXUS_FLEXIBLE_PLAN_REPLACE. A late or
-- replayed request does nothing and asks no popup to hide. Native pooling,
-- return handling and timing are NOT_RUN.
local LOAD_POPUP, CLEAR_POPUP = "NEXUS_FLEXIBLE_PLAN_LOAD", "NEXUS_FLEXIBLE_PLAN_CLEAR"
local function PopupAccept(_, request)
    if type(request) == "table" and type(request.Accept) == "function" then request.Accept() end
end
local function PopupCancel(_, request)
    if type(request) == "table" and type(request.Cancel) == "function" then request.Cancel() end
end
-- Each dialog's question, consequence and buttons are reviewed keys, set
-- again just before each Show (PreparePopup). Every "%" is escaped because the
-- client formats the dialog text.
local POPUP_TEXT = {
    [LOAD_POPUP] = {"plan.popup.load_question", "plan.popup.load_consequence", "plan.button.popup_load_saved"},
    [CLEAR_POPUP] = {"plan.popup.clear_question", "plan.popup.clear_consequence", "plan.button.popup_remove_saved"},
}
local function PreparePopup(which)
    local dialog, keys = type(StaticPopupDialogs) == "table" and StaticPopupDialogs[which], POPUP_TEXT[which]
    if type(dialog) ~= "table" or not keys then return end
    dialog.text = (T(keys[1]) .. "\n" .. T(keys[2])):gsub("%%", "%%%%")
    dialog.button1, dialog.button2 = T(keys[3]), T("plan.button.popup_cancel")
end
if type(StaticPopupDialogs) == "table" then
    StaticPopupDialogs[LOAD_POPUP] = {
        OnAccept = PopupAccept, OnCancel = PopupCancel,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopupDialogs[CLEAR_POPUP] = {
        OnAccept = PopupAccept, OnCancel = PopupCancel,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    PreparePopup(LOAD_POPUP)
    PreparePopup(CLEAR_POPUP)
end

-- #151 visible persistence status: the fixed line under the count help, apart
-- from the pool status at the bottom. Plain player text only: no Store, API or
-- refusal code is shown.
-- Status name -> its reviewed sentence (P below shows it).
local PERSIST = {
    NONE="plan.status.persist_none",
    EMPTY="plan.status.persist_empty",
    NEW="plan.status.persist_new",
    UNSAVED="plan.status.persist_unsaved",
    UNSAVED_EMPTY="plan.status.persist_unsaved_empty",
    CHANGED="plan.status.persist_changed",
    PENDING="plan.status.persist_pending",
    HAS_SAVED="plan.status.persist_has_saved",
    MATCHES="plan.status.persist_matches",
    SAVED="plan.status.persist_saved",
    SAVED_EMPTY="plan.status.persist_saved_empty",
    CLEARED="plan.status.persist_cleared",
    LOADED="plan.status.persist_loaded",
    NOTHING="plan.status.persist_nothing",
    ASK_LOAD="plan.status.persist_ask_load",
    ASK_CLEAR="plan.status.persist_ask_clear",
    LOADING="plan.status.persist_loading",
    UNAVAILABLE="plan.status.persist_unavailable",
    READ_ONLY="plan.status.persist_read_only",
    READ_ONLY_LOAD="plan.status.persist_read_only_load",
    STALE="plan.status.persist_stale",
    FUTURE="plan.status.persist_future",
    UNREADABLE="plan.status.persist_unreadable",
}
local function P(name) return T(PERSIST[name]) end
-- Refusal code -> the reviewed clause that completes "Not saved: ...",
-- "Not loaded: ..." or "Not removed: ..." (plan.status.refused_*).
local WHY_CHANGED = "plan.note.why_saved_data_changed"
local WHY_ASKED = "plan.note.why_changed_after_asked"
local WHY_UNREADABLE = "plan.note.why_unreadable"
local PERSIST_WHY = {
    COUNT_PENDING="plan.note.why_count_pending",
    NOT_OBSERVED="plan.note.why_not_observed",
    INVALID_SESSION="plan.note.why_invalid_session",
    LOAD_INVALID="plan.note.why_load_invalid",
    SAVED_CHANGED="plan.note.why_saved_pool_changed",
    OWNER_CHANGED=WHY_CHANGED, ROOT_CHANGED=WHY_CHANGED, RECEIPT_UNKNOWN=WHY_CHANGED,
    STORE_OWNER_MISMATCH=WHY_CHANGED, LOAD_CHANGED=WHY_ASKED, PLAN_CHANGED=WHY_ASKED,
    RECEIPT_NOT_DURABLE="plan.note.why_receipt_read_only",
    READ_ONLY="plan.note.why_read_only", LOADING="plan.note.why_loading",
    SAVED_FUTURE="plan.note.why_future",
    SAVED_MALFORMED=WHY_UNREADABLE, SAVED_UNSUPPORTED=WHY_UNREADABLE, SAVED_OVERSIZED=WHY_UNREADABLE,
}
local PERSIST_COVERS = {COUNT_PENDING="pending", SAVED_CHANGED="stale", OWNER_CHANGED="stale",
    ROOT_CHANGED="stale", RECEIPT_UNKNOWN="stale", STORE_OWNER_MISMATCH="stale", LOAD_CHANGED="stale",
    RECEIPT_NOT_DURABLE="mode", READ_ONLY="mode", LOADING="mode", SAVED_FUTURE="mode",
    SAVED_MALFORMED="mode", SAVED_UNSUPPORTED="mode", SAVED_OVERSIZED="mode"}
-- English chooses between one and several Echoes; so does this code (two
-- keys, no plural grammar). n >= 1.
local function CatalogNote(n)
    if n == 1 then return T("plan.status.catalog_changed_one") end
    return TF("plan.status.catalog_changed_many", {count = N(n)})
end
-- A pool row's saved facts differ from the current catalog row, or it is gone.
local function Drifted(saved, live)
    return not Plain(live) or rawget(live, "quality") ~= saved.quality
        or rawget(live, "maxStack") ~= saved.maxStack or rawget(live, "groupId") ~= saved.groupId
        or rawget(live, "locked") ~= nil or rawget(live, "sourceRole") ~= nil
        or rawget(live, "lockIntent") ~= nil
end

function Factory.Reason(code)
    return T(REASONS[code] or "plan.status.reason_default")
end

function Factory.New(options)
    local M = {}
    local ids, captured, chosen = {}, {rows={}}, {}
    local pending, bindingCounts = {}, false
    local pool, frame, status, budget, search, catalogArea, poolArea
    local catalogRows, poolRows = {}, {}
    local catalogOffset, poolOffset, revision = 0, 0, 0
    -- The shown refusal as its code ("" for none); its text is resolved only
    -- when shown, so the pending-count check compares the code, never text.
    local note = ""
    -- #151 visible persistence presentation, assigned with the persistence
    -- state below (Refresh and the row scripts run only after New returns).
    local persistLabel, saveButton, loadButton, RenderPersistence, Rebind
    local changedMembers = 0

    local function HasPending() return next(pending) ~= nil end
    local function StatusText()
        local text = note ~= "" and Factory.Reason(note) or ""
        if HasPending() and note ~= "COUNT_PENDING" then
            return text..(text ~= "" and " " or "")..Factory.Reason("COUNT_PENDING")
        end
        return text
    end

    local function Selection()
        local out = {}
        for _, id in ipairs(ids) do
            if chosen[id] then out[#out+1] = {spellId=id, stacks=chosen[id]} end
        end
        return out
    end
    local function Say(code)
        -- Any code without a reviewed sentence shows the default reason, as
        -- Factory.Reason does (nil included).
        note = (code == nil or code == "") and "?" or tostring(code)
        if status then status:SetText(StatusText()) end
        return false, code
    end
    local function Refresh()
        if not frame then return end
        local catalog = options.catalog()
        local available = Plain(catalog) and Plain(catalog.rows)
        local matches = {}
        if available then
            local query = string.lower(search:GetText() or "")
            for id, row in pairs(catalog.rows) do
                if type(id) == "number" and id > 0 and id == math.floor(id) and Plain(row)
                    and (query == "" or tostring(id):find(query,1,true)
                        or string.lower(type(row.name)=="string" and row.name or ""):find(query,1,true)) then
                    matches[#matches+1] = id
                end
            end
            table.sort(matches)
        end
        local left = Nexus.VirtualList.Window(#matches, HEIGHT, ROWS*HEIGHT, catalogOffset, 0)
        local right = Nexus.VirtualList.Window(#ids, HEIGHT, ROWS*HEIGHT, poolOffset, 0)
        catalogOffset, poolOffset = left.offset, right.offset
        for i=1,ROWS do
            local row, id = catalogRows[i], matches[left.first+i-1]
            row.spellId = id
            if id then
                local value = catalog.rows[id]
                -- ID, quality and name are data; "#", "Q" and the spacing
                -- are the reviewed template's.
                local quality, name = tostring(value.quality), Display(value.name)
                row.label:SetText(TF("plan.label.catalog_row", {id = tostring(id), quality = quality, name = name},
                    "#"..id.."  Q"..quality.."  "..name))
                row.action:SetText(T(captured.rows[id] and "plan.button.added" or "plan.button.add"))
                if captured.rows[id] then row.action:Disable() else row.action:Enable() end
                row:Show()
            else row:Hide() end
            row, id = poolRows[i], ids[right.first+i-1]
            row.spellId = id
            if id then
                local value = captured.rows[id]
                -- One line, the committed count first: it stays visible before a
                -- long exact name, and the row tooltip shows the whole line.
                local english = "Set: "..tostring(chosen[id] or 0).."  #"..id.."  Q"..value.quality
                    .." / max "..value.maxStack.."  "..Display(value.name)
                row.label:SetText(TF("plan.label.pool_row", {count = tostring(chosen[id] or 0), id = tostring(id),
                    quality = tostring(value.quality), max_stack = tostring(value.maxStack),
                    name = Display(value.name)}, english))
                bindingCounts = true
                row.count:SetText(pending[id] or tostring(chosen[id] or 0))
                bindingCounts = false
                SetActionLabel(row.action, T(pending[id] and "plan.button.set_pending" or "plan.button.set"))
                row:Show()
            else row:Hide() end
        end
        local total = 0
        for _, count in pairs(chosen) do total = total + count end
        budget:SetText(TF("plan.label.budget", {alternatives = N(#ids), chosen = N(total)}))
        if available then
            -- Saved facts of the current pool against the catalog this Refresh
            -- already read: no further catalog or Store read, at most 256 rows.
            local changed = 0
            for _, id in ipairs(ids) do
                local saved = captured.rows[id]
                if saved and Drifted(saved, rawget(catalog.rows, id)) then changed = changed + 1 end
            end
            changedMembers = changed
        else
            -- No catalog to compare with: no drift is claimed until it is back.
            changedMembers = 0
        end
        status:SetText(available and StatusText() or Factory.Reason("CATALOG_UNAVAILABLE"))
        if RenderPersistence then RenderPersistence() end
    end
    local function Add(id)
        if captured.rows[id] then return Say("INVALID_ALTERNATIVES") end
        local nextIds = {}
        for i,value in ipairs(ids) do nextIds[i]=value end
        nextIds[#nextIds+1]=id
        local catalog = options.catalog()
        if not Plain(catalog) or not Plain(catalog.rows) then return Say("CATALOG_UNAVAILABLE") end
        local nextCatalog = {rows={}}
        for key,value in pairs(captured.rows) do nextCatalog.rows[key]=value end
        nextCatalog.rows[id]=catalog.rows[id]
        local nextPool, why = Nexus.FlexiblePlanModel.New({alternativeSpellIds=nextIds,catalog=nextCatalog})
        if not nextPool then return Say(why) end
        local detached = {rows={}}
        for _,row in ipairs(nextPool.Alternatives()) do detached.rows[row.spellId]=row end
        ids, captured, pool = nextIds, detached, nextPool
        revision, note = revision+1, ""
        Refresh()
        return true
    end
    local function SetCount(id, text)
        local count = tonumber(text)
        if not count or count ~= math.floor(count) or count < 0 or count > 79 then
            return Say("INVALID_SELECTION")
        end
        local selection = {}
        for _, member in ipairs(ids) do
            local copies = member == id and count or chosen[member]
            if copies and copies > 0 then selection[#selection+1]={spellId=member,stacks=copies} end
        end
        -- Choose admits at most 79 selection rows and refuses more as an
        -- invalid selection. Every row holds at least one copy, so more rows
        -- exceed the 79 ordinary copies: say that, after this row's maximum
        -- stack, which Choose checks before the copy budget for fewer rows.
        if #selection > 79 then
            local value = captured.rows[id]
            if value and count > value.maxStack then return Say("STACK_LIMIT") end
            return Say("ORDINARY_LIMIT")
        end
        if #selection > 0 then
            local result, why = pool.Choose(selection)
            if not result then return Say(why) end
        end
        chosen[id] = count > 0 and count or nil
        pending[id] = nil
        revision, note = revision+1, ""
        Refresh()
        return true
    end
    local function Remove(id)
        local nextIds = {}
        for _,member in ipairs(ids) do if member ~= id then nextIds[#nextIds+1]=member end end
        ids, chosen[id], captured.rows[id] = nextIds, nil, nil
        pending[id] = nil
        pool = #ids>0 and Nexus.FlexiblePlanModel.New({alternativeSpellIds=ids,catalog=captured}) or nil
        revision, note = revision+1, ""
        Refresh()
    end
    local function Open()
        if HasPending() then return Say("COUNT_PENDING") end
        if not pool then return Say("INVALID_SELECTION") end
        local draft, why = pool.Choose(Selection())
        if not draft then return Say(why) end
        local capturedRevision = revision
        return options.openDraft(draft, pool.Alternatives(), function()
            if HasPending() then return false, "COUNT_PENDING" end
            return capturedRevision == revision
        end, function() frame:Hide() end, Say)
    end
    local function Button(parent, name, text, width, callback)
        local button=CreateFrame("Button",name,parent,"UIPanelButtonTemplate")
        button:SetSize(width,22);button:SetText(text);button:SetScript("OnClick",callback)
        return button
    end
    local function Label(parent, text, width, height, x, y)
        local label=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        label:SetPoint("TOPLEFT",x,y);label:SetSize(width,height);label:SetJustifyH("LEFT");label:SetText(text)
        return label
    end
    local function EnsureFrame()
        if frame then return end
        frame=CreateFrame("Frame","NexusFlexiblePlanChooser",UIParent)
        frame:SetSize(1020,650);frame:SetPoint("CENTER");frame:SetFrameStrata("HIGH");frame:SetFrameLevel(60)
        frame:SetClampedToScreen(true);frame:EnableMouse(true)
        if type(UISpecialFrames)=="table" then table.insert(UISpecialFrames,"NexusFlexiblePlanChooser") end
        Label(frame,T("plan.title.plan_alternatives"),900,24,22,-16)
        local help=Label(frame,T("plan.label.count_help"),970,20,22,-44)
        -- #151 persistence status, distinct from the pool status at -570.
        persistLabel=Label(frame,"",970,20,22,-66)
        Label(frame,T("plan.heading.catalog"),430,20,22,-94);Label(frame,T("plan.heading.pool"),480,20,505,-94)
        search=CreateFrame("EditBox","NexusFlexiblePlanSearch",frame,"InputBoxTemplate")
        search:SetSize(430,22);search:SetPoint("TOPLEFT",22,-120);search:SetAutoFocus(false);search:SetMaxLetters(96)
        search:SetScript("OnTextChanged",function() catalogOffset=0;Refresh() end)
        search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        catalogArea=CreateFrame("Frame","NexusFlexiblePlanCatalog",frame)
        catalogArea:SetPoint("TOPLEFT",22,-152);catalogArea:SetSize(460,ROWS*HEIGHT)
        poolArea=CreateFrame("Frame","NexusFlexiblePlanPool",frame)
        poolArea:SetPoint("TOPLEFT",505,-152);poolArea:SetSize(495,ROWS*HEIGHT)
        catalogArea:EnableMouseWheel(true);poolArea:EnableMouseWheel(true)
        catalogArea:SetScript("OnMouseWheel",function(_,delta) catalogOffset=catalogOffset-delta*HEIGHT;Refresh() end)
        poolArea:SetScript("OnMouseWheel",function(_,delta) poolOffset=poolOffset-delta*HEIGHT;Refresh() end)
        for i=1,ROWS do
            local row=CreateFrame("Frame",nil,catalogArea)
            row:SetSize(460,HEIGHT);row:SetPoint("TOPLEFT",0,-(i-1)*HEIGHT)
            row.label=Label(row,"",375,30,0,0)
            local catalogRow = row
            row.action=Button(row,nil,T("plan.button.add"),62,function() return Add(catalogRow.spellId) end)
            row.action:SetPoint("TOPRIGHT",0,-3)
            catalogRows[i]=row
            row=CreateFrame("Frame",nil,poolArea)
            row:SetSize(495,HEIGHT);row:SetPoint("TOPLEFT",0,-(i-1)*HEIGHT)
            row.label=Label(row,"",280,HEIGHT,0,0)
            -- One line at the row height (docs/UI_TEXT_LAYOUT.md); while it is shortened
            -- the row's tooltip shows it whole, so the row takes mouse input.
            row:EnableMouse(true)
            if Nexus.LayoutMetrics then Nexus.LayoutMetrics.OneLineLabel(row.label,row,HEIGHT) end
            row.count=CreateFrame("EditBox",nil,row,"InputBoxTemplate")
            row.count:SetSize(32,22);row.count:SetPoint("TOPLEFT",290,-3);row.count:SetAutoFocus(false);row.count:SetMaxLetters(3)
            row.count:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
            row.count:SetScript("OnTextChanged",function(self)
                if bindingCounts or not row.spellId then return end
                local id, text = row.spellId, self:GetText() or ""
                local committed = tostring(chosen[id] or 0)
                if text == (pending[id] or committed) then return end
                pending[id] = text ~= committed and text or nil
                revision, note = revision+1, ""
                SetActionLabel(row.action, T(pending[id] and "plan.button.set_pending" or "plan.button.set"))
                status:SetText(StatusText())
                if RenderPersistence then RenderPersistence() end
            end)
            row.action=Button(row,nil,T("plan.button.set"),SET_MIN,function() row.count:ClearFocus();return SetCount(row.spellId,row.count:GetText()) end)
            row.action:SetPoint("LEFT",row.count,"RIGHT",4,0)
            row.remove=Button(row,nil,T("plan.button.remove"),84,function() return Remove(row.spellId) end)
            row.remove:SetPoint("LEFT",row.action,"RIGHT",4,0)
            poolRows[i]=row
        end
        budget=Label(frame,"",970,20,22,-546)
        status=Label(frame,"",970,36,22,-570)
        -- Fixed multi-line boxes keep their size (docs/UI_TEXT_LAYOUT.md): while
        -- the count help or the status overflows its box, as at a large font
        -- scale, a hover area over it shows the complete text (LayoutMetrics
        -- FullTextTooltip). Created once with the chooser; nothing moves.
        local metrics = Nexus.LayoutMetrics
        if metrics and metrics.FullTextTooltip then
            metrics.FullTextTooltip(help, frame)
            metrics.FullTextTooltip(status, frame)
            metrics.FullTextTooltip(persistLabel, frame)
        end
        local open=Button(frame,"NexusFlexiblePlanOpen",T("plan.button.open_draft"),224,Open)
        open:SetPoint("BOTTOMRIGHT",-22,18)
        -- #151 explicit local pool controls in the free left part of the action
        -- row; Open and Reset keep their places. They call the tested callbacks.
        saveButton=Button(frame,"NexusFlexiblePlanSave",T("plan.button.save_pool"),100,function() return M.SavePool() end)
        saveButton:SetPoint("BOTTOMLEFT",22,18)
        loadButton=Button(frame,"NexusFlexiblePlanLoad",T("plan.button.load_saved"),100,function() return M.LoadPool() end)
        loadButton:SetPoint("LEFT",saveButton,"RIGHT",8,0)
        if metrics and metrics.FitButtonWidth then
            metrics.FitButtonWidth(saveButton,100,170);metrics.FitButtonWidth(loadButton,100,170)
        end
        local reset=Button(frame,"NexusFlexiblePlanReset",T("plan.button.reset_pool"),100,function()
            ids,captured,chosen,pool={},{rows={}},{},nil
            pending={}
            catalogOffset,poolOffset,revision,note=0,0,revision+1,""
            if Rebind then Rebind() end
            Refresh()
        end)
        reset:SetPoint("RIGHT",open,"LEFT",-8,0)
        local hide=Button(frame,"NexusFlexiblePlanHide",T("plan.button.hide"),70,function() frame:Hide() end)
        hide:SetPoint("TOPRIGHT",-20,-16)
        frame:SetScript("OnShow",function(self)
            if Nexus.LayoutMetrics then Nexus.LayoutMetrics.FitToScreen(self) end
        end)
        if Nexus.Theme then
            Nexus.Theme.StyleWindow(frame, 0.96)
            Nexus.Theme.StyleTree(frame)
        end
        frame:Hide()
    end
    -- #151 persistence binding (docs/flexible-plans/LOCAL_PERSISTENCE_CONTRACT.md,
    -- "Chooser (`ui/FlexiblePlanChooser.lua`)"). The optional persistence facade
    -- reads saved data only on Show and on explicit Save, Load saved and Reset,
    -- never in Refresh, typing or scrolling. `observed` is the receipt the facade
    -- issued for the saved data this session is bound to. The first Show binds an
    -- unobserved session; an accepted Save/Clear/Load, an explicit Reset, or an
    -- explicit Save when nothing was observed (that Save then refuses) replaces
    -- it, and a Save or removal whose facade call fails or returns no result
    -- keeps it and marks the session stale. A newer read (`latest`) reports
    -- staleness but never
    -- authorizes a write. `cleanBytes` is the session's own clean baseline
    -- (initially the empty pool), distinct from the saved receipt.
    local persistence = options.persistence
    if not (type(persistence) == "table" and type(persistence.Read) == "function"
        and type(persistence.Save) == "function" and type(persistence.Clear) == "function") then
        persistence = nil
    end
    local observed, latest, observedOnce, cleanBytes, staleFlag, restored
    local cacheRevision, cacheBytes, cacheCode
    local phase, persistCode, phaseOp, phaseRevision, operation = "idle", nil, nil, nil, nil
    local loadRequest, clearRequest

    -- Canonical session bytes, encoded once per revision (nil = empty pool).
    local function SessionBytes()
        if cacheRevision ~= revision then
            local codec = Nexus.FlexiblePlanStore
            if not (codec and type(codec.Encode) == "function") then return nil, "CODEC_UNAVAILABLE" end
            local record, second = codec.Encode(ids, captured.rows, chosen)
            cacheRevision = revision
            if record then cacheBytes, cacheCode = second, nil else cacheBytes, cacheCode = nil, second end
        end
        return cacheBytes, cacheCode
    end
    local function Dirty()
        if HasPending() then return true end
        local bytes, why = SessionBytes()
        return why ~= nil or bytes ~= cleanBytes
    end
    -- Every outcome, including popup Accept paths that run without a button or
    -- Refresh, re-renders the visible status at once (also while hidden).
    local function Persist(nextPhase, nextCode)
        phase, persistCode, phaseOp, phaseRevision = nextPhase, nextCode, operation, revision
        if RenderPersistence then RenderPersistence() end
        return nextPhase, nextCode
    end
    local function Observe()
        local ok, read = pcall(persistence.Read)
        latest = ok and type(read) == "table" and read or {mode="unavailable", reason="READ_FAILED"}
        return latest
    end
    local function Retire(which, request)
        if request and type(StaticPopup_Hide) == "function" then StaticPopup_Hide(which, request) end
    end
    local function Differs(a, b)
        return a ~= nil and b ~= nil and a ~= b and (a.mode ~= b.mode or a.class ~= b.class
            or a.bytes ~= b.bytes or a.ownerKey ~= b.ownerKey or a.root ~= b.root)
    end
    -- #151 visible status from this chooser's own metadata: no Store or catalog
    -- read. A finished outcome is shown until the session changes; an
    -- unverified one until the next Save or Load. It never says Saved unless a
    -- verified Save or Clear completed.
    local function Outcome(seen, stale)
        if phase ~= "unverified" and phaseRevision ~= revision then return nil end
        -- A finished Save, Clear or Load is not current once the latest read
        -- shows other saved data, owner, root or mode: never a stale Saved.
        if stale and (phase == "saved" or phase == "loaded") then return nil end
        if phase == "saved" then
            if phaseOp == "clear" then return P("CLEARED"), "done" end
            return cleanBytes == nil and P("SAVED_EMPTY") or P("SAVED"), "done"
        elseif phase == "loaded" then
            return P("LOADED"), "done"
        elseif phase == "unverified" then
            -- One complete sentence per operation (removal or save) and
            -- whether the earlier saved pool was restored.
            local clear = phaseOp == "clear"
            if restored == true then
                return T(clear and "plan.status.unverified_clear_restored" or "plan.status.unverified_save_restored")
            end
            return T(clear and "plan.status.unverified_clear" or "plan.status.unverified_save")
        elseif phase ~= "refused" then
            return nil
        end
        if persistCode == "NOTHING_SAVED" then return P("NOTHING") end
        -- "Not loaded: / Not removed: / Not saved: {reason} Your pool is kept."
        -- with the refusal code's reviewed clause as {reason}.
        local verb = phaseOp == "load" and "plan.status.refused_load" or phaseOp == "clear"
            and "plan.status.refused_clear" or "plan.status.refused_save"
        local why = PERSIST_WHY[persistCode]
        if why then return TF(verb, {reason = T(why)}), PERSIST_COVERS[persistCode] end
        local mode = seen and seen.mode
        why = mode == "loading" and PERSIST_WHY.LOADING or mode == "readOnly" and PERSIST_WHY.READ_ONLY
            or "plan.note.why_unavailable"
        return TF(verb, {reason = T(why)}), "mode"
    end
    local function PersistText()
        if not persistence then return P("NONE") end
        local seen = latest or observed
        local mode, class = seen and seen.mode, seen and seen.class
        local stale = observed ~= nil and observed.class ~= nil
            and (staleFlag == true or Differs(latest, observed))
        local parts = {}
        if loadRequest then parts[1] = P("ASK_LOAD") elseif clearRequest then parts[1] = P("ASK_CLEAR") end
        local outcome, covers = Outcome(seen, stale)
        parts[#parts + 1] = outcome
        local writable = mode == "durable" and not stale
        if Dirty() then
            if HasPending() then
                if covers ~= "pending" then parts[#parts + 1] = P("PENDING") end
            elseif writable and class == "CURRENT" then
                parts[#parts + 1] = #ids == 0 and P("UNSAVED_EMPTY") or P("UNSAVED")
            elseif writable and class == "ABSENT" then
                parts[#parts + 1] = P("NEW")
            else
                parts[#parts + 1] = P("CHANGED")
            end
        elseif not outcome then
            if class == "CURRENT" and #ids == 0 then
                parts[#parts + 1] = P("HAS_SAVED")
            elseif class == "CURRENT" and not stale and observed and observed.bytes == cleanBytes then
                parts[#parts + 1] = P("MATCHES")
            elseif writable and class == "ABSENT" and #ids == 0 then
                parts[#parts + 1] = P("EMPTY")
            end
        end
        if covers ~= "mode" then
            if class == "FUTURE" then
                parts[#parts + 1] = P("FUTURE")
            elseif class == "MALFORMED" or class == "UNSUPPORTED" or class == "OVERSIZED" then
                parts[#parts + 1] = P("UNREADABLE")
            elseif mode == "loading" then
                parts[#parts + 1] = P("LOADING")
            elseif mode == "readOnly" then
                parts[#parts + 1] = class == "CURRENT" and P("READ_ONLY_LOAD") or P("READ_ONLY")
            elseif mode ~= nil and mode ~= "durable" then
                parts[#parts + 1] = P("UNAVAILABLE")
            end
        end
        if stale and covers ~= "stale" and (mode == "durable" or mode == "readOnly") then
            parts[#parts + 1] = P("STALE")
        end
        if changedMembers > 0 and #ids > 0 then parts[#parts + 1] = CatalogNote(changedMembers) end
        return table.concat(parts, " ")
    end
    RenderPersistence = function()
        if not persistence and saveButton then saveButton:Disable();loadButton:Disable() end
        if persistLabel then persistLabel:SetText(PersistText()) end
    end
    -- Explicit Reset empties the session, so it may bind that empty session to
    -- the current saved data for recovery: a read, never a write, and no dialog
    -- is hidden. A retained session is never rebound by a newer read.
    Rebind = function()
        if persistence and observedOnce then observed, staleFlag = Observe(), false end
    end
    -- Detached session from a decoded saved pool, or nil. Saved ID, quality,
    -- maxStack, group and counts are kept even when stale; a current catalog
    -- name is bounded decoration only. The catalog is read, never changed; drift
    -- is counted only against an available catalog.
    local function Prepare(saved, bytes)
        local codec = Nexus.FlexiblePlanStore
        if not (Plain(saved) and Plain(saved.ids) and Plain(saved.rows) and Plain(saved.chosen)
            and codec and type(codec.Encode) == "function") then return nil end
        local catalog = options.catalog()
        local current = Plain(catalog) and Plain(catalog.rows) and catalog.rows or nil
        local nextIds, rows, nextChosen, selection, changed = {}, {}, {}, {}, 0
        for i, id in ipairs(saved.ids) do
            local s, live = saved.rows[id], current and rawget(current, id)
            if not Plain(s) then return nil end
            rows[id] = {spellId=id, quality=s.quality, maxStack=s.maxStack, groupId=s.groupId}
            if Plain(live) then
                local name = rawget(live, "name")
                if type(name) == "string" and #name <= 256 then rows[id].name = name end
            end
            if current and Drifted(s, live) then changed = changed + 1 end
            nextIds[i] = id
            local count = saved.chosen[id]
            if count then nextChosen[id] = count; selection[#selection+1] = {spellId=id, stacks=count} end
        end
        local model = #nextIds > 0 and Nexus.FlexiblePlanModel.New({alternativeSpellIds=nextIds, catalog={rows=rows}})
        if not model or (#selection > 0 and not model.Choose(selection)) then return nil end
        local detached = {rows={}}
        for _, row in ipairs(model.Alternatives()) do detached.rows[row.spellId] = row end
        local record, encoded = codec.Encode(nextIds, detached.rows, nextChosen)
        if not record or encoded ~= bytes then return nil end
        return {ids=nextIds, captured=detached, chosen=nextChosen, pool=model, changed=changed}
    end
    -- One complete assignment after Prepare succeeded; nothing partial before it.
    local function Install(p, read)
        ids, captured, chosen, pool, pending = p.ids, p.captured, p.chosen, p.pool, {}
        catalogOffset, poolOffset, revision, note = 0, 0, revision + 1, ""
        observed, latest, cleanBytes, staleFlag, restored = read, read, read.bytes, false, nil
        cacheRevision, cacheBytes, cacheCode, changedMembers = revision, read.bytes, nil, p.changed
        Refresh()
        return Persist("loaded", nil)
    end
    local function LoadFrom(read)
        if read.loadable ~= true then
            return Persist("refused", read.class == "ABSENT" and "NOTHING_SAVED"
                or read.class and "SAVED_" .. read.class or read.reason or "UNAVAILABLE")
        end
        local p = Prepare(read.pool, read.bytes)
        if not p then return Persist("refused", "LOAD_INVALID") end
        return Install(p, read)
    end
    local function Apply(result, bytes)
        if type(result) ~= "table" then
            -- Nothing is known about the write or restoration: that answer is dropped
            -- and the session is stale. The bound receipt stays (never a newer read),
            -- so a later Save is still checked against it.
            restored, staleFlag = nil, true
            return Persist("unverified", "SAVE_UNVERIFIED")
        end
        restored = result.restored
        if result.state == "saved" then
            observed, latest = result.receipt or observed, result.receipt or latest
            cleanBytes, staleFlag = bytes, false
            return Persist("saved", result.unchanged and "UNCHANGED" or nil)
        elseif result.state == "unverified" then
            -- Unverified never rebinds: the receipt this session was bound to stays,
            -- so every later Save is checked against it: a restored earlier record
            -- saves again; a differing record keeps Save pool refused until
            -- an explicit Load saved or Reset.
            latest = result.receipt or latest
            return Persist("unverified", result.reason or "SAVE_UNVERIFIED")
        end
        local reason = result.reason or "SAVE_REFUSED"
        if reason == "SAVED_CHANGED" or reason == "OWNER_CHANGED" or reason == "ROOT_CHANGED" then
            staleFlag = true
        end
        return Persist("refused", reason)
    end

    function M.SavePool()
        operation = "save"
        if not persistence then return Persist("refused", "NO_PERSISTENCE") end
        local former = clearRequest
        clearRequest = nil
        Retire(CLEAR_POPUP, former)
        if HasPending() then return Persist("refused", "COUNT_PENDING") end
        if not observed or observed.class == nil then
            observed = Observe()
            return Persist("refused", "NOT_OBSERVED")
        end
        local bytes, why = SessionBytes()
        if why then return Persist("refused", "INVALID_SESSION") end
        if bytes == nil and observed.class == "CURRENT" then
            local receipt = observed
            local request = {chooser=M, revision=revision, bytes=receipt.bytes,
                ownerKey=receipt.ownerKey, root=receipt.root}
            function request.Accept()
                if clearRequest ~= request then return end
                clearRequest = nil
                operation = "clear"
                if revision ~= request.revision or observed ~= receipt then
                    return Persist("refused", "PLAN_CHANGED")
                end
                local ok, result = pcall(persistence.Clear, receipt)
                return Apply(ok and result, nil)
            end
            function request.Cancel()
                if clearRequest == request then clearRequest = nil; RenderPersistence() end
            end
            clearRequest = request
            PreparePopup(CLEAR_POPUP)
            StaticPopup_Show(CLEAR_POPUP, nil, nil, request)
            RenderPersistence()
            return "confirm", "CLEAR_CONFIRM"
        end
        local ok, result = pcall(persistence.Save, {ids=ids, rows=captured.rows, chosen=chosen}, observed)
        return Apply(ok and result, bytes)
    end

    function M.LoadPool()
        operation = "load"
        if not persistence then return Persist("refused", "NO_PERSISTENCE") end
        local read = Observe()
        local former = loadRequest
        loadRequest = nil
        Retire(LOAD_POPUP, former)
        if read.loadable ~= true or not Dirty() then return LoadFrom(read) end
        if not Prepare(read.pool, read.bytes) then return Persist("refused", "LOAD_INVALID") end
        local request = {chooser=M, revision=revision, bytes=read.bytes,
            ownerKey=read.ownerKey, root=read.root}
        function request.Accept()
            if loadRequest ~= request then return end
            -- Single use: retired before any validation.
            loadRequest = nil
            operation = "load"
            if revision ~= request.revision then return Persist("refused", "LOAD_CHANGED") end
            local fresh = Observe()
            if fresh.loadable ~= true or fresh.bytes ~= request.bytes
                or fresh.ownerKey ~= request.ownerKey or fresh.root ~= request.root then
                return Persist("refused", "LOAD_CHANGED")
            end
            return LoadFrom(fresh)
        end
        function request.Cancel()
            if loadRequest == request then loadRequest = nil; RenderPersistence() end
        end
        loadRequest = request
        PreparePopup(LOAD_POPUP)
        StaticPopup_Show(LOAD_POPUP, nil, nil, request)
        RenderPersistence()
        return "confirm", "LOAD_CONFIRM"
    end

    -- Fresh scalar persistence metadata; never reads the Store.
    function M.PersistenceState()
        local seen = latest or observed
        return {available=persistence ~= nil, phase=phase, code=persistCode, dirty=Dirty(),
            pending=HasPending(), stale=staleFlag == true or Differs(latest, observed),
            mode=seen and seen.mode or nil, class=seen and seen.class or nil,
            saved=seen ~= nil and seen.class == "CURRENT", loadable=seen ~= nil and seen.loadable == true,
            saveable=seen ~= nil and seen.saveable == true, restored=restored,
            catalogChanged=changedMembers,
            confirming=loadRequest and "load" or clearRequest and "clear" or nil}
    end

    function M.Show()
        EnsureFrame()
        if persistence then
            -- Each Show reads the latest saved data to state its mode and any
            -- staleness. Only the first binds an unobserved session; a newer read
            -- never replaces the receipt a retained session is bound to.
            local read = Observe()
            if not observedOnce then
                observedOnce = true
                if observed == nil then observed = read end
            end
        end
        Refresh();frame:Show()
    end
    function M.Hide() if frame then frame:Hide() end end
    return M
end
