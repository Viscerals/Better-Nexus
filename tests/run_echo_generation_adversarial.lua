-- Stage 18.3 adversarial matrix for semantic Echo generations.
local F = dofile("tests/automation_live_fixture.lua")
local H = F.H

local echoFields = {"slots", "granted", "locked", "discovery", "activeSlot"}

local beforeMixed = F.Snapshot()
local slots = assert(H.service.GetServerBuildSlots())
slots[1].echoes[2].stacks = slots[1].echoes[2].stacks + 1
H.SetServerActiveSlot(2)
H.granted["Alpha Strike"][#H.granted["Alpha Strike"] + 1] =
    {spellId=200100,quality=3}
H.locked[#H.locked + 1] = {spellId=200102,quality=2,stack=1}
H.discovered[200110] = true
H.disabledEchoes[200110] = true
H.NotifyEchoDataChanged()
H.NotifyEchoDataChanged()
H.NotifyEchoDataChanged()
H.Advance(0.2, 0.2)
local afterMixed = F.Snapshot()
assert(afterMixed.echoReconcile.notifications
        - beforeMixed.echoReconcile.notifications == 3
    and afterMixed.echoReconcile.scans - beforeMixed.echoReconcile.scans == 1,
    "mixed notification burst did not coalesce to one snapshot scan")
for _, field in ipairs(echoFields) do
    assert(F.FixedDelta(afterMixed, beforeMixed,
        "echoFieldChanges", field) == 1,
        "mixed change did not advance " .. field .. " exactly once")
end
assert(F.Delta(afterMixed, beforeMixed, "fullSteps") == 1
    and F.Delta(afterMixed, beforeMixed, "associationRefreshes") == 1
    and F.FixedDelta(afterMixed, beforeMixed,
        "echoDirtyReasons", "slots") == 1
    and F.FixedDelta(afterMixed, beforeMixed,
        "echoDirtyReasons", "data") == 1
    and F.Delta(afterMixed, beforeMixed, "policy") == 0
    and F.Delta(afterMixed, beforeMixed, "actions") == 0,
    "mixed semantic change escaped one-shot dirty/association boundaries")

local beforeEquivalentBurst = F.Snapshot()
for _ = 1, 4 do H.NotifyEchoDataChanged() end
H.Advance(0.2, 0.2)
local afterEquivalentBurst = F.Snapshot()
assert(afterEquivalentBurst.echoReconcile.notifications
        - beforeEquivalentBurst.echoReconcile.notifications == 4
    and afterEquivalentBurst.echoReconcile.scans
        - beforeEquivalentBurst.echoReconcile.scans == 1
    and afterEquivalentBurst.echoReconcile.equivalentNotifications
        - beforeEquivalentBurst.echoReconcile.equivalentNotifications == 1
    and F.Delta(afterEquivalentBurst, beforeEquivalentBurst, "fullSteps") == 0
    and F.Delta(afterEquivalentBurst, beforeEquivalentBurst,
        "associationRefreshes") == 0,
    "equivalent repeated notifications performed work")

local beforeMissed = F.Snapshot()
slots[1].echoes[2].stacks = slots[1].echoes[2].stacks + 1
H.locked[#H.locked + 1] = {spellId=200100,quality=3,stack=1}
H.Advance(5.2, 0.2)
local afterMissed = F.Snapshot()
assert(F.Delta(afterMissed, beforeMissed, "fallbackRepairs") == 1
    and F.Delta(afterMissed, beforeMissed, "fullSteps") == 1
    and F.FixedDelta(afterMissed, beforeMissed,
        "echoFieldChanges", "slots") == 1
    and F.FixedDelta(afterMissed, beforeMissed,
        "echoFieldChanges", "locked") == 1
    and F.FixedDelta(afterMissed, beforeMissed,
        "runtimeMismatchFields", "slots") == 1
    and F.FixedDelta(afterMissed, beforeMissed,
        "runtimeMismatchFields", "locked") == 1
    and F.Delta(afterMissed, beforeMissed, "associationRefreshes") == 1,
    "mixed missed signal was not repaired exactly once")

local function ExpectReject(label, serviceName, replacement)
    local original = H.service[serviceName]
    local before = F.Snapshot()
    H.service[serviceName] = replacement
    H.NotifyEchoDataChanged()
    H.Advance(0.2, 0.2)
    H.service[serviceName] = original
    local after = F.Snapshot()
    assert(after.echoReconcile.failures - before.echoReconcile.failures == 1
        and F.Delta(after, before, "fullSteps") == 0
        and F.Delta(after, before, "associationRefreshes") == 0,
        label .. " did not fail closed")
    for _, field in ipairs(echoFields) do
        assert(after.echoGenerations[field] == before.echoGenerations[field],
            label .. " published " .. field)
    end
    H.NotifyEchoDataChanged()
    H.Advance(0.2, 0.2)
end

ExpectReject("missing required reader", "GetGrantedPerks", nil)
ExpectReject("invalid maximum slot", "GetServerMaxSlots", function() return 0 end)
ExpectReject("invalid active slot", "GetServerActiveSlot", function() return -1 end)

local malformedVerified = H.CloneValue(H.service.GetServerBuildSlots())
malformedVerified[1].verified = "false"
ExpectReject("non-boolean verified state", "GetServerBuildSlots",
    function() return malformedVerified end)
local malformedLockedFlag = H.CloneValue(H.service.GetServerBuildSlots())
malformedLockedFlag[1].echoes[1].locked = "false"
ExpectReject("non-boolean slot lock state", "GetServerBuildSlots",
    function() return malformedLockedFlag end)
local extraGrantedKey = H.CloneValue(H.granted)
extraGrantedKey["Alpha Strike"].extra =
    {spellId=200100,quality=3}
ExpectReject("extra granted-array key", "GetGrantedPerks",
    function() return extraGrantedKey end)
ExpectReject("false discovery marker", "GetDiscoveredEchoes",
    function() return {[200100]=false} end)
ExpectReject("non-boolean disabled state", "IsTomeEchoDisabled",
    function() return 1 end)
ExpectReject("conflicting locked count aliases", "GetLockedPerks",
    function() return {{spellId=200104,stack=1,count=2}} end)
ExpectReject("conflicting locked id aliases", "GetLockedPerks",
    function() return {{spellId=200104,id=200102,stack=1}} end)

local function CountKeys(values)
    local count = 0
    for _ in pairs(values or {}) do count = count + 1 end
    return count
end

local beforeDiagnostics = F.Snapshot()
for _ = 1, 100 do
    local echo = Nexus.GameAdapter.EchoReconcileStats()
    local runtime = Nexus.RecomputeStats()
    assert(CountKeys(echo.generations) == 5
        and CountKeys(echo.fieldChanges) == 5
        and CountKeys(echo.dirtyReasons) == 2
        and CountKeys(runtime.fallbackMismatchFields) == 15
        and CountKeys(runtime.fullStepTriggers) == 6
        and #tostring(echo.lastReason or "") <= 96
        and #tostring(runtime.lastFallbackReason or "") <= 96,
        "diagnostics changed cardinality or exceeded their text bound")
    echo.generations.slots = -1
    runtime.fallbackMismatchFields.slots = -1
end
local afterDiagnostics = F.Snapshot()
assert(F.Delta(afterDiagnostics, beforeDiagnostics, "fullSteps") == 0
    and F.Delta(afterDiagnostics, beforeDiagnostics, "policy") == 0
    and Nexus.GameAdapter.EchoReconcileStats().generations.slots >= 0
    and Nexus.RecomputeStats().fallbackMismatchFields.slots >= 0,
    "diagnostic reads or returned-map mutation influenced runtime state")

print(string.format(
    "Echo generation adversarial matrix: mixedFields=%d notifications=%d scans=%d full=%d associations=%d malformedCases=10 diagnosticReads=100 -- OK",
    #echoFields,
    afterMixed.echoReconcile.notifications - beforeMixed.echoReconcile.notifications,
    afterMixed.echoReconcile.scans - beforeMixed.echoReconcile.scans,
    F.Delta(afterMixed, beforeMixed, "fullSteps"),
    F.Delta(afterMixed, beforeMixed, "associationRefreshes")))
