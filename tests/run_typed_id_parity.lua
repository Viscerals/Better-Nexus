-- Package B / issue #22 Repair Wave 1: MASTER-RC-012, typed identity.
--
-- Root: "second typed-ID encodings; tostring comparison makes numeric 1 and
--  string \"1\" tie."
-- Required repaired outcome: "one canonical codec and comparator: number-first
--  numeric, then bytewise string."
--
-- The defect: core/BuildCatalog.lua carries the canonical collision-free codec
-- and comparator, but core/DataRetention.lua and core/ViewProjections.lua each
-- define a SECOND encoder
--   local function TypedIdentity(value)
--       return type(value) .. ":" .. tostring(value == nil and "" or value)
--   end
-- and core/DataRetention.lua ranks with
--   return tostring(left.key) < tostring(right.key)
-- so ordering runs through tostring instead of the canonical comparator and
-- numeric ids sort lexically ("number:10" before "number:2").
--
-- TID-05 is a guard: it passes before the repair and must keep passing after.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Codec.lua")
local S = dofile("tests/catalog_authority_support.lua")
dofile("core/DataRetention.lua")
dofile("core/ViewProjections.lua")
local Case, Check = S.Case, S.Check
local function AwaitMutation(ok, why, ticket)
    return S.AwaitCatalogMutation(ok, why, ticket,
        "typed-id fixture mutation")
end

local now = 2000000000
time = function() return now end
UnitClass = function() return "Mage", "MAGE" end
UnitName = function() return "Boganic" end
GetNormalizedRealmName = function() return "Ebonhold" end
GetRealmName = GetNormalizedRealmName

local function Read(path)
    local handle = assert(io.open(path, "rb"), "unable to read " .. path)
    local text = handle:read("*a")
    handle:close()
    return text
end

local function CountLiteral(text, needle)
    local count, start = 0, 1
    while true do
        local at = text:find(needle, start, true)
        if not at then return count end
        count, start = count + 1, at + #needle
    end
end

-- TID-01 EXPECTED RED: duplicate encoders.
Case("TID-01",
    "exactly one typed-identity encoder is defined across core/",
function()
    local duplicates = 0
    for _, path in ipairs({"core/DataRetention.lua", "core/ViewProjections.lua",
        "core/BuildCatalog.lua", "core/DpsCapture.lua"}) do
        local text = Read(path)
        duplicates = duplicates
            + CountLiteral(text, "local function TypedIdentity(value)")
            + CountLiteral(text, 'return type(value) .. ":" .. tostring(value)')
    end
    Check(duplicates == 0,
        "found " .. duplicates .. " duplicate typed-identity encoders outside "
            .. "the canonical codec")
end)

