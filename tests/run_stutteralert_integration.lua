-- Bounded operation retention and optional StutterAlert integration stay
-- deterministic, session-only, load-order safe, and failure isolated.
local H = dofile("tests/harness.lua")
local Performance = assert(Nexus.Performance)
local Integration = assert(Nexus.StutterAlertIntegration)

NexusDB = {sentinel=true}
Performance.Reset()
Performance.SetEnabled(true)

local function Record(name, startedMs, finishedMs, endedAt, fields)
    local ticks = {startedMs, finishedMs}
    assert(Performance.SetClock(function() return table.remove(ticks, 1) end))
    H.now = endedAt
    local startedAt = Performance.Begin(name)
    assert(Performance.Finish(name, startedAt, fields))
end

-- Correlation, defensive copying, deterministic newest-first order, capacity,
-- age pruning, and controlled scalar fields.
Record("automation.step", 0, 2, 100, {outcome="one", packet="forbidden"})
Record("automation.step", 10, 12, 100, {outcome="two"})
Record("automation.step", 20, 22, 100, {outcome="three"})
local sameTime = Performance.RecentOperations(99, 101, 100)
assert(#sameTime==3
    and sameTime[1].fields[1].value=="three"
    and sameTime[2].fields[1].value=="two"
    and sameTime[3].fields[1].value=="one",
    "equal-time operation order is not deterministic newest-first")
sameTime[1].fields[1].value = "mutated"
assert(Performance.RecentOperations(99, 101, 100)[1].fields[1].value=="three",
    "recent operation read leaked mutable retained fields")

Performance.Reset()
for index = 1, 40 do
    Record("automation.step", index * 10, index * 10 + 2,
        200 + index / 100, {outcome=tostring(index)})
