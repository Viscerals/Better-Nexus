-- Stage 36.4 expected red: catalog replacement completeness, summary wire
-- validation, future-schema storage refusal, EBH1 import, and relay
-- provenance must agree at their real owners and fail closed.
local H = dofile("tests/harness.lua")
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

local Codec = assert(Nexus.Codec)
local Catalog = assert(Nexus.BuildCatalog)
local Evidence = assert(Nexus.LoadoutEvidence)
local Sync = assert(Nexus.Sync)
local DPS = assert(Nexus.DpsCapture)

local failures = {}
local desiredChecks, controls = 0, 0
local groupRed = {replacement=0,wlbi=0,storage=0,ebh1=0,provenance=0}

local function Desired(group, ok, label)
    desiredChecks = desiredChecks + 1
    if not ok then
        failures[#failures + 1] = group .. ": " .. label
        groupRed[group] = (groupRed[group] or 0) + 1
    end
end

local function Control(ok, label)
    controls = controls + 1
    assert(ok, "green control failed: " .. tostring(label))
end

local clock = 1000
GetTime = function() return clock end
time = function() return 50000 end
UnitName = function() return "Viewer" end
UnitLevel = function() return 80 end
UnitClass = function() return "Mage", "MAGE" end

local function Pump(seconds, step)
    step = step or 0.2
    local target = clock + seconds
    while clock < target - 0.000001 do
        local elapsed = math.min(step, target - clock)
        clock = clock + elapsed
        Sync.OnUpdate(elapsed)
    end
end

local function SplitWire(text)
    local parts, start = {}, 1
    while true do
        local at = text:find("|", start, true)
        if not at then
            parts[#parts + 1] = text:sub(start)
            return parts
        end
        parts[#parts + 1] = text:sub(start, at - 1)
        start = at + 1
    end
end

local function LatestRequestId()
    for index = #H.sentChatMessages, 1, -1 do
        local wire = H.sentChatMessages[index].text:gsub("||", "|")
        if wire:find("^WLRQ|", 1) then return SplitWire(wire)[5] end
    end
end

local function FindSession()
    for index = 1, 80 do
        local _, value = debug.getupvalue(Sync.GetLeaderboardSyncStatus, index)
        if value == nil then break end
        if type(value) == "table"
            and type(value.QueueLegacyRecovery) == "function"
            and type(value.StatusSnapshot) == "function" then
            return value
        end
    end
end

local Session = assert(FindSession(),
    "could not locate the real SyncSession owned by the Sync facade")
local function RequestedLoadouts()
    for index = 1, 40 do
        local name, value = debug.getupvalue(Session.QueueLegacyRecovery, index)
        if name == nil then break end
        if name == "requestedLoadouts" then return value end
    end
end
assert(RequestedLoadouts(),
    "could not locate SyncSession's bounded loadout retry index")

local function ResetSync(database)
    clock = clock + 100
    NexusDB = database or {communityBuilds={},syncTombstones={}}
    H.sentChatMessages = {}
    H.joinedChannels = {}
    DPS.Init({}, Sync)
    Sync.Init(Codec, {})
    Control(Sync.IsConnected(), "Sync fixture joined its named channel")
    return NexusDB
end

local function Encode(value)
    return Codec.Base64Encode(Codec.JSONEncode(value))
end

local function ActualSender(sender)
    return tostring(sender):find("-", 1, true)
        and sender or (tostring(sender) .. "-Ebonhold")
end

local function DeliverSummary(sender, payload, context)
    local wire = "WLBI|" .. sender .. "|" .. Encode(payload)
    if context then
        wire = wire .. "|" .. context.requester .. "|" .. context.requestId
    end
    return Sync.HandleIncoming(wire, ActualSender(sender))
end

local function DeliverBuild(sender, payload, context)
    local encoded = Encode(payload)
    local chunkSize = 120
    local total = math.ceil(#encoded / chunkSize)
    local result = false
    for index = 1, total do
        local wire = string.format("WLRB|%s|%s|%s|%d/%d|%s", sender,
            tostring(payload.id), tostring(payload.m), index, total,
            encoded:sub((index - 1) * chunkSize + 1, index * chunkSize))
        if context then
            wire = wire .. "|" .. context.requester .. "|" .. context.requestId
        end
        Control(#wire <= 255, "build fixture remains inside the real wire cap")
        result = Sync.HandleIncoming(wire, ActualSender(sender)) or result
    end
    return result
end

local function DeliverDps(sender, transferId, record, context)
    local encoded = Encode(record)
    local chunkSize = 96
    local total = math.max(1, math.ceil(#encoded / chunkSize))
    local result = false
    for index = 1, total do
        local wire = string.format("WLD2|%s|%s|%d/%d|%s", sender,
            transferId,index,total,encoded:sub(
                (index - 1) * chunkSize + 1,index * chunkSize))
        if context then
            wire = wire .. "|" .. context.requester .. "|"
                .. context.requestId .. "|" .. tostring(context.bucket)
        end
        Control(#wire <= 255, "DPS fixture remains inside the real wire cap")
        result = Sync.HandleIncoming(wire, ActualSender(sender)) or result
    end
    return result
end

------------------------------------------------------------------------
-- 1. Same-table catalog replacement completeness.
------------------------------------------------------------------------

local function BuildRecord(id, echoes, stamp)
    return {
        id=id,title="Replacement " .. id,author="Owner",class="MAGE",
        lastModified=stamp or 1,postedAt=stamp or 1,echoes=echoes,
        ownerKey="owner@ebonhold",realm="Ebonhold",ownerVerified=true,
    }
end

local completeEchoes = {{spellId=610001,quality=3,stacks=1}}
local completeFingerprint = "610001x1"
local replacementCases = {
    {name="locked", echoes={{spellId=610002,quality=2,stacks=1,locked=true}},
        reason="cross-role"},
    {name="empty", echoes={}, reason="empty"},
    {name="malformed", echoes={{spellId=0,quality=2,stacks=1}},
        reason="malformed"},
}

for _, case in ipairs(replacementCases) do
    local id = "same-table-" .. case.name
    local db = {communityBuilds={},syncTombstones={}}
    NexusDB = db
    Catalog.Init(db, Nexus.BundledBuilds)
    Control(Catalog.Put(BuildRecord(id, completeEchoes, 1)) == true,
        case.name .. " setup stored complete record")
    local rawIdentity = db.communityBuilds[id]
    local warmSummary = Catalog.GetSummary(id)
    Control(warmSummary and warmSummary.ordinaryComplete == true
            and Catalog.FindExactFingerprintId(completeFingerprint) == id
            and Catalog.SyncState(id).delta ~= nil,
        case.name .. " setup warmed complete summary/index/Sync state")
    Control(Catalog.Put(BuildRecord(id, case.echoes, 2)) == true
            and db.communityBuilds[id] == rawIdentity,
        case.name .. " replacement preserved the legacy SavedVariables table identity")
    local public = Catalog.Get(id)
    local verdict = Evidence.OrdinaryCompleteness(db.communityBuilds[id])
    Control(public and public.ordinaryComplete == false
            and verdict.complete == false and verdict.reason == case.reason,
        case.name .. " authoritative evidence sees the replacement")
    local summary = Catalog.GetSummary(id)
    local syncState = Catalog.SyncState(id)
    Desired("replacement", summary and summary.ordinaryComplete == false
            and summary.ordinaryCompletenessReason == case.reason,
        case.name .. " replacement retained a stale complete summary")
    Desired("replacement",
        Catalog.FindExactFingerprintId(completeFingerprint) ~= id,
        case.name .. " replacement retained the stale exact-fingerprint winner")
    Desired("replacement", syncState and syncState.delta == nil,
        case.name .. " replacement remained Sync-eligible")
end

-- Incomplete verdicts are deliberately not cached. The opposite transition
-- must remain immediately recoverable even though the durable table is reused.
do
    local id = "same-table-recovered"
    local db = {communityBuilds={},syncTombstones={}}
    NexusDB = db
    Catalog.Init(db, Nexus.BundledBuilds)
    Control(Catalog.Put(BuildRecord(id, {}, 1)) == true,
        "incomplete setup stored")
    local rawIdentity = db.communityBuilds[id]
    Control(Catalog.GetSummary(id).ordinaryComplete == false,
        "incomplete setup was characterized before recovery")
    Control(Catalog.Put(BuildRecord(id, completeEchoes, 2)) == true
            and db.communityBuilds[id] == rawIdentity,
        "incomplete-to-complete replacement reused its table")
    local summary = Catalog.GetSummary(id)
    Control(summary and summary.ordinaryComplete == true
            and Catalog.FindExactFingerprintId(completeFingerprint) == id
            and Catalog.SyncState(id).delta ~= nil,
        "incomplete-to-complete replacement recovered every catalog owner")
end

-- Relayed rows are represented data and remain readable, but ownerVerified=false
-- is an explicit anti-amplification boundary on every Sync-facing delta surface.
do
    local id = "unverified-readable"
    local db = {communityBuilds={},syncTombstones={}}
    NexusDB = db
    Catalog.Init(db, Nexus.BundledBuilds)
    local record = BuildRecord(id, completeEchoes, 3)
    record.ownerVerified = false
    record.relaySender = "RelayOne"
    Control(Catalog.Put(record) == true,
        "unverified catalog fixture stored")

    local visible = Catalog.Get(id)
    local all = Catalog.All()
    local summary = Catalog.GetSummary(id)
    local summaries = Catalog.Summaries()
    local state = Catalog.SyncState(id)
    Desired("provenance", visible and visible.ownerVerified == false
            and visible.relaySender == "RelayOne"
            and all[id] and all[id].ownerVerified == false
            and summary and summary.ownerVerified == false
            and summary.ordinaryComplete == true
            and summaries[id] and summaries[id].ownerVerified == false
            and state.visible and state.visible.ownerVerified == false,
        "unverified represented row disappeared from a catalog read surface")
    Desired("provenance", Catalog.FindExactFingerprintId(
            completeFingerprint) == id,
        "unverified represented row disappeared from exact navigation")

    local deltaSummaries = Catalog.DeltaSummaries()
    local deltaSnapshot = Catalog.DeltaSnapshot()
    local cursor, delta, done = Catalog.SyncDeltaNext(nil)
    local nextCursor, nextDelta, nextDone = Catalog.SyncDeltaNext(cursor)
    Desired("provenance", state.delta == nil
            and deltaSummaries[id] == nil and deltaSnapshot[id] == nil,
        "unverified represented row entered a materialized Sync delta")
    Desired("provenance", cursor == id and delta == nil and done == false
            and nextCursor == nil and nextDelta == nil and nextDone == true,
        "unverified represented row entered the bounded Sync delta cursor")
end

------------------------------------------------------------------------
-- 2. WLBI exact-type and bounded schema validation.
------------------------------------------------------------------------

ResetSync()
local wlbiSequence = 0
local function SummaryPayload(overrides)
    wlbiSequence = wlbiSequence + 1
    local payload = {
        id="wlbi-" .. tostring(wlbiSequence),t="Summary",a="WirePeer",
        o="wirepeer@ebonhold",c="MAGE",m=10,h="a1",lh="b2",n=1,x=1,
    }
    for key, value in pairs(overrides or {}) do payload[key] = value end
    return payload
end

local canonical = SummaryPayload()
Control(DeliverSummary("WirePeer", canonical) == true
        and Catalog.Get(canonical.id) ~= nil,
    "canonical exact-type WLBI remains accepted")

local coercible = {
    {name="string timestamp", patch={m="11"}},
    {name="fractional timestamp", patch={m=11.5}},
    {name="oversized timestamp", patch={m=9007199254740992}},
    {name="string count", patch={n="1"}},
    {name="fractional count", patch={n=1.5}},
    {name="numeric fingerprint hash", patch={h=1234}},
    {name="numeric link hash", patch={lh=1234}},
    {name="truthy automatic flag", patch={x=true}},
    {name="string automatic flag", patch={x="1"}},
    {name="invalid class token", patch={c="NOT_A_CLASS"}},
    {name="numeric class token", patch={c=7}},
    {name="unexpected Echo collection", patch={e={{610001,3,1}}}},
    {name="unknown scalar field", patch={futureField="future"}},
    {name="unknown false field", patch={futureFlag=false}},
    {name="comma-only build hash",patch={h=","}},
    {name="comma-separated build hash",patch={h="a1,b2"}},
    {name="empty build hash",patch={h=""}},
    {name="over-width build hash",patch={h="123456789"}},
    {name="comma-only link hash",patch={lh=","}},
    {name="comma-separated link hash",patch={lh="a1,b2"}},
    {name="empty link hash",patch={lh=""}},
    {name="over-width link hash",patch={lh="123456789"}},
}
for _, case in ipairs(coercible) do
    local payload = SummaryPayload(case.patch)
    local before = Sync.Stats().received
    local handled = DeliverSummary("WirePeer", payload)
    Desired("wlbi", handled == false and Catalog.Get(payload.id) == nil
            and Sync.Stats().received == before,
        case.name .. " was normalized into an accepted summary")
end

-- Exercise the protocol validator directly for values JSON cannot spell.
-- The real ingress owner above supplies the same Identity and safety owners;
-- this fixture only avoids JSON's required conversion of NaN/Inf to null.
do
    local identity = assert(Nexus.Identity)
    local protocol = Nexus.SyncInternals.Protocol.New({
        limits={
            maxTransferIdBytes=160,maxHashBytes=192,maxVersionBytes=32,
            maxBuildIdBytes=96,maxBuildEchoes=256,maxRequestIdBytes=96,
            bucketCount=8,maxWireFields=8,
        },
        parseVersion=Nexus.Version.Parse,
        ownerKeyMatchesAuthor=identity.OwnerKeyMatchesAuthor,
        validText=identity.ValidWireText,
        validPeerName=identity.ValidPlayer,
        canonicalOwnerKey=identity.CanonicalOwnerKey,
        isSafeTree=function(value, maxDepth, maxNodes)
            return Codec.IsSafeTree(value, maxDepth, maxNodes)
        end,
    })
    local nonfiniteCases = {
        {name="positive infinite timestamp",key="m",value=math.huge},
        {name="negative infinite timestamp",key="m",value=-math.huge},
        {name="NaN timestamp",key="m",value=0/0},
        {name="positive infinite count",key="n",value=math.huge},
        {name="negative infinite count",key="n",value=-math.huge},
        {name="NaN count",key="n",value=0/0},
    }
    for _, case in ipairs(nonfiniteCases) do
        local payload = SummaryPayload()
        payload[case.key] = case.value
        Desired("wlbi", protocol.ValidateNetworkSummary(payload) == nil,
            case.name .. " passed exact WLBI validation")
    end

    local exactRejects = {
        {name="count above exact maximum",patch={n=30721}},
        {name="lowercase class",patch={c="mage"}},
        {name="mismatched owner key",patch={o="other@ebonhold"}},
        {name="owner key without realm",patch={o="wirepeer"}},
        {name="numeric unknown key",patch={[1]="future"}},
    }
    for _, case in ipairs(exactRejects) do
        local payload = SummaryPayload(case.patch)
        Desired("wlbi", protocol.ValidateNetworkSummary(payload) == nil,
            case.name .. " passed exact WLBI validation")
    end

    local exactAccepts = {
        {name="zero count",patch={n=0}},
        {name="maximum count",patch={n=30720}},
        {name="unknown class token",patch={c="UNKNOWN"}},
    }
    for _, case in ipairs(exactAccepts) do
        local payload = SummaryPayload(case.patch)
        Control(protocol.ValidateNetworkSummary(payload) == payload,
            "WLBI accepts exact " .. case.name)
    end
    local ownerless = SummaryPayload()
    ownerless.o = nil
    Control(protocol.ValidateNetworkSummary(ownerless) == ownerless,
        "WLBI permits an absent optional owner key")

    local function GeneratedScalarHash(value)
        local hash = 5381
        for index = 1, #value do
            hash = ((hash * 33) + value:byte(index)) % 2147483648
        end
        return string.format("%x", hash)
    end
    local generatedHash = GeneratedScalarHash("Stage 36.4 WLBI")
    local generatedPayload = SummaryPayload({
        h=generatedHash,lh=generatedHash,
    })
    Control(#generatedHash >= 1 and #generatedHash <= 8
            and generatedHash:match("^[%x]+$") ~= nil
            and protocol.ValidateNetworkSummary(generatedPayload)
                == generatedPayload
            and DeliverSummary("WirePeer", generatedPayload) == true
            and Catalog.Get(generatedPayload.id) ~= nil,
        "WLBI accepts production-shaped scalar hex hashes through width eight")

    local classTokens = {
        "WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","DEATHKNIGHT",
        "SHAMAN","MAGE","WARLOCK","DRUID",
    }
    for _, classToken in ipairs(classTokens) do
        local payload = SummaryPayload({c=classToken})
        Control(protocol.ValidateNetworkSummary(payload) == payload,
            "WLBI accepts exact class " .. classToken)
    end
end

-- Keep the exact accepted boundaries on the real WLBI ingress path too.
do
    local countZero = SummaryPayload({n=0})
    local countMax = SummaryPayload({n=30720})
    local classUnknown = SummaryPayload({c="UNKNOWN"})
    Control(DeliverSummary("WirePeer", countZero) == true
            and DeliverSummary("WirePeer", countMax) == true
            and DeliverSummary("WirePeer", classUnknown) == true
            and Catalog.Get(countZero.id) and Catalog.Get(countMax.id)
            and Catalog.Get(classUnknown.id),
        "real WLBI ingress accepts exact count and class boundaries")

    local transportMismatch = SummaryPayload({
        a="OtherPeer",o="otherpeer@ebonhold",
    })
    local before = Sync.Stats().received
    Desired("wlbi", DeliverSummary("WirePeer", transportMismatch) == false
            and Catalog.Get(transportMismatch.id) == nil
            and Sync.Stats().received == before,
        "WLBI author escaped transport-sender ownership")
end

local rejectedControls = {
    {name="non-string id", patch={id=123}},
    {name="space in id", patch={id="bad id"}},
    {name="non-string title", patch={t=123}},
    {name="non-string author", patch={a=123}},
    {name="malformed owner", patch={o=true}},
    {name="non-hex hash", patch={h="not-hex"}},
    {name="negative count", patch={n=-1}},
    {name="collection count", patch={n={1}}},
    {name="boolean timestamp", patch={m=true}},
}
for _, case in ipairs(rejectedControls) do
    local payload = SummaryPayload(case.patch)
    local before = Sync.Stats().received
    Control(DeliverSummary("WirePeer", payload) == false
            and Catalog.Get(payload.id) == nil
            and Sync.Stats().received == before,
        "WLBI already rejects " .. case.name)
end

------------------------------------------------------------------------
-- 3. Future-schema storage refusal propagation and byte preservation.
------------------------------------------------------------------------

local futureDb = {
    buildCatalog={schemaVersion=99,catalogVersion="future",futureMeta={7,8,9}},
    communityBuilds={
        ["future-existing"]={id="future-existing",title="Future Existing",
            author="FuturePeer",ownerKey="futurepeer@ebonhold",
            class="MAGE",lastModified=5,postedAt=5,
            echoes={{spellId=620001,quality=3,stacks=1}},
            ownerVerified=true,futureRow={opaque="keep"}},
        ["future-mine"]={id="future-mine",title="Future Mine",
            author="Viewer",ownerKey="viewer@ebonhold",class="MAGE",
            lastModified=5,postedAt=5,isMine=true,
            echoes={{spellId=620004,quality=3,stacks=1}},
            ownerVerified=true,futureRow={opaque="keep"}},
        opaque={futureShape={left="untouched",right={1,2,3}}},
    },
    futureRoot={bytes="must remain byte-for-byte"},
}
-- Snapshot the raw future-owned root before any older owner binds it. A
-- read-only catalog cannot license additive siblings that its schema does not
-- understand, even when those siblings are familiar to this older client.
local futureBytes = Codec.JSONEncode(futureDb)
clock = clock + 100
NexusDB = futureDb
H.sentChatMessages = {}
H.joinedChannels = {}
Sync.Init(Codec, {})
Control(Sync.IsConnected(),
    "future-schema Sync fixture joined its named channel")
Control(Catalog.Status().readOnly == true,
    "future catalog bound read-only before wire probes")
Desired("storage", futureDb.loadoutEvidence == nil
        and futureDb.syncTombstones == nil
        and Codec.JSONEncode(futureDb) == futureBytes,
    "Sync.Init created older-owned siblings in a future catalog root")
Control(Sync.RequestSync() == true, "future-schema manual request queued")
Pump(1.2)
local futureRequestId = LatestRequestId()
Control(type(futureRequestId) == "string"
        and futureRequestId:sub(1,3) == "c1-",
    "future-schema fixture reached a marked active request")

local futureSummary = {
    id="future-summary",t="Future Summary",a="FuturePeer",
    o="futurepeer@ebonhold",c="MAGE",m=10,h="c1",n=1,
}
local beforeReceived = Sync.Stats().received
local beforeRequestNew = Sync.Stats().requestNew
local beforeStorageRejected = Sync.Stats().storageRejected
local beforeMalformedRejected = Sync.Stats().malformedRejected
local summaryHandled = DeliverSummary("FuturePeer", futureSummary,
    {requester="Viewer-Ebonhold",requestId=futureRequestId})
local summaryStats = Sync.Stats()
Desired("storage", summaryHandled == false
        and Catalog.Get(futureSummary.id) == nil,
    "future-schema WLBI reported acceptance after Catalog.Put refusal")
Desired("storage", summaryStats.received == beforeReceived
        and summaryStats.requestNew == beforeRequestNew
        and summaryStats.requestRejected >= 1
        and summaryStats.requestLastReason == "storage",
    "future-schema WLBI contaminated accepted/request diagnostics")
Desired("storage", summaryStats.storageRejected == beforeStorageRejected + 1
        and summaryStats.malformedRejected == beforeMalformedRejected,
    "future-schema WLBI conflated storage refusal with malformed input")
Desired("storage", RequestedLoadouts()[futureSummary.id] == nil,
    "future-schema rejected WLBI created a loadout retry for unstored data")

local queuedRecovery = Sync.RequestLoadout("future-full")
local recoveryBefore = Sync.WorkState().recovery
local recoveryIndex = RequestedLoadouts()
Control(queuedRecovery == false and recoveryBefore >= 1
        and type(recoveryIndex["future-full"]) == "table",
    "future full-loadout retry is retained by the bounded recovery owner (depth="
        .. tostring(recoveryBefore) .. ", indexed="
        .. tostring(type(recoveryIndex["future-full"])) .. ")")
beforeReceived = Sync.Stats().received
beforeStorageRejected = Sync.Stats().storageRejected
beforeMalformedRejected = Sync.Stats().malformedRejected
local fullHandled = DeliverBuild("FuturePeer", {
    id="future-full",t="Future Full",a="FuturePeer",
    o="futurepeer@ebonhold",c="MAGE",m=11,d="future",e={{620002,3,1}},
})
Desired("storage", fullHandled == false
        and Catalog.Get("future-full") == nil,
    "future-schema full build reported acceptance after Catalog.Put refusal")
Desired("storage", Sync.Stats().received == beforeReceived,
    "future-schema full build incremented the accepted lifetime count")
Desired("storage", Sync.Stats().storageRejected == beforeStorageRejected + 1
        and Sync.Stats().malformedRejected == beforeMalformedRejected,
    "future-schema full build conflated storage refusal with malformed input")
Desired("storage", Sync.WorkState().recovery == recoveryBefore
        and type(RequestedLoadouts()["future-full"]) == "table",
    "future-schema full build cleared its retry/loadout owner")

local beforeUpdated = Sync.Stats().updated
beforeReceived = Sync.Stats().received
beforeStorageRejected = Sync.Stats().storageRejected
beforeMalformedRejected = Sync.Stats().malformedRejected
DeliverBuild("FuturePeer", {
    id="future-existing",t="Future Changed",a="FuturePeer",
    o="futurepeer@ebonhold",c="MAGE",m=6,d="future",e={{620003,3,1}},
})
Desired("storage", Sync.Stats().updated == beforeUpdated
        and Sync.Stats().received == beforeReceived,
    "future-schema rejected update incremented updated/received counts")
Desired("storage", Sync.Stats().storageRejected == beforeStorageRejected + 1
        and Sync.Stats().malformedRejected == beforeMalformedRejected,
    "future-schema rejected update was diagnosed as malformed")

local outboundBeforeDelete = Sync.WorkState().outbound
beforeStorageRejected = Sync.Stats().storageRejected
local deleteQueued, _, deleteStatus =
    Sync.BroadcastDelete(Catalog.Get("future-mine"))
Desired("storage", deleteQueued == false
        and type(deleteStatus) == "table"
        and deleteStatus.outcome == "rejected"
        and deleteStatus.terminal == true
        and Sync.WorkState().outbound == outboundBeforeDelete
        and Catalog.Get("future-mine") ~= nil
        and Sync.Stats().storageRejected == beforeStorageRejected + 1,
    "future-schema local delete queued bytes after tombstone storage refusal")

local futureDeleteController = Nexus.CommunityInternals.Controller.New({
    catalog=function() return Catalog end,
    notify=function() end,
})
futureDeleteController.Select("future-mine")
local beforeControllerDeleteBytes = Codec.JSONEncode(futureDb)
local controllerDeleted, controllerDeleteOutcome =
    futureDeleteController.DeleteBuild("future-mine")
Desired("storage", controllerDeleted == false
        and type(controllerDeleteOutcome) == "table"
        and controllerDeleteOutcome.localRemoved == false
        and type(controllerDeleteOutcome.storageReason) == "string"
        and type(controllerDeleteOutcome.queueReason) == "string"
        and futureDeleteController.SelectedId() == "future-mine"
        and Catalog.Get("future-mine") ~= nil
        and Codec.JSONEncode(futureDb) == beforeControllerDeleteBytes,
    "future-schema Community delete reported removal after storage refusal")

beforeStorageRejected = Sync.Stats().storageRejected
beforeMalformedRejected = Sync.Stats().malformedRejected
local inboundDelete = Sync.HandleIncoming(table.concat({
    "WLRD","FuturePeer","future-existing","7","FuturePeer",
    "Viewer-Ebonhold",futureRequestId,
}, "|"), "FuturePeer-Ebonhold")
Desired("storage", inboundDelete == false
        and Catalog.Get("future-existing") ~= nil
        and Sync.Stats().storageRejected == beforeStorageRejected + 1
        and Sync.Stats().malformedRejected == beforeMalformedRejected
        and Sync.Stats().requestLastReason == "storage",
    "future-schema inbound delete reported acceptance after storage refusal")

Desired("storage", futureDb.loadoutEvidence == nil,
    "future-schema traffic created a loadoutEvidence sibling")
Desired("storage", futureDb.syncTombstones == nil,
    "future-schema traffic created a syncTombstones sibling")
Desired("storage", futureDb.dpsCapture == nil,
    "future-schema traffic created a dpsCapture sibling")

local function FutureDpsRecord(player, spellId, score, stamp, relayContext)
    local echoes = {{spellId=spellId,quality=3,stacks=1}}
    local record = {
        v=7,f=DPS.GetEchoKey(echoes),h=DPS.GetEchoHash(echoes),e=echoes,
        c="dummy",d=score,u=30,t=stamp,p=player,l=80,k="MAGE",
        o=player:lower() .. "@ebonhold",r="ebonhold",
    }
    if relayContext then
        record.x = {n=relayContext.requester,i=relayContext.requestId,
            b=relayContext.bucket}
    end
    return record
end

local directPlayer = "FutureDpsDirect"
local directBucket = DPS.SyncBucket("dummy", directPlayer)
local syncBeforeDps = Sync.Stats()
local directAcceptedBefore = syncBeforeDps.dpsDirectAccepted
local directRejectedBefore = syncBeforeDps.dpsDirectRejected
local directStorageBefore = syncBeforeDps.storageRejected
local directStored = DeliverDps(directPlayer,"future-dps-direct",
    FutureDpsRecord(directPlayer,620100,260000,50001),
    {requester="Viewer-Ebonhold",requestId=futureRequestId,bucket=directBucket})
local directStats = Sync.Stats()
Desired("storage", directStored == false
        and directStats.dpsDirectAccepted == directAcceptedBefore
        and directStats.dpsDirectRejected == directRejectedBefore + 1
        and directStats.storageRejected == directStorageBefore + 1
        and directStats.requestLastReason == "storage"
        and DPS.GetCharacterBest("dummy", directPlayer) == nil
        and futureDb.dpsCapture == nil,
    "future-schema direct DPS ingress reported transient storage as accepted")

local relayPlayer = "FutureDpsRelay"
local relayContext = {requester="Viewer-Ebonhold",requestId=futureRequestId,
    bucket=DPS.SyncBucket("dummy", relayPlayer)}
syncBeforeDps = Sync.Stats()
local relayAcceptedBefore = syncBeforeDps.dpsRelayAccepted
local relayRejectedBefore = syncBeforeDps.dpsRelayRejected
local relayStorageBefore = syncBeforeDps.storageRejected
local relayStored = DeliverDps("FutureRelay","future-dps-relay",
    FutureDpsRecord(relayPlayer,620101,270000,50002,relayContext),
    relayContext)
local relayStats = Sync.Stats()
Desired("storage", relayStored == false
        and relayStats.dpsRelayAccepted == relayAcceptedBefore
        and relayStats.dpsRelayRejected == relayRejectedBefore + 1
        and relayStats.storageRejected == relayStorageBefore + 1
        and relayStats.requestLastReason == "storage"
        and DPS.GetCharacterBest("dummy", relayPlayer) == nil
        and futureDb.dpsCapture == nil,
    "future-schema relayed DPS ingress reported transient storage as accepted")

Desired("storage", Codec.JSONEncode(futureDb) == futureBytes
        and futureDb.communityBuilds["future-existing"].futureRow.opaque == "keep"
        and futureDb.communityBuilds.opaque.futureShape.left == "untouched",
    "future-schema traffic preserved every unknown SavedVariables byte")

-- A future owner may already have a DPS subtree with an opaque shape. The
-- older DPS and Sync readers must use transient empty views rather than
-- normalizing that real table during initialization or hash/request traffic.
do
    local opaqueDpsDb = {
        buildCatalog={
            schemaVersion=99,catalogVersion="future-dps",
            futureMeta={owner="newer client"},
        },
        communityBuilds={},
        dpsCapture={
            schemaVersion=99,
            characterBest={futureCategory={opaque={1,2,3}}},
            futureBuckets={left="keep",right={4,5,6}},
            opaqueScalar="do not normalize",
        },
        futureRoot={dps="owned by newer schema"},
    }
    local opaqueDpsIdentity = opaqueDpsDb.dpsCapture
    local opaqueDpsBytes = Codec.JSONEncode(opaqueDpsDb)
    clock = clock + 100
    NexusDB = opaqueDpsDb
    H.sentChatMessages = {}
    H.joinedChannels = {}
    DPS.Init({}, Sync)
    Desired("storage", opaqueDpsDb.dpsCapture == opaqueDpsIdentity
            and Codec.JSONEncode(opaqueDpsDb) == opaqueDpsBytes,
        "DPS.Init normalized an opaque future-owned DPS table")
    Sync.Init(Codec, {})
    Control(Catalog.Status().readOnly == true and Sync.IsConnected(),
        "opaque future-DPS fixture reached connected read-only Sync")
    Control(Sync.RequestSync() == true,
        "opaque future-DPS fixture queued a bounded Sync request")
    Pump(1.2)
    Desired("storage", opaqueDpsDb.dpsCapture == opaqueDpsIdentity
            and opaqueDpsDb.loadoutEvidence == nil
            and opaqueDpsDb.syncTombstones == nil
            and Codec.JSONEncode(opaqueDpsDb) == opaqueDpsBytes,
        "Sync request traffic mutated an opaque future-owned DPS table")
end

-- A future owner may also already have a tombstone table whose fields resemble
-- this client's recovery markers. Older Sync must not bind, clear, or replay
-- that opaque table merely because one row contains pending=true.
do
    local opaqueTombstoneDb = {
        buildCatalog={
            schemaVersion=99,catalogVersion="future-tombstones",
            futureMeta={owner="newer client"},
        },
        communityBuilds={},
        syncTombstones={
            ["future-pending"]={
                stamp=71000,author="Viewer",pending=true,
                futureState={attempt=99,opaque={1,2,3}},
            },
        },
        futureRoot={tombstones="owned by newer schema"},
    }
    local opaqueTombstoneIdentity = opaqueTombstoneDb.syncTombstones
    local opaqueTombstoneBytes = Codec.JSONEncode(opaqueTombstoneDb)
    clock = clock + 100
    NexusDB = opaqueTombstoneDb
    H.sentChatMessages = {}
    H.joinedChannels = {}
    Sync.Init(Codec, {})
    Control(Catalog.Status().readOnly == true and Sync.IsConnected(),
        "opaque future-tombstone fixture reached connected read-only Sync")
    Pump(2.4)
    Desired("storage",
        opaqueTombstoneDb.syncTombstones == opaqueTombstoneIdentity
            and Sync.TombstoneCount() == 0
            and Sync.WorkState().pendingDeletes == 0
            and #H.sentChatMessages == 0
            and Codec.JSONEncode(opaqueTombstoneDb) == opaqueTombstoneBytes,
        "Sync recovery mutated or replayed an opaque future tombstone table")
end

------------------------------------------------------------------------
-- 4. EBH1 all-or-nothing decode/import and Nexus locked round-trip.
------------------------------------------------------------------------

local lockedWire = Codec.EncodeEBH1({
    {spellId=630001,quality=3,stacks=2},
    {spellId=630002,quality=2,stacks=1,locked=true},
}, "MAGE", "Nexus Locked")
local lockedDecoded = Codec.DecodeEBH1(lockedWire)
Control(lockedWire == "EBH1:630001.3.2,630002.2.1.1:MAGE:Nexus Locked"
        and lockedDecoded and #lockedDecoded.entries == 2
        and lockedDecoded.entries[1].locked == nil
        and lockedDecoded.entries[2].locked == true
        and lockedDecoded.class == "MAGE"
        and lockedDecoded.name == "Nexus Locked",
    "Nexus three/four-field EBH1 preserves ordinary and locked roles")
Control(Codec.DecodeEBH1("not-ebh1") == nil
        and Codec.DecodeEBH1("EBH1::MAGE:Empty") == nil
        and Codec.DecodeEBH1("EBH1:630001.3.1:MAGE") == nil,
    "wholly malformed/empty EBH1 remains rejected")

local manyParts = {}
for index = 1, 121 do
    manyParts[index] = tostring(640000 + index) .. ".1.1"
end
local malformedEbh1 = {
    {name="mixed valid and malformed", value="EBH1:630001.3.1,bad:MAGE:Mixed"},
    {name="empty middle entry", value="EBH1:630001.3.1,,630002.2.1:MAGE:Gap"},
    {name="truncated subset", value="EBH1:630001.3.1,630002.2:MAGE:Truncated"},
    {name="zero spell id", value="EBH1:0.3.1:MAGE:Range"},
    {name="out-of-range quality", value="EBH1:630001.999.1:MAGE:Range"},
    {name="zero stacks", value="EBH1:630001.3.0:MAGE:Range"},
    {name="invalid lock marker", value="EBH1:630001.3.1.2:MAGE:Lock"},
    {name="trailing damaged subset", value="EBH1:630001.3.1,damage:MAGE:Damage"},
    {name="over-limit entry count", value="EBH1:" .. table.concat(manyParts, ",")
        .. ":MAGE:Too Many"},
}
for _, case in ipairs(malformedEbh1) do
    Desired("ebh1", Codec.DecodeEBH1(case.value) == nil,
        case.name .. " was partially decoded")
end

do
    local ordinary79 = Codec.DecodeEBH1(
        "EBH1:631001.3.79:MAGE:Ordinary 79")
    Control(ordinary79 and #ordinary79.entries == 1
            and ordinary79.entries[1].stacks == 79
            and ordinary79.entries[1].locked == nil,
        "EBH1 accepts the exact 79-copy ordinary budget")
    Desired("ebh1", Codec.DecodeEBH1(
            "EBH1:631001.3.80:MAGE:Ordinary 80") == nil,
        "EBH1 accepted an 80-copy ordinary loadout")

    local lockedSixParts = {}
    for index = 1, 6 do
        lockedSixParts[index] = tostring(631100 + index) .. ".2.1.1"
    end
    local lockedSixWire = "EBH1:" .. table.concat(lockedSixParts, ",")
        .. ":MAGE:Locked 6"
    local lockedSix = Codec.DecodeEBH1(lockedSixWire)
    Control(lockedSix and #lockedSix.entries == 6
            and lockedSix.entries[1].locked == true
            and lockedSix.entries[6].locked == true,
        "EBH1 accepts the exact six-copy locked budget")
    lockedSixParts[7] = "631107.2.1.1"
    Desired("ebh1", Codec.DecodeEBH1("EBH1:"
            .. table.concat(lockedSixParts, ",") .. ":MAGE:Locked 7") == nil,
        "EBH1 accepted a seventh locked copy")

    local countedLocked = Codec.DecodeEBH1(
        "EBH1:631110.2.2.1,631110.2.2.1,631110.2.2.1:MAGE:Counted")
    Control(countedLocked and #countedLocked.entries == 3
            and countedLocked.entries[1].stacks == 2
            and countedLocked.entries[3].locked == true,
        "EBH1 preserves duplicate exact locked rows totaling six copies")
    Desired("ebh1", Codec.DecodeEBH1(
            "EBH1:631110.2.2.1,631110.2.2.1,631110.2.2.1,631111.2.1.1:MAGE:Seven") == nil,
        "EBH1 accepted seven locked copies across four rows")

    local typedOverlap = Codec.DecodeEBH1(
        "EBH1:631200.3.2,631200.2.1.1:MAGE:Typed Overlap")
    Control(typedOverlap and #typedOverlap.entries == 2
            and typedOverlap.entries[1].spellId == 631200
            and typedOverlap.entries[1].locked == nil
            and typedOverlap.entries[2].spellId == 631200
            and typedOverlap.entries[2].locked == true,
        "EBH1 keeps same-ID ordinary and locked roles distinct")
    Desired("ebh1", Codec.DecodeEBH1(
            "EBH1:631200.3.1,631200.2.1:MAGE:Duplicate Ordinary") == nil,
        "EBH1 accepted a duplicate ordinary identity")
end

do
    local bounded = "EBH1:631300.3.1:MAGE:Bounded"
    local exactName = "EBH1:631300.3.1:MAGE:" .. string.rep("N", 120)
    Control(Codec.DecodeEBH1(exactName) ~= nil,
        "EBH1 accepts an exact 120-byte name")
    Desired("ebh1", Codec.DecodeEBH1(
            "EBH1:631300.3.1:MAGE:" .. string.rep("N", 121)) == nil,
        "EBH1 accepted a 121-byte name")
    local colonNameWire = Codec.EncodeEBH1({
        {spellId=631300,quality=3,stacks=1},
    }, "MAGE", "Name:Extra")
    local colonNameDecoded = Codec.DecodeEBH1(colonNameWire)
    Desired("ebh1", colonNameWire == "EBH1:631300.3.1:MAGE:Name:Extra"
            and colonNameDecoded and colonNameDecoded.name == "Name:Extra"
            and colonNameDecoded.class == "MAGE"
            and #colonNameDecoded.entries == 1,
        "EBH1 failed a Nexus round-trip with a colon in the build name")
    Desired("ebh1", Codec.DecodeEBH1(
            "EBH1:631300.3.1:MAGE:Bad" .. string.char(1) .. "Name") == nil,
        "EBH1 accepted an embedded control byte")
    Desired("ebh1", Codec.DecodeEBH1("\t" .. bounded) == nil
            and Codec.DecodeEBH1(bounded .. "\n") == nil,
        "EBH1 trimmed boundary control bytes into accepted input")

    local exactWireBytes = bounded
        .. string.rep(" ", 8192 - #bounded)
    local overWireBytes = exactWireBytes .. " "
    Control(#exactWireBytes == 8192
            and Codec.DecodeEBH1(exactWireBytes) ~= nil,
        "EBH1 accepts an exact 8192-byte raw input")
    Desired("ebh1", #overWireBytes == 8193
            and Codec.DecodeEBH1(overWireBytes) == nil,
        "EBH1 trimmed an over-limit raw input below the byte cap")
end

-- Exercise the real editor owner: a mixed payload must not reset the current
-- draft before the decoder has established the whole input is valid.
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("core/WishlistModel.lua")
dofile("core/WishlistController.lua")
dofile("ui/WishlistRenderer.lua")
dofile("ui/WishlistEditor.lua")

UnitName = function() return "Editor" end
NexusDB = {
    settingsVersion=2,settings={},chars={Editor={}},communityBuilds={},
}
Nexus.Store.Init()
Nexus.GameAdapter.Init({}, Nexus.Store)
H.DeliverSlots({
    [1]={slot=1,name="Active",verified=true,
        echoes={{spellId=630010,quality=2,stacks=1}}},
}, 1)
Nexus.Panel = {
    AttachMenuFrame=function() end,CloseOtherWindows=function() end,
}
Nexus.Theme = {StyleWindow=function() end,StyleTree=function() end}
Nexus.WishlistOverlay = {
    IsShown=function() return false end,Show=function() end,Hide=function() end,
    IsLocked=function() return false end,ToggleLock=function() end,
    GetScale=function() return 1 end,SetScale=function() end,
    ResetPosition=function() end,
}
local Editor = Nexus.WishlistEditor
Editor.Init(Nexus.GameAdapter, Nexus.Model)
Control(Editor.OpenForCandidate({title="Keep Draft",echoes={
        {spellId=630011,quality=3,stacks=1},
        {spellId=630012,quality=2,stacks=1},
    }}) == true,
    "editor established the pre-import draft")
local draftBefore = Editor.DebugDraftState()
Editor.ImportEBH1String("EBH1:630013.3.1,bad:MAGE:Partial", "Bad Import")
local draftAfter = Editor.DebugDraftState()
Desired("ebh1", draftAfter.pending == draftBefore.pending
        and draftAfter.pendingLock == draftBefore.pendingLock,
    "mixed EBH1 partially replaced the active editor draft")

local editorLockedWire = Codec.EncodeEBH1({
    {spellId=630001,quality=3,stacks=1},
    {spellId=630002,quality=2,stacks=1,locked=true},
}, "MAGE", "Locked Roundtrip")
Editor.ImportEBH1String(editorLockedWire, "Locked Roundtrip")
local imported = Editor.DebugDraftState()
Control(imported.pending == 1 and imported.pendingLock == 1
        and imported.scrollOffset == 0 and imported.pickOffset == 0,
    "real editor imported the complete Nexus ordinary/locked round-trip")

------------------------------------------------------------------------
-- 5. Direct-owner versus unverified-relay provenance.
------------------------------------------------------------------------

UnitName = function() return "Viewer" end
local provenanceDb = ResetSync({communityBuilds={},syncTombstones={},dpsCapture={}})
local function BuildPayload(id, title, author, stamp, spellId)
    return {id=id,t=title,a=author,o=author:lower() .. "@ebonhold",
        c="MAGE",m=stamp,d="provenance",e={{spellId,3,1}}}
end

DeliverBuild("RelayOne", BuildPayload(
    "relay-build", "Relay Build", "Origin", 1, 650001))
local relayBuild = Catalog.Get("relay-build")
Control(relayBuild and relayBuild.ownerVerified == false
        and relayBuild.author == "Origin",
    "first build relay remains unverified ambient storage")
local relayedBroadcast, relayedBroadcastWhy = Sync.BroadcastBuild(relayBuild)
Desired("provenance", relayedBroadcast == false
        and relayedBroadcastWhy == "relay unauthorized",
    "unverified relayed build was admitted for another mesh hop")

DeliverBuild("RelayTwo", BuildPayload(
    "relay-build", "Relay Overwrite", "Origin", 2, 650002))
local relayAfterConflict = Catalog.Get("relay-build")
Control(relayAfterConflict.title == "Relay Build"
        and relayAfterConflict.ownerVerified == false,
    "a second relay cannot overwrite an existing unverified build")

DeliverBuild("Origin", BuildPayload(
    "relay-build", "Owner Verified", "Origin", 2, 650002))
local verifiedBuild = Catalog.Get("relay-build")
Control(verifiedBuild and verifiedBuild.ownerVerified == true
        and verifiedBuild.author == "Origin"
        and verifiedBuild.title == "Owner Verified",
    "the exact direct owner can replace relayed provenance")
Control(Sync.BroadcastBuild(verifiedBuild) == true,
    "direct-owner build remains publishable")
DeliverBuild("RelayTwo", BuildPayload(
    "relay-build", "Forged After Verify", "Origin", 3, 650003))
Control(Catalog.Get("relay-build").title == "Owner Verified",
    "relay cannot overwrite direct-owner authority")

DeliverBuild("RelayOne", BuildPayload(
    "relay-takeover", "Relayed Origin", "Origin", 1, 650010))
DeliverBuild("Thief", BuildPayload(
    "relay-takeover", "Claimed By Thief", "Thief", 2, 650011))
local takeover = Catalog.Get("relay-takeover")
Desired("provenance", takeover and takeover.author == "Origin"
        and takeover.ownerVerified == false,
    "different direct sender promoted an unverified relayed ID to verified ownership")

DPS.Init({}, Sync)
local dpsEchoes = {{spellId=650100,stacks=1}}
local dpsFingerprint = DPS.GetEchoKey(dpsEchoes)
local dpsHash = DPS.GetEchoHash(dpsEchoes)
local function DpsRecord(player, score, stamp)
    return {v=7,f=dpsFingerprint,h=dpsHash,e=dpsEchoes,c="dummy",
        d=score,u=30,t=stamp,p=player,l=80,k="MAGE",
        o=player:lower() .. "@ebonhold",r="ebonhold"}
end
Control(DPS.ReceiveRelayedRecord(
        DpsRecord("DpsOrigin",250000,100),"RelayOne-Ebonhold") == true,
    "first DPS relay fills an empty unverified slot")
local firstRelayedDps = DPS.GetCharacterBest("dummy", "DpsOrigin")
Control(firstRelayedDps and firstRelayedDps.ownerVerified == false
        and firstRelayedDps.relaySender == "RelayOne-Ebonhold",
    "first DPS relay retains non-owner provenance")
local relayConflictEchoes = {{spellId=650101,quality=3,stacks=2}}
local relayConflictRecord = {
    v=7,f=DPS.GetEchoKey(relayConflictEchoes),
    h=DPS.GetEchoHash(relayConflictEchoes),e=relayConflictEchoes,
    c="dummy",d=300000,u=30,t=101,p="DpsOrigin",l=80,k="MAGE",
    o="dpsorigin@ebonhold",r="ebonhold",
}
local evidenceBeforeSecondRelay = Codec.JSONEncode(Evidence.Snapshot())
local rootBeforeSecondRelay = Codec.JSONEncode(provenanceDb)
local secondRelayAccepted = DPS.ReceiveRelayedRecord(
    relayConflictRecord,"RelayTwo-Ebonhold")
local afterSecondRelay = DPS.GetCharacterBest("dummy", "DpsOrigin")
Desired("provenance", secondRelayAccepted == false
        and afterSecondRelay and afterSecondRelay.dps == 250000
        and afterSecondRelay.relaySender == "RelayOne-Ebonhold"
        and afterSecondRelay.ownerVerified == false
        and Codec.JSONEncode(Evidence.Snapshot()) == evidenceBeforeSecondRelay
        and Codec.JSONEncode(provenanceDb) == rootBeforeSecondRelay,
    "second DPS relay overwrote provenance or interned rejected evidence")

Control(DPS.ReceiveRecord(
        DpsRecord("DpsOrigin",350000,102),"DpsOrigin-Ebonhold") == true,
    "direct DPS owner supersedes unverified relay provenance")
local directDps = DPS.GetCharacterBest("dummy", "DpsOrigin")
Control(directDps and directDps.ownerVerified == true
        and directDps.relaySender == nil and directDps.dps == 350000,
    "direct DPS owner retained verified authority")
Control(DPS.ReceiveRelayedRecord(
        DpsRecord("DpsOrigin",400000,103),"RelayThree-Ebonhold") == false
        and DPS.GetCharacterBest("dummy", "DpsOrigin").dps == 350000,
    "DPS relay cannot overwrite direct-owner authority")

-- The historical nil-sender API is a local/non-wire compatibility path. It
-- may improve another unverified row for the same player, but it must never
-- displace evidence that arrived directly from the verified owner.
Control(DPS.ReceiveRecord(
        DpsRecord("LegacyLocal",210000,110)) == true
        and DPS.ReceiveRecord(
            DpsRecord("LegacyLocal",220000,111)) == true
        and DPS.ReceiveRelayedRecord(
            DpsRecord("LegacyLocal",225000,112),"RelayFour-Ebonhold") == false
        and DPS.GetCharacterBest("dummy", "LegacyLocal").dps == 220000,
    "nil-sender replacement remains unverified and relay-contained")
Control(DPS.ReceiveRecord(
        DpsRecord("LegacyLocal",230000,113),"LegacyLocal-Ebonhold") == true
        and DPS.ReceiveRecord(
            DpsRecord("LegacyLocal",240000,114)) == false
        and DPS.GetCharacterBest("dummy", "LegacyLocal").dps == 230000
        and DPS.GetCharacterBest(
            "dummy", "LegacyLocal").ownerVerified == true,
    "nil-sender compatibility path cannot replace verified owner evidence")

Control(provenanceDb.futureRoot == nil,
    "provenance fixture did not inherit future-schema state")

------------------------------------------------------------------------
-- 6. Community-derived DPS provenance and direct-owner promotion.
------------------------------------------------------------------------

UnitName = function() return "Viewer" end
GetNormalizedRealmName = function() return "Ebonhold" end
UnitClass = function() return "Mage", "MAGE" end
local communityDb = {
    communityBuilds={},syncTombstones={},dpsCapture={},
}
NexusDB = communityDb
Catalog.Init(communityDb, Nexus.BundledBuilds)
DPS.Init({}, nil)
local communityBroadcasts = {}
Nexus.Sync = {
    BroadcastBuildSummary=function(build)
        communityBroadcasts[#communityBroadcasts + 1] = build.id
        return true, "queued"
    end,
}
local community = Nexus.CommunityInternals.Controller.New({
    catalog=function() return Catalog end,
    notify=function() end,
})
local communityEchoes = {{spellId=651000,quality=3,stacks=1}}
local communityKey = DPS.GetEchoKey(communityEchoes)
local relayCommunityId = community.EnsureDpsBuildForEchoes(
    communityEchoes, "dummy", {
        player="CommunityOrigin",class="MAGE",
        ownerKey="communityorigin@ebonhold",ownerVerified=false,
        relaySender="RelayOne",fingerprint=communityKey,
    })
local relayCommunity = relayCommunityId and Catalog.Get(relayCommunityId)
local relayCommunityState = relayCommunityId
    and Catalog.SyncState(relayCommunityId) or nil
Desired("provenance", relayCommunity
        and relayCommunity.ownerVerified == false
        and relayCommunity.ownerKey == nil
        and relayCommunity.claimedOwnerKey == "communityorigin@ebonhold"
        and relayCommunity.isMine ~= true
        and relayCommunity.relaySender == "RelayOne"
        and #communityBroadcasts == 0
        and relayCommunityState and relayCommunityState.delta == nil,
    "Community-derived relayed DPS lost explicit provenance or entered Sync")

-- An exact fingerprint is not ownership. A different direct sender may share
-- the same loadout, but cannot use that collision to promote the ambient row.
local collisionCommunityId = community.EnsureDpsBuildForEchoes(
    communityEchoes, "dummy", {
    player="DifferentOwner",class="MAGE",
    ownerKey="differentowner@ebonhold",ownerVerified=true,
    fingerprint=communityKey,
})
local afterCommunityCollision = relayCommunityId
    and Catalog.Get(relayCommunityId) or nil
Desired("provenance", afterCommunityCollision
        and collisionCommunityId ~= relayCommunityId
        and afterCommunityCollision.author == "CommunityOrigin"
        and afterCommunityCollision.ownerKey == nil
        and afterCommunityCollision.claimedOwnerKey == "communityorigin@ebonhold"
        and afterCommunityCollision.ownerVerified == false
        and afterCommunityCollision.isMine ~= true
        and afterCommunityCollision.relaySender == "RelayOne"
        and Catalog.SyncState(relayCommunityId).delta == nil,
    "cross-author exact Community collision promoted relayed provenance")

-- The original direct owner can later establish authority over that exact
-- Community row. Promotion clears relay provenance and restores normal Sync.
local broadcastsBeforePromotion = #communityBroadcasts
local promotedCommunityId = community.EnsureDpsBuildForEchoes(
    communityEchoes, "dummy", {
        player="CommunityOrigin",class="MAGE",
        ownerKey="communityorigin@ebonhold",ownerVerified=true,
        fingerprint=communityKey,
    })
local promotedCommunity = promotedCommunityId
    and Catalog.Get(promotedCommunityId) or nil
local promotedCommunityState = promotedCommunityId
    and Catalog.SyncState(promotedCommunityId) or nil
Desired("provenance", promotedCommunityId == relayCommunityId
        and promotedCommunity and promotedCommunity.ownerVerified == true
        and promotedCommunity.claimedOwnerKey == nil
        and promotedCommunity.relaySender == nil
        and promotedCommunity.isMine ~= true
        and promotedCommunity.author == "CommunityOrigin"
        and promotedCommunity.ownerKey == "communityorigin@ebonhold"
        and promotedCommunityState and promotedCommunityState.delta ~= nil
        and #communityBroadcasts == broadcastsBeforePromotion + 1
        and communityBroadcasts[#communityBroadcasts] == relayCommunityId,
    "same direct owner did not promote and publish the exact Community row")

------------------------------------------------------------------------
-- 7. Saved Build recovery cannot shield a stale complete mirror.
------------------------------------------------------------------------

UnitName = function() return "SavedOwner" end
GetNormalizedRealmName = function() return "Ebonhold" end
UnitClass = function() return "Mage", "MAGE" end
local savedDb = {communityBuilds={},syncTombstones={},dpsCapture={}}
NexusDB = savedDb
Catalog.Init(savedDb, Nexus.BundledBuilds)
DPS.Init({}, nil)
Nexus.Sync = {
    IsReceiving=function() return false end,
    BroadcastBuildSummary=function() return true, "queued" end,
}
local savedSlots = {activeSlot=1,bySlot={
    [1]={name="Locked Replacement",class="MAGE",echoes={
        {spellId=652001,quality=3,stacks=1},
    }},
    [2]={name="Malformed Replacement",class="MAGE",echoes={
        {spellId=652011,quality=3,stacks=1},
    }},
}}
local savedGeneration = 1
local savedController = Nexus.CommunityInternals.Controller.New({
    catalog=function() return Catalog end,
    notify=function() end,
})
savedController.Initialize({
    Slots=function() return savedSlots end,
    EchoReconcileStats=function()
        return {generations={slots=savedGeneration}}
    end,
    GetLoadoutWishlist=function() return nil end,
}, Nexus.BundledBuilds)

local function PumpSavedImport(label)
    Control(savedController.BeginSavedLoadoutImport(true) == true,
        label .. " began")
    local changed, pending = 0, true
    for _ = 1, 20 do
        local delta
        delta, pending = savedController.PumpSavedLoadoutImport(25)
        changed = changed + (tonumber(delta) or 0)
        if not pending then break end
    end
    Control(pending == false, label .. " completed inside its bounded pumps")
    return changed
end

Control(PumpSavedImport("complete Saved Build import") == 2,
    "complete Saved Build setup stored both mirrors")
local lockedSavedId = "saved-savedowner-1"
local malformedSavedId = "saved-savedowner-2"
local lockedSavedIdentity = savedDb.communityBuilds[lockedSavedId]
local malformedSavedIdentity = savedDb.communityBuilds[malformedSavedId]
Control(lockedSavedIdentity and malformedSavedIdentity
        and Catalog.GetSummary(lockedSavedId).ordinaryComplete == true
        and Catalog.GetSummary(malformedSavedId).ordinaryComplete == true
        and Catalog.Get(lockedSavedId).echoes[1].spellId == 652001
        and Catalog.Get(malformedSavedId).echoes[1].spellId == 652011,
    "Saved Build setup warmed complete summary and spell mirrors")

-- Preserve both live slot-table identities while their contents transition.
-- This mirrors the server adapter's long-lived slot tables and prevents the
-- regression from being hidden by an object-identity cache miss.
local lockedLiveIdentity = savedSlots.bySlot[1]
local malformedLiveIdentity = savedSlots.bySlot[2]
lockedLiveIdentity.echoes[1].spellId = 652002
lockedLiveIdentity.echoes[1].locked = true
malformedLiveIdentity.echoes[1].spellId = 0
savedGeneration = savedGeneration + 1
PumpSavedImport("invalid Saved Build recovery")
Control(savedSlots.bySlot[1] == lockedLiveIdentity
        and savedSlots.bySlot[2] == malformedLiveIdentity,
    "Saved Build replacement fixture preserved both live table identities")

local savedFilters = {
    scope="mine",sortMode="title",currentClassOnly=false,
    qualifiedOnly=false,
}
local savedRows, savedProjection = Nexus.ViewProjections.Builds(savedFilters)
local projectedSaved = {}
for _, row in ipairs(savedRows or {}) do projectedSaved[row.id] = row end
local lockedSaved = Catalog.Get(lockedSavedId)
local malformedSaved = Catalog.Get(malformedSavedId)
local lockedSavedSummary = Catalog.GetSummary(lockedSavedId)
local malformedSavedSummary = Catalog.GetSummary(malformedSavedId)
local lockedSavedState = Catalog.SyncState(lockedSavedId)
local malformedSavedState = Catalog.SyncState(malformedSavedId)
Desired("replacement", lockedSaved == nil
        and lockedSavedSummary == nil
        and lockedSavedState.delta == nil
        and projectedSaved[lockedSavedId] == nil
        and savedDb.communityBuilds[lockedSavedId] ~= lockedSavedIdentity,
    "complete-to-locked Saved Build retained stale summary/spell evidence")
Desired("replacement", malformedSaved == nil
        and malformedSavedSummary == nil
        and malformedSavedState.delta == nil
        and projectedSaved[malformedSavedId] == nil
        and savedDb.communityBuilds[malformedSavedId] ~= malformedSavedIdentity,
    "complete-to-malformed Saved Build retained stale summary/spell evidence")
Desired("replacement", type(savedRows) == "table" and #savedRows == 0
        and savedProjection and savedProjection.ready == 0
        and savedProjection.pending == 0
        and savedProjection.availableCount == 0,
    "empty Saved recovery projection invented a pending or available row")

------------------------------------------------------------------------
-- 8. Ownerless direct DPS cannot hydrate another author's claimed ID.
------------------------------------------------------------------------

UnitName = function() return "Viewer" end
GetNormalizedRealmName = function() return "Ebonhold" end
UnitClass = function() return "Mage", "MAGE" end
local claimDb = {communityBuilds={},syncTombstones={},dpsCapture={}}
NexusDB = claimDb
Catalog.Init(claimDb, Nexus.BundledBuilds)
DPS.Init({}, nil)
local victimId = "victim-incomplete-build"
Control(Catalog.Put({
        id=victimId,title="Victim Pending",author="VictimOwner",
        class="MAGE",postedAt=1,lastModified=1,echoes={},
        needsFullBuild=true,loadoutAvailable=false,
    }) == true
        and Catalog.GetSummary(victimId).ordinaryComplete == false,
    "ownerless DPS collision setup stored an incomplete victim build")
local victimIdentity = claimDb.communityBuilds[victimId]
local claimCommunity = Nexus.CommunityInternals.Controller.New({
    catalog=function() return Catalog end,
    notify=function() end,
})
Nexus.Sync = {
    BroadcastBuildSummary=function() return true, "queued" end,
}
Nexus.CommunityBuilds = {
    EnsureDpsBuildForEchoes=function(echoes, category, record)
        return claimCommunity.EnsureDpsBuildForEchoes(
            echoes, category, record)
    end,
}
local claimantEchoes = {{spellId=653001,quality=3,stacks=1}}
local claimantFingerprint = DPS.GetEchoKey(claimantEchoes)
Control(DPS.ReceiveRecord({
        v=7,f=claimantFingerprint,h=DPS.GetEchoHash(claimantEchoes),
        e=claimantEchoes,c="dummy",d=275000,u=30,t=51001,
        p="DpsClaimant",l=80,k="MAGE",b=victimId,
        o="dpsclaimant@ebonhold",r="ebonhold",
    }, "DpsClaimant-Ebonhold") == true,
    "verified ownerless direct DPS fixture reached normal storage")
local claimantRow = DPS.GetCharacterBest("dummy", "DpsClaimant")
local claimantBuild = claimantRow and claimantRow.buildId
    and Catalog.Get(claimantRow.buildId) or nil
local victimAfterClaim = Catalog.Get(victimId)
Desired("provenance", claimantRow and claimantRow.ownerVerified == true
        and claimantRow.ownerKey == "dpsclaimant@ebonhold"
        and claimantRow.buildId ~= nil and claimantRow.buildId ~= victimId
        and claimantRow.buildId:find("^dps%-") ~= nil
        and claimantBuild and claimantBuild.author == "DpsClaimant"
        and claimantBuild.ownerVerified == true
        and claimantBuild.ordinaryComplete == true
        and claimDb.communityBuilds[victimId] == victimIdentity
        and type(claimDb.communityBuilds[victimId].echoes) == "table"
        and #claimDb.communityBuilds[victimId].echoes == 0
        and victimAfterClaim and victimAfterClaim.ordinaryComplete == false
        and Catalog.GetSummary(victimId).ordinaryComplete == false,
    "ownerless direct DPS hydrated another author's incomplete build ID")

local summary = string.format(
    "desired=%d expected_red=%d controls=%d replacement=%d wlbi=%d storage=%d ebh1=%d provenance=%d",
    desiredChecks,#failures,controls,groupRed.replacement,groupRed.wlbi,
    groupRed.storage,groupRed.ebh1,groupRed.provenance)
if #failures > 0 then
    error("EXPECTED RED [Stage 36.4 data integrity]: " .. summary
        .. "\n - " .. table.concat(failures, "\n - "))
end
print("Stage 36.4 data integrity: " .. summary .. " -- OK")
