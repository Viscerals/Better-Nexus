-- Nexus: logic/Policy.lua
-- Pure per-board decision engine, v2 quality- and guarantee-aware greedy.
-- Board model: 2 free slots + at most 1 guaranteed (flag-3) card; select
-- is mandatory; freeze does NOT consume the board (freeze fires, then the
-- take happens on the next tick of the same board), which makes banking a
-- stacking-wishlist card nearly free. Policy PROPOSES; the adapter
-- re-checks and may drop. Never targets a guaranteed/frozen/carried/
-- justFrozen card with banish/reroll. No WoW API calls; plain Lua 5.1.
--
-- The live-play rules this version encodes (2026-07-24 session, freeze
-- self-block confirmed 2026-08-01 via structured log analysis across
-- 3,221 distinct boards -- Dev Test 63/Dev Test 2):
--  A. QUALITY GATE -- a below-wished-quality copy of a single-stack,
--     multi-quality family (the stat echoes) scores qualityMiss (< filler):
--     taking it locks the family at the wrong quality AND poisons the
--     saved loadout. The wished quality per family comes from the
--     wishlist itself (plan.targets[fam].wishedQuality) -- no hardcoded
--     stat list.
--  B. DEFER -- a free-slot wished card whose guarantee is still pending
--     (family present in the predicted queue) will come back on its own;
--     its take-value is discounted by deferFactor so a one-shot pick
--     (guaranteed head, banked stack copy, at-quality stat catch) never
--     loses to it. An at-or-above-wished-quality catch of a multi-quality
--     family is NEVER deferred: the guarantee is level-gated and may only
--     serve the low-quality variant, so the free-slot catch is the real
--     opportunity.
--  C. BANK -- freeze only a wanted side copy that is not already fully
--     covered by owned copies plus the remaining exact Saved Build floor,
--     AND only when that family's own guarantee is already exhausted
--     (not pendingFam -- see below). Confirmed live: while a copy of a
--     family sits frozen anywhere on the board, the server will not
--     guarantee another copy of that SAME family in slot 3 -- other
--     families are unaffected (0 of 76 Quick-Hands-guaranteed boards had
--     Quick Hands frozen, across 3,221 distinct boards; a Double-Strike-
--     frozen control board still guaranteed Quick Hands normally). So
--     freezing a family whose guarantee is still open (pendingFam true)
--     would silence the exact channel meant to deliver its remaining
--     copies -- Dev Test 63: Rare Quick Hands frozen at owned=0
--     self-blocked its own guarantee for 4 straight boards while other
--     wanted guarantees kept arriving normally. Once a family's guarantee
--     is exhausted (pendingFam false -- baseline restored, or it was
--     never in the Saved Build to begin with), freezing it costs nothing
--     on that front and this rule applies as before: bank it while a
--     DIFFERENT wanted guarantee is taken. The precious-catch pass (a
--     one-shot multi-quality catch) is exempt from the pendingFam check --
--     its guarantee is already known to serve the wrong quality tier, so
--     nothing of value is lost by freezing it either way.
--  D. RETRIEVE -- once ANY copy is held/frozen, take it back the moment
--     doing so is FREE -- i.e. slot 3 is not a different wanted
--     guarantee. Never sacrifices a different wanted guarantee to
--     retrieve early: rule C only ever freezes a family whose own
--     guarantee was already exhausted, so once something is actually
--     held there is no self-block risk left to race against -- holding
--     it one more board costs that family nothing. Live 2026-08-01 (run
--     2) proved the earlier "always retrieve, even over a different
--     wanted guarantee" version wrong: it cost a guaranteed, single-copy
--     Ember Spark (its only guaranteed appearance all run, permanently
--     forfeited -- see "Absolute one-shot rule" below) to retrieve a
--     Ferocious Bond extra one board sooner, for zero actual benefit.
--     This replaces the older HeldBaselineReady threshold wait too: no
--     artificial delay needed either, since the very first board where
--     slot 3 isn't a competing wanted guarantee is free to take.

Nexus = Nexus or {}
local Policy = {}
Nexus.Policy = Policy

local NEG_INF = -math.huge

-- Resolved at call time, never at file load (load order is not ours).
local Model

local function GetModel()
    Model = Model or Nexus.Model
    return Model
end

local function OwnedFam(owned, fam)
    if fam == nil or type(owned) ~= "table" then return 0 end
    local byFamily = owned.byFamily
    return (type(byFamily) == "table" and tonumber(byFamily[fam])) or 0
end

local function Wished(plan, fam)
    return fam ~= nil and type(plan.wishedFamilies) == "table"
        and plan.wishedFamilies[fam] and true or false
end

local function WishedQuality(plan, fam)
    local t = type(plan.targets) == "table" and plan.targets[fam] or nil
    return (type(t) == "table" and tonumber(t.wishedQuality)) or 0
end

-- Base annotation: guaranteed > wanted > duplicate > filler > junk.
-- Decide overlays "banked" / "returns later" / "low quality" after the
-- effective-value pass.
local function Annotation(card, delta, plan, owned)
    if card.isGuaranteed then return "guaranteed" end
    local fam = card.family
    local wished = Wished(plan, fam)
    if wished and delta > 0 then return "wanted" end
    local have = OwnedFam(owned, fam)
    local cap = 1
    if wished and type(plan.targets) == "table" and plan.targets[fam] ~= nil then
        cap = plan.targets[fam].targetStacks or 1
    end
    if have > 0 and have >= cap then return "duplicate" end
    if not wished then return "filler" end
    return "junk"
end

local function IsFrozen(card)
    return card.isFrozen or card.isCarried or card.justFrozen
end

local function IsWanted(model, card, delta, plan, owned, catalog)
    if not (delta and delta > 0 and Wished(plan, card.family)) then
        return false
    end
    if type(model.FamilyMultiQuality) == "function"
        and model.FamilyMultiQuality(catalog, card.family) then
        if type(model.QualityOfferNeeded) == "function" then
            return model.QualityOfferNeeded(
                plan, catalog, card.family,
                tonumber(card.quality) or 0, owned, card.spellId)
        end
        local bySpell = type(owned) == "table" and owned.bySpell or nil
        local required = type(model.EffectiveWishedQuality) == "function"
            and model.EffectiveWishedQuality(
                plan, catalog, card.family, OwnedFam(owned, card.family), bySpell)
            or WishedQuality(plan, card.family)
        return (tonumber(card.quality) or 0) >= (tonumber(required) or 0)
    end
    return true
end

local function IsOneShot(model, card, plan, owned, catalog)
    local have = OwnedFam(owned, card.family)
    if type(model.TargetProgress) == "function" then
        have = model.TargetProgress(plan, catalog, card.family, owned)
    end
    return have <= 0 and type(model.FamilyMultiQuality) == "function"
        and model.FamilyMultiQuality(catalog, card.family)
        and (type(model.QualityOfferNeeded) ~= "function"
            or model.QualityOfferNeeded(
                plan, catalog, card.family,
                tonumber(card.quality) or 0, owned, card.spellId))
end

local function WantedTier(model, card, plan, owned, catalog)
    if type(model.StackWishBelowTarget) == "function"
        and model.StackWishBelowTarget(
            plan, owned, card.family, catalog) then
        return 1
    end
    if IsOneShot(model, card, plan, owned, catalog) then return 2 end
    return 3
end

local function BetterWanted(model, cards, deltas, plan, owned, catalog,
    candidate, incumbent)
    if incumbent == nil then return true end
    local ct = WantedTier(model, cards[candidate], plan, owned, catalog)
    local it = WantedTier(model, cards[incumbent], plan, owned, catalog)
    if ct ~= it then return ct < it end
    if deltas[candidate] ~= deltas[incumbent] then
        return deltas[candidate] > deltas[incumbent]
    end
    return candidate < incumbent
