-- Nexus: core/Sync.lua v2.1
-- Peer-to-peer sharing for Nexus Builds.
--
-- Login starts slow, bounded convergence passes that require peer-state proof.
-- Valid build and DPS updates are always accepted; exact Echo lists
-- are included in sync responses rather than fetched only when a menu is opened.
--
-- SHARING IS AUTOMATIC. Builds go out when you post or edit, and in
-- response to any peer sync request.
--
-- WIRE PROTOCOL (| separated; pipe escaped to || on send):
--   WLRQ|<sender>|<buildhash>|<dpshash>|<requestId> -- state request
--     buildhash is 8 delta buckets plus a bundled-catalog token on current
--     releases; legacy 8-bucket hashes retain full-catalog recovery.
--   WLRC|<sender>|<requester>|<requestId>|<buildhash>|<dpshash> -- claim
--   WLRB|<sender>|<id>|<m>|<idx>/<total>|<b64>  -- build chunk
--   WLRD|<sender>|<id>|<stamp>                   -- delete notification
--   WLD2|<sender>|<transfer>|<idx>/<total>|<b64> -- exact DPS evidence;
--     changed-bucket relays carry an additive requester/request/bucket context
--
-- PAYLOAD FORMAT (compact, ~65% smaller than verbose):
--   { id, t=title, a=author, c=class, m=lastModified,
--     d=description(omitted if empty), e=[[spellId,quality,stacks],...] }
--
-- ANTI-SPAM:
--   • Conservative paced queued sends; full loadouts sync in-band
--   • Eight build and DPS hash buckets: resend only changed subsets
--   • Responder claims: identical peers elect one sender; unique peers contribute
--   • Hot-build window (120s): a build posted while no peer is listening
--     is still included in the next BroadcastMine so the peer catches it
--     on their next Sync Now
--   • Max 999 chunks per build (enforced before queuing)

Nexus = Nexus or {}
local Identity = assert(Nexus.Identity, "Nexus Identity must load before Sync")
local Sync = {}
Nexus.Sync = Sync

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------

local SYNC_CHANNEL    = "wrbuildssync"
local CODE_BUILD      = "WLRB"
local CODE_INDEX      = "WLBI" -- lightweight build summary, no Echo list
local CODE_LOADOUT_REQ= "WLLQ" -- request one exact loadout by build id
local CODE_LOADOUT_CLAIM="WLLC" -- one peer claims an on-demand loadout response
local CODE_REQUEST    = "WLRQ"
local CODE_CLAIM      = "WLRC" -- protocol-7 whole-state receipt/responder claim
local CODE_BUCKET_CLAIM = "WLBC" -- per-bucket mesh claim; divides work across peers
local CODE_DELETE     = "WLRD"
local CODE_DPS        = "WLDS" -- legacy build-id DPS
local CODE_DPS2       = "WLD2" -- exact-set DPS chunks
local CODE_PRESENCE   = "WLNP" -- lightweight Nexus peer/version presence
local PEER_PROTOCOL_CODES = {
    [CODE_BUILD]=true, [CODE_INDEX]=true, [CODE_LOADOUT_REQ]=true,
    [CODE_LOADOUT_CLAIM]=true, [CODE_REQUEST]=true, [CODE_CLAIM]=true,
    [CODE_BUCKET_CLAIM]=true, [CODE_DELETE]=true, [CODE_DPS]=true,
    [CODE_DPS2]=true, [CODE_PRESENCE]=true,
}
local CHAT_LIMIT      = 255    -- WoW SendChatMessage hard cap
local CHAT_SAFETY     = 8      -- conservative margin
local MAX_WIRE_BYTES  = CHAT_LIMIT
local MAX_BYTES       = 32768  -- maximum encoded bytes per transfer
local MAX_CHUNKS      = 999
local MAX_CHUNK_BYTES = CHAT_LIMIT
local MAX_ENCODED_BYTES = MAX_BYTES
local MAX_BUILD_ID_BYTES = 96
local MAX_BUILD_ECHOES = 256
local MAX_TRANSFER_ID_BYTES = 160
local MAX_REQUEST_ID_BYTES = 96
local BUILD_BUCKETS = 8
local MAX_HASH_BYTES = 192
local MAX_VERSION_BYTES = 32
local MAX_INFLIGHT_GLOBAL = 24
local MAX_INFLIGHT_PER_SENDER = 4
local MAX_OUTBOUND_QUEUE = 8192
local MAX_CONTROL_QUEUE = 512
local MAX_RECOVERY_QUEUE = 512
local MAX_PENDING_RESPONSES = 128
local MAX_PENDING_LOADOUTS = 128
local MAX_RESPONSE_ADMISSIONS = 32
local MAX_RESPONSE_CHUNKS = 64
local MAX_RESPONSE_BYTES = 16384
local MAX_RESPONSE_SEND_SECONDS = 75
local MAX_RESPONSE_TRANSFERS = 8
local MAX_RESPONSE_CONCURRENT_TRANSFERS = 8
local MAX_KNOWN_PEERS = 512
local SEND_INTERVAL   = 1.10   -- conservative channel pacing; avoids server chat spam/mutes
local RECEIVE_WINDOW  = 60     -- compatibility/status timer; receiving is always enabled
local INFLIGHT_GRACE  = 30     -- seconds to finish an interrupted chunk transfer
local INFLIGHT_MAX_AGE = 300   -- absolute cap even if duplicate chunks keep arriving
local REQUEST_COOLDOWN = 6     -- min seconds between our own Sync Now presses
local CLAIM_DELAY_MIN  = 0.35  -- deterministic responder-election delay
local CLAIM_DELAY_MAX  = 1.75
local BUCKET_CLAIM_MAX = 5.50 -- wide deterministic window lets different peers win different buckets
local HOT_WINDOW       = 120   -- seconds a just-posted build is re-included in answers
local JOIN_RETRY_INTERVAL = 10
local JOIN_MAX_ATTEMPTS   = 30
local THROTTLE_PAUSE      = 8     -- pause all Nexus transport after a server throttle notice
local THROTTLE_SLOW_TIME  = 45    -- temporarily use extra-safe pacing after a throttle
local CONTROL_BURST_LIMIT = 4     -- bounded control priority; bulk still progresses
local TRANSPORT_MAX_ATTEMPTS = 3  -- throttle-correlated retransmission cap
local TRANSPORT_CLEANUP_BUDGET = 32 -- per queue/frame; independent of send pacing
local AUTO_SYNC_DELAY      = 6
local AUTO_SYNC_MIN_PASS    = 60  -- allow throttled peers time to begin/drain large responses
local AUTO_SYNC_QUIET       = 15  -- require a real quiet period before judging a pass stable
local CONVERGENCE_MAX_AGE   = 300 -- request-scoped absolute convergence cap
local RECEIVE_MAX_AGE       = 180 -- request-scoped absolute receive cap
local AUTO_SYNC_MAX_PASSES  = 3   -- no unbounded repeat-until-stable loop
local PENDING_TTL           = 30  -- inactivity cap for pending response work
local PENDING_MAX_AGE       = 300 -- absolute cap even while backpressured
local RESPONSE_ELECTION_DELAY = 4.5 -- exceeds the 4s throttle-notice correlation window
local RESPONSE_QUEUE_HEADROOM = 8 -- do no response preparation near saturation
local SHARE_RETRY_INTERVAL  = 1
local SHARE_RETRY_MAX_AGE   = 120
local SHARE_RETRY_MAX_ATTEMPTS = 8
local DELETE_RETRY_MAX_AGE = 300
local DELETE_RETRY_MAX_ATTEMPTS = 8

------------------------------------------------------------------------
-- Module state
------------------------------------------------------------------------

local Codec, Adapter, Transport, Compatibility, Reconciler, Inbound
local Diagnostics, Session
local channelIndex
local seenRemoteIds  = {}   -- id -> lastModified we already hold
local tombstones     = {}   -- id -> stamp; never resurrect
local hotBuilds      = {}   -- id -> { build, t }; recently posted, include in answers
local pendingDeletes = {}   -- local tombstone ids awaiting direct notification
local pendingDeleteTicker = 0
local pendingShare          -- one immutable, session-only Share summary
local pendingShareTicker = 0
local Operation = {
    latestShare=nil,latestDelete=nil,active={},activeShares={},
    activeDeletes={},shareById={},deleteById={},recent={},recentNext=1,
    recentCap=64,sequence=0,deleteCursor=nil,deleteDiscoveryComplete=false,
    counters={
        queued="operationQueued",attempted="operationAttempted",
        requeued="operationRequeued",
        ["sent-attempted"]="operationSentAttempted",
        expired="operationExpired",dropped="operationDropped",
        superseded="operationSuperseded",reset="operationReset",
        ["throttle-exhausted"]="operationThrottleExhausted",
        accepted="operationAccepted",rejected="operationRejected",
    },
    terminals={
        ["sent-attempted"]=true,expired=true,dropped=true,
        superseded=true,reset=true,["throttle-exhausted"]=true,
        accepted=true,rejected=true,
    },
}
local Now, MyName
local recentBuildBroadcast = {}
local BUILD_BROADCAST_DEDUPE = 2
local Responder = {}
local PendingDeleteCount

local function Catalog()
    return Nexus and Nexus.BuildCatalog
end

local function CatalogGet(id)
    local catalog = Catalog()
    if not (catalog and catalog.Get) then return nil end
    return catalog.Get(id)
end

local function CatalogAll()
    local catalog = Catalog()
    return catalog and catalog.All and catalog.All() or {}
end

local function CatalogPut(build)
    local catalog = Catalog()
    return catalog and catalog.Put and catalog.Put(build) or false
end

local function CatalogSetTombstone(id, tomb)
    local catalog = Catalog()
    return catalog and catalog.SetTombstone
        and catalog.SetTombstone(id, tomb) or false
end

local function CatalogClearTombstone(id)
    local catalog = Catalog()
    return catalog and catalog.ClearTombstone
        and catalog.ClearTombstone(id) or false
end

local function OrdinaryComplete(record)
    local evidence = Nexus and Nexus.LoadoutEvidence
    if evidence and type(evidence.OrdinaryCompleteness) == "function" then
        local verdict = evidence.OrdinaryCompleteness(record)
        return type(verdict) == "table" and verdict.complete == true, verdict
    end
    return type(record) == "table" and type(record.echoes) == "table"
        and #record.echoes > 0, nil
end

local function RequestRetention(reason)
    local retention = Nexus and Nexus.DataRetention
    if retention and type(retention.Request) == "function" then
        pcall(retention.Request, reason)
    end
end

local function AllowsRemoteRevision(author, stamp, buildId)
    local retention = Nexus and Nexus.DataRetention
    if not (retention
        and type(retention.AllowsRemoteRevision) == "function") then
        return true
    end
    local ok, allowed = pcall(retention.AllowsRemoteRevision,
        author, stamp, NexusDB, buildId)
    return not ok or allowed ~= false
end

local function NormalizePeerName(name)
    return Identity.PlayerKey(name) or ""
end

local function SamePeer(a, b)
    return Identity.SamePlayer(a, b)
end

local function OwnerKeyMatchesAuthor(ownerKey, author)
    return Identity.OwnerKeyMatchesAuthor(ownerKey, author)
end

local ProtocolFactory = Nexus.SyncInternals and Nexus.SyncInternals.Protocol
if not (ProtocolFactory and type(ProtocolFactory.New) == "function") then
    error("Nexus SyncProtocol must load before Sync")
end
local Protocol = ProtocolFactory.New({
    limits={
        maxTransferIdBytes=MAX_TRANSFER_ID_BYTES,
        maxHashBytes=MAX_HASH_BYTES,
        maxVersionBytes=MAX_VERSION_BYTES,
        maxBuildIdBytes=MAX_BUILD_ID_BYTES,
        maxBuildEchoes=MAX_BUILD_ECHOES,
        maxRequestIdBytes=MAX_REQUEST_ID_BYTES,
        bucketCount=BUILD_BUCKETS,
        maxWireFields=8,
    },
    parseVersion=function(value)
        local parser = Nexus and Nexus.Version and Nexus.Version.Parse
        if type(parser) ~= "function" then return nil end
        return parser(value)
    end,
    ownerKeyMatchesAuthor=OwnerKeyMatchesAuthor,
    validText=Identity.ValidWireText,
    validPeerName=Identity.ValidPlayer,
    canonicalOwnerKey=Identity.CanonicalOwnerKey,
    isSafeTree=function(value, maxDepth, maxNodes)
        return Codec.IsSafeTree(value, maxDepth, maxNodes)
    end,
})
local EscapedLen = Protocol.EscapedLen
local FiniteNumber = Protocol.FiniteNumber
local ValidText = Protocol.ValidText
local ValidField = Protocol.ValidField
local ValidIdentifier = Protocol.ValidIdentifier
local ValidTransferIdentifier = Protocol.ValidTransferIdentifier
local ValidPeerName = Protocol.ValidPeerName
local ValidHash = Protocol.ValidHash
local ValidVersion = Protocol.ValidVersion
local ValidIntegerText = Protocol.ValidIntegerText
local SplitHashes = Protocol.SplitHashes
local CompactEncode = Protocol.CompactEncode
local CompactDecode = Protocol.CompactDecode
local ValidateNetworkPayload = Protocol.ValidateNetworkPayload
local ValidateNetworkDpsPayload = Protocol.ValidateNetworkDpsPayload

function Responder.SupportsRequestContext(requestId)
    return type(requestId) == "string" and requestId:sub(1, 3) == "c1-"
end

function Responder.RequestContext(requester, requestId, bucket)
    if not Responder.SupportsRequestContext(requestId)
        or not ValidPeerName(requester)
        or not ValidIdentifier(requestId, MAX_REQUEST_ID_BYTES) then
        return nil
    end
    bucket = bucket ~= nil and tonumber(bucket) or nil
    if bucket ~= nil and (bucket ~= math.floor(bucket)
        or bucket < 1 or bucket > BUILD_BUCKETS) then return nil end
    return {requester=requester,requestId=requestId,bucket=bucket}
end

function Responder.ContextSuffix(context, includeBucket)
    if type(context) ~= "table"
        or not Responder.SupportsRequestContext(context.requestId) then
        return ""
    end
    local suffix = "|" .. tostring(context.requester)
        .. "|" .. tostring(context.requestId)
    if includeBucket then suffix = suffix .. "|" .. tostring(context.bucket) end
    return suffix
end

function Responder.ContextRequestId(context)
    if type(context) ~= "table" then return nil end
    if SamePeer(context.requester, MyName()) then return context.requestId end
    -- A valid context addressed elsewhere is accepted as ambient storage input,
    -- but it receives one bounded unrelated outcome against the local request.
    return "c1-foreign"
end

function Responder.NoteContextOutcome(context, outcome, reason)
    if not Session or type(Session.NoteOutcome) ~= "function" then return false end
    local requestId = Responder.ContextRequestId(context)
    if requestId == nil then return false end
    return Session.NoteOutcome(requestId, outcome, reason)
end
local SplitWire = Protocol.SplitWire

local function BumpSync(reason)
    local revisions = Nexus and Nexus.Revisions
    if revisions and type(revisions.Advance) == "function" then
        pcall(revisions.Advance, revisions.SYNC_CHANGED, reason)
    end
end

