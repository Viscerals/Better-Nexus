-- Nexus: ordered, bounded conversion of pre-refactor account/DPS storage.
--
-- The live database is never used as scratch space.  Rows are normalized into
-- a durable staging area over small scheduler batches, then the four owned
-- tables are swapped together after validation.  An interrupted phase simply
-- replays into the same idempotent staging maps on the next login.
--
-- Once the authority bundle is occupied, the DPS data this build serves is the
-- bundle's dpsCapture payload and NexusDB.dpsCapture is preserved legacy input
-- (DpsCapture DB, DataCompaction and DataRetention DurablePayload). The
-- conversion then reads that payload and publishes its result through the
-- catalog's maintenance commit before its receipt says complete (Served below).

Nexus = Nexus or {}
local Identity = assert(Nexus.Identity,
    "Nexus Identity must load before LegacyDataMigration")
local Migration = {}
Nexus.LegacyDataMigration = Migration

local SCHEMA_VERSION = 1
local STORAGE_VERSION = 2
local LAST_KNOWN_LEGACY_SETTINGS_VERSION = 5
local SCHEDULER_KEY = "legacy-data-migration"
local BATCH_SIZE = 32
local QUARANTINE_LIMIT = 64
local PHASES = {
    "classHints", "accounts", "personal", "character", "leaderboard",
    "buildBest", "commit",
}
local VALID_PHASE = {}
for _, phase in ipairs(PHASES) do VALID_PHASE[phase] = true end

local active
-- F-S1-1, the served DPS payload. One file-level local holds this part; its
-- functions are defined after the converter helpers they use.
local Served = {
    RECOVERY_KEY = "legacy-data-migration-served",
    -- Seconds between two checks while the catalog cannot take a commit yet.
    WAIT = 0.2,
    -- Refused publications per database and session (each followed by a new
    -- pass) before the conversion or the recovery stops without a write.
    REFUSAL_LIMIT = 8,
    refusals = setmetatable({}, {__mode="k"}),
}
-- The bounded served-payload recovery of this session (memory only).
local recovery

-- Architecture 3b5de54f, docs/SYNC_TRUST_CATALOG_AUTHORITY_STATE_MACHINE.md
-- lines 2983-2985: "Exact PR #68 LegacyDataMigration.Init/Pump/Finish and its
-- writes in Store.lua are disabled before authority bootstrap." "The old
-- module cannot resume a durable cursor or write accountCharacters, DPS
-- tables, leaderboard, or migration metadata after Package B loads."
--
-- Package B therefore loads this module RETIRED. Its direct mutation entry
-- points do nothing and write nothing until AuthorityBootstrapCoordinatorV1
-- classifies the legacy recovery input and authorizes this exact database for
-- the bounded conversion. Terminal metadata already in the database stays an
-- exact read-only non-authoritative receipt; nothing here rewrites it, and
-- Status still reports it while retired.
local writerAuthority

local function WriterArmed(database)
    return writerAuthority ~= nil and database ~= nil
        and writerAuthority.database == database
end

local function RetiredResult()
    return {complete=true, pending=false, needed=false, readOnly=true,
        retired=true, reason="LEGACY_WRITER_RETIRED_V1"}
end

local runtime = {
    requested=0,coalesced=0,jobs=0,pumps=0,workUnits=0,maxWork=0,
    restarts=0,failures=0,completed=0,pending=false,lastReason="none",
    recoveries=0,recovered=0,publicationRefusals=0,
}

-- A present settings marker that is not a finite whole number of 0 or more
-- (6.5, -1, NaN, inf, any string including "5", a boolean, a table) is
-- malformed. Store keeps such data read-only; this converter agrees and never
-- coerces it with tonumber.
local function MalformedSettingsMarker(database)
    local raw = rawget(database, "settingsVersion")
    return raw ~= nil and not (type(raw) == "number" and raw == raw
        and raw >= 0 and raw < math.huge and raw == math.floor(raw))
end

local function Finite(value)
    value = tonumber(value)
    return value ~= nil and value == value
        and value < math.huge and value > -math.huge
end

local function Count(source)
    local total = 0
    for _ in pairs(type(source) == "table" and source or {}) do
        total = total + 1
    end
    return total
end

local function ShallowCopy(source)
    local out = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        out[key] = value
    end
    return out
end

local VALID_CLASS = {
    WARRIOR=true,PALADIN=true,HUNTER=true,ROGUE=true,PRIEST=true,
    DEATHKNIGHT=true,SHAMAN=true,MAGE=true,WARLOCK=true,DRUID=true,
}

local function NormalizedClass(value)
    value = type(value) == "string" and value:upper() or nil
    return value and VALID_CLASS[value] and value or nil
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, child in pairs(value) do
        out[DeepCopy(key, seen)] = DeepCopy(child, seen)
    end
    return out
end

local function CurrentDpsRevision()
    local revisions = Nexus and Nexus.Revisions
    return revisions and type(revisions.Get) == "function"
        and revisions.Get(revisions.DPS_CHANGED) or nil
end

local function CurrentOwnerKey()
    local store = Nexus and Nexus.Store
    if store and type(store.CurrentOwnerKey) == "function" then
        local ok, ownerKey = pcall(store.CurrentOwnerKey)
        ownerKey = ok and Identity.CanonicalOwnerKey(ownerKey) or nil
        if ownerKey and not ownerKey:match("@unknown$") then return ownerKey end
    end
    local name = UnitName and UnitName("player") or nil
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
    if not realm or realm == "" then realm = GetRealmName and GetRealmName() end
    local ownerKey = Identity.OwnerKey(name, realm)
    return ownerKey and not ownerKey:match("@unknown$") and ownerKey or nil
end

local function BetterRow(candidate, existing)
    if not existing then return true end
    local candidateDps = math.floor(tonumber(candidate and candidate.dps) or 0)
    local existingDps = math.floor(tonumber(existing and existing.dps) or 0)
    if candidateDps ~= existingDps then return candidateDps > existingDps end
    local candidateTime = tonumber(candidate and candidate.ts) or 0
    local existingTime = tonumber(existing and existing.ts) or 0
    if candidateTime > 0 and existingTime > 0
        and candidateTime ~= existingTime then
        return candidateTime < existingTime
    end
    return table.concat({
        tostring(candidate and candidate.fingerprint or ""),
        tostring(candidate and candidate.player or ""),
        tostring(candidate and candidate.buildId or candidate and candidate.b or ""),
    }, "\031") < table.concat({
        tostring(existing and existing.fingerprint or ""),
        tostring(existing and existing.player or ""),
        tostring(existing and existing.buildId or existing and existing.b or ""),
    }, "\031")
end

local function AddStat(meta, key, amount)
    meta.stats = type(meta.stats) == "table" and meta.stats or {}
    meta.stats[key] = (tonumber(meta.stats[key]) or 0) + (amount or 1)
end

local function Quarantine(meta, kind, key, reason)
    AddStat(meta, "quarantined", 1)
    meta.quarantine = type(meta.quarantine) == "table" and meta.quarantine or {}
    local rows = type(meta.quarantine.rows) == "table"
        and meta.quarantine.rows or {}
    meta.quarantine.rows = rows
    if #rows < QUARANTINE_LIMIT then
        rows[#rows + 1] = {
            kind=tostring(kind or "unknown"),
            key=tostring(key or ""),
            reason=tostring(reason or "invalid row"),
        }
    else
        AddStat(meta, "quarantineDetailsDropped", 1)
    end
end

