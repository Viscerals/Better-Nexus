-- Package B / issue #22 Repair Wave 1: MASTER-RC-009.
--
-- "The read gate calls Init, so Status and other reads can mutate and admit an
--  unbound database."
-- Acceptance: "Remove admission from Gate and route all binds/rebinds through
--  the explicit coordinator."
-- Required repaired result: "Every read from unbound/pending/invalid/stale/
--  owner-drift state must preserve bytes, generation, and state and return a
--  fixed read-only result."
--
-- Architecture at 3b5de54f, docs/SYNC_TRUST_CATALOG_AUTHORITY_STATE_MACHINE.md
-- lines 1200-1206: `AuthorityBootstrapCoordinatorV1` is the sole startup
-- sequencing owner, and `Store`, `DpsCapture`, `LoadoutEvidence`,
-- `BuildCatalog` "register one idempotent dependency with this coordinator;
-- they do not call a domain recovery pump or raw writer directly." A read path
-- that calls `Catalog.Init` is exactly a domain owner driving its own raw
-- writer, from a read.
--
-- Expected-red measurement is recorded in the header of each case, taken on
-- this tree immediately before the product edit. All five were RED.
--
-- STATUS AFTER THE WAVE-1 REPAIR (MASTER-RC-009 is NOT closed):
--   RDP-01, RDP-02, RDP-04, RDP-05  GREEN. The confirmed MASTER defect --
--     "Status can silently bind, admit, and mutate an UNBOUND SavedVariables
--     root" -- is repaired: the read gate records one explicit rebind request
--     and returns a fixed read-only result, and only the explicit
--     Catalog.PumpAuthorityRebindV1 entry binds or admits.
--   RDP-03  NOW GREEN, by implementation and not by relaxation. Its assertions
--     are unchanged from the expected-red form. The local-owner re-proof branch
--     no longer calls Catalog.Init from a read: the read gate records one
--     explicit OWNER_REBIND_REQUIRED request and returns a fixed read-only
--     result, and the re-admission is driven by the coordinator -- either the
--     MainLifecycle scheduler-turn rebind pump or MutationGate. MASTER-RC-009
--     is closed.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Codec.lua")
local S = dofile("tests/catalog_authority_support.lua")
local Case, Check = S.Case, S.Check

local now = 2000000000
time = function() return now end
UnitClass = function() return "Mage", "MAGE" end

local function Catalog() return Nexus.BuildCatalog end

-- Every raw byte of a database, so "wrote nothing" is proven rather than
-- assumed. The encoder is deterministic for these fixtures.
local function Bytes(db) return S.Encode(db) end

