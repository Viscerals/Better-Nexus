-- Stage 36.1 expected red: exercise the real lifecycle, GameAdapter, and
-- AutomationRuntime owners for retained failures, coalesced run boundaries,
-- and one bounded retry after a failed full step.
local failures = {}

local function Check(name, condition, detail)
    if not condition then
        failures[#failures + 1] = name .. ": " .. tostring(detail)
    end
end

local function ContainsSource(records, source)
    for _, record in ipairs(records) do
        if record.source == source then return true end
    end
    return false
end

local function CountSource(records, source)
    local count = 0
    for _, record in ipairs(records) do
        if record.source == source then count = count + 1 end
    end
    return count
end

local function CountMessage(records, source, needle)
    local count = 0
    for _, record in ipairs(records) do
        if record.source == source
            and record.message:find(needle, 1, true) then
            count = count + 1
        end
    end
    return count
end

------------------------------------------------------------------------
-- MainLifecycle must retain isolated Sync/DPS failures without flooding the
-- bounded Errors owner with an identical entry on every frame/event.
------------------------------------------------------------------------
Nexus = {VERSION="stage36", MainInternals={}}
dofile("core/MainLifecycle.lua")

local lifecycleFactory = assert(Nexus.MainInternals.Lifecycle)
local lifecycleErrors = {}
local lifecycleOrder = {}
local syncUpdates, dpsUpdates, automationUpdates = 0, 0, 0
local combatStarts, combatEnds = 0, 0
local syncFailure = "stage36 sync update failure"
local Store = {
    Init=function() return true end,
    Settings=function() return {} end,
}
local Adapter = {
    Init=function() end,
    OnEvent=function() end,
    SetSoloPicker=function() end,
    RequestSlots=function() end,
    Ready=function() return true end,
    RivalDetected=function() return false end,
}
local Panel = {Init=function() end}
local automation = {
    Initialize=function() return true end,
    JournalData=function() return {} end,
    OnUpdate=function()
        automationUpdates = automationUpdates + 1
        lifecycleOrder[#lifecycleOrder + 1] = "automation"
    end,
    RunFullStep=function() return true end,
    ToggleAuto=function() return false end,
}
Nexus.DiagnosticLogs = {Init=function() return true end}
Nexus.Codec = {}
Nexus.Sync = {
    Init=function() end,
    OnUpdate=function()
        syncUpdates = syncUpdates + 1
        lifecycleOrder[#lifecycleOrder + 1] = "sync"
        if syncFailure then error(syncFailure) end
    end,
}
Nexus.DpsCapture = {
    Init=function() end,
    OnUpdate=function()
        dpsUpdates = dpsUpdates + 1
        lifecycleOrder[#lifecycleOrder + 1] = "dps"
        error("stage36 dps update failure")
    end,
    OnCombatStart=function()
        combatStarts = combatStarts + 1
        lifecycleOrder[#lifecycleOrder + 1] = "combat_start"
        error("stage36 combat start failure")
    end,
    OnCombatEnd=function()
        combatEnds = combatEnds + 1
        lifecycleOrder[#lifecycleOrder + 1] = "combat_end"
        error("stage36 combat end failure")
    end,
}

local lifecycle = lifecycleFactory.New({
    nexus=Nexus,
    bindDependencies=function()
        return {
            Store=Store,Adapter=Adapter,Panel=Panel,Model={},JournalTab=nil,
        }
    end,
    ensureAutomation=function() return automation end,
    print=function() end,
    recordError=function(source, value)
        lifecycleErrors[#lifecycleErrors + 1] = {
            source=tostring(source),message=tostring(value),
        }
    end,
    recordStoreError=function() end,
    errorText=tostring,
    requestRecompute=function() end,
    refreshHud=function() return true end,
    requestFirstHud=function() return true end,
    database=function() return {} end,
    now=function() return 100 end,
})

lifecycle.OnEvent("PLAYER_ENTERING_WORLD")
for _ = 1, 8 do
    lifecycle.OnEvent("PLAYER_REGEN_DISABLED")
    lifecycle.OnEvent("PLAYER_REGEN_ENABLED")
    lifecycle.OnUpdate(0.2)
end

local retainedAll = ContainsSource(lifecycleErrors, "Sync.OnUpdate")
    and ContainsSource(lifecycleErrors, "DpsCapture.OnUpdate")
    and ContainsSource(lifecycleErrors, "DpsCapture.OnCombatStart")
    and ContainsSource(lifecycleErrors, "DpsCapture.OnCombatEnd")
Check("lifecycle_error_retention", retainedAll and #lifecycleErrors == 4,
    string.format("retained=%d sync=%d dps=%d start=%d end=%d",
        #lifecycleErrors,syncUpdates,dpsUpdates,combatStarts,combatEnds))
Check("lifecycle_failure_isolation",
    syncUpdates == 8 and dpsUpdates == 8 and automationUpdates == 8
        and combatStarts == 8 and combatEnds == 8,
    string.format("sync=%d dps=%d automation=%d start=%d end=%d",
        syncUpdates,dpsUpdates,automationUpdates,combatStarts,combatEnds))
local lifecycleOrderOk = #lifecycleOrder == 40
for iteration = 1, 8 do
    local at = (iteration - 1) * 5
    lifecycleOrderOk = lifecycleOrderOk
        and lifecycleOrder[at + 1] == "combat_start"
        and lifecycleOrder[at + 2] == "combat_end"
        and lifecycleOrder[at + 3] == "sync"
        and lifecycleOrder[at + 4] == "dps"
        and lifecycleOrder[at + 5] == "automation"
end
Check("lifecycle_failure_order", lifecycleOrderOk,
    "trace=" .. table.concat(lifecycleOrder, ","))
Check("lifecycle_error_messages",
    CountMessage(lifecycleErrors, "Sync.OnUpdate",
        "stage36 sync update failure") == 1
        and CountMessage(lifecycleErrors, "DpsCapture.OnUpdate",
            "stage36 dps update failure") == 1
        and CountMessage(lifecycleErrors, "DpsCapture.OnCombatStart",
            "stage36 combat start failure") == 1
        and CountMessage(lifecycleErrors, "DpsCapture.OnCombatEnd",
            "stage36 combat end failure") == 1,
    "one or more retained source/message pairs drifted")

-- A changed message is a new bounded incident. A successful call clears the
-- source latch, so a later recurrence is retained once again.
syncFailure = "stage36 changed sync failure"
lifecycle.OnUpdate(0.2)
lifecycle.OnUpdate(0.2)
syncFailure = nil
lifecycle.OnUpdate(0.2)
syncFailure = "stage36 changed sync failure"
lifecycle.OnUpdate(0.2)
Check("lifecycle_error_episode_reset",
    CountSource(lifecycleErrors, "Sync.OnUpdate") == 3
        and CountMessage(lifecycleErrors, "Sync.OnUpdate",
            "stage36 changed sync failure") == 2
        and #lifecycleErrors == 6,
    string.format("sync_retained=%d total=%d",
        CountSource(lifecycleErrors, "Sync.OnUpdate"),#lifecycleErrors))

------------------------------------------------------------------------
-- Real Main + GameAdapter + AutomationRuntime: a run may pass through level 1
-- entirely between two 0.2-second pumps. The existing authoritative reset must
-- still execute exactly once, without submitting an action.
------------------------------------------------------------------------
Nexus = {}
local fixture = assert(dofile("tests/run_main_contract_characterization.lua"))
local H = assert(fixture.harness)
local RealAdapter = assert(fixture.adapter)

-- The characterization leaves Auto enabled. Keep this boundary fixture
-- passive, then establish an observed level-80 end-of-run state.
SlashCmdList["NEXUS"]("auto")
H.playerLevel = 80
H.FireEvent("PLAYER_LEVEL_UP", 80)
H.Advance(0.21, 0.21)

local runBefore = tonumber(NexusDB.auditRunCounter) or 0
local ownedBefore = tonumber(RealAdapter.Owned().generation) or 0
local mutationsBefore = fixture.mutationSnapshot()

-- Level 1 exists but is never pumped. Only level-up notifications for the
-- rapidly advancing new run reach Main before the next direct cadence.
H.playerLevel = 1
for level = 2, 60 do
    H.playerLevel = level
    H.FireEvent("PLAYER_LEVEL_UP", level)
end
H.Advance(0.21, 0.21)

local runAfter = tonumber(NexusDB.auditRunCounter) or 0
local ownedAfter = tonumber(RealAdapter.Owned().generation) or 0
local mutationsAfter = fixture.mutationSnapshot()
Check("coalesced_run_boundary",
    runAfter == runBefore + 1 and ownedAfter == ownedBefore + 1,
    string.format("audit=%d->%d owned_generation=%d->%d",
        runBefore,runAfter,ownedBefore,ownedAfter))
Check("coalesced_run_boundary_no_mutation",
    mutationsAfter == mutationsBefore,
    "mutations=" .. tostring(mutationsBefore) .. "->" .. tostring(mutationsAfter))

-- Duplicate/out-of-order notification arguments at the same live level must
-- not manufacture another boundary.
H.FireEvent("PLAYER_LEVEL_UP", 59)
H.FireEvent("PLAYER_LEVEL_UP", 60)
H.Advance(0.21, 0.21)
Check("coalesced_run_boundary_exactly_once",
    (tonumber(NexusDB.auditRunCounter) or 0) == runAfter,
    string.format("after_boundary=%d after_duplicates=%d",
        runAfter,tonumber(NexusDB.auditRunCounter) or 0))

-- A stale event argument cannot manufacture a boundary while the live player
-- remains at 80. A later poll-only live decrease must detect one boundary.
H.playerLevel = 80
H.FireEvent("PLAYER_LEVEL_UP", 80)
H.Advance(0.21, 0.21)
local directBefore = tonumber(NexusDB.auditRunCounter) or 0
local directOwnedBefore = tonumber(RealAdapter.Owned().generation) or 0
H.FireEvent("PLAYER_LEVEL_UP", 1)
H.Advance(0.21, 0.21)
Check("stale_level_event_no_boundary",
    (tonumber(NexusDB.auditRunCounter) or 0) == directBefore,
    string.format("before=%d after=%d", directBefore,
        tonumber(NexusDB.auditRunCounter) or 0))

H.playerLevel = 42
H.Advance(0.21, 0.21)
local directAfter = tonumber(NexusDB.auditRunCounter) or 0
local directOwnedAfter = tonumber(RealAdapter.Owned().generation) or 0
Check("direct_level_drop_boundary",
    directAfter == directBefore + 1
        and directOwnedAfter == directOwnedBefore + 1,
    string.format("audit=%d->%d owned=%d->%d",
        directBefore,directAfter,directOwnedBefore,directOwnedAfter))

-- Repeated world-entry and out-of-order notifications at the already-lower
-- live level remain disarmed and cannot reset the same run again.
H.FireEvent("PLAYER_ENTERING_WORLD")
H.FireEvent("PLAYER_LEVEL_UP", 80)
H.FireEvent("PLAYER_LEVEL_UP", 2)
H.Advance(0.21, 0.21)
Check("lower_world_entry_no_second_boundary",
    (tonumber(NexusDB.auditRunCounter) or 0) == directAfter,
    string.format("boundary=%d after_world_entry=%d", directAfter,
        tonumber(NexusDB.auditRunCounter) or 0))

-- Literal 80 -> unseen 1 -> first observed 60 remains one boundary even when
-- no intermediate level notification reaches the addon.
H.playerLevel = 80
H.FireEvent("PLAYER_LEVEL_UP", 80)
H.Advance(0.21, 0.21)
local unseenBefore = tonumber(NexusDB.auditRunCounter) or 0
H.playerLevel = 1
H.playerLevel = 60
H.FireEvent("PLAYER_LEVEL_UP", 60)
H.Advance(0.21, 0.21)
local unseenAfter = tonumber(NexusDB.auditRunCounter) or 0
Check("unseen_level_one_direct_sixty",
    unseenAfter == unseenBefore + 1,
    string.format("audit=%d->%d", unseenBefore,unseenAfter))

local idleStepsBefore = Nexus.RecomputeStats().fullSteps
H.Advance(0.21, 0.21)
Check("run_boundary_idle_settled",
    (tonumber(NexusDB.auditRunCounter) or 0) == unseenAfter
        and Nexus.RecomputeStats().fullSteps == idleStepsBefore,
    string.format("audit=%d->%d full=%d->%d",
        unseenAfter,tonumber(NexusDB.auditRunCounter) or 0,
        idleStepsBefore,Nexus.RecomputeStats().fullSteps))

-- Recreate the real adapter at a lower level, as a reload/login would. Its
-- fresh scalar detector is unarmed, so PEW and Poll cannot manufacture a run.
local reloadAuditBefore = tonumber(NexusDB.auditRunCounter) or 0
H.playerLevel = 42
dofile("core/GameAdapter.lua")
local ReloadedAdapter = assert(Nexus.GameAdapter)
ReloadedAdapter.Init({}, Nexus.Store)
ReloadedAdapter.OnEvent("PLAYER_ENTERING_WORLD")
ReloadedAdapter.Poll()
local reloadDirty = {ReloadedAdapter.ConsumeDirty()}
local reloadBurst = ReloadedAdapter.LevelBurstStats()
Check("real_adapter_lower_reload_no_boundary",
    reloadDirty[15] == 0
        and reloadBurst.runBoundaryGeneration == 0
        and reloadBurst.runBoundaryArmed == false
        and (tonumber(NexusDB.auditRunCounter) or 0) == reloadAuditBefore,
    string.format("generation=%s armed=%s audit=%d->%d",
        tostring(reloadDirty[15]),tostring(reloadBurst.runBoundaryArmed),
        reloadAuditBefore,tonumber(NexusDB.auditRunCounter) or 0))

------------------------------------------------------------------------
-- Real AutomationRuntime: dirty work is consumed before Step. A failed Step
-- must not count as complete and receives one, and only one, cadence retry.
------------------------------------------------------------------------
Nexus = {MainInternals={}}
dofile("logic/Model.lua")
dofile("core/WishlistModel.lua")
dofile("core/AutomationRuntime.lua")
local runtimeFactory = assert(Nexus.MainInternals.AutomationRuntime)

local function NewPassiveBoundaryRuntime(initialLevel)
    local now, level, resets = 150, initialLevel, 0
    local dirty = true
    local adapter = {
        Poll=function() end,
        ConsumeDirty=function()
            local current = dirty
            dirty = false
            return current,false,false,nil,0,0,0,0,0,0,0,0,false,0,0
        end,
        AutomationSignature=function()
            return {
                service=true,level=level,slots=0,activeSlot=0,granted=0,
                locked=0,discovery=0,tomeSafety=false,state=true,
                settings=true,associations=true,association=false,
                firstRun=false,
            }
        end,
        Level=function() return level end,
        ExternalActionSeen=function() return false end,
        Catalog=function() return nil end,
        RunBoundaryReset=function() resets = resets + 1 end,
    }
    local runtime = runtimeFactory.New({
        nexus=Nexus,model={},policy={},ratchet={},strategy={},store={},
        adapter=adapter,readout={},defaultProfile={},viewModel={},
        wishlistModel=Nexus.WishlistModel.New(),
        renderPanel=function() end,renderIdlePanel=function() end,
        buildProgress=function() end,buildPanelProgress=function() end,
        appendAudit=function() end,appendAutoLockEvent=function() end,
        print=function() end,recordError=function() end,
        now=function() return now end,
    })
    runtime.Initialize()
    return {
        runtime=runtime,
        advance=function(delta) now = now + delta; runtime.OnUpdate(delta) end,
        setLevel=function(value)
            level, dirty = value, true
            runtime.RequestRecompute()
        end,
        resets=function() return resets end,
    }
end

-- Initial level 1 and ordinary lower-level progress start from already-clean
-- state. Recreating the runtime at a lower level models reload/login and must
-- not increment the durable run identity a second time.
NexusDB = {auditRunCounter=11}
local ordinary = NewPassiveBoundaryRuntime(1)
ordinary.advance(0.2)
ordinary.setLevel(60)
ordinary.advance(0.2)
local reloaded = NewPassiveBoundaryRuntime(60)
reloaded.advance(0.2)
Check("ordinary_leveling_and_reload_no_boundary",
    ordinary.resets() == 0 and reloaded.resets() == 0
        and (tonumber(NexusDB.auditRunCounter) or 0) == 11,
    string.format("ordinary=%d reload=%d audit=%d",
        ordinary.resets(),reloaded.resets(),
        tonumber(NexusDB.auditRunCounter) or 0))

local function NewDeadlineRetryRuntime()
    local now, failRender = 300, false
    local catalogCalls, idleRenders = 0, 0
    local errors = {}
    local adapter = {
        Poll=function() end,
        ConsumeDirty=function()
            return false,false,false,nil,0,0,0,0,0,0,0,0,false,0,0
        end,
        AutomationSignature=function()
            return {
                service=true,level=5,slots=0,activeSlot=0,granted=0,
                locked=0,discovery=0,tomeSafety=false,state=true,
                settings=true,associations=true,association=false,
                firstRun=false,
            }
        end,
        Level=function() return 5 end,
        ExternalActionSeen=function() return false end,
        Catalog=function()
            catalogCalls = catalogCalls + 1
            return nil
        end,
        RunBoundaryReset=function() end,
    }
    local runtime = runtimeFactory.New({
        nexus=Nexus,model={},policy={},ratchet={},strategy={},store={},
        adapter=adapter,readout={},defaultProfile={},viewModel={},
        wishlistModel=Nexus.WishlistModel.New(),
        renderPanel=function() end,
        renderIdlePanel=function()
            if failRender then error("stage36 deadline render failure") end
            idleRenders = idleRenders + 1
        end,
        buildProgress=function() end,buildPanelProgress=function() end,
        appendAudit=function() end,appendAutoLockEvent=function() end,
        print=function() end,
        recordError=function(source, value)
            errors[#errors + 1] = tostring(source) .. ":" .. tostring(value)
        end,
        now=function() return now end,
    })
    runtime.Initialize()
    return {
        runtime=runtime,
        advance=function(delta) now = now + delta; runtime.OnUpdate(delta) end,
        schedule=function(delta) return runtime.RequestStepAt(now + delta) end,
        setFailure=function(value) failRender = value and true or false end,
        catalogCalls=function() return catalogCalls end,
        idleRenders=function() return idleRenders end,
        errors=errors,
    }
end

local deadline = NewDeadlineRetryRuntime()
deadline.advance(0.2) -- settle the constructor's forced step
local deadlineBaseline = deadline.runtime.RecomputeStats()
Check("deadline_fixture_settled",
    deadlineBaseline.fullSteps == 1
        and deadlineBaseline.stepAttempts == 1
        and deadline.schedule(0.2),
    "deadline fixture did not settle or schedule")
deadline.setFailure(true)
deadline.advance(0.19)
local deadlineEarly = deadline.runtime.RecomputeStats()
deadline.advance(0.02)
local deadlineFailed = deadline.runtime.RecomputeStats()
deadline.setFailure(false)
deadline.advance(0.19)
local retryEarly = deadline.runtime.RecomputeStats()
deadline.advance(0.02)
local deadlineRecovered = deadline.runtime.RecomputeStats()
Check("deadline_retry_next_cadence",
    deadlineEarly.stepAttempts == 1
        and deadlineFailed.stepAttempts == 2
        and deadlineFailed.stepFailures == 1
        and deadlineFailed.fullSteps == 1
        and deadlineFailed.nextStepAt == nil
        and deadlineFailed.stepRetryPending == true
        and retryEarly.stepAttempts == 2
        and retryEarly.stepRetryPending == true
        and deadlineRecovered.stepAttempts == 3
        and deadlineRecovered.stepFailures == 1
        and deadlineRecovered.stepRetries == 1
        and deadlineRecovered.stepRetryExhausted == 0
        and deadlineRecovered.stepRetryPending == false
        and deadlineRecovered.fullSteps == 2
        and deadlineRecovered.fullStepTriggers.deadlines == 1
        and deadline.catalogCalls() == 3
        and deadline.idleRenders() == 2
        and #deadline.errors == 1,
    string.format(
        "attempts=%d/%d/%d/%d full=%d failures=%d retries=%d pending=%s catalogs=%d renders=%d errors=%d",
        deadlineEarly.stepAttempts,deadlineFailed.stepAttempts,
        retryEarly.stepAttempts,deadlineRecovered.stepAttempts,
        deadlineRecovered.fullSteps,deadlineRecovered.stepFailures,
        deadlineRecovered.stepRetries,
        tostring(deadlineRecovered.stepRetryPending),
        deadline.catalogCalls(),deadline.idleRenders(),#deadline.errors))

local function NewFailingRuntime(alwaysFail, freshDirty)
    local now, catalogCalls, consumeCalls = 200, 0, 0
    local errors = {}
    local burstPumps = {}
    local adapter = {
        Poll=function() end,
        ConsumeDirty=function()
            consumeCalls = consumeCalls + 1
            return consumeCalls == 1, false,
                freshDirty and consumeCalls == 2, false,
                0,0,0,0,0,0,0,0,false,
                consumeCalls == 1 and 5 or 0,0
        end,
        AutomationSignature=function()
            return {
                service=true,level=5,slots=0,activeSlot=0,granted=0,
                locked=0,discovery=0,tomeSafety=false,state=true,
                settings=true,associations=true,association=false,
                firstRun=false,
            }
        end,
        Level=function() return 5 end,
        Catalog=function()
            catalogCalls = catalogCalls + 1
            if alwaysFail or catalogCalls == 1 then
                error("stage36 full-step failure")
            end
            return nil
        end,
        ExternalActionSeen=function() return false end,
        RunBoundaryReset=function() end,
        RecordLevelBurstPump=function(events, recomputes, renders, actions)
            if (tonumber(events) or 0) <= 0 then return false end
            burstPumps[#burstPumps + 1] = {
                events=events,recomputes=recomputes,
                renders=renders,actions=actions,
            }
            return true
        end,
    }
    local runtime = runtimeFactory.New({
        nexus=Nexus,model={},policy={},ratchet={},strategy={},store={},
        adapter=adapter,readout={},defaultProfile={},viewModel={},
        wishlistModel=Nexus.WishlistModel.New(),
        renderPanel=function() end,renderIdlePanel=function() end,
        buildProgress=function() end,buildPanelProgress=function() end,
        appendAudit=function() end,appendAutoLockEvent=function() end,
        print=function() end,
        recordError=function(source, value)
            errors[#errors + 1] = tostring(source) .. ":" .. tostring(value)
        end,
        now=function() return now end,
    })
    NexusDB = {}
    runtime.Initialize()
    return {
        runtime=runtime,
        advance=function(delta) now = now + delta; runtime.OnUpdate(delta) end,
        catalogCalls=function() return catalogCalls end,
        consumeCalls=function() return consumeCalls end,
        errors=errors,
        burstPumps=burstPumps,
    }
end

local transient = NewFailingRuntime(false, true)
transient.advance(0.2)
local transientFailed = transient.runtime.RecomputeStats()
transient.advance(0.2)
local transientRetried = transient.runtime.RecomputeStats()

local repeated = NewFailingRuntime(true)
repeated.advance(0.2)
for _ = 1, 30 do repeated.advance(0.2) end
local repeatedFinal = repeated.runtime.RecomputeStats()

Check("failed_step_retry_truthfulness",
    transientFailed.fullSteps == 0
        and transientFailed.stepAttempts == 1
        and transientFailed.stepFailures == 1
        and transientFailed.stepRetries == 0
        and transientFailed.stepRetryPending == true
        and transientRetried.fullSteps == 1
        and transientRetried.stepAttempts == 2
        and transientRetried.stepFailures == 1
        and transientRetried.stepRetries == 1
        and transientRetried.stepRetryPending == false
        and transientRetried.lastStepContext.dirtyMask == 5
        and transientRetried.fullStepTriggers.dirty == 1
        and #transient.burstPumps == 2
        and transient.burstPumps[1].events == 5
        and transient.burstPumps[1].recomputes == 0
        and transient.burstPumps[2].events == 5
        and transient.burstPumps[2].recomputes == 1
        and transient.catalogCalls() == 2
        and #transient.errors == 1
        and repeatedFinal.fullSteps == 0
        and repeatedFinal.stepAttempts == 2
        and repeatedFinal.stepFailures == 2
        and repeatedFinal.stepRetries == 1
        and repeatedFinal.stepRetryExhausted == 1
        and repeatedFinal.stepRetryPending == false
        and repeated.catalogCalls() == 2
        and #repeated.burstPumps == 2
        and repeated.burstPumps[1].recomputes == 0
        and repeated.burstPumps[2].recomputes == 0
        and #repeated.errors == 2,
    string.format(
        "transient full=%d->%d attempts=%d retries=%d pending=%s catalog_calls=%d errors=%d; repeated full=%d attempts=%d failures=%d retries=%d exhausted=%d pending=%s catalog_calls=%d errors=%d",
        transientFailed.fullSteps,transientRetried.fullSteps,
        transientRetried.stepAttempts,transientRetried.stepRetries,
        tostring(transientRetried.stepRetryPending),
        transient.catalogCalls(),#transient.errors,repeatedFinal.fullSteps,
        repeatedFinal.stepAttempts,repeatedFinal.stepFailures,
        repeatedFinal.stepRetries,repeatedFinal.stepRetryExhausted,
        tostring(repeatedFinal.stepRetryPending),
        repeated.catalogCalls(),#repeated.errors))

if #failures > 0 then
    error("EXPECTED RED [Stage 36.1 lifecycle safety]:\n - "
        .. table.concat(failures, "\n - "), 0)
end

print("Stage 36.1 run boundary, lifecycle retention, and bounded step retry -- OK")
