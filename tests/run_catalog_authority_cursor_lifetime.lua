-- Package B / issue #22 Repair Wave 1: cursor lifetime and root release.
--
-- Covers MASTER-RC-011 (caller-retained stale tokens can retain one prior root
-- wrapper per generation).
--
-- Architecture at 3b5de54f, docs/SYNC_TRUST_CATALOG_AUTHORITY_STATE_MACHINE.md:
--   "`AuthorityCollectionCursorRegistryV1`: one private weak-key registry ... It
--    owns active caps, retained-memory bounds, page/Result shapes, supersession,
--    and stale/forged token refusal."
--   "The old bootstrap-root reference is lost immediately after swap."
-- MASTER-RC-011 acceptance: "Release old root/accumulator state at publication and
-- supersession; retain at most a bounded stale-once sentinel per family."
--
-- Reproduction from the MASTER packet: "Retain one unused token per generation,
-- publish new roots, begin replacement tokens, and inspect cursorRegistry
-- rootIdentity retention without invoking old tokens."
--
-- Expected-red measurement on the rejected candidate e69497d, before any product
-- edit in this wave:
--   CUR-01 RED  DebugStats() exposes no retained-root accounting at all.
--   CUR-02 RED  each publication leaves one more registry entry holding a prior
--               root wrapper, without bound.
--   CUR-03 GUARD a retained stale token still refuses with STALE_CURSOR.
--   CUR-04 RED  supersession by a replacement token in the same generation does
--               not release the superseded accumulator.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Codec.lua")
local S = dofile("tests/catalog_authority_support.lua")
local Case, Check = S.Case, S.Check

local now = 2000000000
time = function() return now end
UnitClass = function() return "Mage", "MAGE" end

local function Catalog() return Nexus.BuildCatalog end

local FAMILIES = 6

local function Stats()
    local catalog = Catalog()
    Check(type(catalog.DebugStats) == "function", "DebugStats export unavailable")
    return catalog.DebugStats()
end

local function RetainedRoots()
    local stats = Stats()
    Check(type(stats.retainedRoots) == "number",
        "DebugStats() exposes no retainedRoots accounting, so retained-root "
            .. "bounds are unobservable and unproven")
    return stats.retainedRoots
end

Case("CUR-01",
    "the cursor registry publishes a bounded retained-root count",
function()
    local db = S.Database({curA=S.LocalBuild("curA", 2)})
    S.Bind(db)
    local catalog = Catalog()
    Check(RetainedRoots() == 0,
        "a freshly admitted root already retains a superseded root wrapper")
    local token = catalog.BeginRecordCursor()
    Check(type(token) == "table", "record cursor unavailable")
    Check(RetainedRoots() == 0,
        "an active cursor bound to the current serving root was counted as retained")
end)

