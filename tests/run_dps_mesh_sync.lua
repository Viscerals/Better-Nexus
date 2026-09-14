-- Mesh audit: Sync Now responses include every held build and only its highest DPS record.
local H=dofile("tests/harness.lua")
local S=dofile("tests/catalog_authority_support.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
local Sync, DPS=Nexus.Sync, Nexus.DpsCapture
local clock=1000; GetTime=function() return clock end; time=function() return 50000 end
local currentName="Relay"
UnitName=function() return currentName end; UnitLevel=function() return 80 end
local echoes={}; for i=1,79 do echoes[i]={spellId=210000+i,stacks=1} end
local build={id="remote-record-build",title="Mesh Record",author="Origin",class="MAGE",echoes=echoes,postedAt=1,lastModified=1,isMine=false}
NexusDB={communityBuilds={[build.id]=build},syncTombstones={},dpsCapture={}}
-- MASTER-RC-001 (architecture 1207-1211): Sync.Init and DpsCapture.Init no
-- longer admit the catalog root as a side effect. The same admission is
-- performed explicitly here, before the call, because the removed side
-- effect ran inside Init ahead of Init's own dependent steps. No assertion
-- or expected value in this fixture is changed.
H.AdmitCatalogV1(NexusDB)
-- MASTER-RC-001 (architecture 1207-1211): Sync.Init and DpsCapture.Init no
-- longer admit the catalog root as a side effect. The same admission is
-- performed explicitly here, before the call, because the removed side
-- effect ran inside Init ahead of Init's own dependent steps. No assertion
-- or expected value in this fixture is changed.
H.AdmitCatalogV1(NexusDB)
Sync.Init(Nexus.Codec,{})
H.AdmitCatalogV1(NexusDB)
H.AdmitCatalogV1(NexusDB)
DPS.Init({},Sync)
local fp=DPS.GetEchoKey(echoes)
local ownerRecord = {v=3,f=fp,e=echoes,c="dummy",d=31000000,u=65,
    t=50000,p="Champion",k="MAGE",l=80,b=build.id,
    o="champion@ebonhold",r="ebonhold"}
assert(DPS.ReceiveRecord(ownerRecord,"Champion"),
    "seed record failed")
S.PumpCatalogToIdle("relay seed exact-build admission")

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
-- Simulated character switch: the normal lifecycle re-proves owner authority
-- before admitting traffic for the new character.
H.AdmitCatalogV1(NexusDB)
assert(DPS.ReceiveRecord(ownerRecord,"Champion-Ebonhold"),
    "exact owner could not promote retained realm-less evidence")
S.PumpCatalogToIdle("owner promotion exact-build admission")
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
H.AdmitCatalogV1(NexusDB)
H.AdmitCatalogV1(NexusDB)
DPS.Init({},Sync)
for _,text in ipairs(dpsMessages) do
    Sync.HandleIncoming(text,"Champion-Ebonhold")
end
S.PumpCatalogToIdle("received DPS exact-build admission")
local lb=DPS.GetLeaderboard(build.id,"dummy")
assert(#lb==1 and lb[1].dps==31000000 and lb[1].player=="Champion","DPS chunks did not reconstruct the highest record")
assert(not DPS.ReceiveRecord({v=3,f=fp,e=echoes,c="dummy",d=30000000,u=65,
    t=50001,p="Champion",k="MAGE",l=80,b=build.id,
    o="champion@ebonhold",r="ebonhold"},"Champion-Ebonhold"),
    "lower record should be rejected")
assert(DPS.GetLeaderboard(build.id,"dummy")[1].dps==31000000,"stale data overwrote the record")
print("DPS origin authority, chunking, reconstruction and stale rejection -- OK")