local function Meta(database, create)
    local existing = rawget(database, "legacyDataMigration")
    if existing ~= nil and type(existing) ~= "table" then
        return nil, "legacy migration namespace has an incompatible owner"
    end
    if type(existing) == "table" then
        local schema = tonumber(existing.schemaVersion) or 0
        local version = tonumber(existing.version) or 0
        if schema > SCHEMA_VERSION or version > STORAGE_VERSION then
            return nil, "future legacy migration schema is read-only"
        end
        return existing
    end
    if not create then return nil end
    local meta = {schemaVersion=SCHEMA_VERSION,version=0,state="staging"}
    database.legacyDataMigration = meta
    return meta
end

local function DpsStore(database)
    return type(database.dpsCapture) == "table" and database.dpsCapture or nil
end

local function CharacterKey(row, sourceKey)
    if type(row) ~= "table" then return nil end
    local player = Identity.DisplayPlayer(row.player)
    local sourceOwner = Identity.CanonicalOwnerKey(sourceKey)
    if not player and sourceOwner then
        player = sourceOwner:match("^([^@]+)@")
    end
    if not player then player = Identity.DisplayPlayer(sourceKey) end
    if not player then return nil end

    local ownerKey = Identity.CanonicalOwnerKey(row.ownerKey)
    if ownerKey and not Identity.OwnerKeyMatchesAuthor(ownerKey, player) then
        ownerKey = nil
    end
    if not ownerKey and type(row.realm) == "string" then
        ownerKey = Identity.OwnerKey(player, row.realm)
    end
    if not ownerKey and sourceOwner
        and Identity.OwnerKeyMatchesAuthor(sourceOwner, player) then
        ownerKey = sourceOwner
    end
    if ownerKey and ownerKey:match("@unknown$") then ownerKey = nil end
    return ownerKey or Identity.PlayerKey(player), player, ownerKey
end

local function NormalizeDpsRow(meta, row, fingerprint, sourceKey, kind)
    if type(row) ~= "table" or not Finite(row.dps)
        or tonumber(row.dps) <= 0 then
        Quarantine(meta, kind, sourceKey, "non-positive or malformed DPS")
        return nil
    end
    local key, player, ownerKey = CharacterKey(row, sourceKey)
    if not key or not player then
        Quarantine(meta, kind, sourceKey, "invalid player identity")
        return nil
    end
    local out = ShallowCopy(row)
    out.player = player
    if not NormalizedClass(out.class) then
        local hint = type(meta.staging) == "table"
            and type(meta.staging.classHints) == "table"
            and meta.staging.classHints[Identity.PlayerKey(player)] or nil
        if type(hint) == "table" and hint.conflict ~= true
            and NormalizedClass(hint.class) then
            out.class = NormalizedClass(hint.class)
            out.legacyClassInferred = true
            out.legacyClassSource = "migration-author-consensus"
            AddStat(meta, "legacyClassesInferred", 1)
        end
    end
    if type(out.fingerprint) ~= "string" or out.fingerprint == "" then
        out.fingerprint = type(fingerprint) == "string" and fingerprint ~= ""
            and fingerprint or nil
    end
    if ownerKey then
        out.ownerKey = ownerKey
        out.realm = ownerKey:match("@(.+)$")
    elseif out.ownerKey ~= nil or out.ownerVerified == true then
        -- Invalid or unverifiable legacy ownership must never become edit,
        -- delete, or relay authority merely because its row was retained.
        out.ownerKey, out.ownerVerified = nil, nil
        AddStat(meta, "ownershipClaimsRejected", 1)
    end
    return out, key
end

local function PutCharacter(staging, category, key, row)
    local bucket = staging.characterBest[category]
    if BetterRow(row, bucket[key]) then bucket[key] = row; return true end
    return false
end

local function PutPersonal(staging, category, row)
    local fingerprint = type(row) == "table" and row.fingerprint or nil
    if type(fingerprint) ~= "string" or fingerprint == "" then return false end
    local categories = staging.personalBest[fingerprint]
    if type(categories) ~= "table" then
        categories = {}; staging.personalBest[fingerprint] = categories
    end
    if BetterRow(row, categories[category]) then
        categories[category] = row
        return true
    end
    return false
end

-- The canonical owner of a row that claims verified ownership, else nil. The
-- converter promotes such a row as a personal best when that owner is the
-- character logged in (IsLocalRow); the served-payload recovery, which cannot
-- know who that was, applies the same test without the login.
local function VerifiedOwner(row)
    local owner = type(row) == "table"
        and Identity.CanonicalOwnerKey(row.ownerKey) or nil
    return owner ~= nil and row.ownerVerified == true and owner or nil
end

local function IsLocalRow(row)
    local current = CurrentOwnerKey()
    local owner = VerifiedOwner(row)
    return current ~= nil and owner ~= nil and current == owner
end

local function MergeAccount(target, incoming)
    if not target then return ShallowCopy(incoming) end
    for key, value in pairs(incoming) do
        if target[key] == nil then target[key] = value end
    end
    return target
end

local function AccountName(sourceKey, source, declaredOwner, indexedOwner)
    local name = Identity.DisplayPlayer(source.name)
    if not name and declaredOwner then name = declaredOwner:match("^([^@]+)@") end
    if not name and indexedOwner then name = indexedOwner:match("^([^@]+)@") end
    if not name then name = Identity.DisplayPlayer(sourceKey) end
    return name
end

local function AccountEvidenceMatches(ownerKey, source, name)
    if not ownerKey or ownerKey:match("@unknown$") or not name
        or not Identity.OwnerKeyMatchesAuthor(ownerKey, name) then return false end

    if source.ownerKey ~= nil then
        local declared = Identity.CanonicalOwnerKey(source.ownerKey)
        if not declared or declared:match("@unknown$")
            or declared ~= ownerKey then return false end
    end
    if source.name ~= nil then
        if type(source.name) ~= "string"
            or not Identity.OwnerKeyMatchesAuthor(ownerKey, source.name) then
            return false
        end
        if source.name:find("-", 1, true)
            and Identity.CanonicalOwnerFromTransport(source.name) ~= ownerKey then
            return false
        end
    end
    if source.realm ~= nil then
        if type(source.realm) ~= "string" then return false end
        local realm = source.realm:lower()
        if realm ~= "" and realm ~= "unknown"
            and Identity.CanonicalOwnerKey(Identity.OwnerKey(name, source.realm))
                ~= ownerKey then return false end
    end
    return true
end

local function ProvenAccountOwner(sourceKey, source)
    if type(source) ~= "table" then return nil end
    local declaredOwner = Identity.CanonicalOwnerKey(source.ownerKey)
    local indexedOwner = Identity.CanonicalOwnerKey(sourceKey)
    local name = AccountName(sourceKey, source, declaredOwner, indexedOwner)
    local indexedExact = indexedOwner and not indexedOwner:match("@unknown$")
    local declaredExact = declaredOwner and not declaredOwner:match("@unknown$")

    if indexedExact and sourceKey == indexedOwner
        and (not declaredExact or declaredOwner == indexedOwner)
        and AccountEvidenceMatches(indexedOwner, source, name) then
        return indexedOwner, "canonical", name
    end
    if declaredExact and not indexedExact
        and AccountEvidenceMatches(declaredOwner, source, name) then
        return declaredOwner, "bridge", name
    end
    return nil, nil, name
end

