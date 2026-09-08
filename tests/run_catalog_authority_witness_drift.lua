-- Package B / issue #22 Repair Wave 1: MASTER-RC-017, serving witness.
--
-- Root: "tokens watch map identities only, not selected-row identity or
--  content."
-- Required repaired outcome: "bounded per-key witnesses bound and rechecked on
--  every authority-bearing operation."
--
-- Architecture at 3b5de54f, docs/SYNC_TRUST_CATALOG_AUTHORITY_STATE_MACHINE.md:
--   line 454  "Every successful admission also stores a detached, bounded exact
--             SourceWitness for the complete selected raw source, including
--             known and unknown keys, values, aliases, table topology, and
--             provenance. The witness is not a hash and no digest collision can
--             grant authority."
--   line 137  "Current-source drift changes a database, backing table,
--             committed revision, per-key witness, callback, or
--             EvidenceCoordinator identity behind the public root; it cancels
--             work and publishes ROOT_INVALIDATED."
--   line 140  "A missing/replaced witness already bound by the public root is
--             current-source drift and invalidates that root."
--
-- The defect: CaptureToken binds communityBuilds/syncTombstones/buildCatalog/
-- communityRetentionEvictions as WHOLE-TABLE identities and TokenDrifted
-- compares the same. A raw write that replaces, adds, or removes one row while
-- leaving the map table identity untouched is therefore invisible, and the
-- published root keeps serving as if its source were still proven.
--
-- WIT-04 and WIT-05 are guards: they pass before the repair and must keep
-- passing after it, so the fix cannot be a blanket "always drift".
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Codec.lua")
local S = dofile("tests/catalog_authority_support.lua")
local Case, Check = S.Case, S.Check

local now = 2000000000
time = function() return now end
UnitClass = function() return "Mage", "MAGE" end
UnitName = function() return "Witness" end
GetNormalizedRealmName = function() return "Ebonhold" end
GetRealmName = GetNormalizedRealmName

local function Catalog() return Nexus.BuildCatalog end

-- Bind a fresh admitted root and return its durable payload map.
local function AdmitWith(rows)
    local bound = S.Database(rows)
    S.Bind(bound)
    local root = Catalog().RootState()
    Check(root.state == "ROOT_ADMITTED", "fixture did not admit a root")
    local payload = S.Durable(bound, "communityBuilds")
    Check(next(payload) ~= nil, "fixture payload was empty")
    return bound, payload
end

-- WIT-01 EXPECTED RED: one row replaced in place.
Case("WIT-01",
    "a replaced row inside an unchanged payload map is current-source drift",
function()
    local bound, payload = AdmitWith({witA=S.LocalBuild("witA", 2)})
    local mapIdentity = payload
    local original = payload.witA
    Check(original ~= nil, "fixture row missing from the durable payload")
    -- Same map table, different row table. A whole-map identity witness is
    -- blind to this; a per-key witness is not.
    payload.witA = S.DeepCopy(original)
    Check(rawequal(S.Durable(bound, "communityBuilds"), mapIdentity),
        "fixture replaced the map instead of one row")
    Check(not rawequal(payload.witA, original),
        "fixture did not actually replace the row identity")
    local after = Catalog().RootState()
    Check(after.state == "ROOT_INVALIDATED",
        "a replaced row behind the published root did not invalidate it: "
            .. tostring(after.state))
end)

-- WIT-02 EXPECTED RED: a row appended in place.
Case("WIT-02",
    "a row added to an unchanged payload map is current-source drift",
function()
    local bound, payload = AdmitWith({witB=S.LocalBuild("witB", 2)})
    local mapIdentity = payload
    payload.witBintruder = S.LocalBuild("witBintruder", 3)
    Check(rawequal(S.Durable(bound, "communityBuilds"), mapIdentity),
        "fixture replaced the map instead of adding one row")
    local after = Catalog().RootState()
    Check(after.state == "ROOT_INVALIDATED",
        "an added row behind the published root did not invalidate it: "
            .. tostring(after.state))
end)

-- WIT-03 EXPECTED RED: a row removed in place.
Case("WIT-03",
    "a row removed from an unchanged payload map is current-source drift",
function()
    local bound, payload = AdmitWith({
        witC=S.LocalBuild("witC", 2), witCextra=S.LocalBuild("witCextra", 3),
    })
    local mapIdentity = payload
    local removedKey
    for key in pairs(payload) do removedKey = key break end
    Check(removedKey ~= nil, "fixture payload had no key to remove")
    payload[removedKey] = nil
    Check(rawequal(S.Durable(bound, "communityBuilds"), mapIdentity),
        "fixture replaced the map instead of removing one row")
    local after = Catalog().RootState()
    Check(after.state == "ROOT_INVALIDATED",
        "a removed row behind the published root did not invalidate it: "
            .. tostring(after.state))
end)

-- WIT-04 GUARD: whole-map replacement must still be drift after the repair.
Case("WIT-04",
    "GUARD: replacing the whole payload map is still current-source drift",
function()
    local bound = S.Database({witD=S.LocalBuild("witD", 2)})
    S.Bind(bound)
    Check(Catalog().RootState().state == "ROOT_ADMITTED",
        "fixture did not admit a root")
    S.DriftSelectedMap(bound, "communityBuilds")
    Check(Catalog().RootState().state == "ROOT_INVALIDATED",
        "a replaced payload map did not invalidate the published root")
end)