local DiagnosticsFactory = Nexus.SyncInternals
    and Nexus.SyncInternals.Diagnostics
if not (DiagnosticsFactory
    and type(DiagnosticsFactory.New) == "function") then
    error("Nexus SyncDiagnostics must load before Sync")
end
Diagnostics = DiagnosticsFactory.New({
    history=Nexus.DiagnosticHistory,
    now=function() return (GetTime and GetTime()) or 0 end,
})
local stats = Diagnostics.Stats()
local LogEvent = Diagnostics.LogEvent

local function PeerObserve(kind, fields)
    local debugOwner = Nexus and Nexus.PeerDebug
    if debugOwner and type(debugOwner.IsEnabled) == "function"
        and debugOwner.IsEnabled()
        and type(debugOwner.Record) == "function" then
        pcall(debugOwner.Record, kind, fields)
    end
end

local function SameTransportSender(declared, actual)
    return Identity.SameTransportSender(declared, actual)
end

function Sync.GetPeerInfo(name)
    return Session.GetPeerInfo(name)
end

function Sync.IsKnownPeer(name) return Session.IsKnownPeer(name) end

function Sync.WorkState()
    local session = Session.WorkSnapshot()
    local transport = Transport.Snapshot()
    local requestTransport = Transport.RequestSnapshot(MyName(),
        session.requestId)
    local requestIncoming = Inbound.RequestCounts(MyName(), session.requestId)
    return Diagnostics.ProjectWorkState({
        transport=transport,
        reconciliation=Reconciler.Counts(),
        incoming=Inbound.Counts(),
        session=session,
        requestRelated=requestTransport.requestRelated
            + requestIncoming.total,
        requestOutstandingTransfers=requestTransport.outstandingTransfers,
        pendingDeletes=PendingDeleteCount(),
        pendingDeleteDiscovery=Operation.deleteDiscoveryComplete and 0 or 1,
        pendingShares=pendingShare and 1 or 0,
        limits={
            maxGlobal=MAX_INFLIGHT_GLOBAL,
            maxPerSender=MAX_INFLIGHT_PER_SENDER,
            maxEncodedBytes=MAX_ENCODED_BYTES,
            maxOutboundQueue=MAX_OUTBOUND_QUEUE,
            maxControlQueue=MAX_CONTROL_QUEUE,
            maxRecoveryQueue=MAX_RECOVERY_QUEUE,
            maxPendingResponses=MAX_PENDING_RESPONSES,
            maxPendingLoadouts=MAX_PENDING_LOADOUTS,
            maxKnownPeers=MAX_KNOWN_PEERS,
            responseHeadroom=RESPONSE_QUEUE_HEADROOM,
        },
    })
end

function Sync.ResponseStats()
    return Reconciler.Stats()
end

Sync.LogEvent = LogEvent
function Sync.EventLog() return Diagnostics.EventLog() end
function Sync.ClearLog() return Diagnostics.ClearLog() end
function Sync.LogRaw(value) return Diagnostics.LogRaw(value) end
function Sync.RawLog() return Diagnostics.EventLog() end
function Sync.LogStats() return Diagnostics.LogStats() end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

Now = function() return (GetTime and GetTime()) or 0 end
MyName = function() return (UnitName and UnitName("player")) or "?" end

function Operation.Key(kind, id, version)
    return tostring(kind or "operation") .. ":" .. tostring(id or "")
        .. ":" .. tostring(version or "0")
end

function Operation.Register(status)
    Operation.active[status.operationKey] = status
    if status.kind == "share" then
        Operation.activeShares[status.operationKey] = status
        Operation.shareById[status.id] = status
    elseif status.kind == "delete" then
        Operation.activeDeletes[status.operationKey] = status
        Operation.deleteById[status.id] = status
    end
end

function Operation.RetainRecent(status)
    local replaced = Operation.recent[Operation.recentNext]
    if replaced then
        local lookup = replaced.kind == "share" and Operation.shareById
            or replaced.kind == "delete" and Operation.deleteById or nil
        if lookup and lookup[replaced.id] == replaced then
            lookup[replaced.id] = nil
        end
    end
    Operation.recent[Operation.recentNext] = status
    Operation.recentNext = (Operation.recentNext % Operation.recentCap) + 1
end

function Operation.New(kind, id, version, previous, registerActive)
    Operation.sequence = Operation.sequence + 1
    local attempt = previous and tostring(previous.id) == tostring(id)
        and (tonumber(previous.attempt) or 0) + 1 or 1
    local status = {
        kind=tostring(kind),id=tostring(id),version=tostring(version or "0"),
        operationKey=Operation.Key(kind, id, version),
        generation=Operation.sequence,attempt=attempt,
        outcome="not-queued",terminal=false,reason="none",accepted=false,
        queueAdmitted=false,queueReason=nil,retryPending=false,
        retryAttempts=0,sent=false,sendCompleted=false,
        sendState="not queued",confirmation="unavailable",createdAt=Now(),
    }
    if registerActive ~= false then Operation.Register(status) end
    return status
end

function Operation.BoundedReason(value)
    value = tostring(value or "none"):gsub("[%c|]", "")
    if value == "" then return "none" end
    return value:sub(1, 96)
end

function Operation.Transition(status, outcome, reason, fields)
    if type(status) ~= "table" or status.terminal == true then return false end
    outcome = tostring(outcome or "rejected")
    reason = Operation.BoundedReason(reason)
    local changed = status.outcome ~= outcome or status.reason ~= reason
    status.outcome, status.reason = outcome, reason
    status.terminal = Operation.terminals[outcome] == true
    status.accepted = outcome == "accepted"
    local current = Now()
    if outcome == "queued" then
        status.queueAdmitted, status.retryPending = true, false
        status.sendState, status.queuedAt = "queued", current
    elseif outcome == "retry-pending" then
        status.retryPending, status.sendState = true, "retry-pending"
    elseif outcome == "attempted" then
        status.sendState, status.attemptedAt = "attempted", current
    elseif outcome == "requeued" then
        status.sent, status.sendCompleted = false, false
        status.sendState, status.retryPending = "requeued", false
    elseif outcome == "sent-attempted" then
        status.sent, status.sendCompleted = true, true
        status.sendState, status.sentAt = "attempted", current
    elseif status.terminal then
        status.sent, status.sendCompleted = false, false
        status.sendState = outcome
    end
    if type(fields) == "table" and tonumber(fields.attempts) then
        status.retryAttempts = math.max(status.retryAttempts or 0,
            tonumber(fields.attempts) or 0)
    end
    if status.terminal then
        status.retryPending, status.resolvedAt = false, current
        if status.operationKey ~= nil
            and Operation.active[status.operationKey] == status then
            Operation.active[status.operationKey] = nil
        end
        if status.kind == "share" then
            if status.operationKey ~= nil
                and Operation.activeShares[status.operationKey] == status then
                Operation.activeShares[status.operationKey] = nil
            end
        elseif status.operationKey ~= nil
            and Operation.activeDeletes[status.operationKey] == status then
            Operation.activeDeletes[status.operationKey] = nil
        end
        Operation.RetainRecent(status)
    end
    if changed then
        local counter = Operation.counters[outcome]
        if counter then stats[counter] = (stats[counter] or 0) + 1 end
        PeerObserve("operation_" .. outcome:gsub("%-", "_"), {
            operation=status.kind,id=status.id,outcome=outcome,reason=reason,
            attempts=status.retryAttempts,
        })
        if status.kind == "share" and status.terminal
            and outcome ~= "sent-attempted" and outcome ~= "accepted"
            and type(Sync.RequestDataViewRefresh) == "function" then
            -- Terminal failure is rare and user-actionable. Route one
            -- coalesced view refresh so an already-open owned-build detail can
            -- expose Retry Share without polling or rebuilding on every tick.
            pcall(Sync.RequestDataViewRefresh)
        end
    end
    return true
end

function Operation.MarkApiReturned(status, fields)
    if type(status) ~= "table" or status.terminal == true then return end
    status.sent, status.sendCompleted = true, true
    status.sendState, status.sentAt = "attempted", Now()
    if type(fields) == "table" and tonumber(fields.attempts) then
        status.retryAttempts = math.max(status.retryAttempts or 0,
            tonumber(fields.attempts) or 0)
    end
end

function Operation.Copy(status)
    if type(status) ~= "table" then return nil end
    local copy = {}
    for key, value in pairs(status) do
        local kind = type(value)
        if kind == "string" or kind == "number" or kind == "boolean" then
            copy[key] = value
        end
    end
    if status.retryPending and status.expiresAt then
        copy.retrySecondsLeft = math.max(0, status.expiresAt - Now())
    end
    return copy
end

function Operation.RunObserver(owner, source, kind, fields, metadata)
    local callback = owner and owner.HandleTransportEvent
    if type(callback) ~= "function" then return end
    local ok, err = pcall(callback, kind, fields, metadata)
    if not ok then
        LogEvent("ERR", "%s failed: %s", tostring(source),
            Operation.BoundedReason(err))
    end
end

local function ObserveTransport(kind, fields, metadata, context)
    local status = type(context) == "table" and context.operationStatus or nil
    if type(status) == "table" then
        if kind == "send_attempting" then
            Operation.Transition(status, "attempted", "send attempt", fields)
        elseif kind == "send_attempted" then
            Operation.MarkApiReturned(status, fields)
        elseif kind == "send_requeued" then
            Operation.Transition(status, "requeued",
                fields and fields.reason or "server throttle", fields)
        elseif kind == "send_retry" then
            Operation.Transition(status, "requeued",
                fields and fields.reason or "send failed", fields)
        elseif kind == "send_settled" then
            Operation.Transition(status, "sent-attempted",
                "api returned without correlated throttle", fields)
        elseif kind == "operation_terminal" then
            Operation.Transition(status,
                fields and fields.outcome or "dropped",
                fields and fields.reason, fields)
        elseif kind == "send_dropped" then
            local reason = fields and fields.reason or "send dropped"
            local outcome = reason == "expired" and "expired"
                or reason == "superseded" and "superseded"
                or reason == "throttle exhausted" and "throttle-exhausted"
                or "dropped"
            Operation.Transition(status, outcome, reason, fields)
        end
    end
    -- Operation ownership transitions first and cannot be orphaned by a
    -- secondary reconciliation/session diagnostic callback.
    Operation.RunObserver(Reconciler, "SyncReconciler", kind, fields,
        metadata)
    Operation.RunObserver(Session, "SyncSession", kind, fields, metadata)
    if type(status) ~= "table" then PeerObserve(kind, fields) end
end

local CompatibilityFactory = Nexus.SyncInternals
    and Nexus.SyncInternals.Compatibility
if not (CompatibilityFactory
    and type(CompatibilityFactory.New) == "function") then
    error("Nexus SyncCompatibility must load before Sync")
end
Compatibility = CompatibilityFactory.New({
    buckets=BUILD_BUCKETS,
    getCatalog=Catalog,
    getBuildHashCache=function()
        return Nexus and Nexus.BuildHashCache
    end,
    getBuildRevision=function()
        local revisions = Nexus and Nexus.Revisions
        return revisions and revisions.Get
            and revisions.Get(revisions.BUILD_LIBRARY_CHANGED) or nil
    end,
    getDpsCapture=function()
        return Nexus and Nexus.DpsCapture
    end,
    getTombstones=function() return tombstones end,
    samePeer=SamePeer,
    myName=MyName,
    now=Now,
    getCodec=function() return Codec end,
    validIdentifier=ValidIdentifier,
    validHash=ValidHash,
    escapedLen=EscapedLen,
    codeIndex=CODE_INDEX,
    maxBuildIdBytes=MAX_BUILD_ID_BYTES,
    chatLimit=CHAT_LIMIT,
    chatSafety=CHAT_SAFETY,
    noteStat=function(name, amount)
        Reconciler.NoteStat(name, amount)
    end,
})
local BuildBucket = Compatibility.BuildBucket
local TombStamp = Compatibility.TombStamp
local TombAuthor = Compatibility.TombAuthor
local HashText = Compatibility.HashText
local BuildFingerprint = Compatibility.BuildFingerprint
local CatalogToken = Compatibility.CatalogToken
local DeltaBuildHash = Compatibility.DeltaBuildHash
local LegacyBuildHash = Compatibility.LegacyBuildHash
local CurrentBuildHash = Compatibility.CurrentBuildHash
local CurrentDpsHash = Compatibility.CurrentDpsHash

local function BucketContainsTombstone(bucket)
    for id in pairs(tombstones or {}) do
        if BuildBucket(id) == bucket then return true end
    end
    return false
end

-- Read-only compatibility surface used by diagnostics and deterministic tests.
-- It exposes the exact hashes placed on WLRQ without mutating sync state.
function Sync.GetCompatibilityHashes()
    return CurrentBuildHash(), CurrentDpsHash()
end

-- Explicit diagnostic surfaces. Normal Sync never calls the canonical path;
-- it exists so tests and exports can prove cache compatibility against the
-- established whole-collection algorithm.
function Sync.GetCanonicalBuildHashes()
    return Compatibility.CanonicalBuildHashes()
end

function Sync.GetLegacyBuildHash()
    return LegacyBuildHash()
end

function Sync.HashCacheStats()
    return Compatibility.HashCacheStats()
end

local function StableDelay(text)
    local h = 5381
    text = tostring(text or "")
    for i = 1, #text do h = ((h * 33) + text:byte(i)) % 1000003 end
    local span = CLAIM_DELAY_MAX - CLAIM_DELAY_MIN
    return CLAIM_DELAY_MIN + (h % 1000) / 999 * span
end

------------------------------------------------------------------------
-- Channel
------------------------------------------------------------------------

local function FindSyncChannel()
    if not GetChannelList then return nil end
    local all = { GetChannelList() }
    for i = 1, #all, 2 do
        local idx  = tonumber(all[i])
        local name = all[i+1]
        if idx and idx > 0 and type(name) == "string"
            and name:lower() == SYNC_CHANNEL then
            return idx
        end
    end
    return nil
end

local function HideChannelFromChat()
    if not NUM_CHAT_WINDOWS or not ChatFrame_RemoveChannel then return end
    for i = 1, NUM_CHAT_WINDOWS do
        local f = _G["ChatFrame"..i]
        if f then pcall(ChatFrame_RemoveChannel, f, SYNC_CHANNEL) end
    end
end

function Sync.EnsureChannel()
    local idx = FindSyncChannel()
    if idx then
        if channelIndex ~= idx then
            LogEvent("CHAN","already in '%s' at index %d", SYNC_CHANNEL, idx)
        end
        channelIndex = idx
        HideChannelFromChat()
        return true
    end
    if JoinTemporaryChannel then pcall(JoinTemporaryChannel, SYNC_CHANNEL)
    elseif JoinChannelByName then pcall(JoinChannelByName, SYNC_CHANNEL) end
    idx = FindSyncChannel()
    if idx then
        channelIndex = idx
        HideChannelFromChat()
        LogEvent("CHAN","joined '%s' at index %d", SYNC_CHANNEL, idx)
        return true
    end
    channelIndex = nil
    LogEvent("CHAN","FAILED to join '%s'", SYNC_CHANNEL)
    return false
end

function Sync.ChannelName()  return SYNC_CHANNEL end
function Sync.ChannelIndex() return channelIndex end
function Sync.IsConnected()  return channelIndex ~= nil and channelIndex > 0 end
function Sync.Stats()        return stats end

