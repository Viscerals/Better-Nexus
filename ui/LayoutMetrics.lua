-- Nexus-owned font and revision-keyed responsive geometry.
--
-- Layout is computed as plain tables before frames are moved. This keeps font
-- measurement out of render hot paths and makes every supported scale/window
-- combination deterministic under WoW 3.3.5a's Lua 5.1 runtime.

Nexus = Nexus or {}

local M = {}
local panelCache, communityCache = {}, {}

-- Full-UI localization (issues #143-#148): the one code-owned label this
-- file chooses (the Orb mini-panel button) resolves through
-- Nexus.Localization when a layout is computed; while the seam is absent or
-- the key answers "unavailable" the exact English is used. A cached layout
-- keeps the label of its session, whose language does not change.
local function ShownLabel(key, english)
    local localization = Nexus.Localization
    if type(localization) == "table" and type(localization.Text) == "function" then
        local text, source = localization.Text(key)
        if type(text) == "string" and source ~= "unavailable" then return text end
    end
    return english
end
local panelOrder, communityOrder = {}, {}
local MAX_CACHE_ENTRIES = 64
local stats = {
    requests=0,computations=0,hits=0,evictions=0,
    fontBuilds=0,fontApplications=0,
}
local fontsReady = false
local runtimeSignature, runtimeRevision = nil, 1

-- small / normal / large are the shared fonts of every Nexus window.
-- secondary is the main panel's own secondary text (labels, headings, tags,
-- reasons): 11 units, the panel's readable floor, where the shared small
-- font is 10. title is the main panel's own title, 15 units. Both follow the
-- same native reference; no shared size changes.
local FONT_NAMES = {
    small="NexusFontSmall",
    normal="NexusFontNormal",
    large="NexusFontLarge",
    secondary="NexusFontSecondary",
    title="NexusFontTitle",
}
local FONT_SIZES = {small=10,normal=12,large=14,secondary=11,title=15}
-- The owned sizes follow the client's own small text: the native font object
-- the loading overlay's detail line is drawn in. Its reported height becomes
-- the owned small size and the 10 / 12 / 14 hierarchy keeps its proportions,
-- up to the largest font scale the layouts support (2). The owned sizes
-- never fall below 10 / 12 / 14: a client whose small font is 10 or smaller
-- keeps exactly those. The font object itself is read, so no loading frame
-- has to exist or be shown; only the owned objects are ever set, never a
-- game font or a UI scale.
local FONT_REFERENCE = "GameFontHighlightSmall"
local fontReference

local function Clamp(value, low, high)
    value = tonumber(value) or low
    if value < low then return low end
    if value > high then return high end
    return value
end

local function Round(value, places)
    local factor = 10 ^ (places or 0)
    return math.floor((tonumber(value) or 0) * factor + 0.5) / factor
end

local function Box(x, y, width, height)
    return {
        x=math.floor(x + 0.5),y=math.floor(y + 0.5),
        w=math.max(1,math.floor(width + 0.5)),
        h=math.max(1,math.floor(height + 0.5)),
    }
end

