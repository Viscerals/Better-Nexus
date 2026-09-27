-- Nexus: bounded recovery of exact historical loadout identities from legacy
-- DPS rows. This owner never relaxes Community qualification, rewrites DPS,
-- grants ownership, or performs gameplay/transport work.

Nexus = Nexus or {}
local Identity = assert(Nexus.Identity,
    "Nexus Identity must load before LegacyQualificationRepair")
local Repair = {}
Nexus.LegacyQualificationRepair = Repair

local SCHEMA_VERSION = 1
local STORAGE_VERSION = 1
local CURSOR_VERSION = 1
local SCHEDULER_KEY = "legacy-qualification-repair"
local FOLLOWUP_KEY = "legacy-qualification-repair.follow-up"
local BATCH_SIZE = 25
-- Fairness: after a pass in this session, the next one starts no sooner than
-- this many seconds, or the previous pass's own active time if longer. Under
-- sustained DPS input the repair therefore works on at most about half of the
-- frames, and every pass still completes.
local MIN_FOLLOWUP_GAP = 5
-- Active time counts consecutive working pumps; a longer pause between two
-- pumps (a wait for catalog admission, a hidden client) is not work.
local MAX_PUMP_INTERVAL = 0.25
local VALID_CLASS = {
    WARRIOR=true,PALADIN=true,HUNTER=true,ROGUE=true,PRIEST=true,
    DEATHKNIGHT=true,SHAMAN=true,MAGE=true,WARLOCK=true,DRUID=true,
}
local runtime = {
    requested=0,coalesced=0,jobs=0,pumps=0,workUnits=0,maxWork=0,
    scanned=0,affected=0,recoverable=0,recovered=0,reused=0,rejected=0,
    published=0,restarts=0,failures=0,lastReason="none",pending=false,
    completedDpsRevision=nil,
    passesCompleted=0,stalePasses=0,changedSkipped=0,followUps=0,
    followUpsCoalesced=0,deferredRequests=0,followUpPending=false,
    lastPassStartedAt=nil,lastPassFinishedAt=nil,lastPassDuration=nil,
    lastPassElapsed=nil,
    nextPassNotBefore=nil,
    deferredNoCatalog=0,deferredNoDps=0,deferredOneCategory=0,
    deferredDurationOrCategory=0,deferredBuildIdCollision=0,
    deferredInsufficientEvidence=0,deferredUnauthorizedOwner=0,
    deferredStaleOrSuperseded=0,deferredIdentityCollision=0,
    deferredCatalogWrite=0,
}
local active
-- The revision owner and saved root the completed revision belongs to. Kept
-- out of `runtime`, which Stats() copies: only scalars are reported.
local completedSource, completedDatabase

local REASON_FIELD = {
    ["no-catalog"]="deferredNoCatalog",
    ["no-dps"]="deferredNoDps",
    ["one-category"]="deferredOneCategory",
    ["duration-or-category"]="deferredDurationOrCategory",
    ["build-id-collision"]="deferredBuildIdCollision",
    ["insufficient-evidence"]="deferredInsufficientEvidence",
    ["unauthorized-owner"]="deferredUnauthorizedOwner",
    ["stale-or-superseded"]="deferredStaleOrSuperseded",
    ["identity-collision"]="deferredIdentityCollision",
    ["catalog-write-failed"]="deferredCatalogWrite",
}

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, child in pairs(value) do out[Copy(key, seen)] = Copy(child, seen) end
    return out
end

local function Fixed(reason, qualified, recoverable, collision, ownership)
    return {
        schema=SCHEMA_VERSION,reason=reason,
        qualified=qualified == true,recoverable=recoverable == true,
        collision=collision == true,ownership=ownership or "none",
    }
end

local function RowFingerprint(row)
    local value = type(row) == "table" and row.fingerprint or nil
    return type(value) == "string" and value ~= "" and value or nil
end

local function RowEvidence(row)
    if type(row) ~= "table" then return nil end
    local evidence = Nexus.LoadoutEvidence
    if evidence and type(evidence.OrdinaryCompleteness) == "function" then
        local ok, verdict = pcall(evidence.OrdinaryCompleteness, row)
        if ok and type(verdict) == "table" and verdict.complete == true then
            return Copy(verdict.echoes)
        end
    end
    return nil
end

