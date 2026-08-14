-- Nexus: core/Sync.lua v2.1
-- Peer-to-peer sharing for Nexus Builds.
--
-- Automatic mode starts a slow convergence sync while the character is resting
-- and gameplay is safe. Off performs no transport work; Manual starts only from
-- an explicit user request. Exact Echo lists are included in sync responses.
--
-- Posting/editing shares immediately only during an active safe transport
-- session. Otherwise the durable row is included in the next allowed sync.
--
-- WIRE PROTOCOL (| separated; pipe escaped to || on send):
--   WLRQ|<sender>|<buildhash>|<dpshash>|<requestId> -- state request
--     buildhash is 8 delta buckets plus a bundled-catalog token on current
--     releases; legacy 8-bucket hashes retain full-catalog recovery.
--   WLRC|<sender>|<requester>|<requestId>|<buildhash>|<dpshash> -- claim
--   WLRB|<sender>|<id>|<m>|<idx>/<total>|<b64>  -- build chunk
--   WLRD|<sender>|<id>|<stamp>                   -- delete notification
--
-- PAYLOAD FORMAT (compact, ~65% smaller than verbose):
--   { id, t=title, a=author, c=class, m=lastModified,
--     d=description(omitted if empty), e=[[spellId,quality,stacks],...] }
--
-- ANTI-SPAM:
--   • Conservative paced queued sends; full loadouts sync in-band
--   • Eight build and DPS hash buckets: resend only changed subsets
--   • Responder claims: identical peers elect one sender; unique peers contribute
--   • 2s answer spacing between completed peer responses
--   • Hot-build window (120s): a build posted while no peer is listening
--     is still included in the next BroadcastMine so the peer catches it
--     on their next Sync Now
--   • Max 999 chunks per build (enforced before queuing)

Nexus = Nexus or {}
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
local CODE_CLAIM      = "WLRC" -- legacy whole-state responder claim
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
local MAX_HASH_BYTES = 192
local MAX_VERSION_BYTES = 32
local MAX_INFLIGHT_GLOBAL = 24
local MAX_INFLIGHT_PER_SENDER = 4
local MAX_OUTBOUND_QUEUE = 8192
local MAX_CONTROL_QUEUE = 512
local MAX_RECOVERY_QUEUE = 512
local MAX_PENDING_RESPONSES = 128
local MAX_PENDING_LOADOUTS = 128
local MAX_KNOWN_PEERS = 512
local SEND_INTERVAL   = 1.10   -- conservative channel pacing; avoids server chat spam/mutes
local RECEIVE_WINDOW  = 60     -- compatibility/status timer inside an allowed session
local INFLIGHT_GRACE  = 30     -- seconds to finish an interrupted chunk transfer
local INFLIGHT_MAX_AGE = 300   -- absolute cap even if duplicate chunks keep arriving
local REQUEST_COOLDOWN = 6     -- min seconds between our own Sync Now presses
local ANSWER_COOLDOWN  = 2     -- minimum gap between completed peer responses
local CLAIM_DELAY_MIN  = 0.35  -- deterministic responder-election delay
local CLAIM_DELAY_MAX  = 1.75
local BUCKET_CLAIM_MAX = 5.50 -- wide deterministic window lets different peers win different buckets
local HOT_WINDOW       = 120   -- seconds a just-posted build is re-included in answers
local JOIN_RETRY_INTERVAL = 10
local JOIN_MAX_ATTEMPTS   = 30
local THROTTLE_PAUSE      = 8     -- pause all Nexus transport after a server throttle notice
local THROTTLE_SLOW_TIME  = 45    -- temporarily use extra-safe pacing after a throttle
local AUTO_SYNC_DELAY      = 6
local AUTO_SYNC_MIN_PASS    = 60  -- allow throttled peers time to begin/drain large responses
local AUTO_SYNC_QUIET       = 15  -- require a real quiet period before judging a pass stable
local AUTO_SYNC_MAX_PASSES  = 0   -- retained for diagnostics; convergence now ends only when stable
local PENDING_TTL           = 30  -- inactivity cap for pending response work
local PENDING_MAX_AGE       = 300 -- absolute cap even while backpressured
local RESPONSE_QUEUE_HEADROOM = 8 -- do no response preparation near saturation
local MAX_FUTURE_SKEW = 300 -- tolerate ordinary clock skew, reject poisoned epochs

------------------------------------------------------------------------
-- Module state
------------------------------------------------------------------------

local Codec, Adapter
local channelIndex
local sendQueue      = {}
local sendQueueHead  = 1
local sendQueueTail  = 0
local controlQueue   = {} -- tiny election/control packets; always drain before bulk chunks
local controlQueueHead = 1
local controlQueueTail = 0
local inflight       = {}
local dpsInflight    = {}   -- "sender:id" -> { chunks, total, t0, lastMod }
local seenRemoteIds  = {}   -- id -> lastModified we already hold
local tombstones     = {}   -- id -> stamp; never resurrect
local hotBuilds      = {}   -- id -> { build, t }; recently posted, include in answers
local ticker         = 0
local throttlePauseUntil = 0
local throttleSlowUntil  = 0
local lastTransportAttempt = -math.huge
local transportFilterInstalled = false
local joinRetryTicker = 0
local joinAttempts   = 0
local receiveWindowUntil = 0
local lastRequestAt  = -math.huge
local lastAnsweredAt = -math.huge
local pendingResponses = {} -- requester:requestId -> deferred response candidate
local pendingLoadouts = {}  -- requester:buildId -> staggered on-demand response
local pendingDeletes = {}   -- local tombstone ids awaiting direct notification
local pendingDeleteTicker = 0
local requestedLoadouts = {} -- buildId -> last recovery request time
local legacyRecoveryQueue = {} -- incomplete summaries learned from older peers
local legacyRecoveryHead = 1
local legacyRecoveryTail = 0
local legacyRecoveryTicker = 0
local lastSyncNewCount = 0
local autoSyncPending = false
local autoSyncElapsed = 0
local autoConverge = { active=false, pass=0, stable=0, started=0, lastInbound=0, buildHash=nil, dpsHash=nil }
local manualSessionActive = false
local suspendReason = nil
local pendingStatusReply = nil
local Now, MyName
local knownPeers = {} -- normalized player name -> { name, version, lastSeen }
local CleanExpiredInflight
local recentBuildBroadcast = {}
local BUILD_BROADCAST_DEDUPE = 2
local Responder = {
    fairCursor=nil,
    candidateCache=nil,
    stats={
        turns=0, workUnits=0, backpressureDeferrals=0,
        entryPreparations=0, candidateSnapshots=0, candidateSorts=0,
        buildSerializations=0, buildAdmissions=0, dpsSerializations=0,
        chunkMessagesBuilt=0, compatRequests=0,
    },
}

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

local function CatalogDelta()
    local catalog = Catalog()
    return catalog and catalog.DeltaSnapshot and catalog.DeltaSnapshot() or {}
end

local function CatalogVersion()
    local catalog = Catalog()
    return catalog and catalog.CatalogVersion
        and catalog.CatalogVersion() or "unversioned"
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

function Sync._RequestRetention(reason)
    local retention = Nexus and Nexus.DataRetention
    if retention and type(retention.Request) == "function" then
        pcall(retention.Request, reason)
    end
end

function Sync._AllowsRemoteRevision(author, stamp, buildId)
    local retention = Nexus and Nexus.DataRetention
    if not (retention and type(retention.AllowsRemoteRevision) == "function") then
        return true
    end
    local ok, allowed = pcall(retention.AllowsRemoteRevision,
        author, stamp, NexusDB, buildId)
    return not ok or allowed ~= false
end

local function NormalizePeerName(name)
    name = tostring(name or ""):gsub("%s+", "")
    name = name:match("^([^%-]+)") or name
    return name:lower()
end

local function SamePeer(a, b)
    local ak = NormalizePeerName(a)
    local bk = NormalizePeerName(b)
    return ak ~= "" and ak == bk
end

local function OwnerKeyMatchesAuthor(ownerKey, author)
    if ownerKey == nil then return true end
    if type(ownerKey) ~= "string" or #ownerKey > 160
        or ownerKey:find("[%c|]") then return false end
    local ownerName, realm = ownerKey:match("^([^@]+)@([^@]+)$")
    return ownerName ~= nil and realm ~= nil and SamePeer(ownerName, author)
end

local function TransferCount(map, sender)
    local total, perSender = 0, 0
    local senderKey = NormalizePeerName(sender)
    for _, entry in pairs(map) do
        total = total + 1
        if NormalizePeerName(entry.sender) == senderKey then
            perSender = perSender + 1
        end
    end
    return total, perSender
end

local function CanStartTransfer(map, sender)
    local buildTotal, buildSender = TransferCount(inflight, sender)
    local dpsTotal, dpsSender = TransferCount(dpsInflight, sender)
    return (buildTotal + dpsTotal) < MAX_INFLIGHT_GLOBAL
        and (buildSender + dpsSender) < MAX_INFLIGHT_PER_SENDER
end

local function BumpSync(reason)
    local revisions = Nexus and Nexus.Revisions
    if revisions and type(revisions.Advance) == "function" then
        pcall(revisions.Advance, revisions.SYNC_CHANGED, reason)
    end
end

local function MarkPeer(name, version)
    if not name or name == "" then return false end
    local me = MyName and MyName() or ""
    if NormalizePeerName(name) == NormalizePeerName(me) then return false end
    local key = NormalizePeerName(name)
    if key == "" then return false end
    local now = Now and Now() or ((GetTime and GetTime()) or 0)
    if not knownPeers[key] then
        local count = 0
        for peerKey, peer in pairs(knownPeers) do
            if now - (tonumber(peer.lastSeen) or 0) > 7200 then
                knownPeers[peerKey] = nil
            else
                count = count + 1
            end
        end
        if count >= MAX_KNOWN_PEERS then return false end
    end
    local wasKnown = knownPeers[key] ~= nil
    local peer = knownPeers[key] or {}
    local oldName, oldVersion = peer.name, peer.version
    peer.name = tostring(name):match("^([^%-]+)") or tostring(name)
    if version and version ~= "" then peer.version = tostring(version) end
    peer.lastSeen = now
    knownPeers[key] = peer
    if not wasKnown or oldName ~= peer.name or oldVersion ~= peer.version then
        BumpSync(not wasKnown and "peer added" or "peer identity updated")
    end
    return true
end

local function SameTransportSender(declared, actual)
    local declaredText = tostring(declared or ""):gsub("%s+", ""):lower()
    local actualText = tostring(actual or ""):gsub("%s+", ""):lower()
    if declaredText:find("-", 1, true)
        and actualText:find("-", 1, true) then
        return declaredText == actualText
    end
    -- Current wire senders use UnitName("player") without a realm. Preserve
    -- that legacy form while requiring exact realms when both sides carry one.
    return SamePeer(declaredText, actualText)
end

function Sync.GetPeerInfo(name)
    local peer = knownPeers[NormalizePeerName(name)]
    if not peer then return nil end
    local now = Now and Now() or ((GetTime and GetTime()) or 0)
    if peer.lastSeen and now - peer.lastSeen > 7200 then return nil end
    return peer
end

function Sync.IsKnownPeer(name) return Sync.GetPeerInfo(name) ~= nil end

local stats = {
    sent=0, received=0, duplicatesSkipped=0,
    malformedRejected=0, ignoredOutsideWindow=0,
    oversizeDropped=0, updated=0, skippedUpToDate=0,
    queueOverflowRejected=0, pendingOverflowRejected=0,
    baselineSkipped=0, overlaySent=0,
}

function Sync.WorkState()
    local buildCount, buildBytes, dpsCount, dpsBytes = 0, 0, 0, 0
    local pendingResponseCount, pendingLoadoutCount, pendingDeleteCount = 0, 0, 0
    local peerCount = 0
    for _, entry in pairs(inflight) do
        buildCount = buildCount + 1
        buildBytes = buildBytes + (tonumber(entry.bytes) or 0)
    end
    for _, entry in pairs(dpsInflight) do
        dpsCount = dpsCount + 1
        dpsBytes = dpsBytes + (tonumber(entry.bytes) or 0)
    end
    for _ in pairs(pendingResponses) do
        pendingResponseCount = pendingResponseCount + 1
    end
    for _ in pairs(pendingLoadouts) do
        pendingLoadoutCount = pendingLoadoutCount + 1
    end
    for id in pairs(pendingDeletes) do
        local tomb = tombstones and tombstones[id]
        local author = type(tomb) == "table" and tostring(tomb.author or "") or ""
        if tomb and SamePeer(author, MyName()) then
            pendingDeleteCount = pendingDeleteCount + 1
        end
    end
    for _ in pairs(knownPeers) do peerCount = peerCount + 1 end
    local sending = math.max(0, sendQueueTail - sendQueueHead + 1)
    local control = math.max(0, controlQueueTail - controlQueueHead + 1)
    local recovery = math.max(0, legacyRecoveryTail - legacyRecoveryHead + 1)
    return {
        buildInflight=buildCount, buildBytes=buildBytes,
        dpsInflight=dpsCount, dpsBytes=dpsBytes,
        maxGlobal=MAX_INFLIGHT_GLOBAL, maxPerSender=MAX_INFLIGHT_PER_SENDER,
        maxEncodedBytes=MAX_ENCODED_BYTES,
        sending=sending, control=control, outbound=sending + control,
        recovery=recovery,
        pendingResponses=pendingResponseCount,
        pendingLoadouts=pendingLoadoutCount,
        pendingDeletes=pendingDeleteCount,
        manualPublishing=Responder.manualPublish ~= nil,
        knownPeers=peerCount,
        maxOutboundQueue=MAX_OUTBOUND_QUEUE,
        maxControlQueue=MAX_CONTROL_QUEUE,
        maxRecoveryQueue=MAX_RECOVERY_QUEUE,
        maxPendingResponses=MAX_PENDING_RESPONSES,
        maxPendingLoadouts=MAX_PENDING_LOADOUTS,
        maxKnownPeers=MAX_KNOWN_PEERS,
        responseHeadroom=RESPONSE_QUEUE_HEADROOM,
    }
end

function Sync.ResponseStats()
    local out = {}
    for key, value in pairs(Responder.stats) do out[key] = value end
    return out
end

------------------------------------------------------------------------
-- Diagnostic log
------------------------------------------------------------------------

local LogEvent
do
    local DiagnosticHistory = Nexus.DiagnosticHistory
    if not (DiagnosticHistory and type(DiagnosticHistory.New) == "function") then
        error("Nexus DiagnosticHistory must load before Sync")
    end
    local LOG_CAP, LOG_TRIM_AT, LOG_TEXT_BYTES = 160, 200, 2048
    local eventHistory = DiagnosticHistory.New({
        cap=LOG_CAP, trimAt=LOG_TRIM_AT, maxTextBytes=LOG_TEXT_BYTES,
    })
    local logSeq = 0

    LogEvent = function(cat, fmt, ...)
        logSeq = logSeq + 1
        local stamp = 0
        if GetTime then
            local okTime, current = pcall(GetTime)
            if okTime and type(current) == "number" then stamp = current end
        end
        eventHistory.Append({
            seq=logSeq,
            t=stamp,
            cat=DiagnosticHistory.SafeText(cat, 32),
            text=DiagnosticHistory.Format(LOG_TEXT_BYTES, fmt, ...),
        })
    end
    Sync.LogEvent = LogEvent
    function Sync.EventLog() return eventHistory.Snapshot() end
    function Sync.ClearLog() eventHistory.Clear(); logSeq = 0 end
    function Sync.LogRaw(e)
        LogEvent("RX", "%s", DiagnosticHistory.SafeText(e, LOG_TEXT_BYTES))
    end
    function Sync.RawLog() return eventHistory.Snapshot() end
    function Sync.LogStats() return eventHistory.Stats() end
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