local function Add(layout, name, x, y, width, height, required)
    layout.boxes[name] = Box(x, y, width, height)
    if required ~= false then
        layout.required[#layout.required + 1] = name
    end
    return layout.boxes[name]
end

local function KeyText(value)
    value = tostring(value or "")
    return tostring(#value) .. ":" .. value
end

local function Remember(cache, order, key, value)
    if not cache[key] then
        if #order >= MAX_CACHE_ENTRIES then
            local expired = table.remove(order,1)
            cache[expired] = nil
            stats.evictions = stats.evictions + 1
        end
        order[#order+1] = key
    end
    cache[key] = value
    return value
end

-- The reference's scale against the owned small size, from 1 (the fixed
-- sizes, as before; also without a readable reference) to 2.
local function ReferenceScale()
    local font = _G[FONT_REFERENCE]
    if font and type(font.GetFont) == "function" then
        local ok, _, size = pcall(font.GetFont, font)
        size = ok and tonumber(size) or nil
        if size and size > 0 and size < math.huge then
            return Clamp(Round(size, 2) / FONT_SIZES.small, 1, 2)
        end
    end
    return 1
end

-- Builds the owned fonts once, and again only when the reference's height
-- has changed since (a client that sets its fonts after this file first
-- ran). The runtime font scale below then differs, which advances the
-- runtime revision every layout cache is keyed by.
function M.EnsureFonts()
    local reference = ReferenceScale()
    if fontsReady and reference == fontReference then return FONT_NAMES end
    fontsReady, fontReference = true, reference
    if type(CreateFont) ~= "function" then return FONT_NAMES end
    local path = type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT
        or "Fonts\\FRIZQT__.TTF"
    for kind, name in pairs(FONT_NAMES) do
        local font = _G[name]
        if not font then
            local ok, created = pcall(CreateFont, name)
            if ok then font = created end
        end
        if font and type(font.SetFont) == "function" then
            pcall(font.SetFont, font, path, Round(FONT_SIZES[kind] * reference, 2), "")
        end
    end
    stats.fontBuilds = stats.fontBuilds + 1
    return FONT_NAMES
end

function M.FontObject(kind)
    M.EnsureFonts()
    return FONT_NAMES[kind] or FONT_NAMES.normal
end

-- One-shot ownership pass for complex windows assembled from Blizzard
-- templates. It changes each FontString instance, never the shared Blizzard
-- font object, and is intentionally not called from render loops.
function M.ApplyFontTree(root, kind)
    if not root then return 0 end
    local font, seen, applied = M.FontObject(kind or "normal"), {}, 0
    local function Walk(widget)
        if not widget or seen[widget] then return end
        seen[widget] = true
        if type(widget.SetFontObject) == "function" then
            if pcall(widget.SetFontObject, widget, font) then
                applied = applied + 1
            end
        end
        if type(widget.GetRegions) == "function" then
            local ok, regions = pcall(function()
                return {widget:GetRegions()}
            end)
            if ok then for _, region in ipairs(regions) do Walk(region) end end
        end
        if type(widget.GetChildren) == "function" then
            local ok, children = pcall(function()
                return {widget:GetChildren()}
            end)
            if ok then for _, child in ipairs(children) do Walk(child) end end
        end
    end
    Walk(root)
    stats.fontApplications = stats.fontApplications + applied
    return applied
end

local function RuntimeFontScale()
    M.EnsureFonts()
    local font = _G[FONT_NAMES.normal]
    if font and type(font.GetFont) == "function" then
        local ok, _, size = pcall(font.GetFont, font)
        size = ok and tonumber(size) or nil
        if size and size > 0 then return Clamp(size / FONT_SIZES.normal, 0.75, 2) end
    end
    return 1
end

local function RuntimeUiScale()
    if UIParent and type(UIParent.GetEffectiveScale) == "function" then
        local ok, value = pcall(UIParent.GetEffectiveScale, UIParent)
        value = ok and tonumber(value) or nil
        if value and value > 0 then return Clamp(value, 0.25, 4) end
    end
    return 1
end

function M.RuntimeMetrics()
    local fontScale, uiScale = RuntimeFontScale(), RuntimeUiScale()
    local signature = tostring(Round(fontScale, 3)) .. "/"
        .. tostring(Round(uiScale, 3))
    if runtimeSignature and runtimeSignature ~= signature then
        runtimeRevision = runtimeRevision + 1
    end
    runtimeSignature = signature
    return fontScale, uiScale, runtimeRevision
end

function M.RuntimeKey(owner, width, height)
    local fontScale, uiScale, revision = M.RuntimeMetrics()
    return table.concat({tostring(owner or "layout"),tostring(Round(width,1)),
        tostring(Round(height,1)),tostring(Round(fontScale,3)),
        tostring(Round(uiScale,3)),tostring(revision)}, "/")
end

function M.Overlap(left, right)
    if not left or not right then return false end
    return left.x < right.x + right.w and right.x < left.x + left.w
        and left.y < right.y + right.h and right.y < left.y + left.h
end

local function Utf8Step(byte)
    if byte < 128 then return 1 end
    if byte < 224 then return 2 end
    if byte < 240 then return 3 end
    return 4
end

function M.Truncate(value, maxCharacters)
    local text = tostring(value or "")
    local limit = math.max(4, math.floor(tonumber(maxCharacters) or 4))
    local offsets, index = {}, 1
    while index <= #text do
        offsets[#offsets + 1] = index
        index = index + Utf8Step(text:byte(index))
    end
    if #offsets <= limit then return text end
    local keep = math.max(1, limit - 3)
    local stop = offsets[keep + 1] or (#text + 1)
    return text:sub(1, stop - 1) .. "..."
end

-- Conservative text model for rows that must stay readable (the Orb
-- guidance): a face wider than the default one, either not reflected in the
-- runtime font scale (7.0 px per character, 17 px lines, the native-derived
-- model of the QuickStart fit) or scaled with it (0.70 em per character,
-- 1.2 em lines of the 10 px small font). The larger of the two is used.
function M.ConservativeText(scale)
    scale = Clamp(scale or 1, 0.75, 2)
    return math.max(7.0, 0.70 * 10 * scale), math.max(17, math.ceil(12 * scale))
end

-- Greedy word-wrap row count of a text in a width under that model. Colour
-- codes are not visible; a UTF-8 character counts once.
function M.TextRows(text, width, scale)
    local char = M.ConservativeText(scale)
    text = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local rows = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        rows = rows + 1
        local used = 0
        for word in line:gmatch("%S+") do
            local w = #(word:gsub("[\128-\191]", "")) * char
            local space = used > 0 and char or 0
            if used > 0 and used + space + w > width then
                rows = rows + 1;used = w
            else
                used = used + space + w
            end
        end
    end
    return rows
end

-- Text policy for flowed detail views: a FontString gets a fixed width and
-- the height its wrapped text needs, measured by the client (height 0 at a
-- fixed width wraps; GetStringHeight is then the wrapped height). Without a
-- measurement the conservative model above stands in. maximum, when given,
-- caps the height; the caller must then keep the full text reachable.
-- Returns the height set and whether it was capped.
function M.WrapHeight(fontString, width, minimum, maximum)
    width = math.max(1, math.floor(tonumber(width) or 1))
    fontString:SetWidth(width)
    fontString:SetHeight(0)
    local measured
    if type(fontString.GetStringHeight) == "function" then
        local ok, value = pcall(fontString.GetStringHeight, fontString)
        value = ok and tonumber(value) or nil
        if value and value > 0 and value < math.huge then measured = value end
    end
    if not measured then
        local scale = RuntimeFontScale()
        local _, line = M.ConservativeText(scale)
        local text = type(fontString.GetText) == "function"
            and fontString:GetText() or ""
        measured = M.TextRows(text, width, scale) * line
    end
    local height = math.max(tonumber(minimum) or 1, math.ceil(measured))
    local capped = maximum and height > maximum or false
    if capped then height = math.max(1, math.floor(maximum)) end
    fontString:SetHeight(height)
    return height, capped
end

-- True when a one-line FontString's text is wider than its box, so the
-- client shows it shortened.
function M.Shortened(fontString)
    if not (fontString and fontString:IsShown()) then return false end
    local ok, width = pcall(fontString.GetStringWidth, fontString)
    width = ok and tonumber(width) or nil
    return width == nil or width > (tonumber(fontString:GetWidth()) or 0)
end

-- True while GameTooltip still belongs to owner. Another frame may take the
-- tooltip after owner showed it; that frame's tooltip is then left alone.
-- Without an ownership query the previous behaviour (true) is kept.
local function HoldsTooltip(owner)
    if type(GameTooltip.IsOwned) == "function" then
        return GameTooltip:IsOwned(owner) and true or false
    end
    if type(GameTooltip.GetOwner) == "function" then
        return GameTooltip:GetOwner() == owner
    end
    return true
end

-- Fixed row labels keep one line at the row's height, so a long name never
-- spills over the next row; the client shortens the rest. While shortened,
-- the owner (the row or button) shows the complete text in a tooltip beside
-- it. Existing OnEnter/OnLeave scripts of the owner keep running.
function M.OneLineLabel(fontString, owner, height, anchor)
    fontString:SetHeight(height)
    if type(fontString.SetWordWrap) == "function" then
        pcall(fontString.SetWordWrap, fontString, false)
    end
    if not owner or owner._nexusOneLine then
        if owner then owner._nexusOneLine = fontString end
        return
    end
    owner._nexusOneLine = fontString
    owner:HookScript("OnEnter", function(self)
        local label = self._nexusOneLine
        if not (GameTooltip and M.Shortened(label)) then return end
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        GameTooltip:AddLine(tostring(label:GetText() or ""), 1, 1, 1, true)
        GameTooltip:Show()
        self._nexusOneLineTip = true
    end)
    owner:HookScript("OnLeave", function(self)
        if self._nexusOneLineTip and GameTooltip and HoldsTooltip(self) then
            GameTooltip:Hide()
        end
        self._nexusOneLineTip = nil
    end)
end

-- True when a wrapped FontString's text needs more height than its box. The
-- box height is restored; measure on demand (hover), not every refresh.
function M.Overflows(fontString)
    if not (fontString and fontString:IsShown()) then return false end
    local text = fontString:GetText()
    if text == nil or text == "" then return false end
    local height = tonumber(fontString:GetHeight()) or 0
    fontString:SetHeight(0)
    local ok, measured = pcall(fontString.GetStringHeight, fontString)
    fontString:SetHeight(height)
    measured = ok and tonumber(measured) or nil
    return measured == nil or measured > height + 0.5
end

-- A fixed multi-line text box keeps its size; while its text overflows, a
-- hover area over it shows the complete text in a tooltip. An owner that
-- shortened a value itself stores the complete text in _nexusFullText, which
-- the tooltip then shows even when the shortened text fits.
function M.FullTextTooltip(fontString, parent, anchor)
    local hit = CreateFrame("Frame", nil, parent)
    hit:SetAllPoints(fontString)
    hit:EnableMouse(true)
    hit._nexusText = fontString
    hit:SetScript("OnEnter", function(self)
        local label = self._nexusText
        local full = label._nexusFullText
        if not (GameTooltip and (full or M.Overflows(label))) then return end
        GameTooltip:SetOwner(self, anchor or "ANCHOR_TOP")
        GameTooltip:AddLine(tostring(full or label:GetText() or ""), 1, 1, 1, true)
        GameTooltip:Show()
        self._nexusTip = true
    end)
    hit:SetScript("OnLeave", function(self)
        if self._nexusTip and GameTooltip then GameTooltip:Hide() end
        self._nexusTip = nil
    end)
    return hit
end

-- A fixed-size window wider or taller than the visible UI (a 1024 or 960 px
-- wide UI at scale 1 on 4:3 and 5:4 screens) is scaled down to fit with a
-- margin, so its edges and close button stay on screen; one that fits keeps
-- scale 1. An implausibly small reported UI size is not acted on. `ceiling`
-- (the main panel's chosen size, issue #170) replaces that 1 as the largest
-- scale; a missing or invalid ceiling is 1. Width and height are the frame's
-- own size and the screen is UIParent's, both in UIParent-relative units, so
-- no effective scale is multiplied in.
function M.FitToScreen(frame, margin, ceiling)
    margin = tonumber(margin) or 24
    ceiling = type(ceiling) == "number" and ceiling == ceiling and ceiling > 0
        and ceiling < math.huge and ceiling or 1
    local width, height = tonumber(frame:GetWidth()), tonumber(frame:GetHeight())
    local screenW = UIParent and tonumber(UIParent:GetWidth())
    local screenH = UIParent and tonumber(UIParent:GetHeight())
    -- Finite sizes only (review of e1183fd): an infinite size would make a
    -- ratio infinite or zero and step past the ceiling or the floor.
    local function Finite(v) return v ~= nil and v == v and v > -math.huge and v < math.huge end
    if not (Finite(width) and Finite(height) and Finite(screenW) and Finite(screenH))
        or width <= 0 or height <= 0 or not (screenW >= 640 and screenH >= 480) then return nil end
    local scale = math.max(0.5, math.min(ceiling, (screenW - margin) / width,
        (screenH - margin) / height))
    if math.abs((tonumber(frame:GetScale()) or 1) - scale) > 0.001 then
        frame:SetScale(scale)
    end
    return scale
end

-- Button width for its current label: the client's text width when it
-- reports one, otherwise the conservative character model, plus end caps.
function M.FitButtonWidth(button, minimum, maximum)
    local text = tostring(button:GetText() or "")
        :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local width
    if type(button.GetTextWidth) == "function" then
        local ok, value = pcall(button.GetTextWidth, button)
        value = ok and tonumber(value) or nil
        if value and value > 0 and value < math.huge then width = value end
    end
    if not width then
        local char = M.ConservativeText(RuntimeFontScale())
        width = #(text:gsub("[\128-\191]", "")) * char
    end
    width = math.max(tonumber(minimum) or 1, math.ceil(width + 24))
    if maximum then width = math.min(maximum, width) end
    button:SetWidth(width)
    return width
end

-- A DPS entry of the panel spec as a key part: absent, unmeasured (true) or
-- its measured label and value widths.
local function RecordKey(entry)
    if type(entry) == "table" then
        return math.ceil(tonumber(entry[1]) or 0) .. ":" .. math.ceil(tonumber(entry[2]) or 0)
    end
    return entry and "1" or "0"
end

-- A measurement a caller took from the client (a line height, a label
-- width): a finite number above 0, else 0 (not measured).
local function Measured(value)
    value = tonumber(value)
    if value and value == value and value > 0 and value < math.huge then return value end
    return 0
end

local function PanelKey(spec)
    return table.concat({
        Round(spec.width or 272,1),Round(spec.fontScale or 1,3),
        Round(spec.uiScale or 1,3),tonumber(spec.revision) or 0,
        spec.activeRoll and 1 or 0,spec.statusVisible and 1 or 0,
        spec.noBuild and 1 or 0,spec.complete and 1 or 0,
        spec.showPerformance and 1 or 0,
        (tonumber(spec.toLockCount) or 0) > 0 and 1 or 0,
        (tonumber(spec.unknownTomes) or 0) > 0 and 1 or 0,
        spec.orbButton and 1 or 0,tonumber(spec.guidanceRows) or 0,
        spec.cardRows and 1 or 0,
        spec.callboard and 1 or 0,
        spec.planDetails and 1 or 0,spec.orbLine and 1 or 0,
        tonumber(spec.autoScopeRows) or 0,
        spec.noOffer and 1 or 0,
        math.ceil(tonumber(spec.detailNamesH) or 0),
        RecordKey(spec.recordYours),RecordKey(spec.recordBest),
        spec.autoInfo and 1 or 0,
        math.ceil(tonumber(spec.statusTierH) or 0),spec.statusBar == false and 0 or 1,
        type(spec.offerRowsH) == "table" and (math.ceil(tonumber(spec.offerRowsH[1]) or 0) .. ":"
            .. math.ceil(tonumber(spec.offerRowsH[2]) or 0) .. ":" .. math.ceil(tonumber(spec.offerRowsH[3]) or 0)) or 0,
        math.ceil(tonumber(spec.bodyH) or 0),math.ceil(tonumber(spec.bodyFloorH) or 0),
        math.ceil(tonumber(spec.headerBuildH) or 0),math.ceil(tonumber(spec.headerWishlistH) or 0),
        math.ceil(tonumber(spec.callboardTitleH) or 0),math.ceil(tonumber(spec.callboardDetailH) or 0),
        math.ceil(tonumber(spec.callboardLabelW) or 0),
        spec.callboardInline and 1 or 0,math.ceil(Measured(spec.progressLabelW)),
        math.ceil(Measured(spec.toLockH)),
        type(spec.offerRowsPx) == "table" and (math.ceil(tonumber(spec.offerRowsPx[1]) or 0) .. ":"
            .. math.ceil(tonumber(spec.offerRowsPx[2]) or 0) .. ":" .. math.ceil(tonumber(spec.offerRowsPx[3]) or 0)) or 0,
        spec.performanceH == nil and "m" or math.ceil(tonumber(spec.performanceH) or 0),
        math.ceil(tonumber(spec.progressValueH) or 0),
        type(spec.countRowsH) == "table" and (math.ceil(tonumber(spec.countRowsH[1]) or 0) .. ":"
            .. math.ceil(tonumber(spec.countRowsH[2]) or 0)) or 0,
        math.ceil(tonumber(spec.footerH) or 0),
        spec.autoInfoInline and 1 or 0,math.ceil(tonumber(spec.autoInfoW) or 0),
        math.ceil(tonumber(spec.headingH) or 0),
        type(spec.offerReason) == "table" and (tostring(spec.offerReason.row) .. ":"
            .. math.ceil(tonumber(spec.offerReason.top) or 0)) or 0,
        spec.measured and 1 or 0,math.ceil(tonumber(spec.reservedRollH) or 0),
        math.ceil(tonumber(spec.orbLineH) or 0),
        spec.orbDetail and 1 or 0,math.ceil(tonumber(spec.orbDetailH) or 0),
        math.ceil(tonumber(spec.headerTitleH) or 0),
        math.ceil(Measured(spec.lineSmallH)),math.ceil(Measured(spec.planDetailsW)),
        math.ceil(Measured(spec.setupTitleH)),math.ceil(Measured(spec.setupHintH)),
        math.ceil(Measured(spec.completeTitleH)),math.ceil(Measured(spec.completeTextH)),
        math.ceil(Measured(spec.listHeadingH)),
        math.ceil(Measured(spec.headerControlsH)),math.ceil(Measured(spec.planDetailsH)),
        math.ceil(Measured(spec.progressLabelH)),
    }, "|")
end

-- The former two-line offer rows (the main panel's rows are the approved
-- compact ones now: M.Compact, M.Panel; this helper and M.OfferRowGrid are
-- kept as they were for any other caller). The three offer rows of the roll
-- box, from the panel's text lines and section gap. A row is a fixed grid of two text lines: the
-- offer's name on its primary line (`normal`) and its quality on the
-- secondary line under it (`small`), with a row gap above and below them
-- (M.OfferRowGrid gives the columns). Every row has that same base height,
-- so the three rows keep one rhythm; a row whose own text needs more grows
-- by its measured height (M.Panel: spec.offerRowsH). Rows are a row gap
-- apart, and the band keeps two row gaps under the heading line and above
-- the text below. Returns, from the roll box's top: the first row's top, a
-- row's height, the gap between rows and where the text under the rows
-- starts. At font scale 1 (small 11, normal 14, gap 6): 16, 29, 2 and 111.
-- A caller without the primary line gets the two lines' 14 : 11 share of
-- the small line, the proportion the layout's own rows have.
function M.OfferRows(small, gap, normal)
    local rowGap = math.max(2, math.floor(gap / 3))
    normal = tonumber(normal) or math.ceil(small * 14 / 11)
    local rowH = normal + small + 2 * rowGap
    local top = 1 + small + 2 * rowGap
    return top, rowH, rowGap, top + 3 * rowH + 4 * rowGap
end

-- The grid inside one offer row `width` units wide, for its placement and
-- its measurement (Panel.PlaceOfferCards, Panel.MeasuredLayout): the row's
-- content is inset one layout gap from both ends; the icon is a square as
-- tall as the two text lines, at the left; the text column starts one gap
-- after it and the status column ends at the right inset. `content` is the
-- room the text and status columns share; `pad` is the row gap kept above
-- and below the lines.
function M.OfferRowGrid(small, gap, normal, width)
    local _, rowH, rowGap = M.OfferRows(small, gap, normal)
    normal = tonumber(normal) or math.ceil(small * 14 / 11)
    local icon = normal + small
    local textX = gap + icon + gap
    return {
        rowH=rowH,pad=rowGap,inset=gap,gap=gap,icon=icon,textX=textX,
        nameH=normal,metaH=small,
        content=math.max(1, math.floor(tonumber(width) or 0) - textX - gap),
    }
end

-- The main panel's design-base width, 284 units at font scale 1 (it was
-- 420), and the unit of the approved compact design (design draft "Nexus
-- compact panel", difficulty B with its bar and ticks, inline Callboard).
--
-- What 284 is: one fixed layout parameter of this panel, calibrated once
-- from a measurement of the build before it. That build's panel followed
-- this file's own width rule with a 420-unit base, and at the reference
-- client settings it was measured 672 UI units wide and 621 pixels wide in
-- an unresized capture. The approved design is drawn in the pixels of that
-- capture and is 420 of them wide at the same text size, so the base that
-- gives that width under the unchanged rule is 420 x 420 / 621 = 284.06,
-- taken as 284.
--
-- What it is not: a pixel-per-unit, DPI or UI-scale conversion, a multiplier
-- applied while the addon runs, or a figure that holds for another client
-- setting or another capture. No client scale, effective scale or font size
-- is stored or assumed here. The width is still this base times the font
-- scale the owned fonts follow, bounded by the screen (M.PanelWidth, whose
-- rule is unchanged), so the panel follows the client's text size and screen
-- as it did. No font is made smaller and nothing is scaled as a whole: only
-- the room around the text is.
--
-- It is a calculation from one measured baseline, not a measurement of this
-- layout: the width and heights the client really gives the compact panel
-- are known only from the client. A block that needs more than the design
-- draws takes it (M.Panel); no height is reached by cutting or clamping.
--
-- One design pixel is PANEL_BASE_WIDTH / PANEL_DESIGN_WIDTH units times the
-- font scale (M.Design): the design's lengths keep their proportion to the
-- panel's width at every text scale.
M.PANEL_BASE_WIDTH = 284
M.PANEL_DESIGN_WIDTH = 420

-- A length of the approved design, given in its reference pixels, in whole
-- UI units at a font scale (0.75 to 2; 1 without a valid one). A length
-- above 0 is at least 1 unit.
function M.Design(pixels, scale)
    pixels = tonumber(pixels)
    if not (pixels and pixels == pixels and pixels > 0 and pixels < math.huge) then return 0 end
    scale = tonumber(scale)
    if not (scale and scale == scale) then scale = 1 end
    scale = Clamp(scale, 0.75, 2)
    return math.max(1, math.floor(pixels * M.PANEL_BASE_WIDTH / M.PANEL_DESIGN_WIDTH * scale + 0.5))
end

-- The approved compact panel's own lengths at a font scale, each named for
-- what it is in the design and given there in reference pixels (the number
-- in each call). One table per scale, kept: a layout pass builds nothing.
-- These are the lengths inside a block (insets, columns, icons, controls);
-- where the blocks stand, and how tall each is, M.Panel takes from the
-- design's own coordinates. Text heights are not in it: every row is at
-- least its design height and grows by the height the client measures for
-- its text (M.Panel).
-- The grip is the at-least-24 x 24 UI-unit drag target at every scale; where
-- that is larger than the design's 24 pixels, header line 1 is as tall as
-- the grip less the one pixel the design lets it stand out above and below.
local compactCache, compactCount = {}, 0
function M.Compact(scale)
    scale = tonumber(scale)
    if not (scale and scale == scale) then scale = 1 end
    scale = Clamp(scale, 0.75, 2)
    local key = Round(scale, 3)
    local held = compactCache[key]
    if held then return held end
    local function D(pixels) return M.Design(pixels, scale) end
    local grip = math.max(24, D(24))
    -- The room around the words of a button whose label is held inside the
    -- button's end caps (Options; My Builds and Change): the design's 14
    -- pixels, and never under 14 units, which are the label's two 6-unit end
    -- caps and 2 to spare. So such a label is never cut by its own button at
    -- a text size where 14 design pixels are fewer units than that (under
    -- about one and a half times the normal size).
    local labelPad = math.max(D(14), 14)
    local compact = {
        scale = scale,
        -- The panel: its side inset (the 1-pixel edge and 6), the gap under
        -- the header, the gap between body blocks, the room from the body
        -- to the footer hubs and under them.
        inset = D(7), headerGap = D(6), blockGap = D(5), footerGap = D(12), footerBottom = D(6),
        -- Header line 1: the grip, the title and Auto, Options and Close.
        headerTop = D(5), controlH = D(22), grip = grip, line1H = math.max(D(22), grip - 2 * D(1)),
        controlGap = D(6), closeW = D(24), autoPad = D(16), optionsPad = labelPad,
        -- The Build and Wishlist rows and their buttons.
        headerRowGap = D(2), headerRowH = D(20), headerBottom = D(5), captionGap = D(6), buttonPad = labelPad,
        -- The difficulty band (B): its frame and inner edge, the text line
        -- and the Intensity bar under it.
        bandH = D(34), bandPlainH = D(26), bandPadY = D(3), bandPadX = D(8), bandGap = D(10),
        bandBarTop = D(1), bandBarH = D(4), bandBarBottom = D(3),
        -- The Callboard line.
        callboardH = D(20), callboardLine = D(18), callboardIcon = D(16), callboardIconTop = D(2),
        callboardIconGap = D(6), callboardLabelGap = D(8), callboardLineGap = D(10),
        -- The offer heading and rows.
        headingH = D(18), headingGap = D(3), rowH = D(28), rowLine = D(24), rowPadY = D(2), rowPadX = D(6),
        rowGap = D(2), icon = D(24), iconGap = D(8), metaGap = D(10), wordGap = D(5), reasonLine = D(18),
        mark = D(12), markGap = D(4),
        -- The progress row and the open Details block.
        progressH = D(22), progressGap = D(8), progressBar = D(6), progressBarMin = D(40),
        detailsPad = D(14), detailsH = D(20), detailGap = D(3), valueLine = D(20), countLine = D(18),
        countGap = D(1), countColumnGap = D(12), listGap = D(5), listLine = D(18), listColumnGap = D(8),
        -- The footer hubs.
        hubH = D(26), hubGap = D(6), hubPad = D(3),
    }
    if compactCount >= MAX_CACHE_ENTRIES then compactCache, compactCount = {}, 0 end
    compactCache[key] = compact
    compactCount = compactCount + 1
    return compact
end

-- The main panel's width for a text scale: the reference width (above) times
-- the font scale the owned fonts follow (never narrower than the reference,
-- and at most twice it: the largest supported scale), bounded by the room
-- the screen leaves the panel at its chosen size (`screenWidth` in UIParent
-- units less M.FitToScreen's 24-unit margin, over `panelScale`), so a wider
-- panel is never one the fit would then have to scale down for its width. A
-- screen width that is not plausible (M.FitToScreen's own 640-unit floor)
-- bounds nothing. One deterministic value from its three inputs: the caller
-- reads them once per render and nothing is fed back from the fitted size.
-- Returns whole units.
function M.PanelWidth(fontScale, screenWidth, panelScale)
    local base = M.PANEL_BASE_WIDTH
    local scale = tonumber(fontScale)
    if not (scale and scale == scale) then scale = 1 end
    scale = Clamp(scale, 1, 2)
    local width = math.floor(base * scale + 0.5)
    screenWidth = tonumber(screenWidth)
    if screenWidth and screenWidth == screenWidth and screenWidth >= 640 and screenWidth < math.huge then
        panelScale = Measured(panelScale)
        if panelScale <= 0 then panelScale = 1 end
        width = math.min(width, math.floor((screenWidth - 24) / panelScale))
    end
    return math.max(base, width)
end

-- The three footer hubs across a row `full` units wide: three hubs of one
-- width, `gap` apart, that together span the row exactly. What three equal
-- whole widths leave over (0 to 2 units) goes to the two gaps, never to one
-- hub. Returns the hub width and the two gaps.
function M.FooterColumns(full, gap)
    full = math.max(3, math.floor(tonumber(full) or 0))
    gap = math.max(0, math.floor(tonumber(gap) or 0))
    local hub = math.max(1, math.floor((full - 2 * gap) / 3))
    local spare = math.max(0, full - 2 * gap - 3 * hub)
    return hub, gap + math.ceil(spare / 2), gap + math.floor(spare / 2)
end

-- The approved compact panel, block by block from the top: the header, the
-- difficulty band, the Callboard line, the offer heading and rows, the
-- progress row with the Details block under it while that is open, the
-- records, and one line of footer hubs.
-- Heights and gaps are the design's, given below in its reference pixels
-- (the first number of each Block and Gap). They are added up in the
-- design's own pixels and each block's top is that sum in whole units, so a
-- block stands where the design draws it at every font scale and no rounding
-- adds up down the panel: the whole panel is the design's height in units,
-- to the unit, while every text fits its design row.
-- Every block is as tall as the design draws it while its content fits
-- there, and as tall as its content when that needs more (the second number
-- of a Block: the heights the caller measured, in units); what is under it
-- then starts lower by exactly the difference. Nothing is shortened, cut or
-- held to a number of lines, and a block that is absent leaves no row, rule
-- or gap. Lengths inside a block are M.Compact's.
function M.Panel(spec)
    spec = type(spec) == "table" and spec or {}
    stats.requests = stats.requests + 1
    local key = PanelKey(spec)
    if panelCache[key] then
        stats.hits = stats.hits + 1
        return panelCache[key]
    end
    stats.computations = stats.computations + 1

    local scale = Clamp(spec.fontScale or 1, 0.75, 2)
    local compact = M.Compact(scale)
    local width = math.max(240, math.floor(tonumber(spec.width) or 272))
    local small = math.ceil(11 * scale)
    local normal = math.ceil(14 * scale)
    local large = math.ceil(16 * scale)
    local gap = math.ceil(6 * scale)
    -- One line of the panel's secondary text is as tall as the client
    -- measures it (spec.lineSmallH), never under the modelled small row: a
    -- face whose line is taller than its nominal size keeps its whole line
    -- wherever a row holds one line of that text. Without a measurement the
    -- small row stands (the caller passes only a height the client itself
    -- reported: Panel.ClientLineHeight).
    local lineSmall = math.max(small, math.ceil(Measured(spec.lineSmallH)))
    local layout = {
        kind="panel",width=width,boxes={},required={},scale=scale,
        key=key,small=small,normal=normal,large=large,gap=gap,
        lineSmall=lineSmall,compact=compact,
    }
    -- The charges cell of the offer heading row. 72 units hold the compact
    -- row at the 10-unit small size; the cell is never narrower than that,
    -- and chargesGap separates it from the heading. The panel gives the cell
    -- the width its own row of counts measures on one line, while the
    -- heading keeps at least those 72 units (Panel.ChargesCell); chargesW,
    -- the cell the font scale alone would give, is kept for other readers.
    layout.chargesMinW, layout.chargesGap = 72, 4
    layout.chargesW = math.max(72, math.floor(72 * scale + 0.5))
    local inset = compact.inset
    local full = width - inset * 2
    layout.inset, layout.full = inset, full

    -- `drawn`: how far down the design is, in units, unrounded. `grown`:
    -- the whole units content has added beyond the design so far. `cursor`:
    -- where the next block starts. `closing`: the design gap given last.
    local unit = M.PANEL_BASE_WIDTH / M.PANEL_DESIGN_WIDTH * scale
    local drawn, grown, cursor, closing = 0, 0, 0, 0
    local function Gap(pixels)
        drawn = drawn + pixels * unit
        cursor = math.floor(drawn + 0.5) + grown
        closing = pixels
    end
    local function Block(pixels, need)
        local top = cursor
        drawn = drawn + pixels * unit
        local height = math.floor(drawn + 0.5) + grown - top
        need = math.ceil(tonumber(need) or 0)
        if need > height then
            grown = grown + need - height
            height = need
        end
        cursor = top + height
        closing = 0
        return top, height
    end
    -- Where a block would start after a design gap of `pixels` from here
    -- (nothing is laid out).
    local function After(pixels)
        return math.floor(drawn + pixels * unit + 0.5) + grown
    end
    -- A part of the panel that is there only at times (the Callboard, the
    -- Auto lines, the Orb line, the open Details, the records) is laid out
    -- from its own top with a design cursor of its own, and what it adds to
    -- the panel is a whole number of units. So every block under it moves
    -- by exactly its height when it appears or goes, and the rest of the
    -- panel is laid out the same with or without it.
    local function Section(body)
        local heldDrawn, heldGrown, top = drawn, grown, cursor
        drawn, grown = 0, top
        body()
        local height = cursor - top
        drawn, grown = heldDrawn, heldGrown + height
        cursor = math.floor(drawn + 0.5) + grown
    end

    -- The header. Line 1 (22) holds the grip, the title and the three
    -- controls; it is never under the 24-unit grip less the one design pixel
    -- the grip stands out above and below it, and a title that needs more (a
    -- state cue that wraps in the title's slot, a line taller than the row)
    -- takes its measured height (spec.headerTitleH). The Build and Wishlist
    -- rows follow 2 apart, each 20 while its name fits one line there; a name
    -- too long for its line wraps beside its button and the row is its
    -- measured height (spec.headerBuildH, spec.headerWishlistH: the caller
    -- gives the taller of the name and of a row button whose own label
    -- wraps).
    -- Line 1 also holds its controls whole: where a control's label wraps in
    -- the control (a long translation of Options or Auto, or the Auto state
    -- words in the Auto slot), the caller gives what the line must be tall
    -- for it (spec.headerControlsH), and the line grows by what that is over
    -- the title's own row. The title keeps its own height
    -- (layout.headerTitleH); the rows under line 1 start lower by the
    -- difference.
    Gap(5)
    local headerTop = cursor
    local _, titleH = Block(22, math.max(compact.grip - 2 * M.Design(1, scale),
        math.ceil(tonumber(spec.headerTitleH) or 0)))
    local controlsH = math.ceil(Measured(spec.headerControlsH))
    if controlsH > titleH then Block(0, controlsH - titleH) end
    Gap(2)
    local buildY, buildH = Block(20, spec.headerBuildH)
    Gap(2)
    local wishlistY, wishlistH = Block(20, spec.headerWishlistH)
    Gap(5)
    layout.headerLine, layout.headerTitleH = compact.headerRowH, titleH
    layout.headerBuildY, layout.headerBuildH = buildY, buildH
    layout.headerWishlistY, layout.headerWishlistH = wishlistY, wishlistH
    Add(layout,"header",inset,headerTop,full,cursor-headerTop)
    Gap(6)

    local play = not spec.noBuild and not spec.complete
    layout.play = play
    if spec.statusVisible then
        -- The difficulty band (B): the original card's frame around one text
        -- line (the tier, Soul Ash and the multiplier) with the Intensity bar
        -- and its ticks under it: 34, or 26 without a validated Intensity
        -- scale (spec.statusBar false: no room is kept for a bar). Where the
        -- band's words need more than that line (spec.statusTierH, the
        -- measured height of its text block: a long tier that wraps, Soul Ash
        -- on a line of its own under it), the band grows by exactly that.
        local bar = spec.statusBar ~= false
        local around = 2 * compact.bandPadY
            + (bar and (compact.bandBarTop + compact.bandBarH + compact.bandBarBottom) or 0)
        local top, height = Block(bar and 34 or 26, around + math.max(1, math.ceil(tonumber(spec.statusTierH) or 0)))
        layout.statusInset, layout.statusTierH = compact.bandPadY, height - around
        layout.statusBarH = bar and compact.bandBarH or 0
        Add(layout,"status",inset,top,full,height)
        Gap(5)
    end
    if spec.callboard then
        -- The Callboard: its icon, its label and the objective's title on one
        -- line (20), with the objective's progress at the right end of that
        -- line while the caller found that one line of it fits there
        -- (spec.callboardInline). Otherwise the progress lines stand under
        -- the title from the label's left edge, whole, at their measured
        -- height (spec.callboardDetailH; one line is 18), and a title too
        -- long for its column wraps there (spec.callboardTitleH). Nothing is
        -- shortened or cut to one line, and the block has no rule.
        Section(function()
            local inline = spec.callboardInline and true or false
            local top, titleRow = Block(20, spec.callboardTitleH)
            local detailH = 0
            if not inline then
                local _, measured = Block(18, spec.callboardDetailH)
                detailH = measured
            end
            local char = M.ConservativeText(scale)
            layout.callboardLine = compact.callboardH
            layout.callboardTitleH, layout.callboardDetailH, layout.callboardInline = titleRow, detailH, inline
            layout.callboardIcon = compact.callboardIcon
            layout.callboardLabelW = math.ceil(tonumber(spec.callboardLabelW) or (9 * char * 1.1))
            Add(layout,"callboard",inset,top,full,titleRow + detailH)
            Gap(5)
        end)
    end
    if spec.activeRoll and spec.noOffer then
        -- Level 80, normal rolls finished, no offer (the collapsed state): no
        -- heading row and no offer rows. One guidance block of the
        -- conservative model's rows (the caller counts them at the width
        -- left of the button) with the passive Open Orbs... button inline at
        -- its right, exactly as tall as its guidance (or the button), one
        -- block gap from its neighbours.
        local char, line = M.ConservativeText(scale)
        local rows = math.max(1, tonumber(spec.guidanceRows) or 1)
        layout.noOffer = true
        layout.noOfferGap = compact.blockGap
        if spec.orbButton then
            layout.orbButtonH = math.max(small + 6, line)
            layout.orbButtonW = math.min(full, math.ceil(12 * char) + 20)
        end
        local top, height = Block(0, math.max(rows * line, layout.orbButtonH or 0))
        Add(layout,"roll",inset,top,full,height)
        Gap(5)
    elseif spec.activeRoll then
        -- The offer block. The heading row (18, or the measured height of a
        -- heading or charges text that wraps: spec.headingH), then, 3 under
        -- it, the three offer rows 2 apart: each 28 with its name and its
        -- quality and status on one line, and as tall as its own measured
        -- content when that needs more (spec.offerRowsH: a wrapped name, a
        -- status on a line of its own). The selected offer's reason stands
        -- inside its row, under those lines (spec.offerReason: {row, top,
        -- h}): that row is 46 with one line of it and grows with a longer
        -- one.
        -- Text that is not such a reason stands 3 under the rows (or under
        -- the heading without rows) at its measured height (spec.bodyH), and
        -- the passive Open Orbs... row closes the block. The block is exactly
        -- its content; one kept through a gap between boards keeps the
        -- height it had (spec.reservedRollH), so the panel does not jump.
        local top, headH = Block(18, spec.headingH)
        layout.headingH, layout.headingExtra = headH, headH - compact.headingH
        -- The control of the Auto scope line shares the heading row while
        -- the caller found room for it there (spec.autoInfoInline, at its
        -- measured width spec.autoInfoW); it then takes no row of its own.
        layout.autoInfoInline = spec.autoInfo and spec.autoInfoInline and true or false
        if spec.cardRows then
            local rows = type(spec.offerRowsH) == "table" and spec.offerRowsH or nil
            local reason = rows and type(spec.offerReason) == "table" and spec.offerReason or nil
            -- spec.offerRowsPx: the design's own height of each row as the
            -- caller arranged it, in reference pixels (28; 24 more with the
            -- status on a line of its own; 18 more with the reason's line).
            -- Without it, 28, and 46 for the row that holds the reason.
            local drawnRows = rows and type(spec.offerRowsPx) == "table" and spec.offerRowsPx or nil
            local tops, heights = {}, {}
            for index = 1, 3 do
                Gap(index == 1 and 3 or 2)
                local pixels = drawnRows and tonumber(drawnRows[index])
                    or ((reason and reason.row == index) and 46 or 28)
                local rowTop, rowHeight = Block(pixels, rows and rows[index] or 0)
                tops[index], heights[index] = rowTop - top, rowHeight
            end
            layout.offerRowTops, layout.offerRowHeights = tops, heights
            layout.offerRowsH, layout.offerReason = rows, reason
        end
        -- Where the text under the heading or the rows starts: the whole
        -- unit the layout gives it 3 under them (below), not their end plus
        -- a gap rounded on its own, which can be one unit lower.
        layout.bodyTop = After(3) - top
        local buttonH = 0
        if spec.orbButton then
            -- Its own row for the passive "Open Orbs..." button, sized for
            -- its 12-character label in the conservative text model plus the
            -- template's end caps, and at least one of its lines high.
            local char, line = M.ConservativeText(scale)
            layout.orbButtonH = math.max(small + 6, line)
            layout.orbButtonW = math.min(full, math.ceil(12 * char) + 20)
            -- The optional mini-panel access shares this row, immediately
            -- left of Open Orbs. Keep the existing window/button geometry.
            layout.orbMiniButtonGap = 6
            local available = full - layout.orbButtonW - layout.orbMiniButtonGap
            -- Its label is the panel's 11-unit secondary text, a tenth wider
            -- than the 10-unit small font the model's character is for, and
            -- is never fitted below that size: the full label's width
            -- allows for it.
            local fullWidth = math.ceil(14 * char * 1.1) + 20
            layout.orbMiniButtonW = math.max(1, math.min(fullWidth, available))
            -- The width rule above is unchanged; only the chosen label is
            -- shown in the session's language (ShownLabel).
            layout.orbMiniButtonLabel = fullWidth <= available
                and ShownLabel("layout.button.orb_mini_panel", "Orb mini panel")
                or ShownLabel("layout.button.orb_mini_short", "Mini")
            buttonH = layout.orbButtonH
        end
        local bodyH = math.ceil(tonumber(spec.bodyH) or 0)
        if not spec.measured then
            -- A caller that measured nothing: the conservative model's rows
            -- for the Orb guidance body (spec.guidanceRows), never under a
            -- measured text.
            local rows = tonumber(spec.guidanceRows) or 0
            if rows > 0 then
                local _, line = M.ConservativeText(scale)
                bodyH = math.max(bodyH, rows * line)
            end
        elseif bodyH > 0 then
            -- spec.bodyFloorH: the rows of the conservative text model for a
            -- text that must stay readable in a face wider than the measured
            -- one (the Orb guidance, an Orb pause reason, the inline Auto
            -- line). The text is never shorter than that while nothing else
            -- holds the block's height. In a block kept through a gap
            -- between boards the text takes the room that block already has,
            -- up to the floor, and the block itself grows only for the
            -- measured text: the footprint of an Auto cycle stays the
            -- board's.
            local floorH = math.ceil(tonumber(spec.bodyFloorH) or 0)
            if floorH > bodyH then
                local reserved = math.ceil(tonumber(spec.reservedRollH) or 0)
                if reserved > 0 then
                    -- (What the block holds with this text: the text 3
                    -- under the heading or the rows and, with the button,
                    -- its row 3 under the text.)
                    local used = (buttonH > 0 and (After(6) + buttonH) or After(3)) - top + bodyH
                    bodyH = bodyH + math.max(0, math.min(floorH - bodyH, reserved - used))
                else
                    bodyH = floorH
                end
            end
        end
        layout.bodyH = bodyH
        if bodyH > 0 then
            Gap(3)
            Block(0, bodyH)
        end
        if buttonH > 0 then
            Gap(3)
            Block(0, buttonH)
        end
        if spec.measured then
            -- A block kept between boards is never shorter than it was.
            Block(0, math.ceil(tonumber(spec.reservedRollH) or 0) - (cursor - top))
        end
        Add(layout,"roll",inset,top,full,cursor-top)
        Gap(5)
        -- The Auto scope line under the offer (the Auto ON note) is behind
        -- an optional control (spec.autoInfo). While the control shares the
        -- heading row it has no box; at a text size where it does not fit
        -- there it takes one short row of its own under the offer. The
        -- line's own rows are laid out only while it is open (the caller
        -- then gives autoScopeRows, counted at the block's width).
        if spec.autoInfo then
            local char, line = M.ConservativeText(scale)
            layout.autoInfoW = math.min(full, math.ceil(tonumber(spec.autoInfoW) or (math.ceil(16 * char) + 20)))
            if layout.autoInfoInline then
                -- What the heading row keeps free at its right for it.
                layout.headingReserve = layout.autoInfoW + 4
            else
                Section(function()
                    local infoTop, infoH = Block(0, math.max(small + 6, line))
                    Add(layout,"autoInfo",inset,infoTop,layout.autoInfoW,infoH)
                    Gap(5)
                end)
            end
        end
        local scopeRows = tonumber(spec.autoScopeRows) or 0
        if scopeRows > 0 then
            Section(function()
                local _, line = M.ConservativeText(scale)
                local scopeTop, scopeH = Block(0, scopeRows * line)
                Add(layout,"autoScope",inset,scopeTop,full,scopeH)
                Gap(5)
            end)
        end
    end
    if spec.orbLine and not spec.noBuild then
        -- The Orb run status with Open, right under the offer; the Orb
        -- window owns the run's controls. Its text wraps beside the button
        -- in its measured height (spec.orbLineH).
        Section(function()
            local char, line = M.ConservativeText(scale)
            local buttonH = math.max(small + 6, line)
            local openW = math.min(full, math.ceil(6 * char) + 20)
            layout.orbLineOpenW = openW
            local top, height = Block(0, math.max(buttonH, math.ceil(tonumber(spec.orbLineH) or 0)))
            Add(layout,"orbLine",inset,top,math.max(1,full-openW-compact.progressGap),height)
            Add(layout,"orbLineOpen",width-inset-openW,top,openW,buttonH)
            Gap(5)
        end)
    end
    layout.contentTop = cursor

    -- The opt-in DPS RECORDS section (spec.showPerformance). Its height is
    -- the measured height of the rows that exist (spec.performanceH): only
    -- records that exist have a row, and without any there is no section,
    -- heading or reserved block (0). A caller that measured nothing (nil)
    -- gets the modelled block.
    local function Performance(modelled)
        if not spec.showPerformance then return end
        local need = spec.performanceH == nil and modelled or math.ceil(tonumber(spec.performanceH) or 0)
        if need <= 0 then return end
        Section(function()
            local top, height = Block(0, need)
            Add(layout,"performance",inset,top,full,height)
            Gap(5)
        end)
    end
    if spec.noBuild then
        -- The setup view's title and hint are as tall as their wrapped text
        -- measures in this row's width (spec.setupTitleH, spec.setupHintH:
        -- Panel.MeasuredLayout), never under the modelled rows they had (one
        -- large line; two small lines), and the buttons and what follows
        -- move down by what the text needs.
        local top, height = Block(0, math.max(large, math.ceil(Measured(spec.setupTitleH))))
        Add(layout,"setupTitle",inset,top,full,height)
        Gap(5)
        top, height = Block(0, math.max(small * 2, math.ceil(Measured(spec.setupHintH))))
        Add(layout,"setupHint",inset,top,full,height)
        Gap(5)
        local buttonWidth = math.min(146, full)
        top, height = Block(0, math.max(24, normal + 8))
        Add(layout,"setupAssign",(width-buttonWidth)/2,top,buttonWidth,height)
        Gap(5)
        top, height = Block(0, math.max(24, normal + 8))
        Add(layout,"setupCreate",(width-buttonWidth)/2,top,buttonWidth,height)
        Gap(5)
    elseif spec.complete then
        if not spec.statusVisible then
            -- The completion view's badge and sentence, measured the same
            -- way (spec.completeTitleH, spec.completeTextH), never under the
            -- modelled rows they had (one normal line; two small lines).
            local top, height = Block(0, math.max(normal, math.ceil(Measured(spec.completeTitleH))))
            Add(layout,"completeTitle",inset,top,full,height)
            Gap(5)
            top, height = Block(0, math.max(small * 2, math.ceil(Measured(spec.completeTextH))))
            Add(layout,"completeText",inset,top,full,height)
            Gap(5)
        end
        Performance(small * 8 + gap * 5)
    else
        -- The plan progress: one row (22) with its caption at the left, the
        -- Details control at the right and the bar between them, 8 from each,
        -- in the row's middle. The caption is as wide as its own words
        -- (spec.progressLabelW; without a measurement the conservative
        -- model's eight characters) and Details as wide as its own label
        -- needs (spec.planDetailsW: the wider of its two labels with their
        -- room; without one the modelled 12-character button), held to half
        -- the row. Where those leave the bar less than 40 (a long caption or
        -- label), the bar takes a row of its own under them, across the
        -- block. No rule is drawn above the progress.
        -- Both stay whole: a caption wider than the room it then has beside
        -- Details wraps there, and a Details label wider than the control
        -- wraps in it; the caller gives the wrapped caption's height and the
        -- control's (spec.progressLabelH, spec.planDetailsH), the row is as
        -- tall as the taller of them and the control as tall as its label
        -- needs. Neither is shortened or fitted smaller.
        -- Collapsed, that row is the whole progress: the run's count is
        -- hidden with the other four counts until Details is opened. Open,
        -- the count has its own row 3 under it (20, or its measured height:
        -- spec.progressValueH), then the four counts in two rows (18 each, 1
        -- apart, or their measured heights: spec.countRowsH), the Orb run's
        -- numbers while a run is known (spec.orbDetail), then the Echo names
        -- behind the counts: Still needed and Extra copies side by side, and
        -- To lock as a third column beside them while there is one.
        local char = M.ConservativeText(scale)
        local detailsW = math.ceil(12 * char) + 20
        local detailsNeed = math.ceil(Measured(spec.planDetailsW))
        if detailsNeed > 0 then detailsW = detailsNeed end
        detailsW = math.max(1, math.min(detailsW, math.floor(full / 2)))
        local captionW = math.ceil(Measured(spec.progressLabelW))
        if captionW <= 0 then captionW = math.ceil(8 * char * 1.1) end
        local barH = compact.progressBar
        local barW = full - captionW - compact.progressGap * 2 - detailsW
        local detailsNeedH = math.ceil(Measured(spec.planDetailsH))
        local top, rowH = Block(22, math.max(lineSmall, detailsNeedH, math.ceil(Measured(spec.progressLabelH))))
        local detailsH = math.min(rowH, math.max(compact.detailsH, lineSmall, detailsNeedH))
        layout.planDetailsW = detailsW
        Add(layout,"planDetails",width-inset-detailsW,top+math.floor((rowH-detailsH)/2),detailsW,detailsH)
        if barW >= compact.progressBarMin then
            layout.progressInline = true
            Add(layout,"progressHeader",inset,top,math.min(captionW,full),rowH)
            Add(layout,"planBar",inset+captionW+compact.progressGap,top+math.floor((rowH-barH)/2),barW,barH)
        else
            layout.progressInline = false
            Add(layout,"progressHeader",inset,top,math.max(1,full-detailsW-compact.progressGap),rowH)
            Gap(2)
            local barTop = Block(0, barH)
            Add(layout,"planBar",inset,barTop,full,barH)
        end
        -- The open Details stand between the progress row and that row's
        -- own gap: a section, so opening and closing it moves what is under
        -- it by exactly its height.
        if spec.planDetails then
            Section(function()
                Gap(3)
                local valueTop, valueH = Block(20, spec.progressValueH)
                Add(layout,"progressValue",inset,valueTop,full,valueH)
                Gap(3)
                local columnGap = compact.countColumnGap
                local columnWidth = math.floor((full - columnGap) / 2)
                local rightX, rightW = inset+columnWidth+columnGap, full-columnWidth-columnGap
                local counts = type(spec.countRowsH) == "table" and spec.countRowsH or {}
                local firstTop, firstH = Block(18, counts[1])
                Add(layout,"planNeeded",inset,firstTop,columnWidth,firstH)
                Add(layout,"planTomes",rightX,firstTop,rightW,firstH)
                Gap(1)
                local secondTop, secondH = Block(18, counts[2])
                Add(layout,"planExtra",inset,secondTop,columnWidth,secondH)
                Add(layout,"planLocked",rightX,secondTop,rightW,secondH)
                Gap(5)
                -- The Orb run's numbers (used of approved, awaiting a result):
                -- like the other counts, a row of the open Details block only,
                -- across the block, as tall as its wrapped words measure
                -- (spec.orbDetailH). Outside Details the Orb strip has no number.
                if spec.orbDetail then
                    local orbTop, orbH = Block(18, spec.orbDetailH)
                    Add(layout,"planOrb",inset,orbTop,full,orbH)
                    Gap(5)
                end
                -- Each name column: its heading (one line of the secondary
                -- text, 18, unless a heading needs more: below), then its names
                -- right under it, 18 a line.
                -- The columns stand side by side (two, and three with To lock),
                -- so each is a half or a third of the block: a name or a "+N
                -- more" row wider than its column wraps inside it, and the
                -- caller measures every row at its wrapped height in its real
                -- font, width and text (Panel.PanelLayout: spec.detailNamesH for
                -- Still needed and Extra copies, spec.toLockH for To lock), so
                -- no row is cut or held to one line. The design's own three
                -- lines (two names and "+N more") stand while the rows need no
                -- more. The columns are one height: the tallest one's.
                -- The headings share one row over the columns: one line of the
                -- secondary text while every heading fits its column on one
                -- line (as before), and the tallest heading's measured height
                -- when a heading wraps inside its column (spec.listHeadingH:
                -- Panel.MeasureDetailHeadings), so no heading is cut and the
                -- names, and everything after them, start under the whole of
                -- it. layout.detailHeadingTall says the row holds more than
                -- one line; the headings then stand at its top.
                local columns = (tonumber(spec.toLockCount) or 0) > 0 and 3 or 2
                local listGap = compact.listColumnGap
                local listWidth = math.floor((full - listGap * (columns - 1)) / columns)
                local headingNeed = math.ceil(Measured(spec.listHeadingH))
                local listTop, headingH = Block(18, math.max(lineSmall, headingNeed))
                local _, namesH = Block(54, math.max(math.ceil(tonumber(spec.detailNamesH) or 0),
                    columns == 3 and math.ceil(tonumber(spec.toLockH) or 0) or 0))
                layout.detailHeadingH = headingH
                layout.detailHeadingTall = headingNeed > lineSmall
                Add(layout,"needed",inset,listTop,listWidth,headingH + namesH)
                Add(layout,"shed",inset+listWidth+listGap,listTop,listWidth,headingH + namesH)
                if columns == 3 then
                    local thirdX = inset + (listWidth + listGap) * 2
                    Add(layout,"toLock",thirdX,listTop,math.max(1,width-inset-thirdX),headingH + namesH)
                end
            end)
        end
        Gap(5)
        -- No flattened Difficulty / Soul Ash row: the band above holds it.
        Performance(small * 5 + gap * 4)
    end

    if not spec.noBuild then
        -- Your record, then the best known record for the same Echoes: two
        -- entries, never a rank. Only the records that exist are laid out
        -- (spec.recordYours, spec.recordBest): without one, no row, note or
        -- gap is reserved. Each is one entry, a label followed by its value,
        -- given as the measured widths {label, value} (or true: unmeasured,
        -- a whole line). Both entries share one line (18) while they fit
        -- beside each other; otherwise each takes its own line, and an entry
        -- wider than the line puts its value on a second line under its
        -- label. Nothing is shortened. What best known means is on that
        -- entry's hover.
        -- A line of an entry is one whole line of the secondary text
        -- (lineSmall: its measured height when the caller gave one).
        local function Entry(entry)
            if type(entry) ~= "table" then return full, 1 end
            local need = math.ceil((tonumber(entry[1]) or 0) + gap + (tonumber(entry[2]) or 0))
            if need <= full then return need, 1 end
            return full, 2
        end
        local function Row(name, x, entryW, lines)
            local top, height = Block(18 * lines, lineSmall * lines + (lines - 1) * compact.rowGap)
            Add(layout,name,x,top,entryW,height)
            return top, height
        end
        local yours, best = spec.recordYours, spec.recordBest
        layout.recordYours, layout.recordBest = yours, best
        Section(function()
            if yours and best then
                local yoursW, yoursLines = Entry(yours)
                local bestW, bestLines = Entry(best)
                if type(yours) == "table" and type(best) == "table"
                    and yoursLines == 1 and bestLines == 1 and yoursW + gap * 2 + bestW <= full then
                    local top, height = Row("bestDps", inset, yoursW, 1)
                    Add(layout,"bestKnown",inset+yoursW+gap*2,top,bestW,height)
                    Gap(5)
                else
                    Row("bestDps", inset, yoursW, yoursLines)
                    Gap(2)
                    Row("bestKnown", inset, bestW, bestLines)
                    Gap(5)
                end
            elseif yours or best then
                local entryW, lines = Entry(yours or best)
                Row(yours and "bestDps" or "bestKnown", inset, entryW, lines)
                Gap(5)
            end
        end)
    end
    layout.contentBottom = cursor
    -- The footer: three hubs of one width on one line (26, or the height the
    -- caller measured a hub's label to need: spec.footerH), 12 under the
    -- last block (in place of that block's own gap) and 6 above the panel's
    -- lower edge. Every view is as tall as its content: no least height, so
    -- a section that is absent leaves no empty block.
    Gap(12 - closing)
    local footerY, footerHeight = Block(26, spec.footerH)
    Add(layout,"footer",inset,footerY,full,footerHeight)
    Gap(6)
    layout.height = cursor
    return Remember(panelCache,panelOrder,key,layout)
end

local CONTROL_ORDER = {"search","scope","mine","class","qualified","sort"}
local ACTION_ORDER = {"sync","mode","share"}
local CONTROL_BASE = {
    search=165,scope=84,mine=84,class=128,qualified=112,sort=126,
    sync=88,mode=96,share=110,
}
-- The Build Library status region: rows of its composed text (count, the
-- latest Share and the current Sync mode) under the conservative text model,
-- bounded so a very long Share sentence cannot push the list off the window.
-- The bound holds the longest supported composition at the largest supported
-- font scale (2.0, 14 px per character in a 720 px status): an 80-byte Share
-- title in the terminal sentence with its bounded reason, Retry Share, the
-- locked-target sentence and the roles, the count line and the Automatic line
-- need about 17 rows there; 8 rows held only the font scale 1 texts.
local STATUS_MAX_ROWS = 20
-- The window also stays inside the visible UI (M5 queue item 2). The layout
-- (height) is laid out as before: every status row, the controls and the
-- minimum list/detail body. While it fits the UI height less this margin
-- (FitToScreen's), the window shows all of it. Otherwise the window is that
-- tall (windowHeight) and the renderer scrolls the laid-out content inside
-- it (scrollRange), so every control, the whole status and the list/detail
-- can be brought on screen. Nothing is scaled, shortened or hidden. Only the
-- body scrolls: the shared header above scrollTop stays where it is. A UI
-- size under FitToScreen's plausible minimum is not acted on.
local COMMUNITY_VIEWPORT_MARGIN = 24
local COMMUNITY_VIEWPORT_MIN_WIDTH, COMMUNITY_VIEWPORT_MIN_HEIGHT = 640, 480

local function StatusLine(scale)
    return math.max(17, math.ceil(13 * Clamp(scale or 1, 0.75, 2)))
end

-- Community only: visual rows the status text needs at `width`, 1..20.
function M.CommunityStatusRows(text, width, scale)
    local rows = M.TextRows(text, math.max(1, tonumber(width) or 1), scale)
    return math.max(1, math.min(STATUS_MAX_ROWS, rows))
end

-- Community only: the status height that holds `rows` rows at `scale`.
function M.CommunityStatusHeight(rows, scale)
    rows = math.max(1, math.min(STATUS_MAX_ROWS, math.floor(tonumber(rows) or 2)))
    local gap = math.ceil(6 * Clamp(scale or 1, 0.75, 2))
    return math.max(28, rows * StatusLine(scale) + gap)
end

local function LabelKey(labels)
    local out = {}
    for _, name in ipairs(CONTROL_ORDER) do out[#out+1] = KeyText(labels[name]) end
    for _, name in ipairs(ACTION_ORDER) do out[#out+1] = KeyText(labels[name]) end
    return table.concat(out,"|")
end

local function CommunityKey(spec)
    local labels = type(spec.labels) == "table" and spec.labels or {}
    return table.concat({Round(spec.width or 1040,1),
        Round(spec.height or 640,1),Round(spec.fontScale or 1,3),
        Round(spec.uiScale or 1,3),tonumber(spec.revision) or 0,
        LabelKey(labels),"s" .. tostring(tonumber(spec.statusRows) or 0),
        "v" .. tostring(Round(spec.viewportWidth or 0,1)) .. "x"
            .. tostring(Round(spec.viewportHeight or 0,1))},"|")
end

local function ControlWidth(name, label, scale, available)
    local base = CONTROL_BASE[name] or 80
    local estimated = #tostring(label or "") * 6 * scale + 22
    local maximum = name == "search" and 320 or 240
    if name == "qualified" then
        -- A 22 px check box and a gap before its label, sized for the wider
        -- (7 px per character) text model so the fixed label always fits.
        estimated = 26 + #tostring(label or "") * 7 * scale
        maximum = 380
    end
    return math.min(available, math.max(base, math.min(maximum,estimated)))
end

local function Flow(layout, names, labels, startY, scale, available,
        prefix, required)
    local left, right, gap = 20, layout.width - 20, math.ceil(6 * scale)
    local height = math.max(22, math.ceil(14 * scale) + 8)
    local x, y = left, startY
    for _, name in ipairs(names) do
        local width = ControlWidth(name, labels[name], scale, available)
        if x > left and x + width > right then
            x, y = left, y + height + gap
        end
        local boxName = prefix and (prefix .. name) or name
        local box = Add(layout,boxName,x,y,width,height,required)
        if required ~= false then layout.hitboxes[boxName] = box end
        x = x + width + gap
    end
    return y + height
end

function M.Community(spec)
    spec = type(spec) == "table" and spec or {}
    stats.requests = stats.requests + 1
    local key = CommunityKey(spec)
    if communityCache[key] then
        stats.hits = stats.hits + 1
        return communityCache[key]
    end
    stats.computations = stats.computations + 1

    local scale = Clamp(spec.fontScale or 1, 0.75, 2)
    local width = math.max(640,math.floor(tonumber(spec.width) or 1040))
    local requestedHeight = math.max(480,math.floor(tonumber(spec.height) or 640))
    local small, normal = math.ceil(11 * scale), math.ceil(14 * scale)
    local gap = math.ceil(6 * scale)
    local labels = type(spec.labels) == "table" and spec.labels or {}
    local layout = {
        kind="community",width=width,boxes={},required={},hitboxes={},
        scale=scale,key=key,pageSize=20,small=small,normal=normal,gap=gap,
    }
    -- The shared workspace header: the title and the tab row are one row at
    -- the same anchors as Plan's and Records' (M.WorkspaceHeader).
    local header = M.WorkspaceHeader(width)
    local tb, nb = header.boxes.title, header.boxes.tabs
    Add(layout,"title",tb.x,tb.y,tb.w,tb.h)
    Add(layout,"nav",nb.x,nb.y,nb.w,nb.h)
    layout.header = header
    -- The body below the header (every box from here down) is what scrolls;
    -- the header stays on the window. scrollTop is where the body begins.
    layout.scrollTop = header.bottom + gap
    local cursor = header.bottom + gap * 2
    Add(layout,"browseLabel",20,cursor,width-40,small)
    cursor = cursor + small + math.max(3,math.floor(gap/2))
    cursor = Flow(layout,CONTROL_ORDER,labels,cursor,scale,width-40,nil,true)
        + gap
    Add(layout,"actionLabel",20,cursor,width-40,small)
    cursor = cursor + small + math.max(3,math.floor(gap/2))
    cursor = Flow(layout,ACTION_ORDER,labels,cursor,scale,width-40,nil,true)
        + gap
    layout.controlsBottom = cursor

    local metaHeight = math.max(20,normal+6)
    local metaY = cursor
    local resultWidth = math.min(210,math.max(130,math.floor(width*0.24)))
    Add(layout,"result",20,metaY,resultWidth,metaHeight)
    local pageX = 20 + resultWidth + gap
    local prevWidth, pageWidth, nextWidth = 54, 72, 54
    if pageX + prevWidth + pageWidth + nextWidth + gap*2 > width-20 then
        metaY = metaY + metaHeight + gap
        pageX = 20
    end
    local prev = Add(layout,"prev",pageX,metaY,prevWidth,metaHeight)
    layout.hitboxes.prev = prev
    Add(layout,"page",pageX+prevWidth+gap,metaY,pageWidth,metaHeight)
    local nextBox = Add(layout,"next",pageX+prevWidth+gap+pageWidth+gap,
        metaY,nextWidth,metaHeight)
    layout.hitboxes.next = nextBox
    cursor = metaY + metaHeight + gap
    -- The detail keeps its heading, a two-row action footer and at least
    -- three lines of its scrolled body; the list needs less.
    local minimumBody = math.max(150,math.ceil(133 * scale))
    -- Without a measured row count the original two-row reserve stands; with
    -- one, the status holds every measured row (up to STATUS_MAX_ROWS).
    local statusHeight = math.max(28, small * 2 + gap)
    local measuredRows = tonumber(spec.statusRows)
    if measuredRows then
        statusHeight = M.CommunityStatusHeight(measuredRows, scale)
    end
    layout.statusRows = measuredRows or nil
    layout.statusLine = StatusLine(scale)
    Add(layout,"status",20,cursor,width-40,statusHeight)
    cursor = cursor + statusHeight + gap

    local bodyTop = cursor
    local height = math.max(requestedHeight, bodyTop + minimumBody + 20)
    local bodyHeight = height - bodyTop - 20
    local bodyGap = math.max(16,math.ceil(20 * scale))
    local bodyWidth = width - 40
    local listWidth = math.floor((bodyWidth-bodyGap)*0.48)
    listWidth = math.max(290,math.min(480,listWidth))
    local detailWidth = bodyWidth - bodyGap - listWidth
    if detailWidth < 290 then
        listWidth = math.max(260,listWidth-(290-detailWidth))
        detailWidth = bodyWidth-bodyGap-listWidth
    end
    Add(layout,"list",20,bodyTop,listWidth,bodyHeight)
    Add(layout,"detail",20+listWidth+bodyGap,bodyTop,detailWidth,bodyHeight)
    Add(layout,"emptyState",30,bodyTop+gap,listWidth-20,
        math.min(bodyHeight-gap*2,small*5),false)
    layout.height = height
    -- The window shown on screen (see COMMUNITY_VIEWPORT_MARGIN): the whole
    -- layout while it fits the UI height less the margin, otherwise that
    -- height, with the rest reached by scrolling. viewportFit says whether
    -- the window, with its margin, lies inside the UI size; it is nil when
    -- no plausible UI size was given (the window then shows the layout).
    layout.windowHeight, layout.scrollRange = height, 0
    local viewportWidth = tonumber(spec.viewportWidth)
    local viewportHeight = tonumber(spec.viewportHeight)
    if viewportWidth and viewportHeight
        and viewportWidth >= COMMUNITY_VIEWPORT_MIN_WIDTH
        and viewportHeight >= COMMUNITY_VIEWPORT_MIN_HEIGHT then
        local windowHeight = math.min(height,
            math.floor(viewportHeight - COMMUNITY_VIEWPORT_MARGIN))
        layout.windowHeight = windowHeight
        layout.scrollRange = height - windowHeight
        layout.viewportWidth, layout.viewportHeight = viewportWidth, viewportHeight
        layout.viewportMargin = COMMUNITY_VIEWPORT_MARGIN
        layout.viewportFit = windowHeight <= viewportHeight - COMMUNITY_VIEWPORT_MARGIN
            and width <= viewportWidth - COMMUNITY_VIEWPORT_MARGIN
    end
    layout.cardPoolLimit = math.max(1,math.min(19,
        math.ceil(bodyHeight / 92) + 4))
    local cardWidth = math.max(220,listWidth-20)
    local contentWidth = math.max(120,cardWidth-68)
    local dpsWidth = math.max(92,math.floor(contentWidth*0.38))
    local cardGap = gap
    local titleWidth = math.max(20,contentWidth-dpsWidth-cardGap)
    layout.card = {
        width=cardWidth,contentWidth=contentWidth,titleWidth=titleWidth,
        dpsWidth=dpsWidth,gap=cardGap,
        iconCapacity=math.max(1,math.min(12,
            math.floor(math.max(28,cardWidth-88)/28))),
    }
    return Remember(communityCache,communityOrder,key,layout)
end

-- The header Plan, Explore and Records share (FullUIWorkspaces.ApplyHeader):
-- the three workspace tabs, Plan / Explore / Records, then Help, in one row
-- from the window's top-left; the title after Help; Reference at the top
-- right, left of the close button. Every place is measured from the top-left
-- corner (Reference from the top-right), never centred in the window, so the
-- tabs and the title keep one place in each workspace at any window width,
-- and the window's top-left is what navigation carries across. The buttons
-- keep their template height; a title longer than its room stays one line.
M.WORKSPACE_WIDTH = 1040
local WORKSPACE_TABS = {"plan","builds","records"}
function M.WorkspaceHeader(width)
    width = math.max(640, math.floor(tonumber(width) or M.WORKSPACE_WIDTH))
    local top, left, height, gap, tabW, helpW, referenceW = 12, 18, 22, 4, 96, 56, 84
    local boxes, x = {}, left
    for _, key in ipairs(WORKSPACE_TABS) do
        boxes[key] = Box(x, top, tabW, height)
        x = x + tabW + gap
    end
    boxes.help = Box(x, top, helpW, height)
    x = x + helpW
    boxes.tabs = Box(left, top, x - left, height)
    boxes.reference = Box(width - 40 - referenceW, top, referenceW, height)
    local titleX = x + 16
    boxes.title = Box(titleX, top + 2, math.max(1, boxes.reference.x - 12 - titleX), 18)
    return {width=width,top=top,bottom=top + height,order=WORKSPACE_TABS,boxes=boxes}
end

function M.ResetCache()
    panelCache,communityCache,panelOrder,communityOrder = {},{},{},{}
end

function M.Stats()
    return {requests=stats.requests,computations=stats.computations,
        hits=stats.hits,evictions=stats.evictions,
        maxCacheEntries=MAX_CACHE_ENTRIES,fontBuilds=stats.fontBuilds,
        fontApplications=stats.fontApplications,
        runtimeRevision=runtimeRevision,panelEntries=#panelOrder,
        communityEntries=#communityOrder}
end

Nexus.LayoutMetrics = M
