-- Stage 32.1 expected red: protocol-6 DPS evidence can retain a complete
-- historical Echo identity after its old build ID has been reused for a
-- different current loadout. Exact qualification must stay fingerprint-only,
-- while a pure bounded classifier distinguishes safe recovery from every
-- fail-closed state without mutating SavedVariables or constructing UI.
local H = dofile("tests/harness.lua")

UnitName = function() return "FixtureOwner" end
GetNormalizedRealmName = function() return "FixtureRealm" end
UnitClass = function() return "Mage", "MAGE" end

local function Count(source)
    local total = 0
    for _ in pairs(source or {}) do total = total + 1 end
    return total
end

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, child in pairs(value) do out[Copy(key, seen)] = Copy(child, seen) end
    return out
end

local function ScalarSnapshot(value, seen)
    local kind = type(value)
    if kind ~= "table" then return kind .. ":" .. tostring(value) end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        local lt, rt = type(left), type(right)
        if lt ~= rt then return lt < rt end
        return tostring(left) < tostring(right)
    end)
    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = ScalarSnapshot(key, seen)
            .. "=" .. ScalarSnapshot(value[key], seen)
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

local function Echoes(base)
    return {
        {spellId=base,count=1},
        {spellId=base+1,count=2},
    }
end

local function Key(base)
    return tostring(base) .. "x1," .. tostring(base+1) .. "x2"
end

local historicalEchoes = Echoes(810100)
local collisionEchoes = Echoes(810200)
local exactEchoes = Echoes(810300)
local warriorEchoes = Echoes(810400)
local historicalFingerprint = Key(810100)
local collisionFingerprint = Key(810200)
local exactFingerprint = Key(810300)
local warriorFingerprint = Key(810400)

local function Build(id, title, class, fingerprint, echoes, fields)
    local row = {
        id=id,title=title,description="sanitized fixture",author="FixturePeer",
        ownerKey="fixturepeer@fixturerealm",class=class,
        fingerprint=fingerprint,echoes=Copy(echoes),echoCount=3,
        loadoutAvailable=true,postedAt=100,lastModified=100,
    }
    for key, value in pairs(fields or {}) do row[key] = value end
    return row
end

local communityBuilds = {
    ["legacy-collision"] = Build("legacy-collision",
        "Collision Fixture", "MAGE", collisionFingerprint, collisionEchoes),
    ["exact-current"] = Build("exact-current",
        "Exact Fixture", "MAGE", exactFingerprint, exactEchoes, {
            author="FixtureOwner",ownerKey="fixtureowner@fixturerealm",
            ownerVerified=true,realm="fixturerealm",isMine=true,
        }),
    ["warrior-current"] = Build("warrior-current",
        "Warrior Fixture", "WARRIOR", warriorFingerprint, warriorEchoes),
}
for index = 1, 21 do
    local base = 811000 + index * 10
    local id = string.format("library-%02d", index)
    communityBuilds[id] = Build(id, string.format("Library %02d", index),
        "MAGE", Key(base), Echoes(base))
end

local function DpsRow(player, category, fingerprint, echoes, fields)
    local row = {
        player=player,category=category,fingerprint=fingerprint,
        echoes=echoes and Copy(echoes) or nil,
        buildId="legacy-collision",dps=category == "dummy" and 210000 or 190000,
        duration=category == "dummy" and 30 or 20,
        ts=500,level=80,class="MAGE",protocolVersion=6,
    }
    for key, value in pairs(fields or {}) do row[key] = value end
    return row
end

local dpsRows = {dummy={},lk={}}
dpsRows.dummy.legacy = DpsRow("LegacyPeer", "dummy",
    historicalFingerprint, historicalEchoes)
dpsRows.lk.legacy = DpsRow("LegacyPeer", "lk",
    historicalFingerprint, historicalEchoes)
dpsRows.dummy.exact = DpsRow("FixtureOwner", "dummy",
    exactFingerprint, exactEchoes, {
        buildId="exact-current",protocolVersion=7,ownerVerified=true,
        ownerKey="fixtureowner@fixturerealm",
    })
dpsRows.lk.exact = DpsRow("FixtureOwner", "lk",
    exactFingerprint, exactEchoes, {
        buildId="exact-current",protocolVersion=7,ownerVerified=true,
        ownerKey="fixtureowner@fixturerealm",
    })
