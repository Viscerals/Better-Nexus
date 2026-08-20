-- Characterize extracted compatibility hashes, summaries, and candidate views.
Nexus = {}
NexusDB = { sentinel = "keep" }
ProjectEbonhold = { sentinel = "keep" }

dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua")
dofile("core/SyncCompatibility.lua")

local originalDb, originalGame = NexusDB, ProjectEbonhold
local catalogVersion = "compat-catalog-v7"
local delta, all, tombstones = {}, {}, {}
local orderedIds, positions = {}, {}
for index = 1, 1000 do
    local id = string.format("build-%04d", index)
    local build = {
        id=id, title="Build " .. index, author="Peer" .. index,
        class=index % 2 == 0 and "MAGE" or "ROGUE",
        lastModified=index, fingerprintHash=string.format("%x", index * 17),
        echoes=index % 3 == 0 and nil
            or {{spellId=200000 + index, stacks=(index % 4) + 1}},
    }
    delta[id], all[id] = build, build
    orderedIds[index], positions[id] = id, index
end
for index = 1, 40 do
    local id = string.format("base-%03d", index)
    all[id] = {
        id=id, title="Baseline " .. index, author="Release",
        lastModified=index, fingerprintHash=string.format("%x", 9000 + index),
        echoes={{spellId=300000 + index, stacks=1}},
    }
end
for index = 1, 500 do
    local localOwner = index % 2 ~= 0
    tombstones[string.format("gone-%04d", index)] = {
        stamp=2000 + index,
        author=index % 2 == 0 and "Remote" or "Local-Realm",
        ownerKey=localOwner and "local@realm" or "remote@realm",
        ownerVerified=true,
    }
end

local counts = {delta=0, all=0, tombstones=0, next=0}
local catalog = {
    CatalogVersion=function() return catalogVersion end,
    DeltaSnapshot=function() counts.delta = counts.delta + 1; return delta end,
    All=function() counts.all = counts.all + 1; return all end,
    TombstoneSnapshot=function()
        counts.tombstones = counts.tombstones + 1
        return tombstones
    end,
    SyncDeltaNext=function(cursor)
        counts.next = counts.next + 1
        local index = cursor and ((positions[cursor] or 0) + 1) or 1
        local id = orderedIds[index]
        if not id then return nil, nil, true end
        return id, delta[id], false
    end,
}

local cachedDelta, cachedLegacy
local buildRevision = 1
local currentOwner = "local@realm"
local cacheStats = {available=true, marker="cache"}
local hashCache
local echoKeyEnabled = false
local dps = {
    GetSyncHash=function() return "d1,d2,d3,d4,d5,d6,d7,d8" end,
    GetEchoKey=function()
        return echoKeyEnabled and "external-echo-key" or nil
    end,
}
local stats = {candidateSnapshots=0, candidateScans=0}

local Protocol = Nexus.SyncInternals.Protocol.New({
    limits={
        maxTransferIdBytes=96, maxHashBytes=512, maxVersionBytes=64,
        maxBuildIdBytes=160, maxBuildEchoes=128, maxWireFields=8,
    },
    parseVersion=function() return {1, 0, 0} end,
    ownerKeyMatchesAuthor=function() return true end,
    isSafeTree=Nexus.Codec.IsSafeTree,
})

local C = Nexus.SyncInternals.Compatibility.New({
    buckets=8,
    getCatalog=function() return catalog end,
    getBuildHashCache=function() return hashCache end,
    getBuildRevision=function() return buildRevision end,
    getDpsCapture=function() return dps end,
    getTombstones=function() return tombstones end,
    localOwnsTomb=function(tombstone)
        return tombstone.ownerVerified == true
            and tombstone.ownerKey == currentOwner
    end,
    relayEligible=function(build) return build.relayBlocked ~= true end,
    myName=function() return "Local" end,
    currentOwnerKey=function() return currentOwner end,
    now=function() return 123.5 end,
    getCodec=function() return Nexus.Codec end,
    validIdentifier=Protocol.ValidIdentifier,
    validHash=Protocol.ValidHash,
    escapedLen=Protocol.EscapedLen,
    codeIndex="WLI2", maxBuildIdBytes=160,
    chatLimit=255, chatSafety=12,
    noteStat=function(name, amount)
        stats[name] = (stats[name] or 0) + (amount or 1)
    end,
})

