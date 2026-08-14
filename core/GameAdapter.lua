-- Nexus: core/GameAdapter.lua
-- THE ONLY module that reads or writes ProjectEbonhold.* or
-- _G["ProjectEbonholdOptionsService"]. Every getter deep-copies (the client
-- returns live internal tables by reference -- GetActiveEchoLoadout hands out
-- the persisted SavedVariables wishlist itself). Owns the availability
-- predicates, the charge ledger, the whole-loop in-flight gate (released by
-- polling the client's private pending* latches -- freeze success emits no
-- signal at all, banish lands via PerkUI.UpdateSinglePerk), the per-LEVER
-- tome-toggle pending set, and the run-boundary / owned-sync trust model.

Nexus = Nexus or {}
Nexus.GameAdapter = {}
local A = Nexus.GameAdapter
A.DIAGNOSTIC_PASSIVE = false

-- Forward-declare every closure-captured local (Lua 5.1 scoping rule).
local Store
local callbacks
local catalogCache, playerMaskCache
local catalogObservedRef, catalogObservedHint
local catalogPublishedCanonical, catalogPublishedHash
local catalogFailureMessage
local catalogStatus = {
    checks=0, fastHits=0, equivalent=0, rebuilds=0,
    failures=0, familyBlocks=0, scheduled=false,
}
local boardDirty, slotsDirty, dataDirty = true, true, true
local lastBoardSig
local inFlightKind, inFlightSig, pendingOwnPick
local recordedPicks = {}
local ledger = { banish = nil, reroll = nil, freeze = nil, runDataRef = nil, banishThisPush = false }
local selfFreezeSig, selfFreezeIndex
local lastBuildOpAt = -10
local ownedSyncedFlag, ownedRequestAt, ownedRetries = false, nil, 0
local selfCalling = false
local ownedSeen = false
local ownedGeneration, ownedConfirmedGeneration = 0, -1
local ownedRequestGeneration = -1
local ownedBaselineRef, ownedBaselineSig = nil, nil
local boundaryAt = 0     -- time of last run boundary / PEW (owned-sync settle)
local GHOST_OWNED = 25   -- level-1 owned count at/above which we suspect a dead-run ghost
local pewDone = false
local externalActionSeen = false
local hooksInstalled = false
local tomeMutationPausedUntil = 0
-- per-latch watchdog: a client latch stuck >10s with no reply is DEAD for
-- the session (per-action, like the client itself); never a whole-loop stall
local latchSince, deadLatch = {}, {}
local slotsRetryAt, slotsRetries = nil, 0
local slotsRefreshAt = 0
local SLOT_REFRESH_SECONDS = 300
local lastAutoAcceptState, lastRivalState = nil, nil

local CORRECTED_CLASS_MASKS = {
    -- PerkClassMasks.DRUID is a client bug (0x200); every Druid DB row uses
    -- 1024 (ALL = 1535 = 511 + 1024, bit 512 unused). Corrected map:
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}

------------------------------------------------------------------------
-- Raw access helpers (nil-safe on every hop)
------------------------------------------------------------------------

local function PE() return _G.ProjectEbonhold end
local function PS()
    local pe = PE()
    return pe and pe.PerkService
end
local function PerksTbl()
    local pe = PE()
    return pe and pe.Perks
end
local function OptSvc() return _G["ProjectEbonholdOptionsService"] end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil
end

------------------------------------------------------------------------
-- Revision-aware catalog. Ordinary reads are O(1); the keyed noncritical
-- scheduler performs the slower canonical source check for in-place edits.
------------------------------------------------------------------------

local CATALOG_CHECK_INTERVAL = 30

local function CatalogText(value)
    local safe = Nexus.DiagnosticHistory and Nexus.DiagnosticHistory.SafeText
    if type(safe) == "function" then return safe(value, 512) end
    local ok, text = pcall(tostring, value)
    return ok and tostring(text or "") or "unprintable catalog error"
end

local function SourceVersionHint(pe)
    if type(pe) ~= "table" then return "" end
    for _, key in ipairs({"catalogVersion", "databaseVersion", "VERSION", "Version", "version"}) do
        local value = rawget(pe, key)
        local kind = type(value)
        if kind == "string" or kind == "number" then return tostring(value) end
    end
    if type(GetAddOnMetadata) == "function" then
        local ok, value = pcall(GetAddOnMetadata, "ProjectEbonhold", "Version")
        local kind = ok and type(value) or "nil"
        if kind == "string" or kind == "number" then return tostring(value) end
    end
    return ""
end

local function CaptureCatalogSource()
    local pe = PE()
    if type(pe) ~= "table" then return nil, "" end
    return pe.PerkDatabase, SourceVersionHint(pe)
end

local function RecordCatalogFailure(message, familyBlock)
    message = CatalogText(message)
    catalogStatus.failures = catalogStatus.failures + 1
    if familyBlock then catalogStatus.familyBlocks = catalogStatus.familyBlocks + 1 end
    catalogStatus.lastResult = familyBlock and "family-blocked" or "failed"
    catalogStatus.lastError = message
    if message ~= catalogFailureMessage then
        catalogFailureMessage = message
        local errors = Nexus and Nexus.Errors
        if errors and type(errors.Record) == "function" then
            pcall(errors.Record, "GameAdapter.Catalog", message)
        end
    end
end

local function InspectCatalogSource(database, sourceHint)
    catalogStatus.checks = catalogStatus.checks + 1
    catalogObservedRef, catalogObservedHint = database, sourceHint

    local _, classToken = UnitClass("player")
    local mask = CORRECTED_CLASS_MASKS[classToken or ""]
    if not mask then
        -- Do not mark an unresolved login-time class as a durable source
        -- failure. A first build retries once the player is known.
        catalogStatus.lastResult = "waiting-for-class"
        return catalogCache
    end
    if type(database) ~= "table" then
        if catalogCache then RecordCatalogFailure("Project Ebonhold catalog source unavailable") end
        return catalogCache
    end

    local source = Nexus and Nexus.EchoCatalogSource
    if not source or type(source.Materialize) ~= "function" then
        RecordCatalogFailure("EchoCatalogSource module unavailable")
        return catalogCache
    end
    local candidate, canonicalOrError, hash = source.Materialize(
        database, function(spellId) return GetSpellInfo(spellId) end)
    if not candidate then
        RecordCatalogFailure(canonicalOrError)
        return catalogCache
    end
    local canonical = canonicalOrError
    catalogStatus.sourceVersion = sourceHint ~= "" and sourceHint or nil
    catalogStatus.observedHash = hash

    if catalogCache and canonical == catalogPublishedCanonical then
        catalogStatus.equivalent = catalogStatus.equivalent + 1
        catalogStatus.lastResult = "unchanged"
        catalogStatus.lastError = nil
        catalogFailureMessage = nil
        return catalogCache
    end

    if catalogCache and type(source.FamilyDrift) == "function" then
        local drift = source.FamilyDrift(catalogCache, candidate)
        if drift then
            RecordCatalogFailure(string.format(
                "family migration required for spell %s (%s -> %s)",
                tostring(drift.spellId), tostring(drift.before), tostring(drift.after)), true)
            return catalogCache
        end
    end

    candidate.playerMask = mask
    playerMaskCache = mask
    catalogCache = candidate
    catalogPublishedCanonical = canonical
    catalogPublishedHash = hash
    catalogStatus.rebuilds = catalogStatus.rebuilds + 1
    catalogStatus.lastResult = "rebuilt"
    catalogStatus.lastError = nil
    catalogStatus.publishedHash = hash
    catalogStatus.rows = candidate.rowCount
    catalogFailureMessage = nil

    local revisions = Nexus and Nexus.Revisions
    if revisions and type(revisions.Advance) == "function" then
        pcall(revisions.Advance, revisions.CATALOG_CHANGED,
            catalogStatus.rebuilds == 1 and "Echo catalog built" or "Echo catalog source changed")
    end
    return catalogCache
end

function A.Catalog()
    local ok, database, sourceHint = pcall(CaptureCatalogSource)
    if not ok then
        RecordCatalogFailure(database)
        return catalogCache
    end
    if catalogCache and database == catalogObservedRef
        and sourceHint == catalogObservedHint then
        catalogStatus.fastHits = catalogStatus.fastHits + 1
        return catalogCache
    end
    return InspectCatalogSource(database, sourceHint)
end

function A.CheckCatalogSource()
    local ok, database, sourceHint = pcall(CaptureCatalogSource)
    if not ok then
        RecordCatalogFailure(database)
        return false, CatalogText(database)
    end
    local before = catalogCache
    local result = InspectCatalogSource(database, sourceHint)
    local completed = result ~= nil and catalogStatus.lastResult ~= "failed"
        and catalogStatus.lastResult ~= "family-blocked"
        and catalogStatus.lastResult ~= "waiting-for-class"
    return completed, catalogStatus.lastResult, result ~= before
end

function A.CatalogStatus()
    return {
        checks=catalogStatus.checks,
        fastHits=catalogStatus.fastHits,
        equivalent=catalogStatus.equivalent,
        rebuilds=catalogStatus.rebuilds,
        failures=catalogStatus.failures,
        familyBlocks=catalogStatus.familyBlocks,
        scheduled=catalogStatus.scheduled,
        lastResult=catalogStatus.lastResult,
        lastError=catalogStatus.lastError,
        sourceVersion=catalogStatus.sourceVersion,
        observedHash=catalogStatus.observedHash,
        publishedHash=catalogPublishedHash,
        rows=catalogStatus.rows or 0,
    }
end

-- True only once the client can answer per-character getters safely: PEW
-- has fired and UnitName is a real name. Calling GetActiveEchoLoadout /
-- GetPendingRollsCount before this latches the client's poisoned _charKey
-- and resets its pick counter (addendum B5); the main loop gates on it.
function A.Ready()
    if not pewDone then return false end
    local nm = UnitName("player")
    return nm ~= nil and nm ~= "" and nm ~= "Unknown"
