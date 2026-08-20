-- Same-key metadata enrichment must update responder claimability without a
-- collection walk or changing the ordinary DPS digest.
local H = dofile("tests/harness.lua")

time = function() return 50000 end
UnitName = function() return "Local" end
UnitLevel = function() return 80 end
UnitClass = function() return "Mage", "MAGE" end
GetNormalizedRealmName = function() return "Ebonhold" end

dofile("core/DpsCapture.lua")
local DPS = Nexus.DpsCapture
local echoes = {{spellId=940001,stacks=1}}
local fingerprint = DPS.GetEchoKey(echoes)
local hash = DPS.GetEchoHash(echoes)
local owner = "claimant@ebonhold"
local row = {
    protocolVersion=7,fingerprint=fingerprint,loadoutHash=hash,echoes=echoes,
    category="dummy",dps=250000,duration=30,ts=40000,
    player="Claimant",ownerKey=owner,realm="ebonhold",ownerVerified=true,
    level=80,
}
NexusDB = {communityBuilds={},syncTombstones={},dpsCapture={
    characterBest={dummy={[owner]=row},lk={}},personalBest={},buildBest={},
}}
DPS.Init({}, {})

local digestBefore = DPS.GetSyncHash()
local bucket = DPS.SyncBucket("dummy", "Claimant")
local claimBefore = DPS.ResponseBucketClaimInfo(bucket)
local statsBefore = DPS.HashCacheStats()
assert(claimBefore == false,
    "classless row unexpectedly claimed responder authority")

assert(DPS.ReceiveRecord({
    v=7,f=fingerprint,h=hash,e=echoes,c="dummy",d=250000,u=30,
    t=40000,p="Claimant",o=owner,r="ebonhold",l=80,k="MAGE",
}, "Claimant") == true, "same-key metadata enrichment was rejected")

local digestAfter = DPS.GetSyncHash()
local claimAfter, authority = DPS.ResponseBucketClaimInfo(bucket)
local statsAfter = DPS.HashCacheStats()
assert(digestAfter == digestBefore,
    "metadata-only enrichment changed the ordinary DPS digest")
assert(claimAfter == true and authority == owner,
    "metadata enrichment did not update responder claimability immediately")
assert(statsAfter.collectionWalks == statsBefore.collectionWalks
        and statsAfter.fullRebuilds == statsBefore.fullRebuilds
        and statsAfter.targetedInvalidations
            == statsBefore.targetedInvalidations + 1,
    "metadata enrichment rebuilt the full DPS cache instead of one bucket")

print("targeted DPS metadata claim cache -- OK")
