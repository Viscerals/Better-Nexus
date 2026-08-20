-- Project Ebonhold catalog source changes rebuild atomically and only when
-- represented content changes; failures and family drift retain last-good data.
local H = dofile("tests/harness.lua")
local Source = Nexus.EchoCatalogSource

local function CloneRow(row)
    local copy = {}
    for key, value in pairs(row) do
        if type(value) == "table" then
            local nested = {}
            for nestedKey, nestedValue in pairs(value) do nested[nestedKey] = nestedValue end
            copy[key] = nested
        else
            copy[key] = value
        end
    end
    return copy
end

local function CloneDatabase(source, reverse)
    local ids = {}
    for spellId, row in pairs(source) do
        if type(spellId) == "number" and type(row) == "table" then ids[#ids + 1] = spellId end
    end
    table.sort(ids)
    local copy = {}
    if reverse then
        for index = #ids, 1, -1 do copy[ids[index]] = CloneRow(source[ids[index]]) end
    else
        for _, spellId in ipairs(ids) do copy[spellId] = CloneRow(source[spellId]) end
    end
    return copy
end

-- Pure canonicalization is independent of source insertion order and ignores
-- fields that do not enter the represented runtime catalog.
local names = {[11]="One",[12]="Two",[90]="Tome of One"}
local sourceA = {
    [11]={comment="One - Epic",maxStack=1,classMask=128,minLevel=1,
        quality=3,groupId=0,requiredSpell=90,ignored="left"},
    [12]={comment="Two - Rare",maxStack=2,classMask=128,minLevel=2,
        quality=2,groupId=0,requiredSpell=0,ignored="right"},
}
local sourceB = {
    [12]=CloneRow(sourceA[12]),
    [11]=CloneRow(sourceA[11]),
}
sourceB[11].ignored = "different but irrelevant"
local function Resolve(id) return names[id] end
local candidateA, canonicalA, hashA = Source.Materialize(sourceA, Resolve)
local candidateB, canonicalB, hashB = Source.Materialize(sourceB, Resolve)
assert(candidateA and candidateB and canonicalA == canonicalB and hashA == hashB
    and candidateA.rows[11].name == "One"
    and candidateA.levers[90].conformant == true,
    "equivalent reordered sources did not canonicalize identically")
sourceB[12].quality = 1
local changed, canonicalChanged = Source.Materialize(sourceB, Resolve)
assert(changed and canonicalChanged ~= canonicalA
    and Source.FamilyDrift(candidateA, changed) == nil,
    "relevant non-family source change was not detected")
local grouped = CloneDatabase(sourceA)
grouped[11].groupId = 7
grouped[13] = CloneRow(grouped[11])
names[13] = "One"
local groupedCandidate = Source.Materialize(grouped, Resolve)
local drift = Source.FamilyDrift(candidateA, groupedCandidate)
assert(drift and drift.spellId == 11 and drift.before == "s11" and drift.after == "g7",
    "existing-family drift was not deterministic")
local hostileRow = setmetatable({maxStack=1}, {
    __index=function() error("hostile catalog row") end,
})
local malformed, malformedError = Source.Materialize({[20]=hostileRow}, Resolve)
assert(not malformed and tostring(malformedError):find("hostile catalog row", 1, true),
    "hostile source row did not fail closed")
print("order-independent canonical source and family drift detection -- OK")

NexusDB = {}
Nexus.Errors.Init()
dofile("core/Revisions.lua")
local Revisions = Nexus.Revisions
dofile("core/GameAdapter.lua")
local Adapter = Nexus.GameAdapter
H.projectVersion = "1.0.0"

local function MutationCounts()
    return {
        #H.selectCalls, #H.banishCalls, #H.freezeCalls, H.rerollCalls,
        #H.activateCalls, #H.saveCalls, #H.wire,
    }
end

local function AssertMutationCounts(expected, message)
    local actual = MutationCounts()
    for index, value in ipairs(actual) do
        assert(value == expected[index], message .. " at counter " .. tostring(index))
    end
end

local mutationsBefore = MutationCounts()
local first = Adapter.Catalog()
local firstStatus = Adapter.CatalogStatus()
assert(first and firstStatus.rebuilds == 1 and firstStatus.checks == 1
    and firstStatus.sourceVersion == "1.0.0"
    and Revisions.Get(Revisions.CATALOG_CHANGED) == 1,
    "first catalog publication/version/revision is incorrect")
for _ = 1, 100 do assert(Adapter.Catalog() == first) end
assert(Adapter.CatalogStatus().checks == 1
    and Adapter.CatalogStatus().fastHits == 100
    and Revisions.Get(Revisions.CATALOG_CHANGED) == 1,
    "unchanged normal reads were not O(1) identity hits")

local equivalent = CloneDatabase(H.db, true)
ProjectEbonhold.PerkDatabase = equivalent
assert(Adapter.Catalog() == first
    and Adapter.CatalogStatus().equivalent == 1
    and Revisions.Get(Revisions.CATALOG_CHANGED) == 1,
    "equivalent replacement rebuilt the catalog or advanced its revision")
H.projectVersion = "1.0.1"
assert(Adapter.Catalog() == first
    and Adapter.CatalogStatus().sourceVersion == "1.0.1"
    and Revisions.Get(Revisions.CATALOG_CHANGED) == 1,
    "version-only change created a represented catalog revision")

equivalent[200100].futureField = "ignored"
assert(Adapter.Catalog() == first, "ordinary read scanned an in-place edit")
local checked, checkResult, identityChanged = Adapter.CheckCatalogSource()
assert(checked and checkResult == "unchanged" and not identityChanged
    and Adapter.Catalog() == first
    and Revisions.Get(Revisions.CATALOG_CHANGED) == 1,
    "irrelevant in-place change rebuilt or revised the catalog")

equivalent[200100].quality = 2
assert(Adapter.Catalog() == first, "ordinary read scanned a relevant in-place edit")
checked, checkResult, identityChanged = Adapter.CheckCatalogSource()
local second = Adapter.Catalog()
assert(checked and checkResult == "rebuilt" and identityChanged
    and second ~= first and second.rows[200100].quality == 2
    and Revisions.Get(Revisions.CATALOG_CHANGED) == 2,
    "relevant in-place change did not publish exactly once")
assert(Adapter.CheckCatalogSource()
    and Adapter.Catalog() == second
    and Revisions.Get(Revisions.CATALOG_CHANGED) == 2,
    "repeated content check republished unchanged content")

local replacement = CloneDatabase(equivalent, true)
replacement[200104].maxStack = 4
ProjectEbonhold.PerkDatabase = replacement
local third = Adapter.Catalog()
assert(third ~= second and third.rows[200104].maxStack == 4
    and Revisions.Get(Revisions.CATALOG_CHANGED) == 3,
    "relevant replacement did not rebuild immediately and exactly once")

local familyDrift = CloneDatabase(replacement)
familyDrift[200401] = CloneRow(familyDrift[200400])
familyDrift[200401].requiredSpell = 0
H.names[200401] = "Temporal Echo"
ProjectEbonhold.PerkDatabase = familyDrift
local blocked = Adapter.Catalog()
local blockedStatus = Adapter.CatalogStatus()
assert(blocked == third and blockedStatus.familyBlocks == 1
    and blockedStatus.lastResult == "family-blocked"
    and Revisions.Get(Revisions.CATALOG_CHANGED) == 3,
    "family remap did not retain the last-good catalog")
assert(Adapter.Catalog() == third and Adapter.CatalogStatus().familyBlocks == 1,
    "rejected replacement retried on every normal read")
local latestError = Nexus.Errors.Latest()
assert(latestError and latestError.source == "GameAdapter.Catalog"
    and latestError.message:find("family migration required", 1, true),
    "family-remap failure was not retained as bounded diagnostic evidence")

familyDrift[200401] = nil
H.names[200401] = nil
checked, checkResult, identityChanged = Adapter.CheckCatalogSource()
assert(checked and checkResult == "unchanged" and not identityChanged
    and Adapter.Catalog() == third and Revisions.Get(Revisions.CATALOG_CHANGED) == 3,
    "repaired rejected source did not rebind to the last-good catalog")

local hostileDatabase = {
    [200100]=setmetatable({maxStack=1}, {
        __index=function() error("hostile replacement") end,
    }),
}
ProjectEbonhold.PerkDatabase = hostileDatabase
assert(Adapter.Catalog() == third
    and Adapter.CatalogStatus().lastResult == "failed"
    and Revisions.Get(Revisions.CATALOG_CHANGED) == 3,
    "malformed replacement discarded last-good catalog state")
ProjectEbonhold.PerkDatabase = familyDrift
assert(Adapter.Catalog() == third and Revisions.Get(Revisions.CATALOG_CHANGED) == 3,
    "equivalent recovery after malformed replacement republished data")

-- The noncritical keyed scheduler detects edits to the same source table.
assert(Nexus.Scheduler.Init())
Adapter.Init({}, {})
local pending = Nexus.Scheduler.Pending("catalog.source-check")
assert(pending and pending.kind == "every" and pending.interval == 30
    and Adapter.CatalogStatus().scheduled,
    "catalog source check was not installed on the keyed scheduler")
Adapter.Init({}, {})
local catalogTaskCount = 0
for _, task in ipairs(Nexus.Scheduler.Pending()) do
    if task.key == "catalog.source-check" then
        catalogTaskCount = catalogTaskCount + 1
    end
end
assert(catalogTaskCount == 1,
    "repeated adapter initialization duplicated the catalog source check")
familyDrift[200102].minLevel = familyDrift[200102].minLevel + 1
assert(Adapter.Catalog() == third, "normal read scanned before scheduled check")
local revisionBeforeSchedule = Revisions.Get(Revisions.CATALOG_CHANGED)
assert(Nexus.Scheduler.Tick(H.now + 30.1) >= 1)
local scheduledCatalog = Adapter.Catalog()
assert(scheduledCatalog ~= third
    and scheduledCatalog.rows[200102].minLevel == familyDrift[200102].minLevel
    and Revisions.Get(Revisions.CATALOG_CHANGED) == revisionBeforeSchedule + 1,
    "scheduled in-place source check did not publish one represented change")

-- Resolved spell names are represented catalog data even when the database
-- table itself is unchanged; the slow check must detect resolver changes.
H.names[200102] = "Beta Guard Revised"
assert(Adapter.Catalog() == scheduledCatalog,
    "normal read resolved spell names on the fast path")
local revisionBeforeName = Revisions.Get(Revisions.CATALOG_CHANGED)
checked, checkResult, identityChanged = Adapter.CheckCatalogSource()
local resolvedCatalog = Adapter.Catalog()
assert(checked and checkResult == "rebuilt" and identityChanged
    and resolvedCatalog ~= scheduledCatalog
    and resolvedCatalog.rows[200102].name == "Beta Guard Revised"
    and Revisions.Get(Revisions.CATALOG_CHANGED) == revisionBeforeName + 1,
    "slow source check missed a represented spell-name change")

AssertMutationCounts(mutationsBefore,
    "catalog observation/failure authorized a gameplay mutation")
assert(NexusDB.catalogSource == nil and NexusDB.catalogFingerprint == nil,
    "catalog source tracking leaked into SavedVariables")

-- A real addon reload resets both module-local cache and revision bus; the same
-- source deterministically rebuilds once with the same family map/hash.
local finalHash = Adapter.CatalogStatus().publishedHash
local finalFamily = resolvedCatalog.familyOf[200110]
dofile("core/Revisions.lua")
Revisions = Nexus.Revisions
dofile("core/GameAdapter.lua")
Adapter = Nexus.GameAdapter
local reloadCatalog = Adapter.Catalog()
assert(reloadCatalog and reloadCatalog.familyOf[200110] == finalFamily
    and Adapter.CatalogStatus().publishedHash == finalHash
    and Adapter.CatalogStatus().rebuilds == 1
    and Revisions.Get(Revisions.CATALOG_CHANGED) == 1,
    "reload did not reproduce one deterministic catalog publication")
AssertMutationCounts(mutationsBefore,
    "catalog reload authorized a gameplay mutation")
print("identity/version fast path, atomic rebuild, scheduler, last-good safety -- OK")
