-- Nexus UI appearance. Two separate, presentation-only choices:
--   style (structure): how windows and buttons are drawn;
--   colour (palette):  the accent colours that style draws with.
-- Nexus Slate is the shared dark style of test.9094, with the same literals
-- and its own Nexus Graphite colours. The Orb run, history, copy and Continue
-- windows, which test.9094 drew with stock buttons and a flat backdrop, now
-- use the shared style in every choice. Nexus Vista with Nexus Amethyst purple is the default for a
-- player who never chose. A choice is read through Store.Settings() and
-- written only when the player picks one, through the Store settings owner;
-- reading never rewrites a missing, unknown or future saved value. Styling
-- keeps native-looking controls without the bright red UIPanelButton artwork
-- of the stock 3.3.5 templates, never touches gameplay, and never paints a
-- tree marked exempt (the replacement difficulty / Soul Ash card).
Nexus = Nexus or {}
Nexus.Theme = Nexus.Theme or {}
local T = Nexus.Theme
local stats = {
    treeWalks=0, skippedTrees=0, nodesVisited=0,
    buttonsStyled=0, virtualRows=0, hooks=0, textures=0,
    windowsStyled=0, exemptTrees=0, resolves=0, reapplies=0,
    reappliedControls=0, preferenceChanges=0, windowBases=0, tooltipBases=0,
    menuFills=0,
}

