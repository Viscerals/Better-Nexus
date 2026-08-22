-- Stage 32.5: LockPerk success is only a submitted request. The existing
-- AutoLock owner must wait for a new authoritative locked projection, expire
-- once, and retain that terminal decision across unrelated work until the
-- represented target changes or the user explicitly retries.
local F = dofile("tests/automation_live_fixture.lua")
local H = F.H
local Adapter = Nexus.GameAdapter
local state = Nexus.Store.State()

local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end

local function Stats()
    return Nexus.RecomputeStats()
end

local function CopyCount(source)
    local count = 0
    for _ in pairs(type(source) == "table" and source or {}) do
        count = count + 1
    end
    return count
end

-- A locked design is an additional exact-role quota even when its family is
-- already represented by the ordinary Wishlist.  The automation-only plan
-- must retain both a sibling tier and an extra copy of the same exact spell;
-- neither may mutate the server Wishlist snapshot used to derive it.
local exactWishlist = {
    name="Stage48 Exact Automation",
    entries={{spellId=910001,quality=0,stacks=2,family=9100}},
    byFamily={[9100]={targetStacks=2,wishedQuality=0,qualityTiers={
        {spellId=910001,q=0,n=2},
    }}},
}
local exactCatalog = {
    rows={
        [910001]={name="Exact Common",quality=0},
        [910002]={name="Exact Rare",quality=2},
    },
    familyOf={[910001]=9100,[910002]=9100},
    familyMembers={[9100]={910001,910002}},
}
local exactKey = assert(Adapter.WishlistKey(exactWishlist.entries),
    "exact automation fixture identity unavailable")
state.lockDesignTargetsBySlot = state.lockDesignTargetsBySlot or {}
state.lockDesignTargetsBySlot[exactKey] = {
    [910001]={version=1,copies=3,
        rows={{spellId=910001,quality=0,stacks=3}}},
    [910002]=true,
}
local augmented = F.runtime.WishlistWithLockTargets(exactWishlist, exactCatalog)
local augmentedTarget = augmented.byFamily[9100]
local commonNeed, rareNeed = 0, 0
for _, tier in ipairs(augmentedTarget and augmentedTarget.qualityTiers or {}) do
    if tier.spellId == 910001 then commonNeed = tonumber(tier.n) or 0 end
    if tier.spellId == 910002 then rareNeed = tonumber(tier.n) or 0 end
end
Check(augmented ~= exactWishlist and augmentedTarget.targetStacks == 6
        and commonNeed == 5 and rareNeed == 1,
    "same-family locked exact quotas were dropped from automation planning")
Check(exactWishlist.byFamily[9100].targetStacks == 2
        and #exactWishlist.byFamily[9100].qualityTiers == 1
        and #exactWishlist.entries == 1,
    "automation augmentation mutated the authoritative server Wishlist")
state.lockDesignTargetsBySlot[exactKey] = {
    [910001]=true,
    [1.5]=true,
}
Check(F.runtime.WishlistWithLockTargets(exactWishlist, exactCatalog)
        == exactWishlist,
    "mixed valid/invalid target map augmented the automation plan")
state.lockDesignTargetsBySlot[exactKey] = {
    [910001]=true,
    [919999]=true,
}
Check(F.runtime.WishlistWithLockTargets(exactWishlist, exactCatalog)
        == exactWishlist,
    "mixed catalog-known/unknown target map augmented the automation plan")
state.lockDesignTargetsBySlot[exactKey] = {
    [910001]={version=1,copies=4,
        rows={{spellId=910001,quality=0,stacks=4}}},
    [910002]={version=1,copies=3,
        rows={{spellId=910002,quality=2,stacks=3}}},
}
Check(F.runtime.WishlistWithLockTargets(exactWishlist, exactCatalog)
        == exactWishlist,
    "seven-copy target map augmented the automation plan")
state.lockDesignTargetsBySlot[exactKey] = nil

