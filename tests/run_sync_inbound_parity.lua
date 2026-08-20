-- Characterize synchronous inbound ordering, validation, assembly, and owners.
Nexus = nil
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua")
dofile("core/SyncInbound.lua")

local Codec = Nexus.Codec
local Protocol = Nexus.SyncInternals.Protocol.New({
    limits={
        maxTransferIdBytes=120, maxHashBytes=240, maxVersionBytes=48,
        maxBuildIdBytes=120, maxBuildEchoes=80, maxWireFields=8,
    },
    parseVersion=function(value)
        if tostring(value):match("^%d+%.%d+%.%d+") then
            return {normalized=value}
        end
    end,
    ownerKeyMatchesAuthor=function() return true end,
    isSafeTree=Codec.IsSafeTree,
})
local Factory = assert(Nexus.SyncInternals.Inbound)

local function AssertEqual(actual, expected, label)
    assert(actual == expected, string.format("%s: expected %s, got %s",
        tostring(label), tostring(expected), tostring(actual)))
end

local function NewHarness(overrides)
    overrides = overrides or {}
    local state = {
        now=0, order={}, accepted={}, builds={}, dps={}, summaries={},
        deletes={}, claims={}, loadouts={}, refreshes=0, inbound=0,
        malformed=0, logs={}, requests={}, mutations=0,outcomes={},
    }
    local codes = {
        presence="WLP", request="WLRQ", claim="WLRC",
        bucketClaim="WLBC", delete="WLD", index="WLI",
        loadoutRequest="WLLQ", loadoutClaim="WLLC",
        dpsLegacy="WLDPS", dps="WLD2", build="WLB",
    }
    local peerCodes = {}
    for _, code in pairs(codes) do peerCodes[code] = true end
    local inbound = Factory.New({
        codes=codes, peerCodes=peerCodes, bucketCount=8,
        maxWireBytes=overrides.maxWireBytes or 1024,
        maxBuildIdBytes=120, maxRequestIdBytes=80, maxHashBytes=240,
        maxChunkBytes=overrides.maxChunkBytes or 256,
        maxChunks=overrides.maxChunks or 16,
        maxEncodedBytes=overrides.maxEncodedBytes or 2048,
        maxInflightGlobal=overrides.maxInflightGlobal or 8,
        maxInflightPerSender=overrides.maxInflightPerSender or 3,
        inflightGrace=overrides.inflightGrace or 5,
        inflightMaxAge=overrides.inflightMaxAge or 12,
        now=function() return state.now end,
        normalizePeerName=function(value)
            return tostring(value or ""):lower():match("^[^-]+") or ""
        end,
        sameTransportSender=function(left, right)
            return tostring(left):lower() == tostring(right):lower()
        end,
        samePeer=function(left, right)
            return tostring(left):lower() == tostring(right):lower()
        end,
        splitWire=Protocol.SplitWire,
        validField=Protocol.ValidField,
        validIdentifier=Protocol.ValidIdentifier,
        validTransferIdentifier=Protocol.ValidTransferIdentifier,
        validPeerName=Protocol.ValidPeerName,
        validHash=Protocol.ValidHash,
        validVersion=Protocol.ValidVersion,
        validIntegerText=Protocol.ValidIntegerText,
        base64Decode=Codec.Base64Decode,
        jsonDecode=Codec.JSONDecode,
        validatePayload=function(data)
            if type(data) ~= "table" or type(data.id) ~= "string"
                or type(data.author) ~= "string" then return nil end
            return data
        end,
        validateDpsPayload=function(data) return data end,
        noteDpsRejection=function() end,
        log=function(...)
            state.logs[#state.logs + 1] = {...}
        end,
        rejectIncoming=function(reason)
            state.malformed = state.malformed + 1
            state.logs[#state.logs + 1] = {"reject", reason}
            return false
        end,
        noteMalformed=function()
            state.malformed = state.malformed + 1
        end,
        noteOutcome=function(context, outcome, reason)
            state.outcomes[#state.outcomes + 1] = {
                context=context,outcome=outcome,reason=reason,
            }
        end,
        acceptPeer=function(sender, version)
            state.accepted[#state.accepted + 1] = {sender, version}
            state.order[#state.order + 1] = "peer:" .. sender
            return true
        end,
        noteInbound=function() state.inbound = state.inbound + 1 end,
        handleRequest=function(description)
            state.requests[#state.requests + 1] = description
            state.order[#state.order + 1] = "request:" .. description.requestId
            return true
        end,
        handleLegacyClaim=function(description)
            state.claims[#state.claims + 1] = description
            return true
        end,
        handleBucketClaim=function(description)
            state.claims[#state.claims + 1] = description
            return true
        end,
        handleDelete=function(description)
            state.deletes[#state.deletes + 1] = description
            state.mutations = state.mutations + 1
            return true
        end,
        handleSummary=function(data, sender)
            if type(data) ~= "table" then return false, false end
            state.summaries[#state.summaries + 1] = {data, sender}
            state.mutations = state.mutations + 1
            return true, true
        end,
        requestDataViewRefresh=function()
            state.refreshes = state.refreshes + 1
        end,
        handleLoadoutRequest=function(description)
            state.loadouts[#state.loadouts + 1] = description
            return true
        end,
        handleLoadoutClaim=function(description)
            state.loadouts[#state.loadouts + 1] = description
            return true
        end,
        validateDpsRelay=function(record, sender)
            return overrides.acceptDpsRelay == true
        end,
        commitDps=function(record, sender, relayed)
            state.dps[#state.dps + 1] = {record, sender, relayed}
            state.order[#state.order + 1] = "dps:" .. tostring(record.id)
            state.mutations = state.mutations + 1
            return true
        end,
        commitBuild=function(payload, sender)
            state.builds[#state.builds + 1] = {payload, sender}
            state.order[#state.order + 1] = "build:" .. payload.id
            state.mutations = state.mutations + 1
            return true
        end,
    })
    return inbound, state, codes
end

local function Encode(value)
    return Codec.Base64Encode(Codec.JSONEncode(value))
end

local function Chunks(value, count)
    local out, size = {}, math.ceil(#value / count)
    for index = 1, count do
        out[index] = value:sub((index - 1) * size + 1, index * size)
    end
    return out
end

-- A sustained 100-message request burst is processed synchronously in order.
local ordered, os = NewHarness()
for index = 1, 100 do
    local sender, requestId = "Peer" .. index, "r" .. index
    assert(ordered.HandleIncoming(string.format(
        "WLRQ|%s|0|0|%s|1.20.0", sender, requestId), sender))
end
AssertEqual(#os.requests, 100, "all burst requests delivered")
AssertEqual(#os.accepted, 100, "all burst peers accepted")
AssertEqual(#os.order, 200, "synchronous callback pairs")
for index = 1, 100 do
    AssertEqual(os.order[(index - 1) * 2 + 1], "request:r" .. index,
        "request arrival order " .. index)
    AssertEqual(os.order[(index - 1) * 2 + 2], "peer:Peer" .. index,
        "peer acceptance order " .. index)
end
AssertEqual(ordered.Counts().total, 0, "requests are not queued inbound")

-- Interleaved build transfers commit once, in completion order.
local transfers, ts = NewHarness()
local buildA = Chunks(Encode({id="a", author="Alice",lastModified=1}), 3)
local buildB = Chunks(Encode({id="b", author="Bob",lastModified=1}), 2)
assert(not transfers.HandleIncoming("WLB|Alice|a|1|1/3|" .. buildA[1], "Alice"))
assert(not transfers.HandleIncoming("WLB|Bob|b|1|1/2|" .. buildB[1], "Bob"))
assert(not transfers.HandleIncoming("WLB|Alice|a|1|2/3|" .. buildA[2], "Alice"))
assert(transfers.HandleIncoming("WLB|Bob|b|1|2/2|" .. buildB[2], "Bob"))
assert(transfers.HandleIncoming("WLB|Alice|a|1|3/3|" .. buildA[3], "Alice"))
AssertEqual(#ts.builds, 2, "two interleaved builds committed")
AssertEqual(ts.order[1], "build:b", "first completed build commits first")
AssertEqual(ts.order[3], "build:a", "second completed build commits second")
AssertEqual(transfers.Counts().builds, 0, "completed build state released")

-- DPS chunks retain sender binding and commit exactly once.
local dpsPayload = Chunks(Encode({id="d1", p="Dora", d=123}), 2)
assert(not transfers.HandleIncoming("WLD2|Dora|d1|1/2|"
    .. dpsPayload[1], "Dora"))
assert(transfers.HandleIncoming("WLD2|Dora|d1|2/2|"
    .. dpsPayload[2], "Dora"))
AssertEqual(#ts.dps, 1, "DPS transfer committed once")
local badOwner = Encode({id="d2", p="Mallory", d=321})
assert(not transfers.HandleIncoming("WLD2|Dora|d2|1/1|"
    .. badOwner, "Dora"))
AssertEqual(#ts.dps, 1, "DPS owner mismatch rejected")

local relayTransfers, relayState = NewHarness({acceptDpsRelay=true})
local relayPayload = Encode({id="relay",p="Origin",d=456,
    x={n="Viewer",i="request",b=1}})
assert(relayTransfers.HandleIncoming("WLD2|Relay|relay|1/1|"
    .. relayPayload, "Relay"))
assert(#relayState.dps == 1 and relayState.dps[1][3] == true,
    "validated DPS relay context did not reach the distinct commit path")

-- Identical duplicate chunks make no progress; conflicts destroy the transfer.
local duplicate, ds = NewHarness()
local dup = Chunks(Encode({id="dup", author="Alice",lastModified=1}), 2)
assert(not duplicate.HandleIncoming("WLB|Alice|dup|1|1/2|" .. dup[1], "Alice"))
assert(not duplicate.HandleIncoming("WLB|Alice|dup|1|1/2|" .. dup[1], "Alice"))
assert(not duplicate.HandleIncoming("WLB|Alice|dup|1|1/2|changed", "Alice"))
assert(not duplicate.HandleIncoming("WLB|Alice|dup|1|2/2|" .. dup[2], "Alice"))
AssertEqual(#ds.builds, 0, "conflicting duplicate never commits")

-- Shared per-sender/global caps and both expiry deadlines stay bounded.
local bounded, bs = NewHarness({maxInflightGlobal=2,
    maxInflightPerSender=2, inflightGrace=2, inflightMaxAge=4})
assert(not bounded.HandleIncoming("WLB|Alice|one|1|1/2|a", "Alice"))
assert(not bounded.HandleIncoming("WLD2|Alice|two|1/2|a", "Alice"))
assert(not bounded.HandleIncoming("WLB|Alice|three|1|1/2|a", "Alice"))
AssertEqual(bounded.Counts().total, 2, "combined inflight cap")
bs.now = 3
bounded.CleanExpired()
AssertEqual(bounded.Counts().total, 0, "idle transfer expiry")
local aged, ageState = NewHarness({inflightGrace=10, inflightMaxAge=4})
assert(not aged.HandleIncoming("WLB|Alice|age|1|1/2|a", "Alice"))
ageState.now = 5
aged.CleanExpired()
AssertEqual(aged.Counts().total, 0, "absolute transfer expiry")

-- Aggregate byte overflow releases the transfer without committing partial data.
local oversize, ovs = NewHarness({maxChunkBytes=80, maxEncodedBytes=100})
local sixty = string.rep("a", 60)
assert(not oversize.HandleIncoming("WLB|Alice|big|1|1/2|" .. sixty, "Alice"))
assert(not oversize.HandleIncoming("WLB|Alice|big|1|2/2|" .. sixty, "Alice"))
AssertEqual(oversize.Counts().total, 0, "oversize transfer released")
AssertEqual(#ovs.builds, 0, "oversize transfer never commits")

-- A bounded summary field can fail only after its marked request owner was
-- parsed. The rejection remains correlated even when the production wire cap
-- normally makes this defensive limit redundant.
local contextualLimit, cls = NewHarness({maxChunkBytes=4})
assert(not contextualLimit.HandleIncoming(
    "WLI|Bob|abcde|Alice|c1-summary-limit", "Bob"))
AssertEqual(#cls.outcomes, 1, "contextual summary limit outcome count")
AssertEqual(cls.outcomes[1].outcome, "rejected",
    "contextual summary limit outcome")
AssertEqual(cls.outcomes[1].reason, "schema",
    "contextual summary limit reason")
AssertEqual(cls.outcomes[1].context.requestId, "c1-summary-limit",
    "contextual summary limit request owner")

-- Valid control routes preserve descriptions and accepted legacy behavior.
local controls, cs = NewHarness()
assert(controls.HandleIncoming("WLP|Alice|1.20.0", "Alice"))
assert(controls.HandleIncoming("WLRC|Alice|Bob|r1|0|0", "Alice"))
assert(controls.HandleIncoming("WLBC|Alice|Bob|r1|B|1|0", "Alice"))
assert(controls.HandleIncoming("WLD|Alice|build|1|Alice", "Alice"))
local summary = Encode({id="summary"})
assert(controls.HandleIncoming("WLI|Alice|" .. summary, "Alice"))
assert(controls.HandleIncoming("WLLQ|Alice|build", "Alice"))
assert(controls.HandleIncoming("WLLC|Alice|Bob|build", "Alice"))
assert(not controls.HandleIncoming("WLDPS|Alice|build|Alice|1|1|dummy", "Alice"))
AssertEqual(#cs.claims, 2, "legacy and bucket claims routed")
AssertEqual(#cs.deletes, 1, "delete routed")
AssertEqual(#cs.summaries, 1, "summary routed")
AssertEqual(cs.refreshes, 1, "changed summary refreshes once")
AssertEqual(#cs.loadouts, 2, "loadout request and claim routed")

-- Rejected traffic cannot reach mutation/commit/peer callbacks.
local hostile, hs = NewHarness()
local invalid = {
    {"WLP|Wire|1.20.0", "Transport"},
    {"WLB|Alice|bad id|1|1/1|x", "Alice"},
    {"WLRQ|Alice|not-a-hash", "Alice"},
    {"WLD|Alice|build|0", "Alice"},
    {"UNKNOWN|Alice", "Alice"},
    {string.rep("x", 1025), "Alice"},
}
for _, item in ipairs(invalid) do
    assert(not hostile.HandleIncoming(item[1], item[2]))
end
AssertEqual(hs.mutations, 0, "prevalidation rejects before represented mutation")
AssertEqual(#hs.accepted, 0, "prevalidation rejects before peer authority")
AssertEqual(#hs.requests, 0, "prevalidation rejects before request scheduling")
AssertEqual(hostile.Counts().total, 0, "prevalidation rejects before assembly")

hostile.Reset()
AssertEqual(hostile.Counts().total, 0, "reset clears only inbound session state")

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local inboundSource = Read("core/SyncInbound.lua")
local syncSource = Read("core/Sync.lua")
assert(inboundSource:find(
    "local buildInflight, dpsInflight = {}, {}", 1, true),
    "SyncInbound owns both transfer tables")
assert(not syncSource:find("local inflight", 1, true)
    and not syncSource:find("local dpsInflight", 1, true),
    "Sync no longer owns transfer tables")
assert(syncSource:find(
    "return Inbound.HandleIncoming(text, sender)", 1, true),
    "Sync HandleIncoming is a thin synchronous delegate")
for _, forbidden in ipairs({"Enqueue", "SendChatMessage", "NexusDB",
        "BuildCatalog", "DpsCapture", "GameAdapter", "ProjectEbonhold",
        "tombstones", "CatalogPut", "ReceiveRecord", "coroutine"}) do
    assert(not inboundSource:find(forbidden, 1, true),
        "SyncInbound boundary excludes " .. forbidden)
end
local toc = Read("Nexus.toc")
local reconcilerAt = assert(toc:find("core\\SyncReconciler.lua", 1, true))
local inboundAt = assert(toc:find("core\\SyncInbound.lua", reconcilerAt, true))
local syncAt = assert(toc:find("core\\Sync.lua", inboundAt, true))
assert(reconcilerAt < inboundAt and inboundAt < syncAt,
    "Sync inbound load order drifted")

print("synchronous Sync inbound ordering, validation, and assembly -- OK")