-- Full-UI localization (issues #143-#148): the shown style and colour names,
-- hue words, menu rows, outcome notices and HELP resolve through
-- Nexus.Localization at call time; while the seam is absent or a key answers
-- "unavailable" the exact English below is shown. Style and palette ids, the
-- saved values and the STYLES/PALETTES label fields stay raw (data and the
-- names tests and callers compare); only the shown copy is translated.
local function Say(key, english)
    local localization = Nexus.Localization
    if type(localization) == "table" and type(localization.Text) == "function" then
        local text, source = localization.Text(key)
        if type(text) == "string" and source ~= "unavailable" then return text end
    end
    return english
end
local function SayF(key, args, english)
    local localization = Nexus.Localization
    if type(localization) == "table" and type(localization.Format) == "function" then
        local text, source = localization.Format(key, args)
        if type(text) == "string" and source ~= "unavailable" then return text end
    end
    return english
end

local WHITE = "Interface\\Buttons\\WHITE8X8"
local EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
T.STYLE_KEY, T.PALETTE_KEY = "uiStyle", "uiPalette"
T.DEFAULT_STYLE = "vista"

-- Text colours belong to the style, so a colour choice never lowers text
-- contrast; a palette only moves borders, hover, glow and selection accents.
local STYLES = {
    vista = {
        id="vista", order=1, label="Nexus Vista", palette="amethyst",
        summary="Default. A deep, quiet backdrop with Nexus Amethyst purple accents and glow.",
        windowBackdrop={bgFile=WHITE, edgeFile=EDGE, tile=false, edgeSize=12,
            insets={left=3, right=3, top=3, bottom=3}},
        windowColor={0.030, 0.034, 0.046}, baseColor={0.030, 0.034, 0.046},
        shadeBottom={0, 0, 0, 0.30}, glowAlpha=0.14, accentAlpha=0.75,
        buttonBg={0.032, 0.038, 0.054, 0.96}, pressedBg={0.016, 0.020, 0.030, 1},
        text={0.94, 0.92, 0.86}, disabledText={0.52, 0.54, 0.57}, hoverAlpha=0.40,
    },
    slate = {
        id="slate", order=2, label="Nexus Slate", palette="graphite",
        summary="The earlier shared dark style of the imported 1.19.3 source and test.9094, with the same "
            .. "colours and shapes. The Orb windows, plain in test.9094, now use it too.",
        windowBackdrop={bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile=EDGE, tile=true, tileSize=32, edgeSize=12,
            insets={left=4, right=4, top=4, bottom=4}},
        windowColor={0.16, 0.165, 0.175}, baseColor={0.055, 0.057, 0.062},
        shade={0.10, 0.105, 0.115, 0.05},
        buttonBg={0.025, 0.03, 0.04, 0.96}, pressedBg={0.015, 0.02, 0.025, 1},
        text={0.92, 0.84, 0.62}, disabledText={0.48, 0.50, 0.52}, hoverAlpha=0.38,
    },
}
-- Nexus Graphite is exactly the test.9094 accent set.
local PALETTES = {
    sapphire={id="sapphire", order=1, label="Nexus Sapphire", hue="blue",
        border={0.26, 0.44, 0.70}, windowBorder={0.22, 0.36, 0.58},
        hover={0.14, 0.30, 0.52}, accent={0.40, 0.64, 0.98}},
    emerald={id="emerald", order=2, label="Nexus Emerald", hue="green",
        border={0.22, 0.56, 0.42}, windowBorder={0.18, 0.44, 0.34},
        hover={0.12, 0.38, 0.27}, accent={0.32, 0.82, 0.58}},
    amethyst={id="amethyst", order=3, label="Nexus Amethyst", hue="purple",
        border={0.50, 0.36, 0.72}, windowBorder={0.40, 0.29, 0.58},
        hover={0.32, 0.20, 0.50}, accent={0.72, 0.54, 0.98}},
    ember={id="ember", order=4, label="Nexus Ember", hue="orange",
        border={0.78, 0.46, 0.20}, windowBorder={0.60, 0.36, 0.17},
        hover={0.52, 0.28, 0.10}, accent={1.00, 0.62, 0.28}},
    auric={id="auric", order=5, label="Nexus Auric", hue="gold",
        border={0.74, 0.62, 0.30}, windowBorder={0.58, 0.48, 0.24},
        hover={0.46, 0.38, 0.14}, accent={0.98, 0.82, 0.40}},
    graphite={id="graphite", order=6, label="Nexus Graphite", hue="gray",
        border={0.25, 0.29, 0.34}, windowBorder={0.20, 0.23, 0.28},
        hover={0.16, 0.24, 0.29}, accent={0.62, 0.68, 0.76},
        disabledBorder={0.13, 0.15, 0.18}},
}
T.STYLES, T.PALETTES = STYLES, PALETTES

-- Shown names by id (label key, then summary or hue key). Display only.
local STYLE_KEYS = {
    vista = {"theme.label.style_vista", "theme.tooltip.style_vista"},
    slate = {"theme.label.style_slate", "theme.tooltip.style_slate"},
}
local PALETTE_KEYS = {
    sapphire = {"theme.label.palette_sapphire", "theme.value.hue_blue"},
    emerald = {"theme.label.palette_emerald", "theme.value.hue_green"},
    amethyst = {"theme.label.palette_amethyst", "theme.value.hue_purple"},
    ember = {"theme.label.palette_ember", "theme.value.hue_orange"},
    auric = {"theme.label.palette_auric", "theme.value.hue_gold"},
    graphite = {"theme.label.palette_graphite", "theme.value.hue_gray"},
}
local function StyleLabel(style)
    local keys = STYLE_KEYS[style.id]
    return keys and Say(keys[1], style.label) or style.label
end
local function StyleSummary(style)
    local keys = STYLE_KEYS[style.id]
    return keys and Say(keys[2], style.summary) or style.summary
end
local function PaletteLabel(palette)
    local keys = PALETTE_KEYS[palette.id]
    return keys and Say(keys[1], palette.label) or palette.label
end
local function PaletteHue(palette)
    local keys = PALETTE_KEYS[palette.id]
    return keys and Say(keys[2], palette.hue) or palette.hue
end

local BUTTON_BACKDROP = {bgFile=WHITE, edgeFile=EDGE, tile=false, edgeSize=10,
    insets={left=2, right=2, top=2, bottom=2}}
local COMPACT_BACKDROP = {bgFile=WHITE, edgeFile=EDGE, tile=false, edgeSize=8,
    insets={left=2, right=2, top=2, bottom=2}}

-- Controls styled once and repainted only when the active choice changes.
-- Weak keys: the registry never keeps a frame alive by itself.
local weak = {__mode="k"}
local buttons = setmetatable({}, weak)
local inputs = setmetatable({}, weak)
local windows = setmetatable({}, weak)
local rows = setmetatable({}, weak)
local selectables = setmetatable({}, weak)
local labels = setmetatable({}, weak)
-- Native menus Nexus opens (T.OpenMenu): the initializer frames it opened
-- them with, each shared list's own fill, and the lists that show a Nexus
-- menu now (list -> its initializer).
local menuOwners = setmetatable({}, weak)
local menuFills = setmetatable({}, weak)
local menuLists = setmetatable({}, weak)
-- An explicit choice the Store owner could not keep (read-only saved data or
-- no owner yet). It lasts for this session only and is never written anywhere.
local session = {}
local active

local function CopyStats()
    local out = {}
    for key, value in pairs(stats) do out[key] = value end
    return out
end

local function Color(c, alpha)
    return c[1], c[2], c[3], alpha or c[4] or 1
end

local function Dim(c)
    return {c[1] * 0.5, c[2] * 0.5, c[3] * 0.5}
end

local function TextRegion(button)
    if button.GetFontString then return button:GetFontString() end
    return button.text
end

-- Current Ebonhold UIPanelButtonTemplate inherits separate Left/Middle/Right
-- texture regions; older 3.3.5 templates use managed normal/pushed textures.
-- Clear only stock artwork once. State scripts keep those same regions and
-- swap their files, so zero alpha persists without a recurring scan or hook.
-- Preserve labels, custom icons, the hover texture and all input/Click scripts.
local function SuppressStockArt(control, stock)
    if not control.GetRegions then return end
    local regions = {control:GetRegions()}
    for _, region in ipairs(regions) do
        if region and region.GetObjectType and region:GetObjectType() == "Texture"
            and region.GetTexture then
            local texture = region:GetTexture()
            if type(texture) == "string" and texture:lower():find(stock, 1, true) then
                pcall(region.SetAlpha, region, 0)
                pcall(region.Hide, region)
            end
        end
    end
end

-- One recognised value, one choice; anything else falls back without being
-- rewritten. Pure, so the mapping can be asserted directly.
function T.Resolve(savedStyle, savedPalette)
    local style = type(savedStyle) == "string" and STYLES[savedStyle] or nil
    local palette = type(savedPalette) == "string" and PALETTES[savedPalette] or nil
    local resolved = {
        style=style or STYLES[T.DEFAULT_STYLE],
        savedStyle=savedStyle, savedPalette=savedPalette,
        explicitStyle=style ~= nil, explicitPalette=palette ~= nil,
        unknownStyle=savedStyle ~= nil and style == nil,
        unknownPalette=savedPalette ~= nil and palette == nil,
    }
    resolved.palette = palette or PALETTES[resolved.style.palette]
    return resolved
end

local function SavedChoices()
    local store = Nexus.Store
    if not (store and type(store.Settings) == "function") then return nil, nil, nil end
    local ok, settings = pcall(store.Settings)
    if not ok or type(settings) ~= "table" then return nil, nil, nil end
    local style, palette = settings[T.STYLE_KEY], settings[T.PALETTE_KEY]
    -- A read-only saved root (future or unverified format) runs with a
    -- validated copy of its settings that leaves these presentation keys out.
    -- Its saved choice is then read, never written, from the saved table, so
    -- an explicit Nexus Slate stays Nexus Slate there too.
    local db = NexusDB
    local saved = type(db) == "table" and rawget(db, "settings") or nil
    if type(saved) == "table" and saved ~= settings then
        if style == nil then style = rawget(saved, T.STYLE_KEY) end
        if palette == nil then palette = rawget(saved, T.PALETTE_KEY) end
    end
    return style, palette, settings
end

-- A primary action (T.SetPrimary) is filled with the palette's hover colour
-- while it is enabled; the style's text keeps its contrast on that fill. A
-- disabled primary is drawn as any disabled button, so it never looks
-- available. Every other button keeps the style's own fill.
local function ButtonFill(button, enabled)
    if button._nexusPrimary and enabled ~= false then
        return Color(active.palette.hover, 1)
    end
    return Color(active.style.buttonBg)
end

local function ButtonState(button, enabled)
    local style, palette = active.style, active.palette
    if enabled == nil then
        local value = not button.IsEnabled or button:IsEnabled()
        enabled = value == true or value == 1
    end
    if button._nexusPrimary then
        pcall(button.SetBackdropColor, button, ButtonFill(button, enabled))
    end
    local text = TextRegion(button)
    if enabled then
        if text then pcall(text.SetTextColor, text, Color(style.text)) end
        local edge = button._nexusSelected and palette.accent or palette.border
        pcall(button.SetBackdropBorderColor, button, Color(edge, 0.95))
    else
        if text then pcall(text.SetTextColor, text, Color(style.disabledText)) end
        pcall(button.SetBackdropBorderColor, button,
            Color(palette.disabledBorder or Dim(palette.border), 0.8))
    end
end

local function PaintButton(button)
    local style, palette = active.style, active.palette
    pcall(button.SetBackdrop, button,
        button._nexusCompact and COMPACT_BACKDROP or BUTTON_BACKDROP)
    pcall(button.SetBackdropColor, button, ButtonFill(button))
    local hover = button._nexusDarkHover
    if hover then
        -- On a primary fill the hover colour would not show; the accent does.
        local tint = button._nexusPrimary and palette.accent or palette.hover
        pcall(hover.SetVertexColor, hover, Color(tint, button._nexusPrimary and 0.25 or style.hoverAlpha))
    end
    ButtonState(button)
end

local function PaintSelected(button)
    local bar = button._nexusSelectedBar
    if bar then pcall(bar.SetVertexColor, bar, Color(active.palette.accent, 1)) end
end

local function PaintInput(input)
    pcall(input.SetBackdrop, input, COMPACT_BACKDROP)
    pcall(input.SetBackdropColor, input, Color(active.style.buttonBg))
    pcall(input.SetBackdropBorderColor, input, Color(active.palette.border, 0.95))
end

-- The opaque base under a styled window (T.StyleWindow). Its frame sits one
-- level below the window in the window's strata, so the window's own
-- backdrop, shade, accent line, text and children all draw above it. A window
-- at level 0 has no lower level; it keeps its backdrop alone.
local function SyncWindowBase(window)
    local base = window._nexusWindowBase
    if not base then return false end
    local level = tonumber(window.GetFrameLevel and window:GetFrameLevel()) or 0
    if level < 1 then base:Hide(); return false end
    pcall(base.SetFrameLevel, base, level - 1)
    base:Show()
    return true
end
T._SyncWindowBase = SyncWindowBase

local function PaintWindow(window)
    local style, palette = active.style, active.palette
    local c = style.windowColor
    pcall(window.SetBackdrop, window, style.windowBackdrop)
    pcall(window.SetBackdropColor, window, c[1], c[2], c[3], window._nexusWindowAlpha or 0.90)
    pcall(window.SetBackdropBorderColor, window, Color(palette.windowBorder, 0.95))
    local base = window._nexusWindowBase
    if base then
        -- Inside the border, at the style's own backdrop insets.
        local inset = style.windowBackdrop.insets and style.windowBackdrop.insets.left or 3
        base:ClearAllPoints()
        base:SetPoint("TOPLEFT", window, "TOPLEFT", inset, -inset)
        base:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -inset, inset)
        local b = style.baseColor or c
        pcall(base._nexusFill.SetVertexColor, base._nexusFill, b[1], b[2], b[3], 1)
        SyncWindowBase(window)
    end
    local shade = window._nexusWindowShade
    if shade and style.shade then
        local s = style.shade
        pcall(shade.SetGradientAlpha, shade, "VERTICAL", s[1], s[2], s[3], s[4], s[1], s[2], s[3], s[4])
        pcall(shade.SetVertexColor, shade, s[1], s[2], s[3], s[4])
    elseif shade then
        local b, g = style.shadeBottom, palette.accent
        pcall(shade.SetVertexColor, shade, 1, 1, 1, 1)
        pcall(shade.SetGradientAlpha, shade, "VERTICAL",
            b[1], b[2], b[3], b[4], g[1], g[2], g[3], style.glowAlpha)
    end
    local line = window._nexusWindowAccent
    if line and style.accentAlpha then
        pcall(line.SetVertexColor, line, Color(palette.accent, style.accentAlpha))
        line:Show()
    elseif line then
        line:Hide()
    end
