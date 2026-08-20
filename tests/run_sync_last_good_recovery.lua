-- Checkpoint 38.5: a scalar summary may schedule recovery, but it cannot
-- replace the last complete public build. Only the still-current exact full
-- payload may advance represented data.
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

local Codec = assert(Nexus.Codec)
local Catalog = assert(Nexus.BuildCatalog)
local Sync = assert(Nexus.Sync)

local clock = 1000
GetTime = function() return clock end
time = function() return 50000 end
UnitName = function() return "Viewer" end
UnitLevel = function() return 80 end
UnitClass = function() return "Mage", "MAGE" end
GetNormalizedRealmName = function() return "Ebonhold" end

local function Encode(value)
    return Codec.Base64Encode(Codec.JSONEncode(value))
end

local function HashText(text)
    local hash = 5381
    for index = 1, #text do
        hash = ((hash * 33) + text:byte(index)) % 2147483648
    end
    return string.format("%x", hash)
end

local function Fingerprint(echoes)
    local counts, ids = {}, {}
    for _, echo in ipairs(echoes) do
        local id = tonumber(echo.spellId or echo.id)
        local count = tonumber(echo.count or echo.stacks or echo.stack) or 1
        counts[id] = (counts[id] or 0) + count
    end
    for id in pairs(counts) do ids[#ids + 1] = id end
    table.sort(ids)
    local out = {}
    for _, id in ipairs(ids) do
        out[#out + 1] = tostring(id) .. "x" .. tostring(counts[id])
    end
    return table.concat(out, ",")
end

local function Summary(id, stamp, echoes, overrides)
    local payload = {
        id=id,t="Revision " .. tostring(stamp),a="Owner",
        o="owner@ebonhold",c="MAGE",m=stamp,
        h=HashText(Fingerprint(echoes)),n=1,
    }
    for key, value in pairs(overrides or {}) do payload[key] = value end
    return payload
end

local function Full(id, stamp, echoes, overrides)
    local payload = {
        id=id,t="Revision " .. tostring(stamp),a="Owner",
        o="owner@ebonhold",c="MAGE",m=stamp,d="complete",e=echoes,
    }
    for key, value in pairs(overrides or {}) do payload[key] = value end
    return payload
end

local function DeliverSummary(sender, payload)
    local transportSender = sender .. "-Ebonhold"
    return Sync.HandleIncoming("WLBI|" .. transportSender .. "|"
        .. Encode(payload), transportSender)
end

local function DeliverBuild(sender, payload, onlyFirst)
    local transportSender = sender .. "-Ebonhold"
    local encoded = Encode(payload)
    local chunkSize = 96
    local total = math.ceil(#encoded / chunkSize)
    local result = false
    for index = 1, total do
        local wire = string.format("WLRB|%s|%s|%s|%d/%d|%s", transportSender,
            tostring(payload.id),tostring(payload.m),index,total,
            encoded:sub((index - 1) * chunkSize + 1,index * chunkSize))
        assert(#wire <= 255, "fixture exceeded wire limit")
        result = Sync.HandleIncoming(wire, transportSender) or result
        if onlyFirst then break end
    end
    return result
end

local function FindSession()
    for index = 1, 80 do
        local _, value = debug.getupvalue(Sync.GetLeaderboardSyncStatus, index)
        if value == nil then break end
        if type(value) == "table"
            and type(value.QueueLegacyRecovery) == "function"
            and type(value.StatusSnapshot) == "function" then
            return value
        end
    end
end

local Session = assert(FindSession(), "real SyncSession owner unavailable")
local function Pending(id)
    assert(type(Session.PendingReplacement) == "function",
        "expected-red: SyncSession has no pending replacement owner")
    return Session.PendingReplacement(id)
end

local echoesA = {{spellId=710001,quality=3,stacks=1}}
local echoesB = {{spellId=710002,quality=3,stacks=1}}
local echoesC = {{spellId=710003,quality=3,stacks=1}}

local function CompleteRecord(id, stamp, echoes)
    return {
        id=id,title="Revision " .. tostring(stamp),description="complete",
        author="Owner",ownerKey="owner@ebonhold",class="MAGE",
        postedAt=1,lastModified=stamp,echoes=echoes,ownerVerified=true,
        fingerprint=Fingerprint(echoes),fingerprintHash=HashText(Fingerprint(echoes)),
        loadoutAvailable=true,
    }
end

local function Reset(database)
    clock = clock + 400
    NexusDB = database or {communityBuilds={},syncTombstones={}}
    H.sentChatMessages = {}
    H.joinedChannels = {}
    Sync.Init(Codec, {})
    assert(Sync.IsConnected(), "fixture did not join Sync channel")
    return NexusDB
end

local function AssertPublic(id, stamp, echoes, label)
    local row = Catalog.Get(id)
    assert(row and row.lastModified == stamp
            and row.echoes and row.echoes[1]
            and row.echoes[1].spellId == echoes[1].spellId
            and Catalog.GetSummary(id).ordinaryComplete == true,
        label)
end

-- A remains represented while B and then C recover. The scalar short hash is
-- never sufficient to reuse A's exact evidence.
local db = Reset()
assert(Catalog.Put(CompleteRecord("last-good", 10, echoesA)))
local exactA = Catalog.Get("last-good").evidenceKey
local epochA, revisionA = Catalog.RecordRevision("last-good")
local collisionB = Summary("last-good", 20, echoesB, {
    h=HashText(Fingerprint(echoesA)),
})
assert(DeliverSummary("Owner", collisionB))
AssertPublic("last-good", 10, echoesA,
    "B summary replaced or weakened complete A")
assert(Pending("last-good").lastModified == 20,
    "B summary did not enter bounded pending ownership")
assert(db.pendingReplacements == nil and db.syncPendingReplacements == nil,
    "pending recovery created a second SavedVariables database")
local epochB, revisionB = Catalog.RecordRevision("last-good")
assert(epochB == epochA and revisionB == revisionA,
    "pending B advanced the represented revision")
assert(not DeliverBuild("Owner", Full("last-good", 20, echoesB)),
    "mismatched equal-short-hash payload was accepted")
AssertPublic("last-good", 10, echoesA,
    "mismatched B payload replaced complete A")

local intruder = Summary("last-good", 25, echoesB, {
    a="Intruder",o="intruder@ebonhold",
})
assert(not DeliverSummary("Intruder", intruder)
        and Pending("last-good").lastModified == 20,
    "owner conflict displaced protected B recovery identity")
AssertPublic("last-good", 10, echoesA,
    "owner conflict replaced complete A")

assert(DeliverSummary("Owner", Summary("last-good", 30, echoesC)))
assert(Pending("last-good").lastModified == 30,
    "C did not supersede pending B")
assert(DeliverBuild("Owner", Full("last-good", 20, echoesB)),
    "late superseded B was not handled safely")
AssertPublic("last-good", 10, echoesA,
    "late B rolled complete A forward behind C")

-- Durable refusal retains both A and current pending C. Exactly one later
-- successful complete promotion advances the represented record.
local realPut = Catalog.Put
Catalog.Put = function() return false, "injected refusal" end
assert(not DeliverBuild("Owner", Full("last-good", 30, echoesC)),
    "durable refusal reported successful promotion")
Catalog.Put = realPut
AssertPublic("last-good", 10, echoesA,
    "durable refusal replaced complete A")
assert(Pending("last-good").lastModified == 30,
    "durable refusal cleared protected pending C")
assert(DeliverBuild("Owner", Full("last-good", 30, echoesC)),
    "current exact C did not promote")
AssertPublic("last-good", 30, echoesC,
    "current exact C was not published")
assert(type(Catalog.Get("last-good").evidenceKey) == "string"
        and Catalog.Get("last-good").evidenceKey ~= exactA,
    "C promotion reused A's exact content-addressed evidence")
assert(Pending("last-good") == nil,
    "successful C promotion retained pending metadata")
local epochC, revisionC = Catalog.RecordRevision("last-good")
assert(epochC == epochA and revisionC == revisionA + 1,
    "C promotion did not advance exactly one represented record revision")

-- A partial replacement transfer expires without touching its independent
-- last-good row or pending identity.
assert(Catalog.Put(CompleteRecord("expiry", 10, echoesA)))
assert(DeliverSummary("Owner", Summary("expiry", 20, echoesB)))
DeliverBuild("Owner", Full("expiry", 20, echoesB), true)
clock = clock + 301
Sync.OnUpdate(301)
AssertPublic("expiry", 10, echoesA,
    "expired replacement transfer weakened complete A")
assert(Pending("expiry").lastModified == 20,
    "transfer expiry discarded the still-winning recovery identity")

-- A restart loses only session metadata; the durable complete A-equivalent
-- remains public and a repeated summary can safely resume recovery.
local restartDb = Reset()
assert(Catalog.Put(CompleteRecord("restart", 10, echoesA)))
assert(DeliverSummary("Owner", Summary("restart", 20, echoesB)))
AssertPublic("restart", 10, echoesA, "restart setup replaced A")
Sync.Init(Codec, {})
AssertPublic("restart", 10, echoesA, "restart lost durable A")
assert(Pending("restart") == nil, "restart persisted session replacement state")
assert(DeliverSummary("Owner", Summary("restart", 20, echoesB)))
assert(DeliverBuild("Owner", Full("restart", 20, echoesB)))
AssertPublic("restart", 20, echoesB, "restart recovery did not resume")

-- A current scalar summary explicitly carries no link hash when the newer
-- build removed its link. The matching full payload must be able to promote
-- and must not resurrect A's stale local link.
Reset()
local linkedA = CompleteRecord("link-removed", 10, echoesA)
linkedA.link = "https://example.invalid/old"
linkedA.linkHash = HashText(linkedA.link)
assert(Catalog.Put(linkedA))
assert(DeliverSummary("Owner", Summary("link-removed", 20, echoesB)))
assert(DeliverBuild("Owner", Full("link-removed", 20, echoesB)),
    "no-link replacement could not promote over linked A")
AssertPublic("link-removed", 20, echoesB,
    "no-link replacement did not publish")
assert(Catalog.Get("link-removed").link == nil,
    "no-link replacement resurrected A's stale link")

-- New summaries remain internally retained but publicly incomplete until the
-- matching full payload arrives.
Reset()
assert(DeliverSummary("Owner", Summary("new-hidden", 40, echoesB)))
local hidden = Catalog.GetSummary("new-hidden")
assert(hidden and hidden.ordinaryComplete == false,
    "new scalar summary became publicly complete")
assert(Pending("new-hidden").lastModified == 40,
    "new scalar summary has no bounded replacement identity")
assert(DeliverBuild("Owner", Full("new-hidden", 40, echoesB)))
AssertPublic("new-hidden", 40, echoesB,
    "new build did not publish after exact recovery")

-- An authorized tombstone wins durably and cancels pending replacement work.
Reset()
assert(Catalog.Put(CompleteRecord("deleted", 10, echoesA)))
assert(DeliverSummary("Owner", Summary("deleted", 20, echoesB)))
assert(Sync.HandleIncoming(
    "WLRD|Owner-Ebonhold|deleted|25|Owner", "Owner-Ebonhold"))
assert(Catalog.Get("deleted") == nil and Pending("deleted") == nil,
    "authorized tombstone did not defeat pending replacement")
assert(DeliverBuild("Owner", Full("deleted", 20, echoesB)),
    "late tombstoned payload was not handled safely")
assert(Catalog.Get("deleted") == nil,
    "late payload resurrected an authorized tombstone")

-- Future catalog refusal cannot create either represented or pending state.
local future = {
    buildCatalog={schemaVersion=999},
    communityBuilds={opaque={future=true}},
    futureRoot={keep="exact"},
}
local beforeFuture = Codec.JSONEncode(future)
Reset(future)
assert(not DeliverSummary("Owner", Summary("future", 50, echoesC)))
assert(Catalog.Get("future") == nil and Pending("future") == nil
        and Codec.JSONEncode(future) == beforeFuture,
    "future-schema refusal mutated public or pending protected state")

-- Replacement ownership is capped independently of represented storage.
Reset()
local replacementCap = assert(Sync.WorkState().maxRecoveryQueue)
for index = 1, replacementCap do
    local id = "bounded-" .. tostring(index)
    assert(Catalog.Put(CompleteRecord(id, 1, echoesA)))
    assert(DeliverSummary("Owner", Summary(id, 2, echoesB)))
end
assert(Sync.WorkState().pendingReplacements == replacementCap,
    "pending replacement owner exceeded or underfilled its fixed cap: "
        .. tostring(Sync.WorkState().pendingReplacements) .. "/"
        .. tostring(replacementCap))
assert(Catalog.Put(CompleteRecord("bounded-overflow", 1, echoesA)))
assert(not DeliverSummary("Owner",
        Summary("bounded-overflow", 2, echoesB))
        and Sync.WorkState().pendingReplacements == replacementCap,
    "newest replacement was admitted beyond the fixed cap")
AssertPublic("bounded-overflow", 1, echoesA,
    "replacement overflow weakened its last-good row")

print("last-good recovery: A/B/C, collision, expiry, refusal, restart, hidden, tombstone, future -- OK")
