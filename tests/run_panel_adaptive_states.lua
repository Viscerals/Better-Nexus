local H = dofile("tests/harness.lua")
dofile("ui/Panel.lua")

NexusDB = {}
Nexus.DpsCapture = {
    GetPersonalBestForEchoes = function(echoes, category)
        if category == "dummy" then return { dps=24080000, duration=60 } end
    end,
    GetLeaderboardForEchoes = function(echoes, category)
        if category == "dummy" then return {{ dps=25100000, player="Othermage" }} end
        return {}
    end,
}
Nexus.Panel.Init({ ToggleAuto=function() return true end })

Nexus.Panel.Render({progress={},cards={},recommendation="",auto=true,version="2.12"})
local panel = _G.NexusPanel
assert(panel and panel:GetHeight() == 219, "setup state should match the compact 1.19.3 layout")

Nexus.Panel.Render({progress={wishlistName="Leveling",owned=25,total=79,missing={"A","B"},shed={"C"},dpsEchoes={{spellId=1,stacks=1}}},cards={},recommendation="",auto=true,version="2.12"})
assert(panel:GetHeight() == 208, "progress state height incorrect")

Nexus.Panel.Render({progress={wishlistName="Complete",owned=79,total=79,missing={},shed={},dpsEchoes={{spellId=1,stacks=1}}},cards={},recommendation="",auto=true,version="2.12"})
assert(panel:GetHeight() == 109, "completed state should collapse progress lists")

Nexus.Panel.Render({progress={wishlistName="Complete",owned=79,total=79,missing={},shed={},dpsEchoes={{spellId=1,stacks=1}},activeSlot=3},cards={{text="Echo A"}},recommendation="Take Echo A",auto=true,version="2.12"})
assert(panel:GetHeight() == 233, "live roll should expand completed HUD")

-- Enabling Performance must reserve a separate row for character Best DPS
-- above the footer in both the merged-PEH and stock-HUD layouts.
local menuItems
EasyMenu = function(items) menuItems=items end
CloseDropDownMenus = function() end
panel._menuBtn:GetScript("OnClick")(panel._menuBtn)
assert(menuItems and menuItems[3].text == "Show Performance",
    "performance menu action was unavailable")
menuItems[3].func()
local function AssertPerformanceGap(withStatus, expectedHeight)
    Nexus.Panel.Render({
        serverStatus=withStatus and {tier="HC3",ash="25.3M",gain="+320%",intensity=220} or nil,
        bestDps={dummy={dps=72230000},lk={dps=19080000}},
        progress={wishlistName="Almost Complete",owned=78,total=79,
            missing={"Echoing Tides"},shed={"Unbroken Focus (Rare)"},
            dpsEchoes={{spellId=1,stacks=1}},performance={dummy={},lk={}}},
        cards={},recommendation="",auto=true,version="2.12",
    })
    assert(panel:GetHeight() == expectedHeight,
        "performance HUD did not reserve its footer clearance")
    local perf = panel._performanceBottomText
    local best = panel._bestDpsText
    local _,_,_,_,perfY = perf:GetPoint()
    local _,_,_,_,bestY = best:GetPoint()
    local perfBottom = perfY - perf:GetHeight()
    local bestTop = -panel:GetHeight() + bestY + best:GetHeight()
    assert(perfBottom - bestTop >= 8,
        "performance row overlaps Best DPS in " .. (withStatus and "merged PEH" or "server HUD") .. " mode")
end
AssertPerformanceGap(true, 347)
AssertPerformanceGap(false, 288)
print("adaptive panel states OK")