end

local function PaintRow(row)
    pcall(row.SetBackdropBorderColor, row, Color(active.palette.border, 0.95))
end

local function PaintLabel(label, role)
    local color = role == "accent" and active.palette.accent
        or role == "muted" and active.style.disabledText
        or active.style.text
    if not color then return end
    pcall(label.SetTextColor, label, color[1], color[2], color[3], 1)
end

-- Repaints what is already styled. Bounded by the registry, adds no texture
-- or hook, and never walks a frame tree.
local function Reapply()
    stats.reapplies = stats.reapplies + 1
    local count = 0
    for window in pairs(windows) do PaintWindow(window); count = count + 1 end
    for button in pairs(buttons) do PaintButton(button); count = count + 1 end
    for input in pairs(inputs) do PaintInput(input); count = count + 1 end
    for row in pairs(rows) do PaintRow(row); count = count + 1 end
    for label, role in pairs(labels) do
        PaintLabel(label, role)
        count = count + 1
    end
    for button in pairs(selectables) do
        PaintSelected(button)
        if not buttons[button] then count = count + 1 end
    end
    stats.reappliedControls = stats.reappliedControls + count
    return count
end

-- The active choice. Re-resolved only when the saved values, the settings
-- table the Store serves, or a session-only choice changed; a change repaints
-- the registry once.
local function Active()
    local savedStyle, savedPalette, settings = SavedChoices()
    local rawStyle, rawPalette = savedStyle, savedPalette
    if session.style then rawStyle = session.style.value end
    if session.palette then rawPalette = session.palette.value end
    if active and active.source == settings and active.rawStyle == rawStyle
        and active.rawPalette == rawPalette then
        return active
    end
    local previous = active
    active = T.Resolve(rawStyle, rawPalette)
    active.source, active.rawStyle, active.rawPalette = settings, rawStyle, rawPalette
    active.sessionOnly = session.style ~= nil or session.palette ~= nil
    stats.resolves = stats.resolves + 1
    if previous and (previous.style ~= active.style or previous.palette ~= active.palette) then
        Reapply()
    end
    return active
