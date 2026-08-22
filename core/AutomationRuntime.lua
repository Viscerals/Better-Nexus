-- Nexus: core/AutomationRuntime.lua
-- Stateful automation FSM, deadlines, direct poll cadence, and trace owner.

Nexus = Nexus or {}
if type(Nexus.MainInternals) ~= "table" then Nexus.MainInternals = {} end

local AutomationRuntime = {}
Nexus.MainInternals.AutomationRuntime = AutomationRuntime

function AutomationRuntime.New(options)
    options = options or {}
    local Nexus = assert(options.nexus, "AutomationRuntime requires Nexus")
    local Model = assert(options.model, "AutomationRuntime requires Model")
    local Policy = assert(options.policy, "AutomationRuntime requires Policy")
    local Ratchet = assert(options.ratchet, "AutomationRuntime requires Ratchet")
    local Strategy = assert(options.strategy, "AutomationRuntime requires Strategy")
    local Store = assert(options.store, "AutomationRuntime requires Store")
    local Adapter = assert(options.adapter, "AutomationRuntime requires GameAdapter")
    local Readout = assert(options.readout, "AutomationRuntime requires Readout")
    local DefaultProfile = assert(options.defaultProfile,
        "AutomationRuntime requires DefaultProfile")
    local ViewModel = assert(options.viewModel,
        "AutomationRuntime requires MainViewModel")
    assert(options.wishlistModel,
        "AutomationRuntime requires WishlistModel")
    local RenderPanel = assert(options.renderPanel,
        "AutomationRuntime requires renderPanel")
    local RenderIdlePanel = assert(options.renderIdlePanel,
        "AutomationRuntime requires renderIdlePanel")
    local BuildProgress = assert(options.buildProgress,
        "AutomationRuntime requires buildProgress")
    local BuildPanelProgress = assert(options.buildPanelProgress,
        "AutomationRuntime requires buildPanelProgress")
    local AppendAudit = assert(options.appendAudit,
        "AutomationRuntime requires appendAudit")
    local AppendAutoLockEvent = assert(options.appendAutoLockEvent,
        "AutomationRuntime requires appendAutoLockEvent")
    local Print = assert(options.print, "AutomationRuntime requires print")
    local RecordError = assert(options.recordError,
        "AutomationRuntime requires recordError")
    local GetTime = assert(options.now, "AutomationRuntime requires clock")
    local ActiveSlotRow = function(slots) return ViewModel.ActiveSlotRow(slots) end

local autoEnabled = false          -- session-level master switch (panel button / slash)
local quickStartChecked = false   -- one-time-per-session guard for the quick-start check
local pollAccum = 0
local POLL = 0.2
local FALLBACK_RECOMPUTE = 5
local nextStepAt = nil
local nextAutoLockAt = nil
local lastFullStepAt = -math.huge
local lastStaticProbeAt = -math.huge
local lastFallbackCheckAt = -math.huge
local fallbackSignature = nil
local forceStep = true
local authorizationStepPending = false
local staticInvalidated = true
local staticCache = nil
local staticProbeInProgress = false
local catalogRevisionUnsubscribe = nil
local recomputeStats = {
    polls=0, fullSteps=0, skipped=0, dirty=0,
    deadlines=0, fallbacks=0, fallbackChecks=0, fallbackRepairs=0,
    forced=0, explicit=0,
    planCompiles=0,planReuses=0,staticProbes=0,
    wishlistFingerprints=0,lockContextRebuilds=0,
    autoLockEvaluations=0,pollFailures=0,
    stepAttempts=0,stepFailures=0,stepRetries=0,stepRetryExhausted=0,
}
local fullStepTriggers = {
    forced=0, dirty=0, deadlines=0, fallbacks=0, explicit=0, other=0,
}
local PHASE_PATHS = {
    static="automation.phase.static",
    catalog="automation.phase.catalog",
    wishlist="automation.phase.wishlist",
    wishlistFingerprint="automation.phase.wishlist-fingerprint",
    plan="automation.phase.plan",
    slots="automation.phase.slots",
    owned="automation.phase.owned",
    levers="automation.phase.levers",
    board="automation.phase.board",
    boardPrepare="automation.phase.board-prepare",
    policy="automation.phase.policy",
    autoLock="automation.phase.autolock",
    preauthorize="automation.phase.preauthorize",
    overlayPrepare="automation.phase.overlay-prepare",
    overlayRender="automation.phase.overlay-render",
}
local phaseCounts = {}
for name in pairs(PHASE_PATHS) do phaseCounts[name] = 0 end
local lastStepContext = {
    trigger="none",dirtyMask=0,staticProbe=false,forceCompile=false,
    autoLockDue=false,fallbackComponent="none",staticRevisionBefore=0,
    staticRevisionAfter=0,planCompiled=false,planReused=false,
    boardPresent=false,actionAttempted=false,actionType="none",
    syncWindowClass="not-observed",outcome="not-run",retainedScalarFields=16,
}
local stepRetry = {
    pending=false,trigger="other",dirtyMask=0,fallbackComponent=nil,
    staticProbe=false,forceCompile=false,autoLockDue=false,
    runBoundaryGeneration=0,levelEvents=0,
}

local function MeasurePhase(name, callback, ...)
    phaseCounts[name] = phaseCounts[name] + 1
    local performance = Nexus and Nexus.Performance
    if performance and type(performance.Measure) == "function" then
        return performance.Measure(PHASE_PATHS[name], callback, ...)
    end
    return callback(...)
end

local function BeginPhase(name)
    phaseCounts[name] = phaseCounts[name] + 1
    local performance = Nexus and Nexus.Performance
    if performance and type(performance.Begin) == "function" then
        local ok, startedAt = pcall(performance.Begin, PHASE_PATHS[name])
        if ok then return performance, startedAt end
    end
    return nil, nil
end

local function FinishPhase(performance, name, startedAt)
    if performance and startedAt and type(performance.Finish) == "function" then
        pcall(performance.Finish, PHASE_PATHS[name], startedAt)
    end
end

local SAFE_ACTION_TYPES = {
    take=true,banish=true,freeze=true,reroll=true,wait=true,
}
local SAFE_TRIGGERS = {
    forced=true,dirty=true,deadlines=true,fallbacks=true,explicit=true,
    other=true,
}
local SAFE_FALLBACK_COMPONENTS = {
    none=true,signature=true,service=true,level=true,slots=true,
    activeSlot=true,granted=true,locked=true,discovery=true,
    tomeSafety=true,state=true,settings=true,associations=true,
    association=true,firstRun=true,catalogRevision=true,
}
local function ControlledToken(value, allowed, fallback)
    value = tostring(value or fallback)
    return allowed[value] and value or fallback
end
local function MarkActionAttempt(actionType)
    lastStepContext.actionAttempted = true
    lastStepContext.actionType = SAFE_ACTION_TYPES[actionType]
        and actionType or "other"
end

-- GameAdapter publishes allocation-free scalar generations with ConsumeDirty.
-- Cache only the defensive projections returned by the adapter; Project
-- Ebonhold I/O and normalization remain adapter-owned. A missing generation
-- contract (tests/older injected adapters) disables reuse and preserves the
-- prior call behavior.
local projectionRevisions = {
    valid=false,slots=0,activeSlot=0,granted=0,owned=0,
    locked=0,lockedLocal=0,discovery=0,levers=0,
}
local projectionCache = {
    slots={set=false},owned={set=false},
    locked={set=false},levers={set=false},
}

local function ClearProjectionCache()
    for _, row in pairs(projectionCache) do
        row.set, row.value = false, nil
    end
end

local function UpdateProjectionRevisions(slots, activeSlot, granted, owned,
    locked, lockedLocal, discovery, levers)
    local valid = type(slots) == "number"
        and type(activeSlot) == "number"
        and type(granted) == "number" and type(owned) == "number"
        and type(locked) == "number" and type(lockedLocal) == "number"
        and type(discovery) == "number" and type(levers) == "number"
    if not valid then
        if projectionRevisions.valid then ClearProjectionCache() end
        projectionRevisions.valid = false
        return
    end
    projectionRevisions.valid = true
    projectionRevisions.slots, projectionRevisions.activeSlot = slots, activeSlot
    projectionRevisions.granted, projectionRevisions.owned = granted, owned
    projectionRevisions.locked, projectionRevisions.lockedLocal = locked, lockedLocal
    projectionRevisions.discovery, projectionRevisions.levers = discovery, levers
end

local function ReadProjection(name, catalogRevision, level, callback)
    if not projectionRevisions.valid then
        if PHASE_PATHS[name] then return MeasurePhase(name, callback) end
        return callback()
    end
    local first, second
    if name == "slots" then
        first, second = projectionRevisions.slots,
            projectionRevisions.activeSlot
    elseif name == "owned" then
        first, second = projectionRevisions.granted,
            projectionRevisions.owned
    elseif name == "locked" then
        first, second = projectionRevisions.locked,
            projectionRevisions.lockedLocal
    else
        first, second = projectionRevisions.discovery,
            projectionRevisions.levers
    end
    local cached = projectionCache[name]
    -- Only Owned's dead-run ghost filter depends on level, and only at the
    -- level-one boundary. Slots, permanent locks, and lever state are level
    -- independent; ordinary progress must not invalidate their projections.
    local levelKey = name == "owned" and ((tonumber(level) or 0) <= 1 and 1 or 0)
        or 0
    if cached.set and cached.first == first and cached.second == second
        and cached.catalogRevision == catalogRevision
        and cached.levelKey == levelKey then
        return cached.value
    end
    local value
    if PHASE_PATHS[name] then value = MeasurePhase(name, callback)
    else value = callback() end
    cached.set, cached.value = true, value
    cached.first, cached.second = first, second
    cached.catalogRevision = catalogRevision
    cached.levelKey = levelKey
    return value
end

local armAttempts, armedConfirmed, armPendingSince = 0, false, nil
local armTargetSlot = nil
local boardsSinceArm = 0
local leversDoneThisVisit = {}
local lastLeverSendAt = 0

-- RUN state
local lastDecision = nil
local actionIntent = nil
local actionDecisionRevision = 0
local ACTION_INTENT_BEAT = 0.4
local ACTION_CONFIRM_TIMEOUT = 10
local actionLifecycleStats = {
    prepared=0,submitted=0,confirmed=0,rejected=0,
    uncertain=0,expired=0,superseded=0,preauthFailed=0,
}
local lastActionLifecycle = {
    state="idle",actionType="none",reason="none",decisionRevision=0,
    mutationAttempted=false,preparedAt=0,submittedAt=0,resolvedAt=0,
}
-- AutoLock uses this same direct runtime owner, but its server reply is a
-- separate eventually-consistent locked projection. One accepted adapter
-- submission is allowed per exact identity/lifetime; a short spacing refusal
-- may be retried once without extending that lifetime.
local AUTO_LOCK_STATE_VERSION = 1
local AUTO_LOCK_CONFIRM_TIMEOUT = 10
local AUTO_LOCK_MAX_ADAPTER_ATTEMPTS = 2
local autoLockLifecycleStats = {
    prepared=0,submitted=0,awaitingConfirmation=0,confirmed=0,
    rejected=0,expired=0,superseded=0,spacingRetries=0,
    explicitRetries=0,postExpiryBlocked=0,
}
local lastAutoLockLifecycle = {
    state="idle",reason="none",error="none",spellId=0,replaces=0,
    lockedRevision=0,adapterAttempts=0,preparedAt=0,submittedAt=0,
    expiresAt=0,resolvedAt=0,
}
local lastAutoLockCapacity = {
    used=0,maximum=0,known=false,source="unavailable",synced=false,
}
local lastLoggedSig = nil        -- decision-log dedupe per board
local lastBoardForRerollWatch = nil
-- Test 13 bracket-fishing budget. These counters are session/run-local and
-- deliberately reset as the guaranteed spell or eligibility bracket changes.
local fillerFishState = {
    guaranteedId = nil,
    consecutive = 0,
    bracket = nil,
    bracketSpent = 0,
}
-- Test 15: per-spell count of FORCED takes this run (Policy.lua's
-- mandatory-select branch, `forced = true` -- zero legal alternatives that
-- board). Fed into Ratchet.Dominates so the save gate weighs an unavoidable
-- duplicate/wrong-quality pick far more lightly than a voluntary one.
-- Reset at the same run boundary as fillerFishState (level == 1, below).
local forcedTakesBySpell = {}
local frozeThisBoard = nil       -- board signature we already spent a freeze on
local refusedBanishSig = nil
local refusedRerollSig = nil
local externalPauseUntil = 0

-- SAVE state
local savedThisVisit = false
local slotsRefreshAt = nil
local saveVerifySlot, saveVerifyAt, seedVerify, saveVerifySnap = nil, nil, nil, nil
local saveVerifyExpectedActive, saveVerifySummary, saveVerifyName = nil, nil, nil
local saveObserveSchedule = { 0.5, 1, 2, 4, 8, 15, 30 }
local saveObserveIndex, saveObserveReadyAt = 1, nil
local noChangeReportedVisit = false
local saveGateAuditedVisit = false
local auditRunId = 0
local auditRunStarted = nil
local lastLevelSeen = nil
local lastRunBoundaryGeneration = 0
local demotionsClearedThisSession = false

local statusLine = "loading"

    local function SetStatus(value)
        if value ~= statusLine then
            statusLine = value
            if type(options.onStatus) == "function" then
                pcall(options.onStatus, value)
            end
        end
    end

    local function RequestStepAt(when)
        when = tonumber(when)
        if not when or when ~= when or when >= math.huge or when <= -math.huge then
            return false
        end
        if not nextStepAt or when < nextStepAt then nextStepAt = when end
        return true
    end

    local function RequestAutoLockAt(when)
        when = tonumber(when)
        if not when or when ~= when or when >= math.huge
            or when <= -math.huge then return false end
        if not nextAutoLockAt or when < nextAutoLockAt then
            nextAutoLockAt = when
        end
        return RequestStepAt(when)
    end

    local function RequestRecompute()
        forceStep = true
        staticInvalidated = true
        return true
    end

local function CopyCounts(src)
    local out = {}
    if type(src) == "table" then
        for fam, n in pairs(src) do
            n = tonumber(n) or 0
            if n ~= 0 then out[tostring(fam)] = n end
        end
    end
    return out
end

local function WishedCounts(counts, plan)
    local out = {}
    local wished = type(plan) == "table" and plan.wishedFamilies or nil
    if type(counts) == "table" and type(wished) == "table" then
        for fam in pairs(wished) do
            local n = tonumber(counts[fam]) or tonumber(counts[tostring(fam)]) or 0
            if n ~= 0 then out[tostring(fam)] = n end
        end
    end
    return out
end

local function EffectiveFlags()
    local flags = {}
    for k, v in pairs(DefaultProfile.defaultFlags or {}) do flags[k] = v end
    local st = Store.State()
    for k in pairs(st.flagDemotions or {}) do flags[k] = false end
    return flags
end

local function DemoteFlag(name, reason)
    local st = Store.State()
    st.flagDemotions = st.flagDemotions or {}
    if not st.flagDemotions[name] then
        st.flagDemotions[name] = reason
        -- Log internally; this is an advisor-mode state change that players
        -- don't need to see in chat.
    end
end

------------------------------------------------------------------------
-- One FSM step (the whole loop; called from OnUpdate at POLL cadence)
------------------------------------------------------------------------

local function AutoAllowed()
    if not autoEnabled then return false, "manual mode" end
    if GetTime() < externalPauseUntil then return false, "user acting" end
    if Adapter.RivalDetected() then return false, "EchoOptimizer loaded -- disable it" end
    if Adapter.AutoAcceptOn() then return false, "client auto-accept re-enabled" end
    return true
end

-- Wishlist progress for this run: how many wished FAMILIES are owned, and
-- how many total, family-granular (same identity rule as everything else
-- -- addendum B2). Pure; malformed plan/owned degrades to 0/0.
-- This run's progress toward the wishlist's total STACK target (the
-- "79" number) -- not a family-boolean count. A family sitting at 1 of
-- 9 needed copies contributes only 1 toward the total, not a full
-- credit; "missing" lists anything not yet at its FULL target, whether
-- that's zero copies or a partial stack still short.

-- Locked-slot designs are per-WISHLIST, not one global set -- different
-- Saved Builds/wishlists want different permanent Echoes locked in, and a
-- single shared table meant switching wishlists left the previous one's
-- designs bleeding into the new one's STILL NEEDED/TO LOCK/automation
-- (reported live: designs showing "some I need and some I don't" after
-- switching wishlists).
--
-- Identity is Adapter.WishlistKey(entries) -- a content fingerprint
-- (spellId:stacks pairs, sorted), NOT wl.slot (the server's designed-slot
-- NUMBER, tried first in Dev Test 42-49). Slot number turned out to be
-- unstable across a delete+recreate: the server reuses a freed slot number
-- for the next wishlist created, so a deleted wishlist's locked-Echo design
-- bled into a brand-new, unrelated wishlist that happened to land on that
-- same now-freed number (confirmed live). Content fingerprint has no such
-- reuse hazard -- a genuinely different wishlist can't collide with one
-- unless its 79 Echoes happen to be byte-identical, which is a far more
-- benign case to share a bucket over. A wishlist with no Echoes yet (a
-- brand-new, still-empty draft) shares bucket 0.
local function LockSlotKey(wishlist, knownKey)
    if knownKey ~= nil then return knownKey end
    local echoes = type(wishlist) == "table" and (wishlist.entries or wishlist.echoes) or nil
    recomputeStats.wishlistFingerprints =
        recomputeStats.wishlistFingerprints + 1
    return (Adapter and Adapter.WishlistKey and Adapter.WishlistKey(echoes)) or 0
end

