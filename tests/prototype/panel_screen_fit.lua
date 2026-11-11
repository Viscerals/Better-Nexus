-- Offline panel viewport regression: real HUD render and anchor geometry,
-- synthetic 800x600 UI viewport and 2x owned-font model. The harness does
-- not implement native clamping or pixel drawing.
local H = dofile('tests/prototype/harness.lua')
H.Boot()
local G = dofile('tests/prototype/layout_geometry_support.lua')
G.UseFont(G.MODELS.double)
UIParent:SetSize(800, 600)
NexusDB.uiShowPerformance = true
Nexus.Panel.Show()
Nexus.CallboardStatus.GetSummary = function()
    return {observed=true, title='Callboard objective',
        lines={'Bring the tome'}, rewards={}}
end

-- Approved main panel cleanup: the panel is compact now (no fixed 104-unit
-- offer block, a 48-unit difficulty card, an inline Callboard, a one-row
-- progress), so the former model no longer outgrows the 600 px viewport at
-- 2x font. The fixture needs a layout taller than the viewport: it carries
-- three offers with long names, which wrap in full at 2x font.
local model = {
    status='ready', level=40, auto=false,
    cards={{text='Resonance of the Unbroken Covenant of the Northern Reach (Uncommon) wanted'},
        {text='Hollow Bell of the Ninefold Sealed Ember Chamber (Rare) wanted'},
        {text='Ashen Tithe of the Wandering Choir of the Forgotten Threshold (Uncommon)'}},
    recommendation='Review the next choice',
    progress={wishlistName='Synthetic plan', total=6, owned=1,
        missing={}, shed={}, toLock={}, unknownTomes={}},
    serverStatus={tier='Hardcore I', ash='500', gain='20', intensity=0.5},
}
local function Render()
    assert(Nexus.Panel.Render(model), 'synthetic HUD model renders')
    local panel = assert(NexusPanel)
    assert(panel._callboardTitle:IsShown(), 'the Callboard title is visible')
    assert(panel._responsiveLayout.boxes.callboard, 'responsive Callboard box exists')
    return panel
end

local panel = Render()
assert(panel:GetHeight() > UIParent:GetHeight(),
    'fixture: at 2x font the real HUD layout exceeds the 600px viewport')
local function Fits(tag)
    local margin = 24
    assert(panel:GetHeight() * panel:GetScale() <= UIParent:GetHeight() - margin + 0.01,
        tag .. ': panel height stays inside the viewport with margin')
    assert(panel:GetWidth() * panel:GetScale() <= UIParent:GetWidth() - margin + 0.01,
        tag .. ': panel width stays inside the viewport with margin')
end
Fits('initial render')

-- A viewport change does not alter the model or font signature. Fit must
-- still update on an otherwise settled render.
UIParent:SetSize(1200, 900)
Render()
assert(panel:GetScale() == 1, 'a larger viewport restores the native panel scale')
UIParent:SetSize(800, 600)
Render()
Fits('settled render after viewport shrinks')

-- Fixture-local counters on the real widget methods: the harness's shared
-- region methods (reached as layout_geometry_support does, no harness or
-- support file changed) count their calls on watched regions while the real
-- render runs, and every original method is put back exactly afterwards.
-- Offline operation counts only: no native frame-time or stutter claim.
local methods = G.RegionMethods()
local COUNTED = {'ClearAllPoints','SetPoint','SetSize','SetWidth','SetHeight',
    'SetText','GetStringWidth','GetStringHeight'}
local function Measure(watch, fn)
    local counts, per, saved = {}, {}, {}
    for _, name in ipairs(COUNTED) do
        counts[name] = 0
        local original = assert(rawget(methods, name), 'harness method ' .. name)
        saved[name] = original
        methods[name] = function(self, ...)
            if watch[self] then
                counts[name] = counts[name] + 1
                per[self] = per[self] or {}
                per[self][name] = (per[self][name] or 0) + 1
            end
            return original(self, ...)
        end
    end
    local ok, err = pcall(fn)
    for _, name in ipairs(COUNTED) do methods[name] = saved[name] end
    if not ok then error(err, 0) end
    return counts, per