-- TID-02 EXPECTED RED: tostring ranking.
Case("TID-02",
    "no typed identity is ordered through tostring",
function()
    local offenders = {}
    for _, path in ipairs({"core/DataRetention.lua", "core/ViewProjections.lua",
        "core/BuildCatalog.lua", "core/DpsCapture.lua"}) do
        local text = Read(path)
        if text:find("tostring(left.key) < tostring(right.key)", 1, true)
            or text:find("TypedIdentity(left) < TypedIdentity(right)", 1, true)
            or text:find("TypedIdentity(left.id) < TypedIdentity(right.id)",
                1, true) then
            offenders[#offenders + 1] = path
        end
    end
    Check(#offenders == 0,
        "typed identity is still ordered through tostring in: "
            .. table.concat(offenders, ", "))
end)

-- TID-03 EXPECTED RED: the canonical codec is not reachable as one codec.
Case("TID-03",
    "the canonical typed-identity codec distinguishes numeric 1 from \"1\"",
function()
    local identity = Nexus.Identity
    Check(type(identity.TypedIdentity) == "function",
        "no canonical Identity.TypedIdentity codec exists")
    local numeric = identity.TypedIdentity(1)
    local text = identity.TypedIdentity("1")
    Check(numeric ~= text,
        "numeric 1 and string \"1\" produced the same typed identity")
    Check(identity.TypedIdentity("ab") ~= identity.TypedIdentity("a")
            .. identity.TypedIdentity("b"),
        "the typed identity encoding is not collision free under concatenation")
end)

-- TID-04 EXPECTED RED: the canonical comparator.
Case("TID-04",
    "the canonical comparator is number-first numeric, then bytewise string",
function()
    local identity = Nexus.Identity
    Check(type(identity.CompareTypedIds) == "function",
        "no canonical Identity.CompareTypedIds comparator exists")
    Check(identity.CompareTypedIds(2, 10) < 0,
        "numeric ids did not compare numerically: 2 must precede 10")
    Check(identity.CompareTypedIds(10, 2) > 0,
        "numeric comparison is not antisymmetric")
    Check(identity.CompareTypedIds(1, "1") < 0,
        "a number did not sort before a string of the same text")
    Check(identity.CompareTypedIds("ab", "b") < 0,
        "strings did not compare bytewise")
    Check(identity.CompareTypedIds("a", "a") == 0,
        "equal strings did not compare equal")
end)

-- TID-05 GUARD: the catalog keeps numeric and string ids in distinct slots.
Case("TID-05",
    "GUARD: numeric and string ids occupy distinct catalog slots",
function()
    local db = S.Database()
    S.Bind(db)
    local catalog = Nexus.BuildCatalog
    Check(AwaitMutation(catalog.Put(S.LocalBuild(7, 2, {id=7}))),
        "numeric id was refused")
    Check(AwaitMutation(catalog.Put(S.LocalBuild("7", 2, {id="7"}))),
        "string id was refused")
    local numeric, text = catalog.Get(7), catalog.Get("7")
    Check(type(numeric) == "table" and type(text) == "table",
        "one of the two typed ids was lost")
    Check(numeric.id ~= text.id or type(numeric.id) ~= type(text.id),
        "numeric and string ids collapsed into one slot")
end)

-- Wave 2 MASTER-W1-001 expected red. Distinct typed IDs can share one exact
-- content fingerprint. Winner selection must not depend on mutation history.
Case("TID-06",
    "numeric/string exact winner is stable after removal, reinsertion, and reload",
function()
    local db = S.Database()
    S.Bind(db)
    local catalog = Nexus.BuildCatalog
    Check(AwaitMutation(catalog.Put(S.LocalBuild(1, 2, {id=1}))),
        "numeric id was refused")
    Check(AwaitMutation(catalog.Put(S.LocalBuild("1", 2, {id="1"}))),
        "string id was refused")
    local numericState = catalog.AuthorityState(1)
    local stringState = catalog.AuthorityState("1")
    Check(type(numericState.fingerprint) == "string"
            and numericState.fingerprint == stringState.fingerprint,
        "fixture did not create one shared exact fingerprint")
    local fingerprint = numericState.fingerprint
    local initial = catalog.FindExactFingerprintId(fingerprint)
    Check(type(initial) == "number" and initial == 1,
        "number-first order did not select numeric 1 initially")

    Check(AwaitMutation(catalog.RemoveOverlay(1)),
        "numeric winner removal was refused")
    local afterRemoval = catalog.FindExactFingerprintId(fingerprint)
    Check(type(afterRemoval) == "string" and afterRemoval == "1",
        "string id did not become winner after numeric removal")

    Check(AwaitMutation(catalog.Put(S.LocalBuild(1, 2, {id=1}))),
        "numeric reinsertion was refused")
    local afterReinsert = catalog.FindExactFingerprintId(fingerprint)
    Check(type(afterReinsert) == "number" and afterReinsert == 1,
        "numeric 1 did not regain the winner after reinsertion")

    S.Reload()
    S.Bind(db)
    local reconstructed = Nexus.BuildCatalog.FindExactFingerprintId(fingerprint)
    Check(type(reconstructed) == "number" and reconstructed == 1,
        "exact-index reconstruction selected a different typed winner")
end)

S.Finish("typed identity parity")
