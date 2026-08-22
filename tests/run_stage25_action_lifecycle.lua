-- Stage 25.3 gate: each automation mutation belongs to one immutable board
-- intent. Duplicate scheduling, stale boards, and uncertain confirmation may
-- never cause a second mutation for that settled intent.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Relay.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/Readout.lua")
dofile("ui/Panel.lua")
dofile("ui/JournalTab.lua")
dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/WishlistModel.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")

NexusDB = {}
H.playerLevel = 20
H.granted = {}
H.optSettings.autoAcceptLoadoutEchoes = false
H.wishlist = {
    name="Lifecycle Goal",class="MAGE",echoes={
        {spellId=200100,quality=3,stacks=1},
        {spellId=200500,quality=1,stacks=1},
    },
}
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")
SlashCmdList.NEXUS("auto")
H.DeliverSlots({
    [2]={slot=2,name="Snapshot",verified=true,echoes={
        {spellId=200200,quality=1,stacks=1},
    }},
    [3]={slot=3,name="Lifecycle Goal",verified=false,echoes={
        {spellId=200100,quality=3,stacks=1},
        {spellId=200500,quality=1,stacks=1},
    }},
}, 2)
assert(Nexus.GameAdapter.SetLoadoutWishlist(2, 3))
Nexus.GameAdapter.RequestGranted()
assert(Nexus.GameAdapter.Owned().synced,
    "owned-state lifecycle fixture did not synchronize")
H.PushRunData({remainingBanishes=0,totalFreezes=0,usedFreezes=0,
    totalRerolls=0,usedRerolls=0})

local function Stats()
    local stats = Nexus.RecomputeStats()
    assert(type(stats.actionLifecycle) == "table"
        and type(stats.lastActionLifecycle) == "table",
        "action lifecycle diagnostics missing")
    return stats
end

local function DeliverWanted(filler, target)
    H.DeliverBoard({
        {spellId=target or 200100,quality=1},
        {spellId=filler,quality=1},
    })
end

-- A duplicate Show/recompute burst can prepare and submit one mutation only.
local start = Stats()
local selects = #H.selectCalls
DeliverWanted(200201)
H.Advance(0.2, 0.2)
for _ = 1, 20 do
    ProjectEbonhold.PerkUI.Show(H.Perks.currentChoice)
    assert(Nexus.RequestRecompute())
end
H.Advance(0.6, 0.2)
assert(#H.selectCalls == selects + 1 and H.selectCalls[#H.selectCalls] == 200100,
    "duplicate board scheduling did not settle to one target mutation")
for _ = 1, 20 do assert(Nexus.RequestRecompute()) end
H.Advance(1, 0.2)
assert(#H.selectCalls == selects + 1,
    "submitted same-board intent was issued more than once")
local submitted = Stats()
assert(submitted.actionLifecycle.prepared == start.actionLifecycle.prepared + 1
    and submitted.actionLifecycle.submitted == start.actionLifecycle.submitted + 1
    and submitted.lastActionLifecycle.state == "submitted"
    and submitted.lastActionLifecycle.mutationAttempted == true,
    "submitted lifecycle accounting drifted")
submitted.actionLifecycle.submitted = 999
submitted.lastActionLifecycle.state = "mutated"
assert(Stats().actionLifecycle.submitted ~= 999
    and Stats().lastActionLifecycle.state ~= "mutated",
    "action lifecycle diagnostics leaked mutable internal state")

-- Clearing the board confirms exactly once; later scheduling cannot replay it.
H.ResolveSelect(true)
assert(Nexus.RequestRecompute())
H.Advance(0.2, 0.2)
local confirmed = Stats()
assert(confirmed.lastActionLifecycle.state == "confirmed"
    and confirmed.lastActionLifecycle.reason == "board_cleared",
    "cleared selection board did not confirm its submitted intent")
local confirmedCount = confirmed.actionLifecycle.confirmed
for _ = 1, 10 do assert(Nexus.RequestRecompute()) end
H.Advance(0.4, 0.2)
assert(#H.selectCalls == selects + 1
    and Stats().actionLifecycle.confirmed == confirmedCount,
    "confirmed intent advanced or mutated more than once")

-- A prepared intent is void when its board disappears before the beat.
local staleBefore = #H.selectCalls
DeliverWanted(200202)
H.Advance(0.2, 0.2)
H.Perks.currentChoice = nil
H.Advance(0.4, 0.2)
local stale = Stats()
assert(#H.selectCalls == staleBefore
    and stale.lastActionLifecycle.state == "superseded"
    and stale.lastActionLifecycle.reason == "board_unavailable_before_submit",
    "stale prepared intent survived a missing board")

-- Authorization is re-read immediately before submission.
DeliverWanted(200203)
H.Advance(0.2, 0.2)
local authBefore = #H.selectCalls
SlashCmdList.NEXUS("auto")
H.Advance(0.4, 0.2)
assert(#H.selectCalls == authBefore
    and Stats().lastActionLifecycle.reason == "authorization_changed",
    "revoked authorization still allowed an adapter mutation")