end
local function LayoutOps(c)
    return c.ClearAllPoints + c.SetPoint + c.SetSize + c.SetWidth + c.SetHeight
end
local function MeasureOps(c) return c.GetStringWidth + c.GetStringHeight end
local function Sum(per, regions, name)
    local total = 0
    for region in pairs(regions) do
        local row = per[region]
        if row then
            if name then total = total + (row[name] or 0)
            else for _, n in pairs(row) do total = total + n end end
        end
    end
    return total
end
-- Every region and frame under root (the harness lists both).
local function Tree(root, set)
    set = set or {}
    if not root or set[root] then return set end
    set[root] = true
    for _, r in ipairs(root.regions or {}) do Tree(r, set) end
    for _, c in ipairs(root.children or {}) do Tree(c, set) end
    return set
end
-- The lines a region's real OnEnter adds to GameTooltip.
local function Tooltip(region)
    local lines, saved = {}, rawget(GameTooltip, 'AddLine')
    rawset(GameTooltip, 'AddLine', function(_, text) lines[#lines + 1] = tostring(text) end)
    local ok, err = pcall(region:GetScript('OnEnter'), region)
    rawset(GameTooltip, 'AddLine', saved)
    if not ok then error(err, 0) end
    return table.concat(lines, '\n')
end

---------------------------------------------------------------- C-03
-- A settled render (unchanged header facts and geometry) re-anchors, refits,
-- remeasures and re-sets nothing in the header or the passive hovers.
local p = assert(panel._play, 'fixture: the Play summary widgets exist')
local header, watch = {}, {}
local function Watch(set, ...)
    for i = 1, select('#', ...) do
        local region = select(i, ...)
        if region then set[region] = true end
    end
end
Watch(header, panel._contextTitle, panel._contextTitleHit, panel._contextBuild, panel._contextBuildHit,
    panel._contextWishlist, panel._contextWishlistHit, panel._switchBtn, panel._contextChange,
    panel._dragGrip, panel._closeBtn, panel._contextAutoState)
for region in pairs(header) do watch[region] = true end
local hovers = {}
Watch(hovers, panel._contextTitleHit, panel._contextBuildHit, panel._contextWishlistHit,
    p.tomesHit, p.extraHit, p.bestHit, p.orbHit, panel._callboardTitleHit, panel._callboardLineHit,
    panel._chargesHover, panel._recommendationHover, panel._progressLabelHit, panel._needLabelHit,
    panel._shedLabelHit)
for hit in pairs(hovers) do
    watch[hit] = true
    -- The text a fitted hover covers is the region its first anchor names.
    local anchor = hit.points[1] and hit.points[1][2]
    if type(anchor) == 'table' then watch[anchor] = true end
end
watch[p.orb] = true
local headerLabels = {}
Watch(headerLabels, panel._contextTitle, panel._contextBuild, panel._contextWishlist, panel._contextAutoState)
local titleHover = panel._contextTitleHit._nexusFull
assert(type(titleHover) == 'string' and titleHover ~= '', 'fixture: the title hover has its facts')
Render()
local settled, settledPer = Measure(watch, Render)
assert(LayoutOps(settled) == 0,
    'C-03: a settled render re-anchors and resizes no header widget or passive hover ('
    .. LayoutOps(settled) .. ')')
assert(MeasureOps(settled) == 0,
    'C-03: a settled render remeasures no header label or hovered text (' .. MeasureOps(settled) .. ')')
assert(Sum(settledPer, headerLabels, 'SetText') == 0, 'C-03: a settled render sets no header text again')
assert(panel._contextTitleHit._nexusFull == titleHover, 'C-03: the title hover keeps its facts')

-- Changed content on a settled render still updates: a new Orb run line
-- (its row is already laid out) is shown and its hover is refitted, while
-- the unchanged header stays untouched.
local orbPanel = assert(Nexus.OrbPanel, 'fixture: the Orb window module is loaded')
local realRunLine = orbPanel.PanelRunLine
local runShown, runFull = 'Orb run: waiting', 'Orb run: waiting for the next offer'
orbPanel.PanelRunLine = function() return runShown, runFull end
Render()
Render()
assert(p.orb:IsShown() and p.orb:GetText() == runShown and p.orbHit._nexusFull == runFull,
    'fixture: the Orb run line is shown')
runShown, runFull = 'Orb run: offer open', 'Orb run: an offer is open in the Orb window'
local changed, changedPer = Measure(watch, Render)
assert(p.orb:GetText() == runShown, 'C-03: the changed Orb run line is shown')
assert(p.orbHit._nexusFull == runFull and Tooltip(p.orbHit):find(runFull, 1, true),
    'C-03: the Orb line hover says the changed run')
assert(((changedPer[p.orbHit] or {}).ClearAllPoints or 0) > 0,
    'C-03: the changed Orb line hover is refitted to its new text')
local headerOps = 0
for region in pairs(header) do
    local row = changedPer[region] or {}
    headerOps = headerOps + (row.ClearAllPoints or 0) + (row.SetPoint or 0) + (row.SetSize or 0)
        + (row.SetWidth or 0) + (row.SetHeight or 0) + (row.SetText or 0)
end
assert(headerOps == 0, 'C-03: the unchanged header is not applied again (' .. headerOps .. ')')
orbPanel.PanelRunLine = realRunLine
Render()

-- The DPS record hovers are bound once: a performance render updates the
-- record they show, never their scripts.
-- The panel reads uiShowPerformance once, when the boot builds it, so the
-- saved key set above after the boot does not show the records. They are
-- shown here through the player's own route, the Options menu's DPS records
-- row (it changes the shown state, saves the choice and refreshes), only
-- when that row says they are hidden.
local function DpsRecordsItem()
    for _, item in ipairs(Nexus.Panel.MoreMenuItems(panel._menuBtn)) do
        if item.nexusId == 'dps_records' then return item end
    end
end
local hideRecords = Nexus.Localization.Text('panel.menu.dps_records_hide')
local dpsItem = assert(DpsRecordsItem(), 'fixture: the Options menu has the DPS records row')
local showedRecords = false
if dpsItem.text ~= hideRecords then dpsItem.func(); showedRecords = true end
assert(DpsRecordsItem().text == hideRecords, 'fixture: the DPS records are shown')
local function Scripts()
    local out = {}
    for region in pairs(Tree(panel)) do
        local enter = region.scripts and region.scripts.OnEnter
        if enter then out[region] = enter end
    end
    return out
end
model.progress.performance = {dummy={personal={dps=2345678, duration=42}}, lk={personal={dps=1234}}}
Render()
local before = Scripts()
local dummyHover
for region in pairs(before) do
    local ok, text = pcall(Tooltip, region)
    if ok and text:find('2.35M', 1, true) then dummyHover = region end
end
assert(dummyHover, 'fixture: the training dummy record hover shows the record')
model.progress.performance.dummy.personal.dps = 3456789
Render()
local rebound = 0
for region, enter in pairs(Scripts()) do
    if before[region] ~= enter then rebound = rebound + 1 end
end
assert(rebound == 0, 'C-03: a performance render rebinds no hover script (' .. rebound .. ')')
local record = Tooltip(dummyHover)
assert(record:find('3.46M', 1, true) and not record:find('2.35M', 1, true),
    'C-03: the record hover shows the new record: ' .. record)
-- Back to the display the viewport regression was written for: the same
-- row hides the records again when this fixture showed them. Shown, they
-- make the 2x-font panel taller, and a fit below native scale at the larger
-- viewport would then be the intended FitToScreen result, not a regression.
if showedRecords then
    DpsRecordsItem().func()
    assert(DpsRecordsItem().text == Nexus.Localization.Text('panel.menu.dps_records_show'),
        'fixture: the DPS records are hidden again')
    Render()
end

---------------------------------------------------------------- C-02
-- Soul Ash / multiplier / Intensity values alone take no layout pass; a
-- geometry field (the Intensity scale) still does.
local box
for _, child in ipairs(panel.children) do if child.intensityBar then box = child end end
assert(box, 'fixture: the difficulty card exists')
local bar = box.intensityBar
local cardHit
for _, child in ipairs(box.children) do
    if child ~= bar and child.scripts.OnEnter then cardHit = child end
end
assert(cardHit, 'fixture: the difficulty card hover exists')
local ashText, gainText = box.regions[2], box.regions[3]
local tree = Tree(panel)
local cardTree = Tree(box)
model.serverStatus = {tier='Hardcore I', ash='500', gain='20', intensity=120, intensityLevel=1,
    intensityMax=500, intensityThresholds={100, 200, 300, 400}}
local scaled = Measure(tree, Render)
assert(LayoutOps(scaled) > 0, 'C-02 control: a new Intensity scale takes a layout pass')
assert(bar:IsShown() and select(2, bar:GetMinMaxValues()) == 500 and bar:GetValue() == 120,
    'C-02 control: the bar shows Intensity on its scale')
Render()
local base = Measure(tree, Render)
model.serverStatus.intensity = 121
local tick, tickPer = Measure(tree, Render)
assert(LayoutOps(tick) <= LayoutOps(base) and MeasureOps(tick) <= MeasureOps(base),
    'C-02: an Intensity-only change takes no layout pass (' .. LayoutOps(tick) .. ' layout and '
    .. MeasureOps(tick) .. ' measure calls; a settled render takes ' .. LayoutOps(base) .. ' and '
    .. MeasureOps(base) .. ')')
local cardOps = 0
for region in pairs(cardTree) do
    local row = tickPer[region] or {}
    cardOps = cardOps + (row.ClearAllPoints or 0) + (row.SetPoint or 0) + (row.SetSize or 0)
        + (row.SetWidth or 0) + (row.SetHeight or 0)
end
assert(cardOps == 0, 'C-02: the card is not re-laid out for an Intensity-only change (' .. cardOps .. ')')
assert(bar:GetValue() == 121, 'C-02: the bar shows the new Intensity')
assert(Tooltip(cardHit):find('121', 1, true), 'C-02: the card hover says the new Intensity')
assert(ashText:GetText():find('500', 1, true), 'C-02: Soul Ash is unchanged')
model.serverStatus.ash, model.serverStatus.gain = '12,345', 'x2'
model.serverStatus.intensity, model.serverStatus.intensityLevel = 250, 2
local values = Measure(tree, Render)
assert(LayoutOps(values) <= LayoutOps(base) and MeasureOps(values) <= MeasureOps(base),
    'C-02: Soul Ash, multiplier, Intensity and level values take no layout pass ('
    .. LayoutOps(values) .. ' layout calls)')
assert(ashText:GetText():find('12.3k', 1, true) and gainText:GetText():find('x2', 1, true),
    'C-02: the card shows the new Soul Ash and multiplier')
local hover = Tooltip(cardHit)
assert(hover:find('12345', 1, true) and hover:find('250', 1, true),
    'C-02: the card hover says the new Soul Ash and Intensity: ' .. hover)
assert(bar:GetValue() == 250, 'C-02: the bar shows the new Intensity')
model.serverStatus.intensityMax = 600
local rescaled = Measure(tree, Render)
assert(LayoutOps(rescaled) > LayoutOps(base), 'C-02: a changed Intensity maximum still takes a layout pass')
assert(select(2, bar:GetMinMaxValues()) == 600 and bar:GetValue() == 250,
    'C-02: the bar takes its new scale')

-- The viewport regression above still holds after the cached header,
-- hovers and value-only card passes.
UIParent:SetSize(1200, 900)
Render()
assert(panel:GetScale() == 1, 'a larger viewport still restores the native panel scale (scale '
    .. tostring(panel:GetScale()) .. ', panel ' .. tostring(panel:GetWidth()) .. 'x'
    .. tostring(panel:GetHeight()) .. ')')
UIParent:SetSize(800, 600)
Render()
Fits('settled render after header, hover and card value caching')

print('PASS panel_screen_fit')
