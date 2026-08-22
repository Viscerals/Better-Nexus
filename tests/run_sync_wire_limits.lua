-- Regressions for the two live bugs that made receiving fail entirely
-- (2026-07-24):
--   1. CHAT_MSG_CHANNEL arg4 carries the channel name WITH a number
--      prefix ("5. wrbuildssync"); the bare name is arg9. Matching only
--      against arg4 never fired, so nothing was ever received AND peers
--      never saw each other's sync requests.
--   2. A fixed 200-byte chunk + header + pipe-escaping came to 259 chars
--      against WoW's 255 limit, so every multi-chunk build was silently
--      truncated and arrived as corrupt base64.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Relay.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/Readout.lua")
dofile("ui/Panel.lua")
Nexus.LogViewer = { Init = function() end }
dofile("ui/CommunityBuilds.lua")
dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/WishlistModel.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")

local Codec, Sync = Nexus.Codec, Nexus.Sync
local clock = 1000
GetTime = function() return clock end
local function Pump(steps)
    for _ = 1, steps do clock = clock + 0.2; Sync.OnUpdate(0.2) end
end
time = function() return 50000 end
UnitName = function() return "Boganicc" end   -- realistic long-ish name
GetNormalizedRealmName = function() return "Ebonhold" end

NexusDB = {}
H.playerLevel = 5
H.wishlist = { name = "W", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 } } }
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("SPELLS_CHANGED")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(2)

------------------------------------------------------------------------
-- BUG 2: no message may ever exceed WoW's 255-char chat limit
------------------------------------------------------------------------
-- A realistically large build: 70 echoes and a long description, like a
-- real endgame wishlist.
local bigEchoes = {}
for i = 1, 70 do
    bigEchoes[i] = { spellId = 200000 + i, quality = 3, stacks = 9 }
end
local bigBuild = {
    id = "mine-1784886552-123456",       -- realistic generated id length
    title = "Full Endgame Rogue Wishlist",
    description = string.rep("This is a long description explaining the build. ", 6),
    author = "Boganicc", ownerKey = "boganicc@ebonhold", ownerVerified = true,
    isMine = true, class = "ROGUE",
    echoes = bigEchoes, postedAt = 1784886552, lastModified = 1784886552,
}

H.sentChatMessages = {}
assert(Sync.BroadcastBuild(bigBuild), "broadcasting a realistic large build should succeed")
Pump(400)
assert(#H.sentChatMessages > 1, "a 70-echo build should span multiple chunks")

local longest = 0
for _, m in ipairs(H.sentChatMessages) do
    if #m.text > longest then longest = #m.text end
end
print(string.format("largest wire message: %d chars (limit 255, %d chunks)",
    longest, #H.sentChatMessages))
assert(longest <= 255,
    "a chat message exceeded the 255-char limit and would be TRUNCATED: " .. longest)
assert((Sync.Stats().oversizeDropped or 0) == 0,
    "some messages were dropped as oversize -- chunk sizing is still wrong")
print("all wire messages fit within WoW's 255-char chat limit -- OK")

------------------------------------------------------------------------
-- BUG 1: the channel filter must match 3.3.5's actual arg layout
------------------------------------------------------------------------
local msgs = H.sentChatMessages
NexusDB.communityBuilds = nil
Sync.RequestSync()
clock = clock + 1

-- Deliver exactly as 3.3.5 does: arg4 = "5. wrbuildssync" (numbered),
-- arg9 = "wrbuildssync" (bare).
for _, m in ipairs(msgs) do
    H.FireEvent("CHAT_MSG_CHANNEL", m.text, "Boganicc-Ebonhold", "Common",
        "5. " .. Sync.ChannelName(),      -- arg4, numbered
        nil, nil, nil, 5,                  -- arg5..arg8
        Sync.ChannelName())                -- arg9, bare
end

local got = Nexus.BuildCatalog.Get("mine-1784886552-123456")
assert(got, "the build was NOT received -- the 3.3.5 channel arg layout still isn't matched")
assert(#got.echoes == 70, "received build lost echoes in transit (got " .. #got.echoes .. "/70)")
assert(got.title == "Full Endgame Rogue Wishlist", "title corrupted in transit")
assert(got.description:find("long description"), "description corrupted in transit")
print("a full 70-echo build survives the real 3.3.5 channel path intact -- OK")

------------------------------------------------------------------------
-- The numbered-only form (no arg9 at all) must also work
------------------------------------------------------------------------
-- Fresh timestamp: the dedup guard would (correctly) reject a replay of
-- the exact same version we already stored above.
local function RegenMessages(stamp)
    H.sentChatMessages = {}
    local b = {}
    for k, v in pairs(bigBuild) do b[k] = v end
    b.lastModified = stamp
    Sync.BroadcastBuild(b)
    Pump(400)
    return H.sentChatMessages
end

NexusDB.communityBuilds = nil
local msgs2 = RegenMessages(1784886999)
clock = clock + 10
Sync.RequestSync()
for _, m in ipairs(msgs2) do
    H.FireEvent("CHAT_MSG_CHANNEL", m.text, "Boganicc-Ebonhold", "Common",
        "12. " .. Sync.ChannelName())      -- arg4 only, no arg9
end
assert(NexusDB.communityBuilds
    and NexusDB.communityBuilds["mine-1784886552-123456"],
    "delivery failed when only the numbered arg4 form was present")
print("delivery also works when only the numbered channel form is available -- OK")

------------------------------------------------------------------------
-- Traffic on an UNRELATED channel must still be ignored
------------------------------------------------------------------------
NexusDB.communityBuilds = nil
local msgs3 = RegenMessages(1784887777)
clock = clock + 10
Sync.RequestSync()
for _, m in ipairs(msgs3) do
    H.FireEvent("CHAT_MSG_CHANNEL", m.text, "Boganicc", "Common",
        "2. Trade", nil, nil, nil, 2, "Trade")
end
assert(not (NexusDB.communityBuilds
    and NexusDB.communityBuilds["mine-1784886552-123456"]),
    "traffic from an unrelated channel was processed -- filter is too loose now")
print("unrelated channel traffic is still correctly ignored -- OK")
