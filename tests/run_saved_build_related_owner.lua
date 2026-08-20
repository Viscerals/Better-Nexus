-- Saved Build relationship metadata must be selected by verified canonical
-- owner authority before exact-fingerprint, title, or subset similarity.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

UnitName = function() return "Twin" end
GetNormalizedRealmName = function() return "RealmA" end

local function Echoes(first, count)
    local rows = {}
    for offset = 0, count - 1 do
        rows[#rows + 1] = {
            spellId=first + offset,quality=3,stacks=1,
        }
    end
    return rows
end

local exactEchoes = Echoes(970001, 6)
NexusDB = {
    communityBuilds={
        ["realm-b-exact"]={
            id="realm-b-exact",title="Saved Target",author="Twin",
            ownerKey="twin@realmb",ownerVerified=true,realm="realmb",
            class="ROGUE",postedAt=10,lastModified=10,
            echoes=exactEchoes,
        },
        ["realm-a-exact"]={
            id="realm-a-exact",title="Saved Target",author="Twin",
            ownerKey="twin@realma",ownerVerified=true,realm="realma",
            class="MAGE",postedAt=11,lastModified=11,
            echoes=exactEchoes,
        },
        ["saved-twin-1"]={
            id="saved-twin-1",title="Old Mirror",serverTitle="Old Mirror",
            author="Twin",ownerKey="twin@realma",ownerVerified=true,
            realm="realma",class="MAGE",postedAt=12,lastModified=12,
            echoes=exactEchoes,importedSavedBuild=true,isMine=true,
            serverSlot=1,recordBuildId="realm-b-exact",
            _savedSignature="stale",
        },
    },
    syncTombstones={},buildFilters={},
}

Nexus.Store.Init()
dofile("core/DpsCapture.lua")
Nexus.DpsCapture.Init({}, {})

local slots = {activeSlot=1,bySlot={
    [1]={name="Saved Target",class="MAGE",echoes=exactEchoes},
}}
local function NewController()
    local owner = Nexus.CommunityInternals.Controller.New({})
    owner.Initialize({
        Slots=function() return slots end,
        EchoReconcileStats=function()
            return {generations={slots=1}}
        end,
        GetLoadoutWishlist=function() return nil end,
    }, nil)
    return owner
end
local controller = NewController()

local function ImportAll(owner)
    assert(owner.BeginSavedLoadoutImport(true),
        "Saved Build import did not start")
    local changed, pending, total = 0, true, 0
    local pumps = 0
    while pending do
        changed, pending = owner.PumpSavedLoadoutImport(25)
        total = total + changed
        pumps = pumps + 1
        assert(pumps < 50, "Saved Build import did not converge")
    end
    return total
end

assert(ImportAll(controller) == 1,
    "Saved Build import did not refresh the stale related relationship")
local mirror = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
assert(mirror.recordBuildId == "realm-a-exact" and mirror.class == "MAGE",
    "EXPECTED RED: same-name RealmB record outranked exact RealmA owner authority")

-- Durable IDs are only hints. A later stale/corrupt relationship must be
-- revalidated when detail and DPS readers consume it, even before the next
-- server-slot reconciliation runs.
mirror.recordBuildId = "realm-b-exact"
mirror.lastModified = mirror.lastModified + 1
assert(Nexus.BuildCatalog.Put(mirror),
    "stale related-ID fixture did not enter the represented catalog")
local stale = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
local originalLeaderboard = Nexus.DpsCapture.GetLeaderboard
local originalEchoLeaderboard = Nexus.DpsCapture.GetLeaderboardForEchoes
Nexus.DpsCapture.GetLeaderboard = function(buildId)
    if buildId == "realm-b-exact" then
        return {{player="Twin",dps=990000}}
    elseif buildId == stale.id then
        return {{player="Twin",dps=970000}}
    end
    return {}
end
Nexus.DpsCapture.GetLeaderboardForEchoes = function()
    return {{player="Other",dps=980000}}
end
assert(controller.RecordBuildId(stale) == nil
    and controller.DpsSummary(stale).best == 0,
    "EXPECTED RED: stale cross-realm ID/fingerprint supplied Community DPS identity")
Nexus.DpsCapture.GetLeaderboard = originalLeaderboard
Nexus.DpsCapture.GetLeaderboardForEchoes = originalEchoLeaderboard

-- A valid source-bound publication is also a durable read relation. It must
-- remain usable before the next slot reconciliation even when recordBuildId
-- is absent, while an arbitrary same-owner published pointer remains invalid.
local publishedOnlyId = "published-only-local"
assert(Nexus.BuildCatalog.Put({
    id=publishedOnlyId,title="Saved Target",author="Twin",
    ownerKey="twin@realma",ownerVerified=true,realm="realma",
    class="MAGE",postedAt=18,lastModified=18,echoes=exactEchoes,
    sourceSavedBuildId=stale.id,
}), "published-only relation fixture did not initialize")
stale.recordBuildId = nil
stale.publishedBuildId = publishedOnlyId
stale.lastModified = stale.lastModified + 1
assert(Nexus.BuildCatalog.Put(stale),
    "published-only Saved relationship did not initialize")
stale = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
Nexus.DpsCapture.GetLeaderboard = function(buildId)
    if buildId == publishedOnlyId then
        return {{player="Twin",dps=345000}}
    end
    return {}
end
assert(controller.RecordBuildId(stale) == publishedOnlyId
    and controller.DpsSummary(stale).best == 345000,
    "EXPECTED RED: verified source-bound published-only relation was ignored")
Nexus.DpsCapture.GetLeaderboard = originalLeaderboard
stale.publishedBuildId = nil
stale.lastModified = stale.lastModified + 1
assert(Nexus.BuildCatalog.Put(stale),
    "published-only relationship cleanup failed")

assert(Nexus.BuildCatalog.Put({
    id="realm-a-unrelated",title="Different Local Build",author="Twin",
    ownerKey="twin@realma",ownerVerified=true,realm="realma",
    class="MAGE",postedAt=20,lastModified=20,
    echoes=Echoes(975001, 6),
}), "same-owner stale relationship fixture did not initialize")
stale.recordBuildId = "realm-a-unrelated"
stale.lastModified = stale.lastModified + 1
assert(Nexus.BuildCatalog.Put(stale),
    "same-owner stale related ID did not enter the catalog")
stale = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
assert(controller.RecordBuildId(stale) == nil,
    "EXPECTED RED: owner equality bypassed related content revalidation")

