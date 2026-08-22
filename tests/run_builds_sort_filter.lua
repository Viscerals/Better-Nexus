-- Community Builds defaults to the current class and qualified rows, while
-- additive opt-outs expose complete synchronized storage without replacing
-- unrelated persisted settings.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
dofile("data/DefaultProfile.lua"); dofile("logic/Model.lua"); dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua"); dofile("logic/Relay.lua"); dofile("logic/Policy.lua"); dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/Readout.lua"); dofile("ui/Panel.lua")
Nexus.LogViewer = {Init=function() end,Show=function() end,Toggle=function() end}
dofile("ui/CommunityBuilds.lua")
dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/WishlistModel.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")

NexusDB = {}
H.playerLevel = 80
H.wishlist = {name="W",class="ROGUE",echoes={
    {spellId=200100,quality=3,stacks=1},
}}
UnitName = function() return "Alice" end
local classToken = "ROGUE"
UnitClass = function()
    if not classToken then return nil, nil end
    return "Rogue", classToken
end
time = function() return 1000 end

H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("SPELLS_CHANGED"); H.FireEvent("PLAYER_ENTERING_WORLD"); H.Advance(2)

local CB = Nexus.CommunityBuilds
CB.Init(Nexus.GameAdapter, Nexus.Model)
NexusDB.communityBuilds = {
    z1={id="z1",title="Rogue Build",class="ROGUE",fingerprint="1x1",
        echoes={{spellId=1,quality=3,stacks=1}},postedAt=100,lastModified=100,
        isMine=true,author="Alice",ownerKey="alice@unknown",description=""},
    z2={id="z2",title="Mage Build",class="MAGE",fingerprint="2x1",
        echoes={{spellId=2,quality=3,stacks=1}},postedAt=200,lastModified=200,
        author="Bob",ownerKey="bob@unknown",description=""},
    z3={id="z3",title="Warrior Build",class="WARRIOR",fingerprint="3x1",
        echoes={{spellId=3,quality=3,stacks=1}},postedAt=300,lastModified=300,
        author="Carol",ownerKey="carol@unknown",description=""},
}
Nexus.DpsCapture = Nexus.DpsCapture or {}
Nexus.DpsCapture.GetCommunityEligibility = function()
    return {
        ["1x1"]={dummy=100,lk=200,best=200,average=150,count=2},
        ["2x1"]={dummy=300,lk=400,best=400,average=350,count=2},
        ["3x1"]={dummy=500,lk=600,best=600,average=550,count=2},
    }
end

NexusDB.buildFilters = {
    scope="all",sortMode="recent",classFilter="MAGE",futureFilter="keep",
}
CB.Show()
local frame = assert(_G.NexusCommunityBuildsFrame)
local onUpdate = assert(frame:GetScript("OnUpdate"))
for _=1,20 do
    if CB.VirtualStats().results == 1 then break end
    onUpdate(frame,0.05)
end
local initial = CB.VirtualStats()
assert(initial.results == 1
    and NexusDB.buildFilters.classFilter == "ROGUE"
    and NexusDB.buildFilters.currentClassOnly == true
    and NexusDB.buildFilters.qualifiedOnly == true
    and NexusDB.buildFilters.page == 1
    and NexusDB.buildFilters.futureFilter == "keep",
    string.format("stale class filter exposed another class or replaced unrelated settings: results=%s class=%s future=%s",
        tostring(initial.results),tostring(NexusDB.buildFilters.classFilter),
        tostring(NexusDB.buildFilters.futureFilter)))

local classButton = assert(frame._classDropBtn)
local qualifiedButton = assert(frame._qualifiedBtn)
local resultText = assert(frame._resultText)
local pageText = assert(frame._pageText)
assert(frame._prevPageBtn and frame._nextPageBtn
    and resultText:GetText():find("Showing 1-1 of 1", 1, true)
    and pageText:GetText() == "1 / 1",
    "Community pagination controls or truthful result range are missing")
local classPanel = assert(_G.NexusClassDropPanel)
assert(type(classButton:GetScript("OnClick")) == "function"
    and not classPanel:IsShown()
    and classButton:GetText() == "Current Class Only"
    and qualifiedButton:GetText() == "Qualified Only",
    "Community did not expose truthful default filter controls")

classButton:GetScript("OnClick")(classButton)
for _=1,20 do
    if CB.VirtualStats().results == 3 then break end
    onUpdate(frame,0.05)
end
assert(CB.VirtualStats().results == 3
    and NexusDB.buildFilters.currentClassOnly == false
    and NexusDB.buildFilters.futureFilter == "keep"
    and classButton:GetText() == "All Classes",
    "All Classes did not expose the complete qualified catalog")

qualifiedButton:GetScript("OnClick")(qualifiedButton)
assert(NexusDB.buildFilters.qualifiedOnly == false
    and qualifiedButton:GetText() == "All Shared",
    "All Shared did not opt out of qualification")
qualifiedButton:GetScript("OnClick")(qualifiedButton)
assert(NexusDB.buildFilters.qualifiedOnly == true
    and qualifiedButton:GetText() == "Qualified Only",
    "Qualified Only did not restore the default restriction")

-- Restore the default before exercising login-transition fail-closed behavior.
classButton:GetScript("OnClick")(classButton)
for _=1,20 do
    if CB.VirtualStats().results == 1 then break end
    onUpdate(frame,0.05)
end

-- An unavailable class fails closed and retains persisted preferences until a
-- valid token recovers. Recovery republishes the correct class exactly once.
classToken = nil
CB.Refresh()
local unavailable = CB.VirtualStats()
assert(unavailable.results == 0
    and NexusDB.buildFilters.classFilter == "ROGUE"
    and NexusDB.buildFilters.futureFilter == "keep"
    and classButton:GetText() == "Class Loading...",
    "temporarily unavailable class exposed rows or damaged preferences")

classButton:GetScript("OnClick")(classButton)
for _=1,20 do
    if CB.VirtualStats().results == 3 then break end
    onUpdate(frame,0.05)
end
assert(CB.VirtualStats().results == 3
    and NexusDB.buildFilters.currentClassOnly == false
    and classButton:GetText() == "All Classes",
    "All Classes did not remain usable while player class was unavailable")
classButton:GetScript("OnClick")(classButton)
for _=1,20 do
    if CB.VirtualStats().results == 0 then break end
    onUpdate(frame,0.05)
end
local bindsBeforeRecovery = CB.VirtualStats().dataBinds
classToken = "ROGUE"
onUpdate(frame, 8.1)
for _=1,20 do
    if CB.VirtualStats().dataBinds == bindsBeforeRecovery + 1 then break end
    onUpdate(frame,0.05)
end
local recovered = CB.VirtualStats()
assert(recovered.results == 1
    and recovered.dataBinds == bindsBeforeRecovery + 1
    and NexusDB.buildFilters.classFilter == "ROGUE",
    "current-class recovery did not publish the correct result once")
onUpdate(frame, 8.1)
assert(CB.VirtualStats().dataBinds == recovered.dataBinds,
    "unchanged recovered class published more than once")

NexusDB.communityBuilds = {}
Nexus.Revisions.Advance(Nexus.Revisions.BUILD_LIBRARY_CHANGED, {scope="empty"})
assert(pcall(CB.Refresh) and CB.VirtualStats().results == 0,
    "empty current-class library was not handled")

print("Community additive class/qualification filters and recovery -- OK")
