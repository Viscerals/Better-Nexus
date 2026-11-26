-- Local font support for Nexus. English keeps the client's original fonts.
-- The selected language continues to be owned by Nexus's language chooser.
Nexus = Nexus or {}
local F = {}
Nexus.FontSupport = F

local nativeCreateFrame = CreateFrame
local fontFile = "Interface\\AddOns\\Nexus\\Fonts\\DejaVuSans.ttf"
local russian = false
local watched = setmetatable({}, {__mode = "k"})
local shared = setmetatable({}, {__mode = "k"})
local fallbackFonts = setmetatable({}, {__mode = "k"})

local function ApplyOne(widget, saved)
    if not widget then return end
    if type(widget.GetFontString) == "function" then
        local label = widget:GetFontString()
        if label and label ~= widget then ApplyOne(label, saved) end
    end
    if type(widget.GetFont) ~= "function" or type(widget.SetFont) ~= "function" then return end
    local path, size, flags = widget:GetFont()
    if not path or not size then return end
    local text = widget.GetText and widget:GetText()
    local needsCyrillic = russian or (type(text) == "string" and text:find("[\208\209]"))
    if not needsCyrillic then
        local original = fallbackFonts[widget]
        if original then
            if path == fontFile then widget:SetFont(original[1], original[2], original[3] or "") end
            fallbackFonts[widget] = nil
        end
        return
    end
    if path == fontFile then return end
    if saved and not saved[widget] then saved[widget] = {path, size, flags} end
    if not russian and not fallbackFonts[widget] then fallbackFonts[widget] = {path, size, flags} end
    -- SetFont changes this widget's face only; size, flags and colour survive.
    widget:SetFont(fontFile, size, flags or "")
end

local function Changed(widget)
    ApplyOne(widget)
end

local function Walk(root, visit)
    local seen = {}
    local function Step(widget)
        if not widget or seen[widget] then return end
        seen[widget] = true
        visit(widget)
        if type(widget.GetRegions) == "function" then
            for _, region in ipairs({widget:GetRegions()}) do Step(region) end
        end
        if type(widget.GetChildren) == "function" then
            for _, child in ipairs({widget:GetChildren()}) do Step(child) end
        end
    end
    Step(root)
end

local Watch
local function WatchRegions(owner)
    if type(owner.GetRegions) == "function" then
        for _, region in ipairs({owner:GetRegions()}) do Walk(region, Watch) end
    end
end

Watch = function(widget)
    if watched[widget] then return end
    watched[widget] = true
    ApplyOne(widget)
    if type(hooksecurefunc) ~= "function" then return end
    -- Blizzard button templates may reapply their normal/disabled font.
    -- These instance hooks restore Cyrillic before the caller measures text.
    for _, method in ipairs({"SetFontObject", "SetNormalFontObject",
        "SetHighlightFontObject", "SetDisabledFontObject", "SetText", "Enable", "Disable"}) do
        if type(widget[method]) == "function" then
            hooksecurefunc(widget, method, Changed)
        end
    end
    if type(widget.CreateFontString) == "function" then
        hooksecurefunc(widget, "CreateFontString", WatchRegions)
    end
end

-- Nexus UI files use this local factory; the global CreateFrame is unchanged.
function F.CreateFrame(...)
    local widget = nativeCreateFrame(...)
    Walk(widget, Watch)
    return widget
end

function F.Path(original)
    return russian and fontFile or original
end

function F.Refresh()
    local localization = Nexus.Localization
    russian = type(localization) == "table"
        and type(localization.ActiveLanguage) == "function"
        and localization.ActiveLanguage() == "ruRU"
    for widget in pairs(watched) do ApplyOne(widget) end
    if Nexus.LayoutMetrics and type(Nexus.LayoutMetrics.EnsureFonts) == "function" then
        Nexus.LayoutMetrics.EnsureFonts()
    end
end

-- Native dropdowns and GameTooltip are shared. Their original faces are
-- restored when Nexus releases them; no hooks are added to their text rows.
function F.ApplyShared(root, owned)
    if not root then return end
    local saved = shared[root]
    if owned then
        if not saved then
            saved = setmetatable({}, {__mode = "k"})
            shared[root] = saved
        end
        Walk(root, function(widget) ApplyOne(widget, saved) end)
    elseif saved then
        for widget, font in pairs(saved) do
            if widget:GetFont() == fontFile then
                widget:SetFont(font[1], font[2], font[3] or "")
            end
        end
        shared[root] = nil
    end
end

local function NexusOwner(widget)
    for _ = 1, 32 do
        if not widget then return false end
        if watched[widget] then return true end
        local name = type(widget.GetName) == "function" and widget:GetName()
        if type(name) == "string" and name:match("^Nexus") then return true end
        widget = type(widget.GetParent) == "function" and widget:GetParent() or nil
    end
    return false
end

if type(hooksecurefunc) == "function" then
    local localization = Nexus.Localization
    if localization and type(localization.InitializeActiveLanguage) == "function" then
        hooksecurefunc(localization, "InitializeActiveLanguage", F.Refresh)
    end
    local tooltip = _G.GameTooltip
    if tooltip then
        local function TooltipChanged(self)
            local owner = type(self.GetOwner) == "function" and self:GetOwner()
            F.ApplyShared(self, NexusOwner(owner))
        end
        for _, method in ipairs({"SetOwner", "SetText", "AddLine", "AddDoubleLine", "Show"}) do
            if type(tooltip[method]) == "function" then
                hooksecurefunc(tooltip, method, TooltipChanged)
            end
        end
        if type(tooltip.HookScript) == "function" then
            tooltip:HookScript("OnHide", function(self) F.ApplyShared(self, false) end)
        end
    end
end

F.Refresh()
