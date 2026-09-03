-- Issue #58 production-seam regression: historical locked rows are display
-- evidence only, rejected identity rows cannot supply DPS maxima, synchronous
-- and resumable summaries agree, strongest single DPS ranks real pairs, and
-- compatible-pair construction has bounded total work.
local H = dofile("tests/harness.lua")

local failures, checks = {}, 0
local function Desired(ok, label)
    checks = checks + 1
    if not ok then failures[#failures + 1] = label end
end

local function Clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do out[Clone(key, seen)] = Clone(child, seen) end
    return out
end

local function Signature(value, seen)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    seen = seen or {}
    if seen[value] then return "cycle" end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        return type(left) .. ":" .. tostring(left)
            < type(right) .. ":" .. tostring(right)
    end)
    local out = {"{"}
    for _, key in ipairs(keys) do
        out[#out + 1] = Signature(key, seen)
        out[#out + 1] = "="
        out[#out + 1] = Signature(value[key], seen)
        out[#out + 1] = ";"
    end
    out[#out + 1] = "}"
    seen[value] = nil
    return table.concat(out)
end

local function EchoKey(echoes)
    local counts, ids = {}, {}
    for _, echo in ipairs(echoes or {}) do
        local id = assert(tonumber(echo.spellId or echo.id))
        counts[id] = (counts[id] or 0)
            + (tonumber(echo.stacks or echo.count) or 1)
    end
    for id in pairs(counts) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        parts[#parts + 1] = tostring(id) .. "x" .. tostring(counts[id])
    end
    return table.concat(parts, ",")
end

local ordinary = {
    {spellId=981001,quality=3,stacks=2,future={ordinary="kept"}},
    {spellId=981002,quality=2,stacks=1},
}
local fingerprint = EchoKey(ordinary)
local locked = {{spellId=981101,quality=4,stacks=1,
    future={history="kept"}}}

local function PairRow(category, dps, owner, spell, overrides)
    local echoes = {{spellId=spell,quality=2,stacks=1}}
    local row = {
        category=category,dps=dps,player=owner,
        ownerKey=owner:lower() .. "@ebonhold",ownerVerified=true,
        realm="ebonhold",class="MAGE",fingerprint=EchoKey(echoes),
        echoes=echoes,lockedEchoes={},buildId="pair-" .. owner,
        duration=category == "lk" and 180 or 60,level=80,ts=1,
    }
    for key, value in pairs(overrides or {}) do row[key] = value end
    return row
end

------------------------------------------------------------------------
-- Strongest single valid DPS, not arithmetic Average, owns pair rank and the
-- public combined Leaderboard projection. Average remains presentational.
------------------------------------------------------------------------
local Evidence = assert(Nexus.CandidateEvidence)
local strongestDummy = PairRow("dummy", 1000, "Strongest", 982001)
local strongestLk = PairRow("lk", 100, "Strongest", 982001)
local balancedDummy = PairRow("dummy", 700, "Balanced", 982002)
local balancedLk = PairRow("lk", 700, "Balanced", 982002)
local ranked = Evidence.RealDpsPairs(
    {balancedDummy,strongestDummy},{balancedLk,strongestLk})
Desired(ranked[1] and ranked[1].dummy == strongestDummy
        and ranked[1].lk == strongestLk
        and ranked[1].bestDps == 1000 and ranked[1].average == 550,
    "Average still owns compatible-pair rank instead of strongest single DPS")

Nexus.DpsCapture = {GetDpsBoard=function(category)
    return category == "dummy" and {balancedDummy,strongestDummy}
        or {balancedLk,strongestLk}
end}
Nexus.ViewProjections.Reset()
local projected = Nexus.ViewProjections.Leaderboard(
    "combined", {classFilter="ALL",search=""})
Desired(projected[1] and projected[1].player == "Strongest"
        and projected[1].dps == 1000 and projected[1].average == 550,
    "combined Leaderboard projection still grants Average ranking/UI authority")

local leaderboardHandle = assert(io.open("ui/Leaderboard.lua", "rb"))
local leaderboardSource = leaderboardHandle:read("*a")
leaderboardHandle:close()
Desired(leaderboardSource:find("Strongest Pair", 1, true)
        and not leaderboardSource:find("Best Average", 1, true)
        and not leaderboardSource:find("ranked by average DPS", 1, true),
    "Leaderboard UI still presents Best Average as ranking authority")

------------------------------------------------------------------------
-- Category maxima are authority-bearing output. A high-DPS row rejected by
-- PairIdentity must not contribute even when a lower compatible pair remains.
------------------------------------------------------------------------
local admittedDummy = PairRow("dummy",600,"Admitted",983000)
local admittedLk = PairRow("lk",500,"Admitted",983000)
local rejectedCases = {
    {
        kind="unverified",
        dummy=PairRow("dummy",9600,"Unverified",983000,
            {ownerVerified=false,claimedOwnerKey="victim@ebonhold",
                relaySender="Relay"}),
        lk=PairRow("lk",9500,"Unverified",983000,
            {ownerVerified=false,claimedOwnerKey="victim@ebonhold",
                relaySender="Relay"}),
    },
    {
        kind="conflicting",
        dummy=PairRow("dummy",9400,"Conflicting",983000,
            {lockedFingerprint="999999x1"}),
        lk=PairRow("lk",9300,"Conflicting",983000,
            {lockedFingerprint="999999x1"}),
    },
    {
        kind="malformed",
        dummy=PairRow("dummy",9200,"Malformed",983000,
            {echoes="malformed"}),
        lk=PairRow("lk",9100,"Malformed",983000,
            {echoes="malformed"}),
    },
}
for _, rejected in ipairs(rejectedCases) do
    local pairs = Evidence.RealDpsPairs(
        {admittedDummy,rejected.dummy},{admittedLk,rejected.lk})
    local summary = Evidence.DpsSummary(
        {admittedDummy,rejected.dummy},{admittedLk,rejected.lk})
    local permuted = Evidence.DpsSummary(
        {rejected.dummy,admittedDummy},{rejected.lk,admittedLk})
    Desired(pairs[1] and pairs[1].dummy == admittedDummy
            and pairs[1].lk == admittedLk
            and summary.dummy == 600 and summary.lk == 500
            and summary.best == 600 and summary.average == 550,
        rejected.kind
            .. " rejected identity evidence still supplies category maxima")
    Desired(Signature(summary) == Signature(permuted),
        rejected.kind .. " rejection changed with input permutation")
end

------------------------------------------------------------------------
-- The synchronous and resumable DpsCapture paths must publish the same
-- independent admitted category maxima even when valid best rows cross owner
-- identities and rejected higher-DPS rows share the fingerprint bucket.
------------------------------------------------------------------------
local crossedDummy = {
    alice=PairRow("dummy",1000,"Alice",983001),
    bob=PairRow("dummy",900,"Bob",983001),
    unverified=PairRow("dummy",9600,"Unverified",983001,
        {ownerVerified=false,claimedOwnerKey="victim@ebonhold",
            relaySender="Relay"}),
    conflicting=PairRow("dummy",9400,"Conflicting",983001,
        {lockedFingerprint="999999x1"}),
    malformed=PairRow("dummy",9200,"Malformed",983001,
        {echoes="malformed"}),
    clean=PairRow("dummy",1200,"Clean",983002),
    oneSided=PairRow("dummy",1300,"OneSided",983003,
        {buildId="collision-a"}),
    paired=PairRow("dummy",700,"Paired",983003,
        {buildId="collision-b"}),
}
local crossedLk = {
    alice=PairRow("lk",800,"Alice",983001),
    bob=PairRow("lk",1100,"Bob",983001),
    unverified=PairRow("lk",9500,"Unverified",983001,
        {ownerVerified=false,claimedOwnerKey="victim@ebonhold",
            relaySender="Relay"}),
    conflicting=PairRow("lk",9300,"Conflicting",983001,
        {lockedFingerprint="999999x1"}),
    malformed=PairRow("lk",9100,"Malformed",983001,
        {echoes="malformed"}),
    clean=PairRow("lk",700,"Clean",983002),
    paired=PairRow("lk",800,"Paired",983003,
        {buildId="collision-b"}),
}
NexusDB = {dpsCapture={characterBest={dummy=crossedDummy,lk=crossedLk},
    personalBest={},buildBest={}}}
dofile("core/Revisions.lua")
dofile("core/DpsCapture.lua")
local synchronous = assert(Nexus.DpsCapture.GetCommunityEligibility()["983001x1"])
local cachedQualification = assert(
    Nexus.DpsCapture.GetCachedCommunityQualification(
        "pair-Alice", "983001x1", nil))
Desired(cachedQualification.dummy == 1000
        and cachedQualification.lk == 800
        and cachedQualification.best == 1000,
    "cached Community qualification escaped the requested build identity")
local qualificationHash = assert(
    Nexus.DpsCapture.GetEchoHash(
        {{spellId=983001,quality=2,stacks=1}}))
local exactQualification = assert(
    Nexus.DpsCapture.GetCachedCommunityQualification(
        "pair-Alice", "983001x1", qualificationHash))
Desired(Signature(exactQualification) == Signature(cachedQualification),
    "matching conjunctive identity lost cached Community qualification")
local hashOnlyQualification = assert(
    Nexus.DpsCapture.GetCachedCommunityQualification(
        nil, nil, qualificationHash))
Desired(Signature(hashOnlyQualification) == Signature(synchronous),
    "matching fingerprint hash lost fingerprint-wide Community qualification")
local function QualificationUnavailable(value)
    if value == nil then return true end
    return type(value) == "table"
        and value.dummy == 0 and value.lk == 0 and value.best == 0
        and value.average == 0 and value.count == 0
end
local mismatchedBuildQualification =
    Nexus.DpsCapture.GetCachedCommunityQualification(
        "pair-Impostor", "983001x1", qualificationHash)
Desired(QualificationUnavailable(mismatchedBuildQualification),
    "mismatched build ID still borrows cached Community qualification")
local mismatchedHashQualification =
    Nexus.DpsCapture.GetCachedCommunityQualification(
        "pair-Alice", "983001x1", "mismatched-hash")
Desired(QualificationUnavailable(mismatchedHashQualification),
    "mismatched fingerprint hash still borrows cached Community qualification")
local collisionHash = assert(Nexus.DpsCapture.GetEchoHash(
    {{spellId=983003,quality=2,stacks=1}}))
local oneSidedQualification = Nexus.DpsCapture.GetCachedCommunityQualification(
    "collision-a", "983003x1", collisionHash)
local pairedQualification = Nexus.DpsCapture.GetCachedCommunityQualification(
    "collision-b", "983003x1", collisionHash)
Desired(QualificationUnavailable(oneSidedQualification),
    "one-sided build borrowed another build's same-fingerprint pair")
Desired(pairedQualification and pairedQualification.dummy == 700
        and pairedQualification.lk == 800 and pairedQualification.best == 800,
    "complete build lost its exact same-fingerprint pair")

local restartDb = Clone(NexusDB)
NexusDB = restartDb
dofile("core/Revisions.lua")
dofile("core/DpsCapture.lua")
local DPS = Nexus.DpsCapture
local eligibilityCursor = DPS.BeginCommunityEligibilityCursor()
local cursorSteps = 0
while eligibilityCursor.phase ~= "done" do
    local done, err = DPS.CommunityEligibilityCursorNext(eligibilityCursor)
    assert(not err, err)
    cursorSteps = cursorSteps + 1
    assert(cursorSteps < 1000, "eligibility cursor did not terminate")
    if done then break end
end
local resumable = assert(DPS.CommunityEligibilityCursorResult(
    eligibilityCursor)["983001x1"])
Desired(Signature(synchronous) == Signature(resumable),
    "synchronous/cursor summaries disagree under crossed category maxima")
local cursorOneSided = DPS.GetCachedCommunityQualification(
    "collision-a", "983003x1", collisionHash)
local cursorPaired = DPS.GetCachedCommunityQualification(
    "collision-b", "983003x1", collisionHash)
Desired(QualificationUnavailable(cursorOneSided),
    "cursor index let one-sided build borrow another build's pair")
Desired(cursorPaired and cursorPaired.dummy == 700
        and cursorPaired.lk == 800 and cursorPaired.best == 800,
    "cursor index lost complete build's exact pair")
Desired(synchronous.dummy == 1000 and synchronous.lk == 1100
        and synchronous.best == 1100 and synchronous.average == 1000,
    "rejected identity evidence still supplies synchronous category maxima")
Desired(resumable.dummy == 1000 and resumable.lk == 1100
        and resumable.best == 1100 and resumable.average == 1000,
    "rejected identity evidence still supplies cursor category maxima")

local syncReplacement = Clone(restartDb)
NexusDB = syncReplacement
dofile("core/Revisions.lua")
dofile("core/DpsCapture.lua")
local syncRebuilt = assert(
    Nexus.DpsCapture.GetCommunityEligibility()["983001x1"])
Desired(Signature(syncRebuilt) == Signature(synchronous),
    "Sync-shaped store replacement changed admitted summary semantics")
local rebuiltOneSided = Nexus.DpsCapture.GetCachedCommunityQualification(
    "collision-a", "983003x1", collisionHash)
local rebuiltPaired = Nexus.DpsCapture.GetCachedCommunityQualification(
    "collision-b", "983003x1", collisionHash)
Desired(QualificationUnavailable(rebuiltOneSided),
    "reload let one-sided build borrow another build's pair")
Desired(rebuiltPaired and rebuiltPaired.dummy == 700
        and rebuiltPaired.lk == 800 and rebuiltPaired.best == 800,
    "reload lost complete build's exact pair")

local realBuildCatalog = Nexus.BuildCatalog
Nexus.BuildCatalog = {Summaries=function() return {
    contaminated={
        id="contaminated",title="Contaminated Candidate",author="Target",
        ownerKey="target@ebonhold",ownerVerified=true,realm="ebonhold",
        class="MAGE",fingerprint="983001x1",ordinaryComplete=true,
        postedAt=1,lastModified=1,
    },
    clean={
        id="clean",title="Clean Candidate",author="Clean",
        ownerKey="clean@ebonhold",ownerVerified=true,realm="ebonhold",
        class="MAGE",fingerprint="983002x1",ordinaryComplete=true,
        postedAt=1,lastModified=1,
    },
} end}
Nexus.ViewProjections.Reset()
local communityRows = assert(Nexus.ViewProjections.Builds({
    scope="all",currentClassOnly=false,sortMode="dps",
}))
Desired(#communityRows == 2 and communityRows[1].id == "clean"
        and communityRows[1]._nexusBestDps == 1200
        and communityRows[2].id == "contaminated"
        and communityRows[2]._nexusBestDps == 1100,
    "rejected identity evidence still supplies Community DPS ranking authority")
Nexus.BuildCatalog = realBuildCatalog

------------------------------------------------------------------------
-- One compatible identity with many historical rows must not produce the
-- old Dummy x LK Cartesian work product. Per-pump and total work are bounded.
------------------------------------------------------------------------
local manyDummy, manyLk = {}, {}
for index = 1, 96 do
    manyDummy[index] = PairRow("dummy",1000 + index,"Budget",984001,
        {sourceIdentity="dummy-" .. tostring(index)})
    manyLk[index] = PairRow("lk",2000 + index,"Budget",984001,
        {sourceIdentity="lk-" .. tostring(index)})
end
local pairCursor = Evidence.BeginRealDpsPairs(manyDummy, manyLk)
local totalWork, pumps, done = 0, 0, false
while not done do
    local work
    done, work = Evidence.PumpRealDpsPairs(pairCursor, 7)
    Desired(work <= 7, "pair cursor exceeded its per-pump work limit")
    totalWork, pumps = totalWork + work, pumps + 1
    assert(pumps < 5000, "pair cursor did not terminate")
end
local boundedPairs = assert(Evidence.RealDpsPairsResult(pairCursor))
Desired(#boundedPairs == 1
        and boundedPairs[1].dummyDps == 1096
        and boundedPairs[1].lkDps == 2096,
    "bounded compatible-pair aggregation lost the real strongest category rows")
Desired(totalWork <= 8 * (#manyDummy + #manyLk),
    "compatible-pair construction still performs Cartesian total work: "
        .. tostring(totalWork))

local sortDummy, sortLk = {}, {}
for index = 1, 128 do
    local owner = string.format("Sort%03d", index)
    sortDummy[index] = PairRow("dummy",1000 + index,owner,985000 + index)
    sortLk[index] = PairRow("lk",500 + index,owner,985000 + index)
end
local sortCursor = Evidence.BeginRealDpsPairs(sortDummy, sortLk)
local sortWork, maxSortPump, sortDone = 0, 0, false
while not sortDone do
    local work
    sortDone, work = Evidence.PumpRealDpsPairs(sortCursor, 11)
    sortWork = sortWork + work
    maxSortPump = math.max(maxSortPump, work)
end
local sortedPairs = assert(Evidence.RealDpsPairsResult(sortCursor))
Desired(maxSortPump <= 11 and #sortedPairs == 128
        and sortedPairs[1].bestDps == 1128,
    "bounded pair ordering lost its per-pump limit or strongest result")
Desired(sortWork <= 16 * (#sortDummy + #sortLk),
    "compatible-pair ordering still performs quadratic total work: "
        .. tostring(sortWork))

------------------------------------------------------------------------
-- Real Leaderboard Copy: historical locked rows stay visible but may not
-- authorize mutation. An exact current catalog row may authorize non-empty or
-- explicitly proven-empty locks without mutating historical snapshots.
------------------------------------------------------------------------
local historicalBuild = {
    id="pr58-copy",title="Historical Copy Fixture",author="Historical",
    class="MAGE",fingerprint=fingerprint,echoes=Clone(ordinary),
    lockedEchoes=Clone(locked),postedAt=1,lastModified=1,
    autoDps=true,
}
local historicalRow = {
    player="Historical",displayPlayer="Historical",category="dummy",
    dps=450000,duration=60,level=80,ts=1,class="MAGE",
    ownerKey="historical@ebonhold",ownerVerified=true,realm="ebonhold",
    buildId=historicalBuild.id,fingerprint=fingerprint,
    echoes=Clone(ordinary),lockedEchoes=Clone(locked),
    lockedFingerprint=EchoKey(locked),build=Clone(historicalBuild),
}
local historicalBefore = Signature(historicalRow)
NexusDB = {communityBuilds={},syncTombstones={},dpsCapture={}}
local Catalog = assert(Nexus.BuildCatalog)
Catalog.Init(NexusDB, Nexus.BundledBuilds)
local autoDpsPage = Clone(historicalBuild)
autoDpsPage.lockedEchoes = nil
assert(Catalog.Put(autoDpsPage))
Nexus.DpsCapture = {GetDpsBoard=function(category)
    return category == "dummy" and {historicalRow} or {}
end}
Nexus.ViewProjections.Reset()
Nexus.Sync = {GetLeaderboardSyncStatus=function() return "idle",0,0,{} end}
dofile("ui/Theme.lua")
dofile("ui/Leaderboard.lua")
local opened
Nexus.WishlistEditor = {OpenForCandidate=function(candidate)
    opened = candidate
    return false
end}
local Leaderboard = Nexus.Leaderboard
Leaderboard.Init(nil)
Leaderboard.Show("dummy")
local selectedKey = "historical@ebonhold|string:" .. fingerprint
assert(Leaderboard.SelectKey(selectedKey), "historical row was not selectable")
local detail = NexusLeaderboardFrame._leaderboardDetail
Desired(not detail.copy:IsEnabled() and detail.copyCandidate == nil,
    "historical auto-DPS locked row still authorizes Copy")
detail.copy:GetScript("OnClick")()
Desired(opened == nil, "historical Copy reached Wishlist mutation")

local currentLocked = {{spellId=981201,quality=4,stacks=1}}
local currentBuild = Clone(historicalBuild)
currentBuild.author = "Current"
if type(Evidence.CurrentCopyAuthority) == "function" then
    local unverifiedAuthority = Evidence.CurrentCopyAuthority(
        currentBuild, "overlay")
    Desired(unverifiedAuthority == nil,
        "matching-ID/fingerprint unverified current catalog build authorized Copy")
end
currentBuild.ownerKey = "current@ebonhold"
currentBuild.ownerVerified = true
currentBuild.realm = "ebonhold"
local relayedCurrent = Clone(currentBuild)
relayedCurrent.relaySender = "Relay"
if type(Evidence.CurrentCopyAuthority) == "function" then
    Desired(Evidence.CurrentCopyAuthority(relayedCurrent, "overlay") == nil,
        "relayed current catalog build authorized Copy")
end
local peerCurrent = Clone(currentBuild)
peerCurrent.claimedOwnerKey = "victim@ebonhold"
if type(Evidence.CurrentCopyAuthority) == "function" then
    Desired(Evidence.CurrentCopyAuthority(peerCurrent, "overlay") == nil,
        "peer-supplied current catalog build authorized Copy")
    Desired(Evidence.CurrentCopyAuthority(currentBuild, "history") == nil,
        "non-current provenance authorized Copy")
end
currentBuild.autoDps = nil
currentBuild.lockedEchoes = Clone(currentLocked)
currentBuild.lockedAuthorityProven = true
currentBuild.lastModified = 2
assert(Catalog.Put(currentBuild))
Leaderboard.Show("dummy")
Leaderboard.RefreshData()
assert(Leaderboard.SelectKey(selectedKey), "current-authority row was not selectable")
detail = NexusLeaderboardFrame._leaderboardDetail
opened = nil
detail.copy:GetScript("OnClick")()
Desired(opened and #opened.lockedEchoes == 1
        and opened.lockedEchoes[1].spellId == 981201,
    "verified exact current locked authority did not own Copy")

currentBuild.lockedEchoes = {}
currentBuild.lockedAuthorityProven = true
currentBuild.lastModified = 3
assert(Catalog.Put(currentBuild))
Leaderboard.Show("dummy")
Leaderboard.RefreshData()
assert(Leaderboard.SelectKey(selectedKey), "verified-empty row was not selectable")
detail = NexusLeaderboardFrame._leaderboardDetail
opened = nil
detail.copy:GetScript("OnClick")()
Desired(opened and type(opened.lockedEchoes) == "table"
        and #opened.lockedEchoes == 0,
    "verified empty current locks fell through to historical authority")

------------------------------------------------------------------------
-- Equal-authority/equal-DPS historical duplicates may disagree only in
-- clocks and presentation labels. Pair selection must ignore those fields,
-- while assembled synchronous/resumable rows retain stable identity and the
-- exact current catalog presentation needed by Copy.
------------------------------------------------------------------------
local duplicateDummyA = Clone(historicalRow)
duplicateDummyA.category = "dummy"
duplicateDummyA.player = "Historical"
duplicateDummyA.displayPlayer = "Historical-New"
duplicateDummyA.ts = 900
duplicateDummyA.lastModified = 901
duplicateDummyA.build = {id=historicalBuild.id,title="Stale New Label",
    postedAt=902,nested={capturedAt=903,variant="same"}}
local duplicateDummyB = Clone(duplicateDummyA)
duplicateDummyB.player = "historical"
duplicateDummyB.displayPlayer = "Historical-Old"
duplicateDummyB.ts = 100
duplicateDummyB.lastModified = 101
duplicateDummyB.build.title = "Stale Old Label"
duplicateDummyB.build.postedAt = 102
duplicateDummyB.build.nested.capturedAt = 103
local duplicateLkA = Clone(duplicateDummyA)
duplicateLkA.category = "lk"
duplicateLkA.duration = 180
local duplicateLkB = Clone(duplicateDummyB)
duplicateLkB.category = "lk"
duplicateLkB.duration = 180
local duplicatesBefore = Signature({duplicateDummyA,duplicateDummyB,
    duplicateLkA,duplicateLkB})
local duplicateBoards = {
    dummy={duplicateDummyA,duplicateDummyB},
    lk={duplicateLkB,duplicateLkA},
}
Nexus.DpsCapture = {
    GetDpsBoard=function(category) return duplicateBoards[category] or {} end,
    BeginDpsBoardCursor=function(category)
        return {rows=duplicateBoards[category] or {},index=1,done=false}
    end,
    DpsBoardCursorNext=function(cursor)
        if cursor.index > #cursor.rows then cursor.done = true; return true end
        cursor.index = cursor.index + 1
        return false
    end,
    DpsBoardCursorResult=function(cursor)
        return cursor.done and cursor.rows or nil
    end,
}
Nexus.ViewProjections.Reset()
local duplicateSync = Nexus.ViewProjections.Leaderboard(
    "combined", {classFilter="ALL",search=""})
Nexus.ViewProjections.Reset()
local pending = Nexus.ViewProjections.RequestLeaderboard(
    "combined", {classFilter="ALL",search=""})
Desired(pending == nil, "resumable duplicate projection did not start pending")
local published, pumps = false, 0
while not published do
    local err
    published, err = Nexus.ViewProjections.PumpLeaderboard()
    assert(not err, err)
    pumps = pumps + 1
    assert(pumps < 1000, "duplicate Leaderboard projection did not terminate")
end
local duplicateCursor = Nexus.ViewProjections.RequestLeaderboard(
    "combined", {classFilter="ALL",search=""})
Desired(duplicateSync[1] and duplicateCursor[1]
        and duplicateSync[1].player ~= nil
        and duplicateSync[1].player == duplicateCursor[1].player
        and duplicateSync[1].publicIdentityKey
            == duplicateCursor[1].publicIdentityKey
        and duplicateSync[1].build.title == currentBuild.title
        and duplicateCursor[1].build.title == currentBuild.title
        and duplicateSync[1].dps == duplicateCursor[1].dps,
    "equal-DPS duplicate assembly lost stable identity/title or sync/cursor parity: "
        .. tostring(duplicateSync[1] and duplicateSync[1].player) .. "/"
        .. tostring(duplicateCursor[1] and duplicateCursor[1].player) .. "/"
        .. tostring(duplicateSync[1] and duplicateSync[1].publicIdentityKey) .. "/"
        .. tostring(duplicateSync[1] and duplicateSync[1].build
            and duplicateSync[1].build.title) .. "/"
        .. tostring(duplicateCursor[1] and duplicateCursor[1].build
            and duplicateCursor[1].build.title))
Desired(Signature({duplicateDummyA,duplicateDummyB,duplicateLkA,duplicateLkB})
        == duplicatesBefore,
    "equal-DPS duplicate assembly mutated source records")

Leaderboard.Show("combined")
Leaderboard.RefreshData()
local duplicateSelectedKey = "historical@ebonhold|string:" .. fingerprint
Desired(Leaderboard.SelectKey(duplicateSelectedKey),
    "assembled equal-DPS duplicate row was not selectable")
detail = NexusLeaderboardFrame._leaderboardDetail
opened = nil
detail.copy:GetScript("OnClick")()
Desired(opened and type(opened.lockedEchoes) == "table"
        and #opened.lockedEchoes == 0 and opened.title == currentBuild.title,
    "assembled equal-DPS duplicate lost verified current-authority Copy")

local peerSpoof = Clone(historicalRow)
peerSpoof.ownerVerified = false
peerSpoof.claimedOwnerKey = "spoof@ebonhold"
peerSpoof.relaySender = "SpoofRelay"
peerSpoof.lockedEchoes = {{spellId=981299,quality=4,stacks=1}}
local peerBefore = Signature(peerSpoof)
local peerResolution = Evidence.ResolveLocked({
    build=currentBuild,ordinaryEchoes=ordinary,fingerprint=fingerprint,
    dummyRecord=peerSpoof,copyAuthorityRequired=true,currentProvenance="overlay",
})
Desired(peerResolution.status == "none"
        and #peerResolution.lockedEchoes == 0,
    "peer-spoofed historical locks overrode verified empty current authority")
Desired(Signature(peerSpoof) == peerBefore,
    "peer-spoof resistance mutated the historical record")
Desired(Signature(historicalRow) == historicalBefore,
    "Copy authority resolution mutated historical or unknown fields")

if #failures > 0 then
    error("PR58 expected-red failures (" .. tostring(#failures) .. "): "
        .. table.concat(failures, " | "))
end

print("PR58 authority/pair repair tests passed: " .. tostring(checks))
