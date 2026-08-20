-- Stage 35.9: deterministic protocol-7 two-peer outcome and priority fixture.
Nexus = {}
dofile("core/SyncTransport.lua")
dofile("core/SyncSession.lua")

local SessionFactory = assert(Nexus.SyncInternals.Session)
local TransportFactory = assert(Nexus.SyncInternals.Transport)
local clock = 400

local function NewPeer(name)
    local peer = {name=name,queued={}}
    peer.session = SessionFactory.New({
        receiveWindow=5,inflightGrace=2,requestCooldown=0,
        autoSyncDelay=6,autoSyncMinPass=1,autoSyncQuiet=1,
        maxConvergenceAge=20,maxReceiveAge=12,maxPasses=2,
        joinRetryInterval=10,joinMaxAttempts=2,maxRecoveryQueue=8,
        maxKnownPeers=8,chatLimit=255,requestCode="WLRQ",
        loadoutRequestCode="WLLQ",now=function() return clock end,
        myName=function() return name end,
        normalizePeerName=function(value) return tostring(value):lower() end,
        log=function() end,validIdentifier=function() return true end,
        catalogGet=function() return nil end,getCatalog=function() return nil end,
        getDpsCapture=function() return nil end,getAdapter=function() return nil end,
        getCodec=function() return nil end,playerLevel=function() return 80 end,
        requestVersion=function() return "1.20.0-beta.1" end,
        statusVersion=function() return "test.15" end,
        currentBuildHash=function() return "0,0,0,0,0,0,0,0,catalog" end,
        currentClaimBuildHash=function() return "0,0,0,0,0,0,0,0,catalog" end,
        currentDpsHash=function() return "0,0,0,0,0,0,0,0" end,
        enqueueControl=function(message, metadata)
            peer.queued[#peer.queued + 1] = {message=message,metadata=metadata}
            return true
        end,
        enqueue=function() return true end,
        transportSnapshot=function() return {bulk=0,control=0} end,
        isConnected=function() return true end,ensureChannel=function() return true end,
        sendWhisper=function() end,
    })
    assert(peer.session.RequestSync())
    local request = peer.queued[1]
    assert(peer.session.HandleTransportEvent("send_attempted", {}, request.metadata))
    peer.requestId = request.metadata.requestId
    return peer
end

local alice, bob = NewPeer("Alice"), NewPeer("Bob")
assert(alice.requestId ~= bob.requestId, "peer request identities collided")
assert(alice.session.NoteOutcome(alice.requestId, "baseline", "bundled"))
assert(alice.session.NoteOutcome(alice.requestId, "new", "accepted"))
assert(alice.session.NoteOutcome(alice.requestId, "duplicate", "duplicate"))
assert(not alice.session.NoteOutcome(bob.requestId, "updated", "accepted"))
local a = alice.session.StatusSnapshot()
local b = bob.session.StatusSnapshot()
assert(a.useful and a.new == 1 and a.updated == 0 and a.duplicates == 1
        and a.baseline == 1 and a.unrelated == 1,
    "mixed two-peer outcome classification drifted")
assert(not b.useful and b.new == 0 and b.duplicates == 0
        and b.unrelated == 0,
    "one peer's outcomes leaked into the other request")

local sent, stats = {}, {}
local transport = TransportFactory.New({
    maxBulk=8,maxControl=8,responseHeadroom=1,chatLimit=255,
    sendInterval=1.1,slowInterval=1.75,throttlePause=8,
    throttleSlowTime=45,controlBurstLimit=4,maxAttempts=3,
    now=function() return clock end,
    escapedLen=function(value) return #value end,log=function() end,stats=stats,
    resolveChannel=function() return 7 end,channelLabel=function() return 7 end,
    sendChat=function(payload) sent[#sent + 1] = payload end,
    addMessageFilter=function() end,observe=function() end,
})
local responseMetadata = {requester="Alice",requestId=alice.requestId,
    transferId="overlay-1",expiresAt=clock + 20}
assert(transport.EnqueueBatch({"OVERLAY|1", "OVERLAY|2"}, responseMetadata))
local duplicateOK, duplicateWhy = transport.EnqueueBatch(
    {"OVERLAY|1", "OVERLAY|2"}, responseMetadata)
assert(duplicateOK and duplicateWhy == "duplicate"
        and transport.Snapshot().bulk == 2,
    "one eligible overlay was admitted more than once for one request")
assert(transport.EnqueueControl("CLAIM", {queueClass="claim",requestId="r"}))
assert(transport.EnqueueControl("REQUEST", {queueClass="request",requestId="r"}))
assert(transport.EnqueueControl("SHARE", {queueClass="share",shareId="s"}))
clock = clock + 1.1; transport.Pump(1.1)
clock = clock + 1.1; transport.Pump(1.1)
clock = clock + 1.1; transport.Pump(1.1)
assert(sent[1] == "SHARE" and sent[2] == "REQUEST" and sent[3] == "CLAIM",
    "Share/request/claim priority changed")

print("sync two peer: protocol=7 overlay_once=1 duplicate=1 unrelated=1 share_priority=yes isolation=yes -- OK")
