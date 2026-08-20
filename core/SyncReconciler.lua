-- Nexus: bounded, fair Sync response planning and pending-work ownership.

Nexus = Nexus or {}
if type(Nexus.SyncInternals) ~= "table" then Nexus.SyncInternals = {} end

local Reconciler = {}
Nexus.SyncInternals.Reconciler = Reconciler

function Reconciler.New(options)
    options = options or {}
    local bucketCount = assert(options.bucketCount, "bucket count required")
    local maxPendingResponses = assert(options.maxPendingResponses,
        "response cap required")
    local maxPendingLoadouts = assert(options.maxPendingLoadouts,
        "loadout cap required")
    local pendingTtl = assert(options.pendingTtl, "pending TTL required")
    local pendingMaxAge = assert(options.pendingMaxAge,
        "pending max age required")
    local claimDelayMin = assert(options.claimDelayMin,
        "claim delay minimum required")
    local claimDelayMax = assert(options.claimDelayMax,
        "claim delay maximum required")
    local bucketClaimMax = assert(options.bucketClaimMax,
        "bucket claim maximum required")
    local maxAdmissionsPerRequest = math.max(1,
        tonumber(options.maxAdmissionsPerRequest) or 32)
    local maxChunksPerRequest = math.max(1,
        tonumber(options.maxChunksPerRequest) or 64)
    local maxBytesPerRequest = math.max(1,
        tonumber(options.maxBytesPerRequest) or 16384)
    local maxSendSecondsPerRequest = math.max(1,
        tonumber(options.maxSendSecondsPerRequest) or 75)
    local maxTransfersPerRequest = math.max(1,
        tonumber(options.maxTransfersPerRequest) or 8)
    local maxConcurrentTransfers = math.max(1,
        tonumber(options.maxConcurrentTransfers) or maxTransfersPerRequest)
    local sendInterval = math.max(0.01,
        tonumber(options.sendInterval) or 1.10)
    local responseElectionDelay = math.max(sendInterval,
        tonumber(options.responseElectionDelay) or 2.5)
    local now = assert(options.now, "clock callback required")
    local myName = assert(options.myName, "name callback required")
    local stableDelay = assert(options.stableDelay,
        "stable delay callback required")
    local splitHashes = assert(options.splitHashes,
        "hash split callback required")
    local deltaBuildHash = assert(options.deltaBuildHash,
        "delta hash callback required")
    local currentBuildHash = assert(options.currentBuildHash,
        "build hash callback required")
    local currentDpsHash = assert(options.currentDpsHash,
        "DPS hash callback required")
    local catalogToken = assert(options.catalogToken,
        "catalog token callback required")
    local buildCandidateSnapshot = assert(options.buildCandidateSnapshot,
        "candidate snapshot callback required")
    local snapshotCurrent = assert(options.snapshotCurrent,
        "candidate currency callback required")
    local bucketClaimable = assert(options.bucketClaimable,
        "bucket claimability callback required")
    local backpressured = assert(options.backpressured,
        "backpressure callback required")
    local catalogGet = assert(options.catalogGet,
        "catalog read callback required")
    local prepareBuild = assert(options.prepareBuild,
        "build preparation callback required")
    local admitBuild = assert(options.admitBuild,
        "build admission callback required")
    local sendNextBuild = assert(options.sendNextBuild,
        "build response callback required")
    local sendDpsBucket = assert(options.sendDpsBucket,
        "DPS response callback required")
    local publishLoadoutClaim = assert(options.publishLoadoutClaim,
        "loadout claim callback required")
    local publishBucketClaim = assert(options.publishBucketClaim,
        "bucket claim callback required")
    local supportsRequestContext =
        type(options.supportsRequestContext) == "function"
        and options.supportsRequestContext or function() return false end
    local localOwnsDpsBucket =
        type(options.localOwnsDpsBucket) == "function"
        and options.localOwnsDpsBucket or function() return true end
    local dpsBucketClaimInfo =
        type(options.dpsBucketClaimInfo) == "function"
        and options.dpsBucketClaimInfo or function() return false end
    local samePeer = type(options.samePeer) == "function"
        and options.samePeer or function(left, right) return left == right end
    local responseClaimSupported = type(options.publishResponseClaim)
        == "function"
    local publishResponseClaim = responseClaimSupported
        and options.publishResponseClaim or function() return false end
    local outstandingTransfers = type(options.outstandingTransfers) == "function"
        and options.outstandingTransfers or function() return 0 end
    local cancelRequest = type(options.cancelRequest) == "function"
        and options.cancelRequest or function() return false end
    local noteSyncStat = assert(options.noteSyncStat,
        "Sync stat callback required")
    local log = assert(options.log, "log callback required")

    local pendingResponses, pendingLoadouts, continuations = {}, {}, {}
    local recentRequests = {}
    local fairCursor
    local stats
    local R = {}

    local function NewStats()
        return {
            turns=0, workUnits=0, backpressureDeferrals=0,
            entryPreparations=0, candidateSnapshots=0, candidateSorts=0,
            candidateScans=0, buildSerializations=0, buildAdmissions=0,
            dpsSerializations=0, chunkMessagesBuilt=0, compatRequests=0,
            quotaYields=0,wireBudgetYields=0,equivalentSuppressed=0,
            projectedChunks=0,projectedBytes=0,projectedSendSeconds=0,
            outstandingTransfers=0,admissionRejected=0,
            successfulProgress=0,responseClaims=0,claimDeferrals=0,
            requestsSuperseded=0,concurrentDeferrals=0,
            claimQueueDeferrals=0,
        }
    end
    stats = NewStats()

    local function TableCount(value)
        local count = 0
        for _ in pairs(value or {}) do count = count + 1 end
        return count
    end

    local function PruneContinuations()
        local current = now()
        local count, oldestKey, oldestAt = 0, nil, math.huge
        for key, continuation in pairs(continuations) do
            local savedAt = tonumber(continuation.savedAt) or 0
            if current - savedAt > pendingMaxAge then
                continuations[key] = nil
            else
                count = count + 1
                if savedAt < oldestAt then
                    oldestKey, oldestAt = key, savedAt
                end
            end
        end
        return count, oldestKey
    end

    local function PruneRecentRequests()
        local current = now()
        local count, oldestKey, oldestAt = 0, nil, math.huge
        for key, receipt in pairs(recentRequests) do
            local recordedAt = tonumber(receipt.recordedAt) or 0
            if current - recordedAt > pendingMaxAge then
                recentRequests[key] = nil
            else
                count = count + 1
                if recordedAt < oldestAt then
                    oldestKey, oldestAt = key, recordedAt
                end
            end
        end
        while count >= maxPendingResponses * 2 and oldestKey do
            recentRequests[oldestKey] = nil
            count = count - 1
            oldestKey, oldestAt = nil, math.huge
            for key, receipt in pairs(recentRequests) do
                local recordedAt = tonumber(receipt.recordedAt) or 0
                if recordedAt < oldestAt then
                    oldestKey, oldestAt = key, recordedAt
                end
            end
        end
    end

    local function RememberRequest(entry, outcome)
        if type(entry) ~= "table" or type(entry.key) ~= "string" then return end
        PruneRecentRequests()
        recentRequests[entry.key] = {
            buildHash=tostring(entry.peerBuildWireHash or "0"),
            dpsHash=tostring(entry.peerDpsHash or "0"),
            recordedAt=now(),outcome=tostring(outcome or "complete"),
        }
    end

    local function SaveContinuation(entry)
        local count, oldestKey = PruneContinuations()
        if continuations[entry.requester] == nil
            and count >= maxPendingResponses and oldestKey then
            continuations[oldestKey] = nil
        end
        continuations[entry.requester] = {
            buildProgress=entry.buildProgress,dpsProgress=entry.dpsProgress,
            bucketCursor=entry.bucketCursor,savedAt=now(),
        }
    end

    function R.NoteStat(name, amount)
        stats[name] = (stats[name] or 0) + (tonumber(amount) or 1)
    end

    function R.Stats()
        local out = {}
        for key, value in pairs(stats) do out[key] = value end
        return out
    end

    function R.Counts()
        local responses, loadouts = TableCount(pendingResponses),
            TableCount(pendingLoadouts)
        return {responses=responses, loadouts=loadouts,
            total=responses + loadouts}
    end

    function R.HasPending()
        return next(pendingResponses) ~= nil or next(pendingLoadouts) ~= nil
    end

    function R.ScheduleRequest(description)
        local requester = tostring(description and description.requester or "")
        if requester == myName() then
            log("RX", "ignoring own request (no echo loop)")
            return true
        end
        local peerBuildHash = description.peerBuildHash or "0"
        local peerDpsHash = description.peerDpsHash or "0"
        local requestId = description.requestId
            or ("legacy-" .. requester .. "-" .. tostring(math.floor(now())))
        local key = requester .. ":" .. tostring(requestId)
        local prior = pendingResponses[key]
        if prior then
            if tostring(prior.peerBuildWireHash or prior.peerBuildHash)
                    ~= tostring(peerBuildHash)
                or tostring(prior.peerDpsHash) ~= tostring(peerDpsHash) then
                log("RX", "REJECT conflicting request metadata for %s", key)
                return false
            end
            return true
        end
        PruneRecentRequests()
        local recent = recentRequests[key]
        if recent then
            if recent.buildHash ~= tostring(peerBuildHash)
                or recent.dpsHash ~= tostring(peerDpsHash) then
                log("RX", "REJECT conflicting completed request metadata for %s",
                    key)
                return false
            end
            R.NoteStat("equivalentSuppressed", 1)
            log("RX", "suppressed equivalent completed request %s", key)
            return true
        end
        for pendingKey, pending in pairs(pendingResponses) do
            if pendingKey ~= key and pending.requester == requester then
                -- Supersession cancels the old request's queued packets. Its
                -- progress therefore cannot be inherited by the replacement:
                -- doing so would skip records that never reached the peer.
                continuations[pending.requester] = nil
                RememberRequest(pending, "superseded")
                cancelRequest(pending.requestId, pending.requester)
                pendingResponses[pendingKey] = nil
                R.NoteStat("requestsSuperseded", 1)
                log("RX", "newer request %s superseded %s for %s",
                    tostring(requestId), tostring(pending.requestId), requester)
                break
            end
        end
        if TableCount(pendingResponses) >= maxPendingResponses then
            noteSyncStat("pendingOverflowRejected", 1)
            log("RX", "REJECT newest request from %s: pending cap %d",
                requester, maxPendingResponses)
            return false
        end
        local current = now()
        PruneContinuations()
        local continuation = continuations[requester]
        pendingResponses[key] = {
            key=key, requester=requester, requestId=requestId,
            requestContextSupported=supportsRequestContext(requestId) == true,
            peerBuildWireHash=peerBuildHash, peerDpsHash=peerDpsHash,
            createdAt=current, lastActiveAt=current, prepared=false,
            remaining=stableDelay(key .. ":prepare:" .. myName()),
            buildProgress=continuation and continuation.buildProgress or {},
            dpsProgress=continuation and continuation.dpsProgress or {},
            bucketCursor=continuation and continuation.bucketCursor or 0,
            admissions=0,chunks=0,bytes=0,transfers=0,
        }
        continuations[requester] = nil
        log("RX", "mesh request from %s scheduled (id=%s)",
            requester, tostring(requestId))
        return true
    end

    function R.ScheduleLoadout(description)
        local requester = tostring(description and description.requester or "")
        local buildId = tostring(description and description.buildId or "")
        if requester == myName() then return true end
        local key = requester .. ":" .. buildId
        local requestId = description and description.requestId
            or "loadout-" .. buildId
        local existing = pendingLoadouts[key]
        if existing and tostring(existing.requestId or "")
                == tostring(requestId or "") then return true end
        if not existing and TableCount(pendingLoadouts) >= maxPendingLoadouts then
            noteSyncStat("pendingOverflowRejected", 1)
            return false
        end
        local current = now()
        pendingLoadouts[key] = {
            key=key, requester=requester, buildId=buildId,
            requestId=requestId,
            createdAt=current, lastActiveAt=current,
            remaining=stableDelay(key .. ":" .. myName()),
        }
        return true
    end

    local function ResponseClaimState(entry)
        if entry and entry.responseClaimUnavailable then return "unsafe" end
        local hasBucket = false
        for _, bucket in pairs(entry and entry.buckets or {}) do
            hasBucket = true
            if bucket.kind == "B" then
                local snapshot = bucket.snapshot
                if not (snapshot and snapshot.complete) then return "pending" end
                if type(snapshot.claimSafeByBucket) ~= "table"
                    or snapshot.claimSafeByBucket[bucket.bucket] ~= true then
                    return "unsafe"
                end
            elseif bucket.kind == "D" then
                if entry.requestContextSupported ~= true
                    or bucket.claimSafe ~= true
                    or localOwnsDpsBucket(bucket.bucket) then return "unsafe" end
            else
                return "unsafe"
            end
        end
        return hasBucket and "claimable" or "empty"
    end

    local function ClaimRank(entry, responder)
        local authorityTier = 1
        for _, bucket in pairs(entry and entry.buckets or {}) do
            if bucket.kind == "D" and bucket.claimAuthority
                and samePeer(bucket.claimAuthority, responder) then
                authorityTier = 0
                break
            end
        end
        return authorityTier * 10
            + stableDelay(entry.key .. ":prepare:" .. tostring(responder))
    end

    local function StorePendingClaim(entry, claim)
        local prior = entry.pendingClaim
        if not prior or ClaimRank(entry, claim.responder)
                < ClaimRank(entry, prior.responder)
            or (ClaimRank(entry, claim.responder)
                    == ClaimRank(entry, prior.responder)
                and claim.responder < prior.responder) then
            entry.pendingClaim = claim
        end
    end

    function R.HandleLegacyClaim(description)
        local key = tostring(description.requester) .. ":"
            .. tostring(description.requestId)
        local entry = pendingResponses[key]
        if not entry or description.responder == myName() then return false end
        local claim = {
            responder=tostring(description.responder or ""),
            buildHash=tostring(description.buildHash or "0"),
            dpsHash=tostring(description.dpsHash or "0"),receivedAt=now(),
        }
        local claimState = entry.prepared and ResponseClaimState(entry)
            or "pending"
        if claimState == "pending" then
            StorePendingClaim(entry, claim)
            return true
        end
        local claimRank = ClaimRank(entry, claim.responder)
        local selfName = tostring(myName())
        local selfRank = ClaimRank(entry, selfName)
        local outranks = claimRank < selfRank
            or (claimRank == selfRank and claim.responder < selfName)
        if claimState == "claimable" and outranks
            and claim.buildHash == tostring(entry.localBuildWireHash or "0")
            and claim.dpsHash == tostring(entry.localDpsHash or "0") then
            entry.claimResponder = claim.responder
            entry.electedAway = true
            R.NoteStat("claimDeferrals", 1)
            RememberRequest(entry, "elected peer")
            cancelRequest(entry.requestId, entry.requester)
            pendingResponses[key] = nil
            log("RX", "suppressed equivalent response for deterministic claimant %s",
                claim.responder)
        else
            log("RX", "retained response after non-equivalent or owner-only claim from %s",
                claim.responder)
        end
        return true
    end

    local function ApplyPendingClaim(entry)
        local pendingClaim = entry and entry.pendingClaim
        if not pendingClaim then return false end
        entry.pendingClaim = nil
        R.HandleLegacyClaim({responder=pendingClaim.responder,
            requester=entry.requester,requestId=entry.requestId,
            buildHash=pendingClaim.buildHash,dpsHash=pendingClaim.dpsHash})
        return pendingResponses[entry.key] ~= entry
    end

    local function TryPublishResponseClaim(entry)
        local state = ResponseClaimState(entry)
        if entry.responseClaimPublished then return true, state end
        if state == "pending" or state == "unsafe" then return false, state end
        local claimed, delivery = publishResponseClaim(entry)
        if claimed then
            entry.responseClaimPublished = true
            R.NoteStat("responseClaims", 1)
            if state == "claimable" then
                entry.claimAwaitingAttempt = delivery ~= "attempted"
                entry.responseClaimAttempted = delivery == "attempted"
                if entry.responseClaimAttempted then
                    entry.electionUntil = now() + responseElectionDelay
                end
            end
        elseif delivery == "invalid packet" then
            -- Every represented data packet is still independently bounded.
            -- A maximum-field WLRC can be permanently too large, so fall back
            -- to the non-electing response instead of refreshing this request
            -- until its absolute deadline without ever sending data.
            entry.responseClaimUnavailable = true
            state = "unsafe"
        end
        return claimed, state, delivery
    end

    function R.HandleTransportEvent(kind, fields, metadata)
        if type(metadata) ~= "table"
            or tostring(metadata.queueClass or "") ~= "claim" then
            return false
        end
        local requester = tostring(metadata.requester or "")
        local requestId = tostring(metadata.requestId or "")
        local key = requester .. ":" .. requestId
        local entry = pendingResponses[key]
        if not entry or tostring(metadata.transferId or "")
                ~= "response-claim:" .. requester .. ":" .. requestId then
            return false
        end
        if kind == "send_attempted" then
            entry.claimAwaitingAttempt = false
            entry.responseClaimAttempted = true
            entry.electionUntil = now() + responseElectionDelay
            entry.lastActiveAt = now()
        elseif kind == "send_requeued" or kind == "send_retry" then
            entry.claimAwaitingAttempt = true
            entry.responseClaimAttempted = false
            entry.electionUntil = nil
        elseif kind == "send_dropped" then
            entry.claimAwaitingAttempt = false
            entry.responseClaimAttempted = false
            entry.responseClaimPublished = false
            entry.electionUntil = nil
        else
            return false
        end
        return true
    end

    function R.HandleBucketClaim(description)
        if description.responder == myName() then return false end
        local key = tostring(description.requester) .. ":"
            .. tostring(description.requestId)
        local entry = pendingResponses[key]
        if not entry then return false end
        local id = tostring(description.kind)
            .. tostring(tonumber(description.bucket) or 0)
        local bucket = entry.buckets and entry.buckets[id]
        if bucket and bucket.kind == "B"
            and not snapshotCurrent(bucket.snapshot) then
            R.ResetResponseEntry(entry)
            return true
        end
        if bucket and bucket.kind == "B"
            and bucketClaimable(bucket.bucket)
            and tostring(bucket.hash) == tostring(description.hash) then
            entry.buckets[id] = nil
            log("RX", "mesh bucket %s claimed by %s for %s", id,
                tostring(description.responder), tostring(description.requester))
            if not next(entry.buckets) then
                RememberRequest(entry, "claimed")
                pendingResponses[key] = nil
            end
            return true
        end
        if bucket and bucket.kind == "D"
            and entry.requestContextSupported == true
            and not localOwnsDpsBucket(bucket.bucket)
            and tostring(bucket.hash) == tostring(description.hash) then
            entry.buckets[id] = nil
            log("RX", "mesh bucket %s claimed by %s for %s", id,
                tostring(description.responder), tostring(description.requester))
            if not next(entry.buckets) then
                RememberRequest(entry, "claimed")
                pendingResponses[key] = nil
            end
            return true
        end
        return false
    end

    function R.HandleLoadoutClaim(description)
        local key = tostring(description.requester) .. ":"
            .. tostring(description.buildId)
        local entry = pendingLoadouts[key]
        if entry and supportsRequestContext(entry.requestId)
            and tostring(description.requestId or "")
                ~= tostring(entry.requestId or "") then
            return false
        end
        if description.responder ~= myName() and entry then
            pendingLoadouts[key] = nil
            log("RX", "suppressed duplicate loadout response; %s claimed %s",
                tostring(description.responder), tostring(description.buildId))
            return true
        end
        return false
    end

    local function BucketDelay(key, kind, bucket)
        local base = stableDelay(tostring(key) .. ":" .. tostring(kind)
            .. ":" .. tostring(bucket) .. ":" .. myName())
        local span = bucketClaimMax - claimDelayMin
        local normalized = (base - claimDelayMin)
            / math.max(0.01, claimDelayMax - claimDelayMin)
        return claimDelayMin + normalized * span
    end

    function R.PrepareResponseEntry(entry)
        local localDeltaHash, myDpsHash = deltaBuildHash(), currentDpsHash()
        local peerWireBuckets = splitHashes(entry.peerBuildWireHash)
        local comparablePeerHash, buildMode
        if #peerWireBuckets == bucketCount + 1
            and tostring(peerWireBuckets[bucketCount + 1]) == catalogToken() then
            local peerDelta = {}
            for bucket = 1, bucketCount do
                peerDelta[bucket] = peerWireBuckets[bucket]
            end
            comparablePeerHash = table.concat(peerDelta, ",")
            buildMode = "delta"
        elseif #peerWireBuckets == bucketCount then
            comparablePeerHash = entry.peerBuildWireHash
            buildMode = "compat"
            R.NoteStat("compatRequests", 1)
        else
            comparablePeerHash = "0,0,0,0,0,0,0,0"
            buildMode = "compat"
            R.NoteStat("compatRequests", 1)
        end
        local peerBuildBuckets, myBuildBuckets = splitHashes(comparablePeerHash),
            splitHashes(localDeltaHash)
        local peerDpsBuckets, myDpsBuckets = splitHashes(entry.peerDpsHash),
            splitHashes(myDpsHash)
        local responseBuckets, snapshot = {}, nil
        for bucket = 1, bucketCount do
            if tostring(peerBuildBuckets[bucket] or "")
                    ~= tostring(myBuildBuckets[bucket] or "") then
                snapshot = snapshot or buildCandidateSnapshot(localDeltaHash)
                local context = {
                    requester=entry.requester,requestId=entry.requestId,
                    bucket=bucket,
                    contextCapable=entry.requestContextSupported == true,
                }
                responseBuckets["B" .. bucket] = {
                    kind="B", bucket=bucket,
                    hash=tostring(myBuildBuckets[bucket] or "0"),
                    snapshot=snapshot, progress=entry.buildProgress,
                    claimSafe=true,
                    responseContext=context,
                    remaining=BucketDelay(entry.key, "B", bucket),
                }
            end
            if tostring(peerDpsBuckets[bucket] or "")
                    ~= tostring(myDpsBuckets[bucket] or "") then
                entry.dpsProgress[bucket] = entry.dpsProgress[bucket] or {}
                local claimSafe, claimAuthority = dpsBucketClaimInfo(bucket)
                local context = {
                    requester=entry.requester,requestId=entry.requestId,
                    bucket=bucket,
                    contextCapable=entry.requestContextSupported == true,
                }
                responseBuckets["D" .. bucket] = {
                    kind="D", bucket=bucket,
                    hash=tostring(myDpsBuckets[bucket] or "0"),
                    progress=entry.dpsProgress[bucket],
                    claimSafe=claimSafe == true,
                    claimAuthority=claimAuthority,
                    responseContext=context,
                    remaining=BucketDelay(entry.key, "D", bucket),
                }
            end
        end
        entry.peerBuildHash = comparablePeerHash
        entry.buildMode = buildMode
        entry.localDeltaHash = localDeltaHash
        entry.localBuildWireHash = currentBuildHash()
        entry.localDpsHash = myDpsHash
        entry.buckets = responseBuckets
        entry.prepared = true
        entry.remaining = nil
        entry.lastActiveAt = now()
        R.NoteStat("entryPreparations", 1)
        ApplyPendingClaim(entry)
        if entry.electedAway or pendingResponses[entry.key] ~= entry then
            return false
        end
        TryPublishResponseClaim(entry)
        if not next(responseBuckets) then
            noteSyncStat("skippedUpToDate", 1)
            RememberRequest(entry, "up-to-date")
            return false
        end
        return true
    end

    function R.ResetResponseEntry(entry)
        entry.prepared = false
        entry.buckets = nil
        entry.remaining = 0
        entry.bucketCursor = 0
        entry.responseClaimUnavailable = nil
        entry.lastActiveAt = now()
    end

    local function PendingExpired(entry)
        local current = now()
        local createdAt = tonumber(entry and entry.createdAt) or current
        local lastActiveAt = tonumber(entry and entry.lastActiveAt) or createdAt
        return current - createdAt > pendingMaxAge
            or current - lastActiveAt > pendingTtl
    end

    function R.NextReadyBucket(entry)
        local cursor = tonumber(entry.bucketCursor) or 0
        for offset = 1, bucketCount * 2 do
            local ordinal = ((cursor + offset - 1) % (bucketCount * 2)) + 1
            local id = ordinal <= bucketCount and ("B" .. ordinal)
                or ("D" .. (ordinal - bucketCount))
            local bucket = entry.buckets and entry.buckets[id]
            if bucket and (tonumber(bucket.remaining) or 0) <= 0 then
                return id, bucket, ordinal
            end
        end
    end

    function R.SelectFairUnit(units)
        if #units == 0 then return nil end
        table.sort(units, function(left, right) return left.key < right.key end)
        local selected = units[1]
        if fairCursor then
            for _, unit in ipairs(units) do
                if unit.key > fairCursor then selected = unit; break end
            end
        end
        fairCursor = selected.key
        return selected
    end

    function R.ProcessLoadoutResponse(entry)
        local progressed = false
        if entry.preparedBuild
            and entry.preparedRevision ~= currentBuildHash() then
            entry.preparedBuild = nil
            entry.preparedRevision = nil
            progressed = true
        end
        if not entry.preparedBuild then
            local build = catalogGet(entry.buildId)
            if not build or type(build.echoes) ~= "table"
                or #build.echoes == 0 then
                return true, false, "loadout unavailable"
            end
            local responseContext = {requester=entry.requester,
                requestId=entry.requestId,
                contextCapable=supportsRequestContext(entry.requestId)}
            local prepared, why = prepareBuild(build, true, responseContext)
            if not prepared then return true, false, why end
            entry.preparedBuild = prepared
            entry.preparedRevision = currentBuildHash()
            progressed = true
        end
        local responseContext = {requester=entry.requester,
            requestId=entry.requestId,
            contextCapable=supportsRequestContext(entry.requestId)}
        local admitted, why = admitBuild(entry.preparedBuild, true,
            responseContext)
        if not admitted then return false, progressed, why end
        local claimed, claimWhy = publishLoadoutClaim(entry)
        if not claimed then
            log("TX", "loadout claim skipped for '%s': %s",
                tostring(entry.buildId),
                tostring(claimWhy or "control queue full"))
        end
        log("TX", "answered on-demand loadout '%s' for %s",
            tostring(entry.buildId), tostring(entry.requester))
        return true, true
    end

    local function ResponseBudget(entry)
        local outstanding = math.max(0,
            tonumber(outstandingTransfers()) or 0)
        local requestTransfers = math.max(0, maxTransfersPerRequest
            - (tonumber(entry.transfers) or 0))
        local concurrentTransfers = math.max(0,
            maxConcurrentTransfers - outstanding)
        stats.outstandingTransfers = math.max(
            tonumber(stats.outstandingTransfers) or 0, outstanding)
        return {
            chunks=math.max(0, maxChunksPerRequest
                - (tonumber(entry.chunks) or 0)),
            bytes=math.max(0, maxBytesPerRequest
                - (tonumber(entry.bytes) or 0)),
            seconds=math.max(0, maxSendSecondsPerRequest
                - (tonumber(entry.chunks) or 0) * sendInterval),
            transfers=math.min(requestTransfers, concurrentTransfers),
            requestTransfers=requestTransfers,
            concurrentTransfers=concurrentTransfers,
            maxChunks=maxChunksPerRequest,
            maxBytes=maxBytesPerRequest,
            maxSeconds=maxSendSecondsPerRequest,
            maxTransfers=maxTransfersPerRequest,
            sendInterval=sendInterval,
        }
    end

    local function SendBucketResponse(entry, bucketState, budget)
        local buildCount, dpsCount, complete, claimSafe, progressed, why =
            0, 0, true, true, false, nil
        local chunks, bytes, transfers = 0, 0, 0
        bucketState.progress = bucketState.progress or {}
        if bucketState.kind == "B" then
            buildCount, complete, claimSafe, progressed, why,
                chunks, bytes, transfers = sendNextBuild(bucketState, budget)
            if claimSafe == false then bucketState.claimSafe = false end
        else
            local available, ok, result, allAdmitted, didProgress,
                responseWhy, responseChunks, responseBytes,
                responseTransfers, responseClaimSafe = sendDpsBucket(entry.peerDpsHash,
                    bucketState.bucket, bucketState.progress, 1,
                    bucketState.responseContext, budget)
            if available then
                if ok then dpsCount = tonumber(result) or 0 end
                complete = ok and allAdmitted == true
                progressed = ok and didProgress == true
                why = ok and responseWhy or "DPS response failed"
                if not ok then bucketState.claimSafe = false end
                if responseClaimSafe == false then bucketState.claimSafe = false end
                chunks = tonumber(responseChunks) or 0
                bytes = tonumber(responseBytes) or 0
                transfers = tonumber(responseTransfers) or 0
            end
        end
        if buildCount > 0 or dpsCount > 0 or complete then
            log("RX", "mesh bucket %s%d for %s: %d build(s), %d record(s)",
                bucketState.kind, bucketState.bucket,
                tostring(entry.requester), buildCount, dpsCount)
        end
        return complete, bucketState.claimSafe ~= false,
            progressed or buildCount > 0 or dpsCount > 0, why,
            buildCount + dpsCount, chunks, bytes, transfers
    end

    function R.Process(elapsed)
        elapsed = tonumber(elapsed) or 0
        R.NoteStat("turns", 1)
        for key, entry in pairs(pendingResponses) do
            if PendingExpired(entry) then
                RememberRequest(entry, "expired")
                cancelRequest(entry.requestId, entry.requester)
                pendingResponses[key] = nil
            elseif not entry.prepared then
                entry.remaining = (tonumber(entry.remaining) or 0) - elapsed
            else
                for _, bucket in pairs(entry.buckets or {}) do
                    bucket.remaining = (tonumber(bucket.remaining) or 0) - elapsed
                end
            end
        end
        for key, entry in pairs(pendingLoadouts) do
            if PendingExpired(entry) then
                pendingLoadouts[key] = nil
            else
                entry.remaining = (tonumber(entry.remaining) or 0) - elapsed
            end
        end

        if backpressured() then
            R.NoteStat("backpressureDeferrals", 1)
            return
        end

        local units = {}
        for key, entry in pairs(pendingResponses) do
            local deferred = entry.claimAwaitingAttempt
                or (entry.electionUntil and now() < entry.electionUntil)
            if deferred then
                -- A matching responder claim or the short election window
                -- owns this turn. No represented data is touched while held.
            elseif not entry.prepared then
                if (tonumber(entry.remaining) or 0) <= 0 then
                    units[#units + 1] = {key="R|" .. key, type="prepare",
                        entryKey=key, entry=entry}
                end
            else
                local id, bucket, ordinal = R.NextReadyBucket(entry)
                if id then
                    units[#units + 1] = {key="R|" .. key, type="bucket",
                        entryKey=key, entry=entry, id=id,
                        bucketState=bucket, ordinal=ordinal}
                end
            end
        end
        for key, entry in pairs(pendingLoadouts) do
            if (tonumber(entry.remaining) or 0) <= 0 then
                units[#units + 1] = {key="L|" .. key, type="loadout",
                    entryKey=key, entry=entry}
            end
        end
        local unit = R.SelectFairUnit(units)
        if not unit then return end
        R.NoteStat("workUnits", 1)
        stats.lastRequester = unit.entry.requester

        if unit.type == "prepare" then
            if not R.PrepareResponseEntry(unit.entry) then
                pendingResponses[unit.entryKey] = nil
            end
            return
        end
        if unit.type == "loadout" then
            local complete, progressed, why =
                R.ProcessLoadoutResponse(unit.entry)
            if complete then
                pendingLoadouts[unit.entryKey] = nil
            else
                unit.entry.remaining = why == "sync queue full" and 1 or 0
                if progressed then unit.entry.lastActiveAt = now() end
            end
            return
        end

        local entry, bucket = unit.entry, unit.bucketState
        entry.bucketCursor = unit.ordinal
        stats.lastBucket = unit.id
        if ResponseClaimState(entry) == "claimable" and responseClaimSupported
            and not entry.responseClaimPublished
        then
            if ApplyPendingClaim(entry) then return end
            local claimed, claimState = TryPublishResponseClaim(entry)
            if not claimed and claimState ~= "unsafe" then
                bucket.remaining = sendInterval
                entry.lastActiveAt = now()
                R.NoteStat("claimQueueDeferrals", 1)
                return
            end
            if entry.electionUntil and now() < entry.electionUntil then return end
        end
        local beforeChunks = tonumber(stats.chunkMessagesBuilt) or 0
        local beforeBytes = tonumber(stats.encodedBytesBuilt) or 0
        local beforeTransfers = (tonumber(stats.buildAdmissions) or 0)
            + (tonumber(stats.dpsAdmissions) or 0)
        local responseBudget = ResponseBudget(entry)
        if responseBudget.concurrentTransfers <= 0
            and responseBudget.requestTransfers > 0 then
            bucket.remaining = sendInterval
            entry.lastActiveAt = now()
            R.NoteStat("concurrentDeferrals", 1)
            return
        end
        local complete, claimSafe, progressed, why, admittedCount,
            measuredChunks, measuredBytes, measuredTransfers =
            SendBucketResponse(entry, bucket, responseBudget)
        if bucket.kind == "B" and bucket.snapshot
            and bucket.snapshot.complete then
            if ApplyPendingClaim(entry) then return end
            local claimed, claimState = TryPublishResponseClaim(entry)
            if responseClaimSupported and claimState == "claimable"
                and not claimed then
                bucket.remaining = sendInterval
                entry.lastActiveAt = now()
                R.NoteStat("claimQueueDeferrals", 1)
                return
            end
            if entry.electionUntil and now() < entry.electionUntil then
                if progressed then entry.lastActiveAt = now() end
                return
            end
        end
        local projectedChunks = tonumber(measuredChunks)
            or math.max(0, (tonumber(stats.chunkMessagesBuilt) or 0)
                - beforeChunks)
        local projectedBytes = tonumber(measuredBytes)
            or math.max(0, (tonumber(stats.encodedBytesBuilt) or 0)
                - beforeBytes)
        local projectedTransfers = tonumber(measuredTransfers)
            or math.max(0, ((tonumber(stats.buildAdmissions) or 0)
                + (tonumber(stats.dpsAdmissions) or 0)) - beforeTransfers)
        stats.projectedChunks = (tonumber(stats.projectedChunks) or 0)
            + projectedChunks
        stats.projectedBytes = (tonumber(stats.projectedBytes) or 0)
            + projectedBytes
        stats.projectedSendSeconds = (tonumber(stats.projectedSendSeconds) or 0)
            + projectedChunks * sendInterval
        stats.outstandingTransfers = math.max(
            tonumber(stats.outstandingTransfers) or 0,
            tonumber(outstandingTransfers()) or 0)
        if why == "sync queue full" or why == "response wire budget" then
            R.NoteStat("admissionRejected", 1)
        end
        if why == "response wire budget" then
            SaveContinuation(entry)
            RememberRequest(entry, "wire budget")
            pendingResponses[unit.entryKey] = nil
            R.NoteStat("wireBudgetYields", 1)
            return
        end
        if why == "stale candidate snapshot" then
            R.ResetResponseEntry(entry)
            return
        end
        if progressed then entry.lastActiveAt = now() end
        if progressed then R.NoteStat("successfulProgress", 1) end
        entry.admissions = (tonumber(entry.admissions) or 0)
            + (tonumber(admittedCount) or 0)
        entry.chunks = (tonumber(entry.chunks) or 0) + projectedChunks
        entry.bytes = (tonumber(entry.bytes) or 0) + projectedBytes
        entry.transfers = (tonumber(entry.transfers) or 0)
            + projectedTransfers
        if bucket.kind == "D" and (tonumber(admittedCount) or 0) > 0 then
            bucket.responseAdmitted = true
        end
        local hasOtherBuckets = false
        for id in pairs(entry.buckets or {}) do
            if id ~= unit.id then hasOtherBuckets = true; break end
        end
        local budgetReached = entry.chunks >= maxChunksPerRequest
            or entry.bytes >= maxBytesPerRequest
            or entry.chunks * sendInterval >= maxSendSecondsPerRequest
            or entry.transfers >= maxTransfersPerRequest
        if budgetReached and (not complete or hasOtherBuckets) then
            SaveContinuation(entry)
            RememberRequest(entry, "wire budget")
            pendingResponses[unit.entryKey] = nil
            R.NoteStat("wireBudgetYields", 1)
            return
        end
        if entry.admissions >= maxAdmissionsPerRequest
            and (not complete or hasOtherBuckets) then
            SaveContinuation(entry)
            RememberRequest(entry, "record quota")
            pendingResponses[unit.entryKey] = nil
            R.NoteStat("quotaYields", 1)
            log("RX", "response quota reached for %s after %d admission(s)",
                tostring(entry.requester), entry.admissions)
            return
        end
        if complete then
            local publishClaim = claimSafe and (
                bucket.kind == "B" and bucketClaimable(bucket.bucket)
                or bucket.kind == "D"
                    and entry.requestContextSupported == true
                    and bucket.responseAdmitted == true)
            if publishClaim then
                local claimed, claimWhy = publishBucketClaim(entry, bucket)
                if not claimed then
                    log("TX", "bucket claim skipped for %s%d: %s",
                        bucket.kind, bucket.bucket,
                        tostring(claimWhy or "control queue full"))
                end
            end
            entry.buckets[unit.id] = nil
            if not next(entry.buckets) then
                RememberRequest(entry, "complete")
                pendingResponses[unit.entryKey] = nil
            end
        else
            bucket.remaining = why == "sync queue full" and 1 or 0
        end
    end

    function R.Reset()
        pendingResponses, pendingLoadouts, continuations = {}, {}, {}
        recentRequests = {}
        fairCursor = nil
        stats = NewStats()
    end

    return R
end