local wishlistEchoes = {}
for index = 1, 79 do wishlistEchoes[index] = H.wishlist.echoes[index] end
local wishlistKey = assert(Adapter.WishlistKey(wishlistEchoes),
    "fixture wishlist identity unavailable")
assert(Adapter.SetLoadoutWishlistIdentity(1, "Stage32 Confirmation",
    wishlistEchoes))
state.lockDesignTargetsBySlot = {
    [wishlistKey] = {[200100]=true},
}
state.futureStage32 = {keep=true}

local lockCalls, unlockCalls = {}, {}
H.service.GetMaximumPermanentEchoes = function() return 3 end
H.service.LockPerk = function(spellId)
    lockCalls[#lockCalls + 1] = {spellId=spellId, at=H.now}
    return true
end
H.service.UnlockPerk = function(spellId)
    unlockCalls[#unlockCalls + 1] = {spellId=spellId, at=H.now}
    return true
end

if not Stats().autoEnabled then
    SlashCmdList.NEXUS("auto")
end

-- Capacity is copy-based.  Three exact identities holding two permanent
-- copies each fill all six slots and cannot authorize a seventh copy.
H.service.GetMaximumPermanentEchoes = function() return 6 end
H.locked = {
    {spellId=200104,quality=2,stack=2},
    {spellId=200102,quality=2,stack=2},
    {spellId=200999,quality=1,stack=2},
}
state.lockDesignTargetsBySlot[wishlistKey] = {[200100]=true}
H.NotifyEchoDataChanged()
Check(Nexus.RequestRecompute(), "copy-capacity recompute was refused")
H.Advance(0.4, 0.2)
local fullCopyCapacity = Stats().autoLockCapacity
Check(#lockCalls == 0 and fullCopyCapacity.used == 6
        and fullCopyCapacity.maximum == 6,
    string.format("2+2+2 locked copies were treated as free capacity: calls=%d used=%s maximum=%s synced=%s",
        #lockCalls,tostring(fullCopyCapacity.used),
        tostring(fullCopyCapacity.maximum),tostring(fullCopyCapacity.synced)))

-- Unknown or internally inconsistent counted target tables are foreign
-- persisted contracts.  They must not degrade to a one-copy LockPerk action.
H.locked = {}
H.NotifyEchoDataChanged()
for label, scalar in pairs({
    falseValue=false,stringValue="future",fraction=1.5,
    nan=0/0,infinite=math.huge,negative=-1,zero=0,
}) do
    state.lockDesignTargetsBySlot[wishlistKey] = {[200100]=scalar}
    Check(Nexus.RequestRecompute(), label .. " scalar recompute was refused")
    H.Advance(0.4, 0.2)
    Check(#lockCalls == 0,
        "unsupported scalar target authorized LockPerk: " .. label)
end
state.lockDesignTargetsBySlot[wishlistKey] = {
    [200100]=true,
    [1.5]=true,
    [math.huge]={version=1,copies=1,
        rows={{spellId=200100,quality=3,stacks=1}}},
    [-1]=true,
}
Check(Nexus.RequestRecompute(), "invalid target-key recompute was refused")
H.Advance(0.4, 0.2)
Check(#lockCalls == 0 and #unlockCalls == 0,
    "mixed valid/invalid target map reached LockPerk or UnlockPerk")
state.lockDesignTargetsBySlot[wishlistKey] = {
    [200100]=true,["200100"]=true,
}
Check(Nexus.RequestRecompute(), "aliased target recompute was refused")
H.Advance(0.4, 0.2)
Check(#lockCalls == 0 and #unlockCalls == 0,
    "canonical target aliases reached LockPerk or UnlockPerk")
state.lockDesignTargetsBySlot[wishlistKey] = {
    [200100]=true,[299999]=true,
}
Check(Nexus.RequestRecompute(), "catalog-unknown target recompute was refused")
H.Advance(0.4, 0.2)
Check(#lockCalls == 0 and #unlockCalls == 0,
    "mixed catalog-known/unknown targets reached LockPerk or UnlockPerk")
state.lockDesignTargetsBySlot[wishlistKey] = {[200100]=200100}
Check(Nexus.RequestRecompute(), "self-replacement recompute was refused")
H.Advance(0.4, 0.2)
Check(#lockCalls == 0 and #unlockCalls == 0,
    "self replacement reached LockPerk or UnlockPerk")
state.lockDesignTargetsBySlot[wishlistKey] = {
    [200100]={version=1,copies=4,
        rows={{spellId=200100,quality=3,stacks=4}}},
    [200102]={version=1,copies=3,
        rows={{spellId=200102,quality=2,stacks=3}}},
}
Check(Nexus.RequestRecompute(), "seven-copy target recompute was refused")
H.Advance(0.4, 0.2)
Check(#lockCalls == 0 and #unlockCalls == 0,
    "seven-copy target map reached LockPerk or UnlockPerk")
state.lockDesignTargetsBySlot[wishlistKey] = {
    [200100]={version=2,copies=1,
        rows={{spellId=200100,quality=3,stacks=1}}},
}
Check(Nexus.RequestRecompute(), "future-target recompute was refused")
H.Advance(0.4, 0.2)
state.lockDesignTargetsBySlot[wishlistKey] = {
    [200100]={version=1,copies=2,
        rows={{spellId=200100,quality=3,stacks=1}}},
}
Check(Nexus.RequestRecompute(), "inconsistent-target recompute was refused")
H.Advance(0.4, 0.2)
state.lockDesignTargetsBySlot[wishlistKey] = {
    [200100]={version=1,copies=1,
        rows={{spellId=200102,quality=2,stacks=1}}},
}
Check(Nexus.RequestRecompute(), "wrong-identity target recompute was refused")
H.Advance(0.4, 0.2)
Check(#lockCalls == 0,
    "malformed/future/wrong-identity counted target authorized LockPerk")

-- A counted exact target can pair each retained row with a distinct old lock.
-- At full capacity the runtime sheds one still-locked, non-target pair per
-- authoritative revision until the complete deficit fits, then locks X.
local lifecycleBeforeScenario = Stats().autoLockLifecycle
local originalGranted = H.granted
H.granted = {Target={
    {spellId=200100,quality=3},{spellId=200100,quality=3},
    {spellId=200100,quality=3},
}}
state.autoLockAttempts = nil
state.lockDesignTargetsBySlot[wishlistKey] = {
    [200100]={version=1,copies=3,replaces=200104,rows={
        {spellId=200100,quality=3,stacks=1,replaces=200104},
        {spellId=200100,quality=3,stacks=1,replaces=200102},
        {spellId=200100,quality=3,stacks=1,replaces=200999},
    }},
}
H.service.GetMaximumPermanentEchoes = function() return 3 end
H.locked = {
    {spellId=200104,quality=2,stack=1},
    {spellId=200102,quality=2,stack=1},
    {spellId=200999,quality=1,stack=1},
}
H.NotifyEchoDataChanged()
Check(Nexus.RequestRecompute(), "multi-replacement recompute was refused")
H.Advance(0.4, 0.2)
Check(#unlockCalls == 1 and unlockCalls[1].spellId == 200104,
    "first counted replacement pair did not unlock")
H.Advance(3.2, 0.2)
H.locked = {
    {spellId=200102,quality=2,stack=1},
    {spellId=200999,quality=1,stack=1},
}
H.NotifyEchoDataChanged()
H.Advance(0.4, 0.2)
if #unlockCalls ~= 2 and Nexus.GetDiagnosticPageText then
    print(Nexus.GetDiagnosticPageText("autolock"))
end
Check(#unlockCalls == 2 and unlockCalls[2].spellId == 200102,
    "second counted replacement pair did not unlock: calls="
        .. tostring(#unlockCalls) .. " last="
        .. tostring(unlockCalls[#unlockCalls] and unlockCalls[#unlockCalls].spellId))
H.Advance(3.2, 0.2)
H.locked = {{spellId=200999,quality=1,stack=1}}
H.NotifyEchoDataChanged()
H.Advance(0.4, 0.2)
Check(#unlockCalls == 3 and unlockCalls[3].spellId == 200999,
    "third counted replacement pair did not unlock: calls="
        .. tostring(#unlockCalls) .. " last="
        .. tostring(unlockCalls[#unlockCalls] and unlockCalls[#unlockCalls].spellId))
H.Advance(3.2, 0.2)
H.locked = {}
H.NotifyEchoDataChanged()
H.Advance(0.4, 0.2)
Check(#lockCalls == 1 and lockCalls[1].spellId == 200100,
    "counted target did not lock after its full deficit fit")

-- A replacement that remains a separate desired target is never shed; the
-- runtime skips it and uses the next explicit pair.
lockCalls, unlockCalls = {}, {}
state.autoLockAttempts = nil
H.Advance(3.2, 0.2)
state.lockDesignTargetsBySlot[wishlistKey] = {
    [200100]={version=1,copies=2,replaces=200104,rows={
        {spellId=200100,quality=3,stacks=1,replaces=200104},
        {spellId=200100,quality=3,stacks=1,replaces=200102},
    }},
    [200104]=true,
}
H.locked = {
    {spellId=200104,quality=2,stack=1},
    {spellId=200102,quality=2,stack=1},
    {spellId=200999,quality=1,stack=1},
}
H.NotifyEchoDataChanged()
Check(Nexus.RequestRecompute(), "desired-sibling recompute was refused")
H.Advance(0.4, 0.2)
Check(#unlockCalls == 1 and unlockCalls[1].spellId == 200102,
    "counted replacement unlocked a separately desired sibling")
H.Advance(3.2, 0.2)
local lifecycleAfterScenario = Stats().autoLockLifecycle
local scenarioLifecycle = {}
for key, value in pairs(lifecycleAfterScenario) do
    scenarioLifecycle[key] = value - (lifecycleBeforeScenario[key] or 0)
end

-- Restore the original one-of-three fixture for the lifecycle assertions.
H.granted = originalGranted
lockCalls, unlockCalls = {}, {}
state.autoLockAttempts = nil
state.lockDesignTargetsBySlot[wishlistKey] = {[200100]=true}
H.service.GetMaximumPermanentEchoes = function() return 3 end
H.locked = {{spellId=200104,quality=2,stack=1}}
H.NotifyEchoDataChanged()

-- Enable the existing master switch and rebuild the immutable target context.
if not Stats().autoEnabled then
    SlashCmdList.NEXUS("auto")
end
Check(Nexus.RequestRecompute(), "initial AutoLock recompute was refused")
H.Advance(0.4, 0.2)
if #lockCalls ~= 1 and Nexus.GetDiagnosticPageText then
    print(Nexus.GetDiagnosticPageText("autolock"))
end
Check(#lockCalls == 1 and lockCalls[1].spellId == 200100,
    "initial target did not submit exactly one LockPerk")
local initialCapacity = Stats().autoLockCapacity
Check(initialCapacity.used == 1 and initialCapacity.maximum == 3
        and initialCapacity.known and initialCapacity.source == "service"
        and initialCapacity.synced,
    "runtime did not characterize authoritative locked capacity as 1/3")

-- This is the test.13 expected red. The adapter returns true but the server
-- mirror remains unchanged. Forced recomputes after the old ten-second
-- cooldown must not manufacture confirmation or submit the same identity.
for _ = 1, 3 do
    H.Advance(10.1, 0.2)
    Check(Nexus.RequestRecompute(), "unrelated recompute was refused")
    H.Advance(0.2, 0.2)
end
Check(#lockCalls == 1,
    "adapter ok without authoritative confirmation resubmitted LockPerk: "
        .. tostring(#lockCalls))

local first = Stats()
Check(type(first.autoLockLifecycle) == "table"
        and first.autoLockLifecycle.prepared
            - (scenarioLifecycle.prepared or 0) == 1
        and first.autoLockLifecycle.submitted
            - (scenarioLifecycle.submitted or 0) == 1
        and first.autoLockLifecycle.awaitingConfirmation
            - (scenarioLifecycle.awaitingConfirmation or 0) == 1
        and first.autoLockLifecycle.expired
            - (scenarioLifecycle.expired or 0) == 1,
    "prepared/submitted/awaiting/expired lifecycle totals drifted")
Check(first.lastAutoLockLifecycle.state == "expired"
        and first.lastAutoLockLifecycle.reason == "confirmation_timeout"
        and first.lastAutoLockLifecycle.spellId == 200100,
    "unconfirmed target did not retain its structured expiry")
first.autoLockLifecycle.expired = 999
first.lastAutoLockLifecycle.state = "mutated"
first.autoLockCapacity.maximum = 999
Check(Stats().autoLockLifecycle.expired
        - (scenarioLifecycle.expired or 0) == 1
        and Stats().lastAutoLockLifecycle.state == "expired"
        and Stats().autoLockCapacity.maximum == 3,
    "AutoLock lifecycle diagnostics leaked mutable internal state")
Check(type(state.autoLockAttempts) == "table"
        and CopyCount(state.autoLockAttempts.records) == 1
        and state.futureStage32.keep,
    "expiry was not retained in per-character state or changed unknown fields")

-- Replace the live bucket with a scalar-equivalent deserialized table. This
-- is the /reload boundary: runtime locals are not allowed to restart lifetime;
-- the Store-owned record is re-read on the next pump.
local persistedKey, persistedRecord = next(state.autoLockAttempts.records)
local reloadedRecord = {}
for key, value in pairs(persistedRecord) do reloadedRecord[key] = value end
reloadedRecord.lockedRevision = 9
reloadedRecord.identity = reloadedRecord.baseKey
    .. "|locked=number:1:9|state=string:8:200104x1"
state.autoLockAttempts = {
    version=1,records={[persistedKey]=reloadedRecord},future={keep=true},
}

local callsAtExpiry = #lockCalls
for _ = 1, 20 do Check(Nexus.RequestRecompute(), "post-expiry recompute refused") end
H.Advance(5.2, 0.2)
Check(#lockCalls == callsAtExpiry
        and Stats().lastAutoLockLifecycle.state == "expired"
        and state.autoLockAttempts.future.keep,
    "post-expiry pumps retried or reset the terminal identity")

-- Explicit user retry authorizes one new bounded lifetime. Adapter success is
-- still not confirmation until the locked mirror changes.
Check(type(Nexus.RetryAutoLock) == "function" and Nexus.RetryAutoLock(),
    "explicit AutoLock retry was unavailable")
H.Advance(0.4, 0.2)
Check(#lockCalls == callsAtExpiry + 1
        and Stats().lastAutoLockLifecycle.state == "awaiting-confirmation",
    "explicit retry did not submit exactly one fresh attempt")

H.locked = {
    {spellId=200104,quality=2,stack=1},
    {spellId=200100,quality=3,stack=1},
}
H.NotifyEchoDataChanged()
H.Advance(0.4, 0.2)
local confirmed = Stats()
Check(#lockCalls == callsAtExpiry + 1
        and confirmed.lastAutoLockLifecycle.state == "confirmed"
        and confirmed.autoLockLifecycle.confirmed
            - (scenarioLifecycle.confirmed or 0) == 1,
    "authoritative locked evidence did not confirm exactly once")

-- A new target safely supersedes the fulfilled identity. A refusal is
-- terminal and retained; it does not become a successful confirmation.
state.lockDesignTargetsBySlot[wishlistKey] = {[200102]=true}
H.service.LockPerk = function(spellId)
    lockCalls[#lockCalls + 1] = {spellId=spellId, at=H.now}
    return false
end
Check(Nexus.RequestRecompute(), "replacement target recompute was refused")
H.Advance(0.4, 0.2)
local callsBeforeRevocation = #lockCalls
SlashCmdList.NEXUS("auto")
H.Advance(3.2, 0.2)
Check(#lockCalls == callsBeforeRevocation
        and Stats().lastAutoLockLifecycle.state == "prepared",
    "revoked master authorization reached the spaced mutation boundary")
SlashCmdList.NEXUS("auto")
Check(Nexus.RequestRecompute(), "reauthorized target recompute was refused")
H.Advance(0.4, 0.2)
local rejected = Stats()
Check(rejected.lastAutoLockLifecycle.state == "rejected"
        and rejected.lastAutoLockLifecycle.reason == "refused"
        and rejected.autoLockLifecycle.rejected
            - (scenarioLifecycle.rejected or 0) == 1
        and rejected.autoLockLifecycle.superseded
            - (scenarioLifecycle.superseded or 0) >= 1,
    string.format("target change did not supersede then retain adapter rejection: state=%s reason=%s rejected=%s superseded=%s calls=%s",
        tostring(rejected.lastAutoLockLifecycle.state),
        tostring(rejected.lastAutoLockLifecycle.reason),
        tostring(rejected.autoLockLifecycle.rejected),
        tostring(rejected.autoLockLifecycle.superseded),tostring(#lockCalls)))
local callsAtReject = #lockCalls
H.Advance(15, 0.2)
for _ = 1, 5 do Check(Nexus.RequestRecompute(), "rejected recompute refused") end
H.Advance(0.4, 0.2)
Check(#lockCalls == callsAtReject,
    "rejected identity retried without evidence or user authorization")

-- A late authoritative mirror still confirms the desired state after a
-- terminal refusal; it never needs another adapter call to become truth.
H.locked = {
    {spellId=200104,quality=2,stack=1},
    {spellId=200100,quality=3,stack=1},
    {spellId=200102,quality=2,stack=1},
}
H.NotifyEchoDataChanged()
H.Advance(0.4, 0.2)
Check(#lockCalls == callsAtReject
        and Stats().lastAutoLockLifecycle.state == "confirmed"
        and Stats().autoLockLifecycle.confirmed
            - (scenarioLifecycle.confirmed or 0) == 2,
    string.format("late authoritative locked evidence did not confirm without resubmission: calls=%s state=%s confirmed=%s",
        tostring(#lockCalls),tostring(Stats().lastAutoLockLifecycle.state),
        tostring(Stats().autoLockLifecycle.confirmed)))

-- Pause the master switch while representing a manual unlock. This isolates
-- the following replacement-pair identity from the unpaired record.
SlashCmdList.NEXUS("auto")
H.locked = {
    {spellId=200104,quality=2,stack=1},
    {spellId=200100,quality=3,stack=1},
}
H.NotifyEchoDataChanged()
H.Advance(0.4, 0.2)

-- Replacement-pairing changes form a new identity. One accepted submission
-- then remains pending until a semantic locked-state revision arrives.
state.lockDesignTargetsBySlot[wishlistKey] = {[200102]=200104}
H.service.LockPerk = function(spellId)
    lockCalls[#lockCalls + 1] = {spellId=spellId, at=H.now}
    return true
end
SlashCmdList.NEXUS("auto")
Check(Nexus.RequestRecompute(), "pairing-change recompute was refused")
H.Advance(0.4, 0.2)
local paired = Stats()
Check(#lockCalls == callsAtReject + 1
        and paired.lastAutoLockLifecycle.state == "awaiting-confirmation"
        and paired.lastAutoLockLifecycle.replaces == 200104,
    "replacement-pair identity did not supersede and submit once")

-- An authoritative revision that does not contain the target supersedes the
-- old pending identity. Full capacity plus an unsafe destructive context must
-- produce no new LockPerk or UnlockPerk call.
H.locked = {
    {spellId=200104,quality=2,stack=1},
    {spellId=200100,quality=3,stack=1},
    {spellId=200999,quality=1,stack=1},
}
H.NotifyEchoDataChanged()
H.Advance(0.4, 0.2)
local revised = Stats()
Check(#lockCalls == callsAtReject + 1 and #unlockCalls == 0
        and revised.autoLockLifecycle.superseded
            - (scenarioLifecycle.superseded or 0) >= 2,
    "locked-state revision bypassed capacity or destructive-unlock safety")

-- Capacity is server evidence, not the editor's six design cells. This live
-- runtime fixture intentionally reports one of three before any action.
local maximum, source = Adapter.MaxPermanentEchoes()
Check(maximum == 3 and source == "service",
    "runtime capacity did not retain authoritative 1/3 service evidence")

-- Incompatible persisted state must fail closed and remain byte-for-byte owned
-- by its unknown/future writer rather than being normalized into an action.
local validAttempts = state.autoLockAttempts
state.autoLockAttempts = {version=2,records={},futureOwner={keep=true}}
local callsBeforeFuture = #lockCalls
Check(Nexus.RequestRecompute(), "future-state recompute was refused")
H.Advance(0.4, 0.2)
Check(#lockCalls == callsBeforeFuture and #unlockCalls == 0
        and state.autoLockAttempts.version == 2
        and state.autoLockAttempts.futureOwner.keep,
    "future AutoLock state was overwritten or reached a mutation")

-- A malformed current-schema record is also foreign state. Fail closed before
-- pruning or normalizing any record, even when its target is no longer active.
local malformedKeyRecord = {}
for key, value in pairs(reloadedRecord) do malformedKeyRecord[key] = value end
state.autoLockAttempts = {version=1,records={
    ["foreign-record-key"]=malformedKeyRecord,
},futureOwner={keep=true}}
local callsBeforeMalformed = #lockCalls
Check(Nexus.RequestRecompute(), "malformed-key recompute was refused")
H.Advance(0.4, 0.2)
Check(#lockCalls == callsBeforeMalformed and #unlockCalls == 0
        and state.autoLockAttempts.records["foreign-record-key"]
            == malformedKeyRecord
        and state.autoLockAttempts.futureOwner.keep,
    "malformed AutoLock record key was normalized or deleted")

local malformedTimeRecord = {}
for key, value in pairs(reloadedRecord) do malformedTimeRecord[key] = value end
malformedTimeRecord.preparedAt = "not-a-time"
local malformedTimeKey = malformedTimeRecord.baseKey
state.autoLockAttempts = {version=1,records={
    [malformedTimeKey]=malformedTimeRecord,
},futureOwner={keep=true}}
Check(Nexus.RequestRecompute(), "malformed-time recompute was refused")
H.Advance(0.4, 0.2)
Check(#lockCalls == callsBeforeMalformed and #unlockCalls == 0
        and state.autoLockAttempts.records[malformedTimeKey]
            == malformedTimeRecord
        and malformedTimeRecord.preparedAt == "not-a-time"
        and state.autoLockAttempts.futureOwner.keep,
    "malformed AutoLock timestamps were normalized or deleted")

local malformedIdentityRecord = {}
for key, value in pairs(reloadedRecord) do
    malformedIdentityRecord[key] = value
end
malformedIdentityRecord.identity = "foreign-identity"
local malformedIdentityKey = malformedIdentityRecord.baseKey
state.autoLockAttempts = {version=1,records={
    [malformedIdentityKey]=malformedIdentityRecord,
},futureOwner={keep=true}}
Check(Nexus.RequestRecompute(), "malformed-identity recompute was refused")
H.Advance(0.4, 0.2)
Check(#lockCalls == callsBeforeMalformed and #unlockCalls == 0
        and state.autoLockAttempts.records[malformedIdentityKey]
            == malformedIdentityRecord
        and malformedIdentityRecord.identity == "foreign-identity"
        and state.autoLockAttempts.futureOwner.keep,
    "malformed AutoLock identity was normalized or deleted")

local malformedDescriptorRecord = {}
for key, value in pairs(reloadedRecord) do
    malformedDescriptorRecord[key] = value
end
malformedDescriptorRecord.wishlistKey = "foreign-wishlist"
local malformedDescriptorKey = malformedDescriptorRecord.baseKey
state.autoLockAttempts = {version=1,records={
    [malformedDescriptorKey]=malformedDescriptorRecord,
},futureOwner={keep=true}}
Check(Nexus.RequestRecompute(), "malformed-descriptor recompute was refused")
H.Advance(0.4, 0.2)
Check(#lockCalls == callsBeforeMalformed and #unlockCalls == 0
        and state.autoLockAttempts.records[malformedDescriptorKey]
            == malformedDescriptorRecord
        and malformedDescriptorRecord.wishlistKey == "foreign-wishlist"
        and state.autoLockAttempts.futureOwner.keep,
    "malformed AutoLock descriptor was normalized or deleted")

local malformedDeadlineRecord = {}
for key, value in pairs(reloadedRecord) do
    malformedDeadlineRecord[key] = value
end
malformedDeadlineRecord.nextAttemptAt = malformedDeadlineRecord.expiresAt + 1
local malformedDeadlineKey = malformedDeadlineRecord.baseKey
state.autoLockAttempts = {version=1,records={
    [malformedDeadlineKey]=malformedDeadlineRecord,
},futureOwner={keep=true}}
Check(Nexus.RequestRecompute(), "malformed-deadline recompute was refused")
H.Advance(0.4, 0.2)
Check(#lockCalls == callsBeforeMalformed and #unlockCalls == 0
        and state.autoLockAttempts.records[malformedDeadlineKey]
            == malformedDeadlineRecord
        and malformedDeadlineRecord.nextAttemptAt
            == malformedDeadlineRecord.expiresAt + 1
        and state.autoLockAttempts.futureOwner.keep,
    "malformed AutoLock retry deadline was normalized or deleted")
state.autoLockAttempts = validAttempts

local final = Stats()
local boundedLifecycle = {}
for key, value in pairs(final.autoLockLifecycle) do
    boundedLifecycle[key] = value - (scenarioLifecycle[key] or 0)
end
Check(boundedLifecycle.prepared == 4
        and boundedLifecycle.submitted == 3
        and boundedLifecycle.awaitingConfirmation == 3
        and boundedLifecycle.confirmed == 2
        and boundedLifecycle.rejected == 1
        and boundedLifecycle.expired == 1
        and boundedLifecycle.superseded == 4
        and boundedLifecycle.spacingRetries == 1
        and boundedLifecycle.explicitRetries == 1
        and boundedLifecycle.postExpiryBlocked == 3,
    "final AutoLock lifecycle totals were not exact and bounded")
print(string.format(
    "stage32 AutoLock confirmation: checks=%d calls=%d prepared=%d submitted=%d awaiting=%d confirmed=%d rejected=%d expired=%d superseded=%d postExpiry=%d capacity=1/%d",
    checks,#lockCalls,boundedLifecycle.prepared,
    boundedLifecycle.submitted,
    boundedLifecycle.awaitingConfirmation,
    boundedLifecycle.confirmed,boundedLifecycle.rejected,
    boundedLifecycle.expired,boundedLifecycle.superseded,
    boundedLifecycle.postExpiryBlocked,maximum))
print("bounded AutoLock submission and authoritative confirmation -- OK")
