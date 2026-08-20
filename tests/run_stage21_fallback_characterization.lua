-- Stage 21.1: an unchanged 85-entry association and retained relay must not
-- repeatedly force full fallback repair.
local F = dofile("tests/automation_live_fixture.lua")
local H = F.H
local A, state = Nexus.GameAdapter, Nexus.Store.State()

local designed = {}
for index = 1, 79 do
    designed[#designed + 1] = {
        spellId=260000 + index,quality=index % 4,stacks=1,locked=false,
    }
end
for index = 1, 6 do
    designed[#designed + 1] = {
        spellId=270000 + index,quality=3,stacks=1,locked=true,
    }
end
local key = assert(A.WishlistKey(designed))

H.Perks.serverBuildSlots[102] = {
    slot=102,name="Fallback Designed Target",verified=false,echoes=designed,
}
state.loadoutWishlists = {}
for slot = 1, 3 do
    state.loadoutWishlists[slot] = {
        slot=102,name="Fallback Designed Target",key=key,
    }
end
state.pendingRelay = {
    sourceSlot=1,targetSlot=3,wishlistSlot=102,wishlistKey=key,
    futureRelayField={keep=true},
}
local relayRef = state.pendingRelay

-- Consume the one source-arrival/association transition before measuring the
-- unchanged fallback window.
assert(Nexus.RequestRecompute())
H.Advance(0.4, 0.2)
local before = F.Snapshot()
local intervals = 20
for _ = 1, intervals do H.Advance(5, 0.2) end
local after = F.Snapshot()

local function Delta(key) return F.Delta(after, before, key) end
local function Fixed(group, key) return F.FixedDelta(after, before, group, key) end
local mismatchSummary = {}
for _, field in ipairs({
    "service","level","slots","activeSlot","granted","locked",
    "discovery","tomeSafety","state","settings","associations",
    "association","firstRun","catalogRevision","signature",
}) do
    local count = Fixed("runtimeMismatchFields", field)
    if count ~= 0 then
        mismatchSummary[#mismatchSummary + 1] = field .. "=" .. tostring(count)
    end
end
assert(Delta("polls") == intervals * 25,
    "fallback characterization changed the direct 0.2-second Poll cadence")
assert(Delta("fallbackChecks") == intervals
    and Delta("fallbackRepairs") == 0
    and Delta("fullSteps") == 0
    and Delta("staticProbes") == 0,
    string.format("unchanged 85-entry association repeated repair: checks=%d repairs=%d full=%d probes=%d last=%s mismatches=%s",
        Delta("fallbackChecks"),Delta("fallbackRepairs"),Delta("fullSteps"),
        Delta("staticProbes"),tostring(after.lastReason),
        table.concat(mismatchSummary,",")))
for _, field in ipairs({
    "service","level","slots","activeSlot","granted","locked",
    "discovery","tomeSafety","state","settings","associations",
    "association","firstRun","catalogRevision","signature",
}) do
    assert(Fixed("runtimeMismatchFields", field) == 0,
        "unchanged association produced fallback mismatch: " .. field)
end
assert(Delta("associationRefreshes") == 0 and Delta("uploads") == 0
    and Delta("characterMutations") == 0 and Delta("policy") == 0,
    "unchanged association escaped into association/upload/character/Policy work")
assert(state.pendingRelay == relayRef and relayRef.wishlistKey == key
    and relayRef.futureRelayField.keep,
    "unchanged fallback discarded or rewrote pending relay")

print(string.format(
    "Stage 21 fallback characterization: intervals=%d polls=%d checks=%d repairs=%d full=%d probes=%d associationRefreshes=%d uploads=%d mutations=%d mismatchFields=0",
    intervals,Delta("polls"),Delta("fallbackChecks"),
    Delta("fallbackRepairs"),Delta("fullSteps"),Delta("staticProbes"),
    Delta("associationRefreshes"),Delta("uploads"),
    Delta("characterMutations")))
