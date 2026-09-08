-- Package B / issue #22 Repair Wave 1: MASTER-RC-008, retention binding.
--
-- Root: "detached raw database reads and mutations decide admission."
-- Required repaired outcome: "exact ready-authority identity required; raw
--  fallbacks and raw database export removed."
--
-- Architecture at 3b5de54f, docs/SYNC_TRUST_CATALOG_AUTHORITY_STATE_MACHINE.md
-- RAW-01 (line 4849) is RED when "a detached instance falls back to global
-- NexusDB", and requires the "exact Store 9, Retention 8, and Compaction 8 API
-- inventories ... route every mutation through the coordinator".
--
-- The defect: every detached Retention surface resolved its database as
--   database = type(database) == "table" and database or NexusDB
-- so a call with no database silently read the raw global, and
-- AllowsRemoteRevision decided admission from a raw
-- communityRetentionEvictions marker in whatever table it was handed, with no
-- proof that table was the bound authority database.
--
-- RET-04 and RET-05 are guards: they pass before the repair and must keep
-- passing after it.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Codec.lua")
local S = dofile("tests/catalog_authority_support.lua")
dofile("core/DataRetention.lua")
local Case, Check = S.Case, S.Check

local now = 2000000000
time = function() return now end
UnitClass = function() return "Mage", "MAGE" end
UnitName = function() return "Boganic" end
GetNormalizedRealmName = function() return "Ebonhold" end
GetRealmName = GetNormalizedRealmName

local function Retention() return Nexus.DataRetention end

-- A database that was never bound as the authority, carrying a raw eviction
-- marker and ranked DPS content.
local function DetachedDatabase()
    local db = S.Database({retDetached=S.LocalBuild("retDetached", 2)})
    db.communityRetentionEvictions = {retDetached={blocked=true, stamp=1}}
    db.dpsCapture = {characterBest={dummy={}, lk={}}, personalBest={},
        buildBest={}}
    return db
end

-- RET-01 EXPECTED RED: a raw marker in a detached table decided admission.
Case("RET-01",
    "a detached database's raw eviction marker grants no veto authority",
function()
    local bound = S.Database({retBound=S.LocalBuild("retBound", 2)})
    S.Bind(bound)
    local detached = DetachedDatabase()
    -- The detached table is not the bound authority, so its raw marker proves
    -- nothing and cannot veto an inbound revision.
    local allowed = Retention().AllowsRemoteRevision(nil, nil, detached,
        "retDetached")
    Check(allowed == true,
        "a raw marker in an unbound detached database vetoed an inbound "
            .. "revision: " .. tostring(allowed))
end)

-- RET-02 EXPECTED RED: the raw-global fallback.
Case("RET-02",
    "a detached call never falls back to the raw NexusDB global",
function()
    local bound = S.Database({retLimits=S.LocalBuild("retLimits", 2)})
    bound.settings = {communityRetentionEnabled=false}
    S.Bind(bound)
    -- A hostile raw global that is NOT the bound authority. Nothing may read it.
    local foreign = S.Database()
    foreign.settings = {communityRetentionEnabled=true,
        communityRetentionMaxBuilds=1}
    local previousGlobal = NexusDB
    NexusDB = foreign
    local limits = Retention().Limits()
    NexusDB = previousGlobal
    Check(type(limits) == "table" and limits.enabled ~= true,
        "a detached Limits call read retention settings out of the raw global")
end)

-- RET-03 EXPECTED RED: the mutation path's raw-global fallback. RAW-01 forbids
-- a detached instance falling back to global NexusDB; it does not forbid
-- Enforce acting on a database the coordinator supplies explicitly.
Case("RET-03",
    "an unsupplied Enforce resolves the bound authority, never the raw global",
function()
    local bound = S.Database({retBound3=S.LocalBuild("retBound3", 2)})
    S.Bind(bound)
    -- Remove the raw global entirely. The old resolution was
    --   database = type(database) == "table" and database or NexusDB
    -- so with no global there was no database at all and Enforce refused.
    -- Resolving the exact bound authority instead is the repair. The global is
    -- cleared rather than pointed at a foreign table on purpose: swapping the
    -- global mid-session legitimately triggers the authorized coordinator
    -- rebind (MASTER-RC-009), which would confound this measurement.
    local previousGlobal = NexusDB
    NexusDB = nil
    local summary, why = Retention().Enforce(nil, "unsupplied")
    NexusDB = previousGlobal
    Check(type(summary) == "table",
        "an unsupplied Enforce did not resolve the bound authority: "
            .. tostring(why))
end)

-- RET-04 GUARD: the bound authority still answers, and reads stay pure.
Case("RET-04",
    "GUARD: the exact bound authority still answers and reads write nothing",
function()
    local bound = S.Database({retBound4=S.LocalBuild("retBound4", 2)})
    S.Bind(bound)
    local bytes = S.Encode(bound)
    local allowed = Retention().AllowsRemoteRevision(nil, nil, bound,
        "retBound4")
    Check(allowed == true,
        "the bound authority vetoed an unblocked id: " .. tostring(allowed))
    Check(S.Encode(bound) == bytes,
        "an AllowsRemoteRevision read mutated the bound authority database")
end)

-- RET-05 GUARD: Stats and SchemaVersion stay detached and side-effect free.
Case("RET-05",
    "GUARD: Stats returns a detached copy and never mutates its source",
function()
    local bound = S.Database({retBound5=S.LocalBuild("retBound5", 2)})
    bound.dataRetention = {schemaVersion=1, last={pruned=3}}
    S.Bind(bound)
    local bytes = S.Encode(bound)
    local stats = Retention().Stats(bound)
    Check(type(stats) == "table" and stats.pruned == 3,
        "Stats lost the recorded retention receipt")
    stats.pruned = -1
    Check(bound.dataRetention.last.pruned == 3,
        "Stats returned a live reference into the database")
    Check(S.Encode(bound) == bytes, "Stats mutated its source database")
end)

S.Finish("data retention detached isolation")
