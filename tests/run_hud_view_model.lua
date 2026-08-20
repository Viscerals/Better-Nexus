-- Main-owned HUD snapshots, bounded Panel rendering, and idempotent theming.
local H=dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Relay.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/Theme.lua")
dofile("ui/Readout.lua")
dofile("ui/Panel.lua")
dofile("ui/JournalTab.lua")

local serviceReads={server=0,character=0,player=0,personal=0,leaderboard=0}
Nexus.ServerStatus={
    Init=function() end,
    IsUsingNexusHud=function() return true end,
    GetSummary=function()
        serviceReads.server=serviceReads.server+1
        return {tier="Torment",ash="12,000",gain="+25%",intensity=220}
    end,
}
Nexus.DpsCapture={
    Init=function() end,
    GetCharacterBest=function(category)
        serviceReads.character=serviceReads.character+1
        return {dps=category=="dummy" and 24000000 or 21000000,category=category}
    end,
    GetPlayerInfo=function()
        serviceReads.player=serviceReads.player+1
        return {dps=24000000,category="dummy",title="Snapshot Build"}
    end,
    GetPersonalBestForEchoes=function(_,category)
        serviceReads.personal=serviceReads.personal+1
        return {dps=category=="dummy" and 23000000 or 20000000,duration=60}
    end,
    GetLeaderboardForEchoes=function(_,category)
        serviceReads.leaderboard=serviceReads.leaderboard+1
        return {{dps=category=="dummy" and 25000000 or 22000000,player="Peer"}}
    end,
    OnUpdate=function() end,
}
Nexus.Release={
    version="1.19.4-dev",baseVersion="1.19.4",published=false,
    releasesUrl="https://github.com/Viscerals/Better-Nexus/releases",
}
NexusDB={
    settings={updateNotifications=true},
    updateNotice={version="1.20.0",observedAt=123,source="Peer"},
}
H.playerLevel=5
H.granted={}
dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")
H.FireEvent("ADDON_LOADED","Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(0.4)

local Panel=Nexus.Panel
local snapshot=Panel._lastModel
assert(snapshot and snapshot.updateNotice and snapshot.updateNotice.version=="1.20.0"
    and snapshot.serverStatus and snapshot.serverStatus.intensity==220
    and snapshot.bestDps.dummy.dps==24000000
    and snapshot.bestDps.lk.dps==21000000
    and snapshot.level==5,
    "Main did not publish the complete defensive HUD display snapshot")

local function Copy(value,seen)
    if type(value)~="table" then return value end
    seen=seen or {}; if seen[value] then return seen[value] end
    local out={}; seen[value]=out
    for key,child in pairs(value) do out[Copy(key,seen)]=Copy(child,seen) end
    return out
end
local function ReadTotal()
    local total=0
    for _,value in pairs(serviceReads) do total=total+value end
    return total
end

-- The public refresh facade reuses an equal immutable preparation while still
-- preserving its historical refresh/build accounting.
local hudStatsBefore=Nexus.HudSnapshotStats()
assert(Nexus.RefreshHudView() and Nexus.RefreshHudView(),
    "public HUD refresh facade rejected an unchanged model")
local hudStatsAfter=Nexus.HudSnapshotStats()
assert(hudStatsAfter.builds==hudStatsBefore.builds+2
    and hudStatsAfter.refreshes==hudStatsBefore.refreshes+2
    and hudStatsAfter.rebuilds==hudStatsBefore.rebuilds
    and hudStatsAfter.skipped==hudStatsBefore.skipped+2,
    "public HUD refresh facade did not reuse equal prepared inputs")

-- Rendering an already materialized model never reaches a data service.
local readsBefore=ReadTotal()
local panelBefore=Panel.RenderStats()
local themeBefore=Nexus.Theme.Stats()
for _=1,10 do Panel.Render(snapshot) end
local panelAfter=Panel.RenderStats()
local themeAfter=Nexus.Theme.Stats()
assert(ReadTotal()==readsBefore
    and panelAfter.layouts==panelBefore.layouts
    and panelAfter.skipped==panelBefore.skipped+10
    and themeAfter.treeWalks==themeBefore.treeWalks
    and themeAfter.hooks==themeBefore.hooks
    and themeAfter.textures==themeBefore.textures,
    "unchanged HUD snapshots performed service, layout, or theme work")

local statusOnly=Copy(snapshot)
statusOnly.status="status-only model"
local statusLayouts=Panel.RenderStats().layouts
Panel.Render(statusOnly)
assert(Panel.RenderStats().layouts==statusLayouts
    and Panel._lastModel.status=="status-only model",
    "status-only HUD snapshot performed layout work")

local performanceOnly=Copy(statusOnly)
performanceOnly.progress.performance={
    dummy={personal={dps=26000000},global={dps=27000000,player="Peer"}},
    lk={personal={dps=22000000},global={dps=23000000,player="Peer"}},
}
performanceOnly.bestDps={dummy={dps=26000000},lk={dps=22000000},info={dps=26000000,category="dummy"}}
local performanceBefore=Panel.RenderStats()
Panel.Render(performanceOnly)
assert(Panel.RenderStats().layouts==performanceBefore.layouts
    and Panel.RenderStats().performancePasses==performanceBefore.performancePasses+1,
    "performance-only HUD snapshot performed adaptive layout work")

local noticeOnly=Copy(performanceOnly)
noticeOnly.updateNotice=nil
local noticeBefore=Panel.RenderStats()
Panel.Render(noticeOnly)
assert(Panel.RenderStats().layouts==noticeBefore.layouts
    and Panel.RenderStats().noticePasses==noticeBefore.noticePasses+1
    and NexusPanel._menuBtn.text=="...",
    "notice-only HUD snapshot performed layout work or missed its icon")

-- These two card tables collided under delimiter-only signatures because the
-- first text value can spell the serialized second key/value pair.
local collisionA=Copy(noticeOnly)
collisionA.progress={wishlistName="Collision",owned=1,total=2,missing={},shed={},unknownTomes={},toLock={}}
collisionA.cards={{text="x;string:zz=string:y"}}
collisionA.recommendation=""
Panel.Render(collisionA)
local collisionLayouts=Panel.RenderStats().layouts
local collisionB=Copy(collisionA)
collisionB.cards={{text="x",zz="y"}}
Panel.Render(collisionB)
assert(Panel.RenderStats().layouts==collisionLayouts+1,
    "length-unsafe model signatures collapsed distinct card content")

-- Panel retains its own copy; caller mutation cannot alter tooltips or refreshes.
local caller=Copy(noticeOnly)
caller.progress.missing={"Original"}
Panel.Render(caller)
caller.progress.missing[1]="mutated"
assert(Panel._lastModel.progress.missing[1]=="Original",
    "Panel retained a caller-owned HUD model table")

-- Custom virtual rows receive the theme once without hook/texture growth.
local virtual=CreateFrame("Button",nil,UIParent)
local control=CreateFrame("Button",nil,virtual)
local controlText=control:CreateFontString(nil,"OVERLAY","GameFontHighlight")
control.GetObjectType=function() return "Button" end
control.GetFontString=function() return controlText end
control.GetHeight=function() return 22 end
local dynamicBefore=Nexus.Theme.Stats()
Nexus.Theme.StyleVirtualRow(virtual,{control})
Nexus.Theme.StyleVirtualRow(virtual,{control})
local dynamicAfter=Nexus.Theme.Stats()
assert(dynamicAfter.virtualRows==dynamicBefore.virtualRows+1
    and dynamicAfter.buttonsStyled==dynamicBefore.buttonsStyled+1
    and dynamicAfter.hooks==dynamicBefore.hooks+4
    and dynamicAfter.textures==dynamicBefore.textures+1,
    "virtual-row child theming was not one-shot and bounded")

assert(Nexus.RecomputeStats().polls>=2,
    "HUD snapshot work changed the direct 0.2-second safety heartbeat")
print("immutable HUD snapshots and idempotent bounded rendering -- OK")