local function EvidenceFingerprint(row)
    local echoes = RowEvidence(row)
    local dps = Nexus.DpsCapture
    local key = echoes and dps and type(dps.GetEchoKey) == "function"
        and dps.GetEchoKey(echoes) or nil
    return key, echoes
end

local function OwnerState(dummy, lk)
    local dummyOwner = type(dummy) == "table" and dummy.ownerKey or nil
    local lkOwner = type(lk) == "table" and lk.ownerKey or nil
    local dummyCanonical = dummyOwner and Identity.CanonicalOwnerKey(dummyOwner)
    local lkCanonical = lkOwner and Identity.CanonicalOwnerKey(lkOwner)
    if (dummy.ownerVerified == true or lk.ownerVerified == true)
        and (not dummyCanonical or not lkCanonical
            or dummyCanonical ~= lkCanonical) then
        return "unauthorized"
    end
    if dummy.ownerVerified == true and lk.ownerVerified == true
        and dummyCanonical and dummyCanonical == lkCanonical then
        return "verified"
    end
    return "unverified"
end

local function LegacyVersion(row)
    local version = tonumber(type(row) == "table"
        and (row.protocolVersion or row.v) or nil)
    return version and version == math.floor(version)
        and version >= 2 and version <= 6
end

local function FinitePositive(value)
    value = tonumber(value)
    return value ~= nil and value == value
        and value > 0 and value < math.huge
end

function Repair.Classify(input)
    input = type(input) == "table" and input or {}
    if input.catalogAvailable == false then
        return Fixed("no-catalog")
    end
    local build, dummy, lk = input.build, input.dummy, input.lk
    if type(dummy) ~= "table" and type(lk) ~= "table" then
        return Fixed("no-dps")
    end
    if type(dummy) ~= "table" or type(lk) ~= "table" then
        return Fixed("one-category")
    end
    local dps = Nexus.DpsCapture
    if not dps or not dps.IsDurationEligible("dummy", dummy.duration)
        or not dps.IsDurationEligible("lk", lk.duration)
        or dummy.category ~= nil and dummy.category ~= "dummy"
        or lk.category ~= nil and lk.category ~= "lk" then
        return Fixed("duration-or-category")
    end
    local dummyFingerprint, lkFingerprint =
        RowFingerprint(dummy), RowFingerprint(lk)
    if not dummyFingerprint or dummyFingerprint ~= lkFingerprint
        or not FinitePositive(dummy.dps)
        or not FinitePositive(lk.dps) then
        return Fixed("insufficient-evidence")
    end
    local fingerprint = dummyFingerprint
    local collision = type(build) == "table"
        and type(build.fingerprint) == "string"
        and build.fingerprint ~= fingerprint
    if input.superseded == true then
        return Fixed("stale-or-superseded")
    end
    local evidence = Nexus.LoadoutEvidence
    local ok, buildVerdict = false, nil
    if evidence and type(evidence.OrdinaryCompleteness) == "function"
        and type(build) == "table" then
        ok, buildVerdict = pcall(evidence.OrdinaryCompleteness, build)
    end
    local buildComplete = ok and type(buildVerdict) == "table"
        and buildVerdict.complete == true
    if buildComplete and build.fingerprint == fingerprint then
        return Fixed("exact-current", true, false, false, "none")
    end
    if not LegacyVersion(dummy) or not LegacyVersion(lk) then
        return Fixed("insufficient-evidence")
    end
    local dummyClass = type(dummy.class) == "string" and dummy.class:upper() or nil
    local lkClass = type(lk.class) == "string" and lk.class:upper() or nil
    if dummyClass and lkClass and dummyClass ~= lkClass then
        return Fixed("insufficient-evidence")
    end
    local ownership = OwnerState(dummy, lk)
    if ownership == "unauthorized" then
        return Fixed("unauthorized-owner", false, false, false, ownership)
    end
    local dummyKey, dummyEchoes = EvidenceFingerprint(dummy)
    local lkKey, lkEchoes = EvidenceFingerprint(lk)
    if not dummyEchoes and not lkEchoes and collision then
        return Fixed("build-id-collision", false, false, true)
    end
    if not dummyEchoes or not lkEchoes
        or dummyKey ~= fingerprint or lkKey ~= fingerprint then
        return Fixed("insufficient-evidence")
    end
    return Fixed("recoverable-history", false, true, collision, ownership)
end

