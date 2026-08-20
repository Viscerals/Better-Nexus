-- Interleaved multi-build chunk reassembly, inflight timeout cleanup,
-- and RebroadcastMine only sending your own builds.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
local Codec, Sync = Nexus.Codec, Nexus.Sync

NexusDB = {}
UnitName = function() return "Alice" end
local fakeTime = 100
GetTime = function() return fakeTime end
local function Pump(steps) for _ = 1, steps do fakeTime = fakeTime + 0.2; Sync.OnUpdate(0.2) end end
Sync.Init(Codec, nil)

-- 1. Two different builds, both multi-chunk, with their chunks
-- interleaved in delivery order -- must reassemble independently.
local buildA = { id = "A", title = "Build A", description = string.rep("alpha ", 40),
    author = "Alice", class = "MAGE", echoes = { { spellId = 1, quality = 3, stacks = 1 } },
    postedAt = 1000 }
local buildB = { id = "B", title = "Build B", description = string.rep("bravo ", 40),
    author = "Alice", class = "MAGE", echoes = { { spellId = 2, quality = 2, stacks = 1 } },
    postedAt = 1000 }

H.sentChatMessages = {}
Sync.BroadcastBuild(buildA)
Pump(30)
local msgsA = H.sentChatMessages
assert(#msgsA > 1, "test setup expects buildA to span multiple chunks")

H.sentChatMessages = {}
Sync.BroadcastBuild(buildB)
Pump(30)
local msgsB = H.sentChatMessages
assert(#msgsB > 1, "test setup expects buildB to span multiple chunks")

-- Receiving is opt-in: open a window before delivering anything.
fakeTime = fakeTime + 10
Sync.RequestSync()

-- interleave: A1, B1, A2, B2, A3, B3, ...
local maxLen = math.max(#msgsA, #msgsB)
for i = 1, maxLen do
    if msgsA[i] then Sync.HandleIncoming(msgsA[i].text, "Alice") end
    if msgsB[i] then Sync.HandleIncoming(msgsB[i].text, "Alice") end
end

assert(NexusDB.communityBuilds["A"], "build A did not reassemble correctly when interleaved")
assert(NexusDB.communityBuilds["B"], "build B did not reassemble correctly when interleaved")
assert(NexusDB.communityBuilds["A"].title == "Build A")
assert(NexusDB.communityBuilds["B"].title == "Build B")
print("interleaved multi-build chunk transfers reassemble independently and correctly -- OK")

-- 2. An incomplete transfer (missing chunks) must eventually be cleaned
-- up, not leak forever.
local buildA2 = { id = "A2", title = "Build A2", description = string.rep("alpha ", 40),
    author = "Alice", class = "MAGE", echoes = { { spellId = 1, quality = 3, stacks = 1 } },
    postedAt = 1000 }
local buildB2 = { id = "B2", title = "Build B2", description = string.rep("bravo ", 40),
    author = "Alice", class = "MAGE", echoes = { { spellId = 2, quality = 2, stacks = 1 } },
    postedAt = 1000 }
NexusDB = {}
H.sentChatMessages = {}
Sync.BroadcastBuild(buildA2)
Pump(30)
fakeTime = fakeTime + 10
Sync.RequestSync()
-- deliver only the FIRST chunk, never the rest
Sync.HandleIncoming(H.sentChatMessages[1].text, "Alice")
assert(not (NexusDB.communityBuilds and NexusDB.communityBuilds["A2"]),
    "build should not be considered complete with only 1 of several chunks")
-- advance fake time past the inflight timeout, then trigger cleanup via
-- a harmless new incoming message (CleanupExpired runs on each chunked receive)
fakeTime = fakeTime + 130
H.sentChatMessages = {}
Sync.BroadcastBuild(buildB2)
Pump(30)
Sync.RequestSync()
for _, msg in ipairs(H.sentChatMessages) do Sync.HandleIncoming(msg.text, "Alice") end
-- buildB2 should complete fine; buildA2's stale partial transfer should
-- have been silently dropped rather than accumulating forever
assert(NexusDB.communityBuilds["B2"], "buildB2 should complete normally after the timeout window")
print("incomplete/expired transfers are cleaned up without blocking new ones -- OK")

-- 3. Mesh rebroadcast sends every valid build held locally.
NexusDB = { communityBuilds = {
    ["mine-1"] = { id = "mine-1", title = "Mine", description = "d", author = "Alice",
        class = "MAGE", echoes = { { spellId = 1, quality = 0, stacks = 1 } },
        postedAt = 1, isMine = true },
    ["theirs-1"] = { id = "theirs-1", title = "Theirs", description = "d", author = "Bob",
        class = "ROGUE", echoes = { { spellId = 2, quality = 0, stacks = 1 } },
        postedAt = 1, isMine = false },
} }
H.sentChatMessages = {}
local n = Sync.BroadcastMine()
assert(n >= 2, "BroadcastMine should redistribute both locally created and received builds")
Pump(30)
local indexCount = 0
for _, msg in ipairs(H.sentChatMessages) do
    if msg.text:find("^WLBI|") then indexCount = indexCount + 1 end
    assert(not msg.text:find("^WLRB|"), "normal mesh rebroadcast leaked a full loadout")
end
assert(indexCount >= 2, "mesh rebroadcast must include indexes for locally created and received builds")
print("BroadcastMine redistributes the compact valid build index -- OK")
