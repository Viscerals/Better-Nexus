-- Characterize the established Nexus.Sync facade and its pure/stateful
-- ownership boundary before any internal extraction.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")

local Sync = Nexus.Sync
local clock = 1000
GetTime = function() return clock end
time = function() return 50000 end
UnitName = function() return "Alice" end
UnitLevel = function() return 80 end
H.joinedChannels = {}
H.sentChatMessages = {}

local publicFunctions = {
    "GetPeerInfo", "IsKnownPeer", "WorkState", "ResponseStats", "GetShareStatus",
    "GetDeleteStatus", "OnWorldEntry",
    "GetCompatibilityHashes", "GetCanonicalBuildHashes",
    "GetLegacyBuildHash", "HashCacheStats", "EnsureChannel",
    "ChannelName", "ChannelIndex", "IsConnected", "Stats",
    "IsReceiving", "ReceiveTimeLeft", "LastSyncNewCount", "EventLog",
    "ClearLog", "LogRaw", "RawLog", "LogStats", "LogEvent",
    "NoteTransportNotice", "RequestDataViewRefresh", "RequestLoadout",
    "RequestFullLoadoutSync", "BroadcastBuild", "BroadcastMine",
    "BroadcastBuildSummary", "BroadcastDpsRecord", "BroadcastDps",
    "BroadcastDelete", "HandleIncoming", "RequestSync",
    "GetLeaderboardSyncStatus", "TombstoneCount", "OnUpdate",
    "HandleStatusRequest", "FlushStatusReply", "SendStatusTo", "Init",
}
for _, name in ipairs(publicFunctions) do
    assert(type(Sync[name]) == "function",
        "Sync facade lost callable surface " .. tostring(name))
end

local root = {
    communityBuilds={},
    syncTombstones={
        ["retained-delete"]={stamp=12, author="Alice", future="keep"},
    },
    futureRoot={keep=true},
}
NexusDB = root
local adapter = {
    Slots=function() return {maxSlots=5, activeSlot=2} end,
    Wishlist=function() return {name="Contract Wishlist"} end,
}
Sync.Init(Nexus.Codec, adapter)

assert(Sync.ChannelName() == "wrbuildssync"
    and Sync.ChannelIndex() == 1 and Sync.IsConnected(),
    "Sync channel facade changed its initialized projection")
assert(Sync.ReceiveTimeLeft() == 0 and not Sync.IsReceiving()
    and Sync.LastSyncNewCount() == 0,
    "Sync receive facade changed its initialized defaults")
assert(Sync.TombstoneCount() == 1
    and NexusDB.syncTombstones["retained-delete"].future == "keep",
    "Sync initialization changed tombstone projection or data")

local stats = Sync.Stats()
assert(stats == Sync.Stats(), "Sync.Stats stopped exposing its established live table")
local work = Sync.WorkState()
work.sending = 999
assert(Sync.WorkState().sending ~= 999,
    "Sync.WorkState stopped returning a defensive snapshot")
local response = Sync.ResponseStats()
response.turns = 999
assert(Sync.ResponseStats().turns ~= 999,
    "Sync.ResponseStats stopped returning a defensive snapshot")

local pureBefore = Sync.WorkState()
local pureSent = #H.sentChatMessages
local buildHash, dpsHash = Sync.GetCompatibilityHashes()
local canonicalHash, legacyCanonicalHash = Sync.GetCanonicalBuildHashes()
local legacyHash = Sync.GetLegacyBuildHash()
local hashStats = Sync.HashCacheStats()
local pureAfter = Sync.WorkState()
assert(type(buildHash) == "string" and type(dpsHash) == "string"
    and type(canonicalHash) == "string" and type(legacyCanonicalHash) == "string"
    and type(legacyHash) == "string" and type(hashStats) == "table"
    and pureAfter.outbound == pureBefore.outbound
    and pureAfter.pendingResponses == pureBefore.pendingResponses
    and #H.sentChatMessages == pureSent and NexusDB == root
    and NexusDB.communityBuilds == root.communityBuilds
    and NexusDB.syncTombstones == root.syncTombstones,
    "pure compatibility planning admitted transport or mutated persistence")

-- Shape validation is pure with respect to transport, gameplay, and
-- SavedVariables. Diagnostics/counters may change, but no packet or data owner
-- may be reached for a sender mismatch.
local beforeMalformed = stats.malformedRejected or 0
local beforeWork = Sync.WorkState()
local beforeSent = #H.sentChatMessages
local builds = NexusDB.communityBuilds
local tombstones = NexusDB.syncTombstones
assert(not Sync.HandleIncoming("WLRQ|Declared|0|0|pure-probe", "Different"),
    "sender-mismatched request was accepted")
assert((stats.malformedRejected or 0) == beforeMalformed + 1,
    "sender-mismatched request was not counted")
