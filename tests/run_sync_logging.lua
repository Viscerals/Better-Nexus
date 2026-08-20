-- Verifies the sync diagnostic log captures BOTH directions and, crucially,
-- records a DISTINCT reason for every failure mode -- so a broken sync can
-- be diagnosed from the log alone instead of by guesswork.
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
local provider
Nexus.LogViewer = { Init = function(p) provider = p end,
    Show = function() end, Toggle = function() end }
dofile("ui/CommunityBuilds.lua")
dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")

local Codec, Sync = Nexus.Codec, Nexus.Sync
local clock = 1000
GetTime = function() return clock end
time = function() return 50000 end
UnitName = function() return "Alice" end
GetNormalizedRealmName = function() return "Ebonhold" end

NexusDB = {}
H.playerLevel = 5
H.wishlist = { name = "W", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 } } }
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("SPELLS_CHANGED")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(2)

local function LogText() return provider("sync") end
local function LogHas(pattern)
    return LogText():find(pattern) ~= nil
end

-- Channel join must be recorded
assert(LogHas("joined") or LogHas("already in"),
    "channel join was not logged")
print("channel join is logged -- OK")

-- SEND side: posting must log the broadcast and the actual wire sends
local CB = Nexus.CommunityBuilds
local ok, id = CB.PostCurrentWishlist("Logged Build", "desc", H.wishlist)
assert(ok, "post should succeed")
H.Advance(3)
assert(LogHas("queuing") or LogHas("broadcasting"), "broadcast was not logged")
assert(LogHas("sent %d+ chars") or LogHas("TX"), "actual wire sends were not logged")
print("send side is fully logged (broadcast + each wire message) -- OK")

-- Valid owner-authored updates are accepted even outside a manual sync window.
-- Sender identity must match the payload author.
local msgs = {}
for _, m in ipairs(H.sentChatMessages) do msgs[#msgs + 1] = m end
NexusDB.communityBuilds = nil
Sync.ClearLog()
clock = clock + 3600   -- ensure any window is closed
for _, m in ipairs(msgs) do
    H.FireEvent("CHAT_MSG_CHANNEL", m.text, "Alice-Ebonhold", "Common",
        "5. " .. Sync.ChannelName(), nil, nil, nil, 5, Sync.ChannelName())
end
assert(NexusDB.communityBuilds and NexusDB.communityBuilds[id],
    "a valid owner-authored update was dropped outside a sync window")
assert(LogHas("STORED"), "outside-window owner update was not logged")
print("valid owner update is accepted and logged outside a sync window -- OK")

-- RECEIVE side, success: with a window open, the store must be logged
NexusDB.communityBuilds = {}
Sync.Init(Codec, Nexus.GameAdapter or {})
Sync.ClearLog()
clock = clock + 10
Sync.RequestSync()
clock = clock + 1.1
Sync.OnUpdate(1.1)
assert(LogHas("requested sync"), "the sync request itself was not logged")
for _, m in ipairs(msgs) do
    H.FireEvent("CHAT_MSG_CHANNEL", m.text, "Alice-Ebonhold", "Common",
        "5. " .. Sync.ChannelName(), nil, nil, nil, 5, Sync.ChannelName())
end
assert(LogHas("STORED"), "a successful store was not logged")
print("successful receive+store is logged -- OK")

-- RECEIVE side, failure mode 2: duplicate must log a distinct reason
Sync.ClearLog()
clock = clock + 10
Sync.RequestSync()
for _, m in ipairs(msgs) do
    H.FireEvent("CHAT_MSG_CHANNEL", m.text, "Alice-Ebonhold", "Common",
        "5. " .. Sync.ChannelName(), nil, nil, nil, 5, Sync.ChannelName())
end
assert(LogHas("DUPLICATE") or LogHas("duplicate"),
    "a duplicate skip was not logged with its own distinct reason")
print("duplicate skip is logged distinctly from other failures -- OK")

-- RECEIVE side, failure mode 3: corrupt payload must log its own reason
Sync.ClearLog()
clock = clock + 10
Sync.RequestSync()
H.FireEvent("CHAT_MSG_CHANNEL", "WLRB||Bob||corrupt-id||999||1/1||!!!notbase64!!!",
    "Bob", "Common", "5. " .. Sync.ChannelName(), nil, nil, nil, 5, Sync.ChannelName())
assert(LogHas("base64") or LogHas("bad base64"),
    "a corrupt payload was not logged with a decode-failure reason")
print("corrupt payload logs a decode-failure reason -- OK")

-- The CRITICAL diagnostic: protocol seen on an unmatched channel must
-- record the actual arg values (this is what would have instantly
-- revealed the arg4/arg9 bug)
Sync.ClearLog()
H.FireEvent("CHAT_MSG_CHANNEL", "WLRQ||Bob", "Bob", "Common",
    "9. someotherchannel", nil, nil, nil, 9, "someotherchannel")
assert(LogHas("MISMATCH"),
    "protocol traffic on an unmatched channel was not flagged")
assert(LogHas("someotherchannel"),
    "the mismatch log does not include the actual channel values seen")
print("channel MISMATCH is logged with the real arg values -- OK")

-- Peer request handling must be logged
Sync.ClearLog()
clock = clock + 100
H.FireEvent("CHAT_MSG_CHANNEL", "WLRQ||Bob", "Bob", "Common",
    "5. " .. Sync.ChannelName(), nil, nil, nil, 5, Sync.ChannelName())
assert(LogHas("request from Bob"), "answering a peer request was not logged")
print("answering a peer's sync request is logged -- OK")

-- The tab must also summarise state and library contents
local text = LogText()
assert(text:find("connected%s+:"), "tab missing connection summary")
assert(text:find("sent"), "tab missing counters")
assert(text:find("builds in my library"), "tab missing library summary")
print("Sync tab includes connection state, counters, and library summary -- OK")
