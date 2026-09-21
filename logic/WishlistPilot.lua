-- Nexus experimental ordinary-Wishlist planner.
-- Independent implementation of the behavior in supplied LoadoutPilot 1.3.6,
-- patch 103 (WishlistPlanner / WishlistObjective); no external runtime dependency.
-- No WoW API calls, saved-state writes, or predicted Snapshot guarantees here.
Nexus = Nexus or {}
local Pilot = { reference = "LoadoutPilot 1.3.6 / patch 103" }
Nexus.WishlistPilot = Pilot

local function Integer(value, minimum)
    return type(value) == "number" and value == math.floor(value)
        and value > -math.huge and value < math.huge and value >= (minimum or 0)
end
local function Count(value)
    return Integer(value, 0) and value or 0
end
local function Block(reason)
    return {action="BLOCKED", reasonCode=reason, strategyKind="WISHLIST_RANDOM"}
end
local function Frozen(c)
    return c.frozen == true or c.isFrozen == true or c.isCarried == true
        or c.justFrozen == true
end

-- Deliberate Nexus differences from the named reference strategy. Each one is
-- an explicit input option of Pilot.Decide. Without the option, Pilot.Decide
-- keeps the reference decision (tests/prototype/planner_reference.lua compares
-- exactly that). DecideNexus passes this table. See
-- docs/ROLLING_ORB_REVIEW_EADFF8A.md for the fixtures and the trade-offs.
Pilot.NEXUS_POLICY = {
    -- R3: a requested Echo whose exact count is already met does not stop a
    -- permitted Reroll. Only an Echo that is still needed does.
    rerollIgnoresSatisfiedTargets = true,
    -- R5: do not Freeze a copy that the next selection makes surplus: another
    -- selectable copy of the same Echo is on the board and one copy is needed.
    freezeMustStayNeeded = true,
}

