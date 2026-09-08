-- The real DpsCapture index owns Community dual-record eligibility. Exercise
-- its exact fingerprint intersection, revision cache, and defensive snapshot.
local H = dofile("tests/harness.lua")
dofile("core/Revisions.lua")

local function Row(fingerprint, dps, player, buildId, loadoutHash, owner)
    owner = owner or player:lower() .. "@ebonhold"
    return {
        fingerprint=fingerprint,dps=dps,player=player,
        echoes=type(fingerprint)=="string" and {{
            spellId=tonumber(fingerprint:match("^(%d+)x1$")),stacks=1,
        }} or nil,
        ownerKey=owner,ownerVerified=true,realm="ebonhold",lockedEchoes={},
        buildId=buildId or player,loadoutHash=loadoutHash,
        class="MAGE",level=80,ts=100,duration=60,
    }
end

local dummy = {
    exacthigh=Row("900001x1", 150, "Exact", "exact-id", nil,
        "exact@ebonhold"),
    onesided=Row("900002x1", 300, "OneSided"),
    collisiondummy=Row("900003x1", 400, "CollisionDummy", "shared-id", "same-short"),
    zero=Row("900005x1", 0, "Zero"),
    negative=Row("900006x1", -1, "Negative"),
    malformed=Row("900007x1", "bad", "Malformed"),
    infinite=Row("900008x1", math.huge, "Infinite"),
    badfingerprint=Row({}, 500, "BadFingerprint"),
}
local lk = {
    exactlk=Row("900001x1", 200, "Exact", "exact-id", nil,
        "exact@ebonhold"),
    collisionlk=Row("900004x1", 500, "CollisionLk", "shared-id", "same-short"),
    zerolk=Row("900005x1", 250, "ZeroLk"),
    negativelk=Row("900006x1", 250, "NegativeLk"),
    malformedlk=Row("900007x1", 250, "MalformedLk"),
    infinitelk=Row("900008x1", 250, "InfiniteLk"),
}
NexusDB = {
    dpsCapture={
        characterBest={dummy=dummy,lk=lk},
        personalBest={},buildBest={},
    },
}

dofile("core/DpsCapture.lua")
local DPS, R = Nexus.DpsCapture, Nexus.Revisions

-- MASTER-RC-009, architecture 3b5de54f lines 1715 and 1721. Init is the only
-- root-binding surface and cannot be called outside the startup coordinator or
-- an explicit supported rebind; status reads return bounded scalars and never
-- imply row authority. Fixture preparation is therefore separated from runtime
-- reads: the raw-global assignment above is setup only, and it is proven here
-- to carry no authority until one explicit admission is driven. Previously
-- this file relied on the first READ to bind and admit the swapped root, which
-- is the exact defect this wave removes.
local preAdmission = Nexus.BuildCatalog.Status()
assert(preAdmission.state == "ROOT_UNBOUND" and preAdmission.readOnly == true
    and preAdmission.generation == 0 and preAdmission.availableCount == 0,
    "the raw-global swap granted row authority without an explicit Init")
assert(Nexus.BuildCatalog.RebindRequired() == "SOURCE_REBIND_REQUIRED",
    "a status read bound the swapped root instead of recording one explicit "
        .. "rebind request")
Nexus.BuildCatalog.Init(NexusDB, Nexus.BundledBuilds)
local admittedRoot = NexusDB
local initialRows = 0
for _ in pairs(dummy) do initialRows = initialRows + 1 end
for _ in pairs(lk) do initialRows = initialRows + 1 end

local cold, coldWhy = DPS.GetCachedCommunityQualification(
    "exact-id", "900001x1", nil)
assert(cold==nil and coldWhy=="cache cold"
    and DPS.IdentityLookupStats().rowsScanned==0,
    "cached qualification lookup warmed the cold DPS identity index")

local first = DPS.GetCommunityEligibility()
assert(first["900001x1"]
    and first["900001x1"].dummy == 150
    and first["900001x1"].lk == 200
    and first["900001x1"].average == 175
    and first["900001x1"].count == 2,
    "real eligibility index lost the best exact dual-record pair")
local cachedQualification = DPS.GetCachedCommunityQualification(
    "exact-id", "900001x1", nil)
