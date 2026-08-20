-- Public Community and Leaderboard projections must publish only loadouts
-- whose ordinary evidence is independently complete. Incomplete rows remain
-- in their injected source stores so this fixture also proves non-destructive
-- filtering.
local H = dofile("tests/harness.lua")
local P = Nexus.ViewProjections
local Evidence = Nexus.LoadoutEvidence
local Revisions = Nexus.Revisions

UnitName = function() return "ProjectionMage" end
GetNormalizedRealmName = function() return "Ebonhold" end

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[Copy(key, seen)] = Copy(child, seen)
    end
    return out
end

local function Echo(index)
    return {spellId=710000 + index,quality=3,stacks=1}
end

local builds = {}
for index = 1, 25 do
    local echo = Echo(index)
    builds["complete-" .. index] = {
        id="complete-" .. index,title=string.format("Build %02d", index),
        author="Peer",ownerKey="peer@ebonhold",class="MAGE",
        postedAt=index,lastModified=index,
        fingerprint=tostring(echo.spellId) .. "x1",
        echoes={echo},
    }
end

-- Prove that exact pool-backed evidence remains public without materializing
-- the pool into the source record.
local poolBacked = builds["complete-1"]
local key, _, referenced = Evidence.Reference(
    poolBacked, "echoes", "evidenceKey")
assert(type(key) == "string" and referenced == true,
    "fixture failed to create exact pool-backed ordinary evidence")
poolBacked.echoes = nil

local pending = {
    {id="pending-summary",ordinaryComplete=false},
    {id="pending-empty",echoes={}},
    {id="pending-unresolved",evidenceKey="missing-evidence"},
    {id="pending-locked",lockedEchoes={{spellId=719001,locked=true,stacks=1}}},
    {id="pending-fingerprint",fingerprint="wrong",
        echoes={{spellId=719002,quality=3,stacks=1}}},
    {id="pending-cross-role",
        echoes={{spellId=719003,quality=3,stacks=1,locked=true}}},
    {id="pending-conflict",recordIdentityMismatch=true,
        fingerprint="719004x1",
        echoes={{spellId=719004,quality=3,stacks=1}}},
    {id="pending-build-conflict",buildIdentityMismatch=true,
        fingerprint="719005x1",
        echoes={{spellId=719005,quality=3,stacks=1}}},
    {id="pending-resolved-conflict",resolvedIdentityMismatch=true,
        fingerprint="719006x1",
        echoes={{spellId=719006,quality=3,stacks=1}}},
    {id="pending-future",evidenceKey="future-owned-evidence"},
}
for index, row in ipairs(pending) do
    row.title = string.format("Build %02d pending", index)
    row.author, row.ownerKey, row.class = "Peer", "peer@ebonhold", "MAGE"
    row.postedAt, row.lastModified = 100 + index, 100 + index
    builds[row.id] = row
end

local sourceCount = 0
for _ in pairs(builds) do sourceCount = sourceCount + 1 end
assert(sourceCount == 35, "fixture source count changed")

local boards = {dummy={},lk={}}
local function BoardRow(player, category, id, echoes, extra)
    local row = {
        player=player,category=category,buildId=id,
        fingerprint=id .. "x1",echoes=echoes,
        dps=category == "dummy" and 1000 or 2000,
        duration=60,ts=1,class="MAGE",
        ownerKey=player:lower() .. "@ebonhold",ownerVerified=true,
    }
    for keyName, value in pairs(extra or {}) do row[keyName] = value end
    return row
end

for _, category in ipairs({"dummy","lk"}) do
    boards[category][#boards[category] + 1] = BoardRow(
        "Complete", category, "720001",
        {{spellId=720001,count=1}})
    boards[category][#boards[category] + 1] = BoardRow(
        "LockedOnly", category, "720002", nil,
        {lockedEchoes={{spellId=729001,count=1,locked=true}}})
    boards[category][#boards[category] + 1] = BoardRow(
        "Unresolved", category, "720003", nil,
        {evidenceKey="missing-board-evidence"})
    boards[category][#boards[category] + 1] = BoardRow(
        "Conflict", category, "720004",
        {{spellId=720004,count=1}},
        {recordIdentityMismatch=category == "dummy"})
end

Nexus.BuildCatalog = {
    Summaries=function() return Copy(builds) end,
    ResolveFingerprintIdentity=function() return nil end,
    Get=function() return nil end,
    ResolveOwnerClass=function() return nil end,
}
Nexus.DpsCapture = {
    GetCommunityEligibility=function() return {} end,
    GetDpsBoard=function(category) return Copy(boards[category] or {}) end,
}

P.Reset()
local page1, summary1 = P.Builds({
    scope="all",classFilter="MAGE",currentClassOnly=true,
    qualifiedOnly=false,sortMode="title",page=1,
})
local page2, summary2 = P.Builds({
    scope="all",classFilter="MAGE",currentClassOnly=true,
    qualifiedOnly=false,sortMode="title",page=2,
})
assert(#page1 == 20 and #page2 == 5,
    string.format("incomplete Community rows changed paging: %d/%d",
        #page1, #page2))
assert(summary1.total == 25 and summary1.resultCount == 25
        and summary1.pageCount == 2 and summary2.pageCount == 2,
    "incomplete Community rows changed public totals or page count")
assert(summary1.ready == 25 and summary1.pending == 10
        and summary2.ready == 25 and summary2.pending == 10,
    "Community complete/pending counters are ambiguous")
for _, page in ipairs({page1,page2}) do
    for _, row in ipairs(page) do
        assert(not tostring(row.id):find("^pending%-"),
            "incomplete Community identity reached a public page")
    end
end
assert(sourceCount == 35,
    "projection filtering destructively changed the source store")

local dummy = P.Leaderboard("dummy", {classFilter="ALL",search=""})
local combined = P.Leaderboard("combined", {classFilter="ALL",search=""})
assert(#dummy == 1 and dummy[1].player == "Complete"
        and dummy[1].ordinaryComplete == true,
    "incomplete category rows reached the public Leaderboard")
assert(#combined == 1 and combined[1].player == "Complete"
        and combined[1].ordinaryComplete == true,
    "incomplete or conflicted rows reached the combined Leaderboard")
assert(#boards.dummy == 4 and #boards.lk == 4,
    "Leaderboard filtering destructively changed internal rows")

local detailProjection = Nexus.CommunityInternals.Projection.New({
    builds=function() return page1, summary1 end,
    buildsCurrent=function() return true end,
    loadBuild=function(id) return Copy(builds[id]) end,
    revisionSnapshot=function() return {build=1,dps=1} end,
})
assert(detailProjection.Detail("pending-conflict", {}) == nil,
    "stale incomplete Community selection retained detail/Copy authority")
local completeDetail = detailProjection.Detail("complete-2", {})
assert(type(completeDetail) == "table" and completeDetail.hasLoadout == true,
    "complete Community selection lost detail/Copy authority")

local before = P.WorkStats()
P.Builds({
    scope="all",classFilter="MAGE",currentClassOnly=true,
    qualifiedOnly=false,sortMode="title",page=1,
})
P.Leaderboard("combined", {classFilter="ALL",search=""})
local after = P.WorkStats()
assert(after.sourceRows == before.sourceRows
        and after.sortMoves == before.sortMoves
        and after.publications == before.publications,
    "warm public completeness reads rebuilt projection work")

print("public completeness: community=25/10 pages=20+5 leaderboard=1 internal=35+8 -- OK")
