local H = dofile("tests/harness.lua")

local function AwaitMutation(ok, why, ticket)
    if ok ~= nil then return ok, why end
    assert(why == "ROOT_MUTATION_PENDING" and type(ticket) == "table",
        "missing pending mutation ticket")
    for _ = 1, 20000 do
        if ticket.state ~= "pending" then break end
        assert(Nexus.BuildCatalog.PumpRootAdmission() == ticket,
            "pending mutation ticket changed")
    end
    assert(ticket.state ~= "pending", "pending mutation did not terminate")
    return ticket.committed, ticket.reason
end

local function Enforce(database, reason)
    local result = Nexus.DataRetention.Enforce(database, reason)
    for _ = 1, 20000 do
        if not (type(result) == "table" and result.pending) then return result end
        Nexus.BuildCatalog.PumpRootAdmission()
        result = Nexus.DataRetention.Enforce(database, reason)
    end
    error("pending retention did not terminate")
end

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

-- Pre-bootstrap seeding target: the exact PR #68 legacy input this client
-- starts with. It becomes a read-through view of the durable bundle payload
-- immediately after bootstrap below.
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
    ownerVerified=true,realm="ebonhold",fingerprint="910000x1",
    echoes={{spellId=910000,stacks=1}},
    lockedEchoes={},dps=999999,ts=now,
}
for i = 1, 300 do
    local id = string.format("remote-char-%03d", i)
    local fingerprint = tostring(910000 + i) .. "x1"
    local echoes = {{spellId=910000 + i,stacks=1}}
    overlay[id] = {
        id=id, title=id, author="DpsPeer" .. tostring(i), autoDps=true,
        class=classes[(i - 1) % #classes + 1],
        lastModified=10000 + i, loadoutAvailable=true,
    }
    dummy[string.format("player-%03d", i)] = {
        player="Player" .. tostring(i),
        ownerKey="player" .. tostring(i) .. "@ebonhold",
        ownerVerified=true,realm="ebonhold",buildId=id,lockedEchoes={},
        fingerprint=fingerprint,echoes=echoes,dps=100000 + i,ts=10000 + i,
    }
    if i <= 180 then
        NexusDB.dpsCapture.characterBest.lk[string.format("player-%03d", i)] = {
            player="Player" .. tostring(i),
            ownerKey="player" .. tostring(i) .. "@ebonhold",
            ownerVerified=true,realm="ebonhold",buildId=id,lockedEchoes={},
            fingerprint=fingerprint,echoes=echoes,
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

-- Persisted tombstones are reloaded/opaque block-all reservations under the
-- catalog authority contract: they never retire by age and the complete
-- selected root must stay within the 2,048-slot ceiling.
for i = 1, 100 do
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

-- Everything above seeded the exact PR #68 legacy input this client starts with.
-- An incidental read may already have bootstrapped an empty bundle, so the
-- durable authority is discarded once and rebuilt from those legacy bytes on the
-- LEGACY_BUNDLE_MIGRATION_REQUIRED route (state machine line 374).
H.ResetDurableAuthority()
Nexus.LoadoutEvidence.Init(NexusDB)
H.AdmitCatalogV1(NexusDB, Nexus.BundledBuilds)
-- Legacy-to-bundle cutover (architecture 3b5de54f state machine lines 374, 394
-- and 4849). Everything above seeded the exact PR #68 legacy input that
-- bootstrap has now admitted into the first complete authority bundle. From
-- here the durable overlay is the bundle's payload map, which is a fresh table
-- on every publication, so `overlay` becomes a read-through view of it and the
-- preserved legacy input is asserted separately.
local legacyOverlay = overlay
overlay = setmetatable({}, {
    __index = function(_, key) return H.DurableBuilds()[key] end,
    __newindex = function() error("fixture wrote a legacy payload location", 2) end,
})
local limits = Nexus.DataRetention.Limits()
assert(limits.topPerCategory == 120 and limits.minPerClassPerCategory == 10
    and limits.topAverage == 40 and limits.minAveragePerClass == 5
    and limits.otherRemoteBuilds == 60
    and limits.remotePerAuthor == 8,
    "configured retention limits were not resolved")
assert(limits.enabled == true, "explicit ranked retention mode was not enabled")
local retentionBefore = NexusDB.dataRetention and NexusDB.dataRetention.last
local summary = assert(Nexus.DataRetention.Enforce(NexusDB, "focused test"))
assert(summary.pending == true and summary.overlayRemoved == 0
        and summary.perAuthorRemoved == 0
        and NexusDB.dataRetention.last == retentionBefore,
    "retention reported planned removal or stamped completion before catalog commit")
local retainedTicket = summary.mutationTicket
assert(type(retainedTicket) == "table" and retainedTicket.state == "pending",
    "retention dropped its pending transaction ticket")
local retentionPumps = 0
while summary.pending == true do
    assert(Nexus.BuildCatalog.PumpRootAdmission() == retainedTicket,
        "retention restarted or replaced its pending transaction")
    retentionPumps = retentionPumps + 1
    assert(retentionPumps < 20000, "retention transaction did not terminate")
    summary = assert(Nexus.DataRetention.Enforce(NexusDB, "focused test"))
end
assert(retainedTicket.committed == true and summary.blocked ~= true,
    "retention did not observe a committed transaction")

local remoteCount, floodCount, localCount = 0, 0, 0
local classCounts = {}
for _, build in pairs(H.DurableBuilds()) do
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
-- An eviction is a deny-only replay barrier for its exact typed ID. No
-- newer sender-controlled revision clears it; only trusted local expiry in
-- the central catalog transaction can.
local evictedMarker = H.DurablePayload("communityRetentionEvictions")
    and H.DurablePayload("communityRetentionEvictions")["retained-marker-build"]
assert(type(evictedMarker) == "table" and evictedMarker.schemaVersion == 1
    and not Nexus.DataRetention.AllowsRemoteRevision(
        "MarkerPeer", now, NexusDB, "retained-marker-build")
    and not Nexus.DataRetention.AllowsRemoteRevision(
        "MarkerPeer", now + 1, NexusDB, "retained-marker-build")
    and Nexus.DataRetention.AllowsRemoteRevision(
        "OtherPeer", 1, NexusDB, "unrelated-older-build")
    and NexusDB.communityBuildRetentionFloor == nil,
    "exact eviction barrier suppressed an unrelated build or lost its own ID")

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

assert(H.DurableTombstones()["release-mask"] ~= nil
    and Nexus.BuildCatalog.Get("release-mask") == nil,
    "compaction resurrected a tombstoned bundled build")
assert(H.DurableTombstones().pending ~= nil,
    "pending local delete was compacted before transmission")
assert(summary.tombstonesRemoved == 0
    and NexusDB.syncTombstoneFloor == nil
    and H.DurableTombstones()["old-delete-0001"] ~= nil
    and Nexus.BuildCatalog.TombstoneState("old-delete-0001").state
        == "OPAQUE_BLOCK_ALL",
    "persisted tombstones regained age-retirement authority")
assert(Nexus.DataRetention.AllowsRemoteRevision(
        "OldPeer", 1, NexusDB, "unrelated-after-tombstone-compaction")
    and Nexus.DataRetention.AllowsRemoteRevision(
        "OldPeer", 1, NexusDB, "old-delete-0001"),
    "a tombstone reservation acted as a replay barrier for another ID")
local retainedDelete = H.DurableTombstones()["retained-delete"]
assert(type(retainedDelete) == "table"
        and 1 <= (tonumber(retainedDelete.stamp) or 0),
    "recent exact tombstone was compacted")

-- Divergent local retention histories must not partition the mesh.
--
-- MASTER-RC-008 STRENGTHENS this case. These peer tables were never bound as
-- the authority database, so architecture RAW-01 (line 4849) forbids treating
-- them as authority at all -- it is RED when "a detached instance falls back to
-- global NexusDB" -- and line 188 makes such raw fields "claims, not proof".
-- A detached communityRetentionEvictions marker therefore grants no veto, so a
-- divergent local history can no longer suppress ANY id on ANY peer. Per-id
-- isolation and mesh convergence now hold unconditionally instead of only when
-- the marker happens to be absent.
--
-- Real suppression still comes from the bound authority's barrier, which the
-- tombstone-reservation cases above prove against the bound NexusDB.
local peerOne = {communityRetentionEvictions={B=200}}
local peerTwo = {communityRetentionEvictions={}}
assert(Nexus.DataRetention.AllowsRemoteRevision("Peer",150,peerOne,"A")
        and Nexus.DataRetention.AllowsRemoteRevision("Peer",150,peerTwo,"A")
        and Nexus.DataRetention.AllowsRemoteRevision("Peer",150,peerOne,"B")
        and Nexus.DataRetention.AllowsRemoteRevision("Peer",150,peerTwo,"B"),
    "an unbound detached retention history suppressed an inbound revision")
peerOne.communityRetentionEvictions.B = nil
assert(Nexus.DataRetention.AllowsRemoteRevision("Peer",150,peerOne,"B")
        and Nexus.DataRetention.AllowsRemoteRevision("Peer",150,peerTwo,"B"),
    "peers did not converge after exact suppression was forgotten")

assert(AwaitMutation(Nexus.BuildCatalog.Put({
    id="superseded", title="Old DPS page", author="Remote",
    autoDps=true, lastModified=now,
})))
assert(AwaitMutation(Nexus.DataRetention.ReleaseSupersededAutoBuild("superseded", NexusDB))
    and overlay.superseded == nil,
    "direct superseded-page cleanup did not remove an unreferenced remote page")

local markerAge = 30 * 24 * 60 * 60
assert(AwaitMutation(Nexus.BuildCatalog.Put({
    id="old-evicted-today",title="Old revision evicted today",author="Remote",
    autoDps=true,lastModified=now - 90 * 24 * 60 * 60,
})))
assert(AwaitMutation(Nexus.DataRetention.ReleaseSupersededAutoBuild(
        "old-evicted-today", NexusDB)),
    "old remote build was not evicted")
local freshMarker = H.DurablePayload("communityRetentionEvictions")["old-evicted-today"]
assert(type(freshMarker) == "table" and freshMarker.schemaVersion == 1
        and freshMarker.receiptAtServerTime == now,
    "eviction barrier did not record its trusted local creation time")
Enforce(NexusDB, "same-pass marker aging")
assert(H.DurablePayload("communityRetentionEvictions")["old-evicted-today"] ~= nil,
    "new marker for an old revision expired in its creation pass")
now = now + markerAge - 1
Enforce(NexusDB, "marker before expiry")
assert(H.DurablePayload("communityRetentionEvictions")["old-evicted-today"] ~= nil,
    "marker expired before its creation-time lifetime")
now = now + 2
Enforce(NexusDB, "marker after expiry")
assert(H.DurablePayload("communityRetentionEvictions")["old-evicted-today"] == nil,
    "marker did not expire according to creation time")
now = 2000000000

local again = Enforce(NexusDB, "idempotence")
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
            ownerVerified=true,buildId="same",fingerprint="1x1",
            echoes={{spellId=1,stacks=1}},lockedEchoes={},dps=10}},
        lk={b={player="Twin",ownerKey="twin@realmb",realm="realmb",
            ownerVerified=true,buildId="same",fingerprint="1x1",
            echoes={{spellId=1,stacks=1}},lockedEchoes={},dps=20}},
    }},
}
local crossSummary = Nexus.DataRetention.Enforce(crossRealm, "realm identity")
assert(crossSummary.selectedAverage == 0,
    "same-name players from different realms were cross-paired for Average")

