-- Hostile Sync/DPS input and CommunityBuild integrity regressions.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/Sync.lua")
dofile("core/DpsCapture.lua")
dofile("ui/CommunityBuilds.lua")

local Codec, Sync, DPS = Nexus.Codec, Nexus.Sync, Nexus.DpsCapture
time = function() return 2000000000 end
NexusDB = { communityBuilds={}, syncTombstones={}, dpsCapture={} }

local function ResetSync()
    NexusDB.communityBuilds = {}
    NexusDB.syncTombstones = {}
    Sync.Init(Codec, {})
end

local function BuildPacket(sender, build, stamp)
    local payload = {
        id=build.id, t=build.title, a=build.author, o=build.ownerKey,
        c=build.class, m=stamp or build.lastModified, d=build.description,
        e={{build.echoes[1].spellId, build.echoes[1].quality or 0,
            build.echoes[1].stacks or 1}},
    }
    local encoded = Codec.Base64Encode(Codec.JSONEncode(payload))
    return table.concat({"WLRB", sender, build.id, tostring(stamp or 1),
        "1/1", encoded}, "|")
end

-- Invalid indices/totals never allocate.
ResetSync()
for _, spec in ipairs({"0/1", "2/1", "1/0", "1/1000", "999999/999999"}) do
    Sync.HandleIncoming("WLRB|Flood|bad|1|" .. spec .. "|A", "Flood")
    Sync.HandleIncoming("WLD2|Flood|bad|" .. spec .. "|A", "Flood")
end
local state = Sync.WorkState()
assert(state.buildInflight == 0 and state.dpsInflight == 0,
    "invalid chunk geometry allocated state")

-- Duplicate data is free; conflicting data drops the transfer. Per-sender
-- and global caps include both build and DPS transfers.
for i = 1, 5 do
    Sync.HandleIncoming("WLRB|Flood|b" .. i .. "|1|1/2|A", "Flood")
end
state = Sync.WorkState()
assert(state.buildInflight == 4, "per-sender build cap was not enforced")
local beforeBytes = state.buildBytes
Sync.HandleIncoming("WLRB|Flood|b1|1|1/2|A", "Flood")
assert(Sync.WorkState().buildBytes == beforeBytes,
    "duplicate build chunk double-counted bytes")
Sync.HandleIncoming("WLRB|Flood|b1|1|1/2|B", "Flood")
assert(Sync.WorkState().buildInflight == 3,
    "conflicting duplicate did not discard the build transfer")
Sync.HandleIncoming("WLD2|Flood|d1|1/2|A", "Flood")
assert(Sync.WorkState().dpsInflight == 1,
    "combined per-sender allowance should admit the fourth transfer")
Sync.HandleIncoming("WLD2|Flood|d2|1/2|A", "Flood")
assert(Sync.WorkState().dpsInflight == 1,
    "combined per-sender cap did not reject the fifth transfer")

ResetSync()
for senderIndex = 1, 6 do
    local sender = "Peer" .. senderIndex
    for transfer = 1, 4 do
        local id = sender .. "-" .. transfer
        local code = (senderIndex % 2 == 0) and "WLD2" or "WLRB"
        local msg
        if code == "WLRB" then
            msg = "WLRB|" .. sender .. "|" .. id .. "|1|1/2|A"
        else
            msg = "WLD2|" .. sender .. "|" .. id .. "|1/2|A"
        end
        Sync.HandleIncoming(msg, sender)
    end
end
state = Sync.WorkState()
assert(state.buildInflight + state.dpsInflight == state.maxGlobal,
    "combined global transfer cap was not reached deterministically")
Sync.HandleIncoming("WLRB|Overflow|extra|1|1/2|A", "Overflow")
state = Sync.WorkState()
assert(state.buildInflight + state.dpsInflight == state.maxGlobal,
    "global transfer cap admitted an extra transfer")

