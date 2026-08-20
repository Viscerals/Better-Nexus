-- Stage 26.3 expected red: every DPS path must share the same category
-- duration contract and report bounded, sanitized rejection reasons.
local H = dofile("tests/harness.lua")

local clock, actor = 1000, "Viewer"
GetTime = function() return clock end
time = function() return 50000 end
UnitName = function(unit)
    if unit == "target" then return "Target" end
    return actor
end
UnitLevel = function() return 80 end
UnitClass = function() return "Mage", "MAGE" end

dofile("core/Revisions.lua")
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

NexusDB = {communityBuilds={},syncTombstones={},dpsCapture={}}
local Sync, DPS = Nexus.Sync, Nexus.DpsCapture
DPS.Init({}, Sync)
Sync.Init(Nexus.Codec, {})

local failures = {}
local function Check(ok, message)
    if not ok then failures[#failures + 1] = message end
end

local expected = {
    dummy={[19]=false,[20]=false,[29]=false,[30]=true},
    lk={[19]=false,[20]=true,[29]=true,[30]=true},
}
Check(type(DPS.MinimumDuration) == "function"
        and DPS.MinimumDuration("dummy") == 30
        and DPS.MinimumDuration("lk") == 20,
    "authoritative category duration API is missing or inconsistent")

local echoes = {{spellId=410001,stacks=1}}
local fingerprint = DPS.GetEchoKey(echoes)
local hash = DPS.GetEchoHash(echoes)
local function Record(category, duration, player, dps, stamp)
    return {
        v=7,f=fingerprint,h=hash,e=echoes,c=category,
        d=dps or 250000,u=duration,t=stamp or (40000 + duration),
        p=player,l=80,k="MAGE",
    }
end

for _, category in ipairs({"dummy", "lk"}) do
    for _, duration in ipairs({19,20,29,30}) do
        local player = "Direct" .. category .. tostring(duration)
        local accepted = DPS.ReceiveRecord(
            Record(category, duration, player), player)
        Check(accepted == expected[category][duration], string.format(
            "direct inbound %s %ds expected %s got %s", category, duration,
            tostring(expected[category][duration]), tostring(accepted)))

        local relayPlayer = "Relayed" .. category .. tostring(duration)
        local relayed = DPS.ReceiveRelayedRecord(
            Record(category, duration, relayPlayer), "RelayPeer")
        Check(relayed == expected[category][duration], string.format(
            "relayed inbound %s %ds expected %s got %s", category, duration,
            tostring(expected[category][duration]), tostring(relayed)))
    end
end

-- Outbound owner and response-only relay preparation must apply the same table.
for _, category in ipairs({"dummy", "lk"}) do
    for _, duration in ipairs({19,20,29,30}) do
        actor = "Outbound" .. category .. tostring(duration)
        local direct = Record(category, duration, actor)
        direct.protocolVersion, direct.fingerprint, direct.loadoutHash =
            direct.v, direct.f, direct.h
        direct.echoes, direct.category, direct.dps = direct.e, direct.c, direct.d
        direct.duration, direct.ts, direct.player = direct.u, direct.t, direct.p
        direct.level, direct.class = direct.l, direct.k
        local admitted = Sync.BroadcastDpsRecord(direct)
        Check(admitted == expected[category][duration], string.format(
            "direct outbound %s %ds expected %s got %s", category, duration,
            tostring(expected[category][duration]), tostring(admitted)))

        actor = "RelayPeer"
        local relayPlayer = "Offer" .. category .. tostring(duration)
        local relay = Record(category, duration, relayPlayer)
        relay.protocolVersion, relay.fingerprint, relay.loadoutHash =
            relay.v, relay.f, relay.h
        relay.echoes, relay.category, relay.dps = relay.e, relay.c, relay.d
        relay.duration, relay.ts, relay.player = relay.u, relay.t, relay.p
        relay.level, relay.class, relay._originVerified = relay.l, relay.k, true
        local bucket = DPS.SyncBucket(category, relayPlayer)
        local offered = Sync.BroadcastDpsRecord(relay, nil, true, {
            requester="Requester",requestId="duration-contract",bucket=bucket,
        })
        Check(offered == expected[category][duration], string.format(
            "relayed outbound %s %ds expected %s got %s", category, duration,
            tostring(expected[category][duration]), tostring(offered)))
    end
end

-- Local capture already distinguishes LK from Dummy; retain exact boundaries.
local captureAdapter = {
    Owned=function() return {bySpell={[410001]=1}} end,
    Slots=function() return nil end,
    LockedOwned=function() return {bySpell={}} end,
}
local captureSync = {
    BroadcastDpsRecord=function() return true end,
    BroadcastBuild=function() return true end,
}
DPS.Init(captureAdapter, captureSync)
DETAILS_ATTRIBUTE_DAMAGE = 1
local captureDps = 250000
Details = {GetCurrentCombat=function()
    return {GetActor=function()
        return {total=captureDps * 30,Tempo=function() return 30 end}
    end}
end}
UnitExists = function(unit) return unit == "target" end
for _, category in ipairs({"dummy", "lk"}) do
    for _, duration in ipairs({19,20,29,30}) do
        actor = "Local" .. category .. tostring(duration)
        captureDps = 250000 + duration * 1000
        UnitGUID = function()
            local npc = category == "dummy" and 36476 or 36597
            return "Creature-0-1-0-1-" .. tostring(npc) .. "-ABC"
        end
        DPS.OnCombatStart()
        clock = clock + duration
        DPS.OnCombatEnd()
        local captured = DPS.GetCharacterBest(category, actor) ~= nil
        Check(captured == expected[category][duration], string.format(
            "local capture %s %ds expected %s got %s", category, duration,
            tostring(expected[category][duration]), tostring(captured)))
    end
end

-- Stored legacy rows below the contract may remain in SavedVariables, but they
-- must not qualify, publish, hash, or relay as current evidence.
local function StoredRow(category, duration, player, fp)
    return {
        fingerprint=fp,loadoutHash=hash,echoes=echoes,category=category,
        dps=250000,duration=duration,ts=30000,player=player,
        level=80,class="MAGE",ownerVerified=true,
    }
end
NexusDB = {communityBuilds={},syncTombstones={},dpsCapture={
    characterBest={
        dummy={
            valid=StoredRow("dummy",30,"ValidDummy","valid-pair"),
            shortdummy=StoredRow("dummy",29,"ShortDummy","short-dummy"),
            shortlk=StoredRow("dummy",30,"ShortLkDummy","short-lk"),
        },
        lk={
            valid=StoredRow("lk",20,"ValidLk","valid-pair"),
            shortdummy=StoredRow("lk",30,"ShortDummyLk","short-dummy"),
            shortlk=StoredRow("lk",19,"ShortLk","short-lk"),
        },
    },personalBest={},buildBest={},
}}
local eligibility = DPS.GetCommunityEligibility()
Check(eligibility["valid-pair"] ~= nil
        and eligibility["short-dummy"] == nil
        and eligibility["short-lk"] == nil,
    "Community qualification published below-category duration evidence")
local dummyBoard, lkBoard = DPS.GetDpsBoard("dummy"), DPS.GetDpsBoard("lk")
local function HasPlayer(rows, player)
    for _, row in ipairs(rows) do
        if row.player == player then return true end
    end
    return false
end
Check(not HasPlayer(dummyBoard,"ShortDummy")
        and not HasPlayer(lkBoard,"ShortLk"),
    "Leaderboard published below-category duration evidence")

local digestWithShortRows = DPS.GetSyncHashUncached()
local shortDummy = NexusDB.dpsCapture.characterBest.dummy.shortdummy
local shortLk = NexusDB.dpsCapture.characterBest.lk.shortlk
NexusDB.dpsCapture.characterBest.dummy.shortdummy = nil
NexusDB.dpsCapture.characterBest.lk.shortlk = nil
local digestWithoutShortRows = DPS.GetSyncHashUncached()
Check(digestWithShortRows == digestWithoutShortRows,
    "below-category duration evidence changed the DPS Sync digest")
NexusDB.dpsCapture.characterBest.dummy.shortdummy = shortDummy
NexusDB.dpsCapture.characterBest.lk.shortlk = shortLk

local offeredDurations = {}
captureSync.BroadcastDpsRecord = function(record)
    offeredDurations[#offeredDurations + 1] = {
        category=record.category,duration=record.duration,
    }
    return true
end
local offered, relayComplete = DPS.BroadcastAllBuildBests(nil,nil,{},100)
Check(relayComplete == true and offered == 4
        and #offeredDurations == 4,
    "duration-filtered DPS relay did not offer exactly four valid rows")
for _, row in ipairs(offeredDurations) do
    Check(DPS.IsDurationEligible(row.category,row.duration),
        "DPS relay offered below-category duration evidence")
end

-- Every rejection family remains a fixed scalar counter with no payload data.
local function RejectProbe(record, sender, relayed)
    return relayed and DPS.ReceiveRelayedRecord(record, sender)
        or DPS.ReceiveRecord(record, sender)
end
RejectProbe(Record("dummy",29,"ShortDuration"), "ShortDuration")
RejectProbe(Record("bad",30,"BadCategory"), "BadCategory")
RejectProbe({v=7,e={},c="dummy",d=250000,u=30,t=40000,
    p="BadSchema",l=80,k="MAGE"}, "BadSchema")
RejectProbe(Record("dummy",30,"OwnerMismatch"), "OtherSender")
RejectProbe(Record("dummy",30,"SameRelay"), "SameRelay", true)
RejectProbe(Record("dummy",30,"BadIntegrity",500), "BadIntegrity")
local winner = Record("dummy",30,"Duplicate",300000,41000)
RejectProbe(winner,"Duplicate")
RejectProbe(winner,"Duplicate")
RejectProbe(Record("dummy",30,"Duplicate",200000,40000),"Duplicate")
actor = "Viewer"
local outside = Record("dummy",30,"OutsideOwner")
outside.x = {n="Viewer",i="outside-request",b=DPS.SyncBucket(
    outside.c,outside.p)}
local outsideWire = Nexus.Codec.Base64Encode(Nexus.Codec.JSONEncode(outside))
local outsideChunks = math.ceil(#outsideWire / 120)
for index = 1, outsideChunks do
    Sync.HandleIncoming(string.format("WLD2|RelayPeer|outside|%d/%d|%s",
        index,outsideChunks,outsideWire:sub((index-1)*120+1,index*120)),
        "RelayPeer")
end
local reasons = type(DPS.RejectionStats) == "function"
    and DPS.RejectionStats() or {}
for _, reason in ipairs({"duration","owner_sender","relay_authorization",
    "schema","stale_record","duplicate_not_better","invalid_category",
    "integrity","outside_request"}) do
    Check(type(reasons[reason]) == "number" and reasons[reason] >= 1,
        "missing bounded DPS rejection reason: " .. reason)
end
for key, value in pairs(reasons) do
    Check(type(key) == "string" and type(value) == "number",
        "DPS rejection diagnostics retained non-scalar data")
end
local reasonCount = 0
for _ in pairs(reasons) do reasonCount = reasonCount + 1 end
Check(reasonCount == 9, "DPS rejection diagnostics changed fixed shape")
local originalDurationRejects = reasons.duration
reasons.duration = 999999
Check(DPS.RejectionStats().duration == originalDurationRejects,
    "DPS rejection diagnostics did not return a defensive copy")

if #failures > 0 then
    error("EXPECTED RED [Stage 26.3 DPS duration contract]:\n - "
        .. table.concat(failures, "\n - "))
end
print("Stage 26.3 DPS duration and rejection contract -- OK")