local sameRealm = {
    settings=crossRealm.settings,communityBuilds={},syncTombstones={},
    dpsCapture={personalBest={},buildBest={},characterBest={
        dummy={a={player="Twin",ownerKey="twin@realma",realm="realma",
            ownerVerified=true,buildId="same",fingerprint="1x1",
            echoes={{spellId=1,stacks=1}},lockedEchoes={},dps=10}},
        lk={b={player="Twin",ownerKey="twin@realma",realm="realma",
            ownerVerified=true,buildId="same",fingerprint="1x1",
            echoes={{spellId=1,stacks=1}},lockedEchoes={},dps=20}},
    }},
}
local sameRealmSummary = Nexus.DataRetention.Enforce(
    sameRealm, "same realm identity control")
assert(sameRealmSummary.selectedAverage == 1,
    "otherwise-valid same-realm pair did not qualify for Average")

local nonfinitePair = {
    settings=crossRealm.settings,communityBuilds={},syncTombstones={},
    dpsCapture={personalBest={},buildBest={},characterBest={
        dummy={a={player="Hostile",ownerKey="hostile@realma",
            ownerVerified=true,realm="realma",buildId="same",
            fingerprint="same",lockedEchoes={},dps=math.huge}},
        lk={b={player="Hostile",ownerKey="hostile@realma",
            ownerVerified=true,realm="realma",buildId="same",
            fingerprint="same",lockedEchoes={},dps=20}},
    }},
}
local nonfiniteSummary = Nexus.DataRetention.Enforce(
    nonfinitePair, "nonfinite pair")
