-- Nexus: ui/GuidedSetup.lua
-- The guided setup coach window over core/GuidedSetup.lua (issue #131), laid
-- out after the Claude Design guided-setup artifact in its two presentations.
--
-- Setup Alternative (design/current "Nexus Setup Alternative"): the coach is
-- one step at a time in a fixed order: the step line and rail ("All steps"
-- opens the list), the step's title, one WHY THIS MATTERS line, DO THIS with
-- its action, then an outcome slot that says WHAT HAPPENED (the design's
-- OBSERVED, in plain words) only for a result the guide read or the player
-- made (otherwise WHAT YOU WILL SEE). The footer is the Wishlist step's
-- one Selected name, Continue across the row, the gate hint, then Back, Skip
-- for now and Continue later (the same close as X: the place is kept). The
-- header's Reference replaces the step with an optional topic list; a topic
-- opens its short article in the same view (All topics, or Escape, returns
-- to the list), and a separately labelled Open full Reference opens the
-- dense manual in place of the guide. It has its own way back and is never
-- shown under a step. The older notes below on the inline Help card and the
-- Help side panel describe what Reference replaced. The design's
-- 640 px window with a scrolling body and a pinned footer is the bounded
-- window (Bound, ScreenCap): on a readable UI size the coach is at most 640 px
-- tall and its body scrolls; text is no longer shrunk with the whole window.
-- Where the visible UI is wide enough (the design's 960 px, 1100 px at
-- enlarged text) it is the design's desktop window: 900 px, a header (title,
-- character, Help, close), the checklist as side navigation on the left, one
-- step card at a time beside it, Help as a side panel on the right, and a
-- footer across the window. Otherwise it is the 420 px compact window: the
-- same header, a step line with a segmented rail and a collapsible checklist,
-- the step card, inline Help and the footer. Header texts, the step line,
-- status chips and footer buttons take the room their text needs at the
-- current font scale (footer buttons wrap to a further row, never shrink).
-- The footer has Back, the gate hint, Skip for now and Continue. Each step says
-- what it is for, offers one main action that opens an existing window
-- (Wishlist Editor, Echo Journal chooser, Nexus panel, Orb window, Help) and
-- shows the result Nexus actually read back. A pasted Wishlist code is checked
-- in the Wishlist step itself (the design's paste field, Check code and inline
-- outcome) by the editor's read-only WishlistEditor.CheckImportCode; only the
-- later Open it as a draft hands that same code to the editor's own import
-- (naming, draft, then the player's save). Navigation (Continue, Back, Skip,
-- checklist, Close, Escape, Help, replay) and Check code only move or read;
-- they assign, save, send, spend and toggle nothing. The window reads state
-- only when shown, on a click or when a real outcome reports a receipt.
--
-- Adaptations of the HTML design, each an unmeasured choice, not a measured
-- client limit: the rotated diamond is a small square (a solid texture is not
-- drawn rotated here), the dashed simulated-preview border is a solid tinted
-- frame, the header gradient is left to the player's Theme appearance (which
-- owns this window's backdrop) and the stock game fonts stand in for the web
-- fonts. The design's Window switch is a demo control, so the presentation
-- follows the visible UI width (WideFits) instead of a player toggle, and the
-- design's em widths are fixed pixels at the stock font. The design's
-- two-row paste textarea is a one-line field (a 3.3.5a multi-line EditBox
-- needs its own scroll frame, and a code is one unbroken token), and its
-- Sample buttons are demo controls, not offered. Native pixels,
-- native font measurement and the real-client wide/compact comparison are
-- NOT RUN. Status glyphs are printable ASCII beside a word (the shared
-- Readout rule), never Unicode symbols that the client may not draw; on the
-- summary each glyph is its own 14 px icon in the 12 px font (StatusIcon).
-- The design's round radio marks are the client's own UIRadioButtonTemplate
-- (NewRow), not a drawn shape.
--
-- The footer follows the design's three treatments. Continue is the one
-- filled action (amber fill, light gold edge, dark label; while it waits, the
-- design's dark fill, grey edge and grey label), Skip for now is an
-- underlined text action with no fill or edge, and Back is the window's
-- secondary button, the themed look of Help and Close. Continue and Skip
-- are drawn here and kept out of the Theme, whose buttons share one look and
-- repaint their label on enable. Their colours are the design's own, fixed,
-- never from the palette. Client limits, not choices: the stock 3.3.5a fonts
-- have one weight, so Continue's bold label is a 1 px shadow in the label's
-- colour; a FontString has no underline, so Skip's is a 1 px texture under
-- its text; buttons take no keyboard focus, so the design's focus outline
-- has no counterpart, and a hover highlight is given instead. Adaptations:
-- Continue keeps the 22 px row height (the design pads it a little taller)
-- and its wider side padding is a fixed 10 px. A step card's one main action
-- (Try again, Replace and continue, the Wishlist chooser and its again, Check
-- again where the design fills it, Keep or Leave Auto) is the design's same
-- filled action, drawn as Continue is, at the 22 px row and without the
-- extra padding; the card's other actions (Choose another, Review, the links
-- to earlier steps, Help, replay) stay the themed secondary button. Native
-- pixels and font rendering of all of this are NOT RUN.
Nexus = Nexus or {}
local U = {}
Nexus.GuidedSetupUI = U
local frame, note
-- W, PAD and CW are the window width, the step card's left edge and its
-- width for the presentation being rendered (U.Render sets them); EDGE is the
-- window's own margin for the header and footer.
local COMPACT_W, EDGE = 420, 16
local W, PAD = COMPACT_W, EDGE
local CW = W - 2 * PAD
-- The design's desktop window: its width, the side navigation (13em) and the
-- Help side panel (15em) at the stock font, and the visible UI width it needs
-- at normal and enlarged text (the design's 960 px and 1100 px).
local WIDE = {w = 900, nav = 208, aside = 232, need = 960, needLarge = 1100}
local GAP, MIN_H, BLOCK_MAX = 8, 360, 220
-- The tallest the bounded window grows (Setup Alternative "Compact 640px").
local MAX_H = 640
local WHITE = 'Interface\\Buttons\\WHITE8X8'
local HELP = {welcome = 'start', wishlist = 'wishlists', target = 'wishlists', assign = 'wishlists',
    manual = 'rolling', auto = 'rolling', summary = 'start'}
-- Fixed status colours (never from the palette); each kind also has a glyph
-- and a word in the copy.
local COLOR = {['not'] = {0.62, 0.6, 0.58}, waiting = {0.95, 0.8, 0.38}, checking = {0.58, 0.76, 1},
    verified = {0.46, 0.86, 0.52}, skipped = {0.72, 0.7, 0.68}, unavailable = {0.82, 0.64, 1},
    stale = {0.5, 0.86, 0.9}, rejected = {1, 0.52, 0.42}, observed = {0.62, 0.84, 0.72}}
local GOLD, TEXT, MUTED = {1, 0.78, 0.36}, {0.92, 0.9, 0.86}, {0.74, 0.7, 0.66}
local HELP_BLUE = {0.6, 0.72, 0.95}
-- Session-only view state: the help card, the checklist, Auto's explainer,
-- the open optional lesson, the presentation last rendered and the Wishlist
-- step's paste field (open, its text, the last check's result and the text
-- that check read), and whether Start an empty Wishlist was asked while an
-- unsaved Plan draft is set aside (PlanDraftCard), and a bounded window's
-- scroll offset and the step it belongs to (Bound). Never saved; a pasted
-- code is never imported by typing.
local view = {help = false, checklist = false, autoMore = false, lesson = nil, review = false, wide = false,
    planDraft = false, import = {open = false, text = '', result = nil, checked = nil}, scroll = 0}
local function ResetImport() view.import = {open = false, text = '', result = nil, checked = nil} end

local function Core() return Nexus.GuidedSetup end
local function Copy() local t = Nexus.UserText; return t and t.Guide or {} end
-- Words this file adds until core/UserText.lua Guide carries them; a key of
-- the same name there wins (Words). What Nexus follows now on the Wishlist
-- step (core CurrentAssignment), and the summary's Already linked status: a
-- link read back that this guide did not make, never Done - confirmed.
local EXTRA = {
    wishlist = {assignedNow = 'Assigned now to %s',
        assignedNowLine = 'Assigned now to %s: %s.',
        assignedNowAmbiguous = 'Assigned now to %s: %s. More than one listed Wishlist holds the same Echoes under that name, so none is marked.',
        assignedNowUnknown = '! What is assigned now could not be read, so no Wishlist is marked as assigned.'},
    status = {observed = {glyph = '=', word = 'Already linked'}},
}
local function Words(group, key)
    local c = Copy()[group]
    local v = type(c) == 'table' and c[key] or nil
    if v == nil and EXTRA[group] then v = EXTRA[group][key] end
    return v
end
local function Fmt(text, ...)
    local ok, s = pcall(string.format, tostring(text or ''), ...)
    return ok and s or tostring(text or '')
end
local function Safe(v)
    local t = Nexus.UserText
    return t and t.SafeName and t.SafeName(v) or nil
end
local function Name(v) return Safe(v) or '?' end
local function Ready()
    if type(Nexus.StartupStatus) ~= 'function' then return false end
    local ok, s = pcall(Nexus.StartupStatus)
    return ok and type(s) == 'table' and s.coreReady == true
end
local function TargetLabel(dest, name)
    local c = Copy().target or {}
    if dest == 'first' then return c.first or 'First-run target' end
    local n = Safe(name)
    if n and n ~= '' then return Fmt(c.slot, dest, n) end
    return Fmt(c.slotUnnamed, dest)
end
local function Say(line)
    local chat = _G.DEFAULT_CHAT_FRAME
    if chat and type(chat.AddMessage) == 'function' then pcall(chat.AddMessage, chat, line, 1, 0.82, 0.4) end
end

------------------------------------------------------------------------
-- Pools. Every region is a direct child of the coach so the Theme, the
-- Escape child and the tests see one tree; a render hides the pools and
-- places what the step needs from the top down.
------------------------------------------------------------------------
local pools, order = {}, {}

local function Take(kind, make)
    local p = pools[kind]
    if not p then p = {used = 0}; pools[kind] = p end
    p.used = p.used + 1
    local item = p[p.used]
    if not item then item = make(); p[p.used] = item end
    return item
end

local function Release()
    for _, p in pairs(pools) do
        for i = 1, #p do
            local item = p[i]
            -- A region scrolled out of the last render's viewport (ApplyScroll)
            -- is laid out afresh; its mark goes with it.
            item._nexusOut = nil
            if item.desc then item.desc._nexusOut = nil end
            if item.Hide then item:Hide() end
            if item._nexusHit then item._nexusHit:Hide() end
            if item.parts then for _, t in ipairs(item.parts) do t:Hide() end end
            if item.extra then for _, r in ipairs(item.extra) do r:Hide() end end
        end
        p.used = 0
    end
    order = {}
end

local function Tex(layer)
    local t = frame:CreateTexture(nil, layer or 'BORDER')
    t:SetTexture(WHITE)
    t:Hide()
    return t
end

local function Paint(t, c, a) t:SetVertexColor(c[1], c[2], c[3], a or 1) end

-- A flat rectangle (fill and four 1 px edges) behind texts; buttons draw
-- above it as child frames.
local function Box(x, y, w, h, edge, fill, fillAlpha)
    local b = Take('box', function()
        return {parts = {Tex('BORDER'), Tex('ARTWORK'), Tex('ARTWORK'), Tex('ARTWORK'), Tex('ARTWORK')}}
    end)
    local f, top, bottom, left, right = b.parts[1], b.parts[2], b.parts[3], b.parts[4], b.parts[5]
    f:ClearAllPoints(); f:SetPoint('TOPLEFT', frame, 'TOPLEFT', x, y); f:SetSize(w, h)
    Paint(f, fill or {0.1, 0.08, 0.06}, fillAlpha or 0.85); f:Show()
    local edges = {{top, x, y, w, 1}, {bottom, x, y - h + 1, w, 1}, {left, x, y, 1, h}, {right, x + w - 1, y, 1, h}}
    for _, e in ipairs(edges) do
        local t = e[1]
        t:ClearAllPoints(); t:SetPoint('TOPLEFT', frame, 'TOPLEFT', e[2], e[3]); t:SetSize(e[4], e[5])
        if edge then Paint(t, edge, 0.95); t:Show() else t:Hide() end
    end
    -- Its rectangle, so a scrolled body can show the part inside its viewport.
    b.geo = {x = x, y = y, w = w, h = h, edge = edge ~= nil}
    return b
end

local function Fill(x, y, w, h, c, a)
    local t = Take('fill', function() return Tex('ARTWORK') end)
    t:ClearAllPoints(); t:SetPoint('TOPLEFT', frame, 'TOPLEFT', x, y); t:SetSize(w, h)
    Paint(t, c, a); t:Show()
    t.geo = {x = x, y = y, w = w, h = h}
    return t
end

local FONTS = {title = 'GameFontNormalLarge', head = 'GameFontNormal', body = 'GameFontHighlightSmall',
    small = 'GameFontNormalSmall', muted = 'GameFontDisableSmall', strong = 'GameFontHighlight'}

