-- AutomationRuntime is the sole stateful FSM owner. This fixture locks the
-- extracted constructor boundary, deadline/cadence bookkeeping, failure
-- containment, and Main's lack of a second gameplay-mutation path. The real
-- decision/action trace remains covered by run_main_contract_characterization,
-- run_main_refusal_recovery, and the 70-check integration suite.
Nexus = {}
dofile("core/Performance.lua")
dofile("core/Revisions.lua")
dofile("core/AutomationRuntime.lua")

local factory = Nexus.MainInternals and Nexus.MainInternals.AutomationRuntime
assert(factory and type(factory.New) == "function",
    "AutomationRuntime internal constructor is unavailable")
assert(not pcall(factory.New, {}),
    "AutomationRuntime accepted a missing dependency graph")

local now, polls = 100, 0
local performanceClock = 0
Nexus.Performance.SetClock(function()
    performanceClock = performanceClock + 1
    return performanceClock
end)
Nexus.Performance.Reset()
local statuses, errors = {}, {}
local function NewRuntime(overrides)
    local options = {
        nexus=Nexus,
        model={}, policy={}, ratchet={}, strategy={}, store={}, adapter={},
        readout={}, defaultProfile={}, viewModel={},
        renderPanel=function() end,
        renderIdlePanel=function() end,
        buildProgress=function() end,
        buildPanelProgress=function() end,
        appendAudit=function() end,
        appendAutoLockEvent=function() end,
        print=function() end,
        recordError=function() end,
        now=function() return now end,
    }
    for key, value in pairs(overrides or {}) do options[key] = value end
    return factory.New(options)
