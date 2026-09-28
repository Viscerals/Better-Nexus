-- Nexus-owned font and revision-keyed responsive geometry.
--
-- Layout is computed as plain tables before frames are moved. This keeps font
-- measurement out of render hot paths and makes every supported scale/window
-- combination deterministic under WoW 3.3.5a's Lua 5.1 runtime.

Nexus = Nexus or {}

local M = {}
local panelCache, communityCache = {}, {}
local panelOrder, communityOrder = {}, {}
local MAX_CACHE_ENTRIES = 64
local stats = {
    requests=0,computations=0,hits=0,evictions=0,
    fontBuilds=0,fontApplications=0,
}
local fontsReady = false
local runtimeSignature, runtimeRevision = nil, 1

local FONT_NAMES = {
    small="NexusFontSmall",
    normal="NexusFontNormal",
    large="NexusFontLarge",
}
local FONT_SIZES = {small=10,normal=12,large=14}

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

function M.EnsureFonts()
    if fontsReady then return FONT_NAMES end
    fontsReady = true
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
            pcall(font.SetFont, font, path, FONT_SIZES[kind], "")
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

local function PanelKey(spec)
    return table.concat({
        Round(spec.width or 272,1),Round(spec.fontScale or 1,3),
        Round(spec.uiScale or 1,3),tonumber(spec.revision) or 0,
        spec.activeRoll and 1 or 0,spec.statusVisible and 1 or 0,
        spec.noBuild and 1 or 0,spec.complete and 1 or 0,
        spec.showPerformance and 1 or 0,
        (tonumber(spec.toLockCount) or 0) > 0 and 1 or 0,
        (tonumber(spec.unknownTomes) or 0) > 0 and 1 or 0,
    }, "|")
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
    local cursor = 6
    local headerHeight = math.max(26, large + 8)
    Add(layout,"header",8,cursor,width-16,headerHeight)
    cursor = cursor + headerHeight + gap

    if spec.statusVisible then
        local height = math.max(52, normal + small * 2 + gap * 2)
        Add(layout,"status",10,cursor,width-20,height)
        cursor = cursor + height + gap
    end
    if spec.activeRoll then
        local height = math.max(104, small * 6 + gap * 4)
        Add(layout,"roll",10,cursor,width-20,height)
        cursor = cursor + height + gap
    end
    layout.contentTop = cursor

    if spec.noBuild then
        Add(layout,"setupTitle",12,cursor,width-24,large)
        cursor = cursor + large + gap
        Add(layout,"setupHint",12,cursor,width-24,small * 2)
        cursor = cursor + small * 2 + gap
        local buttonHeight = math.max(24, normal + 8)
        Add(layout,"setupAssign",(width-146)/2,cursor,146,buttonHeight)
        cursor = cursor + buttonHeight + gap
        Add(layout,"setupCreate",(width-146)/2,cursor,146,buttonHeight)
        cursor = cursor + buttonHeight + gap
    elseif spec.complete then
        if not spec.statusVisible then
            Add(layout,"completeTitle",12,cursor,width-24,normal)
            cursor = cursor + normal + gap
            Add(layout,"completeText",12,cursor,width-24,small * 2)
            cursor = cursor + small * 2 + gap
        end
        if spec.showPerformance then
            local height = small * 8 + gap * 5
            Add(layout,"performance",12,cursor,width-24,height)
            cursor = cursor + height + gap
        end
    else
        Add(layout,"progressHeader",12,cursor,width-24,small)
        cursor = cursor + small + math.max(3,math.floor(gap/2))
        Add(layout,"progressValue",12,cursor,width-24,normal)
        cursor = cursor + normal + gap
        if (tonumber(spec.unknownTomes) or 0) > 0 then
            Add(layout,"tomes",12,cursor,width-24,small)
            cursor = cursor + small + gap
        end
        local columnGap = 12
        local columnWidth = math.floor((width - 24 - columnGap) / 2)
        local columnHeight = small * 4 + math.max(3,math.floor(gap/2))
        Add(layout,"needed",12,cursor,columnWidth,columnHeight)
        Add(layout,"shed",12+columnWidth+columnGap,cursor,
            width-24-columnWidth-columnGap,columnHeight)
        cursor = cursor + columnHeight + gap
        if (tonumber(spec.toLockCount) or 0) > 0 then
            local height = small * 3 + math.max(3,math.floor(gap/2))
            Add(layout,"toLock",12,cursor,width-24,height)
            cursor = cursor + height + gap
        end
        if spec.showPerformance then
            local height = small * 5 + gap * 4
            Add(layout,"performance",12,cursor,width-24,height)
            cursor = cursor + height + gap
        end
    end

    if not spec.noBuild then
        Add(layout,"bestDps",12,cursor,width-24,small)
        cursor = cursor + small + gap
    end
    layout.contentBottom = cursor
    local footerHeight = math.max(22, normal + 7)
    local reduction = spec.statusVisible and 0 or 59
    local legacyMinimum
    if spec.noBuild then
        legacyMinimum = (spec.activeRoll and 428 or 278) - reduction
    elseif spec.complete then
        if spec.showPerformance then
            legacyMinimum = (spec.activeRoll and 430 or 286) - reduction
        else
            legacyMinimum = (spec.activeRoll and 292 or 168) - reduction
        end
    elseif spec.showPerformance then
        legacyMinimum = (spec.activeRoll and 448 or 325) - reduction
    else
        legacyMinimum = (spec.activeRoll and 388 or 267) - reduction
    end
    if not spec.noBuild and not spec.complete
        and (tonumber(spec.toLockCount) or 0) > 0 then
        legacyMinimum = legacyMinimum + 34
    end
    local footerY = math.max(cursor + gap,
        legacyMinimum - footerHeight - 7)
    Add(layout,"footer",8,footerY,width-16,footerHeight)
    layout.height = footerY + footerHeight + 7
    return Remember(panelCache,panelOrder,key,layout)
end

local CONTROL_ORDER = {"search","scope","mine","class","qualified","sort"}
local ACTION_ORDER = {"sync","share"}
local CONTROL_BASE = {
    search=165,scope=84,mine=84,class=128,qualified=112,sort=126,
    sync=88,share=110,
}

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
        LabelKey(labels)},"|")
end

local function ControlWidth(name, label, scale, available)
    local base = CONTROL_BASE[name] or 80
    local estimated = #tostring(label or "") * 6 * scale + 22
    local maximum = name == "search" and 320 or 240
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
    Add(layout,"title",52,10,width-104,normal)
    local navY = layout.boxes.title.y + layout.boxes.title.h + gap
    Add(layout,"nav",18,navY,math.min(314,width-70),math.max(24,normal+8))
    local cursor = layout.boxes.nav.y + layout.boxes.nav.h + gap * 2
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
    local statusHeight = math.max(28, small * (spec.syncActive and 2 or 2) + gap)
    Add(layout,"status",20,cursor,width-40,statusHeight)
    cursor = cursor + statusHeight + gap

    local bodyTop = cursor
    local minimumBody = math.max(150,math.ceil(110 * scale))
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
