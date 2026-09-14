-- Package B / issue #22: the 79/6/85 semantic envelope at every protocol-7
-- trust boundary, protocol-7 typed-identity refusal, and remote tombstone
-- behaviour through the real Sync stack in one runtime (PRO, SYN, MIX local).
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
local S = dofile("tests/catalog_authority_support.lua")
local BaseCase, Check = S.Case, S.Check
local caseFilter = os.getenv("BN_SYNC_CASE")
local function Case(id, name, body)
    if caseFilter and caseFilter ~= ""
        and not ("," .. caseFilter .. ","):find("," .. id .. ",", 1, true) then
        return
    end
    return BaseCase(id, name, body)
end

-- The sandbox runs as a different Windows identity from the worktree owner.
-- Keep fixture Git reads local to this exact checkout and never alter global
-- Git configuration.
local materializedTrees = {}
local function ReadMaterialized(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local value = handle:read("*a")
    handle:close()
    return value
end
function H.MaterializeBaseTreeV1(commit)
    assert(type(commit) == "string" and #commit >= 7,
        "MaterializeBaseTreeV1 requires an exact commit")
    local cached = materializedTrees[commit]
    if cached then return cached.root, cached.tree end
    local temp = (os.getenv("TEMP") or os.getenv("TMPDIR") or ".")
    local dir = (temp:gsub("\\", "/")) .. "/bn-mix-" .. commit:sub(1, 12)
    local windows = dir:gsub("/", "\\")
    os.execute('rmdir /s /q "' .. windows .. '" 2>nul')
    os.execute('mkdir "' .. windows .. '" 2>nul')
    local cwdPath = dir .. "/.mix-cwd"
    os.execute('cd > "' .. cwdPath .. '"')
    local safeRoot = ReadMaterialized(cwdPath)
    safeRoot = safeRoot and safeRoot:gsub("%s+$", ""):gsub("\\", "/")
    assert(type(safeRoot) == "string" and safeRoot ~= "",
        "could not resolve the active fixture checkout")
    local safeGit = 'git -c safe.directory="' .. safeRoot .. '"'
    os.execute(safeGit .. ' archive ' .. commit
        .. ' | tar -x -C "' .. dir .. '"')
    local hashPath = dir .. "/.mix-tree"
    os.execute(safeGit .. ' log -1 --format=%T ' .. commit
        .. ' > "' .. hashPath .. '"')
    local tree = ReadMaterialized(hashPath)
    tree = tree and tree:gsub("%s+$", "") or nil
    materializedTrees[commit] = {root=dir, tree=tree}
    return dir, tree
end

local Codec, Sync = Nexus.Codec, Nexus.Sync
local clock = 1000
GetTime = function() return clock end
local now = 2000000000
time = function() return now end

local function Catalog() return Nexus.BuildCatalog end

-- Isolated peers use their own public scheduler seams. Setup waits for its
-- mutation ticket; receive assertions inspect only the settled durable state.
local function PumpSide(side)
    local catalog = side.nexus.BuildCatalog
    if type(catalog.PumpRootAdmission) == "function" then
        catalog.PumpRootAdmission()
    end
    if type(catalog.RootState) == "function" then
        local root = catalog.RootState()
        if root.state ~= "ROOT_ADMITTED" or root.candidate == true then
            return false, "catalog"
        end
    end
    local cache = side.nexus.BuildHashCache
    if type(cache) == "table" and type(cache.Pump) == "function"
        and cache.Pump() ~= true then
        return false, "hash-cache"
    end
    side.nexus.Sync.OnUpdate(0.2)
    return true
end

local function SettleSide(side)
    local catalog = side.nexus.BuildCatalog
    if type(catalog.RootState) ~= "function" then return end
    local budget = type(catalog.Budget) == "function" and catalog.Budget() or {}
    local limit = math.min(tonumber(budget.maximumPumps) or 200000, 200000)
    for _ = 1, limit do
        if not catalog.RootState().candidate then return end
        catalog.PumpRootAdmission()
    end
    Check(not catalog.RootState().candidate, "isolated peer catalog did not settle")
end

local OriginalIsolatedSide = H.IsolatedSideV1
H.IsolatedSideV1 = function(root, database, identity)
    local side = OriginalIsolatedSide(root, database, identity)
    local catalog = side.nexus and side.nexus.BuildCatalog
    if type(catalog) == "table" and type(catalog.Init) == "function"
        and type(catalog.RootState) == "function" then
        catalog.Init(side.env.NexusDB, side.nexus.BundledBuilds)
        SettleSide(side)
        local state = catalog.RootState()
        assert(state.state == "ROOT_ADMITTED" and state.candidate ~= true,
            "isolated peer catalog did not reach ROOT_ADMITTED")
    end
    local dps = side.nexus and side.nexus.DpsCapture
    if dps and type(dps.Init) == "function" then
        dps.Init({}, side.nexus.Sync)
    end
    local cache = side.nexus and side.nexus.BuildHashCache
    if type(cache) == "table" and type(cache.Pump) == "function" then
        for pumps = 0, 200000 do
            if cache.Pump() == true then break end
            assert(pumps < 200000,
                "isolated peer compatibility hashes did not converge")
        end
    end
    return side
end

local function PutSide(side, record, options)
    local ok, why, ticket = side.nexus.BuildCatalog.Put(record, options)
    if ok == nil and why == "ROOT_MUTATION_PENDING" then
        SettleSide(side)
        Check(ticket and ticket.state ~= "pending", "setup mutation did not settle")
        return ticket.committed, ticket.reason
    end
    return ok, why
end

local function ReplaySide(side, wire, sender, pumps)
    local result = H.ReplayIntoReceiverV1(side, wire, sender, 0)
    for _ = 1, (pumps or 20) do PumpSide(side) end
    SettleSide(side)
    result.after = side.nexus.Codec.JSONEncode(side.env.NexusDB)
    result.mutated = result.before ~= result.after
    return result
end

local function Pump(seconds)
    for _ = 1, math.ceil((seconds or 10) / 0.2) do
        clock = clock + 0.2
        local catalog = Catalog()
        catalog.PumpRootAdmission()
        local root = catalog.RootState()
        if root.state == "ROOT_ADMITTED" and root.candidate ~= true then
            local cache = Nexus.BuildHashCache
            if type(cache) ~= "table" or type(cache.Pump) ~= "function"
                or cache.Pump() == true then Sync.OnUpdate(0.2) end
        end
    end
end

local function SettleCatalog()
    local catalog = Catalog()
    local limit = catalog.Budget().maximumPumps
    for _ = 1, limit do
        if not catalog.RootState().candidate then return end
        catalog.PumpRootAdmission()
    end
    Check(not catalog.RootState().candidate, "catalog did not settle")
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
    H.AdmitCatalogV1(db, Nexus.BundledBuilds)
    Sync.Init(Codec, {})
    H.sentChatMessages = {}
    return db
end

-- Protocol boundary ---------------------------------------------------------

Case("SYN-W2-01", "Sync accounts for a received build only after commit", function()
    local rows = {}
    for index = 1, 9 do
        local id = "pending-seed-" .. tostring(index)
        rows[id] = S.LocalBuild(id, 1)
    end
    local db = ResetSync(S.Database(rows))
    local before = rawget(db, "authorityBundle")
    local received = Sync.Stats().received
    Deliver(BuildWire(Payload("pending-received", 1, 0)))
    Check(rawget(db, "authorityBundle") == before
            and Catalog().Get("pending-received") == nil,
        "pending receive already changed the serving bundle")
    Check(Sync.Stats().received == received,
        "Sync counted a received build before its pending catalog commit")
    local outcome
    for _ = 1, Catalog().Budget().maximumPumps do
        outcome = Catalog().PumpRootAdmission()
        if outcome.state ~= "pending" then break end
    end
    Check(outcome.committed == true and Catalog().Get("pending-received") ~= nil,
        "received build did not commit through its retained catalog candidate")
    Check(Sync.Stats().received == received + 1,
        "Sync did not account for the terminal committed receive exactly once")
end)

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
--
-- MASTER-RC-015 step 3: MIX-06 and MIX-07 rebuilt to full fixture mechanics.
-- Fixture rules 1-5 (architecture 4700-4708) require the verified PR #68 tree,
-- each side in its own global table in exact TOC order, real captured bytes fed
-- through the other side's real receive path, and a durable or fail-closed
-- terminal asserted -- never a helper return alone. The single-runtime
-- assertions each case already carried are KEPT and the quadrant drive is added
-- beneath them, so nothing that was covered stops being covered.
--
-- VERIFIED ON THE BASE TREE BEFORE WRITING, and it decides which half of each
-- class is contract and which is characterization:
--   * `MAX_BUILD_ID_BYTES = 96` at the identical line 68 in BOTH trees, and both
--     resolve `ValidIdentifier` from SyncProtocol. Width and encoding refusals
--     are therefore TWO-SIDED contract; only the reason string is new-tree.
--   * base calls `ValidIdentifier(tostring(build.id or ""), ...)` -- it
--     STRINGIFIES then validates -- while the new tree validates the typed id.
--     `WireBuildId` and `TypedIdentity` have zero occurrences in the base tree.
--     So numeric-versus-string collision is NEW-SIDE contract with the old side
--     as characterization, exactly as the fixture rule row says.
--
-- KEYS COVERED AND STILL OPEN, stated exactly rather than approximated.
-- COVERED in this file:
--   WLRB (BroadcastBuild), WLBI (BroadcastBuildSummary),
--   WLRD (BroadcastDelete), WLLQ (RequestLoadout) -- four quadrants each,
--     driven from a public send path, in MIX-06/07.
--   WLRQ, WLRC -- MIX-17, on BOTH trees: one correlated claim naming the
--     requester and its request id, with no durable mutation and no channel
--     movement.
--   WLBC -- MIX-18, on BOTH trees: a bucket claim is non-durable, mutates
--     nothing and moves no channel.
--   WLLC -- RCONF-01: the responder's loadout claim, exactly one alongside the
--     complete chunk sequence.
--   WLDS -- MIX-21, on BOTH trees: exactly one from the public BroadcastDps.
--   WLNP -- MIX-21: measured to have NO public send entry (asserted as a fact,
--     not invented), plus its inbound terminal -- non-durable, no relay, no
--     channel movement.
--   TOTAL 10 of 11 with an asserted disposition.
--   WLD2 -- MIX-25 names its producer by inventory: every WLD2 construction
--     site in core/Sync.lua lies inside the public Sync.BroadcastDpsRecord,
--     and the frozen parent has the same shape at its own line numbers.
--   TOTAL 11 of 11 with an asserted disposition.
-- MIX-06/07 therefore remain DELEGATED-AND-PARTIAL on key breadth even though
-- their mechanics are now full: verified base tree, isolated exact-TOC sides,
-- real captured bytes, real receive path, durable/fail-closed terminals.

local MIX_COMMIT = "6f6204dc9e94b0339f2c9cbacf0c5de8b98a539f"
local MIX_TREE = "0d293768d6c7a14d78a9b9ee9b3844d2b9bad3b6"
local MIX_BASE

-- Rule 1. H.MaterializeBaseTreeV1 reports the tree hash and does not assert it,
-- so the verification is the caller's and cannot be skipped by accident.
local function MixQuadrants()
    if not MIX_BASE then
        local root, tree = H.MaterializeBaseTreeV1(MIX_COMMIT)
        Check(tree == MIX_TREE,
            "materialized base tree hash is " .. tostring(tree)
                .. ", required " .. MIX_TREE)
        MIX_BASE = root
    end
    return {
        {name="oldold", sender=MIX_BASE, receiver=MIX_BASE, senderIsNew=false},
        {name="oldnew", sender=MIX_BASE, receiver=".", senderIsNew=false},
        {name="newold", sender=".", receiver=MIX_BASE, senderIsNew=true},
        {name="newnew", sender=".", receiver=".", senderIsNew=true},
    }
end

local mixSequence = 0
local function MixRecord(id)
    mixSequence = mixSequence + 1
    return {
        id=id, title="Envelope " .. mixSequence, author="Boganic",
        ownerKey="boganic@ebonhold", realm="ebonhold", ownerVerified=true,
        isMine=true, class="MAGE", postedAt=10, lastModified=10,
        echoes={{spellId=300000 + mixSequence, quality=3, stacks=1}},
    }
end

-- Drive one public send path on a side and return the wire it actually emitted
-- plus the operation's own result. Batched under ONE quadrant boot, which the
-- accepted structure permits, and which never omits a sender/receiver
-- combination because the caller loops the quadrants.
local function MixDrive(side, key, record)
    local wire, ok, accepted, why = H.CaptureWireV1(side, function(s)
        pcall(PutSide, s, record, {source="local"})
        if key == "WLRB" then
            return s.nexus.Sync.BroadcastBuild(record)
        elseif key == "WLBI" then
            return s.nexus.Sync.BroadcastBuildSummary(record, {retryOnFull=true})
        elseif key == "WLRD" then
            return s.nexus.Sync.BroadcastDelete(record)
        elseif key == "WLLQ" then
            return s.nexus.Sync.RequestLoadout(record.id)
        end
    end)
    return wire, ok, accepted, why
end


Case("MIX-06", "numeric 1 and string \"1\" never collide; numeric never reaches wire", function()
    local db = ResetSync(S.Database({}))
    local catalog = Catalog()
    Check(S.CatalogMutation(function()
        return catalog.Put(S.LocalBuild(1, 2), {source="local"})
    end, "numeric typed-id admission"), "numeric local ID refused")
    Check(S.CatalogMutation(function()
        return catalog.Put(S.LocalBuild("1", 3), {source="local"})
    end, "string typed-id admission"), "string local ID refused")
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
    -- Legacy-to-bundle cutover: durable typed slots live in the bundle payload.
    Check(S.Durable(db)[1] ~= nil and S.Durable(db)["1"] ~= nil,
        "typed slots were merged in storage")

    -- FULL FIXTURE MECHANICS, all four quadrants.
    for _, q in ipairs(MixQuadrants()) do
        local sender = H.IsolatedSideV1(q.sender)
        Check(#sender.failed == 0,
            q.name .. ": sender side failed to load " .. #sender.failed
                .. " module(s)")
        for _, key in ipairs({"WLRB", "WLBI", "WLRD", "WLLQ"}) do
            local numeric = MixRecord(1)
            local wire, _, accepted, why = MixDrive(sender, key, numeric)
            local emitted = H.WireOfCodeV1(wire, key)
            if q.senderIsNew then
                -- Contract: a numeric id is unrepresentable in protocol 7 and
                -- is refused before any bytes, on every key.
                Check(#emitted == 0,
                    q.name .. "/" .. key .. ": a numeric id reached the wire ["
                        .. H.WireCodesV1(wire) .. "]")
                Check(accepted == false
                        and tostring(why):find("PROTOCOL7", 1, true) ~= nil,
                    q.name .. "/" .. key .. ": numeric refusal was "
                        .. tostring(accepted) .. "/" .. tostring(why))
            else
                -- Characterization only: the base tree stringifies the id
                -- before validating, so it has no typed-identity refusal.
                Check(true, q.name .. "/" .. key .. ": old sender emitted "
                    .. #emitted .. " " .. key .. " [" .. H.WireCodesV1(wire)
                    .. "]")
            end
            -- Rule 5 on both sides: whatever the sender did, no receiver may
            -- end up holding the numeric row aliased under the string key.
            if #emitted > 0 then
                local receiver = H.IsolatedSideV1(q.receiver)
                local got = ReplaySide(receiver, emitted, "Boganic")
                Check(got.Durable("1") == nil,
                    q.name .. "/" .. key
                        .. ": a numeric id converged aliased to the string key")
            end
        end
    end
end)

Case("MIX-07", "only exact 1..96-byte UTF-8 identifiers send", function()
    ResetSync(S.Database({}))
    local catalog = Catalog()
    local wide = string.rep("a", 97)
    local exact = string.rep("b", 96)
    local invalidUtf8 = "id\255x"
    local control = "id\1x"
    Check(S.CatalogMutation(function()
        return catalog.Put(S.LocalBuild(wide, 1), {source="local"})
    end, "97-byte id admission"), "97-byte local ID refused")
    Check(S.CatalogMutation(function()
        return catalog.Put(S.LocalBuild(exact, 1), {source="local"})
    end, "96-byte id admission"), "96-byte local ID refused")
    Check(S.CatalogMutation(function()
        return catalog.Put(S.LocalBuild(invalidUtf8, 1), {source="local"})
    end, "invalid UTF-8 id admission"), "invalid UTF-8 local ID refused")
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

    -- FULL FIXTURE MECHANICS, all four quadrants. Width and encoding are
    -- TWO-SIDED contract: both trees carry MAX_BUILD_ID_BYTES = 96 at the
    -- identical line 68 and both resolve ValidIdentifier from SyncProtocol, so
    -- neither side may put an unrepresentable id on the wire. Only the reason
    -- string is new-tree specific, so it is asserted only there.
    local UNREPRESENTABLE = {
        {label="97-byte", id=string.rep("w", 97)},
        {label="256-byte", id=string.rep("x", 256)},
        {label="control-byte", id="idx"},
        {label="delimiter", id="id|x"},
        {label="invalid-utf8", id="id­x"},
    }
    for _, q in ipairs(MixQuadrants()) do
        local sender = H.IsolatedSideV1(q.sender)
        Check(#sender.failed == 0,
            q.name .. ": sender side failed to load " .. #sender.failed
                .. " module(s)")
        for _, spec in ipairs(UNREPRESENTABLE) do
            for _, key in ipairs({"WLRB", "WLBI", "WLRD", "WLLQ"}) do
                local record = MixRecord(spec.id)
                local wire, _, accepted, why = MixDrive(sender, key, record)
                local emitted = H.WireOfCodeV1(wire, key)
                Check(#emitted == 0,
                    q.name .. "/" .. spec.label .. "/" .. key
                        .. ": an unrepresentable id reached the wire ["
                        .. H.WireCodesV1(wire) .. "]")
                if q.senderIsNew then
                    -- The rule requires an EXACT refusal with zero bytes on
                    -- every key, which is asserted for every key here. It does
                    -- not fix one reason string across every send path.
                    Check(accepted == false,
                        q.name .. "/" .. spec.label .. "/" .. key
                            .. ": an unrepresentable id was accepted")
                    -- MEASURED DIVERGENCE, recorded rather than loosened away:
                    -- the build path reports a PROTOCOL7_* reason, while the
                    -- summary path reports the generic "invalid build id" (seen
                    -- as newold/control-byte/WLBI). Both refuse and both emit
                    -- zero bytes, so the contract holds; the reason precision
                    -- differs by path. The PROTOCOL7 reason is therefore
                    -- asserted where the architecture names it, on the build
                    -- path, and the divergence is disclosed here rather than
                    -- asserted away.
                    if key == "WLRB" then
                        Check(tostring(why):find("PROTOCOL7", 1, true) ~= nil,
                            q.name .. "/" .. spec.label
                                .. "/WLRB: refusal reason was "
                                .. tostring(why) .. ", expected a PROTOCOL7_*")
                    end
                end
            end
        end
        -- BOTH-SIDES GUARD: 96 bytes is inside the bound on both trees and must
        -- still reach the wire carrying its id verbatim, so none of the
        -- refusals above can be a blanket refusal of long ids.
        local fits = MixRecord(string.rep("e", 96))
        local okWire = H.WireOfCodeV1(MixDrive(sender, "WLRB", fits), "WLRB")
        Check(#okWire >= 1,
            q.name .. ": a 96-byte id emitted no WLRB at all")
        if #okWire >= 1 then
            Check(okWire[1]:find("||" .. fits.id .. "||", 1, true) ~= nil,
                q.name .. ": the 96-byte id was not carried verbatim")
        end
    end
end)

-- Inbound admission ---------------------------------------------------------

Case("SYN-01", "inbound 80 ordinary rejects before storage or relay", function()
    local db = ResetSync(S.Database({}))
    Sync.ClearLog()
    Deliver(BuildWire(Payload("syn01", 80, 0)))
    Check(S.Durable(db).syn01 == nil and Catalog().Get("syn01") == nil,
        "80 ordinary reached durable storage")
    Check(#Drain() == 0, "rejected payload was relayed")
end)

Case("SYN-02", "inbound 79 plus 6 explicit locked converges once", function()
    local db = ResetSync(S.Database({}))
    Deliver(BuildWire(Payload("syn02", 79, 6)))
    SettleCatalog()
    local record = Catalog().Get("syn02")
    Check(record and #record.echoes == 85, "79/6 payload was not stored")
    Check(S.State("syn02").semantic.locked == 6, "locked role evidence was lost")
    Check(S.Durable(db).syn02 ~= nil, "durable row missing")
    local generation = S.Root().generation
    Deliver(BuildWire(Payload("syn02", 79, 6)))
    SettleCatalog()
    Check(S.Root().generation == generation, "exact replay republished the root")
end)

Case("SYN-03", "remote tombstone: opaque block-all, replay, conflict, no resurrection", function()
    local db = ResetSync(S.Database({}))
    local catalog = Catalog()
    Check(S.CatalogMutation(function()
        return catalog.Put(S.Build("syn03", 3, 0),
            {source="remote", sender="Peer-Ebonhold"})
    end, "remote tombstone seed"))
    local raw = S.Durable(db).syn03
    local rawBytes = S.Encode(raw)
    Sync.HandleIncoming("WLRD|Peer|syn03|30|Peer", "Peer-Ebonhold")
    SettleCatalog()
    Check(catalog.Get("syn03") == nil and catalog.Count() == 0,
        "deleted row remained publicly available")
    Check(S.Durable(db).syn03 == raw and S.Encode(raw) == rawBytes,
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
    Check(S.CatalogMutation(function()
        return catalog.Put(S.Build("syn03b", 3, 0),
            {source="remote", sender="Peer-Ebonhold"})
    end, "non-owner tombstone seed"))
    Check(Sync.HandleIncoming("WLRD|Griefer|syn03b|40|Griefer", "Griefer-Ebonhold") == false
        and catalog.Get("syn03b") ~= nil, "non-owner delete was applied")
end)

Case("SYN-04", "local delete uses the V1 tombstone and session-only pending", function()
    local db = ResetSync(S.Database({}))
    local catalog = Catalog()
    Check(S.CatalogMutation(function()
        return catalog.Put(S.LocalBuild("syn04", 3), {source="local"})
    end, "local tombstone seed"))
    -- MASTER-RC-019 SUPERSEDED EXPECTATION, with its architecture
    -- justification written down rather than silently satisfied.
    -- Architecture line 4856 and the mixed-client tombstone rows fix the
    -- contract for BOTH quadrants:
    --   new -> PR #68 : "Refuse before encoder invocation with
    --     REMOTE_TOMBSTONE_ORDER_UNPROVEN; emit zero bytes, retain the exact
    --     local serving root, create no outbound ownership claim, and produce
    --     zero relay."
    --   new -> new    : "Same local refusal and zero-wire result as
    --     new-to-old. A local row-to-tombstone operation is not a Sync
    --     message."
    -- The refusal is therefore unconditional. This case previously required
    -- the local delete to EMIT a WLRD, which is exactly what the accepted
    -- architecture forbids, so the expectation is SUPERSEDED, not relaxed:
    -- the replacement asserts the strictly stronger zero-wire contract plus
    -- the named refusal reason. Every other assertion in this case is
    -- unchanged, including the V1 durable tombstone shape, CURRENT_DENY
    -- authority, session-only pending, and the readmission claim.
    local ok, why = Sync.BroadcastDelete(catalog.Get("syn04"))
    if why == "ROOT_MUTATION_PENDING" then
        SettleCatalog()
        local terminal = Sync.GetDeleteStatus("syn04")
        Check(type(terminal) == "table" and terminal.terminal == true,
            "local delete did not publish one terminal refusal")
        ok, why = false, terminal and terminal.reason or why
    end
    Check(ok == false and why == "REMOTE_TOMBSTONE_ORDER_UNPROVEN",
        "local delete was not the named zero-wire refusal: "
            .. tostring(ok) .. "/" .. tostring(why))
    local sent = Drain()
    local wire
    for _, message in ipairs(sent) do
        if message.text:find("^WLRD|", 1, false) then wire = message.text end
    end
    Check(wire == nil, "a local row-to-tombstone operation emitted wire bytes")
    local durable = S.Durable(db, "syncTombstones").syn04
    Check(type(durable) == "table" and durable.schemaVersion == 1 and durable.pending == nil,
        "local tombstone is not the V1 durable shape or carries a pending payload")
    Check(catalog.TombstoneState("syn04").state == "CURRENT_DENY"
        and catalog.TombstoneState("syn04").localOwned == true,
        "local tombstone lost current-session authority")
    Check(Sync.WorkState().pendingDeletes == 0, "pending state leaked after send")
    -- the original author may readmit only through the explicit local claim
    local claim = assert(catalog.BeginTombstoneReadmissionClaim("syn04"))
    Check(S.CatalogMutation(function()
        return catalog.PutWithClaim(claim,
            S.LocalBuild("syn04", 2, {lastModified=99}), {source="local"})
    end, "local tombstone readmission"), "local readmission refused")
    Check(catalog.Get("syn04") and S.Durable(db, "syncTombstones").syn04 == nil,
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
    local acceptedMax = Sync.HandleIncoming(SummaryWire("syn05-max", 85),
        "Peer-Ebonhold")
    if not acceptedMax and Catalog().RootState().candidate then
        -- The accepted summary is one retained catalog mutation; its terminal
        -- commit is the only acceptance evidence, so settle and read the row.
        S.PumpCatalogToIdle("n=85 summary admission")
        acceptedMax = Catalog().Get("syn05-max") ~= nil
    end
    Check(acceptedMax, "n=85 summary was refused")
    local stored = Catalog().Get("syn05-max")
    Check(stored == nil or stored.loadoutAvailable ~= true,
        "summary scalar n proved loadout availability")
end)


-- ---------------------------------------------------------------------------
-- MASTER-RC-003 REOPENED ELEMENT: the 79/6/85 envelope and `n` ON THE WIRE.
--
-- RC-003 requires "exact 79/6/85 and n=85 through every summary/full path".
-- Its previous evidence, SEM-05 in tests/run_catalog_authority_semantic_union.lua,
-- pins the envelope on Catalog().Put/Get only -- that file contains ZERO
-- references to `Sync.`, `WLRB`, `HandleIncoming` or `Broadcast`, so the wire
-- paths were entirely unobserved. RC-003 was closed on incomplete evidence by
-- the coordinator and reopened on this worker's measurement.
--
-- These cases pin the SEND half on the wire. The responder half is a separate
-- element and is NOT covered here: the fixture cannot yet reach the
-- loadout-response path, which is a coverage gap, not a defect -- an isolated
-- responder holding a never-broadcast build answers a WLLQ with nothing even
-- for a 2-echo payload, so the behaviour is uniform across payload size, locked
-- content, build presence and peer identity.
--
-- Architecture line 4722: "The new sender must emit the exact full-payload
-- total in `n`, because the PR #68 receiver checks that scalar against the
-- decoded full payload. No capability heuristic is needed: the established full
-- payload's Echo tuple slot 4 carries the locked flag."
--
-- MEASURED BEFORE WRITING: both trees emit `"n":85` for 79+6 and `"n":79` for
-- 79 ordinary, so `n` is a TWO-SIDED contract asserted on both. The base tree
-- can emit the summary for 85 even though it emits no full-payload chunks for
-- it, which is why the full-payload assertions below are new-side only.

local function SndEchoes(ordinary, locked)
    local rows, spell = {}, 100000
    for _ = 1, (ordinary or 0) do
        rows[#rows + 1] = {spellId=spell, quality=3, stacks=1}
        spell = spell + 1
    end
    spell = 200000
    for _ = 1, (locked or 0) do
        rows[#rows + 1] = {spellId=spell, quality=3, stacks=1, locked=true}
        spell = spell + 1
    end
    return rows
end

local sndSequence = 0
local function SndRecord(ordinary, locked)
    sndSequence = sndSequence + 1
    return {
        id="snd" .. sndSequence, title="Send " .. sndSequence,
        author="Boganic", ownerKey="boganic@ebonhold", realm="ebonhold",
        ownerVerified=true, isMine=true, class="MAGE",
        postedAt=10, lastModified=10, echoes=SndEchoes(ordinary, locked),
    }
end

-- Reassemble a wire sequence and decode it. The framings differ by message:
-- a chunked full payload is CODE||sender||id||stamp||i/n||body (body field 6)
-- while a summary is CODE||sender||body (body field 3). The base64 body is the
-- LAST field in both, so taking the last field handles each without assuming a
-- fixed index -- assuming field 6 made the summary undecodable.
local function SndDecode(side, texts)
    local body = {}
    for _, text in ipairs(texts) do
        local parts = {}
        for piece in (text .. "||"):gmatch("(.-)||") do
            if piece ~= "" then parts[#parts + 1] = piece end
        end
        body[#body + 1] = parts[#parts] or ""
    end
    local joined = table.concat(body)
    local codec = side.nexus.Codec
    local raw = codec.Base64DecodeNetwork(joined) or codec.Base64Decode(joined)
    if not raw then return nil end
    return codec.JSONDecode(raw), raw
end

Case("SND-01",
    "MASTER-RC-003: the full payload carries 85 tuples with exactly 6 slot-4",
function()
    local side = H.IsolatedSideV1(".")
    local record = SndRecord(79, 6)
    local wire = H.CaptureWireV1(side, function(s)
        PutSide(s, record, {source="local"})
        return s.nexus.Sync.BroadcastBuild(record)
    end, 60)
    local chunks = H.WireOfCodeV1(wire, "WLRB")
    Check(#chunks > 0,
        "the new sender emitted no full-payload chunks for 79+6 [window: "
            .. H.WireCodesV1(wire) .. "]")
    if #chunks == 0 then return end
    local decoded = SndDecode(side, chunks)
    Check(type(decoded) == "table" and type(decoded.e) == "table",
        "the reassembled full payload did not decode")
    if not (type(decoded) == "table" and type(decoded.e) == "table") then
        return
    end
    local slot4, total = 0, 0
    for _, tuple in ipairs(decoded.e) do
        total = total + (tonumber(tuple[3]) or 0)
        if tuple[4] ~= nil then slot4 = slot4 + 1 end
    end
    Check(#decoded.e == 85,
        "the full payload carried " .. #decoded.e .. " echo tuples, required 85")
    Check(slot4 == 6,
        "the full payload carried " .. slot4
            .. " slot-4 locked flags, required exactly 6")
    Check(total == 85,
        "the full payload summed " .. total .. " stacks, required 85")
end)

Case("SND-02",
    "MASTER-RC-003: the summary scalar n equals the full total, on both trees",
function()
    -- Two-sided: measured, both trees emit n=85 for 79+6 and n=79 for 79.
    -- MaterializeBaseTreeV1 returns (root, treeHash); binding the root to a
    -- local first is required, because `select(1, ...)` inside a table
    -- constructor expands BOTH values and would add the hash as a third
    -- bogus root.
    local baseRoot = H.MaterializeBaseTreeV1(
        "6f6204dc9e94b0339f2c9cbacf0c5de8b98a539f")
    for _, root in ipairs({".", baseRoot}) do
        local label = root == "." and "new" or "base"
        for _, spec in ipairs({{o=79, l=6, n=85}, {o=79, l=0, n=79}}) do
            local side = H.IsolatedSideV1(root)
            local record = SndRecord(spec.o, spec.l)
            local wire = H.CaptureWireV1(side, function(s)
                PutSide(s, record, {source="local"})
                return s.nexus.Sync.BroadcastBuildSummary(record,
                    {retryOnFull=true})
            end, 60)
            local summaries = H.WireOfCodeV1(wire, "WLBI")
            Check(#summaries == 1,
                label .. "/" .. spec.n .. ": emitted " .. #summaries
                    .. " summaries [window: " .. H.WireCodesV1(wire) .. "]")
            if #summaries == 1 then
                local decoded = SndDecode(side, summaries)
                Check(type(decoded) == "table" and decoded.n == spec.n,
                    label .. ": summary n was "
                        .. tostring(type(decoded) == "table" and decoded.n
                            or "undecodable")
                        .. ", required " .. spec.n)
            end
        end
    end
end)

Case("SND-03",
    "GUARD: 79 ordinary carries no slot-4 flag and sums 79",
function()
    -- Passes before and after: the locked flag must appear only when locked
    -- rows exist, so SND-01 cannot be satisfied by stamping slot 4 everywhere.
    local side = H.IsolatedSideV1(".")
    local record = SndRecord(79, 0)
    local wire = H.CaptureWireV1(side, function(s)
        PutSide(s, record, {source="local"})
        return s.nexus.Sync.BroadcastBuild(record)
    end, 60)
    local chunks = H.WireOfCodeV1(wire, "WLRB")
    Check(#chunks > 0, "the new sender emitted no chunks for 79 ordinary")
    if #chunks == 0 then return end
    local decoded = SndDecode(side, chunks)
    if not (type(decoded) == "table" and type(decoded.e) == "table") then
        Check(false, "the 79-ordinary payload did not decode")
        return
    end
    local slot4, total = 0, 0
    for _, tuple in ipairs(decoded.e) do
        total = total + (tonumber(tuple[3]) or 0)
        if tuple[4] ~= nil then slot4 = slot4 + 1 end
    end
    Check(#decoded.e == 79 and total == 79,
        "79 ordinary produced " .. #decoded.e .. " tuples summing " .. total)
    Check(slot4 == 0,
        "79 ordinary carried " .. slot4 .. " slot-4 locked flags, required 0")
end)

-- ---------------------------------------------------------------------------
-- MASTER-RC-015: rule 7 class 6 (recovery) and the WLRQ / WLRC / WLBC keys.
--
-- ORDINARY PAYLOADS ONLY. No locked echo appears anywhere in these cases. The
-- locked-payload question -- whether the accepted architecture's new->old
-- convergence outcome is satisfiable on the exact 6f6204dc tree, given that
-- PR #68's core/LoadoutEvidence.lua:421-429 abandons echo resolution on the
-- first locked echo -- is under consultation. Nothing here asserts old-side
-- convergence of a locked payload, and nothing here asserts that the responder
-- refuses one.
--
-- MEASURED BEFORE WRITING:
--   * A partial chunk set admits NOTHING durable and holds exactly one
--     buildInflight; the receiver emits no spontaneous recovery request for the
--     missing chunk. Delivering the final chunk reaches the durable terminal
--     and clears inflight to zero.
--   * A reconciliation request (WLRQ) from a distinct peer draws exactly one
--     correlated WLRC naming that requester and its requestId, on BOTH trees.
--   * Both sides must carry DISTINCT identities or the exchange is treated as a
--     self-request and silently dropped (core/SyncReconciler.lua ScheduleLoadout).

local RECOVERY_BASE_COMMIT = "6f6204dc9e94b0339f2c9cbacf0c5de8b98a539f"

local keySequence = 0
local function KeyRecord(ordinaryStacks, owner)
    keySequence = keySequence + 1
    local rows, spell = {}, 100000
    for _ = 1, ordinaryStacks do
        rows[#rows + 1] = {spellId=spell, quality=3, stacks=1}
        spell = spell + 1
    end
    return {
        id="key" .. keySequence, title="Key " .. keySequence,
        author=owner, ownerKey=owner:lower() .. "@ebonhold", realm="ebonhold",
        ownerVerified=true, isMine=true, class="MAGE",
        postedAt=10, lastModified=10, echoes=rows,
    }
end

local function KeyStacks(record)
    if type(record) ~= "table" or type(record.echoes) ~= "table" then
        return -1
    end
    local total = 0
    for _, echo in ipairs(record.echoes) do
        total = total + (tonumber(echo.stacks) or 0)
    end
    return total
end

Case("MIX-16",
    "rule 7 class 6: an interrupted transfer admits nothing and recovers",
function()
    -- Not a replay of a completed payload: the receiver is given a genuinely
    -- incomplete chunk set and must hold it without admitting anything.
    local sender = H.IsolatedSideV1(".", nil, {playerName="Sender"})
    local record = KeyRecord(79, "Sender")
    local wire = H.CaptureWireV1(sender, function(s)
        PutSide(s, record, {source="local"})
        return s.nexus.Sync.BroadcastBuild(record)
    end, 90)
    local chunks = H.WireOfCodeV1(wire, "WLRB")
    Check(#chunks >= 2,
        "the fixture needs a multi-chunk transfer to interrupt; got "
            .. #chunks)
    if #chunks < 2 then return end

    local receiver = H.IsolatedSideV1(".", nil, {playerName="Receiver"})
    for index = 1, #chunks - 1 do
        pcall(receiver.nexus.Sync.HandleIncoming, chunks[index], "Sender")
    end
    local partial = receiver.nexus.Sync.WorkState()
    Check(receiver.nexus.BuildCatalog.Get(record.id) == nil,
        "an incomplete transfer admitted a durable row")
    Check(partial.buildInflight == 1,
        "an incomplete transfer held " .. tostring(partial.buildInflight)
            .. " inflight builds, required exactly 1")

    -- The missing piece arrives through the real receive path.
    pcall(receiver.nexus.Sync.HandleIncoming, chunks[#chunks], "Sender")
    for _ = 1, 60 do PumpSide(receiver) end
    SettleSide(receiver)
    local durable = receiver.nexus.BuildCatalog.Get(record.id)
    Check(durable ~= nil,
        "the completed transfer did not reach a durable terminal")
    if durable then
        Check(KeyStacks(durable) == 79,
            "the recovered row carried " .. KeyStacks(durable)
                .. " of 79 stacks")
    end
    local settled = receiver.nexus.Sync.WorkState()
    Check(settled.buildInflight == 0,
        "the completed transfer left " .. tostring(settled.buildInflight)
            .. " inflight, required 0")
end)

Case("MIX-17",
    "rule 7 keys WLRQ and WLRC: one correlated claim, no durable mutation",
function()
    -- Non-durable control messages. Their terminal is the correlation and the
    -- wire count, so no durable assertion is invented for them.
    local baseRoot = H.MaterializeBaseTreeV1(RECOVERY_BASE_COMMIT)
    local requester = H.IsolatedSideV1(".", nil, {playerName="Alpha"})
    local ambient = H.CaptureWireV1(requester, function() return true end, 80)
    local requests = H.WireOfCodeV1(ambient, "WLRQ")
    Check(#requests >= 1,
        "the requester emitted no WLRQ [window: " .. H.WireCodesV1(ambient)
            .. "]")
    if #requests == 0 then return end
    local requestId = requests[1]:match("||(c1%-[%w%-]+)")
    Check(requestId ~= nil, "the WLRQ carried no parseable request id")

    for _, spec in ipairs({{name="new", root="."},
                           {name="old", root=baseRoot}}) do
        local responder = H.IsolatedSideV1(spec.root, nil,
            {playerName="Bravo" .. spec.name})
        PutSide(responder, KeyRecord(3, "Bravo"),
            {source="local"})
        local before = responder.nexus.Codec.JSONEncode(responder.env.NexusDB)
        local channelBefore = responder.nexus.Sync.ChannelName()
        local answered = H.CaptureWireV1(responder, function(s)
            return s.nexus.Sync.HandleIncoming(requests[1], "Alpha")
        end, 100)
        local claims = H.WireOfCodeV1(answered, "WLRC")
        Check(#claims == 1,
            spec.name .. ": a reconciliation request drew " .. #claims
                .. " WLRC claims, required exactly 1 [window: "
                .. H.WireCodesV1(answered) .. "]")
        if #claims == 1 then
            Check(claims[1]:find("Alpha", 1, true) ~= nil,
                spec.name .. ": the claim does not name the requester")
            if requestId then
                Check(claims[1]:find(requestId, 1, true) ~= nil,
                    spec.name .. ": the claim does not carry the request id "
                        .. requestId)
            end
        end
        local after = responder.nexus.Codec.JSONEncode(responder.env.NexusDB)
        Check(after == before,
            spec.name .. ": answering a reconciliation request mutated "
                .. "durable state")
        Check(responder.nexus.Sync.ChannelName() == channelBefore,
            spec.name .. ": the transport channel moved while answering")
    end
end)

Case("MIX-18",
    "rule 7 key WLBC: a bucket claim is non-durable and moves no channel",
function()
    -- A per-bucket mesh claim divides reconciliation work. It carries no
    -- payload, so its terminal is "no durable mutation, no channel movement",
    -- and no durable assertion is invented for it.
    local baseRoot = H.MaterializeBaseTreeV1(RECOVERY_BASE_COMMIT)
    for _, spec in ipairs({{name="new", root="."},
                           {name="old", root=baseRoot}}) do
        local side = H.IsolatedSideV1(spec.root, nil,
            {playerName="Claimer" .. spec.name})
        PutSide(side, KeyRecord(3, "Claimer"), {source="local"})
        local hashes = side.nexus.Sync.GetCompatibilityHashes()
        Check(type(hashes) == "string" and hashes ~= "",
            spec.name .. ": no compatibility hashes to claim against")
        local before = side.nexus.Codec.JSONEncode(side.env.NexusDB)
        local channelBefore = side.nexus.Sync.ChannelName()
        local bucket = tostring((hashes or ""):match("([%w]+)") or "0")
        local claim = "WLBC||Relay||Requester||c1-bucket||B||1||" .. bucket
        local wire = H.CaptureWireV1(side, function(s)
            return s.nexus.Sync.HandleIncoming(claim, "Relay")
        end, 80)
        local after = side.nexus.Codec.JSONEncode(side.env.NexusDB)
        Check(after == before,
            spec.name .. ": a bucket claim mutated durable state")
        Check(side.nexus.Sync.ChannelName() == channelBefore,
            spec.name .. ": a bucket claim moved the transport channel")
        Check(#H.WireOfCodeV1(wire, "WLRB") == 0,
            spec.name .. ": a bucket claim emitted build payload bytes")
    end
end)

-- ---------------------------------------------------------------------------
-- MASTER-RC-003 responder element, under the AMENDED contract.
--
-- SUPERSEDED EXPECTATION, with its documented architecture-based
-- justification. This is not an adjusted oracle: the expectation was replaced
-- by an operator decision recorded in a governing packet.
--
--   packet   C:\T3\BN\task-packets\
--              catalog-authority-22-repair-wave-1-amendment-9.json
--   sha256   85b996b1294e34506f5c845df894d808e1172bf94eca96d4dc58f91852488cb6
--
-- SUPERSEDED CLAUSE -- fixed outcome line 4739, "new -> PR #68 | Explicit
-- 79 ordinary + 0..6 locked, legacy-representable string ID". Superseded text,
-- quoted verbatim:
--
--   "Use the exact PR #68 full-payload encoder shape. Echo tuple slot 4
--    carries the locked flag. The summary scalar is the exact total stacks
--    across ordinary and locked rows and must equal the full payload total.
--    Exact golden bytes must converge once without capability/version
--    branching."
--
-- The superseding text keeps every new-side obligation and replaces only the
-- old side's terminal: emission continues without capability or version
-- branching, INCLUDING when answering a PR #68 peer's WLLQ, and the PR #68
-- receiver's terminal for a locked-bearing payload is CHARACTERIZATION, not
-- convergence -- cross-role, echoes=nil, needsFullBuild=true,
-- ordinaryComplete=false, unchanged by the complete response including the
-- claim. A locked build never converges on a PR #68 peer. That is PR #68's
-- existing behaviour for any locked row from any source, including a local
-- Put, and is not a regression introduced by the new sender.
--
-- Likely origin of the false premise: 4710 cites the base SUMMARY code, which
-- does sum locked stacks, while the base EVIDENCE path refuses them.
--
-- CLAUSES: 4720-4722, 4735-4736, 4739, 4764-4771, 4782, 4840-4841.
--
-- AUTHORITY:
--   architecture   3b5de54f56f1c27678e53b1dd7e1de742de820af
--   base commit    6f6204dc9e94b0339f2c9cbacf0c5de8b98a539f
--   base tree      0d293768d6c7a14d78a9b9ee9b3844d2b9bad3b6
--   consultation   C:\T3\BN\review-results\package-b-wave1-consult\
--                    rc003-locked-reference\SNAPSHOT_MANIFEST.txt
--
-- THE CONFLICT. Architecture 4720-4722 and 4739 state that a new sender's
-- explicit `79 ordinary + 0..6 locked` payload converges once on a PR #68
-- receiver, because that receiver decodes the full payload and reads Echo slot
-- 4. Measured on the exact base tree: the base codec does encode and decode
-- slot 4 -- representability is not the problem -- but the base evidence owner
-- returns `cross-role` on the FIRST locked tuple
-- (`core/LoadoutEvidence.lua:421-429`), and the summary/full scalar match at
-- base `core/Sync.lua:2677` sits behind a `recordComplete` gate that a locked
-- tuple makes false. It is transport-independent: a local Put on the base tree
-- drops the echo list for 79+6, 2+1 and 0+6 alike.
--
-- The likely origin of the false premise is that 4710 cites the base SUMMARY
-- code, which does sum locked stacks, while the base EVIDENCE path refuses
-- them.
--
-- The current new responder is the INTENDED implementation under the amended
-- contract. It must not be changed: refusing a valid locked record would
-- violate the amended 4739 and the no-capability-branching rule at 4764-4768.
--
-- Both measured sides are asserted below so the operator reads evidence rather
-- than a description.

Case("RCONF-01",
    "MASTER-RC-003 responder: exact 85/6 emission, PR #68 characterization",
function()
    local baseRoot = H.MaterializeBaseTreeV1(
        "6f6204dc9e94b0339f2c9cbacf0c5de8b98a539f")
    local rows, spell = {}, 100000
    for _ = 1, 79 do
        rows[#rows + 1] = {spellId=spell, quality=3, stacks=1}
        spell = spell + 1
    end
    spell = 200000
    for _ = 1, 6 do
        rows[#rows + 1] = {spellId=spell, quality=3, stacks=1, locked=true}
        spell = spell + 1
    end
    local record = {
        id="rconf85", title="Reference conflict", author="Owner",
        ownerKey="owner@ebonhold", realm="ebonhold", ownerVerified=true,
        isMine=true, class="MAGE", postedAt=10, lastModified=10, echoes=rows,
    }

    -- SIDE ONE: the new responder's outbound behaviour.
    local owner = H.IsolatedSideV1(".", nil, {playerName="Owner"})
    local pushed = H.CaptureWireV1(owner, function(s)
        PutSide(s, record, {source="local"})
        return s.nexus.Sync.BroadcastBuild(record)
    end, 90)
    local pushedChunks = H.WireOfCodeV1(pushed, "WLRB")

    local old = H.IsolatedSideV1(baseRoot, nil, {playerName="OldPeer"})
    for _, chunk in ipairs(pushedChunks) do
        pcall(old.nexus.Sync.HandleIncoming, chunk, "Owner")
    end
    local requestWire = H.CaptureWireV1(old, function(s)
        return s.nexus.Sync.RequestLoadout(record.id)
    end, 90)
    local wllq = H.WireOfCodeV1(requestWire, "WLLQ")
    Check(#wllq == 1,
        "the PR #68 receiver did not raise exactly one loadout request; got "
            .. #wllq)
    if #wllq ~= 1 then return end

    local answer = H.CaptureWireV1(owner, function(s)
        return s.nexus.Sync.HandleIncoming(wllq[1], "OldPeer")
    end, 120)
    local claims = H.WireOfCodeV1(answer, "WLLC")
    local chunks = H.WireOfCodeV1(answer, "WLRB")
    Check(#claims == 1,
        "the new responder emitted " .. #claims .. " WLLC claims, required 1")
    Check(#chunks == 8,
        "the new responder emitted " .. #chunks
            .. " WLRB chunks, measured contract is the complete 8")

    -- The answer carries the exact 85/6 payload the send rule requires.
    local body = {}
    for _, text in ipairs(chunks) do
        local parts = {}
        for piece in (text .. "||"):gmatch("(.-)||") do
            if piece ~= "" then parts[#parts + 1] = piece end
        end
        body[#body + 1] = parts[#parts] or ""
    end
    local codec = owner.nexus.Codec
    local joined = table.concat(body)
    local raw = codec.Base64DecodeNetwork(joined) or codec.Base64Decode(joined)
    local decoded = raw and codec.JSONDecode(raw) or nil
    Check(type(decoded) == "table" and type(decoded.e) == "table",
        "the responder's answer did not decode")
    if type(decoded) == "table" and type(decoded.e) == "table" then
        local slot4, total = 0, 0
        for _, tuple in ipairs(decoded.e) do
            total = total + (tonumber(tuple[3]) or 0)
            if tuple[4] ~= nil then slot4 = slot4 + 1 end
        end
        Check(#decoded.e == 85 and slot4 == 6 and total == 85,
            "the responder's answer carried " .. #decoded.e .. " tuples, "
                .. slot4 .. " slot-4, " .. total .. " stacks; required 85/6/85")
    end

    -- SIDE TWO: the PR #68 receiver, given the COMPLETE answer including the
    -- claim, in emission order. This is the measured conflict.
    for _, text in ipairs(answer) do
        if not text:find("^WLRQ") then
            pcall(old.nexus.Sync.HandleIncoming, text, "Owner")
        end
    end
    for _ = 1, 100 do pcall(old.nexus.Sync.OnUpdate, 0.2) end
    local durable = old.nexus.BuildCatalog.Get(record.id)
    Check(durable ~= nil, "the PR #68 receiver holds no row at all")
    if durable then
        Check(type(durable.echoes) ~= "table",
            "MEASUREMENT CHANGED: the PR #68 receiver now holds an echo list. "
                .. "Amendment 9 documents characterization, not convergence, "
                .. "for a locked-bearing payload; if this fails the amended "
                .. "contract must be re-measured before this case is trusted.")
        Check(durable.needsFullBuild == true
                and durable.ordinaryComplete == false
                and tostring(durable.ordinaryCompletenessReason) == "cross-role",
            "the PR #68 receiver's deferral markers changed: needsFullBuild="
                .. tostring(durable.needsFullBuild) .. " ordinaryComplete="
                .. tostring(durable.ordinaryComplete) .. " reason="
                .. tostring(durable.ordinaryCompletenessReason))
    end

    -- BOTH-SIDES GUARD. A WLLQ for a build the responder does not hold must
    -- answer nothing and mutate nothing, so the emission asserted above cannot
    -- be a responder that answers everything.
    local stranger = H.IsolatedSideV1(".", nil, {playerName="Stranger"})
    local strangerBefore =
        stranger.nexus.Codec.JSONEncode(stranger.env.NexusDB)
    local strangerWire = H.CaptureWireV1(stranger, function(s)
        return s.nexus.Sync.HandleIncoming("WLLQ||OldPeer||rconf85", "OldPeer")
    end, 100)
    Check(#H.WireOfCodeV1(strangerWire, "WLRB") == 0,
        "a responder answered a WLLQ for a build it does not hold")
    Check(stranger.nexus.Codec.JSONEncode(stranger.env.NexusDB)
            == strangerBefore,
        "answering an unheld WLLQ mutated durable state")

    -- NEW -> NEW CONTROL, required alongside so the old-peer outcome cannot
    -- silently alter the new -> new rule (4740, 4842): the same 79/6/85 record
    -- converges once on a new receiver and an exact replay does not mutate it
    -- a second time.
    local newReceiver = H.IsolatedSideV1(".", nil, {playerName="NewPeer"})
    local converged = ReplaySide(newReceiver, pushedChunks,
        "Owner", 80)
    local newRow = converged.Durable(record.id)
    Check(newRow ~= nil, "new -> new: the 85-stack payload did not converge")
    if newRow then
        local total, locked = 0, 0
        for _, echo in ipairs(newRow.echoes or {}) do
            total = total + (tonumber(echo.stacks) or 0)
            if echo.locked then locked = locked + 1 end
        end
        Check(total == 85 and locked == 6,
            "new -> new converged with " .. total .. " stacks and "
                .. locked .. " locked rows, required 85 and 6")
    end
    local settled = converged.after
    local replayed = ReplaySide(newReceiver, pushedChunks,
        "Owner", 60)
    Check(replayed.after == settled,
        "new -> new: an exact replay mutated durable state a second time")
end)

-- ---------------------------------------------------------------------------
-- MASTER-RC-015 rule 7: class 3 (invalid 80/7/86), class 4 (unrelated
-- correlation rejection), and the WLDS / WLD2 / WLNP keys.
--
-- MEASURED BEFORE WRITING:
--   * Through the PRODUCTION path the new side holds nothing for 80 ordinary,
--     79+7 and 80+6, and therefore emits zero chunks. Broadcasting a raw record
--     the catalog refused is not a production path and is not asserted.
--   * PR #68 ADMITS all three invalid totals locally (put=true, stored=true).
--     That is the old-side characterization, stated rather than asserted as a
--     contract.
--   * BroadcastDps emits WLDS on BOTH trees. WLD2 (exact-set DPS chunks) is not
--     produced by that entry.
--   * WLNP has NO public send entry: no Sync function matches "presence", and
--     OnWorldEntry emits only WLRQ. That fact is asserted; no entry is invented.

local C3_COMMIT = "6f6204dc9e94b0339f2c9cbacf0c5de8b98a539f"

local c3Sequence = 0
local function C3Record(ordinary, locked, owner)
    c3Sequence = c3Sequence + 1
    local rows, spell = {}, 100000
    for _ = 1, ordinary do
        rows[#rows + 1] = {spellId=spell, quality=3, stacks=1}
        spell = spell + 1
    end
    spell = 200000
    for _ = 1, (locked or 0) do
        rows[#rows + 1] = {spellId=spell, quality=3, stacks=1, locked=true}
        spell = spell + 1
    end
    return {
        id="c3" .. c3Sequence, title="Envelope " .. c3Sequence, author=owner,
        ownerKey=owner:lower() .. "@ebonhold", realm="ebonhold",
        ownerVerified=true, isMine=true, class="MAGE",
        postedAt=10, lastModified=10, echoes=rows,
    }
end

Case("MIX-19",
    "rule 7 class 3: 80 / 7 locked / 86 total reject before storage",
function()
    local invalid = {
        {label="80-ordinary", ordinary=80, locked=0},
        {label="79+7-locked", ordinary=79, locked=7},
        {label="80+6=86-total", ordinary=80, locked=6},
    }
    for _, spec in ipairs(invalid) do
        local side = H.IsolatedSideV1(".", nil, {playerName="Envelope"})
        local record = C3Record(spec.ordinary, spec.locked, "Envelope")
        pcall(PutSide, side, record, {source="local"})
        local held = side.nexus.BuildCatalog.Get(record.id)
        Check(held == nil,
            spec.label .. ": an over-envelope record was admitted to storage")
        -- Rejected before storage means the production path has nothing to
        -- send: a caller can only broadcast what the catalog holds.
        local wire = H.CaptureWireV1(side, function(s)
            return s.nexus.Sync.BroadcastBuild(held)
        end, 60)
        Check(#H.WireOfCodeV1(wire, "WLRB") == 0,
            spec.label .. ": an over-envelope record reached the wire [window: "
                .. H.WireCodesV1(wire) .. "]")
    end

    -- BOTH-SIDES GUARD: the exact 79+6=85 envelope is still admitted, so the
    -- refusals above cannot be a blanket refusal of large payloads.
    local ok = H.IsolatedSideV1(".", nil, {playerName="Envelope"})
    local valid = C3Record(79, 6, "Envelope")
    pcall(PutSide, ok, valid, {source="local"})
    Check(ok.nexus.BuildCatalog.Get(valid.id) ~= nil,
        "the exact 79+6=85 envelope was refused")

    -- OLD-SIDE CHARACTERIZATION, measured and stated, not asserted as contract:
    -- PR #68 admits all three invalid totals locally. Recorded so a reader
    -- knows the envelope is a new-side guarantee the frozen parent lacks.
    local baseRoot = H.MaterializeBaseTreeV1(C3_COMMIT)
    local old = H.IsolatedSideV1(baseRoot, nil, {playerName="OldEnvelope"})
    local oldRecord = C3Record(80, 0, "OldEnvelope")
    pcall(PutSide, old, oldRecord, {source="local"})
    Check(old.nexus.BuildCatalog.Get(oldRecord.id) ~= nil,
        "CHARACTERIZATION CHANGED: PR #68 now refuses 80 ordinary locally. "
            .. "The new-side envelope guarantee above is unaffected, but this "
            .. "recorded difference must be re-measured.")
end)

Case("MIX-20",
    "rule 7 class 4: a response with unrelated correlation changes nothing",
function()
    -- Class 4 is requestId/hash CORRELATION rejection. MIX-05's corrupt body
    -- and foreign sender are a weaker adjacent property and are NOT class 4.
    for _, spec in ipairs({{name="new", root="."},
                           {name="old", root=H.MaterializeBaseTreeV1(C3_COMMIT)}}) do
        local receiver = H.IsolatedSideV1(spec.root, nil,
            {playerName="Correlate" .. spec.name})
        local before = receiver.nexus.Codec.JSONEncode(receiver.env.NexusDB)
        local channelBefore = receiver.nexus.Sync.ChannelName()
        -- A claim naming a request id this receiver never issued.
        local unrelated =
            "WLLC||Stranger||Correlate" .. spec.name
            .. "||c1-never-issued-0000||0,0,0,0,0,0,0,0"
        local wire = H.CaptureWireV1(receiver, function(s)
            return s.nexus.Sync.HandleIncoming(unrelated, "Stranger")
        end, 80)
        Check(receiver.nexus.Codec.JSONEncode(receiver.env.NexusDB) == before,
            spec.name .. ": an unrelated correlation mutated durable state")
        Check(#H.WireOfCodeV1(wire, "WLRB") == 0,
            spec.name .. ": an unrelated correlation drew a build relay")
        Check(receiver.nexus.Sync.ChannelName() == channelBefore,
            spec.name .. ": an unrelated correlation moved the channel")
    end
end)

Case("MIX-21",
    "rule 7 keys WLDS, WLD2 and WLNP: dispositions and real terminals",
function()
    local baseRoot = H.MaterializeBaseTreeV1(C3_COMMIT)

    -- WLDS: emitted by the public DPS broadcast on BOTH trees.
    for _, spec in ipairs({{name="new", root="."},
                           {name="old", root=baseRoot}}) do
        local side = H.IsolatedSideV1(spec.root, nil,
            {playerName="Dps" .. spec.name})
        local wire = H.CaptureWireV1(side, function(s)
            return s.nexus.Sync.BroadcastDps("dpskey", "Dps" .. spec.name,
                6000, 80, "dummy")
        end, 80)
        Check(#H.WireOfCodeV1(wire, "WLDS") == 1,
            spec.name .. ": BroadcastDps emitted "
                .. #H.WireOfCodeV1(wire, "WLDS") .. " WLDS, required 1 [window: "
                .. H.WireCodesV1(wire) .. "]")
        -- WLD2 is the exact-set chunked DPS code and is NOT produced by this
        -- entry. Recorded as measured rather than asserted absent by accident.
        Check(#H.WireOfCodeV1(wire, "WLD2") == 0,
            spec.name .. ": BroadcastDps unexpectedly emitted WLD2; its "
                .. "disposition here is 'not produced by this entry'")
    end

    -- WLNP: no public send entry exists. Asserted as a fact, not invented.
    local side = H.IsolatedSideV1(".", nil, {playerName="Presence"})
    local presenceEntries = {}
    for key, value in pairs(side.nexus.Sync) do
        if type(value) == "function"
            and tostring(key):lower():find("presence") then
            presenceEntries[#presenceEntries + 1] = tostring(key)
        end
    end
    Check(#presenceEntries == 0,
        "a public presence send entry now exists ("
            .. table.concat(presenceEntries, ",")
            .. "); WLNP's disposition must be re-measured")
    -- Its real terminal on the inbound side: non-durable, no relay, no channel
    -- movement.
    local before = side.nexus.Codec.JSONEncode(side.env.NexusDB)
    local channelBefore = side.nexus.Sync.ChannelName()
    local wire = H.CaptureWireV1(side, function(s)
        return s.nexus.Sync.HandleIncoming("WLNP||Peer||1.20.0-beta.1", "Peer")
    end, 60)
    Check(side.nexus.Codec.JSONEncode(side.env.NexusDB) == before,
        "an inbound presence message mutated durable state")
    Check(#H.WireOfCodeV1(wire, "WLRB") == 0,
        "an inbound presence message drew a build relay")
    Check(side.nexus.Sync.ChannelName() == channelBefore,
        "an inbound presence message moved the channel")
end)

-- ---------------------------------------------------------------------------
-- MASTER-RC-015: rule 7 class 5 (tombstone replacement failure, 4743), the
-- deferred 96-byte durable convergence, and WLD2's producer inventory.
--
-- The fault mechanism is the AUTHORIZED harness-only seam already in the tree:
-- `S.PoisonDurableField`, the same one ATOM-01..08 use in
-- tests/run_catalog_authority_commit_fault_matrix.lua. No new seam is
-- introduced and no production fault-injection API exists -- ATOM-01 asserts
-- `InstallFaultInjector` is not exported, and a grep of `core/` finds no
-- fault-injection surface at all.
--
-- MEASURED BEFORE WRITING:
--   * Under a poisoned bundle payload field, SetTombstone fails with
--     ROOT_INVALIDATED, the durable bytes are unchanged, and the bundle pointer
--     is unchanged. That is 4743's PRE-COMMIT terminal.
--   * With no fault, the same tombstone replaces once, the row goes, the state
--     is CURRENT_DENY, and an exact replay leaves durable bytes unchanged.
--   * The durable snapshot must be taken AFTER poisoning: the poison is itself
--     a durable byte change, so a pre-poison snapshot cannot isolate what the
--     failed commit did.

local c5Sequence = 0
local function C5Name()
    c5Sequence = c5Sequence + 1
    return "t5x" .. c5Sequence
end

Case("MIX-22",
    "rule 7 class 5: a pre-commit fault leaves bundle and serving root exact",
function()
    local id = C5Name()
    local db = S.Database({[id]=S.LocalBuild(id, 3)})
    S.Bind(db)
    local catalog = Catalog()
    Check(catalog.RootState().state == "ROOT_ADMITTED",
        "fixture did not admit a root")

    local bundleBefore = rawget(db, "authorityBundle")
    local restore = S.PoisonDurableField(db, "communityBuilds", "not-a-map")
    -- Snapshot AFTER poisoning, so the poison is not counted as the failure's
    -- own mutation.
    local beforeJson = S.Encode(db)
    local ok, why = catalog.SetTombstone(id,
        {stamp=50, author="Boganic", ownerKey="boganic@ebonhold",
         ownerVerified=true}, {source="local"})

    Check(ok == false,
        "a tombstone replacement under a pre-commit fault reported success")
    Check(S.Encode(db) == beforeJson,
        "a failed tombstone replacement changed durable bytes ("
            .. tostring(why) .. ")")
    Check(rawget(db, "authorityBundle") == bundleBefore,
        "a failed tombstone replacement replaced the durable bundle pointer")
    -- No false success relay: the refusal is a named terminal, not silence.
    Check(why ~= nil and why ~= "",
        "the failure reported no terminal reason")
    restore()
end)

Case("MIX-23",
    "GUARD: with no fault the same tombstone replaces exactly once",
function()
    -- Both-sides guard for MIX-22: passes before and after, so the refusal
    -- above cannot be a blanket refusal of tombstone replacement.
    local id = C5Name()
    local db = S.Database({[id]=S.LocalBuild(id, 3)})
    S.Bind(db)
    local catalog = Catalog()
    local tomb = {stamp=50, author="Boganic", ownerKey="boganic@ebonhold",
        ownerVerified=true}
    -- The row-to-tombstone transaction is one retained catalog mutation
    -- (MASTER-RC-006); its terminal commit is the acceptance evidence.
    local ok, why, ticket = catalog.SetTombstone(id, tomb, {source="local"})
    if ok == nil and why == "ROOT_MUTATION_PENDING" then
        S.PumpCatalogToIdle("clean tombstone replacement")
        ok = type(ticket) == "table" and ticket.committed == true
    end
    Check(ok == true, "a clean tombstone replacement was refused")
    Check(catalog.Get(id) == nil, "the row survived its tombstone")
    Check(tostring((catalog.TombstoneState(id) or {}).state) == "CURRENT_DENY",
        "the tombstone did not reach CURRENT_DENY")
    -- Replays once: the same tombstone again changes no durable byte.
    local settled = S.Encode(db)
    catalog.SetTombstone(id, tomb, {source="local"})
    S.PumpCatalogToIdle("replayed tombstone")
    Check(S.Encode(db) == settled,
        "replaying the same tombstone re-applied the mutation")
end)

Case("MIX-24",
    "rule 7 class 8 closed: a 96-byte id converges once through the real path",
function()
    -- Deferred from MIX-11 because it needed the chunked drive; the drive
    -- exists now, so this closes it with MIX-14's trace.
    local exact = string.rep("e", 96)
    local sender = H.IsolatedSideV1(".", nil, {playerName="Wide"})
    local record = {
        id=exact, title="Wide id", author="Wide",
        ownerKey="wide@ebonhold", realm="ebonhold", ownerVerified=true,
        isMine=true, class="MAGE", postedAt=10, lastModified=10,
        echoes={{spellId=340001, quality=3, stacks=1},
                {spellId=340002, quality=3, stacks=1}},
    }
    local wire = H.CaptureWireV1(sender, function(s)
        PutSide(s, record, {source="local"})
        return s.nexus.Sync.BroadcastBuild(record)
    end, 90)
    local chunks = H.WireOfCodeV1(wire, "WLRB")
    Check(#chunks > 0,
        "a 96-byte id emitted no chunks [window: " .. H.WireCodesV1(wire) .. "]")
    if #chunks == 0 then return end
    local receiver = H.IsolatedSideV1(".", nil, {playerName="WideRecv"})
    local got = ReplaySide(receiver, chunks, "Wide", 80)
    Check(got.Durable(exact) ~= nil,
        "a 96-byte id did not converge across " .. #chunks .. " chunk(s)")
    local settled = got.after
    local again = ReplaySide(receiver, chunks, "Wide", 60)
    Check(again.after == settled,
        "an exact replay of a 96-byte id mutated durable state a second time")
end)

Case("MIX-25",
    "rule 7 class 10: WLD2's producer named by inventory",
function()
    -- Found by inventory rather than guess. Every WLD2 construction site in
    -- core/ is inside one public operation, and the frozen parent has the same
    -- shape at its own line numbers.
    local handle = assert(io.open("core/Sync.lua", "rb"))
    local source = handle:read("*a")
    handle:close()
    local sites, lineNo, enclosing, producer = 0, 0, nil, nil
    for line in (source .. "\n"):gmatch("(.-)\r?\n") do
        lineNo = lineNo + 1
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed:find("^function Sync%.") or trimmed:find("^local function ") then
            enclosing = trimmed:match("^function (Sync%.[%w_]+)")
                or trimmed:match("^local function ([%w_]+)")
        end
        if not trimmed:find("^%-%-") and trimmed:find("CODE_DPS2")
            and (trimmed:find("format") or trimmed:find('%.%.')) then
            sites = sites + 1
            producer = producer or enclosing
        end
    end
    Check(sites > 0,
        "no WLD2 construction site found in core/Sync.lua; the inventory "
            .. "must be re-taken")
    Check(producer == "Sync.BroadcastDpsRecord",
        "WLD2's enclosing producer is " .. tostring(producer)
            .. ", expected Sync.BroadcastDpsRecord")
    -- It is a public operation, so WLD2 has a named producer rather than the
    -- "no public send entry" disposition WLNP carries.
    Check(type(Sync.BroadcastDpsRecord) == "function",
        "Sync.BroadcastDpsRecord is not a public entry")
end)
Check(#S.results > 0, "no selected Sync test case executed")
S.Finish("sync semantic envelope and protocol-7 identity matrix")
