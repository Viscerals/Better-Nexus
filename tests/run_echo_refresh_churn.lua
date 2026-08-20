-- Stage 18.2 semantic-generation correction for fresh equivalent Echo replies.
local F = dofile("tests/automation_live_fixture.lua")
local H = F.H

assert(H.playerLevel == 80 and H.Perks.currentChoice == nil,
    "fixture lost the level-80/no-board live shape")
assert(NexusDB.settings.autoPick == true
    and NexusDB.settings.autoLockEchoes == true
    and F.runtime and F.runtime.AutoEnabled() == false,
    "fixture lost enabled preferences or runtime-disabled automation")
local initialSlots = assert(H.service.GetServerBuildSlots())
for slot = 1, 5 do
    assert(initialSlots[slot] and #initialSlots[slot].echoes == 85,
        "fixture lost one of five approximately 85-Echo slots")
end

local function ExpectOneRecompute(label, mutate, elapsed, associationExpected,
    echoField)
    local before = F.Snapshot()
    mutate()
    H.Advance(elapsed or 0.2, 0.2)
    local after = F.Snapshot()
    assert(F.Delta(after, before, "fullSteps") == 1,
        label .. " did not produce exactly one recomputation")
    assert(F.Delta(after, before, "policy") == 0
        and F.Delta(after, before, "actions") == 0,
        label .. " escaped the no-board/no-runtime-automation boundary")
    assert(F.Delta(after, before, "associationRefreshes")
        == (associationExpected or 0),
        label .. " refreshed associations an unexpected number of times")
    if echoField then
        assert(F.FixedDelta(after, before, "echoFieldChanges", echoField) == 1,
            label .. " did not advance its semantic Echo generation once")
    end

    local settledBefore = F.Snapshot()
    H.EnableFreshEchoReplies(true)
    H.Advance(5, 0.2)
    H.EnableFreshEchoReplies(false)
    local settledAfter = F.Snapshot()
    local settledFull = F.Delta(settledAfter, settledBefore, "fullSteps")
    local settledRepairs = F.Delta(
        settledAfter, settledBefore, "fallbackRepairs")
    local settledAssociations = F.Delta(
        settledAfter, settledBefore, "associationRefreshes")
    assert(settledFull == 0 and settledRepairs == 0
        and settledAssociations == 0,
        string.format("%s did not settle: full=%d repairs=%d associations=%d reason=%s",
            label,settledFull,settledRepairs,settledAssociations,
            tostring(settledAfter.lastReason)))
end

ExpectOneRecompute("slot content", function()
    local slots = H.service.GetServerBuildSlots()
    slots[1].echoes[1].stacks = slots[1].echoes[1].stacks + 1
    H.NotifyEchoDataChanged()
end, nil, 1, "slots")

ExpectOneRecompute("active slot", function()
    H.SetServerActiveSlot(2)
    H.NotifyEchoDataChanged()
end, nil, 1, "activeSlot")

