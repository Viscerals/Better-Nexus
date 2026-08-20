-- Unsigned relays cannot delete or redistribute another author's build.
local H=dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
local Sync=Nexus.Sync
local clock=1000; GetTime=function() return clock end; time=function() return 50000 end
UnitName=function() return "Relay" end
GetNormalizedRealmName=function() return "Ebonhold" end
NexusDB={communityBuilds={x={id="x",title="Old",author="Origin",
    ownerKey="origin@ebonhold",ownerVerified=true,class="MAGE",
    echoes={{spellId=1,stacks=1}},lastModified=10,postedAt=10,
    isMine=false}},syncTombstones={}}
Sync.Init(Nexus.Codec,{})
Sync.HandleIncoming("WLRD|PeerA||x||20||Origin","PeerA")
assert(NexusDB.communityBuilds.x,"relayed author deletion gained owner authority")
Sync.HandleIncoming("WLRD|Origin||x||20||Origin","Origin-Ebonhold")
assert(not NexusDB.communityBuilds.x,"direct author deletion was not applied")
H.sentChatMessages={}; clock=clock+100
Sync.HandleIncoming("WLRQ|NewPeer|0|0|relay-delete","NewPeer")
for i=1,100 do Sync.OnUpdate(0.2) end
local found=false
for _,m in ipairs(H.sentChatMessages) do if m.text:find("^WLRD|") and m.text:find("||x||20||Origin",1,true) then found=true end end
assert(not found,"third-party tombstone was redistributed without owner proof")
print("only direct owners can delete; third-party tombstones do not relay -- OK")