Now = function() return (GetTime and GetTime()) or 0 end
MyName = function() return (UnitName and UnitName("player")) or "?" end

function Sync.Mode()
    local policy = Nexus and Nexus.SyncPolicy
    return policy and type(policy.Mode) == "function"
        and policy.Mode() or "automatic"
end

function Sync._TransportAllowed()
    local policy = Nexus and Nexus.SyncPolicy
    if not (policy and type(policy.Allows) == "function") then return true end
    return policy.Allows(manualSessionActive)
end

function Sync._LeaveChannel(reason)
    local wasConnected = channelIndex ~= nil
    if type(LeaveChannelByName) == "function" then
        pcall(LeaveChannelByName, SYNC_CHANNEL)
    end
    channelIndex = nil
    if wasConnected and LogEvent then
        LogEvent("CHAN", "transport inactive: %s", tostring(reason or "policy"))
    end
end

function Sync._Suspend(reason)
    suspendReason = tostring(reason or "suspended")
    sendQueue, sendQueueHead, sendQueueTail = {}, 1, 0
    controlQueue, controlQueueHead, controlQueueTail = {}, 1, 0
    inflight, dpsInflight = {}, {}
    pendingResponses, pendingLoadouts = {}, {}
    legacyRecoveryQueue, legacyRecoveryHead, legacyRecoveryTail = {}, 1, 0
    Responder.manualPublish = nil
    receiveWindowUntil = 0
    autoConverge.active = false
    pendingStatusReply = nil
    if Sync.Mode() == "automatic" then
        autoSyncPending, autoSyncElapsed = true, 0
    else
        autoSyncPending = false
        manualSessionActive = false
    end
    Sync._LeaveChannel(suspendReason)
    return false, suspendReason
end

local function EscapedLen(s)
    return #s + select(2, s:gsub("|", ""))
end

local function FiniteNumber(value)
    return type(value) == "number" and value == value
        and value < math.huge and value > -math.huge
end

function Sync._WallNow()
    if type(time) ~= "function" then return 0 end
    local ok, value = pcall(time)
    value = ok and tonumber(value) or 0
    return FiniteNumber(value) and value > 0 and value or 0
end

function Sync._ValidRemoteEpoch(value, minimum)
    value = tonumber(value)
    if not FiniteNumber(value) or value < (minimum or 0) then return false end
    local now = Sync._WallNow()
    return now <= 1000000000 or value <= now + MAX_FUTURE_SKEW
end

local function ValidText(value, maxBytes, allowEmpty)
    return type(value) == "string"
        and (allowEmpty or value ~= "")
        and #value <= maxBytes
        and not value:find("[%c]")
end

local function ValidField(value, maxBytes, allowEmpty)
    return ValidText(value, maxBytes, allowEmpty)
        and not value:find("|", 1, true)
end

local function ValidIdentifier(value, maxBytes)
    return ValidField(value, maxBytes, false)
        and value:match("^[%w%._:@%+%-]+$") ~= nil
end

local function ValidTransferIdentifier(value)
    -- Transfer IDs embed a player name, and valid WoW names may contain
    -- non-ASCII UTF-8 bytes. Keep the wire delimiter/control protections
    -- without applying the ASCII-oriented identifier character class.
    return ValidField(value, MAX_TRANSFER_ID_BYTES, false)
        and not value:find("%s")
end

local function ValidPeerName(value)
    return ValidField(value, 80, false)
        and not value:find("%s")
end

local function ValidHash(value)
    return ValidField(value, MAX_HASH_BYTES, false)
        and value:match("^[%x,]+$") ~= nil
end

local function ValidVersion(value)
    if not ValidField(value, MAX_VERSION_BYTES, false)
        or value:match("^[%w%.%+%-]+$") == nil then return false end
    local parser = Nexus and Nexus.Version and Nexus.Version.Parse
    if type(parser) ~= "function" then return false end
    local ok, parsed = pcall(parser, value)
    return ok and parsed ~= nil
end

local function ValidIntegerText(value, minimum)
    if not ValidField(value, 24, false)
        or value:match("^%-?%d+$") == nil then return false end
    local number = tonumber(value)
    return FiniteNumber(number) and number == math.floor(number)
        and number >= (minimum or 0)
end

local function TableCount(value)
    local count = 0
    for _ in pairs(value or {}) do count = count + 1 end
    return count
end

-- djb2 hash of the caller's library so peers can skip sends when already
-- up to date. Input: { [id] = { lastModified=N }, ... }
local BUILD_BUCKETS = 8
local function BuildBucket(id)
    local text = tostring(id or "")
    local h = 5381
    for i = 1, #text do h = ((h * 33) + text:byte(i)) % 2147483648 end
    return (h % BUILD_BUCKETS) + 1
end

local function SplitHashes(value)
    local out = {}
    local i = 1
    for part in tostring(value or ""):gmatch("([^,]+)") do out[i] = part; i = i + 1 end
    return out
end

local function TombStamp(value)
    if type(value) == "table" then return tonumber(value.stamp) or 0 end
    return tonumber(value) or 0
end

local function TombAuthor(value)
    return type(value) == "table" and tostring(value.author or "") or ""
end

local function BucketContainsTombstone(bucket)
    for id in pairs(tombstones or {}) do
        if BuildBucket(id) == bucket then return true end
    end
    return false
end

