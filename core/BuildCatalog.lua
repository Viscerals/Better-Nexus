-- Nexus: merged view of the immutable release catalog and SavedVariables
-- community-build overlay under one complete admission verdict.
--
-- Package B catalog authority (issue #22). One completed admission verdict is
-- the only source of catalog authority: raw durable evidence, the bounded
-- canonical snapshot, and public authority are three different things. Every
-- public read copies from the published root; every mutation is one prepared
-- transaction that publishes one new root generation; raw storage is never
-- mutated before a complete candidate commits.

Nexus = Nexus or {}
local Identity = assert(Nexus.Identity,
    "Nexus Identity must load before BuildCatalog")
local Catalog = {}
Nexus.BuildCatalog = Catalog

local STORAGE_SCHEMA_VERSION = 1
local TOMBSTONE_SCHEMA_VERSION = 1
local BARRIER_SCHEMA_VERSION = 1
local TOMBSTONE_AGE = 180 * 24 * 60 * 60
local BARRIER_AGE = 30 * 24 * 60 * 60
local MAX_SAFE_INTEGER = 9007199254740991

-- CATALOG_AUTHORITY_BUDGET_V1: complete-root totals.
local BUDGET = {
    rows=2048, rootMapKeys=2048, rootMapEdges=8192,
    bytesInspected=67108864, nodes=4096000, edges=33554432,
    evidenceRows=524288, stacks=20480000, aliasProbes=57344,
    tableIdentities=4096000, unknownBytes=8388608, rootKeyBytes=2146304,
    keyWidth=256, tombstones=2048, tombstoneEdges=131072,
    tombstoneBytes=8388608, barriers=2048, barrierEdges=131072,
    barrierNodes=133120, barrierBytes=67108864,
    indexMemberships=172032, indexEdges=1386496, indexNodes=1562634,
    indexBytes=61009920, cursorMetadata=326024,
    evidenceRowsPerRecord=256, stacksPerRecord=10000,
    ordinaryCopies=79, lockedCopies=6, totalCopies=85,
    objectKeys=64, denseEntries=256, nestedNodes=2000, depth=6,
    aliasForms=28, recordBytes=32768, unknownBytesPerRow=4096,
    unknownTables=16, tombstoneTables=16, tombstoneEntries=64,
    tombstoneDepth=8, tombstoneStringBytes=4096, compactionUnits=32,
    activeCandidates=1, cursorsPerFamily=1, oneCallRows=8,
    oneCallBytes=32768, oneCallNodes=2000,
}

-- Per-pump frontier slices. A pump stops at the first exhausted slice.
local SLICE = {
    rows=8, rootMapEdges=64, edges=64, nodes=64, evidenceRows=16, stacks=16,
    aliasProbes=8, bytesInspected=2048, unknownBytes=512, tableIdentities=8,
    tombstoneEdges=16, tombstoneBytes=1024, barriers=8, barrierEdges=64,
    barrierNodes=64, barrierBytes=2048, sortComparisons=64, sortBytes=2048,
    compactionUnits=32, indexEdges=64, indexNodes=64, indexBytes=2048,
    cursorMetadata=64, claimFields=8,
}

local COUNTER_KEYS = {
    "rows", "rootMapEdges", "edges", "nodes", "evidenceRows", "stacks",
    "aliasProbes", "bytesInspected", "unknownBytes", "tableIdentities",
    "tombstoneEdges", "tombstoneBytes", "barriers", "barrierEdges",
    "barrierNodes", "barrierBytes", "sortComparisons", "sortBytes",
    "compactionUnits", "indexEdges", "indexNodes", "indexBytes",
    "cursorMetadata", "claimFields",
}

-- CatalogSchemaV1 known top-level fields: architecture list plus the exact
-- PR #68 consumer-evidenced fields read by Community, Sync, DPS, Wishlist,
-- Leaderboard, and diagnostics owners. Every other key is unknown under V1.
local FIELD = {
    id={kind="id"},
    title={kind="string", max=1024}, serverTitle={kind="string", max=1024},
    description={kind="string", max=4000, multiline=true},
    author={kind="string", max=80}, player={kind="string", max=80},
    ownerKey={kind="string", max=177}, claimedOwnerKey={kind="string", max=177},
    relaySender={kind="string", max=80}, realm={kind="string", max=96},
    class={kind="string", max=32}, link={kind="string", max=2048},
    fingerprint={kind="string", max=4096}, fingerprintHash={kind="string", max=64},
    loadoutHash={kind="string", max=64}, evidenceKey={kind="string", max=6996},
    lockedEvidenceKey={kind="string", max=6996},
    destinationWishlistName={kind="string", max=1024},
    _savedSignature={kind="string", max=4096},
    postedAt={kind="integer", min=0}, lastModified={kind="integer", min=0},
    echoCount={kind="integer", min=0}, serverSlot={kind="integer", min=0},
    destinationProgress={kind="integer", min=0},
    destinationTotal={kind="integer", min=0},
    schemaVersion={kind="integer", min=0}, protocolVersion={kind="integer", min=0},
    autoDps={kind="boolean"}, ownerVerified={kind="boolean"},
    isMine={kind="boolean"}, importedSavedBuild={kind="boolean"},
    loadoutAvailable={kind="boolean"}, needsFullBuild={kind="boolean"},
    activeServerBuild={kind="boolean"}, legacyRecovered={kind="boolean"},
    lockedAuthorityProven={kind="boolean"},
    legacySource={kind="string", max=64}, legacyOwnership={kind="string", max=64},
    lockedFingerprint={kind="string", max=4096},
    lockedEvidenceSource={kind="string", max=64},
    userTitle={kind="string", max=1024},
    buildId={kind="id"}, recordBuildId={kind="id"}, publishedBuildId={kind="id"},
    sourceSavedBuildId={kind="id"},
    sourceIdentity={kind="string", max=256}, provenanceIdentity={kind="string", max=256},
    echoes={kind="evidence", locked=false}, lockedEchoes={kind="evidence", locked=true},
}

-- Fixed compact/verbose alias table (source key -> canonical field).
local ALIAS = {
    t="title", a="author", o="ownerKey", c="class", m="lastModified",
    d="description", e="echoes", x="autoDps", lk="link", p="player", r="realm",
}
local ECHO_ALIAS = {
    spellId="spellId", id="spellId", quality="quality", stacks="stacks",
    count="stacks", stack="stacks", locked="locked",
}

local SUMMARY_FIELDS = {
    "id", "title", "serverTitle", "description", "author", "player",
    "ownerKey", "realm", "class", "postedAt", "lastModified",
    "importedSavedBuild", "isMine", "destinationWishlistName",
    "destinationProgress", "destinationTotal", "recordBuildId",
    "publishedBuildId", "sourceSavedBuildId", "autoDps", "fingerprint",
    "fingerprintHash", "needsFullBuild", "ownerVerified", "claimedOwnerKey",
    "relaySender", "serverSlot", "activeServerBuild", "legacyRecovered",
    "linkHash", "evidenceKey", "lockedAuthorityProven",
}

local VALID_CLASS = {
    WARRIOR=true,PALADIN=true,HUNTER=true,ROGUE=true,PRIEST=true,
    DEATHKNIGHT=true,SHAMAN=true,MAGE=true,WARLOCK=true,DRUID=true,
}

local TOMBSTONE_V1_FIELDS = {
    schemaVersion=true, typedId=true, ownerKey=true, sourceKind=true,
    sourceIdentity=true, targetRowGeneration=true, targetRowProvenance=true,
    receiptRevision=true, receiptAtServerTime=true, remoteStampEvidence=true,
}
local BARRIER_V1_FIELDS = {
    schemaVersion=true, typedId=true, evictedCatalogGeneration=true,
    evictedSourceIdentity=true, evictedProvenanceIdentity=true,
    receiptRevision=true, receiptAtServerTime=true,
}

------------------------------------------------------------------------
-- Module state (one table keeps every closure inside the Lua 5.1 upvalue
-- limit). Nothing here is ever stored in SavedVariables.
------------------------------------------------------------------------

local ST = {
    db=nil, bundled=nil, baseline=nil,
    rootState="ROOT_UNBOUND", rootReason=nil,
    published=nil, candidate=nil, futureToken=nil,
    bindingGeneration=0, committedMutationRevision=0, preparationEpoch=0,
    reservationEpoch=0, semanticGeneration=0, generation=0,
    sessionTombstones=setmetatable({}, {__mode="k"}),
    sessionBarriers=setmetatable({}, {__mode="k"}),
    readmittedBarriers=setmetatable({}, {__mode="k"}),
    claimRegistry=setmetatable({}, {__mode="k"}), activeClaim=nil,
    cursorRegistry=setmetatable({}, {__mode="k"}), activeCursors={},
    cursorSequence=0,
    maintenanceRegistry=setmetatable({}, {__mode="k"}), activeMaintenance=nil,
    faultInjector=nil,
    recordEpoch=0, exactEpoch=0, exactRevisionClock=0,
    recordRevisions={}, exactRevisions={},
    trustedHigh=nil, trustedUntrusted=false,
    receiptRevision=0, lastInitSummary=nil,
    counters=nil, lastCounters=nil,
    debugStats={
        initCalls=0, rebinds=0, fastPathHits=0, revisionSnapshots=0,
        authorIndexRebuilds=0, summarySnapshots=0, relatedIndexRebuilds=0,
        relatedLookups=0, relatedCandidates=0, maxRelatedCandidates=0,
        putCalls=0, putChanges=0, compactionCalls=0, compactionWrites=0,
        referenceCalls=0, referenceStores=0, relatedIndexUpdates=0,
        savedMirrorEnumerations=0, savedMirrorRows=0,
        exactLookups=0, exactCandidates=0, maxExactCandidates=0,
        identityResolutions=0, identityResolutionFailures=0,
        identityRawHits=0, identityFingerprintHits=0,
        ownerClassLookups=0, ownerClassHits=0, ownerClassConflicts=0,
        rootAdmissions=0, rootPumps=0, commits=0, protectedFailures=0,
        notificationFailures=0, maintenanceCommits=0, claimsIssued=0,
        cursorsBegun=0, driftInvalidations=0,
    },
}

------------------------------------------------------------------------
-- Generic helpers
------------------------------------------------------------------------

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[DeepCopy(key, seen)] = DeepCopy(child, seen)
    end
    return out
end

local function DeepEqual(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    seen = seen or {}
    if seen[left] then return seen[left] == right end
    seen[left] = right
    for key, value in pairs(left) do
        if not DeepEqual(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function Count(source)
    local n = 0
    for _ in pairs(source or {}) do n = n + 1 end
    return n
end

local function HashText(text)
    if type(text) ~= "string" or text == "" then return nil end
    local hash = 5381
    for i = 1, #text do
        hash = ((hash * 33) + text:byte(i)) % 2147483648
    end
    return string.format("%x", hash)
end

local function FiniteInteger(value, minimum, maximum)
    if type(value) ~= "number" or value ~= value or value >= math.huge
        or value <= -math.huge or value ~= math.floor(value) then return nil end
    if minimum and value < minimum then return nil end
    if maximum and value > maximum then return nil end
    return value
end

local function ScalarBytes(value)
    local kind = type(value)
    if kind == "string" then return #value + 1 end
    if kind == "number" then return 9 end
    if kind == "boolean" then return 2 end
    return 1
end

-- Collision-free typed identity: numeric 1 and string "1" occupy different
-- local slots through every index, cursor, snapshot, and reload.
local function TypedKey(id)
    local kind = type(id)
    if kind == "number" then
        if not FiniteInteger(id, 1, 2147483647) then
            return nil, "INVALID_TYPED_ID"
        end
        return "n:" .. string.format("%d", id), "number"
    elseif kind == "string" then
        if #id < 1 or #id > BUDGET.keyWidth or id:find("[%c]") then
            return nil, "INVALID_TYPED_ID"
        end
        return "s:" .. #id .. ":" .. id, "string"
    end
    return nil, "INVALID_TYPED_ID"
end

local function CompareSlots(left, right)
    if left.kind ~= right.kind then
        return left.kind == "number" and -1 or 1, 2
    end
    if left.kind == "number" then
        if left.id == right.id then return 0, 18 end
        return left.id < right.id and -1 or 1, 18
    end
    local a, b = left.id, right.id
    local bytes = math.min(#a, #b) + 1
    if a == b then return 0, bytes end
    return a < b and -1 or 1, bytes
end

local function CompareStrings(left, right)
    if left == right then return 0, #left + 1 end
    return left < right and -1 or 1, math.min(#left, #right) + 1
end

local function CompareTuples(left, right)
    local bytes = 30
    if left.spellId ~= right.spellId then
        return left.spellId < right.spellId and -1 or 1, bytes
    end
    if left.quality ~= right.quality then
        return left.quality < right.quality and -1 or 1, bytes
    end
    local leftLocked, rightLocked = left.locked and true or false,
        right.locked and true or false
    if leftLocked ~= rightLocked then
        return leftLocked and 1 or -1, bytes
    end
    local leftOrigin = left.origin == "lockedArray" and 1 or 0
    local rightOrigin = right.origin == "lockedArray" and 1 or 0
    if leftOrigin ~= rightOrigin then
        return leftOrigin < rightOrigin and -1 or 1, bytes
    end
    return 0, bytes
end

local function TrustedServerTime()
    if ST.trustedUntrusted or type(time) ~= "function" then return nil end
    local ok, value = pcall(time)
    value = ok and FiniteInteger(value, 1, MAX_SAFE_INTEGER) or nil
    if not value then return nil end
    if ST.trustedHigh and value < ST.trustedHigh then
        ST.trustedUntrusted = true
        return nil
    end
    ST.trustedHigh = value
    return value
end

local function CurrentOwnerKey()
    local name = UnitName and UnitName("player") or nil
    if not name or name == "" or name == "Unknown" then return nil end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then realm = GetRealmName and GetRealmName() end
    realm = tostring(realm or ""):gsub("%s+", "")
    if realm == "" or realm:lower() == "unknown" then return nil end
    local ownerKey = Identity.OwnerKey(name, realm)
    if not ownerKey or ownerKey:match("@unknown$") then return nil end
    return ownerKey
end

------------------------------------------------------------------------
-- Budget accounting
------------------------------------------------------------------------

local function NewCounters()
    local totals, maxPerPump = {}, {}
    for _, key in ipairs(COUNTER_KEYS) do totals[key] = 0; maxPerPump[key] = 0 end
    return {totals=totals, maxPerPump=maxPerPump, pumps=0}
end

local function NewBudget()
    local budget = {}
    for _, key in ipairs(COUNTER_KEYS) do budget[key] = 0 end
    return budget
end

local function Exhausted(budget)
    for _, key in ipairs(COUNTER_KEYS) do
        local slice = SLICE[key]
        if slice and budget[key] >= slice then return true end
    end
    return false
end

local function Charge(work, key, amount)
    amount = amount or 1
    work.budget[key] = work.budget[key] + amount
    local totals = work.counters.totals
    totals[key] = totals[key] + amount
    work.progress = true
end

local function ClosePump(work)
    local counters = work.counters
    counters.pumps = counters.pumps + 1
    for _, key in ipairs(COUNTER_KEYS) do
        if work.budget[key] > counters.maxPerPump[key] then
            counters.maxPerPump[key] = work.budget[key]
        end
    end
end

local function NewWork(counters)
    return {budget=NewBudget(), counters=counters or NewCounters(), progress=false}
end

------------------------------------------------------------------------
-- Resumable bottom-up stable merge sort with metered comparisons.
------------------------------------------------------------------------

local function NewSort(items, count, compare)
    return {items=items, buffer={}, n=count, width=1, left=0, i=nil,
        compare=compare, done=count <= 1}
end

local function SortStep(sort, work)
    if sort.done then return true end
    local n = sort.n
    while true do
        if sort.width >= n then sort.done = true; return true end
        if sort.left >= n then
            sort.items, sort.buffer = sort.buffer, sort.items
            sort.width = sort.width * 2
            sort.left, sort.i = 0, nil
            if sort.width >= n then sort.done = true; return true end
        end
        local items, buffer = sort.items, sort.buffer
        if sort.i == nil then
            sort.mid = math.min(sort.left + sort.width, n)
            sort.right = math.min(sort.left + sort.width * 2, n)
            sort.i, sort.j, sort.k = sort.left + 1, sort.mid + 1, sort.left + 1
        end
        while sort.k <= sort.right do
            if sort.i > sort.mid then
                buffer[sort.k] = items[sort.j]; sort.j = sort.j + 1
            elseif sort.j > sort.right then
                buffer[sort.k] = items[sort.i]; sort.i = sort.i + 1
            else
                if Exhausted(work.budget) then return false end
                local cmp, bytes = sort.compare(items[sort.i], items[sort.j])
                Charge(work, "sortComparisons", 1)
                Charge(work, "sortBytes", bytes)
                if cmp <= 0 then
                    buffer[sort.k] = items[sort.i]; sort.i = sort.i + 1
                else
                    buffer[sort.k] = items[sort.j]; sort.j = sort.j + 1
                end
            end
            sort.k = sort.k + 1
        end
        sort.left, sort.i = sort.right, nil
    end
end

------------------------------------------------------------------------
-- Bounded row walker: one resumable depth-first frontier per row.
------------------------------------------------------------------------

local function RowFail(walker, reason)
    if not walker.reason then walker.reason = reason end
    walker.stage = "failed"
    return "done"
end

local function PushFrame(walker, frame)
    frame.stage = "keys"
    frame.cursor = nil
    frame.keys = {}
    frame.keyCount = 0
    walker.frames[#walker.frames + 1] = frame
end

local function CollectKeys(walker, frame, work, limit, allowNumeric)
    while true do
        if Exhausted(work.budget) then return "pending" end
        local ok, key = pcall(next, frame.table, frame.cursor)
        if not ok then return RowFail(walker, "MALFORMED_ROW") end
        if key == nil then break end
        frame.cursor = key
        Charge(work, "edges", 1)
        local kind = type(key)
        if kind == "string" then
            if #key > BUDGET.keyWidth then return RowFail(walker, "KEY_WIDTH") end
            Charge(work, "bytesInspected", #key + 1)
        elseif kind == "number" and allowNumeric and FiniteInteger(key, 1) then
            Charge(work, "bytesInspected", 9)
        else
            return RowFail(walker, "UNSUPPORTED_KEY")
        end
        frame.keyCount = frame.keyCount + 1
        if frame.keyCount > limit then
            return RowFail(walker, frame.kind == "array" and "EVIDENCE_ROW_LIMIT"
                or "OBJECT_KEY_LIMIT")
        end
        frame.keys[frame.keyCount] = key
    end
    return "done"
end

local function CompareKeys(left, right)
    if type(left) ~= type(right) then
        return type(left) == "number" and -1 or 1, 2
    end
    if type(left) == "number" then
        return left < right and -1 or (left > right and 1 or 0), 18
    end
    return CompareStrings(left, right)
end

local function ValidateScalar(spec, value)
    if spec.kind == "string" then
        if type(value) ~= "string" or #value > spec.max then return nil end
        return value
    elseif spec.kind == "integer" then
        if not FiniteInteger(value, spec.min, MAX_SAFE_INTEGER) then return nil end
        return value
    elseif spec.kind == "boolean" then
        if type(value) ~= "boolean" then return nil end
        return value
    elseif spec.kind == "id" then
        if TypedKey(value) == nil then return nil end
        return value
    end
    return nil
end

-- Register one table identity; a table already on the active frame stack is
-- a cycle. Every inbound edge is charged; a shared identity counts once.
local function RegisterTable(walker, work, value, frameKind)
    if getmetatable(value) ~= nil then return RowFail(walker, "METATABLE_BACKED") end
    if walker.active[value] then return RowFail(walker, "CYCLE") end
    if not walker.identities[value] then
        walker.identities[value] = true
        walker.identityCount = walker.identityCount + 1
        Charge(work, "tableIdentities", 1)
    end
    walker.nodes = walker.nodes + 1
    if walker.nodes > BUDGET.nestedNodes then return RowFail(walker, "NODE_LIMIT") end
    Charge(work, "nodes", 1)
    Charge(work, "bytesInspected", 1)
    if frameKind == "unknown" then
        walker.unknownTables = walker.unknownTables + 1
        if walker.unknownTables > BUDGET.unknownTables then
            return RowFail(walker, "UNKNOWN_EVIDENCE_BUDGET")
        end
    end
    return "ok"
end

local function ChargeUnknownBytes(walker, work, amount)
    walker.unknownBytes = walker.unknownBytes + amount
    if walker.unknownBytes > BUDGET.unknownBytesPerRow then
        return RowFail(walker, "UNKNOWN_EVIDENCE_BUDGET")
    end
    Charge(work, "unknownBytes", amount)
    return "ok"
end

local function CopyUnknownScalar(walker, work, target, key, value)
    local kind = type(value)
    if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then
        return RowFail(walker, "MALFORMED_ROW")
    end
    if kind == "number" and (value ~= value or value >= math.huge
        or value <= -math.huge) then return RowFail(walker, "MALFORMED_ROW") end
    local bytes = ScalarBytes(key) + ScalarBytes(value)
    Charge(work, "nodes", 1)
    walker.nodes = walker.nodes + 1
    if walker.nodes > BUDGET.nestedNodes then return RowFail(walker, "NODE_LIMIT") end
    Charge(work, "bytesInspected", ScalarBytes(value))
    if ChargeUnknownBytes(walker, work, bytes) ~= "ok" then return "done" end
    target[key] = value
    return "ok"
end

local function BeginUnknownTable(walker, work, frame, key, value, target)
    if RegisterTable(walker, work, value, "unknown") ~= "ok" then return "done" end
    if frame.depth + 1 > BUDGET.depth then return RowFail(walker, "DEPTH_LIMIT") end
    if ChargeUnknownBytes(walker, work, ScalarBytes(key) + 1) ~= "ok" then
        return "done"
    end
    local copy = {}
    target[key] = copy
    walker.active[value] = true
    PushFrame(walker, {kind="unknown", table=value, target=copy,
        depth=frame.depth + 1, limit=BUDGET.objectKeys, numeric=true})
    return "ok"
end

local function KnownField(walker, work, key, value, canonical)
    local spec = FIELD[canonical]
    local validated = ValidateScalar(spec, value)
    if validated == nil then return RowFail(walker, "MALFORMED_ROW") end
    Charge(work, "nodes", 1)
    Charge(work, "bytesInspected", ScalarBytes(value))
    walker.nodes = walker.nodes + 1
    local existing = walker.known[canonical]
    if existing ~= nil and existing ~= validated then
        return RowFail(walker, "ALIAS_DISAGREEMENT")
    end
    walker.known[canonical] = validated
    if key ~= canonical then
        walker.aliasProbes = walker.aliasProbes + 1
        Charge(work, "aliasProbes", 1)
    end
    return "ok"
end

local function BeginEvidenceArray(walker, work, frame, key, value, locked)
    if type(value) ~= "table" then return RowFail(walker, "MALFORMED_ROW") end
    local role = locked and "locked" or "ordinary"
    if walker.evidenceSeen[role] then
        walker.aliasProbes = walker.aliasProbes + 1
        Charge(work, "aliasProbes", 1)
        if walker.evidenceSeen[role] ~= value then
            return RowFail(walker, "ALIAS_DISAGREEMENT")
        end
        return "ok"
    end
    if RegisterTable(walker, work, value, "array") ~= "ok" then return "done" end
    walker.evidenceSeen[role] = value
    if key ~= "echoes" and key ~= "lockedEchoes" then
        walker.aliasProbes = walker.aliasProbes + 1
        Charge(work, "aliasProbes", 1)
    end
    walker.active[value] = true
    PushFrame(walker, {kind="array", table=value, depth=frame.depth + 1,
        locked=locked, limit=BUDGET.denseEntries, numeric=true})
    return "ok"
end

local function BeginEcho(walker, work, frame, value)
    if type(value) ~= "table" then return RowFail(walker, "MALFORMED_ROW") end
    if RegisterTable(walker, work, value, "echo") ~= "ok" then return "done" end
    if frame.depth + 1 > BUDGET.depth then return RowFail(walker, "DEPTH_LIMIT") end
    walker.active[value] = true
    PushFrame(walker, {kind="echo", table=value, depth=frame.depth + 1,
        locked=frame.locked, fields={}, unknown=nil, limit=BUDGET.objectKeys,
        numeric=false})
    return "ok"
end

local function FinishEcho(walker, work, frame)
    local fields = frame.fields
    local spellId = FiniteInteger(fields.spellId, 1, 2147483647)
    local quality = fields.quality == nil and 0
        or FiniteInteger(fields.quality, 0, 2147483647)
    local stacks = fields.stacks == nil and 1
        or FiniteInteger(fields.stacks, 1, BUDGET.stacksPerRecord)
    if not spellId or not quality or not stacks then
        return RowFail(walker, "MALFORMED_ROW")
    end
    if fields.locked ~= nil and type(fields.locked) ~= "boolean"
        and fields.locked ~= 1 and fields.locked ~= 0 then
        return RowFail(walker, "MALFORMED_ROW")
    end
    local locked = frame.locked or fields.locked == true or fields.locked == 1
    walker.evidenceRowCount = walker.evidenceRowCount + 1
    if walker.evidenceRowCount > BUDGET.evidenceRowsPerRecord then
        return RowFail(walker, "EVIDENCE_ROW_LIMIT")
    end
    walker.stackTotal = walker.stackTotal + stacks
    if walker.stackTotal > BUDGET.stacksPerRecord then
        return RowFail(walker, "STACK_LIMIT")
    end
    Charge(work, "evidenceRows", 1)
    Charge(work, "stacks", stacks)
    -- The source role array is part of the tuple identity: PR #68 keeps the
    -- inline `echoes` rows (with their locked flags) and the separate
    -- locked-authority `lockedEchoes` rows as two durable fields.
    walker.tuples[#walker.tuples + 1] = {
        spellId=spellId, quality=quality, stacks=stacks, locked=locked,
        origin=frame.locked and "lockedArray" or "inline",
        unknown=frame.unknown,
    }
    return "ok"
end

local function WalkFrame(walker, frame, work)
    if frame.stage == "keys" then
        local result = CollectKeys(walker, frame, work, frame.limit, frame.numeric)
        if result ~= "done" then return result end
        if walker.stage == "failed" then return "done" end
        if frame.kind == "array" then
            local highest = 0
            for _, key in ipairs(frame.keys) do
                if type(key) ~= "number" then return RowFail(walker, "DENSE_ARRAY") end
                if key > highest then highest = key end
            end
            if highest ~= frame.keyCount then return RowFail(walker, "DENSE_ARRAY") end
            frame.stage, frame.index = "walk", 0
            return "ok"
        end
        frame.sort = NewSort(frame.keys, frame.keyCount, CompareKeys)
        frame.stage = "sort"
    end
    if frame.stage == "sort" then
        if not SortStep(frame.sort, work) then return "pending" end
        frame.keys = frame.sort.items
        frame.stage, frame.index = "walk", 0
    end
    while frame.stage == "walk" do
        if Exhausted(work.budget) then return "pending" end
        frame.index = frame.index + 1
        if frame.index > frame.keyCount then
            frame.stage = "done"
            break
        end
        local key
        if frame.kind == "array" then key = frame.index else key = frame.keys[frame.index] end
        local value = rawget(frame.table, key)
        if frame.kind == "array" then
            if BeginEcho(walker, work, frame, value) ~= "ok" then return "done" end
            return "ok"
        elseif frame.kind == "unknown" then
            if type(value) == "table" then
                if BeginUnknownTable(walker, work, frame, key, value, frame.target)
                    ~= "ok" then return "done" end
                return "ok"
            end
            if CopyUnknownScalar(walker, work, frame.target, key, value) ~= "ok" then
                return "done"
            end
        elseif frame.kind == "echo" then
            local canonical = ECHO_ALIAS[key]
            if canonical then
                Charge(work, "nodes", 1)
                Charge(work, "bytesInspected", ScalarBytes(value))
                walker.nodes = walker.nodes + 1
                if key ~= canonical then
                    walker.aliasProbes = walker.aliasProbes + 1
                    Charge(work, "aliasProbes", 1)
                end
                local existing = frame.fields[canonical]
                if existing ~= nil and existing ~= value then
                    return RowFail(walker, "ALIAS_DISAGREEMENT")
                end
                frame.fields[canonical] = value
            elseif type(value) == "table" then
                frame.unknown = frame.unknown or {}
                if BeginUnknownTable(walker, work, frame, key, value, frame.unknown)
                    ~= "ok" then return "done" end
                return "ok"
            else
                frame.unknown = frame.unknown or {}
                if CopyUnknownScalar(walker, work, frame.unknown, key, value) ~= "ok" then
                    return "done"
                end
            end
        else -- row
            local canonical = FIELD[key] and key or ALIAS[key]
            local spec = canonical and FIELD[canonical]
            if spec and spec.kind == "evidence" then
                if BeginEvidenceArray(walker, work, frame, key, value, spec.locked)
                    ~= "ok" then return "done" end
                if walker.frames[#walker.frames] ~= frame then return "ok" end
            elseif spec then
                if KnownField(walker, work, key, value, canonical) ~= "ok" then
                    return "done"
                end
            elseif type(value) == "table" then
                if BeginUnknownTable(walker, work, frame, key, value, walker.unknown)
                    ~= "ok" then return "done" end
                return "ok"
            else
                if CopyUnknownScalar(walker, work, walker.unknown, key, value) ~= "ok" then
                    return "done"
                end
            end
        end
    end
    return "ok"
end

local function NewWalker(raw, options)
    return {
        raw=raw, options=options or {}, stage="start", frames={},
        known={}, unknown={}, unknownBytes=0, unknownTables=0,
        identities={}, identityCount=0, active={}, nodes=0, aliasProbes=0,
        evidenceSeen={}, tuples={}, evidenceRowCount=0, stackTotal=0,
        reason=nil, sort=nil, grouped=nil,
    }
end

local function GroupTuples(walker)
    local sorted = walker.sort.items
    local grouped, index = {}, 0
    local ordinary, locked, total = 0, 0, 0
    local previous
    for i = 1, #sorted do
        local tuple = sorted[i]
        if previous and CompareTuples(previous, tuple) == 0 then
            if previous.unknown ~= nil or tuple.unknown ~= nil then
                return nil, "AMBIGUOUS_NESTED_UNKNOWN_SCOPE"
            end
            previous.stacks = previous.stacks + tuple.stacks
            if previous.stacks > BUDGET.stacksPerRecord then
                return nil, "STACK_LIMIT"
            end
        else
            index = index + 1
            previous = {spellId=tuple.spellId, quality=tuple.quality,
                stacks=tuple.stacks, locked=tuple.locked or nil,
                origin=tuple.origin or "inline", unknown=tuple.unknown}
            grouped[index] = previous
        end
        if tuple.locked then locked = locked + tuple.stacks
        else ordinary = ordinary + tuple.stacks end
        total = total + tuple.stacks
    end
    return grouped, nil, ordinary, locked, total
end

-- Drive one row walker until the pump budget is exhausted or the row has a
-- verdict. Returns "pending" or "done"; walker.reason names a row fault.
local function WalkRow(walker, work)
    if walker.stage == "start" then
        local raw = walker.raw
        if type(raw) ~= "table" then return RowFail(walker, "MALFORMED_ROW") end
        if RegisterTable(walker, work, raw, "row") ~= "ok" then return "done" end
        walker.active[raw] = true
        PushFrame(walker, {kind="row", table=raw, depth=0,
            limit=BUDGET.objectKeys, numeric=false})
        walker.stage = "walk"
    end
    while walker.stage == "walk" do
        local frame = walker.frames[#walker.frames]
        if not frame then
            walker.stage = "evidence"
            break
        end
        local result = WalkFrame(walker, frame, work)
        if walker.stage == "failed" then return "done" end
        if result == "pending" then return "pending" end
        if frame.stage == "done" then
            walker.active[frame.table] = nil
            walker.frames[#walker.frames] = nil
            if frame.kind == "echo" then
                if FinishEcho(walker, work, frame) ~= "ok" then return "done" end
            end
        end
    end
    if walker.stage == "evidence" then
        if walker.sort == nil then
            walker.sort = NewSort(walker.tuples, #walker.tuples, CompareTuples)
        end
        if not SortStep(walker.sort, work) then return "pending" end
        local grouped, reason, ordinary, locked, total = GroupTuples(walker)
        if not grouped then return RowFail(walker, reason) end
        walker.grouped = grouped
        walker.semantic = {ordinary=ordinary, locked=locked, total=total}
        if ordinary > BUDGET.ordinaryCopies or locked > BUDGET.lockedCopies
            or total > BUDGET.totalCopies then
            return RowFail(walker, "SEMANTIC_ENVELOPE")
        end
        walker.stage = "complete"
    end
    return "done"
end

local function WalkToCompletion(walker)
    local work = NewWork()
    for _ = 1, 10000000 do
        if WalkRow(walker, work) == "done" then return walker end
        work.budget = NewBudget()
    end
    return walker
end

------------------------------------------------------------------------
-- Canonical snapshot, provenance, fingerprints
------------------------------------------------------------------------

local function OrdinaryFingerprint(tuples)
    local counts, ids = {}, {}
    for _, row in ipairs(tuples or {}) do
        if not row.locked then
            counts[row.spellId] = (counts[row.spellId] or 0) + row.stacks
        end
    end
    for id in pairs(counts) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        parts[#parts + 1] = tostring(id) .. "x" .. tostring(counts[id])
    end
    return #parts > 0 and table.concat(parts, ",") or nil
end

local function FingerprintSpells(fingerprint)
    local spells, total = {}, 0
    if type(fingerprint) ~= "string" then return spells, total end
    for rawId, rawCount in fingerprint:gmatch("(%d+)x(%d+)") do
        local id, count = tonumber(rawId), tonumber(rawCount)
        if id and count and count > 0 then
            spells[#spells + 1] = id
            total = total + count
        end
    end
    return spells, total
end

local function NormalizedClass(value)
    value = type(value) == "string" and value:upper() or nil
    return value and VALID_CLASS[value] and value or nil
end

local function SplitTuples(grouped)
    local ordinary, locked = {}, {}
    for _, row in ipairs(grouped or {}) do
        local copy = {spellId=row.spellId, quality=row.quality, stacks=row.stacks,
            locked=row.locked or nil}
        if row.locked then locked[#locked + 1] = copy
        else ordinary[#ordinary + 1] = copy end
    end
    return ordinary, locked
end

-- Resolve pool-only evidence through the shared evidence owner. The catalog
-- never touches the evidence store itself; a resolved record is re-proved
-- under the same semantic envelope as inline evidence.
local function ResolveEvidence(known)
    local evidence = Nexus and Nexus.LoadoutEvidence
    if not (evidence and type(evidence.Resolve) == "function") then return nil end
    local rows = {}
    if type(known.evidenceKey) == "string" and known.evidenceKey ~= "" then
        local ok, resolved = pcall(evidence.Resolve, known.evidenceKey, nil)
        if ok and type(resolved) == "table" then
            for _, row in ipairs(resolved) do
                rows[#rows + 1] = {spellId=row.spellId, quality=row.quality,
                    stacks=row.stacks, locked=row.locked or nil, origin="inline"}
            end
        end
    end
    if type(known.lockedEvidenceKey) == "string" and known.lockedEvidenceKey ~= "" then
        local ok, resolved = pcall(evidence.Resolve, known.lockedEvidenceKey, nil,
            {forceLocked=true})
        if ok and type(resolved) == "table" then
            for _, row in ipairs(resolved) do
                rows[#rows + 1] = {spellId=row.spellId, quality=row.quality,
                    stacks=row.stacks, locked=true, origin="lockedArray"}
            end
        end
    end
    return #rows > 0 and rows or nil
end

local function SemanticOf(rows)
    local ordinary, locked, total = 0, 0, 0
    for _, row in ipairs(rows or {}) do
        local stacks = tonumber(row.stacks) or 0
        if row.locked then locked = locked + stacks else ordinary = ordinary + stacks end
        total = total + stacks
    end
    return {ordinary=ordinary, locked=locked, total=total}
end

local function Completeness(snapshotLike)
    local evidence = Nexus and Nexus.LoadoutEvidence
    if not (evidence and type(evidence.OrdinaryCompleteness) == "function") then
        return {complete=false, reason="unavailable", echoCount=0}
    end
    local resolver = type(evidence.PublicOrdinaryCompleteness) == "function"
        and evidence.PublicOrdinaryCompleteness or evidence.OrdinaryCompleteness
    local ok, verdict = pcall(resolver, snapshotLike)
    if ok and type(verdict) == "table" then return verdict end
    return {complete=false, reason="malformed", echoCount=0}
end

-- Derive every authority field from the admitted source. Input claims such as
-- ownerVerified, isMine, and relaySender are evidence, never proof.
local function DeriveProvenance(known, source, options)
    local ownerKey = type(known.ownerKey) == "string"
        and Identity.CanonicalOwnerKey(known.ownerKey) or nil
    local current = CurrentOwnerKey()
    local mode = options.source or "durable"
    if mode == "remote" then
        local verified = ownerKey ~= nil
            and Identity.TransportOwns(ownerKey, options.sender)
        if verified then
            known.ownerKey = ownerKey
            known.ownerVerified = true
            known.claimedOwnerKey = nil
            known.relaySender = nil
        else
            known.claimedOwnerKey = ownerKey or known.claimedOwnerKey
            known.ownerKey = nil
            known.ownerVerified = false
            known.relaySender = type(options.sender) == "string" and options.sender or nil
        end
        known.isMine = false
        known.importedSavedBuild = nil
    elseif mode == "local" or mode == "import" then
        local mine = ownerKey ~= nil and current ~= nil and ownerKey == current
        known.ownerKey = ownerKey
        known.ownerVerified = mine
        known.isMine = mine
        known.claimedOwnerKey = nil
        known.relaySender = nil
        if mode == "import" then known.importedSavedBuild = true end
        if not mine and known.importedSavedBuild == true then
            known.importedSavedBuild = nil
        end
    elseif source == "bundled" then
        -- Bundled author text never proves local ownership; the package's
        -- own saved-mirror marker is preserved as stored.
        known.ownerKey = ownerKey
        known.isMine = false
    else
        known.ownerKey = ownerKey
        if known.ownerVerified == true
            and Identity.CoherentRecordOwnerKey(known) == nil then
            known.ownerVerified = false
        end
        -- `isMine` stays preserved legacy evidence. It grants no authority on
        -- its own: every owner check goes through verified ownership, and the
        -- Saved-mirror adoption bridge still requires exact owner proof.
    end
end

local function BuildSnapshot(walker, slot, source, options)
    local known = walker.known
    local grouped = walker.grouped or {}
    known.id = slot.id
    if type(known.class) == "string" then known.class = known.class:upper() end
    DeriveProvenance(known, source, options)
    -- One canonical evidence record proves the semantic envelope across both
    -- roles; the public snapshot keeps PR #68's two durable fields so the
    -- locked-authority consumers (Package A) read the exact shapes they own.
    local canonical, inline, lockedArray = {}, {}, {}
    local function Admit(row)
        local copy = {spellId=row.spellId, quality=row.quality, stacks=row.stacks,
            locked=row.locked and true or nil}
        canonical[#canonical + 1] = copy
        if row.origin == "lockedArray" then lockedArray[#lockedArray + 1] = copy
        else inline[#inline + 1] = copy end
    end
    for _, row in ipairs(grouped) do Admit(row) end
    local hadInline = walker.evidenceSeen.ordinary ~= nil
        or walker.evidenceSeen.locked ~= nil
    -- A compacted row keeps its evidence in the shared pool. Each role
    -- resolves independently: an absent inline array is replaced by its own
    -- reference, and the union is re-proved against the semantic envelope.
    local wantsInline, wantsLockedRole = #inline == 0, #lockedArray == 0
    if wantsInline or wantsLockedRole then
        local resolvedRows = ResolveEvidence(known)
        for _, row in ipairs(resolvedRows or {}) do
            local isLocked = row.origin == "lockedArray"
            if (isLocked and wantsLockedRole) or (not isLocked and wantsInline) then
                Admit(row)
            end
        end
        if resolvedRows then
            local semantic = SemanticOf(canonical)
            if semantic.ordinary > BUDGET.ordinaryCopies
                or semantic.locked > BUDGET.lockedCopies
                or semantic.total > BUDGET.totalCopies then
                return nil, "SEMANTIC_ENVELOPE", semantic
            end
            walker.semantic = semantic
        end
    end
    local ordinary = {}
    for _, row in ipairs(inline) do
        if not row.locked then ordinary[#ordinary + 1] = row end
    end
    local snapshot = {}
    for key, value in pairs(known) do snapshot[key] = value end
    local evidence = Nexus and Nexus.LoadoutEvidence
    local function EvidenceKeyOf(rows, keyOptions)
        if evidence and type(evidence.Fingerprint) == "function" then
            local ok, key = pcall(evidence.Fingerprint, rows, keyOptions)
            if ok and type(key) == "string" then return key end
        end
        return nil
    end
    if #inline > 0 then
        snapshot.echoes = inline
        snapshot.evidenceKey = EvidenceKeyOf(inline) or snapshot.evidenceKey
        local total = 0
        for _, row in ipairs(inline) do total = total + row.stacks end
        snapshot.echoCount = total
    else
        snapshot.echoes = nil
    end
    if #lockedArray > 0 then
        snapshot.lockedEchoes = lockedArray
        snapshot.lockedEvidenceKey = EvidenceKeyOf(lockedArray, {forceLocked=true})
            or snapshot.lockedEvidenceKey
    else
        snapshot.lockedEchoes = nil
    end
    -- The evidence owner classifies completeness from the exact admitted
    -- inline record, including a cross-role row, so its fixed reason is
    -- preserved instead of being reduced to "unavailable".
    local verdict = Completeness({
        echoes=#inline > 0 and inline or (hadInline and {} or nil),
        fingerprint=snapshot.fingerprint,
        evidenceKey=#inline == 0 and snapshot.evidenceKey or nil,
    })
    local complete = type(verdict) == "table" and verdict.complete == true
    local computedFingerprint = OrdinaryFingerprint(ordinary)
    if complete and type(snapshot.fingerprint) == "string"
        and snapshot.fingerprint ~= "" and snapshot.fingerprint:sub(1, 1) ~= "@"
        and computedFingerprint and snapshot.fingerprint ~= computedFingerprint then
        complete = false
        verdict = {complete=false, reason="fingerprint-mismatch", echoCount=0}
    end
    snapshot.loadoutAvailable = complete
    if complete then
        snapshot.fingerprint = snapshot.fingerprint or computedFingerprint
        snapshot.fingerprintHash = type(snapshot.fingerprintHash) == "string"
            and snapshot.fingerprintHash:lower() or HashText(snapshot.fingerprint)
    end
    if snapshot.link and not snapshot.linkHash then
        snapshot.linkHash = HashText(snapshot.link)
    end
    snapshot.ordinaryComplete = complete
    snapshot.ordinaryCompletenessReason = type(verdict) == "table"
        and verdict.reason or "unavailable"
    local exactFingerprint = type(known.fingerprint) == "string"
        and known.fingerprint ~= "" and known.fingerprint or computedFingerprint
    return snapshot, nil, walker.semantic or SemanticOf(canonical), {
        complete=complete, computedFingerprint=computedFingerprint,
        exactFingerprint=exactFingerprint, grouped=grouped,
    }
end

------------------------------------------------------------------------
-- Tombstone and eviction-barrier classification
------------------------------------------------------------------------

local function BoundedShape(raw, work, edgeKey, byteKey, maxTables, maxEntries, maxDepth, maxBytes)
    local tables, entries, bytes = 0, 0, 0
    local seen = {}
    local ok = true
    local function Visit(value, depth)
        if not ok then return end
        if type(value) ~= "table" then return end
        if getmetatable(value) ~= nil or seen[value] then ok = false; return end
        seen[value] = true
        tables = tables + 1
        if tables > maxTables or depth > maxDepth then ok = false; return end
        for key, child in pairs(value) do
            entries = entries + 1
            Charge(work, edgeKey, 1)
            if entries > maxEntries then ok = false; return end
            local width = ScalarBytes(key) + ScalarBytes(child)
            if type(key) == "string" then bytes = bytes + #key end
            if type(child) == "string" then bytes = bytes + #child end
            Charge(work, byteKey, width)
            if bytes > maxBytes then ok = false; return end
            if type(key) ~= "string" and type(key) ~= "number" then ok = false; return end
            if type(child) == "table" then Visit(child, depth + 1)
            elseif type(child) ~= "string" and type(child) ~= "number"
                and type(child) ~= "boolean" then ok = false; return end
        end
    end
    Visit(raw, 0)
    return ok
end

local function ExactTypedId(value, slot)
    return type(value) == "table" and getmetatable(value) == nil
        and value.luaType == slot.kind and value.exactValue == slot.id
        and Count(value) == 2
end

local function ClassifyTombstone(raw, slot, work)
    local view = {stamp=0, author="", ownerKey=nil, ownerVerified=false,
        sourceKind=nil, localOwned=false}
    if ST.sessionTombstones[raw] then
        view.state = "CURRENT_DENY"
        view.stamp = tonumber(raw.remoteStampEvidence) or 0
        local provenance = type(raw.targetRowProvenance) == "table"
            and raw.targetRowProvenance or {}
        view.author = tostring(provenance.author or "")
        view.ownerKey = type(raw.ownerKey) == "string" and raw.ownerKey or nil
        view.ownerVerified = provenance.ownerVerified == true
        view.sourceKind = raw.sourceKind
        local current = CurrentOwnerKey()
        view.localOwned = raw.sourceKind == "local" and current ~= nil
            and view.ownerKey == current
        Charge(work, "tombstoneEdges", 10)
        return "CURRENT_DENY", view
    end
    if type(raw) ~= "table" then
        Charge(work, "tombstoneEdges", 1)
        Charge(work, "tombstoneBytes", ScalarBytes(raw))
        view.state = "OPAQUE_BLOCK_ALL"
        view.stamp = tonumber(raw) or 0
        return "OPAQUE_BLOCK_ALL", view
    end
    local bounded = BoundedShape(raw, work, "tombstoneEdges", "tombstoneBytes",
        BUDGET.tombstoneTables, BUDGET.tombstoneEntries, BUDGET.tombstoneDepth,
        BUDGET.tombstoneStringBytes)
    if not bounded then
        view.state = "OPAQUE_BLOCK_ALL"
        return "OPAQUE_BLOCK_ALL", view
    end
    view.stamp = tonumber(raw.stamp or raw.remoteStampEvidence) or 0
    local provenance = type(raw.targetRowProvenance) == "table"
        and raw.targetRowProvenance or nil
    view.author = tostring(raw.author or (provenance and provenance.author) or "")
    view.ownerKey = type(raw.ownerKey) == "string" and raw.ownerKey or nil
    local exact = raw.schemaVersion == TOMBSTONE_SCHEMA_VERSION
        and ExactTypedId(raw.typedId, slot) and provenance ~= nil
    if exact then
        for key in pairs(raw) do
            if not TOMBSTONE_V1_FIELDS[key] then exact = false; break end
        end
        for key in pairs(TOMBSTONE_V1_FIELDS) do
            if raw[key] == nil then exact = false end
        end
    end
    if exact then
        view.state = "RELOADED_BLOCK_ALL"
        view.sourceKind = raw.sourceKind
        return "RELOADED_BLOCK_ALL", view
    end
    view.state = "OPAQUE_BLOCK_ALL"
    return "OPAQUE_BLOCK_ALL", view
end

local function ClassifyBarrier(raw, slot, work)
    local view = {}
    if ST.sessionBarriers[raw] then
        Charge(work, "barrierEdges", 7)
        Charge(work, "barrierNodes", 8)
        view.state = "BARRIER_CURRENT_DENY"
        view.receiptAtServerTime = tonumber(raw.receiptAtServerTime) or 0
        view.revision = tonumber(raw.receiptRevision) or 0
        return view
    end
    if type(raw) ~= "table" then
        Charge(work, "barrierEdges", 1)
        Charge(work, "barrierBytes", ScalarBytes(raw))
        view.state = "BARRIER_OPAQUE_BLOCK_ALL"
        view.revision = tonumber(raw) or 0
        return view
    end
    local bounded = BoundedShape(raw, work, "barrierEdges", "barrierBytes",
        BUDGET.tombstoneTables, BUDGET.tombstoneEntries, BUDGET.depth,
        BUDGET.recordBytes)
    Charge(work, "barrierNodes", 1)
    if not bounded then
        view.state = "BARRIER_OPAQUE_BLOCK_ALL"
        return view
    end
    view.revision = tonumber(raw.revision or raw.stamp) or 0
    view.recordedAt = tonumber(raw.recordedAt or raw.evictedAt) or nil
    local exact = raw.schemaVersion == BARRIER_SCHEMA_VERSION
        and ExactTypedId(raw.typedId, slot)
    if exact then
        for key in pairs(raw) do
            if not BARRIER_V1_FIELDS[key] then exact = false; break end
        end
        for key in pairs(BARRIER_V1_FIELDS) do
            if raw[key] == nil then exact = false end
        end
    end
    if exact then
        view.state = "BARRIER_RELOADED_BLOCK_ALL"
        local observed = ST.readmittedBarriers[raw]
        if not observed then
            observed = TrustedServerTime() or 0
            ST.readmittedBarriers[raw] = observed
        end
        view.readmittedAtServerTime = observed
        view.receiptAtServerTime = tonumber(raw.receiptAtServerTime) or 0
        return view
    end
    view.state = "BARRIER_OPAQUE_BLOCK_ALL"
    return view
end

------------------------------------------------------------------------
-- Selection and verdict construction
------------------------------------------------------------------------

local function RawRevision(row)
    if type(row) ~= "table" or getmetatable(row) ~= nil then return -math.huge end
    return tonumber(rawget(row, "lastModified") or rawget(row, "postedAt")) or 0
end

-- An explicit local marker (isMine / importedSavedBuild) exempts an overlay
-- from baseline pruning; owner-key equality alone only steers selection.
local function RawLocalMarker(row)
    if type(row) ~= "table" or getmetatable(row) ~= nil then return false end
    return rawget(row, "isMine") == true or rawget(row, "importedSavedBuild") == true
end

local function RawPersonal(row)
    if type(row) ~= "table" or getmetatable(row) ~= nil then return false end
    if rawget(row, "isMine") == true or rawget(row, "importedSavedBuild") == true then
        return true
    end
    local ownerKey = rawget(row, "ownerKey")
    if type(ownerKey) ~= "string" then return false end
    local current = CurrentOwnerKey()
    return current ~= nil and Identity.CanonicalOwnerKey(ownerKey) == current
end

local function SelectRawSource(slot)
    local over, base = slot.overlay, slot.bundled
    -- A malformed or future-owned raw overlay value occupies its typed slot
    -- deny-only; it never falls through to the lower bundled source.
    if over ~= nil and type(over) ~= "table" then return over, "overlay" end
    if type(over) == "table" then
        if type(base) ~= "table" or RawPersonal(over)
            or RawRevision(over) >= RawRevision(base) then
            return over, "overlay"
        end
    end
    if type(base) == "table" then return base, "bundled" end
    if over ~= nil then return over, "overlay" end
    return nil, nil
end

local function NewVerdict(slot, state, reason)
    return {state=state, reason=reason, id=slot.id, typedKey=slot.key,
        kind=slot.kind}
end

local function FutureSchemaOf(row)
    if type(row) ~= "table" or getmetatable(row) ~= nil then return nil end
    local version = rawget(row, "schemaVersion")
    if FiniteInteger(version, 0) and version > STORAGE_SCHEMA_VERSION then
        return version
    end
    return nil
end

local function FinishRowVerdict(walker, slot, source, options)
    local verdict = NewVerdict(slot, "ADMITTED", "complete")
    verdict.source = source
    verdict.raw = walker.raw
    if walker.reason then
        verdict.state, verdict.reason = "INVALIDATED", walker.reason
        verdict.semantic = walker.semantic
        return verdict
    end
    -- An embedded identity that contradicts the typed slot is a collision;
    -- title, hash, or arrival order never breaks the tie.
    if walker.known.id ~= nil and walker.known.id ~= slot.id then
        verdict.state, verdict.reason = "INVALIDATED", "TYPED_ID_MISMATCH"
        return verdict
    end
    local snapshot, reason, semantic, derived = BuildSnapshot(walker, slot, source, options)
    if not snapshot then
        verdict.state, verdict.reason = "INVALIDATED", reason
        verdict.semantic = semantic
        return verdict
    end
    verdict.snapshot = snapshot
    verdict.semantic = semantic
    verdict.unknown = walker.unknown
    verdict.hasUnknown = next(walker.unknown) ~= nil
    for _, row in ipairs(derived.grouped) do
        if row.unknown ~= nil then verdict.hasUnknown = true end
    end
    verdict.grouped = derived.grouped
    verdict.complete = derived.complete
    verdict.exactFingerprint = derived.exactFingerprint
    verdict.relatedFingerprint = derived.computedFingerprint or derived.exactFingerprint
    verdict.savedKind = Identity.SavedMirrorKind(snapshot)
    verdict.verifiedOwner = Identity.VerifiedOwnerKey(snapshot)
    -- Package authority: an immutable bundled row's coherent owner tuple is
    -- trusted for delete ownership even without a verification flag.
    verdict.trustedOwner = verdict.verifiedOwner
        or (source == "bundled" and Identity.CoherentRecordOwnerKey(snapshot)) or nil
    if verdict.savedKind == "invalid" then
        verdict.state, verdict.reason = "INVALIDATED", "MALFORMED_ROW"
        verdict.snapshot = nil
    end
    return verdict
end

local function AdmitRaw(raw, slot, source, options)
    local walker = WalkToCompletion(NewWalker(raw, options or {}))
    return FinishRowVerdict(walker, slot, source, options or {}), walker
end

------------------------------------------------------------------------
-- Root-local indexes (exact, fingerprint, title, spells, saved, owner class,
-- author). Buckets contain only bounded typed-key memberships.
------------------------------------------------------------------------

local function RelatedText(value)
    return tostring(value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function RelatedKey(author, value)
    author, value = Identity.PlayerKey(author) or RelatedText(author),
        tostring(value or "")
    if author == "" or value == "" then return nil end
    return author .. "\0" .. value
end

local function AuthorKey(value)
    if type(value) ~= "string" or value == "" then return nil end
    return Identity.PlayerKey(value)
        or (value:match("^([^-]+)") or value):lower()
end

local function NewIndex()
    return {exact={}, fingerprints={}, titles={}, spells={}, saved={},
        ownerClasses={}, authors={}, memberships={}}
end

local function BetterExactCandidate(id, verdict, currentId, currentVerdict)
    if not currentId or not currentVerdict then return true end
    local auto = verdict.snapshot.autoDps and true or false
    local currentAuto = currentVerdict.snapshot.autoDps and true or false
    if auto ~= currentAuto then return not auto end
    return tostring(id) < tostring(currentId)
end

local function RecomputeExactWinner(rows, bucket)
    bucket.winnerKey, bucket.winnerId = nil, nil
    for key in pairs(bucket.ids) do
        local verdict = rows[key]
        if verdict and verdict.snapshot then
            if BetterExactCandidate(verdict.id, verdict, bucket.winnerId,
                bucket.winnerKey and rows[bucket.winnerKey]) then
                bucket.winnerKey, bucket.winnerId = key, verdict.id
            end
        end
    end
end

local function AddBucket(map, bucketKey, key, work)
    if not bucketKey then return nil end
    local bucket = map[bucketKey]
    if not bucket then
        bucket = {ids={}, count=0}
        map[bucketKey] = bucket
        if work then Charge(work, "indexNodes", 1) end
    end
    if not bucket.ids[key] then
        bucket.ids[key] = true
        bucket.count = bucket.count + 1
        if work then
            Charge(work, "indexEdges", 1)
            Charge(work, "indexBytes", #bucketKey + 18)
        end
    end
    return bucket
end

local function RemoveBucket(map, bucketKey, key)
    local bucket = bucketKey and map[bucketKey]
    if not bucket then return end
    if bucket.ids[key] then
        bucket.ids[key] = nil
        bucket.count = math.max(0, bucket.count - 1)
    end
    if bucket.count == 0 then map[bucketKey] = nil end
end

local function IndexRemove(index, rows, key)
    local membership = index.memberships[key]
    if not membership then return end
    local exactBucket = membership.exact and index.exact[membership.exact]
    if exactBucket and exactBucket.ids[key] then
        local field = membership.exactAuto and "autoCount" or "explicitCount"
        exactBucket[field] = math.max(0, (exactBucket[field] or 0) - 1)
    end
    RemoveBucket(index.exact, membership.exact, key)
    if exactBucket and index.exact[membership.exact] and exactBucket.winnerKey == key then
        RecomputeExactWinner(rows, exactBucket)
    end
    RemoveBucket(index.fingerprints, membership.fingerprint, key)
    RemoveBucket(index.titles, membership.title, key)
    RemoveBucket(index.saved, membership.saved, key)
    for _, spellKey in ipairs(membership.spells or {}) do
        RemoveBucket(index.spells, spellKey, key)
    end
    local owner = membership.classOwner and index.ownerClasses[membership.classOwner]
    if owner and owner.ids[key] then
        local class = owner.ids[key]
        owner.ids[key] = nil
        owner.count = owner.count - 1
        owner.classes[class] = (owner.classes[class] or 1) - 1
        if owner.classes[class] <= 0 then owner.classes[class] = nil end
        if owner.count <= 0 then index.ownerClasses[membership.classOwner] = nil end
    end
    if membership.author then
        local authorBucket = index.authors[membership.author]
        if authorBucket then
            authorBucket[key] = nil
            if next(authorBucket) == nil then index.authors[membership.author] = nil end
        end
    end
    index.memberships[key] = nil
end

local function IndexAdd(index, rows, verdict, work)
    local key = verdict.typedKey
    local snapshot = verdict.snapshot
    if not snapshot then return end
    local membership = {}
    local savedKind = verdict.savedKind
    local exact = savedKind == "ordinary" and verdict.complete
        and verdict.exactFingerprint or nil
    local exactBucket = AddBucket(index.exact, exact, key, work)
    membership.exact = exact
    membership.exactAuto = snapshot.autoDps == true
    if exactBucket then
        local field = membership.exactAuto and "autoCount" or "explicitCount"
        exactBucket[field] = (exactBucket[field] or 0) + 1
        if BetterExactCandidate(verdict.id, verdict, exactBucket.winnerId,
            exactBucket.winnerKey and rows[exactBucket.winnerKey]) then
            exactBucket.winnerKey, exactBucket.winnerId = key, verdict.id
        end
    end
    if savedKind == "ordinary" and verdict.verifiedOwner then
        local class = NormalizedClass(snapshot.class)
        if class then
            local owner = index.ownerClasses[verdict.verifiedOwner]
            if not owner then
                owner = {ids={}, classes={}, count=0}
                index.ownerClasses[verdict.verifiedOwner] = owner
            end
            if owner.ids[key] == nil then
                owner.ids[key] = class
                owner.classes[class] = (owner.classes[class] or 0) + 1
                owner.count = owner.count + 1
                if work then Charge(work, "indexEdges", 1) end
            end
            membership.classOwner = verdict.verifiedOwner
        end
    end
    local authorKey = AuthorKey(snapshot.author)
    if authorKey then
        index.authors[authorKey] = index.authors[authorKey] or {}
        index.authors[authorKey][key] = true
        membership.author = authorKey
        if work then Charge(work, "indexEdges", 1) end
    end
    local author = RelatedText(snapshot.author)
    if author ~= "" then
        if savedKind == "saved" then
            membership.saved = RelatedKey(author, "saved")
            AddBucket(index.saved, membership.saved, key, work)
        else
            local fingerprint = verdict.relatedFingerprint
            membership.fingerprint = RelatedKey(author, fingerprint)
            membership.title = RelatedKey(author,
                RelatedText(snapshot.title or snapshot.serverTitle))
            membership.spells = {}
            local spells = FingerprintSpells(fingerprint)
            for _, spellId in ipairs(spells) do
                local spellKey = RelatedKey(author, tostring(spellId))
                if spellKey then
                    membership.spells[#membership.spells + 1] = spellKey
                    AddBucket(index.spells, spellKey, key, work)
                end
            end
            AddBucket(index.fingerprints, membership.fingerprint, key, work)
            AddBucket(index.titles, membership.title, key, work)
        end
    end
    index.memberships[key] = membership
end

------------------------------------------------------------------------
-- Root token, drift detection, published root
------------------------------------------------------------------------

local function CaptureToken(db)
    return {
        databaseIdentity=db, overlayIdentity=rawget(db, "communityBuilds"),
        tombstoneIdentity=rawget(db, "syncTombstones"),
        metadataIdentity=rawget(db, "buildCatalog"),
        evictionIdentity=rawget(db, "communityRetentionEvictions"),
        bundledIdentity=ST.bundled, baselineIdentity=ST.baseline,
        ownerIdentity=CurrentOwnerKey(),
        bindingGeneration=ST.bindingGeneration,
        committedMutationRevision=ST.committedMutationRevision,
        preparationEpoch=ST.preparationEpoch,
        reservationEpoch=ST.reservationEpoch,
        callbackOwnerIdentity=Nexus and Nexus.Revisions or nil,
    }
end

local function TokenDrifted(token)
    local db = token.databaseIdentity
    if type(db) ~= "table" then return "SOURCE_DRIFT" end
    if rawget(db, "communityBuilds") ~= token.overlayIdentity
        or rawget(db, "syncTombstones") ~= token.tombstoneIdentity
        or rawget(db, "buildCatalog") ~= token.metadataIdentity
        or rawget(db, "communityRetentionEvictions") ~= token.evictionIdentity
        or (Nexus and Nexus.Revisions) ~= token.callbackOwnerIdentity then
        return "SOURCE_DRIFT"
    end
    if token.bundledIdentity ~= ST.bundled or token.baselineIdentity ~= ST.baseline then
        return "SOURCE_DRIFT"
    end
    if ST.bindingGeneration ~= token.bindingGeneration then return "SOURCE_DRIFT" end
    return nil
end

local function Invalidate(reason)
    if ST.rootState ~= "ROOT_INVALIDATED" then
        ST.debugStats.driftInvalidations = ST.debugStats.driftInvalidations + 1
    end
    ST.rootState, ST.rootReason = "ROOT_INVALIDATED", reason
    ST.published = nil
    ST.activeClaim = nil
    ST.activeCursors = {}
    ST.activeMaintenance = nil
end

-- Every authority API first proves the published root is still bound to the
-- exact raw identities it was admitted from.
local function Gate()
    if type(NexusDB) == "table" and NexusDB ~= ST.db and ST.candidate == nil then
        Catalog.Init(NexusDB, Nexus.BundledBuilds)
    end
    if ST.rootState == "ROOT_ADMITTED" then
        local drift = ST.published and TokenDrifted(ST.published.token)
        if drift then Invalidate(drift) end
    end
    -- The local-owner proof is an admission input. When the character
    -- identity becomes available or changes, every selection and provenance
    -- verdict is re-proved by one explicit complete re-admission.
    if ST.rootState == "ROOT_ADMITTED" and ST.published and ST.candidate == nil
        and ST.published.token.ownerIdentity ~= CurrentOwnerKey() then
        Catalog.Init(ST.db, ST.bundled)
    end
    if ST.rootState == "ROOT_ADMITTED" then return ST.published end
    return nil, ST.candidate and "ROOT_ADMISSION_PENDING" or ST.rootState
end

------------------------------------------------------------------------
-- Root admission handle
------------------------------------------------------------------------

local function ClassifyMetadata(db)
    local meta = rawget(db, "buildCatalog")
    if meta == nil then return "current", nil, nil end
    if type(meta) ~= "table" or getmetatable(meta) ~= nil then
        return "invalid", "METADATA_MALFORMED"
    end
    local version = rawget(meta, "schemaVersion")
    if version ~= nil and not FiniteInteger(version, 0) then
        return "invalid", "METADATA_MALFORMED"
    end
    if version ~= nil and version > STORAGE_SCHEMA_VERSION then
        return "future", nil, meta, version
    end
    for key, value in pairs(meta) do
        if key ~= "schemaVersion" and key ~= "catalogVersion"
            and key ~= "sourceVersion" then
            return "invalid", "METADATA_UNKNOWN_FIELD"
        end
        if key ~= "schemaVersion" and type(value) ~= "string" then
            return "invalid", "METADATA_MALFORMED"
        end
    end
    return "current", nil, meta, version
end

local function PlainMapOrNil(value)
    if value == nil then return true, nil end
    if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
    return true, value
end

local function NewAdmission(db)
    ST.bindingGeneration = ST.bindingGeneration + 1
    local handle = {
        mode="admission", phase="capture", counters=NewCounters(),
        slots={}, slotVector={}, slotCount=0, mapIndex=1, mapCursor=nil,
        rootMapEdges=0, verdicts={}, index=NewIndex(),
        rowIndex=0, indexIndex=0, counts=nil, mapCounts={},
        pumps=0, failure=nil, token=CaptureToken(db),
    }
    ST.counters = handle.counters
    return handle
end

local MAP_ORDER = {"overlay", "bundled", "tombstone", "barrier"}

local function AdmissionFail(handle, reason)
    handle.phase, handle.failure = "failed", reason
    return "failed"
end

local function CollectRootMap(handle, work)
    local name = MAP_ORDER[handle.mapIndex]
    local map = handle.maps[name]
    if map == nil then
        handle.mapIndex, handle.mapCursor = handle.mapIndex + 1, nil
        handle.mapCounts[name] = 0
        return "ok"
    end
    while true do
        if Exhausted(work.budget) then return "pending" end
        local ok, key = pcall(next, map, handle.mapCursor)
        if not ok then return AdmissionFail(handle, "ROOT_MAP_MALFORMED") end
        if key == nil then
            handle.mapIndex, handle.mapCursor = handle.mapIndex + 1, nil
            return "ok"
        end
        handle.mapCursor = key
        Charge(work, "rootMapEdges", 1)
        handle.rootMapEdges = handle.rootMapEdges + 1
        if handle.rootMapEdges > BUDGET.rootMapEdges then
            return AdmissionFail(handle, "ROOT_MAP_LIMIT")
        end
        local typedKey, kind = TypedKey(key)
        if not typedKey then return AdmissionFail(handle, "ROOT_MAP_KEY_INVALID") end
        Charge(work, "bytesInspected", #typedKey)
        handle.mapCounts[name] = (handle.mapCounts[name] or 0) + 1
        local limitReason = name == "tombstone" and "TOMBSTONE_SET_LIMIT"
            or name == "barrier" and "BARRIER_SET_LIMIT" or "ROOT_SLOT_LIMIT"
        if handle.mapCounts[name] > BUDGET.rootMapKeys then
            return AdmissionFail(handle, limitReason)
        end
        local slot = handle.slots[typedKey]
        if not slot then
            slot = {key=typedKey, id=key, kind=kind}
            handle.slots[typedKey] = slot
            handle.slotCount = handle.slotCount + 1
            if handle.slotCount > BUDGET.rows then
                return AdmissionFail(handle, limitReason)
            end
            handle.slotVector[handle.slotCount] = slot
        end
        slot[name] = rawget(map, key)
    end
end

local function AdmitSlot(handle, slot, work)
    if slot.tombstone ~= nil then
        if not slot.tombstoneVerdict then
            local state, view = ClassifyTombstone(slot.tombstone, slot, work)
            slot.tombstoneVerdict = {state=state, view=view, raw=slot.tombstone}
        end
        local verdict = NewVerdict(slot, "INVALIDATED", "TOMBSTONE_RESERVATION")
        if slot.tombstoneVerdict.state == "CURRENT_DENY" then
            verdict.state, verdict.reason = "TOMBSTONED", "TOMBSTONE_CURRENT_DENY"
        end
        verdict.reservation = "TOMBSTONE_" .. slot.tombstoneVerdict.state
        verdict.tombstone = slot.tombstoneVerdict
        verdict.raw = slot.overlay
        verdict.source = "tombstone"
        return verdict
    end
    if slot.walker == nil then
        local raw, source = SelectRawSource(slot)
        slot.selectedSource = source
        if raw == nil then
            return NewVerdict(slot, "UNADMITTED", "no source")
        end
        local future = FutureSchemaOf(raw)
        if future then
            local verdict = NewVerdict(slot, "READ_ONLY_FUTURE_SCHEMA", "FUTURE_SCHEMA")
            verdict.schemaVersion = future
            verdict.reservation = "FUTURE_SCHEMA"
            verdict.raw = raw
            verdict.source = source
            Charge(work, "nodes", 1)
            return verdict
        end
        slot.walker = NewWalker(raw, {})
        Charge(work, "rows", 1)
    end
    local status = WalkRow(slot.walker, work)
    if status == "pending" then return nil end
    return FinishRowVerdict(slot.walker, slot, slot.selectedSource, {})
end

local function ProcessRows(handle, work)
    while handle.rowIndex <= handle.slotCount do
        if Exhausted(work.budget) then return "pending" end
        local slot = handle.slotVector[handle.rowIndex]
        local verdict = AdmitSlot(handle, slot, work)
        if not verdict then return "pending" end
        slot.walker = nil
        if slot.barrier ~= nil then
            verdict.barrier = ClassifyBarrier(slot.barrier, slot, work)
            verdict.barrier.raw = slot.barrier
            Charge(work, "barriers", 1)
        end
        verdict.overlayRaw = slot.overlay
        verdict.bundledRaw = slot.bundled
        handle.verdicts[slot.key] = verdict
        handle.rowIndex = handle.rowIndex + 1
    end
    return "ok"
end

local function BuildIndexes(handle, work)
    while handle.indexIndex < handle.slotCount do
        if Exhausted(work.budget) then return "pending" end
        handle.indexIndex = handle.indexIndex + 1
        local slot = handle.slotVector[handle.indexIndex]
        local verdict = handle.verdicts[slot.key]
        if verdict and verdict.snapshot then
            IndexAdd(handle.index, handle.verdicts, verdict, work)
        end
        Charge(work, "indexNodes", 1)
    end
    return "ok"
end

local function ComputeCounts(handle)
    local counts = {bundled=handle.mapCounts.bundled or 0,
        overlay=0, tombstones=0, barriers=0, available=0, invalid=0, future=0}
    for _, slot in ipairs(handle.slotVector) do
        local verdict = handle.verdicts[slot.key]
        if verdict.snapshot then counts.available = counts.available + 1
        elseif verdict.state == "READ_ONLY_FUTURE_SCHEMA" then counts.future = counts.future + 1
        elseif verdict.state == "INVALIDATED" and not verdict.tombstone then
            counts.invalid = counts.invalid + 1
        end
        if verdict.tombstone then counts.tombstones = counts.tombstones + 1 end
        if verdict.overlayRaw ~= nil then counts.overlay = counts.overlay + 1 end
        if verdict.barrier then counts.barriers = counts.barriers + 1 end
    end
    return counts
end

local function OverlayVectors(handle)
    local overlayKeys, tombstoneKeys = {}, {}
    for _, slot in ipairs(handle.slotVector) do
        local verdict = handle.verdicts[slot.key]
        if verdict.source == "overlay" and verdict.snapshot then
            overlayKeys[#overlayKeys + 1] = slot.key
        end
        if verdict.tombstone then tombstoneKeys[#tombstoneKeys + 1] = slot.key end
    end
    return overlayKeys, tombstoneKeys
end

-- Known-field baseline equivalence: an overlay that duplicates its bundled
-- row may be pruned only when it owns no unknown evidence.
local function BaselineEquivalent(snapshot, hasUnknown, overlayRaw, bundledRaw, slot)
    if not (snapshot and bundledRaw) or hasUnknown or RawLocalMarker(overlayRaw) then
        return false
    end
    local bundledVerdict = AdmitRaw(bundledRaw, {key=slot.key, id=slot.id,
        kind=slot.kind}, "bundled", {})
    if not bundledVerdict.snapshot then return false end
    local left, right = DeepCopy(snapshot), DeepCopy(bundledVerdict.snapshot)
    for _, key in ipairs({"isMine", "ownerVerified", "needsFullBuild", "linkHash",
        "fingerprintHash", "ordinaryCompletenessReason", "claimedOwnerKey",
        "relaySender"}) do
        left[key], right[key] = nil, nil
    end
    return DeepEqual(left, right)
end

local function RunFaultInjector(boundary)
    if ST.faultInjector then ST.faultInjector(boundary) end
end

-- Notifications run only after the new root is public. A failing subscriber,
-- scheduler, or logger cannot undo or replay the committed mutation; it is
-- recorded as one bounded NOTIFICATION_FAILED receipt.
local function NotifyBuild(reason, id, scope)
    local ok = pcall(function()
        RunFaultInjector("notify")
        local revisions = Nexus and Nexus.Revisions
        if revisions and type(revisions.Advance) == "function" then
            revisions.Advance(revisions.BUILD_LIBRARY_CHANGED, {
                reason=reason, scope=scope or (id ~= nil and "record" or "all"), id=id,
            })
        end
    end)
    if not ok then
        ST.debugStats.notificationFailures = ST.debugStats.notificationFailures + 1
    end
end

local function PublishRoot(handle)
    local db = handle.token.databaseIdentity
    local classification, metaReason, meta, metaVersion = ClassifyMetadata(db)
    if classification == "invalid" then return AdmissionFail(handle, metaReason) end
    local catalogVersion = tostring(ST.bundled and ST.bundled.catalogVersion or "unversioned")
    local needsMigration = meta == nil
        or tonumber(rawget(meta, "schemaVersion")) ~= STORAGE_SCHEMA_VERSION
        or tostring(rawget(meta, "catalogVersion") or "") ~= catalogVersion
    local prune = {}
    if needsMigration then
        for _, slot in ipairs(handle.slotVector) do
            local verdict = handle.verdicts[slot.key]
            if verdict.source == "overlay" and verdict.snapshot
                and BaselineEquivalent(verdict.snapshot, verdict.hasUnknown,
                    verdict.overlayRaw, verdict.bundledRaw, slot) then
                prune[#prune + 1] = slot
            end
        end
    end
    local drift = TokenDrifted(handle.token)
    if drift then return AdmissionFail(handle, drift) end
    ST.preparationEpoch = ST.preparationEpoch + 1
    local ok = pcall(function()
        RunFaultInjector("before-commit")
        if rawget(db, "communityBuilds") == nil then rawset(db, "communityBuilds", {}) end
        if rawget(db, "syncTombstones") == nil then rawset(db, "syncTombstones", {}) end
        if meta == nil then
            meta = {}
            rawset(db, "buildCatalog", meta)
        end
        if needsMigration then
            rawset(meta, "schemaVersion", STORAGE_SCHEMA_VERSION)
            rawset(meta, "catalogVersion", catalogVersion)
            rawset(meta, "sourceVersion", tostring(ST.bundled
                and ST.bundled.sourceVersion or "unknown"))
            local overlay = rawget(db, "communityBuilds")
            for _, slot in ipairs(prune) do
                rawset(overlay, slot.id, nil)
                slot.overlay = nil
                local replacement = AdmitRaw(slot.bundled, slot, "bundled", {})
                replacement.overlayRaw, replacement.bundledRaw = nil, slot.bundled
                IndexRemove(handle.index, handle.verdicts, slot.key)
                handle.verdicts[slot.key] = replacement
                IndexAdd(handle.index, handle.verdicts, replacement, nil)
            end
        end
        RunFaultInjector("after-raw-write")
    end)
    if not ok then
        ST.debugStats.protectedFailures = ST.debugStats.protectedFailures + 1
        return AdmissionFail(handle, "PROTECTED_COMMIT_FAILED")
    end
    handle.token = CaptureToken(db)
    handle.counts = ComputeCounts(handle)
    local overlayKeys, tombstoneKeys = OverlayVectors(handle)
    ST.generation = ST.generation + 1
    ST.semanticGeneration = ST.semanticGeneration + 1
    ST.published = {
        generation=ST.generation, token=handle.token, rows=handle.verdicts,
        slots=handle.slots, slotVector=handle.slotVector, slotCount=handle.slotCount,
        index=handle.index, counts=handle.counts, overlayKeys=overlayKeys,
        tombstoneKeys=tombstoneKeys, catalogVersion=catalogVersion,
        schemaVersion=metaVersion or STORAGE_SCHEMA_VERSION,
        migrated=needsMigration, redundantRemoved=#prune,
    }
    ST.rootState, ST.rootReason = "ROOT_ADMITTED", nil
    ST.activeCursors = {}
    ST.debugStats.relatedIndexRebuilds = ST.debugStats.relatedIndexRebuilds + 1
    ST.debugStats.authorIndexRebuilds = ST.debugStats.authorIndexRebuilds + 1
    handle.phase = "published"
    return "published"
end

local function PumpAdmission(handle)
    local work = NewWork(handle.counters)
    handle.pumps = handle.pumps + 1
    ST.debugStats.rootPumps = ST.debugStats.rootPumps + 1
    local result
    if handle.phase == "capture" then
        local db = handle.token.databaseIdentity
        local classification, reason, _, version = ClassifyMetadata(db)
        if classification == "invalid" then
            result = AdmissionFail(handle, reason)
        elseif classification == "future" then
            handle.phase, handle.futureSchema = "future", version
            result = "future"
        else
            local okOverlay, overlay = PlainMapOrNil(rawget(db, "communityBuilds"))
            local okTomb, tombstones = PlainMapOrNil(rawget(db, "syncTombstones"))
            local okEvict, evictions = PlainMapOrNil(rawget(db, "communityRetentionEvictions"))
            local okBundle, bundledMap = PlainMapOrNil(ST.baseline)
            if not (okOverlay and okTomb and okEvict and okBundle) then
                result = AdmissionFail(handle, "ROOT_MAP_MALFORMED")
            else
                handle.maps = {overlay=overlay, bundled=bundledMap,
                    tombstone=tombstones, barrier=evictions}
                handle.phase = "collect"
                Charge(work, "nodes", 1)
                result = "ok"
            end
        end
    end
    while handle.phase == "collect" and result ~= "pending" do
        if handle.mapIndex > #MAP_ORDER then
            handle.sort = NewSort(handle.slotVector, handle.slotCount, CompareSlots)
            handle.phase = "sort"
        else
            result = CollectRootMap(handle, work)
        end
    end
    if handle.phase == "sort" and result ~= "pending" then
        if SortStep(handle.sort, work) then
            handle.slotVector = handle.sort.items
            handle.phase, handle.rowIndex = "rows", 1
        else
            result = "pending"
        end
    end
    if handle.phase == "rows" and result ~= "pending" then
        result = ProcessRows(handle, work)
        if result == "ok" then handle.phase = "index" end
    end
    if handle.phase == "index" and result ~= "pending" then
        result = BuildIndexes(handle, work)
        if result == "ok" then handle.phase = "publish" end
    end
    if handle.phase == "publish" and result ~= "pending" then
        result = PublishRoot(handle)
    end
    ClosePump(work)
    if result == "pending" and not work.progress then
        result = AdmissionFail(handle, "FRONTIER_NO_PROGRESS")
    end
    return result
end

local function SummaryOf(handle, state, reason)
    local counts = handle and handle.counts or {}
    local mapCounts = handle and handle.mapCounts or {}
    local published = ST.published
    return {
        migrated=published and published.migrated or false,
        bundled=counts.bundled or mapCounts.bundled or 0,
        overlay=counts.overlay or mapCounts.overlay or 0,
        tombstones=counts.tombstones or mapCounts.tombstone or 0,
        merged=counts.available or 0,
        redundantRemoved=published and published.redundantRemoved or 0,
        schemaVersion=state == "ROOT_READ_ONLY_FUTURE_SCHEMA"
            and (handle and handle.futureSchema) or STORAGE_SCHEMA_VERSION,
        catalogVersion=tostring(ST.bundled and ST.bundled.catalogVersion or "unversioned"),
        readOnly=state ~= "ROOT_ADMITTED",
        state=state, reason=reason,
        generation=ST.generation,
        pumps=handle and handle.pumps or 0,
    }
end

local function FinishAdmission(result)
    local handle = ST.candidate
    if result == "pending" then return {state="pending", pumps=handle.pumps} end
    ST.candidate = nil
    ST.lastCounters = handle.counters
    if result == "published" then
        ST.lastInitSummary = SummaryOf(handle, "ROOT_ADMITTED")
        NotifyBuild("catalog initialized")
        return {state="ROOT_ADMITTED", pumps=handle.pumps, generation=ST.generation}
    elseif result == "future" then
        ST.rootState, ST.rootReason = "ROOT_READ_ONLY_FUTURE_SCHEMA", "FUTURE_SCHEMA"
        ST.published = nil
        ST.futureToken = handle.token
        ST.lastInitSummary = SummaryOf(handle, "ROOT_READ_ONLY_FUTURE_SCHEMA", "FUTURE_SCHEMA")
        return {state="ROOT_READ_ONLY_FUTURE_SCHEMA", reason="FUTURE_SCHEMA", pumps=handle.pumps}
    end
    Invalidate(handle.failure or "ROOT_CONSTRUCTION_FAILED")
    ST.lastInitSummary = SummaryOf(handle, "ROOT_INVALIDATED", ST.rootReason)
    return {state="ROOT_INVALIDATED", reason=ST.rootReason, pumps=handle.pumps}
end

------------------------------------------------------------------------
-- Public: root binding
------------------------------------------------------------------------

function Catalog.BeginRootAdmission(database, bundle)
    local db = type(database) == "table" and database or {}
    local bundled = type(bundle) == "table" and bundle
        or type(Nexus.BundledBuilds) == "table" and Nexus.BundledBuilds or {}
    local baseline = type(bundled.builds) == "table" and bundled.builds or {}
    ST.db, ST.bundled, ST.baseline = db, bundled, baseline
    ST.published = nil
    ST.rootState, ST.rootReason = "ROOT_ADMISSION_PENDING", nil
    ST.activeClaim, ST.activeCursors, ST.activeMaintenance = nil, {}, nil
    ST.candidate = NewAdmission(db)
    ST.debugStats.rootAdmissions = ST.debugStats.rootAdmissions + 1
    return {state="pending", pumps=0}
end

function Catalog.PumpRootAdmission()
    local handle = ST.candidate
    if not handle then return {state=ST.rootState, reason=ST.rootReason, pumps=0} end
    local drift = TokenDrifted(handle.token)
    if drift then
        handle.phase, handle.failure = "failed", drift
        return FinishAdmission("failed")
    end
    return FinishAdmission(PumpAdmission(handle))
end

function Catalog.CancelRootAdmission()
    if ST.candidate then
        ST.candidate = nil
        ST.rootState, ST.rootReason = "ROOT_UNBOUND", "CANCELLED"
        ST.published = nil
    end
    return {state=ST.rootState, reason=ST.rootReason}
end

function Catalog.Init(database, bundle)
    ST.debugStats.initCalls = ST.debugStats.initCalls + 1
    local nextDb = type(database) == "table" and database or {}
    local nextBundled = type(bundle) == "table" and bundle
        or type(Nexus.BundledBuilds) == "table" and Nexus.BundledBuilds or {}
    local nextBaseline = type(nextBundled.builds) == "table" and nextBundled.builds or {}
    if ST.candidate == nil and ST.db == nextDb and ST.bundled == nextBundled
        and ST.baseline == nextBaseline
        and (ST.rootState == "ROOT_ADMITTED" or ST.rootState == "ROOT_READ_ONLY_FUTURE_SCHEMA")
        and ST.lastInitSummary then
        local token = ST.published and ST.published.token or ST.futureToken
        if token and not TokenDrifted(token)
            and token.ownerIdentity == CurrentOwnerKey() then
            ST.debugStats.fastPathHits = ST.debugStats.fastPathHits + 1
            local summary = DeepCopy(ST.lastInitSummary)
            summary.migrated, summary.redundantRemoved = false, 0
            return summary
        end
    end
    ST.debugStats.rebinds = ST.debugStats.rebinds + 1
    if Nexus.LoadoutEvidence and Nexus.LoadoutEvidence.Init then
        Nexus.LoadoutEvidence.Init(nextDb)
    end
    Catalog.BeginRootAdmission(nextDb, nextBundled)
    local result
    for _ = 1, 100000000 do
        result = Catalog.PumpRootAdmission()
        if result.state ~= "pending" then break end
    end
    return DeepCopy(ST.lastInitSummary or SummaryOf(nil, ST.rootState, ST.rootReason))
end

------------------------------------------------------------------------
-- Public: diagnostics and state
------------------------------------------------------------------------

function Catalog.Budget()
    return {totals=DeepCopy(BUDGET), slices=DeepCopy(SLICE)}
end

function Catalog.BudgetCounters()
    local counters = ST.candidate and ST.candidate.counters or ST.lastCounters
    if not counters then return NewCounters() end
    return DeepCopy(counters)
end

function Catalog.RootState()
    if ST.rootState == "ROOT_ADMITTED" and ST.published then
        local drift = TokenDrifted(ST.published.token)
        if drift then Invalidate(drift) end
    end
    return {
        state=ST.rootState, reason=ST.rootReason, generation=ST.generation,
        schemaVersion=STORAGE_SCHEMA_VERSION,
        catalogVersion=tostring(ST.bundled and ST.bundled.catalogVersion or "unversioned"),
        bindingGeneration=ST.bindingGeneration,
        committedMutationRevision=ST.committedMutationRevision,
        preparationEpoch=ST.preparationEpoch,
        reservationEpoch=ST.reservationEpoch,
        semanticGeneration=ST.semanticGeneration,
        candidate=ST.candidate ~= nil,
    }
end

local function Occupancy(verdict)
    if not verdict then return "VACANT" end
    if verdict.snapshot then return "OCCUPIED" end
    if verdict.state == "UNADMITTED" and not verdict.barrier then return "VACANT" end
    return "BLOCKED"
end

function Catalog.AuthorityState(id)
    local root = Gate()
    local typedKey = TypedKey(id)
    local out = {state="UNADMITTED", reason=ST.rootState, typedKey=typedKey,
        occupancy="BLOCKED", generation=ST.generation}
    if not root then return out end
    local verdict = typedKey and root.rows[typedKey] or nil
    if not verdict then
        out.reason = typedKey and "no source" or "INVALID_TYPED_ID"
        out.occupancy = typedKey and "VACANT" or "BLOCKED"
        return out
    end
    out.state, out.reason, out.source = verdict.state, verdict.reason, verdict.source
    out.reservation = verdict.reservation
    if verdict.barrier then out.barrier = verdict.barrier.state end
    out.schemaVersion = verdict.schemaVersion
    out.semantic = verdict.semantic and DeepCopy(verdict.semantic) or nil
    out.fingerprint = verdict.exactFingerprint
    out.occupancy = Occupancy(verdict)
    return out
end

function Catalog.IsAdmittedRecord(id)
    local root = Gate()
    local typedKey = TypedKey(id)
    local verdict = root and typedKey and root.rows[typedKey] or nil
    return verdict ~= nil and verdict.snapshot ~= nil
end

function Catalog.TrustedServerTime()
    return TrustedServerTime()
end

function Catalog.InstallFaultInjector(callback)
    ST.faultInjector = type(callback) == "function" and callback or nil
    return true
end

function Catalog.DebugStats()
    return DeepCopy(ST.debugStats)
end

function Catalog.SchemaVersion()
    return STORAGE_SCHEMA_VERSION
end

-- Exact bound database identity for maintenance owners. It is the raw table
-- the caller already holds; the catalog exposes no other raw reference.
function Catalog.BoundDatabase()
    return ST.db
end

function Catalog.CatalogVersion()
    Gate()
    return tostring(ST.bundled and ST.bundled.catalogVersion or "unversioned")
end

function Catalog.HasBaseline(id)
    Gate()
    return type(ST.baseline) == "table" and type(rawget(ST.baseline, id)) == "table"
end

------------------------------------------------------------------------
-- Public: reads
------------------------------------------------------------------------

local function RestoreId(copy, verdict)
    if type(copy) == "table" and copy.id == nil then copy.id = verdict.id end
    return copy
end

local function PublicRecord(verdict)
    if not (verdict and verdict.snapshot) then return nil end
    return RestoreId(DeepCopy(verdict.snapshot), verdict)
end

local function SyncEligible(verdict)
    return verdict.source == "overlay" and verdict.savedKind == "ordinary"
        and verdict.verifiedOwner ~= nil and verdict.complete == true
end

local function Summarize(verdict)
    local snapshot = verdict.snapshot
    if not snapshot then return nil end
    local out = {}
    for _, key in ipairs(SUMMARY_FIELDS) do
        local value = snapshot[key]
        if value ~= nil then out[key] = DeepCopy(value) end
    end
    out.echoCount = verdict.complete and (tonumber(snapshot.echoCount) or 0) or 0
    out.loadoutAvailable = verdict.complete
    out.ordinaryComplete = verdict.complete
    out.ordinaryCompletenessReason = snapshot.ordinaryCompletenessReason or "unavailable"
    out.source = verdict.source
    out.syncDelta = SyncEligible(verdict)
    return RestoreId(out, verdict)
end

local function VerdictOf(root, id)
    local typedKey = TypedKey(id)
    return typedKey and root.rows[typedKey] or nil, typedKey
end

function Catalog.Get(id)
    local root = Gate()
    if not root then return nil, nil end
    local verdict = VerdictOf(root, id)
    if not (verdict and verdict.snapshot) then return nil, nil end
    return PublicRecord(verdict), verdict.source
end

function Catalog.GetSummary(id)
    local root = Gate()
    if not root then return nil, nil end
    local verdict = VerdictOf(root, id)
    if not (verdict and verdict.snapshot) then return nil, nil end
    return Summarize(verdict), verdict.source
end

function Catalog.Count()
    local root = Gate()
    return root and root.counts.available or 0
end

function Catalog.Status()
    local root = Gate()
    local counts = root and root.counts or {}
    return {
        bundledCount=counts.bundled or 0,
        overlayCount=counts.overlay or 0,
        tombstoneCount=counts.tombstones or 0,
        availableCount=counts.available or 0,
        invalidCount=counts.invalid or 0,
        futureCount=counts.future or 0,
        barrierCount=counts.barriers or 0,
        catalogVersion=tostring(ST.bundled and ST.bundled.catalogVersion or "unversioned"),
        readOnly=root == nil,
        state=ST.rootState, reason=ST.rootReason,
        generation=ST.generation,
    }
end

local function CopyCost(value, seen)
    seen = seen or {}
    if type(value) ~= "table" then return ScalarBytes(value), 1 end
    if seen[value] then return 1, 0 end
    seen[value] = true
    local bytes, nodes = 1, 1
    for key, child in pairs(value) do
        local childBytes, childNodes = CopyCost(child, seen)
        bytes = bytes + ScalarBytes(key) + childBytes
        nodes = nodes + childNodes
    end
    return bytes, nodes
end

-- Complete detached collections are returned only within the one-call
-- limits; otherwise the caller must use the matching cursor family.
local function BoundedCollection(root, filter, project)
    local out, rows, bytes, nodes = {}, 0, 0, 0
    for _, slot in ipairs(root.slotVector) do
        local verdict = root.rows[slot.key]
        if verdict and filter(verdict) then
            rows = rows + 1
            if rows > BUDGET.oneCallRows then return nil, "CURSOR_REQUIRED" end
            local projected = project(verdict)
            local itemBytes, itemNodes = CopyCost(projected)
            bytes, nodes = bytes + itemBytes, nodes + itemNodes
            if bytes > BUDGET.oneCallBytes or nodes > BUDGET.oneCallNodes then
                return nil, "CURSOR_REQUIRED"
            end
            out[verdict.id] = projected
        end
    end
    return out
end

local function Admitted(verdict) return verdict.snapshot ~= nil end

function Catalog.All()
    local root, why = Gate()
    if not root then return nil, why end
    return BoundedCollection(root, Admitted, PublicRecord)
end

function Catalog.Summaries()
    local root, why = Gate()
    if not root then return nil, why end
    ST.debugStats.summarySnapshots = ST.debugStats.summarySnapshots + 1
    return BoundedCollection(root, Admitted, Summarize)
end

function Catalog.DeltaSummaries()
    local root, why = Gate()
    if not root then return nil, why end
    return BoundedCollection(root, SyncEligible, Summarize)
end

function Catalog.DeltaSnapshot()
    local root, why = Gate()
    if not root then return nil, why end
    return BoundedCollection(root, SyncEligible, PublicRecord)
end

-- Diagnostic export of every raw overlay slot, including rows shadowed by a
-- newer bundled row. A shadowed row is re-proved through the same bounded
-- walker before it is copied; nothing raw escapes.
local function OverlayExport(verdict)
    if verdict.source == "overlay" and verdict.snapshot then
        return PublicRecord(verdict)
    end
    local slot = {key=verdict.typedKey, id=verdict.id, kind=verdict.kind}
    local shadowed = AdmitRaw(verdict.overlayRaw, slot, "overlay", {})
    if shadowed.snapshot then return PublicRecord(shadowed) end
    return {id=verdict.id, state="INVALIDATED", reason=shadowed.reason}
end

function Catalog.OverlaySnapshot()
    local root, why = Gate()
    if not root then return nil, why end
    return BoundedCollection(root, function(verdict)
        return type(verdict.overlayRaw) == "table"
    end, OverlayExport)
end

local function TombstoneView(verdict)
    local view = verdict.tombstone and verdict.tombstone.view or nil
    if not view then return nil end
    return {
        state=view.state, stamp=view.stamp, author=view.author,
        ownerKey=view.ownerKey, ownerVerified=view.ownerVerified,
        sourceKind=view.sourceKind, localOwned=view.localOwned,
    }
end

local function CompatTombstone(verdict)
    local view = TombstoneView(verdict)
    if not view then return nil end
    return {stamp=view.stamp, author=view.author, ownerKey=view.ownerKey,
        ownerVerified=view.ownerVerified == true or nil}
end

function Catalog.TombstoneSnapshot()
    local root, why = Gate()
    if not root then return nil, why end
    return BoundedCollection(root, function(verdict)
        return verdict.tombstone ~= nil
    end, CompatTombstone)
end

function Catalog.ForEach(visitor)
    if type(visitor) ~= "function" then return 0 end
    local all, why = Catalog.All()
    if not all then return 0, why end
    local root = ST.published
    local count = 0
    for id, record in pairs(all) do
        count = count + 1
        visitor(id, record)
        if ST.published ~= root then return count, "STALE_CURSOR" end
    end
    return count
end

function Catalog.SyncState(id)
    local root = Gate()
    local verdict = root and VerdictOf(root, id) or nil
    return {
        id=id,
        visible=verdict and PublicRecord(verdict) or nil,
        delta=verdict and SyncEligible(verdict) and PublicRecord(verdict) or nil,
        tombstone=verdict and CompatTombstone(verdict) or nil,
        catalogVersion=tostring(ST.bundled and ST.bundled.catalogVersion or "unversioned"),
    }
end

function Catalog.TombstoneState(id)
    local root = Gate()
    local verdict = root and VerdictOf(root, id) or nil
    local view = verdict and TombstoneView(verdict) or nil
    if not view then
        return {state="NONE", stamp=0, author="", localOwned=false}
    end
    return view
end

function Catalog.BarrierState(id)
    local root = Gate()
    local verdict = root and VerdictOf(root, id) or nil
    local barrier = verdict and verdict.barrier or nil
    if not barrier then return {state="BARRIER_NONE", blocked=false} end
    return {state=barrier.state, blocked=true, revision=barrier.revision,
        recordedAt=barrier.recordedAt,
        receiptAtServerTime=barrier.receiptAtServerTime,
        readmittedAtServerTime=barrier.readmittedAtServerTime}
end

-- Stateless generation-bound steps over the immutable overlay and tombstone
-- vectors: each call examines at most one slot.
local function VectorStep(vector, cursorId, root)
    local ordinal = 0
    if cursorId ~= nil then
        local typedKey = TypedKey(cursorId)
        for index, key in ipairs(vector) do
            if key == typedKey then ordinal = index; break end
        end
        if ordinal == 0 then return nil end
    end
    local key = vector[ordinal + 1]
    return key and root.rows[key] or nil
end

function Catalog.SyncDeltaNext(cursor)
    local root = Gate()
    if not root then return nil, nil, true end
    local verdict = VectorStep(root.overlayKeys, cursor, root)
    if not verdict then return nil, nil, true end
    local record = SyncEligible(verdict) and PublicRecord(verdict) or nil
    return verdict.id, record, false
end

function Catalog.TombstoneNext(cursor)
    local root = Gate()
    if not root then return nil, nil, true end
    local verdict = VectorStep(root.tombstoneKeys, cursor, root)
    if not verdict then return nil, nil, true end
    return verdict.id, TombstoneView(verdict), false
end

function Catalog.BarrierNext(cursor)
    local root = Gate()
    if not root then return nil, nil, true end
    local ordinal = 0
    if cursor ~= nil then
        local typedKey = TypedKey(cursor)
        for index, slot in ipairs(root.slotVector) do
            if slot.key == typedKey then ordinal = index; break end
        end
        if ordinal == 0 then return nil, nil, true end
    end
    for index = ordinal + 1, root.slotCount do
        local verdict = root.rows[root.slotVector[index].key]
        if verdict and verdict.barrier then
            return verdict.id, Catalog.BarrierState(verdict.id), false
        end
    end
    return nil, nil, true
end

function Catalog.RecordRevision(id)
    Gate()
    return ST.recordEpoch, ST.recordRevisions[id] or 0
end

function Catalog.ExactFingerprintRevision(fingerprint)
    Gate()
    if type(fingerprint) ~= "string" or fingerprint == "" then
        return ST.exactEpoch, 0
    end
    return ST.exactEpoch, ST.exactRevisions[fingerprint] or 0
end

------------------------------------------------------------------------
-- Public: allocation occupancy and claims
------------------------------------------------------------------------

local function Advisory(occupancy)
    return {blocked=occupancy ~= "VACANT", generation=ST.generation,
        reservationEpoch=ST.reservationEpoch}
end

function Catalog.AllocationOccupancy(id)
    local root = Gate()
    if not root then return "opaque", nil, Advisory("BLOCKED") end
    local verdict, typedKey = VerdictOf(root, id)
    if not typedKey then return "opaque", nil, Advisory("BLOCKED") end
    if not verdict then return "absent", nil, Advisory("VACANT") end
    local occupancy = Occupancy(verdict)
    if verdict.tombstone then return "tombstone", nil, Advisory(occupancy) end
    if not verdict.snapshot then return "opaque", nil, Advisory(occupancy) end
    if verdict.bundledRaw ~= nil then
        return "bundled", PublicRecord(verdict), Advisory(occupancy)
    end
    return "visible", PublicRecord(verdict), Advisory(occupancy)
end

local function AdvanceReservation()
    ST.reservationEpoch = ST.reservationEpoch + 1
end

local function IssueClaim(kind, typedKey, id, extra)
    if ST.activeClaim and ST.claimRegistry[ST.activeClaim] then
        return nil, "CLAIM_ACTIVE"
    end
    local claim = {kind=kind, typedKey=typedKey, generation=ST.generation,
        reservationEpoch=ST.reservationEpoch}
    ST.claimRegistry[claim] = {kind=kind, typedKey=typedKey, id=id,
        generation=ST.generation, reservationEpoch=ST.reservationEpoch,
        extra=extra}
    ST.activeClaim = claim
    AdvanceReservation()
    ST.debugStats.claimsIssued = ST.debugStats.claimsIssued + 1
    return claim
end

local function ReleaseClaim(claim)
    if ST.claimRegistry[claim] then
        ST.claimRegistry[claim] = nil
        if ST.activeClaim == claim then ST.activeClaim = nil end
        AdvanceReservation()
        return true
    end
    return false
end

function Catalog.BeginAllocationClaim(id)
    local root, why = Gate()
    if not root then return nil, why end
    local verdict, typedKey = VerdictOf(root, id)
    if not typedKey then return nil, "INVALID_TYPED_ID" end
    if Occupancy(verdict) ~= "VACANT" then return nil, "OCCUPIED" end
    return IssueClaim("allocation", typedKey, id)
end

function Catalog.CancelAllocationClaim(claim)
    return ReleaseClaim(claim)
end

function Catalog.BeginTombstoneReadmissionClaim(id)
    local root, why = Gate()
    if not root then return nil, why end
    local verdict, typedKey = VerdictOf(root, id)
    if not typedKey then return nil, "INVALID_TYPED_ID" end
    if not (verdict and verdict.tombstone) then
        return nil, "TOMBSTONE_RESERVATION_ABSENT"
    end
    if CurrentOwnerKey() == nil then return nil, "LOCAL_OWNER_REQUIRED" end
    return IssueClaim("readmission", typedKey, id, {
        tombstoneRaw=verdict.tombstone.raw,
        reservation=verdict.tombstone.state,
    })
end

------------------------------------------------------------------------
-- Mutation transactions
------------------------------------------------------------------------

local function TupleKey(row)
    return tostring(row.spellId) .. ":" .. tostring(row.quality) .. ":"
        .. (row.locked and "1" or "0") .. ":" .. (row.origin or "inline")
end

-- Construct the detached destination row: exact V1 known fields, the
-- existing unknown owners at their original scope, and every incoming
-- unknown field that does not overwrite an existing owner.
local function BuildDestination(verdict, walker, existing)
    local destination = {}
    for key, value in pairs(verdict.snapshot) do
        if FIELD[key] and FIELD[key].kind ~= "evidence" then
            destination[key] = DeepCopy(value)
        end
    end
    destination.id = verdict.id
    local existingUnknown = existing and existing.unknown or {}
    for key, value in pairs(existingUnknown) do destination[key] = DeepCopy(value) end
    for key, value in pairs(walker.unknown) do
        if destination[key] == nil then destination[key] = DeepCopy(value) end
    end
    local existingTupleUnknown = {}
    for _, row in ipairs(existing and existing.grouped or {}) do
        if row.unknown ~= nil then existingTupleUnknown[TupleKey(row)] = row.unknown end
    end
    local echoes, lockedEchoes
    for _, row in ipairs(verdict.grouped or {}) do
        local echo = {spellId=row.spellId, quality=row.quality, stacks=row.stacks}
        if row.locked then echo.locked = true end
        local unknown = row.unknown or existingTupleUnknown[TupleKey(row)]
        if unknown then
            -- The tuple keeps owning its exact unknown subtree in the
            -- published verdict as well as in the durable destination.
            row.unknown = unknown
            verdict.hasUnknown = true
            for key, value in pairs(unknown) do
                if echo[key] == nil then echo[key] = DeepCopy(value) end
            end
        end
        if row.origin == "lockedArray" then
            lockedEchoes = lockedEchoes or {}
            lockedEchoes[#lockedEchoes + 1] = echo
        else
            echoes = echoes or {}
            echoes[#echoes + 1] = echo
        end
        existingTupleUnknown[TupleKey(row)] = nil
    end
    local seen = walker.evidenceSeen or {}
    -- An explicitly empty evidence array stays an empty known field.
    if echoes then destination.echoes = echoes
    elseif seen.ordinary then destination.echoes = {} end
    if lockedEchoes then destination.lockedEchoes = lockedEchoes
    elseif seen.locked then destination.lockedEchoes = {} end
    if next(existingTupleUnknown) ~= nil then
        return nil, "UNKNOWN_TUPLE_SCHEMA_MIGRATION_REQUIRED"
    end
    return destination
end

local function CompactDestination(destination)
    local compaction = Nexus and Nexus.DataCompaction
    local evidence = Nexus and Nexus.LoadoutEvidence
    local compacted = false
    if compaction and type(compaction.Enabled) == "function"
        and compaction.Enabled(ST.db)
        and type(compaction.CompactBuildRow) == "function" then
        ST.debugStats.compactionCalls = ST.debugStats.compactionCalls + 1
        local ok, changed = pcall(compaction.CompactBuildRow, destination)
        compacted = ok
        if ok and changed then
            ST.debugStats.compactionWrites = ST.debugStats.compactionWrites + 1
        end
    end
    if not compacted and evidence and type(evidence.Reference) == "function"
        and type(destination.echoes) == "table" and #destination.echoes > 0 then
        ST.debugStats.referenceCalls = ST.debugStats.referenceCalls + 1
        local ok, reference, created = pcall(evidence.Reference, destination,
            "echoes", "evidenceKey")
        if ok and reference and created then
            ST.debugStats.referenceStores = ST.debugStats.referenceStores + 1
        end
    end
end

local function BumpRevisions(verdict, previous, id)
    ST.generation = ST.generation + 1
    ST.committedMutationRevision = ST.committedMutationRevision + 1
    ST.semanticGeneration = ST.semanticGeneration + 1
    ST.recordRevisions[id] = (ST.recordRevisions[id] or 0) + 1
    ST.exactRevisionClock = ST.exactRevisionClock + 1
    local before = previous and previous.snapshot and previous.exactFingerprint or nil
    local after = verdict and verdict.snapshot and verdict.exactFingerprint or nil
    if before then ST.exactRevisions[before] = ST.exactRevisionClock end
    if after then ST.exactRevisions[after] = ST.exactRevisionClock end
    ST.debugStats.relatedIndexUpdates = ST.debugStats.relatedIndexUpdates + 1
    ST.debugStats.commits = ST.debugStats.commits + 1
end

local function InsertSlot(root, slot)
    root.slots[slot.key] = slot
    local vector = root.slotVector
    local position = #vector + 1
    for index = 1, #vector do
        if CompareSlots(slot, vector[index]) < 0 then position = index; break end
    end
    table.insert(vector, position, slot)
    root.slotCount = #vector
end

local function RemoveSlot(root, key)
    local vector = root.slotVector
    for index = 1, #vector do
        if vector[index].key == key then table.remove(vector, index); break end
    end
    root.slots[key] = nil
    root.slotCount = #vector
end

local function InsertKey(vector, key, slotsByKey)
    for index, existing in ipairs(vector) do
        if existing == key then return end
        if CompareSlots(slotsByKey[key], slotsByKey[existing]) < 0 then
            table.insert(vector, index, key)
            return
        end
    end
    vector[#vector + 1] = key
end

local function RemoveKey(vector, key)
    for index, existing in ipairs(vector) do
        if existing == key then table.remove(vector, index); return end
    end
end

local function RefreshVectors(root, key)
    local verdict = root.rows[key]
    if verdict and verdict.source == "overlay" and verdict.snapshot then
        InsertKey(root.overlayKeys, key, root.slots)
    else
        RemoveKey(root.overlayKeys, key)
    end
    if verdict and verdict.tombstone then
        InsertKey(root.tombstoneKeys, key, root.slots)
    else
        RemoveKey(root.tombstoneKeys, key)
    end
end

local function ApplyCounts(root, previous, verdict)
    local counts = root.counts
    local function Delta(item, sign)
        if not item then return end
        if item.snapshot then counts.available = counts.available + sign end
        if item.state == "READ_ONLY_FUTURE_SCHEMA" then counts.future = counts.future + sign end
        if item.state == "INVALIDATED" and not item.tombstone then
            counts.invalid = counts.invalid + sign
        end
        if item.tombstone then counts.tombstones = counts.tombstones + sign end
        if item.overlayRaw ~= nil then counts.overlay = counts.overlay + sign end
        if item.barrier then counts.barriers = counts.barriers + sign end
    end
    Delta(previous, -1)
    Delta(verdict, 1)
end

-- One protected replacement of a single typed slot: exact old products are
-- replaced by the prepared verdict inside a synchronous no-callback section.
local function CommitSlot(root, slot, verdict, rawWrites, reason, deferred)
    local key = slot.key
    local previous = root.rows[key]
    local drift = TokenDrifted(root.token)
    if drift then Invalidate(drift); return false, drift end
    ST.preparationEpoch = ST.preparationEpoch + 1
    local db = root.token.databaseIdentity
    local phase = "prepare"
    local ok = pcall(function()
        RunFaultInjector("before-commit")
        phase = "protected"
        for _, write in ipairs(rawWrites) do
            local map = rawget(db, write.map)
            if map == nil then
                map = {}
                rawset(db, write.map, map)
            end
            local current = rawget(map, write.id)
            if write.map == "communityBuilds" and type(write.value) == "table"
                and type(current) == "table" and getmetatable(current) == nil
                and current ~= write.value then
                -- Replace the overlay row's known fields in place: the
                -- durable table identity survives, absent V1-known fields
                -- are removed, and the row is never cleared first.
                for field in pairs(current) do
                    if write.value[field] == nil then rawset(current, field, nil) end
                end
                for field, value in pairs(write.value) do
                    rawset(current, field, value)
                end
                if verdict and verdict.overlayRaw == write.value then
                    verdict.overlayRaw = current
                end
                if slot.overlay == write.value then slot.overlay = current end
            else
                rawset(map, write.id, write.value)
            end
            if write.session then ST[write.session][write.value] = true end
        end
        RunFaultInjector("after-raw-write")
        if previous then IndexRemove(root.index, root.rows, key) end
        if verdict then
            root.rows[key] = verdict
            if not root.slots[key] then InsertSlot(root, slot) end
            IndexAdd(root.index, root.rows, verdict, nil)
        else
            root.rows[key] = nil
            RemoveSlot(root, key)
        end
        ApplyCounts(root, previous, verdict)
        RefreshVectors(root, key)
        root.token = CaptureToken(db)
        RunFaultInjector("before-publish")
    end)
    if not ok then
        if phase == "prepare" then return false, "CANDIDATE_FAILED" end
        ST.debugStats.protectedFailures = ST.debugStats.protectedFailures + 1
        Invalidate("PROTECTED_COMMIT_FAILED")
        return false, "PROTECTED_COMMIT_FAILED"
    end
    BumpRevisions(verdict, previous, slot.id)
    ST.published = {
        generation=ST.generation, token=root.token, rows=root.rows, slots=root.slots,
        slotVector=root.slotVector, slotCount=root.slotCount, index=root.index,
        counts=root.counts, overlayKeys=root.overlayKeys,
        tombstoneKeys=root.tombstoneKeys, catalogVersion=root.catalogVersion,
        schemaVersion=root.schemaVersion, migrated=false, redundantRemoved=0,
    }
    ST.activeCursors = {}
    if not deferred then NotifyBuild(reason, slot.id) end
    return true
end

local function SlotFor(root, id)
    local typedKey, kind = TypedKey(id)
    if not typedKey then return nil, nil, "INVALID_TYPED_ID" end
    local slot = root.slots[typedKey] or {key=typedKey, id=id, kind=kind}
    return slot, root.rows[typedKey]
end

local function ConsumeClaim(claim, typedKey, kind)
    local entry = ST.claimRegistry[claim]
    if not entry or entry.kind ~= kind then return false, "INVALID_CLAIM" end
    if entry.typedKey ~= typedKey then return false, "TYPED_ID_MISMATCH" end
    if entry.superseded or entry.generation ~= ST.generation
        or entry.reservationEpoch + 1 ~= ST.reservationEpoch then
        ReleaseClaim(claim)
        return false, "STALE_CLAIM"
    end
    return true, entry
end

-- An owner-routed mutation supersedes an outstanding explicit claim: the old
-- claim stays registered only so its next use refuses as stale.
local function SupersedeActiveClaim()
    local active = ST.activeClaim
    if active and ST.claimRegistry[active] then
        ST.claimRegistry[active].superseded = true
        ST.activeClaim = nil
        AdvanceReservation()
    end
end

local function BundledRawFor(slot)
    if slot.bundled ~= nil then return slot.bundled end
    if type(ST.baseline) == "table" then return rawget(ST.baseline, slot.id) end
    return nil
end

local function PutInternal(record, options, claim, deferred)
    ST.debugStats.putCalls = ST.debugStats.putCalls + 1
    local root, why = Gate()
    if not root then return false, why end
    if type(record) ~= "table" or record.id == nil then
        return false, "build id required"
    end
    options = type(options) == "table" and options or {}
    local slot, existing, slotWhy = SlotFor(root, record.id)
    if not slot then return false, slotWhy end
    local readmitTombstone = false
    if claim then
        local ok, entryOrWhy = ConsumeClaim(claim, slot.key,
            existing and existing.tombstone and "readmission" or "allocation")
        if not ok then return false, entryOrWhy end
        if entryOrWhy.kind == "readmission" then
            if not (existing and existing.tombstone
                and existing.tombstone.raw == entryOrWhy.extra.tombstoneRaw) then
                ReleaseClaim(claim)
                return false, "STALE_CLAIM"
            end
            readmitTombstone = true
        end
    else
        if existing and existing.tombstone then return false, "TOMBSTONE_RESERVATION" end
        if existing and existing.barrier then return false, "BARRIER_RESERVATION" end
        if existing and existing.state == "READ_ONLY_FUTURE_SCHEMA" then
            return false, "FUTURE_SCHEMA_RESERVATION"
        end
        if Occupancy(existing) == "VACANT" then
            SupersedeActiveClaim()
            local issued, issueWhy = IssueClaim("allocation", slot.key, record.id)
            if not issued then return false, issueWhy end
            claim = issued
        end
    end
    local function Fail(reason)
        if claim then ReleaseClaim(claim) end
        return false, reason
    end
    if readmitTombstone and options.source ~= "local" and options.source ~= "import" then
        return Fail("LOCAL_OWNER_REQUIRED")
    end
    local candidateSlot = {key=slot.key, id=slot.id, kind=slot.kind}
    local verdict, walker = AdmitRaw(record, candidateSlot, "overlay", options)
    if verdict.state ~= "ADMITTED" then return Fail(verdict.reason) end
    if readmitTombstone and not (verdict.verifiedOwner ~= nil
        and verdict.verifiedOwner == CurrentOwnerKey()) then
        return Fail("LOCAL_OWNER_REQUIRED")
    end
    local existingRow = existing and existing.snapshot and existing or nil
    if existingRow and existingRow.verifiedOwner
        and verdict.verifiedOwner ~= existingRow.verifiedOwner
        and (verdict.verifiedOwner or options.source == "remote") then
        return Fail("PROVENANCE_COLLISION")
    end
    local destination, destinationWhy = BuildDestination(verdict, walker,
        existingRow and existingRow.source == "overlay" and existingRow or nil)
    if not destination then return Fail(destinationWhy) end
    local rawWrites = {}
    local storedAs = "overlay"
    local bundledRaw = BundledRawFor(slot)
    verdict.bundledRaw, verdict.overlayRaw = bundledRaw, destination
    if bundledRaw ~= nil and BaselineEquivalent(verdict.snapshot, verdict.hasUnknown,
        destination, bundledRaw, slot) then
        storedAs = "baseline"
        if not (existing and existing.overlayRaw ~= nil) and not readmitTombstone
            and existing and existing.snapshot and existing.source == "bundled" then
            -- The bundled row already serves this exact content: nothing
            -- durable or public changes, so no generation publishes.
            if claim then ReleaseClaim(claim) end
            return true, storedAs
        end
        rawWrites[#rawWrites + 1] = {map="communityBuilds", id=slot.id, value=nil}
        slot.overlay, slot.bundled, slot.tombstone = nil, bundledRaw, nil
        verdict = AdmitRaw(bundledRaw, slot, "bundled", {})
        verdict.bundledRaw, verdict.overlayRaw = bundledRaw, nil
    else
        CompactDestination(destination)
        -- Nothing represented changed only when the admitted snapshot and the
        -- durable bytes both already match: no raw write, no generation.
        if existingRow and existingRow.source == "overlay" and not readmitTombstone
            and type(existingRow.overlayRaw) == "table"
            and DeepEqual(verdict.snapshot, existingRow.snapshot)
            and DeepEqual(destination, existingRow.overlayRaw) then
            if claim then ReleaseClaim(claim) end
            return true, storedAs
        end
        rawWrites[#rawWrites + 1] = {map="communityBuilds", id=slot.id, value=destination}
        slot.overlay, slot.bundled, slot.tombstone = destination, bundledRaw, nil
    end
    if readmitTombstone then
        rawWrites[#rawWrites + 1] = {map="syncTombstones", id=slot.id, value=nil}
    end
    if existingRow or readmitTombstone or (existing and existing.state == "INVALIDATED") then
        verdict.state = "READMITTED"
    end
    if existing and existing.barrier then verdict.barrier = existing.barrier end
    local ok, commitWhy = CommitSlot(root, slot, verdict, rawWrites, "build put", deferred)
    if claim then ReleaseClaim(claim) end
    if not ok then return false, commitWhy end
    ST.debugStats.putChanges = ST.debugStats.putChanges + 1
    return true, storedAs
end

function Catalog.Put(record, options)
    return PutInternal(record, options, nil, false)
end

function Catalog.PutWithClaim(claim, record, options)
    if type(claim) ~= "table" or not ST.claimRegistry[claim] then
        return false, "INVALID_CLAIM"
    end
    local root, why = Gate()
    if not root then return false, why end
    local entry = ST.claimRegistry[claim]
    local typedKey = type(record) == "table" and TypedKey(record.id) or nil
    if entry.typedKey ~= typedKey then return false, "TYPED_ID_MISMATCH" end
    return PutInternal(record, options, claim, false)
end

-- Stage one repair record without publishing a represented-data revision.
function Catalog.PutDeferred(record)
    local root, why = Gate()
    if not root then return false, why end
    if type(record) ~= "table" or record.id == nil then
        return false, "build id required"
    end
    local slot, existing = SlotFor(root, record.id)
    if not slot then return false, "INVALID_TYPED_ID" end
    if existing and (existing.overlayRaw ~= nil or existing.tombstone
        or existing.snapshot) then
        return false, "deferred build id unavailable"
    end
    local ok, storedAs = PutInternal(record, {}, nil, true)
    if not ok then return false, storedAs end
    return true, storedAs, true
end

function Catalog.PublishDeferred(changed, reason)
    local root, why = Gate()
    if not root then return false, why end
    changed = math.max(0, math.floor(tonumber(changed) or 0))
    if changed == 0 then return true, 0 end
    ST.recordEpoch = ST.recordEpoch + 1
    ST.exactEpoch = ST.exactEpoch + 1
    NotifyBuild(reason or "deferred builds published", nil, "all")
    return true, 1
end

local function ReadmitLowerSource(slot)
    local bundledRaw = type(ST.baseline) == "table" and rawget(ST.baseline, slot.id) or nil
    if bundledRaw == nil then return nil end
    slot.overlay, slot.tombstone, slot.bundled = nil, nil, bundledRaw
    local verdict = AdmitRaw(bundledRaw, slot, "bundled", {})
    verdict.bundledRaw, verdict.overlayRaw = bundledRaw, nil
    return verdict
end

local function CarryBarrier(replacement, existing, slot)
    if existing.barrier then
        if not replacement then
            replacement = NewVerdict(slot, "UNADMITTED", "no source")
        end
        replacement.barrier = existing.barrier
    end
    return replacement
end

function Catalog.RemoveOverlay(id)
    local root, why = Gate()
    if not root then return false, why end
    local slot, existing, slotWhy = SlotFor(root, id)
    if not slot then return false, slotWhy end
    if not existing or existing.overlayRaw == nil then return false end
    if existing.tombstone then return false, "TOMBSTONE_RESERVATION" end
    if existing.state == "READ_ONLY_FUTURE_SCHEMA" then
        return false, "FUTURE_SCHEMA_RESERVATION"
    end
    if existing.state == "INVALIDATED" then return false, "INVALID_RESERVATION" end
    local replacement = CarryBarrier(ReadmitLowerSource(slot), existing, slot)
    if not replacement then slot.overlay = nil end
    local ok, commitWhy = CommitSlot(root, slot, replacement, {
        {map="communityBuilds", id=slot.id, value=nil},
    }, "overlay removed", false)
    if not ok then return false, commitWhy end
    return true
end

function Catalog.RemoveOverlayBatch(ids)
    local root, why = Gate()
    if not root then return 0, why end
    if type(ids) ~= "table" then return 0, "build id list required" end
    local removed = 0
    for _, id in ipairs(ids) do
        if Catalog.RemoveOverlay(id) then removed = removed + 1 end
    end
    return removed
end

local function TombstoneRecord(slot, existing, tombstone)
    local snapshot = existing.snapshot
    ST.receiptRevision = ST.receiptRevision + 1
    return {
        schemaVersion=TOMBSTONE_SCHEMA_VERSION,
        typedId={luaType=slot.kind, exactValue=slot.id},
        ownerKey=existing.verifiedOwner or snapshot.ownerKey or "",
        sourceKind="local",
        sourceIdentity="local",
        targetRowGeneration=ST.generation,
        targetRowProvenance={
            author=tostring(tombstone.author or snapshot.author or ""),
            ownerKey=existing.verifiedOwner or snapshot.ownerKey,
            realm=snapshot.realm, ownerVerified=existing.verifiedOwner ~= nil,
        },
        receiptRevision=ST.receiptRevision,
        receiptAtServerTime=TrustedServerTime() or 0,
        remoteStampEvidence=tonumber(tombstone.stamp) or 0,
    }
end

function Catalog.SetTombstone(id, tombstone, options)
    local root, why = Gate()
    if not root then return false, why end
    if id == nil or type(tombstone) ~= "table" then return false, "tombstone required" end
    options = type(options) == "table" and options or {}
    local slot, existing, slotWhy = SlotFor(root, id)
    if not slot then return false, slotWhy end
    local sourceKind = options.source == "remote" and "remote" or "local"
    local stamp = tonumber(tombstone.stamp) or 0
    local author = tostring(tombstone.author or "")
    if existing and existing.tombstone then
        local view = existing.tombstone.view
        if view.stamp == stamp and view.author == author then
            return true, "TOMBSTONE_REPLAY_NOOP"
        end
        return false, sourceKind == "remote" and "REMOTE_TOMBSTONE_CONFLICT"
            or "TOMBSTONE_REPLAY_CONFLICT"
    end
    if not (existing and existing.snapshot) then
        if existing and existing.state == "READ_ONLY_FUTURE_SCHEMA" then
            return false, "FUTURE_SCHEMA_RESERVATION"
        end
        if existing and existing.state == "INVALIDATED" then
            return false, "INVALID_RESERVATION"
        end
        return false, sourceKind == "remote" and "REMOTE_OWNER_REQUIRED"
            or "LOCAL_OWNER_REQUIRED"
    end
    local current = CurrentOwnerKey()
    if sourceKind == "local" then
        -- Local deletion requires current local-owner proof for the admitted
        -- row: a verified overlay owner, or the coherent owner tuple of an
        -- immutable bundled row (package authority, never user text).
        local owns = current ~= nil
            and (Identity.LocalOwnsBuild(existing.snapshot, current)
                or (existing.source == "bundled" and existing.trustedOwner == current))
        if not owns then
            return false, "LOCAL_OWNER_REQUIRED"
        end
        local record = TombstoneRecord(slot, existing, tombstone)
        local verdict = NewVerdict(slot, "TOMBSTONED", "TOMBSTONE_CURRENT_DENY")
        verdict.reservation = "TOMBSTONE_CURRENT_DENY"
        local view = {state="CURRENT_DENY", stamp=stamp,
            author=record.targetRowProvenance.author, ownerKey=record.ownerKey,
            ownerVerified=true, sourceKind="local", localOwned=true}
        verdict.tombstone = {state="CURRENT_DENY", view=view, raw=record}
        verdict.source = "tombstone"
        verdict.bundledRaw, verdict.overlayRaw = existing.bundledRaw, nil
        verdict.barrier = existing.barrier
        slot.overlay, slot.tombstone = nil, record
        local ok, commitWhy = CommitSlot(root, slot, verdict, {
            {map="syncTombstones", id=slot.id, value=record, session="sessionTombstones"},
            {map="communityBuilds", id=slot.id, value=nil},
        }, "build tombstoned", false)
        if not ok then return false, commitWhy end
        return true
    end
    -- Remote: protocol 7 supplies no operation order proof. The admitted raw
    -- row stays in place, the bounded opaque payload occupies the tombstone
    -- slot, and the typed ID becomes deny-only with zero relay authority.
    -- Deletion requires transport proof for the admitted row's own owner key.
    -- The stored claim is never authority by itself; the exact sender must own
    -- it, and a claim that contradicts the stored key grants nothing.
    local snapshot = existing.snapshot
    local storedOwner = type(snapshot.ownerKey) == "string"
        and Identity.CanonicalOwnerKey(snapshot.ownerKey) or nil
    local claimedOwner = type(snapshot.claimedOwnerKey) == "string"
        and Identity.CanonicalOwnerKey(snapshot.claimedOwnerKey) or nil
    if storedOwner and claimedOwner and storedOwner ~= claimedOwner then
        return false, "REMOTE_OWNER_REQUIRED"
    end
    local owner = existing.verifiedOwner
        or (existing.source == "bundled" and existing.trustedOwner)
        or storedOwner or claimedOwner or nil
    if not (owner and Identity.TransportOwns(owner, options.sender)) then
        return false, "REMOTE_OWNER_REQUIRED"
    end
    local payload = {stamp=stamp, author=author,
        ownerKey=type(tombstone.ownerKey) == "string" and tombstone.ownerKey or owner,
        ownerVerified=tombstone.ownerVerified == true or nil}
    local verdict = NewVerdict(slot, "INVALIDATED", "TOMBSTONE_RESERVATION")
    verdict.reservation = "TOMBSTONE_OPAQUE_BLOCK_ALL"
    verdict.tombstone = {state="OPAQUE_BLOCK_ALL", raw=payload, view={
        state="OPAQUE_BLOCK_ALL", stamp=stamp, author=author, ownerKey=payload.ownerKey,
        ownerVerified=false, sourceKind="remote", localOwned=false}}
    verdict.source = "tombstone"
    verdict.raw = existing.overlayRaw
    verdict.overlayRaw, verdict.bundledRaw = existing.overlayRaw, existing.bundledRaw
    verdict.barrier = existing.barrier
    slot.tombstone = payload
    local ok, commitWhy = CommitSlot(root, slot, verdict, {
        {map="syncTombstones", id=slot.id, value=payload},
    }, "build tombstoned", false)
    if not ok then return false, commitWhy end
    return true, "REMOTE_TOMBSTONE_ORDER_UNPROVEN"
end

local function RetiredReplacement(slot, existing)
    local replacement = ReadmitLowerSource(slot)
    if existing.overlayRaw ~= nil and not replacement then
        slot.overlay, slot.tombstone = existing.overlayRaw, nil
        replacement = AdmitRaw(existing.overlayRaw, slot, "overlay", {})
        replacement.overlayRaw = existing.overlayRaw
    end
    slot.tombstone = nil
    return CarryBarrier(replacement, existing, slot)
end

function Catalog.ClearTombstone(id)
    local root, why = Gate()
    if not root then return false, why end
    local slot, existing, slotWhy = SlotFor(root, id)
    if not slot then return false, slotWhy end
    if not (existing and existing.tombstone) then return false, "TOMBSTONE_RESERVATION_ABSENT" end
    if existing.tombstone.state ~= "CURRENT_DENY" or not existing.tombstone.view.localOwned then
        return false, "TOMBSTONE_RESERVATION_BLOCK_ALL"
    end
    local ok, commitWhy = CommitSlot(root, slot, RetiredReplacement(slot, existing), {
        {map="syncTombstones", id=slot.id, value=nil},
    }, "tombstone cleared", false)
    if not ok then return false, commitWhy end
    return true
end

------------------------------------------------------------------------
-- Maintenance transactions (retention, compaction, migration)
------------------------------------------------------------------------

function Catalog.BeginCatalogMaintenance(request)
    request = type(request) == "table" and request or {}
    local root, why = Gate()
    if not root then return nil, why end
    if request.database ~= ST.db then return nil, "DETACHED_DATABASE" end
    local handle = {operation=request.operation or "retention",
        generation=ST.generation, revision=ST.committedMutationRevision,
        ops={}, seen={}, state="open"}
    ST.maintenanceRegistry[handle] = true
    ST.activeMaintenance = handle
    return handle
end

local function MaintenanceOpen(handle)
    if type(handle) ~= "table" or not ST.maintenanceRegistry[handle] then
        return nil, "INVALID_MAINTENANCE_HANDLE"
    end
    local root, why = Gate()
    if not root then return nil, why end
    if handle.state ~= "open" then return nil, "INVALID_MAINTENANCE_HANDLE" end
    return root
end

local function BarrierRecord(slot, existing)
    ST.receiptRevision = ST.receiptRevision + 1
    return {
        schemaVersion=BARRIER_SCHEMA_VERSION,
        typedId={luaType=slot.kind, exactValue=slot.id},
        evictedCatalogGeneration=ST.generation,
        evictedSourceIdentity=existing.source or "overlay",
        evictedProvenanceIdentity=existing.verifiedOwner
            or (existing.snapshot and existing.snapshot.claimedOwnerKey) or "",
        receiptRevision=ST.receiptRevision,
        receiptAtServerTime=TrustedServerTime() or 0,
    }
end

function Catalog.MaintenanceEvictOverlay(handle, id)
    local root, why = MaintenanceOpen(handle)
    if not root then return false, why end
    local slot, existing, slotWhy = SlotFor(root, id)
    if not slot then return false, slotWhy end
    if handle.seen[slot.key] then return false, "DUPLICATE_TARGET" end
    if existing and existing.barrier and existing.overlayRaw == nil then
        return true, "BARRIER_REPLAY_NOOP"
    end
    if not existing or existing.overlayRaw == nil then return false, "OVERLAY_ABSENT" end
    if existing.tombstone then return false, "TOMBSTONE_RESERVATION" end
    if existing.state == "READ_ONLY_FUTURE_SCHEMA" then return false, "FUTURE_SCHEMA_RESERVATION" end
    if not existing.snapshot then return false, "INVALID_RESERVATION" end
    handle.seen[slot.key] = true
    handle.ops[#handle.ops + 1] = {kind="evict", slot=slot, existing=existing,
        barrier=BarrierRecord(slot, existing)}
    return true
end

local function TombstoneExpired(existing)
    if existing.tombstone.state ~= "CURRENT_DENY" then
        return false, "TOMBSTONE_RESERVATION_BLOCK_ALL"
    end
    local now = TrustedServerTime()
    if not now then return false, "TIME_UNTRUSTED" end
    local created = tonumber(existing.tombstone.raw.receiptAtServerTime) or 0
    if created <= 0 or now - created < TOMBSTONE_AGE then
        return false, "TOMBSTONE_NOT_EXPIRED"
    end
    return true
end

function Catalog.MaintenanceRetireTombstone(handle, id)
    local root, why = MaintenanceOpen(handle)
    if not root then return false, why end
    local slot, existing, slotWhy = SlotFor(root, id)
    if not slot then return false, slotWhy end
    if not (existing and existing.tombstone) then return false, "TOMBSTONE_RESERVATION_ABSENT" end
    local expired, expiredWhy = TombstoneExpired(existing)
    if not expired then return false, expiredWhy end
    if handle.seen[slot.key] then return false, "DUPLICATE_TARGET" end
    handle.seen[slot.key] = true
    handle.ops[#handle.ops + 1] = {kind="retire", slot=slot, existing=existing}
    return true
end

local function BarrierExpired(barrier)
    if barrier.state == "BARRIER_OPAQUE_BLOCK_ALL" then
        return false, "BARRIER_RESERVATION_BLOCK_ALL"
    end
    local now = TrustedServerTime()
    if not now then return false, "TIME_UNTRUSTED" end
    local observed = barrier.state == "BARRIER_CURRENT_DENY"
        and (tonumber(barrier.receiptAtServerTime) or 0)
        or (tonumber(barrier.readmittedAtServerTime) or 0)
    if observed <= 0 or now - observed < BARRIER_AGE then
        return false, "BARRIER_NOT_EXPIRED"
    end
    return true
end

function Catalog.MaintenanceExpireBarrier(handle, id)
    local root, why = MaintenanceOpen(handle)
    if not root then return false, why end
    local slot, existing, slotWhy = SlotFor(root, id)
    if not slot then return false, slotWhy end
    if not (existing and existing.barrier) then return false, "BARRIER_ABSENT" end
    local expired, expiredWhy = BarrierExpired(existing.barrier)
    if not expired then return false, expiredWhy end
    if handle.seen[slot.key] then return false, "DUPLICATE_TARGET" end
    handle.seen[slot.key] = true
    handle.ops[#handle.ops + 1] = {kind="expire", slot=slot, existing=existing}
    return true
end

function Catalog.MaintenanceReplaceRow(handle, id, record)
    local root, why = MaintenanceOpen(handle)
    if not root then return false, why end
    local slot, existing, slotWhy = SlotFor(root, id)
    if not slot then return false, slotWhy end
    if not (existing and existing.snapshot and existing.source == "overlay") then
        return false, existing and existing.state == "READ_ONLY_FUTURE_SCHEMA"
            and "FUTURE_SCHEMA_RESERVATION" or "OVERLAY_ABSENT"
    end
    if type(record) ~= "table" then return false, "MALFORMED_ROW" end
    if handle.seen[slot.key] then return false, "DUPLICATE_TARGET" end
    local candidate = {key=slot.key, id=slot.id, kind=slot.kind}
    local verdict, walker = AdmitRaw(record, candidate, "overlay", {})
    if verdict.state ~= "ADMITTED" then
        handle.failed = verdict.reason
        return false, verdict.reason
    end
    if existing.verifiedOwner and verdict.verifiedOwner ~= existing.verifiedOwner then
        handle.failed = "PROVENANCE_COLLISION"
        return false, "PROVENANCE_COLLISION"
    end
    local destination, destinationWhy = BuildDestination(verdict, walker, existing)
    if not destination then
        handle.failed = destinationWhy
        return false, destinationWhy
    end
    verdict.state = "READMITTED"
    verdict.bundledRaw, verdict.overlayRaw = existing.bundledRaw, destination
    verdict.barrier = existing.barrier
    handle.seen[slot.key] = true
    handle.ops[#handle.ops + 1] = {kind="replace", slot=slot, existing=existing,
        verdict=verdict, destination=destination}
    return true
end

function Catalog.MaintenanceOverlayNext(handle, cursor)
    local root, why = MaintenanceOpen(handle)
    if not root then return nil, nil, true, why end
    local verdict = VectorStep(root.overlayKeys, cursor, root)
    if not verdict then return nil, nil, true end
    return verdict.id, DeepCopy(verdict.overlayRaw), false
end

function Catalog.CancelMaintenance(handle)
    if type(handle) == "table" and ST.maintenanceRegistry[handle] then
        handle.state = "cancelled"
        ST.maintenanceRegistry[handle] = nil
        if ST.activeMaintenance == handle then ST.activeMaintenance = nil end
        return true
    end
    return false
end

function Catalog.CommitMaintenance(handle)
    local root, why = MaintenanceOpen(handle)
    if not root then return false, why end
    handle.state = "committing"
    ST.maintenanceRegistry[handle] = nil
    if ST.activeMaintenance == handle then ST.activeMaintenance = nil end
    if handle.failed then return false, "CANDIDATE_FAILED" end
    if handle.generation ~= ST.generation
        or handle.revision ~= ST.committedMutationRevision then
        return false, "SOURCE_DRIFT"
    end
    if #handle.ops == 0 then return true, {applied=0} end
    -- Prepare every replacement verdict off-state before any raw write.
    local prepared = {}
    for _, op in ipairs(handle.ops) do
        local slot, existing = op.slot, op.existing
        local item = {op=op, writes={}}
        if op.kind == "evict" then
            local replacement = ReadmitLowerSource(slot)
            if not replacement then
                replacement = NewVerdict(slot, "UNADMITTED", "no source")
            end
            replacement.barrier = {state="BARRIER_CURRENT_DENY", raw=op.barrier,
                receiptAtServerTime=op.barrier.receiptAtServerTime,
                revision=op.barrier.receiptRevision}
            slot.overlay, slot.barrier = nil, op.barrier
            item.verdict = replacement
            item.writes[1] = {map="communityBuilds", id=slot.id, value=nil}
            item.writes[2] = {map="communityRetentionEvictions", id=slot.id,
                value=op.barrier, session="sessionBarriers"}
        elseif op.kind == "retire" then
            item.verdict = RetiredReplacement(slot, existing)
            item.writes[1] = {map="syncTombstones", id=slot.id, value=nil}
        elseif op.kind == "expire" then
            local replacement
            if existing.snapshot or existing.tombstone
                or existing.state == "READ_ONLY_FUTURE_SCHEMA"
                or existing.state == "INVALIDATED" then
                replacement = existing
                replacement.barrier = nil
            end
            slot.barrier = nil
            item.verdict = replacement
            item.writes[1] = {map="communityRetentionEvictions", id=slot.id, value=nil}
        elseif op.kind == "replace" then
            CompactDestination(op.destination)
            slot.overlay = op.destination
            item.verdict = op.verdict
            item.writes[1] = {map="communityBuilds", id=slot.id, value=op.destination}
        end
        prepared[#prepared + 1] = item
    end
    local applied = 0
    for _, item in ipairs(prepared) do
        local ok, commitWhy = CommitSlot(root, item.op.slot, item.verdict,
            item.writes, "catalog maintenance", true)
        if not ok then return false, commitWhy end
        applied = applied + 1
    end
    ST.debugStats.maintenanceCommits = ST.debugStats.maintenanceCommits + 1
    NotifyBuild(handle.operation == "compaction" and "exact evidence compaction"
        or "catalog maintenance", nil, "all")
    return true, {applied=applied}
end

function Catalog.RemoveTombstonesBatch(ids)
    local root, why = Gate()
    if not root then return 0, why end
    if type(ids) ~= "table" then return 0, "tombstone id list required" end
    local removed = 0
    for _, id in ipairs(ids) do
        local handle = Catalog.BeginCatalogMaintenance({database=ST.db, operation="retention"})
        if handle and Catalog.MaintenanceRetireTombstone(handle, id)
            and Catalog.CommitMaintenance(handle) then
            removed = removed + 1
        elseif handle then
            Catalog.CancelMaintenance(handle)
        end
    end
    return removed
end

------------------------------------------------------------------------
-- Cursor families: record, summary, delta, relationship, saved-mirror,
-- diagnostic. Authority is the exact token identity in a weak registry.
------------------------------------------------------------------------

local function BeginCursor(family, state)
    local root, why = Gate()
    if not root then return nil, why end
    local previous = ST.activeCursors[family]
    if previous then ST.cursorRegistry[previous] = nil end
    ST.cursorSequence = ST.cursorSequence + 1
    local token = {kind=family, cursorId=ST.cursorSequence, generation=ST.generation}
    state = state or {}
    state.kind, state.rootIdentity, state.generation = family, ST.published, ST.generation
    state.nextIndex, state.exhausted = 1, false
    ST.cursorRegistry[token] = state
    ST.activeCursors[family] = token
    ST.debugStats.cursorsBegun = ST.debugStats.cursorsBegun + 1
    return token
end

local function CursorState(token, family)
    local state = type(token) == "table" and ST.cursorRegistry[token] or nil
    if not state or state.kind ~= family then return nil, "INVALID_CURSOR" end
    local root = Gate()
    if not root or state.rootIdentity ~= root or state.generation ~= ST.generation then
        ST.cursorRegistry[token] = nil
        if ST.activeCursors[family] == token then ST.activeCursors[family] = nil end
        return nil, "STALE_CURSOR"
    end
    return state, nil, root
end

local function NextVerdict(state, root, filter)
    while state.nextIndex <= root.slotCount do
        local slot = root.slotVector[state.nextIndex]
        state.nextIndex = state.nextIndex + 1
        local verdict = root.rows[slot.key]
        if verdict and filter(verdict) then return verdict end
    end
    state.exhausted = true
    return nil
end

function Catalog.BeginRecordCursor()
    return BeginCursor("record")
end

function Catalog.RecordCursorNext(token)
    local state, why, root = CursorState(token, "record")
    if not state then return nil, why end
    if state.exhausted then return {done=true} end
    local verdict = NextVerdict(state, root, Admitted)
    if not verdict then return {done=true} end
    return {done=false, id=verdict.id, record=PublicRecord(verdict), source=verdict.source}
end

function Catalog.BeginSummaryCursor()
    return BeginCursor("summary")
end

function Catalog.SummaryCursorNext(token)
    local state, why, root = CursorState(token, "summary")
    if not state then
        return nil, true, why == "INVALID_CURSOR" and "invalid cursor" or "catalog changed"
    end
    if state.exhausted then return nil, true end
    local verdict = NextVerdict(state, root, Admitted)
    if not verdict then return nil, true end
    return Summarize(verdict), false, nil, verdict.bundledRaw ~= nil, verdict.overlayRaw ~= nil
end

function Catalog.BeginDeltaCursor()
    return BeginCursor("delta")
end

function Catalog.DeltaCursorNext(token)
    local state, why, root = CursorState(token, "delta")
    if not state then return nil, why end
    if state.exhausted then return {done=true} end
    local verdict = NextVerdict(state, root, SyncEligible)
    if not verdict then return {done=true} end
    return {done=false, id=verdict.id, record=PublicRecord(verdict)}
end

local function SavedMirrorKeys(root, author)
    local bucket = root.index.saved[RelatedKey(author, "saved")]
    local keys = {}
    for key in pairs(bucket and bucket.ids or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

function Catalog.BeginSavedMirrorCursor(author)
    local root, why = Gate()
    if not root then return nil, why end
    ST.debugStats.savedMirrorEnumerations = ST.debugStats.savedMirrorEnumerations + 1
    return BeginCursor("saved-mirror", {keys=SavedMirrorKeys(root, author)})
end

function Catalog.SavedMirrorCursorNext(token)
    local state, why, root = CursorState(token, "saved-mirror")
    if not state then return nil, why end
    while state.nextIndex <= #state.keys do
        local key = state.keys[state.nextIndex]
        state.nextIndex = state.nextIndex + 1
        local verdict = root.rows[key]
        if verdict and verdict.snapshot then
            ST.debugStats.savedMirrorRows = ST.debugStats.savedMirrorRows + 1
            return {done=false, id=verdict.id, record=PublicRecord(verdict)}
        end
    end
    return {done=true}
end

function Catalog.SavedMirrorIds(author)
    local root, why = Gate()
    if not root then return {}, why end
    ST.debugStats.savedMirrorEnumerations = ST.debugStats.savedMirrorEnumerations + 1
    local ids = {}
    for _, key in ipairs(SavedMirrorKeys(root, author)) do
        local verdict = root.rows[key]
        if verdict then ids[#ids + 1] = verdict.id end
        if #ids > BUDGET.oneCallRows then return nil, "CURSOR_REQUIRED" end
    end
    table.sort(ids, function(left, right) return tostring(left) < tostring(right) end)
    ST.debugStats.savedMirrorRows = ST.debugStats.savedMirrorRows + #ids
    return ids
end

function Catalog.BeginDiagnosticCursor(kind)
    if kind ~= "overlay" and kind ~= "tombstone" then return nil, "INVALID_CURSOR" end
    return BeginCursor("diagnostic", {diagnostic=kind})
end

function Catalog.DiagnosticCursorNext(token)
    local state, why, root = CursorState(token, "diagnostic")
    if not state then return nil, why end
    if state.exhausted then return {done=true} end
    local verdict = NextVerdict(state, root, function(item)
        if state.diagnostic == "tombstone" then return item.tombstone ~= nil end
        return item.overlayRaw ~= nil and item.snapshot ~= nil
    end)
    if not verdict then return {done=true} end
    if state.diagnostic == "tombstone" then
        return {done=false, id=verdict.id, tombstone=CompatTombstone(verdict),
            state=verdict.tombstone.state}
    end
    return {done=false, id=verdict.id, record=PublicRecord(verdict)}
end

function Catalog.BeginRelatedCursor(author, title, fingerprint)
    local root, why = Gate()
    if not root then return nil, why end
    ST.debugStats.relatedLookups = ST.debugStats.relatedLookups + 1
    local authorKey = RelatedText(author)
    local buckets = {}
    if authorKey ~= "" then
        local index = root.index
        local function Add(bucket) if bucket then buckets[#buckets + 1] = bucket end end
        Add(index.fingerprints[RelatedKey(authorKey, fingerprint)])
        Add(index.titles[RelatedKey(authorKey, RelatedText(title))])
        local spells, total = FingerprintSpells(fingerprint)
        if total >= 6 then
            local smallest
            for _, spellId in ipairs(spells) do
                local bucket = index.spells[RelatedKey(authorKey, tostring(spellId))]
                if bucket and (not smallest or bucket.count < smallest.count) then
                    smallest = bucket
                end
            end
            Add(smallest)
        end
    end
    local keys, seen = {}, {}
    for _, bucket in ipairs(buckets) do
        for key in pairs(bucket.ids) do
            if not seen[key] then seen[key] = true; keys[#keys + 1] = key end
        end
    end
    table.sort(keys)
    return BeginCursor("relationship", {keys=keys, returned=0})
end

function Catalog.RelatedCursorNext(token)
    local state, why, root = CursorState(token, "relationship")
    if not state then
        return nil, true, why == "INVALID_CURSOR" and "invalid related cursor" or "catalog changed"
    end
    while state.nextIndex <= #state.keys do
        local key = state.keys[state.nextIndex]
        state.nextIndex = state.nextIndex + 1
        local verdict = root.rows[key]
        if verdict and verdict.snapshot then
            state.returned = state.returned + 1
            ST.debugStats.relatedCandidates = ST.debugStats.relatedCandidates + 1
            ST.debugStats.maxRelatedCandidates = math.max(
                ST.debugStats.maxRelatedCandidates, state.returned)
            return PublicRecord(verdict), false
        end
    end
    return nil, true
end

function Catalog.RelatedCandidates(author, title, fingerprint)
    local rows = {}
    local cursor, err = Catalog.BeginRelatedCursor(author, title, fingerprint)
    if not cursor then return rows, err end
    while true do
        local record, done, nextErr = Catalog.RelatedCursorNext(cursor)
        if nextErr then return {}, nextErr end
        if record then rows[#rows + 1] = record end
        if #rows > BUDGET.oneCallRows then return nil, "CURSOR_REQUIRED" end
        if done then break end
    end
    return rows
end

------------------------------------------------------------------------
-- Fingerprint, owner, and author identity
------------------------------------------------------------------------

local function ExactWinner(root, fingerprint)
    ST.debugStats.exactLookups = ST.debugStats.exactLookups + 1
    if type(fingerprint) ~= "string" or fingerprint == "" then return nil end
    local bucket = root.index.exact[fingerprint]
    local candidates = bucket and bucket.count or 0
    ST.debugStats.exactCandidates = ST.debugStats.exactCandidates + candidates
    ST.debugStats.maxExactCandidates = math.max(ST.debugStats.maxExactCandidates, candidates)
    if not (bucket and bucket.winnerKey) then return nil end
    return root.rows[bucket.winnerKey], bucket
end

function Catalog.FindExactFingerprintId(fingerprint)
    local root = Gate()
    if not root then return nil end
    local verdict = ExactWinner(root, fingerprint)
    return verdict and verdict.id or nil
end

function Catalog.FindExactFingerprint(fingerprint)
    local root = Gate()
    if not root then return nil, nil, nil end
    local verdict = ExactWinner(root, fingerprint)
    if not verdict then return nil, nil, nil end
    return verdict.id, PublicRecord(verdict), verdict.source
end

function Catalog.ValidateLegacyFingerprintClaim(rawId, record)
    local root = Gate()
    if not root then return nil, "catalog authority unavailable" end
    if rawId == nil or (type(rawId) ~= "string" and type(rawId) ~= "number")
        or tostring(rawId) == "" then
        return nil, "legacy claim requires an exact typed build ID"
    end
    local verdict = VerdictOf(root, rawId)
    if verdict and verdict.tombstone then
        return nil, "historical build identity is tombstoned"
    end
    if not (verdict and verdict.snapshot) then
        return nil, "exact represented build is unavailable"
    end
    if verdict.savedKind ~= "ordinary" then
        return nil, "historical build identity is private"
    end
    local evidence = Nexus and Nexus.LoadoutEvidence
    if not (evidence and type(evidence.ValidateLegacyFingerprintClaim) == "function") then
        return nil, "legacy claim validator is unavailable"
    end
    local claim = type(record) == "table" and record or {buildId=rawId}
    local ok, proof, reason = pcall(evidence.ValidateLegacyFingerprintClaim,
        claim, PublicRecord(verdict))
    if not ok then return nil, "legacy claim validation failed" end
    if type(proof) ~= "table" then return nil, reason end
    return proof
end

function Catalog.ResolveFingerprintIdentity(rawId, fingerprint, options)
    local root = Gate()
    ST.debugStats.identityResolutions = ST.debugStats.identityResolutions + 1
    local function Failure(reason)
        ST.debugStats.identityResolutionFailures = ST.debugStats.identityResolutionFailures + 1
        return nil, reason
    end
    if not root then return Failure("catalog authority unavailable") end
    if type(fingerprint) ~= "string" or fingerprint == "" then
        return Failure("record fingerprint is unavailable")
    end
    local allowClassOnly = false
    if type(options) == "table" then
        allowClassOnly = options.allowClassOnly == true or options.allowIncompleteForClass == true
    elseif type(options) == "boolean" then
        allowClassOnly = options == true
    end
    if fingerprint:sub(1, 1) == "@" then
        local legacyRecord = type(options) == "table" and options.legacyRecord or nil
        if type(legacyRecord) ~= "table" then
            legacyRecord = {buildId=rawId, fingerprint=fingerprint}
        end
        local proof, reason = Catalog.ValidateLegacyFingerprintClaim(rawId, legacyRecord)
        if proof then
            ST.debugStats.identityRawHits = ST.debugStats.identityRawHits + 1
            return rawId, "legacy-alias", proof.fingerprint
        end
        return Failure(reason or "legacy fingerprint identity is unavailable")
    end
    local function ClassOnly(verdict)
        return allowClassOnly and type(verdict.snapshot.class) == "string"
            and verdict.snapshot.class ~= ""
    end
    if rawId ~= nil then
        local verdict = VerdictOf(root, rawId)
        if verdict and verdict.tombstone then
            return Failure("historical build identity is tombstoned")
        end
        if verdict and verdict.snapshot and verdict.savedKind == "ordinary"
            and verdict.exactFingerprint == fingerprint
            and (verdict.complete or ClassOnly(verdict)) then
            ST.debugStats.identityRawHits = ST.debugStats.identityRawHits + 1
            return rawId, "raw"
        end
    end
    local bucket = root.index.exact[fingerprint]
    local explicit = bucket and (bucket.explicitCount or 0) or 0
    local automatic = bucket and (bucket.autoCount or 0) or 0
    if explicit > 1 or (explicit == 0 and automatic > 1) then
        return Failure("exact build identity is ambiguous")
    end
    local verdict = ExactWinner(root, fingerprint)
    if verdict and verdict.exactFingerprint == fingerprint
        and (verdict.complete or ClassOnly(verdict)) then
        ST.debugStats.identityFingerprintHits = ST.debugStats.identityFingerprintHits + 1
        return verdict.id, "fingerprint"
    end
    return Failure("exact build identity is unavailable")
end

function Catalog.ResolveOwnerClass(record)
    local root = Gate()
    ST.debugStats.ownerClassLookups = ST.debugStats.ownerClassLookups + 1
    if not root then return nil, "owner class index stale" end
    local key = Identity.VerifiedOwnerKey(record)
    if not key then return nil, "owner identity is unverified" end
    local bucket = root.index.ownerClasses[key]
    if not bucket then return nil, "owner class unavailable" end
    local resolved, distinct = nil, 0
    for value in pairs(bucket.classes) do
        resolved = value
        distinct = distinct + 1
        if distinct > 1 then
            ST.debugStats.ownerClassConflicts = ST.debugStats.ownerClassConflicts + 1
            return nil, "owner class evidence conflicts"
        end
    end
    if distinct == 1 then
        ST.debugStats.ownerClassHits = ST.debugStats.ownerClassHits + 1
        return resolved, "owner-consensus"
    end
    return nil, "owner class unavailable"
end

function Catalog.IsAuthor(name)
    local root = Gate()
    if not root then return false end
    local key = AuthorKey(name)
    if not key then return false end
    return root.index.authors[key] ~= nil
end
