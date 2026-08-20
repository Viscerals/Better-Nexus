-- Community public projection contract: exact dual-DPS identity, current
-- class, scope/search, selected ordering, first 20, and bounded source work.
Nexus = {}
dofile("core/Revisions.lua")
dofile("core/Identity.lua")
dofile("core/CandidateEvidence.lua")
dofile("core/ViewProjections.lua")
dofile("core/CommunityProjection.lua")

UnitName = function() return "ContractMage" end
GetNormalizedRealmName = function() return "Ebonhold" end
local currentClass = "MAGE"
UnitClass = function()
    if not currentClass then return nil, nil end
    return "Mage", currentClass
end

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, child in pairs(value) do out[Copy(key, seen)] = Copy(child, seen) end
    return out
end

local builds, rawRows = {}, {dummy={},lk={}}
local allCalls, summaryCalls, exactCalls = 0, 0, 0
local perBuildReads, eligibilityReads, rawScans = 0, 0, 0

local function AddBuild(index, class, options)
    options = options or {}
    local id = options.id or string.format("contract-%04d", index)
    local fingerprint = options.fingerprint or ("full-fingerprint-" .. index)
    builds[id] = {
        id=id,
        title=options.title or string.format("Title %04d", 1001-index),
        description=options.description or "",
        author=options.author or "Peer",
        ownerKey=options.ownerKey or "peer@ebonhold",
        ownerVerified=options.ownerVerified,
        realm=options.realm,
        class=class,
        postedAt=options.postedAt or index,
        lastModified=options.lastModified or index,
        importedSavedBuild=options.importedSavedBuild,
        isMine=options.isMine,
        fingerprint=fingerprint,
        fingerprintHash=options.fingerprintHash or ("short-" .. index),
        ordinaryComplete=true,
        echoCount=2,loadoutAvailable=true,
    }
    return builds[id]
end

local function AddDps(category, build, value, player, identity)
    rawRows[category][#rawRows[category] + 1] = {
        buildId=build.id,
        fingerprint=identity or build.fingerprint,
        loadoutHash=build.fingerprintHash,
        dps=value,
        player=player or (category .. "-" .. build.id),
    }
end

-- Forty eligible current-class rows provide enough candidates to prove each
-- selected ordering before the 20-row boundary. Fields deliberately conflict.
for index = 1, 40 do
    local build = AddBuild(index, "MAGE", {
        title=string.format("Eligible %04d", 41-index),
        description=index % 2 == 0 and "needle" or "ordinary",
        postedAt=10000-index,lastModified=10000-index,
        isMine=index <= 25,
        author=index <= 25 and "ContractMage" or "Peer",
        ownerKey=index <= 25 and "contractmage@ebonhold" or "peer@ebonhold",
        ownerVerified=index <= 25 and true or nil,
        realm=index <= 25 and "ebonhold" or nil,
    })
    AddDps("dummy", build, 100000 + index * 100, "Dummy" .. index)
    AddDps("lk", build, 200000 + index * 200, "Lk" .. index)
end

-- Eligible wrong-class rows are newer and stronger, but may never displace a
-- current-class result.
for index = 41, 80 do
    local build = AddBuild(index, "WARRIOR", {
        title=string.format("Wrong %04d", index),
        postedAt=20000+index,lastModified=20000+index,
    })
    AddDps("dummy", build, 900000 + index, "WrongDummy" .. index)
    AddDps("lk", build, 900000 + index, "WrongLk" .. index)
end

-- Newer current-class rows with only one category must be excluded before the
-- limit, as must zero, negative, malformed, and no-DPS rows.
for index = 81, 180 do
    local build = AddBuild(index, "MAGE", {
        title=string.format("Ineligible %04d", index),
        postedAt=30000+index,lastModified=30000+index,
    })
    AddDps("dummy", build, 300000 + index, "OneSided" .. index)
