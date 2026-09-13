-- Hostile Sync/DPS input and CommunityBuild integrity regressions.
local H = dofile("tests/harness.lua")
local S = dofile("tests/catalog_authority_support.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
dofile("core/DpsCapture.lua")
dofile("ui/CommunityBuilds.lua")

local Codec, Sync, DPS = Nexus.Codec, Nexus.Sync, Nexus.DpsCapture
time = function() return 50000 end
NexusDB = { communityBuilds={}, syncTombstones={}, dpsCapture={} }

-- Legacy-to-bundle cutover: clearing the preserved legacy input no longer
-- resets durable state, so a reset client is a fresh database whose bootstrap
-- builds a new first complete bundle.
local function ResetSync()
    NexusDB = { communityBuilds={}, syncTombstones={},
        dpsCapture=NexusDB.dpsCapture }
    Sync.Init(Codec, {})
end

-- MASTER-W2-008: inbound rows are retained catalog mutations. Every delivery
-- below settles that retained work before the durable assertion that follows;
-- a rejected packet leaves no candidate and settles nothing.
local function Deliver(text, sender)
    local accepted = Sync.HandleIncoming(text, sender)
    S.PumpCatalogToIdle("inbound catalog mutation")
    return accepted
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
-- Legacy-to-bundle cutover (architecture 3b5de54f state machine lines 394 and
-- 4849): the durable authority payload is `authorityBundle`; the exact PR #68
-- locations are read-only preserved input that receiving never writes.
Deliver(BuildPacket("Mallory", alice, 10), "Mallory")
local relayed = H.DurableBuilds()[alice.id]
assert(relayed and relayed.ownerVerified == false and relayed.ownerKey == nil
    and relayed.claimedOwnerKey == "alice@ebonhold"
    and not relayed.isMine, "relay gained build-owner authority")
Deliver(BuildPacket("Alice", alice, 10), "Alice-Ebonhold")
local verified = H.DurableBuilds()[alice.id]
assert(verified and verified.ownerVerified == true
    and verified.ownerKey == "alice@ebonhold",
    "direct owner did not replace the unverified relay")
local forged = {
    id=alice.id, title="Forged", author="Alice", ownerKey="alice@ebonhold",
    class="MAGE", description="forged", lastModified=99,
    echoes={{spellId=200101, quality=3, stacks=1}},
}
Deliver(BuildPacket("Mallory", forged, 99), "Mallory")
assert(H.DurableBuilds()[alice.id].title == "Alice Build",
    "relayed overwrite changed owner-controlled state")
Deliver("WLRD|Mallory|alice-build|100|Alice", "Mallory")
assert(H.DurableBuilds()[alice.id], "spoofed tombstone deleted a build")
Deliver("WLRD|Mallory|unknown|100|Mallory", "Mallory")
assert(H.DurableTombstones().unknown == nil,
    "unknown tombstone gained persistent authority")
Deliver("WLRD|Alice|alice-build|101|Alice", "Alice-Ebonhold")
-- The owner delete publishes a deny-only reservation and preserves the raw row.
assert(Nexus.BuildCatalog.Get(alice.id) == nil
    and H.DurableBuilds()[alice.id] ~= nil,
    "actual owner could not delete the build")

-- Sender spoofing is rejected before any protocol handler sees the packet.
Deliver(BuildPacket("Alice", alice, 110), "Mallory")
-- The reserved slot still serves nothing and its raw evidence is unchanged.
assert(Nexus.BuildCatalog.Get(alice.id) == nil
    and H.DurableBuilds()[alice.id].title == "Alice Build",
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
local function DeliverDps(sender, transferId, encoded, transportSender)
    local chunkSize = 160
    local total = math.ceil(#encoded / chunkSize)
    for i = 1, total do
        local chunk = encoded:sub((i - 1) * chunkSize + 1, i * chunkSize)
        local packet = "WLD2|" .. sender .. "|" .. transferId .. "|"
            .. i .. "/" .. total .. "|" .. chunk
        assert(#packet <= 255, "DPS test fixture exceeded the real wire limit")
        Sync.HandleIncoming(packet, transportSender or sender)
    end
end
DeliverDps("Mallory", "spoof", dpsData)
assert(#DPS.GetDpsBoard("dummy") == 0,
    "DPS player spoof entered the verified board")
DeliverDps("Alice", "valid", dpsData, "Alice-Ebonhold")
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
-- Seeded as exact PR #68 legacy input on a fresh database so bootstrap admits
-- it and builds the first complete bundle (state machine line 374). After bundle
-- occupancy a raw legacy write is not an admission input at all (line 394).
NexusDB = {
    dpsCapture=NexusDB.dpsCapture,
    syncTombstones={},
    communityBuilds={
        mine={id="mine", title="Original", description="Original description",
            author="Boganic", ownerKey="boganic@ebonhold",
            ownerVerified=true,realm="ebonhold",class="MAGE",
            echoes=originalEchoes, postedAt=10, lastModified=10, isMine=true,
            fingerprint="stale", fingerprintHash="stale", echoCount=99},
    },
}
local adapter = { Wishlist=function()
    return {entries={{spellId=200301, quality=3, stacks=2}}}
end }
local admitted = H.RebindCatalog()
assert(admitted and admitted.state == "ROOT_ADMITTED",
    "legacy security fixture did not reach terminal catalog admission")
Builds.Init(adapter, {})
-- `backing` is the preserved legacy input map and `mine` the exact legacy row
-- bootstrap admitted from it. Both must survive every later publication
-- untouched: after occupancy these locations are neither storage nor input.
local backing = NexusDB.communityBuilds
local mine = backing.mine
local legacyBytes = Nexus.Codec.JSONEncode(backing)
local durableBefore = H.DurableBuilds().mine
assert(durableBefore ~= nil and Nexus.BuildCatalog.Get("mine") ~= nil,
    "bootstrap did not admit the legacy row into the first complete bundle")
local ok = Builds.EditBuild("mine", "Changed", "Changed description",
    "https://example.com/not-discord")
assert(not ok and mine.title == "Original"
    and mine.description == "Original description" and mine.lastModified == 10,
    "invalid link partially mutated the build")
-- Capture the published row after Init. Admission may already have replaced
-- the seed table; that prior row must stay immutable across Echo replacement.
local oldFingerprint, oldHash = durableBefore.fingerprint, durableBefore.fingerprintHash
local oldEchoCount = durableBefore.echoCount
local bundleBefore = rawget(NexusDB, "authorityBundle")
-- Earlier owner writes are retained catalog mutations; settle them so the
-- replacement is admitted against the published root, not refused as pending.
S.PumpCatalogToIdle("pre-replacement catalog work")
local replaced, count = Builds.UpdateFromWishlist("mine")
-- The replacement is one retained catalog mutation; settle it before the
-- bundle and row assertions.
S.PumpCatalogToIdle("Echo replacement admission")
local published = H.DurableBuilds().mine
local publicRow = Nexus.BuildCatalog.Get("mine")

-- Architecture 3b5de54f, MASTER-RC-001 and MASTER-RC-002. Five separate
-- obligations, each proved on its own; the identity check is repointed at the
-- authoritative seam rather than removed.
--
-- 1. The legacy input is preserved exactly: same map identity, same row
--    identity, same bytes. Line 394 gives it no Package B writer.
assert(NexusDB.communityBuilds == backing and backing.mine == mine
    and Nexus.Codec.JSONEncode(backing) == legacyBytes,
    "the preserved legacy input map, row, or bytes changed")
-- 2. The new authoritative data is published through one complete bundle
--    replacement, so the durable row is replaced, never rewritten in place.
assert(replaced and count == 1
    and rawget(NexusDB, "authorityBundle") ~= bundleBefore
    and published ~= durableBefore,
    "Echo replacement did not publish a replacement row inside a new bundle")
-- 3. The old durable snapshot is not rewritten: the superseded bundle graph
--    stays byte-exact.
assert(bundleBefore.communityBuilds.mine == durableBefore
    and durableBefore.fingerprint == oldFingerprint
    and durableBefore.fingerprintHash == oldHash
    and durableBefore.echoCount == oldEchoCount,
    "the superseded durable row was rewritten in place")
-- 4. Public reads return the replacement row with refreshed derived identity.
assert(publicRow and publicRow.echoCount == 2
    and publicRow.fingerprint ~= oldFingerprint
    and publicRow.fingerprintHash ~= oldHash
    and publicRow.loadoutAvailable == true and publicRow.needsFullBuild == false
    and published.echoCount == 2
    and published.fingerprint ~= oldFingerprint
    and published.fingerprintHash ~= oldHash
    and published.loadoutAvailable == true and published.needsFullBuild == false,
    "Echo replacement left stale derived identity")
-- 5. The preserved legacy contents cannot override an occupied bundle: an
--    explicit complete readmission from cursor zero still serves the
--    replacement, not the stale legacy row (line 394, never a fallback).
H.RebindCatalog()
assert(Nexus.BuildCatalog.Get("mine").echoCount == 2
    and Nexus.BuildCatalog.Get("mine").fingerprint ~= oldFingerprint
    and NexusDB.communityBuilds == backing and backing.mine == mine,
    "stale legacy input overrode the occupied authority bundle")

print("sync authority, bounded transfers, DPS evidence, and atomic builds -- OK")
