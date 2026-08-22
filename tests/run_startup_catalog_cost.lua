-- Reproduces the beta's real login/zone initialization sequence with the
-- shipped bundled catalog. Focused suites normally use an empty bundle, which
-- cannot expose full-library defensive-copy pressure.
local H = dofile("tests/harness.lua")
dofile("data/BundledBuilds.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
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
local mageBuilds, fingerprintCounts = {}, {}
for _, build in pairs(Nexus.BuildCatalog.Summaries()) do
    if build.class == "MAGE" and type(build.fingerprint) == "string" then
        mageBuilds[#mageBuilds + 1] = build
        fingerprintCounts[build.fingerprint] =
            (fingerprintCounts[build.fingerprint] or 0) + 1
    end
end
table.sort(mageBuilds, function(left, right)
    return tostring(left.id) < tostring(right.id)
end)
local eligibleBuild
for _, build in ipairs(mageBuilds) do
    if build.loadoutAvailable == true
        and fingerprintCounts[build.fingerprint] == 1 then
        eligibleBuild = build
        break
    end
end
assert(eligibleBuild,
    "bundled startup fixture has no complete, unique Mage identity")
NexusDB.dpsCapture.characterBest = {
    dummy={startupdummy={
        player="StartupDummy",dps=100000,duration=60,ts=1,class="MAGE",
        buildId=eligibleBuild.id,fingerprint=eligibleBuild.fingerprint,
    }},
    lk={startuplk={
        player="StartupLk",dps=200000,duration=60,ts=1,class="MAGE",
        buildId=eligibleBuild.id,fingerprint=eligibleBuild.fingerprint,
    }},
}
NexusDB.dpsCapture.personalBest = {}
NexusDB.dpsCapture.buildBest = {}
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
local buildHash, dpsHash = Nexus.Sync.GetCompatibilityHashes()
assert(type(buildHash) == "string" and buildHash ~= ""
    and type(dpsHash) == "string",
    "startup compatibility hashes did not build from lightweight summaries")

-- Community filtering/sorting likewise publishes defensive summaries. Exact
-- Echo arrays are loaded later only for the bounded visible card window.
Nexus.ViewProjections.Reset()
local rows, projection = Nexus.ViewProjections.Builds({sortMode="recent"})
assert(type(rows) == "table" and #rows > 0
    and #rows == 1
    and projection.total == Nexus.BundledBuilds.generation.included
    and rows[1].echoes == nil and rows[1].loadoutAvailable == true,
    "Community projection materialized full bundled Echo arrays")
local originalTitle = rows[1].title
rows[1].title = "caller mutation"
assert(Nexus.ViewProjections.Builds({sortMode="recent"})[1].title == originalTitle,
    "lightweight projection stopped defending its cache from callers")
Catalog.All = realAll

print("real bundled startup, hashes, projections, and author lookup stay allocation-bounded -- OK")