function Sync.OnWorldEntry()
    local connected = Sync.EnsureChannel()
    if Session and type(Session.OnWorldEntry) == "function" then
        Session.OnWorldEntry(connected)
    end
    return connected
end

local function ResolveSendChannel()
    -- Channel numbers are not stable: leaving/joining any channel can move
    -- wrbuildssync while the old slot is reassigned to General or Trade.
    -- Re-resolve the name immediately before each queued channel send.
    local idx = FindSyncChannel()
    if idx then
        if channelIndex ~= idx then
            LogEvent("CHAN", "'%s' moved from slot %s to %d",
                SYNC_CHANNEL, tostring(channelIndex), idx)
        end
        channelIndex = idx
        return idx
    end
    channelIndex = nil
    if not Sync.EnsureChannel() then return nil end
    idx = FindSyncChannel()
    if not idx then
        channelIndex = nil
        return nil
    end
    channelIndex = idx
    return idx
end

local TransportFactory = Nexus.SyncInternals
    and Nexus.SyncInternals.Transport
if not (TransportFactory and type(TransportFactory.New) == "function") then
    error("Nexus SyncTransport must load before Sync")
end
Transport = TransportFactory.New({
    maxBulk=MAX_OUTBOUND_QUEUE,
    maxControl=MAX_CONTROL_QUEUE,
    responseHeadroom=RESPONSE_QUEUE_HEADROOM,
    chatLimit=CHAT_LIMIT,
    sendInterval=SEND_INTERVAL,
    slowInterval=1.75,
    throttlePause=THROTTLE_PAUSE,
    throttleSlowTime=THROTTLE_SLOW_TIME,
    controlBurstLimit=CONTROL_BURST_LIMIT,
    maxAttempts=TRANSPORT_MAX_ATTEMPTS,
    cleanupBudget=TRANSPORT_CLEANUP_BUDGET,
    now=Now,
    escapedLen=EscapedLen,
    log=LogEvent,
    stats=stats,
    resolveChannel=ResolveSendChannel,
    channelLabel=function() return channelIndex end,
    sendChat=function(...) return SendChatMessage(...) end,
    addMessageFilter=function(event, filter)
        if type(ChatFrame_AddMessageEventFilter) ~= "function" then
            return false
        end
        return ChatFrame_AddMessageEventFilter(event, filter)
    end,
    observe=ObserveTransport,
})

local ReconcilerFactory = Nexus.SyncInternals
    and Nexus.SyncInternals.Reconciler
if not (ReconcilerFactory and type(ReconcilerFactory.New) == "function") then
    error("Nexus SyncReconciler must load before Sync")
end
Reconciler = ReconcilerFactory.New({
    bucketCount=BUILD_BUCKETS,
    maxPendingResponses=MAX_PENDING_RESPONSES,
    maxPendingLoadouts=MAX_PENDING_LOADOUTS,
    pendingTtl=PENDING_TTL,
    pendingMaxAge=PENDING_MAX_AGE,
    claimDelayMin=CLAIM_DELAY_MIN,
    claimDelayMax=CLAIM_DELAY_MAX,
    bucketClaimMax=BUCKET_CLAIM_MAX,
    maxAdmissionsPerRequest=MAX_RESPONSE_ADMISSIONS,
    maxChunksPerRequest=MAX_RESPONSE_CHUNKS,
    maxBytesPerRequest=MAX_RESPONSE_BYTES,
    maxSendSecondsPerRequest=MAX_RESPONSE_SEND_SECONDS,
    maxTransfersPerRequest=MAX_RESPONSE_TRANSFERS,
    maxConcurrentTransfers=MAX_RESPONSE_CONCURRENT_TRANSFERS,
    sendInterval=SEND_INTERVAL,
    responseElectionDelay=RESPONSE_ELECTION_DELAY,
    now=Now,
    myName=MyName,
    stableDelay=StableDelay,
    splitHashes=SplitHashes,
    deltaBuildHash=DeltaBuildHash,
    currentBuildHash=CurrentBuildHash,
    currentDpsHash=CurrentDpsHash,
    catalogToken=CatalogToken,
    buildCandidateSnapshot=function(deltaHash)
        return Responder.BuildCandidateSnapshot(deltaHash)
    end,
    snapshotCurrent=function(snapshot)
        return Responder.SnapshotCurrent(snapshot)
    end,
    bucketClaimable=function(bucket)
        return not BucketContainsTombstone(bucket)
    end,
    backpressured=function() return Transport.Backpressured() end,
    supportsRequestContext=function(requestId)
        return Responder.SupportsRequestContext(requestId)
    end,
    localOwnsDpsBucket=function(bucket)
        local dps = Nexus and Nexus.DpsCapture
        if not (dps and type(dps.LocalOwnsDpsBucket) == "function") then
            return true
        end
        return dps.LocalOwnsDpsBucket(bucket) == true
    end,
    dpsBucketClaimInfo=function(bucket)
        local dps = Nexus and Nexus.DpsCapture
        if not (dps and type(dps.ResponseBucketClaimInfo) == "function") then
            return false
        end
        return dps.ResponseBucketClaimInfo(bucket)
    end,
    samePeer=SamePeer,
    catalogGet=CatalogGet,
    prepareBuild=function(build, responseMode, responseContext)
        return Responder.PrepareBuild(build, responseMode, responseContext)
    end,
    admitBuild=function(prepared, responseMode, responseContext)
        return Responder.AdmitBuild(prepared, responseMode, responseContext)
    end,
    sendNextBuild=function(bucketState, responseBudget)
        return Responder.SendNextBuild(bucketState, responseBudget)
    end,
    sendDpsBucket=function(peerDpsHash, bucket, progress, limit,
            responseContext, responseBudget)
        local dps = Nexus and Nexus.DpsCapture
        if not (dps and dps.BroadcastAllBuildBests) then return false end
        local ok, result, allAdmitted, didProgress, why,
            chunks, bytes, transfers, claimSafe = pcall(
            dps.BroadcastAllBuildBests, peerDpsHash, bucket, progress, limit,
            responseContext, responseBudget)
        return true, ok, result, allAdmitted, didProgress, why,
            chunks, bytes, transfers, claimSafe
    end,
    publishLoadoutClaim=function(entry)
        local contextual = Responder.SupportsRequestContext(entry.requestId)
        local wire = contextual and string.format("%s|%s|%s|%s|%s",
                CODE_LOADOUT_CLAIM, MyName(), entry.requester,
                entry.buildId, entry.requestId)
            or string.format("%s|%s|%s|%s", CODE_LOADOUT_CLAIM,
                MyName(), entry.requester, entry.buildId)
        local requestId = contextual and entry.requestId
            or "loadout-" .. tostring(entry.buildId)
        return Transport.EnqueueControl(wire, {
                requester=tostring(entry.requester),
                requestId=requestId,
                transferId="loadout-claim:" .. tostring(entry.requester)
                    .. ":" .. tostring(entry.buildId) .. ":"
                    .. tostring(requestId),
                buildId=tostring(entry.buildId),queueClass="claim",
                enqueuedAt=Now(),expiresAt=Now() + PENDING_MAX_AGE,
            })
    end,
    publishResponseClaim=function(entry)
        return Transport.EnqueueControl(string.format(
            "%s|%s|%s|%s|%s|%s", CODE_CLAIM, MyName(),
            entry.requester, entry.requestId,
            tostring(entry.localBuildWireHash or "0"),
            tostring(entry.localDpsHash or "0")), {
                requester=tostring(entry.requester),
                requestId=tostring(entry.requestId),
                transferId="response-claim:" .. tostring(entry.requester)
                    .. ":" .. tostring(entry.requestId),
                queueClass="claim",enqueuedAt=Now(),
                expiresAt=Now() + PENDING_MAX_AGE,
            })
    end,
    publishBucketClaim=function(entry, bucketState)
        return Transport.EnqueueControl(string.format(
            "%s|%s|%s|%s|%s|%d|%s", CODE_BUCKET_CLAIM,
            MyName(), entry.requester, entry.requestId, bucketState.kind,
            bucketState.bucket, bucketState.hash), {
                requester=tostring(entry.requester),
                requestId=tostring(entry.requestId),
                transferId="bucket-claim:" .. tostring(entry.requester)
                    .. ":" .. tostring(entry.requestId) .. ":"
                    .. tostring(bucketState.kind) .. tostring(bucketState.bucket),
                queueClass="claim",
                enqueuedAt=Now(),expiresAt=Now() + PENDING_MAX_AGE,
            })
    end,
    noteSyncStat=function(name, amount)
        stats[name] = (stats[name] or 0) + (tonumber(amount) or 1)
    end,
    outstandingTransfers=function()
        return Transport.Snapshot().requestOutstandingTransfers
    end,
    cancelRequest=function(requestId, requester)
        return Transport.CancelRequest(requestId, requester)
    end,
    log=LogEvent,
})

------------------------------------------------------------------------
-- Receive window
------------------------------------------------------------------------

function Sync.IsReceiving() return Session.IsReceiving() end
function Sync.ReceiveTimeLeft() return Session.ReceiveTimeLeft() end
function Sync.LastSyncNewCount() return Session.LastSyncNewCount() end

------------------------------------------------------------------------
-- Send queue (rate-limited, anti-spam)
------------------------------------------------------------------------

local function RejectRecoveryOverflow(depth)
    stats.queueOverflowRejected = (stats.queueOverflowRejected or 0) + 1
    LogEvent("TX", "REJECT newest recovery packet(s): queue full (%d+1>%d)",
        tonumber(depth) or 0, MAX_RECOVERY_QUEUE)
    return false
end

function Responder.BulkFree()
    return Transport.BulkFree()
end

function Responder.Backpressured()
    return Transport.Backpressured()
end

function Responder.CanAdmit(count)
    return Transport.CanAdmit(count)
end

local function WireCost(messages)
    local chunks, bytes = 0, 0
    for _, message in ipairs(type(messages) == "table" and messages or {}) do
        chunks = chunks + 1
        bytes = bytes + EscapedLen(message)
    end
    return {chunks=chunks,bytes=bytes,transfers=chunks > 0 and 1 or 0,
        seconds=chunks * SEND_INTERVAL}
end

local function PreparedWireCost(prepared, responseMode, countChunks)
    if type(prepared) ~= "table" then return WireCost(nil) end
    if type(prepared.wireCost) ~= "table" then
        prepared.wireCost = WireCost(prepared.messages)
        if responseMode then
            if countChunks then
                Reconciler.NoteStat("chunkMessagesBuilt",
                    prepared.wireCost.chunks)
            end
            Reconciler.NoteStat("encodedBytesBuilt", prepared.wireCost.bytes)
        end
    end
    return prepared.wireCost
end

local function ResponseBudgetReason(cost, budget)
    if type(budget) ~= "table" then return nil end
    local chunks = tonumber(cost and cost.chunks) or 0
    local bytes = tonumber(cost and cost.bytes) or 0
    local seconds = tonumber(cost and cost.seconds) or 0
    local transfers = tonumber(cost and cost.transfers) or 0
    if chunks > (tonumber(budget.maxChunks) or math.huge)
        or bytes > (tonumber(budget.maxBytes) or math.huge)
        or seconds > (tonumber(budget.maxSeconds) or math.huge)
        or transfers > (tonumber(budget.maxTransfers) or math.huge) then
        return "response transfer too large"
    end
    if chunks > (tonumber(budget.chunks) or 0)
        or bytes > (tonumber(budget.bytes) or 0)
        or seconds > (tonumber(budget.seconds) or 0)
        or transfers > (tonumber(budget.transfers) or 0) then
        return "response wire budget"
    end
    return nil
end

function Sync.NoteTransportNotice(text)
    return Transport.NoteTransportNotice(text)
end


local function RelayEligible(build)
    return type(build) == "table"
        and build.ownerVerified ~= false
        and not (build.legacyRecovered == true
            and build.ownerVerified ~= true)
end

function Responder.PrepareSummary(build, responseContext)
    if not RelayEligible(build) then return nil, "relay unauthorized" end
    return Compatibility.PrepareSummary(build, responseContext)
end

function Operation.ShareVersion(build)
    return tostring(tonumber(build and build.lastModified)
        or tonumber(build and build.postedAt) or 0)
end

function Operation.NewShare(build)
    local id = tostring(build and build.id or ""):sub(1, MAX_BUILD_ID_BYTES)
    local version = Operation.ShareVersion(build)
    return Operation.New("share", id, version, Operation.shareById[id])
end

local function FinishPendingShare(reason, expired, superseded)
    local pending = pendingShare
    if not pending then return false end
    local status = pending.status
    status.expired = expired == true
    status.superseded = superseded == true
    status.queueReason = tostring(reason or status.queueReason or "retry stopped")
    status.retryOutcome = expired and "expired"
        or superseded and "superseded" or "stopped"
    Operation.Transition(status, expired and "expired"
        or superseded and "superseded" or "dropped", status.queueReason)
    PeerObserve("share_retry", {id=status.id,
        outcome=status.retryOutcome,reason=status.queueReason})
    pendingShare, pendingShareTicker = nil, 0
    return true
end

local function PumpPendingShare(elapsed)
    local pending = pendingShare
    if not pending then return end
    local current = Now()
    if current >= pending.expiresAt then
        FinishPendingShare("share retry expired", true, false)
        return
    end
    pendingShareTicker = pendingShareTicker + (tonumber(elapsed) or 0)
    if pendingShareTicker < SHARE_RETRY_INTERVAL then return end
    local transport = Transport.Snapshot()
    if transport.control >= transport.maxControl then
        pendingShareTicker = SHARE_RETRY_INTERVAL
        return
    end
    if pending.attempts >= SHARE_RETRY_MAX_ATTEMPTS then
        FinishPendingShare("share retry attempts exhausted", true, false)
        return
    end
    pendingShareTicker = 0
    pending.attempts = pending.attempts + 1
    pending.status.retryAttempts = pending.attempts
    local queued, why = Transport.EnqueueControl(pending.message,
        pending.metadata)
    if queued then
        local status = pending.status
        status.queueReason = "queued after retry"
        status.retryOutcome = "admitted"
        Operation.Transition(status, "queued", "bounded retry admitted")
        pendingShare = nil
        PeerObserve("share_queue", {id=status.id,outcome="admitted",
            reason="bounded retry",queue=Transport.Snapshot().control})
    elseif why ~= "sync queue full" then
        FinishPendingShare(why or "share retry rejected", true, false)
    end
end