end

function T.StyleButton(button, compact)
    if not button or button._nexusDarkStyled or button._nexusThemeExempt then return button end
    if not button.GetObjectType or button:GetObjectType() ~= "Button" then return button end
    local text = TextRegion(button)
    if not text then return button end
    button._nexusDarkStyled = true
    button._nexusCompact = compact and true or nil
    stats.buttonsStyled = stats.buttonsStyled + 1
    -- A tree of new buttons resolves the choice once, not once per button;
    -- windows and explicit choices re-read it.
    if not active then Active() end

    SuppressStockArt(button, "interface\\buttons\\ui-panel-button-")

    pcall(button.SetNormalTexture, button, nil)
    pcall(button.SetPushedTexture, button, nil)
    pcall(button.SetDisabledTexture, button, nil)
    pcall(button.SetHighlightTexture, button, nil)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    stats.textures = stats.textures + 1
    hover:SetTexture(WHITE)
    hover:SetAllPoints()
    button._nexusDarkHover = hover

    -- Shared handlers read the active choice when they run, so a later
    -- colour change needs no new hook.
    button:HookScript("OnMouseDown", T._OnMouseDown)
    button:HookScript("OnMouseUp", T._OnMouseUp)
    button:HookScript("OnEnable", T._OnEnable)
    button:HookScript("OnDisable", T._OnDisable)
    stats.hooks = stats.hooks + 4
    buttons[button] = true
    PaintButton(button)
    return button
end

-- Only callers that own an ordinary input opt in; multi-line copy/report
-- boxes and embedded foreign-client controls are not styled by a tree walk.
function T.StyleInput(input)
    if not input or input._nexusInputStyled or input._nexusThemeExempt then return input end
    input._nexusInputStyled = true
    if not active then Active() end
    SuppressStockArt(input, "interface\\common\\common-input-border")
    -- The inherited border extended outside the box; our backdrop is inside.
    -- Reserve clearance while leaving 53 units for the five-digit maximum.
    pcall(input.SetTextInsets, input, 6, 6, 0, 0)
    inputs[input] = true
    PaintInput(input)
    return input
end

function T._OnMouseDown(self)
    if active then pcall(self.SetBackdropColor, self, Color(active.style.pressedBg)) end
end
function T._OnMouseUp(self)
    if not active then return end
    local enabled = not self.IsEnabled or self:IsEnabled()
    pcall(self.SetBackdropColor, self, ButtonFill(self, enabled == true or enabled == 1))
end
function T._OnEnable(self) if active then ButtonState(self, true) end end
function T._OnDisable(self) if active then ButtonState(self, false) end end

