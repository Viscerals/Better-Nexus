-- Nexus: core/DpsCapture.lua
--
-- Automatically records completed Training Dummy and Lich King sessions
-- from Details!. Results are keyed by the player's EXACT owned Echo set.
-- This means the panel can keep a personal best while a wishlist is still
-- incomplete, and community build leaderboards only compare players using
-- the exact Echo loadout published by that build.

Nexus = Nexus or {}
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
local MIN_LK_SESSION_SECS = 20
local MIN_DUMMY_SESSION_SECS = 30
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

local function NormalizeClass(class)
    class = type(class) == "string" and class:upper() or nil
    return class and VALID_CLASS[class] and class or nil
end

local Adapter, Sync
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

local function DB()
    NexusDB = NexusDB or {}
    NexusDB.dpsCapture = NexusDB.dpsCapture or {}
    return NexusDB.dpsCapture
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

local function RequestRetention(reason)
    local retention = Nexus and Nexus.DataRetention
    if retention and type(retention.Request) == "function" then
        pcall(retention.Request, reason)
    end
end

local function ReleaseSupersededAutoBuild(buildId)
    local retention = Nexus and Nexus.DataRetention
    if buildId and retention
        and type(retention.ReleaseSupersededAutoBuild) == "function" then
        pcall(retention.ReleaseSupersededAutoBuild, buildId, NexusDB)
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
    return tostring(name or "?"):lower()
end

local function CurrentRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then realm = GetRealmName and GetRealmName() end
    return tostring(realm or "unknown"):lower():gsub("%s+", "")
end

