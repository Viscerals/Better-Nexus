-- Stage 24.1 expected red: Community's default current-class/dual-positive
-- contract remains the default, but explicit opt-outs and 20-row pages must
-- reveal the complete synchronized catalog without changing storage.
local H = dofile("tests/harness.lua")

UnitName = function() return "FixtureOwner" end
GetNormalizedRealmName = function() return "FixtureRealm" end
UnitClass = function() return "Mage", "MAGE" end

local builds, eligibility, buildCount = {}, {}, 0
local function Add(id, class, state, mine, imported)
    buildCount = buildCount + 1
    local index = buildCount
    local fingerprint = "fp-" .. id
    local row = {
        id=id,title=string.format("%02d %s", index, id),
        description="generated fixture",author=mine and "FixtureOwner" or "Peer",
        ownerKey=mine and "fixtureowner@fixturerealm" or "peer@fixturerealm",
        ownerVerified=mine and true or nil,
        realm=mine and "fixturerealm" or nil,
        class=class,fingerprint=fingerprint,fingerprintHash="h-" .. id,
        ordinaryComplete=true,
        echoCount=1,loadoutAvailable=true,postedAt=index,lastModified=index,
        isMine=mine and true or false,importedSavedBuild=imported and true or nil,
    }
    builds[id] = row
    if state == "qualified" then
        eligibility[fingerprint] = {
            dummy=1000 + index,lk=2000 + index,count=2,
            best=2000 + index,average=1500 + index,
        }
    elseif state == "dummy" then
        eligibility[fingerprint] = {
            dummy=1000 + index,lk=0,count=1,best=1000 + index,
        }
    end
end

for index = 1, 25 do
    Add("mage-qualified-" .. index, "MAGE", "qualified", index <= 2)
end
for index = 1, 4 do Add("warrior-qualified-" .. index, "WARRIOR", "qualified") end
for index = 1, 2 do Add("unknown-qualified-" .. index, "UNKNOWN", "qualified") end
for index = 1, 2 do Add("mage-dummy-only-" .. index, "MAGE", "dummy") end
for index = 1, 2 do Add("mage-no-dps-" .. index, "MAGE", "none") end
Add("saved-private", "MAGE", "qualified", true, true)

Nexus.BuildCatalog = {
    Summaries=function() return builds end,
    All=function() return builds end,
}
Nexus.DpsCapture = {
    GetCommunityEligibility=function() return eligibility end,
}
Nexus.Revisions = {
    BUILD_LIBRARY_CHANGED="BUILD_LIBRARY_CHANGED",DPS_CHANGED="DPS_CHANGED",
    Get=function() return 1 end,
}
local P = Nexus.ViewProjections
P.Reset()

