-- Record class and per-character ownership regression coverage.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
dofile("data/DefaultProfile.lua"); dofile("logic/Model.lua"); dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua"); dofile("logic/Policy.lua"); dofile("core/Store.lua")
dofile("core/GameAdapter.lua"); dofile("ui/CommunityBuilds.lua")

local DPS=Nexus.DpsCapture
local C=Nexus.CommunityBuilds
local A=Nexus.GameAdapter
local now=50000; time=function() return now end
GetNormalizedRealmName=function() return "Ebonhold" end
UnitName=function() return "Mageowner" end
UnitClass=function() return "Mage", "MAGE" end
NexusDB={communityBuilds={},syncTombstones={},dpsCapture={}}
DPS.Init(A,nil); C.Init(A,Nexus.Model)

local mageEchoes={{spellId=200100,stacks=1},{spellId=200101,stacks=1}}
local fp=DPS.GetEchoKey(mageEchoes)
local id,b=C.EnsureDpsBuildForEchoes(mageEchoes,"dummy",{
  player="Mageowner",class="MAGE",ownerKey="mageowner@ebonhold",realm="ebonhold",
  ownerVerified=true,
  dps=24000000,duration=65,ts=now,fingerprint=fp,echoes=mageEchoes,
})
assert(id and b and b.class=="MAGE", "local Mage record must create a Mage build")
assert(type(b.fingerprintHash)=="string" and b.fingerprintHash~=""
  and b.fingerprintHash==DPS.GetEchoHash(mageEchoes)
  and b.echoCount==2 and b.loadoutAvailable==true,
  "DPS build creation must refresh every derived identity field")
assert(C.IsOwnBuild(id), "capturing character must own its record page")

-- Account-wide SavedVariables do not grant ownership to another character.
UnitName=function() return "Shamanalt" end
UnitClass=function() return "Shaman", "SHAMAN" end
assert(not C.IsOwnBuild(id), "another character on the same account must not own the Mage build")
local ok,err=C.EditBuild(id,"Fraud edit","no")
assert(not ok and err=="not your build", "cross-character edit must be rejected")

-- Receiving a Mage record while logged into a Shaman must preserve Mage.
local remoteEchoes={{spellId=200102,stacks=1},{spellId=200103,stacks=2}}
local remoteFp=DPS.GetEchoKey(remoteEchoes)
assert(DPS.ReceiveRecord({v=7,f=remoteFp,e=remoteEchoes,c="dummy",d=25000000,u=65,t=now,
  p="Remotemage",k="MAGE",o="remotemage@ebonhold",r="ebonhold",l=80}),
  "valid remote Mage record should be accepted")
local found
for _,build in pairs(NexusDB.communityBuilds) do
  if build.author=="Remotemage" then found=build break end
end
assert(found and found.class=="MAGE", "remote Mage record must not inherit local Shaman class")
assert(type(found.fingerprintHash)=="string" and found.fingerprintHash~=""
  and found.fingerprintHash==DPS.GetEchoHash(remoteEchoes)
  and found.echoCount==3 and found.loadoutAvailable==true,
  "remote DPS build completion must refresh every derived identity field")
assert(not found.isMine and not C.IsOwnBuild(found), "remote record build must remain non-editable")

-- Explicitly invalid identity/class metadata is rejected.
assert(not DPS.ReceiveRecord({v=7,f=remoteFp,e=remoteEchoes,c="dummy",d=26000000,u=65,t=now,
  p="Remotemage",k="NOTACLASS",o="remotemage@ebonhold",r="ebonhold",l=80}),
  "invalid class token must be rejected")
assert(not DPS.ReceiveRecord({v=7,f=remoteFp,e=remoteEchoes,c="dummy",d=26000000,u=65,t=now,
  p="Remotemage",k="MAGE",o="someoneelse@ebonhold",r="ebonhold",l=80}),
  "mismatched owner identity must be rejected")

-- The public receive seam also rejects mixed compact/verbose identities before
-- precedence can erase the contradictory value.
local aliasEchoes={{spellId=200109,stacks=1}}
local aliasFp=DPS.GetEchoKey(aliasEchoes)
local function AliasRecord()
  return {v=7,f=aliasFp,h=DPS.GetEchoHash(aliasEchoes),e=aliasEchoes,
    c="dummy",d=26000001,u=65,t=now+1,p="Alias",k="MAGE",
    o="alias@ebonhold",r="ebonhold",l=80,b="alias-page"}
