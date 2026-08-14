-- Nexus: core/Main.lua
-- Bootstrap + the decision loop. Wires adapter reads -> pure logic ->
-- adapter actions. Owns the OnUpdate cadence, the lifecycle FSM
-- (LOAD / ARM@L1 / RUN / SAVE@L80), auto-pick pacing, the runtime
-- self-checks (flag demotions), and the slash commands.
-- SCOPING RULE: every closure-captured local is declared here, before
-- any closure that reads it.

Nexus = Nexus or {}
Nexus.VERSION = (Nexus.Release and Nexus.Release.version) or "1.20.0-beta.1"

local Model, Policy, Ratchet, Strategy, Store, Adapter
local Readout, Panel, JournalTab, DefaultProfile
local initialized = false
local autoEnabled = false          -- session-level master switch (panel button / slash)
local quickStartChecked = false   -- one-time-per-session guard for the quick-start check
local pollAccum = 0
local POLL = 0.2
-- GameAdapter's dirty flags and explicit action deadlines are the primary
-- invalidation path. The short heartbeat is retained while a run is active to
-- recover a private-server event the client failed to deliver. At level 80 it
-- is only a last-resort recovery path: running the complete automation and HUD
-- pipeline every five seconds caused a visible 0.4-0.9s hitch while idle.
local FALLBACK_RECOMPUTE = 5
local IDLE_FALLBACK_RECOMPUTE = 300
local nextStepAt = nil
local lastFullStepAt = -math.huge
local forceStep = true
local recomputeStats = {
    polls=0, fullSteps=0, skipped=0, dirty=0,
    deadlines=0, fallbacks=0, forced=0, explicit=0,
}

-- Lag / addon interference detection
-- If the OnUpdate frame time jumps significantly above the poll cadence,
-- another addon is probably blocking the main thread. We report in chat
-- once per minute at most, so it's informative but not spammy.
local lagWarnedAt    = -math.huge
local LAG_THRESHOLD  = 1.5    -- seconds; a single frame stall this long is suspicious
local LAG_WARN_COOLDOWN = 60  -- seconds between chat warnings

-- ARM state
local armAttempts, armedConfirmed, armPendingSince = 0, false, nil
local armTargetSlot = nil
local boardsSinceArm = 0
local leversDoneThisVisit = {}
local lastLeverSendAt = 0

-- RUN state
local lastDecidedSig, lastDecision, decidedAt = nil, nil, nil
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
local demotionsClearedThisSession = false

local statusLine = "loading"
local EH  -- event frame
local lastPanelInput = nil
local hudSnapshotStats = { builds=0, refreshes=0 }

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff7fd5ffNexus:|r " .. tostring(msg))
end

local function ErrorText(value)
    local errors = Nexus and Nexus.Errors
    if errors and type(errors.SafeText) == "function" then
        local ok, text = pcall(errors.SafeText, value)
        if ok and type(text) == "string" then return text end
    end
    local ok, text = pcall(tostring, value)
    return ok and text or "<unprintable error>"
end

local function RecordError(source, value)
    local errors = Nexus and Nexus.Errors
    if errors and type(errors.Record) == "function" then
        local ok = pcall(errors.Record, source, value)
        if ok then return end
    end
    Nexus.lastError = ErrorText(value)
end

local function SetStatus(s)
    if s ~= statusLine then
        statusLine = s
        if Panel and type(Panel.SetStatus) == "function" then
            pcall(Panel.SetStatus, s)
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

local function RequestRecompute()
    forceStep = true
    return true
end

local function FallbackSeconds()
    local level = Adapter and type(Adapter.Level) == "function"
        and tonumber(Adapter.Level()) or 0
    return level >= 80 and IDLE_FALLBACK_RECOMPUTE or FALLBACK_RECOMPUTE
end

local function Measure(name, callback, ...)
    local performance = Nexus and Nexus.Performance
    if performance and type(performance.Measure) == "function" then
        return performance.Measure(name, callback, ...)
    end
    return callback(...)
end

Nexus.RequestRecompute = RequestRecompute

function Nexus.RecomputeStats()
    local out = {}
    for key, value in pairs(recomputeStats) do out[key] = value end
    out.nextStepAt = nextStepAt
    out.lastFullStepAt = lastFullStepAt
    out.fallbackSeconds = FallbackSeconds()
    return out
end

-- Diagnostic-only retained history. These records never participate in
-- decisions; they exist solely to explain guarantee behavior and save gates.
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

local function AppendAudit(kind, fields)
    local logs = Nexus.DiagnosticLogs
    if not (logs and type(logs.Append) == "function") then return false end
    local e = {}
    if type(fields) == "table" then
        for key, value in pairs(fields) do e[key] = value end
    end
    e.kind = kind
    e.t = date and date("%H:%M:%S") or ""
    e.run = auditRunId
    return logs.Append("runAudit", e)
end
Nexus.AppendAudit = AppendAudit

-- Same bounded-history pattern as AppendAudit, for TryAutoLock's actual
-- LockPerk/UnlockPerk attempts specifically. lastAutoLockTrace (see
-- TryAutoLock) is rebuilt every poll tick and only ever holds the MOST
-- RECENT tick's reasoning -- fine for "why isn't this firing right now",
-- useless for reconstructing what happened over an entire test run, since
-- whatever a full diagnostic export captures is only whatever the last tick
-- before the export happened to look like. This keeps every actual write
-- attempt (not the far more frequent no-op ticks) so a full run's lock/
-- unlock sequence survives to be reviewed after the fact.
local function AppendAutoLockEvent(fields)
    local logs = Nexus.DiagnosticLogs
    if not (logs and type(logs.Append) == "function") then return false end
    local e = {}
    if type(fields) == "table" then
        for key, value in pairs(fields) do e[key] = value end
    end
    e.t = date and date("%H:%M:%S") or ""
    return logs.Append("autoLock", e)
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

local function ActiveSlotRow(slots)
    if not slots or slots.activeSlot == 0 then return nil end
    local s = slots.bySlot[slots.activeSlot]
    if s and s.verified and s.verifiedFieldPresent and not s.suspectParse then
        return s
    end
    return nil
end

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
local QUALITY_NAMES = { [0]="Common", [1]="Uncommon", [2]="Rare", [3]="Epic" }
local function QualityName(q) return QUALITY_NAMES[q] or ("q"..q) end

-- Families present in the compiled plan only because a locked-slot design
-- target (NexusDB.lockDesignTargets, via WishlistWithLockTargets) added
-- them -- not because the real, saved wishlist asked for them. These don't
-- belong in the 79-slot run total: the server's guaranteed-loadout cap is
-- real and fixed, while a locked Echo only ever needs to be rolled ONCE,
-- ever, and then never again. Keeping them out of stackTotal/stackCount
-- keeps the panel's "N / 79" honest; WishlistProgress instead reports them
-- separately as "toLock" so the player still sees what's left to acquire.
local function LockOnlyFamilies(plan, wishlist)
    local out = {}
    if type(plan) ~= "table" or type(plan.wishedFamilies) ~= "table" then return out end
    local realFamilies = (type(wishlist) == "table" and wishlist.byFamily) or {}
    for fam in pairs(plan.wishedFamilies) do
        if not realFamilies[fam] then out[fam] = true end
    end
    return out
end

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
local function LockSlotKey(wishlist)
    local echoes = type(wishlist) == "table" and (wishlist.entries or wishlist.echoes) or nil
    return (Adapter and Adapter.WishlistKey and Adapter.WishlistKey(echoes)) or 0
end

