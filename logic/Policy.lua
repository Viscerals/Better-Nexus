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