-- Normalized pure policy. Its action order and tie breakers intentionally match
-- the supplied reference. Runtime-specific safety differences belong in the
-- adapter below, never in hidden re-scoring after this function returns.
function Pilot.Decide(input)
    if type(input) ~= "table" then return Block("INVALID_WISHLIST_STATE") end
    local obj, board = input.objective, input.board
    if type(obj) ~= "table" or type(obj.requestedCounts) ~= "table"
        or type(obj.outstandingCounts) ~= "table" then
        return Block("INVALID_WISHLIST_STATE")
    end
    local left = input.remainingPicks
    if not Integer(left, 0) then return Block("INVALID_WISHLIST_STATE") end
    if type(board) ~= "table" or type(board.choices) ~= "table" then
        return Block("INVALID_BOARD")
    end
    local total = obj.outstandingTotal
    if not Integer(total, 0) then
        total = 0
        for id in pairs(obj.requestedCounts) do total = total + Count(obj.outstandingCounts[id]) end
    end
    local pressure = total == 0 and "COMPLETE"
        or ((left <= 6 or total >= left) and "HIGH")
        or ((left <= 18 or total * 3 >= left) and "MEDIUM") or "LOW"
    local cap, resources = board.capabilities or {}, input.resources or board.resources or input
    local special = (board.boardType == "ORB_LOST_MEMORIES" or board.isOrb == true)
    local pending = cap.pending == true or input.pending == true or input.pendingAction ~= nil
    local canSelect = cap.canSelect ~= false
    local canBanish = cap.canBanish ~= false and not special and not pending
    local canFreeze = cap.canFreeze ~= false and not special and not pending
    local canReroll = input.commonBoardRerollEnabled == true and cap.canReroll == true
        and board.twoFrozenRerollProhibited ~= true and not special and not pending
    local legal, wanted, held, disposable = {}, {}, {}, {}
    local anyRequested, forbiddenSelectable = false, false
    local anyOutstanding = false
    local policy = type(input.policy) == "table" and input.policy or {}
    for i = 1, 3 do
        local raw = board.choices[i]
        if type(raw) ~= "table" then return Block("INVALID_BOARD") end
        local id = raw.echoID or raw.spellId
        if not Integer(id, 1) then return Block("INVALID_BOARD") end
        local index = raw.index or raw.slot or i
        if not Integer(index, 1) then index = i end
        local c = {echoID=id,index=index,quality=Integer(raw.quality,-math.huge) and raw.quality or nil,
            frozen=Frozen(raw), selectable=raw.selectable ~= false}
        c.freezeEligible = not c.frozen and raw.freezeEligible ~= false
        c.banishEligible = not c.frozen and raw.banishEligible ~= false
        c.need = Count(obj.outstandingCounts[id])
        local requested = Count(obj.requestedCounts[id]) > 0
        anyRequested = anyRequested or requested
        anyOutstanding = anyOutstanding or c.need > 0
        c.forbidden = not requested and type(obj.banlistedEchoes)=="table" and obj.banlistedEchoes[id] == true
        c.legal = c.selectable and canSelect and not c.forbidden
        if c.selectable and canSelect and c.forbidden then forbiddenSelectable = true end
        if c.legal then legal[#legal+1] = c end
        if c.legal and c.need > 0 then
            wanted[#wanted+1] = c
            if c.frozen then held[#held+1] = c end
        elseif c.banishEligible and (c.legal or c.forbidden) then
            disposable[#disposable+1] = c
        end
    end
    local function Better(a,b)
        if a.frozen ~= b.frozen then return not a.frozen end
        if a.need ~= b.need then return a.need > b.need end
        if a.quality ~= b.quality then return (a.quality or -math.huge) > (b.quality or -math.huge) end
        if a.index ~= b.index then return a.index < b.index end
        return a.echoID < b.echoID
    end
    table.sort(wanted, Better)
    table.sort(held, Better)
    table.sort(disposable, function(a,b)
        if a.forbidden ~= b.forbidden then return a.forbidden end
        if a.frozen ~= b.frozen then return not a.frozen end
        if a.index ~= b.index then return a.index < b.index end
        return a.echoID < b.echoID
    end)
    local best, frozen, trash = wanted[1], held[1], disposable[1]
    local banish = canBanish and Count(resources.banishesRemaining) > 0 and trash
    local function Result(action, c, reason)
        local result = {action=action,reasonCode=reason,strategyKind="WISHLIST_RANDOM",
            pressure=pressure,outstandingCounts=obj.outstandingCounts,outstandingTotal=total,
            remainingPicks=left,completionFeasibleByCount=total<=left,boardType=board.boardType}
        if total > left then result.completionAdvisory="INSUFFICIENT_PICKS_FOR_CURRENT_DEFICIT" end
        if c then result.echoID=c.echoID; result.index=c.index; result.slot=c.index end
        return result
    end
    if #legal == 0 then
        if not forbiddenSelectable then
            local invalid = Result("BLOCKED",nil,"INVALID_BOARD")
            invalid.pressure, invalid.completionFeasibleByCount = "INVALID", false
            invalid.completionAdvisory = "INSUFFICIENT_PICKS_FOR_CURRENT_DEFICIT"
            return invalid
        end
        if banish then return Result("BANISH",trash,"AVOID_NEVER_SELECT_ECHO") end
        return Result("BLOCKED",nil,"NEVER_SELECT_ECHO_ONLY_BOARD")
    end
    if special then
        return Result("SELECT",best or legal[1],best and "SPECIAL_BOARD_SELECT" or "SPECIAL_BOARD_FALLBACK")
    end
    if total == 0 then return Result("SELECT",legal[1],"OBJECTIVE_COMPLETE_FALLBACK") end
    -- Reference rule: any Echo of the original Wishlist on the board stops the
    -- Reroll. With the explicit R3 option, only a still-needed Echo stops it.
    local keepBoard = anyRequested
    if policy.rerollIgnoresSatisfiedTargets == true then keepBoard = anyOutstanding end
    if canReroll and Count(resources.rerollsRemaining)>0 and not keepBoard then
        return Result("REROLL",nil,anyRequested and "REROLL_NO_OUTSTANDING_ON_BOARD" or "REROLL_COMMON_UNWANTED_BOARD")
    end
    if frozen then
        if best and not best.frozen then return Result("SELECT",best,"SELECT_OUTSTANDING_WISHLIST") end
        if pressure == "HIGH" and banish then return Result("BANISH",trash,"BANISH_FOR_WISHLIST_SEARCH") end
        return Result("SELECT",frozen,"SELECT_OUTSTANDING_WISHLIST")
    end
    if best then
        -- After a Freeze of `best`, the next observation selects the next
        -- unfrozen wanted offer (wanted[2]). With the explicit R5 option, skip
        -- the Freeze when that selection is the same Echo and exhausts its need:
        -- the held copy would then be surplus and would occupy an offer slot.
        local following = wanted[2]
        local surplusAfterNext = policy.freezeMustStayNeeded == true and following ~= nil
            and following.echoID == best.echoID and best.need <= 1
        if pressure == "HIGH" and total >= 2 and left >= 2 and canFreeze and not surplusAfterNext
            and Count(resources.freezesRemaining)>0 and best.freezeEligible and banish then
            return Result("FREEZE",best,"FREEZE_OUTSTANDING_FOR_HIGH_PRESSURE_SEARCH")
        end
        return Result("SELECT",best,"SELECT_OUTSTANDING_WISHLIST")
    end
    if pressure == "MEDIUM" or pressure == "HIGH" then
        if banish then return Result("BANISH",trash,"BANISH_FOR_WISHLIST_SEARCH") end
        return Result("SELECT",legal[1],"RESOURCE_EXHAUSTED_FALLBACK")
    end
    return Result("SELECT",legal[1],"LOW_PRESSURE_FALLBACK")
end

local LABELS = {
    SELECT_OUTSTANDING_WISHLIST="Take wanted Echo (Pilot)",
    FREEZE_OUTSTANDING_FOR_HIGH_PRESSURE_SEARCH="Freeze wanted Echo before search (Pilot)",
    BANISH_FOR_WISHLIST_SEARCH="Banish to find Wishlist targets (Pilot)",
    REROLL_COMMON_UNWANTED_BOARD="Reroll: no requested Echo on board (Pilot)",
    REROLL_NO_OUTSTANDING_ON_BOARD="Reroll: no needed Echo on board (Pilot)",
    LOW_PRESSURE_FALLBACK="Take available filler (Pilot)",
    RESOURCE_EXHAUSTED_FALLBACK="Take filler; search unavailable (Pilot)",
    OBJECTIVE_COMPLETE_FALLBACK="Wishlist complete; take filler (Pilot)",
}

function Pilot.DecideNexus(state)
    local annotations, deltas = {}, {}
    local function Wait(reason) return {type="wait",reason=reason,annotations=annotations,deltas=deltas,planner="pilot103"} end
    local plan, owned, board = state.plan, state.owned, state.board
    if state.ordinaryBoardAllowed == false then return Wait("Orb state active or unknown") end
    if not plan or plan.advisorOnly then return Wait("assign a Wishlist") end
    if not owned or (owned.synced ~= true and (tonumber(state.level) or 0)>1) then return Wait("unsynced") end
    if state.pending or state.pendingAction then return Wait("waiting for action confirmation") end
    if not board or type(board.cards)~="table" or #board.cards~=3 then return Wait("waiting for three-card board") end
    if not Integer(state.horizon,0) then return Wait("waiting for pending-pick count") end
    local locked = state.locked
    -- Permanent locked ownership must be known before subtracting copies.
    if locked and locked.synced == false then return Wait("waiting for locked Echo state") end
    local requested, outstanding, total = {}, {}, 0
    for id,n in pairs(plan.requestedCounts or {}) do
        requested[id]=Count(n)
        local have = Count(owned.bySpell and owned.bySpell[id])
            + Count(locked and locked.bySpell and locked.bySpell[id])
        outstanding[id]=math.max(0,requested[id]-have)
        total=total+outstanding[id]
    end
    if next(requested)==nil then return Wait("no exact Wishlist targets") end
    local choices, frozenCount = {},0
    for i,c in ipairs(board.cards) do
        local isFrozen=Frozen(c)
        if isFrozen then frozenCount=frozenCount+1 end
        local id=tonumber(c.spellId)
        choices[i]={echoID=id,index=i,quality=c.quality,frozen=isFrozen,
            selectable=c.selectable~=false,
            -- Nexus server guards: a guaranteed occurrence cannot be banished
            -- or frozen, even though the generic policy supports such inputs.
            banishEligible=not c.isGuaranteed and c.banishEligible~=false,
            freezeEligible=not c.isGuaranteed and c.freezeEligible~=false}
        local wanted=id and (outstanding[id] or 0)>0
        annotations[i]=isFrozen and "frozen" or c.isGuaranteed and "guaranteed"
            or wanted and "wanted" or requested[id] and "target satisfied" or "filler"
        deltas[i]=wanted and (100+(tonumber(c.quality) or 0)*2) or -15
    end
    local charges,refused=state.charges or {},state.searchRefused or {}
    local trusted=charges.trustworthy==true
    local decision=Pilot.Decide({
        objective={requestedCounts=requested,outstandingCounts=outstanding,outstandingTotal=total},
        remainingPicks=state.horizon,
        board={choices=choices,twoFrozenRerollProhibited=frozenCount>=2,
            capabilities={canSelect=true,
                canBanish=trusted and state.allowBanish~=false and not refused.banish,
                canFreeze=trusted and state.canFreeze~=false and state.allowFreeze~=false,
                canReroll=trusted and state.allowReroll~=false and not refused.reroll}},
        resources={banishesRemaining=charges.banish,freezesRemaining=charges.freeze,rerollsRemaining=charges.reroll},
        commonBoardRerollEnabled=state.allowReroll~=false,
        policy=Pilot.NEXUS_POLICY})
    local kinds={SELECT="take",FREEZE="freeze",BANISH="banish",REROLL="reroll",BLOCKED="wait"}
    return {type=kinds[decision.action] or "wait",spellId=decision.echoID,index=decision.index,
        reason=LABELS[decision.reasonCode] or decision.reasonCode,reasonCode=decision.reasonCode,
        annotations=annotations,deltas=deltas,pressure=decision.pressure,
        outstanding=total,planner="pilot103"}
end
