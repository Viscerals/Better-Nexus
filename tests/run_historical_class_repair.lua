-- Historical leaderboard/build class repair regression coverage.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
dofile("data/DefaultProfile.lua"); dofile("logic/Model.lua"); dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua"); dofile("logic/Policy.lua"); dofile("core/Store.lua")
dofile("core/GameAdapter.lua"); dofile("ui/CommunityBuilds.lua"); dofile("ui/Leaderboard.lua")

local DPS=Nexus.DpsCapture
local A=Nexus.GameAdapter
local now=70000; time=function() return now end
GetNormalizedRealmName=function() return "Ebonhold" end
UnitName=function() return "Explore" end
UnitClass=function() return "Mage", "MAGE" end

local echoes={{spellId=200100,count=1},{spellId=200101,count=1}}
NexusDB={communityBuilds={},syncTombstones={},dpsCapture={personalBest={},characterBest={dummy={},lk={}}}}
DPS.Init(A,nil)
local fp=DPS.GetEchoKey(echoes)
local id="dps-old-shaman"
NexusDB.communityBuilds[id]={id=id,title="Shaman Record Loadout",author="Explore",ownerKey="explore@ebonhold",ownerVerified=true,class="SHAMAN",echoes=echoes,autoDps=true,postedAt=1,lastModified=1}
local row={player="Explore",ownerKey="explore@ebonhold",ownerVerified=true,realm="ebonhold",class="SHAMAN",dps=24000000,duration=60,ts=100,level=80,buildId=id,echoes=echoes,fingerprint=fp}
NexusDB.dpsCapture.characterBest.dummy["explore@ebonhold"]=row
NexusDB.dpsCapture.personalBest[fp]={dummy={player="Explore",ownerKey="explore@ebonhold",ownerVerified=true,realm="ebonhold",class="SHAMAN",dps=24000000,buildId=id,fingerprint=fp}}

local board=DPS.GetDpsBoard("dummy")
assert(#board==1 and board[1].class=="MAGE", "local historical row must repair to current character class")
assert(NexusDB.communityBuilds[id].class=="MAGE", "linked automatic record page class must repair")
assert(NexusDB.communityBuilds[id].title=="Mage Record Loadout", "untouched default title must repair")

local twin={player="Explore",class="SHAMAN",dps=23000000,duration=60,
    ts=90,level=80,buildId=id,echoes=echoes,fingerprint=fp}
NexusDB.dpsCapture.characterBest.dummy.explore=twin
DPS.GetDpsBoard("dummy")
assert(twin.class=="SHAMAN" and twin.ownerKey==nil
        and twin.ownerVerified~=true,
    "realm-less same-name row was claimed as the current character")

-- Equal-DPS corrected metadata must be accepted by a peer with stale class.
UnitName=function() return "Other" end
UnitClass=function() return "Shaman", "SHAMAN" end
DPS.ReceiveRecord({v=7,f=fp,e=echoes,c="dummy",d=24000000,u=60,t=100,p="Explore",k="MAGE",o="explore@ebonhold",r="ebonhold",l=80,b=id})
assert(NexusDB.dpsCapture.characterBest.dummy["explore@ebonhold"].class=="MAGE", "peer row must retain corrected Mage class")
print("historical class repair -- OK")