local function Meta(database)
    local existing = database.legacyQualificationRepair
    if type(existing) == "table"
        and ((tonumber(existing.schemaVersion) or 0) > SCHEMA_VERSION
            or (tonumber(existing.version) or 0) > STORAGE_VERSION
            or (tonumber(existing.cursorVersion) or 0) > CURSOR_VERSION) then
        return nil, "future legacy repair schema is read-only"
    end
    database.legacyQualificationRepair = type(existing) == "table"
        and existing or {}
    local meta = database.legacyQualificationRepair
    if meta.schemaVersion == nil then meta.schemaVersion = SCHEMA_VERSION end
    return meta
end

local function ExistingBuild(id)
    local catalog = Nexus.BuildCatalog
    return catalog and type(catalog.Get) == "function" and catalog.Get(id) or nil
end

local function Tombstoned(id)
    local catalog = Nexus.BuildCatalog
    local state = id and catalog and type(catalog.SyncState) == "function"
        and catalog.SyncState(id) or nil
    return type(state) == "table" and state.tombstone ~= nil
end

local function HashText(value, seed)
    local hash = tonumber(seed) or 5381
    for index = 1, #value do
        hash = (hash * 33 + value:byte(index)) % 2147483648
    end
    return string.format("%x", hash)
end

local function HistoricalId(fingerprint)
    return "legacy-dps-" .. HashText(fingerprint, 5381)
        .. "-" .. HashText(fingerprint, 216613626)
end

local function NormalizeClass(dummy, lk)
    local value = tostring(dummy.class or lk.class or "UNKNOWN"):upper()
    return VALID_CLASS[value] and value or "UNKNOWN"
end

local function BuildEchoes(source)
    local out = {}
    for _, echo in ipairs(source or {}) do
        out[#out + 1] = {
            spellId=tonumber(echo.spellId or echo.id),
            quality=tonumber(echo.quality) or 0,
            stacks=tonumber(echo.stacks or echo.count) or 1,
            locked=echo.locked and true or nil,
        }
    end
    return out
end

local function LegacyAuthor(dummy, lk)
    local dummyAuthor = Identity.DisplayPlayer(dummy.player)
    local lkAuthor = Identity.DisplayPlayer(lk.player)
    if dummyAuthor and lkAuthor and Identity.SamePlayer(dummyAuthor, lkAuthor) then
        return dummyAuthor
    end
    return dummyAuthor and not lkAuthor and dummyAuthor
        or lkAuthor and not dummyAuthor and lkAuthor or "Legacy record"
end

local function LegacySource(dummy, lk)
    local dummyRelay = type(dummy.relaySender) == "string"
        and dummy.relaySender ~= ""
    local lkRelay = type(lk.relaySender) == "string" and lk.relaySender ~= ""
    if dummyRelay ~= lkRelay then return "mixed" end
    return dummyRelay and "relay" or "direct-or-unknown"
end

local function RecoveredBuild(fingerprint, dummy, lk)
    local echoes = BuildEchoes(RowEvidence(dummy) or RowEvidence(lk))
    local baseId = HistoricalId(fingerprint)
    local ownerState = OwnerState(dummy, lk)
    if Tombstoned(baseId) then
        return nil, nil, "stale-or-superseded"
    end
    local id, existing = baseId, ExistingBuild(baseId)
    if existing and existing.fingerprint ~= fingerprint then
        id, existing = nil, nil
        for suffix = 1, 64 do
            local candidate = baseId .. "-" .. tostring(suffix)
            if not Tombstoned(candidate) then
                local candidateBuild = ExistingBuild(candidate)
                if not candidateBuild
                    or candidateBuild.fingerprint == fingerprint then
                    id, existing = candidate, candidateBuild
                    break
                end
            end
        end
    end
    if not id then return nil, nil, "identity-collision" end
    if existing and existing.fingerprint == fingerprint then
        return nil, id, "existing"
    end
    if existing then return nil, nil, "identity-collision" end
    local author = LegacyAuthor(dummy, lk)
    local echoCount = 0
    for index = 1, #echoes do
        echoCount = echoCount + (tonumber(echoes[index].stacks) or 1)
    end
    return {
        id=id,title=NormalizeClass(dummy, lk) .. " Historical Record Loadout",
        description="Recovered from complete legacy DPS loadout evidence.",
        author=author,class=NormalizeClass(dummy, lk),echoes=echoes,
        fingerprint=fingerprint,echoCount=echoCount,loadoutAvailable=true,
        postedAt=math.min(tonumber(dummy.ts) or 0,tonumber(lk.ts) or 0),
        lastModified=math.max(tonumber(dummy.ts) or 0,tonumber(lk.ts) or 0),
        autoDps=true,legacyRecovered=true,
        legacyOwnership=ownerState,legacySource=LegacySource(dummy, lk),
        -- Deliberately omit ownerKey/isMine/ownerVerified. Proven content is
        -- not independent proof of edit, delete, tombstone, or relay authority.
    }, id, nil
