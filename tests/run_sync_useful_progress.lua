-- Stage 35.9: request-window liveness is not useful Sync progress.
Nexus = {}
dofile("core/DiagnosticHistory.lua")
dofile("core/SyncDiagnostics.lua")
dofile("core/SyncSession.lua")

local Diagnostics = assert(Nexus.SyncInternals.Diagnostics).New({
    history=Nexus.DiagnosticHistory,now=function() return 100 end,
})
local SessionFactory = assert(Nexus.SyncInternals.Session)

local function NewSession(options)
    options = options or {}
    local state = {clock=100,queued={},connected=options.connected ~= false}
    local session = SessionFactory.New({
        receiveWindow=2,inflightGrace=1,requestCooldown=0,
        autoSyncDelay=6,autoSyncMinPass=1,autoSyncQuiet=1,
        maxConvergenceAge=12,maxReceiveAge=8,maxPasses=1,
        joinRetryInterval=10,joinMaxAttempts=2,maxRecoveryQueue=8,
        maxKnownPeers=8,chatLimit=255,requestCode="WLRQ",
        loadoutRequestCode="WLLQ",now=function() return state.clock end,
        myName=function() return "Alice" end,
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
            if options.queueFailure then return false, options.queueFailure end
            state.queued[#state.queued + 1] = {message=message,metadata=metadata}
            return true
        end,
        enqueue=function(message, metadata)
            state.queued[#state.queued + 1] = {message=message,metadata=metadata}
            return true
        end,
        transportSnapshot=function() return {bulk=0,control=0} end,
        isConnected=function() return state.connected end,
        ensureChannel=function() return false end,
        sendWhisper=function() end,
        noteRequestOutcome=function(snapshot)
            Diagnostics.UpdateRequestOutcome(snapshot)
        end,
    })
    state.session = session
    return state
end

local active = NewSession()
assert(active.session.RequestSync())
local request = assert(active.queued[1])
assert(active.session.HandleTransportEvent("send_attempted", {}, request.metadata))
local requestId = request.metadata.requestId
local started = active.session.StatusSnapshot()
assert(started.requestId == requestId and started.queueOutcome == "sent"
        and started.useful == false and started.new == 0
        and started.updated == 0 and started.shares == 0,
    "request outcome was not initialized as bounded sent/non-useful state")

assert(active.session.NoteInbound(requestId))
assert(active.session.NoteOutcome(requestId, "baseline", "bundled")
        and active.session.NoteOutcome(requestId, "duplicate", "duplicate")
        and active.session.NoteOutcome(requestId, "rejected", "schema"),
    "non-useful request outcomes were not accepted for accounting")
local quiet = active.session.StatusSnapshot()
assert(not quiet.useful and not quiet.peerProgress
        and quiet.baseline == 1 and quiet.duplicates == 1
        and quiet.rejected == 1 and quiet.lastReason == "schema",
    "baseline/duplicate/rejection traffic became useful progress")

assert(not active.session.NoteInbound("foreign-request"),
    "unrelated inbound request identity was admitted")
local unrelated = active.session.StatusSnapshot()
assert(unrelated.unrelated == 1 and unrelated.new == 0
        and unrelated.lastReason == "request_auth",
    "unrelated request traffic was not classified without progress")

assert(active.session.NoteOutcome(requestId, "new", "accepted")
        and active.session.NoteOutcome(requestId, "updated", "accepted")
        and active.session.NoteOutcome(requestId, "share", "accepted"),
    "useful overlay/Share outcomes were rejected")
local useful = active.session.StatusSnapshot()
assert(useful.useful and useful.peerProgress and useful.new == 1
        and useful.updated == 1 and useful.shares == 1
        and active.session.LastSyncNewCount() == 2,
    "accepted overlay/Share outcomes were not separated exactly")

active.clock = active.clock + 13
active.session.UpdateAutoConvergence()
local terminal = active.session.StatusSnapshot()
assert(not terminal.converging and terminal.terminalReason == "expired",
    "bounded timeout did not retain a request-scoped terminal cause")

local aggregate = Diagnostics.Stats()
assert(aggregate.requestId == requestId and aggregate.useful == true
        and aggregate.requestNew == 1 and aggregate.requestUpdated == 1
        and aggregate.requestShares == 1 and aggregate.requestDuplicates == 1
        and aggregate.requestRejected == 1 and aggregate.requestUnrelated == 1
        and aggregate.terminalReason == "expired"
        and aggregate.queueOutcome == "sent",
    "diagnostic aggregate did not mirror the bounded request outcome")

Diagnostics.UpdateRequestOutcome({
    requestId=string.rep("x", 80) .. "|\nsecret",useful=true,
    new=100000,updated=-1,shares=math.huge,duplicates="bad",
    rejected=10000,baseline=1,unrelated=2,lastReason="private reason",
    terminalReason="private terminal",queueOutcome="private queue",
})
local bounded = Diagnostics.Stats()
assert(#bounded.requestId == 64 and not bounded.requestId:find("|", 1, true)
        and bounded.requestNew == 9999 and bounded.requestUpdated == 0
        and bounded.requestShares == 9999 and bounded.requestRejected == 9999
        and bounded.requestLastReason == "none"
        and bounded.terminalReason == "none" and bounded.queueOutcome == "none",
    "request diagnostics accepted unbounded counters, text, or reason values")

local noUseful = NewSession()
assert(noUseful.session.RequestSync())
local noUsefulRequest = noUseful.queued[1]
assert(noUseful.session.HandleTransportEvent("send_attempted", {},
    noUsefulRequest.metadata))
assert(noUseful.session.NoteOutcome(noUsefulRequest.metadata.requestId,
    "baseline", "bundled"))
noUseful.clock = noUseful.clock + 3
noUseful.session.UpdateAutoConvergence()
local noUsefulStatus = noUseful.session.StatusSnapshot()
assert(noUsefulStatus.terminal == "no peer progress"
        and noUsefulStatus.terminalReason == "no_useful_progress"
        and not noUsefulStatus.useful,
    "bounded non-useful request did not explain its terminal cause")

local full = NewSession({queueFailure="sync queue full"})
local ok, why = full.session.RequestSync()
assert(not ok and why == "sync queue full")
local fullStatus = full.session.StatusSnapshot()
assert(fullStatus.queueOutcome == "full"
        and fullStatus.terminalReason == "queue_rejected",
    "queue pressure did not retain bounded terminal diagnostics")

local disconnected = NewSession({connected=false})
local connectedOK = disconnected.session.RequestSync()
local disconnectedStatus = disconnected.session.StatusSnapshot()
assert(not connectedOK and disconnectedStatus.queueOutcome == "disconnected"
        and disconnectedStatus.terminalReason == "disconnected",
    "disconnection did not retain bounded terminal diagnostics")

local retrying = NewSession()
assert(retrying.session.RequestSync())
local retryRequest = retrying.queued[1]
assert(retrying.session.HandleTransportEvent("send_attempted", {},
    retryRequest.metadata))
assert(retrying.session.HandleTransportEvent("send_requeued", {},
    retryRequest.metadata)
        and retrying.session.StatusSnapshot().queueOutcome == "requeued")
assert(retrying.session.HandleTransportEvent("send_attempted", {},
    retryRequest.metadata)
        and retrying.session.StatusSnapshot().queueOutcome == "sent")
assert(retrying.session.HandleTransportEvent("send_dropped",
    {reason="retry exhausted"}, retryRequest.metadata))
local retryStatus = retrying.session.StatusSnapshot()
assert(retryStatus.queueOutcome == "dropped"
        and retryStatus.terminalReason == "send_dropped"
        and not retryStatus.converging,
    "late retry/drop outcome was lost after the first send attempt")

print("sync useful progress: request=1 nonuseful=4 useful=3 terminal=expired/no_useful/drop queue=full/requeued disconnect=yes bounded=yes -- OK")
