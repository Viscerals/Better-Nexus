-- A character may keep many exact-set personal bests locally, but only the
-- highest encounter result creates/syncs a leaderboard build.
--
-- Legacy-to-bundle cutover observation repoint (MASTER-RC-001, architecture
-- 3b5de54f). State machine line 394 gives the exact PR #68 payload locations
-- "No Package B writer | Legacy admission only | Preserved legacy input when
-- the bundle is absent. Never used as fallback after bundle occupancy", and
-- line 4849 (RAW-01) requires "one complete `authorityBundle` pointer is the
-- sole durable payload write ... legacy payload locations are read-only
-- inputs". This fixture counted the leaderboard builds the addon had just
-- created by enumerating `NexusDB.communityBuilds`; after the cutover a
-- runtime-created build never appears there by construction. The count is
-- therefore taken from the durable bundle payload through `H.DurableBuilds()`.
-- The behaviour under test is unchanged -- exactly one leaderboard build per
-- character and encounter, replaced and rebroadcast on a new best, never
-- accumulated on a weaker pull -- and the preserved legacy input is now
-- additionally asserted to keep its table identity and to take no write.
local H=dofile("tests/harness.lua")
local S = dofile("tests/catalog_authority_support.lua")
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
local legacyBuilds=NexusDB.communityBuilds
local function durableCount()
 local n=0; for _ in pairs(H.DurableBuilds()) do n=n+1 end; return n
end
local function legacyCount()
 local n=0; for _ in pairs(rawget(NexusDB,"communityBuilds") or {}) do n=n+1 end; return n
end
-- Line 394: the legacy payload location is preserved input, never a Package B
-- write target. It is seeded empty here, so it must stay the same empty table
-- for the whole run no matter how many builds the capture publishes.
local function legacyUntouched(what)
 assert(rawget(NexusDB,"communityBuilds")==legacyBuilds and legacyCount()==0,
  "Package B wrote a legacy payload location ("..what..")")
end
local sent={}
DPS.Init(Adapter,{BroadcastDpsRecord=function(r) sent[#sent+1]=r return true end,BroadcastBuild=function() return true end,BroadcastDelete=function() return true end})
local function setLoadout(ids)
 H.wishlist={name="test",echoes={}}
 H.granted={}
 for i,id in ipairs(ids) do H.wishlist.echoes[i]={spellId=id,stacks=1}; H.granted[tostring(i)]={{spellId=id,stack=1,maxStack=1}} end
end
local function pull(value)
 dps=value; DPS.OnCombatStart(); clock=clock+35; DPS.OnUpdate(10); DPS.OnCombatEnd()
 -- MASTER-W2-004: the automatic page and the superseded-page removal are
 -- retained catalog mutations; settle them before counting durable rows.
 S.PumpCatalogToIdle("character best catalog work")
end
setLoadout({200100,200102}); pull(24000000)
local count=durableCount()
assert(count==1 and #sent==1,"first character best should create and sync one build")
legacyUntouched("first character best")
setLoadout({200104,200110}); pull(22000000)
count=durableCount()
assert(count==1 and #sent==1,"weaker experimental loadout created leaderboard bloat")
legacyUntouched("weaker experimental loadout")
pull(26000000)
count=durableCount()
assert(count==1 and #sent==2,"new character best should replace the old automatic page, not accumulate it")
legacyUntouched("new character best")
local board=DPS.GetDpsBoard("dummy")
assert(#board==1 and board[1].player=="Guardmage" and board[1].dps==26000000,"board should expose only the character's winning loadout")
print("one synced winning loadout per character and encounter -- OK")
