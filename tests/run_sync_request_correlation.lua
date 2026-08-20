-- Stage 36.3 expected red: real protocol-7 response bytes must advance only
-- the matching capability-marked request. Legacy requestless traffic remains
-- valid ambient storage input and cannot keep a current request alive.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua")
dofile("core/SyncTransport.lua")
dofile("core/SyncCompatibility.lua")
dofile("core/SyncReconciler.lua")
dofile("core/SyncInbound.lua")
dofile("core/SyncDiagnostics.lua")
dofile("core/SyncSession.lua")
dofile("core/Sync.lua")
dofile("core/DpsCapture.lua")

local Sync = assert(Nexus.Sync)
local Codec = assert(Nexus.Codec)
local Catalog = assert(Nexus.BuildCatalog)
local DPS = assert(Nexus.DpsCapture)
local clock = 1000
local fixture = 0
GetTime = function() return clock end
UnitName = function() return "Alice" end
GetNormalizedRealmName = function() return "Ebonhold" end

local LOCAL_TRANSPORT = "Alice-Ebonhold"
local function ActualSender(sender)
    sender = tostring(sender or "")
    return sender:find("-", 1, true) and sender or (sender .. "-Ebonhold")
end

local function OwnerKey(sender)
    local name = tostring(sender or ""):match("^([^-]+)")
    return name and (name:lower() .. "@ebonhold") or nil
end