local function OwnerKey(name, realm)
    name = tostring(name or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    realm = tostring(realm or CurrentRealm()):lower():gsub("%s+", "")
    return name .. "@" .. realm
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
            local rowOwner = tostring(row and row.ownerKey or ""):lower()
            local derivedOwner = row and OwnerKey(row.player,
                row.realm and row.realm ~= "" and row.realm or realm)
            if row and (rowOwner == localOwner or derivedOwner == localOwner) then
                if row.class ~= class then row.class = class; changed = true end
                local prow = row.fingerprint and personal[row.fingerprint]
                    and personal[row.fingerprint][category]
                if prow then
                    if prow.class ~= class then prow.class = class; changed = true end
                    if not prow.ownerKey then
                        prow.ownerKey = localOwner
                        changed = true
                    end
                    if not prow.realm then
                        prow.realm = realm
                        changed = true
                    end
                end

                local build = row.buildId and builds[row.buildId]
                if build and build.autoDps then
                    local buildOwner = tostring(build.ownerKey or ""):lower()
                    local legacyOwned = buildOwner == ""
                        and tostring(build.author or ""):lower() == me:lower()
                    if buildOwner == localOwner or legacyOwned then
                        local buildChanged = false
                        if build.class ~= class then build.class = class; buildChanged = true end
                        local title = tostring(build.title or "")
                        if title:match("^[%a%s]+ Record Loadout$") then
                            local corrected = (CLASS_LABEL[class] or class) .. " Record Loadout"
                            if title ~= corrected then build.title = corrected; buildChanged = true end
                        end
                        if not build.ownerKey then build.ownerKey = localOwner; buildChanged = true end
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

local legacyMigrated = false
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
    if legacyMigrated then return false end
    legacyMigrated = true
    local db = DB()
    local me = (UnitName and UnitName("player")) or "?"
    local personal = PersonalBestStore()
    local character = CharacterBestStore()
    local changed = false

    -- Normalize any existing CharacterBestStore keys that were stored
    -- with original casing (pre-PlayerKey-lowercase era). Collect all
    -- non-lowercase keys and merge them into the canonical lowercase key.
    for _, category in ipairs({ "dummy", "lk" }) do
        local bucket = character[category]
        if type(bucket) == "table" then
            local toMerge = {}
            for k in pairs(bucket) do
                if k ~= k:lower() then toMerge[#toMerge+1] = k end
            end
            for _, k in ipairs(toMerge) do
                local lk = k:lower()
                local row = bucket[k]
                if BetterRow(row, bucket[lk]) then
                    bucket[lk] = row
                    changed = true
                end
                bucket[k] = nil
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
        if PlayerKey(row.player) == PlayerKey(me) and fingerprint then
            personal[fingerprint] = personal[fingerprint] or {}
            if BetterRow(row, personal[fingerprint][category]) then
                personal[fingerprint][category] = row
                changed = true
            end
        end
        local bucket = character[category]
        if bucket then
            local pk = PlayerKey(row.player)
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
    return changed
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

    local me = PlayerKey((UnitName and UnitName("player")) or "?")
    local changed = false
    local changedRows = {}
    for _, category in ipairs({ "dummy", "lk" }) do
        local row = CharacterBestStore()[category][me]
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
local function CorrectLockedRows(store, lockedBySpell)
    lockedBySpell = type(lockedBySpell) == "table" and lockedBySpell or {}
    -- If no locked echoes are known yet, abort. Subtracting zero from
    -- everything would produce identical keys (no-op), but if the locked
    -- data simply hasn't loaded yet we must not run at all -- a partially
    -- loaded lockedBySpell could subtract fewer echoes than the true
    -- baseline and generate wrong keys that orphan existing records.
    local anyLocked = false
    for _ in pairs(lockedBySpell) do anyLocked = true; break end
    if not anyLocked then return end

    local moves = {}
    for oldKey, categories in pairs(store) do
        for category, row in pairs(type(categories) == "table" and categories or {}) do
            local oldEchoes = StoredEchoes(row, false)
            if oldEchoes then
                local corrected = {}
                for _, e in ipairs(oldEchoes) do
                    local n = math.max(0, (tonumber(e.count) or 0) - (tonumber(lockedBySpell[e.spellId]) or 0))
                    if n > 0 then corrected[#corrected + 1] = { spellId=e.spellId, count=n } end
                end
                corrected = NormalizeEchoes(corrected)
                local newKey = EchoKey(corrected)
                -- Only move if we produced a valid, different key.
                -- If corrected is empty (all echoes were locked) keep
                -- the original record -- don't orphan it.
                if newKey and newKey ~= oldKey then
                    moves[#moves + 1] = {oldKey=oldKey,newKey=newKey,category=category,row=row,echoes=corrected}
                end
            end
        end
    end
    for _, m in ipairs(moves) do
        store[m.newKey] = store[m.newKey] or {}
        local current = store[m.newKey][m.category]
        if not current or (tonumber(m.row.dps) or 0) > (tonumber(current.dps) or 0) then
            m.row.echoes, m.row.fingerprint = m.echoes, m.newKey
            ReferenceEvidence(m.row)
            store[m.newKey][m.category] = m.row
        end
        -- Only clear the old slot after successfully writing the new one
        if store[m.newKey][m.category] then
            store[m.oldKey][m.category] = nil
            if next(store[m.oldKey]) == nil then store[m.oldKey] = nil end
        end
    end
end

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
    local locked = Adapter and Adapter.LockedOwned and Adapter.LockedOwned()
    if not (locked and locked.synced == true) then
        return
    end
    MigrateLegacyLeaderboard()
    local lockedBySpell = locked and locked.bySpell or {}
    local beforeState = {
        personalBest=DeepCopy(PersonalBestStore()),
        buildBest=DeepCopy(BuildBestStore()),
        characterBest=DeepCopy(CharacterBestStore()),
    }
    local function RevisionIfChanged()
        local changed = not DeepEqual(beforeState.personalBest, PersonalBestStore())
            or not DeepEqual(beforeState.buildBest, BuildBestStore())
            or not DeepEqual(beforeState.characterBest, CharacterBestStore())
        if changed then BumpDps("locked baseline migrated") end
        return changed
    end

    -- Preserve an immutable source before any subtraction. An interrupted
    -- pass restores this snapshot and recomputes instead of subtracting twice.
    if type(db.lockedMigrationSource) ~= "table" then
        db.lockedMigrationSource = {
            personalBest=DeepCopy(PersonalBestStore()),
            buildBest=DeepCopy(BuildBestStore()),
            characterBest=DeepCopy(CharacterBestStore()),
        }
    else
        db.personalBest = DeepCopy(db.lockedMigrationSource.personalBest or {})
        db.buildBest = DeepCopy(db.lockedMigrationSource.buildBest or {})
        db.characterBest = DeepCopy(db.lockedMigrationSource.characterBest
            or { dummy={}, lk={} })
    end

    local ok = pcall(function()
        CorrectLockedRows(PersonalBestStore(), lockedBySpell)
        CorrectLockedRows(BuildBestStore(), lockedBySpell)
        local character = CharacterBestStore()
        local anyLocked = false
        for _ in pairs(lockedBySpell) do anyLocked = true; break end
        if anyLocked then
            for _, category in ipairs({ "dummy", "lk" }) do
                for _, row in pairs(character[category] or {}) do
                    local oldEchoes = StoredEchoes(row, false)
                    if oldEchoes then
                        local corrected = {}
                        for _, e in ipairs(oldEchoes) do
                            local n = math.max(0, (tonumber(e.count) or 0)
                                - (tonumber(lockedBySpell[e.spellId]) or 0))
                            if n > 0 then
                                corrected[#corrected + 1] = {
                                    spellId=e.spellId, count=n }
                            end
                        end
                        corrected = NormalizeEchoes(corrected)
                        local newKey = EchoKey(corrected)
                        if newKey and newKey ~= row.fingerprint then
                            row.echoes, row.fingerprint = corrected, newKey
                            row.loadoutHash = EchoHashFromKey(newKey)
                            ReferenceEvidence(row)
                        end
                    end
                end
            end
        end
    end)
    if not ok then RevisionIfChanged(); return end
    db.lockedMigrationSource = nil
    db.lockedMigrationVersion = LOCKED_MIGRATION_VERSION
    migratedLockedBaseline = true
    RevisionIfChanged()
end

local function BuildSnapshot(build)
    return build and NormalizeEchoes(build.echoes)
end

local function FindMatchingBuild(snap)
    local key = EchoKey(snap)
    if not key then return nil, nil end
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
    return (key and rowKey == key) or (hash and rowHash == hash)
end

local function GlobalForBuild(buildId, key, category)
    MigrateLegacyLeaderboard()
    local hash = EchoHashFromKey(key)
    local best
    local bucket = CharacterBestStore()[category] or {}
    for _, row in pairs(bucket) do
        if RowMatchesBuild(row, buildId, key, hash) and BetterRow(row, best) then
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
    categories={dummy=nil,lk=nil},
    stats={rebuilds=0,rowsScanned=0,indexedRows=0,lookups=0,candidateChecks=0},
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
    local scanned, indexed = 0, 0
    local store = CharacterBestStore()
    for _, category in ipairs({"dummy", "lk"}) do
        local target = categories[category]
        for _, row in pairs(store[category] or {}) do
            scanned = scanned + 1
            if type(row) == "table" then
                local fingerprint = row.fingerprint
                local hash = row.loadoutHash
                    or (fingerprint and EchoHashFromKey(fingerprint))
                AddIdentityRow(target.buildId, row.buildId, row)
                AddIdentityRow(target.fingerprint, fingerprint, row)
                AddIdentityRow(target.hash, hash, row)
                indexed = indexed + 1
            end
        end
    end
    identityIndex.categories = categories
    identityIndex.initialized = true
    identityIndex.revisionSource, identityIndex.observedRevision =
        CurrentDpsRevision()
    identityIndex.stats.rebuilds = identityIndex.stats.rebuilds + 1
    identityIndex.stats.rowsScanned = identityIndex.stats.rowsScanned + scanned
    identityIndex.stats.indexedRows = indexed
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

local function GlobalForIdentity(buildId, key, hash, category)
    EnsureIdentityIndex()
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

function DPS.IdentityLookupStats()
    local stats = identityIndex.stats
    return {
        rebuilds=stats.rebuilds, rowsScanned=stats.rowsScanned,
        indexedRows=stats.indexedRows, lookups=stats.lookups,
        candidateChecks=stats.candidateChecks,
    }
end

-- A build is Details-verified only when a valid public record exists for its
-- exact loadout and the capture met the shared 30-second evidence floor.
function DPS.GetBuildVerification(buildId)
    local key = BuildKey(buildId)
    if not key then return nil end
    local best
    for _, category in ipairs({ "dummy", "lk" }) do
        local row = GlobalForKey(key, category)
        if row and (tonumber(row.duration) or 0) >= MIN_DUMMY_SESSION_SECS then
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
    if not (row and (tonumber(row.dps) or 0) > 0) then return nil end
    return table.concat({ category, tostring(playerKey),
        tostring(math.floor(tonumber(row.dps) or 0)),
        tostring(row.loadoutHash or EchoHashFromKey(row.fingerprint or "") or "0") }, "|")
end

local function ComputeDpsSyncHash()
    local buckets = {}
    for i = 1, DPS_BUCKETS do buckets[i] = {} end
    local store = CharacterBestStore()
    for _, category in ipairs({ "dummy", "lk" }) do
        for playerKey, row in pairs(store[category] or {}) do
            if row and (tonumber(row.dps) or 0) > 0 then
                local b = DpsBucket(category, playerKey)
                buckets[b][#buckets[b]+1] = DpsHashEntry(category, playerKey, row)
            end
        end
    end
    local hashes = {}
    for i = 1, DPS_BUCKETS do hashes[i] = #buckets[i] > 0 and HashStrings(buckets[i]) or "0" end
    return table.concat(hashes, ",")
end

local dpsHashCache = {
    initialized=false, entries={}, hashes={}, dirty={},
    revisionSource=nil, observedRevision=nil,
    stats={
        hits=0, collectionWalks=0, fullRebuilds=0,
        bucketRebuilds=0, targetedInvalidations=0, fullInvalidations=0,
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
    dpsHashCache.dirty[bucket] = nil
    dpsHashCache.stats.bucketRebuilds = dpsHashCache.stats.bucketRebuilds + 1
end

local function WarmDpsHashCache()
    local entries = NewDpsBuckets()
    local store = CharacterBestStore()
    dpsHashCache.stats.collectionWalks = dpsHashCache.stats.collectionWalks + 1
    for _, category in ipairs({ "dummy", "lk" }) do
        for playerKey, row in pairs(store[category] or {}) do
            local entry = DpsHashEntry(category, playerKey, row)
            if entry then
                local bucket = DpsBucket(category, playerKey)
                entries[bucket][category .. "|" .. tostring(playerKey)] = entry
            end
        end
    end
    dpsHashCache.entries, dpsHashCache.hashes, dpsHashCache.dirty = entries, {}, {}
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

local function UpdateDpsHashRecord(category, player)
    if not dpsHashCache.initialized then return end
    if category ~= "dummy" and category ~= "lk" then
        InvalidateAllDpsHashes()
        return
    end
    local playerKey = PlayerKey(player)
    local bucket = DpsBucket(category, playerKey)
    local row = CharacterBestStore()[category][playerKey]
    dpsHashCache.entries[bucket][category .. "|" .. playerKey] =
        DpsHashEntry(category, playerKey, row)
    dpsHashCache.dirty[bucket] = true
    dpsHashCache.stats.targetedInvalidations =
        dpsHashCache.stats.targetedInvalidations + 1
end

local function OnDpsRevision(_, revision, detail)
    dpsHashCache.observedRevision = revision
    if type(detail) == "table" and detail.scope == "record"
        and detail.category and detail.player then
        UpdateDpsHashRecord(detail.category, detail.player)
    elseif type(detail) ~= "table"
        or (detail.scope ~= "local" and detail.scope ~= "metadata") then
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
    return out
end

-- Broadcast only the single highest known result for this exact build.
function DPS.BroadcastBestForBuild(buildId)
    local key, build = BuildKey(buildId)
    if not key or not build or not (Sync and Sync.BroadcastDpsRecord) then return false end
    local sent = false
    local store = CharacterBestStore()
    for _, category in ipairs({ "dummy", "lk" }) do
        for _, row in pairs(store[category] or {}) do
            if row and row.buildId == buildId and (tonumber(row.dps) or 0) > 0 then
                local record = {
                    protocolVersion = PROTOCOL_VERSION, fingerprint = row.fingerprint or key,
                    loadoutHash = row.loadoutHash or build.fingerprintHash or EchoHashFromKey(key),
                    category = category, dps = math.floor(tonumber(row.dps) or 0),
                    duration = tonumber(row.duration) or 0, ts = tonumber(row.ts) or 0,
                    player = row.player or "?", level = tonumber(row.level) or 0, buildId = buildId,
                    class = row.class, ownerKey = row.ownerKey, realm = row.realm,
                    echoes = StoredEchoes(row, false) or BuildSnapshot(build),
                    lockedEchoes = StoredEchoes(row, true),
                }
                local ok, result = pcall(Sync.BroadcastDpsRecord, record)
                if ok and result ~= false then sent = true end
            end
        end
    end
    return sent
end

function DPS.BroadcastAllBuildBests(peerHash, onlyBucket, progress, maxItems)
    local localHash = tostring(DPS.GetSyncHash())
    if peerHash and tostring(peerHash) == localHash then return 0, true end
    progress = type(progress) == "table" and progress or {}
    MigrateLegacyLeaderboard()
    local peerBuckets = SplitBucketHash(peerHash)
    local myBuckets = SplitBucketHash(localHash)
    local legacyPeer = #peerBuckets ~= DPS_BUCKETS
    local stateKey = table.concat({tostring(peerHash or "0"),
        tostring(onlyBucket or "*"), localHash}, "|")
    local state = progress._responseState
    if state and state.key ~= stateKey then
        progress._responseState = nil
        state = nil
    end
    if not state then
        state = {key=stateKey, localHash=localHash, categoryIndex=1,
            cursor=nil, scanComplete=false, candidates={}, sendCursor=1}
        progress._responseState = state
    elseif tostring(DPS.GetSyncHash()) ~= state.localHash then
        progress._responseState = nil
        return 0, false, true, "stale candidate snapshot"
    end

    local limit = tonumber(maxItems)
    if not limit or limit < 1 then limit = math.huge end
    local work, n, progressed = 0, 0, false
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
                    local bucket = DpsBucket(category, playerKey)
                    if (not onlyBucket or bucket == onlyBucket)
                        and (legacyPeer or tostring(peerBuckets[bucket] or "")
                            ~= tostring(myBuckets[bucket] or ""))
                        and row and (tonumber(row.dps) or 0) > 0
                        and Sync and Sync.BroadcastDpsRecord then
                        local loadoutHash = row.loadoutHash
                            or EchoHashFromKey(row.fingerprint or "")
                        local key = table.concat({category, tostring(playerKey),
                            tostring(math.floor(tonumber(row.dps) or 0)),
                            tostring(loadoutHash or "0")}, "|")
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
                                buildId=row.buildId, class=row.class,
                                ownerKey=row.ownerKey, realm=row.realm,
                                echoes=StoredEchoes(row, false),
                                lockedEchoes=StoredEchoes(row, true),
                            },
                        }
                    end
                end
            end
        else
            while state.sendCursor <= #state.candidates
                and progress[state.candidates[state.sendCursor].key] do
                state.sendCursor = state.sendCursor + 1
            end
            if state.sendCursor > #state.candidates then
                return n, true, progressed
            end
            local item = state.candidates[state.sendCursor]
            work = work + 1
            local ok, result, why, retryPrepared = pcall(
                Sync.BroadcastDpsRecord, item.record, item.prepared, true)
            if ok and result ~= false then
                progress[item.key] = "admitted"
                state.sendCursor = state.sendCursor + 1
                item.prepared = nil
                n, progressed = n + 1, true
            elseif ok and why == "sync queue full" then
                item.prepared = retryPrepared or item.prepared
                return n, false, progressed, why
            else
                progress[item.key] = "skipped"
                state.sendCursor = state.sendCursor + 1
                item.prepared = nil
                progressed = true
            end
        end
    end
    local complete = state.scanComplete
        and state.sendCursor > #state.candidates
    return n, complete, progressed
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
    local out = {}
    local seenPlayer = {}   -- dedup by lowercase player name
    for _, row in pairs(CharacterBestStore()[category] or {}) do
        if type(row) == "table" and (tonumber(row.dps) or 0) > 0 then
            local buildId = row.buildId
            local build = CatalogGet(buildId)
            local rowEchoes = StoredEchoes(row, false)
            if build and rowEchoes then
                local buildKey = build.fingerprint
                    or EchoKey(BuildSnapshot(build))
                if row.fingerprint and buildKey
                    and tostring(buildKey) ~= tostring(row.fingerprint) then
                    -- An opaque claimed ID may collide with an unrelated page.
                    -- Keep the verified row exact and detach only the bad view
                    -- association; the evidence itself remains independently
                    -- usable and copyable.
                    build = nil
                end
            end
            if not build and rowEchoes then
                buildId, build = FindMatchingBuild(rowEchoes)
            end
            if build or rowEchoes then
                local pkey = PlayerKey(row.player or "?")
                local entry = {
                    player = row.player or "?", dps = math.floor(tonumber(row.dps) or 0),
                    class = row.class, ownerKey = row.ownerKey, realm = row.realm,
                    level = tonumber(row.level) or 0, ts = tonumber(row.ts) or 0,
                    duration = tonumber(row.duration) or 0, category = category,
                    fingerprint = row.fingerprint, echoes = rowEchoes or BuildSnapshot(build),
                    lockedEchoes = StoredEchoes(row, true),
                    buildId = buildId, build = build,
                }
                -- Keep only the highest-DPS entry per player
                local existing = seenPlayer[pkey]
                if not existing then
                    out[#out + 1] = entry
                    seenPlayer[pkey] = #out
                elseif BetterRow(entry, out[existing]) then
                    out[existing] = entry
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.dps ~= b.dps then return a.dps > b.dps end
        if a.ts ~= b.ts then return a.ts < b.ts end
        return tostring(a.player):lower() < tostring(b.player):lower()
    end)
    return out
end

-- Returns { rank, dps, category, buildTitle } for a named player, or nil
-- if they have no record in the local leaderboard. Rank is 1-based across
-- all players for their best category (dummy preferred over lk when tied).
-- Used by the nameplate module to decorate moused-over players.
function DPS.GetCharacterBest(category, playerName)
    if category ~= "dummy" and category ~= "lk" then return nil end
    MigrateLocalLockedBaseline()
    MigrateLegacyLeaderboard()
    local name = playerName or ((UnitName and UnitName("player")) or "?")
    local row = CharacterBestStore()[category][PlayerKey(name)]
    if not row or (tonumber(row.dps) or 0) <= 0 then return nil end
    return DPS.MaterializeRecord(row)
end

function DPS.GetPlayerInfo(playerName)
    if not playerName or playerName == "" then return nil end
    MigrateLocalLockedBaseline()
    MigrateLegacyLeaderboard()
    local pk = PlayerKey(playerName)
    local best
    for _, category in ipairs({"dummy", "lk"}) do
        local row = CharacterBestStore()[category][pk]
        if row and (tonumber(row.dps) or 0) > 0 then
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
    for opk, row in pairs(bucket) do
        if opk ~= pk and (tonumber(row.dps) or 0) > best.dps then
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
    local minSessionSecs = (category == "dummy") and MIN_DUMMY_SESSION_SECS or MIN_LK_SESSION_SECS
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

    local buildId, build = FindMatchingBuild(snap)
    local player = (UnitName and UnitName("player")) or "?"
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
        }
        SetStoreRow(PersonalBestStore(), key, category, personalRow)

        -- Only this character's highest result for the encounter enters the
        -- public mesh. Exact-set personal bests remain local, so experimenting
        -- with weaker loadouts cannot create or sync leaderboard bloat.
        local characterBucket = CharacterBestStore()[category]
        local pk = PlayerKey(player)
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
        } or {scope="local"})
        RequestRetention("personal DPS best committed")
        local catLabel = category == "lk" and "Lich King" or "Training Dummy"
        local setLabel = build and build.title or "current Echo set"
        print(string.format(
            "|cff7fd5ffNexus:|r |cff4dff80New best for '%s' (%s): %s DPS!|r",
            tostring(setLabel), catLabel,
            dpsFloor >= 1000000 and string.format("%.2fM", dpsFloor / 1000000)
            or string.format("%dk", math.floor(dpsFloor / 1000))))

        -- Global comparison is only meaningful when the exact current Echo
        -- set is already a published community build.
        local characterNow = CharacterBestStore()[category][PlayerKey(player)]
        if characterNow == personalRow and Sync and Sync.BroadcastDpsRecord then
            pcall(Sync.BroadcastDpsRecord, {
                protocolVersion = PROTOCOL_VERSION, fingerprint = key,
                echoes = snap, category = category, dps = dpsFloor,
                duration = elapsed, ts = stamp, player = player,
                level = level, buildId = buildId, lockedEchoes = lockedSnap,
                class = localClass, ownerKey = personalRow.ownerKey,
                realm = personalRow.realm,
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

local function FiniteNumber(value)
    return type(value) == "number" and value == value
        and value < math.huge and value > -math.huge
end

local function ShortIdentity(value)
    local name = tostring(value or ""):gsub("%s+", "")
    name = name:match("^([^-]+)") or name
    return name:lower()
end

local function ValidWireEchoList(source)
    if type(source) ~= "table" then return false end
    local entries, maxIndex, total = 0, 0, 0
    for index, echo in pairs(source) do
        if type(index) ~= "number" or index < 1
            or index ~= math.floor(index) or type(echo) ~= "table" then
            return false
        end
        local spellId = tonumber(echo.spellId or echo.id)
        local count = tonumber(echo.count or echo.stacks or echo.stack) or 1
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

function DPS.ReceiveRecord(record, transportSender)
    if type(record) ~= "table" then return false end
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
    if not ValidWireEchoList(rawEchoes) then return false end
    local echoes = NormalizeEchoes(rawEchoes)
    local computed = EchoKey(echoes)
    local claimed = record.f or record.fingerprint
    local hash = record.h or record.loadoutHash
    local fingerprint = computed or (type(claimed)=="string" and claimed or nil) or (type(hash)=="string" and ("@"..hash) or nil)
    local ownerName, ownerRealm
    if ownerKey ~= nil then
        if type(ownerKey) ~= "string" or #ownerKey > 160
            or ownerKey:find("[%c|]") then return false end
        ownerName, ownerRealm = ownerKey:match("^([^@]+)@([^@]+)$")
        if not ownerName or not ownerRealm
            or ShortIdentity(ownerName) ~= ShortIdentity(player) then
            return false
        end
    end
    if realm ~= nil and (type(realm) ~= "string" or #realm > 96
        or realm:find("[%c|]")) then return false end
    if ownerRealm and realm
        and ownerRealm:gsub("%s+", ""):lower()
            ~= tostring(realm):gsub("%s+", ""):lower() then
        return false
    end

    -- Schema validation
    if (version ~= 2 and version ~= 3 and version ~= 4 and version ~= 5
            and version ~= 6 and version ~= PROTOCOL_VERSION)
        or (category ~= "dummy" and category ~= "lk")
        or not FiniteNumber(dps) or dps <= 0 or dps > 500000000
        or not FiniteNumber(duration) or duration < 30
        or not FiniteNumber(ts) or ts <= 0
        or player == "" or #player > 64 or player:find("[%c|]")
        or not FiniteNumber(level) or level < 1 or level > 80
        or level ~= math.floor(level)
        or type(playerClass) ~= "string"
        or not VALID_CLASS[playerClass:upper()]
        or not echoes or #echoes < 1 or #echoes > 120
        or not computed or not fingerprint
        or (computed and claimed and claimed ~= computed)
        or (computed and hash and EchoHashFromKey(computed) ~= hash)
        or (transportSender ~= nil
            and ShortIdentity(player) ~= ShortIdentity(transportSender)) then
        return false
    end

    -- Integrity checks (deliberately silent -- legitimate clients never trip these)
    -- DPS floor: no real build produces under 1k active-time DPS
    if dps < 1000 then return false end
    -- Session duration floor must match local capture: dummy 30s, LK 20s.
    local minDur = 30
    if duration < minDur then return false end
    -- Hard DPS ceiling: set high to accommodate extreme builds while
    -- still blocking obviously fabricated absurd values.
    if dps > 500000000 then return false end
    -- Timestamp sanity: reject records claiming to be from the future
    local nowTs = (time and time()) or 0
    if nowTs > 1000000000 and ts > 0 and ts > nowTs + 300 then return false end
    -- Echo count sanity
    if #echoes < 1 or #echoes > 120 then return false end

    MigrateLegacyLeaderboard()
    local bucket = CharacterBestStore()[category]
    local existing = bucket[PlayerKey(player)]
    local rawLocked = record.lk or record.lockedEchoes
    if rawLocked ~= nil and not ValidWireEchoList(rawLocked) then return false end
    local incomingLocked = NormalizeEchoes(rawLocked)
    local row = {
        dps = math.floor(dps), level = level, ts = ts, duration = duration,
        player = player,
        class = playerClass and tostring(playerClass):upper() or nil,
        ownerKey = ownerKey and tostring(ownerKey):lower() or nil,
        realm = realm and tostring(realm):lower() or ownerRealm,
        buildId = record.b or record.buildId,
        echoes = echoes, fingerprint = fingerprint, loadoutHash = hash or EchoHashFromKey(fingerprint),
        lockedEchoes = incomingLocked,
        protocolVersion = PROTOCOL_VERSION,
    }
    ReferenceEvidence(row)
    if not IsBetterPublicRecord(row, existing) then
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
            if ownerKey and not existing.ownerKey then
                existing.ownerKey = tostring(ownerKey):lower()
                enriched = true
            end
            if realm and not existing.realm then
                existing.realm = tostring(realm):lower()
                enriched = true
            end
            if incomingLocked and not StoredEchoes(existing, true) then
                existing.lockedEchoes = incomingLocked
                ReferenceEvidence(existing)
                enriched = true
            end
            if enriched then
                BumpDps("public record enriched", {scope="metadata"})
                return true
            end
        end
        return false
    end
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
    local supersededBuildId = existing and existing.buildId
    bucket[PlayerKey(player)] = row
    if supersededBuildId and supersededBuildId ~= row.buildId then
        ReleaseSupersededAutoBuild(supersededBuildId)
    end
    RequestRetention("public DPS record received")
    BumpDps("public record received", {
        scope="record", category=category, player=player,
    })
    RequestDataViewRefresh()
    return true
end

function DPS.ReceiveSubmission(buildId, player, dps, level, category, ts)
    dps = tonumber(dps); level = tonumber(level) or 0
    category = (category == "lk" or category == "dummy") and category or "dummy"
    local key = BuildKey(buildId)
    if not (key and player and dps and dps > 0) then return end
    local bucket = CharacterBestStore()[category]
    local existing = bucket[PlayerKey(player)]
    local row = {
        dps = dps, level = level, ts = ts or 0, player = player, buildId = buildId,
        echoes = BuildSnapshot(CatalogGet(buildId)),
        fingerprint = key, protocolVersion = PROTOCOL_VERSION,
    }
    ReferenceEvidence(row)
    if not IsBetterPublicRecord(row, existing) then return end
    local supersededBuildId = existing and existing.buildId
    bucket[PlayerKey(player)] = row
    if supersededBuildId and supersededBuildId ~= row.buildId then
        ReleaseSupersededAutoBuild(supersededBuildId)
    end
    RequestRetention("legacy DPS record received")
    BumpDps("legacy submission received", {
        scope="record", category=category, player=player,
    })
    RequestDataViewRefresh()
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
    NexusDB = NexusDB or {}
    if Nexus.LoadoutEvidence and Nexus.LoadoutEvidence.Init then
        Nexus.LoadoutEvidence.Init(NexusDB)
    end
    if Catalog() and Catalog().Init then
        Catalog().Init(NexusDB, Nexus.BundledBuilds)
    end
    MigrateLocalLockedBaseline()
    MigrateLegacyLeaderboard()
    if RepairCurrentCharacterClass() then
        BumpDps("local class repaired", {scope="metadata"})
    end
    RequestRetention("DPS initialized")
    Debug("initialized; current tracked key=" .. tostring(DPS.GetCurrentEchoKey()))
end

function DPS.IsEnabled() return true end