ExpectOneRecompute("owned Echoes", function()
    H.granted["Alpha Strike"][#H.granted["Alpha Strike"] + 1] =
        {spellId=200100,quality=3}
    H.NotifyEchoDataChanged()
end, nil, 0, "granted")

ExpectOneRecompute("locked Echoes", function()
    H.locked[#H.locked + 1] = {spellId=200102,quality=2,stack=1}
    H.NotifyEchoDataChanged()
end, nil, 0, "locked")

ExpectOneRecompute("discovered/disabled Echoes", function()
    H.discovered[200110] = true
    H.disabledEchoes[200110] = true
    H.NotifyEchoDataChanged()
end, nil, 0, "discovery")

ExpectOneRecompute("settings", function()
    NexusDB.settings = {
        autoPick=true,autoLockEchoes=true,anchorSpellId=200102,
    }
end, 5.2, 0)

ExpectOneRecompute("association", function()
    local state = assert(Nexus.Store.State())
    local associations = H.CloneValue(state.loadoutWishlists or {})
    associations[2] = {
        slot=2,name="Echo Refresh Association",
        echoes={{spellId=200100,quality=3,stacks=1}},
    }
    state.loadoutWishlists = associations
end, 5.2, 0)

local missedBefore = F.Snapshot()
H.granted["Beta Guard"][#H.granted["Beta Guard"] + 1] =
    {spellId=200102,quality=2}
H.Advance(5.2, 0.2)
local missedAfter = F.Snapshot()
assert(F.Delta(missedAfter, missedBefore, "fullSteps") == 1
    and F.Delta(missedAfter, missedBefore, "fallbackRepairs") == 1
    and F.FixedDelta(missedAfter, missedBefore,
        "echoFieldChanges", "granted") == 1
    and F.FixedDelta(missedAfter, missedBefore,
        "runtimeMismatchFields", "granted") == 1
    and F.FixedDelta(missedAfter, missedBefore,
        "runtimeFullStepTriggers", "fallbacks") == 1,
    "five-second fallback did not repair one missed represented change once")
local missedSettled = F.Snapshot()
H.Advance(5, 0.2)
local missedFinal = F.Snapshot()
assert(F.Delta(missedFinal, missedSettled, "fullSteps") == 0
    and F.Delta(missedFinal, missedSettled, "fallbackRepairs") == 0,
    "missed represented change repaired more than once")

local realSlotsGetter = H.service.GetServerBuildSlots
local function ExpectLastGood(label, serviceName, replacement)
    local beforeFailure = F.Snapshot()
    local realGetter = H.service[serviceName]
    H.service[serviceName] = replacement
    H.NotifyEchoDataChanged()
    H.Advance(0.2, 0.2)
    H.service[serviceName] = realGetter
    local afterFailure = F.Snapshot()
    local failureDelta = afterFailure.echoReconcile.failures
        - beforeFailure.echoReconcile.failures
    local fullDelta = F.Delta(afterFailure, beforeFailure, "fullSteps")
    assert(F.Delta(afterFailure, beforeFailure, "fullSteps") == 0
        and failureDelta == 1,
        string.format("%s did not fail closed: failures=%d full=%d",
            label, failureDelta, fullDelta))
    for _, field in ipairs({"slots","granted","locked","discovery","activeSlot"}) do
        assert((afterFailure.echoGenerations[field] or 0)
            == (beforeFailure.echoGenerations[field] or 0),
            label .. " published a partial semantic generation")
    end
    H.NotifyEchoDataChanged()
    H.Advance(0.2, 0.2)
    local recovered = F.Snapshot()
    assert(F.Delta(recovered, afterFailure, "fullSteps") == 0,
        label .. " did not retain and recover the last-good snapshot")
end

ExpectLastGood("failing Echo read", "GetServerBuildSlots",
    function() error("fixture read failure") end)
ExpectLastGood("malformed Echo read", "GetServerBuildSlots",
    function() return "malformed" end)
local sparseSlots = H.CloneValue(realSlotsGetter())
sparseSlots[1].echoes = {
    [1]=sparseSlots[1].echoes[1], [3]=sparseSlots[1].echoes[3],
}
ExpectLastGood("sparse slot Echo array", "GetServerBuildSlots",
    function() return sparseSlots end)
local sparseGranted = H.CloneValue(H.granted)
sparseGranted["Alpha Strike"] = {
    [1]=sparseGranted["Alpha Strike"][1],
    [3]=sparseGranted["Alpha Strike"][2],
}
ExpectLastGood("sparse granted array", "GetGrantedPerks",
    function() return sparseGranted end)
ExpectLastGood("malformed disabled state", "IsTomeEchoDisabled",
    function() return "false" end)
ExpectLastGood("malformed locked count", "GetLockedPerks", function()
    return {{spellId=200104,quality=2,stack="bad"}}
end)
local cyclicLocked = {{spellId=200104,quality=2,stack=1}}
cyclicLocked.loop = cyclicLocked
ExpectLastGood("cyclic locked container", "GetLockedPerks",
    function() return cyclicLocked end)
local deepLocked, cursor = {}, nil
cursor = deepLocked
for _ = 1, 10 do
    cursor.child = {}
    cursor = cursor.child
end
cursor[1] = {spellId=200104,quality=2,stack=1}
ExpectLastGood("over-depth locked container", "GetLockedPerks",
    function() return deepLocked end)

local supportedBefore = F.Snapshot()
local realLockedGetter = H.service.GetLockedPerks
H.service.GetLockedPerks = function()
    return {
        ["Alpha Strike"]={{perkID=200104,amount=1}},
        nested={entries={{echoId=200102,qty=1}}},
    }
end
H.NotifyEchoDataChanged()
H.Advance(0.2, 0.2)
H.service.GetLockedPerks = realLockedGetter
local supportedAfter = F.Snapshot()
assert(supportedAfter.echoReconcile.failures
        == supportedBefore.echoReconcile.failures
    and supportedAfter.echoGenerations.locked
        == supportedBefore.echoGenerations.locked
    and F.Delta(supportedAfter, supportedBefore, "fullSteps") == 0,
    "supported nested locked aliases did not remain equivalent")

print("genuine, missed-signal, and failed-read Echo paths remain one-shot -- OK")

local before = F.Snapshot()
local replyCountBefore = H.freshEchoReplyCount or 0
local identityBefore = {
    slots=H.freshSlotIdentityChanges or 0,
    granted=H.freshGrantedIdentityChanges or 0,
    locked=H.freshLockedIdentityChanges or 0,
    discovered=H.freshDiscoveredIdentityChanges or 0,
    disabled=H.freshDisabledIdentityChanges or 0,
}
local semanticBaseline = {
    slots=H.CloneValue(H.service.GetServerBuildSlots()),
    granted=H.CloneValue(H.granted),
    locked=H.CloneValue(H.locked),
    discovered=H.CloneValue(H.discovered),
    disabled=H.CloneValue(H.disabledEchoes),
    activeSlot=H.service.GetServerActiveSlot(),
}

local function EqualValue(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if not EqualValue(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function Reverse(values)
    for left = 1, math.floor(#values / 2) do
        local right = #values - left + 1
        values[left], values[right] = values[right], values[left]
    end
end

local function ReorderEquivalentReply(ctx)
    for _, slot in pairs(ctx.service.GetServerBuildSlots() or {}) do
        Reverse(slot.echoes or {})
    end
    for _, entries in pairs(ctx.granted or {}) do Reverse(entries) end
    Reverse(ctx.locked or {})
end

H.EnableFreshEchoReplies(true, ReorderEquivalentReply)
local intervals = 20
for _ = 1, intervals do H.Advance(5, 0.2) end
H.EnableFreshEchoReplies(false)
local after = F.Snapshot()

local function Delta(key) return F.Delta(after, before, key) end
local function Mismatch(field)
    return F.FixedDelta(after, before, "signatureMismatches", field)
end
local function Dirty(reason)
    return F.FixedDelta(after, before, "dirtyReasons", reason)
end
local function EchoDelta(key)
    return (after.echoReconcile[key] or 0) - (before.echoReconcile[key] or 0)
end
local function EchoField(field)
    return (after.echoFieldChanges[field] or 0)
        - (before.echoFieldChanges[field] or 0)
end
local function EchoDirty(reason)
    return (after.echoDirtyReasons[reason] or 0)
        - (before.echoDirtyReasons[reason] or 0)
end
local function RuntimeMismatch(field)
    return (after.runtimeMismatchFields[field] or 0)
        - (before.runtimeMismatchFields[field] or 0)
end

local expectedPolls = intervals * 25
local replies = (H.freshEchoReplyCount or 0) - replyCountBefore
assert(Delta("polls") == expectedPolls,
    string.format("direct Poll cadence changed: expected=%d actual=%d",
        expectedPolls, Delta("polls")))
assert(Delta("slotRequests") >= intervals and replies >= intervals
    and Delta("echoNotifications") >= intervals,
    string.format("fresh hooked replies were not exercised: requests=%d replies=%d notifications=%d",
        Delta("slotRequests"), replies, Delta("echoNotifications")))
assert((H.freshSlotIdentityChanges or 0) - identityBefore.slots >= intervals
    and (H.freshGrantedIdentityChanges or 0) - identityBefore.granted >= intervals
    and (H.freshLockedIdentityChanges or 0) - identityBefore.locked >= intervals
    and (H.freshDiscoveredIdentityChanges or 0) - identityBefore.discovered >= intervals
    and (H.freshDisabledIdentityChanges or 0) - identityBefore.disabled >= intervals,
    "fresh replies did not replace every raw table identity")
assert(EqualValue(semanticBaseline.slots, H.service.GetServerBuildSlots())
    and EqualValue(semanticBaseline.granted, H.granted)
    and EqualValue(semanticBaseline.locked, H.locked)
    and EqualValue(semanticBaseline.discovered, H.discovered)
    and EqualValue(semanticBaseline.disabled, H.disabledEchoes)
    and semanticBaseline.activeSlot == H.service.GetServerActiveSlot(),
    "fresh snapshots were not semantically equal across represented Echo state")
assert(Mismatch("slots") == 0 and Mismatch("granted") == 0
    and Mismatch("locked") == 0 and Mismatch("discovery") == 0
    and RuntimeMismatch("slots") == 0 and RuntimeMismatch("granted") == 0
    and RuntimeMismatch("locked") == 0 and RuntimeMismatch("discovery") == 0,
    "equivalent snapshots changed a generation-backed fallback field")
assert(EchoDelta("slotRequests") >= intervals
    and EchoDelta("notifications") >= intervals
    and EchoDelta("equivalentNotifications") >= intervals
    and EchoDelta("scans") <= (EchoDelta("notifications")
        + Delta("fallbackChecks"))
    and EchoField("slots") == 0 and EchoField("granted") == 0
    and EchoField("locked") == 0 and EchoField("discovery") == 0
    and EchoField("activeSlot") == 0
    and EchoDirty("slots") == 0 and EchoDirty("data") == 0,
    string.format("bounded Echo diagnostics drifted: requests=%d notifications=%d equivalent=%d scans=%d cacheHits=%d fields=%d/%d/%d/%d/%d dirty=%d/%d",
        EchoDelta("slotRequests"),EchoDelta("notifications"),
        EchoDelta("equivalentNotifications"),EchoDelta("scans"),
        EchoDelta("cacheHits"),EchoField("slots"),EchoField("granted"),
        EchoField("locked"),EchoField("discovery"),EchoField("activeSlot"),
        EchoDirty("slots"),EchoDirty("data")))

print(string.format(
    "echo refresh correction: intervals=%d polls=%d requests=%d replies=%d notifications=%d equivalent=%d mismatches[slots=%d granted=%d locked=%d discovery=%d] dirty[board=%d slots=%d data=%d autoLock=%d] repairs=%d full=%d fallbackTriggers=%d dirtyTriggers=%d associationRefreshes=%d policy=%d renders=%d uploads=%d mutations=%d lastReason=%s",
    intervals,Delta("polls"),Delta("slotRequests"),replies,
    Delta("echoNotifications"),EchoDelta("equivalentNotifications"),
    Mismatch("slots"),Mismatch("granted"),Mismatch("locked"),
    Mismatch("discovery"),Dirty("board"),Dirty("slots"),Dirty("data"),
    Dirty("autoLock"),Delta("fallbackRepairs"),Delta("fullSteps"),
    Delta("fallbacks"),Delta("dirty"),Delta("associationRefreshes"),
    Delta("policy"),Delta("panelRenders"),Delta("uploads"),
    Delta("characterMutations"),tostring(after.echoReconcile.lastReason)))

assert(Delta("policy") == 0 and Delta("actions") == 0
    and Delta("uploads") == 0 and Delta("characterMutations") == 0,
    "equivalent idle replies escaped into Policy, upload, or character mutation")

assert(Delta("fallbackRepairs") == 0 and Delta("fullSteps") == 0
    and Delta("panelRenders") == 0 and Delta("associationRefreshes") == 0,
    string.format("fresh equivalent Echo replies performed work: repairs=%d full=%d renders=%d associations=%d last=%s",
        Delta("fallbackRepairs"),Delta("fullSteps"),Delta("panelRenders"),
        Delta("associationRefreshes"),tostring(after.echoReconcile.lastReason)))

local adapterSnapshot = Nexus.GameAdapter.EchoReconcileStats()
adapterSnapshot.generations.slots = -1
adapterSnapshot.fieldChanges.slots = -1
adapterSnapshot.dirtyReasons.slots = -1
local adapterDefensive = Nexus.GameAdapter.EchoReconcileStats()
assert(adapterDefensive.generations.slots >= 0
    and adapterDefensive.fieldChanges.slots >= 0
    and adapterDefensive.dirtyReasons.slots >= 0
    and #tostring(adapterDefensive.lastReason or "") <= 96,
    "Echo reconciliation diagnostics are mutable or unbounded")
local runtimeSnapshot = Nexus.RecomputeStats()
runtimeSnapshot.fallbackMismatchFields.slots = -1
runtimeSnapshot.fullStepTriggers.fallbacks = -1
local runtimeDefensive = Nexus.RecomputeStats()
assert(runtimeDefensive.fallbackMismatchFields.slots >= 0
    and runtimeDefensive.fullStepTriggers.fallbacks >= 0,
    "runtime mismatch or trigger diagnostics are not defensive")

print("fresh equivalent Echo replies remain zero-work -- OK")
