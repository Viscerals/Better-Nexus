-- Nexus main panel drag grip: the at-least-24 x 24 UI-unit target the
-- maintainer chose on 2026-11-08 (layout and Shift-only drag preserved;
-- native checks pending) over the real ui/Panel.lua and the harness widget
-- mocks.
--
-- Scope (user choices of 2026-11-08): the four counts stay collapsed until
-- Details is expanded, offer cards stay display-only and Back keeps the
-- secondary button; only the grip target changes. This file checks the grip
-- and that the collapsed Details toggle, Shift-only drag, header slots and
-- the neighbouring controls are unchanged.
--
-- Boot: the harness's widget mocks only (CreateFrame, UIParent, GameTooltip,
-- IsShiftKeyDown). H.Boot() is NOT called: it reads Nexus.toc and loads every
-- listed module, which this test does not need. The Nexus modules the panel
-- reaches while it builds are permissive stubs; Localization answers the
-- key. NEXUS_PANEL_PATH selects the Panel file (default ui/Panel.lua) so the
-- same checks run against another copy of the file.
--
-- GRIP-01..03 are the target: they fail at the base pin (22 x 22) and pass
-- with the candidate. KEEP-01..10 are preservation: they pass at both.
-- Native hit-testing, pointer capture, the client's drag threshold and the
-- effective target at the client's scale are NOT RUN: the geometry is the
-- frames' nominal SetSize / SetPoint resolved by layout_geometry_support.
local PANEL = os.getenv('NEXUS_PANEL_PATH') or 'ui/Panel.lua'
local H = dofile('tests/prototype/harness.lua')
local G = dofile('tests/prototype/layout_geometry_support.lua')

local passes, fails = 0, 0
local function check(id, cond, text)
  if cond then passes = passes + 1 else fails = fails + 1 end
  print((cond and 'PASS ' or 'FAIL ') .. id .. ' ' .. text)
  return cond
end
local function fixture(cond, text) assert(cond, 'fixture: ' .. text) end

-- Module stubs: any capitalised field of any Nexus module is a function
-- returning nil unless given below.
Nexus = Nexus or {}
local function Stub(name, fields)
  local t = fields or {}
  setmetatable(t, {__index = function(_, k)
    if type(k) == 'string' and k:match('^[A-Z]') then return function() return nil end end
  end})
  rawset(Nexus, name, t)
  return t
end
Stub('Localization', {
  Text = function(k) return tostring(k) end,
  Format = function(k) return tostring(k) end,
  Count = function(v) return tostring(v) end,
  Resolve = function(k) return tostring(k) end,
  ActiveLanguage = function() return 'enUS' end,
})
Stub('LayoutMetrics', {
  FullTextTooltip = function(cell, row) return CreateFrame('Frame', nil, row) end,
  FontObject = function() return 'GameFontNormal' end,
  OneLineLabel = function() end,
})
Stub('UserText', {
  DestinationFields = function()
    return {{value = 'Character'}, {value = 'Build', compact = 'Build'}, {value = 'Wishlist', compact = 'Wishlist'}},
      {'Character', 'Build', 'Wishlist', 'Assignment'}
  end,
})
setmetatable(Nexus, {__index = function(_, k)
  if type(k) == 'string' and k:match('^[A-Z]') then return Stub(k) end
end})

-- GameTooltip lines, for the hover titles.
local tooltipLines = {}
GameTooltip.SetOwner = function() tooltipLines = {} end
GameTooltip.AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = tostring(text) end
GameTooltip.Show = function() end
GameTooltip.Hide = function() end

local chunk, loadErr = loadfile(PANEL)
fixture(chunk, 'Panel file loads: ' .. tostring(loadErr))
chunk()
local P = Nexus.Panel
fixture(type(P) == 'table' and type(P.HeaderSlots) == 'function', 'Nexus.Panel with HeaderSlots')
local okShow, whyShow = pcall(P.Show)
fixture(okShow, 'Panel.Show builds the frame: ' .. tostring(whyShow))
local root = NexusPanel
fixture(root and root:GetWidth() == 420, 'NexusPanel is 420 wide')
local okHeader, whyHeader = pcall(P.UpdateContextHeader, {}, false)
fixture(okHeader, 'UpdateContextHeader places the title: ' .. tostring(whyHeader))

