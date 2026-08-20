-- Stage 32.6: deterministic responsive-UI work budget at realistic scale.
-- This characterizes geometry computations, projection work, frame/card
-- allocation, and last-valid retention. Scalar runtime scale probes are
-- reported separately; they are not geometry or tree-rebuild work.
local H = dofile("tests/harness.lua")
dofile("ui/Theme.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

UnitName = function() return "BudgetMage" end
GetNormalizedRealmName = function() return "Ebonhold" end
UnitClass = function() return "Mage", "MAGE" end
UIParent:SetSize(1400,900)

local fontSize, fontSamples, uiScaleSamples = 12, 0, 0
_G.NexusFontNormal = {
    GetFont=function()
        fontSamples = fontSamples + 1
        return STANDARD_TEXT_FONT or "font",fontSize,""
    end,
}
local realEffectiveScale = UIParent.GetEffectiveScale
UIParent.GetEffectiveScale = function(self)
    uiScaleSamples = uiScaleSamples + 1
    return realEffectiveScale and realEffectiveScale(self) or 1
end

NexusDB = {
    communityBuilds={},
    buildFilters={scope="all",sortMode="title",currentClassOnly=false,
        qualifiedOnly=false,page=1,pageSize=20},
    dpsCapture={characterBest={dummy={},lk={}},personalBest={},buildBest={}},
}
for index = 1, 1000 do
    local id = string.format("layout-budget-%04d",index)
    local echoes = {}
    local fingerprintParts = {}
    for echoIndex = 1, 6 do
        local spellId = 790000+index*10+echoIndex
        echoes[echoIndex] = {
            spellId=spellId,quality=3,stacks=1,
        }
        fingerprintParts[echoIndex] = tostring(spellId).."x1"
    end
    local fingerprint = table.concat(fingerprintParts, ",")
    NexusDB.communityBuilds[id] = {
        id=id,title=string.format("Layout Budget Build %04d",index),
        author="Peer",ownerKey="peer@ebonhold",class="MAGE",
        postedAt=index,lastModified=index,fingerprint=fingerprint,
        echoes=echoes,
    }
    if index <= 250 then
        for _, category in ipairs({"dummy","lk"}) do
            NexusDB.dpsCapture.characterBest[category]
                [category.."layout"..index] = {
                player=category.."Player"..index,
                dps=(category=="dummy" and 100000 or 200000)+index,
                level=80,ts=index,duration=60,class="MAGE",
                buildId=id,fingerprint=fingerprint,
                echoes={{spellId=790000+index*10+1,count=1}},
                protocolVersion=7,
            }
        end
    end
end
Nexus.Store.Init()
dofile("core/DpsCapture.lua")
Nexus.DpsCapture.Init({}, {})

Nexus.Sync = {
    IsReceiving=function() return false end,
    LastSyncNewCount=function() return 0 end,
    ReceiveTimeLeft=function() return 0 end,
    Stats=function() return {received=0} end,
}

local createdFrames = 0
local realCreateFrame = CreateFrame
CreateFrame = function(...)
    createdFrames = createdFrames + 1
    return realCreateFrame(...)
end

dofile("ui/CommunityBuilds.lua")
local Community = Nexus.CommunityBuilds
local Projection = Nexus.ViewProjections
local Layout = Nexus.LayoutMetrics
Community.Init(nil,nil)
Community.Show()
local communityFrame = assert(NexusCommunityBuildsFrame)
local onUpdate = assert(communityFrame:GetScript("OnUpdate"))
for _ = 1, 200 do
    if Community.VirtualStats().dataBinds >= 1 then break end
    onUpdate(communityFrame,0.05)
end
assert(Community.VirtualStats().results == 20,
    "realistic Community page did not publish 20 rows")

local function Snapshot()
    local layout = Layout.Stats()
    local virtual = Community.VirtualStats()
    local projection = Projection.Stats().builds
    local work = Projection.WorkStats()
    return {
        layoutRequests=layout.requests,
        layoutComputations=layout.computations,
        layoutHits=layout.hits,panelEntries=layout.panelEntries,
        communityEntries=layout.communityEntries,
        frames=createdFrames,cards=virtual.created,
        dataBinds=virtual.dataBinds,periodicSkips=virtual.periodicSkips,
        rebuilds=projection.rebuilds,catalogWalks=projection.catalogWalks,
        dpsReads=projection.dpsReads,sorts=projection.sorts,
        defensiveCopies=projection.defensiveCopies,
        acquisitions=work.acquisitions,publications=work.publications,
        fontSamples=fontSamples,uiScaleSamples=uiScaleSamples,
        layoutRef=communityFrame._responsiveLayout,
    }
end

-- Twenty-five unchanged safety ticks may perform cheap currentness probes,
-- but cannot request geometry, rebuild/copy/sort a projection, bind rows, or
-- allocate another frame/card.
local warm = Snapshot()
for _ = 1, 25 do onUpdate(communityFrame,8.1) end
local unchanged = Snapshot()
assert(unchanged.layoutRequests == warm.layoutRequests
    and unchanged.layoutComputations == warm.layoutComputations
    and unchanged.frames == warm.frames and unchanged.cards == warm.cards
    and unchanged.dataBinds == warm.dataBinds
    and unchanged.rebuilds == warm.rebuilds
    and unchanged.catalogWalks == warm.catalogWalks
    and unchanged.dpsReads == warm.dpsReads
    and unchanged.sorts == warm.sorts
    and unchanged.defensiveCopies == warm.defensiveCopies
    and unchanged.acquisitions == warm.acquisitions
    and unchanged.publications == warm.publications
    and unchanged.layoutRef == warm.layoutRef
    and unchanged.periodicSkips == warm.periodicSkips + 25,
    "unchanged visible Community ticks repeated geometry/projection/tree work")

-- Hidden public refreshes and update ticks are completely inert.
Community.Hide()
local hidden = Snapshot()
for _ = 1, 50 do
    Community.Refresh()
    onUpdate(communityFrame,8.1)
end
local hiddenAfter = Snapshot()
assert(hiddenAfter.layoutRequests == hidden.layoutRequests
    and hiddenAfter.layoutComputations == hidden.layoutComputations
    and hiddenAfter.frames == hidden.frames and hiddenAfter.cards == hidden.cards
    and hiddenAfter.dataBinds == hidden.dataBinds
    and hiddenAfter.periodicSkips == hidden.periodicSkips
    and hiddenAfter.rebuilds == hidden.rebuilds
    and hiddenAfter.catalogWalks == hidden.catalogWalks
    and hiddenAfter.dpsReads == hidden.dpsReads
    and hiddenAfter.sorts == hidden.sorts
    and hiddenAfter.defensiveCopies == hidden.defensiveCopies
    and hiddenAfter.acquisitions == hidden.acquisitions
    and hiddenAfter.publications == hidden.publications
    and hiddenAfter.layoutRef == hidden.layoutRef,
    "hidden Community surface performed layout/projection/allocation work")

-- One runtime font revision computes exactly one new geometry snapshot. A
-- second identical refresh reuses it and the existing frame/card pool.
Community.Show()
local beforeRevision = Snapshot()
fontSize = 18
Community.Refresh()
local revised = Snapshot()
assert(revised.layoutRequests == beforeRevision.layoutRequests + 1
    and revised.layoutComputations == beforeRevision.layoutComputations + 1
    and revised.frames == beforeRevision.frames
    and revised.cards == beforeRevision.cards
    and revised.layoutRef ~= beforeRevision.layoutRef,
    "one Community layout revision was not one bounded recomputation")
Community.Refresh()
local revisedWarm = Snapshot()
assert(revisedWarm.layoutRequests == revised.layoutRequests
    and revisedWarm.layoutComputations == revised.layoutComputations
    and revisedWarm.frames == revised.frames and revisedWarm.cards == revised.cards
    and revisedWarm.layoutRef == revised.layoutRef,
    "byte-identical Community layout repeated geometry/tree allocation")

-- Panel uses a realistic 79-Echo progress model. Identical renders retain the
-- same responsive layout and construct no new frames or geometry snapshots.
NexusDB.uiShowPerformance = true
dofile("ui/Panel.lua")
Nexus.Panel.Init({ToggleAuto=function() return true end})
local missing, shed = {}, {}
for index = 1, 79 do
    missing[index] = "Missing Echo "..index
    shed[index] = "Shed Echo "..index
end
local panelModel = {
    status="budget",level=12,auto=true,
    cards={{text="First"},{text="Second"},{text="Third"}},
    recommendation="Take the safest exact Echo",
    serverStatus={tier="Torment",ash="123456789",gain="+250%",intensity=420},
    bestDps={dummy={dps=999999999},lk={dps=888888888}},
    progress={wishlistName="Layout Work Budget",owned=40,total=79,
        missing=missing,shed=shed,unknownTomes={"Tome"},
        toLock={"Lock 1","Lock 2","Lock 3","Lock 4","Lock 5","Lock 6"},
        performance={dummy={personal={dps=999999999}},
            lk={personal={dps=888888888}}}},
}
Nexus.Panel.Render(panelModel)
-- Frame construction hydrates the persisted performance-visibility setting;
-- one second render settles that cold-only signature before warm measurement.
Nexus.Panel.Render(panelModel)
local panelBefore = Nexus.Panel.RenderStats()
local panelLayoutBefore = Layout.Stats()
local panelFrames = createdFrames
local panelRef = NexusPanel._responsiveLayout
local themeBefore = Nexus.Theme.Stats()
for _ = 1, 100 do Nexus.Panel.Render(panelModel) end
local panelWarm = Nexus.Panel.RenderStats()
local panelLayoutWarm = Layout.Stats()
local themeWarm = Nexus.Theme.Stats()
assert(panelWarm.layouts == panelBefore.layouts
    and panelWarm.skipped == panelBefore.skipped + 100
    and panelLayoutWarm.requests == panelLayoutBefore.requests
    and panelLayoutWarm.computations == panelLayoutBefore.computations
    and createdFrames == panelFrames
    and NexusPanel._responsiveLayout == panelRef
    and themeWarm.treeWalks == themeBefore.treeWalks,
    string.format("identical Panel models repeated geometry/tree/theme work: layouts=%d/%d skipped=%d/%d requests=%d/%d computations=%d/%d frames=%d/%d layoutRef=%s themeWalks=%d/%d",
        panelWarm.layouts,panelBefore.layouts,panelWarm.skipped,panelBefore.skipped,
        panelLayoutWarm.requests,panelLayoutBefore.requests,
        panelLayoutWarm.computations,panelLayoutBefore.computations,
        createdFrames,panelFrames,tostring(NexusPanel._responsiveLayout==panelRef),
        themeWarm.treeWalks,themeBefore.treeWalks))

fontSize = 24
Nexus.Panel.Render(panelModel)
local panelRevised = Nexus.Panel.RenderStats()
local panelLayoutRevised = Layout.Stats()
local panelRevisionRef = NexusPanel._responsiveLayout
assert(panelRevised.layouts == panelWarm.layouts + 1
    and panelLayoutRevised.requests == panelLayoutWarm.requests + 1
    and panelLayoutRevised.computations == panelLayoutWarm.computations + 1
    and createdFrames == panelFrames and panelRevisionRef ~= panelRef,
    "one Panel layout revision was not one bounded recomputation")
Nexus.Panel.Render(panelModel)
assert(Nexus.Panel.RenderStats().layouts == panelRevised.layouts
    and Layout.Stats().requests == panelLayoutRevised.requests
    and createdFrames == panelFrames
    and NexusPanel._responsiveLayout == panelRevisionRef,
    "warm revised Panel repeated geometry/tree allocation")

-- A layout fault retains the last valid geometry/model and allocates nothing.
local originalPanel = Layout.Panel
fontSize = 15
Layout.Panel = function() error("expected Stage 32.6 layout fault") end
local faultOk = pcall(Nexus.Panel.Render,panelModel)
Layout.Panel = originalPanel
assert(faultOk and NexusPanel._responsiveLayout == panelRevisionRef
    and Nexus.Panel._lastModel.progress.wishlistName == "Layout Work Budget"
    and createdFrames == panelFrames,
    "Panel layout fault blanked last-valid state or rebuilt the tree")

local finalLayout = Layout.Stats()
assert(finalLayout.panelEntries <= finalLayout.maxCacheEntries
    and finalLayout.communityEntries <= finalLayout.maxCacheEntries
    and Community.VirtualStats().created
        <= communityFrame._responsiveLayout.cardPoolLimit,
    "responsive caches or card pool exceeded fixed bounds")
assert(fontSamples == uiScaleSamples and fontSamples <= 125,
    "constant-size runtime signature probes exceeded their scalar bound")

print(string.format(
    "Stage 32 layout work budget: builds=1000 dpsRows=500 warmTicks=25 hiddenTicks=50 panelRenders=100 layoutComputations=%d frames=%d cards=%d runtimeSamples=%d/%d -- OK",
    finalLayout.computations,createdFrames,Community.VirtualStats().created,
    fontSamples,uiScaleSamples))
