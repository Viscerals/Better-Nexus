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
        build={id=1,title="Numeric",class="MAGE"}}},
    lk={{player="Collision",buildId="1",dps=200,category="lk",
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
collisionBoards.dummy[1].lockedEchoes = {{spellId=810001,count=1}}
collisionBoards.lk[1].lockedEchoes = {{spellId=810002,count=1}}
Revisions.Advance(Revisions.DPS_CHANGED, {scope="all"})
local lockedConflict = P.Leaderboard("combined", {classFilter="ALL"})
assert(#lockedConflict == 1 and lockedConflict[1].lockedEvidenceMismatch == true,
    "combined record silently selected conflicting locked evidence")
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