local slots = P.HeaderSlots()
local grip = P.EnsureHeaderGrip()
local close = P.EnsureHeaderClose()
fixture(grip and grip == root._dragGrip, 'EnsureHeaderGrip returns frame._dragGrip')
fixture(close, 'EnsureHeaderClose returns the Close button')

local rootRect = G.Rect(root, root)
local gripRect = G.Rect(grip, root)
local function Size(r) return r[3] - r[1], r[4] - r[2] end
local gw, gh = Size(gripRect)
print(string.format('INFO grip rect %s slots.gripWidth=%s slots.gripHeight=%s slots.gripTop=%s titleLeft=%s',
  G.Text(gripRect), tostring(slots.gripWidth), tostring(slots.gripHeight), tostring(slots.gripTop), tostring(slots.titleLeft)))

-- Target: at least 24 x 24 UI units.
check('GRIP-01', (tonumber(slots.gripWidth) or 0) >= 24 and (tonumber(slots.gripHeight or slots.height) or 0) >= 24,
  'the header slot table offers a grip of at least 24 x 24 UI units (' .. tostring(slots.gripWidth) .. ' x ' .. tostring(slots.gripHeight or slots.height) .. ')')
check('GRIP-02', (grip:GetWidth() or 0) >= 24 and (grip:GetHeight() or 0) >= 24,
  'the grip frame is sized at least 24 x 24 (' .. tostring(grip:GetWidth()) .. ' x ' .. tostring(grip:GetHeight()) .. ')')
check('GRIP-03', gw >= 24 and gh >= 24 and G.Inside(gripRect, rootRect),
  'the grip resolved rectangle is at least 24 x 24 and inside the panel ' .. G.Text(gripRect))

-- Preservation: header slots and the title's room.
check('KEEP-01', slots.top == 7 and slots.height == 22 and slots.gap == 8 and slots.edge == 10 and slots.closeWidth == 24
  and slots.options == 42 and slots.optionsWidth == 92 and slots.auto == 142 and slots.autoWidth == 84
  and slots.reserved == 234 and slots.titleLeft == 36 and slots.gripX == 8 and (420 - slots.reserved - slots.titleLeft) == 150,
  'row height, right-hand slots, titleLeft 36 and the title 150 px at 420 px are unchanged')

-- Preservation: neighbours. The title (after UpdateContextHeader), the Build
-- line's hover, Close, Options and the Auto slot are apart from the grip.
local titleRect = G.Rect(root._contextTitle, root)
local titleHit = G.Rect(root._contextTitleHit, root)
local buildHit = G.Rect(root._contextBuildHit, root)
local closeRect = G.Rect(close, root)
local menuRect = G.Rect(root._menuBtn, root)
local autoSlot = {420 - slots.auto - slots.autoWidth, slots.top, 420 - slots.auto, slots.top + slots.height}
print(string.format('INFO title %s titleHit %s buildHit %s close %s options %s autoSlot %s',
  G.Text(titleRect), G.Text(titleHit), G.Text(buildHit), G.Text(closeRect), G.Text(menuRect), G.Text(autoSlot)))
check('KEEP-02', titleRect[1] == slots.titleLeft and G.Apart(gripRect, titleHit) and titleHit[1] - gripRect[3] > 0,
  string.format('the title starts at titleLeft and its hover is apart from the grip (gap %.0f)', titleHit[1] - gripRect[3]))
check('KEEP-03', G.Apart(gripRect, buildHit) and buildHit[2] - gripRect[4] > 0,
  string.format('the Build line hover is below and apart from the grip (gap %.0f)', buildHit[2] - gripRect[4]))
check('KEEP-04', G.Apart(gripRect, closeRect) and G.Apart(gripRect, menuRect) and G.Apart(gripRect, autoSlot)
  and closeRect[1] == 386 and closeRect[2] == 7 and closeRect[3] == 410 and closeRect[4] == 29
  and menuRect[1] == 286 and menuRect[2] == 7 and menuRect[3] == 378 and menuRect[4] == 29,
  'Close, Options and the Auto slot keep their places and none meets the grip')
check('KEEP-05', gripRect[1] >= 0 and gripRect[2] >= 0 and gripRect[2] <= slots.top and gripRect[4] >= slots.top + slots.height,
  string.format('the grip spans the header row (top %.0f, bottom %.0f; row 7 to 29)', gripRect[2], gripRect[4]))