local failures = {}
local function Expect(name, condition, detail)
    if not condition then failures[#failures + 1] = name .. ": " .. detail end
end
local function Contains(rows, prefix)
    for _, row in ipairs(rows or {}) do
        if tostring(row.id):find(prefix, 1, true) == 1 then return true end
    end
    return false
end

-- Default compatibility stays green: current MAGE, qualified, first 20.
local defaults, defaultSummary = P.Builds({
    scope="all",sortMode="title",currentClassOnly=true,
    qualifiedOnly=true,page=1,pageSize=20,
})
assert(#defaults == 20 and defaultSummary.qualifying == 25,
    "default current-class dual-positive contract changed")
for _, row in ipairs(defaults) do
    assert(row.class == "MAGE" and row._nexusDps
        and row._nexusDps.count == 2 and not row.importedSavedBuild,
        "default page admitted wrong-class, unqualified, or private rows")
end

-- Class opt-out must expose qualified Warrior and Unknown rows.
P.Reset()
local _, allClassSummary = P.Builds({
    scope="all",sortMode="title",currentClassOnly=false,
    qualifiedOnly=true,page=1,pageSize=20,
})
local allClassesPage2 = P.Builds({
    scope="all",sortMode="title",currentClassOnly=false,
    qualifiedOnly=true,page=2,pageSize=20,
})
Expect("all_classes_filter_is_honored",
    allClassSummary and allClassSummary.filteredTotal == 31
        and Contains(allClassesPage2, "warrior-qualified-")
        and Contains(allClassesPage2, "unknown-qualified-"),
    "caller opt-out was forced back to the current class")

-- Qualification opt-out must expose synchronized one-sided and no-DPS rows.
P.Reset()
local allShared, allSharedSummary = P.Builds({
    scope="all",sortMode="title",currentClassOnly=false,
    qualifiedOnly=false,page=1,pageSize=20,
})
local beforePage = P.Stats().builds
local beforePageKey = P.CacheKeys().builds
local allSharedPage2 = P.Builds({
    scope="all",sortMode="title",currentClassOnly=false,
    qualifiedOnly=false,page=2,pageSize=20,
})
Expect("all_shared_filter_is_honored",
    allSharedSummary and allSharedSummary.filteredTotal == 35
        and Contains(allSharedPage2, "mage-dummy-only-")
        and Contains(allSharedPage2, "mage-no-dps-"),
    "unqualified synchronized rows remained hidden")
local afterPage = P.Stats().builds
Expect("page_change_reuses_cached_projection",
    beforePageKey == P.CacheKeys().builds
        and afterPage.rebuilds == beforePage.rebuilds
        and afterPage.catalogWalks == beforePage.catalogWalks
        and afterPage.dpsReads == beforePage.dpsReads
        and afterPage.sorts == beforePage.sorts,
    "page change reacquired, resorted, or changed the represented query")

-- Page two must reuse the represented query but return rows 21-35.
local secondPage, secondSummary = P.Builds({
    scope="all",sortMode="title",currentClassOnly=false,
    qualifiedOnly=false,page=2,pageSize=20,
})
Expect("second_page_is_distinct",
    secondPage and #secondPage == 15 and secondPage[1]
        and defaults[1] and secondPage[1].id ~= allShared[1].id,
    "page two repeated the first 20 rows")
Expect("page_status_is_truthful",
    secondSummary and secondSummary.page == 2
        and secondSummary.first == 21 and secondSummary.last == 35
        and secondSummary.filteredTotal == 35,
    "projection did not expose showing 21-35 of 35")

-- Selected-build explanations stay on demand instead of retaining payloads
-- or an unbounded reason map for every row.
Expect("bounded_exclusion_explainer_exists",
    type(P.ExplainBuild) == "function",
    "no precise on-demand projection exclusion API exists")
if type(P.ExplainBuild) == "function" then
    local classReason = P.ExplainBuild("warrior-qualified-1", {
        scope="all",currentClassOnly=true,qualifiedOnly=true,
    })
    local oneReason = P.ExplainBuild("mage-dummy-only-1", {
        scope="all",currentClassOnly=false,qualifiedOnly=true,
    })
    local noneReason = P.ExplainBuild("mage-no-dps-1", {
        scope="all",currentClassOnly=false,qualifiedOnly=true,
    })
    Expect("exclusion_reasons_are_precise",
        classReason == "current class filter"
            and oneReason == "missing Lich King record"
            and noneReason == "missing Dummy and Lich King records",
        "selected rows did not receive exact filter/DPS reasons")
end

-- Existing scope/search/sort semantics remain independently green.
P.Reset()
local mine = P.Builds({scope="mine",sortMode="title",search="qualified-1"})
assert(#mine > 0 and #mine <= 2,
    "existing mine/search/sort behavior changed during characterization")
for _, row in ipairs(mine) do
    assert(row.isMine and tostring(row.id):find("qualified-1", 1, true),
        "mine/search scope admitted an unrelated row")
end
assert(builds["saved-private"] ~= nil,
    "display filtering changed complete source storage")

-- Controller accepts additive booleans and preserves unknown preferences.
local settings = {scope="all",sortMode="title",futureFilter="keep"}
local controller = assert(Nexus.CommunityInternals.Controller).New({
    filterSettings=function() return settings end,
})
Expect("controller_accepts_additive_filter_toggles",
    controller.SetFilter("currentClassOnly", false)
        and controller.SetFilter("qualifiedOnly", false),
    "controller rejected the additive class/qualification settings")
Expect("controller_preserves_unknown_filter_fields",
    settings.futureFilter == "keep",
    "additive filter update replaced an unknown preference")

if #failures > 0 then
    error("EXPECTED RED: Stage 24 Community filter characterization:\n - "
        .. table.concat(failures, "\n - "))
end

print("Stage 24 Community filter and page characterization -- OK")