stale.recordBuildId = "realm-b-exact"
stale.publishedBuildId = "realm-b-exact"
stale.lastModified = stale.lastModified + 1
assert(Nexus.BuildCatalog.Put(stale),
    "projection stale related-ID fixture did not initialize")
stale = assert(Nexus.BuildCatalog.Get("saved-twin-1"))

local requestedIds = {}
local projection = Nexus.CommunityInternals.Projection.New({
    builds=function() return {}, {} end,
    buildsCurrent=function() return false end,
    loadBuild=function(id) return Nexus.BuildCatalog.Get(id) end,
    revisionSnapshot=function() return controller.RevisionSnapshot() end,
    recordBuildId=function(build) return controller.RecordBuildId(build) end,
    publishedBuildId=function(build)
        return controller.PublishedBuildId(build)
    end,
    savedProjection=function(build)
        return controller.ProjectBuild(build)
    end,
    leaderboard=function(buildId)
        requestedIds[#requestedIds + 1] = buildId
        if buildId == "realm-b-exact" then
            return {{player="Twin",dps=990000}}
        elseif buildId == stale.id then
            return {{player="Twin",dps=970000}}
        end
        return {}
    end,
    personalBest=function() return nil end,
})
local detail = assert(projection.Detail("saved-twin-1", {
    ownerKey="twin@realma",player="Twin",detailsAvailable=true,
}))
for _, buildId in ipairs(requestedIds) do
    assert(buildId ~= "realm-b-exact",
        "EXPECTED RED: Community projection bypassed related-owner validation")
end
assert(#detail.dummyRows == 0 and #detail.lkRows == 0,
    "cross-realm related DPS remained visible in Saved Build detail")
assert(detail.actionText == "Upload Build"
    and detail.editState
    and detail.editState:find("Local server loadout", 1, true),
    "EXPECTED RED: invalid published relationship remained visible as uploaded")

-- A stale publishedBuildId must not become write authority. Keep the occupied
-- foreign record intact and publish the valid local mirror to a safe identity.
local occupiedId = "published-saved-twin-1"
assert(Nexus.BuildCatalog.Put({
    id=occupiedId,title="RealmB Publication",author="Twin",
    ownerKey="twin@realmb",ownerVerified=true,realm="realmb",
    class="ROGUE",postedAt=30,lastModified=30,
    echoes=Echoes(980001, 6),sourceSavedBuildId="saved-twin-1",
}), "foreign publication collision fixture did not initialize")
stale = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
stale.publishedBuildId = occupiedId
stale.lastModified = stale.lastModified + 1
assert(Nexus.BuildCatalog.Put(stale),
    "stale published-ID relationship did not initialize")
Nexus.Sync = {BroadcastBuildSummary=function() return true end}
local published, publishedId = controller.PublishImportedBuild("saved-twin-1")
local occupied = assert(Nexus.BuildCatalog.Get(occupiedId))
local publishedRecord = publishedId and Nexus.BuildCatalog.Get(publishedId)
local savedAfterPublish = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
assert(published and publishedId ~= occupiedId
    and occupied.title == "RealmB Publication"
    and occupied.ownerKey == "twin@realmb"
    and publishedRecord and publishedRecord.sourceSavedBuildId == stale.id
    and Nexus.Identity.VerifiedOwnerKey(publishedRecord) == "twin@realma"
    and savedAfterPublish.publishedBuildId == publishedId,
    "EXPECTED RED: stale published ID overwrote another canonical owner")
local publishedAgain, samePublishedId =
    controller.PublishImportedBuild("saved-twin-1")
assert(publishedAgain and samePublishedId == publishedId
    and Nexus.Identity.VerifiedOwnerKey(
        Nexus.BuildCatalog.Get(occupiedId)) == "twin@realmb",
    "collision-safe publication identity was not stable on re-upload")

-- Once the stable publication relationship is reflected in the mirror's
-- signature, a later stale ID must still be cleared during reload/import.
ImportAll(controller)
local stable = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
assert(stable.publishedBuildId == publishedId
    and stable.recordBuildId == publishedId,
    "valid publication did not become the Saved Build relation")
assert(Nexus.BuildCatalog.Put({
    id="000-equal-local",title="Saved Target",author="Twin",
    ownerKey="twin@realma",ownerVerified=true,realm="realma",
    class="MAGE",postedAt=35,lastModified=35,echoes=exactEchoes,
}), "lexically earlier equal relation fixture did not initialize")
ImportAll(controller)
stable = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
assert(stable.publishedBuildId == publishedId
    and stable.recordBuildId == publishedId,
    "source-bound publication was displaced by an equal candidate")
local publicationReload = NewController()
ImportAll(publicationReload)
stable = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
assert(stable.publishedBuildId == publishedId
    and stable.recordBuildId == publishedId,
    "source-bound publication changed after a fresh controller reload")
stable.publishedBuildId = occupiedId
stable.lastModified = stable.lastModified + 1
assert(Nexus.BuildCatalog.Put(stable),
    "post-publication stale ID fixture did not initialize")
ImportAll(controller)
local reloadedPublishedId = Nexus.BuildCatalog.Get("saved-twin-1").publishedBuildId
assert(reloadedPublishedId == publishedId,
    "EXPECTED RED: invalid published ID survived unchanged Saved Build import"
        .. " (expected=" .. tostring(publishedId)
        .. ", actual=" .. tostring(reloadedPublishedId) .. ")")

-- The historical mirror ID contains only the short character name. A RealmB
-- mirror occupying that ID must neither be overwritten by RealmA's live slot
-- nor be swept as an obsolete RealmA mirror during cleanup.
local foreignMirrorId = "saved-twin-2"
local foreignOrphanId = "saved-twin-3"
assert(Nexus.BuildCatalog.Put({
    id=foreignMirrorId,title="RealmB Saved Slot",serverTitle="RealmB Saved Slot",
    author="Twin",ownerKey="twin@realmb",ownerVerified=true,realm="realmb",
    class="ROGUE",postedAt=40,lastModified=40,echoes=Echoes(985001, 6),
    importedSavedBuild=true,isMine=false,serverSlot=2,
}), "foreign Saved mirror collision fixture did not initialize")
assert(Nexus.BuildCatalog.Put({
    id=foreignOrphanId,title="RealmB Orphan",serverTitle="RealmB Orphan",
    author="Twin",ownerKey="twin@realmb",ownerVerified=true,realm="realmb",
    class="ROGUE",postedAt=41,lastModified=41,echoes=Echoes(986001, 6),
    importedSavedBuild=true,isMine=false,serverSlot=3,
}), "foreign Saved mirror cleanup fixture did not initialize")
slots.bySlot[2] = {
    name="RealmA Saved Slot",class="MAGE",echoes=Echoes(987001, 6),
}
ImportAll(controller)
local foreignMirror = assert(Nexus.BuildCatalog.Get(foreignMirrorId))
local localSlotTwo
for id, build in pairs(Nexus.BuildCatalog.All()) do
    if build.importedSavedBuild and build.serverSlot == 2
        and Nexus.Identity.VerifiedOwnerKey(build) == "twin@realma" then
        localSlotTwo = id
    end
end
assert(Nexus.Identity.VerifiedOwnerKey(foreignMirror) == "twin@realmb"
    and foreignMirror.title == "RealmB Saved Slot"
    and Nexus.BuildCatalog.Get(foreignOrphanId) ~= nil
    and localSlotTwo and localSlotTwo ~= foreignMirrorId,
    "EXPECTED RED: short-name Saved mirror collision overwrote or deleted RealmB")
assert(Nexus.BuildCatalog.RemoveOverlay(foreignMirrorId),
    "foreign base mirror removal failed")
ImportAll(controller)
local stableLocalSlotTwo
for id, build in pairs(Nexus.BuildCatalog.All()) do
    if build.importedSavedBuild and build.serverSlot == 2
        and Nexus.Identity.VerifiedOwnerKey(build) == "twin@realma" then
        stableLocalSlotTwo = id
    end
end
assert(stableLocalSlotTwo == localSlotTwo,
    "EXPECTED RED: vacated short-name ID changed the established local mirror identity")

local ambiguousMirrorId = "saved-twin-4"
local ambiguousOrphanId = "saved-twin-8"
local explicitLegacyOrphanId = "saved-twin-14"
assert(Nexus.BuildCatalog.Put({
    id=ambiguousMirrorId,title="Ambiguous Private",userTitle="Ambiguous Private",
    serverTitle="Ambiguous Private",author="Twin",isMine=true,
    class="ROGUE",postedAt=45,lastModified=45,echoes=Echoes(987501, 6),
    importedSavedBuild=true,serverSlot=4,
}), "ambiguous Saved mirror collision fixture did not initialize")
assert(Nexus.BuildCatalog.Put({
    id=ambiguousOrphanId,title="Ambiguous Orphan",author="Twin",isMine=true,
    class="ROGUE",postedAt=46,lastModified=46,echoes=Echoes(987601, 6),
    importedSavedBuild=true,serverSlot=8,
}), "ambiguous Saved mirror cleanup fixture did not initialize")
assert(Nexus.BuildCatalog.Put({
    id=explicitLegacyOrphanId,title="Explicit Legacy Orphan",
    serverTitle="Explicit Legacy Orphan",author="Twin",
    ownerKey="twin@realma",realm="realma",isMine=true,
    class="MAGE",postedAt=47,lastModified=47,echoes=Echoes(987651, 6),
    importedSavedBuild=true,serverSlot=14,
}), "explicit-owner legacy Saved orphan did not initialize")
slots.bySlot[4] = {
    name="RealmA Slot Four",class="MAGE",echoes=Echoes(987701, 6),
}
ImportAll(controller)
local ambiguousMirror = assert(Nexus.BuildCatalog.Get(ambiguousMirrorId))
local localSlotFour
for id, build in pairs(Nexus.BuildCatalog.All()) do
    if build.importedSavedBuild and build.serverSlot == 4
        and Nexus.Identity.VerifiedOwnerKey(build) == "twin@realma" then
        localSlotFour = id
    end
end
assert(ambiguousMirror.ownerVerified ~= true
    and ambiguousMirror.userTitle == "Ambiguous Private"
    and Nexus.BuildCatalog.Get(ambiguousOrphanId) ~= nil
    and Nexus.BuildCatalog.Get(explicitLegacyOrphanId) ~= nil
    and localSlotFour and localSlotFour ~= ambiguousMirrorId,
    "EXPECTED RED: unverified Saved evidence was adopted or cleaned as RealmA")

-- A valid persisted relation remains the stable winner across equal candidates.
-- With no persisted winner, equal authority/content candidates resolve by ID
-- so hash-table traversal order cannot change a cold relationship.
local tieEchoes = Echoes(988001, 6)
for _, id in ipairs({"tie-z", "tie-a"}) do
    assert(Nexus.BuildCatalog.Put({
        id=id,title="Tie Target",author="Twin",
        ownerKey="twin@realma",ownerVerified=true,realm="realma",
        class="MAGE",postedAt=50,lastModified=50,echoes=tieEchoes,
    }), "deterministic tie candidate did not initialize: " .. id)
end
assert(Nexus.BuildCatalog.Put({
    id="saved-twin-5",title="Old Tie Mirror",serverTitle="Old Tie Mirror",
    author="Twin",ownerKey="twin@realma",ownerVerified=true,realm="realma",
    class="MAGE",postedAt=51,lastModified=51,echoes=tieEchoes,
    importedSavedBuild=true,isMine=true,serverSlot=5,
    recordBuildId="tie-z",_savedSignature="stale",
}), "deterministic tie mirror did not initialize")
slots.bySlot[5] = {name="Tie Target",class="MAGE",echoes=tieEchoes}
ImportAll(controller)
assert(Nexus.BuildCatalog.Get("saved-twin-5").recordBuildId == "tie-z",
    "valid persisted relation was displaced by an equal candidate")
slots.bySlot[7] = {name="Tie Target",class="MAGE",echoes=tieEchoes}
ImportAll(controller)
assert(Nexus.BuildCatalog.Get("saved-twin-7").recordBuildId == "tie-a",
    "cold equal related candidates did not resolve deterministically")

-- Content similarity never repairs missing authority. The verified RealmA
-- title/subset candidate is the only admissible relation; a realm-less exact
-- match and a verified RealmB title/subset match remain ambient evidence.
local subsetEchoes = Echoes(989001, 8)
assert(Nexus.BuildCatalog.Put({
    id="unverified-exact",title="Subset Target",author="Twin",
    ownerKey="twin@realma",ownerVerified=false,realm="realma",
    class="ROGUE",postedAt=60,lastModified=60,
    echoes=subsetEchoes,
}), "explicitly unverified exact candidate did not initialize")
assert(Nexus.BuildCatalog.Put({
    id="realm-less-exact",title="Subset Target",author="Twin",
    ownerVerified=true,class="ROGUE",postedAt=60,lastModified=60,
    echoes=subsetEchoes,
}), "realm-less exact candidate did not initialize")
assert(Nexus.BuildCatalog.Put({
    id="realm-b-subset",title="Subset Target",author="Twin",
    ownerKey="twin@realmb",ownerVerified=true,realm="realmb",
    class="ROGUE",postedAt=61,lastModified=61,
    echoes=Echoes(989001, 10),
}), "RealmB subset candidate did not initialize")
assert(Nexus.BuildCatalog.Put({
    id="realm-a-subset",title="Subset Target",author="Twin",
    ownerKey="twin@realma",ownerVerified=true,realm="realma",
    class="MAGE",postedAt=62,lastModified=62,
    echoes=Echoes(989001, 10),
}), "RealmA subset candidate did not initialize")
slots.bySlot[6] = {name="Subset Target",class="MAGE",echoes=subsetEchoes}
ImportAll(controller)
local subsetMirror = assert(Nexus.BuildCatalog.Get("saved-twin-6"))
assert(subsetMirror.recordBuildId == "realm-a-subset"
    and subsetMirror.class == "MAGE",
    "verified exact-owner title/subset relation was not selected")

-- A catalog revision must invalidate the warm relation cache. Once the only
-- verified local candidate changes owner, the durable relationship clears;
-- recreating the controller must not resurrect it from persisted metadata.
assert(Nexus.BuildCatalog.RemoveOverlay("realm-a-subset"),
    "valid subset candidate removal failed")
assert(Nexus.BuildCatalog.Put({
    id="realm-a-subset",title="Subset Target",author="Twin",
    ownerKey="twin@realmb",ownerVerified=true,realm="realmb",
    class="ROGUE",postedAt=62,lastModified=63,
    echoes=Echoes(989001, 10),
}), "subset owner-change fixture did not initialize")
ImportAll(controller)
subsetMirror = assert(Nexus.BuildCatalog.Get("saved-twin-6"))
assert(subsetMirror.recordBuildId == nil and subsetMirror.class ~= "ROGUE",
    "EXPECTED RED: cache retained a relation after canonical owner changed")
local reloadedController = NewController()
ImportAll(reloadedController)
assert(Nexus.BuildCatalog.Get("saved-twin-6").recordBuildId == nil,
    "stale persisted relation returned after controller reload")

assert(Nexus.BuildCatalog.RemoveOverlay("realm-a-subset"),
    "wrong-owner subset candidate removal failed")
local restoredSubsetEchoes = Echoes(989001, 10)
assert(Nexus.BuildCatalog.Put({
    id="realm-a-subset",title="Subset Target",author="Twin",
    ownerKey="twin@realma",ownerVerified=true,realm="realma",
    class="MAGE",postedAt=62,lastModified=64,
    echoes=restoredSubsetEchoes,
    fingerprint=Nexus.DpsCapture.GetEchoKey(restoredSubsetEchoes),
    fingerprintHash=Nexus.DpsCapture.GetEchoHash(restoredSubsetEchoes),
}), "restored exact-owner subset candidate did not initialize")
ImportAll(reloadedController)
local restoredSubset = assert(Nexus.BuildCatalog.Get("saved-twin-6"))
assert(restoredSubset.recordBuildId == "realm-a-subset",
    "later verified exact-owner evidence did not restore the relation")
local compactSubsetRelation = assert(
    reloadedController.SavedProjectionRelation(
        Nexus.BuildCatalog.GetSummary(restoredSubset.id)),
    "compact Saved projection could not validate a title/subset relation")
assert(compactSubsetRelation.buildId == "realm-a-subset",
    "compact Saved projection selected the wrong title/subset relation")
local malformedSourceSummary = Nexus.BuildCatalog.GetSummary(restoredSubset.id)
malformedSourceSummary.fingerprint = "989001x8,malformed"
assert(reloadedController.SavedProjectionRelation(malformedSourceSummary) == nil,
    "malformed compact Saved fingerprint entered relationship scoring")
assert(Nexus.BuildCatalog.Put({
    id="malformed-compact-target",title="Subset Target",author="Twin",
    ownerKey="twin@realma",ownerVerified=true,realm="realma",
    class="MAGE",postedAt=65,lastModified=65,
    echoes=restoredSubsetEchoes,fingerprint="malformed",
}), "malformed compact target fixture did not initialize")
local malformedTargetSource = Nexus.BuildCatalog.GetSummary(restoredSubset.id)
malformedTargetSource.recordBuildId = "malformed-compact-target"
malformedTargetSource.publishedBuildId = nil
assert(reloadedController.SavedProjectionRelation(malformedTargetSource) == nil,
    "malformed compact target fingerprint entered relationship scoring")

-- Public ownership and library consumers must apply the same verified-owner
-- boundary as Saved Build relationship reconciliation. Preserve the explicit
-- owner-key legacy adoption path as a positive control: it is authoritative
-- enough to adopt locally, while a claimless isMine row is not.
local savedRelationResolver = function(build)
    return controller.ProjectBuild(build)
end
assert(Nexus.ViewProjections.BindSavedRelationResolver(
    savedRelationResolver), "Saved relation resolver did not bind")

local function ProjectedBuild(rows, id)
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        if row.id == id then return row end
    end
    return nil
end

local function ProjectMine(search, qualifiedOnly, currentClassOnly)
    Nexus.ViewProjections.Reset()
    local rows, summary, err = Nexus.ViewProjections.Builds({
        scope="mine",search=search,currentClassOnly=currentClassOnly == true,
        qualifiedOnly=qualifiedOnly,sortMode="title",
    })
    assert(type(rows) == "table", tostring(err or "My Builds projection failed"))
    return rows, summary
end

local function ProjectMineAsync(search, qualifiedOnly, currentClassOnly)
    Nexus.ViewProjections.Reset()
    local filters = {
        scope="mine",search=search,currentClassOnly=currentClassOnly == true,
        qualifiedOnly=qualifiedOnly,sortMode="title",
    }
    for _ = 1, 200 do
        local rows, summary, err = Nexus.ViewProjections.RequestBuilds(filters)
        if type(rows) == "table" then return rows, summary end
        assert(err == "pending", tostring(err or "async My Builds failed"))
        Nexus.ViewProjections.PumpBuilds()
    end
    error("async My Builds projection did not converge")
end

local function ProjectPublic(search, qualifiedOnly)
    Nexus.ViewProjections.Reset()
    local rows, summary, err = Nexus.ViewProjections.Builds({
        scope="all",search=search,currentClassOnly=false,
        qualifiedOnly=qualifiedOnly,sortMode="title",
    })
    assert(type(rows) == "table", tostring(err or "public projection failed"))
    return rows, summary
end

local function LocalMirrorForSlot(slot)
    for id, build in pairs(Nexus.BuildCatalog.All()) do
        if build.importedSavedBuild and tonumber(build.serverSlot) == slot
            and Nexus.Identity.VerifiedOwnerKey(build) == "twin@realma" then
            return id, build
        end
    end
    return nil, nil
end

-- A rejected relationship must not keep contributing its persisted class or
-- IDs while startup reconciliation is still pending. The verified local Saved
-- mirror belongs to the current MAGE; only its RealmB candidate says ROGUE.
local staleProjectionEchoes = Echoes(990501, 6)
local staleProjectionFingerprint =
    assert(Nexus.DpsCapture.GetEchoKey(staleProjectionEchoes))
local staleProjectionHash =
    assert(Nexus.DpsCapture.GetEchoHash(staleProjectionEchoes))
assert(Nexus.BuildCatalog.Put({
    id="realm-b-stale-projection",title="Stale Projection Candidate",
    author="Twin",ownerKey="twin@realmb",ownerVerified=true,realm="realmb",
    class="ROGUE",postedAt=66,lastModified=66,echoes=staleProjectionEchoes,
    fingerprint=staleProjectionFingerprint,
    fingerprintHash=staleProjectionHash,
}), "stale projection wrong-owner candidate did not initialize")
local staleProjectionId = "saved-stale-projection"
assert(Nexus.BuildCatalog.Put({
    id=staleProjectionId,title="Stale Projection Mirror",
    serverTitle="Stale Projection Candidate",author="Twin",
    ownerKey="twin@realma",ownerVerified=true,realm="realma",isMine=true,
    class="ROGUE",postedAt=67,lastModified=67,echoes=staleProjectionEchoes,
    fingerprint=staleProjectionFingerprint,
    fingerprintHash=staleProjectionHash,importedSavedBuild=true,serverSlot=13,
    recordBuildId="realm-b-stale-projection",
    publishedBuildId="realm-b-stale-projection",
}), "stale projection Saved mirror did not initialize")
local staleProjectionSource =
    assert(Nexus.BuildCatalog.Get(staleProjectionId))
assert(controller.SavedProjectionRelation(staleProjectionSource) == nil
    and controller.RecordBuildId(staleProjectionSource) == nil
    and controller.PublishedBuildId(staleProjectionSource) == nil,
    "stale projection setup unexpectedly retained the RealmB relationship")
local controllerProjectedStale, controllerStaleRelation =
    controller.ProjectBuild(staleProjectionSource)
local persistedStaleProjection =
    assert(Nexus.BuildCatalog.Get(staleProjectionId))
assert(controllerProjectedStale and controllerStaleRelation == nil
    and controllerProjectedStale.class == "MAGE"
    and controllerProjectedStale.recordBuildId == nil
    and controllerProjectedStale.publishedBuildId == nil
    and persistedStaleProjection.class == "ROGUE"
    and persistedStaleProjection.recordBuildId == "realm-b-stale-projection"
    and persistedStaleProjection.publishedBuildId == "realm-b-stale-projection",
    "controller projection did not sanitize without mutating persisted evidence")
assert(controller.Build(staleProjectionId).class == "MAGE",
    "renderer-facing exact build reader reused rejected class metadata")
controller.Select(staleProjectionId)
local selectedStaleProjection = assert(controller.SelectedBuild())
assert(selectedStaleProjection.class == "MAGE"
    and selectedStaleProjection.recordBuildId == nil
    and selectedStaleProjection.publishedBuildId == nil,
    "renderer-facing selected build reused rejected relationship metadata")
controller.ClearSelection(staleProjectionId)
local projectedStale = ProjectedBuild(
    ProjectMine("stale projection mirror", false, true), staleProjectionId)
assert(projectedStale and projectedStale.class == "MAGE"
    and projectedStale.recordBuildId == nil
    and projectedStale.publishedBuildId == nil,
    "EXPECTED RED: sync projection reused rejected class or related IDs")
local asyncProjectedStale = ProjectedBuild(
    ProjectMineAsync("stale projection mirror", false, true), staleProjectionId)
assert(asyncProjectedStale and asyncProjectedStale.class == "MAGE"
    and asyncProjectedStale.recordBuildId == nil
    and asyncProjectedStale.publishedBuildId == nil,
    "EXPECTED RED: async projection reused rejected class or related IDs")
local staleDetailProjection = Nexus.CommunityInternals.Projection.New({
    builds=function() return {}, {} end,
    buildsCurrent=function() return false end,
    loadBuild=function(id) return controller.Build(id) end,
    revisionSnapshot=function() return controller.RevisionSnapshot() end,
    recordBuildId=function(build) return controller.RecordBuildId(build) end,
    publishedBuildId=function(build)
        return controller.PublishedBuildId(build)
    end,
    savedProjection=function(build)
        return controller.ProjectBuild(build)
    end,
    leaderboard=function() return {} end,
    personalBest=function() return nil end,
})
local staleDetail = assert(staleDetailProjection.Detail(staleProjectionId, {
    ownerKey="twin@realma",player="Twin",currentClass="MAGE",
    detailsAvailable=true,
}))
assert(staleDetail.build.class == "MAGE"
    and staleDetail.build.recordBuildId == nil
    and staleDetail.build.publishedBuildId == nil,
    "EXPECTED RED: detail projection exposed rejected class or related IDs")
assert(Nexus.ViewProjections.ExplainBuild(staleProjectionId, {
        scope="mine",search="stale projection mirror",currentClassOnly=true,
        qualifiedOnly=false,sortMode="title",
    }) == "included on current page",
    "EXPECTED RED: ExplainBuild filtered a Saved mirror by rejected class")

-- A source-bound publication remains a stable upload identity even after the
-- local Saved content changes enough that it is no longer a DPS relation.
local changedPublicationId = "published-content-changed"
local changedSavedId = "saved-content-changed"
local changedSavedEchoes = Echoes(990701, 6)
assert(Nexus.BuildCatalog.Put({
    id=changedPublicationId,title="Old Published Content",author="Twin",
    ownerKey="twin@realma",ownerVerified=true,realm="realma",class="MAGE",
    postedAt=68,lastModified=68,echoes=Echoes(990801, 6),
    sourceSavedBuildId=changedSavedId,
}), "content-changed publication target did not initialize")
assert(Nexus.BuildCatalog.Put({
    id=changedSavedId,title="Changed Local Content",
    serverTitle="Changed Local Content",author="Twin",
    ownerKey="twin@realma",ownerVerified=true,realm="realma",isMine=true,
    class="ROGUE",postedAt=69,lastModified=69,echoes=changedSavedEchoes,
    importedSavedBuild=true,serverSlot=14,
    recordBuildId=changedPublicationId,publishedBuildId=changedPublicationId,
}), "content-changed Saved mirror did not initialize")
local changedSaved = assert(Nexus.BuildCatalog.Get(changedSavedId))
local changedProjected, changedRelation = controller.ProjectBuild(changedSaved)
assert(changedRelation == nil and changedProjected
    and changedProjected.class == "MAGE"
    and changedProjected.recordBuildId == nil
    and changedProjected.publishedBuildId == changedPublicationId,
    "valid publication identity was nested under content relation acceptance")
local changedDetailProjection = Nexus.CommunityInternals.Projection.New({
    builds=function() return {}, {} end,
    buildsCurrent=function() return false end,
    loadBuild=function(id) return Nexus.BuildCatalog.Get(id) end,
    savedProjection=function(build) return controller.ProjectBuild(build) end,
    revisionSnapshot=function() return controller.RevisionSnapshot() end,
    leaderboard=function() return {} end,
    personalBest=function() return nil end,
})
local changedDetail = assert(changedDetailProjection.Detail(changedSavedId, {
    ownerKey="twin@realma",player="Twin",currentClass="MAGE",
}))
assert(changedDetail.build.recordBuildId == nil
    and changedDetail.build.publishedBuildId == changedPublicationId
    and changedDetail.actionText == "Update Upload",
    "content-changed valid publication lost its projected upload state")
local changedPublished, changedPublishedId =
    controller.PublishImportedBuild(changedSavedId)
local changedPublishedBuild = changedPublishedId
    and Nexus.BuildCatalog.Get(changedPublishedId) or nil
assert(changedPublished and changedPublishedId == changedPublicationId
    and changedPublishedBuild and changedPublishedBuild.class == "MAGE",
    "EXPECTED RED: content-changed upload migrated identity or published stale class")

local explicitLegacyId = "saved-twin-9"
local explicitLegacyEchoes = Echoes(990001, 6)
assert(Nexus.BuildCatalog.Put({
    id=explicitLegacyId,title="Legacy Local Private",
    userTitle="Legacy Local Private",serverTitle="Legacy Before Import",
    author="Twin",ownerKey="twin@realma",realm="realma",
    class="MAGE",postedAt=70,lastModified=70,
    echoes=Echoes(990101, 6),importedSavedBuild=true,isMine=true,
    serverSlot=9,
}), "explicit-owner legacy Saved mirror fixture did not initialize")
local explicitLegacyBefore = assert(Nexus.BuildCatalog.Get(explicitLegacyId))
local explicitLegacyPublished, explicitLegacyWhy =
    controller.PublishImportedBuild(explicitLegacyId)
local explicitLegacyRows = ProjectMine("legacy local private", false)
assert(not controller.IsOwnBuild(explicitLegacyBefore)
    and not explicitLegacyPublished and explicitLegacyWhy == "not your build"
    and not ProjectedBuild(explicitLegacyRows, explicitLegacyId),
    "EXPECTED RED: unverified explicit-owner mirror gained authority before adoption")
slots.bySlot[9] = {
    name="Legacy Live Slot",class="MAGE",echoes=explicitLegacyEchoes,
}
ImportAll(controller)
local explicitLegacy = assert(Nexus.BuildCatalog.Get(explicitLegacyId))
assert(Nexus.Identity.VerifiedOwnerKey(explicitLegacy) == "twin@realma"
    and explicitLegacy.ownerVerified == true
    and explicitLegacy.userTitle == "Legacy Local Private"
    and explicitLegacy.title == "Legacy Local Private",
    "explicit-owner legacy Saved mirror was not adopted by its exact owner")
local explicitRows = ProjectMine("legacy local private", false)
assert(ProjectedBuild(explicitRows, explicitLegacyId),
    "verified explicit-owner legacy mirror was excluded from My Builds")

local ambiguousBefore = assert(Nexus.BuildCatalog.Get(ambiguousMirrorId))
local ambiguousProjected = assert(controller.ProjectBuild(ambiguousBefore))
assert(not controller.IsOwnBuild(ambiguousBefore),
    "EXPECTED RED: claimless isMine Saved mirror granted owner authority")
local ambiguousPublished, ambiguousWhy =
    controller.PublishImportedBuild(ambiguousMirrorId)
assert(not ambiguousPublished and ambiguousWhy == "not your build"
    and ambiguousProjected.class == "UNKNOWN"
    and ambiguousProjected.recordBuildId == nil
    and ambiguousProjected.publishedBuildId == nil
    and Nexus.BuildCatalog.Get("published-" .. ambiguousMirrorId) == nil,
    "EXPECTED RED: claimless Saved mirror reached publication authority")
local ambiguousDetail = assert(changedDetailProjection.Detail(
    ambiguousMirrorId, {ownerKey="twin@realma",player="Twin",
        currentClass="MAGE"}))
assert(not ambiguousDetail.mine and ambiguousDetail.build.class == "UNKNOWN"
    and ambiguousDetail.build.recordBuildId == nil
    and ambiguousDetail.build.publishedBuildId == nil,
    "unverified Saved detail borrowed the current character's metadata")
local foreignProjected = assert(controller.ProjectBuild(
    Nexus.BuildCatalog.Get(foreignOrphanId)))
local foreignDetail = assert(changedDetailProjection.Detail(
    foreignOrphanId, {ownerKey="twin@realma",player="Twin",
        currentClass="MAGE"}))
assert(foreignProjected.class == "UNKNOWN"
    and foreignDetail.build.class == "UNKNOWN" and not foreignDetail.mine,
    "foreign Saved detail borrowed the current character's class")

-- Saved-marker classification must be type-stable at every public boundary.
-- A truthy non-boolean marker cannot take ordinary-build ownership and then
-- switch to Saved-build publication semantics.
for index, marker in ipairs({"true", 1, {future=true}}) do
    local malformedId = "malformed-saved-marker-" .. index
    assert(Nexus.BuildCatalog.Put({
        id=malformedId,title="Malformed Saved Marker " .. index,
        serverTitle="Malformed Saved Marker " .. index,author="Twin",
        class="MAGE",postedAt=80 + index,lastModified=80 + index,
        echoes=Echoes(991000 + index * 100, 6),
        importedSavedBuild=marker,isMine=true,serverSlot=10 + index,
    }), "malformed Saved marker fixture did not initialize: " .. index)
    local malformed = assert(Nexus.BuildCatalog.Get(malformedId))
    local published, why = controller.PublishImportedBuild(malformedId)
    local rows = ProjectMine("malformed saved marker " .. index, false)
    local malformedDetail = changedDetailProjection.Detail(malformedId, {
        ownerKey="twin@realma",player="Twin",currentClass="MAGE",
    })
    assert(not controller.IsOwnBuild(malformed)
        and controller.ProjectBuild(malformed) == nil
        and controller.Build(malformedId) == nil
        and malformedDetail == nil
        and not published and why == "not a saved loadout"
        and not ProjectedBuild(rows, malformedId)
        and Nexus.BuildCatalog.Get("published-" .. malformedId) == nil,
        "EXPECTED RED: malformed Saved marker crossed authority boundaries: "
            .. index)
end

local explicitOrdinaryId = "explicit-false-ordinary"
assert(Nexus.BuildCatalog.Put({
    id=explicitOrdinaryId,title="Explicit False Ordinary",author="Twin",
    ownerKey="twin@realma",ownerVerified=true,realm="realma",isMine=true,
    class="MAGE",postedAt=90,lastModified=90,
    echoes=Echoes(992001, 6),importedSavedBuild=false,
}), "explicit false ordinary fixture did not initialize")
local explicitOrdinary = assert(Nexus.BuildCatalog.Get(explicitOrdinaryId))
local falsePublished, falseWhy =
    controller.PublishImportedBuild(explicitOrdinaryId)
assert(controller.IsOwnBuild(explicitOrdinary)
    and not falsePublished and falseWhy == "not a saved loadout"
    and ProjectedBuild(ProjectMine("explicit false ordinary", false),
        explicitOrdinaryId),
    "boolean false no longer retained ordinary-build semantics")

for _, denied in ipairs({
    {id=foreignOrphanId,search="realmb orphan"},
    {id=ambiguousMirrorId,search="ambiguous private"},
    {id=ambiguousOrphanId,search="ambiguous orphan"},
}) do
    assert(Nexus.BuildCatalog.Get(denied.id),
        "My Builds denial fixture disappeared: " .. denied.id)
    local deniedRows = ProjectMine(denied.search, false)
    assert(not ProjectedBuild(deniedRows, denied.id),
        "EXPECTED RED: foreign or ambiguous Saved mirror entered My Builds: "
            .. denied.id)
end

-- A valid foreign DPS pair proves the fingerprint is qualified, but that
-- fingerprint alone must not qualify the local Saved mirror when the only
-- related canonical build belongs to another realm.
local foreignFingerprintId = "foreign-fingerprint-only"
local foreignFingerprintEchoes = Echoes(994001, 6)
local foreignFingerprint =
    assert(Nexus.DpsCapture.GetEchoKey(foreignFingerprintEchoes))
local foreignFingerprintHash =
    assert(Nexus.DpsCapture.GetEchoHash(foreignFingerprintEchoes))
assert(Nexus.BuildCatalog.Put({
    id=foreignFingerprintId,title="Foreign Fingerprint Only",author="Twin",
    ownerKey="twin@realmb",ownerVerified=true,realm="realmb",
    class="ROGUE",postedAt=80,lastModified=80,
    echoes=foreignFingerprintEchoes,fingerprint=foreignFingerprint,
    fingerprintHash=foreignFingerprintHash,
}), "wrong-owner fingerprint candidate did not initialize")
slots.bySlot[10] = {
    name="Foreign Fingerprint Only",class="MAGE",
    echoes=foreignFingerprintEchoes,
}
ImportAll(controller)
local localFingerprintId, localFingerprintMirror = LocalMirrorForSlot(10)
assert(localFingerprintId and localFingerprintMirror.recordBuildId == nil
    and controller.RecordBuildId(localFingerprintMirror) == nil
    and controller.DpsSummary(localFingerprintMirror).best == 0,
    "wrong-owner fingerprint fixture gained a durable DPS relationship")

local function ForeignDpsWire(category, dps, duration, stamp)
    return {
        v=7,f=foreignFingerprint,h=foreignFingerprintHash,
        e=foreignFingerprintEchoes,c=category,d=dps,u=duration,t=stamp,
        p="Twin",k="ROGUE",o="twin@realmb",r="realmb",l=80,
        b=foreignFingerprintId,
    }
end
assert(Nexus.DpsCapture.ReceiveRecord(
    ForeignDpsWire("dummy", 765432, 65, 701), "Twin-RealmB"),
    "valid foreign Dummy DPS control was rejected")
assert(Nexus.DpsCapture.ReceiveRecord(
    ForeignDpsWire("lk", 654321, 240, 702), "Twin-RealmB"),
    "valid foreign Lich King DPS control was rejected")
local eligibility = Nexus.DpsCapture.GetCommunityEligibility()
assert(eligibility[foreignFingerprint]
    and eligibility[foreignFingerprint].dummy == 765432
    and eligibility[foreignFingerprint].lk == 654321,
    "valid foreign DPS pair did not enter public eligibility")
local foreignPublicRows = ProjectPublic("foreign fingerprint only", true)
local foreignPublic = ProjectedBuild(foreignPublicRows, foreignFingerprintId)
assert(foreignPublic and foreignPublic._nexusQualified == true
    and foreignPublic._nexusDps.dummy == 765432
    and foreignPublic._nexusDps.lk == 654321,
    "valid canonical foreign DPS disappeared from the public build list")
local wrongOwnerRows = ProjectMine("foreign fingerprint only", true)
assert(not ProjectedBuild(wrongOwnerRows, localFingerprintId),
    "EXPECTED RED: wrong-owner fingerprint DPS qualified a local Saved mirror")

local validSaved = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
local validRelation = assert(controller.SavedProjectionRelation(validSaved),
    "verified Saved relation was unavailable to the list projection")
local validRelationEchoes = exactEchoes
local validRelationHash =
    assert(Nexus.DpsCapture.GetEchoHash(validRelationEchoes))
local function LocalDpsWire(category, dps, duration, stamp)
    return {
        v=7,f=validRelation.fingerprint,h=validRelationHash,
        e=validRelationEchoes,c=category,d=dps,u=duration,t=stamp,
        p="Twin",k="MAGE",o="twin@realma",r="realma",l=80,
        b=validRelation.buildId,
    }
end
assert(Nexus.DpsCapture.ReceiveRecord(
    LocalDpsWire("dummy", 876543, 65, 711), "Twin-RealmA")
    and Nexus.DpsCapture.ReceiveRecord(
        LocalDpsWire("lk", 765431, 240, 712), "Twin-RealmA"),
    "valid exact-owner Saved relation DPS controls were rejected")
local validSavedRows = ProjectMine("saved target", true)
local projectedSaved = ProjectedBuild(validSavedRows, validSaved.id)
assert(projectedSaved and projectedSaved._nexusQualified == true
    and projectedSaved._nexusDps.dummy == 876543
    and projectedSaved._nexusDps.lk == 765431,
    "validated Saved relation did not join the bulk DPS eligibility snapshot")
local asyncSavedRows = ProjectMineAsync("saved target", true)
local asyncProjectedSaved = ProjectedBuild(asyncSavedRows, validSaved.id)
assert(asyncProjectedSaved and asyncProjectedSaved._nexusQualified == true
    and asyncProjectedSaved._nexusDps.dummy == 876543
    and asyncProjectedSaved._nexusDps.lk == 765431,
    "async Saved projection diverged from validated relation DPS")

-- Tombstones and opaque SavedVariables values are occupied identities even
-- though BuildCatalog.Get cannot materialize them. Neither Saved mirror nor
-- publication allocation may overwrite or hide data at those identities.
local tombstoneMirrorBase = "saved-twin-11"
assert(Nexus.BuildCatalog.SetTombstone(tombstoneMirrorBase, {
    stamp=900000,author="Twin",
}), "Saved mirror tombstone fixture did not initialize")
slots.bySlot[11] = {
    name="Tombstone Collision Slot",class="MAGE",echoes=Echoes(995001, 6),
}
ImportAll(controller)
local tombstoneMirrorId = LocalMirrorForSlot(11)
local tombstoneMirrorState = Nexus.BuildCatalog.SyncState(tombstoneMirrorBase)
assert(tombstoneMirrorId and tombstoneMirrorId ~= tombstoneMirrorBase
    and tombstoneMirrorState.visible == nil
    and tombstoneMirrorState.delta == nil
    and tombstoneMirrorState.tombstone ~= nil
    and NexusDB.communityBuilds[tombstoneMirrorBase] == nil,
    "EXPECTED RED: Saved mirror allocation wrote through a tombstoned ID")

local opaqueMirrorBase = "saved-twin-12"
local opaqueMirrorValue = "opaque-saved-mirror-collision"
NexusDB.communityBuilds[opaqueMirrorBase] = opaqueMirrorValue
assert(Nexus.BuildCatalog.AllocationOccupancy(opaqueMirrorBase) == "opaque",
    "opaque Saved mirror fixture was not observable as occupied")
slots.bySlot[12] = {
    name="Opaque Collision Slot",class="MAGE",echoes=Echoes(996001, 6),
}
ImportAll(controller)
local opaqueMirrorId = LocalMirrorForSlot(12)
assert(opaqueMirrorId and opaqueMirrorId ~= opaqueMirrorBase
    and NexusDB.communityBuilds[opaqueMirrorBase] == opaqueMirrorValue,
    "EXPECTED RED: Saved mirror allocation overwrote opaque raw storage")

local tombstonePublicationBase = "published-" .. tombstoneMirrorId
assert(Nexus.BuildCatalog.SetTombstone(tombstonePublicationBase, {
    stamp=900001,author="Twin",
}), "publication tombstone fixture did not initialize")
local tombstonePublished, tombstonePublishedId =
    controller.PublishImportedBuild(tombstoneMirrorId)
local tombstonePublicationState =
    Nexus.BuildCatalog.SyncState(tombstonePublicationBase)
local tombstonePublication = tombstonePublishedId
    and Nexus.BuildCatalog.Get(tombstonePublishedId) or nil
assert(tombstonePublished and tombstonePublishedId ~= tombstonePublicationBase
    and tombstonePublicationState.visible == nil
    and tombstonePublicationState.delta == nil
    and tombstonePublicationState.tombstone ~= nil
    and NexusDB.communityBuilds[tombstonePublicationBase] == nil
    and tombstonePublication
    and tombstonePublication.sourceSavedBuildId == tombstoneMirrorId
    and Nexus.Identity.VerifiedOwnerKey(tombstonePublication)
        == "twin@realma",
    "EXPECTED RED: publication allocation wrote through a tombstoned ID")

local opaquePublicationBase = "published-" .. opaqueMirrorId
local opaquePublicationValue = "opaque-publication-collision"
NexusDB.communityBuilds[opaquePublicationBase] = opaquePublicationValue
assert(Nexus.BuildCatalog.AllocationOccupancy(opaquePublicationBase)
        == "opaque",
    "opaque publication fixture was not observable as occupied")
local opaquePublished, opaquePublishedId =
    controller.PublishImportedBuild(opaqueMirrorId)
local opaquePublication = opaquePublishedId
    and Nexus.BuildCatalog.Get(opaquePublishedId) or nil
assert(opaquePublished and opaquePublishedId ~= opaquePublicationBase
    and NexusDB.communityBuilds[opaquePublicationBase]
        == opaquePublicationValue
    and opaquePublication
    and opaquePublication.sourceSavedBuildId == opaqueMirrorId
    and Nexus.Identity.VerifiedOwnerKey(opaquePublication) == "twin@realma",
    "EXPECTED RED: publication allocation overwrote opaque raw storage")

-- Once a collision-safe publication is source-bound, vacating the historical
-- base and persisting a stale published hint must not move the upload target.
local stablePublication = assert(Nexus.BuildCatalog.Get(publishedId))
assert(stablePublication.sourceSavedBuildId == "saved-twin-1"
    and Nexus.Identity.VerifiedOwnerKey(stablePublication) == "twin@realma",
    "stable publication control disappeared before the vacancy regression")
assert(Nexus.BuildCatalog.RemoveOverlay(occupiedId),
    "foreign publication base did not vacate for the stability regression")
assert(Nexus.BuildCatalog.Get(occupiedId) == nil,
    "vacated publication base remained represented")
local stableSource = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
stableSource.publishedBuildId = occupiedId
stableSource.recordBuildId = publishedId
stableSource.lastModified = stableSource.lastModified + 1
assert(Nexus.BuildCatalog.Put(stableSource),
    "stale publication hint did not enter the stability fixture")
local republished, reusedPublicationId =
    controller.PublishImportedBuild("saved-twin-1")
local sourceAfterReuse = assert(Nexus.BuildCatalog.Get("saved-twin-1"))
assert(republished and reusedPublicationId == publishedId
    and sourceAfterReuse.publishedBuildId == publishedId
    and sourceAfterReuse.recordBuildId == publishedId
    and Nexus.BuildCatalog.Get(occupiedId) == nil
    and Nexus.BuildCatalog.Get(publishedId) ~= nil,
    "EXPECTED RED: vacated base or stale hint moved a source-bound publication")

print("saved build related owner: exact-owner-first stale-read-denial projection collision-safe-publish -- OK")
