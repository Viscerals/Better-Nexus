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
        echoes={{spellId=820001,quality=1,stacks=1}},
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

local contradictoryClaim = Row("lk", 700, "alice@realm", "820001x1", lockA)
contradictoryClaim.echoes = {{spellId=820002,quality=1,stacks=1}}
Check(Evidence.DpsSummary(
        {Row("dummy", 500, "alice@realm", "820001x1", lockA)},
        {contradictoryClaim}).average == 0,
    "equal claimed fingerprints with different ordinary pools synthesized an average")
local missingOrdinary = Row("lk", 700, "alice@realm", "820001x1", lockA)
missingOrdinary.echoes = nil
Check(Evidence.DpsSummary(
        {Row("dummy", 500, "alice@realm", "820001x1", lockA)},
        {missingOrdinary}).average == 0,
    "missing ordinary evidence authorized a paired average")

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

local equalDummyA = Row("dummy", 600, "alice@realm", "820001x1", lockA)
equalDummyA.sourceIdentity = "source-b"
local equalDummyB = Row("dummy", 600, "alice@realm", "820001x1", lockA)
equalDummyB.sourceIdentity = "source-a"
local equalLk = Row("lk", 700, "alice@realm", "820001x1", lockA)
local equalFirst = Evidence.DpsSummary({equalDummyA,equalDummyB},{equalLk})
local equalSecond = Evidence.DpsSummary({equalDummyB,equalDummyA},{equalLk})
Check(equalFirst.pair.dummy.sourceIdentity == "source-a"
        and equalSecond.pair.dummy.sourceIdentity == "source-a",
    "equal-DPS duplicate selection depended on input order")

local outputDummyA = Row("dummy", 600, "alice@realm", "820001x1", lockA)
outputDummyA.duration = 20
outputDummyA.build = {variant="b", nested={rank=2}}
local outputDummyB = Row("dummy", 600, "alice@realm", "820001x1", lockA)
outputDummyB.duration = 10
outputDummyB.build = {variant="a", nested={rank=1}}
local outputFirst = Evidence.DpsSummary(
    {outputDummyA,outputDummyB},{equalLk})
local outputSecond = Evidence.DpsSummary(
    {outputDummyB,outputDummyA},{equalLk})
Check(outputFirst.pair.dummy.duration == outputSecond.pair.dummy.duration
        and outputFirst.pair.dummy.build.variant
            == outputSecond.pair.dummy.build.variant,
    "output-relevant equal-DPS tie depended on input order")

local clockDummyA = Row("dummy", 600, "alice@realm", "820001x1", lockA)
clockDummyA.ts = 900
clockDummyA.lastModified = 901
clockDummyA.build = {postedAt=902,nested={capturedAt=903,variant="same"}}
local clockDummyB = Row("dummy", 600, "alice@realm", "820001x1", lockA)
clockDummyB.ts = 100
clockDummyB.lastModified = 101
clockDummyB.build = {postedAt=102,nested={capturedAt=103,variant="same"}}
local clockFirst = Evidence.DpsSummary({clockDummyA,clockDummyB},{equalLk})
local clockSecond = Evidence.DpsSummary({clockDummyB,clockDummyA},{equalLk})
Check(clockFirst.pair.tie == clockSecond.pair.tie
        and clockFirst.pair.dummy.ts == nil
        and clockSecond.pair.dummy.ts == nil
        and clockFirst.pair.dummy.lastModified == nil
        and clockFirst.pair.dummy.build.postedAt == nil
        and clockFirst.pair.dummy.build.nested.capturedAt == nil
        and clockFirst.pair.dummy.build.nested.variant == "same",
    "top-level or nested clocks changed equal-DPS pair output")
Check(clockDummyA.ts == 900 and clockDummyA.build.postedAt == 902
        and clockDummyA.build.nested.capturedAt == 903,
    "clock-neutral pair projection mutated historical source evidence")

local huge = 1e308
local overflowSummary = Evidence.DpsSummary(
    {Row("dummy", huge, "alice@realm", "820001x1", lockA)},
    {Row("lk", huge, "alice@realm", "820001x1", lockA)})
Check(overflowSummary.average == huge
        and overflowSummary.average < math.huge
        and overflowSummary.pair.average == huge,
    "finite operands synthesized a nonfinite paired average")
local overflowPairs = Evidence.RealDpsPairs(
    {Row("dummy", huge, "alice@realm", "820001x1", lockA)},
    {Row("lk", huge, "alice@realm", "820001x1", lockA)})
Check(#overflowPairs == 1 and overflowPairs[1].average == huge
        and Evidence.DpsRowBefore(overflowPairs[1].dummy,
            Row("dummy", 1, "alice@realm", "820001x1", lockA)),
    "overflow-safe pair did not remain finite for ordering consumers")

local manyDummy = {}
for index = 1, 100 do
    manyDummy[index] = Row("dummy", 500 + index,
        "alice@realm", "820001x1", lockA)
end
local cursor = Evidence.BeginRealDpsPairs(manyDummy, {equalLk})
Check(cursor.dummyIndex == 1 and next(cursor.dummyByIdentity) == nil,
    "real-pair cursor indexed the full Dummy bucket synchronously")
local done, work = Evidence.PumpRealDpsPairs(cursor, 1)
Check(done == false and work == 1 and cursor.dummyIndex == 2,
    "real-pair cursor exceeded its one-unit indexing budget")

for _, invalid in ipairs({0/0, math.huge, -math.huge, 0, -1, "bad"}) do
    local invalidSummary = Evidence.DpsSummary(
        {Row("dummy", invalid, "alice@realm", "820001x1", lockA)},
        {Row("lk", 700, "alice@realm", "820001x1", lockA)})
    Check(invalidSummary.dummy == 0 and invalidSummary.average == 0
            and invalidSummary.pair == nil,
        "invalid Dummy DPS entered category or paired summary: "
            .. tostring(invalid))
end

print("Paired DPS summary tests passed: " .. checks)
