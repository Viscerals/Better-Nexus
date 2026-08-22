-- Stage 49.2: Average is derived from one real authority-compatible pair.
Nexus = {Identity={}}
function Nexus.Identity.VerifiedOwnerKey(row)
    if type(row) ~= "table" or row.ownerVerified ~= true
        or type(row.ownerKey) ~= "string" then return nil end
    return row.ownerKey:lower()
end
dofile("core/CandidateEvidence.lua")
local Evidence = assert(Nexus.CandidateEvidence)
local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end
local function Row(category, dps, owner, ordinary, locked, stamp)
    return {category=category,dps=dps,player=owner,ownerKey=owner,
        ownerVerified=true,fingerprint=ordinary,lockedEchoes=locked,
        ts=stamp or 1,buildId="shared-build"}
end
local lockA = {{spellId=820010,quality=3,stacks=1}}
local lockB = {{spellId=820010,quality=4,stacks=1}}

local differentOwners = Evidence.DpsSummary(
    {Row("dummy", 500, "alice@realm", "820001x1", lockA)},
    {Row("lk", 700, "bob@realm", "820001x1", lockA)})
Check(differentOwners.dummy == 500 and differentOwners.lk == 700
        and differentOwners.average == 0 and differentOwners.pair == nil,
    "different canonical owners synthesized a paired average")

local differentLocked = Evidence.DpsSummary(
    {Row("dummy", 500, "alice@realm", "820001x1", lockA)},
    {Row("lk", 700, "alice@realm", "820001x1", lockB)})
Check(differentLocked.average == 0,
    "different locked full-combat identities synthesized an average")

local differentOrdinary = Evidence.DpsSummary(
    {Row("dummy", 500, "alice@realm", "820001x1", lockA)},
    {Row("lk", 700, "alice@realm", "820002x1", lockA)})
Check(differentOrdinary.average == 0,
    "different ordinary fingerprints synthesized an average")

local dummy = {
    Row("dummy", 500, "alice@realm", "820001x1", lockA, 99),
    Row("dummy", 600, "alice@realm", "820001x1", lockA, 1),
}
local lk = {
    Row("lk", 700, "alice@realm", "820001x1", lockA, 100),
    Row("lk", 650, "alice@realm", "820001x1", lockA, 2),
}
local first = Evidence.DpsSummary(dummy, lk)
local second = Evidence.DpsSummary({dummy[2],dummy[1]}, {lk[2],lk[1]})
Check(first.average == 650 and second.average == 650
        and first.pair.dummyDps == second.pair.dummyDps
        and first.pair.lkDps == second.pair.lkDps,
    "record or timestamp order changed deterministic pair selection")

print("Paired DPS summary tests passed: " .. checks)