end
for index = 181, 200 do
    local build = AddBuild(index, "MAGE")
    AddDps("dummy", build, index % 2 == 0 and 0 or -index, "BadDummy" .. index)
    AddDps("lk", build, index % 3 == 0 and "bad" or 0, "BadLk" .. index)
end

-- Same opaque ID and short hash, different full fingerprints: neither side is
-- eligible. Legacy per-build lookup stubs below intentionally expose how an ID
-- fallback could otherwise fabricate a pair.
local collision = AddBuild(201, "MAGE", {
    id="collision", fingerprint="collision-full-a", fingerprintHash="same-short",
    postedAt=40000,lastModified=40000,
})
AddDps("dummy", collision, 700000, "CollisionDummy", "collision-full-a")
AddDps("lk", collision, 800000, "CollisionLk", "collision-full-b")

-- Fill the fixture to exactly 500 stored DPS rows without creating another
-- current-class dual-record identity.
local nextIndex = 202
while #rawRows.dummy + #rawRows.lk < 500 do
    local build = builds[string.format("contract-%04d", nextIndex)]
        or AddBuild(nextIndex, nextIndex % 2 == 0 and "WARRIOR" or "MAGE")
    AddDps("dummy", build, 400000 + nextIndex, "Filler" .. nextIndex)
    nextIndex = nextIndex + 1
end
for index = nextIndex, 1000 do AddBuild(index, "MAGE") end

local function BuildEligibility()
    rawScans = rawScans + 1
    local categories = {dummy={},lk={}}
    for _, category in ipairs({"dummy", "lk"}) do
        for _, row in ipairs(rawRows[category]) do
            local fingerprint = type(row.fingerprint) == "string"
                and row.fingerprint or nil
            local value = tonumber(row.dps) or 0
            if fingerprint and fingerprint ~= "" and value > 0 then
                local previous = categories[category][fingerprint] or 0
                if value > previous then categories[category][fingerprint] = value end
            end
        end
    end
    local out = {}
    for fingerprint, dummy in pairs(categories.dummy) do
        local lk = categories.lk[fingerprint]
        if lk and dummy > 0 and lk > 0 then
            out[fingerprint] = {
                dummy=dummy,lk=lk,best=math.max(dummy,lk),
                average=(dummy+lk)/2,count=2,
            }
        end
    end
    return out
end

local eligibility = BuildEligibility()
assert(#rawRows.dummy + #rawRows.lk == 500,
    "contract fixture must contain exactly 500 DPS rows")
local sourceCount = 0; for _ in pairs(builds) do sourceCount = sourceCount + 1 end
assert(sourceCount == 1000, "contract fixture must contain exactly 1,000 builds")

Nexus.BuildCatalog = {
    All=function() allCalls = allCalls + 1; error("full catalog read forbidden") end,
    Summaries=function() summaryCalls = summaryCalls + 1; return Copy(builds) end,
    Get=function(id) exactCalls = exactCalls + 1; return Copy(builds[id]) end,
}
Nexus.DpsCapture = {
    GetCommunityEligibility=function()
        eligibilityReads = eligibilityReads + 1
        return Copy(eligibility)
    end,
    GetLeaderboardForIdentity=function(buildId, _, _, category)
        perBuildReads = perBuildReads + 1
        if buildId == "collision" then
            return {{player="legacy",dps=category == "dummy" and 700000 or 800000}}
        end
        return {}
    end,
}

local P, R = Nexus.ViewProjections, Nexus.Revisions
local factory = assert(Nexus.CommunityInternals
    and Nexus.CommunityInternals.Projection)
local projection = factory.New({
    builds=function(filters) return P.Builds(filters) end,
    buildsCurrent=function(filters) return P.BuildsCurrent(filters) end,
    loadBuild=function(id) return Nexus.BuildCatalog.Get(id) end,
    revisionSnapshot=function()
        return {build=R.Get(R.BUILD_LIBRARY_CHANGED),dps=R.Get(R.DPS_CHANGED)}
    end,
})

