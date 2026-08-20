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
assert(panel:GetHeight() == 138,
    "completed state should collapse progress lists without overlapping its footer")

Nexus.Panel.Render({progress={wishlistName="Complete",owned=79,total=79,missing={},shed={},dpsEchoes={{spellId=1,stacks=1}},activeSlot=3},cards={{text="Echo A"}},recommendation="Take Echo A",auto=true,version="2.12"})
assert(panel:GetHeight() == 248,
    "live roll should expand completed HUD without overlapping its footer")
print("adaptive panel states OK")