dpsRows.dummy.warrior = DpsRow("WarriorPeer", "dummy",
    warriorFingerprint, warriorEchoes, {
        buildId="warrior-current",protocolVersion=7,ownerVerified=true,
        ownerKey="warriorpeer@fixturerealm",class="WARRIOR",
    })
dpsRows.lk.warrior = DpsRow("WarriorPeer", "lk",
    warriorFingerprint, warriorEchoes, {
        buildId="warrior-current",protocolVersion=7,ownerVerified=true,
        ownerKey="warriorpeer@fixturerealm",class="WARRIOR",
    })

NexusDB = {
    communityBuilds=communityBuilds,
    syncTombstones={untouched={ownerKey="future@realm",ts=77}},
    buildAssociations={future={keep=true}},
    dpsCapture={characterBest=dpsRows,personalBest={},buildBest={}},
    buildFilters={scope="all",currentClassOnly=true,qualifiedOnly=true,
        classFilter="MAGE",search="",sortMode="title",page=1},
    futureRoot={keep=true},
}

dofile("core/DpsCapture.lua")
local DPS = Nexus.DpsCapture
DPS.Init({}, {})
Nexus.ViewProjections.Reset()

local source = io.open("core/LegacyQualificationRepair.lua", "rb")
if source then
    source:close()
    dofile("core/LegacyQualificationRepair.lua")
end

