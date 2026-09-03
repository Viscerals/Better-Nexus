-- Package B / issue #22: the 79/6/85 semantic envelope at every protocol-7
-- trust boundary, protocol-7 typed-identity refusal, and remote tombstone
-- behaviour through the real Sync stack in one runtime (PRO, SYN, MIX local).
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
local S = dofile("tests/catalog_authority_support.lua")
local Case, Check = S.Case, S.Check

local Codec, Sync = Nexus.Codec, Nexus.Sync
local clock = 1000
GetTime = function() return clock end
local now = 2000000000
time = function() return now end

local function Catalog() return Nexus.BuildCatalog end

local function Pump(seconds)
    for _ = 1, math.ceil((seconds or 10) / 0.2) do
        clock = clock + 0.2
        Sync.OnUpdate(0.2)
    end
end

-- Only build, summary, delete, and loadout-request envelopes are mutation
-- traffic; presence and request handshakes are ignored by every assertion.
local function Drain()
    Pump(14)
    local out = {}
    for _, message in ipairs(H.sentChatMessages) do
        local code = tostring(message.text or ""):match("^(%u+)|")
        if code == "WLRB" or code == "WLBI" or code == "WLRD" or code == "WLLQ" then
            out[#out + 1] = message
        end
    end
    H.sentChatMessages = {}
    return out
end

local function Protocol()
    return Nexus.SyncInternals.Protocol.New({
        limits={maxTransferIdBytes=160, maxHashBytes=192, maxVersionBytes=32,
            maxBuildIdBytes=96, maxBuildEchoes=256, maxRequestIdBytes=96,
            bucketCount=8, maxWireFields=8},
        parseVersion=function(value) return {normalized=value} end,
        ownerKeyMatchesAuthor=Nexus.Identity.OwnerKeyMatchesAuthor,
        isSafeTree=function(value, depth, nodes)
            return Codec.IsSafeTree(value, depth, nodes)
        end,
    })
end

local function CompactRows(ordinary, locked, perRow)
    local rows = {}
    for _, row in ipairs(S.Echoes(ordinary, locked, {perRow=perRow})) do
        if row.locked then
            rows[#rows + 1] = {row.spellId, row.quality, row.stacks, 1}
        else
            rows[#rows + 1] = {row.spellId, row.quality, row.stacks}
        end
    end
    return rows
end

local function Payload(id, ordinary, locked, extra)
    local payload = {id=id, t="Wire " .. tostring(id), a="Peer", o="peer@ebonhold",
        c="MAGE", m=20, e=CompactRows(ordinary, locked)}
    for key, value in pairs(extra or {}) do payload[key] = value end
    return payload
end

local function BuildWire(payload, sender)
    sender = sender or "Peer"
    local data = Codec.Base64Encode(Codec.JSONEncode(payload))
    local header = string.format("WLRB|%s|%s|%s|999/999|", sender, payload.id, payload.m)
    local budget = 255 - 8 - #header
    local messages = {}
    local total = math.max(1, math.ceil(#data / budget))
    for index = 1, total do
        local start = (index - 1) * budget + 1
        messages[#messages + 1] = string.format("WLRB|%s|%s|%s|%d/%d|%s", sender,
            payload.id, payload.m, index, total, data:sub(start, start + budget - 1))
    end
    return messages
end

local function Deliver(messages, sender)
    local accepted
    for _, text in ipairs(messages) do
        accepted = Sync.HandleIncoming(text, sender or "Peer-Ebonhold")
    end
    return accepted
end

local function ResetSync(db)
    NexusDB = db
    Nexus.LoadoutEvidence.Init(db)
    Sync.Init(Codec, {})
    H.sentChatMessages = {}
    return db
end

-- Protocol boundary ---------------------------------------------------------

Case("PRO-01", "one semantic envelope owner at every wire boundary", function()
    local limits = Nexus.LoadoutEvidence.SemanticLimits()
    Check(limits.ordinary == 79 and limits.locked == 6 and limits.total == 85,
        "LoadoutEvidence does not own the 79/6/85 envelope")
    local envelope = Nexus.LoadoutEvidence.SemanticEnvelope(S.Echoes(79, 6))
    Check(envelope.valid and envelope.ordinary == 79 and envelope.locked == 6
        and envelope.total == 85, "envelope owner miscounted 79/6/85")
    Check(Nexus.LoadoutEvidence.SemanticEnvelope(S.Echoes(80, 0)).valid == false
        and Nexus.LoadoutEvidence.SemanticEnvelope(S.Echoes(79, 7)).valid == false,
        "envelope owner admitted 80 or 7")
    local P = Protocol()
    Check(P.ValidateNetworkPayload(Payload("p79", 79, 0)), "79 ordinary wire refused")
    Check(P.ValidateNetworkPayload(Payload("p80", 80, 0)) == nil, "80 ordinary wire admitted")
    local roleBearing = P.ValidateNetworkPayload(Payload("p85", 79, 6))
    Check(roleBearing and #roleBearing.echoes == 85, "79/6 wire refused")
    local lockedCount = 0
    for _, echo in ipairs(roleBearing.echoes) do
        if echo.locked then lockedCount = lockedCount + 1 end
    end
    Check(lockedCount == 6, "slot-4 locked evidence was not preserved")
    Check(P.ValidateNetworkPayload(Payload("p86", 79, 7)) == nil, "79/7 wire admitted")
    Check(P.ValidateNetworkPayload(Payload("p7", 1, 7)) == nil, "7 locked wire admitted")
    local stacked = Payload("stack", 1, 0)
    stacked.e[1][3] = 86
    Check(P.ValidateNetworkPayload(stacked) == nil, "one oversized stack crossed the wire envelope")
    local parserCeiling = Payload("p257", 0, 0)
    parserCeiling.e = {}
    for index = 1, 257 do parserCeiling.e[index] = {100000 + index, 3, 1} end
    Check(P.ValidateNetworkPayload(parserCeiling) == nil, "257-entry parser ceiling relaxed")
    Check(P.CompactDecode(Payload("c80", 80, 0)) == nil, "CompactDecode admitted 80 ordinary")
    Check(P.CompactDecode(Payload("c79", 79, 0)), "CompactDecode refused 79 ordinary")
    local function Summary(n)
        return {id="s" .. tostring(n), t="Summary", a="Peer", o="peer@ebonhold",
            c="MAGE", m=20, h="deadbeef", n=n}
    end
    Check(P.ValidateNetworkSummary(Summary(85)), "n=85 summary refused")
    Check(P.ValidateNetworkSummary(Summary(86)) == nil, "n=86 summary admitted")
end)

-- Typed identity ------------------------------------------------------------

Case("MIX-06", "numeric 1 and string \"1\" never collide; numeric never reaches wire", function()
    local db = ResetSync(S.Database({}))
    local catalog = Catalog()
    Check(catalog.Put(S.LocalBuild(1, 2), {source="local"}), "numeric local ID refused")
    Check(catalog.Put(S.LocalBuild("1", 3), {source="local"}), "string local ID refused")
    Check(catalog.Get(1).echoCount == 2 and catalog.Get("1").echoCount == 3,
        "typed IDs collided in the catalog")
    Check(S.State(1).typedKey == "n:1" and S.State("1").typedKey == "s:1:1",
        "typed keys are not collision-free encodings")
    local ok, why = Sync.BroadcastBuild(catalog.Get(1))
    Check(ok == false and why == "PROTOCOL7_TYPED_ID_UNREPRESENTABLE",
        "numeric ID reached the wire path: " .. tostring(why))
    Check(select(2, Sync.BroadcastDelete(catalog.Get(1))) == "PROTOCOL7_TYPED_ID_UNREPRESENTABLE",
        "numeric delete reached the wire path")
    Check(select(2, Sync.BroadcastBuildSummary(catalog.Get(1)))
        == "PROTOCOL7_TYPED_ID_UNREPRESENTABLE", "numeric summary reached the wire path")
    Check(select(2, Sync.RequestLoadout(1)) == "PROTOCOL7_TYPED_ID_UNREPRESENTABLE",
        "numeric loadout request reached the queue")
    local sent = Drain()
    Check(#sent == 0, "numeric ID produced wire bytes")
    Check(Sync.BroadcastBuild(catalog.Get("1")), "string ID refused")
    sent = Drain()
    local envelope
    for _, message in ipairs(sent) do
        -- wire pipes are escaped as `||` on the chat channel
        if message.text:find("WLRB||Boganic||1||", 1, true) then envelope = message.text end
    end
    Check(envelope ~= nil, "string ID did not emit the exact protocol-7 envelope")
    Check(db.communityBuilds[1] ~= nil and db.communityBuilds["1"] ~= nil,
        "typed slots were merged in storage")
end)

Case("MIX-07", "only exact 1..96-byte UTF-8 identifiers send", function()
    ResetSync(S.Database({}))
    local catalog = Catalog()
    local wide = string.rep("a", 97)
    local exact = string.rep("b", 96)
    local invalidUtf8 = "id\255x"
    local control = "id\1x"
    Check(catalog.Put(S.LocalBuild(wide, 1), {source="local"}), "97-byte local ID refused")
    Check(catalog.Put(S.LocalBuild(exact, 1), {source="local"}), "96-byte local ID refused")
    Check(catalog.Put(S.LocalBuild(invalidUtf8, 1), {source="local"}), "invalid UTF-8 local ID refused")
    Check(select(1, catalog.Put(S.LocalBuild(control, 1), {source="local"})) == false,
        "control-byte ID entered local storage")
    local okWide, whyWide = Sync.BroadcastBuild(catalog.Get(wide))
    Check(okWide == false and whyWide == "PROTOCOL7_ID_WIDTH_UNREPRESENTABLE",
        "97-byte ID reached the wire: " .. tostring(whyWide))
    local okUtf, whyUtf = Sync.BroadcastBuild(catalog.Get(invalidUtf8))
    Check(okUtf == false and whyUtf == "PROTOCOL7_ID_UNREPRESENTABLE",
        "invalid UTF-8 ID reached the wire: " .. tostring(whyUtf))
    Check(#Drain() == 0, "unrepresentable IDs produced wire bytes")
    Check(Sync.BroadcastBuild(catalog.Get(exact)), "96-byte ID refused")
    Check(#Drain() >= 1, "96-byte ID did not send")
end)

-- Inbound admission ---------------------------------------------------------

Case("SYN-01", "inbound 80 ordinary rejects before storage or relay", function()
    local db = ResetSync(S.Database({}))
    Sync.ClearLog()
    Deliver(BuildWire(Payload("syn01", 80, 0)))
    Check(db.communityBuilds.syn01 == nil and Catalog().Get("syn01") == nil,
        "80 ordinary reached durable storage")
    Check(#Drain() == 0, "rejected payload was relayed")
end)

Case("SYN-02", "inbound 79 plus 6 explicit locked converges once", function()
    local db = ResetSync(S.Database({}))
    Deliver(BuildWire(Payload("syn02", 79, 6)))
    local record = Catalog().Get("syn02")
    Check(record and #record.echoes == 85, "79/6 payload was not stored")
    Check(S.State("syn02").semantic.locked == 6, "locked role evidence was lost")
    Check(db.communityBuilds.syn02 ~= nil, "durable row missing")
    local generation = S.Root().generation
    Deliver(BuildWire(Payload("syn02", 79, 6)))
    Check(S.Root().generation == generation, "exact replay republished the root")
end)

Case("SYN-03", "remote tombstone: opaque block-all, replay, conflict, no resurrection", function()
    local db = ResetSync(S.Database({}))
    local catalog = Catalog()
    Check(catalog.Put(S.Build("syn03", 3, 0), {source="remote", sender="Peer-Ebonhold"}))
    local raw = db.communityBuilds.syn03
    local rawBytes = S.Encode(raw)
    Check(Sync.HandleIncoming("WLRD|Peer|syn03|30|Peer", "Peer-Ebonhold"),
        "owner delete was refused")
    Check(catalog.Get("syn03") == nil and catalog.Count() == 0,
        "deleted row remained publicly available")
    Check(db.communityBuilds.syn03 == raw and S.Encode(raw) == rawBytes,
        "remote delete removed or rewrote the admitted raw row")
    local view = catalog.TombstoneState("syn03")
    Check(view.state == "OPAQUE_BLOCK_ALL" and view.stamp == 30 and view.localOwned == false,
        "remote tombstone gained current-session authority")
    Check(#Drain() == 0, "remote tombstone was relayed")
    local generation = S.Root().generation
    Check(Sync.HandleIncoming("WLRD|Peer|syn03|30|Peer", "Peer-Ebonhold"),
        "exact replay was not a no-op")
    Check(S.Root().generation == generation, "exact replay republished")
    Check(Sync.HandleIncoming("WLRD|Peer|syn03|31|Peer", "Peer-Ebonhold") == false
        and catalog.TombstoneState("syn03").stamp == 30,
        "unequal replay refreshed the reservation")
    Deliver(BuildWire(Payload("syn03", 3, 0, {m=99})))
    Check(catalog.Get("syn03") == nil, "remote resurrection succeeded")
    Check(Sync.TombstoneCount() == 1, "tombstone count disagrees with the catalog")
    -- a peer other than the owner still cannot delete
    Check(catalog.Put(S.Build("syn03b", 3, 0), {source="remote", sender="Peer-Ebonhold"}))
    Check(Sync.HandleIncoming("WLRD|Griefer|syn03b|40|Griefer", "Griefer-Ebonhold") == false
        and catalog.Get("syn03b") ~= nil, "non-owner delete was applied")
end)

Case("SYN-04", "local delete uses the V1 tombstone and session-only pending", function()
    local db = ResetSync(S.Database({}))
    local catalog = Catalog()
    Check(catalog.Put(S.LocalBuild("syn04", 3), {source="local"}))
    local ok, why = Sync.BroadcastDelete(catalog.Get("syn04"))
    Check(ok, "local delete refused: " .. tostring(why))
    local sent = Drain()
    local wire
    for _, message in ipairs(sent) do
        if message.text:find("^WLRD|", 1, false) then wire = message.text end
    end
    Check(wire and wire:find("|syn04|", 1, true), "local delete did not emit WLRD")
    local durable = db.syncTombstones.syn04
    Check(type(durable) == "table" and durable.schemaVersion == 1 and durable.pending == nil,
        "local tombstone is not the V1 durable shape or carries a pending payload")
    Check(catalog.TombstoneState("syn04").state == "CURRENT_DENY"
        and catalog.TombstoneState("syn04").localOwned == true,
        "local tombstone lost current-session authority")
    Check(Sync.WorkState().pendingDeletes == 0, "pending state leaked after send")
    -- the original author may readmit only through the explicit local claim
    local claim = assert(catalog.BeginTombstoneReadmissionClaim("syn04"))
    Check(catalog.PutWithClaim(claim, S.LocalBuild("syn04", 2, {lastModified=99}),
        {source="local"}), "local readmission refused")
    Check(catalog.Get("syn04") and db.syncTombstones.syn04 == nil,
        "local readmission did not replace the tombstone")
end)

Case("SYN-05", "summary n is request evidence only; n>85 never requests", function()
    ResetSync(S.Database({}))
    local function SummaryWire(id, n)
        local payload = {id=id, t="Summary " .. id, a="Peer", o="peer@ebonhold",
            c="MAGE", m=20, h="deadbeef", n=n}
        return "WLBI|Peer|" .. Codec.Base64Encode(Codec.JSONEncode(payload))
    end
    local pendingBefore = Sync.WorkState().pendingReplacements or 0
    Check(Sync.HandleIncoming(SummaryWire("syn05-over", 86), "Peer-Ebonhold") == false,
        "n=86 summary was accepted")
    Check((Sync.WorkState().pendingReplacements or 0) == pendingBefore
        and Catalog().Get("syn05-over") == nil,
        "n=86 summary queued a request or stored a row")
    Check(Sync.HandleIncoming(SummaryWire("syn05-max", 85), "Peer-Ebonhold"),
        "n=85 summary was refused")
    local stored = Catalog().Get("syn05-max")
    Check(stored == nil or stored.loadoutAvailable ~= true,
        "summary scalar n proved loadout availability")
end)

S.Finish("sync semantic envelope and protocol-7 identity matrix")
