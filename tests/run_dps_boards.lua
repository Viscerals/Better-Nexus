-- Public boards: one highest winning loadout per character, ranked separately by encounter.
local H=dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
dofile("data/DefaultProfile.lua"); dofile("logic/Model.lua"); dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua"); dofile("logic/Policy.lua"); dofile("core/Store.lua")
dofile("core/GameAdapter.lua"); dofile("ui/CommunityBuilds.lua")
local DPS=Nexus.DpsCapture
UnitName=function(unit) return unit=="player" and "Viewer" or nil end
UnitClass=function() return "Mage","MAGE" end
NexusDB={communityBuilds={},syncTombstones={},dpsCapture={}}
DPS.Init({}, {BroadcastBuild=function() return true end})
local a={{spellId=200001,stacks=2},{spellId=200002,stacks=1}}
local b={{spellId=200010,stacks=1},{spellId=200011,stacks=3}}
local fa,fb=DPS.GetEchoKey(a),DPS.GetEchoKey(b)
assert(DPS.ReceiveRecord({v=4,f=fa,e=a,c="dummy",d=24000000,u=65,t=100,p="Alpha",k="MAGE",l=80}),"dummy A rejected")
assert(DPS.ReceiveRecord({v=4,f=fb,e=b,c="dummy",d=28000000,u=65,t=101,p="Bravo",k="MAGE",l=80}),"dummy B rejected")
assert(DPS.ReceiveRecord({v=4,f=fa,e=a,c="lk",d=19000000,u=240,t=102,p="Alpha",k="MAGE",l=80}),"LK A rejected")
assert(not DPS.ReceiveRecord({v=4,f=fb,e=b,c="dummy",d=23000000,u=65,t=103,p="Alpha",k="MAGE",l=80}),"lower second loadout for the same character accepted")
local dummy=DPS.GetDpsBoard("dummy")
assert(#dummy==2,"dummy board should contain one row per character")
assert(dummy[1].player=="Bravo" and dummy[1].dps==28000000,"dummy board not DPS-ranked")
assert(dummy[1].build and dummy[1].buildId and #dummy[1].echoes==2,"board row lacks copyable exact build")
local lk=DPS.GetDpsBoard("lk")
assert(#lk==1 and lk[1].player=="Alpha" and lk[1].category=="lk","LK board not separate")
assert(DPS.GetDpsBoard("bad")[1]==nil,"invalid category should be empty")

-- Same-named characters on different realms are separate public identities.
local twinA={{spellId=200020,stacks=1}}
local twinB={{spellId=200021,stacks=1}}
assert(DPS.ReceiveRecord({v=7,f=DPS.GetEchoKey(twinA),e=twinA,c="dummy",
  d=26000000,u=65,t=104,p="Twin",k="MAGE",l=80,
  o="twin@realma",r="realma"}),"Realm A Twin rejected")
assert(DPS.ReceiveRecord({v=7,f=DPS.GetEchoKey(twinB),e=twinB,c="dummy",
  d=25000000,u=65,t=105,p="Twin",k="MAGE",l=80,
  o="twin@realmb",r="realmb"}),"Realm B Twin collided with Realm A")
local twins=0
for _,row in ipairs(DPS.GetDpsBoard("dummy")) do
  if row.player=="Twin" then twins=twins+1 end
end
assert(twins==2,"same-name cross-realm DPS rows did not remain distinct")
print("separate Dummy/Lich boards, one row per character, exact loadout, and stale rejection -- OK")
