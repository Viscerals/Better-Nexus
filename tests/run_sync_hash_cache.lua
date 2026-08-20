local H = dofile("tests/harness.lua")
dofile("core/Revisions.lua")
dofile("core/BuildCatalog.lua")
dofile("core/BuildHashCache.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
dofile("core/DpsCapture.lua")

local R, Catalog = Nexus.Revisions, Nexus.BuildCatalog
local Sync, DPS = Nexus.Sync, Nexus.DpsCapture
time = function() return 50000 end
UnitName = function() return "Local" end
GetNormalizedRealmName = function() return "Ebonhold" end

local baseline = {
    id="base",title="Baseline",author="Release",class="MAGE",
    postedAt=1,lastModified=1,fingerprint="200100x1",fingerprintHash="111",
    echoes={{spellId=200100,quality=3,stacks=1}},
}
Nexus.BundledBuilds = {
    schemaVersion=1,catalogVersion="hash-cache-test",sourceVersion="test",
    builds={base=baseline},
}
NexusDB = {communityBuilds={
    [1]={id=1,title="Numeric legacy ID",author="Legacy",class="MAGE",
        postedAt=1,lastModified=1,fingerprint="200110x1",fingerprintHash="110",
        echoes={{spellId=200110,quality=3,stacks=1}}},
    ["1"]={id="1",title="String legacy ID",author="Legacy",class="MAGE",
        postedAt=1,lastModified=1,fingerprint="200111x1",fingerprintHash="111a",
        echoes={{spellId=200111,quality=3,stacks=1}}},
},syncTombstones={},dpsCapture={}}
Catalog.Init(NexusDB, Nexus.BundledBuilds)
DPS.Init({}, {})
Sync.Init(Nexus.Codec, {})

local function AssertCanonical()
    local current, dps = Sync.GetCompatibilityHashes()
    local legacy = Sync.GetLegacyBuildHash()
    local canonicalCurrent, canonicalLegacy = Sync.GetCanonicalBuildHashes()
    assert(current == canonicalCurrent and legacy == canonicalLegacy,
        "cached build hash diverged from the established canonical algorithm")
    assert(dps == DPS.GetSyncHashUncached(),
        "cached DPS hash diverged from the established canonical algorithm")
    return current, legacy, dps
end

local current0, legacy0, dps0 = AssertCanonical()
local buildWarm, dpsWarm = Sync.HashCacheStats(), DPS.HashCacheStats()
assert(buildWarm.initialized and buildWarm.fullRebuilds == 1
    and buildWarm.collectionWalks == 2
    and buildWarm.deltaBucketRebuilds == 8
    and buildWarm.legacyBucketRebuilds == 8,
    "build hash cache did not warm deterministically")
assert(dpsWarm.initialized and dpsWarm.fullRebuilds == 1
    and dpsWarm.collectionWalks == 1 and dpsWarm.bucketRebuilds == 8,
    "DPS hash cache did not warm deterministically")

-- Unchanged reads use retained bucket strings: no collection walk or sort.
for _ = 1, 10 do
    assert(Sync.GetCompatibilityHashes() == current0)
    assert(Sync.GetLegacyBuildHash() == legacy0)
end
local buildHits, dpsHits = Sync.HashCacheStats(), DPS.HashCacheStats()
assert(buildHits.collectionWalks == buildWarm.collectionWalks
    and buildHits.deltaBucketRebuilds == buildWarm.deltaBucketRebuilds
    and buildHits.legacyBucketRebuilds == buildWarm.legacyBucketRebuilds
    and buildHits.hits >= buildWarm.hits + 20,
    "unchanged build hash reads walked or rebuilt buckets")
assert(dpsHits.collectionWalks == dpsWarm.collectionWalks
    and dpsHits.bucketRebuilds == dpsWarm.bucketRebuilds
    and dpsHits.hits >= dpsWarm.hits + 10,
    "unchanged DPS hash reads walked or rebuilt buckets")

-- One overlay mutation updates one entry and rebuilds only its bucket in each
-- compatibility view. No full collection snapshot is requested.
local buildBefore = Sync.HashCacheStats()
assert(Catalog.Put({
    id="peer-a",title="Peer",author="Peer",class="MAGE",
    postedAt=2,lastModified=2,fingerprint="200200x1",fingerprintHash="222",
    echoes={{spellId=200200,quality=3,stacks=1}},
}))
AssertCanonical()
local buildAfter = Sync.HashCacheStats()
assert(buildAfter.targetedInvalidations == buildBefore.targetedInvalidations + 1
    and buildAfter.fullRebuilds == buildBefore.fullRebuilds
    and buildAfter.collectionWalks == buildBefore.collectionWalks
    and buildAfter.deltaBucketRebuilds == buildBefore.deltaBucketRebuilds + 1
    and buildAfter.legacyBucketRebuilds == buildBefore.legacyBucketRebuilds + 1,
    "one build mutation did not stay inside one deterministic bucket")

local tombBefore = Sync.HashCacheStats()
assert(Catalog.SetTombstone("peer-a", {stamp=3,author="Peer"}))
AssertCanonical()
local tombAfter = Sync.HashCacheStats()
assert(tombAfter.targetedInvalidations == tombBefore.targetedInvalidations + 1
    and tombAfter.collectionWalks == tombBefore.collectionWalks
    and tombAfter.deltaBucketRebuilds == tombBefore.deltaBucketRebuilds + 1
    and tombAfter.legacyBucketRebuilds == tombBefore.legacyBucketRebuilds + 1,
    "one tombstone mutation did not stay inside one deterministic bucket")
assert(Catalog.SetTombstone("peer-a", {stamp=3,author="Peer"}))
local duplicateTomb = Sync.HashCacheStats()
assert(duplicateTomb.targetedInvalidations == tombAfter.targetedInvalidations,
    "duplicate tombstone invalidated the build hash cache")

-- Status-only activity does not touch build or DPS cache invalidation state.
local statusBuild, statusDps = Sync.HashCacheStats(), DPS.HashCacheStats()
R.Advance(R.SYNC_CHANGED, {reason="status-only"})
Sync.GetCompatibilityHashes(); Sync.GetLegacyBuildHash()
assert(Sync.HashCacheStats().targetedInvalidations == statusBuild.targetedInvalidations
    and Sync.HashCacheStats().fullInvalidations == statusBuild.fullInvalidations
    and DPS.HashCacheStats().targetedInvalidations == statusDps.targetedInvalidations
    and DPS.HashCacheStats().fullInvalidations == statusDps.fullInvalidations,
    "status-only revision invalidated compatibility hashes")

-- A public DPS winner rebuilds one category/player bucket. Duplicate,
-- rejected, and metadata-only traffic changes no DPS hash bucket.
Nexus.CommunityBuilds = nil
local echoes = {{spellId=200300,stacks=2}}
local fingerprint = DPS.GetEchoKey(echoes)
local record = {
    v=7,f=fingerprint,h=DPS.GetEchoHash(echoes),e=echoes,
    c="dummy",d=25000,u=60,t=40000,p="Peer",l=80,k="MAGE",
}
local dpsBefore = DPS.HashCacheStats()
assert(DPS.ReceiveRecord(record, "Peer"))
local changedDps = DPS.GetSyncHash()
assert(changedDps ~= dps0 and changedDps == DPS.GetSyncHashUncached())
local dpsAfter = DPS.HashCacheStats()
assert(dpsAfter.targetedInvalidations == dpsBefore.targetedInvalidations + 1
    and dpsAfter.fullRebuilds == dpsBefore.fullRebuilds
    and dpsAfter.collectionWalks == dpsBefore.collectionWalks
    and dpsAfter.bucketRebuilds == dpsBefore.bucketRebuilds + 1,
    "one DPS winner did not stay inside one deterministic bucket")
assert(not DPS.ReceiveRecord(record, "Peer"))
local afterDuplicate = DPS.HashCacheStats()
local enriched = {}
for key, value in pairs(record) do enriched[key] = value end
enriched.o, enriched.r = "peer@ebonhold", "ebonhold"
enriched.lk = {{spellId=200999,stacks=1}}
assert(DPS.ReceiveRecord(enriched, "Peer"))
local enrichedDps = DPS.GetSyncHash()
assert(enrichedDps ~= changedDps
    and enrichedDps == DPS.GetSyncHashUncached())
local afterMetadata = DPS.HashCacheStats()
assert(afterMetadata.targetedInvalidations
        == afterDuplicate.targetedInvalidations + 1
    and afterMetadata.bucketRebuilds == afterDuplicate.bucketRebuilds + 1
    and afterMetadata.collectionWalks == afterDuplicate.collectionWalks,
    "realm identity enrichment did not update exactly one wire hash bucket")
local rejected = {}
for key, value in pairs(record) do rejected[key] = value end
rejected.u = 0
assert(not DPS.ReceiveRecord(rejected, "Peer"))
assert(DPS.HashCacheStats().targetedInvalidations == afterMetadata.targetedInvalidations)

-- Explicit migration/all details deliberately rebuild every bucket.
local allBuildBefore = Sync.HashCacheStats()
R.Advance(R.BUILD_LIBRARY_CHANGED, {scope="all",reason="migration probe"})
AssertCanonical()
local allBuildAfter = Sync.HashCacheStats()
assert(allBuildAfter.fullRebuilds == allBuildBefore.fullRebuilds + 1
    and allBuildAfter.collectionWalks == allBuildBefore.collectionWalks + 2
    and allBuildAfter.deltaBucketRebuilds == allBuildBefore.deltaBucketRebuilds + 8
    and allBuildAfter.legacyBucketRebuilds == allBuildBefore.legacyBucketRebuilds + 8,
    "full build invalidation did not rebuild every required bucket")
local allDpsBefore = DPS.HashCacheStats()
R.Advance(R.DPS_CHANGED, {scope="all",reason="migration probe"})
assert(DPS.GetSyncHash() == DPS.GetSyncHashUncached())
local allDpsAfter = DPS.HashCacheStats()
assert(allDpsAfter.fullRebuilds == allDpsBefore.fullRebuilds + 1
    and allDpsAfter.collectionWalks == allDpsBefore.collectionWalks + 1
    and allDpsAfter.bucketRebuilds == allDpsBefore.bucketRebuilds + 8,
    "full DPS invalidation did not rebuild every required bucket")

-- A failed warm-up never publishes a half-initialized cache. Restoring the
-- catalog lets the reloaded module build cleanly and reproduce both hashes.
local expectedCurrent, expectedLegacy = Sync.GetCompatibilityHashes(), Sync.GetLegacyBuildHash()
local realDelta = Catalog.DeltaSummaries
dofile("core/BuildHashCache.lua")
Catalog.DeltaSummaries = function() error("forced cache warm failure") end
assert(Nexus.BuildHashCache.Delta() == nil
    and Nexus.BuildHashCache.Stats().initialized == false,
    "failed cache warm published initialized state")
Catalog.DeltaSummaries = realDelta
assert(Sync.GetCompatibilityHashes() == expectedCurrent
    and Sync.GetLegacyBuildHash() == expectedLegacy
    and Nexus.BuildHashCache.Stats().fullRebuilds == 1,
    "cache reload did not recover canonical compatibility hashes")

print("revision-cached build/DPS hashes preserve wire output and targeted buckets -- OK")
