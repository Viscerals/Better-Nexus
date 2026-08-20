-- Basic Sync lifecycle: channel discovery/join, and a small single-chunk
-- build broadcast/receive round trip end to end.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")

local Codec = Nexus.Codec
local Sync = Nexus.Sync

NexusDB = {}
UnitName = function() return "Alice" end
GetTime = function() return 100 end

-- channel not joined yet
assert(not Sync.IsConnected(), "should not be connected before EnsureChannel")
Sync.Init(Codec, nil)
assert(Sync.IsConnected(), "Sync.Init should have joined the channel")
print("channel discovery/join works -- OK")

-- broadcast a small build (fits in a single chunk)
local build = { id = "mine-1", title = "Fire Mage AoE", description = "Great farm build",
    author = "Alice", class = "MAGE", echoes = {
        { spellId = 200100, quality = 3, stacks = 1 },
    }, postedAt = 1000 }
local ok = Sync.BroadcastBuild(build)
assert(ok, "BroadcastBuild should have succeeded for a small build")

-- pump the send queue until the message actually goes out
for i = 1, 20 do Sync.OnUpdate(0.2) end
assert(#H.sentChatMessages >= 1, "no chat message was actually sent")
local sentText = H.sentChatMessages[1].text
assert(H.sentChatMessages[1].kind == "CHANNEL", "message should be sent to CHANNEL")
print("BroadcastBuild sends a real chat message via the sync channel -- OK")

-- Now simulate a DIFFERENT client (Bob) receiving that exact message.
-- This build spans more than one chunk, so feed ALL queued messages
-- through in order, exactly as CHAT_MSG_CHANNEL would deliver each one.
NexusDB = {}  -- fresh DB, as if this were Bob's client
-- Receiving is opt-in now: Bob must have requested a sync for incoming
-- builds to be accepted at all.
assert(Sync.RequestSync(), "RequestSync should succeed")
H.now = H.now + 1.1
Sync.OnUpdate(1.1)
assert(Sync.IsReceiving(), "receive window should be open after RequestSync")
for _, msg in ipairs(H.sentChatMessages) do
    Sync.HandleIncoming(msg.text, "Alice")
end

local stored = NexusDB.communityBuilds and NexusDB.communityBuilds["mine-1"]
assert(stored, "received build was not stored")
assert(stored.title == "Fire Mage AoE", "wrong title received")
assert(stored.description == "Great farm build", "wrong description received")
assert(#stored.echoes == 1 and stored.echoes[1].spellId == 200100, "wrong echoes received")
assert(stored.isMine == false, "a received build must never be tagged isMine")
print("a broadcast build is correctly received, decoded, and stored by another client -- OK")
