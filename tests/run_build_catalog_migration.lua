local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("data/BundledBuilds.lua")
dofile("core/BuildCatalog.lua")
dofile("core/Store.lua")

Nexus.BundledBuilds = {
    schemaVersion = 1,
    catalogVersion = "migration-1",
    sourceVersion = "test",
    builds = {
        equal = { id="equal", title="Same", author="A", postedAt=10,
            lastModified=10, echoes={{spellId=1,stacks=1}} },
        newer = { id="newer", title="Bundled old", author="A", postedAt=10,
            lastModified=10, echoes={{spellId=2,stacks=1}} },
        oldremote = { id="oldremote", title="Bundled current", author="A",
            postedAt=20, lastModified=20, echoes={{spellId=3,stacks=1}} },
        personal = { id="personal", title="Bundled current", author="Me",
            postedAt=20, lastModified=20, echoes={{spellId=4,stacks=1}} },
        ownerOnly = { id="ownerOnly", title="Bundled owner copy", author="Boganic",
            ownerKey="boganic@ebonhold", postedAt=20, lastModified=20,
            echoes={{spellId=6,stacks=1}} },
    },
}

local filters = { scope="mine", classFilter="MAGE", sortMode="recent" }
local dps = { personalBest={keep=true}, buildBest={keep=true} }
local tombstones = { gone={stamp=50,author="A"} }
NexusDB = {
    settingsVersion = 1,
    settings = { autoPick=false },
    chars = {},
    buildFilters = filters,
    dpsCapture = dps,
    syncTombstones = tombstones,
    communityBuilds = {
        equal = Nexus.BundledBuilds.builds.equal,
        newer = { id="newer", title="Local newer", author="A", postedAt=30,
            lastModified=30, echoes={{spellId=2,stacks=2}} },
        oldremote = { id="oldremote", title="Stale", author="A", postedAt=5,
            lastModified=5, echoes={{spellId=3,stacks=1}} },
        personal = { id="personal", title="My older copy", author="Me", isMine=true,
            postedAt=5, lastModified=5, echoes={{spellId=4,stacks=1}} },
        ownerOnly = { id="ownerOnly", title="My owner-key copy", author="Boganic",
            ownerKey="boganic@ebonhold", postedAt=5, lastModified=5,
            echoes={{spellId=6,stacks=2}} },
        legacy = { id="legacy", title="Legacy only", author="B", postedAt=7,
            lastModified=7, echoes={{spellId=5,stacks=1}} },
    },
}

local liveUnitName = UnitName
UnitName = function() return nil end
Nexus.Store.Init()
UnitName = liveUnitName
local overlay = NexusDB.communityBuilds
assert(overlay.equal == nil, "baseline-equal legacy row remained in overlay")
assert(overlay.oldremote and overlay.oldremote.title == "Stale",
    "differing older remote row was not preserved losslessly")
assert(overlay.newer and overlay.newer.title == "Local newer",
    "newer legacy revision was not preserved")
assert(overlay.personal and overlay.personal.isMine,
    "personal legacy revision was not preserved")
assert(overlay.ownerOnly and overlay.ownerOnly.ownerKey == "boganic@ebonhold",
    "owner-key personal revision was not preserved")
assert(Nexus.BuildCatalog.Get("ownerOnly").title == "My owner-key copy",
    "owner-key personal revision did not win once player identity was available")
assert(overlay.legacy and overlay.legacy.title == "Legacy only",
    "legacy row absent from the baseline was not preserved")
assert(NexusDB.buildFilters == filters and NexusDB.dpsCapture == dps
    and NexusDB.syncTombstones == tombstones,
    "unrelated filters, DPS, or tombstones changed during migration")
assert(NexusDB.buildCatalog.schemaVersion == 1
    and NexusDB.buildCatalog.catalogVersion == "migration-1",
    "catalog migration metadata was not recorded")

local before = Nexus.BuildCatalog.OverlaySnapshot()
Nexus.Store.Init()
local after = Nexus.BuildCatalog.OverlaySnapshot()
local beforeCount, afterCount = 0, 0
for _ in pairs(before) do beforeCount = beforeCount + 1 end
for _ in pairs(after) do afterCount = afterCount + 1 end
assert(beforeCount == 5 and afterCount == 5,
    "repeated Store.Init was not idempotent")

