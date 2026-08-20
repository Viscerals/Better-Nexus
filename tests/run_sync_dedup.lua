-- Verifies the core correctness requirement: no duplicates, correct
-- update-vs-stale handling, and safe rejection of malformed data.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
local Codec, Sync = Nexus.Codec, Nexus.Sync

NexusDB = {}
UnitName = function() return "Alice" end
fakeClock = 100
GetTime = function() return fakeClock end
Sync.Init(Codec, nil)

local function BroadcastAndCollect(build)
    H.sentChatMessages = {}
    Sync.BroadcastBuild(build)
    for i = 1, 30 do Sync.OnUpdate(0.2) end
    return H.sentChatMessages
end

-- Receiving is opt-in: every delivery in these tests happens inside an
-- explicitly-opened receive window, since that's the only state in which
-- builds are accepted at all.
local function DeliverAll(msgs)
    fakeClock = (fakeClock or 100) + 10   -- clear the request cooldown
    Sync.RequestSync()
    for _, msg in ipairs(msgs) do Sync.HandleIncoming(msg.text, "Alice") end
end

-- 1. Sending the exact same build twice must NOT create a duplicate or
-- double-count as newly received.
NexusDB = {}
local build = { id = "b1", title = "Build One", description = "d", author = "Alice",
    class = "MAGE", echoes = { { spellId = 200100, quality = 3, stacks = 1 } }, postedAt = 1000 }
DeliverAll(BroadcastAndCollect(build))
local receivedAfterFirst = Sync.Stats().received
DeliverAll(BroadcastAndCollect(build))  -- identical rebroadcast
assert(Sync.Stats().received == receivedAfterFirst,
    "identical rebroadcast should NOT count as a new receive")
assert(Sync.Stats().duplicatesSkipped >= 1, "duplicate rebroadcast should be counted as skipped")
local count = 0
for _ in pairs(NexusDB.communityBuilds) do count = count + 1 end
assert(count == 1, "expected exactly 1 stored build after receiving the same one twice, got " .. count)
print("identical rebroadcast is correctly deduplicated, no double-entry -- OK")

-- 2. A NEWER version of the same build (higher postedAt) must update the
-- stored copy.
local buildV2 = { id = "b1", title = "Build One (updated)", description = "d2", author = "Alice",
    class = "MAGE", echoes = { { spellId = 200100, quality = 3, stacks = 2 } }, postedAt = 2000 }
DeliverAll(BroadcastAndCollect(buildV2))
assert(NexusDB.communityBuilds["b1"].title == "Build One (updated)",
    "newer version should have updated the stored title")
assert(NexusDB.communityBuilds["b1"].echoes[1].stacks == 2,
    "newer version should have updated the stored echoes")
count = 0
for _ in pairs(NexusDB.communityBuilds) do count = count + 1 end
assert(count == 1, "update should replace, not add a second entry")
print("a newer version correctly updates the existing entry, still no duplicate -- OK")

-- 3. An OLDER/stale rebroadcast must NOT overwrite the newer stored copy
-- (protects against a stale peer's old data clobbering something newer).
local staleReplay = { id = "b1", title = "Build One (STALE)", description = "old", author = "Alice",
    class = "MAGE", echoes = { { spellId = 200100, quality = 3, stacks = 1 } }, postedAt = 1000 }
DeliverAll(BroadcastAndCollect(staleReplay))
assert(NexusDB.communityBuilds["b1"].title == "Build One (updated)",
    "a stale/older replay must NOT overwrite the newer stored version")
print("stale/older replays are correctly rejected, newer data is protected -- OK")

-- 4. Malformed payloads must be safely rejected, never crash, never stored.
NexusDB = {}
local before = Sync.Stats().malformedRejected
local ok1 = pcall(Sync.HandleIncoming, "WLRB|Alice|bad-id|1000|1/1|not-valid-base64!!!", "Alice")
assert(ok1, "malformed base64 payload should not error")
assert(NexusDB.communityBuilds == nil or NexusDB.communityBuilds["bad-id"] == nil,
    "malformed payload must not be stored")
local ok2 = pcall(Sync.HandleIncoming, "garbage that is not our protocol at all", "Mallory")
assert(ok2, "unrecognized message format should not error")
local ok3 = pcall(Sync.HandleIncoming, "WLRB|Alice|bad-id2|1000|1/1|" .. Codec.Base64Encode("not json{{{"), "Alice")
assert(ok3, "valid base64 but invalid JSON should not error")
assert(Sync.Stats().malformedRejected > before, "malformed payloads should be counted as rejected")
print("malformed/malicious payloads are safely rejected without crashing or storing -- OK")

-- 5. A build claiming a mismatched id (payload.id != the id in the
-- envelope) must be rejected -- prevents a peer from spoofing envelope
-- routing while smuggling a different id inside the payload.
NexusDB = {}
local spoofPayload = Codec.JSONEncode({ id = "real-id", title = "T", echoes = {
    { spellId = 1, quality = 0, stacks = 1 } } })
local spoofB64 = Codec.Base64Encode(spoofPayload)
Sync.HandleIncoming("WLRB|Alice|different-envelope-id|1000|1/1|" .. spoofB64, "Alice")
assert(NexusDB.communityBuilds == nil or
    NexusDB.communityBuilds["different-envelope-id"] == nil,
    "mismatched envelope/payload id must be rejected, not silently accepted")
print("mismatched envelope/payload id is correctly rejected -- OK")
