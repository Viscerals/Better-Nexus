-- Reproduces the beta's real login/zone initialization sequence with the
-- shipped bundled catalog. Focused suites normally use an empty bundle, which
-- cannot expose full-library defensive-copy pressure.
local H = dofile("tests/harness.lua")
local S = dofile("tests/catalog_authority_support.lua")
dofile("data/BundledBuilds.lua")
dofile("data/DefaultProfile.lua")
-- The shipped login sequence loads the compatibility hash owner between the
-- catalog and Store (Nexus.toc order). MASTER-W2-006 refuses any one-call
-- collection read on the shipped maximum root, so the compatibility view is
-- served only through this cache owner's retained cursor work.
dofile("core/BuildHashCache.lua")
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
H.BootstrapStore()
-- MASTER-W2-002: the first login writes the retention bookkeeping metadata
-- through one detached catalog transaction instead of a raw legacy write. The
-- coordinator releases dependents at STORE_READY while that transaction is
-- still a pending catalog candidate, exactly as MainLifecycle then pumps it
-- one slice per frame. Settle it here through the same public scheduler seam,
-- retain its exact ticket, and account for its slices explicitly below. It is
-- the only root work at login that Init does not drive.
local startupRetention = Nexus.DataRetention.Enforce(NexusDB, "startup")
assert(type(startupRetention) == "table" and startupRetention.pending == true
    and type(startupRetention.mutationTicket) == "table",
    "the first-login retention transaction was not a retained pending ticket")
local startupTicket = startupRetention.mutationTicket
local _, startupTransactionPumps = S.PumpCatalogToIdle(
    "first-login retention transaction")
assert(startupTicket.state == "committed" and startupTicket.committed == true
    and startupTicket.pumps == startupTransactionPumps + 1,
    string.format("first-login retention transaction did not commit exactly: state=%s committed=%s pumps=%s settled=%s",
        tostring(startupTicket.state), tostring(startupTicket.committed),
        tostring(startupTicket.pumps), tostring(startupTransactionPumps)))
local settledRetention = Nexus.DataRetention.Enforce(NexusDB, "startup")
assert(type(settledRetention) == "table" and settledRetention.pending == false
    and not settledRetention.blocked,
    "settled first-login retention transaction did not publish its terminal summary")
H.BootstrapStore()
Nexus.CommunityBuilds.Init({}, {})
-- MASTER-RC-001 (architecture 1207-1211): Sync.Init and DpsCapture.Init no
-- longer admit the catalog root as a side effect. The same admission is
-- performed explicitly here, before the call, because the removed side
-- effect ran inside Init ahead of Init's own dependent steps.
H.AdmitCatalogV1(NexusDB)
Nexus.Sync.Init(Nexus.Codec, {})
-- Complete collections are read through the generation-bound summary cursor.
local function Summaries()
    local out = {}
    local token = assert(Nexus.BuildCatalog.BeginSummaryCursor())
    for _ = 1, 4096 do
        local summary, done, err = Nexus.BuildCatalog.SummaryCursorNext(token)
        assert(err == nil, tostring(err))
        if summary then out[summary.id] = summary end
        if done then break end
    end
    return out
end
-- Shipped bundled rows above the issue #22 envelope (79 ordinary, 6 locked,
-- 85 total copies) are quarantined deny-only; only rows inside it count.
local function AdmissibleBundledCount()
    local limits = Nexus.LoadoutEvidence.SemanticLimits()
    local count = 0
    for _, build in pairs(Nexus.BundledBuilds.builds) do
        local verdict = Nexus.LoadoutEvidence.SemanticEnvelope(build.echoes)
        if verdict.valid and verdict.ordinary <= limits.ordinary then
            count = count + 1
        end
    end
    return count
end
local mageBuilds, fingerprintCounts = {}, {}
for _, build in pairs(Summaries()) do
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
        player="Startup",ownerKey="startup@ebonhold",ownerVerified=true,
        realm="ebonhold",lockedEchoes={},dps=100000,duration=60,ts=1,class="MAGE",
        buildId=eligibleBuild.id,fingerprint=eligibleBuild.fingerprint,
        echoes=eligibleBuild.echoes,
    }},
    lk={startuplk={
        player="Startup",ownerKey="startup@ebonhold",ownerVerified=true,
        realm="ebonhold",lockedEchoes={},dps=200000,duration=60,ts=1,class="MAGE",
        buildId=eligibleBuild.id,fingerprint=eligibleBuild.fingerprint,
        echoes=eligibleBuild.echoes,
    }},
}
NexusDB.dpsCapture.personalBest = {}
NexusDB.dpsCapture.buildBest = {}
H.AdmitCatalogV1(NexusDB)
Nexus.DpsCapture.Init({}, Nexus.Sync)

