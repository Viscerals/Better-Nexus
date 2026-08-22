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
    settings={
        communityRetentionEnabled=true,
        communityRetentionTopPerCategory=120,
        communityRetentionMinPerClassPerCategory=10,
        communityRetentionTopAverage=40,
        communityRetentionMinAveragePerClass=5,
        communityRetentionOtherRemoteBuilds=60,
        communityRetentionMaxPerAuthor=8,
    },
    accountCharacters={
        ["boganic@ebonhold"]={name="Boganic",realm="ebonhold"},
        ["altanic@ebonhold"]={name="Altanic",realm="ebonhold"},
    },
    communityBuilds={},
    syncTombstones={},
    dpsCapture={
        personalBest={}, buildBest={},
        characterBest={dummy={},lk={}},
    },
}
Nexus.Store = {
    IsAccountOwnerKey=function(ownerKey)
        return type(ownerKey) == "string"
            and type(NexusDB.accountCharacters[ownerKey:lower()]) == "table"
    end,
    IsAccountBuild=function(build)
        return type(build) == "table" and (build.isMine == true
            or build.importedSavedBuild == true
            or (type(build.ownerKey) == "string"
                and type(NexusDB.accountCharacters[build.ownerKey:lower()]) == "table"))
    end,
}

local overlay = NexusDB.communityBuilds
local classes = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}
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
overlay["alt-reference"] = {
    id="alt-reference", title="Alt reference", author="Altanic",
    ownerKey="altanic@ebonhold", class="DRUID", lastModified=now,
}

