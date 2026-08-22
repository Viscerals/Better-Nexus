-- The real DpsCapture index owns Community dual-record eligibility. Exercise
-- its exact fingerprint intersection, revision cache, and defensive snapshot.
local H = dofile("tests/harness.lua")
dofile("core/Revisions.lua")

local function Row(fingerprint, dps, player, buildId, loadoutHash, owner)
    owner = owner or player:lower() .. "@ebonhold"
    return {
        fingerprint=fingerprint,dps=dps,player=player,
        ownerKey=owner,ownerVerified=true,realm="ebonhold",lockedEchoes={},
        buildId=buildId or player,loadoutHash=loadoutHash,
        class="MAGE",level=80,ts=100,duration=60,
    }
end

local dummy = {
    exacthigh=Row("exact-full", 150, "Exact", nil, nil, "exact@ebonhold"),
    onesided=Row("one-sided", 300, "OneSided"),
    collisiondummy=Row("collision-a", 400, "CollisionDummy", "shared-id", "same-short"),
    zero=Row("zero-pair", 0, "Zero"),
    negative=Row("negative-pair", -1, "Negative"),
    malformed=Row("malformed-pair", "bad", "Malformed"),
    infinite=Row("infinite-pair", math.huge, "Infinite"),
    badfingerprint=Row({}, 500, "BadFingerprint"),
}
local lk = {
    exactlk=Row("exact-full", 200, "Exact", nil, nil, "exact@ebonhold"),
    collisionlk=Row("collision-b", 500, "CollisionLk", "shared-id", "same-short"),
    zerolk=Row("zero-pair", 250, "ZeroLk"),
    negativelk=Row("negative-pair", 250, "NegativeLk"),
    malformedlk=Row("malformed-pair", 250, "MalformedLk"),
    infinitelk=Row("infinite-pair", 250, "InfiniteLk"),
}
NexusDB = {
    dpsCapture={
        characterBest={dummy=dummy,lk=lk},
        personalBest={},buildBest={},
    },
}

dofile("core/DpsCapture.lua")
local DPS, R = Nexus.DpsCapture, Nexus.Revisions
local initialRows = 0
for _ in pairs(dummy) do initialRows = initialRows + 1 end
for _ in pairs(lk) do initialRows = initialRows + 1 end

local cold, coldWhy = DPS.GetCachedCommunityQualification(
    "exact-id", "exact-full", nil)
assert(cold==nil and coldWhy=="cache cold"
    and DPS.IdentityLookupStats().rowsScanned==0,
    "cached qualification lookup warmed the cold DPS identity index")

local first = DPS.GetCommunityEligibility()
assert(first["exact-full"]
    and first["exact-full"].dummy == 150
    and first["exact-full"].lk == 200
    and first["exact-full"].average == 175
    and first["exact-full"].count == 2,
    "real eligibility index lost the best exact dual-record pair")
local cachedQualification = DPS.GetCachedCommunityQualification(
    "exact-id", "exact-full", nil)
assert(cachedQualification and cachedQualification.dummy==150
    and cachedQualification.lk==200 and cachedQualification.count==2,
    "cached qualification lookup lost exact dual-record evidence")
for _, fingerprint in ipairs({
    "one-sided", "collision-a", "collision-b", "zero-pair",
    "negative-pair", "malformed-pair", "infinite-pair",
}) do
    assert(first[fingerprint] == nil,
        "real eligibility index admitted invalid identity: " .. fingerprint)
end

first["exact-full"].dummy = -999
first.injected = {dummy=1,lk=1,count=2}
local second = DPS.GetCommunityEligibility()
local cachedStats = DPS.IdentityLookupStats()
assert(second["exact-full"].dummy == 150 and second.injected == nil,
    "eligibility reader leaked its immutable cached snapshot")
assert(cachedStats.rebuilds == 1
    and cachedStats.rowsScanned == initialRows
    and cachedStats.eligibilityReads == 2
    and cachedStats.intersections == 1,
    "unchanged eligibility reads rebuilt or rescanned DPS storage")

lk.onesidedlk = Row("one-sided", 350, "OneSided", nil, nil,
    "onesided@ebonhold")
local advancedRevision = R.Advance(R.DPS_CHANGED, "eligibility fixture")
assert(advancedRevision >= 1, "DPS revision did not advance: "
    .. tostring(advancedRevision))
local stale, staleWhy = DPS.GetCachedCommunityQualification(
    "one-id", "one-sided", nil)
assert(stale==nil and staleWhy=="cache cold",
    "cached qualification lookup used a stale DPS identity index")
local refreshed = DPS.GetCommunityEligibility()
local refreshedStats = DPS.IdentityLookupStats()
assert(refreshed["one-sided"]
    and refreshed["one-sided"].dummy == 300
    and refreshed["one-sided"].lk == 350,
    "DPS revision did not invalidate and refresh eligibility")
assert(refreshed["collision-a"] == nil
    and refreshed["collision-b"] == nil,
    "shared build ID or short hash combined different full fingerprints")
assert(refreshedStats.rebuilds == 2
    and refreshedStats.rowsScanned == initialRows * 2 + 1
    and refreshedStats.eligibilityReads == 3
    and refreshedStats.intersections == 2,
    "eligibility revision refresh performed unexpected index work")

print(string.format(
    "community DPS eligibility: rows=%d rebuilds=%d intersections=%d defensive snapshots -- OK",
    initialRows + 1, refreshedStats.rebuilds, refreshedStats.intersections))
