-- Nexus: logic/Policy.lua
-- Ordinary-board decision entry. No WoW API calls; plain Lua 5.1.
--
-- Current contract (CONTRACTS.md, "Current rolling and Orb contract"): there
-- are no guaranteed future Echo rolls, and every ordinary board goes to the
-- one planner that holds no future-offer assumption, EchoWeaver.DecideNexus.
-- The quality-and-guarantee-aware greedy scoring that this file carried from
-- v1.19 (rules A-D: quality gate, defer, bank, retrieve, and the convergence
-- selection) was reachable only when EchoWeaver was not loaded, which the
-- production TOC never allows. It was removed as unreachable; its text is in
-- the repository history and its rules in the historical section of
-- CONTRACTS.md. The free-slot support and draw-distribution helpers that fed
-- it are kept for the policy adapter in
-- tests/prototype/historical_model_support.lua.

Nexus = Nexus or {}
local Policy = {}
Nexus.Policy = Policy

-- state = { board, owned, charges, plan, level, horizon, params, canFreeze,
--           rerollBudget, ordinaryBoardAllowed, allow* permissions, ... }
-- Returns { type = "take"|"freeze"|"reroll"|"banish"|"wait", spellId=?,
--   index=?, reason = s, annotations = { [cardIndex] = s },
--   deltas = { [cardIndex] = n } }
-- Pure: same input, same output; malformed input degrades to "wait".
function Policy.Decide(state)
    if type(state) == "table" and state.ordinaryBoardAllowed == false then
        return {type="wait", reason="Orb state active or unknown", annotations={}, deltas={}}
    end
    -- Saved verification is identity, contents and ownership evidence; it
    -- selects no planner. `snapshotVerified`, `queue` and `flags` are
    -- deliberately not read here.
    if type(state) == "table" and Nexus.EchoWeaver then
        return Nexus.EchoWeaver.DecideNexus(state)
    end
    return {type="wait", reason=type(state) == "table" and "ordinary planner unavailable"
        or "no board", annotations={}, deltas={}}
end

-- Optional "Auto-pick while leveling" (settings.autoPickLeveling): with no
-- Wishlist assigned, take the highest observed rarity on an ordinary board at
-- live levels 2 to 79, the first card in current offer order on a tie. Pure.
-- It reads only the adapter's observed rarity (card.observedQuality: an exact
-- integer 0..4, nil otherwise). Any card without a valid Echo id or rarity, or
-- one Echo offered at two rarities, refuses the WHOLE board: an unknown rarity
-- never becomes Common and never wins or loses a tie. No future offer, draw,
-- resource or Wishlist value is read. The caller owns the authority (exact
-- opt-in, master Auto, autoPick, positively known unassigned target).
Policy.LEVELING = {policyId = "leveling-rarity-1", minLevel = 2, maxLevel = 79,
    minQuality = 0, maxQuality = 4, boardSize = 3}
local function LevelingInteger(v, lo, hi)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
        and v == math.floor(v) and v >= lo and v <= hi
end
function Policy.LevelingLevel(level)
    return LevelingInteger(level, Policy.LEVELING.minLevel, Policy.LEVELING.maxLevel)
end
function Policy.DecideLevelingRarity(state)
    local L = Policy.LEVELING
    local function Wait(reason)
        return {type="wait", reason="Random Roll: " .. reason,
            annotations={}, deltas={}, planner="leveling-rarity", policyId=L.policyId}
    end
    if type(state) ~= "table" then return Wait("no board") end
    if state.ordinaryBoardAllowed ~= true then return Wait("Orb state active or unknown") end
    if state.pending or state.pendingAction then return Wait("waiting for action confirmation") end
    if not Policy.LevelingLevel(state.level) then return Wait("level is not 2 to 79") end
    if not LevelingInteger(state.horizon, 0, math.huge - 1) then
        return Wait("waiting for pending-pick count")
    end
    local board = state.board
    local cards = type(board) == "table" and board.cards or nil
    if type(cards) ~= "table" or cards[L.boardSize + 1] ~= nil then
        return Wait("waiting for three-card board")
    end
    -- R5: the adapter says the WHOLE raw choice was not a strict three-card
    -- observation (for example one invalid raw entry filtered out of four):
    -- a valid-looking projected subset is never admitted.
    if board.strictObservation == false then
        return Wait("the offer is not a clean three-card board; pick manually")
    end
    -- The adapter's later-frame settle rule (Board().revealSettling), as in
    -- EchoWeaver: wait, and the runtime decides again at the poll pace.
    if board.revealSettling == true then
        return Wait("waiting for the game's own pick window to pass")
    end
    local best, bestQ, seen = nil, nil, {}
    for i = 1, L.boardSize do
        local c = cards[i]
        if type(c) ~= "table" then return Wait("waiting for three-card board") end
        local id, q = c.spellId, c.observedQuality
        if not LevelingInteger(id, 1, math.huge - 1) then return Wait("an offer has no valid Echo id") end
        if not LevelingInteger(q, L.minQuality, L.maxQuality) then
            return Wait("the rarity of an offer is unknown; pick manually")
        end
        if seen[id] ~= nil and seen[id] ~= q then return Wait("one Echo is offered at two rarities") end
        seen[id] = q
        if bestQ == nil or q > bestQ then best, bestQ = i, q end
    end
    return {type="take", spellId=cards[best].spellId, index=best, quality=bestQ,
        reason="Random Roll: highest-rarity offer (first current offer on a tie)",
        annotations={}, deltas={}, planner="leveling-rarity", policyId=L.policyId}
end
