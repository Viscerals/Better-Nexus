-- Nexus: core/DpsCapture.lua
--
-- Automatically records completed Training Dummy and Lich King sessions
-- from Details!. Results are keyed by the player's EXACT owned Echo set.
-- This means the panel can keep a personal best while a wishlist is still
-- incomplete, and community build leaderboards only compare players using
-- the exact Echo loadout published by that build.

Nexus = Nexus or {}
local Identity = assert(Nexus.Identity,
    "Nexus Identity must load before DpsCapture")
local DiagnosticHistory = Nexus.DiagnosticHistory
if not (DiagnosticHistory and type(DiagnosticHistory.New) == "function") then
    error("Nexus DiagnosticHistory must load before DpsCapture")
end
local DPS = {}
Nexus.DpsCapture = DPS

------------------------------------------------------------------------
-- Constants / state
------------------------------------------------------------------------

local SAMPLE_INTERVAL  = 5
local MIN_SESSION_SECS = {dummy=30,lk=20}
local MAX_LB_ENTRIES   = 1
local PROTOCOL_VERSION = 7
local VALID_CLASS = {
    WARRIOR=true, PALADIN=true, HUNTER=true, ROGUE=true, PRIEST=true,
    DEATHKNIGHT=true, SHAMAN=true, MAGE=true, WARLOCK=true, DRUID=true,
}
local CLASS_LABEL = {
    WARRIOR="Warrior", PALADIN="Paladin", HUNTER="Hunter", ROGUE="Rogue",
    PRIEST="Priest", DEATHKNIGHT="Death Knight", SHAMAN="Shaman", MAGE="Mage",
    WARLOCK="Warlock", DRUID="Druid",
}

local REJECTION_KEYS = {
    "duration", "owner_sender", "relay_authorization", "schema",
    "stale_record", "duplicate_not_better", "invalid_category",
    "integrity", "outside_request",
}
local rejectionStats = {}

-- Session-only responder decisions. These counters deliberately retain no
-- row identity or payload data. Terminal counters are one-per-row; queue and
-- wire deferrals are attempt counters because the same immutable candidate may
-- be retried after pressure clears.
local OUTBOUND_KEYS = {
    "considered", "eligible", "offered_direct", "offered_relay",
    "peer_current", "outside_bucket", "score", "duration",
    "owner_sender", "relay_authorization", "schema", "stale_record",
    "duplicate_not_better", "invalid_category", "integrity",
    "outside_request", "other", "queue_deferred", "wire_deferred",
}
local outboundStats = {}

local function ResetRejectionStats()
    for _, key in ipairs(REJECTION_KEYS) do rejectionStats[key] = 0 end
end

local function ResetOutboundStats()
    for _, key in ipairs(OUTBOUND_KEYS) do outboundStats[key] = 0 end
end

local function NoteOutbound(reason, amount)
    reason = outboundStats[reason] ~= nil and reason or "other"
    amount = math.max(0, math.floor(tonumber(amount) or 1))
    outboundStats[reason] = outboundStats[reason] + amount
end

local function RejectReceive(reason)
    if rejectionStats[reason] ~= nil then
        rejectionStats[reason] = rejectionStats[reason] + 1
    end
    return false
end

function DPS.MinimumDuration(category)
    return MIN_SESSION_SECS[category]
end

function DPS.IsDurationEligible(category, duration)
    local minimum = MIN_SESSION_SECS[category]
    local value = tonumber(duration)
    return minimum ~= nil and type(value) == "number" and value == value
        and value < math.huge and value > -math.huge and value >= minimum
end

function DPS.NoteReceiveRejection(reason)
    return RejectReceive(reason)
end

function DPS.RejectionStats()
    local out = {}
    for _, key in ipairs(REJECTION_KEYS) do out[key] = rejectionStats[key] end
    return out
end

function DPS.OutboundStats()
    local out = {}
    for _, key in ipairs(OUTBOUND_KEYS) do out[key] = outboundStats[key] end
    return out
end

ResetRejectionStats()
ResetOutboundStats()

local function NormalizeClass(class)
    class = type(class) == "string" and class:upper() or nil
    return class and VALID_CLASS[class] and class or nil
end

local Adapter, Sync
-- Response cursors may be retained by Sync across module reinitialization.
-- A monotonic binding generation prevents a same-digest/same-revision profile
-- replacement from replaying candidates captured from the previous store.
local responseGeneration = 0
local inCombat         = false
local sessionStart     = 0
local latestDps        = 0
local peakDps          = 0
local sampleTicker     = 0
local lastTargetGUID   = nil
local lastTargetName   = nil
local sessionCategory  = nil
local MAX_DEBUG_LINES   = 120
local DEBUG_TRIM_AT     = 150
local DEBUG_TEXT_BYTES  = 2048
local debugHistory      = DiagnosticHistory.New({
    cap=MAX_DEBUG_LINES, trimAt=DEBUG_TRIM_AT,
    maxTextBytes=DEBUG_TEXT_BYTES,
})

local TRAINING_DUMMIES = {
    [36476] = true, [36855] = true, [32541] = true, [30527] = true,
    [31144] = true, [16218] = true, [2673] = true,
}
local LICH_KING_NPCS = { [36597] = true, [72523] = true, [36730] = true }


local function Debug(msg)
    local stamp = (date and date("%H:%M:%S")) or tostring((GetTime and GetTime()) or 0)
    debugHistory.Append("[" .. DiagnosticHistory.SafeText(stamp, 32) .. "] "
        .. DiagnosticHistory.SafeText(msg, DEBUG_TEXT_BYTES))
end

function DPS.ClearDebugLog()
    debugHistory.Clear()
end

