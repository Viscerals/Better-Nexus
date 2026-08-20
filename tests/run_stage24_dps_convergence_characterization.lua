-- Stage 24.1 expected red: a valid DPS winner held by one peer must be able to
-- converge to another peer through the normal changed-bucket response without
-- weakening direct-owner validation or treating a rejected relay as accepted.
local H = dofile("tests/harness.lua")

local clock = 1000
local actor = "Viewer"
GetTime = function() return clock end
time = function() return 50000 end
UnitName = function() return actor end
GetNormalizedRealmName = function() return "FixtureRealm" end
UnitClass = function() return "Mage", "MAGE" end

local function Boot(name, db)
    actor = name
    NexusDB = db
    Nexus.CommunityBuilds = nil
    dofile("core/Revisions.lua")
    dofile("core/Codec.lua")
    dofile("core/SyncProtocol.lua")
    dofile("core/SyncTransport.lua")
    dofile("core/SyncCompatibility.lua")
    dofile("core/SyncReconciler.lua")
    dofile("core/SyncInbound.lua")
    dofile("core/SyncDiagnostics.lua")
    dofile("core/SyncSession.lua")
    dofile("core/Sync.lua")
    dofile("core/DpsCapture.lua")
    Nexus.DpsCapture.Init({}, Nexus.Sync)
    Nexus.Sync.Init(Nexus.Codec, {})
    H.sentChatMessages = {}
    return Nexus.Sync, Nexus.DpsCapture, Nexus.Revisions
end

local function Pump(sync, steps)
    for _ = 1, steps do
        clock = clock + 0.2
        sync.OnUpdate(0.2)
    end
end

local originDb = {communityBuilds={},syncTombstones={},dpsCapture={}}
local Sync, DPS = Boot("OriginPeer", originDb)
local echoes = {
    {spellId=300101,stacks=1},
    {spellId=300102,stacks=2},
}
local record = {
    v=7,f=DPS.GetEchoKey(echoes),h=DPS.GetEchoHash(echoes),e=echoes,
    c="dummy",d=250000,u=60,t=40000,p="OriginPeer",l=80,k="MAGE",
    o="originpeer@fixturerealm",r="fixturerealm",
}
assert(DPS.ReceiveRecord(record, "OriginPeer"),
    "origin fixture did not accept its direct-owner DPS record")
local originHash = DPS.GetSyncHash()
local outboundRecord = {
    protocolVersion=7,fingerprint=record.f,loadoutHash=record.h,
    echoes=echoes,category="dummy",dps=record.d,duration=record.u,
    ts=record.t,player=record.p,level=record.l,class=record.k,
    ownerKey=record.o,realm=record.r,
}

-- First prove the established direct-owner path end to end: creation,
-- complete chunks, validation, commit, DPS_CHANGED, and matching digest.
assert(Sync.BroadcastDpsRecord(outboundRecord),
    "direct owner did not admit its DPS payload")
Pump(Sync, 60)
local directMessages, directChunks = H.sentChatMessages, 0
for _, message in ipairs(directMessages) do
    if message.text:find("^WLD2|") then directChunks = directChunks + 1 end
end
assert(directChunks > 0, "direct-owner transfer produced no complete chunks")
local directViewerDb = {communityBuilds={},syncTombstones={},dpsCapture={}}
local R
Sync, DPS, R = Boot("DirectViewer", directViewerDb)
dofile("core/ViewProjections.lua")
dofile("ui/Theme.lua")
dofile("ui/Leaderboard.lua")
dofile("core/ViewRefresh.lua")
Nexus.Scheduler.Init()
Nexus.ViewRefresh.Init()
local Leaderboard, Projections = Nexus.Leaderboard, Nexus.ViewProjections
Leaderboard.Init(nil)
Leaderboard.Show("dummy")
local leaderboardFrame = H.frames.NexusLeaderboardFrame
local leaderboardOnUpdate = leaderboardFrame
    and leaderboardFrame.scripts.OnUpdate
assert(type(leaderboardOnUpdate) == "function",
    "Leaderboard fixture did not expose its bounded projection pump")
for _ = 1, 20 do leaderboardOnUpdate(leaderboardFrame, 0.05) end
local initialVirtual = Leaderboard.VirtualStats()
local initialProjection = Projections.Stats().leaderboard
local directBefore = R.Get(R.DPS_CHANGED)
assert(Sync.RequestSync(), "direct viewer receive window did not start")
clock = clock + 1.1
Sync.OnUpdate(1.1)
for _, message in ipairs(directMessages) do
    Sync.HandleIncoming(message.text, "OriginPeer")