-- Every incomplete type expires on the same bounded TTL.
H.now = H.now + 31
Sync.OnUpdate(0)
state = Sync.WorkState()
assert(state.buildInflight == 0 and state.dpsInflight == 0,
    "expired build/DPS transfers were retained")

-- Cumulative encoded data is bounded before concatenation.
ResetSync()
local chunk = string.rep("A", 255)
local total = 172
for i = 1, total do
    Sync.HandleIncoming("WLRB|Bulk|large|1|" .. i .. "/" .. total
        .. "|" .. chunk, "Bulk")
end
assert(Sync.WorkState().buildInflight == 0,
    "oversized cumulative build payload remained allocated")

-- Transport identity controls full-build authority. Relayed information may
-- be stored only as unverified and cannot overwrite verified/local state.
ResetSync()
local alice = {
    id="alice-build", title="Alice Build", author="Alice",
    ownerKey="alice@ebonhold", class="MAGE", description="original",
    lastModified=10, echoes={{spellId=200100, quality=3, stacks=1}},
}
Sync.HandleIncoming(BuildPacket("Mallory", alice, 10), "Mallory")
local relayed = NexusDB.communityBuilds[alice.id]
assert(relayed and relayed.ownerVerified == false and relayed.ownerKey == nil
    and not relayed.isMine, "relay gained build-owner authority")
Sync.HandleIncoming(BuildPacket("Alice", alice, 10), "Alice")
local verified = NexusDB.communityBuilds[alice.id]
assert(verified and verified.ownerVerified == true
    and verified.ownerKey == "alice@ebonhold",
    "direct owner did not replace the unverified relay")
local forged = {
    id=alice.id, title="Forged", author="Alice", ownerKey="alice@ebonhold",
    class="MAGE", description="forged", lastModified=99,
    echoes={{spellId=200101, quality=3, stacks=1}},
}
Sync.HandleIncoming(BuildPacket("Mallory", forged, 99), "Mallory")
assert(NexusDB.communityBuilds[alice.id].title == "Alice Build",
    "relayed overwrite changed owner-controlled state")

local futureStamp = 2000000301
local futureBuild = {
    id="future-build", title="Future Build", author="Alice",
    ownerKey="alice@ebonhold", class="MAGE", description="poison",
    lastModified=futureStamp,
    echoes={{spellId=200102, quality=3, stacks=1}},
}
assert(not Sync.HandleIncoming(
        BuildPacket("Alice", futureBuild, futureStamp), "Alice")
    and NexusDB.communityBuilds[futureBuild.id] == nil,
    "far-future full build revision entered the durable catalog")
local futureSummary = Codec.Base64Encode(Codec.JSONEncode({
    id="future-summary", t="Future Summary", a="Alice",
    o="alice@ebonhold", c="MAGE", m=futureStamp,
    h="deadbeef", n=1,
}))
assert(not Sync.HandleIncoming("WLBI|Alice|" .. futureSummary, "Alice")
    and NexusDB.communityBuilds["future-summary"] == nil,
    "far-future build summary entered the durable catalog")

Sync.HandleIncoming("WLRD|Mallory|alice-build|100|Alice", "Mallory")
assert(NexusDB.communityBuilds[alice.id], "spoofed tombstone deleted a build")
Sync.HandleIncoming("WLRD|Mallory|unknown|100|Mallory", "Mallory")
assert(NexusDB.syncTombstones.unknown == nil,
    "unknown tombstone gained persistent authority")
Sync.HandleIncoming("WLRD|Alice|alice-build|0|Alice", "Alice")
assert(NexusDB.communityBuilds[alice.id]
    and NexusDB.syncTombstones[alice.id] == nil,
    "zero-stamped tombstone bypassed delete validation")
Sync.HandleIncoming("WLRD|Alice|alice-build|101|Alice", "Alice")
assert(NexusDB.communityBuilds[alice.id] == nil,
    "actual owner could not delete the build")

