-- Owner-only DPS records and tombstones must never be suppressed by a peer
-- that knows the same state but lacks authority to retransmit it.
local H=dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
local Sync,DPS=Nexus.Sync,Nexus.DpsCapture
local clock=1000; GetTime=function() return clock end; time=function() return 50000 end
local currentName="Relay"; UnitName=function() return currentName end
UnitClass=function() return "Mage","MAGE" end
GetNormalizedRealmName=function() return "Ebonhold" end
local function Pump(steps) for _=1,steps do clock=clock+0.2; Sync.OnUpdate(0.2) end end
local function NonzeroBucket(hash)
  local i=0
  for value in tostring(hash):gmatch("([^,]+)") do
    i=i+1; if value~="0" then return i,value end
  end
end

-- DPS: a relay knows Owner's row. Matching new/legacy claims must not stop
-- this client once it is acting as the actual owner from answering.
local echoes={{spellId=200100,stacks=1}}
NexusDB={communityBuilds={},syncTombstones={},dpsCapture={}}
Sync.Init(Nexus.Codec,{}); DPS.Init({},Sync); Pump(100); H.sentChatMessages={}
local fp,hash=DPS.GetEchoKey(echoes),DPS.GetEchoHash(echoes)
assert(DPS.ReceiveRecord({v=7,f=fp,h=hash,e=echoes,c="dummy",d=25000000,u=65,
  t=49000,p="Owner",k="MAGE",o="owner@ebonhold",r="ebonhold",l=80},"Owner"))
local _,dpsHash=Sync.GetCompatibilityHashes()
local dpsBucket,dpsBucketHash=NonzeroBucket(dpsHash)
assert(dpsBucket,"DPS row did not occupy a reconciliation bucket")
Sync.HandleIncoming("WLRQ|Requester|0|0|dps-owner","Requester")
Sync.HandleIncoming("WLBC|RelayTwo|Requester|dps-owner|D|"..dpsBucket.."|"..dpsBucketHash,"RelayTwo")
Sync.HandleIncoming("WLRC|RelayTwo|Requester|dps-owner|0|"..dpsHash,"RelayTwo")
currentName="Owner"; Pump(100)
local sawDps,sawDpsClaim=false,false
for _,m in ipairs(H.sentChatMessages) do
  sawDps=sawDps or not not m.text:find("^WLD2|")
  sawDpsClaim=sawDpsClaim or not not m.text:find("^WLBC|[^|]+|[^|]+|[^|]+|D|")
end
assert(sawDps,"non-owner claim suppressed the actual DPS owner")
assert(not sawDpsClaim,"owner-only DPS bucket emitted a suppressible claim")

-- Tombstone: a relay holds Origin's valid delete. Claims from another relay
-- cannot suppress Origin's later authoritative WLRD response.
currentName="Relay"; clock=clock+100
NexusDB={communityBuilds={gone={id="gone",title="Gone",author="Origin",
  ownerKey="origin@ebonhold",class="MAGE",echoes=echoes,postedAt=10,lastModified=10}},
  syncTombstones={},dpsCapture={}}
Sync.Init(Nexus.Codec,{}); DPS.Init({},Sync); Pump(100); H.sentChatMessages={}
Sync.HandleIncoming("WLRD|Origin|gone|20|Origin","Origin")
assert(not NexusDB.communityBuilds.gone,"authoritative delete fixture failed")
local buildHash=select(1,Sync.GetCompatibilityHashes())
local buildBucket,buildBucketHash=NonzeroBucket(buildHash)
assert(buildBucket,"tombstone did not occupy a reconciliation bucket")
Sync.HandleIncoming("WLRQ|RequesterTwo|0|0|delete-owner","RequesterTwo")
Sync.HandleIncoming("WLBC|RelayTwo|RequesterTwo|delete-owner|B|"..buildBucket.."|"..buildBucketHash,"RelayTwo")
Sync.HandleIncoming("WLRC|RelayTwo|RequesterTwo|delete-owner|"..buildHash.."|0","RelayTwo")
currentName="Origin"; Pump(100)
local sawDelete,sawDeleteClaim=false,false
for _,m in ipairs(H.sentChatMessages) do
  sawDelete=sawDelete or not not m.text:find("^WLRD|")
  sawDeleteClaim=sawDeleteClaim or not not m.text:find("^WLBC|[^|]+|[^|]+|[^|]+|B|")
end
assert(sawDelete,"non-owner claim suppressed the actual deletion owner")
assert(not sawDeleteClaim,"tombstone bucket emitted a suppressible claim")

-- Exact UTF-8 owner bytes remain authoritative through DPS, projections, and
-- tombstones; an ASCII lookalike stays a different identity.
local accented="Valentin"..string.char(0xC3,0xA9)
currentName=accented; clock=clock+100
NexusDB={communityBuilds={},syncTombstones={},dpsCapture={}}
Sync.Init(Nexus.Codec,{}); DPS.Init({},Sync)
assert(DPS.ReceiveRecord({v=7,f=fp,h=hash,e=echoes,c="dummy",d=26000000,u=65,
  t=49001,p=accented,k="MAGE",o=accented:lower().."@ebonhold",
  r="ebonhold",l=80},accented),"exact UTF-8 DPS owner was rejected")
local projected=Nexus.ViewProjections.Leaderboard("dummy",{classFilter="ALL"})
assert(projected and projected[1] and projected[1].player==accented,
  "Leaderboard projection changed exact UTF-8 player bytes")

NexusDB.communityBuilds["utf8-gone"]={id="utf8-gone",title="Gone",
  author=accented,ownerKey=accented:lower().."@ebonhold",class="MAGE",
  echoes=echoes,postedAt=10,lastModified=10}
assert(not Sync.HandleIncoming("WLRD|Valentine|utf8-gone|20|Valentine","Valentine")
  and NexusDB.communityBuilds["utf8-gone"],
  "ASCII lookalike gained UTF-8 tombstone authority")
assert(Sync.HandleIncoming("WLRD|"..accented.."|utf8-gone|21|"..accented,
  accented) and not NexusDB.communityBuilds["utf8-gone"]
  and NexusDB.syncTombstones["utf8-gone"].author==accented,
  "exact UTF-8 tombstone identity was changed or rejected")

print("owner-only DPS and tombstone claims cannot suppress authoritative sync -- OK")
