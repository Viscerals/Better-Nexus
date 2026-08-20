-- Stage 24.1 expected red: saving a Share Build locally is not evidence that
-- the immutable payload entered Sync's bounded outgoing queue.
local H = dofile("tests/harness.lua")

UnitName = function() return "FixtureOwner" end
GetNormalizedRealmName = function() return "FixtureRealm" end
UnitClass = function() return "Mage", "MAGE" end
time = function() return 50000 end

local failures = {}
local function Expect(name, condition, detail)
    if not condition then
        failures[#failures + 1] = name .. ": " .. tostring(detail)
    end
end

local revision = 0
local records = {}
local catalog = {
    Get=function(id) return records[id] end,
    Put=function(build)
        records[build.id] = build
        revision = revision + 1
        return true
    end,
    All=function() return records end,
}
Nexus.Revisions = {
    BUILD_LIBRARY_CHANGED="BUILD_LIBRARY_CHANGED",
    DPS_CHANGED="DPS_CHANGED",
    Get=function(event)
        return event == "BUILD_LIBRARY_CHANGED" and revision or 0
    end,
}
Nexus.DpsCapture = {
    GetEchoKey=function(echoes)
        local parts = {}
        for _, echo in ipairs(echoes or {}) do
            parts[#parts + 1] = tostring(echo.spellId)
                .. "x" .. tostring(echo.stacks or echo.count or 1)
        end
        table.sort(parts)
        return table.concat(parts, ",")
    end,
    GetEchoHash=function(echoes) return "fixture-" .. tostring(#echoes) end,
    BroadcastBestForBuild=function() return false, "no DPS record" end,
}

local adapter = {
    Wishlist=function() return {} end,
    Catalog=function() return {rows={}} end,
}
local selected = {
    slot=1,name="Synthetic Share",class="MAGE",
    echoes={
        {spellId=200100,quality=3,stacks=1},
        {spellId=200102,quality=2,stacks=2},
    },
}

local function NewController()
    local controller = assert(Nexus.CommunityInternals.Controller).New({
        catalog=function() return catalog end,
        filterSettings=function() return {} end,
        notify=function() end,
        refresh=function() end,
    })
    controller.BindAdapter(adapter)
    return controller
end

-- Local persistence succeeds while Sync rejects the newest immutable batch.
Nexus.Sync = {
    BroadcastBuildSummary=function()
        return false, "sync queue full"
    end,
}
local rejected = NewController()
local rejectedOk, rejectedValue, rejectedStatus = rejected.PostCurrentWishlist(
    "Synthetic Queue Rejection", "generated fixture", selected, "MAGE")
local rejectedOutcome = type(rejectedStatus) == "table" and rejectedStatus
    or type(rejectedValue) == "table" and rejectedValue or nil
local rejectedId = rejectedOutcome and rejectedOutcome.id
    or type(rejectedValue) == "string" and rejectedValue or nil
Expect("queue_rejection_preserves_local_save",
    rejectedId and records[rejectedId] ~= nil,
    "the test did not reach a successful local catalog save")
Expect("queue_rejection_is_not_peer_share_success",
    rejectedOk == false or (rejectedOutcome
        and rejectedOutcome.localSaved == true
        and rejectedOutcome.queueAdmitted == false
        and rejectedOutcome.peerStored ~= true),
    "PostCurrentWishlist returned unconditional success without an admission outcome")
Expect("queue_rejection_reason_is_visible",
    rejectedOutcome and rejectedOutcome.queueReason == "sync queue full",
    "the bounded queue rejection was discarded")

-- A successful admission must expose the represented record and queue result
-- without claiming that any peer stored it.
Nexus.Sync = {
    BroadcastBuildSummary=function() return true, "queued" end,
}
local admitted = NewController()
local beforeRevision = revision
local admittedOk, admittedValue, admittedStatus = admitted.PostCurrentWishlist(
    "Synthetic Queue Admission", "generated fixture", selected, "MAGE")
local admittedOutcome = type(admittedStatus) == "table" and admittedStatus
    or type(admittedValue) == "table" and admittedValue or nil
local admittedId = admittedOutcome and admittedOutcome.id
    or type(admittedValue) == "string" and admittedValue or nil
local admittedRecord = admittedId and records[admittedId] or nil
Expect("successful_share_is_admitted", admittedOk == true
    and admittedOutcome and admittedOutcome.queueAdmitted == true,
    "successful return omitted the queue-admission result")
Expect("successful_share_records_identity",
    admittedOutcome and admittedOutcome.id == admittedId
        and admittedRecord and admittedRecord.id == admittedId,
    "generated build identity was not returned with the outcome")
Expect("successful_share_records_class_and_echo_count",
    admittedOutcome and admittedOutcome.class == "MAGE"
        and admittedOutcome.echoCount == 3,
    "selected class or represented Echo count was not returned")
Expect("successful_share_records_revision",
    admittedOutcome and admittedOutcome.buildRevision == beforeRevision + 1
        and revision == beforeRevision + 1,
    "represented BUILD_LIBRARY_CHANGED revision was not returned")
Expect("successful_share_does_not_invent_peer_receipt",
    admittedOutcome and admittedOutcome.peerStored == nil
        and admittedOutcome.confirmation == "unavailable",
    "queue admission was presented as peer storage")

-- Preserve the established direct sender-to-receiver build path as a green
-- control: queue admission, complete chunks, validation, catalog commit, and
-- BUILD_LIBRARY_CHANGED must all occur before projection policy is considered.
local wireClock, wireActor = 1000, "BuildSender"
GetTime = function() return wireClock end
time = function() return 50000 end
UnitName = function() return wireActor end
local function BootBuild(name, db)
    wireActor, NexusDB = name, db
    dofile("core/Revisions.lua")
    dofile("core/BuildCatalog.lua")
    Nexus.BundledBuilds = {
        schemaVersion=1,catalogVersion="stage24-build-fixture",
        sourceVersion="test",generatedAt=0,builds={},
    }
    Nexus.BuildCatalog.Init(NexusDB, Nexus.BundledBuilds)
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
    return Nexus.Sync, Nexus.BuildCatalog, Nexus.Revisions
end
local function Pump(sync, steps)
    for _ = 1, steps do
        wireClock = wireClock + 0.2
        sync.OnUpdate(0.2)
    end
end
local senderDb = {communityBuilds={},syncTombstones={},dpsCapture={}}
local receiverDb = {communityBuilds={},syncTombstones={},dpsCapture={}}
local WireSync, WireCatalog = BootBuild("BuildSender", senderDb)
local wireBuild = {
    id="mine-stage24-generated",title="Generated Transfer Fixture",
    description="generated fixture",author="BuildSender",
    ownerKey="buildsender@fixturerealm",class="MAGE",
    echoes={{spellId=300201,quality=3,stacks=1}},
    postedAt=40000,lastModified=40000,isMine=true,
}
assert(WireCatalog.Put(wireBuild), "sender fixture did not enter its catalog")
assert(WireSync.BroadcastBuild(wireBuild),
    "sender fixture did not enter the outgoing queue")
Pump(WireSync, 80)
local buildMessages, buildChunks = H.sentChatMessages, 0
for _, message in ipairs(buildMessages) do
    if message.text:find("^WLRB|") then buildChunks = buildChunks + 1 end
end
assert(buildChunks > 0, "admitted build produced no complete transfer chunks")
local ReceiverSync, ReceiverCatalog, ReceiverRevisions =
    BootBuild("BuildReceiver", receiverDb)
local buildRevisionBefore = ReceiverRevisions.Get(
    ReceiverRevisions.BUILD_LIBRARY_CHANGED)
assert(ReceiverSync.RequestSync(), "receiver build window did not start")
for _, message in ipairs(buildMessages) do
    ReceiverSync.HandleIncoming(message.text, "BuildSender")
end
local receivedBuild = ReceiverCatalog.Get(wireBuild.id)
assert(receivedBuild and receivedBuild.title == wireBuild.title
    and receivedBuild.echoes and #receivedBuild.echoes == 1,
    "complete sender build was not validated and committed")
assert(ReceiverRevisions.Get(ReceiverRevisions.BUILD_LIBRARY_CHANGED)
        == buildRevisionBefore + 1,
    "receiver catalog commit did not advance BUILD_LIBRARY_CHANGED once")

-- Finish the path at projection policy. Give the received record a synthetic
-- dual-positive eligibility row, then prove that the real projection includes
-- the exact committed ID rather than stopping at persistence.
local receivedFingerprint = Nexus.DpsCapture.GetEchoKey(receivedBuild.echoes)
Nexus.DpsCapture.GetCommunityEligibility=function()
    return {
        [receivedFingerprint]={
            dummy=120000,lk=110000,count=2,best=120000,average=115000,
        },
    }
end
dofile("core/ViewProjections.lua")
Nexus.ViewProjections.Reset()
local projected = Nexus.ViewProjections.Builds({
    scope="all",sortMode="title",currentClassOnly=true,
    qualifiedOnly=true,page=1,pageSize=20,
})
local projectedBuild
for _, row in ipairs(projected) do
    if row.id == wireBuild.id then projectedBuild = row break end
end
assert(projectedBuild and projectedBuild._nexusDps
    and projectedBuild._nexusDps.count == 2,
    "receiver commit did not enter its qualifying Community projection")

-- A saturated bulk response queue cannot block an explicit immutable Share.
-- The reserved control class attempts the original prepared bytes first even
-- if the caller mutates its table after admission.
local retryDb = {communityBuilds={},syncTombstones={},dpsCapture={}}
local RetrySync = BootBuild("RetrySender", retryDb)
local retryLimits = RetrySync.WorkState()
for index = 1, retryLimits.maxOutboundQueue do
    assert(RetrySync.BroadcastDps("stage24-fill-" .. index,
        "RetrySender", 70000 + index, 80, "dummy"),
        "priority fixture did not fill the bounded bulk transport")
end
local immutableBuild = {
    id="mine-stage24-immutable",title="Immutable Before Retry",
    author="RetrySender",ownerKey="retrysender@fixturerealm",class="MAGE",
    echoes={{spellId=300301,quality=3,stacks=1}},
    postedAt=50001,lastModified=50001,isMine=true,
}
local immediate, retryWhy, retryStatus = RetrySync.BroadcastBuildSummary(
    immutableBuild, {retryOnFull=true})
assert(immediate == true and retryWhy == "queued"
    and retryStatus and retryStatus.queueAdmitted == true
    and retryStatus.retryPending == false
    and RetrySync.WorkState().control == 1,
    "explicit Share did not use reserved bounded control admission")
immutableBuild.id = "mine-stage24-mutated"
immutableBuild.title = "Mutated After Admission"
H.joinedChannels[RetrySync.ChannelName()] = 7
wireClock = wireClock + 1.2; RetrySync.OnUpdate(1.2)
local immutablePayload
for _, message in ipairs(H.sentChatMessages) do
    local normalizedWire = message.text:gsub("||", "|")
    local summaryData = normalizedWire:match("^WLBI|[^|]+|([^|]+)$")
    local payload = summaryData and Nexus.Codec.JSONDecode(
        Nexus.Codec.Base64Decode(summaryData)) or nil
    if payload and payload.id == "mine-stage24-immutable" then
        immutablePayload = payload
    end
end
local completed = RetrySync.GetShareStatus("mine-stage24-immutable")
assert(immutablePayload
    and immutablePayload.id == "mine-stage24-immutable"
    and immutablePayload.t == "Immutable Before Retry",
    "priority Share serialized a mutated caller table instead of retained bytes")
assert(completed and completed.sendCompleted == true
    and completed.sent == true and completed.confirmation == "unavailable"
    and completed.peerStored == nil,
    "send attempt was not separated from unavailable peer storage proof")

if #failures > 0 then
    error("EXPECTED RED: Stage 24 Share characterization:\n - "
        .. table.concat(failures, "\n - "))
end

print("Stage 24 truthful Share admission characterization -- OK")
