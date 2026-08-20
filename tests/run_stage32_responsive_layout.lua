-- Stage 32 responsive-layout contract. Geometry is computed without creating
-- frames so font/UI-scale changes can be checked deterministically and cached.
Nexus = {}

local sharedTouched = 0
GameFontNormal = { SetFont=function() sharedTouched=sharedTouched+1 end }
GameFontHighlightSmall = { SetFont=function() sharedTouched=sharedTouched+1 end }
GameFontDisableSmall = { SetFont=function() sharedTouched=sharedTouched+1 end }
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

local ownedFonts = {}
function CreateFont(name)
    local font = { name=name }
    function font:SetFont(path, size, flags)
        self.path, self.size, self.flags = path, size, flags
    end
    ownedFonts[name] = font
    _G[name] = font
    return font
end

dofile("ui/LayoutMetrics.lua")
local Layout = assert(Nexus.LayoutMetrics,
    "responsive layout owner did not register")

local failures = {}
local checks = 0
local function Expect(name, condition, detail)
    checks = checks + 1
    if not condition then
        failures[#failures + 1] = name .. ": " .. tostring(detail)
    end
end

local function Inside(container, child)
    return child.x >= container.x and child.y >= container.y
        and child.x + child.w <= container.x + container.w
        and child.y + child.h <= container.y + container.h
end

local function NoOverlap(boxes, names)
    for leftIndex = 1, #names do
        for rightIndex = leftIndex + 1, #names do
            local left, right = boxes[names[leftIndex]], boxes[names[rightIndex]]
            if left and right and Layout.Overlap(left, right) then
                return false, names[leftIndex] .. "/" .. names[rightIndex]
            end
        end
    end
    return true
end

local fontNames = Layout.EnsureFonts()
Expect("owned_fonts_created",
    fontNames.small == "NexusFontSmall"
        and fontNames.normal == "NexusFontNormal"
        and fontNames.large == "NexusFontLarge"
        and ownedFonts.NexusFontSmall and ownedFonts.NexusFontNormal
        and ownedFonts.NexusFontLarge,
    "Nexus-owned font objects were not created")
Expect("shared_fonts_untouched", sharedTouched == 0,
    "globally shared Blizzard font objects were mutated")

local panelCases = 0
for _, fontScale in ipairs({1, 1.25, 1.5, 2}) do
    for _, uiScale in ipairs({0.75, 1}) do
        for _, state in ipairs({
            {name="progress", activeRoll=false,statusVisible=false,
                noBuild=false,complete=false,showPerformance=true,
                toLockCount=3,unknownTomes=2},
            {name="live", activeRoll=true,statusVisible=true,
                noBuild=false,complete=false,showPerformance=true,
                toLockCount=3,unknownTomes=2},
            {name="complete", activeRoll=true,statusVisible=true,
                noBuild=false,complete=true,showPerformance=true,
                toLockCount=0,unknownTomes=0},
            {name="setup", activeRoll=false,statusVisible=true,
                noBuild=true,complete=false,showPerformance=false,
                toLockCount=0,unknownTomes=0},
        }) do
            local spec = {}
            for key, value in pairs(state) do spec[key] = value end
            spec.width, spec.fontScale, spec.uiScale, spec.revision =
                272, fontScale, uiScale, 32
            local layout = Layout.Panel(spec)
            panelCases = panelCases + 1
            local ok, pair = NoOverlap(layout.boxes, layout.required)
            Expect("panel_zero_overlap_" .. state.name .. "_" .. fontScale
                .. "_" .. uiScale, ok, pair)
            for _, name in ipairs(layout.required) do
                Expect("panel_inside_" .. state.name .. "_" .. name,
                    Inside({x=0,y=0,w=layout.width,h=layout.height},
                        layout.boxes[name]), name)
            end
            Expect("panel_footer_below_content_" .. state.name,
                layout.boxes.footer.y >= layout.contentBottom,
                layout.boxes.footer.y .. "/" .. layout.contentBottom)
        end
    end
end

local longLabels = {
    search="Search title, author, localized description, or exact identifier",
    scope="Every Shared Community Build",mine="My Imported Saved Builds",
    class="Current Character Class Only",qualified="Qualified Records Only",
    sort="Sort by Highest Verified Damage",sync="Listening for Nearby Builds",
    share="Share This Exact Build With Nearby Players",
}
local communityCases = 0
for _, width in ipairs({760, 1040}) do
    for _, fontScale in ipairs({1, 1.25, 1.5, 2}) do
        for _, state in ipairs({
            {name="empty",empty=true,syncActive=false,results=0},
            {name="full",empty=false,syncActive=false,results=20},
            {name="sync",empty=false,syncActive=true,results=20},
        }) do
            local layout = Layout.Community({
                width=width,height=640,fontScale=fontScale,uiScale=0.8,
                revision=32,labels=longLabels,empty=state.empty,
                syncActive=state.syncActive,results=state.results,
            })
            communityCases = communityCases + 1
            local ok, pair = NoOverlap(layout.boxes, layout.required)
            Expect("community_zero_overlap_" .. width .. "_"
                .. fontScale .. "_" .. state.name, ok, pair)
            for _, name in ipairs(layout.required) do
                Expect("community_inside_" .. width .. "_" .. name,
                    Inside({x=0,y=0,w=layout.width,h=layout.height},
                        layout.boxes[name]), name)
            end
            for name, hit in pairs(layout.hitboxes) do
                local visible = layout.boxes[name]
                Expect("community_hitbox_" .. width .. "_" .. name,
                    visible and hit.x == visible.x and hit.y == visible.y
                        and hit.w == visible.w and hit.h == visible.h,
                    "hit region differs from visible button")
            end
            Expect("community_status_below_controls_" .. width,
                layout.boxes.status.y >= layout.controlsBottom,
                layout.boxes.status.y .. "/" .. layout.controlsBottom)
            Expect("community_body_below_status_" .. width,
                layout.boxes.list.y >= layout.boxes.status.y
                    + layout.boxes.status.h,
                layout.boxes.list.y .. "/" .. layout.boxes.status.y)
            Expect("community_fixed_page_contract_" .. width,
                layout.pageSize == 20 and layout.cardPoolLimit > 0
                    and layout.cardPoolLimit < 20,
                layout.pageSize .. "/" .. layout.cardPoolLimit)
            if state.empty then
                Expect("empty_state_inside_list_" .. width,
                    Inside(layout.boxes.list, layout.boxes.emptyState),
                    "empty explanation escaped list viewport")
            end
        end
    end
end

Layout.ResetCache()
local before = Layout.Stats()
local cachedA = Layout.Community({width=1040,height=640,fontScale=1.5,
    uiScale=0.8,revision=7,labels=longLabels,results=20})
local cachedB = Layout.Community({width=1040,height=640,fontScale=1.5,
    uiScale=0.8,revision=7,labels=longLabels,results=20})
local cachedC = Layout.Community({width=1040,height=640,fontScale=1.5,
    uiScale=0.8,revision=8,labels=longLabels,results=20})
local after = Layout.Stats()
Expect("revision_keyed_layout_cache",
    cachedA == cachedB and cachedA ~= cachedC
        and after.computations == before.computations + 2
        and after.hits == before.hits + 1,
    string.format("compute=%d hits=%d",after.computations,after.hits))

local title = "Caf\195\169 \230\157\177\228\186\172 " .. string.rep("Long Build ", 20)
local shortened = Layout.Truncate(title, 36)
Expect("utf8_safe_truncation",
    #shortened < #title and shortened:sub(-3) == "..."
        and not shortened:find("[\128-\191]$"), shortened)
Expect("long_dps_column_bounded",
    cachedA.card.titleWidth > 0 and cachedA.card.dpsWidth > 0
        and cachedA.card.titleWidth + cachedA.card.dpsWidth
            + cachedA.card.gap <= cachedA.card.contentWidth,
    "card title/DPS columns exceeded row width")

for revision=1,100 do
    Layout.Community({width=1040,height=640,fontScale=1,uiScale=1,
        revision=revision,labels=longLabels,results=20})
end
local bounded = Layout.Stats()
Expect("layout_cache_is_bounded",
    bounded.communityEntries <= bounded.maxCacheEntries
        and bounded.evictions > 0,
    string.format("entries=%d max=%d evictions=%d",
        bounded.communityEntries,bounded.maxCacheEntries,bounded.evictions))

if #failures > 0 then
    error(string.format("Stage 32 responsive layout failed %d/%d checks:\n%s",
        #failures, checks, table.concat(failures, "\n")))
end

print(string.format(
    "Stage 32 responsive layout matrix -- OK (%d checks; panel=%d community=%d)",
    checks, panelCases, communityCases))
