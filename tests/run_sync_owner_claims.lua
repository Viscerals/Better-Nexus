-- Owner-only DPS records and tombstones must never be suppressed by a peer
-- that knows the same state but lacks authority to retransmit it.
local H=dofile("tests/harness.lua")
local S = dofile("tests/catalog_authority_support.lua")
-- MASTER-W2-006: the compatibility hash owner loads between the catalog and
-- Sync (Nexus.toc order); Sync answers only from its retained cursor work.
dofile("core/BuildHashCache.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
local Sync,DPS=Nexus.Sync,Nexus.DpsCapture
local clock=1000; GetTime=function() return clock end; time=function() return 50000 end
local currentName="Relay"; UnitName=function() return currentName end
UnitClass=function() return "Mage","MAGE" end
GetNormalizedRealmName=function() return "Ebonhold" end
local function Pump(steps)
  for _=1,steps do
    clock=clock+0.2
    -- One catalog slice and one cache slice per turn before Sync consumes
    -- them, exactly as MainLifecycle gates its frame.
    Nexus.BuildCatalog.PumpRootAdmission()
    Nexus.BuildHashCache.Pump()
    Sync.OnUpdate(0.2)
  end
end
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
-- MASTER-RC-001 (architecture 1207-1211): Sync.Init and DpsCapture.Init no
-- longer admit the catalog root as a side effect. The same admission is
-- performed explicitly here, before the call, because the removed side
-- effect ran inside Init ahead of Init's own dependent steps. No assertion
-- or expected value in this fixture is changed.
H.AdmitCatalogV1(NexusDB)
Sync.Init(Nexus.Codec,{}); DPS.Init({},Sync); S.CompatibilityHashes(Sync); Pump(100); H.sentChatMessages={}
local fp,hash=DPS.GetEchoKey(echoes),DPS.GetEchoHash(echoes)
assert(DPS.ReceiveRecord({v=7,f=fp,h=hash,e=echoes,c="dummy",d=25000000,u=65,
  t=49000,p="Owner",k="MAGE",o="owner@ebonhold",r="ebonhold",l=80},
  "Owner-Ebonhold"))
S.PumpCatalogToIdle("owner record page admission")
local _,dpsHash=S.CompatibilityHashes(Sync)
local dpsBucket,dpsBucketHash=NonzeroBucket(dpsHash)
assert(dpsBucket,"DPS row did not occupy a reconciliation bucket")
Sync.HandleIncoming("WLRQ|Requester|0|0|dps-owner","Requester")
Sync.HandleIncoming("WLBC|RelayTwo|Requester|dps-owner|D|"..dpsBucket.."|"..dpsBucketHash,"RelayTwo")
Sync.HandleIncoming("WLRC|RelayTwo|Requester|dps-owner|0|"..dpsHash,"RelayTwo")
currentName="Owner"; H.AdmitCatalogV1(NexusDB); Pump(100)
local sawDps,sawDpsClaim=false,false
for _,m in ipairs(H.sentChatMessages) do
  sawDps=sawDps or not not m.text:find("^WLD2|")
  sawDpsClaim=sawDpsClaim or not not m.text:find("^WLBC|[^|]+|[^|]+|[^|]+|D|")
end
assert(sawDps,"non-owner claim suppressed the actual DPS owner")
assert(not sawDpsClaim,"owner-only DPS bucket emitted a suppressible claim")

-- Tombstone: a relay holds Origin's valid delete. Claims from another relay
-- cannot suppress Origin's later authoritative WLRD response.
-- Tombstone: a relayed remote delete is a deny-only reservation with zero
-- relay authority. The deletion owner's own current-session tombstone is
-- what answers a request, and another relay's claim cannot suppress it.
currentName="Relay"; clock=clock+100
NexusDB={communityBuilds={gone={id="gone",title="Gone",author="Origin",
  ownerKey="origin@ebonhold",ownerVerified=true,class="MAGE",
  echoes=echoes,postedAt=10,lastModified=10}},
  syncTombstones={},dpsCapture={}}
H.AdmitCatalogV1(NexusDB)
Sync.Init(Nexus.Codec,{}); DPS.Init({},Sync); S.CompatibilityHashes(Sync); Pump(100); H.sentChatMessages={}
Sync.HandleIncoming("WLRD|Origin|gone|20|Origin","Origin-Ebonhold")
-- MASTER-W2-008: the deny-only reservation is one retained catalog mutation;
-- settle it before the public surfaces are read.
S.PumpCatalogToIdle("relayed delete reservation")
-- Legacy-to-bundle cutover: the deny-only reservation preserves the durable raw
-- row inside the bundle, and the exact PR #68 bootstrap input stays untouched.
assert(Nexus.BuildCatalog.Get("gone") == nil
  and H.DurableBuilds().gone ~= nil
  and NexusDB.communityBuilds.gone ~= nil
  and Nexus.BuildCatalog.TombstoneState("gone").state == "OPAQUE_BLOCK_ALL",
  "relayed delete did not become a deny-only reservation")
H.sentChatMessages={}; Pump(100)
for _,m in ipairs(H.sentChatMessages) do
  assert(not m.text:find("^WLRD|"),
    "a relayed remote delete gained relay authority")
end

-- The owner's own client deletes its own build: that current-session
-- tombstone is the authoritative response a claim must not suppress.
currentName="Origin"; clock=clock+100
NexusDB={communityBuilds={mine={id="mine",title="Mine",author="Origin",
  ownerKey="origin@ebonhold",ownerVerified=true,realm="ebonhold",isMine=true,
  class="MAGE",echoes=echoes,postedAt=10,lastModified=10}},
  syncTombstones={},dpsCapture={}}
H.AdmitCatalogV1(NexusDB)
Sync.Init(Nexus.Codec,{}); DPS.Init({},Sync); S.CompatibilityHashes(Sync); Pump(100); H.sentChatMessages={}
-- MASTER-RC-019 SUPERSEDED EXPECTATION, architecture justification recorded.
-- Line 4856 and the mixed-client tombstone rows make a local row-to-tombstone
-- operation an UNCONDITIONAL zero-wire refusal with
-- REMOTE_TOMBSTONE_ORDER_UNPROVEN: it "is not a Sync message". The truthy
-- return this fixture required was the queued-to-wire result the architecture
-- forbids. The local tombstone is still committed through the central owner,
-- so every assertion about the durable tombstone below is unchanged; only the
-- wire-success half is replaced, by the strictly stronger named refusal.
local mineDeleteOk, mineDeleteWhy =
  Sync.BroadcastDelete(Nexus.BuildCatalog.Get("mine"))
if mineDeleteWhy == "ROOT_MUTATION_PENDING" then
  -- The local row-to-tombstone transaction is one retained catalog mutation;
  -- the zero-wire refusal is registered at its terminal commit.
  S.PumpCatalogToIdle("local tombstone transaction")
  local terminal = Sync.GetDeleteStatus("mine")
  mineDeleteOk = false
  mineDeleteWhy = terminal and terminal.outcome == "rejected"
    and terminal.reason or mineDeleteWhy
end
assert(mineDeleteOk == false
  and mineDeleteWhy == "REMOTE_TOMBSTONE_ORDER_UNPROVEN"
  and H.DurableTombstones()["mine"],
  "authoritative delete fixture failed")
Pump(100); H.sentChatMessages={}
local buildHash=select(1,Sync.GetCompatibilityHashes())
local buildBucket,buildBucketHash=NonzeroBucket(buildHash)
assert(buildBucket,"tombstone did not occupy a reconciliation bucket")
Sync.HandleIncoming("WLRQ|RequesterTwo|0|0|delete-owner","RequesterTwo")
Sync.HandleIncoming("WLBC|RelayTwo|RequesterTwo|delete-owner|B|"..buildBucket.."|"..buildBucketHash,"RelayTwo")
Sync.HandleIncoming("WLRC|RelayTwo|RequesterTwo|delete-owner|"..buildHash.."|0","RelayTwo")
Pump(100)
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
H.AdmitCatalogV1(NexusDB)
Sync.Init(Nexus.Codec,{}); DPS.Init({},Sync); S.CompatibilityHashes(Sync)
assert(DPS.ReceiveRecord({v=7,f=fp,h=hash,e=echoes,c="dummy",d=26000000,u=65,
  t=49001,p=accented,k="MAGE",o=accented:lower().."@ebonhold",
  r="ebonhold",l=80},accented.."-Ebonhold"),
  "exact UTF-8 DPS owner was rejected")
S.PumpCatalogToIdle("exact UTF-8 owner record page")
local projected=Nexus.ViewProjections.Leaderboard("dummy",{classFilter="ALL"})
assert(projected and projected[1] and projected[1].player==accented,
  "Leaderboard projection changed exact UTF-8 player bytes")

-- An occupied bundle is authoritative, so this row is admitted through the
-- public write seam instead of a raw legacy write plus readmission.
assert(S.CatalogMutation(function()
  return Nexus.BuildCatalog.Put({id="utf8-gone",title="Gone",
    author=accented,ownerKey=accented:lower().."@ebonhold",class="MAGE",
    ownerVerified=true,echoes=echoes,postedAt=10,lastModified=10})
end, "exact UTF-8 owned build admission"),
  "fixture could not admit the exact UTF-8 owned build")
assert(not Sync.HandleIncoming("WLRD|Valentine|utf8-gone|20|Valentine","Valentine")
  and H.DurableBuilds()["utf8-gone"],
  "ASCII lookalike gained UTF-8 tombstone authority")
-- The exact-owner delete is one retained row-to-tombstone transaction; its
-- terminal durable state is the oracle.
Sync.HandleIncoming("WLRD|"..accented.."|utf8-gone|21|"..accented,
  accented.."-Ebonhold")
S.PumpCatalogToIdle("exact UTF-8 tombstone transaction")
assert(Nexus.BuildCatalog.Get("utf8-gone") == nil
  and H.DurableBuilds()["utf8-gone"] ~= nil
  and H.DurableTombstones()["utf8-gone"].author==accented,
  "exact UTF-8 tombstone identity was changed or rejected")

print("owner-only DPS and tombstone claims cannot suppress authoritative sync -- OK")
