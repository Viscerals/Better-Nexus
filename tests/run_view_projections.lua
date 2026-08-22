-- Revision/filter-cached Community Builds and Leaderboard projections.
local H = dofile("tests/harness.lua")
local Revisions = Nexus.Revisions
local P = Nexus.ViewProjections

UnitName = function() return "ProjectionMage" end
GetNormalizedRealmName = function() return "Ebonhold" end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, child in pairs(value) do out[DeepCopy(key, seen)] = DeepCopy(child, seen) end
    return out
end

local builds = {}
for index = 1, 1000 do
    local id = string.format("projection-%04d", index)
    local fingerprint = tostring(500000+index).."x1"
    builds[id] = {
        id=id, title=string.format("Build %04d", 1001-index),
        description=index % 7 == 0 and "needle" or "",
        author=index % 10 == 0 and "ProjectionMage" or "Peer",
        ownerKey=index % 10 == 0 and "projectionmage@ebonhold" or "peer@ebonhold",
        ownerVerified=true,
        class=index % 2 == 0 and "MAGE" or "WARRIOR",
        postedAt=index, lastModified=index,
        importedSavedBuild=index <= 15 and true or nil,
        fingerprint=fingerprint,
        echoes={{spellId=500000+index,quality=3,stacks=1}},
    }
end

local catalogWalks, boardReads, eligibilityReads = 0, 0, 0
Nexus.BuildCatalog = {Summaries=function()
    catalogWalks = catalogWalks + 1
    return DeepCopy(builds)
end}