function T.StyleWindow(window, alpha)
    if not window or window._nexusWindowStyled then return window end
    window._nexusWindowStyled = true
    window._nexusWindowAlpha = alpha or 0.90
    stats.windowsStyled = stats.windowsStyled + 1
    Active()
    local shade = window:CreateTexture(nil, "BACKGROUND")
    stats.textures = stats.textures + 1
    shade:SetTexture(WHITE)
    shade:SetPoint("TOPLEFT", 5, -5)
    shade:SetPoint("BOTTOMRIGHT", -5, 5)
    window._nexusWindowShade = shade
    -- A thin edge under the top border; shown only by styles that use it.
    local line = window:CreateTexture(nil, "BORDER")
    stats.textures = stats.textures + 1
    line:SetTexture(WHITE)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 6, -6)
    line:SetPoint("TOPRIGHT", -6, -6)
    window._nexusWindowAccent = line
    -- #163 visual review: game text showed through windows that asked for
    -- 0.94-0.98. The requested alpha is only the backdrop colour's; Nexus
    -- Slate's tiled dialog background has its own partly transparent texels,
    -- and every style's shade is translucent. An opaque base one level below
    -- the window gives each style a solid floor behind its text while the
    -- window still draws its own backdrop, texture, shade and border on top
    -- (the same identity). Native effective opacity is not established here.
    local base = CreateFrame("Frame", nil, window)
    local fill = base:CreateTexture(nil, "BACKGROUND")
    stats.textures = stats.textures + 1
    fill:SetTexture(WHITE)
    fill:SetAllPoints(base)
    base._nexusFill = fill
    window._nexusWindowBase = base
    stats.windowBases = stats.windowBases + 1
    -- A window raised or re-levelled while hidden takes its base along.
    if window.HookScript then
        window:HookScript("OnShow", SyncWindowBase)
        stats.hooks = stats.hooks + 1
    end
    windows[window] = true
    PaintWindow(window)
    T.EnsureTooltipBase()
    return window
end

-- A Nexus tooltip gets the same solid floor: a base under GameTooltip, shown
-- only while the tooltip's owner lies inside a styled Nexus window or a
-- shared menu list that shows a Nexus menu now (T.OpenMenu), and hidden for
-- every other owner and whenever the tooltip hides. GameTooltip's own
-- backdrop, size and lines are unchanged. Created and hooked once.
local tooltipHooked = false
local function StyledOwner(owner)
    local node, depth = owner, 0
    while node and depth < 16 do
        if windows[node] or menuLists[node] then return node end
        if type(node.GetParent) ~= "function" then return nil end
        local ok, parent = pcall(node.GetParent, node)
        node = ok and parent or nil
        depth = depth + 1
    end
    return nil
end
function T.SyncTooltipBase(tip)
    tip = tip or GameTooltip
    local base = tip and tip._nexusSolidBase
    if not base then return false end
    local okOwner, owner = pcall(tip.GetOwner, tip)
    local level = tonumber(tip.GetFrameLevel and tip:GetFrameLevel()) or 0
    if not (okOwner and owner and level >= 1 and StyledOwner(owner)) then
        base:Hide()
        return false
    end
    if not active then Active() end
    local c = active.style.baseColor or active.style.windowColor
    pcall(base._nexusFill.SetVertexColor, base._nexusFill, c[1], c[2], c[3], 1)
    pcall(base.SetFrameLevel, base, level - 1)
    base:Show()
    return true
end
function T.EnsureTooltipBase()
    if tooltipHooked then return true end
    local tip = GameTooltip
    if not (tip and tip.HookScript and type(hooksecurefunc) == "function"
        and type(CreateFrame) == "function") then return false end
    tooltipHooked = true
    local base = CreateFrame("Frame", nil, tip)
    base:SetPoint("TOPLEFT", tip, "TOPLEFT", 3, -3)
    base:SetPoint("BOTTOMRIGHT", tip, "BOTTOMRIGHT", -3, 3)
    local fill = base:CreateTexture(nil, "BACKGROUND")
    stats.textures = stats.textures + 1
    fill:SetTexture(WHITE)
    fill:SetAllPoints(base)
    base._nexusFill = fill
    base:Hide()
    tip._nexusSolidBase = base
    stats.tooltipBases = stats.tooltipBases + 1
    -- A post-hook: every Show of the shared tooltip, whoever calls it, runs
    -- first; this only shows or hides the base, never the tooltip. OnShow
    -- covers a tooltip the client shows without a Lua Show call (a SetText
    -- or Set* that shows it); a Show of an already shown tooltip with a new
    -- owner has only the Show hook.
    local function Sync(self) pcall(T.SyncTooltipBase, self) end
    hooksecurefunc(tip, "Show", Sync)
    tip:HookScript("OnShow", Sync)
    tip:HookScript("OnHide", function(self)
        if self._nexusSolidBase then self._nexusSolidBase:Hide() end
    end)
    stats.hooks = stats.hooks + 3
    return true
end

-- Native menus Nexus opens (native acceptance of test.163009: the Options
-- menu fitted the screen, but main-panel text stayed readable through it).
-- EasyMenu initializes the Nexus anchor frame and then displays the menu in
-- the shared DropDownList<n> frames that every game and addon menu reuses
-- (3.3.5 export, build 12340: UIDropDownMenu.xml 5-20; UIDropDownMenu.lua
-- 178-201, 576-722 and 794-810; EasyMenu.lua 17-22), so styling the anchor
-- never reached the surface on screen. Such a list gets one solid fill: a
-- BACKGROUND texture of the list itself over its stock MenuBackdrop's
-- background area (that backdrop's own 5-unit insets, UIDropDownMenuTemplates
-- .xml 163-196, so no square corner shows past its rounded border),
-- so that backdrop, its border and every row (all child frames of the list)
-- still draw over it, in the list's own FULLSCREEN_DIALOG strata; no frame
-- level is assumed. The fill shows only while its list is shown and the root
-- menu open in it (UIDROPDOWNMENU_OPEN_MENU: set for level 1 and kept by its
-- submenus, lines 622-624 and 690-693) is a frame T.OpenMenu opened. Another
-- menu reusing the list, a hide and a close hide it again; the lists keep
-- every script (HookScript), size, anchor, row, callback and timeout, and
-- ToggleDropDownMenu is only post-hooked. Native effective opacity is not
-- established here.
local MENU_INSET = 5
local menuHooked = false

