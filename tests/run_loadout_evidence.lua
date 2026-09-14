-- Canonical exact-loadout evidence: additive storage, defensive reads, and
-- established build/DPS wire materialization.
local H = dofile("tests/harness.lua")
local S = dofile("tests/catalog_authority_support.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
dofile("core/DpsCapture.lua")

local Evidence = Nexus.LoadoutEvidence
local Catalog = Nexus.BuildCatalog
local Revisions = Nexus.Revisions
local Sync, DPS, Codec = Nexus.Sync, Nexus.DpsCapture, Nexus.Codec
local clock, currentName = 1000, "Localhero"
GetTime = function() return clock end
time = function() return 50000 end
UnitName = function() return currentName end
UnitClass = function() return "Mage", "MAGE" end
UnitLevel = function() return 80 end
GetNormalizedRealmName = function() return "Ebonhold" end

local baseline = {
    id="release-only", title="Release", author="Release", class="MAGE",
    postedAt=1, lastModified=1,
    echoes={{spellId=200090,quality=3,stacks=1}},
}
local baselineEchoes = baseline.echoes
Nexus.BundledBuilds = {
    schemaVersion=1, catalogVersion="evidence-test", sourceVersion="test",
    builds={[baseline.id]=baseline},
}
NexusDB = {communityBuilds={}, syncTombstones={}, dpsCapture={}}
Evidence.Init(NexusDB)
H.AdmitCatalogV1(NexusDB, Nexus.BundledBuilds)
local function AwaitMutation(ok, why, ticket)
    return S.AwaitCatalogMutation(ok, why, ticket,
        "loadout-evidence catalog mutation", 200000)
end

local sameA = {
    {spellId=200101,quality=3,stacks=1},
    {spellId=200100,quality=3,stacks=1},
    {spellId=200100,quality=3,stacks=1},
}
local sameB = {
    {spellId=200100,quality=3,stacks=2},
    {spellId=200101,quality=3,stacks=1},
}
local keyA, normalizedA, createdA = Evidence.Intern(sameA)
local keyB, normalizedB, createdB = Evidence.Intern(sameB)
assert(keyA and keyA == keyB and createdA and not createdB,
    "equal canonical loadouts did not share one pool entry")
assert(#normalizedA == 2 and #normalizedB == 2
    and Evidence.Stats().entries == 1,
    "canonical duplicate rows were not merged deterministically")

local lockedKey = Evidence.Intern({
    {spellId=200100,quality=3,stacks=2,locked=true},
    {spellId=200101,quality=3,stacks=1},
})
assert(lockedKey and lockedKey ~= keyA and Evidence.Stats().entries == 2,
    "locked and ordinary exact evidence merged")
local legacyLockedKey = Evidence.Intern({
    {spellId=200100,quality=3,stacks=2,locked=1},
    {spellId=200101,quality=3,stacks=1},
})
assert(legacyLockedKey == lockedKey,
    "legacy truthy locked evidence canonicalized as ordinary")
H.RebindCatalog(NexusDB, Nexus.BundledBuilds)

local beforeBuildRevision = Revisions.Get(Revisions.BUILD_LIBRARY_CHANGED)
assert(AwaitMutation(Catalog.Put({
    id="short-a", title="Short A", author="Peer", class="MAGE",
    ownerKey="peer@ebonhold", ownerVerified=true,
    postedAt=10, lastModified=10, fingerprintHash="deadbeef", echoes=sameA,
})))
assert(Revisions.Get(Revisions.BUILD_LIBRARY_CHANGED) == beforeBuildRevision + 1,
    "one evidence-backed build write did not retain one build revision")
assert(AwaitMutation(Catalog.Put({
    id="short-b", title="Short B", author="Peer", class="MAGE",
    postedAt=11, lastModified=11, fingerprintHash="deadbeef",
    echoes={{spellId=200102,quality=3,stacks=1}},
})))
-- Legacy-to-bundle cutover (architecture 3b5de54f state machine lines 374,
-- 394, 4849): the durable authority payload is `authorityBundle`; the exact
-- PR #68 locations are read-only preserved bootstrap input.
local rawA, rawB = H.DurableBuilds()["short-a"],
    H.DurableBuilds()["short-b"]
assert(rawA.evidenceKey == keyA and rawB.evidenceKey ~= keyA
    and rawB.evidenceKey ~= rawA.evidenceKey,
    "a short-hash collision merged distinct full evidence")
assert(rawA.echoes and rawB.echoes,
    "the additive stage removed established inline evidence")
assert(baseline.echoes == baselineEchoes and baseline.evidenceKey == nil,
    "overlay evidence integration mutated the bundled baseline")

local claimed = {
    echoes={{spellId=200103,quality=3,stacks=1}}, evidenceKey=keyA,
}
local correctedClaim = Evidence.Reference(claimed)
assert(correctedClaim and correctedClaim ~= keyA
    and #Evidence.Conflicts() >= 1,
    "a colliding claimed reference was trusted or went unreported")
local entriesBeforeMalformed = Evidence.Stats().entries
assert(not Evidence.Intern({[2]={spellId=200104,stacks=1}})
    and not Evidence.Intern({{spellId=0,stacks=1}})
    and Evidence.Stats().entries == entriesBeforeMalformed,
    "malformed evidence entered the pool")
H.RebindCatalog(NexusDB, Nexus.BundledBuilds)

-- Public reads serve the admitted canonical evidence record (one unique
-- sorted tuple order with grouped stacks) and are defensive. A synthetic
-- pool-only row then proves offline hydration without a network request.
local inlineCopy = Catalog.Get("short-a")
assert(#inlineCopy.echoes == 2 and inlineCopy.echoes[1].spellId == 200100
    and inlineCopy.echoes[1].stacks == 2
    and inlineCopy.echoes[2].spellId == 200101,
    "public read did not serve the canonical evidence record")
inlineCopy.echoes[1].stacks = 99
assert(Catalog.Get("short-a").echoes[1].stacks == 2,
    "a public build copy mutated SavedVariables")
rawA.echoes = nil
local pooledBuild = Catalog.Get("short-a")
assert(pooledBuild and #pooledBuild.echoes == 2
    and pooledBuild.echoes[1].spellId == 200100
    and pooledBuild.echoes[1].stacks == 2,
    "a pool-only build was not independently exact offline")
pooledBuild.echoes[1].stacks = 77
assert(Catalog.Get("short-a").echoes[1].stacks == 2,
    "a pooled public build copy mutated canonical evidence")

-- Module reload binds the same SavedVariables pool and resolves the same key.
dofile("core/LoadoutEvidence.lua")
Evidence = Nexus.LoadoutEvidence
Evidence.Init(NexusDB)
local afterReload = Evidence.Resolve(keyA)
assert(afterReload and #afterReload == 2
    and afterReload[1].spellId == 200100,
    "evidence did not survive a module reload")

-- Future schemas remain readable but cannot be modified, and an externally
-- corrupted full-key entry is conflict-preserving rather than overwritten.
local primaryDb = NexusDB
local futureDb = {loadoutEvidence={
    schemaVersion=99, entries={[keyA]=Evidence.Snapshot()[keyA]},
}}
NexusDB = futureDb
Evidence.Init(NexusDB)
assert(Evidence.Resolve(keyA)
    and not Evidence.Intern({{spellId=200150,stacks=1}})
    and next(futureDb.loadoutEvidence.entries, keyA) == nil,
    "future evidence schema was unreadable or writable")
local opaqueFutureDb = {loadoutEvidence={
    schemaVersion=100, entries="future-owned", marker={keep=true},
}}
NexusDB = opaqueFutureDb
local opaqueStats = Evidence.Init(NexusDB)
local unresolved = Evidence.Resolve("future-owned-key")
local opaqueGc = Evidence.CollectGarbage(NexusDB)
assert(opaqueStats.readOnly and not unresolved and opaqueGc.blocked
    and opaqueFutureDb.loadoutEvidence.entries == "future-owned"
    and opaqueFutureDb.loadoutEvidence.marker.keep == true,
    "opaque future evidence schema was mutated or assumed to be schema 1")
local corruptDb = {loadoutEvidence={schemaVersion=1, entries={
    [keyA]={{spellId=200999,quality=3,stacks=1}},
}}}
NexusDB = corruptDb
Evidence.Init(NexusDB)
assert(not Evidence.Intern(sameA)
    and corruptDb.loadoutEvidence.entries[keyA][1].spellId == 200999,
    "corrupt full-key evidence was overwritten")
NexusDB = primaryDb
Evidence.Init(NexusDB)
H.RebindCatalog(NexusDB, Nexus.BundledBuilds)

local function Pump(seconds)
    for _ = 1, math.ceil(seconds / 0.2) do
        clock = clock + 0.2
        Sync.OnUpdate(0.2)
    end
end

local function Parts(text)
    text = tostring(text or ""):gsub("||", "|")
    local out = {}
    for part in text:gmatch("([^|]*)|?") do
        out[#out + 1] = part
        if #out > 12 then break end
    end
    return out
end

local function DecodeChunks(messages, code, indexField, dataField)
    local chunks, total = {}, nil
    for _, message in ipairs(messages) do
        local parts = Parts(message.text)
        if parts[1] == code then
            local index, count = tostring(parts[indexField]):match("^(%d+)/(%d+)$")
            index, count = tonumber(index), tonumber(count)
            total = total or count
            chunks[index] = parts[dataField]
        end
        assert(#message.text <= 255, "evidence wire packet exceeded 255 bytes")
    end
    assert(total and total > 0, "no " .. code .. " payload was sent")
    local joined = {}
    for index = 1, total do
        assert(chunks[index], "missing " .. code .. " chunk")
        joined[#joined + 1] = chunks[index]
    end
    return Codec.JSONDecode(Codec.Base64Decode(table.concat(joined)))
end

Sync.Init(Codec, {})
H.RebindCatalog(NexusDB, Nexus.BundledBuilds)
H.sentChatMessages = {}
local shortForWire = Catalog.Get("short-a")
local buildBroadcast, buildBroadcastWhy = Sync.BroadcastBuild(
    shortForWire)
assert(buildBroadcast,
    "pool-only build could not enter the established wire path: "
        .. tostring(buildBroadcastWhy) .. " row=" .. tostring(shortForWire)
        .. " echoes=" .. tostring(shortForWire and shortForWire.echoes)
        .. " root=" .. tostring(Catalog.RootState().state) .. "/"
        .. tostring(Catalog.RootState().reason))
Pump(10)
local buildPayload = DecodeChunks(H.sentChatMessages, "WLRB", 5, 6)
assert(type(buildPayload.e) == "table" and #buildPayload.e == 2
    and buildPayload.e[1][1] == 200100 and buildPayload.e[1][3] == 2,
    "build wire lost pooled exact Echo evidence")
H.sentChatMessages = {}
assert(Sync.BroadcastBuild({
    id="reference-only", title="Reference-owned", author="Localhero", class="MAGE",
    ownerKey="localhero@ebonhold", ownerVerified=true,
    postedAt=12, lastModified=12, evidenceKey=rawB.evidenceKey,
}), "reference-only build could not enter the wire path")
Pump(10)
local collisionPayload = DecodeChunks(H.sentChatMessages, "WLRB", 5, 6)
assert(#collisionPayload.e == 1 and collisionPayload.e[1][1] == 200102,
    "catalog fallback replaced reference-owned exact build evidence")

-- A public DPS row remains viewable without its claimed catalog page. Its
-- stored inline array can also be removed synthetically and hydrated from the
-- pool for board, detail, and defensive-copy access.
Nexus.CommunityBuilds = nil
DPS.Init({}, Sync)
local remoteEchoes = {
    {spellId=200200,stacks=2}, {spellId=200201,stacks=1},
}
local remoteFingerprint = DPS.GetEchoKey(remoteEchoes)
local beforeDpsRevision = Revisions.Get(Revisions.DPS_CHANGED)
assert(DPS.ReceiveRecord({
    v=7, f=remoteFingerprint, h=DPS.GetEchoHash(remoteEchoes), e=remoteEchoes,
    c="dummy", d=25000000, u=65, t=49000, p="Peer", k="MAGE",
    o="peer@ebonhold", r="ebonhold", l=80, b="missing-page",
}, "Peer-Ebonhold"))
assert(Revisions.Get(Revisions.DPS_CHANGED) == beforeDpsRevision + 1,
    "one evidence-backed DPS winner did not retain one DPS revision")
local storedRow = H.DurablePayload("dpsCapture").characterBest.dummy["peer@ebonhold"]
assert(storedRow.evidenceKey and not Catalog.Get("missing-page"),
    "missing-page DPS fixture unexpectedly gained a catalog row")
-- MASTER-W2-011: a DPS row written outside a catalog candidate binds only its
-- self-verifying key and keeps its inline bytes; the pool entry is written
-- later inside a compaction transaction. Seed that exact pool entry here as
-- durable input before the complete readmission below, so the pool-only row
-- oracle keeps its meaning without a raw write behind an admitted root.
assert(Evidence.Intern(storedRow.echoes) == storedRow.evidenceKey,
    "fixture could not seed the exact pool entry for the DPS winner")
storedRow.echoes = nil
local collisionEchoes = {{spellId=200299,quality=3,stacks=1}}
H.RebindCatalog(NexusDB, Nexus.BundledBuilds)
assert(AwaitMutation(Catalog.Put({
    id="missing-page", title="Colliding page", author="Other", class="MAGE",
    postedAt=20, lastModified=20, echoes=collisionEchoes,
    fingerprint=DPS.GetEchoKey(collisionEchoes),
})))
local board = DPS.GetDpsBoard("dummy")
assert(#board == 1 and board[1].player == "Peer"
    and #board[1].echoes == 2 and board[1].build == nil,
    "DPS board hid exact evidence or attached an ID-colliding page")
board[1].echoes[1].count = 99
assert(DPS.GetCharacterBest("dummy", "Peer").echoes[1].count == 2,
    "a public DPS copy mutated pooled evidence")

-- Outgoing DPS materialization preserves the established exact list and the
-- separately locked evidence, even when the source row contains references
-- only. Direct pool writes own no data revision.
local localEchoes = {
    {spellId=200300,stacks=2}, {spellId=200301,stacks=1},
}
local localLocked = {{spellId=200399,stacks=1}}
local localFingerprint = DPS.GetEchoKey(localEchoes)
local localRow = {
    protocolVersion=7, fingerprint=localFingerprint,
    loadoutHash=DPS.GetEchoHash(localEchoes), echoes=localEchoes,
    lockedEchoes=localLocked, category="dummy", dps=26000000,
    duration=66, ts=49001, player="Localhero", class="MAGE",
    ownerKey="localhero@ebonhold", realm="ebonhold", ownerVerified=true,
    level=80,
    buildId="missing-local-page",
}
local buildRevision = Revisions.Get(Revisions.BUILD_LIBRARY_CHANGED)
local dpsRevision = Revisions.Get(Revisions.DPS_CHANGED)
assert(Evidence.ReferenceDpsRow(localRow)
    and Revisions.Get(Revisions.BUILD_LIBRARY_CHANGED) == buildRevision
    and Revisions.Get(Revisions.DPS_CHANGED) == dpsRevision,
    "the evidence pool advanced a revision outside its originating mutation")
localRow.echoes, localRow.lockedEchoes = nil, nil
H.sentChatMessages = {}
assert(Sync.BroadcastDpsRecord(localRow),
    "reference-only DPS evidence could not enter the established wire path")
Pump(12)
local dpsPayload = DecodeChunks(H.sentChatMessages, "WLD2", 4, 5)
assert(type(dpsPayload.e) == "table" and #dpsPayload.e == 2
    and dpsPayload.e[1].spellId == 200300 and dpsPayload.e[1].count == 2
    and type(dpsPayload.lk) == "table" and #dpsPayload.lk == 1
    and dpsPayload.lk[1].spellId == 200399,
    "DPS wire lost pooled ordinary or locked exact evidence")

assert(Evidence.Stats().entries >= 7,
    "evidence cardinality did not retain all distinct canonical loadouts")

-- EVD-OFFSTATE: the durable evidence payload after the accepted legacy-to-bundle
-- cutover (MASTER-RC-001, architecture 3b5de54f). State machine line 394 gives
-- the exact PR #68 `loadoutEvidence` location "No Package B writer | Legacy
-- admission only | Preserved legacy input when the bundle is absent. Never used
-- as fallback after bundle occupancy", and RAW-01 (line 4849) makes one
-- complete `authorityBundle` pointer the sole durable payload write.
--
-- A malformed legacy input therefore may not be repaired in place, because that
-- is a write to a preserved legacy input. It is repaired off-state instead, and
-- the repaired store must be stable: rebuilding it on every read would silently
-- discard every intern staged since the previous read.
do
    local malformedDb = {loadoutEvidence={schemaVersion=1, entries="malformed"}}
    local legacyStore = malformedDb.loadoutEvidence
    local legacyEntries = legacyStore.entries
    local priorDb = NexusDB
    NexusDB = malformedDb
    Evidence.Init(malformedDb)
    local firstKey = Evidence.Intern({{spellId=200500,quality=3,stacks=1}})
    local secondKey = Evidence.Intern({{spellId=200501,quality=3,stacks=1}})
    local durable = Evidence.DurableStore(malformedDb)
    local staged = 0
    for _ in pairs(type(durable) == "table"
        and type(durable.entries) == "table" and durable.entries or {}) do
        staged = staged + 1
    end
    assert(firstKey and secondKey and staged == 2,
        "off-state evidence repair discarded an intern between reads")
    assert(Evidence.DurableStore(malformedDb) == durable,
        "off-state evidence repair rebuilt its store on every read")
    assert(rawget(malformedDb, "loadoutEvidence") == legacyStore
        and legacyStore.entries == legacyEntries
        and legacyStore.entries == "malformed"
        and rawget(malformedDb, "authorityBundle") == nil,
        "malformed legacy evidence input was repaired in place or replaced")
    NexusDB = priorDb
    Evidence.Init(priorDb)
end

print("canonical loadout evidence pooling and exact offline/wire reads -- OK")
