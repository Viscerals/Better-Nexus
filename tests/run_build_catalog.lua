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
            lastModified=11, ownerKey="a@realma",realm="realma",
            ownerVerified=true,echoes={{spellId=1,stacks=2}} },
        newer = { id="newer", title="Stale overlay", author="A", postedAt=5,
            lastModified=5, echoes={{spellId=2,stacks=1}} },
        personal = { id="personal", title="Mine", author="Me", isMine=true,
            ownerKey="me@realma",realm="realma",ownerVerified=true,
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

assert(Nexus.BuildCatalog.Put({id="delta-unverified",title="Unverified",
    author="Peer",ownerKey="peer@realma",realm="realma",
    postedAt=12,lastModified=12,echoes={{spellId=6,stacks=1}}}))
assert(Nexus.BuildCatalog.Put({id="delta-saved",title="Private Saved",
    author="Me",ownerKey="me@realma",realm="realma",ownerVerified=true,
    importedSavedBuild=true,isMine=true,serverSlot=1,
    postedAt=13,lastModified=13,echoes={{spellId=7,stacks=1}}}))
local authorityDelta = Nexus.BuildCatalog.DeltaSnapshot()
assert(authorityDelta["delta-unverified"] == nil
        and authorityDelta["delta-saved"] == nil,
    "EXPECTED RED: unverified or private Saved rows entered Sync delta state")
assert(Nexus.BuildCatalog.RemoveOverlay("delta-unverified")
        and Nexus.BuildCatalog.RemoveOverlay("delta-saved"),
    "authority delta fixtures were not removed cleanly")

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

local allocationDb = {
    communityBuilds={
        opaque="future-owned-row",
        booleanOpaque=false,
        opaqueBundled="future-owned-bundled-row",
        malformed={title="Missing durable identity",author="Twin",
            future={keep=true}},
        malformedTwin={title="Second missing identity",author="Twin",
            future={keep=true}},
        mismatched={id="different-id",future={keep=true}},
        slotA={id="shared",title="Contradictory A",author="Ghost",
            ownerKey="twin@realma",realm="realma",ownerVerified=true,
            class="MAGE",fingerprint="96x1",
            echoes={{spellId=96,stacks=1}}},
        slotB={id="shared",title="Contradictory B",author="Phantom",
            ownerKey="twin@realma",realm="realma",ownerVerified=true,
            class="MAGE",fingerprint="97x1",
            echoes={{spellId=97,stacks=1}}},
        visible={id="visible",title="Visible",echoes={{spellId=91,stacks=1}}},
        shadowed={id="shadowed",title="Overlay on bundled ID",
            echoes={{spellId=93,stacks=2}}},
    },
    syncTombstones={
        tombstoned={stamp=93,future={keep=true}},
    },
}
local allocationBundle = {
    schemaVersion=1,catalogVersion="allocation-1",sourceVersion="test",
    builds={
        bundled={id="bundled",title="Bundled allocation",
            echoes={{spellId=92,stacks=1}}},
        shadowed={id="shadowed",title="Bundled shadow target",
            echoes={{spellId=93,stacks=1}}},
        opaqueBundled={id="opaqueBundled",title="Opaque shadow target",
            echoes={{spellId=94,stacks=1}}},
        tombstoned={id="tombstoned",title="Tombstone target",
            echoes={{spellId=95,stacks=1}}},
    },
}
local allocationSummary = Nexus.BuildCatalog.Init(allocationDb, allocationBundle)
local occupancy, represented =
    Nexus.BuildCatalog.AllocationOccupancy("absent")
assert(occupancy == "absent" and represented == nil,
    "truly absent allocation ID was not distinguished")
occupancy, represented = Nexus.BuildCatalog.AllocationOccupancy("opaque")
assert(occupancy == "opaque" and represented == nil
    and allocationDb.communityBuilds.opaque == "future-owned-row",
    "opaque raw overlay evidence was exposed, cleared, or reported free")
occupancy, represented = Nexus.BuildCatalog.AllocationOccupancy("booleanOpaque")
assert(occupancy == "opaque" and represented == nil
    and allocationDb.communityBuilds.booleanOpaque == false,
    "false raw overlay evidence was cleared or reported free")
occupancy, represented = Nexus.BuildCatalog.AllocationOccupancy("malformed")
assert(occupancy == "opaque" and represented == nil
    and allocationDb.communityBuilds.malformed.future.keep == true,
    "malformed raw overlay evidence was exposed, cleared, or reported free")
occupancy, represented = Nexus.BuildCatalog.AllocationOccupancy("mismatched")
assert(occupancy == "opaque" and represented == nil
    and allocationDb.communityBuilds.mismatched.id == "different-id"
    and allocationDb.communityBuilds.mismatched.future.keep == true,
    "mismatched raw overlay evidence was exposed, cleared, or reported free")
occupancy, represented = Nexus.BuildCatalog.AllocationOccupancy("visible")
assert(occupancy == "visible" and represented
    and represented.id == "visible" and represented.title == "Visible",
    "represented overlay row was not distinguished from opaque evidence")
represented.title = "caller mutation"
represented.echoes[1].stacks = 99
assert(allocationDb.communityBuilds.visible.title == "Visible"
    and allocationDb.communityBuilds.visible.echoes[1].stacks == 1,
    "allocation occupancy exposed mutable overlay storage")
occupancy, represented = Nexus.BuildCatalog.AllocationOccupancy("bundled")
assert(occupancy == "bundled" and represented
    and represented.id == "bundled"
    and represented.title == "Bundled allocation",
    "bundled allocation ID was reported free or not represented")
represented.title = "caller mutation"
represented.echoes[1].stacks = 99
assert(allocationBundle.builds.bundled.title == "Bundled allocation"
    and allocationBundle.builds.bundled.echoes[1].stacks == 1,
    "allocation occupancy exposed mutable bundled storage")
occupancy, represented = Nexus.BuildCatalog.AllocationOccupancy("shadowed")
assert(occupancy == "bundled" and represented
    and represented.id == "shadowed"
    and represented.title == "Overlay on bundled ID",
    "a represented overlay made an immutable bundled ID allocatable")
represented.title = "caller mutation"
represented.echoes[1].stacks = 99
assert(allocationDb.communityBuilds.shadowed.title == "Overlay on bundled ID"
    and allocationDb.communityBuilds.shadowed.echoes[1].stacks == 2
    and allocationBundle.builds.shadowed.title == "Bundled shadow target",
    "shadowed bundled occupancy exposed mutable storage")
occupancy, represented = Nexus.BuildCatalog.AllocationOccupancy("opaqueBundled")
assert(occupancy == "opaque" and represented == nil
    and allocationDb.communityBuilds.opaqueBundled
        == "future-owned-bundled-row"
    and allocationBundle.builds.opaqueBundled.title == "Opaque shadow target",
    "opaque evidence on a bundled ID was exposed, cleared, or misclassified")
occupancy, represented = Nexus.BuildCatalog.AllocationOccupancy("tombstoned")
assert(occupancy == "tombstone" and represented == nil
    and allocationDb.syncTombstones.tombstoned.stamp == 93
    and allocationDb.syncTombstones.tombstoned.future.keep == true
    and allocationBundle.builds.tombstoned.title == "Tombstone target",
    "tombstone evidence was exposed, cleared, or reported free")

-- A malformed historical row can be retained under a durable typed map key
-- without carrying an id field.  The resumable public summary restores that
-- key so distinct records cannot receive the same presentation identity.
local cursor = Nexus.BuildCatalog.BeginSummaryCursor()
local summaries = {}
while true do
    local item, done, err = Nexus.BuildCatalog.SummaryCursorNext(cursor)
    assert(not err, err)
    if item then summaries[item.id] = item end
    if done then break end
end
assert(summaries.malformed and summaries.malformed.title
        == "Missing durable identity"
        and summaries.malformedTwin
        and summaries.malformedTwin.title == "Second missing identity"
        and Nexus.Identity.PublicRecordKey(summaries.malformed, "author")
            ~= Nexus.Identity.PublicRecordKey(summaries.malformedTwin, "author"),
    "summary cursor did not restore the durable map key as a missing id")
local syncSummaries = Nexus.BuildCatalog.Summaries()
local exactMalformed = Nexus.BuildCatalog.Get("malformed")
local exactSummary = Nexus.BuildCatalog.GetSummary("malformedTwin")
assert(syncSummaries.malformed.id == "malformed"
        and syncSummaries.malformedTwin.id == "malformedTwin"
        and exactMalformed.id == "malformed"
        and exactSummary.id == "malformedTwin"
        and Nexus.Identity.PublicRecordKey(syncSummaries.malformed, "author")
            ~= Nexus.Identity.PublicRecordKey(
                syncSummaries.malformedTwin, "author"),
    "sync summary or exact hydration lost durable missing-id identity")
assert(syncSummaries.slotA == nil and syncSummaries.slotB == nil
        and Nexus.BuildCatalog.Get("slotA") == nil
        and Nexus.BuildCatalog.GetSummary("slotB") == nil,
    "contradictory embedded IDs escaped opaque public quarantine")
assert(Nexus.BuildCatalog.FindExactFingerprintId("96x1") == nil
        and Nexus.BuildCatalog.ResolveFingerprintIdentity(nil, "96x1") == nil
        and Nexus.BuildCatalog.ResolveOwnerClass({player="Twin",
            ownerKey="twin@realma",realm="realma",ownerVerified=true}) == nil,
    "opaque contradictory IDs entered exact or owner authority indexes")
local slotAVerdict = Nexus.LoadoutEvidence.OrdinaryCompleteness(
    allocationDb.communityBuilds.slotA)
local slotAHash = Nexus.LoadoutEvidence.CompatibilityHash(
    slotAVerdict and slotAVerdict.fingerprint)
assert(slotAHash and Nexus.BuildCatalog.ResolveFingerprintIdentity(
        "slotA", "@" .. slotAHash, {legacyRecord={
            buildId="shared",fingerprint="@" .. slotAHash,
            loadoutHash=slotAHash,echoes={{spellId=96,stacks=1}},
        }}) == nil,
    "opaque contradictory ID supplied legacy fingerprint authority")
assert(Nexus.BuildCatalog.IsAuthor("Twin") == true
        and Nexus.BuildCatalog.IsAuthor("Ghost") == false
        and Nexus.BuildCatalog.IsAuthor("Phantom") == false,
    "opaque contradictory IDs entered the public author index")
local publicCount = 0
for _ in pairs(syncSummaries) do publicCount = publicCount + 1 end
local allocationStatus = Nexus.BuildCatalog.Status()
assert(Nexus.BuildCatalog.Count() == publicCount
        and allocationSummary.merged == publicCount
        and allocationStatus.availableCount == publicCount,
    "opaque catalog rows inflated public availability counts: summaries="
        .. tostring(publicCount) .. ", count="
        .. tostring(Nexus.BuildCatalog.Count()) .. ", init="
        .. tostring(allocationSummary.merged) .. ", status="
        .. tostring(allocationStatus.availableCount))

print("BuildCatalog precedence and defensive copies -- OK")