local boards = {dummy={},lk={}}
for index = 1, 100 do
    local common = {
        player="Player"..index, buildId="board-"..index,
        ownerKey="player"..index.."@realma",ownerVerified=true,
        realm="realma",
        fingerprint=tostring(600000+index).."x1",
        build={id="board-"..index,title="Board "..index,
            author="Author"..index,class=index%2==0 and "MAGE" or "WARRIOR",
            fingerprint=tostring(600000+index).."x1"},
        echoes={{spellId=600000+index,count=1}}, level=80,
    }
    local dummy = DeepCopy(common); dummy.category="dummy"
    dummy.dps=1000000+index*100; dummy.duration=60; dummy.ts=index
    local lk = DeepCopy(common); lk.category="lk"
    lk.dps=2000000+index*100; lk.duration=120; lk.ts=index
    boards.dummy[#boards.dummy+1] = dummy
    boards.lk[#boards.lk+1] = lk
end
table.sort(boards.dummy,function(a,b) return a.dps>b.dps end)
table.sort(boards.lk,function(a,b) return a.dps>b.dps end)

local eligibility = {}
for index = 1, 1000 do
    eligibility[tostring(500000+index).."x1"] = {
        dummy=10*index,lk=20*index,best=20*index,
        average=15*index,count=2,
    }
end

Nexus.DpsCapture = {
    GetCommunityEligibility=function()
        eligibilityReads = eligibilityReads + 1
        return DeepCopy(eligibility)
    end,
    GetDpsBoard=function(category)
        boardReads = boardReads + 1
        return DeepCopy(boards[category] or {})
    end,
}
function Nexus.DpsCapture.BeginDpsBoardCursor(category)
    return {rows=DeepCopy(boards[category] or {}),index=0}
end
function Nexus.DpsCapture.DpsBoardCursorNext(cursor)
    cursor.index = cursor.index + 1
    return cursor.index > #cursor.rows
end
function Nexus.DpsCapture.DpsBoardCursorResult(cursor)
    return cursor.rows
end

P.Reset()
local first, firstSummary = P.Builds({scope="all",classFilter="MAGE",sortMode="recent"})
assert(#first == 20 and first[1].lastModified == 1000
    and firstSummary.total == 1000 and firstSummary.pending == 0
    and firstSummary.qualifying == 493 and firstSummary.filtered == 20,
    "build projection changed established scope/class/recent behavior")
local afterFirst = P.Stats()
assert(afterFirst.builds.defensiveCopies == 1,
    "build projection rebuild copied the full result more than once")
local second, secondSummary = P.Builds({scope="all",classFilter="MAGE",sortMode="recent"})
local afterSecond = P.Stats()
assert(#second == #first and secondSummary.filtered == #first
    and catalogWalks == 1
    and afterSecond.builds.catalogWalks == afterFirst.builds.catalogWalks
    and afterSecond.builds.dpsReads == afterFirst.builds.dpsReads
    and afterSecond.builds.sorts == afterFirst.builds.sorts
    and afterSecond.builds.defensiveCopies == afterFirst.builds.defensiveCopies + 1
    and afterSecond.builds.hits == afterFirst.builds.hits + 1,
    "unchanged build projection walked or sorted after warm-up")
second[1].title = "mutated"
assert(P.Builds({scope="all",classFilter="MAGE",sortMode="recent"})[1].title ~= "mutated",
    "caller mutated cached build projection")

local mine, mineSummary = P.Builds({scope="mine",search="needle",sortMode="title"})
assert(mineSummary.savedLoadouts == 15 and mineSummary.uploaded == 99
    and #mine > 0,
    "owner/scope/search projection summary changed")
local beforeStatus = P.Stats().builds.rebuilds
Revisions.Advance(Revisions.SYNC_CHANGED, {scope="status"})
assert(P.BuildsCurrent({scope="mine",search="needle",sortMode="title"}),
    "status-only revision made the current build projection look dirty")
P.Builds({scope="mine",search="needle",sortMode="title"})
assert(P.Stats().builds.rebuilds == beforeStatus,
    "status-only revision invalidated build projection")
local beforeDirtyProbe = P.Stats().builds
Revisions.Advance(Revisions.DPS_CHANGED, {scope="all"})
assert(not P.BuildsCurrent({scope="mine",search="needle",sortMode="title"})
    and P.Stats().builds.catalogWalks == beforeDirtyProbe.catalogWalks
    and P.Stats().builds.dpsReads == beforeDirtyProbe.dpsReads
    and P.Stats().builds.sorts == beforeDirtyProbe.sorts
    and P.Stats().builds.defensiveCopies == beforeDirtyProbe.defensiveCopies,
    "dirty probe performed projection work")
P.Builds({scope="mine",search="needle",sortMode="title"})
assert(P.Stats().builds.rebuilds == beforeStatus + 1,
    "DPS revision did not invalidate DPS-sorted build metadata")

-- Imported Saved rows may join the bulk eligibility snapshot only through a
-- relation that the Community controller already validated. Binding changes
-- projection identity, and a warm cache must not re-run the resolver.
local savedFilters = {scope="mine",search="build 0991",sortMode="dps",
    currentClassOnly=false,qualifiedOnly=true}
eligibility["500010x1"] = {dummy=0,lk=0,best=0,average=0,count=0}
Revisions.Advance(Revisions.DPS_CHANGED, {scope="saved-relation"})
assert(#P.Builds(savedFilters) == 0,
    "raw Saved fingerprint remained qualified without a relation resolver")
local relationCalls = 0
local function ResolveSaved(build)
    relationCalls = relationCalls + 1
    if build.id == "projection-0010" then
        local projected = {}
        for key, value in pairs(build) do projected[key] = value end
        projected.recordBuildId = "projection-0020"
        projected.class = "MAGE"
        return projected,
            {buildId="projection-0020",fingerprint="500020x1"}
    end
    return nil
end
assert(P.BindSavedRelationResolver(ResolveSaved),
    "Saved relation resolver did not invalidate the build projection")
local resolvedSaved = P.Builds(savedFilters)
assert(#resolvedSaved == 1 and resolvedSaved[1].id == "projection-0010"
    and resolvedSaved[1]._nexusDps.dummy == 200
    and resolvedSaved[1]._nexusDps.lk == 400
    and relationCalls == 1,
    "Saved relation did not join its canonical target eligibility")
assert((P.WorkStats().joins or 0) >= 1,
    "Saved relation join was omitted from bounded work telemetry")
local warmRelationCalls = relationCalls
assert(#P.Builds(savedFilters) == 1 and relationCalls == warmRelationCalls,
    "warm Saved projection repeated relation resolution")
assert(P.BindSavedRelationResolver(function() return nil end)
    and not P.BuildsCurrent(savedFilters)
    and #P.Builds(savedFilters) == 0,
    "rebinding the Saved relation policy did not fail closed")
P.BindSavedRelationResolver(nil)
eligibility["500010x1"] = {
    dummy=100,lk=200,best=200,average=150,count=2,
}
Revisions.Advance(Revisions.DPS_CHANGED, {scope="saved-relation-reset"})

local combined = P.Leaderboard("combined", {classFilter="MAGE",search="player"})
assert(#combined == 50 and combined[1].category == "combined"
    and combined[1].average == (combined[1].dummyDps+combined[1].lkDps)/2,
    "combined leaderboard pairing/filter projection changed: rows="
        ..tostring(#combined).." first="
        ..tostring(combined[1] and combined[1].resolvedClass))
local boardReadsAfter = boardReads
local combinedAgain = P.Leaderboard("combined", {classFilter="MAGE",search="player"})
assert(#combinedAgain == #combined and boardReads == boardReadsAfter,
    "unchanged leaderboard projection reread DPS boards")
combinedAgain[1].player = "mutated"
assert(P.Leaderboard("combined", {classFilter="MAGE",search="player"})[1].player ~= "mutated",
    "caller mutated cached leaderboard projection")

local duplicateLk = DeepCopy(boards.lk[1])
duplicateLk.dps = duplicateLk.dps + 5000000
duplicateLk.ts = 999999
boards.lk[#boards.lk + 1] = duplicateLk
local nonfiniteLk = DeepCopy(duplicateLk)
nonfiniteLk.dps = math.huge
boards.lk[#boards.lk + 1] = nonfiniteLk
Revisions.Advance(Revisions.DPS_CHANGED, {scope="multi-pair-parity"})
local asyncRows, asyncSummary, asyncReason = P.RequestLeaderboard(
    "combined", {classFilter="MAGE",search=""})
for _ = 1, 1000 do
    if asyncRows then break end
    local _, pumpError = P.PumpLeaderboard()
    assert(pumpError == nil, "resumable multi-pair projection failed")
    asyncRows, asyncSummary, asyncReason = P.RequestLeaderboard(
        "combined", {classFilter="MAGE",search=""})
end
assert(type(asyncRows) == "table" and #asyncRows == 50,
    "resumable projection diverged from one-pair-per-identity selection: "
        .. tostring(asyncReason))
local selectedPair
for _, row in ipairs(asyncRows) do
    if row.ownerKey == duplicateLk.ownerKey then selectedPair = row end
end
assert(selectedPair and selectedPair.lkDps == duplicateLk.dps,
    "resumable projection selected a non-best compatible pair: got="
        .. tostring(selectedPair and selectedPair.lkDps)
        .. " expected=" .. tostring(duplicateLk.dps))
local synchronousRows = P.Leaderboard(
    "combined", {classFilter="MAGE",search=""})
assert(#synchronousRows == #asyncRows,
    "synchronous/resumable pair counts diverged")
for index, row in ipairs(synchronousRows) do
    local async = asyncRows[index]
    assert(async and row.ownerKey == async.ownerKey
            and row.average == async.average
            and row.dummyDps == async.dummyDps
            and row.lkDps == async.lkDps,
        "synchronous/resumable selected-record or sort parity diverged at "
            .. tostring(index))
end

local function Reverse(rows)
    local out = {}
    for index = #rows, 1, -1 do out[#out + 1] = rows[index] end
    return out
end
boards.dummy, boards.lk = Reverse(boards.dummy), Reverse(boards.lk)
P.Reset()
Revisions.Advance(Revisions.SYNC_CHANGED, {scope="wp5-sync-permutation"})
local permutedRows = P.Leaderboard(
    "combined", {classFilter="MAGE",search=""})
assert(#permutedRows == #synchronousRows,
    "Sync input permutation changed real-pair result count")
for index, row in ipairs(permutedRows) do
    local expected = synchronousRows[index]
    assert(expected and row.ownerKey == expected.ownerKey
            and row.average == expected.average
            and row.dummyDps == expected.dummyDps
            and row.lkDps == expected.lkDps,
        "reload/Sync input permutation changed selected pair or sort at "
            .. tostring(index))
end
local restoredLk = {}
for _, row in ipairs(boards.lk) do
    if row.ts ~= 999999 then restoredLk[#restoredLk + 1] = row end
end
boards.lk = restoredLk

local healthySummaries = Nexus.BuildCatalog.Summaries
Nexus.BuildCatalog.Summaries = function() error("forced catalog failure") end
Revisions.Advance(Revisions.BUILD_LIBRARY_CHANGED, {scope="all"})
local failed = P.Builds({scope="all",sortMode="dps"})
assert(failed == nil and P.Stats().builds.failures >= 1,
    "failed projection published partial build cache")
Nexus.BuildCatalog.Summaries = healthySummaries
local recovered = P.Builds({scope="all",sortMode="dps"})
assert(#recovered == 20, "projection did not recover after failed construction")

local healthyEligibility = Nexus.DpsCapture.GetCommunityEligibility
Nexus.DpsCapture.GetCommunityEligibility = function() error("transient DPS failure") end
Revisions.Advance(Revisions.DPS_CHANGED, {scope="all"})
assert(P.Builds({scope="all",sortMode="dps"}) == nil,
    "transient DPS exception published a partial build projection")
Nexus.DpsCapture.GetCommunityEligibility = healthyEligibility
assert(#P.Builds({scope="all",sortMode="dps"}) == 20,
    "build projection did not recover from a transient DPS exception")

local healthyBoard = Nexus.DpsCapture.GetDpsBoard
Nexus.DpsCapture.GetDpsBoard = function() error("transient board failure") end
Revisions.Advance(Revisions.DPS_CHANGED, {scope="all"})
assert(P.Leaderboard("lk", {classFilter="ALL"}) == nil,
    "transient board exception published a cached empty projection")
Nexus.DpsCapture.GetDpsBoard = healthyBoard
assert(#P.Leaderboard("lk", {classFilter="ALL"}) == 100,
    "leaderboard projection did not recover from a transient exception")

-- Lua permits numeric and string IDs simultaneously. Equal display text must
-- neither make final build order unstable nor cross-pair leaderboard records.
local idCollisionBuilds = {
    [1]={id=1,title="Same",author="Peer",ownerKey="peer@ebonhold",
        class="MAGE",postedAt=1,lastModified=1,
        fingerprint="700001x1",
        echoes={{spellId=700001,quality=3,stacks=1}}},
    ["1"]={id="1",title="Same",author="Peer",ownerKey="peer@ebonhold",
        class="MAGE",postedAt=1,lastModified=1,
        fingerprint="700002x1",
        echoes={{spellId=700002,quality=3,stacks=1}}},
}
eligibility = {
    ["700001x1"]={dummy=100,lk=200,best=200,average=150,count=2},
    ["700002x1"]={dummy=100,lk=200,best=200,average=150,count=2},
}
Nexus.BuildCatalog.Summaries = function() return DeepCopy(idCollisionBuilds) end
Revisions.Advance(Revisions.BUILD_LIBRARY_CHANGED, {scope="all"})
local orderedCollision = P.Builds({scope="all",sortMode="title"})
assert(#orderedCollision == 2 and type(orderedCollision[1].id) == "number"
    and type(orderedCollision[2].id) == "string",
    "numeric/string build IDs retained nondeterministic final ordering")

local collisionBoards = {
    dummy={{player="Collision",buildId=1,dps=100,category="dummy",
        ownerKey="collision@realma",ownerVerified=true,realm="realma",
        build={id=1,title="Numeric",class="MAGE"}}},
    lk={{player="Collision",buildId="1",dps=200,category="lk",
        ownerKey="collision@realma",ownerVerified=true,realm="realma",
        build={id="1",title="String",class="MAGE"}}},
}
Nexus.DpsCapture.GetDpsBoard = function(category)
    return DeepCopy(collisionBoards[category] or {})
end
Revisions.Advance(Revisions.DPS_CHANGED, {scope="all"})
assert(#P.Leaderboard("combined", {classFilter="ALL"}) == 0,
    "numeric/string leaderboard IDs falsely paired across categories")
collisionBoards.dummy[1].buildId = "1"
collisionBoards.dummy[1].build.id = "1"
Revisions.Advance(Revisions.DPS_CHANGED, {scope="all"})
assert(#P.Leaderboard("combined", {classFilter="ALL"}) == 0,
    "build ID alone paired leaderboard records across categories")
collisionBoards.dummy[1].fingerprint = "700002x1"
collisionBoards.lk[1].fingerprint = "700002x1"
collisionBoards.dummy[1].echoes = {{spellId=700002,count=1}}
collisionBoards.lk[1].echoes = {{spellId=700002,count=1}}
Revisions.Advance(Revisions.DPS_CHANGED, {scope="all"})
local exactCombined = P.Leaderboard("combined", {classFilter="ALL"})
assert(#exactCombined == 1 and not exactCombined[1].lockedEvidenceMismatch,
    "matching exact fingerprints did not pair leaderboard records")
collisionBoards.lk[1].player = "Collision-RealmB"
collisionBoards.lk[1].ownerKey = "collision@realmb"
collisionBoards.lk[1].realm = "realmb"
Revisions.Advance(Revisions.DPS_CHANGED, {scope="all"})
assert(#P.Leaderboard("combined", {classFilter="ALL"}) == 0,
    "same-name different-realm records were combined")
collisionBoards.lk[1].player = "Collision"
collisionBoards.lk[1].ownerKey = "collision@realma"
collisionBoards.lk[1].realm = "realma"
Revisions.Advance(Revisions.DPS_CHANGED, {scope="all"})
exactCombined = P.Leaderboard("combined", {classFilter="ALL"})
assert(#exactCombined == 1,
    "restored exact owner records did not combine")
collisionBoards.dummy[1].lockedEchoes = {{spellId=810001,count=1}}
collisionBoards.lk[1].lockedEchoes = {{spellId=810002,count=1}}
Revisions.Advance(Revisions.DPS_CHANGED, {scope="all"})
local lockedConflict = P.Leaderboard("combined", {classFilter="ALL"})
assert(#lockedConflict == 0,
    "incompatible locked full-combat identities produced an Average")
collisionBoards.lk[1].lockedEchoes = {{spellId=810001,count=1}}
Revisions.Advance(Revisions.DPS_CHANGED, {scope="all"})
local lockedExact = P.Leaderboard("combined", {classFilter="ALL"})
assert(#lockedExact == 1 and not lockedExact[1].lockedEvidenceMismatch,
    "matching combined locked evidence remained non-actionable")

local beforeReload = P.Leaderboard("lk", {classFilter="ALL",search=""})
dofile("core/ViewProjections.lua")
P = Nexus.ViewProjections
local afterReload = P.Leaderboard("lk", {classFilter="ALL",search=""})
assert(#afterReload == #beforeReload and afterReload[1].player == beforeReload[1].player,
    "module reload changed canonical leaderboard output")

print(string.format(
    "view projections: builds=%d filtered=%d boards=%d catalogWalks=%d eligibilityReads=%d -- OK",
    Count and Count(builds) or 1000, #first, #combined,
    catalogWalks, eligibilityReads))