-- NexusDB is ACCOUNT-WIDE (## SavedVariables has no "PerCharacter"), same as
-- every other addon's plain SavedVariables -- a Dev Test 42-47 bucket keyed
-- ONLY by wl.slot collided across different characters on the same account
-- whenever two characters happened to have a wishlist at the same server
-- slot number (reported live: a design from "my other character" showing up
-- on a brand-new wishlist here). Store.State() is this codebase's existing,
-- already-battle-tested per-character subtable (NexusDB.chars[UnitName()],
-- with the same "never latch a bad key before UnitName is ready" handling
-- Store.lua already does for everything else) -- nesting the per-slot
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
local function LockDesignTargetsFor(wishlist)
    local state = Store.State()
    if type(state) ~= "table" then return nil end
    local old = NexusDB and NexusDB.lockDesignTargets
    if type(old) == "table" then
        state.lockDesignTargetsBySlot = state.lockDesignTargetsBySlot or {}
        local key = LockSlotKey(wishlist)
        if not state.lockDesignTargetsBySlot[key] then
            state.lockDesignTargetsBySlot[key] = old
        end
        NexusDB.lockDesignTargets = nil
    end
    local bySlot = state.lockDesignTargetsBySlot
    local key = LockSlotKey(wishlist)
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
    local stackTotal, stackCount, missing, toLock = 0, 0, {}, {}
    if type(plan) ~= "table" or type(plan.wishedFamilies) ~= "table" then
        return 0, 0, missing, toLock
    end
    lockOnlyFamilies = lockOnlyFamilies or {}
    local targets = type(plan.targets) == "table" and plan.targets or {}
    local byFamily = (type(owned) == "table" and owned.byFamily) or {}
    local bySpell  = (type(owned) == "table" and owned.bySpell)  or {}
    -- A family fully covered by locked (permanent) Echoes is dropped from
    -- both the total and the owned count entirely -- the same "remove, don't
    -- reserve a slot for it" treatment WishlistEditor.LoadPendingEchoes gives
    -- it when saving. Without this, the live server wishlist (which still
    -- contains locked-duplicate entries until the player actually saves a
    -- trimmed version in the editor) makes the panel's total read higher
    -- than what the editor already shows as the real, current target.
    local lockedByFamily, lockedBySpell = {}, {}
    if Adapter and Adapter.LockedOwned then
        local locked = Adapter.LockedOwned()
        if locked and type(locked.byFamily) == "table" then lockedByFamily = locked.byFamily end
        if locked and type(locked.bySpell) == "table" then lockedBySpell = locked.bySpell end
    end

    -- A designed locked slot remains a TO LOCK requirement until the exact
    -- spellId is confirmed by GetLockedPerks(), whether that Echo is also a
    -- normal 79-slot wishlist entry or exists only as a synthetic lock target.
    -- Previously only synthetic lock-only families reached this list, so a
    -- normal wishlist entry tagged lockIntent (the editor's usual path) showed
    -- under STILL NEEDED but gave no HUD indication that it must also be locked.
    local seenToLock = {}
    local designTargets = LockDesignTargetsFor(wishlist)
    if type(designTargets) == "table" then
        local rows = catalog and catalog.rows or {}
        for spellIdKey in pairs(designTargets) do
            local id = tonumber(spellIdKey)
            if id and not seenToLock[id] and (tonumber(lockedBySpell[id]) or 0) <= 0 then
                local row = rows[id]
                toLock[#toLock + 1] = tostring((row and row.name) or ("spell " .. tostring(id)))
                seenToLock[id] = true
            end
        end
    end

    -- Coverage is counted per EXACT spellId (Ratchet.WantedExact/ExactCoverage),
    -- the same identity the save gate uses. Counting by family here made a
    -- forced Uncommon sibling read as one of the Rare copies the wishlist asked
    -- for, so STILL NEEDED and the save gate contradicted each other on the
    -- same run -- see the Ratchet.lua header for the live 2026-08-02 case.
    for fam in pairs(plan.wishedFamilies) do
        local target = targets[fam]
        local famExact = Ratchet.TargetExact(target)
        local have, want = Ratchet.ExactCoverage(famExact, bySpell)
        local lockedHave = Ratchet.ExactCoverage(famExact, lockedBySpell)
        if want <= 0 then
            -- Malformed/absent target: degrade to family granularity rather
            -- than silently dropping the family out of the "N / 79" total.
            want = (type(target) == "table" and tonumber(target.targetStacks)) or 1
            have = math.min(tonumber(byFamily[fam]) or 0, want)
            lockedHave = tonumber(lockedByFamily[fam]) or 0
        end
        if lockedHave >= want then
            -- Fully satisfied by a permanent lock -- not part of the active
            -- target set anymore, same as an editor save would treat it.
        elseif lockOnlyFamilies[fam] then
            -- A locked-slot design target, not a real wishlist entry -- keep
            -- it out of the 79 total entirely. Its exact spellId is reported
            -- in TO LOCK above until LockedOwned() confirms the permanent lock,
            -- including the short window after acquisition but before locking.
        else
        stackTotal = stackTotal + want
        stackCount = stackCount + have
        if have < want then
            local nm = catalog and catalog.familyName and catalog.familyName[fam]
            local remain = want - have
            local tiers = type(target) == "table" and target.qualityTiers
            if tiers and #tiers > 1 then
                -- Exact per-tier counts, so the parts always sum to `remain`.
                local tierParts = {}
                for _, tier in ipairs(tiers) do
                    local ownedThisTier = tier.spellId
                        and (tonumber(bySpell[tier.spellId]) or 0) or 0
                    local tierRemain = math.max(0,
                        (tonumber(tier.n) or 0) - ownedThisTier)
                    if tierRemain > 0 then
                        tierParts[#tierParts + 1] = QualityName(tier.q) .. ":×" .. tierRemain
                    end
                end
                local label = tostring(nm or fam) .. " ×" .. remain
                if #tierParts > 0 then
                    label = label .. " (" .. table.concat(tierParts, " ") .. ")"
                end
                missing[#missing + 1] = label
            else
                missing[#missing + 1] = tostring(nm or fam) .. (remain > 1 and (" ×" .. remain) or "")
            end
        end
        end
    end
    table.sort(missing)
    table.sort(toLock)
    return stackCount, stackTotal, missing, toLock
end

-- How many wished families the ACTIVE loadout snapshot already covers,
-- and the NAMES of the ones it's still missing -- the cross-run
-- convergence number (loadout -> ideal build), distinct from
-- WishlistProgress which is this run's owned set. Returns count, missing
-- (sorted name array); count is nil when there's no active snapshot to
-- measure against (never confused with "converged").
-- Convergence of the ACTIVE loadout snapshot toward the ideal wishlist,
-- using the SAME two units the game's own Echo Journal uses ("68
-- echo(es), 79/79 stacks"): distinct wished FAMILIES present at all
-- (familyCount/familyTotal), and total STACKS actually banked toward
-- each family's target, capped per family so extra copies past target
-- don't inflate it (stackCount/stackTotal). Family count alone
-- overstates progress -- a family sitting at 1 of 9 needed copies reads
-- as "covered" there but is nowhere near done; stackCount is the honest
-- number. Also returns the missing family NAMES (families with zero
-- copies) and the LOCKED echo names (server build-slot locks -- distinct
-- from the wishlist's own "locked" concept, these are echoes pinned in
-- the saved snapshot itself).

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

local function LoadoutCoverage(activeRow, plan, catalog)
    if type(activeRow) ~= "table" or type(activeRow.echoes) ~= "table"
        or type(plan) ~= "table" or type(plan.wishedFamilies) ~= "table" then
        return {}, nil, {}
    end
    local targets = type(plan.targets) == "table" and plan.targets or {}
    -- Exact spellId counts, matching WishlistProgress and the save gate: a
    -- wrong-quality sibling sitting in the loadout is not coverage.
    local bySpell = {}
    local locked = {}
    for i = 1, #activeRow.echoes do
        local e = activeRow.echoes[i]
        local fam = e and e.family
        local id = e and tonumber(e.spellId)
        if fam and id and plan.wishedFamilies[fam] then
            bySpell[id] = (bySpell[id] or 0) + (tonumber(e.stacks) or 1)
            if e.locked then
                local row = catalog and catalog.rows and catalog.rows[id]
                locked[#locked + 1] = (row and row.name) or ("spell " .. tostring(id))
            end
        end
    end
    local stackTotal, stackCount = 0, 0
    local missing = {}
    for fam in pairs(plan.wishedFamilies) do
        local target = targets[fam]
        local famExact = Ratchet.TargetExact(target)
        local have, want = Ratchet.ExactCoverage(famExact, bySpell)
        if want <= 0 then
            want = (type(target) == "table" and tonumber(target.targetStacks)) or 1
            have = 0
        end
        stackTotal = stackTotal + want
        stackCount = stackCount + have
        if have < want then
            local nm = catalog and catalog.familyName and catalog.familyName[fam]
            missing[#missing + 1] = nm or fam
        end
    end
    table.sort(missing)
    table.sort(locked)
    return missing, { stackCount = stackCount, stackTotal = stackTotal }, locked
end

-- Builds the one progress table every render site feeds to the panel:
-- this run's gains, the active loadout's convergence toward the ideal
-- wishlist, and the loadout's specific missing echoes (what "close to
-- ideal" actually means, not just a percentage).
local function BuildProgress(plan, owned, slots, catalog, wishlistOverride, previewBuildId)
    local wl = wishlistOverride or Adapter.Wishlist()
    local lockOnlyFamilies = LockOnlyFamilies(plan, wl)
    local runStacks, wishTotal, wishlistMissing, toLock =
        WishlistProgress(plan, owned, catalog, lockOnlyFamilies, wl)
    local loadoutMissing, loadoutStacks, locked =
        LoadoutCoverage(ActiveSlotRow(slots), plan, catalog)

    -- Build a set of families that are LOCKED in the active slot -- the
    -- player intentionally placed these and they should never appear as
    -- "to shed" even if they aren't on the wishlist.
    local lockedByFamily = {}
    if Adapter.LockedOwned then
        local lockedOwned = Adapter.LockedOwned()
        if lockedOwned and type(lockedOwned.byFamily) == "table" then
            lockedByFamily = lockedOwned.byFamily
        end
    end
    local activeRow = ActiveSlotRow(slots)
    if type(activeRow) == "table" and type(activeRow.echoes) == "table" then
        for _, e in ipairs(activeRow.echoes) do
            if e.locked and e.family then
                lockedByFamily[e.family] = (lockedByFamily[e.family] or 0)
                    + (tonumber(e.stacks) or 1)
            end
        end
    end

    -- Shed echoes at EXACT spell/quality granularity. The server persists and
    -- guarantees exact spell IDs, so a Common Agility Boost cannot be hidden
    -- behind the family's requested Rare copy. Wrong-quality siblings and
    -- exact over-stacks are listed independently. Locked exact copies remain
    -- protected even when they are outside the current wishlist.
    local shed = {}
    if type(plan) == "table" and type(owned) == "table"
        and type(owned.bySpell) == "table" then
        local wantedExact, lockedExact = Ratchet.WantedExact(plan), {}
        if type(activeRow) == "table" and type(activeRow.echoes) == "table" then
            for _, e in ipairs(activeRow.echoes) do
                if e.locked and tonumber(e.spellId) then
                    local id = tonumber(e.spellId)
                    lockedExact[id] = (lockedExact[id] or 0)
                        + math.max(1, tonumber(e.stacks or e.count or e.stack) or 1)
                end
            end
        end
        local qualityNames = { [0] = "Common", [1] = "Uncommon", [2] = "Rare", [3] = "Epic" }
        for id, count in pairs(owned.bySpell) do
            local keepCount = math.max(tonumber(wantedExact[id]) or 0,
                tonumber(lockedExact[id]) or 0)
            local shedCount = math.max(0, (tonumber(count) or 0) - keepCount)
            if shedCount > 0 then
                local row = catalog and catalog.rows and catalog.rows[id]
                local nm = row and row.name or ("spell " .. tostring(id))
                local q = row and tonumber(row.quality)
                local label = q ~= nil and qualityNames[q] or nil
                shed[#shed + 1] = tostring(nm)
                    .. (label and (" (" .. label .. ")") or "")
                    .. (shedCount > 1 and (" ×" .. shedCount) or "")
            end
        end
        table.sort(shed)
    end

    -- Find the WR Build that matches the WISHLIST (not the exact owned
    -- set). This is what the player is working toward, so the panel
    -- shows DPS numbers even when the run isn't complete yet.
    local matchedBuildId = nil
    local D = Nexus.DpsCapture
    if D and D.FindMatchingBuildPublic and wl then
        -- Try wishlist-based match first (works mid-run)
        matchedBuildId = D.FindMatchingBuildPublic(wl)
    end

    local wishlistEchoes = wl and (wl.echoes or wl.entries) or nil
    -- Tome readiness must include designed lock targets that live outside the
    -- saved 79-slot wishlist. They are real automation targets in `plan`, so
    -- omitting them here made the HUD claim the roll pool was ready when a
    -- locked-slot Echo was still gated behind an unknown tome.
    local tomeEchoes, seenTomeEcho = {}, {}
    for _, e in ipairs(wishlistEchoes or {}) do
        tomeEchoes[#tomeEchoes + 1] = e
        local id = tonumber(e and (e.spellId or e.id))
        if id then seenTomeEcho[id] = true end
    end
    local tomeDesignTargets = LockDesignTargetsFor(wl)
    if type(tomeDesignTargets) == "table" then
        for spellIdKey in pairs(tomeDesignTargets) do
            local id = tonumber(spellIdKey)
            if id and not seenTomeEcho[id] then
                tomeEchoes[#tomeEchoes + 1] = { spellId = id }
                seenTomeEcho[id] = true
            end
        end
    end
    local unknownTomes = Adapter.UnknownTomesForEchoes and Adapter.UnknownTomesForEchoes(tomeEchoes) or {}
    return { owned = runStacks, total = wishTotal, missing = wishlistMissing, unknownTomes = unknownTomes,
        loadoutMissing = loadoutMissing, loadoutStacks = loadoutStacks, locked = locked, shed = shed,
        toLock = toLock,
        wishlistName = wl and ((wl.name ~= "" and wl.name) or "(unnamed)") or nil,
        activeSlot = activeRow and tonumber(activeRow.slot) or 0,
        matchedBuildId = matchedBuildId, previewBuildId = previewBuildId,
        dpsEchoes = wishlistEchoes,
        isCommunityPreview = previewBuildId and true or false }
end


local function BuildPanelProgressUnmeasured(activePlan, owned, slots, catalog)
    local C = Nexus.CommunityBuilds
    local build = C and C.GetSelectedBuildForPanel and C.GetSelectedBuildForPanel()
    if build and type(build.echoes) == "table" and #build.echoes > 0 then
        local wl = { name = build.title or "Community Build", entries = build.echoes }
        local previewPlan = Strategy.Compile(catalog, wl, Store.Settings())
        return BuildProgress(previewPlan, owned, slots, catalog, wl, build.id)
    end
    return BuildProgress(activePlan, owned, slots, catalog)
end

local function CopyDisplay(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[CopyDisplay(key, seen)] = CopyDisplay(child, seen)
    end
    return out
end

local function DisplayCall(callback, ...)
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, ...)
    return ok and value or nil
end

-- Main owns every service read used by the adaptive HUD. Panel receives only
-- this defensive display snapshot and never reaches back into data services
-- while rendering it.
local function BuildHudDisplayModel(base)
    local out = CopyDisplay(type(base) == "table" and base or {})
    out.status = statusLine
    if out.level == nil then out.level = DisplayCall(Adapter and Adapter.Level) or 0 end

    local updates = Nexus.Updates
    local notice = updates and DisplayCall(updates.GetVisibleNotice)
    out.updateNotice = CopyDisplay(notice)
    if out.updateNotice and updates then
        out.updateNotice.releaseUrl = DisplayCall(updates.ReleaseUrl)
    end

    local server = Nexus.ServerStatus
    local useServer = server and DisplayCall(server.IsUsingNexusHud)
    out.serverStatus = useServer and CopyDisplay(DisplayCall(server.GetSummary)) or nil

    local capture = Nexus.DpsCapture
    local player = UnitName and UnitName("player") or nil
    out.bestDps = {
        dummy = CopyDisplay(capture and DisplayCall(capture.GetCharacterBest, "dummy", player)),
        lk = CopyDisplay(capture and DisplayCall(capture.GetCharacterBest, "lk", player)),
        info = CopyDisplay(capture and DisplayCall(capture.GetPlayerInfo, player)),
    }
    local progress = type(out.progress) == "table" and out.progress or {}
    out.progress = progress
    local echoes = type(progress.dpsEchoes) == "table" and progress.dpsEchoes or nil
    local performance = { dummy={}, lk={} }
    if capture and echoes then
        performance.dummy.personal = CopyDisplay(DisplayCall(
            capture.GetPersonalBestForEchoes, echoes, "dummy"))
        performance.lk.personal = CopyDisplay(DisplayCall(
            capture.GetPersonalBestForEchoes, echoes, "lk"))
        local dummyRows = DisplayCall(capture.GetLeaderboardForEchoes, echoes, "dummy")
        local lkRows = DisplayCall(capture.GetLeaderboardForEchoes, echoes, "lk")
        performance.dummy.global = CopyDisplay(type(dummyRows) == "table" and dummyRows[1] or nil)
        performance.lk.global = CopyDisplay(type(lkRows) == "table" and lkRows[1] or nil)
    end
    progress.performance = performance
    hudSnapshotStats.builds = hudSnapshotStats.builds + 1
    return out
end

local function RenderPanel(base)
    lastPanelInput = CopyDisplay(base)
    return Panel.Render(Measure("automation.hud", BuildHudDisplayModel,
        lastPanelInput))
end

local function BuildPanelProgress(...)
    return Measure("automation.progress", BuildPanelProgressUnmeasured, ...)
end

function Nexus.RefreshHudView()
    if not Panel or type(Panel.Render) ~= "function" or not lastPanelInput then
        return false
    end
    hudSnapshotStats.refreshes = hudSnapshotStats.refreshes + 1
    local ok, result = pcall(Panel.Render,
        Measure("automation.hud", BuildHudDisplayModel, lastPanelInput))
    if not ok then
        RecordError("Main.RefreshHudView", result)
        return false
    end
    return result ~= false
end

function Nexus.HudSnapshotStats()
    return CopyDisplay(hudSnapshotStats)
end

-- Renders the panel with just status + progress, no board cards. Used at
-- every point in Step() where StepRun isn't running this tick (level 1,
-- level 80 with no board, or catalog not yet loaded) -- otherwise the
-- panel only ever refreshes while an echo board is live and freezes
-- showing stale leveling-era content the rest of the time, which breaks
-- both "check status at level 80" and "alt-tab between characters".
-- All args may be nil; WishlistProgress/LoadoutCoverage are null-safe.
local function RenderIdlePanel(plan, owned, slots, catalog)
    local settings = Store.Settings()
    local okAuto = AutoAllowed()
    RenderPanel({
        status = statusLine,
        cards = {},
        recommendation = "",
        progress = BuildPanelProgress(plan, owned, slots, catalog),
        level = Adapter.Level(),
        auto = autoEnabled,
        version = Nexus.VERSION,
    })
end

local function StepArm(level, plan, owned, slots, disabledLevers)
    local settings = Store.Settings()
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
    if settings.autoDisable and plan and not plan.advisorOnly
        and Adapter.DiscoverySynced()
        and not (Adapter.TomeMutationPaused
            and Adapter.TomeMutationPaused()) then
        if (GetTime() - lastLeverSendAt) <= 0.5 then
            RequestStepAt(lastLeverSendAt + 0.5)
            RenderIdlePanel(plan, owned, slots, Adapter.Catalog())
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
    RenderIdlePanel(plan, owned, slots, Adapter.Catalog())
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
-- carefully-tuned decision logic itself. A family already covered by the
-- real wishlist is left alone -- this only ADDS families the real
-- wishlist doesn't already ask for.
local function WishlistWithLockTargets(wishlist, catalog)
    local targets = LockDesignTargetsFor(wishlist)
    if type(targets) ~= "table" or not next(targets) then return wishlist end
    local rows = catalog and catalog.rows
    local familyOf = catalog and catalog.familyOf
    if type(rows) ~= "table" or type(familyOf) ~= "table" then return wishlist end

    local entries, byFamily, existingIds = {}, {}, {}
    if wishlist then
        for fam, t in pairs(wishlist.byFamily or {}) do byFamily[fam] = t end
        for _, e in ipairs(wishlist.entries or {}) do
            entries[#entries + 1] = e
            if e and e.spellId then existingIds[tonumber(e.spellId)] = true end
        end
    end

    local changed = false
    for spellIdKey in pairs(targets) do
        local id = tonumber(spellIdKey)
        local row = id and rows[id]
        local fam = id and familyOf[id]
        if id and row and fam and not existingIds[id] and not byFamily[fam] then
            local q = tonumber(row.quality) or 0
            entries[#entries + 1] = { spellId = id, quality = q, stacks = 1, family = fam }
            byFamily[fam] = { targetStacks = 1, wishedQuality = q, spellId = id,
                qualityTiers = { { q = q, n = 1, spellId = id } } }
            existingIds[id] = true
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
-- A 10s per-spellId cooldown (on top of GameAdapter's own 3s hard spacing)
-- keeps this from hammering the server while waiting for a write to be
-- reflected back through GetLockedPerks().
local autoLockCooldown = {}
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
local function TryAutoLock(owned, catalog, slots, wishlist)
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

    local targets = LockDesignTargetsFor(wishlist)
    if type(targets) ~= "table" then
        trace[#trace + 1] = string.format(
            "lockDesignTargetsBySlot[%s]: table missing", tostring(LockSlotKey(wishlist)))
        return
    end
    if not (Adapter.LockPerk and Adapter.UnlockPerk and Adapter.LockedOwned) then
        trace[#trace + 1] = "Adapter.LockPerk/UnlockPerk/LockedOwned: missing on this build"
        return
    end
    local targetCount = 0
    for _ in pairs(targets) do targetCount = targetCount + 1 end
    trace[#trace + 1] = string.format("lockDesignTargets[slot %s]: %d entries",
        tostring(LockSlotKey(wishlist)), targetCount)
    if targetCount == 0 then return end

    local locked = Adapter.LockedOwned()
    local lockedBySpell = (locked and locked.bySpell) or {}
    local lockedCount = 0
    for _ in pairs(lockedBySpell) do lockedCount = lockedCount + 1 end
    local maxSlots = Adapter.MaxPermanentEchoes and Adapter.MaxPermanentEchoes() or 6
    trace[#trace + 1] = string.format("locked: %d/%d", lockedCount, maxSlots)

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
        unlockContextKey = tostring(activeIdx) .. "|" .. tostring(LockSlotKey(wishlist))
    end
    if unlockContextKey ~= autoUnlockContextKey then
        autoUnlockContextKey = unlockContextKey
        autoUnlockContextSince = now
    end
    local canUnlock = unlockContextKey ~= nil and (now - autoUnlockContextSince) >= 2
    if unlockContextKey ~= nil and not canUnlock then
        RequestStepAt(autoUnlockContextSince + 2)
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
        local lastAttempt = autoLockCooldown[oldId] or -30
        if (now - lastAttempt) < 10 then return false end
        autoLockCooldown[oldId] = now
        local ok, err = Adapter.UnlockPerk(oldId)
        trace[#trace + 1] = string.format(
            "  -> UnlockPerk(%s) for ready replacement %s: ok=%s err=%s",
            tostring(oldId), tostring(newId), tostring(ok), tostring(err))
        if err ~= "spacing" then
            AppendAutoLockEvent({ action = "unlock", spellId = oldId,
                name = EchoName(oldId), forTarget = newId, forName = EchoName(newId),
                pairing = "replacement", ok = ok and true or false, err = err,
                wishlistKey = LockSlotKey(wishlist) })
        end
        if ok then
            Print(string.format(
                "|cff4dff80Nexus:|r unlocked %s -- %s is acquired and ready to replace it.",
                EchoName(oldId), EchoName(newId)))
            lockedBySpell[oldId] = nil
            lockedCount = math.max(0, lockedCount - 1)
            return true
        elseif err ~= "spacing" then
            Print(string.format("|cffff6060Nexus:|r couldn't unlock %s: %s",
                EchoName(oldId), tostring(err)))
        end
        return false
    end

    -- Never sweep every currently-locked Echo just because it is absent from
    -- a momentary wanted set. Replacements are now transactional: Nexus waits
    -- until the exact new target is actually owned, then unlocks only the
    -- explicitly paired old Echo (`targets[newId] == oldId`). The following
    -- tick locks the replacement into the newly-open slot. This preserves all
    -- unrelated/intended locks through death, reset, reload, and association
    -- transitions while still fully automating deliberate swaps.
    for spellIdKey, replacementValue in pairs(targets) do
        local id = tonumber(spellIdKey)
        local replaces = type(replacementValue) == "number" and replacementValue or nil
        local haveN = id and tonumber(ownedBySpell[id]) or 0
        local isLocked = id and (tonumber(lockedBySpell[id]) or 0) > 0
        trace[#trace + 1] = string.format(
            "target %s (%s): locked=%s owned=%s replaces=%s lastAttempt=%ss ago",
            tostring(id), EchoName(id or 0), tostring(isLocked), tostring(haveN),
            tostring(replaces),
            autoLockCooldown[id] and string.format("%.1f", now - autoLockCooldown[id]) or "never")
        if id and isLocked then
            -- Fulfilled targets stay in the committed set permanently. They
            -- are desired lock-slot state, not a temporary work queue. If this
            -- target was a replacement and both Echoes are temporarily locked
            -- (because an open slot let the new one lock first), finish the
            -- exact pair by shedding only its explicitly replaced old Echo.
            if replaces then UnlockReplacement(replaces, id) end
        elseif id and haveN > 0 then
            if lockedCount < maxSlots then
                local lastAttempt = autoLockCooldown[id] or -30
                if (now - lastAttempt) >= 10 then
                    autoLockCooldown[id] = now
                    local ok, err = Adapter.LockPerk(id)
                    trace[#trace + 1] = string.format("  -> LockPerk(%s): ok=%s err=%s",
                        tostring(id), tostring(ok), tostring(err))
                    if err ~= "spacing" then
                        AppendAutoLockEvent({ action = "lock", spellId = id, name = EchoName(id),
                            ok = ok and true or false, err = err,
                            wishlistKey = LockSlotKey(wishlist) })
                    end
                    if ok then
                        Print(string.format("|cff4dff80Nexus:|r locked in %s.", EchoName(id)))
                        lockedBySpell[id] = 1
                        lockedCount = lockedCount + 1
                    elseif err ~= "spacing" then
                        Print(string.format("|cffff6060Nexus:|r couldn't lock %s: %s",
                            EchoName(id), tostring(err)))
                    end
                end
            elseif replaces and replaces ~= id and (tonumber(lockedBySpell[replaces]) or 0) > 0 then
                UnlockReplacement(replaces, id)
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

local function LogText_AutoLock()
    local age = lastAutoLockTrace.at and (GetTime() - lastAutoLockTrace.at) or nil
    local out = { string.format("AUTO-LOCK TRACE (last run %s ago)",
        age and string.format("%.1fs", age) or "never") , "" }
    for _, line in ipairs(lastAutoLockTrace.lines or {}) do
        out[#out + 1] = line
    end
    if #(lastAutoLockTrace.lines or {}) == 0 then
        out[#out + 1] = "(no trace recorded yet -- Step() may not have run; check /nexus err)"
    end
    out[#out + 1] = ""

    -- The raw committed table TryAutoLock actually reads (see
    -- LockDesignTargetsFor/CommitLockDesignTargets) -- LogText_Locked shows
    -- a live re-derivation from LockedOwned()/Wishlist(), which is close but
    -- not the same thing as what automation is actually keyed off.
    out[#out + 1] = "COMMITTED LOCK-DESIGN TARGETS (what TryAutoLock is actually working from):"
    local wl = Adapter.Wishlist()
    if wl then
        local targets = LockDesignTargetsFor(wl)
        local catalog = Adapter.Catalog()
        local ids = {}
        for spellIdKey in pairs(type(targets) == "table" and targets or {}) do
            ids[#ids + 1] = tonumber(spellIdKey)
        end
        table.sort(ids)
        if #ids == 0 then
            out[#out + 1] = "  (none committed for this wishlist)"
        else
            -- Fulfilled (already really locked) entries are deliberately
            -- kept in this table now, not deleted -- see TryAutoLock's
            -- comment. Flagged here so a fulfilled design doesn't read as
            -- "still pending" in the log.
            local lockedNow = Adapter.LockedOwned and Adapter.LockedOwned()
            local lockedBySpellNow = (lockedNow and lockedNow.bySpell) or {}
            for _, id in ipairs(ids) do
                local replaces = targets[id]
                local row = catalog and catalog.rows and catalog.rows[id]
                local name = (row and row.name) or ("spell " .. tostring(id))
                local fulfilled = (tonumber(lockedBySpellNow[id]) or 0) > 0
                local suffix = fulfilled and " [FULFILLED -- already locked]" or ""
                if type(replaces) == "number" then
                    local rrow = catalog and catalog.rows and catalog.rows[replaces]
                    out[#out + 1] = string.format("  %s (id=%d) -- replaces %s (id=%d)%s",
                        name, id, (rrow and rrow.name) or ("spell " .. tostring(replaces)), replaces,
                        suffix)
                else
                    out[#out + 1] = string.format(
                        "  %s (id=%d) -- fresh target, no replacement pairing%s", name, id, suffix)
                end
            end
        end
    else
        out[#out + 1] = "  (no wishlist resolved)"
    end
    out[#out + 1] = ""

    -- lastAutoLockTrace above is a single-tick snapshot, overwritten every
    -- poll -- by the time a full diagnostic export is taken, it only reflects
    -- whatever the last tick looked like. This is the durable history: every
    -- actual LockPerk/UnlockPerk attempt this session, oldest first.
    out[#out + 1] = "LOCK/UNLOCK EVENT HISTORY (actual write attempts only, oldest first):"
    local hist = Nexus.DiagnosticLogs and Nexus.DiagnosticLogs.Snapshot
        and Nexus.DiagnosticLogs.Snapshot("autoLock") or {}
    if #hist == 0 then
        out[#out + 1] = "  (empty -- no LockPerk/UnlockPerk attempts recorded yet this session)"
    else
        for _, e in ipairs(hist) do
            if e.action == "lock" then
                out[#out + 1] = string.format("  [%s] LOCK %s (id=%s) ok=%s%s",
                    tostring(e.t), tostring(e.name), tostring(e.spellId), tostring(e.ok),
                    e.ok and "" or (" err=" .. tostring(e.err)))
            else
                out[#out + 1] = string.format("  [%s] UNLOCK %s (id=%s) for %s [%s pairing] ok=%s%s",
                    tostring(e.t), tostring(e.name), tostring(e.spellId), tostring(e.forName),
                    tostring(e.pairing), tostring(e.ok), e.ok and "" or (" err=" .. tostring(e.err)))
            end
        end
    end
    return table.concat(out, "\n")
end

local function StepRun(level, plan, slots, owned, flags, disabledLevers)
    local settings = Store.Settings()
    local catalog = Adapter.Catalog()
    local board = Adapter.Board()
    if not board then
        SetStatus("waiting for board")
        RenderPanel({ status = statusLine, cards = {}, recommendation = "",
            progress = BuildProgress(plan, owned, slots, catalog),
            auto = AutoAllowed() and settings.autoPick,
            version = Nexus.VERSION })
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

    local activeRow = ActiveSlotRow(slots)
    local queue = Ratchet.PredictQueue(activeRow and activeRow.echoes or {},
        owned, plan, flags, disabledLevers, catalog)
    local charges = Adapter.Charges()
    local locked = Adapter.LockedOwned and Adapter.LockedOwned() or nil
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
    local action = Policy.Decide(state)

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
                    wishlist = (Adapter.Wishlist() and Adapter.Wishlist().name) or "",
                    incumbent = WishedCounts(slotCounts, plan),
                    exact = exact,
                })
            end
        end
    end

    -- render (bridge display names onto the copies -- Readout is id-blind)
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
    local okAuto, autoWhy = AutoAllowed()
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
    RenderPanel({
        status = statusLine,
        cards = cardLines,
        progress = BuildPanelProgress(plan, owned, slots, catalog),
        level = level,
        recommendation = recommendation,
        auto = autoEnabled,
        version = Nexus.VERSION,
    })

    -- pacing: decide, show intent, act after a short beat
    if action.type == "wait" then
        SetStatus(action.reason == "advisor"
            and "No wishlist set -- advisor only" or ("waiting: " .. tostring(action.reason)))
        return
    end
    SetStatus("L" .. level .. " -- " .. (action.reason or action.type))
    if not (okAuto and settings.autoPick) then
        if not okAuto then SetStatus("auto paused: " .. autoWhy) end
        return
    end
    if lastDecidedSig ~= board.signature then
        lastDecidedSig, lastDecision, decidedAt = board.signature, action, GetTime()
        RequestStepAt(decidedAt + 0.4)
        return -- show the intent one beat before acting
    end
    if (GetTime() - (decidedAt or 0)) < 0.4 then
        RequestStepAt((decidedAt or GetTime()) + 0.4)
        return
    end
    if Adapter.InFlight() then return end

    if action.type == "take" then
        fillerFishState.consecutive = 0
        if action.forced then
            local fid = tonumber(action.spellId)
            if fid then
                forcedTakesBySpell[fid] = (forcedTakesBySpell[fid] or 0) + 1
            end
        end
        Adapter.Take(action.spellId)
    elseif action.type == "banish" and settings.autoBanish then
        fillerFishState.consecutive = 0
        -- Policy indexes cards 1-based; the client (and adapter) are 0-based
        local ok, err = Adapter.Banish(action.index - 1)
        if ok then
            SetStatus(string.format("|cffff6666Banished|r echo #%d", action.index))
        else
            refusedBanishSig = board.signature
            lastDecidedSig = nil
            SetStatus(action.endgame
                and "final-search Banish refused -- re-evaluating"
                or "Banish refused -- trying another action")
        end
    elseif action.type == "freeze" then
        fillerFishState.consecutive = 0
        -- one freeze per board; the follow-up banish/reroll happens on a
        -- later tick once this resolves
        local ok = Adapter.Freeze(action.index - 1)
        if ok then
            frozeThisBoard = board.signature
            SetStatus(string.format("|cff66aaff Froze|r echo #%d -- waiting for board to update",
                action.index))
        else
            frozeThisBoard = board.signature   -- refused: do not retry this board
        end
    elseif action.type == "reroll" then
        local ok = Adapter.Reroll()
        if ok then
            lastBoardForRerollWatch = board
            if action.reason == "bracket fishing: reroll filler guarantee" then
                fillerFishState.consecutive = fillerFishState.consecutive + 1
                fillerFishState.bracketSpent = fillerFishState.bracketSpent + 1
            else
                fillerFishState.consecutive = 0
            end
        else
            refusedRerollSig = board.signature
            lastDecidedSig = nil
            SetStatus(action.endgame
                and "final-search Reroll refused -- taking held Echo"
                or "Reroll refused -- taking the least-harmful Echo")
        end
    end
end

local function StepSave(level, plan, slots, owned)
    RenderIdlePanel(plan, owned, slots, Adapter.Catalog())
    local settings = Store.Settings()
    if not settings.autoSave or savedThisVisit then return end
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
    local catalog = Adapter.Catalog()
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

local function Step()
    local level = Adapter.Level()
    local levelChanged = lastLevelSeen ~= level
    if levelChanged then
        -- A short user-action pause belongs to the board/level where it was
        -- observed. Never let it suppress the first actionable board after a
        -- genuine progression transition.
        externalPauseUntil = 0
        if level == 1 then
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
            lastDecidedSig, lastDecision, decidedAt = nil, nil, nil
            lastLoggedSig = nil
            lastBoardForRerollWatch = nil
            frozeThisBoard = nil
            refusedBanishSig, refusedRerollSig = nil, nil
            Adapter.RunBoundaryReset()   -- void the dead run's picks/trust
        end
        if level ~= 80 then savedThisVisit = false end
        lastLevelSeen = level
    end
    if Adapter.ExternalActionSeen() and not levelChanged then
        externalPauseUntil = GetTime() + 3
    end

    local catalog = Measure("automation.catalog", Adapter.Catalog)
    if not catalog then
        SetStatus("waiting for ProjectEbonhold")
        RenderIdlePanel(nil, nil, nil, nil)
        return
    end
    local wishlist = Measure("automation.wishlist", Adapter.Wishlist)
    if not quickStartChecked then
        quickStartChecked = true
        if Nexus.QuickStart then
            Nexus.QuickStart.ShowIfFirstTime(wishlist ~= nil)
        end
    end
    local plan = Measure("automation.compile", Strategy.Compile,
        catalog, WishlistWithLockTargets(wishlist, catalog), Store.Settings())
    local slots = Measure("automation.slots", Adapter.Slots)
    local owned = Measure("automation.owned", Adapter.Owned)
    local flags, disabledLevers = {}, {}
    local activeBoard = nil
    local rolledTotal = tonumber(owned and owned.total) or 0
    -- Tome state is consulted by level-1 arming and by a live roll board. It
    -- cannot affect a completed, boardless level-80 character, yet querying
    -- every member through the server API was part of the idle hot path.
    if level < 80 then
        flags = EffectiveFlags()
        disabledLevers = Measure("automation.levers", Adapter.DisabledLevers)
    elseif rolledTotal < 79 then
        activeBoard = Adapter.Board()
        if activeBoard then
            flags = EffectiveFlags()
            disabledLevers = Measure("automation.levers", Adapter.DisabledLevers)
        end
    end
    do
        local okAutoLock, errAutoLock = pcall(Measure,
            "automation.autolock", TryAutoLock, owned, catalog, slots, wishlist)
        if not okAutoLock then
            SetStatus("error (see /nexus err)")
            RecordError("TryAutoLock", errAutoLock)
            return
        end
    end

    -- once per session, clear stale flag demotions (they are session-
    -- scoped per addendum C; a real one re-arms on the first evidence)
    if not demotionsClearedThisSession and Adapter.Ready() then
        Store.State().flagDemotions = {}
        demotionsClearedThisSession = true
    end

    -- Post-save observation. One write is sent, then Nexus polls every
    -- Snapshot slot for 30 seconds. It never resubmits automatically. This
    -- distinguishes a real server write failure from stale or differently
    -- normalized slot data without risking repeated overwrites.
    if saveVerifySlot then
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
            local confirmed = ObserveAllSlots(freshSlots, saveVerifySnap, catalog, due or elapsed)
            saveObserveReadyAt = nil
            saveObserveIndex = saveObserveIndex + 1

            if confirmed then
                if saveVerifyExpectedActive
                    and tonumber(freshSlots and freshSlots.activeSlot) ~= tonumber(saveVerifyExpectedActive) then
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
                            .. tostring(saveVerifySlot) .. ". Activate that slot in My Builds before starting the next run.")
                    else
                        SetStatus("Save complete — server confirmed Active Loadout " .. saveVerifySlot)
                    end
                    NexusDB.lastSaveStatus = {
                        state = "confirmed", slot = saveVerifySlot,
                        t = date and date("%H:%M:%S") or "",
                        summary = saveVerifySummary or "",
                    }
                    saveVerifySlot, seedVerify, saveVerifySnap = nil, nil, nil
                    saveVerifyExpectedActive, saveVerifySummary, saveVerifyName = nil, nil, nil
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
                -- A normal overwrite may still have succeeded with a
                -- non-canonical immediate readback. A first-run seed is
                -- different: there was no prior Saved Build to fall back on,
                -- so make the required manual handoff unmistakable.
                if seedVerify then
                    SetStatus("First run not confirmed — save it manually in My Builds before resetting")
                    Print("|cffff9040Nexus:|r I couldn't confirm that your first completed run was stored in Saved Build "
                        .. tostring(saveVerifySlot) .. ". Open Echo Journal > My Builds and save this finished loadout into a slot before resetting.")
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
                -- Keep savedThisVisit latched for the rest of this completed
                -- run. A timeout is diagnostic uncertainty, not permission to
                -- write the same loadout again.
                saveVerifySlot, seedVerify, saveVerifySnap = nil, nil, nil
                saveVerifyExpectedActive, saveVerifySummary, saveVerifyName = nil, nil, nil
                saveObserveIndex, saveObserveReadyAt = 1, nil
            else
                SetStatus(string.format("Save sent to Active Loadout %d — checking server (+%.0fs)",
                    saveVerifySlot, due or elapsed))
            end
        end
    end

    if level == 1 then
        StepArm(level, plan, owned, slots, disabledLevers)
        if plan.advisorOnly then
            SetStatus("No wishlist set -- advisor only")
        end
    elseif level >= 2 and level < 80 then
        StepRun(level, plan, slots, owned, flags, disabledLevers)
    elseif level == 80 then
        -- A run is complete when the current rolled loadout reaches the
        -- server's 79-Echo capacity. Do not use an arbitrary no-board delay:
        -- board frames can disappear briefly between chained selections.
        -- Locked Echoes are not included in owned.total.
        if owned and owned.synced and rolledTotal >= 79 then
            StepSave(level, plan, slots, owned)
        else
            local board = activeBoard or Adapter.Board()
            if board then
                StepRun(level, plan, slots, owned, flags, disabledLevers)
            elseif Adapter.InFlight() then
                SetStatus("finishing final Echo selections")
            else
                SetStatus(string.format("finishing run — %d/79 Echoes", rolledTotal))
            end
        end
    end
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

------------------------------------------------------------------------
-- Init + events + slash
------------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- Log viewer data providers (/wr log). Pure text assembly; the viewer
-- renders whatever these return, one tab each.
-- ---------------------------------------------------------------------

local function FamLabel(catalog, fam)
    local nm = catalog and catalog.familyName and catalog.familyName[fam]
    return nm and (tostring(fam) .. " '" .. tostring(nm) .. "'") or tostring(fam)
end

local function DiagnosticTable(value)
    return type(value) == "table" and value or {}
end

local function DiagnosticScalar(value)
    local kind = type(value)
    if kind == "nil" then return "" end
    if kind == "string" or kind == "number" or kind == "boolean" then
        return tostring(value)
    end
    return "<" .. kind .. ">"
end

local function LogText_Boards()
    local log = Nexus.DiagnosticLogs and Nexus.DiagnosticLogs.Snapshot
        and Nexus.DiagnosticLogs.Snapshot("decision") or {}
    local out = { string.format("DECISION LOG -- %d boards (v%s)",
        #log, Nexus.VERSION), "" }
    local first = math.max(1, #log - 39)
    if first > 1 then
        out[#out + 1] = string.format("(showing newest 40 of %d boards; use Clear Log in this window)", #log)
        out[#out + 1] = ""
    end
    for i = first, #log do
        local e = DiagnosticTable(log[i])
        local proposal = DiagnosticTable(e.proposal)
        local charges = DiagnosticTable(e.charges)
        local cards = DiagnosticTable(e.cards)
        local users = DiagnosticTable(e.user)
        out[#out + 1] = string.format("== #%d [%s] L%s H:%s%s  charges B:%s R:%s F:%s%s",
            i, DiagnosticScalar(e.t), DiagnosticScalar(e.level),
            DiagnosticScalar(e.horizon),
            proposal.endgame and " [FINAL]" or "",
            DiagnosticScalar(charges.b),
            DiagnosticScalar(charges.r),
            DiagnosticScalar(charges.f),
            charges.ok == false and " (untrusted)" or "")
        for ci = 1, #cards do
            local c = DiagnosticTable(cards[ci])
            out[#out + 1] = string.format(
                "  %d%s %s id=%s fam=%s q=%s/cat:%s wishQ=%s max=%s own=%s d=%s %s%s",
                ci, c.g and "[G]" or "", DiagnosticScalar(c.name), DiagnosticScalar(c.id),
                DiagnosticScalar(c.fam), DiagnosticScalar(c.cardQ), DiagnosticScalar(c.catQ),
                DiagnosticScalar(c.wishQ), DiagnosticScalar(c.maxStack), DiagnosticScalar(c.owned),
                DiagnosticScalar(c.delta), DiagnosticScalar(c.ann),
                (c.wished and "" or " OFF-WISHLIST"))
            if c.frozen then out[#out] = out[#out] .. " FROZEN" end
        end
        out[#out + 1] = string.format("  proposal: %s %s (%s)",
            DiagnosticScalar(proposal.type),
            DiagnosticScalar(proposal.spellId or proposal.index or ""),
            DiagnosticScalar(proposal.reason))
        if #users > 0 then
            for _, rawUser in ipairs(users) do
                local u = DiagnosticTable(rawUser)
                out[#out + 1] = string.format("  USER: %s(%s)",
                    DiagnosticScalar(u.kind), DiagnosticScalar(u.arg))
            end
        end
        if e.pending and e.pending ~= "" then
            out[#out + 1] = "  pending guarantee: " .. DiagnosticScalar(e.pending)
        end
        out[#out + 1] = ""
    end
    return table.concat(out, "\n")
end

-- A user action "matches" the proposal when it is the same verb aimed at
-- the same thing; anything else is a training mismatch worth reading.
local function UserMatchesProposal(u, p)
    if type(u) ~= "table" or type(p) ~= "table" then return false end
    local k, a = tostring(u.kind), tonumber(u.arg)
    if k == "SelectPerk" then
        return p.type == "take" and a ~= nil and a == tonumber(p.spellId)
    elseif k == "BanishPerk" then
        return p.type == "banish" and a ~= nil and (a + 1) == tonumber(p.index)
    elseif k == "FreezePerk" then
        return p.type == "freeze" and a ~= nil and (a + 1) == tonumber(p.index)
    elseif k == "RequestReroll" then
        return p.type == "reroll"
    end
    return false
end

-- Complete, compact diagnostic export. The normal Boards/Mismatch tabs stay
-- bounded so opening /nexus log is cheap; this export includes every decision
-- still retained in SavedVariables (currently up to 200) in one copy operation.
-- Strings are dictionary-encoded to keep the single EditBox comfortably below
-- the client-freeze range without dropping any decision or mismatch fields.
local function NewAIExportCoroutine()
    return coroutine.create(function()
        local logs = Nexus.DiagnosticLogs
        local log = logs and logs.Snapshot and logs.Snapshot("decision") or {}
        local audits = logs and logs.Snapshot and logs.Snapshot("runAudit") or {}
        local probes = logs and logs.Snapshot and logs.Snapshot("uiProbe") or {}
        local errors = {}
        if Nexus.Errors and type(Nexus.Errors.History) == "function" then
            local okErrors, retained = pcall(Nexus.Errors.History)
            if okErrors and type(retained) == "table" then errors = retained end
        end
        local performance = {rows={}}
        if Nexus.Performance and type(Nexus.Performance.Snapshot) == "function" then
            local okPerformance, retained = pcall(Nexus.Performance.Snapshot)
            if okPerformance and type(retained) == "table" then performance = retained end
        end
        local dict, dictIndex = {}, {}
        local function Esc(v)
            local s = v and DiagnosticScalar(v) or ""
            s = s:gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\n", "%%0A"):gsub("\r", "")
            return s
        end
        local function Ref(v)
            if v == nil or v == "" then return 0 end
            local s = DiagnosticScalar(v)
            local idx = dictIndex[s]
            if not idx then idx = #dict + 1; dict[idx] = s; dictIndex[s] = idx end
            return idx
        end
        local function B(v) if v == nil then return 0 elseif v then return 1 else return -1 end end
        local function N(v) return tonumber(v) or 0 end
        local function V(v) return DiagnosticScalar(v) end
        local function Mismatch(e)
            e = DiagnosticTable(e)
            local p = DiagnosticTable(e.proposal)
            for _, u in ipairs(DiagnosticTable(e.user)) do
                if not UserMatchesProposal(u, p) then return 1 end
            end
            return 0
        end
        local function Counts(map)
            local a = {}
            for fam, n in pairs(type(map) == "table" and map or {}) do
                local kind = type(fam)
                if kind == "string" or kind == "number" or kind == "boolean" then
                    a[#a + 1] = { Ref(fam), N(n) }
                end
            end
            table.sort(a, function(x,y)
                if x[1] == y[1] then return x[2] < y[2] end
                return x[1] < y[1]
            end)
            local rows = {}
            for _, x in ipairs(a) do rows[#rows + 1] = x[1] .. ":" .. x[2] end
            return table.concat(rows, ",")
        end

        local out = {
            "NEXUS_DIAGNOSTIC_LOG_5",
            "version=" .. Esc(Nexus.VERSION) .. "|boards=" .. #log .. "|audits=" .. #audits .. "|probes=" .. #probes .. "|errors=" .. #errors,
            "B=board|C=card|U=user action|Q=predicted guarantee queue head|A=run/save audit|D=dictionary",
            "B|i|time|level|horizon|endgame|guaranteedIndex|banish|reroll|freeze|trusted|actionRef|spellId|cardIndex|reasonRef|pendingRef|mismatch|activeSlot|run|queueN",
            "C|board|card|spellId|familyRef|cardQ|catalogQ|wishQ|maxStack|owned|delta|annotationRef|flags(G,F,W)",
            "Q|board|position|spellId|familyRef|wished",
            "A|kindRef|time|run|level|activeSlot|targetSlot|resultRef|reasonRef|incumbentCounts|candidateCounts|summaryRef|exactRef|exactGained|exactLost|excessForced|excessAvoidable|excessShed|wrongQForced|wrongQAvoidable|wrongQShed|wrongQDetailRef|pollutionScoreRef",
            "P|time|eventRef|detailRef",
            "E|index|time|sourceRef|messageRef",
            "L|pageRef|line|textRef",
            "F|pathRef|count|totalMs|maximumMs|lastMs",
            "String refs use D lines. Counts are familyRef:stacks. This is observational logging only.",
        }
        for i, rawEntry in ipairs(log) do
            local e = DiagnosticTable(rawEntry)
            local p = DiagnosticTable(e.proposal); local ch = DiagnosticTable(e.charges)
            out[#out + 1] = table.concat({"B",i,Esc(e.t),V(e.level),V(e.horizon),B(p.endgame),V(e.gIndex),V(ch.b),V(ch.r),V(ch.f),B(ch.ok),Ref(p.type),V(p.spellId),V(p.index),Ref(p.reason),Ref(e.pending),Mismatch(e),N(e.activeSlot),N(e.run),N(e.queueN)}, "|")
            for ci, rawCard in ipairs(DiagnosticTable(e.cards)) do
                local c = DiagnosticTable(rawCard)
                local flags = (c.g and "G" or "-") .. (c.frozen and "F" or "-") .. (c.wished and "W" or "-")
                out[#out + 1] = table.concat({"C",i,ci,V(c.id),Ref(c.fam),V(c.cardQ),V(c.catQ),V(c.wishQ),V(c.maxStack),V(c.owned),V(c.delta),Ref(c.ann),flags}, "|")
            end
            for ui, rawUser in ipairs(DiagnosticTable(e.user)) do
                local u = DiagnosticTable(rawUser)
                out[#out + 1] = table.concat({"U",i,ui,Ref(u.kind),Esc(u.arg)}, "|")
            end
            for qi, rawQueue in ipairs(DiagnosticTable(e.queueHead)) do
                local q = DiagnosticTable(rawQueue)
                out[#out + 1] = table.concat({"Q",i,qi,V(q.id),Ref(q.fam),q.wished and 1 or 0}, "|")
            end
            if i % 5 == 0 then coroutine.yield("Encoding decisions " .. i .. "/" .. #log) end
        end
        for i, rawAudit in ipairs(audits) do
            local a = DiagnosticTable(rawAudit)
            local exact = {}
            for _, rawExact in ipairs(DiagnosticTable(a.exact)) do
                local x = DiagnosticTable(rawExact)
                exact[#exact + 1] = table.concat({N(x.id),Ref(x.fam),N(x.q),N(x.n)}, ":")
            end
            out[#out + 1] = table.concat({"A",Ref(a.kind),Esc(a.t),N(a.run),N(a.level),N(a.activeSlot),N(a.targetSlot),Ref(a.result),Ref(a.reason),Counts(a.incumbent),Counts(a.candidate),Ref(a.summary),Ref(table.concat(exact, ",")),N(a.exactGained),N(a.exactLost),N(a.excessForced),N(a.excessAvoidable),N(a.excessShed),N(a.wrongQForced),N(a.wrongQAvoidable),N(a.wrongQShed),Ref(a.wrongQDetail),Ref(a.pollutionScore)}, "|")
            if i % 8 == 0 then coroutine.yield("Encoding run audits " .. i .. "/" .. #audits) end
        end
        for i, rawProbe in ipairs(probes) do
            local p = DiagnosticTable(rawProbe)
            out[#out + 1] = table.concat({"P",Esc(p.t),Ref(p.event),Ref(p.detail)}, "|")
            if i % 10 == 0 then coroutine.yield("Encoding UI probes " .. i .. "/" .. #probes) end
        end
        for i, rawError in ipairs(errors) do
            local e = DiagnosticTable(rawError)
            out[#out + 1] = table.concat({"E",i,Esc(e.timestamp),Ref(e.source),Ref(e.message)}, "|")
        end
        -- Include every human-readable /nexus log page in the same export.
        -- This makes the export self-contained: compact event rows plus the exact
        -- State/Wishlist/Sync/DPS pages the player can see in the log window.
        local pageKeys = {"state", "wishlist", "boards", "mismatch", "sync", "dps", "autolock", "errors", "perf"}
        local pageProvider = Nexus and Nexus.GetDiagnosticPageText
        if type(pageProvider) == "function" then
            for _, pageKey in ipairs(pageKeys) do
                local okPage, pageText = pcall(pageProvider, pageKey)
                pageText = okPage and tostring(pageText or "") or ("provider error: " .. tostring(pageText))
                local lineNo = 0
                for line in (pageText .. "\n"):gmatch("(.-)\n") do
                    lineNo = lineNo + 1
                    out[#out + 1] = table.concat({"L",Ref(pageKey),lineNo,Ref(line)}, "|")
                    if lineNo % 40 == 0 then coroutine.yield("Encoding " .. pageKey .. " page line " .. lineNo) end
                end
            end
        end
        for index, rawRow in ipairs(DiagnosticTable(performance.rows)) do
            local row = DiagnosticTable(rawRow)
            out[#out + 1] = table.concat({
                "F", Ref(row.name), N(row.count),
                string.format("%.3f", N(row.total)),
                string.format("%.3f", N(row.maximum)),
                string.format("%.3f", N(row.last)),
            }, "|")
            if index % 4 == 0 then
                coroutine.yield("Encoding performance aggregates " .. index
                    .. "/" .. #DiagnosticTable(performance.rows))
            end
        end
        out[#out + 1] = "DICTIONARY"
        for i, v in ipairs(dict) do
            out[#out + 1] = "D|" .. i .. "|" .. Esc(v)
            if i % 40 == 0 then coroutine.yield("Encoding dictionary " .. i .. "/" .. #dict) end
        end
        out[#out + 1] = "END|boards=" .. #log .. "|audits=" .. #audits .. "|probes=" .. #probes .. "|errors=" .. #errors .. "|dict=" .. #dict
        coroutine.yield("Finalizing copy text")
        return table.concat(out, "\n")
    end)
end

-- Public UI hook. The log window resumes this coroutine in tiny slices so the
-- expensive full export never monopolizes one frame.
function Nexus.NewAIExportCoroutine()
    return NewAIExportCoroutine()
end

local function LogText_AIExport()
    return "Press Copy Full Diagnostic Log. Nexus builds the complete export gradually to avoid a frame hitch."
end

local function LogText_Mismatch()
    local log = Nexus.DiagnosticLogs and Nexus.DiagnosticLogs.Snapshot
        and Nexus.DiagnosticLogs.Snapshot("decision") or {}
    local out = { "MISMATCHES -- boards where your manual play differed", "" }
    local nMis = 0
    local first = math.max(1, #log - 99)
    if first > 1 then out[#out + 1] = "(scanning newest 100 boards)"; out[#out + 1] = "" end
    for i = first, #log do
        local e = DiagnosticTable(log[i])
        local users = DiagnosticTable(e.user)
        local proposal = DiagnosticTable(e.proposal)
        if #users > 0 then
            local anyMismatch = false
            for _, u in ipairs(users) do
                if not UserMatchesProposal(u, proposal) then anyMismatch = true end
            end
            if anyMismatch then
                nMis = nMis + 1
                out[#out + 1] = string.format("== board #%d [%s] L%s",
                    i, DiagnosticScalar(e.t), DiagnosticScalar(e.level))
                local cards = DiagnosticTable(e.cards)
                for ci = 1, #cards do
                    local c = DiagnosticTable(cards[ci])
                    out[#out + 1] = string.format(
                        "  %d%s %s id=%s fam=%s q=%s wishQ=%s own=%s d=%s %s%s",
                        ci, c.g and "[G]" or "", DiagnosticScalar(c.name), DiagnosticScalar(c.id),
                        DiagnosticScalar(c.fam), DiagnosticScalar(c.cardQ), DiagnosticScalar(c.wishQ),
                        DiagnosticScalar(c.owned), DiagnosticScalar(c.delta), DiagnosticScalar(c.ann),
                        (c.wished and "" or " OFF-WISHLIST"))
                end
                out[#out + 1] = string.format("  addon: %s %s (%s)",
                    DiagnosticScalar(proposal.type),
                    DiagnosticScalar(proposal.spellId or proposal.index or ""),
                    DiagnosticScalar(proposal.reason))
                for _, rawUser in ipairs(users) do
                    local u = DiagnosticTable(rawUser)
                    out[#out + 1] = string.format("  you:   %s(%s)",
                        DiagnosticScalar(u.kind), DiagnosticScalar(u.arg))
                end
                out[#out + 1] = ""
            end
        end
    end
    if nMis == 0 then out[#out + 1] = "(none recorded yet)" end
    return table.concat(out, "\n")
end

-- Reconciliation view for the "imported an 85-Echo build" scenario: Nexus has
-- no server API to lock/unlock an Echo (GameAdapter only exposes the
-- read-only LockedOwned), so this cannot swap anything automatically -- it
-- exists to tell the player exactly what to change by hand in the native
-- lock UI: which of their current locked Echoes this wishlist doesn't want,
-- and which wishlist Echoes don't fit the 79 cap because of it.
local function LogText_Locked()
    local catalog = Adapter.Catalog()
    local lockedOwned = Adapter.LockedOwned and Adapter.LockedOwned()
    local lockedBySpell = (lockedOwned and lockedOwned.bySpell) or {}
    local out = {}

    local lockedIds = {}
    for id in pairs(lockedBySpell) do lockedIds[#lockedIds + 1] = id end
    table.sort(lockedIds)
    out[#out + 1] = string.format(
        "LOCKED ECHOES -- %d total (permanent; Nexus can only read these, never lock/unlock them)",
        #lockedIds)
    for _, id in ipairs(lockedIds) do
        local row = catalog and catalog.rows and catalog.rows[id]
        out[#out + 1] = string.format("  %s (id=%d)", (row and row.name) or "?", id)
    end
    out[#out + 1] = ""

    local wl = Adapter.Wishlist()
    if not wl then
        out[#out + 1] = "no wishlist resolved -- nothing to compare against"
        return table.concat(out, "\n")
    end

    local entries = wl.entries or {}
    local wishedIds, total = {}, 0
    for _, e in ipairs(entries) do
        local id = tonumber(e and e.spellId)
        if id then wishedIds[id] = true end
        total = total + math.max(1, tonumber(e and e.stacks) or 1)
    end
    out[#out + 1] = string.format("WISHLIST '%s' -- %d total Echo copies (%d distinct entries)",
        tostring(wl.name), total, #entries)
    out[#out + 1] = ""

    local unwantedLocked = {}
    for _, id in ipairs(lockedIds) do
        if not wishedIds[id] then unwantedLocked[#unwantedLocked + 1] = id end
    end
    if #unwantedLocked > 0 then
        out[#out + 1] = string.format(
            "Locked but NOT on this wishlist (%d) -- swap candidates if you want to lock "
                .. "something this build actually asks for instead:", #unwantedLocked)
        for _, id in ipairs(unwantedLocked) do
            local row = catalog and catalog.rows and catalog.rows[id]
            out[#out + 1] = "  " .. ((row and row.name) or ("spell " .. tostring(id)))
        end
    else
        out[#out + 1] = "Every locked Echo is also on this wishlist -- no obvious swap candidates."
    end
    out[#out + 1] = ""

    -- Mirrors WishlistEditor.LoadPendingEchoes: already-locked matches don't
    -- consume the 79 cap, so overflow is whatever's left over after those.
    local remaining, overflow = 79, {}
    for _, e in ipairs(entries) do
        local id = tonumber(e and e.spellId)
        if id then
            if (tonumber(lockedBySpell[id]) or 0) > 0 then
                -- already locked; does not consume the cap
            elseif remaining <= 0 then
                overflow[#overflow + 1] = id
            else
                remaining = remaining - math.min(math.max(1, tonumber(e.stacks) or 1), remaining)
            end
        end
    end
    if #overflow > 0 then
        out[#out + 1] = string.format(
            "Doesn't fit in the 79-slot cap even after excluding locked matches (%d) -- "
                .. "lock one of these in-game to free a slot, or trim the wishlist:", #overflow)
        for _, id in ipairs(overflow) do
            local row = catalog and catalog.rows and catalog.rows[id]
            out[#out + 1] = "  " .. ((row and row.name) or ("spell " .. tostring(id)))
        end
    else
        out[#out + 1] = "No overflow -- everything on this wishlist fits within the 79-slot cap."
    end

    return table.concat(out, "\n")
end

local function LogText_Wishlist()
    local catalog = Adapter.Catalog()
    local wl = Adapter.Wishlist()
    local out = {}
    if not wl then
        return "no wishlist resolved" ..
            (Adapter.WishlistNote and (" -- " .. tostring(Adapter.WishlistNote())) or "")
    end
    local plan = Strategy.Compile(catalog, WishlistWithLockTargets(wl, catalog), Store.Settings())
    local owned = Adapter.Owned()
    out[#out + 1] = string.format("WISHLIST '%s' source=%s -- %d entries",
        tostring(wl.name), tostring(wl.source), #wl.entries)
    local nFam = 0
    for _ in pairs(plan.wishedFamilies or {}) do nFam = nFam + 1 end
    out[#out + 1] = string.format("plan.wishedFamilies: %d families", nFam)
    out[#out + 1] = ""
    local orphans = {}
    for _, e in ipairs(wl.entries) do
        local row = catalog and catalog.rows[e.spellId]
        local fam = e.family
        local members = catalog and catalog.familyMembers
            and catalog.familyMembers[fam] or {}
        local mq = {}
        for _, mid in ipairs(members) do
            local mr = catalog.rows[mid]
            mq[#mq + 1] = tostring(mid) .. ":q" .. tostring(mr and mr.quality)
        end
        local inPlan = plan.wishedFamilies and plan.wishedFamilies[fam] and true or false
        local ownedFamLog = (owned and owned.byFamily and fam and owned.byFamily[fam]) or 0
        local effQ = Model.EffectiveWishedQuality
            and Model.EffectiveWishedQuality(plan, catalog, fam, ownedFamLog, owned and owned.bySpell) or "?"
        out[#out + 1] = string.format(
            "%s id=%s q=%s stacks=%s fam=%s effWishQ=%s own=%s%s",
            tostring(row and row.name or ("spell " .. tostring(e.spellId))),
            tostring(e.spellId), tostring(e.quality), tostring(e.stacks),
            FamLabel(catalog, fam), tostring(effQ),
            tostring(owned.byFamily and owned.byFamily[fam] or 0),
            inPlan and "" or "  <-- NOT IN PLAN")
        out[#out + 1] = "    variants: " .. (next(mq) and table.concat(mq, ", ")
            or "(sole variant)")
        if not inPlan then orphans[#orphans + 1] = tostring(row and row.name or e.spellId) end
    end
    out[#out + 1] = ""
    if #orphans > 0 then
        out[#out + 1] = "!! ENTRIES MISSING FROM PLAN (this is the ST/AB bug surface):"
        out[#out + 1] = "   " .. table.concat(orphans, ", ")
    else
        out[#out + 1] = "all wishlist entries resolved into the plan"
    end
    return table.concat(out, "\n")
end

local function LogText_State()
    local catalog = Adapter.Catalog()
    local wl = Adapter.Wishlist()
    local plan = wl and Strategy.Compile(catalog, WishlistWithLockTargets(wl, catalog), Store.Settings())
        or { advisorOnly = true }
    local slots = Adapter.Slots()
    local owned = Adapter.Owned()
    local charges = Adapter.Charges()
    local out = {}
    out[#out + 1] = string.format("v%s  level=%s  auto=%s",
        Nexus.VERSION, tostring(Adapter.Level()),
        tostring(autoEnabled))
    out[#out + 1] = string.format("charges B:%s R:%s F:%s trustworthy=%s",
        tostring(charges.banish), tostring(charges.reroll),
        tostring(charges.freeze), tostring(charges.trustworthy))
    for k, v in pairs(EffectiveFlags()) do
        out[#out + 1] = "flag " .. tostring(k) .. " = " .. tostring(v)
    end
    local s = Store.Settings()
    out[#out + 1] = string.format(
        "settings: autoPick=%s autoActivate=%s autoBanish=%s autoSave=%s autoDisable=%s autoLockEchoes=%s",
        tostring(s.autoPick), tostring(s.autoActivate), tostring(s.autoBanish),
        tostring(s.autoSave), tostring(s.autoDisable), tostring(s.autoLockEchoes))
    out[#out + 1] = ""
    local refusal = NexusDB and NexusDB.lastSaveRefusal
    if refusal then
        out[#out + 1] = string.format(
            "LAST SAVE REFUSAL [%s] L%s slot %s: %s",
            tostring(refusal.t), tostring(refusal.level),
            tostring(refusal.incumbentSlot), tostring(refusal.detail))
        out[#out + 1] = "  (\"coverage lost: X\" = a wished family X the active loadout"
        out[#out + 1] = "   already has is missing from this run. \"no net gain\" = coverage"
        out[#out + 1] = "   held even but this run picked up more off-wishlist filler than"
        out[#out + 1] = "   the active loadout carries -- not a coverage regression.)"
        out[#out + 1] = ""
    end
    if slots then
        out[#out + 1] = "SLOTS (activeSlot=" .. tostring(slots.activeSlot) .. "):"
        local ids = {}
        for id in pairs(slots.bySlot or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local row = slots.bySlot[id]
            out[#out + 1] = string.format("  slot %s '%s' verified=%s echoes=%d%s",
                tostring(id), tostring(row.name), tostring(row.verified),
                #(row.echoes or {}), row.suspectParse and " SUSPECT" or "")
            if id == slots.activeSlot then
                for _, e in ipairs(row.echoes or {}) do
                    out[#out + 1] = string.format(
                        "      id=%s fam=%s q=%s stacks=%s%s wished=%s",
                        tostring(e.spellId), tostring(e.family), tostring(e.quality),
                        tostring(e.stacks), e.locked and " locked" or "",
                        tostring(plan.wishedFamilies
                            and plan.wishedFamilies[e.family] or false))
                end
            end
        end
    else
        out[#out + 1] = "SLOTS: not loaded"
    end
    out[#out + 1] = ""
    out[#out + 1] = "OWNED byFamily:"
    local fams = {}
    for fam in pairs(owned.byFamily or {}) do fams[#fams + 1] = fam end
    table.sort(fams, function(a, b) return tostring(a) < tostring(b) end)
    for _, fam in ipairs(fams) do
        out[#out + 1] = string.format("  %s x%s", FamLabel(catalog, fam),
            tostring(owned.byFamily[fam]))
    end
    out[#out + 1] = string.format("owned synced=%s", tostring(owned.synced))
    return table.concat(out, "\n")
end

local function LogText_Sync()
    local s = Nexus.Sync
    if not s then return "sync module not loaded" end
    local out = {}
    local function Add(fmt, ...)
        local ok, line = pcall(string.format, fmt, ...)
        out[#out + 1] = ok and line or tostring(fmt)
    end

    Add("SYNC DIAGNOSTICS -- Nexus v%s", tostring(Nexus.VERSION))
    Add("")
    Add("-- connection --")
    Add("channel name   : %s", s.ChannelName())
    Add("connected      : %s", tostring(s.IsConnected()))
    Add("channel index  : %s", tostring(s.ChannelIndex()))
    Add("my name        : %s", tostring((UnitName and UnitName("player")) or "?"))
    Add("receiving now  : %s (%.0fs left)", tostring(s.IsReceiving()), s.ReceiveTimeLeft())
    Add("last sync new  : %d build(s)", s.LastSyncNewCount())
    Add("")

    local st = s.Stats()
    Add("-- counters --")
    Add("messages sent          : %d", st.sent or 0)
    Add("builds stored (new)    : %d", (st.received or 0) - (st.updated or 0))
    Add("builds updated         : %d", st.updated or 0)
    Add("skipped (peer up2date) : %d", st.skippedUpToDate or 0)
    Add("duplicates skipped     : %d", st.duplicatesSkipped or 0)
    Add("malformed rejected     : %d", st.malformedRejected or 0)
    Add("ignored (no sync open) : %d", st.ignoredOutsideWindow or 0)
    Add("oversize dropped       : %d", st.oversizeDropped or 0)
    Add("deleted (tombstoned)   : %d", s.TombstoneCount and s.TombstoneCount() or 0)
    Add("")

    Add("-- builds in my library --")
    local mine, theirs, listed = 0, 0, 0
    local catalog = Nexus and Nexus.BuildCatalog
    local builds = catalog and catalog.All and catalog.All() or {}
    for _, b in pairs(builds) do
        if listed < 100 and b.isMine then
            listed = listed + 1
            mine = mine + 1
            Add("  [MINE]  %-28s %2d echoes  stamp=%s",
                tostring(b.title), #(b.echoes or {}),
                tostring(b.lastModified or b.postedAt))
        elseif listed < 100 then
            listed = listed + 1
            theirs = theirs + 1
            Add("  [THEIRS] %-27s %2d echoes  by %s",
                tostring(b.title), #(b.echoes or {}), tostring(b.author))
        end
    end
    if mine + theirs == 0 then Add("  (none)") end
    if listed >= 100 then Add("  (list capped at 100 entries for client safety)") end
    Add("  listed: %d mine, %d from others", mine, theirs)
    Add("")

    Add("-- event log (newest last) --")
    local log = s.EventLog()
    if #log == 0 then
        Add("  (empty -- no sync activity yet this session)")
        Add("  If you pressed Sync Now and this is still empty, the addon")
        Add("  is not seeing ANY traffic on the channel.")
    else
        local first = math.max(1, #log - 99)
        local t0 = log[first].t or 0
        if first > 1 then Add("  (showing newest 100 of %d events)", #log) end
        for i = first, #log do
            local e = log[i]
            Add("  [%7.2fs] %-5s %s", (e.t or 0) - t0, e.cat or "?", e.text or "")
        end
    end
    return table.concat(out, "\n")
end

local function LogText_Errors()
    local errors = Nexus.Errors
    if not errors or type(errors.Format) ~= "function" then
        return "error history unavailable"
    end
    local ok, text = pcall(errors.Format)
    return ok and tostring(text or "")
        or ("error history render failed: " .. ErrorText(text))
end

local function LogText_Performance()
    local performance = Nexus.Performance
    if not performance or type(performance.Snapshot) ~= "function" then
        return "performance diagnostics unavailable"
    end
    local ok, snapshot = pcall(performance.Snapshot)
    if not ok or type(snapshot) ~= "table" then
        return "performance diagnostics unavailable"
    end
    local out = {
        "PERFORMANCE AGGREGATES -- this session only",
        "Observational milliseconds; no per-call samples or SavedVariables history.",
        string.format("enabled=%s clockAvailable=%s clockFailures=%d",
            tostring(snapshot.enabled == true),
            tostring(snapshot.clockAvailable == true),
            tonumber(snapshot.clockFailures) or 0),
        "",
        "path                         count    total ms      max ms     last ms",
    }
    for _, rawRow in ipairs(DiagnosticTable(snapshot.rows)) do
        local row = DiagnosticTable(rawRow)
        out[#out + 1] = string.format("%-28s %7d %11.3f %11.3f %11.3f",
            DiagnosticScalar(row.name), tonumber(row.count) or 0,
            tonumber(row.total) or 0, tonumber(row.maximum) or 0,
            tonumber(row.last) or 0)
    end
    return table.concat(out, "\n")
end

local function ClearDiagnosticLogs(tabKey)
    if tabKey == "perf" then
        if Nexus.Performance and type(Nexus.Performance.Reset) == "function" then
            local ok, cleared = pcall(Nexus.Performance.Reset)
            return ok and cleared ~= false
        end
        return false
    end
    if tabKey == "errors" then
        if Nexus.Errors and type(Nexus.Errors.Clear) == "function" then
            local ok, cleared = pcall(Nexus.Errors.Clear)
            return ok and cleared ~= false
        end
        return false
    end
    NexusDB = NexusDB or {}
    local clearedDurable = Nexus.DiagnosticLogs
        and type(Nexus.DiagnosticLogs.ClearAll) == "function"
        and Nexus.DiagnosticLogs.ClearAll()
    NexusDB.lastSaveRefusal = nil
    NexusDB.lastSaveStatus = nil
    NexusDB.auditRunCounter = 0
    lastLoggedSig = nil
    auditRunStarted = nil
    auditRunId = 0
    if Nexus.Sync and type(Nexus.Sync.ClearLog) == "function" then
        pcall(Nexus.Sync.ClearLog)
    end
    if Nexus.DpsCapture and type(Nexus.DpsCapture.ClearDebugLog) == "function" then
        pcall(Nexus.DpsCapture.ClearDebugLog)
    end
    if Nexus.Errors and type(Nexus.Errors.Clear) == "function" then
        pcall(Nexus.Errors.Clear)
    end
    return clearedDurable and true or false
end

local function LogViewerProvider(tabKey)
    if tabKey == "boards" then return LogText_Boards() end
    if tabKey == "mismatch" then return LogText_Mismatch() end
    if tabKey == "ai_export" then return LogText_AIExport() end
    if tabKey == "wishlist" then return LogText_Wishlist() end
    if tabKey == "locked" then return LogText_Locked() end
    if tabKey == "state" then return LogText_State() end
    if tabKey == "sync" then return LogText_Sync() end
    if tabKey == "dps" then
        local D = Nexus.DpsCapture
        return D and D.GetDebugLog and D.GetDebugLog() or "DPS module unavailable"
    end
    if tabKey == "autolock" then return LogText_AutoLock() end
    if tabKey == "errors" then return LogText_Errors() end
    if tabKey == "perf" then return LogText_Performance() end
    return "unknown tab: " .. tostring(tabKey)
end

-- Public read-only provider used by the comprehensive diagnostic export. It returns
-- exactly the same text shown on each /nexus log page.
function Nexus.GetDiagnosticPageText(tabKey)
    return LogViewerProvider(tabKey)
end

local function ScheduleKnownDeadlines()
    local now = GetTime()
    if externalPauseUntil and externalPauseUntil > now then
        RequestStepAt(externalPauseUntil)
    end
    if lastDecidedSig and decidedAt and (decidedAt + 0.4) > now then
        RequestStepAt(decidedAt + 0.4)
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
        RequestStepAt(autoUnlockContextSince + 2)
    end
end

local function RunFullStep(trigger, errorSource)
    forceStep = false
    lastFullStepAt = GetTime()
    recomputeStats.fullSteps = recomputeStats.fullSteps + 1
    recomputeStats[trigger] = (recomputeStats[trigger] or 0) + 1
    local ok, err
    if Nexus.Performance and type(Nexus.Performance.Measure) == "function" then
        ok, err = pcall(Nexus.Performance.Measure, "automation.step", Step)
    else
        ok, err = pcall(Step)
    end
    if not ok then
        SetStatus("error (see /nexus err)")
        RecordError(errorSource or "Main.Step", err)
        return false
    end
    ScheduleKnownDeadlines()
    return true
end

-- Immediate repaint hook used when a DPS result is committed. This avoids
-- waiting for the normal poll interval and guarantees the panel reads the
-- newly saved exact-set best from SavedVariables.
function Nexus.RefreshPanel()
    if not initialized or not Adapter.Ready() then return false end
    return RunFullStep("explicit", "RefreshPanel.Step")
end

local function Init()
    if initialized then return end
    Model = Nexus.Model
    Policy = Nexus.Policy
    Ratchet = Nexus.Ratchet
    Strategy = Nexus.Strategy
    Store = Nexus.Store
    Adapter = Nexus.GameAdapter
    Readout = Nexus.Readout
    Panel = Nexus.Panel
    JournalTab = Nexus.JournalTab
    DefaultProfile = Nexus.DefaultProfile
    if not (Model and Policy and Ratchet and Strategy and Store
        and Adapter and Readout and Panel and DefaultProfile
        and Nexus.DiagnosticLogs) then
        return -- missing module: stay uninitialized, retry next event
    end
    local okStore, errStore = pcall(Store.Init)
    if not okStore then
        RecordError("Store.Init", errStore)
        return
    end
    local okLogs, initializedLogs, errLogs = pcall(Nexus.DiagnosticLogs.Init, NexusDB)
    if not okLogs or initializedLogs == false then
        RecordError("DiagnosticLogs.Init", okLogs and errLogs or initializedLogs)
    end
    if Nexus.Errors and Nexus.Errors.Init then
        local okErrors, initializedErrors, errErrors = pcall(Nexus.Errors.Init)
        if not okErrors or initializedErrors == false then
            RecordError("Errors.Init", okErrors and errErrors or initializedErrors)
        end
    end
    if Nexus.Scheduler and Nexus.Scheduler.Init then
        local okScheduler, schedulerFrame = pcall(Nexus.Scheduler.Init)
        if not okScheduler or not schedulerFrame then
            RecordError("Scheduler.Init", okScheduler and "frame unavailable" or schedulerFrame)
        end
    end
    if Nexus.Updates and Nexus.Updates.Init then
        Nexus.Updates.Init({
            notify = function(version)
                Print("Update " .. tostring(version)
                    .. " is available. Installation is manual; open the Nexus update notice to copy the releases page.")
            end,
            refresh = function()
                if Nexus.Panel and Nexus.Panel.Refresh then Nexus.Panel.Refresh() end
            end,
        })
    end
    auditRunId = tonumber(NexusDB and NexusDB.auditRunCounter) or 0
    Adapter.Init({ OnStatus = Print }, Store)
    if Nexus.LogViewer and Nexus.LogViewer.Init then
        Nexus.LogViewer.Init(LogViewerProvider, ClearDiagnosticLogs)
    end
    if Nexus.WishlistEditor and Nexus.WishlistEditor.Init then
        Nexus.WishlistEditor.Init(Adapter, Model)
    end
    if Nexus.WishlistOverlay and Nexus.WishlistOverlay.Init then
        Nexus.WishlistOverlay.Init(Adapter, Model)
        if NexusDB.overlayShown then
            Nexus.WishlistOverlay.Show()
        end
    end
    if Nexus.CommunityBuilds and Nexus.CommunityBuilds.Init then
        Nexus.CommunityBuilds.Init(Adapter, Model)
    end
    if Nexus.Leaderboard and Nexus.Leaderboard.Init then
        Nexus.Leaderboard.Init(Adapter, Model)
    end
    if Nexus.Performance and type(Nexus.Performance.InstallDefaults) == "function" then
        local okPerformance, performanceError = pcall(Nexus.Performance.InstallDefaults)
        if not okPerformance then
            RecordError("Performance.InstallDefaults", performanceError)
        end
    end
    if Nexus.ViewRefresh and Nexus.ViewRefresh.Init then
        local okRefresh, refreshReady = pcall(Nexus.ViewRefresh.Init)
        if not okRefresh or refreshReady == false then
            RecordError("ViewRefresh.Init", okRefresh and "initialization failed" or refreshReady)
        end
    end
    if Nexus.Nameplate and Nexus.Nameplate.Init then
        Nexus.Nameplate.Init()
    end
    if Nexus.ServerStatus and Nexus.ServerStatus.Init then
        Nexus.ServerStatus.Init()
    end
    Panel.Init({ ToggleAuto = function()
        autoEnabled = not autoEnabled
        RequestRecompute()
        Print("auto " .. (autoEnabled and "ON" or "OFF"))
        return autoEnabled   -- Panel uses this to repaint the button NOW
    end, RefreshDisplay = function()
        return Nexus.RefreshHudView()
    end })
    initialized = true
    RequestRecompute()
    Print("v" .. Nexus.VERSION .. " -- type /nexus for commands.")
    if Adapter.RivalDetected() then
        Print("|cffff6060EchoOptimizer detected -- it conflicts with Nexus's board hook. Disable EchoOptimizer; Nexus replaces its functionality.|r")
    end
end

EH = CreateFrame("Frame")
EH:RegisterEvent("ADDON_LOADED")
EH:RegisterEvent("PLAYER_ENTERING_WORLD")
EH:RegisterEvent("PLAYER_LEVEL_UP")
EH:RegisterEvent("CHAT_MSG_CHANNEL")
EH:RegisterEvent("PLAYER_REGEN_DISABLED")
EH:RegisterEvent("PLAYER_REGEN_ENABLED")
EH:RegisterEvent("PLAYER_UPDATE_RESTING")
EH:RegisterEvent("ZONE_CHANGED_NEW_AREA")
EH:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4,
                                 arg5, arg6, arg7, arg8, arg9)
    if event == "ADDON_LOADED" and arg1 == "Nexus" then
        -- SavedVariables are ready here, but the player and Project Ebonhold UI
        -- may not be. Only run the cheap data migration now; defer all frames,
        -- hooks, scanners and catalog work until PLAYER_ENTERING_WORLD.
        if Nexus.Store and Nexus.Store.Init then
            local okStore, errStore = pcall(Nexus.Store.Init)
            if not okStore then RecordError("Store.Init", errStore) end
        end
        if Nexus.DiagnosticLogs and Nexus.DiagnosticLogs.Init then
            local okLogs, initializedLogs, errLogs =
                pcall(Nexus.DiagnosticLogs.Init, NexusDB)
            if not okLogs or initializedLogs == false then
                RecordError("DiagnosticLogs.Init", okLogs and errLogs or initializedLogs)
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        Init()
        if initialized then
            Adapter.OnEvent(event)
            if Store.Settings().autoPick then Adapter.SetSoloPicker() end
            Adapter.RequestSlots()
            if JournalTab then JournalTab.TryInstall(JournalData) end
            if Nexus.Sync and Nexus.Codec then
                Nexus.Sync.Init(Nexus.Codec, Adapter)
            end
            if Nexus.DpsCapture then
                Nexus.DpsCapture.Init(Adapter, Nexus.Sync)
            end
        end
    elseif event == "PLAYER_LEVEL_UP" then
        if initialized then Adapter.OnEvent(event) end
    elseif event == "PLAYER_UPDATE_RESTING" or event == "ZONE_CHANGED_NEW_AREA" then
        if initialized and Nexus.Sync and Nexus.Sync.ContextChanged then
            pcall(Nexus.Sync.ContextChanged, event)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if initialized and Nexus.Sync and Nexus.Sync.ContextChanged then
            pcall(Nexus.Sync.ContextChanged, event)
        end
        if initialized and Nexus.DpsCapture then
            pcall(Nexus.DpsCapture.OnCombatStart)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if initialized and Nexus.DpsCapture then
            pcall(Nexus.DpsCapture.OnCombatEnd)
        end
        if initialized and Nexus.Sync and Nexus.Sync.ContextChanged then
            pcall(Nexus.Sync.ContextChanged, event)
        end
    elseif event == "CHAT_MSG_WHISPER" then
        -- Dev diagnostic: a WLRQ whisper with token "dev" is a status
        -- request from a developer client.  Looks like routine sync traffic.
        if initialized and Nexus.Sync and type(arg1) == "string"
            and arg1:sub(1,5) == "WLRQ|" then
            local parts = {}
            for p in arg1:gmatch("([^|]*)") do parts[#parts+1] = p end
            if parts[4] == "dev" and Nexus.Sync.HandleStatusRequest then
                pcall(Nexus.Sync.HandleStatusRequest, arg2, parts[3])
            end
        end
    elseif event == "CHAT_MSG_CHANNEL" then
        -- 3.3.5 CHAT_MSG_CHANNEL: arg1=text, arg2=sender, arg3=language,
        -- arg4=channel name WITH its number prefix ("5. wrbuildssync"),
        -- arg8=channel number, arg9=bare channel name.
        --
        -- Comparing the bare name against arg4 alone never matched (live
        -- bug 2026-07-24: nothing was ever received, and peers never saw
        -- each other's sync requests either). Accept either form.
        if initialized and Nexus.Sync then
            local want = Nexus.Sync.ChannelName()
            local bare = type(arg9) == "string" and arg9:lower() or nil
            local numbered = nil
            if type(arg4) == "string" then
                numbered = (arg4:lower():gsub("^%s*%d+%.%s*", ""))
            end
            if bare == want or numbered == want then
                local ok, err = pcall(Nexus.Sync.HandleIncoming, arg1, arg2)
                if not ok then
                    RecordError("Sync.HandleIncoming", err)
                    Nexus.Sync.LogEvent("RX", "handler ERROR: %s", ErrorText(err))
                end
            elseif type(arg1) == "string" and arg1:find("^WLR") then
                -- Our protocol seen on a channel we didn't match -- the
                -- single most useful clue if filtering ever breaks again.
                Nexus.Sync.LogEvent("RX",
                    "MISMATCH arg4=%q arg9=%q (wanted %q)",
                    tostring(arg4), tostring(arg9), want)
            end
        end
    end
end)
EH:RegisterEvent("CHAT_MSG_WHISPER")
EH:SetScript("OnUpdate", function(_, elapsed)
    -- Detect unusually long frame stalls. On 3.3.5 these are common during
    -- loading screens and zone transitions and do not indicate a real problem.
    -- Logged silently; never printed to chat.
    if elapsed and elapsed > LAG_THRESHOLD then
        local now = GetTime and GetTime() or 0
        if now - lagWarnedAt > LAG_WARN_COOLDOWN then
            lagWarnedAt = now
            -- Stash for /nexus err if a dev wants to investigate.
            Nexus.lastLagElapsed = elapsed
        end
    end
    if not initialized then return end
    -- OnUpdate fires during the login loading screen (ADDON_LOADED before
    -- PLAYER_ENTERING_WORLD). Running the loop then would call
    -- GetActiveEchoLoadout / UnitClass before the player is known and
    -- poison the client's session char-key + class mask (addendum B5).
    if not Adapter.Ready() then return end
    if Nexus.Sync then
        pcall(Nexus.Sync.OnUpdate, elapsed)
    end
    if Nexus.DpsCapture then
        pcall(Nexus.DpsCapture.OnUpdate, elapsed)
    end
    pollAccum = pollAccum + (elapsed or 0)
    if pollAccum < POLL then return end
    pollAccum = 0
    recomputeStats.polls = recomputeStats.polls + 1
    local okPoll, errPoll = pcall(Adapter.Poll)
    if not okPoll then
        SetStatus("error (see /nexus err)")
        RecordError("GameAdapter.Poll", errPoll)
        return
    end

    local boardDirty, slotsDirty, dataDirty = false, false, false
    if Adapter.ConsumeDirty then
        local okDirty, b, s, d = pcall(Adapter.ConsumeDirty)
        if okDirty then
            boardDirty, slotsDirty, dataDirty = b and true or false,
                s and true or false, d and true or false
        else
            -- Unknown invalidation state is handled conservatively: retain
            -- the direct safe tick and record the failed optimization.
            forceStep = true
            RecordError("GameAdapter.ConsumeDirty", b)
        end
    end
    local now = GetTime()
    local isDirty = boardDirty or slotsDirty or dataDirty
    local deadlineDue = nextStepAt ~= nil and now >= nextStepAt
    local fallbackDue = (now - lastFullStepAt) >= FallbackSeconds()
    if not (forceStep or isDirty or deadlineDue or fallbackDue) then
        recomputeStats.skipped = recomputeStats.skipped + 1
        return
    end
    if deadlineDue then nextStepAt = nil end
    local trigger = forceStep and "forced"
        or isDirty and "dirty"
        or deadlineDue and "deadlines"
        or "fallbacks"
    RunFullStep(trigger, "Main.Step")
end)

SLASH_NEXUS1 = "/nexus"
SLASH_NEXUS2 = "/nx"
SLASH_NEXUS3 = "/wr"   -- legacy alias kept for muscle memory
SlashCmdList["NEXUS"] = function(msg)
    if not initialized then Print("not initialized yet") return end
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local settings = Store.Settings()
    if msg == "auto" then
        autoEnabled = not autoEnabled
        RequestRecompute()
        Print("auto " .. (autoEnabled and "ON" or "OFF"))
        if Panel.SetAuto then Panel.SetAuto(autoEnabled) end
    elseif msg == "panel" then
        Panel.Toggle()
    elseif msg == "restore" then
        Print(Adapter.RestoreAutoAccept() and "client auto-accept restored"
            or "nothing to restore")
        RequestRecompute()
    elseif msg == "flags" then
        for k, v in pairs(EffectiveFlags()) do
            Print(k .. " = " .. tostring(v))
        end
        local st = Store.State()
        for k, why in pairs(st.flagDemotions or {}) do
            Print("demoted " .. k .. ": " .. tostring(why))
        end
    elseif msg == "status" then
        local catalog = Adapter.Catalog()
        local wl = Adapter.Wishlist()
        local slots = Adapter.Slots()
        local owned = Adapter.Owned()
        Print("v" .. Nexus.VERSION .. " -- level " .. Adapter.Level()
            .. ", auto " .. (autoEnabled and "ON" or "OFF"))
        -- Target (wishlist)
        if wl then
            local src = (wl.source == "designed" and "Echo Wishlist build")
                or (wl.source == "active" and "active loadout") or "wishlist"
            Print(string.format("TARGET: |cff7fff7f'%s'|r (your %s) -- %d echoes",
                (wl.name ~= "" and wl.name) or "(unnamed)", src, #wl.entries))
        else
            local note = Adapter.WishlistNote and Adapter.WishlistNote()
            Print("TARGET: none -- advisor only" .. (note and ("  (" .. note .. ")") or ""))
        end
        -- Loadout / snapshot data (the guarantee source)
        if not slots then
            Print("LOADOUTS: slot data not loaded yet (waiting on the server).")
        else
            local nsnap, ndesign = 0, 0
            for _, s in pairs(slots.bySlot) do
                if type(s.echoes) == "table" and #s.echoes > 0 then
                    if s.verified then nsnap = nsnap + 1 else ndesign = ndesign + 1 end
                end
            end
            local act = slots.activeSlot
            if act ~= 0 and slots.bySlot[act] then
                local s = slots.bySlot[act]
                Print(string.format("ACTIVE slot %d '%s': %s, %d echoes", act,
                    (s.name ~= "" and s.name) or "?",
                    s.verified and "snapshot (arms the guarantee)"
                        or "designed build (highlight only -- not a guarantee)",
                    #s.echoes))
            else
                Print("ACTIVE: no build activated right now.")
            end
            Print(string.format("READABLE: %d loadout snapshot(s), %d designed wishlist build(s)",
                nsnap, ndesign))
            if wl and Ratchet and Ratchet.BestSlot then
                local plan = Strategy.Compile(catalog, wl, Store.Settings())
                local best = Ratchet.BestSlot(slots, plan, catalog)
                Print(best and ("Would arm snapshot slot " .. best .. " at level 1.")
                    or "No verified snapshot to arm -- first run seeds one.")
            end
        end
        Print(string.format("OWNED this run: %d echoes (%s).", owned.distinct or 0,
            owned.synced and "synced" or "not synced yet"))
    elseif msg == "wishlist" or msg == "check" then
        local wl = Adapter.Wishlist()
        if not wl then
            local note = Adapter.WishlistNote and Adapter.WishlistNote()
            if note then
                Print(note)
            else
                Print("no wishlist detected -- running as advisor only.")
                Print("Design one in the Echo Journal: 'New Wishlist' (the 'Echo Wishlist'")
                Print("section), pick its echoes, and save it. The addon reads that build.")
            end
        else
            local cat = Adapter.Catalog()
            local src = (wl.source == "designed" and "your Echo Wishlist build")
                or (wl.source == "active" and "your active loadout")
                or "your wishlist"
            local famset = {}
            for _, e in ipairs(wl.entries) do famset[e.family] = true end
            local nfam = 0
            for _ in pairs(famset) do nfam = nfam + 1 end
            Print(string.format("reading |cff7fff7f'%s'|r (from %s) -- %d echoes, %d families",
                (wl.name ~= "" and wl.name) or "(unnamed)", src, #wl.entries, nfam))
            local names = {}
            for _, e in ipairs(wl.entries) do
                local row = cat and cat.rows[e.spellId]
                names[#names + 1] = (row and row.name or ("spell " .. e.spellId))
                    .. (e.stacks > 1 and (" x" .. e.stacks) or "")
            end
            table.sort(names)
            Print("  " .. table.concat(names, ", "))
        end
    elseif msg == "progress" or msg == "missing" then
        local catalog = Adapter.Catalog()
        local wl = Adapter.Wishlist()
        local owned = Adapter.Owned()
        if not wl then
            Print("no wishlist set -- advisor only, nothing to track.")
        else
            local plan = Strategy.Compile(catalog, WishlistWithLockTargets(wl, catalog), Store.Settings())
            local haveN, totalN, missing = WishlistProgress(plan, owned, catalog)
            local pct = (totalN > 0) and math.floor(haveN / totalN * 100 + 0.5) or 0
            Print(string.format("this run: |cff7fff7f%d/%d|r echoes (%d%%) -- %d still short",
                haveN, totalN, pct, #missing))
            if msg == "missing" and #missing > 0 then
                Print("  " .. table.concat(missing, ", "))
            end
        end
    elseif msg == "editor" then
        if Nexus.WishlistEditor then
            Nexus.WishlistEditor.Toggle()
        else
            Print("wishlist editor unavailable")
        end
    elseif msg == "syncdebug" then
        if Nexus.LogViewer then
            Nexus.LogViewer.Show("sync")
        else
            Print("log viewer unavailable")
        end
    elseif msg:sub(1, 6) == "probe " then
        local target = msg:sub(7):match("^%s*(.-)%s*$")
        if target ~= "" and Nexus.Sync and Nexus.Sync.SendStatusTo then
            pcall(Nexus.Sync.SendStatusTo, target)
        end
    elseif msg == "nameplate" then
        local NP = Nexus.Nameplate
        if NP then
            Print("Mouseover tooltip: active.")
            Print("Nexus users seen on the sync mesh are tagged, with leaderboard data when available.")
        else
            Print("Nameplate module not loaded.")
        end
    elseif msg == "dps" then
        if Nexus.Emergency and Nexus.Emergency.dpsDisabled then
            Print(Nexus.Emergency.reason)
            return
        end
        -- Always-on: this just shows the current capture status
        local D = Nexus.DpsCapture
        if not D then Print("DPS capture module not loaded"); return end
        if D.IsDetailsAvailable() then
            Print("|cff4dff80DPS capture is active.|r")
            Print("Fight the Lich King or hit a training dummy to record your best.")
        else
            Print("|cffff9040Details! damage meter is not installed.|r")
            Print("Install Details! to enable DPS tracking on your builds.")
        end
        if Nexus.lastDpsNote then
            Print("Last session: " .. Nexus.lastDpsNote)
        end
        local wl = Adapter.Wishlist()
        if wl and D.GetEchoKey then
            Print("Selected wishlist key: " .. tostring(D.GetEchoKey(wl.entries)))
        end
        if D.GetCurrentEchoKey then
            Print("Current tracked Echo key: " .. tostring(D.GetCurrentEchoKey()))
        end
        Print("Open /nexus log and select DPS for the full capture trace.")
    elseif msg:match("^syncmode") then
        local requested = msg:match("^syncmode%s+(%S+)$")
        if requested and requested ~= "off" and requested ~= "manual"
            and requested ~= "automatic" and requested ~= "auto" then
            Print("usage: /nexus syncmode <automatic|manual|off>")
        elseif requested and Nexus.Sync and Nexus.Sync.SetMode then
            local mode = Nexus.Sync.SetMode(requested)
            Print("Sync mode set to " .. tostring(mode)
                .. ". Sync runs only while resting and in a safe context.")
        elseif Nexus.Sync and Nexus.Sync.GetEffectiveState then
            local state = Nexus.Sync.GetEffectiveState()
            Print("Sync: " .. tostring(state.label)
                .. (state.reason and (" (" .. tostring(state.reason) .. ")") or ""))
        else
            Print("sync unavailable")
        end
    elseif msg:match("^synclimits") then
        local retentionMode = msg:match("^synclimits%s+(%S+)$")
        local top, perClass, average, averagePerClass, other, perAuthor = msg:match(
            "^synclimits%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)$")
        if retentionMode == "on" or retentionMode == "off" then
            settings.communityRetentionEnabled = retentionMode == "on"
            if Nexus.DataRetention and Nexus.DataRetention.Enforce then
                pcall(Nexus.DataRetention.Enforce, NexusDB,
                    "retention " .. retentionMode)
            end
        elseif top then
            settings.communityRetentionEnabled = true
            settings.communityRetentionTopPerCategory = tonumber(top)
            settings.communityRetentionMinPerClassPerCategory = tonumber(perClass)
            settings.communityRetentionTopAverage = tonumber(average)
            settings.communityRetentionMinAveragePerClass = tonumber(averagePerClass)
            settings.communityRetentionOtherRemoteBuilds = tonumber(other)
            settings.communityRetentionMaxPerAuthor = tonumber(perAuthor)
            local limits = Nexus.DataRetention and Nexus.DataRetention.Limits
                and Nexus.DataRetention.Limits(NexusDB) or nil
            if limits then
                settings.communityRetentionTopPerCategory = limits.topPerCategory
                settings.communityRetentionMinPerClassPerCategory = limits.minPerClassPerCategory
                settings.communityRetentionTopAverage = limits.topAverage
                settings.communityRetentionMinAveragePerClass = limits.minAveragePerClass
                settings.communityRetentionOtherRemoteBuilds = limits.otherRemoteBuilds
                settings.communityRetentionMaxPerAuthor = limits.remotePerAuthor
                pcall(Nexus.DataRetention.Enforce, NexusDB, "settings changed")
            end
        elseif msg ~= "synclimits" then
            Print("usage: /nexus synclimits <on|off> or <D/L top> <D/L class> <avg top> <avg class> <other> <author>")
        end
        local limits = Nexus.DataRetention and Nexus.DataRetention.Limits
            and Nexus.DataRetention.Limits(NexusDB) or nil
        if limits then
            Print(limits.enabled
                and "Ranked retention: ON (custom limits active)."
                or "Ranked retention: OFF (relaxed hard safety ceilings remain).")
            Print(string.format("DPS retention: %d overall + %d/class for Dummy and LK; %d overall + %d/class for Average.",
                limits.topPerCategory, limits.minPerClassPerCategory,
                limits.topAverage, limits.minAveragePerClass))
            Print(string.format("Other community builds: %d total, %d per author.",
                limits.otherRemoteBuilds, limits.remotePerAuthor))
            Print("Set mode: /nexus synclimits <on|off>")
            Print("Set custom limits (also enables): /nexus synclimits <raw-top> <raw-per-class> <avg-top> <avg-per-class> <other> <per-author>")
        else
            Print("retention settings unavailable")
        end
    elseif msg == "sync" then
        if Nexus.Sync then
            local ok, err = Nexus.Sync.RequestSync()
            if ok then
                Print("asking other players for their builds -- results appear in /nexus builds")
            else
                Print(tostring(err))
            end
        else
            Print("sync unavailable")
        end
    elseif msg == "builds" then
        if Nexus.CommunityBuilds then
            Nexus.CommunityBuilds.Toggle()
        else
            Print("Nexus Builds unavailable")
        end
    elseif msg == "leaderboard" or msg == "ranks" then
        if Nexus.Leaderboard then
            Nexus.Leaderboard.Toggle()
        else
            Print("Nexus Leaderboard unavailable")
        end
    elseif msg == "log errors" or msg == "errors" then
        if Nexus.LogViewer then
            Nexus.LogViewer.Show("errors")
        else
            Print("log viewer unavailable")
        end
    elseif msg == "perf" or msg == "performance" then
        if Nexus.LogViewer then
            Nexus.LogViewer.Show("perf")
        else
            Print("performance diagnostics unavailable")
        end
    elseif msg == "log" or msg == "logs" then
        if Nexus.LogViewer then
            Nexus.LogViewer.Toggle()
        else
            Print("log viewer unavailable")
        end
    elseif msg == "err" then
        local latest
        if Nexus.Errors and type(Nexus.Errors.Latest) == "function" then
            local okLatest, retained = pcall(Nexus.Errors.Latest)
            if okLatest then latest = retained end
        end
        Print(latest and latest.message or ErrorText(Nexus.lastError))
    elseif msg == "undemote" then
        local st = Store.State()
        st.flagDemotions = {}
        RequestRecompute()
        Print("flag demotions cleared (they re-arm on fresh evidence)")
    elseif msg == "overlay" then
        if Nexus.WishlistOverlay then
            Nexus.WishlistOverlay.Toggle()
        else
            Print("overlay unavailable")
        end
    elseif msg:match("^anchor") then
        local arg = msg:match("^anchor%s+(%S+)")
        if arg == "off" or arg == nil then
            settings.anchorSpellId = nil
            Print("anchor cleared")
        else
            settings.anchorSpellId = tonumber(arg)
            Print("anchor set to " .. tostring(settings.anchorSpellId))
        end
        RequestRecompute()
    else
        -- Showing the general status/help surface is an explicit user refresh.
        -- This also keeps retired diagnostic command aliases harmless without
        -- letting them suppress the next normal ownership snapshot.
        RequestRecompute()
        Print("v" .. Nexus.VERSION .. " -- " .. statusLine)
        Print("|cffffd200Nexus v" .. Nexus.VERSION .. "|r  --  /nexus (or /nx, /wr)")
        Print("|cffffd200Setup:|r  builds  |  leaderboard  |  editor  |  sync  |  overlay")
        Print("|cffffd200Sync:|r   syncmode <automatic|manual|off>  |  sync")
        Print("|cffffd200Limits:|r synclimits <on|off>  |  synclimits <D/L top> <D/L class> <avg top> <avg class> <other> <author>")
        Print("|cffffd200Run:|r    auto  |  panel  |  status  |  wishlist  |  progress")
        Print("|cffffd200Data:|r   log  |  perf  |  dps  |  nameplate  |  logclear")
        Print("|cffffd200Fixes:|r  flags  |  undemote  |  anchor <id|off>  |  restore  |  err")
    end
end
