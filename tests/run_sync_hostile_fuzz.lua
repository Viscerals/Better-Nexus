-- Deterministic hostile-input coverage. This is an independent Nexus test:
-- fixed LCG input generation, bounded-state assertions, and no source shared
-- with the unlicensed architectural reference archive.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")

local Sync = Nexus.Sync
local clock = 4000
GetTime = function() return clock end
UnitName = function() return "Defender" end
time = function() return 50000 end

local protectedBuild = {
    id="protected", title="Protected", author="Defender",
    ownerKey="defender@ebonhold", class="MAGE", isMine=true,
    postedAt=1, lastModified=1,
    echoes={{spellId=200100, quality=3, stacks=1}},
}
NexusDB = {
    communityBuilds={ protected=protectedBuild },
    syncTombstones={},
    settings={ hostileFuzzSentinel="unchanged" },
    characterState={ selectedSlot=3, ownedGeneration=77 },
}
Sync.Init(Nexus.Codec, {})

local seed = 24681357
local function Next()
    seed = (seed * 48271) % 2147483647
    return seed
end

local function SafeHandle(payload, actualSender)
    local ok, err = pcall(Sync.HandleIncoming, payload, actualSender)
    assert(ok, "hostile payload raised an error: " .. tostring(err))
end

local hostileNames = {}
for i = 1, 4000 do
    local n = Next()
    local sender = "Fuzzer" .. tostring((n % 50) + 1)
    hostileNames[sender] = true
    local case = n % 12
    local payload
    local actual = sender
    if case == 0 then
        payload = string.rep("X", 256 + (n % 512))
    elseif case == 1 then
        payload = "UNKNOWN|" .. sender .. "|" .. tostring(n)
    elseif case == 2 then
        payload = "WLRQ|Forged|0|0|mismatch-" .. tostring(n)
    elseif case == 3 then
        payload = "WLRB|" .. sender .. "|" .. string.rep("i", 140)
            .. "|1|1/2|AAAA"
    elseif case == 4 then
        payload = "WLRB|" .. sender .. "|bad-" .. tostring(n)
            .. "|1|0/1|AAAA"
    elseif case == 5 then
        payload = "WLD2|" .. sender .. "|bad-" .. tostring(n)
            .. "|1/1000|AAAA"
    elseif case == 6 then
        payload = "WLRD|" .. sender .. "|unknown-" .. tostring(n)
            .. "|-1|" .. sender
    elseif case == 7 then
        payload = "WLNP|" .. sender .. "|" .. string.rep("9", 80)
    elseif case == 8 then
        payload = "WLRQ|" .. sender .. "|0|0|" .. string.rep("r", 140)
    elseif case == 9 then
        -- Valid geometry but incomplete/out of order: bounded transfer state
        -- may be retained, but it must not prove that this is a Nexus peer.
        payload = "WLRB|" .. sender .. "|partial-" .. tostring(n)
            .. "|1|2/3|AAAA"
    elseif case == 10 then
        payload = "WLD2|" .. sender .. "|partial-" .. tostring(n)
            .. "|2/3|AAAA"
    else
        payload = "WLRQ|" .. sender .. "|not a hash|0|bad-" .. tostring(n)
    end
    if case == 2 then actual = sender end
    SafeHandle(payload, actual)
end

-- Deterministic duplicate/out-of-order and immutable-metadata conflicts.
SafeHandle("WLRB|ConflictPeer|same|1|2/3|AAAA", "ConflictPeer")
SafeHandle("WLRB|ConflictPeer|same|1|2/3|AAAA", "ConflictPeer")
SafeHandle("WLRB|ConflictPeer|same|2|1/3|BBBB", "ConflictPeer")
SafeHandle("WLD2|ConflictDps|same|2/3|AAAA", "ConflictDps")
SafeHandle("WLD2|ConflictDps|same|1/4|BBBB", "ConflictDps")
assert(not Sync.IsKnownPeer("ConflictPeer")
    and not Sync.IsKnownPeer("ConflictDps"),
    "incomplete/conflicting transfers created false peers")

