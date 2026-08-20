-- Active Sync response work must remain bounded and durable near saturation.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/BuildHashCache.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")

local Sync = Nexus.Sync
local Catalog = Nexus.BuildCatalog
local HashCache = Nexus.BuildHashCache
local clock = 1000
GetTime = function() return clock end
time = function() return 50000 end
UnitName = function() return "Alice" end
GetNormalizedRealmName = function() return "Ebonhold" end

local function Pump(steps, elapsed)
    elapsed = elapsed or 0.2
    for _ = 1, steps do
        clock = clock + elapsed
        Sync.OnUpdate(elapsed)
    end
end

local function Bucket(id)
    local hash = 5381
    for index = 1, #id do
        hash = ((hash * 33) + id:byte(index)) % 2147483648
    end
    return (hash % 8) + 1
end

local ids, used = {}, {}
for index = 1, 200 do
    local id = "bounded-overlay-" .. index
    local bucket = Bucket(id)
    if not used[bucket] then
        used[bucket] = true
        ids[#ids + 1] = id
        if #ids == 3 then break end
    end
end
assert(#ids == 3, "test setup did not find three distinct build buckets")

local largeDescription = string.rep("response-payload-", 80)
Nexus.BundledBuilds = {
    schemaVersion=1, catalogVersion="bounded-sync-test-1",
    sourceVersion="1.20.0-beta.1",
    builds={
        ["bundled-exact"]={id="bundled-exact", title="Bundled Exact",
            author="Alice", ownerKey="alice@ebonhold", class="MAGE",
            description=largeDescription, postedAt=1,
            lastModified=1,
            echoes={{spellId=200001,quality=3,stacks=1}}},
    },
}
NexusDB = {
    communityBuilds={
        [ids[1]]={id=ids[1],title="Overlay C",author="Alice",
            ownerKey="alice@ebonhold",ownerVerified=true,realm="ebonhold",
            class="MAGE",
            description="C",postedAt=10,lastModified=10,
            isMine=true,
            echoes={{spellId=200101,quality=3,stacks=1},
                {spellId=200102,quality=3,stacks=1}}},
        [ids[2]]={id=ids[2],title="Small Overlay A",author="Alice",
            ownerKey="alice@ebonhold",ownerVerified=true,realm="ebonhold",
            class="MAGE",description="A",
            postedAt=11,lastModified=11,isMine=true,
            echoes={{spellId=200103,quality=3,stacks=1}}},
        [ids[3]]={id=ids[3],title="Small Overlay B",author="Alice",
            ownerKey="alice@ebonhold",ownerVerified=true,realm="ebonhold",
            class="MAGE",description="B",
            postedAt=12,lastModified=12,isMine=true,
            echoes={{spellId=200104,quality=3,stacks=1}}},
    },
    syncTombstones={}, dpsCapture={},
}

Sync.Init(Nexus.Codec, {})
Pump(260) -- finish login convergence before transport accounting begins
H.sentChatMessages = {}

local currentBuildHash, dpsHash = Sync.GetCompatibilityHashes()
local canonicalDeltaBefore, canonicalLegacyBefore =
    Sync.GetCanonicalBuildHashes()
local token = currentBuildHash:match("([^,]+)$")
local emptyBuckets = "0,0,0,0,0,0,0,0"
local currentEmpty = emptyBuckets .. "," .. token
local differentCatalog = emptyBuckets .. ",deadbeef"

local limits = Sync.WorkState()
assert(limits.maxOutboundQueue == 8192,
    "test requires the documented 8192-packet bulk cap")
for index = 1, limits.maxOutboundQueue - 2 do
    assert(Sync.BroadcastDps("durable-fill-" .. index, "Alice",
        100000 + index, 80, "dummy"),
        "failed to prepare the 8190-packet saturation fixture")
end
assert(Sync.WorkState().sending == 8190,
    "saturation fixture did not stop at 8190/8192")

local oldTemporary, oldNamed = JoinTemporaryChannel, JoinChannelByName
H.joinedChannels = {}
JoinTemporaryChannel = function() end
JoinChannelByName = function() end

local counts = {all=0, delta=0, cursor=0, legacy=0,
    sort=0, json=0, base64=0}
local oldAll, oldDelta, oldCursor = Catalog.All,
    Catalog.DeltaSnapshot, Catalog.SyncDeltaNext
local oldLegacy = HashCache.Legacy
local oldSort = table.sort
local oldJson, oldBase64 = Nexus.Codec.JSONEncode,
    Nexus.Codec.Base64Encode
Catalog.All = function(...)
    counts.all = counts.all + 1
    return oldAll(...)
end
Catalog.DeltaSnapshot = function(...)
    counts.delta = counts.delta + 1
    return oldDelta(...)
end
Catalog.SyncDeltaNext = function(...)
    counts.cursor = counts.cursor + 1
    return oldCursor(...)
end
HashCache.Legacy = function(...)
    counts.legacy = counts.legacy + 1
    return oldLegacy(...)
end
table.sort = function(...)
    counts.sort = counts.sort + 1
    return oldSort(...)
end
Nexus.Codec.JSONEncode = function(...)
    counts.json = counts.json + 1
    return oldJson(...)
end
Nexus.Codec.Base64Encode = function(...)
    counts.base64 = counts.base64 + 1
    return oldBase64(...)
end

assert(Sync.HandleIncoming("WLRQ|LegacyA|" .. emptyBuckets .. "|"
    .. dpsHash .. "|legacy-a|1.19.4", "LegacyA"))
assert(Sync.HandleIncoming("WLRQ|LegacyB|" .. emptyBuckets .. "|"
    .. dpsHash .. "|legacy-b|1.19.4", "LegacyB"))
assert(Sync.HandleIncoming("WLRQ|OtherRelease|" .. differentCatalog .. "|"
    .. dpsHash .. "|other-release|1.20.0-beta.1", "OtherRelease"))
assert(Sync.HandleIncoming("WLRQ|CurrentPeer|" .. currentEmpty .. "|"
    .. dpsHash .. "|current-peer|1.20.0-beta.1", "CurrentPeer"))
assert(Sync.HandleIncoming("WLLQ|ExactPeer|bundled-exact", "ExactPeer"))

local beforeBlocked = Sync.ResponseStats()
clock = clock + 10
local blockedStarted = os.clock()
Sync.OnUpdate(10)
local blockedElapsed = os.clock() - blockedStarted
local afterBlocked = Sync.ResponseStats()
assert(afterBlocked.workUnits == beforeBlocked.workUnits,
    "backpressured update performed response work")
assert(afterBlocked.chunkMessagesBuilt == beforeBlocked.chunkMessagesBuilt,
    "backpressured update constructed response chunks")
assert(counts.all == 0 and counts.delta == 0 and counts.cursor == 0
    and counts.legacy == 0 and counts.sort == 0 and counts.json == 0
    and counts.base64 == 0,
    "backpressured update reached catalog/hash/sort/encoding work")
local blockedState = Sync.WorkState()
assert(blockedState.sending == 8190 and blockedState.pendingResponses == 4
    and blockedState.pendingLoadouts == 1 and blockedState.control == 0,
    "cheap saturation yield changed durable queue or pending work")
assert(blockedElapsed < 0.25,
    "backpressured update exceeded the bounded wall-clock budget")

JoinTemporaryChannel, JoinChannelByName = oldTemporary, oldNamed
H.joinedChannels[Sync.ChannelName()] = 7
local lastWork = afterBlocked.workUnits
local firstResponseOrder, seenResponse, repeatedBeforeFairCycle = {}, {}, false
local maxUpdateElapsed = blockedElapsed
local completed = false
for _ = 1, 270 do
    clock = clock + 1.2
    local started = os.clock()
    Sync.OnUpdate(1.2)
    local duration = os.clock() - started
    if duration > maxUpdateElapsed then maxUpdateElapsed = duration end
    local response = Sync.ResponseStats()
    local deltaWork = response.workUnits - lastWork
    assert(deltaWork >= 0 and deltaWork <= 1,
        "one OnUpdate processed more than one response work unit")
    if deltaWork == 1 then
        local requester = response.lastRequester
        if requester and requester ~= "ExactPeer" then
            if seenResponse[requester] then
                if #firstResponseOrder < 4 then repeatedBeforeFairCycle = true end
            else
                seenResponse[requester] = true
                firstResponseOrder[#firstResponseOrder + 1] = requester
            end
        end
    end
    lastWork = response.workUnits
    local state = Sync.WorkState()
    if state.pendingResponses == 0 and state.pendingLoadouts == 0 then
        completed = true
        break
    end
end
assert(completed, "fair responder did not stop at the bounded pending-work expiry")
assert(#firstResponseOrder == 4 and not repeatedBeforeFairCycle,
    "ready requesters did not receive a fair first response turn")
assert(maxUpdateElapsed < 0.25,
    "resumable response update exceeded the bounded wall-clock budget")

local response = Sync.ResponseStats()
assert(response.entryPreparations == 4,
    "request metadata was prepared more than once without invalidation")
assert(response.candidateSnapshots == 1,
    "identical requesters rebuilt the same delta candidate snapshot")
assert((response.candidateSorts or 0) == 0,
    "response candidates were sorted instead of advanced incrementally")
assert((response.candidateScans or 0) == 5 and counts.cursor == 4,
    "candidate discovery did not remain one-row resumable work")
assert(response.compatRequests == 3,
    "legacy/catalog-mismatch compatibility routing changed")
assert((Sync.Stats().overlaySent or 0) == 7,
    "concurrent transfer cap admitted an unexpected overlay count")
assert(response.buildSerializations == 8
    and response.buildAdmissions == 8,
    "concurrent response cap repeated serialization or exceeded admission")
assert(counts.json >= 8 and counts.base64 == 8,
    "bounded response payloads were encoded more than once per admission")
assert((response.concurrentDeferrals or 0) > 0,
    "valid queued transfers did not defer later response amplification")
assert(response.backpressureDeferrals > afterBlocked.backpressureDeferrals,
    "resumed response work did not exercise queue-full backpressure")
assert(counts.all == 0 and counts.delta == 0 and counts.legacy == 0,
    "response path reached full-catalog materialization or legacy hashing")

local sawCurrentClaim, sawExactClaim = false, false
local bulkSent = 0
for _, message in ipairs(H.sentChatMessages) do
    local wire = message.text:gsub("||", "|")
    if wire:find("^WLBC|Alice|CurrentPeer|current%-peer|B|") then
        sawCurrentClaim = true
    elseif wire:find("^WLLC|Alice|ExactPeer|bundled%-exact$") then
        sawExactClaim = true
    end
    if not wire:find("^WLBC|") and not wire:find("^WLLC|")
        and not wire:find("^WLRC|")
        and not wire:find("^WLRQ|") and not wire:find("^WLLQ|") then
        bulkSent = bulkSent + 1
    end
end
assert(sawCurrentClaim,
    "current-version delta did not converge through admitted bucket payloads")
assert(sawExactClaim,
    "exact-loadout claim was not published after payload admission")
assert(Sync.WorkState().sending + bulkSent
        + (Sync.WorkState().expiredRemoved or 0)
    == 8190 + response.chunkMessagesBuilt,
    string.format("saturation changed, dropped, or duplicated admitted bulk queue data: queued=%d sent=%d expired=%d baseline=%d built=%d",
        Sync.WorkState().sending, bulkSent,
        Sync.WorkState().expiredRemoved or 0,8190,
        response.chunkMessagesBuilt))

Catalog.All, Catalog.DeltaSnapshot, Catalog.SyncDeltaNext =
    oldAll, oldDelta, oldCursor
HashCache.Legacy = oldLegacy
table.sort = oldSort
Nexus.Codec.JSONEncode, Nexus.Codec.Base64Encode = oldJson, oldBase64
local canonicalDeltaAfter, canonicalLegacyAfter =
    Sync.GetCanonicalBuildHashes()
assert(canonicalDeltaAfter == canonicalDeltaBefore
    and canonicalLegacyAfter == canonicalLegacyBefore,
    "bounded responder changed canonical Sync hashes")

print("bounded fair Sync response backpressure and queue durability -- OK")