end

local function CurrentDpsRevision()
    local revisions = Nexus.Revisions
    return revisions and type(revisions.Get) == "function"
        and revisions.Get(revisions.DPS_CHANGED) or nil
end

-- Revision numbers are session-local counters of one owner; a number is only
-- comparable with one read from the same owner.
local function RevisionSource()
    return Nexus.Revisions
end

local function Clock()
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        value = ok and tonumber(value) or nil
        if value and value == value and value < math.huge
            and value > -math.huge then return value end
    end
    return 0
end

local function NewJob(database, reason, restorePending, countPending)
    local dps = Nexus.DpsCapture
    if not (dps and type(dps.BeginLegacyQualificationCursor) == "function") then
        return nil, "DPS legacy cursor unavailable"
    end
    local cursor = dps.BeginLegacyQualificationCursor()
    if type(cursor) ~= "table" then return nil, "DPS legacy cursor unavailable" end
    local meta, metaError = Meta(database)
    if not meta then return nil, metaError end
    local pending = meta.inProgress == true
        and math.max(0,math.floor(tonumber(meta.pendingWrites) or 0)) or 0
    if restorePending and countPending and pending > 0 then
        runtime.recoverable = runtime.recoverable + pending
        runtime.recovered = runtime.recovered + pending
    end
    runtime.jobs = runtime.jobs + 1
    return {
        database=database,reason=reason or "requested",cursor=cursor,
        pairs={},phase="scan",pairKey=nil,changed=pending,work=0,
        recoverable=pending,recovered=pending,reused=0,rejected=0,
        dpsRevision=CurrentDpsRevision(),revisionSource=RevisionSource(),
        startedAt=Clock(),stale=false,skippedChanged=0,activeSeconds=0,
    }
end

local function CandidateKey(item)
    local row = item.row or {}
    return table.concat({
        tostring(item.key or ""),tostring(row.player or ""),
        tostring(row.buildId or row.b or ""),tostring(row.ts or ""),
    }, "\031")
end

local function AddCandidate(job, item)
    local fingerprint = item.fingerprint
    local pair = job.pairs[fingerprint]
    if not pair then pair = {}; job.pairs[fingerprint] = pair end
    local current = pair[item.category]
    local score = tonumber(item.row and item.row.dps) or 0
    local currentScore = tonumber(current and current.row
        and current.row.dps) or 0
    if not current or score > currentScore
        or score == currentScore
            and CandidateKey(item) < CandidateKey(current) then
        pair[item.category] = item
    end
end

local function Reject(job, reason)
    reason = REASON_FIELD[reason] and reason or "insufficient-evidence"
    runtime.rejected = runtime.rejected + 1
    job.rejected = job.rejected + 1
    runtime.lastReason = reason
    local field = REASON_FIELD[reason]
    runtime[field] = runtime[field] + 1
    job[field] = (tonumber(job[field]) or 0) + 1
end

local function Reuse(job)
    runtime.reused = runtime.reused + 1
    job.reused = job.reused + 1
end

local function RollbackRejected(job)
    if type(job) ~= "table" then return end
    runtime.rejected = math.max(0,
        runtime.rejected - (tonumber(job.rejected) or 0))
    for _, field in pairs(REASON_FIELD) do
        runtime[field] = math.max(0,
            runtime[field] - (tonumber(job[field]) or 0))
    end
end

-- Each scanned candidate row must still be the row stored under its captured
-- key when it is classified; a replaced, removed or re-keyed row is left for
-- the follow-up pass instead of being recovered from a stale snapshot.
local function PairCurrent(job, pair)
    local dps = Nexus.DpsCapture
    if not (dps and type(dps.LegacyQualificationCurrentRow) == "function") then
        return false
    end
    for _, category in ipairs({"dummy", "lk"}) do
        local item = pair[category]
        if item and dps.LegacyQualificationCurrentRow(
            job.cursor, item.category, item.key) ~= item.row then
            return false
        end
    end
    return true
