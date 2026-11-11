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
        spec.performanceH == nil and "m" or math.ceil(tonumber(spec.performanceH) or 0),
        math.ceil(tonumber(spec.progressLabelW) or 0),math.ceil(tonumber(spec.progressValueH) or 0),
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
    }, "|")
end

-- The three offer rows of the roll box, in one place for the box's height
-- (M.Panel) and their placement (Panel.PlaceOfferCards), from the panel's
-- small text line and section gap. A row is one small text line with a row
-- gap above and below it (room for a legible icon and for the text to
-- breathe); rows are a row gap apart, and the band keeps two row gaps under
-- the heading line and above the text below. Returns, from the roll box's
-- top: the first row's top, a row's height, the gap between rows and where
-- the text under the rows starts. At font scale 1 (small 11, gap 6):
-- 16, 15, 2 and 69.
function M.OfferRows(small, gap)
    local rowGap = math.max(2, math.floor(gap / 3))
    local rowH = small + 2 * rowGap
    local top = 1 + small + 2 * rowGap
    return top, rowH, rowGap, top + 3 * rowH + 4 * rowGap
end

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
    local width = math.max(240, math.floor(tonumber(spec.width) or 272))
    local small = math.ceil(11 * scale)
    local normal = math.ceil(14 * scale)
    local large = math.ceil(16 * scale)
    local gap = math.ceil(6 * scale)
    local layout = {
        kind="panel",width=width,boxes={},required={},scale=scale,
        key=key,small=small,normal=normal,large=large,gap=gap,
    }
    -- The charges cell of the offer heading row. 72 px holds the compact row
    -- at the 10 px small size, so the cell follows the font scale and is
    -- never narrower than that; chargesGap separates it from the heading.
    -- The heading forms are fitted beside the 72 px minimum, and the cell is
    -- given its width only in the room the shown heading then leaves
    -- (Panel.SetOfferHeading, Panel.ChargesCell).
    layout.chargesMinW, layout.chargesGap = 72, 4
    layout.chargesW = math.max(72, math.floor(72 * scale + 0.5))
    local cursor = 6
    -- The Build and Wishlist lines keep a row of the normal font (at least
    -- 20 units) while their text fits it; a name too long for its line wraps
    -- beside its button and the header grows by the measured height of each
    -- wrapped line (spec.headerBuildH, spec.headerWishlistH). Nothing is
    -- shortened.
    -- The approved compact header: line 1 (the 24-unit grip and the three
    -- controls) ends 26 units under the header's top; the Build row follows
    -- at 32, the Wishlist row 2 units under it, and 4 units close the header
    -- (72 units at font scale 1, where it was 82).
    -- The title on line 1 keeps a 20-unit row while its text needs no more.
    -- A title that needs more (a state cue that wraps in the title's slot,
    -- or one line of a larger font) takes its measured height
    -- (spec.headerTitleH), and line 1 grows by the difference: the Build and
    -- Wishlist rows and the header's end move down by exactly that. The grip
    -- and the three controls stay at the top of line 1.
    local headerLine = math.max(20, normal)
    local titleH = math.max(20, math.ceil(tonumber(spec.headerTitleH) or 0))
    local titleExtra = titleH - 20
    local buildH = math.max(headerLine, math.ceil(tonumber(spec.headerBuildH) or 0))
    local wishlistH = math.max(headerLine, math.ceil(tonumber(spec.headerWishlistH) or 0))
    layout.headerLine, layout.headerBuildH, layout.headerWishlistH = headerLine, buildH, wishlistH
    layout.headerTitleH = titleH
    layout.headerBuildY = cursor + 26 + titleExtra
    layout.headerWishlistY = layout.headerBuildY + buildH + 2
    local headerHeight = 26 + titleExtra + buildH + 2 + wishlistH + 4
    -- Every block of the body keeps one compact side inset: 8 units, where it
    -- was 10. The approved preview draws 6; 8 keeps the body on the line of
    -- the header's grip, whose slot (x 8) is unchanged.
    local inset = 8
    local full = width - inset * 2
    layout.inset, layout.full = inset, full
    Add(layout,"header",inset,cursor,full,headerHeight)
    cursor = cursor + headerHeight + gap

    -- The Play panel of a build in progress (design/current "Nexus Main Panel
    -- - Compact Redesign"): below the Build / Wishlist header, the original
    -- difficulty card (the pre-overhaul b0870929 worldStatusBox, 56 px for an
    -- active build), then the current offer, a compact plan progress, the DPS
    -- rows and the Orb run line. The same card heads the setup and completed
    -- views. It is never flattened into a text row.
    local play = not spec.noBuild and not spec.complete
    layout.play = play
    if spec.statusVisible then
        -- The Compact A card (approved cleanup; the original card was 56 px
        -- active and 66 completed): a 5-unit inset, the tier line (15 units
        -- of primary text, or the measured height of a wrapped tier:
        -- spec.statusTierH), the Soul Ash line (14), then 3 units and the
        -- 6-unit Intensity bar, and a 5-unit inset: 48 units with short text
        -- at font scale 1, active or completed. Without a validated
        -- Intensity scale (spec.statusBar false) no room is kept for the bar.
        local tierH = math.max(math.ceil(15 * scale), math.ceil(tonumber(spec.statusTierH) or 0))
        local ashH = math.ceil(14 * scale)
        local barH = spec.statusBar ~= false and 6 or 0
        local height = 5 + tierH + ashH + (barH > 0 and (3 + barH) or 0) + 5
        layout.statusInset, layout.statusTierH, layout.statusAshH, layout.statusBarH = 5, tierH, ashH, barH
        Add(layout,"status",inset,cursor,full,height)
        cursor = cursor + height + gap
    end
    if spec.callboard then
        -- The approved inline Callboard: its icon and its label share the
        -- objective title's first line (the label's measured width:
        -- spec.callboardLabelW), and the objective lines follow under the
        -- title. Each row is at least one 17px line, including the
        -- conservative face at font scale 1. A title or objective lines
        -- longer than one row wrap, and the box grows by their measured
        -- heights (spec.callboardTitleH, spec.callboardDetailH): nothing is
        -- shortened or cut to one line.
        local char, lineH = M.ConservativeText(scale)
        if lineH < 17 then lineH = 17 end
        layout.callboardLine = lineH
        local titleH = math.max(lineH, math.ceil(tonumber(spec.callboardTitleH) or 0))
        local detailH = math.max(lineH, math.ceil(tonumber(spec.callboardDetailH) or 0))
        layout.callboardTitleH, layout.callboardDetailH = titleH, detailH
        layout.callboardIcon = 16
        layout.callboardLabelW = math.ceil(tonumber(spec.callboardLabelW) or (9 * char * 1.1))
        local callboardH = titleH + detailH
        Add(layout,"callboard",inset,cursor,full,callboardH)
        cursor = cursor + callboardH + gap
    end
    if spec.activeRoll and spec.noOffer then
        -- Level 80, normal rolls finished, no offer (the design's collapsed
        -- state): no 104 px offer minimum and no separate button row. One
        -- guidance block of the conservative model's rows (the caller counts
        -- them at the width left of the button) with the passive Open
        -- Orbs... button inline at its right.
        -- The block is exactly as tall as its guidance (or the button), with
        -- no inner padding, and the gaps above and below it are at most 8 px
        -- at any font scale (design/current Lv80: no empty band where the
        -- offers were). Every earlier section ended with one `gap`.
        local char, line = M.ConservativeText(scale)
        local rows = math.max(1, tonumber(spec.guidanceRows) or 1)
        local tight = math.min(gap, 8)
        layout.noOffer = true
        layout.noOfferGap = tight
        if spec.orbButton then
            layout.orbButtonH = math.max(small + 6, line)
            layout.orbButtonW = math.min(full, math.ceil(12 * char) + 20)
        end
        cursor = cursor - gap + tight
        local height = math.max(rows * line, layout.orbButtonH or 0)
        Add(layout,"roll",inset,cursor,full,height)
        cursor = cursor + height + tight
    elseif spec.activeRoll then
        local rowGap = math.max(2,math.floor(gap/3))
        -- The heading row: one small line, or the measured height of a
        -- heading or charges text that wraps beside the other
        -- (spec.headingH). Everything under it moves down by the difference.
        local headH = math.max(small, math.ceil(tonumber(spec.headingH) or 0))
        local headExtra = headH - small
        layout.headingH, layout.headingExtra = headH, headExtra
        -- The control of the Auto scope line shares the heading row while
        -- the caller found room for it there (spec.autoInfoInline, at its
        -- measured width spec.autoInfoW); it then takes no row of its own.
        layout.autoInfoInline = spec.autoInfo and spec.autoInfoInline and true or false
        local height = math.max(104, small * 6 + gap * 4) + headExtra
        -- Where the text under the heading starts: under the offer rows
        -- while there are any (M.OfferRows), else right under the heading.
        local bodyTop = 1 + headH + math.max(3,math.floor(gap/2))
        if spec.cardRows then
            -- That least height was sized for three one-line rows (to
            -- test.163021: 3 x (small + row gap) under the heading). The
            -- rows are taller now, and the box grows by exactly what they
            -- gained (15 px at font scale 1), so the text under them keeps
            -- the room it had.
            local oneLineRows = bodyTop + 3 * (small + rowGap)
            bodyTop = select(4, M.OfferRows(small, gap)) + headExtra
            height = height + bodyTop - oneLineRows
        end
        -- Measured content (approved cleanup: full offer names, tags and the
        -- full recommendation, wrapped, with no line cap). spec.offerRowsH
        -- gives each offer row's measured height: a wrapped name or tag, or
        -- the selected offer's reason inside its row (spec.offerReason:
        -- {row, top}, the reason starting `top` under the row's top), makes
        -- that row taller than the model row, and the box grows by exactly
        -- that.
        if spec.cardRows and type(spec.offerRowsH) == "table" then
            local _, rowH = M.OfferRows(small, gap)
            local extra = 0
            for index = 1, 3 do
                extra = extra + math.max(0, math.ceil(tonumber(spec.offerRowsH[index]) or 0) - rowH)
            end
            layout.offerRowsH, layout.offerRowsExtra = spec.offerRowsH, extra
            layout.offerReason = type(spec.offerReason) == "table" and spec.offerReason or nil
            bodyTop = bodyTop + extra
            height = height + extra
        end
        layout.bodyTop = bodyTop
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
            local available = full - 4 - layout.orbButtonW - layout.orbMiniButtonGap
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
            height = height + layout.orbButtonH + math.ceil(gap/2)
        end
        local rows = tonumber(spec.guidanceRows) or 0
        if rows > 0 then
            -- Readable allocation for the Orb guidance body: every row of the
            -- conservative text model below the heading (and the card rows,
            -- if any), above the button row. Never smaller than before.
            local _, line = M.ConservativeText(scale)
            local needed = bodyTop + rows * line + gap
            if spec.orbButton then needed = needed + layout.orbButtonH + math.ceil(gap/2) end
            height = math.max(height, needed)
        end
        -- spec.bodyH: the measured height of the text under the heading (or
        -- under the offer rows) at its width; the box is never shorter than
        -- the whole text needs, above the button row.
        local bodyH = math.ceil(tonumber(spec.bodyH) or 0)
        layout.bodyH = bodyH
        if spec.measured then
            -- With measured content (the panel's own second computation) the
            -- box is exactly its content: the heading, the offer rows, the
            -- text under them when there is any, and the button row. No
            -- least height or empty text room is kept (approved cleanup:
            -- conditional content, no fixed empty block). A block reserved
            -- through a gap between boards keeps the height it had
            -- (spec.reservedRollH), so the panel does not jump.
            if bodyH > 0 then
                -- spec.bodyFloorH: the rows of the conservative text model
                -- for a text that must stay readable in a face wider than
                -- the measured one (the Orb guidance, an Orb pause reason,
                -- the inline Auto line). The box is never shorter than that
                -- while nothing else holds the block's height. In a block
                -- kept through a gap between boards the text takes the room
                -- that block already has, up to the floor, and the block
                -- itself grows only for the measured text: the footprint of
                -- an Auto cycle stays the board's.
                local floorH = math.ceil(tonumber(spec.bodyFloorH) or 0)
                if floorH > bodyH then
                    local reserved = math.ceil(tonumber(spec.reservedRollH) or 0)
                    if reserved > 0 then
                        local used = bodyTop + bodyH + rowGap
                            + (spec.orbButton and (layout.orbButtonH + math.ceil(gap/2)) or 0)
                        bodyH = bodyH + math.max(0, math.min(floorH - bodyH, reserved - used))
                    else
                        bodyH = floorH
                    end
                    layout.bodyH = bodyH
                end
                height = bodyTop + bodyH + rowGap
            elseif spec.cardRows then
                height = bodyTop - rowGap
            else
                height = 1 + headH + rowGap
            end
            if spec.orbButton then height = height + layout.orbButtonH + math.ceil(gap/2) end
            height = math.max(height, math.ceil(tonumber(spec.reservedRollH) or 0))
        elseif bodyH > 0 then
            local needed = bodyTop + bodyH + gap
            if spec.orbButton then needed = needed + layout.orbButtonH + math.ceil(gap/2) end
            height = math.max(height, needed)
        end
        Add(layout,"roll",inset,cursor,full,height)
        cursor = cursor + height + gap
        -- The Auto scope line under the offer (the design's Auto ON note) is
        -- behind an optional control (spec.autoInfo). While the control
        -- shares the heading row it has no box; at a text size where it does
        -- not fit there it takes one short row of its own under the offer.
        -- The line's own rows are laid out only while it is open (the caller
        -- then gives autoScopeRows, counted at the block's width).
        if spec.autoInfo then
            local char, line = M.ConservativeText(scale)
            layout.autoInfoW = math.min(full, math.ceil(tonumber(spec.autoInfoW) or (math.ceil(16 * char) + 20)))
            if layout.autoInfoInline then
                -- What the heading row keeps free at its right for it.
                layout.headingReserve = layout.autoInfoW + 4
            else
                local infoH = math.max(small + 6, line)
                Add(layout,"autoInfo",inset,cursor,layout.autoInfoW,infoH)
                cursor = cursor + infoH + gap
            end
        end
        local scopeRows = tonumber(spec.autoScopeRows) or 0
        if scopeRows > 0 then
            local _, line = M.ConservativeText(scale)
            Add(layout,"autoScope",inset,cursor,full,scopeRows * line)
            cursor = cursor + scopeRows * line + gap
        end
    end
    if spec.orbLine and not spec.noBuild then
        -- The Orb run status with Open, right under the offer (the approved
        -- order); the Orb window owns the run's controls. Its text wraps
        -- beside the button in its measured height (spec.orbLineH).
        local char, line = M.ConservativeText(scale)
        local buttonH = math.max(small + 6, line)
        local h = math.max(buttonH, math.ceil(tonumber(spec.orbLineH) or 0))
        local openW = math.min(full, math.ceil(6 * char) + 20)
        layout.orbLineOpenW = openW
        Add(layout,"orbLine",inset,cursor,full-openW-gap,h)
        Add(layout,"orbLineOpen",width-inset-openW,cursor,openW,buttonH)
        cursor = cursor + h + gap
    end
    layout.contentTop = cursor

    -- The opt-in DPS RECORDS section (spec.showPerformance). Its height is
    -- the measured height of the rows that exist (spec.performanceH): only
    -- records that exist have a row, and without any there is no section,
    -- heading or reserved block (0). A caller that measured nothing (nil)
    -- gets the former modelled block.
    local function Performance(modelled)
        if not spec.showPerformance then return end
        local height = spec.performanceH == nil and modelled or math.ceil(tonumber(spec.performanceH) or 0)
        if height <= 0 then return end
        Add(layout,"performance",inset,cursor,full,height)
        cursor = cursor + height + gap
    end
    if spec.noBuild then
        Add(layout,"setupTitle",inset,cursor,full,large)
        cursor = cursor + large + gap
        Add(layout,"setupHint",inset,cursor,full,small * 2)
        cursor = cursor + small * 2 + gap
        local buttonHeight = math.max(24, normal + 8)
        Add(layout,"setupAssign",(width-146)/2,cursor,146,buttonHeight)
        cursor = cursor + buttonHeight + gap
        Add(layout,"setupCreate",(width-146)/2,cursor,146,buttonHeight)
        cursor = cursor + buttonHeight + gap
    elseif spec.complete then
        if not spec.statusVisible then
            Add(layout,"completeTitle",inset,cursor,full,normal)
            cursor = cursor + normal + gap
            Add(layout,"completeText",inset,cursor,full,small * 2)
            cursor = cursor + small * 2 + gap
        end
        Performance(small * 8 + gap * 5)
    else
        -- Compact plan progress: one heading row (the heading and Show /
        -- Hide details), the run's count with its whole unit on its own
        -- full-width row (the design's heading row wraps) and a bar. The
        -- detail section below the bar (two rows of two counts: Still needed,
        -- Missing tomes, Extra copies, Locked targets; then the Echo names
        -- behind them: the Still needed, Extra copies and To lock lists) is
        -- laid out only while details are shown (native QA test.163008):
        -- Hide details gives back its whole height.
        -- Approved cleanup: collapsed, the progress is one row: the heading
        -- (its measured width, spec.progressLabelW), the bar and Show
        -- details. The run's count is hidden with the other four counts
        -- until Details is opened and takes no row while it is. When the
        -- heading and the button leave the bar too little room (large or
        -- long text), the bar takes a row of its own under them. With
        -- Details open the count has its own full-width row (its measured
        -- height, spec.progressValueH), then the four counts in two rows
        -- (their measured heights, spec.countRowsH), then the names.
        local rowGap = math.max(2,math.floor(gap/3))
        local char = M.ConservativeText(scale)
        local detailsW = math.min(full, math.ceil(12 * char) + 20)
        local rowH = math.max(normal, small + 6)
        local barH = math.max(5, math.ceil(small / 2))
        local labelW = math.ceil(tonumber(spec.progressLabelW) or (8 * char * 1.1))
        local barW = full - labelW - detailsW - gap * 2
        layout.planDetailsW = detailsW
        if barW >= 48 then
            Add(layout,"progressHeader",inset,cursor,labelW,rowH)
            Add(layout,"planBar",inset+labelW+gap,cursor+math.floor((rowH-barH)/2),barW,barH)
            Add(layout,"planDetails",width-inset-detailsW,cursor,detailsW,rowH)
            cursor = cursor + rowH
        else
            Add(layout,"progressHeader",inset,cursor,math.max(1,full-detailsW-gap),rowH)
            Add(layout,"planDetails",width-inset-detailsW,cursor,detailsW,rowH)
            cursor = cursor + rowH + rowGap
            Add(layout,"planBar",inset,cursor,full,barH)
            cursor = cursor + barH
        end
        if not spec.planDetails then
            cursor = cursor + gap
        else
            cursor = cursor + rowGap + 1
            local valueH = math.max(normal, math.ceil(tonumber(spec.progressValueH) or 0))
            Add(layout,"progressValue",inset,cursor,full,valueH)
            cursor = cursor + valueH + rowGap
            local columnGap = 12
            local columnWidth = math.floor((full - columnGap) / 2)
            local rightX, rightW = inset+columnWidth+columnGap, full-columnWidth-columnGap
            local counts = type(spec.countRowsH) == "table" and spec.countRowsH or {}
            local firstH = math.max(small, math.ceil(tonumber(counts[1]) or 0))
            local secondH = math.max(small, math.ceil(tonumber(counts[2]) or 0))
            Add(layout,"planNeeded",inset,cursor,columnWidth,firstH)
            Add(layout,"planTomes",rightX,cursor,rightW,firstH)
            cursor = cursor + firstH + rowGap
            Add(layout,"planExtra",inset,cursor,columnWidth,secondH)
            Add(layout,"planLocked",rightX,cursor,rightW,secondH)
            cursor = cursor + secondH + gap
            -- The Orb run's numbers (used of approved, awaiting a result):
            -- like the other counts, a row of the open Details block only,
            -- across the block, as tall as its wrapped words measure
            -- (spec.orbDetailH). Outside Details the Orb strip has no number.
            if spec.orbDetail then
                local orbH = math.max(small, math.ceil(tonumber(spec.orbDetailH) or 0))
                Add(layout,"planOrb",inset,cursor,full,orbH)
                cursor = cursor + orbH + gap
            end
            -- Each name column: its heading, a gap, then its three one-line
            -- name rows (two names and "+N more"), modelled at the small
            -- row; when the client measured those rows taller in their real
            -- font, width and text (Panel.PanelLayout, spec.detailNamesH),
            -- that measured stack instead, so the last row is never cut.
            local namesH = math.max(small * 3, math.ceil(tonumber(spec.detailNamesH) or 0))
            local columnHeight = small + math.max(3,math.floor(gap/2)) + namesH
            Add(layout,"needed",inset,cursor,columnWidth,columnHeight)
            Add(layout,"shed",rightX,cursor,rightW,columnHeight)
            cursor = cursor + columnHeight + gap
            if (tonumber(spec.toLockCount) or 0) > 0 then
                local height = small * 3 + math.max(3,math.floor(gap/2))
                Add(layout,"toLock",inset,cursor,full,height)
                cursor = cursor + height + gap
            end
        end
        -- No flattened Difficulty / Soul Ash row: the card above holds it.
        Performance(small * 5 + gap * 4)
    end

    if not spec.noBuild then
        -- Your record, then the best known record for the same Echoes, then
        -- what best known means: two rows and their note, never a rank.
        -- Only the records that exist are laid out (spec.recordYours,
        -- spec.recordBest): without one, no row, note or gap is reserved.
        -- Each is one entry, a label followed by its value, given as the
        -- measured widths {label, value} (or true: unmeasured, a whole
        -- line). Both entries share one line while they fit beside each
        -- other; otherwise each takes its own line, and an entry wider than
        -- the line puts its value on a second line under its label. Nothing
        -- is shortened. What best known means is on that entry's hover.
        local rowGap = math.max(2,math.floor(gap/3))
        local function Entry(entry)
            if type(entry) ~= "table" then return full, small end
            local need = math.ceil((tonumber(entry[1]) or 0) + gap + (tonumber(entry[2]) or 0))
            if need <= full then return need, small end
            return full, small * 2 + rowGap
        end
        local yours, best = spec.recordYours, spec.recordBest
        layout.recordYours, layout.recordBest = yours, best
        if yours and best then
            local yoursW, yoursH = Entry(yours)
            local bestW, bestH = Entry(best)
            if type(yours) == "table" and type(best) == "table"
                and yoursH == small and bestH == small and yoursW + gap * 2 + bestW <= full then
                Add(layout,"bestDps",inset,cursor,yoursW,small)
                Add(layout,"bestKnown",inset+yoursW+gap*2,cursor,bestW,small)
                cursor = cursor + small + gap
            else
                Add(layout,"bestDps",inset,cursor,yoursW,yoursH)
                cursor = cursor + yoursH + rowGap
                Add(layout,"bestKnown",inset,cursor,bestW,bestH)
                cursor = cursor + bestH + gap
            end
        elseif yours or best then
            local entryW, entryH = Entry(yours or best)
            Add(layout,yours and "bestDps" or "bestKnown",inset,cursor,entryW,entryH)
            cursor = cursor + entryH + gap
        end
    end
    layout.contentBottom = cursor
    -- The footer hubs are two lines each: the hub's name and, under it, what
    -- it opens; the row is as tall as the tallest hub needs (its measured
    -- height, spec.footerH). A caller that measured nothing gets the former
    -- one-line row.
    local footerHeight = math.max(22, normal + 7, math.ceil(tonumber(spec.footerH) or 0))
    -- Every view is as tall as its content: no minimum from the former fixed
    -- columns, so a section that is absent leaves no empty block. That
    -- includes the setup view (no Wishlist): with an Echo board open its
    -- former least height left an empty band above the footer once the
    -- header, the card and the measured offer block became compact.
    -- Every section above ended with one gap: the footer follows it, and the
    -- panel's own 6-unit inset closes it.
    local footerY = cursor
    Add(layout,"footer",inset,footerY,full,footerHeight)
    layout.height = footerY + footerHeight + 6
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