local function SyncMenuList(list)
    local fill = list and menuFills[list]
    if not fill then return false end
    local open = _G.UIDROPDOWNMENU_OPEN_MENU
    if not (open ~= nil and menuOwners[open] and list:IsShown()) then
        fill:Hide()
        menuLists[list] = nil
        return false
    end
    if not active then Active() end
    local c = active.style.baseColor or active.style.windowColor
    pcall(fill.SetVertexColor, fill, c[1], c[2], c[3], 1)
    fill:Show()
    menuLists[list] = open
    return true
end

local function HideMenuFill(list)
    local fill = menuFills[list]
    if fill then fill:Hide() end
    menuLists[list] = nil
end

-- Made once per shared list, the first time a Nexus menu shows in it.
local function MenuFill(list)
    local fill = menuFills[list]
    if fill then return fill end
    if not (list.CreateTexture and list.HookScript) then return nil end
    fill = list:CreateTexture(nil, "BACKGROUND")
    stats.textures = stats.textures + 1
    fill:SetTexture(WHITE)
    local name = list.GetName and list:GetName()
    local surface = name and _G[name .. "MenuBackdrop"] or list
    fill:SetPoint("TOPLEFT", surface, "TOPLEFT", MENU_INSET, -MENU_INSET)
    fill:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT", -MENU_INSET, MENU_INSET)
    fill:Hide()
    menuFills[list] = fill
    stats.menuFills = stats.menuFills + 1
    -- A list shown or redrawn for another owner, or hidden by a close or a
    -- timeout, follows at once.
    list:HookScript("OnShow", SyncMenuList)
    list:HookScript("OnHide", HideMenuFill)
    stats.hooks = stats.hooks + 2
    return fill
end

-- Every shared list, levels made on demand included: a list a Nexus menu
-- shows gets its fill, every other list has it hidden. Returns how many
-- lists show a Nexus menu.
function T.SyncMenus()
    local open = _G.UIDROPDOWNMENU_OPEN_MENU
    local owned = open ~= nil and menuOwners[open] == true
    local treated, level = 0, 1
    local list = _G.DropDownList1
    while list do
        if owned and list:IsShown() then MenuFill(list) end
        if SyncMenuList(list) then treated = treated + 1 end
        level = level + 1
        list = _G["DropDownList" .. level]
    end
    return treated
end

-- Submenus open from a row's hover or its arrow, both through
-- ToggleDropDownMenu (UIDropDownMenuTemplates.xml 87-101 and 130-150).
local function EnsureMenuHook()
    if menuHooked then return true end
    if not (type(hooksecurefunc) == "function" and type(ToggleDropDownMenu) == "function") then
        return false
    end
    menuHooked = true
    hooksecurefunc("ToggleDropDownMenu", function() pcall(T.SyncMenus) end)
    stats.hooks = stats.hooks + 1
    return true
end

-- Opens a Nexus menu exactly as EasyMenu(items, frame, anchor, x, y, "MENU")
-- does, with `frame` recorded as a Nexus initializer.
function T.OpenMenu(items, frame, anchor, x, y)
    if type(EasyMenu) ~= "function" or not frame then return false end
    menuOwners[frame] = true
    EnsureMenuHook()
    EasyMenu(items, frame, anchor, x or 0, y or 0, "MENU")
    T.SyncMenus()
    return true
end

-- A window's one primary action (Plan's Save / Create, level-80 Open Orbs and
-- its Orbs hub): filled with the palette's hover colour while enabled, drawn as
-- any disabled button otherwise. on=false returns it to an ordinary button.
-- Only presentation; a repeated call with the same state does nothing.
function T.SetPrimary(button, on)
    if not button then return button end
    on = on and true or nil
    if button._nexusPrimary == on then return button end
    button._nexusPrimary = on
    if not button._nexusDarkStyled then T.StyleButton(button) end
    if button._nexusDarkStyled and active then PaintButton(button) end
    return button
end

-- Opt-in dialog labels follow style contrast and palette accents. The weak
-- registry repaints existing labels when the player changes either choice.
function T.StyleLabel(label, role)
    if not label or not label.SetTextColor then return label end
    if role ~= "accent" and role ~= "muted" then role = "text" end
    labels[label] = role
    Active()
    PaintLabel(label, role)
    return label
end

-- A frame marked exempt keeps its own look: no tree walk enters it and no
-- button inside it is restyled. The replacement difficulty / Soul Ash card
-- carries this mark.
function T.Exempt(frame)
    if frame then frame._nexusThemeExempt = true end
    return frame
end

