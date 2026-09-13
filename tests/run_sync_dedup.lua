-- Verifies the core correctness requirement: no duplicates, correct
-- update-vs-stale handling, and safe rejection of malformed data.
local H = dofile("tests/harness.lua")
local S = dofile("tests/catalog_authority_support.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
local Codec, Sync = Nexus.Codec, Nexus.Sync
local Catalog = Nexus.BuildCatalog

NexusDB = {}
UnitName = function() return "Alice" end
GetNormalizedRealmName = function() return "Ebonhold" end
fakeClock = 100
GetTime = function() return fakeClock end
Sync.Init(Codec, nil)

local function BroadcastAndCollect(build)
    -- A replaced SavedVariables owner is current-source drift: readmit the
    -- complete root from cursor zero before the sender writes into it.
    if type(Catalog.BoundDatabase) == "function"
        and Catalog.BoundDatabase() ~= NexusDB then
        H.RebindCatalog(NexusDB)
    end
    -- Received builds are retained catalog mutations; settle them before the
    -- sender writes so the fixture never races its own pending work.
    S.PumpCatalogToIdle("sender fixture catalog work")
    local previous = Catalog.Get(build.id)
    assert(S.CatalogMutation(function() return Catalog.Put(build) end,
        "sender build admission"), "sender build could not enter the catalog")
    local selected = Catalog.Get(build.id)
    H.sentChatMessages = {}
    local queued, why = Sync.BroadcastBuild(selected)
    assert(queued, "selected sender build was not queued: " .. tostring(why))
    for i = 1, 30 do Sync.OnUpdate(0.2) end
    local messages = H.sentChatMessages
    local emitted = false
    for _, message in ipairs(messages) do
        if tostring(message.text):match("^WLRB|") then emitted = true break end
    end
    assert(emitted, "selected sender build emitted no WLRB payload")
    if previous then
        assert(S.CatalogMutation(function() return Catalog.Put(previous) end,
            "receiver snapshot restore"), "receiver snapshot could not be restored")
    else
        assert(S.CatalogMutation(function() return Catalog.RemoveOverlay(build.id) end,
            "temporary sender build removal"),
            "temporary sender build could not be removed")
    end
    return messages
end

-- Receiving is opt-in: every delivery in these tests happens inside an
-- explicitly-opened receive window, since that's the only state in which
-- builds are accepted at all.
local function DeliverAll(msgs)
    fakeClock = (fakeClock or 100) + 10   -- clear the request cooldown
    Sync.RequestSync()
    for _, msg in ipairs(msgs) do Sync.HandleIncoming(msg.text, "Alice-Ebonhold") end
    S.PumpCatalogToIdle("received build catalog work")
end

-- 1. Sending the exact same build twice must NOT create a duplicate or
-- double-count as newly received.
NexusDB = {}
local build = { id = "b1", title = "Build One", description = "d", author = "Alice",
    ownerKey = "alice@ebonhold", ownerVerified = true, isMine = true, class = "MAGE",
    echoes = { { spellId = 200100, quality = 3, stacks = 1 } }, postedAt = 1000 }
DeliverAll(BroadcastAndCollect(build))
local receivedAfterFirst = Sync.Stats().received
DeliverAll(BroadcastAndCollect(build))  -- identical rebroadcast
assert(Sync.Stats().received == receivedAfterFirst,
    "identical rebroadcast should NOT count as a new receive")
assert(Sync.Stats().duplicatesSkipped >= 1, "duplicate rebroadcast should be counted as skipped")
-- Legacy-to-bundle cutover (architecture 3b5de54f, state machine lines 394,
-- 4849): received builds are durable in the authority bundle only; the exact
-- PR #68 location is preserved read-only input that receiving never writes.
local count = 0
for _ in pairs(H.DurableBuilds()) do count = count + 1 end
assert(count == 1, "expected exactly 1 stored build after receiving the same one twice, got " .. count)
assert(rawget(NexusDB, "communityBuilds") == nil,
    "receiving wrote a legacy payload location")
print("identical rebroadcast is correctly deduplicated, no double-entry -- OK")

-- 2. A NEWER version of the same build (higher postedAt) must update the
-- stored copy.
local buildV2 = { id = "b1", title = "Build One (updated)", description = "d2", author = "Alice",
    ownerKey = "alice@ebonhold", ownerVerified = true, isMine = true, class = "MAGE",
    echoes = { { spellId = 200100, quality = 3, stacks = 2 } }, postedAt = 2000 }
DeliverAll(BroadcastAndCollect(buildV2))
assert(H.DurableBuilds()["b1"].title == "Build One (updated)",
    "newer version should have updated the stored title")
assert(H.DurableBuilds()["b1"].echoes[1].stacks == 2,
    "newer version should have updated the stored echoes")
count = 0
for _ in pairs(H.DurableBuilds()) do count = count + 1 end
assert(count == 1, "update should replace, not add a second entry")
print("a newer version correctly updates the existing entry, still no duplicate -- OK")

-- 3. An OLDER/stale rebroadcast must NOT overwrite the newer stored copy
-- (protects against a stale peer's old data clobbering something newer).
local staleReplay = { id = "b1", title = "Build One (STALE)", description = "old", author = "Alice",
    ownerKey = "alice@ebonhold", ownerVerified = true, isMine = true, class = "MAGE",
    echoes = { { spellId = 200100, quality = 3, stacks = 1 } }, postedAt = 1000 }
DeliverAll(BroadcastAndCollect(staleReplay))
assert(H.DurableBuilds()["b1"].title == "Build One (updated)",
    "a stale/older replay must NOT overwrite the newer stored version")
print("stale/older replays are correctly rejected, newer data is protected -- OK")

-- 4. Malformed payloads must be safely rejected, never crash, never stored.
NexusDB = {}
local before = Sync.Stats().malformedRejected
local ok1 = pcall(Sync.HandleIncoming, "WLRB|Alice|bad-id|1000|1/1|not-valid-base64!!!", "Alice")
assert(ok1, "malformed base64 payload should not error")
assert(H.DurableBuilds()["bad-id"] == nil
    and rawget(NexusDB, "communityBuilds") == nil,
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
assert(H.DurableBuilds()["different-envelope-id"] == nil
    and rawget(NexusDB, "communityBuilds") == nil,
    "mismatched envelope/payload id must be rejected, not silently accepted")
print("mismatched envelope/payload id is correctly rejected -- OK")