Nexus.BundledBuilds = {
    schemaVersion=1, catalogVersion="canonical-test", sourceVersion="test",
    builds={
        canonical={id="canonical",title="Canonical",description="",author="Alice",
            ownerKey="alice@realm",class="MAGE",
            echoes={{spellId=10,quality=0,stacks=1}},
            postedAt=10,lastModified=10,fingerprint="10x1",
            fingerprintHash="1",echoCount=1,loadoutAvailable=true},
        personalEqual={id="personalEqual",title="Personal",description="",author="Me",
            ownerKey="me@realm",class="ROGUE",
            echoes={{spellId=11,quality=0,stacks=1}},
            postedAt=11,lastModified=11,fingerprint="11x1",
            fingerprintHash="2",echoCount=1,loadoutAvailable=true},
    },
}
NexusDB = {
    settingsVersion=1,settings={},chars={},syncTombstones={},
    communityBuilds={
        canonical={id="canonical",title="Canonical",description="",author="Alice",
            ownerKey="ALICE@REALM",class="mage",
            echoes={{spellId=10,quality=0,stacks=1}},
            postedAt=10,lastModified=10,fingerprint="10x1",
            fingerprintHash="1",echoCount=1,loadoutAvailable=true,
            isMine=false,ownerVerified=true,needsFullBuild=false,
            _nexusDps={best=123}},
        personalEqual={id="personalEqual",title="Personal",description="",author="Me",
            ownerKey="me@realm",class="ROGUE",
            echoes={{spellId=11,quality=0,stacks=1}},
            postedAt=11,lastModified=11,fingerprint="11x1",
            fingerprintHash="2",echoCount=1,loadoutAvailable=true,isMine=true},
    },
}
Nexus.Store.Init()
assert(NexusDB.communityBuilds.canonical == nil,
    "canonical bundled row with transient cache fields remained in overlay")
assert(NexusDB.communityBuilds.personalEqual
    and NexusDB.communityBuilds.personalEqual.isMine,
    "locally marked row was pruned by canonical migration")

Nexus.BundledBuilds = {
    schemaVersion=1, catalogVersion="empty-test", sourceVersion="test", builds={}
}
NexusDB = {
    settingsVersion=1, settings={}, chars={}, syncTombstones={},
    communityBuilds={
        one={id="one",title="One",postedAt=1,lastModified=1},
        two={id="two",title="Two",postedAt=2,lastModified=2},
    },
}
Nexus.Store.Init()
assert(NexusDB.communityBuilds.one and NexusDB.communityBuilds.two,
    "empty bundled catalog lost legacy community builds")
assert(Nexus.BuildCatalog.Count() == 2,
    "empty bundled catalog did not expose all legacy builds")

-- Downgrading across a newer catalog schema must not erase fields this build
-- cannot understand or stamp the SavedVariables back to schema 1.
local futureMeta = {
    schemaVersion=99, catalogVersion="future-catalog",
    sourceVersion="future-source", futureOwner={marker="keep"},
}
local futureRow = {
    id="future", title="Future", author="Alice", postedAt=10,
    lastModified=10, echoes={{spellId=90,stacks=1}},
    futureOnly={marker="keep"},
}
local futureOverlay = {future=futureRow}
local futureTombstones = {gone={stamp=50,author="Alice",futureOnly=true}}
local futureDb = {
    buildCatalog=futureMeta,
    communityBuilds=futureOverlay,
    syncTombstones=futureTombstones,
}
local futureBundle = {
    schemaVersion=1, catalogVersion="downgrade-catalog", sourceVersion="old",
    builds={
        future={id="future",title="Future",author="Alice",postedAt=10,
            lastModified=10,echoes={{spellId=90,stacks=1}}},
    },
}
NexusDB = futureDb
Nexus.BundledBuilds = futureBundle
local compactionCalls = 0
Nexus.DataCompaction = {Init=function(database)
    compactionCalls = compactionCalls + 1
    database.communityBuilds.future = nil
end}
Nexus.Store.Init()
local futureSummary = Nexus.BuildCatalog.Init(futureDb, futureBundle)
assert(futureSummary.readOnly and not futureSummary.migrated
    and futureSummary.schemaVersion == 99
    and futureSummary.redundantRemoved == 0,
    "future catalog schema was not bound read-only")
assert(futureDb.buildCatalog == futureMeta
    and futureMeta.catalogVersion == "future-catalog"
    and futureMeta.futureOwner.marker == "keep",
    "future catalog metadata was rewritten during downgrade")
assert(futureDb.communityBuilds == futureOverlay
    and futureOverlay.future == futureRow
    and futureRow.futureOnly.marker == "keep",
    "future overlay row was pruned or rewritten during downgrade")
assert(compactionCalls == 0,
    "startup compaction mutated a future catalog overlay")
local ok, reason = Nexus.BuildCatalog.Put({id="blocked",title="Blocked"})
assert(not ok and reason == "future build catalog schema is read-only"
    and futureOverlay.blocked == nil,
    "future catalog accepted an overlay write")
ok, reason = Nexus.BuildCatalog.RemoveOverlay("future")
assert(not ok and reason == "future build catalog schema is read-only"
    and futureOverlay.future == futureRow,
    "future catalog accepted an overlay removal")
ok, reason = Nexus.BuildCatalog.SetTombstone("future", {stamp=99})
assert(not ok and reason == "future build catalog schema is read-only"
    and futureTombstones.future == nil,
    "future catalog accepted a tombstone write")
ok, reason = Nexus.BuildCatalog.ClearTombstone("gone")
assert(not ok and reason == "future build catalog schema is read-only"
    and futureTombstones.gone.futureOnly,
    "future catalog accepted a tombstone removal")

local writableDb = {communityBuilds={},syncTombstones={}}
NexusDB = writableDb
Nexus.BuildCatalog.Init(writableDb, futureBundle)
assert(Nexus.BuildCatalog.Put({id="writable",title="Writable"})
    and writableDb.communityBuilds.writable,
    "read-only guard survived rebinding to a supported schema")

print("BuildCatalog migration preserved data and is idempotent -- OK")