end
local directRows = DPS.GetDpsBoard("dummy")
assert(directRows[1] and directRows[1].player == "OriginPeer",
    "direct-owner transfer did not commit")
assert(R.Get(R.DPS_CHANGED) == directBefore + 1,
    "direct-owner commit did not advance DPS_CHANGED exactly once")
assert(DPS.GetSyncHash() == originHash,
    "direct-owner receiver digest did not converge")

-- Tie that accepted revision to the real publication budget. While the
-- receive window is active, only the dirty marker may run. Once it closes,
-- the visible Leaderboard publishes the newly accepted projection once.
assert(Nexus.Scheduler.Pending("ui.data-views.refresh")
    and Nexus.Scheduler.Pending("data-retention.enforce"),
    "accepted DPS revision did not coalesce view refresh and retention work")
clock = clock + 0.05
assert(Nexus.Scheduler.Tick(clock) == 1,
    "active receive refresh did not run its cheap dirty pass")
local activeVirtual = Leaderboard.VirtualStats()
assert(activeVirtual.dataBinds == initialVirtual.dataBinds
    and activeVirtual.refreshDirty,
    "active receive performed a Leaderboard publication")
Nexus.Sync = {
    IsReceiving=function() return false end,
    ReceiveTimeLeft=function() return 0 end,
    GetLeaderboardSyncStatus=function() return "idle",0,0,{} end,
}
clock = clock + 61
assert(Nexus.Scheduler.Tick(clock) == 2,
    "quiet receive boundary did not run deferred refresh and retention")
for _ = 1, 20 do leaderboardOnUpdate(leaderboardFrame, 0.05) end
local quietVirtual = Leaderboard.VirtualStats()
local quietProjection = Projections.Stats().leaderboard
assert(quietVirtual.dataBinds == initialVirtual.dataBinds + 1
    and quietVirtual.deferredRefreshes == 1
    and quietProjection.rebuilds == initialProjection.rebuilds + 1,
    string.format("accepted DPS did not publish exactly one refreshed projection after quiet: binds=%d->%d deferred=%d rebuilds=%d->%d",
        initialVirtual.dataBinds, quietVirtual.dataBinds,
        quietVirtual.deferredRefreshes, initialProjection.rebuilds,
        quietProjection.rebuilds))
assert(Nexus.Scheduler.Tick(clock + 1) == 0,
    "quiet Leaderboard publication duplicated")

-- Now model the supplied scale shape: RelayPeer legitimately holds a row
-- accepted from OriginPeer, while a second viewer has an empty bucket.
local relayDb = originDb
local viewerDb = {communityBuilds={},syncTombstones={},dpsCapture={}}
Sync, DPS = Boot("RelayPeer", relayDb)
local relayHash = DPS.GetSyncHash()
assert(relayHash == originHash,
    "relay's represented store changed the accepted origin digest")

