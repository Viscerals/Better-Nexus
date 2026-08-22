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
local staticDirty = false
local lastBoardSig
local boardNotificationPending = false
local inFlightKind, inFlightSig, pendingOwnPick
local recordedPicks = {}
local ownedProjectionRevision = 0
local lockedProjectionRevision = 0
local leverProjectionRevision = 0
local wishlistProjectionRevision = 0
local wishlistEvidenceObservations = {}
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
local uiHooksInstalled = {
    Show = false,
    UpdateSinglePerk = false,
    OnDataChanged = false,
}
local serviceHooksInstalled = {
    SelectPerk = false,
    BanishPerk = false,
    FreezePerk = false,
    RequestReroll = false,
}
local tomeMutationPausedUntil = 0
-- per-latch watchdog: a client latch stuck >10s with no reply is DEAD for
-- the session (per-action, like the client itself); never a whole-loop stall
local latchSince, deadLatch = {}, {}
local slotsRetryAt, slotsRetries = nil, 0
local slotsRefreshAt = 0
local lastAutoAcceptState, lastRivalState = nil, nil
local echoNotificationPending = false
local echoSnapshot = nil
local echoActiveSlot = 0
local echoVerifiedAt = nil
local echoGenerations = {
    slots=0, granted=0, locked=0, discovery=0, activeSlot=0,
}
local echoStatus = {
    slotRequests=0, notifications=0, reconciliations=0, scans=0, cacheHits=0,
    equivalentNotifications=0, equivalentFallbacks=0,
    semanticChanges=0, failures=0, associationRefreshes=0,
    fieldChanges={slots=0,granted=0,locked=0,discovery=0,activeSlot=0},
    dirtyReasons={slots=0,data=0},
    lastReason="",
}
-- Session-only aggregate work indicators for the projections consumed inside
-- AutomationRuntime.Step. Counts are fixed-shape, contain no spell IDs or
-- payloads, and never participate in revisions, dirtying, or gameplay logic.
local projectionStatus = {
    board={calls=0,cards=0,notifications=0,equivalent=0},
    slots={calls=0,slots=0,echoes=0},
    owned={calls=0,entries=0,distinct=0},
    locked={calls=0,spells=0,copies=0},
    levers={calls=0,levers=0,memberChecks=0},
    wishlist={calls=0},
}
-- Fixed session-only proof for rapid level notifications. The event handler
-- only increments scalars and the existing dirty bit; no per-level rows,
-- callbacks, timers, or scheduler work are retained.
local levelBurstStatus = {
    events=0,bursts=0,coalesced=0,pending=0,queueHighWater=0,
    pumps=0,recomputes=0,renders=0,actions=0,
    lastEvents=0,lastLevel=0,lastWorkPerPump=0,maxWorkPerPump=0,
    runBoundaryArmed=false,runBoundaryGeneration=0,
}

local function MarkWishlistPresentationDirty()
    wishlistProjectionRevision = wishlistProjectionRevision + 1
end

local function MarkWishlistProjectionDirty()
    dataDirty = true
    staticDirty = true
    wishlistEvidenceObservations = {}
    MarkWishlistPresentationDirty()
end

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

-- Cheap semantic identity for hooked board notifications. It contains every
-- choice field consumed by policy, but performs no Catalog lookup and retains
-- no board payload. A failed/malformed read deliberately returns nil so the
-- caller fails open and schedules the established full step.
local function BoardFingerprint(choice)
    if type(choice) ~= "table" or #choice == 0 then return "none" end
    local parts = {}
    for i = 1, #choice do
        local card = choice[i]
        local spellId = type(card) == "table" and tonumber(card.spellId) or nil
        local quality = type(card) == "table" and tonumber(card.quality or 0) or nil
        if not spellId or not quality then return nil end
        parts[i] = table.concat({
            tostring(spellId), tostring(quality),
            card.isFrozen and "F" or "-",
            card.isCarried and "C" or "-",
            card.isGuaranteed and "G" or "-",
            card.justFrozen and "J" or "-",
        }, ":")
    end
    return table.concat(parts, ",")
end

local function ReconcilePendingBoardState()
    if not boardNotificationPending then return end
    boardNotificationPending = false
    local svc = PS()
    local choice = svc and SafeCall(svc.GetCurrentChoice)
    local signature = BoardFingerprint(choice)
    if signature == nil or signature ~= lastBoardSig then
        boardDirty = true
        lastBoardSig = signature
    else
        projectionStatus.board.equivalent =
            projectionStatus.board.equivalent + 1
    end
end

function A.Board()
    projectionStatus.board.calls = projectionStatus.board.calls + 1
    local svc = PS()
    local ch = svc and SafeCall(svc.GetCurrentChoice)
    if type(ch) ~= "table" or #ch == 0 then return nil end
    local cards, gi = {}, nil
    local sigParts = {}
    for i = 1, #ch do
        local c = ch[i]
        projectionStatus.board.cards = projectionStatus.board.cards + 1
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
    local malformed = false
    local totalCopies = 0

    local function RecognizedInteger(value, names)
        local found, selected = false, nil
        for i = 1, #names do
            local rawValue = rawget(value, names[i])
            if rawValue ~= nil then
                local number = tonumber(rawValue)
                if type(number) ~= "number" or number ~= number
                    or number <= 0 or number >= math.huge
                    or number ~= math.floor(number)
                    or (found and number ~= selected) then
                    return nil, false, true
                end
                found, selected = true, number
            end
        end
        return selected, true, found
    end

    local function Walk(value, depth)
        if type(value) ~= "table" then malformed = true; return end
        if depth > 8 or seenTables[value] then malformed = true; return end
        seenTables[value] = true

        local id, idValid, hasId = RecognizedInteger(value, {
            "spellId", "spellID", "id", "perkId", "perkID", "entryId",
            "entryID", "echoId", "echoID", "spell", "perk",
        })
        local count, countValid, hasCount = RecognizedInteger(value, {
            "stack", "stacks", "count", "amount", "qty",
        })
        if not idValid or not countValid then malformed = true end
        if hasId and idValid and countValid then
            local n = hasCount and count or 1
            bySpell[id] = (bySpell[id] or 0) + n
            totalCopies = totalCopies + n
            if totalCopies > 6 then malformed = true end
            -- Do not `return` here -- if this table ALSO nests further locked
            -- entries as children (an id field alongside a child array, rather
            -- than instead of one), those must still be walked, not skipped.
        end

        local childTables, scalarLeaves = 0, 0
        for _, child in pairs(value) do
            if type(child) == "table" then
                childTables = childTables + 1
                Walk(child, depth + 1)
            else
                scalarLeaves = scalarLeaves + 1
            end
        end
        if not hasId and childTables == 0 and scalarLeaves > 0 then
            malformed = true
        end
    end

    Walk(raw, 0)
    return bySpell, not malformed
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
    projectionStatus.locked.calls = projectionStatus.locked.calls + 1
    local svc = PS()
    local locked = svc and SafeCall(svc.GetLockedPerks)
    local bySpell, valid = ReadLockedPerks(locked)
    local byFamily = {}
    for id, n in pairs(bySpell) do
        projectionStatus.locked.spells = projectionStatus.locked.spells + 1
        projectionStatus.locked.copies = projectionStatus.locked.copies
            + (tonumber(n) or 0)
        local fam = FamilyOf(id) or id
        byFamily[fam] = (byFamily[fam] or 0) + n
    end
    return { bySpell = bySpell, byFamily = byFamily,
        synced = type(locked) == "table" and valid == true }
end

-- Confirmed live via /nexus sniff, 2026-08-01: the server exposes the real
-- locked-slot cap directly rather than it being a hardcoded assumption.
function A.MaxPermanentEchoes()
    local svc = PS()
    local maximum = tonumber(svc and SafeCall(svc.GetMaximumPermanentEchoes))
    if not maximum or maximum ~= maximum or maximum <= 0
        or maximum >= math.huge or maximum ~= math.floor(maximum) then
        -- The editor deliberately exposes six design cells, but that is not
        -- evidence of this character's live server capacity. Automation must
        -- fail closed when the authoritative service value is unavailable.
        return nil, "unavailable"
    end
    return maximum, "service"
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
    projectionStatus.owned.calls = projectionStatus.owned.calls + 1
    local cat = A.Catalog()
    local svc = PS()
    local bySpell = {}
    local granted = svc and SafeCall(svc.GetGrantedPerks)
    if type(granted) == "table" then
        for _, entries in pairs(granted) do        -- name-keyed; use values only
            if type(entries) == "table" then
                for i = 1, #entries do
                    projectionStatus.owned.entries =
                        projectionStatus.owned.entries + 1
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
    projectionStatus.owned.distinct = projectionStatus.owned.distinct + distinct
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
    ownedProjectionRevision = ownedProjectionRevision + 1
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