local failures, checks, controls = {}, 0, 0
local function Check(ok, label)
    checks = checks + 1
    if not ok then failures[#failures + 1] = label end
end

local function Control(ok, label)
    controls = controls + 1
    assert(ok, "green control failed: " .. tostring(label))
end

local function SplitWire(text)
    local out, start = {}, 1
    while true do
        local at = text:find("|", start, true)
        if not at then
            out[#out + 1] = text:sub(start)
            return out
        end
        out[#out + 1] = text:sub(start, at - 1)
        start = at + 1
    end
end

local function Pump(seconds, step)
    step = step or 0.2
    local target = clock + seconds
    while clock < target - 0.000001 do
        local elapsed = math.min(step, target - clock)
        clock = clock + elapsed
        Sync.OnUpdate(elapsed)
    end
end

local function FindSession()
    for index = 1, 80 do
        local _, value = debug.getupvalue(Sync.GetLeaderboardSyncStatus, index)
        if value == nil then break end
        if type(value) == "table"
            and type(value.StatusSnapshot) == "function"
            and type(value.NoteInbound) == "function" then
            return value
        end
    end
end

local Session = assert(FindSession(),
    "could not locate the real SyncSession owned by the Sync facade")

local function FindCompatibility()
    local seen = {}
    local function Inspect(fn, depth)
        if type(fn) ~= "function" or seen[fn] or depth > 4 then return nil end
        seen[fn] = true
        for index = 1, 80 do
            local _, value = debug.getupvalue(fn, index)
            if value == nil then break end
            if type(value) == "table"
                and type(value.PrepareSummary) == "function"
                and type(value.CanonicalBuildHashes) == "function" then
                return value
            end
            if type(value) == "function" then
                local found = Inspect(value, depth + 1)
                if found then return found end
            end
        end
        return nil
    end
    return Inspect(Sync.GetCompatibilityHashes, 0)
end

local Compatibility = assert(FindCompatibility(),
    "could not locate the real SyncCompatibility owned by the Sync facade")

local function LatestRequest()
    for index = #H.sentChatMessages, 1, -1 do
        local wire = H.sentChatMessages[index].text:gsub("||", "|")
        if wire:find("^WLRQ|") then
            local parts = SplitWire(wire)
            return parts[5], wire
        end
    end
end

local function BeginManual()
    fixture = fixture + 1
    clock = 1000 + fixture * 1000
    NexusDB = {communityBuilds={},syncTombstones={}}
    H.sentChatMessages = {}
    H.joinedChannels = {}
    DPS.Init({}, Sync)
    Sync.Init(Codec, {})
    Control(Sync.IsConnected(), "fixture joined the named Sync channel")
    local queued, why = Sync.RequestSync()
    Control(queued == true, "manual request queued: " .. tostring(why))
    Pump(1.2)
    local requestId, wire = LatestRequest()
    Control(type(requestId) == "string" and requestId ~= ""
            and type(wire) == "string",
        "manual request reached the actual transport")
    Control(Sync.Stats().requestId == requestId
            and Sync.Stats().queueOutcome == "sent",
        "request diagnostics follow the sent request")
    return requestId, clock
end

local function EncodeBuild(id, author, stamp)
    return Codec.Base64Encode(Codec.JSONEncode({
        id=id,t="Correlation " .. id,a=author,o=OwnerKey(author),
        c="MAGE",m=stamp,
        e={{410001,3,1}},
    }))
end

local function Chunks(encoded, total)
    local out = {}
    local size = math.ceil(#encoded / total)
    for index = 1, total do
        out[index] = encoded:sub((index - 1) * size + 1, index * size)
    end
    return out
end

local function BuildWire(sender, id, stamp, index, total, data, context)
    local wire = string.format("WLRB|%s|%s|%d|%d/%d|%s",
        sender, id, stamp, index, total, data)
    if context then
        wire = wire .. "|" .. context.requester .. "|" .. context.requestId
    end
    return wire
end

local function SendSingle(id, stamp, context, sender)
    sender = sender or "Bob"
    return Sync.HandleIncoming(BuildWire(sender, id, stamp, 1, 1,
        EncodeBuild(id, sender, stamp), context), ActualSender(sender))
end

local function SummaryWire(sender, id, stamp, context)
    local payload = {
        id=id,t="Summary " .. id,a=sender,o=OwnerKey(sender),
        c="MAGE",m=stamp,
        h="36a3",n=3,
    }
    local wire = "WLBI|" .. sender .. "|"
        .. Codec.Base64Encode(Codec.JSONEncode(payload))
    if context then
        wire = wire .. "|" .. context.requester .. "|" .. context.requestId
    end
    return wire
end

local function CompactDps(player, dps, stamp, context)
    local echoes = {
        {spellId=470001 + fixture * 10,stacks=1},
        {spellId=470002 + fixture * 10,stacks=2},
    }
    local record = {
        v=7,f=DPS.GetEchoKey(echoes),h=DPS.GetEchoHash(echoes),e=echoes,
        c="dummy",d=dps,u=65,t=stamp,p=player,l=80,k="MAGE",
        o=player:lower() .. "@ebonhold",r="ebonhold",
    }
    if context and context.relay then
        record.x = {n=context.requester,i=context.requestId,b=context.bucket}
    end
    return record
end

local function DpsChunkWire(sender, transferId, index, total, data, context)
    local wire = string.format("WLD2|%s|%s|%d/%d|%s",
        sender, transferId, index, total, data)
    if context then
        wire = wire .. "|" .. context.requester .. "|"
            .. context.requestId .. "|" .. tostring(context.bucket)
    end
    return wire
end

local function SendDpsRecord(sender, transferId, record, context)
    local data = Codec.Base64Encode(Codec.JSONEncode(record))
    local total = math.max(1, math.ceil(#data / 96))
    local chunks = Chunks(data, total)
    local accepted = false
    for index = 1, total do
        accepted = Sync.HandleIncoming(DpsChunkWire(sender, transferId,
            index, total, chunks[index], context), ActualSender(sender))
    end
    return accepted
end

local function PutBuild(id, author, stamp, complete)
    local echoes
    if complete ~= false then
        echoes = {{spellId=480001 + fixture,quality=3,stacks=2}}
    end
    local record = {
        id=id,title="Wire " .. id,author=author,class="MAGE",
        ownerKey=OwnerKey(author),
        postedAt=stamp,lastModified=stamp,isMine=author == "Alice",
        ownerVerified=true,echoes=echoes,echoCount=echoes and 2 or 2,
        loadoutAvailable=echoes ~= nil,
        fingerprintHash=echoes and nil or "36b3",
    }
    local stored = Catalog.Put(record)
    return stored ~= false and record or nil
end

local function FindSentWire(code, predicate)
    for _, message in ipairs(H.sentChatMessages) do
        local wire = tostring(message.text or ""):gsub("||", "|")
        if wire:find("^" .. code .. "|", 1, false) then
            local parts = SplitWire(wire)
            if not predicate or predicate(parts, wire) then
                return parts, wire
            end
        end
    end
end

local function Stored(id)
    local row = Catalog.Get(id)
    return type(row) == "table" and row.id == id
end

local function RequestOutcome()
    local stats = Sync.Stats()
    return {
        requestId=stats.requestId,useful=stats.useful == true,
        new=tonumber(stats.requestNew) or 0,
        updated=tonumber(stats.requestUpdated) or 0,
        duplicates=tonumber(stats.requestDuplicates) or 0,
        rejected=tonumber(stats.requestRejected) or 0,
        unrelated=tonumber(stats.requestUnrelated) or 0,
        lastReason=stats.requestLastReason,
    }
end

local function FlatSanitized(value)
    if type(value) ~= "table" then return false end
    local fields = 0
    for key, item in pairs(value) do
        fields = fields + 1
        if type(key) ~= "string" then return false end
        local kind = type(item)
        if kind ~= "number" and kind ~= "string" and kind ~= "boolean" then
            return false
        end
        if kind == "string" and #item > 96 then return false end
        local lower = key:lower()
        if lower:find("payload", 1, true) or lower:find("echo", 1, true)
            or lower:find("packet", 1, true) or lower:find("message", 1, true)
            or lower:find("text", 1, true) then return false end
    end
    return fields <= 64
end

------------------------------------------------------------------------
-- A. A local protocol-7 request advertises the correlation capability. A
-- matching encoded build is admitted, stored, counted, and extends quiet,
-- while repeated useful work can never extend the absolute receive lifetime.
------------------------------------------------------------------------

local matchingId, matchingSent = BeginManual()
Check(matchingId:find("^c1%-") ~= nil,
    "marked-request: local protocol-7 request lacks the c1 capability prefix")
clock = matchingSent + 55
local matchingAccepted = SendSingle("matching-build-1", 101, {
    requester=LOCAL_TRANSPORT,requestId=matchingId,
})
local matchingOutcome = RequestOutcome()
Check(matchingAccepted and Stored("matching-build-1")
        and matchingOutcome.requestId == matchingId
        and matchingOutcome.useful and matchingOutcome.new == 1
        and matchingOutcome.updated == 0 and matchingOutcome.unrelated == 0,
    "matching-response: encoded matching WLRB was not stored and attributed once")
clock = matchingSent + 61
Check(Session.StatusSnapshot().receiving == true,
    "matching-quiet: accepted matching WLRB did not extend the quiet window")
for index, offset in ipairs({80,110,140,170}) do
    clock = matchingSent + offset
    SendSingle("matching-build-" .. tostring(index + 1), 101 + index, {
        requester=LOCAL_TRANSPORT,requestId=matchingId,
    })
end
clock = matchingSent + 181
Control(Session.StatusSnapshot().receiving == false,
    "matching work cannot extend the absolute receive lifetime")

------------------------------------------------------------------------
-- B. The byte-identical six-field legacy packet remains accepted storage
-- input, but it is ambient: no useful/current counters and no quiet extension.
------------------------------------------------------------------------

local ambientId, ambientSent = BeginManual()
clock = ambientSent + 55
Control(SendSingle("ambient-build", 201, nil) == true,
    "requestless protocol-7 build remains store compatible")
Control(Stored("ambient-build"),
    "requestless protocol-7 build reached the catalog")
local ambientOutcome = RequestOutcome()
Check(ambientOutcome.requestId == ambientId and not ambientOutcome.useful
        and ambientOutcome.new == 0 and ambientOutcome.updated == 0
        and ambientOutcome.rejected == 0 and ambientOutcome.unrelated == 0
        and Sync.LastSyncNewCount() == 0,
    "ambient-attribution: requestless accepted build contaminated current counters")
clock = ambientSent + 61
Check(Session.StatusSnapshot().receiving == false,
    "ambient-quiet: requestless accepted build extended the current quiet window")

------------------------------------------------------------------------
-- C. Request-related diagnostics count only matching admitted work. An
-- ambient partial transfer remains visible globally but never as request work,
-- and the public projection stays a flat bounded scalar snapshot.
------------------------------------------------------------------------

local diagnosticId, diagnosticSent = BeginManual()
clock = diagnosticSent + 10
local ambientEncoded = EncodeBuild("ambient-partial", "Bob", 250)
local ambientChunks = Chunks(ambientEncoded, 2)
Control(Sync.HandleIncoming(BuildWire("Bob", "ambient-partial", 250,
    1, 2, ambientChunks[1], nil), "Bob") == false,
    "partial ambient build does not report a complete commit")
Control(Sync.WorkState().buildInflight == 1,
    "partial ambient transfer remains globally observable")
local _, _, _, diagnosticWork = Sync.GetLeaderboardSyncStatus()
Check(diagnosticWork.requestRelated == 0,
    "request-related-projection: ambient inflight work counted as request work")
Control(FlatSanitized(diagnosticWork)
        and type(diagnosticId) == "string",
    "request work diagnostics are flat sanitized scalars")

------------------------------------------------------------------------
-- D. Valid stale and foreign context remains ambient store input. It records
-- one bounded unrelated result, but cannot become useful or extend quiet.
------------------------------------------------------------------------

local staleActive, staleSent = BeginManual()
clock = staleSent + 55
local staleAccepted = SendSingle("stale-build", 301, {
    requester=LOCAL_TRANSPORT,requestId="c1-stale-request",
})
local staleOutcome = RequestOutcome()
clock = staleSent + 61
Check(staleAccepted and Stored("stale-build")
        and staleOutcome.requestId == staleActive
        and not staleOutcome.useful and staleOutcome.new == 0
        and staleOutcome.unrelated == 1
        and Sync.LastSyncNewCount() == 0
        and Session.StatusSnapshot().receiving == false,
    "stale-context: stale request identity was rejected or contaminated current work")

local foreignActive, foreignSent = BeginManual()
clock = foreignSent + 55
local foreignAccepted = SendSingle("foreign-build", 302, {
    requester="Mallory-Ebonhold",requestId=foreignActive,
})
local foreignOutcome = RequestOutcome()
clock = foreignSent + 61
Check(foreignAccepted and Stored("foreign-build")
        and foreignOutcome.requestId == foreignActive
        and not foreignOutcome.useful and foreignOutcome.new == 0
        and foreignOutcome.unrelated == 1
        and Sync.LastSyncNewCount() == 0
        and Session.StatusSnapshot().receiving == false,
    "foreign-context: foreign requester was rejected or contaminated current work")

------------------------------------------------------------------------
-- E. Every chunk repeats immutable context. The first unique matching chunk
-- is progress; an identical duplicate cannot refresh transfer/quiet age, and
-- a conflicting duplicate kills the transfer with one matching rejection.
------------------------------------------------------------------------

local duplicateId, duplicateSent = BeginManual()
local duplicateEncoded = EncodeBuild("duplicate-chunks", "Bob", 401)
local duplicateChunks = Chunks(duplicateEncoded, 2)
local duplicateContext = {requester=LOCAL_TRANSPORT,requestId=duplicateId}
clock = duplicateSent + 55
Sync.HandleIncoming(BuildWire("Bob", "duplicate-chunks", 401, 1, 2,
    duplicateChunks[1], duplicateContext), "Bob")
local duplicateStarted = Sync.WorkState().buildInflight == 1
clock = duplicateSent + 80
Sync.HandleIncoming(BuildWire("Bob", "duplicate-chunks", 401, 1, 2,
    duplicateChunks[1], duplicateContext), "Bob")
clock = duplicateSent + 86
Sync.OnUpdate(0)
Check(duplicateStarted and Sync.WorkState().buildInflight == 0
        and Session.StatusSnapshot().receiving == false,
    "duplicate-chunk: identical chunk refreshed transfer or request quiet age")

local conflictId, conflictSent = BeginManual()
local conflictEncoded = EncodeBuild("conflict-chunks", "Bob", 402)
local conflictChunks = Chunks(conflictEncoded, 2)
local conflictContext = {requester=LOCAL_TRANSPORT,requestId=conflictId}
clock = conflictSent + 55
Sync.HandleIncoming(BuildWire("Bob", "conflict-chunks", 402, 1, 2,
    conflictChunks[1], conflictContext), "Bob")
local conflictStarted = Sync.WorkState().buildInflight == 1
clock = conflictSent + 80
Sync.HandleIncoming(BuildWire("Bob", "conflict-chunks", 402, 1, 2,
    conflictChunks[1] .. "A", conflictContext), "Bob")
clock = conflictSent + 86
local conflictOutcome = RequestOutcome()
Check(conflictStarted and Sync.WorkState().buildInflight == 0
        and Session.StatusSnapshot().receiving == false
        and conflictOutcome.rejected == 1 and conflictOutcome.new == 0,
    "conflicting-chunk: conflict did not terminate once without useful progress")

------------------------------------------------------------------------
-- F. After the old request expires, a later manual request owns a new marked
-- identity. An old response is ambient/unrelated; the new matching response is
-- useful and may reopen quiet within only the new fixed absolute lifetime.
------------------------------------------------------------------------

local oldId, oldSent = BeginManual()
clock = oldSent + 301
Sync.OnUpdate(0)
Control(Session.StatusSnapshot().converging == false
        and Session.StatusSnapshot().terminalReason == "expired",
    "first request reached its fixed expiry terminal")
local laterQueued, laterWhy = Sync.RequestSync()
Control(laterQueued == true,
    "later manual request queued after expiry: " .. tostring(laterWhy))
H.sentChatMessages = {}
Pump(1.2)
local laterId = assert(LatestRequest())
local laterSent = clock
Check(laterId ~= oldId and laterId:find("^c1%-") ~= nil,
    "later-request: replacement request lacks a distinct marked identity")
clock = laterSent + 55
local oldAccepted = SendSingle("expired-old-build", 501, {
    requester=LOCAL_TRANSPORT,requestId=oldId,
})
local afterOld = RequestOutcome()
clock = laterSent + 61
local oldDidNotExtend = Session.StatusSnapshot().receiving == false
clock = laterSent + 62
local laterAccepted = SendSingle("later-matching-build", 502, {
    requester=LOCAL_TRANSPORT,requestId=laterId,
})
local afterLater = RequestOutcome()
Check(oldAccepted and laterAccepted and Stored("expired-old-build")
        and Stored("later-matching-build") and oldDidNotExtend
        and afterOld.requestId == laterId and not afterOld.useful
        and afterOld.new == 0 and afterOld.unrelated == 1
        and afterLater.requestId == laterId and afterLater.useful
        and afterLater.new == 1 and afterLater.unrelated == 1
        and Session.StatusSnapshot().receiving == true,
    "expiry-and-later-request: old/new encoded responses crossed request ownership")

------------------------------------------------------------------------
-- G. Summary and malformed-result owners use the same exact correlation.
-- Legacy WLBI remains byte-compatible ambient input; a matching malformed
-- build is rejected once and cannot refresh the request quiet clock.
------------------------------------------------------------------------

do
local summaryId, summarySent = BeginManual()
clock = summarySent + 55
local summaryAccepted = Sync.HandleIncoming(SummaryWire("Bob",
    "context-summary", 601, {requester=LOCAL_TRANSPORT,
        requestId=summaryId}), "Bob-Ebonhold")
local summaryOutcome = RequestOutcome()
clock = summarySent + 61
Check(summaryAccepted and Stored("context-summary")
        and summaryOutcome.new == 1 and summaryOutcome.updated == 0
        and summaryOutcome.rejected == 0
        and Session.StatusSnapshot().receiving == true,
    "contextual-summary: matching WLBI was not stored and attributed once")

local legacySummaryId, legacySummarySent = BeginManual()
clock = legacySummarySent + 55
Control(Sync.HandleIncoming(SummaryWire("Bob",
    "legacy-summary", 602, nil), "Bob-Ebonhold") == true,
    "legacy three-field WLBI remains accepted")
local legacySummaryOutcome = RequestOutcome()
clock = legacySummarySent + 61
Check(Stored("legacy-summary") and legacySummaryOutcome.requestId == legacySummaryId
        and legacySummaryOutcome.new == 0
        and legacySummaryOutcome.updated == 0
        and legacySummaryOutcome.rejected == 0
        and legacySummaryOutcome.unrelated == 0
        and Session.StatusSnapshot().receiving == false,
    "legacy-summary: requestless WLBI contaminated or extended current work")

local malformedId, malformedSent = BeginManual()
clock = malformedSent + 55
Control(Sync.HandleIncoming(BuildWire("Bob", "matching-malformed", 603,
    1, 1, "!!!!", {requester=LOCAL_TRANSPORT,
        requestId=malformedId}), "Bob") == false,
    "matching malformed WLRB remained rejected")
local malformedOutcome = RequestOutcome()
clock = malformedSent + 61
Check(malformedOutcome.rejected == 1 and malformedOutcome.new == 0
        and malformedOutcome.updated == 0 and not malformedOutcome.useful
        and Session.StatusSnapshot().receiving == false,
    "matching-reject: malformed contextual WLRB was not attributed exactly once")
end

------------------------------------------------------------------------
-- H. Deletes retain their legacy five-field form and acquire request context
-- only for a marked response. The represented tombstone mutation is identical;
-- only the matching contextual delete belongs to the current request.
------------------------------------------------------------------------

do
local deleteId, deleteSent = BeginManual()
Control(PutBuild("context-delete", "Bob", 610, true) ~= nil,
    "contextual delete fixture stored its remote build")
clock = deleteSent + 55
local deleteAccepted = Sync.HandleIncoming(table.concat({
    "WLRD","Bob","context-delete","611","Bob",LOCAL_TRANSPORT,deleteId,
}, "|"), "Bob-Ebonhold")
local deleteOutcome = RequestOutcome()
clock = deleteSent + 61
Check(deleteAccepted and not Stored("context-delete")
        and deleteOutcome.updated == 1 and deleteOutcome.new == 0
        and deleteOutcome.rejected == 0 and deleteOutcome.useful
        and Session.StatusSnapshot().receiving == true,
    "contextual-delete: matching WLRD did not mutate and attribute once")

local legacyDeleteId, legacyDeleteSent = BeginManual()
Control(PutBuild("legacy-delete", "Bob", 620, true) ~= nil,
    "legacy delete fixture stored its remote build")
clock = legacyDeleteSent + 55
Control(Sync.HandleIncoming(
    "WLRD|Bob|legacy-delete|621|Bob", "Bob-Ebonhold") == true,
    "legacy five-field WLRD remains accepted")
local legacyDeleteOutcome = RequestOutcome()
clock = legacyDeleteSent + 61
Check(not Stored("legacy-delete")
        and legacyDeleteOutcome.requestId == legacyDeleteId
        and legacyDeleteOutcome.new == 0
        and legacyDeleteOutcome.updated == 0
        and legacyDeleteOutcome.rejected == 0
        and legacyDeleteOutcome.unrelated == 0
        and Session.StatusSnapshot().receiving == false,
    "legacy-delete: requestless WLRD contaminated or extended current work")
end

------------------------------------------------------------------------
-- I. Whole-state, bucket, and loadout claims are bounded request progress.
-- Matching marked claims extend quiet without inventing useful data. Stale
-- identifiers are one unrelated result; requestless WLLC remains ambient.
------------------------------------------------------------------------

do
local wholeClaimId, wholeClaimSent = BeginManual()
local claimBuildHash, claimDpsHash = Sync.GetCompatibilityHashes()
clock = wholeClaimSent + 55
Control(Sync.HandleIncoming(table.concat({"WLRC","ClaimPeer",LOCAL_TRANSPORT,
    wholeClaimId,claimBuildHash,claimDpsHash}, "|"),
    "ClaimPeer-Ebonhold") == true,
    "matching WLRC was accepted by the real session owner")
local wholeClaimOutcome = RequestOutcome()
clock = wholeClaimSent + 61
Check(not wholeClaimOutcome.useful and wholeClaimOutcome.new == 0
        and wholeClaimOutcome.updated == 0
        and wholeClaimOutcome.unrelated == 0
        and Session.StatusSnapshot().receiving == true,
    "matching-WLRC: claim invented useful work or failed to extend quiet")

local staleClaimId, staleClaimSent = BeginManual()
clock = staleClaimSent + 55
Control(Sync.HandleIncoming(table.concat({"WLRC","ClaimPeer",LOCAL_TRANSPORT,
    "legacy-claim-id",claimBuildHash,claimDpsHash}, "|"),
    "ClaimPeer-Ebonhold") == false,
    "stale unmarked WLRC did not masquerade as matching")
local staleClaimOutcome = RequestOutcome()
clock = staleClaimSent + 61
Check(staleClaimOutcome.requestId == staleClaimId
        and staleClaimOutcome.unrelated == 1
        and not staleClaimOutcome.useful
        and Session.StatusSnapshot().receiving == false,
    "stale-WLRC: stale claim lacked one bounded unrelated attribution")

local bucketClaimId, bucketClaimSent = BeginManual()
clock = bucketClaimSent + 55
Control(Sync.HandleIncoming(table.concat({"WLBC","ClaimPeer",LOCAL_TRANSPORT,
    bucketClaimId,"B","1","0"}, "|"),
    "ClaimPeer-Ebonhold") == true,
    "matching WLBC was accepted by the real session owner")
clock = bucketClaimSent + 61
Check(Session.StatusSnapshot().receiving == true
        and RequestOutcome().new == 0 and RequestOutcome().updated == 0,
    "matching-WLBC: bucket claim failed bounded quiet attribution")

local staleBucketId, staleBucketSent = BeginManual()
clock = staleBucketSent + 55
Control(Sync.HandleIncoming(table.concat({"WLBC","ClaimPeer",LOCAL_TRANSPORT,
    "legacy-bucket-id","B","1","0"}, "|"),
    "ClaimPeer-Ebonhold") == false,
    "stale unmarked WLBC did not masquerade as matching")
local staleBucketOutcome = RequestOutcome()
clock = staleBucketSent + 61
Check(staleBucketOutcome.requestId == staleBucketId
        and staleBucketOutcome.unrelated == 1
        and Session.StatusSnapshot().receiving == false,
    "stale-WLBC: stale bucket claim lacked bounded unrelated attribution")

local loadoutClaimId, loadoutClaimSent = BeginManual()
clock = loadoutClaimSent + 55
Control(Sync.HandleIncoming(table.concat({"WLLC","ClaimPeer",LOCAL_TRANSPORT,
    "loadout-target",loadoutClaimId}, "|"),
    "ClaimPeer-Ebonhold") == true,
    "matching contextual WLLC was accepted")
clock = loadoutClaimSent + 61
Check(Session.StatusSnapshot().receiving == true
        and RequestOutcome().new == 0 and RequestOutcome().updated == 0,
    "matching-WLLC: loadout claim failed bounded quiet attribution")

local legacyLoadoutClaimId, legacyLoadoutClaimSent = BeginManual()
clock = legacyLoadoutClaimSent + 55
Control(Sync.HandleIncoming(
    "WLLC|ClaimPeer|Alice|loadout-target", "ClaimPeer") == false,
    "legacy WLLC remained ambient rather than matching by guess")
local legacyLoadoutClaimOutcome = RequestOutcome()
clock = legacyLoadoutClaimSent + 61
Check(legacyLoadoutClaimOutcome.requestId == legacyLoadoutClaimId
        and legacyLoadoutClaimOutcome.new == 0
        and legacyLoadoutClaimOutcome.updated == 0
        and legacyLoadoutClaimOutcome.unrelated == 0
        and Session.StatusSnapshot().receiving == false,
    "legacy-WLLC: requestless claim contaminated or extended current work")

local staleLoadoutClaimId, staleLoadoutClaimSent = BeginManual()
clock = staleLoadoutClaimSent + 55
Control(Sync.HandleIncoming(table.concat({"WLLC","ClaimPeer",LOCAL_TRANSPORT,
    "loadout-target","c1-stale-loadout-claim"}, "|"),
    "ClaimPeer-Ebonhold") == false,
    "stale contextual WLLC did not masquerade as matching")
local staleLoadoutClaimOutcome = RequestOutcome()
clock = staleLoadoutClaimSent + 61
Check(staleLoadoutClaimOutcome.requestId == staleLoadoutClaimId
        and staleLoadoutClaimOutcome.new == 0
        and staleLoadoutClaimOutcome.updated == 0
        and staleLoadoutClaimOutcome.rejected == 0
        and staleLoadoutClaimOutcome.unrelated == 1
        and not staleLoadoutClaimOutcome.useful
        and Session.StatusSnapshot().receiving == false,
    "stale-WLLC: stale loadout claim lacked one bounded unrelated attribution")
end

------------------------------------------------------------------------
-- J. Loadout request/response bytes remain legacy-exact unless WLLQ carries a
-- marked ID. Reusing requester/build with a later marked identity transfers
-- ownership to the later request instead of answering under stale context.
------------------------------------------------------------------------

do
local function CaptureLoadoutResponse(buildId, requestId)
    BeginManual()
    Control(PutBuild(buildId, "Alice", 700 + fixture, true) ~= nil,
        "loadout response fixture stored " .. buildId)
    H.sentChatMessages = {}
    local wire = "WLLQ|Bob|" .. buildId
    if requestId then wire = wire .. "|" .. requestId end
    Control(Sync.HandleIncoming(wire, "Bob-Ebonhold") == true,
        "loadout request scheduled " .. buildId)
    Pump(25)
    return FindSentWire("WLRB", function(parts)
            return parts[3] == buildId
        end), FindSentWire("WLLC", function(parts)
            return parts[4] == buildId
        end)
end

local legacyLoadoutBuild, legacyLoadoutClaim = CaptureLoadoutResponse(
    "legacy-loadout-wire", nil)
Check(legacyLoadoutBuild and #legacyLoadoutBuild == 6
        and legacyLoadoutClaim and #legacyLoadoutClaim == 4,
    "legacy-WLLQ: response changed WLRB/WLLC field counts")

local contextualLoadoutId = "c1-loadout-wire"
local contextualLoadoutBuild, contextualLoadoutClaim = CaptureLoadoutResponse(
    "context-loadout-wire", contextualLoadoutId)
Check(contextualLoadoutBuild and #contextualLoadoutBuild == 8
        and contextualLoadoutBuild[7] == "Bob-Ebonhold"
        and contextualLoadoutBuild[8] == contextualLoadoutId
        and contextualLoadoutClaim and #contextualLoadoutClaim == 5
        and contextualLoadoutClaim[3] == "Bob-Ebonhold"
        and contextualLoadoutClaim[5] == contextualLoadoutId,
    "contextual-WLLQ: WLRB/WLLC did not repeat exact request ownership")

local function PrepareSummaryResponse(buildId, requestId)
    local build = assert(PutBuild(buildId, "Alice", 720 + fixture, false))
    local context = requestId
        and {requester="Bob-Ebonhold",requestId=requestId} or nil
    local prepared = assert(Compatibility.PrepareSummary(build, context))
    return SplitWire(assert(prepared.messages[1]))
end

BeginManual()
local legacySummaryResponse = PrepareSummaryResponse(
    "legacy-summary-wire", nil)
Check(legacySummaryResponse and #legacySummaryResponse == 3,
    "legacy-WLRQ: WLBI response gained contextual wire fields")
local contextualSummaryResponse = PrepareSummaryResponse(
    "context-summary-wire", "c1-summary-wire-request")
Check(contextualSummaryResponse and #contextualSummaryResponse == 5
        and contextualSummaryResponse[4] == "Bob-Ebonhold"
        and contextualSummaryResponse[5] == "c1-summary-wire-request",
    "contextual-WLRQ: WLBI response lost exact request ownership")

BeginManual()
Control(PutBuild("overlap-loadout-wire", "Alice", 730, true) ~= nil,
    "overlapping loadout fixture stored")
H.sentChatMessages = {}
Control(Sync.HandleIncoming(
    "WLLQ|Bob|overlap-loadout-wire|c1-loadout-old", "Bob-Ebonhold") == true,
    "first overlapping WLLQ scheduled")
Control(Sync.HandleIncoming(
    "WLLQ|Bob|overlap-loadout-wire|c1-loadout-new", "Bob-Ebonhold") == true,
    "later overlapping WLLQ scheduled")
Pump(25)
local overlapBuild = FindSentWire("WLRB", function(parts)
    return parts[3] == "overlap-loadout-wire"
end)
local overlapClaim = FindSentWire("WLLC", function(parts)
    return parts[4] == "overlap-loadout-wire"
end)
Check(overlapBuild and overlapBuild[7] == "Bob-Ebonhold"
        and overlapBuild[8] == "c1-loadout-new"
        and overlapClaim and overlapClaim[5] == "c1-loadout-new",
    "overlapping-WLLQ: later request inherited stale loadout response context")
end

------------------------------------------------------------------------
-- K. Direct and authorized-relay WLD2 records use the same exact envelope.
-- A direct record with the wrong deterministic bucket is rejected; legacy
-- requestless WLD2 remains valid ambient storage input.
------------------------------------------------------------------------

do
local directDpsId, directDpsSent = BeginManual()
local directRecord = CompactDps("DirectDps", 910000, 801)
local directBucket = assert(DPS.SyncBucket("dummy", "DirectDps"))
clock = directDpsSent + 55
local directAccepted = SendDpsRecord("DirectDps", "direct-context",
    directRecord, {requester=LOCAL_TRANSPORT,
        requestId=directDpsId,bucket=directBucket})
local directOutcome = RequestOutcome()
clock = directDpsSent + 61
Check(directAccepted and directOutcome.updated == 1
        and directOutcome.new == 0 and directOutcome.rejected == 0
        and directOutcome.useful and Session.StatusSnapshot().receiving == true,
    "direct-WLD2: matching owner record lacked exact useful attribution")

local ambientDpsId, ambientDpsSent = BeginManual()
local ambientRecord = CompactDps("AmbientDps", 920000, 802)
clock = ambientDpsSent + 55
Control(SendDpsRecord("AmbientDps", "direct-ambient",
    ambientRecord, nil) == true,
    "legacy requestless direct WLD2 remains accepted")
local ambientDpsOutcome = RequestOutcome()
clock = ambientDpsSent + 61
Check(ambientDpsOutcome.requestId == ambientDpsId
        and ambientDpsOutcome.new == 0 and ambientDpsOutcome.updated == 0
        and ambientDpsOutcome.rejected == 0
        and ambientDpsOutcome.unrelated == 0
        and Session.StatusSnapshot().receiving == false,
    "ambient-WLD2: requestless direct record contaminated current work")

local staleDirectId, staleDirectSent = BeginManual()
local staleDirectRecord = CompactDps("StaleDirectDps", 925000, 805)
local staleDirectBucket = assert(DPS.SyncBucket("dummy", "StaleDirectDps"))
clock = staleDirectSent + 55
local staleDirectAccepted = SendDpsRecord("StaleDirectDps", "direct-stale",
    staleDirectRecord, {requester=LOCAL_TRANSPORT,
        requestId="c1-stale-direct",
        bucket=staleDirectBucket})
local staleDirectOutcome = RequestOutcome()
local staleDirectStored = NexusDB and NexusDB.dpsCapture
    and NexusDB.dpsCapture.characterBest
    and NexusDB.dpsCapture.characterBest.dummy
    and NexusDB.dpsCapture.characterBest.dummy["staledirectdps@ebonhold"] ~= nil
clock = staleDirectSent + 61
Check(staleDirectAccepted and staleDirectStored
        and staleDirectOutcome.requestId == staleDirectId
        and staleDirectOutcome.new == 0 and staleDirectOutcome.updated == 0
        and staleDirectOutcome.rejected == 0
        and staleDirectOutcome.unrelated == 1
        and not staleDirectOutcome.useful
        and Session.StatusSnapshot().receiving == false,
    "stale-direct-WLD2: valid stale context was rejected or contaminated current work")

local foreignDirectId, foreignDirectSent = BeginManual()
local foreignDirectRecord = CompactDps("ForeignDirectDps", 927000, 806)
local foreignDirectBucket = assert(DPS.SyncBucket("dummy", "ForeignDirectDps"))
clock = foreignDirectSent + 55
local foreignDirectAccepted = SendDpsRecord("ForeignDirectDps",
    "direct-foreign", foreignDirectRecord, {requester="Mallory-Ebonhold",
        requestId=foreignDirectId,bucket=foreignDirectBucket})
local foreignDirectOutcome = RequestOutcome()
local foreignDirectStored = NexusDB and NexusDB.dpsCapture
    and NexusDB.dpsCapture.characterBest
    and NexusDB.dpsCapture.characterBest.dummy
    and NexusDB.dpsCapture.characterBest.dummy["foreigndirectdps@ebonhold"] ~= nil
clock = foreignDirectSent + 61
Check(foreignDirectAccepted and foreignDirectStored
        and foreignDirectOutcome.requestId == foreignDirectId
        and foreignDirectOutcome.new == 0 and foreignDirectOutcome.updated == 0
        and foreignDirectOutcome.rejected == 0
        and foreignDirectOutcome.unrelated == 1
        and not foreignDirectOutcome.useful
        and Session.StatusSnapshot().receiving == false,
    "foreign-direct-WLD2: valid foreign context was rejected or contaminated current work")

local relayDpsId, relayDpsSent = BeginManual()
local relayBucket = assert(DPS.SyncBucket("dummy", "RelayOrigin"))
local relayContext = {requester=LOCAL_TRANSPORT,requestId=relayDpsId,
    bucket=relayBucket,relay=true}
local relayRecord = CompactDps("RelayOrigin", 930000, 803, relayContext)
clock = relayDpsSent + 55
local relayAccepted = SendDpsRecord("RelayPeer", "authorized-relay",
    relayRecord, relayContext)
local relayOutcome = RequestOutcome()
clock = relayDpsSent + 61
Check(relayAccepted and relayOutcome.updated == 1
        and relayOutcome.rejected == 0 and relayOutcome.useful
        and Session.StatusSnapshot().receiving == true,
    "relay-WLD2: exact authorized relay was not accepted and attributed")

local wrongBucketId, wrongBucketSent = BeginManual()
local wrongBucketRecord = CompactDps("WrongBucketDps", 940000, 804)
local correctBucket = assert(DPS.SyncBucket("dummy", "WrongBucketDps"))
local wrongBucket = (correctBucket % 8) + 1
clock = wrongBucketSent + 55
local wrongBucketAccepted = SendDpsRecord("WrongBucketDps", "wrong-bucket",
    wrongBucketRecord, {requester=LOCAL_TRANSPORT,requestId=wrongBucketId,
        bucket=wrongBucket})
Check(wrongBucketAccepted == false,
    "direct contextual WLD2 with wrong bucket remained fail-closed")
local wrongBucketOutcome = RequestOutcome()
local wrongBucketStored = NexusDB and NexusDB.dpsCapture
    and NexusDB.dpsCapture.characterBest
    and NexusDB.dpsCapture.characterBest.dummy
    and NexusDB.dpsCapture.characterBest.dummy.wrongbucketdps ~= nil
clock = wrongBucketSent + 61
Check(wrongBucketOutcome.updated == 0 and wrongBucketOutcome.new == 0
        and wrongBucketOutcome.duplicates == 0
        and wrongBucketOutcome.rejected == 1
        and wrongBucketOutcome.unrelated == 0
        and wrongBucketOutcome.lastReason == "request_auth"
        and not wrongBucketOutcome.useful and not wrongBucketStored,
    "wrong-bucket-WLD2: rejected direct record was stored or misattributed")
end

------------------------------------------------------------------------
-- L. requestRelated is exact positive matching work, not a synonym for global
-- outbound, recovery, responder reconciliation, delete, Share, or ambient
-- inflight activity. The public surface remains fixed, flat, and sanitized.
------------------------------------------------------------------------

do
local exactWorkId, exactWorkSent = BeginManual()
clock = exactWorkSent + 10
local exactEncoded = EncodeBuild("exact-partial", "Bob", 850)
local exactChunks = Chunks(exactEncoded, 2)
Control(Sync.HandleIncoming(BuildWire("Bob", "exact-partial", 850,
    1, 2, exactChunks[1], {requester=LOCAL_TRANSPORT,
        requestId=exactWorkId}),
    "Bob-Ebonhold") == false, "matching partial build remains inflight")
Control(Session.QueueLegacyRecovery("unrelated-recovery") == true,
    "unrelated recovery work queued")
local shareBuild = assert(PutBuild("unrelated-share", "Alice", 851, false))
Control(Sync.BroadcastBuildSummary(shareBuild, {retryOnFull=true}) == true,
    "unrelated Share summary admitted")
Control(Sync.BroadcastDelete({id="unrelated-delete",title="Unrelated delete",
    author="Alice",ownerKey="alice@ebonhold",ownerVerified=true,isMine=true})
    == true, "unrelated delete admitted")
Control(Sync.HandleIncoming(
    "WLRQ|ResponderPeer|0|0|c1-unrelated-response|1.20.0-beta.1",
    "ResponderPeer-Ebonhold") == true,
    "unrelated responder reconciliation scheduled")
local exactWork = Sync.WorkState()
local _, _, _, exactLeaderboardWork = Sync.GetLeaderboardSyncStatus()
Check(exactWork.requestRelated == 1
        and exactLeaderboardWork.requestRelated == 1
        and exactWork.buildInflight == 1
        and exactWork.recovery >= 1 and exactWork.pendingResponses >= 1
        and exactWork.outbound >= 2
        and FlatSanitized(exactWork) and FlatSanitized(exactLeaderboardWork),
    "exact-requestRelated: unrelated global owners contaminated matching work")
end

------------------------------------------------------------------------
-- M. Once a syntactically valid matching c1 owner is known, later bounded
-- envelope/schema rejection is retained exactly once by the request ledger.
-- Malformed request identity itself remains unattributed.
------------------------------------------------------------------------

do
local function MatchingReject(message, sender, label)
    local requestId = BeginManual()
    local wire = message(requestId)
    Control(Sync.HandleIncoming(wire, sender) == false,
        label .. " remains rejected")
    local outcome = RequestOutcome()
    Check(outcome.rejected == 1 and outcome.unrelated == 0
            and outcome.lastReason == "schema" and not outcome.useful,
        label .. ": matching rejection was not retained exactly once")
end

MatchingReject(function(requestId)
    return table.concat({"WLRB","Bob","bad-geometry", "1", "0/1", "e30=",
        LOCAL_TRANSPORT,requestId}, "|")
end, "Bob", "malformed-WLRB")

MatchingReject(function(requestId)
    return table.concat({"WLD2","DpsOwner","bad-geometry", "2/1", "e30=",
        LOCAL_TRANSPORT,requestId,"1"}, "|")
end, "DpsOwner", "malformed-WLD2")

MatchingReject(function(requestId)
    return table.concat({"WLBI","Bob","!!!!", LOCAL_TRANSPORT,requestId}, "|")
end, "Bob", "malformed-WLBI")

MatchingReject(function(requestId)
    return table.concat({"WLRD","Bob","bad id","1","Bob",
        LOCAL_TRANSPORT,requestId}, "|")
end, "Bob", "malformed-WLRD")

MatchingReject(function(requestId)
    return table.concat({"WLLC","Bob",LOCAL_TRANSPORT,
        "bad id",requestId}, "|")
end, "Bob", "malformed-WLLC")

MatchingReject(function(requestId)
    return table.concat({"WLRC","Bob",LOCAL_TRANSPORT,requestId,
        string.rep("a", 193),"0"}, "|")
end, "Bob", "malformed-WLRC")

MatchingReject(function(requestId)
    return table.concat({"WLBC","Bob",LOCAL_TRANSPORT,
        requestId,"X","1","0"}, "|")
end, "Bob", "malformed-WLBC")

local staleRejectId = BeginManual()
Control(Sync.HandleIncoming(table.concat({"WLRB","Bob","stale-reject","1",
    "0/1","e30=",LOCAL_TRANSPORT,"c1-stale-reject"}, "|"),
    "Bob") == false,
    "stale malformed contextual response remains rejected")
local staleRejectOutcome = RequestOutcome()
Check(staleRejectOutcome.rejected == 0
        and staleRejectOutcome.unrelated == 1
        and staleRejectOutcome.lastReason == "request_auth",
    "stale malformed context was not bounded as unrelated")

Control(Sync.HandleIncoming(table.concat({"WLRB","Bob","foreign-reject","1",
    "0/1","e30=","Mallory-Ebonhold",staleRejectId}, "|"),
    "Bob") == false,
    "foreign malformed contextual response remains rejected")
local foreignRejectOutcome = RequestOutcome()
Check(foreignRejectOutcome.rejected == 0
        and foreignRejectOutcome.unrelated == 2
        and foreignRejectOutcome.lastReason == "request_auth",
    "foreign malformed context was not bounded as unrelated")

local legacyBefore = RequestOutcome()
Control(Sync.HandleIncoming(
    "WLRB|Bob|legacy-reject|1|0/1|e30=", "Bob") == false,
    "legacy malformed response remains rejected")
local legacyAfter = RequestOutcome()
Check(legacyAfter.rejected == legacyBefore.rejected
        and legacyAfter.unrelated == legacyBefore.unrelated,
    "requestless malformed response contaminated the active request")

local capacityId = BeginManual()
for index = 1, 4 do
    Control(Sync.HandleIncoming(table.concat({"WLRB","Bob",
        "capacity-" .. index,"1","1/2","e30="}, "|"), "Bob") == false,
        "per-sender inflight capacity fixture admitted partial " .. index)
end
Control(Sync.HandleIncoming(table.concat({"WLRB","Bob","capacity-overflow",
    "1","1/2","e30=",LOCAL_TRANSPORT,capacityId}, "|"),
    "Bob") == false,
    "matching capacity overflow remains rejected")
local capacityOutcome = RequestOutcome()
Check(capacityOutcome.rejected == 1 and capacityOutcome.unrelated == 0
        and capacityOutcome.lastReason == "queue",
    "matching inflight capacity refusal was not attributed once")

local dpsCapacityId = BeginManual()
for index = 1, 4 do
    Control(Sync.HandleIncoming(table.concat({"WLD2","DpsOwner",
        "dps-capacity-" .. index,"1/2","e30="}, "|"), "DpsOwner") == false,
        "DPS per-sender inflight capacity fixture admitted partial " .. index)
end
Control(Sync.HandleIncoming(table.concat({"WLD2","DpsOwner",
    "dps-capacity-overflow","1/2","e30=",LOCAL_TRANSPORT,
    dpsCapacityId,"1"}, "|"),
    "DpsOwner") == false, "matching DPS capacity overflow remains rejected")
local dpsCapacityOutcome = RequestOutcome()
Check(dpsCapacityOutcome.rejected == 1
        and dpsCapacityOutcome.unrelated == 0
        and dpsCapacityOutcome.lastReason == "queue",
    "matching DPS inflight capacity refusal was not attributed once")

local conflictId = BeginManual()
local conflictEncoded = EncodeBuild("conflict-reason", "Bob", 990)
local conflictChunks = Chunks(conflictEncoded, 2)
local conflictContext = {requester=LOCAL_TRANSPORT,requestId=conflictId}
Control(Sync.HandleIncoming(BuildWire("Bob", "conflict-reason", 990,
    1, 2, conflictChunks[1], conflictContext), "Bob") == false,
    "conflicting transfer starts with one valid chunk")
Control(Sync.HandleIncoming(BuildWire("Bob", "conflict-reason", 990,
    1, 2, conflictChunks[1] .. "x", conflictContext), "Bob") == false,
    "conflicting duplicate remains rejected")
local conflictOutcome = RequestOutcome()
Check(conflictOutcome.rejected == 1
        and conflictOutcome.lastReason == "integrity",
    "chunk-conflict: bounded rejection reason was suppressed")

local dpsConflictId = BeginManual()
local dpsConflictContext = {requester=LOCAL_TRANSPORT,
    requestId=dpsConflictId,bucket=1}
Control(Sync.HandleIncoming(DpsChunkWire("DpsOwner", "dps-conflict", 1, 2,
    "e30=", dpsConflictContext), "DpsOwner") == false,
    "conflicting DPS transfer starts with one valid chunk")
Control(Sync.HandleIncoming(DpsChunkWire("DpsOwner", "dps-conflict", 1, 2,
    "e30=x", dpsConflictContext), "DpsOwner") == false,
    "conflicting DPS duplicate remains rejected")
local dpsConflictOutcome = RequestOutcome()
Check(dpsConflictOutcome.rejected == 1
        and dpsConflictOutcome.lastReason == "integrity",
    "DPS chunk-conflict: bounded rejection reason was suppressed")
end

------------------------------------------------------------------------
-- N. Overlapping stale and current partial transfers never mix contexts or
-- let the stale identity poison the later exact request. The current WLRB and
-- direct WLD2 complete once with no synthetic conflict rejection.
------------------------------------------------------------------------

do
local overlapBuildId, overlapBuildSent = BeginManual()
local overlapEncoded = EncodeBuild("overlap-build", "Bob", 901)
local overlapChunks = Chunks(overlapEncoded, 2)
local oldBuildContext = {requester=LOCAL_TRANSPORT,
    requestId="c1-overlap-old"}
local newBuildContext = {requester=LOCAL_TRANSPORT,
    requestId=overlapBuildId}
clock = overlapBuildSent + 10
Sync.HandleIncoming(BuildWire("Bob", "overlap-build", 901, 1, 2,
    overlapChunks[1], oldBuildContext), "Bob-Ebonhold")
Sync.HandleIncoming(BuildWire("Bob", "overlap-build", 901, 1, 2,
    overlapChunks[1], newBuildContext), "Bob-Ebonhold")
local overlapBuildAccepted = Sync.HandleIncoming(BuildWire("Bob",
    "overlap-build", 901, 2, 2, overlapChunks[2], newBuildContext),
    "Bob-Ebonhold")
local overlapBuildOutcome = RequestOutcome()
Check(overlapBuildAccepted and Stored("overlap-build")
        and overlapBuildOutcome.new == 1
        and overlapBuildOutcome.rejected == 0,
    "overlapping-WLRB: stale partial poisoned the later matching transfer")

local overlapDpsId, overlapDpsSent = BeginManual()
local overlapDpsRecord = CompactDps("OverlapDps", 950000, 902)
local overlapDpsBucket = assert(DPS.SyncBucket("dummy", "OverlapDps"))
local overlapDpsData = Codec.Base64Encode(Codec.JSONEncode(overlapDpsRecord))
local overlapDpsTotal = math.max(2, math.ceil(#overlapDpsData / 96))
local overlapDpsChunks = Chunks(overlapDpsData, overlapDpsTotal)
local oldDpsContext = {requester=LOCAL_TRANSPORT,requestId="c1-dps-old",
    bucket=overlapDpsBucket}
local newDpsContext = {requester=LOCAL_TRANSPORT,requestId=overlapDpsId,
    bucket=overlapDpsBucket}
clock = overlapDpsSent + 10
Sync.HandleIncoming(DpsChunkWire("OverlapDps", "overlap-dps", 1,
    overlapDpsTotal,
    overlapDpsChunks[1], oldDpsContext), "OverlapDps-Ebonhold")
Sync.HandleIncoming(DpsChunkWire("OverlapDps", "overlap-dps", 1,
    overlapDpsTotal,
    overlapDpsChunks[1], newDpsContext), "OverlapDps-Ebonhold")
local overlapDpsAccepted = false
for index = 2, overlapDpsTotal do
    overlapDpsAccepted = Sync.HandleIncoming(DpsChunkWire("OverlapDps",
        "overlap-dps", index, overlapDpsTotal, overlapDpsChunks[index],
        newDpsContext), "OverlapDps-Ebonhold")
end
local overlapDpsOutcome = RequestOutcome()
Check(overlapDpsAccepted and overlapDpsOutcome.updated == 1
        and overlapDpsOutcome.rejected == 0,
    "overlapping-WLD2: stale partial poisoned the later matching transfer")
end

if #failures > 0 then
    for index, label in ipairs(failures) do
        print(string.format("EXPECTED RED %02d: %s", index, label))
    end
    error(string.format(
        "Stage 36.3 request correlation expected red: %d/%d desired checks failed; controls=%d green",
        #failures, checks, controls))
end

print(string.format(
    "sync request correlation: desired=%d controls=%d legacy_ambient=yes sanitized=yes -- OK",
    checks, controls))
