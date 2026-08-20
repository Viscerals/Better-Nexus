-- Optimized mesh: state hashes skip current peers and responder claims suppress duplicates.
local H=dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
local Sync,DPS=Nexus.Sync,Nexus.DpsCapture
local clock=1000; GetTime=function() return clock end; time=function() return 50000 end
local function Pump(steps) for _=1,steps do clock=clock+0.2; Sync.OnUpdate(0.2) end end
local playerName="RelayB"; UnitName=function() return playerName end; UnitLevel=function() return 80 end
local echoes={{spellId=200001,stacks=2},{spellId=200002,stacks=1}}
local build={id="manual-build",title="Real Build",description="Real description",
  author="Author",ownerKey="author@ebonhold",ownerVerified=true,
  class="MAGE",echoes=echoes,postedAt=10,lastModified=10,isMine=false}
NexusDB={communityBuilds={[build.id]=build},syncTombstones={},dpsCapture={}}
Sync.Init(Nexus.Codec,{})
DPS.Init({},Sync)
-- Let the login-time automatic sync fire and drain, then clear it before targeted claims.
Pump(100)
H.sentChatMessages={}
local fp=DPS.GetEchoKey(echoes)
assert(DPS.ReceiveRecord({v=4,f=fp,e=echoes,c="dummy",d=24000000,u=65,t=50000,p="Winner",k="MAGE",l=80,b=build.id}))
local function buildHash(builds)
  local buckets={}; for i=1,8 do buckets[i]={} end
  local function bucket(id) local h=5381; for i=1,#id do h=((h*33)+id:byte(i))%2147483648 end; return (h%8)+1 end
  for id,b in pairs(builds) do local n=bucket(id); local complete=(type(b.echoes)=="table" and #b.echoes>0) and "F" or "S"; local fp=tostring(b.fingerprintHash or b.fingerprint or "0"); buckets[n][#buckets[n]+1]=id..":"..tostring(b.lastModified or b.postedAt or 0)..":"..complete..":"..fp end
  local out={}
  for n=1,8 do table.sort(buckets[n]); local h=5381; for _,text in ipairs(buckets[n]) do for i=1,#text do h=((h*33)+text:byte(i))%2147483648 end end; out[n]=#buckets[n]>0 and string.format("%x",h) or "0" end
  return table.concat(out,",")
end
local bh=buildHash(NexusDB.communityBuilds)
local dh=DPS.GetSyncHash()
local emptyBuckets="0,0,0,0,0,0,0,0"
-- A fully current requester receives one existing-protocol state receipt and
-- no build/DPS payload. The receipt is peer proof for truthful convergence.
H.sentChatMessages={}
Sync.HandleIncoming("WLRQ|Current|"..bh.."|"..dh.."|req-current","Current")
Pump(20)
local currentClaims,currentPayloads=0,0
for _,message in ipairs(H.sentChatMessages) do
  local wire=message.text:gsub("||","|")
  if wire:find("^WLRC|[^|]+|Current|req%-current|") then
    currentClaims=currentClaims+1
  elseif wire:find("^WLRB|") or wire:find("^WLD2|") then
    currentPayloads=currentPayloads+1
  end
end
assert(currentClaims==1 and currentPayloads==0,
  "current requester did not receive one payload-free state receipt")
-- A matching per-build bucket claim suppresses only that safely relayable
-- build bucket. Legacy whole-state claims cannot suppress owner-only state.
H.sentChatMessages={}
Sync.HandleIncoming("WLRQ|NewPeer|"..emptyBuckets.."|"..emptyBuckets.."|req-claim","NewPeer")
local buildParts={}; for p in bh:gmatch("([^,]+)") do buildParts[#buildParts+1]=p end
local buildBucket,buildBucketHash
for i,value in ipairs(buildParts) do if value~="0" then buildBucket,buildBucketHash=i,value break end end
assert(buildBucket,"test build did not occupy a reconciliation bucket")
Sync.HandleIncoming("WLBC|RelayA|NewPeer|req-claim|B|"..buildBucket.."|"..buildBucketHash,"RelayA")
Pump(20)
local duplicateBuild=false
for _,m in ipairs(H.sentChatMessages) do
  duplicateBuild=duplicateBuild or not not m.text:find("^WLRB|")
end
assert(not duplicateBuild,"matching build-bucket claim did not suppress duplicate build reply")
-- A claim advertising different state must not suppress our useful contribution.
H.sentChatMessages={}
Sync.HandleIncoming("WLRQ|OtherPeer|"..emptyBuckets.."|"..emptyBuckets.."|req-different","OtherPeer")
Sync.HandleIncoming("WLRC|PartialPeer|OtherPeer|req-different|different|different","PartialPeer")
Pump(100)
local claim,buildMsg,dpsMsg=false,false,false
for _,m in ipairs(H.sentChatMessages) do
  claim=claim or not not m.text:find("^WLBC|")
  buildMsg=buildMsg or not not m.text:find("^WLRB|")
  dpsMsg=dpsMsg or not not m.text:find("^WLD2|")
end
assert(claim and buildMsg,"different-state peer incorrectly suppressed useful build contribution")
assert(not dpsMsg,"relay redistributed a verified DPS row without origin evidence")
print("mesh hashes, claims, complete builds, and DPS origin authority -- OK")