function DPS.GetDebugLog()
    local out = { "Nexus DPS capture log", "" }
    local debugLog = debugHistory.Snapshot()
    if #debugLog == 0 then
        out[#out + 1] = "No DPS activity logged this session."
    else
        for i = 1, #debugLog do out[#out + 1] = debugLog[i] end
    end
    return table.concat(out, "\n")
end

function DPS.DebugLogStats()
    return debugHistory.Stats()
end

------------------------------------------------------------------------
-- Saved variables
------------------------------------------------------------------------

local transientDb, transientDbOwner, dbPolicyOwner, dbPolicyReadOnly
local function DB()
    NexusDB = NexusDB or {}
    if dbPolicyOwner ~= NexusDB then
        local catalog = Nexus and Nexus.BuildCatalog
        local status = catalog and type(catalog.Status) == "function"
            and catalog.Status() or nil
        dbPolicyOwner = NexusDB
        dbPolicyReadOnly = type(status) == "table"
            and status.readOnly == true
    end
    if dbPolicyReadOnly then
        if transientDbOwner ~= NexusDB then
            transientDbOwner, transientDb = NexusDB, {}
        end
        return transientDb
    end
    if type(NexusDB.dpsCapture) == "table" then
        return NexusDB.dpsCapture
    end
    NexusDB.dpsCapture = {}
    return NexusDB.dpsCapture
end

local function StorageReadOnly()
    -- Refresh the cached policy without exposing or mutating any future-owned
    -- SavedVariables table. DB returns the fixed transient read view here.
    DB()
    return dbPolicyReadOnly == true
end

local function BumpDps(reason, detail)
    local revisions = Nexus and Nexus.Revisions
    if revisions and type(revisions.Advance) == "function" then
        detail = type(detail) == "table" and detail or {scope="all"}
        if detail.reason == nil then detail.reason = reason end
        pcall(revisions.Advance, revisions.DPS_CHANGED, detail)
    end
end

local function RequestDataViewRefresh()
    local refresh = Nexus and Nexus.ViewRefresh
    if refresh and type(refresh.Request) == "function" then
        return refresh.Request()
    end
    if Nexus.CommunityBuilds and Nexus.CommunityBuilds.Refresh then
        return pcall(Nexus.CommunityBuilds.Refresh)
    end
end

local function Catalog()
    return Nexus and Nexus.BuildCatalog
end

local function CatalogGet(id)
    local catalog = Catalog()
    if not (catalog and catalog.Get) then return nil end
    return catalog.Get(id)
end

local function CatalogAll()
    local catalog = Catalog()
    return catalog and catalog.All and catalog.All() or {}
end

local function CatalogPut(build)
    local catalog = Catalog()
    return catalog and catalog.Put and catalog.Put(build) or false
end

local ReferenceEvidence, StoredEchoes

-- Version 4 stores only the data the feature needs:
-- personalBest[fingerprint][category] = this character's highest pull
-- buildBest[fingerprint][category]    = highest known pull worldwide
-- Older per-player leaderboard rows are migrated once on access.
local function PersonalBestStore()
    local db = DB()
    db.personalBest = db.personalBest or {}
    return db.personalBest
end

local function BuildBestStore()
    local db = DB()
    db.buildBest = db.buildBest or {}
    return db.buildBest
end

-- Public mesh state is bounded to one winning loadout per character and
-- encounter. The row still carries the exact loadout fingerprint/build id,
-- but weaker loadouts from the same character are replaced.
local function CharacterBestStore()
    local db = DB()
    db.characterBest = db.characterBest or { dummy = {}, lk = {} }
    db.characterBest.dummy = db.characterBest.dummy or {}
    db.characterBest.lk = db.characterBest.lk or {}
    return db.characterBest
end

local function PlayerKey(name)
    return Identity.PlayerKey(name) or "invalid"
end

-- Durable public records are keyed by account character whenever verified
-- realm metadata exists. Realm-less legacy rows retain their historical
-- player-only key until a later direct-owner record safely enriches them.
local function CharacterKey(name, ownerKey, realm)
    local canonical = Identity.CanonicalOwnerKey(ownerKey)
    if canonical and not canonical:match("@unknown$") then return canonical end
    if type(realm) == "string" and realm ~= ""
        and realm:lower() ~= "unknown" then
        local inferred = Identity.OwnerKey(name, realm)
        if inferred and not inferred:match("@unknown$") then return inferred end
    end
    return PlayerKey(name)
end

local function CurrentRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then realm = GetRealmName and GetRealmName() end
    return tostring(realm or "unknown"):lower():gsub("%s+", "")
end

local function OwnerKey(name, realm)
    return Identity.OwnerKey(name, realm or CurrentRealm())
end

local function CurrentCharacterKey(name)
    name = name or ((UnitName and UnitName("player")) or "?")
    return CharacterKey(name, OwnerKey(name), CurrentRealm())
end

local function SameLocalCharacter(row, localName)
    if type(row) ~= "table" then return false end
    localName = localName or ((UnitName and UnitName("player")) or "?")
    local localKey = CurrentCharacterKey(localName)
    return localKey ~= "invalid" and DPS.VerifiedOwnerKey(row) == localKey
end

-- Repair legacy class metadata only for the exact character currently logged
-- in. SavedVariables are account-wide, so no other player's row is inferred.
local function RepairCurrentCharacterClass()
    if not (UnitName and UnitClass) then return false end
    local me = tostring(UnitName("player") or "")
    local _, token = UnitClass("player")
    local class = NormalizeClass(token)
    if me == "" or not class then return false end

    local realm = CurrentRealm()
    local localOwner = OwnerKey(me, realm)
    if not localOwner then return false end
    local changed = false
    local builds = CatalogAll()
    local character = CharacterBestStore()
    local personal = PersonalBestStore()

    for _, category in ipairs({ "dummy", "lk" }) do
        for _, row in pairs(character[category] or {}) do
            if row and DPS.VerifiedOwnerKey(row) == localOwner then
                if row.class ~= class then row.class = class; changed = true end
                local prow = row.fingerprint and personal[row.fingerprint]
                    and personal[row.fingerprint][category]
                if prow and DPS.VerifiedOwnerKey(prow) == localOwner then
                    if prow.class ~= class then prow.class = class; changed = true end
                    if not prow.realm then
                        prow.realm = realm
                        changed = true
                    end
                end

                local build = row.buildId and builds[row.buildId]
                if build and build.autoDps then
                    if Identity.VerifiedOwnerKey(build) == localOwner then
                        local buildChanged = false
                        if build.class ~= class then build.class = class; buildChanged = true end
                        local title = tostring(build.title or "")
                        if title:match("^[%a%s]+ Record Loadout$") then
                            local corrected = (CLASS_LABEL[class] or class) .. " Record Loadout"
                            if title ~= corrected then build.title = corrected; buildChanged = true end
                        end
                        if buildChanged then
                            local now = (time and time()) or 0
                            local old = tonumber(build.lastModified or build.postedAt) or 0
                            build.lastModified = now > old and now or old + 1
                            CatalogPut(build)
                            changed = true
                        end
                    end
                end
            end
        end
    end
    return changed
end

local legacyMigratedOwner
local function BetterRow(candidate, existing)
    if not existing then return true end
    local nd = math.floor(tonumber(candidate and candidate.dps) or 0)
    local od = math.floor(tonumber(existing and existing.dps) or 0)
    if nd ~= od then return nd > od end
    local nt = tonumber(candidate and candidate.ts) or 0
    local ot = tonumber(existing and existing.ts) or 0
    if nt > 0 and ot > 0 and nt ~= ot then return nt < ot end
    return tostring(candidate and candidate.fingerprint or "") < tostring(existing and existing.fingerprint or "")
end

local function MigrateLegacyLeaderboard()
    local root = type(NexusDB) == "table" and NexusDB or nil
    if legacyMigratedOwner == root then return false end
    local coordinator = Nexus and Nexus.LegacyDataMigration
    if coordinator and type(coordinator.BlocksDpsMigration) == "function"
        and coordinator.BlocksDpsMigration(root) then
        return false
    end
    if coordinator and type(coordinator.IsComplete) == "function"
        and coordinator.IsComplete(root)
        and type(root and root.legacyDataMigration) == "table" then
        legacyMigratedOwner = root
        return false
    end
    local db = DB()
    local me = (UnitName and UnitName("player")) or "?"
    local personal = PersonalBestStore()
    local character = CharacterBestStore()
    local changed = false

    -- Normalize existing rows to realm-qualified keys where their own
    -- metadata proves the identity. Remove sources before merging targets so
    -- a same-name character on another realm cannot overwrite its peer.
    for _, category in ipairs({ "dummy", "lk" }) do
        local bucket = character[category]
        if type(bucket) == "table" then
            local toMerge = {}
            for key, row in pairs(bucket) do
                local target = CharacterKey(
                    type(row) == "table" and row.player or key,
                    type(row) == "table" and row.ownerKey or nil,
                    type(row) == "table" and row.realm or nil)
                if key ~= target then
                    toMerge[#toMerge + 1] = {
                        source=key,target=target,row=row,
                    }
                end
            end
            for _, item in ipairs(toMerge) do bucket[item.source] = nil end
            for _, item in ipairs(toMerge) do
                if BetterRow(item.row, bucket[item.target]) then
                    bucket[item.target] = item.row
                    changed = true
                end
                changed = true
            end
        end
    end

    local function Consider(row, fingerprint, category, fallbackPlayer)
        if type(row) ~= "table" or not tonumber(row.dps) then return end
        if not row.player then
            row.player = fallbackPlayer or "?"
            changed = true
        end
        if not row.fingerprint and fingerprint then
            row.fingerprint = fingerprint
            changed = true
        end
        if ReferenceEvidence(row) then changed = true end
        if SameLocalCharacter(row, me) and fingerprint then
            personal[fingerprint] = personal[fingerprint] or {}
            if BetterRow(row, personal[fingerprint][category]) then
                personal[fingerprint][category] = row
                changed = true
            end
        end
        local bucket = character[category]
        if bucket then
            local pk = CharacterKey(row.player, row.ownerKey, row.realm)
            if BetterRow(row, bucket[pk]) then
                bucket[pk] = row
                changed = true
            end
        end
    end

    local legacy = db.leaderboard
    if type(legacy) == "table" then
        for fingerprint, categories in pairs(legacy) do
            if type(categories) == "table" then
                for category, entries in pairs(categories) do
                    if type(entries) == "table" then
                        for player, row in pairs(entries) do Consider(row, fingerprint, category, player) end
                    end
                end
            end
        end
        db.leaderboard = nil
    end

    local oldGlobal = db.buildBest
    if type(oldGlobal) == "table" then
        for fingerprint, categories in pairs(oldGlobal) do
            if type(categories) == "table" then
                for _, category in ipairs({ "dummy", "lk" }) do
                    Consider(categories[category], fingerprint, category)
                end
            end
        end
    end
    if changed then BumpDps("legacy DPS migrated") end
    legacyMigratedOwner = root
    return changed
end

function DPS.MigrateLegacyLeaderboard()
    return MigrateLegacyLeaderboard()
end

------------------------------------------------------------------------
-- Echo fingerprints
------------------------------------------------------------------------

local function NormalizeEchoes(source)
    if type(source) ~= "table" then return nil end
    local counts = {}
    for _, e in ipairs(source) do
        -- Locked perks must never alter a wishlist/build fingerprint (see
        -- SnapshotEchoes below) -- otherwise a 79-Echo completed build is
        -- captured under an 85-Echo key and can never be found by the panel
        -- or its posted community build. Applied here, centrally, so every
        -- caller (including a build's stored `echoes`, which may now itself
        -- carry `.locked` entries -- see CommunityBuilds.EnsureDpsBuildForEchoes)
        -- gets this exclusion automatically and consistently.
        if not (e and e.locked) then
            local spellId = tonumber(e and (e.spellId or e.id))
            local count = tonumber(e and (e.count or e.stacks or e.stack)) or 1
            if spellId and count > 0 then
                counts[spellId] = (counts[spellId] or 0) + count
            end
        end
    end
    local snap = {}
    for spellId, count in pairs(counts) do
        snap[#snap + 1] = { spellId = spellId, count = count }
    end
    table.sort(snap, function(a, b) return a.spellId < b.spellId end)
    return #snap > 0 and snap or nil
end

local function SnapshotEchoes()
    if not (Adapter and Adapter.Owned) then return nil end
    local owned = Adapter.Owned()
    if not owned or type(owned.bySpell) ~= "table" then return nil end

    -- Adapter.Owned() reflects GetGrantedPerks(), a THIS-RUN-only concept
    -- that resets at every level-1 boundary -- an Echo equipped from an
    -- earlier run that was never re-rolled this run wouldn't show as owned
    -- here at all, even though it's sitting right in the active loadout.
    -- Same gap TryAutoLock (core/Main.lua) already had to work around for
    -- lock automation. Left unfixed here, every DPS-record capture (and so
    -- every leaderboard/community-build entry auto-created from one, via
    -- CommunityBuilds.EnsureDpsBuildForEchoes) silently undercounts the
    -- player's actual Echoes -- this is why historical leaderboard builds
    -- can be missing entries that were never actually missing in-game.
    local ownedBySpell = {}
    for spellId, count in pairs(owned.bySpell) do ownedBySpell[spellId] = tonumber(count) or 0 end
    local slots = Adapter.Slots and Adapter.Slots()
    local activeIdx = slots and tonumber(slots.activeSlot)
    local activeRow = activeIdx and activeIdx > 0 and slots.bySlot and slots.bySlot[activeIdx]
    if activeRow and type(activeRow.echoes) == "table" then
        for _, e in ipairs(activeRow.echoes) do
            local eid = tonumber(e and e.spellId)
            if eid then
                local n = tonumber(e.stacks) or 1
                if n > (tonumber(ownedBySpell[eid]) or 0) then ownedBySpell[eid] = n end
            end
        end
    end

    -- Locked perks are permanent baseline Echoes supplied outside the roll
    -- build. They must not alter a wishlist/build fingerprint; otherwise a
    -- 79-Echo completed build is captured under an 85-Echo key and can never
    -- be found by the panel or its posted community build.
    local lockedBySpell = {}
    if Adapter.LockedOwned then
        local locked = Adapter.LockedOwned()
        if locked and type(locked.bySpell) == "table" then
            lockedBySpell = locked.bySpell
        end
    end

    local source = {}
    for spellId, count in pairs(ownedBySpell) do
        local tracked = math.max(0, count - (tonumber(lockedBySpell[spellId]) or 0))
        if tracked > 0 then
            source[#source + 1] = { spellId = spellId, count = tracked }
        end
    end
    return NormalizeEchoes(source)
end

local function EchoKey(snap)
    if not snap or #snap == 0 then return nil end
    local out = {}
    for _, e in ipairs(snap) do
        out[#out + 1] = tostring(e.spellId) .. "x" .. tostring(e.count)
    end
    return table.concat(out, ",")
end


local function EchoHashFromKey(key)
    if type(key) ~= "string" or key == "" then return nil end
    local h = 5381
    for i = 1, #key do h = ((h * 33) + key:byte(i)) % 2147483648 end
    return string.format("%x", h)
end

function DPS.GetEchoHash(echoes)
    return EchoHashFromKey(EchoKey(NormalizeEchoes(echoes)))
end

local function LockedKey(echoes)
    return EchoKey(NormalizeEchoes(echoes)) or "0"
end

ReferenceEvidence = function(row)
    local compaction = Nexus and Nexus.DataCompaction
    if compaction and type(compaction.Enabled) == "function"
        and compaction.Enabled(NexusDB)
        and type(compaction.CompactDpsRow) == "function" then
        local ok, changed = pcall(compaction.CompactDpsRow, row)
        if ok then return changed == true end
    end
    local evidence = Nexus and Nexus.LoadoutEvidence
    if evidence and type(evidence.ReferenceDpsRow) == "function" then
        local ok, changed = pcall(evidence.ReferenceDpsRow, row)
        return ok and changed == true
    end
    return false
end

StoredEchoes = function(row, locked)
    if type(row) ~= "table" then return nil end
    local evidence = Nexus and Nexus.LoadoutEvidence
    if evidence and type(evidence.ResolveDpsEchoes) == "function" then
        local ok, echoes = pcall(evidence.ResolveDpsEchoes, row, locked == true)
        if ok and type(echoes) == "table" then return echoes end
    end
    return NormalizeEchoes(row[locked and "lockedEchoes" or "echoes"])
end

-- Locked perks can arrive from the server after a combat record is committed.
-- Backfill this character's public rows once the API becomes ready so the
-- metadata is not permanently lost just because GetLockedPerks was late.
local function BackfillLocalLockedRows()
    if not (Adapter and Adapter.LockedOwned) then return false end
    local locked = Adapter.LockedOwned()
    local snap = NormalizeEchoes(locked and locked.bySpell and (function()
        local out = {}
        for spellId, count in pairs(locked.bySpell) do
            out[#out + 1] = { spellId = spellId, count = count }
        end
        return out
    end)() or nil)
    if not snap then return false end

    local localName = (UnitName and UnitName("player")) or "?"
    local me = CurrentCharacterKey(localName)
    local legacyMe = PlayerKey(localName)
    local changed = false
    local changedRows = {}
    for _, category in ipairs({ "dummy", "lk" }) do
        local rows = CharacterBestStore()[category]
        local row = rows[me] or rows[legacyMe]
        if row and LockedKey(StoredEchoes(row, true)) ~= LockedKey(snap) then
            row.lockedEchoes = snap
            ReferenceEvidence(row)
            changed = true
            changedRows[#changedRows + 1] = row
        end
    end
    -- Keep the established bucket-hash format compatible with older clients.
    -- Instead of changing the hash schema, proactively rebroadcast only the
    -- locally enriched winning row. Updated peers can merge this metadata into
    -- an equal record; older peers still receive all core DPS/build data.
    if changed and Sync and Sync.BroadcastDpsRecord then
        for _, row in ipairs(changedRows) do
            pcall(Sync.BroadcastDpsRecord, row)
        end
    end
    return changed
end

local migratedLockedBaseline = false
local LOCKED_MIGRATION_VERSION = 1

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[DeepCopy(key, seen)] = DeepCopy(child, seen)
    end
    return copy
end

function DPS.MaterializeRecord(row)
    if type(row) ~= "table" then return nil end
    local evidence = Nexus and Nexus.LoadoutEvidence
    if evidence and type(evidence.ResolveDpsRow) == "function" then
        local ok, resolved = pcall(evidence.ResolveDpsRow, row)
        if ok and type(resolved) == "table" then return resolved end
    end
    return DeepCopy(row)
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

local function MigrateLocalLockedBaseline()
    if migratedLockedBaseline then return end
    local db = DB()
    if (tonumber(db.lockedMigrationVersion) or 0)
        >= LOCKED_MIGRATION_VERSION then
        migratedLockedBaseline = true
        return
    end
    local source = db.lockedMigrationSource
    if type(source) == "table" then
        local beforeState = {
            personalBest=DeepCopy(PersonalBestStore()),
            buildBest=DeepCopy(BuildBestStore()),
            characterBest=DeepCopy(CharacterBestStore()),
        }
        db.personalBest = DeepCopy(source.personalBest or {})
        db.buildBest = DeepCopy(source.buildBest or {})
        db.characterBest = DeepCopy(source.characterBest
            or { dummy={}, lk={} })
        db.lockedMigrationSource = nil
        local changed = not DeepEqual(beforeState.personalBest, PersonalBestStore())
            or not DeepEqual(beforeState.buildBest, BuildBestStore())
            or not DeepEqual(beforeState.characterBest, CharacterBestStore())
        if changed then BumpDps("locked migration source restored") end
    end

    -- Exact rollback is independent of current ownership readiness. Keep only
    -- the migration completion stamp gated so an unsynced restart cannot expose
    -- partial rows while still preserving the established retry lifecycle.
    local locked = Adapter and Adapter.LockedOwned and Adapter.LockedOwned()
    if not (locked and locked.synced == true) then
        return
    end

    -- Reconcile legacy stores only after an interrupted pass has restored its
    -- immutable source. Partial live rows must never create pooled evidence,
    -- copied aliases, or revision churn before they are discarded.
    MigrateLegacyLeaderboard()
    -- Current durable rows do not record whether locked evidence was captured
    -- with the pull or attached later from the current login. Inline and direct
    -- references therefore prove content integrity, not historical provenance.
    -- Preserve the restored source exactly and only complete the version stamp.
    db.lockedMigrationSource = nil
    db.lockedMigrationVersion = LOCKED_MIGRATION_VERSION
    migratedLockedBaseline = true
end

local function BuildSnapshot(build)
    return build and NormalizeEchoes(build.echoes)
end

local function FindMatchingBuild(snap)
    local key = EchoKey(snap)
    if not key then return nil, nil end
    local catalog = Catalog()
    if catalog and type(catalog.FindExactFingerprint) == "function" then
        return catalog.FindExactFingerprint(key)
    end
    -- Compatibility fallback for older injected/test catalog facades. The
    -- packaged owner always provides the indexed path above.
    local builds = CatalogAll()
    local fallbackId, fallbackBuild
    for id, build in pairs(builds) do
        if (build.fingerprint or EchoKey(BuildSnapshot(build))) == key then
            -- Prefer a player-authored build with its real title/description.
            -- Auto-generated record pages are only a fallback when no posted
            -- build exists for the exact same Echo IDs and stack quantities.
            if not build.autoDps then return id, build end
            fallbackId, fallbackBuild = fallbackId or id, fallbackBuild or build
        end
    end
    return fallbackId, fallbackBuild
end

local function BuildKey(buildId)
    local build = CatalogGet(buildId)
    if not build then return nil, nil end
    local key = build.fingerprint or EchoKey(BuildSnapshot(build))
    if not key and build.fingerprintHash then key = "@"..tostring(build.fingerprintHash) end
    return key, build
end

local function RelationshipFingerprint(record)
    if type(record) ~= "table" then return nil end
    return record.fingerprint or EchoKey(BuildSnapshot(record))
end

local function VerifiedBuildRelation(row, buildId)
    local ownerKey = DPS.VerifiedOwnerKey(row)
    local build = buildId and CatalogGet(buildId) or nil
    if not ownerKey or type(build) ~= "table"
        or Identity.SavedMirrorKind(build) ~= "ordinary"
        or Identity.VerifiedOwnerKey(build) ~= ownerKey then
        return nil, nil
    end
    local rowFingerprint = RelationshipFingerprint(row)
    local buildFingerprint = RelationshipFingerprint(build)
    if rowFingerprint and buildFingerprint
        and tostring(rowFingerprint) ~= tostring(buildFingerprint) then
        return nil, nil
    end
    return buildId, build
end

------------------------------------------------------------------------
-- Target detection (3.3.5-compatible)
------------------------------------------------------------------------

local function NpcIdFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    -- Modern/private-core textual GUID.
    local id = guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
    if id then return tonumber(id) end
    -- Some 3.3.5 cores expose a simple Creature-<entry>-... form.
    id = guid:match("[Cc]reature[^%d]+(%d+)")
    return tonumber(id)
end

local function ClassifyTarget(guid, name)
    local npcId = NpcIdFromGUID(guid)
    if npcId then
        if TRAINING_DUMMIES[npcId] then return "dummy" end
        if LICH_KING_NPCS[npcId] then return "lk" end
    end
    local n = type(name) == "string" and name:lower() or ""
    if n:find("training dummy", 1, true) or n:find("target dummy", 1, true) then
        return "dummy"
    end
    if n == "the lich king" or n:find("lich king", 1, true) then
        return "lk"
    end
    return nil
end

local function RememberTarget()
    if UnitExists and not UnitExists("target") then return end
    local guid = UnitGUID and UnitGUID("target") or nil
    local name = UnitName and UnitName("target") or nil
    local category = ClassifyTarget(guid, name)

    -- Once a supported encounter has been seen during this combat, keep it.
    -- Players commonly deselect a training dummy or target something else
    -- before PLAYER_REGEN_ENABLED fires; that must not erase the capture.
    if category then
        sessionCategory = category
        if guid then lastTargetGUID = guid end
        if name and name ~= "" then lastTargetName = name end
    elseif not sessionCategory then
        if guid then lastTargetGUID = guid end
        if name and name ~= "" then lastTargetName = name end
    end
end

------------------------------------------------------------------------
-- Details! integration
------------------------------------------------------------------------

function DPS.IsDetailsAvailable()
    return Details ~= nil and (type(Details.GetCurrentCombat) == "function"
        or type(Details.GetCombat) == "function")
end

local function ActorDps(combat)
    if not combat then return nil end
    local player = UnitName and UnitName("player")
    if not player then return nil end
    local result
    pcall(function()
        local attrDmg = DETAILS_ATTRIBUTE_DAMAGE or 1
        local actor = combat.GetActor and combat:GetActor(attrDmg, player)
        if not actor and player:find("%-", 1, true) then
            actor = combat:GetActor(attrDmg, player:match("^[^-]+"))
        end
        if not actor then return end
        local total = tonumber(actor.total)
        if not total or total <= 0 then return end
        local activeTime = actor.Tempo and tonumber(actor:Tempo())
        if activeTime and activeTime > 0 then
            result = total / activeTime
            return
        end
        local combatTime = combat.GetCombatTime and tonumber(combat:GetCombatTime())
        if combatTime and combatTime > 0 then result = total / combatTime end
    end)
    return result
end

local function ReadDetailsDps()
    if not DPS.IsDetailsAvailable() then return nil end
    local current
    pcall(function()
        if Details.GetCurrentCombat then current = Details:GetCurrentCombat() end
    end)
    local value = ActorDps(current)
    if value and value > 0 then return value end

    -- On some 3.3.5 Details builds the completed segment moves to history
    -- before PLAYER_REGEN_ENABLED. Only use history when current is empty;
    -- never take the larger of two unrelated segments.
    local previous
    pcall(function()
        if Details.GetCombat then previous = Details:GetCombat(1) end
    end)
    return ActorDps(previous)
end

------------------------------------------------------------------------
-- Leaderboard access
------------------------------------------------------------------------

local function StoreRow(store, key, category, create)
    if not key then return nil end
    if create then
        store[key] = store[key] or {}
    end
    return store[key] and store[key][category] or nil
end

local function SetStoreRow(store, key, category, row)
    ReferenceEvidence(row)
    store[key] = store[key] or {}
    store[key][category] = row
end

local function RowMatchesBuild(row, buildId, key, hash)
    if type(row) ~= "table" then return false end
    local rowKey = row.fingerprint
    local rowHash = row.loadoutHash or (rowKey and EchoHashFromKey(rowKey))
    if buildId and row.buildId == buildId then
        if key and rowKey and rowKey ~= key then return false end
        if hash and rowHash and rowHash ~= hash then return false end
        return true
    end
    if key and rowKey then return rowKey == key end
    return hash and rowHash == hash or false
end

local function GlobalForBuild(buildId, key, category)
    MigrateLegacyLeaderboard()
    local hash = EchoHashFromKey(key)
    local best
    local bucket = CharacterBestStore()[category] or {}
    for _, row in pairs(bucket) do
        if DPS.IsDurationEligible(category, row and row.duration)
            and RowMatchesBuild(row, buildId, key, hash)
            and BetterRow(row, best) then
            best = row
        end
    end
    return best
end

-- Community projections ask for two categories for every visible catalog
-- candidate. Scanning every character row for each of those lookups made one
-- refresh O(builds * DPS rows). Keep a revision-scoped identity index instead:
-- one bounded store walk after represented DPS changes, then only exact
-- candidate checks until the next revision.
local identityIndex = {
    initialized=false, revisionSource=nil, observedRevision=nil,
    categories={dummy=nil,lk=nil}, eligibility={},
    stats={rebuilds=0,rowsScanned=0,indexedRows=0,lookups=0,
        candidateChecks=0,eligibilityReads=0,intersections=0},
}

local function IdentityPart(value)
    if value == nil then return nil end
    return type(value) .. ":" .. tostring(value)
end

local function AddIdentityRow(map, value, row)
    local key = IdentityPart(value)
    if not key then return end
    local rows = map[key]
    if not rows then rows = {}; map[key] = rows end
    rows[#rows + 1] = row
end

local function NewIdentityCategory()
    return {buildId={},fingerprint={},hash={}}
end

local function CurrentDpsRevision()
    local revisions = Nexus and Nexus.Revisions
    local revision = revisions and type(revisions.Get) == "function"
        and revisions.Get(revisions.DPS_CHANGED) or nil
    return revisions, revision
end

local function RebuildIdentityIndex()
    MigrateLegacyLeaderboard()
    local categories = {dummy=NewIdentityCategory(),lk=NewIdentityCategory()}
    local bestByFingerprint = {dummy={},lk={}}
    local scanned, indexed = 0, 0
    local store = CharacterBestStore()
    for _, category in ipairs({"dummy", "lk"}) do
        local target = categories[category]
        for _, row in pairs(store[category] or {}) do
            scanned = scanned + 1
            if type(row) == "table"
                and DPS.IsDurationEligible(category, row.duration) then
                local fingerprint = row.fingerprint
                local hash = row.loadoutHash
                    or (fingerprint and EchoHashFromKey(fingerprint))
                AddIdentityRow(target.buildId, row.buildId, row)
                AddIdentityRow(target.fingerprint, fingerprint, row)
                AddIdentityRow(target.hash, hash, row)
                local value = tonumber(row.dps) or 0
                if type(fingerprint) == "string" and fingerprint ~= ""
                    and value == value and value < math.huge and value > 0 then
                    local previous = bestByFingerprint[category][fingerprint] or 0
                    if value > previous then
                        bestByFingerprint[category][fingerprint] = value
                    end
                end
                indexed = indexed + 1
            end
        end
    end
    local eligibility = {}
    for fingerprint, dummy in pairs(bestByFingerprint.dummy) do
        local lk = bestByFingerprint.lk[fingerprint]
        if lk and dummy > 0 and lk > 0 then
            eligibility[fingerprint] = {
                dummy=dummy,lk=lk,best=math.max(dummy,lk),
                average=(dummy+lk)/2,count=2,
            }
        end
    end
    identityIndex.categories = categories
    identityIndex.eligibility = eligibility
    identityIndex.initialized = true
    identityIndex.revisionSource, identityIndex.observedRevision =
        CurrentDpsRevision()
    identityIndex.stats.rebuilds = identityIndex.stats.rebuilds + 1
    identityIndex.stats.rowsScanned = identityIndex.stats.rowsScanned + scanned
    identityIndex.stats.indexedRows = indexed
    identityIndex.stats.intersections = identityIndex.stats.intersections + 1
end

local function EnsureIdentityIndex()
    local revisionSource, revision = CurrentDpsRevision()
    if not identityIndex.initialized
        or identityIndex.revisionSource ~= revisionSource
        or revision == nil
        or identityIndex.observedRevision ~= revision then
        RebuildIdentityIndex()
    end
end

local function AddIdentityCandidates(out, seen, rows)
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        if not seen[row] then
            seen[row] = true
            out[#out + 1] = row
        end
    end
end

local function IndexedGlobalForIdentity(buildId, key, hash, category)
    identityIndex.stats.lookups = identityIndex.stats.lookups + 1
    local best
    local index = identityIndex.categories[category]
        or NewIdentityCategory()
    local candidates, seen = {}, {}
    AddIdentityCandidates(candidates, seen,
        index.buildId[IdentityPart(buildId)])
    AddIdentityCandidates(candidates, seen,
        index.fingerprint[IdentityPart(key)])
    AddIdentityCandidates(candidates, seen,
        index.hash[IdentityPart(hash)])
    for _, row in ipairs(candidates) do
        identityIndex.stats.candidateChecks =
            identityIndex.stats.candidateChecks + 1
        if RowMatchesBuild(row, buildId, key, hash)
            and BetterRow(row, best) then
            best = row
        end
    end
    return best
end

local function GlobalForIdentity(buildId, key, hash, category)
    EnsureIdentityIndex()
    return IndexedGlobalForIdentity(buildId, key, hash, category)
end

local function GlobalForKey(key, category)
    return GlobalForBuild(nil, key, category)
end

local function PersonalForBuild(buildId, key, category)
    MigrateLegacyLeaderboard()
    local store = PersonalBestStore()
    local exact = StoreRow(store, key, category, false)
    if exact then return exact end

    -- A captured result may already be associated with the deterministic
    -- record page while the player is viewing their manual/uploaded copy of
    -- the same loadout. Resolve by build id or fingerprint hash as well as the
    -- raw table key so the build sheet never loses a valid local record.
    local hash = EchoHashFromKey(key)
    local best
    for _, categories in pairs(store) do
        local row = type(categories) == "table" and categories[category] or nil
        if RowMatchesBuild(row, buildId, key, hash) and BetterRow(row, best) then
            best = row
        end
    end
    return best
end

local function PersonalForKey(key, category)
    return PersonalForBuild(nil, key, category)
end

local function SortedEntries(row)
    if not row then return {} end
    return {{
        player = row.player or "?", dps = tonumber(row.dps) or 0,
        level = tonumber(row.level) or 0, ts = tonumber(row.ts) or 0,
    }}
end

function DPS.GetLeaderboard(buildId, category)
    local key = BuildKey(buildId)
    return key and SortedEntries(GlobalForBuild(buildId, key, category)) or {}
end

-- Projection-facing lookup. BuildCatalog summaries already carry the stable
-- identity fields, so browser refreshes need not hydrate/copy every Echo list
-- merely to find a DPS row.
function DPS.GetLeaderboardForIdentity(buildId, fingerprint, fingerprintHash, category)
    local key = type(fingerprint) == "string" and fingerprint or nil
    local hash = fingerprintHash ~= nil and tostring(fingerprintHash) or nil
    if not key and not hash then return {} end
    return SortedEntries(GlobalForIdentity(buildId, key, hash, category))
end

local CachedLockedRecord

function DPS.GetRecordForIdentity(buildId, fingerprint, fingerprintHash, category)
    local key = type(fingerprint) == "string" and fingerprint or nil
    local hash = fingerprintHash ~= nil and tostring(fingerprintHash) or nil
    if not key and not hash then return nil end
    local row = GlobalForIdentity(buildId, key, hash, category)
    return row and CachedLockedRecord(row, category, buildId) or nil
end

-- Lightweight Community qualification snapshot. The exact full fingerprint
-- intersection is built during the existing revision-scoped identity scan, so
-- browser projections neither walk DPS storage again nor query per build.
function DPS.GetCommunityEligibility()
    EnsureIdentityIndex()
    identityIndex.stats.eligibilityReads =
        identityIndex.stats.eligibilityReads + 1
    return DeepCopy(identityIndex.eligibility)
end

-- Resumable identity/eligibility construction for UI projections. Each step
-- examines exactly one stored row (or one fingerprint during intersection).
-- The completed structure becomes the same revision-scoped identity index used
-- by synchronous compatibility readers.
function DPS.BeginCommunityEligibilityCursor()
    local revisionSource, revision = CurrentDpsRevision()
    if identityIndex.initialized
        and identityIndex.revisionSource == revisionSource
        and revision ~= nil and identityIndex.observedRevision == revision then
        return {
            revisionSource=revisionSource,revision=revision,
            store=CharacterBestStore(),phase="done",
            eligibility=identityIndex.eligibility,reused=true,
        }
    end
    return {
        revisionSource=revisionSource,revision=revision,
        store=CharacterBestStore(),phase="dummy",key=nil,
        categories={dummy=NewIdentityCategory(),lk=NewIdentityCategory()},
        best={dummy={},lk={}},eligibility={},scanned=0,indexed=0,
    }
end

local function EligibilityCursorCurrent(cursor)
    local source, revision = CurrentDpsRevision()
    return cursor.revisionSource == source
        and cursor.revision == revision
        and cursor.store == CharacterBestStore()
end

function DPS.CommunityEligibilityCursorNext(cursor)
    if type(cursor) ~= "table" then return true, "invalid cursor" end
    if cursor.phase == "done" then return true end
    if not EligibilityCursorCurrent(cursor) then return true, "DPS changed" end
    if cursor.phase == "dummy" or cursor.phase == "lk" then
        local category = cursor.phase
        local bucket = type(cursor.store[category]) == "table"
            and cursor.store[category] or {}
        local key, row = next(bucket, cursor.key)
        cursor.key = key
        if key == nil then
            if category == "dummy" then
                cursor.phase, cursor.key = "lk", nil
            else
                cursor.phase, cursor.key = "intersect", nil
            end
            return false
        end
        cursor.scanned = cursor.scanned + 1
        if type(row) == "table"
            and DPS.IsDurationEligible(category, row.duration) then
            local fingerprint = row.fingerprint
            local hash = row.loadoutHash
                or (fingerprint and EchoHashFromKey(fingerprint))
            local target = cursor.categories[category]
            AddIdentityRow(target.buildId, row.buildId, row)
            AddIdentityRow(target.fingerprint, fingerprint, row)
            AddIdentityRow(target.hash, hash, row)
            local value = tonumber(row.dps) or 0
            if type(fingerprint) == "string" and fingerprint ~= ""
                and value == value and value < math.huge and value > 0 then
                local previous = cursor.best[category][fingerprint] or 0
                if value > previous then cursor.best[category][fingerprint] = value end
            end
            cursor.indexed = cursor.indexed + 1
        end
        return false
    end

    local fingerprint, dummy = next(cursor.best.dummy, cursor.key)
    cursor.key = fingerprint
    if fingerprint ~= nil then
        local lk = cursor.best.lk[fingerprint]
        if lk and dummy > 0 and lk > 0 then
            cursor.eligibility[fingerprint] = {
                dummy=dummy,lk=lk,best=math.max(dummy,lk),
                average=(dummy+lk)/2,count=2,
            }
        end
        return false
    end

    cursor.phase = "done"
    identityIndex.categories = cursor.categories
    identityIndex.eligibility = cursor.eligibility
    identityIndex.initialized = true
    identityIndex.revisionSource = cursor.revisionSource
    identityIndex.observedRevision = cursor.revision
    identityIndex.stats.rebuilds = identityIndex.stats.rebuilds + 1
    identityIndex.stats.rowsScanned = identityIndex.stats.rowsScanned
        + cursor.scanned
    identityIndex.stats.indexedRows = cursor.indexed
    identityIndex.stats.intersections = identityIndex.stats.intersections + 1
    return true
end

function DPS.CommunityEligibilityCursorResult(cursor)
    if type(cursor) ~= "table" or cursor.phase ~= "done" then return nil end
    identityIndex.stats.eligibilityReads =
        identityIndex.stats.eligibilityReads + 1
    return cursor.eligibility
end

-- Legacy repair first builds the normal exact-fingerprint eligibility index,
-- then makes one second bounded pass over represented DPS rows. Each call
-- advances at most one stored row and returns only its existing table
-- reference; the repair owner materializes evidence for one candidate at a
-- time. Ineligible rows remain visible to its bounded reason accounting.
function DPS.BeginLegacyQualificationCursor()
    local revisionSource, revision = CurrentDpsRevision()
    local eligibilityCursor = DPS.BeginCommunityEligibilityCursor()
    local eligibility = eligibilityCursor.phase == "done"
        and DPS.CommunityEligibilityCursorResult(eligibilityCursor) or nil
    return {
        revisionSource=revisionSource,revision=revision,
        store=CharacterBestStore(),eligibilityCursor=eligibilityCursor,
        eligibility=eligibility,
        phase=eligibility and "dummy" or "eligibility",
        key=nil,scanned=0,materialized=0,
    }
end

local function LegacyQualificationCursorCurrent(cursor)
    local revisionSource, revision = CurrentDpsRevision()
    return cursor.revisionSource == revisionSource
        and cursor.revision == revision
        and cursor.store == CharacterBestStore()
end

function DPS.LegacyQualificationCursorNext(cursor)
    if type(cursor) ~= "table" then return nil, true, "invalid cursor" end
    if cursor.phase == "done" then return nil, true end
    if not LegacyQualificationCursorCurrent(cursor) then
        return nil, true, "DPS changed"
    end
    if cursor.phase == "eligibility" then
        local done, err = DPS.CommunityEligibilityCursorNext(
            cursor.eligibilityCursor)
        if err then return nil, true, err end
        if done then
            cursor.eligibility = DPS.CommunityEligibilityCursorResult(
                cursor.eligibilityCursor)
            if type(cursor.eligibility) ~= "table" then
                return nil, true, "eligibility unavailable"
            end
            cursor.phase, cursor.key = "dummy", nil
        end
        return nil, false
    end

    local category = cursor.phase
    local bucket = type(cursor.store[category]) == "table"
        and cursor.store[category] or {}
    local key, row = next(bucket, cursor.key)
    cursor.key = key
    if key == nil then
        if category == "dummy" then
            cursor.phase, cursor.key = "lk", nil
        else
            cursor.phase = "done"
            return nil, true
        end
        return nil, false
    end
    cursor.scanned = cursor.scanned + 1
    local fingerprint = type(row) == "table" and row.fingerprint or nil
    if type(fingerprint) == "string" and fingerprint ~= "" then
        cursor.materialized = cursor.materialized + 1
        return {
            category=category,fingerprint=fingerprint,key=key,row=row,
        }, false
    end
    return nil, false
end

function DPS.LegacyQualificationCursorResult(cursor)
    if type(cursor) ~= "table" or cursor.phase ~= "done"
        or not LegacyQualificationCursorCurrent(cursor) then return nil end
    return {
        scanned=tonumber(cursor.scanned) or 0,
        materialized=tonumber(cursor.materialized) or 0,
    }
end

function DPS.IdentityLookupStats()
    local stats = identityIndex.stats
    return {
        rebuilds=stats.rebuilds, rowsScanned=stats.rowsScanned,
        indexedRows=stats.indexedRows, lookups=stats.lookups,
        candidateChecks=stats.candidateChecks,
        eligibilityReads=stats.eligibilityReads,
        intersections=stats.intersections,
    }
end

-- A build is Details-verified only when a valid public record exists for its
-- exact loadout and the capture met that encounter's duration floor.
function DPS.GetBuildVerification(buildId)
    local key = BuildKey(buildId)
    if not key then return nil end
    local best
    for _, category in ipairs({ "dummy", "lk" }) do
        local row = GlobalForKey(key, category)
        if row and DPS.IsDurationEligible(category, row.duration) then
            if not best or (tonumber(row.dps) or 0) > (tonumber(best.dps) or 0) then
                best = {
                    category=category, dps=tonumber(row.dps) or 0,
                    duration=tonumber(row.duration) or 0, player=row.player,
                }
            end
        end
    end
    return best
end

function DPS.GetPersonalBest(buildId, category)
    local key = BuildKey(buildId)
    return key and DPS.MaterializeRecord(
        PersonalForBuild(buildId, key, category)) or nil
end

function DPS.GetBestRecordForEchoes(echoes, category)
    return DPS.MaterializeRecord(
        GlobalForKey(DPS.GetEchoKey(echoes), category))
end

local function HashStrings(items)
    table.sort(items)
    local h = 5381
    for _, text in ipairs(items) do
        for i = 1, #text do h = ((h * 33) + text:byte(i)) % 2147483648 end
    end
    return string.format("%x", h)
end

-- Compact digest of the only leaderboard state that matters: the highest
-- record known for each exact loadout and encounter. Peers with the same
-- digest do not resend any DPS payloads during Sync Now.
local DPS_BUCKETS = 8
local function DpsBucket(category, player)
    -- The wire bucket remains player-name based for protocol-7 compatibility.
    -- Realm identity belongs in the hashed entry/storage key, not in routing.
    local text = tostring(category or "") .. ":" .. PlayerKey(player)
    local h = 5381
    for i = 1, #text do h = ((h * 33) + text:byte(i)) % 2147483648 end
    return (h % DPS_BUCKETS) + 1
end

local function SplitBucketHash(value)
    local out = {}
    value = tostring(value or "")
    local i = 1
    for part in value:gmatch("([^,]+)") do out[i] = part; i = i + 1 end
    return out
end

local function DpsHashEntry(category, playerKey, row)
    if not (row and (tonumber(row.dps) or 0) > 0
        and DPS.IsDurationEligible(category, row.duration)) then return nil end
    return table.concat({ category, tostring(playerKey),
        tostring(math.floor(tonumber(row.dps) or 0)),
        tostring(row.loadoutHash or EchoHashFromKey(row.fingerprint or "") or "0") }, "|")
end

local function DpsHashClass(category, row)
    if type(row) ~= "table" then return "schema" end
    if (tonumber(row.dps) or 0) <= 0 then return "score" end
    if not DPS.IsDurationEligible(category, row.duration) then return "duration" end
    return "eligible"
end

local function FiniteNumber(value)
    return type(value) == "number" and value == value
        and value < math.huge and value > -math.huge
end

local function WireScalarAliasesAgree(compact, verbose, normalize)
    if compact == nil or verbose == nil then return true end
    if normalize then
        local left, right = normalize(compact), normalize(verbose)
        return left ~= nil and left == right
    end
    return type(compact) == type(verbose) and compact == verbose
end

local function WireEchoValue(echo)
    if type(echo) ~= "table"
        or not WireScalarAliasesAgree(echo.spellId, echo.id)
        or not WireScalarAliasesAgree(echo.count, echo.stacks)
        or not WireScalarAliasesAgree(echo.count, echo.stack)
        or not WireScalarAliasesAgree(echo.stacks, echo.stack) then
        return nil
    end
    local spellId = echo.spellId
    if spellId == nil then spellId = echo.id end
    local count = echo.count
    if count == nil then count = echo.stacks end
    if count == nil then count = echo.stack end
    if count == nil then count = 1 end
    local locked = echo.locked
    if locked ~= nil and locked ~= true and locked ~= false
        and locked ~= 0 and locked ~= 1 then return nil end
    return spellId, count, echo.quality, locked == true or locked == 1
end

local function ValidWireEchoList(source)
    if type(source) ~= "table" then return false end
    local entries, maxIndex, total = 0, 0, 0
    for index, echo in pairs(source) do
        if type(index) ~= "number" or index < 1
            or index ~= math.floor(index) or type(echo) ~= "table" then
            return false
        end
        local rawSpellId, rawCount = WireEchoValue(echo)
        local spellId = tonumber(rawSpellId)
        local count = tonumber(rawCount)
        if not FiniteNumber(spellId) or spellId < 1
            or spellId ~= math.floor(spellId) or spellId > 2147483647
            or not FiniteNumber(count) or count < 1
            or count ~= math.floor(count) or count > 120 then
            return false
        end
        entries = entries + 1
        if index > maxIndex then maxIndex = index end
        total = total + count
        if entries > 120 or total > 120 then return false end
    end
    return entries > 0 and entries == maxIndex
end

local function WireEchoListsAgree(left, right)
    if left == nil or right == nil then return true end
    if not ValidWireEchoList(left) or not ValidWireEchoList(right)
        or #left ~= #right then return false end
    for index = 1, #left do
        local li, lc, lq, ll = WireEchoValue(left[index])
        local ri, rc, rq, rl = WireEchoValue(right[index])
        if li ~= ri or lc ~= rc or lq ~= rq or ll ~= rl then return false end
    end
    return true
end

local function WireDpsAliasesAgree(record)
    local function Lower(value)
        return type(value) == "string" and value:lower() or nil
    end
    local function Realm(value)
        return type(value) == "string"
            and value:lower():gsub("%s+", "") or nil
    end
    return WireScalarAliasesAgree(record.v, record.protocolVersion)
        and WireScalarAliasesAgree(record.c, record.category)
        and WireScalarAliasesAgree(record.d, record.dps)
        and WireScalarAliasesAgree(record.u, record.duration)
        and WireScalarAliasesAgree(record.t, record.ts)
        and WireScalarAliasesAgree(record.p, record.player)
        and WireScalarAliasesAgree(record.l, record.level)
        and WireScalarAliasesAgree(record.k, record.class, Lower)
        and WireScalarAliasesAgree(record.o, record.ownerKey,
            Identity.CanonicalOwnerKey)
        and WireScalarAliasesAgree(record.r, record.realm, Realm)
        and WireScalarAliasesAgree(record.b, record.buildId)
        and WireScalarAliasesAgree(record.f, record.fingerprint)
        and WireScalarAliasesAgree(record.h, record.loadoutHash, Lower)
        and WireEchoListsAgree(record.e, record.echoes)
        and WireEchoListsAgree(record.lk, record.lockedEchoes)
end

-- Canonical DPS identity is one tuple. Compact wire and verbose storage aliases
-- may coexist, but every present value must agree. Authority is layered below
-- so contextual relays may validate the tuple without becoming record owners.
function DPS.HasCanonicalOwnerIdentity(record)
    if type(record) ~= "table" then return false end
    local ownerKey
    local function AcceptOwner(value)
        if value == nil then return true end
        local canonical = Identity.CanonicalOwnerKey(value)
        if not canonical or canonical:match("@unknown$")
            or (ownerKey and ownerKey ~= canonical) then return false end
        ownerKey = canonical
        return true
    end
    if not AcceptOwner(record.o) or not AcceptOwner(record.ownerKey)
        or not ownerKey then return false end

    local hasPlayer = false
    local function AcceptPlayer(value)
        if value == nil then return true end
        hasPlayer = true
        if type(value) ~= "string" or not Identity.ValidPlayer(value)
            or not Identity.OwnerKeyMatchesAuthor(ownerKey, value) then
            return false
        end
        if value:find("-", 1, true)
            and Identity.CanonicalOwnerFromTransport(value) ~= ownerKey then
            return false
        end
        return true
    end
    if not AcceptPlayer(record.p) or not AcceptPlayer(record.player)
        or not hasPlayer then return false end

    local ownerName = ownerKey:match("^([^@]+)@")
    local function AcceptRealm(value)
        if value == nil then return true end
        if type(value) ~= "string" or #value > 96
            or value:find("[%c|%s]") then return false end
        return Identity.CanonicalOwnerKey(
            Identity.OwnerKey(ownerName, value)) == ownerKey
    end
    if not AcceptRealm(record.r) or not AcceptRealm(record.realm) then
        return false
    end
    return true, ownerKey
end

function DPS.VerifiedOwnerKey(record)
    if type(record) ~= "table" or record.ownerVerified ~= true
        or record.claimedOwnerKey ~= nil or record.relaySender ~= nil
        or not WireDpsAliasesAgree(record) then
        return nil
    end
    local valid, ownerKey = DPS.HasCanonicalOwnerIdentity(record)
    return valid == true and ownerKey or nil
end

-- Stable read identity for visible but non-authoritative evidence. This never
-- grants ownership; it only lets UI freshness checks re-read the same retained
-- realm/provenance tuple instead of falling back to a stronger same-short-name
-- row from another realm.
function DPS.EvidenceIdentityKey(record)
    if type(record) ~= "table" then return nil end
    local verified = DPS.VerifiedOwnerKey(record)
    if verified then return "verified:" .. verified end
    local player = type(record.player) == "string"
        and record.player:lower() or ""
    local realm = type(record.realm) == "string"
        and record.realm:lower() or ""
    local owner = type(record.ownerKey) == "string"
        and record.ownerKey:lower() or ""
    local claimed = type(record.claimedOwnerKey) == "string"
        and record.claimedOwnerKey:lower() or ""
    local relay = type(record.relaySender) == "string"
        and record.relaySender:lower() or ""
    if player == "" then return nil end
    return table.concat({"evidence",player,realm,owner,claimed,relay}, "\0")
end

-- The response election may suppress every equivalent peer, so its cached
-- safety bit is deliberately stricter than the digest's score eligibility.
-- It must prove this client can serialize and authoritatively send every row
-- represented by the bucket hash.  This runs only while warming or repairing
-- the revision-keyed hash cache, never once per response tick.
local function DpsResponseClaimInfo(category, playerKey, row)
    if DpsHashClass(category, row) ~= "eligible" then return false end
    local player = tostring(row.player or "")
    local echoes = StoredEchoes(row, false)
    local fingerprint = ValidWireEchoList(echoes) and EchoKey(echoes) or nil
    local loadoutHash = row.loadoutHash
        or (row.fingerprint and EchoHashFromKey(row.fingerprint))
    local dps, stamp, level = tonumber(row.dps), tonumber(row.ts),
        tonumber(row.level)
    local nowTs = (time and time()) or 0
    local authorityValid = DPS.VerifiedOwnerKey(row) ~= nil
    local safe = authorityValid and Identity.ValidPlayer(player)
        and #player <= 64
        and CharacterKey(player, row.ownerKey, row.realm) == tostring(playerKey)
        and FiniteNumber(dps) and dps >= 1000 and dps <= 500000000
        and DPS.IsDurationEligible(category, row.duration)
        and FiniteNumber(stamp) and stamp > 0
        and (nowTs <= 1000000000 or stamp <= nowTs + 300)
        and FiniteNumber(level) and level >= 1 and level <= 80
        and level == math.floor(level) and NormalizeClass(row.class) ~= nil
        and fingerprint ~= nil and fingerprint == row.fingerprint
        and loadoutHash ~= nil and EchoHashFromKey(fingerprint) == loadoutHash
    return safe, safe and CharacterKey(player, row.ownerKey, row.realm) or nil
end

local function ComputeDpsSyncHash()
    local buckets = {}
    for i = 1, DPS_BUCKETS do buckets[i] = {} end
    local store = CharacterBestStore()
    for _, category in ipairs({ "dummy", "lk" }) do
        for playerKey, row in pairs(store[category] or {}) do
            if row and (tonumber(row.dps) or 0) > 0 then
                local b = DpsBucket(category, row.player or playerKey)
                buckets[b][#buckets[b]+1] = DpsHashEntry(category, playerKey, row)
            end
        end
    end
    local hashes = {}
    for i = 1, DPS_BUCKETS do hashes[i] = #buckets[i] > 0 and HashStrings(buckets[i]) or "0" end
    return table.concat(hashes, ",")
end

local dpsHashCache = {
    initialized=false, entries={}, classifications={}, hashes={}, dirty={},
    responseRows={}, responseClaimable={}, responseAuthority={},
    revisionSource=nil, observedRevision=nil,
    stats={
        hits=0, collectionWalks=0, fullRebuilds=0,
        bucketRebuilds=0, targetedInvalidations=0, fullInvalidations=0,
        rows=0, storedRows=0, durationIneligibleRows=0,
        scoreIneligibleRows=0, schemaIneligibleRows=0,
    },
}

local function NewDpsBuckets()
    local buckets = {}
    for bucket = 1, DPS_BUCKETS do buckets[bucket] = {} end
    return buckets
end

local function RebuildDpsBucket(bucket)
    local values = {}
    for _, value in pairs(dpsHashCache.entries[bucket] or {}) do
        values[#values + 1] = value
    end
    dpsHashCache.hashes[bucket] = #values > 0 and HashStrings(values) or "0"
    local claimable, authority = #values > 0, nil
    for entryKey in pairs(dpsHashCache.entries[bucket] or {}) do
        local candidate = dpsHashCache.responseRows[bucket]
            and dpsHashCache.responseRows[bucket][entryKey]
        if type(candidate) ~= "string" or candidate == "" then
            claimable = false
        elseif authority == nil or candidate < authority then
            authority = candidate
        end
    end
    dpsHashCache.responseClaimable[bucket] = claimable
    dpsHashCache.responseAuthority[bucket] = claimable and authority or nil
    dpsHashCache.dirty[bucket] = nil
    dpsHashCache.stats.bucketRebuilds = dpsHashCache.stats.bucketRebuilds + 1
end

local function WarmDpsHashCache()
    local entries, classifications, responseRows = NewDpsBuckets(),
        NewDpsBuckets(), NewDpsBuckets()
    local store = CharacterBestStore()
    local counts = {eligible=0,duration=0,score=0,schema=0,stored=0}
    dpsHashCache.stats.collectionWalks = dpsHashCache.stats.collectionWalks + 1
    for _, category in ipairs({ "dummy", "lk" }) do
        for playerKey, row in pairs(store[category] or {}) do
            local bucket = DpsBucket(category,
                type(row) == "table" and row.player or playerKey)
            local entryKey = category .. "|" .. tostring(playerKey)
            local classification = DpsHashClass(category, row)
            classifications[bucket][entryKey] = classification
            counts.stored = counts.stored + 1
            counts[classification] = counts[classification] + 1
            if classification == "eligible" then
                entries[bucket][entryKey] = DpsHashEntry(category, playerKey, row)
                local safe, authority = DpsResponseClaimInfo(
                    category, playerKey, row)
                responseRows[bucket][entryKey] = safe and authority or false
            end
        end
    end
    dpsHashCache.entries, dpsHashCache.classifications = entries, classifications
    dpsHashCache.responseRows = responseRows
    dpsHashCache.hashes, dpsHashCache.dirty = {}, {}
    dpsHashCache.responseClaimable, dpsHashCache.responseAuthority = {}, {}
    dpsHashCache.stats.rows = counts.eligible
    dpsHashCache.stats.storedRows = counts.stored
    dpsHashCache.stats.durationIneligibleRows = counts.duration
    dpsHashCache.stats.scoreIneligibleRows = counts.score
    dpsHashCache.stats.schemaIneligibleRows = counts.schema
    for bucket = 1, DPS_BUCKETS do
        dpsHashCache.dirty[bucket] = true
        RebuildDpsBucket(bucket)
    end
    dpsHashCache.initialized = true
    dpsHashCache.stats.fullRebuilds = dpsHashCache.stats.fullRebuilds + 1
    local revisions = Nexus and Nexus.Revisions
    dpsHashCache.observedRevision = revisions and revisions.Get
        and revisions.Get(revisions.DPS_CHANGED) or nil
end

local function InvalidateAllDpsHashes()
    if dpsHashCache.initialized then
        dpsHashCache.initialized = false
        dpsHashCache.stats.fullInvalidations = dpsHashCache.stats.fullInvalidations + 1
    end
end

local function AdjustDpsHashClass(classification, delta)
    if not classification then return end
    dpsHashCache.stats.storedRows = math.max(0,
        (tonumber(dpsHashCache.stats.storedRows) or 0) + delta)
    local key = classification == "eligible" and "rows"
        or classification == "duration" and "durationIneligibleRows"
        or classification == "score" and "scoreIneligibleRows"
        or "schemaIneligibleRows"
    dpsHashCache.stats[key] = math.max(0,
        (tonumber(dpsHashCache.stats[key]) or 0) + delta)
end

local function UpdateDpsHashRecord(category, player, ownerKey, realm,
        characterKey, previousCharacterKey)
    if not dpsHashCache.initialized then return end
    if category ~= "dummy" and category ~= "lk" then
        InvalidateAllDpsHashes()
        return
    end
    local playerKey = characterKey
        or CharacterKey(player, ownerKey, realm)
    if previousCharacterKey and previousCharacterKey ~= playerKey then
        local previousBucket = DpsBucket(category, player)
        local previousEntry = category .. "|" .. previousCharacterKey
        local previousClass = dpsHashCache.classifications[previousBucket]
            [previousEntry]
        AdjustDpsHashClass(previousClass, -1)
        dpsHashCache.entries[previousBucket][previousEntry] = nil
        dpsHashCache.classifications[previousBucket][previousEntry] = nil
        dpsHashCache.responseRows[previousBucket][previousEntry] = nil
        dpsHashCache.dirty[previousBucket] = true
    end
    local bucket = DpsBucket(category, player)
    local entryKey = category .. "|" .. playerKey
    local previousClass = dpsHashCache.classifications[bucket][entryKey]
    local row = CharacterBestStore()[category][playerKey]
    local nextClass = row ~= nil and DpsHashClass(category, row) or nil
    AdjustDpsHashClass(previousClass, -1)
    AdjustDpsHashClass(nextClass, 1)
    dpsHashCache.classifications[bucket][entryKey] = nextClass
    dpsHashCache.entries[bucket][entryKey] = nextClass == "eligible"
        and DpsHashEntry(category, playerKey, row) or nil
    if nextClass == "eligible" then
        local safe, authority = DpsResponseClaimInfo(category, playerKey, row)
        dpsHashCache.responseRows[bucket][entryKey] = safe and authority or false
    else
        dpsHashCache.responseRows[bucket][entryKey] = nil
    end
    dpsHashCache.dirty[bucket] = true
    dpsHashCache.stats.targetedInvalidations =
        dpsHashCache.stats.targetedInvalidations + 1
end

local function OnDpsRevision(_, revision, detail)
    dpsHashCache.observedRevision = revision
    if type(detail) == "table"
        and (detail.scope == "record" or detail.scope == "metadata")
        and detail.category and detail.player then
        UpdateDpsHashRecord(detail.category, detail.player,
            detail.ownerKey, detail.realm, detail.characterKey,
            detail.previousCharacterKey)
    elseif type(detail) ~= "table" or detail.scope ~= "local" then
        InvalidateAllDpsHashes()
    end
end

local function EnsureDpsHashSubscription()
    local revisions = Nexus and Nexus.Revisions
    if not (revisions and type(revisions.Subscribe) == "function") then return end
    if dpsHashCache.revisionSource ~= revisions then
        dpsHashCache.revisionSource = revisions
        dpsHashCache.observedRevision = revisions.Get
            and revisions.Get(revisions.DPS_CHANGED) or nil
        revisions.Subscribe(revisions.DPS_CHANGED, OnDpsRevision)
        InvalidateAllDpsHashes()
    end
end

local function CachedDpsSyncHash()
    EnsureDpsHashSubscription()
    local revisions = Nexus and Nexus.Revisions
    local currentRevision = revisions and revisions.Get
        and revisions.Get(revisions.DPS_CHANGED) or nil
    if dpsHashCache.initialized and currentRevision ~= nil
        and dpsHashCache.observedRevision ~= nil
        and currentRevision ~= dpsHashCache.observedRevision then
        InvalidateAllDpsHashes()
    end
    if not dpsHashCache.initialized then WarmDpsHashCache() end
    local rebuilt = false
    for bucket = 1, DPS_BUCKETS do
        if dpsHashCache.dirty[bucket] then
            RebuildDpsBucket(bucket)
            rebuilt = true
        end
    end
    if not rebuilt then dpsHashCache.stats.hits = dpsHashCache.stats.hits + 1 end
    return table.concat(dpsHashCache.hashes, ",")
end

function DPS.GetSyncHash()
    MigrateLocalLockedBaseline()
    MigrateLegacyLeaderboard()
    if BackfillLocalLockedRows() then
        BumpDps("locked metadata backfilled", {scope="metadata"})
    end
    return CachedDpsSyncHash()
end

function DPS.GetSyncHashUncached()
    MigrateLocalLockedBaseline()
    MigrateLegacyLeaderboard()
    if BackfillLocalLockedRows() then
        BumpDps("locked metadata backfilled", {scope="metadata"})
    end
    return ComputeDpsSyncHash()
end

function DPS.HashCacheStats()
    local out = {}
    for key, value in pairs(dpsHashCache.stats) do out[key] = value end
    out.initialized = dpsHashCache.initialized
    out.revision = dpsHashCache.observedRevision
    out.buckets = DPS_BUCKETS
    out.dirtyBuckets = 0
    if dpsHashCache.initialized then
        for bucket = 1, DPS_BUCKETS do
            if dpsHashCache.dirty[bucket] then
                out.dirtyBuckets = out.dirtyBuckets + 1
            end
        end
    end
    out.digest = dpsHashCache.initialized
        and table.concat(dpsHashCache.hashes or {}, ",") or nil
    return out
end

function DPS.ResponseBucketClaimInfo(bucket)
    bucket = tonumber(bucket)
    if not bucket or bucket ~= math.floor(bucket)
        or bucket < 1 or bucket > DPS_BUCKETS then return false end
    CachedDpsSyncHash()
    return dpsHashCache.responseClaimable[bucket] == true,
        dpsHashCache.responseAuthority[bucket]
end

-- Diagnostic-facing exact qualification lookup. It intentionally refuses to
-- warm or rebuild the identity index; the Community projection owns that
-- resumable work. A Peer Test report may inspect only an already-current index.
function DPS.GetCachedCommunityQualification(buildId, fingerprint, fingerprintHash)
    local key = type(fingerprint) == "string" and fingerprint or nil
    local hash = fingerprintHash ~= nil and tostring(fingerprintHash) or nil
    if not key and not hash then return nil, "identity unavailable" end
    local revisionSource, revision = CurrentDpsRevision()
    if not identityIndex.initialized
        or identityIndex.revisionSource ~= revisionSource
        or revision == nil
        or identityIndex.observedRevision ~= revision then
        return nil, "cache cold"
    end
    local out = {dummy=0,lk=0,count=0}
    for _, category in ipairs({"dummy", "lk"}) do
        local row = IndexedGlobalForIdentity(buildId, key, hash, category)
        local value = row and tonumber(row.dps) or 0
        if value == value and value > 0 and value < math.huge then
            out[category] = value
            out.count = out.count + 1
        end
    end
    return out
end

CachedLockedRecord = function(row, category, expectedBuildId)
    if type(row) ~= "table" then return nil end
    local materialized = DPS.MaterializeRecord(row) or {}
    local ordinary = type(materialized.echoes) == "table"
        and materialized.echoes or StoredEchoes(row, false)
    local locked = type(materialized.lockedEchoes) == "table"
        and materialized.lockedEchoes or StoredEchoes(row, true)
    local fingerprint = materialized.fingerprint or row.fingerprint
    local resolvedBuildId
    if expectedBuildId ~= nil and materialized.buildId == expectedBuildId then
        resolvedBuildId = expectedBuildId
    elseif type(fingerprint) == "string" and fingerprint ~= "" then
        local catalog = Catalog()
        if catalog and type(catalog.ResolveFingerprintIdentity) == "function" then
            local ok, resolved = pcall(catalog.ResolveFingerprintIdentity,
                materialized.buildId, fingerprint)
            if ok then resolvedBuildId = resolved end
        end
    end
    return {
        category=category,buildId=materialized.buildId,
        resolvedBuildId=resolvedBuildId,fingerprint=fingerprint,
        echoes=DeepCopy(ordinary),lockedEchoes=DeepCopy(locked or {}),
        lockedFingerprint=materialized.lockedFingerprint ~= nil
            and materialized.lockedFingerprint or LockedKey(locked),
        recordIdentityMismatch=materialized.recordIdentityMismatch,
        buildIdentityMismatch=materialized.buildIdentityMismatch,
        resolvedIdentityMismatch=materialized.resolvedIdentityMismatch,
    }
end

-- Explicit-report evidence reader.  Peer Test may inspect only a current
-- identity cache: it must not warm the cache, traverse DPS storage, or expose
-- complete score/player records merely to explain one selected build.
function DPS.GetCachedLockedEvidence(buildId, fingerprint, fingerprintHash)
    local key = type(fingerprint) == "string" and fingerprint or nil
    local hash = fingerprintHash ~= nil and tostring(fingerprintHash) or nil
    if not key and not hash and buildId ~= nil then
        local catalog = Catalog()
        local okSummary, summary = false, nil
        if catalog and type(catalog.GetSummary) == "function" then
            okSummary, summary = pcall(catalog.GetSummary, buildId)
        end
        if not okSummary then summary = nil end
        key = type(summary) == "table"
            and type(summary.fingerprint) == "string"
            and summary.fingerprint or nil
        hash = type(summary) == "table" and summary.fingerprintHash ~= nil
            and tostring(summary.fingerprintHash) or nil
    end
    if not key and not hash then return nil, "identity unavailable" end
    local revisionSource, revision = CurrentDpsRevision()
    if not identityIndex.initialized
        or identityIndex.revisionSource ~= revisionSource
        or revision == nil
        or identityIndex.observedRevision ~= revision then
        return nil, "cache cold"
    end

    local dummy = IndexedGlobalForIdentity(buildId, key, hash, "dummy")
    local lk = IndexedGlobalForIdentity(buildId, key, hash, "lk")
    if not dummy and not lk then return nil, "evidence unavailable" end
    local out = {
        dummy=CachedLockedRecord(dummy, "dummy", buildId),
        lk=CachedLockedRecord(lk, "lk", buildId),
    }
    local ordinary = out.dummy and out.dummy.echoes
        or out.lk and out.lk.echoes or nil
    out.ordinaryEchoes = DeepCopy(ordinary)
    return out
end

function DPS.ProtocolVersion()
    return PROTOCOL_VERSION
end

local function TerminalOutbound(reason, amount)
    NoteOutbound("considered", amount)
    NoteOutbound(reason, amount)
end

local function CurrentDpsRevision()
    local revisions = Nexus and Nexus.Revisions
    return revisions and type(revisions.Get) == "function"
        and revisions.Get(revisions.DPS_CHANGED) or nil
end

local function NormalizeOutboundReason(reason)
    if reason == "duplicate" then return "duplicate_not_better" end
    if outboundStats[reason] ~= nil then return reason end
    if reason == "invalid prepared DPS record"
        or reason == "invalid packet" or reason == "empty batch" then
        return "schema"
    end
    return "other"
end

-- Broadcast only the single highest known result for this exact build.
function DPS.BroadcastBestForBuild(buildId)
    local key, build = BuildKey(buildId)
    if not key or not build or not (Sync and Sync.BroadcastDpsRecord) then return false end
    local sent = false
    local store = CharacterBestStore()
    for _, category in ipairs({ "dummy", "lk" }) do
        for _, row in pairs(store[category] or {}) do
            local relatedId, relatedBuild
            if row then
                relatedId, relatedBuild = VerifiedBuildRelation(row, buildId)
            end
            if row and row.buildId == buildId and relatedId
                and (tonumber(row.dps) or 0) > 0
                and DPS.IsDurationEligible(category, row.duration)
                and DPS.VerifiedOwnerKey(row) ~= nil then
                local record = {
                    protocolVersion = PROTOCOL_VERSION, fingerprint = row.fingerprint or key,
                    loadoutHash = row.loadoutHash or relatedBuild.fingerprintHash
                        or EchoHashFromKey(key),
                    category = category, dps = math.floor(tonumber(row.dps) or 0),
                    duration = tonumber(row.duration) or 0, ts = tonumber(row.ts) or 0,
                    player = row.player or "?", level = tonumber(row.level) or 0,
                    buildId = relatedId,
                    class = row.class, ownerKey = row.ownerKey, realm = row.realm,
                    ownerVerified = row.ownerVerified == true,
                    echoes = StoredEchoes(row, false) or BuildSnapshot(relatedBuild),
                    lockedEchoes = StoredEchoes(row, true),
                }
                local ok, result = pcall(Sync.BroadcastDpsRecord, record)
                if ok and result ~= false then sent = true end
            end
        end
    end
    return sent
end

function DPS.BroadcastAllBuildBests(peerHash, onlyBucket, progress, maxItems,
        responseContext, responseBudget)
    local localHash = tostring(DPS.GetSyncHash())
    local localRevision = CurrentDpsRevision()
    progress = type(progress) == "table" and progress or {}
    local state = progress._responseState
    if peerHash and tostring(peerHash) == localHash then
        local pending = state
            and math.max(0, math.floor(tonumber(state.pending) or 0)) or 0
        if pending > 0 then
            TerminalOutbound("peer_current", pending)
        elseif not state then
            -- GetSyncHash warmed this scalar count. Explain a no-op response
            -- without re-walking the uncapped DPS store.
            TerminalOutbound("peer_current", dpsHashCache.stats.rows)
        end
        progress._responseState = nil
        return 0, true, false, nil, 0, 0, 0, true
    end
    MigrateLegacyLeaderboard()
    local peerBuckets = SplitBucketHash(peerHash)
    local myBuckets = SplitBucketHash(localHash)
    local legacyPeer = #peerBuckets ~= DPS_BUCKETS
    local stateKey = table.concat({tostring(peerHash or "0"),
        tostring(onlyBucket or "*"), localHash,
        tostring(responseGeneration)}, "|")
    local revisionChanged = state and state.revision ~= localRevision
    local generationChanged = state
        and state.generation ~= responseGeneration
    if state and (state.key ~= stateKey or revisionChanged
            or generationChanged) then
        local pending = math.max(0, math.floor(tonumber(state.pending) or 0))
        local superseded = state.localHash ~= localHash or revisionChanged
            or generationChanged
        if pending > 0 then
            TerminalOutbound(superseded
                and "stale_record" or "outside_request", pending)
        end
        progress._responseState = nil
        state = nil
        -- A superseded immutable snapshot is a complete accounting boundary.
        -- Do not start walking its replacement in this call: doing so makes
        -- diagnostics and work performed depend on Lua's table iteration
        -- order. The reconciler will begin the fresh snapshot on its retry.
        if superseded then
            return 0, false, true, "stale candidate snapshot",
                0, 0, 0, false
        end
    end
    if not state then
        state = {key=stateKey, localHash=localHash, revision=localRevision,
            generation=responseGeneration,
            categoryIndex=1,
            cursor=nil, scanComplete=false, candidates={}, sendCursor=1,
            pending=0,claimSafe=true}
        progress._responseState = state
    elseif tostring(DPS.GetSyncHash()) ~= state.localHash
        or CurrentDpsRevision() ~= state.revision
        or state.generation ~= responseGeneration then
        local pending = math.max(0, math.floor(tonumber(state.pending) or 0))
        if pending > 0 then TerminalOutbound("stale_record", pending) end
        progress._responseState = nil
        return 0, false, true, "stale candidate snapshot", 0, 0, 0, false
    end

    local limit = tonumber(maxItems)
    if not limit or limit < 1 then limit = math.huge end
    local work, n, progressed = 0, 0, false
    local wireChunks, wireBytes, wireTransfers = 0, 0, 0
    local categories = {"dummy", "lk"}
    local store = CharacterBestStore()
    while work < limit do
        if not state.scanComplete then
            local category = categories[state.categoryIndex]
            if not category then
                state.scanComplete = true
                progressed = true
                work = work + 1
            else
                local playerKey, row = next(store[category] or {}, state.cursor)
                work = work + 1
                progressed = true
                if playerKey == nil then
                    state.categoryIndex = state.categoryIndex + 1
                    state.cursor = nil
                else
                    state.cursor = playerKey
                    local bucket = DpsBucket(category,
                        type(row) == "table" and row.player or playerKey)
                    local skipReason
                    local verifiedOwner = type(row) == "table"
                        and DPS.VerifiedOwnerKey(row) or nil
                    if onlyBucket and bucket ~= onlyBucket then
                        skipReason = "outside_bucket"
                    elseif not legacyPeer
                        and tostring(peerBuckets[bucket] or "")
                            == tostring(myBuckets[bucket] or "") then
                        skipReason = "peer_current"
                    elseif type(row) ~= "table" then
                        skipReason = "schema"
                    elseif (tonumber(row.dps) or 0) <= 0 then
                        skipReason = "score"
                    elseif not DPS.IsDurationEligible(category, row.duration) then
                        skipReason = "duration"
                    elseif not verifiedOwner then
                        state.claimSafe = false
                        skipReason = "relay_authorization"
                    elseif not (Sync and Sync.BroadcastDpsRecord) then
                        skipReason = "other"
                    end
                    if skipReason then
                        TerminalOutbound(skipReason)
                    else
                        NoteOutbound("eligible")
                        local loadoutHash = row.loadoutHash
                            or EchoHashFromKey(row.fingerprint or "")
                        local key = table.concat({category, tostring(playerKey),
                            tostring(verifiedOwner),
                            tostring(math.floor(tonumber(row.dps) or 0)),
                            tostring(loadoutHash or "0")}, "|")
                        local relatedId = VerifiedBuildRelation(row, row.buildId)
                        state.candidates[#state.candidates + 1] = {
                            key=key,
                            record={
                                protocolVersion=PROTOCOL_VERSION,
                                fingerprint=row.fingerprint,
                                loadoutHash=loadoutHash,
                                category=category,
                                dps=math.floor(tonumber(row.dps) or 0),
                                duration=tonumber(row.duration) or 0,
                                ts=tonumber(row.ts) or 0,
                                player=row.player or "?",
                                level=tonumber(row.level) or 0,
                                buildId=relatedId, class=row.class,
                                ownerKey=verifiedOwner, realm=row.realm,
                                ownerVerified=true,
                                echoes=StoredEchoes(row, false),
                                lockedEchoes=StoredEchoes(row, true),
                                -- Only a row this client received directly from
                                -- its named owner may cross the response-only
                                -- relay path. Legacy/locally injected rows keep
                                -- the old owner-only behavior.
                                _originVerified=true,
                            },
                        }
                        state.pending = (tonumber(state.pending) or 0) + 1
                    end
                end
            end
        else
            while state.sendCursor <= #state.candidates
                and progress[state.candidates[state.sendCursor].key] do
                state.pending = math.max(0,
                    (tonumber(state.pending) or 0) - 1)
                TerminalOutbound("duplicate_not_better")
                state.sendCursor = state.sendCursor + 1
            end
            if state.sendCursor > #state.candidates then
                return n, true, progressed, nil,
                    wireChunks, wireBytes, wireTransfers,
                    state.claimSafe ~= false
            end
            local item = state.candidates[state.sendCursor]
            work = work + 1
            local ok, result, why, retryPrepared,
                costChunks, costBytes, costTransfers = pcall(
                Sync.BroadcastDpsRecord, item.record, item.prepared, true,
                responseContext, responseBudget)
            if ok and result ~= false then
                progress[item.key] = "admitted"
                state.sendCursor = state.sendCursor + 1
                item.prepared = nil
                n, progressed = n + 1, true
                state.pending = math.max(0,
                    (tonumber(state.pending) or 0) - 1)
                wireChunks = wireChunks + (tonumber(costChunks) or 0)
                wireBytes = wireBytes + (tonumber(costBytes) or 0)
                wireTransfers = wireTransfers + (tonumber(costTransfers) or 0)
                if why == "duplicate" then
                    TerminalOutbound("duplicate_not_better")
                else
                    local me = (UnitName and UnitName("player")) or "?"
                    TerminalOutbound(PlayerKey(item.record.player) == PlayerKey(me)
                        and "offered_direct" or "offered_relay")
                end
            elseif ok and (why == "sync queue full"
                    or why == "response wire budget") then
                NoteOutbound(why == "sync queue full"
                    and "queue_deferred" or "wire_deferred")
                item.prepared = retryPrepared or item.prepared
                return n, false, progressed, why,
                    wireChunks + (tonumber(costChunks) or 0),
                    wireBytes + (tonumber(costBytes) or 0),
                    wireTransfers + (tonumber(costTransfers) or 0),
                    state.claimSafe ~= false
            else
                state.claimSafe = false
                progress[item.key] = "skipped"
                state.sendCursor = state.sendCursor + 1
                item.prepared = nil
                progressed = true
                state.pending = math.max(0,
                    (tonumber(state.pending) or 0) - 1)
                TerminalOutbound(NormalizeOutboundReason(why))
            end
        end
    end
    local complete = state.scanComplete
        and state.sendCursor > #state.candidates
    return n, complete, progressed, nil,
        wireChunks, wireBytes, wireTransfers, state.claimSafe ~= false
end

local function DpsBoardEntry(row, category, summaryOnly)
    if type(row) ~= "table" or (tonumber(row.dps) or 0) <= 0
        or not DPS.IsDurationEligible(category, row.duration) then return nil end
    local rawBuildId = row.buildId
    local buildId = rawBuildId
    local verifiedOwnerKey = DPS.VerifiedOwnerKey(row)
    local relationFingerprint = RelationshipFingerprint(row)
    local protocolVersion = tonumber(row.protocolVersion)
    local legacyProtocol = protocolVersion
        and protocolVersion == math.floor(protocolVersion)
        and protocolVersion > 0 and protocolVersion < PROTOCOL_VERSION
    local function CanRelate(candidate, source)
        if type(candidate) ~= "table"
            or Identity.SavedMirrorKind(candidate) ~= "ordinary" then
            return false
        end
        if verifiedOwnerKey ~= nil
            and Identity.VerifiedOwnerKey(candidate) == verifiedOwnerKey then
            local candidateFingerprint = RelationshipFingerprint(candidate)
            return relationFingerprint ~= nil and candidateFingerprint ~= nil
                and tostring(candidateFingerprint)
                    == tostring(relationFingerprint)
        end
        -- Historical protocol rows may retain their already-proven immutable
        -- catalog navigation identity. Overlay/current rows never enter this
        -- compatibility branch, even when their content looks identical.
        return legacyProtocol and source == "bundled"
    end
    local resolvedBuildId
    local resolvedFingerprintEpoch, resolvedFingerprintRevision
    local rowEchoes = StoredEchoes(row, false)
    local lockedEchoes = StoredEchoes(row, true)
    local catalog = Catalog()
    local buildIdentityMismatch = false
    local recordIdentityMismatch = false
    local legacyProof
    if type(row.fingerprint) == "string"
        and row.fingerprint:sub(1, 1) == "@"
        and catalog
        and type(catalog.ValidateLegacyFingerprintClaim) == "function" then
        local ok, proof = pcall(
            catalog.ValidateLegacyFingerprintClaim, rawBuildId, row)
        if ok and type(proof) == "table" then legacyProof = proof end
    end
    local rowKey = EchoKey(rowEchoes)
    if row.fingerprint and rowKey
        and tostring(row.fingerprint) ~= tostring(rowKey)
        and not (legacyProof
            and tostring(legacyProof.fingerprint) == tostring(rowKey)) then
        recordIdentityMismatch = true
    end
    local idBuild, idSource
    if summaryOnly and rowEchoes and catalog
        and type(catalog.GetSummary) == "function" then
        idBuild, idSource = catalog.GetSummary(buildId)
    else
        idBuild, idSource = CatalogGet(buildId)
    end
    local build = idBuild
    local legacyRawBuildId = legacyProtocol and idSource == "bundled"
        and not recordIdentityMismatch and rawBuildId or nil
    if build then
        if not CanRelate(build, idSource) then
            build, buildId = nil, nil
        else
            local buildKey = build.fingerprint or EchoKey(BuildSnapshot(build))
            if row.fingerprint and buildKey
            and tostring(buildKey) ~= tostring(row.fingerprint)
            and not (legacyProof
                and type(build.id) == type(legacyProof.buildId)
                and build.id == legacyProof.buildId
                and tostring(buildKey) == tostring(legacyProof.fingerprint)) then
                buildIdentityMismatch = true
                build, buildId = nil, nil
            end
        end
    else
        buildId = nil
    end
    if summaryOnly and build and legacyProtocol then
        resolvedBuildId = legacyProof and legacyProof.buildId or buildId
        if type(catalog.ExactFingerprintRevision) == "function" then
            resolvedFingerprintEpoch, resolvedFingerprintRevision =
                catalog.ExactFingerprintRevision(
                    legacyProof and legacyProof.fingerprint or row.fingerprint)
        end
    end
    if summaryOnly and not build and rowEchoes and not recordIdentityMismatch
        and legacyProtocol and catalog
        and type(catalog.ResolveFingerprintIdentity) == "function" then
        local ok, resolved, _, resolvedFingerprint = pcall(
            catalog.ResolveFingerprintIdentity,
            rawBuildId, row.fingerprint, {legacyRecord=row})
        if ok and resolved then
            local resolvedBuild, resolvedSource = CatalogGet(resolved)
            if CanRelate(resolvedBuild, resolvedSource) then
                resolvedBuildId = resolved
                if type(catalog.ExactFingerprintRevision) == "function" then
                    resolvedFingerprintEpoch, resolvedFingerprintRevision =
                        catalog.ExactFingerprintRevision(
                            resolvedFingerprint or row.fingerprint)
                end
            end
        end
    end
    if not build and rowEchoes and not summaryOnly then
        local candidateId, candidate, candidateSource = FindMatchingBuild(rowEchoes)
        if CanRelate(candidate, candidateSource) then
            buildId, build = candidateId, candidate
        end
    end
    local displayBuild = build
    if not displayBuild and not rowEchoes
        and not buildIdentityMismatch then return nil end
    return {
        player=row.player or "?",dps=math.floor(tonumber(row.dps) or 0),
        class=row.class,ownerKey=row.ownerKey,realm=row.realm,
        ownerVerified=verifiedOwnerKey ~= nil,relaySender=row.relaySender,
        claimedOwnerKey=row.claimedOwnerKey,
        level=tonumber(row.level) or 0,ts=tonumber(row.ts) or 0,
        duration=tonumber(row.duration) or 0,category=category,
        fingerprint=row.fingerprint,
        echoes=rowEchoes or (not buildIdentityMismatch and BuildSnapshot(build) or nil),
        lockedEchoes=lockedEchoes,lockedFingerprint=LockedKey(lockedEchoes),
        protocolVersion=row.protocolVersion,
        buildId=buildId or legacyRawBuildId,
        resolvedBuildId=resolvedBuildId,build=displayBuild,
        resolvedFingerprintEpoch=resolvedFingerprintEpoch,
        resolvedFingerprintRevision=resolvedFingerprintRevision,
        buildIdentityMismatch=buildIdentityMismatch or nil,
        recordIdentityMismatch=recordIdentityMismatch or nil,
    }
end

function DPS.BeginDpsBoardCursor(category)
    if category ~= "dummy" and category ~= "lk" then return nil end
    local revisionSource, revision = CurrentDpsRevision()
    local store = CharacterBestStore()
    return {
        category=category,revisionSource=revisionSource,revision=revision,
        store=store,bucket=type(store[category]) == "table" and store[category] or {},
        key=nil,rows={},presented={},presentedByKey={},ambiguous={},
        ambiguousByKey={},presentIndex=1,seen={},done=false,
        phase="acquire",presentation=Identity.NewPublicPresentation(
            "player", {shadowAmbiguous=true}),
    }
end

function DPS.DpsBoardCursorNext(cursor)
    if type(cursor) ~= "table" then return true, "invalid cursor" end
    if cursor.done then return true end
    local source, revision = CurrentDpsRevision()
    if cursor.revisionSource ~= source or cursor.revision ~= revision
        or cursor.store ~= CharacterBestStore() then
        return true, "DPS changed"
    end
    if cursor.phase == "acquire" then
        local key, row = next(cursor.bucket, cursor.key)
        cursor.key = key
        if key == nil then cursor.phase = "present"; return false end
        local entry = DpsBoardEntry(row, cursor.category, true)
        if entry then
            local player = Identity.PublicRecordKey(entry, "player")
            local existing = cursor.seen[player]
            if not existing then
                cursor.rows[#cursor.rows + 1] = entry
                cursor.seen[player] = #cursor.rows
                if Identity.VerifiedOwnerKey(entry) then
                    Identity.IndexPublicRecord(cursor.presentation, entry)
                    local presented = Identity.PresentPublicRecord(
                        cursor.presentation, entry)
                    cursor.presented[#cursor.presented + 1] = presented
                    cursor.presentedByKey[player] = #cursor.presented
                else
                    cursor.ambiguous[#cursor.ambiguous + 1] = entry
                    cursor.ambiguousByKey[player] = #cursor.ambiguous
                end
            elseif BetterRow(entry, cursor.rows[existing]) then
                cursor.rows[existing] = entry
                local presentedIndex = cursor.presentedByKey[player]
                local ambiguousIndex = cursor.ambiguousByKey[player]
                if presentedIndex then
                    cursor.presentation.visible =
                        math.max(0, cursor.presentation.visible - 1)
                    cursor.presented[presentedIndex] =
                        Identity.PresentPublicRecord(cursor.presentation, entry)
                elseif ambiguousIndex then
                    cursor.ambiguous[ambiguousIndex] = entry
                end
            end
        end
        return false
    end
    local entry = cursor.ambiguous[cursor.presentIndex]
    if not entry then cursor.done = true; return true end
    cursor.presentIndex = cursor.presentIndex + 1
    local presented = Identity.PresentPublicRecord(cursor.presentation, entry)
    if presented then cursor.presented[#cursor.presented + 1] = presented end
    return false
end

function DPS.DpsBoardCursorResult(cursor)
    if type(cursor) ~= "table" or not cursor.done then return nil end
    return cursor.presented, {shadowed=cursor.presentation.shadowed,
        visible=cursor.presentation.visible,invalid=cursor.presentation.invalid}
end

-- Public board: one row per character for the selected encounter. The row is
-- that character's highest known DPS and retains the exact winning loadout.
function DPS.GetDpsBoard(category)
    if category ~= "dummy" and category ~= "lk" then return {} end
    MigrateLocalLockedBaseline()
    MigrateLegacyLeaderboard()
    if RepairCurrentCharacterClass() then
        BumpDps("local class repaired", {scope="metadata"})
    end
    if BackfillLocalLockedRows() then
        BumpDps("locked metadata backfilled", {scope="metadata"})
    end
    local out, seenPlayer = {}, {}
    for _, row in pairs(CharacterBestStore()[category] or {}) do
        local entry = DpsBoardEntry(row, category)
        if entry then
            local pkey = Identity.PublicRecordKey(entry, "player")
            local existing = seenPlayer[pkey]
            if not existing then
                out[#out + 1] = entry
                seenPlayer[pkey] = #out
            elseif BetterRow(entry, out[existing]) then
                out[existing] = entry
            end
        end
    end
    out = Identity.PresentPublicRecords(out, "player", {shadowAmbiguous=true})
    table.sort(out, function(a, b)
        if a.dps ~= b.dps then return a.dps > b.dps end
        if a.ts ~= b.ts then return a.ts < b.ts end
        local left, right = tostring(a.player):lower(), tostring(b.player):lower()
        if left ~= right then return left < right end
        return tostring(a.publicIdentityKey or "")
            < tostring(b.publicIdentityKey or "")
    end)
    return out
end

-- Returns { rank, dps, category, buildTitle } for a named player, or nil
-- if they have no record in the local leaderboard. Rank is 1-based across
-- all players for their best category (dummy preferred over lk when tied).
-- Used by the nameplate module to decorate moused-over players.
local function FindCharacterRow(rows, name)
    local currentRealmKey = CharacterKey(name, nil, CurrentRealm())
    local legacyKey = PlayerKey(name)
    local row = rows[currentRealmKey] or rows[legacyKey]
    if row then return row end
    -- Some legacy/UI callers know only the displayed name. Realm-qualified
    -- storage remains collision-free; the read fallback selects the strongest
    -- matching row when that caller cannot express a realm.
    for _, candidate in pairs(rows) do
        if type(candidate) == "table"
            and Identity.SamePlayer(candidate.player, name)
            and BetterRow(candidate, row) then
            row = candidate
        end
    end
    return row
end

function DPS.GetCharacterBest(category, playerName, expectedOwnerKey,
        expectedEvidenceKey)
    if category ~= "dummy" and category ~= "lk" then return nil end
    MigrateLocalLockedBaseline()
    MigrateLegacyLeaderboard()
    local name = playerName or ((UnitName and UnitName("player")) or "?")
    local rows = CharacterBestStore()[category]
    local expectedOwner = expectedOwnerKey ~= nil
        and Identity.CanonicalOwnerKey(expectedOwnerKey) or nil
    if expectedOwnerKey ~= nil and not expectedOwner then return nil end
    local row
    if expectedOwner then
        row = rows[expectedOwner]
        if DPS.VerifiedOwnerKey(row) ~= expectedOwner then return nil end
    elseif expectedEvidenceKey ~= nil then
        if type(expectedEvidenceKey) ~= "string"
            or expectedEvidenceKey == "" then return nil end
        for _, candidate in pairs(rows) do
            if type(candidate) == "table"
                and Identity.SamePlayer(candidate.player, name)
                and DPS.EvidenceIdentityKey(candidate) == expectedEvidenceKey
                and BetterRow(candidate, row) then
                row = candidate
            end
        end
        if not row then return nil end
    else
        row = playerName and FindCharacterRow(rows, name)
            or rows[CurrentCharacterKey(name)] or rows[PlayerKey(name)]
    end
    if not row or (tonumber(row.dps) or 0) <= 0
        or not DPS.IsDurationEligible(category, row.duration) then return nil end
    return DPS.MaterializeRecord(row)
end

function DPS.GetPlayerInfo(playerName)
    if not playerName or playerName == "" then return nil end
    MigrateLocalLockedBaseline()
    MigrateLegacyLeaderboard()
    local pk = PlayerKey(playerName)
    local qualified = CurrentCharacterKey(playerName)
    local best
    for _, category in ipairs({"dummy", "lk"}) do
        local rows = CharacterBestStore()[category]
        local row = rows[qualified] or rows[pk]
            or FindCharacterRow(rows, playerName)
        if row and (tonumber(row.dps) or 0) > 0
            and DPS.IsDurationEligible(category, row.duration) then
            if not best or (tonumber(row.dps) or 0) > (tonumber(best.dps) or 0) then
                best = { dps = tonumber(row.dps), category = category,
                         buildId = row.buildId, fingerprint = row.fingerprint }
            end
        end
    end
    if not best then return nil end
    -- Compute rank: how many players have a higher DPS in the same category
    local category = best.category
    local rank = 1
    local bucket = CharacterBestStore()[category]
    if bucket[qualified] then pk = qualified end
    for opk, row in pairs(bucket) do
        if opk ~= pk and (tonumber(row.dps) or 0) > best.dps
            and DPS.IsDurationEligible(category, row.duration) then
            rank = rank + 1
        end
    end
    -- Resolve build title
    local buildTitle = nil
    if best.buildId then
        local build = CatalogGet(best.buildId)
        buildTitle = build and build.title or nil
    end
    return {
        rank     = rank,
        dps      = best.dps,
        category = best.category,
        buildId  = best.buildId,
        title    = buildTitle,
    }
end

function DPS.GetCurrentEchoCount()
    local snap = SnapshotEchoes()
    local total = 0
    for _, e in ipairs(snap or {}) do total = total + (tonumber(e.count) or 0) end
    return total
end

function DPS.GetCurrentEchoKey()
    return EchoKey(SnapshotEchoes())
end

function DPS.GetCurrentMatchingBuild()
    return FindMatchingBuild(SnapshotEchoes())
end

function DPS.GetCurrentLeaderboard(category)
    return SortedEntries(GlobalForKey(DPS.GetCurrentEchoKey(), category))
end

function DPS.GetCurrentPersonalBest(category)
    return DPS.MaterializeRecord(
        PersonalForKey(DPS.GetCurrentEchoKey(), category))
end

-- Direct exact-set access for wishlist panel display. A wishlist does not
-- need to be posted as a community build before its own exact-set best can
-- be shown; posting only makes that same fingerprint shareable.
function DPS.GetEchoKey(echoes)
    return EchoKey(NormalizeEchoes(echoes))
end

function DPS.GetPersonalBestForEchoes(echoes, category)
    MigrateLocalLockedBaseline()
    return DPS.MaterializeRecord(
        PersonalForKey(DPS.GetEchoKey(echoes), category))
end

function DPS.GetLeaderboardForEchoes(echoes, category)
    MigrateLocalLockedBaseline()
    return SortedEntries(GlobalForKey(DPS.GetEchoKey(echoes), category))
end

-- Exact build match for wishlist/community-page use.
function DPS.FindMatchingBuildPublic(wishlist)
    if not wishlist then return nil end
    local snap = NormalizeEchoes(wishlist.echoes or wishlist.entries)
    local key = EchoKey(snap)
    local catalog = Catalog()
    if key and catalog
        and type(catalog.FindExactFingerprintId) == "function" then
        return catalog.FindExactFingerprintId(key)
    end
    local id = FindMatchingBuild(snap)
    return id
end

------------------------------------------------------------------------
-- Session lifecycle
------------------------------------------------------------------------

local function StartSession()
    inCombat = true
    Debug("combat start")
    sessionStart = (GetTime and GetTime()) or 0
    latestDps = 0
    peakDps = 0
    sampleTicker = 0
    lastTargetGUID = nil
    lastTargetName = nil
    sessionCategory = nil
    RememberTarget()
end

local function TakeSample()
    local dps = ReadDetailsDps()
    if dps and dps > 0 then
        latestDps = dps
        if dps > peakDps then peakDps = dps end
    end
end

local function CommitSession(category)
    inCombat = false
    Debug("combat end; category=" .. tostring(category) .. ", target=" .. tostring(lastTargetName))
    if not category then
        Nexus.lastDpsNote = "ignored: target was not a training dummy or the Lich King"
        Debug(Nexus.lastDpsNote)
        return
    end
    local elapsed = ((GetTime and GetTime()) or 0) - sessionStart
    local minSessionSecs = DPS.MinimumDuration(category)
    if elapsed < minSessionSecs then
        Nexus.lastDpsNote = "ignored: session shorter than " .. minSessionSecs .. " seconds"
        Debug(Nexus.lastDpsNote .. "; elapsed=" .. tostring(elapsed))
        return
    end

    -- Prefer the completed segment's final DPS. Peak is only a fallback for
    -- Details builds that rotate the segment before PLAYER_REGEN_ENABLED.
    TakeSample()
    local sessionDps = latestDps > 0 and latestDps or peakDps
    if not sessionDps or sessionDps <= 0 then
        Nexus.lastDpsNote = "ignored: Details! returned no player DPS"
        Debug(Nexus.lastDpsNote)
        return
    end

    local snap = SnapshotEchoes()
    local key = EchoKey(snap)
    if not key then
        Nexus.lastDpsNote = "ignored: no owned Echo snapshot was available"
        Debug(Nexus.lastDpsNote)
        return
    end

    local player = (UnitName and UnitName("player")) or "?"
    local buildId, build = FindMatchingBuild(snap)
    local localOwner = OwnerKey(player)
    if buildId and (Identity.SavedMirrorKind(build) ~= "ordinary"
        or Identity.VerifiedOwnerKey(build) ~= localOwner) then
        -- Exact fingerprints are content matches, not relationship authority.
        -- Let the Community owner create or reuse this character's own page
        -- instead of persisting a foreign or unverified catalog identity.
        buildId, build = nil, nil
    end
    local level = (UnitLevel and UnitLevel("player")) or 0
    MigrateLegacyLeaderboard()
    local dpsFloor = math.floor(sessionDps)
    local existing = PersonalForKey(key, category)
    Debug("commit " .. tostring(category) .. ": dps=" .. tostring(dpsFloor)
        .. ", key=" .. tostring(key) .. ", existing="
        .. tostring(existing and existing.dps or "none"))

    if not existing or dpsFloor > (tonumber(existing.dps) or 0) then
        local stamp = (time and time()) or 0
        local localClass = select(2, UnitClass and UnitClass("player")) or "UNKNOWN"
        -- Capture locked perks (permanent baseline echoes) at record time
        -- so the leaderboard can display the full 85-echo picture.
        local lockedSnap = nil
        if Adapter and Adapter.LockedOwned then
            local lo = Adapter.LockedOwned()
            if lo and type(lo.bySpell) == "table" and next(lo.bySpell) then
                local ls = {}
                for spellId, count in pairs(lo.bySpell) do
                    ls[#ls+1] = { spellId=spellId, count=count }
                end
                table.sort(ls, function(a,b) return a.spellId < b.spellId end)
                if #ls > 0 then lockedSnap = ls end
            end
        end
        local personalRow = {
            dps = dpsFloor, level = level, ts = stamp,
            duration = elapsed, player = player,
            buildId = buildId, echoes = snap, fingerprint = key,
            lockedEchoes = lockedSnap,
            class = localClass,
            ownerKey = OwnerKey(player), realm = CurrentRealm(),
            protocolVersion = PROTOCOL_VERSION,
            ownerVerified = true,
        }
        SetStoreRow(PersonalBestStore(), key, category, personalRow)

        -- Only this character's highest result for the encounter enters the
        -- public mesh. Exact-set personal bests remain local, so experimenting
        -- with weaker loadouts cannot create or sync leaderboard bloat.
        local characterBucket = CharacterBestStore()[category]
        local pk = CharacterKey(player, personalRow.ownerKey,
            personalRow.realm)
        local previousCharacterBest = characterBucket[pk]
        local becameCharacterBest = BetterRow(personalRow, previousCharacterBest)
        if becameCharacterBest then
            local C = Nexus.CommunityBuilds
            if C and C.EnsureDpsBuildForEchoes then
                local ok, ensuredId, ensuredBuild = pcall(C.EnsureDpsBuildForEchoes, snap, category, personalRow)
                if ok and ensuredId then buildId, build = ensuredId, ensuredBuild or build end
                personalRow.buildId = buildId
            end
            characterBucket[pk] = personalRow

            -- If the previous winning page was an automatically generated
            -- local record page and no leaderboard row references it anymore,
            -- remove it from the mesh instead of accumulating dead experiments.
            local oldBuildId = previousCharacterBest and previousCharacterBest.buildId
            if oldBuildId and oldBuildId ~= buildId and C and C.DeleteBuild then
                local stillUsed = false
                for _, encounter in ipairs({ "dummy", "lk" }) do
                    for _, publicRow in pairs(CharacterBestStore()[encounter] or {}) do
                        if publicRow and publicRow.buildId == oldBuildId then stillUsed = true; break end
                    end
                    if stillUsed then break end
                end
                local oldBuild = CatalogGet(oldBuildId)
                if not stillUsed and oldBuild and oldBuild.autoDps and oldBuild.isMine then
                    pcall(C.DeleteBuild, oldBuildId)
                end
            end
        end
        BumpDps("personal best committed", becameCharacterBest and {
            scope="record", category=category, player=player,
            ownerKey=personalRow.ownerKey, realm=personalRow.realm,
            characterKey=pk,
        } or {scope="local"})
        if Nexus.DataRetention and Nexus.DataRetention.Request then
            Nexus.DataRetention.Request("personal DPS best committed")
        end
        local catLabel = category == "lk" and "Lich King" or "Training Dummy"
        local setLabel = build and build.title or "current Echo set"
        print(string.format(
            "|cff7fd5ffNexus:|r |cff4dff80New best for '%s' (%s): %s DPS!|r",
            tostring(setLabel), catLabel,
            dpsFloor >= 1000000 and string.format("%.2fM", dpsFloor / 1000000)
            or string.format("%dk", math.floor(dpsFloor / 1000))))

        -- Global comparison is only meaningful when the exact current Echo
        -- set is already a published community build.
        local characterNow = CharacterBestStore()[category][pk]
        if characterNow == personalRow and Sync and Sync.BroadcastDpsRecord then
            pcall(Sync.BroadcastDpsRecord, {
                protocolVersion = PROTOCOL_VERSION, fingerprint = key,
                echoes = snap, category = category, dps = dpsFloor,
                duration = elapsed, ts = stamp, player = player,
                level = level, buildId = buildId, lockedEchoes = lockedSnap,
                class = localClass, ownerKey = personalRow.ownerKey,
                realm = personalRow.realm, ownerVerified = true,
            })
        end
    end

    Nexus.lastDpsNote = string.format("%s: %d DPS (%s)",
        category, dpsFloor, build and build.title or "current Echo set")
    Debug("saved/retained best: " .. Nexus.lastDpsNote)

    RequestDataViewRefresh()
    if Nexus.RefreshPanel then
        pcall(Nexus.RefreshPanel)
    end
end

------------------------------------------------------------------------
-- Sync receive
------------------------------------------------------------------------

local function IsBetterPublicRecord(candidate, existing)
    return BetterRow(candidate, existing)
end

local function ShortIdentity(value)
    return Identity.PlayerKey(value) or ""
end

function DPS.SyncBucket(category, player)
    if category ~= "dummy" and category ~= "lk" then return nil end
    local value = DpsBucket(category, player)
    return value >= 1 and value <= DPS_BUCKETS and value or nil
end

-- Exact O(1) authority guard for response-bucket claims. A matching relay
-- claim may suppress another relay, but never the local character's own
-- eligible dummy/LK row. Deliberately avoid migration, indexing, or a store
-- traversal here: response reconciliation can ask once per received claim.
function DPS.LocalOwnsDpsBucket(bucket)
    bucket = tonumber(bucket)
    if not bucket or bucket ~= math.floor(bucket)
        or bucket < 1 or bucket > DPS_BUCKETS then return false end
    local me = (UnitName and UnitName("player")) or nil
    local playerKey = me and CurrentCharacterKey(me) or nil
    if not playerKey or playerKey == "invalid" then return false end
    local store = CharacterBestStore()
    local legacyKey = me and PlayerKey(me) or nil
    local row = store.dummy
        and (store.dummy[playerKey] or store.dummy[legacyKey])
    if type(row) == "table"
        and DPS.VerifiedOwnerKey(row) == playerKey
        and (tonumber(row.dps) or 0) > 0
        and DPS.IsDurationEligible("dummy", row.duration)
        and DpsBucket("dummy", me) == bucket then
        return true
    end
    row = store.lk and (store.lk[playerKey] or store.lk[legacyKey])
    if type(row) == "table"
        and DPS.VerifiedOwnerKey(row) == playerKey
        and (tonumber(row.dps) or 0) > 0
        and DPS.IsDurationEligible("lk", row.duration)
        and DpsBucket("lk", me) == bucket then
        return true
    end
    return false
end

local function ReceiveRecord(record, transportSender, relayed)
    if type(record) ~= "table" then return RejectReceive("schema") end
    if not WireDpsAliasesAgree(record) then return RejectReceive("schema") end
    local version = tonumber(record.v or record.protocolVersion)
    local category = record.c or record.category
    local dps = tonumber(record.d or record.dps)
    local duration = tonumber(record.u or record.duration) or 0
    local ts = tonumber(record.t or record.ts) or 0
    local player = tostring(record.p or record.player or "")
    local level = tonumber(record.l or record.level) or 0
    local playerClass = record.k or record.class
    local ownerKey = record.o or record.ownerKey
    local realm = record.r or record.realm
    local rawEchoes = record.e or record.echoes
    if not ValidWireEchoList(rawEchoes) then return RejectReceive("schema") end
    local echoes = NormalizeEchoes(rawEchoes)
    local computed = EchoKey(echoes)
    local claimed = record.f or record.fingerprint
    local hash = record.h or record.loadoutHash
    local fingerprint = computed or (type(claimed)=="string" and claimed or nil) or (type(hash)=="string" and ("@"..hash) or nil)
    if not Identity.ValidPlayer(player) or #player > 64 then
        return RejectReceive("schema")
    end
    local ownerRealm, canonicalOwner
    if ownerKey ~= nil then
        canonicalOwner = Identity.CanonicalOwnerKey(ownerKey)
        if canonicalOwner then
            ownerRealm = canonicalOwner:match("@(.+)$")
        end
        if not canonicalOwner
            or not Identity.OwnerKeyMatchesAuthor(canonicalOwner, player) then
            return RejectReceive("owner_sender")
        end
    end
    if realm ~= nil and (type(realm) ~= "string" or #realm > 96
        or realm:find("[%c|%s]") or not Identity.OwnerKey(player, realm)) then
        return RejectReceive("schema")
    end
    if ownerRealm and realm then
        local realmOwner = Identity.OwnerKey(player, realm)
        local canonicalRealm = realmOwner and realmOwner:match("@(.+)$")
        if ownerRealm ~= canonicalRealm then return RejectReceive("owner_sender") end
    end

    if category ~= "dummy" and category ~= "lk" then
        return RejectReceive("invalid_category")
    end
    if not DPS.IsDurationEligible(category, duration) then
        return RejectReceive("duration")
    end
    if not relayed and transportSender ~= nil
        and not Identity.SamePlayer(player, transportSender) then
        return RejectReceive("owner_sender")
    end
    if relayed and (transportSender == nil
        or Identity.SamePlayer(player, transportSender)) then
        return RejectReceive("relay_authorization")
    end

    -- Wire schema validation. Category, duration, and authority are split out
    -- above so diagnostics identify the actionable rejection boundary.
    if (version ~= 2 and version ~= 3 and version ~= 4 and version ~= 5
            and version ~= 6 and version ~= PROTOCOL_VERSION)
        or not FiniteNumber(dps) or dps <= 0 or dps > 500000000
        or not FiniteNumber(ts) or ts <= 0
        or not Identity.ValidPlayer(player) or #player > 64
        or not FiniteNumber(level) or level < 1 or level > 80
        or level ~= math.floor(level)
        or type(playerClass) ~= "string"
        or not VALID_CLASS[playerClass:upper()]
        or not echoes or #echoes < 1 or #echoes > 120
        or not computed or not fingerprint then
        return RejectReceive("schema")
    end

    -- Integrity checks retain only a scalar reason count.
    if (computed and claimed and claimed ~= computed)
        or (computed and hash and EchoHashFromKey(computed) ~= hash) then
        return RejectReceive("integrity")
    end
    -- DPS floor: no real build produces under 1k active-time DPS
    if dps < 1000 then return RejectReceive("integrity") end
    -- Hard DPS ceiling: set high to accommodate extreme builds while
    -- still blocking obviously fabricated absurd values.
    if dps > 500000000 then return RejectReceive("integrity") end
    -- Timestamp sanity: reject records claiming to be from the future
    local nowTs = (time and time()) or 0
    if nowTs > 1000000000 and ts > 0 and ts > nowTs + 300 then
        return RejectReceive("integrity")
    end
    -- Echo count sanity
    if #echoes < 1 or #echoes > 120 then return RejectReceive("integrity") end

    -- Future-schema profiles are readable through a transient empty view, but
    -- inbound records must not be committed there and reported as accepted.
    if StorageReadOnly() then
        return RejectReceive("storage"), "storage"
    end

    local directSender = not relayed and transportSender ~= nil
        and Identity.SamePlayer(player, transportSender)
    local directOwner = directSender
        and DPS.HasCanonicalOwnerIdentity(record) == true
        and record.claimedOwnerKey == nil and record.relaySender == nil
        and Identity.TransportOwns(canonicalOwner, transportSender)
    local transportOwner = directSender
        and Identity.CanonicalOwnerFromTransport(transportSender) or nil
    local transportRealm = transportOwner
        and transportOwner:match("@(.+)$") or nil
    local storageOwner, storageRealm
    if directOwner then
        storageOwner, storageRealm = canonicalOwner, realm or ownerRealm
    elseif directSender then
        storageOwner, storageRealm = transportOwner, transportRealm
    else
        storageOwner, storageRealm = canonicalOwner, realm or ownerRealm
    end

    local rawLocked = record.lk or record.lockedEchoes
    if rawLocked ~= nil and not ValidWireEchoList(rawLocked) then
        return RejectReceive("schema")
    end
    local incomingLocked = NormalizeEchoes(rawLocked)

    MigrateLegacyLeaderboard()
    local bucket = CharacterBestStore()[category]
    local characterKey = CharacterKey(player, storageOwner, storageRealm)
    local existing = bucket[characterKey]
    local existingKey = characterKey
    local legacyKey = PlayerKey(player)
    if not existing and legacyKey ~= characterKey then
        local legacy = bucket[legacyKey]
        local incomingBuildId = record.b or record.buildId
        local legacyBuildId = legacy and legacy.buildId
        local legacyBuildMissing = legacyBuildId == nil or legacyBuildId == ""
        local legacyBuildKind = type(legacyBuildId)
        local legacyBuildValid = legacyBuildMissing
            or legacyBuildKind == "string" and #legacyBuildId <= 96
                and Identity.ValidDisplayText(legacyBuildId, 96, false)
            or legacyBuildKind == "number" and FiniteNumber(legacyBuildId)
        local legacyDuration = legacy and legacy.duration
        local legacyHash = legacy and type(legacy.loadoutHash) == "string"
            and legacy.loadoutHash or nil
        local incomingHash = tostring(hash or EchoHashFromKey(fingerprint) or "")
        local rawLegacyLocked = legacy and legacy.lockedEchoes
        local resolvedLegacyLocked = legacy and StoredEchoes(legacy, true) or nil
        local lockedReference = legacy and legacy.lockedEvidenceKey
        local lockedReferenceAbsent = lockedReference == nil
            or lockedReference == ""
        local lockedReferenceValid = lockedReferenceAbsent
        if not lockedReferenceAbsent and type(lockedReference) == "string" then
            local evidence = Nexus and Nexus.LoadoutEvidence
            if evidence and type(evidence.Resolve) == "function" then
                local ok, normalized, exact = pcall(evidence.Resolve,
                    lockedReference, type(rawLegacyLocked) == "table"
                        and rawLegacyLocked or nil, {forceLocked=true})
                lockedReferenceValid = ok and type(normalized) == "table"
                    and exact == lockedReference
                    and resolvedLegacyLocked ~= nil
            end
        end
        local rawLockedMissing = rawLegacyLocked == nil
            or type(rawLegacyLocked) == "table"
                and next(rawLegacyLocked) == nil
        local legacyLockedValid = rawLockedMissing
            or ValidWireEchoList(rawLegacyLocked)
        if resolvedLegacyLocked ~= nil then
            legacyLockedValid = legacyLockedValid
                and ValidWireEchoList(resolvedLegacyLocked)
        end
        local legacyLockedMissing = rawLockedMissing
            and resolvedLegacyLocked == nil and lockedReferenceAbsent
        local legacyLockedKey = resolvedLegacyLocked
            and LockedKey(resolvedLegacyLocked) or nil
        local sameLegacyRecord = legacy
            and math.floor(tonumber(legacy.dps) or 0) == math.floor(dps)
            and tonumber(legacy.ts or 0) == tonumber(ts or 0)
            and (legacyDuration == nil or legacyDuration == 0
                or type(legacyDuration) == "number"
                    and legacyDuration == tonumber(duration or 0))
            and tostring(legacy.fingerprint or "") == tostring(fingerprint or "")
            and (legacy.loadoutHash == nil or legacyHash == ""
                or legacyHash == incomingHash)
            and legacyBuildValid
            and (legacyBuildMissing or incomingBuildId == nil
                or type(legacyBuildId) == type(incomingBuildId)
                    and legacyBuildId == incomingBuildId)
            -- Missing legacy metadata may be enriched during an otherwise
            -- exact bridge. Conflicting represented metadata cannot retire it.
            and legacyLockedValid and lockedReferenceValid
            and (legacyLockedMissing
                or legacyLockedKey == LockedKey(incomingLocked))
        if sameLegacyRecord then
            existing, existingKey = legacy, legacyKey
        end
    end
    local legacyLocal = not relayed and transportSender == nil
    local existingVerifiedOwner = existing and DPS.VerifiedOwnerKey(existing)
    local promotedBuildId = directOwner and existing
        and existingVerifiedOwner ~= canonicalOwner and existing.buildId or nil
    local row = {
        dps = math.floor(dps), level = level, ts = ts, duration = duration,
        player = player,
        class = playerClass and tostring(playerClass):upper() or nil,
        ownerKey = directOwner and canonicalOwner
            or (relayed or legacyLocal) and canonicalOwner or nil,
        realm = directOwner and (realm and Identity.OwnerKey(player, realm):match("@(.+)$")
                or ownerRealm)
            or directSender and transportRealm
            or (relayed or legacyLocal) and (realm and Identity.OwnerKey(player, realm):match("@(.+)$")
                or ownerRealm) or nil,
        buildId = record.b or record.buildId or promotedBuildId,
        echoes = echoes, fingerprint = fingerprint, loadoutHash = hash or EchoHashFromKey(fingerprint),
        lockedEchoes = incomingLocked,
        protocolVersion = PROTOCOL_VERSION,
        ownerVerified = directOwner and true or false,
        relaySender = not directOwner and transportSender or nil,
        _promotedFromUnverified = promotedBuildId and true or nil,
    }
    -- A relayed row may fill an empty slot, but it never overwrites an existing
    -- row. The established nil-sender compatibility path may still replace a
    -- better unverified row, but it cannot displace verified owner evidence.
    -- Conversely, a later direct owner copy supersedes relay provenance even
    -- when the score ties.
    if existing and not directOwner
        and (not legacyLocal or existingVerifiedOwner ~= nil) then
        return RejectReceive("relay_authorization")
    end
    local better = directOwner and existing
        and existingVerifiedOwner ~= canonicalOwner
        or IsBetterPublicRecord(row, existing)
    if not better then
        -- Metadata enrichment: the same winning parse may have been received
        -- before its source client's locked-perk API was ready. Accept a later
        -- copy that fills the previously empty locked-Echo snapshot.
        local sameRecord = existing
            and math.floor(tonumber(existing.dps) or 0) == math.floor(dps)
            and tonumber(existing.ts or 0) == tonumber(ts or 0)
            and tostring(existing.fingerprint or "") == tostring(fingerprint or "")
        if sameRecord then
            local enriched = false
            local normalizedClass = NormalizeClass(playerClass)
            if normalizedClass and existing.class ~= normalizedClass then
                existing.class = normalizedClass
                enriched = true
            end
            if directOwner and existingVerifiedOwner ~= canonicalOwner then
                existing.player = player
                existing.ownerKey = canonicalOwner
                existing.realm = row.realm
                existing.ownerVerified = true
                existing.o, existing.p, existing.r = nil, nil, nil
                existing.claimedOwnerKey, existing.relaySender = nil, nil
                existing._originVerified = nil
                enriched = true
            elseif row.realm and not existing.realm then
                existing.realm = row.realm
                enriched = true
            end
            if incomingLocked and not StoredEchoes(existing, true) then
                existing.lockedEchoes = incomingLocked
                ReferenceEvidence(existing)
                enriched = true
            end
            local rekeyed = existingKey ~= characterKey
            if rekeyed then
                bucket[existingKey] = nil
                bucket[characterKey] = existing
                enriched = true
            end
            if enriched then
                BumpDps(rekeyed and "public record identity enriched"
                    or "public record enriched", {
                        scope=rekeyed and "record" or "metadata",
                        category=category,player=player,
                        ownerKey=existing.ownerKey,realm=existing.realm,
                        characterKey=characterKey,
                        previousCharacterKey=rekeyed and existingKey or nil,
                    })
                return true
            end
        end
        local existingStamp = tonumber(existing and existing.ts) or 0
        return RejectReceive(existing and ts < existingStamp
            and "stale_record" or "duplicate_not_better")
    end
    -- Persist evidence only after the row wins the authority and replacement
    -- decision. Rejected relays must not grow the shared evidence pool.
    ReferenceEvidence(row)
    -- A DPS row must always lead to a viewable/copyable exact loadout, even
    -- when the DPS chunks arrive before the corresponding build broadcast.
    local C = Nexus.CommunityBuilds
    if echoes and C and C.EnsureDpsBuildForEchoes then
        local ok, ensuredId = pcall(C.EnsureDpsBuildForEchoes, echoes, category, row)
        if ok and ensuredId then
            row.buildId = ensuredId
        elseif row.buildId then
            -- The claimed opaque ID collided with a different loadout or
            -- owner. Retry without it so the exact evidence receives a safe,
            -- deterministic record page instead of attaching to that build.
            row.buildId = nil
            local safeOk, safeId = pcall(
                C.EnsureDpsBuildForEchoes, echoes, category, row)
            if safeOk and safeId then row.buildId = safeId end
        end
    end
    row._promotedFromUnverified = nil
    local previousCharacterKey = existing and existingKey ~= characterKey
        and existingKey or nil
    if previousCharacterKey then bucket[previousCharacterKey] = nil end
    bucket[characterKey] = row
    BumpDps("public record received", {
        scope="record", category=category, player=player,
        ownerKey=row.ownerKey, realm=row.realm, characterKey=characterKey,
        previousCharacterKey=previousCharacterKey,
    })
    if Nexus.DataRetention and Nexus.DataRetention.Request then
        Nexus.DataRetention.Request("public DPS record received")
    end
    RequestDataViewRefresh()
    return true
end


function DPS.ReceiveRecord(record, transportSender)
    return ReceiveRecord(record, transportSender, false)
end

-- Response-only relay admission. SyncInbound establishes the intended
-- requester/receive-window/bucket context before this narrower storage path is
-- reachable; ordinary callers retain the direct-owner ReceiveRecord contract.
function DPS.ReceiveRelayedRecord(record, transportSender)
    return ReceiveRecord(record, transportSender, true)
end

function DPS.ReceiveSubmission(buildId, player, dps, level, category, ts,
        duration)
    dps = tonumber(dps); level = tonumber(level) or 0
    category = (category == "lk" or category == "dummy") and category or "dummy"
    local key = BuildKey(buildId)
    if not (key and player and dps and dps > 0
        and DPS.IsDurationEligible(category, duration)) then return false end
    local bucket = CharacterBestStore()[category]
    local characterKey = CharacterKey(player)
    local existing = bucket[characterKey]
    local row = {
        dps = dps, level = level, ts = ts or 0, duration=duration,
        player = player, buildId = buildId,
        echoes = BuildSnapshot(CatalogGet(buildId)),
        fingerprint = key, protocolVersion = PROTOCOL_VERSION,
    }
    ReferenceEvidence(row)
    if not IsBetterPublicRecord(row, existing) then return false end
    bucket[characterKey] = row
    BumpDps("legacy submission received", {
        scope="record", category=category, player=player,
        characterKey=characterKey,
    })
    if Nexus.DataRetention and Nexus.DataRetention.Request then
        Nexus.DataRetention.Request("legacy DPS record received")
    end
    RequestDataViewRefresh()
    return true
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

function DPS.OnCombatStart() StartSession() end

function DPS.OnCombatEnd()
    if not inCombat then return end
    RememberTarget()
    local category = sessionCategory or ClassifyTarget(lastTargetGUID, lastTargetName)
    CommitSession(category)
    sessionCategory = nil
end

function DPS.OnUpdate(elapsed)
    if not inCombat then return end
    RememberTarget()
    sampleTicker = sampleTicker + (elapsed or 0)
    if sampleTicker >= SAMPLE_INTERVAL then
        sampleTicker = 0
        TakeSample()
    end
end

function DPS.Init(adapter, sync)
    Adapter, Sync = adapter, sync
    responseGeneration = responseGeneration + 1
    ResetRejectionStats()
    ResetOutboundStats()
    -- Init may bind a different SavedVariables profile while revision counters
    -- coincidentally match. Cached identities and response authority are scoped
    -- to the represented store, not only to its scalar revision.
    identityIndex.initialized = false
    InvalidateAllDpsHashes()
    NexusDB = NexusDB or {}
    if Nexus.LoadoutEvidence and Nexus.LoadoutEvidence.Init then
        Nexus.LoadoutEvidence.Init(NexusDB)
    end
    if Catalog() and Catalog().Init then
        Catalog().Init(NexusDB, Nexus.BundledBuilds)
    end
    MigrateLocalLockedBaseline()
    local migrated = MigrateLegacyLeaderboard()
    if RepairCurrentCharacterClass() and not migrated then
        BumpDps("local class repaired", {scope="metadata"})
    end
    Debug("initialized; current tracked key=" .. tostring(DPS.GetCurrentEchoKey()))
end

function DPS.IsEnabled() return true end