end

local function QueueCanDeliverWanted(model, state, card, plan, owned, catalog)
    local queue = type(state.queue) == "table" and state.queue.entries or nil
    if type(queue) ~= "table" or card.family == nil then return false end
    for i = 1, #queue do
        local entry = queue[i]
        if type(entry) == "table" and entry.wanted == true
            and entry.family == card.family then
            if type(model.FamilyMultiQuality) ~= "function"
                or not model.FamilyMultiQuality(catalog, card.family) then
                return true
            end
            local rows = type(catalog) == "table" and catalog.rows or nil
            local row = type(rows) == "table"
                and rows[tonumber(entry.spellId)] or nil
            local quality = type(row) == "table"
                and tonumber(row.quality) or tonumber(entry.quality)
            if quality and type(model.QualityOfferNeeded) == "function"
                and model.QualityOfferNeeded(
                    plan, catalog, card.family, quality, owned) then
                return true
            end
        end
    end
    return false
end

local function FreezeWorthy(model, state, card, plan, owned, catalog)
    if type(model.StackWishBelowTarget) == "function"
        and model.StackWishBelowTarget(
            plan, owned, card.family, catalog) then
        return true
    end
    return not QueueCanDeliverWanted(
        model, state, card, plan, owned, catalog)
end

local function TakeAction(cards, annotations, deltas, index, reason)
    return {
        type = "take", index = index, spellId = cards[index].spellId,
        reason = reason, annotations = annotations, deltas = deltas,
    }
end

local function Endgame(action)
    action.endgame = true
    return action
end

local function SafeBanishCandidate(cards, deltas, plan, gIndex)
    local worst, worstDelta = nil, nil
    for i = 1, #cards do
        local card = cards[i]
        if i ~= gIndex
            and not (card.isGuaranteed or card.isFrozen or card.isCarried
                or card.justFrozen)
            and not Wished(plan, card.family)
            and (worst == nil or deltas[i] < worstDelta
                or (deltas[i] == worstDelta and i < worst)) then
            worst, worstDelta = i, deltas[i]
        end
    end
    return worst
end

local function LeastHarmfulSide(cards, annotations, deltas, gIndex)
    local anyNonDuplicate = false
    for i = 1, #cards do
        if i ~= gIndex and not cards[i].isGuaranteed
            and not cards[i].justFrozen
            and annotations[i] ~= "duplicate" then
            anyNonDuplicate = true
            break
        end
    end
    local pick = nil
    for i = 1, #cards do
        local eligible = i ~= gIndex and not cards[i].isGuaranteed
            and not cards[i].justFrozen
            and ((not anyNonDuplicate) or annotations[i] ~= "duplicate")
        if eligible and (pick == nil
            or deltas[i] > deltas[pick]
            or (deltas[i] == deltas[pick]
                and annotations[pick] == "filler"
                and annotations[i] ~= "filler")
            or (deltas[i] == deltas[pick]
                and (annotations[i] == "filler")
                    == (annotations[pick] == "filler")
                and (tonumber(cards[i].quality) or 0)
                    < (tonumber(cards[pick].quality) or 0))
            or (deltas[i] == deltas[pick]
                and (tonumber(cards[i].quality) or 0)
                    == (tonumber(cards[pick].quality) or 0)
                and i < pick)) then
            pick = i
        end
    end
    return pick
end

local function MissingAfterFallback(plan, owned, fallbackCard, catalog)
    local simulated = { byFamily = {}, bySpell = {} }
    for family, count in pairs(type(owned) == "table" and owned.byFamily or {}) do
        simulated.byFamily[family] = tonumber(count) or 0
    end
    for spellId, count in pairs(type(owned) == "table" and owned.bySpell or {}) do
        simulated.bySpell[spellId] = tonumber(count) or 0
    end
    if type(fallbackCard) == "table" then
        local family = fallbackCard.family
            or (type(catalog) == "table"
                and type(catalog.familyOf) == "table"
                and catalog.familyOf[tonumber(fallbackCard.spellId)])
        local count = tonumber(fallbackCard.stacks or fallbackCard.count) or 1
        if family ~= nil then
            simulated.byFamily[family] =
                (tonumber(simulated.byFamily[family]) or 0) + count
        end
        local spellId = tonumber(fallbackCard.spellId)
        if spellId then
            simulated.bySpell[spellId] =
                (tonumber(simulated.bySpell[spellId]) or 0) + count
        end
    end
    for family in pairs(type(plan) == "table" and plan.wishedFamilies or {}) do
        local have, want
        local model = GetModel()
        if type(model.TargetProgress) == "function" then
            have, want = model.TargetProgress(plan, catalog, family, simulated)
        else
            local target = type(plan.targets) == "table" and plan.targets[family]
            want = type(target) == "table" and tonumber(target.targetStacks) or 1
            have = tonumber(simulated.byFamily[family]) or 0
        end
        if have < math.max(1, tonumber(want) or 1) then return true end
    end
    return false
end

