-- Characterize Main as the sole lifecycle/automation coordinator. Passive
-- views and diagnostics must remain action-free even when an auto action is
-- armed and its pacing deadline has elapsed.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Relay.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
dofile("core/DpsCapture.lua")
dofile("core/GameAdapter.lua")
dofile("ui/Readout.lua")
dofile("ui/Panel.lua")

local Store, Adapter = Nexus.Store, Nexus.GameAdapter
UnitName = function() return "Hero" end
GetNormalizedRealmName = function() return "Ebonhold" end
GetRealmName = GetNormalizedRealmName
H.playerLevel = 5
local targetEchoes = {{spellId=200100, quality=3, stacks=1}}
NexusDB = {
    settingsVersion=2,
    settings={
        autoPick=true, autoActivate=false, autoDisable=false,
        autoBanish=true, autoSave=false,
    },
    chars={["hero@ebonhold"]={
        loadoutWishlists={
            [1]={slot=6, name="Main Contract",
                key=Adapter.WishlistKey(targetEchoes)},
        },
        futureSafety={keep=true},
    }},
    communityBuilds={}, futureRoot={keep=true},
}
H.PushRunData({
    remainingBanishes=3, totalRerolls=3, usedRerolls=0,
    totalFreezes=3, usedFreezes=0,
})
H.granted = {}
H.DeliverDiscovery({})
H.DeliverSlots({
    [1]={slot=1, name="Saved Loadout", verified=true,
        echoes={{spellId=200102, stacks=1}}},
    [6]={slot=6, name="Main Contract", verified=false,
        echoes=targetEchoes},
}, 1)
H.DeliverBoard({
    {spellId=200100, quality=3},
    {spellId=200102, quality=2},
    {spellId=200104, quality=2},
})

