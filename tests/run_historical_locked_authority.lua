-- Stage 49.1: historical category snapshots are immutable evidence, never
-- current/build copy authority. Exact build-bound locked rows may authorize a
-- copy without rewriting those snapshots.
Nexus = {}
dofile("core/CandidateEvidence.lua")

local Evidence = assert(Nexus.CandidateEvidence)
local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end

local function Signature(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {"{"}
    for _, key in ipairs(keys) do
        out[#out + 1] = tostring(key) .. "=" .. Signature(value[key]) .. ";"
    end
    out[#out + 1] = "}"
    return table.concat(out)
end

local ordinary = {{spellId=810001,quality=2,stacks=1}}
local currentLocked = {{spellId=810010,quality=4,stacks=1,
    future={authority="current"},locked=true}}
local dummy = {category="dummy",buildId="build-49",
    fingerprint="810001x1",echoes=ordinary,
    lockedEchoes={{spellId=810020,quality=3,stacks=1,
        future={capture="dummy"}}}}
local lk = {category="lk",buildId="build-49",
    fingerprint="810001x1",echoes=ordinary,
    lockedEchoes={{spellId=810030,quality=3,stacks=1,
        future={capture="lk"}}}}
local dummyBefore, lkBefore = Signature(dummy), Signature(lk)

local historicalOnly = Evidence.ResolveLocked({
    ordinaryEchoes=ordinary,buildId="build-49",fingerprint="810001x1",
    dummyRecord=dummy,lkRecord=lk,copyAuthorityRequired=true,
})
Check(historicalOnly.status == "conflict"
        and #historicalOnly.lockedEchoes == 0,
    "conflicting historical snapshots granted copy authority")

local exactCurrent = Evidence.ResolveLocked({
    build={id="build-49",fingerprint="810001x1",echoes={
        ordinary[1],currentLocked[1],
    }},dummyRecord=dummy,lkRecord=lk,copyAuthorityRequired=true,
})
Check(exactCurrent.status == "ok" and exactCurrent.source == "build"
        and exactCurrent.lockedEchoes[1].spellId == 810010,
    "exact build-bound current evidence did not resolve copy authority")
Check(Signature(dummy) == dummyBefore and Signature(lk) == lkBefore,
    "copy resolution mutated historical DPS snapshots")

local exactEmpty = Evidence.ResolveLocked({
    build={id="build-49",fingerprint="810001x1",echoes=ordinary,
        lockedEchoes={},lockedAuthorityProven=true},
    dummyRecord=dummy,lkRecord=lk,copyAuthorityRequired=true,
})
Check(exactEmpty.status == "none" and exactEmpty.source == "build"
        and #exactEmpty.lockedEchoes == 0,
    "exact proven empty current authority fell through to historical conflict")
Check(Signature(dummy) == dummyBefore and Signature(lk) == lkBefore,
    "empty current authority mutated historical DPS snapshots")

-- Simulate restart/reload before a later Sync supplies the same exact current
-- state. Historical category bytes remain immutable across module ownership.
dofile("core/CandidateEvidence.lua")
Evidence = assert(Nexus.CandidateEvidence)
local afterRestartSync = Evidence.ResolveLocked({
    build={id="build-49",fingerprint="810001x1",echoes={
        ordinary[1],currentLocked[1],
    }},dummyRecord=dummy,lkRecord=lk,copyAuthorityRequired=true,
})
Check(afterRestartSync.status == "ok"
        and afterRestartSync.source == "build"
        and afterRestartSync.lockedEchoes[1].spellId == 810010,
    "later exact Sync state did not converge after restart/reload")
Check(Signature(dummy) == dummyBefore and Signature(lk) == lkBefore,
    "restart/reload/Sync convergence mutated historical snapshots")

local matchingDummy = {category="dummy",buildId="build-49",
    fingerprint="810001x1",echoes=ordinary,lockedEchoes=currentLocked}
local matchingLk = {category="lk",buildId="build-49",
    fingerprint="810001x1",echoes=ordinary,lockedEchoes=currentLocked}
local matchingHistory = Evidence.ResolveLocked({
    ordinaryEchoes=ordinary,buildId="build-49",fingerprint="810001x1",
    dummyRecord=matchingDummy,lkRecord=matchingLk,copyAuthorityRequired=true,
})
Check(matchingHistory.status == "unavailable"
        and #matchingHistory.lockedEchoes == 0,
    "matching historical categories were promoted to current copy authority")

local reversed = Evidence.ResolveLocked({
    build={id="build-49",fingerprint="810001x1",echoes={
        ordinary[1],currentLocked[1],
    }},records={lk=lk,dummy=dummy},copyAuthorityRequired=true,
})
Check(reversed.status == "ok" and reversed.source == "build"
        and Signature(reversed.lockedEchoes) == Signature(exactCurrent.lockedEchoes),
    "category order changed exact copy authority")

print("Historical locked authority tests passed: " .. checks)