-- state = { board, owned, charges, plan, queue, flags, level, horizon,
--           support, params, canFreeze, rerollBudget [, catalog] }
-- Returns { type = "take"|"freeze"|"reroll"|"banish"|"wait", spellId=?,
--   index=?, reason = s, annotations = { [cardIndex] = s },
--   deltas = { [cardIndex] = n } }
-- Pure: same input, same output; malformed input degrades to "wait".
function Policy.Decide(state)
    local annotations = {}
    if type(state) ~= "table" then
        return { type = "wait", reason = "no board", annotations = annotations }
    end
    local Model = GetModel()
    if not Model or type(Model.Delta) ~= "function" then
        return { type = "wait", reason = "model unavailable", annotations = annotations }
    end

    local board = state.board
    local rawCards = type(board) == "table" and board.cards or nil
    if type(rawCards) ~= "table" or #rawCards == 0 then
        return { type = "wait", reason = "no board", annotations = annotations }
    end

    local owned = state.owned
    local plan = state.plan or { advisorOnly = true }
    local params = state.params or {}
    local charges = state.charges or {}
    local flags = state.flags or {}
    local level = tonumber(state.level)
    local catalog = state.catalog

    local cards = {}
    for i = 1, #rawCards do
        local c = rawCards[i]
        cards[i] = type(c) == "table" and c or {}
    end
    local n = #cards

    -- Guaranteed card first (annotation + defer logic both need it).
    local gIndex = board.guaranteedIndex
    if gIndex and not cards[gIndex] then gIndex = nil end
    if not gIndex then
        for i = 1, n do
            if cards[i].isGuaranteed then gIndex = i break end
        end
    end

    -- Families with a pending guarantee (the predicted queue).
    local pendingFam = {}
    do
        local entries = state.queue and state.queue.entries or nil
        if type(entries) == "table" then
            for i = 1, #entries do
                local e = entries[i]
                if type(e) == "table" and e.family ~= nil then
                    pendingFam[e.family] = true
                end
            end
        end
    end

    -- Deltas, effective take-values, annotations. Effective value is what
    -- the take comparison uses; raw delta is what the UI shows.
    --
    -- Locked Echoes (the account's up-to-6 permanent picks, GameAdapter's
    -- LockedOwned/GetLockedPerks) are deliberately excluded from `owned`
    -- (GameAdapter.lua: "never part of the current run's rolled ownership...
    -- board decisions"). But every scoring/annotation path below reads
    -- ownedSafe to decide whether a family/spellId is still needed -- without
    -- folding locked coverage in here, Policy keeps treating an
    -- already-permanently-secured Echo as still wanted (freezing side copies
    -- for it, deferring on it, scoring guaranteed offers of it as "wanted")
    -- when it can never need another copy again. Folded in once, here, so
    -- every downstream read (Annotation, Model.Delta, the precious-catch and
    -- BANK checks, OwnedFam) sees it consistently.
    local ownedSafe = owned or {}
    local function TrustedLocked(value)
        if type(value) ~= "table" or value.synced ~= true
            or type(value.bySpell) ~= "table"
            or type(value.byFamily) ~= "table" then return false end
        for id, count in pairs(value.bySpell) do
            id, count = tonumber(id), tonumber(count)
            if not id or id <= 0 or id ~= math.floor(id)
                or not count or count < 0 or count >= math.huge
                or count ~= math.floor(count) then return false end
        end
        for _, count in pairs(value.byFamily) do
            count = tonumber(count)
            if not count or count < 0 or count >= math.huge
                or count ~= math.floor(count) then return false end
        end
        return true
    end
    if TrustedLocked(state.locked) then
        local merged = { synced = ownedSafe.synced, bySpell = {}, byFamily = {} }
        for id, n in pairs(ownedSafe.bySpell or {}) do merged.bySpell[id] = n end
        for fam, n in pairs(ownedSafe.byFamily or {}) do merged.byFamily[fam] = n end
        for id, n in pairs(state.locked.bySpell or {}) do
            merged.bySpell[id] = (merged.bySpell[id] or 0) + (tonumber(n) or 0)
        end
        for fam, n in pairs(state.locked.byFamily or {}) do
            merged.byFamily[fam] = (merged.byFamily[fam] or 0) + (tonumber(n) or 0)
        end
        ownedSafe = merged
    end

    -- Exact active Saved Build coverage. The server guarantees reaching this
    -- count; copies taken early count toward the baseline rather than adding
    -- on top of it.
    local function SnapshotExact(spellId)
        local total = 0
        local activeEchoes = state.activeEchoes
        if type(activeEchoes) == "table" then
            for activeIndex = 1, #activeEchoes do
                local ae = activeEchoes[activeIndex]
                if type(ae) == "table"
                    and tonumber(ae.spellId) == tonumber(spellId) then
                    total = total
                        + math.max(1, tonumber(ae.count or ae.stack or ae.stacks) or 1)
                end
            end
        end
        return total
    end

    local function OwnedExact(spellId)
        if type(ownedSafe.bySpell) ~= "table" then return 0 end
        return tonumber(ownedSafe.bySpell[spellId]) or 0
    end

    local deltas, eff, wanted = {}, {}, {}
    local precious = {}   -- [i]=true: one-shot quality catch (see loop)
    local deferFactor = tonumber(params.deferFactor) or 0.35
    local bankedWantedOnBoard = false
    for i = 1, n do
        local card = cards[i]
        local d = Model.Delta(plan, ownedSafe, card.spellId, catalog, params)
        d = tonumber(d) or 0
        deltas[i] = d
        wanted[i] = IsWanted(Model, card, d, plan, ownedSafe, catalog)
        annotations[i] = Annotation(card, d, plan, ownedSafe)
        eff[i] = d

        local fam = card.family
        local frozenish = card.isFrozen or card.isCarried or card.justFrozen
        -- Precious catch: an at/above-wished-quality roll of a
        -- multi-quality wished, uncovered family. One-shot regardless of
        -- the guarantee queue -- the level-gated guarantee may only ever
        -- serve the low variant, so THIS roll is the opportunity.
        if not frozenish and d > 0 and Wished(plan, fam)
            and OwnedFam(ownedSafe, fam) <= 0
            and type(Model.FamilyMultiQuality) == "function"
            and Model.FamilyMultiQuality(catalog, fam)
            and (tonumber(card.quality) or 0)
                >= Model.EffectiveWishedQuality(plan, catalog, fam) then
            precious[i] = true
        end
        if frozenish and wanted[i] then
            -- Banked: already secured with a freeze. Rule C only ever
            -- freezes a family whose own guarantee was already exhausted
            -- (see header), so holding it costs that family nothing
            -- further. Rule D (below, before the BANK block and the
            -- one-shot guaranteed rule) retrieves it as soon as doing so
            -- is free -- i.e. not over a different wanted guarantee -- so
            -- no eff[] suppression is needed here.
            annotations[i] = "banked"
            bankedWantedOnBoard = true
        elseif i ~= gIndex and not frozenish and wanted[i]
            and Wished(plan, fam) and OwnedFam(ownedSafe, fam) <= 0
            and pendingFam[fam] then
            -- Pending guarantee: it comes back. Unless this roll is a
            -- precious catch (above) -- then never defer.
            if not precious[i] then
                eff[i] = d * deferFactor
                annotations[i] = "returns later"
            end
        elseif Wished(plan, fam) and d < 0
            and annotations[i] ~= "duplicate" then
            -- Negative delta on a non-duplicate wished family = the
            -- quality gate fired (Model.Delta rule A), whether on the
            -- first copy or a stack top-up.
            annotations[i] = "low quality"
        end
    end

    -- Wait states (annotated boards still returned so the UI renders).
    if (owned == nil or owned.synced == false) and level and level > 1 then
        return { type = "wait", reason = "unsynced",
            annotations = annotations, deltas = deltas }
    end
    if plan.advisorOnly then
        return { type = "wait", reason = "advisor",
            annotations = annotations, deltas = deltas }
    end

    local gDelta = gIndex and deltas[gIndex] or nil
    local gWanted = gIndex ~= nil and wanted[gIndex] == true
    -- The quality gate makes a wrong-quality guaranteed head score
    -- negative, so gWanted is false for it and every "Taking guaranteed echo"
    -- path below is naturally skipped -- exactly the gray-Armor-Pen case.

    -- The end of a pending-roll batch is not the end of the run until level
    -- 80.  At that point the last selectable Echo needs a separate search
    -- policy so a safe frozen fallback survives Banish/Reroll attempts.
    local finalSelection = (level or 0) >= 80
        and type(state.horizon) == "number"
        and state.horizon == 1
    local unusableGuarantee = gIndex ~= nil and not gWanted

    -- Reject an off-wishlist guarantee during ordinary leveling. Prefer a
    -- useful side offer, otherwise spend only trustworthy search actions and
    -- never loop an action the adapter already reported as refused.
    if unusableGuarantee and not finalSelection then
        local bestWantedSide, wantedFreezeResolving = nil, false
        for i = 1, n do
            if i ~= gIndex and wanted[i] then
                if not FreezeWorthy(
                    Model, state, cards[i], plan, ownedSafe, catalog) then
                    annotations[i] = "returns later"
                elseif cards[i].justFrozen then
                    wantedFreezeResolving = true
                elseif BetterWanted(
                    Model, cards, deltas, plan, ownedSafe, catalog,
                    i, bestWantedSide) then
                    bestWantedSide = i
                end
            end
        end
        if bestWantedSide then
            return TakeAction(cards, annotations, deltas, bestWantedSide,
                "Reject off-wishlist guarantee; take missing wishlist side Echo")
        end
        if wantedFreezeResolving then
            return {
                type = "wait",
                reason = "Wanted side Freeze is resolving before rejecting "
                    .. "off-wishlist guarantee",
                annotations = annotations,
                deltas = deltas,
            }
        end

        local refused = type(state.searchRefused) == "table"
            and state.searchRefused or {}
        if state.allowBanish ~= false and not refused.banish
            and (tonumber(charges.banish) or 0) > 0
            and charges.trustworthy == true
            and not charges.banishSpentThisPush then
            local worst = SafeBanishCandidate(cards, deltas, plan, gIndex)
            if worst then
                return {
                    type = "banish",
                    index = worst,
                    spellId = cards[worst].spellId,
                    reason = "Replace off-wishlist guarantee: Banish safe "
                        .. "side to search for a missing wishlist Echo",
                    annotations = annotations,
                    deltas = deltas,
                }
            end
        end
        if not refused.reroll and (tonumber(charges.reroll) or 0) > 0
            and charges.trustworthy == true then
            return {
                type = "reroll",
                reason = "Replace off-wishlist guarantee: Reroll side choices "
                    .. "for a missing wishlist Echo",
                annotations = annotations,
                deltas = deltas,
            }
        end

        local side = LeastHarmfulSide(cards, annotations, deltas, gIndex)
        if side then
            return TakeAction(cards, annotations, deltas, side,
                "Reject off-wishlist guarantee; take least-harmful side")
        end
        return {
            type = "wait",
            reason = "Off-wishlist guarantee has no selectable side",
            annotations = annotations,
            deltas = deltas,
        }
    end

    -- Below level 80, spend at most one safe Banish per fresh run-data push.
    -- Never pre-empt a wanted side offer that still needs protection.
    if level and level < 80 then
        local hasWantedSide, hasUnbankedWantedSide = false, false
        for i = 1, n do
            if i ~= gIndex and wanted[i] then
                hasWantedSide = true
                if not IsFrozen(cards[i]) then
                    hasUnbankedWantedSide = true
                    break
                end
            end
        end
        local wantedSideBlocksBanish
        if gIndex then
            wantedSideBlocksBanish = hasUnbankedWantedSide
        else
            wantedSideBlocksBanish = hasWantedSide
        end
        local refused = type(state.searchRefused) == "table"
            and state.searchRefused or {}
        if not wantedSideBlocksBanish and state.allowBanish ~= false
            and not refused.banish
            and (tonumber(charges.banish) or 0) > 0
            and charges.trustworthy == true
            and not charges.banishSpentThisPush then
            local worst = SafeBanishCandidate(cards, deltas, plan, gIndex)
            if worst then
                return {
                    type = "banish",
                    index = worst,
                    spellId = cards[worst].spellId,
                    reason = "Early search: Banish safe off-wishlist side "
                        .. "before normal roll sequencing",
                    annotations = annotations,
                    deltas = deltas,
                }
            end
        end
    end

    if finalSelection then
        local bestFrozen, bestVisible = nil, nil
        for i = 1, n do
            local card = cards[i]
            if wanted[i] and not card.justFrozen then
                if card.isFrozen or card.isCarried then
                    if BetterWanted(
                        Model, cards, deltas, plan, ownedSafe, catalog,
                        i, bestFrozen) then
                        bestFrozen = i
                    end
                elseif i ~= gIndex and not card.isGuaranteed
                    and BetterWanted(
                        Model, cards, deltas, plan, ownedSafe, catalog,
                        i, bestVisible) then
                    bestVisible = i
                end
            end
        end

        if bestVisible and (not bestFrozen
            or BetterWanted(
                Model, cards, deltas, plan, ownedSafe, catalog,
                bestVisible, bestFrozen)) then
            return Endgame(TakeAction(
                cards, annotations, deltas, bestVisible,
                bestFrozen
                    and ("Final selection: better remaining wishlist Echo "
                        .. "replaces frozen target")
                    or "Final selection: take wanted side Echo before search"))
        end

        local protectedIndex = bestFrozen or gIndex
        local protectedWanted = bestFrozen ~= nil
            or (gIndex ~= nil and wanted[gIndex] == true)
        local fallbackCard = protectedWanted and cards[protectedIndex] or nil
        local searchPending = protectedIndex ~= nil
            and MissingAfterFallback(plan, ownedSafe, fallbackCard, catalog)
        if searchPending then
            local refused = type(state.searchRefused) == "table"
                and state.searchRefused or {}
            if state.allowBanish ~= false and not refused.banish
                and (tonumber(charges.banish) or 0) > 0
                and charges.trustworthy == true
                and not charges.banishSpentThisPush then
                local worst = SafeBanishCandidate(cards, deltas, plan, gIndex)
                if worst then
                    return Endgame({
                        type = "banish",
                        index = worst,
                        spellId = cards[worst].spellId,
                        reason = "Final selection: safe Banish searches for "
                            .. "another missing wanted Echo",
                        annotations = annotations,
                        deltas = deltas,
                    })
                end
            end

            local rerollSafe = bestFrozen ~= nil
                or gIndex == nil
                or wanted[gIndex] ~= true
                or flags.REROLL_HOLDS_GUARANTEED == true
            if not refused.reroll
                and (tonumber(charges.reroll) or 0) > 0
                and charges.trustworthy == true
                and rerollSafe then
                local reason
                if bestFrozen then
                    reason = "Final selection: Reroll searches while "
                        .. "the frozen wanted Echo remains protected"
                elseif gIndex and wanted[gIndex] then
                    reason = "Final selection: Reroll searches while "
                        .. "the guaranteed wanted Echo is held"
                else
                    reason = "Final selection: Reroll searches past "
                        .. "a non-wanted guaranteed Echo"
                end
                return Endgame({
                    type = "reroll",
                    reason = reason,
                    annotations = annotations,
                    deltas = deltas,
                })
            end
        end

        if bestFrozen then
            local reason = "Final selection: search exhausted or unavailable; "
                .. "take frozen wanted Echo"
            local refused = type(state.searchRefused) == "table"
                and state.searchRefused or {}
            if refused.banish or refused.reroll then
                reason = "Final selection: search action refused; "
                    .. "take frozen wanted Echo"
            end
            return Endgame(TakeAction(
                cards, annotations, deltas, bestFrozen, reason))
        end
    end

    if finalSelection and unusableGuarantee then
        local side = LeastHarmfulSide(cards, annotations, deltas, gIndex)
        if side then
            return Endgame(TakeAction(cards, annotations, deltas, side,
                "Final selection: reject off-wishlist guarantee"))
        end
        return Endgame({
            type = "wait",
            reason = "Final off-wishlist guarantee has no selectable side",
            annotations = annotations,
            deltas = deltas,
        })
    end

    -- Phase A: protect one useful side offer, then drain the guaranteed queue.
    if gIndex then
        local bestUnbanked, hasBankedWanted = nil, false
        for i = 1, n do
            if i ~= gIndex and wanted[i] then
                if IsFrozen(cards[i]) then
                    hasBankedWanted = true
                elseif FreezeWorthy(
                    Model, state, cards[i], plan, ownedSafe, catalog) then
                    if BetterWanted(
                        Model, cards, deltas, plan, ownedSafe, catalog,
                        i, bestUnbanked) then
                        bestUnbanked = i
                    end
                else
                    annotations[i] = "returns later"
                end
            end
        end

        if hasBankedWanted then
            return TakeAction(cards, annotations, deltas, gIndex,
                "Take guaranteed; wanted side Echo is safely frozen")
        end

        if bestUnbanked then
            local freezeAvailable = (tonumber(charges.freeze) or 0) > 0
                and charges.trustworthy == true
                and state.canFreeze ~= false
                and not cards[bestUnbanked].isGuaranteed
            if freezeAvailable then
                return {
                    type = "freeze",
                    index = bestUnbanked,
                    spellId = cards[bestUnbanked].spellId,
                    reason = "Freeze wanted side Echo; take guaranteed after it resolves",
                    steps = {
                        { type = "freeze", index = bestUnbanked,
                          spellId = cards[bestUnbanked].spellId },
                        { type = "take", index = gIndex,
                          spellId = cards[gIndex].spellId },
                    },
                    annotations = annotations,
                    deltas = deltas,
                }
            end

            local why
            if (tonumber(charges.freeze) or 0) <= 0 then
                why = "Freeze unavailable"
            elseif charges.trustworthy ~= true then
                why = "Freeze count untrusted"
            else
                why = "Freeze unavailable or refused on this board"
            end
            return TakeAction(cards, annotations, deltas, bestUnbanked,
                why .. ": taking wanted side Echo to prevent its loss")
        end

        return TakeAction(cards, annotations, deltas, gIndex,
            "Drain guaranteed queue")
    end

    -- Phase B: consume the bank first, then any other wanted offer.
    local bestFrozen, bestWanted = nil, nil
    local protectedWanted = false
    for i = 1, n do
        if wanted[i] then
            if cards[i].justFrozen then
                protectedWanted = true
            elseif cards[i].isFrozen or cards[i].isCarried then
                if BetterWanted(
                    Model, cards, deltas, plan, ownedSafe, catalog,
                    i, bestFrozen) then
                    bestFrozen = i
                end
            elseif BetterWanted(
                Model, cards, deltas, plan, ownedSafe, catalog,
                i, bestWanted) then
                bestWanted = i
            end
        end
    end
    if bestFrozen then
        return TakeAction(cards, annotations, deltas, bestFrozen,
            "Take frozen wanted Echo before searching")
    end
    if bestWanted then
        return TakeAction(cards, annotations, deltas, bestWanted,
            "Take wanted Echo")
    end

    local refused = type(state.searchRefused) == "table"
        and state.searchRefused or {}
    if not protectedWanted and state.allowBanish ~= false
        and not refused.banish
        and (tonumber(charges.banish) or 0) > 0
        and charges.trustworthy == true
        and not charges.banishSpentThisPush then
        local worst = SafeBanishCandidate(cards, deltas, plan, gIndex)
        if worst then
            local action = {
                type = "banish", index = worst, spellId = cards[worst].spellId,
                reason = "No wanted Echo: banish worst safe off-wishlist card",
                annotations = annotations, deltas = deltas,
            }
            return finalSelection and Endgame(action) or action
        end
    end

    if not protectedWanted and not refused.reroll
        and (tonumber(charges.reroll) or 0) > 0
        and charges.trustworthy == true then
        local action = {
            type = "reroll",
            reason = "No wanted Echo or useful safe Banish: reroll",
            annotations = annotations,
            deltas = deltas,
        }
        return finalSelection and Endgame(action) or action
    end

    local anyNonDuplicate, anySelectable = false, false
    for i = 1, n do
        if annotations[i] ~= "duplicate" then anyNonDuplicate = true end
        if not cards[i].justFrozen then anySelectable = true end
    end
    local convergencePick = nil
    for i = 1, n do
        local eligible = ((not anyNonDuplicate)
                or annotations[i] ~= "duplicate")
            and ((not anySelectable) or not cards[i].justFrozen)
        if eligible and (convergencePick == nil
            or deltas[i] > deltas[convergencePick]
            or (deltas[i] == deltas[convergencePick]
                and annotations[convergencePick] == "filler"
                and annotations[i] ~= "filler")
            or (deltas[i] == deltas[convergencePick]
                and (annotations[i] == "filler")
                    == (annotations[convergencePick] == "filler")
                and (tonumber(cards[i].quality) or 0)
                    < (tonumber(cards[convergencePick].quality) or 0))
            or (deltas[i] == deltas[convergencePick]
                and (tonumber(cards[i].quality) or 0)
                    == (tonumber(cards[convergencePick].quality) or 0)
                and i < convergencePick)) then
            convergencePick = i
        end
    end
    convergencePick = convergencePick or 1
    local convergenceAction = TakeAction(
        cards, annotations, deltas, convergencePick,
        annotations[convergencePick] == "duplicate"
            and "Forced take: every selectable Echo is already owned"
            or "Forced least-harmful selection")
    -- Every executable search path has already returned. This selection is
    -- mandatory, so preserve that fact for the save gate's pollution model.
    convergenceAction.forced = true
    return finalSelection and Endgame(convergenceAction) or convergenceAction
end

--[[ Legacy 1.19.3 heuristic retained as design history. The convergence
decision above is exhaustive for every well-formed board and replaces it.
    -- Presumptive take: best effective value among selectable cards
    -- (justFrozen excluded -- the client refuses same-board select of a
    -- just-frozen card). Ties go to the guaranteed head (one-shot).
    local takeIdx, takeEff = nil, NEG_INF
    for i = 1, n do
        if not cards[i].justFrozen then
            if eff[i] > takeEff
                or (eff[i] == takeEff and i == gIndex) then
                takeIdx, takeEff = i, eff[i]
            end
        end
    end
    if gIndex and gWanted and not cards[gIndex].justFrozen
        and eff[gIndex] >= takeEff then
        takeIdx, takeEff = gIndex, eff[gIndex]
    end

    -- A free-slot wished Echo does not need Freeze when the predicted
    -- guarantee queue already supplies every remaining copy of that exact
    -- spell variant.  Stacking targets still bank when the build needs more
    -- copies than the queue will provide (for example: need 2, one guaranteed).
    local function NeedsProtectionBeyondGuarantees(card)
        if type(card) ~= "table" or card.family == nil then return true end
        local target = type(plan.targets) == "table" and plan.targets[card.family] or nil
        local targetStacks = (type(target) == "table" and tonumber(target.targetStacks)) or 1
        if targetStacks < 1 then targetStacks = 1 end

        -- The active Saved Build is the server guarantee contract. Count the
        -- exact saved spell variant, including stack counts, rather than only
        -- the broad family. This now applies to Double Strike, Quick Hands,
        -- and quality-bearing stat Echoes alike.
        local snapshotExact = SnapshotExact(card.spellId)
        local ownedExact = OwnedExact(card.spellId)

        -- The server guarantees a FLOOR equal to the active Saved Build.
        -- It is not additive: taking a free-slot copy early consumes one unit
        -- of that floor. Therefore a wishlist target ABOVE the saved baseline
        -- always has an extra copy to protect, even while the baseline appears
        -- in the predicted guarantee queue. Live Test 5 proved that subtracting
        -- the pending baseline suppresses the only freeze opportunity.
        if snapshotExact > 0 then
            if targetStacks <= snapshotExact then return false end
            return ownedExact < targetStacks
        end

        -- No active Saved Build coverage for this exact variant: preserve the
        -- wishlist-only/first-run behavior and allow an exact predicted queue
        -- entry to cover the remaining need.
        local uncovered = targetStacks - ownedExact
        if uncovered <= 0 then return false end
        local guaranteedExact = 0
        local entries = state.queue and state.queue.entries or nil
        if type(entries) == "table" then
            for qi = 1, #entries do
                local qe = entries[qi]
                if type(qe) == "table"
                    and tonumber(qe.spellId) == tonumber(card.spellId) then
                    guaranteedExact = guaranteedExact + 1
                end
            end
        end
        return uncovered > guaranteedExact
    end

    -- RETRIEVE (rule D): a held/carried wanted Echo is already consuming a
    -- board slot. Take it back the moment doing so is FREE -- i.e. slot 3
    -- is not a different wanted guarantee. Checked before rule C so an
    -- existing hold is always resolved before a new one can start.
    --
    -- Deliberately does NOT sacrifice a different wanted guarantee to
    -- retrieve early. Earlier version of this rule did, on the reasoning
    -- that holding costs the held family its own guarantee -- but rule C
    -- only ever freezes a family whose guarantee is ALREADY exhausted
    -- (pendingFam false), so by the time something is actually held there
    -- is no self-block risk left to race against; holding it one more
    -- board costs that family nothing. Confirmed live 2026-08-01 (run 2):
    -- retrieving a held Ferocious Bond (already past its 4-copy Saved
    -- Build baseline, chasing extras toward an 8-copy wishlist target)
    -- cost a guaranteed Ember Spark -- a distinct single-copy family at
    -- its only guaranteed appearance all run, permanently forfeited via
    -- the Absolute one-shot rule below (a guaranteed copy not selected is
    -- gone, not deferred). Sacrificing a different wanted guarantee is
    -- only a good trade when the alternative is a proven ongoing cost;
    -- post rule-C that's never true for anything this rule can see, so it
    -- doesn't pay for speed nothing needs.
    --
    -- Also deliberately NOT value-weighted (comparing held-echo delta
    -- against the guaranteed echo's delta before deciding whether to
    -- sacrifice it) -- a stacking family and a single-copy family are not
    -- symmetric risks even at equal delta. A stacking echo can only ever
    -- be advanced in order (copy 5 requires 1-4 already in hand), but
    -- once it's held with its OWN guarantee already closed, one more
    -- board of holding costs it literally nothing -- the next copy in
    -- that sequence isn't going anywhere. A single-copy echo's one
    -- guaranteed appearance has no known recovery schedule if skipped --
    -- it might come back next board, next run, or not for a long time.
    -- So the side that looks more "urgent" (deep in a long stack) is
    -- actually the safe one to make wait, and the side that looks more
    -- "replaceable" (just 1 copy) is the one actually at risk. Never
    -- trade a bird in hand (a live wanted guarantee) for a held echo that
    -- isn't going anywhere.
    if not (gIndex and gWanted) then
        local heldIdx, heldDelta = nil, NEG_INF
        for i = 1, n do
            local c = cards[i]
            local frozenish = c.isFrozen or c.isCarried
            if frozenish and not c.justFrozen
                and (tonumber(deltas[i]) or 0) > 0
                and Wished(plan, c.family) then
                local d = tonumber(deltas[i]) or 0
                if d > heldDelta then
                    heldIdx, heldDelta = i, d
                end
            end
        end
        if heldIdx then
            return { type = "take", spellId = cards[heldIdx].spellId, index = heldIdx,
                reason = "retrieve held wanted echo (its guarantee is already exhausted while frozen)",
                annotations = annotations, deltas = deltas }
        end
    end

    -- BANK (rule C): freeze a free-slot card that is either (a) a copy of
    -- a wished stacking family below its uncovered target or (b) a PRECIOUS
    -- quality catch not already covered by the exact active Saved Build
    -- snapshot. Fires whenever the card isn't this board's own pick.
    -- Runs BEFORE the tight-horizon check below: a precious catch that
    -- isn't yet in the predicted queue (e.g. a family just added to the
    -- wishlist this session) gets no other protection, and tight horizon
    -- would otherwise take the guaranteed and let it slip -- live
    -- 2026-07-24, a blue Strength Training lost to a tight-horizon
    -- guaranteed until manually frozen instead. Freeze doesn't consume
    -- the board: Main fires the freeze, marks the board, and this
    -- function runs again with canFreeze=false to place the take (the
    -- guaranteed, tight horizon or not, is still taken on that next
    -- tick). One per board; never a card already frozen/carried; never
    -- when a copy of the same family is already banked on this board.
    if (charges.freeze or 0) > 0 and charges.trustworthy ~= false
        and state.canFreeze ~= false then
        local function FindBankable(wantStack)
            for i = 1, n do
                local c = cards[i]
                local isStack = deltas[i] > 0
                    and type(Model.StackWishBelowTarget) == "function"
                    and Model.StackWishBelowTarget(plan, ownedSafe, c.family)
                -- Freeze only to preserve one wanted side Echo while taking a
                -- DIFFERENT wanted guarantee, and only when the wishlist target
                -- exceeds exact Saved Build coverage. Baseline-only side offers
                -- such as Lightning Charged 1/1 must be left for their later
                -- guarantee rather than wasting a freeze charge.
                --
                -- Stacking pass only: never freeze while this family's own
                -- guarantee is still open (pendingFam). Confirmed live: a
                -- frozen copy blocks the server from ever guaranteeing
                -- another copy of the SAME family, so freezing here would
                -- silence the exact channel meant to deliver the remaining
                -- copies (rule C in the header). The precious-catch pass
                -- (wantStack=false) is unaffected -- that guarantee is
                -- already known to serve the wrong quality tier.
                local guaranteeStillOpen = wantStack and isStack
                    and pendingFam[c.family] == true
                local protectBeforeGuaranteed = gIndex and gWanted
                    and i ~= gIndex and deltas[i] > 0 and Wished(plan, c.family)
                    and NeedsProtectionBeyondGuarantees(c)
                    and not guaranteeStillOpen
                local bankable = protectBeforeGuaranteed and
                    ((wantStack and isStack)
                    or (not wantStack and deltas[i] > 0 and not isStack))
                if i ~= gIndex and bankable
                    and not (c.isFrozen or c.isCarried or c.justFrozen) then
                    local famAlreadyBanked = false
                    for j = 1, n do
                        local o = cards[j]
                        if j ~= i and o.family == c.family
                            and (o.isFrozen or o.isCarried or o.justFrozen) then
                            famAlreadyBanked = true
                        end
                    end
                    if not famAlreadyBanked then return i end
                end
            end
            return nil
        end
        -- Pass 1: a stacking-family copy (Double Strike, needing many
        -- more) always wins the single freeze over a precious catch.
        -- Pass 2: no stack candidate -- bank the precious catch instead.
        local bankIdx = FindBankable(true) or FindBankable(false)
        if bankIdx then
            local isStack = type(Model.StackWishBelowTarget) == "function"
                and Model.StackWishBelowTarget(plan, ownedSafe, cards[bankIdx].family)
            local followIdx = gIndex and gWanted and gIndex or takeIdx
            local steps = {
                { type = "freeze", index = bankIdx, spellId = cards[bankIdx].spellId },
            }
            if followIdx and followIdx ~= bankIdx then
                steps[#steps + 1] = {
                    type = "take", index = followIdx, spellId = cards[followIdx].spellId,
                }
            end
            return { type = "freeze", index = bankIdx,
                spellId = cards[bankIdx].spellId,
                reason = (SnapshotExact(cards[bankIdx].spellId) > 0
                        and "freeze wanted side / preserve wanted guarantee")
                    or (isStack and "freeze wanted stack / preserve wanted guarantee"
                        or "freeze wanted side / preserve wanted guarantee"),
                steps = steps,
                annotations = annotations, deltas = deltas }
        end
    end

    -- Absolute one-shot rule: when slot 3 is a saved/guaranteed Echo that
    -- the wishlist still wants, take it before every other selectable
    -- Echo -- including a held/frozen wanted Echo (rule D deliberately
    -- does not run when this condition holds; see rule D's header note).
    -- A wanted free-slot Echo is protected by the freeze block above when
    -- a charge is available; otherwise it is sacrificed. The guaranteed
    -- copy cannot wait and is permanently lost when another slot is
    -- selected.
    if gIndex and gWanted and not cards[gIndex].justFrozen then
        return { type = "take", spellId = cards[gIndex].spellId, index = gIndex,
            reason = "take wanted guaranteed echo",
            annotations = annotations, deltas = deltas }
    end

    -- BRACKET FISHING: when slot 3 is an unwanted guaranteed/fixed filler,
    -- sample the two free slots while this level bracket still has its own
    -- eligible pool. Test 12 proved this must be budgeted: an unconditional
    -- return burned 17 rerolls against one level-35 guarantee. Main supplies
    -- cross-board counters; once any limit is reached we simply fall through
    -- to the normal wanted/banish/EV/least-harmful cascade below.
    if gIndex and not gWanted
        and (charges.reroll or 0) > 0
        and charges.trustworthy ~= false
        and not bankedWantedOnBoard
        and flags.REROLL_HOLDS_GUARANTEED ~= false then
        local actionableFree = false
        for i = 1, n do
            if i ~= gIndex and not cards[i].justFrozen then
                local d = tonumber(deltas[i]) or 0
                local a = annotations[i]
                -- Genuine progress must be selected or frozen, never rerolled
                -- away. "returns later" and zero-value duplicates are safe to
                -- redraw because they do not increase the final wishlist count.
                if d > 0 and a ~= "returns later" then
                    actionableFree = true
                    break
                end
            end
        end
        if not actionableFree then
            local budget = type(state.rerollBudget) == "table"
                and state.rerollBudget or {}
            local consecutive = tonumber(budget.consecutive) or 0
            local consecutiveLimit = tonumber(budget.consecutiveLimit) or 3
            local bracketSpent = tonumber(budget.bracketSpent) or 0
            local bracketLimit = tonumber(budget.bracketLimit) or 4
            local reserve = tonumber(budget.reserve) or 0
            local remaining = tonumber(charges.reroll) or 0
            if consecutive < consecutiveLimit
                and bracketSpent < bracketLimit
                and remaining > reserve then
                return { type = "reroll",
                    reason = "bracket fishing: reroll filler guarantee",
                    annotations = annotations, deltas = deltas }
            end
        end
    end

    -- Tight regime: pending wanted guarantees fill the whole horizon;
    -- never divert a pick from the queue. Unknown horizon = abundant.
    local horizon = tonumber(state.horizon)
    if horizon and gIndex and gWanted then
        local wantedInQueue = 0
        local entries = state.queue and state.queue.entries or nil
        if type(entries) == "table" then
            for i = 1, #entries do
                local e = entries[i]
                if type(e) == "table" and e.wanted then
                    wantedInQueue = wantedInQueue + 1
                end
            end
        end
        if wantedInQueue >= horizon then
            return { type = "take", spellId = cards[gIndex].spellId, index = gIndex,
                reason = "tight horizon: take guaranteed",
                annotations = annotations, deltas = deltas }
        end
    end

    -- Reroll EV test, shared by two call sites: (1) before settling for a
    -- board whose best option is merely DEFERRED (a deferred card returns
    -- guaranteed by definition, so rerolling it away loses nothing), and
    -- (2) the classic junk-board chain. Conservative on missing params.
    -- Charge scarcity (live 2026-07-24, board with Banish 0): the cost
    -- escalates as remaining rerolls thin -- an abundant reroll is cheap,
    -- the last few are precious and reserved for genuinely junk boards.
    local function TryReroll(bestCurrent, reason, deferredOnly)
        local remaining = tonumber(charges.reroll) or 0
        if remaining <= 0 or charges.trustworthy == false
            or bankedWantedOnBoard then
            return nil
        end
        -- Dodging a POSITIVE deferred pick is a luxury: only with a
        -- comfortable reserve. Junk boards may spend down to the last.
        if deferredOnly
            and remaining < (tonumber(params.deferRerollFloor) or 4) then
            return nil
        end
        local holdOk = (gIndex == nil)
            or (flags.REROLL_HOLDS_GUARANTEED == true)
            or ((gDelta or NEG_INF) < (tonumber(params.rerollHoldThreshold) or NEG_INF))
        if not holdOk then return nil end
        if type(Model.FreeDist) ~= "function"
            or type(Model.EmaxGivenK) ~= "function" then
            return nil
        end
        local dist = Model.FreeDist(state.support)
        local cost = tonumber(params.rerollCost)
        if not (dist and cost) then return nil end
        local pacing = (tonumber(params.rerollPacingBase) or 6) / remaining
        -- Early levels have a smaller eligible Echo pool, so rerolls can be
        -- especially valuable for finding stack targets such as Quick Hands.
        -- Conserve more aggressively through the middle, then spend freely at
        -- levels 78-80 where unused charges have no future value.
        --
        -- The very earliest levels (roughly 1-10) are a different regime,
        -- not just "smaller" -- confirmed live 2026-08-01: 3 general
        -- rerolls plus bracket-fishing burned across ~8 boards at level
        -- 7-8, nearly all landing on off-wishlist filler or low-quality
        -- catches, because most of a large wishlist simply isn't
        -- level-eligible yet this early. The thin, mostly-ineligible pool
        -- makes "best of 2 draws" look deceptively good on paper (the few
        -- eligible wished rows dominate the estimate) while actually
        -- landing one is high-variance -- so the 0.70 discount below,
        -- which makes rerolling CHEAPER, was making this worse exactly
        -- when the pool is thinnest. Raise the bar instead for this
        -- narrow band; the normal mid-game discount resumes right after.
        if level and level <= 10 then
            pacing = pacing * 1.6
        elseif level and level <= 25 then
            pacing = pacing * 0.70
        end
        if level and level >= 78 then pacing = pacing * 0.35 end
        if pacing < 0.35 then pacing = 0.35 end
        if Model.EmaxGivenK(dist, bestCurrent, 2) - cost * pacing > bestCurrent then
            return { type = "reroll", reason = reason,
                annotations = annotations, deltas = deltas }
        end
        return nil
    end

    -- Take the best free/banked card when it strictly beats the
    -- guaranteed head's value (deferred cards compete at their
    -- discounted value, so a pending-guarantee catch no longer diverts
    -- the pick from a one-shot).
    local gBar = (gIndex and eff[gIndex]) or NEG_INF
    if takeIdx and takeIdx ~= gIndex and takeEff > 0 and takeEff > gBar then
        if annotations[takeIdx] == "returns later" then
            -- Nothing one-shot on this board: the pick would only be a
            -- deferred card. Taking it now costs nothing (it's not a
            -- scarce resource), so a reroll only makes sense if it beats
            -- the card's TRUE value -- not its discounted take-comparison
            -- value (that discount exists only so a genuine one-shot can
            -- outrank a deferred pick above; reusing it here made reroll
            -- clear an artificially low bar and fire on boards that were
            -- already fine -- live 2026-07-24, five repeated L64 boards).
            local rr = TryReroll(deltas[takeIdx], "Rerolling — only deferred echoes on board", true)
            if rr then return rr end
        end
        return { type = "take", spellId = cards[takeIdx].spellId, index = takeIdx,
            reason = (annotations[takeIdx] == "banked") and "Taking held stack copy"
                or "Taking best available echo",
            annotations = annotations, deltas = deltas }
    end

    -- Else the guaranteed head, when present and wanted (at quality --
    -- the gate already zeroed the wrong-quality case out of gWanted).
    if gIndex and gWanted then
        return { type = "take", spellId = cards[gIndex].spellId, index = gIndex,
            reason = "take guaranteed",
            annotations = annotations, deltas = deltas }
    end

    -- Junk-board chain: banish, else reroll, else least-harmful take.

    -- Banish only on a genuinely junk board (no selectable card with a
    -- positive effective value): the redraw of the removed worst card is
    -- the improvement. Never a guaranteed/frozen/carried/justFrozen
    -- target, and NEVER a wished family regardless of its quality-gate
    -- status -- confirmed live 2026-07-24: banishing removes the entire
    -- family from the draw pool, including quality variants that haven't
    -- even appeared yet. A gray Strength Training scores worse than
    -- filler (qualityMiss < filler) but banishing it would permanently
    -- forfeit the blue variant for the run. Only a genuinely off-wishlist
    -- card is ever a safe banish target.
    local allFreeJunk = true
    for i = 1, n do
        if i ~= gIndex and eff[i] > 0 then allFreeJunk = false end
    end
    if allFreeJunk and (charges.banish or 0) > 0
        and not charges.banishSpentThisPush
        and charges.trustworthy ~= false then
        local worst, worstDelta = nil, 0
        for i = 1, n do
            local c = cards[i]
            if i ~= gIndex
                and not (c.isGuaranteed or c.isFrozen or c.isCarried or c.justFrozen)
                and not Wished(plan, c.family)
                and deltas[i] < worstDelta then
                worst, worstDelta = i, deltas[i]
            end
        end
        if worst then
            return { type = "banish", index = worst, spellId = cards[worst].spellId,
                reason = "junk board: banish worst",
                annotations = annotations, deltas = deltas }
        end
    end

    -- Least-harmful mandatory pick, worked out now (before the reroll
    -- decision below) so a forced wrong-quality take can be weighed against
    -- spending a reroll instead of silently happening. Structurally NEVER
    -- take a duplicate while any non-duplicate card exists (a new distinct
    -- echo, even filler, at least advances an Adaptive-Power-style distinct
    -- count), and never a justFrozen card while any other exists (the
    -- client refuses it this board).
    --
    -- Persistence safety matters when every option is already owned. The
    -- final run is autosaved and becomes the next run's exact guarantee
    -- baseline. A new lower-quality sibling of a wished family is therefore
    -- much worse than an exact wished spell already in the Saved Build: it
    -- pollutes the next baseline and is served immediately at low level.
    -- Test 5 confirmed this with Common Agility Boost. Rank mandatory picks
    -- by projected saved-build damage before ordinary quality/index ties.
    local anyNonDup, anySelectable = false, false
    for i = 1, n do
        if annotations[i] ~= "duplicate" then anyNonDup = true end
        if not cards[i].justFrozen then anySelectable = true end
    end
    local function WishlistExactTarget(spellId)
        local cardFam = type(catalog) == "table" and type(catalog.familyOf) == "table"
            and catalog.familyOf[spellId] or nil
        local target = type(plan.targets) == "table" and plan.targets[cardFam] or nil
        if type(target) ~= "table" then return 0 end
        local tiers = target.qualityTiers
        local total = 0
        if type(tiers) == "table" then
            for ti = 1, #tiers do
                local tier = tiers[ti]
                if type(tier) == "table" and tonumber(tier.spellId) == tonumber(spellId) then
                    total = total + math.max(1, tonumber(tier.n) or 1)
                end
            end
        elseif tonumber(target.spellId) == tonumber(spellId) then
            total = math.max(1, tonumber(target.targetStacks) or 1)
        end
        return total
    end

    local function PersistenceRisk(card)
        if type(card) ~= "table" then return 99 end
        local spellId, fam = card.spellId, card.family
        local exactWish = WishlistExactTarget(spellId)
        if exactWish > 0 then
            -- Re-taking an exact wishlist spell does not introduce a new
            -- quality variant into the next Saved Build.
            return 0
        end
        if not Wished(plan, fam) then
            -- A truly off-wishlist filler is disposable and does not masquerade
            -- as progress toward a wished family.
            return 1
        end
        local wishedQ = Model.EffectiveWishedQuality
            and Model.EffectiveWishedQuality(plan, catalog, fam) or WishedQuality(plan, fam)
        if (tonumber(card.quality) or 0) < (tonumber(wishedQ) or 0) then
            -- Worst case: wrong-quality sibling becomes an exact guaranteed
            -- baseline entry next run.
            return 4
        end
        -- Same-family but not the exact requested spell/quality still pollutes
        -- exact convergence, though less severely than a lower tier.
        return 3
    end

    local pick = nil
    for i = 1, n do
        local eligible = ((not anyNonDup) or (annotations[i] ~= "duplicate"))
            and ((not anySelectable) or (not cards[i].justFrozen))
        if eligible then
            if pick == nil then
                pick = i
            else
                local better = false
                if eff[i] > eff[pick] then
                    better = true
                elseif eff[i] == eff[pick] then
                    local ir, pr = PersistenceRisk(cards[i]), PersistenceRisk(cards[pick])
                    if ir < pr then
                        better = true
                    elseif ir == pr then
                        local iFiller = annotations[i] == "filler"
                        local pFiller = annotations[pick] == "filler"
                        if pFiller and not iFiller then
                            better = true
                        elseif iFiller == pFiller
                            and (cards[i].quality or 0) > (cards[pick].quality or 0) then
                            -- Once persistence risk is equal, prefer the higher
                            -- quality card; the old lower-quality tie-break is
                            -- what selected Common Agility Boost.
                            better = true
                        end
                    end
                end
                if better then pick = i end
            end
        end
    end
    pick = pick or 1
    local pickRisk = PersistenceRisk(cards[pick])

    -- Reroll on a junk board (same shared gate as above) -- EXCEPT at
    -- level 80: there's no future board within this run left to conserve
    -- a reroll charge for, so per the "this can only ever be neutral or
    -- better" logic, spend one unconditionally rather than force a
    -- worthless duplicate/filler take.
    do
        local bestCurrent = NEG_INF
        for i = 1, n do
            if eff[i] > bestCurrent then bestCurrent = eff[i] end
        end
        if level and level >= 78 and bestCurrent <= 0
            and (charges.reroll or 0) > 0 and charges.trustworthy ~= false
            and not bankedWantedOnBoard then
            return { type = "reroll", reason = "late run: spend reroll before forced filler",
                annotations = annotations, deltas = deltas }
        end
        -- Secure duplicates correctly: a forced take that would poison the
        -- next Saved Build with a below-wished-quality sibling (PersistenceRisk
        -- 4 -- the worst case, distinct from an ordinary disposable off-
        -- wishlist duplicate at risk 1) directly costs the save gate
        -- (Ratchet.Dominates' wrongQForced weighting) -- live 2026-08-01,
        -- two forced Open Wounds/Rend the Weak wrong-quality picks with 2
        -- reroll charges sitting unspent tipped an otherwise-tied run into
        -- BLOCKED. That downside is worse than the generic junk-board EV/
        -- pacing gate below accounts for, so it earns its own unconditional
        -- reroll rather than waiting on the pacing math to agree.
        if pickRisk >= 4 and (charges.reroll or 0) > 0
            and charges.trustworthy ~= false and not bankedWantedOnBoard then
            return { type = "reroll", reason = "avoiding forced wrong-quality duplicate",
                annotations = annotations, deltas = deltas }
        end
        local rr = TryReroll(bestCurrent, "Rerolling — redraw expected to improve board")
        if rr then return rr end
    end

    return { type = "take", spellId = cards[pick].spellId, index = pick,
        reason = (annotations[pick] == "duplicate") and "Forced take — all echoes already owned"
            or "Taking filler — will be replaced in a later run",
        -- This is the ONLY branch reached with zero legal alternatives (every
        -- other take/freeze/banish/reroll path above returned first). The
        -- save gate (Ratchet.Dominates) uses this to weigh unavoidable
        -- pollution far more lightly than a voluntary one -- Test 13/14's
        -- Stonefist Barrage refusal was exactly this take rejected outright.
        forced = true,
        annotations = annotations, deltas = deltas }
end
--]]