-- WIT-05 GUARD: no false positives. An untouched source must stay admitted
-- across repeated authority-bearing reads, so the repair cannot be a blanket
-- "always drift".
Case("WIT-05",
    "GUARD: an untouched source never reports drift",
function()
    local bound = S.Database({
        witE=S.LocalBuild("witE", 2), witEtwo=S.LocalBuild("witEtwo", 3),
    })
    S.Bind(bound)
    for pass = 1, 5 do
        local root = Catalog().RootState()
        Check(root.state == "ROOT_ADMITTED",
            "an untouched source reported drift on pass " .. pass .. ": "
                .. tostring(root.state))
        Catalog().Status()
        Catalog().Count()
        Catalog().Get("witE")
    end
    local final = Catalog().RootState()
    Check(final.state == "ROOT_ADMITTED",
        "repeated authority-bearing reads invalidated an untouched source")
end)

-- ---------------------------------------------------------------------------
-- MASTER-RC-017 REOPENED ELEMENT: the bundled baseline is an unwitnessed
-- backing table.
--
-- Architecture lines 135-141: "Current-source drift changes a database,
-- backing table, committed revision, per-key witness, callback, or
-- EvidenceCoordinator identity behind the public root; it cancels work and
-- publishes ROOT_INVALIDATED", and "A missing/replaced witness already bound
-- by the public root is current-source drift and invalidates that root."
--
-- The defect. CaptureToken stores `baselineIdentity = ST.baseline`
-- (core/BuildCatalog.lua:1999) and TokenDrifted compares that value back to the
-- SAME cached ST.baseline (:2034). ST.baseline is written only inside
-- BeginRootAdmission (:2669). Witness.Capture is applied to exactly four maps
-- (:1994-1997) -- communityBuilds, syncTombstones, buildCatalog and
-- communityRetentionEvictions -- and NOT to the bundled baseline. So the
-- bundled `builds` map, which the root is admitted FROM, has neither a
-- re-read nor a per-key witness: replacing or mutating it behind the published
-- root is invisible.
--
-- WIT-01..03 fixed exactly this whole-map blindness for communityBuilds. The
-- bundled baseline is the same defect on a source those cases never touched,
-- which is why MASTER-RC-017 was closed with it still live.
--
-- WIT-08 is a guard: it passes before the repair and after it, so the fix
-- cannot be a blanket "the baseline always drifts".

-- Bind a fresh admitted root against a bundle we retain a handle to.
local function AdmitWithBundle(rows, baseline)
    local bound = S.Database(rows)
    local bundle = S.Bundle(baseline)
    S.Bind(bound, bundle)
    local root = Catalog().RootState()
    Check(root.state == "ROOT_ADMITTED",
        "fixture did not admit a root: " .. tostring(root.state))
    return bound, bundle
end

-- WIT-06 EXPECTED RED: the nested builds map replaced under the same bundle.
Case("WIT-06",
    "a replaced bundled builds map under the same bundle is current-source drift",
function()
    local _, bundle = AdmitWithBundle(
        {witF=S.LocalBuild("witF", 2)},
        {bundledF=S.LocalBuild("bundledF", 2)})
    local bundleIdentity = bundle
    -- Same OUTER bundle table, different nested builds map. Identity-only
    -- comparison of the cached ST.baseline is blind to this.
    bundle.builds = {
        bundledF=S.LocalBuild("bundledF", 3),
        bundledIntruder=S.LocalBuild("bundledIntruder", 4),
    }
    Check(rawequal(bundle, bundleIdentity),
        "fixture replaced the outer bundle instead of its builds map")
    local after = Catalog().RootState()
    Check(after.state == "ROOT_INVALIDATED",
        "a replaced bundled builds map behind the published root did not "
            .. "invalidate it: " .. tostring(after.state))
end)

-- WIT-07 EXPECTED RED: one bundled row replaced inside an unchanged map.
Case("WIT-07",
    "a replaced row inside an unchanged bundled builds map is current-source drift",
function()
    local _, bundle = AdmitWithBundle(
        {witG=S.LocalBuild("witG", 2)},
        {bundledG=S.LocalBuild("bundledG", 2)})
    local baselineIdentity = bundle.builds
    local original = bundle.builds.bundledG
    Check(original ~= nil, "fixture row missing from the bundled baseline")
    -- Same builds map, different row table -- the per-key half, exactly the
    -- shape WIT-01 asserts for communityBuilds.
    bundle.builds.bundledG = S.DeepCopy(original)
    Check(rawequal(bundle.builds, baselineIdentity),
        "fixture replaced the builds map instead of one row")
    Check(not rawequal(bundle.builds.bundledG, original),
        "fixture did not actually replace the bundled row identity")
    local after = Catalog().RootState()
    Check(after.state == "ROOT_INVALIDATED",
        "a replaced bundled row behind the published root did not invalidate "
            .. "it: " .. tostring(after.state))
end)

-- WIT-08 GUARD: passes before the repair and after it.
Case("WIT-08",
    "GUARD: an untouched bundled baseline never reports drift",
function()
    AdmitWithBundle({witH=S.LocalBuild("witH", 2)},
        {bundledH=S.LocalBuild("bundledH", 2)})
    for pass = 1, 5 do
        local root = Catalog().RootState()
        Check(root.state == "ROOT_ADMITTED",
            "an untouched bundled baseline reported drift on pass " .. pass
                .. ": " .. tostring(root.state))
        Catalog().Status()
        Catalog().Count()
        Catalog().Get("witH")
    end
    local final = Catalog().RootState()
    Check(final.state == "ROOT_ADMITTED",
        "repeated authority-bearing reads invalidated an untouched bundled "
            .. "baseline")
end)

S.Finish("catalog authority serving witness drift")