local function BroadcastSummary(build, options)
    local retryOnFull = type(options) == "table"
        and options.retryOnFull == true
    local status
    local prepared, why = Responder.PrepareSummary(build)
    if not prepared then
        if retryOnFull then
            local id = tostring(build and build.id or ""):sub(1,
                MAX_BUILD_ID_BYTES)
            local previous = Operation.shareById[id]
            status = Operation.New("share", id,
                Operation.ShareVersion(build), previous, false)
            Operation.latestShare = status
            Operation.Transition(status, "rejected", why)
            -- A rejected pre-admission attempt is observable through its
            -- returned receipt and diagnostics, but cannot replace a valid
            -- active owner for the same immutable operation identity.
            if not previous or previous.terminal == true then
                Operation.shareById[id] = status
            end
        end
        return false, why, Operation.Copy(status)
    end
    if retryOnFull then
        local id = tostring(build and build.id or ""):sub(1,
            MAX_BUILD_ID_BYTES)
        local version = Operation.ShareVersion(build)
        local key = Operation.Key("share", id, version)
        local active = Operation.activeShares[key]
        if active and active.terminal ~= true then
            Operation.latestShare = active
            return true, "already queued", Operation.Copy(active)
        end
        -- A new explicit confirmation supersedes only an older summary that
        -- never entered Transport. Already admitted FIFO work is untouched.
        FinishPendingShare("superseded by newer Share Build", false, true)
        status = Operation.NewShare(build)
        Operation.latestShare = status
    end
    local msg = prepared.messages[1]
    local current = Now()
    local metadata = status and {
        operationStatus=status,operationKind="share",
        operationId=status.id,operationVersion=status.version,
        operationKey=status.operationKey,shareId=tostring(status.id),
        buildId=tostring(status.id),transferId=status.operationKey,
        queueClass="share",enqueuedAt=current,
        expiresAt=current + SHARE_RETRY_MAX_AGE,
    } or {buildId=tostring(build.id or ""),queueClass="bulk",
        enqueuedAt=current,expiresAt=current + PENDING_MAX_AGE}
    local queued, queueWhy
    if status then
        queued, queueWhy = Transport.EnqueueControl(msg, metadata)
    else
        queued, queueWhy = Transport.Enqueue(msg, metadata)
    end
    if not queued then
        if status then
            status.queueReason = queueWhy or "queue rejected"
            if queueWhy == "sync queue full" then
                status.retryOutcome = "pending"
                status.expiresAt = Now() + SHARE_RETRY_MAX_AGE
                status.retryAttempts = 0
                Operation.Transition(status, "retry-pending", queueWhy)
                pendingShare = {
                    message=msg,metadata=metadata,status=status,
                    createdAt=Now(),expiresAt=status.expiresAt,attempts=0,
                }
                pendingShareTicker = 0
            else
                Operation.Transition(status, "rejected", queueWhy)
            end
        end
        return false, queueWhy, Operation.Copy(status)
    end
    if status then
        status.queueReason = "queued"
        Operation.Transition(status, "queued", "transport admitted")
    end
    LogEvent("TX","queuing summary '%s' (%d chars, no Echo list)", tostring(build.title), EscapedLen(msg))
    return true, "queued", Operation.Copy(status)
end
Sync.BroadcastBuildSummary = BroadcastSummary

function Sync.GetShareStatus(id)
    local status = id ~= nil and Operation.shareById[tostring(id)]
        or Operation.latestShare
    if type(status) ~= "table" then return nil end
    return Operation.Copy(status)
end

local function DeleteWireMessage(id, tomb, responseContext)
    return string.format("%s|%s|%s|%s|%s%s", CODE_DELETE, MyName(),
        tostring(id), tostring(TombStamp(tomb)), TombAuthor(tomb),
        Responder.ContextSuffix(responseContext, false))
end

function Operation.NewDelete(id, tomb)
    local version = tostring(TombStamp(tomb)) .. ":" .. TombAuthor(tomb)
    local status = Operation.New("delete", id, version,
        Operation.deleteById[tostring(id)])
    status.owner = TombAuthor(tomb)
    return status
end

function Operation.DeleteMetadata(id, tomb, status)
    local current = Now()
    return {
        operationStatus=status,operationKind="delete",
        operationId=tostring(id),operationVersion=status.version,
        operationKey=status.operationKey,
        transferId=status.operationKey,buildId=tostring(id),
        queueClass="bulk",enqueuedAt=current,
        expiresAt=current + PENDING_MAX_AGE,
    }
end

local function MarkDeletePending(id, tomb, status)
    pendingDeletes[id] = status or true
    if type(tomb) == "table" then tomb.pending = true end
end

local function ClearPendingDelete(id, tomb)
    pendingDeletes[id] = nil
    if type(tomb) == "table" and tombstones[id] == tomb then
        tomb.pending = nil
    end
end

PendingDeleteCount = function()
    local count = 0
    for id in pairs(pendingDeletes) do
        local tomb = tombstones[id]
        if tomb and SamePeer(TombAuthor(tomb), MyName()) then
            count = count + 1
        end
    end
    return count
end

function Operation.DiscoverPendingDeletes(budget)
    if Operation.deleteDiscoveryComplete then return 0 end
    local available = MAX_RECOVERY_QUEUE - PendingDeleteCount()
    if available <= 0 then return 0 end
    -- Lua 5.1 rejects next(table, key) when the retained key was removed
    -- between bounded discovery slices. Restarting from the table head is
    -- safe and bounded; already admitted IDs are skipped below.
    if Operation.deleteCursor ~= nil
        and tombstones[Operation.deleteCursor] == nil then
        Operation.deleteCursor = nil
    end
    local inspected, admitted = 0, 0
    budget = math.max(1, math.floor(tonumber(budget) or 1))
    while inspected < budget and available > 0 do
        local id, tomb = next(tombstones, Operation.deleteCursor)
        Operation.deleteCursor = id
        if id == nil then
            Operation.deleteDiscoveryComplete = true
            break
        end
        inspected = inspected + 1
        if type(tomb) == "table" and tomb.pending
            and pendingDeletes[id] == nil
            and SamePeer(TombAuthor(tomb), MyName()) then
            pendingDeletes[id] = true
            admitted, available = admitted + 1, available - 1
        end
    end
    return admitted
end

local function PumpPendingDeletes(elapsed)
    pendingDeleteTicker = pendingDeleteTicker + (tonumber(elapsed) or 0)
    if pendingDeleteTicker < 1 then return end
    pendingDeleteTicker = 0
    Operation.DiscoverPendingDeletes(32)
    if not next(pendingDeletes) then return end
    local current = Now()
    local selectedId, selectedTomb, selectedStatus
    for id, status in pairs(pendingDeletes) do
        local tomb = tombstones[id]
        if not tomb then
            if type(status) == "table" then
                Operation.Transition(status, "rejected", "missing tombstone")
            end
            pendingDeletes[id] = nil
        elseif type(status) == "table" and status.expiresAt
            and current >= status.expiresAt then
            ClearPendingDelete(id, tomb)
            Operation.Transition(status, "expired", "delete retry expired")
        elseif SamePeer(TombAuthor(tomb), MyName())
            and (not selectedId or tostring(id) < tostring(selectedId)) then
            selectedId, selectedTomb, selectedStatus = id, tomb, status
        end
    end
    if not selectedId then return end
    if Transport.BulkFree() <= 0 then
        return
    end
    if type(selectedStatus) ~= "table" then
        selectedStatus = Operation.NewDelete(selectedId, selectedTomb)
        selectedStatus.expiresAt = current + DELETE_RETRY_MAX_AGE
        pendingDeletes[selectedId] = selectedStatus
        Operation.latestDelete = selectedStatus
        Operation.Transition(selectedStatus, "retry-pending",
            "restored pending delete")
    end
    selectedStatus.retryAttempts = (selectedStatus.retryAttempts or 0) + 1
    if selectedStatus.retryAttempts > DELETE_RETRY_MAX_ATTEMPTS then
        ClearPendingDelete(selectedId, selectedTomb)
        Operation.Transition(selectedStatus, "dropped",
            "delete retry attempts exhausted")
        return
    end
    local queued, why = Transport.Enqueue(
        DeleteWireMessage(selectedId, selectedTomb),
        Operation.DeleteMetadata(selectedId, selectedTomb, selectedStatus))
    if queued then
        ClearPendingDelete(selectedId, selectedTomb)
        Operation.Transition(selectedStatus, "queued", "transport admitted")
        LogEvent("TX", "queued pending delete '%s'", tostring(selectedId))
    elseif why ~= "sync queue full" then
        -- A permanent local serialization failure cannot be helped by retrying;
        -- the tombstone remains available to normal reconciliation.
        ClearPendingDelete(selectedId, selectedTomb)
        Operation.Transition(selectedStatus, "rejected", why)
        LogEvent("TX", "dropping unsendable pending delete '%s': %s",
            tostring(selectedId), tostring(why or "invalid packet"))
    end
end

Sync._pendingDeleteScheduled = false

function Sync.RequestDataViewRefresh()
    local refresh = Nexus and Nexus.ViewRefresh
    if refresh and type(refresh.Request) == "function" then
        return refresh.Request()
    end
    if Nexus.CommunityBuilds and Nexus.CommunityBuilds.Refresh then
        return pcall(Nexus.CommunityBuilds.Refresh)
    end
end

