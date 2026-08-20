-- Mesh audit: Sync Now responses include every held build and only its highest DPS record.
local H=dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
local Sync, DPS=Nexus.Sync, Nexus.DpsCapture
local clock=1000; GetTime=function() return clock end; time=function() return 50000 end
local currentName="Relay"
UnitName=function() return currentName end; UnitLevel=function() return 80 end
local echoes={}; for i=1,79 do echoes[i]={spellId=210000+i,stacks=1} end
local build={id="remote-record-build",title="Mesh Record",author="Origin",class="MAGE",echoes=echoes,postedAt=1,lastModified=1,isMine=false}
NexusDB={communityBuilds={[build.id]=build},syncTombstones={},dpsCapture={}}
Sync.Init(Nexus.Codec,{})
DPS.Init({},Sync)
local fp=DPS.GetEchoKey(echoes)
assert(DPS.ReceiveRecord({v=3,f=fp,e=echoes,c="dummy",d=31000000,u=65,t=50000,p="Champion",k="MAGE",l=80,b=build.id}),"seed record failed")

H.sentChatMessages={}
clock=clock+100
Sync.HandleIncoming("WLRQ|NewPeer|0","NewPeer")
for i=1,1000 do Sync.OnUpdate(0.2) end
local sawBuild,sawDps=false,false
for _,m in ipairs(H.sentChatMessages) do
    assert(#m.text<=255,"wire message exceeds WoW limit")
    if m.text:find("^WLBI|") then sawBuild=true end
    if m.text:find("^WLD2|") then sawDps=true end
end
assert(not sawBuild,"relay redistributed a remotely authored build as its own")
assert(not sawDps,"relay redistributed a verified DPS record without origin evidence")

-- The actual record owner can still publish the exact evidence.
currentName="Champion"
H.sentChatMessages={}
assert(DPS.BroadcastAllBuildBests("0")>0,"record owner did not queue its DPS evidence")
for i=1,1000 do Sync.OnUpdate(0.2) end
local dpsMessages={}
for _,m in ipairs(H.sentChatMessages) do
    if m.text:find("^WLD2|") then dpsMessages[#dpsMessages+1]=m.text end
end
assert(#dpsMessages>0,"record owner produced no DPS chunks")

-- Fresh receiver: the chunks reconstruct the exact authoritative record.
NexusDB={communityBuilds={[build.id]=build},syncTombstones={},dpsCapture={}}
DPS.Init({},Sync)
for _,text in ipairs(dpsMessages) do Sync.HandleIncoming(text,"Champion") end
local lb=DPS.GetLeaderboard(build.id,"dummy")
assert(#lb==1 and lb[1].dps==31000000 and lb[1].player=="Champion","DPS chunks did not reconstruct the highest record")
assert(not DPS.ReceiveRecord({v=3,f=fp,e=echoes,c="dummy",d=30000000,u=65,t=50001,p="Champion",k="MAGE",l=80,b=build.id}),"lower record should be rejected")
assert(DPS.GetLeaderboard(build.id,"dummy")[1].dps==31000000,"stale data overwrote the record")
print("DPS origin authority, chunking, reconstruction and stale rejection -- OK")
