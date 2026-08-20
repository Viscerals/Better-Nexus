-- Stage 36.6 responsive-layout recovery regression.
--
-- The Stage 32 real-frame matrix deliberately injects a Community geometry
-- failure after changing the runtime font revision. It proves last-good
-- geometry is retained. This companion proves that failed revision is not
-- committed: the next ordinary refresh at the same key must retry and recover.

dofile("tests/run_stage32_responsive_layout.lua")
dofile("tests/run_stage32_responsive_ui.lua")

local Community = assert(Nexus and Nexus.CommunityBuilds,
    "Community facade unavailable after responsive UI matrix")
local Layout = assert(Nexus and Nexus.LayoutMetrics,
    "layout owner unavailable after responsive UI matrix")
local frame = assert(NexusCommunityBuildsFrame,
    "Community frame unavailable after responsive UI matrix")

local retained = assert(frame._responsiveLayout,
    "injected layout failure did not retain last-good geometry")
local original = assert(Layout.Community)
local attempts = 0
Layout.Community = function(...)
    attempts = attempts + 1
    return original(...)
end

local ok, changed = pcall(Community.Refresh)
Layout.Community = original

local failures = {}
if not ok then
    failures[#failures + 1] = "same-key recovery escaped its failure boundary"
end
if attempts ~= 1 then
    failures[#failures + 1] = "same-key recovery did not retry geometry exactly once"
end
if frame._responsiveLayout == retained then
    failures[#failures + 1] = "same-key recovery retained stale prior-revision geometry"
end
if changed ~= nil and type(changed) ~= "boolean" then
    failures[#failures + 1] = "Community refresh changed its public return shape"
end

-- Geometry application is transactional too. A late setter failure happens
-- after most boxes have already moved; it must be contained, restore every
-- exposed box to the last-good layout, and leave the new runtime key available
-- for one ordinary same-key retry.
local function Matches(widget, box)
    local point, relative, relativePoint, x, y = widget:GetPoint(1)
    return point == "TOPLEFT" and relative == frame
        and relativePoint == "TOPLEFT" and x == box.x and y == -box.y
        and widget:GetWidth() == box.w and widget:GetHeight() == box.h
end

local beforeApplyLayout = assert(frame._responsiveLayout)
local beforeApplyRuntimeKey = frame._nexusRuntimeLayoutKey
local beforeApplyLayoutKey = frame._nexusLayoutKey
local boxes = beforeApplyLayout.boxes
local exposed = {
    title=frame._titleText,nav=frame._navBar,
    search=frame._searchBox,scope=frame._scopeBtn,
    mine=frame._myBuildsBtn,class=frame._classDropBtn,
    qualified=frame._qualifiedBtn,sort=frame._sortToggle,
    list=frame._listClip,detail=frame._detailPanel,
    emptyState=frame._emptyState,
}
local lateWidget = assert(frame._detailPanel.lbLKPersonal)
local lateWidth = lateWidget:GetWidth()
local originalSetWidth = lateWidget.SetWidth
lateWidget.SetWidth = function(self, value)
    lateWidget.SetWidth = originalSetWidth
    error("expected late Community layout application fault")
end
_G.NexusFontNormal.GetFont = function()
    return STANDARD_TEXT_FONT or "font",24,""
end
local lateAttempts = 0
Layout.Community = function(...)
    lateAttempts = lateAttempts + 1
    return original(...)
end
local lateOk = pcall(Community.Refresh)
if not lateOk then
    failures[#failures + 1] = "late geometry failure escaped its boundary"
end
if frame._responsiveLayout ~= beforeApplyLayout
    or frame._nexusRuntimeLayoutKey ~= beforeApplyRuntimeKey
    or frame._nexusLayoutKey ~= beforeApplyLayoutKey then
    failures[#failures + 1] = "late geometry failure committed a poisoned key or layout"
end
for name, widget in pairs(exposed) do
    if not Matches(widget,boxes[name]) then
        failures[#failures + 1] = "late geometry rollback lost box " .. name
    end
end
if lateWidget:GetWidth() ~= lateWidth then
    failures[#failures + 1] = "late geometry rollback lost a detail width"
end

local retryOk = pcall(Community.Refresh)
local recoveredApplyLayout = frame._responsiveLayout
local warmOk = pcall(Community.Refresh)
Layout.Community = original
if not retryOk or lateAttempts ~= 2
    or recoveredApplyLayout == beforeApplyLayout then
    failures[#failures + 1] = "late geometry failure did not retry exactly once"
end
if not warmOk or frame._responsiveLayout ~= recoveredApplyLayout then
    failures[#failures + 1] = "recovered geometry was not stable on a warm refresh"
end

if #failures > 0 then
    error("EXPECTED RED [Stage 36.6 responsive layout recovery]:\n - "
        .. table.concat(failures, "\n - "))
end

print(string.format(
    "Stage 36.6 responsive layout recovery: attempts=%d late_attempts=%d last_good=yes recovered=yes -- OK",
    attempts,lateAttempts))
