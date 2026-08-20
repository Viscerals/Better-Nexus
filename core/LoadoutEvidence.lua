-- Nexus: canonical, content-addressed Echo evidence owned by SavedVariables.
--
-- This module is deliberately data-only. It never advances revisions, calls
-- GameAdapter, schedules work, or authorizes automation. The additive cutover
-- keeps established inline arrays and adds exact references beside them; compaction
-- remains a separate, verified migration.

Nexus = Nexus or {}
local Evidence = {}
Nexus.LoadoutEvidence = Evidence

local SCHEMA_VERSION = 1
local MAX_ENTRIES = 256
local MAX_TOTAL_STACKS = 10000
local MAX_CONFLICTS = 40
local boundDb, boundReadOnly
local readOnlyEmptyStore = {schemaVersion=SCHEMA_VERSION + 1,entries={}}
local referenceProviders = {}
local referenceProviderGeneration = 0
local runtime = {
    created=0, reused=0, resolved=0, inlineFallbacks=0,
    malformed=0, conflicts={},
    completeness={checks=0,complete=0,absent=0,empty=0,unresolved=0,
        malformed=0,crossRole=0,fingerprintMismatch=0,lockedOnly=0},
}

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

local function FiniteInteger(value, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value or value <= -math.huge
        or value >= math.huge or value ~= math.floor(value)
        or value < minimum or value > maximum then
        return nil
    end
    return value
end

local function Count(source)
    local n = 0
    for _ in pairs(source or {}) do n = n + 1 end
    return n
end

local function RecordConflict(kind, claimed, actual)
    local item = {
        kind=tostring(kind or "conflict"),
        claimed=claimed ~= nil and tostring(claimed) or nil,
        actual=actual ~= nil and tostring(actual) or nil,
    }
    runtime.conflicts[#runtime.conflicts + 1] = item
    while #runtime.conflicts > MAX_CONFLICTS do
        table.remove(runtime.conflicts, 1)
    end
    return item
end

local function Store()
    if type(NexusDB) == "table" and NexusDB ~= boundDb then
        Evidence.Init(NexusDB)
    elseif type(boundDb) ~= "table" then
        NexusDB = type(NexusDB) == "table" and NexusDB or {}
        Evidence.Init(NexusDB)
    end
    local store = boundDb.loadoutEvidence
    if type(store) ~= "table" then
        if boundReadOnly then return readOnlyEmptyStore end
        store = {schemaVersion=SCHEMA_VERSION, entries={}}
        boundDb.loadoutEvidence = store
    end
    if boundReadOnly then return store end
    -- A newer owner may use an entirely different entries shape. Preserve it
    -- byte-for-byte; callers that understand only schema 1 treat an unknown
    -- shape as empty/read-only instead of "repairing" future data.
    if tonumber(store.schemaVersion)
        and tonumber(store.schemaVersion) > SCHEMA_VERSION then
        return store
    end
    if type(store.entries) ~= "table" then store.entries = {} end
    if store.schemaVersion == nil then store.schemaVersion = SCHEMA_VERSION end
    return store
end

local function FingerprintNormalized(rows)
    local parts = {"v1"}
    for _, row in ipairs(rows or {}) do
        parts[#parts + 1] = table.concat({
            tostring(row.spellId), tostring(row.quality),
            tostring(row.stacks), row.locked and "1" or "0",
        }, ":")
    end
    return #parts > 1 and table.concat(parts, "|") or nil
end

function Evidence.Init(database)
    boundDb = type(database) == "table" and database or {}
    local catalog = Nexus and Nexus.BuildCatalog
    local supported = catalog and type(catalog.SchemaVersion) == "function"
        and tonumber(catalog.SchemaVersion()) or nil
    local stored = type(boundDb.buildCatalog) == "table"
        and tonumber(boundDb.buildCatalog.schemaVersion) or nil
    boundReadOnly = supported ~= nil and stored ~= nil and stored > supported
    local store = boundDb.loadoutEvidence
    if type(store) ~= "table" then
        if boundReadOnly then
            return {schemaVersion=nil,entries=0,readOnly=true}
        end
        store = {schemaVersion=SCHEMA_VERSION, entries={}}
        boundDb.loadoutEvidence = store
    end
    if boundReadOnly then
        return {
            schemaVersion=store.schemaVersion,
            entries=type(store.entries) == "table"
                and Count(store.entries) or 0,
            readOnly=true,
        }
    end
    if tonumber(store.schemaVersion)
        and tonumber(store.schemaVersion) > SCHEMA_VERSION then
        return {
            schemaVersion=store.schemaVersion,
            entries=type(store.entries) == "table"
                and Count(store.entries) or 0,
            readOnly=true,
        }
    end
    if type(store.entries) ~= "table" then store.entries = {} end
    if store.schemaVersion == nil then store.schemaVersion = SCHEMA_VERSION end
    return {
        schemaVersion=store.schemaVersion,
        entries=Count(store.entries),
    }
end

-- Canonical exact shape. Duplicate rows merge only when spell, quality, and
-- locked state all match. Locked and ordinary Echoes therefore cannot alias.
function Evidence.Normalize(source, options)
    if type(source) ~= "table" then
        runtime.malformed = runtime.malformed + 1
        return nil, "evidence must be a table"
    end
    options = type(options) == "table" and options or {}
    local grouped, entries, maxIndex, total = {}, 0, 0, 0
    for index, echo in pairs(source) do
        if type(index) ~= "number" or index < 1
            or index ~= math.floor(index) or type(echo) ~= "table" then
            runtime.malformed = runtime.malformed + 1
            return nil, "evidence must be a dense array"
        end
        local spellId = FiniteInteger(echo.spellId or echo.id, 1, 2147483647)
        local quality = FiniteInteger(echo.quality or 0, 0, 2147483647)
        local stacks = FiniteInteger(
            echo.stacks or echo.count or echo.stack or 1,
            1, MAX_TOTAL_STACKS)
        if not spellId or not quality or not stacks then
            runtime.malformed = runtime.malformed + 1
            return nil, "invalid Echo evidence row"
        end
        -- Match the established BuildCatalog/DPS truthiness contract. Legacy
        -- SavedVariables may carry 1 instead of a JSON boolean.
        local locked = options.forceLocked == true
            or (echo.locked and true or false)
        local key = table.concat({
            tostring(spellId), tostring(quality), locked and "1" or "0",
        }, ":")
        local row = grouped[key]
        if row then
            row.stacks = row.stacks + stacks
            if row.stacks > MAX_TOTAL_STACKS then
                runtime.malformed = runtime.malformed + 1
                return nil, "Echo stack total is too large"
            end
        else
            grouped[key] = {
                spellId=spellId, quality=quality, stacks=stacks,
                locked=locked and true or nil,
            }
        end
        entries = entries + 1
        total = total + stacks
        if index > maxIndex then maxIndex = index end
        if entries > MAX_ENTRIES or total > MAX_TOTAL_STACKS then
            runtime.malformed = runtime.malformed + 1
            return nil, "Echo evidence is too large"
        end
    end
    if entries == 0 or entries ~= maxIndex then
        runtime.malformed = runtime.malformed + 1
        return nil, "evidence must be a nonempty dense array"
    end
    local rows = {}
    for _, row in pairs(grouped) do rows[#rows + 1] = row end
    table.sort(rows, function(left, right)
        if left.spellId ~= right.spellId then return left.spellId < right.spellId end
        if left.quality ~= right.quality then return left.quality < right.quality end
        if left.locked ~= right.locked then return left.locked ~= true end
        return left.stacks < right.stacks
    end)
    return rows
end

function Evidence.Fingerprint(source, options)
    local normalized, why = Evidence.Normalize(source, options)
    if not normalized then return nil, why end
    return FingerprintNormalized(normalized), normalized
end

function Evidence.Intern(source, claimedReference, options)
    local exact, normalized = Evidence.Fingerprint(source, options)
    if not exact then return nil, normalized end
    if claimedReference ~= nil and tostring(claimedReference) ~= exact then
        RecordConflict("reference mismatch", claimedReference, exact)
    end
    local store = Store()
    if boundReadOnly or tonumber(store.schemaVersion)
        and tonumber(store.schemaVersion) > SCHEMA_VERSION then
        return nil, "future evidence schema is read-only"
    end
    local entries = store.entries
    local existing = entries[exact]
    if existing ~= nil then
        local existingNormalized = Evidence.Normalize(existing)
        local existingExact = existingNormalized
            and FingerprintNormalized(existingNormalized) or nil
        if existingExact ~= exact
            or not DeepEqual(existingNormalized, normalized) then
            RecordConflict("stored evidence collision", exact, existingExact)
            return nil, "stored evidence conflicts with canonical key"
        end
        runtime.reused = runtime.reused + 1
        return exact, DeepCopy(existingNormalized), false
    end
    entries[exact] = DeepCopy(normalized)
    runtime.created = runtime.created + 1
    return exact, DeepCopy(normalized), true
end

-- Inline evidence wins during the additive stage. A stale or malicious
-- reference is reported but cannot replace the record's independently exact
-- inline array. Pool-only rows resolve only from a self-verifying full key.
function Evidence.Resolve(reference, inline, options)
    local inlineExact, inlineNormalized
    if type(inline) == "table" then
        inlineExact, inlineNormalized = Evidence.Fingerprint(inline, options)
    end
    local storedNormalized
    if type(reference) == "string" and reference ~= "" then
        local store = Store()
        local entries = type(store.entries) == "table" and store.entries or {}
        local stored = entries[reference]
        if stored ~= nil then
            storedNormalized = Evidence.Normalize(stored)
            local storedExact = storedNormalized
                and FingerprintNormalized(storedNormalized) or nil
            if storedExact ~= reference then
                RecordConflict("stored evidence mismatch", reference, storedExact)
                storedNormalized = nil
            end
        end
    end
    if inlineNormalized then
        if reference ~= nil and tostring(reference) ~= inlineExact then
            RecordConflict("inline reference mismatch", reference, inlineExact)
        end
        runtime.inlineFallbacks = runtime.inlineFallbacks + 1
        return DeepCopy(inlineNormalized), inlineExact, "inline"
    end
    if storedNormalized then
        runtime.resolved = runtime.resolved + 1
        return DeepCopy(storedNormalized), reference, "pool"
    end
    return nil, "exact evidence unavailable"
end

function Evidence.Reference(record, inlineField, referenceField, options)
    if type(record) ~= "table" then return nil, "record must be a table" end
    inlineField = inlineField or "echoes"
    referenceField = referenceField or "evidenceKey"
    local source = record[inlineField]
    if type(source) ~= "table" or next(source) == nil then
        return nil, "inline evidence unavailable"
    end
    local previous = record[referenceField]
    local exact, normalizedOrWhy, created = Evidence.Intern(
        source, previous, options)
    if not exact then return nil, normalizedOrWhy end
    record[referenceField] = exact
    return exact, created, previous ~= exact
end

local function ToDpsRows(source, includeLocked)
    local counts = {}
    for _, echo in ipairs(type(source) == "table" and source or {}) do
        if includeLocked or not echo.locked then
            local spellId = tonumber(echo.spellId)
            local stacks = tonumber(echo.stacks or echo.count) or 0
            if spellId and stacks > 0 then
                counts[spellId] = (counts[spellId] or 0) + stacks
            end
        end
    end
    local rows = {}
    for spellId, count in pairs(counts) do
        rows[#rows + 1] = {spellId=spellId, count=count}
    end
    table.sort(rows, function(left, right) return left.spellId < right.spellId end)
    return #rows > 0 and rows or nil
end

function Evidence.ReferenceDpsRow(row)
    if type(row) ~= "table" then return false end
    local changed = false
    if type(row.echoes) == "table" and next(row.echoes) ~= nil then
        local _, _, didChange = Evidence.Reference(
            row, "echoes", "evidenceKey")
        changed = didChange or changed
    end
    if type(row.lockedEchoes) == "table" and next(row.lockedEchoes) ~= nil then
        local _, _, didChange = Evidence.Reference(
            row, "lockedEchoes", "lockedEvidenceKey", {forceLocked=true})
        changed = didChange or changed
    end
    return changed
end

function Evidence.ResolveDpsEchoes(row, locked)
    if type(row) ~= "table" then return nil end
    local inlineField = locked and "lockedEchoes" or "echoes"
    local referenceField = locked and "lockedEvidenceKey" or "evidenceKey"
    local options = locked and {forceLocked=true} or nil
    local normalized = Evidence.Resolve(
        row[referenceField], row[inlineField], options)
    return ToDpsRows(normalized, locked == true)
end

function Evidence.ResolveDpsRow(row)
    if type(row) ~= "table" then return nil end
    local copy = DeepCopy(row)
    copy.echoes = Evidence.ResolveDpsEchoes(row, false)
    copy.lockedEchoes = Evidence.ResolveDpsEchoes(row, true)
    return copy
end

local function OrdinaryFingerprint(rows)
    local counts, ids = {}, {}
    for _, row in ipairs(rows or {}) do
        local id = tonumber(row.spellId)
        local stacks = tonumber(row.stacks or row.count) or 0
        if id and stacks > 0 then counts[id] = (counts[id] or 0) + stacks end
    end
    for id in pairs(counts) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        parts[#parts + 1] = tostring(id) .. "x" .. tostring(counts[id])
    end
    return #parts > 0 and table.concat(parts, ",") or nil
end

-- One shared ordinary-loadout authority. Flags, claimed counts, locked pools,
-- and a reference token alone are never completeness evidence. The returned
-- row is fixed-shape and defensive; callers may project it but must not store
-- it back as an implicit migration.
function Evidence.OrdinaryCompleteness(row)
    local out = {
        complete=false,reason="absent",echoes=nil,evidenceKey=nil,
        fingerprint=nil,echoCount=0,
    }
    local lockedOnly = type(row) == "table"
        and ((type(row.lockedEchoes) == "table"
                and next(row.lockedEchoes) ~= nil)
            or (type(row.lockedEvidenceKey) == "string"
                and row.lockedEvidenceKey ~= "")) or false
    local function Finish(reason)
        reason = reason or out.reason
        out.reason, out.lockedOnly = reason, lockedOnly
        local stats = runtime.completeness
        stats.checks = stats.checks + 1
        if out.complete then stats.complete = stats.complete + 1
        elseif reason == "empty" then stats.empty = stats.empty + 1
        elseif reason == "unresolved" then stats.unresolved = stats.unresolved + 1
        elseif reason == "malformed" then stats.malformed = stats.malformed + 1
        elseif reason == "cross-role" then stats.crossRole = stats.crossRole + 1
        elseif reason == "fingerprint-mismatch" then
            stats.fingerprintMismatch = stats.fingerprintMismatch + 1
        else stats.absent = stats.absent + 1 end
        if lockedOnly and not out.complete then
            stats.lockedOnly = stats.lockedOnly + 1
        end
        return out
    end
    if type(row) ~= "table" then return Finish("absent") end
    local inline = row.echoes
    local normalized, exactOrWhy
    if type(inline) == "table" then
        for _, echo in pairs(inline) do
            if type(echo) == "table" and (echo.locked
                or (echo.sourceRole ~= nil
                    and tostring(echo.sourceRole) ~= "ordinary")) then
                if echo.locked then lockedOnly = true end
                out.reason = "cross-role"
                return Finish("cross-role")
            end
        end
        if next(inline) ~= nil then
            exactOrWhy, normalized = Evidence.Fingerprint(inline)
            if exactOrWhy == nil then return Finish("malformed") end
            if row.evidenceKey ~= nil
                and tostring(row.evidenceKey) ~= exactOrWhy then
                RecordConflict("inline reference mismatch",
                    row.evidenceKey, exactOrWhy)
            end
            runtime.inlineFallbacks = runtime.inlineFallbacks + 1
        end
    end
    if not normalized then
        normalized, exactOrWhy = Evidence.Resolve(row.evidenceKey, nil)
    end
    if not normalized then
        if type(inline) == "table" and next(inline) == nil
            and not (type(row.evidenceKey) == "string"
                and row.evidenceKey ~= "") then
            out.reason = "empty"
        elseif type(inline) == "table" and next(inline) ~= nil then
            out.reason = "malformed"
        elseif type(row.evidenceKey) == "string" and row.evidenceKey ~= "" then
            out.reason = "unresolved"
        end
        return Finish(out.reason)
    end
    for _, echo in ipairs(normalized) do
        if echo.locked == true then
            out.reason = "cross-role"
            return Finish("cross-role")
        end
    end
    local fingerprint = OrdinaryFingerprint(normalized)
    local claimed = type(row.fingerprint) == "string"
        and row.fingerprint ~= "" and row.fingerprint or nil
    if not fingerprint then
        out.reason = "empty"
        return Finish("empty")
    end
    if claimed and claimed ~= fingerprint then
        out.reason = "fingerprint-mismatch"
        out.fingerprint = fingerprint
        return Finish("fingerprint-mismatch")
    end
    local count = 0
    for _, echo in ipairs(normalized) do
        count = count + (tonumber(echo.stacks) or 0)
    end
    out.complete=true
    out.reason="complete"
    out.echoes=DeepCopy(normalized)
    out.evidenceKey=exactOrWhy
    out.fingerprint=fingerprint
    out.echoCount=count
    return Finish("complete")
end

-- Public Community/Leaderboard consumers share one additional identity gate.
-- A stale raw build ID may remain usable only after exact recovery has supplied
-- a represented replacement identity; unresolved or record-level conflicts
-- never gain count, selection, Copy, or Open authority.
function Evidence.HasPublicOrdinaryConflict(row)
    return type(row) ~= "table"
        or row.recordIdentityMismatch == true
        or row.resolvedIdentityMismatch == true
        or (row.buildIdentityMismatch == true
            and row.resolvedBuildId == nil)
end

function Evidence.PublicOrdinaryCompleteness(row)
    if Evidence.HasPublicOrdinaryConflict(row) then
        return {
            complete=false,reason="identity-conflict",echoes=nil,
            evidenceKey=nil,fingerprint=nil,echoCount=0,
            lockedOnly=type(row) == "table"
                and (row.lockedEchoes ~= nil
                    or row.lockedEvidenceKey ~= nil) or false,
        }
    end
    return Evidence.OrdinaryCompleteness(row)
end

-- Historical protocol-v6 DPS summaries may identify a canonical ordinary
-- loadout as "@<djb2 hash>". The alias is compatibility metadata, never the
-- canonical identity itself. Keep its validation beside the ordinary-evidence
-- owner so every consumer uses the same normalization and hash rules.
function Evidence.CompatibilityHash(fingerprint)
    if type(fingerprint) ~= "string" or fingerprint == "" then return nil end
    local hash = 5381
    for index = 1, #fingerprint do
        hash = ((hash * 33) + fingerprint:byte(index)) % 2147483648
    end
    return string.format("%x", hash)
end

local function CanonicalOrdinaryFingerprint(row)
    if type(row) ~= "table" then return nil, "ordinary evidence unavailable" end
    local copy = DeepCopy(row)
    -- The canonical evidence must be evaluated independently of a persisted
    -- full fingerprint or legacy alias claim.
    copy.fingerprint = nil
    local verdict = Evidence.OrdinaryCompleteness(copy)
    if not (type(verdict) == "table" and verdict.complete == true
        and type(verdict.fingerprint) == "string"
        and verdict.fingerprint ~= "") then
        return nil, type(verdict) == "table" and verdict.reason
            or "ordinary evidence unavailable"
    end
    return verdict.fingerprint
end

local function SameTypedIdentity(left, right)
    return left ~= nil and right ~= nil and type(left) == type(right)
        and left == right
end

local function NormalizeCompatibilityHash(value)
    if value == nil then return nil end
    if type(value) ~= "string" and type(value) ~= "number" then return false end
    local normalized = tostring(value):lower()
    if normalized == "" or #normalized > 8
        or not normalized:match("^[0-9a-f]+$") then return false end
    return normalized
end

-- Validate one legacy DPS alias against an exact represented build. At least
-- the build's canonical ordinary evidence must be available; inline DPS
-- evidence, when present, is independently canonicalized and must agree.
-- Nothing is written back to either input table.
function Evidence.ValidateLegacyFingerprintClaim(record, represented)
    if type(record) ~= "table" or type(represented) ~= "table" then
        return nil, "legacy claim requires an exact represented build"
    end
    local claim = type(record.fingerprint) == "string"
        and record.fingerprint or nil
    local alias = claim and claim:match("^@([0-9A-Fa-f]+)$") or nil
    alias = NormalizeCompatibilityHash(alias)
    if not alias then return nil, "legacy fingerprint alias is invalid" end

    if not SameTypedIdentity(record.buildId, represented.id) then
        return nil, "legacy claim build ID does not match exact represented build"
    end
    if record.resolvedBuildId ~= nil
        and not SameTypedIdentity(record.resolvedBuildId, represented.id) then
        return nil, "legacy resolved build ID disagrees"
    end

    local buildFingerprint, buildReason =
        CanonicalOrdinaryFingerprint(represented)
    if not buildFingerprint then
        return nil, "represented build ordinary evidence is "
            .. tostring(buildReason or "unavailable")
    end
    local inlineFingerprint = nil
    if type(record.echoes) == "table" or record.evidenceKey ~= nil then
        local inlineReason
        inlineFingerprint, inlineReason = CanonicalOrdinaryFingerprint(record)
        if not inlineFingerprint then
            return nil, "legacy inline ordinary evidence is "
                .. tostring(inlineReason or "unavailable")
        end
        if inlineFingerprint ~= buildFingerprint then
            return nil, "legacy inline canonical fingerprint disagrees"
        end
    end

    local recomputed = Evidence.CompatibilityHash(buildFingerprint)
    if not recomputed or alias ~= recomputed then
        return nil, "legacy alias disagrees with canonical ordinary evidence"
    end

    local function RequireHash(label, value)
        if value == nil then return true end
        local normalized = NormalizeCompatibilityHash(value)
        if not normalized or normalized ~= recomputed then
            return nil, label .. " disagrees with canonical ordinary evidence"
        end
        return true
    end
    local ok, reason = RequireHash("legacy loadoutHash", record.loadoutHash)
    if not ok then return nil, reason end
    ok, reason = RequireHash("legacy fingerprintHash", record.fingerprintHash)
    if not ok then return nil, reason end
    ok, reason = RequireHash(
        "represented build fingerprintHash", represented.fingerprintHash)
    if not ok then return nil, reason end
    ok, reason = RequireHash(
        "represented build loadoutHash", represented.loadoutHash)
    if not ok then return nil, reason end

    local representedClaim = represented.fingerprint
    if representedClaim ~= nil then
        if type(representedClaim) ~= "string" or representedClaim == "" then
            return nil, "represented build fingerprint is invalid"
        end
        local representedAlias = representedClaim:match("^@([0-9A-Fa-f]+)$")
        if representedAlias then
            if NormalizeCompatibilityHash(representedAlias) ~= recomputed then
                return nil, "represented build alias disagrees"
            end
        elseif representedClaim ~= buildFingerprint then
            return nil, "represented build canonical fingerprint disagrees"
        end
    end

    return {
        buildId=represented.id,
        fingerprint=buildFingerprint,
        fingerprintHash=recomputed,
        inlineFingerprint=inlineFingerprint,
    }
end

function Evidence.ResolveBuildRow(row)
    if type(row) ~= "table" then return nil end
    local copy = DeepCopy(row)
    local verdict = Evidence.OrdinaryCompleteness(row)
    if verdict.complete then
        copy.echoes = type(row.echoes) == "table"
            and DeepCopy(row.echoes) or verdict.echoes
        copy.echoCount = verdict.echoCount
        copy.fingerprint = verdict.fingerprint
        copy.loadoutAvailable = true
        copy.needsFullBuild = false
    else
        copy.echoes = nil
        copy.echoCount = 0
        copy.loadoutAvailable = false
        copy.needsFullBuild = true
    end
    copy.ordinaryComplete = verdict.complete
    copy.ordinaryCompletenessReason = verdict.reason
    return copy
end

function Evidence.Conflicts()
    return DeepCopy(runtime.conflicts)
end

function Evidence.Snapshot()
    local entries = Store().entries
    return DeepCopy(type(entries) == "table" and entries or {})
end

function Evidence.RegisterReferenceProvider(name, provider)
    if type(name) ~= "string" or name == "" then return false end
    if provider == nil then
        referenceProviders[name] = nil
        referenceProviderGeneration = referenceProviderGeneration + 1
        return true
    end
    if type(provider) ~= "function" then return false end
    referenceProviders[name] = provider
    referenceProviderGeneration = referenceProviderGeneration + 1
    return true
end

-- Startup compaction never performs a destructive full-store garbage scan.
-- It still verifies that every transient reference owner can be queried before
-- stamping the migration complete, preserving the established retry/failure
-- boundary without traversing SavedVariables in one frame.
function Evidence.ReferenceProvidersHealthy()
    local generation = referenceProviderGeneration
    local failures = 0
    for _, provider in pairs(referenceProviders) do
        local ok = pcall(provider)
        if not ok then failures = failures + 1 end
    end
    return failures == 0, failures,
        generation == referenceProviderGeneration,referenceProviderGeneration
end

function Evidence.ReferenceProviderGeneration()
    return referenceProviderGeneration
end

local function AddReference(references, value)
    if type(value) == "string" and value ~= "" then
        references[value] = true
    end
end

local function ScanReferences(value, references, seen, poolEntries, providerMode)
    if type(value) == "string" then
        if providerMode then AddReference(references, value) end
        return
    end
    if type(value) ~= "table" or value == poolEntries then return end
    seen = seen or {}
    if seen[value] then return end
    seen[value] = true
    for key, child in pairs(value) do
        if key == "evidenceKey" or key == "lockedEvidenceKey" then
            AddReference(references, child)
        elseif providerMode and child == true and type(key) == "string"
            and poolEntries[key] ~= nil then
            AddReference(references, key)
        else
            ScanReferences(child, references, seen, poolEntries, providerMode)
        end
    end
end

-- Full scan first, deletion second. Providers protect transient retry owners
-- such as Sync's hot-build window that are not represented in SavedVariables.
function Evidence.ReferenceSnapshot(database)
    local store = Store()
    local entries = type(store.entries) == "table" and store.entries or {}
    local references = {}
    ScanReferences(type(database) == "table" and database or boundDb,
        references, {}, entries, false)
    local providerFailures = 0
    for _, provider in pairs(referenceProviders) do
        local ok, provided = pcall(provider)
        if ok then
            ScanReferences(provided, references, {}, entries, true)
        else
            providerFailures = providerFailures + 1
        end
    end
    return references, providerFailures
end

function Evidence.CollectGarbage(database, dryRun)
    local store = Store()
    if boundReadOnly or tonumber(store.schemaVersion)
        and tonumber(store.schemaVersion) > SCHEMA_VERSION then
        return {
            blocked=true, reason="future evidence schema is read-only",
            removed=0,
            retained=type(store.entries) == "table"
                and Count(store.entries) or 0,
            providerFailures=0,
        }
    end
    local entries = type(store.entries) == "table" and store.entries or {}
    local references, providerFailures = Evidence.ReferenceSnapshot(database)
    if providerFailures > 0 and dryRun ~= true then
        return {
            blocked=true, reason="runtime reference provider failed",
            removed=0, retained=Count(entries),
            references=Count(references), providerFailures=providerFailures,
        }
    end
    local unreachable = {}
    for key in pairs(entries) do
        if not references[key] then unreachable[#unreachable + 1] = key end
    end
    table.sort(unreachable)
    if dryRun ~= true then
        for _, key in ipairs(unreachable) do entries[key] = nil end
    end
    return {
        blocked=false,
        removed=dryRun == true and 0 or #unreachable,
        candidates=#unreachable,
        retained=Count(entries) - (dryRun == true and #unreachable or 0),
        references=Count(references),
        providerFailures=providerFailures,
        dryRun=dryRun == true,
        unreachable=DeepCopy(unreachable),
    }
end

function Evidence.Stats()
    local store = Store()
    local out = {
        schemaVersion=store.schemaVersion,
        entries=type(store.entries) == "table" and Count(store.entries) or 0,
        created=runtime.created, reused=runtime.reused,
        resolved=runtime.resolved, inlineFallbacks=runtime.inlineFallbacks,
        malformed=runtime.malformed, conflicts=#runtime.conflicts,
        completeness=DeepCopy(runtime.completeness),
    }
    return out
end

function Evidence.SchemaVersion()
    return SCHEMA_VERSION
end