end
for label,mutate in pairs({
  player=function(row) row.player="Other" end,
  owner=function(row) row.ownerKey="other@ebonhold" end,
  realm=function(row) row.realm="otherrealm" end,
  build=function(row) row.buildId="other-page" end,
  fingerprint=function(row) row.fingerprint="200110x1" end,
  echoes=function(row)
    row.echoes={{spellId=200109,stacks=1,locked=true}}
  end,
  inner=function(row) row.e={{spellId=200109,id=200110,stacks=1}} end,
}) do
  local row=AliasRecord(); mutate(row)
  assert(not DPS.ReceiveRecord(row,"Alias-Ebonhold"),
    "mixed compact/verbose DPS alias was accepted: "..label)
end

-- A raw true flag with contradictory persisted aliases/provenance is still
-- unverified. A later exact transport owner may promote the matching evidence,
-- but the promotion must atomically remove every contradictory field.
local promoteEchoes={{spellId=200106,stacks=1}}
local promoteFp=DPS.GetEchoKey(promoteEchoes)
NexusDB.dpsCapture.characterBest.dummy["promote@ebonhold"]={
  player="Promote",ownerKey="promote@ebonhold",ownerVerified=true,
  realm="ebonhold",o="other@ebonhold",p="Other",r="otherrealm",
  claimedOwnerKey="other@ebonhold",relaySender="Other-Realm",
  class="MAGE",dps=26500000,duration=65,ts=now+1,level=80,
  fingerprint=promoteFp,loadoutHash=DPS.GetEchoHash(promoteEchoes),
  echoes=promoteEchoes,buildId="promote-page",
}
assert(DPS.ReceiveRecord({v=7,f=promoteFp,h=DPS.GetEchoHash(promoteEchoes),
  e=promoteEchoes,c="dummy",d=26500000,u=65,t=now+1,
  p="Promote",k="MAGE",o="promote@ebonhold",r="ebonhold",l=80,
  b="promote-page"},"Promote-Ebonhold"),
  "EXPECTED RED: exact DPS owner could not repair malformed retained evidence")
local promoted=NexusDB.dpsCapture.characterBest.dummy["promote@ebonhold"]
assert(promoted and DPS.VerifiedOwnerKey(promoted)=="promote@ebonhold"
  and promoted.o==nil and promoted.p==nil and promoted.r==nil
  and promoted.claimedOwnerKey==nil and promoted.relaySender==nil,
  "exact DPS promotion retained contradictory authority aliases")

-- A hostile/accidental build ID collision must not attach an exact DPS row
-- to an unrelated loadout merely because the opaque IDs match.
local collisionEchoes={{spellId=200104,stacks=1}}
NexusDB.communityBuilds.collision={id="collision",title="Unrelated",author="Other",
  ownerKey="other@ebonhold",class="MAGE",echoes=collisionEchoes,
  fingerprint=DPS.GetEchoKey(collisionEchoes),postedAt=1,lastModified=1}
local winningEchoes={{spellId=200105,stacks=2}}
local winningFp=DPS.GetEchoKey(winningEchoes)
assert(DPS.ReceiveRecord({v=7,f=winningFp,h=DPS.GetEchoHash(winningEchoes),e=winningEchoes,
  c="dummy",d=27000000,u=65,t=now+1,p="Collisionmage",k="MAGE",
  o="collisionmage@ebonhold",r="ebonhold",l=80,b="collision"},
  "Collisionmage-Ebonhold"),
  "valid colliding DPS record was rejected")
local collisionRow
for _,row in ipairs(DPS.GetDpsBoard("dummy")) do
  if row.player=="Collisionmage" then collisionRow=row break end
end
assert(collisionRow and collisionRow.buildId~="collision"
  and NexusDB.communityBuilds[collisionRow.buildId]
  and NexusDB.communityBuilds[collisionRow.buildId].fingerprint==winningFp,
  "colliding DPS build ID was not detached to an exact safe loadout")
local unrelated=DPS.GetLeaderboard("collision","dummy")
for _,row in ipairs(unrelated) do
  assert(row.player~="Collisionmage",
    "colliding DPS row leaked onto the unrelated build leaderboard")
end

-- Reload/materialization may retain inline unverified evidence, but it must
-- not recreate a Community relationship from fingerprint or opaque ID alone.
local relationEchoes={{spellId=200108,stacks=1}}
local relationFp=DPS.GetEchoKey(relationEchoes)
assert(Nexus.BuildCatalog.Put({
  id="realm-b-relation",title="Realm B Relation",author="Twin",
  ownerKey="twin@realmb",ownerVerified=true,realm="realmb",class="MAGE",
  fingerprint=relationFp,fingerprintHash=DPS.GetEchoHash(relationEchoes),
  echoes=relationEchoes,lastModified=now+2,
}))
NexusDB.dpsCapture.characterBest.dummy["twin@realma"]={
  player="Twin",ownerKey="twin@realma",ownerVerified=true,realm="realma",
  class="MAGE",dps=27000001,duration=65,ts=now+2,level=80,
  fingerprint=relationFp,echoes=relationEchoes,buildId="realm-b-relation",
}
NexusDB.dpsCapture.characterBest.dummy["legacyrelation@realma"]={
  player="Legacyrelation",ownerKey="legacyrelation@realma",ownerVerified=false,
  realm="realma",class="MAGE",dps=27000002,duration=65,ts=now+3,level=80,
  fingerprint=relationFp,echoes=relationEchoes,
}
local materialized={}
for _,row in ipairs(DPS.GetDpsBoard("dummy")) do
  materialized[row.player]=row