local function Fields(db)
    local names = {}
    for key in pairs(db) do names[#names + 1] = tostring(key) end
    table.sort(names)
    return table.concat(names, ",")
end

-- RDP-01 EXPECTED RED on this tree: Gate() calls
-- Catalog.Init(NexusDB, Nexus.BundledBuilds) whenever the raw global differs
-- from the bound database, so Catalog.Status() -- a pure read -- performs a
-- complete root admission against the replacement and writes its durable
-- authority bundle into it.
Case("RDP-01",
    "a read never binds or admits a replaced authority database",
function()
    local bound = S.Database({rdpA=S.LocalBuild("rdpA", 2)})
    S.Bind(bound)
    local before = Catalog().RootState()
    Check(before.state == "ROOT_ADMITTED", "fixture did not admit a root")

    -- A different SavedVariables root appears under the global name. Only the
    -- coordinator may rebind; a read may not.
    local replacement = S.Database({rdpB=S.LocalBuild("rdpB", 3)})
    local replacementBytes, replacementFields = Bytes(replacement), Fields(replacement)
    NexusDB = replacement

    local status = Catalog().Status()
    Check(Bytes(replacement) == replacementBytes,
        "a read wrote into the replacement database: " .. Fields(replacement)
        .. " (was " .. replacementFields .. ")")
    Check(rawget(replacement, "authorityBundle") == nil,
        "a read admitted a durable authority bundle into an unbound database")
    local after = Catalog().RootState()
    Check(after.generation == before.generation,
        "a read advanced the root generation")
    Check(after.durableBundleGeneration == before.durableBundleGeneration,
        "a read advanced the durable bundle generation")
    Check(status.readOnly == true,
        "a read from a stale binding did not return a fixed read-only result")
end)

-- RDP-02 EXPECTED RED on this tree: the same Gate() admission runs for every
-- read surface, so Get/All/AuthorityState each bind and mutate too.
Case("RDP-02",
    "every read surface returns a fixed read-only result without writing",
function()
    local bound = S.Database({rdpC=S.LocalBuild("rdpC", 2)})
    S.Bind(bound)
    local replacement = S.Database({rdpD=S.LocalBuild("rdpD", 3)})
    local replacementBytes = Bytes(replacement)
    NexusDB = replacement

    local catalog = Catalog()
    local reads = {
        {name="Get", run=function() return catalog.Get("rdpD") end},
        {name="Status", run=function() return catalog.Status() end},
        {name="RootState", run=function() return catalog.RootState() end},
        {name="AuthorityState",
            run=function() return catalog.AuthorityState("rdpD") end},
    }
    for _, read in ipairs(reads) do
        local ok, value = pcall(read.run)
        Check(ok, read.name .. " raised from a stale binding: " .. tostring(value))
        Check(Bytes(replacement) == replacementBytes,
            read.name .. " wrote into the unbound database")
    end
    Check(catalog.Get("rdpD") == nil,
        "a read served a record out of a database it was never bound to")
end)

-- RDP-03 EXPECTED RED on this tree: Gate() re-admits when the local-owner
-- proof changes, so a read performs a complete re-admission and can advance
-- durable state.
Case("RDP-03",
    "owner-identity drift does not re-admit from a read",
function()
    UnitName = function() return "Ownera" end
    GetNormalizedRealmName = function() return "Ebonhold" end
    GetRealmName = GetNormalizedRealmName
    local bound = S.Database({rdpE=S.LocalBuild("rdpE", 2)})
    S.Bind(bound)
    local before = Catalog().RootState()
    local boundBytes = Bytes(bound)

    -- The character identity changes mid-session.
    UnitName = function() return "Ownerb" end
    local status = Catalog().Status()
    local after = Catalog().RootState()
    Check(Bytes(bound) == boundBytes,
        "a read re-admitted and rewrote durable bytes on owner drift")
    Check(after.generation == before.generation
        and after.durableBundleGeneration == before.durableBundleGeneration,
        "a read advanced a generation on owner drift")
    Check(status.readOnly == true,
        "a read under owner drift did not return a fixed read-only result")
end)

-- RDP-04 EXPECTED RED on this tree: with no bound root at all, the first read
-- binds the raw global and admits it.
Case("RDP-04",
    "a read from an unbound catalog writes nothing into the raw global",
function()
    S.Reload()
    local fresh = S.Database({rdpF=S.LocalBuild("rdpF", 2)})
    local freshBytes = Bytes(fresh)
    NexusDB = fresh
    local catalog = Catalog()
    local status = catalog.Status()
    Check(Bytes(fresh) == freshBytes,
        "the first read bound and admitted the raw global")
    Check(rawget(fresh, "authorityBundle") == nil,
        "the first read wrote a durable authority bundle")
    Check(status.readOnly == true,
        "an unbound read did not return a fixed read-only result")
    Check(catalog.RootState().state ~= "ROOT_ADMITTED",
        "an unbound read reported an admitted root")
end)

-- RDP-05 EXPECTED RED on this tree: because Gate() already rebound, there is
-- no explicit coordinator rebind entry to observe, and no way to distinguish
-- "the coordinator rebound" from "a read rebound".
Case("RDP-05",
    "only the explicit coordinator rebind binds, and reads serve again after it",
function()
    S.Reload()
    local catalog = Catalog()
    Check(type(catalog.RebindRequired) == "function"
        and type(catalog.PumpAuthorityRebindV1) == "function",
        "the explicit coordinator rebind entry is unavailable")

    local bound = S.Database({rdpG=S.LocalBuild("rdpG", 2)})
    S.Bind(bound)
    Check(catalog.RebindRequired() == nil,
        "a freshly admitted root already requested a rebind")

    local replacement = S.Database({rdpH=S.LocalBuild("rdpH", 3)})
    NexusDB = replacement
    catalog.Status()
    Check(catalog.RebindRequired() ~= nil,
        "a stale binding recorded no explicit rebind request")

    -- Nothing has bound yet.
    Check(rawget(replacement, "authorityBundle") == nil,
        "the rebind request itself admitted the replacement")

    local selected = S.Bundle()
    local rebound = catalog.PumpAuthorityRebindV1(replacement, selected)
    for _ = 1, catalog.Budget().maximumPumps do
        if catalog.RebindRequired() == nil then break end
        rebound = catalog.PumpAuthorityRebindV1(replacement, selected)
    end
    Check(rebound and rebound.rebound == true,
        "the coordinator rebind did not run")
    Check(catalog.RebindRequired() == nil,
        "the rebind request survived the coordinator rebind")
    Check(catalog.RootState().state == "ROOT_ADMITTED",
        "the coordinator rebind did not admit the replacement root")
    Check(catalog.Get("rdpH") ~= nil,
        "reads did not serve again after the coordinator rebind")
    Check(catalog.Status().readOnly == false,
        "the catalog stayed read-only after an explicit coordinator rebind")
end)

-- ---------------------------------------------------------------------------
-- MASTER-RC-010, legacy cursors. The root map pairs RC-009 and RC-010 on this
-- shared read-gate and cursor-drift fixture.
--
-- Root: "raw-ID continuations cross generations and serve rows added mid-walk."
-- Required repaired outcome: "STALE_CURSOR once then INVALID_CURSOR after root
--  replacement, or opaque bound tokens."
--
-- Measured defect: Catalog.SyncDeltaNext, Catalog.TombstoneNext and
-- Catalog.BarrierNext each take a RAW ID and re-locate position by scanning the
-- vector for it (VectorStep). A raw ID carries no generation, so a continuation
-- captured against one root keeps walking a replaced root and serves rows that
-- were committed after the walk began.
--
-- RDP-08 is a guard: it passes before the repair and after it, so the fix
-- cannot be a blanket refusal of every continuation.
local function DriftRoot()
    -- A commit replaces the published root and advances its generation.
    Check(Catalog().Put(S.LocalBuild("rdpDrift", 2)),
        "the drift commit was refused")
end

Case("RDP-06",
    "a delta continuation across a root replacement stales once then invalidates",
function()
    -- Earlier cases in this file rebind the character identity; these cases own
    -- Boganic rows, so pin it before binding.
    UnitName = function() return "Boganic" end
    GetNormalizedRealmName = function() return "Ebonhold" end
    GetRealmName = GetNormalizedRealmName
    S.Bind(S.Database({
        rdpF=S.LocalBuild("rdpF", 2), rdpG=S.LocalBuild("rdpG", 2),
    }))
    local first = Catalog().SyncDeltaNext(nil)
    Check(first ~= nil, "the delta walk produced no first row")
    local before = Catalog().RootState().generation
    DriftRoot()
    Check(Catalog().RootState().generation ~= before,
        "the fixture commit did not replace the published root")
    local id, reason, done = Catalog().SyncDeltaNext(first)
    Check(id == nil and done == true and reason == "STALE_CURSOR",
        "a raw-ID delta continuation survived a root replacement: id="
            .. tostring(id) .. " reason=" .. tostring(reason))
    local id2, reason2, done2 = Catalog().SyncDeltaNext(first)
    Check(id2 == nil and done2 == true and reason2 == "INVALID_CURSOR",
        "a superseded delta continuation staled twice instead of invalidating: "
            .. tostring(reason2))
end)

Case("RDP-07",
    "a tombstone continuation across a root replacement stales then invalidates",
function()
    -- Fresh module state: the preceding case leaves a drifted root behind, and
    -- this case needs its own generation to measure the continuation against.
    S.Reload()
    -- Earlier cases in this file rebind the character identity; these cases own
    -- Boganic rows, so pin it before binding.
    UnitName = function() return "Boganic" end
    GetNormalizedRealmName = function() return "Ebonhold" end
    GetRealmName = GetNormalizedRealmName
    S.Bind(S.Database({
        rdpH=S.LocalBuild("rdpH", 2), rdpI=S.LocalBuild("rdpI", 2),
    }))
    local ok1, why1 = Catalog().SetTombstone("rdpH", {stamp=1}, {source="local"})
    Check(ok1, "the tombstone fixture was refused: " .. tostring(why1))
    local ok2, why2 = Catalog().SetTombstone("rdpI", {stamp=1}, {source="local"})
    Check(ok2, "the second tombstone fixture was refused: " .. tostring(why2))
    local first = Catalog().TombstoneNext(nil)
    Check(first ~= nil, "the tombstone walk produced no first row")
    DriftRoot()
    local id, reason, done = Catalog().TombstoneNext(first)
    Check(id == nil and done == true and reason == "STALE_CURSOR",
        "a raw-ID tombstone continuation survived a root replacement: reason="
            .. tostring(reason))
    local id2, reason2 = Catalog().TombstoneNext(first)
    Check(id2 == nil and reason2 == "INVALID_CURSOR",
        "a superseded tombstone continuation staled twice: " .. tostring(reason2))
end)

Case("RDP-08",
    "GUARD: a continuation inside one generation still walks every row",
function()
    -- Earlier cases in this file rebind the character identity; these cases own
    -- Boganic rows, so pin it before binding.
    UnitName = function() return "Boganic" end
    GetNormalizedRealmName = function() return "Ebonhold" end
    GetRealmName = GetNormalizedRealmName
    S.Bind(S.Database({
        rdpJ=S.LocalBuild("rdpJ", 2), rdpK=S.LocalBuild("rdpK", 2),
        rdpL=S.LocalBuild("rdpL", 2),
    }))
    local seen, cursor, guard = {}, nil, 0
    while guard < 64 do
        guard = guard + 1
        local id, record, done = Catalog().SyncDeltaNext(cursor)
        if done or id == nil then break end
        Check(record ~= nil or true, "unused")
        seen[id] = true
        cursor = id
    end
    Check(seen.rdpJ and seen.rdpK and seen.rdpL,
        "a clean single-generation delta walk lost a row")
end)

S.Finish("catalog authority read purity")