function T.StyleTree(root)
    if not root or not root.GetChildren then return end
    if root._nexusThemeExempt then
        stats.exemptTrees = stats.exemptTrees + 1
        return root
    end
    if root._nexusDarkTreeStyled then
        stats.skippedTrees = stats.skippedTrees + 1
        return root
    end
    stats.treeWalks = stats.treeWalks + 1
    local children = { root:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        stats.nodesVisited = stats.nodesVisited + 1
        if child and not child._nexusThemeExempt and child.GetObjectType
            and child:GetObjectType() == "Button" then
            T.StyleButton(child, (child.GetHeight and child:GetHeight() or 24) <= 20)
        end
        T.StyleTree(child)
    end
    root._nexusDarkTreeStyled = true
    return root
end

-- Virtual rows already own their purpose-built backdrop and hover behavior.
-- This applies the shared border accent once without adding textures or hooks,
-- and lets marked static trees stay closed to later recursive walks.
function T.StyleVirtualRow(row, controls)
    if not row or row._nexusVirtualRowStyled then return row end
    row._nexusVirtualRowStyled = true
    stats.virtualRows = stats.virtualRows + 1
    if not active then Active() end
    rows[row] = true
    PaintRow(row)
    if type(controls) == "table" then
        for _, control in ipairs(controls) do T.StyleButton(control) end
    end
    return row
end

-- A selected tab or view: a bar under the label and a held highlight, so the
-- selection reads without relying on colour or on a disabled look.
function T.SetSelected(button, selected)
    if not button then return button end
    selected = selected and true or nil
    if button._nexusSelectedBar and button._nexusSelected == selected then return button end
    button._nexusSelected = selected
    local bar = button._nexusSelectedBar
    if not bar and button.CreateTexture then
        bar = button:CreateTexture(nil, "OVERLAY")
        stats.textures = stats.textures + 1
        bar:SetTexture(WHITE)
        bar:SetHeight(2)
        bar:SetPoint("BOTTOMLEFT", 5, 3)
        bar:SetPoint("BOTTOMRIGHT", -5, 3)
        button._nexusSelectedBar = bar
        selectables[button] = true
    end
    if not active then Active() end
    if bar then
        PaintSelected(button)
        if selected then bar:Show() else bar:Hide() end
    end
    if selected then pcall(button.LockHighlight, button)
    else pcall(button.UnlockHighlight, button) end
    if button._nexusDarkStyled then ButtonState(button) end
    return button
end

local function Ordered(source)
    local list = {}
    for _, entry in pairs(source) do list[#list + 1] = entry end
    table.sort(list, function(a, b) return a.order < b.order end)
    return list
end

function T.Styles() return Ordered(STYLES) end
function T.Palettes() return Ordered(PALETTES) end

local function DisplayValue(value)
    return (tostring(value):gsub("|", "||"):gsub("%c", " "):sub(1, 32))
end

-- Every colour a palette paints with (see ButtonState and Paint*).
local function PaintedColours(palette)
    return {palette.border, palette.windowBorder, palette.hover, palette.accent,
        palette.disabledBorder or Dim(palette.border)}
end

-- Compared by value, not by name: two palettes that paint the same colours
-- look the same, so the menu offers them as one choice.
local function SameColours(a, b)
    local x, y = PaintedColours(a), PaintedColours(b)
    for i = 1, #x do
        for j = 1, 3 do
            if x[i][j] ~= y[i][j] then return false end
        end
    end
    return true
end

-- What is in effect and why, in words a player can read.
function T.Current()
    local a = Active()
    return {
        style=a.style.id, styleLabel=a.style.label,
        palette=a.palette.id, paletteLabel=a.palette.label, hue=a.palette.hue,
        explicitStyle=a.explicitStyle, explicitPalette=a.explicitPalette,
        unknownStyle=a.unknownStyle, unknownPalette=a.unknownPalette,
        savedStyle=a.savedStyle ~= nil and DisplayValue(a.savedStyle) or nil,
        savedPalette=a.savedPalette ~= nil and DisplayValue(a.savedPalette) or nil,
        sessionOnly=a.sessionOnly == true,
    }
end

function T.Summary()
    local a = Active()
    local style, palette = StyleLabel(a.style), PaletteLabel(a.palette)
    return SayF("theme.value.summary", {style = style, palette = palette}, style .. ", " .. palette)
end

local OUTCOME = {
    durable="Saved.",
    database="Applied for this session. Local saved data is still loading, so it is not saved yet.",
    session="Applied for this session only. Saved data is kept unchanged and read-only by this build.",
    unavailable="Applied for this session only. The settings owner is not available, so nothing was saved.",
}
T.OUTCOME = OUTCOME
-- The shown outcome sentence (OUTCOME keeps the English by outcome name).
local OUTCOME_KEYS = {
    durable = "theme.status.outcome_saved",
    database = "theme.status.outcome_database_loading",
    session = "theme.status.outcome_session_read_only",
    unavailable = "theme.status.outcome_owner_unavailable",
}
local function Applied(outcome)
    local summary = T.Summary()
    local said = Say(OUTCOME_KEYS[outcome], OUTCOME[outcome])
    return SayF("theme.chat.appearance_applied", {summary = summary, outcome = said},
        "Appearance: " .. summary .. ". " .. said)
end

-- An explicit selection is the only write. It goes through the Store
-- settings owner; a refusal keeps saved data untouched and applies the choice
-- to this session only.
local function Choose(field, key, value)
    local internals = Nexus.MainInternals
    local owner = type(internals) == "table" and internals.StoreAuthorityOwner or nil
    local result, why
    if type(owner) == "table" and type(owner.UpdateSettingsV1) == "function" then
        local ok, first, second = pcall(owner.UpdateSettingsV1, key, value)
        if ok then result, why = first, second end
    end
    local outcome
    if type(result) == "table" then
        session[field] = nil
        if result.mode == "durable" then outcome = "durable"
        elseif result.reason == "database" then outcome = "database"
        else outcome = "session" end
    else
        session[field] = {value=value}
        outcome = (why == "invalid-key" or why == "invalid-value") and "session" or "unavailable"
    end
    stats.preferenceChanges = stats.preferenceChanges + 1
    Active()
    return outcome
end

function T.SetStyle(id)
    if type(id) ~= "string" or not STYLES[id] then
        return nil, Say("theme.chat.style_unavailable", "That style is not available in this build. Nothing changed.")
    end
    local outcome = Choose("style", T.STYLE_KEY, id)
    return outcome, Applied(outcome)
end

-- nil returns to the style's own colours.
function T.SetPalette(id)
    if id ~= nil and (type(id) ~= "string" or not PALETTES[id]) then
        return nil, Say("theme.chat.colour_unavailable", "That colour is not available in this build. Nothing changed.")
    end
    local outcome = Choose("palette", T.PALETTE_KEY, id)
    return outcome, Applied(outcome)
end

function T.Notify(message)
    if message and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("Nexus: " .. tostring(message))
    end
end

-- T.HELP (the Appearance hover) is a shown field: it resolves at each read
-- through the metatable below, in the session's language.
local HELP = "Appearance changes only how Nexus windows look. Style sets the "
    .. "structure (Nexus Vista is the default; Nexus Slate is the earlier shared "
    .. "dark style of the imported 1.19.3 source and test.9094, with the same "
    .. "colours and shapes; the Orb windows, plain in test.9094, now use it too). "
    .. "Colour sets the accents; Nexus Amethyst purple is the Vista default. The difficulty / Soul Ash card keeps its own "
    .. "look, and no choice changes automation or gameplay."
setmetatable(T, {__index = function(_, name)
    if name == "HELP" then return Say("theme.tooltip.appearance_help", HELP) end
    return nil
end})

-- Items for one flat 3.3.5 EasyMenu. A check mark, not only a colour, marks
-- the active choice; a saved value this build does not know is named and kept.
-- The style's own colours and any palette that paints the same colours are one
-- "Default" row. It is checked for no saved colour and for a saved palette
-- with those colours; opening the menu never rewrites either. Choosing it
-- clears the saved colour, as "Style colours" did.
function T.MenuItems(close)
    local a = Active()
    local function pick(fn, id)
        return function()
            if type(close) == "function" then close() end
            local _, message = fn(id)
            T.Notify(message)
        end
    end
    local items = {{text=Say("theme.menu.style_title", "Appearance: style"), isTitle=true, notCheckable=true}}
    for _, style in ipairs(T.Styles()) do
        local label = StyleLabel(style)
        items[#items + 1] = {
            text=style.id == T.DEFAULT_STYLE
                and SayF("theme.menu.style_default", {style = label}, label .. " (default)") or label,
            checked=a.style == style, tooltipTitle=label, tooltipText=StyleSummary(style),
            func=pick(T.SetStyle, style.id),
        }
    end
    if a.unknownStyle then
        local value = DisplayValue(a.savedStyle)
        items[#items + 1] = {notCheckable=true, disabled=true,
            text=SayF("theme.menu.unknown_style", {value = value},
                "Saved style \"" .. value .. "\" is not in this build; it stays saved.")}
    end
    items[#items + 1] = {text=Say("theme.menu.colour_title", "Appearance: colour"), isTitle=true, notCheckable=true}
    local own = PALETTES[a.style.palette]
    local ownLabel, ownHue = PaletteLabel(own), PaletteHue(own)
    items[#items + 1] = {
        text=SayF("theme.menu.colour_default", {palette = ownLabel, hue = ownHue},
            "Default (" .. ownLabel .. ", " .. ownHue .. ")"),
        checked=not a.unknownPalette and (not a.explicitPalette or SameColours(a.palette, own)),
        func=pick(T.SetPalette, nil),
    }
    for _, palette in ipairs(T.Palettes()) do
        if not SameColours(palette, own) then
            local label, hue = PaletteLabel(palette), PaletteHue(palette)
            items[#items + 1] = {
                text=SayF("theme.menu.colour_choice", {palette = label, hue = hue}, label .. " (" .. hue .. ")"),
                checked=a.explicitPalette and a.palette == palette,
                func=pick(T.SetPalette, palette.id),
            }
        end
    end
    if a.unknownPalette then
        local value = DisplayValue(a.savedPalette)
        items[#items + 1] = {notCheckable=true, disabled=true,
            text=SayF("theme.menu.unknown_colour", {value = value},
                "Saved colour \"" .. value .. "\" is not in this build; it stays saved.")}
    end
    return items
end

function T.ShowMenu(anchor)
    if type(EasyMenu) ~= "function" then return false end
    if type(CloseDropDownMenus) == "function" then CloseDropDownMenus() end
    T._menu = T._menu or CreateFrame("Frame", "NexusAppearanceMenu", UIParent, "UIDropDownMenuTemplate")
    return T.OpenMenu(T.MenuItems(CloseDropDownMenus), T._menu, anchor or "cursor", 0, 0)
end

-- Re-reads the choice and repaints styled controls if it changed.
function T.Refresh()
    Active()
    return T.Current()
end

function T.Reapply()
    Active()
    return Reapply()
end

function T.Stats()
    return CopyStats()
end
