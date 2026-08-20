-- Ordered exact-evidence compaction at realistic account-library scale.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")

local Store = Nexus.Store
local Catalog = Nexus.BuildCatalog
local Evidence = Nexus.LoadoutEvidence
local Compaction = Nexus.DataCompaction
local Sync = Nexus.Sync
local clock = 1000
GetTime = function() return clock end
time = function() return 50000 end
UnitName = function() return "Compactor" end
GetNormalizedRealmName = function() return "Ebonhold" end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[DeepCopy(key, seen)] = DeepCopy(child, seen)
    end
    return out
end

local function DeepEqual(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    seen = seen or {}
    if seen[left] then return seen[left] == right end
    seen[left] = right
    for key, value in pairs(left) do
        if not DeepEqual(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function BuildEchoes(group)
    local rows = {}
    for index = 1, 6 do
        rows[index] = {
            spellId=300000 + group * 10 + index,
            quality=(index % 4), stacks=(index % 3) + 1,
        }
    end
    return rows
end

local function Fingerprint(echoes)
    local counts = {}
    for _, echo in ipairs(echoes or {}) do
        if not echo.locked then
            counts[echo.spellId] = (counts[echo.spellId] or 0)
                + (echo.stacks or echo.count or 1)
        end
    end
    local ids = {}
    for spellId in pairs(counts) do ids[#ids + 1] = spellId end
    table.sort(ids)
    local parts = {}
    for _, spellId in ipairs(ids) do
        parts[#parts + 1] = tostring(spellId) .. "x" .. tostring(counts[spellId])
    end
    return table.concat(parts, ",")
end

local builds = {}
for index = 1, 1000 do
    local id = string.format("scale-%04d", index)
    local echoes = BuildEchoes(((index - 1) % 25) + 1)
    builds[id] = {
        id=id, title="Scale " .. tostring(index), author="Compactor",
        ownerKey="compactor@ebonhold", class="MAGE",
        postedAt=index, lastModified=index,
        autoDps=index <= 557 and true or nil,
        fingerprint=Fingerprint(echoes), fingerprintHash="shared-short",
        echoes=echoes, isMine=index % 10 == 0,
    }
end

-- Three rows are deliberately unprovable and must remain inline.
builds["scale-0998"].echoes = {
    builds["scale-0998"].echoes[2], builds["scale-0998"].echoes[1],
}
builds["scale-0998"].fingerprint = Fingerprint(builds["scale-0998"].echoes)
builds["scale-0999"].evidenceKey = "v1|claimed:0:1:0"
builds["scale-1000"].echoes = {{spellId=0,quality=3,stacks=1}}
builds["scale-1000"].fingerprint = "0x1"

local personalBest = {}
for index = 1, 200 do
    local echoes = {
        {spellId=400000 + (index % 20), count=2},
        {spellId=400100 + (index % 20), count=1},
    }
    local fingerprint = Fingerprint(echoes)
    personalBest[fingerprint .. ":" .. tostring(index)] = {dummy={
        dps=1000000 + index, duration=60, ts=index, player="P" .. index,
        class="MAGE", level=80, fingerprint=fingerprint, echoes=echoes,
    }}
end
local characterBest = {dummy={}, lk={}}
for index = 1, 80 do
    local echoes = {
        {spellId=410000 + (index % 10), count=2},
        {spellId=410100 + (index % 10), count=1},
    }
    local fingerprint = Fingerprint(echoes)
    characterBest.dummy["p" .. index] = {
        dps=2000000 + index, duration=60, ts=index,
        player="P" .. index, class="MAGE", level=80,
        fingerprint=fingerprint, echoes=echoes,
        lockedEchoes={{spellId=420000 + (index % 5), count=1}},
    }
end

local filters = {scope="mine", classFilter="MAGE", sortMode="recent"}
local tombstones = {gone={stamp=9000, author="Compactor"}}
Nexus.BundledBuilds = {
    schemaVersion=1, catalogVersion="compaction-scale", sourceVersion="test",
    builds={},
}
NexusDB = {
    settingsVersion=2, settings={}, chars={},
    communityBuilds=builds, syncTombstones=tombstones,
    buildFilters=filters,
    dpsCapture={
        personalBest=personalBest, buildBest={}, characterBest=characterBest,
    },
}

local expectedBuild = DeepCopy(builds["scale-0001"].echoes)
local _, samplePersonal = next(personalBest)
local expectedDps = DeepCopy(samplePersonal.dummy.echoes)
Store.Init()
local firstPump = Compaction.Stats()
assert(firstPump.pending == true
    and firstPump.lastPumpWork <= firstPump.workBudget
    and firstPump.overlayRecordsBefore < 1000,
    "large migration was not deferred after one bounded startup pump")
local concurrentEdit = assert(Catalog.Get("scale-0001"))
concurrentEdit.title = "Scale 1 edited during migration"
concurrentEdit.lastModified = 70001
assert(Catalog.Put(concurrentEdit),
    "concurrent catalog edit was refused during compaction")
local migrationPumps = 1
while Compaction.Stats().pending do
    local _, completed = Compaction.Pump()
    migrationPumps = migrationPumps + 1
    assert(migrationPumps < 10000,
        "incremental compaction did not converge")
    if completed then break end
end
local stats = Compaction.Stats()
print(string.format(
    "compaction migration stats: overlay=%s/%s dps=%s/%s arrays=%s removed=%s retained=%s/%s/%s pumps=%s max=%s",
    tostring(stats.overlayRecordsBefore), tostring(stats.overlayRecordsAfter),
    tostring(stats.dpsRecordsBefore), tostring(stats.dpsRecordsAfter),
    tostring(stats.arraysCompacted), tostring(stats.removedInlineEchoRows),
    tostring(stats.retainedMalformed), tostring(stats.retainedConflicts),
    tostring(stats.retainedNonCanonical),tostring(stats.pumps),
    tostring(stats.maxPumpWork)))
assert(NexusDB.dataCompaction.version == 1
    and stats.overlayRecordsBefore == 1000
    and stats.overlayRecordsAfter == 1000
    and stats.dpsRecordsBefore == 280
    and stats.dpsRecordsAfter == 280
    and stats.recordCountsUnchanged
    and stats.pending == false
    and stats.maxPumpWork <= stats.workBudget
    and stats.restarts >= 1,
    "scale migration changed build or DPS record counts")
assert(stats.arraysCompacted >= 1275
    and stats.removedInlineEchoRows > 6000
    and stats.poolEntriesAfter < stats.arraysCompacted,
    "scale migration did not collapse duplicate inline Echo storage")

local autoPages, records = 0, 0
for _, build in pairs(NexusDB.communityBuilds) do
    records = records + 1
    if build.autoDps then autoPages = autoPages + 1 end
end
assert(records == 1000 and autoPages == 557,
    "automatic page or build retention changed during compaction")
assert(NexusDB.buildFilters == filters and NexusDB.syncTombstones == tombstones,
    "filters or authorized tombstones changed during compaction")
assert(NexusDB.communityBuilds["scale-0001"].echoes == nil
    and Catalog.Get("scale-0001").title == "Scale 1 edited during migration"
    and DeepEqual(Catalog.Get("scale-0001").echoes, expectedBuild),
    "canonical build did not hydrate exactly after inline removal")
local _, firstPersonal = next(NexusDB.dpsCapture.personalBest)
assert(firstPersonal.dummy.echoes == nil
    and DeepEqual(Evidence.ResolveDpsEchoes(firstPersonal.dummy), expectedDps),
    "canonical DPS row did not hydrate exactly after inline removal")
assert(NexusDB.communityBuilds["scale-0998"].echoes
    and NexusDB.communityBuilds["scale-0999"].echoes
    and NexusDB.communityBuilds["scale-1000"].echoes
    and stats.retainedNonCanonical >= 1
    and stats.retainedConflicts >= 1
    and stats.retainedMalformed >= 1,
    "unprovable rows were compacted or not counted")

-- The migration stamp makes repeat Store.Init byte-for-byte stable.
local beforeRepeat = DeepCopy(NexusDB)
Store.Init()
assert(DeepEqual(beforeRepeat, NexusDB),
    "repeat Store.Init changed an already compacted database")

-- New canonical writes compact immediately after the migration is enabled.
local newEchoes = {{spellId=499001,quality=3,stacks=2}}
assert(Catalog.Put({
    id="new-after-migration", title="New", author="Compactor",
    ownerKey="compactor@ebonhold", class="MAGE", postedAt=60000,
    lastModified=60000, fingerprint=Fingerprint(newEchoes), echoes=newEchoes,
}))
assert(NexusDB.communityBuilds["new-after-migration"].echoes == nil
    and DeepEqual(Catalog.Get("new-after-migration").echoes, newEchoes),
    "post-migration build writes retained duplicate inline evidence")

local newDps = {
    dps=3000000, duration=60, ts=60000, player="New",
    class="MAGE", level=80, fingerprint="499002x1",
    echoes={{spellId=499002,count=1}},
}
assert(Compaction.CompactDpsRow(newDps)
    and newDps.echoes == nil
    and Evidence.ResolveDpsEchoes(newDps)[1].spellId == 499002,
    "post-migration DPS writes retained duplicate inline evidence")

-- GC preserves durable owners and transient retry providers, blocks on a
-- failed provider, then removes only evidence proven unreachable.
local durableReference = NexusDB.communityBuilds["scale-0001"].evidenceKey
Sync.Init(Nexus.Codec, {})
local retryEchoes = {{spellId=499900,quality=3,stacks=1}}
assert(Catalog.Put({
    id="outgoing-retry", title="Retry", author="Compactor",
    ownerKey="compactor@ebonhold", class="MAGE", postedAt=60001,
    lastModified=60001, fingerprint=Fingerprint(retryEchoes),
    echoes=retryEchoes,
}))
local retryReference = NexusDB.communityBuilds["outgoing-retry"].evidenceKey
assert(Sync.BroadcastBuild(Catalog.Get("outgoing-retry"))
    and Catalog.RemoveOverlay("outgoing-retry"),
    "outgoing retry fixture did not enter Sync's retained hot-build path")
local gcWithRetry = Compaction.CollectGarbage(NexusDB)
assert(not gcWithRetry.blocked
    and Evidence.Snapshot()[durableReference]
    and Evidence.Snapshot()[retryReference],
    "GC removed durable or outgoing-retry evidence")
local orphanReference = Evidence.Intern({{spellId=499901,stacks=1}})
Evidence.RegisterReferenceProvider("test.failure", function()
    error("forced provider failure")
end)
local blockedGc = Compaction.CollectGarbage(NexusDB)
assert(blockedGc.blocked and Evidence.Snapshot()[orphanReference],
    "GC deleted evidence after an incomplete reference scan")
Evidence.RegisterReferenceProvider("test.failure", nil)
Sync.Init(Nexus.Codec, {}) -- clears the hot-build retry owner and its queue
local finalGc = Compaction.CollectGarbage(NexusDB)
assert(not finalGc.blocked and finalGc.removed >= 2
    and Evidence.Snapshot()[durableReference]
    and not Evidence.Snapshot()[retryReference]
    and not Evidence.Snapshot()[orphanReference],
    "reference-aware GC did not remove only unreachable evidence")

-- A newer compaction owner is completely read-only.
local futureDb = {
    communityBuilds={}, dpsCapture={},
    dataCompaction={schemaVersion=99, version=0, marker={keep=true}},
}
local futureBefore = DeepCopy(futureDb)
local futureResult = Compaction.Init(futureDb)
assert(futureResult.blocked and DeepEqual(futureBefore, futureDb),
    "future compaction schema was modified")

-- A self-verifying key occupied by conflicting stored evidence cannot justify
-- deleting the independently exact inline array.
local collisionEchoes = {{spellId=499940,quality=3,stacks=1}}
local collisionKey = Evidence.Fingerprint(collisionEchoes)
local collisionDb = {
    loadoutEvidence={schemaVersion=1, entries={
        [collisionKey]={{spellId=499941,quality=3,stacks=1}},
    }},
    communityBuilds={collision={
        id="collision", fingerprint=Fingerprint(collisionEchoes),
        evidenceKey=collisionKey, echoes=DeepCopy(collisionEchoes),
    }},
    dpsCapture={},
}
NexusDB = collisionDb
Evidence.Init(collisionDb)
Catalog.Init(collisionDb, Nexus.BundledBuilds)
local collisionResult = Compaction.Init(collisionDb)
assert(not collisionResult.blocked
    and collisionResult.retainedConflicts == 1
    and collisionDb.communityBuilds.collision.echoes
    and collisionDb.loadoutEvidence.entries[collisionKey][1].spellId == 499941,
    "stored evidence collision replaced or compacted independent inline data")

-- A failure after row compaction but before the version stamp is resumable.
-- The first pass leaves a valid reference, and the next init completes from
-- that partial state without losing or duplicating the represented loadout.
local interruptEchoes = {{spellId=499950,quality=3,stacks=2}}
local interruptedDb = {communityBuilds={interrupt={
    id="interrupt", title="Interrupt", author="Compactor",
    ownerKey="compactor@ebonhold", class="MAGE", postedAt=60002,
    lastModified=60002, fingerprint=Fingerprint(interruptEchoes),
    echoes=DeepCopy(interruptEchoes),
}}, dpsCapture={}}
NexusDB = interruptedDb
Evidence.Init(interruptedDb)
Catalog.Init(interruptedDb, Nexus.BundledBuilds)
Evidence.RegisterReferenceProvider("test.interrupt", function()
    error("forced migration interruption")
end)
local interruptedResult = Compaction.Init(interruptedDb)
assert(interruptedResult.blocked
    and not interruptedDb.dataCompaction.version
    and interruptedDb.communityBuilds.interrupt.echoes == nil
    and interruptedDb.communityBuilds.interrupt.evidenceKey,
    "failed migration did not leave a safe resumable partial state")
Evidence.RegisterReferenceProvider("test.interrupt", nil)
local resumedResult, resumed = Compaction.Init(interruptedDb)
local resumeGuard = 0
while Compaction.Stats(interruptedDb).pending do
    resumedResult, resumed = Compaction.Pump()
    resumeGuard = resumeGuard + 1
    assert(resumeGuard < 100,
        "interrupted migration did not finish its bounded verification pass")
end
assert(resumed and not resumedResult.blocked
    and interruptedDb.dataCompaction.version == 1
    and DeepEqual(Catalog.Get("interrupt").echoes, interruptEchoes),
    "interrupted migration did not resume to exact hydrated evidence")

-- A later bundled-catalog version can still identify and prune an exact
-- redundant overlay after the overlay's inline evidence has been compacted.
local promoted = Catalog.Get("interrupt")
Catalog.Init(interruptedDb, {
    schemaVersion=1, catalogVersion="post-compaction-promotion",
    sourceVersion="test", builds={interrupt=promoted},
})
assert(interruptedDb.communityBuilds.interrupt == nil
    and DeepEqual(Catalog.Get("interrupt").echoes, interruptEchoes),
    "pool-only redundant overlay survived a later baseline promotion")

print(string.format(
    "data compaction: builds=%d auto=%d DPS=%d rows removed=%d pool=%d -- OK",
    records, autoPages, stats.dpsRecordsAfter,
    stats.removedInlineEchoRows, stats.poolEntriesAfter))