local function RefBucket(id)
    local text, hash = tostring(id or ""), 5381
    for index = 1, #text do
        hash = ((hash * 33) + text:byte(index)) % 2147483648
    end
    return (hash % 8) + 1
end

local function RefLibraryHash(builds, tombstoneSource)
    local grouped = {}
    for bucket = 1, 8 do grouped[bucket] = {} end
    for id, build in pairs(builds or {}) do
        local complete = type(build.echoes) == "table"
            and #build.echoes > 0 and "F" or "S"
        grouped[RefBucket(id)][#grouped[RefBucket(id)] + 1] = id .. ":"
            .. tostring(build.lastModified or build.postedAt or 0) .. ":"
            .. complete .. ":"
            .. tostring(build.fingerprintHash or build.fingerprint or "0")
    end
    for id, tombstone in pairs(tombstoneSource or {}) do
        local stamp = type(tombstone) == "table"
            and (tonumber(tombstone.stamp) or 0) or (tonumber(tombstone) or 0)
        local author = type(tombstone) == "table"
            and tostring(tombstone.author or "") or ""
        grouped[RefBucket(id)][#grouped[RefBucket(id)] + 1] = "!" .. id
            .. ":" .. tostring(stamp) .. ":" .. author
    end
    local hashes = {}
    for bucket = 1, 8 do
        table.sort(grouped[bucket])
        local hash = 5381
        for _, text in ipairs(grouped[bucket]) do
            for index = 1, #text do
                hash = ((hash * 33) + text:byte(index)) % 2147483648
            end
        end
        hashes[bucket] = #grouped[bucket] > 0
            and string.format("%x", hash) or "0"
    end
    return table.concat(hashes, ",")
end

local function RefCatalogToken(value)
    local out = {}
    value = tostring(value)
    for index = 1, #value do
        out[index] = string.format("%02x", value:byte(index))
    end
    return table.concat(out)
end

local expectedDelta = RefLibraryHash(delta, tombstones)
local expectedLegacy = RefLibraryHash(all, tombstones)
local expectedCurrent = expectedDelta .. "," .. RefCatalogToken(catalogVersion)
assert(C.DeltaBuildHash() == expectedDelta
    and C.LegacyBuildHash() == expectedLegacy
    and C.CurrentBuildHash() == expectedCurrent,
    "large-fixture compatibility hashes changed")
assert(C.CurrentDpsHash() == "d1,d2,d3,d4,d5,d6,d7,d8",
    "DPS compatibility hash changed")
local canonicalCurrent, canonicalLegacy = C.CanonicalBuildHashes()
assert(canonicalCurrent == expectedCurrent and canonicalLegacy == expectedLegacy,
    "canonical diagnostic hashes changed")
assert(counts.delta == 3 and counts.all == 2 and counts.tombstones == 1,
    "fallback/canonical collection reads drifted")

-- Dynamic hash-cache replacement remains visible to the retained Sync instance.
cachedDelta, cachedLegacy = "1,2,3,4,5,6,7,8", "8,7,6,5,4,3,2,1"
hashCache = {
    Delta=function() return cachedDelta end,
    Legacy=function() return cachedLegacy end,
    Stats=function() return cacheStats end,
}
local readsBefore = counts.delta + counts.all
assert(C.DeltaBuildHash() == cachedDelta and C.LegacyBuildHash() == cachedLegacy
    and C.CurrentBuildHash() == cachedDelta .. "," .. RefCatalogToken(catalogVersion),
    "revision cache projections were not reused")
assert(counts.delta + counts.all == readsBefore and C.HashCacheStats() == cacheStats,
    "cached compatibility reads materialized a catalog")

-- Candidate discovery performs one bounded row/tombstone unit per call and
-- reuses the same derived snapshot while the represented delta is unchanged.
local snapshot = C.BuildCandidateSnapshot(cachedDelta)
assert(C.BuildCandidateSnapshot(cachedDelta) == snapshot
    and stats.candidateSnapshots == 1,
    "unchanged candidate revision did not reuse its snapshot")
local previousCandidates = 0
local steps = 0
while not snapshot.complete do
    local beforeNext = counts.next
    local _, why, progressed = C.AdvanceCandidateSnapshot(snapshot)
    assert(why == nil and progressed == true,
        "candidate construction failed to make one bounded step")
    local candidates = 0
    for bucket = 1, 8 do candidates = candidates + #snapshot.byBucket[bucket] end
    assert(candidates - previousCandidates >= 0
        and candidates - previousCandidates <= 1,
        "one candidate step appended more than one row")
    assert(counts.next - beforeNext >= 0 and counts.next - beforeNext <= 1,
        "one candidate step scanned more than one overlay row")
    previousCandidates, steps = candidates, steps + 1
    assert(steps <= 1600, "candidate construction did not terminate")
end
assert(steps == 1502 and previousCandidates == 1250
    and stats.candidateScans == 1502,
    "large candidate snapshot coverage/count drifted")
assert(counts.delta + counts.all == readsBefore,
    "candidate construction materialized a full catalog")
local scansAtComplete = stats.candidateScans
local complete, why, progressed = C.AdvanceCandidateSnapshot(snapshot)
assert(complete == true and why == nil and progressed == false
    and stats.candidateScans == scansAtComplete,
    "completed snapshot was rebuilt or rescanned")

-- Tomb candidates depend on exact local authority, not only the short display
-- name. A same-name realm transition must invalidate every retained snapshot
-- even when the represented hash and catalog revision are unchanged.
currentOwner = "local@otherrealm"
assert(C.SnapshotCurrent(snapshot) == false,
    "EXPECTED RED: exact owner change retained a prior tomb snapshot")
complete, why, progressed = C.AdvanceCandidateSnapshot(snapshot)
assert(complete == false and why == "stale candidate snapshot"
    and progressed == true,
    "exact-owner-stale candidate snapshot did not fail explicitly")
local ownerReplacement = C.BuildCandidateSnapshot(cachedDelta)
assert(ownerReplacement ~= snapshot and stats.candidateSnapshots == 2
    and C.BuildCandidateSnapshot(cachedDelta) == ownerReplacement,
    "exact owner invalidation did not rebuild exactly once")
currentOwner = "local@realm"
assert(C.SnapshotCurrent(ownerReplacement) == false,
    "same-short owner rollback retained the foreign-owner snapshot")
snapshot = C.BuildCandidateSnapshot(cachedDelta)
assert(stats.candidateSnapshots == 3,
    "owner rollback did not rebuild the candidate snapshot")

-- Metadata-only represented changes advance the build revision even when the
-- wire hash fields stay byte-identical. They must replace the derived view.
buildRevision = buildRevision + 1
assert(C.SnapshotCurrent(snapshot) == false,
    "metadata-only represented revision did not invalidate old snapshot")
complete, why, progressed = C.AdvanceCandidateSnapshot(snapshot)
assert(complete == false and why == "stale candidate snapshot"
    and progressed == true,
    "stale candidate snapshot did not fail explicitly")
local replacement = C.BuildCandidateSnapshot(cachedDelta)
assert(replacement ~= snapshot and stats.candidateSnapshots == 4
    and C.BuildCandidateSnapshot(cachedDelta) == replacement,
    "metadata-only invalidation did not rebuild exactly once")

cachedDelta = "new-delta-revision"
buildRevision = buildRevision + 1
assert(C.SnapshotCurrent(replacement) == false,
    "wire-hash revision did not invalidate old snapshot")
local hashReplacement = C.BuildCandidateSnapshot(cachedDelta)
assert(hashReplacement ~= replacement and stats.candidateSnapshots == 5
    and C.BuildCandidateSnapshot(cachedDelta) == hashReplacement,
    "wire-hash invalidation did not rebuild exactly once")
C.Reset()
assert(C.BuildCandidateSnapshot(cachedDelta) ~= hashReplacement
    and stats.candidateSnapshots == 6,
    "session reset retained derived candidate state")

-- Fingerprints and compact summaries preserve the established exact fields.
local summaryBuild = {
    id="sum-1", title="Summary", author="Peer", ownerKey="peer@realm",
    class="MAGE", lastModified=77, link="EBH1:example", autoDps=true,
    echoes={
        {spellId=20,stacks=1}, {spellId=10,stacks=2},
        {spellId=10,count=1},
    },
}
assert(C.BuildFingerprint(summaryBuild) == "10x3,20x1",
    "fallback fingerprint canonicalization changed")
echoKeyEnabled = true
assert(C.BuildFingerprint(summaryBuild) == "external-echo-key",
    "established DPS fingerprint provider was not preferred")
echoKeyEnabled = false
local encoded = C.SummaryEncode(summaryBuild)
assert(encoded.id == "sum-1" and encoded.t == "Summary"
    and encoded.a == "Peer" and encoded.o == "peer@realm"
    and encoded.c == "MAGE" and encoded.m == 77 and encoded.n == 4
    and encoded.x == 1 and encoded.h == C.HashText("10x3,20x1")
    and encoded.lh == C.HashText("EBH1:example"),
    "compact summary fields changed")
local prepared = assert(C.PrepareSummary(summaryBuild))
local expectedWire = "WLI2|Local|" .. Nexus.Codec.Base64Encode(
    Nexus.Codec.JSONEncode(encoded))
assert(#prepared.messages == 1 and prepared.messages[1] == expectedWire
    and prepared.title == "Summary" and prepared.summary == true,
    "compact summary wire output changed")
local bad, badWhy = C.PrepareSummary({
    id="bad id", title="Bad", author="Peer", fingerprintHash="abc",
})
assert(bad == nil and badWhy == "invalid build id",
    "invalid summary id was accepted")
bad, badWhy = C.PrepareSummary({
    id="ok", title="Bad", author="Peer", fingerprintHash="not a hash",
})
assert(bad == nil and badWhy == "invalid build hash",
    "invalid summary hash was accepted")
bad, badWhy = C.PrepareSummary({
    id="ok", title=string.rep("x", 500), author="Peer", fingerprintHash="abc",
})
assert(bad == nil and badWhy == "summary too large",
    "oversize summary was accepted")

local function Read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local syncSource = Read("core/Sync.lua")
local compatibilitySource = Read("core/SyncCompatibility.lua")
local _, receivedFingerprintCalls = syncSource:gsub(
    "BuildFingerprint%(payload%)", "")
assert(receivedFingerprintCalls == 1,
    "received build recomputes its canonical fingerprint")
for _, stale in ipairs({
    "local function LibraryHash", "local function CatalogToken",
    "local function DeltaBuildHash", "local function LegacyBuildHash",
    "local function CurrentBuildHash", "local function CurrentDpsHash",
    "local function HashText", "local function BuildFingerprint",
    "local function SummaryEncode", "Responder.candidateCache",
}) do
    assert(not syncSource:find(stale, 1, true),
        "Sync retained compatibility implementation: " .. stale)
end
for _, delegated in ipairs({
    "Compatibility.CanonicalBuildHashes()",
    "Compatibility.PrepareSummary(build, responseContext)",
    "Compatibility.BuildCandidateSnapshot(deltaHash)",
    "Compatibility.AdvanceCandidateSnapshot(snapshot)",
}) do
    assert(syncSource:find(delegated, 1, true),
        "Sync does not delegate compatibility operation " .. delegated)
end
for _, forbidden in ipairs({
    "Transport", "Enqueue", "SendChatMessage", "Catalog.Put",
    "SetTombstone", "ClearTombstone", "NexusDB", "ProjectEbonhold",
    "GameAdapter", "pendingResponses", "pendingLoadouts",
}) do
    assert(not compatibilitySource:find(forbidden, 1, true),
        "SyncCompatibility crossed frozen owner boundary: " .. forbidden)
end
local toc = Read("Nexus.toc")
local protocolAt = assert(toc:find("core\\SyncProtocol.lua", 1, true))
local transportAt = assert(toc:find("core\\SyncTransport.lua", protocolAt, true))
local compatibilityAt = assert(toc:find(
    "core\\SyncCompatibility.lua", transportAt, true))
local reconcilerAt = assert(toc:find(
    "core\\SyncReconciler.lua", compatibilityAt, true))
local inboundAt = assert(toc:find(
    "core\\SyncInbound.lua", reconcilerAt, true))
local syncAt = assert(toc:find("core\\Sync.lua", inboundAt, true))
assert(protocolAt < transportAt and transportAt < compatibilityAt
    and compatibilityAt < reconcilerAt and reconcilerAt < inboundAt
    and inboundAt < syncAt,
    "compatibility load order drifted")
assert(NexusDB == originalDb and NexusDB.sentinel == "keep"
    and ProjectEbonhold == originalGame and ProjectEbonhold.sentinel == "keep",
    "compatibility work mutated persistence or gameplay state")

print("Sync compatibility hashes, summaries, snapshots, and cost parity -- OK")