for i = 1, 900 do
    local id = string.format("remote-%04d", i)
    overlay[id] = {
        id=id, title=id, author="Peer" .. tostring((i - 1) % 60 + 1),
        class=classes[(i - 1) % #classes + 1],
        lastModified=1000 + i, loadoutAvailable=true,
    }
end
for i = 1, 40 do
    local id = string.format("flood-%03d", i)
    overlay[id] = {
        id=id, title=id, author="Flood", class="MAGE", lastModified=5000 + i,
        loadoutAvailable=true,
    }
end

local dummy = NexusDB.dpsCapture.characterBest.dummy
dummy.boganic = {
    player="Boganic", ownerKey="boganic@ebonhold", buildId="local-leader",
    ownerVerified=true,realm="ebonhold",fingerprint="fp-local",
    lockedEchoes={},dps=999999,ts=now,
}
for i = 1, 300 do
    local id = string.format("remote-char-%03d", i)
    overlay[id] = {
        id=id, title=id, author="DpsPeer" .. tostring(i), autoDps=true,
        class=classes[(i - 1) % #classes + 1],
        lastModified=10000 + i, loadoutAvailable=true,
    }
    dummy[string.format("player-%03d", i)] = {
        player="Player" .. tostring(i),
        ownerKey="player" .. tostring(i) .. "@ebonhold",
        ownerVerified=true,realm="ebonhold",buildId=id,lockedEchoes={},
        fingerprint="fp-char-" .. tostring(i), dps=100000 + i, ts=10000 + i,
    }
    if i <= 180 then
        NexusDB.dpsCapture.characterBest.lk[string.format("player-%03d", i)] = {
            player="Player" .. tostring(i),
            ownerKey="player" .. tostring(i) .. "@ebonhold",
            ownerVerified=true,realm="ebonhold",buildId=id,lockedEchoes={},
            fingerprint="fp-char-" .. tostring(i),
            dps=(i <= 40 and 900000 + i or 200000 + i), ts=10000 + i,
        }
    end
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

overlay["retained-marker-build"] = {
    id="retained-marker-build",title="Retained exact marker",
    author="MarkerPeer",autoDps=true,lastModified=now,
    loadoutAvailable=true,
}

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
NexusDB.syncTombstones["retained-delete"] = {
    stamp=now - 1, author="OldPeer",
}

Nexus.LoadoutEvidence.Init(NexusDB)
Nexus.BuildCatalog.Init(NexusDB, Nexus.BundledBuilds)
local limits = Nexus.DataRetention.Limits()
assert(limits.topPerCategory == 120 and limits.minPerClassPerCategory == 10
    and limits.topAverage == 40 and limits.minAveragePerClass == 5
    and limits.otherRemoteBuilds == 60
    and limits.remotePerAuthor == 8,
    "configured retention limits were not resolved")
assert(limits.enabled == true, "explicit ranked retention mode was not enabled")
local summary = assert(Nexus.DataRetention.Enforce(NexusDB, "focused test"))

local remoteCount, floodCount, localCount = 0, 0, 0
local classCounts = {}
for _, build in pairs(NexusDB.communityBuilds) do
    if build.isMine or build.importedSavedBuild
        or build.ownerKey == "boganic@ebonhold"
        or build.ownerKey == "altanic@ebonhold" then
        localCount = localCount + 1
    else
        remoteCount = remoteCount + 1
        local class = tostring(build.class or "UNKNOWN")
        classCounts[class] = (classCounts[class] or 0) + 1
        if tostring(build.author):lower() == "flood" then
            floodCount = floodCount + 1
        end
    end
end
assert(localCount == 32 and overlay["alt-reference"] ~= nil,
    "retention removed a current or account-character build")
assert(floodCount <= limits.remotePerAuthor,
    "one remote author exceeded the per-author cap")
assert(overlay["remote-char-300"] ~= nil,
    "current leaderboard build was removed")
assert(overlay["remote-char-001"] ~= nil,
    "Average selection did not preserve its lower raw-category contributor")
assert(summary.orphanAutoBuildsRemoved >= 45,
    "superseded automatic DPS pages were not reclaimed")
local evictedMarker = NexusDB.communityRetentionEvictions
    and NexusDB.communityRetentionEvictions["retained-marker-build"]
local evictedRevision = type(evictedMarker) == "table"
    and evictedMarker.revision or evictedMarker
assert(type(evictedMarker) == "table" and evictedRevision
    and not Nexus.DataRetention.AllowsRemoteRevision(
        "MarkerPeer", evictedRevision, NexusDB, "retained-marker-build")
    and Nexus.DataRetention.AllowsRemoteRevision(
        "MarkerPeer", evictedRevision + 1, NexusDB, "retained-marker-build")
    and Nexus.DataRetention.AllowsRemoteRevision(
        "OtherPeer", 1, NexusDB, "unrelated-older-build")
    and NexusDB.communityBuildRetentionFloor == nil,
    "exact eviction marker suppressed an unrelated build or lost its own ID")

local characterCount = 0
for _ in pairs(dummy) do characterCount = characterCount + 1 end
assert(characterCount >= limits.topPerCategory
    and summary.selectedAverage >= limits.topAverage,
    "ranked category selection did not keep overall/Average leaders")
local perClass = {}
for _, row in pairs(dummy) do
    local build = overlay[row.buildId]
    local class = tostring(build and build.class or "UNKNOWN")
    perClass[class] = (perClass[class] or 0) + 1
end
for _, class in ipairs(classes) do
    assert((perClass[class] or 0) >= limits.minPerClassPerCategory,
        tostring(class) .. " lost its per-category minimum")
end
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
    and NexusDB.syncTombstoneFloor == nil
    and NexusDB.syncTombstones["old-delete-0001"] == nil,
    "old non-baseline tombstones were not safely forgotten")
assert(Nexus.DataRetention.AllowsRemoteRevision(
        "OldPeer", 1, NexusDB, "unrelated-after-tombstone-compaction")
    and Nexus.DataRetention.AllowsRemoteRevision(
        "OldPeer", 1, NexusDB, "old-delete-0001"),
    "forgotten tombstone suppressed its own or an unrelated ID")
local retainedDelete = NexusDB.syncTombstones["retained-delete"]
assert(type(retainedDelete) == "table"
        and 1 <= (tonumber(retainedDelete.stamp) or 0),
    "recent exact tombstone was compacted")

-- Divergent local retention histories must not partition the mesh. Only B is
-- suppressed on the peer that still remembers B; A remains admissible to both,
-- and forgetting B's exact marker restores convergence for B.
local peerOne = {communityRetentionEvictions={B=200}}
local peerTwo = {communityRetentionEvictions={}}
assert(Nexus.DataRetention.AllowsRemoteRevision("Peer",150,peerOne,"A")
        and Nexus.DataRetention.AllowsRemoteRevision("Peer",150,peerTwo,"A")
        and not Nexus.DataRetention.AllowsRemoteRevision("Peer",150,peerOne,"B")
        and Nexus.DataRetention.AllowsRemoteRevision("Peer",150,peerTwo,"B"),
    "one build's exact retention history affected another build")
peerOne.communityRetentionEvictions.B = nil
assert(Nexus.DataRetention.AllowsRemoteRevision("Peer",150,peerOne,"B")
        and Nexus.DataRetention.AllowsRemoteRevision("Peer",150,peerTwo,"B"),
    "peers did not converge after exact suppression was forgotten")

overlay.superseded = {
    id="superseded", title="Old DPS page", author="Remote",
    autoDps=true, lastModified=now,
}
assert(Nexus.DataRetention.ReleaseSupersededAutoBuild("superseded", NexusDB)
    and overlay.superseded == nil,
    "direct superseded-page cleanup did not remove an unreferenced remote page")

local markerAge = 30 * 24 * 60 * 60
overlay["old-evicted-today"] = {
    id="old-evicted-today",title="Old revision evicted today",author="Remote",
    autoDps=true,lastModified=now - 90 * 24 * 60 * 60,
}
local oldRevision = overlay["old-evicted-today"].lastModified
assert(Nexus.DataRetention.ReleaseSupersededAutoBuild(
        "old-evicted-today", NexusDB),
    "old remote build was not evicted")
local freshMarker = NexusDB.communityRetentionEvictions["old-evicted-today"]
assert(type(freshMarker) == "table" and freshMarker.revision == oldRevision
        and freshMarker.recordedAt == now,
    "eviction marker did not separate revision from creation time")
Nexus.DataRetention.Enforce(NexusDB, "same-pass marker aging")
assert(NexusDB.communityRetentionEvictions["old-evicted-today"] ~= nil,
    "new marker for an old revision expired in its creation pass")
now = now + markerAge - 1
Nexus.DataRetention.Enforce(NexusDB, "marker before expiry")
assert(NexusDB.communityRetentionEvictions["old-evicted-today"] ~= nil,
    "marker expired before its creation-time lifetime")
now = now + 2
Nexus.DataRetention.Enforce(NexusDB, "marker after expiry")
assert(NexusDB.communityRetentionEvictions["old-evicted-today"] == nil,
    "marker did not expire according to creation time")
now = 2000000000

local again = Nexus.DataRetention.Enforce(NexusDB, "idempotence")
assert(again.overlayRemoved == 0 and again.characterBestRemoved == 0
    and again.personalRemoved == 0 and again.buildBestRemoved == 0
    and again.tombstonesRemoved == 0,
    "retention was not idempotent")

local crossRealm = {
    settings={communityRetentionEnabled=true,
        communityRetentionTopPerCategory=25,
        communityRetentionMinPerClassPerCategory=1,
        communityRetentionTopAverage=10,
        communityRetentionMinAveragePerClass=1,
        communityRetentionOtherRemoteBuilds=0,
        communityRetentionMaxPerAuthor=1},
    communityBuilds={}, syncTombstones={},
    dpsCapture={personalBest={},buildBest={},characterBest={
        dummy={a={player="Twin",ownerKey="twin@realma",realm="realma",
            buildId="same",fingerprint="same",dps=10}},
        lk={b={player="Twin",ownerKey="twin@realmb",realm="realmb",
            buildId="same",fingerprint="same",dps=20}},
    }},
}
local crossSummary = Nexus.DataRetention.Enforce(crossRealm, "realm identity")
assert(crossSummary.selectedAverage == 0,
    "same-name players from different realms were cross-paired for Average")

local function TypedReferenceFixture(referenceId)
    local database = {
        settings={communityRetentionEnabled=true,
            communityRetentionTopPerCategory=25,
            communityRetentionMinPerClassPerCategory=1,
            communityRetentionTopAverage=10,
            communityRetentionMinAveragePerClass=1,
            communityRetentionOtherRemoteBuilds=0,
            communityRetentionMaxPerAuthor=1},
        communityBuilds={
            [1]={id=1,author="Numeric",class="MAGE",autoDps=true,
                lastModified=10},
            ["1"]={id="1",author="String",class="ROGUE",autoDps=true,
                lastModified=11},
        },syncTombstones={},
        dpsCapture={personalBest={},buildBest={},characterBest={
            dummy={one={player="Typed",buildId=referenceId,
                fingerprint="typed",class="MAGE",dps=100,ts=10}},lk={}}},
    }
    NexusDB = database
    Nexus.BuildCatalog.Init(database, {schemaVersion=1,
        catalogVersion="typed",sourceVersion="test",builds={}})
    Nexus.DataRetention.Enforce(database, "typed ID reference")
    return database
end
local numericReference = TypedReferenceFixture(1)
assert(numericReference.communityBuilds[1] ~= nil
        and numericReference.communityBuilds["1"] == nil,
    "numeric build reference did not protect only numeric ID 1")
local stringReference = TypedReferenceFixture("1")
assert(stringReference.communityBuilds["1"] ~= nil
        and stringReference.communityBuilds[1] == nil,
    "string build reference did not protect only string ID 1")

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

local relaxedLimits = Nexus.DataRetention.Limits({settings={
    communityRetentionEnabled=false,
    communityRetentionTopPerCategory=25,
    communityRetentionMinPerClassPerCategory=1,
    communityRetentionTopAverage=10,
    communityRetentionMinAveragePerClass=1,
    communityRetentionOtherRemoteBuilds=0,
    communityRetentionMaxPerAuthor=1,
}})
assert(relaxedLimits.enabled == false
    and relaxedLimits.contentUnlimited == true
    and relaxedLimits.topPerCategory == 25
    and relaxedLimits.minPerClassPerCategory == 1
    and relaxedLimits.topAverage == 10
    and relaxedLimits.otherRemoteBuilds == 0
    and relaxedLimits.remotePerAuthor == 1,
    "disabled ranked retention did not preserve its dormant configuration")

local unlimited = {
    settings={communityRetentionEnabled=false},
    communityBuildRetentionFloor=now,
    syncTombstoneFloor=now,
    communityRetentionEvictions={
        ["disabled-exact-marker"]=now,
    },
    communityBuilds={},syncTombstones={},
    dpsCapture={personalBest={},buildBest={},characterBest={dummy={},lk={}}},
}
local function UnlimitedCount(source)
    local total = 0
    for _ in pairs(source or {}) do total = total + 1 end
    return total
end
for index = 1, 1100 do
    local key = string.format("unlimited-%04d", index)
    unlimited.communityBuilds[key] = {
        id=key,author="Remote",lastModified=index,
    }
    unlimited.dpsCapture.characterBest.dummy[key] = {
        player=key,dps=index,fingerprint=key,buildId=key,
    }
    unlimited.dpsCapture.characterBest.lk[key] = {
        player=key,dps=index,fingerprint=key,buildId=key,
    }
    unlimited.dpsCapture.personalBest[key] = {dummy={dps=index}}
    unlimited.dpsCapture.buildBest[key] = {dummy={dps=index}}
end
local unlimitedSummary = Nexus.DataRetention.Enforce(
    unlimited, "disabled content retention")
assert(unlimitedSummary.contentUnlimited == true
        and unlimitedSummary.characterBestRemoved == 0
        and unlimitedSummary.personalRemoved == 0
        and unlimitedSummary.buildBestRemoved == 0
        and unlimitedSummary.overlayRemoved == 0
        and UnlimitedCount(unlimited.communityBuilds) == 1100
        and UnlimitedCount(unlimited.dpsCapture.characterBest.dummy) == 1100
        and UnlimitedCount(unlimited.dpsCapture.characterBest.lk) == 1100
        and UnlimitedCount(unlimited.dpsCapture.personalBest) == 1100
        and UnlimitedCount(unlimited.dpsCapture.buildBest) == 1100
        and unlimited.communityBuildRetentionFloor == nil
        and unlimited.syncTombstoneFloor == nil
        and Nexus.DataRetention.AllowsRemoteRevision(
            "Peer",1,unlimited,"unrelated-disabled")
        and not Nexus.DataRetention.AllowsRemoteRevision(
            "Peer",now,unlimited,"disabled-exact-marker"),
    "disabled retention still capped build or DPS content")

print("bounded community/DPS retention and tombstone compaction -- OK")