end

local function ClassifyPair(job, fingerprint, pair)
    local catalog = Nexus.BuildCatalog
    if not PairCurrent(job, pair) then
        job.stale = true
        job.skippedChanged = job.skippedChanged + 1
        runtime.changedSkipped = runtime.changedSkipped + 1
        return
    end
    if not (pair.dummy and pair.lk) then
        Reject(job, "one-category")
        return
    end
    local exactId = catalog and catalog.FindExactFingerprintId
        and catalog.FindExactFingerprintId(fingerprint) or nil
    local dps = Nexus.DpsCapture
    local dummy = dps.MaterializeRecord(pair.dummy.row)
    local lk = dps.MaterializeRecord(pair.lk.row)
    if type(dummy) ~= "table" or type(lk) ~= "table" then
        Reject(job, "insufficient-evidence")
        return
    end
    local dummyBuildId = dummy.buildId or dummy.b
    local lkBuildId = lk.buildId or lk.b
    if Tombstoned(dummyBuildId) or Tombstoned(lkBuildId) then
        Reject(job, "stale-or-superseded")
        return
    end
    local buildId = dummyBuildId == lkBuildId and dummyBuildId or nil
    local build = exactId and ExistingBuild(exactId)
        or buildId and ExistingBuild(buildId) or nil
    local result = Repair.Classify({catalogAvailable=catalog ~= nil,
        build=build,dummy=dummy,lk=lk})
    if result.collision then runtime.affected = runtime.affected + 1 end
    if result.reason == "exact-current" then Reuse(job); return end
    if not result.recoverable then
        Reject(job, result.reason)
        return
    end
    runtime.recoverable = runtime.recoverable + 1
    job.recoverable = job.recoverable + 1
    local recovered, _, recoveryError = RecoveredBuild(
        fingerprint, dummy, lk)
    if not recovered then
        if recoveryError == "existing" then
            Reuse(job)
        else
            Reject(job, recoveryError or "insufficient-evidence")
        end
        return
    end
    local ok, why, changed = catalog.PutDeferred(recovered)
    if ok == nil and why == "ROOT_MUTATION_PENDING"
        and type(changed) == "table" then
        job.pendingCatalog = {ticket=changed, recovered=recovered, catalog=catalog}
        job.phase = "catalog-pending"
        return
    end
    if not ok then
        Reject(job, "catalog-write-failed")
        return
    end
    if changed then
        job.changed = job.changed + 1
        job.recovered = job.recovered + 1
        runtime.recovered = runtime.recovered + 1
        local meta = Meta(job.database)
        if meta then meta.pendingWrites = job.changed end
    else
        Reuse(job)
    end
end

local function CompletePendingCatalog(job)
    local pending = job.pendingCatalog
    if not pending then
        job.phase = "classify"
        return true
    end
    local ticket = pending.ticket
    if ticket.state == "pending" then return false end
    local catalog = pending.catalog
    if ticket.state == "committed" and (ticket.database ~= job.database
        or NexusDB ~= job.database or Nexus.BuildCatalog ~= catalog
        or catalog.BoundDatabase() ~= job.database
        or rawget(job.database, "authorityBundle") ~= ticket.bundle) then
        -- A terminal ticket acknowledges only its exact owner and publication.
        -- Abandon session work without stamping either database after drift.
        active, runtime.pending = nil, false
        runtime.failures = runtime.failures + 1
        runtime.lastReason = "SOURCE_DRIFT"
        return true
    end
    job.pendingCatalog = nil
    job.phase = "classify"
    if ticket.state ~= "committed" or ticket.committed ~= true then
        Reject(job, "catalog-write-failed")
        return true
    end
    job.changed = job.changed + 1
    job.recovered = job.recovered + 1
    runtime.recovered = runtime.recovered + 1
    local meta = Meta(job.database)
    if meta then meta.pendingWrites = job.changed end
    return true
end

