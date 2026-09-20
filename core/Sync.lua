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
-- MASTER-RC-019: the delete retry bounds were removed with the retry pump.
-- A local row-to-tombstone operation is an unconditional zero-wire refusal
-- (architecture line 4856), so no delete ever acquires retry ownership and
-- there is no age or attempt budget left to bound.

------------------------------------------------------------------------
-- Module state
------------------------------------------------------------------------

local Codec, Adapter, Transport, Compatibility, Reconciler, Inbound
local Diagnostics, Session
local channelIndex
local seenRemoteIds  = {}   -- id -> lastModified we already hold
local tombstones     = {}   -- id -> stamp; never resurrect
local hotBuilds      = {}   -- id -> { build, t }; recently posted, include in answers
local registeredHotBuildEvidenceOwner
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
local Now, MyName, CurrentTransportSender, IsLocalTransportSender
local RelayEligible
local recentBuildBroadcast = {}
local BUILD_BROADCAST_DEDUPE = 2
local Responder = {state={hotBuildGeneration=0}, Work={}}
-- Session-only owner of validated inbound items that the catalog refused
-- without a ticket because another transaction owned admission. It is a field
-- because this chunk is at the Lua limit of 200 local variables.
Responder.Admission = {order={}, byKey={}, count=0, maxTotal=64, maxPerSender=16}
local catalogMutationIdentity
local PendingDeleteCount

local function Catalog()
    return Nexus and Nexus.BuildCatalog
end

local function CatalogGet(id)
    local catalog = Catalog()
    if not (catalog and catalog.Get) then return nil end
    return catalog.Get(id)
end