assert(nonfiniteSummary.selectedAverage == 0,
    "nonfinite DPS influenced Average retention")

local hugeFinitePair = {
    settings=crossRealm.settings,communityBuilds={},syncTombstones={},
    dpsCapture={personalBest={},buildBest={},characterBest={
        dummy={a={player="Huge",ownerKey="huge@realma",
            ownerVerified=true,realm="realma",buildId="same",
            fingerprint="1x1",echoes={{spellId=1,stacks=1}},
            lockedEchoes={},dps=1e308}},
        lk={b={player="Huge",ownerKey="huge@realma",
            ownerVerified=true,realm="realma",buildId="same",
            fingerprint="1x1",echoes={{spellId=1,stacks=1}},
            lockedEchoes={},dps=1e308}},
    }},
}
local hugeFiniteSummary = Nexus.DataRetention.Enforce(
    hugeFinitePair, "overflow-safe finite pair")
assert(hugeFiniteSummary.selectedAverage == 1
        and hugeFinitePair.dpsCapture.characterBest.dummy.a ~= nil
        and hugeFinitePair.dpsCapture.characterBest.lk.b ~= nil,
    "finite overflow-sized pair was lost by Average retention")

local clockDuplicatePair = {
    settings={communityRetentionEnabled=true,
        communityRetentionTopPerCategory=0,
        communityRetentionMinPerClassPerCategory=0,
        communityRetentionTopAverage=1,
        communityRetentionMinAveragePerClass=0,
        communityRetentionOtherRemoteBuilds=0,
        communityRetentionMaxPerAuthor=1},
    communityBuilds={},syncTombstones={},
    dpsCapture={personalBest={},buildBest={},characterBest={
        dummy={old={player="Clock",ownerKey="clock@realma",
            ownerVerified=true,fingerprint="1x1",
            echoes={{spellId=1,stacks=1}},lockedEchoes={},dps=100,ts=1},
            new={player="Clock",ownerKey="clock@realma",
            ownerVerified=true,fingerprint="1x1",
            echoes={{spellId=1,stacks=1}},lockedEchoes={},dps=100,ts=2}},
        lk={one={player="Clock",ownerKey="clock@realma",
            ownerVerified=true,fingerprint="1x1",
            echoes={{spellId=1,stacks=1}},lockedEchoes={},dps=200,ts=3}},
    }},
}
local clockDuplicateSummary = Nexus.DataRetention.Enforce(
    clockDuplicatePair, "clock-only duplicate pair")