-- A wrapped text block: fixed width, the height its text needs (capped; the
-- complete text is then on hover). Returns the height used.
local function Text(str, x, y, w, kind, color, justify)
    if str == nil or str == '' then return 0 end
    local fs = Take('text_' .. kind, function()
        local t = frame:CreateFontString(nil, 'OVERLAY', FONTS[kind] or FONTS.body)
        t:SetJustifyV('TOP')
        local metrics = Nexus.LayoutMetrics
        if metrics and type(metrics.FullTextTooltip) == 'function' then t._nexusHit = metrics.FullTextTooltip(t, frame) end
        return t
    end)
    fs:SetJustifyH(justify or 'LEFT')
    fs:SetText(str)
    fs:ClearAllPoints()
    fs:SetPoint('TOPLEFT', frame, 'TOPLEFT', x, y)
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    fs:Show()
    if fs._nexusHit then fs._nexusHit:Show() end
    local metrics, h = Nexus.LayoutMetrics, 14
    if metrics and type(metrics.WrapHeight) == 'function' then h = metrics.WrapHeight(fs, w, 12, BLOCK_MAX)
    else fs:SetWidth(w); fs:SetHeight(h) end
    order[#order + 1] = fs
    return h
end

local function Tooltip(self)
    if not (GameTooltip and self.full) then return end
    GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
    GameTooltip:AddLine(self.full, 1, 1, 1, true)
    if self.tip then GameTooltip:AddLine(self.tip, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
end

-- Click, hover and leave scripts shared by every coach button.
local function Wire(b)
    b:SetScript('OnClick', function(self)
        if not self.act then return end
        self.act()
        if frame:IsShown() then U.Render() end
    end)
    -- The complete label (a long or localized name) is always reachable here.
    b:SetScript('OnEnter', Tooltip)
    b:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
end

local function NewButton()
    local b = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
    b:SetSize(100, 22)
    Wire(b)
    local theme = Nexus.Theme
    if theme and theme.StyleButton then theme.StyleButton(b) end
    b:Hide()
    return b
end

-- The footer's own looks (file header), converted from the design's oklch
-- values: Continue usable (on) and waiting (off), and Skip for now (link).
-- A step card's main action is the design's same fill, edge and label.
local FOOT = {
    on = {fill = {0.8, 0.45, 0.16}, edge = {0.91, 0.63, 0.3}, text = {0.06, 0.04, 0.03}},
    off = {fill = {0.06, 0.04, 0.03}, edge = {0.21, 0.17, 0.15}, text = {0.47, 0.44, 0.42}},
    link = {text = {0.77, 0.74, 0.71}, hover = {1, 0.84, 0.57}},
}

-- A footer action outside the Theme: 'primary' (Continue, and a step card's
-- main action) draws a fill, four 1 px edges and a hover highlight; 'link'
-- (Skip for now) draws only an underline, brighter on hover. FooterPaint
-- colours it for its state.
local function FooterAction(look)
    local b = CreateFrame('Button', nil, frame)
    b:SetSize(100, 22)
    Wire(b)
    local theme = Nexus.Theme
    if theme and theme.Exempt then theme.Exempt(b) else b._nexusThemeExempt = true end
    b.look = look
    b.label = b:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    b.label:SetPoint('CENTER', b, 'CENTER', 0, 0)
    b:SetFontString(b.label)
    local function Part(layer)
        local t = b:CreateTexture(nil, layer)
        t:SetTexture(WHITE)
        return t
    end
    if look == 'primary' then
        b.fill = Part('BACKGROUND'); b.fill:SetAllPoints(b)
        b.edges = {}
        local sides = {{'TOPLEFT', 'TOPRIGHT'}, {'BOTTOMLEFT', 'BOTTOMRIGHT'}, {'TOPLEFT', 'BOTTOMLEFT'}, {'TOPRIGHT', 'BOTTOMRIGHT'}}
        for i, side in ipairs(sides) do
            local e = Part('BORDER')
            e:SetPoint(side[1], b, side[1], 0, 0); e:SetPoint(side[2], b, side[2], 0, 0)
            if i <= 2 then e:SetHeight(1) else e:SetWidth(1) end
            b.edges[i] = e
        end
        local hover = Part('HIGHLIGHT'); hover:SetAllPoints(b)
        hover:SetVertexColor(1, 1, 1, 0.12)
    else
        -- About the design's 3 px underline offset below the text's baseline.
        b.underline = Part('ARTWORK'); b.underline:SetHeight(1)
        b.underline:SetPoint('BOTTOM', b, 'BOTTOM', 0, 4)
        Paint(b.underline, FOOT.link.text)
        b.underlineHover = Part('HIGHLIGHT'); b.underlineHover:SetHeight(1)
        b.underlineHover:SetPoint('BOTTOM', b, 'BOTTOM', 0, 4)
        Paint(b.underlineHover, FOOT.link.hover)
    end
    b:Hide()
    return b
end

-- Colours a footer action for its state; b.painted names what was drawn.
local function FooterPaint(b, enabled)
    local c = b.look == 'link' and FOOT.link or (enabled and FOOT.on or FOOT.off)
    b.label:SetTextColor(c.text[1], c.text[2], c.text[3])
    if b.look ~= 'primary' then b.painted = 'link'; return end
    Paint(b.fill, c.fill)
    for _, e in ipairs(b.edges) do Paint(e, c.edge) end
    -- One font weight: a shadow one pixel to the right in the label's own
    -- colour thickens its strokes in place of the design's bold.
    b.label:SetShadowColor(c.text[1], c.text[2], c.text[3], 1)
    b.label:SetShadowOffset(1, 0)
    b.painted = enabled and 'primary' or 'waiting'
end

local function Arm(b, spec)
    b:SetText(spec.label or '')
    b.full, b.tip, b.act = spec.label, spec.tip, spec.act
    if spec.enabled == false then b:Disable() else b:Enable() end
    if b.look then FooterPaint(b, spec.enabled ~= false); b:Show(); return end
    local font = type(b.GetFontString) == 'function' and b:GetFontString() or nil
    local color = spec.primary and GOLD or TEXT
    if font and font.SetTextColor then font:SetTextColor(color[1], color[2], color[3]) end
    b:Show()
end

local function NewPrimary() return FooterAction('primary') end

-- One action button sized to its label (capped to the row; hover shows all).
-- A primary spec is the filled action from its own pool; any other is the
-- themed secondary button.
local function Action(spec, x, y, maxW)
    local b = spec.primary and Take('primary', NewPrimary) or Take('action', NewButton)
    b:SetHeight(22)
    Arm(b, spec)
    local metrics = Nexus.LayoutMetrics
    local w = metrics and metrics.FitButtonWidth and metrics.FitButtonWidth(b, spec.min or 70, maxW or CW) or 120
    b:SetWidth(w)
    b:ClearAllPoints()
    b:SetPoint('TOPLEFT', frame, 'TOPLEFT', x, y)
    return b, w
end

-- A row of actions that wraps to further lines inside width w. Returns height.
local function Actions(specs, x, y, w)
    local cx, cy, used = x, y, 0
    for _, spec in ipairs(specs) do
        if spec then
            local b, bw = Action(spec, cx, cy, w)
            if cx > x and cx + bw > x + w then
                cx, cy = x, cy - 26
                b:ClearAllPoints(); b:SetPoint('TOPLEFT', frame, 'TOPLEFT', cx, cy)
            end
            cx = cx + bw + 6
            used = y - cy + 22
        end
    end
    return used
end

-- A choice row: a radio mark (when given), its title as the button text and a
-- wrapped description under it. Long names wrap; the full title is on hover.
-- The mark is the client's own round single-choice button (the stock
-- UIRadioButtonTemplate, as the Sync mode dialog in ui/CommunityRenderer.lua
-- uses it: its ring, and its dot only while checked), so a choice never reads
-- as a square check box and no texture path is assumed here. It takes no
-- mouse: the row stays the one click target, and each render sets the mark
-- checked for the one choice only. The client's radio art is NOT RUN here.
local function NewRow()
    local b = NewButton()
    b.desc = b:CreateFontString(nil, 'OVERLAY', FONTS.body)
    b.desc:SetJustifyH('LEFT'); b.desc:SetJustifyV('TOP')
    b.radio = CreateFrame('CheckButton', nil, b, 'UIRadioButtonTemplate')
    b.radio:SetSize(16, 16)
    b.radio:EnableMouse(false)
    local theme = Nexus.Theme
    if theme and theme.Exempt then theme.Exempt(b.radio) else b.radio._nexusThemeExempt = true end
    b.radio:Hide()
    b.extra = {b.desc, b.radio}
    return b
end

local function Measure(font, str, w)
    local metrics = Nexus.LayoutMetrics
    local measured = 0
    if font then
        font:SetWidth(w)
        if type(font.SetWordWrap) == 'function' then font:SetWordWrap(true) end
        font:SetHeight(0)
        if type(font.GetStringHeight) == 'function' then
            local ok, h = pcall(font.GetStringHeight, font)
            if ok and type(h) == 'number' and h > 0 and h < math.huge then measured = h end
        end
    end
    if metrics and type(metrics.TextRows) == 'function' and type(metrics.ConservativeText) == 'function' then
        local scale = type(metrics.RuntimeMetrics) == 'function' and metrics.RuntimeMetrics() or 1
        local _, line = metrics.ConservativeText(scale)
        measured = math.max(measured, metrics.TextRows(str, w, scale) * line)
    end
    return math.ceil(measured > 0 and measured or 14)
end

local function Row(spec, x, y, w)
    local b = Take('row', NewRow)
    Arm(b, spec)
    local inset = spec.radio ~= nil and 28 or 10
    local tw = math.max(40, w - inset - 8)
    local font = type(b.GetFontString) == 'function' and b:GetFontString() or nil
    local th = math.min(BLOCK_MAX, Measure(font, spec.label or '', tw))
    if font then
        font:ClearAllPoints()
        font:SetPoint('TOPLEFT', b, 'TOPLEFT', inset, -6)
        font:SetJustifyH('LEFT')
        font:SetHeight(th)
    end
    local dh = 0
    local desc = spec.desc or ''
    b.desc:SetText(desc)
    if desc ~= '' then
        b.desc:ClearAllPoints()
        b.desc:SetPoint('TOPLEFT', b, 'TOPLEFT', inset, -8 - th)
        local dc = spec.descColor or MUTED
        b.desc:SetTextColor(dc[1], dc[2], dc[3])
        local metrics = Nexus.LayoutMetrics
        if metrics and type(metrics.WrapHeight) == 'function' then dh = metrics.WrapHeight(b.desc, tw, 12, BLOCK_MAX)
        else b.desc:SetWidth(tw); b.desc:SetHeight(14); dh = 14 end
        b.desc:Show()
        order[#order + 1] = b.desc
    end
    local h = math.max(spec.radio ~= nil and 30 or 26, th + dh + (dh > 0 and 14 or 12))
    b:SetSize(w, h)
    b:ClearAllPoints()
    b:SetPoint('TOPLEFT', frame, 'TOPLEFT', x, y)
    if spec.radio ~= nil then
        -- The round mark's dot reads as chosen without colour (NewRow).
        b.radio:ClearAllPoints(); b.radio:SetPoint('TOPLEFT', b, 'TOPLEFT', 7, -7)
        b.radio:SetChecked(spec.radio == true)
        if spec.enabled == false then b.radio:Disable() else b.radio:Enable() end
        b.radio:Show()
    else b.radio:Hide() end
    local theme = Nexus.Theme
    if theme and theme.SetSelected then theme.SetSelected(b, spec.radio == true or spec.selected == true) end
    return h
end

-- A status kind's glyph and word: the copy's, else this file's (EXTRA).
local function Status(kind)
    local c = Copy().status or {}
    return c[kind] or EXTRA.status[kind] or c['not'] or {glyph = '?', word = '?'}
end

-- A checklist row's marker (owner-approved usability item 13, 2026-10-30):
-- the status kind's own glyph for every row, the summary row too (never a
-- step number), beside the row's status word. One glyph language across the
-- checklist, the outcome slot and the summary icons; never colour alone.
local function Marker(c, kind)
    local st = (c.status or {})[kind]
    return (st and st.glyph) or Status(kind).glyph or '?'
end

-- A status icon: the state's own glyph in the 12 px font inside a 14 px mark
-- drawn with the solid texture, filled for Done - confirmed and outlined for
-- every other state. Each state has its own printable ASCII glyph (the
-- Readout rule), so the icons differ without colour; no icon texture of the
-- client is assumed. Native glyph pixels are NOT RUN.
local ICON = 14
local function StatusIcon(kind, x, y)
    local color = COLOR[kind] or MUTED
    local solid = kind == 'verified'
    if solid then Fill(x, y, ICON, ICON, color, 0.95)
    else
        Fill(x, y, ICON, 1, color, 0.95); Fill(x, y - ICON + 1, ICON, 1, color, 0.95)
        Fill(x, y, 1, ICON, color, 0.95); Fill(x + ICON - 1, y, 1, ICON, color, 0.95)
    end
    Text(Status(kind).glyph or '?', x, y - 1, ICON, 'head', solid and {0.06, 0.04, 0.03} or color, 'CENTER')
end

-- A status word's width in the conservative text model at the current font
-- scale (its 10 px character width scaled to the 12 px font), up to maxW; a
-- longer word wraps under itself.
local function WordWidth(str, maxW)
    local metrics = Nexus.LayoutMetrics
    local char = metrics and metrics.ConservativeText and metrics.ConservativeText(metrics.RuntimeMetrics and metrics.RuntimeMetrics() or 1) or 7
    local length = #(tostring(str or ''):gsub('[\128-\191]', ''))
    return math.max(24, math.min(maxW or CW, math.ceil(length * char * 1.2)))
end

-- Go to step on a summary row: the design's small Go at the row's right end,
-- in the link look of Skip for now with the 12 px font, sized to its label
-- and right-aligned at `right`. It only moves the guide. Returns its width.
local GO_H = 18
local function NewGoLink()
    local b = FooterAction('link')
    for _, line in ipairs({b.underline, b.underlineHover}) do
        line:ClearAllPoints(); line:SetPoint('BOTTOM', b, 'BOTTOM', 0, 2)
    end
    return b
end
local function GoLink(label, act, right, y, maxW)
    local b = Take('golink', NewGoLink)
    Arm(b, {label = label, act = act})
    b:SetHeight(GO_H)
    local metrics = Nexus.LayoutMetrics
    local w = metrics and metrics.FitButtonWidth and metrics.FitButtonWidth(b, 40, maxW or CW) or 80
    -- The underline spans the text (FooterButton's rule for Skip for now).
    local ok, tw = pcall(b.GetTextWidth, b)
    tw = ok and tonumber(tw) or nil
    if not (tw and tw > 0 and tw < math.huge) then tw = w - 24 end
    tw = math.max(1, math.min(w - 8, math.ceil(tw)))
    b.underline:SetWidth(tw); b.underlineHover:SetWidth(tw)
    -- The design's amber link, not the footer link's grey.
    b.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3]); Paint(b.underline, GOLD)
    b:ClearAllPoints()
    b:SetPoint('TOPLEFT', frame, 'TOPLEFT', right - w, y)
    return w
end

-- The design's desktop window where the visible UI holds it (with the same
-- margin LayoutMetrics.FitToScreen keeps), else the compact window. An
-- implausibly small or unreadable UI size keeps the compact window.
local function WideFits()
    if not UIParent then return false end
    local okW, screenW = pcall(UIParent.GetWidth, UIParent)
    local okH, screenH = pcall(UIParent.GetHeight, UIParent)
    screenW, screenH = okW and tonumber(screenW) or nil, okH and tonumber(screenH) or nil
    if not (screenW and screenH) or screenH < 480 then return false end
    local metrics = Nexus.LayoutMetrics
    local scale = metrics and type(metrics.RuntimeMetrics) == 'function' and metrics.RuntimeMetrics() or 1
    return screenW >= ((tonumber(scale) or 1) >= 1.2 and WIDE.needLarge or WIDE.need)
end