assert(cachedQualification and cachedQualification.dummy==150
    and cachedQualification.lk==200 and cachedQualification.count==2,
    "cached qualification lookup lost exact dual-record evidence")
local narrowQualification = DPS.GetCommunityQualification("900001x1")
assert(narrowQualification and narrowQualification.dummy==150
    and narrowQualification.lk==200 and narrowQualification.best==200,
    "narrow qualification reader lost validated eligibility semantics")
narrowQualification.dummy = -999
assert(DPS.GetCommunityQualification("900001x1").dummy==150,
    "narrow qualification reader leaked its cached authority snapshot")
for _, fingerprint in ipairs({
    "900002x1", "900003x1", "900004x1", "900005x1",
    "900006x1", "900007x1", "900008x1",
}) do
    assert(first[fingerprint] == nil,
        "real eligibility index admitted invalid identity: " .. fingerprint)
end

first["900001x1"].dummy = -999
first.injected = {dummy=1,lk=1,count=2}
local second = DPS.GetCommunityEligibility()
local cachedStats = DPS.IdentityLookupStats()
assert(second["900001x1"].dummy == 150 and second.injected == nil,
    "eligibility reader leaked its immutable cached snapshot")
assert(cachedStats.rebuilds == 1
    and cachedStats.rowsScanned == initialRows
    and cachedStats.eligibilityReads == 2
    and cachedStats.intersections == 1,
    "unchanged eligibility reads rebuilt or rescanned DPS storage")

lk.onesidedlk = Row("900002x1", 350, "OneSided", nil, nil,
    "onesided@ebonhold")
local advancedRevision = R.Advance(R.DPS_CHANGED, "eligibility fixture")
assert(advancedRevision >= 1, "DPS revision did not advance: "
    .. tostring(advancedRevision))
local stale, staleWhy = DPS.GetCachedCommunityQualification(
    "one-id", "900002x1", nil)
assert(stale==nil and staleWhy=="cache cold",
    "cached qualification lookup used a stale DPS identity index")
local refreshed = DPS.GetCommunityEligibility()
local refreshedStats = DPS.IdentityLookupStats()
assert(refreshed["900002x1"]
    and refreshed["900002x1"].dummy == 300
    and refreshed["900002x1"].lk == 350,
    "DPS revision did not invalidate and refresh eligibility")
assert(refreshed["900003x1"] == nil
    and refreshed["900004x1"] == nil,
    "shared build ID or short hash combined different full fingerprints")
assert(refreshedStats.rebuilds == 2
    and refreshedStats.rowsScanned == initialRows * 2 + 1
    and refreshedStats.eligibilityReads == 3
    and refreshedStats.intersections == 2,
    "eligibility revision refresh performed unexpected index work")

-- MASTER-RC-009 guarantee, retained explicitly rather than implied: an
-- ordinary read never binds, admits, or mutates an unrelated database. Swap a
-- foreign root under the module, read through every eligibility surface, and
-- prove the foreign root gained no rows and the bound generation did not move.
local unrelated = {dpsCapture={
    characterBest={dummy={},lk={}}, personalBest={}, buildBest={},
}}
local generationBefore = Nexus.BuildCatalog.Status().generation
NexusDB = unrelated
DPS.GetCommunityEligibility()
DPS.GetCommunityQualification("900001x1")
DPS.GetCachedCommunityQualification("exact-id", "900001x1", nil)
assert(next(unrelated.dpsCapture.characterBest.dummy) == nil
    and next(unrelated.dpsCapture.characterBest.lk) == nil
    and next(unrelated.dpsCapture.personalBest) == nil
    and next(unrelated.dpsCapture.buildBest) == nil,
    "an ordinary read wrote into an unrelated database")
assert(Nexus.BuildCatalog.Status().generation == generationBefore
    and Nexus.BuildCatalog.RebindRequired() == "SOURCE_REBIND_REQUIRED",
    "an ordinary read bound or admitted an unrelated database")
NexusDB = admittedRoot

print(string.format(
    "community DPS eligibility: rows=%d rebuilds=%d intersections=%d defensive snapshots -- OK",
    initialRows + 1, refreshedStats.rebuilds, refreshedStats.intersections))