local function StoreSummary(data, transportSender, context)
    local validated, validationReason = Protocol.ValidateNetworkSummary(data)
    if not validated then
        Responder.NoteContextOutcome(context, "rejected",
            validationReason == "ownership" and "ownership" or "schema")
        return false, false
    end
    data = validated
    if not SamePeer(data.a, transportSender) then
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        return false, false
    end
    local id = tostring(data.id)
    local recoveryRequestId = type(context) == "table"
        and SamePeer(context.requester, MyName()) and context.requestId or nil
    local old, oldSource = CatalogGet(id)
    if old and old.isMine then
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        return false, false
    end
    if old and not SamePeer(old.author, data.a) then
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        return false, false
    end
    local stamp = tonumber(data.m) or 0
    local pending = Session.PendingReplacement(id)
    if pending then
        local pendingStamp = tonumber(pending.lastModified) or 0
        if stamp < pendingStamp then
            Responder.NoteContextOutcome(context, "duplicate", "stale")
            return true, false
        end
        if stamp == pendingStamp then
            local same = tostring(pending.author) == tostring(data.a)
                and tostring(pending.ownerKey or "") == tostring(
                    type(data.o) == "string"
                        and Identity.CanonicalOwnerKey(data.o) or "")
                and tostring(pending.fingerprintHash) == tostring(data.h):lower()
                and tostring(pending.linkHash or "") == tostring(data.lh or "")
                and tonumber(pending.echoCount or 0) == tonumber(data.n or 0)
            Responder.NoteContextOutcome(context,
                same and "duplicate" or "rejected",
                same and "duplicate" or "integrity")
            return same, false
        end
    end
    if not AllowsRemoteRevision(data.a, stamp, id) then
        LogEvent("RX", "skip summary '%s': older than retention floor",
            tostring(data.t))
        Responder.NoteContextOutcome(context, "duplicate", "stale")
        return true, false
    end
    local tomb = tombstones[id]
    if tomb and stamp <= TombStamp(tomb) then
        LogEvent("RX","skip summary '%s': tombstoned", tostring(data.t))
        Responder.NoteContextOutcome(context, "rejected", "tombstone")
        return true, false
    end
    if tomb and (TombAuthor(tomb) == ""
        or not SamePeer(TombAuthor(tomb), data.a)) then
        LogEvent("RX", "REJECT summary resurrection of '%s': tombstone belongs to %s",
            tostring(id), tostring(TombAuthor(tomb)))
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        return false, false
    end
    local oldStamp = old and (tonumber(old.lastModified) or tonumber(old.postedAt) or 0) or nil
    if oldStamp and stamp < oldStamp then
        LogEvent("RX","skip summary '%s': older than local copy", tostring(data.t))
        Responder.NoteContextOutcome(context, "duplicate", "stale")
        return true, false
    end
    if oldStamp and stamp == oldStamp then
        stats.duplicatesSkipped = stats.duplicatesSkipped + 1
        if oldSource == "bundled" then
            stats.baselineSkipped = (stats.baselineSkipped or 0) + 1
            Responder.NoteContextOutcome(context, "baseline", "bundled")
        else
            Responder.NoteContextOutcome(context, "duplicate", "duplicate")
        end
        if old and (type(old.echoes) ~= "table" or #old.echoes == 0) then
            Session.QueueLegacyRecovery(id, recoveryRequestId)
            LogEvent("RX","DUPLICATE legacy summary '%s'; queued missing full loadout", tostring(data.t))
        else
            LogEvent("RX","skip summary '%s': DUPLICATE", tostring(data.t))
        end
        return true, false
    end
    local newHash = tostring(data.h):lower()
    local newLinkHash = type(data.lh) == "string"
        and data.lh:lower() or nil
    local oldLinkHash = old and (old.linkHash or HashText(old.link)) or nil
    local linkChanged = old ~= nil and newLinkHash ~= oldLinkHash
    local keepEchoes = old and old.fingerprintHash == newHash and old.echoes or nil
    local replacement = {
        buildId=id,title=tostring(data.t),author=tostring(data.a),
        ownerKey=type(data.o)=="string"
            and Identity.CanonicalOwnerKey(data.o) or nil,
        class=data.c,lastModified=stamp,fingerprintHash=newHash:lower(),
        linkHash=newLinkHash,echoCount=tonumber(data.n) or 0,
        autoDps=data.x==1,
    }
    local oldComplete = OrdinaryComplete(old)
    if old and oldComplete then
        local queued = Session.QueueReplacement(
            id, replacement, recoveryRequestId)
        if not queued then
            Responder.NoteContextOutcome(context, "rejected", "queue")
            LogEvent("RX", "REJECT summary '%s': recovery queue full",
                tostring(data.t))
            return false, false, "queue"
        end
        stats.received = stats.received + 1
        stats.updated = (stats.updated or 0) + 1
        Session.NoteReceived(Responder.ContextRequestId(context), "updated")
        LogEvent("RX", "PENDING summary '%s' by %s (last-good retained)",
            tostring(data.t), tostring(data.a or "Unknown"))
        return true, true
    end
    local record = {
        id=id, title=tostring(data.t):sub(1,120), author=tostring(data.a or "Unknown"):sub(1,80),
        ownerKey=type(data.o)=="string"
            and Identity.CanonicalOwnerKey(data.o) or nil,
        class=data.c, description=old and old.description or "",
        lastModified=stamp, postedAt=old and old.postedAt or stamp, isMine=old and old.isMine or false,
        autoDps=data.x==1, fingerprint=keepEchoes and old.fingerprint or nil,
        fingerprintHash=newHash, echoCount=tonumber(data.n) or 0,
        echoes=keepEchoes, loadoutAvailable=type(keepEchoes)=="table" and #keepEchoes>0,
        linkHash=newLinkHash, needsFullBuild=linkChanged or nil,
        ownerVerified=true,
    }
    CatalogClearTombstone(id)
    local stored, storedAs = CatalogPut(record)
    if stored == false then
        stats.storageRejected = (stats.storageRejected or 0) + 1
        Responder.NoteContextOutcome(context, "rejected", "storage")
        PeerObserve("receiver_commit", {id=id,peer=transportSender,
            outcome="store_failed",reason="storage"})
        LogEvent("RX", "REJECT summary '%s': local storage refused",
            tostring(data.t))
        return false, false, "storage"
    end
    if storedAs == "baseline" then
        stats.baselineSkipped = (stats.baselineSkipped or 0) + 1
    end
    seenRemoteIds[id] = stamp
    stats.received = stats.received + 1
    if old then
        stats.updated = (stats.updated or 0) + 1
        if storedAs == "baseline" then
            Responder.NoteContextOutcome(context, "baseline", "bundled")
        else
            Session.NoteReceived(Responder.ContextRequestId(context), "updated")
        end
        LogEvent("RX","UPDATED summary '%s' by %s%s", tostring(data.t), tostring(data.a or "Unknown"),
            keepEchoes and " (loadout unchanged)" or " (loadout needed)")
    else
        if storedAs == "baseline" then
            Responder.NoteContextOutcome(context, "baseline", "bundled")
        else
            Session.NoteReceived(Responder.ContextRequestId(context), "new")
        end
        LogEvent("RX","STORED legacy summary '%s' by %s (%d Echo entries pending full sync)",
            tostring(data.t), tostring(data.a or "Unknown"), tonumber(data.n) or 0)
    end
    if not keepEchoes or linkChanged then
        Session.QueueReplacement(id, replacement, recoveryRequestId)
    end
    RequestRetention("build summary received")
    return true, true
end

function Sync.RequestLoadout(buildId)
    -- Menu clicks never transmit directly. If this is a summary inherited from
    -- an older Nexus peer, queue one slow background recovery request instead.
    -- Current peers send complete builds during normal reconciliation.
    local queued = Session.QueueLegacyRecovery(buildId)
    return false, queued and "queued for background recovery" or "awaiting sync"
end

function Sync.RequestFullLoadoutSync()
    -- Backward-compatible API: use one normal hash reconciliation instead of
    -- broadcasting one request per missing build.
    return Sync.RequestSync()
end


-- Header-aware chunking: measures the ACTUAL escaped header so no chunk
-- can ever exceed the hard limit.
function Responder.ChunkBuildMessages(buildId, lastMod, data, responseMode,
        responseContext)
    if not ValidIdentifier(tostring(buildId or ""), MAX_BUILD_ID_BYTES)
        or not ValidIntegerText(tostring(lastMod or ""), 0)
        or type(data) ~= "string" or data == "" or #data > MAX_BYTES then
        return nil, "invalid build envelope"
    end
    buildId = tostring(buildId)
    lastMod = tostring(lastMod)
    local sender = MyName()
    local suffix = Responder.ContextSuffix(responseContext, false)
    -- Worst-case header = largest chunk index digits (999/999)
    local sampleHdr = string.format("%s|%s|%s|%s|999/999|",
        CODE_BUILD, sender, buildId, lastMod)
    local budget = CHAT_LIMIT - CHAT_SAFETY - EscapedLen(sampleHdr)
        - EscapedLen(suffix)
    if budget < 32 then return nil, "id too long" end

    local single = string.format("%s|%s|%s|%s|1/1|%s%s",
        CODE_BUILD, sender, buildId, lastMod, data, suffix)
    if EscapedLen(single) <= CHAT_LIMIT - CHAT_SAFETY then
        if responseMode then
            Reconciler.NoteStat("chunkMessagesBuilt", 1)
        end
        return {single}
    end
    local total = math.ceil(#data / budget)
    if total > MAX_CHUNKS then return nil, "build too large" end
    local messages = {}
    for idx = 1, total do
        local s = (idx-1)*budget + 1
        messages[#messages + 1] = string.format("%s|%s|%s|%s|%d/%d|%s%s",
            CODE_BUILD, sender, buildId, lastMod, idx, total,
            data:sub(s, s+budget-1), suffix)
    end
    if responseMode then
        Reconciler.NoteStat("chunkMessagesBuilt", #messages)
    end
    return messages
end

function Responder.ResolveBuild(build)
    if build and (type(build.echoes) ~= "table" or #build.echoes == 0) then
        local evidence = Nexus and Nexus.LoadoutEvidence
        if evidence and type(evidence.ResolveBuildRow) == "function" then
            local ok, resolved = pcall(evidence.ResolveBuildRow, build)
            if ok and type(resolved) == "table" then build = resolved end
        end
    end
    if build and (type(build.echoes) ~= "table" or #build.echoes == 0)
        and build.id ~= nil then
        local stored = CatalogGet(build.id)
        if stored then build = stored end
    end
    return build
end

function Responder.PrepareBuild(build, responseMode, responseContext)
    build = Responder.ResolveBuild(build)
    if not RelayEligible(build) then return nil, "relay unauthorized" end
    if not build or type(build.echoes) ~= "table" or #build.echoes == 0 then
        return nil, "no echoes"
    end
    if not ValidIdentifier(tostring(build.id or ""), MAX_BUILD_ID_BYTES) then
        return nil, "invalid build id"
    end
    if responseMode then
        Reconciler.NoteStat("buildSerializations", 1)
    end
    local payload = CompactEncode(build)
    local json = Codec.JSONEncode(payload)
    local b64 = Codec.Base64Encode(json)
    if #b64 > MAX_BYTES then
        return nil, "too large"
    end
    local messages, why = Responder.ChunkBuildMessages(
        build.id, tostring(payload.m), b64, responseMode, responseContext)
    if not messages then return nil, why end
    local prepared = {
        messages=messages, build=build,
        buildKey=tostring(build.id or build.fingerprintHash
            or build.fingerprint or ""),
        title=build.title, id=build.id,
        echoCount=#build.echoes, b64Bytes=#b64,
    }
    PreparedWireCost(prepared, responseMode, false)
    return prepared
end

function Responder.AdmitBuild(prepared, responseMode, responseContext)
    if type(prepared) ~= "table" or type(prepared.messages) ~= "table" then
        return false, "invalid prepared build"
    end
    if not Responder.CanAdmit(#prepared.messages) then
        return false, "sync queue full"
    end
    local queued, why = Transport.EnqueueBatch(prepared.messages, {
        requester=responseContext and responseContext.requester or nil,
        requestId=responseContext and responseContext.requestId or nil,
        transferId=tostring(prepared.id or ""),
        buildId=tostring(prepared.id or ""),queueClass="bulk",
        enqueuedAt=Now(),expiresAt=Now() + PENDING_MAX_AGE,
    })
    if not queued then return false, why end
    if responseMode then
        Reconciler.NoteStat("buildAdmissions", 1)
    end
    LogEvent("TX","queuing '%s' %d echoes %d b64 bytes (compact)",
        tostring(prepared.title), tonumber(prepared.echoCount) or 0,
        tonumber(prepared.b64Bytes) or 0)
    if not responseMode then
        hotBuilds[prepared.id] = { build=prepared.build, t=Now() }
        if prepared.buildKey ~= "" then
            recentBuildBroadcast[prepared.buildKey] = Now()
        end
    end
    return true
end

------------------------------------------------------------------------
-- Outgoing
------------------------------------------------------------------------

-- A DPS record relay and a full-sync response may both ask for the same
-- exact build in the same frame. Suppress only rapid duplicate wire sends;
-- later sync requests still receive the build normally.
function Sync.BroadcastBuild(build)
    build = Responder.ResolveBuild(build)
    if not build or type(build.echoes) ~= "table" or #build.echoes == 0 then
        return false, "no echoes"
    end
    if not ValidIdentifier(tostring(build.id or ""), MAX_BUILD_ID_BYTES) then
        return false, "invalid build id"
    end
    local buildKey = tostring(build.id or build.fingerprintHash or build.fingerprint or "")
    local now = Now()
    if buildKey ~= "" and recentBuildBroadcast[buildKey]
        and now - recentBuildBroadcast[buildKey] < BUILD_BROADCAST_DEDUPE then
        return true, "duplicate suppressed"
    end
    local prepared, why = Responder.PrepareBuild(build, false)
    if not prepared then
        if why == "too large" then
            LogEvent("TX","'%s' too large", tostring(build.id))
        end
        return false, why
    end
    prepared.buildKey = buildKey
    return Responder.AdmitBuild(prepared, false)
end

function Sync.BroadcastMine()
    local now = Now()
    -- Expire hot builds
    for id, h in pairs(hotBuilds) do
        if now - h.t > HOT_WINDOW then hotBuilds[id] = nil end
    end
    local sent = {}   -- track by id to avoid double-sending
    local n = 0
    -- True mesh: redistribute every valid build held locally.
    for _, b in pairs(CatalogAll()) do
        if not (b.legacyRecovered == true and b.ownerVerified ~= true)
            and BroadcastSummary(b) then n=n+1 end
        sent[b.id] = true
    end
    -- Also include hot builds not already sent (covers: posted while no
    -- peer was listening, then peer syncs within HOT_WINDOW)
    for id, h in pairs(hotBuilds) do
        if not sent[id] then
            if BroadcastSummary(h.build) then n=n+1 end
        end
    end
    return n
end

-- Response candidates are the mutable overlay/tombstone delta only. Immutable
-- release baselines arrive with addon releases; mixed-version peers can request
-- an exact known ID through WLLQ without flooding the channel with every bundled
-- loadout. Candidate discovery itself advances one catalog row per worker turn.
function Responder.BuildCandidateSnapshot(deltaHash)
    return Compatibility.BuildCandidateSnapshot(deltaHash)
end

function Responder.SnapshotCurrent(snapshot)
    return Compatibility.SnapshotCurrent(snapshot)
end

function Responder.AdvanceCandidateSnapshot(snapshot)
    return Compatibility.AdvanceCandidateSnapshot(snapshot)
end

function Responder.PrepareCandidate(item, bucketState)
    bucketState.prepared = bucketState.prepared or {}
    local cached = bucketState.prepared[item.token]
    if cached then return cached end
    local prepared, why
    if item.kind == "build" then
        if type(item.build.echoes) == "table" and #item.build.echoes > 0 then
            prepared, why = Responder.PrepareBuild(item.build, true,
                bucketState.responseContext)
        else
            Reconciler.NoteStat("buildSerializations", 1)
            prepared, why = Responder.PrepareSummary(item.build,
                bucketState.responseContext)
        end
    else
        prepared = {messages={DeleteWireMessage(item.id, item.tomb,
            bucketState.responseContext)},
            tomb=true, id=item.id, tombstone=item.tomb}
    end
    if not prepared then return nil, why end
    if not prepared.wireCost then
        PreparedWireCost(prepared, true, true)
    end
    bucketState.prepared[item.token] = prepared
    return prepared
end

function Responder.AdmitCandidate(item, bucketState, responseBudget)
    if Responder.Backpressured() then
        return false, "sync queue full", true
    end
    local prepared, why = Responder.PrepareCandidate(item, bucketState)
    if not prepared then return false, why, false end
    local wireCost = PreparedWireCost(prepared, true, false)
    local budgetWhy = ResponseBudgetReason(wireCost, responseBudget)
    if budgetWhy then
        return false, budgetWhy, budgetWhy == "response wire budget",
            wireCost
    end
    if not Responder.CanAdmit(#prepared.messages) then
        return false, "sync queue full", true
    end
    local admitted, admitWhy
    if item.kind == "build" and not prepared.summary then
        admitted, admitWhy = Responder.AdmitBuild(prepared, true,
            bucketState.responseContext)
    else
        admitted, admitWhy = Transport.EnqueueBatch(prepared.messages, {
            requester=bucketState.responseContext
                and bucketState.responseContext.requester or nil,
            requestId=bucketState.responseContext
                and bucketState.responseContext.requestId or nil,
            transferId=tostring(prepared.id or item.id or ""),
            buildId=tostring(prepared.id or item.id or ""),
            queueClass="bulk",enqueuedAt=Now(),
            expiresAt=Now() + PENDING_MAX_AGE,
        })
        if admitted and prepared.summary then
            LogEvent("TX", "queuing summary '%s' (no Echo list)",
                tostring(item.build and item.build.title))
        end
    end
    if not admitted then
        return false, admitWhy, admitWhy == "sync queue full"
    end
    bucketState.prepared[item.token] = nil
    return true, "admitted", false, wireCost
end

function Responder.SendNextBuild(bucketState, responseBudget)
    bucketState.progress = bucketState.progress or {}
    bucketState.cursor = tonumber(bucketState.cursor) or 1
    local snapshot = bucketState.snapshot
    if snapshot then
        if not Responder.SnapshotCurrent(snapshot) then
            return 0, false, false, true, "stale candidate snapshot"
        end
        if not snapshot.complete then
            local _, why, progressed =
                Responder.AdvanceCandidateSnapshot(snapshot)
            return 0, false, bucketState.claimSafe ~= false,
                progressed, why
        end
        if bucketState.candidates == nil then
            bucketState.candidates = snapshot.byBucket[bucketState.bucket] or {}
        end
    end
    local candidates = bucketState.candidates or {}
    while bucketState.cursor <= #candidates
        and bucketState.progress[candidates[bucketState.cursor].token] do
        bucketState.cursor = bucketState.cursor + 1
    end
    if bucketState.cursor > #candidates then
        return 0, true, bucketState.claimSafe ~= false, false
    end
    local item = candidates[bucketState.cursor]
    local admitted, why, transient, wireCost =
        Responder.AdmitCandidate(item, bucketState, responseBudget)
    if admitted then
        bucketState.progress[item.token] = "admitted"
        bucketState.cursor = bucketState.cursor + 1
        if item.kind == "tomb" then
            ClearPendingDelete(item.id, item.tomb)
        else
            stats.overlaySent = (stats.overlaySent or 0) + 1
        end
        return 1, bucketState.cursor > #candidates,
            bucketState.claimSafe ~= false, true, nil,
            wireCost.chunks, wireCost.bytes, wireCost.transfers
    end
    if transient then
        return 0, false, bucketState.claimSafe ~= false, false, why
    end
    bucketState.prepared[item.token] = nil
    bucketState.progress[item.token] = "skipped"
    bucketState.cursor = bucketState.cursor + 1
    bucketState.claimSafe = false
    LogEvent("TX", "skipping unsendable %s '%s': %s",
        tostring(item.kind), tostring(item.id), tostring(why or "invalid"))
    return 0, bucketState.cursor > #candidates, false, true, why,
        wireCost and wireCost.chunks or nil,
        wireCost and wireCost.bytes or nil,
        wireCost and wireCost.transfers or nil
end

-- Broadcast a validated exact-set DPS record. The JSON/base64 payload is
-- chunked using the same 255-byte-safe discipline as build sync.
local function ValidDpsRelayContext(context, player)
    local D = Nexus and Nexus.DpsCapture
    local bucket = type(context) == "table" and tonumber(context.b) or nil
    return type(context) == "table"
        and type(context.n) == "string"
        and type(context.i) == "string"
        and type(context.b) == "number"
        and ValidPeerName(context.n)
        and ValidIdentifier(tostring(context.i or ""), MAX_REQUEST_ID_BYTES)
        and bucket and bucket == math.floor(bucket)
        and bucket >= 1 and bucket <= BUILD_BUCKETS
        and D and type(D.SyncBucket) == "function"
        and D.SyncBucket(context.c or "dummy", player) == bucket
end

local function ValidDpsDuration(category, duration)
    local D = Nexus and Nexus.DpsCapture
    return D and type(D.IsDurationEligible) == "function"
        and D.IsDurationEligible(category, duration) == true
end

function Responder.ValidatePreparedDps(payload, originVerified)
    local D = Nexus and Nexus.DpsCapture
    if type(payload) ~= "table" or type(payload.f) ~= "string"
        or type(payload.e) ~= "table" then return false end
    local dps, duration, stamp, level = tonumber(payload.d),
        tonumber(payload.u), tonumber(payload.t), tonumber(payload.l)
    local player = tostring(payload.p or "")
    local playerClass = type(payload.k) == "string"
        and payload.k:upper() or nil
    local validClass = playerClass == "WARRIOR" or playerClass == "PALADIN"
        or playerClass == "HUNTER" or playerClass == "ROGUE"
        or playerClass == "PRIEST" or playerClass == "DEATHKNIGHT"
        or playerClass == "SHAMAN" or playerClass == "MAGE"
        or playerClass == "WARLOCK" or playerClass == "DRUID"
    local computed = D and D.GetEchoKey and D.GetEchoKey(payload.e) or nil
    local computedHash = D and D.GetEchoHash and D.GetEchoHash(payload.e)
        or nil
    local directOwner = SamePeer(player, MyName())
    local relayContext = payload.x
    local relayValid = not directOwner and originVerified == true
        and ValidDpsRelayContext({n=relayContext and relayContext.n,
            i=relayContext and relayContext.i,
            b=relayContext and relayContext.b,c=payload.c}, player)
    return FiniteNumber(dps) and dps > 0 and dps <= 500000000
        and FiniteNumber(duration) and ValidDpsDuration(payload.c, duration)
        and FiniteNumber(stamp) and stamp > 0
        and FiniteNumber(level) and level >= 1 and level <= 80
        and level == math.floor(level) and validClass
        and player ~= "" and #player <= 64 and not player:find("[%c|]")
        and (payload.c == "dummy" or payload.c == "lk")
        and (directOwner or relayValid)
        and OwnerKeyMatchesAuthor(payload.o, player)
        and computed and computed == payload.f
        and payload.h and (not computedHash or payload.h == computedHash)
end

function Sync.BroadcastDpsRecord(record, prepared, responseMode,
        responseContext, responseBudget)
    if type(prepared) ~= "table" then prepared = nil end
    if responseMode and Responder.Backpressured() then
        return false, "sync queue full", prepared
    end
    if prepared ~= nil then
        if type(prepared) ~= "table" or type(prepared.messages) ~= "table"
            or type(prepared.payload) ~= "table"
            or #prepared.messages < 1
            or not Responder.ValidatePreparedDps(prepared.payload,
                prepared.originVerified) then
            return false, "schema"
        end
        local wireCost = PreparedWireCost(prepared, responseMode, false)
        local budgetWhy = ResponseBudgetReason(wireCost, responseBudget)
        if budgetWhy then
            return false, budgetWhy, prepared, wireCost.chunks,
                wireCost.bytes, wireCost.transfers
        end
        if not Responder.CanAdmit(#prepared.messages) then
            return false, "sync queue full", prepared
        end
        local queued, queueWhy = Transport.EnqueueBatch(prepared.messages, {
            requester=prepared.context and prepared.context.requester
                or prepared.payload.x and prepared.payload.x.n or nil,
            requestId=prepared.context and prepared.context.requestId
                or prepared.payload.x and prepared.payload.x.i or nil,
            transferId=tostring(prepared.payload.p) .. ":"
                .. tostring(prepared.payload.t) .. ":"
                .. tostring(prepared.payload.d),
            buildId=tostring(prepared.payload.b or ""),
            dpsId=tostring(prepared.payload.f or ""),queueClass="bulk",
            enqueuedAt=Now(),expiresAt=Now() + PENDING_MAX_AGE,
        })
        if not queued then return false, queueWhy, prepared end
        LogEvent("TX","DPS2 [%s] %.0f by %s (%d chunks)",
            tostring(prepared.payload.c), prepared.payload.d,
            prepared.payload.p, #prepared.messages)
        if prepared.payload.x then
            stats.dpsRelayOffered = (stats.dpsRelayOffered or 0) + 1
            PeerObserve("dps_offer", {peer=prepared.payload.x.n,
                category=prepared.payload.c,
                outcome=queueWhy == "duplicate" and "duplicate" or "admitted"})
        end
        if responseMode then Reconciler.NoteStat("dpsAdmissions", 1) end
        return true, queueWhy, nil, wireCost.chunks, wireCost.bytes,
            wireCost.transfers
    end
    local D = Nexus.DpsCapture
    if type(record) == "table" and D
        and type(D.MaterializeRecord) == "function" then
        local ok, resolved = pcall(D.MaterializeRecord, record)
        if ok and type(resolved) == "table" then record = resolved end
    end
    if type(record) ~= "table" or type(record.fingerprint) ~= "string"
        or type(record.echoes) ~= "table" then return false, "schema" end
    local dps = tonumber(record.dps)
    local duration = tonumber(record.duration)
    local stamp = tonumber(record.ts)
    local level = tonumber(record.level)
    local player = tostring(record.player or "")
    local playerClass = type(record.class) == "string"
        and record.class:upper() or nil
    local validClass = playerClass == "WARRIOR" or playerClass == "PALADIN"
        or playerClass == "HUNTER" or playerClass == "ROGUE"
        or playerClass == "PRIEST" or playerClass == "DEATHKNIGHT"
        or playerClass == "SHAMAN" or playerClass == "MAGE"
        or playerClass == "WARLOCK" or playerClass == "DRUID"
    if record.category ~= "dummy" and record.category ~= "lk" then
        return false, "invalid_category"
    end
    if not FiniteNumber(duration)
        or not ValidDpsDuration(record.category, duration) then
        return false, "duration"
    end
    if not FiniteNumber(dps) or dps <= 0 or dps > 500000000
        or not FiniteNumber(stamp) or stamp <= 0
        or not FiniteNumber(level) or level < 1 or level > 80
        or level ~= math.floor(level) or not validClass
        or player == "" or #player > 64 or player:find("[%c|]") then
        return false, "schema"
    end
    local computed = D and D.GetEchoKey and D.GetEchoKey(record.echoes) or nil
    local directOwner = SamePeer(player, MyName())
    local relayContext
    if not directOwner then
        if not responseMode then return false, "owner_sender" end
        if record._originVerified ~= true then
            return false, "relay_authorization"
        end
        if type(responseContext) ~= "table" then
            return false, "outside_request"
        end
        relayContext = {
            n=responseContext.requester,
            i=responseContext.requestId,
            b=responseContext.bucket,
            c=record.category,
        }
        if not ValidDpsRelayContext(relayContext, player) then
            return false, "outside_request"
        end
    end
    local envelopeContext = type(responseContext) == "table"
        and Responder.RequestContext(responseContext.requester,
            responseContext.requestId, responseContext.bucket) or nil
    if not OwnerKeyMatchesAuthor(record.ownerKey, player) then
        return false, "owner_sender"
    end
    if not computed or computed ~= record.fingerprint then
        return false, "integrity"
    end
    local loadoutHash = record.loadoutHash
    if not loadoutHash and D and D.GetEchoHash then
        loadoutHash = D.GetEchoHash(record.echoes)
    end
    local computedHash = D and D.GetEchoHash and D.GetEchoHash(record.echoes)
        or nil
    if not loadoutHash or (computedHash and loadoutHash ~= computedHash) then
        return false, "integrity"
    end
    local payload = {
        v = tonumber(record.protocolVersion) or 5,
        h = loadoutHash,
        f = record.fingerprint,
        e = record.echoes,
        c = record.category, d = math.floor(dps),
        u = duration, t = stamp,
        p = player, l = level,
        k = record.class, o = record.ownerKey, r = record.realm,
        b = record.buildId,
        lk = (type(record.lockedEchoes)=="table" and #record.lockedEchoes>0)
             and record.lockedEchoes or nil,
        x = relayContext and {n=relayContext.n,i=relayContext.i,
            b=relayContext.b} or nil,
    }
    if responseMode then
        Reconciler.NoteStat("dpsSerializations", 1)
    end
    local encoded = Codec.Base64Encode(Codec.JSONEncode(payload))
    local transferId = tostring(payload.p) .. ":" .. tostring(payload.t) .. ":" .. tostring(payload.d)
    if not ValidTransferIdentifier(transferId)
        or #encoded > MAX_ENCODED_BYTES then return false, "schema" end
    local suffix = Responder.ContextSuffix(envelopeContext, true)
    local header = CODE_DPS2 .. "|" .. MyName() .. "|" .. transferId .. "|999/999|"
    local chunkSize = CHAT_LIMIT - CHAT_SAFETY - EscapedLen(header)
        - EscapedLen(suffix)
    if chunkSize < 24 then return false, "schema" end
    local total = math.ceil(#encoded / chunkSize)
    if total < 1 or total > 999 then return false, "schema" end
    local messages = {}
    for i = 1, total do
        local data = encoded:sub((i - 1) * chunkSize + 1, i * chunkSize)
        messages[#messages + 1] = string.format("%s|%s|%s|%d/%d|%s%s",
            CODE_DPS2, MyName(), transferId, i, total, data, suffix)
    end
    if responseMode then
        Reconciler.NoteStat("chunkMessagesBuilt", #messages)
    end
    prepared = {messages=messages, payload=payload,context=envelopeContext,
        originVerified=record._originVerified == true}
    local wireCost = PreparedWireCost(prepared, responseMode, false)
    local budgetWhy = ResponseBudgetReason(wireCost, responseBudget)
    if budgetWhy then
        return false, budgetWhy, prepared, wireCost.chunks,
            wireCost.bytes, wireCost.transfers
    end
    if not Responder.CanAdmit(#messages) then
        return false, "sync queue full", prepared
    end
    local queued, queueWhy = Transport.EnqueueBatch(messages, {
        requester=envelopeContext and envelopeContext.requester
            or relayContext and relayContext.n or nil,
        requestId=envelopeContext and envelopeContext.requestId
            or relayContext and relayContext.i or nil,
        transferId=transferId,buildId=tostring(payload.b or ""),
        dpsId=tostring(payload.f or ""),queueClass="bulk",
        enqueuedAt=Now(),expiresAt=Now() + PENDING_MAX_AGE,
    })
    if not queued then return false, queueWhy, prepared end
    LogEvent("TX","DPS2 [%s] %.0f by %s (%d chunks)",
        tostring(payload.c), payload.d, payload.p, total)
    if relayContext then
        stats.dpsRelayOffered = (stats.dpsRelayOffered or 0) + 1
        PeerObserve("dps_offer", {peer=relayContext.n,
            category=payload.c,
            outcome=queueWhy == "duplicate" and "duplicate" or "admitted"})
    end
    if responseMode then Reconciler.NoteStat("dpsAdmissions", 1) end
    return true, queueWhy, nil, wireCost.chunks, wireCost.bytes,
        wireCost.transfers
end

-- Legacy wrapper retained for older callers/peers.
function Sync.BroadcastDps(buildId, player, dps, level, category)
    if not (buildId and player and dps and dps > 0) then return false end
    local payload = string.format("%s|%s|%s|%s|%s|%s|%s",
        CODE_DPS, MyName(), buildId, tostring(player),
        tostring(math.floor(dps)), tostring(level or 0), category or "dummy")
    if EscapedLen(payload) > CHAT_LIMIT - CHAT_SAFETY then return false end
    return Transport.Enqueue(payload, {
        transferId="legacy-dps:" .. tostring(buildId) .. ":"
            .. tostring(player),buildId=tostring(buildId),
        dpsId=tostring(player),category=category or "dummy",
        queueClass="bulk",enqueuedAt=Now(),
        expiresAt=Now() + PENDING_MAX_AGE,
    })
end

function Sync.BroadcastDelete(build)
    if not build or not ValidIdentifier(tostring(build.id or ""),
        MAX_BUILD_ID_BYTES) then return false end
    local id = tostring(build.id)
    local author = tostring(build.author or MyName())
    if not SamePeer(author, MyName()) then return false end
    local existing = tombstones[id]
    local existingVersion = existing and (tostring(TombStamp(existing))
        .. ":" .. TombAuthor(existing)) or ""
    local existingKey = existing and Operation.Key("delete", id,
        existingVersion) or nil
    local active = existingKey and Operation.activeDeletes[existingKey] or nil
    if active and active.terminal ~= true
        and SamePeer(active.owner, author) then
        Operation.latestDelete = active
        return true, "already queued", Operation.Copy(active)
    end
    local previous = Operation.deleteById[id]
    local retryable = previous and previous.terminal == true
        and tostring(previous.id) == id
        and (previous.outcome == "expired" or previous.outcome == "dropped"
            or previous.outcome == "throttle-exhausted"
            or previous.outcome == "reset"
            or previous.outcome == "rejected")
    local tomb = retryable and existing
        and SamePeer(TombAuthor(existing), author)
        and tostring(previous.version) == existingVersion and existing or {
            stamp=tonumber((time and time()) or 0) or 0,author=author,
        }
    local tombStored, tombStoreWhy = CatalogSetTombstone(id, tomb)
    if tombStored == false then
        stats.storageRejected = (stats.storageRejected or 0) + 1
        local refused = Operation.NewDelete(id, tomb)
        Operation.latestDelete = refused
        Operation.Transition(refused, "rejected",
            tombStoreWhy or "tombstone storage refused")
        return false, tombStoreWhy or "tombstone storage refused",
            Operation.Copy(refused)
    end
    tombstones[id] = tomb
    hotBuilds[id] = nil
    RequestRetention("local delete stored")
    local status = Operation.NewDelete(id, tomb)
    Operation.latestDelete = status
    local queued, why = Transport.Enqueue(DeleteWireMessage(id, tomb),
        Operation.DeleteMetadata(id, tomb, status))
    if queued then
        ClearPendingDelete(id, tomb)
        Operation.Transition(status, "queued", "transport admitted")
        LogEvent("TX","delete '%s'", tostring(build.title or id))
        return true, "queued", Operation.Copy(status)
    end
    if why == "sync queue full" then
        if PendingDeleteCount() >= MAX_RECOVERY_QUEUE then
            Operation.Transition(status, "rejected",
                "delete retry queue full")
            return false, "delete retry queue full", Operation.Copy(status)
        end
        status.expiresAt = Now() + DELETE_RETRY_MAX_AGE
        status.retryAttempts = 0
        MarkDeletePending(id, tomb, status)
        Operation.Transition(status, "retry-pending", why)
        LogEvent("TX", "delete '%s' queued for retry",
            tostring(build.title or id))
        return false, "queued for retry", Operation.Copy(status)
    end
    Operation.Transition(status, "rejected", why)
    return false, why, Operation.Copy(status)
end

function Sync.GetDeleteStatus(id)
    local status = id ~= nil and Operation.deleteById[tostring(id)]
        or Operation.latestDelete
    if type(status) ~= "table" then return nil end
    return Operation.Copy(status)
end

------------------------------------------------------------------------
-- Incoming
------------------------------------------------------------------------

local function ShouldStore(id, lastMod, author)
    if not AllowsRemoteRevision(author, lastMod, id) then
        return false, "retention floor"
    end
    local tomb = tombstones[id]
    if tomb and (tonumber(lastMod) or 0) <= TombStamp(tomb) then return false, "deleted" end
    if tomb and (TombAuthor(tomb) == ""
        or not SamePeer(TombAuthor(tomb), author)) then
        return false, "tombstone owner"
    end
    local existing = CatalogGet(id)
    local known = seenRemoteIds[id]
    if known == nil and existing then
        known = tonumber(existing.lastModified) or tonumber(existing.postedAt) or 0
        seenRemoteIds[id] = known
    end
    if known == nil then return true, "new" end
    if existing and (existing.needsFullBuild
        or type(existing.echoes) ~= "table" or #existing.echoes == 0) then
        return true, "loadout"
    end
    if (tonumber(lastMod) or 0) > known then return true, "updated" end
    return false, "duplicate"
end

local function StoreReceivedBuild(payload, ownerVerified, relaySender,
        matchedReplacement, canonicalFingerprint)
    local existing = CatalogGet(payload.id)
    local mine = (existing and existing.isMine) or false
    -- A matching current summary makes an absent link authoritative. Legacy
    -- unsolicited full payloads retain the established local-link fallback.
    local link = payload.link
    if not matchedReplacement and link == nil then
        link = existing and existing.link or nil
    end
    local fingerprint = canonicalFingerprint
    if type(fingerprint) ~= "string" or fingerprint == "" then
        return false, "canonical fingerprint unavailable"
    end
    local record = {
        id=payload.id, title=payload.title, description=payload.description,
        author=payload.author,
        ownerKey=ownerVerified and payload.ownerKey or nil,
        class=payload.class, echoes=payload.echoes,
        postedAt=payload.postedAt, lastModified=payload.lastModified, isMine=mine,
        autoDps=payload.autoDps, fingerprint=fingerprint,
        fingerprintHash=HashText(fingerprint),
        echoCount=(function() local t=0; for _,e in ipairs(payload.echoes) do t=t+(tonumber(e.stacks or e.count) or 1) end; return t end)(),
        loadoutAvailable=true,
        link=link,
        linkHash=HashText(link), needsFullBuild=nil,
        ownerVerified=ownerVerified and true or false,
        relaySender=ownerVerified and nil or relaySender,
    }
    CatalogClearTombstone(payload.id)
    local stored, storedAs = CatalogPut(record)
    if stored == false then return false, storedAs end
    if storedAs == "baseline" then
        stats.baselineSkipped = (stats.baselineSkipped or 0) + 1
    end
    seenRemoteIds[payload.id] = payload.lastModified
    Session.ClearRequestedLoadout(payload.id, payload.lastModified)
    stats.received = stats.received + 1
    RequestRetention("full build received")
    return true, storedAs
end

local function CommitReceivedBuild(payload, transportSender, context)
    local directOwner = SamePeer(payload.author, transportSender)
    local existing, existingSource = CatalogGet(payload.id)
    local previousRemoteStamp = seenRemoteIds[payload.id]
    local replacingUnverified = existing and existing.ownerVerified == false
        and directOwner and SamePeer(existing.author, payload.author)
    local pending = Session.PendingReplacement(payload.id)
    local matchedReplacement = false
    local replacementFingerprint = BuildFingerprint(payload)
    if pending then
        local pendingStamp = tonumber(pending.lastModified) or 0
        local payloadStamp = tonumber(payload.lastModified) or 0
        if payloadStamp < pendingStamp then
            stats.duplicatesSkipped = stats.duplicatesSkipped + 1
            Responder.NoteContextOutcome(context, "duplicate", "stale")
            PeerObserve("receiver_commit", {id=payload.id,peer=transportSender,
                outcome="duplicate",reason="superseded replacement"})
            return true
        end
        if payloadStamp == pendingStamp then
            local fingerprint = replacementFingerprint
            local fingerprintHash = HashText(fingerprint)
            local total = 0
            for _, echo in ipairs(payload.echoes or {}) do
                total = total + (tonumber(echo.stacks or echo.count) or 1)
            end
            local link = payload.link
            local recordComplete = OrdinaryComplete({
                echoes=payload.echoes,fingerprint=fingerprint,
            })
            local matches = directOwner and recordComplete
                and SamePeer(pending.author, payload.author)
                and tostring(pending.title) == tostring(payload.title)
                and tostring(pending.ownerKey or "")
                    == tostring(payload.ownerKey or "")
                and tostring(pending.class or "")
                    == tostring(payload.class or "")
                and tostring(pending.fingerprintHash)
                    == tostring(fingerprintHash or ""):lower()
                and tostring(pending.linkHash or "")
                    == tostring(HashText(link) or "")
                and tonumber(pending.echoCount or 0) == total
                and (pending.autoDps and true or false)
                    == (payload.autoDps and true or false)
            if not matches then
                Responder.NoteContextOutcome(context, "rejected", "integrity")
                PeerObserve("receiver_commit", {id=payload.id,
                    peer=transportSender,outcome="rejected",
                    reason="replacement identity"})
                LogEvent("RX", "REJECT '%s': pending replacement mismatch",
                    tostring(payload.title))
                return false
            end
            matchedReplacement = true
        end
    end
    local allowed, why
    if replacingUnverified then
        allowed, why = true, "owner-verified"
    else
        allowed, why = ShouldStore(payload.id, payload.lastModified,
            payload.author)
    end
    if not allowed then
        if why == "deleted" then
            LogEvent("RX","skip '%s': tombstoned", tostring(payload.title))
            Responder.NoteContextOutcome(context, "rejected", "tombstone")
        elseif why == "tombstone owner" then
            LogEvent("RX", "REJECT resurrection of '%s': tombstone belongs to %s",
                tostring(payload.id), tostring(TombAuthor(tombstones[payload.id])))
            Responder.NoteContextOutcome(context, "rejected", "ownership")
        else
            stats.duplicatesSkipped = stats.duplicatesSkipped + 1
            if existingSource == "bundled" then
                stats.baselineSkipped = (stats.baselineSkipped or 0) + 1
                Responder.NoteContextOutcome(context, "baseline", "bundled")
            else
                Responder.NoteContextOutcome(context, "duplicate", why == "duplicate"
                    and "duplicate" or "stale")
            end
            LogEvent("RX","skip '%s': DUPLICATE (have stamp %s)",
                tostring(payload.title), tostring(seenRemoteIds[payload.id]))
        end
        PeerObserve("receiver_commit", {id=payload.id,peer=transportSender,
            outcome=why == "deleted" and "tombstoned" or "duplicate",
            reason=why})
        return true
    end
    if existing and not directOwner then
        LogEvent("RX", "REJECT relayed overwrite of '%s' from %s",
            tostring(payload.id), tostring(transportSender))
        PeerObserve("receiver_commit", {id=payload.id,peer=transportSender,
            outcome="rejected",reason="relayed overwrite"})
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        return false
    end
    if existing and existing.isMine then
        LogEvent("RX", "REJECT remote overwrite of local build '%s'",
            tostring(payload.id))
        PeerObserve("receiver_commit", {id=payload.id,peer=transportSender,
            outcome="rejected",reason="local owner"})
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        return false
    end
    if existing and not SamePeer(existing.author, payload.author) then
        LogEvent("RX", "REJECT owner change for '%s'", tostring(payload.id))
        PeerObserve("receiver_commit", {id=payload.id,peer=transportSender,
            outcome="rejected",reason="owner change"})
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        return false
    end
    local stored, storedWhy = StoreReceivedBuild(
        payload, directOwner, transportSender, matchedReplacement,
        replacementFingerprint)
    if not stored then
        stats.storageRejected = (stats.storageRejected or 0) + 1
        Responder.NoteContextOutcome(context, "rejected", "storage")
        PeerObserve("receiver_commit", {id=payload.id,peer=transportSender,
            outcome="store_failed",reason="storage",echoes=#payload.echoes})
        LogEvent("RX", "REJECT '%s': local storage refused",
            tostring(payload.title))
        return false
    end
    if why == "updated" then
        stats.updated = (stats.updated or 0) + 1
        LogEvent("RX","UPDATED '%s' by %s (%d echoes, %s->%s)",
            tostring(payload.title), tostring(payload.author), #payload.echoes,
            tostring(previousRemoteStamp), tostring(payload.lastModified))
    elseif why == "loadout" then
        LogEvent("RX","LOADED exact Echo list for '%s' by %s (%d echoes)",
            tostring(payload.title), tostring(payload.author), #payload.echoes)
    else
        LogEvent("RX","STORED (new) '%s' by %s (%d echoes)",
            tostring(payload.title), tostring(payload.author), #payload.echoes)
    end
    local outcome = why == "new" and "new" or "updated"
    if storedWhy == "baseline" then
        Responder.NoteContextOutcome(context, "baseline", "bundled")
    else
        Session.NoteReceived(Responder.ContextRequestId(context), outcome)
    end
    PeerObserve("receiver_commit", {id=payload.id,peer=transportSender,
        outcome=why or "stored",echoes=#payload.echoes})
    Sync.RequestDataViewRefresh()
    return true
end

local function HandleRequest(requester, peerBuildHash, peerDpsHash, requestId)
    local accepted = Reconciler.ScheduleRequest({
        requester=requester,
        peerBuildHash=peerBuildHash or "0",
        peerDpsHash=peerDpsHash or "0",
        requestId=requestId,
    })
    if accepted then
        stats.dpsRequestsReceived = (stats.dpsRequestsReceived or 0) + 1
        PeerObserve("dps_request", {peer=requester,outcome="scheduled"})
    end
    return accepted
end

function Responder.PrepareResponseEntry(entry)
    return Reconciler.PrepareResponseEntry(entry)
end

function Responder.ResetResponseEntry(entry)
    return Reconciler.ResetResponseEntry(entry)
end

local function HandleClaim(responder, requester, requestId, buildHash, dpsHash)
    local handled = Reconciler.HandleLegacyClaim({
        responder=responder, requester=requester, requestId=requestId,
        buildHash=buildHash, dpsHash=dpsHash,
    })
    if handled then return true end
    if SamePeer(requester, MyName()) and Session
        and type(Session.NotePeerClaim) == "function" then
        return Session.NotePeerClaim(requestId, buildHash, dpsHash)
    end
    return false
end

local function HandleBucketClaim(responder, requester, requestId, kind, bucket, bucketHash)
    local handled = Reconciler.HandleBucketClaim({
        responder=responder, requester=requester, requestId=requestId,
        kind=kind, bucket=bucket, hash=bucketHash,
    })
    if handled then return true end
    if SamePeer(requester, MyName()) then
        if Session.AcceptsResponse(requestId) then return true end
        Session.NoteOutcome(requestId, "unrelated", "request_auth")
    end
    return false
end

function Responder.NextReadyBucket(entry)
    return Reconciler.NextReadyBucket(entry)
end

function Responder.SelectFairUnit(units)
    return Reconciler.SelectFairUnit(units)
end

function Responder.ProcessLoadoutResponse(entry)
    return Reconciler.ProcessLoadoutResponse(entry)
end

local function ProcessPendingResponses(elapsed)
    return Reconciler.Process(elapsed)
end

local function HandleDelete(sender, buildId, stamp, originAuthor, context)
    local existing = CatalogGet(buildId)
    -- originAuthor is an optional 5th field; treat empty string same as nil
    local author = tostring((originAuthor and originAuthor ~= "")
        and originAuthor or sender or "")
    if not SamePeer(sender, author) then
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        LogEvent("RX", "REJECT relayed delete for '%s' from %s",
            tostring(buildId), tostring(sender))
        return false
    end
    local tomb = { stamp=tonumber(stamp) or 0, author=author }
    local prior = tombstones[buildId]
    if prior and TombStamp(prior) >= tomb.stamp then
        Responder.NoteContextOutcome(context, "duplicate", "stale")
        return true
    end
    if not existing then
        Responder.NoteContextOutcome(context, "rejected", "tombstone")
        LogEvent("RX", "REJECT unprovable tombstone for unknown build '%s'",
            tostring(buildId))
        return false
    end
    if existing.isMine then
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        LogEvent("RX","ignoring delete for MY build '%s' relayed by %s",
            tostring(existing.title), tostring(sender))
        return false
    end
    if not SamePeer(existing.author, sender) then
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        LogEvent("RX","REJECT delete of '%s': origin %s is not the author (%s)",
            tostring(existing.title), author, tostring(existing.author))
        return false
    end
    local tombStored = CatalogSetTombstone(buildId, tomb)
    if tombStored == false then
        stats.storageRejected = (stats.storageRejected or 0) + 1
        Responder.NoteContextOutcome(context, "rejected", "storage")
        LogEvent("RX", "REJECT delete of '%s': local storage refused",
            tostring(existing.title))
        return false
    end
    tombstones[buildId] = tomb
    seenRemoteIds[buildId] = nil
    Session.ClearRequestedLoadout(buildId)
    LogEvent("RX","DELETED '%s' from origin %s (relay %s)",
        tostring(existing.title), author, tostring(sender))
    Sync.RequestDataViewRefresh()
    RequestRetention("remote delete received")
    Responder.NoteContextOutcome(context, "updated", "accepted")
    return true
end

-- CHAT_MSG_CHANNEL handler. The wire has | escaped to || on send;
-- since none of our fields ever contain a literal |, collapsing ||→|
-- is unambiguous.
local function RejectIncoming(reason)
    stats.malformedRejected = (stats.malformedRejected or 0) + 1
    if Session and type(Session.NoteOutcome) == "function" then
        Session.NoteOutcome(nil, "rejected", "malformed")
    end
    LogEvent("RX", "REJECT envelope: %s", tostring(reason or "malformed"))
    return false
end

local function AcceptPeer(sender, version)
    local parsed = version and Nexus.Version and Nexus.Version.Parse
        and Nexus.Version.Parse(version) or nil
    local marked = Session.MarkPeer(sender,
        parsed and parsed.normalized or nil)
    if marked and parsed and Nexus.Updates and Nexus.Updates.Observe then
        pcall(Nexus.Updates.Observe, parsed, sender)
    end
    return true
end

local InboundFactory = Nexus.SyncInternals and Nexus.SyncInternals.Inbound
if not (InboundFactory and type(InboundFactory.New) == "function") then
    error("Nexus SyncInbound must load before Sync")
end
Inbound = InboundFactory.New({
    codes={
        presence=CODE_PRESENCE,
        request=CODE_REQUEST,
        claim=CODE_CLAIM,
        bucketClaim=CODE_BUCKET_CLAIM,
        delete=CODE_DELETE,
        index=CODE_INDEX,
        loadoutRequest=CODE_LOADOUT_REQ,
        loadoutClaim=CODE_LOADOUT_CLAIM,
        dpsLegacy=CODE_DPS,
        dps=CODE_DPS2,
        build=CODE_BUILD,
    },
    peerCodes=PEER_PROTOCOL_CODES,
    bucketCount=BUILD_BUCKETS,
    maxWireBytes=MAX_WIRE_BYTES,
    maxBuildIdBytes=MAX_BUILD_ID_BYTES,
    maxRequestIdBytes=MAX_REQUEST_ID_BYTES,
    maxHashBytes=MAX_HASH_BYTES,
    maxChunkBytes=MAX_CHUNK_BYTES,
    maxChunks=MAX_CHUNKS,
    maxEncodedBytes=MAX_ENCODED_BYTES,
    maxInflightGlobal=MAX_INFLIGHT_GLOBAL,
    maxInflightPerSender=MAX_INFLIGHT_PER_SENDER,
    inflightGrace=INFLIGHT_GRACE,
    inflightMaxAge=INFLIGHT_MAX_AGE,
    now=Now,
    normalizePeerName=NormalizePeerName,
    sameTransportSender=SameTransportSender,
    samePeer=SamePeer,
    splitWire=SplitWire,
    validField=ValidField,
    validIdentifier=ValidIdentifier,
    validTransferIdentifier=ValidTransferIdentifier,
    validPeerName=ValidPeerName,
    validHash=ValidHash,
    validVersion=ValidVersion,
    validIntegerText=ValidIntegerText,
    base64Decode=function(value) return Codec.Base64DecodeNetwork(value) end,
    jsonDecode=function(value) return Codec.JSONDecodeNetwork(value) end,
    validatePayload=ValidateNetworkPayload,
    validateDpsPayload=ValidateNetworkDpsPayload,
    noteDpsRejection=function(reason)
        local D = Nexus and Nexus.DpsCapture
        if D and type(D.NoteReceiveRejection) == "function" then
            D.NoteReceiveRejection(reason)
        end
    end,
    log=LogEvent,
    rejectIncoming=RejectIncoming,
    noteMalformed=function()
        stats.malformedRejected = (stats.malformedRejected or 0) + 1
        if Session and type(Session.NoteOutcome) == "function" then
            Session.NoteOutcome(nil, "rejected", "malformed")
        end
    end,
    acceptPeer=AcceptPeer,
    noteOutcome=function(context, outcome, reason)
        return Responder.NoteContextOutcome(context, outcome, reason)
    end,
    noteInbound=function(description)
        if type(description) == "table" and description.requester
            and not SamePeer(description.requester, MyName()) then
            return false
        end
        local requestId = type(description) == "table"
            and description.requestId or nil
        if not Session.AcceptsResponse(requestId) then return false end
        return Session.NoteInbound(requestId)
    end,
    handleRequest=function(description)
        return HandleRequest(description.requester,
            description.peerBuildHash, description.peerDpsHash,
            description.requestId)
    end,
    handleLegacyClaim=function(description)
        return HandleClaim(description.responder, description.requester,
            description.requestId, description.buildHash, description.dpsHash)
    end,
    handleBucketClaim=function(description)
        return HandleBucketClaim(description.responder, description.requester,
            description.requestId, description.kind, description.bucket,
            description.hash)
    end,
    handleDelete=function(description)
        return HandleDelete(description.sender, description.buildId,
            description.stamp, description.originAuthor, description.context)
    end,
    handleSummary=StoreSummary,
    requestDataViewRefresh=function()
        return Sync.RequestDataViewRefresh()
    end,
    handleLoadoutRequest=function(description)
        return Reconciler.ScheduleLoadout(description)
    end,
    handleLoadoutClaim=function(description)
        local handled = Reconciler.HandleLoadoutClaim(description)
        if handled then return true end
        if SamePeer(description.requester, MyName())
            and description.requestId ~= nil then
            if Session.AcceptsResponse(description.requestId) then return true end
            Session.NoteOutcome(description.requestId, "unrelated", "request_auth")
        end
        return false
    end,
    validateDpsRelay=function(record, sender, envelopeContext)
        local context = type(record) == "table" and record.x or nil
        local D = Nexus and Nexus.DpsCapture
        local player = type(record) == "table"
            and (record.p or record.player) or nil
        local category = type(record) == "table"
            and (record.c or record.category) or nil
        local directOwner = SamePeer(player, sender)
        local marked = Responder.SupportsRequestContext(context and context.i)
        -- Old protocol-7 responders can echo the marked request in relay JSON
        -- but cannot add the Stage 36.3 envelope suffix.  Preserve that
        -- authorized relay as ambient input; contextual peers must still match
        -- x and envelope exactly before they can affect request progress.
        local envelopeMatches = envelopeContext == nil
            or (marked and type(envelopeContext) == "table"
                and SamePeer(context.n, envelopeContext.requester)
                and tostring(context.i) == tostring(envelopeContext.requestId)
                and tonumber(context.b) == tonumber(envelopeContext.bucket))
        local valid
        if directOwner then
            valid = context == nil and type(envelopeContext) == "table"
                and ValidDpsRelayContext({n=envelopeContext.requester,
                    i=envelopeContext.requestId,b=envelopeContext.bucket,
                    c=category}, player)
        else
            valid = Session.AcceptsResponse(context and context.i)
                and type(context) == "table"
                and SamePeer(context.n, MyName())
                and envelopeMatches
                and ValidDpsRelayContext({n=context.n,i=context.i,b=context.b,
                    c=category}, player)
                and D and type(D.ReceiveRelayedRecord) == "function"
        end
        if not valid then
            Responder.NoteContextOutcome(envelopeContext, "rejected",
                "request_auth")
            if D and type(D.NoteReceiveRejection) == "function" then
                D.NoteReceiveRejection(directOwner and "outside_request"
                    or type(context) == "table"
                        and "outside_request" or "owner_sender")
            end
            local rejectedKey = directOwner and "dpsDirectRejected"
                or "dpsRelayRejected"
            stats[rejectedKey] = (stats[rejectedKey] or 0) + 1
            PeerObserve("dps_commit", {peer=sender,outcome="rejected",
                reason="outside requested response"})
        end
        return valid and true or false
    end,
    commitDps=function(record, sender, relayed, context)
        local dps = Nexus and Nexus.DpsCapture
        local receiver = relayed and dps and dps.ReceiveRelayedRecord
            or dps and dps.ReceiveRecord
        if type(receiver) ~= "function" then
            Responder.NoteContextOutcome(context, "rejected", "storage")
            return false
        end
        local ok, accepted, rejectionReason = pcall(receiver, record, sender)
        if not (ok and accepted) then
            local key = relayed and "dpsRelayRejected" or "dpsDirectRejected"
            stats[key] = (stats[key] or 0) + 1
            if ok and rejectionReason == "storage" then
                stats.storageRejected = (stats.storageRejected or 0) + 1
            end
            PeerObserve("dps_commit", {peer=sender,outcome="rejected",
                reason=ok and rejectionReason or "receiver failure"})
            Responder.NoteContextOutcome(context, "rejected", "storage")
            return false
        end
        local key = relayed and "dpsRelayAccepted" or "dpsDirectAccepted"
        stats[key] = (stats[key] or 0) + 1
        PeerObserve("dps_commit", {peer=sender,outcome="accepted",
            category=record.c or record.category,
            relay=relayed and true or false})
        -- Mesh redistribution retains the established accepted-record path.
        if not relayed then Sync.BroadcastDpsRecord(record) end
        local buildId = record.b or record.buildId
        local build = buildId and CatalogGet(buildId)
        if build and type(build.echoes) == "table" and #build.echoes > 0 then
            pcall(Sync.BroadcastBuild, build)
        end
        Responder.NoteContextOutcome(context, "updated", "accepted")
        return true
    end,
    commitBuild=CommitReceivedBuild,
    observe=PeerObserve,
})

local SessionFactory = Nexus.SyncInternals and Nexus.SyncInternals.Session
if not (SessionFactory and type(SessionFactory.New) == "function") then
    error("Nexus SyncSession must load before Sync")
end
Session = SessionFactory.New({
    receiveWindow=RECEIVE_WINDOW,
    inflightGrace=INFLIGHT_GRACE,
    requestCooldown=REQUEST_COOLDOWN,
    autoSyncDelay=AUTO_SYNC_DELAY,
    autoSyncMinPass=AUTO_SYNC_MIN_PASS,
    autoSyncQuiet=AUTO_SYNC_QUIET,
    maxConvergenceAge=CONVERGENCE_MAX_AGE,
    maxReceiveAge=RECEIVE_MAX_AGE,
    maxPasses=AUTO_SYNC_MAX_PASSES,
    joinRetryInterval=JOIN_RETRY_INTERVAL,
    joinMaxAttempts=JOIN_MAX_ATTEMPTS,
    maxRecoveryQueue=MAX_RECOVERY_QUEUE,
    maxKnownPeers=MAX_KNOWN_PEERS,
    chatLimit=CHAT_LIMIT,
    requestCode=CODE_REQUEST,
    loadoutRequestCode=CODE_LOADOUT_REQ,
    now=Now,
    myName=MyName,
    normalizePeerName=NormalizePeerName,
    bumpSync=BumpSync,
    log=LogEvent,
    validIdentifier=function(buildId)
        return ValidIdentifier(buildId, MAX_BUILD_ID_BYTES)
    end,
    catalogGet=CatalogGet,
    getCatalog=Catalog,
    getDpsCapture=function() return Nexus and Nexus.DpsCapture end,
    getAdapter=function() return Adapter end,
    getCodec=function() return Codec end,
    playerLevel=function()
        return UnitLevel and UnitLevel("player") or 0
    end,
    requestVersion=function()
        return (Nexus and Nexus.VERSION) or "0.0.0-dev"
    end,
    statusVersion=function()
        return (Nexus and Nexus.VERSION) or "?"
    end,
    currentBuildHash=CurrentBuildHash,
    currentClaimBuildHash=CurrentBuildHash,
    currentDpsHash=CurrentDpsHash,
    enqueue=function(message, metadata)
        return Transport.Enqueue(message, metadata)
    end,
    enqueueControl=function(message, metadata)
        return Transport.EnqueueControl(message, metadata)
    end,
    cancelRequest=function(requestId, requester)
        return Transport.CancelRequest(requestId, requester)
    end,
    noteRequestOutcome=function(snapshot)
        return Diagnostics.UpdateRequestOutcome(snapshot)
    end,
    transportSnapshot=function() return Transport.Snapshot() end,
    transportHasPending=function() return Transport.HasPending() end,
    inboundHasPending=function() return Inbound.HasPending() end,
    reconcilerHasPending=function() return Reconciler.HasPending() end,
    pendingDeleteCount=PendingDeleteCount,
    rejectRecoveryOverflow=RejectRecoveryOverflow,
    isConnected=function() return Sync.IsConnected() end,
    ensureChannel=function() return Sync.EnsureChannel() end,
    sendWhisper=function(message, target)
        return SendChatMessage(message, "WHISPER", nil, target)
    end,
})

function Sync.HandleIncoming(text, sender)
    return Inbound.HandleIncoming(text, sender)
end

-- Manual Sync Now uses the same bounded convergence passes as login and can
-- supersede stale automatic work without duplicating outstanding transfers.
function Sync.RequestSync()
    return Session.RequestSync()
end

function Sync.GetLeaderboardSyncStatus()
    local session = Session.StatusSnapshot()
    local transport = Transport.Snapshot()
    local requestTransport = Transport.RequestSnapshot(MyName(),
        session.requestId)
    local requestIncoming = Inbound.RequestCounts(MyName(), session.requestId)
    local work = Diagnostics.ProjectSyncWork({
        transport=transport,
        reconciliation=Reconciler.Counts(),
        incoming=Inbound.Counts(),
        session=session,
        requestRelated=requestTransport.requestRelated
            + requestIncoming.total,
        requestOutstandingTransfers=requestTransport.outstandingTransfers,
        pendingDeletes=PendingDeleteCount(),
        pendingDeleteDiscovery=Operation.deleteDiscoveryComplete and 0 or 1,
        pendingShares=pendingShare and 1 or 0,
    })
    return Diagnostics.ProjectLeaderboardStatus({
        work=work,
        throttleRemaining=Transport.ThrottleRemaining(),
        converging=session.converging,
        receiving=session.receiving,
    })
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------

function Sync.TombstoneCount()
    local n = 0; for _ in pairs(tombstones) do n=n+1 end; return n
end

function Sync.OnUpdate(elapsed)
    Inbound.CleanExpired()
    ProcessPendingResponses(elapsed)
    Session.PumpRecovery(elapsed)
    if not Sync._pendingDeleteScheduled then
        PumpPendingDeletes(elapsed)
        PumpPendingShare(elapsed)
    end
    Transport.Pump(elapsed)
    if Sync.FlushStatusReply then Sync.FlushStatusReply() end
    Session.UpdateAutoSync(elapsed)
    Session.UpdateAutoConvergence()
    Session.UpdateJoinRetry(elapsed)
end

------------------------------------------------------------------------
-- Peer status exchange (dev diagnostic, internal)
-- Sends a compact base64 JSON token via WHISPER on request.
-- Looks identical to a normal sync handshake; decodable only by a dev
-- client that knows the field mapping.  Regular clients never request
-- this and never see anything unusual.
------------------------------------------------------------------------

function Sync.HandleStatusRequest(sender, requestId)
    return Session.HandleStatusRequest(sender, requestId)
end

function Sync.FlushStatusReply()
    return Session.FlushStatusReply()
end

-- Send a status token to a specific player on demand (dev use only).
function Sync.SendStatusTo(target)
    return Session.SendStatusTo(target)
end

function Sync.Init(codec, adapter)
    Codec, Adapter = codec, adapter
    -- Explicit Init remains the destructive session boundary. Publish exact
    -- terminal ownership before clearing queues; ordinary world transitions
    -- use OnWorldEntry and never enter this path.
    Diagnostics.ResetStats()
    Transport.Reset("reset")
    if pendingShare and type(pendingShare.status) == "table" then
        Operation.Transition(pendingShare.status, "reset", "explicit reset")
    end
    for _, status in pairs(pendingDeletes) do
        if type(status) == "table" then
            Operation.Transition(status, "reset", "explicit reset")
        end
    end
    Inbound.Reset()
    Session.Reset()
    Compatibility.Reset()
    Reconciler.Reset()
    hotBuilds    = {}  -- clear on init
    local evidence = Nexus and Nexus.LoadoutEvidence
    if evidence and type(evidence.RegisterReferenceProvider) == "function" then
        evidence.RegisterReferenceProvider("sync.hot-builds", function()
            local references = {}
            for _, hot in pairs(hotBuilds) do
                local build = hot and hot.build
                if type(build) == "table"
                    and type(build.evidenceKey) == "string" then
                    references[#references + 1] = build.evidenceKey
                end
            end
            return references
        end)
    end
    pendingDeletes = {}
    pendingDeleteTicker = 0
    pendingShare = nil
    pendingShareTicker = 0
    Operation.active, Operation.activeShares, Operation.activeDeletes = {}, {}, {}
    Sync._pendingDeleteScheduled = false
    -- Keep login initialization constant-time. Existing build timestamps are
    -- resolved lazily in ShouldStore instead of walking the entire library
    -- during PLAYER_ENTERING_WORLD.
    seenRemoteIds = {}
    NexusDB = NexusDB or {}
    if Catalog() and Catalog().Init then
        Catalog().Init(NexusDB, Nexus.BundledBuilds)
    end
    local catalogStatus = Catalog() and Catalog().Status
        and Catalog().Status() or nil
    if type(catalogStatus) == "table"
        and catalogStatus.readOnly == true then
        -- A newer catalog schema owns the complete SavedVariables shape,
        -- including any tombstone table already present. Bind an empty runtime
        -- view so older recovery logic can neither normalize nor replay it.
        tombstones = {}
    elseif type(NexusDB.syncTombstones) == "table" then
        tombstones = NexusDB.syncTombstones
    else
        NexusDB.syncTombstones = {}
        tombstones = NexusDB.syncTombstones
    end
    Operation.deleteCursor = nil
    Operation.deleteDiscoveryComplete = false
    -- Restore only bounded admission markers. Additional persisted pending
    -- tombstones are discovered resumably as capacity opens; their uncapped
    -- storage and unknown fields remain untouched.
    Operation.DiscoverPendingDeletes(MAX_RECOVERY_QUEUE)
    local scheduler = Nexus and Nexus.Scheduler
    if scheduler and scheduler.IsInitialized and scheduler.IsInitialized()
        and type(scheduler.Every) == "function" then
        local scheduled = scheduler.Every("sync.pending-deletes", 1, function()
            PumpPendingDeletes(1)
            PumpPendingShare(1)
        end)
        Sync._pendingDeleteScheduled = scheduled == true
    end
    Transport.InstallFilters()
    Sync.EnsureChannel()
end