local state = Sync.WorkState()
assert(state.buildInflight + state.dpsInflight <= state.maxGlobal,
    "hostile fuzz escaped the global inflight cap")
assert(state.buildBytes + state.dpsBytes
        <= state.maxGlobal * state.maxEncodedBytes,
    "hostile fuzz escaped the cumulative transfer-byte cap")
assert(state.pendingResponses <= state.maxPendingResponses
    and state.pendingLoadouts <= state.maxPendingLoadouts,
    "hostile fuzz escaped pending-response bounds")
for sender in pairs(hostileNames) do
    assert(not Sync.IsKnownPeer(sender),
        "rejected/incomplete hostile traffic created a false Nexus peer")
end
SafeHandle("WLNP|RealmTwin-One|1.19.4", "RealmTwin-Two")
assert(not Sync.IsKnownPeer("RealmTwin"),
    "realm-qualified sender mismatch created a false peer")

-- Accepted protocol traffic still creates a peer after validation.
SafeHandle("WLNP|KnownPeer|1.19.4", "KnownPeer")
assert(Sync.IsKnownPeer("KnownPeer"),
    "accepted presence did not create a Nexus peer")

-- Exercise pending/control and bulk overflow boundaries with accepted local
-- work. Both queues remain bounded and report rejected-newest backpressure.
for i = 1, state.maxPendingResponses + 32 do
    SafeHandle("WLRQ|QueuePeer" .. i .. "|0|0|req-" .. i,
        "QueuePeer" .. i)
end
Sync.OnUpdate(10)
state = Sync.WorkState()
assert(state.pendingResponses <= state.maxPendingResponses,
    "request flood exceeded the pending-response cap")
assert(state.control <= state.maxControlQueue,
    "request flood exceeded the control-queue cap")

for i = 1, state.maxOutboundQueue + 32 do
    Sync.BroadcastDps("fuzz-queue-" .. i, "Defender", 1000 + i, 80, "dummy")
end
state = Sync.WorkState()
assert(state.sending <= state.maxOutboundQueue,
    "bulk queue exceeded its explicit cap")
assert((Sync.Stats().queueOverflowRejected or 0) > 0,
    "queue pressure did not report rejected-newest overflow")

-- Abandoned chunk and pending-response state expires deterministically.
clock = clock + 61
Sync.OnUpdate(0)
state = Sync.WorkState()
assert(state.buildInflight == 0 and state.dpsInflight == 0,
    "abandoned hostile transfers survived their TTL")
assert(state.pendingResponses == 0 and state.pendingLoadouts == 0,
    "abandoned hostile response state survived its TTL")

-- Replaying an identical duplicate chunk never refreshes idle activity and
-- cannot retain an incomplete transfer beyond the absolute lifetime cap.
Sync.Init(Nexus.Codec, {})
SafeHandle("WLRB|DripPeer|drip|1|1/2|AAAA", "DripPeer")
for _ = 1, 16 do
    clock = clock + 20
    SafeHandle("WLRB|DripPeer|drip|1|1/2|AAAA", "DripPeer")
    Sync.OnUpdate(0)
end
assert(Sync.WorkState().buildInflight == 0,
    "duplicate drip traffic retained an incomplete transfer indefinitely")

-- Protected player/configuration state must remain byte-for-byte equivalent
-- at the fields hostile traffic could otherwise target.
assert(NexusDB.communityBuilds.protected == protectedBuild
    and NexusDB.communityBuilds.protected.title == "Protected"
    and NexusDB.communityBuilds.protected.isMine == true,
    "hostile fuzz mutated the protected local build")
assert(NexusDB.settings.hostileFuzzSentinel == "unchanged"
    and NexusDB.characterState.selectedSlot == 3
    and NexusDB.characterState.ownedGeneration == 77,
    "hostile fuzz mutated protected character or automation state")

print("4000 deterministic hostile Sync payloads remained bounded and fail-closed -- OK")