local function AssertEligibleRows(rows, label)
    assert(#rows == 20, label .. " must return exactly 20 rows")
    for _, row in ipairs(rows) do
        assert(row.class == "MAGE" and eligibility[row.fingerprint]
            and row.id ~= "collision",
            label .. " exposed wrong-class, ineligible, or colliding identity")
    end
end

local dpsRows, dpsSummary = projection.List({
    scope="all",classFilter="WARRIOR",sortMode="dps",
})
AssertEligibleRows(dpsRows, "DPS sort")
assert(dpsRows[1].id == "contract-0040"
    and dpsRows[20].id == "contract-0021",
    "DPS sort did not limit after descending dual-record average")
assert(dpsSummary.filtered == 20 and dpsSummary.qualifying == 40,
    "projection summary lost returned/qualifying count semantics")

local recentRows = assert(projection.List({scope="all",sortMode="recent"}))
AssertEligibleRows(recentRows, "Recent sort")
assert(recentRows[1].id == "contract-0001"
    and recentRows[20].id == "contract-0020",
    "Recent sort did not use newest timestamp before the limit")

local titleRows = assert(projection.List({scope="all",sortMode="title"}))
AssertEligibleRows(titleRows, "Title sort")
assert(titleRows[1].id == "contract-0040"
    and titleRows[20].id == "contract-0021",
    "Title sort inherited recency or limited before title ordering")

local mineRows = assert(projection.List({scope="mine",sortMode="dps"}))
assert(#mineRows == 20 and mineRows[1].id == "contract-0025"
    and mineRows[20].id == "contract-0006",
    "My Builds scope was not applied before DPS sorting/limit")
local searchRows = assert(projection.List({
    scope="all",search="needle",sortMode="recent",
}))
assert(#searchRows == 20 and searchRows[1].id == "contract-0002"
    and searchRows[20].id == "contract-0040",
    "search was not applied before Recent sorting/limit")

local statsBeforeHit = P.Stats().builds
local sameRows = assert(projection.List({
    scope="all",search="needle",sortMode="recent",
}))
local statsAfterHit = P.Stats().builds
assert(sameRows == searchRows
    and statsAfterHit.catalogWalks == statsBeforeHit.catalogWalks
    and statsAfterHit.dpsReads == statsBeforeHit.dpsReads
    and statsAfterHit.sorts == statsBeforeHit.sorts
    and statsAfterHit.defensiveCopies == statsBeforeHit.defensiveCopies,
    "unchanged Community read walked, joined, sorted, copied, or rebuilt")

currentClass = nil
assert(not projection.ListCurrent({scope="all",sortMode="title"}),
    "missing current class left the old projection current")
local unavailable, unavailableSummary = projection.List({scope="all",sortMode="title"})
assert(#unavailable == 0 and unavailableSummary.filtered == 0,
    "missing current class did not fail closed")
currentClass = "MAGE"
assert(not projection.ListCurrent({scope="all",sortMode="title"}),
    "class recovery did not invalidate the fail-closed projection")
AssertEligibleRows(assert(projection.List({scope="all",sortMode="title"})),
    "recovered class")

assert(allCalls == 0 and exactCalls == 0,
    "opening/projecting Community used full catalog or exact hydration")
assert(perBuildReads == 0,
    "Community projection performed per-build leaderboard lookups")
assert(rawScans == 1,
    "DPS eligibility fixture scanned raw DPS more than once per revision")
assert(eligibilityReads == P.Stats().builds.dpsReads,
    "available-class projection rebuild did not consume one eligibility snapshot")

print(string.format(
    "community projection contract: builds=%d dpsRows=%d returned=%d summaryWalks=%d eligibilityReads=%d rawScans=%d -- OK",
    sourceCount, #rawRows.dummy + #rawRows.lk, #dpsRows,
    summaryCalls, eligibilityReads, rawScans))
