-- Nexus: passive Orb guidance for the main HUD.
--
-- Presentation only. Observe() collects observations that the adapter and the
-- Orb runtime already own (no Orb catalog read, no preparation, no new
-- polling); Project() turns them into what the HUD may SAY and whether it
-- offers the passive "Open Orbs..." button. Nothing here starts, resumes,
-- approves, spends, selects or changes any setting, and nothing here is read
-- by a decision.
--
-- Precedence (first match wins; every present blocker stays in `blockers`):
--   1. no assigned Wishlist           -> name the limitation, no Orb advice
--   2. unresolved/owned Orb run       -> its recovery reason, Open Orbs (inspect)
--   3. Orb state blocks ordinary      -> paused reason, Open Orbs (inspect)
--   4. a submitted action unconfirmed -> waiting for confirmation
--   5. an Echo choice is open         -> it is open in the game window
--   6. rolled targets done, locks left-> Orbs do not fill locked slots
--   7. normal rolls finished (server count 0), rolled targets missing
--                                     -> review Orbs, Open Orbs
--   8. normal-roll count unknown      -> say it is not confirmed
-- A level alone never means finished; an empty pending list is not proof that
-- nothing is pending; a visible board alone is not "unanswered" when a
-- submitted action or an Orb uncertainty exists (those rank first).
Nexus = Nexus or {}
local G = {}
Nexus.OrbGuidance = G

local function Text(value)
    local user = Nexus.UserText
    if user and type(user.Message) == "function" then
        local ok, text = pcall(user.Message, value)
        if ok and type(text) == "string" then return text end
    end
    return tostring(value or "")
end

-- obs fields (all optional; absent means unknown):
--   plan         true when an assigned Wishlist resolved
--   orbBlock     the Orb runtime's block reason (unresolved or owned Orb run)
--   ordinaryAllowed, ordinaryWhy   the adapter's Orb-state gate
--   intent       "submitted" / "uncertain" when an action awaits its result
--   inFlight     true when the adapter holds an unconfirmed action or latch
--   board        true when an Echo choice is shown by the game
--   horizon      the server's pending normal-roll count, nil when unknown
--   rolledMissing, lockMissing   remaining target copies (nil when unknown)
function G.Project(obs)
    obs = type(obs) == "table" and obs or {}
    local blockers = {}
    local function Add(kind, text) blockers[#blockers + 1] = {kind = kind, text = text} end
    if obs.orbBlock then Add("orb-run", obs.orbBlock) end
    if obs.ordinaryAllowed == false then
        Add("orb-state", Text(obs.ordinaryWhy or "Orb state active or unknown"))
    end
    if obs.intent == "submitted" or obs.intent == "uncertain" then
        Add("submitted", "The last Echo action has no confirmed result yet.")
    end
    if obs.inFlight then
        Add("in-flight", "The game has not confirmed an Echo action yet.")
    end
    if obs.board then Add("choice", "An Echo choice is open in the game window.") end

    local function Out(state, text, openOrbs)
        return {state = state, text = text, openOrbs = openOrbs == true, blockers = blockers}
    end
    if not obs.plan then
        return Out("no-plan", "No assigned Wishlist: Orb guidance needs one.", false)
    end
    if obs.orbBlock then return Out("orb-run", obs.orbBlock, true) end
    if obs.ordinaryAllowed == false then
        return Out("orb-state", Text(obs.ordinaryWhy or "Orb state active or unknown")
            .. ". Open Orbs to inspect it.", true)
    end
    if obs.intent == "submitted" or obs.intent == "uncertain" or obs.inFlight then
        return Out("waiting", "Waiting for the game to confirm the last Echo action.", false)
    end
    if obs.board then
        return Out("choice", "An Echo choice is open in the game window.", false)
    end
    local rolled, locks = tonumber(obs.rolledMissing), tonumber(obs.lockMissing)
    if rolled == 0 and locks and locks > 0 then
        return Out("locks-only", "Rolled targets are complete. Orbs do not fill locked slots.", false)
    end
    local horizon = tonumber(obs.horizon)
    if horizon == 0 then
        if rolled and rolled > 0 then
            return Out("finished", "Normal rolls finished. Review Orbs for remaining rolled targets.", true)
        end
        if rolled == nil then
            return Out("finished-unknown", "Normal rolls finished. Target progress is not available.", false)
        end
        return Out("complete", nil, false)
    end
    if horizon == nil then
        return Out("unknown", "The game has not reported whether normal rolls remain.", false)
    end
    return Out("rolling", nil, false)
end

-- Observations from the owners that already hold them. `intent` comes from
-- the automation runtime's own record; `progress` is the HUD progress model.
function G.Observe(progress, intent, plan)
    local A = Nexus.GameAdapter
    local obs = {plan = plan and true or false, intent = intent}
    if A then
        if type(A.OrbBlockReason) == "function" then
            local ok, why = pcall(A.OrbBlockReason, "Ordinary rolling")
            if ok and type(why) == "string" and why ~= "" then obs.orbBlock = why end
        end
        if type(A.OrdinaryBoardAllowed) == "function" then
            local ok, allowed, why = pcall(A.OrdinaryBoardAllowed)
            if ok then obs.ordinaryAllowed = allowed == true;obs.ordinaryWhy = why end
        end
        if type(A.InFlight) == "function" then
            local ok, v = pcall(A.InFlight);obs.inFlight = ok and v == true
        end
        if type(A.Board) == "function" then
            local ok, board = pcall(A.Board);obs.board = ok and type(board) == "table"
        end
        if type(A.Horizon) == "function" then
            local ok, n = pcall(A.Horizon);if ok then obs.horizon = n end
        end
    end
    if type(progress) == "table" then
        local total, owned = tonumber(progress.total), tonumber(progress.owned)
        if total and owned then obs.rolledMissing = math.max(0, total - owned) end
        obs.lockMissing = type(progress.toLock) == "table" and #progress.toLock or 0
    end
    return obs
end

return G