local function LibraryHash(builds, tombstoneSource)
    local buckets = {}
    for i = 1, BUILD_BUCKETS do buckets[i] = {} end
    for id, b in pairs(builds or {}) do
        local bucket = BuildBucket(id)
        local complete = (type(b.echoes) == "table" and #b.echoes > 0) and "F" or "S"
        local fp = tostring(b.fingerprintHash or b.fingerprint or "0")
        buckets[bucket][#buckets[bucket]+1] = id..":"..tostring(b.lastModified or b.postedAt or 0)..":"..complete..":"..fp
    end
    for id, tomb in pairs(tombstoneSource or tombstones or {}) do
        local bucket = BuildBucket(id)
        buckets[bucket][#buckets[bucket]+1] = "!"..id..":"..tostring(TombStamp(tomb))..":"..TombAuthor(tomb)
    end
    local hashes = {}
    for bucket = 1, BUILD_BUCKETS do
        table.sort(buckets[bucket])
        local h = 5381
        for _, text in ipairs(buckets[bucket]) do
            for i = 1, #text do h = ((h * 33) + text:byte(i)) % 2147483648 end
        end
        hashes[bucket] = #buckets[bucket] > 0 and string.format("%x", h) or "0"
    end
    return table.concat(hashes, ",")
end

local function CatalogToken()
    local text = tostring(CatalogVersion())
    local encoded = {}
    for i = 1, #text do
        encoded[i] = string.format("%02x", text:byte(i))
    end
    return table.concat(encoded)
end

local function DeltaBuildHash()
    local cache = Nexus and Nexus.BuildHashCache
    return cache and cache.Delta and cache.Delta()
        or LibraryHash(CatalogDelta())
end

local function LegacyBuildHash()
    local cache = Nexus and Nexus.BuildHashCache
    return cache and cache.Legacy and cache.Legacy()
        or LibraryHash(CatalogAll())
end

local function CurrentBuildHash()
    return DeltaBuildHash() .. "," .. CatalogToken()
end

local function CurrentDpsHash()
    local D = Nexus.DpsCapture
    if D and D.GetSyncHash then
        local ok, value = pcall(D.GetSyncHash)
        if ok and value then return tostring(value) end
    end
    return "0"
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
    local canonicalTombstones = tombstones
    local catalog = Catalog()
    if catalog and type(catalog.TombstoneSnapshot) == "function" then
        local ok, snapshot = pcall(catalog.TombstoneSnapshot)
        if ok and type(snapshot) == "table" then canonicalTombstones = snapshot end
    end
    return LibraryHash(CatalogDelta(), canonicalTombstones) .. "," .. CatalogToken(),
        LibraryHash(CatalogAll(), canonicalTombstones)
end

function Sync.GetLegacyBuildHash()
    return LegacyBuildHash()
end

function Sync.HashCacheStats()
    local cache = Nexus and Nexus.BuildHashCache
    return cache and cache.Stats and cache.Stats() or {available=false}
end

local function StableDelay(text)
    local h = 5381
    text = tostring(text or "")
    for i = 1, #text do h = ((h * 33) + text:byte(i)) % 1000003 end
    local span = CLAIM_DELAY_MAX - CLAIM_DELAY_MIN
    return CLAIM_DELAY_MIN + (h % 1000) / 999 * span
end

-- Compact payload: short field names + echo arrays instead of objects.
-- Cuts a 69-echo build from ~4100 bytes b64 down to ~1400 bytes b64
-- (8 chunks instead of 23).
local function CompactEncode(build)
    local e = {}
    for _, echo in ipairs(build.echoes or {}) do
        -- 4th array slot is optional and omitted for ordinary Echoes (a Lua
        -- table constructor with a trailing nil is indistinguishable from
        -- one without it -- #e stays 3), so this is byte-for-byte identical
        -- to the old wire shape for every build that has no locked Echoes,
        -- and an older Nexus peer decoding a build that does simply never
        -- looks at index 4 and is unaffected.
        e[#e+1] = { tonumber(echo.spellId), tonumber(echo.quality) or 0,
                    math.max(1, tonumber(echo.stacks) or 1), echo.locked and 1 or nil }
    end
    return {
        id = build.id,
        t  = build.title,
        a  = build.author,
        o  = build.ownerKey,
        c  = build.class,
        m  = tonumber(build.lastModified) or tonumber(build.postedAt) or 0,
        d  = (type(build.description) == "string" and build.description ~= "")
             and build.description or nil,
        e  = e,
        x  = build.autoDps and 1 or nil,
        -- build link URL (optional; admin-set reference to external page)
        lk = (type(build.link) == "string" and build.link ~= "") and build.link or nil,
    }
end

-- Reverse compact -> standard shape (used on receive)
local function CompactDecode(data)
    if type(data) ~= "table" then return nil end
    -- Support both compact (t/a/c/m/e) and legacy verbose (title/author/...)
    local title  = data.t or data.title
    local author = data.a or data.author
    local ownerKey = data.o or data.ownerKey
    local class  = data.c or data.class
    local lastMod = tonumber(data.m or data.lastModified or data.postedAt) or 0
    local postedAt = tonumber(data.postedAt) or lastMod
    local rawE   = data.e or data.echoes
    if not (ValidIdentifier(data.id, MAX_BUILD_ID_BYTES)
        and type(title) == "string" and title ~= ""
        and type(author) == "string" and ValidPeerName(author)
        and type(rawE) == "table" and #rawE <= MAX_BUILD_ECHOES) then
        return nil
    end
    if not Sync._ValidRemoteEpoch(lastMod, 0)
        or not Sync._ValidRemoteEpoch(postedAt, 0) then return nil end
    if not OwnerKeyMatchesAuthor(ownerKey, author) then return nil end
    local echoes = {}
    for _, e in ipairs(rawE) do
        local spellId, quality, stacks, locked
        if type(e) == "table" then
            -- compact array form [spellId, quality, stacks, locked(optional)]
            if e[1] then
                spellId = tonumber(e[1])
                quality = tonumber(e[2]) or 0
                stacks  = math.max(1, tonumber(e[3]) or 1)
                locked  = (e[4] == 1) or nil
            else
                -- verbose object form (legacy)
                spellId = tonumber(e.spellId)
                quality = tonumber(e.quality) or 0
                stacks  = math.max(1, tonumber(e.stacks) or 1)
                locked  = e.locked and true or nil
            end
        end
        if spellId and spellId > 0 then
            echoes[#echoes+1] = { spellId=spellId, quality=quality, stacks=stacks, locked=locked }
        end
    end
    if #echoes == 0 then return nil end
    return {
        id          = tostring(data.id),
        title       = tostring(title):sub(1, 120),
        author      = type(author) == "string" and author:sub(1, 80) or "Unknown",
        ownerKey    = type(ownerKey) == "string" and ownerKey:lower() or nil,
        class       = type(class) == "string" and class or nil,
        description = type(data.d or data.description) == "string"
                      and (data.d or data.description):sub(1, 4000) or "",
        lastModified = lastMod,
        postedAt     = postedAt,
        echoes       = echoes,
        autoDps      = data.x == 1 or data.autoDps == true,
        link         = (type(data.lk) == "string" and data.lk ~= "") and data.lk or nil,
    }
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
    local allowed, why = Sync._TransportAllowed()
    if not allowed then
        channelIndex = nil
        return false, why
    end
    local idx = FindSyncChannel()
    if idx then
        if channelIndex ~= idx then
            LogEvent("CHAN","already in '%s' at index %d", SYNC_CHANNEL, idx)
        end
        channelIndex = idx; return true
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

local function ResolveSendChannel()
    local allowed = Sync._TransportAllowed()
    if not allowed then return nil end
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

------------------------------------------------------------------------
-- Receive window
------------------------------------------------------------------------

function Sync.IsReceiving()       return Now() < receiveWindowUntil end
function Sync.ReceiveTimeLeft()
    local l = receiveWindowUntil - Now(); return l > 0 and l or 0
end
function Sync.LastSyncNewCount()  return lastSyncNewCount end

------------------------------------------------------------------------
-- Send queue (rate-limited, anti-spam)
------------------------------------------------------------------------

local function QueueDepth(head, tail)
    return math.max(0, (tonumber(tail) or 0) - (tonumber(head) or 1) + 1)
end

function Responder.BulkFree()
    return math.max(0, MAX_OUTBOUND_QUEUE
        - QueueDepth(sendQueueHead, sendQueueTail))
end

function Responder.Backpressured()
    return Responder.BulkFree() < RESPONSE_QUEUE_HEADROOM
end

function Responder.CanAdmit(count)
    return tonumber(count) ~= nil and count >= 1
        and count <= Responder.BulkFree()
end

local function ValidateQueuedPayload(payload)
    if type(payload) ~= "string" or payload == "" then return false end
    if EscapedLen(payload) > CHAT_LIMIT then
        stats.oversizeDropped = (stats.oversizeDropped or 0) + 1
        LogEvent("TX", "REJECT oversize queued msg (%d>%d): %s",
            EscapedLen(payload), CHAT_LIMIT, payload:sub(1, 40))
        return false
    end
    return true
end

local function RejectQueueOverflow(kind, need, depth, cap)
    stats.queueOverflowRejected = (stats.queueOverflowRejected or 0) + 1
    LogEvent("TX", "REJECT newest %s packet(s): queue full (%d+%d>%d)",
        tostring(kind), tonumber(depth) or 0, tonumber(need) or 1,
        tonumber(cap) or 0)
    return false, "sync queue full"
end

local function Enqueue(payload)
    local allowed, why = Sync._TransportAllowed()
    if not allowed then return false, why end
    if not ValidateQueuedPayload(payload) then return false, "invalid packet" end
    local depth = QueueDepth(sendQueueHead, sendQueueTail)
    if depth >= MAX_OUTBOUND_QUEUE then
        return RejectQueueOverflow("bulk", 1, depth, MAX_OUTBOUND_QUEUE)
    end
    sendQueueTail = sendQueueTail + 1
    sendQueue[sendQueueTail] = payload
    return true
end

local function EnqueueBatch(payloads)
    local allowed, why = Sync._TransportAllowed()
    if not allowed then return false, why end
    if type(payloads) ~= "table" or #payloads == 0 then
        return false, "empty batch"
    end
    for i = 1, #payloads do
        if not ValidateQueuedPayload(payloads[i]) then
            return false, "invalid packet"
        end
    end
    local depth = QueueDepth(sendQueueHead, sendQueueTail)
    if depth + #payloads > MAX_OUTBOUND_QUEUE then
        return RejectQueueOverflow("bulk batch", #payloads, depth,
            MAX_OUTBOUND_QUEUE)
    end
    for i = 1, #payloads do
        sendQueueTail = sendQueueTail + 1
        sendQueue[sendQueueTail] = payloads[i]
    end
    return true
end

local function EnqueueControl(payload)
    local allowed, why = Sync._TransportAllowed()
    if not allowed then return false, why end
    if not ValidateQueuedPayload(payload) then return false, "invalid packet" end
    local depth = QueueDepth(controlQueueHead, controlQueueTail)
    if depth >= MAX_CONTROL_QUEUE then
        return RejectQueueOverflow("control", 1, depth, MAX_CONTROL_QUEUE)
    end
    controlQueueTail = controlQueueTail + 1
    controlQueue[controlQueueTail] = payload
    return true
end

local function IsWaitingNotice(text)
    text = type(text) == "string" and text:lower() or ""
    return text:find("waiting to send", 1, true)
        or text:find("wait to send", 1, true)
        or text:find("message is queued", 1, true)
end

local function IsThrottleNotice(text)
    text = type(text) == "string" and text:lower() or ""
    return IsWaitingNotice(text)
        or text:find("sending messages too quickly", 1, true)
        or text:find("too many messages", 1, true)
        or text:find("chat thrott", 1, true)
end

function Sync.NoteTransportNotice(text)
    if not IsThrottleNotice(text) then return false end
    local now = Now()
    -- Only attribute a server notice to Nexus when it follows one of our own
    -- transport attempts. This avoids hiding or reacting to unrelated chat.
    if now - lastTransportAttempt > 4 then return false end
    throttlePauseUntil = math.max(throttlePauseUntil or 0, now + THROTTLE_PAUSE)
    throttleSlowUntil = math.max(throttleSlowUntil or 0, now + THROTTLE_SLOW_TIME)
    ticker = 0
    LogEvent("TX", "server throttle detected; transport paused %.0fs", THROTTLE_PAUSE)
    return IsWaitingNotice(text) and true or false
end

local function InstallTransportFilters()
    if transportFilterInstalled then return end
    transportFilterInstalled = true
    if ChatFrame_AddMessageEventFilter then
        local function QuietNexusWaitNotice(_, _, text, ...)
            if Sync.NoteTransportNotice(text) then return true end
            return false, text, ...
        end
        pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_SYSTEM", QuietNexusWaitNotice)
        -- Some 3.3.5 servers route their queue warning through this event.
        pcall(ChatFrame_AddMessageEventFilter, "UI_ERROR_MESSAGE", QuietNexusWaitNotice)
    end
end

local function PopQueued(isControl)
    if isControl then
        controlQueue[controlQueueHead] = nil
        controlQueueHead = controlQueueHead + 1
        if controlQueueHead > controlQueueTail then
            controlQueue, controlQueueHead, controlQueueTail = {}, 1, 0
        end
    else
        sendQueue[sendQueueHead] = nil
        sendQueueHead = sendQueueHead + 1
        if sendQueueHead > sendQueueTail then
            sendQueue, sendQueueHead, sendQueueTail = {}, 1, 0
        end
    end
end

local function PumpQueue(elapsed)
    if not Sync._TransportAllowed() then return end
    local now = Now()
    if now < (throttlePauseUntil or 0) then return end
    ticker = ticker + (elapsed or 0)
    local interval = now < (throttleSlowUntil or 0) and 1.75 or SEND_INTERVAL
    if ticker < interval then return end
    ticker = 0
    local payload = controlQueue[controlQueueHead]
    local isControl = payload ~= nil
    if not payload then payload = sendQueue[sendQueueHead] end
    if not payload then
        if sendQueueHead > sendQueueTail then
            sendQueue, sendQueueHead, sendQueueTail = {}, 1, 0
        end
        if controlQueueHead > controlQueueTail then
            controlQueue, controlQueueHead, controlQueueTail = {}, 1, 0
        end
        return
    end
    local validatedChannel = ResolveSendChannel()
    if not validatedChannel then
        -- Retain the head packet. Reconnect/revalidation will retry later.
        return
    end
    local escaped = payload:gsub("|","||")
    if #escaped > CHAT_LIMIT then
        LogEvent("TX","DROPPED oversize msg (%d>%d): %s",
            #escaped, CHAT_LIMIT, payload:sub(1,40))
        stats.oversizeDropped = (stats.oversizeDropped or 0) + 1
        PopQueued(isControl)
        return
    end
    lastTransportAttempt = now
    local ok = pcall(SendChatMessage, escaped, "CHANNEL", nil,
        validatedChannel)
    if ok then
        PopQueued(isControl)
        stats.sent = stats.sent + 1
        LogEvent("TX","sent %d chars ch=%s: %s",
            #escaped, tostring(validatedChannel), payload:sub(1,44))
    else
        -- Keep the packet queued. A temporary chat/channel failure must not
        -- discard a build, DPS update, deletion, or reconciliation response.
        throttlePauseUntil = math.max(throttlePauseUntil or 0, now + 2)
        LogEvent("TX","SendChatMessage FAILED ch=%s; retained for retry", tostring(channelIndex))
    end
end


local function HashText(text)
    if type(text) ~= "string" or text == "" then return nil end
    local h = 5381
    for i=1,#text do h=((h*33)+text:byte(i))%2147483648 end
    return string.format("%x",h)
end

-- Lightweight build index retained for backward compatibility with older peers.
-- Current reconciliation responses prefer complete build payloads.
local function BuildFingerprint(build)
    local D = Nexus.DpsCapture
    if build and build.fingerprint then return tostring(build.fingerprint) end
    if D and D.GetEchoKey and build and type(build.echoes) == "table" then
        local ok, key = pcall(D.GetEchoKey, build.echoes)
        if ok and key then return key end
    end
    if build and type(build.echoes) == "table" then
        local counts = {}
        for _, e in ipairs(build.echoes) do
            local id = tonumber(e and (e.spellId or e.id))
            local n = tonumber(e and (e.count or e.stacks or e.stack)) or 1
            if id and n > 0 then counts[id] = (counts[id] or 0) + n end
        end
        local ids = {}; for id in pairs(counts) do ids[#ids+1]=id end
        table.sort(ids)
        local out = {}; for _,id in ipairs(ids) do out[#out+1]=tostring(id).."x"..tostring(counts[id]) end
        if #out > 0 then return table.concat(out, ",") end
    end
    return nil
end

local function SummaryEncode(build)
    return {
        id=build.id, t=build.title, a=build.author, o=build.ownerKey,
        c=build.class,
        m=tonumber(build.lastModified) or tonumber(build.postedAt) or 0,
        h=build.fingerprintHash or HashText(BuildFingerprint(build)),
        lh=HashText(build.link),
        n=(function()
            if type(build.echoes)=="table" then
                local t=0; for _,e in ipairs(build.echoes) do t=t+(tonumber(e.stacks or e.count) or 1) end; return t
            end
            return tonumber(build.echoCount) or 0
        end)(),
        x=build.autoDps and 1 or nil,
    }
end

function Responder.PrepareSummary(build)
    local payload = SummaryEncode(build)
    if not ValidIdentifier(payload.id, MAX_BUILD_ID_BYTES) then
        return nil, "invalid build id"
    end
    if not ValidHash(tostring(payload.h or "")) then
        return nil, "invalid build hash"
    end
    local data = Codec.Base64Encode(Codec.JSONEncode(payload))
    local msg = string.format("%s|%s|%s", CODE_INDEX, MyName(), data)
    if EscapedLen(msg) > CHAT_LIMIT - CHAT_SAFETY then
        return nil, "summary too large"
    end
    return {messages={msg}, title=build.title, summary=true}
end

local function BroadcastSummary(build)
    local prepared, why = Responder.PrepareSummary(build)
    if not prepared then return false, why end
    local msg = prepared.messages[1]
    local queued, queueWhy = Enqueue(msg)
    if not queued then return false, queueWhy end
    LogEvent("TX","queuing summary '%s' (%d chars, no Echo list)", tostring(build.title), EscapedLen(msg))
    return true
end
Sync.BroadcastBuildSummary = BroadcastSummary

local function DeleteWireMessage(id, tomb)
    return string.format("%s|%s|%s|%s|%s", CODE_DELETE, MyName(),
        tostring(id), tostring(TombStamp(tomb)), TombAuthor(tomb))
end

local function MarkDeletePending(id, tomb)
    pendingDeletes[id] = true
    if type(tomb) == "table" then tomb.pending = true end
end

local function ClearPendingDelete(id, tomb)
    pendingDeletes[id] = nil
    if type(tomb) == "table" and tombstones[id] == tomb then
        tomb.pending = nil
    end
end

local function PendingDeleteCount()
    local count = 0
    for id in pairs(pendingDeletes) do
        local tomb = tombstones[id]
        if tomb and SamePeer(TombAuthor(tomb), MyName()) then
            count = count + 1
        end
    end
    return count
end

local function PumpPendingDeletes(elapsed)
    if not Sync._TransportAllowed() then return end
    if not next(pendingDeletes) then return end
    pendingDeleteTicker = pendingDeleteTicker + (tonumber(elapsed) or 0)
    if pendingDeleteTicker < 1 then return end
    if QueueDepth(sendQueueHead, sendQueueTail) >= MAX_OUTBOUND_QUEUE then
        pendingDeleteTicker = 1
        return
    end
    local selectedId, selectedTomb
    for id in pairs(pendingDeletes) do
        local tomb = tombstones[id]
        if not tomb then
            pendingDeletes[id] = nil
        elseif SamePeer(TombAuthor(tomb), MyName())
            and (not selectedId or tostring(id) < tostring(selectedId)) then
            selectedId, selectedTomb = id, tomb
        end
    end
    if not selectedId then return end
    pendingDeleteTicker = 0
    local queued, why = Enqueue(DeleteWireMessage(selectedId, selectedTomb))
    if queued then
        ClearPendingDelete(selectedId, selectedTomb)
        LogEvent("TX", "queued pending delete '%s'", tostring(selectedId))
    elseif why ~= "sync queue full" then
        -- A permanent local serialization failure cannot be helped by retrying;
        -- the tombstone remains available to normal reconciliation.
        ClearPendingDelete(selectedId, selectedTomb)
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

local QueueLegacyRecovery

local function StoreSummary(data, transportSender)
    if type(data) ~= "table" or not Codec.IsSafeTree(data, 4, 80)
        or not ValidIdentifier(data.id, MAX_BUILD_ID_BYTES)
        or not ValidText(data.t, 120, false)
        or not ValidPeerName(data.a)
        or not ValidHash(tostring(data.h or ""))
        or (data.lh ~= nil and not ValidHash(tostring(data.lh)))
        or not Sync._ValidRemoteEpoch(data.m, 0)
        or (data.n ~= nil and (not FiniteNumber(tonumber(data.n))
            or tonumber(data.n) < 0 or tonumber(data.n) > 10000)) then
        return false, false
    end
    if not SamePeer(data.a, transportSender)
        or not OwnerKeyMatchesAuthor(data.o or data.ownerKey, data.a) then
        return false, false
    end
    local id = tostring(data.id)
    local old, oldSource = CatalogGet(id)
    if old and old.isMine then return false, false end
    if old and old.ownerVerified ~= false
        and not SamePeer(old.author, data.a) then return false, false end
    local stamp = tonumber(data.m) or 0
    if not Sync._AllowsRemoteRevision(data.a, stamp, id) then
        LogEvent("RX", "skip summary '%s': older than compacted deletion floor",
            tostring(data.t))
        return true, false
    end
    local tomb = tombstones[id]
    if tomb and stamp <= TombStamp(tomb) then
        LogEvent("RX","skip summary '%s': tombstoned", tostring(data.t))
        return true, false
    end
    if tomb and (TombAuthor(tomb) == ""
        or not SamePeer(TombAuthor(tomb), data.a)) then
        LogEvent("RX", "REJECT summary resurrection of '%s': tombstone belongs to %s",
            tostring(id), tostring(TombAuthor(tomb)))
        return false, false
    end
    local oldStamp = old and (tonumber(old.lastModified) or tonumber(old.postedAt) or 0) or nil
    if oldStamp and stamp < oldStamp then
        LogEvent("RX","skip summary '%s': older than local copy", tostring(data.t))
        return true, false
    end
    if oldStamp and stamp == oldStamp then
        stats.duplicatesSkipped = stats.duplicatesSkipped + 1
        if oldSource == "bundled" then
            stats.baselineSkipped = (stats.baselineSkipped or 0) + 1
        end
        if old and (type(old.echoes) ~= "table" or #old.echoes == 0) then
            QueueLegacyRecovery(id)
            LogEvent("RX","DUPLICATE legacy summary '%s'; queued missing full loadout", tostring(data.t))
        else
            LogEvent("RX","skip summary '%s': DUPLICATE", tostring(data.t))
        end
        return true, false
    end
    local newHash = tostring(data.h)
    local newLinkHash = type(data.lh) == "string" and data.lh or nil
    local oldLinkHash = old and (old.linkHash or HashText(old.link)) or nil
    local linkChanged = old ~= nil and newLinkHash ~= oldLinkHash
    local keepEchoes = old and old.fingerprintHash == newHash and old.echoes or nil
    local record = {
        id=id, title=tostring(data.t):sub(1,120), author=tostring(data.a or "Unknown"):sub(1,80),
        ownerKey=type(data.o)=="string" and data.o:lower() or nil,
        class=data.c, description=old and old.description or "",
        lastModified=stamp, postedAt=old and old.postedAt or stamp, isMine=old and old.isMine or false,
        autoDps=data.x==1, fingerprint=keepEchoes and old.fingerprint or nil,
        fingerprintHash=newHash, echoCount=tonumber(data.n) or 0,
        echoes=keepEchoes, loadoutAvailable=type(keepEchoes)=="table" and #keepEchoes>0,
        linkHash=newLinkHash, needsFullBuild=linkChanged or nil,
        ownerVerified=true,
    }
    CatalogClearTombstone(id)
    local _, storedAs = CatalogPut(record)
    if storedAs == "baseline" then
        stats.baselineSkipped = (stats.baselineSkipped or 0) + 1
    end
    seenRemoteIds[id] = stamp
    stats.received = stats.received + 1
    lastSyncNewCount = lastSyncNewCount + 1
    if old then
        stats.updated = (stats.updated or 0) + 1
        LogEvent("RX","UPDATED summary '%s' by %s%s", tostring(data.t), tostring(data.a or "Unknown"),
            keepEchoes and " (loadout unchanged)" or " (loadout needed)")
    else
        LogEvent("RX","STORED legacy summary '%s' by %s (%d Echo entries pending full sync)",
            tostring(data.t), tostring(data.a or "Unknown"), tonumber(data.n) or 0)
    end
    if not keepEchoes or linkChanged then QueueLegacyRecovery(id) end
    Sync._RequestRetention("build summary received")
    return true, true
end

QueueLegacyRecovery = function(buildId)
    if not ValidIdentifier(buildId, MAX_BUILD_ID_BYTES) then return false end
    local build = CatalogGet(buildId)
    if build and type(build.echoes) == "table" and #build.echoes > 0 then return false end
    local now = Now()
    if requestedLoadouts[buildId] and now - requestedLoadouts[buildId] < 120 then return false end
    local depth = QueueDepth(legacyRecoveryHead, legacyRecoveryTail)
    if depth >= MAX_RECOVERY_QUEUE then
        RejectQueueOverflow("recovery", 1, depth, MAX_RECOVERY_QUEUE)
        return false
    end
    requestedLoadouts[buildId] = now
    legacyRecoveryTail = legacyRecoveryTail + 1
    legacyRecoveryQueue[legacyRecoveryTail] = tostring(buildId)
    return true
end

function Sync.RequestLoadout(buildId)
    -- Menu clicks never transmit directly. If this is a summary inherited from
    -- an older Nexus peer, queue one slow background recovery request instead.
    -- Current peers send complete builds during normal reconciliation.
    local queued = QueueLegacyRecovery(buildId)
    return false, queued and "queued for background recovery" or "awaiting sync"
end

function Sync.RequestFullLoadoutSync()
    -- Backward-compatible API: use one normal hash reconciliation instead of
    -- broadcasting one request per missing build.
    return Sync.RequestSync()
end


-- Header-aware chunking: measures the ACTUAL escaped header so no chunk
-- can ever exceed the hard limit.
function Responder.ChunkBuildMessages(buildId, lastMod, data, responseMode)
    if not ValidIdentifier(tostring(buildId or ""), MAX_BUILD_ID_BYTES)
        or not ValidIntegerText(tostring(lastMod or ""), 0)
        or type(data) ~= "string" or data == "" or #data > MAX_BYTES then
        return nil, "invalid build envelope"
    end
    buildId = tostring(buildId)
    lastMod = tostring(lastMod)
    local sender = MyName()
    -- Worst-case header = largest chunk index digits (999/999)
    local sampleHdr = string.format("%s|%s|%s|%s|999/999|",
        CODE_BUILD, sender, buildId, lastMod)
    local budget = CHAT_LIMIT - CHAT_SAFETY - EscapedLen(sampleHdr)
    if budget < 32 then return nil, "id too long" end

    local single = string.format("%s|%s|%s|%s|1/1|%s",
        CODE_BUILD, sender, buildId, lastMod, data)
    if EscapedLen(single) <= CHAT_LIMIT - CHAT_SAFETY then
        if responseMode then
            Responder.stats.chunkMessagesBuilt =
                Responder.stats.chunkMessagesBuilt + 1
        end
        return {single}
    end
    local total = math.ceil(#data / budget)
    if total > MAX_CHUNKS then return nil, "build too large" end
    local messages = {}
    for idx = 1, total do
        local s = (idx-1)*budget + 1
        messages[#messages + 1] = string.format("%s|%s|%s|%s|%d/%d|%s",
            CODE_BUILD, sender, buildId, lastMod, idx, total,
            data:sub(s, s+budget-1))
    end
    if responseMode then
        Responder.stats.chunkMessagesBuilt =
            Responder.stats.chunkMessagesBuilt + #messages
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

function Responder.PrepareBuild(build, responseMode)
    build = Responder.ResolveBuild(build)
    if not build or type(build.echoes) ~= "table" or #build.echoes == 0 then
        return nil, "no echoes"
    end
    if not ValidIdentifier(tostring(build.id or ""), MAX_BUILD_ID_BYTES) then
        return nil, "invalid build id"
    end
    if responseMode then
        Responder.stats.buildSerializations =
            Responder.stats.buildSerializations + 1
    end
    local payload = CompactEncode(build)
    local json = Codec.JSONEncode(payload)
    local b64 = Codec.Base64Encode(json)
    if #b64 > MAX_BYTES then
        return nil, "too large"
    end
    local messages, why = Responder.ChunkBuildMessages(
        build.id, tostring(payload.m), b64, responseMode)
    if not messages then return nil, why end
    return {
        messages=messages, build=build,
        buildKey=tostring(build.id or build.fingerprintHash
            or build.fingerprint or ""),
        title=build.title, id=build.id,
        echoCount=#build.echoes, b64Bytes=#b64,
    }
end

function Responder.AdmitBuild(prepared, responseMode)
    if type(prepared) ~= "table" or type(prepared.messages) ~= "table" then
        return false, "invalid prepared build"
    end
    if not Responder.CanAdmit(#prepared.messages) then
        return false, "sync queue full"
    end
    local queued, why = EnqueueBatch(prepared.messages)
    if not queued then return false, why end
    if responseMode then
        Responder.stats.buildAdmissions =
            Responder.stats.buildAdmissions + 1
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
        if BroadcastSummary(b) then n=n+1 end
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
    local cacheKey = tostring(deltaHash) .. "|" .. tostring(MyName())
    local cached = Responder.candidateCache
    if cached and cached.key == cacheKey then return cached end
    local byBucket = {}
    for i = 1, BUILD_BUCKETS do byBucket[i] = {} end
    cached = {
        key=cacheKey, deltaHash=tostring(deltaHash), sender=MyName(),
        byBucket=byBucket, phase="overlay", cursor=nil,
        complete=false, createdAt=Now(),
    }
    Responder.candidateCache = cached
    Responder.stats.candidateSnapshots =
        Responder.stats.candidateSnapshots + 1
    return cached
end

function Responder.SnapshotCurrent(snapshot)
    return type(snapshot) == "table"
        and snapshot.key == tostring(DeltaBuildHash()) .. "|" .. tostring(MyName())
end

function Responder.AdvanceCandidateSnapshot(snapshot)
    if not Responder.SnapshotCurrent(snapshot) then
        return false, "stale candidate snapshot", true
    end
    if snapshot.complete then return true, nil, false end
    Responder.stats.candidateScans =
        (Responder.stats.candidateScans or 0) + 1
    if snapshot.phase == "overlay" then
        local catalog = Catalog()
        local id, build, done
        if catalog and catalog.SyncDeltaNext then
            id, build, done = catalog.SyncDeltaNext(snapshot.cursor)
        else
            done = true
        end
        if done then
            snapshot.phase, snapshot.cursor = "tombstone", nil
            return false, nil, true
        end
        snapshot.cursor = id
        if build then
            local complete = (type(build.echoes) == "table"
                and #build.echoes > 0) and "F" or "S"
            local token = table.concat({"B", tostring(id),
                tostring(build.lastModified or build.postedAt or 0), complete,
                tostring(build.fingerprintHash or build.fingerprint or "0")}, ":")
            local bucket = BuildBucket(id)
            snapshot.byBucket[bucket][#snapshot.byBucket[bucket] + 1] = {
                kind="build", id=id, build=build, token=token,
            }
        end
        return false, nil, true
    end
    local id, tomb = next(tombstones or {}, snapshot.cursor)
    if id == nil then
        snapshot.complete = true
        return true, nil, true
    end
    snapshot.cursor = id
    if SamePeer(TombAuthor(tomb), snapshot.sender) then
        local copy = {stamp=TombStamp(tomb), author=TombAuthor(tomb)}
        local bucket = BuildBucket(id)
        snapshot.byBucket[bucket][#snapshot.byBucket[bucket] + 1] = {
            kind="tomb", id=id, tomb=copy,
            token=table.concat({"T", tostring(id),
                tostring(TombStamp(copy)), TombAuthor(copy)}, ":"),
        }
    end
    return false, nil, true
end

function Responder.PrepareCandidate(item, bucketState)
    bucketState.prepared = bucketState.prepared or {}
    local cached = bucketState.prepared[item.token]
    if cached then return cached end
    local prepared, why
    if item.kind == "build" then
        if type(item.build.echoes) == "table" and #item.build.echoes > 0 then
            prepared, why = Responder.PrepareBuild(item.build, true)
        else
            Responder.stats.buildSerializations =
                Responder.stats.buildSerializations + 1
            prepared, why = Responder.PrepareSummary(item.build)
        end
    else
        prepared = {messages={DeleteWireMessage(item.id, item.tomb)},
            tomb=true, id=item.id, tombstone=item.tomb}
    end
    if not prepared then return nil, why end
    bucketState.prepared[item.token] = prepared
    return prepared
end

function Responder.AdmitCandidate(item, bucketState)
    if Responder.Backpressured() then
        return false, "sync queue full", true
    end
    local prepared, why = Responder.PrepareCandidate(item, bucketState)
    if not prepared then return false, why, false end
    if not Responder.CanAdmit(#prepared.messages) then
        return false, "sync queue full", true
    end
    local admitted, admitWhy
    if item.kind == "build" and not prepared.summary then
        admitted, admitWhy = Responder.AdmitBuild(prepared, true)
    else
        admitted, admitWhy = EnqueueBatch(prepared.messages)
        if admitted and prepared.summary then
            LogEvent("TX", "queuing summary '%s' (no Echo list)",
                tostring(item.build and item.build.title))
        end
    end
    if not admitted then
        return false, admitWhy, admitWhy == "sync queue full"
    end
    bucketState.prepared[item.token] = nil
    return true, "admitted", false
end

function Responder.SendNextBuild(bucketState)
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
    local admitted, why, transient = Responder.AdmitCandidate(item, bucketState)
    if admitted then
        bucketState.progress[item.token] = "admitted"
        bucketState.cursor = bucketState.cursor + 1
        if item.kind == "tomb" then
            ClearPendingDelete(item.id, item.tomb)
        else
            stats.overlaySent = (stats.overlaySent or 0) + 1
        end
        return 1, bucketState.cursor > #candidates,
            bucketState.claimSafe ~= false, true
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
    return 0, bucketState.cursor > #candidates, false, true, why
end

local function BucketDelay(key, kind, bucket)
    local base = StableDelay(tostring(key)..":"..tostring(kind)..":"..tostring(bucket)..":"..MyName())
    local span = BUCKET_CLAIM_MAX - CLAIM_DELAY_MIN
    local normalized = (base - CLAIM_DELAY_MIN) / math.max(0.01, CLAIM_DELAY_MAX - CLAIM_DELAY_MIN)
    return CLAIM_DELAY_MIN + normalized * span
end

local function RequestSyncOnce()
    if not Sync.IsConnected() and not Sync.EnsureChannel() then
        joinAttempts = 0
        LogEvent("SYNC","sync requested but not connected")
        return false, "not connected to the sync channel"
    end
    local now = Now()
    if now - lastRequestAt < REQUEST_COOLDOWN then
        LogEvent("SYNC","sync request ignored (cooldown %.1fs)", now-lastRequestAt)
        return false, "please wait a few seconds between syncs"
    end
    lastRequestAt = now
    lastSyncNewCount = 0
    receiveWindowUntil = now + RECEIVE_WINDOW
    -- Include independent build and leaderboard hashes. Identical peers can
    -- suppress their response entirely, and peers with the same state elect
    -- one responder instead of all flooding the channel with duplicates.
    local buildHash = CurrentBuildHash()
    local dpsHash = CurrentDpsHash()
    local requestId = tostring(math.floor(now * 1000)) .. "-" .. tostring(math.random(1000,9999))
    local queued, queueWhy = Enqueue(string.format("%s|%s|%s|%s|%s|%s",
        CODE_REQUEST, MyName(), buildHash, dpsHash, requestId,
        tostring((Nexus and Nexus.VERSION) or "0.0.0-dev")))
    if not queued then
        lastRequestAt = -math.huge
        receiveWindowUntil = 0
        return false, queueWhy or "sync queue full"
    end
    LogEvent("SYNC","requested sync (build=%s dps=%s id=%s) -- reconciliation active",
        buildHash, dpsHash, requestId)
    return true
end

-- Broadcast a validated exact-set DPS record. The JSON/base64 payload is
-- chunked using the same 255-byte-safe discipline as build sync.
function Responder.ValidatePreparedDps(payload)
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
    return FiniteNumber(dps) and dps > 0 and dps <= 500000000
        and FiniteNumber(duration) and duration >= 30
        and FiniteNumber(stamp) and stamp > 0
        and FiniteNumber(level) and level >= 1 and level <= 80
        and level == math.floor(level) and validClass
        and player ~= "" and #player <= 64 and not player:find("[%c|]")
        and (payload.c == "dummy" or payload.c == "lk")
        and SamePeer(player, MyName())
        and OwnerKeyMatchesAuthor(payload.o, player)
        and computed and computed == payload.f
        and payload.h and (not computedHash or payload.h == computedHash)
end

function Sync.BroadcastDpsRecord(record, prepared, responseMode)
    if type(prepared) ~= "table" then prepared = nil end
    if responseMode and Responder.Backpressured() then
        return false, "sync queue full", prepared
    end
    if prepared ~= nil then
        if type(prepared) ~= "table" or type(prepared.messages) ~= "table"
            or type(prepared.payload) ~= "table"
            or #prepared.messages < 1
            or not Responder.ValidatePreparedDps(prepared.payload) then
            return false, "invalid prepared DPS record"
        end
        if not Responder.CanAdmit(#prepared.messages) then
            return false, "sync queue full", prepared
        end
        local queued, queueWhy = EnqueueBatch(prepared.messages)
        if not queued then return false, queueWhy, prepared end
        LogEvent("TX","DPS2 [%s] %.0f by %s (%d chunks)",
            tostring(prepared.payload.c), prepared.payload.d,
            prepared.payload.p, #prepared.messages)
        return true
    end
    local D = Nexus.DpsCapture
    if type(record) == "table" and D
        and type(D.MaterializeRecord) == "function" then
        local ok, resolved = pcall(D.MaterializeRecord, record)
        if ok and type(resolved) == "table" then record = resolved end
    end
    if type(record) ~= "table" or type(record.fingerprint) ~= "string"
        or type(record.echoes) ~= "table" then return false end
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
    local computed = D and D.GetEchoKey and D.GetEchoKey(record.echoes) or nil
    if not FiniteNumber(dps) or dps <= 0 or dps > 500000000
        or not FiniteNumber(duration) or duration < 30
        or not FiniteNumber(stamp) or stamp <= 0
        or not FiniteNumber(level) or level < 1 or level > 80
        or level ~= math.floor(level) or not validClass
        or player == "" or #player > 64 or player:find("[%c|]")
        or (record.category ~= "dummy" and record.category ~= "lk")
        or not SamePeer(player, MyName())
        or not OwnerKeyMatchesAuthor(record.ownerKey, player)
        or not computed or computed ~= record.fingerprint then
        return false
    end
    local loadoutHash = record.loadoutHash
    if not loadoutHash and D and D.GetEchoHash then
        loadoutHash = D.GetEchoHash(record.echoes)
    end
    local computedHash = D and D.GetEchoHash and D.GetEchoHash(record.echoes)
        or nil
    if not loadoutHash or (computedHash and loadoutHash ~= computedHash) then
        return false
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
    }
    if responseMode then
        Responder.stats.dpsSerializations =
            Responder.stats.dpsSerializations + 1
    end
    local encoded = Codec.Base64Encode(Codec.JSONEncode(payload))
    local transferId = tostring(payload.p) .. ":" .. tostring(payload.t) .. ":" .. tostring(payload.d)
    if not ValidTransferIdentifier(transferId)
        or #encoded > MAX_ENCODED_BYTES then return false end
    local header = CODE_DPS2 .. "|" .. MyName() .. "|" .. transferId .. "|999/999|"
    local chunkSize = CHAT_LIMIT - CHAT_SAFETY - EscapedLen(header)
    if chunkSize < 24 then return false end
    local total = math.ceil(#encoded / chunkSize)
    if total < 1 or total > 999 then return false end
    local messages = {}
    for i = 1, total do
        local data = encoded:sub((i - 1) * chunkSize + 1, i * chunkSize)
        messages[#messages + 1] = string.format("%s|%s|%s|%d/%d|%s",
            CODE_DPS2, MyName(), transferId, i, total, data)
    end
    if responseMode then
        Responder.stats.chunkMessagesBuilt =
            Responder.stats.chunkMessagesBuilt + #messages
    end
    prepared = {messages=messages, payload=payload}
    if not Responder.CanAdmit(#messages) then
        return false, "sync queue full", prepared
    end
    local queued, queueWhy = EnqueueBatch(messages)
    if not queued then return false, queueWhy, prepared end
    LogEvent("TX","DPS2 [%s] %.0f by %s (%d chunks)",
        tostring(payload.c), payload.d, payload.p, total)
    return true
end

-- Legacy wrapper retained for older callers/peers.
function Sync.BroadcastDps(buildId, player, dps, level, category)
    if not (buildId and player and dps and dps > 0) then return false end
    local payload = string.format("%s|%s|%s|%s|%s|%s|%s",
        CODE_DPS, MyName(), buildId, tostring(player),
        tostring(math.floor(dps)), tostring(level or 0), category or "dummy")
    if EscapedLen(payload) > CHAT_LIMIT - CHAT_SAFETY then return false end
    return Enqueue(payload)
end

local function HandleDps(parts)
    -- The legacy format has no duration, timestamp, or exact Echo evidence.
    -- Keep the code recognized so old traffic fails cleanly, but never admit
    -- it to a verified leaderboard.
    LogEvent("RX", "DROP legacy DPS submission without required evidence")
end

local function HandleDps2(parts)
    local sender, transferId, spec, data = parts[2], parts[3], parts[4], parts[5]
    if not ValidPeerName(sender)
        or not ValidTransferIdentifier(transferId)
        or not ValidField(spec, 16, false)
        or not ValidField(data, MAX_CHUNK_BYTES, false) then return false end
    local idx, total = spec:match("^(%d+)/(%d+)$")
    idx, total = tonumber(idx), tonumber(total)
    if not (idx and total and idx >= 1 and idx <= total
        and total >= 1 and total <= MAX_CHUNKS) then return false end
    autoConverge.lastInbound = Now()
    local key = sender .. ":" .. transferId
    local e = dpsInflight[key]
    if not e then
        CleanExpiredInflight()
        if not CanStartTransfer(dpsInflight, sender) then return false end
        e = { chunks = {}, total = total, t0 = Now(), lastSeen = Now(),
            sender = sender, transferId=transferId, bytes = 0, received = 0 }
        dpsInflight[key] = e
    end
    if e.total ~= total or e.sender ~= sender
        or e.transferId ~= transferId then
        dpsInflight[key] = nil
        return false
    end
    e.lastSeen = Now()
    local prior = e.chunks[idx]
    if prior ~= nil then
        if prior ~= data then dpsInflight[key] = nil end
        return false
    end
    if e.bytes + #data > MAX_ENCODED_BYTES then
        dpsInflight[key] = nil
        return false
    end
    e.chunks[idx] = data
    e.bytes = e.bytes + #data
    e.received = e.received + 1
    if e.received ~= total then return false end
    dpsInflight[key] = nil
    local raw = Codec.Base64Decode(table.concat(e.chunks, "", 1, total))
    local record = raw and Codec.JSONDecode(raw)
    if type(record) ~= "table" then return false end
    if Nexus.DpsCapture and Nexus.DpsCapture.ReceiveRecord then
        if not SamePeer(record.p or record.player, sender) then
            LogEvent("RX", "DROP DPS owner mismatch from %s", tostring(sender))
            return false
        end
        local ok, accepted = pcall(
            Nexus.DpsCapture.ReceiveRecord, record, sender)
        if ok and accepted then
            -- Mesh redistribution: relay the record so peers learn about it.
            Sync.BroadcastDpsRecord(record)
            -- Also relay the exact echo list if we have it locally —
            -- the original player may be offline so we carry the data forward.
            local buildId = record.b or record.buildId
            local build = buildId and CatalogGet(buildId)
            if build and type(build.echoes) == "table" and #build.echoes > 0 then
                pcall(Sync.BroadcastBuild, build)
            end
            return true
        end
    end
    return false
end

function Sync.BroadcastDelete(build)
    if not build or not ValidIdentifier(tostring(build.id or ""),
        MAX_BUILD_ID_BYTES) then return false end
    local stamp = tostring((time and time()) or 0)
    local author = tostring(build.author or MyName())
    if not SamePeer(author, MyName()) then return false end
    local tomb = { stamp=tonumber(stamp) or 0, author=author }
    CatalogSetTombstone(build.id, tomb)
    tombstones[build.id] = tomb
    hotBuilds[build.id] = nil
    local queued, why = Enqueue(DeleteWireMessage(build.id, tomb))
    if queued then
        ClearPendingDelete(build.id, tomb)
        LogEvent("TX","delete '%s'", tostring(build.title or build.id))
        return true
    end
    if why == "sync queue full" then
        MarkDeletePending(build.id, tomb)
        LogEvent("TX", "delete '%s' queued for retry",
            tostring(build.title or build.id))
        return false, "queued for retry"
    end
    return false, why
end

------------------------------------------------------------------------
-- Incoming
------------------------------------------------------------------------

CleanExpiredInflight = function()
    local now = Now()
    for key, v in pairs(inflight) do
        if now - (v.lastSeen or v.t0 or now) > INFLIGHT_GRACE
            or now - (v.t0 or now) > INFLIGHT_MAX_AGE then
            inflight[key] = nil
        end
    end
    for key, v in pairs(dpsInflight) do
        if now - (v.lastSeen or v.t0 or now) > INFLIGHT_GRACE
            or now - (v.t0 or now) > INFLIGHT_MAX_AGE then
            dpsInflight[key] = nil
        end
    end
end

local function ValidatePayload(data)
    if type(data) ~= "table" then return nil end
    if not Codec.IsSafeTree(data, 6, 2000) then return nil end
    return CompactDecode(data)
end

local function ShouldStore(id, lastMod, author)
    if not Sync._AllowsRemoteRevision(author, lastMod, id) then
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

local function StoreReceivedBuild(payload, ownerVerified, relaySender)
    local existing = CatalogGet(payload.id)
    local mine = (existing and existing.isMine) or false
    -- Preserve an existing local link if the incoming payload has no link
    local link = payload.link or (existing and existing.link) or nil
    local record = {
        id=payload.id, title=payload.title, description=payload.description,
        author=payload.author,
        ownerKey=ownerVerified and payload.ownerKey or nil,
        class=payload.class, echoes=payload.echoes,
        postedAt=payload.postedAt, lastModified=payload.lastModified, isMine=mine,
        autoDps=payload.autoDps, fingerprint=BuildFingerprint(payload), fingerprintHash=HashText(BuildFingerprint(payload)),
        echoCount=(function() local t=0; for _,e in ipairs(payload.echoes) do t=t+(tonumber(e.stacks or e.count) or 1) end; return t end)(),
        loadoutAvailable=true,
        link=link,
        linkHash=HashText(link), needsFullBuild=nil,
        ownerVerified=ownerVerified and true or false,
        relaySender=ownerVerified and nil or relaySender,
    }
    CatalogClearTombstone(payload.id)
    local _, storedAs = CatalogPut(record)
    if storedAs == "baseline" then
        stats.baselineSkipped = (stats.baselineSkipped or 0) + 1
    end
    seenRemoteIds[payload.id] = payload.lastModified
    requestedLoadouts[payload.id] = nil
    stats.received = stats.received + 1
    lastSyncNewCount = lastSyncNewCount + 1
    Sync._RequestRetention("full build received")
end

function Responder.StartManualPublish()
    Responder.manualPublish = {
        phase="build", cursor=nil, pending=nil,
        dpsProgress={}, scanned=0, sentBuilds=0,
        sentTombstones=0, sentDps=0, restarts=0,
    }
    LogEvent("SYNC", "manual outbound reconciliation started")
end

function Responder.FinishManualPublish()
    local state = Responder.manualPublish
    if not state then return end
    LogEvent("SYNC", "manual outbound reconciliation complete: %d build(s), %d delete(s), %d DPS record(s)",
        tonumber(state.sentBuilds) or 0,
        tonumber(state.sentTombstones) or 0,
        tonumber(state.sentDps) or 0)
    Responder.manualPublish = nil
end

function Responder.AdvanceManualCursor(state, id)
    state.cursor = id
    state.pending = nil
end

function Responder.PumpManualBuilds(state)
    local catalog = Catalog()
    if not (catalog and type(catalog.SyncDeltaNext) == "function") then
        state.phase, state.cursor, state.pending = "tombstone", nil, nil
        return
    end
    if not state.pending then
        local ok, id, build, done = pcall(catalog.SyncDeltaNext, state.cursor)
        if not ok then
            state.restarts = (tonumber(state.restarts) or 0) + 1
            state.cursor = nil
            if state.restarts > 3 then
                LogEvent("SYNC", "manual build scan abandoned after catalog churn")
                state.phase = "tombstone"
            end
            return
        end
        if done then
            state.phase, state.cursor = "tombstone", nil
            return
        end
        state.scanned = (tonumber(state.scanned) or 0) + 1
        if not build or not SamePeer(build.author, MyName()) then
            state.cursor = id
            return
        end
        local prepared, why = Responder.PrepareSummary(build)
        if not prepared then
            LogEvent("TX", "manual publish skipped build '%s': %s",
                tostring(id), tostring(why or "invalid summary"))
            state.cursor = id
            return
        end
        state.pending = {id=id, message=prepared.messages[1]}
    end
    local pending = state.pending
    local queued, why = Enqueue(pending.message)
    if queued then
        state.sentBuilds = state.sentBuilds + 1
        Responder.AdvanceManualCursor(state, pending.id)
    elseif why ~= "sync queue full" then
        LogEvent("TX", "manual publish dropped build '%s': %s",
            tostring(pending.id), tostring(why or "invalid packet"))
        Responder.AdvanceManualCursor(state, pending.id)
    end
end

function Responder.PumpManualTombstones(state)
    if not state.pending then
        local ok, id, tomb = pcall(next, tombstones or {}, state.cursor)
        if not ok then
            state.restarts = (tonumber(state.restarts) or 0) + 1
            state.cursor = nil
            if state.restarts > 6 then
                LogEvent("SYNC", "manual delete scan abandoned after catalog churn")
                state.phase = "dps"
            end
            return
        end
        if id == nil then
            state.phase, state.cursor = "dps", nil
            return
        end
        if not SamePeer(TombAuthor(tomb), MyName())
            or not Sync._ValidRemoteEpoch(TombStamp(tomb), 1) then
            state.cursor = id
            return
        end
        state.pending = {
            id=id, tomb=tomb, message=DeleteWireMessage(id, tomb),
        }
    end
    local pending = state.pending
    local queued, why = Enqueue(pending.message)
    if queued then
        state.sentTombstones = state.sentTombstones + 1
        ClearPendingDelete(pending.id, pending.tomb)
        Responder.AdvanceManualCursor(state, pending.id)
    elseif why ~= "sync queue full" then
        LogEvent("TX", "manual publish dropped delete '%s': %s",
            tostring(pending.id), tostring(why or "invalid packet"))
        Responder.AdvanceManualCursor(state, pending.id)
    end
end

function Responder.PumpManualDps(state)
    local dps = Nexus and Nexus.DpsCapture
    if not (dps and type(dps.BroadcastAllBuildBests) == "function") then
        Responder.FinishManualPublish()
        return
    end
    local ok, sent, complete, _, why = pcall(dps.BroadcastAllBuildBests,
        "manual-local", nil, state.dpsProgress, 1, true)
    if not ok then
        LogEvent("SYNC", "manual DPS reconciliation failed: %s", tostring(sent))
        Responder.FinishManualPublish()
        return
    end
    state.sentDps = state.sentDps + (tonumber(sent) or 0)
    if complete then Responder.FinishManualPublish()
    elseif why and why ~= "sync queue full" then
        LogEvent("SYNC", "manual DPS reconciliation deferred: %s", tostring(why))
    end
end

function Responder.PumpManualPublish()
    local state = Responder.manualPublish
    if not state or Responder.Backpressured() then return end
    if state.phase == "build" then Responder.PumpManualBuilds(state)
    elseif state.phase == "tombstone" then Responder.PumpManualTombstones(state)
    else Responder.PumpManualDps(state) end
end

local function HandleComplete(buildId, lastMod, fullData, transportSender)
    local json = Codec.Base64Decode(fullData)
    if not json then
        stats.malformedRejected = stats.malformedRejected + 1
        LogEvent("RX","REJECT '%s': bad base64 (%d bytes -- truncated?)",
            tostring(buildId), #tostring(fullData))
        return false
    end
    local data = Codec.JSONDecode(json)
    if not data then
        stats.malformedRejected = stats.malformedRejected + 1
        LogEvent("RX","REJECT '%s': JSON decode failed", tostring(buildId))
        return false
    end
    -- Silently drop legacy placeholder builds posted as "WR Team" before the rename
    if tostring(data.a or data.author or ""):lower() == "wr team" then
        LogEvent("RX","REJECT legacy placeholder '%s'", tostring(data.t or data.title))
        return false
    end
    local payload = ValidatePayload(data)
    if not payload then
        stats.malformedRejected = stats.malformedRejected + 1
        LogEvent("RX","REJECT '%s': validation failed", tostring(buildId))
        return false
    end
    if payload.id ~= buildId then
        stats.malformedRejected = stats.malformedRejected + 1
        LogEvent("RX","REJECT id mismatch: envelope='%s' payload='%s'",
            tostring(buildId), tostring(payload.id))
        return false
    end
    local directOwner = SamePeer(payload.author, transportSender)
    local existing, existingSource = CatalogGet(payload.id)
    local replacingUnverified = existing and existing.ownerVerified == false
        and directOwner
    local allowed, why
    if not Sync._AllowsRemoteRevision(payload.author,
        payload.lastModified, payload.id) then
        allowed, why = false, "retention floor"
    elseif replacingUnverified then
        allowed, why = true, "owner-verified"
    else
        allowed, why = ShouldStore(payload.id, payload.lastModified,
            payload.author)
    end
    if not allowed then
        if why == "deleted" then
            LogEvent("RX","skip '%s': tombstoned", tostring(payload.title))
        elseif why == "tombstone owner" then
            LogEvent("RX", "REJECT resurrection of '%s': tombstone belongs to %s",
                tostring(payload.id), tostring(TombAuthor(tombstones[payload.id])))
        elseif why == "retention floor" then
            LogEvent("RX", "skip '%s': older than compacted deletion floor",
                tostring(payload.title))
        else
            stats.duplicatesSkipped = stats.duplicatesSkipped + 1
            if existingSource == "bundled" then
                stats.baselineSkipped = (stats.baselineSkipped or 0) + 1
            end
            LogEvent("RX","skip '%s': DUPLICATE (have stamp %s)",
                tostring(payload.title), tostring(seenRemoteIds[payload.id]))
        end
        return true
    end
    if existing and not directOwner then
        LogEvent("RX", "REJECT relayed overwrite of '%s' from %s",
            tostring(payload.id), tostring(transportSender))
        return false
    end
    if existing and existing.isMine then
        LogEvent("RX", "REJECT remote overwrite of local build '%s'",
            tostring(payload.id))
        return false
    end
    if existing and existing.ownerVerified ~= false
        and not SamePeer(existing.author, payload.author) then
        LogEvent("RX", "REJECT owner change for '%s'", tostring(payload.id))
        return false
    end
    if why == "updated" then
        stats.updated = (stats.updated or 0) + 1
        LogEvent("RX","UPDATED '%s' by %s (%d echoes, %s->%s)",
            tostring(payload.title), tostring(payload.author), #payload.echoes,
            tostring(seenRemoteIds[payload.id]), tostring(payload.lastModified))
    elseif why == "loadout" then
        LogEvent("RX","LOADED exact Echo list for '%s' by %s (%d echoes)",
            tostring(payload.title), tostring(payload.author), #payload.echoes)
    else
        LogEvent("RX","STORED (new) '%s' by %s (%d echoes)",
            tostring(payload.title), tostring(payload.author), #payload.echoes)
    end
    StoreReceivedBuild(payload, directOwner, transportSender)
    Sync.RequestDataViewRefresh()
    return true
end

local function SendBucketResponse(entry, kind, bucket, bucketState)
    local n, dpsN, complete, claimSafe, progressed, why =
        0, 0, true, true, false, nil
    bucketState.progress = bucketState.progress or {}
    if kind == "B" then
        n, complete, claimSafe, progressed, why =
            Responder.SendNextBuild(bucketState)
        if claimSafe == false then bucketState.claimSafe = false end
    else
        local D = Nexus.DpsCapture
        if D and D.BroadcastAllBuildBests then
            local ok, result, allAdmitted, didProgress, responseWhy = pcall(
                D.BroadcastAllBuildBests, entry.peerDpsHash, bucket,
                bucketState.progress, 1)
            if ok then dpsN = tonumber(result) or 0 end
            complete = ok and allAdmitted == true
            progressed = ok and didProgress == true
            why = ok and responseWhy or "DPS response failed"
            if not ok then bucketState.claimSafe = false end
        end
    end
    if n > 0 or dpsN > 0 or complete then
        LogEvent("RX", "mesh bucket %s%d for %s: %d build(s), %d record(s)",
            kind, bucket, tostring(entry.requester), n, dpsN)
    end
    return complete, bucketState.claimSafe ~= false,
        progressed or n > 0 or dpsN > 0, why
end

local function HandleRequest(requester, peerBuildHash, peerDpsHash, requestId)
    if requester == MyName() then
        LogEvent("RX","ignoring own request (no echo loop)")
        return true
    end
    peerBuildHash, peerDpsHash = peerBuildHash or "0", peerDpsHash or "0"
    requestId = requestId or ("legacy-"..tostring(requester).."-"..tostring(math.floor(Now())))
    local key=tostring(requester)..":"..tostring(requestId)
    local prior = pendingResponses[key]
    if prior then
        if tostring(prior.peerBuildWireHash or prior.peerBuildHash)
                ~= tostring(peerBuildHash)
            or tostring(prior.peerDpsHash) ~= tostring(peerDpsHash) then
            LogEvent("RX", "REJECT conflicting request metadata for %s", key)
            return false
        end
        return true
    end
    if TableCount(pendingResponses) >= MAX_PENDING_RESPONSES then
        stats.pendingOverflowRejected = (stats.pendingOverflowRejected or 0) + 1
        LogEvent("RX", "REJECT newest request from %s: pending cap %d",
            tostring(requester), MAX_PENDING_RESPONSES)
        return false
    end
    pendingResponses[key]={
        key=key, requester=requester, requestId=requestId,
        peerBuildWireHash=peerBuildHash, peerDpsHash=peerDpsHash,
        createdAt=Now(), lastActiveAt=Now(), prepared=false,
        remaining=StableDelay(key..":prepare:"..MyName()),
        buildProgress={}, dpsProgress={}, bucketCursor=0,
    }
    LogEvent("RX","mesh request from %s scheduled (id=%s)",
        tostring(requester),tostring(requestId))
    return true
end

function Responder.PrepareResponseEntry(entry)
    local localDeltaHash, myDpsHash = DeltaBuildHash(), CurrentDpsHash()
    local peerWireBuckets = SplitHashes(entry.peerBuildWireHash)
    local comparablePeerHash, buildMode
    if #peerWireBuckets == BUILD_BUCKETS + 1
        and tostring(peerWireBuckets[BUILD_BUCKETS + 1]) == CatalogToken() then
        local peerDelta = {}
        for i = 1, BUILD_BUCKETS do peerDelta[i] = peerWireBuckets[i] end
        comparablePeerHash = table.concat(peerDelta, ",")
        buildMode = "delta"
    elseif #peerWireBuckets == BUILD_BUCKETS then
        -- Legacy bucket hashes may describe a library with no bundled baseline.
        -- Comparing them directly to our delta is safe; any mismatch still
        -- sends only bounded overlay/tombstone candidates.
        comparablePeerHash = entry.peerBuildWireHash
        buildMode = "compat"
        Responder.stats.compatRequests = Responder.stats.compatRequests + 1
    else
        -- Compatibility peers reconcile only the mutable overlay/tombstone
        -- delta. Bundled loadouts are obtained explicitly by known ID.
        comparablePeerHash = "0,0,0,0,0,0,0,0"
        buildMode = "compat"
        Responder.stats.compatRequests = Responder.stats.compatRequests + 1
    end
    local peerB, myB = SplitHashes(comparablePeerHash),
        SplitHashes(localDeltaHash)
    local peerD, myD = SplitHashes(entry.peerDpsHash),
        SplitHashes(myDpsHash)
    local buckets, snapshot = {}, nil
    for i = 1, BUILD_BUCKETS do
        if tostring(peerB[i] or "") ~= tostring(myB[i] or "") then
            snapshot = snapshot or Responder.BuildCandidateSnapshot(localDeltaHash)
            buckets["B"..i]={kind="B", bucket=i,
                hash=tostring(myB[i] or "0"), snapshot=snapshot,
                progress=entry.buildProgress, claimSafe=true,
                claimable=not BucketContainsTombstone(i),
                remaining=BucketDelay(entry.key,"B",i)}
        end
        if tostring(peerD[i] or "") ~= tostring(myD[i] or "") then
            entry.dpsProgress[i] = entry.dpsProgress[i] or {}
            buckets["D"..i]={kind="D", bucket=i,
                hash=tostring(myD[i] or "0"),
                progress=entry.dpsProgress[i], claimable=false,
                remaining=BucketDelay(entry.key,"D",i)}
        end
    end
    entry.peerBuildHash = comparablePeerHash
    entry.buildMode = buildMode
    entry.localDeltaHash = localDeltaHash
    entry.localDpsHash = myDpsHash
    entry.buckets = buckets
    entry.prepared = true
    entry.remaining = nil
    entry.lastActiveAt = Now()
    Responder.stats.entryPreparations =
        Responder.stats.entryPreparations + 1
    if not next(buckets) then
        stats.skippedUpToDate = (stats.skippedUpToDate or 0) + 1
        return false
    end
    return true
end

function Responder.ResetResponseEntry(entry)
    entry.prepared = false
    entry.buckets = nil
    entry.remaining = 0
    entry.bucketCursor = 0
    entry.lastActiveAt = Now()
end

local function HandleClaim(responder, requester, requestId, buildHash, dpsHash)
    local key=tostring(requester)..":"..tostring(requestId)
    if pendingResponses[key] and responder~=MyName() then
        -- Legacy whole-state claims cannot prove that the claimant owns every
        -- DPS row or tombstone represented by the hashes. Keep the packet
        -- readable for older peers, but never let it suppress an authoritative
        -- owner response.
        LogEvent("RX","ignored legacy whole-state claim from %s for owner-only safety",
            tostring(responder))
    end
    return true
end

local function HandleBucketClaim(responder, requester, requestId, kind, bucket, bucketHash)
    if responder==MyName() then return true end
    local key=tostring(requester)..":"..tostring(requestId)
    local entry=pendingResponses[key]; if not entry then return true end
    local id=tostring(kind)..tostring(tonumber(bucket) or 0)
    local b=entry.buckets and entry.buckets[id]
    if b and b.claimable ~= false
        and tostring(b.hash)==tostring(bucketHash) then
        entry.buckets[id]=nil
        LogEvent("RX","mesh bucket %s claimed by %s for %s",id,tostring(responder),tostring(requester))
        if not next(entry.buckets) then pendingResponses[key]=nil end
    end
    return true
end

local function PendingExpired(entry)
    local now = Now()
    local createdAt = tonumber(entry and entry.createdAt) or now
    local lastActiveAt = tonumber(entry and entry.lastActiveAt) or createdAt
    return now - createdAt > PENDING_MAX_AGE
        or now - lastActiveAt > PENDING_TTL
end

function Responder.NextReadyBucket(entry)
    local cursor = tonumber(entry.bucketCursor) or 0
    for offset = 1, BUILD_BUCKETS * 2 do
        local ordinal = ((cursor + offset - 1) % (BUILD_BUCKETS * 2)) + 1
        local id = ordinal <= BUILD_BUCKETS and ("B"..ordinal)
            or ("D"..(ordinal - BUILD_BUCKETS))
        local bucketState = entry.buckets and entry.buckets[id]
        if bucketState and (tonumber(bucketState.remaining) or 0) <= 0 then
            return id, bucketState, ordinal
        end
    end
end

function Responder.SelectFairUnit(units)
    if #units == 0 then return nil end
    table.sort(units, function(left, right) return left.key < right.key end)
    local selected = units[1]
    if Responder.fairCursor then
        for _, unit in ipairs(units) do
            if unit.key > Responder.fairCursor then
                selected = unit
                break
            end
        end
    end
    Responder.fairCursor = selected.key
    return selected
end

function Responder.ProcessLoadoutResponse(entry)
    local progressed = false
    if entry.preparedBuild
        and entry.preparedRevision ~= CurrentBuildHash() then
        entry.preparedBuild = nil
        entry.preparedRevision = nil
        progressed = true
    end
    if not entry.preparedBuild then
        local build = CatalogGet(entry.buildId)
        if not build or type(build.echoes) ~= "table" or #build.echoes == 0 then
            return true, false, "loadout unavailable"
        end
        local prepared, why = Responder.PrepareBuild(build, true)
        if not prepared then return true, false, why end
        entry.preparedBuild = prepared
        entry.preparedRevision = CurrentBuildHash()
        progressed = true
    end
    local sent, why = Responder.AdmitBuild(entry.preparedBuild, true)
    if not sent then return false, progressed, why end
    local claimed, claimWhy = EnqueueControl(string.format(
        "%s|%s|%s|%s",CODE_LOADOUT_CLAIM,MyName(),
        entry.requester,entry.buildId))
    if not claimed then
        LogEvent("TX","loadout claim skipped for '%s': %s",
            tostring(entry.buildId),tostring(claimWhy or "control queue full"))
    end
    LogEvent("TX","answered on-demand loadout '%s' for %s",
        tostring(entry.buildId),tostring(entry.requester))
    return true, true
end

local function ProcessPendingResponses(elapsed)
    elapsed = tonumber(elapsed) or 0
    Responder.stats.turns = Responder.stats.turns + 1
    for key,entry in pairs(pendingResponses) do
        if PendingExpired(entry) then
            pendingResponses[key] = nil
        elseif not entry.prepared then
            entry.remaining = (tonumber(entry.remaining) or 0) - elapsed
        else
            for _, bucketState in pairs(entry.buckets or {}) do
                bucketState.remaining =
                    (tonumber(bucketState.remaining) or 0) - elapsed
            end
        end
    end
    for key,entry in pairs(pendingLoadouts) do
        if PendingExpired(entry) then
            pendingLoadouts[key] = nil
        else
            entry.remaining = (tonumber(entry.remaining) or 0) - elapsed
        end
    end

    -- Saturation is a cheap yield: no hash, catalog, sort, validation,
    -- serialization, encoding, or chunk construction occurs below this gate.
    if Responder.Backpressured() then
        Responder.stats.backpressureDeferrals =
            Responder.stats.backpressureDeferrals + 1
        return
    end

    local units = {}
    for key, entry in pairs(pendingResponses) do
        if not entry.prepared then
            if (tonumber(entry.remaining) or 0) <= 0 then
                units[#units + 1] = {key="R|"..key, type="prepare",
                    entryKey=key, entry=entry}
            end
        else
            local id, bucketState, ordinal = Responder.NextReadyBucket(entry)
            if id then
                units[#units + 1] = {key="R|"..key, type="bucket",
                    entryKey=key, entry=entry, id=id,
                    bucketState=bucketState, ordinal=ordinal}
            end
        end
    end
    for key, entry in pairs(pendingLoadouts) do
        if (tonumber(entry.remaining) or 0) <= 0 then
            units[#units + 1] = {key="L|"..key, type="loadout",
                entryKey=key, entry=entry}
        end
    end
    local unit = Responder.SelectFairUnit(units)
    if not unit then return end
    Responder.stats.workUnits = Responder.stats.workUnits + 1
    Responder.stats.lastRequester = unit.entry.requester

    if unit.type == "prepare" then
        if not Responder.PrepareResponseEntry(unit.entry) then
            pendingResponses[unit.entryKey] = nil
        end
        return
    end
    if unit.type == "loadout" then
        local complete, progressed, why =
            Responder.ProcessLoadoutResponse(unit.entry)
        if complete then
            pendingLoadouts[unit.entryKey] = nil
        else
            unit.entry.remaining = why == "sync queue full" and 1 or 0
            if progressed then unit.entry.lastActiveAt = Now() end
        end
        return
    end

    local entry, bucketState = unit.entry, unit.bucketState
    entry.bucketCursor = unit.ordinal
    Responder.stats.lastBucket = unit.id
    local complete, claimSafe, progressed, why = SendBucketResponse(
        entry, bucketState.kind, bucketState.bucket, bucketState)
    if why == "stale candidate snapshot" then
        Responder.ResetResponseEntry(entry)
        return
    end
    if progressed then entry.lastActiveAt = Now() end
    if complete then
        if claimSafe and bucketState.claimable ~= false then
            local claimed, claimWhy = EnqueueControl(string.format(
                "%s|%s|%s|%s|%s|%d|%s",CODE_BUCKET_CLAIM,
                MyName(),entry.requester,entry.requestId,bucketState.kind,
                bucketState.bucket,bucketState.hash))
            if not claimed then
                LogEvent("TX","bucket claim skipped for %s%d: %s",
                    bucketState.kind,bucketState.bucket,
                    tostring(claimWhy or "control queue full"))
            end
        end
        entry.buckets[unit.id] = nil
        if not next(entry.buckets) then pendingResponses[unit.entryKey] = nil end
    else
        bucketState.remaining = why == "sync queue full" and 1 or 0
    end
end

local function HandleDelete(sender, buildId, stamp, originAuthor)
    autoConverge.lastInbound = Now()
    local existing = CatalogGet(buildId)
    -- originAuthor is an optional 5th field; treat empty string same as nil
    local author = tostring((originAuthor and originAuthor ~= "")
        and originAuthor or sender or "")
    if not SamePeer(sender, author) then
        LogEvent("RX", "REJECT relayed delete for '%s' from %s",
            tostring(buildId), tostring(sender))
        return false
    end
    local deleteStamp = tonumber(stamp) or 0
    if not Sync._ValidRemoteEpoch(deleteStamp, 1) then
        LogEvent("RX", "REJECT invalid delete stamp for '%s' from %s",
            tostring(buildId), tostring(sender))
        return false
    end
    local tomb = { stamp=deleteStamp, author=author }
    local prior = tombstones[buildId]
    if prior and TombStamp(prior) >= tomb.stamp then return true end
    if not existing then
        LogEvent("RX", "REJECT unprovable tombstone for unknown build '%s'",
            tostring(buildId))
        return false
    end
    if existing.isMine then
        LogEvent("RX","ignoring delete for MY build '%s' relayed by %s",
            tostring(existing.title), tostring(sender))
        return false
    end
    if not SamePeer(existing.author, sender) then
        LogEvent("RX","REJECT delete of '%s': origin %s is not the author (%s)",
            tostring(existing.title), author, tostring(existing.author))
        return false
    end
    CatalogSetTombstone(buildId, tomb)
    tombstones[buildId] = tomb
    seenRemoteIds[buildId] = nil
    LogEvent("RX","DELETED '%s' from origin %s (relay %s)",
        tostring(existing.title), author, tostring(sender))
    Sync.RequestDataViewRefresh()
    Sync._RequestRetention("remote delete received")
    return true
end

-- CHAT_MSG_CHANNEL handler. The wire has | escaped to || on send;
-- since none of our fields ever contain a literal |, collapsing ||→|
-- is unambiguous.
local function SplitWire(text)
    local parts, start = {}, 1
    while true do
        if #parts >= 8 then return nil end
        local pos = text:find("|", start, true)
        if not pos then
            parts[#parts + 1] = text:sub(start)
            return parts
        end
        parts[#parts + 1] = text:sub(start, pos - 1)
        start = pos + 1
    end
end

local function RejectIncoming(reason)
    stats.malformedRejected = (stats.malformedRejected or 0) + 1
    LogEvent("RX", "REJECT envelope: %s", tostring(reason or "malformed"))
    return false
end

local function AcceptPeer(sender, version)
    local parsed = version and Nexus.Version and Nexus.Version.Parse
        and Nexus.Version.Parse(version) or nil
    local marked = MarkPeer(sender, parsed and parsed.normalized or nil)
    if marked and parsed and Nexus.Updates and Nexus.Updates.Observe then
        pcall(Nexus.Updates.Observe, parsed, sender)
    end
    return true
end

function Sync.HandleIncoming(text, sender)
    local allowed, why = Sync._TransportAllowed()
    if not allowed then
        stats.ignoredOutsideWindow = (stats.ignoredOutsideWindow or 0) + 1
        suspendReason = tostring(why or "policy")
        return false
    end
    if type(text) ~= "string" or #text > MAX_WIRE_BYTES
        or text:find("[%c]") then return RejectIncoming("invalid wire length") end
    text = text:gsub("||", "|")
    local parts = SplitWire(text)
    if not parts then return RejectIncoming("too many fields") end
    local code = parts[1]
    if not PEER_PROTOCOL_CODES[code] then
        if code and code ~= "" then
            LogEvent("RX","unknown code '%s'", tostring(code))
        end
        return false
    end

    local protocolSender = parts[2]
    local actualSender = sender or protocolSender
    if not ValidPeerName(protocolSender) or not ValidPeerName(actualSender)
        or not SameTransportSender(protocolSender, actualSender) then
        LogEvent("RX", "DROP sender mismatch: wire=%s transport=%s",
            tostring(protocolSender), tostring(actualSender))
        return RejectIncoming("sender mismatch")
    end
    parts[2] = actualSender
    protocolSender = actualSender

    if code == CODE_PRESENCE then
        if #parts ~= 3 or not ValidVersion(parts[3]) then
            return RejectIncoming("invalid presence")
        end
        return AcceptPeer(protocolSender, parts[3])
    end

    if code == CODE_REQUEST then
        if #parts < 2 or #parts > 6
            or (parts[3] ~= nil and parts[3] ~= "" and not ValidHash(parts[3]))
            or (parts[4] ~= nil and parts[4] ~= "" and not ValidHash(parts[4]))
            or (parts[5] ~= nil and parts[5] ~= ""
                and not ValidIdentifier(parts[5], MAX_REQUEST_ID_BYTES))
            or (parts[6] ~= nil and not ValidVersion(parts[6])) then
            return RejectIncoming("invalid request")
        end
        local accepted = HandleRequest(protocolSender,
            (parts[3] and parts[3] ~= "") and parts[3] or "0",
            (parts[4] and parts[4] ~= "") and parts[4] or "0",
            (parts[5] and parts[5] ~= "") and parts[5] or nil)
        if accepted then return AcceptPeer(protocolSender, parts[6]) end
        return false
    end

    if code == CODE_CLAIM then
        if #parts ~= 6 or not ValidPeerName(parts[3])
            or not ValidIdentifier(parts[4], MAX_REQUEST_ID_BYTES)
            or not ValidField(parts[5], MAX_HASH_BYTES, false)
            or not ValidField(parts[6], MAX_HASH_BYTES, false) then
            return RejectIncoming("invalid legacy claim")
        end
        HandleClaim(protocolSender, parts[3], parts[4], parts[5], parts[6])
        return AcceptPeer(protocolSender)
    end

    if code == CODE_BUCKET_CLAIM then
        local bucket = tonumber(parts[6])
        if #parts ~= 7 or not ValidPeerName(parts[3])
            or not ValidIdentifier(parts[4], MAX_REQUEST_ID_BYTES)
            or (parts[5] ~= "B" and parts[5] ~= "D")
            or not bucket or bucket ~= math.floor(bucket)
            or bucket < 1 or bucket > BUILD_BUCKETS
            or not ValidHash(parts[7]) then
            return RejectIncoming("invalid bucket claim")
        end
        HandleBucketClaim(protocolSender, parts[3], parts[4], parts[5],
            bucket, parts[7])
        return AcceptPeer(protocolSender)
    end

    if code == CODE_DELETE then
        if (#parts ~= 4 and #parts ~= 5)
            or not ValidIdentifier(parts[3], MAX_BUILD_ID_BYTES)
            or not ValidIntegerText(parts[4], 1)
            or (parts[5] ~= nil and parts[5] ~= ""
                and not ValidPeerName(parts[5])) then
            return RejectIncoming("invalid delete")
        end
        if HandleDelete(protocolSender, parts[3], parts[4], parts[5]) then
            return AcceptPeer(protocolSender)
        end
        return false
    end

    if code == CODE_INDEX then
        if #parts ~= 3 or not ValidField(parts[3], MAX_CHUNK_BYTES, false) then
            return RejectIncoming("invalid build summary")
        end
        local raw = Codec.Base64Decode(parts[3])
        local data = raw and Codec.JSONDecode(raw)
        local accepted, changed = StoreSummary(data, protocolSender)
        if not accepted then return RejectIncoming("rejected build summary") end
        autoConverge.lastInbound = Now()
        if changed then Sync.RequestDataViewRefresh() end
        return AcceptPeer(protocolSender)
    end

    if code == CODE_LOADOUT_REQ then
        if #parts ~= 3
            or not ValidIdentifier(parts[3], MAX_BUILD_ID_BYTES) then
            return RejectIncoming("invalid loadout request")
        end
        local requester, buildId = protocolSender, parts[3]
        if requester ~= MyName() then
            local key = tostring(requester)..":"..tostring(buildId)
            if not pendingLoadouts[key] then
                if TableCount(pendingLoadouts) >= MAX_PENDING_LOADOUTS then
                    stats.pendingOverflowRejected =
                        (stats.pendingOverflowRejected or 0) + 1
                    return false
                end
                pendingLoadouts[key] = { key=key, requester=requester,
                    buildId=buildId, createdAt=Now(), lastActiveAt=Now(),
                    remaining=StableDelay(key..":"..MyName()) }
            end
        end
        return AcceptPeer(protocolSender)
    end

    if code == CODE_LOADOUT_CLAIM then
        if #parts ~= 4 or not ValidPeerName(parts[3])
            or not ValidIdentifier(parts[4], MAX_BUILD_ID_BYTES) then
            return RejectIncoming("invalid loadout claim")
        end
        local requester, buildId = parts[3], parts[4]
        local key = tostring(requester)..":"..tostring(buildId)
        if protocolSender ~= MyName() and pendingLoadouts[key] then
            pendingLoadouts[key] = nil
            LogEvent("RX","suppressed duplicate loadout response; %s claimed %s",
                tostring(protocolSender), tostring(buildId))
        end
        return AcceptPeer(protocolSender)
    end

    if code == CODE_DPS then
        if #parts ~= 7 then return RejectIncoming("invalid legacy DPS") end
        HandleDps(parts)
        return false
    end

    if code == CODE_DPS2 then
        if #parts ~= 5 then return RejectIncoming("invalid DPS transfer") end
        if HandleDps2(parts) then return AcceptPeer(protocolSender) end
        return false
    end

    if code ~= CODE_BUILD or #parts ~= 6 then
        return RejectIncoming("invalid build transfer")
    end
    local msgSender, buildId, lastMod, chunkSpec, data =
        protocolSender, parts[3], parts[4], parts[5], parts[6]
    if not ValidIdentifier(buildId, MAX_BUILD_ID_BYTES)
        or not ValidIntegerText(lastMod, 0)
        or not ValidField(chunkSpec, 16, false)
        or not ValidField(data, MAX_CHUNK_BYTES, false) then
        return RejectIncoming("invalid build fields")
    end
    local idx, total = chunkSpec:match("^(%d+)/(%d+)$")
    idx, total = tonumber(idx), tonumber(total)
    if not (idx and total and idx >= 1 and total >= 1 and idx <= total
        and total <= MAX_CHUNKS) then
        return RejectIncoming("invalid build chunk geometry")
    end

    autoConverge.lastInbound = Now()
    local key = msgSender..":"..buildId
    local entry = inflight[key]
    if not entry then
        if total == 1 then
            local accepted = HandleComplete(buildId, lastMod, data, msgSender)
            if accepted then return AcceptPeer(protocolSender) end
            return false
        end
        CleanExpiredInflight()
        if not CanStartTransfer(inflight, msgSender) then return false end
        LogEvent("RX","starting %d-chunk build '%s' from %s",
            total, tostring(buildId), tostring(msgSender))
        entry = { chunks={}, total=total, t0=Now(), lastSeen=Now(),
            buildId=buildId, lastMod=lastMod, sender=msgSender,
            bytes=0, received=0 }
        inflight[key] = entry
    end

    if total ~= entry.total or buildId ~= entry.buildId
        or msgSender ~= entry.sender
        or tostring(lastMod) ~= tostring(entry.lastMod) then
        inflight[key] = nil
        return false
    end
    entry.lastSeen = Now()
    local prior = entry.chunks[idx]
    if prior ~= nil then
        if prior ~= data then inflight[key] = nil end
        return false
    end
    if entry.bytes + #data > MAX_ENCODED_BYTES then
        inflight[key] = nil
        return false
    end
    entry.chunks[idx] = data
    entry.bytes = entry.bytes + #data
    entry.received = entry.received + 1
    if entry.received ~= entry.total then return false end
    local full = table.concat(entry.chunks, "", 1, entry.total)
    inflight[key] = nil
    LogEvent("RX","transfer '%s' complete (%d/%d chunks, %d bytes)",
        tostring(buildId), entry.received, entry.total, #full)
    if HandleComplete(buildId, entry.lastMod, full, msgSender) then
        return AcceptPeer(protocolSender)
    end
    return false
end

local function PumpLegacyRecovery(elapsed)
    legacyRecoveryTicker = legacyRecoveryTicker + (tonumber(elapsed) or 0)
    if legacyRecoveryTicker < 1.5 then return end
    legacyRecoveryTicker = 0
    -- Do not pile recovery traffic on top of a large response burst.
    local pending = QueueDepth(sendQueueHead, sendQueueTail)
    if pending > 8 then return end
    local buildId = legacyRecoveryQueue[legacyRecoveryHead]
    if not buildId then
        if legacyRecoveryHead > legacyRecoveryTail then
            legacyRecoveryQueue, legacyRecoveryHead, legacyRecoveryTail = {}, 1, 0
        end
        return
    end
    local build = CatalogGet(buildId)
    if not (build and type(build.echoes) == "table" and #build.echoes > 0) then
        local queued = Enqueue(string.format("%s|%s|%s",
            CODE_LOADOUT_REQ, MyName(), tostring(buildId)))
        if not queued then return end
        receiveWindowUntil = math.max(receiveWindowUntil, Now() + INFLIGHT_GRACE)
        LogEvent("SYNC", "background recovery requested legacy loadout '%s'", tostring(buildId))
    end
    legacyRecoveryQueue[legacyRecoveryHead] = nil
    legacyRecoveryHead = legacyRecoveryHead + 1
end

local function QueueBusy()
    if controlQueue[controlQueueHead] then return true end
    if sendQueue[sendQueueHead] then return true end
    if next(inflight) or next(dpsInflight) then return true end
    if next(pendingResponses) or next(pendingLoadouts) then return true end
    if PendingDeleteCount() > 0 then return true end
    if Responder.manualPublish then return true end
    if legacyRecoveryHead <= legacyRecoveryTail
        and legacyRecoveryQueue[legacyRecoveryHead] then return true end
    return false
end

local function BeginConvergencePass()
    local ok, why = RequestSyncOnce()
    if not ok then return false, why end
    autoConverge.pass = autoConverge.pass + 1
    autoConverge.started = Now()
    autoConverge.lastInbound = Now()
    autoConverge.buildHash = CurrentBuildHash()
    autoConverge.dpsHash = CurrentDpsHash()
    LogEvent("SYNC", "convergence pass %d started", autoConverge.pass)
    return true
end

-- Manual Sync Now uses the same repeat-until-stable convergence loop as login.
-- Existing data is deduplicated, so restarting the loop is safe.
function Sync.RequestSync()
    local mode = Sync.Mode()
    if mode == "off" then return false, "sync mode is Off" end
    -- Do not interrupt a convergence already in progress. The current loop is
    -- already continuing until stable, so another click has nothing to add.
    if autoConverge.active then return true, "already syncing" end
    manualSessionActive = mode == "manual"
    local allowed, blocked = Sync._TransportAllowed()
    if not allowed then
        manualSessionActive = false
        return false, "sync suspended: " .. tostring(blocked or "unsafe context")
    end
    suspendReason = nil
    autoSyncPending = false
    autoConverge.active = true
    autoConverge.pass = 0
    autoConverge.stable = 0
    if mode == "manual" then Responder.StartManualPublish() end
    local ok, why = BeginConvergencePass()
    if not ok then
        autoConverge.active = false
        if mode == "manual" then
            Responder.manualPublish = nil
            manualSessionActive = false
            Sync._LeaveChannel(why or "manual sync failed")
        end
        return false, why
    end
    return true
end

local function SyncWorkCounts()
    local work = {
        control = 0,
        sending = 0,
        receivingBuilds = 0,
        receivingRecords = 0,
        preparing = 0,
        recovery = 0,
        publishing = Responder.manualPublish and 1 or 0,
        pass = tonumber(autoConverge.pass) or 0,
    }
    for i = controlQueueHead, controlQueueTail do
        if controlQueue[i] then work.control = work.control + 1 end
    end
    for i = sendQueueHead, sendQueueTail do
        if sendQueue[i] then work.sending = work.sending + 1 end
    end
    for _ in pairs(inflight) do work.receivingBuilds = work.receivingBuilds + 1 end
    for _ in pairs(dpsInflight) do work.receivingRecords = work.receivingRecords + 1 end
    for _ in pairs(pendingResponses) do work.preparing = work.preparing + 1 end
    for _ in pairs(pendingLoadouts) do work.preparing = work.preparing + 1 end
    work.preparing = work.preparing + PendingDeleteCount()
        + work.publishing
    if legacyRecoveryHead <= legacyRecoveryTail
        and legacyRecoveryQueue[legacyRecoveryHead] then
        for i = legacyRecoveryHead, legacyRecoveryTail do
            if legacyRecoveryQueue[i] then work.recovery = work.recovery + 1 end
        end
    end
    work.outbound = work.control + work.sending
    work.receiving = work.receivingBuilds + work.receivingRecords
    work.total = work.outbound + work.receiving + work.preparing + work.recovery
    return work
end

local function PendingCount()
    return SyncWorkCounts().total
end

function Sync.GetLeaderboardSyncStatus()
    local now = Now()
    local work = SyncWorkCounts()
    local effective = Sync.GetEffectiveState and Sync.GetEffectiveState() or nil
    if effective and (effective.key == "off" or effective.key == "suspended"
        or effective.key == "manual-idle") then
        return effective.key, 0, work.total, work
    end
    if now < (throttlePauseUntil or 0) then
        return "throttled", math.max(1, math.ceil((throttlePauseUntil or 0) - now)), work.total, work
    end
    if autoConverge.active or work.total > 0 or now < receiveWindowUntil then
        return "syncing", 0, work.total, work
    end
    return "idle", 0, 0, work
end

local function UpdateAutoConvergence()
    if not autoConverge.active then return end
    local now = Now()
    if now - autoConverge.started < AUTO_SYNC_MIN_PASS then return end
    if QueueBusy() then return end
    if now - autoConverge.lastInbound < AUTO_SYNC_QUIET then return end

    local changed = tostring(CurrentBuildHash()) ~= tostring(autoConverge.buildHash)
        or tostring(CurrentDpsHash()) ~= tostring(autoConverge.dpsHash)
    if changed then autoConverge.stable = 0 else autoConverge.stable = autoConverge.stable + 1 end

    if autoConverge.stable >= 2 then
        autoConverge.active = false
        LogEvent("SYNC", "convergence complete after %d pass(es)", autoConverge.pass)
        if Sync.Mode() == "manual" then
            manualSessionActive = false
            Sync._LeaveChannel("manual sync complete")
        end
        return
    end
    local ok, why = BeginConvergencePass()
    if not ok then
        autoConverge.started = now
        LogEvent("SYNC", "next convergence pass deferred: %s", tostring(why or "unknown"))
    end
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------

function Sync.PruneTransientState(now)
    now = tonumber(now) or Now()
    local removed = { requestedLoadouts=0, recentBroadcasts=0, hotBuilds=0 }
    for id, requestedAt in pairs(requestedLoadouts) do
        if now - (tonumber(requestedAt) or now) > 240 then
            requestedLoadouts[id] = nil
            removed.requestedLoadouts = removed.requestedLoadouts + 1
        end
    end
    for key, broadcastAt in pairs(recentBuildBroadcast) do
        if now - (tonumber(broadcastAt) or now) > BUILD_BROADCAST_DEDUPE then
            recentBuildBroadcast[key] = nil
            removed.recentBroadcasts = removed.recentBroadcasts + 1
        end
    end
    for id, hot in pairs(hotBuilds) do
        local postedAt = type(hot) == "table" and tonumber(hot.t) or nil
        if postedAt == nil or now - postedAt > HOT_WINDOW then
            hotBuilds[id] = nil
            removed.hotBuilds = removed.hotBuilds + 1
        end
    end
    return removed
end

function Sync.ContextChanged(reason)
    local allowed, blocked = Sync._TransportAllowed()
    if not allowed then
        return Sync._Suspend(blocked or reason or "context changed")
    end
    suspendReason = nil
    if Sync.Mode() == "automatic" then
        if not autoConverge.active then
            autoSyncPending, autoSyncElapsed = true, 0
        end
        if not Sync.IsConnected() then Sync.EnsureChannel() end
    elseif manualSessionActive and not Sync.IsConnected() then
        Sync.EnsureChannel()
    end
    return true
end

function Sync.SetMode(value)
    local policy = Nexus and Nexus.SyncPolicy
    local mode = policy and type(policy.SetMode) == "function"
        and policy.SetMode(value) or tostring(value or "automatic"):lower()
    manualSessionActive = false
    Responder.manualPublish = nil
    autoConverge.active = false
    if mode == "automatic" then
        autoSyncPending, autoSyncElapsed = true, 0
    else
        autoSyncPending = false
    end
    Sync.ContextChanged("mode changed")
    return mode
end

function Sync.GetEffectiveState()
    local mode = Sync.Mode()
    if mode == "off" then
        return { key="off", mode=mode, label="Off", reason="disabled by user" }
    end
    local policy = Nexus and Nexus.SyncPolicy
    local blocked = policy and type(policy.ContextBlock) == "function"
        and policy.ContextBlock() or nil
    if blocked then
        return { key="suspended", mode=mode,
            label=(mode == "manual" and "Manual" or "Automatic")
                .. " - suspended", reason=blocked }
    end
    if mode == "manual" and not manualSessionActive then
        return { key="manual-idle", mode=mode,
            label="Manual - idle", reason="press Sync Now while resting" }
    end
    local work = SyncWorkCounts()
    if autoConverge.active or (tonumber(work.total) or 0) > 0
        or Now() < receiveWindowUntil then
        return { key="syncing", mode=mode,
            label=(mode == "manual" and "Manual" or "Automatic")
                .. " - syncing" }
    end
    return { key="active", mode=mode,
        label=(mode == "manual" and "Manual" or "Automatic")
            .. " - active", reason=suspendReason }
end

function Sync.TombstoneCount()
    local n = 0; for _ in pairs(tombstones) do n=n+1 end; return n
end

function Sync.OnUpdate(elapsed)
    Sync._transientPruneTicker = (Sync._transientPruneTicker or 0)
        + (tonumber(elapsed) or 0)
    if Sync._transientPruneTicker >= 30 then
        Sync._transientPruneTicker = 0
        Sync.PruneTransientState()
    end
    local allowed, blocked = Sync._TransportAllowed()
    if not allowed then
        suspendReason = tostring(blocked or "policy")
        if Sync.IsConnected() or autoConverge.active
            or sendQueue[sendQueueHead] or controlQueue[controlQueueHead]
            or next(inflight) or next(dpsInflight)
            or next(pendingResponses) or next(pendingLoadouts) then
            Sync._Suspend(suspendReason)
        end
        return
    end
    CleanExpiredInflight()
    ProcessPendingResponses(elapsed)
    PumpLegacyRecovery(elapsed)
    if not Sync._pendingDeleteScheduled then PumpPendingDeletes(elapsed) end
    Responder.PumpManualPublish()
    PumpQueue(elapsed)
    if Sync.FlushStatusReply then Sync.FlushStatusReply() end
    if autoSyncPending then
        autoSyncElapsed = autoSyncElapsed + (tonumber(elapsed) or 0)
        if autoSyncElapsed >= AUTO_SYNC_DELAY and Sync.IsConnected() then
            autoSyncPending = false
            autoConverge.active = true
            autoConverge.pass = 0
            autoConverge.stable = 0
            local ok, why = BeginConvergencePass()
            if not ok then
                autoSyncPending = true
                autoSyncElapsed = AUTO_SYNC_DELAY - 1
                LogEvent("SYNC", "automatic login convergence deferred: %s", tostring(why or "unknown"))
            end
        end
    end
    UpdateAutoConvergence()
    -- Retry channel join if chat wasn't ready at login
    if not Sync.IsConnected() and joinAttempts < JOIN_MAX_ATTEMPTS then
        joinRetryTicker = joinRetryTicker + (elapsed or 0)
        if joinRetryTicker >= JOIN_RETRY_INTERVAL then
            joinRetryTicker = 0
            joinAttempts = joinAttempts + 1
            if Sync.EnsureChannel() then
                LogEvent("CHAN","connected on retry #%d", joinAttempts)
            elseif joinAttempts == JOIN_MAX_ATTEMPTS then
                LogEvent("CHAN","gave up after %d attempts (use /wr sync to retry)",
                    joinAttempts)
            end
        end
    end
end

------------------------------------------------------------------------
-- Peer status exchange (dev diagnostic, internal)
-- Sends a compact base64 JSON token via WHISPER on request.
-- Looks identical to a normal sync handshake; decodable only by a dev
-- client that knows the field mapping.  Regular clients never request
-- this and never see anything unusual.
------------------------------------------------------------------------

pendingStatusReply = nil   -- { target, requestId }

local function BuildStatusToken()
    local A  = Adapter
    local D  = Nexus and Nexus.DpsCapture
    local sl = A and A.Slots and A.Slots() or nil
    local wl = A and A.Wishlist and A.Wishlist() or nil
    local me = UnitName and UnitName("player") or "?"
    local lv = UnitLevel and UnitLevel("player") or 0
    local catalog = Catalog()
    local nb = catalog and catalog.Count and catalog.Count() or 0
    local pi = D and D.GetPlayerInfo and D.GetPlayerInfo(me) or nil
    local p = {
        v  = Nexus and Nexus.VERSION or "?",
        s  = sl and sl.maxSlots or 0,
        a  = sl and sl.activeSlot or 0,
        w  = wl and wl.name or "",
        d  = pi and pi.dps or 0,
        dc = pi and pi.category or "",
        b  = nb,
        l  = lv,
    }
    if not (Codec and Codec.JSONEncode and Codec.Base64Encode) then return nil end
    local j = Codec.JSONEncode(p)
    return j and Codec.Base64Encode(j) or nil
end

function Sync.HandleStatusRequest(sender, requestId)
    if not Sync._TransportAllowed() then return false end
    if sender and sender ~= "" then
        pendingStatusReply = { target = sender, requestId = requestId or "0" }
    end
end

function Sync.FlushStatusReply()
    if not Sync._TransportAllowed() then pendingStatusReply = nil; return end
    if not pendingStatusReply then return end
    local rep = pendingStatusReply
    pendingStatusReply = nil
    local token = BuildStatusToken()
    if not token then return end
    local msg = "WLRQ|" .. MyName() .. "|" .. rep.requestId .. "|" .. token
    if #msg > CHAT_LIMIT then msg = msg:sub(1, CHAT_LIMIT) end
    pcall(SendChatMessage, msg, "WHISPER", nil, rep.target)
end

-- Send a status token to a specific player on demand (dev use only).
function Sync.SendStatusTo(target)
    if not Sync._TransportAllowed() then return false end
    if not target or target == "" then return false end
    local token = BuildStatusToken()
    if not token then return false end
    local msg = "WLRQ|" .. MyName() .. "|dev|" .. token
    if #msg > CHAT_LIMIT then msg = msg:sub(1, CHAT_LIMIT) end
    return pcall(SendChatMessage, msg, "WHISPER", nil, target)
end

function Sync.Init(codec, adapter)
    Codec, Adapter = codec, adapter
    sendQueue, sendQueueHead, sendQueueTail = {}, 1, 0
    controlQueue, controlQueueHead, controlQueueTail = {}, 1, 0
    inflight, dpsInflight = {}, {}
    ticker = 0
    throttlePauseUntil, throttleSlowUntil = 0, 0
    lastTransportAttempt = -math.huge
    joinRetryTicker, joinAttempts = 0, 0
    receiveWindowUntil = 0
    lastRequestAt, lastAnsweredAt = -math.huge, -math.huge
    lastSyncNewCount = 0
    for key in pairs(stats) do stats[key] = 0 end
    stats.sent, stats.received, stats.duplicatesSkipped = 0, 0, 0
    stats.malformedRejected, stats.ignoredOutsideWindow = 0, 0
    stats.oversizeDropped, stats.updated, stats.skippedUpToDate = 0, 0, 0
    stats.queueOverflowRejected, stats.pendingOverflowRejected = 0, 0
    stats.baselineSkipped, stats.overlaySent = 0, 0
    Responder.fairCursor = nil
    Responder.candidateCache = nil
    Responder.stats = {
        turns=0, workUnits=0, backpressureDeferrals=0,
        entryPreparations=0, candidateSnapshots=0, candidateSorts=0,
        candidateScans=0, buildSerializations=0, buildAdmissions=0,
        dpsSerializations=0, chunkMessagesBuilt=0, compatRequests=0,
    }
    hotBuilds    = {}  -- clear on init
    recentBuildBroadcast = {}
    Sync._transientPruneTicker = 0
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
    pendingResponses = {}
    pendingLoadouts = {}
    pendingDeletes = {}
    pendingDeleteTicker = 0
    Sync._pendingDeleteScheduled = false
    requestedLoadouts = {}
    legacyRecoveryQueue = {}
    legacyRecoveryHead = 1
    legacyRecoveryTail = 0
    legacyRecoveryTicker = 0
    autoConverge = { active=false, pass=0, stable=0, started=0, lastInbound=0, buildHash=nil, dpsHash=nil }
    -- Keep login initialization constant-time. Existing build timestamps are
    -- resolved lazily in ShouldStore instead of walking the entire library
    -- during PLAYER_ENTERING_WORLD.
    seenRemoteIds = {}
    NexusDB = NexusDB or {}
    if Catalog() and Catalog().Init then
        Catalog().Init(NexusDB, Nexus.BundledBuilds)
    end
    NexusDB.syncTombstones = NexusDB.syncTombstones or {}
    tombstones = NexusDB.syncTombstones
    for id, tomb in pairs(tombstones) do
        if type(tomb) == "table" and tomb.pending then
            pendingDeletes[id] = true
        end
    end
    manualSessionActive = false
    Responder.manualPublish = nil
    suspendReason = nil
    autoSyncPending = Sync.Mode() == "automatic"
    autoSyncElapsed = 0
    local scheduler = Nexus and Nexus.Scheduler
    if scheduler and scheduler.IsInitialized and scheduler.IsInitialized()
        and type(scheduler.Every) == "function" then
        local scheduled = scheduler.Every("sync.pending-deletes", 1, function()
            PumpPendingDeletes(1)
        end)
        Sync._pendingDeleteScheduled = scheduled == true
    end
    InstallTransportFilters()
    Sync.ContextChanged("initialization")
end