-- NexusDB is ACCOUNT-WIDE (## SavedVariables has no "PerCharacter"), same as
-- every other addon's plain SavedVariables -- a Dev Test 42-47 bucket keyed
-- ONLY by wl.slot collided across different characters on the same account
-- whenever two characters happened to have a wishlist at the same server
-- slot number (reported live: a design from "my other character" showing up
-- on a brand-new wishlist here). Store.State() is this codebase's existing,
-- realm-qualified per-character subtable (NexusDB.chars[name@realm], with
-- transient-only handling until both identity parts are ready) -- nesting the per-slot
-- buckets inside it, instead of at NexusDB's own top level, makes this
-- correctly per-character for free.
--
-- One-time, self-guarding migration: `lockDesignTargets` (Dev Test 37-41)
-- was a single flat, account-wide, ALSO cross-character table. Move
-- whatever's in it into the CURRENTLY ACTIVE wishlist's own per-character
-- bucket (the best available guess for what it was designed against -- and
-- for THIS character specifically, unlike the account-wide bucket it came
-- from) and retire the flat key permanently. The Dev Test 42-47 account-wide
-- lockDesignTargetsBySlot bucket is deliberately NOT migrated forward -- its
-- contents can't be reliably attributed to any one character, so carrying it
-- over would just reintroduce the same cross-character bleed one more time.
-- It's left in place, orphaned and never read again.
local function LockDesignTargetsFor(wishlist, knownKey)
    local state = Store.State()
    if type(state) ~= "table" then return nil end
    local old = NexusDB and NexusDB.lockDesignTargets
    if type(old) == "table" then
        state.lockDesignTargetsBySlot = state.lockDesignTargetsBySlot or {}
        local key = LockSlotKey(wishlist, knownKey)
        if not state.lockDesignTargetsBySlot[key] then
            state.lockDesignTargetsBySlot[key] = old
        end
        NexusDB.lockDesignTargets = nil
    end
    local bySlot = state.lockDesignTargetsBySlot
    local key = LockSlotKey(wishlist, knownKey)
    -- Deliberately NOT promoting bucket 0 here the way WishlistEditor.lua's
    -- LoadPendingEchoes does (a wishlist saved for the first time commits
    -- its locks to bucket 0 until the server assigns it a real slot). This
    -- read fires every tick for whatever wishlist is CURRENTLY ACTIVE, which
    -- may be a completely different, unrelated wishlist than the one still
    -- waiting in bucket 0 for its slot to resolve -- promoting here could
    -- attribute a brand-new wishlist's designs to the wrong active one just
    -- because that one has no designs of its own yet. The editor's own
    -- promotion is safe because it only ever runs while THAT specific
    -- wishlist is the one being opened -- automation simply won't pursue a
    -- newly-created wishlist's locks until the player opens it in the
    -- editor at least once after saving, which also happens to be the
    -- moment its real slot resolves.
    return type(bySlot) == "table" and bySlot[key] or nil
end

local function WishlistProgress(plan, owned, catalog, lockOnlyFamilies, wishlist)
    local lockedOwned, designTargets
    if type(plan) == "table" and type(plan.wishedFamilies) == "table" then
        lockedOwned = Adapter and Adapter.LockedOwned and Adapter.LockedOwned()
        if wishlist == nil and staticCache then
            designTargets = staticCache.targets
        else
            designTargets = LockDesignTargetsFor(wishlist)
        end
    end
    return ViewModel.WishlistProgress(plan, owned, catalog, lockOnlyFamilies,
        lockedOwned, designTargets, wishlist)
end

local function LockTargetCopies(value, expectedSpellId)
    return options.wishlistModel.TargetCopies(value, expectedSpellId)
end

local function LockTargetReplacement(value)
    if type(value) == "table" then
        return type(value.replaces) == "number" and value.replaces or nil
    end
    return type(value) == "number" and value or nil
end

local function FamilyCountsFromEchoes(echoes, catalog)
    local out = {}
    for i = 1, #(echoes or {}) do
        local e = echoes[i]
        local fam = e and (e.family or (catalog and catalog.familyOf and catalog.familyOf[e.spellId]))
        if fam then out[fam] = (out[fam] or 0) + (tonumber(e.stacks) or 1) end
    end
    return out
end

-- Saved Build readback includes the current permanent locked Echoes in the
-- same row as the 79 rolled Echoes. When the same exact spell exists in both
-- places the server represents it once, not twice, so the post-save snapshot
-- is an exact-spell UNION (max count), not an addition. Building verification
-- from rolled ownership alone caused every successful save to look different
-- as soon as permanent locks existed.
local function CopyOwnedSnapshot(owned, locked, catalog)
    local snap = { byFamily = {}, bySpell = {} }
    -- Do not use CopyCounts here: it intentionally stringifies keys for
    -- diagnostics, while exact spell maps must retain numeric IDs so a rolled
    -- copy and a locked copy of the same Echo collapse into one max() entry.
    if type(owned) == "table" and type(owned.bySpell) == "table" then
        for id, n in pairs(owned.bySpell) do
            id, n = tonumber(id), tonumber(n)
            if id and n and n > 0 then snap.bySpell[id] = n end
        end
    end
    if type(locked) == "table" and type(locked.bySpell) == "table" then
        for id, n in pairs(locked.bySpell) do
            id, n = tonumber(id), tonumber(n)
            if id and n and n > 0 then
                local have = tonumber(snap.bySpell[id]) or 0
                if n > have then snap.bySpell[id] = n end
            end
        end
    end
    for id, n in pairs(snap.bySpell) do
        local fam = catalog and catalog.familyOf and catalog.familyOf[id]
        if fam then
            snap.byFamily[fam] = (snap.byFamily[fam] or 0) + n
        end
    end
    return snap
end

local function ExactEchoList(echoes, catalog)
    local exact = {}
    for i = 1, #(echoes or {}) do
        local e = echoes[i]
        local id = e and tonumber(e.spellId)
        local n = e and (tonumber(e.stacks or e.count) or 1)
        if id and n and n > 0 then
            exact[#exact + 1] = {
                id = id,
                fam = e.family or (catalog and catalog.familyOf and catalog.familyOf[id]),
                q = catalog and catalog.rows and catalog.rows[id]
                    and tonumber(catalog.rows[id].quality) or 0,
                n = n,
            }
        end
    end
    table.sort(exact, function(a, b) return a.id < b.id end)
    return exact
end

local function SpellCountsFromEchoes(echoes)
    local out = {}
    for i = 1, #(echoes or {}) do
        local e = echoes[i]
        local id = e and tonumber(e.spellId)
        local n = e and (tonumber(e.stacks or e.count) or 1)
        if id and n and n > 0 then out[id] = (out[id] or 0) + n end
    end
    return out
end

local function CountsEqual(a, b)
    a, b = type(a) == "table" and a or {}, type(b) == "table" and b or {}
    for k, n in pairs(a) do
        local have = tonumber(b[k]) or tonumber(b[tonumber(k)]) or 0
        if have ~= (tonumber(n) or 0) then return false end
    end
    for k, n in pairs(b) do
        local want = tonumber(a[k]) or tonumber(a[tostring(k)]) or 0
        if want ~= (tonumber(n) or 0) then return false end
    end
    return true
end

local function SlotMatchesSnapshot(row, snap, catalog)
    if type(row) ~= "table" or type(row.echoes) ~= "table"
        or type(snap) ~= "table" or type(snap.bySpell) ~= "table" then
        return false
    end
    return CountsEqual(SpellCountsFromEchoes(row.echoes), snap.bySpell)
end

local function ObserveAllSlots(slots, snap, catalog, elapsed)
    if type(slots) ~= "table" then return false end
    local exactMatch = false
    local maxSlots = tonumber(slots.maxSlots) or 0
    local unlocked = Adapter.UnlockedSlots and Adapter.UnlockedSlots() or maxSlots
    maxSlots = math.max(maxSlots, tonumber(unlocked) or 0)
    for slot = 1, maxSlots do
        local row = slots.bySlot and slots.bySlot[slot] or nil
        local family = row and FamilyCountsFromEchoes(row.echoes, catalog) or {}
        local exact = row and ExactEchoList(row.echoes, catalog) or {}
        local exactOk = row and SlotMatchesSnapshot(row, snap, catalog) or false
        local familyOk = row and CountsEqual(family, snap and snap.byFamily) or false
        if exactOk and tonumber(slot) == tonumber(saveVerifySlot) then exactMatch = true end
        AppendAudit("SAVE_OBSERVE", {
            level = Adapter.Level(), activeSlot = slots.activeSlot or 0,
            targetSlot = slot,
            result = exactOk and "EXACT_MATCH" or (familyOk and "FAMILY_MATCH" or (row and "DIFFERENT" or "EMPTY")),
            reason = string.format("+%.1fs requested=%s", tonumber(elapsed) or 0,
                tostring(saveVerifySlot or 0)),
            incumbent = family,
            candidate = snap and CopyCounts(snap.byFamily) or {},
            exact = exact,
        })
    end
    return exactMatch
end

-- Counted at EXACT spellId granularity, the same identity Ratchet.Dominates
-- uses to approve the save. Counting families here meant the gate and this
-- message could describe the same run in opposite terms: live 2026-08-02, a
-- run that shed three forced Uncommon siblings (Quick Hands, Vital Bond,
-- Ferocious Bond) and gained a real Rare Ferocious Bond was approved as "+1
-- exact progress" and announced as "loadout cleaned up — shed Quick Hands".
local function SaveChangeSummary(owned, incumbentEchoes, plan, catalog, diag)
    local before, lockedExact = {}, {}
    for i = 1, #(incumbentEchoes or {}) do
        local e = incumbentEchoes[i]
        local id = type(e) == "table" and tonumber(e.spellId) or nil
        if id then
            local n = math.max(1, tonumber(e.stacks or e.count or e.stack) or 1)
            before[id] = (before[id] or 0) + n
            -- Locked Echoes are deliberately excluded from `owned` (this run's
            -- rolled ownership -- GameAdapter.lua: "never part of the current
            -- run's rolled ownership"), but a normal Save() never touches
            -- locked slots at all: they persist into the post-save loadout
            -- untouched. Without folding them into `after` below, every
            -- wished-and-locked family reads as fully "shed" on every single
            -- save regardless of what happened.
            if e.locked then lockedExact[id] = (lockedExact[id] or 0) + n end
        end
    end
    local after = {}
    for id, n in pairs((owned and owned.bySpell) or {}) do
        after[id] = math.max(0, tonumber(n) or 0)
    end
    -- Saved Build rows are the rolled loadout UNION the locked Echoes; the
    -- server keeps one entry when a spell is both, so max(), never addition --
    -- identical to Ratchet.Dominates' candidatePostExact.
    for id, n in pairs(lockedExact) do
        if (tonumber(after[id]) or 0) < n then after[id] = n end
    end

    local wished = (plan and plan.wishedFamilies) or {}
    local targets = (plan and plan.targets) or {}
    local gained, shed = {}, {}
    local beforeProgress, afterProgress = 0, 0

    for fam in pairs(wished) do
        local famExact = Ratchet.TargetExact(targets[fam])
        local b = Ratchet.ExactCoverage(famExact, before)
        local a = Ratchet.ExactCoverage(famExact, after)
        beforeProgress = beforeProgress + b
        afterProgress = afterProgress + a
        local d = a - b
        local name = catalog and catalog.familyName and catalog.familyName[fam] or tostring(fam)
        if d > 0 then
            gained[#gained + 1] = name .. (d > 1 and (" x" .. d) or "")
        elseif d < 0 then
            local n = -d
            shed[#shed + 1] = name .. (n > 1 and (" x" .. n) or "")
        end
    end

    table.sort(gained); table.sort(shed)
    local net = afterProgress - beforeProgress
    local lead = net > 0 and ("wishlist progress +" .. net) or "loadout cleaned up"
    local out
    if #gained > 0 and #shed > 0 then
        out = lead .. " — gained " .. table.concat(gained, ", ")
            .. "; shed " .. table.concat(shed, ", ")
    elseif #gained > 0 then
        out = lead .. " — gained " .. table.concat(gained, ", ")
    elseif #shed > 0 then
        out = lead .. " — shed " .. table.concat(shed, ", ")
    else
        out = lead
    end
    -- Those siblings leaving makes the family's owned count visibly drop, so
    -- name the cleanup rather than let the player read it as a regression.
    local cleared = diag and tonumber(diag.wrongQShed) or 0
    if cleared > 0 then
        out = out .. "; cleared " .. cleared .. " wrong-quality cop"
            .. (cleared == 1 and "y" or "ies")
    end
    return out
end

local function MissingEchoSummary(plan, owned, catalog)
    local _, _, missing = WishlistProgress(plan, owned, catalog)
    if #missing == 0 then return "none" end
    return table.concat(missing, ", ")
end

local function StepArm(level, plan, owned, slots, disabledLevers, static, locked)
    local settings = Store.Settings()
    local automationAllowed = AutoAllowed()
    -- (a) Loadout selection is owned by the stock Echo Journal. Each saved
    -- loadout has its own Nexus wishlist association, so automatically choosing
    -- a different "best" slot would silently move the player into another
    -- build. We only trust the server-confirmed active numbered slot.
    if slots and not ActiveSlotRow(slots) then
        if plan then
            SetStatus("First-run wishlist active — Saved Build will be created by normal server progression")
        else
            SetStatus("Choose or create a wishlist to begin your first run")
        end
    end
    -- (b) disable off-wishlist conformant tome levers (one send per 0.5s)
    if automationAllowed and settings.autoDisable and plan and not plan.advisorOnly
        and Adapter.DiscoverySynced()
        and not (Adapter.TomeMutationPaused
            and Adapter.TomeMutationPaused()) then
        if (GetTime() - lastLeverSendAt) <= 0.5 then
            RequestStepAt(lastLeverSendAt + 0.5)
            MeasurePhase("overlayRender", RenderIdlePanel,
                plan, owned, slots, static.catalog, static, locked)
            return
        end
        local optOut = settings.leverOptOut or {}
        for _, lever in ipairs(plan.leverPlan.disable) do
            if not optOut[lever] and not disabledLevers[lever]
                and not leversDoneThisVisit[lever] then
                if not Adapter.LeverHasKnownMember(lever) then
                    -- unknown tome: its echo isn't in your pool, so there is
                    -- nothing to disable. Skip (marking done so we never
                    -- retry it -- this was the "no confirmation" spam).
                    leversDoneThisVisit[lever] = true
                else
                    local ok = Adapter.ToggleLever(lever, true)
                    if ok then
                        leversDoneThisVisit[lever] = true
                        lastLeverSendAt = GetTime()
                        RequestStepAt(lastLeverSendAt + 0.5)
                        SetStatus("disabling off-wishlist tome lever " .. lever)
                        break
                    else
                        RequestStepAt(GetTime() + 0.5)
                    end
                end
            end
        end
        -- (c) RE-ENABLE any confirmed-disabled lever the wishlist now
        -- needs (a wishlist switch after earlier disables would otherwise
        -- silently make convergence impossible)
        if (GetTime() - lastLeverSendAt) > 0.5 then
            for _, lever in ipairs(plan.leverPlan.keep) do
                if disabledLevers[lever] == "confirmed" then
                    local ok = Adapter.ToggleLever(lever, false)
                    if ok then
                        lastLeverSendAt = GetTime()
                        RequestStepAt(lastLeverSendAt + 0.5)
                        SetStatus("re-enabling wishlist tome lever " .. lever)
                        break
                    else
                        RequestStepAt(GetTime() + 0.5)
                    end
                end
            end
        end
    end
    MeasurePhase("overlayRender", RenderIdlePanel,
        plan, owned, slots, static.catalog, static, locked)
end

local function WatchRerollHold(board)
    -- reroll-hold observation: if our last action was a reroll and the
    -- previous board carried a guaranteed card, a changed flag-3 identity
    -- kills the tactic permanently (conservative).
    if lastDecision and lastDecision.type == "reroll" and lastBoardForRerollWatch then
        local prevG, curG = nil, nil
        local pb = lastBoardForRerollWatch
        if pb.guaranteedIndex then prevG = pb.cards[pb.guaranteedIndex].spellId end
        if board.guaranteedIndex then curG = board.cards[board.guaranteedIndex].spellId end
        if prevG and prevG ~= curG then
            local st = Store.State()
            st.rerollHoldViolations = (st.rerollHoldViolations or 0) + 1
            DemoteFlag("REROLL_HOLDS_GUARANTEED", "guaranteed head changed across a reroll")
        end
        lastBoardForRerollWatch = nil
    end
end

local function SelfCheckDisable(board, disabledLevers, catalog)
    -- user-confirmed DISABLE_SUPPRESSES_GUARANTEE=true: if a disabled
    -- lever's echo ever shows up flag-3 anyway, demote for the session.
    if not board.guaranteedIndex then return end
    local g = board.cards[board.guaranteedIndex]
    local row = catalog and catalog.rows[g.spellId]
    if not (row and row.requiredSpell ~= 0) then return end
    -- only a server-CONFIRMED disable proves anything; a pending one may
    -- simply not have been processed before this board was rolled
    if disabledLevers[row.requiredSpell] ~= "confirmed" then return end
    -- and only a CONFORMANT lever we actually disabled: the garbage
    -- requiredSpell=9 cohort (38 unrelated echoes) is never disabled by us,
    -- so a member appearing guaranteed after the user hand-disables one
    -- cohort sibling in the journal is NOT evidence against suppression.
    local lever = catalog.levers and catalog.levers[row.requiredSpell]
    if not (lever and lever.conformant) then return end
    DemoteFlag("DISABLE_SUPPRESSES_GUARANTEE",
        "disabled tome echo " .. tostring(g.spellId) .. " appeared guaranteed")
end

local function RerollBracket(level)
    level = tonumber(level) or 0
    if level <= 34 then return 1 end
    if level <= 63 then return 2 end
    if level <= 69 then return 3 end
    if level <= 77 then return 4 end
    return 5
end

-- Locked-slot design targets (NexusDB.lockDesignTargets, written by the
-- Wishlist Editor's locked-slot picker) are NOT part of the uploaded server
-- wishlist -- the 79-slot cap is real and a player may have zero room to
-- spare there. But the actual requirement is that these still get pursued
-- by the live decision engine the instant a board offers one, across
-- however many runs it takes; there is no "wait for wishlist room" here,
-- since the whole point of a locked slot is a standing, permanent pick
-- that never needs re-acquiring once secured. Folding these into the
-- compiled plan's wishedFamilies/targets is the only change needed --
-- every downstream rule in Policy.lua (guaranteed-take, defer, BANK/
-- freeze, held-echo preference, least-harmful-select) already keys off
-- plan.wishedFamilies, so a lock-designated family is automatically
-- treated exactly like any other wished family with zero changes to that
-- carefully-tuned decision logic itself. A locked target remains an
-- additional exact quota when the ordinary Wishlist already represents its
-- family (or even the same exact spell), so this builds an automation-only
-- merged target without mutating the server Wishlist projection.
local function WishlistWithLockTargets(wishlist, catalog, knownKey, knownTargets)
    local targets = knownTargets or LockDesignTargetsFor(wishlist, knownKey)
    if type(targets) ~= "table" or not next(targets) then return wishlist end
    local rows = catalog and catalog.rows
    local familyOf = catalog and catalog.familyOf
    if type(rows) ~= "table" or type(familyOf) ~= "table" then return wishlist end

    local entries, byFamily = {}, {}
    if wishlist then
        for fam, t in pairs(wishlist.byFamily or {}) do byFamily[fam] = t end
        for _, e in ipairs(wishlist.entries or {}) do
            entries[#entries + 1] = e
        end
    end

    local copiedFamilies = {}
    local function WritableTarget(fam)
        if copiedFamilies[fam] then return byFamily[fam] end
        local source = byFamily[fam]
        if type(source) ~= "table" then return nil end
        local copy = {}
        for key, value in pairs(source) do copy[key] = value end
        copy.qualityTiers = {}
        for index, tier in ipairs(source.qualityTiers or {}) do
            local tierCopy = {}
            for key, value in pairs(tier) do tierCopy[key] = value end
            copy.qualityTiers[index] = tierCopy
        end
        byFamily[fam] = copy
        copiedFamilies[fam] = true
        return copy
    end

    local changed = false
    for spellIdKey, targetValue in pairs(targets) do
        local id = tonumber(spellIdKey)
        local row = id and rows[id]
        local fam = id and familyOf[id]
        local copies = LockTargetCopies(targetValue, id)
        if id and row and fam and copies then
            local q = tonumber(row.quality) or 0
            entries[#entries + 1] = {
                spellId=id,quality=q,stacks=copies,family=fam,locked=true,
            }
            local target = WritableTarget(fam)
            if target then
                target.targetStacks = math.max(0,
                    tonumber(target.targetStacks) or 0) + copies
                local exactTier
                for _, tier in ipairs(target.qualityTiers) do
                    if tonumber(tier.spellId) == id then
                        exactTier = tier
                        break
                    end
                end
                if exactTier then
                    exactTier.n = math.max(0,
                        tonumber(exactTier.n) or 0) + copies
                else
                    target.qualityTiers[#target.qualityTiers + 1] = {
                        q=q,n=copies,spellId=id,
                    }
                end
                table.sort(target.qualityTiers, function(a, b)
                    local aq, bq = tonumber(a.q) or 0, tonumber(b.q) or 0
                    if aq ~= bq then return aq < bq end
                    return (tonumber(a.spellId) or 0)
                        < (tonumber(b.spellId) or 0)
                end)
            else
                byFamily[fam] = {
                    targetStacks=copies,wishedQuality=q,spellId=id,
                    qualityTiers={{q=q,n=copies,spellId=id}},
                }
            end
            changed = true
        end
    end
    if not changed then return wishlist end

    local merged = {}
    for k, v in pairs(wishlist or {}) do merged[k] = v end
    merged.entries = entries
    merged.byFamily = byFamily
    return merged
end

-- Static automation inputs are expensive but change far less often than the
-- board. Rebuild this immutable context only from explicit represented-data
-- signals (or the five-second self-healing fallback), never from board-only
-- dirtiness or an ordinary decision deadline.
local function CopyStatic(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, child in pairs(value) do
        out[CopyStatic(key, seen)] = CopyStatic(child, seen)
    end
    return out
end

local function KeyPart(value)
    local kind = type(value)
    local text = tostring(value == nil and "" or value)
    return kind .. ":" .. tostring(#text) .. ":" .. text
end

local function SortedMapKey(value, truthyOnly)
    local parts = {}
    for key, child in pairs(type(value) == "table" and value or {}) do
        if not truthyOnly or child then
            parts[#parts + 1] = KeyPart(key) .. "=" .. KeyPart(child)
        end
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function StrategyWishlistKey(wishlist)
    if type(wishlist) ~= "table" then return KeyPart(nil) end
    local familyParts = {}
    for key in pairs(type(wishlist.byFamily) == "table"
        and wishlist.byFamily or {}) do
        familyParts[#familyParts + 1] = KeyPart(key)
    end
    table.sort(familyParts)
    local entryParts = {}
    for index, entry in ipairs(type(wishlist.entries) == "table"
        and wishlist.entries or {}) do
        entryParts[index] = KeyPart(type(entry) == "table"
            and entry.spellId or nil)
    end
    return table.concat({
        table.concat(familyParts, ","),
        table.concat(entryParts, ","),
    }, "|")
end

local function SettingsKey(settings)
    local anchors = {}
    for _, name in ipairs(type(settings) == "table"
        and type(settings.anchorNames) == "table" and settings.anchorNames or {}) do
        anchors[#anchors + 1] = KeyPart(name)
    end
    table.sort(anchors)
    return table.concat({
        KeyPart(type(settings) == "table" and settings.anchorSpellId or nil),
        table.concat(anchors, ","),
        SortedMapKey(type(settings) == "table" and settings.leverOptOut, true),
    }, "|")
end

local AUTO_LOCK_WAITING_STATES = {
    submitted=true,["awaiting-confirmation"]=true,
}
local AUTO_LOCK_TERMINAL_STATES = {
    confirmed=true,rejected=true,expired=true,superseded=true,
}
local AUTO_LOCK_RECORD_STATES = {
    prepared=true,submitted=true,["awaiting-confirmation"]=true,
    confirmed=true,rejected=true,expired=true,superseded=true,
}

local function AutoLockInteger(value, allowZero)
    value = tonumber(value)
    if not value or value ~= value or value >= math.huge
        or value ~= math.floor(value)
        or (allowZero and value < 0 or not allowZero and value <= 0) then
        return nil
    end
    return value
end

local function AutoLockTime(value)
    value = tonumber(value)
    if not value or value ~= value or value < 0 or value >= math.huge then
        return nil
    end
    return value
end

local function AutoLockBaseKey(wishlistKey, spellId, replaces, copies)
    local parts = {
        KeyPart(wishlistKey),KeyPart(spellId),KeyPart(replaces or false),
    }
    if tonumber(copies) and tonumber(copies) > 1 then
        parts[#parts + 1] = KeyPart(tonumber(copies))
    end
    return table.concat(parts, "|")
end

local function AutoLockIdentity(baseKey, lockedRevision, lockedToken)
    return baseKey .. "|locked=" .. KeyPart(lockedRevision)
        .. "|state=" .. KeyPart(lockedToken)
end

local function AutoLockBucket(create)
    local state = Store and Store.State and Store.State() or nil
    if type(state) ~= "table" then return nil, "state_unavailable" end
    local bucket = state.autoLockAttempts
    if bucket == nil and create then
        bucket = {version=AUTO_LOCK_STATE_VERSION,records={}}
        state.autoLockAttempts = bucket
    end
    if type(bucket) ~= "table"
        or tonumber(bucket.version) ~= AUTO_LOCK_STATE_VERSION
        or type(bucket.records) ~= "table" then
        return nil, "state_incompatible"
    end
    local count = 0
    for key, record in pairs(bucket.records) do
        count = count + 1
        local preparedAt = type(record) == "table"
            and AutoLockTime(record.preparedAt) or nil
        local expiresAt = type(record) == "table"
            and AutoLockTime(record.expiresAt) or nil
        local adapterAttempts = type(record) == "table"
            and AutoLockInteger(record.adapterAttempts, true) or nil
        local spellId = type(record) == "table"
            and AutoLockInteger(record.spellId) or nil
        local lockedRevision = type(record) == "table"
            and AutoLockInteger(record.lockedRevision, true) or nil
        local replaces = type(record) == "table" and record.replaces ~= nil
            and AutoLockInteger(record.replaces) or nil
        local copies = type(record) == "table" and record.copies ~= nil
            and AutoLockInteger(record.copies) or 1
        local submittedAt = type(record) == "table"
            and AutoLockTime(record.submittedAt) or nil
        local resolvedAt = type(record) == "table"
            and AutoLockTime(record.resolvedAt) or nil
        local nextAttemptAt = type(record) == "table"
            and record.nextAttemptAt ~= nil
            and AutoLockTime(record.nextAttemptAt) or nil
        if type(key) ~= "string" or type(record) ~= "table"
            or key ~= record.baseKey
            or not AUTO_LOCK_RECORD_STATES[record.state]
            or type(record.identity) ~= "string"
            or type(record.baseKey) ~= "string"
            or type(record.wishlistKey) ~= "string"
            or type(record.lockedToken) ~= "string"
            or spellId == nil or lockedRevision == nil
            or (record.replaces ~= nil and replaces == nil)
            or copies == nil
            or record.baseKey ~= AutoLockBaseKey(record.wishlistKey,
                spellId,replaces,copies)
            or record.identity ~= AutoLockIdentity(record.baseKey,
                lockedRevision,record.lockedToken)
            or adapterAttempts == nil
            or adapterAttempts > AUTO_LOCK_MAX_ADAPTER_ATTEMPTS
            or preparedAt == nil or expiresAt == nil
            or expiresAt < preparedAt
            or submittedAt == nil or resolvedAt == nil
            -- A reload can reset GetTime before a retained attempt expires,
            -- so resolvedAt is finite but may legitimately precede preparedAt.
            or (submittedAt > 0
                and (submittedAt < preparedAt or submittedAt > expiresAt))
            or (record.nextAttemptAt ~= nil
                and (nextAttemptAt == nil or nextAttemptAt < preparedAt
                    or nextAttemptAt > expiresAt))
            or (record.retryRequested ~= nil
                and record.retryRequested ~= true)
            or (record.reason ~= nil and type(record.reason) ~= "string")
            or (record.error ~= nil and type(record.error) ~= "string")
            or count > 6 then
            return nil, "record_incompatible"
        end
    end
    return bucket
end

local function CaptureAutoLockLifecycle(record)
    if type(record) ~= "table" then return end
    lastAutoLockLifecycle = {
        state=tostring(record.state or "idle"),
        reason=tostring(record.reason or "none"),
        error=tostring(record.error or "none"),
        spellId=tonumber(record.spellId) or 0,
        replaces=tonumber(record.replaces) or 0,
        lockedRevision=tonumber(record.lockedRevision) or 0,
        adapterAttempts=tonumber(record.adapterAttempts) or 0,
        preparedAt=tonumber(record.preparedAt) or 0,
        submittedAt=tonumber(record.submittedAt) or 0,
        expiresAt=tonumber(record.expiresAt) or 0,
        resolvedAt=tonumber(record.resolvedAt) or 0,
    }
end

local function TransitionAutoLock(record, state, reason, now, err)
    if record.state ~= state then
        local counter = state == "awaiting-confirmation"
            and "awaitingConfirmation" or state
        if autoLockLifecycleStats[counter] ~= nil then
            autoLockLifecycleStats[counter] =
                autoLockLifecycleStats[counter] + 1
        end
    end
    record.state = state
    record.reason = reason or "none"
    record.error = err
    if state == "submitted" then record.submittedAt = now end
    if AUTO_LOCK_TERMINAL_STATES[state] then record.resolvedAt = now end
    CaptureAutoLockLifecycle(record)
end

local function AutoLockRecordMatches(record, descriptor)
    return type(record) == "table"
        and record.baseKey == descriptor.baseKey
        and tonumber(record.spellId) == descriptor.spellId
        and tonumber(record.replaces) == descriptor.replaces
        and (tonumber(record.copies) or 1) == descriptor.copies
        and record.identity == AutoLockIdentity(descriptor.baseKey,
            tonumber(record.lockedRevision),record.lockedToken)
end

local function AutoLockLockedToken(locked)
    if type(locked) ~= "table" or locked.synced ~= true
        or type(locked.bySpell) ~= "table" then return nil end
    local parts = {}
    for spellId, count in pairs(locked.bySpell) do
        spellId = AutoLockInteger(spellId)
        count = AutoLockInteger(count)
        if not spellId or not count then return nil end
        parts[#parts + 1] = tostring(spellId) .. "x" .. tostring(count)
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ",") or "0"
end

local function AutoLockDescriptors(targets, wishlistKey)
    local out, seen = {}, {}
    for spellIdKey, replacementValue in pairs(targets) do
        local spellId = AutoLockInteger(spellIdKey)
        local replaces = LockTargetReplacement(replacementValue)
        local copies = LockTargetCopies(replacementValue, spellId)
        if spellId and not copies then
            return nil, nil, "invalid persisted lock target"
        end
        if spellId then
            local baseKey = AutoLockBaseKey(
                wishlistKey, spellId, replaces, copies)
            if not seen[baseKey] then
                seen[baseKey] = true
                out[#out + 1] = {
                    spellId=spellId,replaces=replaces,copies=copies,
                    baseKey=baseKey,
                }
            end
        end
    end
    table.sort(out, function(left, right)
        if left.spellId ~= right.spellId then
            return left.spellId < right.spellId
        end
        return (left.replaces or 0) < (right.replaces or 0)
    end)
    return out, seen
end

local function SupersedeMissingAutoLockRecords(records, seen, now)
    for key, record in pairs(records) do
        if not seen[key] then
            if record.state ~= "superseded" then
                TransitionAutoLock(record, "superseded", "target_changed", now)
            end
            records[key] = nil
        end
    end
end

local function NewAutoLockRecord(descriptor, wishlistKey, lockedRevision,
    lockedToken, now)
    local record = {
        identity=AutoLockIdentity(descriptor.baseKey, lockedRevision,
            lockedToken),
        baseKey=descriptor.baseKey,
        wishlistKey=wishlistKey,spellId=descriptor.spellId,
        replaces=descriptor.replaces,copies=descriptor.copies,
        lockedRevision=lockedRevision,
        lockedToken=lockedToken,
        state="idle",reason="none",adapterAttempts=0,
        preparedAt=now,submittedAt=0,
        expiresAt=now + AUTO_LOCK_CONFIRM_TIMEOUT,resolvedAt=0,
    }
    TransitionAutoLock(record, "prepared", "ready", now)
    return record
end

local function RefreshAutoLockRecord(record, lockedRevision, lockedToken,
    isLocked, now)
    if record.retryRequested then
        record.retryRequested = nil
        TransitionAutoLock(record, "superseded", "explicit_retry", now)
        return nil
    end
    if tonumber(record.lockedRevision) ~= lockedRevision
        or record.lockedToken ~= lockedToken then
        if record.lockedToken == lockedToken then
            -- Session generations restart at login/reload. Identical
            -- authoritative content rebases the diagnostic revision only;
            -- it never grants a fresh submission lifetime.
            record.lockedRevision = lockedRevision
            record.identity = AutoLockIdentity(record.baseKey, lockedRevision,
                lockedToken)
            CaptureAutoLockLifecycle(record)
            return record
        end
        if isLocked then
            record.lockedRevision = lockedRevision
            record.lockedToken = lockedToken
            record.identity = AutoLockIdentity(record.baseKey, lockedRevision,
                lockedToken)
            TransitionAutoLock(record, "confirmed",
                "locked_state_observed", now)
            return record
        end
        TransitionAutoLock(record, "superseded", "locked_state_changed", now)
        return nil
    end
    if record.state == "submitted" then
        TransitionAutoLock(record, "awaiting-confirmation",
            "awaiting_locked_state", now)
    end
    if record.state == "prepared"
        or record.state == "awaiting-confirmation" then
        local preparedAt = tonumber(record.preparedAt) or now
        local expiresAt = tonumber(record.expiresAt)
            or (preparedAt + AUTO_LOCK_CONFIRM_TIMEOUT)
        record.expiresAt = expiresAt
        if now < preparedAt then
            TransitionAutoLock(record, "expired", "runtime_clock_reset", now,
                "runtime_clock_reset")
        elseif now >= expiresAt then
            TransitionAutoLock(record, "expired", "confirmation_timeout", now,
                "confirmation_timeout")
        else
            local nextAttemptAt = tonumber(record.nextAttemptAt)
            RequestAutoLockAt(nextAttemptAt and nextAttemptAt > now
                and nextAttemptAt or expiresAt)
            CaptureAutoLockLifecycle(record)
        end
    elseif record.state == "expired" then
        autoLockLifecycleStats.postExpiryBlocked =
            autoLockLifecycleStats.postExpiryBlocked + 1
        CaptureAutoLockLifecycle(record)
    else
        CaptureAutoLockLifecycle(record)
    end
    return record
end

local function RequestAutoLockRetry()
    local bucket = AutoLockBucket(false)
    if not bucket then return false end
    local changed = false
    for _, record in pairs(bucket.records) do
        if record.state == "expired" or record.state == "rejected" then
            if not record.retryRequested then
                record.retryRequested = true
                autoLockLifecycleStats.explicitRetries =
                    autoLockLifecycleStats.explicitRetries + 1
            end
            changed = true
        end
    end
    if changed then RequestRecompute() end
    return changed
end

local function CatalogRevision()
    local revisions = Nexus and Nexus.Revisions
    if not (revisions and type(revisions.Get) == "function") then return 0 end
    return revisions.Get(revisions.CATALOG_CHANGED) or 0
end

local FALLBACK_SIGNATURE_FIELDS = {
    "service", "level", "slots", "activeSlot", "granted", "locked",
    "discovery", "tomeSafety",
    "state", "settings", "associations", "association", "firstRun",
}
local FALLBACK_STATIC_COMPONENTS = {
    signature=true,service=true,level=true,slots=true,activeSlot=true,
    state=true,settings=true,associations=true,association=true,
    firstRun=true,catalogRevision=true,
}
local fallbackMismatchFields = {catalogRevision=0,signature=0}
for _, field in ipairs(FALLBACK_SIGNATURE_FIELDS) do
    fallbackMismatchFields[field] = 0
end
local lastFallbackReason = ""

local function SameFallbackSignature(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then
        return false, {"signature"}
    end
    local mismatches = {}
    for _, key in ipairs(FALLBACK_SIGNATURE_FIELDS) do
        if left[key] ~= right[key] then mismatches[#mismatches + 1] = key end
    end
    if left.catalogRevision ~= right.catalogRevision then
        mismatches[#mismatches + 1] = "catalogRevision"
    end
    return #mismatches == 0, mismatches
end

local function RecordFallbackMismatches(fields)
    for _, field in ipairs(fields or {"signature"}) do
        if fallbackMismatchFields[field] ~= nil then
            fallbackMismatchFields[field] = fallbackMismatchFields[field] + 1
            lastFallbackReason = "fallback:" .. field
        end
    end
end

local function ReadFallbackSignature()
    if type(Adapter.AutomationSignature) ~= "function" then return nil end
    local signature = Adapter.AutomationSignature()
    if type(signature) ~= "table" then return nil end
    signature.catalogRevision = CatalogRevision()
    return signature
end

local function CaptureFallbackSignature()
    lastFallbackCheckAt = GetTime()
    local ok, signature = pcall(ReadFallbackSignature)
    if ok and type(signature) == "table" then
        fallbackSignature = signature
        return true
    end
    return false
end

local function FallbackNeedsRepair(now)
    recomputeStats.fallbackChecks = recomputeStats.fallbackChecks + 1
    lastFallbackCheckAt = now
    local ok, signature = pcall(ReadFallbackSignature)
    local same, mismatches
    if ok and type(signature) == "table" then
        same, mismatches = SameFallbackSignature(fallbackSignature, signature)
    else
        same, mismatches = false, {"signature"}
    end
    if not same then
        RecordFallbackMismatches(mismatches)
        recomputeStats.fallbackRepairs = recomputeStats.fallbackRepairs + 1
        -- A complete validated signature is itself the new repair baseline.
        -- Dynamic-only mismatches intentionally skip static reconstruction,
        -- so retain this snapshot here rather than requiring StaticContext to
        -- run merely to prevent the same mismatch repairing every five seconds.
        if ok and type(signature) == "table" then
            fallbackSignature = signature
        end
        return true, mismatches and mismatches[1] or nil, signature
    end
    return false, nil, signature
end

local function AdvanceFallbackGeneration(field, value)
    if type(fallbackSignature) ~= "table" or type(value) ~= "number" then
        return
    end
    local current = tonumber(fallbackSignature[field])
    if current == nil or value >= current then
        fallbackSignature[field] = value
    end
end

local function AdvanceFallbackDynamicBaseline(level)
    if type(fallbackSignature) ~= "table" then return end
    level = tonumber(level)
    if level then fallbackSignature.level = level end
    if projectionRevisions.valid then
        -- Reconcile performed during StaticContext may already have captured
        -- a newer generation than ConsumeDirty returned at the start of this
        -- same tick. Never roll that freshly validated fallback baseline back.
        AdvanceFallbackGeneration("slots", projectionRevisions.slots)
        AdvanceFallbackGeneration("activeSlot", projectionRevisions.activeSlot)
        AdvanceFallbackGeneration("granted", projectionRevisions.granted)
        AdvanceFallbackGeneration("locked", projectionRevisions.locked)
        AdvanceFallbackGeneration("discovery", projectionRevisions.discovery)
    end
    AdvanceFallbackGeneration("catalogRevision", CatalogRevision())
end

local function StaticContext(probe, forceCompile)
    if staticCache and not probe and not staticInvalidated then
        recomputeStats.planReuses = recomputeStats.planReuses + 1
        return staticCache
    end
    recomputeStats.staticProbes = recomputeStats.staticProbes + 1
    lastStaticProbeAt = GetTime()
    staticProbeInProgress = true
    local catalogOk, catalog = pcall(MeasurePhase,
        "catalog", Adapter.Catalog)
    staticProbeInProgress = false
    if not catalogOk then error(catalog) end
    if not catalog then
        staticInvalidated = true
        CaptureFallbackSignature()
        return {catalog=nil}
    end
    local wishlist = MeasurePhase("wishlist", Adapter.Wishlist)
    local wishlistKey = MeasurePhase("wishlistFingerprint",
        LockSlotKey, wishlist)
    local targets = CopyStatic(LockDesignTargetsFor(wishlist, wishlistKey))
    recomputeStats.lockContextRebuilds =
        recomputeStats.lockContextRebuilds + 1
    local sourceSettings = Store.Settings()
    local settings = {
        anchorSpellId=type(sourceSettings) == "table"
            and sourceSettings.anchorSpellId or nil,
        anchorNames=CopyStatic(type(sourceSettings) == "table"
            and sourceSettings.anchorNames or nil),
        leverOptOut=CopyStatic(type(sourceSettings) == "table"
            and sourceSettings.leverOptOut or nil),
    }
    local wishlistSnapshot = CopyStatic(wishlist)
    local augmented = WishlistWithLockTargets(
        wishlistSnapshot, catalog, wishlistKey, targets)
    local key = table.concat({
        KeyPart(CatalogRevision()),StrategyWishlistKey(wishlist),
        KeyPart(wishlistKey),
        SortedMapKey(targets),SettingsKey(settings),
    }, "|")
    local plan
    if forceCompile or not staticCache or staticCache.key ~= key then
        plan = MeasurePhase("plan", Strategy.Compile,
            catalog, augmented, settings)
        recomputeStats.planCompiles = recomputeStats.planCompiles + 1
    else
        plan = staticCache.plan
        recomputeStats.planReuses = recomputeStats.planReuses + 1
    end
    staticCache = {
        key=key,catalog=catalog,wishlist=wishlistSnapshot,
        wishlistKey=wishlistKey,targets=targets,plan=plan,
    }
    staticInvalidated = false
    CaptureFallbackSignature()
    return staticCache
end

-- Auto-lock: the actual write side of the locked-slot feature. Confirmed
-- live via /nexus sniff, 2026-08-01 -- LockPerk(spellId)/UnlockPerk(spellId)
-- are real, callable functions (GameAdapter.lua's A.LockPerk/A.UnlockPerk).
-- Runs at ordinary poll cadence, independent of the board decision loop --
-- locking is a wholly separate character-state system.
--
-- For each NexusDB.lockDesignTargets entry not yet really locked:
--   - if the player now owns at least one copy (it's ready to lock) AND a
--     real slot is free, lock it immediately;
--   - if slots are full but this spellId was explicitly designed to
--     REPLACE a specific still-locked Echo (LockDesignTargets()[id] is that
--     Echo's spellId, not just `true`), unlock the old one to make room --
--     the next poll tick sees the freed slot and locks the new one.
-- Once LockedOwned() confirms an entry, the design target remains committed:
-- it describes the build's desired permanent lock state, not a disposable
-- work item. A later explicit replacement removes it when the wishlist is saved.
--
-- Replacement unlocks retain their prior conservative cooldown. LockPerk has
-- a stronger identity-bound confirmation lifecycle below and never uses a
-- time-only cooldown as permission to resubmit.
local autoUnlockCooldown = {}
-- Unlocking is destructive, so it is allowed only after the same real,
-- server-confirmed Saved Build + wishlist association has remained stable for
-- a short window. A death/reset temporarily reports activeSlot=0; the old
-- eager-shed code still ran in that transient first-run context and could
-- empty permanent lock slots against stale or incomplete design data.
local autoUnlockContextKey, autoUnlockContextSince = nil, 0
-- Rebuilt every call (even when gated out early) so /nexus log -> AutoLock
-- shows exactly what the live check saw, instead of guessing from the
-- outside -- this is what answers "why isn't this firing" directly.
local lastAutoLockTrace = { at = 0, lines = {} }
local function TryAutoLock(owned, catalog, slots, wishlist, targets, wishlistKey,
    locked, lockedRevision)
    local trace = {}
    local now = GetTime()
    lastAutoLockTrace = { at = now, lines = trace }

    -- Reuses the same master-switch gate as board automation (autoEnabled,
    -- not mid-manual-action, no rival addon, no client auto-accept
    -- conflict) -- if the player has paused Nexus, it shouldn't be taking
    -- ANY action on their behalf, locking included.
    local allowed, whyNot = AutoAllowed()
    trace[#trace + 1] = string.format("AutoAllowed: %s%s", tostring(allowed),
        (not allowed and whyNot) and (" (" .. tostring(whyNot) .. ")") or "")
    if not allowed then return end

    -- Separate opt-in, off by default (Wishlist Editor checkbox next to the
    -- Locked strip) -- a player may want full board automation without
    -- also handing Nexus this specific, more consequential write action.
    local settings = Store.Settings()
    trace[#trace + 1] = string.format("autoLockEchoes setting: %s", tostring(settings.autoLockEchoes))
    if not settings.autoLockEchoes then return end

    targets = targets or LockDesignTargetsFor(wishlist, wishlistKey)
    if type(targets) ~= "table" then
        trace[#trace + 1] = string.format(
            "lockDesignTargetsBySlot[%s]: table missing",
            tostring(LockSlotKey(wishlist, wishlistKey)))
        return
    end
    if not (Adapter.LockPerk and Adapter.UnlockPerk and Adapter.LockedOwned) then
        trace[#trace + 1] = "Adapter.LockPerk/UnlockPerk/LockedOwned: missing on this build"
        return
    end
    local descriptors, seen, descriptorError = AutoLockDescriptors(
        targets, wishlistKey)
    if not descriptors then
        trace[#trace + 1] = "AutoLock target state: "
            .. tostring(descriptorError or "invalid")
        return
    end
    local bucket, bucketError = AutoLockBucket(true)
    if not bucket then
        trace[#trace + 1] = "AutoLock attempt state: " .. tostring(bucketError)
        return
    end
    SupersedeMissingAutoLockRecords(bucket.records, seen, now)
    local targetCount = #descriptors
    trace[#trace + 1] = string.format("lockDesignTargets[slot %s]: %d entries",
        tostring(LockSlotKey(wishlist, wishlistKey)), targetCount)
    if targetCount == 0 then return end

    local lockedBySpell = (locked and locked.bySpell) or {}
    local lockedCount = 0
    for _, count in pairs(lockedBySpell) do
        local copies = AutoLockInteger(count)
        if not copies then
            trace[#trace + 1] = "authoritative locked-state counts are invalid"
            return
        end
        lockedCount = lockedCount + copies
    end
    lockedRevision = AutoLockInteger(lockedRevision, true)
    local lockedToken = AutoLockLockedToken(locked)
    local maxSlots, capacitySource = Adapter.MaxPermanentEchoes
        and Adapter.MaxPermanentEchoes() or nil, "unavailable"
    maxSlots = AutoLockInteger(maxSlots)
    if maxSlots then capacitySource = "service" end
    lastAutoLockCapacity = {
        used=lockedCount,maximum=maxSlots or 0,known=maxSlots ~= nil,
        source=capacitySource,synced=locked and locked.synced == true or false,
    }
    trace[#trace + 1] = string.format("locked: %d/%s source=%s synced=%s revision=%s",
        lockedCount,tostring(maxSlots or "unknown"),tostring(capacitySource),
        tostring(lastAutoLockCapacity.synced),tostring(lockedRevision))
    if not lastAutoLockCapacity.synced or lockedRevision == nil
        or lockedToken == nil then
        trace[#trace + 1] =
            "authoritative locked-state evidence unavailable; no submission"
        return
    end
    if not maxSlots then
        trace[#trace + 1] =
            "authoritative permanent-Echo capacity unavailable; no submission"
        return
    end

    -- "Owned" here needs to be more than Adapter.Owned() -- that reflects
    -- GetGrantedPerks(), a THIS-RUN concept that resets at every level-1
    -- boundary, so an Echo that's simply been sitting in the active saved
    -- loadout since an earlier run (never re-rolled this run) wouldn't show
    -- as owned at all, even though the player unmistakably has it. Copied
    -- into a fresh local table -- never mutate the shared owned.bySpell
    -- that StepRun/Policy.Decide also read this same tick.
    local ownedBySpell = {}
    for id, n in pairs((owned and owned.bySpell) or {}) do ownedBySpell[id] = n end
    local activeIdx = slots and tonumber(slots.activeSlot)
    local activeRow = activeIdx and activeIdx > 0 and slots.bySlot and slots.bySlot[activeIdx]
    trace[#trace + 1] = string.format("active loadout: slot=%s echoes=%s",
        tostring(activeIdx),
        tostring(activeRow and type(activeRow.echoes) == "table" and #activeRow.echoes or "n/a"))
    if activeRow and type(activeRow.echoes) == "table" then
        for _, e in ipairs(activeRow.echoes) do
            local eid = tonumber(e and e.spellId)
            if eid then
                local n = tonumber(e.stacks) or 1
                if n > (tonumber(ownedBySpell[eid]) or 0) then ownedBySpell[eid] = n end
            end
        end
    end

    -- LockPerk is additive and can safely continue during a first run. An
    -- UnlockPerk is different: only allow it while a populated numbered
    -- Saved Build is active AND its association is what produced this
    -- wishlist. Never unlock during activeSlot=0, a death/reset transition,
    -- an unassociated loadout, or a transient slot refresh.
    local unlockContextKey = nil
    if activeIdx and activeIdx > 0 and activeRow
        and type(activeRow.echoes) == "table" and #activeRow.echoes > 0
        and wishlist and wishlist.source == "loadout-association" then
        unlockContextKey = tostring(activeIdx) .. "|"
            .. tostring(LockSlotKey(wishlist, wishlistKey))
    end
    if unlockContextKey ~= autoUnlockContextKey then
        autoUnlockContextKey = unlockContextKey
        autoUnlockContextSince = now
    end
    local canUnlock = unlockContextKey ~= nil and (now - autoUnlockContextSince) >= 2
    if unlockContextKey ~= nil and not canUnlock then
        RequestAutoLockAt(autoUnlockContextSince + 2)
    end
    trace[#trace + 1] = string.format("destructive unlock context: %s%s",
        tostring(canUnlock), unlockContextKey and (" (" .. unlockContextKey .. ")")
            or " (no confirmed active Saved Build association)")

    local rows = catalog and catalog.rows
    local function EchoName(id)
        local row = rows and rows[id]
        return (row and row.name) or ("spell " .. tostring(id))
    end
    local function IsStillTarget(id)
        return id and (targets[id] ~= nil or targets[tostring(id)] ~= nil) and true or false
    end
    local function UnlockReplacement(oldId, newId)
        oldId, newId = tonumber(oldId), tonumber(newId)
        if not oldId or not newId or oldId == newId
            or (tonumber(lockedBySpell[oldId]) or 0) <= 0 then
            return false
        end
        -- Never honor a stale/inconsistent replacement pointer by unlocking an
        -- Echo the same committed design still explicitly says it wants.
        if IsStillTarget(oldId) then
            trace[#trace + 1] = "  -> replacement pointer conflicts with another desired target; unlock blocked"
            return false
        end
        if not canUnlock then
            trace[#trace + 1] =
                "  -> replacement is ready, but unlock deferred until a Saved Build association is active and stable"
            return false
        end
        local stillAllowed, actionWhy = AutoAllowed()
        local currentSettings = Store.Settings()
        if not stillAllowed or not currentSettings.autoLockEchoes then
            trace[#trace + 1] = "  -> unlock authorization changed: "
                .. tostring(actionWhy or "AutoLock disabled")
            return false
        end
        local lastAttempt = autoUnlockCooldown[oldId] or -30
        if (now - lastAttempt) < 10 then return false end
        autoUnlockCooldown[oldId] = now
        local ok, err = Adapter.UnlockPerk(oldId)
        trace[#trace + 1] = string.format(
            "  -> UnlockPerk(%s) for ready replacement %s: ok=%s err=%s",
            tostring(oldId), tostring(newId), tostring(ok), tostring(err))
        if err ~= "spacing" then
            AppendAutoLockEvent({ action = "unlock", spellId = oldId,
                name = EchoName(oldId), forTarget = newId, forName = EchoName(newId),
                pairing = "replacement", ok = ok and true or false, err = err,
                wishlistKey = LockSlotKey(wishlist, wishlistKey) })
        end
        if ok then
            Print(string.format(
                "|cff4dff80Nexus:|r unlocked %s -- %s is acquired and ready to replace it.",
                EchoName(oldId), EchoName(newId)))
            local removedCopies = tonumber(lockedBySpell[oldId]) or 0
            lockedBySpell[oldId] = nil
            lockedCount = math.max(0, lockedCount - removedCopies)
            return true
        elseif err ~= "spacing" then
            Print(string.format("|cffff6060Nexus:|r couldn't unlock %s: %s",
                EchoName(oldId), tostring(err)))
        end
        return false
    end

    -- Reconcile every persisted identity before considering a new mutation.
    -- This is what makes /reload and unrelated dirty/fallback work retain the
    -- original lifetime instead of manufacturing a fresh cooldown window.
    local currentRecords = {}
    local outstanding, uncertainTerminal = false, false
    for _, descriptor in ipairs(descriptors) do
        local record = bucket.records[descriptor.baseKey]
        if record and not AutoLockRecordMatches(record, descriptor) then
            trace[#trace + 1] =
                "AutoLock attempt record does not match its target identity"
            return
        end
        if record then
            record = RefreshAutoLockRecord(record, lockedRevision, lockedToken,
                (tonumber(lockedBySpell[descriptor.spellId]) or 0)
                    >= descriptor.copies, now)
            bucket.records[descriptor.baseKey] = record
        end
        currentRecords[descriptor.baseKey] = record
        if record and AUTO_LOCK_WAITING_STATES[record.state] then
            outstanding = true
        elseif record and record.state == "expired" then
            uncertainTerminal = true
        end
    end

    -- Never sweep every currently-locked Echo just because it is absent from
    -- a momentary wanted set. Replacements remain transactional, and at most
    -- one AutoLock mutation crosses the adapter boundary per evaluation.
    local mutationAttempted = false
    for _, descriptor in ipairs(descriptors) do
        local id, replaces = descriptor.spellId, descriptor.replaces
        local targetCopies = descriptor.copies
        local haveN = tonumber(ownedBySpell[id]) or 0
        local isLocked = (tonumber(lockedBySpell[id]) or 0) >= targetCopies
        local record = currentRecords[descriptor.baseKey]
        trace[#trace + 1] = string.format(
            "target %s (%s): locked=%s owned=%s/%s replaces=%s lifecycle=%s",
            tostring(id), EchoName(id or 0), tostring(isLocked), tostring(haveN),
            tostring(targetCopies),tostring(replaces),
            tostring(record and record.state or "none"))
        if isLocked then
            -- Fulfilled targets stay in the committed set permanently. They
            -- are desired lock-slot state, not a temporary work queue. If this
            -- target was a replacement and both Echoes are temporarily locked
            -- (because an open slot let the new one lock first), finish the
            -- exact pair by shedding only its explicitly replaced old Echo.
            if replaces and not outstanding and not uncertainTerminal
                and not mutationAttempted then
                UnlockReplacement(replaces, id)
                mutationAttempted = true
            end
        elseif haveN >= targetCopies then
            local currentCopies = tonumber(lockedBySpell[id]) or 0
            local neededCopies = math.max(0, targetCopies - currentCopies)
            if lockedCount + neededCopies <= maxSlots then
                if not record and not outstanding and not uncertainTerminal
                    and not mutationAttempted then
                    record = NewAutoLockRecord(descriptor, wishlistKey,
                        lockedRevision, lockedToken, now)
                    bucket.records[descriptor.baseKey] = record
                    currentRecords[descriptor.baseKey] = record
                end
                local nextAttemptAt = record and tonumber(record.nextAttemptAt)
                local canAttempt = record and record.state == "prepared"
                    and not outstanding and not uncertainTerminal
                    and not mutationAttempted
                    and (not nextAttemptAt or now >= nextAttemptAt)
                if canAttempt then
                    -- Immediate authorization is re-read after preparation and
                    -- directly before the consequential adapter call.
                    local stillAllowed, actionWhy = AutoAllowed()
                    local currentSettings = Store.Settings()
                    if not stillAllowed or not currentSettings.autoLockEchoes then
                        TransitionAutoLock(record, "superseded",
                            "authorization_changed", now,
                            actionWhy or "authorization_changed")
                        mutationAttempted = true
                    else
                        record.adapterAttempts =
                            (tonumber(record.adapterAttempts) or 0) + 1
                        record.nextAttemptAt = nil
                        local ok, err = Adapter.LockPerk(id)
                        mutationAttempted = true
                        trace[#trace + 1] = string.format(
                            "  -> LockPerk(%s): ok=%s err=%s attempt=%d/%d",
                            tostring(id),tostring(ok),tostring(err),
                            record.adapterAttempts,AUTO_LOCK_MAX_ADAPTER_ATTEMPTS)
                        if err ~= "spacing" then
                            AppendAutoLockEvent({ action = "lock", spellId = id,
                                name = EchoName(id),ok = ok and true or false,
                                err = err,wishlistKey = LockSlotKey(wishlist,
                                    wishlistKey),lifecycle=ok and "submitted"
                                    or "rejected" })
                        end
                        if ok then
                            TransitionAutoLock(record, "submitted",
                                "adapter_accepted", now)
                            TransitionAutoLock(record, "awaiting-confirmation",
                                "awaiting_locked_state", now)
                            RequestAutoLockAt(record.expiresAt)
                            outstanding = true
                            Print(string.format(
                                "|cff4dff80Nexus:|r lock request sent for %s; waiting for server confirmation.",
                                EchoName(id)))
                        elseif err == "spacing"
                            and record.adapterAttempts
                                < AUTO_LOCK_MAX_ADAPTER_ATTEMPTS
                            and (now + 3) < record.expiresAt then
                            record.reason, record.error = "spacing", "spacing"
                            record.nextAttemptAt = now + 3
                            autoLockLifecycleStats.spacingRetries =
                                autoLockLifecycleStats.spacingRetries + 1
                            CaptureAutoLockLifecycle(record)
                            RequestAutoLockAt(record.nextAttemptAt)
                        else
                            local reason = err == "spacing"
                                and "spacing_bound" or tostring(err or "refused")
                            TransitionAutoLock(record, "rejected", reason, now,
                                reason)
                            if err ~= "spacing" then
                                Print(string.format(
                                    "|cffff6060Nexus:|r couldn't lock %s: %s",
                                    EchoName(id),tostring(err)))
                            end
                        end
                    end
                elseif record and record.state == "expired" then
                    trace[#trace + 1] =
                        "  -> expired identity retained; explicit retry or authoritative change required"
                elseif record and record.state == "rejected" then
                    trace[#trace + 1] =
                        "  -> rejected identity retained; explicit retry or authoritative change required"
                end
            elseif replaces and replaces ~= id
                and (tonumber(lockedBySpell[replaces]) or 0) > 0 then
                if not outstanding and not uncertainTerminal
                    and not mutationAttempted then
                    UnlockReplacement(replaces, id)
                    mutationAttempted = true
                end
            elseif replaces and (tonumber(lockedBySpell[replaces]) or 0) <= 0 then
                trace[#trace + 1] =
                    "  -> paired old Echo is no longer locked; waiting for a free slot/server refresh"
            else
                trace[#trace + 1] =
                    "  -> all lock slots full; no explicit replacement pairing, so nothing destructive was attempted"
            end
        end
    end
end

local function ActionKey(action)
    if type(action) ~= "table" then return "none" end
    return table.concat({
        tostring(action.type or "none"),
        tostring(tonumber(action.spellId) or 0),
        tostring(tonumber(action.index) or 0),
        tostring(action.reason or "none"),
        action.endgame and "1" or "0",
        action.forced and "1" or "0",
    }, ":")
end

local function RecordActionLifecycle(intent, state, reason)
    if type(intent) ~= "table" then return end
    if intent.state ~= state and actionLifecycleStats[state] ~= nil then
        actionLifecycleStats[state] = actionLifecycleStats[state] + 1
    end
    intent.state, intent.lifecycleReason = state, reason
    lastActionLifecycle.state = state
    lastActionLifecycle.actionType = SAFE_ACTION_TYPES[intent.action.type]
        and intent.action.type or "other"
    lastActionLifecycle.reason = tostring(reason or "none")
    lastActionLifecycle.decisionRevision = intent.decisionRevision
    lastActionLifecycle.mutationAttempted = intent.mutationAttempted and true or false
    lastActionLifecycle.preparedAt = intent.preparedAt or 0
    lastActionLifecycle.submittedAt = intent.submittedAt or 0
    lastActionLifecycle.resolvedAt = (state == "prepared" or state == "submitted")
        and 0 or GetTime()
end

local function FinishActionIntent(state, reason, keepBlocking)
    local intent = actionIntent
    if not intent then return end
    RecordActionLifecycle(intent, state, reason)
    if not keepBlocking then actionIntent = nil end
end

local function ResolveActionIntent(board)
    local intent = actionIntent
    if not intent then return end
    if type(board) ~= "table" then
        if intent.state == "prepared" then
            FinishActionIntent("superseded", "board_unavailable_before_submit", false)
        elseif intent.state == "submitted" or intent.state == "uncertain" then
            FinishActionIntent("confirmed", "board_cleared", false)
        else
            actionIntent = nil
        end
        return
    end
    if board.signature ~= intent.boardSignature then
        if intent.state == "prepared" then
            FinishActionIntent("superseded", "board_changed_before_submit", false)
        elseif intent.state == "submitted" or intent.state == "uncertain" then
            FinishActionIntent("confirmed", "board_transition", false)
        else
            actionIntent = nil
        end
        return
    end
    local now = GetTime()
    if intent.state == "submitted" then
        if now >= (intent.expiresAt or math.huge) then
            FinishActionIntent("expired", "confirmation_timeout", true)
        elseif not Adapter.InFlight() then
            FinishActionIntent("uncertain", "latch_cleared_same_board", true)
        end
    elseif intent.state == "uncertain"
        and now >= (intent.expiresAt or math.huge) then
        FinishActionIntent("expired", "confirmation_timeout", true)
    end
end

local function PrepareActionIntent(board, action)
    actionDecisionRevision = actionDecisionRevision + 1
    local copy = {
        type=action.type,spellId=tonumber(action.spellId),
        index=tonumber(action.index),reason=action.reason,
        endgame=action.endgame and true or false,
        forced=action.forced and true or false,
    }
    local targetSpellId = copy.spellId
    if not targetSpellId and copy.index and board.cards[copy.index] then
        targetSpellId = tonumber(board.cards[copy.index].spellId)
    end
    local now = GetTime()
    actionIntent = {
        boardSignature=board.signature,
        boardIdSignature=board.idSignature,
        action=copy,actionKey=ActionKey(copy),
        targetSpellId=targetSpellId,
        decisionRevision=actionDecisionRevision,
        preparedAt=now,readyAt=now + ACTION_INTENT_BEAT,
        mutationAttempted=false,state="idle",
    }
    RecordActionLifecycle(actionIntent, "prepared", "intent_beat")
    RequestStepAt(actionIntent.readyAt)
    return actionIntent
end

local function PreauthorizeActionIntent(intent, settings)
    if not intent or intent.state ~= "prepared" then
        return false, "intent_not_prepared"
    end
    if GetTime() < (intent.readyAt or math.huge) then
        RequestStepAt(intent.readyAt)
        return false, "intent_beat"
    end
    local allowed, reason = MeasurePhase("preauthorize", AutoAllowed)
    if not (allowed and settings.autoPick) then
        actionLifecycleStats.preauthFailed =
            actionLifecycleStats.preauthFailed + 1
        FinishActionIntent("superseded", "authorization_changed", false)
        return false, reason or "authorization_changed"
    end
    if MeasurePhase("preauthorize", Adapter.InFlight) then
        RequestStepAt(GetTime() + POLL)
        return false, "adapter_in_flight"
    end
    local fresh = MeasurePhase("preauthorize", Adapter.Board)
    if not fresh or fresh.signature ~= intent.boardSignature then
        actionLifecycleStats.preauthFailed =
            actionLifecycleStats.preauthFailed + 1
        FinishActionIntent("superseded", "board_changed_before_submit", false)
        RequestStepAt(GetTime() + POLL)
        return false, "board_changed_before_submit"
    end
    local action = intent.action
    if action.type == "take" then
        local found = false
        for i = 1, #fresh.cards do
            if fresh.cards[i].spellId == action.spellId then found = true; break end
        end
        if not found then
            actionLifecycleStats.preauthFailed =
                actionLifecycleStats.preauthFailed + 1
            FinishActionIntent("superseded", "target_changed_before_submit", false)
            return false, "target_changed_before_submit"
        end
    elseif action.type == "banish" or action.type == "freeze" then
        local card = action.index and fresh.cards[action.index]
        if not card or tonumber(card.spellId) ~= intent.targetSpellId then
            actionLifecycleStats.preauthFailed =
                actionLifecycleStats.preauthFailed + 1
            FinishActionIntent("superseded", "target_changed_before_submit", false)
            return false, "target_changed_before_submit"
        end
    end
    return true
end

local function MarkIntentSubmitted(intent)
    intent.mutationAttempted = true
    intent.submittedAt = GetTime()
    intent.expiresAt = intent.submittedAt + ACTION_CONFIRM_TIMEOUT
    RecordActionLifecycle(intent, "submitted", "adapter_accepted")
    RequestStepAt(intent.expiresAt)
end


local function StepRun(level, plan, slots, owned, flags, disabledLevers, static,
    locked)
    local settings = Store.Settings()
    local catalog = static.catalog
    local board = MeasurePhase("board", Adapter.Board)
    lastStepContext.boardPresent = board ~= nil
    ResolveActionIntent(board)
    if not board then
        SetStatus("waiting for board")
        local preparePerformance, prepareStarted = BeginPhase("overlayPrepare")
        local model = { status = statusLine, cards = {}, recommendation = "",
            progress = BuildProgress(plan, owned, slots, catalog,
                nil, nil, static, locked),
            auto = AutoAllowed() and settings.autoPick,
            version = Nexus.VERSION }
        FinishPhase(preparePerformance, "overlayPrepare", prepareStarted)
        MeasurePhase("overlayRender", RenderPanel, model)
        return
    end

    if refusedBanishSig and refusedBanishSig ~= board.signature then
        refusedBanishSig = nil
    end
    if refusedRerollSig and refusedRerollSig ~= board.signature then
        refusedRerollSig = nil
    end

    if armTargetSlot and not armedConfirmed then
        boardsSinceArm = boardsSinceArm + 1
        if board.guaranteedIndex then
            armedConfirmed = true
            SetStatus("armed (guaranteed queue live)")
        elseif boardsSinceArm >= 3 then
            SetStatus("Activate did not guarantee -- treating as unarmed")
        end
    end

    WatchRerollHold(board)
    SelfCheckDisable(board, disabledLevers, catalog)

    local currentGuaranteedId = nil
    if board.guaranteedIndex and board.cards[board.guaranteedIndex] then
        currentGuaranteedId = tonumber(board.cards[board.guaranteedIndex].spellId)
    end
    local currentBracket = RerollBracket(level)
    if currentBracket ~= fillerFishState.bracket then
        fillerFishState.bracket = currentBracket
        fillerFishState.bracketSpent = 0
        fillerFishState.consecutive = 0
        fillerFishState.guaranteedId = currentGuaranteedId
    elseif currentGuaranteedId ~= fillerFishState.guaranteedId then
        fillerFishState.guaranteedId = currentGuaranteedId
        fillerFishState.consecutive = 0
    end

    local preparePerformance, prepareStarted = BeginPhase("boardPrepare")
    local activeRow = ActiveSlotRow(slots)
    local queue = Ratchet.PredictQueue(activeRow and activeRow.echoes or {},
        owned, plan, flags, disabledLevers, catalog)
    local charges = Adapter.Charges()
    local horizon = Adapter.Horizon()
    local state = {
        board = board, owned = owned, locked = locked, charges = charges, plan = plan,
        activeEchoes = activeRow and activeRow.echoes or {},
        queue = queue, flags = flags, level = level, catalog = catalog,
        horizon = horizon,
        canFreeze = (level < 80
            or (type(horizon) == "number" and horizon > 1))
            and (frozeThisBoard ~= board.signature),
        support = Model.Support(catalog, owned, level, disabledLevers, plan, DefaultProfile.params),
        params = DefaultProfile.params,
        allowBanish = settings.autoBanish ~= false,
        searchRefused = {
            banish = refusedBanishSig == board.signature,
            reroll = refusedRerollSig == board.signature,
        },
        rerollBudget = {
            consecutive = fillerFishState.consecutive,
            -- Bracket 1 (RerollBracket above) spans levels 1-34 and the
            -- 4-reroll budget below is meant to be rationed across that
            -- whole span for ONE continuous attempt. fillerFishState is
            -- deliberately reset on every run boundary (see its
            -- declaration above), so repeated early deaths/restarts each
            -- grant a full fresh allowance -- fine deep into a run, but
            -- confirmed live 2026-08-01 to compound badly when death
            -- keeps happening at level 1-10: the same thin, mostly
            -- level-ineligible pool gets fished again and again on a full
            -- budget every time. Shrink the allowance itself for that
            -- narrow band rather than touch the reset semantics.
            consecutiveLimit = (level <= 10) and 2 or 3,
            bracketSpent = fillerFishState.bracketSpent,
            bracketLimit = (level <= 10) and 2 or 4,
            -- Preserve a late-run reserve while several brackets remain.
            -- At 78-80 unused charges have no future value.
            reserve = (level >= 78) and 0 or 5,
        },
    }
    FinishPhase(preparePerformance, "boardPrepare", prepareStarted)
    local action = MeasurePhase("policy", Policy.Decide, state)

    -- ------------------------------------------------------------------
    -- Decision log (manual-training data). One entry per fresh board:
    -- everything needed to replay the decision offline, plus whatever
    -- the USER manually clicked on that board. Lives in SavedVariables
    -- (NexusDB.decisionLog) -- persists on /reload or logout.
    -- ------------------------------------------------------------------
    do
        local logs = Nexus.DiagnosticLogs
        -- Attach any pending user action to the PREVIOUS entry BEFORE
        -- creating this tick's new one. See file header note above.
        local ua = Adapter.ConsumeUserAction and Adapter.ConsumeUserAction()
        if ua and logs and type(logs.UpdateLast) == "function" then
            logs.UpdateLast("decision", function(e)
                e.user = type(e.user) == "table" and e.user or {}
                e.user[#e.user + 1] = { kind = ua.kind, arg = ua.arg }
            end)
        end
        if lastLoggedSig ~= board.signature then
            lastLoggedSig = board.signature
            local entry = {
                t = date and date("%H:%M:%S") or "",
                level = level,
                horizon = horizon,
                gIndex = board.guaranteedIndex,
                charges = { b = charges.banish, r = charges.reroll,
                            f = charges.freeze, ok = charges.trustworthy },
                proposal = { type = action.type, spellId = action.spellId,
                             index = action.index, reason = action.reason,
                             endgame = action.endgame },
                cards = {},
                pending = (function()
                    local out = {}
                    local total = #(queue.entries or {})
                    for qi = 1, math.min(12, total) do
                        local qe = queue.entries[qi]
                        if type(qe) == "table" and qe.family then
                            out[#out + 1] = tostring(qe.family)
                                .. (qe.wanted and "*" or "")
                        end
                    end
                    if total > 12 then out[#out + 1] = "...+" .. tostring(total - 12) end
                    return table.concat(out, ",")
                end)(),
                run = auditRunId,
                activeSlot = slots and slots.activeSlot or 0,
                queueN = #(queue.entries or {}),
                queueHead = (function()
                    local out = {}
                    for qi = 1, math.min(8, #(queue.entries or {})) do
                        local qe = queue.entries[qi]
                        if type(qe) == "table" then
                            out[#out + 1] = {
                                id = tonumber(qe.spellId) or 0,
                                fam = tostring(qe.family or ""),
                                wished = qe.wanted and true or false,
                            }
                        end
                    end
                    return out
                end)(),
            }
            for i = 1, #board.cards do
                local c = board.cards[i]
                local row = catalog.rows[c.spellId]
                local fam = c.family
                entry.cards[i] = {
                    id = c.spellId,
                    name = row and row.name or ("spell " .. tostring(c.spellId)),
                    fam = tostring(fam),
                    cardQ = c.quality,
                    catQ = row and row.quality,
                    maxStack = row and row.maxStack,
                    g = c.isGuaranteed or nil,
                    frozen = (c.isFrozen or c.isCarried or c.justFrozen) or nil,
                    wished = (plan.wishedFamilies and fam
                        and plan.wishedFamilies[fam]) and true or false,
                    wishQ = Model.EffectiveWishedQuality
                        and Model.EffectiveWishedQuality(plan, catalog, fam,
                            (owned and owned.byFamily and fam and owned.byFamily[fam]) or 0,
                            owned and owned.bySpell) or nil,
                    owned = (owned and owned.byFamily and fam
                        and owned.byFamily[fam]) or 0,
                    delta = action.deltas and action.deltas[i],
                    ann = action.annotations and action.annotations[i],
                }
            end
            if logs and type(logs.Append) == "function" then
                logs.Append("decision", entry)
            end

            if auditRunStarted ~= auditRunId then
                auditRunStarted = auditRunId
                local slotCounts = activeRow and FamilyCountsFromEchoes(activeRow.echoes, catalog) or {}
                local exact = {}
                for _, ae in ipairs((activeRow and activeRow.echoes) or {}) do
                    exact[#exact + 1] = {
                        id = tonumber(ae.spellId) or 0,
                        fam = tostring(ae.family or ""),
                        q = tonumber(ae.quality) or -1,
                        n = tonumber(ae.stacks) or 1,
                    }
                end
                AppendAudit("RUN_START", {
                    level = level,
                    activeSlot = slots and slots.activeSlot or 0,
                    wishlist = (static.wishlist and static.wishlist.name) or "",
                    incumbent = WishedCounts(slotCounts, plan),
                    exact = exact,
                })
            end
        end
    end

    -- render (bridge display names onto the copies -- Readout is id-blind)
    local overlayPerformance, overlayStarted = BeginPhase("overlayPrepare")
    local cardLines = {}
    for i = 1, #board.cards do
        local card = board.cards[i]
        local row = catalog.rows[card.spellId]
        card.name = row and row.name or nil
        cardLines[#cardLines + 1] = {
            text = Readout.CardLine(card,
                action.annotations and action.annotations[i],
                action.deltas and action.deltas[i]),
            highlight = (action.type == "take"
                and board.cards[i].spellId == action.spellId),
        }
    end
    local okAuto, autoWhy = MeasurePhase("preauthorize", AutoAllowed)
    local recommendation = action.reason or action.type or ""
    if type(action.steps) == "table" and #action.steps > 0 then
        local lines = {}
        for si, step in ipairs(action.steps) do
            local row = step.spellId and catalog.rows[step.spellId]
            local label = step.type == "freeze" and "Freeze"
                or step.type == "take" and "Take"
                or tostring(step.type)
            lines[#lines + 1] = string.format("%d. %s %s",
                si, label, row and row.name or ("spell " .. tostring(step.spellId or "?")))
        end
        recommendation = table.concat(lines, "\n")
    end
    local panelModel = {
        status = statusLine,
        cards = cardLines,
        progress = BuildPanelProgress(plan, owned, slots, catalog, static,
            locked),
        level = level,
        recommendation = recommendation,
        auto = autoEnabled,
        version = Nexus.VERSION,
    }
    FinishPhase(overlayPerformance, "overlayPrepare", overlayStarted)
    MeasurePhase("overlayRender", RenderPanel, panelModel)

    -- pacing: decide, show intent, act after a short beat
    if action.type == "wait" then
        if actionIntent and actionIntent.boardSignature == board.signature
            and actionIntent.state == "prepared" then
            FinishActionIntent("superseded", "policy_wait", false)
        end
        SetStatus(action.reason == "advisor"
            and "No wishlist set -- advisor only" or ("waiting: " .. tostring(action.reason)))
        return
    end
    SetStatus("L" .. level .. " -- " .. (action.reason or action.type))
    if not (okAuto and settings.autoPick) then
        if actionIntent and actionIntent.boardSignature == board.signature
            and actionIntent.state == "prepared" then
            FinishActionIntent("superseded", "authorization_changed", false)
        end
        if not okAuto then SetStatus("auto paused: " .. autoWhy) end
        return
    end
    if actionIntent and actionIntent.boardSignature == board.signature then
        if actionIntent.state ~= "prepared" then
            SetStatus("waiting: " .. tostring(actionIntent.state)
                .. " " .. tostring(actionIntent.action.type))
            return
        end
        if actionIntent.actionKey ~= ActionKey(action) then
            FinishActionIntent("superseded", "decision_changed", false)
        end
    end
    local intent = actionIntent
    if not intent then
        PrepareActionIntent(board, action)
        return -- show the immutable intent one beat before acting
    end
    local authorized = PreauthorizeActionIntent(intent, settings)
    if not authorized then return end
    local immutable = intent.action

    if immutable.type == "take" then
        MarkActionAttempt(immutable.type)
        fillerFishState.consecutive = 0
        if immutable.forced then
            local fid = tonumber(immutable.spellId)
            if fid then
                forcedTakesBySpell[fid] = (forcedTakesBySpell[fid] or 0) + 1
            end
        end
        local ok, err = Adapter.Take(immutable.spellId)
        if ok then
            lastDecision = immutable
            MarkIntentSubmitted(intent)
        else
            intent.mutationAttempted = true
            FinishActionIntent("rejected", err or "adapter_refused", true)
        end
    elseif immutable.type == "banish" and settings.autoBanish then
        MarkActionAttempt(immutable.type)
        fillerFishState.consecutive = 0
        -- Policy indexes cards 1-based; the client (and adapter) are 0-based
        local ok, err = Adapter.Banish(immutable.index - 1)
        if ok then
            lastDecision = immutable
            MarkIntentSubmitted(intent)
            SetStatus(string.format("|cffff6666Banished|r echo #%d", immutable.index))
        else
            refusedBanishSig = board.signature
            intent.mutationAttempted = true
            FinishActionIntent("rejected", err or "adapter_refused", false)
            SetStatus(immutable.endgame
                and "final-search Banish refused -- re-evaluating"
                or "Banish refused -- trying another action")
        end
    elseif immutable.type == "freeze" then
        MarkActionAttempt(immutable.type)
        fillerFishState.consecutive = 0
        -- one freeze per board; the follow-up banish/reroll happens on a
        -- later tick once this resolves
        local ok, err = Adapter.Freeze(immutable.index - 1)
        if ok then
            lastDecision = immutable
            MarkIntentSubmitted(intent)
            frozeThisBoard = board.signature
            SetStatus(string.format("|cff66aaff Froze|r echo #%d -- waiting for board to update",
                immutable.index))
        else
            intent.mutationAttempted = true
            FinishActionIntent("rejected", err or "adapter_refused", true)
            frozeThisBoard = board.signature   -- refused: do not retry this board
        end
    elseif immutable.type == "reroll" then
        MarkActionAttempt(immutable.type)
        local ok = Adapter.Reroll()
        if ok then
            lastDecision = immutable
            MarkIntentSubmitted(intent)
            lastBoardForRerollWatch = board
            if immutable.reason == "bracket fishing: reroll filler guarantee" then
                fillerFishState.consecutive = fillerFishState.consecutive + 1
                fillerFishState.bracketSpent = fillerFishState.bracketSpent + 1
            else
                fillerFishState.consecutive = 0
            end
        else
            refusedRerollSig = board.signature
            intent.mutationAttempted = true
            FinishActionIntent("rejected", "adapter_refused", false)
            SetStatus(immutable.endgame
                and "final-search Reroll refused -- taking held Echo"
                or "Reroll refused -- taking the least-harmful Echo")
        end
    end
end

local function StepSave(level, plan, slots, owned, static, locked)
    MeasurePhase("overlayRender", RenderIdlePanel,
        plan, owned, slots, static.catalog, static, locked)
    local settings = Store.Settings()
    local automationAllowed = AutoAllowed()
    if not automationAllowed or not settings.autoSave or savedThisVisit then
        return
    end
    -- A level-80 character can load with owned data that looks like a
    -- completed run. Never evaluate or send a save unless this session
    -- actually observed at least one offering for the current run.
    if auditRunStarted ~= auditRunId then
        SetStatus("saved loadout unchanged — no current run observed")
        return
    end
    if plan.advisorOnly then
        -- with no wishlist every family is "filler": Dominates would bless
        -- any smaller build and shrink the snapshot -- never save
        SetStatus("No wishlist set -- not saving")
        return
    end
    if not slots then SetStatus("waiting for slot data"); return end
    if not owned.synced then SetStatus("waiting for owned-state sync"); return end
    local catalog = static.catalog
    local incumbent = ActiveSlotRow(slots)
    if incumbent then
        local incumbentCounts = FamilyCountsFromEchoes(incumbent.echoes, catalog)
        local candidateCounts = CopyCounts(owned.byFamily)
        local ok, detail, saveDiag = Ratchet.Dominates(
            owned, incumbent.echoes, plan, catalog, forcedTakesBySpell)
        if not saveGateAuditedVisit then
            AppendAudit("SAVE_GATE", {
                level = level, activeSlot = slots.activeSlot, targetSlot = incumbent.slot,
                result = ok and "APPROVED" or "BLOCKED", reason = tostring(detail or ""),
                incumbent = WishedCounts(incumbentCounts, plan),
                candidate = WishedCounts(candidateCounts, plan),
                -- Test 15: itemized save-gate breakdown (nil-safe -- Dominates
                -- returns no diag table on its early unreadable-input paths).
                exactGained = saveDiag and saveDiag.gainedStacks,
                exactLost = saveDiag and saveDiag.lostStacks,
                excessForced = saveDiag and saveDiag.excessIncreaseForced,
                excessAvoidable = saveDiag and saveDiag.excessIncreaseAvoidable,
                excessShed = saveDiag and saveDiag.excessDecrease,
                wrongQForced = saveDiag and saveDiag.wrongQForced,
                wrongQAvoidable = saveDiag and saveDiag.wrongQAvoidable,
                wrongQShed = saveDiag and saveDiag.wrongQShed,
                wrongQDetail = saveDiag and saveDiag.wrongQDetail,
                pollutionScore = saveDiag and saveDiag.pollutionScore
                    and string.format("%.2f", saveDiag.pollutionScore) or nil,
            })
            saveGateAuditedVisit = true
        end
        if ok then
            -- Writes must always target the server-confirmed active loadout.
            if tonumber(incumbent.slot) ~= tonumber(slots.activeSlot) then
                SetStatus("active loadout changed before save -- write cancelled")
                return
            end
            -- The saved loadout is the in-progress form of its associated
            -- wishlist, so keep both names aligned whenever Nexus overwrites it.
            local wl = Adapter.Wishlist()
            local saveName = wl and tostring(wl.name or "") or ""
            if saveName == "" then saveName = incumbent.name or "Nexus" end
            local saved = Adapter.Save(incumbent.slot, saveName)
            if saved then
                -- send != success: SS-541 FAIL (combat/dead) is consumed
                -- invisibly. Block re-save, but only CONFIRM after a fresh
                -- SS-540 shows the slot now holds the improved build.
                savedThisVisit = true
                -- Snapshot the exact post-save state at send time. Saved Build
                -- readback merges permanent locks into the rolled loadout, so
                -- verification must expect that same server-normalized union.
                local lockedNow = Adapter.LockedOwned and Adapter.LockedOwned() or nil
                local snap = CopyOwnedSnapshot(owned, lockedNow, catalog)
                saveVerifySlot, saveVerifyAt, seedVerify, saveVerifySnap =
                    incumbent.slot, GetTime(), false, snap
                saveVerifyExpectedActive = tonumber(slots.activeSlot)
                saveVerifySummary = SaveChangeSummary(owned, incumbent.echoes, plan, catalog, saveDiag)
                saveVerifyName = saveName
                noChangeReportedVisit = false
                saveObserveIndex, saveObserveReadyAt = 1, nil
                slotsRefreshAt = nil
                AppendAudit("SAVE_SENT", {
                    level = level, activeSlot = slots.activeSlot,
                    targetSlot = incumbent.slot, expectedActive = slots.activeSlot,
                    candidate = WishedCounts(snap.byFamily, plan), summary = saveVerifySummary or "",
                })
                local stillNeeded = MissingEchoSummary(plan, owned, catalog)
                SetStatus("Save sent — checking server")
                Print(string.format("Save sent — %s. Checking the Saved Build now. Still needed: %s.",
                    saveVerifySummary or "loadout improved", stillNeeded))
                NexusDB.lastSaveStatus = {
                    state = "sent", slot = incumbent.slot, name = saveName,
                    t = date and date("%H:%M:%S") or "",
                    summary = saveVerifySummary or "", stillNeeded = stillNeeded,
                }
            end
        else
            local wl = Adapter.Wishlist()
            local wlName = wl and ((wl.name ~= "" and wl.name) or "your build") or "your build"
            -- Translate the raw Ratchet detail into something readable
            local readableDetail
            if tostring(detail):find("no net gain") then
                readableDetail = "wishlist coverage unchanged this run"
            elseif tostring(detail):find("progress regressed")
                or tostring(detail):find("coverage lost") then
                readableDetail = "this run finished farther from the wishlist than your saved snapshot"
            elseif tostring(detail):find("pollution") and saveDiag and saveDiag.wrongQDetail then
                -- Name the actual offending Echo instead of the generic technical
                -- phrase. "cleanup-only save added new excess/wrong-quality
                -- pollution" reads as if nothing happened, but what actually
                -- happened is a forced wrong-quality sibling -- visible in the
                -- UI as that family's owned count going UP -- with no other net
                -- wishlist progress to offset it. Live 2026-08-02: a player saw
                -- Swift Step's count rise and read that as progress; it was a
                -- forced quality-1 copy while the wished quality-2 target was
                -- already fully covered by the saved build.
                local id, actualQ, wishedQ =
                    tostring(saveDiag.wrongQDetail):match("(%d+) q(%d+)<q(%d+)")
                local row = id and catalog and catalog.rows and catalog.rows[tonumber(id)]
                local name = row and row.name or (id and ("spell " .. id)) or nil
                if name and actualQ and wishedQ then
                    readableDetail = string.format(
                        "%s rolled at quality tier %s instead of the wished tier %s -- "
                            .. "not real progress, and nothing else this run offset it",
                        name, actualQ, wishedQ)
                else
                    readableDetail = tostring(detail)
                end
            else
                readableDetail = tostring(detail)
            end
            SetStatus(string.format(
                "Working toward '%s' — run complete, no improvement (%s)",
                wlName, readableDetail))
            NexusDB.lastSaveRefusal = {
                t = date and date("%H:%M:%S") or "",
                level = level, detail = tostring(detail),
                incumbentSlot = incumbent.slot,
            }
            if not noChangeReportedVisit then
                local incumbentOwned = { byFamily = FamilyCountsFromEchoes(incumbent.echoes, catalog) }
                Print(string.format("No improvement run — not saving. Still needed: %s.",
                    MissingEchoSummary(plan, owned, catalog)))
                noChangeReportedVisit = true
            end
        end
    else
        -- Seeding: only create a new snapshot if the player has NO echo
        -- data in any slot at all. If they have existing slots with echoes,
        -- the problem is activation (wrong slot is active), not seeding.
        -- Seeding into an empty slot when slots with data exist was causing
        -- the "must manually overwrite your loadout after first run" bug.
        local hasAnyData = false
        for _, slotData in pairs(slots.bySlot) do
            if slotData and slotData.echoes and #slotData.echoes > 0 then
                hasAnyData = true; break
            end
        end
        if hasAnyData then
            SetStatus("First run complete — save/activate it in My Builds before resetting")
            if not noChangeReportedVisit then
                Print("|cffff9040Nexus:|r Nexus cannot safely choose or overwrite a Saved Build while none is active. "
                    .. "Open Echo Journal > My Builds, save this finished run into a slot, and activate that slot before resetting.")
                noChangeReportedVisit = true
            end
        else
            -- Truly fresh install: seed into the first unlocked empty slot
            local unlocked = Adapter.UnlockedSlots()
            local target = nil
            for slot = 1, math.min(slots.maxSlots, unlocked) do
                if slots.bySlot[slot] == nil then target = slot; break end
            end
            if target then
                local saved, saveErr = Adapter.Save(target, "Nexus")
                if saved then
                    savedThisVisit = true
                    local lockedNow = Adapter.LockedOwned and Adapter.LockedOwned() or nil
                    local snap = CopyOwnedSnapshot(owned, lockedNow, catalog)
                    saveVerifySlot, saveVerifyAt, seedVerify, saveVerifySnap =
                        target, GetTime(), true, snap
                    saveVerifyExpectedActive = nil
                    saveVerifySummary = "first completed run"
                    saveVerifyName = "Nexus"
                    saveObserveIndex, saveObserveReadyAt = 1, nil
                    slotsRefreshAt = nil
                    AppendAudit("SAVE_SENT", {
                        level = level, activeSlot = slots.activeSlot or 0,
                        targetSlot = target, candidate = WishedCounts(snap.byFamily, plan),
                        summary = "first completed run",
                    })
                    SetStatus("first-run save sent to Saved Build " .. target .. " -- confirming")
                    Print("|cffff9040Nexus:|r first run complete. Nexus is attempting to store it in Saved Build "
                        .. tostring(target) .. ". Wait for the confirmation message before resetting; "
                        .. "if it does not confirm, save this finished loadout manually in Echo Journal > My Builds.")
                elseif saveErr ~= "spacing" then
                    savedThisVisit = true
                    SetStatus("First run complete — save it manually in My Builds before resetting")
                    Print("|cffff9040Nexus:|r I couldn't create the first Saved Build automatically. "
                        .. "Open Echo Journal > My Builds and save this finished run into a Saved Build slot before resetting.")
                end
            else
                SetStatus("First run complete — no free Saved Build slot; save manually before resetting")
                if not noChangeReportedVisit then
                    Print("|cffff9040Nexus:|r your first run is finished, but Nexus found no free Saved Build slot. "
                        .. "Save this loadout manually in Echo Journal > My Builds before resetting.")
                    noChangeReportedVisit = true
                end
            end
        end
    end
end

local function BeginStepContext(work)
    work = type(work) == "table" and work or {}
    local compileBefore = recomputeStats.planCompiles
    local reuseBefore = recomputeStats.planReuses
    lastStepContext.trigger = ControlledToken(
        work.trigger, SAFE_TRIGGERS, "other")
    lastStepContext.dirtyMask = tonumber(work.dirtyMask) or 0
    lastStepContext.staticProbe = work.staticProbe and true or false
    lastStepContext.forceCompile = work.forceCompile and true or false
    lastStepContext.autoLockDue = work.autoLockDue and true or false
    lastStepContext.fallbackComponent = ControlledToken(
        work.fallbackComponent, SAFE_FALLBACK_COMPONENTS, "none")
    lastStepContext.staticRevisionBefore = CatalogRevision()
    lastStepContext.staticRevisionAfter = lastStepContext.staticRevisionBefore
    lastStepContext.planCompiled = false
    lastStepContext.planReused = false
    lastStepContext.boardPresent = false
    lastStepContext.actionAttempted = false
    lastStepContext.actionType = "none"
    lastStepContext.outcome = "running"
    lastStepContext.syncWindowClass = "unavailable"
    if Nexus.Sync and type(Nexus.Sync.IsReceiving) == "function" then
        local okReceiving, receiving = pcall(Nexus.Sync.IsReceiving)
        if okReceiving then
            lastStepContext.syncWindowClass = receiving
                and "receiving" or "quiet"
        end
    end
    return work, compileBefore, reuseBefore
end

local function FinishStepContext(compileBefore, reuseBefore)
    lastStepContext.staticRevisionAfter = CatalogRevision()
    lastStepContext.planCompiled = recomputeStats.planCompiles > compileBefore
    lastStepContext.planReused = recomputeStats.planReuses > reuseBefore
end

local function ResetRunBoundary()
    if seedVerify and saveVerifySlot then
        Print("|cffff9040Nexus:|r the first-run Saved Build write was not confirmed before the reset. "
            .. "Open Echo Journal > My Builds and verify/save the loadout manually before relying on automated convergence.")
    end
    NexusDB.auditRunCounter = (tonumber(NexusDB.auditRunCounter) or 0) + 1
    auditRunId = NexusDB.auditRunCounter
    auditRunStarted = nil
    leversDoneThisVisit = {}
    armAttempts, armTargetSlot = 0, nil
    armedConfirmed, boardsSinceArm = false, 0
    saveVerifySlot, seedVerify, saveVerifySnap = nil, nil, nil
    saveVerifyExpectedActive, saveVerifySummary = nil, nil
    saveObserveIndex, saveObserveReadyAt = 1, nil
    noChangeReportedVisit = false
    saveGateAuditedVisit = false
    fillerFishState.guaranteedId = nil
    fillerFishState.consecutive = 0
    fillerFishState.bracket = nil
    fillerFishState.bracketSpent = 0
    forcedTakesBySpell = {}
    if actionIntent then
        FinishActionIntent("superseded", "run_boundary", false)
    end
    lastDecision = nil
    lastLoggedSig = nil
    lastBoardForRerollWatch = nil
    frozeThisBoard = nil
    refusedBanishSig, refusedRerollSig = nil, nil
    Adapter.RunBoundaryReset()   -- void the dead run's picks/trust
end

local function HandleLevelTransition(level, boundaryGeneration)
    boundaryGeneration = tonumber(boundaryGeneration)
    if boundaryGeneration
        and boundaryGeneration == math.floor(boundaryGeneration)
        and boundaryGeneration > lastRunBoundaryGeneration then
        ResetRunBoundary()
        -- A sticky generation can be observed again after a later Step phase
        -- fails. Acknowledge it immediately after the authoritative reset so
        -- the bounded retry cannot reset the same run twice.
        lastRunBoundaryGeneration = boundaryGeneration
    end
    local levelChanged = lastLevelSeen ~= level
    if levelChanged then
        -- A short user-action pause belongs to the board/level where it was
        -- observed. Never let it suppress the first actionable board after a
        -- genuine progression transition.
        externalPauseUntil = 0
        if level ~= 80 then savedThisVisit = false end
        lastLevelSeen = level
    end
    if Adapter.ExternalActionSeen() and not levelChanged then
        externalPauseUntil = GetTime() + 3
    end
end

local function ShowQuickStartOnce(wishlist)
    if quickStartChecked then return end
    quickStartChecked = true
    if Nexus.QuickStart then
        Nexus.QuickStart.ShowIfFirstTime(wishlist ~= nil)
    end
end

local function RunAutoLockStep(work, owned, catalog, slots, wishlist,
                               static, locked)
    if not work.autoLockDue then return true end
    recomputeStats.autoLockEvaluations =
        recomputeStats.autoLockEvaluations + 1
    local okAutoLock, errAutoLock = pcall(MeasurePhase, "autoLock",
        TryAutoLock, owned, catalog, slots, wishlist, static.targets,
        static.wishlistKey, locked,
        projectionRevisions.valid and projectionRevisions.locked or nil)
    if okAutoLock then return true end
    SetStatus("error (see /nexus err)")
    RecordError("TryAutoLock", errAutoLock)
    return false
end

local function ClearStaleDemotions()
    if not demotionsClearedThisSession and Adapter.Ready() then
        Store.State().flagDemotions = {}
        demotionsClearedThisSession = true
    end
end

local function ObservePendingSave(catalog)
    -- One write is sent, then Nexus polls every Snapshot slot for 30 seconds.
    -- It never resubmits automatically. This distinguishes a real server write
    -- failure from stale or differently normalized slot data without risking
    -- repeated overwrites.
    if not saveVerifySlot then return end
    local elapsed = GetTime() - (saveVerifyAt or GetTime())
    local due = saveObserveSchedule[saveObserveIndex]
    if due and elapsed >= due and not saveObserveReadyAt then
        if Adapter.RequestSlots() then
            saveObserveReadyAt = GetTime() + 0.4
            RequestStepAt(saveObserveReadyAt)
        else
            RequestStepAt(GetTime() + POLL)
        end
    elseif saveObserveReadyAt and GetTime() >= saveObserveReadyAt then
        local freshSlots = Adapter.Slots()
        local confirmed = ObserveAllSlots(freshSlots, saveVerifySnap, catalog,
            due or elapsed)
        saveObserveReadyAt = nil
        saveObserveIndex = saveObserveIndex + 1
        if confirmed then
            if saveVerifyExpectedActive
                and tonumber(freshSlots and freshSlots.activeSlot)
                    ~= tonumber(saveVerifyExpectedActive) then
                SetStatus("save data matched, but active loadout changed — not claiming overwrite")
            else
                AppendAudit("SAVE_CONFIRMED", {
                    targetSlot = saveVerifySlot,
                    activeSlot = freshSlots and freshSlots.activeSlot or 0,
                    candidate = CopyCounts(saveVerifySnap and saveVerifySnap.byFamily),
                    summary = saveVerifySummary or "",
                })
                if seedVerify then
                    SetStatus("First run saved to Saved Build " .. saveVerifySlot
                        .. " — activate it in My Builds before resetting")
                    Print("|cff4dff80Nexus:|r first run saved to Saved Build "
                        .. tostring(saveVerifySlot)
                        .. ". Activate that slot in My Builds before starting the next run.")
                else
                    SetStatus("Save complete — server confirmed Active Loadout "
                        .. saveVerifySlot)
                end
                NexusDB.lastSaveStatus = {
                    state = "confirmed", slot = saveVerifySlot,
                    t = date and date("%H:%M:%S") or "",
                    summary = saveVerifySummary or "",
                }
                saveVerifySlot, seedVerify, saveVerifySnap = nil, nil, nil
                saveVerifyExpectedActive, saveVerifySummary, saveVerifyName =
                    nil, nil, nil
                saveObserveIndex, saveObserveReadyAt = 1, nil
            end
        elseif not saveObserveSchedule[saveObserveIndex] then
            AppendAudit("SAVE_UNCONFIRMED", {
                targetSlot = saveVerifySlot,
                activeSlot = freshSlots and freshSlots.activeSlot or 0,
                candidate = CopyCounts(saveVerifySnap and saveVerifySnap.byFamily),
                summary = saveVerifySummary or "",
                reason = "no exact spell/stack match after 30 seconds; no retry sent",
            })
            if seedVerify then
                SetStatus("First run not confirmed — save it manually in My Builds before resetting")
                Print("|cffff9040Nexus:|r I couldn't confirm that your first completed run was stored in Saved Build "
                    .. tostring(saveVerifySlot)
                    .. ". Open Echo Journal > My Builds and save this finished loadout into a slot before resetting.")
            else
                SetStatus("Save complete — immediate readback was non-canonical")
            end
            NexusDB.lastSaveStatus = {
                state = seedVerify and "first_run_unconfirmed" or "saved_unverified",
                slot = saveVerifySlot,
                name = saveVerifyName or "",
                t = date and date("%H:%M:%S") or "",
                summary = saveVerifySummary or "",
            }
            -- Timeout uncertainty never authorizes a second write.
            saveVerifySlot, seedVerify, saveVerifySnap = nil, nil, nil
            saveVerifyExpectedActive, saveVerifySummary, saveVerifyName =
                nil, nil, nil
            saveObserveIndex, saveObserveReadyAt = 1, nil
        else
            SetStatus(string.format(
                "Save sent to Active Loadout %d — checking server (+%.0fs)",
                saveVerifySlot, due or elapsed))
        end
    end
end

local function DispatchLevelStep(level, plan, slots, owned, flags,
                                 disabledLevers, static, locked)
    if level == 1 then
        StepArm(level, plan, owned, slots, disabledLevers, static, locked)
        if plan.advisorOnly then
            SetStatus("No wishlist set -- advisor only")
        end
    elseif level >= 2 and level < 80 then
        StepRun(level, plan, slots, owned, flags, disabledLevers, static,
            locked)
    elseif level == 80 then
        -- A run is complete when the current rolled loadout reaches the
        -- server's 79-Echo capacity. Do not use an arbitrary no-board delay:
        -- board frames can disappear briefly between chained selections.
        -- Locked Echoes are not included in owned.total.
        local rolledTotal = tonumber(owned and owned.total) or 0
        if owned and owned.synced and rolledTotal >= 79 then
            StepSave(level, plan, slots, owned, static, locked)
        else
            local board = Adapter.Board()
            if board then
                StepRun(level, plan, slots, owned, flags, disabledLevers,
                    static, locked)
            elseif Adapter.InFlight() then
                SetStatus("finishing final Echo selections")
            else
                SetStatus(string.format("finishing run — %d/79 Echoes",
                    rolledTotal))
            end
        end
    end
end

local function Step(work)
    local compileBefore, reuseBefore
    work, compileBefore, reuseBefore = BeginStepContext(work)
    local level = Adapter.Level()
    work.observedLevel = level
    HandleLevelTransition(level, work.runBoundaryGeneration)
    local static = MeasurePhase("static", StaticContext,
        work.staticProbe, work.forceCompile)
    FinishStepContext(compileBefore, reuseBefore)
    local catalog = static.catalog
    if not catalog then
        SetStatus("waiting for ProjectEbonhold")
        MeasurePhase("overlayRender", RenderIdlePanel,
            nil, nil, nil, nil, static)
        return
    end
    local wishlist = static.wishlist
    ShowQuickStartOnce(wishlist)
    local plan = static.plan
    local catalogRevision = CatalogRevision()
    local slots = ReadProjection("slots", catalogRevision, level,
        Adapter.Slots)
    local owned = ReadProjection("owned", catalogRevision, level,
        Adapter.Owned)
    local locked = Adapter.LockedOwned
        and ReadProjection("locked", catalogRevision, level,
            Adapter.LockedOwned)
        or nil
    local flags = EffectiveFlags()
    local disabledLevers = ReadProjection("levers", catalogRevision, level,
        Adapter.DisabledLevers)
    if not RunAutoLockStep(work, owned, catalog, slots, wishlist, static,
        locked) then return end
    ClearStaleDemotions()
    ObservePendingSave(catalog)
    DispatchLevelStep(level, plan, slots, owned, flags, disabledLevers,
        static, locked)
end

------------------------------------------------------------------------
-- Journal tab data provider
------------------------------------------------------------------------

local function JournalData()
    local catalog = Adapter.Catalog()
    local wishlist = Adapter.Wishlist()
    local plan = Strategy.Compile(catalog, WishlistWithLockTargets(wishlist, catalog), Store.Settings())
    local owned = Adapter.Owned()
    local slots = Adapter.Slots()
    local flags = EffectiveFlags()
    local disabledLevers = Adapter.DisabledLevers()
    local sections = {}

    if not wishlist then
        local note = Adapter.WishlistNote and Adapter.WishlistNote()
        sections[#sections + 1] = { title = "Target", lines = {
            "No wishlist set -- advisor only.",
            note or "Design a build with 'New Wishlist' (the Echo Wishlist section).",
        } }
    else
        local ownedN, pending, filler = 0, {}, {}
        for fam in pairs(plan.wishedFamilies) do
            if (owned.byFamily[fam] or 0) > 0 then ownedN = ownedN + 1
            else pending[#pending + 1] = catalog.familyName[fam] or fam end
        end
        local activeRow = ActiveSlotRow(slots)   -- genuinely-verified only
        if activeRow then
            local seen = {}
            for _, e in ipairs(activeRow.echoes) do
                if not plan.wishedFamilies[e.family] and not seen[e.family] then
                    seen[e.family] = true
                    filler[#filler + 1] = catalog.familyName[e.family] or e.family
                end
            end
        end
        table.sort(pending); table.sort(filler)
        local famN = 0
        for _ in pairs(plan.wishedFamilies) do famN = famN + 1 end
        local srcTag = (wishlist.source == "designed" and " (Echo Wishlist build)")
            or (wishlist.source == "active" and " (active loadout)") or ""
        local lines = {
            string.format("Wishlist '%s'%s: %d families -- %d owned, %d pending, %d filler in snapshot",
                wishlist.name, srcTag, famN, ownedN, #pending, #filler),
        }
        sections[#sections + 1] = { title = "Target", lines = lines }
        sections[#sections + 1] = { title = "Pending (" .. #pending .. ")", lines = pending }
        local fillerLines = {}
        for _, f in ipairs(filler) do
            fillerLines[#fillerLines + 1] = f .. (flags.DISABLE_SUPPRESSES_GUARANTEE
                and "  (shed via disable or skip)" or "  (will shed next run)")
        end
        sections[#sections + 1] = { title = "Lingering filler", lines = fillerLines }
    end

    local leverLines = {}
    for _, lever in ipairs(plan.leverPlan.disable) do
        leverLines[#leverLines + 1] = string.format("lever %d: disable%s", lever,
            disabledLevers[lever] and " (done)" or "")
    end
    for _, lever in ipairs(plan.leverPlan.skippedNonConformant) do
        leverLines[#leverLines + 1] = string.format("lever %d: skipped (non-conformant data)", lever)
    end
    sections[#sections + 1] = { title = "Tome levers", lines = leverLines }
    local est = "no estimate (advisor mode)"
    if wishlist then
        local activeRow = ActiveSlotRow(slots)
        local queue = Ratchet.PredictQueue(activeRow and activeRow.echoes or {},
            owned, plan, flags, disabledLevers, catalog)
        local e = Ratchet.RunsEstimate(plan, owned, queue, nil)
        est = (e and e.text) or "estimate unavailable"
    end
    sections[#sections + 1] = { title = "Notes", lines = {
        "Targets the ACTIVE loadout (journal 'Play with...'), not designed slots.",
        est,
    } }
    return { sections = sections, version = Nexus.VERSION }
end

local function ScheduleKnownDeadlines()
    local now = GetTime()
    if Adapter.TomeMutationResumeAt then
        local resumeAt = Adapter.TomeMutationResumeAt()
        if resumeAt and resumeAt > now then RequestStepAt(resumeAt) end
    end
    if externalPauseUntil and externalPauseUntil > now then
        RequestStepAt(externalPauseUntil)
    end
    if actionIntent then
        if actionIntent.state == "prepared"
            and actionIntent.readyAt and actionIntent.readyAt > now then
            RequestStepAt(actionIntent.readyAt)
        elseif (actionIntent.state == "submitted"
                or actionIntent.state == "uncertain")
            and actionIntent.expiresAt and actionIntent.expiresAt > now then
            RequestStepAt(actionIntent.expiresAt)
        end
    end
    if saveVerifySlot then
        if saveObserveReadyAt and saveObserveReadyAt > now then
            RequestStepAt(saveObserveReadyAt)
        else
            local due = saveObserveSchedule[saveObserveIndex]
            local when = due and ((saveVerifyAt or now) + due) or nil
            if when then
                RequestStepAt(when > now and when or (now + POLL))
            end
        end
    end
    if autoUnlockContextKey and autoUnlockContextSince
        and (autoUnlockContextSince + 2) > now then
        RequestAutoLockAt(autoUnlockContextSince + 2)
    end
end

local function RunFullStep(trigger, errorSource, work)
    if type(work) ~= "table" then
        work = {staticProbe=true,forceCompile=true,autoLockDue=true}
    end
    trigger = trigger or "other"
    work.trigger = work.trigger or trigger
    forceStep = false
    lastStepContext.outcome = "running"
    recomputeStats.stepAttempts = recomputeStats.stepAttempts + 1
    local ok, err
    local performance = Nexus and Nexus.Performance
    if performance and type(performance.Measure) == "function" then
        ok, err = pcall(performance.Measure, "automation.step", Step, work)
    else
        ok, err = pcall(Step, work)
    end
    if not ok then
        if performance and type(performance.CancelAutomationStep) == "function" then
            pcall(performance.CancelAutomationStep)
        end
        recomputeStats.stepFailures = recomputeStats.stepFailures + 1
        lastStepContext.outcome = "failed"
        SetStatus("error (see /nexus err)")
        RecordError(errorSource or "Main.Step", err)
        return false
    end
    lastFullStepAt = GetTime()
    recomputeStats.fullSteps = recomputeStats.fullSteps + 1
    recomputeStats[trigger] = (recomputeStats[trigger] or 0) + 1
    local triggerKey = fullStepTriggers[trigger] ~= nil and trigger or "other"
    fullStepTriggers[triggerKey] = fullStepTriggers[triggerKey] + 1
    lastStepContext.outcome = "completed"
    AdvanceFallbackDynamicBaseline(work.observedLevel)
    ScheduleKnownDeadlines()
    return true
end

local function MergeDirtyMasks(left, right)
    left, right = tonumber(left) or 0, tonumber(right) or 0
    local merged = 0
    local flag = 1
    while flag <= 16 do
        if math.floor(left / flag) % 2 == 1
            or math.floor(right / flag) % 2 == 1 then
            merged = merged + flag
        end
        flag = flag * 2
    end
    return merged
end

local function CaptureStepRetry(work, levelEvents)
    stepRetry.pending = true
    stepRetry.trigger = work.trigger or "other"
    stepRetry.dirtyMask = tonumber(work.dirtyMask) or 0
    stepRetry.fallbackComponent = work.fallbackComponent
    stepRetry.staticProbe = work.staticProbe and true or false
    stepRetry.forceCompile = work.forceCompile and true or false
    stepRetry.autoLockDue = work.autoLockDue and true or false
    stepRetry.runBoundaryGeneration =
        tonumber(work.runBoundaryGeneration) or 0
    stepRetry.levelEvents = math.max(0, tonumber(levelEvents) or 0)
end

local function ClearStepRetry()
    stepRetry.pending = false
    stepRetry.trigger = "other"
    stepRetry.dirtyMask = 0
    stepRetry.fallbackComponent = nil
    stepRetry.staticProbe = false
    stepRetry.forceCompile = false
    stepRetry.autoLockDue = false
    stepRetry.runBoundaryGeneration = 0
    stepRetry.levelEvents = 0
end

    local M = {}

    function M.Initialize()
        auditRunId = tonumber(NexusDB and NexusDB.auditRunCounter) or 0
        local revisions = Nexus and Nexus.Revisions
        if not catalogRevisionUnsubscribe and revisions
            and type(revisions.Subscribe) == "function" then
            catalogRevisionUnsubscribe = revisions.Subscribe(
                revisions.CATALOG_CHANGED, function()
                    if not staticProbeInProgress then RequestRecompute() end
                end)
        end
        return true
    end

    function M.RequestRecompute() return RequestRecompute() end
    function M.RequestStepAt(when) return RequestStepAt(when) end
    function M.StatusLine() return statusLine end
    function M.AutoEnabled() return autoEnabled end
    function M.AutoAllowed() return AutoAllowed() end
    function M.ToggleAuto()
        autoEnabled = not autoEnabled
        if autoEnabled then
            -- Authorization changed, represented data did not. Coalesce one
            -- bounded decision evaluation without invalidating static state.
            authorizationStepPending = true
        else
            authorizationStepPending = false
            if actionIntent and actionIntent.state == "prepared" then
                local revokedDeadline = actionIntent.readyAt
                FinishActionIntent("superseded", "authorization_changed", false)
                if revokedDeadline ~= nil and nextStepAt == revokedDeadline then
                    nextStepAt = nil
                    ScheduleKnownDeadlines()
                end
            end
        end
        return autoEnabled
    end
    function M.RecomputeStats()
        local out = {}
        for key, value in pairs(recomputeStats) do out[key] = value end
        out.fallbackMismatchFields = {}
        for key, value in pairs(fallbackMismatchFields) do
            out.fallbackMismatchFields[key] = value
        end
        out.fullStepTriggers = {}
        for key, value in pairs(fullStepTriggers) do
            out.fullStepTriggers[key] = value
        end
        out.phaseCounts = {}
        for key, value in pairs(phaseCounts) do
            out.phaseCounts[key] = value
        end
        out.lastStepContext = {}
        for key, value in pairs(lastStepContext) do
            out.lastStepContext[key] = value
        end
        out.actionLifecycle = {}
        for key, value in pairs(actionLifecycleStats) do
            out.actionLifecycle[key] = value
        end
        out.lastActionLifecycle = {}
        for key, value in pairs(lastActionLifecycle) do
            out.lastActionLifecycle[key] = value
        end
        out.autoLockLifecycle = {}
        for key, value in pairs(autoLockLifecycleStats) do
            out.autoLockLifecycle[key] = value
        end
        out.lastAutoLockLifecycle = {}
        for key, value in pairs(lastAutoLockLifecycle) do
            out.lastAutoLockLifecycle[key] = value
        end
        out.autoLockCapacity = {}
        for key, value in pairs(lastAutoLockCapacity) do
            out.autoLockCapacity[key] = value
        end
        out.autoEnabled = autoEnabled
        out.lastFallbackReason = lastFallbackReason
        if type(Adapter.EchoReconcileStats) == "function" then
            local ok, stats = pcall(Adapter.EchoReconcileStats)
            if ok and type(stats) == "table" then out.echoReconcile = stats end
        end
        if type(Adapter.LevelBurstStats) == "function" then
            local ok, stats = pcall(Adapter.LevelBurstStats)
            if ok and type(stats) == "table" then
                out.levelBurst = stats
                out.levelEvents = tonumber(stats.events) or 0
                out.levelBursts = tonumber(stats.bursts) or 0
                out.levelEventsCoalesced = tonumber(stats.coalesced) or 0
            end
        end
        out.nextStepAt = nextStepAt
        out.nextAutoLockAt = nextAutoLockAt
        out.stepRetryPending = stepRetry.pending
        out.lastFullStepAt = lastFullStepAt
        out.lastStaticProbeAt = lastStaticProbeAt
        out.lastFallbackCheckAt = lastFallbackCheckAt
        out.fallbackSeconds = FALLBACK_RECOMPUTE
        return out
    end
    function M.EffectiveFlags() return EffectiveFlags() end
    function M.LockDesignTargetsFor(wishlist)
        return LockDesignTargetsFor(wishlist)
    end
    function M.WishlistWithLockTargets(wishlist, catalog)
        return WishlistWithLockTargets(wishlist, catalog)
    end
    function M.WishlistProgress(plan, owned, catalog, lockOnlyFamilies, wishlist)
        return WishlistProgress(plan, owned, catalog, lockOnlyFamilies, wishlist)
    end
    function M.LastAutoLockTrace() return lastAutoLockTrace end
    function M.RetryAutoLock() return RequestAutoLockRetry() end
    function M.AuditRunId() return auditRunId end
    function M.ResetAuditState()
        lastLoggedSig = nil
        auditRunStarted = nil
        auditRunId = 0
    end
    function M.JournalData() return JournalData() end
    function M.RunFullStep(trigger, errorSource)
        return RunFullStep(trigger, errorSource)
    end
    local function RunUpdate(elapsed)
        pollAccum = pollAccum + (elapsed or 0)
        if pollAccum < POLL then return end
        pollAccum = 0
        recomputeStats.polls = recomputeStats.polls + 1
        local performance = Nexus and Nexus.Performance
        local startedAt
        if performance and type(performance.Begin) == "function" then
            local okStarted, value = pcall(performance.Begin,
                "gameadapter.poll")
            if okStarted then startedAt = value end
        end
        local okPoll, errPoll = pcall(Adapter.Poll)
        if startedAt and performance and type(performance.Finish) == "function" then
            pcall(performance.Finish, "gameadapter.poll", startedAt)
        end
        if not okPoll then
            recomputeStats.pollFailures = recomputeStats.pollFailures + 1
            SetStatus("error (see /nexus err)")
            RecordError("GameAdapter.Poll", errPoll)
            return
        end

        local boardDirty, slotsDirty, dataDirty, autoLockDirty =
            false, false, false, false
        local staticDependencyDirty = false
        local levelEvents = 0
        local runBoundaryGeneration = 0
        if Adapter.ConsumeDirty then
            local okDirty, board, slots, data, lock,
                slotsRevision, activeSlotRevision,
                grantedRevision, ownedRevision,
                lockedRevision, lockedLocalRevision,
                discoveryRevision, leverRevision,
                staticDirty
            okDirty, board, slots, data, lock,
                slotsRevision, activeSlotRevision,
                grantedRevision, ownedRevision,
                lockedRevision, lockedLocalRevision,
                discoveryRevision, leverRevision,
                staticDirty, levelEvents, runBoundaryGeneration =
                    pcall(Adapter.ConsumeDirty)
            if okDirty then
                boardDirty, slotsDirty, dataDirty = board and true or false,
                    slots and true or false, data and true or false
                autoLockDirty = lock and true or false
                if lock == nil then
                    autoLockDirty = slotsDirty or dataDirty
                end
                UpdateProjectionRevisions(slotsRevision, activeSlotRevision,
                    grantedRevision, ownedRevision,
                    lockedRevision, lockedLocalRevision,
                    discoveryRevision, leverRevision)
                staticDependencyDirty = staticDirty == true
                    or (staticDirty == nil
                        and type(slotsRevision) ~= "number" and dataDirty)
            else
                UpdateProjectionRevisions()
                forceStep = true
                staticInvalidated = true
                RecordError("GameAdapter.ConsumeDirty", board)
            end
        end
        local now = GetTime()
        local boundaryDirty = type(runBoundaryGeneration) == "number"
            and runBoundaryGeneration > lastRunBoundaryGeneration
        local retrying = stepRetry.pending
        local isDirty = boardDirty or slotsDirty or dataDirty or boundaryDirty
        local deadlineDue = nextStepAt ~= nil and now >= nextStepAt
        local autoLockDeadlineDue = nextAutoLockAt ~= nil
            and now >= nextAutoLockAt
        local fallbackDue = (now - lastFallbackCheckAt) >= FALLBACK_RECOMPUTE
        local fallbackRepair = false
        local fallbackMismatch = nil
        local fallbackSnapshot = nil
        local fallbackStatic = false
        if fallbackDue then
            local performance = Nexus and Nexus.Performance
            if performance and type(performance.Measure) == "function" then
                fallbackRepair, fallbackMismatch, fallbackSnapshot = performance.Measure(
                    "automation.fallback.check", FallbackNeedsRepair, now)
            else
                fallbackRepair, fallbackMismatch, fallbackSnapshot =
                    FallbackNeedsRepair(now)
            end
            if fallbackRepair and projectionRevisions.valid
                and type(fallbackSnapshot) == "table" then
                UpdateProjectionRevisions(
                    fallbackSnapshot.slots, fallbackSnapshot.activeSlot,
                    fallbackSnapshot.granted, projectionRevisions.owned,
                    fallbackSnapshot.locked, projectionRevisions.lockedLocal,
                    fallbackSnapshot.discovery, projectionRevisions.levers)
            end
            if not fallbackRepair and not (forceStep
                or authorizationStepPending or isDirty or autoLockDirty
                or deadlineDue or autoLockDeadlineDue or retrying) then
                recomputeStats.skipped = recomputeStats.skipped + 1
                return
            end
            fallbackStatic = fallbackRepair
                and FALLBACK_STATIC_COMPONENTS[fallbackMismatch] == true
            if fallbackStatic then staticInvalidated = true end
        end
        if not (forceStep or authorizationStepPending
            or isDirty or autoLockDirty or deadlineDue
            or autoLockDeadlineDue or fallbackRepair or retrying) then
            recomputeStats.skipped = recomputeStats.skipped + 1
            return
        end
        if deadlineDue then nextStepAt = nil end
        if autoLockDeadlineDue then nextAutoLockAt = nil end
        local forced = forceStep
        local authorizationRequested = authorizationStepPending
        authorizationStepPending = false
        local freshTrigger = forceStep and "forced"
            or fallbackRepair and "fallbacks"
            or (isDirty or autoLockDirty) and "dirty"
            or (deadlineDue or autoLockDeadlineDue) and "deadlines"
            or authorizationRequested and "explicit"
            or nil
        local trigger = freshTrigger
            or (retrying and stepRetry.trigger)
            or "fallbacks"
        local repairStarted
        local performance = Nexus and Nexus.Performance
        if fallbackRepair and performance
            and type(performance.Begin) == "function" then
            local okStarted, value = pcall(performance.Begin,
                "automation.fallback.repair")
            if okStarted then repairStarted = value end
        end
        local burstRenderBefore = phaseCounts.overlayRender
        local burstAutoLockBefore = autoLockLifecycleStats.submitted
            + autoLockLifecycleStats.rejected
        local work = {
            trigger=trigger,
            dirtyMask=(boardDirty and 1 or 0)
                + (slotsDirty and 2 or 0)
                + (dataDirty and 4 or 0)
                + (autoLockDirty and 8 or 0)
                + (boundaryDirty and 16 or 0),
            fallbackComponent=fallbackMismatch,
            staticProbe=staticInvalidated or forced or slotsDirty
                or staticDependencyDirty or fallbackStatic,
            forceCompile=forced,
            autoLockDue=forced or slotsDirty or dataDirty
                or autoLockDirty or autoLockDeadlineDue or fallbackRepair,
            runBoundaryGeneration=runBoundaryGeneration,
        }
        local retryLevelEvents = 0
        if retrying then
            retryLevelEvents = stepRetry.levelEvents
            work.dirtyMask = MergeDirtyMasks(
                work.dirtyMask, stepRetry.dirtyMask)
            work.fallbackComponent = work.fallbackComponent
                or stepRetry.fallbackComponent
            work.staticProbe = work.staticProbe or stepRetry.staticProbe
            work.forceCompile = work.forceCompile or stepRetry.forceCompile
            work.autoLockDue = work.autoLockDue or stepRetry.autoLockDue
            work.runBoundaryGeneration = math.max(
                tonumber(work.runBoundaryGeneration) or 0,
                tonumber(stepRetry.runBoundaryGeneration) or 0)
            ClearStepRetry()
            recomputeStats.stepRetries = recomputeStats.stepRetries + 1
        end
        local stepSucceeded = RunFullStep(trigger, "Main.Step", work)
        if not stepSucceeded then
            if retrying then
                recomputeStats.stepRetryExhausted =
                    recomputeStats.stepRetryExhausted + 1
            else
                CaptureStepRetry(work, levelEvents)
            end
        end
        local burstLevelEvents = (tonumber(levelEvents) or 0)
            + (tonumber(retryLevelEvents) or 0)
        if burstLevelEvents > 0
            and type(Adapter.RecordLevelBurstPump) == "function" then
            local burstActions = lastStepContext.actionAttempted and 1 or 0
            burstActions = burstActions
                + math.max(0, autoLockLifecycleStats.submitted
                    + autoLockLifecycleStats.rejected - burstAutoLockBefore)
            pcall(Adapter.RecordLevelBurstPump, burstLevelEvents,
                stepSucceeded and 1 or 0,
                math.max(0, phaseCounts.overlayRender - burstRenderBefore),
                burstActions)
        end
        if repairStarted and performance
            and type(performance.Finish) == "function" then
            pcall(performance.Finish, "automation.fallback.repair", repairStarted, {
                trigger="fallback",
                mismatch=fallbackMismatch,
            })
        end
    end

    function M.OnUpdate(elapsed)
        local performance = Nexus and Nexus.Performance
        if performance and type(performance.Measure) == "function" then
            return performance.Measure("automation.update", RunUpdate, elapsed)
        end
        return RunUpdate(elapsed)
    end

    return M
end
