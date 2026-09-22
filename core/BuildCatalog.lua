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
-- MASTER-RC-003: LoadoutEvidence owns the canonical evidence-union identity and
-- loads before this module (Nexus.toc 22 before 25).
local Evidence = assert(Nexus.LoadoutEvidence,
    "Nexus LoadoutEvidence must load before BuildCatalog")
local Identity = assert(Nexus.Identity,
    "Nexus Identity must load before BuildCatalog")
local Catalog = {}
Nexus.BuildCatalog = Catalog

local STORAGE_SCHEMA_VERSION = 1

------------------------------------------------------------------------
-- Durable authority kernel (MASTER-RC-001).
--
-- The accepted architecture at 3b5de54f names exactly one durable authority
-- payload slot, `authorityDatabase.authorityBundle`, written only by
-- AuthorityCommitCoordinatorV1 as one complete detached bundle, and exactly one
-- public authority pointer, `currentServingRoot`, written only by
-- AuthorityServingRootWriterV1 in two closed modes. Both live here.
------------------------------------------------------------------------

-- "Every durable generation or revision is an unsigned exact Lua 5.1 integer in
-- 0..9,007,199,254,740,991."
local GENERATION_MAXIMUM = 9007199254740991
local BUNDLE_SCHEMA_VERSION = 1

-- AuthorityDurableBundleV1. The order is the architecture's field order; the
-- catalog domain owns the first four, LoadoutEvidence owns the fifth, and the
-- remaining five are carried as complete detached snapshots until their own
-- owners route their writes through this coordinator.
local BUNDLE_PAYLOAD_FIELDS = {
    "communityBuilds", "syncTombstones", "buildCatalog",
    "communityRetentionEvictions", "loadoutEvidence", "dpsCapture",
    "dpsAuthority", "storeData", "dataRetention", "dataCompaction",
}
local BUNDLE_CATALOG_MAPS = {
    communityBuilds=true, syncTombstones=true, communityRetentionEvictions=true,
}
local BUNDLE_MUTATION_OVERRIDES = {
    dpsCapture=true, dataRetention=true, dataCompaction=true,
}
local BUNDLE_KNOWN_FIELDS = {schemaVersion=true, transactionGeneration=true}
for _, field in ipairs(BUNDLE_PAYLOAD_FIELDS) do BUNDLE_KNOWN_FIELDS[field] = true end

-- One shared immutable marker fills every domain field of an invalid serving
-- root. "Neither form uses absent/nil fields as state."
local INVALID_AUTHORITY_DOMAIN = {}

-- The six cursor families below share one bounded stale-sentinel cap.
local CURSOR_FAMILIES = {
    "record", "summary", "delta", "savedMirror", "diagnostic", "related",
}
local TOMBSTONE_SCHEMA_VERSION = 1
local BARRIER_SCHEMA_VERSION = 1
local TOMBSTONE_AGE = 180 * 24 * 60 * 60
local BARRIER_AGE = 30 * 24 * 60 * 60
local MAX_SAFE_INTEGER = 9007199254740991
-- Architecture 3b5de54f lines 1022-1060. This is the exact Pbuild ledger,
-- including the start-token capture pump and every named and derived frontier
-- term. Fixture drivers read it from Catalog.Budget instead of fitting a bound
-- to the bundled data set.
local ADMISSION_MAX_PUMPS = 58622488

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

-- A missing optional release bundle is one stable empty source. A fresh table
-- per Init call would change the source identity and restart any multi-slice
-- admission before its persistent frontier could complete.
local EMPTY_BUNDLED = {builds={}}

------------------------------------------------------------------------
-- Module state (one table keeps every closure inside the Lua 5.1 upvalue
-- limit). Nothing here is ever stored in SavedVariables.
------------------------------------------------------------------------