local lifecycle, routed = {}, {}
local function Wrap(owner, name, label, sink)
    local original = owner[name]
    assert(type(original) == "function", "missing wrapped function " .. label)
    owner[name] = function(...)
        local target = sink or lifecycle
        target[#target + 1] = label
        return original(...)
    end
end

Wrap(Store, "Init", "Store.Init")
Wrap(Nexus.DiagnosticLogs, "Init", "DiagnosticLogs.Init")
Wrap(Adapter, "Init", "Adapter.Init")
Wrap(Adapter, "OnEvent", "Adapter.OnEvent", routed)
Wrap(Adapter, "RequestSlots", "Adapter.RequestSlots", routed)
Wrap(Adapter, "Poll", "Adapter.Poll", routed)
Wrap(Adapter, "ConsumeDirty", "Adapter.ConsumeDirty", routed)
Wrap(Nexus.Sync, "Init", "Sync.Init")
Wrap(Nexus.Sync, "OnUpdate", "Sync.OnUpdate", routed)
Wrap(Nexus.Sync, "HandleIncoming", "Sync.HandleIncoming", routed)
Wrap(Nexus.Sync, "HandleStatusRequest", "Sync.HandleStatusRequest", routed)
Wrap(Nexus.DpsCapture, "Init", "DpsCapture.Init")
Wrap(Nexus.DpsCapture, "OnUpdate", "DpsCapture.OnUpdate", routed)
Wrap(Nexus.DpsCapture, "OnCombatStart", "DpsCapture.OnCombatStart", routed)
Wrap(Nexus.DpsCapture, "OnCombatEnd", "DpsCapture.OnCombatEnd", routed)
Wrap(Nexus.Panel, "Init", "Panel.Init")

local policyInputs, policyOutputs = {}, {}
local originalDecide = Nexus.Policy.Decide
Nexus.Policy.Decide = function(state)
    local input = table.concat({
        tostring(state and state.level),
        tostring(state and state.board and state.board.signature),
        tostring(state and state.charges and state.charges.banish),
        tostring(state and state.charges and state.charges.reroll),
        tostring(state and state.charges and state.charges.freeze),
        tostring(state and state.plan and state.plan.advisorOnly),
    }, "|")
    policyInputs[#policyInputs + 1] = input
    local decision = originalDecide(state)
    policyOutputs[#policyOutputs + 1] = table.concat({
        tostring(decision and decision.type),
        tostring(decision and decision.spellId),
        tostring(decision and decision.index),
        tostring(decision and decision.reason),
    }, "|")
    return decision
end

local optional = {}
local function Note(name)
    optional[#optional + 1] = name
end
Nexus.LogViewer = {Init=function() Note("LogViewer.Init") end}
Nexus.WishlistEditor = {
    Init=function() Note("WishlistEditor.Init") end,
    Toggle=function() Note("WishlistEditor.Toggle") end,
}
Nexus.WishlistOverlay = {
    Init=function() Note("WishlistOverlay.Init") end,
    Show=function() Note("WishlistOverlay.Show") end,
    Refresh=function() Note("WishlistOverlay.Refresh") end,
}
Nexus.CommunityBuilds = {
    Init=function() Note("CommunityBuilds.Init") end,
    Refresh=function() Note("CommunityBuilds.Refresh") end,
    MarkDataDirty=function() Note("CommunityBuilds.MarkDataDirty") end,
}
Nexus.Leaderboard = {
    Init=function() Note("Leaderboard.Init") end,
    Refresh=function() Note("Leaderboard.Refresh") end,
    RefreshData=function() Note("Leaderboard.RefreshData") end,
}
Nexus.Nameplate = {Init=function() Note("Nameplate.Init") end}
Nexus.ServerStatus = {Init=function() Note("ServerStatus.Init") end}

dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/WishlistModel.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")
for _, name in ipairs({
    "RequestRecompute", "RetryAutoLock", "AppendAudit", "RecomputeStats", "RefreshHudView",
    "HudSnapshotStats", "NewAIExportCoroutine", "GetDiagnosticPageText",
    "RefreshPanel",
}) do
    assert(type(Nexus[name]) == "function",
        "Main facade lost callable surface " .. tostring(name))
end

local function MutationSnapshot()
    return table.concat({
        #H.wire, #H.selectCalls, #H.banishCalls, H.rerollCalls,
        #H.freezeCalls, #H.activateCalls, #H.saveCalls,
    }, ":")
end

-- ADDON_LOADED owns only SavedVariables/diagnostic binding. The update frame
-- remains inert until PLAYER_ENTERING_WORLD completes initialization.
H.FireEvent("ADDON_LOADED", "Nexus")
assert(table.concat(lifecycle, ",") == "Store.Init,DiagnosticLogs.Init",
    "ADDON_LOADED performed more than cheap persistence initialization")
H.Advance(0.4, 0.2)
assert(#routed == 0 and MutationSnapshot() == "0:0:0:0:0:0:0",
    "pre-world update reached adapter, transport, or gameplay work")

H.FireEvent("PLAYER_ENTERING_WORLD")
local expectedLifecycle = table.concat({
    "Store.Init", "DiagnosticLogs.Init",
    "Store.Init", "DiagnosticLogs.Init", "Adapter.Init", "Panel.Init",
    "Sync.Init", "DpsCapture.Init",
}, ",")
assert(table.concat(lifecycle, ",") == expectedLifecycle,
    "Main initialization order changed: " .. table.concat(lifecycle, ","))
assert(table.concat(optional, ",") == table.concat({
    "LogViewer.Init", "WishlistEditor.Init", "WishlistOverlay.Init",
    "CommunityBuilds.Init", "Leaderboard.Init", "Nameplate.Init",
    "ServerStatus.Init",
}, ","), "optional facade initialization order changed")
assert(table.concat(routed, ",", 1, 2)
    == "Adapter.OnEvent,Adapter.RequestSlots",
    "world-entry routing changed before Sync/DPS initialization")

-- Sync/DPS update every frame after readiness, while Poll/automation remains
-- on the direct 0.2-second cadence.
local routeBase = #routed
H.Advance(0.19, 0.19)
assert(#routed == routeBase + 2
    and routed[routeBase + 1] == "Sync.OnUpdate"
    and routed[routeBase + 2] == "DpsCapture.OnUpdate",
    "sub-cadence frame reached Poll or changed update ordering")
-- Cross the 0.2 threshold rather than landing on it exactly: binary floating
-- point representations must not decide whether this contract fixture ticks.
H.Advance(0.02, 0.02)
local pollAt, consumeAt
for i = routeBase + 3, #routed do
    if routed[i] == "Adapter.Poll" then pollAt = i end
    if routed[i] == "Adapter.ConsumeDirty" then consumeAt = i end
end
assert(pollAt and consumeAt and pollAt < consumeAt
    and #policyInputs == 1 and #policyOutputs == 1,
    "0.2-second direct poll did not perform one ordered safe step: routes="
        .. table.concat(routed, ",") .. " inputs=" .. tostring(#policyInputs)
        .. " outputs=" .. tostring(#policyOutputs))
local manualInput, manualDecision = policyInputs[1], policyOutputs[1]
assert(not manualDecision:find("^wait|"),
    "Main action fixture produced only a wait decision")
assert(MutationSnapshot() == "0:0:0:0:0:0:0",
    "manual-mode safe step submitted gameplay work")

-- Arm automation, let the intent deadline mature without firing OnUpdate,
-- and prove every passive provider/refresh stays action-free. Only the next
-- direct cadence tick may submit the prepared decision.
SlashCmdList["NEXUS"]("auto")
H.Advance(0.2, 0.2)
assert(#policyInputs == 2 and policyInputs[2] == manualInput
    and policyOutputs[2] == manualDecision
    and MutationSnapshot() == "0:0:0:0:0:0:0",
    "identical input changed decision or skipped the intent beat")
H.now = H.now + 0.5
local passiveBefore = MutationSnapshot()
assert(Nexus.RefreshHudView(), "passive HUD refresh failed")
assert(type(Nexus.GetDiagnosticPageText("sync")) == "string",
    "diagnostic page provider changed shape")
assert(Nexus.AppendAudit("CONTRACT", {value="passive"}),
    "audit append fixture failed")
local export = Nexus.NewAIExportCoroutine()
while coroutine.status(export) ~= "dead" do
    local ok, why = coroutine.resume(export)
    assert(ok, "diagnostic export failed: " .. tostring(why))
end
SlashCmdList["NEXUS"]("status")
SlashCmdList["NEXUS"]("panel")
SlashCmdList["NEXUS"]("editor")
assert(Nexus.ViewRefresh.Request())
assert(Nexus.Scheduler.Tick(H.now + 0.1) >= 1)
local editorToggled = false
for _, entry in ipairs(optional) do
    if entry == "WishlistEditor.Toggle" then editorToggled = true end
end
assert(MutationSnapshot() == passiveBefore and editorToggled,
    "passive diagnostic, slash, HUD, or scheduled view submitted gameplay work")

H.Advance(0.2, 0.2)
assert(#H.selectCalls == 1 and H.selectCalls[1] == 200100
    and #H.banishCalls == 0 and H.rerollCalls == 0
    and #H.freezeCalls == 0 and #H.activateCalls == 0 and #H.saveCalls == 0,
    "direct deadline tick changed the prepared GameAdapter mutation")
H.ResolveSelect(false)
Adapter.Poll()

local stats = Nexus.RecomputeStats()
assert(stats.polls == 3 and stats.fullSteps == 3
    and stats.forced == 1 and stats.explicit == 1
    and stats.deadlines == 1
    and stats.fallbackSeconds == 5,
    string.format("Main recompute counters changed: polls=%d full=%d forced=%d explicit=%d deadlines=%d fallback=%d",
        stats.polls,stats.fullSteps,stats.forced,stats.explicit,
        stats.deadlines,stats.fallbackSeconds))
stats.polls = -1
assert(Nexus.RecomputeStats().polls == 3,
    "Main recompute stats stopped returning a defensive snapshot")
local hudStats = Nexus.HudSnapshotStats()
hudStats.refreshes = -1
assert(Nexus.HudSnapshotStats().refreshes ~= -1,
    "Main HUD stats stopped returning a defensive snapshot")

-- Lifecycle/event routing stays ordered and cannot submit another action.
local routeBeforeEvents = #routed
local mutationBeforeEvents = MutationSnapshot()
H.FireEvent("PLAYER_LEVEL_UP", 6)
H.FireEvent("PLAYER_REGEN_DISABLED")
H.FireEvent("PLAYER_REGEN_ENABLED")
H.FireEvent("CHAT_MSG_CHANNEL", "WLNP|Peer|1.20.0", "Peer", "Common",
    "5. wrbuildssync", nil, nil, nil, 5, "wrbuildssync")
H.FireEvent("CHAT_MSG_WHISPER", "WLRQ|Dev|request-9|dev", "Dev")
assert(table.concat(routed, ",", routeBeforeEvents + 1) == table.concat({
    "Adapter.OnEvent", "DpsCapture.OnCombatStart", "DpsCapture.OnCombatEnd",
    "Sync.HandleIncoming", "Sync.HandleStatusRequest",
}, ","), "Main event routing order changed: "
    .. table.concat(routed, ",", routeBeforeEvents + 1))
assert(MutationSnapshot() == mutationBeforeEvents,
    "passive lifecycle routing submitted gameplay work")

print("Main boot, event/slash routing, policy parity, passive safety, and direct cadence -- OK")

return {
    harness=H,
    adapter=Adapter,
    routed=routed,
    mutationSnapshot=MutationSnapshot,
    policyInputs=policyInputs,
    policyOutputs=policyOutputs,
}