-- The empty viewer emits its real WLRQ digest.
Sync, DPS = Boot("ViewerPeer", viewerDb)
local requestingSync, requestingDps, requestingRevisions = Sync, DPS, Nexus.Revisions
local emptyHash = DPS.GetSyncHash()
assert(emptyHash ~= relayHash, "asymmetric DPS fixture produced matching hashes")
assert(Sync.RequestSync(), "viewer did not admit its Sync request")
Pump(Sync, 20)
local requestMessages = H.sentChatMessages
assert(#requestMessages > 0, "viewer request produced no wire message")

-- The relay processes that request and emits only the differing DPS bucket.
Sync, DPS = Boot("RelayPeer", relayDb)
assert(#DPS.GetDpsBoard("dummy") == 1,
    "relay reboot lost its accepted DPS row before reconciliation")
for _, message in ipairs(requestMessages) do
    Sync.HandleIncoming(message.text, "ViewerPeer")
end
Pump(Sync, 100)
local responseMessages, dpsChunks = H.sentChatMessages, 0
for _, message in ipairs(responseMessages) do
    if message.text:find("^WLD2|") then dpsChunks = dpsChunks + 1 end
end
local relayResponseStats, relayWireStats = Sync.ResponseStats(), Sync.Stats()
assert(relayResponseStats.dpsSerializations == 1
    and relayWireStats.dpsRequestsReceived == 1
    and relayWireStats.dpsRelayOffered == 1,
    "changed DPS bucket did not serialize and offer exactly one row")

-- Matching digests remain silent and do not enumerate/send another record.
H.sentChatMessages = {}
local matchingCount, matchingComplete = DPS.BroadcastAllBuildBests(
    relayHash, nil, {}, 100, {requester="ViewerPeer",
        requestId="matching-digest",bucket=1})
assert(matchingCount == 0 and matchingComplete == true,
    "matching DPS digest did not short-circuit")
Pump(Sync, 20)
for _, message in ipairs(H.sentChatMessages) do
    assert(not message.text:find("^WLD2|"),
        "matching DPS digest emitted a payload")
end

-- Replay any produced response on the requesting peer. Today the responder
-- refuses to serialize a row whose original owner differs from the relay, so
-- the changed bucket yields zero records and the receiver cannot converge.
actor = "ViewerPeer"
NexusDB = viewerDb
Nexus.Sync, Nexus.DpsCapture, Nexus.Revisions = requestingSync,
    requestingDps, requestingRevisions
Sync, DPS, R = requestingSync, requestingDps, requestingRevisions
local beforeRevision = R.Get(R.DPS_CHANGED)
-- A paced changed bucket can legitimately outlive the initial 60-second UI
-- window. Inbound activity for the exact active request must extend quiet-time
-- deferral so the late complete record is still admitted atomically.
clock = clock + 61
for _, message in ipairs(responseMessages) do
    Sync.HandleIncoming(message.text, "RelayPeer")
end
local afterRevision = R.Get(R.DPS_CHANGED)
local viewerWireStats = Sync.Stats()
local received
for _, row in ipairs(DPS.GetDpsBoard("dummy")) do
    if row.player == "OriginPeer" then received = row break end
end

local failures = {}
local function Expect(name, condition, detail)
    if not condition then failures[#failures + 1] = name .. ": " .. detail end
end
Expect("changed_bucket_is_offered", dpsChunks > 0,
    "differing bucket produced zero DPS records from the normal responder")
Expect("changed_bucket_record_is_accepted", received ~= nil,
    dpsChunks == 0 and "no complete responder transfer was admitted"
        or "complete responder transfer was rejected before receiver commit")
Expect("accepted_record_advances_dps_revision",
    received and afterRevision == beforeRevision + 1,
    "DPS_CHANGED stayed " .. tostring(afterRevision - beforeRevision))
Expect("accepted_record_changes_viewer_digest",
    received and DPS.GetSyncHash() == relayHash,
    "viewer digest did not converge to the offered bucket digest")
Expect("relay_context_is_counted_once",
    viewerWireStats.dpsRelayAccepted == 1
        and viewerWireStats.dpsRelayRejected == 0,
    string.format("accepted=%s rejected=%s",
        tostring(viewerWireStats.dpsRelayAccepted),
        tostring(viewerWireStats.dpsRelayRejected)))
Expect("late_active_request_extends_receive_quiet",
    Sync.IsReceiving() and Sync.ReceiveTimeLeft() > 0,
    "bounded inbound activity did not reopen the active request quiet window")
Expect("relay_provenance_remains_non_owner",
    received and received.ownerVerified == false
        and received.relaySender == "RelayPeer",
    "relayed row gained direct-owner authority or lost its relay source")

-- The additive relay context is addressed to the requester and is only live
-- during a receive window. Other peers and unsolicited replay stay closed.
local otherDb = {communityBuilds={},syncTombstones={},dpsCapture={}}
Sync, DPS = Boot("OtherViewer", otherDb)
assert(Sync.RequestSync(), "other-viewer receive window did not start")
for _, message in ipairs(responseMessages) do
    Sync.HandleIncoming(message.text, "RelayPeer")
end
Expect("relay_target_is_exact", #DPS.GetDpsBoard("dummy") == 0,
    "a response addressed to ViewerPeer committed on OtherViewer")

local unsolicitedDb = {communityBuilds={},syncTombstones={},dpsCapture={}}
Sync, DPS = Boot("ViewerPeer", unsolicitedDb)
for _, message in ipairs(responseMessages) do
    Sync.HandleIncoming(message.text, "RelayPeer")
end
Expect("unsolicited_relay_is_rejected", #DPS.GetDpsBoard("dummy") == 0,
    "relay payload committed outside a receive window")

-- Direct sender mismatch remains a hostile boundary. A future relay solution
-- must use explicit compatible provenance rather than accepting arbitrary
-- callers through ReceiveRecord.
local forged = {}
for key, value in pairs(record) do forged[key] = value end
forged.d = 999999
forged.t = 40001
Expect("arbitrary_sender_still_rejected",
    DPS.ReceiveRecord(forged, "UnrelatedPeer") == false,
    "sender identity validation was weakened")

if #failures > 0 then
    error("EXPECTED RED: Stage 24 DPS convergence characterization:\n - "
        .. table.concat(failures, "\n - "))
end

print(string.format(
    "Stage 24 DPS convergence: directChunks=%d relayChunks=%d revision=%d digest=matched -- OK",
    directChunks, dpsChunks, afterRevision - beforeRevision))