local function LockState(value)
    if type(value) == "boolean" then return value end
    return nil
end

local function PositiveInteger(value)
    value = tonumber(value)
    if not value or value ~= value or value <= 0 or value >= math.huge
        or value ~= math.floor(value) then return nil end
    return value
end

local function NonNegativeInteger(value)
    value = tonumber(value)
    if not value or value ~= value or value < 0 or value >= math.huge
        or value ~= math.floor(value) then return nil end
    return value
end

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
            -- Preserve the raw tri-state lock field parsed by A.Slots(). A
            -- boolean is authoritative; an omitted or unknown field remains
            -- unavailable rather than being manufactured as false. This lets
            -- LoadPendingEchoes
            -- (ui/WishlistEditor.lua) recognize a wishlist's intended locked
            -- picks reliably, including ones that never went through Nexus's
            -- own Import button (e.g. the game's native ImportEchoLoadout UI).
            entries[#entries + 1] = { spellId = id, quality = q,
                                      stacks = stacks, family = fam,
                                      locked = LockState(e.locked) }
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
    local totals = {}
    for i = 1, #echoes do
        local e = echoes[i]
        if type(e) ~= "table" then return nil end
        local id = PositiveInteger(e.spellId)
        local stacks = e.stacks == nil and 1 or PositiveInteger(e.stacks)
        local quality = e.quality == nil and 0 or NonNegativeInteger(e.quality)
        if not id or not stacks or quality == nil then return nil end
        totals[id] = (totals[id] or 0) + stacks
    end
    local parts = {}
    for id, stacks in pairs(totals) do
        parts[#parts + 1] = tostring(id) .. ":" .. tostring(stacks)
    end
    if #parts == 0 then return nil end
    table.sort(parts)
    return table.concat(parts, ",")
end

local MAX_WISHLIST_ECHOES = 79
local MAX_WISHLIST_LOCKED_TARGETS = 6
local MAX_COMPLETE_WISHLIST_ECHOES = MAX_WISHLIST_ECHOES
    + MAX_WISHLIST_LOCKED_TARGETS
local WISHLIST_LOCK_EVIDENCE_VERSION = 1

local function WishlistStackTotal(echoes)
    local total = 0
    for i = 1, #(echoes or {}) do
        total = total + math.max(1, tonumber(echoes[i].stacks) or 1)
    end
    return total
end

local function WishlistRequiresLockEvidence(candidate)
    return type(candidate) == "table"
        and tonumber(candidate.lockEvidenceVersion)
            ~= WISHLIST_LOCK_EVIDENCE_VERSION
        and WishlistStackTotal(candidate.echoes) > MAX_WISHLIST_ECHOES
end

local function AllWishlistLocksExplicitFalse(echoes)
    if type(echoes) ~= "table" or #echoes < 1 then return false end
    for i = 1, #echoes do
        if type(echoes[i]) ~= "table" or echoes[i].locked ~= false then
            return false
        end
    end
    return true
end

-- Designed builds can contain the ordinary 79-copy upload plus as many as six
-- server-authoritative locked targets. A legacy record without explicit lock
-- evidence may remain visible by stable identity up to the complete 85-copy
-- envelope, but it gains no action authority until an exact live candidate
-- supplies complete boolean evidence.
local function NormalizeWishlistEchoes(echoes, evidenceVersion, allowInlineEvidence)
    if type(echoes) ~= "table" then return nil end
    local count, maxIndex = 0, 0
    for index in pairs(echoes) do
        if type(index) == "number" then
            if index < 1 or index ~= math.floor(index) then return nil end
            count = count + 1
            if index > maxIndex then maxIndex = index end
        end
    end
    if count < 1 or count ~= maxIndex then return nil end

    local markedEvidence = tonumber(evidenceVersion)
        == WISHLIST_LOCK_EVIDENCE_VERSION
    local inlineEvidence = allowInlineEvidence and true or false
    local out = {}
    for i = 1, maxIndex do
        local entry = echoes[i]
        if type(entry) ~= "table" or type(entry.locked) ~= "boolean" then
            inlineEvidence = false
            if markedEvidence then return nil end
        end
    end
    local hasLockEvidence = markedEvidence or inlineEvidence
    local ordinaryStacks, lockedStacks, totalStacks = 0, 0, 0
    for i = 1, maxIndex do
        local entry = echoes[i]
        local spellId = type(entry) == "table"
            and PositiveInteger(entry.spellId) or nil
        local stacks = type(entry) == "table"
            and PositiveInteger(entry.stacks) or nil
        local quality = type(entry) == "table" and (entry.quality == nil
            and 0 or NonNegativeInteger(entry.quality)) or nil
        if not spellId or not stacks or quality == nil then
            return nil
        end
        totalStacks = totalStacks + stacks
        if hasLockEvidence and entry.locked then
            lockedStacks = lockedStacks + stacks
        elseif hasLockEvidence then
            ordinaryStacks = ordinaryStacks + stacks
        end
        if (hasLockEvidence and ordinaryStacks > MAX_WISHLIST_ECHOES)
            or lockedStacks > MAX_WISHLIST_LOCKED_TARGETS
            or totalStacks > MAX_COMPLETE_WISHLIST_ECHOES then return nil end
        out[i] = {
            spellId=spellId, quality=quality,
            stacks=stacks,
            locked=LockState(entry.locked),
        }
    end
    return out, hasLockEvidence,
        hasLockEvidence and "authoritative" or "unavailable"
end

-- Fixed diagnostic states distinguish a missing identity from a malformed or
-- mismatched one without ever turning an unknown lock flag into false. The
-- passive "unavailable" marker is authoritative for classification: it keeps
-- an over-envelope identity visible while withholding all action authority.
local function ClassifyWishlistEvidence(candidate, expectedKey)
    if candidate == nil then return "identity-unavailable" end
    if type(candidate) ~= "table" or type(candidate.echoes) ~= "table" then
        return "invalid-schema"
    end
    if candidate.lockEvidenceStatus ~= nil
        and candidate.lockEvidenceStatus ~= "unavailable"
        and candidate.lockEvidenceStatus ~= "authoritative" then
        return "invalid-schema"
    end
    if candidate.lockEvidenceVersion ~= nil
        and tonumber(candidate.lockEvidenceVersion)
            ~= WISHLIST_LOCK_EVIDENCE_VERSION then
        return "invalid-schema"
    end
    if candidate.lockEvidenceStatus == "unavailable"
        and tonumber(candidate.lockEvidenceVersion)
            == WISHLIST_LOCK_EVIDENCE_VERSION then
        return "invalid-schema"
    end
    if candidate.key ~= nil and type(candidate.key) ~= "string" then
        return "invalid-schema"
    end
    for index, entry in pairs(candidate.echoes) do
        if type(index) == "number" and (type(entry) ~= "table"
            or (entry.locked ~= nil and type(entry.locked) ~= "boolean")) then
            return "invalid-schema"
        end
    end

    local allowInlineEvidence = candidate.lockEvidenceStatus ~= "unavailable"
    local echoes, hasLockEvidence = NormalizeWishlistEchoes(
        candidate.echoes, candidate.lockEvidenceVersion, allowInlineEvidence)
    if not echoes then return "invalid-schema" end
    local key = WishlistIdentity(echoes)
    if not key then return "invalid-schema" end
    if type(candidate.key) == "string" and candidate.key ~= ""
        and candidate.key ~= key then
        return "association-mismatch", key
    end
    if expectedKey ~= nil and (type(expectedKey) ~= "string"
        or expectedKey == "" or expectedKey ~= key) then
        return "association-mismatch", key
    end
    if not hasLockEvidence
        and WishlistStackTotal(echoes) > MAX_WISHLIST_ECHOES then
        return "evidence-pending", key
    end
    return "actionable", key
end

local function WishlistEchoesFromIdentity(key)
    if type(key) ~= "string" or key == "" then return nil end
    local out, totalStacks = {}, 0
    for part in key:gmatch("[^,]+") do
        if #out >= MAX_COMPLETE_WISHLIST_ECHOES then return nil end
        local idText, stacksText = part:match("^(%d+):(%d+)$")
        local spellId, stacks = tonumber(idText), tonumber(stacksText)
        if not spellId or spellId <= 0 or not stacks or stacks < 1 then
            return nil
        end
        totalStacks = totalStacks + stacks
        if totalStacks > MAX_COMPLETE_WISHLIST_ECHOES then return nil end
        out[#out + 1] = {
            spellId=spellId, quality=0, stacks=stacks,
        }
    end
    return #out > 0 and out or nil
end

local function StoredWishlistRecord(candidate)
    candidate = type(candidate) == "table" and candidate or {}
    local echoes, hasLockEvidence = NormalizeWishlistEchoes(
        candidate.echoes, candidate.lockEvidenceVersion, true)
    if not echoes then return nil end
    if not hasLockEvidence
        and WishlistStackTotal(echoes) > MAX_WISHLIST_ECHOES then return nil end
    local key = WishlistIdentity(echoes)
    if type(candidate.key) == "string" and candidate.key ~= ""
        and candidate.key ~= key then return nil end
    local record = {
        slot=tonumber(candidate.slot), name=tostring(candidate.name or ""),
        key=key,
    }
    if echoes then record.echoes = echoes end
    if hasLockEvidence then
        record.lockEvidenceVersion = WISHLIST_LOCK_EVIDENCE_VERSION
    end
    return record
end

local function CandidateFromStoredRecord(saved)
    if type(saved) ~= "table" then return nil end
    local echoes, hasLockEvidence = NormalizeWishlistEchoes(
        saved.echoes, saved.lockEvidenceVersion, false)
    if not echoes then echoes = WishlistEchoesFromIdentity(saved.key) end
    if not echoes then return nil end
    local key = WishlistIdentity(echoes)
    if type(saved.key) == "string" and saved.key ~= ""
        and saved.key ~= key then return nil end
    local candidate = {
        slot=tonumber(saved.slot), name=tostring(saved.name or ""),
        count=#echoes, echoes=echoes, key=key, active=false, stored=true,
        lockEvidenceVersion=hasLockEvidence
            and WISHLIST_LOCK_EVIDENCE_VERSION or nil,
    }
    if WishlistRequiresLockEvidence(candidate) then
        candidate.lockEvidenceStatus = "unavailable"
    end
    return candidate
end

local function CandidateSnapshot(candidate, expectedSlot)
    if type(candidate) ~= "table"
        or tonumber(candidate.slot) ~= tonumber(expectedSlot) then return nil end
    local echoes, hasLockEvidence = NormalizeWishlistEchoes(
        candidate.echoes, candidate.lockEvidenceVersion, true)
    if not echoes then return nil end
    if not hasLockEvidence and WishlistStackTotal(echoes) > MAX_WISHLIST_ECHOES
        and candidate.lockEvidenceStatus ~= "unavailable" then return nil end
    local key = WishlistIdentity(echoes)
    if type(candidate.key) == "string" and candidate.key ~= ""
        and candidate.key ~= key then return nil end
    local snapshot = {
        slot=tonumber(candidate.slot), name=tostring(candidate.name or ""),
        count=#echoes, echoes=echoes, key=key, active=false,
        lockEvidenceVersion=hasLockEvidence
            and WISHLIST_LOCK_EVIDENCE_VERSION or nil,
    }
    if WishlistRequiresLockEvidence(snapshot) then
        snapshot.lockEvidenceStatus = "unavailable"
    end
    return snapshot
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

function A.WishlistEvidenceState(candidate, expectedKey)
    return ClassifyWishlistEvidence(candidate, expectedKey)
end

local function LiveWishlistCandidates(slots)
    slots = slots or A.Slots()
    if not slots then return {} end
    local maxSlots = slots.maxSlots or 5
    local out = {}
    local cat, catalogRead
    for slotId, row in pairs(slots.bySlot or {}) do
        local isDesigned = (row.verified == false)
            or (type(row.slot) == "number" and row.slot > maxSlots)
        if isDesigned and type(row.echoes) == "table" and #row.echoes > 0 then
            if not catalogRead then
                cat, catalogRead = A.Catalog(), true
            end
            local echoes = {}
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
                    locked = LockState(e.locked),
                }
            end
            local normalized, hasLockEvidence = NormalizeWishlistEchoes(
                echoes, nil, true)
            -- An explicit all-false 80-85 mirror proves a stable server
            -- identity, but also proves that it cannot be an actionable
            -- ordinary Wishlist. Keep that identity passively visible by
            -- deliberately discarding inline authority for discovery only.
            -- CandidateSnapshot revalidates actions with inline evidence and
            -- therefore continues to reject the same over-79 payload.
            if not normalized and AllWishlistLocksExplicitFalse(echoes) then
                normalized, hasLockEvidence = NormalizeWishlistEchoes(
                    echoes, nil, false)
            end
            if normalized then
                local candidate = {
                    slot = tonumber(slotId) or tonumber(row.slot),
                    name = tostring(row.name or ""), count = #normalized,
                    echoes = normalized, key = WishlistIdentity(normalized),
                    active = false,
                    lockEvidenceVersion=hasLockEvidence
                        and WISHLIST_LOCK_EVIDENCE_VERSION or nil,
                }
                if WishlistRequiresLockEvidence(candidate) then
                    candidate.lockEvidenceStatus = "unavailable"
                end
                out[#out + 1] = candidate
            end
        end
    end
    table.sort(out, function(a, b) return (tonumber(a.slot) or 0) < (tonumber(b.slot) or 0) end)
    return out
end

function A.GetWishlistCandidates()
    local out = LiveWishlistCandidates()

    -- Slot mirrors are eventually consistent. When the complete designed list
    -- is absent or partial, also expose immutable identities the user already
    -- associated; never infer an unrelated candidate from a recycled slot.
    local state = Store and Store.State and Store.State()
    if not state then return out end
    local seen = {}
    for _, candidate in ipairs(out) do
        if candidate.key then seen[candidate.key] = true end
    end
    local function Add(saved)
        local candidate = CandidateFromStoredRecord(saved)
        if not candidate or seen[candidate.key] then return end
        seen[candidate.key] = true
        out[#out + 1] = candidate
    end
    Add(state.firstRunWishlist)
    for _, saved in pairs(state.loadoutWishlists or {}) do Add(saved) end
    table.sort(out, function(a, b)
        return (tonumber(a.slot) or 0) < (tonumber(b.slot) or 0)
    end)
    return out
end

local function SelectWishlistCandidate(wishlistSlot, candidate)
    wishlistSlot = tonumber(wishlistSlot)
    if not wishlistSlot or wishlistSlot < 1
        or wishlistSlot ~= math.floor(wishlistSlot) then
        return nil, "invalid wishlist"
    end
    local snapshot = candidate ~= nil
        and CandidateSnapshot(candidate, wishlistSlot) or nil
    if candidate ~= nil and not snapshot then return nil, "invalid wishlist" end
    if snapshot and WishlistRequiresLockEvidence(snapshot) then
        return nil, "wishlist lock evidence unavailable; refresh and try again"
    end

    local live = LiveWishlistCandidates()
    if snapshot then
        for _, current in ipairs(live) do
            if current.key == snapshot.key then return current end
        end
        for _, current in ipairs(live) do
            if tonumber(current.slot) == wishlistSlot then
                return nil, "wishlist changed; refresh and try again"
            end
        end
        -- A missing live row is uncertain, not deletion evidence. Admit the
        -- already-rendered immutable identity so one transient read cannot
        -- invalidate the user's click.
        return snapshot
    end
    for _, current in ipairs(live) do
        if tonumber(current.slot) == wishlistSlot then return current end
    end
    for _, stored in ipairs(A.GetWishlistCandidates()) do
        if tonumber(stored.slot) == wishlistSlot then return stored end
    end
    return nil, "invalid wishlist"
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
                if not WishlistRequiresLockEvidence(c) then
                    saved.slot, saved.name = c.slot, c.name
                end
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
            if nameMatches == 1 and nameMatch
                and tonumber(nameMatch.slot) ~= oldSlot then
                saved.slot, saved.key, saved.name = nameMatch.slot, nameMatch.key, nameMatch.name
                return nameMatch
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
    -- Missing or partial server mirrors are not deletion evidence. Retain the
    -- association and its bounded payload until an explicit user action clears
    -- or replaces it.
    return CandidateFromStoredRecord(saved)
end

-- First-run target: players with no populated/active Saved Build still need a
-- wishlist target so Nexus can guide their very first 1-80 run. This is a
-- temporary account-local association and is replaced naturally once the
-- player has a real Saved Build selected.
local function ResolveFirstRunWishlist()
    local state = Store and Store.State and Store.State()
    local saved = state and state.firstRunWishlist
    if type(saved) ~= "table" then
        local unique, only, count = {}, nil, 0
        for _, linked in pairs((state and state.loadoutWishlists) or {}) do
            local candidate = CandidateFromStoredRecord(linked)
            if candidate and not unique[candidate.key] then
                unique[candidate.key] = true
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
                if not WishlistRequiresLockEvidence(c) then
                    saved.slot, saved.name = c.slot, c.name
                end
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
    return CandidateFromStoredRecord(saved)
end

function A.GetFirstRunWishlist()
    local candidate = ResolveFirstRunWishlist()
    if WishlistRequiresLockEvidence(candidate) then return nil end
    return candidate
end

function A.SetFirstRunWishlist(wishlistSlot, candidate)
    wishlistSlot = tonumber(wishlistSlot)
    local selected, why = SelectWishlistCandidate(wishlistSlot, candidate)
    if not selected then return false, why end
    local record = StoredWishlistRecord(selected)
    if not record then return false, "invalid wishlist" end
    local state = Store and Store.State and Store.State()
    if not state then return false, "store unavailable" end
    state.firstRunWishlist = record
    MarkWishlistProjectionDirty()
    return true
end

function A.SetFirstRunWishlistIdentity(name, echoes)
    local record = StoredWishlistRecord({name=name, echoes=echoes})
    if not record then return false end
    local state = Store and Store.State and Store.State()
    if not state then return false end
    state.firstRunWishlist = record
    MarkWishlistProjectionDirty()
    return true
end

function A.ClearFirstRunWishlist()
    local state = Store and Store.State and Store.State()
    if not state then return false end
    state.firstRunWishlist = nil
    MarkWishlistProjectionDirty()
    return true
end

local function IsPopulatedLoadout(loadoutSlot, slots)
    loadoutSlot = tonumber(loadoutSlot)
    slots = slots or A.Slots()
    local row = slots and slots.bySlot and loadoutSlot and slots.bySlot[loadoutSlot]
    return row and type(row.echoes) == "table" and #row.echoes > 0 and true or false
end

-- A designed 80-85-copy mirror and the verified active loadout carry the exact
-- total, but their inline lock flags may be absent or unusably all-false.
-- Bridge only that active association: prove exact spell/stack identity, then
-- subtract the independent authoritative LockedOwned counts from the active
-- totals. The result is a new projection; neither mirror nor SavedVariables
-- is rewritten.
local function ExactActiveWishlistRoles(slots, loadoutSlot, candidate)
    loadoutSlot = tonumber(loadoutSlot)
    if type(slots) ~= "table" or not loadoutSlot
        or tonumber(slots.activeSlot) ~= loadoutSlot
        or type(candidate) ~= "table"
        or not WishlistRequiresLockEvidence(candidate) then return nil end

    local active = slots.bySlot and slots.bySlot[loadoutSlot]
    if type(active) ~= "table" or active.verified ~= true
        or active.verifiedFieldPresent ~= true
        or type(active.echoes) ~= "table" or #active.echoes < 1 then
        return nil
    end
    local candidateKey = type(candidate.key) == "string" and candidate.key
        or WishlistIdentity(candidate.echoes)
    local activeKey = WishlistIdentity(active.echoes)
    if not candidateKey or not activeKey or candidateKey ~= activeKey then
        return nil
    end

    local catalog = A.Catalog()
    local totalBySpell, qualityBySpell = {}, {}
    local totalCopies = 0
    for index = 1, #active.echoes do
        local echo = active.echoes[index]
        local id = type(echo) == "table" and PositiveInteger(echo.spellId)
        local stacks = type(echo) == "table" and PositiveInteger(echo.stacks)
        local quality = type(echo) == "table"
            and NonNegativeInteger(echo.quality) or nil
        if quality == nil and id and catalog and catalog.rows
            and catalog.rows[id] then
            quality = NonNegativeInteger(catalog.rows[id].quality)
        end
        if not id or not stacks or quality == nil then return nil end
        totalCopies = totalCopies + stacks
        if qualityBySpell[id] ~= nil and qualityBySpell[id] ~= quality then
            return nil
        end
        qualityBySpell[id] = quality
        totalBySpell[id] = (totalBySpell[id] or 0) + stacks
    end
    if totalCopies > MAX_COMPLETE_WISHLIST_ECHOES then return nil end

    local owned = A.LockedOwned()
    if type(owned) ~= "table" or owned.synced ~= true
        or type(owned.bySpell) ~= "table" then return nil end
    local represented, lockedCopies = {}, 0
    for spellId, count in pairs(owned.bySpell) do
        local id, copies = PositiveInteger(spellId), PositiveInteger(count)
        if not id or not copies or copies > (totalBySpell[id] or 0) then
            return nil
        end
        represented[id] = (represented[id] or 0) + copies
        lockedCopies = lockedCopies + copies
    end
    if lockedCopies > MAX_WISHLIST_LOCKED_TARGETS
        or totalCopies - lockedCopies > MAX_WISHLIST_ECHOES then return nil end

    local ids, ordinary, lockedRows = {}, {}, {}
    for id in pairs(totalBySpell) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local lockedCount = represented[id] or 0
        local ordinaryCount = totalBySpell[id] - lockedCount
        if ordinaryCount > 0 then
            ordinary[#ordinary + 1] = {
                spellId=id,quality=qualityBySpell[id],stacks=ordinaryCount,
                locked=false,sourceRole="ordinary",
                evidenceSource="verified-active-minus-locked",
            }
        end
        if lockedCount > 0 then
            lockedRows[#lockedRows + 1] = {
                spellId=id,quality=qualityBySpell[id],stacks=lockedCount,
                locked=true,sourceRole="locked",
                evidenceSource="authoritative-locked-owned",
            }
        end
    end
    local evidence = Nexus and Nexus.CandidateEvidence
    if not (evidence
        and type(evidence.NormalizeLockedEchoes) == "function") then return nil end
    local normalizedLocked, lockedReason = evidence.NormalizeLockedEchoes(
        lockedRows)
    if not normalizedLocked or lockedReason ~= nil then return nil end

    local echoes = {}
    for _, row in ipairs(ordinary) do echoes[#echoes + 1] = row end
    for _, row in ipairs(normalizedLocked) do echoes[#echoes + 1] = row end
    return {
        slot=candidate.slot, name=candidate.name, count=#echoes,
        echoes=echoes, key=activeKey, active=candidate.active,
        lockEvidenceVersion=WISHLIST_LOCK_EVIDENCE_VERSION,
        lockEvidenceStatus="authoritative",
        evidenceSource="verified-active",
        activeLoadoutSlot=loadoutSlot,
    }
end

-- Read-only association diagnosis for presentation code. Unlike
-- ResolveAssociation, this never migrates, renames, reindexes, or otherwise
-- rewrites SavedVariables; it admits only an exact stable identity or the
-- bounded immutable fallback already stored for that identity.
local function ReadLoadoutWishlistState(loadoutSlot)
    loadoutSlot = tonumber(loadoutSlot)
    if not loadoutSlot then return nil, "identity-unavailable", nil end
    local slots = A.Slots()
    if not IsPopulatedLoadout(loadoutSlot, slots) then
        return nil, "identity-unavailable", nil
    end
    local state = Store and Store.State and Store.State()
    local links = state and state.loadoutWishlists
    local saved = links and links[loadoutSlot]
    if saved == nil then return nil, "identity-unavailable", nil end
    if type(saved) ~= "table" then return nil, "invalid-schema", nil end
    if saved.key ~= nil and type(saved.key) ~= "string" then
        return nil, "invalid-schema", nil
    end

    local expectedKey = saved.key
    local candidate
    if type(expectedKey) == "string" and expectedKey ~= "" then
        for _, current in ipairs(LiveWishlistCandidates(slots)) do
            if current.key == expectedKey then
                candidate = current
                break
            end
        end
    end
    candidate = candidate or CandidateFromStoredRecord(saved)
    if not candidate then
        return nil, expectedKey and expectedKey ~= ""
            and "invalid-schema" or "association-mismatch", expectedKey
    end

    if WishlistRequiresLockEvidence(candidate) then
        candidate = ExactActiveWishlistRoles(slots, loadoutSlot, candidate)
            or candidate
    end
    local evidenceState, key = ClassifyWishlistEvidence(candidate,
        expectedKey ~= "" and expectedKey or nil)
    if expectedKey == nil or expectedKey == "" then
        evidenceState = "association-mismatch"
    end
    return candidate, evidenceState, key
end

local function RememberLoadoutWishlistState(loadoutSlot, key, evidenceState)
    loadoutSlot = tonumber(loadoutSlot)
    if not loadoutSlot or loadoutSlot < 1 or loadoutSlot > 5
        or type(key) ~= "string" or key == "" then
        if loadoutSlot then wishlistEvidenceObservations[loadoutSlot] = nil end
        return
    end
    local previous = wishlistEvidenceObservations[loadoutSlot]
    if not previous or previous.key ~= key then
        wishlistEvidenceObservations[loadoutSlot] = {
            key=key,state=evidenceState,
        }
        return
    end
    -- Preserve the pending edge until the semantic notification path observes
    -- it. A UI read that happens just before Poll must not consume the edge.
    if previous.state == "evidence-pending"
        and evidenceState == "actionable" then return end
    previous.state = evidenceState
end

function A.GetLoadoutWishlistState(loadoutSlot)
    local candidate, evidenceState, key =
        ReadLoadoutWishlistState(loadoutSlot)
    RememberLoadoutWishlistState(loadoutSlot, key, evidenceState)
    return candidate, evidenceState, key
end

-- Runs only after a semantic designed-slot change and only when a presentation
-- reader previously observed an association. The table is bounded by the five
-- loadout slots; ordinary 0.2-second Poll calls do no Wishlist traversal.
local function RefreshWishlistEvidenceTransitions()
    if next(wishlistEvidenceObservations) == nil then return false end
    local liveStates = {}
    for _, candidate in ipairs(LiveWishlistCandidates()) do
        local evidenceState, key = ClassifyWishlistEvidence(candidate)
        if key then
            if liveStates[key] == nil then
                liveStates[key] = evidenceState
            elseif liveStates[key] ~= evidenceState then
                liveStates[key] = "ambiguous"
            end
        end
    end

    local transitioned = false
    for _, observed in pairs(wishlistEvidenceObservations) do
        local evidenceState = liveStates[observed.key]
        if evidenceState then
            if observed.state == "evidence-pending"
                and evidenceState == "actionable" then
                transitioned = true
            end
            observed.state = evidenceState
        end
    end
    if transitioned then MarkWishlistPresentationDirty() end
    return transitioned
end

function A.GetLoadoutWishlist(loadoutSlot)
    -- An association on an empty numbered slot is stale metadata, not a usable
    -- build. Never expose it to the panel/UI as though the player can swap to it.
    local slots = A.Slots()
    if not IsPopulatedLoadout(loadoutSlot, slots) then return nil end
    local candidate = ResolveAssociation(loadoutSlot)
    if WishlistRequiresLockEvidence(candidate) then
        candidate = ExactActiveWishlistRoles(slots, loadoutSlot, candidate)
    end
    if WishlistRequiresLockEvidence(candidate) then return nil end
    return candidate
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
    local record = StoredWishlistRecord({name=name, echoes=echoes})
    if not record then return false, "invalid wishlist" end
    local state = Store and Store.State and Store.State()
    if not state then return false, "store unavailable" end
    state.loadoutWishlists = state.loadoutWishlists or {}
    state.loadoutWishlists[loadoutSlot] = record
    state.firstRunWishlist = nil
    MarkWishlistProjectionDirty()
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
    local record = StoredWishlistRecord({name=name, echoes=echoes})
    if not record then return false, "invalid wishlist" end
    local state = Store and Store.State and Store.State()
    if not state then return false, "store unavailable" end
    state.loadoutWishlists = state.loadoutWishlists or {}
    state.loadoutWishlists[1] = record
    state.firstRunWishlist = StoredWishlistRecord(record)
    MarkWishlistProjectionDirty()
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
    local selected, why = SelectWishlistCandidate(wishlistSlot, candidate)
    if not selected then return false, why end
    local record = StoredWishlistRecord(selected)
    if not record then return false, "invalid wishlist" end
    local state = Store and Store.State and Store.State()
    if not state then return false, "store unavailable" end
    state.loadoutWishlists = state.loadoutWishlists or {}
    state.loadoutWishlists[loadoutSlot] = record
    state.firstRunWishlist = nil
    MarkWishlistProjectionDirty()
    return true
end


function A.UpdateWishlistAssociationAfterSave(loadoutSlot, wishlistSlot, name, echoes)
    loadoutSlot, wishlistSlot = tonumber(loadoutSlot), tonumber(wishlistSlot)
    if not loadoutSlot or not wishlistSlot then return false end
    local record = StoredWishlistRecord({
        slot=wishlistSlot, name=name, echoes=echoes,
    })
    if not record then return false end
    local state = Store and Store.State and Store.State()
    if not state then return false end
    state.loadoutWishlists = state.loadoutWishlists or {}
    state.loadoutWishlists[loadoutSlot] = record
    state.firstRunWishlist = nil
    MarkWishlistProjectionDirty()
    return true
end

function A.ClearLoadoutWishlist(loadoutSlot)
    if A.DIAGNOSTIC_PASSIVE then return false, "internal.6 passive diagnostic: write blocked" end
    loadoutSlot = tonumber(loadoutSlot)
    local state = Store and Store.State and Store.State()
    if not state or not loadoutSlot then return false end
    state.loadoutWishlists = state.loadoutWishlists or {}
    state.loadoutWishlists[loadoutSlot] = nil
    MarkWishlistProjectionDirty()
    return true
end

function A.Wishlist()
    projectionStatus.wishlist.calls = projectionStatus.wishlist.calls + 1
    A._wishlistNote = nil
    local slots = A.Slots()
    local activeSlot = slots and tonumber(slots.activeSlot) or 0
    local maxSlots = slots and (tonumber(slots.maxSlots) or 5) or 5
    if activeSlot < 1 or activeSlot > maxSlots then
        local starter = ResolveFirstRunWishlist()
        if starter then
            if WishlistRequiresLockEvidence(starter) then
                A._wishlistNote = "Wishlist identity found, but lock evidence is temporarily unavailable; awaiting authoritative lock evidence."
                return nil
            end
            A._wishlistNote = "First-run wishlist target"
            return EchoesToWishlist(starter.echoes, starter.name,
                "first-run-wishlist", false, starter.slot)
        end
        local state = Store and Store.State and Store.State()
        if state and type(state.firstRunWishlist) == "table" then
            A._wishlistNote = "First-run wishlist data is temporarily unavailable; waiting for the server mirror."
            return nil
        end
        A._wishlistNote = "Choose or create a wishlist to begin your first run."
        return nil
    end
    local linked = ResolveAssociation(activeSlot)
    if linked then
        if WishlistRequiresLockEvidence(linked) then
            linked = ExactActiveWishlistRoles(slots, activeSlot, linked)
            if not linked then
                A._wishlistNote = "Wishlist identity found, but lock evidence is temporarily unavailable; awaiting authoritative lock evidence."
                return nil
            end
        end
        return EchoesToWishlist(linked.echoes, linked.name,
            "loadout-association", linked.evidenceSource == "verified-active",
            linked.slot)
    end
    local state = Store and Store.State and Store.State()
    if state and type(state.loadoutWishlists) == "table"
        and state.loadoutWishlists[activeSlot] ~= nil then
        A._wishlistNote = "Wishlist data is temporarily unavailable; waiting for the server mirror."
        return nil
    end
    -- Promote one explicitly selected zero-slot target when the server later
    -- publishes a real populated active loadout. This is the only automatic
    -- hand-off; ambiguous stored associations remain unresolved.
    local starter = IsPopulatedLoadout(activeSlot, slots)
        and ResolveFirstRunWishlist() or nil
    if starter then
        local state = Store and Store.State and Store.State()
        local record = StoredWishlistRecord(starter)
        if state and record then
            state.loadoutWishlists = state.loadoutWishlists or {}
            state.loadoutWishlists[activeSlot] = record
            state.firstRunWishlist = nil
            MarkWishlistProjectionDirty()
        end
        return EchoesToWishlist(starter.echoes, starter.name,
            "loadout-association", false, starter.slot)
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
    projectionStatus.slots.calls = projectionStatus.slots.calls + 1
    local svc = PS()
    local raw = svc and SafeCall(svc.GetServerBuildSlots)
    if type(raw) ~= "table" then return nil end
    local maxSlots = tonumber(svc and SafeCall(svc.GetServerMaxSlots)) or 5
    local bySlot = {}
    local anyFalse, designedTrue = false, false
    for slot, s in pairs(raw) do
        if type(s) == "table" then
            projectionStatus.slots.slots = projectionStatus.slots.slots + 1
            local echoes = {}
            if type(s.echoes) == "table" then
                for i = 1, #s.echoes do
                    projectionStatus.slots.echoes =
                        projectionStatus.slots.echoes + 1
                    local e = s.echoes[i]
                    local id = type(e) == "table" and tonumber(e.spellId)
                    if id then
                        echoes[#echoes + 1] = {
                            spellId = id, stacks = tonumber(e.stacks) or 1,
                            quality = tonumber(e.quality),
                            locked = LockState(e.locked),
                            family = FamilyOf(id),
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
        echoStatus.slotRequests = echoStatus.slotRequests + 1
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
    projectionStatus.levers.calls = projectionStatus.levers.calls + 1
    local cat = A.Catalog()
    local svc = PS()
    local out = {}
    if not cat or not svc then return out end
    local pending = Store and Store.State().tomeTogglePending or {}
    for lever, lv in pairs(cat.levers) do
        projectionStatus.levers.levers = projectionStatus.levers.levers + 1
        local dis = false
        for i = 1, #lv.members do
            projectionStatus.levers.memberChecks =
                projectionStatus.levers.memberChecks + 1
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
        leverProjectionRevision = leverProjectionRevision + 1
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
            leverProjectionRevision = leverProjectionRevision + 1
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
                    ownedProjectionRevision = ownedProjectionRevision + 1
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
        lockedProjectionRevision = lockedProjectionRevision + 1
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
        lockedProjectionRevision = lockedProjectionRevision + 1
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

-- A new Echo run is authoritative only after this session has observed the
-- previous run at level 80 and then observes a live lower level. The sticky
-- generation survives event coalescing until AutomationRuntime consumes it;
-- PLAYER_LEVEL_UP arguments are deliberately not trusted as live state.
local function ObserveRunBoundary()
    local level = tonumber(A.Level())
    if not level or level ~= math.floor(level) or level < 1 or level > 80 then
        return false
    end
    if level == 80 then
        levelBurstStatus.runBoundaryArmed = true
        return false
    end
    if not levelBurstStatus.runBoundaryArmed then return false end
    levelBurstStatus.runBoundaryArmed = false
    levelBurstStatus.runBoundaryGeneration =
        levelBurstStatus.runBoundaryGeneration + 1
    boardDirty = true
    return true
end

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

-- Project Ebonhold replaces its Echo tables on routine server replies. Raw
-- identity is therefore not change evidence. These exact canonical snapshots
-- are built only for a received Echo notification or the five-second
-- AutomationRuntime fallback -- never for an ordinary 0.2-second Poll.
local ECHO_FIELDS = {"slots", "granted", "locked", "discovery", "activeSlot"}

local function EchoReason(value)
    value = tostring(value or "")
    if #value > 96 then value = value:sub(1, 96) end
    echoStatus.lastReason = value
end

local function FiniteNumber(value)
    return type(value) == "number" and value == value
        and value < math.huge and value > -math.huge
end

local function NumberPart(value)
    if not FiniteNumber(value) then return nil end
    return string.format("%.17g", value)
end

local function IntegerAtLeast(value, minimum)
    return FiniteNumber(value) and value == math.floor(value)
        and value >= (minimum or 0)
end

local function DenseArrayLength(values, label)
    if type(values) ~= "table" then return nil, label .. ":not-table" end
    local count, maximum = 0, 0
    for key in pairs(values) do
        if type(key) ~= "number" or not IntegerAtLeast(key, 1) then
            return nil, label .. ":key"
        end
        count = count + 1
        if key > maximum then maximum = key end
    end
    if count ~= maximum then return nil, label .. ":sparse" end
    return maximum
end

local function TextPart(value)
    if value == nil then return "0:" end
    local kind = type(value)
    if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then
        return nil
    end
    local text = tostring(value)
    return tostring(#text) .. ":" .. text
end

local function CountsFingerprint(counts)
    local ids = {}
    for id in pairs(counts or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for i = 1, #ids do
        parts[i] = tostring(ids[i]) .. ":" .. tostring(counts[ids[i]])
    end
    return table.concat(parts, ",")
end

local function SlotsFingerprint(raw, maxSlots)
    if raw == nil then return "nil" end
    if type(raw) ~= "table" then return nil, "slots:not-table" end
    local maxPart = NumberPart(maxSlots)
    if not maxPart then return nil, "slots:max" end
    local rows, seenSlots = {}, {}
    for slotKey, row in pairs(raw) do
        local slot = tonumber(slotKey)
        if not IntegerAtLeast(slot, 1)
            or seenSlots[slot] or type(row) ~= "table" then
            return nil, "slots:row"
        end
        seenSlots[slot] = true
        local name = TextPart(row.name or "")
        if not name then return nil, "slots:name" end
        if row.verified ~= nil and type(row.verified) ~= "boolean" then
            return nil, "slots:verified"
        end
        local echoes = row.echoes
        if echoes ~= nil and type(echoes) ~= "table" then
            return nil, "slots:echoes"
        end
        local echoCount, echoCountError =
            DenseArrayLength(echoes or {}, "slots:echoes")
        if not echoCount then return nil, echoCountError end
        local echoParts = {}
        for i = 1, echoCount do
            local entry = echoes[i]
            local spellId = type(entry) == "table"
                and tonumber(entry.spellId) or nil
            local stacks = type(entry) == "table"
                and (tonumber(entry.stacks) or 1) or nil
            local idPart, stackPart = NumberPart(spellId), NumberPart(stacks)
            if not idPart or not stackPart or not IntegerAtLeast(spellId, 1)
                or not IntegerAtLeast(stacks, 1)
                or (entry.locked ~= nil and type(entry.locked) ~= "boolean") then
                return nil, "slots:echo"
            end
            local lockPart = entry.locked == nil and "?"
                or (entry.locked and "1" or "0")
            echoParts[#echoParts + 1] = table.concat({
                idPart, stackPart, lockPart,
            }, ":")
        end
        table.sort(echoParts)
        rows[#rows + 1] = table.concat({
            NumberPart(slot), name, row.verified and "1" or "0",
            table.concat(echoParts, ","),
        }, "|")
    end
    table.sort(rows)
    return maxPart .. ";" .. table.concat(rows, ";")
end

local function GrantedFingerprint(raw, catalog)
    if raw == nil then return "nil" end
    if type(raw) ~= "table" then return nil, "granted:not-table" end
    local counts = {}
    for groupName, entries in pairs(raw) do
        if type(groupName) ~= "string" or groupName == ""
            or type(entries) ~= "table" then
            return nil, "granted:entries"
        end
        local entryCount, entryCountError =
            DenseArrayLength(entries, "granted:entries")
        if not entryCount then return nil, entryCountError end
        for i = 1, entryCount do
            local entry = entries[i]
            local spellId = type(entry) == "table"
                and tonumber(entry.spellId) or nil
            if not IntegerAtLeast(spellId, 1) then
                return nil, "granted:entry"
            end
            if type(catalog) == "table" and type(catalog.rows) == "table"
                and catalog.rows[spellId] then
                counts[spellId] = (counts[spellId] or 0) + 1
            end
        end
    end
    return CountsFingerprint(counts)
end

local function LockedFingerprint(raw)
    if raw == nil then return "nil" end
    if type(raw) ~= "table" then return nil, "locked:not-table" end
    local ok, counts, valid = pcall(ReadLockedPerks, raw)
    if not ok or type(counts) ~= "table" or not valid then
        return nil, "locked:read"
    end
    for spellId, count in pairs(counts) do
        if not IntegerAtLeast(spellId, 1) or not IntegerAtLeast(count, 1) then
            return nil, "locked:value"
        end
    end
    return CountsFingerprint(counts)
end

local function DiscoveryFingerprint(raw, catalog)
    if raw == nil then return "nil" end
    if type(raw) ~= "table" then return nil, "discovery:not-table" end
    local discovered = {}
    for key, marker in pairs(raw) do
        local spellId
        if type(key) == "number" then
            spellId = key
        elseif type(key) == "string" and key:match("^[1-9][0-9]*$") then
            spellId = tonumber(key)
        end
        if not FiniteNumber(spellId) or spellId <= 0
            or spellId ~= math.floor(spellId)
            or (type(marker) == "boolean" and marker ~= true)
            or (type(marker) ~= "boolean" and not FiniteNumber(marker)) then
            return nil, "discovery:key"
        end
        if type(catalog) == "table" and type(catalog.rows) == "table"
            and catalog.rows[spellId] then
            if discovered[spellId] then return nil, "discovery:duplicate" end
            discovered[spellId] = 1
        end
    end
    return CountsFingerprint(discovered)
end

local function DisabledFingerprint(svc, catalog)
    if not (type(catalog) == "table" and type(catalog.levers) == "table") then
        return "unavailable"
    end
    if not (svc and type(svc.IsTomeEchoDisabled) == "function") then
        return nil, "disabled:unavailable"
    end
    local disabled = {}
    for lever, row in pairs(catalog.levers) do
        local leverId = tonumber(lever)
        if not IntegerAtLeast(leverId, 1) or type(row) ~= "table"
            or type(row.members) ~= "table" then
            return nil, "disabled:lever"
        end
        for i = 1, #row.members do
            local spellId = tonumber(row.members[i])
            if not IntegerAtLeast(spellId, 1) then return nil, "disabled:member" end
            local ok, value = pcall(svc.IsTomeEchoDisabled, spellId)
            if not ok then return nil, "disabled:read" end
            if type(value) ~= "boolean" then return nil, "disabled:value" end
            if value then disabled[leverId] = 1; break end
        end
    end
    return CountsFingerprint(disabled)
end

local function ServiceRead(svc, name, optional)
    local fn = svc and svc[name]
    if type(fn) ~= "function" then
        if optional then return true, nil end
        return false, nil, name .. ":unavailable"
    end
    local ok, value = pcall(fn)
    if not ok then return false, nil, name .. ":error" end
    return true, value
end

local function CaptureEchoSnapshot()
    local svc = PS()
    if not svc then
        return {
            slots="unavailable", granted="unavailable", locked="unavailable",
            discovery="unavailable", activeSlot=0,
        }, 0
    end
    local okSlots, rawSlots, slotsError = ServiceRead(svc, "GetServerBuildSlots")
    local okMax, maxSlots, maxError = ServiceRead(svc, "GetServerMaxSlots", true)
    local okActive, activeSlot, activeError = ServiceRead(svc, "GetServerActiveSlot")
    local okGranted, granted, grantedError = ServiceRead(svc, "GetGrantedPerks")
    local okLocked, locked, lockedError = ServiceRead(svc, "GetLockedPerks")
    local okDiscovered, discovered, discoveredError =
        ServiceRead(svc, "GetDiscoveredEchoes")
    if not (okSlots and okMax and okActive and okGranted and okLocked
        and okDiscovered) then
        return nil, nil, slotsError or maxError or activeError
            or grantedError or lockedError or discoveredError
    end
    maxSlots = maxSlots == nil and 5 or tonumber(maxSlots)
    activeSlot = activeSlot == nil and 0 or tonumber(activeSlot)
    if not IntegerAtLeast(maxSlots, 1) or not IntegerAtLeast(activeSlot, 0) then
        return nil, nil, "echo:scalar"
    end
    local okCatalog, catalog = pcall(A.Catalog)
    if not okCatalog then return nil, nil, "disabled:catalog" end
    local slotsSig, slotsSigError = SlotsFingerprint(rawSlots, maxSlots)
    local grantedSig, grantedSigError = GrantedFingerprint(granted, catalog)
    local lockedSig, lockedSigError = LockedFingerprint(locked)
    local discoveredSig, discoveredSigError =
        DiscoveryFingerprint(discovered, catalog)
    local disabledSig, disabledSigError = DisabledFingerprint(svc, catalog)
    if not (slotsSig and grantedSig and lockedSig and discoveredSig
        and disabledSig) then
        return nil, nil, slotsSigError or grantedSigError or lockedSigError
            or discoveredSigError or disabledSigError or "echo:malformed"
    end
    return {
        slots=slotsSig,
        granted=grantedSig,
        locked=lockedSig,
        discovery=discoveredSig .. "|" .. disabledSig,
        activeSlot=activeSlot,
    }, activeSlot
end

local function RefreshEchoAssociations()
    if Nexus.JournalTab and Nexus.JournalTab.RefreshAssociations then
        echoStatus.associationRefreshes = echoStatus.associationRefreshes + 1
        pcall(Nexus.JournalTab.RefreshAssociations)
    end
end

local function ReconcileEchoState(markDirty, source)
    local hadPending = echoNotificationPending
    echoNotificationPending = false
    echoStatus.reconciliations = echoStatus.reconciliations + 1
    local now = GetTime and GetTime() or 0
    if not markDirty and not hadPending and echoSnapshot
        and echoVerifiedAt == now then
        echoStatus.cacheHits = echoStatus.cacheHits + 1
        echoStatus.equivalentFallbacks = echoStatus.equivalentFallbacks + 1
        EchoReason(tostring(source or "reconcile") .. ":cached")
        return true, false
    end
    echoStatus.scans = echoStatus.scans + 1
    local ok, snapshot, activeSlot, failure = pcall(CaptureEchoSnapshot)
    if not ok then
        failure, snapshot = snapshot, nil
    end
    if type(snapshot) ~= "table" then
        echoStatus.failures = echoStatus.failures + 1
        EchoReason("failure:" .. tostring(failure or "capture"))
        return false, false
    end
    if not echoSnapshot then
        echoSnapshot, echoActiveSlot = snapshot, activeSlot or 0
        echoVerifiedAt = now
        EchoReason(tostring(source or "baseline") .. ":baseline")
        return true, false
    end

    local changed, changedNames = {}, {}
    for _, field in ipairs(ECHO_FIELDS) do
        if echoSnapshot[field] ~= snapshot[field] then
            changed[field] = true
            changedNames[#changedNames + 1] = field
            echoGenerations[field] = echoGenerations[field] + 1
            echoStatus.fieldChanges[field] = echoStatus.fieldChanges[field] + 1
        end
    end
    echoSnapshot, echoActiveSlot = snapshot, activeSlot or 0
    echoVerifiedAt = now
    if #changedNames == 0 then
        if source == "notification" then
            echoStatus.equivalentNotifications =
                echoStatus.equivalentNotifications + 1
        else
            echoStatus.equivalentFallbacks = echoStatus.equivalentFallbacks + 1
        end
        EchoReason(tostring(source or "reconcile") .. ":equivalent")
        return true, false
    end

    echoStatus.semanticChanges = echoStatus.semanticChanges + 1
    if markDirty then
        if changed.slots or changed.activeSlot then
            slotsDirty = true
            echoStatus.dirtyReasons.slots = echoStatus.dirtyReasons.slots + 1
        end
        if changed.granted or changed.locked or changed.discovery then
            dataDirty = true
            echoStatus.dirtyReasons.data = echoStatus.dirtyReasons.data + 1
        end
    end
    if changed.slots then RefreshWishlistEvidenceTransitions() end
    if changed.slots or changed.activeSlot then RefreshEchoAssociations() end
    EchoReason(tostring(source or "reconcile") .. ":" .. table.concat(changedNames, ","))
    return true, true
end

local function ReconcilePendingEchoState()
    if echoNotificationPending then
        return ReconcileEchoState(true, "notification")
    end
    return true, false
end

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
    local pe = PE()
    if not pe then return end
    if pe.PerkUI and type(pe.PerkUI.Show) == "function"
        and not uiHooksInstalled.Show then
        hooksecurefunc(pe.PerkUI, "Show", function()
            pcall(function()
                projectionStatus.board.notifications =
                    projectionStatus.board.notifications + 1
                boardNotificationPending = true
            end)
        end)
        uiHooksInstalled.Show = true
    end
    if pe.PerkUI and type(pe.PerkUI.UpdateSinglePerk) == "function"
        and not uiHooksInstalled.UpdateSinglePerk then
        hooksecurefunc(pe.PerkUI, "UpdateSinglePerk", function()
            pcall(function()
                projectionStatus.board.notifications =
                    projectionStatus.board.notifications + 1
                boardNotificationPending = true
            end)
        end)
        uiHooksInstalled.UpdateSinglePerk = true
    end
    if pe.EchoJournal and type(pe.EchoJournal.OnDataChanged) == "function"
        and not uiHooksInstalled.OnDataChanged then
        hooksecurefunc(pe.EchoJournal, "OnDataChanged", function()
            pcall(function()
                echoStatus.notifications = echoStatus.notifications + 1
                echoNotificationPending = true
            end)
        end)
        uiHooksInstalled.OnDataChanged = true
    end
    local svc = PS()
    if not svc then return end
    if type(svc.SelectPerk) == "function"
        and not serviceHooksInstalled.SelectPerk then
        hooksecurefunc(svc, "SelectPerk", function(arg1)
            pcall(function()
                boardDirty = true
                if not selfCalling and not inFlightKind then
                    externalActionSeen = true
                    ownedProjectionRevision = ownedProjectionRevision + 1
                    A._lastUserAction = { kind = "SelectPerk",
                        arg = tonumber(arg1), t = GetTime() }
                end
            end)
        end)
        serviceHooksInstalled.SelectPerk = true
    end
    if type(svc.BanishPerk) == "function"
        and not serviceHooksInstalled.BanishPerk then
        hooksecurefunc(svc, "BanishPerk", function(arg1)
            pcall(function()
                boardDirty = true
                if not selfCalling and not inFlightKind then
                    externalActionSeen = true
                    A._lastUserAction = { kind = "BanishPerk",
                        arg = tonumber(arg1), t = GetTime() }
                end
            end)
        end)
        serviceHooksInstalled.BanishPerk = true
    end
    if type(svc.FreezePerk) == "function"
        and not serviceHooksInstalled.FreezePerk then
        hooksecurefunc(svc, "FreezePerk", function(arg1)
            pcall(function()
                boardDirty = true
                if not selfCalling and not inFlightKind then
                    externalActionSeen = true
                    A._lastUserAction = { kind = "FreezePerk",
                        arg = tonumber(arg1), t = GetTime() }
                end
            end)
        end)
        serviceHooksInstalled.FreezePerk = true
    end
    if type(svc.RequestReroll) == "function"
        and not serviceHooksInstalled.RequestReroll then
        hooksecurefunc(svc, "RequestReroll", function()
            pcall(function()
                boardDirty = true
                if not selfCalling and not inFlightKind then
                    externalActionSeen = true
                    A._lastUserAction = { kind = "RequestReroll",
                        t = GetTime() }
                end
            end)
        end)
        serviceHooksInstalled.RequestReroll = true
    end
end

function A.ConsumeDirty()
    local b, s, d, static = boardDirty, slotsDirty, dataDirty, staticDirty
    local levelEvents = levelBurstStatus.pending
    if b then
        local svc = PS()
        local signature = BoardFingerprint(
            svc and SafeCall(svc.GetCurrentChoice))
        if signature ~= nil then lastBoardSig = signature end
    end
    -- A failure above leaves the pending burst intact for the next pump. Only
    -- a fully successful consume acknowledges it and publishes the current
    -- authoritative level snapshot.
    if levelEvents > 0 then
        local observedLevel = tonumber(A.Level()) or 0
        levelBurstStatus.pending = 0
        levelBurstStatus.lastLevel = observedLevel
    end
    boardDirty, slotsDirty, dataDirty, staticDirty = false, false, false, false
    -- Trailing scalar revisions are consumed only by AutomationRuntime. They
    -- keep the established three dirty returns intact and allocate no table on
    -- the direct 0.2-second poll path.
    return b, s, d, nil,
        echoGenerations.slots, echoGenerations.activeSlot,
        echoGenerations.granted, ownedProjectionRevision,
        echoGenerations.locked, lockedProjectionRevision,
        echoGenerations.discovery, leverProjectionRevision,
        static, levelEvents, levelBurstStatus.runBoundaryGeneration
end

function A.RecordLevelBurstPump(eventCount, recomputes, renders, actions)
    eventCount = math.max(0, math.floor(tonumber(eventCount) or 0))
    if eventCount == 0 then return false end
    recomputes = math.max(0, math.floor(tonumber(recomputes) or 0))
    renders = math.max(0, math.floor(tonumber(renders) or 0))
    actions = math.max(0, math.floor(tonumber(actions) or 0))
    local work = recomputes + renders + actions
    levelBurstStatus.pumps = levelBurstStatus.pumps + 1
    levelBurstStatus.recomputes = levelBurstStatus.recomputes + recomputes
    levelBurstStatus.renders = levelBurstStatus.renders + renders
    levelBurstStatus.actions = levelBurstStatus.actions + actions
    levelBurstStatus.lastEvents = eventCount
    levelBurstStatus.lastWorkPerPump = work
    if work > levelBurstStatus.maxWorkPerPump then
        levelBurstStatus.maxWorkPerPump = work
    end
    return true
end

function A.LevelBurstStats()
    return {
        events=levelBurstStatus.events,
        bursts=levelBurstStatus.bursts,
        coalesced=levelBurstStatus.coalesced,
        pending=levelBurstStatus.pending,
        queueHighWater=levelBurstStatus.queueHighWater,
        pumps=levelBurstStatus.pumps,
        recomputes=levelBurstStatus.recomputes,
        renders=levelBurstStatus.renders,
        actions=levelBurstStatus.actions,
        lastEvents=levelBurstStatus.lastEvents,
        lastLevel=levelBurstStatus.lastLevel,
        lastWorkPerPump=levelBurstStatus.lastWorkPerPump,
        maxWorkPerPump=levelBurstStatus.maxWorkPerPump,
        runBoundaryArmed=levelBurstStatus.runBoundaryArmed,
        runBoundaryGeneration=levelBurstStatus.runBoundaryGeneration,
    }
end

function A.TomeMutationResumeAt()
    local now = GetTime and GetTime() or 0
    return tomeMutationPausedUntil > now and tomeMutationPausedUntil or nil
end

function A.EchoReconcileStats()
    local out = {
        slotRequests=echoStatus.slotRequests,
        notifications=echoStatus.notifications,
        reconciliations=echoStatus.reconciliations,
        scans=echoStatus.scans,
        cacheHits=echoStatus.cacheHits,
        equivalentNotifications=echoStatus.equivalentNotifications,
        equivalentFallbacks=echoStatus.equivalentFallbacks,
        semanticChanges=echoStatus.semanticChanges,
        failures=echoStatus.failures,
        associationRefreshes=echoStatus.associationRefreshes,
        lastReason=echoStatus.lastReason,
        generations={},fieldChanges={},dirtyReasons={},projections={},
    }
    for _, field in ipairs(ECHO_FIELDS) do
        out.generations[field] = echoGenerations[field]
        out.fieldChanges[field] = echoStatus.fieldChanges[field]
    end
    out.dirtyReasons.slots = echoStatus.dirtyReasons.slots
    out.dirtyReasons.data = echoStatus.dirtyReasons.data
    for name, source in pairs(projectionStatus) do
        local copy = {}
        for field, value in pairs(source) do copy[field] = value end
        out.projections[name] = copy
    end
    return out
end

-- Allocation-free semantic revisions for the Wishlist overlay. These expose
-- only bounded scalar generations; the overlay still acquires all represented
-- data through the established defensive GameAdapter getters.
function A.PresentationRevisions()
    local catalogRevision = catalogStatus.rebuilds or 0
    local revisions = Nexus and Nexus.Revisions
    if revisions and type(revisions.Get) == "function" then
        catalogRevision = revisions.Get(revisions.CATALOG_CHANGED)
            or catalogRevision
    end
    return echoGenerations.slots, echoGenerations.activeSlot,
        echoGenerations.granted, ownedProjectionRevision,
        wishlistProjectionRevision, catalogRevision,
        echoGenerations.locked, lockedProjectionRevision,
        echoGenerations.discovery, leverProjectionRevision,
        (A.Level() <= 1) and 1 or 0
end

-- The fallback calls this only every five seconds (and when a real full step
-- captures its new baseline). It may therefore perform a complete semantic
-- verification without adding that work to the direct 0.2-second Poll path.
function A.AutomationSignature()
    local svc = PS()
    local echoOk = ReconcileEchoState(false, "fallback")
    if not echoOk then return nil end
    local state = Store and Store.State and Store.State() or nil
    local settings = Store and Store.Settings and Store.Settings() or nil
    local associations = type(state) == "table" and state.loadoutWishlists or nil
    return {
        service=svc,
        level=UnitLevel and UnitLevel("player") or 0,
        slots=echoGenerations.slots,
        activeSlot=echoGenerations.activeSlot,
        granted=echoGenerations.granted,
        locked=echoGenerations.locked,
        discovery=echoGenerations.discovery,
        tomeSafety=(EchoTomeInBags() or VisibleBindConfirmation())
            and true or false,
        state=state,
        settings=settings,
        associations=associations,
        association=type(associations) == "table"
            and associations[echoActiveSlot] or nil,
        firstRun=type(state) == "table" and state.firstRunWishlist or nil,
    }
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
    ReconcileEchoState(false, "init")
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
        ObserveRunBoundary()
        InstallHooks()
        A.RequestGranted()
        boardDirty, slotsDirty = true, true
    elseif event == "PLAYER_LEVEL_UP" then
        ObserveRunBoundary()
        levelBurstStatus.events = levelBurstStatus.events + 1
        if levelBurstStatus.pending == 0 then
            levelBurstStatus.bursts = levelBurstStatus.bursts + 1
        else
            levelBurstStatus.coalesced = levelBurstStatus.coalesced + 1
        end
        levelBurstStatus.pending = levelBurstStatus.pending + 1
        if levelBurstStatus.pending > levelBurstStatus.queueHighWater then
            levelBurstStatus.queueHighWater = levelBurstStatus.pending
        end
        boardDirty = true
    end
end

-- Main drives this from its OnUpdate (~0.2s cadence)
function A.Poll()
    ObserveRunBoundary()
    InstallHooks()
    ReconcilePendingBoardState()
    ReconcilePendingEchoState()
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
            slotsRefreshAt = GetTime() + 5
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
    -- RequestServerBuildSlots may synchronously invoke the hooked reply path.
    -- Consume that one pending bit now so an equivalent reply settles within
    -- the same Poll while an asynchronous reply waits for the next Poll.
    ReconcilePendingEchoState()
end