local function Finish(job)
    local catalog = Nexus.BuildCatalog
    if not (catalog and type(catalog.PublishDeferred) == "function") then
        return false, "catalog publication unavailable"
    end
    local ok, published = catalog.PublishDeferred(
        job.changed, "legacy qualification repaired")
    if not ok then return false, published or "catalog publication unavailable" end
    runtime.published = runtime.published + (published or 0)
    local meta, metaError = Meta(job.database)
    if not meta then return false, metaError end
    meta.version=STORAGE_VERSION
    meta.cursorVersion=CURSOR_VERSION
    meta.inProgress=nil
    meta.phase=nil
    meta.workUnits=nil
    meta.pendingWrites=nil
    meta.requestedDpsRevision=nil
    -- Only the generation this pass covered is complete, and only when every
    -- candidate in its scope was classified. A newer revision that arrived
    -- during the pass, or a skipped changed candidate, stays for the
    -- follow-up pass; a pass that skipped anything stamps nothing.
    if (tonumber(job.skippedChanged) or 0) == 0 then
        meta.completedDpsRevision=job.dpsRevision or 0
        runtime.completedDpsRevision=job.dpsRevision
        completedSource=job.revisionSource
        completedDatabase=job.database
    end
    meta.lastResult={
        schema=SCHEMA_VERSION,recoverable=job.recoverable,
        coveredDpsRevision=job.dpsRevision,followUp=job.stale == true,
        recovered=job.recovered,reused=job.reused,rejected=job.rejected,
        published=published or 0,reason="complete",
        deferredNoCatalog=job.deferredNoCatalog or 0,
        deferredNoDps=job.deferredNoDps or 0,
        deferredOneCategory=job.deferredOneCategory or 0,
        deferredDurationOrCategory=job.deferredDurationOrCategory or 0,
        deferredBuildIdCollision=job.deferredBuildIdCollision or 0,
        deferredInsufficientEvidence=job.deferredInsufficientEvidence or 0,
        deferredUnauthorizedOwner=job.deferredUnauthorizedOwner or 0,
        deferredStaleOrSuperseded=job.deferredStaleOrSuperseded or 0,
        deferredIdentityCollision=job.deferredIdentityCollision or 0,
        deferredCatalogWrite=job.deferredCatalogWrite or 0,
    }
    runtime.lastReason = "complete"
    return true
end

-- One coalesced follow-up covers every DPS change that arrived during or after
-- a pass. It starts no sooner than the fairness gap after the previous pass;
-- an already scheduled follow-up is kept, never pushed later.
local function FollowUpGap()
    return math.max(MIN_FOLLOWUP_GAP, tonumber(runtime.lastPassDuration) or 0)
end

local function ScheduleFollowUp()
    runtime.followUpPending = true
    local scheduler = Nexus.Scheduler
    if scheduler and type(scheduler.Pending) == "function"
        and scheduler.Pending(FOLLOWUP_KEY) then
        runtime.followUpsCoalesced = runtime.followUpsCoalesced + 1
        return true
    end
    local due = (tonumber(runtime.lastPassFinishedAt) or Clock()) + FollowUpGap()
    runtime.nextPassNotBefore = due
    local scheduled, why = scheduler and type(scheduler.After) == "function"
        and scheduler.After(FOLLOWUP_KEY, math.max(0, due - Clock()), function()
            Repair.Request("follow-up")
        end)
    if not scheduled then
        runtime.failures = runtime.failures + 1
        runtime.lastReason = "schedule-failed"
        return false, why or "legacy repair scheduler unavailable"
    end
    runtime.followUps = runtime.followUps + 1
    return true
end

local function PassEnded(job, completed)
    local finished = Clock()
    runtime.lastPassFinishedAt = finished
    runtime.lastPassElapsed = math.max(0,
        finished - (tonumber(job.startedAt) or finished))
    runtime.lastPassDuration = tonumber(job.activeSeconds) or 0
    if completed then runtime.passesCompleted = runtime.passesCompleted + 1 end
    local newer = job.stale == true or (tonumber(job.skippedChanged) or 0) > 0
        or job.dpsRevision ~= CurrentDpsRevision()
        or job.revisionSource ~= RevisionSource()
    -- A pass that could not finish (publication refused, cursor lost) is
    -- retried by the same bounded follow-up; Request starts nothing while the
    -- catalog authority is exhausted.
    if newer or not completed then
        if completed then runtime.stalePasses = runtime.stalePasses + 1 end
        ScheduleFollowUp()
    else
        runtime.followUpPending = false
    end
end