end

local function FamilyOf(spellId)
    local cat = A.Catalog()
    return cat and cat.familyOf[spellId] or ("s" .. tostring(spellId))
end

------------------------------------------------------------------------
-- Board (deep copy; guaranteed by FLAG, never position)
------------------------------------------------------------------------

function A.Board()
    local svc = PS()
    local ch = svc and SafeCall(svc.GetCurrentChoice)
    if type(ch) ~= "table" or #ch == 0 then return nil end
    local cards, gi = {}, nil
    local sigParts = {}
    for i = 1, #ch do
        local c = ch[i]
        if type(c) == "table" and c.spellId then
            local card = {
                spellId = c.spellId,
                quality = c.quality or 0,
                family = FamilyOf(c.spellId),
                isFrozen = c.isFrozen and true or false,
                isCarried = c.isCarried and true or false,
                isGuaranteed = c.isGuaranteed and true or false,
                -- stamped onto the live entry by the SS-104 handler; preserve
                justFrozen = c.justFrozen and true or false,
            }
            cards[#cards + 1] = card
            if card.isGuaranteed and not gi then gi = #cards end
            sigParts[#sigParts + 1] = tostring(c.spellId)
                .. (card.isFrozen and "F" or "") .. (card.isCarried and "C" or "")
                .. (card.isGuaranteed and "G" or "") .. (card.justFrozen and "J" or "")
        end
    end
    if #cards == 0 then return nil end
    local sig = table.concat(sigParts, ",")
    local idParts = {}
    for i = 1, #cards do idParts[i] = tostring(cards[i].spellId) end
    local idSig = table.concat(idParts, ",")
    -- our own freeze-in-flight overlay: cleared only when the board changes
    if selfFreezeSig and selfFreezeSig ~= sig then
        selfFreezeSig, selfFreezeIndex = nil, nil
    end
    if selfFreezeSig == sig and selfFreezeIndex and cards[selfFreezeIndex] then
        cards[selfFreezeIndex].justFrozen = true
    end
    return { cards = cards, guaranteedIndex = gi, signature = sig,
             idSignature = idSig }
end

------------------------------------------------------------------------
-- Charges (eventually-consistent client counts + own conservative ledger)
------------------------------------------------------------------------

local function RawRunData()
    local pe = PE()
    local prs = pe and pe.PlayerRunService
    local d = prs and SafeCall(prs.GetCurrentData)
    if type(d) ~= "table" then return nil end
    return d
end

function A.Charges()
    local d = RawRunData()
    local arrived = d ~= nil and (d.remainingBanishes ~= nil or d.totalRerolls ~= nil)
    if not arrived then
        return { banish = 0, freeze = 0, reroll = 0, trustworthy = false, arrived = false }
    end
    -- table identity change = fresh server push: reconcile the ledger
    if ledger.runDataRef ~= d then
        ledger.runDataRef = d
        ledger.banish = tonumber(d.remainingBanishes) or 0
        ledger.reroll = math.max(0,
            (tonumber(d.totalRerolls) or 0) - (tonumber(d.usedRerolls) or 0))
        ledger.freeze = math.max(0,
            (tonumber(d.totalFreezes) or 0) - (tonumber(d.usedFreezes) or 0))
        ledger.banishThisPush = false
    end
    local clientBanish = tonumber(d.remainingBanishes) or 0
    local clientReroll = math.max(0,
        (tonumber(d.totalRerolls) or 0) - (tonumber(d.usedRerolls) or 0))
    local tf, uf = tonumber(d.totalFreezes) or 0, tonumber(d.usedFreezes) or 0
    local clientFreeze = math.max(0, tf - uf)
    -- synthesized legacy formats fabricate remainingBanishes=1 with 0/0 freezes
    local trustworthy = not (tf == 0 and uf == 0 and clientBanish == 1)
    local banish = math.max(0, math.min(clientBanish, ledger.banish or clientBanish))
    local reroll = math.max(0, math.min(clientReroll, ledger.reroll or clientReroll))
    local freeze = math.max(0, math.min(clientFreeze, ledger.freeze or clientFreeze))
    if deadLatch.banish then banish = 0 end     -- dead latch: action is gone
    if deadLatch.reroll then reroll = 0 end
    if deadLatch.freeze then freeze = 0 end
    return {
        banish = banish,
        freeze = freeze,
        reroll = reroll,
        trustworthy = trustworthy, arrived = true,
        banishSpentThisPush = ledger.banishThisPush,
    }
end

------------------------------------------------------------------------
-- Owned (current-run granted ∪ recorded picks; trust model)
------------------------------------------------------------------------

-- deterministic signature of the CLIENT-reported owned set (no recorded
-- picks): used to detect the post-reset refresh after a run boundary
local function ClientOwnedSig(bySpell)
    local ids = {}
    for id in pairs(bySpell) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for i = 1, #ids do
        parts[i] = ids[i] .. ":" .. bySpell[ids[i]]
    end
    return table.concat(parts, ",")
end

-- GetLockedPerks has appeared in more than one server-side shape: a flat
-- numeric array, a name-keyed table of arrays, and entries using spellId/id
-- plus stack/stacks/count. Locked perks may also sit outside the normal roll
-- catalog, so never discard them merely because Catalog().rows lacks the id.
--
-- Live report (2026-07-31): a player with 6 total locked Echoes only saw 5
-- via this reader (the 6th had never been on their wishlist, ruling out any
-- wishlist-side cause -- this function/GetLockedPerks is the only remaining
-- suspect). Widened the recognized id-field names and recursion depth
-- defensively since the exact shape of the missing entry isn't confirmed
-- yet; A.DumpLockedPerksRaw below exists to get a definitive answer instead
-- of guessing again.
local function ReadLockedPerks(raw)
    local bySpell = {}
    local seenTables = {}

    local function Walk(value, depth)
        if type(value) ~= "table" or depth > 8 or seenTables[value] then return end
        seenTables[value] = true

        local id = tonumber(value.spellId or value.spellID or value.id or value.perkId
            or value.perkID or value.entryId or value.entryID or value.echoId or value.echoID
            or value.spell or value.perk)
        if id then
            local n = math.max(1, tonumber(value.stack or value.stacks or value.count
                or value.amount or value.qty) or 1)
            bySpell[id] = (bySpell[id] or 0) + n
            -- Do not `return` here -- if this table ALSO nests further locked
            -- entries as children (an id field alongside a child array, rather
            -- than instead of one), those must still be walked, not skipped.
        end

        for _, child in pairs(value) do
            if type(child) == "table" then Walk(child, depth + 1) end
        end
    end

    Walk(raw, 0)
    return bySpell
end

-- Diagnostic-only: the exact, unfiltered GetLockedPerks() return, serialized
-- via Codec.JSONEncode. Never used by decision logic -- exists solely so a
-- ReadLockedPerks miscount can be diagnosed from real data instead of a guess.
function A.DumpLockedPerksRaw()
    local svc = PS()
    local raw = svc and SafeCall(svc.GetLockedPerks)
    if raw == nil then return "GetLockedPerks() returned nil" end
    local Codec = Nexus and Nexus.Codec
    if Codec and type(Codec.JSONEncode) == "function" then
        local ok, text = pcall(Codec.JSONEncode, raw)
        if ok then return text end
    end
    return tostring(raw)
end

function A.LockedOwned()
    local svc = PS()
    local locked = svc and SafeCall(svc.GetLockedPerks)
    local bySpell = ReadLockedPerks(locked)
    local byFamily = {}
    for id, n in pairs(bySpell) do
        local fam = FamilyOf(id) or id
        byFamily[fam] = (byFamily[fam] or 0) + n
    end
    return { bySpell = bySpell, byFamily = byFamily,
        synced = type(locked) == "table" }
end

-- Confirmed live via /nexus sniff, 2026-08-01: the server exposes the real
-- locked-slot cap directly rather than it being a hardcoded assumption.
function A.MaxPermanentEchoes()
    local svc = PS()
    return tonumber(svc and SafeCall(svc.GetMaximumPermanentEchoes)) or 6
end

local function GrantedSignature(granted)
    if type(granted) ~= "table" then return nil end
    local counts = {}
    for _, entries in pairs(granted) do
        if type(entries) == "table" then
            for i = 1, #entries do
                local id = type(entries[i]) == "table"
                    and tonumber(entries[i].spellId) or nil
                if id then counts[id] = (counts[id] or 0) + 1 end
            end
        end
    end
    local ids = {}
    for id in pairs(counts) do ids[#ids + 1] = id end
    table.sort(ids)
    local out = {}
    for i = 1, #ids do
        out[#out + 1] = tostring(ids[i]) .. ":" .. tostring(counts[ids[i]])
    end
    return table.concat(out, ",")
end

function A.Owned()
    local cat = A.Catalog()
    local svc = PS()
    local bySpell = {}
    local granted = svc and SafeCall(svc.GetGrantedPerks)
    if type(granted) == "table" then
        for _, entries in pairs(granted) do        -- name-keyed; use values only
            if type(entries) == "table" then
                for i = 1, #entries do
                    local e = entries[i]
                    local id = type(e) == "table" and tonumber(e.spellId)
                    if id and cat and cat.rows[id] then
                        bySpell[id] = (bySpell[id] or 0) + 1  -- one entry per stack
                    end
                end
            end
        end
    end
    -- Locked Echoes are a separate, permanent player selection. They are
    -- captured for leaderboard/build metadata through LockedOwned(), but they
    -- are never part of the current run's rolled ownership, guarantee queue,
    -- wishlist progress, board decisions, or save candidate.
    -- auto-chained boards are stale-by-one: union our own confirmed picks
    for id, n in pairs(recordedPicks) do
        if (bySpell[id] or 0) < n then bySpell[id] = n end
    end
    local byFamily, distinct, total = {}, 0, 0
    for id, n in pairs(bySpell) do
        local fam = FamilyOf(id)
        byFamily[fam] = (byFamily[fam] or 0) + n
        distinct = distinct + 1
        total = total + (tonumber(n) or 0)
    end
    -- A response belongs to this run only when it changes the pre-request
    -- table/reference or content snapshot. A successful prior run must not
    -- satisfy a later generation, and elapsed time alone never makes an empty
    -- snapshot authoritative. Replacing the granted table with a fresh empty
    -- table is the supported confirmed-empty signal.
    local level = A.Level()
    local ghost = (level <= 1 and distinct >= GHOST_OWNED)
    local currentResponse = ownedRequestGeneration == ownedGeneration
        and type(granted) == "table"
        and (granted ~= ownedBaselineRef
            or GrantedSignature(granted) ~= ownedBaselineSig)
    if (currentResponse or (ownedGeneration == 0 and distinct > 0))
        and not ghost then
        ownedConfirmedGeneration = ownedGeneration
    end
    ownedSeen = ownedConfirmedGeneration == ownedGeneration
    local synced = ownedSeen and not ghost
    return { bySpell = bySpell, byFamily = byFamily,
             synced = synced, ghostSuspect = ghost,
             distinct = distinct, total = total,
             generation = ownedGeneration }
end

-- Run boundary (each visit to level 1): the previous run's recorded picks
-- are void, and we re-request granted so the fresh run's owned set loads.
-- Sync trust is handled per-level in A.Owned (no fragile snapshot compare).
function A.RunBoundaryReset()
    recordedPicks = {}
    pendingOwnPick = nil
    ownedGeneration = ownedGeneration + 1
    ownedConfirmedGeneration = -1
    ownedRequestGeneration = -1
    ownedBaselineRef, ownedBaselineSig = nil, nil
    ownedSeen = false
    ownedSyncedFlag = false
    ownedRequestAt = nil
    ownedRetries = 0
    boundaryAt = GetTime()
    A.RequestGranted()
end

function A.RequestGranted()
    local svc = PS()
    if svc and svc.RequestGrantedPerks then
        if ownedRequestGeneration ~= ownedGeneration then
            local before = SafeCall(svc.GetGrantedPerks)
            ownedBaselineRef = before
            ownedBaselineSig = GrantedSignature(before)
            ownedRequestGeneration = ownedGeneration
        end
        SafeCall(svc.RequestGrantedPerks)
        ownedRequestAt = GetTime()
        ownedRetries = ownedRetries + 1
    end
end

------------------------------------------------------------------------
-- Wishlist (sole target store; NEVER IsSpellInActiveEchoLoadout)
------------------------------------------------------------------------

-- Build the internal wishlist shape from a raw echo list. echoHasQuality is
-- true for the active-loadout store (carries rolled quality) and false for a
-- designed server build (id.stack.locked on the wire -> quality is nominal,
-- taken from the catalog).
local function EchoesToWishlist(echoes, name, source, echoHasQuality, slot)
    local cat = A.Catalog()
    if type(echoes) ~= "table" then return nil end
    local entries, byFamily = {}, {}
    for i = 1, #echoes do
        local e = echoes[i]
        local id = type(e) == "table" and tonumber(e.spellId)
        if id and cat and cat.rows[id] then
            local fam = FamilyOf(id)
            local stacks = tonumber(e.stacks) or 1
            if stacks < 1 then stacks = 1 end
            local q = (echoHasQuality and (tonumber(e.quality) or 0))
                or (cat.rows[id].quality or 0)
            -- e.locked is a REAL, order-independent server flag -- A.Slots()
            -- already parses it off GetServerBuildSlots() for every slot,
            -- designed or snapshot (see A.Slots()). Propagate it here instead
            -- of silently dropping it: it's what lets LoadPendingEchoes
            -- (ui/WishlistEditor.lua) recognize a wishlist's intended locked
            -- picks reliably, including ones that never went through Nexus's
            -- own Import button (e.g. the game's native ImportEchoLoadout UI).
            entries[#entries + 1] = { spellId = id, quality = q,
                                      stacks = stacks, family = fam,
                                      locked = e.locked and true or false }
            local t = byFamily[fam]
            if not t then
                byFamily[fam] = {
                    targetStacks  = stacks,
                    wishedQuality = q,
                    spellId       = id,
                    qualityTiers  = { { q = q, n = stacks, spellId = id } },
                }
            else
                t.targetStacks = t.targetStacks + stacks
                if q < t.wishedQuality then t.wishedQuality = q end
                local found = false
                for _, tier in ipairs(t.qualityTiers) do
                    if tier.q == q then
                        tier.n = tier.n + stacks
                        -- keep the spellId of this tier (first encountered wins;
                        -- all same-quality variants map to the same tier)
                        found = true
                        break
                    end
                end
                if not found then
                    t.qualityTiers[#t.qualityTiers + 1] = { q = q, n = stacks, spellId = id }
                end
            end
        end
    end
    -- Sort tiers ascending so callers walk low→high.
    for _, t in pairs(byFamily) do
        if t.qualityTiers and #t.qualityTiers > 1 then
            table.sort(t.qualityTiers, function(a, b) return a.q < b.q end)
        end
    end
    if #entries == 0 then return nil end
    return { name = tostring(name or ""), entries = entries,
             byFamily = byFamily, source = source, slot = slot }
end

-- Target resolution (corrected 2026-07-24 -- supersedes addendum B4's
-- "GetActiveEchoLoadout only"). Reality: the modern Echo Journal's "Echo
-- Wishlist" section is DESIGNED server build slots (verified==false / ids
-- above the snapshot range); activating one only sets serverActiveSlot and
-- NEVER feeds GetActiveEchoLoadout (perks_service SS-542 handler). So:
--   1. an explicit active loadout ("Play with..." -> SetActiveEchoLoadout)
--      wins when present (legacy, rare in the current UI); else
--   2. the designed "Echo Wishlist" build -- the active one if a designed
--      build is active, else the sole designed build; ambiguous only when
--      several exist with none active.
local function WishlistIdentity(echoes)
    if type(echoes) ~= "table" then return nil end
    local parts = {}
    for i = 1, #echoes do
        local e = echoes[i]
        local id = type(e) == "table" and tonumber(e.spellId)
        if id then
            parts[#parts + 1] = tostring(id) .. ":" .. tostring(math.max(1, tonumber(e.stacks) or 1))
        end
    end
    if #parts == 0 then return nil end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function CopyWishlistEchoes(echoes)
    local out = {}
    if type(echoes) ~= "table" then return out end
    for i = 1, #echoes do
        local e = echoes[i]
        local id = type(e) == "table" and tonumber(e.spellId)
        if id then
            out[#out + 1] = {
                spellId = id,
                quality = tonumber(e.quality) or 0,
                stacks = math.max(1, tonumber(e.stacks) or 1),
                locked = e.locked and true or false,
            }
        end
    end
    return out
end

-- Association fingerprints already contain the complete ordinary wishlist
-- (spellId:stacks pairs).  Decode that bounded snapshot when Project
-- Ebonhold briefly reports no designed slots so a transient empty response
-- cannot make an existing target disappear.
local function WishlistEchoesFromIdentity(key)
    local out = {}
    if type(key) ~= "string" or key == "" then return out end
    for part in string.gmatch(key, "[^,]+") do
        local idText, stacksText = string.match(part, "^(%d+):(%d+)$")
        local id, stacks = tonumber(idText), tonumber(stacksText)
        if id and id > 0 and stacks and stacks > 0 then
            out[#out + 1] = {
                spellId = id, quality = 0, stacks = math.max(1, stacks),
                locked = false,
            }
        end
    end
    return out
end

local function StoredWishlistRecord(candidate)
    local echoes = CopyWishlistEchoes(type(candidate) == "table" and candidate.echoes)
    local key = type(candidate) == "table" and candidate.key or nil
    if (not key or key == "") and #echoes > 0 then key = WishlistIdentity(echoes) end
    local record = {
        slot = type(candidate) == "table" and tonumber(candidate.slot) or nil,
        key = key,
        name = type(candidate) == "table" and tostring(candidate.name or "") or "",
    }
    if #echoes > 0 then record.echoes = echoes end
    return record
end

local function CandidateFromStoredRecord(saved)
    if type(saved) ~= "table" then return nil end
    local echoes = CopyWishlistEchoes(saved.echoes)
    if #echoes == 0 then echoes = WishlistEchoesFromIdentity(saved.key) end
    if #echoes == 0 then return nil end
    local key = tostring(saved.key or "")
    if key == "" then key = WishlistIdentity(echoes) end
    return {
        slot = tonumber(saved.slot), name = tostring(saved.name or ""),
        count = #echoes, echoes = echoes, key = key, active = false,
        stored = true,
    }
end

-- Public wrapper: a stable, content-based wishlist identity (spellId:stacks
-- pairs, sorted) usable outside this file. See LockDesignTargetsFor/
-- LockDesignTargets (core/Main.lua, ui/WishlistEditor.lua) -- this is what
-- locked-slot designs are keyed by, instead of the server's designed-slot
-- NUMBER, which gets reused for a new, unrelated wishlist the moment an old
-- one occupying it is deleted (confirmed live: a deleted wishlist's locked-
-- Echo design bled into a brand-new, differently-named wishlist that
-- happened to land on the same now-freed slot number).
function A.WishlistKey(echoes)
    return WishlistIdentity(echoes)
end

local function LiveWishlistCandidates()
    local slots = A.Slots()
    if not slots then return {} end
    local maxSlots = slots.maxSlots or 5
    local out = {}
    for slotId, row in pairs(slots.bySlot or {}) do
        local isDesigned = (row.verified == false)
            or (type(row.slot) == "number" and row.slot > maxSlots)
        if isDesigned and type(row.echoes) == "table" and #row.echoes > 0 then
            local echoes = {}
            local cat = A.Catalog()
            for i = 1, #row.echoes do
                local e = row.echoes[i]
                -- e.locked here is the same real, server-reported per-echo
                -- flag A.Slots() parses off GetServerBuildSlots() -- NOT
                -- inferred from position. Previously dropped on the floor,
                -- which meant a wishlist's intended locked picks were only
                -- ever recognized if this exact candidate had just been
                -- decoded from a pasted string (Import button); reading it
                -- back later (reopening, or importing via the game's own
                -- native UI) lost the signal entirely.
                --
                -- A.Slots() never carries a real .quality for a designed
                -- build (it's nominal -- see EchoesToWishlist's comment
                -- above), so this must look it up from the catalog itself.
                -- Previously defaulted straight to the literal 0 -- since 0
                -- is truthy in Lua, LoadPendingEchoes' own
                -- "tonumber(e.quality) or catalog fallback" never triggered,
                -- so every Echo in a reopened server wishlist displayed as
                -- quality 0/Common in the editor regardless of its real
                -- quality.
                local id = tonumber(e.spellId)
                local catQuality = id and cat and cat.rows and cat.rows[id]
                    and tonumber(cat.rows[id].quality)
                echoes[#echoes + 1] = {
                    spellId = id,
                    quality = catQuality or 0,
                    stacks = math.max(1, tonumber(e.stacks) or 1),
                    locked = e.locked and true or false,
                }
            end
            out[#out + 1] = {
                slot = tonumber(slotId) or tonumber(row.slot),
                name = tostring(row.name or ""), count = #echoes,
                echoes = echoes, key = WishlistIdentity(echoes), active = false,
            }
        end
    end
    table.sort(out, function(a, b) return (tonumber(a.slot) or 0) < (tonumber(b.slot) or 0) end)
    return out
end

function A.GetWishlistCandidates()
    local out = LiveWishlistCandidates()
    if #out > 0 then return out end

    -- Emergency/offline fallback: retain only identities the user explicitly
    -- associated before.  This does not resurrect Community Builds or Sync;
    -- it keeps the core wishlist usable while the server slot mirror is empty.
    local state = Store and Store.State and Store.State()
    if not state then return out end
    local seen = {}
    local function Add(saved)
        local candidate = CandidateFromStoredRecord(saved)
        if not candidate or not candidate.slot then return end
        local identity = candidate.key ~= "" and ("key:" .. candidate.key)
            or ("slot:" .. tostring(candidate.slot) .. ":" .. candidate.name)
        if seen[identity] then return end
        seen[identity] = true
        out[#out + 1] = candidate
    end
    Add(state.firstRunWishlist)
    for _, saved in pairs(state.loadoutWishlists or {}) do Add(saved) end
    table.sort(out, function(a, b) return (tonumber(a.slot) or 0) < (tonumber(b.slot) or 0) end)
    return out
end

local function ResolveAssociation(loadoutSlot)
    loadoutSlot = tonumber(loadoutSlot)
    if not loadoutSlot then return nil end
    local state = Store and Store.State and Store.State()
    local links = state and state.loadoutWishlists
    local saved = links and links[loadoutSlot]
    if saved == nil then return nil end

    -- 1.0.5 stored a bare designed-slot number. Migrate it only after
    -- validating the current contents, then persist a content identity so a
    -- recycled server slot can never resurrect an unrelated historical name.
    if type(saved) == "number" or type(saved) == "string" then
        local wanted = tonumber(saved)
        for _, c in ipairs(A.GetWishlistCandidates()) do
            if tonumber(c.slot) == wanted then
                links[loadoutSlot] = { slot = c.slot, key = c.key, name = c.name }
                return c
            end
        end
        return nil
    end
    if type(saved) ~= "table" then
        return nil
    end

    local candidates = A.GetWishlistCandidates()
    local wantedKey = saved.key
    if wantedKey and wantedKey ~= "" then
        for _, c in ipairs(candidates) do
            if c.key == wantedKey then
                -- Keep the current server slot/name synchronized after slot
                -- reordering while the Echo identity remains stable.
                saved.slot, saved.name = c.slot, c.name
                return c
            end
        end
        -- A server wishlist can be edited and then recreated/reindexed, which
        -- changes both its Echo fingerprint and numeric designed slot. Follow
        -- a unique exact-name match and immediately refresh the stored slot/key.
        -- Duplicate names are deliberately not guessed.
        local oldSlot, oldName = tonumber(saved.slot), tostring(saved.name or "")
        if oldName ~= "" then
            local nameMatch, nameMatches = nil, 0
            for _, c in ipairs(candidates) do
                if tostring(c.name or "") == oldName then
                    nameMatch, nameMatches = c, nameMatches + 1
                end
            end
            if nameMatches == 1 and nameMatch then
                saved.slot, saved.key, saved.name = nameMatch.slot, nameMatch.key, nameMatch.name
                return nameMatch
            end
        end
        -- Last safe fallback for older records: the same server slot and name.
        if oldSlot and oldName ~= "" then
            for _, c in ipairs(candidates) do
                if tonumber(c.slot) == oldSlot and tostring(c.name or "") == oldName then
                    saved.slot, saved.key = c.slot, c.key
                    return c
                end
            end
        end
    end
    -- No key means an incomplete/old record. Slot fallback is accepted once
    -- only and upgraded immediately.
    local wantedSlot = tonumber(saved.slot)
    if not wantedKey and wantedSlot then
        for _, c in ipairs(candidates) do
            if tonumber(c.slot) == wantedSlot then
                saved.key, saved.name = c.key, c.name
                return c
            end
        end
    end
    -- A missing candidate is not proof that the user deleted a wishlist.
    -- GetServerBuildSlots is eventually consistent and can be nil/empty
    -- during login and run transitions.  Keep the association so a later
    -- authoritative snapshot can resolve it instead of deleting user state
    -- from a read path.
    return nil
end

-- First-run target: players with no populated/active Saved Build still need a
-- wishlist target so Nexus can guide their very first 1-80 run. This is a
-- temporary account-local association and is replaced naturally once the
-- player has a real Saved Build selected.
local function ResolveFirstRunWishlist()
    local state = Store and Store.State and Store.State()
    local saved = state and state.firstRunWishlist
    if type(saved) ~= "table" then
        -- activeSlot=0 also occurs during run/login transitions.  If exactly
        -- one numbered loadout association exists, it is the only safe target
        -- to carry through that temporary no-active-slot window.
        local only, count = nil, 0
        for _, linked in pairs((state and state.loadoutWishlists) or {}) do
            if CandidateFromStoredRecord(linked) then
                only, count = linked, count + 1
            end
        end
        if count ~= 1 then return nil end
        saved = only
    end
    local candidates = A.GetWishlistCandidates()
    local wantedKey, wantedName = tostring(saved.key or ""), tostring(saved.name or "")
    if wantedKey ~= "" then
        for _, c in ipairs(candidates) do
            if c.key == wantedKey then
                saved.slot, saved.name = c.slot, c.name
                return c
            end
        end
    end
    if wantedName ~= "" then
        local match, count = nil, 0
        for _, c in ipairs(candidates) do
            if tostring(c.name or "") == wantedName then match, count = c, count + 1 end
        end
        if count == 1 and match then
            saved.slot, saved.key, saved.name = match.slot, match.key, match.name
            return match
        end
    end
    return nil
end

function A.GetFirstRunWishlist()
    return ResolveFirstRunWishlist()
end

function A.SetFirstRunWishlist(wishlistSlot, candidate)
    wishlistSlot = tonumber(wishlistSlot)
    local selected = type(candidate) == "table"
        and tonumber(candidate.slot) == wishlistSlot and candidate or nil
    if not selected then
        for _, c in ipairs(A.GetWishlistCandidates()) do
            if tonumber(c.slot) == wishlistSlot then selected = c; break end
        end
    end
    if not selected then return false, "invalid wishlist" end
    local state = Store and Store.State and Store.State()
    if not state then return false, "store unavailable" end
    state.firstRunWishlist = StoredWishlistRecord(selected)
    dataDirty = true
    return true
end

function A.SetFirstRunWishlistIdentity(name, echoes)
    local state = Store and Store.State and Store.State()
    if not state then return false end
    state.firstRunWishlist = StoredWishlistRecord({ name=name, echoes=echoes })
    dataDirty = true
    return true
end

function A.ClearFirstRunWishlist()
    local state = Store and Store.State and Store.State()
    if not state then return false end
    state.firstRunWishlist = nil
    dataDirty = true
    return true
end

local function IsPopulatedLoadout(loadoutSlot, slots)
    loadoutSlot = tonumber(loadoutSlot)
    slots = slots or A.Slots()
    local row = slots and slots.bySlot and loadoutSlot and slots.bySlot[loadoutSlot]
    return row and type(row.echoes) == "table" and #row.echoes > 0 and true or false
end

function A.GetLoadoutWishlist(loadoutSlot)
    -- An association on an empty numbered slot is stale metadata, not a usable
    -- build. Never expose it to the panel/UI as though the player can swap to it.
    if not IsPopulatedLoadout(loadoutSlot) then return nil end
    return ResolveAssociation(loadoutSlot)
end

function A.GetLoadoutWishlistSlot(loadoutSlot)
    local c = A.GetLoadoutWishlist(loadoutSlot)
    return c and tonumber(c.slot) or nil
end

function A.SetLoadoutWishlistIdentity(loadoutSlot, name, echoes)
    loadoutSlot = tonumber(loadoutSlot)
    local slots = A.Slots()
    if not slots or not loadoutSlot or loadoutSlot < 1
        or loadoutSlot > (tonumber(slots.maxSlots) or 5) then
        return false, "invalid loadout"
    end
    if not IsPopulatedLoadout(loadoutSlot, slots) then
        return false, "that loadout slot is empty or unavailable"
    end
    local state = Store and Store.State and Store.State()
    if not state then return false, "store unavailable" end
    state.loadoutWishlists = state.loadoutWishlists or {}
    state.loadoutWishlists[loadoutSlot] = StoredWishlistRecord({ name=name, echoes=echoes })
    dataDirty = true
    return true
end

-- Bootstrap for a genuinely brand-new character: no Saved Build exists yet
-- at all (every loadout slot empty), so there's no active/populated loadout
-- to associate the first wishlist with via SetLoadoutWishlistIdentity above
-- (which requires the target slot to already have echoes in it -- that
-- guard is right for its normal callers, just wrong for this one case).
--
-- Writes to BOTH places, deliberately:
--   - state.loadoutWishlists[1] -- a first Saved Build is always created in
--     slot 1, so this makes ResolveAssociation(1) find it the INSTANT the
--     player's activeSlot becomes 1, with no extra hand-off step. (The old
--     firstRunWishlist-only path never actually got promoted into a real
--     loadout association anywhere in this codebase -- "replaced naturally"
--     was the intent, but nothing implemented the replacement, so a player
--     who set one up would see "no wishlist association" again the moment
--     they got their first real Saved Build.)
--   - state.firstRunWishlist -- still needed for BEFORE that point: while
--     activeSlot is 0 (no Saved Build activated in-game yet at all, still
--     leveling 1-79), A.Wishlist() reads ONLY this, via
--     ResolveFirstRunWishlist -- ResolveAssociation is never even reached
--     yet since there's no active slot to resolve.
function A.SetFirstLoadoutWishlistIdentity(name, echoes)
    local state = Store and Store.State and Store.State()
    if not state then return false, "store unavailable" end
    state.loadoutWishlists = state.loadoutWishlists or {}
    state.loadoutWishlists[1] = StoredWishlistRecord({ name=name, echoes=echoes })
    state.firstRunWishlist = StoredWishlistRecord({ name=name, echoes=echoes })
    dataDirty = true
    return true
end

function A.SetLoadoutWishlist(loadoutSlot, wishlistSlot, candidate)
    if A.DIAGNOSTIC_PASSIVE then return false, "internal.6 passive diagnostic: write blocked" end
    loadoutSlot, wishlistSlot = tonumber(loadoutSlot), tonumber(wishlistSlot)
    local slots = A.Slots()
    if not slots or not loadoutSlot or loadoutSlot < 1
        or loadoutSlot > (tonumber(slots.maxSlots) or 5) then
        return false, "invalid loadout"
    end
    -- The server's populated echo list is the reliable proof that this is a
    -- real saved loadout. Optional verification fields are missing on some
    -- Ebonhold responses and previously made valid rows impossible to assign.
    if not IsPopulatedLoadout(loadoutSlot, slots) then
        return false, "that loadout slot is empty or unavailable"
    end
    local selected = type(candidate) == "table"
        and tonumber(candidate.slot) == wishlistSlot and candidate or nil
    if not selected then
        for _, c in ipairs(A.GetWishlistCandidates()) do
            if tonumber(c.slot) == wishlistSlot then selected = c; break end
        end
    end
    if not selected then return false, "invalid wishlist" end
    local state = Store and Store.State and Store.State()
    if not state then return false, "store unavailable" end
    state.loadoutWishlists = state.loadoutWishlists or {}
    state.loadoutWishlists[loadoutSlot] = StoredWishlistRecord(selected)
    dataDirty = true
    return true
end


function A.UpdateWishlistAssociationAfterSave(loadoutSlot, wishlistSlot, name, echoes)
    loadoutSlot, wishlistSlot = tonumber(loadoutSlot), tonumber(wishlistSlot)
    if not loadoutSlot or not wishlistSlot then return false end
    local state = Store and Store.State and Store.State()
    if not state then return false end
    state.loadoutWishlists = state.loadoutWishlists or {}
    state.loadoutWishlists[loadoutSlot] = StoredWishlistRecord({
        slot=wishlistSlot, name=name, echoes=echoes,
    })
    dataDirty = true
    return true
end

function A.ClearLoadoutWishlist(loadoutSlot)
    if A.DIAGNOSTIC_PASSIVE then return false, "internal.6 passive diagnostic: write blocked" end
    loadoutSlot = tonumber(loadoutSlot)
    local state = Store and Store.State and Store.State()
    if not state or not loadoutSlot then return false end
    state.loadoutWishlists = state.loadoutWishlists or {}
    state.loadoutWishlists[loadoutSlot] = nil
    dataDirty = true
    return true
end

function A.Wishlist()
    A._wishlistNote = nil
    local slots = A.Slots()
    local activeSlot = slots and tonumber(slots.activeSlot) or 0
    local maxSlots = slots and (tonumber(slots.maxSlots) or 5) or 5
    -- Project Ebonhold can make a designed wishlist (slot > maxSlots) the
    -- active server selection. That slot is already an exact, authoritative
    -- target; resolving it must not go through the activeSlot=0 first-run
    -- fallback or depend on a numbered Saved Build association.
    if activeSlot > maxSlots then
        for _, candidate in ipairs(A.GetWishlistCandidates()) do
            if tonumber(candidate.slot) == activeSlot then
                A._wishlistNote = "Active designed wishlist target"
                return EchoesToWishlist(candidate.echoes, candidate.name,
                    "designed", false, candidate.slot)
            end
        end
    end
    if activeSlot < 1 or activeSlot > maxSlots then
        local starter = ResolveFirstRunWishlist()
        if starter then
            A._wishlistNote = "First-run wishlist target"
            return EchoesToWishlist(starter.echoes, starter.name,
                "first-run-wishlist", false, starter.slot)
        end
        A._wishlistNote = "Choose or create a wishlist to begin your first run."
        return nil
    end
    local linked = ResolveAssociation(activeSlot)
    if linked then
        return EchoesToWishlist(linked.echoes, linked.name,
            "loadout-association", false, linked.slot)
    end
    A._wishlistNote = "Loadout " .. tostring(activeSlot)
        .. " has no wishlist association. Set it in the Echo Journal."
    return nil
end

function A.WishlistNote() return A._wishlistNote end

function A.GetLoadoutCandidates()
    local slots = A.Slots()
    if not slots then return {} end
    local out = {}
    local maxSlots = tonumber(slots.maxSlots) or 5
    for slot = 1, maxSlots do
        local row = slots.bySlot and slots.bySlot[slot]
        -- Only populated server loadouts are real switch targets. A stale
        -- association on an empty slot must never make Nexus present it as one.
        if IsPopulatedLoadout(slot, slots) then
            local linked = ResolveAssociation(slot)
            out[#out + 1] = {
                slot = slot,
                name = row and tostring(row.name or "") or "",
                count = row and #(row.echoes or {}) or 0,
                available = true,
                active = tonumber(slots.activeSlot) == slot,
                wishlist = linked, wishlistSlot = linked and linked.slot or nil,
            }
        end
    end
    return out
end

------------------------------------------------------------------------
-- Build slots (nil-until-540; sparse; verified-field + parse heuristics)
------------------------------------------------------------------------

function A.Slots()
    local svc = PS()
    local raw = svc and SafeCall(svc.GetServerBuildSlots)
    if type(raw) ~= "table" then return nil end
    local maxSlots = tonumber(svc and SafeCall(svc.GetServerMaxSlots)) or 5
    local bySlot = {}
    local anyFalse, designedTrue = false, false
    for slot, s in pairs(raw) do
        if type(s) == "table" then
            local echoes = {}
            if type(s.echoes) == "table" then
                for i = 1, #s.echoes do
                    local e = s.echoes[i]
                    local id = type(e) == "table" and tonumber(e.spellId)
                    if id then
                        echoes[#echoes + 1] = {
                            spellId = id, stacks = tonumber(e.stacks) or 1,
                            locked = e.locked and true or false, family = FamilyOf(id),
                        }
                    end
                end
            end
            if s.verified == false then anyFalse = true end
            if s.verified and type(slot) == "number" and slot > maxSlots then
                designedTrue = true  -- designed slots are never really verified
            end
            bySlot[slot] = {
                slot = slot, name = tostring(s.name or ""),
                verified = s.verified and true or false,
                echoes = echoes,
                suspectParse = (s.verified and #echoes == 0) and true or false,
            }
        end
    end
    -- Field-presence heuristic (addendum C1): a payload lacking the [01]
    -- field parses EVERYTHING as verified=true -- including designed slots
    -- above maxSlots, which are never verified on a real payload.
    local fieldPresent = anyFalse or not designedTrue
    for _, s in pairs(bySlot) do s.verifiedFieldPresent = fieldPresent end
    local active = tonumber(svc and SafeCall(svc.GetServerActiveSlot)) or 0
    return { bySlot = bySlot, activeSlot = active, maxSlots = maxSlots }
end

-- NOTE: this is a READ (asks the server to re-send slot data), so it has
-- its own throttle and deliberately does NOT touch lastBuildOpAt.
-- Sharing that guard was a real bug (2026-07-24): the background loop
-- calls this every ~5s, and the write guard is 3s, so a manual Save /
-- Activate / UploadWishlist was refused with "spacing" roughly 60% of
-- the time. Reads must never block writes.
local lastSlotRequestAt = -10
function A.RequestSlots()
    local svc = PS()
    if svc and svc.RequestServerBuildSlots and (GetTime() - lastSlotRequestAt) >= 3 then
        SafeCall(svc.RequestServerBuildSlots)
        lastSlotRequestAt = GetTime()
        return true
    end
    return false
end

------------------------------------------------------------------------
-- Tome levers (per-requiredSpell; latch-less client call -> own pending set)
------------------------------------------------------------------------

function A.DiscoverySynced()
    local p = PerksTbl()
    return (p and p.discoveredEchoes) ~= nil
end

-- A tome can only be disabled if it is KNOWN -- the client's own journal
-- gates its disable toggle on tomeKnown = owned OR discovered
-- [echo_journal.lua:399,508]. Disabling an unknown tome is a no-op the
-- server never confirms (the echo is absent from the discovery mirror),
-- which is what produced the "no confirmation" spam. GetDiscoveredEchoes
-- (ever-obtained) is the cross-run "known" signal.
function A.LeverHasKnownMember(leverId)
    local cat = A.Catalog()
    local svc = PS()
    if not cat or not svc then return false end
    local lv = cat.levers[leverId]
    if not lv then return false end
    local discovered = SafeCall(svc.GetDiscoveredEchoes) or {}
    for i = 1, #lv.members do
        if discovered[lv.members[i]] ~= nil then return true end
    end
    return false
end

-- Returns the unique tome gates required by a wishlist that the character
-- has never discovered. These Echoes cannot enter the roll pool yet.
function A.UnknownTomesForEchoes(echoes)
    local cat = A.Catalog()
    local svc = PS()
    if not cat or not svc or type(echoes) ~= "table" then return {} end
    local discovered = SafeCall(svc.GetDiscoveredEchoes)
    if type(discovered) ~= "table" then return {} end
    local seen, out = {}, {}
    for _, entry in ipairs(echoes) do
        local spellId = tonumber(entry and (entry.spellId or entry.id))
        local row = spellId and cat.rows[spellId]
        local lever = row and tonumber(row.requiredSpell) or 0
        if lever > 0 and not seen[lever] then
            local lv = cat.levers[lever]
            local known = false
            if lv then
                for i = 1, #lv.members do
                    if discovered[lv.members[i]] ~= nil then known = true; break end
                end
            else
                known = discovered[spellId] ~= nil
            end
            if not known then
                seen[lever] = true
                out[#out + 1] = (lv and lv.tomeName) or ("Tome of " .. tostring(row.name or spellId))
            end
        end
    end
    table.sort(out)
    return out
end

-- values: "confirmed" (server mirror says disabled) or "pending" (our
-- disable request not yet 530-confirmed). Both are truthy for pool math;
-- only "confirmed" may drive the flag self-check (a pending lever proves
-- nothing about the server).
function A.DisabledLevers()
    local cat = A.Catalog()
    local svc = PS()
    local out = {}
    if not cat or not svc then return out end
    local pending = Store and Store.State().tomeTogglePending or {}
    for lever, lv in pairs(cat.levers) do
        local dis = false
        for i = 1, #lv.members do
            if SafeCall(svc.IsTomeEchoDisabled, lv.members[i]) then dis = true; break end
        end
        local p = pending[lever]
        local pendingDisable = p ~= nil
            and not (type(p) == "table" and p.want == false)
        if dis then
            out[lever] = "confirmed"
        elseif pendingDisable then
            out[lever] = "pending"
        end
    end
    return out
end

function A.ToggleLever(leverId, wantDisabled)
    if A.DIAGNOSTIC_PASSIVE then return false, "internal.6 passive diagnostic: write blocked" end
    if A.TomeMutationPaused and A.TomeMutationPaused() then
        return false, "Tome of Echo transaction settling"
    end
    local cat = A.Catalog()
    local svc = PS()
    if not cat or not svc or not svc.ToggleTomeEcho then return false, "no api" end
    local lv = cat.levers[leverId]
    if not lv then return false, "unknown lever" end
    if not lv.conformant then return false, "non-conformant lever" end
    if (UnitLevel("player") or 0) ~= 1 then return false, "not level 1" end
    local st = Store and Store.State()
    local pending = st and st.tomeTogglePending or {}
    if pending[leverId] then return false, "pending" end
    -- effective state: any member disabled OR pending counts as disabled
    local cur = false
    for i = 1, #lv.members do
        if SafeCall(svc.IsTomeEchoDisabled, lv.members[i]) then cur = true; break end
    end
    if cur == (wantDisabled and true or false) then return false, "already" end
    local ok = SafeCall(svc.ToggleTomeEcho, lv.members[1])
    if ok then
        pending[leverId] = { t = GetTime(), want = wantDisabled and true or false }
        if st then st.tomeTogglePending = pending end
        return true
    end
    return false, "refused"
end

-- called from the poll: clear pending entries the server has confirmed
-- (mirror matches the requested direction) or that expired (30s) with no
-- reply. Expiry only counts once the session's mirror is authoritative
-- (first SS-530 arrived) and clamps timestamps from a previous boot
-- (GetTime() restarts at reboot -- a persisted future timestamp would
-- otherwise never expire).
local function ReconcileTomePending()
    local st = Store and Store.State()
    if not st or not st.tomeTogglePending then return end
    local cat = A.Catalog()
    local svc = PS()
    if not cat or not svc then return end
    local now = GetTime()
    local mirrorLive = A.DiscoverySynced()
    for lever, p in pairs(st.tomeTogglePending) do
        local sentAt = (type(p) == "table" and tonumber(p.t)) or tonumber(p) or 0
        local want = not (type(p) == "table" and p.want == false)
        if sentAt > now then      -- cross-boot entry: restart the window
            if type(p) == "table" then p.t = now else
                st.tomeTogglePending[lever] = { t = now, want = want }
            end
            sentAt = now
        end
        local lv = cat.levers[lever]
        local cur = false
        if lv then
            for i = 1, #lv.members do
                if SafeCall(svc.IsTomeEchoDisabled, lv.members[i]) then cur = true; break end
            end
        end
        local confirmed = lv and (cur == want)
        local expired = mirrorLive and (now - sentAt) > 30
        if confirmed or not lv or expired then
            -- clear silently: a genuine failure just leaves the echo in the
            -- pool (mild), and we no longer disable unknown tomes (the cause
            -- of the old per-lever "no confirmation" chat spam)
            st.tomeTogglePending[lever] = nil
        end
    end
end

------------------------------------------------------------------------
-- In-flight gate v2 (latch polling is the primary release)
------------------------------------------------------------------------

local LATCH_FIELDS = {
    select = "pendingSelectSpellId", banish = "pendingBanishIndex",
    freeze = "pendingFreezeIndex", reroll = "pendingReroll",
}

-- true when any LIVE (not watchdog-dead) client latch is set
local function AnyLatch()
    local p = PerksTbl()
    if not p then return false end
    for kind, field in pairs(LATCH_FIELDS) do
        if p[field] ~= nil and not deadLatch[kind] then return true end
    end
    return false
end

-- stuck-latch watchdog: the client's latches have NO timeout and some
-- refusals arrive with no reply at all (a user-clicked freeze the server
-- ignores would otherwise halt automation forever). A latch stuck >10s is
-- declared dead for the session -- per-ACTION, mirroring the client's own
-- failure mode -- and excluded from the whole-loop gate. Never writes the
-- client's fields; recovers if the latch does clear later.
local function WatchLatches()
    local p = PerksTbl()
    if not p then return end
    local now = GetTime()
    for kind, field in pairs(LATCH_FIELDS) do
        if p[field] ~= nil then
            latchSince[kind] = latchSince[kind] or now
            if not deadLatch[kind] and (now - latchSince[kind]) > 10 then
                deadLatch[kind] = true
                if inFlightKind == kind then inFlightKind, inFlightSig = nil, nil end
                if callbacks and callbacks.OnStatus then
                    callbacks.OnStatus(kind .. " got no server reply for 10s -- "
                        .. kind .. " disabled for this session (/reload recovers)")
                end
            end
        else
            if latchSince[kind] ~= nil then boardDirty = true end
            latchSince[kind] = nil
            if deadLatch[kind] then deadLatch[kind] = nil end  -- late reply: recover
        end
    end
end

function A.InFlight()
    return (inFlightKind ~= nil) or AnyLatch()
end

-- poll tick: resolve our own in-flight marker from latch + board transitions
local function ResolveInFlight()
    if not inFlightKind then return end
    local p = PerksTbl()
    if inFlightKind == "select" then
        if not (p and p.pendingSelectSpellId) then
            local ch = p and p.currentChoice
            local resolvedSig = nil
            if type(ch) == "table" then
                local parts = {}
                for i = 1, #ch do parts[#parts + 1] = tostring(ch[i].spellId) end
                resolvedSig = table.concat(parts, ",")
            end
            if ch == nil or resolvedSig ~= inFlightSig then
                -- success: board consumed (auto-chain requests the next one)
                if pendingOwnPick then
                    recordedPicks[pendingOwnPick] = (recordedPicks[pendingOwnPick] or 0) + 1
                end
            end
            -- failure (SS-1000 "0"): latch cleared, same board -> just release
            inFlightKind, inFlightSig, pendingOwnPick = nil, nil, nil
            boardDirty = true
        end
    elseif inFlightKind == "banish" then
        if not (p and p.pendingBanishIndex) then
            inFlightKind, inFlightSig = nil, nil
            boardDirty = true          -- SS-103 mutated the board in place
        end
    elseif inFlightKind == "reroll" then
        if not (p and p.pendingReroll) then
            inFlightKind, inFlightSig = nil, nil
            boardDirty = true
        end
    else
        inFlightKind, inFlightSig = nil, nil
        boardDirty = true
    end
end

------------------------------------------------------------------------
-- Availability predicates (the stall fix) + actions
------------------------------------------------------------------------

local function CardBlocked(card)
    return card.isGuaranteed or card.isFrozen or card.isCarried or card.justFrozen
end

function A.Take(spellId)
    if A.DIAGNOSTIC_PASSIVE then return false, "internal.6 passive diagnostic: write blocked" end
    if A.InFlight() then return false, "in flight" end
    local board = A.Board()
    if not board then return false, "no board" end
    local found = false
    for i = 1, #board.cards do
        if board.cards[i].spellId == spellId then found = true; break end
    end
    if not found then return false, "not on board" end
    local svc = PS()
    selfCalling = true
    local ok = svc and SafeCall(svc.SelectPerk, spellId)
    selfCalling = false
    if ok then
        -- ids-only signature: ResolveInFlight compares like-for-like (a
        -- flag-suffixed sig would misread every FAILED select as success)
        inFlightKind, inFlightSig, pendingOwnPick = "select", board.idSignature, spellId
        return true
    end
    return false, "refused"
end

function A.Banish(index0)
    if A.DIAGNOSTIC_PASSIVE then return false, "internal.6 passive diagnostic: write blocked" end
    if A.InFlight() then return false, "in flight" end
    local board = A.Board()
    if not board then return false, "no board" end
    local card = board.cards[index0 + 1]
    if not card then return false, "no card" end
    if CardBlocked(card) then return false, "blocked card" end
    local ch = A.Charges()
    if ch.banish <= 0 then return false, "no charges" end
    if ledger.banishThisPush then return false, "one per push" end
    local pe = PE()
    if not (pe and pe.Constants and pe.Constants.ENABLE_BANISH_SYSTEM) then
        return false, "system off"
    end
    local svc = PS()
    selfCalling = true
    local ok = svc and SafeCall(svc.BanishPerk, index0)
    selfCalling = false
    if ok then
        ledger.banish = math.max(0, (ledger.banish or 1) - 1)
        ledger.banishThisPush = true
        inFlightKind, inFlightSig = "banish", board.signature
        return true
    end
    return false, "refused"
end

function A.Reroll()
    if A.DIAGNOSTIC_PASSIVE then return false, "internal.6 passive diagnostic: write blocked" end
    if A.InFlight() then return false, "in flight" end
    local ch = A.Charges()
    if ch.reroll <= 0 then return false, "no charges" end
    local svc = PS()
    selfCalling = true
    local ok = svc and SafeCall(svc.RequestReroll)
    selfCalling = false
    if ok then
        ledger.reroll = math.max(0, (ledger.reroll or 1) - 1)
        local b = A.Board()
        inFlightKind, inFlightSig = "reroll", b and b.signature or ""
        return true
    end
    return false, "refused"
end

-- FreezePerk emits no success signal of its own [mirrors BanishPerk/
-- RequestReroll]; release comes from the pendingFreezeIndex latch via
-- WatchLatches/ResolveInFlight like every other mutator. Never at level
-- 80 (no next board for a freeze to carry into). Never a blocked card.
function A.Freeze(index0)
    if A.DIAGNOSTIC_PASSIVE then return false, "internal.6 passive diagnostic: write blocked" end
    if A.InFlight() then return false, "in flight" end
    if deadLatch.freeze then return false, "freeze dead this session" end
    if (UnitLevel("player") or 0) >= 80 then
        local horizon = A.Horizon()
        if type(horizon) ~= "number" or horizon <= 1 then
            return false, "no trustworthy next board"
        end
    end
    local board = A.Board()
    if not board then return false, "no board" end
    local card = board.cards[index0 + 1]
    if not card then return false, "no card" end
    if CardBlocked(card) then return false, "blocked card" end
    local ch = A.Charges()
    if ch.freeze <= 0 or ch.trustworthy == false then return false, "no charges" end
    local svc = PS()
    selfCalling = true
    local ok = svc and SafeCall(svc.FreezePerk, index0)
    selfCalling = false
    if ok then
        ledger.freeze = math.max(0, (ledger.freeze or 1) - 1)
        selfFreezeSig, selfFreezeIndex = board.signature, index0 + 1
        inFlightKind, inFlightSig = "freeze", board.signature
        return true
    end
    return false, "refused"
end

------------------------------------------------------------------------
-- Build-slot actions (explicit level gates; 3s spacing; observation-verified)
------------------------------------------------------------------------

function A.Activate(slot)
    if A.DIAGNOSTIC_PASSIVE then return false, "internal.6 passive diagnostic: write blocked" end
    local level = UnitLevel("player") or 0
    if level ~= 1 and level ~= 80 then return false, "not level 1/80" end
    if (GetTime() - lastBuildOpAt) < 3 then return false, "spacing" end
    local svc = PS()
    local ok = svc and SafeCall(svc.ActivateServerBuildSlot, slot)
    if ok then
        lastBuildOpAt = GetTime()
        A._pendingWishlistSlot = tonumber(slot) or slot
        A._pendingWishlistAt = GetTime()
        A.RequestSlots()
        return true
    end
    return false, "refused"
end

function A.Save(slot, name)
    if A.DIAGNOSTIC_PASSIVE then return false, "internal.6 passive diagnostic: write blocked" end
    if (UnitLevel("player") or 0) ~= 80 then return false, "not level 80" end
    if (GetTime() - lastBuildOpAt) < 3 then return false, "spacing" end
    local svc = PS()
    local ok = svc and SafeCall(svc.SaveServerBuildSlot, slot, name)
    if ok then lastBuildOpAt = GetTime(); return true end
    return false, "refused"
end

-- Writes an arbitrary echo list to a DESIGNED build slot -- i.e. the
-- wishlist itself, not a rolled loadout snapshot. Confirmed via /wr
-- sniff (2026-07-24): two independent real captures (a community-loadout
-- import and a raw ImportEchoLoadout string import) both called
-- UploadServerBuildSlot(0, name, echoes) with slot 0, regardless of
-- source -- strong evidence slot 0 is a fixed sentinel for "the designed
-- wishlist slot", distinct from the 1..maxSlots loadout snapshot range.
-- echoes: array of { spellId=n, quality=n, stacks=n } -- exactly the
-- shape both captures showed. No level gate (unlike Save, which is
-- level-80-only for rolled loadouts) -- designing a wishlist isn't tied
-- to being at cap. Same spacing guard as Save/Activate.
function A.UploadWishlist(slot, name, echoes)
    if A.DIAGNOSTIC_PASSIVE then return false, "internal.6 passive diagnostic: write blocked" end
    if type(echoes) ~= "table" or #echoes == 0 then return false, "no echoes" end
    if (GetTime() - lastBuildOpAt) < 3 then return false, "spacing" end
    local svc = PS()
    local clean, byFamily = {}, {}
    local catalog = A.Catalog and A.Catalog()
    for i = 1, #echoes do
        local e = echoes[i]
        local spellId = tonumber(e and e.spellId)
        if spellId then
            local row = catalog and catalog.rows and catalog.rows[spellId]
            -- Wishlist editing dedupes only true quality variants. Neither
            -- groupId nor displayed name is unique by itself in the live catalog;
            -- their combination preserves same-name Echoes in different groups.
            local editorName = tostring(row and row.name or ""):lower()
            editorName = editorName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            editorName = editorName:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
            local family
            if editorName ~= "" then
                local groupId = tonumber(row and row.groupId) or 0
                family = groupId > 0
                    and ("ng:" .. editorName .. ":" .. tostring(groupId))
                    or ("n:" .. editorName)
            else
                family = "s:" .. tostring(spellId)
            end
            local requestedStacks = math.max(1, tonumber(e.stacks) or 1)
            -- Unknown-but-well-formed Echoes come from newer server data. Do
            -- not silently collapse their requested stack count to one merely
            -- because this client's catalog has not learned the row yet.
            local maxStack = row and math.max(1, tonumber(row.maxStack) or 1)
                or requestedStacks
            -- Catalog first -- a known spellId's quality is fixed, not a
            -- variable roll result, so it's always authoritative once the
            -- catalog has the row. e.quality is only a fallback for a
            -- spellId the catalog doesn't recognize yet. Same "truthy 0"
            -- fix as ui/WishlistEditor.lua's LoadPendingEchoes -- this
            -- dedup's own quality tie-break (candidate.quality > prior.quality
            -- below) needs the real value to pick the right survivor.
            local candidate = { spellId = spellId,
                quality = tonumber(row and row.quality) or tonumber(e.quality) or 0,
                stacks = math.min(maxStack, requestedStacks) }
            local prior = byFamily[family]
            if not prior or candidate.quality > prior.quality then
                byFamily[family] = candidate
            elseif prior.spellId == candidate.spellId then
                prior.stacks = math.min(maxStack, prior.stacks + candidate.stacks)
            else
                prior.stacks = math.max(prior.stacks, candidate.stacks)
            end
        end
    end
    for _, e in pairs(byFamily) do clean[#clean + 1] = e end
    table.sort(clean, function(a, b) return a.spellId < b.spellId end)
    if #clean == 0 then return false, "no valid echoes" end
    local ok = svc and SafeCall(svc.UploadServerBuildSlot,
        tonumber(slot) or 0, tostring(name or "Nexus"), clean)
    if ok then
        lastBuildOpAt = GetTime()
        -- the slot cache is now stale; re-request like Save/seed does
        A.RequestSlots()
        return true
    end
    return false, "refused"
end

------------------------------------------------------------------------
-- Locked Echo write path (LockPerk/UnlockPerk) -- confirmed live via
-- /nexus sniff, 2026-08-01: manually locking an Echo in the character
-- progression UI calls LockPerk(spellId) then RequestGrantedPerks();
-- unlocking calls UnlockPerk(spellId) the same way. Independent
-- throttle from lastBuildOpAt -- locking is a separate, more
-- consequential action and gets its own conservative spacing rather
-- than competing with wishlist saves for the same window.
------------------------------------------------------------------------

local lastLockOpAt = -10

function A.LockPerk(spellId)
    if A.DIAGNOSTIC_PASSIVE then return false, "internal.6 passive diagnostic: write blocked" end
    spellId = tonumber(spellId)
    if not spellId then return false, "invalid spellId" end
    if (GetTime() - lastLockOpAt) < 3 then return false, "spacing" end
    local svc = PS()
    local ok = svc and SafeCall(svc.LockPerk, spellId)
    if ok then
        lastLockOpAt = GetTime()
        if svc and svc.RequestGrantedPerks then SafeCall(svc.RequestGrantedPerks) end
        return true
    end
    return false, "refused"
end

function A.UnlockPerk(spellId)
    if A.DIAGNOSTIC_PASSIVE then return false, "internal.6 passive diagnostic: write blocked" end
    spellId = tonumber(spellId)
    if not spellId then return false, "invalid spellId" end
    if (GetTime() - lastLockOpAt) < 3 then return false, "spacing" end
    local svc = PS()
    local ok = svc and SafeCall(svc.UnlockPerk, spellId)
    if ok then
        lastLockOpAt = GetTime()
        if svc and svc.RequestGrantedPerks then SafeCall(svc.RequestGrantedPerks) end
        return true
    end
    return false, "refused"
end

------------------------------------------------------------------------
-- Solo picker + rival detection
------------------------------------------------------------------------

function A.SetSoloPicker()
    if A.DIAGNOSTIC_PASSIVE then return false, "internal.6 passive diagnostic: write blocked" end
    local opt = OptSvc()
    if not (opt and opt.SetSetting and opt.GetSetting) then return false end
    local cur = SafeCall(function() return opt:GetSetting("autoAcceptLoadoutEchoes") end)
    if cur then
        local st = Store and Store.State()
        if st and st.priorAutoAccept == nil then st.priorAutoAccept = true end
        pcall(function() opt:SetSetting("autoAcceptLoadoutEchoes", false) end)
        return true, "disabled"
    end
    return true, "already off"
end

function A.AutoAcceptOn()
    local opt = OptSvc()
    if not (opt and opt.GetSetting) then return false end
    return SafeCall(function() return opt:GetSetting("autoAcceptLoadoutEchoes") end)
        and true or false
end

function A.RestoreAutoAccept()
    if A.DIAGNOSTIC_PASSIVE then return false, "internal.6 passive diagnostic: write blocked" end
    local st = Store and Store.State()
    local opt = OptSvc()
    if st and st.priorAutoAccept and opt and opt.SetSetting then
        pcall(function() opt:SetSetting("autoAcceptLoadoutEchoes", true) end)
        st.priorAutoAccept = nil
        return true
    end
    return false
end

function A.RivalDetected()
    -- EchoOptimizer replaces PerkUI.Show outright and would blind us
    return _G.EchoOptimizer ~= nil
end

------------------------------------------------------------------------
-- Misc reads
------------------------------------------------------------------------

function A.Level() return UnitLevel("player") or 0 end

function A.Horizon()
    -- GetPendingRollsCount has PERSISTENT SIDE EFFECTS at level<=1 /
    -- loading screens (pick-counter reset, char-key latch): call guarded.
    if not pewDone then return nil end
    if (UnitLevel("player") or 0) < 2 then return nil end
    local svc = PS()
    local n = svc and SafeCall(svc.GetPendingRollsCount)
    if type(n) ~= "number" then return nil end
    return n
end

function A.ExternalActionSeen()
    local v = externalActionSeen
    externalActionSeen = false
    return v
end

function A.OwnedSyncInfo()
    return { requestedAt = ownedRequestAt, retries = ownedRetries }
end

function A.UnlockedSlots()
    local svc = PS()
    return tonumber(svc and SafeCall(svc.GetServerUnlockedSlots)) or 0
end

------------------------------------------------------------------------
-- Hooks + events + poll
------------------------------------------------------------------------

-- Rare Tome of Echo items use the stock bind-on-use popup. Pause only
-- Nexus's automatic ToggleTomeEcho traffic before the first click and for a
-- settling window after the item disappears. The popup remains stock-owned;
-- inspection below is read-only and secondary to carried-bag detection.
local BIND_SETTLE_SECONDS = 20

local function IsBindConfirmation(which, popupText)
    local key = tostring(which or ""):upper()
    local lower = tostring(popupText or ""):lower()
    if key:find("BIND", 1, true) then return true end
    return lower:find("using this item will bind it to you", 1, true) ~= nil
end

local function HoldTomeMutations()
    tomeMutationPausedUntil = math.max(tomeMutationPausedUntil,
        (GetTime and GetTime() or 0) + BIND_SETTLE_SECONDS)
end

local function EchoTomeInBags()
    if type(GetContainerNumSlots) ~= "function"
        or type(GetContainerItemLink) ~= "function" then
        return false
    end
    for bag = 0, 4 do
        local slots = tonumber(SafeCall(GetContainerNumSlots, bag)) or 0
        for slot = 1, slots do
            local link = SafeCall(GetContainerItemLink, bag, slot)
            if type(link) == "string" then
                local name = SafeCall(GetItemInfo, link)
                    or link:match("%[(.-)%]")
                if tostring(name or ""):lower():find(
                    "tome of echo", 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

local function VisibleBindConfirmation()
    for i = 1, 4 do
        local frame = _G["StaticPopup" .. i]
        if frame and frame.IsShown and frame:IsShown() then
            local popupText = frame.text and frame.text.GetText
                and frame.text:GetText() or nil
            if IsBindConfirmation(frame.which, popupText) then return true end
        end
    end
    return false
end

function A.TomeMutationPaused()
    if EchoTomeInBags() or VisibleBindConfirmation() then
        HoldTomeMutations()
    end
    return (GetTime and GetTime() or 0) < tomeMutationPausedUntil
end

local function InstallHooks()
    if hooksInstalled then return end
    local pe = PE()
    if not pe then return end
    -- every hook body minimal + pcall'd: these run INSIDE the client's
    -- pcall'd handler chain; an error here breaks the client's own handler
    if pe.PerkUI and type(pe.PerkUI.Show) == "function" then
        hooksecurefunc(pe.PerkUI, "Show", function()
            local ok = pcall(function() boardDirty = true end)
            if not ok then return end
        end)
    end
    if pe.PerkUI and type(pe.PerkUI.UpdateSinglePerk) == "function" then
        hooksecurefunc(pe.PerkUI, "UpdateSinglePerk", function()
            pcall(function() boardDirty = true end)
        end)
    end
    if pe.EchoJournal and type(pe.EchoJournal.OnDataChanged) == "function" then
        hooksecurefunc(pe.EchoJournal, "OnDataChanged", function()
            pcall(function()
                slotsDirty = true; dataDirty = true
                if Nexus.JournalTab and Nexus.JournalTab.RefreshAssociations then
                    Nexus.JournalTab.RefreshAssociations()
                end
            end)
        end)
    end
    local svc = PS()
    if svc then
        for _, name in ipairs({ "SelectPerk", "BanishPerk", "FreezePerk", "RequestReroll" }) do
            if type(svc[name]) == "function" then
                hooksecurefunc(svc, name, function(arg1)
                    pcall(function()
                        boardDirty = true
                        -- fires during our OWN sends too (before inFlightKind
                        -- is set): selfCalling distinguishes user/rival calls
                        if not selfCalling and not inFlightKind then
                            externalActionSeen = true
                            -- manual-training capture: what the USER did,
                            -- consumed by Main's decision log
                            A._lastUserAction = { kind = name,
                                arg = tonumber(arg1), t = GetTime() }
                        end
                    end)
                end)
            end
        end
        hooksInstalled = true
    end
end

function A.ConsumeDirty()
    local b, s, d = boardDirty, slotsDirty, dataDirty
    boardDirty, slotsDirty, dataDirty = false, false, false
    return b, s, d
end

-- Manual-training capture: returns and clears the last user-clicked
-- action (SelectPerk/BanishPerk/FreezePerk/RequestReroll + its argument).
function A.ConsumeUserAction()
    local ua = A._lastUserAction
    A._lastUserAction = nil
    return ua
end

function A.Init(cb, store)
    callbacks = cb or {}
    Store = store
    InstallHooks()
    lastAutoAcceptState = A.AutoAcceptOn()
    lastRivalState = A.RivalDetected()
    local scheduler = Nexus and Nexus.Scheduler
    if scheduler and scheduler.IsInitialized and scheduler.IsInitialized()
        and type(scheduler.Every) == "function" then
        local scheduled = scheduler.Every("catalog.source-check",
            CATALOG_CHECK_INTERVAL, function() A.CheckCatalogSource() end)
        catalogStatus.scheduled = scheduled == true
    end
end

function A.OnEvent(event)
    if event == "PLAYER_ENTERING_WORLD" then
        pewDone = true
        boundaryAt = GetTime()
        InstallHooks()
        A.RequestGranted()
        boardDirty, slotsDirty = true, true
    elseif event == "PLAYER_LEVEL_UP" then
        boardDirty = true
    end
end

-- Main drives this from its OnUpdate (~0.2s cadence)
function A.Poll()
    InstallHooks()
    local autoAcceptState = A.AutoAcceptOn()
    local rivalState = A.RivalDetected()
    if lastAutoAcceptState ~= nil and autoAcceptState ~= lastAutoAcceptState then
        boardDirty = true
    end
    if lastRivalState ~= nil and rivalState ~= lastRivalState then
        boardDirty = true
    end
    lastAutoAcceptState, lastRivalState = autoAcceptState, rivalState
    ResolveInFlight()
    WatchLatches()
    ReconcileTomePending()
    -- owned-sync retry loop: keep re-requesting granted until non-empty
    -- data has been seen at least once (handles the empty-{} window after a
    -- reset/reload); bounded so it never spins
    if not ownedSeen and pewDone and ownedRequestAt
        and (GetTime() - ownedRequestAt) > 5 and ownedRetries < 5 then
        A.RequestGranted()
    end
    -- Keep the active Echo Wishlist selection fresh. The player can switch
    -- which designed build is active while the addon is already running, and
    -- the old slot snapshot may otherwise leave us targeting a previous
    -- wishlist. Refresh periodically; RequestSlots() itself is rate-limited.
    if pewDone and GetTime() >= (slotsRefreshAt or 0) then
        if A.RequestSlots() then
            -- EchoJournal's data-change hook invalidates immediately after a
            -- real slot edit.  This request is only a slow recovery path for a
            -- missed server event; a five-second request/reply loop forced the
            -- complete automation pipeline to run while the player was idle.
            slotsRefreshAt = GetTime() + SLOT_REFRESH_SECONDS
        else
            slotsRefreshAt = GetTime() + 1
        end
    end

    -- bounded slots-sync retry: the client requests SS 540 lazily and an
    -- empty reply can be framed tab-less and silently dropped -- never an
    -- unbounded "waiting for slot data"
    if pewDone and slotsRetries < 5
        and (GetTime() - (slotsRetryAt or -99)) > 6 then
        local svc = PS()
        if svc and SafeCall(svc.GetServerBuildSlots) == nil then
            if A.RequestSlots() then
                slotsRetryAt = GetTime()
                slotsRetries = slotsRetries + 1
            end
        end
    end
end