local login = Catalog.DebugStats()
local maximumPumps = Catalog.Budget().maximumPumps
-- Every root pump at login is either one Init-driven admission slice or one
-- slice of the exact first-login retention transaction settled above. Nothing
-- else may rebuild or copy the catalog.
assert(login.rootAdmissions == 1 and login.rebinds == 1
    and login.rootPumps > 0 and login.rootPumps <= maximumPumps
    and login.fastPathHits == 4
    and login.rootPumps == (login.initCalls - login.fastPathHits)
        + startupTicket.pumps
    and login.revisionSnapshots == 0,
    string.format("login rebuilt/copied catalog: calls=%s pumps=%s retention=%s rebinds=%s fast=%s snapshots=%s",
        tostring(login.initCalls), tostring(login.rootPumps),
        tostring(startupTicket.pumps), tostring(login.rebinds),
        tostring(login.fastPathHits), tostring(login.revisionSnapshots)))
assert(Catalog.Count() == AdmissibleBundledCount()
    and Catalog.Status().bundledCount == Nexus.BundledBuilds.generation.included,
    "startup fast path changed the merged bundled catalog")

-- Every later PLAYER_ENTERING_WORLD reinitializes Sync and DPS. Those calls
-- must stay allocation-free when the database/bundle bindings are unchanged.
H.AdmitCatalogV1(NexusDB)
Nexus.Sync.Init(Nexus.Codec, {})
H.AdmitCatalogV1(NexusDB)
Nexus.DpsCapture.Init({}, Nexus.Sync)
local zone = Catalog.DebugStats()
assert(zone.initCalls == login.initCalls + 2
    and zone.rootAdmissions == login.rootAdmissions
    and zone.rootPumps == login.rootPumps and zone.rebinds == 1
    and zone.fastPathHits == login.fastPathHits + 2
    and zone.revisionSnapshots == 0,
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
-- The author index is part of the published root; lookups never rebuild it.
assert(Catalog.DebugStats().authorIndexRebuilds == beforeAuthor,
    "repeated author lookups rebuilt the catalog author index")

-- The first automatic Sync pass warms both compatibility hashes. Hashing may
-- walk lightweight identities, but must not copy all shipped Echo arrays.
local realAll = Catalog.All
Catalog.All = function()
    error("full catalog copy reached startup hash/projection path")
end
-- MASTER-W2-006: the compatibility view warms one BuildHashCache slice per
-- scheduler turn; the fixture stands in for that lifecycle turn without
-- draining more than one slice per call.
local buildHash, dpsHash = S.CompatibilityHashes(Nexus.Sync)
assert(type(buildHash) == "string" and buildHash ~= ""
    and type(dpsHash) == "string",
    "startup compatibility hashes did not build from lightweight summaries")

-- Community filtering/sorting likewise publishes defensive summaries. Exact
-- Echo arrays are loaded later only for the bounded visible card window.
Nexus.ViewProjections.Reset()
local filters = {sortMode="recent",classFilter="MAGE",qualifiedOnly=false}
local rows, projection = Nexus.ViewProjections.RequestBuilds(filters)
for _ = 1, 20000 do
    if type(rows) == "table" then break end
    local _, pumpError = Nexus.ViewProjections.PumpBuilds()
    assert(pumpError == nil, "bounded Community startup pump failed")
    rows, projection = Nexus.ViewProjections.RequestBuilds(filters)
end
assert(type(rows) == "table" and #rows > 0
    and #rows > 0 and #rows <= 20
    and projection.total == AdmissibleBundledCount()
    and rows[1].echoes == nil and rows[1].loadoutAvailable == true,
    string.format("Community projection materialized full bundled Echo arrays: rows=%s total=%s echoes=%s available=%s",
        tostring(type(rows)=="table" and #rows or nil),
        tostring(projection and projection.total),
        tostring(type(rows)=="table" and rows[1] and rows[1].echoes),
        tostring(type(rows)=="table" and rows[1] and rows[1].loadoutAvailable)))
local defensiveRows = Nexus.ViewProjections.Builds(filters)
local originalTitle = defensiveRows[1].title
defensiveRows[1].title = "caller mutation"
assert(Nexus.ViewProjections.Builds(filters)[1].title == originalTitle,
    "lightweight projection stopped defending its cache from callers")
Catalog.All = realAll

print("real bundled startup, hashes, projections, and author lookup stay allocation-bounded -- OK")
