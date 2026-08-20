-- Checkpoint 12.6: public facade, source ownership, TOC order, reset identity,
-- passive diagnostics, and ordered coordinator characterization.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")

local function Read(path)
    local handle = assert(io.open(path, "rb"))
    local text = handle:read("*a")
    handle:close()
    return text
end

local function Sorted(values)
    table.sort(values)
    return table.concat(values, "\n")
end

local expected = {
    "BroadcastBuild", "BroadcastBuildSummary", "BroadcastDelete",
    "BroadcastDps", "BroadcastDpsRecord", "BroadcastMine", "ChannelIndex",
    "ChannelName", "ClearLog", "EnsureChannel", "EventLog",
    "FlushStatusReply", "GetCanonicalBuildHashes", "GetCompatibilityHashes",
    "GetDeleteStatus", "GetLeaderboardSyncStatus", "GetLegacyBuildHash", "GetPeerInfo",
    "GetShareStatus", "HandleIncoming", "HandleStatusRequest", "HashCacheStats", "Init",
    "IsConnected", "IsKnownPeer", "IsReceiving", "LastSyncNewCount",
    "LogEvent", "LogRaw", "LogStats", "NoteTransportNotice", "OnUpdate", "OnWorldEntry",
    "RawLog", "ReceiveTimeLeft", "RequestDataViewRefresh",
    "RequestFullLoadoutSync", "RequestLoadout", "RequestSync",
    "ResponseStats", "SendStatusTo", "Stats", "TombstoneCount", "WorkState",
}
local actual = {}
for name, value in pairs(Nexus.Sync) do
    if type(value) == "function" then actual[#actual + 1] = name end
end
assert(Sorted(actual) == Sorted(expected),
    "Nexus.Sync callable surface changed during internal extraction")

assert(type(Nexus.SyncInternals.Diagnostics.New) == "function"
    and type(Nexus.SyncInternals.Session.New) == "function",
    "internal Sync factories are unavailable")

local toc = Read("Nexus.toc")
local ordered = {
    "core\\SyncInbound.lua", "core\\SyncDiagnostics.lua",
    "core\\SyncSession.lua", "core\\Sync.lua",
}
local cursor = 1
for _, path in ipairs(ordered) do
    local found = assert(toc:find(path, cursor, true),
        "TOC load order lost " .. path)
    cursor = found + #path
end

local syncSource = Read("core/Sync.lua")
local sessionSource = Read("core/SyncSession.lua")
local diagnosticSource = Read("core/SyncDiagnostics.lua")
local forbiddenSessionOwners = {
    "local joinRetryTicker", "local joinAttempts",
    "local receiveWindowUntil", "local lastRequestAt",
    "local requestedLoadouts", "local legacyRecoveryQueue",
    "local legacyRecoveryHead", "local legacyRecoveryTail",
    "local legacyRecoveryTicker", "local lastSyncNewCount",
    "local autoSyncPending", "local autoSyncElapsed",
    "local autoConverge", "local knownPeers", "local pendingStatusReply",
}
for _, anchor in ipairs(forbiddenSessionOwners) do
    assert(not syncSource:find(anchor, 1, true),
        "Sync retained session owner " .. anchor)
end
for _, anchor in ipairs({
    "local receiveWindowUntil", "local requestedLoadouts",
    "local recoveryQueue", "local lastSyncNewCount",
    "local autoConverge", "local knownPeers", "local pendingStatusReply",
}) do
    assert(sessionSource:find(anchor, 1, true),
        "SyncSession lost sole state owner " .. anchor)
end
assert(not syncSource:find("DiagnosticHistory.New", 1, true)
    and diagnosticSource:find("History.New", 1, true)
    and diagnosticSource:find("local stats = {}", 1, true),
    "Sync diagnostic history or live counters have duplicate owners")

local updateStart = assert(syncSource:find(
    "function Sync.OnUpdate(elapsed)", 1, true),
    "Sync.OnUpdate coordinator unavailable")
local updateEnd = assert(syncSource:find(
    "-- Peer status exchange", updateStart, true),
    "Sync.OnUpdate coordinator end unavailable")
local update = syncSource:sub(updateStart, updateEnd)
local updateOrder = {
    "Inbound.CleanExpired()",
    "ProcessPendingResponses(elapsed)",
    "Session.PumpRecovery(elapsed)",
    "PumpPendingDeletes(elapsed)",
    "Transport.Pump(elapsed)",
    "Sync.FlushStatusReply()",
    "Session.UpdateAutoSync(elapsed)",
    "Session.UpdateAutoConvergence()",
    "Session.UpdateJoinRetry(elapsed)",
}
cursor = 1
for _, anchor in ipairs(updateOrder) do
    local found = assert(update:find(anchor, cursor, true),
        "Sync.OnUpdate order lost " .. anchor)
    cursor = found + #anchor
end

local Sync = Nexus.Sync
local clock = 1000
GetTime = function() return clock end
UnitName = function() return "Alice" end
UnitLevel = function() return 80 end
H.joinedChannels = {}
H.sentChatMessages = {}
NexusDB = {communityBuilds={}, syncTombstones={}}
local adapter = {
    Slots=function() return {maxSlots=5, activeSlot=2} end,
    Wishlist=function() return {name="Parity Wishlist"} end,
}
Sync.Init(Nexus.Codec, adapter)
local liveStats = Sync.Stats()
Sync.LogRaw("retained across session reset")
assert(Sync.HandleIncoming("WLNP|Bob|1.20.0-beta.1", "Bob"),
    "peer fixture was rejected")
local peer = assert(Sync.GetPeerInfo("Bob"))
assert(peer == Sync.GetPeerInfo("Bob"),
    "GetPeerInfo stopped returning its established live peer row")
assert(Sync.RequestLoadout("missing-parity-loadout") == false
    and Sync.WorkState().recovery == 1,
    "legacy recovery fixture was not retained")
assert(Sync.BroadcastDps("reset-parity", "Alice", 1200, 80, "dummy")
    and Sync.WorkState().outbound > 0,
    "transport reset fixture was not admitted")
liveStats.received = 7
Sync.HandleStatusRequest("Bob", "survives-init")
local logCount = #Sync.EventLog()

Sync.Init(Nexus.Codec, adapter)
assert(Sync.Stats() == liveStats and liveStats.received == 0,
    "Sync stats live identity or reset semantics changed")
assert(Sync.GetPeerInfo("Bob") == peer,
    "recognized peer identity stopped surviving established Init reset")
assert(Sync.WorkState().outbound == 0 and Sync.WorkState().recovery == 0
    and Sync.LastSyncNewCount() == 0 and #Sync.EventLog() >= logCount,
    "Init did not reset accepted session work or changed log retention")
local sentBeforeReply = #H.sentChatMessages
Sync.FlushStatusReply()
assert(#H.sentChatMessages == sentBeforeReply + 1
    and H.sentChatMessages[#H.sentChatMessages].target == "Bob"
    and H.sentChatMessages[#H.sentChatMessages].text:find(
        "^WLRQ|Alice|survives%-init|"),
    "pending diagnostic status replacement/reset timing changed")

local work = Sync.WorkState()
local status, retryAfter, pending, statusWork =
    Sync.GetLeaderboardSyncStatus()
local sentBeforeProjection = #H.sentChatMessages
work.sending = 999
statusWork.total = 999
assert(Sync.WorkState().sending ~= 999
    and select(3, Sync.GetLeaderboardSyncStatus()) ~= 999
    and #H.sentChatMessages == sentBeforeProjection
    and (status == "idle" or status == "syncing" or status == "throttled")
    and type(retryAfter) == "number" and type(pending) == "number",
    "diagnostic projections stopped being defensive and passive")

print("Sync facade=43, sole owners=2, TOC/order/reset/diagnostics parity -- OK")
