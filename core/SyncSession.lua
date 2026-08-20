-- Nexus: core/SyncSession.lua
-- Peer, receive-window, recovery, convergence, and status-reply session owner.

Nexus = Nexus or {}
if type(Nexus.SyncInternals) ~= "table" then Nexus.SyncInternals = {} end

local Session = {}
Nexus.SyncInternals.Session = Session

local function Number(value)
    return tonumber(value) or 0
end

local OUTCOME_REASONS = {
    none=true,accepted=true,bundled=true,duplicate=true,malformed=true,
    schema=true,integrity=true,ownership=true,tombstone=true,stale=true,
    request_auth=true,storage=true,queue=true,timeout=true,disconnect=true,
}

local function OutcomeReason(value)
    value = tostring(value or "none")
    return OUTCOME_REASONS[value] and value or "none"
end

function Session.New(options)
    options = options or {}
    local now = assert(options.now, "SyncSession requires now")
    local myName = assert(options.myName, "SyncSession requires myName")
    local normalizePeerName = assert(options.normalizePeerName,
        "SyncSession requires normalizePeerName")
    local log = options.log or function() end

    local receiveWindow = Number(options.receiveWindow)
    local inflightGrace = Number(options.inflightGrace)
    local requestCooldown = Number(options.requestCooldown)
    local autoSyncDelay = Number(options.autoSyncDelay)
    local autoSyncMinPass = Number(options.autoSyncMinPass)
    local autoSyncQuiet = Number(options.autoSyncQuiet)
    local maxConvergenceAge = math.max(1,
        tonumber(options.maxConvergenceAge) or 300)
    local maxReceiveAge = math.max(1,
        tonumber(options.maxReceiveAge) or 180)
    local maxPasses = math.max(1, tonumber(options.maxPasses) or 3)
    local joinRetryInterval = Number(options.joinRetryInterval)
    local joinMaxAttempts = Number(options.joinMaxAttempts)
    local maxRecoveryQueue = Number(options.maxRecoveryQueue)
    local maxKnownPeers = Number(options.maxKnownPeers)
    local cancelRequest = type(options.cancelRequest) == "function"
        and options.cancelRequest or function() return false end
    local noteRequestOutcome = type(options.noteRequestOutcome) == "function"
        and options.noteRequestOutcome or function() end
    local currentClaimBuildHash = type(options.currentClaimBuildHash) == "function"
        and options.currentClaimBuildHash or options.currentBuildHash

    local joinRetryTicker = 0
    local joinAttempts = 0
    local receiveWindowUntil = 0
    local receiveAbsoluteUntil = 0
    local lastRequestAt = -math.huge
    local lastRequestId = nil
    local pendingRequest = nil
    local requestedLoadouts = {}
    local pendingReplacementCount = 0
    local recoveryQueue, recoveryHead, recoveryTail = {}, 1, 0
    local recoveryTicker = 0
    local lastSyncNewCount = 0
    local autoSyncPending, autoSyncElapsed = false, 0
    local autoConverge = {
        active=false, pass=0, stable=0, started=0, lastInbound=0,
        absoluteUntil=0,terminal=nil,buildHash=nil, dpsHash=nil,
        mode=nil,peerProgress=false,peerEquivalent=false,superseded=0,
    }
    local requestOutcome = {
        requestId=nil,useful=false,new=0,updated=0,shares=0,
        duplicates=0,rejected=0,baseline=0,unrelated=0,
        lastReason="none",terminalReason="none",queueOutcome="none",
    }
    local knownPeers = {}
    local pendingStatusReply = nil
    local M = {}

    local function OutcomeSnapshot()
        return {
            requestId=requestOutcome.requestId,
            useful=requestOutcome.useful and true or false,
            new=Number(requestOutcome.new),updated=Number(requestOutcome.updated),
            shares=Number(requestOutcome.shares),
            duplicates=Number(requestOutcome.duplicates),
            rejected=Number(requestOutcome.rejected),
            baseline=Number(requestOutcome.baseline),
            unrelated=Number(requestOutcome.unrelated),
            lastReason=requestOutcome.lastReason or "none",
            terminalReason=requestOutcome.terminalReason or "none",
            queueOutcome=requestOutcome.queueOutcome or "none",
        }
    end

    local function PublishOutcome()
        noteRequestOutcome(OutcomeSnapshot())
    end

    local function ResetOutcome(requestId)
        requestOutcome = {
            requestId=requestId,useful=false,new=0,updated=0,shares=0,
            duplicates=0,rejected=0,baseline=0,unrelated=0,
            lastReason="none",terminalReason="none",queueOutcome="none",
        }
        PublishOutcome()
    end

    local function IncrementOutcome(key)
        requestOutcome[key] = math.min(9999,
            Number(requestOutcome[key]) + 1)
    end

    local function SetTerminal(reason)
        requestOutcome.terminalReason = reason or "none"
        PublishOutcome()
    end

    local function SetQueueOutcome(outcome)
        requestOutcome.queueOutcome = outcome or "none"
        PublishOutcome()
    end

    local function RecoveryCount()
        return math.max(0, recoveryTail - recoveryHead + 1)
    end

    local function ReplacementCount()
        return pendingReplacementCount
    end

    local function CopyReplacement(source)
        if type(source) ~= "table" then return nil end
        return {
            buildId=tostring(source.buildId or ""),
            title=source.title,author=source.author,ownerKey=source.ownerKey,
            class=source.class,lastModified=source.lastModified,
            fingerprintHash=source.fingerprintHash,
            linkHash=source.linkHash,echoCount=source.echoCount,
            autoDps=source.autoDps and true or false,
        }
    end

    function M.MarkPeer(name, version)
        if not name or name == "" then return false end
        if normalizePeerName(name) == normalizePeerName(myName()) then
            return false
        end
        local key = normalizePeerName(name)
        if key == "" then return false end
        local current = now()
        if not knownPeers[key] then
            local count = 0
            for peerKey, peer in pairs(knownPeers) do
                if current - (tonumber(peer.lastSeen) or 0) > 7200 then
                    knownPeers[peerKey] = nil
                else
                    count = count + 1
                end
            end
            if count >= maxKnownPeers then return false end
        end
        local wasKnown = knownPeers[key] ~= nil
        local peer = knownPeers[key] or {}
        local oldName, oldVersion = peer.name, peer.version
        peer.name = tostring(name):match("^([^%-]+)") or tostring(name)
        if version and version ~= "" then peer.version = tostring(version) end
        peer.lastSeen = current
        knownPeers[key] = peer
        if not wasKnown or oldName ~= peer.name or oldVersion ~= peer.version then
            if options.bumpSync then
                options.bumpSync(not wasKnown and "peer added"
                    or "peer identity updated")
            end
        end
        return true
    end

    function M.GetPeerInfo(name)
        local peer = knownPeers[normalizePeerName(name)]
        if not peer then return nil end
        if peer.lastSeen and now() - peer.lastSeen > 7200 then return nil end
        return peer
    end

    function M.IsKnownPeer(name)
        return M.GetPeerInfo(name) ~= nil
    end

    function M.IsReceiving()
        return now() < receiveWindowUntil
    end

    function M.ReceiveTimeLeft()
        local left = receiveWindowUntil - now()
        return left > 0 and left or 0
    end

    function M.AcceptsResponse(requestId)
        return autoConverge.active and now() < receiveAbsoluteUntil
            and type(requestId) == "string"
            and requestId ~= "" and requestId == lastRequestId
    end

    function M.LastSyncNewCount()
        return lastSyncNewCount
    end

    function M.NoteReceived(requestId, outcome)
        outcome = outcome or "new"
        local recorded = M.NoteOutcome(requestId, outcome, "accepted")
        if not recorded and not autoConverge.active
            and (outcome == "new" or outcome == "updated") then
            -- Preserve the lifetime-facing "last sync new" aggregate for an
            -- accepted unsolicited Share outside a manual receive window.
            lastSyncNewCount = lastSyncNewCount + 1
        end
        return recorded
    end

    function M.NoteInbound(requestId)
        local current = now()
        if not autoConverge.active or current >= receiveAbsoluteUntil then
            return false
        end
        -- Requestless protocol-7 traffic is valid ambient input. Only an
        -- explicit matching correlation identity may move the active request's
        -- quiet clock; mismatches are classified by the eventual outcome owner.
        if requestId == nil then
            return false
        end
        if tostring(requestId) ~= tostring(lastRequestId) then
            M.NoteOutcome(requestId, "unrelated", "request_auth")
            return false
        end
        autoConverge.lastInbound = current
        -- A paced changed bucket can outlive the initial compatibility timer.
        -- While this convergence pass is active, bounded inbound work extends
        -- the same quiet boundary used by views and final pass evaluation.
        if autoConverge.active then
            receiveWindowUntil = math.min(receiveAbsoluteUntil,
                math.max(receiveWindowUntil, current + inflightGrace))
        end
        return true
    end

    function M.NoteOutcome(requestId, outcome, reason)
        local current = now()
        if not autoConverge.active or current >= receiveAbsoluteUntil
            or not lastRequestId then
            return false
        end
        if requestId == nil then return false end
        if tostring(requestId) ~= tostring(lastRequestId) then
            IncrementOutcome("unrelated")
            requestOutcome.lastReason = "request_auth"
            PublishOutcome()
            return false
        end
        local useful = outcome == "new" or outcome == "updated"
            or outcome == "share"
        if useful then
            local key = outcome == "share" and "shares" or outcome
            IncrementOutcome(key)
            requestOutcome.useful = true
            autoConverge.peerProgress = true
            if outcome ~= "share" then
                lastSyncNewCount = lastSyncNewCount + 1
            end
        elseif outcome == "duplicate" then
            IncrementOutcome("duplicates")
        elseif outcome == "rejected" then
            IncrementOutcome("rejected")
        elseif outcome == "baseline" then
            IncrementOutcome("baseline")
        elseif outcome == "unrelated" then
            IncrementOutcome("unrelated")
        else
            return false
        end
        requestOutcome.lastReason = OutcomeReason(reason)
        PublishOutcome()
        return true
    end

    function M.NotePeerClaim(requestId, buildHash, dpsHash)
        if not M.AcceptsResponse(requestId) then
            M.NoteOutcome(requestId, "unrelated", "request_auth")
            return false
        end
        if not M.NoteInbound(requestId) then return false end
        local equivalent = tostring(buildHash or "0")
                == tostring(currentClaimBuildHash() or "0")
            and tostring(dpsHash or "0")
                == tostring(options.currentDpsHash() or "0")
        autoConverge.peerEquivalent =
            autoConverge.peerEquivalent or equivalent
        return true
    end

    function M.ClearRequestedLoadout(buildId, promotedStamp)
        local recovery = requestedLoadouts[buildId]
        local replacement = type(recovery) == "table"
            and recovery.replacement or nil
        if replacement and promotedStamp ~= nil
            and Number(replacement.lastModified) > Number(promotedStamp) then
            return false
        end
        if replacement then
            pendingReplacementCount = math.max(0,
                pendingReplacementCount - 1)
        end
        requestedLoadouts[buildId] = nil
        return true
    end

    function M.PendingReplacement(buildId)
        local recovery = requestedLoadouts[buildId]
        return CopyReplacement(type(recovery) == "table"
            and recovery.replacement or nil)
    end

    -- Scalar summaries identify recovery work, not represented builds. Keep
    -- one bounded, session-only winner per build until its exact full payload
    -- is durably accepted by the catalog.
    function M.QueueReplacement(buildId, replacement, requestId)
        if not options.validIdentifier(buildId)
            or type(replacement) ~= "table"
            or tostring(replacement.buildId or "") ~= tostring(buildId)
            or type(replacement.fingerprintHash) ~= "string"
            or type(replacement.lastModified) ~= "number"
            or replacement.lastModified < 0 then
            return false
        end
        local current = now()
        local markedId = type(requestId) == "string"
            and requestId:sub(1, 3) == "c1-" and requestId or nil
        local prior = requestedLoadouts[buildId]
        local priorReplacement = type(prior) == "table"
            and prior.replacement or nil
        local nextStamp = Number(replacement.lastModified)
        local priorStamp = priorReplacement
            and Number(priorReplacement.lastModified) or nil
        if priorStamp and nextStamp <= priorStamp then return false end
        if not priorReplacement and ReplacementCount() >= maxRecoveryQueue then
            if options.rejectRecoveryOverflow then
                return options.rejectRecoveryOverflow(ReplacementCount())
            end
            return false
        end
        local copy = CopyReplacement(replacement)
        if type(prior) == "table" and not prior.sent then
            if not priorReplacement then
                pendingReplacementCount = pendingReplacementCount + 1
            end
            prior.replacement = copy
            prior.requestId = markedId or prior.requestId
            prior.at = current
            return true
        end
        local recovery = {
            buildId=tostring(buildId),requestId=markedId,
            at=current,sent=false,replacement=copy,
        }
        requestedLoadouts[buildId] = recovery
        if not priorReplacement then
            pendingReplacementCount = pendingReplacementCount + 1
        end
        recoveryTail = recoveryTail + 1
        recoveryQueue[recoveryTail] = recovery
        return true
    end

    function M.QueueLegacyRecovery(buildId, requestId)
        if not options.validIdentifier(buildId) then return false end
        local build = options.catalogGet(buildId)
        if build and type(build.echoes) == "table" and #build.echoes > 0 then
            return false
        end
        local current = now()
        local markedId = type(requestId) == "string"
            and requestId:sub(1, 3) == "c1-" and requestId or nil
        local prior = requestedLoadouts[buildId]
        -- A scalar-summary replacement carries a stricter exact identity than
        -- the legacy id-only request. Never downgrade or overwrite that owner.
        if type(prior) == "table" and prior.replacement then return false end
        local priorAt = type(prior) == "table" and prior.at or prior
        if priorAt and current - priorAt < 120 then
            -- A later contextual summary may arrive while the legacy recovery
            -- is still queued.  Upgrade that one bounded owner in place so it
            -- cannot answer the new request under stale identity.
            if markedId and type(prior) == "table" and not prior.sent
                and prior.requestId ~= markedId then
                prior.requestId, prior.at = markedId, current
                return true
            end
            return false
        end
        local depth = RecoveryCount()
        if depth >= maxRecoveryQueue then
            if options.rejectRecoveryOverflow then
                return options.rejectRecoveryOverflow(depth)
            end
            return false
        end
        local recovery = {
            buildId=tostring(buildId),requestId=markedId,
            at=current,sent=false,
        }
        requestedLoadouts[buildId] = recovery
        recoveryTail = recoveryTail + 1
        recoveryQueue[recoveryTail] = recovery
        return true
    end

    function M.PumpRecovery(elapsed)
        recoveryTicker = recoveryTicker + Number(elapsed)
        if recoveryTicker < 1.5 then return end
        recoveryTicker = 0
        local transport = options.transportSnapshot()
        if Number(transport and transport.bulk) > 8 then return end
        local recovery = recoveryQueue[recoveryHead]
        if not recovery then
            if recoveryHead > recoveryTail then
                recoveryQueue, recoveryHead, recoveryTail = {}, 1, 0
            end
            return
        end
        local buildId = type(recovery) == "table" and recovery.buildId
            or recovery
        local requestId = type(recovery) == "table" and recovery.requestId
            or nil
        local build = options.catalogGet(buildId)
        if type(recovery) == "table" and recovery.replacement
            or not (build and type(build.echoes) == "table"
            and #build.echoes > 0) then
            local contextual = type(requestId) == "string"
                and requestId:sub(1, 3) == "c1-"
            local wire = contextual
                and string.format("%s|%s|%s|%s", options.loadoutRequestCode,
                    myName(), tostring(buildId), requestId)
                or string.format("%s|%s|%s", options.loadoutRequestCode,
                    myName(), tostring(buildId))
            local transportRequestId = contextual and requestId
                or "loadout-" .. tostring(buildId)
            local queued, queueWhy = (options.enqueueControl or options.enqueue)(
                wire, {
                    requester=myName(),
                    requestId=transportRequestId,
                    buildId=tostring(buildId),queueClass="request",
                    enqueuedAt=now(),expiresAt=now() + maxReceiveAge,
                })
            if not queued then
                -- Queue pressure is transient; an invalid maximum-field wire is
                -- deterministic and must not retry forever every 1.5 seconds.
                if queueWhy ~= "invalid packet" then return end
                log("SYNC", "legacy loadout request '%s' exceeded wire bounds",
                    tostring(buildId))
            else
                if type(recovery) == "table" then
                    recovery.sent, recovery.at = true, now()
                end
                receiveWindowUntil = math.max(receiveWindowUntil,
                    now() + inflightGrace)
                log("SYNC", "background recovery requested legacy loadout '%s'",
                    tostring(buildId))
            end
        end
        if type(recovery) == "table" then recovery.sent = true end
        recoveryQueue[recoveryHead] = nil
        recoveryHead = recoveryHead + 1
    end

    local function RequestSyncOnce(bypassCooldown)
        if not options.isConnected() and not options.ensureChannel() then
            joinAttempts = 0
            ResetOutcome(nil)
            SetQueueOutcome("disconnected")
            SetTerminal("disconnected")
            log("SYNC", "sync requested but not connected")
            return false, "not connected to the sync channel"
        end
        local current = now()
        if pendingRequest then
            return false, "sync request already queued"
        end
        if not bypassCooldown and current - lastRequestAt < requestCooldown then
            log("SYNC", "sync request ignored (cooldown %.1fs)",
                current - lastRequestAt)
            return false, "please wait a few seconds between syncs"
        end
        lastSyncNewCount = 0
        local buildHash = options.currentBuildHash()
        local dpsHash = options.currentDpsHash()
        local requestId = "c1-" .. tostring(math.floor(current * 1000)) .. "-"
            .. tostring(math.random(1000, 9999))
        ResetOutcome(requestId)
        SetQueueOutcome("queued")
        local expiresAt = math.min(autoConverge.absoluteUntil > current
                and autoConverge.absoluteUntil or current + maxConvergenceAge,
            current + maxConvergenceAge)
        local metadata = {
            requester=myName(),
            requestId=requestId,transferId=requestId,queueClass="request",
            enqueuedAt=current,expiresAt=expiresAt,attempts=0,
        }
        local queued, why = (options.enqueueControl or options.enqueue)(string.format(
            "%s|%s|%s|%s|%s|%s", options.requestCode, myName(),
            buildHash, dpsHash, requestId,
            tostring(options.requestVersion())), metadata)
        if not queued then
            SetQueueOutcome(tostring(why or ""):find("full", 1, true)
                and "full" or "dropped")
            SetTerminal("queue_rejected")
            return false, why or "sync queue full"
        end
        pendingRequest = {id=requestId,queuedAt=current,expiresAt=expiresAt,
            buildHash=buildHash,dpsHash=dpsHash,sentAt=nil}
        log("SYNC", "requested sync queued (build=%s dps=%s id=%s)",
            buildHash, dpsHash, requestId)
        return true
    end

    function M.HandleTransportEvent(kind, fields, metadata)
        local requestId = type(metadata) == "table" and metadata.requestId
            or nil
        local pendingMatches = pendingRequest and tostring(requestId)
            == tostring(pendingRequest.id)
        local activeMatches = autoConverge.active and lastRequestId
            and tostring(requestId) == tostring(lastRequestId)
        if not pendingMatches and not activeMatches then
            return false
        end
        local current = now()
        if kind == "send_attempted" then
            if pendingMatches then
                pendingRequest.sentAt = current
                lastRequestAt = current
                lastRequestId = pendingRequest.id
                receiveAbsoluteUntil = math.min(pendingRequest.expiresAt,
                    current + maxReceiveAge)
                receiveWindowUntil = math.min(receiveAbsoluteUntil,
                    current + receiveWindow)
                autoConverge.lastInbound = current
                pendingRequest = nil
            else
                receiveWindowUntil = math.min(receiveAbsoluteUntil,
                    math.max(receiveWindowUntil, current + receiveWindow))
            end
            SetQueueOutcome("sent")
            log("SYNC", "sync request sent (id=%s); receive window active",
                tostring(lastRequestId))
            return true
        end
        if kind == "send_dropped" then
            pendingRequest = nil
            receiveWindowUntil, receiveAbsoluteUntil = 0, 0
            autoConverge.active = false
            autoConverge.terminal = fields and fields.reason or "send dropped"
            SetQueueOutcome("dropped")
            SetTerminal("send_dropped")
            return true
        end
        if kind == "send_requeued" then
            SetQueueOutcome("requeued")
            return true
        end
        if kind == "send_retry" then
            SetQueueOutcome("retry")
            return true
        end
        return false
    end

    local function BeginConvergencePass(mode, bypassCooldown)
        local ok, why = RequestSyncOnce(bypassCooldown)
        if not ok then return false, why end
        autoConverge.mode = mode or autoConverge.mode
        autoConverge.pass = autoConverge.pass + 1
        autoConverge.started = now()
        autoConverge.lastInbound = now()
        autoConverge.peerProgress = false
        autoConverge.peerEquivalent = false
        autoConverge.buildHash = options.currentBuildHash()
        autoConverge.dpsHash = options.currentDpsHash()
        log("SYNC", "convergence pass %d queued", autoConverge.pass)
        return true
    end

    function M.RequestSync()
        local current = now()
        if autoConverge.active
            and current >= Number(autoConverge.absoluteUntil) then
            autoConverge.active = false
            autoConverge.terminal = "expired"
            pendingRequest = nil
            receiveWindowUntil, receiveAbsoluteUntil = 0, 0
        end
        local supersedingAutomatic = autoConverge.active
            and autoConverge.mode == "automatic"
        if autoConverge.active and not supersedingAutomatic then
            return true, "already syncing"
        end
        if supersedingAutomatic then
            local staleRequestId = pendingRequest and pendingRequest.id
                or lastRequestId
            if staleRequestId then cancelRequest(staleRequestId, myName()) end
            pendingRequest = nil
            lastRequestId = nil
            receiveWindowUntil, receiveAbsoluteUntil = 0, 0
            autoConverge.superseded = Number(autoConverge.superseded) + 1
            log("SYNC", "manual convergence superseded automatic request")
        end
        autoSyncPending = false
        autoConverge.active = true
        autoConverge.pass = 0
        autoConverge.stable = 0
        autoConverge.terminal = nil
        autoConverge.mode = "manual"
        autoConverge.peerProgress = false
        autoConverge.peerEquivalent = false
        autoConverge.absoluteUntil = current + maxConvergenceAge
        local ok, why = BeginConvergencePass("manual", supersedingAutomatic)
        if not ok then
            autoConverge.active = false
            return false, why
        end
        return true
    end

    function M.UpdateAutoSync(elapsed)
        if not autoSyncPending then return end
        autoSyncElapsed = autoSyncElapsed + Number(elapsed)
        if autoSyncElapsed < autoSyncDelay or not options.isConnected() then
            return
        end
        autoSyncPending = false
        autoConverge.active = true
        autoConverge.pass = 0
        autoConverge.stable = 0
        autoConverge.terminal = nil
        autoConverge.mode = "automatic"
        autoConverge.peerProgress = false
        autoConverge.peerEquivalent = false
        autoConverge.absoluteUntil = now() + maxConvergenceAge
        local ok, why = BeginConvergencePass("automatic", false)
        if not ok then
            autoSyncPending = true
            autoSyncElapsed = autoSyncDelay - 1
            log("SYNC", "automatic login convergence deferred: %s",
                tostring(why or "unknown"))
        end
    end

    function M.UpdateAutoConvergence()
        if not autoConverge.active then return end
        local current = now()
        if current >= Number(autoConverge.absoluteUntil) then
            autoConverge.active = false
            autoConverge.terminal = "expired"
            pendingRequest = nil
            receiveWindowUntil, receiveAbsoluteUntil = 0, 0
            SetTerminal("expired")
            log("SYNC", "convergence expired after %d pass(es)",
                autoConverge.pass)
            return
        end
        if pendingRequest or M.IsReceiving() then return end
        if current - autoConverge.started < autoSyncMinPass then return end
        if current - autoConverge.lastInbound < autoSyncQuiet then return end
        local changed = tostring(options.currentBuildHash())
                ~= tostring(autoConverge.buildHash)
            or tostring(options.currentDpsHash())
                ~= tostring(autoConverge.dpsHash)
        if changed or not autoConverge.peerEquivalent then
            autoConverge.stable = 0
        else
            autoConverge.stable = autoConverge.stable + 1
        end
        if autoConverge.stable >= 2 then
            autoConverge.active = false
            autoConverge.terminal = "stable"
            SetTerminal("stable")
            log("SYNC", "convergence complete after %d pass(es)",
                autoConverge.pass)
            return
        end
        if autoConverge.pass >= maxPasses then
            autoConverge.active = false
            autoConverge.terminal = not autoConverge.peerProgress
                and "no peer progress" or not autoConverge.peerEquivalent
                and "peer state unconfirmed" or "pass limit"
            SetTerminal(not autoConverge.peerProgress
                and "no_useful_progress" or not autoConverge.peerEquivalent
                and "peer_state_unconfirmed" or "pass_limit")
            log("SYNC", "convergence stopped at bounded pass limit (%d)",
                maxPasses)
            return
        end
        local ok, why = BeginConvergencePass(autoConverge.mode, false)
        if not ok then
            autoConverge.started = current
            log("SYNC", "next convergence pass deferred: %s",
                tostring(why or "unknown"))
        end
    end

    function M.OnWorldEntry()
        joinRetryTicker, joinAttempts = 0, 0
        return options.isConnected() and true or false
    end

    function M.UpdateJoinRetry(elapsed)
        if options.isConnected() or joinAttempts >= joinMaxAttempts then return end
        joinRetryTicker = joinRetryTicker + Number(elapsed)
        if joinRetryTicker < joinRetryInterval then return end
        joinRetryTicker = 0
        joinAttempts = joinAttempts + 1
        if options.ensureChannel() then
            log("CHAN", "connected on retry #%d", joinAttempts)
        elseif joinAttempts == joinMaxAttempts then
            log("CHAN", "gave up after %d attempts (use /wr sync to retry)",
                joinAttempts)
        end
    end

    function M.WorkSnapshot()
        local peerCount = 0
        for _ in pairs(knownPeers) do peerCount = peerCount + 1 end
        local outcome = OutcomeSnapshot()
        return {
            knownPeers=peerCount,
            recovery=RecoveryCount(),
            pendingReplacements=ReplacementCount(),
            pass=Number(autoConverge.pass),
            terminal=autoConverge.terminal,
            requestQueued=pendingRequest ~= nil,
            mode=autoConverge.mode,
            peerProgress=autoConverge.peerProgress and true or false,
            peerEquivalent=autoConverge.peerEquivalent and true or false,
            superseded=Number(autoConverge.superseded),
            requestId=outcome.requestId,useful=outcome.useful,
            new=outcome.new,updated=outcome.updated,shares=outcome.shares,
            duplicates=outcome.duplicates,rejected=outcome.rejected,
            baseline=outcome.baseline,unrelated=outcome.unrelated,
            lastReason=outcome.lastReason,
            terminalReason=outcome.terminalReason,
            queueOutcome=outcome.queueOutcome,
        }
    end

    -- Status polling stays O(1): unlike WorkState, it does not need the peer
    -- inventory count and therefore must not scan that bounded table.
    function M.StatusSnapshot()
        local outcome = OutcomeSnapshot()
        return {
            recovery=RecoveryCount(),
            pendingReplacements=ReplacementCount(),
            pass=Number(autoConverge.pass),
            converging=autoConverge.active and true or false,
            receiving=M.IsReceiving(),
            terminal=autoConverge.terminal,
            requestQueued=pendingRequest ~= nil,
            mode=autoConverge.mode,
            peerProgress=autoConverge.peerProgress and true or false,
            peerEquivalent=autoConverge.peerEquivalent and true or false,
            superseded=Number(autoConverge.superseded),
            requestId=outcome.requestId,useful=outcome.useful,
            new=outcome.new,updated=outcome.updated,shares=outcome.shares,
            duplicates=outcome.duplicates,rejected=outcome.rejected,
            baseline=outcome.baseline,unrelated=outcome.unrelated,
            lastReason=outcome.lastReason,
            terminalReason=outcome.terminalReason,
            queueOutcome=outcome.queueOutcome,
        }
    end

    local function BuildStatusToken()
        local adapter = options.getAdapter()
        local dps = options.getDpsCapture()
        local slots = adapter and adapter.Slots and adapter.Slots() or nil
        local wishlist = adapter and adapter.Wishlist
            and adapter.Wishlist() or nil
        local player = myName()
        local level = options.playerLevel()
        local catalog = options.getCatalog()
        local builds = catalog and catalog.Count and catalog.Count() or 0
        local playerInfo = dps and dps.GetPlayerInfo
            and dps.GetPlayerInfo(player) or nil
        local payload = {
            v=options.statusVersion(),
            s=slots and slots.maxSlots or 0,
            a=slots and slots.activeSlot or 0,
            w=wishlist and wishlist.name or "",
            d=playerInfo and playerInfo.dps or 0,
            dc=playerInfo and playerInfo.category or "",
            b=builds,
            l=level,
        }
        local codec = options.getCodec()
        if not (codec and codec.JSONEncode and codec.Base64Encode) then
            return nil
        end
        local json = codec.JSONEncode(payload)
        return json and codec.Base64Encode(json) or nil
    end

    function M.HandleStatusRequest(sender, requestId)
        if sender and sender ~= "" then
            pendingStatusReply = {
                target=sender,
                requestId=requestId or "0",
            }
        end
    end

    function M.FlushStatusReply()
        if not pendingStatusReply then return end
        local reply = pendingStatusReply
        pendingStatusReply = nil
        local token = BuildStatusToken()
        if not token then return end
        local message = "WLRQ|" .. myName() .. "|" .. reply.requestId
            .. "|" .. token
        if #message > options.chatLimit then
            message = message:sub(1, options.chatLimit)
        end
        pcall(options.sendWhisper, message, reply.target)
    end

    function M.SendStatusTo(target)
        if not target or target == "" then return false end
        local token = BuildStatusToken()
        if not token then return false end
        local message = "WLRQ|" .. myName() .. "|dev|" .. token
        if #message > options.chatLimit then
            message = message:sub(1, options.chatLimit)
        end
        return pcall(options.sendWhisper, message, target)
    end

    function M.Reset()
        joinRetryTicker, joinAttempts = 0, 0
        receiveWindowUntil = 0
        receiveAbsoluteUntil = 0
        lastRequestAt = -math.huge
        lastRequestId = nil
        pendingRequest = nil
        lastSyncNewCount = 0
        requestedLoadouts = {}
        pendingReplacementCount = 0
        recoveryQueue, recoveryHead, recoveryTail = {}, 1, 0
        recoveryTicker = 0
        autoConverge = {
            active=false, pass=0, stable=0, started=0, lastInbound=0,
            absoluteUntil=0,terminal=nil,buildHash=nil, dpsHash=nil,
            mode=nil,peerProgress=false,peerEquivalent=false,superseded=0,
        }
        ResetOutcome(nil)
        autoSyncPending = true
        autoSyncElapsed = 0
        -- Established Init behavior keeps recognized peers and a pending
        -- developer reply; neither is accepted transport or represented data.
    end

    return M
end
