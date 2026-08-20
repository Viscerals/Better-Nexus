-- Nexus: synchronous inbound Sync parsing, validation, and transfer assembly.

Nexus = Nexus or {}
if type(Nexus.SyncInternals) ~= "table" then Nexus.SyncInternals = {} end

local Inbound = {}
Nexus.SyncInternals.Inbound = Inbound

function Inbound.New(options)
    options = options or {}
    local codes = assert(options.codes, "wire codes required")
    local peerCodes = assert(options.peerCodes, "recognized code set required")
    local bucketCount = assert(options.bucketCount, "bucket count required")
    local maxWireBytes = assert(options.maxWireBytes, "wire limit required")
    local maxBuildIdBytes = assert(options.maxBuildIdBytes,
        "build id limit required")
    local maxRequestIdBytes = assert(options.maxRequestIdBytes,
        "request id limit required")
    local maxHashBytes = assert(options.maxHashBytes, "hash limit required")
    local maxChunkBytes = assert(options.maxChunkBytes, "chunk limit required")
    local maxChunks = assert(options.maxChunks, "chunk count required")
    local maxEncodedBytes = assert(options.maxEncodedBytes,
        "encoded payload limit required")
    local maxInflightGlobal = assert(options.maxInflightGlobal,
        "global transfer cap required")
    local maxInflightPerSender = assert(options.maxInflightPerSender,
        "sender transfer cap required")
    local inflightGrace = assert(options.inflightGrace,
        "transfer grace required")
    local inflightMaxAge = assert(options.inflightMaxAge,
        "transfer max age required")
    local now = assert(options.now, "clock callback required")
    local normalizePeerName = assert(options.normalizePeerName,
        "peer normalization callback required")
    local sameTransportSender = assert(options.sameTransportSender,
        "transport sender callback required")
    local samePeer = assert(options.samePeer, "peer comparison callback required")
    local splitWire = assert(options.splitWire, "wire split callback required")
    local validField = assert(options.validField,
        "field validation callback required")
    local validIdentifier = assert(options.validIdentifier,
        "identifier validation callback required")
    local validTransferIdentifier = assert(options.validTransferIdentifier,
        "transfer identifier validation callback required")
    local validPeerName = assert(options.validPeerName,
        "peer validation callback required")
    local validHash = assert(options.validHash,
        "hash validation callback required")
    local validVersion = assert(options.validVersion,
        "version validation callback required")
    local validIntegerText = assert(options.validIntegerText,
        "integer validation callback required")
    local base64Decode = assert(options.base64Decode,
        "base64 decode callback required")
    local jsonDecode = assert(options.jsonDecode,
        "JSON decode callback required")
    local validatePayload = assert(options.validatePayload,
        "build payload validation callback required")
    local validateDpsPayload = assert(options.validateDpsPayload,
        "DPS payload validation callback required")
    local noteDpsRejection = type(options.noteDpsRejection) == "function"
        and options.noteDpsRejection or function() end
    local noteOutcome = type(options.noteOutcome) == "function"
        and options.noteOutcome or function() end
    local log = assert(options.log, "log callback required")
    local rejectIncoming = assert(options.rejectIncoming,
        "envelope rejection callback required")
    local noteMalformed = assert(options.noteMalformed,
        "malformed counter callback required")
    local acceptPeer = assert(options.acceptPeer,
        "peer acceptance callback required")
    local noteInbound = assert(options.noteInbound,
        "inbound activity callback required")
    local handleRequest = assert(options.handleRequest,
        "request callback required")
    local handleLegacyClaim = assert(options.handleLegacyClaim,
        "legacy claim callback required")
    local handleBucketClaim = assert(options.handleBucketClaim,
        "bucket claim callback required")
    local handleDelete = assert(options.handleDelete,
        "delete callback required")
    local handleSummary = assert(options.handleSummary,
        "summary callback required")
    local requestDataViewRefresh = assert(options.requestDataViewRefresh,
        "view refresh callback required")
    local handleLoadoutRequest = assert(options.handleLoadoutRequest,
        "loadout request callback required")
    local handleLoadoutClaim = assert(options.handleLoadoutClaim,
        "loadout claim callback required")
    local commitDps = assert(options.commitDps,
        "DPS commit callback required")
    local validateDpsRelay = assert(options.validateDpsRelay,
        "DPS relay validation callback required")
    local commitBuild = assert(options.commitBuild,
        "build commit callback required")
    local observe = type(options.observe) == "function"
        and options.observe or function() end

    local buildInflight, dpsInflight = {}, {}
    local blockedTransfers, blockedTransferCount = {}, 0
    local blockedTransferCap = math.max(1, maxInflightGlobal)
    local I = {}

    local function TransferToken(kind, key)
        return tostring(kind) .. ":" .. tostring(key)
    end

    -- A marked response generation owns its own multipart assembly.  Keep the
    -- legacy key byte-for-byte simple, but prevent an old c1 request from
    -- poisoning a newer request that legitimately reuses a build/transfer ID.
    local function TransferScope(context)
        if type(context) ~= "table" then return "" end
        local requester = tostring(context.requester or "")
        local requestId = tostring(context.requestId or "")
        local bucket = tostring(context.bucket or "")
        return table.concat({"|", #requester, ":", requester,
            "|", #requestId, ":", requestId,
            "|", #bucket, ":", bucket})
    end

    local function TransferExpired(entry)
        local current = now()
        return current - (entry.lastSeen or entry.t0 or current) > inflightGrace
            or current - (entry.t0 or current) > inflightMaxAge
    end

    local function RememberBlockedTransfer(kind, key)
        local token = TransferToken(kind, key)
        local expiresAt = now() + inflightMaxAge
        if blockedTransfers[token] ~= nil then
            blockedTransfers[token] = expiresAt
            return
        end
        if blockedTransferCount >= blockedTransferCap then
            local oldestToken, oldestExpiry
            for candidate, expiry in pairs(blockedTransfers) do
                if oldestExpiry == nil or expiry < oldestExpiry then
                    oldestToken, oldestExpiry = candidate, expiry
                end
            end
            if oldestToken then
                blockedTransfers[oldestToken] = nil
                blockedTransferCount = math.max(0, blockedTransferCount - 1)
            end
        end
        blockedTransfers[token] = expiresAt
        blockedTransferCount = blockedTransferCount + 1
    end

    local function TransferBlocked(kind, key)
        local token = TransferToken(kind, key)
        local expiresAt = blockedTransfers[token]
        if expiresAt == nil then return false end
        if now() >= expiresAt then
            blockedTransfers[token] = nil
            blockedTransferCount = math.max(0, blockedTransferCount - 1)
            return false
        end
        return true
    end

    function I.RequestContext(requester, requestId, bucket)
        if not validPeerName(requester)
            or not validIdentifier(requestId, maxRequestIdBytes)
            or tostring(requestId):sub(1, 3) ~= "c1-" then
            return nil
        end
        if bucket ~= nil then
            bucket = tonumber(bucket)
            if not bucket or bucket ~= math.floor(bucket)
                or bucket < 1 or bucket > bucketCount then return nil end
        end
        return {requester=requester,requestId=requestId,bucket=bucket}
    end

    function I.SameContext(left, right)
        if left == nil or right == nil then return left == right end
        return left.requester == right.requester
            and left.requestId == right.requestId
            and tonumber(left.bucket or 0) == tonumber(right.bucket or 0)
    end

    local function RejectWithContext(context, message, reason)
        if context ~= nil then
            noteOutcome(context, "rejected", reason or "schema")
        end
        return rejectIncoming(message)
    end

    local function TransferCount(map, sender)
        local total, perSender = 0, 0
        local senderKey = normalizePeerName(sender)
        for _, entry in pairs(map) do
            total = total + 1
            if normalizePeerName(entry.sender) == senderKey then
                perSender = perSender + 1
            end
        end
        return total, perSender
    end

    local function CanStartTransfer(sender)
        local buildTotal, buildSender = TransferCount(buildInflight, sender)
        local dpsTotal, dpsSender = TransferCount(dpsInflight, sender)
        return (buildTotal + dpsTotal) < maxInflightGlobal
            and (buildSender + dpsSender) < maxInflightPerSender
    end

    function I.Counts()
        local buildCount, buildBytes, dpsCount, dpsBytes = 0, 0, 0, 0
        for _, entry in pairs(buildInflight) do
            buildCount = buildCount + 1
            buildBytes = buildBytes + (tonumber(entry.bytes) or 0)
        end
        for _, entry in pairs(dpsInflight) do
            dpsCount = dpsCount + 1
            dpsBytes = dpsBytes + (tonumber(entry.bytes) or 0)
        end
        return {
            builds=buildCount, buildBytes=buildBytes,
            dps=dpsCount, dpsBytes=dpsBytes,
            total=buildCount + dpsCount,
        }
    end

    function I.RequestCounts(requester, requestId)
        local builds, dps = 0, 0
        local requesterKey = normalizePeerName(requester)
        for _, entry in pairs(buildInflight) do
            local context = entry.context
            if context and normalizePeerName(context.requester) == requesterKey
                and context.requestId == requestId then builds = builds + 1 end
        end
        for _, entry in pairs(dpsInflight) do
            local context = entry.context
            if context and normalizePeerName(context.requester) == requesterKey
                and context.requestId == requestId then dps = dps + 1 end
        end
        return {builds=builds,dps=dps,total=builds + dps}
    end

    function I.HasPending()
        return next(buildInflight) ~= nil or next(dpsInflight) ~= nil
    end

    function I.CleanExpired()
        local current = now()
        for key, entry in pairs(buildInflight) do
            if current - (entry.lastSeen or entry.t0 or current) > inflightGrace
                or current - (entry.t0 or current) > inflightMaxAge then
                buildInflight[key] = nil
                RememberBlockedTransfer("build", key)
            end
        end
        for key, entry in pairs(dpsInflight) do
            if current - (entry.lastSeen or entry.t0 or current) > inflightGrace
                or current - (entry.t0 or current) > inflightMaxAge then
                dpsInflight[key] = nil
                RememberBlockedTransfer("dps", key)
            end
        end
    end

    local function HandleCompleteBuild(buildId, envelopeModified, fullData,
            transportSender, context)
        local json = base64Decode(fullData)
        if not json then
            noteOutcome(context, "rejected", "malformed")
            noteMalformed()
            log("RX", "REJECT '%s': bad base64 (%d bytes -- truncated?)",
                tostring(buildId), #tostring(fullData))
            return false
        end
        local data = jsonDecode(json)
        if not data then
            noteOutcome(context, "rejected", "malformed")
            noteMalformed()
            log("RX", "REJECT '%s': JSON decode failed", tostring(buildId))
            return false
        end
        -- Retain the established rejection of pre-rename placeholder records.
        if tostring(data.a or data.author or ""):lower() == "wr team" then
            noteOutcome(context, "rejected", "schema")
            log("RX", "REJECT legacy placeholder '%s'",
                tostring(data.t or data.title))
            return false
        end
        local payload = validatePayload(data)
        if not payload then
            noteOutcome(context, "rejected", "schema")
            noteMalformed()
            log("RX", "REJECT '%s': validation failed", tostring(buildId))
            return false
        end
        if payload.id ~= buildId then
            noteOutcome(context, "rejected", "integrity")
            noteMalformed()
            log("RX", "REJECT id mismatch: envelope='%s' payload='%s'",
                tostring(buildId), tostring(payload.id))
            return false
        end
        if tonumber(payload.lastModified) ~= tonumber(envelopeModified) then
            noteOutcome(context, "rejected", "integrity")
            noteMalformed()
            log("RX", "REJECT timestamp mismatch for '%s'", tostring(buildId))
            return false
        end
        observe("receiver_validation", {id=buildId,peer=transportSender,
            outcome="accepted"})
        local committed = commitBuild(payload, transportSender, context)
        return committed
    end

    local function HandleDpsTransfer(parts)
        local sender, transferId, spec, data =
            parts[2], parts[3], parts[4], parts[5]
        local context
        if #parts == 8 then
            context = I.RequestContext(parts[6], parts[7], parts[8])
            if not context then return rejectIncoming("invalid DPS context") end
        elseif #parts ~= 5 then
            return rejectIncoming("invalid DPS transfer")
        end
        if not validPeerName(sender)
            or not validTransferIdentifier(transferId)
            or not validField(spec, 16, false)
            or not validField(data, maxChunkBytes, false) then
            return RejectWithContext(context, "invalid DPS fields", "schema")
        end
        local idx, total = spec:match("^(%d+)/(%d+)$")
        idx, total = tonumber(idx), tonumber(total)
        if not (idx and total and idx >= 1 and idx <= total
            and total >= 1 and total <= maxChunks) then
            return RejectWithContext(context,
                "invalid DPS chunk geometry", "schema")
        end
        local key = sender .. ":" .. transferId .. TransferScope(context)
        local entry = dpsInflight[key]
        if entry and TransferExpired(entry) then
            dpsInflight[key] = nil
            RememberBlockedTransfer("dps", key)
            entry = nil
        end
        if not entry then
            if TransferBlocked("dps", key) then return false end
            I.CleanExpired()
            if not CanStartTransfer(sender) then
                noteOutcome(context, "rejected", "queue")
                return false
            end
            local current = now()
            entry = {chunks={}, total=total, t0=current, lastSeen=current,
                sender=sender, transferId=transferId, bytes=0, received=0,
                context=context}
            dpsInflight[key] = entry
        end
        if entry.total ~= total or entry.sender ~= sender
            or entry.transferId ~= transferId
            or not I.SameContext(entry.context, context) then
            dpsInflight[key] = nil
            RememberBlockedTransfer("dps", key)
            noteMalformed()
            noteOutcome(context or entry.context, "rejected", "integrity")
            return false
        end
        local prior = entry.chunks[idx]
        if prior ~= nil then
            if prior ~= data then
                dpsInflight[key] = nil
                RememberBlockedTransfer("dps", key)
                noteMalformed()
                noteOutcome(context, "rejected", "integrity")
            end
            return false
        end
        if entry.bytes + #data > maxEncodedBytes then
            dpsInflight[key] = nil
            RememberBlockedTransfer("dps", key)
            noteMalformed()
            noteOutcome(context, "rejected", "schema")
            return false
        end
        entry.lastSeen = now()
        entry.chunks[idx] = data
        entry.bytes = entry.bytes + #data
        entry.received = entry.received + 1
        if entry.received ~= total then
            noteInbound({kind="dps_chunk",sender=sender,
                transferId=transferId,duplicate=false,
                requester=context and context.requester or nil,
                requestId=context and context.requestId or nil})
            return false
        end
        dpsInflight[key] = nil
        observe("dps_transfer_complete", {peer=sender,chunks=total,
            bytes=entry.bytes,outcome="complete"})
        local raw = base64Decode(table.concat(entry.chunks, "", 1, total))
        local record = raw and jsonDecode(raw)
        local schemaReason
        if type(record) == "table" then
            record, schemaReason = validateDpsPayload(record)
        end
        if not record then
            noteDpsRejection(schemaReason or "schema")
            noteMalformed()
            noteOutcome(context, "rejected",
                schemaReason == "integrity" and "integrity" or "schema")
            return false
        end
        local directOwner = samePeer(record.p or record.player, sender)
        local relayed = not directOwner
        if directOwner and record.x ~= nil then
            noteDpsRejection("relay_authorization")
            noteOutcome(context, "rejected", "ownership")
            log("RX", "DROP DPS owner payload with relay context from %s",
                tostring(sender))
            return false
        end
        if (relayed or context ~= nil)
            and not validateDpsRelay(record, sender, context) then
            log("RX", "DROP DPS response outside requested bucket context from %s",
                tostring(sender))
            return false
        end
        local committed = commitDps(record, sender, relayed, context)
        if committed then
            noteInbound({kind="dps_commit",sender=sender,
                transferId=transferId,
                requester=context and context.requester or nil,
                requestId=context and context.requestId or nil})
        end
        return committed
    end

    local function HandleBuildTransfer(parts, protocolSender)
        local buildId, lastMod, chunkSpec, data =
            parts[3], parts[4], parts[5], parts[6]
        local context
        if #parts == 8 then
            context = I.RequestContext(parts[7], parts[8])
            if not context then return rejectIncoming("invalid build context") end
        elseif #parts ~= 6 then
            return rejectIncoming("invalid build transfer")
        end
        if not validIdentifier(buildId, maxBuildIdBytes)
            or not validIntegerText(lastMod, 0)
            or not validField(chunkSpec, 16, false)
            or not validField(data, maxChunkBytes, false) then
            return RejectWithContext(context, "invalid build fields", "schema")
        end
        local idx, total = chunkSpec:match("^(%d+)/(%d+)$")
        idx, total = tonumber(idx), tonumber(total)
        if not (idx and total and idx >= 1 and total >= 1 and idx <= total
            and total <= maxChunks) then
            return RejectWithContext(context,
                "invalid build chunk geometry", "schema")
        end
        local key = protocolSender .. ":" .. buildId .. TransferScope(context)
        local entry = buildInflight[key]
        if entry and TransferExpired(entry) then
            buildInflight[key] = nil
            RememberBlockedTransfer("build", key)
            entry = nil
        end
        if not entry then
            if TransferBlocked("build", key) then return false end
            if total == 1 then
                if HandleCompleteBuild(buildId, lastMod, data,
                        protocolSender, context) then
                    noteInbound({kind="build_commit",sender=protocolSender,
                        buildId=buildId,
                        requester=context and context.requester or nil,
                        requestId=context and context.requestId or nil})
                    return acceptPeer(protocolSender)
                end
                return false
            end
            I.CleanExpired()
            if not CanStartTransfer(protocolSender) then
                noteOutcome(context, "rejected", "queue")
                return false
            end
            log("RX", "starting %d-chunk build '%s' from %s",
                total, tostring(buildId), tostring(protocolSender))
            local current = now()
            entry = {chunks={}, total=total, t0=current, lastSeen=current,
                buildId=buildId, lastMod=lastMod, sender=protocolSender,
                bytes=0, received=0,context=context}
            buildInflight[key] = entry
        end
        if total ~= entry.total or buildId ~= entry.buildId
            or protocolSender ~= entry.sender
            or tostring(lastMod) ~= tostring(entry.lastMod)
            or not I.SameContext(entry.context, context) then
            buildInflight[key] = nil
            RememberBlockedTransfer("build", key)
            noteMalformed()
            noteOutcome(context or entry.context, "rejected", "integrity")
            return false
        end
        local prior = entry.chunks[idx]
        if prior ~= nil then
            if prior ~= data then
                buildInflight[key] = nil
                RememberBlockedTransfer("build", key)
                noteMalformed()
                noteOutcome(context, "rejected", "integrity")
            end
            return false
        end
        if entry.bytes + #data > maxEncodedBytes then
            buildInflight[key] = nil
            RememberBlockedTransfer("build", key)
            noteMalformed()
            noteOutcome(context, "rejected", "schema")
            return false
        end
        entry.lastSeen = now()
        entry.chunks[idx] = data
        entry.bytes = entry.bytes + #data
        entry.received = entry.received + 1
        if entry.received ~= entry.total then
            noteInbound({kind="build_chunk",sender=protocolSender,
                buildId=buildId,duplicate=false,
                requester=context and context.requester or nil,
                requestId=context and context.requestId or nil})
            return false
        end
        local full = table.concat(entry.chunks, "", 1, entry.total)
        buildInflight[key] = nil
        log("RX", "transfer '%s' complete (%d/%d chunks, %d bytes)",
            tostring(buildId), entry.received, entry.total, #full)
        observe("build_transfer_complete", {id=buildId,peer=protocolSender,
            chunks=entry.total,bytes=#full,outcome="complete"})
        if HandleCompleteBuild(buildId, lastMod, full, protocolSender,
                context) then
            noteInbound({kind="build_commit",sender=protocolSender,
                buildId=buildId,
                requester=context and context.requester or nil,
                requestId=context and context.requestId or nil})
            return acceptPeer(protocolSender)
        end
        return false
    end

    function I.HandleIncoming(text, sender)
        if type(text) ~= "string" then return false end
        local claimedCode = text:match("^([^|]+)")
        if not peerCodes[claimedCode] then return false end
        if #text > maxWireBytes or text:find("[%c]") then
            return rejectIncoming("invalid wire length")
        end
        text = text:gsub("||", "|")
        local parts = splitWire(text)
        if not parts then return rejectIncoming("too many fields") end
        local code = parts[1]
        if not peerCodes[code] then return false end

        local protocolSender = parts[2]
        local actualSender = sender or protocolSender
        if not validPeerName(protocolSender) or not validPeerName(actualSender)
            or not sameTransportSender(protocolSender, actualSender) then
            log("RX", "DROP sender mismatch: wire=%s transport=%s",
                tostring(protocolSender), tostring(actualSender))
            return rejectIncoming("sender mismatch")
        end
        parts[2] = actualSender
        protocolSender = actualSender

        if code == codes.presence then
            if #parts ~= 3 or not validVersion(parts[3]) then
                return rejectIncoming("invalid presence")
            end
            return acceptPeer(protocolSender, parts[3])
        end

        if code == codes.request then
            if #parts < 2 or #parts > 6
                or (parts[3] ~= nil and parts[3] ~= ""
                    and not validHash(parts[3]))
                or (parts[4] ~= nil and parts[4] ~= ""
                    and not validHash(parts[4]))
                or (parts[5] ~= nil and parts[5] ~= ""
                    and not validIdentifier(parts[5], maxRequestIdBytes))
                or (parts[6] ~= nil and not validVersion(parts[6])) then
                return rejectIncoming("invalid request")
            end
            local accepted = handleRequest({
                requester=protocolSender,
                peerBuildHash=(parts[3] and parts[3] ~= "")
                    and parts[3] or "0",
                peerDpsHash=(parts[4] and parts[4] ~= "")
                    and parts[4] or "0",
                requestId=(parts[5] and parts[5] ~= "")
                    and parts[5] or nil,
            })
            if accepted then return acceptPeer(protocolSender, parts[6]) end
            return false
        end

        if code == codes.claim then
            local context = I.RequestContext(parts[3], parts[4])
            if #parts ~= 6 or not validPeerName(parts[3])
                or not validIdentifier(parts[4], maxRequestIdBytes)
                or not validField(parts[5], maxHashBytes, false)
                or not validField(parts[6], maxHashBytes, false) then
                return RejectWithContext(context,
                    "invalid legacy claim", "schema")
            end
            local accepted = handleLegacyClaim({responder=protocolSender,
                requester=parts[3],requestId=parts[4],
                buildHash=parts[5],dpsHash=parts[6]})
            if not accepted then return false end
            noteInbound({kind="legacy_claim",sender=protocolSender,
                requester=parts[3],requestId=parts[4]})
            return acceptPeer(protocolSender)
        end

        if code == codes.bucketClaim then
            local bucket = tonumber(parts[6])
            local context = I.RequestContext(parts[3], parts[4])
            if #parts ~= 7 or not validPeerName(parts[3])
                or not validIdentifier(parts[4], maxRequestIdBytes)
                or (parts[5] ~= "B" and parts[5] ~= "D")
                or not bucket or bucket ~= math.floor(bucket)
                or bucket < 1 or bucket > bucketCount
                or not validHash(parts[7]) then
                return RejectWithContext(context,
                    "invalid bucket claim", "schema")
            end
            local accepted = handleBucketClaim({responder=protocolSender,
                requester=parts[3],
                requestId=parts[4], kind=parts[5], bucket=bucket,
                hash=parts[7]})
            if not accepted then return false end
            noteInbound({kind="bucket_claim",sender=protocolSender,
                requester=parts[3],requestId=parts[4]})
            return acceptPeer(protocolSender)
        end

        if code == codes.delete then
            local context
            if #parts == 7 then
                context = I.RequestContext(parts[6], parts[7])
                if not context then return rejectIncoming("invalid delete context") end
            elseif #parts ~= 4 and #parts ~= 5 then
                return rejectIncoming("invalid delete")
            end
            if (#parts ~= 4 and #parts ~= 5 and #parts ~= 7)
                or not validIdentifier(parts[3], maxBuildIdBytes)
                or not validIntegerText(parts[4], 1)
                or (parts[5] ~= nil and parts[5] ~= ""
                    and not validPeerName(parts[5])) then
                return RejectWithContext(context, "invalid delete", "schema")
            end
            if handleDelete({sender=protocolSender, buildId=parts[3],
                stamp=parts[4], originAuthor=parts[5],context=context}) then
                noteInbound({kind="delete",sender=protocolSender,
                    buildId=parts[3],
                    requester=context and context.requester or nil,
                    requestId=context and context.requestId or nil})
                return acceptPeer(protocolSender)
            end
            return false
        end

        if code == codes.index then
            local context
            if #parts == 5 then
                context = I.RequestContext(parts[4], parts[5])
                if not context then return rejectIncoming("invalid summary context") end
            elseif #parts ~= 3 then
                return rejectIncoming("invalid build summary")
            end
            if not validField(parts[3], maxChunkBytes, false) then
                return RejectWithContext(context,
                    "invalid build summary", "schema")
            end
            local raw = base64Decode(parts[3])
            local data = raw and jsonDecode(raw)
            local accepted, changed, rejection =
                handleSummary(data, protocolSender, context)
            if not accepted then
                if rejection == "storage" then return false end
                return rejectIncoming("rejected build summary")
            end
            noteInbound({kind="summary",sender=protocolSender,
                requester=context and context.requester or nil,
                requestId=context and context.requestId or nil})
            if changed then requestDataViewRefresh() end
            return acceptPeer(protocolSender)
        end

        if code == codes.loadoutRequest then
            local requestId = #parts == 4 and parts[4] or nil
            if (#parts ~= 3 and #parts ~= 4)
                or not validIdentifier(parts[3], maxBuildIdBytes) then
                return rejectIncoming("invalid loadout request")
            end
            if requestId and not I.RequestContext(protocolSender, requestId) then
                return rejectIncoming("invalid loadout request context")
            end
            if not handleLoadoutRequest({requester=protocolSender,
                buildId=parts[3],requestId=requestId}) then return false end
            return acceptPeer(protocolSender)
        end

        if code == codes.loadoutClaim then
            local context
            if #parts == 5 then
                context = I.RequestContext(parts[3], parts[5])
                if not context then
                    return rejectIncoming("invalid loadout claim context")
                end
            elseif #parts ~= 4 then
                return rejectIncoming("invalid loadout claim")
            end
            if not validPeerName(parts[3])
                or not validIdentifier(parts[4], maxBuildIdBytes) then
                return RejectWithContext(context,
                    "invalid loadout claim", "schema")
            end
            local accepted = handleLoadoutClaim({responder=protocolSender,
                requester=parts[3], buildId=parts[4],requestId=parts[5]})
            if not accepted then return false end
            noteInbound({kind="loadout_claim",sender=protocolSender,
                buildId=parts[4],requester=parts[3],requestId=parts[5]})
            return acceptPeer(protocolSender)
        end

        if code == codes.dpsLegacy then
            if #parts ~= 7 then return rejectIncoming("invalid legacy DPS") end
            log("RX", "DROP legacy DPS submission without required evidence")
            return false
        end

        if code == codes.dps then
            if #parts ~= 5 and #parts ~= 8 then
                return rejectIncoming("invalid DPS transfer")
            end
            if HandleDpsTransfer(parts) then return acceptPeer(protocolSender) end
            return false
        end

        if code ~= codes.build or (#parts ~= 6 and #parts ~= 8) then
            return rejectIncoming("invalid build transfer")
        end
        return HandleBuildTransfer(parts, protocolSender)
    end

    function I.Reset()
        buildInflight, dpsInflight = {}, {}
        blockedTransfers, blockedTransferCount = {}, 0
    end

    return I
end
