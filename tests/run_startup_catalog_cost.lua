-- Reproduces the beta's real login/zone initialization sequence with the
-- shipped bundled catalog. Focused suites normally use an empty bundle, which
-- cannot expose full-library defensive-copy pressure.
local H = dofile("tests/harness.lua")
dofile("data/BundledBuilds.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")
dofile("core/Codec.lua")
dofile("core/Sync.lua")
dofile("core/DpsCapture.lua")
dofile("ui/CommunityBuilds.lua")

NexusDB = {
    settings={}, chars={}, communityBuilds={}, syncTombstones={},
    dpsCapture={},
}

local Catalog = Nexus.BuildCatalog
assert(type(Catalog.DebugStats) == "function",
    "BuildCatalog startup instrumentation is unavailable")

-- ADDON_LOADED Store.Init, Main Init's Store.Init, then the Community, Sync,
-- and DPS subsystem initializers all bind the same database and immutable
-- release bundle during one login.
Nexus.Store.Init()
Nexus.Store.Init()
Nexus.CommunityBuilds.Init({}, {})
Nexus.Sync.Init(Nexus.Codec, {})
Nexus.DpsCapture.Init({}, Nexus.Sync)

local login = Catalog.DebugStats()
assert(login.initCalls == 5 and login.rebinds == 1
    and login.fastPathHits == 4 and login.revisionSnapshots == 0,
    string.format("login rebuilt/copied catalog: calls=%s rebinds=%s fast=%s snapshots=%s",
        tostring(login.initCalls), tostring(login.rebinds),
        tostring(login.fastPathHits), tostring(login.revisionSnapshots)))
assert(Catalog.Count() == Nexus.BundledBuilds.generation.included,
    "startup fast path changed the merged bundled catalog")

-- Every later PLAYER_ENTERING_WORLD reinitializes Sync and DPS. Those calls
-- must stay allocation-free when the database/bundle bindings are unchanged.
Nexus.Sync.Init(Nexus.Codec, {})
Nexus.DpsCapture.Init({}, Nexus.Sync)
local zone = Catalog.DebugStats()
assert(zone.initCalls == 7 and zone.rebinds == 1
    and zone.fastPathHits == 6 and zone.revisionSnapshots == 0,
    "zone transition recopied the unchanged bundled catalog")

-- Author membership may scan visible build identities once per library
-- generation, but repeated tooltips must remain O(1) and never copy Echoes.
local knownAuthor
for _, build in pairs(Nexus.BundledBuilds.builds) do
    if type(build.author) == "string" and build.author ~= "" then
        knownAuthor = build.author
        break
    end
end
assert(knownAuthor, "bundled startup fixture has no author")
local beforeAuthor = Catalog.DebugStats().authorIndexRebuilds
assert(Catalog.IsAuthor(knownAuthor)
    and Catalog.IsAuthor(knownAuthor .. "-SomeRealm")
    and not Catalog.IsAuthor("DefinitelyNotABundledAuthor"),
    "bounded author lookup returned the wrong membership")
for _ = 1, 100 do assert(Catalog.IsAuthor(knownAuthor)) end
assert(Catalog.DebugStats().authorIndexRebuilds == beforeAuthor + 1,
    "repeated author lookups rebuilt the catalog author index")

-- The first automatic Sync pass warms both compatibility hashes. Hashing may
-- walk lightweight identities, but must not copy all shipped Echo arrays.
local realAll = Catalog.All
Catalog.All = function()
    error("full catalog copy reached startup hash/projection path")
end

-- HUD progress performs exact-build matching. It may scan the lightweight
-- identity summaries once per library revision, but repeated renders must not
-- materialize the full 36k-Echo catalog.
local matchingId, matchingBuild
for id, build in pairs(Nexus.BundledBuilds.builds) do
    matchingId, matchingBuild = id, build
    break
end
assert(matchingId and matchingBuild, "bundled matching fixture is empty")
local summariesBefore = Catalog.DebugStats().summarySnapshots
for _ = 1, 100 do
    assert(Nexus.DpsCapture.FindMatchingBuildPublic({echoes=matchingBuild.echoes})
        == matchingId, "indexed exact-build lookup returned the wrong build")
end
local matchStats = Nexus.DpsCapture.BuildMatchLookupStats()
assert(Catalog.DebugStats().summarySnapshots == summariesBefore + 1
    and matchStats.rebuilds == 1 and matchStats.lookups == 100
    and matchStats.hydratedMissing == 0,
    "repeated exact-build lookup rebuilt or hydrated the full catalog")
local buildHash, dpsHash = Nexus.Sync.GetCompatibilityHashes()
assert(type(buildHash) == "string" and buildHash ~= ""
    and type(dpsHash) == "string",
    "startup compatibility hashes did not build from lightweight summaries")

-- Community filtering/sorting likewise publishes defensive summaries. Exact
-- Echo arrays are loaded later only for the bounded visible card window.
Nexus.ViewProjections.Reset()
local rows, projection = Nexus.ViewProjections.Builds({sortMode="recent"})
assert(type(rows) == "table" and #rows > 0
    and projection.total == Nexus.BundledBuilds.generation.included
    and rows[1].echoes == nil and rows[1].loadoutAvailable == true,
    "Community projection materialized full bundled Echo arrays")
local originalTitle = rows[1].title
rows[1].title = "caller mutation"
assert(Nexus.ViewProjections.Builds({sortMode="recent"})[1].title == originalTitle,
    "lightweight projection stopped defending its cache from callers")

-- A represented library change invalidates the index once. A user-authored
-- exact duplicate is preferred over an automatic DPS record page, matching the
-- historical scan's selection rule.
local replacementId = "000-indexed-authored-match"
local replacement = {
    id=replacementId, title="Indexed authored match", author="Tester",
    class=matchingBuild.class, echoes=matchingBuild.echoes,
    fingerprint=matchingBuild.fingerprint,
    fingerprintHash=matchingBuild.fingerprintHash,
    postedAt=9999999999, lastModified=9999999999,
}
assert(Catalog.Put(replacement))
assert(Nexus.DpsCapture.FindMatchingBuildPublic({echoes=matchingBuild.echoes})
    == replacementId, "library revision did not refresh authored match preference")
assert(Nexus.DpsCapture.BuildMatchLookupStats().rebuilds == 2,
    "library revision did not rebuild the exact-build index once")
assert(Catalog.RemoveOverlay(replacementId), "matching test overlay cleanup failed")
Catalog.All = realAll

print("real bundled startup, hashes, projections, and author lookup stay allocation-bounded -- OK")
