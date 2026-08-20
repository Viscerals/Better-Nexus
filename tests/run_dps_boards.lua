-- Public boards: one highest winning loadout per character, ranked separately by encounter.
local H=dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
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
assert(DPS.ReceiveRecord({v=4,f=fa,e=a,c="dummy",d=24000000,u=65,t=100,p="Alpha",k="MAGE",l=80,
    o="alpha@realma",r="realma"}, "Alpha-RealmA"),"dummy A rejected")
assert(DPS.ReceiveRecord({v=4,f=fb,e=b,c="dummy",d=28000000,u=65,t=101,p="Bravo",k="MAGE",l=80,
    o="bravo@realmb",r="realmb"}, "Bravo-RealmB"),"dummy B rejected")
assert(DPS.ReceiveRecord({v=4,f=fa,e=a,c="lk",d=19000000,u=240,t=102,p="Alpha",k="MAGE",l=80,
    o="alpha@realma",r="realma"}, "Alpha-RealmA"),"LK A rejected")
assert(not DPS.ReceiveRecord({v=4,f=fb,e=b,c="dummy",d=23000000,u=65,t=103,p="Alpha",k="MAGE",l=80,
    o="alpha@realma",r="realma"}, "Alpha-RealmA"),"lower second loadout for the same character accepted")
local dummy=DPS.GetDpsBoard("dummy")
assert(#dummy==2,"dummy board should contain one row per character")
assert(dummy[1].player=="Bravo" and dummy[1].dps==28000000,"dummy board not DPS-ranked")
assert(dummy[1].build and dummy[1].buildId and #dummy[1].echoes==2
    and dummy[1].ownerVerified==true and dummy[1].ownerKey=="bravo@realmb",
    "verified board row lacks its copyable exact build")
local collisionId=dummy[1].buildId
local collisionBuild=NexusDB.communityBuilds[collisionId]
collisionBuild.fingerprint="different-current-content"
collisionBuild.echoes={{spellId=299999,stacks=1}}
local collisionRow
for _,candidate in ipairs(DPS.GetDpsBoard("dummy")) do
    if candidate.player=="Bravo" then collisionRow=candidate break end
end
assert(collisionRow and collisionRow.ownerVerified==true
    and collisionRow.build==nil and collisionRow.buildId==nil
    and collisionRow.fingerprint==fb and #collisionRow.echoes==2
    and collisionRow.lockedFingerprint=="0",
    "stale catalog relationship did not retain exact verified row evidence and fail closed")
local rawBravo
for _,candidate in pairs(NexusDB.dpsCapture.characterBest.dummy) do
    if candidate.player=="Bravo" then rawBravo=candidate break end
end
assert(rawBravo,"raw Bravo board row unavailable")
rawBravo.echoes={{spellId=200010,count=1}}
local evidenceMismatch
for _,candidate in ipairs(DPS.GetDpsBoard("dummy")) do
    if candidate.player=="Bravo" then evidenceMismatch=candidate break end
end
assert(evidenceMismatch and evidenceMismatch.recordIdentityMismatch==true
    and evidenceMismatch.fingerprint==fb and #evidenceMismatch.echoes==1,
    "record fingerprint/content mismatch did not remain visible and fail closed")
local lk=DPS.GetDpsBoard("lk")
assert(#lk==1 and lk[1].player=="Alpha" and lk[1].category=="lk","LK board not separate")
assert(DPS.GetDpsBoard("bad")[1]==nil,"invalid category should be empty")
print("separate Dummy/Lich boards, one row per character, exact loadout, and stale rejection -- OK")
