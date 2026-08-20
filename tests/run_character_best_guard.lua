-- A character may keep many exact-set personal bests locally, but only the
-- highest encounter result creates/syncs a leaderboard build.
local H=dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
dofile("data/DefaultProfile.lua"); dofile("logic/Model.lua"); dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua"); dofile("logic/Policy.lua"); dofile("core/Store.lua")
dofile("core/GameAdapter.lua"); dofile("ui/CommunityBuilds.lua")
local DPS=Nexus.DpsCapture
local Adapter=Nexus.GameAdapter
local clock,wall=1000,50000
GetTime=function() return clock end; time=function() wall=wall+1 return wall end
UnitName=function(unit) if unit=="target" then return "Training Dummy" end return "Guardmage" end
UnitLevel=function() return 80 end; UnitClass=function() return "Mage","MAGE" end
UnitExists=function(u) return u=="target" end
UnitGUID=function() return "Creature-0-1-0-1-36476-ABC" end
DETAILS_ATTRIBUTE_DAMAGE=1
local dps=24000000
Details={GetCurrentCombat=function() return {GetActor=function() return {total=dps*30,Tempo=function() return 30 end} end} end}
NexusDB={communityBuilds={},syncTombstones={},dpsCapture={}}
local sent={}
DPS.Init(Adapter,{BroadcastDpsRecord=function(r) sent[#sent+1]=r return true end,BroadcastBuild=function() return true end,BroadcastDelete=function() return true end})
local function setLoadout(ids)
 H.wishlist={name="test",echoes={}}
 H.granted={}
 for i,id in ipairs(ids) do H.wishlist.echoes[i]={spellId=id,stacks=1}; H.granted[tostring(i)]={{spellId=id,stack=1,maxStack=1}} end
end
local function pull(value)
 dps=value; DPS.OnCombatStart(); clock=clock+35; DPS.OnUpdate(10); DPS.OnCombatEnd()
end
setLoadout({200100,200102}); pull(24000000)
local count=0; for _ in pairs(NexusDB.communityBuilds) do count=count+1 end
assert(count==1 and #sent==1,"first character best should create and sync one build")
setLoadout({200104,200110}); pull(22000000)
count=0; for _ in pairs(NexusDB.communityBuilds) do count=count+1 end
assert(count==1 and #sent==1,"weaker experimental loadout created leaderboard bloat")
pull(26000000)
count=0; for _ in pairs(NexusDB.communityBuilds) do count=count+1 end
assert(count==1 and #sent==2,"new character best should replace the old automatic page, not accumulate it")
local board=DPS.GetDpsBoard("dummy")
assert(#board==1 and board[1].player=="Guardmage" and board[1].dps==26000000,"board should expose only the character's winning loadout")
print("one synced winning loadout per character and encounter -- OK")