Case("CUR-02",
    "retained unused tokens do not accumulate one prior root per generation",
function()
    local db = S.Database({curA=S.LocalBuild("curA", 2)})
    S.Bind(db)
    local catalog = Catalog()
    -- Retain one unused token per generation and never consume it. The token is
    -- kept alive here exactly as a caller would keep it.
    local retained = {}
    for generation = 1, 12 do
        retained[#retained + 1] = catalog.BeginRecordCursor()
        retained[#retained + 1] = catalog.BeginSummaryCursor()
        retained[#retained + 1] = catalog.BeginDeltaCursor()
        Check(catalog.Put(S.LocalBuild("curGen" .. generation, generation + 1)),
            "publication fixture refused at generation " .. generation)
    end
    Check(#retained == 36, "fixture did not retain one token per family per generation")

    local held = RetainedRoots()
    Check(held <= FAMILIES,
        "retained tokens hold " .. tostring(held) .. " superseded root wrappers "
            .. "after 12 publications; the documented cap is at most one bounded "
            .. "stale sentinel per cursor family (" .. tostring(FAMILIES) .. ")")
end)

Case("CUR-03",
    "GUARD: a retained stale token still refuses after its root is superseded",
function()
    local db = S.Database({curA=S.LocalBuild("curA", 2)})
    S.Bind(db)
    local catalog = Catalog()
    local token = catalog.BeginRecordCursor()
    Check(catalog.RecordCursorNext(token).done == false,
        "the cursor served no row before supersession")
    Check(catalog.Put(S.LocalBuild("curB", 3)), "publication fixture refused")

    local result, why = catalog.RecordCursorNext(token)
    Check(result == nil, "a stale token served a page after its root was superseded")
    Check(why == "STALE_CURSOR" or why == "INVALID_CURSOR",
        "a stale token refused with " .. tostring(why))
end)

Case("CUR-04",
    "a superseded token in the same generation releases its accumulator",
function()
    local db = S.Database({
        curA=S.LocalBuild("curA", 2), curB=S.LocalBuild("curB", 3),
        curC=S.LocalBuild("curC", 4),
    })
    S.Bind(db)
    local catalog = Catalog()
    local superseded = {}
    for _ = 1, 8 do
        local token = catalog.BeginRecordCursor()
        catalog.RecordCursorNext(token)
        superseded[#superseded + 1] = token
    end
    -- Only the newest token per family is active. Every earlier one is
    -- superseded and must hold no root or accumulator state.
    local held = RetainedRoots()
    Check(held == 0,
        "eight superseded record tokens in one generation hold " .. tostring(held)
            .. " root wrappers; supersession must release them immediately")
    local result, why = catalog.RecordCursorNext(superseded[1])
    Check(result == nil and why == "INVALID_CURSOR",
        "a superseded token refused with " .. tostring(why)
            .. " instead of INVALID_CURSOR")
end)

-- ---------------------------------------------------------------------------
-- MASTER-RC-018, cursor consumers. The root map pairs RC-011 and RC-018 on this
-- shared lifetime-and-consumer fixture.
--
-- Root: "cursor error returns the accumulated prefix as if complete."
-- Required repaired outcome: "clean done distinguished from error; fixed
--  empty/refusal result on error."
--
-- Measured defect: core/CommunityController.lua and core/SyncCompatibility.lua
-- both walked a cursor with
--     if err or type(page) ~= "table" or page.done then break end
-- and then returned the accumulated table, so a mid-walk fault produced a
-- SHORT collection that was indistinguishable from a complete one.
-- core/ViewProjections.lua already had the correct shape
-- (`if err then all = {}; break end`), which is the contract the two consumers
-- now match.
local function ReadSource(path)
    local handle = assert(io.open(path, "rb"), "unable to read " .. path)
    local text = handle:read("*a")
    handle:close()
    return text
end

Case("CUR-05",
    "no mapped cursor consumer returns its accumulated prefix on error",
function()
    local offenders = {}
    for _, path in ipairs({"core/CommunityController.lua",
        "core/SyncCompatibility.lua", "core/CommunityProjection.lua",
        "core/ViewProjections.lua"}) do
        if ReadSource(path):find(
            'if err or type(page) ~= "table" or page.done then break end',
            1, true) then
            offenders[#offenders + 1] = path
        end
    end
    Check(#offenders == 0,
        "a cursor error is still treated as a clean done in: "
            .. table.concat(offenders, ", "))
end)

Case("CUR-06",
    "GUARD: a clean cursor walk still returns the complete collection",
function()
    local catalog = Nexus.BuildCatalog
    local db = S.Database({
        cur06a=S.LocalBuild("cur06a", 2), cur06b=S.LocalBuild("cur06b", 2),
        cur06c=S.LocalBuild("cur06c", 2),
    })
    S.Bind(db)
    local token = catalog.BeginRecordCursor()
    Check(token ~= nil, "record cursor was refused")
    local seen, guard = {}, 0
    while guard < 4096 do
        guard = guard + 1
        local page, err = catalog.RecordCursorNext(token)
        Check(err == nil, "a clean walk reported an error: " .. tostring(err))
        if type(page) ~= "table" or page.done then break end
        if page.id ~= nil then seen[page.id] = true end
    end
    Check(seen.cur06a and seen.cur06b and seen.cur06c,
        "a clean cursor walk lost a row")
end)

S.Finish("catalog authority cursor lifetime")