local failures = {}
local function Check(ok, name, detail)
    if not ok then
        failures[#failures + 1] = name .. (detail and ": " .. detail or "")
    end
end

local function Find(rows, id)
    for _, row in ipairs(rows or {}) do
        if row.id == id then return row end
    end
end

-- Current behavior is intentionally green: the colliding current build is
-- not qualified by its reused ID, disabling Qualified Only exposes it, and
-- an exact current fingerprint remains qualified without any repair.
local P = Nexus.ViewProjections
local collisionQualified, collisionQualifiedSummary = P.Builds({
    scope="all",currentClassOnly=true,qualifiedOnly=true,
    search="Collision",sortMode="title",page=1,
})
assert(#collisionQualified == 0
        and collisionQualifiedSummary.filteredTotal == 0,
    "build-ID collision fabricated exact qualification")
P.Reset()
local collisionLibrary, collisionLibrarySummary = P.Builds({
    scope="all",currentClassOnly=true,qualifiedOnly=false,
    search="Collision",sortMode="title",page=1,
})
assert(#collisionLibrary == 1
        and collisionLibrarySummary.filteredTotal == 1
        and collisionLibrary[1].id == "legacy-collision"
        and collisionLibrary[1]._nexusQualified == false,
    "Qualified Only opt-out did not expose the stored collision fixture")
P.Reset()
local exactRows = P.Builds({
    scope="all",currentClassOnly=true,qualifiedOnly=true,
    search="Exact",sortMode="dps",page=1,
})
assert(#exactRows == 1 and exactRows[1].id == "exact-current"
        and exactRows[1]._nexusQualified == true
        and exactRows[1]._nexusDps.count == 2,
    "exact current fingerprint stopped qualifying")

-- Existing current-class, scope, search, sort, and real 20-row paging remain
-- independently usable before the new classifier exists.
P.Reset()
local allClasses = P.Builds({scope="all",currentClassOnly=false,
    qualifiedOnly=true,search="Warrior",sortMode="recent",page=1})
assert(#allClasses == 1 and allClasses[1].id == "warrior-current",
    "current-class opt-out lost a valid exact Warrior build")
P.Reset()
local mine = P.Builds({scope="mine",currentClassOnly=true,
    qualifiedOnly=true,search="Fixture",sortMode="title",page=1})
assert(#mine == 1 and mine[1].id == "exact-current",
    "My Builds/search/sort control lost the exact local build")
P.Reset()
local pageOne, pageOneSummary = P.Builds({scope="all",
    currentClassOnly=true,qualifiedOnly=false,search="",sortMode="title",page=1})
local workBeforePage = P.Stats().builds
local pageTwo, pageTwoSummary = P.Builds({scope="all",
    currentClassOnly=true,qualifiedOnly=false,search="",sortMode="title",page=2})
local workAfterPage = P.Stats().builds
assert(#pageOne == 20 and #pageTwo == 3
        and pageOneSummary.filteredTotal == 23
        and pageTwoSummary.first == 21 and pageTwoSummary.last == 23
        and not Find(pageOne, pageTwo[1].id)
        and workAfterPage.rebuilds == workBeforePage.rebuilds
        and workAfterPage.catalogWalks == workBeforePage.catalogWalks
        and workAfterPage.dpsReads == workBeforePage.dpsReads
        and workAfterPage.sorts == workBeforePage.sorts,
    "real 20-row page change rebuilt or repeated the first page")

local dbBefore = ScalarSnapshot(NexusDB)
local revisionsBefore = ScalarSnapshot(Nexus.Revisions.Snapshot())
local catalogBefore = Nexus.BuildCatalog.DebugStats()
local framesBefore = Count(H.frames)
local buildsBefore = Count(NexusDB.communityBuilds)
local dpsBefore = Count(NexusDB.dpsCapture.characterBest.dummy)
    + Count(NexusDB.dpsCapture.characterBest.lk)
local tombstonesBefore = Count(NexusDB.syncTombstones)
local associationsBefore = Count(NexusDB.buildAssociations)

local goodHistoricalDummy = DpsRow("LegacyPeer", "dummy",
    historicalFingerprint, historicalEchoes)
local goodHistoricalLk = DpsRow("LegacyPeer", "lk",
    historicalFingerprint, historicalEchoes)
local collisionBuild = Copy(NexusDB.communityBuilds["legacy-collision"])
local exactBuild = Copy(NexusDB.communityBuilds["exact-current"])

local cases = {
    {name="no_catalog", expected="no-catalog", input={
        catalogAvailable=false,dummy=goodHistoricalDummy,lk=goodHistoricalLk,
    }},
    {name="no_dps", expected="no-dps", input={
        catalogAvailable=true,build=collisionBuild,
    }},
    {name="one_category", expected="one-category", input={
        catalogAvailable=true,build=collisionBuild,dummy=goodHistoricalDummy,
    }},
    {name="duration_or_category", expected="duration-or-category", input={
        catalogAvailable=true,build=collisionBuild,
        dummy=DpsRow("LegacyPeer", "dummy", historicalFingerprint,
            historicalEchoes, {duration=29}),
        lk=goodHistoricalLk,
    }},
    {name="exact_current", expected="exact-current", qualified=true, input={
        catalogAvailable=true,build=exactBuild,
        dummy=DpsRow("FixtureOwner", "dummy", exactFingerprint, exactEchoes, {
            buildId="exact-current",protocolVersion=7,ownerVerified=true,
            ownerKey="fixtureowner@fixturerealm",
        }),
        lk=DpsRow("FixtureOwner", "lk", exactFingerprint, exactEchoes, {
            buildId="exact-current",protocolVersion=7,ownerVerified=true,
            ownerKey="fixtureowner@fixturerealm",
        }),
    }},
    {name="recoverable_history", expected="recoverable-history",
        recoverable=true,collision=true,ownership="unverified", input={
            catalogAvailable=true,build=collisionBuild,
            dummy=goodHistoricalDummy,lk=goodHistoricalLk,
        }},
    {name="build_id_collision", expected="build-id-collision", collision=true,
        input={catalogAvailable=true,build=collisionBuild,
            dummy=DpsRow("LegacyPeer", "dummy", historicalFingerprint, nil),
            lk=DpsRow("LegacyPeer", "lk", historicalFingerprint, nil),
        }},
    {name="insufficient_evidence", expected="insufficient-evidence", input={
        catalogAvailable=true,build=collisionBuild,
        dummy=goodHistoricalDummy,
        lk=DpsRow("LegacyPeer", "lk", historicalFingerprint, Echoes(810150)),
    }},
    {name="unauthorized_owner", expected="unauthorized-owner",
        ownership="unauthorized", input={catalogAvailable=true,
            build=collisionBuild,
            dummy=DpsRow("LegacyPeer", "dummy", historicalFingerprint,
                historicalEchoes, {ownerVerified=true,ownerKey="one@realm"}),
            lk=DpsRow("OtherPeer", "lk", historicalFingerprint,
                historicalEchoes, {ownerVerified=true,ownerKey="two@realm"}),
        }},
    {name="stale_or_superseded", expected="stale-or-superseded", input={
        catalogAvailable=true,build=collisionBuild,
        dummy=goodHistoricalDummy,lk=goodHistoricalLk,superseded=true,
    }},
}

local Repair = Nexus.LegacyQualificationRepair
Check(type(Repair) == "table", "legacy_repair_owner_exists",
    "Nexus.LegacyQualificationRepair is unavailable")
Check(type(Repair) == "table" and type(Repair.Classify) == "function",
    "legacy_classifier_exists", "Classify is unavailable")
local diagnostics = {}
for _, fixture in ipairs(cases) do
    local inputBefore = ScalarSnapshot(fixture.input)
    local result
    if type(Repair) == "table" and type(Repair.Classify) == "function" then
        local ok, value = pcall(Repair.Classify, fixture.input)
        if ok then result = value end
    end
    diagnostics[fixture.name] = result
    Check(type(result) == "table" and result.reason == fixture.expected,
        "reason_" .. fixture.name,
        "expected=" .. fixture.expected .. " got="
            .. tostring(result and result.reason or "classifier unavailable"))
    if type(result) == "table" then
        Check(result.schema == 1, "schema_" .. fixture.name,
            "diagnostic schema is not 1")
        Check(result.qualified == (fixture.qualified == true),
            "qualified_" .. fixture.name, "qualification flag changed")
        Check(result.recoverable == (fixture.recoverable == true),
            "recoverable_" .. fixture.name, "recovery flag changed")
        Check(result.collision == (fixture.collision == true),
            "collision_" .. fixture.name, "collision flag changed")
        Check(result.ownership == (fixture.ownership or "none"),
            "ownership_" .. fixture.name,
            "expected=" .. tostring(fixture.ownership or "none")
                .. " got=" .. tostring(result.ownership))
    end
    Check(ScalarSnapshot(fixture.input) == inputBefore,
        "classifier_input_immutable_" .. fixture.name,
        "classification mutated its fixture")
end

local allowedResultKeys = {
    schema=true,reason=true,qualified=true,recoverable=true,
    collision=true,ownership=true,
}
local forbiddenKeys = {
    title=true,echoes=true,player=true,ownerKey=true,payload=true,
    packet=true,savedVariables=true,build=true,dummy=true,lk=true,
}
for name, result in pairs(diagnostics) do
    if type(result) == "table" then
        local fields = 0
        for key, value in pairs(result) do
            fields = fields + 1
            Check(allowedResultKeys[key] == true,
                "bounded_diagnostic_key_" .. name,
                "unexpected key=" .. tostring(key))
            Check(forbiddenKeys[key] ~= true and type(value) ~= "table",
                "scalar_diagnostic_value_" .. name,
                "non-scalar or sensitive field=" .. tostring(key))
        end
        Check(fields == 6, "fixed_diagnostic_shape_" .. name,
            "fields=" .. tostring(fields))
    end
end

local catalogAfter = Nexus.BuildCatalog.DebugStats()
local buildsAfter = Count(NexusDB.communityBuilds)
local dpsAfter = Count(NexusDB.dpsCapture.characterBest.dummy)
    + Count(NexusDB.dpsCapture.characterBest.lk)
assert(buildsAfter == buildsBefore and dpsAfter == dpsBefore
        and Count(NexusDB.syncTombstones) == tombstonesBefore
        and Count(NexusDB.buildAssociations) == associationsBefore
        and ScalarSnapshot(NexusDB) == dbBefore
        and ScalarSnapshot(Nexus.Revisions.Snapshot()) == revisionsBefore
        and catalogAfter.putCalls == catalogBefore.putCalls
        and catalogAfter.putChanges == catalogBefore.putChanges
        and Count(H.frames) == framesBefore
        and NexusDB.futureRoot.keep
        and NexusDB.buildAssociations.future.keep,
    "characterization changed builds, DPS, authority, unknown fields, revisions, catalog work, or UI")

if #failures > 0 then
    print(string.format(
        "Stage 32.1 controls: builds=%d dps=%d pages=20+3 exact=1 collision-qualified=0 mutation=0",
        buildsAfter,dpsAfter))
    error("EXPECTED RED [Stage 32.1 legacy qualification]:\n - "
        .. table.concat(failures, "\n - "))
end

print(string.format(
    "Stage 32.1 legacy qualification: reasons=%d builds=%d dps=%d pages=20+3 mutation=0 -- OK",
    #cases,buildsAfter,dpsAfter))