local function HotBuildEvidenceReferences()
    local references = {}
    for _, hot in pairs(hotBuilds) do
        local build = hot and hot.build
        if type(build) == "table"
            and type(build.evidenceKey) == "string" then
            references[#references + 1] = build.evidenceKey
        end
    end
    return references
end

function Responder.Work.RememberHotBuild(id, hot)
    hotBuilds[id] = hot
    Responder.state.hotBuildGeneration =
        (Responder.state.hotBuildGeneration or 0) + 1
end

function Responder.Work.ForgetHotBuild(id)
    if hotBuilds[id] == nil then return false end
    hotBuilds[id] = nil
    Responder.state.hotBuildGeneration =
        (Responder.state.hotBuildGeneration or 0) + 1
    return true
end

local function EnsureHotBuildEvidenceProvider()
    local evidence = Nexus and Nexus.LoadoutEvidence
    if evidence == registeredHotBuildEvidenceOwner then return true end
    if not (evidence
        and type(evidence.RegisterReferenceProvider) == "function") then
        return false
    end
    local registered = evidence.RegisterReferenceProvider(
        "sync.hot-builds", HotBuildEvidenceReferences)
    if registered then registeredHotBuildEvidenceOwner = evidence end
    return registered == true
end

-- Register stable Sync evidence ownership before catalog admission. A later
-- owner replacement still requires an explicit rebind through Sync.Init.
EnsureHotBuildEvidenceProvider()

-- Every catalog write names its exact source so the central admission owner
-- derives provenance itself; Sync never clears a tombstone before a write.
local function CatalogPut(build, options)
    local catalog = Catalog()
    if not (catalog and catalog.Put) then return false end
    return catalog.Put(build, options)
end

local function CatalogSetTombstone(id, tomb, options)
    local catalog = Catalog()
    if not (catalog and catalog.SetTombstone) then return false end
    return catalog.SetTombstone(id, tomb, options)
end

local function BindCatalogCompletion(ticket, callback)
    local catalog = Catalog()
    local identity = catalogMutationIdentity
    local database = catalog and catalog.BoundDatabase()
    if not (catalog and type(catalog.BindMutationCompletion) == "function") then
        return false
    end
    return catalog.BindMutationCompletion(ticket, function(outcome)
        if catalogMutationIdentity ~= identity or Catalog() ~= catalog then return end
        local committed = outcome.committed == true and outcome.state == "committed"
            and outcome.database == database and catalog.BoundDatabase() == database
            and rawget(database, "authorityBundle") == outcome.bundle
        callback(committed, committed and outcome.storedAs or outcome.reason)
    end)
end

-- The catalog's fixed state reason when its root is not serving. Inbound
-- work refused for that reason is a local storage refusal, not malformed or
-- unknown data: the durable row exists and is reserved deny-only.
local function CatalogRootRefusal()
    local catalog = Catalog()
    if not (catalog and type(catalog.RootState) == "function") then return nil end
    local root = catalog.RootState()
    if type(root) ~= "table" or root.state == "ROOT_ADMITTED" then return nil end
    return tostring(root.reason or root.state)
end

-- Fixed-shape tombstone reservation view. Sync never holds the raw
-- SavedVariables tombstone table; a NONE state returns nil.
local function CatalogTombstoneView(id)
    local catalog = Catalog()
    if not (catalog and type(catalog.TombstoneState) == "function") then return nil end
    local view = catalog.TombstoneState(id)
    if type(view) ~= "table" or view.state == "NONE" then return nil end
    return view
end

-- Bounded compatibility map of every tombstone reservation: the same
-- `{stamp, author, ownerKey, ownerVerified}` token shape the exact PR #68
-- bucket hash uses, plus the session-only `localOwned` verdict.
local function TombstoneMap()
    local catalog = Catalog()
    if not (catalog and type(catalog.TombstoneSnapshot) == "function") then
        return {}
    end
    local snapshot = catalog.TombstoneSnapshot()
    return type(snapshot) == "table" and snapshot or nil
end

-- Protocol 7 gains no typed envelope. Only an exact 1..96-byte, UTF-8,
-- delimiter-free identifier is representable; everything else stops before
-- any message, header, request, correlation, queue, or bucket key exists.
local function WireBuildId(id)
    if type(id) ~= "string" then return nil, "PROTOCOL7_TYPED_ID_UNREPRESENTABLE" end
    if #id > MAX_BUILD_ID_BYTES then return nil, "PROTOCOL7_ID_WIDTH_UNREPRESENTABLE" end
    if not Identity.ValidUtf8(id) then return nil, "PROTOCOL7_ID_UNREPRESENTABLE" end
    return id
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
    return Identity.PlayerKey(name, true) or ""
end

local function CatalogRecordRevision(id)
    local catalog = Catalog()
    if not (catalog and type(catalog.RecordRevision) == "function") then
        return nil, nil
    end
    return catalog.RecordRevision(id)
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
    if IsLocalTransportSender(context.requester) then return context.requestId end
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
    local requestIncoming = Inbound.RequestCounts(
        CurrentTransportSender(), session.requestId)
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
        deferredAdmissions=Responder.Admission.count,
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

local function CurrentOwnerKey()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = GetRealmName and GetRealmName()
    end
    if not realm or realm == "" then return nil end
    local ownerKey = Identity.OwnerKey(MyName(), realm)
    if ownerKey and not ownerKey:match("@unknown$") then return ownerKey end
    return nil
end

CurrentTransportSender = function()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then realm = GetRealmName and GetRealmName() end
    realm = type(realm) == "string" and realm:gsub("%s+", "") or nil
    local full = realm and (tostring(MyName()) .. "-" .. realm) or nil
    return Identity.PlayerKey(full, true) and full or MyName()
end

IsLocalTransportSender = function(sender)
    local transportOwner = Identity.CanonicalOwnerFromTransport(sender)
    local localOwner = CurrentOwnerKey()
    return transportOwner ~= nil and localOwner ~= nil
        and transportOwner == localOwner
end

local function TrustedStoredOwnerKey(record, source)
    if type(record) ~= "table" then return nil end
    local verified = Identity.VerifiedOwnerKey(record)
    if verified then return verified end
    if source == "bundled" then
        return Identity.CoherentRecordOwnerKey(record)
    end
    return nil
end

local function LocalOwnsStoredBuild(record)
    local localOwner = CurrentOwnerKey()
    return type(record) == "table" and record.isMine == true
        and localOwner ~= nil
        and Identity.LocalOwnsBuild(record, localOwner)
end

local function OwnerKeyIsLocal(ownerKey)
    local localOwner = CurrentOwnerKey()
    return localOwner ~= nil
        and Identity.CanonicalOwnerKey(ownerKey) == localOwner
end

-- Exact owner traffic may replace evidence that was retained without durable
-- authority. The claimed key is evidence only: it can constrain a later
-- promotion, but never grants relay, edit, or delete authority by itself.
local function CanPromoteStoredOwner(record, ownerKey)
    if type(record) ~= "table" or Identity.VerifiedOwnerKey(record) ~= nil then
        return false
    end
    local incomingOwner = Identity.CanonicalOwnerKey(ownerKey)
    if not incomingOwner then return false end

    local claimedKey = Identity.CanonicalOwnerKey(record.claimedOwnerKey)
    local storedKey = Identity.CanonicalOwnerKey(record.ownerKey)
    if claimedKey and storedKey and claimedKey ~= storedKey then return false end
    local claimedOwner = claimedKey or storedKey
    if claimedOwner then return claimedOwner == incomingOwner end

    -- Older retained rows that lost their claim remain ambiguous. Do not infer
    -- an owner's realm from a short author or from an unrelated relay sender.
    return false
end

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
    local counters = Nexus and Nexus.MainInternals
        and Nexus.MainInternals.CatalogAuthorityCounters
    if not (counters and type(counters.Advance) == "function") then
        return nil, "GENERATION_EXHAUSTED"
    end
    local sequence, why = counters.Advance(Operation, "sequence", 1)
    if not sequence then return nil, why end
    local attempt = previous and tostring(previous.id) == tostring(id)
        and (tonumber(previous.attempt) or 0) + 1 or 1
    local status = {
        kind=tostring(kind),id=tostring(id),version=tostring(version or "0"),
        operationKey=Operation.Key(kind, id, version),
        generation=sequence,attempt=attempt,
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
            if Operation.housekeeping then
                Operation.housekeepingRefreshPending = true
            else
                pcall(Sync.RequestDataViewRefresh)
            end
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

function Operation.ShareScopeCurrent(status)
    local scope = status and status.preparedScope
    if not scope then return true end
    local catalog = Catalog()
    if scope.database ~= NexusDB or scope.catalog ~= catalog
        or scope.owner ~= CurrentOwnerKey() then return false end
    local current = catalog and type(catalog.ManualPreparationStatus) == "function"
        and catalog.ManualPreparationStatus() or nil
    return scope.binding == nil or current and current.binding == scope.binding or false
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
-- Only a current-session tombstone published by this client's own
-- transaction carries local delete authority; persisted fields never do.
local function LocalOwnsVerifiedTomb(tomb)
    return type(tomb) == "table" and tomb.localOwned == true
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
    getTombstones=TombstoneMap,
    localOwnsTomb=LocalOwnsVerifiedTomb,
    -- REMOTE_TOMBSTONE_ORDER_UNPROVEN applies to every outbound path, not only
    -- the originating Stop Sharing. Protocol 7 carries no target revision or
    -- comparable operation order, so answering a reconciliation request must
    -- not emit the withdrawal the originating operation refused to send.
    tombstoneWireAllowed=function() return false end,
    relayEligible=function(build) return RelayEligible(build) end,
    myName=MyName,
    currentOwnerKey=CurrentOwnerKey,
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
local function TombOwnerKey(value)
    return Identity.VerifiedOwnerKey(value)
end
local function LocalOwnsTomb(value)
    return LocalOwnsVerifiedTomb(value)
end
local HashText = Compatibility.HashText
local BuildFingerprint = Compatibility.BuildFingerprint
local CatalogToken = Compatibility.CatalogToken
local DeltaBuildHash = Compatibility.DeltaBuildHash
local LegacyBuildHash = Compatibility.LegacyBuildHash
local CurrentBuildHash = Compatibility.CurrentBuildHash
local CurrentDpsHash = Compatibility.CurrentDpsHash

local function BucketContainsTombstone(bucket)
    local cache = Nexus and Nexus.BuildHashCache
    if cache and type(cache.BucketHasTombstone) == "function" then
        local present = cache.BucketHasTombstone(bucket)
        if present ~= nil then return present == true end
    end
    -- An unavailable complete view cannot prove that a bucket is claim-safe.
    return true
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
function Sync.Stats()
    -- The diagnostic queue enum describes transport, not hash preparation.
    -- Expose the current session's separate readiness state without inventing
    -- a queued request or expanding that transport enum.
    stats.preparingRequest = Session.StatusSnapshot().queueOutcome == "preparing"
    return stats
end

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
    operationCurrent=Operation.ShareScopeCurrent,
    resolveChannel=ResolveSendChannel,
    channelLabel=function() return channelIndex end,
    sendChat=function(...) return SendChatMessage(...) end,
    canDispatch=function(payload,metadata)
        local wire=Nexus.SyncWire
        if not wire or wire.suspended then return false end
        return wire.CanDispatch(payload,metadata)
    end,
    sendPacket=function(payload,metadata,channel)
        return Nexus.SyncWire.SendPacket(payload,metadata,channel)
    end,
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
    isLocalPeer=IsLocalTransportSender,
    isSelfRequest=function(sender)
        return IsLocalTransportSender(sender)
            or (Identity.CanonicalOwnerFromTransport(sender) == nil
                and SamePeer(sender, MyName()))
    end,
    transportOwnsOwner=function(ownerKey, sender)
        return Identity.TransportOwns(ownerKey, sender)
    end,
    catalogGet=CatalogGet,
    prepareBuild=function(build, responseMode, responseContext, source)
        return Responder.PrepareBuild(build, responseMode, responseContext,
            source)
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
    local firstMeasurement = type(prepared.wireCost) ~= "table"
    -- The cache object is caller-visible when admission is deferred. Always
    -- derive budget accounting from the integrity-bound messages rather than
    -- trusting a retained or caller-modified scalar summary.
    prepared.wireCost = WireCost(prepared.messages)
    if firstMeasurement then
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


local function RelayOwnerKey(build, source)
    if type(build) ~= "table" then return nil end
    local ownerKey = Identity.VerifiedOwnerKey(build)
    if not ownerKey and source == "bundled" then
        ownerKey = Identity.CoherentRecordOwnerKey(build)
    end
    return ownerKey
end

RelayEligible = function(build, source)
    if type(build) ~= "table" then return false end
    local kind = Identity.SavedMirrorKind(build)
    if kind == "invalid" then return false end
    if kind == "saved" then return false end
    local ownerKey = RelayOwnerKey(build, source)
    return ownerKey ~= nil
        and not (build.legacyRecovered == true
            and build.ownerVerified ~= true)
end

function Responder.PrepareSummary(build, responseContext)
    local wireId, wireWhy = WireBuildId(build and build.id)
    if not wireId then return nil, wireWhy end
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
    local status, why = Operation.New("share", id, version, Operation.shareById[id])
    if status then
        local catalog = Catalog()
        local preparation = catalog and type(catalog.ManualPreparationStatus) == "function"
            and catalog.ManualPreparationStatus() or nil
        status.preparedScope = {database=NexusDB,catalog=catalog,owner=CurrentOwnerKey(),
            binding=preparation and preparation.binding}
    end
    return status, why
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
    local retryBuild = pending.catalogBound
        and CatalogGet(pending.status.id) or pending.build
    local retryOwner = Identity.VerifiedOwnerKey(retryBuild)
    if not retryBuild or Operation.ShareVersion(retryBuild)
            ~= pending.status.version
        or retryOwner ~= pending.ownerKey
        or BuildFingerprint(retryBuild) ~= pending.fingerprint then
        FinishPendingShare("share source changed", false, true)
        return
    end
    local retryPrepared, prepareWhy = Responder.PrepareSummary(retryBuild)
    if not retryPrepared or type(retryPrepared.messages) ~= "table"
        or type(retryPrepared.messages[1]) ~= "string" then
        FinishPendingShare(prepareWhy or "share source unauthorized", false, true)
        return
    end
    pending.message = retryPrepared.messages[1]
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
    local explicit = retryOnFull or type(options) == "table" and options.explicit == true
    local status
    local prepared, why = Responder.PrepareSummary(build)
    if not prepared then
        if explicit then
            local id = tostring(build and build.id or ""):sub(1,
                MAX_BUILD_ID_BYTES)
            local previous = Operation.shareById[id]
            local statusWhy
            status, statusWhy = Operation.New("share", id,
                Operation.ShareVersion(build), previous, false)
            if not status then return false, statusWhy end
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
    if explicit then
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
        if retryOnFull then
            FinishPendingShare("superseded by newer Share Build", false, true)
        end
        local statusWhy
        status, statusWhy = Operation.NewShare(build)
        if not status then return false, statusWhy end
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
            if queueWhy == "sync queue full" and retryOnFull then
                status.retryOutcome = "pending"
                status.expiresAt = Now() + SHARE_RETRY_MAX_AGE
                status.retryAttempts = 0
                Operation.Transition(status, "retry-pending", queueWhy)
                local pendingCatalogBuild = CatalogGet(status.id)
                pendingShare = {
                    message=msg,metadata=metadata,status=status,
                    build=pendingCatalogBuild and nil or build,
                    catalogBound=pendingCatalogBuild ~= nil,
                    ownerKey=Identity.VerifiedOwnerKey(build),
                    fingerprint=BuildFingerprint(build),
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

-- DeleteWireMessage, the WLRD encoder, was removed with its last caller. The
-- responder was the only remaining sender, and it now refuses a tombstone
-- candidate as REMOTE_TOMBSTONE_ORDER_UNPROVEN exactly as the originating
-- delete does. The inbound WLRD decoder is unchanged for older peers; its
-- fields are code, sender, ID, tombstone stamp, author and optional context.

function Operation.NewDelete(id, tomb, registerActive)
    local version = tostring(TombStamp(tomb)) .. ":" .. TombAuthor(tomb)
    local status, why = Operation.New("delete", id, version,
        Operation.deleteById[tostring(id)], registerActive)
    if not status then return nil, why end
    status.owner = TombAuthor(tomb)
    return status
end

-- MASTER-RC-019: Operation.DeleteMetadata described the outbound queue
-- envelope for a delete packet. With the originating send refused zero-wire
-- and the retry pump removed, nothing enqueues a delete, so the envelope had
-- no remaining caller.

-- Pending deletes are a session-only fixed-shape map. A durable `pending`
-- field on a tombstone is opaque evidence and grants no retry authority.
--
-- MASTER-RC-019. `MarkDeletePending` was removed with the retry pump below:
-- architecture line 4856 makes the originating local delete an unconditional
-- zero-wire refusal, so nothing populates this map any more and
-- `PendingDeleteCount()` honestly reports zero. The map, its clear entry and
-- its count are kept because `Sync.WorkState()` is a public surface that must
-- keep reporting them.
local function ClearPendingDelete(id)
    pendingDeletes[id] = nil
end

PendingDeleteCount = function()
    local count = 0
    for id in pairs(pendingDeletes) do
        if LocalOwnsTomb(CatalogTombstoneView(id)) then
            count = count + 1
        end
    end
    return count
end

function Operation.DiscoverPendingDeletes()
    -- Persisted pending markers never restore session delete work.
    Operation.deleteDiscoveryComplete = true
    return 0
end

local function PumpPendingDeletes(elapsed)
    pendingDeleteTicker = pendingDeleteTicker + (tonumber(elapsed) or 0)
    if pendingDeleteTicker < 1 then return end
    pendingDeleteTicker = 0
    -- MASTER-RC-019. The retry-pump CONSUMER that used to live here -- expiry
    -- and drop transitions, owner selection, and the retry
    -- Transport.Enqueue(DeleteWireMessage(...)) -- was unreachable once the
    -- originating local delete became an unconditional zero-wire refusal
    -- (architecture line 4856): `MarkDeletePending` had exactly one caller, in
    -- the enqueue tail that refusal replaced, so `pendingDeletes` can never be
    -- non-empty and every branch past this point was dead.
    --
    -- Discovery is kept: it is reachable, it publishes
    -- `Operation.deleteDiscoveryComplete`, and it honestly returns zero.
    -- The RESPONDER path no longer encodes a withdrawal either: answering a
    -- peer's reconciliation request emitted the WLRD that the originating
    -- operation had refused as REMOTE_TOMBSTONE_ORDER_UNPROVEN. Both paths are
    -- now zero-wire. Remote withdrawal stays unsupported until the protocol
    -- carries a comparable edit/delete order.
    Operation.DiscoverPendingDeletes(32)
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

------------------------------------------------------------------------
-- Deferred inbound admission
------------------------------------------------------------------------

-- Catalog.Put answers `false` plus a root-pending reason, and no ticket, when
-- another transaction owns admission. Nothing was accepted, so that is not a
-- pending operation. It is also not a verdict on the item. The validated item
-- is retained here, bounded and session-only, and is submitted once when
-- ordinary admission is available again. The complete inbound handler runs
-- again at that point, so owner, revision, pending-replacement and tombstone
-- state are rechecked against the then-current catalog. Only the ticket that
-- submission returns may report success; expiry, overflow, reset and a
-- changed catalog scope settle as the same storage refusal the item would
-- have received before.
--
-- Each item has one fixed deadline, PENDING_MAX_AGE from its own arrival.
-- Other catalog work never extends it. An item whose turn does not come in
-- that time fails as a storage refusal, even while the catalog keeps working.
function Responder.Admission.Busy(stored, why)
    return stored == false and (why == "ROOT_MUTATION_PENDING"
        or why == "ROOT_ADMISSION_PENDING")
end

function Responder.Admission.Remove(entry)
    if Responder.Admission.byKey[entry.key] ~= entry then return false end
    Responder.Admission.byKey[entry.key] = nil
    for index, candidate in ipairs(Responder.Admission.order) do
        if candidate == entry then
            table.remove(Responder.Admission.order, index)
            break
        end
    end
    Responder.Admission.count = #Responder.Admission.order
    return true
end

function Responder.Admission.Fail(entry, counter, detail)
    if not Responder.Admission.Remove(entry) then return false end
    if counter then
        stats.storageRejected = (stats.storageRejected or 0) + 1
        stats[counter] = (stats[counter] or 0) + 1
    end
    Responder.NoteContextOutcome(entry.context, "rejected", "storage")
    PeerObserve("receiver_commit", {id=entry.id,peer=entry.sender,
        outcome="store_failed",reason=detail})
    LogEvent("RX", "REJECT deferred %s '%s': %s", tostring(entry.kind),
        tostring(entry.id), tostring(detail))
    entry.settle(false, false, "storage")
    return true
end

-- The scope an item was validated in: this Sync session, this catalog owner,
-- its bound database and binding generation, and the local player. An item is
-- never submitted into any other scope.
function Responder.Admission.Scope()
    local catalog = Catalog()
    local preparation = catalog
        and type(catalog.ManualPreparationStatus) == "function"
        and catalog.ManualPreparationStatus() or nil
    return {
        identity=catalogMutationIdentity,catalog=catalog,
        database=catalog and type(catalog.BoundDatabase) == "function"
            and catalog.BoundDatabase() or nil,
        savedVariables=NexusDB,
        binding=preparation and preparation.binding or nil,
        owner=CurrentOwnerKey(),
    }
end

function Responder.Admission.SameScope(entry)
    local scope, current = entry.scope, Responder.Admission.Scope()
    for _, key in ipairs({"identity", "catalog", "database", "savedVariables",
        "binding", "owner"}) do
        if scope[key] ~= current[key] then return false end
    end
    return current.catalog ~= nil and current.database ~= nil
end

-- Returns "deferred", "duplicate", "rejected" or "overflow". One entry per
-- kind and ID: an older or equal revision never displaces the retained one,
-- and a different owner claim cannot take over its place in the queue.
function Responder.Admission.Defer(fields)
    local key = tostring(fields.kind) .. ":" .. type(fields.id) .. ":"
        .. tostring(fields.id)
    -- Settle cancelled and expired items first. An item retained in an earlier
    -- scope is not a prior claim in this one: it must not make a fresh valid
    -- receipt a duplicate, refuse its owner, or count against the bounds.
    Responder.Admission.Expire()
    local prior = Responder.Admission.byKey[key]
    if prior then
        if prior.owner ~= fields.owner then
            Responder.NoteContextOutcome(fields.context, "rejected", "ownership")
            return "rejected"
        end
        local promotes = fields.stamp == prior.stamp
            and fields.direct == true and prior.direct ~= true
            and fields.digest == prior.digest
        if fields.stamp < prior.stamp then
            Responder.NoteContextOutcome(fields.context, "duplicate", "stale")
            return "duplicate"
        end
        if fields.stamp == prior.stamp and not promotes then
            local same = fields.digest == prior.digest
            Responder.NoteContextOutcome(fields.context,
                same and "duplicate" or "rejected",
                same and "duplicate" or "integrity")
            return same and "duplicate" or "rejected"
        end
        Responder.Admission.Remove(prior)
        stats.admissionSuperseded = (stats.admissionSuperseded or 0) + 1
        Responder.NoteContextOutcome(prior.context, "duplicate", "stale")
        prior.settle(true, false)
    end
    local fromSender = 0
    for _, candidate in ipairs(Responder.Admission.order) do
        if candidate.sender == fields.sender then fromSender = fromSender + 1 end
    end
    if Responder.Admission.count >= Responder.Admission.maxTotal
        or fromSender >= Responder.Admission.maxPerSender then
        stats.admissionOverflow = (stats.admissionOverflow or 0) + 1
        return "overflow"
    end
    local current = Now()
    local entry = {
        key=key,kind=fields.kind,id=fields.id,stamp=fields.stamp,
        owner=fields.owner,direct=fields.direct == true,digest=fields.digest,
        sender=fields.sender,context=fields.context,run=fields.run,
        settle=fields.settle,enqueuedAt=current,
        expiresAt=current + PENDING_MAX_AGE,
        scope=Responder.Admission.Scope(),
    }
    Responder.Admission.byKey[key] = entry
    Responder.Admission.order[#Responder.Admission.order + 1] = entry
    Responder.Admission.count = #Responder.Admission.order
    stats.admissionDeferred = (stats.admissionDeferred or 0) + 1
    PeerObserve("receiver_commit", {id=fields.id,peer=fields.sender,
        outcome="deferred",reason="catalog admission pending"})
    LogEvent("RX", "DEFER %s '%s': catalog admission pending",
        tostring(fields.kind), tostring(fields.id))
    return "deferred"
end

function Responder.Admission.Expire()
    if Responder.Admission.count == 0 then return end
    local current, index = Now(), 1
    while Responder.Admission.order[index] do
        local entry = Responder.Admission.order[index]
        if not Responder.Admission.SameScope(entry) then
            -- A changed player, database or binding cancels the item. It is
            -- never carried into the new scope.
            Responder.Admission.Fail(entry, "admissionCancelled",
                "catalog scope changed")
        elseif current >= entry.expiresAt then
            Responder.Admission.Fail(entry, "admissionExpired",
                "catalog admission wait expired")
        else
            index = index + 1
        end
    end
end

-- A submission makes the catalog busy, and the lifecycle then withholds every
-- full Sync turn until that transaction ends. Transport only sends in a full
-- turn, so a queue that submits in every ready turn leaves outbound traffic,
-- including the user's explicit Sync Now request, with no turn at all.
-- Outbound and deferred inbound work therefore alternate, and the outbound
-- unit is a whole transfer, never a single chunk: a catalog transaction
-- between two chunks outlasts the chunks' own deadline.
--  * Sync's paced owners (response election, recovery, send pacing) only
--    accumulate time in full turns. After the catalog becomes ready they get
--    one continuous RESPONSE_ELECTION_DELAY window before any submission, or
--    they would never produce the outbound work that is then owed.
--  * A started multi-chunk transfer is never interrupted.
--  * While response work is pending or valid outbound traffic waits, one
--    whole unit must be transmitted between two submissions. Outbound goes
--    first.
--  * Apart from a started transfer, admission never yields for more than
--    PENDING_TTL of continuous ready time, so sustained outbound work cannot
--    hold deferred inbound work until its deadline.
-- The catalog stays ready in the meantime, so ordinary send pacing decides
-- when a transmission happens. Admission yields only to a transmission
-- that can actually happen: when the channel is absent, a throttle pause is
-- active, or the wire itself reports a persistent blocker (suspended, combat,
-- no throttle library), no send is possible and the catalog is not left
-- idle. Nothing is dropped, reordered or extended: each item keeps its fixed
-- deadline.
function Responder.Admission.OutboundOwed()
    if not Sync.IsConnected() or Transport.ThrottleRemaining() > 0 then
        return false
    end
    -- The same owner Transport asks before every dispatch.
    local wire = Nexus.SyncWire
    if not wire or type(wire.Blocked) ~= "function" or wire.Blocked() then
        return false
    end
    local progress = Transport.OutboundProgress()
    if progress.midTransfer then return true end
    local readyFor = Now() - (Responder.Admission.readySince or Now())
    if readyFor >= PENDING_TTL then return false end
    if readyFor < RESPONSE_ELECTION_DELAY then return true end
    local pending = Reconciler.Counts()
    if progress.waiting <= 0 and (tonumber(pending.total) or 0) <= 0 then
        return false
    end
    return progress.unitsSent == (Responder.Admission.unitsAtSubmission or -1)
        or Responder.Admission.unitsAtSubmission == nil
end

-- A validated inbound item that finds the catalog ready normally takes it at
-- once. While the user's explicit manual request is still unsent, that write
-- costs the request its turn: every commit invalidates the hash walk the
-- request waits for, the lifecycle withholds every full Sync turn until the
-- catalog and the hash are both ready, and at a large catalog the request
-- expires unsent behind a chain of direct writes. The lifecycle already gives
-- a pending Share the next admission turn; this gives the same to a manual
-- request. The item is not refused, dropped or delayed beyond its own
-- deadline: it enters this same bounded, scoped owner, keeps its validation,
-- fixed deadline, scope capture and FIFO place, and is submitted by the pump
-- after the request's transmission. The hold is bounded by the request's own
-- fixed lifetime, and it never waits for a transmission the wire cannot make.
-- A full owner refuses a held item exactly as it refuses one that found the
-- catalog busy: a counted storage refusal, never a silent drop.
function Responder.Admission.RequestHold()
    if not (Session and type(Session.ManualRequestUnsent) == "function"
        and Session.ManualRequestUnsent()) then return false end
    if not Sync.IsConnected() or Transport.ThrottleRemaining() > 0 then
        return false
    end
    local wire = Nexus.SyncWire
    if not wire or type(wire.Blocked) ~= "function" or wire.Blocked() then
        return false
    end
    return true
end

-- Full Sync turns are continuous while the catalog is ready. A gap means the
-- lifecycle withheld them, so the continuous ready window starts again.
function Responder.Admission.NoteTurn()
    local current = Now()
    if not Responder.Admission.turnAt or current - Responder.Admission.turnAt > 1 then
        Responder.Admission.readySince = current
    end
    Responder.Admission.turnAt = current
end

-- Runs only behind the lifecycle's full catalog readiness gate, after the
-- transport turn. The passive status read means a still-busy catalog receives
-- no further Put call.
function Responder.Admission.Pump()
    if Responder.Admission.count == 0 then return end
    Responder.Admission.Expire()
    if Responder.Admission.OutboundOwed() then
        stats.admissionYielded = (stats.admissionYielded or 0) + 1
        return
    end
    local catalog = Catalog()
    while Responder.Admission.order[1] do
        local preparation = catalog
            and type(catalog.ManualPreparationStatus) == "function"
            and catalog.ManualPreparationStatus() or nil
        if preparation and preparation.ready ~= true then return end
        local entry = Responder.Admission.order[1]
        -- Rechecked at the point of submission, after Expire above, because
        -- an earlier entry in this same turn can change nothing about scope
        -- but a rebind can complete between turns.
        if not Responder.Admission.SameScope(entry) then
            Responder.Admission.Fail(entry, "admissionCancelled",
                "catalog scope changed")
        else
            local outcome = entry.run(entry)
            if outcome == "busy" then return end
            if outcome == "ticket" then
                -- One accepted submission per turn; the next one waits for a
                -- whole transmitted unit while outbound work is owed.
                Responder.Admission.unitsAtSubmission =
                    Transport.OutboundProgress().unitsSent
            end
        end
        Responder.Admission.Remove(entry)
    end
end

function Responder.Admission.Reset()
    while Responder.Admission.order[1] do
        Responder.Admission.Fail(Responder.Admission.order[1], nil, "explicit reset")
    end
    Responder.Admission.order, Responder.Admission.byKey, Responder.Admission.count = {}, {}, 0
    Responder.Admission.unitsAtSubmission = nil
    Responder.Admission.readySince, Responder.Admission.turnAt = nil, nil
end

local function StoreSummary(data, transportSender, context, onComplete,
        deferredEntry)
    local received = data
    local validated, validationReason = Protocol.ValidateNetworkSummary(data)
    if not validated then
        Responder.NoteContextOutcome(context, "rejected",
            validationReason == "ownership" and "ownership" or "schema")
        return false, false
    end
    data = validated
    if not Identity.TransportOwns(data.o, transportSender) then
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        return false, false
    end
    local id = tostring(data.id)
    local recoveryRequestId = type(context) == "table"
        and IsLocalTransportSender(context.requester)
        and context.requestId or nil
    local old, oldSource = CatalogGet(id)
    if old and Identity.SavedMirrorKind(old) ~= "ordinary" then
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        return false, false
    end
    if old and LocalOwnsStoredBuild(old) then
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        return false, false
    end
    if old then
        local oldOwner = TrustedStoredOwnerKey(old, oldSource)
        if not CanPromoteStoredOwner(old, data.o) and (not oldOwner
            or oldOwner ~= Identity.CanonicalOwnerKey(data.o)) then
            Responder.NoteContextOutcome(context, "rejected", "ownership")
            return false, false
        end
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
    local summaryReservation = CatalogTombstoneView(id)
    if summaryReservation then
        -- Every tombstone reservation denies inbound summaries for its exact
        -- typed ID; a newer stamp or a matching owner never resurrects it. A
        -- foreign owner claim is reported as a refusal, not a benign skip.
        local reserved = Identity.CanonicalOwnerKey(summaryReservation.ownerKey)
        local incoming = Identity.CanonicalOwnerKey(data.o or data.ownerKey)
        if reserved and (incoming ~= reserved
            or not Identity.TransportOwns(reserved, transportSender)) then
            LogEvent("RX", "REJECT summary resurrection of '%s': tombstone belongs to %s",
                tostring(id), tostring(TombAuthor(summaryReservation)))
            Responder.NoteContextOutcome(context, "rejected", "ownership")
            return false, false
        end
        LogEvent("RX","skip summary '%s': tombstoned", tostring(data.t))
        Responder.NoteContextOutcome(context, "rejected", "tombstone")
        return true, false
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
        lastModified=stamp, postedAt=old and old.postedAt or stamp,
        -- Transport ownership verifies the remote record; it does not prove
        -- this client created the local source row.
        isMine=false,
        autoDps=data.x==1, fingerprint=keepEchoes and old.fingerprint or nil,
        fingerprintHash=newHash, echoCount=tonumber(data.n) or 0,
        echoes=keepEchoes, loadoutAvailable=type(keepEchoes)=="table" and #keepEchoes>0,
        linkHash=newLinkHash, needsFullBuild=linkChanged or nil,
        ownerVerified=true,
    }
    local function Complete(stored, storedAs)
        if not stored then
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
    local function Submit()
        local stored, storedAs, ticket = CatalogPut(record, {source="remote",
            sender=transportSender})
        if stored == nil and storedAs == "ROOT_MUTATION_PENDING" then
            if not BindCatalogCompletion(ticket, function(ok, why)
                if type(onComplete) == "function" then
                    onComplete(Complete(ok, why))
                else
                    Complete(ok, why)
                end
            end) then
                return false, "INVALID_MUTATION_TICKET"
            end
            return nil, storedAs
        end
        return stored, storedAs
    end
    local held = not deferredEntry and Responder.Admission.RequestHold()
    local stored, storedAs
    if not held then
        stored, storedAs = Submit()
        if stored == nil and storedAs == "ROOT_MUTATION_PENDING" then
            return nil, false, storedAs
        end
    end
    if held or Responder.Admission.Busy(stored, storedAs) then
        if deferredEntry then return nil, false, "ADMISSION_BUSY" end
        if held then stats.admissionHeld = (stats.admissionHeld or 0) + 1 end
        local disposition = Responder.Admission.Defer({
            kind="summary",id=id,stamp=stamp,owner=record.ownerKey or "",
            direct=true,digest=newHash .. "|" .. tostring(newLinkHash or ""),
            sender=transportSender,context=context,
            settle=function(...)
                if type(onComplete) == "function" then onComplete(...) end
            end,
            run=function(entry)
                local accepted, changed, rejection = StoreSummary(received,
                    transportSender, context, onComplete, entry)
                if accepted == nil and rejection == "ADMISSION_BUSY" then
                    return "busy"
                end
                Responder.Admission.Remove(entry)
                stats.admissionResolved = (stats.admissionResolved or 0) + 1
                if accepted == nil and rejection == "ROOT_MUTATION_PENDING" then
                    return "ticket"
                end
                entry.settle(accepted, changed, rejection)
                return "terminal"
            end,
        })
        if disposition == "deferred" then return nil, false, "ROOT_MUTATION_PENDING" end
        if disposition == "duplicate" then return true, false end
        if disposition == "rejected" then return false, false end
        -- "overflow": the bounded owner is full. Held or busy, the item gets
        -- the same counted storage refusal; a held item never takes the
        -- catalog the request is waiting for.
        stored, storedAs = false, "ROOT_MUTATION_PENDING"
    end
    return Complete(stored, storedAs)
end

function Sync.RequestLoadout(buildId)
    -- Menu clicks never transmit directly. If this is a summary inherited from
    -- an older Nexus peer, queue one slow background recovery request instead.
    -- Current peers send complete builds during normal reconciliation.
    local wireId, why = WireBuildId(buildId)
    if not wireId then return false, why end
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
    local wireId, wireWhy = WireBuildId(buildId)
    if not wireId then return nil, wireWhy end
    if not ValidIdentifier(buildId, MAX_BUILD_ID_BYTES)
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

function Responder.PrepareBuild(build, responseMode, responseContext, source)
    build = Responder.ResolveBuild(build)
    if not RelayEligible(build, source) then return nil, "relay unauthorized" end
    if not build or type(build.echoes) ~= "table" or #build.echoes == 0 then
        return nil, "no echoes"
    end
    local wireId, wireWhy = WireBuildId(build.id)
    if not wireId then return nil, wireWhy end
    if not ValidIdentifier(build.id, MAX_BUILD_ID_BYTES) then
        return nil, "PROTOCOL7_ID_UNREPRESENTABLE"
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
    local catalogBuild, catalogSource = CatalogGet(build.id)
    local catalogBound = type(catalogBuild) == "table"
    local recordEpoch, recordRevision
    if catalogBound then
        recordEpoch, recordRevision = CatalogRecordRevision(build.id)
    end
    local authoritySource = catalogBound and catalogSource or source
    local prepared = {
        messages=messages, build=build,
        buildKey=tostring(build.id or build.fingerprintHash
            or build.fingerprint or ""),
        title=build.title, id=build.id,
        echoCount=#build.echoes, b64Bytes=#b64,
        catalogBound=catalogBound,catalogSource=authoritySource,
        recordEpoch=recordEpoch,recordRevision=recordRevision,
        ownerKey=RelayOwnerKey(build, source),
        fingerprint=BuildFingerprint(build),
        version=Operation.ShareVersion(build),
    }
    PreparedWireCost(prepared, responseMode, false)
    return prepared
end

function Responder.AdmitBuild(prepared, responseMode, responseContext)
    if type(prepared) ~= "table" or type(prepared.messages) ~= "table" then
        return false, "invalid prepared build"
    end
    local current, currentSource = CatalogGet(prepared.id)
    if prepared.catalogBound then
        local currentEpoch, currentRevision = CatalogRecordRevision(prepared.id)
        if type(current) ~= "table"
            or currentSource ~= prepared.catalogSource
            or (prepared.recordEpoch ~= nil
                and (currentEpoch ~= prepared.recordEpoch
                    or currentRevision ~= prepared.recordRevision))
            or not RelayEligible(current, currentSource)
            or RelayOwnerKey(current, currentSource) ~= prepared.ownerKey
            or BuildFingerprint(current) ~= prepared.fingerprint
            or Operation.ShareVersion(current) ~= prepared.version then
            return false, "stale prepared build"
        end
    elseif current ~= nil or not RelayEligible(
            prepared.build, prepared.catalogSource) then
        return false, "stale prepared build"
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
        Responder.Work.RememberHotBuild(
            prepared.id, { build=prepared.build, t=Now() })
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
    local wireId, wireWhy = WireBuildId(build.id)
    if not wireId then return false, wireWhy end
    if not ValidIdentifier(build.id, MAX_BUILD_ID_BYTES) then
        return false, "PROTOCOL7_ID_UNREPRESENTABLE"
    end
    if not RelayEligible(build) then return false, "relay unauthorized" end
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

function Responder.Work.BroadcastCatalogRecord(build, sent)
    if type(build) ~= "table" then return 0 end
    sent[build.id] = true
    if build.legacyRecovered == true and build.ownerVerified ~= true then
        return 0
    end
    return BroadcastSummary(build) and 1 or 0
end

function Responder.Work.HotBuildCountWithin(limit)
    local count = 0
    for _ in pairs(hotBuilds) do
        count = count + 1
        if count > limit then return nil end
    end
    return count
end

function Responder.Work.BroadcastSmallRoot(records, now)
    local sent, expired, count = {}, {}, 0
    for _, build in pairs(records) do
        count = count + Responder.Work.BroadcastCatalogRecord(build, sent)
    end
    for id, hot in pairs(hotBuilds) do
        if now - hot.t > HOT_WINDOW then
            expired[#expired + 1] = id
        elseif not sent[id] then
            local current = CatalogGet(id)
            if current and RelayEligible(current) then
                if BroadcastSummary(current) then count = count + 1 end
            else
                expired[#expired + 1] = id
            end
        end
    end
    for _, id in ipairs(expired) do Responder.Work.ForgetHotBuild(id) end
    return count
end

function Responder.Work.PumpBroadcastMine()
    local job = Responder.state.broadcastMineJob
    if not job then return true end
    if job.phase == "records" then
        local page, err = job.catalog.RecordCursorNext(job.cursor)
        if err or type(page) ~= "table" then
            Responder.state.broadcastMineJob = nil
            return false, err or "catalog cursor unavailable"
        end
        if page.done then
            job.phase, job.hotCursor = "hot", nil
            job.hotGeneration = Responder.state.hotBuildGeneration or 0
            return false, "pending"
        end
        if type(page.record) == "table" then
            job.count = job.count
                + Responder.Work.BroadcastCatalogRecord(page.record, job.sent)
        end
        return false, "pending"
    end

    -- The traversal key remains present until the next key is obtained. Any
    -- external hot-set mutation changes the generation before `next` runs.
    if job.hotGeneration ~= (Responder.state.hotBuildGeneration or 0) then
        Responder.state.broadcastMineJob = nil
        return false, "hot build set changed"
    end
    local id, hot = next(hotBuilds, job.hotCursor)
    if job.removeHot then
        Responder.Work.ForgetHotBuild(job.removeHot)
        job.hotGeneration = Responder.state.hotBuildGeneration or 0
        job.removeHot = nil
    end
    if id == nil then
        local count = job.count
        Responder.state.broadcastMineJob = nil
        return true, count
    end
    job.hotCursor = id
    if job.now - hot.t > HOT_WINDOW then
        job.removeHot = id
    elseif not job.sent[id] then
        local current = CatalogGet(id)
        if current and RelayEligible(current) then
            if BroadcastSummary(current) then job.count = job.count + 1 end
        else
            job.removeHot = id
        end
    end
    return false, "pending"
end

function Sync.BroadcastMine()
    local now = Now()
    local catalog = Catalog()
    if not catalog then return 0 end
    if Responder.state.broadcastMineJob then return nil, "pending" end

    -- Preserve immediate behavior only when both collections fit the public
    -- one-call frontier. A sparse maximum root refuses before traversal.
    local records, why = type(catalog.All) == "function" and catalog.All()
    if type(records) == "table"
        and Responder.Work.HotBuildCountWithin(8) ~= nil then
        return Responder.Work.BroadcastSmallRoot(records, now)
    end
    if records == nil and why ~= "CURSOR_REQUIRED" then return 0, why end
    if type(catalog.BeginRecordCursor) ~= "function"
        or type(catalog.RecordCursorNext) ~= "function" then
        return 0, "catalog cursor unavailable"
    end
    local cursor, cursorWhy = catalog.BeginRecordCursor()
    if not cursor then return 0, cursorWhy or "catalog cursor unavailable" end
    Responder.state.broadcastMineJob = {catalog=catalog, cursor=cursor,
        sent={}, count=0,
        phase="records", now=now}
    return nil, "pending"
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
        -- Refuse before encoder invocation, as the originating delete does.
        -- Candidate selection already withholds these; this holds the same
        -- zero-wire result if a tombstone candidate is ever supplied.
        Reconciler.NoteStat("tombstoneWireRefused", 1)
        return nil, "REMOTE_TOMBSTONE_ORDER_UNPROVEN"
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
        if admitWhy == "stale prepared build" then
            bucketState.prepared[item.token] = nil
        end
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
    local canonicalOwner = D and type(D.HasCanonicalOwnerIdentity) == "function"
        and D.HasCanonicalOwnerIdentity(payload) == true
    local directOwner = originVerified == true
        and CurrentOwnerKey() ~= nil
        and Identity.CanonicalOwnerKey(payload.o) == CurrentOwnerKey()
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
        and canonicalOwner
        and computed and computed == payload.f
        and payload.h and (not computedHash or payload.h == computedHash)
end

local function VerifiedDpsBuildId(ownerKey, fingerprint, buildId)
    if type(buildId) ~= "string" or buildId == "" then return nil end
    local canonicalOwner = Identity.CanonicalOwnerKey(ownerKey)
    local relatedBuild = CatalogGet(buildId)
    if not canonicalOwner or type(relatedBuild) ~= "table"
        or Identity.SavedMirrorKind(relatedBuild) ~= "ordinary"
        or Identity.VerifiedOwnerKey(relatedBuild) ~= canonicalOwner
        or BuildFingerprint(relatedBuild) ~= fingerprint then
        return nil
    end
    return buildId
end

-- Prepared DPS payloads are private, in-memory serialization caches. Keep an
-- integrity proof outside the caller-visible table so a fabricated or mutated
-- cache can never supply authority or arbitrary wire bytes on a later retry.
local preparedDpsProofs = setmetatable({}, {__mode="k"})

local function PreparedDpsProof(prepared, responseMode)
    if type(prepared) ~= "table" or type(prepared.messages) ~= "table"
        or type(prepared.payload) ~= "table" then return nil end
    local messages = {}
    for index = 1, #prepared.messages do
        if type(prepared.messages[index]) ~= "string" then return nil end
        messages[index] = prepared.messages[index]
    end
    local okPayload, payload = pcall(Codec.JSONEncode, prepared.payload)
    local okContext, context = pcall(Codec.JSONEncode,
        prepared.context or false)
    if not okPayload or not okContext then return nil end
    return table.concat({
        responseMode and "1" or "0",
        prepared.originVerified == true and "1" or "0",
        payload, context, tostring(#messages), table.concat(messages, "\0"),
    }, "\1")
end

local function SamePreparedDpsContext(preparedContext, responseContext)
    local current = type(responseContext) == "table"
        and Responder.RequestContext(responseContext.requester,
            responseContext.requestId, responseContext.bucket) or nil
    if preparedContext == nil or current == nil then
        return preparedContext == nil and current == nil
    end
    return preparedContext.requester == current.requester
        and preparedContext.requestId == current.requestId
        and preparedContext.bucket == current.bucket
end

local function CurrentPreparedDpsAuthority(record, payload, responseMode,
        responseContext)
    local D = Nexus and Nexus.DpsCapture
    if type(record) ~= "table" or type(payload) ~= "table"
        or not (D and type(D.VerifiedOwnerKey) == "function"
            and type(D.GetCharacterBest) == "function"
            and type(D.GetEchoKey) == "function") then
        return false, "relay_authorization"
    end
    local verifiedOwner = D.VerifiedOwnerKey(record)
    if not verifiedOwner then return false, "relay_authorization" end
    local category = record.category
    if category ~= "dummy" and category ~= "lk" then
        return false, "stale prepared DPS"
    end
    local current = D.GetCharacterBest(
        category, record.player, verifiedOwner)
    if type(current) ~= "table"
        or D.VerifiedOwnerKey(current) ~= verifiedOwner then
        return false, "stale prepared DPS"
    end
    local fingerprint = D.GetEchoKey(current.echoes)
    local loadoutHash = current.loadoutHash
        or (type(D.GetEchoHash) == "function"
            and D.GetEchoHash(current.echoes) or nil)
    local currentBuildId = VerifiedDpsBuildId(
        verifiedOwner, fingerprint, current.buildId)
    local currentLocked = D.GetEchoKey(current.lockedEchoes) or "0"
    local payloadLocked = D.GetEchoKey(payload.lk) or "0"
    local currentOwner = CurrentOwnerKey()
    local directOwner = currentOwner ~= nil and verifiedOwner == currentOwner
    if not directOwner then
        if not responseMode or record._originVerified ~= true then
            return false, "relay_authorization"
        end
        local relay = {
            n=type(responseContext) == "table"
                and responseContext.requester or nil,
            i=type(responseContext) == "table"
                and responseContext.requestId or nil,
            b=type(responseContext) == "table"
                and responseContext.bucket or nil,
            c=category,
        }
        local wireRelay = payload.x
        if not ValidDpsRelayContext(relay, current.player) then
            return false, "outside_request"
        end
        if type(wireRelay) ~= "table" or wireRelay.n ~= relay.n
            or wireRelay.i ~= relay.i or tonumber(wireRelay.b) ~= relay.b then
            return false, "stale prepared DPS"
        end
    elseif payload.x ~= nil then
        return false, "stale prepared DPS"
    end
    if Identity.CanonicalOwnerKey(payload.o) ~= verifiedOwner
        or tostring(payload.f or "") ~= tostring(fingerprint or "")
        or tostring(payload.h or "") ~= tostring(loadoutHash or "")
        or payload.b ~= currentBuildId
        or payloadLocked ~= currentLocked
        or payload.c ~= category
        or tostring(payload.p or "") ~= tostring(current.player or "")
        or tonumber(payload.d) ~= math.floor(tonumber(current.dps) or -1)
        or tonumber(payload.u) ~= tonumber(current.duration)
        or tonumber(payload.t) ~= tonumber(current.ts)
        or tonumber(payload.l) ~= tonumber(current.level)
        or tostring(payload.k or ""):upper()
            ~= tostring(current.class or ""):upper()
        or tostring(payload.r or ""):lower()
            ~= tostring(current.realm or ""):lower() then
        return false, "stale prepared DPS"
    end
    return true
end

function Sync.BroadcastDpsRecord(record, prepared, responseMode,
        responseContext, responseBudget)
    if type(prepared) ~= "table" then prepared = nil end
    if responseMode and Responder.Backpressured() then
        return false, "sync queue full", prepared
    end
    local D = Nexus and Nexus.DpsCapture
    if type(record) == "table" and D
        and type(D.MaterializeRecord) == "function" then
        local ok, resolved = pcall(D.MaterializeRecord, record)
        if ok and type(resolved) == "table" then record = resolved end
    end
    if prepared ~= nil then
        local expectedProof = preparedDpsProofs[prepared]
        if expectedProof == nil
            or PreparedDpsProof(prepared, responseMode) ~= expectedProof
            or not SamePreparedDpsContext(prepared.context,
                responseContext) then
            return false, "relay_authorization"
        end
    end
    if prepared ~= nil and type(prepared.payload) == "table"
        and prepared.payload.b ~= nil
        and not VerifiedDpsBuildId(prepared.payload.o,
            prepared.payload.f, prepared.payload.b) then
        -- Never fall through and rebuild from the caller-held record: the
        -- durable row or its owner authority may have changed while this cache
        -- waited. A later candidate scan can serialize current evidence anew.
        return false, "stale prepared DPS"
    end
    if prepared ~= nil then
        if type(prepared) ~= "table" or type(prepared.messages) ~= "table"
            or type(prepared.payload) ~= "table"
            or #prepared.messages < 1
            or not Responder.ValidatePreparedDps(prepared.payload,
                prepared.originVerified) then
            return false, "schema"
        end
        local authorityOk, authorityWhy = CurrentPreparedDpsAuthority(
            record, prepared.payload, responseMode, responseContext)
        if not authorityOk then return false, authorityWhy end
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
        preparedDpsProofs[prepared] = nil
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
    if not (D and type(D.HasCanonicalOwnerIdentity) == "function"
            and D.HasCanonicalOwnerIdentity(record) == true) then
        return false, "owner_sender"
    end
    if record.claimedOwnerKey ~= nil or record.relaySender ~= nil then
        return false, "owner_sender"
    end
    local computed = D and D.GetEchoKey and D.GetEchoKey(record.echoes) or nil
    local verifiedOwner = type(D.VerifiedOwnerKey) == "function"
        and D.VerifiedOwnerKey(record) or nil
    local directOwner = CurrentOwnerKey() ~= nil
        and verifiedOwner == CurrentOwnerKey()
    local relayContext
    if not directOwner then
        if not responseMode then return false, "owner_sender" end
        -- `_originVerified` records how verified evidence reached this client;
        -- it is never owner authority by itself. The durable row must still
        -- carry one coherent explicit verified owner verdict.
        if verifiedOwner == nil or record._originVerified ~= true then
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
    local relatedBuildId = VerifiedDpsBuildId(
        verifiedOwner, record.fingerprint, record.buildId)
    local payload = {
        v = tonumber(record.protocolVersion) or 5,
        h = loadoutHash,
        f = record.fingerprint,
        e = record.echoes,
        c = record.category, d = math.floor(dps),
        u = duration, t = stamp,
        p = player, l = level,
        k = record.class, o = record.ownerKey, r = record.realm,
        b = relatedBuildId,
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
        originVerified=directOwner
            or (verifiedOwner ~= nil and record._originVerified == true)}
    preparedDpsProofs[prepared] = PreparedDpsProof(prepared, responseMode)
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
    preparedDpsProofs[prepared] = nil
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

function Sync.BroadcastDelete(build, onLocalComplete)
    if not build then return false end
    local id, wireWhy = WireBuildId(build.id)
    if not id then return false, wireWhy end
    if not ValidIdentifier(id, MAX_BUILD_ID_BYTES) then
        return false, "PROTOCOL7_ID_UNREPRESENTABLE"
    end
    local author = tostring(build.author or MyName())
    local localOwner = CurrentOwnerKey()
    if Identity.SavedMirrorKind(build) ~= "ordinary"
        or not localOwner
        or not Identity.LocalOwnsRecord(build, localOwner) then
        return false
    end
    local existing = CatalogTombstoneView(id)
    local existingVersion = existing and (tostring(TombStamp(existing))
        .. ":" .. TombAuthor(existing)) or ""
    local existingKey = existing and Operation.Key("delete", id,
        existingVersion) or nil
    local active = existingKey and Operation.activeDeletes[existingKey] or nil
    if active and active.terminal ~= true
        and existing and LocalOwnsTomb(existing) then
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
        and LocalOwnsTomb(existing)
        and tostring(previous.version) == existingVersion and existing or {
            stamp=tonumber((time and time()) or 0) or 0,author=author,
            ownerKey=localOwner,ownerVerified=true,
        }
    local localRemoval = {localRemoved=false,localPending=false,
        queueAdmitted=false,retryPending=false}
    local function Finish(tombStored, tombStoreWhy)
        if not tombStored then
            stats.storageRejected = (stats.storageRejected or 0) + 1
            local refused, operationWhy = Operation.NewDelete(id, tomb)
            if not refused then return false, operationWhy end
            Operation.latestDelete = refused
            Operation.Transition(refused, "rejected",
                tombStoreWhy or "tombstone storage refused")
            return false, tombStoreWhy or "tombstone storage refused",
                Operation.Copy(refused)
        end
        tomb = CatalogTombstoneView(id) or tomb
        Responder.Work.ForgetHotBuild(id)
        RequestRetention("local delete stored")
        -- MASTER-RC-019. Architecture line 4856 and the mixed-client tombstone
        -- rows: "Refuse before encoder invocation with
        -- REMOTE_TOMBSTONE_ORDER_UNPROVEN; emit zero bytes, retain the exact local
        -- serving root, create no outbound ownership claim, and produce zero
        -- relay", and for new->new "Same local refusal and zero-wire result ... A
        -- local row-to-tombstone operation is not a Sync message."
        --
        -- The refusal is UNCONDITIONAL. It is not conditioned on a peer protocol
        -- version, and it cannot be: no per-peer protocol-capability tracking
        -- exists anywhere in this codebase. Session.MarkPeer stores the parsed
        -- addon version, core/SyncCompatibility.lua carries no protocol/release/
        -- legacy concept, and protocolVersion is a DPS payload field.
        --
        -- The local tombstone was already committed through the central owner
        -- above and is RETAINED: only the wire is refused. This returns before
        -- DeleteWireMessage is constructed and before Transport.Enqueue, and the
        -- status registers no active delete claim.
        local status, operationWhy = Operation.NewDelete(id, tomb, false)
        if not status then return false, operationWhy end
        Operation.latestDelete = status
        Operation.Transition(status, "rejected", "REMOTE_TOMBSTONE_ORDER_UNPROVEN")
        ClearPendingDelete(id, tomb)
        return false, "REMOTE_TOMBSTONE_ORDER_UNPROVEN", Operation.Copy(status)
    end
    local function Complete(tombStored, tombStoreWhy)
        local queued, why, status = Finish(tombStored, tombStoreWhy)
        localRemoval.localPending = false
        localRemoval.localRemoved = tombStored == true
        localRemoval.storageReason = not tombStored and tombStoreWhy or nil
        localRemoval.queueAdmitted = queued == true
        localRemoval.queueReason = not queued and why or nil
        return queued, why, status, localRemoval
    end
    local tombStored, tombStoreWhy, ticket = CatalogSetTombstone(id, tomb, {source="local"})
    if tombStored == nil and tombStoreWhy == "ROOT_MUTATION_PENDING" then
        if not BindCatalogCompletion(ticket, function(stored, why)
            Complete(stored, why)
            if type(onLocalComplete) == "function" then onLocalComplete(localRemoval) end
        end) then
            return Complete(false, "INVALID_MUTATION_TICKET")
        end
        -- Wire admission remains false. This separate receipt proves that the
        -- original local ticket was accepted; callers must not submit it again.
        localRemoval.localPending = true
        localRemoval.storageReason = tombStoreWhy
        return false, tombStoreWhy, nil, localRemoval
    end
    return Complete(tombStored, tombStoreWhy)
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

local function ShouldStore(id, lastMod, author, ownerKey, transportSender)
    if not AllowsRemoteRevision(author, lastMod, id) then
        return false, "retention floor"
    end
    -- Any tombstone reservation denies every inbound row for its typed ID.
    -- Protocol 7 supplies no order proof, so remote resurrection never
    -- succeeds; only an explicit trusted local claim can readmit a row. A
    -- foreign owner claim is reported as a refusal, not a benign duplicate.
    local reservation = CatalogTombstoneView(id)
    if reservation then
        local reserved = Identity.CanonicalOwnerKey(reservation.ownerKey)
        local incoming = Identity.CanonicalOwnerKey(ownerKey)
        if reserved and (incoming ~= reserved
            or not Identity.TransportOwns(reserved, transportSender)) then
            return false, "tombstone owner"
        end
        return false, "deleted"
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
        matchedReplacement, canonicalFingerprint, onComplete)
    local existing = CatalogGet(payload.id)
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
        claimedOwnerKey=not ownerVerified and payload.ownerKey or nil,
        class=payload.class, echoes=payload.echoes,
        postedAt=payload.postedAt, lastModified=payload.lastModified, isMine=false,
        autoDps=payload.autoDps, fingerprint=fingerprint,
        fingerprintHash=HashText(fingerprint),
        echoCount=(function() local t=0; for _,e in ipairs(payload.echoes) do t=t+(tonumber(e.stacks or e.count) or 1) end; return t end)(),
        loadoutAvailable=true,
        link=link,
        linkHash=HashText(link), needsFullBuild=nil,
        ownerVerified=ownerVerified and true or false,
        relaySender=not ownerVerified and relaySender or nil,
    }
    local function Complete(stored, storedAs)
        if not stored then return false, storedAs end
        if storedAs == "baseline" then
            stats.baselineSkipped = (stats.baselineSkipped or 0) + 1
        end
        seenRemoteIds[payload.id] = payload.lastModified
        Session.ClearRequestedLoadout(payload.id, payload.lastModified)
        stats.received = stats.received + 1
        RequestRetention("full build received")
        return true, storedAs
    end
    local stored, storedAs, ticket = CatalogPut(record, {source="remote",
        sender=relaySender})
    if stored == nil and storedAs == "ROOT_MUTATION_PENDING" then
        if not BindCatalogCompletion(ticket, function(ok, why)
            onComplete(Complete(ok, why))
        end) then return false, "INVALID_MUTATION_TICKET" end
        return nil, storedAs
    end
    return Complete(stored, storedAs)
end

local function CommitReceivedBuild(payload, transportSender, context,
        onComplete, deferredEntry)
    local directOwner = Identity.TransportOwns(
        payload.ownerKey, transportSender)
    local existing, existingSource = CatalogGet(payload.id)
    if existing and Identity.SavedMirrorKind(existing) ~= "ordinary" then
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        return false
    end
    local previousRemoteStamp = seenRemoteIds[payload.id]
    local payloadOwner = Identity.CanonicalOwnerKey(payload.ownerKey)
    local replacingUnverified = existing and directOwner
        and CanPromoteStoredOwner(existing, payloadOwner)
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
    if existing and not LocalOwnsStoredBuild(existing)
        and not replacingUnverified then
        local existingOwner = TrustedStoredOwnerKey(existing, existingSource)
        if not existingOwner or existingOwner ~= payloadOwner then
            LogEvent("RX", "REJECT owner change for '%s'", tostring(payload.id))
            PeerObserve("receiver_commit", {id=payload.id,
                peer=transportSender,outcome="rejected",reason="owner change"})
            Responder.NoteContextOutcome(context, "rejected", "ownership")
            return false
        end
    end
    local allowed, why
    if replacingUnverified then
        allowed, why = true, "owner-verified"
    else
        allowed, why = ShouldStore(payload.id, payload.lastModified,
            payload.author, payload.ownerKey, transportSender)
    end
    if not allowed then
        if why == "deleted" then
            LogEvent("RX","skip '%s': tombstoned", tostring(payload.title))
            Responder.NoteContextOutcome(context, "rejected", "tombstone")
        elseif why == "tombstone owner" then
            LogEvent("RX", "REJECT resurrection of '%s': tombstone belongs to %s",
                tostring(payload.id), tostring(TombAuthor(CatalogTombstoneView(payload.id))))
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
        return why ~= "tombstone owner"
    end
    if existing and not directOwner then
        LogEvent("RX", "REJECT relayed overwrite of '%s' from %s",
            tostring(payload.id), tostring(transportSender))
        PeerObserve("receiver_commit", {id=payload.id,peer=transportSender,
            outcome="rejected",reason="relayed overwrite"})
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        return false
    end
    if existing and LocalOwnsStoredBuild(existing) then
        LogEvent("RX", "REJECT remote overwrite of local build '%s'",
            tostring(payload.id))
        PeerObserve("receiver_commit", {id=payload.id,peer=transportSender,
            outcome="rejected",reason="local owner"})
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        return false
    end
    local function Complete(stored, storedWhy)
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
    local function Submit()
        return StoreReceivedBuild(
            payload, directOwner, transportSender, matchedReplacement,
            replacementFingerprint, function(completed, completedWhy)
                local accepted = Complete(completed, completedWhy)
                if type(onComplete) == "function" then onComplete(accepted) end
                return accepted
            end)
    end
    local held = not deferredEntry and Responder.Admission.RequestHold()
    local stored, storedWhy
    if not held then
        stored, storedWhy = Submit()
        if stored == nil and storedWhy == "ROOT_MUTATION_PENDING" then
            return nil, storedWhy
        end
    end
    if held or Responder.Admission.Busy(stored, storedWhy) then
        if deferredEntry then return nil, "ADMISSION_BUSY" end
        if held then stats.admissionHeld = (stats.admissionHeld or 0) + 1 end
        local disposition = Responder.Admission.Defer({
            kind="build",id=payload.id,
            stamp=tonumber(payload.lastModified) or 0,
            owner=payloadOwner or "",direct=directOwner == true,
            digest=tostring(HashText(replacementFingerprint) or "") .. "|"
                .. tostring(HashText(payload.link) or ""),
            sender=transportSender,context=context,
            settle=function(accepted)
                if type(onComplete) == "function" then onComplete(accepted) end
            end,
            run=function(entry)
                local accepted, pendingWhy = CommitReceivedBuild(payload,
                    transportSender, context, onComplete, entry)
                if accepted == nil and pendingWhy == "ADMISSION_BUSY" then
                    return "busy"
                end
                Responder.Admission.Remove(entry)
                stats.admissionResolved = (stats.admissionResolved or 0) + 1
                if accepted == nil and pendingWhy == "ROOT_MUTATION_PENDING" then
                    return "ticket"
                end
                entry.settle(accepted)
                return "terminal"
            end,
        })
        if disposition == "deferred" then return nil, "ROOT_MUTATION_PENDING" end
        if disposition == "duplicate" then return true end
        if disposition == "rejected" then return false end
        -- "overflow": the same counted storage refusal, held or busy.
        stored, storedWhy = false, "ROOT_MUTATION_PENDING"
    end
    return Complete(stored, storedWhy)
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
    if IsLocalTransportSender(requester) and Session
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
    if IsLocalTransportSender(requester) then
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

local function HandleDelete(sender, buildId, stamp, originAuthor, context,
        onComplete)
    local existing, existingSource = CatalogGet(buildId)
    -- originAuthor is an optional 5th field; treat empty string same as nil
    local author = tostring((originAuthor and originAuthor ~= "")
        and originAuthor or sender or "")
    local senderOwner = Identity.CanonicalOwnerFromTransport(sender)
    local qualifiedAuthorOwner = author:find("-", 1, true)
        and Identity.CanonicalOwnerFromTransport(author) or nil
    if not SamePeer(sender, author)
        or (author:find("-", 1, true)
            and qualifiedAuthorOwner ~= senderOwner) then
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        LogEvent("RX", "REJECT relayed delete for '%s' from %s",
            tostring(buildId), tostring(sender))
        return false
    end
    local prior = CatalogTombstoneView(buildId)
    if prior then
        -- An exact replay of the reservation evidence is an idempotent no-op;
        -- every unequal replay is a conflict that changes nothing.
        if TombStamp(prior) == (tonumber(stamp) or 0)
            and TombAuthor(prior) == author then
            Responder.NoteContextOutcome(context, "duplicate", "stale")
            return true
        end
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        LogEvent("RX", "REJECT tombstone conflict for '%s' from %s",
            tostring(buildId), tostring(sender))
        return false
    end
    if not existing then
        local refusal = CatalogRootRefusal()
        if refusal then
            stats.storageRejected = (stats.storageRejected or 0) + 1
            Responder.NoteContextOutcome(context, "rejected", "storage")
            LogEvent("RX", "REJECT delete of '%s': local storage refused (%s)",
                tostring(buildId), refusal)
            return false
        end
        Responder.NoteContextOutcome(context, "rejected", "tombstone")
        LogEvent("RX", "REJECT unprovable tombstone for unknown build '%s'",
            tostring(buildId))
        return false
    end
    if Identity.SavedMirrorKind(existing) ~= "ordinary" then
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        LogEvent("RX", "REJECT delete of private or malformed build '%s'",
            tostring(buildId))
        return false
    end
    if LocalOwnsStoredBuild(existing) then
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        LogEvent("RX","ignoring delete for MY build '%s' relayed by %s",
            tostring(existing.title), tostring(sender))
        return false
    end
    local existingOwner = TrustedStoredOwnerKey(existing, existingSource)
    if not existingOwner
        and CanPromoteStoredOwner(existing, senderOwner) then
        existingOwner = senderOwner
    end
    if not existingOwner
        or not Identity.TransportOwns(existingOwner, sender) then
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        LogEvent("RX","REJECT delete of '%s': origin %s is not the author (%s)",
            tostring(existing.title), author, tostring(existing.author))
        return false
    end
    -- REMOTE_TOMBSTONE_ORDER_UNPROVEN, inbound. A WLRD carries an ID, a clock
    -- stamp and an author. It carries no target revision or digest and no
    -- operation order that is comparable with a row edit: edits use
    -- max(now, previous + 1) while a tombstone uses the clock. So no stamp,
    -- older, equal or later, proves that this withdrawal follows the stored
    -- revision, and a verified direct owner proves authorship only. A new
    -- withdrawal therefore never creates a reservation and never hides a
    -- stored row. This claims no order rule and enables no remote withdrawal.
    -- Reservations that already exist are untouched above: an exact replay is
    -- a no-op, an unequal one a conflict, and they keep denying inbound rows.
    -- The remote CatalogSetTombstone path that followed had no other caller.
    stats.withdrawalOrderRefused = (stats.withdrawalOrderRefused or 0) + 1
    Responder.NoteContextOutcome(context, "rejected", "tombstone")
    LogEvent("RX", "REJECT delete of '%s' from %s: REMOTE_TOMBSTONE_ORDER_UNPROVEN (stamp %s, stored revision %s)",
        tostring(buildId), tostring(sender), tostring(stamp),
        tostring(existing.lastModified or existing.postedAt))
    return false
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
            and not IsLocalTransportSender(description.requester) then
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
    handleDelete=function(description, onComplete)
        return HandleDelete(description.sender, description.buildId,
            description.stamp, description.originAuthor, description.context,
            onComplete)
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
        if IsLocalTransportSender(description.requester)
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
        local directOwner = Identity.TransportOwns(
            type(record) == "table" and (record.o or record.ownerKey), sender)
        local marked = Responder.SupportsRequestContext(context and context.i)
        -- Old protocol-7 responders can echo the marked request in relay JSON
        -- but cannot add the Stage 36.3 envelope suffix.  Preserve that
        -- authorized relay as ambient input; contextual peers must still match
        -- x and envelope exactly before they can affect request progress.
        local envelopeMatches = envelopeContext == nil
            or (marked and type(envelopeContext) == "table"
                and SameTransportSender(context.n, envelopeContext.requester)
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
                and IsLocalTransportSender(context.n)
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
        -- Never reuse payload-supplied authority hints for automatic egress.
        -- Only an exact transport-to-owner bridge may enter the established
        -- direct-owner redistribution path.
        if not relayed and Identity.TransportOwns(
                record.o or record.ownerKey, sender) then
            Sync.BroadcastDpsRecord(record)
        end
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
    shortPeerName=function(name)
        return Identity.PlayerKey(name) or ""
    end,
    isLocalPeer=function(sender)
        return IsLocalTransportSender(sender)
            or (Identity.CanonicalOwnerFromTransport(sender) == nil
                and SamePeer(sender, MyName()))
    end,
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
    isRequestChannelPresent=function()
        local index = FindSyncChannel()
        if not index then channelIndex = nil end
        return index ~= nil
    end,
    ensureChannel=function() return Sync.EnsureChannel() end,
    sendWhisper=function(message, target)
        return SendChatMessage(message, "WHISPER", nil, target)
    end,
})

function Sync.HandleIncoming(text, sender)
    local accepted,reason=Inbound.HandleIncoming(text,sender)
    if accepted and Nexus.SyncWire then Nexus.SyncWire.ObservePeer(sender) end
    return accepted,reason
end

-- Manual Sync Now uses the same bounded convergence passes as login and can
-- supersede stale automatic work without duplicating outstanding transfers.
function Sync.RequestSync()
    local startup=type(Nexus.StartupStatus)=="function" and Nexus.StartupStatus()
    if startup and (startup.state~="ready" or not startup.syncReady) then
        return false,startup.state=="failed"
            and "shared data preparation failed; see /nexus log errors"
            or "shared data is preparing; try Sync again when ready"
    end
    return Session.RequestSync()
end

function Sync.GetLeaderboardSyncStatus()
    local session = Session.StatusSnapshot()
    local transport = Transport.Snapshot()
    local requestTransport = Transport.RequestSnapshot(MyName(),
        session.requestId)
    local requestIncoming = Inbound.RequestCounts(
        CurrentTransportSender(), session.requestId)
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
        deferredAdmissions=Responder.Admission.count,
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

function Sync.WireStatus()
    return Nexus.SyncWire and Nexus.SyncWire.Stats() or {available=false}
end

function Sync.TombstoneCount()
    local catalog = Catalog()
    if not (catalog and type(catalog.Status) == "function") then return 0 end
    local status = catalog.Status()
    return type(status) == "table" and tonumber(status.tombstoneCount) or 0
end

-- Safe while catalog/hash readiness gates the full update. This cannot
-- prepare requests, retry transfers, admit packets, or send network traffic.
function Sync.Housekeep()
    -- Passive expiry only: a deferred inbound item is never submitted here.
    Responder.Admission.Expire()
    Operation.housekeeping = true
    local ok, err = pcall(Transport.Housekeep)
    Operation.housekeeping = false
    if not ok then error(err, 0) end
end

-- Only already-admitted manual Share summaries can progress behind the full
-- update gate. The passive catalog proof must still describe this owner's
-- admitted root. No preparation, new admission, retry or handshake runs here.
function Sync.PumpPreparedShare(elapsed)
    local catalog = Catalog()
    local preparation = catalog and type(catalog.ManualPreparationStatus) == "function"
        and catalog.ManualPreparationStatus() or nil
    if not (preparation and preparation.ownerAgrees
        and (preparation.ready or preparation.relevant)) then
        return Sync.Housekeep()
    end
    Responder.Admission.Expire()
    Operation.housekeeping = true
    local ok, err = pcall(Transport.PumpPreparedShare, elapsed)
    Operation.housekeeping = false
    if not ok then error(err, 0) end
end

function Sync.OnUpdate(elapsed)
    Responder.Admission.NoteTurn()
    Responder.Admission.Expire()
    Inbound.CleanExpired()
    ProcessPendingResponses(elapsed)
    Session.PumpRecovery(elapsed)
    Responder.Work.PumpBroadcastMine()
    if not Sync._pendingDeleteScheduled then
        PumpPendingDeletes(elapsed)
        PumpPendingShare(elapsed)
    end
    Session.PrepareTransport()
    if Nexus.SyncWire then Nexus.SyncWire.PumpHandshake() end
    Transport.Pump(elapsed)
    if Sync.FlushStatusReply then Sync.FlushStatusReply() end
    Session.UpdateAutoSync(elapsed)
    Session.UpdateAutoConvergence()
    Session.UpdateJoinRetry(elapsed)
    -- After the request, response and transport turn above, never before it.
    Responder.Admission.Pump()
    -- A refresh can initiate legacy catalog repair. Release it only after
    -- the already-ready update, not before its transport validation work.
    if Operation.housekeepingRefreshPending then
        Operation.housekeepingRefreshPending = false
        pcall(Sync.RequestDataViewRefresh)
    end
end

-- Safe before catalog/hash readiness: only expire or disconnect a retained
-- request. This never pumps recovery, hashes, or transport ahead of their gate.
-- The additive second result is an opaque identity while an explicit manual
-- request owns preparation. Repeated clicks keep that same identity.
function Sync.UpdatePendingRequestStatus()
    return Session.UpdatePendingRequestStatus()
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
    Operation.housekeeping, Operation.housekeepingRefreshPending = false, false
    catalogMutationIdentity = {}
    Codec, Adapter = codec, adapter
    if Nexus.SyncWire then Nexus.SyncWire.Init(function(text,sender)
        return Inbound.HandleIncoming(text,sender)
    end) end
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
    Responder.Admission.Reset()
    Inbound.Reset()
    Session.Reset()
    Compatibility.Reset()
    Reconciler.Reset()
    preparedDpsProofs = setmetatable({}, {__mode="k"})
    hotBuilds = {}  -- clear on init
    Responder.state.hotBuildGeneration =
        (Responder.state.hotBuildGeneration or 0) + 1
    Responder.state.broadcastMineJob = nil
    EnsureHotBuildEvidenceProvider()
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
    -- MASTER-RC-001, dependent-side prohibition of architecture lines
    -- 1207-1211. This previously drove Catalog().Init
    -- directly from Sync.Init, which is exactly a dependent initializer calling
    -- another domain recovery pump: architecture line 1715 makes `Init` a
    -- pump that "cannot be called outside the startup coordinator or an
    -- explicit supported rebind." It now registers one idempotent dependency
    -- and binds nothing; the coordinator services it.
    -- The dependency is registered only when there actually is one. This is
    -- the same condition the read gate uses (NexusDB ~= the bound database);
    -- registering unconditionally would force a needless re-admission on every
    -- ordinary login and discard in-flight candidate state.
    local catalog = Catalog()
    if catalog and type(catalog.RequestAuthorityRebindV1) == "function"
        and type(catalog.BoundDatabase) == "function"
        and catalog.BoundDatabase() ~= NexusDB then
        catalog.RequestAuthorityRebindV1("SOURCE_REBIND_REQUIRED")
    end
    -- Tombstone authority is served only by the catalog's published root;
    -- Sync never binds the raw SavedVariables tombstone table again.
    tombstones = {}
    Operation.deleteCursor = nil
    Operation.deleteDiscoveryComplete = true
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
