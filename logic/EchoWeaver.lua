-- Nexus: EchoWeaver, the internally maintained ordinary-Wishlist rolling
-- engine (Take, Freeze, Banish, Reroll decisions for one board).
-- No WoW API calls, saved-state writes, or predicted Snapshot guarantees here.
Nexus = Nexus or {}
local EchoWeaver = { name = "EchoWeaver" }
Nexus.EchoWeaver = EchoWeaver

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

-- Deliberate Nexus rules on top of the base strategy. Each one is an explicit
-- input option of EchoWeaver.Decide. Without the option, EchoWeaver.Decide
-- keeps the base decision. DecideNexus passes this table. See
-- docs/ROLLING_ORB_REVIEW_EADFF8A.md for the fixtures and the trade-offs.
EchoWeaver.NEXUS_POLICY = {
    -- R3: a requested Echo whose exact count is already met does not stop a
    -- permitted Reroll. Only an Echo that is still needed does.
    rerollIgnoresSatisfiedTargets = true,
    -- R5: do not Freeze a copy that the next selection makes surplus: another
    -- selectable copy of the same Echo is on the board and one copy is needed.
    freezeMustStayNeeded = true,
}

-- Normalized pure policy with a fixed action order and fixed tie breakers.
-- Runtime-specific safety differences belong in the adapter below, never in
-- hidden re-scoring after this function returns.
function EchoWeaver.Decide(input)
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
        -- Adaptive-policy option (docs/ADAPTIVE_ROLLING.md). Without it the
        -- decision is unchanged. It reuses the protected-card, permission and
        -- resource gates above: `banish` is already false when any is unmet.
        if policy.banishBeforeReroll == true and banish then
            return Result("BANISH",trash,"BANISH_BEFORE_REROLL")
        end
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

-- Rolling-policy identity. The released planner above stays selectable.
-- ADAPTIVE is the live variant of the studied adaptive-0-settle candidate
-- (private study echo-banish-policy-sim 85ec1d2) with its group-protected,
-- neutral-weight profile. Neutral weight (equal draw weight for every eligible
-- exact Echo) is an ASSUMPTION of the study, not a measured server rule. Two
-- study inputs do not exist live and are not invented here: the eligible draw
-- pool and its weights. Scarcity therefore uses outstanding copies only, and
-- the Banish victim among equally safe offers is the first one on the board.
-- That differs from the study only when the study could rank victims by
-- family pool weight, so this variant has its own ID.
EchoWeaver.POLICY = {
    RELEASED = "released-nexus-1",
    ADAPTIVE = "adaptive-0-settle-live1",
    PROFILE = "group-protected-neutral-1",
}

-- Selector values are "adaptive" (the default) and "released" (the explicit
-- rollback). nil means the default. Any other value is not guessed at: it
-- runs the released planner and says why.
function EchoWeaver.PolicySelection(value)
    if value == nil or value == "adaptive" then return "adaptive" end
    if value == "released" then return "released" end
    return "released", "SELECTOR_UNKNOWN"
end

local LABELS = {
    SELECT_OUTSTANDING_WISHLIST="Take wanted Echo (EchoWeaver)",
    FREEZE_OUTSTANDING_FOR_HIGH_PRESSURE_SEARCH="Freeze wanted Echo before search (EchoWeaver)",
    BANISH_FOR_WISHLIST_SEARCH="Banish to find Wishlist targets (EchoWeaver)",
    REROLL_COMMON_UNWANTED_BOARD="Reroll: no requested Echo on board (EchoWeaver)",
    REROLL_NO_OUTSTANDING_ON_BOARD="Reroll: no needed Echo on board (EchoWeaver)",
    LOW_PRESSURE_FALLBACK="Take available filler (EchoWeaver)",
    RESOURCE_EXHAUSTED_FALLBACK="Take filler; search unavailable (EchoWeaver)",
    OBJECTIVE_COMPLETE_FALLBACK="Wishlist complete; take filler (EchoWeaver)",
    BANISH_BEFORE_REROLL="Banish an unwanted Echo before Reroll (EchoWeaver, experimental)",
    PAIR_FREEZE_SECOND_NEEDED="Freeze one wanted Echo to keep a second wanted offer (EchoWeaver, experimental)",
    SETTLE_HELD_WANTED="Take the held wanted Echo instead of searching (EchoWeaver, experimental)",
}