local ST = {
    db=nil, bundled=nil, baseline=nil,
    rootState="ROOT_UNBOUND", rootReason=nil,
    -- currentServingRoot is the sole public authority pointer. ST.published is
    -- deliberately gone: every reader goes through ServingCatalogRoot().
    currentServingRoot=nil, servingGeneration=0,
    -- The exact selected durable bundle and its durable transaction generation.
    durableBundle=nil, durableBundleGeneration=0,
    -- AUTHORITY_GENERATION_EXHAUSTED is an outer deny-only latch with precedence
    -- over every root/domain/API state. It is session state; a reload re-detects
    -- the maximum durable counter during bundle admission.
    exhausted=false,
    candidate=nil, futureToken=nil, sourceVerification=nil,
    bindingGeneration=0, committedMutationRevision=0, preparationEpoch=0,
    reservationEpoch=0, semanticGeneration=0, generation=0,
    sessionTombstones=setmetatable({}, {__mode="k"}),
    sessionBarriers=setmetatable({}, {__mode="k"}),
    readmittedBarriers=setmetatable({}, {__mode="k"}),
    claimRegistry=setmetatable({}, {__mode="k"}), activeClaim=nil,
    cursorRegistry=setmetatable({}, {__mode="k"}), activeCursors={},
    cursorSequence=0,
    maintenanceRegistry=setmetatable({}, {__mode="k"}), activeMaintenance=nil,
    mutationTickets=setmetatable({}, {__mode="k"}),
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
        notificationFailures=0, notificationReplays=0,
        notificationReplaysStale=0,
        maintenanceCommits=0, claimsIssued=0,
        mutationCompletionFailures=0,
        cursorsBegun=0, driftInvalidations=0,
        bundleWrites=0, servingSwaps=0, cursorSentinels=0,
        cursorRowsInspected=0, maxCursorRowsPerCall=0,
        cursorCopyNodes=0, cursorCopyBytes=0, cursorCopyPending=0,
        maxCursorCopyNodesPerCall=0, maxCursorCopyBytesPerCall=0,
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
-- MASTER-RC-012: the one canonical codec now lives in core/Identity.lua and is
-- shared with every other typed-identity consumer. The returned strings are
-- byte-identical to the private codec this replaced.
local function TypedKey(id)
    return Identity.TypedKey(id, BUDGET.keyWidth)
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

-- MASTER-RC-003: the canonical union rule lives in LoadoutEvidence. This used
-- to rank tuples by their source array, so the same semantic tuple carried in
-- both the inline and locked arrays became two members instead of one.
local function CompareTuples(left, right)
    return Evidence.CanonicalTupleOrder(left, right), 30
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
        -- Diagnostic only, never part of the published semantic record: the
        -- shape these counts were taken from.
        walker.semanticRepresentation = "inline"
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
local function ResolveEvidence(known, options)
    local evidence = Nexus and Nexus.LoadoutEvidence
    if not (evidence and type(evidence.Resolve) == "function") then return nil end
    local rows = {}
    local candidateOptions = options and options.candidateEvidence
        and {useCandidate=true} or nil
    if type(known.evidenceKey) == "string" and known.evidenceKey ~= "" then
        local ok, resolved = pcall(evidence.Resolve, known.evidenceKey, nil,
            candidateOptions)
        if ok and type(resolved) == "table" then
            for _, row in ipairs(resolved) do
                rows[#rows + 1] = {spellId=row.spellId, quality=row.quality,
                    stacks=row.stacks, locked=row.locked or nil, origin="inline"}
            end
        end
    end
    if type(known.lockedEvidenceKey) == "string" and known.lockedEvidenceKey ~= "" then
        local lockedOptions = {forceLocked=true}
        if candidateOptions then lockedOptions.useCandidate = true end
        local ok, resolved = pcall(evidence.Resolve, known.lockedEvidenceKey, nil,
            lockedOptions)
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
        local resolvedRows = ResolveEvidence(known, options)
        for _, row in ipairs(resolvedRows or {}) do
            local isLocked = row.origin == "lockedArray"
            if (isLocked and wantsLockedRole) or (not isLocked and wantsInline) then
                Admit(row)
            end
        end
        if resolvedRows then
            local semantic = SemanticOf(canonical)
            walker.semanticRepresentation = "referenced"
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
    local sessionTombstones = ST.candidate and ST.candidate.sessionTombstones
        or ST.sessionTombstones
    if sessionTombstones[raw] then
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
    local sessionBarriers = ST.candidate and ST.candidate.sessionBarriers
        or ST.sessionBarriers
    if sessionBarriers[raw] then
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
    -- MASTER-RC-004. A bundled row's coherent owner tuple is NOT delete
    -- authority. Architecture 3b5de54f line 193: "Bundled package row | Content
    -- fields and immutable bundled source position only. ... Bundled author text
    -- never proves local ownership." Line 188 makes ownerVerified, isMine and
    -- provenance fields "claims, not proof", and line 202 requires internally
    -- coherent spoofed tuples to obtain "zero verified-owner or mutation
    -- privilege". Only a derived verified owner carries authority, so the
    -- separate trusted-owner concept is removed rather than narrowed.
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

-- The related/exact index is part of the published root, so a replacement root
-- must not mutate the index a superseded root still references (MASTER-RC-001,
-- MASTER-RC-002). CloneIndex copies only the eight top-level maps; every bucket
-- below them is shared until a write touches it, and `owned` records the buckets
-- this index may mutate in place.
local INDEX_MAPS = {
    "exact", "fingerprints", "titles", "spells", "saved",
    "ownerClasses", "authors", "memberships",
}

local function NewIndex()
    return {owned={}, exact={}, fingerprints={}, titles={}, spells={},
        saved={}, ownerClasses={}, authors={}, memberships={}}
end

local function CloneIndex(index)
    local out = {owned={}}
    for _, name in ipairs(INDEX_MAPS) do
        local copy = {}
        for key, value in pairs(index[name]) do copy[key] = value end
        out[name] = copy
    end
    return out
end

-- Copy-on-write: a bucket created under an earlier index is shared with a
-- superseded root, so it is cloned before the first mutation in this index.
local function OwnBucket(index, map, bucketKey)
    if bucketKey == nil then return nil end
    local bucket = map[bucketKey]
    if bucket == nil or index.owned[bucket] then return bucket end
    local copy = {}
    for key, value in pairs(bucket) do
        if key == "ids" or key == "classes" or key == "idVector" then
            local inner = {}
            for innerKey, innerValue in pairs(value) do inner[innerKey] = innerValue end
            copy[key] = inner
        else
            copy[key] = value
        end
    end
    index.owned[copy] = true
    map[bucketKey] = copy
    return copy
end

local function BetterExactCandidate(id, verdict, currentId, currentVerdict)
    if not currentId or not currentVerdict then return true end
    local auto = verdict.snapshot.autoDps and true or false
    local currentAuto = currentVerdict.snapshot.autoDps and true or false
    if auto ~= currentAuto then return not auto end
    return Identity.CompareTypedIds(id, currentId) < 0
end

local function RecomputeExactWinner(rows, bucket)
    bucket.winnerKey, bucket.winnerId = nil, nil
    for _, key in ipairs(bucket.idVector) do
        local verdict = rows[key]
        if verdict and verdict.snapshot then
            if BetterExactCandidate(verdict.id, verdict, bucket.winnerId,
                bucket.winnerKey and rows[bucket.winnerKey]) then
                bucket.winnerKey, bucket.winnerId = key, verdict.id
            end
        end
    end
end

local function AddBucket(index, map, bucketKey, key, work, rows, prepaid)
    if not bucketKey then return nil end
    local bucket = OwnBucket(index, map, bucketKey)
    if not bucket then
        bucket = {ids={}, idVector={}, count=0}
        index.owned[bucket] = true
        map[bucketKey] = bucket
        if work and not prepaid then Charge(work, "indexNodes", 1) end
    end
    if not bucket.ids[key] then
        bucket.ids[key] = true
        bucket.count = bucket.count + 1
        local position = #bucket.idVector + 1
        if not work then
            for index = 1, #bucket.idVector do
                if CompareSlots(rows[key], rows[bucket.idVector[index]]) < 0 then
                    position = index
                    break
                end
            end
        end
        table.insert(bucket.idVector, position, key)
        if work and not prepaid then
            Charge(work, "indexEdges", 1)
            Charge(work, "indexBytes", #bucketKey + 18)
        end
    end
    return bucket
end

local function RemoveBucket(index, map, bucketKey, key)
    local bucket = bucketKey and OwnBucket(index, map, bucketKey) or nil
    if not bucket then return end
    if bucket.ids[key] then
        bucket.ids[key] = nil
        bucket.count = math.max(0, bucket.count - 1)
        for index, existing in ipairs(bucket.idVector) do
            if existing == key then table.remove(bucket.idVector, index); break end
        end
    end
    if bucket.count == 0 then map[bucketKey] = nil end
end

local function IndexRemove(index, rows, key)
    local membership = index.memberships[key]
    if not membership then return end
    local exactBucket = membership.exact
        and OwnBucket(index, index.exact, membership.exact) or nil
    if exactBucket and exactBucket.ids[key] then
        local field = membership.exactAuto and "autoCount" or "explicitCount"
        exactBucket[field] = math.max(0, (exactBucket[field] or 0) - 1)
    end
    RemoveBucket(index, index.exact, membership.exact, key)
    if exactBucket and index.exact[membership.exact] and exactBucket.winnerKey == key then
        RecomputeExactWinner(rows, exactBucket)
    end
    RemoveBucket(index, index.fingerprints, membership.fingerprint, key)
    RemoveBucket(index, index.titles, membership.title, key)
    RemoveBucket(index, index.saved, membership.saved, key)
    for _, spellKey in ipairs(membership.spells or {}) do
        RemoveBucket(index, index.spells, spellKey, key)
    end
    local owner = membership.classOwner
        and OwnBucket(index, index.ownerClasses, membership.classOwner) or nil
    if owner and owner.ids[key] then
        local class = owner.ids[key]
        owner.ids[key] = nil
        owner.count = owner.count - 1
        owner.classes[class] = (owner.classes[class] or 1) - 1
        if owner.classes[class] <= 0 then owner.classes[class] = nil end
        if owner.count <= 0 then index.ownerClasses[membership.classOwner] = nil end
    end
    if membership.author then
        local authorBucket = OwnBucket(index, index.authors, membership.author)
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
    local exactBucket = AddBucket(index, index.exact, exact, key, work, rows)
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
            local owner = OwnBucket(index, index.ownerClasses, verdict.verifiedOwner)
            if not owner then
                owner = {ids={}, classes={}, count=0}
                index.owned[owner] = true
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
        local authorBucket = OwnBucket(index, index.authors, authorKey)
        if not authorBucket then
            authorBucket = {}
            index.owned[authorBucket] = true
            index.authors[authorKey] = authorBucket
        end
        authorBucket[key] = true
        membership.author = authorKey
        if work then Charge(work, "indexEdges", 1) end
    end
    local author = RelatedText(snapshot.author)
    if author ~= "" then
        if savedKind == "saved" then
            membership.saved = RelatedKey(author, "saved")
            AddBucket(index, index.saved, membership.saved, key, work, rows)
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
                    AddBucket(index, index.spells, spellKey, key, work, rows)
                end
            end
            AddBucket(index, index.fingerprints, membership.fingerprint, key, work, rows)
            AddBucket(index, index.titles, membership.title, key, work, rows)
        end
    end
    index.memberships[key] = membership
end

------------------------------------------------------------------------
-- Root token, drift detection, published root
------------------------------------------------------------------------

------------------------------------------------------------------------
-- Generation domain (MASTER-RC-007)
------------------------------------------------------------------------

-- An unsigned exact Lua 5.1 integer in 0..GENERATION_MAXIMUM. A negative,
-- fractional, nonfinite, larger, or non-numeric value is malformed
-- current-schema evidence, never a current counter.
local function ExactGeneration(value)
    if type(value) ~= "number" then return false end
    if value ~= value then return false end
    if value == math.huge or value == -math.huge then return false end
    if value < 0 or value > GENERATION_MAXIMUM then return false end
    return math.floor(value) == value
end

-- One candidate settles one ticket, except a receiver batch, which settles one
-- ticket per member: a member refused while it was prepared keeps its own
-- refusal, every other member takes the candidate's outcome, and each ticket
-- is settled exactly once here.
local function SettleMutationTicket(handle, state, committed, reason, deferCallback)
    local function SettleOneTicket(ticket, ticketState, ticketCommitted,
                                   ticketReason, storedAs)
        ticket.state, ticket.committed = ticketState, ticketCommitted
        ticket.reason, ticket.pumps = ticketReason, handle.pumps
        if ticketCommitted then
            ticket.generation = ST.generation
            ticket.database, ticket.bundle = ST.db, ST.durableBundle
            ticket.storedAs = storedAs or handle.storedAs
        end
        if not ticketCommitted then ticket.detail = handle.failureDetail end
        ST.mutationTickets[ticket] = nil
        local callback = ticket.completionCallback
        ticket.completionCallback = nil
        return callback
    end
    local function RunTicketCallback(ticket, callback)
        if callback and not pcall(callback, ticket) then
            ST.debugStats.mutationCompletionFailures =
                ST.debugStats.mutationCompletionFailures + 1
        end
    end
    local members = handle.batch and handle.batch.members
    if not members then
        local ticket = handle.ticket or {}
        local callback = SettleOneTicket(ticket, state, committed, reason)
        if deferCallback then return ticket, callback end
        RunTicketCallback(ticket, callback)
        return ticket
    end
    local settled = {}
    for _, member in ipairs(members) do
        local ticket = member.ticket
        if ticket and ST.mutationTickets[ticket] ~= nil then
            local memberState, memberCommitted, memberReason =
                state, committed, reason
            if member.outcome == "failed" then
                memberState, memberCommitted, memberReason =
                    "failed", false, member.reason
            end
            settled[#settled + 1] = {ticket=ticket,
                callback=SettleOneTicket(ticket, memberState, memberCommitted,
                    memberReason, member.storedAs)}
        end
    end
    -- The candidate's own ticket carries no receiver callback; settling it
    -- keeps the registry free of a ticket nobody can complete.
    local own = handle.ticket
    if own and ST.mutationTickets[own] ~= nil then
        SettleOneTicket(own, state, committed, reason)
    end
    local first = own or (settled[1] and settled[1].ticket) or {}
    if deferCallback then
        return first, function()
            for _, row in ipairs(settled) do
                RunTicketCallback(row.ticket, row.callback)
            end
        end
    end
    for _, row in ipairs(settled) do
        RunTicketCallback(row.ticket, row.callback)
    end
    return first
end

-- Latch the outer deny-only state. It publishes no candidate, permits no read
-- that can grant authority, and is never cleared by byte equality: only a fresh
-- session (module reload) plus a durable counter below the maximum clears it.
local function LatchGenerationExhausted()
    local abandoned = ST.candidate
    ST.exhausted = true
    ST.rootState = "AUTHORITY_GENERATION_EXHAUSTED"
    ST.rootReason = "GENERATION_EXHAUSTED"
    ST.candidate = nil
    ST.activeClaim = nil
    ST.activeCursors = {}
    ST.activeMaintenance = nil
    ST.cursorRegistry = setmetatable({}, {__mode="k"})
    if abandoned and abandoned.mode == "mutation" then
        SettleMutationTicket(abandoned, "failed", false, "GENERATION_EXHAUSTED")
    end
end

-- One guarded counter authority owns every durable and session increment.
-- Plans are checked in full before the first counter changes, including the
-- per-item increments of a multi-row commit.
local Generation = {}

function Generation.Preflight(plan)
    for _, entry in ipairs(plan or {}) do
        local amount = tonumber(entry.amount) or 1
        local value = type(entry.owner) == "table" and entry.owner[entry.key] or nil
        if value == nil and entry.zeroDefault then value = 0 end
        if not ExactGeneration(value) or not ExactGeneration(amount)
            or amount < 1 or value > GENERATION_MAXIMUM - amount then
            LatchGenerationExhausted()
            return false, "GENERATION_EXHAUSTED"
        end
    end
    return true
end

function Generation.Advance(owner, key, amount, zeroDefault)
    amount = amount or 1
    local ok, why = Generation.Preflight({
        {owner=owner, key=key, amount=amount, zeroDefault=zeroDefault},
    })
    if not ok then return nil, why end
    owner[key] = (owner[key] or 0) + amount
    return owner[key]
end

function Generation.Next(owner, key, amount, zeroDefault)
    amount = amount or 1
    local ok, why = Generation.Preflight({
        {owner=owner, key=key, amount=amount, zeroDefault=zeroDefault},
    })
    if not ok then return nil, why end
    return (owner[key] or 0) + amount
end

-- The caller preflights the complete plan before entering the callback-free
-- publication section. Applying that same plan then consists only of writes to
-- private, plain owner tables and cannot discover a new refusal midway.
function Generation.ApplyPlan(plan, skipServing)
    for _, entry in ipairs(plan or {}) do
        if not (skipServing and entry.owner == ST
            and entry.key == "servingGeneration") then
            entry.owner[entry.key] = (entry.owner[entry.key] or 0)
                + (entry.amount or 1)
        end
    end
end

-- The three other resettable authority owners resolve this seam at the point
-- of each increment. A BuildCatalog reload therefore gives them a fresh guard
-- owner and the same outer deny-only latch; no module can continue incrementing
-- behind an exhausted catalog session.
Nexus.MainInternals = type(Nexus.MainInternals) == "table"
    and Nexus.MainInternals or {}
Nexus.MainInternals.CatalogAuthorityCounters = {owner=Catalog}
function Nexus.MainInternals.CatalogAuthorityCounters.Preflight(plan)
    return Generation.Preflight(plan)
end
function Nexus.MainInternals.CatalogAuthorityCounters.Advance(
        owner, key, amount, zeroDefault)
    return Generation.Advance(owner, key, amount, zeroDefault)
end
function Nexus.MainInternals.CatalogAuthorityCounters.Next(
        owner, key, amount, zeroDefault)
    return Generation.Next(owner, key, amount, zeroDefault)
end

function Generation.MutationPlan(items)
    local count = math.max(1, #items)
    local plan = {
        {owner=ST, key="durableBundleGeneration", amount=1},
        {owner=ST, key="preparationEpoch", amount=1},
        {owner=ST, key="servingGeneration", amount=1},
        {owner=ST, key="generation", amount=count},
        {owner=ST, key="committedMutationRevision", amount=count},
        {owner=ST, key="semanticGeneration", amount=count},
        {owner=ST, key="exactRevisionClock", amount=count},
    }
    local perRecord = {}
    local receiptCount = 0
    for _, item in ipairs(items) do
        local id = item.slot.id
        perRecord[id] = (perRecord[id] or 0) + 1
        receiptCount = receiptCount + #(item.receiptRecords or {})
    end
    for id, amount in pairs(perRecord) do
        plan[#plan + 1] = {owner=ST.recordRevisions, key=id,
            amount=amount, zeroDefault=true}
    end
    if receiptCount > 0 then
        plan[#plan + 1] = {owner=ST, key="receiptRevision",
            amount=receiptCount}
    end
    local evidence = Nexus and Nexus.LoadoutEvidence
    local evidencePlan = evidence
        and type(evidence.CandidateRevisionPlanV1) == "function"
        and evidence.CandidateRevisionPlanV1() or nil
    for _, entry in ipairs(type(evidencePlan) == "table"
            and evidencePlan or {}) do
        plan[#plan + 1] = entry
    end
    return plan
end

function Generation.PrepareReceiptRecords(items)
    local revision = ST.receiptRevision
    local count = 0
    for _, item in ipairs(items or {}) do
        for _, record in ipairs(item.receiptRecords or {}) do
            count = count + 1
            record.receiptRevision = revision + count
        end
    end
    return count
end

------------------------------------------------------------------------
-- AuthorityServingRootWriterV1 (MASTER-RC-001)
--
-- The sole serving-location writer, with exactly two closed assignment modes:
-- one initial invalid-bootstrap install and one protected final
-- replacement-or-sentinel swap. Every other assignment site is forbidden, and
-- the pointer never enters SavedVariables.
------------------------------------------------------------------------

local function NewServingRoot(catalogRoot, durableBundleGeneration)
    return {
        catalogRoot=catalogRoot,
        dpsRoot=INVALID_AUTHORITY_DOMAIN,
        evidenceRoot=INVALID_AUTHORITY_DOMAIN,
        providerRegistryRoot=INVALID_AUTHORITY_DOMAIN,
        durableBundleGeneration=durableBundleGeneration or 0,
        generation=0,
    }
end

-- InvalidBootstrapServingRootV1 and the ordinary invalid sentinel share one
-- shape: all four domain fields reference the same immutable marker.
local function NewInvalidServingRoot()
    return NewServingRoot(INVALID_AUTHORITY_DOMAIN, 0)
end

local function AuthorityServingRootWriterV1(mode, serving)
    if mode == "initial-invalid-install" then
        if ST.currentServingRoot ~= nil then return false end
        serving = NewInvalidServingRoot()
        serving.generation = 0
        ST.currentServingRoot = serving
        return true
    end
    if mode ~= "final-swap" then return false end
    if type(serving) ~= "table" or not ExactGeneration(serving.generation)
        or serving.generation == 0 then return false end
    ST.currentServingRoot = serving
    return true
end

-- MASTER-RC-001 REOPENED ELEMENT: serving publication order.
-- Architecture 1517-1519 permits the final `currentServingRoot` swap only in
-- `STORE_SERVING_PUBLICATION_PENDING`, after legacy disposition completes, and
-- line 1715 says a bootstrap `Init` yields "only a detached bounded summary of
-- the privately sealed generation; it becomes public only in the final
-- all-domain serving publication."
--
-- While the startup coordinator holds the seal, a completed admission installs
-- NO public pointer: the constructed serving root is retained privately in
-- ST.sealedServing and swapped in only when the coordinator reaches its own
-- serving-publication state. Outside bootstrap -- ordinary rebind, maintenance
-- readmission, post-ready supersession -- nothing changes and the swap is
-- immediate, so this narrows bootstrap only.
--
-- The coordinator owns the ordering: it opens and closes the seal through the
-- two entries below. BuildCatalog never inspects coordinator state and never
-- drives it, which keeps lines 1207-1211 satisfied.
function Catalog.BeginBootstrapSealV1()
    ST.bootstrapSeal = true
    ST.sealedServing = nil
    return true
end

function Catalog.PublishSealedServingV1()
    ST.bootstrapSeal = nil
    local sealed = ST.sealedServing
    ST.sealedServing = nil
    if type(sealed) ~= "table" then return false end
    local generation, why = Generation.Advance(ST, "servingGeneration")
    if not generation then return false, why end
    sealed.generation = generation
    local published = AuthorityServingRootWriterV1("final-swap", sealed)
    if published then
        ST.debugStats.servingSwaps = ST.debugStats.servingSwaps + 1
    end
    return published
end

function Catalog.SealedServingPendingV1()
    return ST.sealedServing ~= nil
end

-- Every consumer obtains the catalog root only through the serving pointer.
-- There is no separately consumable public catalog pointer.
local function ServingCatalogRoot()
    local serving = ST.currentServingRoot
    if type(serving) ~= "table" then return nil end
    local root = serving.catalogRoot
    if root == nil or root == INVALID_AUTHORITY_DOMAIN then return nil end
    return root
end

-- Publish the ordinary invalid sentinel. This never restores slots and never
-- republishes a prior token.
local function PublishInvalidServing()
    local generation = Generation.Advance(ST, "servingGeneration")
    if not generation then return false, "GENERATION_EXHAUSTED" end
    local serving = NewInvalidServingRoot()
    serving.generation = generation
    local published = AuthorityServingRootWriterV1("final-swap", serving)
    if published then
        ST.debugStats.servingSwaps = ST.debugStats.servingSwaps + 1
    end
    return published
end

------------------------------------------------------------------------
-- AuthorityCommitCoordinatorV1 (MASTER-RC-001, MASTER-RC-005)
--
-- The sole durable writer of `authorityDatabase.authorityBundle`. It accepts
-- only a complete detached AuthorityDurableBundleV1 and replaces the pointer
-- exactly once; it never mutates a live nested bundle field.
--
-- Scope note, recorded rather than assumed: this slice implements the writer,
-- the complete-bundle shape, the generation domain, and the serving pointer.
-- Bundle-versus-legacy *read* precedence (the ordered Store selection table and
-- the STORE_READY gate) belongs to the bootstrap element of MASTER-RC-001 owned
-- by core/Store.lua and core/MainLifecycle.lua and is not closed here. Until it
-- lands, the exact PR #68 locations remain the admission inputs and are kept
-- byte-equal to the published bundle payload by the legacy compatibility mirror
-- in CommitBatch. This is a bounded, disclosed remainder, not a downgrade.
------------------------------------------------------------------------

local function ShallowSnapshot(value)
    if type(value) ~= "table" then return {} end
    local out = {}
    for key, child in pairs(value) do out[key] = child end
    return out
end

-- The common raw bundle discriminator. It inspects only the slot's Lua type,
-- metatable, raw schema discriminator, and generation domain, and never falls
-- back to a legacy location once any nonnil bundle exists.
local function ClassifyDurableBundle(db)
    local raw = rawget(db, "authorityBundle")
    if raw == nil then return "absent" end
    if type(raw) ~= "table" or getmetatable(raw) ~= nil then
        return "invalid", "AUTHORITY_BUNDLE_INVALID"
    end
    local version = rawget(raw, "schemaVersion")
    if ExactGeneration(version) and version > BUNDLE_SCHEMA_VERSION then
        return "future", "AUTHORITY_BUNDLE_FUTURE_SCHEMA", raw, version
    end
    if version ~= BUNDLE_SCHEMA_VERSION then
        return "invalid", "AUTHORITY_BUNDLE_INVALID"
    end
    local generation = rawget(raw, "transactionGeneration")
    if not ExactGeneration(generation) or generation < 1 then
        return "invalid", "AUTHORITY_BUNDLE_INVALID"
    end
    for key in pairs(raw) do
        if not BUNDLE_KNOWN_FIELDS[key] then
            return "invalid", "AUTHORITY_BUNDLE_INVALID"
        end
    end
    -- Reload detects a maximum selected durable counter before current-schema
    -- admission and re-enters the deny-only state.
    if generation >= GENERATION_MAXIMUM then
        return "exhausted", "GENERATION_EXHAUSTED", raw, generation
    end
    return "current", nil, raw, generation
end

-- One complete detached bundle. Every payload field is a fresh table, so a
-- superseded bundle graph stays byte-exact after the replacement.
--
-- `source` is the exact selected authority input for the catalog domain's four
-- payload fields: the occupied bundle after bundle occupancy, and the exact
-- PR #68 legacy locations only while the bundle is absent. State machine line
-- 394 gives those locations "No Package B writer / Legacy admission only /
-- Preserved legacy input when the bundle is absent. Never used as fallback
-- after bundle occupancy."
--
-- The remaining six fields are carried forward from the bound database, because
-- their owners (Store, LegacyDataMigration, DpsCapture, DataRetention,
-- DataCompaction, and the evidence owner) are not yet routed through this
-- coordinator. That is the disclosed bootstrap remainder of MASTER-RC-001
-- recorded in the checkpoint, not an accepted end state.
local function BuildDurableBundleCandidate(db, source, generation, overrides)
    local bundle = {
        schemaVersion=BUNDLE_SCHEMA_VERSION,
        transactionGeneration=generation,
    }
    for _, field in ipairs(BUNDLE_PAYLOAD_FIELDS) do
        local override = overrides and overrides[field]
        local origin = (BUNDLE_CATALOG_MAPS[field] or field == "buildCatalog")
            and source or db
        if override ~= nil then
            bundle[field] = override
        elseif field == "dpsAuthority" then
            -- MASTER-RC-001: DpsAuthorityOwnerV1 owns the durable DPS sidecar
            -- and offers it through the internals seam, the same way the Store
            -- and evidence owners offer theirs. It is never read from the
            -- database.
            local internals = Nexus and Nexus.MainInternals
            local owner = type(internals) == "table"
                and internals.DpsAuthority or nil
            local owned = owner and type(owner.Sidecar) == "function"
                and owner.Sidecar(db) or nil
            bundle[field] = owned or ShallowSnapshot(nil)
        elseif field == "storeData" then
            -- MASTER-RC-001: the Store owner builds one detached StoreDataV1
            -- during STORE_CHAR_MIGRATION_PENDING and offers it through the
            -- internals seam. Asking the owner keeps one construction rule for
            -- the domain, exactly as loadoutEvidence does below, and RAW-01
            -- forbids `authorityDatabase.storeData` surviving as a top-level
            -- field, so it is never read from the database.
            local internals = Nexus and Nexus.MainInternals
            local owner = type(internals) == "table"
                and internals.AuthorityBootstrap or nil
            local owned = owner
                and type(owner.DurableStoreData) == "function"
                and owner.DurableStoreData(db) or nil
            bundle[field] = owned or ShallowSnapshot(nil)
        elseif field == "loadoutEvidence" then
            -- The evidence owner selects its own durable payload: the bundle's
            -- field after occupancy, the preserved legacy input only while the
            -- bundle is absent (state machine line 394). Asking the owner keeps
            -- one selection rule for the domain instead of a second one here,
            -- and it never reads the legacy location after occupancy. The
            -- entries map is detached as well, so no live nested bundle field
            -- is ever carried by reference into the replacement.
            local owner = Nexus and Nexus.LoadoutEvidence
            local owned = owner and type(owner.DurableStore) == "function"
                and owner.DurableStore(db) or nil
            if type(owned) ~= "table" then owned = rawget(origin, field) end
            local snapshot = ShallowSnapshot(owned)
            snapshot.entries = ShallowSnapshot(snapshot.entries)
            bundle[field] = snapshot
        else
            bundle[field] = ShallowSnapshot(rawget(origin, field))
        end
    end
    return bundle
end

------------------------------------------------------------------------
-- Evidence candidate seam (MASTER-RC-005)
--
-- EvidenceCoordinator builds only evidence fields and never writes
-- SavedVariables. The catalog opens a detached candidate before preparation, so
-- every intern performed while a candidate is being built lands in the detached
-- store and becomes durable only inside the complete bundle.
------------------------------------------------------------------------

local function EvidenceOwner()
    local evidence = Nexus and Nexus.LoadoutEvidence
    if type(evidence) ~= "table" then return nil end
    if type(evidence.BeginCandidate) ~= "function" then return nil end
    return evidence
end

local function EvidenceBeginCandidate()
    local evidence = EvidenceOwner()
    if evidence then evidence.BeginCandidate(ST.db) end
end

-- The complete detached replacement store, or nil when this transaction interned
-- nothing and the current durable store is carried unchanged.
local function EvidenceCandidateStore()
    local evidence = EvidenceOwner()
    if not evidence then return nil end
    return evidence.CandidateStore()
end

local function EvidencePublishCandidate()
    local evidence = EvidenceOwner()
    if evidence then evidence.PublishCandidate() end
end

local function EvidenceCancelCandidate()
    local evidence = EvidenceOwner()
    if evidence then evidence.CancelCandidate() end
end

------------------------------------------------------------------------
-- Cursor root release (MASTER-RC-011)
--
-- Release old root and accumulator state at publication and supersession.
-- At most one bounded stale-once sentinel survives per cursor family; every
-- other superseded entry leaves the registry and its next use is INVALID_CURSOR.
------------------------------------------------------------------------

local function ReleaseSupersededCursors()
    local registry = ST.cursorRegistry
    if type(registry) ~= "table" then return end
    local sentinel = {}
    local drop = {}
    for token, state in pairs(registry) do
        if state.servingGeneration ~= ST.servingGeneration then
            local family = state.kind
            if sentinel[family] then
                drop[#drop + 1] = token
            else
                sentinel[family] = true
                -- The sentinel keeps no root wrapper, no accumulator, and no
                -- page state: only enough to refuse once with STALE_CURSOR.
                registry[token] = {kind=family, stale=true,
                    servingGeneration=state.servingGeneration}
                ST.debugStats.cursorSentinels = ST.debugStats.cursorSentinels + 1
            end
        end
    end
    for _, token in ipairs(drop) do registry[token] = nil end
end

local function RetainedRootCount()
    local registry = ST.cursorRegistry
    if type(registry) ~= "table" then return 0 end
    local held = 0
    for _, state in pairs(registry) do
        if state.servingGeneration ~= ST.servingGeneration then held = held + 1 end
    end
    return held
end

-- The only Package B durable payload write, immediately followed by its
-- identity verification.
local function CommitDurableBundle(db, bundle)
    rawset(db, "authorityBundle", bundle)
    if rawget(db, "authorityBundle") ~= bundle then return false end
    return true
end

function Generation.EvidenceCandidateChanged()
    local evidence = EvidenceOwner()
    local plan = evidence
        and type(evidence.CandidateRevisionPlanV1) == "function"
        and evidence.CandidateRevisionPlanV1() or nil
    return type(plan) == "table" and #plan > 0
end

-- The serving witness binds the exact authority input the root was admitted
-- from. After bundle occupancy that is the durable bundle pointer and its four
-- catalog payload field identities; the exact PR #68 legacy locations are
-- witnessed only while the bundle is absent, which is the one condition under
-- which line 394 makes them admission input at all.
-- MASTER-RC-017. The bounded per-key serving witness. Architecture line 454:
-- admission stores "a detached, bounded exact SourceWitness for the complete
-- selected raw source, including known and unknown keys, values, aliases, table
-- topology, and provenance. The witness is not a hash and no digest collision
-- can grant authority." Line 137 makes a per-key witness change current-source
-- drift, and line 140 makes a missing or replaced witness bound by the public
-- root invalidate that root.
--
-- Whole-map table identity cannot see a row replaced, added, or removed inside
-- an unchanged map, so the witness records the exact admitted value identity of
-- every key plus the key count. It stores identities, never digests.
--
-- One file-level local is spent on purpose: core/BuildCatalog.lua is close to
-- the Lua 5.1 200 file-level local ceiling, so the capture and recheck helpers
-- are fields of one table rather than two more locals.
local Witness = {
    EDGE_MAXIMUM=BUDGET.edges,
    NODE_MAXIMUM=BUDGET.nodes,
    BYTE_MAXIMUM=BUDGET.bytesInspected,
    DEPTH_MAXIMUM=BUDGET.depth + 2,
}

-- MASTER-RC-017 REOPENED ELEMENT: the bundled baseline is an admitted source.
-- The bundled `builds` map is what the root is admitted FROM, so architecture
-- lines 135-141 make it a backing table behind the public root and any change
-- to it current-source drift. It is RE-READ from the bundle on every recheck:
-- ST.baseline is written only inside BeginRootAdmission, so comparing a token
-- field back to it -- as the removed `baselineIdentity` check did -- could
-- never observe a change made behind the root.
function Witness.BaselineMap()
    local bundled = ST.bundled
    if type(bundled) ~= "table" then return nil end
    local builds = rawget(bundled, "builds")
    if type(builds) ~= "table" then return nil end
    return builds
end

function Witness.SelectedRoots(source)
    return {
        {name="communityBuilds", value=rawget(source, "communityBuilds")},
        {name="syncTombstones", value=rawget(source, "syncTombstones")},
        {name="buildCatalog", value=rawget(source, "buildCatalog")},
        {name="communityRetentionEvictions",
            value=rawget(source, "communityRetentionEvictions")},
        {name="bundledBuilds", value=Witness.BaselineMap()},
    }
end
-- Persistent shallow bundle construction. Each pump copies no more than the
-- V1 edge/node/byte slice. Nested catalog rows remain immutable identities;
-- the evidence entries map receives its own detached top-level map.
local Candidate, Cursor = {}, {}
Candidate.EvidenceCandidateStore = EvidenceCandidateStore

function Candidate.SourceValue(db, source, field)
    if field == "dpsAuthority" then
        local internals = Nexus and Nexus.MainInternals
        local owner = type(internals) == "table" and internals.DpsAuthority or nil
        return owner and type(owner.Sidecar) == "function" and owner.Sidecar(db) or nil
    end
    if field == "storeData" then
        local internals = Nexus and Nexus.MainInternals
        local owner = type(internals) == "table"
            and internals.AuthorityBootstrap or nil
        return owner and type(owner.DurableStoreData) == "function"
            and owner.DurableStoreData(db) or nil
    end
    if field == "loadoutEvidence" then
        local owner = Nexus and Nexus.LoadoutEvidence
        local owned = owner and type(owner.DurableStore) == "function"
            and owner.DurableStore(db) or nil
        if type(owned) == "table" then return owned end
    end
    -- Once a complete bundle exists, every unchanged payload field is carried
    -- from that bundle. Legacy database fields remain preserved bootstrap
    -- input and can never overwrite a newer accepted bundle value.
    local origin = type(source) == "table" and source or db
    return rawget(origin, field)
end

function Candidate.NewBundle(db, source, generation, overrides, drops, items)
    return {db=db, source=source, generation=generation,
        overrides=overrides or {}, drops=drops or {}, fieldIndex=1,
        bundle={schemaVersion=BUNDLE_SCHEMA_VERSION,
            transactionGeneration=generation}, current=nil, nested=nil,
        items=items or {}, writeItemIndex=1, writeIndex=1}
end

function Candidate.PumpCopy(task, work)
    while not Exhausted(work.budget) do
        local pending = task.pending
        if not pending then
            local ok, key, value = pcall(next, task.source, task.cursor)
            if not ok then return false, "ROOT_MAP_MALFORMED" end
            if key == nil then return true end
            pending = {key=key, value=value,
                bytes=ScalarBytes(key) + ScalarBytes(value)}
            task.pending = pending
            Charge(work, "edges", 1)
            Charge(work, "nodes", 1)
        end
        local bytes = math.min(pending.bytes,
            SLICE.bytesInspected - work.budget.bytesInspected)
        if bytes > 0 then
            Charge(work, "bytesInspected", bytes)
            pending.bytes = pending.bytes - bytes
        end
        if pending.bytes > 0 then return nil end
        task.cursor = pending.key
        if not (task.drop and task.drop[pending.key]) then
            task.target[pending.key] = pending.value
        end
        task.pending = nil
    end
    return nil
end

function Candidate.PumpBundle(handle, work)
    while handle.fieldIndex <= #BUNDLE_PAYLOAD_FIELDS do
        if handle.nested then
            local complete, reason = Candidate.PumpCopy(handle.nested, work)
            if complete == false then return false, reason end
            if not complete then return nil end
            handle.nested = nil
            handle.fieldIndex = handle.fieldIndex + 1
        elseif handle.current then
            local complete, reason = Candidate.PumpCopy(handle.current, work)
            if complete == false then return false, reason end
            if not complete then return nil end
            if handle.current.field == "loadoutEvidence" then
                local entries = rawget(handle.current.source, "entries")
                if type(entries) == "table" then
                    local target = {}
                    handle.current.target.entries = target
                    handle.nested = {source=entries, target=target, cursor=nil}
                end
            end
            handle.current = nil
            if not handle.nested then handle.fieldIndex = handle.fieldIndex + 1 end
        else
            local field = BUNDLE_PAYLOAD_FIELDS[handle.fieldIndex]
            local override = handle.overrides[field]
            if override ~= nil then
                handle.bundle[field] = override
                handle.fieldIndex = handle.fieldIndex + 1
                Charge(work, "nodes", 1)
            else
                local source = Candidate.SourceValue(handle.db, handle.source, field)
                if type(source) ~= "table" or getmetatable(source) ~= nil then
                    source = {}
                end
                local target = {}
                handle.bundle[field] = target
                handle.current = {field=field, source=source, target=target,
                    cursor=nil, drop=handle.drops[field]}
                Charge(work, "nodes", 1)
            end
        end
        if handle.nested == nil and handle.current == nil
            and handle.fieldIndex <= #BUNDLE_PAYLOAD_FIELDS then
            -- The just-finished field has no nested copy.
        elseif Exhausted(work.budget) then
            return nil
        end
    end
    while handle.writeItemIndex <= #handle.items do
        if Exhausted(work.budget) then return nil end
        local item = handle.items[handle.writeItemIndex]
        local write = item and item.writes[handle.writeIndex] or nil
        if write then
            local map = handle.bundle[write.map]
            if type(map) ~= "table" then return false, "ROOT_MAP_MALFORMED" end
            map[write.id] = write.value
            handle.writeIndex = handle.writeIndex + 1
            Charge(work, "edges", 1)
            Charge(work, "nodes", 1)
            Charge(work, "bytesInspected", ScalarBytes(write.id)
                + ScalarBytes(write.value))
        else
            handle.writeItemIndex = handle.writeItemIndex + 1
            handle.writeIndex = 1
        end
    end
    return true
end

function Candidate.NewMutation(root, items, reason, deferred, notifyScope,
                               existingHandle, bundleOverrides, publishPlan)
    local generation, why = Generation.Next(ST, "durableBundleGeneration")
    if not generation then return nil, why end
    local overrides = {}
    for _, field in ipairs(BUNDLE_PAYLOAD_FIELDS) do
        if bundleOverrides and bundleOverrides[field] ~= nil then
            overrides[field] = bundleOverrides[field]
        end
    end
    local stagedEvidence = Candidate.EvidenceCandidateStore()
    if stagedEvidence ~= nil then overrides.loadoutEvidence = stagedEvidence end
    local handle = existingHandle or {}
    local ticket = handle.ticket
    if not ticket then
        ticket = {state="pending", committed=false, pumps=handle.pumps or 0}
        ST.mutationTickets[ticket] = true
    end
    handle.mode, handle.phase = "mutation", "mutation-bundle"
    handle.preparationIdentity = handle.preparationIdentity or {}
    handle.counters = handle.counters or NewCounters()
    handle.pumps, handle.failure = handle.pumps or 0, nil
    handle.token, handle.originalRoot, handle.ticket = root.token, root, ticket
    handle.items, handle.reason = items, reason
    handle.deferred, handle.notifyScope = deferred, notifyScope
    handle.publishPlan = publishPlan
    handle.bundleClass, handle.bundleGeneration = "current", ST.durableBundleGeneration
    handle.bundleWrite, handle.source = true, ST.durableBundle
    handle.slots, handle.slotVector, handle.slotCount = {}, {}, 0
    handle.mapIndex, handle.mapCursor, handle.rootMapEdges = 1, nil, 0
    handle.verdicts, handle.index, handle.rowIndex = {}, NewIndex(), 0
    handle.mutationStates = {}
    handle.indexIndex, handle.counts, handle.mapCounts = 0, nil, {}
    handle.sessionTombstones = setmetatable({}, {__mode="k"})
    handle.sessionBarriers = setmetatable({}, {__mode="k"})
    handle.put = nil
    handle.bundleBuilder = Candidate.NewBundle(ST.db, ST.durableBundle,
        generation, overrides, nil, items)
    handle.sessionCopy = {source=ST.sessionTombstones,
        target=handle.sessionTombstones, cursor=nil}
    return handle
end

function Candidate.ConfigureMutationAdmission(handle)
    local source = handle.finalBundle
    handle.source, handle.bundleRaw = source, source
    handle.bundleGeneration = source.transactionGeneration
    local classification, reason, _, version =
        Candidate.ClassifyMetadata(rawget(source, "buildCatalog"))
    if classification ~= "current" then
        return false, reason or (classification == "future"
            and "FUTURE_SCHEMA" or "ROOT_MAP_MALFORMED")
    end
    handle.metaVersion = version
    local okOverlay, overlay = Candidate.PlainMapOrNil(rawget(source, "communityBuilds"))
    local okTomb, tombstones = Candidate.PlainMapOrNil(rawget(source, "syncTombstones"))
    local okEvict, evictions = Candidate.PlainMapOrNil(
        rawget(source, "communityRetentionEvictions"))
    local okBundle, bundledMap = Candidate.PlainMapOrNil(ST.baseline)
    if not (okOverlay and okTomb and okEvict and okBundle) then
        return false, "ROOT_MAP_MALFORMED"
    end
    handle.maps = {overlay=overlay, bundled=bundledMap,
        tombstone=tombstones, barrier=evictions}
    handle.phase = "collect"
    return true
end

function Witness.ScalarEdge(value)
    local kind = type(value)
    if kind == "nil" then return {kind="nil"} end
    if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then
        return nil
    end
    return {kind=kind, value=value}
end

function Witness.NewCapture(source)
    return {mode="capture", roots=Witness.SelectedRoots(source), rootIndex=1,
        witness={roots={}, nodes={}, edgeCount=0, nodeCount=0, byteCount=0},
        sourceToNode={}, frames={}, pending=nil, done=false}
end

function Witness.Fail(handle, reason)
    handle.done, handle.failure = true, reason or "SOURCE_WITNESS_INVALID"
    return {state="failed", reason=handle.failure}
end

function Witness.EnqueueCaptureTable(handle, value, depth)
    if depth > Witness.DEPTH_MAXIMUM then
        return nil, "SOURCE_WITNESS_INVALID"
    end
    local existing = handle.sourceToNode[value]
    if existing then return {kind="table", node=existing} end
    local witness = handle.witness
    if witness.nodeCount >= Witness.NODE_MAXIMUM then
        return nil, "SOURCE_WITNESS_LIMIT"
    end
    local id = witness.nodeCount + 1
    witness.nodeCount = id
    local record = {identity=value, edges={}, count=0}
    witness.nodes[id] = record
    handle.sourceToNode[value] = id
    handle.frames[#handle.frames + 1] = {
        source=value, record=record, cursor=nil, depth=depth,
    }
    return {kind="table", node=id}, nil, true
end

function Witness.CaptureValue(handle, value, depth)
    if type(value) == "table" then
        return Witness.EnqueueCaptureTable(handle, value, depth)
    end
    local edge = Witness.ScalarEdge(value)
    if not edge then return nil, "SOURCE_WITNESS_INVALID" end
    return edge
end

function Witness.BeginVerify(witness, source)
    if type(witness) ~= "table" or type(witness.roots) ~= "table"
        or type(witness.nodes) ~= "table" then
        return {mode="verify", done=true, failure="SOURCE_WITNESS_MISSING"}
    end
    return {mode="verify", witness=witness,
        roots=Witness.SelectedRoots(source), rootIndex=1,
        sourceToNode={}, nodeToSource={}, frames={}, pending=nil, done=false}
end

function Witness.EnqueueVerifyTable(handle, value, expectedNode, depth)
    if type(value) ~= "table" or depth > Witness.DEPTH_MAXIMUM then
        return false, "SOURCE_DRIFT"
    end
    local mapped = handle.sourceToNode[value]
    if mapped and mapped ~= expectedNode then return false, "SOURCE_DRIFT" end
    local reverse = handle.nodeToSource[expectedNode]
    if reverse and reverse ~= value then return false, "SOURCE_DRIFT" end
    if mapped then return true end
    local record = handle.witness.nodes[expectedNode]
    if type(record) ~= "table" or record.identity ~= value then
        return false, "SOURCE_DRIFT"
    end
    handle.sourceToNode[value], handle.nodeToSource[expectedNode] =
        expectedNode, value
    handle.frames[#handle.frames + 1] = {
        source=value, record=record, cursor=nil, count=0, depth=depth,
    }
    return true, nil, true
end

function Witness.VerifyValue(handle, value, expected, depth)
    if type(expected) ~= "table" then return false, "SOURCE_DRIFT" end
    if expected.kind == "table" then
        return Witness.EnqueueVerifyTable(handle, value, expected.node, depth)
    end
    local sameNaN = expected.kind == "number" and type(value) == "number"
        and value ~= value and expected.value ~= expected.value
    if type(value) ~= expected.kind or (value ~= expected.value and not sameNaN) then
        return false, "SOURCE_DRIFT"
    end
    return true
end

function Witness.ResumePending(handle, budget)
    local pending = handle.pending
    if not pending then return true end
    local charged = math.min(budget.maximumBytes - budget.bytes, pending.bytes)
    budget.bytes = budget.bytes + charged
    pending.bytes = pending.bytes - charged
    if pending.bytes > 0 then return false end
    handle.pending = nil
    local ok, reason, created = pending.finish()
    if not ok then Witness.Fail(handle, reason); return false end
    budget.edges = budget.edges + 1
    if created then budget.nodes = budget.nodes + 1 end
    return true
end

function Witness.Defer(handle, budget, byteCost, finish)
    handle.pending = {bytes=byteCost, finish=finish}
    return Witness.ResumePending(handle, budget)
end

function Witness.Pump(handle, limits)
    if type(handle) ~= "table" then
        return {state="failed", reason="SOURCE_WITNESS_MISSING"}
    end
    if handle.done then
        return handle.failure and {state="failed", reason=handle.failure}
            or {state="complete"}
    end
    limits = limits or {}
    local budget = {edges=0, nodes=0, bytes=0,
        maximumEdges=limits.edges or 64,
        maximumNodes=limits.nodes or 64,
        maximumBytes=limits.bytes or 2048}
    if not Witness.ResumePending(handle, budget) then
        if handle.failure then return {state="failed", reason=handle.failure} end
        return {state="pending", edges=budget.edges, nodes=budget.nodes,
            bytes=budget.bytes}
    end
    while budget.edges < budget.maximumEdges
        and budget.nodes < budget.maximumNodes
        and budget.bytes < budget.maximumBytes do
        if handle.rootIndex <= #handle.roots then
            local index = handle.rootIndex
            local actual = handle.roots[index]
            local expected = handle.mode == "verify"
                and handle.witness.roots[index] or nil
            handle.rootIndex = index + 1
            local function FinishRoot()
                if handle.mode == "capture" then
                    local edge, reason, created = Witness.CaptureValue(
                        handle, actual.value, 1)
                    if not edge then return false, reason end
                    handle.witness.roots[index] = {name=actual.name, edge=edge}
                    return true, nil, created
                end
                if type(expected) ~= "table" or expected.name ~= actual.name then
                    return false, "SOURCE_DRIFT"
                end
                return Witness.VerifyValue(handle, actual.value, expected.edge, 1)
            end
            if not Witness.Defer(handle, budget,
                ScalarBytes(actual.name) + ScalarBytes(actual.value), FinishRoot) then
                if handle.failure then return {state="failed", reason=handle.failure} end
                return {state="pending", edges=budget.edges, nodes=budget.nodes,
                    bytes=budget.bytes}
            end
        else
            local frame = handle.frames[#handle.frames]
            if not frame then
                handle.done = true
                return {state="complete", edges=budget.edges,
                    nodes=budget.nodes, bytes=budget.bytes}
            end
            local metatable = getmetatable(frame.source)
            if not frame.metadataDone and (metatable ~= nil
                or frame.record.metatable ~= nil) then
                frame.metadataDone = true
                local function FinishMetatable()
                    if handle.mode == "capture" then
                        if handle.witness.edgeCount >= Witness.EDGE_MAXIMUM then
                            return false, "SOURCE_WITNESS_LIMIT"
                        end
                        local edge, reason, created = Witness.CaptureValue(
                            handle, metatable, frame.depth + 1)
                        if not edge then return false, reason end
                        frame.record.metatable = edge
                        handle.witness.edgeCount = handle.witness.edgeCount + 1
                        handle.witness.byteCount = handle.witness.byteCount
                            + ScalarBytes(metatable)
                        if handle.witness.byteCount > Witness.BYTE_MAXIMUM then
                            return false, "SOURCE_WITNESS_LIMIT"
                        end
                        return true, nil, created
                    end
                    return Witness.VerifyValue(handle, metatable,
                        frame.record.metatable, frame.depth + 1)
                end
                if not Witness.Defer(handle, budget, ScalarBytes(metatable),
                    FinishMetatable) then
                    if handle.failure then return {state="failed", reason=handle.failure} end
                    return {state="pending", edges=budget.edges, nodes=budget.nodes,
                        bytes=budget.bytes}
                end
            else
                frame.metadataDone = true
                local ok, key, value = pcall(next, frame.source, frame.cursor)
                if not ok then return Witness.Fail(handle, "SOURCE_WITNESS_INVALID") end
                if key == nil then
                    if handle.mode == "verify" and frame.count ~= frame.record.count then
                        return Witness.Fail(handle, "SOURCE_DRIFT")
                    end
                    handle.frames[#handle.frames] = nil
                else
                    frame.cursor = key
                    if type(key) ~= "string" and type(key) ~= "number"
                        and type(key) ~= "boolean" then
                        return Witness.Fail(handle, "SOURCE_WITNESS_INVALID")
                    end
                    local function FinishEdge()
                        if handle.mode == "capture" then
                            local witness = handle.witness
                            if witness.edgeCount >= Witness.EDGE_MAXIMUM then
                                return false, "SOURCE_WITNESS_LIMIT"
                            end
                            local edge, reason, created = Witness.CaptureValue(
                                handle, value, frame.depth + 1)
                            if not edge then return false, reason end
                            frame.record.edges[key] = edge
                            frame.record.count = frame.record.count + 1
                            witness.edgeCount = witness.edgeCount + 1
                            witness.byteCount = witness.byteCount
                                + ScalarBytes(key) + ScalarBytes(value)
                            if witness.byteCount > Witness.BYTE_MAXIMUM then
                                return false, "SOURCE_WITNESS_LIMIT"
                            end
                            return true, nil, created
                        end
                        local expected = frame.record.edges[key]
                        if expected == nil then return false, "SOURCE_DRIFT" end
                        local verified, reason, created = Witness.VerifyValue(
                            handle, value, expected, frame.depth + 1)
                        if not verified then return false, reason end
                        frame.count = frame.count + 1
                        return true, nil, created
                    end
                    if not Witness.Defer(handle, budget,
                        ScalarBytes(key) + ScalarBytes(value), FinishEdge) then
                        if handle.failure then return {state="failed", reason=handle.failure} end
                        return {state="pending", edges=budget.edges, nodes=budget.nodes,
                            bytes=budget.bytes}
                    end
                end
            end
        end
    end
    return {state="pending", edges=budget.edges, nodes=budget.nodes,
        bytes=budget.bytes}
end

function Witness.Capture(source)
    local handle = Witness.NewCapture(source)
    local result = Witness.Pump(handle)
    while result.state == "pending" do result = Witness.Pump(handle) end
    if result.state ~= "complete" then return nil, result.reason end
    return handle.witness
end

local function CaptureToken(db, selectedBundle, sourceWitness, future,
                            includeCandidateEvidence)
    local bundle = selectedBundle or rawget(db, "authorityBundle")
    local source = type(bundle) == "table" and bundle or db
    local witness = sourceWitness
    if witness == nil then witness = Witness.Capture(source)
    elseif witness == false then witness = nil end
    local evidenceOwner = Nexus and Nexus.LoadoutEvidence
    local evidenceToken = evidenceOwner
        and type(evidenceOwner.AuthorityTokenV1) == "function"
        and evidenceOwner.AuthorityTokenV1(includeCandidateEvidence) or {}
    return {
        databaseIdentity=db, bundleIdentity=bundle,
        overlayIdentity=rawget(source, "communityBuilds"),
        tombstoneIdentity=rawget(source, "syncTombstones"),
        metadataIdentity=rawget(source, "buildCatalog"),
        evictionIdentity=rawget(source, "communityRetentionEvictions"),
        sourceWitness=witness,
        bundledIdentity=ST.bundled,
        baselineIdentity=Witness.BaselineMap(),
        ownerIdentity=CurrentOwnerKey(),
        bindingGeneration=ST.bindingGeneration,
        committedMutationRevision=future
            and future.committedMutationRevision
            or ST.committedMutationRevision,
        preparationEpoch=future and future.preparationEpoch
            or ST.preparationEpoch,
        reservationEpoch=ST.reservationEpoch,
        callbackOwnerIdentity=Nexus and Nexus.Revisions or nil,
        evidenceOwnerIdentity=evidenceOwner,
        evidenceAuthorityIdentity=evidenceToken.ownerIdentity,
        evidenceAppendRevision=evidenceToken.appendRevision,
        evidenceRemovalRevision=evidenceToken.removalRevision,
        evidenceProviderRevision=evidenceToken.providerRevision,
    }
end

local function TokenDrifted(token)
    local db = token.databaseIdentity
    if type(db) ~= "table" then return "SOURCE_DRIFT" end
    local bundle = rawget(db, "authorityBundle")
    if bundle ~= token.bundleIdentity then return "SOURCE_DRIFT" end
    local source = type(bundle) == "table" and bundle or db
    if rawget(source, "communityBuilds") ~= token.overlayIdentity
        or rawget(source, "syncTombstones") ~= token.tombstoneIdentity
        or rawget(source, "buildCatalog") ~= token.metadataIdentity
        or rawget(source, "communityRetentionEvictions") ~= token.evictionIdentity
        or (Nexus and Nexus.Revisions) ~= token.callbackOwnerIdentity then
        return "SOURCE_DRIFT"
    end
    local evidenceOwner = Nexus and Nexus.LoadoutEvidence
    if evidenceOwner ~= token.evidenceOwnerIdentity then return "SOURCE_DRIFT" end
    local evidenceToken = evidenceOwner
        and type(evidenceOwner.AuthorityTokenV1) == "function"
        and evidenceOwner.AuthorityTokenV1() or {}
    if evidenceToken.ownerIdentity ~= token.evidenceAuthorityIdentity
        or evidenceToken.appendRevision ~= token.evidenceAppendRevision
        or evidenceToken.removalRevision ~= token.evidenceRemovalRevision
        or evidenceToken.providerRevision ~= token.evidenceProviderRevision then
        return "SOURCE_DRIFT"
    end
    if token.bundledIdentity ~= ST.bundled then return "SOURCE_DRIFT" end
    if Witness.BaselineMap() ~= token.baselineIdentity then
        return "SOURCE_DRIFT"
    end
    if ST.bindingGeneration ~= token.bindingGeneration then return "SOURCE_DRIFT" end
    return nil
end

local function Invalidate(reason)
    local abandoned = ST.candidate
    ST.candidate = nil
    if ST.rootState ~= "ROOT_INVALIDATED" then
        ST.debugStats.driftInvalidations = ST.debugStats.driftInvalidations + 1
    end
    ST.rootState, ST.rootReason = "ROOT_INVALIDATED", reason
    PublishInvalidServing()
    ST.activeClaim = nil
    ST.activeCursors = {}
    ST.activeMaintenance = nil
    ST.sourceVerification = nil
    if abandoned and abandoned.mode == "mutation" then
        EvidenceCancelCandidate()
        SettleMutationTicket(abandoned, "failed", false, reason)
    end
end

-- Diagnostic exact-source comparison. Ordinary authority APIs use only the
-- detached published root plus fixed token identities. They never start or
-- drain this multi-pump task. The scheduler alone advances this frontier.
function Catalog.PumpSourceVerificationV1(limits)
    if ST.exhausted then
        return {state="failed", reason="GENERATION_EXHAUSTED"}
    end
    local root = ServingCatalogRoot()
    if ST.rootState ~= "ROOT_ADMITTED" or not root then
        ST.sourceVerification = nil
        return {state="failed", reason=ST.rootReason or ST.rootState}
    end
    local token = root.token
    local drift = TokenDrifted(token)
    if drift then
        Invalidate(drift)
        return {state="invalidated", reason=drift}
    end
    local source = type(token.bundleIdentity) == "table"
        and token.bundleIdentity or token.databaseIdentity
    local handle = ST.sourceVerification
    if not handle or handle.token ~= token then
        handle = Witness.BeginVerify(token.sourceWitness, source)
        handle.token = token
        ST.sourceVerification = handle
    end
    local result = Witness.Pump(handle, limits)
    if result.state == "failed" then
        ST.sourceVerification = nil
        Invalidate(result.reason == "SOURCE_WITNESS_MISSING"
            and result.reason or "SOURCE_DRIFT")
        return {state="invalidated", reason=ST.rootReason,
            edges=result.edges or 0, nodes=result.nodes or 0,
            bytes=result.bytes or 0}
    end
    if result.state == "complete" then
        ST.sourceVerification = nil
        local finalDrift = TokenDrifted(token)
        if finalDrift then
            Invalidate(finalDrift)
            return {state="invalidated", reason=finalDrift}
        end
        return {state="current", edges=result.edges or 0,
            nodes=result.nodes or 0, bytes=result.bytes or 0}
    end
    return result
end

-- Every authority API first proves the published root is still bound to the
-- exact raw identities it was admitted from. The outer generation-exhaustion
-- latch has precedence over every root/domain/API state: when it is latched no
-- inner state transition runs and the fixed bounded result is returned.
-- MASTER-RC-009. This is the READ gate and it performs no admission of any
-- kind. When the raw global no longer matches the bound authority database,
-- or the local-owner proof has drifted, it records exactly one explicit
-- rebind request and returns a fixed read-only result: bytes, generation and
-- state are all preserved. Architecture 3b5de54f,
-- docs/SYNC_TRUST_CATALOG_AUTHORITY_STATE_MACHINE.md lines 1200-1206 -- every
-- dependent owner "register[s] one idempotent dependency with this
-- coordinator; they do not call a domain recovery pump or raw writer
-- directly". Only Catalog.PumpAuthorityRebindV1 binds or admits.
local function Gate()
    if ST.exhausted then return nil, "GENERATION_EXHAUSTED" end
    if type(NexusDB) == "table" and NexusDB ~= ST.db and ST.candidate == nil then
        ST.rebindRequired = "SOURCE_REBIND_REQUIRED"
        return nil, "ROOT_REBIND_REQUIRED"
    end
    local published = ServingCatalogRoot()
    if ST.rootState == "ROOT_ADMITTED" then
        local drift = published and TokenDrifted(published.token)
        if drift then Invalidate(drift); published = nil end
    end
    -- MASTER-RC-009, closing element. The local-owner proof is an admission
    -- input, so when the character identity becomes available or changes every
    -- selection and provenance verdict must be re-proved by a complete
    -- re-admission. That re-admission is admission work, and architecture
    -- lines 1200-1206 forbid a dependent owner from driving it directly: a
    -- READ must never bind, admit, or advance durable state. This branch
    -- previously called Catalog.Init here, so a read re-admitted and could
    -- advance a generation. It now records one explicit rebind request and
    -- returns a fixed read-only refusal; only Catalog.PumpAuthorityRebindV1,
    -- driven by the MainLifecycle scheduler turn or by MutationGate, performs
    -- the re-admission.
    if ST.rootState == "ROOT_ADMITTED" and published and ST.candidate == nil
        and published.token.ownerIdentity ~= CurrentOwnerKey() then
        ST.rebindRequired = ST.rebindRequired or "OWNER_REBIND_REQUIRED"
        return nil, "ROOT_REBIND_REQUIRED"
    end
    if ST.rootState == "ROOT_ADMITTED" then return published end
    return nil, ST.candidate and "ROOT_ADMISSION_PENDING" or ST.rootState
end

-- The one explicit coordinator rebind. AuthorityBootstrapCoordinatorV1 and
-- the mutation gate drive it; nothing else binds or admits.
function Catalog.RebindRequired() return ST.rebindRequired end

-- MASTER-RC-001. A dependent REGISTERS an idempotent rebind dependency here
-- instead of driving admission itself. Architecture lines 1207-1211: every
-- dependent initializer "register[s] one idempotent dependency with this
-- coordinator; they do not call a domain recovery pump or raw writer
-- directly." This records a request and binds, admits, allocates and mutates
-- nothing; only Catalog.PumpAuthorityRebindV1 -- driven by the startup
-- coordinator, the MainLifecycle scheduler turn, or MutationGate -- performs
-- the admission. Repeated calls collapse to the one pending request.
function Catalog.RequestAuthorityRebindV1(reason)
    if reason ~= "OWNER_REBIND_REQUIRED" then
        reason = "SOURCE_REBIND_REQUIRED"
    end
    ST.rebindRequired = ST.rebindRequired or reason
    return ST.rebindRequired
end

-- requestedReason lets the startup coordinator re-prove admission when it has
-- just made an admission input available (the current-character owner proof),
-- without a read having recorded the request first. Only the coordinator and
-- MutationGate reach this; a read still never binds or admits.
-- MASTER-RC-001. The database the next Catalog.PumpAuthorityRebindV1 would
-- bind. A pure read that binds, admits and mutates nothing. It exists so the
-- startup coordinator and the MainLifecycle rebind pump can admit the evidence
-- pool against the SAME database before the catalog -- preserving the
-- evidence-before-catalog order that Catalog.Init used to enforce internally
-- by driving LoadoutEvidence directly -- without either driver duplicating
-- source selection.
function Catalog.PendingRebindDatabaseV1()
    local reason = ST.rebindRequired
    if not reason then return nil end
    if reason == "OWNER_REBIND_REQUIRED" then return ST.db end
    return type(NexusDB) == "table" and NexusDB or ST.db
end

function Catalog.PumpAuthorityRebindV1(database, bundle, requestedReason)
    local reason = ST.rebindRequired or requestedReason
    if not reason then return {rebound=false} end
    ST.rebindRequired = nil
    local nextDb, nextBundle
    if reason == "OWNER_REBIND_REQUIRED" then
        nextDb, nextBundle = ST.db, ST.bundled
    else
        nextDb = type(NexusDB) == "table" and NexusDB or ST.db
        nextBundle = type(Nexus.BundledBuilds) == "table"
            and Nexus.BundledBuilds or ST.bundled
    end
    if type(database) == "table" then nextDb = database end
    if type(bundle) == "table" then nextBundle = bundle end
    local summary = Catalog.Init(nextDb, nextBundle)
    -- MASTER-RC-006: Init advances exactly one slice. Preserve the one pending
    -- request until a later coordinator turn reaches a terminal result.
    if type(summary) == "table" and summary.state == "pending" then
        ST.rebindRequired = ST.rebindRequired or reason
    end
    return {rebound=true, reason=reason, summary=summary,
        exhausted=ST.exhausted == true}
end

-- A mutation may require the coordinator rebind before it runs. A read may
-- never trigger one.
local function MutationGate(maintenanceHandle)
    -- A long-lived maintenance walk is optimistic. A direct product mutation
    -- takes precedence, cancels the detached maintenance candidate, and lets
    -- that owner restart from the next published root.
    if ST.activeMaintenance
        and ST.activeMaintenance ~= maintenanceHandle then
        local displaced = ST.activeMaintenance
        displaced.state = "cancelled"
        ST.maintenanceRegistry[displaced] = nil
        ST.activeMaintenance = nil
        EvidenceCancelCandidate()
    end
    if ST.rebindRequired then Catalog.PumpAuthorityRebindV1() end
    if ST.candidate then return nil, ST.candidate.mode == "mutation"
        and "ROOT_MUTATION_PENDING" or "ROOT_ADMISSION_PENDING" end
    return Gate()
end

------------------------------------------------------------------------
-- Root admission handle
------------------------------------------------------------------------

-- `meta` is the selected raw metadata value: the bundle's `buildCatalog` field
-- after occupancy, the legacy location only while the bundle is absent.
local function ClassifyMetadata(meta)
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
    local binding, why = Generation.Advance(ST, "bindingGeneration")
    if not binding then return nil, why end
    local handle = {
        mode="admission", phase="capture", counters=NewCounters(),
        slots={}, slotVector={}, slotCount=0, mapIndex=1, mapCursor=nil,
        rootMapEdges=0, verdicts={}, index=NewIndex(),
        rowIndex=0, indexIndex=0, counts=nil, mapCounts={},
        pumps=0, failure=nil, token=CaptureToken(db, nil, false),
    }
    ST.counters = handle.counters
    return handle
end
Candidate.ClassifyMetadata = ClassifyMetadata
Candidate.PlainMapOrNil = PlainMapOrNil

local MAP_ORDER = {"overlay", "bundled", "tombstone", "barrier"}

local function AdmissionFail(handle, reason)
    handle.phase, handle.failure = "failed", reason
    return "failed"
end

-- Session-only record of the last collection refusal: which map, which
-- counter (keys in one map, or distinct keys across maps), the count at the
-- moment of refusal (limit + 1; later keys are not counted), the limit, the
-- phase and whether the saved bundle or the legacy table was the active
-- source. Scalars only; no keys, names or record contents. Never saved.
function Candidate.NoteLimit(handle, map, counter, count, limit, reason)
    local counts = {}
    for _, name in ipairs(MAP_ORDER) do
        counts[name] = tonumber(handle.mapCounts and handle.mapCounts[name]) or 0
    end
    ST.lastLimit = {reason=reason, map=map, counter=counter, count=count,
        limit=limit, phase="collect", mode=handle.mode,
        source=handle.sourceKind or (handle.mode == "mutation" and "bundle") or "unknown",
        overlay=counts.overlay, bundled=counts.bundled,
        tombstone=counts.tombstone, barrier=counts.barrier}
end

-- Read-only copy of that record, or nil. Touches no root, cursor or gate.
function Catalog.LastLimitSummary()
    local last = ST.lastLimit
    if type(last) ~= "table" then return nil end
    local copy = {}
    for key, value in pairs(last) do copy[key] = value end
    return copy
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
            -- The combined key budget of all four maps, charged per key read.
            -- Each map has its own 2048-key limit and all four share one
            -- 2048 distinct-key budget, so this total (8192) is a defensive
            -- stop that those checks normally reach first. It is the same
            -- kind of saved-capacity verdict, so it records the same facts.
            Candidate.NoteLimit(handle, name, "root-map-edges", handle.rootMapEdges,
                BUDGET.rootMapEdges, "ROOT_MAP_LIMIT")
            return AdmissionFail(handle, "ROOT_MAP_LIMIT")
        end
        local typedKey, kind = TypedKey(key)
        if not typedKey then return AdmissionFail(handle, "ROOT_MAP_KEY_INVALID") end
        Charge(work, "bytesInspected", #typedKey)
        handle.mapCounts[name] = (handle.mapCounts[name] or 0) + 1
        local limitReason = name == "tombstone" and "TOMBSTONE_SET_LIMIT"
            or name == "barrier" and "BARRIER_SET_LIMIT" or "ROOT_SLOT_LIMIT"
        if handle.mapCounts[name] > BUDGET.rootMapKeys then
            Candidate.NoteLimit(handle, name, "map-keys", handle.mapCounts[name],
                BUDGET.rootMapKeys, limitReason)
            return AdmissionFail(handle, limitReason)
        end
        local slot = handle.slots[typedKey]
        if not slot then
            slot = {key=typedKey, id=key, kind=kind}
            handle.slots[typedKey] = slot
            handle.slotCount = handle.slotCount + 1
            if handle.slotCount > BUDGET.rows then
                Candidate.NoteLimit(handle, name, "distinct-slots", handle.slotCount,
                    BUDGET.rows, limitReason)
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
        slot.admissionOptions = handle.mode == "mutation"
            and {candidateEvidence=true} or {}
        slot.walker = NewWalker(raw, slot.admissionOptions)
        Charge(work, "rows", 1)
    end
    local status = WalkRow(slot.walker, work)
    if status == "pending" then return nil end
    return FinishRowVerdict(slot.walker, slot, slot.selectedSource,
        slot.admissionOptions or {})
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
        local mutationState = handle.mutationStates
            and handle.mutationStates[slot.key] or nil
        if verdict.snapshot and mutationState == "READMITTED" then
            verdict.state = mutationState
        end
        handle.verdicts[slot.key] = verdict
        handle.rowIndex = handle.rowIndex + 1
    end
    return "ok"
end

-- Admission owns a fresh private index. Retain both the row phase and the
-- current membership charge so a rich row or a long key cannot drain a slice.
function Candidate.IndexCharge(state, work, bytes, nodes, edges)
    state.bytesRemaining = state.bytesRemaining or bytes
    local take = math.min(state.bytesRemaining,
        SLICE.indexBytes - work.budget.indexBytes)
    if take > 0 then
        Charge(work, "indexBytes", take)
        state.bytesRemaining = state.bytesRemaining - take
    end
    if state.bytesRemaining > 0
        or work.budget.indexNodes + nodes > SLICE.indexNodes
        or work.budget.indexEdges + edges > SLICE.indexEdges then return false end
    Charge(work, "indexNodes", nodes)
    Charge(work, "indexEdges", edges)
    state.bytesRemaining = nil
    return true
end

function Candidate.PumpIndexRow(handle, verdict, work)
    local index, key, snapshot = handle.index, verdict.typedKey, verdict.snapshot
    local state = handle.indexRow
    if not state then
        state = {phase="exact", membership={}, spellPosition=1}
        handle.indexRow = state
    end
    local membership = state.membership
    while not Exhausted(work.budget) do
        local phase = state.phase
        local map, bucketKey, nextPhase
        if phase == "exact" then
            bucketKey = verdict.savedKind == "ordinary" and verdict.complete
                and verdict.exactFingerprint or nil
            map, nextPhase = index.exact, "owner"
        elseif phase == "owner" then
            local ownerKey = verdict.savedKind == "ordinary" and verdict.verifiedOwner
            local class = ownerKey and NormalizedClass(snapshot.class)
            if class then
                local owner = index.ownerClasses[ownerKey]
                if not Candidate.IndexCharge(state, work, #ownerKey + 18,
                    owner and 0 or 1, 1) then return false end
                if not owner then
                    owner = {ids={}, classes={}, count=0}
                    index.owned[owner], index.ownerClasses[ownerKey] = true, owner
                end
                owner.ids[key] = class
                owner.classes[class] = (owner.classes[class] or 0) + 1
                owner.count = owner.count + 1
                membership.classOwner = ownerKey
            end
            state.phase = "author"
        elseif phase == "author" then
            local authorKey = AuthorKey(snapshot.author)
            if authorKey then
                local author = index.authors[authorKey]
                if not Candidate.IndexCharge(state, work, #authorKey + 18,
                    author and 0 or 1, 1) then return false end
                if not author then
                    author = {}
                    index.owned[author], index.authors[authorKey] = true, author
                end
                author[key], membership.author = true, authorKey
            end
            state.author = RelatedText(snapshot.author)
            state.phase = state.author == "" and "done"
                or (verdict.savedKind == "saved" and "saved" or "spell")
            if state.phase == "spell" then membership.spells = {} end
        elseif phase == "spell" then
            if not state.spellKey then
                local fingerprint = verdict.relatedFingerprint or ""
                local _, finish, rawId, rawCount = fingerprint:find(
                    "(%d+)x(%d+)", state.spellPosition)
                if finish then
                    state.spellPosition = finish + 1
                    if tonumber(rawCount) > 0 then
                        state.spellKey = RelatedKey(state.author, tostring(tonumber(rawId)))
                    end
                else state.phase = "fingerprint" end
            end
            bucketKey, map, nextPhase = state.spellKey, index.spells, state.phase
        elseif phase == "fingerprint" then
            bucketKey = RelatedKey(state.author, verdict.relatedFingerprint)
            map, nextPhase = index.fingerprints, "title"
        elseif phase == "title" then
            bucketKey = RelatedKey(state.author,
                RelatedText(snapshot.title or snapshot.serverTitle))
            map, nextPhase = index.titles, "done"
        elseif phase == "saved" then
            bucketKey = RelatedKey(state.author, "saved")
            map, nextPhase = index.saved, "done"
        else
            if not Candidate.IndexCharge(state, work, 0, 1, 0) then return false end
            index.memberships[key] = membership
            handle.indexRow = nil
            return true
        end
        if map then
            if bucketKey then
                local bucket = map[bucketKey]
                local added = not bucket or not bucket.ids[key]
                if not Candidate.IndexCharge(state, work,
                    added and (#bucketKey + 18) or 0, bucket and 0 or 1,
                    added and 1 or 0) then return false end
                bucket = AddBucket(index, map, bucketKey, key, work, handle.verdicts, true)
                if phase == "exact" then
                    membership.exact, membership.exactAuto = bucketKey, snapshot.autoDps == true
                    local field = membership.exactAuto and "autoCount" or "explicitCount"
                    bucket[field] = (bucket[field] or 0) + 1
                    if BetterExactCandidate(verdict.id, verdict, bucket.winnerId,
                        bucket.winnerKey and handle.verdicts[bucket.winnerKey]) then
                        bucket.winnerKey, bucket.winnerId = key, verdict.id
                    end
                elseif phase == "spell" then
                    membership.spells[#membership.spells + 1] = bucketKey
                    state.spellKey = nil
                else membership[phase] = bucketKey end
            end
            state.phase = nextPhase
        end
    end
    return false
end

local function BuildIndexes(handle, work)
    while handle.indexIndex < handle.slotCount do
        if Exhausted(work.budget) then return "pending" end
        local slot = handle.slotVector[handle.indexIndex + 1]
        local verdict = handle.verdicts[slot.key]
        if verdict and verdict.snapshot then
            if not Candidate.PumpIndexRow(handle, verdict, work) then return "pending" end
        else
            Charge(work, "indexNodes", 1)
        end
        handle.indexIndex = handle.indexIndex + 1
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
    local overlayKeys, tombstoneKeys, barrierKeys = {}, {}, {}
    for _, slot in ipairs(handle.slotVector) do
        local verdict = handle.verdicts[slot.key]
        if verdict.source == "overlay" and verdict.snapshot then
            overlayKeys[#overlayKeys + 1] = slot.key
        end
        if verdict.tombstone then tombstoneKeys[#tombstoneKeys + 1] = slot.key end
        if verdict.barrier then barrierKeys[#barrierKeys + 1] = slot.key end
    end
    return overlayKeys, tombstoneKeys, barrierKeys
end

-- Known-field baseline equivalence: an overlay that duplicates its bundled
-- row may be pruned only when it owns no unknown evidence.
local function BaselineVerdictEquivalent(snapshot, hasUnknown, overlayRaw,
                                          bundledVerdict)
    if not (snapshot and bundledVerdict and bundledVerdict.snapshot)
        or hasUnknown or RawLocalMarker(overlayRaw) then
        return false
    end
    local left, right = DeepCopy(snapshot), DeepCopy(bundledVerdict.snapshot)
    for _, key in ipairs({"isMine", "ownerVerified", "needsFullBuild", "linkHash",
        "fingerprintHash", "ordinaryCompletenessReason", "claimedOwnerKey",
        "relaySender"}) do
        left[key], right[key] = nil, nil
    end
    return DeepEqual(left, right)
end

-- Notifications run only after the new root is public. A failing subscriber,
-- scheduler, or logger cannot undo or replay the committed mutation; it is
-- recorded as one bounded NOTIFICATION_FAILED receipt.
--
-- MASTER-RC-015, class 5 terminal 3. Architecture 2618-2630: "The owner records
-- one bounded NOTIFICATION_FAILED receipt and schedules notification-only replay
-- bound to the exact new root generation. Replay never reruns raw writes or the
-- authority transaction and becomes stale if a newer root publishes." Governing
-- with 650, 2391-2394 ("BuildCatalog owns one transaction"), and 4743. Line 628
-- states the same invariant generically for DPS, evidence, recovery, registry,
-- and provider publication and is corroborative only.
--
-- Line 1598 is NOT this seam. It is one row of core/Store.lua's own exhaustive
-- table (1538-1540) for the separate StoreMutationTokenV1 post-ready pipeline,
-- reachable only from STORE_READY for RegisterCurrentCharacter, Retention, and
-- Compaction. That pipeline is unimplemented and is MASTER-RC-001's, not this
-- root's; nothing here may publish a result field on its behalf.
--
-- The mechanism is deliberately the smallest one that satisfies the governing
-- clauses: exactly ONE private pending item, dispatched by the existing shared
-- Nexus.Scheduler on a later ordinary turn. No new pump, no new export, no new
-- module dependency, and NO new public field -- the replay is observable as the
-- delayed Nexus.Revisions.Advance effect itself, plus the normative catalog
-- diagnostics DebugStats already owns (architecture line 1721).
local ReplayPendingNotification

local function NotifyBuild(reason, id, scope)
    scope = scope or (id ~= nil and "record" or "all")
    local ok = pcall(function()
        local revisions = Nexus and Nexus.Revisions
        if revisions and type(revisions.Advance) == "function" then
            revisions.Advance(revisions.BUILD_LIBRARY_CHANGED, {
                reason=reason, scope=scope, id=id,
            })
        end
    end)
    if ok then return true end
    ST.debugStats.notificationFailures = ST.debugStats.notificationFailures + 1
    -- One bounded pending item, bound to the exact published serving root's
    -- identity AND its generation. A second failure supersedes the first: once a
    -- newer root has published, the earlier item is stale by construction, so
    -- retaining it could only produce a discard.
    ST.pendingNotification = {
        reason=reason, id=id, scope=scope,
        serving=ST.currentServingRoot,
        servingGeneration=ST.servingGeneration,
    }
    local scheduler = Nexus and Nexus.Scheduler
    if scheduler and type(scheduler.After) == "function" then
        -- Keyed, so at most one replay task exists at any time in any session.
        pcall(scheduler.After, "build-catalog-notification-replay", 0,
            ReplayPendingNotification)
    end
    return false
end

-- Dispatched by the scheduler on a later ordinary turn, never from a read and
-- never from the commit that queued it. It touches no raw write, no authority
-- transaction, no serving swap, and no revision or generation counter on either
-- the delivered or the discarded path: it is notification only.
function ReplayPendingNotification()
    -- A reload replaces this module while the scheduler may still hold the
    -- previous session's closure. That closure owns a dead ST whose bound
    -- generation would still compare equal to itself, so it must never deliver.
    if Nexus.BuildCatalog ~= Catalog then return end
    local pending = ST.pendingNotification
    if not pending then return end
    -- Bounded: this one dispatch consumes the item on both paths. A replay that
    -- fails again is recorded as a further NOTIFICATION_FAILED receipt and is
    -- not requeued, so no unbounded retry loop can exist.
    ST.pendingNotification = nil
    if pending.serving ~= ST.currentServingRoot
        or pending.servingGeneration ~= ST.servingGeneration then
        ST.debugStats.notificationReplaysStale =
            ST.debugStats.notificationReplaysStale + 1
        return
    end
    local ok = pcall(function()
        local revisions = Nexus and Nexus.Revisions
        if revisions and type(revisions.Advance) == "function" then
            revisions.Advance(revisions.BUILD_LIBRARY_CHANGED, {
                reason=pending.reason, scope=pending.scope, id=pending.id,
            })
        end
    end)
    if ok then
        ST.debugStats.notificationReplays = ST.debugStats.notificationReplays + 1
    else
        ST.debugStats.notificationFailures = ST.debugStats.notificationFailures + 1
    end
end

local function PublishRoot(handle)
    local db = handle.token.databaseIdentity
    local drift = TokenDrifted(handle.token)
    if drift then return AdmissionFail(handle, drift) end
    local publishPlan = handle.publishPlan
    if type(publishPlan) ~= "table" then
        publishPlan = handle.mode == "mutation"
            and Generation.MutationPlan(handle.items) or {
                {owner=ST, key="preparationEpoch", amount=1},
                {owner=ST, key="generation", amount=1},
                {owner=ST, key="semanticGeneration", amount=1},
                {owner=ST, key="servingGeneration", amount=1},
            }
    end
    local countersOk, countersWhy = Generation.Preflight(publishPlan)
    if not countersOk then return AdmissionFail(handle, countersWhy) end

    local itemCount = handle.mode == "mutation"
        and math.max(1, #handle.items) or 1
    local future = {
        generation=ST.generation + itemCount,
        preparationEpoch=ST.preparationEpoch + 1,
        committedMutationRevision=ST.committedMutationRevision
            + (handle.mode == "mutation" and itemCount or 0),
    }
    if handle.mode == "mutation" then
        for _, item in ipairs(handle.items) do
            item.previous = handle.originalRoot.rows[item.slot.key]
        end
    end
    handle.token = CaptureToken(db, handle.finalBundle,
        handle.sourceWitness, future, handle.mode == "mutation")
    local catalogRoot = {
        generation=future.generation, token=handle.token, rows=handle.verdicts,
        slots=handle.slots, slotVector=handle.slotVector, slotCount=handle.slotCount,
        index=handle.index, counts=handle.counts, overlayKeys=handle.overlayKeys,
        tombstoneKeys=handle.tombstoneKeys, barrierKeys=handle.barrierKeys,
        catalogVersion=handle.catalogVersion,
        schemaVersion=handle.metaVersion or STORAGE_SCHEMA_VERSION,
        migrated=handle.needsMigration, redundantRemoved=#handle.prune,
    }
    local durableGeneration = tonumber(handle.finalBundle.transactionGeneration)
        or ST.durableBundleGeneration
    local sealedServing = NewServingRoot(catalogRoot, durableGeneration)
    -- The bootstrap seal withholds only the startup ADMISSION root until the
    -- coordinator's serving-publication state. A mutation always replaces an
    -- already published root and must keep its durable bundle and serving
    -- root adjacent: sealing it would commit the bundle while the public root
    -- still bound the previous bundle identity, which is exact source drift.
    local sealed = ST.bootstrapSeal == true and handle.mode ~= "mutation"
    if not sealed then
        sealedServing.generation = ST.servingGeneration + 1
    end

    -- Protected section: all allocation, copying, witness work, counter work,
    -- and callback work is complete. The durable and serving assignments are
    -- adjacent. Nothing between them can inspect or publish a partial graph.
    local ok = pcall(function()
        if handle.bundleWrite and not CommitDurableBundle(db, handle.finalBundle) then
            error("AUTHORITY_BUNDLE_VERIFICATION_FAILED", 0)
        end
        if sealed then
            ST.sealedServing = sealedServing
        else
            local swapped, swapWhy = AuthorityServingRootWriterV1(
                "final-swap", sealedServing)
            if not swapped then error(swapWhy or "SERVING_SWAP_FAILED", 0) end
        end
    end)
    if not ok then
        ST.debugStats.protectedFailures = ST.debugStats.protectedFailures + 1
        return AdmissionFail(handle, "PROTECTED_COMMIT_FAILED")
    end
    Generation.ApplyPlan(publishPlan, sealed)
    ST.durableBundle = handle.finalBundle
    ST.durableBundleGeneration = durableGeneration
    if handle.mode == "mutation" then
        ST.sessionTombstones = handle.sessionTombstones
        ST.sessionBarriers = handle.sessionBarriers
    end
    if handle.bundleWrite then
        ST.debugStats.bundleWrites = ST.debugStats.bundleWrites + 1
    end
    if not sealed then
        ST.debugStats.servingSwaps = ST.debugStats.servingSwaps + 1
    end

    -- Evidence publication only releases the already durable candidate. It is
    -- deliberately outside the adjacent publication pair. A faulty release
    -- cannot turn the complete transaction into a reported failure.
    local evidenceReleased = pcall(EvidencePublishCandidate)
    if not evidenceReleased then EvidenceCancelCandidate() end
    if handle.mode == "mutation" then
        local clock = ST.exactRevisionClock - #handle.items
        for index, item in ipairs(handle.items) do
            local verdict = handle.verdicts[item.slot.key]
            local before = item.previous and item.previous.snapshot
                and item.previous.exactFingerprint or nil
            local after = verdict and verdict.snapshot
                and verdict.exactFingerprint or nil
            local revision = clock + index
            if before then ST.exactRevisions[before] = revision end
            if after then ST.exactRevisions[after] = revision end
        end
        ST.debugStats.relatedIndexUpdates = ST.debugStats.relatedIndexUpdates
            + #handle.items
        ST.debugStats.commits = ST.debugStats.commits + itemCount
    end
    if sealed then
        -- PublishSealedServingV1 assigns the serving generation when the startup
        -- coordinator reaches the final all-domain publication state.
        sealedServing.generation = 0
    end
    ST.rootState, ST.rootReason = "ROOT_ADMITTED", nil
    ST.activeCursors = {}
    ReleaseSupersededCursors()
    -- Mutation candidates are resumed through the same bounded constructor as
    -- admission, but they remain one logical incremental index update per item.
    -- Keep rebuild telemetry for explicit root admission; BumpRevisions owns
    -- mutation update accounting.
    if handle.mode ~= "mutation" then
        ST.debugStats.relatedIndexRebuilds = ST.debugStats.relatedIndexRebuilds + 1
        ST.debugStats.authorIndexRebuilds = ST.debugStats.authorIndexRebuilds + 1
    end
    if handle.mode == "mutation" and handle.claim then
        local released, releaseWhy = Candidate.ReleaseClaim(handle.claim, true)
        if not released then return AdmissionFail(handle, releaseWhy) end
    end
    if handle.mode == "mutation" and handle.claims then
        for _, claim in ipairs(handle.claims) do
            local released, releaseWhy = Candidate.ReleaseClaim(claim, true)
            if not released then return AdmissionFail(handle, releaseWhy) end
        end
        handle.claims = {}
    end
    if handle.completion == "put" then
        ST.debugStats.putChanges = ST.debugStats.putChanges + 1
    elseif handle.completion == "maintenance" then
        ST.debugStats.maintenanceCommits = ST.debugStats.maintenanceCommits + 1
    end
    handle.phase = "published"
    return "published"
end

local function PumpAdmission(handle)
    local work = NewWork(handle.counters)
    handle.pumps = handle.pumps + 1
    ST.debugStats.rootPumps = ST.debugStats.rootPumps + 1
    local result
    if handle.phase == "maintenance-prepare" then
        local prepared, prepareWhy = Candidate.PumpMaintenancePreparation(
            handle, work)
        if prepared == "failed" then
            result = AdmissionFail(handle, prepareWhy)
        elseif prepared == "pending" then
            result = "pending"
        else
            result = "ok"
        end
    end
    if handle.phase == "batch-prepare" then
        local prepared, prepareWhy = Candidate.PumpBatchPutPreparation(handle,
            work)
        if prepared == "failed" then
            result = AdmissionFail(handle, prepareWhy)
        elseif prepared == "noop" then
            ClosePump(work)
            return "noop"
        elseif prepared == "pending" then
            result = "pending"
        else
            result = "ok"
        end
    end
    if handle.phase == "put-prepare" then
        local prepared, prepareWhy = Candidate.PumpPutPreparation(handle, work)
        if prepared == "failed" then
            result = AdmissionFail(handle, prepareWhy)
        elseif prepared == "noop" then
            ClosePump(work)
            return "noop"
        elseif prepared == "pending" then
            result = "pending"
        else
            result = "ok"
        end
    end
    if handle.phase == "mutation-bundle" and result ~= "pending"
        and not handle.sourceVerified then
        -- MASTER-RC-017 / MASTER-W2-011. A mutation rebuilds its root from
        -- the durable bundle's raw maps, so before it copies one raw row it
        -- proves the exact nested source graph still matches the witness the
        -- admitted root is bound to. Identity drift is caught by the token;
        -- a key written behind the published root is not, and without this
        -- bounded walk that raw write would be admitted as source by the
        -- next mutation instead of invalidating the root it drifted from.
        if not handle.sourceVerifyHandle then
            local token = handle.token
            local source = type(token.bundleIdentity) == "table"
                and token.bundleIdentity or token.databaseIdentity
            handle.sourceVerifyHandle = Witness.BeginVerify(
                token.sourceWitness, source)
        end
        local remaining = {edges=SLICE.edges - work.budget.edges,
            nodes=SLICE.nodes - work.budget.nodes,
            bytes=SLICE.bytesInspected - work.budget.bytesInspected}
        local verified = remaining.edges > 0 and remaining.nodes > 0
            and remaining.bytes > 0
            and Witness.Pump(handle.sourceVerifyHandle, remaining)
            or {state="pending", edges=0, nodes=0, bytes=0}
        if (verified.edges or 0) > 0 then
            Charge(work, "edges", verified.edges)
        end
        if (verified.nodes or 0) > 0 then
            Charge(work, "nodes", verified.nodes)
        end
        if (verified.bytes or 0) > 0 then
            Charge(work, "bytesInspected", verified.bytes)
        end
        if verified.state == "failed" then
            result = AdmissionFail(handle,
                verified.reason == "SOURCE_WITNESS_MISSING"
                    and verified.reason or "SOURCE_DRIFT")
        elseif verified.state == "complete" then
            -- The bundle copy continues inside this same slice so the pump
            -- that closes the walk still makes frontier progress.
            handle.sourceVerified, handle.sourceVerifyHandle = true, nil
            result = "ok"
        else
            result = "pending"
        end
    end
    if handle.phase == "mutation-bundle" and result ~= "pending" then
        local complete, why = Candidate.PumpBundle(handle.bundleBuilder, work)
        if complete == false then result = AdmissionFail(handle, why)
        elseif not complete then result = "pending"
        else
            handle.finalBundle = handle.bundleBuilder.bundle
            handle.phase, result = "mutation-session-tombstones", "ok"
        end
    end
    if handle.phase == "mutation-session-tombstones" and result ~= "pending" then
        local complete, why = Candidate.PumpCopy(handle.sessionCopy, work)
        if complete == false then result = AdmissionFail(handle, why)
        elseif not complete then result = "pending"
        else
            handle.sessionCopy = {source=ST.sessionBarriers,
                target=handle.sessionBarriers, cursor=nil}
            handle.phase, result = "mutation-session-barriers", "ok"
        end
    end
    if handle.phase == "mutation-session-barriers" and result ~= "pending" then
        local complete, why = Candidate.PumpCopy(handle.sessionCopy, work)
        if complete == false then result = AdmissionFail(handle, why)
        elseif not complete then result = "pending"
        else
            handle.sessionWriteItem, handle.sessionWriteIndex = 1, 1
            handle.phase, result = "mutation-session-writes", "ok"
        end
    end
    if handle.phase == "mutation-session-writes" and result ~= "pending" then
        while handle.sessionWriteItem <= #handle.items and not Exhausted(work.budget) do
            local item = handle.items[handle.sessionWriteItem]
            local write = item.writes[handle.sessionWriteIndex]
            if not write then
                local desired = item.verdict and item.verdict.state
                if desired == "READMITTED" then
                    handle.mutationStates[item.slot.key] = desired
                end
                handle.sessionWriteItem = handle.sessionWriteItem + 1
                handle.sessionWriteIndex = 1
            else
                if write.session == "sessionTombstones" then
                    handle.sessionTombstones[write.value] = true
                elseif write.session == "sessionBarriers" then
                    handle.sessionBarriers[write.value] = true
                end
                handle.sessionWriteIndex = handle.sessionWriteIndex + 1
                Charge(work, "edges", 1)
            end
        end
        if handle.sessionWriteItem <= #handle.items then result = "pending"
        else
            local configured, why = Candidate.ConfigureMutationAdmission(handle)
            if not configured then result = AdmissionFail(handle, why)
            else result = "ok" end
        end
    end
    if handle.phase == "capture" then
        local db = handle.token.databaseIdentity
        -- A selected database's nonnil raw authorityBundle is classified before
        -- any legacy location decides anything. It never falls back.
        local bundleClass, bundleReason, bundleRaw, bundleValue =
            ClassifyDurableBundle(db)
        handle.bundleClass = bundleClass
        handle.bundleRaw, handle.bundleGeneration = bundleRaw, bundleValue
        if bundleClass == "exhausted" then
            LatchGenerationExhausted()
            handle.phase, handle.failure = "failed", "GENERATION_EXHAUSTED"
            ClosePump(work)
            return "failed"
        end
        if bundleClass == "invalid" then
            ClosePump(work)
            return AdmissionFail(handle, bundleReason)
        end
        if bundleClass == "future" then
            handle.phase, handle.futureSchema = "future", bundleValue
            ClosePump(work)
            return "future"
        end
        -- Bundle-versus-legacy read precedence. Once any complete bundle is
        -- occupied it is the only admission input for the catalog domain; the
        -- exact PR #68 locations are "Never used as fallback after bundle
        -- occupancy" (state machine line 394) and are read only on the absent
        -- bundle's LEGACY_BUNDLE_MIGRATION_REQUIRED route (line 374).
        local source = bundleClass == "absent" and db or bundleRaw
        handle.source = source
        handle.sourceKind = bundleClass == "absent" and "legacy" or "bundle"
        local classification, reason, _, version =
            ClassifyMetadata(rawget(source, "buildCatalog"))
        if classification == "invalid" then
            result = AdmissionFail(handle, reason)
        elseif classification == "future" then
            handle.phase, handle.futureSchema = "future", version
            result = "future"
        else
            local okOverlay, overlay = PlainMapOrNil(rawget(source, "communityBuilds"))
            local okTomb, tombstones = PlainMapOrNil(rawget(source, "syncTombstones"))
            local okEvict, evictions = PlainMapOrNil(rawget(source, "communityRetentionEvictions"))
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
        if result == "ok" then
            local begun, why = Candidate.BeginAdmissionFinalization(handle)
            if not begun then result = AdmissionFail(handle, why)
            else result = "ok" end
        end
    end
    if handle.phase == "finalize-scan" and result ~= "pending" then
        if Candidate.PumpAdmissionFinalization(handle, work) then
            result = "ok"
        else
            result = "pending"
        end
    end
    if handle.phase == "finalize-prune" and result ~= "pending" then
        if Candidate.PumpAdmissionPrune(handle, work) then result = "ok"
        else result = "pending" end
    end
    if handle.phase == "index" and result ~= "pending" then
        result = BuildIndexes(handle, work)
        if result == "ok" then
            local begun, why = Candidate.BeginAdmissionBundle(handle)
            if not begun then result = AdmissionFail(handle, why)
            else result = "ok" end
        end
    end
    if handle.phase == "bundle" and result ~= "pending" then
        local complete, why = Candidate.PumpBundle(handle.bundleBuilder, work)
        if complete == false then result = AdmissionFail(handle, why)
        elseif not complete then result = "pending"
        else
            handle.finalBundle = handle.bundleBuilder.bundle
            handle.phase = "witness-capture"
            result = "ok"
        end
    end
    if handle.phase == "witness-capture" and result ~= "pending" then
        handle.witnessHandle = handle.witnessHandle
            or Witness.NewCapture(handle.finalBundle)
        local remaining = {edges=SLICE.edges - work.budget.edges,
            nodes=SLICE.nodes - work.budget.nodes,
            bytes=SLICE.bytesInspected - work.budget.bytesInspected}
        local witnessResult = remaining.edges > 0 and remaining.nodes > 0
            and remaining.bytes > 0
            and Witness.Pump(handle.witnessHandle, remaining)
            or {state="pending", edges=0, nodes=0, bytes=0}
        if (witnessResult.edges or 0) > 0 then
            Charge(work, "edges", witnessResult.edges)
        end
        if (witnessResult.nodes or 0) > 0 then
            Charge(work, "nodes", witnessResult.nodes)
        end
        if (witnessResult.bytes or 0) > 0 then
            Charge(work, "bytesInspected", witnessResult.bytes)
        end
        if witnessResult.state == "failed" then
            result = AdmissionFail(handle, witnessResult.reason)
        elseif witnessResult.state == "complete" then
            handle.sourceWitness = handle.witnessHandle.witness
            handle.witnessHandle = Witness.BeginVerify(
                handle.sourceWitness, handle.finalBundle)
            handle.phase, result = "witness-verify", "ok"
        else
            result = "pending"
        end
    end
    if handle.phase == "witness-verify" and result ~= "pending" then
        local remaining = {edges=SLICE.edges - work.budget.edges,
            nodes=SLICE.nodes - work.budget.nodes,
            bytes=SLICE.bytesInspected - work.budget.bytesInspected}
        local witnessResult = remaining.edges > 0 and remaining.nodes > 0
            and remaining.bytes > 0
            and Witness.Pump(handle.witnessHandle, remaining)
            or {state="pending", edges=0, nodes=0, bytes=0}
        if (witnessResult.edges or 0) > 0 then
            Charge(work, "edges", witnessResult.edges)
        end
        if (witnessResult.nodes or 0) > 0 then
            Charge(work, "nodes", witnessResult.nodes)
        end
        if (witnessResult.bytes or 0) > 0 then
            Charge(work, "bytesInspected", witnessResult.bytes)
        end
        if witnessResult.state == "failed" then
            result = AdmissionFail(handle, witnessResult.reason)
        elseif witnessResult.state == "complete" then
            handle.phase, result = "publish", "ok"
        else
            result = "pending"
        end
    end
    if handle.phase == "publish" and result ~= "pending" then
        -- FinishAdmission owns failure settlement after it detaches this handle,
        -- so a completion callback may safely begin a replacement candidate.
        local published, outcome = pcall(PublishRoot, handle)
        if published then
            result = outcome
        else
            ST.debugStats.protectedFailures = ST.debugStats.protectedFailures + 1
            result = AdmissionFail(handle, "ROOT_PUBLICATION_FAILED")
        end
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
    local published = ServingCatalogRoot()
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
    -- The generation-exhaustion latch discards the candidate, so there is no
    -- handle to finish: the fixed outer result is returned unchanged.
    if not handle then
        return {state=ST.rootState, reason=ST.rootReason, pumps=0}
    end
    if result == "pending" then
        if handle.mode == "mutation" and handle.ticket then
            handle.ticket.pumps = handle.pumps
            return handle.ticket
        end
        return {state="pending", pumps=handle.pumps}
    end
    ST.candidate = nil
    ST.lastCounters = handle.counters
    if result == "noop" and handle.mode == "mutation" then
        local ticket, callback = SettleMutationTicket(handle,
            "committed", true, nil, true)
        if callback and not pcall(callback, ticket) then
            ST.debugStats.mutationCompletionFailures =
                ST.debugStats.mutationCompletionFailures + 1
        end
        return ticket
    elseif result == "published" then
        if handle.mode == "mutation" then
            -- Close and bind this receipt before a subscriber can start another
            -- candidate. Notifications and owner callbacks may re-enter safely;
            -- none of the remaining completion work consumes ST.candidate.
            local ticket, callback = SettleMutationTicket(handle,
                "committed", true, nil, true)
            if not handle.deferred then
                pcall(NotifyBuild, handle.reason, handle.notifyScope == "all" and nil
                    or (handle.items[1] and handle.items[1].slot.id), handle.notifyScope)
            end
            if handle.completion == "maintenance" then
                pcall(NotifyBuild, handle.maintenanceOperation == "compaction"
                    and "exact evidence compaction" or "catalog maintenance", nil, "all")
            end
            if callback and not pcall(callback, ticket) then
                ST.debugStats.mutationCompletionFailures =
                    ST.debugStats.mutationCompletionFailures + 1
            end
            return ticket
        end
        ST.lastInitSummary = SummaryOf(handle, "ROOT_ADMITTED")
        NotifyBuild("catalog initialized")
        return {state="ROOT_ADMITTED", pumps=handle.pumps, generation=ST.generation}
    elseif result == "future" then
        ST.rootState, ST.rootReason = "ROOT_READ_ONLY_FUTURE_SCHEMA", "FUTURE_SCHEMA"
        PublishInvalidServing()
        ST.futureToken = handle.token
        ST.lastInitSummary = SummaryOf(handle, "ROOT_READ_ONLY_FUTURE_SCHEMA", "FUTURE_SCHEMA")
        return {state="ROOT_READ_ONLY_FUTURE_SCHEMA", reason="FUTURE_SCHEMA", pumps=handle.pumps}
    end
    if handle.mode == "mutation" then
        if handle.failure == "SOURCE_DRIFT"
            or handle.failure == "SOURCE_WITNESS_MISSING"
            or handle.failure == "PROTECTED_COMMIT_FAILED"
            or handle.failure == "ROOT_PUBLICATION_FAILED" then
            Invalidate(handle.failure)
        end
        EvidenceCancelCandidate()
        return SettleMutationTicket(handle, "failed", false,
            handle.failure or "ROOT_CONSTRUCTION_FAILED")
    end
    Invalidate(handle.failure or "ROOT_CONSTRUCTION_FAILED")
    ST.lastInitSummary = SummaryOf(handle, "ROOT_INVALIDATED", ST.rootReason)
    return {state="ROOT_INVALIDATED", reason=ST.rootReason, pumps=handle.pumps}
end

------------------------------------------------------------------------
-- Public: root binding
------------------------------------------------------------------------

function Catalog.BeginRootAdmission(database, bundle)
    local abandoned = ST.candidate
    local db = type(database) == "table" and database or {}
    local bundled = type(bundle) == "table" and bundle
        or type(Nexus.BundledBuilds) == "table" and Nexus.BundledBuilds or {}
    local baseline = type(bundled.builds) == "table" and bundled.builds or {}
    if ST.exhausted then
        return {state=ST.rootState, reason="GENERATION_EXHAUSTED", pumps=0}
    end
    local countersOk = Generation.Preflight({
        {owner=ST, key="bindingGeneration", amount=1},
        {owner=ST, key="servingGeneration", amount=1},
    })
    if not countersOk then
        return {state=ST.rootState, reason="GENERATION_EXHAUSTED", pumps=0}
    end
    ST.db, ST.bundled, ST.baseline = db, bundled, baseline
    PublishInvalidServing()
    ST.rootState, ST.rootReason = "ROOT_ADMISSION_PENDING", nil
    ST.activeClaim, ST.activeCursors, ST.activeMaintenance = nil, {}, nil
    -- A complete rebind discards every prior session cursor: no registry entry
    -- may outlive the root it was issued against.
    ST.cursorRegistry = setmetatable({}, {__mode="k"})
    ST.candidate = NewAdmission(db)
    ST.debugStats.rootAdmissions = ST.debugStats.rootAdmissions + 1
    if abandoned and abandoned.mode == "mutation" then
        EvidenceCancelCandidate()
        SettleMutationTicket(abandoned, "failed", false, "SUPERSEDED")
    end
    return {state="pending", pumps=0}
end

function Candidate.PreparationWork(handle)
    local totals = handle and handle.counters and handle.counters.totals
    local amount = 0
    for _, key in ipairs(COUNTER_KEYS) do amount = amount + (totals and totals[key] or 0) end
    return amount
end

-- Passive current-step counters. Only the three row walks that already hold
-- their own index against the fixed slot vector report a total; every other
-- phase returns nil, so no caller can present a guessed or counted size.
function Candidate.StepProgress(handle)
    if not handle then return nil end
    local total, done = handle.slotCount
    if handle.phase == "rows" then done = (handle.rowIndex or 1) - 1
    elseif handle.phase == "finalize-scan" then done = (handle.finalizeIndex or 1) - 1
    elseif handle.phase == "index" then done = handle.indexIndex
    else return nil end
    if type(total) ~= "number" or type(done) ~= "number" or total < 1
        or done < 0 or done > total then return nil end
    return done, total
end

-- Scalar, read-only dependency description. The separate empty identity has
-- no authority fields; editing it cannot change a candidate. Neither this
-- query nor identity comparison admits, invalidates or advances any root.
function Catalog.ManualPreparationStatus()
    local root, handle = ServingCatalogRoot(), ST.candidate
    local token = handle and handle.token or root and root.token
    local agrees = token ~= nil and token.databaseIdentity == ST.db
        and (type(NexusDB) ~= "table" or NexusDB == ST.db)
        and token.ownerIdentity == CurrentOwnerKey()
        and token.bindingGeneration == ST.bindingGeneration
        and TokenDrifted(token) == nil and not ST.rebindRequired and not ST.exhausted
    local relevant = agrees and ST.rootState == "ROOT_ADMITTED" and root ~= nil
        and handle ~= nil and handle.mode == "mutation"
        and handle.originalRoot == root and token == root.token
        and handle.preparationIdentity ~= nil
    local witness = handle and (handle.witnessHandle or handle.sourceVerifyHandle)
    local stepDone, stepTotal = Candidate.StepProgress(handle)
    return {ready=agrees and ST.rootState == "ROOT_ADMITTED" and handle == nil or false,
        relevant=relevant or false, ownerAgrees=agrees or false,
        reason=not agrees and "OWNER_OR_GENERATION_MISMATCH"
            or handle and (relevant and "CATALOG_COMMIT_PENDING" or "UNRELATED_CATALOG_WORK")
            or ST.rootState,
        kind=handle and (handle.maintenanceOperation or handle.completion or handle.mode),
        phase=handle and handle.phase, pumps=handle and handle.pumps or 0,
        totalPumps=ST.debugStats.rootPumps,
        work=Candidate.PreparationWork(handle), row=handle and handle.rowIndex or 0,
        index=handle and handle.indexIndex or 0,
        witnessRoot=witness and witness.rootIndex or 0,
        witnessDepth=witness and #witness.frames or 0,
        stepDone=stepDone, stepTotal=stepTotal,
        binding=ST.bindingGeneration, generation=ST.generation},
        relevant and handle.preparationIdentity or nil
end

function Catalog.PumpRootAdmission(expectedPreparation)
    if ST.exhausted then
        return {state=ST.rootState, reason="GENERATION_EXHAUSTED", pumps=0}
    end
    local handle = ST.candidate
    if not handle then return {state=ST.rootState, reason=ST.rootReason, pumps=0} end
    if expectedPreparation ~= nil then
        local _, current = Catalog.ManualPreparationStatus()
        if current ~= expectedPreparation then
            return {state="pending", reason="PREPARATION_SUPERSEDED", pumps=handle.pumps}, false
        end
    end
    local drift = TokenDrifted(handle.token)
    if drift then
        handle.phase, handle.failure = "failed", drift
        return FinishAdmission("failed")
    end
    local before, phase = Candidate.PreparationWork(handle), handle.phase
    local outcome = FinishAdmission(PumpAdmission(handle))
    return outcome, outcome.state ~= "failed" and (Candidate.PreparationWork(handle) > before
        or handle.phase ~= phase or outcome.state == "committed")
end

function Catalog.BindMutationCompletion(ticket, callback)
    if type(ticket) ~= "table" or ST.mutationTickets[ticket] ~= true
        or ticket.state ~= "pending" or type(callback) ~= "function"
        or ticket.completionCallback ~= nil then
        return false, "INVALID_MUTATION_TICKET"
    end
    ticket.completionCallback = callback
    return true
end

function Catalog.CancelRootAdmission()
    if ST.candidate then
        local abandoned = ST.candidate
        ST.candidate = nil
        ST.rootState, ST.rootReason = "ROOT_UNBOUND", "CANCELLED"
        PublishInvalidServing()
        if abandoned.mode == "mutation" then
            EvidenceCancelCandidate()
            SettleMutationTicket(abandoned, "failed", false, "CANCELLED")
        end
    end
    return {state=ST.rootState, reason=ST.rootReason}
end

-- MASTER-RC-006, architecture line 1715. One public admission call performs
-- no more than one V1 slice and returns the honest pending or terminal result.
local function AdmissionSlice()
    local result = Catalog.PumpRootAdmission()
    if type(result) == "table" and result.state == "pending" then
        return {state="pending", pumps=result.pumps}
    end
    return DeepCopy(ST.lastInitSummary
        or SummaryOf(nil, ST.rootState, ST.rootReason))
end

function Catalog.Init(database, bundle)
    ST.rebindRequired = nil
    ST.debugStats.initCalls = ST.debugStats.initCalls + 1
    if ST.exhausted then
        return SummaryOf(nil, ST.rootState, "GENERATION_EXHAUSTED")
    end
    local nextDb = type(database) == "table" and database or {}
    local nextBundled = type(bundle) == "table" and bundle
        or type(Nexus.BundledBuilds) == "table" and Nexus.BundledBuilds
        or EMPTY_BUNDLED
    local nextBaseline = type(nextBundled.builds) == "table" and nextBundled.builds or {}
    if ST.candidate == nil and ST.db == nextDb and ST.bundled == nextBundled
        and ST.baseline == nextBaseline
        and (ST.rootState == "ROOT_ADMITTED" or ST.rootState == "ROOT_READ_ONLY_FUTURE_SCHEMA")
        and ST.lastInitSummary then
        local servingRoot = ServingCatalogRoot()
        local token = servingRoot and servingRoot.token or ST.futureToken
        if token and not TokenDrifted(token)
            and token.ownerIdentity == CurrentOwnerKey() then
            ST.debugStats.fastPathHits = ST.debugStats.fastPathHits + 1
            local summary = DeepCopy(ST.lastInitSummary)
            summary.migrated, summary.redundantRemoved = false, 0
            return summary
        end
    end
    -- Repeated calls with the same exact source resume the same private handle.
    -- Do not compare nextBaseline here: an absent bundle builds a fresh empty
    -- table for that expression on every call and would restart forever.
    if ST.candidate ~= nil and ST.db == nextDb and ST.bundled == nextBundled then
        return AdmissionSlice()
    end
    ST.debugStats.rebinds = ST.debugStats.rebinds + 1
    -- MASTER-RC-001, dependent-side prohibition of architecture lines
    -- 1207-1211. This previously called Nexus.LoadoutEvidence.Init(nextDb):
    -- BuildCatalog, itself a named dependent initializer, drove another
    -- domain owner directly. The evidence pool is still admitted before the
    -- catalog, but by the startup coordinator (core/Store.lua BootstrapSlice)
    -- and by the coordinator rebind pump, never from here.
    Catalog.BeginRootAdmission(nextDb, nextBundled)
    return AdmissionSlice()
end

------------------------------------------------------------------------
-- Public: diagnostics and state
------------------------------------------------------------------------

function Catalog.Budget()
    return {totals=DeepCopy(BUDGET), slices=DeepCopy(SLICE),
        maximumPumps=ADMISSION_MAX_PUMPS}
end

function Catalog.BudgetCounters()
    local counters = ST.candidate and ST.candidate.counters or ST.lastCounters
    if not counters then return NewCounters() end
    return DeepCopy(counters)
end

function Catalog.RootState()
    local servingRoot = ServingCatalogRoot()
    if ST.rootState == "ROOT_ADMITTED" and servingRoot then
        local drift = TokenDrifted(servingRoot.token)
        if drift then Invalidate(drift) end
    end
    return {
        state=ST.rootState, reason=ST.rootReason, generation=ST.generation,
        -- The serving pointer and the exact durable bundle generation it binds.
        servingGeneration=ST.servingGeneration,
        durableBundleGeneration=ST.durableBundleGeneration,
        generationMaximum=GENERATION_MAXIMUM,
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
    if not root then
        -- A root-fatal source refusal invalidates every authority query. This
        -- fixed deny-only result does not assert that the typed ID exists.
        if ST.rootState == "ROOT_INVALIDATED" then out.state = "INVALIDATED" end
        return out
    end
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

function Catalog.DebugStats()
    local stats = DeepCopy(ST.debugStats)
    -- MASTER-RC-011: registry entries still bound to a superseded serving
    -- generation. The documented cap is one bounded stale sentinel per family.
    stats.retainedRoots = RetainedRootCount()
    stats.cursorFamilyCap = #CURSOR_FAMILIES
    return stats
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
    -- A sparse match set does not make a maximum root safe to scan in one
    -- public call. Refuse from fixed root metadata before inspecting its first
    -- slot; the caller can retain the matching cursor instead.
    if root.slotCount > BUDGET.oneCallRows then
        return nil, "CURSOR_REQUIRED"
    end
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
    local servingGeneration = ST.servingGeneration
    local count = 0
    for id, record in pairs(all) do
        count = count + 1
        visitor(id, record)
        if ST.servingGeneration ~= servingGeneration then
            return count, "STALE_CURSOR"
        end
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
-- MASTER-RC-010. A legacy raw-ID continuation carries no generation, so a walk
-- captured against one root kept stepping a REPLACED root and served rows
-- committed after the walk began. Each legacy family now binds the generation
-- its walk started at: a continuation presented after a root replacement
-- returns STALE_CURSOR once and INVALID_CURSOR thereafter, which is the
-- "stale once, then invalidate" contract the root requires.
--
-- The public (id, record, done) shape is unchanged. Every consumer --
-- core/Sync.lua, core/SyncCompatibility.lua, core/BuildHashCache.lua and the
-- retention reservation sweeps -- breaks on `done or id == nil` before reading
-- the second slot, so the reason travels there without disturbing them.
local function LegacyWalkGuard(family, cursorId)
    local walks = ST.legacyWalks
    if walks == nil then walks = {}; ST.legacyWalks = walks end
    if cursorId == nil then
        -- A fresh walk binds the current published generation.
        walks[family] = {generation=ST.generation, nextIndex=1}
        return walks[family]
    end
    local walk = walks[family]
    if walk == nil then return nil, "INVALID_CURSOR" end
    if walk.generation ~= ST.generation then
        if not walk.staled then
            walk.staled = true
            return nil, "STALE_CURSOR"
        end
        return nil, "INVALID_CURSOR"
    end
    if walk.lastId ~= cursorId then return nil, "INVALID_CURSOR" end
    return walk
end

local function VectorStep(vector, walk, root)
    local key = vector[walk.nextIndex]
    walk.nextIndex = walk.nextIndex + 1
    local verdict = key and root.rows[key] or nil
    walk.lastId = verdict and verdict.id or nil
    return verdict
end

function Catalog.SyncDeltaNext(cursor)
    local root = Gate()
    if not root then return nil, nil, true end
    local walk, guardWhy = LegacyWalkGuard("delta", cursor)
    if guardWhy then return nil, guardWhy, true end
    local verdict = VectorStep(root.overlayKeys, walk, root)
    if not verdict then return nil, nil, true end
    local record = SyncEligible(verdict) and PublicRecord(verdict) or nil
    return verdict.id, record, false
end

function Catalog.TombstoneNext(cursor)
    local root = Gate()
    if not root then return nil, nil, true end
    local walk, guardWhy = LegacyWalkGuard("tombstone", cursor)
    if guardWhy then return nil, guardWhy, true end
    local verdict = VectorStep(root.tombstoneKeys, walk, root)
    if not verdict then return nil, nil, true end
    return verdict.id, TombstoneView(verdict), false
end

function Catalog.BarrierNext(cursor)
    local root = Gate()
    if not root then return nil, nil, true end
    local walk, guardWhy = LegacyWalkGuard("barrier", cursor)
    if guardWhy then return nil, guardWhy, true end
    local verdict = VectorStep(root.barrierKeys, walk, root)
    if not verdict then return nil, nil, true end
    return verdict.id, Catalog.BarrierState(verdict.id), false
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
    return Generation.Advance(ST, "reservationEpoch")
end

function Candidate.BeginAdmissionFinalization(handle)
    local source = handle.source or handle.token.databaseIdentity
    local classification, metaReason, meta, metaVersion =
        ClassifyMetadata(rawget(source, "buildCatalog"))
    if classification == "invalid" then return false, metaReason end
    local catalogVersion = tostring(ST.bundled
        and ST.bundled.catalogVersion or "unversioned")
    local needsMigration = handle.mode ~= "mutation" and (meta == nil
        or tonumber(rawget(meta, "schemaVersion")) ~= STORAGE_SCHEMA_VERSION
        or tostring(rawget(meta, "catalogVersion") or "") ~= catalogVersion)
    local publishPlan = handle.mode == "mutation"
        and Generation.MutationPlan(handle.items) or {
        {owner=ST, key="preparationEpoch", amount=1},
        {owner=ST, key="generation", amount=1},
        {owner=ST, key="semanticGeneration", amount=1},
        {owner=ST, key="servingGeneration", amount=1},
    }
    local claimCount = (handle.claim and 1 or 0)
        + (handle.claims and #handle.claims or 0)
    if handle.mode == "mutation" and claimCount > 0 then
        publishPlan[#publishPlan + 1] = {
            owner=ST, key="reservationEpoch", amount=claimCount,
        }
    end
    if handle.bundleClass == "absent" or needsMigration then
        publishPlan[#publishPlan + 1] = {
            owner=ST, key="durableBundleGeneration", amount=1,
        }
    end
    local countersOk, countersWhy = Generation.Preflight(publishPlan)
    if not countersOk then return false, countersWhy end
    handle.publishPlan = publishPlan
    handle.meta, handle.metaVersion = meta, metaVersion
    handle.catalogVersion, handle.needsMigration = catalogVersion, needsMigration
    handle.counts = {bundled=handle.mapCounts.bundled or 0,
        overlay=0, tombstones=0, barriers=0, available=0, invalid=0, future=0}
    handle.overlayKeys, handle.tombstoneKeys, handle.barrierKeys = {}, {}, {}
    handle.finalizeIndex, handle.prune, handle.pruneIndex = 1, {}, 1
    handle.pruneDrops = {}
    handle.phase = "finalize-scan"
    return true
end

Candidate.BASELINE_IGNORED_FIELDS = {
    isMine=true, ownerVerified=true, needsFullBuild=true, linkHash=true,
    fingerprintHash=true, ordinaryCompletenessReason=true,
    claimedOwnerKey=true, relaySender=true,
}

function Candidate.PumpBaselineComparison(task, work)
    while not Exhausted(work.budget) do
        local pending = task.pending
        if pending then
            local bytes = math.min(pending.bytes,
                SLICE.bytesInspected - work.budget.bytesInspected)
            if bytes > 0 then
                Charge(work, "bytesInspected", bytes)
                pending.bytes = pending.bytes - bytes
            end
            if pending.bytes > 0 then return nil end
            task.pending = nil
            local frame, key = pending.frame, pending.key
            if not (frame.top and Candidate.BASELINE_IGNORED_FIELDS[key]) then
                local left, right = pending.left, pending.right
                if type(left) ~= type(right) then return true, false end
                if type(left) == "table" then
                    if task.seen[left] then
                        if task.seen[left] ~= right then return true, false end
                    else
                        task.seen[left] = right
                        task.frames[#task.frames + 1] = {
                            left=left, right=right, phase="left",
                        }
                        Charge(work, "nodes", 1)
                    end
                elseif left ~= right then return true, false end
            end
        else
            local frame = task.frames[#task.frames]
            if not frame then return true, true end
            local source = frame.phase == "left" and frame.left or frame.right
            local key, value = next(source, frame.cursor)
            if key == nil then
                if frame.phase == "left" then
                    frame.phase, frame.cursor = "right", nil
                else task.frames[#task.frames] = nil end
            else
                frame.cursor = key
                local left = frame.phase == "left" and value or rawget(frame.left, key)
                local right = frame.phase == "right" and value or rawget(frame.right, key)
                task.pending = {frame=frame, key=key, left=left, right=right,
                    bytes=ScalarBytes(key) + ScalarBytes(left) + ScalarBytes(right)}
                Charge(work, "edges", 1)
            end
        end
    end
    return nil
end

function Candidate.PumpBaseline(handle, slot, verdict, work)
    if not slot.bundled or verdict.hasUnknown or RawLocalMarker(slot.overlay) then
        return true, false
    end
    local task = handle.baselineTask
    if not task then
        task = {walker=NewWalker(slot.bundled, {})}
        handle.baselineTask = task
        Charge(work, "rows", 1)
    end
    if task.walker then
        if WalkRow(task.walker, work) == "pending" then return nil end
        task.verdict = FinishRowVerdict(task.walker, slot, "bundled", {})
        task.walker = nil
        if not task.verdict.snapshot then
            handle.baselineTask = nil
            return true, false
        end
        task.frames = {{left=verdict.snapshot, right=task.verdict.snapshot,
            phase="left", top=true}}
        task.seen = {[verdict.snapshot]=task.verdict.snapshot}
    end
    local complete, equivalent = Candidate.PumpBaselineComparison(task, work)
    if not complete then return nil end
    if equivalent then slot.pruneVerdict = task.verdict end
    handle.baselineTask = nil
    return true, equivalent
end

function Candidate.PumpAdmissionFinalization(handle, work)
    while handle.finalizeIndex <= handle.slotCount do
        if Exhausted(work.budget) then return nil end
        local slot = handle.slotVector[handle.finalizeIndex]
        local verdict = handle.verdicts[slot.key]
        local prune = false
        if handle.needsMigration and verdict.source == "overlay" and verdict.snapshot then
            local complete
            complete, prune = Candidate.PumpBaseline(handle, slot, verdict, work)
            if not complete then return nil end
        end
        local counts = handle.counts
        if verdict.snapshot then counts.available = counts.available + 1
        elseif verdict.state == "READ_ONLY_FUTURE_SCHEMA" then
            counts.future = counts.future + 1
        elseif verdict.state == "INVALIDATED" and not verdict.tombstone then
            counts.invalid = counts.invalid + 1
        end
        if verdict.tombstone then
            counts.tombstones = counts.tombstones + 1
            handle.tombstoneKeys[#handle.tombstoneKeys + 1] = slot.key
        end
        if verdict.overlayRaw ~= nil then counts.overlay = counts.overlay + 1 end
        if verdict.barrier then
            counts.barriers = counts.barriers + 1
            handle.barrierKeys[#handle.barrierKeys + 1] = slot.key
        end
        if verdict.source == "overlay" and verdict.snapshot then
            handle.overlayKeys[#handle.overlayKeys + 1] = slot.key
        end
        if prune then
            handle.prune[#handle.prune + 1] = slot
        end
        handle.finalizeIndex = handle.finalizeIndex + 1
        Charge(work, "rows", 1)
    end
    handle.phase = "finalize-prune"
    return true
end

function Candidate.PumpAdmissionPrune(handle, work)
    while handle.pruneIndex <= #handle.prune do
        if Exhausted(work.budget) then return nil end
        local slot = handle.prune[handle.pruneIndex]
        slot.overlay = nil
        local replacement = slot.pruneVerdict
        slot.pruneVerdict = nil
        replacement.overlayRaw, replacement.bundledRaw = nil, slot.bundled
        handle.verdicts[slot.key] = replacement
        handle.counts.overlay = math.max(0, handle.counts.overlay - 1)
        handle.pruneDrops[slot.id] = true
        handle.pruneIndex = handle.pruneIndex + 1
        Charge(work, "rows", 1)
    end
    handle.index, handle.indexIndex = NewIndex(), 0
    handle.phase = "index"
    return true
end

function Candidate.BeginAdmissionBundle(handle)
    if handle.mode == "mutation" then
        handle.phase = "witness-capture"
        return true
    end
    if handle.bundleClass ~= "absent" and not handle.needsMigration then
        handle.finalBundle, handle.bundleWrite = handle.bundleRaw, false
        handle.phase = "witness-capture"
        return true
    end
    local migrated = ShallowSnapshot(handle.meta)
    migrated.schemaVersion = STORAGE_SCHEMA_VERSION
    migrated.catalogVersion = handle.catalogVersion
    migrated.sourceVersion = tostring(ST.bundled
        and ST.bundled.sourceVersion or "unknown")
    local overrides = {buildCatalog=migrated}
    local evidence = EvidenceCandidateStore()
    if evidence ~= nil then overrides.loadoutEvidence = evidence end
    local generation = 1
    if handle.bundleClass ~= "absent" then
        generation = Generation.Next(ST, "durableBundleGeneration")
        if not generation then return false, "GENERATION_EXHAUSTED" end
    end
    local drops = {communityBuilds=handle.pruneDrops}
    handle.bundleBuilder = Candidate.NewBundle(handle.token.databaseIdentity,
        handle.source or handle.token.databaseIdentity, generation, overrides, drops)
    handle.bundleWrite = true
    handle.phase = "bundle"
    return true
end

local function IssueClaim(kind, typedKey, id, extra)
    if ST.activeClaim and ST.claimRegistry[ST.activeClaim] then
        return nil, "CLAIM_ACTIVE"
    end
    local reservationEpoch = ST.reservationEpoch
    local advanced, advanceWhy = AdvanceReservation()
    if not advanced then return nil, advanceWhy end
    local claim = {kind=kind, typedKey=typedKey, generation=ST.generation,
        reservationEpoch=reservationEpoch}
    ST.claimRegistry[claim] = {kind=kind, typedKey=typedKey, id=id,
        generation=ST.generation, reservationEpoch=reservationEpoch,
        extra=extra}
    ST.activeClaim = claim
    ST.debugStats.claimsIssued = ST.debugStats.claimsIssued + 1
    return claim
end

local function ReleaseClaim(claim, counterAlreadyAdvanced)
    if ST.claimRegistry[claim] then
        if not counterAlreadyAdvanced then
            local advanced, advanceWhy = AdvanceReservation()
            if not advanced then return false, advanceWhy end
        end
        ST.claimRegistry[claim] = nil
        if ST.activeClaim == claim then ST.activeClaim = nil end
        return true
    end
    return false
end

function Catalog.BeginAllocationClaim(id)
    local root, why = MutationGate()
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
    local root, why = MutationGate()
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

-- MASTER-RC-003: identity is (spellId, quality, locked); the source array is
-- deliberately absent so a cross-array duplicate keys to one canonical member.
local function TupleKey(row)
    return tostring(row.spellId) .. ":" .. tostring(row.quality) .. ":"
        .. (row.locked and "1" or "0")
end

-- Construct the detached destination row: exact V1 known fields, the
-- existing unknown owners at their original scope, and every incoming
-- unknown field that does not overwrite an existing owner.
-- MASTER-RC-013 sibling, MASTER-RC-016. Row-to-tombstone replacement used to
-- drop every top-level and tuple-scoped unknown field the row owned: the
-- durable overlay row disappeared and the tombstone record carried none of it,
-- so future-owned evidence was destroyed by a delete. The required repaired
-- outcome is that "unknown evidence [is] carried in the atomic transaction and
-- restored by scope, or fail closed".
--
-- This builds the scoped carriage. Top-level unknown owners and each tuple's
-- exact unknown subtree are copied out under their original scope, bounded by
-- the same BUDGET.unknownTables ceiling that bounds admission.
local function CarriedUnknown(existing)
    if type(existing) ~= "table" then return nil end
    local top, tuples, count = nil, nil, 0
    for key, value in pairs(existing.unknown or {}) do
        top = top or {}
        top[key] = DeepCopy(value)
    end
    for _, row in ipairs(existing.grouped or {}) do
        if row.unknown ~= nil and count < BUDGET.unknownTables then
            tuples = tuples or {}
            tuples[TupleKey(row)] = DeepCopy(row.unknown)
            count = count + 1
        end
    end
    if top == nil and tuples == nil then return nil end
    return {top=top, tuples=tuples}
end

local function BuildDestination(verdict, walker, existing, carried)
    local destination = {}
    for key, value in pairs(verdict.snapshot) do
        if FIELD[key] and FIELD[key].kind ~= "evidence" then
            destination[key] = DeepCopy(value)
        end
    end
    destination.id = verdict.id
    local existingUnknown = existing and existing.unknown or {}
    for key, value in pairs(existingUnknown) do destination[key] = DeepCopy(value) end
    -- Restored by scope: unknown evidence carried through a tombstone returns to
    -- the exact scope it was taken from, and never overwrites a live owner.
    for key, value in pairs(carried and carried.top or {}) do
        if destination[key] == nil then destination[key] = DeepCopy(value) end
    end
    for key, value in pairs(walker.unknown) do
        if destination[key] == nil then destination[key] = DeepCopy(value) end
    end
    local existingTupleUnknown = {}
    for key, value in pairs(carried and carried.tuples or {}) do
        existingTupleUnknown[key] = value
    end
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

-- MASTER-RC-005: preparation may intern evidence, so it opens a detached
-- evidence candidate first. Nothing interned here is durable until the authority
-- commit coordinator installs the candidate inside the complete bundle.
local function CompactDestination(destination, work)
    local compaction = Nexus and Nexus.DataCompaction
    local evidence = Nexus and Nexus.LoadoutEvidence
    local compacted = false
    if not (evidence and type(destination.echoes) == "table"
        and #destination.echoes > 0) then return true end
    EvidenceBeginCandidate()
    local _, candidateWhy, copied = EvidenceCandidateStore()
    copied = tonumber(copied) or 0
    if work and copied > 0 then
        Charge(work, "edges", copied)
        Charge(work, "nodes", copied)
    end
    if candidateWhy == "EVIDENCE_CANDIDATE_PENDING" then
        return nil, candidateWhy
    end
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
    if not compacted and type(evidence.Reference) == "function" then
        ST.debugStats.referenceCalls = ST.debugStats.referenceCalls + 1
        local ok, reference, created = pcall(evidence.Reference, destination,
            "echoes", "evidenceKey")
        if ok and reference and created then
            ST.debugStats.referenceStores = ST.debugStats.referenceStores + 1
        end
    end
    return true
end

local function BumpRevisions(verdict, previous, id)
    Generation.Advance(ST, "generation")
    Generation.Advance(ST, "committedMutationRevision")
    Generation.Advance(ST, "semanticGeneration")
    Generation.Advance(ST.recordRevisions, id, 1, true)
    Generation.Advance(ST, "exactRevisionClock")
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
    if verdict and verdict.barrier then
        InsertKey(root.barrierKeys, key, root.slots)
    else
        RemoveKey(root.barrierKeys, key)
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

-- One complete detached replacement of a whole candidate, published through one
-- durable bundle write and one serving-root swap (MASTER-RC-001, MASTER-RC-002,
-- MASTER-RC-005).
--
-- Every fallible step -- map shape, drift, verdict preparation,
-- replacement-root construction and bundle construction -- happens off-state.
-- The protected section allocates nothing and runs no production callback: it is
-- the single durable bundle rawset, its identity verification, the
-- non-authoritative legacy mirror rawsets, and one currentServingRoot swap.
--
-- The live published root's rows, slots, index, counts, and vectors are never
-- mutated. The candidate root is invisible until the swap, and the superseded
-- root becomes unreachable immediately after it.
local function CloneServingCatalogRoot(root)
    local rows, slots = {}, {}
    for key, value in pairs(root.rows) do rows[key] = value end
    for key, value in pairs(root.slots) do slots[key] = value end
    local slotVector = {}
    for index, slot in ipairs(root.slotVector) do slotVector[index] = slot end
    local overlayKeys, tombstoneKeys, barrierKeys = {}, {}, {}
    for index, key in ipairs(root.overlayKeys) do overlayKeys[index] = key end
    for index, key in ipairs(root.tombstoneKeys) do tombstoneKeys[index] = key end
    for index, key in ipairs(root.barrierKeys) do barrierKeys[index] = key end
    return {
        generation=root.generation, token=root.token, rows=rows, slots=slots,
        slotVector=slotVector, slotCount=root.slotCount,
        index=CloneIndex(root.index), counts=DeepCopy(root.counts),
        overlayKeys=overlayKeys, tombstoneKeys=tombstoneKeys,
        barrierKeys=barrierKeys,
        catalogVersion=root.catalogVersion, schemaVersion=root.schemaVersion,
        migrated=false, redundantRemoved=0,
    }
end

local function DetachedSlot(slot)
    return {key=slot.key, id=slot.id, kind=slot.kind, overlay=slot.overlay,
        bundled=slot.bundled, tombstone=slot.tombstone, barrier=slot.barrier}
end
Candidate.ReleaseClaim = ReleaseClaim
Candidate.BumpRevisions = BumpRevisions

local function DetachedVerdict(verdict)
    if type(verdict) ~= "table" then return verdict end
    local copy = {}
    for key, value in pairs(verdict) do copy[key] = value end
    return copy
end

local function CommitBatch(root, items, reason, deferred, notifyScope,
                           existingHandle, bundleOverrides, counterPlan)
    local drift = TokenDrifted(root.token)
    if drift then
        EvidenceCancelCandidate()
        Invalidate(drift)
        return false, drift
    end
    local db = root.token.databaseIdentity
    -- The occupied bundle is the sole durable authority payload. Every commit
    -- reads its current payload from that bundle and never from the exact PR #68
    -- legacy locations, which after occupancy are neither input nor storage.
    local current = ST.durableBundle
    if type(current) ~= "table" then
        EvidenceCancelCandidate()
        Invalidate("AUTHORITY_BUNDLE_ABSENT")
        return false, "AUTHORITY_BUNDLE_ABSENT"
    end

    for field, value in pairs(bundleOverrides or {}) do
        if not BUNDLE_MUTATION_OVERRIDES[field]
            or type(value) ~= "table" or getmetatable(value) ~= nil then
            EvidenceCancelCandidate()
            return false, "ROOT_MAP_MALFORMED"
        end
    end

    -- Off-state validation. A target map that exists but is not a table would
    -- fail mid-publication, so the candidate is refused before any durable write.
    for _, item in ipairs(items) do
        for _, write in ipairs(item.writes) do
            local map = rawget(current, write.map)
            if map ~= nil and type(map) ~= "table" then
                EvidenceCancelCandidate()
                return false, "ROOT_MAP_MALFORMED"
            end
        end
    end

    -- Every required increment, including every per-item revision, is refused
    -- before any one of them is performed.
    local publishPlan = counterPlan or Generation.MutationPlan(items)
    local countersOk, countersWhy = Generation.Preflight(publishPlan)
    if not countersOk then
        EvidenceCancelCandidate()
        return false, countersWhy
    end
    Generation.PrepareReceiptRecords(items)
    local handle, handleWhy = Candidate.NewMutation(root, items, reason,
        deferred, notifyScope, existingHandle, bundleOverrides, publishPlan)
    if not handle then
        EvidenceCancelCandidate()
        return false, handleWhy
    end
    ST.candidate = handle
    if existingHandle then return handle, "ROOT_MUTATION_PENDING" end
    local outcome = Catalog.PumpRootAdmission()
    if type(outcome) == "table" and outcome.state == "committed" then
        return true
    end
    if type(outcome) == "table" and outcome.state == "failed" then
        return false, outcome.reason
    end
    return outcome, "ROOT_MUTATION_PENDING"
end

local function CommitSlot(root, slot, verdict, rawWrites, reason, deferred,
                          receiptRecords)
    return CommitBatch(root, {{slot=slot, verdict=verdict, writes=rawWrites,
        receiptRecords=receiptRecords}},
        reason, deferred)
end

local function SlotFor(root, id)
    local typedKey, kind = TypedKey(id)
    if not typedKey then return nil, nil, "INVALID_TYPED_ID" end
    local published = root.slots[typedKey]
    local slot = published and DetachedSlot(published)
        or {key=typedKey, id=id, kind=kind}
    return slot, root.rows[typedKey]
end

local function ConsumeClaim(claim, typedKey, kind)
    local entry = ST.claimRegistry[claim]
    if not entry or entry.kind ~= kind then return false, "INVALID_CLAIM" end
    if entry.typedKey ~= typedKey then return false, "TYPED_ID_MISMATCH" end
    if entry.superseded or entry.generation ~= ST.generation
        or entry.reservationEpoch + 1 ~= ST.reservationEpoch then
        local released, releaseWhy = ReleaseClaim(claim)
        if not released and releaseWhy then return false, releaseWhy end
        return false, "STALE_CLAIM"
    end
    return true, entry
end

-- An owner-routed mutation supersedes an outstanding explicit claim: the old
-- claim stays registered only so its next use refuses as stale.
local function SupersedeActiveClaim()
    local active = ST.activeClaim
    if active and ST.claimRegistry[active] then
        local advanced, advanceWhy = AdvanceReservation()
        if not advanced then return false, advanceWhy end
        ST.claimRegistry[active].superseded = true
        ST.activeClaim = nil
    end
    return true
end

local function BundledRawFor(slot)
    if slot.bundled ~= nil then return slot.bundled end
    if type(ST.baseline) == "table" then return rawget(ST.baseline, slot.id) end
    return nil
end

function Candidate.ReleasePreparedPutClaim(handle)
    local put = handle and handle.put
    local claim = put and put.claim
    if not claim then return true end
    local released, why = ReleaseClaim(claim)
    if released then put.claim = nil end
    return released, why or "INVALID_CLAIM"
end

function Candidate.FinishPreparedPutWithoutCommit(handle, success, value)
    -- A batch member refuses only itself: the candidate's staged evidence
    -- belongs to the whole batch, and the batch cancels it if it fails.
    if not handle.batchMember then EvidenceCancelCandidate() end
    local released, releaseWhy = Candidate.ReleasePreparedPutClaim(handle)
    if not released then return "failed", releaseWhy end
    handle.storedAs = handle.put and handle.put.storedAs or value
    if success then return "noop", value end
    return "failed", value
end

function Candidate.NewPutPreparation(root, record, options, claim, deferred, slot,
                                     existing, readmitTombstone, carriedUnknown)
    return {
        mode="mutation", phase="put-prepare", counters=NewCounters(), pumps=1,
        preparationIdentity={},
        failure=nil, token=root.token, originalRoot=root, ticket=nil,
        reason="build put", deferred=deferred, notifyScope=nil,
        put={
            phase="row", root=root, record=record, options=options,
            claim=claim, slot=slot, existing=existing,
            readmitTombstone=readmitTombstone,
            carriedUnknown=carriedUnknown,
            walker=NewWalker(record, options), storedAs="overlay",
        },
    }
end

function Candidate.ActivatePutPreparation(handle)
    local ticket = {state="pending", committed=false, pumps=handle.pumps}
    handle.ticket = ticket
    ST.mutationTickets[ticket] = true
    ST.candidate = handle
    return nil, "ROOT_MUTATION_PENDING", ticket
end

function Candidate.PumpPutPreparation(handle, work)
    local put = handle.put
    while not Exhausted(work.budget) do
        if put.phase == "row" then
            if WalkRow(put.walker, work) == "pending" then return "pending" end
            put.phase = "finish"
        elseif put.phase == "finish" then
            local verdict = FinishRowVerdict(put.walker, put.slot, "overlay",
                put.options)
            if verdict.state ~= "ADMITTED" then
                -- Scalar facts only, for the caller's own refusal message.
                local semantic = verdict.semantic
                if type(semantic) == "table" then
                    handle.failureDetail = {ordinary=semantic.ordinary,
                        locked=semantic.locked, total=semantic.total,
                        representation=put.walker
                            and put.walker.semanticRepresentation or nil}
                end
                return Candidate.FinishPreparedPutWithoutCommit(handle, false,
                    verdict.reason)
            end
            if put.readmitTombstone and not (verdict.verifiedOwner ~= nil
                and verdict.verifiedOwner == CurrentOwnerKey()) then
                return Candidate.FinishPreparedPutWithoutCommit(handle, false,
                    "LOCAL_OWNER_REQUIRED")
            end
            local existingRow = put.existing and put.existing.snapshot
                and put.existing or nil
            if existingRow and existingRow.verifiedOwner
                and verdict.verifiedOwner ~= existingRow.verifiedOwner
                and (verdict.verifiedOwner or put.options.source == "remote") then
                return Candidate.FinishPreparedPutWithoutCommit(handle, false,
                    "PROVENANCE_COLLISION")
            end
            local destination, destinationWhy = BuildDestination(verdict,
                put.walker, existingRow and existingRow.source == "overlay"
                    and existingRow or nil, put.carriedUnknown)
            if not destination then
                return Candidate.FinishPreparedPutWithoutCommit(handle, false,
                    destinationWhy)
            end
            put.verdict, put.destination, put.existingRow = verdict, destination,
                existingRow
            put.bundledRaw = BundledRawFor(put.slot)
            verdict.bundledRaw, verdict.overlayRaw = put.bundledRaw, destination
            if put.bundledRaw ~= nil and verdict.snapshot
                and not verdict.hasUnknown and not RawLocalMarker(destination) then
                put.baselineWalker = NewWalker(put.bundledRaw, {})
                put.phase = "baseline"
            else
                put.phase = "compact"
            end
        elseif put.phase == "baseline" then
            if WalkRow(put.baselineWalker, work) == "pending" then
                return "pending"
            end
            local bundledVerdict = FinishRowVerdict(put.baselineWalker,
                put.slot, "bundled", {})
            if BaselineVerdictEquivalent(put.verdict.snapshot,
                put.verdict.hasUnknown, put.destination, bundledVerdict) then
                put.storedAs = "baseline"
                put.rawWrites = {
                    {map="communityBuilds", id=put.slot.id, value=nil},
                }
                put.slot.overlay, put.slot.bundled, put.slot.tombstone = nil,
                    put.bundledRaw, nil
                put.verdict = bundledVerdict
                bundledVerdict.bundledRaw, bundledVerdict.overlayRaw =
                    put.bundledRaw, nil
                if not (put.existing and put.existing.overlayRaw ~= nil)
                    and not put.readmitTombstone and put.existing
                    and put.existing.snapshot
                    and put.existing.source == "bundled" then
                    return Candidate.FinishPreparedPutWithoutCommit(handle, true,
                        put.storedAs)
                end
                put.phase = "finalize"
            else
                put.phase = "compact"
            end
        elseif put.phase == "compact" then
            local complete, compactWhy = CompactDestination(put.destination, work)
            if not complete then
                if compactWhy == "EVIDENCE_CANDIDATE_PENDING" then
                    return "pending"
                end
                return Candidate.FinishPreparedPutWithoutCommit(handle, false,
                    compactWhy)
            end
            put.phase = "finalize"
        elseif put.phase == "finalize" then
            local verdict, existingRow = put.verdict, put.existingRow
            if put.storedAs ~= "baseline" then
                if existingRow and existingRow.source == "overlay"
                    and not put.readmitTombstone
                    and type(existingRow.overlayRaw) == "table"
                    and DeepEqual(verdict.snapshot, existingRow.snapshot)
                    and DeepEqual(put.destination, existingRow.overlayRaw) then
                    return Candidate.FinishPreparedPutWithoutCommit(handle, true,
                        put.storedAs)
                end
                put.rawWrites = {
                    {map="communityBuilds", id=put.slot.id,
                        value=put.destination},
                }
                put.slot.overlay, put.slot.bundled, put.slot.tombstone =
                    put.destination, put.bundledRaw, nil
            end
            if put.readmitTombstone then
                put.rawWrites[#put.rawWrites + 1] = {
                    map="syncTombstones", id=put.slot.id, value=nil,
                }
            end
            if existingRow or put.readmitTombstone
                or (put.existing and put.existing.state == "INVALIDATED") then
                verdict.state = "READMITTED"
            end
            if put.existing and put.existing.barrier then
                verdict.barrier = put.existing.barrier
            end
            if put.claim then
                local releaseReady, releaseWhy = Generation.Preflight({
                    {owner=ST, key="reservationEpoch", amount=1},
                })
                if not releaseReady then
                    return Candidate.FinishPreparedPutWithoutCommit(handle, false,
                        releaseWhy)
                end
            end
            put.item = {slot=put.slot, verdict=verdict, writes=put.rawWrites}
            put.phase = "commit"
        elseif put.phase == "commit" then
            if not handle.ticket then return "prepared" end
            local claim, storedAs = put.claim, put.storedAs
            local outcome, commitWhy = CommitBatch(put.root, {put.item},
                "build put", handle.deferred, nil, handle)
            if type(outcome) ~= "table" then
                return Candidate.FinishPreparedPutWithoutCommit(handle, false,
                    commitWhy)
            end
            handle.claim, handle.completion, handle.storedAs = claim, "put",
                storedAs
            return "ready"
        else
            return Candidate.FinishPreparedPutWithoutCommit(handle, false,
                "ROOT_CONSTRUCTION_FAILED")
        end
    end
    return "pending"
end

-- Identity, slot, reservation and claim decisions for ONE record, exactly as
-- a single put makes them. Every receiver batch member is prepared through
-- this same function, so no record reaches the catalog through a shortcut
-- that skips these checks.
function Candidate.PreparePut(root, record, options, claim, deferred)
    local carriedUnknown
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
            -- MASTER-RC-016: restore the unknown evidence this exact tombstone
            -- carried, at its original scope.
            local carriedRaw = entryOrWhy.extra.tombstoneRaw
            carriedUnknown = type(carriedRaw) == "table"
                and carriedRaw.unknownEvidence or nil
        end
    else
        if existing and existing.tombstone then return false, "TOMBSTONE_RESERVATION" end
        if existing and existing.barrier then return false, "BARRIER_RESERVATION" end
        if existing and existing.state == "READ_ONLY_FUTURE_SCHEMA" then
            return false, "FUTURE_SCHEMA_RESERVATION"
        end
        if Occupancy(existing) == "VACANT" then
            local superseded, supersedeWhy = SupersedeActiveClaim()
            if not superseded then return false, supersedeWhy end
            local issued, issueWhy = IssueClaim("allocation", slot.key, record.id)
            if not issued then return false, issueWhy end
            claim = issued
        end
    end
    if readmitTombstone and options.source ~= "local" and options.source ~= "import" then
        if claim then
            local released, releaseWhy = ReleaseClaim(claim)
            if not released then return false, releaseWhy end
        end
        return false, "LOCAL_OWNER_REQUIRED"
    end
    local candidateSlot = {key=slot.key, id=slot.id, kind=slot.kind}
    return Candidate.NewPutPreparation(root, record, options, claim,
        deferred,
        candidateSlot, existing, readmitTombstone, carriedUnknown)
end

local function PutInternal(record, options, claim, deferred)
    ST.debugStats.putCalls = ST.debugStats.putCalls + 1
    local root, why = MutationGate()
    if not root then return false, why end
    local handle, prepareWhy = Candidate.PreparePut(root, record, options,
        claim, deferred)
    if not handle then return false, prepareWhy end
    local work = NewWork(handle.counters)
    local prepared, prepareWhy = Candidate.PumpPutPreparation(handle, work)
    ClosePump(work)
    if prepared == "pending" then
        return Candidate.ActivatePutPreparation(handle)
    end
    if prepared == "failed" then return false, prepareWhy end
    if prepared == "noop" then return true, prepareWhy end
    if prepared ~= "prepared" then
        return false, prepareWhy or "ROOT_CONSTRUCTION_FAILED"
    end
    local put = handle.put
    local ok, commitWhy = CommitSlot(root, put.item.slot, put.item.verdict,
        put.item.writes, "build put", deferred)
    if type(ok) == "table" and ok.state == "pending" then
        ST.candidate.claim = put.claim
        ST.candidate.completion = "put"
        ST.candidate.storedAs = put.storedAs
        return nil, commitWhy, ok
    end
    if put.claim then
        local released, releaseWhy = ReleaseClaim(put.claim)
        if not released then return false, releaseWhy end
    end
    if not ok then return false, commitWhy end
    ST.debugStats.putChanges = ST.debugStats.putChanges + 1
    return true, put.storedAs
end

-- A finite, frozen batch of validated records published as ONE catalog
-- mutation. Membership is fixed when the batch is created: a record that
-- arrives later waits for a later batch instead of enlarging or restarting
-- this candidate. Each member is prepared by PreparePutHandle and the ordinary
-- row walk, keeps its own ticket, storage answer and refusal reason, and the
-- admitted members are published together by the existing multi-item commit.
-- The batch holds each member's allocation reservation until publication, in
-- handle.claims; it is the only holder, because one candidate owns the
-- mutation gate for its whole life.
Candidate.BATCH_MAX_MEMBERS = 64

function Candidate.NewBatchPutPreparation(root, members, deferred)
    return {
        mode="mutation", phase="batch-prepare", counters=NewCounters(), pumps=1,
        preparationIdentity={}, failure=nil, token=root.token,
        originalRoot=root, ticket=nil, reason="receiver batch",
        deferred=deferred, notifyScope="all", completion="put",
        storedAs="overlay", claims={},
        batch={members=members, index=1, items={}, admitted=0, refused=0},
    }
end

function Candidate.PumpBatchPutPreparation(handle, work)
    local batch = handle.batch
    while batch.index <= #batch.members do
        if Exhausted(work.budget) then return "pending" end
        local member = batch.members[batch.index]
        if member.outcome then
            batch.index = batch.index + 1
        elseif not member.sub then
            local sub, prepareWhy = Candidate.PreparePut(handle.originalRoot,
                member.record, member.options, nil, handle.deferred)
            if sub then
                sub.batchMember = true
                member.sub = sub
            else
                member.outcome = "failed"
                member.reason = prepareWhy or "ROOT_CONSTRUCTION_FAILED"
                batch.refused, batch.index = batch.refused + 1, batch.index + 1
            end
        else
            local prepared, why = Candidate.PumpPutPreparation(member.sub, work)
            if prepared == "pending" then return "pending" end
            if prepared == "prepared" then
                local put = member.sub.put
                if put.claim then
                    handle.claims[#handle.claims + 1] = put.claim
                    if ST.activeClaim == put.claim then ST.activeClaim = nil end
                    put.claim = nil
                end
                member.outcome, member.storedAs = "admitted", put.storedAs
                batch.items[#batch.items + 1] = put.item
                batch.admitted = batch.admitted + 1
            elseif prepared == "noop" then
                member.outcome, member.storedAs = "noop", why
            else
                member.outcome = "failed"
                member.reason = why or "ROOT_CONSTRUCTION_FAILED"
                batch.refused = batch.refused + 1
            end
            batch.index = batch.index + 1
        end
    end
    if #batch.items == 0 then return "noop" end
    local outcome, commitWhy = CommitBatch(handle.originalRoot, batch.items,
        "receiver batch", handle.deferred, handle.notifyScope, handle)
    if type(outcome) ~= "table" then
        return "failed", commitWhy or "ROOT_CONSTRUCTION_FAILED"
    end
    return "ready"
end

-- Public: commit several validated records in one bounded catalog mutation.
-- requests[i] = {record=<validated record>, options=<put options>}. The answer
-- is one ticket per request, in the same order, or false and a reason when no
-- candidate could be created at all.
function Catalog.PutBatch(requests)
    if type(requests) ~= "table" then return false, "batch required" end
    local count = #requests
    if count == 0 then return false, "empty batch" end
    if count > Candidate.BATCH_MAX_MEMBERS then
        return false, "BATCH_TOO_LARGE"
    end
    local root, why = MutationGate()
    if not root then return false, why end
    ST.debugStats.putCalls = ST.debugStats.putCalls + count
    local members, tickets, seen = {}, {}, {}
    for index = 1, count do
        local request = requests[index]
        local member = {ticket={state="pending", committed=false, pumps=0}}
        local record = type(request) == "table" and request.record or nil
        local typedKey = type(record) == "table" and record.id ~= nil
            and TypedKey(record.id) or nil
        if type(request) ~= "table" then
            member.outcome, member.reason = "failed", "build id required"
        elseif typedKey ~= nil and seen[typedKey] then
            member.outcome, member.reason = "failed", "DUPLICATE_BATCH_MEMBER"
        else
            if typedKey ~= nil then seen[typedKey] = true end
            member.record, member.options = request.record, request.options
        end
        ST.mutationTickets[member.ticket] = true
        members[index], tickets[index] = member, member.ticket
    end
    ST.candidate = Candidate.NewBatchPutPreparation(root, members, false)
    return nil, "ROOT_MUTATION_PENDING", tickets
end

function Catalog.Put(record, options)
    return PutInternal(record, options, nil, false)
end

function Catalog.PutWithClaim(claim, record, options)
    if type(claim) ~= "table" or not ST.claimRegistry[claim] then
        return false, "INVALID_CLAIM"
    end
    local root, why = MutationGate()
    if not root then return false, why end
    local entry = ST.claimRegistry[claim]
    local typedKey = type(record) == "table" and TypedKey(record.id) or nil
    if entry.typedKey ~= typedKey then return false, "TYPED_ID_MISMATCH" end
    return PutInternal(record, options, claim, false)
end

-- Stage one repair record without publishing a represented-data revision.
function Catalog.PutDeferred(record)
    local root, why = MutationGate()
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
    local ok, storedAs, ticket = PutInternal(record, {}, nil, true)
    if ok == nil and storedAs == "ROOT_MUTATION_PENDING" then
        return nil, storedAs, ticket
    end
    if not ok then return false, storedAs end
    return true, storedAs, true
end

function Catalog.PublishDeferred(changed, reason)
    local root, why = MutationGate()
    if not root then return false, why end
    changed = math.max(0, math.floor(tonumber(changed) or 0))
    if changed == 0 then return true, 0 end
    local countersOk, countersWhy = Generation.Preflight({
        {owner=ST, key="recordEpoch", amount=1},
        {owner=ST, key="exactEpoch", amount=1},
    })
    if not countersOk then return false, countersWhy end
    Generation.Advance(ST, "recordEpoch")
    Generation.Advance(ST, "exactEpoch")
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
    local root, why = MutationGate()
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
    if type(ok) == "table" and ok.state == "pending" then
        return nil, commitWhy, ok
    end
    if not ok then return false, commitWhy end
    return true
end

function Catalog.RemoveOverlayBatch(ids)
    local root, why = MutationGate()
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
        receiptRevision=nil,
        receiptAtServerTime=TrustedServerTime() or 0,
        remoteStampEvidence=tonumber(tombstone.stamp) or 0,
        -- MASTER-RC-016: the replaced row's unknown evidence travels with the
        -- tombstone inside the same atomic transaction instead of being lost.
        unknownEvidence=CarriedUnknown(existing),
    }
end

function Catalog.SetTombstone(id, tombstone, options)
    local root, why = MutationGate()
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
        -- row: a derived verified overlay owner and nothing else. A bundled
        -- row's coherent author/player/ownerKey tuple proves nothing
        -- (MASTER-RC-004, architecture line 193).
        local owns = current ~= nil
            and Identity.LocalOwnsBuild(existing.snapshot, current)
        if not owns then
            return false, "LOCAL_OWNER_REQUIRED"
        end
        local record = TombstoneRecord(slot, existing, tombstone)
        if not record then return false, "GENERATION_EXHAUSTED" end
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
        }, "build tombstoned", false, {record})
        if type(ok) == "table" and ok.state == "pending" then
            return nil, commitWhy, ok
        end
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
    -- MASTER-RC-004: a bundled row's owner text is not remote delete authority
    -- either. Architecture line 195 gives remote rows their owner contract --
    -- "Require Identity.TransportOwns(canonicalOwnerKey, actualSender) for
    -- direct owner authority" -- and that contract is preserved unchanged for
    -- remote and overlay rows. But line 193 admits from a bundled row "Content
    -- fields and immutable bundled source position only", so a bundled row's
    -- ownerKey is content, not an owner claim a sender can prove. A bundled row
    -- therefore carries remote delete authority only from a derived verified
    -- owner.
    local owner = existing.verifiedOwner
    if owner == nil and existing.source ~= "bundled" then
        owner = storedOwner or claimedOwner or nil
    end
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
    if type(ok) == "table" and ok.state == "pending" then
        return nil, commitWhy, ok
    end
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
    local root, why = MutationGate()
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
    if type(ok) == "table" and ok.state == "pending" then
        return nil, commitWhy, ok
    end
    if not ok then return false, commitWhy end
    return true
end

------------------------------------------------------------------------
-- Maintenance transactions (retention, compaction, migration)
------------------------------------------------------------------------

function Catalog.BeginCatalogMaintenance(request)
    request = type(request) == "table" and request or {}
    if ST.activeMaintenance ~= nil then return nil, "MAINTENANCE_ACTIVE" end
    local root, why = MutationGate()
    if not root then return nil, why end
    if request.database ~= ST.db then return nil, "DETACHED_DATABASE" end
    if ST.activeMaintenance ~= nil then return nil, "MAINTENANCE_ACTIVE" end
    EvidenceBeginCandidate()
    local handle = {operation=request.operation or "retention",
        generation=ST.generation, revision=ST.committedMutationRevision,
        ops={}, seen={}, receiptCount=0, state="open"}
    ST.maintenanceRegistry[handle] = true
    ST.activeMaintenance = handle
    return handle
end

local function MaintenanceOpen(handle)
    if type(handle) ~= "table" or not ST.maintenanceRegistry[handle] then
        return nil, "INVALID_MAINTENANCE_HANDLE"
    end
    local root, why = MutationGate(handle)
    if not root then return nil, why end
    if handle.state ~= "open" then return nil, "INVALID_MAINTENANCE_HANDLE" end
    return root
end

local function BarrierRecord(slot, existing)
    return {
        schemaVersion=BARRIER_SCHEMA_VERSION,
        typedId={luaType=slot.kind, exactValue=slot.id},
        evictedCatalogGeneration=ST.generation,
        evictedSourceIdentity=existing.source or "overlay",
        evictedProvenanceIdentity=existing.verifiedOwner
            or (existing.snapshot and existing.snapshot.claimedOwnerKey) or "",
        receiptRevision=nil,
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
    local barrier, barrierWhy = BarrierRecord(slot, existing)
    if not barrier then return false, barrierWhy end
    handle.seen[slot.key] = true
    handle.ops[#handle.ops + 1] = {kind="evict", slot=slot, existing=existing,
        barrier=barrier}
    handle.receiptCount = handle.receiptCount + 1
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

function Catalog.MaintenanceReplaceRow(handle, id, record, options)
    local root, why = MaintenanceOpen(handle)
    if not root then return false, why end
    local slot, existing, slotWhy = SlotFor(root, id)
    if not slot then return false, slotWhy end
    options = type(options) == "table" and options or {}
    local inserting = existing == nil and options.allowInsert == true
    if not inserting
        and not (existing and existing.snapshot and existing.source == "overlay") then
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
    if existing and existing.verifiedOwner
        and verdict.verifiedOwner ~= existing.verifiedOwner then
        handle.failed = "PROVENANCE_COLLISION"
        return false, "PROVENANCE_COLLISION"
    end
    local destination, destinationWhy = BuildDestination(verdict, walker, existing)
    if not destination then
        handle.failed = destinationWhy
        return false, destinationWhy
    end
    verdict.state = inserting and "ADMITTED" or "READMITTED"
    verdict.bundledRaw = existing and existing.bundledRaw or BundledRawFor(slot)
    verdict.overlayRaw = destination
    verdict.barrier = existing and existing.barrier or nil
    handle.seen[slot.key] = true
    handle.ops[#handle.ops + 1] = {kind="replace", slot=slot, existing=existing,
        verdict=verdict, destination=destination}
    return true
end

function Catalog.MaintenanceOverlayNext(handle, cursor)
    local root, why = MaintenanceOpen(handle)
    if not root then return nil, nil, true, why end
    if cursor == nil then
        handle.overlayNextIndex, handle.overlayLastId = 1, nil
    elseif handle.overlayLastId ~= cursor then
        return nil, nil, true, "INVALID_CURSOR"
    end
    local verdict = handle.copyVerdict
    if not verdict then
        local key = root.overlayKeys[handle.overlayNextIndex]
        local admitted = key and root.rows[key] or nil
        if admitted then
            verdict = {id=admitted.id, snapshot=admitted.overlayRaw}
        end
    end
    if not verdict then return nil, nil, true end
    local row, copiedVerdict, complete = Cursor.CopyStep(handle, verdict)
    if not complete then return nil, nil, false, "COPY_PENDING" end
    handle.overlayNextIndex = handle.overlayNextIndex + 1
    handle.overlayLastId = copiedVerdict.id
    return copiedVerdict.id, row, false
end

function Catalog.CancelMaintenance(handle)
    if type(handle) == "table" and ST.maintenanceRegistry[handle] then
        handle.state = "cancelled"
        ST.maintenanceRegistry[handle] = nil
        if ST.activeMaintenance == handle then ST.activeMaintenance = nil end
        EvidenceCancelCandidate()
        return true
    end
    return false
end

function Candidate.NewMaintenancePreparation(root, maintenance, overrides)
    local ticket = {state="pending", committed=false, pumps=0}
    ST.mutationTickets[ticket] = true
    return {
        mode="mutation", phase="maintenance-prepare", preparationIdentity={},
        counters=NewCounters(), pumps=0, failure=nil,
        token=root.token, originalRoot=root, ticket=ticket,
        reason=nil, deferred=true, notifyScope="all",
        maintenance=maintenance, maintenanceIndex=1, items={},
        bundleOverrides=overrides,
        completion="maintenance",
        maintenanceOperation=maintenance.operation,
        applied=#maintenance.ops,
    }
end

function Candidate.PumpMaintenancePreparation(handle, work)
    local maintenance = handle.maintenance
    local op = maintenance.ops[handle.maintenanceIndex]
    if not op then
        local outcome, why = CommitBatch(handle.originalRoot, handle.items,
            nil, true, "all", handle, handle.bundleOverrides)
        if type(outcome) ~= "table" then return "failed", why end
        return "ready"
    end
    local slot, existing = op.slot, op.existing
    local item = {slot=slot, writes={}}
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
        item.receiptRecords = {op.barrier}
    elseif op.kind == "retire" then
        item.verdict = RetiredReplacement(slot, existing)
        item.writes[1] = {map="syncTombstones", id=slot.id, value=nil}
    elseif op.kind == "expire" then
        local replacement
        if existing.snapshot or existing.tombstone
            or existing.state == "READ_ONLY_FUTURE_SCHEMA"
            or existing.state == "INVALIDATED" then
            replacement = DetachedVerdict(existing)
            replacement.barrier = nil
        end
        slot.barrier = nil
        item.verdict = replacement
        item.writes[1] = {map="communityRetentionEvictions",
            id=slot.id, value=nil}
    elseif op.kind == "replace" then
        local compacted, compactWhy = CompactDestination(op.destination, work)
        if not compacted then
            if compactWhy == "EVIDENCE_CANDIDATE_PENDING" then
                return "pending"
            end
            return "failed", compactWhy
        end
        slot.overlay = op.destination
        item.verdict = op.verdict
        item.writes[1] = {map="communityBuilds", id=slot.id,
            value=op.destination}
    else
        return "failed", "CANDIDATE_FAILED"
    end
    handle.items[#handle.items + 1] = item
    handle.maintenanceIndex = handle.maintenanceIndex + 1
    Charge(work, "rows", 1)
    Charge(work, "nodes", 1)
    -- One operation is one retained maintenance frontier step. Yield even when
    -- the row was small so one public call cannot drain the complete list.
    return "pending"
end

function Catalog.CommitMaintenance(handle, bundleOverrides)
    local root, why = MaintenanceOpen(handle)
    if not root then return false, why end
    handle.state = "committing"
    ST.maintenanceRegistry[handle] = nil
    if ST.activeMaintenance == handle then ST.activeMaintenance = nil end
    if handle.failed then
        EvidenceCancelCandidate()
        return false, "CANDIDATE_FAILED"
    end
    if handle.generation ~= ST.generation
        or handle.revision ~= ST.committedMutationRevision then
        EvidenceCancelCandidate()
        return false, "SOURCE_DRIFT"
    end
    local count = math.max(1, #handle.ops)
    local headPlan = {
        {owner=ST, key="durableBundleGeneration", amount=1},
        {owner=ST, key="preparationEpoch", amount=1},
        {owner=ST, key="servingGeneration", amount=1},
        {owner=ST, key="generation", amount=count},
        {owner=ST, key="committedMutationRevision", amount=count},
        {owner=ST, key="semanticGeneration", amount=count},
        {owner=ST, key="exactRevisionClock", amount=count},
    }
    if handle.receiptCount > 0 then
        headPlan[#headPlan + 1] = {owner=ST, key="receiptRevision",
            amount=handle.receiptCount}
    end
    local headOk, headWhy = Generation.Preflight(headPlan)
    if not headOk then
        EvidenceCancelCandidate()
        return false, headWhy
    end
    if #handle.ops == 0 and next(bundleOverrides or {}) == nil
        and not Generation.EvidenceCandidateChanged() then
        EvidenceCancelCandidate()
        return true, {applied=0}
    end
    local candidate = Candidate.NewMaintenancePreparation(
        root, handle, bundleOverrides)
    ST.candidate = candidate
    local outcome = Catalog.PumpRootAdmission()
    if candidate.ticket.state == "committed" then
        return true, {applied=#handle.ops}
    end
    if candidate.ticket.state == "failed" then
        return false, candidate.ticket.reason
    end
    return nil, "ROOT_MUTATION_PENDING", candidate.ticket
end

function Catalog.RemoveTombstonesBatch(ids)
    local root, why = MutationGate()
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

-- One namespace spends one file-level local for the six bounded cursor
-- families. Copy state stays private and is discarded on completion,
-- supersession, staleness, or publication.
-- Cursor was forward-declared with Candidate so maintenance can reuse the same
-- retained defensive-copy frontier.

function Cursor.ChargeCopy(nodes, bytes, pending)
    local stats = ST.debugStats
    stats.cursorCopyNodes = stats.cursorCopyNodes + nodes
    stats.cursorCopyBytes = stats.cursorCopyBytes + bytes
    stats.maxCursorCopyNodesPerCall = math.max(
        stats.maxCursorCopyNodesPerCall, nodes)
    stats.maxCursorCopyBytesPerCall = math.max(
        stats.maxCursorCopyBytesPerCall, bytes)
    if pending then stats.cursorCopyPending = stats.cursorCopyPending + 1 end
end

function Cursor.AssignCopy(state, frame, key, value)
    if type(value) ~= "table" then
        frame.target[key] = value
        return
    end
    local existing = state.copySeen[value]
    if existing then
        frame.target[key] = existing
        return
    end
    local child = {}
    state.copySeen[value] = child
    frame.target[key] = child
    state.copyFrames[#state.copyFrames + 1] = {
        source=value, target=child, cursor=nil,
    }
end

function Cursor.CopyStep(state, verdict)
    if state.copyState ~= "COPY_PENDING" then
        local source = verdict and verdict.snapshot
        if type(source) ~= "table" then return nil, verdict, true end
        state.copyState = "COPY_PENDING"
        state.copyAccumulator = {}
        state.copySeen = {[source]=state.copyAccumulator}
        state.copyFrames = {{source=source, target=state.copyAccumulator, cursor=nil}}
        state.copyVerdict = verdict
        state.copyFresh = true
        state.copyEdge = nil
    end
    local nodes, bytes = 0, 0
    if state.copyFresh then
        nodes, bytes, state.copyFresh = 1, 1, nil
    end
    while nodes < 64 and bytes < 2048 do
        local edge = state.copyEdge
        if edge then
            local consumed = math.min(edge.remaining, 2048 - bytes)
            edge.remaining = edge.remaining - consumed
            bytes = bytes + consumed
            if edge.remaining > 0 then break end
            state.copyEdge = nil
            Cursor.AssignCopy(state, edge.frame, edge.key, edge.value)
        else
            local frame = state.copyFrames[#state.copyFrames]
            if not frame then
                local copy, copiedVerdict = state.copyAccumulator, state.copyVerdict
                state.copyState, state.copyAccumulator = "IDLE", nil
                state.copySeen, state.copyFrames, state.copyVerdict = nil, nil, nil
                if copy.id == nil then copy.id = copiedVerdict.id end
                Cursor.ChargeCopy(nodes, bytes, false)
                return copy, copiedVerdict, true
            end
            local key, value = next(frame.source, frame.cursor)
            if key == nil then
                state.copyFrames[#state.copyFrames] = nil
            else
                frame.cursor = key
                nodes = nodes + 1
                local cost = ScalarBytes(key)
                    + (type(value) == "table" and 1 or ScalarBytes(value))
                local available = 2048 - bytes
                if cost > available then
                    state.copyEdge = {frame=frame, key=key, value=value,
                        remaining=cost - available}
                    bytes = 2048
                else
                    bytes = bytes + cost
                    Cursor.AssignCopy(state, frame, key, value)
                end
            end
        end
    end
    Cursor.ChargeCopy(nodes, bytes, true)
    return nil, state.copyVerdict, false
end

local function BeginCursor(family, state)
    local root, why = Gate()
    if not root then return nil, why end
    local sequence, sequenceWhy = Generation.Advance(ST, "cursorSequence")
    if not sequence then return nil, sequenceWhy end
    local previous = ST.activeCursors[family]
    if previous then ST.cursorRegistry[previous] = nil end
    local token = {kind=family, cursorId=sequence, generation=ST.generation}
    state = state or {}
    -- MASTER-RC-011: the entry binds the serving generation it was issued
    -- against. It holds no root wrapper, so a superseded root is released at
    -- publication instead of being pinned by an unused retained token.
    state.kind, state.generation = family, ST.generation
    state.servingGeneration = ST.servingGeneration
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
    if not root or state.stale or state.servingGeneration ~= ST.servingGeneration
        or state.generation ~= ST.generation then
        -- A stale-once sentinel refuses exactly once and then leaves the
        -- registry; its next use is INVALID_CURSOR.
        ST.cursorRegistry[token] = nil
        if ST.activeCursors[family] == token then ST.activeCursors[family] = nil end
        return nil, "STALE_CURSOR"
    end
    return state, nil, root
end

local function NextVerdict(state, root, filter)
    local inspected = 0
    while state.nextIndex <= root.slotCount and inspected < BUDGET.oneCallRows do
        local slot = root.slotVector[state.nextIndex]
        state.nextIndex = state.nextIndex + 1
        inspected = inspected + 1
        local verdict = root.rows[slot.key]
        if verdict and filter(verdict) then
            ST.debugStats.cursorRowsInspected =
                ST.debugStats.cursorRowsInspected + inspected
            ST.debugStats.maxCursorRowsPerCall = math.max(
                ST.debugStats.maxCursorRowsPerCall, inspected)
            return verdict, false
        end
    end
    ST.debugStats.cursorRowsInspected =
        ST.debugStats.cursorRowsInspected + inspected
    ST.debugStats.maxCursorRowsPerCall = math.max(
        ST.debugStats.maxCursorRowsPerCall, inspected)
    if inspected == BUDGET.oneCallRows then return nil, true end
    state.exhausted = true
    return nil, false
end

function Cursor.RecordPage(state, root, filter)
    local verdict, scanPending
    if state.copyState == "COPY_PENDING" then
        verdict = state.copyVerdict
    else
        verdict, scanPending = NextVerdict(state, root, filter)
        if scanPending then return {done=false, state="COPY_PENDING"} end
        if not verdict then return {done=true} end
    end
    local copy, copiedVerdict, complete = Cursor.CopyStep(state, verdict)
    if not complete then return {done=false, state="COPY_PENDING"} end
    return {done=false, id=copiedVerdict.id, record=copy,
        source=copiedVerdict.source}
end

function Cursor.VectorRecordPage(state, root)
    local verdict
    if state.copyState == "COPY_PENDING" then
        verdict = state.copyVerdict
    else
        local key = state.keys[state.nextIndex]
        state.nextIndex = state.nextIndex + 1
        verdict = key and root.rows[key] or nil
        if not verdict then state.exhausted = true; return {done=true} end
    end
    local copy, copiedVerdict, complete = Cursor.CopyStep(state, verdict)
    if not complete then return {done=false, state="COPY_PENDING"} end
    return {done=false, id=copiedVerdict.id, record=copy,
        source=copiedVerdict.source}
end

function Catalog.BeginRecordCursor()
    return BeginCursor("record")
end

-- Passive position of a live record cursor: rows already passed and the
-- fixed row count of the root it reads. No registry, drift or root change;
-- a stale or foreign token simply has no position.
function Catalog.RecordCursorProgress(token)
    local state = type(token) == "table" and ST.cursorRegistry[token] or nil
    local root = ServingCatalogRoot()
    if not state or state.kind ~= "record" or not root or state.stale
        or state.servingGeneration ~= ST.servingGeneration
        or state.generation ~= ST.generation
        or type(root.slotCount) ~= "number" or root.slotCount < 1 then
        return nil
    end
    return math.min(root.slotCount, math.max(0, state.nextIndex - 1)), root.slotCount
end

function Catalog.RecordCursorNext(token)
    local state, why, root = CursorState(token, "record")
    if not state then return nil, why end
    if state.exhausted then return {done=true} end
    return Cursor.RecordPage(state, root, Admitted)
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
    local verdict, pending = NextVerdict(state, root, Admitted)
    if pending then return nil, false, nil, "COPY_PENDING" end
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
    return Cursor.RecordPage(state, root, SyncEligible)
end

function Catalog.BeginSavedMirrorCursor(author)
    local root, why = Gate()
    if not root then return nil, why end
    ST.debugStats.savedMirrorEnumerations = ST.debugStats.savedMirrorEnumerations + 1
    local bucket = root.index.saved[RelatedKey(author, "saved")]
    return BeginCursor("saved-mirror", {keys=bucket and bucket.idVector or {}})
end

function Catalog.SavedMirrorCursorNext(token)
    local state, why, root = CursorState(token, "saved-mirror")
    if not state then return nil, why end
    local page = Cursor.VectorRecordPage(state, root)
    if page.record then
        ST.debugStats.savedMirrorRows = ST.debugStats.savedMirrorRows + 1
    end
    return page
end

function Catalog.SavedMirrorIds(author)
    local root, why = Gate()
    if not root then return {}, why end
    ST.debugStats.savedMirrorEnumerations = ST.debugStats.savedMirrorEnumerations + 1
    local ids = {}
    local bucket = root.index.saved[RelatedKey(author, "saved")]
    for _, key in ipairs(bucket and bucket.idVector or {}) do
        local verdict = root.rows[key]
        if verdict then ids[#ids + 1] = verdict.id end
        if #ids > BUDGET.oneCallRows then return nil, "CURSOR_REQUIRED" end
    end
    table.sort(ids, function(left, right)
        return Identity.CompareTypedIds(left, right) < 0
    end)
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
    if state.diagnostic == "overlay" then
        return Cursor.RecordPage(state, root, function(item)
            return item.overlayRaw ~= nil and item.snapshot ~= nil
        end)
    end
    local verdict, pending = NextVerdict(state, root, function(item)
        return item.tombstone ~= nil
    end)
    if pending then return {done=false, state="COPY_PENDING"} end
    if not verdict then return {done=true} end
    return {done=false, id=verdict.id, tombstone=CompatTombstone(verdict),
        state=verdict.tombstone.state}
end

function Cursor.PrepareRelated(state, root)
    if state.parseDone then return true end
    local steps = 0
    while steps < BUDGET.oneCallRows do
        local first, last, rawId, rawCount = state.query:find(
            "(%d+)x(%d+)", state.parseIndex)
        if not first then
            state.parseDone = true
            state.buckets[1], state.buckets[2], state.buckets[3] =
                state.exactBucket, state.titleBucket,
                state.queryTotal >= 6 and state.smallestBucket or nil
            return true
        end
        state.parseIndex = last + 1
        steps = steps + 1
        local id, count = tonumber(rawId), tonumber(rawCount)
        if id and count and count > 0 then
            state.queryTotal = state.queryTotal + count
            local bucket = root.index.spells[
                RelatedKey(state.authorKey, tostring(id))]
            if bucket and (not state.smallestBucket
                or bucket.count < state.smallestBucket.count) then
                state.smallestBucket = bucket
            end
        end
    end
    return false
end

function Cursor.RelatedVerdict(state, root)
    local best
    for index = 1, 3 do
        local bucket = state.buckets[index]
        local key = bucket and bucket.idVector[state.bucketPositions[index]] or nil
        if key and (not best
            or CompareSlots(root.rows[key], root.rows[best]) < 0) then
            best = key
        end
    end
    if not best then state.exhausted = true; return nil end
    for index = 1, 3 do
        local bucket = state.buckets[index]
        if bucket and bucket.idVector[state.bucketPositions[index]] == best then
            state.bucketPositions[index] = state.bucketPositions[index] + 1
        end
    end
    return root.rows[best]
end

function Catalog.BeginRelatedCursor(author, title, fingerprint)
    local root, why = Gate()
    if not root then return nil, why end
    ST.debugStats.relatedLookups = ST.debugStats.relatedLookups + 1
    local authorKey = RelatedText(author)
    local query = type(fingerprint) == "string" and fingerprint or ""
    return BeginCursor("relationship", {
        authorKey=authorKey, query=query, parseIndex=1, queryTotal=0,
        exactBucket=root.index.fingerprints[RelatedKey(authorKey, query)],
        titleBucket=root.index.titles[RelatedKey(authorKey, RelatedText(title))],
        smallestBucket=nil, buckets={}, bucketPositions={1,1,1},
        parseDone=authorKey == "", returned=0,
    })
end

function Catalog.RelatedCursorNext(token)
    local state, why, root = CursorState(token, "relationship")
    if not state then
        return nil, true, why == "INVALID_CURSOR" and "invalid related cursor" or "catalog changed"
    end
    if not Cursor.PrepareRelated(state, root) then
        return nil, false, nil, "COPY_PENDING"
    end
    local verdict, pending
    if state.copyState == "COPY_PENDING" then
        verdict = state.copyVerdict
    else
        verdict = Cursor.RelatedVerdict(state, root)
        if not verdict then return nil, true end
    end
    local copy, _, complete = Cursor.CopyStep(state, verdict)
    if not complete then return nil, false, nil, "COPY_PENDING" end
    state.returned = state.returned + 1
    ST.debugStats.relatedCandidates = ST.debugStats.relatedCandidates + 1
    ST.debugStats.maxRelatedCandidates = math.max(
        ST.debugStats.maxRelatedCandidates, state.returned)
    return copy, false
end

function Catalog.RelatedCandidates(author, title, fingerprint)
    local rows = {}
    local cursor, err = Catalog.BeginRelatedCursor(author, title, fingerprint)
    if not cursor then return rows, err end
    for _ = 1, BUDGET.oneCallRows do
        local record, done, nextErr, pending = Catalog.RelatedCursorNext(cursor)
        if nextErr then return {}, nextErr end
        if pending == "COPY_PENDING" then return nil, "CURSOR_REQUIRED" end
        if record then rows[#rows + 1] = record end
        if done then return rows end
    end
    return nil, "CURSOR_REQUIRED"
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

------------------------------------------------------------------------
-- Initial invalid-bootstrap serving install (MASTER-RC-001).
--
-- AuthorityCommitCoordinatorV1 constructs InvalidBootstrapServingRootV1 once
-- under a fresh session owner before any authority API becomes reachable, and
-- AuthorityServingRootWriterV1 installs it. Numeric zero never recreates session
-- authority: all four domain fields hold the shared immutable invalid marker, so
-- every authority API returns its fixed non-valid result until one complete root
-- publishes through the final swap.
------------------------------------------------------------------------
AuthorityServingRootWriterV1("initial-invalid-install")