------------------------------------------------------------------------
-- Step status (one vocabulary for the rail, checklist, chip and summary).
------------------------------------------------------------------------
local function StepStatus(g, s, ctx, id)
    local wd = Copy().words or {}
    local w = g.StepId() == id and 'waiting' or 'not'
    if id == 'welcome' then
        if s.path then return 'verified', wd.chosen end
        return w
    elseif id == 'wishlist' then
        if s.wishlist then return 'verified', wd.chosen end
        if s.draft then return 'waiting', wd.draft end
        local seen = s.saveSeen and s.saveSeen.saveKind
        if seen == 'uncertain' then return 'unavailable' end
        if seen then return 'rejected' end
        if s.skipped.wishlist then return 'skipped' end
        return w
    elseif id == 'target' then
        if ctx.facts and ctx.facts.canContinue then return 'verified', wd.chosen end
        -- Chosen, but the chooser cannot reach it yet (an empty slot, or a
        -- Saved Build that is not active): it still needs the player.
        if ctx.facts and (ctx.facts.ready or ctx.facts.empty) then return 'waiting' end
        if s.skipped.target then return 'skipped' end
        if g.StepId() == 'target' and not ctx.targets then return 'unavailable' end
        return w
    elseif id == 'assign' then
        local st = ctx.assign.state
        if st == 'verified' then return 'verified' end
        if st == 'observed' then return 'verified', wd.linked end
        if s.skipped.assign and (st == 'none' or st == 'ready' or st == 'pending') then return 'skipped' end
        if st == 'pending' then return 'waiting' end
        if st == 'none' or st == 'ready' then return w end
        if st == 'refused' then return 'rejected' end
        if st == 'cancelled' then return 'rejected', wd.cancelled end
        if st == 'unknown' then return 'unavailable' end
        return 'stale'
    elseif id == 'manual' then
        if s.manualAck then return 'verified', wd.tried end
        if s.skipped.manual then return 'skipped' end
        return w
    elseif id == 'auto' then
        if s.autoKept == 'unknown' then return 'stale', wd.leftUnknown end
        if s.autoKept then return 'verified', s.autoKept == 'on' and wd.leftOn or wd.leftOff end
        if ctx.auto == 'unknown' then return 'stale', wd.modeUnknown end
        if s.skipped.auto then return 'skipped' end
        return w
    end
    return w, g.StepId() == 'summary' and wd.review or wd.summary
end

------------------------------------------------------------------------
-- Step bodies. Each returns the y below its last element.
------------------------------------------------------------------------
local VIEW = {}

local function Notes(y, extra)
    for _, line in ipairs(extra or {}) do
        if line and line ~= '' then y = y - Text(line, PAD, y, CW, 'body', GOLD) - GAP end
    end
    return y
end

-- The step's head in the Setup Alternative order: its title, one WHY THIS
-- MATTERS line, then the DO THIS label above the step's action. The step is
-- the one U.Render is drawing (view.id).
local function Head(title, y)
    local c = Copy()
    y = y - Text(title, PAD, y, CW, 'title', GOLD) - GAP
    local why = (c.why or {})[view.id]
    if why and why ~= '' then
        y = y - Text(c.whyLabel or 'WHY THIS MATTERS', PAD, y, CW, 'small', MUTED) - 2
        y = y - Text(why, PAD, y, CW, 'body', TEXT) - GAP
    end
    return y - Text(c.doLabel or 'DO THIS', PAD, y, CW, 'small', MUTED) - 4
end

-- The one Wishlist this step shows as chosen: the chosen card's own record,
-- except a listed choice set aside while the paste field is the chosen way.
-- The status line and the footer's Selected name both read this, so they can
-- never name different Wishlists.
local function ShownWishlist(s)
    local w = s.wishlist
    return w and not (view.import.open and w.source ~= 'saved') and w or nil
end

function VIEW.welcome(g, s, ctx, c, y)
    local t = c.welcome or {}
    y = Head(s.replay and t.titleReplay or t.title, y)
    y = y - Text(s.replay and t.bodyReplay or t.body, PAD, y, CW, 'body', TEXT) - GAP
    for _, p in ipairs(t.paths or {}) do
        local id = p.id
        y = y - Row({label = p.title, desc = p.desc, radio = s.path == id,
            act = function() note = nil; g.SetPath(id) end}, PAD, y, CW) - 4
    end
    -- The navigation safety words are the outcome slot's WHAT YOU WILL SEE
    -- line below (expect.welcome), said once, not a second line here.
    return y - 4
end

