local H = dofile("tests/harness.lua")

local now = 2000000000
time = function() return now end
UnitName = function() return "Boganic" end
GetNormalizedRealmName = function() return "Ebonhold" end

local baseline = {
    ["release-mask"]={
        id="release-mask", title="Bundled", author="Release", class="MAGE",
        postedAt=1, lastModified=1, echoes={{spellId=1,stacks=1}},
    },
}
Nexus.BundledBuilds = {
    schemaVersion=1, catalogVersion="retention-test", sourceVersion="test",
    builds=baseline,
}

NexusDB = {
    communityBuilds={},
    syncTombstones={},
    dpsCapture={
        personalBest={}, buildBest={},
        characterBest={dummy={},lk={}},
    },
}

local overlay = NexusDB.communityBuilds
for i = 1, 30 do
    local id = string.format("local-%03d", i)
    overlay[id] = {
        id=id, title=id, author="Boganic", ownerKey="boganic@ebonhold",
        isMine=true, lastModified=i,
    }
end
overlay["local-leader"] = {
    id="local-leader", title="Local leader", author="Boganic",
    ownerKey="boganic@ebonhold", isMine=true, autoDps=true,
    lastModified=now,
}

for i = 1, 900 do
    local id = string.format("remote-%04d", i)
    overlay[id] = {
        id=id, title=id, author="Peer" .. tostring((i - 1) % 60 + 1),
        lastModified=1000 + i, loadoutAvailable=true,
    }
end
for i = 1, 40 do
    local id = string.format("flood-%03d", i)
    overlay[id] = {
        id=id, title=id, author="Flood", lastModified=5000 + i,
        loadoutAvailable=true,
    }
end

local dummy = NexusDB.dpsCapture.characterBest.dummy
dummy.boganic = {
    player="Boganic", ownerKey="boganic@ebonhold", buildId="local-leader",
    fingerprint="fp-local", dps=999999, ts=now,
}
for i = 1, 300 do
    local id = string.format("remote-char-%03d", i)
    overlay[id] = {
        id=id, title=id, author="DpsPeer" .. tostring(i), autoDps=true,
        lastModified=10000 + i, loadoutAvailable=true,
    }
    dummy[string.format("player-%03d", i)] = {
        player="Player" .. tostring(i), buildId=id,
        fingerprint="fp-char-" .. tostring(i), dps=100000 + i, ts=10000 + i,
    }
end

for i = 1, 150 do
    local key = string.format("fp-personal-%03d", i)
    NexusDB.dpsCapture.personalBest[key] = {
        dummy={player="Boganic", fingerprint=key, dps=i, ts=i},
    }
    NexusDB.dpsCapture.buildBest[key] = {
        dummy={player="Peer", fingerprint=key, dps=i, ts=i},
    }
end

for i = 1, 2100 do
    NexusDB.syncTombstones[string.format("old-delete-%04d", i)] = {
        stamp=now - 200 * 24 * 60 * 60 + i, author="OldPeer",
    }
end
NexusDB.syncTombstones["release-mask"] = {
    stamp=now - 300 * 24 * 60 * 60, author="Release",
}
NexusDB.syncTombstones.pending = {
    stamp=now - 300 * 24 * 60 * 60, author="Boganic", pending=true,
}

Nexus.LoadoutEvidence.Init(NexusDB)
Nexus.BuildCatalog.Init(NexusDB, Nexus.BundledBuilds)
local limits = Nexus.DataRetention.Limits()
local summary = assert(Nexus.DataRetention.Enforce(NexusDB, "focused test"))

local remoteCount, floodCount, localCount = 0, 0, 0
for _, build in pairs(NexusDB.communityBuilds) do
    if build.isMine or build.importedSavedBuild
        or build.ownerKey == "boganic@ebonhold" then
        localCount = localCount + 1
    else
        remoteCount = remoteCount + 1
        if tostring(build.author):lower() == "flood" then
            floodCount = floodCount + 1
        end
    end
end
assert(localCount == 31, "retention removed a local build")
assert(remoteCount <= limits.remoteOverlay,
    "remote overlay exceeded its global retention cap")
assert(floodCount <= limits.remotePerAuthor,
    "one remote author exceeded the per-author cap")
assert(overlay["remote-char-300"] ~= nil,
    "current leaderboard build was removed")
assert(summary.orphanAutoBuildsRemoved >= 45,
    "superseded automatic DPS pages were not reclaimed")
assert((NexusDB.communityBuildRetentionFloor or 0) > 0
    and not Nexus.DataRetention.AllowsRemoteRevision(
        "Peer1", 1001, NexusDB, "remote-0001"),
    "evicted mesh history could immediately re-enter and churn Sync")

local characterCount = 0
for _ in pairs(dummy) do characterCount = characterCount + 1 end
assert(characterCount <= limits.characterBestPerCategory,
    "character-best bucket exceeded its cap")
local personalCount, buildBestCount = 0, 0
for _ in pairs(NexusDB.dpsCapture.personalBest) do personalCount = personalCount + 1 end
for _ in pairs(NexusDB.dpsCapture.buildBest) do buildBestCount = buildBestCount + 1 end
assert(personalCount <= limits.personalFingerprints
    and buildBestCount <= limits.buildBestFingerprints,
    "fingerprint history exceeded its cap")

assert(NexusDB.syncTombstones["release-mask"] ~= nil
    and Nexus.BuildCatalog.Get("release-mask") == nil,
    "compaction resurrected a tombstoned bundled build")
assert(NexusDB.syncTombstones.pending ~= nil,
    "pending local delete was compacted before transmission")
assert(summary.tombstonesRemoved == 2100
    and (NexusDB.syncTombstoneFloor or 0) > 0,
    "old exact tombstones were not replaced by a retention floor")
assert(not Nexus.DataRetention.AllowsRemoteRevision(
    "OldPeer", NexusDB.syncTombstoneFloor, NexusDB),
    "compacted deletion floor accepted a stale resurrection")
assert(Nexus.DataRetention.AllowsRemoteRevision(
    "OldPeer", NexusDB.syncTombstoneFloor + 1, NexusDB),
    "compacted deletion floor rejected a newer revision")

overlay.superseded = {
    id="superseded", title="Old DPS page", author="Remote",
    autoDps=true, lastModified=now,
}
assert(Nexus.DataRetention.ReleaseSupersededAutoBuild("superseded", NexusDB)
    and overlay.superseded == nil,
    "direct superseded-page cleanup did not remove an unreferenced remote page")

local again = Nexus.DataRetention.Enforce(NexusDB, "idempotence")
assert(again.overlayRemoved == 0 and again.characterBestRemoved == 0
    and again.personalRemoved == 0 and again.buildBestRemoved == 0
    and again.tombstonesRemoved == 0,
    "retention was not idempotent")

local future = {
    dataRetention={schemaVersion=99},
    communityBuilds={keep={id="keep",author="Remote",autoDps=true}},
}
local futureSummary = Nexus.DataRetention.Enforce(future, "future schema")
assert(futureSummary.readOnly and future.communityBuilds.keep,
    "future retention schema was mutated")

local futureCatalog = {
    buildCatalog={schemaVersion=99},
    communityBuilds={keep={id="keep",author="Remote",autoDps=true}},
}
local futureCatalogSummary = Nexus.DataRetention.Enforce(
    futureCatalog, "future catalog")
assert(futureCatalogSummary.readOnly and futureCatalog.communityBuilds.keep
    and futureCatalog.dataRetention == nil,
    "future catalog schema was mutated by retention")

print("bounded community/DPS retention and tombstone compaction -- OK")
