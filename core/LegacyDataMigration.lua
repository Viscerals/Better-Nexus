-- Nexus: ordered, bounded conversion of pre-refactor account/DPS storage.
--
-- The live database is never used as scratch space.  Rows are normalized into
-- a durable staging area over small scheduler batches, then the four owned
-- tables are swapped together after validation.  An interrupted phase simply
-- replays into the same idempotent staging maps on the next login.

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
local runtime = {
    requested=0,coalesced=0,jobs=0,pumps=0,workUnits=0,maxWork=0,
    restarts=0,failures=0,completed=0,pending=false,lastReason="none",
}

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

local function IsLocalRow(row)
    local current = CurrentOwnerKey()
    local owner = type(row) == "table"
        and Identity.CanonicalOwnerKey(row.ownerKey) or nil
    return current ~= nil and owner ~= nil
        and row.ownerVerified == true and current == owner
end

local function MergeAccount(target, incoming)
    if not target then return ShallowCopy(incoming) end
    local leftSeen = tonumber(target.lastSeen) or 0
    local rightSeen = tonumber(incoming.lastSeen) or 0
    local winner, fallback = target, incoming
    if rightSeen > leftSeen then winner, fallback = ShallowCopy(incoming), target end
    for key, value in pairs(fallback) do
        if winner[key] == nil then winner[key] = value end
    end
    return winner
end

local function NormalizeAccount(meta, sourceKey, source)
    if type(source) ~= "table" then
        Quarantine(meta, "account", sourceKey, "malformed account row")
        return nil
    end
    local ownerKey = Identity.CanonicalOwnerKey(source.ownerKey)
        or Identity.CanonicalOwnerKey(sourceKey)
    local name = Identity.DisplayPlayer(source.name)
    if not name and ownerKey then name = ownerKey:match("^([^@]+)@") end
    if not ownerKey and name and type(source.realm) == "string" then
        ownerKey = Identity.OwnerKey(name, source.realm)
    end
    local localOwner = CurrentOwnerKey()
    if ownerKey and ownerKey:match("@unknown$") then
        if localOwner and Identity.PlayerKey(name or sourceKey)
            == localOwner:match("^([^@]+)@") then
            ownerKey = localOwner
        else
            ownerKey = nil
        end
    end
    if not ownerKey or not name
        or not Identity.OwnerKeyMatchesAuthor(ownerKey, name) then
        Quarantine(meta, "account", sourceKey, "unresolved account identity")
        return nil
    end
    local out = ShallowCopy(source)
    out.ownerKey = nil -- the canonical map key is the sole identity index
    out.name = source.name or name
    out.realm = ownerKey:match("@(.+)$")
    return ownerKey, out
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
    local dps = DpsStore(database)
    if not dps then
        database.dpsCapture = {}
        dps = database.dpsCapture
    end
    if not restarting and meta.state == "staging"
        and ValidStaging(meta.staging) and VALID_PHASE[meta.phase] then
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
        items=nil,index=1,dpsRevision=CurrentDpsRevision(),
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
    end
end

local function ProcessCharacter(job, item)
    local row, key = NormalizeDpsRow(job.meta, item.row,
        type(item.row) == "table" and item.row.fingerprint or nil,
        item.key, "characterBest")
    if row and PutCharacter(job.meta.staging, item.category, key, row) then
        AddStat(job.meta, "characterRowsCopied", 1)
    end
end

local function ProcessLeaderboard(job, item)
    local row, key = NormalizeDpsRow(job.meta, item.row,
        item.fingerprint, item.key, "leaderboard")
    if not row then return end
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
        local key, row = NormalizeAccount(job.meta, item.key, item.row)
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
    local dps = DpsStore(job.database)
    return dps ~= job.dps
        or job.source.communityBuilds ~= job.database.communityBuilds
        or job.source.personalBest ~= dps.personalBest
        or job.source.characterBest ~= dps.characterBest
        or job.source.leaderboard ~= dps.leaderboard
        or job.source.buildBest ~= dps.buildBest
end

local function Finish(job)
    if SourceChanged(job) then return false, "source-changed" end
    local staging = job.meta.staging
    if not ValidStaging(staging) then return false, "invalid staging owner" end
    local database, dps, meta = job.database, job.dps, job.meta
    meta.state, meta.phase = "committing", "commit"

    -- These assignments are the transaction boundary.  The old tables remain
    -- untouched until every replacement has been constructed and validated.
    database.accountCharacters = staging.accountCharacters
    dps.personalBest = staging.personalBest
    dps.buildBest = staging.buildBest
    dps.characterBest = staging.characterBest
    dps.leaderboard = nil

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
        -- ViewRefresh owns the repair-before-publish ordering and coalesces the
        -- UI work. Avoid a duplicate direct repair request here.
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
    limit = math.max(1, math.min(math.floor(tonumber(limit) or BATCH_SIZE),
        BATCH_SIZE))
    runtime.pumps = runtime.pumps + 1
    local work = 0
    while active and work < limit do
        if active.phase == "commit" then
            local job = active
            local ok, why = Finish(job)
            if ok then active = nil else Restart(job, why) end
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
    local scheduled, why = scheduler and scheduler.After
        and scheduler.After(SCHEDULER_KEY, 0, ScheduledPump)
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

function Migration.Init(database)
    runtime.requested = runtime.requested + 1
    database = type(database) == "table" and database
        or type(NexusDB) == "table" and NexusDB or nil
    if not database then return {complete=false,reason="database unavailable"} end

    local existing, metaError = Meta(database, false)
    if metaError then
        return {complete=false,readOnly=true,reason=metaError}
    end
    if existing and existing.state == "complete"
        and (tonumber(existing.version) or 0) >= STORAGE_VERSION then
        return {complete=true,needed=true,reason="complete"}
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
        stats=type(meta) == "table" and DeepCopy(meta.stats) or {},
        lastResult=type(meta) == "table" and DeepCopy(meta.lastResult) or nil,
        runtime=DeepCopy(runtime),
    }
end

function Migration.BatchSize() return BATCH_SIZE end