end
local adapter = {
    Poll=function()
        polls = polls + 1
        error("poll fixture failure")
    end,
}
local runtime = NewRuntime({
    adapter=adapter,
    recordError=function(source, message)
        errors[#errors + 1] = {source=source,message=tostring(message)}
    end,
    onStatus=function(value)
        statuses[#statuses + 1] = value
        error("status fixture failure")
    end,
})

NexusDB = {auditRunCounter=7}
assert(runtime.Initialize() and runtime.AuditRunId()==7,
    "runtime initialization lost the durable audit run id")
assert(runtime.StatusLine()=="loading" and runtime.AutoEnabled()==false,
    "runtime initial status/automation state changed")

assert(runtime.RequestStepAt(102)
    and runtime.RequestStepAt(101)
    and runtime.RequestStepAt(103),
    "valid runtime deadlines were rejected")
local deadlineStats = runtime.RecomputeStats()
assert(deadlineStats.nextStepAt==101 and deadlineStats.fallbackSeconds==5,
    "runtime stopped retaining the earliest deadline/fallback cadence")
for _, invalid in ipairs({"bad", 0/0, math.huge, -math.huge}) do
    assert(runtime.RequestStepAt(invalid)==false,
        "invalid runtime deadline was accepted")
end
assert(runtime.RecomputeStats().nextStepAt==101,
    "invalid deadline changed retained scheduling state")

deadlineStats.polls = -1
deadlineStats.nextStepAt = -1
local defensive = runtime.RecomputeStats()
assert(defensive.polls==0 and defensive.nextStepAt==101,
    "runtime recompute stats stopped returning a defensive snapshot")

runtime.OnUpdate(0.19)
assert(polls==0 and #statuses==0 and #errors==0,
    "sub-cadence update entered the direct safety poll")
local pollContained = pcall(runtime.OnUpdate,0.02)
assert(pollContained and polls==1 and statuses[1]=="error (see /nexus err)"
    and errors[1] and errors[1].source=="GameAdapter.Poll"
    and errors[1].message:find("poll fixture failure",1,true),
    "direct poll failure escaped containment or changed attribution")
local afterPoll = runtime.RecomputeStats()
assert(afterPoll.polls==1 and afterPoll.pollFailures==1
    and afterPoll.fullSteps==0
    and Nexus.Performance.Stats("gameadapter.poll").count==1
    and Nexus.Performance.Stats("automation.update").count==2,
    "failed direct poll entered policy/FSM work")

assert(runtime.ToggleAuto()==true and runtime.ToggleAuto()==false
    and polls==1,
    "runtime master switch changed adapter state outside a safety tick")

local ordinaryCallbackCalls, ordinaryErrors = 0, {}
local ordinary = NewRuntime({
    adapter={
        Poll=function() end,
        ConsumeDirty=function() return true, false, false end,
        Level=function() return 5 end,
        ExternalActionSeen=function() return false end,
        Catalog=function() return nil end,
    },
    onStatus=function()
        ordinaryCallbackCalls = ordinaryCallbackCalls + 1
        error("ordinary status fixture failure")
    end,
    recordError=function(source, message)
        ordinaryErrors[#ordinaryErrors + 1] = {source=source,message=message}
    end,
})
NexusDB = {}
ordinary.Initialize()
assert(pcall(ordinary.OnUpdate,0.2)
    and ordinaryCallbackCalls==1
    and ordinary.StatusLine()=="waiting for ProjectEbonhold"
    and ordinary.RecomputeStats().fullSteps==1
    and #ordinaryErrors==0,
    "ordinary status callback failure aborted or misattributed the FSM step")

-- A catalog revision published synchronously from Catalog() belongs to the
-- static probe already in progress. It must not force a duplicate next-tick
-- rebuild after that same probe consumed the newly published catalog state.
local reentrantCatalogCalls = 0
local reentrant = NewRuntime({
    adapter={
        Poll=function() end,
        ConsumeDirty=function() return false, false, false end,
        Level=function() return 5 end,
        ExternalActionSeen=function() return false end,
        Catalog=function()
            reentrantCatalogCalls = reentrantCatalogCalls + 1
            if reentrantCatalogCalls == 1 then
                Nexus.Revisions.Advance(Nexus.Revisions.CATALOG_CHANGED,
                    "reentrant fixture")
            end
            return nil
        end,
    },
})
reentrant.Initialize()
assert(reentrant.OnUpdate(0.2)==nil)
local reentrantFirst = reentrant.RecomputeStats()
assert(reentrant.OnUpdate(0.2)==nil)
local reentrantSecond = reentrant.RecomputeStats()
assert(reentrantCatalogCalls==1 and reentrantFirst.fullSteps==1
    and reentrantSecond.fullSteps==1,
    "reentrant catalog revision scheduled a duplicate static probe")

local function Read(path)
    local file = assert(io.open(path,"r"))
    local value = file:read("*a")
    file:close()
    return value
end

local main = Read("core/Main.lua")
local runtimeSource = Read("core/AutomationRuntime.lua")
for _, pattern in ipairs({
    "local autoEnabled", "local pollAccum", "local nextStepAt",
    "local armAttempts", "local lastDecidedSig", "local savedThisVisit",
    "local function StepArm", "local function StepRun", "local function StepSave",
    "Adapter.Activate(", "Adapter.Select(", "Adapter.Banish(",
    "Adapter.Reroll(", "Adapter.Freeze(", "Adapter.Save(",
    "Adapter.ToggleLever(",
}) do
    assert(not main:find(pattern,1,true),
        "Main retained a second automation owner: " .. pattern)
end
for _, pattern in ipairs({
    "local autoEnabled", "local pollAccum", "local nextStepAt",
    "local function StepArm", "local function StepRun", "local function StepSave",
    "Adapter.Banish(", "Adapter.Reroll(", "Adapter.Freeze(",
    "Adapter.Save(", "Adapter.ToggleLever(",
}) do
    assert(runtimeSource:find(pattern,1,true),
        "AutomationRuntime lost extracted ownership: " .. pattern)
end
for _, forbidden in ipairs({"ProjectEbonhold.", "_G.ProjectEbonhold",
    "SendAddonMessage", "CreateFrame"}) do
    assert(not runtimeSource:find(forbidden,1,true),
        "AutomationRuntime bypassed an injected authority: " .. forbidden)
end

local toc = Read("Nexus.toc")
local runtimeAt = assert(toc:find("core\\AutomationRuntime.lua",1,true))
local mainAt = assert(toc:find("core\\Main.lua",1,true))
assert(runtimeAt < mainAt, "AutomationRuntime no longer loads before Main")

print("automation runtime ownership, deadlines, cadence, and failure containment -- OK")
