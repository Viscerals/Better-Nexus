-- Real-frame companion to the pure Stage 32 geometry matrix. This proves the
-- HUD/browser consumers use the cached boxes and keep their visible controls,
-- card pool, and hit regions aligned.
local H = dofile("tests/harness.lua")
dofile("ui/Theme.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

UnitName = function() return "LayoutMage" end
GetNormalizedRealmName = function() return "Ebonhold" end
UnitClass = function() return "Mage", "MAGE" end
UIParent:SetSize(800,700)
_G.NexusFontNormal = {
    GetFont=function() return STANDARD_TEXT_FONT or "font",12,"" end,
}

NexusDB = {
    communityBuilds={},dpsCapture={},
    buildFilters={scope="all",sortMode="recent",currentClassOnly=false,
        qualifiedOnly=false,page=1,pageSize=20},
}
for index = 1, 25 do
    local id = string.format("layout-%02d",index)
    NexusDB.communityBuilds[id] = {
        id=id,class="MAGE",author="Peer",ownerKey="peer@ebonhold",
        title=index == 25 and ("Caf\195\169 \230\157\177\228\186\172 "
            .. string.rep("Long Build Title ",20)) or ("Build "..index),
        description="responsive fixture",postedAt=index,lastModified=index,
        fingerprint=tostring(780000+index).."x1",
        echoes={{spellId=780000+index,quality=3,stacks=1}},
    }
end
Nexus.Store.Init()
local eligibility = {}
Nexus.DpsCapture = {
    GetCommunityEligibility=function() return eligibility end,
    GetLeaderboard=function() return {} end,
    GetLeaderboardForEchoes=function() return {} end,
    GetPersonalBest=function() return nil end,
    GetDpsBoard=function() return {} end,
    IsDetailsAvailable=function() return false end,
}
for _, build in pairs(Nexus.BuildCatalog.Summaries()) do
    eligibility[build.fingerprint] = {
        dummy=999999999,lk=888888888,best=999999999,
        average=944444443.5,count=2,
    }
end

local realCreateFrame = CreateFrame
local created = {}
CreateFrame = function(...)
    local widget = realCreateFrame(...)
    created[#created+1] = widget
    return widget
end
dofile("ui/CommunityBuilds.lua")
local Community = Nexus.CommunityBuilds
Community.Init(nil,nil)
Community.Show()

local frame = assert(NexusCommunityBuildsFrame)
local onUpdate = assert(frame:GetScript("OnUpdate"))
for _=1,200 do
    if Community.VirtualStats().results==20 then break end
    onUpdate(frame,0.05)
end
local initialStats, initialView = Community.VirtualStats(),
    Community.DiagnosticSnapshot()
assert(initialStats.results==20,string.format(
    "responsive fixture did not publish its full page: results=%s pending=%s dirty=%s reason=%s catalog=%s",
    tostring(initialStats.results),tostring(initialView.projectionPending),
    tostring(initialView.projectionDirty),tostring(initialView.blockedReason),
    tostring(initialView.catalogCount)))
local Layout = assert(Nexus.LayoutMetrics)
local checks, failures = 0, {}
local function Expect(name, condition, detail)
    checks = checks + 1
    if not condition then failures[#failures+1] = name..": "..tostring(detail) end
end
local function Matches(widget, box)
    local point, relative, relativePoint, x, y = widget:GetPoint(1)
    return point == "TOPLEFT" and relative == frame
        and relativePoint == "TOPLEFT" and x == box.x and y == -box.y
        and widget:GetWidth() == box.w and widget:GetHeight() == box.h
end
local function NoOverlap(layout)
    for leftIndex=1,#layout.required do
        for rightIndex=leftIndex+1,#layout.required do
            local leftName,rightName=layout.required[leftIndex],layout.required[rightIndex]
            if Layout.Overlap(layout.boxes[leftName],layout.boxes[rightName]) then
                return false,leftName.."/"..rightName
            end
        end
    end
    return true
end

local widgets = {
    title=frame._titleText,nav=frame._navBar,
    browseLabel=frame._browseLabel,search=frame._searchBox,
    scope=frame._scopeBtn,mine=frame._myBuildsBtn,
    class=frame._classDropBtn,qualified=frame._qualifiedBtn,
    sort=frame._sortToggle,actionLabel=frame._actionLabel,
    sync=frame._syncBtn,share=frame._postBtn,
    result=frame._resultText,prev=frame._prevPageBtn,
    page=frame._pageText,next=frame._nextPageBtn,
    status=frame._syncStatusText,list=frame._listClip,
    detail=frame._detailPanel,emptyState=frame._emptyState,
}

for _, size in ipairs({12,15,18,24}) do
    _G.NexusFontNormal.GetFont = function()
        return STANDARD_TEXT_FONT or "font",size,""
    end
    Community.Refresh()
    local layout = assert(frame._responsiveLayout)
    local ok, pair = NoOverlap(layout)
    Expect("real_narrow_zero_overlap_"..size,ok,pair)
    for name, widget in pairs(widgets) do
        Expect("real_narrow_box_"..size.."_"..name,
            Matches(widget,layout.boxes[name]),name)
    end
    Expect("real_status_below_controls_"..size,
        layout.boxes.status.y >= layout.controlsBottom,
        layout.boxes.status.y.."/"..layout.controlsBottom)
end

UIParent:SetSize(1400,900)
Community.Refresh()
local wide = assert(frame._responsiveLayout)
local wideOk, widePair = NoOverlap(wide)
Expect("real_wide_zero_overlap",wideOk,widePair)
Expect("real_wide_dimensions",frame:GetWidth()==1040
    and frame:GetHeight()==wide.height,"frame/layout dimensions differ")

local longCard
for _, widget in ipairs(created) do
    if widget._fullTitle and widget._fullTitle:find("Long Build Title",1,true) then
        longCard = widget
        break
    end
end
Expect("long_title_safely_truncated",longCard
    and longCard._displayTitle ~= longCard._fullTitle
    and longCard._displayTitle:sub(-3)=="...","long title was not bounded")
Expect("fixed_visible_card_pool",Community.VirtualStats().results==20
    and Community.VirtualStats().created<20,
    Community.VirtualStats().created.." cards")

local beforeFilter = Layout.Stats()
frame._qualifiedBtn:GetScript("OnClick")(frame._qualifiedBtn)
frame._qualifiedBtn:GetScript("OnClick")(frame._qualifiedBtn)
local afterFilter = Layout.Stats()
Expect("filter_change_reuses_geometry",
    afterFilter.computations==beforeFilter.computations
        and afterFilter.requests==beforeFilter.requests,
    string.format("compute=%s/%s requests=%s/%s",
        tostring(afterFilter.computations),tostring(beforeFilter.computations),
        tostring(afterFilter.requests),tostring(beforeFilter.requests)))

frame._searchBox:SetText("no-build-can-match-this")
frame._searchBox:GetScript("OnTextChanged")(frame._searchBox)
for _=1,200 do
    onUpdate(frame,0.05)
    if Community.VirtualStats().results==0
        and not Community.VirtualStats().refreshDirty then break end
end
local emptyLayout = frame._responsiveLayout
Expect("empty_state_below_controls",frame._emptyState:IsShown()
    and Matches(frame._emptyState,emptyLayout.boxes.emptyState)
    and emptyLayout.boxes.emptyState.y >= emptyLayout.boxes.list.y,
    string.format("shown=%s results=%s dirty=%s point=%s/%s expected=%s/%s",
        tostring(frame._emptyState:IsShown()),
        tostring(Community.VirtualStats().results),
        tostring(Community.VirtualStats().refreshDirty),
        tostring(select(4,frame._emptyState:GetPoint(1))),
        tostring(select(5,frame._emptyState:GetPoint(1))),
        tostring(emptyLayout.boxes.emptyState.x),
        tostring(-emptyLayout.boxes.emptyState.y)))

NexusDB.uiShowPerformance = true
dofile("ui/Panel.lua")
Nexus.Panel.Init({ToggleAuto=function() return true end})
local panelModel = {
    status="layout",level=12,auto=true,
    cards={{text="First"},{text="Second"},{text="Third"}},
    recommendation="Take the safest exact Echo",
    serverStatus={tier="Torment",ash="123456789",gain="+250%",intensity=420},
    bestDps={dummy={dps=999999999},lk={dps=888888888}},
    progress={wishlistName="Responsive Layout",owned=20,total=79,
        missing={"A","B","C"},shed={"D","E"},
        unknownTomes={"Tome"},toLock={"Lock A","Lock B","Lock C"},
        performance={dummy={personal={dps=999999999},global={dps=1000000000}},
            lk={personal={dps=888888888},global={dps=999999999}}}},
}
for _, size in ipairs({12,15,18,24}) do
    _G.NexusFontNormal.GetFont = function()
        return STANDARD_TEXT_FONT or "font",size,""
    end
    panelModel.status = "layout-"..size
    Nexus.Panel.Render(panelModel)
    local panelLayout = assert(NexusPanel._responsiveLayout)
    local ok, pair = NoOverlap(panelLayout)
    Expect("real_panel_zero_overlap_"..size,ok,pair)
    Expect("real_panel_height_"..size,
        NexusPanel:GetHeight()==panelLayout.height,
        NexusPanel:GetHeight().."/"..panelLayout.height)
    local buttons = assert(NexusPanel._footerButtons)
    Expect("real_panel_footer_controls_"..size,
        buttons.auto:IsShown() and buttons.builds:IsShown()
            and buttons.leaderboard:IsShown(),
        "footer navigation was not visible")
end

local retainedCommunity = frame._responsiveLayout
local originalCommunityLayout = Layout.Community
Layout.Community = function() error("expected Community layout fault") end
_G.NexusFontNormal.GetFont = function()
    return STANDARD_TEXT_FONT or "font",18,""
end
local communityFaultContained = pcall(Community.Refresh)
Layout.Community = originalCommunityLayout
Expect("community_retains_last_valid_layout_on_fault",
    communityFaultContained and frame._responsiveLayout == retainedCommunity,
    "Community layout fault escaped or replaced the retained layout")

local retainedPanel = NexusPanel._responsiveLayout
local originalPanelLayout = Layout.Panel
Layout.Panel = function() error("expected Panel layout fault") end
panelModel.status = "layout-fault"
local panelFaultContained = pcall(Nexus.Panel.Render,panelModel)
Layout.Panel = originalPanelLayout
Expect("panel_retains_last_valid_layout_on_fault",
    panelFaultContained and NexusPanel._responsiveLayout == retainedPanel,
    "Panel layout fault escaped or replaced the retained layout")

if #failures>0 then
    error(string.format("Stage 32 responsive UI failed %d/%d checks:\n%s",
        #failures,checks,table.concat(failures,"\n")))
end
print(string.format(
    "Stage 32 responsive UI consumers -- OK (%d checks; narrow=4 wide=1 cards=%d)",
    checks,Community.VirtualStats().created))
