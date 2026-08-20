-- Stage 35.4 expected red: exercise the real initialized Main event path for
-- near-instant level bursts. This proves only deterministic addon-side bounds;
-- it does not reproduce or attribute the reported native client exit.
local fixture = assert(dofile("tests/run_main_contract_characterization.lua"))
local H = assert(fixture.harness)
local Adapter = assert(fixture.adapter)

local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end

local function Count(source)
    local count = 0
    for _ in pairs(source or {}) do count = count + 1 end
    return count
end

local function MutationSnapshot()
    return table.concat({
        #H.selectCalls,#H.banishCalls,H.rerollCalls,#H.freezeCalls,
        #H.activateCalls,#H.saveCalls,
    }, ":")
end

local function Counters()
    local recompute = Nexus.RecomputeStats()
    local hud = Nexus.HudSnapshotStats()
    local render = Nexus.Panel.RenderStats()
    local sync = Nexus.Sync.Stats()
    return {
        polls=recompute.polls,fullSteps=recompute.fullSteps,
        skipped=recompute.skipped,fallbackChecks=recompute.fallbackChecks,
        staticPhases=recompute.phaseCounts.static or 0,
        boardPhases=recompute.phaseCounts.board or 0,
        policyPhases=recompute.phaseCounts.policy or 0,
        hudPreparePhases=recompute.phaseCounts.overlayPrepare or 0,
        hudRenderPhases=recompute.phaseCounts.overlayRender or 0,
        hudBuilds=hud.builds,hudRefreshes=hud.refreshes,
        panelRenders=render.renders or render.renderCalls or 0,
        syncSent=sync.sent or 0,syncReceived=sync.received or 0,
        scheduler=#Nexus.Scheduler.Pending(),handlers=#H.updateHandlers,
        wire=#H.wire,mutations=MutationSnapshot(),
    }
end

local function Delta(after, before, key)
    return (tonumber(after[key]) or 0) - (tonumber(before[key]) or 0)
end

local function BurstDelta(after, before, key)
    return (tonumber(after[key]) or 0) - (tonumber(before[key]) or 0)
end

local function WorkBounded(after, before, pumps)
    return Delta(after, before, "staticPhases") <= pumps
        and Delta(after, before, "boardPhases") <= pumps
        and Delta(after, before, "policyPhases") <= pumps
        and Delta(after, before, "hudPreparePhases") <= pumps
        and Delta(after, before, "hudRenderPhases") <= pumps
        and Delta(after, before, "panelRenders") <= pumps
end

local function FireLevels(levels, distributed)
    for index, level in ipairs(levels) do
        H.playerLevel = level
        H.FireEvent("PLAYER_LEVEL_UP", level)
        if index % 3 == 0 then H.NotifyEchoDataChanged() end
        if index % 7 == 0 then Adapter.CheckCatalogSource() end
        if distributed then H.Advance(0.01, 0.01) end
    end
end