-- Everything both policies read, built once per decision. Returns nil and a
-- wait result when a required input is missing or incomplete: that refusal is
-- the same for both policies.
local function Prepare(state)
    local annotations, deltas = {}, {}
    local function Wait(reason) return nil, {type="wait",reason=reason,annotations=annotations,deltas=deltas,planner="echoweaver"} end
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
    local lockedTargets = plan.lockedRequestedCounts or {}
    for id,n in pairs(plan.requestedCounts or {}) do
        requested[id]=Count(n)
        local lockedHave = Count(locked and locked.bySpell and locked.bySpell[id])
        -- With explicit roles a current lock covers only the plan's LOCKED
        -- targets of that Echo; an ordinary target needs an ordinary copy.
        -- (A held rolled copy still counts toward a locked target it will
        -- become, so lock acquisition is neither dropped nor doubled.)
        if plan.explicitRoles then
            lockedHave = math.min(lockedHave, Count(lockedTargets[id]))
        end
        local have = Count(owned.bySpell and owned.bySpell[id]) + lockedHave
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
        -- A different quality tier of a wished family is not taken in place
        -- of the requested tier, but it is on the Wishlist: say so rather
        -- than "not on Wishlist". Explanation only; the value is unchanged.
        local family=c.family
        if family==nil and id and state.catalog and state.catalog.familyOf then
            family=state.catalog.familyOf[id]
        end
        -- Only when the card's quality differs from every requested tier of
        -- that family: a same-quality variant is not a quality difference.
        local otherTier=false
        local target=family~=nil and plan.wishedFamilies and plan.wishedFamilies[family]
            and plan.targets and plan.targets[family]
        if target then
            local cardQ=tonumber(c.quality)
            if cardQ==nil and id and state.catalog and state.catalog.rows and state.catalog.rows[id] then
                cardQ=tonumber(state.catalog.rows[id].quality)
            end
            otherTier=cardQ~=nil
            for _,tier in ipairs(target.qualityTiers or {}) do
                if tonumber(tier.q)==cardQ then otherTier=false end
            end
            if not target.qualityTiers or #target.qualityTiers==0 then
                otherTier=cardQ~=nil and tonumber(target.wishedQuality)~=cardQ
            end
        end
        annotations[i]=isFrozen and "frozen" or c.isGuaranteed and "guaranteed"
            or wanted and "wanted" or requested[id] and "target satisfied"
            or otherTier and "wrong quality" or "filler"
        deltas[i]=wanted and (100+(tonumber(c.quality) or 0)*2) or -15
    end
    local charges,refused=state.charges or {},state.searchRefused or {}
    local trusted=charges.trustworthy==true
    return {state=state,requested=requested,outstanding=outstanding,total=total,choices=choices,
        frozenCount=frozenCount,annotations=annotations,deltas=deltas,charges=charges,trusted=trusted,
        catalog=state.catalog,
        canBanish=trusted and state.allowBanish~=false and not refused.banish,
        canFreeze=trusted and state.canFreeze~=false and state.allowFreeze~=false,
        canReroll=trusted and state.allowReroll~=false and not refused.reroll}
end

-- The normalized input of the pure planner. The capability arguments let the
-- adaptive policy ask the same planner a narrower question (no Freeze, or no
-- Banish) without a second code path for the safety gates.
local function PlannerInput(prep, canBanish, canFreeze, policy)
    local state, charges = prep.state, prep.charges
    return {
        objective={requestedCounts=prep.requested,outstandingCounts=prep.outstanding,outstandingTotal=prep.total},
        remainingPicks=state.horizon,
        board={choices=prep.choices,twoFrozenRerollProhibited=prep.frozenCount>=2,
            capabilities={canSelect=true,canBanish=canBanish,canFreeze=canFreeze,canReroll=prep.canReroll}},
        resources={banishesRemaining=charges.banish,freezesRemaining=charges.freeze,rerollsRemaining=charges.reroll},
        commonBoardRerollEnabled=state.allowReroll~=false,
        policy=policy}
end

local KINDS={SELECT="take",FREEZE="freeze",BANISH="banish",REROLL="reroll",BLOCKED="wait"}
local function Finish(prep, decision, policyId, profile, requested, fallback)
    return {type=KINDS[decision.action] or "wait",spellId=decision.echoID,index=decision.index,
        reason=LABELS[decision.reasonCode] or decision.reasonCode,reasonCode=decision.reasonCode,
        annotations=prep.annotations,deltas=prep.deltas,pressure=decision.pressure,
        outstanding=prep.total,planner="echoweaver",
        policyId=policyId,policyProfile=profile,policyRequested=requested,fallbackReason=fallback}
end

local function Released(prep, requested, fallback)
    local decision=EchoWeaver.Decide(PlannerInput(prep,prep.canBanish,prep.canFreeze,EchoWeaver.NEXUS_POLICY))
    return Finish(prep,decision,EchoWeaver.POLICY.RELEASED,"none",requested,fallback)
end

-- A copy of the planner's decision aimed at another offer. Every field the
-- planner set (pressure, completion advice) is kept.
local function Redirect(prep, decision, action, index, code)
    local out={}
    for key,value in pairs(decision) do out[key]=value end
    local card=prep.choices[index]
    out.action,out.echoID,out.index,out.slot=action,card.echoID,card.index,card.index
    out.reasonCode=code or decision.reasonCode
    return out
end

