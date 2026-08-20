-- Related-build lookup stays revision-owned, narrow, and behaviorally equal to
-- the former exhaustive Saved Build scan across preferred/collision cases.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

UnitName = function() return "IndexMage" end
GetNormalizedRealmName = function() return "Ebonhold" end

local function Echoes(first, count)
    local rows = {}
    for offset = 0, count - 1 do
        rows[#rows + 1] = {spellId=first+offset,quality=3,stacks=1}
    end
    return rows
end

NexusDB = {communityBuilds={},syncTombstones={},buildFilters={}}
for index = 1, 1000 do
    NexusDB.communityBuilds[string.format("other-%04d", index)] = {
        id=string.format("other-%04d", index),title="Unrelated "..index,
        author="Other",ownerKey="other@ebonhold",class="MAGE",
        postedAt=index,lastModified=index,echoes=Echoes(820000+index, 1),
    }
end
NexusDB.communityBuilds["index-exact"] = {
    id="index-exact",title="Published Exact",author="IndexMage",
    ownerKey="indexmage@ebonhold",ownerVerified=true,realm="ebonhold",
    class="MAGE",postedAt=2001,
    lastModified=2001,echoes=Echoes(810001, 6),
}
NexusDB.communityBuilds["index-title"] = {
    id="index-title",title="Saved Target",author="IndexMage",
    ownerKey="indexmage@ebonhold",ownerVerified=true,realm="ebonhold",
    class="MAGE",postedAt=2002,
    lastModified=2002,echoes=Echoes(810001, 3),
}
NexusDB.communityBuilds["index-subset"] = {
    id="index-subset",title="Different Title",author="IndexMage",
    ownerKey="indexmage@ebonhold",ownerVerified=true,realm="ebonhold",
    class="MAGE",postedAt=2003,
    lastModified=2003,echoes=Echoes(810001, 7),
}
NexusDB.communityBuilds["stale-fingerprint"] = {
    id="stale-fingerprint",title="Different Stored Title",author="IndexMage",
    ownerKey="indexmage@ebonhold",class="MAGE",postedAt=20035,
    lastModified=20035,fingerprint="999999x1",echoes=Echoes(860001, 3),
}
NexusDB.communityBuilds["stale-link"] = {
    id="stale-link",title="Stale",author="Other",class="ROGUE",
    postedAt=2004,lastModified=2004,echoes=Echoes(830001, 6),
}
NexusDB.communityBuilds["saved-indexmage-1"] = {
    id="saved-indexmage-1",title="Old Mirror",serverTitle="Old Mirror",
    author="IndexMage",ownerKey="indexmage@ebonhold",class="MAGE",
    postedAt=2005,lastModified=2005,echoes=Echoes(810001, 6),
    importedSavedBuild=true,isMine=true,serverSlot=1,
    recordBuildId="stale-link",_savedSignature="stale",
}

Nexus.Store.Init()
dofile("core/DpsCapture.lua")
Nexus.DpsCapture.Init({}, {})
local Catalog = Nexus.BuildCatalog
local beforeStats = Catalog.DebugStats()

local exactKey = Nexus.DpsCapture.GetEchoKey(Echoes(810001, 6))
local candidates = assert(Catalog.RelatedCandidates(
    "IndexMage", "Saved Target", exactKey))
local ids = {}
for _, row in ipairs(candidates) do ids[row.id] = true end
assert(#candidates == 3 and ids["index-exact"]
    and ids["index-title"] and ids["index-subset"]
    and not ids["stale-link"],
    "related index lost exact/title/subset candidates or admitted another author")
candidates[1].title = "mutated"
assert(Catalog.Get(candidates[1].id).title ~= "mutated",
    "related candidate lookup leaked a mutable catalog row")

local staleFingerprintKey = Nexus.DpsCapture.GetEchoKey(Echoes(860001, 3))
local staleFingerprintCandidates = assert(Catalog.RelatedCandidates(
    "IndexMage", "Different Live Title", staleFingerprintKey))
local foundStaleFingerprint = false
for _, row in ipairs(staleFingerprintCandidates) do
    if row.id == "stale-fingerprint" then foundStaleFingerprint = true end
end
assert(Catalog.FindExactFingerprintId("999999x1") == nil
    and Catalog.FindExactFingerprintId(staleFingerprintKey) == nil,
    "exact index authorized fingerprint-mismatched ordinary evidence")

local slots = {activeSlot=1,bySlot={
    [1]={name="Saved Target",class="MAGE",echoes=Echoes(810001, 6)},
}}
local slotGeneration, slotSnapshot = 1, slots
local controller = Nexus.CommunityInternals.Controller.New({})
controller.Initialize({
    Slots=function() return slotSnapshot end,
    EchoReconcileStats=function()
        return {generations={slots=slotGeneration}}
    end,
    GetLoadoutWishlist=function() return nil end,
}, nil)
local fullReads = 0
local originalAll = Catalog.All
Catalog.All = function(...)
    fullReads = fullReads + 1
    return originalAll(...)
end

-- Exact fingerprint lookup is incrementally revision-owned, deterministic,
-- prefers a posted build over an auto-generated DPS row, and never needs All.
local recordEpoch, recordRevision = Catalog.RecordRevision("index-exact")
local exactEpoch, exactRevision = Catalog.ExactFingerprintRevision(exactKey)
local exactId, exactRecord = Catalog.FindExactFingerprint(exactKey)
assert(exactId == "index-exact" and exactRecord.id == exactId
    and Catalog.FindExactFingerprintId(exactKey) == exactId and fullReads == 0,
    "exact fingerprint index lost its deterministic initial winner")
exactRecord.title = "mutated"
assert(Catalog.Get(exactId).title ~= "mutated",
    "exact fingerprint index leaked a mutable represented row")
assert(Catalog.Put({
    id="000-saved-exact",title="Private Saved Exact",serverTitle="Private Saved Exact",
    author="IndexMage",ownerKey="indexmage@ebonhold",ownerVerified=true,
    realm="ebonhold",class="ROGUE",postedAt=1997,lastModified=1997,
    importedSavedBuild=true,isMine=true,serverSlot=99,
    echoes=Echoes(810001, 6),
}))
local savedRawResolution, savedRawReason =
    Catalog.ResolveFingerprintIdentity("000-saved-exact", exactKey)
assert(Catalog.FindExactFingerprintId(exactKey) == "index-exact"
    and savedRawResolution == "index-exact"
    and savedRawReason == "fingerprint",
    "private Saved mirror hid or became the public exact-content winner")
assert(Catalog.RemoveOverlay("000-saved-exact"),
    "private Saved exact-index control could not be removed")
assert(Catalog.Put({
    id="invalid-exact",title="Invalid Exact",author="Other",
    ownerKey="other@ebonhold",class="MAGE",postedAt=1998,
    lastModified=1998,echoes={
        {spellId=0,quality=0,stacks=1},
        {spellId=810001,quality=0,stacks=math.huge},
    },
}))
assert(Catalog.FindExactFingerprintId("0x1") == nil
    and Catalog.FindExactFingerprintId("810001xinf") == nil,
    "non-finite/non-positive Echo data entered the exact index")
assert(Catalog.RemoveOverlay("invalid-exact"))

assert(Catalog.Put({
    id="000-auto",title="Auto Collision",author="IndexMage",
    ownerKey="indexmage@ebonhold",class="MAGE",postedAt=1999,
    lastModified=1999,autoDps=true,echoes=Echoes(810001, 6),
}))
local exactEpochAfterAuto, exactRevisionAfterAuto =
    Catalog.ExactFingerprintRevision(exactKey)
local autoCollisionWinner = Catalog.FindExactFingerprintId(exactKey)
assert(autoCollisionWinner == "index-exact"
    and exactEpochAfterAuto == exactEpoch
    and exactRevisionAfterAuto > exactRevision and fullReads == 0,
    string.format("auto collision mismatch: winner=%s epoch=%s/%s revision=%s/%s full=%d",
        tostring(autoCollisionWinner),tostring(exactEpochAfterAuto),
        tostring(exactEpoch),tostring(exactRevisionAfterAuto),
        tostring(exactRevision),fullReads))

assert(Catalog.Put({
    id="000-explicit",title="Explicit Collision",author="IndexMage",
    ownerKey="indexmage@ebonhold",class="MAGE",postedAt=2000,
    lastModified=2000,echoes=Echoes(810001, 6),
}))
local exactEpochAfterExplicit, exactRevisionAfterExplicit =
    Catalog.ExactFingerprintRevision(exactKey)
assert(Catalog.FindExactFingerprintId(exactKey) == "000-explicit"
    and exactEpochAfterExplicit == exactEpoch
    and exactRevisionAfterExplicit > exactRevisionAfterAuto,
    "explicit exact-match collision did not use deterministic id ordering")

assert(Catalog.Put({
    id="exact-unrelated",title="Unrelated Exact Revision",author="Other",
    ownerKey="other@ebonhold",class="ROGUE",postedAt=2000,
    lastModified=2000,echoes=Echoes(899500, 1),
}))
local recordEpochAfter, recordRevisionAfter =
    Catalog.RecordRevision("index-exact")
local exactEpochAfterUnrelated, exactRevisionAfterUnrelated =
    Catalog.ExactFingerprintRevision(exactKey)
assert(recordEpochAfter == recordEpoch and recordRevisionAfter == recordRevision
    and exactEpochAfterUnrelated == exactEpoch
    and exactRevisionAfterUnrelated == exactRevisionAfterExplicit,
    "unrelated build mutation invalidated selected/exact scalar revisions")

assert(Catalog.RemoveOverlay("000-explicit"))
local _, exactRevisionAfterRemove = Catalog.ExactFingerprintRevision(exactKey)
assert(Catalog.FindExactFingerprintId(exactKey) == "index-exact"
    and exactRevisionAfterRemove > exactRevisionAfterExplicit,
    "exact index removal did not restore/revise the deterministic winner")
assert(Catalog.RemoveOverlay("000-auto"))
assert(Catalog.RemoveOverlay("exact-unrelated"))

assert(controller.ImportCurrentSavedLoadouts(true) == 1,
    "indexed saved-slot import did not update the stale mirror")
local mirror = assert(Catalog.Get("saved-indexmage-1"))
assert(mirror.recordBuildId == "index-exact"
    and mirror.class == "MAGE" and fullReads == 0,
    "indexed lookup chose a stale/lower-score record or read the full catalog")

local revisionBeforeWarm = Nexus.Revisions.Get(
    Nexus.Revisions.BUILD_LIBRARY_CHANGED)
assert(controller.ImportCurrentSavedLoadouts(true) == 0
    and Nexus.Revisions.Get(Nexus.Revisions.BUILD_LIBRARY_CHANGED)
        == revisionBeforeWarm and fullReads == 0,
    "unchanged indexed import wrote, revised, or read the full catalog")

local newRecord = {
    id="index-new",title="Saved Target",author="IndexMage",
    ownerKey="indexmage@ebonhold",class="MAGE",postedAt=3000,
    lastModified=3000,echoes=Echoes(810001, 6),
}
local rebuildsBeforeMutation = Catalog.DebugStats().relatedIndexRebuilds
assert(Catalog.Put(newRecord))
local afterPut = assert(Catalog.RelatedCandidates(
    "IndexMage", "Saved Target", exactKey))
local foundNew = false
for _, row in ipairs(afterPut) do
    if row.id == "index-new" then foundNew = true end
end
assert(foundNew and Catalog.DebugStats().relatedIndexRebuilds
    == rebuildsBeforeMutation,
    "record Put failed to maintain the related index incrementally")
assert(Catalog.RemoveOverlay("index-new"))
local afterRemove = assert(Catalog.RelatedCandidates(
    "IndexMage", "Saved Target", exactKey))
for _, row in ipairs(afterRemove) do
    assert(row.id ~= "index-new",
        "removed overlay remained in the related index")
end

local mirrors = Catalog.SavedMirrorIds("IndexMage")
assert(#mirrors == 1 and mirrors[1] == "saved-indexmage-1",
    "saved-mirror index lost or broadened the current author's mirror")
local narrowStats = Catalog.DebugStats()
assert(narrowStats.relatedIndexRebuilds == beforeStats.relatedIndexRebuilds
    and narrowStats.relatedLookups >= 4
    and narrowStats.maxRelatedCandidates <= 4,
    "related lookup rebuilt synchronously or lost its narrow candidate bound")

-- A collision-heavy same-title bucket cannot be capped without changing the
-- winner contract. It must instead resume across fixed 25-candidate pumps.
for index = 1, 80 do
    assert(Catalog.Put({
        id="wide-"..index,title="Wide Target",author="IndexMage",
        ownerKey="indexmage@ebonhold",ownerVerified=true,realm="ebonhold",
        class="MAGE",postedAt=4000+index,
        lastModified=4000+index,echoes=Echoes(840000+index, 1),
    }))
end
slots.bySlot[2] = {
    name="Wide Target",class="MAGE",echoes=Echoes(899001, 6),
}
assert(controller.BeginSavedLoadoutImport(true))
local _, pending = controller.PumpSavedLoadoutImport(25)
local pumps = 1
assert(pending, "wide candidate collision completed without exercising resume")
local restartsBeforeMutation = controller.SavedImportStats().restarts
assert(Catalog.Put({
    id="mid-job-revision",title="Unrelated Revision",author="Other",
    ownerKey="other@ebonhold",class="ROGUE",postedAt=5000,
    lastModified=5000,echoes=Echoes(899900, 1),
}), "mid-job revision fixture did not change the catalog")
slotSnapshot = nil
local _, unavailablePending = controller.PumpSavedLoadoutImport(25)
assert(unavailablePending and controller.HasPendingSavedLoadoutImport(),
    "EXPECTED RED: unavailable restart source dropped the pending last-good job")
slotSnapshot = slots
_, pending = controller.PumpSavedLoadoutImport(25)
pumps = pumps + 1
assert(pending, "catalog restart completed before the slot-generation probe")
slotSnapshot = {activeSlot=2,bySlot={
    [1]={name="Saved Target",class="MAGE",echoes=Echoes(810001, 6)},
    [2]={name="Wide Target",class="MAGE",echoes=Echoes(899001, 6)},
}}
slotGeneration = slotGeneration + 1
while pending and pumps < 20 do
    _, pending = controller.PumpSavedLoadoutImport(25)
    pumps = pumps + 1
end
local importStats = controller.SavedImportStats()
assert(not pending and pumps >= 4
    and importStats.maxCandidatesPerPump <= 25 and fullReads == 0,
    string.format("wide candidate budget mismatch: pending=%s pumps=%d max=%d restarts=%d fullReads=%d",
        tostring(pending),pumps,importStats.maxCandidatesPerPump,
        importStats.restarts,fullReads))
local wideMirror = assert(Catalog.Get("saved-indexmage-2"))
assert(importStats.restarts == restartsBeforeMutation + 2
    and wideMirror.recordBuildId == nil
    and wideMirror.activeServerBuild == true
    and foundStaleFingerprint,
    string.format("EXPECTED RED: source revision parity failed: restarts=%d expected=%d record=%s active=%s staleFingerprintCandidates=%d",
        importStats.restarts,restartsBeforeMutation+2,
        tostring(wideMirror.recordBuildId),tostring(wideMirror.activeServerBuild),
        #staleFingerprintCandidates))

local stats = Catalog.DebugStats()

print(string.format(
    "related build index: source=%d narrow=%d wide=%d pumps=%d pumpMax=%d restarts=%d lookups=%d exact=%d candidates=%d rebuilds=%d fullReads=%d warmRevisionDelta=0 -- OK",
    Catalog.Count(),#candidates,stats.maxRelatedCandidates,pumps,
    importStats.maxCandidatesPerPump,importStats.restarts,stats.relatedLookups,
    stats.exactLookups,stats.exactCandidates,
    stats.relatedIndexRebuilds,fullReads))