end
assert(materialized.Twin and materialized.Twin.echoes
  and materialized.Twin.buildId==nil and materialized.Twin.build==nil,
  "EXPECTED RED: foreign-owner DPS relationship was restored after reload")
assert(materialized.Legacyrelation and materialized.Legacyrelation.echoes
  and materialized.Legacyrelation.buildId==nil
  and materialized.Legacyrelation.build==nil,
  "EXPECTED RED: unverified DPS evidence acquired a fingerprint relationship")

local savedRelationEchoes={{spellId=200109,stacks=1}}
local savedRelationFp=DPS.GetEchoKey(savedRelationEchoes)
assert(Nexus.BuildCatalog.Put({
  id="private-saved-relation",title="Private Saved",author="Shamanalt",
  ownerKey="shamanalt@ebonhold",ownerVerified=true,realm="ebonhold",
  importedSavedBuild=true,isMine=true,class="SHAMAN",
  fingerprint=savedRelationFp,fingerprintHash=DPS.GetEchoHash(savedRelationEchoes),
  echoes=savedRelationEchoes,lastModified=now+4,
}))
NexusDB.dpsCapture.characterBest.dummy["shamanalt@ebonhold"]={
  player="Shamanalt",ownerKey="shamanalt@ebonhold",ownerVerified=true,
  realm="ebonhold",class="SHAMAN",dps=27000003,duration=65,ts=now+4,
  level=80,fingerprint=savedRelationFp,echoes=savedRelationEchoes,
  buildId="private-saved-relation",
}
local savedMaterialized
for _,row in ipairs(DPS.GetDpsBoard("dummy")) do
  if row.player=="Shamanalt" then savedMaterialized=row break end
end
assert(savedMaterialized and savedMaterialized.echoes
  and savedMaterialized.buildId==nil and savedMaterialized.build==nil,
  "EXPECTED RED: private Saved mirror became a DPS relationship")

-- Exact evidence rehydration must remain realm-qualified even when two
-- players share the same short name and fingerprint.
local twinEchoes={{spellId=200107,stacks=1}}
local twinFp=DPS.GetEchoKey(twinEchoes)
local twinRows=NexusDB.dpsCapture.characterBest.dummy
twinRows["twin@realma"]={
  player="Twin",ownerKey="twin@realma",ownerVerified=true,realm="realma",
  class="MAGE",dps=27100000,duration=65,ts=now+2,level=80,
  fingerprint=twinFp,echoes=twinEchoes,
}
twinRows["twin@realmb"]={
  player="Twin",ownerKey="twin@realmb",ownerVerified=true,realm="realmb",
  class="MAGE",dps=27200000,duration=65,ts=now+3,level=80,
  fingerprint=twinFp,echoes=twinEchoes,
}
local realmB=DPS.GetCharacterBest("dummy","Twin","twin@realmb")
assert(realmB and realmB.ownerKey=="twin@realmb" and realmB.dps==27200000,
  "owner-qualified evidence lookup selected the wrong same-name realm")
twinRows["twin@realmb"].claimedOwnerKey="twin@realma"
assert(DPS.GetCharacterBest("dummy","Twin","twin@realmb")==nil,
  "owner-qualified evidence lookup reused authority-poisoned state")

-- Unverified evidence is visible but never short-name rehydrated across realms.
-- The exact retained evidence tuple selects RealmB even when RealmA has a
-- stronger score, and any provenance change invalidates the stale selector.
twinRows["twin@realma"].dps=29000000
twinRows["twin@realma"].ownerVerified=false
twinRows["twin@realmb"].ownerVerified=false
twinRows["twin@realmb"].claimedOwnerKey=nil
local realmBEvidence=DPS.EvidenceIdentityKey(twinRows["twin@realmb"])
local unverifiedRealmB=DPS.GetCharacterBest(
  "dummy","Twin",nil,realmBEvidence)
assert(unverifiedRealmB and unverifiedRealmB.realm=="realmb"
  and unverifiedRealmB.dps==27200000,
  "unverified evidence lookup crossed into the stronger same-name realm")
twinRows["twin@realmb"].relaySender="Relay-OtherRealm"
assert(DPS.GetCharacterBest("dummy","Twin",nil,realmBEvidence)==nil,
  "unverified evidence lookup reused changed provenance")

print("record class, ownership, and identity integrity -- OK")
