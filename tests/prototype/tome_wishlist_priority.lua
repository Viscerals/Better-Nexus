-- Restore confirmed-disabled Wishlist tomes before pruning unwanted tomes on
-- the same paced level-one action beat. Real runtime/assignment facades, with
-- synthetic server mirrors; no native client, resource use, or private data.
local checks, failures = 0, {}
local function check(value, message) assert(value, message); checks = checks + 1 end
local function expect(value, message)
    checks = checks + 1
    if not value then failures[#failures+1] = message end
end
local REQUIRED, LEVER, EXTRAS = 300001, 777001, 6
local UNKNOWN, NONCONFORMANT, OPTED_OUT = REQUIRED+7, REQUIRED+8, REQUIRED+9
local function fixture(route, holdRequired)
    Nexus, NexusDB, WishlistRealizerDB = nil, nil, nil
    local H = dofile('tests/prototype/harness.lua')
    for offset=0,9 do
        local id, lever = REQUIRED+offset, LEVER+offset
        local name = 'Gated Echo '..offset
        H.names[lever] = offset == 8 and 'Unrelated tome name' or 'Tome of '..name
        H.AddEcho(id, name, 1, 1, 0); H.db[id].requiredSpell = lever
        if offset ~= 7 then H.discovered[id] = true end
    end
    H.perks.discoveredEchoes = H.discovered
    H.disabled[REQUIRED] = true
    H.playerLevel, H.orbKnown = 80, true
    if route == 'active_saved' then
        H.perks.serverActiveSlot = 1
        H.perks.serverBuildSlots[1] = {name='Active Saved Build', verified=true,
            echoes={{spellId=200001,quality=1,stacks=1}}}
    end
    ProjectEbonhold.OrbService = {IsStateKnown=function() return H.orbKnown end,
        IsOfferPending=function() return false end}
    local trace, rawToggle = {}, H.service.ToggleTomeEcho
    H.service.ToggleTomeEcho = function(id)
        local result = rawToggle(id)
        trace[#trace+1] = {id=id, at=H.now}
        if not (id == REQUIRED and holdRequired) then
            H.disabled[id] = not H.disabled[id]; H.Notify()
        end
        return result
    end
    H.Boot()
    local A = Nexus.GameAdapter
    check(Nexus.MainInternals.StoreAuthorityOwner.UpdateSettingsV1('leverOptOut', {[LEVER+9]=true}),
        route..' opted-out control installed through settings owner')
    local function assign(wanted)
        local name = wanted and 'New Wishlist' or 'Old Wishlist'
        local echoes = {{spellId=wanted and REQUIRED or 200001,quality=1,stacks=1}}
        local ok, why
        if route == 'active_saved' then ok, why = A.SetLoadoutWishlistIdentity(1,name,echoes,{})
        else ok, why = A.SetFirstLoadoutWishlistIdentity(name,echoes) end
        check(ok == true, route..' assignment: '..tostring(why)); H.Notify()
    end
    assign(false); SlashCmdList.NEXUS('auto'); H.Advance(.4,.05)
    check(Nexus.Panel._lastModel.auto == true and Nexus.Store.Settings().autoDisable == true,
        route..' Auto and tome permission ON')
    check(A.DiscoverySynced() == true and A.OrdinaryBoardAllowed() == true
        and A.TomeMutationPaused() == false, route..' readiness gates open')
    check(#trace == 0, route..' level80 sends no tome mutations')
    H.resetAt = H.now; H.playerLevel = 1; H.Fire('PLAYER_LEVEL_UP',1); H.Notify(); assign(true)
    return H,A,trace
end
local function controls(H,A,trace,route)
    local targetSends = 0
    for i,row in ipairs(trace) do
        check(row.id ~= UNKNOWN and row.id ~= NONCONFORMANT and row.id ~= OPTED_OUT,
            route..' unknown/nonconformant/opted-out controls are not pruned')
        if row.id == REQUIRED then targetSends = targetSends + 1 end
        -- cadence.leverInterval is 0.5; accepted sends must not bunch tighter.
        if i > 1 then check(row.at-trace[i-1].at >= .5-1e-6, route..' original send spacing retained') end
    end
    check(targetSends <= 1, route..' required enable is never duplicated')
    local plan = Nexus.Strategy.Compile(A.Catalog(),A.Wishlist(),Nexus.Store.Settings())
    local keep, skip = {}, {}
    for _,id in ipairs(plan.leverPlan.keep) do keep[id] = true end
    for _,id in ipairs(plan.leverPlan.skippedNonConformant) do skip[id] = true end
    check(keep[LEVER] and keep[LEVER+9] and skip[LEVER+8], route..' current plan and control partitions')
end
for _,route in ipairs({'first_run','active_saved'}) do
    for _,scenario in ipairs({'held_level1','exit_level2','no_ack','closed_gate'}) do
        local H,A,trace = fixture(route,scenario == 'no_ack')
        if scenario == 'closed_gate' then
            H.orbKnown = false; H.Advance(1,.05)
            check(#trace == 0 and H.disabled[REQUIRED] == true, route..' closed Orb gate sends nothing')
            H.orbKnown = true
        end
        -- One leverInterval beat (0.5 s); a longer window admits a prune send.
        H.Advance(.25,.05)
        expect(#trace == 1 and trace[1].id == REQUIRED,
            route..' '..scenario..': first eligible action beat must restore required tome before pruning')
        if scenario == 'exit_level2' then
            H.playerLevel = 2; H.Fire('PLAYER_LEVEL_UP',2); H.Advance(4,.05)
            expect(#trace == 1 and H.disabled[REQUIRED] == false,
                route..': restoring at1 must survive exit before the next paced beat')
            local ok,why = A.ToggleLever(LEVER+1,true)
            check(ok == false and why == 'not level 1', route..' no outside-level1 mutation')
        else
            if scenario == 'no_ack' then
                local pending = Nexus.Store.State().tomeTogglePending[LEVER]
                expect(pending and pending.want == false and H.disabled[REQUIRED] == true,
                    route..': first accepted required enable remains pending without its mirror')
            end
            -- Drain the paced 0.5 s queue well before the 30 s pending expiry.
            H.Advance(4,.05)
            check(#trace == EXTRAS+1, route..' one enable plus all six eligible unwanted disables')
            if scenario == 'no_ack' then
                local pending = Nexus.Store.State().tomeTogglePending[LEVER]
                check(pending and pending.want == false and H.disabled[REQUIRED] == true,
                    route..' absent acknowledgement never becomes confirmation')
                -- Expiry is not resubmit permission: a late first effect must
                -- not be undone by a second toggle after the 30 s window.
                H.Advance(31,.05)
                check(#trace == EXTRAS+1, route..' expired unconfirmed enable is not resent')
                check(H.disabled[REQUIRED] == true, route..' held enable mirror is unchanged after expiry')
            else check(H.disabled[REQUIRED] == false, route..' required tome restored at1') end
        end
        controls(H,A,trace,route)
        print(string.format('TRACE %s %s first=%s t=+%.2f sends=%d level=%d requiredDisabled=%s',
            route,scenario,trace[1] and tostring(trace[1].id) or 'none',
            trace[1] and trace[1].at-H.resetAt or 0,#trace,H.playerLevel,tostring(H.disabled[REQUIRED])))
    end
end
assert(#failures == 0,table.concat(failures,'\n'))
print('PASS level1 Wishlist tome restore priority and mutation guards checks='..checks)