-- Sender spoofing is rejected before any protocol handler sees the packet.
Sync.HandleIncoming(BuildPacket("Alice", alice, 110), "Mallory")
assert(NexusDB.communityBuilds[alice.id] == nil,
    "embedded sender spoof bypassed transport binding")

-- Exact DPS evidence is required and is bound to the transport player.
NexusDB.dpsCapture = {}
DPS.Init({}, Sync)
local echoes = {{spellId=200200, stacks=2}}
local fingerprint = DPS.GetEchoKey(echoes)
local record = {
    v=7, f=fingerprint, h=DPS.GetEchoHash(echoes), e=echoes,
    c="dummy", d=25000000, u=65, t=50000, p="Alice", l=80,
    k="MAGE", o="alice@ebonhold", r="ebonhold",
}
local dpsData = Codec.Base64Encode(Codec.JSONEncode(record))
local function DeliverDps(sender, transferId, encoded)
    local chunkSize = 160
    local total = math.ceil(#encoded / chunkSize)
    for i = 1, total do
        local chunk = encoded:sub((i - 1) * chunkSize + 1, i * chunkSize)
        local packet = "WLD2|" .. sender .. "|" .. transferId .. "|"
            .. i .. "/" .. total .. "|" .. chunk
        assert(#packet <= 255, "DPS test fixture exceeded the real wire limit")
        Sync.HandleIncoming(packet, sender)
    end
end
DeliverDps("Mallory", "spoof", dpsData)
assert(#DPS.GetDpsBoard("dummy") == 0,
    "DPS player spoof entered the verified board")
DeliverDps("Alice", "valid", dpsData)
assert(#DPS.GetDpsBoard("dummy") == 1,
    "valid owner-bound DPS record was rejected")
Sync.HandleIncoming("WLDS|Mallory|x|Mallory|999999999999|80|dummy",
    "Mallory")
assert(#DPS.GetDpsBoard("dummy") == 1,
    "legacy enormous/no-duration DPS altered the board")
record.d = 26000000
record.u = 0
assert(not DPS.ReceiveRecord(record, "Alice"),
    "no-duration current DPS record was accepted")
record.u = 65
record.e = {{spellId=200200, stacks=121}}
assert(not DPS.ReceiveRecord(record, "Alice"),
    "oversized Echo evidence was accepted")

-- Failed edits are atomic; successful Echo replacement refreshes all identity.
UnitName = function() return "Boganic" end
GetNormalizedRealmName = function() return "Ebonhold" end
local Builds = Nexus.CommunityBuilds
local originalEchoes = {{spellId=200300, quality=2, stacks=1}}
NexusDB.communityBuilds = {
    mine={id="mine", title="Original", description="Original description",
        author="Boganic", ownerKey="boganic@ebonhold", class="MAGE",
        echoes=originalEchoes, postedAt=10, lastModified=10, isMine=true,
        fingerprint="stale", fingerprintHash="stale", echoCount=99},
}
local adapter = { Wishlist=function()
    return {entries={{spellId=200301, quality=3, stacks=2}}}
end }
Builds.Init(adapter, {})
local ok = Builds.EditBuild("mine", "Changed", "Changed description",
    "https://example.com/not-discord")
local mine = NexusDB.communityBuilds.mine
assert(not ok and mine.title == "Original"
    and mine.description == "Original description" and mine.lastModified == 10,
    "invalid link partially mutated the build")
local oldFingerprint, oldHash = mine.fingerprint, mine.fingerprintHash
local replaced, count = Builds.UpdateFromWishlist("mine")
assert(replaced and count == 1 and mine.echoCount == 2
    and mine.fingerprint ~= oldFingerprint and mine.fingerprintHash ~= oldHash
    and mine.loadoutAvailable == true and mine.needsFullBuild == false,
    "Echo replacement left stale derived identity")

print("sync authority, bounded transfers, DPS evidence, and atomic builds -- OK")