assert(clockDuplicateSummary.selectedAverage == 1
        and clockDuplicatePair.dpsCapture.characterBest.lk.one ~= nil
        and (clockDuplicatePair.dpsCapture.characterBest.dummy.old ~= nil
            or clockDuplicatePair.dpsCapture.characterBest.dummy.new ~= nil),
    "clock-neutral projection lost the accepted real pair during retention")

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
    H.AdmitCatalogV1(database, {schemaVersion=1,
        catalogVersion="typed",sourceVersion="test",builds={}})
    Nexus.DataRetention.Enforce(database, "typed ID reference")
    return database
end
-- Legacy-to-bundle cutover: retention publishes through the catalog owner, so
-- the surviving typed slot is observed in the durable bundle payload.
local numericReference = TypedReferenceFixture(1)
assert(H.DurableBuilds(numericReference)[1] ~= nil
        and H.DurableBuilds(numericReference)["1"] == nil,
    "numeric build reference did not protect only numeric ID 1")
local stringReference = TypedReferenceFixture("1")
assert(H.DurableBuilds(stringReference)["1"] ~= nil
        and H.DurableBuilds(stringReference)[1] == nil,
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
        -- MASTER-RC-008: `unlimited` is a fixture table, not the bound
        -- authority, so its raw communityRetentionEvictions marker is a claim
        -- and grants no veto (architecture line 188; RAW-01 forbids treating a
        -- detached instance as authority). Both ids are therefore admissible.
        -- Real suppression comes from the bound authority's barrier, proven
        -- against the bound NexusDB earlier in this file.
        and Nexus.DataRetention.AllowsRemoteRevision(
            "Peer",1,unlimited,"unrelated-disabled")
        and Nexus.DataRetention.AllowsRemoteRevision(
            "Peer",now,unlimited,"disabled-exact-marker"),
    "disabled retention still capped build or DPS content")

print("bounded community/DPS retention and tombstone compaction -- OK")