local sequential = {}
for level = 2, 60 do sequential[#sequential + 1] = level end
local disorder = {2,2,9,4,17,16,40,22,59,59,8,60}

-- Start from a passive state. The original contract leaves Auto enabled; an
-- empty board makes the transition safe even before toggling it off.
H.DeliverBoard({})
SlashCmdList["NEXUS"]("auto")
Nexus.Panel.Hide()
Adapter.ConsumeDirty()
local burstBaseline = Adapter.LevelBurstStats()

local before = Counters()
H.playerLevel = 1
FireLevels(sequential, false)
local queued = Counters()
Check(queued.polls == before.polls and queued.fullSteps == before.fullSteps
        and queued.wire == before.wire and queued.mutations == before.mutations,
    "one-frame 59-transition burst performed work before the direct cadence")
H.Advance(0.21, 0.21)
local oneFrame = Counters()
Check(Delta(oneFrame, before, "polls") == 1
        and Delta(oneFrame, before, "fullSteps") <= 1
        and WorkBounded(oneFrame, before, 1),
    "one-frame burst was not coalesced into one direct poll/step")
Check(oneFrame.mutations == before.mutations
        and oneFrame.syncSent == before.syncSent,
    "passive one-frame burst amplified gameplay or network actions")
Check(H.playerLevel == 60 and UnitLevel("player") == 60,
    "one-frame burst lost the authoritative final level")
local oneFrameBurst = Adapter.LevelBurstStats()
Check(BurstDelta(oneFrameBurst, burstBaseline, "events") == 59
        and BurstDelta(oneFrameBurst, burstBaseline, "bursts") == 1
        and BurstDelta(oneFrameBurst, burstBaseline, "coalesced") == 58
        and BurstDelta(oneFrameBurst, burstBaseline, "pumps") == 1
        and oneFrameBurst.lastLevel == 60,
    "one-frame burst counters lost exact coalescing or final-level authority")

-- Visible HUD, Auto enabled, changing board, valid Wishlist, and an active
-- Sync receive window all remain on their existing owners. The one explicit
-- request is captured before the burst so transition traffic must add zero.
Nexus.Panel.Show()
SlashCmdList["NEXUS"]("auto")
H.DeliverSlots({
    [1]={slot=1,name="Valid",verified=false,
        echoes={{spellId=200100,stacks=1}}},
}, 1)
H.DeliverBoard({
    {spellId=200100,quality=3},{spellId=200102,quality=2},
    {spellId=200104,quality=1},
})
local requested = Nexus.Sync.RequestSync()
for _ = 1, 20 do
    if Nexus.Sync.IsReceiving() then break end
    H.Advance(0.1, 0.1)
end
local syncBaseline = Counters()
Check(requested == true and Nexus.Sync.IsReceiving(),
    "real Sync fixture did not enter its request-scoped receive window")
H.playerLevel = 1
FireLevels(disorder, false)
H.DeliverBoard({
    {spellId=200104,quality=2},{spellId=200102,quality=2},
    {spellId=200100,quality=3},
})
H.Advance(0.21, 0.21)
local mixed = Counters()
Check(Delta(mixed, syncBaseline, "polls") == 1
        and Delta(mixed, syncBaseline, "fullSteps") <= 1
        and mixed.syncSent == syncBaseline.syncSent,
    "duplicate/out-of-order burst escaped one pump or amplified Sync")
Check(H.playerLevel == 60 and UnitLevel("player") == 60,
    "event arguments overrode the authoritative direct-jump level")

-- Unresolved and locked-only Wishlist shapes are represented through the
-- same real slot notification path. Distributed delivery may cross at most
-- three 0.2-second cadence boundaries over 0.59 seconds.
H.DeliverSlots({
    [2]={slot=2,name="Locked only",verified=false,
        echoes={{spellId=200104,stacks=1,locked=true}}},
}, 2)
local distributedBefore = Counters()
H.playerLevel = 1
FireLevels(sequential, true)
local distributedAfter = Counters()
local distributedPolls = Delta(distributedAfter, distributedBefore, "polls")
Check(distributedPolls >= 2 and distributedPolls <= 3
        and Delta(distributedAfter, distributedBefore, "fullSteps")
            <= distributedPolls
        and WorkBounded(distributedAfter, distributedBefore,
            distributedPolls),
    "distributed burst exceeded the established direct cadence bound")
Check(distributedAfter.mutations == distributedBefore.mutations
        and distributedAfter.syncSent == distributedBefore.syncSent,
    "distributed locked-only burst amplified actions or network traffic")

-- Repeat the burst enough times to catch scheduler/task accumulation. Fixed
-- owner tables and update handlers must retain their shape.
Nexus.Panel.Hide()
SlashCmdList["NEXUS"]("auto")
local repetitionBefore = Counters()
for repetition = 1, 24 do
    H.playerLevel = 1
    FireLevels(disorder, false)
    H.playerLevel = 60
    H.FireEvent("PLAYER_LEVEL_UP", 60)
    H.Advance(0.21, 0.21)
end
local repetitionAfter = Counters()
Check(Delta(repetitionAfter, repetitionBefore, "polls") == 24
        and Delta(repetitionAfter, repetitionBefore, "fullSteps") <= 24
        and WorkBounded(repetitionAfter, repetitionBefore, 24),
    "repeated bursts escaped one-pump-per-cadence work bounds")
Check(repetitionAfter.scheduler == repetitionBefore.scheduler
        and repetitionAfter.handlers == repetitionBefore.handlers,
    "repeated bursts grew scheduler tasks or update handlers")
Check(repetitionAfter.mutations == repetitionBefore.mutations
        and repetitionAfter.syncSent == repetitionBefore.syncSent,
    "repeated passive bursts amplified actions or network traffic")
Check(Count(Nexus.Errors and Nexus.Errors.History
        and Nexus.Errors.History() or {}) == 0,
    "offline burst fixture suppressed an addon error")

-- The repaired owners expose only fixed scalar proof. These counters do not
-- claim that Nexus caused or prevents the reported native client exit.
local stats = Nexus.RecomputeStats()
local burst = Adapter.LevelBurstStats()
Check(stats.levelEvents == burst.events
        and stats.levelBursts == burst.bursts
        and stats.levelEventsCoalesced == burst.coalesced,
    "runtime burst counters diverged from the fixed adapter owner")
Check(BurstDelta(burst, burstBaseline, "events") == 442
        and BurstDelta(burst, burstBaseline, "coalesced")
            == BurstDelta(burst, burstBaseline, "events")
                - BurstDelta(burst, burstBaseline, "bursts")
        and burst.pending == 0 and burst.queueHighWater == 59,
    "session burst totals, coalescing, or fixed queue bound changed")
Check(burst.recomputes == burst.pumps
        and burst.renders <= burst.recomputes
        and burst.actions == 0 and burst.maxWorkPerPump <= 2
        and burst.lastLevel == 60,
    "burst work per pump exceeded recompute/render/action bounds")
local diagnostic = Nexus.GetDiagnosticPageText("automation")
Check(tostring(diagnostic):find("level burst", 1, true)
        and tostring(diagnostic):find("actions=0", 1, true),
    "sanitized automation diagnostic omitted bounded burst state")

print(string.format(
    "level burst characterization: transitions=59 one_frame=1 distributed=%d repeated=24 actions=0 sync_amplification=0 scheduler_growth=0 expected_red=%d checks=%d native_attribution=none -- OK",
    distributedPolls,0,checks))