local afterInvalid = Sync.WorkState()
assert(afterInvalid.outbound == beforeWork.outbound
    and afterInvalid.pendingResponses == beforeWork.pendingResponses
    and afterInvalid.knownPeers == beforeWork.knownPeers
    and #H.sentChatMessages == beforeSent
    and NexusDB == root and NexusDB.communityBuilds == builds
    and NexusDB.syncTombstones == tombstones
    and NexusDB.futureRoot.keep,
    "pure sender validation reached transport or SavedVariables mutation")

local refreshCalls = 0
local previousRefresh = Nexus.ViewRefresh
Nexus.ViewRefresh = {Request=function()
    refreshCalls = refreshCalls + 1
    return "scheduled"
end}
assert(Sync.RequestDataViewRefresh() == "scheduled" and refreshCalls == 1,
    "Sync data-view callback no longer delegates exactly once")
Nexus.ViewRefresh = previousRefresh

assert(Sync.HandleIncoming("WLNP|Bob|1.20.0-beta.1", "Bob")
    and Sync.IsKnownPeer("Bob") and Sync.GetPeerInfo("Bob").name == "Bob",
    "accepted peer projection changed")
assert(Sync.RequestSync(), "manual Sync request did not start")
H.now = H.now + 1.1
Sync.OnUpdate(1.1)
assert(Sync.IsReceiving() and Sync.ReceiveTimeLeft() > 0
    and Sync.LastSyncNewCount() == 0,
    "manual Sync request changed receive-window facade behavior")
local fullOk, fullWhy = Sync.RequestFullLoadoutSync()
assert(fullOk and fullWhy == "already syncing",
    "full-loadout compatibility facade stopped sharing normal reconciliation")
local phase, retryAfter, pending, phaseWork = Sync.GetLeaderboardSyncStatus()
assert(phase == "syncing" and retryAfter == 0 and type(pending) == "number"
    and type(phaseWork) == "table" and phaseWork.total == pending,
    "Sync status projection changed its public result shape")

Sync.LogRaw("contract raw entry")
local log = Sync.EventLog()
assert(#log > 0 and Sync.RawLog()[#Sync.RawLog()].text:find("contract raw entry", 1, true),
    "Sync diagnostic projection omitted an appended event")
local originalText = log[1].text
log[1].text = "mutated snapshot"
assert(Sync.EventLog()[1].text == originalText,
    "Sync diagnostic history stopped returning defensive rows")
local logStats = Sync.LogStats()
assert(type(logStats) == "table" and type(logStats.retained) == "number",
    "Sync diagnostic stats changed shape")
local queuedBeforeClear = Sync.WorkState().outbound
Sync.ClearLog()
assert(#Sync.EventLog() == 0 and Sync.WorkState().outbound == queuedBeforeClear,
    "clearing Sync diagnostics changed accepted queue data")

local statusBefore = #H.sentChatMessages
Sync.HandleStatusRequest("", "ignored")
Sync.FlushStatusReply()
assert(#H.sentChatMessages == statusBefore,
    "empty status requester produced a reply")
Sync.HandleStatusRequest("Bob", "request-7")
Sync.HandleStatusRequest("Carol", "request-8")
Sync.FlushStatusReply()
assert(#H.sentChatMessages == statusBefore + 1
    and H.sentChatMessages[#H.sentChatMessages].kind == "WHISPER"
    and H.sentChatMessages[#H.sentChatMessages].target == "Carol"
    and H.sentChatMessages[#H.sentChatMessages].text:find(
        "^WLRQ|Alice|request%-8|"),
    "status replacement changed target, wire prefix, or flush timing")
assert(not Sync.SendStatusTo(""), "empty explicit status target was accepted")
assert(Sync.SendStatusTo("Dave")
    and H.sentChatMessages[#H.sentChatMessages].target == "Dave"
    and H.sentChatMessages[#H.sentChatMessages].text:find("^WLRQ|Alice|dev|"),
    "explicit status reply changed return or wire behavior")

-- Init is the sole session owner: accepted queue/counter state is reset while
-- SavedVariables identity and tombstones stay bound to their existing tables.
assert(Sync.BroadcastDps("reset-probe", "Alice", 1234, 80, "dummy"),
    "session reset fixture could not admit a packet")
assert(Sync.WorkState().outbound > 0, "session reset fixture has no queued work")
Sync.Init(Nexus.Codec, adapter)
assert(Sync.WorkState().outbound == 0 and Sync.LastSyncNewCount() == 0
    and Sync.Stats().sent == 0 and Sync.Stats().received == 0
    and NexusDB == root and NexusDB.syncTombstones == tombstones
    and Sync.TombstoneCount() == 1,
    "Sync.Init changed session reset or persistence binding behavior")

print("Sync facade, pure validation/planning, callbacks, diagnostics, and session ownership -- OK")
