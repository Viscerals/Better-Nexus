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
--   • Hot-build window (120s): a build this client broadcast keeps its
--     evidence pinned for the responder window, then is forgotten
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
-- WLCP: locked-role wire capability (docs/P1_7_LOCKED_ROLE_WIRE.md).
-- Released peers drop this unknown code before parsing it. (No new chunk
-- local: the main chunk is at Lua's 200-local limit.)
local PEER_PROTOCOL_CODES = {
    [CODE_BUILD]=true, [CODE_INDEX]=true, [CODE_LOADOUT_REQ]=true,
    [CODE_LOADOUT_CLAIM]=true, [CODE_REQUEST]=true, [CODE_CLAIM]=true,
    [CODE_BUCKET_CLAIM]=true, [CODE_DELETE]=true, [CODE_DPS]=true,
    [CODE_DPS2]=true, [CODE_PRESENCE]=true, WLCP=true,
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
local hotBuilds      = {}   -- id -> { build, t }; broadcast builds, pinned for HOT_WINDOW
local hotBuildCheckedAt = 0 -- the last once-per-second hot-build expiry check
local registeredHotBuildEvidenceOwner
local pendingShare          -- one immutable, session-only Share summary
local pendingShareTicker = 0
local Operation = {
    latestShare=nil,latestDelete=nil,active={},activeShares={},
    activeDeletes={},shareById={},deleteById={},recent={},recentNext=1,
    recentCap=64,sequence=0,deleteDiscoveryComplete=true,
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
-- order/byKey/count are the items still waiting. inFlight holds the members of
-- the batch that is currently inside the catalog candidate: they have left the
-- queue but are not settled, so they keep counting against the same bounds and
-- no new arrival gains an unaccounted allowance while a batch runs.
-- The behaviour is installed by core/SyncAdmission.lua below (see "Deferred
-- inbound admission").
Responder.Admission = {order={}, byKey={}, count=0, maxTotal=64, maxPerSender=16,
    inFlight={}, inFlightCount=0}
local catalogMutationIdentity

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

-- A broadcast build stays hot for HOT_WINDOW seconds after its broadcast and
-- then leaves; nothing keeps it pinned for the rest of the session. The pin
-- is not what keeps the build's queued transfer intact: AdmitBuild
-- serializes the whole build into the queued packets before it pins the
-- build, and Transport owns those strings until they are sent or expire
-- (PENDING_MAX_AGE, longer than this window). The pin only reports the
-- build's evidence reference to the evidence reference provider for the
-- responder window; its expiry releases that reference and nothing else
-- (tests/prototype/sync_hot_build_release.lua). Checked once a second.
local function ExpireHotBuilds()
    local now = Now()
    if now - hotBuildCheckedAt < 1 then return 0 end
    hotBuildCheckedAt = now
    local expired = 0
    for id, hot in pairs(hotBuilds) do
        local posted = type(hot) == "table" and tonumber(hot.t) or nil
        if posted == nil or now - posted > HOT_WINDOW then
            hotBuilds[id] = nil
            expired = expired + 1
        end
    end
    if expired > 0 then
        Responder.state.hotBuildGeneration =
            (Responder.state.hotBuildGeneration or 0) + 1
    end
    return expired
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
        callback(committed, committed and outcome.storedAs or outcome.reason,
            outcome.detail)
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
        pendingDeletes=0, -- MASTER-RC-019: no delete ever acquires retry ownership
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

-- A temporary channel join is asynchronous: the channel is listed a moment
-- after the join call, so the lookup inside EnsureChannel can fail although
-- the join succeeds. The join retry runs only inside the full Sync turn and
-- needs JOIN_RETRY_INTERVAL of full-turn time, and every hold and yield of the
-- deferred admission owner requires IsConnected. On a client whose catalog is
-- kept busy by inbound records that retry never ran: in the offline probe the
-- client stayed unconnected for the whole 600-second observation while channel
-- traffic kept arriving. (A native report showed connected=false at one reading;
-- the rest of that session was not observed.)
-- Channel traffic is itself proof of membership. This reads the channel list
-- and records the slot the game reports, exactly like the "already in" branch
-- of EnsureChannel. It never joins, sends, pumps or touches the catalog, it
-- does nothing while an index is known, and it never reports a connection the
-- game does not list. Every send still re-resolves its slot in
-- ResolveSendChannel, and the join retry and its attempt cap are unchanged.
function Sync.NoteChannelTraffic()
    if channelIndex ~= nil and channelIndex > 0 then return false end
    local idx = FindSyncChannel()
    if not idx then return false end
    channelIndex = idx
    HideChannelFromChat()
    LogEvent("CHAN","found '%s' at index %d from channel traffic", SYNC_CHANNEL, idx)
    return true
end

function Sync.ChannelName()  return SYNC_CHANNEL end
function Sync.ChannelIndex() return channelIndex end
function Sync.IsConnected()  return channelIndex ~= nil and channelIndex > 0 end
function Sync.Stats()
    -- The diagnostic queue enum describes transport, not hash preparation.
    -- Expose the current session's separate readiness state without inventing
    -- a queued request or expanding that transport enum.
    stats.preparingRequest = Session.StatusSnapshot().queueOutcome == "preparing"
    local hot = 0
    for _ in pairs(hotBuilds) do hot = hot + 1 end
    stats.hotBuilds, stats.hotWindow = hot, HOT_WINDOW
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
    -- The saved Sync mode (core/SyncModePolicy.lua): the same decision the
    -- wire asks again at submission.
    permit=function(metadata)
        local policy=Nexus.SyncModePolicy
        if not policy then return true end
        return policy.Allows("packet",metadata)
    end,
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
    permitResponse=function(requester, buildId)
        local policy=Nexus.SyncModePolicy
        if not policy then return true end
        return policy.Allows("packet",{requester=requester,buildId=buildId})
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
        -- Same follow-up permission as a first-time admission, with the
        -- Share's own (unchanged) expiry.
        if Nexus.SyncModePolicy then
            Nexus.SyncModePolicy.NoteExplicitShare(status.id,
                pending.metadata and pending.metadata.expiresAt)
        end
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
        -- Under a saved Manual mode, peers fetching this shared record are
        -- answered until this Share's own expiry.
        if Nexus.SyncModePolicy then
            Nexus.SyncModePolicy.NoteExplicitShare(status.id, metadata.expiresAt)
        end
    end
    LogEvent("TX","queuing summary '%s' (%d chars, no Echo list)", tostring(build.title), EscapedLen(msg))
    return true, "queued", Operation.Copy(status)
end
Sync.BroadcastBuildSummary = BroadcastSummary

function Sync.GetShareStatus(id)
    local status = id ~= nil and Operation.shareById[tostring(id)]
        or Operation.latestShare
    if type(status) ~= "table" then return nil end
    local copy = Operation.Copy(status)
    -- Responses prepared for this build that carried its locked targets, and
    -- those that carried the ordinary targets only (older requesters).
    -- Prepared is not received: nothing here claims peer storage.
    local roles = type(copy) == "table" and Responder.LockedRoleOutcomes
        and Responder.LockedRoleOutcomes[tostring(copy.id)] or nil
    if roles then
        copy.lockedRolesFull = roles.full
        copy.lockedRolesOrdinaryOnly = roles.ordinaryOnly
    end
    return copy
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

-- MASTER-RC-019. The originating local delete is an unconditional zero-wire
-- refusal (architecture line 4856) and the responder path encodes no
-- withdrawal either, so no delete ever acquires retry ownership. The retry
-- pump, its session map, its discovery and its count were dead and are gone;
-- `Sync.WorkState()` keeps reporting the public fields, which were always
-- zero. A durable `pending` field on a tombstone is opaque evidence and grants
-- no retry authority. Remote withdrawal stays unsupported until the protocol
-- carries a comparable edit/delete order.

-- Whether the scheduler owns the once-per-second Share retry pump (then the
-- update turn skips it). On the module table: this chunk is near the Lua 5.1
-- limit of 200 locals and the field is read by the step table below.
Sync._pendingShareScheduled = false

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

-- The owner lives in core/SyncAdmission.lua, a verbatim move out of this
-- chunk, which is at the Lua 5.1 limit of 200 local variables. The factory
-- installs the Responder.Admission functions onto the state table created
-- above. Session and the catalog mutation identity are bound after this
-- point, so they are handed over as accessors.
if not (Nexus.SyncInternals and type(Nexus.SyncInternals.Admission) == "table"
    and type(Nexus.SyncInternals.Admission.New) == "function") then
    error("Nexus SyncAdmission must load before Sync")
end
Nexus.SyncInternals.Admission.New({
    responder=Responder,
    sync=Sync,
    stats=stats,
    now=Now,
    catalog=Catalog,
    currentOwnerKey=CurrentOwnerKey,
    mutationIdentity=function() return catalogMutationIdentity end,
    transport=Transport,
    reconciler=Reconciler,
    session=function() return Session end,
    bindCatalogCompletion=BindCatalogCompletion,
    logEvent=LogEvent,
    peerObserve=PeerObserve,
    pendingTtl=PENDING_TTL,
    pendingMaxAge=PENDING_MAX_AGE,
    responseElectionDelay=RESPONSE_ELECTION_DELAY,
})

-- Read-only view of the retained inbound items: one bounded row per queued
-- entry, in queue order. It starts no work, submits nothing, settles nothing
-- and changes no counter, so a diagnostic or a test can report exclusive
-- queued/in-flight/terminal categories without driving admission.
function Sync.AdmissionSnapshot()
    local current, rows = Now(), {}
    for index, entry in ipairs(Responder.Admission.order) do
        rows[index] = {kind=entry.kind, id=entry.id, sender=entry.sender,
            stamp=entry.stamp, direct=entry.direct,
            enqueuedAt=entry.enqueuedAt, expiresAt=entry.expiresAt,
            age=current - entry.enqueuedAt}
    end
    local flying = {}
    for index, member in ipairs(Responder.Admission.inFlight) do
        flying[index] = {key=member.key, sender=member.sender}
    end
    return {count=Responder.Admission.count, entries=rows,
        inFlight=Responder.Admission.inFlightCount, inFlightEntries=flying,
        maxTotal=Responder.Admission.maxTotal,
        maxPerSender=Responder.Admission.maxPerSender}
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
        -- Inside a receiver batch the validated record joins the batch instead
        -- of starting a catalog mutation of its own. Everything above this
        -- point has already run for this item: schema, ownership, tombstone,
        -- revision and freshness checks included.
        local collector = Responder.Admission.collector
        if collector and deferredEntry then
            collector[#collector + 1] = {
                record=record,
                options={source="remote", sender=transportSender},
                key=deferredEntry.key, sender=deferredEntry.sender,
                entry=deferredEntry,
                complete=function(ok, why)
                    if type(onComplete) == "function" then
                        onComplete(Complete(ok, why))
                    else
                        Complete(ok, why)
                    end
                end,
            }
            return nil, "ROOT_MUTATION_PENDING"
        end
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
    local held = not deferredEntry and (Responder.Admission.RequestHold()
        or Responder.Admission.OwedHold())
    local behind = not deferredEntry and Responder.Admission.Behind()
    local stored, storedAs
    if not (held or behind) then
        stored, storedAs = Submit()
        if stored == nil and storedAs == "ROOT_MUTATION_PENDING" then
            return nil, false, storedAs
        end
    end
    if held or behind or Responder.Admission.Busy(stored, storedAs) then
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

-- Locked-role completion for one stored build, on a deliberate user action
-- only (docs/P1_7_LOCKED_ROLE_WIRE.md). The record must be a remote build of
-- an independently verified owner whose locked roles are unknown. One exact-ID
-- request is queued with our capability stated; only the owner's own
-- same-revision full answer can enrich it (ShouldStore "roles"; a relay's
-- answer is refused). Nothing is sent from rendering, and nothing retries:
-- a new request needs a new click after the previous one ended. Memory only.
Sync.RolesRequests = {byId={}, count=0, max=32, timeout=60}

function Sync.RequestLockedRoles(buildId)
    local wireId, why = WireBuildId(buildId)
    if not wireId then return false, "refused", tostring(why or "invalid build ID") end
    local key = tostring(buildId)
    local build = CatalogGet(buildId)
    if type(build) ~= "table" or type(build.echoes) ~= "table"
        or #build.echoes == 0 then
        return false, "refused", "the build's Echo list is not in your library"
    end
    if LocalOwnsStoredBuild(build) then
        return false, "refused", "this is your own build"
    end
    if not Identity.VerifiedOwnerKey(build) then
        return false, "refused", "the build owner is not verified"
    end
    if Responder.Caps.KnownLockedRoles(build) ~= nil then
        return false, "complete", "the locked Echo roles are already known"
    end
    local requests = Sync.RolesRequests
    local entry = requests.byId[key]
    if entry and Sync.LockedRolesRequestStatus(buildId) == "pending" then
        return false, "pending", "a request for this build is already waiting"
    end
    local policy = Nexus and Nexus.SyncModePolicy
    local mode = policy and policy.Mode and policy.Mode() or "automatic"
    if mode == "off" then
        return false, "refused", "Sync is Off"
    end
    if mode == "manual" and not Session.ManualGrant() then
        return false, "refused",
            "Sync is in Manual mode. Press Sync Now, then request again"
    end
    if not Sync.IsConnected() then
        return false, "offline", "not connected to the Nexus sync channel"
    end
    if not Session.QueueRolesRequest(buildId) then
        return false, "refused", "the request queue is full"
    end
    if not entry then
        if requests.count >= requests.max then
            local oldest, stamp
            for id, value in pairs(requests.byId) do
                if not stamp or value.at < stamp then oldest, stamp = id, value.at end
            end
            if oldest then requests.byId[oldest] = nil; requests.count = requests.count - 1 end
        end
        requests.count = requests.count + 1
    end
    requests.byId[key] = {state="pending", at=Now()}
    LogEvent("SYNC", "user requested the locked roles of '%s'", key)
    return true, "pending"
end

-- nil when no request was made; otherwise "pending", "complete", "refused"
-- or "timeout" with a factual reason. The reply time counts from the actual
-- send (a busy queue may hold the request first). Reading never sends.
function Sync.LockedRolesRequestStatus(buildId)
    local requests = Sync.RolesRequests
    local entry = buildId ~= nil and requests.byId[tostring(buildId)] or nil
    if not entry then return nil end
    local build = CatalogGet(buildId)
    if type(build) == "table"
        and Responder.Caps.KnownLockedRoles(build) ~= nil then
        return "complete"
    end
    if entry.state ~= "pending" then return entry.state, entry.reason end
    local sent, detail = Session.RolesRequestState(buildId)
    if sent == "unsent" then
        entry.state, entry.reason = "refused", detail == "mode"
            and "the saved Sync mode did not allow the request"
            or "the request could not be sent"
    elseif sent == "sent" and Now() - detail >= requests.timeout then
        entry.state, entry.reason = "timeout",
            "no reply with the locked Echo roles arrived"
    elseif sent ~= "sent" and Now() - entry.at >= 2 * requests.timeout then
        entry.state, entry.reason = "timeout",
            "the request could not be sent before the time limit"
    end
    if entry.state ~= "pending" then return entry.state, entry.reason end
    return "pending"
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

------------------------------------------------------------------------
-- Locked-role wire capability (#73; docs/P1_7_LOCKED_ROLE_WIRE.md)
------------------------------------------------------------------------
-- A peer states "lv1" in WLCP|sender|caps|nonce next to its own requests.
-- The state is memory only, keyed by the transport sender (the inbound owner
-- has already required that the message's sender field is that sender), and
-- expires; a reload clears it. It is advertised support for the
-- representation, never trusted authorship: every owner, provenance, size
-- and semantic check of a transfer stays unchanged. No version string is read.
-- All state and helpers live in one table: the main chunk is at Lua's
-- 200-local limit.
Responder.Caps = {
    code="WLCP", token="lv1", ttl=900, advertiseInterval=300, maxPeers=128,
    readvertiseSpacing=30, readvertise=false,
    peers={}, count=0, seen={}, seenCount=0, nonce=nil, lastAdvert=nil,
    outcomes={}, outcomeCount=0,
}
Responder.LockedRoleOutcomes = Responder.Caps.outcomes

function Responder.Caps.Nonce()
    local caps = Responder.Caps
    if not caps.nonce then
        -- From the clocks, not math.random: taking random numbers here would
        -- shift every later random draw (for example request IDs).
        local wall = type(time) == "function" and tonumber(time()) or 0
        local up = math.floor((tonumber(Now()) or 0) * 1000)
        caps.nonce = string.format("s%07x%06x", wall % 268435456, up % 16777216)
    end
    return caps.nonce
end

function Responder.NoteCapability(sender, advertised, nonce)
    local caps = Responder.Caps
    local key = NormalizePeerName(sender)
    if not key or key == "" then return false end
    local supports = false
    for token in tostring(advertised or ""):gmatch("[^,]+") do
        if token == caps.token then supports = true end
    end
    local entry = caps.peers[key]
    if not supports then
        -- The peer now states no support (for example after a downgrade).
        if entry then caps.peers[key] = nil; caps.count = caps.count - 1 end
        return true
    end
    -- A peer we did not know, or one with a new session nonce (it restarted),
    -- may not know our capability either: our next request states it again.
    if not entry or entry.nonce ~= tostring(nonce) then caps.readvertise = true end
    if not entry then
        if caps.count >= caps.maxPeers then
            local oldest, stamp
            for name, value in pairs(caps.peers) do
                if not stamp or value.at < stamp then oldest, stamp = name, value.at end
            end
            if oldest then caps.peers[oldest] = nil; caps.count = caps.count - 1 end
        end
        caps.count = caps.count + 1
    end
    caps.peers[key] = {lv=1, nonce=tostring(nonce), at=Now()}
    return true
end

function Responder.PeerSupportsLockedRoles(requester)
    local caps = Responder.Caps
    local key = type(requester) == "string" and NormalizePeerName(requester)
    local entry = key and caps.peers[key]
    if not entry then return false end
    if Now() - entry.at > caps.ttl then
        caps.peers[key] = nil; caps.count = caps.count - 1
        return false
    end
    return true
end

-- Activity from a peer without a current capability entry (a new peer, or
-- one that restarted and lost ours): our next request states the capability
-- again, not earlier than readvertiseSpacing after the last advertisement.
-- Once per peer per ttl, so an older peer that never advertises does not
-- keep the shorter spacing.
function Responder.NotePeerActivity(sender)
    local caps = Responder.Caps
    if Responder.PeerSupportsLockedRoles(sender) then return end
    local key = NormalizePeerName(sender)
    if not key or key == "" then return end
    local stamp = caps.seen[key]
    if stamp and Now() - stamp <= caps.ttl then return end
    if not stamp then
        if caps.seenCount >= caps.maxPeers then caps.seen, caps.seenCount = {}, 0 end
        caps.seenCount = caps.seenCount + 1
    end
    caps.seen[key] = Now()
    caps.readvertise = true
end

-- Enqueued just before one of our own requests, with a copy of that
-- request's metadata: the same queue, route and Sync-mode permission. Once
-- per interval, or again after readvertiseSpacing when a new or restarted
-- peer was seen; nothing is sent on its own schedule.
-- force: one user-requested roles completion (one advertisement per
-- deliberate request; see Sync.RequestLockedRoles).
function Responder.AdvertiseCapability(metadata, force)
    local caps = Responder.Caps
    local current = Now()
    local since = caps.lastAdvert and current - caps.lastAdvert or nil
    local due = force == true or since == nil
        or since >= caps.advertiseInterval
        or (caps.readvertise and since >= caps.readvertiseSpacing)
    if not due then
        return false
    end
    local copy = {}
    for key, value in pairs(type(metadata) == "table" and metadata or {}) do
        copy[key] = value
    end
    copy.requestId = "caps-" .. caps.Nonce()
    local message = string.format("%s|%s|%s|%s", caps.code, MyName(),
        caps.token, caps.Nonce())
    local queued = Transport.EnqueueControl(message, copy)
    if queued then caps.lastAdvert = current; caps.readvertise = false end
    return queued and true or false
end

-- The record's own locked-role state: its complete locked set (possibly
-- empty) when known, or nil when unknown. Inline slot-4 rows are the older
-- representation and are never restated.
function Responder.Caps.KnownLockedRoles(build)
    if type(build) ~= "table" then return nil end
    for _, echo in ipairs(build.echoes or {}) do
        if echo.locked then return nil end
    end
    if type(build.lockedEchoes) == "table" and #build.lockedEchoes > 0 then
        return build.lockedEchoes
    end
    if build.lockedAuthorityProven == true then return {} end
    return nil
end

-- A response states the locked set only to a requester that advertised the
-- capability, and only when this record knows it: a relay never
-- reconstructs roles it did not receive.
function Responder.LockedRolesFor(build, responseContext)
    local requester = type(responseContext) == "table"
        and responseContext.requester or nil
    if not requester or not Responder.PeerSupportsLockedRoles(requester) then
        return nil
    end
    return Responder.Caps.KnownLockedRoles(build)
end

-- Bounded per-build counts of prepared responses for records with locked
-- targets: with them, or ordinary targets only (an older requester).
function Responder.NoteLockedRoleOutcome(build, lockedRoles)
    local caps = Responder.Caps
    local known = caps.KnownLockedRoles(build)
    if not known or #known == 0 then return end
    local key = tostring(build.id or "")
    if key == "" then return end
    local entry = caps.outcomes[key]
    if not entry then
        if caps.outcomeCount >= 64 then return end
        entry = {full=0, ordinaryOnly=0}
        caps.outcomes[key] = entry
        caps.outcomeCount = caps.outcomeCount + 1
    end
    if lockedRoles then entry.full = entry.full + 1
    else entry.ordinaryOnly = entry.ordinaryOnly + 1 end
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
    local lockedRoles = responseMode
        and Responder.LockedRolesFor(build, responseContext) or nil
    local payload = CompactEncode(build, lockedRoles)
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
    if responseMode then Responder.NoteLockedRoleOutcome(build, lockedRoles) end
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

-- The whole-library "BroadcastMine" sweep (every catalog record plus the hot
-- set as summaries) had no caller left: the library reaches peers through
-- hash-bucket reconciliation, and a single posted or changed build through
-- its own Share summary. The hot-build expiry it carried now runs on its own
-- (ExpireHotBuilds).

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
        if item.kind ~= "tomb" then
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

local function ShouldStore(id, lastMod, author, ownerKey, transportSender,
        incomingFingerprint, incomingRolesKnown)
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
    -- The same revision with its locked roles stated may complete a record
    -- that arrived ordinary-only (roles unknown). It never replaces known
    -- roles, and the ordinary content must be the same.
    -- docs/P1_7_LOCKED_ROLE_WIRE.md
    if incomingRolesKnown and existing
        and (tonumber(lastMod) or 0) == known
        and existing.lockedAuthorityProven ~= true
        and not (type(existing.lockedEchoes) == "table"
            and #existing.lockedEchoes > 0)
        and type(incomingFingerprint) == "string"
        and existing.fingerprint == incomingFingerprint then
        return true, "roles"
    end
    return false, "duplicate"
end

local function StoreReceivedBuild(payload, ownerVerified, relaySender,
        matchedReplacement, canonicalFingerprint, onComplete, deferredEntry)
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
    -- Locked roles only as the payload states them (lv=1): the complete set,
    -- possibly empty. Without that statement they stay unknown (no field),
    -- never zero and never taken from an earlier revision.
    if type(payload.lockedRoles) == "table" then
        local rows = {}
        for _, echo in ipairs(payload.lockedRoles) do
            rows[#rows + 1] = {spellId=echo.spellId, quality=echo.quality,
                stacks=echo.stacks, locked=true}
        end
        record.lockedEchoes = rows
        record.lockedAuthorityProven = true
    end
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
    -- Inside a receiver batch this validated record joins the batch instead
    -- of starting a mutation of its own. Every check above has already run.
    local collector = Responder.Admission.collector
    if collector and deferredEntry then
        collector[#collector + 1] = {
            record=record, options={source="remote", sender=relaySender},
            key=deferredEntry.key, sender=deferredEntry.sender,
            entry=deferredEntry,
            complete=function(ok, why) onComplete(Complete(ok, why)) end,
        }
        return nil, "ROOT_MUTATION_PENDING"
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
        onComplete, deferredEntry, channelOwnerSender)
    local directOwner = Identity.TransportOwns(
        payload.ownerKey, channelOwnerSender or transportSender)
    local existing, existingSource = CatalogGet(payload.id)
    if existing and Identity.SavedMirrorKind(existing) ~= "ordinary" then
        Responder.NoteContextOutcome(context, "rejected", "ownership")
        return false
    end
    local previousRemoteStamp = seenRemoteIds[payload.id]
    local payloadOwner = Identity.CanonicalOwnerKey(payload.ownerKey)
    local replacingUnverified = existing and directOwner
        and CanPromoteStoredOwner(existing, payloadOwner)
    -- The peer trace displays a short name. Record the authority boundary
    -- separately without retaining that name, the owner key or payload.
    pcall(function()
        local debugOwner = Nexus and Nexus.PeerDebug
        if not (debugOwner and type(debugOwner.IsEnabled) == "function"
            and debugOwner.IsEnabled()) then return end
        local claim = existing and Identity.CanonicalOwnerKey(existing.claimedOwnerKey)
        local stored = existing and Identity.CanonicalOwnerKey(existing.ownerKey)
        PeerObserve("owner_boundary", {
            rawSenderQualified=Identity.CanonicalOwnerFromTransport(transportSender) ~= nil,
            localRealmAvailable=CurrentOwnerKey() ~= nil,
            directOwner=directOwner == true,
            claimMatches=payloadOwner ~= nil and (claim or stored) == payloadOwner,
            storedOwnerConflict=claim ~= nil and stored ~= nil and claim ~= stored,
            existingVerified=Identity.VerifiedOwnerKey(existing) ~= nil,
            sourceKind=not existingSource and "none"
                or existingSource == "bundled" and "bundled"
                or existingSource == "overlay" and "overlay" or "other",
        })
    end)
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
            payload.author, payload.ownerKey, transportSender,
            replacementFingerprint, payload.lockedRoles ~= nil)
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
            payload, directOwner, channelOwnerSender or transportSender, matchedReplacement,
            replacementFingerprint, function(completed, completedWhy)
                local accepted = Complete(completed, completedWhy)
                if type(onComplete) == "function" then onComplete(accepted) end
                return accepted
            end, deferredEntry)
    end
    local held = not deferredEntry and (Responder.Admission.RequestHold()
        or Responder.Admission.OwedHold())
    local behind = not deferredEntry and Responder.Admission.Behind()
    local stored, storedWhy
    if not (held or behind) then
        stored, storedWhy = Submit()
        if stored == nil and storedWhy == "ROOT_MUTATION_PENDING" then
            return nil, storedWhy
        end
    end
    if held or behind or Responder.Admission.Busy(stored, storedWhy) then
        if deferredEntry then return nil, "ADMISSION_BUSY" end
        if held then stats.admissionHeld = (stats.admissionHeld or 0) + 1 end
        local disposition = Responder.Admission.Defer({
            kind="build",id=payload.id,
            stamp=tonumber(payload.lastModified) or 0,
            owner=payloadOwner or "",direct=directOwner == true,
            digest=tostring(HashText(replacementFingerprint) or "") .. "|"
                .. tostring(HashText(payload.link) or ""),
            rolesKnown=type(payload.lockedRoles) == "table",
            sender=transportSender,context=context,
            settle=function(accepted)
                if type(onComplete) == "function" then onComplete(accepted) end
            end,
            run=function(entry)
                local accepted, pendingWhy = CommitReceivedBuild(payload,
                    transportSender, context, onComplete, entry, channelOwnerSender)
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
        capability="WLCP",
    },
    noteCapability=function(sender, caps, nonce)
        return Responder.NoteCapability(sender, caps, nonce)
    end,
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
    commitDps=function(record, sender, relayed, context, channelOwnerSender)
        local dps = Nexus and Nexus.DpsCapture
        local receiver = relayed and dps and dps.ReceiveRelayedRecord
            or dps and dps.ReceiveRecord
        if type(receiver) ~= "function" then
            Responder.NoteContextOutcome(context, "rejected", "storage")
            return false
        end
        local authoritySender = channelOwnerSender or sender
        if channelOwnerSender and not relayed then
            authoritySender = Identity.NativeChannelDpsOwnerSender(
                channelOwnerSender, record.o or record.ownerKey)
        end
        local ok, accepted, rejectionReason = pcall(receiver, record,
            authoritySender, channelOwnerSender)
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
        -- direct-owner redistribution path, and only for this client's own
        -- record (its channel echo): a remote owner's record is that owner's
        -- to redistribute, and BroadcastDpsRecord would refuse it as
        -- "owner_sender" after validating it in full.
        if not relayed and IsLocalTransportSender(sender)
            and Identity.TransportOwns(record.o or record.ownerKey, sender) then
            Sync.BroadcastDpsRecord(record)
        end
        -- The build a record names is relayed only when this client owns it.
        -- A receiver that relayed a held remote build after every accepted
        -- record made every peer resend the same complete build; a peer that
        -- lacks it asks for it through its own request instead.
        local buildId = record.b or record.buildId
        local build = buildId and CatalogGet(buildId)
        if build and LocalOwnsStoredBuild(build)
            and type(build.echoes) == "table" and #build.echoes > 0 then
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
    escapedLen=EscapedLen,
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
        -- The one declared release identity. No field is added to the packet.
        if Nexus and type(Nexus.ReleaseIdentity) == "function" then
            local ok, identity = pcall(Nexus.ReleaseIdentity)
            if ok and type(identity) == "table" and ValidVersion(identity.announce) then
                return identity.announce
            end
        end
        return (Nexus and Nexus.VERSION) or "0.0.0-dev"
    end,
    requestPlainVersion=function()
        -- The release version without build metadata (the form every peer
        -- has always parsed, as test.9027 sent it). Used only when the full
        -- request would exceed the transport limit.
        if Nexus and type(Nexus.ReleaseIdentity) == "function" then
            local ok, identity = pcall(Nexus.ReleaseIdentity)
            if ok and type(identity) == "table" and ValidVersion(identity.version)
                and not tostring(identity.version):find("+", 1, true) then
                return identity.version
            end
        end
        return nil
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
    -- Our locked-role capability, next to our own requests only.
    advertiseCapability=function(metadata, force)
        return Responder.AdvertiseCapability(metadata, force)
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
    rejectRecoveryOverflow=RejectRecoveryOverflow,
    isConnected=function() return Sync.IsConnected() end,
    isRequestChannelPresent=function()
        local index = FindSyncChannel()
        if not index then channelIndex = nil end
        return index ~= nil
    end,
    ensureChannel=function() return Sync.EnsureChannel() end,
    sendWhisper=function(message, target)
        -- The diagnostic probe whisper bypasses the queue and the wire, so it
        -- asks the saved Sync mode itself (refused under Off).
        local policy=Nexus.SyncModePolicy
        if policy then
            local allowed, why = policy.Allows("whisper")
            if not allowed then return false, why end
        end
        return SendChatMessage(message, "WHISPER", nil, target)
    end,
    syncMode=function()
        local policy=Nexus.SyncModePolicy
        return policy and policy.Mode() or "automatic"
    end,
    syncModeText=function(mode)
        local policy=Nexus.SyncModePolicy
        return policy and policy.Text(mode) or nil
    end,
})

function Sync.HandleIncoming(text, sender)
    -- Isolated: a failure of this passive read must never cost the message.
    pcall(Sync.NoteChannelTraffic)
    local accepted,reason=Inbound.HandleIncoming(text,sender)
    if accepted and Nexus.SyncWire then Nexus.SyncWire.ObservePeer(sender) end
    if accepted then pcall(Responder.NotePeerActivity, sender) end
    return accepted,reason
end

-- Called only after MainLifecycle admits CHAT_MSG_CHANNEL for wrbuildssync.
-- Task 037: the owner confirms that this current server's channel is realm-
-- local, with no cross-realm channels. Revisit this assumption if that changes.
-- Qualify only the game event's bare sender for full-build and DPS owner admission.
-- Keep the raw sender for diagnostics, peer/session state and other messages.
-- Unknown entry points and addon whispers never receive this authority.
function Sync.HandleNativeChannelIncoming(text, sender)
    if not Identity.ValidPlayer(sender) then return false end
    local channelOwnerSender
    if not sender:find("-", 1, true) then
        if type(text) == "string" and text:match("^WLD2|") then
            channelOwnerSender = Identity.NativeChannelSender(sender)
        else
            -- Full-build admission keeps its established context rules. This
            -- correction is bounded to native exact DPS evidence.
            local realm = GetNormalizedRealmName and GetNormalizedRealmName()
            if not realm or realm == "" then realm = GetRealmName and GetRealmName() end
            local owner = type(realm) == "string" and Identity.OwnerKey(sender, realm)
            local qualified = owner and not owner:match("@unknown$")
                and (sender .. "-" .. owner:match("@(.+)$")) or nil
            channelOwnerSender = qualified
                and Identity.CanonicalOwnerFromTransport(qualified) and qualified or nil
        end
        if not channelOwnerSender then return false end
    end
    pcall(Sync.NoteChannelTraffic)
    local accepted,reason=Inbound.HandleIncoming(text,sender,channelOwnerSender)
    if accepted and Nexus.SyncWire then Nexus.SyncWire.ObservePeer(sender) end
    if accepted then pcall(Responder.NotePeerActivity, sender) end
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
        pendingDeletes=0, -- MASTER-RC-019: no delete ever acquires retry ownership
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
    ExpireHotBuilds()
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

-- Attribution for a long update, at the owner that already has one.
--
-- The instrumented "sync.update" path wraps EVERY step below, so a large
-- maximum says one update was long and nothing about which step was long: the
-- admission drive's slice allowance covers only the preparation slices inside
-- Responder.Admission.Pump, while transport preparation, serialization,
-- inbound decoding and the view refresh sit outside it.
--
-- Measuring every step on every update would be its own cost, so the
-- phases are timed only AFTER an update was actually slow, for a bounded
-- window of updates. In the ordinary case this is two clock reads per update.
-- These are scalars for a support report, not a profiler and not a claim about
-- frames per second.
-- Held on the module table, not in a local: this chunk is already at the Lua
-- 5.1 limit for locals in one file.
Sync._phases = {thresholdMs = 50, window = 20, stats = {},
    armed = 0, slowUpdates = 0, lastTotal = nil, maxTotal = nil}

function Sync._phases.clock()
    if type(debugprofilestop) ~= "function" then return nil end
    local ok, value = pcall(debugprofilestop)
    if ok and type(value) == "number" then return value end
    return nil
end

function Sync._phases.record(name, started)
    if not started then return end
    local finished = Sync._phases.clock()
    if not finished then return end
    local elapsed = finished - started
    if elapsed < 0 then return end
    local row = Sync._phases.stats[name]
    if not row then row = {count=0, maxMs=0, lastMs=0}; Sync._phases.stats[name] = row end
    row.count = row.count + 1
    row.lastMs = elapsed
    if elapsed > row.maxMs then row.maxMs = elapsed end
end

-- name -> the phase's own maximum and last measurement, plus how many updates
-- crossed the slow threshold. Empty until an update was slow.
function Sync.PhaseStats()
    local phases = Sync._phases
    if type(phases) ~= "table" then return {phases={}} end
    local out = {slowUpdates=rawget(phases, "slowUpdates"), armed=rawget(phases, "armed"),
        thresholdMs=rawget(phases, "thresholdMs"), lastUpdateMs=rawget(phases, "lastTotal"),
        maxUpdateMs=rawget(phases, "maxTotal"), phases={}}
    local stats = rawget(phases, "stats")
    for name, row in pairs(type(stats) == "table" and stats or {}) do
        if type(row) == "table" then
            out.phases[name] = {count=rawget(row, "count"), maxMs=rawget(row, "maxMs"),
                lastMs=rawget(row, "lastMs")}
        end
    end
    return out
end

function Sync.ResetPhaseStats()
    local phases = Sync._phases
    if type(phases) ~= "table" then return false end
    rawset(phases, "stats", {})
    rawset(phases, "armed", 0)
    rawset(phases, "slowUpdates", 0)
    rawset(phases, "lastTotal", nil)
    rawset(phases, "maxTotal", nil)
    return true
end

-- The ordered steps of one update, built ONCE at load. Naming them in a table
-- instead of wrapping each call in a closure per update keeps the un-armed
-- path free of per-frame allocation: an ordinary update reads the clock twice
-- and calls these functions directly.
Sync._phases.steps = {
    {name = "admission.turn", run = function()
        Responder.Admission.NoteTurn()
        Responder.Admission.Expire()
        Inbound.CleanExpired()
        ExpireHotBuilds()
    end},
    {name = "responses", run = function(elapsed) ProcessPendingResponses(elapsed) end},
    {name = "recovery", run = function(elapsed) Session.PumpRecovery(elapsed) end},
    {name = "share", run = function(elapsed) PumpPendingShare(elapsed) end,
        skip = function() return Sync._pendingShareScheduled end},
    {name = "transport.prepare", run = function() Session.PrepareTransport() end},
    {name = "handshake", run = function()
        if Nexus.SyncWire then Nexus.SyncWire.PumpHandshake() end
    end},
    {name = "transport.pump", run = function(elapsed) Transport.Pump(elapsed) end},
    {name = "status.reply", run = function()
        if Sync.FlushStatusReply then Sync.FlushStatusReply() end
    end},
    {name = "auto.sync", run = function(elapsed)
        Session.UpdateAutoSync(elapsed)
        Session.UpdateAutoConvergence()
        Session.UpdateJoinRetry(elapsed)
    end},
    -- After the request, response and transport turn above, never before it.
    {name = "admission.pump", run = function() Responder.Admission.Pump() end},
    -- A refresh can initiate legacy catalog repair. Release it only after
    -- the already-ready update, not before its transport validation work.
    {name = "view.refresh", run = function() pcall(Sync.RequestDataViewRefresh) end,
        skip = function()
            if not Operation.housekeepingRefreshPending then return true end
            Operation.housekeepingRefreshPending = false
            return false
        end},
}

-- Kept beside the table, so a replaced Sync._phases cannot take the steps with
-- it: the update still runs every step in order.
Sync._defaultSteps = Sync._phases.steps

function Sync.OnUpdate(elapsed)
    -- The phase state lives on the module table because this chunk is at the
    -- Lua 5.1 local limit, which makes it writable from outside. Measurement
    -- must never be able to stop the update, so it is read defensively once
    -- and skipped entirely if anything replaced it.
    -- Every field of that table is read with rawget and written with rawset,
    -- so a metatable on it cannot raise on the guard line and stop all sync.
    local phases = Sync._phases
    if type(phases) ~= "table" or type(rawget(phases, "clock")) ~= "function"
        or type(rawget(phases, "record")) ~= "function" then
        phases = nil
    end
    -- The steps ARE the update, so they are never taken from the measurement
    -- table while the list built at load is intact: emptying, replacing or
    -- decoying Sync._phases.steps changes nothing. The copy there is read only
    -- if the load-time list itself was lost.
    -- STATED LIMIT, not a protection claim: both references are fields of the
    -- module table, so whichever is read first wins, and whatever replaces
    -- Sync._defaultSteps replaces the work. The list cannot be held in an
    -- upvalue instead: this chunk is AT the Lua 5.1 limit of 200 locals in one
    -- function, and even a block-scoped local here fails to compile
    -- ("core/Sync.lua: main function has more than 200 local variables").
    -- What is closed is the measurement path; an addon that overwrites another
    -- addon's module fields can stop that addon, and always could.
    local steps = Sync._defaultSteps
    if type(steps) ~= "table" or #steps == 0 then
        steps = phases and rawget(phases, "steps") or nil
        if type(steps) ~= "table" then steps = nil end
    end
    -- Every clock and record call goes through pcall: a raising clock is a
    -- measurement failure, and a measurement failure must never be a sync
    -- failure. One raise disables measurement for this update and no more.
    local function readClock()
        if not phases then return nil end
        local ok, value = pcall(rawget(phases, "clock"))
        if ok and type(value) == "number" then return value end
        phases = nil
        return nil
    end
    local updateStarted = readClock()
    local detail = phases and (tonumber(rawget(phases, "armed")) or 0) > 0
        and updateStarted ~= nil
    for index = 1, steps and #steps or 0 do
        -- rawget on the LIST too, not only on the entry: `#` ignores __len in
        -- Lua 5.1, so a list with a hole below its length reaches __index, and
        -- a raising one there would raise out of the update on every frame.
        local entry = rawget(steps, index)
        -- rawget for the same reason as the phase table: a step entry carrying
        -- a metatable must not raise on the guard line and stop every step
        -- after it. Its `run` is called directly, so a failing step is still a
        -- real failure of that step and reaches the owner isolation.
        local run = type(entry) == "table" and rawget(entry, "run") or nil
        if type(run) == "function" then
            local skipped = false
            local skip = rawget(entry, "skip")
            if type(skip) == "function" then
                local okSkip, result = pcall(skip)
                skipped = okSkip and result and true or false
            end
            if not skipped then
                local started = detail and readClock() or nil
                run(elapsed)
                if started and phases then
                    pcall(rawget(phases, "record"), rawget(entry, "name"), started)
                end
            end
        end
    end
    if phases and updateStarted then
        local finished = readClock()
        if finished then
            local total = finished - updateStarted
            local threshold = tonumber(rawget(phases, "thresholdMs")) or 50
            if total >= 0 then
                rawset(phases, "lastTotal", total)
                local highest = tonumber(rawget(phases, "maxTotal"))
                if not highest or total > highest then
                    rawset(phases, "maxTotal", total)
                end
                if total >= threshold then
                    rawset(phases, "slowUpdates",
                        (tonumber(rawget(phases, "slowUpdates")) or 0) + 1)
                    rawset(phases, "armed", tonumber(rawget(phases, "window")) or 20)
                else
                    local armed = tonumber(rawget(phases, "armed")) or 0
                    if armed > 0 then rawset(phases, "armed", armed - 1) end
                end
            end
        end
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
    Responder.Admission.Reset()
    Inbound.Reset()
    Session.Reset()
    Compatibility.Reset()
    Reconciler.Reset()
    if Nexus.SyncModePolicy then
        Nexus.SyncModePolicy.Reset()
        Nexus.SyncModePolicy.Bind(Session.ManualGrant, MyName)
    end
    preparedDpsProofs = setmetatable({}, {__mode="k"})
    hotBuilds = {}  -- clear on init
    hotBuildCheckedAt = 0
    Responder.state.hotBuildGeneration =
        (Responder.state.hotBuildGeneration or 0) + 1
    EnsureHotBuildEvidenceProvider()
    pendingShare = nil
    pendingShareTicker = 0
    Operation.active, Operation.activeShares, Operation.activeDeletes = {}, {}, {}
    Sync._pendingShareScheduled = false
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
    -- Sync never binds the raw SavedVariables tombstone table.
    Operation.deleteDiscoveryComplete = true
    -- The retained Share's once-per-second local-save retry runs from the
    -- scheduler, so it progresses while the full update turn is withheld
    -- (catalog or hashes not ready); the update turn then skips it.
    local scheduler = Nexus and Nexus.Scheduler
    if scheduler and scheduler.IsInitialized and scheduler.IsInitialized()
        and type(scheduler.Every) == "function" then
        local scheduled = scheduler.Every("sync.pending-share", 1, function()
            PumpPendingShare(1)
        end)
        Sync._pendingShareScheduled = scheduled == true
    end
    Transport.InstallFilters()
    Sync.EnsureChannel()
end