-- Preservation: the grip is still the passive drag surface with its hover
-- and six dots inside it, and has no click of its own.
local dotsInside, dotCount = true, 0
for _, dot in ipairs(grip.dots or {}) do
  dotCount = dotCount + 1
  local pt = dot.points[1]
  local l, t = gripRect[1] + (pt and pt[4] or 0), gripRect[2] - (pt and pt[5] or 0)
  local r = {l, t, l + (dot:GetWidth() or 0), t + (dot:GetHeight() or 0)}
  if not G.Inside(r, gripRect) then dotsInside = false end
end
check('KEEP-06', grip._nexusPassiveDrag == true and grip:GetScript('OnDragStart') ~= nil and grip:GetScript('OnDragStop') ~= nil
  and grip:GetScript('OnClick') == nil and grip:GetScript('OnMouseUp') == nil and grip:GetScript('OnMouseDown') == nil
  and grip:GetScript('OnEnter') ~= nil and grip.hover ~= nil and dotCount == 6 and dotsInside,
  'passive drag surface, hover and six dots inside the grip, no click of its own')
grip:GetScript('OnEnter')(grip)
check('KEEP-07', tooltipLines[1] == 'panel.tooltip.drag_title' and tooltipLines[2] == 'panel.tooltip.drag_explained',
  'the grip hover still says Drag to move (panel.tooltip.drag_title / drag_explained)')

-- Preservation: Shift-only drag start and continued-release finish, through
-- the grip. The harness has no layout engine: StartMoving / StopMovingOrSizing
-- are counted on the root.
local starts, stops = 0, 0
root.StartMoving = function() starts = starts + 1 end
root.StopMovingOrSizing = function() stops = stops + 1 end
-- BeginPanelDrag refuses while the panel is hidden; no model is rendered
-- here, so the fixture shows the built frame itself.
if not root:IsShown() then root:Show() end
fixture(root:IsShown(), 'the panel is shown for the drag checks')
local function Shift(answer) IsShiftKeyDown = function() return answer end end
local function DragStart(button) grip:GetScript('OnDragStart')(grip, button or 'LeftButton') end
local refusedWithoutShift = true
for _, answer in ipairs({{false}, {0}, {nil}, {'held'}}) do
  Shift(answer[1])
  DragStart()
  if P._panelDrag or starts ~= 0 then refusedWithoutShift = false end
end
Shift(1)
DragStart('RightButton')
local refusedRight = P._panelDrag == nil and starts == 0
DragStart()
local startedWithShift = P._panelDrag ~= nil and P._panelDrag.origin == grip and starts == 1
check('KEEP-08', refusedWithoutShift and refusedRight and startedWithShift,
  'a grip drag starts only with Shift held (1) and the left button, from the grip (starts=' .. starts .. ')')
-- Shift released during the move: the root's OnUpdate watch finishes it.
Shift(nil)
local watch = root:GetScript('OnUpdate')
if watch then watch(root, 0.016) end
local finishedOnRelease = P._panelDrag == nil and stops == 1
-- A later move ends on the grip's own drag stop.
Shift(true)
DragStart()
grip:GetScript('OnDragStop')(grip)
check('KEEP-09', finishedOnRelease and P._panelDrag == nil and stops == 2 and starts == 2,
  'releasing Shift finishes the move; a drag stop finishes the next (starts=' .. starts .. ', stops=' .. stops .. ')')

-- Preservation: the Play summary's Details stays the collapsed toggle.
local okPlay, play = pcall(P.EnsurePlayWidgets)
fixture(okPlay and type(play) == 'table' and play.details, 'EnsurePlayWidgets builds the Details button: ' .. tostring(play))
local before = P._playDetails == true
play.details:GetScript('OnEnter')(play.details)
local collapsedTitle = tooltipLines[1]
pcall(play.details:GetScript('OnClick'), play.details)
local after = P._playDetails == true
pcall(P.TogglePlanDetails)
check('KEEP-10', before == false and collapsedTitle == 'panel.button.details_show' and after == true and P._playDetails ~= true,
  'Details is collapsed by default, its hover says Show details and its click still toggles M._playDetails')

print(string.format('RESULT passes=%d fails=%d panel=%s', passes, fails, PANEL))
if fails > 0 then
  print('FAIL panel_original_design (' .. fails .. ' check(s) failed)')
  os.exit(1)
end
print('PASS panel_original_design (grip target and preserved drag, header and Details over the harness; native hit-testing, pointer capture, drag threshold and effective scale NOT RUN)')