function Repair.Pump(limit)
    if not active then return true end
    limit = math.max(1,math.min(tonumber(limit) or BATCH_SIZE,BATCH_SIZE))
    runtime.pumps = runtime.pumps + 1
    local work = 0
    local pumping, pumpedAt = active, Clock()
    local worked = false
    while active and work < limit do
        work = work + 1
        if active.phase == "catalog-pending" then
            -- Settle the retained operation before a revision restart can
            -- replace its owner. Start the next operation on a later turn.
            CompletePendingCatalog(active)
            break
        end
        local catalog = Nexus.BuildCatalog
        local root = catalog and type(catalog.RootState) == "function"
            and catalog.RootState() or nil
        if type(root) == "table" and root.candidate == true then break end
        worked = true
        if active.database ~= NexusDB then
            -- The saved root was replaced: this pass's scope and progress
            -- record belong to the old one. It is abandoned; nothing is
            -- stamped, and the one follow-up starts over on the current root.
            RollbackRejected(active)
            runtime.failures = runtime.failures + 1
            runtime.lastReason = "SOURCE_DRIFT"
            active = nil;runtime.pending = false
            runtime.lastPassFinishedAt = Clock()
            ScheduleFollowUp()
            break
        end
        -- A newer DPS revision no longer discards the pass: its captured scope
        -- still completes, each candidate is revalidated before a write, and
        -- one follow-up pass covers what changed.
        if active.dpsRevision ~= CurrentDpsRevision() then active.stale = true end
        if active.phase == "classify"
            and type(Nexus.DpsCapture.LegacyQualificationCursorSourceCurrent) == "function"
            and not Nexus.DpsCapture.LegacyQualificationCursorSourceCurrent(active.cursor) then
            -- The DPS store was replaced after the scan (possibly without a
            -- DPS revision): no captured row can be revalidated any more.
            -- Start over on the current store instead of skipping them all.
            local database = active.database
            RollbackRejected(active)
            runtime.restarts = runtime.restarts + 1
            active = NewJob(database, "restart", true, false)
            runtime.pending = active ~= nil
            if not active then runtime.failures = runtime.failures + 1 end
            break
        end
        if active.phase == "scan" then
            local item, done, err = Nexus.DpsCapture.LegacyQualificationCursorNext(
                active.cursor)
            if err then
                -- The DPS store or revision owner was replaced: the captured
                -- scope no longer describes the stored rows. Start over.
                local database = active.database
                RollbackRejected(active)
                runtime.restarts = runtime.restarts + 1
                active = NewJob(database, "restart", true, false)
                runtime.pending = active ~= nil
                if not active then runtime.failures = runtime.failures + 1 end
                break
            end
            if item then AddCandidate(active, item) end
            if done then
                local result = Nexus.DpsCapture.LegacyQualificationCursorResult(
                    active.cursor)
                if not result then
                    runtime.failures=runtime.failures+1
                    runtime.lastReason="cursor-incomplete"
                    active=nil;runtime.pending=false
                    runtime.lastPassFinishedAt=Clock()
                    ScheduleFollowUp()
                    break
                end
                runtime.scanned = runtime.scanned + result.scanned
                active.phase, active.pairKey = "classify", nil
            end
        else
            local fingerprint, pair = next(active.pairs, active.pairKey)
            active.pairKey = fingerprint
            if fingerprint == nil then
                local completed = active
                local ok, why = Finish(completed)
                if not ok then
                    runtime.failures=runtime.failures+1
                    runtime.lastReason=tostring(why or "finish-failed")
                end
                active=nil;runtime.pending=false
                PassEnded(completed, ok == true)
                break
            else
                ClassifyPair(active, fingerprint, pair)
            end
        end
        local meta = active and Meta(active.database) or nil
        if meta then
            meta.cursorVersion=CURSOR_VERSION
            meta.inProgress=true
            meta.phase=active.phase
            meta.workUnits=(tonumber(meta.workUnits) or 0)+1
        end
    end
    runtime.workUnits=runtime.workUnits+work
    runtime.maxWork=math.max(runtime.maxWork,work)
    if worked and pumping.lastPumpAt then
        local interval = pumpedAt - pumping.lastPumpAt
        if interval > 0 and interval <= MAX_PUMP_INTERVAL then
            pumping.activeSeconds = (tonumber(pumping.activeSeconds) or 0) + interval
        end
    end
    pumping.lastPumpAt = pumpedAt
    return active == nil
end

