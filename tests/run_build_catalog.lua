local H = dofile("tests/harness.lua")
dofile("data/BundledBuilds.lua")
dofile("core/BuildCatalog.lua")

local baseline = {
    schemaVersion = 1,
    catalogVersion = "test-1",
    sourceVersion = "test",
    builds = {
        base = { id="base", title="Bundled", author="A", postedAt=10,
            lastModified=10, echoes={{spellId=1,stacks=1}} },
        newer = { id="newer", title="Bundled newer", author="A", postedAt=20,
            lastModified=20, echoes={{spellId=2,stacks=1}} },
        deleted = { id="deleted", title="Deleted", author="A", postedAt=10,
            lastModified=10, echoes={{spellId=3,stacks=1}} },
    },
}

local database = {
    communityBuilds = {
        base = { id="base", title="Overlay", author="A", postedAt=10,
            lastModified=11, echoes={{spellId=1,stacks=2}} },
        newer = { id="newer", title="Stale overlay", author="A", postedAt=5,
            lastModified=5, echoes={{spellId=2,stacks=1}} },
        personal = { id="personal", title="Mine", author="Me", isMine=true,
            postedAt=1, lastModified=1, echoes={{spellId=4,stacks=1}} },
    },
    syncTombstones = { deleted={stamp=30,author="A"} },
}

local summary = Nexus.BuildCatalog.Init(database, baseline)
assert(summary.bundled == 3 and summary.overlay == 3,
    "initial migration counts are wrong")
assert(summary.redundantRemoved == 0,
    "a differing legacy overlay was pruned")

local build, source = Nexus.BuildCatalog.Get("base")
assert(build and build.title == "Overlay" and source == "overlay",
    "newer overlay did not win")
build.title = "mutated caller copy"
build.echoes[1].stacks = 99
local again = Nexus.BuildCatalog.Get("base")
assert(again.title == "Overlay" and again.echoes[1].stacks == 2,
    "Get exposed mutable catalog storage")

build, source = Nexus.BuildCatalog.Get("newer")
assert(build and build.title == "Bundled newer" and source == "bundled",
    "newer bundled row did not replace a stale overlay")
assert(Nexus.BuildCatalog.Get("deleted") == nil,
    "tombstone did not hide the bundled row")

local delta = Nexus.BuildCatalog.DeltaSnapshot()
assert(delta.base and delta.personal and not delta.newer and not delta.deleted,
    "delta snapshot included bundled, stale, or tombstoned rows")
delta.base.title = "mutated delta copy"
assert(Nexus.BuildCatalog.Get("base").title == "Overlay",
    "DeltaSnapshot exposed mutable overlay storage")

assert(Nexus.BuildCatalog.Put({ id="deleted", title="Resurrection attempt",
    postedAt=50, lastModified=50, echoes={{spellId=3,stacks=2}} }))
assert(Nexus.BuildCatalog.Get("deleted") == nil,
    "Put implicitly cleared an authorized tombstone")
assert(Nexus.BuildCatalog.Count() == 3,
    "merged catalog count should include two visible baseline rows and personal")

local all = Nexus.BuildCatalog.All()
all.newer.title = "mutated snapshot"
assert(Nexus.BuildCatalog.Get("newer").title == "Bundled newer",
    "All exposed mutable bundled storage")

local incoming = { id="copy", title="Copied", postedAt=40, lastModified=40,
    echoes={{spellId=5,stacks=1}} }
assert(Nexus.BuildCatalog.Put(incoming))
incoming.title = "changed after Put"
assert(Nexus.BuildCatalog.Get("copy").title == "Copied",
    "Put retained the caller's mutable table")

local baselineEquivalent = {
    id="newer", title="Bundled newer", author="A", postedAt=20,
    lastModified=20, echoes={{spellId=2,quality=0,stacks=1}},
    echoCount=1, loadoutAvailable=true,
}
local putOk, putTarget = Nexus.BuildCatalog.Put(baselineEquivalent)
assert(putOk and putTarget == "baseline"
    and database.communityBuilds.newer == nil,
    "canonical baseline-equivalent Put was persisted in the overlay")

assert(Nexus.BuildCatalog.SetTombstone("copy", {stamp=41,author="Me"}))
assert(Nexus.BuildCatalog.Get("copy") == nil,
    "SetTombstone did not hide and remove the overlay row")
assert(Nexus.BuildCatalog.ClearTombstone("copy"))
assert(Nexus.BuildCatalog.Get("copy") == nil,
    "clearing a tombstone unexpectedly restored a removed overlay")

print("BuildCatalog precedence and defensive copies -- OK")