-- Adaptive-0-settle, live variant. Rules, in order:
--   1. The pure planner decides with Banish-before-Reroll on unwanted boards
--      and without Freeze (it keeps every permission, resource, pending,
--      Orb-board and two-held-card Reroll rule).
--   2. A Take with two useful unheld offers and no held offer becomes a
--      Freeze of one of them (never the surplus copy of a single needed Echo).
--   3. A Take or Freeze aims at the useful offer with the most outstanding
--      copies (neutral weight, so copies per unit weight = copies).
--   4. A Banish aims at the first unheld, unguaranteed offer that is not
--      needed and whose quality group holds no needed Echo. With no such
--      offer the planner decides again without Banish.
--   5. A Banish with only held useful offers becomes a Take of the held one.
-- Returns the decision, or nil and a reason when a required input is missing.
local function Adaptive(prep)
    local choices, need, charges, state = prep.choices, prep.outstanding, prep.charges, prep.state
    local familyOf = prep.catalog and type(prep.catalog.familyOf)=="table" and prep.catalog.familyOf or nil
    local missing = {}
    for id,count in pairs(need) do
        if count>0 then
            local family = familyOf and familyOf[id]
            if family==nil then return nil,"FAMILY_UNKNOWN" end
            missing[family]=true
        end
    end
    local held, unheld = {}, {}
    for i=1,3 do
        local c=choices[i]
        if c.selectable and (need[c.echoID] or 0)>0 then
            local list=c.frozen and held or unheld
            list[#list+1]=i
        end
    end
    local options={}
    for key,value in pairs(EchoWeaver.NEXUS_POLICY) do options[key]=value end
    options.banishBeforeReroll=true
    local base=EchoWeaver.Decide(PlannerInput(prep,prep.canBanish,false,options))
    if base.action=="BLOCKED" then return base end
    local decision=base
    if base.action=="SELECT" and prep.canFreeze and Count(charges.freeze)>0
        and Integer(state.horizon,2) and prep.frozenCount==0 and #unheld>=2 then
        for _,i in ipairs(unheld) do
            local card=choices[i]
            for _,j in ipairs(unheld) do
                if i~=j and card.freezeEligible
                    and (card.echoID~=choices[j].echoID or need[card.echoID]>=2) then
                    decision=Redirect(prep,base,"FREEZE",i,"PAIR_FREEZE_SECOND_NEEDED")
                    break
                end
            end
            if decision~=base then break end
        end
    end
    local action=decision.action
    if action=="SELECT" or action=="FREEZE" then
        local list=#unheld>0 and unheld or held
        local best,bestScore
        for _,i in ipairs(list) do
            local c=choices[i]
            local eligible=action=="SELECT"
            if action=="FREEZE" and not c.frozen and c.freezeEligible then
                for _,j in ipairs(unheld) do
                    if j~=i and (choices[j].echoID~=c.echoID or need[c.echoID]>=2) then eligible=true end
                end
            end
            local score=need[c.echoID]
            if eligible and (not bestScore or score>bestScore) then best,bestScore=i,score end
        end
        if best and best~=decision.index then return Redirect(prep,decision,action,best) end
        return decision
    elseif action=="BANISH" then
        if #held>0 and #unheld==0 then return Redirect(prep,decision,"SELECT",held[1],"SETTLE_HELD_WANTED") end
        for i=1,3 do
            local c=choices[i]
            local family=familyOf and familyOf[c.echoID]
            if not c.frozen and c.banishEligible and c.selectable and (need[c.echoID] or 0)==0
                and family~=nil and not missing[family] then
                if i==decision.index then return decision end
                return Redirect(prep,decision,"BANISH",i)
            end
        end
        return EchoWeaver.Decide(PlannerInput(prep,false,false,options))
    end
    return decision
end

-- Every action the adaptive policy returns is checked again against the
-- normalized board, permissions and resources before it leaves this module.
local function Valid(prep, decision)
    local action, charges = decision.action, prep.charges
    if action=="BLOCKED" then return true end
    if action=="REROLL" then
        return prep.canReroll and Count(charges.reroll)>0 and prep.frozenCount<2
    end
    local card=prep.choices[decision.index or 0]
    if not card or card.echoID~=decision.echoID or not card.selectable then return false end
    if action=="SELECT" then return true end
    if action=="BANISH" then
        return prep.canBanish and Count(charges.banish)>0 and card.banishEligible and not card.frozen
    end
    if action=="FREEZE" then
        return prep.canFreeze and Count(charges.freeze)>0 and card.freezeEligible and not card.frozen
    end
    return false
end

function EchoWeaver.DecideNexus(state)
    local prep, waited = Prepare(state)
    if not prep then return waited end
    local selection, note = EchoWeaver.PolicySelection(state.rollingPolicy)
    if selection=="released" then return Released(prep,selection,note) end
    local ok, decision, why = pcall(Adaptive,prep)
    if not ok then return Released(prep,selection,"ADAPTIVE_ERROR") end
    if not decision then return Released(prep,selection,why) end
    if not Valid(prep,decision) then return Released(prep,selection,"ACTION_INVALID") end
    return Finish(prep,decision,EchoWeaver.POLICY.ADAPTIVE,EchoWeaver.POLICY.PROFILE,selection,nil)
end