local function ScheduledPump()
    local ok, done = pcall(Repair.Pump, BATCH_SIZE)
    if not ok then
        runtime.failures=runtime.failures+1
        runtime.lastReason="pump-failed"
        active=nil;runtime.pending=false
        error(done)
    end
    if done then return end
    local scheduler=Nexus.Scheduler
    local scheduled, why = scheduler and scheduler.After
        and scheduler.After(SCHEDULER_KEY,0,ScheduledPump)
    if not scheduled then
        runtime.failures=runtime.failures+1
        runtime.lastReason="schedule-failed"
        active=nil;runtime.pending=false
        error(why or "legacy repair scheduler unavailable")
    end
end

function Repair.Request(reason)
    runtime.requested=runtime.requested+1
    if active then runtime.coalesced=runtime.coalesced+1; return true,"coalesced" end
    local database=type(NexusDB)=="table" and NexusDB or nil
    if not database then return false,"database unavailable" end
    -- A read-only saved root is not repaired: the repair and its progress
    -- record are writes into that root.
    local readOnlyRoot=Nexus.MainInternals and Nexus.MainInternals.SavedRootReadOnlyV1
    if type(readOnlyRoot)=="function" and readOnlyRoot(database) then
        runtime.lastReason="read-only-saved-data"
        return true,"read-only"
    end
    -- An exhausted catalog authority refuses every write until a fresh
    -- session: a pass could only fail again, so none starts (fail closed, as
    -- before follow-ups existed). The catalog state is the observable cause.
    local catalog=Nexus.BuildCatalog
    local root=catalog and type(catalog.RootState)=="function"
        and catalog.RootState() or nil
    if type(root)=="table" and root.state=="AUTHORITY_GENERATION_EXHAUSTED" then
        runtime.followUpPending=false
        runtime.lastReason="GENERATION_EXHAUSTED"
        return true,"catalog-exhausted"
    end
    local meta,metaError=Meta(database)
    if not meta then return false,metaError end
    local revision=CurrentDpsRevision()
    -- Revisions are intentionally session-local. The durable value is useful
    -- for diagnostics/reload recovery, but only this module instance may use a
    -- completed revision as an in-session skip token. A fresh login performs
    -- one bounded idempotent pass instead of trusting a coincidentally equal
    -- counter from an older session.
    if runtime.completedDpsRevision ~= nil
        and completedSource == RevisionSource()
        and completedDatabase == database
        and tonumber(runtime.completedDpsRevision)==tonumber(revision)
        and meta.inProgress ~= true then
        runtime.followUpPending=false
        runtime.lastReason="current"
        return true,"current"
    end
    -- Fairness: a pass does not start straight after the previous one. The
    -- request is folded into the one scheduled follow-up instead.
    if reason ~= "follow-up" and runtime.lastPassFinishedAt ~= nil
        and Clock() < runtime.lastPassFinishedAt + FollowUpGap() then
        runtime.deferredRequests=runtime.deferredRequests+1
        local ok,scheduleWhy=ScheduleFollowUp()
        if not ok then return false,scheduleWhy end
        return true,"deferred"
    end
    local job,why=NewJob(database,reason,true,true)
    if not job then runtime.failures=runtime.failures+1; return false,why end
    meta.cursorVersion=CURSOR_VERSION
    meta.inProgress=true
    meta.phase="scan"
    meta.workUnits=0
    meta.pendingWrites=job.changed
    meta.requestedDpsRevision=revision
    active=job;runtime.pending=true
    runtime.followUpPending=false
    runtime.lastPassStartedAt=job.startedAt
    local scheduler=Nexus.Scheduler
    local scheduled,scheduleError=scheduler and scheduler.After
        and scheduler.After(SCHEDULER_KEY,0,ScheduledPump)
    if not scheduled then
        runtime.failures=runtime.failures+1
        runtime.lastReason="schedule-failed"
        active=nil;runtime.pending=false
        return false,scheduleError or "legacy repair scheduler unavailable"
    end
    return true,"scheduled"
end

function Repair.Stats()
    return Copy(runtime)
end

function Repair.Init()
    local migration = Nexus and Nexus.LegacyDataMigration
    if migration and type(migration.BlocksDpsMigration) == "function"
        and migration.BlocksDpsMigration(NexusDB) then
        runtime.lastReason="legacy-data-migration-pending"
        return true,"deferred"
    end
    return Repair.Request("startup")
end
