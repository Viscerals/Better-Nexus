-- Stage 26.2 expected red: only strictly decoded, context-accepted inbound
-- traffic may advance session liveness, establish a peer, or mutate state.
Nexus = nil
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua")
dofile("core/SyncInbound.lua")
dofile("core/SyncSession.lua")

local Codec = Nexus.Codec
local Protocol = Nexus.SyncInternals.Protocol.New({
    limits={maxTransferIdBytes=120,maxHashBytes=240,maxVersionBytes=48,
        maxBuildIdBytes=120,maxBuildEchoes=120,maxWireFields=8},
    parseVersion=function(value)
        return tostring(value):match("^%d+%.%d+%.%d+$")
            and {normalized=value} or nil
    end,
    ownerKeyMatchesAuthor=function() return true end,
    isSafeTree=Codec.IsSafeTree,
})
local Factory = assert(Nexus.SyncInternals.Inbound)
local failures = {}
local function Check(ok, message)
    if not ok then failures[#failures + 1] = message end
end

local strictBase64 = Codec.Base64DecodeNetwork or Codec.Base64Decode
local strictJson = Codec.JSONDecodeNetwork or Codec.JSONDecode
Check(strictBase64("TQ==") == "M" and strictBase64("TR==") == nil
        and strictBase64("T===") == nil and strictBase64("=AAA") == nil
        and strictBase64("AA=A") == nil,
    "network Base64 accepted noncanonical padding or unused bits")
local strictJsonRejected = true
for _, value in ipairs({
    '{"a":1}junk', '{"a" 1}', '{"a":"unterminated}',
    '[1,]', '{"a":"\\q"}', '{"a":tru}', '{"a":null}',
    '{"a":1,"a":2}',
}) do
    if strictJson(value) ~= nil then strictJsonRejected = false end
end
Check(strictJsonRejected,
    "network JSON accepted partial, trailing, or malformed syntax")

local validBuild = {id="schema",t="Schema",a="Alice",c="MAGE",m=1,
    d="bounded",lk="https://example.invalid/build",e={{200100,3,1}}}
Check(Protocol.ValidateNetworkPayload(validBuild) ~= nil,
    "strict network schema rejected a canonical compact build")
local invalidSchemas = {
    {id="schema",t=string.rep("T",121),a="Alice",m=1,e={{1,1,1}}},
    {id="schema",t="T",a="Alice",c="MAGE\n",m=1,e={{1,1,1}}},
    {id="schema",t="T",a="Alice",m="1",e={{1,1,1}}},
    {id="schema",t="T",a="Alice",m=1,d=string.rep("D",4001),e={{1,1,1}}},
    {id="schema",t="T",a="Alice",m=1,lk="bad\nlink",e={{1,1,1}}},
    {id="schema",t="T",a="Alice",m=1,e={{1.5,1,1}}},
    {id="schema",t="T",a="Alice",m=1,e={{1,256,1}}},
    {id="schema",t="T",a="Alice",m=1,e={{1,1,121}}},
    {id="schema",t="T",a="Alice",m=1,e={[1]={1,1,1},[3]={2,1,1}}},
}
local invalidSchemaAccepted = false
for _, payload in ipairs(invalidSchemas) do
    if Protocol.ValidateNetworkPayload(payload) ~= nil then
        invalidSchemaAccepted = true
    end
end
Check(not invalidSchemaAccepted,
    "strict network schema normalized an invalid bounded field or sparse Echoes")

local state = {now=100,inbound=0,malformed=0,peers={},builds={},dps={}}
local codes = {presence="WLP",request="WLRQ",claim="WLRC",
    bucketClaim="WLBC",delete="WLD",index="WLI",
    loadoutRequest="WLLQ",loadoutClaim="WLLC",dpsLegacy="WLDPS",
    dps="WLD2",build="WLB"}
local peerCodes = {}
for _, code in pairs(codes) do peerCodes[code] = true end
local inbound = Factory.New({
    codes=codes,peerCodes=peerCodes,bucketCount=8,maxWireBytes=1024,
    maxBuildIdBytes=120,maxRequestIdBytes=80,maxHashBytes=240,
    maxChunkBytes=256,maxChunks=16,maxEncodedBytes=2048,
    maxInflightGlobal=8,maxInflightPerSender=3,
    inflightGrace=5,inflightMaxAge=12,now=function() return state.now end,
    normalizePeerName=function(value) return tostring(value):lower() end,
    sameTransportSender=function(a,b)
        return tostring(a):lower() == tostring(b):lower()
    end,
    samePeer=function(a,b) return tostring(a):lower() == tostring(b):lower() end,
    splitWire=Protocol.SplitWire,validField=Protocol.ValidField,
    validIdentifier=Protocol.ValidIdentifier,
    validTransferIdentifier=Protocol.ValidTransferIdentifier,
    validPeerName=Protocol.ValidPeerName,validHash=Protocol.ValidHash,
    validVersion=Protocol.ValidVersion,validIntegerText=Protocol.ValidIntegerText,
    base64Decode=strictBase64,jsonDecode=strictJson,
    validatePayload=Protocol.ValidateNetworkPayload or Protocol.ValidatePayload,
    validateDpsPayload=Protocol.ValidateNetworkDpsPayload,
    noteDpsRejection=function() end,
    log=function() end,
    rejectIncoming=function() state.malformed=state.malformed+1; return false end,
    noteMalformed=function() state.malformed=state.malformed+1 end,
    acceptPeer=function(sender) state.peers[sender]=true; return true end,
    noteInbound=function() state.inbound=state.inbound+1; return true end,
    handleRequest=function() return true end,
    handleLegacyClaim=function() return false end,
    handleBucketClaim=function() return false end,
    handleDelete=function() return false end,
    handleSummary=function() return false,false end,
    requestDataViewRefresh=function() end,
    handleLoadoutRequest=function() return false end,
    handleLoadoutClaim=function() return false end,
    validateDpsRelay=function() return false end,
    commitDps=function(record)
        state.dps[#state.dps+1]=record
        return true
    end,
    commitBuild=function(build)
        state.builds[#state.builds+1]=build
        return true
    end,
})

-- Unknown channel text, even if oversized, is not malformed Nexus traffic.
local malformedBefore = state.malformed
assert(not inbound.HandleIncoming(string.rep("human chat ", 120), "Alice"))
Check(state.malformed == malformedBefore,
    "unknown channel traffic inflated malformed Nexus counters")

-- The first well-formed chunk is accepted progress. The final malformed
-- packet and a conflicting duplicate are not progress and cannot add peers.
assert(not inbound.HandleIncoming("WLB|Alice|bad-final|1|1/2|AAAA", "Alice"))
assert(not inbound.HandleIncoming("WLB|Alice|bad-final|1|2/2|!!!!", "Alice"))
Check(state.inbound == 1 and not state.peers.Alice,
    "ultimately rejected build packet prolonged liveness or created a peer")
local progressBefore = state.inbound
assert(not inbound.HandleIncoming("WLB|Bob|dup|1|1/3|AAAA", "Bob"))
assert(not inbound.HandleIncoming("WLB|Bob|dup|1|1/3|AAAA", "Bob"))
assert(not inbound.HandleIncoming("WLB|Bob|dup|1|1/3|BBBB", "Bob"))
Check(state.inbound == progressBefore + 1 and not state.peers.Bob,
    "conflicting duplicate counted as accepted progress")

-- A decoded build must agree with both envelope identity and timestamp.
local function Encode(value)
    return Codec.Base64Encode(Codec.JSONEncode(value))
end
local mismatched = Encode({id="mismatch",t="Title",a="Carol",m=2,
    e={{200100,3,1}}})
inbound.HandleIncoming(
    "WLB|Carol|mismatch|1|1/1|" .. mismatched, "Carol")
local invalidEcho = Encode({id="invalid-echo",t="Title",a="Carol",m=1,
    e={{200100,"3",0}}})
inbound.HandleIncoming(
    "WLB|Carol|invalid-echo|1|1/1|" .. invalidEcho, "Carol")
Check(#state.builds == 0 and not state.peers.Carol,
    "envelope mismatch or invalid Echo values were normalized and committed")

-- Strict JSON applies to DPS too; trailing bytes cannot reach commit.
local trailingDps = Codec.Base64Encode('{"p":"Dana","d":1}junk')
inbound.HandleIncoming(
    "WLD2|Dana|trailing|1/1|" .. trailingDps, "Dana")
Check(#state.dps == 0 and not state.peers.Dana,
    "trailing DPS JSON reached mutation or peer acceptance")

local coercibleDps = Encode({v=7,h="hash",f="fingerprint",
    e={{spellId="200100",stacks="1"}},c="dummy",d="250000",
    u=60,t=1,p="Dana",l=80,k="MAGE"})
inbound.HandleIncoming(
    "WLD2|Dana|coercible|1/1|" .. coercibleDps, "Dana")
Check(#state.dps == 0 and not state.peers.Dana,
    "coercible DPS schema reached mutation or peer acceptance")

-- Syntactically valid but unsolicited claims cannot manufacture peer state.
inbound.HandleIncoming("WLRC|Claim|Viewer|stale|0|0", "Claim")
inbound.HandleIncoming(
    "WLBC|Claim|Viewer|stale|B|1|0", "Claim")
inbound.HandleIncoming("WLLC|Claim|Viewer|missing", "Claim")
Check(not state.peers.Claim,
    "stale or reconciler-rejected claims established a false peer")

-- The production session gate also requires an active matching request.
local sessionClock, requestMetadata = 200, nil
local session = Nexus.SyncInternals.Session.New({
    receiveWindow=60,inflightGrace=30,requestCooldown=1,
    autoSyncDelay=1,autoSyncMinPass=1,autoSyncQuiet=1,
    maxConvergenceAge=100,maxReceiveAge=80,maxPasses=2,
    joinRetryInterval=10,joinMaxAttempts=2,maxRecoveryQueue=2,
    maxKnownPeers=2,chatLimit=255,requestCode="WLRQ",
    loadoutRequestCode="WLLQ",now=function() return sessionClock end,
    myName=function() return "Viewer" end,
    normalizePeerName=function(value) return tostring(value):lower() end,
    log=function() end,validIdentifier=function() return true end,
    catalogGet=function() end,getCatalog=function() end,
    getDpsCapture=function() end,getAdapter=function() end,getCodec=function() end,
    playerLevel=function() return 80 end,requestVersion=function() return "1.20.0" end,
    statusVersion=function() return "test" end,currentBuildHash=function() return "0" end,
    currentDpsHash=function() return "0" end,
    enqueue=function() return true end,
    enqueueControl=function(_, metadata) requestMetadata=metadata; return true end,
    transportSnapshot=function() return {bulk=0} end,
    transportHasPending=function() return false end,
    inboundHasPending=function() return false end,
    reconcilerHasPending=function() return false end,
    pendingDeleteCount=function() return 0 end,isConnected=function() return true end,
    ensureChannel=function() return true end,sendWhisper=function() end,
})
assert(session.RequestSync())
session.HandleTransportEvent("send_attempted", {}, requestMetadata)
sessionClock = 250
Check(not session.NoteInbound("foreign") and session.ReceiveTimeLeft() == 10,
    "foreign request context extended the active receive window")
Check(session.NoteInbound(requestMetadata.requestId)
        and session.ReceiveTimeLeft() == 30,
    "accepted matching progress did not extend within the absolute boundary")
sessionClock = 281
Check(not session.NoteInbound(requestMetadata.requestId)
        and session.ReceiveTimeLeft() == 0,
    "expired receive context was revived by later traffic")

local counts = inbound.Counts()
Check(counts.total <= 2 and counts.buildBytes + counts.dpsBytes <= 2048 * 2,
    "hostile acceptance probes escaped deterministic inflight/byte bounds")

if #failures > 0 then
    error("EXPECTED RED [Stage 26.2 inbound acceptance]:\n - "
        .. table.concat(failures, "\n - "))
end
print("Stage 26.2 strict inbound acceptance -- OK")