-- The last check's outcome: edge and fill colours, its head line and the
-- lines under it. Accepted reads the code only; it is never a chosen or
-- saved Wishlist.
local function ImportOutcome(r, t)
    if r.state == 'accepted' then
        local lines = {t.importOkBody}
        if r.needsRoles then lines[#lines + 1] = t.importRoles end
        if r.suspended then lines[#lines + 1] = t.importSuspended end
        return COLOR.verified, {0.07, 0.13, 0.08},
            Fmt(t.importOk, r.name and Name(r.name) or t.importUnnamed, r.entries or 0, r.rolled or 0, r.locked or 0), lines
    elseif r.state == 'rejected' then
        return COLOR.rejected, {0.16, 0.07, 0.06}, t.importBad,
            {r.reason == 'long' and Fmt(t.importLong, r.limit or 0) or t.importBadBody}
    end
    return COLOR.unavailable, {0.13, 0.1, 0.16}, r.state == 'empty' and t.importEmpty or t.importUnavailable, {}
end

-- The design's paste field, Check code and inline outcome. Check code is the
-- filled action until a code reads as one; then Open it as a draft is. Once
-- a draft or a save of this step is reported, its own status line (below the
-- choices) speaks instead of the check.
local function ImportPanel(s, c, y)
    local t, b, imp = c.wishlist or {}, c.buttons or {}, view.import
    local x, w = PAD + 8, CW - 16
    y = y - Text(t.importLabel, x, y, w, 'small', MUTED) - 4
    local box = frame.importBox
    if box:GetText() ~= imp.text then box._nexusSyncing = true; box:SetText(imp.text); box._nexusSyncing = nil end
    box:ClearAllPoints(); box:SetPoint('TOPLEFT', frame, 'TOPLEFT', x, y); box:SetSize(w, 24)
    box:Show()
    y = y - 24 - 6
    local r = imp.result
    local accepted = r and r.state == 'accepted'
    y = y - Actions({{label = b.checkCode, primary = not accepted, act = function() note = nil; U.CheckImport() end},
        accepted and {label = b.openDraft, primary = true, enabled = not r.suspended, act = function() U.RouteImport() end}},
        x, y, w) - 6
    if r and not (s.draft or (s.wishlist and s.wishlist.source == 'saved')) then
        local edge, fill, head, lines = ImportOutcome(r, t)
        local top, h = y, 6
        h = h + Text(head, x + 8, y - h, w - 16, 'head', edge) + 3
        for _, line in ipairs(lines) do h = h + Text(line, x + 8, y - h, w - 16, 'body', TEXT) + 3 end
        Box(x, top, w, h + 4, edge, fill)
        y = y - h - 4 - 6
    end
    return y - 4
end

-- The editor's read-only fact (WishlistEditor.SuspendedPlanDraft): an unsaved
-- Plan draft set aside in another workspace, or nil.
local function SuspendedDraft()
    local editor = Nexus.WishlistEditor
    if not (editor and type(editor.SuspendedPlanDraft) == 'function') then return nil end
    local ok, d = pcall(editor.SuspendedPlanDraft)
    return ok and type(d) == 'table' and d or nil
end

-- Start an empty Wishlist asked while an unsaved Plan draft is set aside
-- (U.RouteEditor): the step's one answer, said here instead of the editor's
-- refusal in chat, with one action (U.RoutePlan): Return to Plan draft while
-- it can be reopened as it is, else Keep or discard Plan draft, which only
-- asks the editor's question (its Discard opens Plan without that draft).
-- The fact is read again on every render; the card goes with the draft.
local function PlanDraftCard(c, y)
    if not view.planDraft then return y end
    local d = SuspendedDraft()
    if not d then view.planDraft = false; return y end
    local t, b = c.wishlist or {}, c.buttons or {}
    local top, h = y, 8
    h = h + Text(t.planHead, PAD + 8, y - h, CW - 16, 'head', COLOR.waiting) + 3
    h = h + Text(t.planBody, PAD + 8, y - h, CW - 16, 'body', TEXT) + 3
    h = h + Text(d.sameContext and t.planSame or t.planContext, PAD + 8, y - h, CW - 16, 'body', TEXT) + 4
    -- Pick a saved Wishlist only closes this note: the draft stays as it is.
    h = h + Actions({{label = d.sameContext and b.returnPlan or b.planChanged or b.returnPlan, primary = true,
        act = function() U.RoutePlan() end},
        {label = b.dismissDraft, act = function() view.planDraft = false; note = nil end}}, PAD + 8, y - h, CW - 16) + 8
    Box(PAD, top, CW, h, COLOR.waiting, {0.12, 0.1, 0.06})
    return y - h - GAP
end

function VIEW.wishlist(g, s, ctx, c, y)
    local t, n = c.wishlist or {}, c.notes or {}
    local imp = view.import
    y = Head(t.title, y)
    -- Wishlist versus Saved Build: two concept cards side by side.
    local half = math.floor((CW - 1) / 2)
    local function Card(x, head, body)
        local h1 = Text(head, x + 8, y - 6, half - 16, 'head', GOLD)
        local h2 = Text(body, x + 8, y - 10 - h1, half - 16, 'body', TEXT)
        return h1 + h2 + 16
    end
    local hA = Card(PAD, t.conceptWish, t.conceptWishBody)
    local hB = Card(PAD + half + 1, t.conceptBuild, t.conceptBuildBody)
    local ch = math.max(hA, hB)
    Box(PAD, y, half, ch, {0.42, 0.3, 0.18}, {0.12, 0.09, 0.07})
    Box(PAD + half + 1, y, half, ch, {0.42, 0.3, 0.18}, {0.12, 0.09, 0.07})
    y = y - ch - GAP
    local list = g.WishlistOptions()
    local w = s.wishlist
    -- The one listed row that is the choice itself (core ChosenOption): copies
    -- of the same Echoes share a key, so a key alone would mark each of them.
    local chosen = type(g.ChosenOption) == 'function' and g.ChosenOption(list) or nil
    -- What Nexus follows now (core CurrentAssignment, read for this render):
    -- its one listed row says Assigned now. That is the game's assignment,
    -- not this step's choice: the row is not selected, chosen or done by it.
    local cur = ctx.current
    local now, matches
    if cur and type(g.CurrentOption) == 'function' then now, matches = g.CurrentOption(list, cur) end
    local where = cur and cur.destination and TargetLabel(cur.destination, cur.destName) or nil
    local more
    for i, cand in ipairs(list or {}) do
        if i > 8 then more = t.more; break end
        -- One choice at a time: while the paste field is the chosen way, a
        -- listed Wishlist shows unchosen (Continue waits on the code; Render).
        local mine = chosen == i and not imp.open
        local desc = cand.lockEvidenceStatus == 'unavailable' and t.needsRoles or t.yours
        local current = now == i
        if current then desc = Fmt(Words('wishlist', 'assignedNow'), where or '?') .. '\n' .. (desc or '') end
        y = y - Row({label = Name(cand.name), radio = mine and true or false,
            desc = desc, descColor = current and COLOR.observed or nil,
            act = function()
                imp.open, view.planDraft = false, false
                local ok, why = g.ChooseWishlist(cand); note = (not ok) and n[why] or nil
            end}, PAD, y, CW) - 4
    end
    y = y - Row({label = t.importTitle, desc = t.importDesc, radio = imp.open,
        act = function() imp.open, view.planDraft = true, false; note = nil end}, PAD, y, CW) - 4
    if imp.open then y = ImportPanel(s, c, y) end
    -- An unsaved Plan draft set aside: the row says it is unavailable before
    -- any click; a click still only shows the one note (U.RouteEditor).
    local blocked = SuspendedDraft() ~= nil
    y = y - Row({label = blocked and t.createBlocked or t.createTitle,
        desc = blocked and t.createBlockedDesc or t.createDesc, radio = false,
        act = function() imp.open = false; U.RouteEditor('new') end}, PAD, y, CW) - GAP
    y = PlanDraftCard(c, y)
    -- What Nexus follows now when no shown row can carry it: unread (never
    -- guessed), shared by several listed rows (none is picked), or not among
    -- the rows shown. Nothing assigned, or an empty active build, says nothing.
    if cur and cur.state == 'unknown' then
        y = y - Text(Words('wishlist', 'assignedNowUnknown'), PAD, y, CW, 'body', COLOR.unavailable) - GAP
    elseif list and cur and (cur.state == 'assigned' or cur.state == 'roles') and not (now and now <= 8) then
        local line = (matches or 0) > 1 and Words('wishlist', 'assignedNowAmbiguous') or Words('wishlist', 'assignedNowLine')
        y = y - Text(Fmt(line, where or '?', Name(cur.name)), PAD, y, CW, 'body', COLOR.observed) - GAP
    end
    -- A kept Wishlist that several listed ones match (core Readopt): none
    -- was taken, and the step says so until the player chooses.
    if s.reselect and not w then y = y - Text(t.reselect, PAD, y, CW, 'body', COLOR.waiting) - GAP end
    local status, color
    -- A listed choice set aside for the paste field is not shown as chosen.
    local shown = ShownWishlist(s)
    if shown then status, color = Fmt(w.source == 'saved' and t.saved or t.chosen, Name(w.name)), COLOR.verified
    elseif s.draft then status, color = t.draft, COLOR.waiting
    elseif s.saveSeen then status, color = t[s.saveSeen.saveKind] or t.notSaved, COLOR.rejected end
    if status then
        local kind = shown and 'verified' or (s.draft and 'waiting') or 'rejected'
        local glyph = ((c.status or {})[kind] or {}).glyph or ''
        y = y - Text(glyph .. ' ' .. status, PAD, y, CW, 'body', color) - GAP
    end
    if not list then more = t.notLoaded elseif #list == 0 then more = t.none end
    return Notes(y, {more})
end

function VIEW.target(g, s, ctx, c, y)
    local t, b, n = c.target or {}, c.buttons or {}, c.notes or {}
    y = Head(t.title, y)
    local opts = ctx.targets
    if not opts then
        local top = y
        local h = Text(t.unavailable, PAD + 8, y - 8, CW - 16, 'head', COLOR.unavailable)
        h = h + Text(t.unavailableBody, PAD + 8, y - 12 - h, CW - 16, 'body', TEXT)
        local ah = Actions({{label = b.retry, primary = true, act = function() note = nil end}}, PAD + 8, y - 18 - h, CW - 16)
        Box(PAD, top, CW, h + ah + 26, COLOR.unavailable, {0.13, 0.1, 0.16})
        return y - h - ah - 26 - GAP
    end
    y = y - Text(t.read, PAD, y, CW, 'muted', MUTED) - GAP
    for _, o in ipairs(opts) do
        local dest = o.destination
        local desc
        if o.blocked then desc = t[o.blocked] or o.blocked
        elseif o.empty then desc = t.emptyOffer or t.empty
        elseif dest == 'first' then desc = t.firstDesc
        else
            local r = g.ReadAssignment(dest)
            desc = (r.state == 'assigned' or r.state == 'roles') and Fmt(t.follows, Name(r.name))
                or (r.state == 'none' and t.followsNone) or t.followsUnknown
        end
        if o.selected then desc = (t.active or '') .. ' - ' .. (desc or '') end
        local mine = s.target and s.target.destination == dest
        y = y - Row({label = TargetLabel(dest, o.name), desc = desc, radio = mine and true or false, enabled = not o.blocked,
            act = function() local ok, why = g.ChooseTarget(dest); note = (not ok) and n[why] or nil end}, PAD, y, CW) - 4
    end
    y = y - 4
    local f = ctx.facts
    if f then
        local label = TargetLabel(f.destination, f.name)
        local wish = s.wishlist and Name(s.wishlist.name) or nil
        local lines = {}
        if f.empty then lines = {Fmt(t.cEmpty, label), t.cEmptySave, t.cReturn}
        elseif f.read.state == 'unknown' then lines = {t.cUnknown}
        elseif f.already then lines = {Fmt(t.cAlready, label, Name(f.read.name)), t.cAlready2}
        elseif f.replaces then
            lines = {Fmt(t.cReplace, label, Name(f.read.name), wish or '?'), Fmt(t.cKept, Name(f.read.name)), t.cEchoes}
            if f.destination == opts.journal then lines[#lines + 1] = t.cActive end
            if ctx.auto == 'on' then lines[#lines + 1] = t.cAutoOn end
            if f.confirmed then lines[#lines + 1] = t.accepted end
        else lines = {t.cNew, t.cEchoes} end
        -- The route (core TargetFacts): a ready Saved Build the Echo Journal
        -- chooser does not assign to now keeps Continue waiting, and says
        -- what the player does in the game to get there. Nothing here saves,
        -- loads or activates a slot.
        local needsBuilds = false
        if not f.empty and f.read.state ~= 'unknown' and not f.already then
            if f.route == 'select' then
                lines[#lines + 1] = Fmt(t.cSelect, label)
                lines[#lines + 1] = t.cSelectHow
                lines[#lines + 1] = t.cReturn
                needsBuilds = true
            elseif f.route == 'first' then
                lines[#lines + 1] = t.cFirst
            end
        end
        if f.empty then needsBuilds = true end
        local top, h = y, 8
        h = h + Text(Fmt(t.ifAssign, wish or Name(nil)), PAD + 8, y - h, CW - 16, 'head', GOLD) + 4
        for _, line in ipairs(lines) do
            h = h + Text('- ' .. line, PAD + 8, y - h, CW - 16, 'body', TEXT) + 3
        end
        if f.replaces and not f.confirmed then
            h = h + 4 + Actions({{label = b.cancel, act = function() g.CancelReplace() end},
                {label = b.replace, primary = true, act = function() g.ConfirmReplace() end}}, PAD + 8, y - h - 4, CW - 16)
        elseif needsBuilds then
            -- The game's own My Builds page, as the panel's My Builds button
            -- opens it; the coach steps aside and is reopened by the player.
            h = h + 4 + Actions({{label = b.openBuilds, primary = true, act = function() U.RouteBuilds() end}},
                PAD + 8, y - h - 4, CW - 16)
        end
        Box(PAD, top, CW, h + 8, {0.7, 0.42, 0.18}, {0.14, 0.1, 0.07})
        y = y - h - 8 - GAP
    end
    return y
end

function VIEW.assign(g, s, ctx, c, y)
    local t, b, sb = c.assign or {}, c.buttons or {}, c.target or {}
    y = Head(t.title, y)
    local f, st = ctx.facts, ctx.assign
    -- A target that is not ready (its read back unknown, or a replacement not
    -- accepted) takes no new assignment. An assignment already made whose
    -- result is unknown or stale (core AssignStatus: only with a receipt) is
    -- still shown as that result, with Check again only; the target before
    -- any assignment stays the prerequisite card.
    local result = st.state == 'unknown' or st.state == 'stale'
    if not (s.wishlist and f and (f.ready or result)) then
        local top = y
        local h = Text(t.missing, PAD + 8, y - 8, CW - 16, 'body', TEXT)
        local links = {}
        if not s.wishlist then links[#links + 1] = {label = b.goWishlist, act = function() g.GoTo('wishlist') end} end
        if not (f and f.ready) then links[#links + 1] = {label = b.goTarget, act = function() g.GoTo('target') end} end
        local ah = Actions(links, PAD + 8, y - 14 - h, CW - 16)
        Box(PAD, top, CW, h + ah + 22, {0.42, 0.34, 0.26}, {0.1, 0.08, 0.06})
        return y - h - ah - 22 - GAP
    end
    local dest, wish = TargetLabel(f.destination, f.name), Name(s.wishlist.name)
    -- The pairing being assigned, with its one-line consequence (unknown
    -- while the slot cannot be read, never guessed).
    local short = f.read.state == 'unknown' and sb.cUnknown or f.already and sb.shortAlready
        or f.replaces and Fmt(sb.shortReplace, Name(f.read.name)) or sb.shortNew
    local top, h = y, 6
    h = h + Text(wish .. '  ->  ' .. dest, PAD + 8, y - h, CW - 16, 'head', GOLD) + 2
    h = h + Text(short, PAD + 8, y - h, CW - 16, 'body', MUTED) + 6
    Box(PAD, top, CW, h, {0.42, 0.32, 0.22}, {0.12, 0.09, 0.07})
    y = y - h - GAP
    local open = {label = b.open, primary = true, act = function() U.RouteChooser() end}
    local again = {label = b.openAgain, primary = true, act = function() U.RouteChooser() end}
    local check = {label = b.check, act = function() note = nil end}
    -- With no answer, or a slot changed after the check, the design's one
    -- action is the filled Check again: it reads the slot again and arms,
    -- opens and assigns nothing. The chooser stays on the ready, waiting and
    -- declined cards (guarded by ArmAssign); Skip for now is in the footer.
    local checkFirst = {label = b.check, primary = true, act = check.act}
    local function Result(edge, fill, head, body, actions)
        local rt, rh = y, 8
        rh = rh + Text(head, PAD + 8, y - rh, CW - 16, 'head', edge) + 3
        if body and body ~= '' then rh = rh + Text(body, PAD + 8, y - rh, CW - 16, 'body', TEXT) + 4 end
        if actions then rh = rh + 4 + Actions(actions, PAD + 8, y - rh - 4, CW - 16) end
        Box(PAD, rt, CW, rh + 8, edge, fill)
        y = y - rh - 8 - GAP
    end
    local state = st.state
    if state == 'ready' then
        y = y - Actions({open}, PAD, y, CW) - 6
        y = y - Text(Fmt(t.openNote, wish), PAD, y, CW, 'body', MUTED) - GAP
    elseif state == 'pending' then
        Result(COLOR.waiting, {0.12, 0.1, 0.06}, Fmt(t.waiting, wish), nil, {check, again})
    elseif state == 'verified' then
        local rt, rh = y, 6
        Text(t.verified, PAD + 8, y - rh, CW / 2, 'head', COLOR.verified)
        rh = rh + Text(t.readback, PAD + CW / 2, y - rh - 2, CW / 2 - 8, 'small', HELP_BLUE, 'RIGHT') + 8
        local req = s.request
        local rows = {{t.evCharacter, ctx.character}, {t.evBuild, dest}, {t.evWishlist, wish},
            {t.evRequest, st.origin == 'save' and t.evSave or Fmt(t.evRequestValue, req and req.serial or 0)},
            {t.evRead, t.evReadValue}}
        for _, r in ipairs(rows) do
            Fill(PAD + 1, y - rh + 2, CW - 2, 1, COLOR.verified, 0.25)
            local kh = Text(r[1], PAD + 8, y - rh - 2, 100, 'body', MUTED)
            local vh = Text(r[2], PAD + 112, y - rh - 2, CW - 150, 'body', TEXT)
            Text('+', PAD + CW - 20, y - rh - 2, 12, 'body', COLOR.verified)
            rh = rh + math.max(kh, vh) + 6
        end
        Box(PAD, rt, CW, rh + 4, COLOR.verified, {0.07, 0.13, 0.08})
        y = y - rh - 4 - GAP
    elseif state == 'observed' then
        Result(COLOR.verified, {0.07, 0.13, 0.08}, t.observed, Fmt(t.observedBody, dest, wish), {check})
    elseif state == 'refused' then
        Result(COLOR.rejected, {0.16, 0.07, 0.06}, t.rejected, Fmt(t.rejectedBody, Name(st.reason)), {again})
    elseif state == 'cancelled' then
        Result(COLOR.rejected, {0.16, 0.07, 0.06}, t.cancelled, t.cancelledBody, {again})
    elseif state == 'unknown' then
        Result(COLOR.unavailable, {0.13, 0.1, 0.16}, t.unavailable, t.unavailableBody, {checkFirst})
    else
        local body = Fmt((t.staleBody or {})[state] or (t.staleBody or {}).stale, dest,
            Name(state == 'other' and st.name or st.readName))
        local recheck = state == 'stale' or state == 'changed'
        Result(COLOR.stale, {0.06, 0.13, 0.14}, t.stale, body, recheck and {checkFirst} or {check, again})
    end
    return y
end

function VIEW.manual(g, s, ctx, c, y)
    local m = c.sim or {}
    y = Head(m.title, y)
    y = y - Text(m.body, PAD, y, CW, 'body', TEXT) - GAP
    local top = y
    -- The simulated preview: a labelled frame that stays visible.
    Fill(PAD + 1, y - 1, CW - 2, 18, {0.18, 0.26, 0.42}, 0.95)
    Text(m.banner, PAD + 8, y - 4, CW - 16, 'small', {0.92, 0.95, 1})
    local iy = y - 26
    local cards = m.cards or {}
    local cw = math.floor((CW - 16 - 2 * 6) / 3)
    local tallest = 0
    for i, card in ipairs(cards) do
        local idx = i
        local h = Row({label = card.name, desc = (card.desc or '') .. (i == g.SIM_ANSWER and ('\n' .. (m.mark or '')) or ''),
            selected = s.manualPick == i, act = function() g.SimPick(idx) end}, PAD + 8 + (i - 1) * (cw + 6), iy, cw)
        tallest = math.max(tallest, h)
    end
    iy = iy - tallest - GAP
    iy = iy - Text(m.why, PAD + 8, iy, CW - 16, 'body', TEXT) - 4
    if s.manualPick then
        local name = (cards[s.manualPick] or {}).name or '?'
        local msg = Fmt(m.picked, name) .. (s.manualPick == g.SIM_ANSWER and (m.match or '') or (m.differ or ''))
        if ctx.auto == 'on' then msg = msg .. (m.autoOn or '') end
        iy = iy - Text(msg, PAD + 8, iy, CW - 16, 'body', HELP_BLUE) - 4
    end
    Box(PAD, top, CW, top - iy + 4, {0.4, 0.52, 0.8}, {0.07, 0.09, 0.14})
    return iy - 4 - GAP
end

function VIEW.auto(g, s, ctx, c, y)
    local a, b = c.auto or {}, c.buttons or {}
    y = Head(a.title, y)
    local mode = ctx.auto
    local unknown = mode == 'unknown'
    local top, h = y, 8
    local dot = unknown and COLOR.stale or mode == 'on' and {1, 0.5, 0.3} or {0.62, 0.6, 0.58}
    Fill(PAD + 10, y - 12, 10, 10, dot, 1)
    h = h + Text(unknown and a.modeUnknown or (mode == 'on' and a.modeOn or a.modeOff), PAD + 28, y - h, CW - 36, 'head', TEXT) + 2
    h = h + Text(unknown and a.subUnknown or a.subRead, PAD + 28, y - h, CW - 36, 'body', MUTED) + 8
    Box(PAD, top, CW, h, {0.42, 0.34, 0.26}, {0.12, 0.09, 0.07})
    y = y - h - GAP
    y = y - Text(a.lead, PAD, y, CW, 'body', TEXT) - GAP
    y = y - Actions({{label = view.autoMore and b.autoLess or b.autoMore,
        act = function() view.autoMore = not view.autoMore end}}, PAD, y, CW) - 4
    if view.autoMore then
        local mh = Text(a.moreOn, PAD + 10, y, CW - 10, 'body', TEXT) + 3
        mh = mh + Text(a.moreOff, PAD + 10, y - mh, CW - 10, 'body', TEXT)
        Fill(PAD, y, 2, mh, GOLD, 0.6)
        y = y - mh - GAP
    end
    if s.autoKept then
        local kept = s.autoKept == 'unknown' and a.keptUnknown or s.autoKept == 'on' and a.keptOn or a.keptOff
        local kt = y
        local kh = Text(kept, PAD + 8, y - 6, CW - 16, 'body', TEXT) + 12
        Box(PAD, kt, CW, kh, COLOR.verified, {0.07, 0.13, 0.08})
        y = y - kh - GAP
    end
    if view.review then y = y - Text(a.reviewNote, PAD, y, CW, 'body', HELP_BLUE) - GAP end
    local keep = {label = unknown and b.leave or Fmt(b.keep, mode == 'on' and 'ON' or 'OFF'), primary = true,
        act = function() g.KeepAuto(); g.Next() end}
    local review = unknown and {label = b.reread, act = function() view.review = false end}
        or {label = b.review, act = function()
            view.review = true
            if Nexus.Panel and Nexus.Panel.Show then Nexus.Panel.Show() end
        end}
    y = y - Actions({keep, review}, PAD, y, CW) - GAP
    return y
end

function VIEW.summary(g, s, ctx, c, y)
    local fin, b = c.finish or {}, c.buttons or {}
    local sm = ctx.summary
    local explore = s.path == 'explore'
    local title, sub
    if explore then title, sub = fin.titleExplore, fin.subExplore
    elseif sm.complete then title, sub = fin.titleDone, fin.subDone
    elseif sm.trueNow then title, sub = fin.titleDone, fin.subTrue
    else
        title = Fmt(fin.titleOpen, sm.open, sm.open == 1 and '' or 's')
        sub = ctx.kept == 'saved' and fin.subOpen or fin.subOpenSession or fin.subOpen
    end
    y = Head(title, y)
    y = y - Text(sub, PAD, y, CW, 'body', TEXT) - GAP
    local f, st = ctx.facts, ctx.assign
    local wishName = s.wishlist and Name(s.wishlist.name) or '?'
    local destName = f and TargetLabel(f.destination, f.name) or '?'
    local function Detail(id, kind)
        if explore and (id == 'wishlist' or id == 'target' or id == 'assign') then return fin.explore end
        if id == 'wishlist' then
            if s.wishlist then return Fmt(fin.wishDone, wishName) end
            if sm.wishlist == 'draft' then return fin.wishDraft end
            if sm.wishlist == 'partial' then return fin.wishPartial end
            if sm.wishlist == 'uncertain' then return fin.wishUncertain end
            return kind == 'skipped' and fin.wishSkipped or fin.wishNot
        elseif id == 'target' then
            if f and f.ready then return destName end
            return kind == 'skipped' and fin.targetSkipped or fin.targetNot
        elseif id == 'assign' then
            if st.state == 'verified' then return Fmt(fin.assignDone, destName, wishName) end
            if st.state == 'observed' then return Fmt(fin.assignTrue, destName, wishName) end
            if kind == 'skipped' then return fin.assignSkipped end
            if st.state == 'pending' then return fin.assignWaiting end
            if kind == 'rejected' then return fin.assignRejected end
            if kind == 'unavailable' then return fin.assignUnknown end
            if kind == 'stale' then return fin.assignStale end
            return fin.assignNot
        elseif id == 'manual' then
            if s.manualAck then return fin.manualDone end
            return kind == 'skipped' and fin.manualSkipped or fin.manualNot
        elseif id == 'auto' then
            if ctx.auto == 'unknown' then return fin.autoUnknown end
            return Fmt(fin.autoMode, ctx.auto == 'on' and 'ON' or 'OFF')
        end
    end
    local rowsTop = y
    for _, id in ipairs({'wishlist', 'target', 'assign', 'manual', 'auto'}) do
        local inPath = not explore or id == 'manual' or id == 'auto'
        local kind, word = StepStatus(g, s, ctx, id)
        if not inPath then kind, word = 'not', nil end
        if kind == 'waiting' and g.StepId() ~= id and id ~= 'assign' then kind = 'not' end
        if id == 'auto' and not s.autoKept and kind ~= 'stale' and kind ~= 'skipped' then
            kind, word = 'not', Fmt(fin.autoNotReviewed, ctx.auto == 'on' and 'ON' or 'OFF')
        end
        -- A link Nexus read back but this guide did not make (core
        -- AssignStatus observed) has its own icon, apart from Done - confirmed.
        if id == 'assign' and inPath and st.state == 'observed' then kind = 'observed' end
        local rt = y
        local half = math.floor(CW / 2)
        -- The design's summary row (Setup Alternative Step 7), one line
        -- across: the boxed icon, the step, its status word and a small Go,
        -- with the step's detail as a second muted line under the step (an
        -- adaptive wrap, not a second column). A long word or text wraps
        -- inside its own column, so nothing overlaps at larger text.
        local right, gw = PAD + CW - 6, 0
        if inPath and kind ~= 'verified' and kind ~= 'observed' and not (id == 'auto' and s.autoKept) then
            local target = id
            gw = GoLink(b.goStep, function() g.GoTo(target) end, right, y - 6, half)
        end
        local str = word or Status(kind).word or ''
        local wordRight = right - (gw > 0 and gw + 6 or 0)
        local ww = WordWidth(str, half - (gw > 0 and gw + 6 or 0))
        -- The word is drawn just before its icon's glyph (tests read them
        -- as one pair).
        local wh = Text(str, wordRight - ww, y - 8, ww, 'strong', COLOR[kind] or MUTED, 'RIGHT')
        local ix = PAD + 8
        StatusIcon(kind, ix, y - 6)
        local lx = ix + ICON + 8
        local lw = math.max(40, wordRight - ww - 8 - lx)
        local lh = Text((fin.rows or {})[id] or id, lx, y - 6, lw, 'head', TEXT)
        lh = lh + Text(Detail(id, kind), lx, y - 8 - lh, lw, 'body', MUTED) + 2
        local rh = math.max(lh, wh + 2, ICON, gw > 0 and GO_H or 0) + 10
        Fill(PAD + 1, y - rh, CW - 2, 1, {0.3, 0.24, 0.18}, 1)
        y = rt - rh
    end
    local sh = Text(fin.sent, PAD + 8, y - 6, CW - 16, 'muted', MUTED) + 12
    Box(PAD, rowsTop, CW, rowsTop - y + sh, {0.4, 0.32, 0.22}, {0.1, 0.08, 0.06}, 0.5)
    y = y - sh - GAP
    -- What the game follows now, read for this render (core
    -- CurrentAssignment), apart from the rows above: they are this guide's
    -- own progress, so "Not chosen in this guide" never contradicts a panel
    -- that shows an assignment. The note selects, completes and keeps
    -- nothing; a confirmed or already read link says it in its row instead.
    local cur = ctx.current
    if cur and not explore and not (sm.complete or sm.trueNow) then
        if cur.state == 'assigned' or cur.state == 'roles' then
            local where = cur.destination and TargetLabel(cur.destination, cur.destName) or '?'
            y = y - Text(Fmt(fin.currentNote, where, Name(cur.name)), PAD, y, CW, 'body', COLOR.observed) - GAP
        elseif cur.state == 'unknown' and fin.currentUnknown then
            y = y - Text(fin.currentUnknown, PAD, y, CW, 'body', COLOR.unavailable) - GAP
        end
    end
    -- Optional lessons: separate, never blocking setup.
    y = y - Text((fin.more or '') .. ' ' .. (fin.moreSub or ''), PAD, y, CW, 'body', TEXT) - 6
    for _, l in ipairs(fin.lessons or {}) do
        local id, open = l.id, view.lesson == l.id
        y = y - Row({label = l.title .. '  -  ' .. (open and b.hide or b.read),
            act = function() view.lesson = (view.lesson == id) and nil or id end}, PAD, y, CW) - 4
        if open then
            for _, line in ipairs(l.lines or {}) do y = y - Text(line, PAD + 10, y, CW - 10, 'body', TEXT) - 3 end
            y = y - 3 - Actions({{label = l.open, act = function() U.Lesson(id) end}}, PAD + 10, y - 3, CW - 10) - GAP
        end
    end
    y = y - Actions({{label = b.replay, act = function() note = nil; view.lesson, view.planDraft = nil, false; ResetImport(); g.Replay() end}}, PAD, y - 2, CW) - GAP
    return y
end

------------------------------------------------------------------------
-- Window.
------------------------------------------------------------------------
local function Character()
    local c = Copy()
    local okN, name, realm = pcall(function() return UnitName('player') end)
    if not okN or not name or name == '' then return c.charUnknown end
    if not realm or realm == '' then
        local okR, r = pcall(function() return GetRealmName and GetRealmName() end)
        realm = okR and r or nil
    end
    local okL, level = pcall(function() return UnitLevel and UnitLevel('player') end)
    local parts = {Name(name)}
    if realm and realm ~= '' then parts[#parts + 1] = Name(realm) end
    if okL and tonumber(level) and tonumber(level) > 0 then parts[#parts + 1] = 'Level ' .. tostring(level) end
    return table.concat(parts, ' - ')
end

-- Where the coach's top edge starts below the UI's top: where a full-height
-- (MAX_H) coach centred 40 px above the middle had it before, so the tallest
-- step opens where it did. The coach is held by its top (Setup Alternative:
-- the dialog is aligned at its top), so its header, Reference and X stay put
-- while a step, All steps or Reference changes the height below them.
local function TopOffset()
    local ok, h = pcall(UIParent.GetHeight, UIParent)
    h = ok and tonumber(h) or nil
    if not h or h < 480 then return 24 end
    return math.max(12, math.floor((h - math.min(MAX_H, h - 24)) / 2) - 40)
end

local function Ensure()
    if frame then return frame end
    frame = CreateFrame('Frame', 'NexusGuidedSetup', UIParent)
    frame:SetSize(W, MIN_H)
    frame:SetPoint('TOP', UIParent, 'TOP', 0, -TopOffset())
    frame:SetFrameStrata('DIALOG')
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag('LeftButton')
    frame:SetScript('OnDragStart', function(self) self:StartMoving() end)
    -- A moved coach is held again by its top-left corner where the player
    -- put it (the client may anchor a moved frame by another corner, which
    -- would move the header when the height changes). Its own scale's units.
    frame:SetScript('OnDragStop', function(self)
        self:StopMovingOrSizing()
        local okL, left = pcall(self.GetLeft, self)
        local okT, top = pcall(self.GetTop, self)
        left, top = okL and tonumber(left) or nil, okT and tonumber(top) or nil
        if left and top then
            self:ClearAllPoints()
            self:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', left, top)
        end
    end)
    -- The wheel scrolls a bounded body (U.ScrollWheel); otherwise it does nothing.
    frame:EnableMouseWheel(true)
    frame:SetScript('OnMouseWheel', function(_, delta) U.ScrollWheel(delta) end)
    frame:Hide()
    pcall(function()
        frame:SetBackdrop({bgFile = WHITE, edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border', edgeSize = 14,
            insets = {left = 4, right = 4, top = 4, bottom = 4}})
        frame:SetBackdropColor(0.06, 0.045, 0.035, 0.97)
        frame:SetBackdropBorderColor(0.75, 0.42, 0.18, 0.95)
    end)
    -- Fixed header: the diamond mark (a square: no rotation on 3.3.5a), the
    -- title, the character line, Help and close.
    frame.mark = Tex('ARTWORK')
    frame.mark:SetPoint('TOPLEFT', frame, 'TOPLEFT', PAD, -16); frame.mark:SetSize(12, 12)
    Paint(frame.mark, {0.82, 0.42, 0.16}); frame.mark:Show()
    frame.title = frame:CreateFontString(nil, 'OVERLAY', FONTS.title)
    frame.title:SetPoint('TOPLEFT', frame, 'TOPLEFT', PAD + 20, -12)
    frame.title:SetJustifyH('LEFT')
    frame.title:SetSize(CW - 130, 20)
    -- The character line wraps (the design's overflow-wrap); Render sizes the
    -- header to the title and this line at the current font.
    frame.char = frame:CreateFontString(nil, 'OVERLAY', FONTS.muted)
    frame.char:SetPoint('TOPLEFT', frame, 'TOPLEFT', PAD + 20, -32)
    frame.char:SetJustifyH('LEFT')
    frame.char:SetJustifyV('TOP')
    frame.char:SetSize(CW - 120, 14)
    local metrics = Nexus.LayoutMetrics
    if metrics and metrics.FullTextTooltip then frame.char._hit = metrics.FullTextTooltip(frame.char, frame) end
    frame.headLine = Tex('ARTWORK')
    frame.headLine:SetPoint('TOPLEFT', frame, 'TOPLEFT', 6, -52); frame.headLine:SetSize(W - 12, 1)
    Paint(frame.headLine, {0.45, 0.3, 0.16}); frame.headLine:Show()
    frame.help, frame.close = NewButton(), NewButton()
    frame.close:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -12, -14)
    frame.help:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -46, -14)
    frame.checklist = NewButton()
    -- Back is a themed secondary button; Skip for now and Continue keep the
    -- design's own looks (FooterAction), which the tree walk below leaves alone.
    frame.back, frame.skip, frame.next = NewButton(), FooterAction('link'), FooterAction('primary')
    -- Continue later (Setup Alternative): the same deliberate close as X.
    frame.later = FooterAction('link')
    frame.footLine = Tex('ARTWORK')
    local theme = Nexus.Theme
    if theme then
        if theme.StyleWindow then theme.StyleWindow(frame, 0.97) end
        if theme.StyleTree then theme.StyleTree(frame) end
        if theme.StyleLabel then theme.StyleLabel(frame.title, 'accent'); theme.StyleLabel(frame.char, 'muted') end
    end
    -- The Wishlist step's paste field (ImportPanel). It holds the import
    -- dialog's own limit, takes the keyboard only when clicked, and Enter
    -- checks; Escape gives the keyboard back. Typing only keeps the text in
    -- this session's view; a changed text drops the earlier check, which
    -- belongs to the exact text it read.
    local box = CreateFrame('EditBox', nil, frame)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextInsets(6, 6, 0, 0)
    local editor = Nexus.WishlistEditor
    box:SetMaxLetters(tonumber(editor and editor.IMPORT_MAX_LETTERS) or 4096)
    pcall(function()
        box:SetBackdrop({bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = {left = 1, right = 1, top = 1, bottom = 1}})
        box:SetBackdropColor(0.05, 0.04, 0.03, 1)
        box:SetBackdropBorderColor(0.42, 0.3, 0.18, 1)
    end)
    box:SetScript('OnTextChanged', function(self)
        if self._nexusSyncing then return end
        local text, imp = tostring(self:GetText() or ''), view.import
        if text == imp.text then return end
        imp.text = text
        if imp.result then imp.result, imp.checked = nil, nil; if frame:IsShown() then U.Render() end end
    end)
    box:SetScript('OnEnterPressed', function(self)
        self:ClearFocus(); note = nil; U.CheckImport()
        if frame:IsShown() then U.Render() end
    end)
    box:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
    if theme and theme.Exempt then theme.Exempt(box) else box._nexusThemeExempt = true end
    box:Hide()
    frame.importBox = box
    -- Escape closes the topmost layer: an open Reference article first
    -- (back to the topics, view.topic), then the Reference view (back to the
    -- step, view.help), then the coach
    -- exactly as Close does (U.Close). As for the Welcome
    -- (ui/QuickStart.lua), the coach itself is not listed in UISpecialFrames:
    -- a route that steps aside, a warning or another window hides it without
    -- closing it, and a first-use dismissal must not be taken from such a
    -- hide. This invisible child is listed instead. It is shown exactly while
    -- the coach is, and its own hide closes the coach only while the coach is
    -- still visible; an explicit hide of the coach hides it first, so that
    -- closes nothing. Offline model only; native NOT_RUN.
    local escape = CreateFrame('Frame', 'NexusGuidedSetupEscape', frame)
    escape:SetScript('OnHide', function(self)
        if not (frame and frame:IsVisible()) then return end
        if view.help then
            if view.topic then view.topic = nil else view.help = false end
            self:Show(); U.Render(); return
        end
        U.Close()
    end)
    frame:HookScript('OnShow', function() escape:Show() end)
    -- Any hide also ends a pending Open My Builds (U.RouteBuilds): its late
    -- answer belongs to the coach session it was asked from.
    frame:HookScript('OnHide', function() escape:Hide(); box:ClearFocus(); frame.buildsRoute = nil end)
    escape:Hide()
    UISpecialFrames = UISpecialFrames or {}
    UISpecialFrames[#UISpecialFrames + 1] = 'NexusGuidedSetupEscape'
    local g = Core()
    if g then g.onChange = function(receipt) U.OnChange(receipt) end end
    return frame
end

local function Place(b, spec, x, y, w)
    Arm(b, spec)
    b:SetHeight(22)
    local metrics = Nexus.LayoutMetrics
    if w then b:SetWidth(w) elseif metrics and metrics.FitButtonWidth then metrics.FitButtonWidth(b, 60, 160) end
    b:ClearAllPoints()
    if x and y then b:SetPoint('TOPLEFT', frame, 'TOPLEFT', x, y) end
end

-- The optional Reference view (Setup Alternative), drawn in place of the
-- step while view.help is set. Its topic list: a way back to the step, the
-- title and tag, one lead line, one row per topic. A topic opens its short
-- article in this same view (view.topic): All topics returns to the list,
-- and Escape goes article -> topics -> step -> close (Ensure's Escape child).
-- The dense manual is a separate, explicitly labelled Open full Reference
-- (U.OpenHelp), at the open topic's page or this step's. Reading, moving and
-- opening change nothing. Returns the y below.
local function Topic(r, page)
    for _, topic in ipairs(r.topics or {}) do if topic.page == page then return topic end end
end
local function ReferenceView(c, b, labels, id, pos, y)
    local r = c.reference or {}
    local topic = view.topic and Topic(r, view.topic) or nil
    if not topic then view.topic = nil end
    local back = topic and {label = b.allTopics or '< All topics', act = function() view.topic = nil end}
        or {label = Fmt(b.refBack, pos, labels[id] or id), act = function() view.help = false end}
    y = y - Actions({back}, PAD, y, CW) - 2
    y = y - Text(topic and r.escTopics or Fmt(r.escStep, pos), PAD, y, CW, 'muted', MUTED) - GAP
    y = y - Text(topic and topic.title or r.title, PAD, y, CW, 'title', GOLD) - 2
    y = y - Text(r.tag, PAD, y, CW, 'small', MUTED) - GAP
    if topic then
        for _, para in ipairs(topic.paras or {}) do y = y - Text(para, PAD, y, CW, 'body', TEXT) - GAP end
    else
        y = y - Text(r.lead, PAD, y, CW, 'body', TEXT) - GAP
        for _, t in ipairs(r.topics or {}) do
            local page = t.page
            y = y - Row({label = t.title .. '  >', act = function() view.topic = page end}, PAD, y, CW) - 2
        end
        y = y - GAP
    end
    y = y - Text(r.full, PAD, y, CW, 'muted', MUTED) - 6
    local page = topic and topic.page or HELP[id]
    return y - Actions({{label = b.fullReference or b.fullHelp, act = function() U.OpenHelp(page) end}}, PAD, y, CW) - GAP
end

-- The outcome slot under the step's action (Setup Alternative): WHAT
-- HAPPENED (the design's OBSERVED) with the status word only for a result
-- the guide read (StepStatus);
-- otherwise WHAT YOU WILL SEE with what the step is expected to show. A
-- glyph and a word, never colour alone. Returns the y below.
local function Outcome(c, id, kind, word, y)
    local o = c.outcome or {}
    local st = (c.status or {})[kind] or {}
    local label, text, color
    if id == 'summary' then
        label, text, color = o.summaryLabel, (o.expect or {}).summary, MUTED
    elseif kind == 'not' or (kind == 'waiting' and not word) then
        label, text, color = o.expectLabel, (o.expect or {})[id], MUTED
        st = (c.status or {})['not'] or {}
    else
        local extra = (o.extra or {})[kind]
        label = o.observedLabel
        text = tostring(word or st.word or '') .. '.' .. ((extra and extra ~= '') and (' ' .. extra) or '')
        color = COLOR[kind] or MUTED
    end
    local x, w, h = PAD, CW, 6
    local g = Text(st.glyph or 'o', x + 8, y - h, 26, 'head', color)
    local lh = Text(label or '', x + 40, y - h, w - 48, 'small', color) + 2
    lh = lh + Text(text or '', x + 40, y - h - lh, w - 48, 'body', TEXT)
    h = h + math.max(g, lh) + 6
    Box(x, y, w, h, color, {0.07, 0.055, 0.045})
    return y - h - GAP
end

-- A footer button sized to its whole label: at least `minimum`, at most the
-- footer row, so a long or localized label is never cut. Not yet placed.
local function FooterButton(b, spec, minimum, rowW)
    Place(b, spec, nil, nil, minimum)
    local metrics = Nexus.LayoutMetrics
    if metrics and metrics.FitButtonWidth then metrics.FitButtonWidth(b, minimum, rowW) end
    local w = b:GetWidth()
    -- Continue's wider side padding (the design's 1.3em to Back's 1em).
    if b.look == 'primary' then w = math.min(rowW, w + 10); b:SetWidth(w) end
    -- Skip's underline spans its text: the client's text width, else the
    -- label width FitButtonWidth allowed (its 24 px of end caps removed).
    if b.underline then
        local ok, tw = pcall(b.GetTextWidth, b)
        tw = ok and tonumber(tw) or nil
        if not (tw and tw > 0 and tw < math.huge) then tw = w - 24 end
        tw = math.max(1, math.min(w - 8, math.ceil(tw)))
        b.underline:SetWidth(tw); b.underlineHover:SetWidth(tw)
    end
    return w
end

------------------------------------------------------------------------
-- The bounded window (Setup Alternative, "Compact 640px": a scrolling body
-- between the fixed header and a pinned footer). Where the visible UI size is
-- readable (the same 640 x 480 floor as LayoutMetrics.FitToScreen) the coach
-- is at most 640 px tall, or the UI height less FitToScreen's 24 px margin.
-- A step taller than that keeps its header and its footer (Continue, Back,
-- Skip for now, Continue later) in place, and the body between them scrolls:
-- the mouse wheel over the coach, or the small up and down controls at its
-- right edge, beside a track and thumb that show where the view is. So the
-- text keeps its size instead of FitToScreen scaling the whole window down.
-- An implausibly small reported UI size keeps the earlier growing window.
-- Every region is still a direct child of the coach (no ScrollFrame): a
-- region wholly inside the view is moved by the scroll offset and shown, any
-- other one is hidden until scrolled to (a text is never cut through), and a
-- box or fill shows the part of it inside the view. The view starts at the
-- top for each step and for the Reference view; a click inside the same step
-- keeps it. Scrolling only moves what is shown: it reads, writes, sends and
-- changes nothing. Native wheel dispatch over child buttons, clipping and
-- pixels are NOT RUN.
------------------------------------------------------------------------
local SCROLL = {max = MAX_H, view = BLOCK_MAX + 20, step = 40, bar = 12}

-- The tallest the coach may be on this UI, or nil to grow as before.
local function ScreenCap()
    if not UIParent then return nil end
    local okW, w = pcall(UIParent.GetWidth, UIParent)
    local okH, h = pcall(UIParent.GetHeight, UIParent)
    w, h = okW and tonumber(w) or nil, okH and tonumber(h) or nil
    if not (w and h) or w < 640 or h < 480 then return nil end
    return math.max(MIN_H, math.min(SCROLL.max, math.floor(h - 24)))
end

-- A shown region anchored by one point to the coach: where it is laid out.
local function Anchored(r)
    if not (r and type(r.GetPoint) == 'function' and r:IsShown()) then return nil end
    local point, rel, relPoint, x, y = r:GetPoint(1)
    if rel ~= frame or type(y) ~= 'number' then return nil end
    return {r = r, point = point, relPoint = relPoint or point, x = tonumber(x) or 0, y = y,
        h = tonumber(r:GetHeight()) or 0}
end

-- The body as this render laid it out: every pooled item taken before the
-- footer (`used`), with the checklist button and the paste field.
local function BodyRecords(used)
    local list = {}
    for kind, p in pairs(pools) do
        for i = 1, math.min(p.used, used[kind] or 0) do
            local item = p[i]
            if kind == 'box' then
                if item.geo and item.parts[1]:IsShown() then list[#list + 1] = {box = item} end
            elseif kind == 'fill' then
                if item.geo and item:IsShown() then list[#list + 1] = {fill = item} end
            else
                local rec = Anchored(item)
                if rec then list[#list + 1] = rec end
            end
        end
    end
    for _, r in ipairs({frame.checklist, frame.importBox}) do
        local rec = Anchored(r)
        if rec then list[#list + 1] = rec end
    end
    return list
end

-- Moves the footer (its line, its buttons and every pooled item taken after
-- the body) up by `shift` px, onto the bottom of the view.
local function FooterShift(used, shift)
    local list = {frame.footLine, frame.next, frame.back, frame.skip, frame.later}
    for kind, p in pairs(pools) do
        for i = (used[kind] or 0) + 1, p.used do list[#list + 1] = p[i] end
    end
    for _, r in ipairs(list) do
        local rec = Anchored(r)
        if rec then r:ClearAllPoints(); r:SetPoint(rec.point, frame, rec.relPoint, rec.x, rec.y + shift) end
    end
end

-- Places texture `t` over content depths from..to (px below the coach's top
-- before scrolling) at scroll offset s, or hides it when nothing is left.
local function Clip(t, x, w, from, to, s)
    if to - from < 1 then t:Hide(); return end
    t:ClearAllPoints(); t:SetPoint('TOPLEFT', frame, 'TOPLEFT', x, -(from - s)); t:SetSize(w, to - from); t:Show()
end

local function ScrollControl(label, tip, dir)
    local b = CreateFrame('Button', nil, frame)
    b:SetSize(SCROLL.bar, SCROLL.bar)
    local theme = Nexus.Theme
    if theme and theme.Exempt then theme.Exempt(b) else b._nexusThemeExempt = true end
    b.fill = b:CreateTexture(nil, 'BACKGROUND'); b.fill:SetTexture(WHITE); b.fill:SetAllPoints(b)
    b.label = b:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    b.label:SetPoint('CENTER', b, 'CENTER', 0, 0)
    b:SetFontString(b.label)
    b:SetText(label)
    local hover = b:CreateTexture(nil, 'HIGHLIGHT'); hover:SetTexture(WHITE); hover:SetAllPoints(b)
    hover:SetVertexColor(1, 1, 1, 0.15)
    b.full = tip
    b:SetScript('OnClick', function() U.ScrollBy(dir * math.max(SCROLL.step, (view.body and
        (view.body.bottom - view.body.head) or SCROLL.step) - SCROLL.step)) end)
    b:SetScript('OnEnter', Tooltip)
    b:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
    b:Hide()
    return b
end

-- Shows the body at view.scroll: each region wholly inside the view moved
-- and shown, any other hidden; boxes and fills cut to the view. Then the
-- track, thumb and up / down controls (hidden while nothing scrolls).
local function ApplyScroll()
    local f, b = frame, view.body
    local parts = {f.scrollUp, f.scrollDown, f.scrollTrack, f.scrollThumb}
    if not (b and b.max > 0) then
        for _, r in ipairs(parts) do if r then r:Hide() end end
        if not b then return end
    end
    local s = view.scroll
    local top, bottom = b.head + s, b.bottom + s
    for _, rec in ipairs(b.records) do
        if rec.box then
            local g, p = rec.box.geo, rec.box.parts
            local t0, t1 = -g.y, -g.y + g.h
            local a, z = math.max(t0, top), math.min(t1, bottom)
            Clip(p[1], g.x, g.w, a, z, s)
            local open = z - a >= 1
            if g.edge and open and a == t0 then Clip(p[2], g.x, g.w, t0, t0 + 1, s) else p[2]:Hide() end
            if g.edge and open and z == t1 then Clip(p[3], g.x, g.w, t1 - 1, t1, s) else p[3]:Hide() end
            if g.edge then Clip(p[4], g.x, 1, a, z, s); Clip(p[5], g.x + g.w - 1, 1, a, z, s)
            else p[4]:Hide(); p[5]:Hide() end
        elseif rec.fill then
            local g = rec.fill.geo
            Clip(rec.fill, g.x, g.w, math.max(-g.y, top), math.min(-g.y + g.h, bottom), s)
        else
            local r, d = rec.r, -rec.y
            local inside = d >= top - 0.5 and d + rec.h <= bottom + 0.5
            r:ClearAllPoints(); r:SetPoint(rec.point, f, rec.relPoint, rec.x, rec.y + s)
            if inside then r:Show() else r:Hide() end
            r._nexusOut = (not inside) or nil
            if r.desc then r.desc._nexusOut = r._nexusOut end
            if r._nexusHit then if inside then r._nexusHit:Show() else r._nexusHit:Hide() end end
        end
    end
    if b.max <= 0 then return end
    -- Built the first time a step scrolls (after the Theme's tree walk; the
    -- controls draw their own fixed colours).
    if not f.scrollUp then
        f.scrollUp = ScrollControl('^', (Copy().buttons or {}).scrollUp or 'Scroll up', -1)
        f.scrollDown = ScrollControl('v', (Copy().buttons or {}).scrollDown or 'Scroll down', 1)
        f.scrollTrack, f.scrollThumb = Tex('ARTWORK'), Tex('OVERLAY')
        Paint(f.scrollTrack, {0.3, 0.24, 0.18}); Paint(f.scrollThumb, GOLD, 0.8)
    end
    local x, bar = W - SCROLL.bar - 2, SCROLL.bar
    f.scrollUp:ClearAllPoints(); f.scrollUp:SetPoint('TOPLEFT', f, 'TOPLEFT', x, -b.head)
    f.scrollDown:ClearAllPoints(); f.scrollDown:SetPoint('TOPLEFT', f, 'TOPLEFT', x, -(b.bottom - bar))
    f.scrollUp:Show(); f.scrollDown:Show()
    if s > 0 then f.scrollUp:Enable() else f.scrollUp:Disable() end
    if s < b.max then f.scrollDown:Enable() else f.scrollDown:Disable() end
    for _, c in ipairs({{f.scrollUp, s > 0}, {f.scrollDown, s < b.max}}) do
        Paint(c[1].fill, c[2] and GOLD or MUTED, c[2] and 0.35 or 0.15)
        c[1].label:SetTextColor(c[2] and GOLD[1] or MUTED[1], c[2] and GOLD[2] or MUTED[2], c[2] and GOLD[3] or MUTED[3])
    end
    local trackTop, trackH = b.head + bar + 2, math.max(1, b.bottom - b.head - 2 * (bar + 2))
    f.scrollTrack:ClearAllPoints(); f.scrollTrack:SetPoint('TOPLEFT', f, 'TOPLEFT', x + bar / 2 - 2, -trackTop)
    f.scrollTrack:SetSize(4, trackH); f.scrollTrack:Show()
    local shownH = b.bottom - b.head
    local thumbH = math.max(10, math.min(trackH, math.floor(trackH * shownH / (shownH + b.max))))
    local thumbY = trackTop + math.floor((trackH - thumbH) * s / b.max)
    f.scrollThumb:ClearAllPoints(); f.scrollThumb:SetPoint('TOPLEFT', f, 'TOPLEFT', x + bar / 2 - 2, -thumbY)
    f.scrollThumb:SetSize(4, thumbH); f.scrollThumb:Show()
end

-- Scrolls the body by dy px (positive: further down), within its range.
-- Returns whether the view moved. Reads and changes nothing else.
function U.ScrollBy(dy)
    local b = view.body
    if not (frame and frame:IsShown() and b and b.max > 0) then return false end
    local s = math.max(0, math.min(b.max, view.scroll + (tonumber(dy) or 0)))
    if s == view.scroll then return false end
    view.scroll = s
    ApplyScroll()
    return true
end

-- The mouse wheel over the coach (Ensure): one notch is SCROLL.step px.
function U.ScrollWheel(delta)
    return U.ScrollBy(-(tonumber(delta) or 0) * SCROLL.step)
end

-- The view of the body (nil while the whole step shows): its top and bottom
-- in px below the coach's top, the scroll offset and its largest value.
function U.ScrollState()
    local b = view.body
    if not b then return nil end
    return {head = b.head, bottom = b.bottom, scroll = view.scroll, max = b.max}
end

-- The end of a render: the coach's height, bounded where the UI size is
-- readable (ScreenCap) with the body scrolled in its view. `top` is the body's
-- top, `contentEnd` where its content ends, `footY` the footer line, `endY`
-- the footer's bottom (all negative offsets) and `used` the pools' counts
-- when the footer began. `key` names the step and view, whose scroll resets.
local function Bound(top, contentEnd, footY, endY, used, key)
    local f = frame
    local natural = math.ceil(-endY)
    if key ~= view.scrollKey then view.scroll, view.scrollKey = 0, key end
    view.body = nil
    local cap = ScreenCap()
    if cap and natural > cap then
        local head, foot = -top, -footY
        local footer = natural - foot
        local bottom = math.max(head + SCROLL.view, cap - footer)
        if bottom < foot then
            view.body = {head = head, bottom = bottom, max = math.max(0, math.ceil(-contentEnd - bottom)),
                records = BodyRecords(used)}
            view.scroll = math.max(0, math.min(view.scroll, view.body.max))
            FooterShift(used, foot - bottom)
            natural = math.ceil(bottom + footer)
        end
    end
    if not view.body then view.scroll = 0 end
    ApplyScroll()
    f:SetHeight(math.max(MIN_H, natural))
    local metrics = Nexus.LayoutMetrics
    if metrics and type(metrics.FitToScreen) == 'function' then metrics.FitToScreen(f) end
end

function U.Render()
    local f, g = Ensure(), Core()
    if not g then return end
    -- The kept place is bound (and on first use this session applied) before
    -- anything is read for this render; its results are all read again below.
    if type(g.Resume) == 'function' then g.Resume() end
    g.Recheck()
    Release()
    f.importBox:Hide()
    local s, c = g.State(), Copy()
    local b = c.buttons or {}
    local id = g.StepId()
    view.id = id
    local ctx = {targets = g.TargetOptions(), facts = g.TargetFacts(), assign = g.AssignStatus(),
        auto = g.AutoState(), character = Character(),
        kept = type(g.PlaceKept) == 'function' and g.PlaceKept() or 'session'}
    ctx.summary = g.Summary()
    -- What Nexus follows now, read for this render of the Wishlist step and
    -- the summary only (VIEW.wishlist, VIEW.summary); never kept, so a later
    -- render reads it again.
    if (id == 'wishlist' or id == 'summary') and not view.help and type(g.CurrentAssignment) == 'function' then
        ctx.current = g.CurrentAssignment()
    end
    local metrics = Nexus.LayoutMetrics
    local labels = c.labels or {}
    local pos, total = g.Position()
    local path = g.Order()

    -- The presentation (file header), then the step card's left edge and width.
    view.wide = WideFits()
    local nav = view.wide and WIDE.nav or 0
    -- Reference is its own view in place of the step (Setup Alternative),
    -- never a side panel beside it.
    local aside = 0
    W = view.wide and WIDE.w or COMPACT_W
    PAD = nav + EDGE
    CW = W - nav - 2 * EDGE - (aside > 0 and (aside + EDGE) or 0)
    f:SetWidth(W)

    -- Header: the title and the character line wrap left of Help and close,
    -- and the header is as tall as they are.
    Place(f.close, {label = b.close, tip = ctx.kept == 'saved' and b.closeTip or b.closeTipSession or b.closeTip,
        act = function() U.Close() end}, nil, nil, 26)
    f.close:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -12, -14)
    Place(f.help, {label = b.help, act = function() view.help, view.topic = not view.help, nil end}, nil, nil, 52)
    if metrics and metrics.FitButtonWidth then metrics.FitButtonWidth(f.help, 52, 140) end
    f.help:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -42, -14)
    if Nexus.Theme and Nexus.Theme.SetSelected then Nexus.Theme.SetSelected(f.help, view.help) end
    local headW = math.max(80, W - EDGE - 20 - 42 - f.help:GetWidth() - 8)
    f.title:SetText(c.title or '')
    f.title:ClearAllPoints(); f.title:SetPoint('TOPLEFT', f, 'TOPLEFT', EDGE + 20, -12)
    local th = 20
    if metrics and metrics.WrapHeight then th = metrics.WrapHeight(f.title, headW, 20, 60) else f.title:SetSize(headW, 20) end
    f.char:SetText(Fmt(c.charLine, ctx.character))
    f.char:ClearAllPoints(); f.char:SetPoint('TOPLEFT', f, 'TOPLEFT', EDGE + 20, -12 - th)
    local chh = 14
    if metrics and metrics.WrapHeight then chh = metrics.WrapHeight(f.char, headW, 14, 48) else f.char:SetSize(headW, 14) end
    local head = math.max(52, 12 + th + chh + 6)
    f.headLine:ClearAllPoints(); f.headLine:SetPoint('TOPLEFT', f, 'TOPLEFT', 6, -head); f.headLine:SetSize(W - 12, 1)
    local top = -(head + 8)
    local y = top

    local navBottom = top
    if not view.wide then
        -- Compact: step line, segmented rail and the collapsible checklist.
        Place(f.checklist, {label = view.checklist and b.checklistHide or b.checklistShow,
            act = function() view.checklist = not view.checklist end}, nil, nil, 100)
        if metrics and metrics.FitButtonWidth then metrics.FitButtonWidth(f.checklist, 100, math.floor(CW / 2)) end
        f.checklist:SetPoint('TOPRIGHT', f, 'TOPLEFT', PAD + CW, y)
        local stepLine = Fmt(c.kicker, pos, total) .. ' - ' .. (labels[id] or id)
        local sh = Text(stepLine, PAD, y - 3, CW - f.checklist:GetWidth() - 10, 'body', MUTED)
        y = y - math.max(28, sh + 8)
        local segW = math.floor((CW - 3 * (#path - 1)) / #path)
        for i, step in ipairs(path) do
            local kind = StepStatus(g, s, ctx, step)
            local color = kind == 'verified' and COLOR.verified or step == id and GOLD
                or kind == 'skipped' and {0.45, 0.43, 0.4} or {0.3, 0.24, 0.18}
            Fill(PAD + (i - 1) * (segW + 3), y, segW, 5, color, 1)
        end
        y = y - 5 - GAP
        if view.checklist then
            for _, step in ipairs(path) do
                local kind, word = StepStatus(g, s, ctx, step)
                local target = step
                y = y - Row({label = Marker(c, kind) .. '  ' .. (labels[step] or step),
                    desc = word or Status(kind).word, selected = step == id,
                    act = function() note = nil; view.checklist = false; g.GoTo(target) end}, PAD, y, CW) - 2
            end
            y = y - GAP
        end
    else
        -- Desktop: the checklist is the side navigation, always shown, one
        -- row per step of the path with its glyph-and-word status.
        f.checklist:Hide()
        local ny = top - Text(c.checklistTitle or 'CHECKLIST', EDGE, top, nav - 2 * EDGE, 'small', MUTED) - 6
        for _, step in ipairs(path) do
            local kind, word = StepStatus(g, s, ctx, step)
            local target = step
            ny = ny - Row({label = Marker(c, kind) .. '  ' .. (labels[step] or step),
                desc = word or Status(kind).word, selected = step == id,
                act = function() note = nil; g.GoTo(target) end}, 8, ny, nav - 16) - 2
        end
        navBottom = ny - GAP
    end

    local asideBottom = top
    local reference = view.help == true
    if reference then
        -- The optional Reference in place of the step (Escape closes it
        -- before the coach); the step and its footer wait underneath.
        y = ReferenceView(c, b, labels, id, pos, y)
    else
        -- The desktop window has no compact step line: its position heads
        -- the card. The step's status is the outcome slot below its action.
        if view.wide then
            local kicker = Fmt(c.kicker, pos, total) .. (id == 'auto' and (c.kickerOptional or '') or '')
            y = y - Text(kicker, PAD, y - 3, CW, 'body', GOLD) - GAP
        end
        if s.notice then y = y - Text('? ' .. ((c.notice or {})[s.notice] or ''), PAD, y, CW, 'body', COLOR.stale) - GAP end
        y = VIEW[id](g, s, ctx, c, y)
        if note then y = y - Text(note, PAD, y, CW, 'body', GOLD) - GAP end
        local kind, word = StepStatus(g, s, ctx, id)
        y = Outcome(c, id, kind, word, y)
    end

    -- Footer: Back, the gate hint, Skip for now and Continue. While the paste
    -- field is the chosen way, Continue waits until a Wishlist from it is
    -- saved: a checked code or an open draft is not a Wishlist yet.
    local imp = view.import
    local importing = id == 'wishlist' and imp.open and not (s.wishlist and s.wishlist.source == 'saved')
    local canNext = id == 'summary' or (g.CanNext() and not importing)
    local hint = ''
    if not canNext then
        local gt, st = c.gate or {}, ctx.assign.state
        if id == 'wishlist' then
            hint = s.draft and gt.wishlistDraft
                or importing and (imp.result and imp.result.state == 'accepted' and gt.wishlistChecked or gt.wishlistImport)
                or gt.wishlist
        elseif id == 'target' then
            local tf = ctx.facts
            hint = not ctx.targets and gt.targetUnavailable
                or (tf and tf.empty) and gt.targetSave
                or (tf and tf.replaces and not tf.confirmed) and gt.targetReplace
                or (tf and tf.ready and tf.route == 'select') and gt.targetSelect
                or (tf and tf.ready and tf.route == 'first') and gt.targetFirst
                or gt.target
        elseif id == 'assign' then hint = (st == 'pending' and gt.assignWaiting) or ((st == 'refused' or st == 'cancelled') and gt.assignRejected)
            or (st == 'unknown' and gt.assignUnknown)
            or ((st == 'stale' or st == 'changed' or st == 'other' or st == 'mismatch' or st == 'outdated' or st == 'partial') and gt.assignStale)
            or gt.assign
        elseif id == 'auto' then hint = ctx.auto == 'unknown' and gt.autoUnknown or gt.auto
        else hint = gt[id] or '' end
    end
    -- Footer across the window (Setup Alternative): on the Wishlist step the
    -- one Selected name, then Continue across the row, the gate hint under it
    -- while it waits, then Back, Skip for now and Continue later centred in
    -- one row; a link that does not fit moves to a further row (never over
    -- another, never cut). The Reference view has no footer: its own way back
    -- returns to the step, whose footer then shows again.
    -- Where the body's content ends, before the window's minimum height pads
    -- it; a bounded window scrolls exactly that far (Bound).
    local contentEnd = math.min(y, navBottom, asideBottom)
    y = math.min(contentEnd, -MIN_H + 70)
    local footY = y
    f.footLine:ClearAllPoints(); f.footLine:SetPoint('TOPLEFT', f, 'TOPLEFT', 6, y); f.footLine:SetSize(W - 12, 1)
    Paint(f.footLine, {0.45, 0.3, 0.16}); f.footLine:Show()
    if view.wide then Fill(nav, -(head + 2), 1, -y - head - 2, {0.3, 0.24, 0.18}, 1) end
    -- Everything taken from the pools so far is the body; the rest is footer.
    local bodyUsed = {}
    for kind, p in pairs(pools) do bodyUsed[kind] = p.used end
    local scrollKey = id .. (reference and (':reference:' .. tostring(view.topic or '')) or '') .. (view.wide and ':wide' or '')
    y = y - GAP
    local rowW = W - 2 * EDGE
    if reference then
        f.next:Hide(); f.skip:Hide(); f.back:Hide(); f.later:Hide()
        y = y - EDGE
        Bound(top, contentEnd, footY, y, bodyUsed, scrollKey)
        return
    end
    if id == 'wishlist' then
        local tw = c.wishlist or {}
        local shown = ShownWishlist(s)
        y = y - Text(shown and Fmt(tw.selected, Name(shown.name)) or tw.selectedNone, EDGE, y, rowW, 'body', TEXT) - 6
    end
    FooterButton(f.next, {label = id == 'summary' and b.finish or b.next, enabled = canNext, primary = true,
        act = function()
            note = nil
            if id == 'summary' then U.Close('finish') else g.Next() end
        end}, 60, rowW)
    f.next:SetWidth(rowW)
    f.next:SetPoint('TOPLEFT', f, 'TOPLEFT', EDGE, y)
    y = y - 22 - 6
    if hint ~= '' then y = y - Text(hint, EDGE, y, rowW, 'body', {1, 0.84, 0.5}, 'CENTER') - 6 end
    local links = {}
    if pos > 1 then
        links[#links + 1] = {f.back, FooterButton(f.back, {label = b.back, act = function() note = nil; g.Back() end}, 70, rowW)}
    else f.back:Hide() end
    if g.SKIPPABLE[id] and not canNext then
        links[#links + 1] = {f.skip, FooterButton(f.skip, {label = b.skip, act = function() note = nil; g.Skip() end}, 60, rowW)}
    else f.skip:Hide() end
    links[#links + 1] = {f.later, FooterButton(f.later, {label = b.later, tip = ctx.kept == 'saved' and b.closeTip
        or b.closeTipSession or b.closeTip, act = function() note = nil; U.Close() end}, 60, rowW)}
    -- Rows of links, each row centred in the footer.
    local rows, row, used = {}, {}, 0
    for _, link in ipairs(links) do
        if #row > 0 and used + 6 + link[2] > rowW then rows[#rows + 1] = {row, used}; row, used = {}, 0 end
        used = used + (#row > 0 and 6 or 0) + link[2]
        row[#row + 1] = link
    end
    if #row > 0 then rows[#rows + 1] = {row, used} end
    for index, r in ipairs(rows) do
        local x = EDGE + math.floor((rowW - r[2]) / 2)
        for _, link in ipairs(r[1]) do
            link[1]:SetPoint('TOPLEFT', f, 'TOPLEFT', x, y)
            x = x + link[2] + 6
        end
        if index < #rows then y = y - 26 end
    end
    y = y - 22 - EDGE
    Bound(top, contentEnd, footY, y, bodyUsed, scrollKey)
end

-- The coach's text in render order (the header first), for readers and
-- tests. A bounded window's body text scrolled out of view is included: it is
-- the step's own text, one scroll away (U.TextRegions lists only what is in view).
function U.VisibleText()
    if not frame then return '' end
    local out = {frame.title:GetText() or '', frame.char:GetText() or ''}
    for _, fs in ipairs(order) do out[#out + 1] = fs:GetText() or '' end
    return table.concat(out, ' | ')
end
-- The text regions in view, in render order (ApplyScroll marks the others).
function U.TextRegions()
    local out = {}
    for _, fs in ipairs(order) do if not fs._nexusOut then out[#out + 1] = fs end end
    return out
end

-- The routes that end through the editor or the import dialog ('plan': the
-- set-aside Plan draft, U.RoutePlan, or the Plan its Discard draft opened for
-- the current context, U.PlanDiscarded). A coach that stepped aside for full
-- Help ('help') comes back only through U.HelpEnded.
local EDITOR_ROUTE = {new = true, import = true, plan = true}

-- An unsaved route may be canceled without a save receipt. Return to the
-- same guide step, but never claim the Wishlist was completed.
function U.RouteEnded(kind)
    local f = frame
    if not f or not f.waiting or f.waitingKind ~= kind or not EDITOR_ROUTE[kind] then return end
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
-- The hook outlasts its route: a later editor hide while the coach waits for
-- anything other than an editor route (full Help, the chooser) ends nothing.
function U.WatchEditor(kind)
    local f, editorFrame = frame, _G.NexusEditorFrame
    if not f or f.waitingKind ~= kind then return end
    if not editorFrame or not editorFrame:IsShown() then U.RouteEnded(kind); return end
    if type(editorFrame.HookScript) == 'function' and not editorFrame._NexusGuideOnHide then
        editorFrame._NexusGuideOnHide = true
        editorFrame:HookScript('OnHide', function()
            if frame and EDITOR_ROUTE[frame.waitingKind] then U.RouteEnded(frame.waitingKind) end
        end)
    end
end

-- Opens the editor or the import dialog; the guide steps aside and returns
-- when the editor reports a save or the route is canceled. Opening a draft
-- completes nothing. An empty Wishlist would replace an unsaved Plan draft
-- set aside in another workspace, which the editor refuses (NewWishlist); the
-- step then says so in place (PlanDraftCard) and opens, arms and prints
-- nothing. A refusal the editor still reports brings the coach back at once.
function U.RouteEditor(kind)
    local g, n, f = Core(), Copy().notes or {}, frame
    if not Ready() then note = n.startup; return end
    local editor = Nexus.WishlistEditor
    if kind == 'import' then
        if type(StaticPopup_Show) ~= 'function' or not (StaticPopupDialogs or {}).NEXUS_IMPORT_WISHLIST then note = n.noEditor; return end
    elseif not (editor and type(editor.NewWishlist) == 'function') then note = n.noEditor; return end
    if kind == 'new' and SuspendedDraft() then view.planDraft = true; note = nil; return end
    g.AwaitSave(); note = nil
    f.waiting, f.waitingKind = true, kind
    f:Hide()
    if kind == 'import' then
        StaticPopup_Show('NEXUS_IMPORT_WISHLIST')
    else
        local ok, opened = pcall(editor.NewWishlist)
        if not ok or opened == false then
            if not ok then note = n.noEditor end
            view.planDraft = SuspendedDraft() ~= nil
            U.RouteEnded('new')
            return
        end
        U.WatchEditor('new')
    end
end

-- Return to Plan draft: the draft set aside in another workspace, reopened
-- as it is by the editor's own resume (WishlistEditor.ResumeWorkspaceDraft).
-- That draft is not the empty Wishlist this step asked for, so no save is
-- armed and its later save chooses nothing here. The coach steps aside only
-- once Plan is shown, and comes back when the editor closes (U.WatchEditor).
-- Under another character or Saved Build the editor asks first whether to
-- discard it; that question is this click's answer, and the coach stays.
-- Keep draft leaves the draft and the coach as they are. Discard draft is the
-- player's own answer: the editor drops the draft and opens Plan for the
-- current context (not the old draft), and only then does the coach step
-- aside for that Plan exactly as for a returned draft (PlanDiscarded).
function U.RoutePlan()
    local n, f = Copy().notes or {}, frame
    if not Ready() then note = n.startup; return end
    local editor = Nexus.WishlistEditor
    if not (editor and type(editor.ResumeWorkspaceDraft) == 'function') then note = n.noEditor; return end
    local d = SuspendedDraft()
    note = nil
    if not d then view.planDraft = false; return end
    -- This ask only: a hide of the coach, a reopen or a later ask drops it.
    local ask = {}
    f.planAsk = ask
    local ok, opened = pcall(editor.ResumeWorkspaceDraft, function() U.PlanDiscarded(ask) end)
    local editorFrame = _G.NexusEditorFrame
    if ok and opened and editorFrame and editorFrame:IsShown() then
        f.planAsk = nil
        view.planDraft = false
        f.waiting, f.waitingKind = true, 'plan'
        f:Hide()
        U.WatchEditor('plan')
        return
    end
    if not ok then f.planAsk = nil; note = n.noEditor elseif d.sameContext then f.planAsk = nil; note = n.planRefused end
end

-- The editor's report that the player answered this coach's changed-context
-- question (U.RoutePlan) with Discard draft and Plan was shown for the
-- current context. A coach closed, reopened or asked again since (Close,
-- Hide, Show, ShowFirstUse and a new ask drop the ask), or one that stepped
-- aside for another route meanwhile, takes nothing from it. The new Plan arms
-- no save and chooses nothing here; the coach steps aside for it and comes
-- back when the editor closes. When Plan is not on screen the coach stays and
-- says so.
function U.PlanDiscarded(ask)
    local f = frame
    if not (f and ask ~= nil and f.planAsk == ask and not f.waiting) then return end
    f.planAsk = nil
    view.planDraft = false
    local editorFrame = _G.NexusEditorFrame
    if editorFrame and editorFrame:IsShown() then
        note = nil
        f.waiting, f.waitingKind = true, 'plan'
        f:Hide()
        U.WatchEditor('plan')
        return
    end
    note = (Copy().notes or {}).planDiscarded
    if f:IsShown() then U.Render() end
end

-- Check code: reads the pasted text through the editor's read-only check
-- (WishlistEditor.CheckImportCode). It opens, imports, saves and arms nothing,
-- and its result belongs to the exact text it read.
function U.CheckImport()
    local imp, editor = view.import, Nexus.WishlistEditor
    if frame and frame.importBox then imp.text = tostring(frame.importBox:GetText() or '') end
    local r
    if editor and type(editor.CheckImportCode) == 'function' then
        local ok, got = pcall(editor.CheckImportCode, imp.text)
        r = ok and type(got) == 'table' and got or nil
    end
    imp.result, imp.checked = r or {state = 'unavailable'}, imp.text
    return imp.result
end

-- Open it as a draft: the deliberate later action. The same text is read
-- again and must still be the code that was checked; then the guide steps
-- aside and hands it to the editor's own import (WishlistEditor
-- ImportEBH1String: its suspended-draft refusal, naming dialog and draft).
-- The import route's cancel, refusal or editor close brings the guide back
-- (U.RouteEnded); only the player's later save there completes this step.
function U.RouteImport()
    local g, n, f, imp = Core(), Copy().notes or {}, frame, view.import
    if not Ready() then note = n.startup; return end
    local editor = Nexus.WishlistEditor
    if not (editor and type(editor.ImportEBH1String) == 'function') then note = n.noEditor; return end
    local r = U.CheckImport()
    if r.state ~= 'accepted' then note = n.importChanged; return end
    if r.suspended then note = n.importSuspended; return end
    local text = imp.checked
    g.AwaitSave(); note = nil
    f.waiting, f.waitingKind = true, 'import'
    f:Hide()
    local ok, opened = pcall(editor.ImportEBH1String, text)
    if not ok or opened == false then
        note = ok and n.importSuspended or n.noEditor
        U.RouteEnded('import')
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

-- Opens the game's own My Builds page (JournalTab.OpenBuilds(false), the
-- route of the panel's My Builds button) for a target the Echo Journal
-- chooser cannot reach now: a Saved Build to make active there, or an empty
-- slot to save Echoes into there through the game's own confirmation. The
-- guide arms, saves, loads, activates and assigns nothing. It steps aside
-- only once the Journal reports My Builds seen (OpenBuilds' onSettled);
-- when it is not seen, the coach stays with a note saying so. It reads every
-- slot again when the player reopens it (Setup / Welcome or /nexus guide).
function U.RouteBuilds()
    local n, f = Copy().notes or {}, frame
    if not Ready() then note = n.startup; return end
    local journal = Nexus.JournalTab
    if not (journal and type(journal.OpenBuilds) == 'function')
        or (type(journal.CanOpenBuilds) == 'function' and not journal.CanOpenBuilds()) then
        note = n.unavailable; return
    end
    note = nil
    -- Only the latest open answers, and only in the coach session it was asked
    -- from: a hide (Close, Escape, another route) or a reopen (Show,
    -- ShowFirstUse, Replay) drops it, so a late answer never hides a coach
    -- shown since, and a coach the player closed meanwhile stays closed.
    local route = {}
    f.buildsRoute = route
    local ok, opened = pcall(journal.OpenBuilds, false, nil, function(seen)
        if f.buildsRoute ~= route then return end
        f.buildsRoute = nil
        if not f:IsShown() then return end
        if seen then
            f.waiting, f.waitingKind = true, 'builds'
            f:Hide()
        else
            note = n.buildsUnconfirmed or n.buildsUnavailable or n.unavailable
            U.Render()
        end
    end)
    if not (ok and opened) then
        f.buildsRoute = nil
        f.waiting, f.waitingKind = nil, nil
        note = n.buildsUnavailable or n.unavailable
        if not f:IsShown() then f:Show() end
    end
end

-- Optional lessons open the existing screens; reading or opening spends and
-- sends nothing.
function U.Lesson(id)
    if id == 'orbs' and Nexus.OrbPanel and Nexus.OrbPanel.Show then Nexus.OrbPanel.Show(); return end
    U.OpenHelp(id)
end

-- Full Help is the dense reference window; over the coach it would cover the
-- step in progress. The coach steps aside for it (a hide that closes nothing,
-- as for its other routes) and comes back at the same step when Help is
-- closed (Close or Escape). A route Help opens itself takes over instead;
-- Help's Setup / Welcome resumes the coach.
local helpReturn
function U.OpenHelp(page)
    local help = Nexus.Help
    if not (help and type(help.Show) == 'function') then return false end
    local f = frame
    if not (f and f:IsShown()) then return pcall(help.Show, page) end
    -- The Reference view gives way to full Help; closing Help returns to the
    -- step itself, not to the topic list.
    view.help, view.topic = false, nil
    f.waiting, f.waitingKind = true, 'help'
    f:Hide()
    local ok = pcall(help.Show, page, function()
        -- One frame later: the client's Escape hides every listed window in
        -- one pass, and the coach shown inside that pass would be closed by
        -- the same key press.
        if not helpReturn then
            helpReturn = CreateFrame('Frame')
            helpReturn:SetScript('OnUpdate', function(self) self:Hide(); U.HelpEnded() end)
        end
        helpReturn:Show()
    end)
    if not ok then U.HelpEnded() end
    return ok
end

-- Brings back a coach that stepped aside for Help, unless it was reopened or
-- closed meanwhile or a warning waits for its answer.
function U.HelpEnded()
    local f = frame
    if not (f and f.waitingKind == 'help') or f:IsShown() then return end
    local warning = Nexus.OverwriteWarning
    if warning and type(warning.IsOpen) == 'function' and warning.IsOpen() then return end
    f.waiting, f.waitingKind = nil, nil
    f:Show()
    U.Render()
end

-- Resume: the same step, with its context checked again. Never opens over
-- an Auto warning that waits for its answer, and asks it nothing.
function U.Show()
    local warning = Nexus.OverwriteWarning
    if warning and type(warning.IsOpen) == 'function' and warning.IsOpen() then return false, 'warning-open' end
    local f = Ensure()
    -- An ordinary hide does not acknowledge first use. Keep its guarded
    -- callback across a Help reopen so a later deliberate Close can do so.
    -- A new session: an earlier Open My Builds or Plan draft question no
    -- longer answers here, and an earlier answer about a set-aside Plan draft
    -- is given again only if asked.
    f.waiting, f.waitingKind, f.buildsRoute, f.planAsk, note = nil, nil, nil, nil, nil
    -- A reopened coach shows its step from the top (Bound resets the view).
    view.planDraft, view.scrollKey = false, nil
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
    f.waiting, f.waitingKind, f.buildsRoute, f.planAsk, note = nil, nil, nil, nil, nil
    view.planDraft, view.scrollKey = false, nil
    f:Show()
    U.Render()
    return true
end
function U.Replay()
    local g = Core()
    if g then g.Replay() end
    view.lesson, view.checklist = nil, false
    ResetImport()
    return U.Show()
end
function U.Hide() if frame then frame.waiting, frame.waitingKind, frame.planAsk = nil, nil, nil; frame:Hide() end end

-- What the chat says on close: where the guide paused, or (from the summary's
-- Close guide) what is true now. Closing never marks a step done.
local function CloseLines(reason)
    local g, c = Core(), Copy()
    local ch = c.chat or {}
    if not g then return {} end
    local id = g.StepId()
    -- Where it reopens, and whether its place outlasts a reload (PlaceKept).
    local reopen = (type(g.PlaceKept) == 'function' and g.PlaceKept() == 'saved') and ch.reopen
        or ch.reopenSession or ch.reopen
    if reason ~= 'finish' then
        return {Fmt(ch.paused, (c.labels or {})[id] or id), reopen}
    end
    local s, sm = g.State(), g.Summary()
    if s.path == 'explore' then return {ch.explore} end
    if sm.complete or sm.trueNow then
        local f = g.TargetFacts()
        local auto = sm.auto == 'unknown' and 'unknown' or (sm.auto == 'on' and 'ON' or 'OFF')
        return {Fmt(ch.complete, f and TargetLabel(f.destination, f.name) or '?', Name(s.wishlist and s.wishlist.name)),
            Fmt(ch.auto, auto)}
    end
    return {Fmt(ch.incomplete, sm.open, sm.open == 1 and '' or 's'), reopen}
end

-- Close and Escape: the deliberate close. A first-use coach tells its caller
-- once, after it is hidden; that caller decides what is recorded (only that
-- first use was seen: guide steps keep their own state).
function U.Close(reason)
    if not frame then return end
    local onClose = frame.firstUse
    local lines = CloseLines(reason)
    frame.firstUse, frame.waiting, frame.waitingKind, frame.buildsRoute, frame.planAsk = nil, nil, nil, nil, nil
    view.help, view.topic = false, nil
    frame:Hide()
    for _, line in ipairs(lines) do if line then Say(line) end end
    if type(onClose) == 'function' then pcall(onClose) end
end

-- A save or assignment receipt brings back a coach that stepped aside for
-- its own route. One that stepped aside for full Help is not brought back over
-- Help (or over a window Help opened in its place): the receipt is already
-- recorded (core/GuidedSetup.lua G.Note), and U.HelpEnded reads it afresh
-- when Help closes. Nor is one that returned the player to a set-aside Plan
-- draft (U.RoutePlan) or to the Plan its Discard draft opened
-- (U.PlanDiscarded): a save there is not this step's, and the coach comes
-- back when the editor closes.
function U.OnChange(receipt)
    if not frame then return end
    if frame.waiting and frame.waitingKind ~= 'help' and frame.waitingKind ~= 'plan' and type(receipt) == 'table'
        and (receipt.kind == 'save' or receipt.kind == 'assign') then
        local warning = Nexus.OverwriteWarning
        if not (warning and type(warning.IsOpen) == 'function' and warning.IsOpen()) then
            frame.waiting, frame.waitingKind = nil, nil
            frame:Show()
        end
    end
    if frame:IsShown() then U.Render() end
end

return U
