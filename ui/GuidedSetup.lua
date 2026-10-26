-- Nexus: ui/GuidedSetup.lua
-- The guided setup coach window over core/GuidedSetup.lua (issue #131): one
-- step at a time, each with its purpose, one main action that opens an
-- existing window (Wishlist Editor, import dialog, Echo Journal chooser,
-- Nexus panel, Help) and the result Nexus actually read back. Navigation
-- (Next, Back, Skip, Close, Escape, Help, replay) only moves the guide; it
-- assigns, saves, sends, spends and toggles nothing. The window reads state
-- only when shown, on a click or when a real outcome reports a receipt.
Nexus = Nexus or {}
local U = {}
Nexus.GuidedSetupUI = U
local frame, note
local W, TEXT_W, ROWS, BLOCK_MAX = 420, 372, 11, 160
local HELP = {welcome = 'start', wishlist = 'wishlists', target = 'wishlists', assign = 'wishlists',
    manual = 'rolling', auto = 'rolling', summary = 'start'}

local function Core() return Nexus.GuidedSetup end
local function Copy() local t = Nexus.UserText; return t and t.Guide or {} end
local function Fmt(text, ...)
    local ok, s = pcall(string.format, tostring(text or ''), ...)
    return ok and s or tostring(text or '')
end
local function Safe(v)
    local t = Nexus.UserText
    return t and t.SafeName and t.SafeName(v) or nil
end
local function Q(v) return string.char(39) .. (Safe(v) or '?') .. string.char(39) end
local function Ready()
    if type(Nexus.StartupStatus) ~= 'function' then return false end
    local ok, s = pcall(Nexus.StartupStatus)
    return ok and type(s) == 'table' and s.coreReady == true
end
local function TargetLabel(dest, name)
    local t = Nexus.UserText
    if dest == 'first' then return (Copy().target or {}).first or 'the first-run target' end
    return t and t.SavedBuildLabel and t.SavedBuildLabel(dest, name) or ('Saved Build ' .. tostring(dest))
end

local function NewText(template)
    local fs = frame:CreateFontString(nil, 'OVERLAY', template or 'GameFontHighlightSmall')
    fs:SetJustifyH('LEFT')
    fs:SetJustifyV('TOP')
    fs:SetWidth(TEXT_W)
    return fs
end

local function NewButton(width, height)
    local b = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
    b:SetSize(width, height or 22)
    b:SetScript('OnClick', function(self)
        if not self.act then return end
        self.act()
        if frame:IsShown() then U.Render() end
    end)
    -- The complete label (a long or localized name) is always reachable here.
    b:SetScript('OnEnter', function(self)
        if not (GameTooltip and self.full) then return end
        GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
        GameTooltip:AddLine(self.full, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
    b:Hide()
    return b
end

local function SetButton(b, spec)
    if type(spec) ~= 'table' then b.act, b.full = nil, nil; b:Hide(); return end
    b:SetText(spec.label or '')
    b.full, b.act = spec.label, spec.act
    if spec.enabled == false then b:Disable() else b:Enable() end
    b:Show()
end

local function Ensure()
    if frame then return frame end
    frame = CreateFrame('Frame', 'NexusGuidedSetup', UIParent)
    frame:SetSize(W, 300)
    frame:SetPoint('CENTER', UIParent, 'CENTER', 0, 40)
    frame:SetFrameStrata('DIALOG')
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag('LeftButton')
    frame:SetScript('OnDragStart', function(self) self:StartMoving() end)
    frame:SetScript('OnDragStop', function(self) self:StopMovingOrSizing() end)
    frame:Hide()
    pcall(function()
        frame:SetBackdrop({bgFile = 'Interface\\Buttons\\WHITE8X8',
            edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border', edgeSize = 14,
            insets = {left = 4, right = 4, top = 4, bottom = 4}})
        frame:SetBackdropColor(0.06, 0.045, 0.035, 0.97)
        frame:SetBackdropBorderColor(0.75, 0.42, 0.18, 0.95)
    end)
    frame.title = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    frame.title:SetPoint('TOP', frame, 'TOP', 0, -14)
    frame.title:SetSize(TEXT_W, 20)
    frame.step = NewText('GameFontNormalSmall')
    frame.purpose = NewText('GameFontHighlightSmall')
    frame.status = NewText('GameFontHighlightSmall')
    frame.extra = NewText('GameFontHighlightSmall')
    frame.options = {}
    for i = 1, ROWS do frame.options[i] = NewButton(TEXT_W, 22) end
    frame.primary, frame.secondary = NewButton(180, 24), NewButton(186, 24)
    frame.back, frame.skip, frame.next = NewButton(70), NewButton(70), NewButton(90)
    frame.help, frame.close = NewButton(56), NewButton(62)
    frame.back:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 24, 18)
    frame.skip:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 100, 18)
    frame.next:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 176, 18)
    frame.help:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 272, 18)
    frame.close:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 334, 18)
    local metrics = Nexus.LayoutMetrics
    if metrics and type(metrics.FullTextTooltip) == 'function' then
        for _, fs in ipairs({frame.purpose, frame.status, frame.extra}) do metrics.FullTextTooltip(fs, frame) end
    end
    local theme = Nexus.Theme
    if theme then
        if theme.StyleWindow then theme.StyleWindow(frame, 0.97) end
        if theme.StyleTree then theme.StyleTree(frame) end
        if theme.StyleLabel then theme.StyleLabel(frame.title, 'accent'); theme.StyleLabel(frame.step, 'muted') end
    end
    -- Escape closes the coach exactly as Close does (U.Close). As for the
    -- Welcome (ui/QuickStart.lua), the coach itself is not listed in
    -- UISpecialFrames: a route that steps aside, a warning or another window
    -- hides it without closing it, and a first-use dismissal must not be taken
    -- from such a hide. This invisible child is listed instead. It is shown
    -- exactly while the coach is, and its own hide closes the coach only while
    -- the coach is still visible; an explicit hide of the coach hides it first,
    -- so that closes nothing. Offline model only; native NOT_RUN.
    local escape = CreateFrame('Frame', 'NexusGuidedSetupEscape', frame)
    escape:SetScript('OnHide', function() if frame and frame:IsVisible() then U.Close() end end)
    frame:HookScript('OnShow', function() escape:Show() end)
    frame:HookScript('OnHide', function() escape:Hide() end)
    escape:Hide()
    UISpecialFrames = UISpecialFrames or {}
    UISpecialFrames[#UISpecialFrames + 1] = 'NexusGuidedSetupEscape'
    local g = Core()
    if g then g.onChange = function(receipt) U.OnChange(receipt) end end
    return frame
end

-- Each block takes the height its wrapped text needs (capped; the complete
-- text is then on hover), so 125% text and long names never clip.
local function Place(fs, y, gap)
    local text = fs:GetText()
    fs:ClearAllPoints()
    fs:SetPoint('TOPLEFT', frame, 'TOPLEFT', 24, y)
    if text == nil or text == '' then fs:SetHeight(1); fs:Hide(); return y end
    fs:Show()
    local metrics, height = Nexus.LayoutMetrics, 42
    if metrics and type(metrics.WrapHeight) == 'function' then
        height = metrics.WrapHeight(fs, TEXT_W, 12, BLOCK_MAX)
    else fs:SetWidth(TEXT_W); fs:SetHeight(height) end
    return y - height - (gap or 6)
end

local function Layout()
    local y = -40
    y = Place(frame.step, y, 4)
    y = Place(frame.purpose, y, 8)
    y = Place(frame.status, y, 8)
    for _, b in ipairs(frame.options) do
        if b:IsShown() then
            b:ClearAllPoints()
            b:SetPoint('TOPLEFT', frame, 'TOPLEFT', 24, y)
            y = y - 26
        end
    end
    if frame.options[1]:IsShown() then y = y - 4 end
    y = Place(frame.extra, y, 8)
    frame.primary:ClearAllPoints()
    frame.primary:SetPoint('TOPLEFT', frame, 'TOPLEFT', 24, y)
    frame.secondary:ClearAllPoints()
    frame.secondary:SetPoint('TOPLEFT', frame, 'TOPLEFT', 210, y)
    if frame.primary:IsShown() or frame.secondary:IsShown() then y = y - 30 end
    frame:SetHeight(math.max(240, math.ceil(-y + 50)))
    local metrics = Nexus.LayoutMetrics
    if metrics and type(metrics.FitToScreen) == 'function' then metrics.FitToScreen(frame) end
end

local VIEW = {}

function VIEW.welcome(g, s, c)
    local p, v = c.paths or {}, {options = {}}
    for _, id in ipairs({'new', 'existing', 'explore'}) do
        v.options[#v.options + 1] = {label = (s.path == id and '> ' or '') .. (p[id] or id),
            act = function() note = nil; g.SetPath(id) end}
    end
    return v
end

function VIEW.wishlist(g, s, c)
    local t, b, n = c.wishlist or {}, c.buttons or {}, c.notes or {}
    local v = {options = {}}
    local list = g.WishlistOptions()
    for i, cand in ipairs(list or {}) do
        if i > 8 then v.extra = n.more; break end
        local w = s.wishlist
        local mine = w and w.source == 'existing' and w.key == cand.key and w.slot == tonumber(cand.slot)
        v.options[#v.options + 1] = {label = (mine and '> ' or '') .. Q(cand.name)
            .. (cand.lockEvidenceStatus == 'unavailable' and (t.rolesShort or '') or ''),
            act = function() local ok, why = g.ChooseWishlist(cand); note = (not ok) and n[why] or nil end}
    end
    if list and #list == 0 then v.extra = n.none end
    if not list then v.extra = n.notLoaded end
    local w = s.wishlist
    if w then
        v.status = Fmt(w.source == 'saved' and t.saved or t.chosen, Q(w.name)) .. (w.needsRoles and (t.needsRoles or '') or '')
    elseif s.draft then v.status = t.draft
    elseif s.saveSeen then v.status = t[s.saveSeen.saveKind] or t.notSaved
    else v.status = t.none end
    v.primary = {label = b.create, act = function() U.RouteEditor('new') end}
    v.secondary = {label = b.import, act = function() U.RouteEditor('import') end}
    return v
end

function VIEW.target(g, s, c)
    local t, b, n, mk = c.target or {}, c.buttons or {}, c.notes or {}, c.marks or {}
    local opts = g.TargetOptions()
    if not opts then return {status = t.notLoaded} end
    local v = {options = {}}
    for _, o in ipairs(opts) do
        local label = TargetLabel(o.destination, o.name)
        if o.blocked then label = label .. ' - ' .. (t[o.blocked] or o.blocked)
        elseif o.selected then label = label .. (t.selected or '') end
        local mine = s.target and s.target.destination == o.destination
        v.options[#v.options + 1] = {label = (mine and '> ' or '') .. label, enabled = not o.blocked,
            act = function() local ok, why = g.ChooseTarget(o.destination); note = (not ok) and n[why] or nil end}
    end
    local f = g.TargetFacts()
    if not f then v.status = t.none; return v end
    local label = TargetLabel(f.destination, f.name)
    v.status = (mk[f.ready and 'done' or 'todo'] or '') .. ' ' .. Fmt(t.chosen, label)
    if f.read.state == 'unknown' then v.extra = Fmt(t.unknown, label)
    elseif f.already then v.extra = Fmt(t.already, label, Q(f.read.name))
    elseif f.replaces then
        v.extra = Fmt(t.replace, label, Q(f.read.name), Q(s.wishlist and s.wishlist.name))
        if f.confirmed then v.extra = v.extra .. '\n' .. (t.confirmed or '')
        else
            v.primary = {label = b.replace, act = function() g.ConfirmReplace() end}
            v.secondary = {label = b.cancel, act = function() g.CancelReplace() end}
        end
    end
    return v
end

function VIEW.assign(g, s, c)
    local t, b = c.assign or {}, c.buttons or {}
    local st, f = g.AssignStatus(), g.TargetFacts()
    local target = f and TargetLabel(f.destination, f.name) or '?'
    local wish = s.wishlist and Q(s.wishlist.name) or Q(nil)
    local detail = (st.state == 'refused' and (Safe(tostring(st.reason or '?')) or '?'))
        or (st.state == 'other' and Q(st.name)) or (st.state == 'mismatch' and Q(st.readName)) or ''
    local key = (st.state == 'verified' and st.origin == 'save') and 'verifiedSave' or st.state
    local v = {status = Fmt(t[key] or t.unknown, target, wish, detail)}
    if st.state ~= 'none' and st.state ~= 'verified' and st.state ~= 'observed' then
        v.primary = {label = b.open, act = function() U.RouteChooser() end}
    end
    if st.state ~= 'none' then v.secondary = {label = b.check, act = function() note = nil end} end
    return v
end

function VIEW.manual(g, s, c)
    local m, b = c.sim or {}, c.buttons or {}
    local v = {options = {}, status = (m.banner or '') .. '\n' .. (m.plan or '')}
    for i, card in ipairs(m.cards or {}) do
        v.options[i] = {label = (s.manualPick == i and '> ' or '') .. '[SIMULATED] ' .. card,
            act = function() g.SimPick(i) end}
    end
    if s.manualPick then
        v.extra = s.manualPick == g.SIM_ANSWER and (m.right or '') or Fmt(m.wrong, (m.cards or {})[s.manualPick] or '?')
        if s.manualAck then v.extra = v.extra .. '\n' .. (m.acked or '') end
    end
    v.primary = {label = b.ack, enabled = s.manualPick == g.SIM_ANSWER and not s.manualAck,
        act = function() g.SimAck() end}
    return v
end

function VIEW.auto(g, s, c)
    local a, b = c.auto or {}, c.buttons or {}
    return {status = a[g.AutoState()] or a.unknown,
        primary = {label = b.panel, act = function() if Nexus.Panel and Nexus.Panel.Show then Nexus.Panel.Show() end end},
        secondary = {label = b.autoHelp, act = function() if Nexus.Help then Nexus.Help.Show('rolling') end end}}
end

function VIEW.summary(g, s, c)
    local sm, mk, b = c.summary or {}, c.marks or {}, c.buttons or {}
    local r = g.Summary()
    local lines = {sm.head or ''}
    for _, id in ipairs({'wishlist', 'target', 'assign', 'manual', 'auto'}) do
        lines[#lines + 1] = (mk[r[id]] or ('[' .. tostring(r[id]) .. ']')) .. ' ' .. ((sm.rows or {})[id] or id)
    end
    lines[#lines + 1] = (r.complete and sm.complete) or (r.trueNow and sm.trueNow) or sm.notComplete or ''
    return {status = table.concat(lines, '\n'), extra = sm.optional,
        options = {{label = b.replay, act = function() note = nil; g.Replay() end}},
        primary = {label = b.orb, act = function() U.Lesson('orbs') end},
        secondary = {label = b.share, act = function() U.Lesson('sharing') end}, noNext = true, noSkip = true}
end

function U.Render()
    local f, g = Ensure(), Core()
    if not g then return end
    g.Recheck()
    local s, c = g.State(), Copy()
    local b = c.buttons or {}
    local id = g.StepId()
    f.title:SetText(c.title or '')
    f.step:SetText(Fmt(c.stepOf, s.index, #g.STEPS, (c.names or {})[id] or id))
    f.purpose:SetText((c.purpose or {})[id] or '')
    local v = VIEW[id](g, s, c) or {}
    local status = v.status or ''
    if s.notice then status = ((c.notice or {})[s.notice] or '') .. '\n' .. status end
    f.status:SetText(status)
    local extra = v.extra
    if note then extra = extra and (extra .. '\n' .. note) or note end
    f.extra:SetText(extra or '')
    for i, btn in ipairs(f.options) do SetButton(btn, (v.options or {})[i]) end
    SetButton(f.primary, v.primary)
    SetButton(f.secondary, v.secondary)
    SetButton(f.back, s.index > 1 and {label = b.back, act = function() note = nil; g.Back() end} or nil)
    SetButton(f.skip, not v.noSkip and {label = b.skip, act = function() note = nil; g.Skip() end} or nil)
    SetButton(f.next, not v.noNext and {label = b.next, enabled = g.CanNext(),
        act = function() note = nil; g.Next() end} or nil)
    SetButton(f.help, {label = b.help, act = function() if Nexus.Help then Nexus.Help.Show(HELP[id]) end end})
    SetButton(f.close, {label = b.close, act = function() U.Close() end})
    Layout()
end

-- An unsaved route may be canceled without a save receipt. Return to the
-- same guide step, but never claim the Wishlist was completed.
function U.RouteEnded(kind)
    local f = frame
    if not f or not f.waiting or f.waitingKind ~= kind then return end
    local warning = Nexus.OverwriteWarning
    if warning and type(warning.IsOpen) == 'function' and warning.IsOpen() then return end
    local g = Core()
    if g and type(g.CancelAwaitSave) == 'function' then g.CancelAwaitSave() end
    f.waiting, f.waitingKind = nil, nil
    f:Show()
    U.Render()
end

-- Imported plans can open the editor after a second naming/role dialog.
-- Watch that same editor once, and use the currently active route on close.
function U.WatchEditor(kind)
    local f, editorFrame = frame, _G.NexusEditorFrame
    if not f or f.waitingKind ~= kind then return end
    if not editorFrame or not editorFrame:IsShown() then U.RouteEnded(kind); return end
    if type(editorFrame.HookScript) == 'function' and not editorFrame._NexusGuideOnHide then
        editorFrame._NexusGuideOnHide = true
        editorFrame:HookScript('OnHide', function()
            if frame and frame.waitingKind then U.RouteEnded(frame.waitingKind) end
        end)
    end
end

-- Opens the editor or the import dialog; the guide steps aside and returns
-- when the editor reports a save or the route is canceled. Opening a draft
-- completes nothing.
function U.RouteEditor(kind)
    local g, n, f = Core(), Copy().notes or {}, frame
    if not Ready() then note = n.startup; return end
    local editor = Nexus.WishlistEditor
    if kind == 'import' then
        if type(StaticPopup_Show) ~= 'function' or not (StaticPopupDialogs or {}).NEXUS_IMPORT_WISHLIST then note = n.noEditor; return end
    elseif not (editor and type(editor.NewWishlist) == 'function') then note = n.noEditor; return end
    g.AwaitSave(); note = nil
    f.waiting, f.waitingKind = true, kind
    f:Hide()
    if kind == 'import' then
        StaticPopup_Show('NEXUS_IMPORT_WISHLIST')
    else
        editor.NewWishlist()
        U.WatchEditor('new')
    end
end

-- Arms one request, then opens the existing Echo Journal chooser. A target
-- the Journal does not assign to is refused, never redirected.
function U.RouteChooser()
    local g, n, f = Core(), Copy().notes or {}, frame
    if not Ready() then note = n.startup; return end
    local journal = Nexus.JournalTab
    if not (journal and type(journal.OpenBuilds) == 'function')
        or (type(journal.CanOpenBuilds) == 'function' and not journal.CanOpenBuilds()) then
        note = n.unavailable; return
    end
    local ok, why, where, whereName = g.ArmAssign()
    if not ok then
        if why == 'route' then
            local tf = g.TargetFacts()
            note = Fmt(n.route, where == 'blocked' and (n.blocked or '?') or TargetLabel(where, whereName),
                tf and TargetLabel(tf.destination, tf.name) or '?')
        else note = n[why] or n.notReady end
        return
    end
    note = nil
    local opened = journal.OpenBuilds(true, function() f.waiting = true; f:Hide() end)
    if not opened then g.Disarm(); f.waiting = nil; note = n.unavailable; f:Show() end
end

function U.Lesson(id) if Nexus.Help and Nexus.Help.Show then Nexus.Help.Show(id) end end

-- Resume: the same step, with its context checked again. Never opens over
-- an Auto warning that waits for its answer, and asks it nothing.
function U.Show()
    local warning = Nexus.OverwriteWarning
    if warning and type(warning.IsOpen) == 'function' and warning.IsOpen() then return false, 'warning-open' end
    local f = Ensure()
    -- An ordinary hide does not acknowledge first use. Keep its guarded
    -- callback across a Help reopen so a later deliberate Close can do so.
    f.waiting, f.waitingKind, note = nil, nil, nil
    f:Show()
    U.Render()
    return true
end

-- First use (ui/QuickStart.lua ShowIfFirstTime): the same coach, and the one
-- caller told when it is deliberately closed (Close or Escape: U.Close); no
-- other hide tells it anything. A coach that stepped aside for its own route
-- is not reopened over that window: the route's outcome returns it.
function U.ShowFirstUse(onClose)
    if type(onClose) ~= 'function' then return false end
    local warning = Nexus.OverwriteWarning
    if warning and type(warning.IsOpen) == 'function' and warning.IsOpen() then return false, 'warning-open' end
    local f = Ensure()
    f.firstUse = onClose
    if f.waiting and not f:IsShown() then return true end
    f.waiting, f.waitingKind, note = nil, nil, nil
    f:Show()
    U.Render()
    return true
end
function U.Replay()
    local g = Core()
    if g then g.Replay() end
    return U.Show()
end
function U.Hide() if frame then frame.waiting, frame.waitingKind = nil, nil; frame:Hide() end end
-- Close and Escape: the deliberate close. A first-use coach tells its caller
-- once, after it is hidden; that caller decides what is recorded (only that
-- first use was seen: guide steps keep their own state).
function U.Close()
    if not frame then return end
    local onClose = frame.firstUse
    frame.firstUse, frame.waiting, frame.waitingKind = nil, nil, nil
    frame:Hide()
    if type(onClose) == 'function' then pcall(onClose) end
end

function U.OnChange(receipt)
    if not frame then return end
    if frame.waiting and type(receipt) == 'table' and (receipt.kind == 'save' or receipt.kind == 'assign') then
        local warning = Nexus.OverwriteWarning
        if not (warning and type(warning.IsOpen) == 'function' and warning.IsOpen()) then
            frame.waiting, frame.waitingKind = nil, nil
            frame:Show()
        end
    end
    if frame:IsShown() then U.Render() end
end

return U