end
local limits = Performance.OperationLimits()
local capped = Performance.RecentOperations(190, 210, H.now)
assert(limits.capacity==32 and limits.maxAgeSeconds==15
    and limits.minimumDurationMs==1 and limits.maxFields==4
    and limits.slowStepMinimumMs==16
    and #capped==32 and capped[1].fields[1].value=="40"
    and capped[#capped].fields[1].value=="9",
    "operation ring capacity or retained order changed")

Performance.Reset()
Record("automation.step", 0, 2, 300, {outcome="outside"})
Record("sync.update", 10, 12, 302, {mode="inside"})
local correlated = Performance.RecentOperations(301.5, 302.1, 302.1)
assert(#correlated==1 and correlated[1].name=="sync.update",
    "correlation window returned an unrelated operation")
H.now = 318
assert(#Performance.RecentOperations(0, 400, H.now)==0,
    "age pruning retained a stale operation")

-- Disabled and ordinary sub-millisecond paths preserve the cheap bypass and
-- do not allocate retained operations.
Performance.Reset()
local clockCalls = 0
assert(Performance.SetClock(function()
    clockCalls = clockCalls + 1
    return clockCalls * 0.25
end))
for index = 1, 100 do
    assert(Performance.Measure("lifecycle.update", function() return index end)==index)
end
assert(#Performance.RecentOperations(0, 1000, H.now)==0,
    "ordinary sub-millisecond operations entered the retained ring")
Performance.SetEnabled(false)
local callsBeforeDisabled = clockCalls
assert(Performance.Measure("lifecycle.update", function() return "disabled" end)
        == "disabled" and clockCalls==callsBeforeDisabled,
    "disabled performance path touched the clock")
Performance.SetEnabled(true)

-- A completed slow Step retains one fixed-shape sanitized receipt and annotates
-- its outer operation with the dominant aggregate-only inner phase. No phase
-- samples enter the bounded recent-operation ring.
Performance.Reset()
local nestedTicks = {0, 10, 594.391, 606.582}
assert(Performance.SetClock(function() return table.remove(nestedTicks, 1) end))
H.now = 350
assert(Performance.Measure("automation.step", function()
    return Performance.Measure("automation.phase.overlay-prepare",
        function() return "nested-ok" end)
end) == "nested-ok")
local slow = Performance.LastSlowStep()
assert(slow.present and math.abs(slow.durationMs - 606.582) < 0.0001
    and slow.dominantPhase == "automation.phase.overlay-prepare"
    and math.abs(slow.dominantPhaseMs - 584.391) < 0.0001
    and slow.endTime == 350 and slow.retainedScalarFields == 5,
    "slow-step receipt lost its bounded dominant-phase attribution")
slow.dominantPhase = "mutated"
assert(Performance.LastSlowStep().dominantPhase
        == "automation.phase.overlay-prepare",
    "slow-step receipt leaked mutable retained state")
local nestedOperations = Performance.RecentOperations(349, 351, 350)
assert(#nestedOperations == 1
    and nestedOperations[1].name == "automation.step",
    "aggregate-only inner phase displaced the outer Step breadcrumb")
local nestedFields = {}
for _, field in ipairs(nestedOperations[1].fields or {}) do
    nestedFields[field.key] = field.value
end
assert(nestedFields.mode == "automation.phase.overlay-prepare"
    and math.abs(nestedFields.outcome - 584.391) < 0.0001,
    "outer Step breadcrumb did not retain the dominant bounded phase")
assert(Performance.Reset("automation.step")
    and Performance.LastSlowStep().present == false,
    "named automation.step reset retained a stale slow-step receipt")

-- Optional API absence/version mismatch, late arrival, idempotence, explicit
-- unregistration, and registration failure isolation.
_G.StutterAlert = nil
assert(Integration.Register()==false and not Integration.IsRegistered(),
    "absent StutterAlert did not remain optional")
local wrongCalls = 0
_G.StutterAlert = {
    DIAGNOSTIC_PROVIDER_API=2,
    RegisterDiagnosticProvider=function() wrongCalls=wrongCalls+1; return true end,
}
assert(Integration.Register()==false and wrongCalls==0,
    "unsupported provider API was invoked")

local registeredProvider, registerCalls, unregisterCalls = nil, 0, 0
local captures = {}
local function SanitizeResult(result)
    if type(result) ~= "table" then return nil, "malformed" end
    local summary = type(result.summary) == "string"
        and result.summary ~= "" and result.summary or nil
    if result.summary ~= nil and not summary then return nil, "malformed" end
    if result.operations ~= nil and type(result.operations) ~= "table" then
        return nil, "malformed"
    end
    local operations = {}
    for index = 1, math.min(5,
        type(result.operations) == "table" and #result.operations or 0) do
        local operation = result.operations[index]
        if type(operation) ~= "table" or type(operation.name) ~= "string"
            or type(operation.durationMs) ~= "number" then
            return nil, "malformed"
        end
        operations[#operations + 1] = operation
    end
    if not summary and #operations == 0 then return nil, "empty" end
    return {summary=summary,operations=operations,status="ok"}
end
local api = {
    DIAGNOSTIC_PROVIDER_API=1,
    RegisterDiagnosticProvider=function(addonName, provider)
        assert(addonName=="Nexus" and type(provider)=="function")
        registerCalls = registerCalls + 1
        registeredProvider = provider
        return true
    end,
    UnregisterDiagnosticProvider=function(addonName)
        assert(addonName=="Nexus")
        unregisterCalls = unregisterCalls + 1
        return true
    end,
    CaptureForHitch=function(addonName, context)
        local ok, result = pcall(registeredProvider, context)
        if not ok then
            captures[addonName] = {status="error"}
            return false, "error"
        end
        local sanitized, reason = SanitizeResult(result)
        if not sanitized then
            captures[addonName] = {status=reason}
            return false, reason
        end
        captures[addonName] = sanitized
        return true
    end,
}
_G.StutterAlert = api
assert(Integration.Register() and Integration.Register()
    and registerCalls==1 and Integration.IsRegistered(),
    "registration was not late-load safe and idempotent")

Performance.Reset()
Record("automation.fallback.repair", 100, 602.7, 400, {
    trigger="fallback", mismatch="slots", packet="not retained",
})
local context = {
    addonName="Nexus",
    hitchStartTime=399.4,
    hitchEndTime=400.1,
    profilingTimestamp=400.1,
    profileWindowMs=700,
    frameDurationMs=600,
    addonCpuDeltaMs=550,
    totalAddonCpuDeltaMs=570,
    addonShare=0.91,
    attributionConfidence=0.91,
    attributionMode="sampled",
}
local accepted = api.CaptureForHitch("Nexus", context)
local capture = captures.Nexus
assert(accepted and capture.status=="ok",
    "StutterAlert-compatible capture rejected the correlated provider result")
assert(type(capture)=="table"
    and capture.summary=="A recent Nexus automation repair overlaps the attributed hitch."
    and #capture.operations==1
    and capture.operations[1].name=="automation.fallback.repair"
    and math.abs(capture.operations[1].durationMs - 502.7) < 0.0001,
    "provider did not return the bounded correlated repair")
local fields = {}
for _, field in ipairs(capture.operations[1].fields or {}) do
    fields[field.key] = field.value
end
assert(fields.trigger=="fallback" and fields.mismatch=="slots"
    and fields.packet==nil and #capture.operations[1].fields==2,
    "provider fields were not controlled and bounded")
local emptyOK, emptyReason = api.CaptureForHitch("Nexus", {
    addonName="Nexus",hitchStartTime=410,hitchEndTime=411,
    profilingTimestamp=411,profileWindowMs=100})
assert(emptyOK==false and emptyReason=="empty"
    and captures.Nexus.status=="empty",
    "provider no-match output was malformed instead of valid empty")

for index = 1, 8 do
    Record("automation.step", index, index + 2, 400, {outcome=tostring(index)})
end
local bounded = registeredProvider(context)
assert(#bounded.operations==5 and #bounded.summary<240,
    "provider exceeded its operation or summary limits")
local estimatedBytes = #bounded.summary
for _, operation in ipairs(bounded.operations) do
    assert(#operation.name<80 and #operation.fields<=4)
    estimatedBytes = estimatedBytes + #operation.name + 24
    for _, field in ipairs(operation.fields) do
        assert(#field.key<24 and #tostring(field.value)<64)
        estimatedBytes = estimatedBytes + #field.key + #tostring(field.value)
    end
end
assert(estimatedBytes<1024, "provider output exceeded the capture budget")

local realRecent = Performance.RecentOperations
Performance.RecentOperations = function() error("simulated provider read failure") end
local failedOK, failedReason = api.CaptureForHitch("Nexus", context)
assert(failedOK==false and failedReason=="empty"
    and captures.Nexus.status=="empty",
    "provider read failure escaped or became malformed in StutterAlert")
Performance.RecentOperations = function()
    return {false,{name=false,durationMs="bad"},
        {name="community.show",durationMs=0/0}}
end
local malformedOK, malformedReason = api.CaptureForHitch("Nexus", context)
assert(malformedOK==false and malformedReason=="empty"
    and captures.Nexus.status=="empty",
    "malformed internal operations escaped or became malformed provider output")
Performance.RecentOperations = realRecent

assert(Integration.Unregister() and unregisterCalls==1
    and not Integration.IsRegistered() and Integration.Unregister()==false,
    "explicit provider unregistration was not idempotent")
_G.StutterAlert = {
    DIAGNOSTIC_PROVIDER_API=1,
    RegisterDiagnosticProvider=function() error("simulated registration failure") end,
    UnregisterDiagnosticProvider=function() return true end,
}
local okFailure, registered = pcall(Integration.Register)
assert(okFailure and registered==false and not Integration.IsRegistered(),
    "registration failure escaped into Nexus")

assert(NexusDB.sentinel==true and NexusDB.performance==nil
    and NexusDB.recentOperations==nil and NexusDB.stutterAlert==nil,
    "session-only diagnostics changed SavedVariables")

print("StutterAlert provider registration, bounded correlation, limits, failures, and session-only storage -- OK")