local function AmbiguousAccountKey(sourceKey)
    local indexedOwner = Identity.CanonicalOwnerKey(sourceKey)
    if indexedOwner and indexedOwner:match("@unknown$")
        and sourceKey == indexedOwner then return indexedOwner end
    if type(sourceKey) == "string" then
        return "legacy:string:" .. tostring(#sourceKey) .. ":" .. sourceKey
    end
    if type(sourceKey) == "number" and Finite(sourceKey) then
        return "legacy:number:" .. string.format("%.17g", sourceKey)
    end
    if type(sourceKey) == "boolean" then
        return "legacy:boolean:" .. tostring(sourceKey)
    end
    return nil
end

local function NormalizeAccount(job, sourceKey, source)
    local meta = job.meta
    if type(source) ~= "table" then
        Quarantine(meta, "account", sourceKey, "malformed account row")
        return nil
    end
    local ownerKey, proof, name = ProvenAccountOwner(sourceKey, source)
    if proof == "bridge" and (job.canonicalAccountOwners[ownerKey]
        or (job.accountBridgeCounts[ownerKey] or 0) ~= 1) then
        ownerKey, proof = nil, nil
    end

    if ownerKey then
        local out = ShallowCopy(source)
        out.ownerKey = nil -- the canonical map key is the sole identity index
        out.name = source.name or name
        out.realm = ownerKey:match("@(.+)$")
        return ownerKey, out
    end

    -- Realm-less, @unknown, or contradictory account evidence remains in the
    -- staged map under a non-authoritative key. Login identity is deliberately
    -- absent from this decision, so restart and login order cannot claim it.
    local ambiguousKey = AmbiguousAccountKey(sourceKey)
    if not ambiguousKey or not name then
        Quarantine(meta, "account", sourceKey, "unresolved account identity")
        return nil
    end

    local out = ShallowCopy(source)
    out.name = source.name or name
    AddStat(meta, "accountRowsPreservedAmbiguous", 1)
    return ambiguousKey, out
end

local function NeedsMigration(database)
    local settingsVersion = tonumber(database.settingsVersion) or 0
    if settingsVersion > 2 then return true end
    local dps = DpsStore(database)
    if type(dps) == "table" and type(dps.leaderboard) == "table"
        and next(dps.leaderboard) ~= nil then return true end
    -- Main v1.19.5 is stamped to settings schema 2 before this owner runs. Its
    -- public rows commonly lack class/realm evidence, so route only databases
    -- with actual classless legacy rows through the one-time staged converter.
    local character = type(dps) == "table" and dps.characterBest or nil
    for _, category in ipairs({"dummy", "lk"}) do
        for _, row in pairs(type(character) == "table"
            and type(character[category]) == "table"
            and character[category] or {}) do
            if type(row) == "table" and not NormalizedClass(row.class) then
                return true
            end
        end
    end
    return false
end

local function NewStaging()
    return {
        accountCharacters={}, personalBest={}, buildBest={},
        characterBest={dummy={},lk={}}, classHints={},
    }
end

local function ValidStaging(staging)
    return type(staging) == "table"
        and type(staging.accountCharacters) == "table"
        and type(staging.personalBest) == "table"
        and type(staging.buildBest) == "table"
        and type(staging.characterBest) == "table"
        and type(staging.characterBest.dummy) == "table"
        and type(staging.characterBest.lk) == "table"
        and type(staging.classHints) == "table"
end

local function Begin(database, meta, reason, restarting)
    -- After bundle occupancy the converter reads the served payload; the
    -- legacy location is preserved input and is neither created nor written.
    local served = Served.Payload(database)
    local dps = served or DpsStore(database)
    if not dps then
        database.dpsCapture = {}
        dps = database.dpsCapture
    end
    -- A served payload can be published again between two sessions (a
    -- received record, compaction, retention), so its staging is never
    -- resumed: a reload rebuilds it from the payload as it is then.
    local canResume = not restarting and not served and meta.state == "staging"
        and ValidStaging(meta.staging) and VALID_PHASE[meta.phase]
    if canResume then
        -- A reload has no trustworthy Lua cursor. Replaying only the durable
        -- current phase is safe because every staging write is a max/merge.
    else
        meta.staging = NewStaging()
        meta.phase = "classHints"
        meta.stats = {}
        meta.quarantine = nil
    end
    meta.schemaVersion = SCHEMA_VERSION
    meta.version = 0
    meta.state = "staging"
    meta.inProgress = true
    meta.reason = tostring(reason or "startup")
    meta.sourceSettingsVersion = tonumber(database.settingsVersion) or 0
    meta.workUnits = tonumber(meta.workUnits) or 0
    runtime.jobs = runtime.jobs + 1
    runtime.pending = true
    return {
        database=database,meta=meta,dps=dps,phase=meta.phase,
        -- `retained` (served conversions only, memory): what the converter
        -- refuses, kept for the served payload (Served.Converted).
        served=served ~= nil,retained=served and Served.NewRetained() or nil,
        items=nil,index=1,dpsRevision=CurrentDpsRevision(),
        canonicalAccountOwners={},accountBridgeCounts={},
        source={
            accountCharacters=database.accountCharacters,
            communityBuilds=database.communityBuilds,
            bundledBuilds=type(Nexus.BundledBuilds) == "table"
                and Nexus.BundledBuilds.builds or nil,
            personalBest=dps.personalBest,
            characterBest=dps.characterBest,
            leaderboard=dps.leaderboard,
            buildBest=dps.buildBest,
        },
    }
end

local function SnapshotAccounts(job)
    local out = {}
    for key, row in pairs(type(job.source.accountCharacters) == "table"
        and job.source.accountCharacters or {}) do
        out[#out + 1] = {key=key,row=row}
        local ownerKey, proof = ProvenAccountOwner(key, row)
        if proof == "canonical" then
            job.canonicalAccountOwners[ownerKey] = true
        elseif proof == "bridge" then
            job.accountBridgeCounts[ownerKey] =
                (job.accountBridgeCounts[ownerKey] or 0) + 1
        end
    end
    table.sort(out, function(left, right)
        return type(left.key) .. ":" .. tostring(left.key)
            < type(right.key) .. ":" .. tostring(right.key)
    end)
    return out
end

local function SnapshotMap(source)
    local out = {}
    for key, row in pairs(type(source) == "table" and source or {}) do
        out[#out + 1] = {key=key,row=row}
    end
    table.sort(out, function(left, right)
        return type(left.key) .. ":" .. tostring(left.key)
            < type(right.key) .. ":" .. tostring(right.key)
    end)
    return out
end

local function SnapshotClassHints(job)
    local selected = {}
    local function Merge(source)
        for _, item in ipairs(SnapshotMap(source)) do
            selected[type(item.key) .. ":" .. tostring(item.key)] = item
        end
    end
    -- Match BuildCatalog precedence: an exact typed overlay ID replaces its
    -- immutable bundled predecessor instead of becoming conflicting evidence.
    Merge(job.source.bundledBuilds)
    Merge(job.source.communityBuilds)
    local out = {}
    for _, item in pairs(selected) do out[#out + 1] = item end
    table.sort(out, function(left, right)
        return type(left.key) .. ":" .. tostring(left.key)
            < type(right.key) .. ":" .. tostring(right.key)
    end)
    return out
end

local function SnapshotCharacter(job)
    local out = {}
    local source = type(job.source.characterBest) == "table"
        and job.source.characterBest or {}
    for _, category in ipairs({"dummy", "lk"}) do
        for key, row in pairs(type(source[category]) == "table"
            and source[category] or {}) do
            out[#out + 1] = {category=category,key=key,row=row}
        end
    end
    table.sort(out, function(left, right)
        local leftKey = left.category .. "|" .. type(left.key)
            .. ":" .. tostring(left.key)
        local rightKey = right.category .. "|" .. type(right.key)
            .. ":" .. tostring(right.key)
        return leftKey < rightKey
    end)
    return out
end

local function SnapshotLeaderboard(job)
    local out = {}
    for fingerprint, categories in pairs(type(job.source.leaderboard) == "table"
        and job.source.leaderboard or {}) do
        if type(categories) == "table" then
            for _, category in ipairs({"dummy", "lk"}) do
                for key, row in pairs(type(categories[category]) == "table"
                    and categories[category] or {}) do
                    out[#out + 1] = {fingerprint=fingerprint,
                        category=category,key=key,row=row}
                end
            end
        end
    end
    table.sort(out, function(left, right)
        local leftKey = type(left.fingerprint) .. ":"
            .. tostring(left.fingerprint) .. "|" .. left.category .. "|"
            .. type(left.key) .. ":" .. tostring(left.key)
        local rightKey = type(right.fingerprint) .. ":"
            .. tostring(right.fingerprint) .. "|" .. right.category .. "|"
            .. type(right.key) .. ":" .. tostring(right.key)
        return leftKey < rightKey
    end)
    -- A served conversion keeps what it cannot convert (Served.KeepItems).
    if job.served then Served.KeepItems(job.source.leaderboard, out) end
    return out
end

local function ItemsFor(job)
    if job.phase == "classHints" then return SnapshotClassHints(job) end
    if job.phase == "accounts" then return SnapshotAccounts(job) end
    if job.phase == "personal" then return SnapshotMap(job.source.personalBest) end
    if job.phase == "character" then return SnapshotCharacter(job) end
    if job.phase == "leaderboard" then return SnapshotLeaderboard(job) end
    if job.phase == "buildBest" then return SnapshotMap(job.source.buildBest) end
    return {}
end

local function ProcessClassHint(job, item)
    local build = item.row
    local author = type(build) == "table"
        and Identity.PlayerKey(build.author) or nil
    local class = type(build) == "table"
        and NormalizedClass(build.class) or nil
    if not author or not class then return end
    local hints = job.meta.staging.classHints
    local hint = hints[author]
    if not hint then
        hints[author] = {class=class}
    elseif hint.class ~= class then
        hint.class = nil
        hint.conflict = true
    end
end

local function AdvancePhase(job)
    local nextPhase = "commit"
    for index, phase in ipairs(PHASES) do
        if phase == job.phase then nextPhase = PHASES[index + 1] or "commit"; break end
    end
    job.phase, job.meta.phase = nextPhase, nextPhase
    job.items, job.index = nil, 1
end

local function ProcessPersonal(job, item)
    if type(item.row) == "table" then
        -- Preserve unknown category fields while isolating the staging owner
        -- from later writes to the legacy outer map.
        job.meta.staging.personalBest[item.key] = ShallowCopy(item.row)
        AddStat(job.meta, "personalFingerprintsCopied", 1)
    else
        Quarantine(job.meta, "personal", item.key, "malformed category map")
        if job.retained then job.retained.personalBest[item.key] = item.row end
    end
end

local function ProcessCharacter(job, item)
    local row, key = NormalizeDpsRow(job.meta, item.row,
        type(item.row) == "table" and item.row.fingerprint or nil,
        item.key, "characterBest")
    if not row then
        if job.retained then
            job.retained.characterBest[item.category][item.key] = item.row
        end
        return
    end
    if PutCharacter(job.meta.staging, item.category, key, row) then
        AddStat(job.meta, "characterRowsCopied", 1)
    end
end

local function ProcessLeaderboard(job, item)
    if item.keep then
        if job.retained then
            Served.KeepLegacy(job.retained.leaderboard, item.fingerprint,
                item.category, nil, item.row)
        end
        return
    end
    local row, key = NormalizeDpsRow(job.meta, item.row,
        item.fingerprint, item.key, "leaderboard")
    if not row then
        if job.retained then
            Served.KeepLegacy(job.retained.leaderboard, item.fingerprint,
                item.category, item.key, item.row)
        end
        return
    end
    if PutCharacter(job.meta.staging, item.category, key, row) then
        AddStat(job.meta, "legacyRowsPromoted", 1)
    end
    if IsLocalRow(row) and PutPersonal(job.meta.staging, item.category, row) then
        AddStat(job.meta, "personalRowsPromoted", 1)
    end
end

local function ProcessBuildBest(job, item)
    if type(item.row) ~= "table" then
        Quarantine(job.meta, "buildBest", item.key, "malformed category map")
        if job.retained then job.retained.buildBest[item.key] = item.row end
        return
    end
    job.meta.staging.buildBest[item.key] = ShallowCopy(item.row)
    AddStat(job.meta, "buildFingerprintsCopied", 1)
    for _, category in ipairs({"dummy", "lk"}) do
        if type(item.row[category]) == "table" then
            local row, key = NormalizeDpsRow(job.meta, item.row[category],
                item.key, nil, "buildBest")
            if row and PutCharacter(job.meta.staging, category, key, row) then
                AddStat(job.meta, "buildRowsPromoted", 1)
            end
        end
    end
end

local function Process(job, item)
    if job.phase == "classHints" then
        ProcessClassHint(job, item)
    elseif job.phase == "accounts" then
        local key, row = NormalizeAccount(job, item.key, item.row)
        if key then
            local staging = job.meta.staging.accountCharacters
            staging[key] = MergeAccount(staging[key], row)
            AddStat(job.meta, "accountRowsCopied", 1)
        end
    elseif job.phase == "personal" then ProcessPersonal(job, item)
    elseif job.phase == "character" then ProcessCharacter(job, item)
    elseif job.phase == "leaderboard" then ProcessLeaderboard(job, item)
    elseif job.phase == "buildBest" then ProcessBuildBest(job, item) end
end

local function SourceChanged(job)
    if job.dpsRevision ~= CurrentDpsRevision() then return true end
    local dps
    if job.served then
        -- Every catalog publication carries the payload forward as a new
        -- top-level table over the same maps, so the maps are the signal here.
        dps = Served.Payload(job.database)
        if not dps then return true end
    else
        dps = DpsStore(job.database)
        if dps ~= job.dps then return true end
    end
    -- Store registration is refused while this transaction is active. Account
    -- normalization shallow-copies only the row shell and never mutates nested
    -- unknown values, so exact table replacement is the bounded ownership
    -- signal; recursively walking the whole SavedVariables graph here would
    -- escape the Pump budget and can never be made safe for arbitrary graphs.
    return job.source.accountCharacters ~= job.database.accountCharacters
        or job.source.communityBuilds ~= job.database.communityBuilds
        or job.source.personalBest ~= dps.personalBest
        or job.source.characterBest ~= dps.characterBest
        or job.source.leaderboard ~= dps.leaderboard
        or job.source.buildBest ~= dps.buildBest
end

------------------------------------------------------------------------
-- F-S1-1: the served DPS payload.
--
-- The conversion's result reaches the served payload only through the
-- catalog's maintenance commit (BuildCatalog.CommitMaintenance with a
-- dpsCapture override), the one authorized writer of the authority bundle. It
-- is never written into the payload in place, and no table is shared between
-- the payload and the legacy location. Its publication guard refuses the
-- commit unless the live payload is still exactly the one the result was
-- prepared from, so a record accepted meanwhile, a compaction or another
-- publication is never overwritten. Publication is verified from the
-- catalog's own commit, never from a marker.
------------------------------------------------------------------------

-- The occupied bundle's DPS payload, or nil: no bundle, or a bundle without a
-- table payload, which keeps the earlier behaviour on the legacy location.
function Served.Payload(database)
    local bundle = type(database) == "table"
        and rawget(database, "authorityBundle") or nil
    local payload = type(bundle) == "table" and rawget(bundle, "dpsCapture") or nil
    return type(payload) == "table" and payload or nil
end

-- Saved data the Store keeps read-only, and a settings format this converter
-- leaves untouched, are never written (Store never starts it for them either).
function Served.Writable(database)
    if MalformedSettingsMarker(database)
        or (tonumber(rawget(database, "settingsVersion")) or 0)
            > LAST_KNOWN_LEGACY_SETTINGS_VERSION then
        return false
    end
    local internals = Nexus and Nexus.MainInternals
    local verdict = type(internals) == "table"
        and internals.SavedRootReadOnlyV1 or nil
    if type(verdict) ~= "function" then return true end
    local ok, class = pcall(verdict, database)
    return ok and class == nil
end

function Served.NewRetained()
    return {personalBest={}, buildBest={}, characterBest={dummy={},lk={}},
        leaderboard={}}
end

-- One kept part of an older leaderboard map (fingerprint -> category ->
-- player), at its own place: the whole entry, one category value, or one row.
function Served.KeepLegacy(leaderboard, fingerprint, category, key, value)
    if category == nil then leaderboard[fingerprint] = value; return end
    local entry = leaderboard[fingerprint]
    if type(entry) ~= "table" then entry = {}; leaderboard[fingerprint] = entry end
    if key == nil then entry[category] = value; return end
    local rows = entry[category]
    if type(rows) ~= "table" then rows = {}; entry[category] = rows end
    rows[key] = value
end

-- The parts of an older leaderboard map that are not dummy/lk rows of a table
-- entry: an entry or a category value that is not a table, and any other
-- category. They are kept as they are, never converted.
function Served.KeepItems(leaderboard, out)
    for fingerprint, categories in pairs(type(leaderboard) == "table"
        and leaderboard or {}) do
        if type(categories) ~= "table" then
            out[#out + 1] = {keep=true, fingerprint=fingerprint, row=categories}
        else
            for category, rows in pairs(categories) do
                if type(rows) ~= "table"
                    or (category ~= "dummy" and category ~= "lk") then
                    out[#out + 1] = {keep=true, fingerprint=fingerprint,
                        category=category, row=rows}
                end
            end
        end
    end
    return out
end

-- The live top level as a shallow copy and its key count, for the guard.
function Served.TopLevel(source)
    local out, count = {}, 0
    for key, value in pairs(source) do out[key] = value; count = count + 1 end
    return out, count
end

function Served.SameTopLevel(source, top, count)
    local seen = 0
    for key, value in pairs(source) do
        if top[key] ~= value then return false end
        seen = seen + 1
    end
    return seen == count
end

-- A conversion's replacement payload: the live top level as it is (unknown
-- keys included), the three maps the converter owns replaced by its result,
-- categories it does not know carried over, what it refused kept at its own
-- key, and the older map reduced to what it could not convert.
function Served.Converted(staging, retained, top)
    for key, value in pairs(retained.personalBest) do
        if staging.personalBest[key] == nil then staging.personalBest[key] = value end
    end
    for key, value in pairs(retained.buildBest) do
        if staging.buildBest[key] == nil then staging.buildBest[key] = value end
    end
    local character = staging.characterBest
    for _, category in ipairs({"dummy", "lk"}) do
        local bucket = character[category]
        for key, value in pairs(retained.characterBest[category]) do
            if bucket[key] == nil then bucket[key] = value end
        end
    end
    if type(top.characterBest) == "table" then
        for key, value in pairs(top.characterBest) do
            if character[key] == nil then character[key] = value end
        end
    end
    local out = ShallowCopy(top)
    out.personalBest, out.buildBest = staging.personalBest, staging.buildBest
    out.characterBest = character
    out.leaderboard = next(retained.leaderboard) ~= nil
        and retained.leaderboard or nil
    return out
end

-- An open maintenance transaction of the catalog bound to this database, or
-- nil while it cannot take one (bootstrap seal, another candidate or walk,
-- rebind): the caller checks again later.
function Served.Maintenance(database)
    local catalog = Nexus and Nexus.BuildCatalog
    if not (catalog and type(catalog.BoundDatabase) == "function"
        and catalog.BoundDatabase() == database
        and type(catalog.BeginCatalogMaintenance) == "function"
        and type(catalog.CommitMaintenance) == "function") then
        return nil
    end
    local handle = catalog.BeginCatalogMaintenance({database=database,
        operation="legacy-data-migration"})
    if type(handle) ~= "table" then return nil end
    return catalog, handle
end

-- One publication of `payload` as the served DPS payload. Returns true
-- (committed and served now), nil and the catalog's pending ticket, or false
-- and the catalog's refusal.
function Served.Commit(catalog, handle, database, live, top, count, payload)
    local revision = CurrentDpsRevision()
    local committed, why, ticket = catalog.CommitMaintenance(handle,
        {dpsCapture=payload}, function()
            return CurrentDpsRevision() == revision
                and Served.Payload(database) == live
                and Served.SameTopLevel(live, top, count)
        end)
    if committed == true then
        if Served.Payload(database) == payload then return true end
        return false, "PUBLICATION_NOT_SERVED"
    end
    if committed == nil and why == "ROOT_MUTATION_PENDING"
        and type(ticket) == "table" then
        return nil, ticket
    end
    if type(catalog.CancelMaintenance) == "function" then
        catalog.CancelMaintenance(handle)
    end
    return false, why or "PUBLICATION_FAILED"
end

-- A pending publication is verified from the catalog's own settled ticket:
-- the bundle it committed for this database holds exactly this payload.
function Served.Committed(database, ticket, payload)
    local bundle = ticket.bundle
    return ticket.state == "committed" and ticket.committed == true
        and ticket.database == database and type(bundle) == "table"
        and rawget(bundle, "dpsCapture") == payload
end

function Served.Refused(job, why)
    local count = (Served.refusals[job.database] or 0) + 1
    Served.refusals[job.database] = count
    runtime.publicationRefusals = runtime.publicationRefusals + 1
    return false, "publication refused: " .. tostring(why),
        count >= Served.REFUSAL_LIMIT
end

-- The publication step of a served conversion. Returns true once its payload
-- is served, nil while it waits for the catalog, or false, why and whether to
-- stop (else the conversion starts a new pass from the current payload).
function Served.Publish(job)
    local database = job.database
    local ticket = job.ticket
    if ticket then
        if ticket.state == "pending" then job.waiting = true; return nil end
        job.ticket, job.waiting = nil, nil
        if Served.Committed(database, ticket, job.published) then return true end
        return Served.Refused(job, ticket.reason or "PUBLICATION_FAILED")
    end
    if SourceChanged(job) then return false, "source-changed" end
    if not Served.Writable(database) then
        return false, "read-only saved data", true
    end
    local staging = job.staging or job.meta.staging
    if not ValidStaging(staging) or type(job.retained) ~= "table" then
        return false, "invalid staging owner"
    end
    local catalog, handle = Served.Maintenance(database)
    if not handle then job.waiting = true; return nil end
    job.waiting = nil
    -- The receipt keeps no reference to the maps that become the payload; an
    -- unfinished receipt without staging starts a new pass on the next login.
    job.staging, job.meta.staging = staging, nil
    local live = Served.Payload(database)
    local top, count = Served.TopLevel(live)
    local payload = Served.Converted(staging, job.retained, top)
    local committed, detail = Served.Commit(catalog, handle, database,
        live, top, count, payload)
    if committed == nil then
        job.ticket, job.published, job.waiting = detail, payload, true
        return nil
    end
    if committed then return true end
    return Served.Refused(job, detail)
end

-- A conversion whose publication keeps being refused stops for this session
-- without a write; its receipt stays unfinished and the next login starts over.
function Served.Stop(job, why)
    if active == job then active = nil end
    runtime.pending = false
    runtime.failures = runtime.failures + 1
    runtime.lastReason = tostring(why or "publication refused")
end

local function Finish(job)
    local staging
    if job.served then
        -- The receipt says complete only once the served payload holds this
        -- conversion.
        local published, why, stop = Served.Publish(job)
        if published ~= true then return published, why, stop end
        staging = job.staging
        if job.source.accountCharacters ~= job.database.accountCharacters then
            return false, "source-changed"
        end
    else
        if SourceChanged(job) then return false, "source-changed" end
        staging = job.meta.staging
    end
    if not ValidStaging(staging) then return false, "invalid staging owner" end
    local database, dps, meta = job.database, job.dps, job.meta
    meta.state, meta.phase = "committing", "commit"

    -- These assignments are the transaction boundary.  The old tables remain
    -- untouched until every replacement has been constructed and validated.
    -- A served conversion's DPS maps were published above; the legacy
    -- location keeps its preserved input.
    database.accountCharacters = staging.accountCharacters
    if not job.served then
        dps.personalBest = staging.personalBest
        dps.buildBest = staging.buildBest
        dps.characterBest = staging.characterBest
        dps.leaderboard = nil
    end

    meta.version = STORAGE_VERSION
    meta.state = "complete"
    meta.inProgress = nil
    meta.phase = nil
    meta.completedAt = type(time) == "function" and time() or 0
    meta.lastResult = {
        schemaVersion=SCHEMA_VERSION,version=STORAGE_VERSION,
        accountCharacters=Count(staging.accountCharacters),
        personalFingerprints=Count(staging.personalBest),
        buildFingerprints=Count(staging.buildBest),
        dummyCharacters=Count(staging.characterBest.dummy),
        lkCharacters=Count(staging.characterBest.lk),
        quarantined=tonumber(meta.stats and meta.stats.quarantined) or 0,
    }
    meta.staging = nil
    runtime.pending = false
    runtime.completed = runtime.completed + 1
    runtime.lastReason = "complete"

    local revisions = Nexus and Nexus.Revisions
    if revisions and type(revisions.Advance) == "function" then
        pcall(revisions.Advance, revisions.DPS_CHANGED,
            {scope="all",reason="legacy data migration committed"})
    end
    local compaction = Nexus and Nexus.DataCompaction
    if compaction and type(compaction.Init) == "function" then
        pcall(compaction.Init, database)
    end
    local retention = Nexus and Nexus.DataRetention
    if retention and type(retention.Request) == "function" then
        pcall(retention.Request, "legacy data migration committed")
    end
    local refresh = Nexus and Nexus.ViewRefresh
    if refresh and type(refresh.Request) == "function" then
        -- ViewRefresh requests the repair on each refresh and coalesces the UI
        -- work. Avoid a duplicate direct repair request here.
        pcall(refresh.Request)
    else
        local repair = Nexus and Nexus.LegacyQualificationRepair
        if repair and type(repair.Request) == "function" then
            pcall(repair.Request, "legacy data migration committed")
        end
    end
    return true
end

local function Restart(job, reason)
    runtime.restarts = runtime.restarts + 1
    runtime.lastReason = tostring(reason or "restart")
    job.meta.staging = nil
    job.meta.phase = nil
    active = Begin(job.database, job.meta, reason or "restart", true)
end

function Migration.Pump(limit)
    if not active then return true end
    -- A retired writer can never resume a durable cursor.
    if not WriterArmed(active.database) then return true end
    limit = math.max(1, math.min(math.floor(tonumber(limit) or BATCH_SIZE),
        BATCH_SIZE))
    runtime.pumps = runtime.pumps + 1
    local work = 0
    while active and work < limit do
        if active.phase == "commit" then
            local job = active
            local ok, why, stop = Finish(job)
            if ok then
                active = nil
            elseif ok == false then
                if stop then Served.Stop(job, why) else Restart(job, why) end
            end
            -- nil: the served publication is not committed yet; the job waits.
            break
        end
        if not active.items then active.items = ItemsFor(active) end
        local item = active.items[active.index]
        if item then
            Process(active, item)
            active.index = active.index + 1
            work = work + 1
            active.meta.workUnits = (tonumber(active.meta.workUnits) or 0) + 1
        else
            AdvancePhase(active)
        end
    end
    runtime.workUnits = runtime.workUnits + work
    runtime.maxWork = math.max(runtime.maxWork, work)
    return active == nil
end

local function ScheduledPump()
    local ok, done = pcall(Migration.Pump, BATCH_SIZE)
    if not ok then
        runtime.failures = runtime.failures + 1
        runtime.lastReason = tostring(done or "pump failed")
        runtime.pending = false
        active = nil
        error(done)
    end
    if done then return end
    local scheduler = Nexus and Nexus.Scheduler
    -- A publication waiting for the catalog is checked again after a short
    -- delay instead of on every frame.
    local delay = active and active.waiting and Served.WAIT or 0
    local scheduled, why = scheduler and scheduler.After
        and scheduler.After(SCHEDULER_KEY, delay, ScheduledPump)
    if not scheduled then
        runtime.failures = runtime.failures + 1
        runtime.lastReason = "schedule-failed"
        runtime.pending = false
        active = nil
        error(why or "legacy data migration scheduler unavailable")
    end
end

local function Schedule()
    local scheduler = Nexus and Nexus.Scheduler
    return scheduler and scheduler.After
        and scheduler.After(SCHEDULER_KEY, 0, ScheduledPump)
end

------------------------------------------------------------------------
-- F-S1-1: recovery of a profile whose conversion reached only the legacy
-- location (the defect of b704660). Its receipt says complete, the served
-- payload still holds the older leaderboard map, and the legacy location
-- holds the converter's own result (Finish retired the older map there). The
-- converted maps are merged into the served payload once, bounded and
-- validated: a converted row is merged only when it is exactly the converted
-- form of a row of the served older map (or that row's promoted personal
-- best), only where the served payload has no stronger row, and always as a
-- copy. Nothing is converted again, no record is made for a row the legacy
-- location does not hold, and a row stays in the older map unless the
-- converted maps account for all the converter made of it (Served.Account).
-- The receipt and the legacy location are not written. The trigger is the
-- served content itself, so the recovery is idempotent: afterwards the older
-- map holds only rows that stay, whose merged rows are served already, and a
-- later start-up scans those and publishes nothing.
------------------------------------------------------------------------

function Served.RecoveryInput(database)
    local live = Served.Payload(database)
    local raw = rawget(database, "dpsCapture")
    if not live or type(raw) ~= "table" then return nil end
    local older = rawget(live, "leaderboard")
    if type(older) ~= "table" or next(older) == nil then return nil end
    if rawget(raw, "leaderboard") ~= nil
        or type(rawget(raw, "characterBest")) ~= "table" then
        return nil
    end
    return live, raw
end

function Served.NewRecovery(database, restarts)
    local live, raw = Served.RecoveryInput(database)
    if not live then return nil end
    return {database=database, phase="scan", index=1, items=nil,
        restarts=restarts or 0, revision=CurrentDpsRevision(), raw=raw,
        -- NormalizeDpsRow records its quarantine and counts here, never in
        -- the receipt.
        scratch={},
        source={leaderboard=rawget(live, "leaderboard"),
            characterBest=rawget(live, "characterBest"),
            personalBest=rawget(live, "personalBest")},
        -- accounted: older-map rows that leave the map; gains: merged rows
        -- that rank above the served row at their place.
        merge={dummy={}, lk={}}, personal={}, residual={}, accounted=0,
        gains=0}
end

function Served.RecoveryChanged(job)
    if job.revision ~= CurrentDpsRevision() then return true end
    local live = Served.Payload(job.database)
    return not live or rawget(live, "leaderboard") ~= job.source.leaderboard
        or rawget(live, "characterBest") ~= job.source.characterBest
        or rawget(live, "personalBest") ~= job.source.personalBest
end

-- Neither row ranks above the other: the same record.
function Served.SameRecord(left, right)
    return not BetterRow(left, right) and not BetterRow(right, left)
end

-- A merged row that ranks above the served row at map[outer][inner] changes
-- the served payload (Served.Recovered makes the same comparison).
function Served.Gain(job, map, outer, inner, row)
    local rows = type(map) == "table" and map[outer] or nil
    local current = type(rows) == "table" and rows[inner] or nil
    if BetterRow(row, type(current) == "table" and current or nil) then
        job.gains = job.gains + 1
    end
end

-- One item of the served older map, read the way the converter read it. The
-- converter made a character best of every row and, of a row with verified
-- ownership, the personal best of its loadout when its owner was the
-- character logged in (ProcessLeaderboard). That character is not recorded,
-- so a row leaves the older map only when the converted maps account for its
-- character best (the same record, or a stronger converted row of that
-- character) and, for a row with verified ownership, for its personal best
-- (the same record), whichever row the converter kept as the character best.
-- Every other row stays; what is merged for it is still merged.
function Served.Account(job, item)
    if item.keep then
        Served.KeepLegacy(job.residual, item.fingerprint, item.category, nil,
            item.row)
        return
    end
    local row, key = NormalizeDpsRow(job.scratch, item.row, item.fingerprint,
        item.key, "leaderboard")
    local converted = rawget(job.raw, "characterBest")
    converted = row and type(converted) == "table" and converted[item.category]
    converted = type(converted) == "table" and converted[key] or nil
    if type(converted) ~= "table" then converted = nil end
    local accounted = false
    if converted and Served.SameRecord(row, converted) then
        accounted = true
        local merge = job.merge[item.category]
        if BetterRow(converted, merge[key]) then merge[key] = converted end
        Served.Gain(job, job.source.characterBest, item.category, key,
            converted)
    elseif converted and BetterRow(converted, row) then
        -- The converter kept a stronger row of this character instead.
        accounted = true
    end
    if accounted then
        local personal = rawget(job.raw, "personalBest")
        local entry = type(personal) == "table" and row.fingerprint ~= nil
            and personal[row.fingerprint] or nil
        local best = type(entry) == "table" and entry[item.category] or nil
        if type(best) == "table" and Served.SameRecord(row, best) then
            job.personal[row.fingerprint] = job.personal[row.fingerprint] or {}
            job.personal[row.fingerprint][item.category] = best
            Served.Gain(job, job.source.personalBest, row.fingerprint,
                item.category, best)
        elseif row.fingerprint ~= nil and VerifiedOwner(row) then
            -- Nothing accounts for the personal best the converter can have
            -- promoted from this row: it stays rather than being consumed.
            accounted = false
        end
    end
    if accounted then
        job.accounted = job.accounted + 1
    else
        Served.KeepLegacy(job.residual, item.fingerprint, item.category,
            item.key, item.row)
    end
end

-- The recovery's replacement payload: the live top level as it is, each
-- merged row copied into a copy of its map where the served payload has no
-- stronger row, and the older map reduced to the rows that stay.
-- nil when a map the merge needs is not a table: that payload stays as it is.
function Served.Recovered(job, top)
    local function Merge(target, rows)
        if target ~= nil and type(target) ~= "table" then return nil end
        local copy = ShallowCopy(target)
        for key, row in pairs(rows) do
            local current = copy[key]
            if current ~= nil and type(current) ~= "table" then return nil end
            if BetterRow(row, current) then copy[key] = DeepCopy(row) end
        end
        return copy
    end
    local out = ShallowCopy(top)
    if next(job.merge.dummy) ~= nil or next(job.merge.lk) ~= nil then
        if top.characterBest ~= nil and type(top.characterBest) ~= "table" then
            return nil
        end
        local character = ShallowCopy(top.characterBest)
        for _, category in ipairs({"dummy", "lk"}) do
            if next(job.merge[category]) ~= nil then
                local bucket = Merge(character[category], job.merge[category])
                if not bucket then return nil end
                character[category] = bucket
            end
        end
        out.characterBest = character
    end
    if next(job.personal) ~= nil then
        if top.personalBest ~= nil and type(top.personalBest) ~= "table" then
            return nil
        end
        local personal = ShallowCopy(top.personalBest)
        for fingerprint, categories in pairs(job.personal) do
            local entry = Merge(personal[fingerprint], categories)
            if not entry then return nil end
            personal[fingerprint] = entry
        end
        out.personalBest = personal
    end
    out.leaderboard = next(job.residual) ~= nil and job.residual or nil
    return out
end

function Served.RecoveryDone(published)
    recovery = nil
    if not published then return true end
    runtime.recovered = runtime.recovered + 1
    runtime.lastReason = "served DPS payload recovered"
    local revisions = Nexus and Nexus.Revisions
    if revisions and type(revisions.Advance) == "function" then
        pcall(revisions.Advance, revisions.DPS_CHANGED,
            {scope="all",reason="legacy DPS recovered into the served payload"})
    end
    local retention = Nexus and Nexus.DataRetention
    if retention and type(retention.Request) == "function" then
        pcall(retention.Request, "legacy DPS recovered")
    end
    local refresh = Nexus and Nexus.ViewRefresh
    if refresh and type(refresh.Request) == "function" then pcall(refresh.Request) end
    return true
end

-- A changed source or a refused publication starts a new scan of the current
-- payload, at most REFUSAL_LIMIT times per session; then nothing is written.
function Served.RetryRecovery(job, why)
    recovery = nil
    if job.restarts + 1 >= Served.REFUSAL_LIMIT then
        runtime.failures = runtime.failures + 1
        runtime.lastReason = "served recovery stopped: " .. tostring(why)
        return true
    end
    recovery = Served.NewRecovery(job.database, job.restarts + 1)
    return recovery == nil
end

-- One bounded step: at most `limit` rows of the older map, or one publication
-- attempt. Returns true when the recovery is over.
function Served.PumpRecovery(limit)
    local job = recovery
    if not job then return true end
    if not WriterArmed(job.database) then recovery = nil; return true end
    if job.ticket then
        local ticket = job.ticket
        if ticket.state == "pending" then job.waiting = true; return false end
        job.ticket, job.waiting = nil, nil
        if Served.Committed(job.database, ticket, job.published) then
            return Served.RecoveryDone(true)
        end
        return Served.RetryRecovery(job, ticket.reason)
    end
    if Served.RecoveryChanged(job) then
        return Served.RetryRecovery(job, "source-changed")
    end
    if job.phase == "scan" then
        job.items = job.items or SnapshotLeaderboard({served=true,
            source={leaderboard=job.source.leaderboard}})
        local work = 0
        while work < limit do
            local item = job.items[job.index]
            if not item then job.phase = "publish"; break end
            Served.Account(job, item)
            job.index, work = job.index + 1, work + 1
        end
        if job.phase == "scan" then return false end
        -- No row leaves the older map and no merged row ranks above the
        -- served one: nothing changes, and nothing is written. Rows that stay
        -- therefore start no publication at a later start-up.
        if job.accounted == 0 and job.gains == 0 then
            return Served.RecoveryDone(false)
        end
    end
    if not Served.Writable(job.database) then return Served.RecoveryDone(false) end
    local catalog, handle = Served.Maintenance(job.database)
    if not handle then job.waiting = true; return false end
    job.waiting = nil
    local live = Served.Payload(job.database)
    local top, count = Served.TopLevel(live)
    local payload = Served.Recovered(job, top)
    if not payload then
        if type(catalog.CancelMaintenance) == "function" then
            catalog.CancelMaintenance(handle)
        end
        runtime.lastReason = "served recovery skipped: a DPS map is not a table"
        return Served.RecoveryDone(false)
    end
    local committed, detail = Served.Commit(catalog, handle, job.database,
        live, top, count, payload)
    if committed == nil then
        job.ticket, job.published, job.waiting = detail, payload, true
        return false
    end
    if committed then return Served.RecoveryDone(true) end
    return Served.RetryRecovery(job, detail)
end

function Served.ScheduledRecovery()
    local ok, done = pcall(Served.PumpRecovery, BATCH_SIZE)
    if not ok then
        runtime.failures = runtime.failures + 1
        runtime.lastReason = tostring(done or "served recovery failed")
        recovery = nil
        error(done)
    end
    if done or not recovery then return end
    local scheduler = Nexus and Nexus.Scheduler
    local scheduled = scheduler and scheduler.After
        and scheduler.After(Served.RECOVERY_KEY,
            recovery.waiting and Served.WAIT or 0, Served.ScheduledRecovery)
    if not scheduled then recovery = nil end
end

-- Called by Init for a complete receipt. Read-only saved data, a settings
-- format this converter leaves untouched, and a payload that does not show
-- the defect start nothing.
function Served.StartRecovery(database)
    if recovery and recovery.database == database then return "pending" end
    recovery = nil
    if not Served.Writable(database) then return nil end
    local job = Served.NewRecovery(database)
    if not job then return nil end
    local scheduler = Nexus and Nexus.Scheduler
    local scheduled = scheduler and scheduler.After
        and scheduler.After(Served.RECOVERY_KEY, 0, Served.ScheduledRecovery)
    if not scheduled then return "unscheduled" end
    recovery = job
    runtime.recoveries = runtime.recoveries + 1
    return "scheduled"
end

function Migration.Init(database)
    runtime.requested = runtime.requested + 1
    database = type(database) == "table" and database
        or type(NexusDB) == "table" and NexusDB or nil
    if not database then return {complete=false,reason="database unavailable"} end
    if not WriterArmed(database) then return RetiredResult() end

    local existing, metaError = Meta(database, false)
    if metaError then
        return {complete=false,readOnly=true,reason=metaError}
    end
    if existing and existing.state == "complete"
        and (tonumber(existing.version) or 0) >= STORAGE_VERSION then
        -- A conversion that reached only the legacy location is recovered
        -- into the served payload; the receipt itself is not written.
        return {complete=true,needed=true,reason="complete",
            servedRecovery=Served.StartRecovery(database)}
    end

    if MalformedSettingsMarker(database) then
        return {complete=true,needed=false,skipped=true,readOnly=true,
            reason="malformed settings format marker left untouched"}
    end
    local settingsVersion = tonumber(database.settingsVersion) or 0
    if settingsVersion > LAST_KNOWN_LEGACY_SETTINGS_VERSION then
        -- Settings and DPS/catalog storage have separate schema owners.  This
        -- converter must leave an unknown settings format untouched, but it
        -- must not prevent those independent owners from doing their guarded
        -- initialization when no legacy-data transaction was started.
        return {complete=true,needed=false,skipped=true,readOnly=true,
            reason="future settings schema left untouched"}
    end
    if not existing and not NeedsMigration(database) then
        return {complete=true,needed=false,reason="current"}
    end
    local meta
    meta, metaError = Meta(database, true)
    if not meta then return {complete=false,readOnly=true,reason=metaError} end

    if active and active.database == database then
        runtime.coalesced = runtime.coalesced + 1
        return {complete=false,pending=true,needed=true,reason="coalesced"}
    end
    if active and active.database ~= database then
        runtime.restarts = runtime.restarts + 1
        active = nil
    end
    active = Begin(database, meta, "startup", false)
    local scheduled, why = Schedule()
    if not scheduled then
        active = nil
        runtime.pending = false
        runtime.failures = runtime.failures + 1
        return {complete=false,needed=true,reason=why or "scheduler unavailable"}
    end
    return {complete=false,pending=true,needed=true,reason="scheduled"}
end

-- Store registration runs before a new migration starts so the exact current
-- character is part of the staged snapshot. It must stand down for active or
-- future-owned migration state and for an unknown future settings owner.
function Migration.AccountWritesAllowed(database)
    database = type(database) == "table" and database
        or type(NexusDB) == "table" and NexusDB or nil
    if not database then return false, "database unavailable" end
    if MalformedSettingsMarker(database) then
        return false, "malformed settings format marker is read-only"
    end
    local store = Nexus and Nexus.Store
    local currentSettingsVersion = store
        and type(store.SettingsVersion) == "function"
        and tonumber(store.SettingsVersion()) or 2
    -- Saved formats 3-5 read by Store (core/Store.lua SavedFormat) also stop
    -- here, and Store refuses ledger writes for them on its own as well; this
    -- converter is not started for them (Store's knownSavedFormat gate).
    if (tonumber(database.settingsVersion) or 0) > currentSettingsVersion then
        return false, "future settings schema is read-only"
    end
    local existing, metaError = Meta(database, false)
    if metaError then return false, metaError end
    if existing and existing.state ~= "complete" then
        return false, "legacy migration is active"
    end
    return true
end

function Migration.BlocksDpsMigration(database)
    database = type(database) == "table" and database
        or type(NexusDB) == "table" and NexusDB or nil
    if not database then return false end
    local meta = rawget(database, "legacyDataMigration")
    return type(meta) == "table" and meta.state ~= "complete"
end

function Migration.IsComplete(database)
    database = type(database) == "table" and database
        or type(NexusDB) == "table" and NexusDB or nil
    if not database then return false end
    local meta = rawget(database, "legacyDataMigration")
    return type(meta) ~= "table" or (meta.state == "complete"
        and (tonumber(meta.version) or 0) >= STORAGE_VERSION)
end

function Migration.Status(database)
    database = type(database) == "table" and database
        or type(NexusDB) == "table" and NexusDB or nil
    local meta = database and rawget(database, "legacyDataMigration") or nil
    return {
        schemaVersion=SCHEMA_VERSION,version=STORAGE_VERSION,
        pending=active ~= nil and active.database == database,
        state=type(meta) == "table" and meta.state or "not-needed",
        phase=type(meta) == "table" and meta.phase or nil,
        workUnits=type(meta) == "table" and tonumber(meta.workUnits) or 0,
        retired=not WriterArmed(database),
        stats=type(meta) == "table" and DeepCopy(meta.stats) or {},
        lastResult=type(meta) == "table" and DeepCopy(meta.lastResult) or nil,
        -- The phase of this session's served-payload recovery, if one runs.
        servedRecovery=recovery ~= nil and recovery.database == database
            and recovery.phase or nil,
        runtime=DeepCopy(runtime),
    }
end

-- The only entry that may arm the retired writer. It is called by
-- AuthorityBootstrapCoordinatorV1 before authority bootstrap, reads only the
-- fixed top-level recovery metadata, never descends into staging, and writes
-- nothing. A non-table marker is LEGACY_DATA_RECOVERY_INVALID and leaves the
-- writer retired.
function Migration.ClassifyLegacyWriterV1(database, coordinator)
    database = type(database) == "table" and database
        or type(NexusDB) == "table" and NexusDB or nil
    writerAuthority = nil
    if not database then
        return {armed=false, classification="DATABASE_UNAVAILABLE"}
    end
    local meta = rawget(database, "legacyDataMigration")
    local classification = "INACTIVE"
    if meta ~= nil then
        if type(meta) ~= "table" then
            return {armed=false,
                classification="LEGACY_DATA_RECOVERY_INVALID"}
        elseif meta.state == "complete" then
            classification = "TERMINAL_RECEIPT_PRESERVED"
        else
            classification = "RECOVERY_REQUIRED"
        end
    end
    writerAuthority = {database=database, coordinator=coordinator}
    return {armed=true, classification=classification}
end

-- Retires the writer again. No ordinary caller can resume the cursor after
-- this, and any in-flight session job is abandoned without a durable write.
function Migration.RetireLegacyWriterV1()
    writerAuthority = nil
    active = nil
    recovery = nil
    runtime.pending = false
    return true
end

function Migration.LegacyWriterRetired(database)
    database = type(database) == "table" and database
        or type(NexusDB) == "table" and NexusDB or nil
    return not WriterArmed(database)
end

function Migration.BatchSize() return BATCH_SIZE end