SlashCmdList.NEXUS("auto")

-- A same-board negative/late reply becomes uncertain, then expires. Neither
-- duplicate dirties nor the watchdog deadline may reissue the mutation.
DeliverWanted(200204)
H.Advance(0.6, 0.2)
local uncertainCount = #H.selectCalls
assert(uncertainCount == authBefore + 1
    and Stats().lastActionLifecycle.state == "submitted",
    "uncertainty fixture did not submit exactly one board action")
local confirmationExpiresAt = Stats().lastActionLifecycle.submittedAt + 10
H.ResolveSelect(false)
assert(Nexus.RequestRecompute())
H.Advance(0.2, 0.2)
assert(Stats().lastActionLifecycle.state == "uncertain",
    "same-board latch release did not enter uncertainty")
for _ = 1, 25 do
    ProjectEbonhold.PerkUI.Show(H.Perks.currentChoice)
    assert(Nexus.RequestRecompute())
end
local untilJustBeforeExpiry = confirmationExpiresAt - H.now - 0.1
assert(untilJustBeforeExpiry > 0,
    "uncertainty fixture reached its expiry before the boundary probe")
H.Advance(untilJustBeforeExpiry, 0.1)
assert(#H.selectCalls == uncertainCount
    and Stats().lastActionLifecycle.state == "uncertain"
    and H.now < confirmationExpiresAt,
    "uncertain intent retried or expired before its exact boundary")
H.Advance(0.1, 0.1)
local expired = Stats()
assert(#H.selectCalls == uncertainCount
    and expired.lastActionLifecycle.state == "expired"
    and expired.lastActionLifecycle.reason == "confirmation_timeout"
    and H.now >= confirmationExpiresAt,
    "uncertain intent did not expire exactly at its bounded deadline")
for _ = 1, 10 do assert(Nexus.RequestRecompute()) end
H.Advance(0.4, 0.2)
assert(#H.selectCalls == uncertainCount,
    "expired same-board intent was reissued")

-- A board transition confirms the old intent but cannot bypass the adapter's
-- still-live latch. Once that latch clears, only the new board target submits.
H.ResolveSelect(false)
DeliverWanted(200205)
H.Advance(0.6, 0.2)
local transitionBefore = #H.selectCalls
assert(transitionBefore == uncertainCount + 1,
    "transition fixture did not submit one old-board action")
DeliverWanted(200206, 200500)
H.Advance(0.6, 0.2)
local transition = Stats()
assert(#H.selectCalls == transitionBefore
    and transition.lastActionLifecycle.state == "prepared"
    and transition.actionLifecycle.confirmed >= confirmedCount + 1,
    "new board bypassed the old adapter latch or lost confirmation")
H.ResolveSelect(false)
assert(Nexus.RequestRecompute())
H.Advance(0.4, 0.2)
assert(#H.selectCalls == transitionBefore + 1
    and H.selectCalls[#H.selectCalls] == 200500,
    "late confirmation did not preserve the new board's immutable target")

-- A malformed replacement cannot mutate through a prepared board intent.
H.ResolveSelect(true)
DeliverWanted(200207)
H.Advance(0.2, 0.2)
local malformedBefore = #H.selectCalls
H.Perks.currentChoice = {{quality=1}}
ProjectEbonhold.PerkUI.Show(H.Perks.currentChoice)
H.Advance(0.6, 0.2)
assert(#H.selectCalls == malformedBefore,
    "malformed replacement board reached the mutation boundary")
assert(Stats().lastActionLifecycle.state == "superseded"
    and Stats().lastActionLifecycle.reason == "board_unavailable_before_submit",
    "malformed replacement did not supersede its prepared intent")

-- A genuine run boundary voids a prepared action before StepRun can submit it.
DeliverWanted(200208)
H.Advance(0.2, 0.2)
H.playerLevel = 80
H.FireEvent("PLAYER_LEVEL_UP", 80)
H.Advance(0.2, 0.2)
assert(Stats().lastActionLifecycle.state == "prepared",
    "level-80 run completion unexpectedly consumed the prepared action")
local boundaryBefore = #H.selectCalls
H.playerLevel = 1
H.FireEvent("PLAYER_LEVEL_UP", 1)
assert(Nexus.RequestRecompute())
H.Advance(0.2, 0.2)
assert(#H.selectCalls == boundaryBefore
    and Stats().lastActionLifecycle.state == "superseded"
    and Stats().lastActionLifecycle.reason == "run_boundary",
    "run boundary did not void its prepared board action")

local final = Stats()
print(string.format(
    "stage25 action lifecycle: prepared=%d submitted=%d confirmed=%d uncertain=%d expired=%d superseded=%d preauthFailed=%d selects=%d",
    final.actionLifecycle.prepared,final.actionLifecycle.submitted,
    final.actionLifecycle.confirmed,final.actionLifecycle.uncertain,
    final.actionLifecycle.expired,final.actionLifecycle.superseded,
    final.actionLifecycle.preauthFailed,#H.selectCalls))
print("board-bound action lifecycle and bounded confirmation -- OK")
