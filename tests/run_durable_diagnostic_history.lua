-- Durable diagnostics keep their established SavedVariables arrays and export
-- shape while repair, retention, clear, and failure paths stay observational.
local H = dofile("tests/harness.lua")
local Logs, Revisions = Nexus.DiagnosticLogs, Nexus.Revisions

NexusDB = {
    decisionLog = {
        [1]={seq=1, futureField={token="keep-one"}},
        [2]="malformed",
        [4]={seq=4, futureField={token="keep-four"}},
        extension={future=true},
    },
    runAudit = "malformed-container",
    autoLockLog = {},
    uiProbeLog = {[3]={seq=3, event="legacy-probe", unknown="keep"}},
    diagnosticMeta = {
        schemaVersion=9,
        future="keep-meta",
        histories={decision={future="keep-history-meta"}},
    },
    settings={autoPick=false, futureSetting=true},
    communityBuilds={keep={id="keep"}},
    dpsCapture={keep=true},
    chars={Observer={latch=true}},
    errorHistory={{timestamp=1,source="existing",message="keep"}},
}
assert(Logs.Init(NexusDB), "legacy durable diagnostics failed initialization")
local repairedDecision = Logs.Snapshot("decision")
local repairedProbe = Logs.Snapshot("uiProbe")
assert(#repairedDecision == 2 and repairedDecision[1].seq == 1
    and repairedDecision[2].seq == 4
    and repairedDecision[1].futureField.token == "keep-one"
    and repairedDecision.extension.future == true,
    "legacy decision repair lost order, records, or unknown fields")
assert(#repairedProbe == 1 and repairedProbe[1].seq == 3
    and repairedProbe[1].unknown == "keep"
    and type(NexusDB.runAudit) == "table" and #NexusDB.runAudit == 0,
    "hole/malformed durable history repair was not additive and deterministic")
assert(NexusDB.diagnosticMeta.schemaVersion == 9
    and NexusDB.diagnosticMeta.future == "keep-meta"
    and NexusDB.diagnosticMeta.histories.decision.future == "keep-history-meta",
    "future diagnostic metadata was overwritten")
local decisionIdentity, probeIdentity = NexusDB.decisionLog, NexusDB.uiProbeLog
local repairedCount = Logs.Stats("decision").repaired
assert(Logs.Stats("decision").dropped == 1,
    "malformed retained record was removed without a dropped count")
assert(Logs.Init(NexusDB) and NexusDB.decisionLog == decisionIdentity
    and NexusDB.uiProbeLog == probeIdentity
    and Logs.Stats("decision").repaired == repairedCount,
    "repeat initialization rewrote a current normalized history")
print("legacy/malformed/future-field repair and repeat-init identity -- OK")

assert(Logs.ClearAll(), "durable diagnostic clear-all setup failed")
assert(#NexusDB.errorHistory == 1 and NexusDB.errorHistory[1].message == "keep",
    "durable clear-all unintentionally cleared structured errors")
local revisionBefore = {
    build=Revisions.Get(Revisions.BUILD_LIBRARY_CHANGED),
    dps=Revisions.Get(Revisions.DPS_CHANGED),
    sync=Revisions.Get(Revisions.SYNC_CHANGED),
    catalog=Revisions.Get(Revisions.CATALOG_CHANGED),
}
for index = 1, 205 do
    local source = {seq=index, futureField={token="decision-" .. index}}
    assert(Logs.Append("decision", source))
    source.seq, source.futureField.token = -1, "mutated"
end
for index = 1, 245 do assert(Logs.Append("runAudit", {seq=index, unknown=index})) end
for index = 1, 155 do assert(Logs.Append("autoLock", {seq=index, unknown=index})) end
for index = 1, 125 do assert(Logs.Append("uiProbe", {seq=index, unknown=index})) end
local definitions = Logs.Definitions()
local decision = Logs.Snapshot("decision")
local audits = Logs.Snapshot("runAudit")
local locks = Logs.Snapshot("autoLock")
local probes = Logs.Snapshot("uiProbe")
assert(definitions.decision.cap == 200 and definitions.runAudit.cap == 240
    and definitions.autoLock.cap == 150 and definitions.uiProbe.cap == 120,
    "durable history limits are not explicit")
assert(#decision == 200 and decision[1].seq == 6 and decision[200].seq == 205
    and decision[200].futureField.token == "decision-205",
    "decision history cap/order or append-source isolation failed")
assert(#audits == 240 and audits[1].seq == 6 and audits[240].seq == 245
    and #locks == 150 and locks[1].seq == 6 and locks[150].seq == 155
    and #probes == 120 and probes[1].seq == 6 and probes[120].seq == 125,
    "audit/AutoLock/UI-probe caps or chronological order failed")
assert(Logs.Stats("decision").appended == 205
    and Logs.Stats("decision").dropped == 5
    and Logs.Stats("runAudit").dropped == 5
    and Logs.Stats("autoLock").dropped == 5
    and Logs.Stats("uiProbe").dropped == 5,
    "durable retention metadata does not match overflow")
decision[200].seq = -1
decision[200].futureField.token = "mutated"
assert(Logs.Snapshot("decision")[200].seq == 205
    and Logs.Snapshot("decision")[200].futureField.token == "decision-205",
    "durable snapshot leaked mutable SavedVariables state")

local lastBefore = Logs.Snapshot("decision")[200]
local updated, updateError = Logs.UpdateLast("decision", function(entry)
    entry.user = {{kind="bad"}}
    error("forced updater failure")
end)
assert(not updated and tostring(updateError):find("forced updater failure", 1, true)
    and Logs.Snapshot("decision")[200].user == lastBefore.user,
    "failed last-record update published partial state")
assert(Logs.UpdateLast("decision", function(entry)
    entry.user = {{kind="SelectPerk", arg=2}}
end) and Logs.Snapshot("decision")[200].user[1].arg == 2,
    "successful last-record update was not published")
assert(Revisions.Get(Revisions.BUILD_LIBRARY_CHANGED) == revisionBefore.build
    and Revisions.Get(Revisions.DPS_CHANGED) == revisionBefore.dps
    and Revisions.Get(Revisions.SYNC_CHANGED) == revisionBefore.sync
    and Revisions.Get(Revisions.CATALOG_CHANGED) == revisionBefore.catalog,
    "durable diagnostics advanced represented-data revisions")
assert(Logs.Clear("uiProbe") and #Logs.Snapshot("uiProbe") == 0
    and #Logs.Snapshot("decision") == 200 and #Logs.Snapshot("runAudit") == 240
    and #Logs.Snapshot("autoLock") == 150 and #NexusDB.errorHistory == 1,
    "selective durable clear changed another diagnostic history")
local replacementProbe = {{seq=900, futureField="replacement"}}
NexusDB.uiProbeLog = replacementProbe
assert(Logs.Append("uiProbe", {seq=901})
    and NexusDB.uiProbeLog == replacementProbe
    and #Logs.Snapshot("uiProbe") == 2
    and Logs.Snapshot("uiProbe")[1].futureField == "replacement"
    and Logs.Snapshot("uiProbe")[2].seq == 901,
    "live SavedVariables array replacement remained attached to a stale cache")
print("four durable caps, defensive append/read/update, metadata, revisions -- OK")

-- Module reload keeps the SavedVariables arrays and their normalized order.
dofile("core/DiagnosticLogs.lua")
Logs = Nexus.DiagnosticLogs
assert(Logs.Init(NexusDB) and #Logs.Snapshot("decision") == 200
    and Logs.Snapshot("decision")[200].user[1].arg == 2,
    "durable histories did not survive module reload")

local savedDB = NexusDB
NexusDB = setmetatable({}, {__newindex=function() error("storage denied") end})
local mutationCountsBefore = {#H.selectCalls, #H.banishCalls, #H.freezeCalls,
    H.rerollCalls, #H.saveCalls, #H.activateCalls}
local appended, appendError = Logs.Append("decision", {seq=999})
local cleared, clearError = Logs.ClearAll()
assert(not appended and tostring(appendError):find("storage denied", 1, true)
    and not cleared and tostring(clearError):find("storage denied", 1, true),
    "hostile persistence did not fail closed")
local mutationCountsAfter = {#H.selectCalls, #H.banishCalls, #H.freezeCalls,
    H.rerollCalls, #H.saveCalls, #H.activateCalls}
for index, count in ipairs(mutationCountsAfter) do
    assert(count == mutationCountsBefore[index],
        "diagnostic persistence failure authorized a gameplay mutation")
end
NexusDB = savedDB
print("reload and hostile persistence remain failure-closed -- OK")

-- Boot the real Main/LogViewer/export integration.
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
dofile("ui/JournalTab.lua")
dofile("ui/LogViewer.lua")

local diagnosticProvider, clearProvider
local realLogInit = Nexus.LogViewer.Init
Nexus.LogViewer.Init = function(provider, clearer)
    diagnosticProvider, clearProvider = provider, clearer
    realLogInit(provider, clearer)
end
dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/WishlistModel.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")
H.wishlist = {name="Durable",class="MAGE",echoes={
    {spellId=200100,quality=3,stacks=1},
}}
H.playerLevel = 5
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("SPELLS_CHANGED")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(1)
assert(type(diagnosticProvider) == "function" and type(clearProvider) == "function",
    "Main did not wire durable diagnostic providers")

assert(Logs.ClearAll())
local function BuildExport()
    local exportJob = Nexus.NewAIExportCoroutine()
    local text
    while coroutine.status(exportJob) ~= "dead" do
        local okResume, value = coroutine.resume(exportJob)
        assert(okResume, "durable diagnostic export failed: " .. tostring(value))
        text = value
    end
    return text
end

local hostileScalar = setmetatable({}, {
    __tostring=function() error("hostile export tostring") end,
})
assert(Logs.Append("decision", {
    t=hostileScalar, level=5, horizon=2, charges="malformed",
    proposal={type=hostileScalar, reason=hostileScalar},
    cards="malformed", user="malformed", queueHead="malformed",
}))
assert(Logs.Append("decision", {
    t=hostileScalar, level=5, horizon=2, charges={},
    proposal={type=hostileScalar, reason=hostileScalar},
    cards={hostileScalar, {id=hostileScalar, fam=hostileScalar}},
    user={hostileScalar, {kind=hostileScalar, arg=hostileScalar}},
    queueHead={hostileScalar, {id=hostileScalar, fam=hostileScalar}},
}))
assert(Logs.Append("runAudit", {
    kind=hostileScalar, t=hostileScalar, exact="malformed",
    incumbent="malformed", candidate="malformed",
}))
assert(Logs.Append("runAudit", {
    kind=hostileScalar, t=hostileScalar,
    exact={hostileScalar, {id=hostileScalar, fam=hostileScalar}},
    incumbent={[hostileScalar]=hostileScalar},
    candidate={[hostileScalar]=hostileScalar},
}))
assert(Logs.Append("uiProbe", {
    t=hostileScalar, event=hostileScalar, detail=hostileScalar,
}))
local malformedExport = BuildExport()
local malformedExportAgain = BuildExport()
assert(malformedExport:find("NEXUS_DIAGNOSTIC_LOG_5", 1, true)
    and malformedExport:find("END|boards=2|audits=2|probes=1", 1, true)
    and malformedExport == malformedExportAgain
    and not malformedExport:find("table: 0x", 1, true),
    "malformed nested diagnostics did not produce a complete bounded export")

assert(Logs.ClearAll())
assert(Logs.Append("decision", {t="01:02:03",level=5,horizon=2,
    charges={},proposal={type="wait",reason="review"},cards={},user={},queueHead={}}))
assert(Logs.Append("runAudit", {kind="RUN_START",t="01:02:03",run=1}))
assert(Logs.Append("uiProbe", {t="01:02:03",event="probe",detail="detail"}))
assert(Logs.Append("autoLock", {t="01:02:03",action="lock",name="Echo",
    spellId=200100,ok=true}))
Nexus.Errors.Clear()
local exportText = BuildExport()
assert(type(exportText) == "string"
    and exportText:find("NEXUS_DIAGNOSTIC_LOG_5", 1, true)
    and exportText:find("|boards=1|audits=1|probes=1|errors=0", 1, true)
    and exportText:find("B|1|", 1, true)
    and exportText:find("A|", 1, true)
    and exportText:find("P|", 1, true)
    and exportText:find("END|boards=1|audits=1|probes=1|errors=0", 1, true)
    and not exportText:find("diagnosticMeta", 1, true),
    "comprehensive export format or retained-history counts changed")
assert(diagnosticProvider("boards"):find("DECISION LOG -- 1 boards", 1, true)
    and diagnosticProvider("autolock"):find("LOCK/UNLOCK EVENT HISTORY", 1, true),
    "existing diagnostic tabs did not consume durable snapshots")

local settingsRef, buildsRef = NexusDB.settings, NexusDB.communityBuilds
local dpsRef, charsRef = NexusDB.dpsCapture, NexusDB.chars
assert(Nexus.Sync.BroadcastDps("clear-retained", "Observer", 1000, 80, "dummy"))
local queuedBeforeClear = Nexus.Sync.WorkState().outbound
assert(Nexus.Errors.Record("clear", "expected clear compatibility"))
assert(clearProvider("state"), "full diagnostic clear reported failure")
assert(#Logs.Snapshot("decision") == 0 and #Logs.Snapshot("runAudit") == 0
    and #Logs.Snapshot("autoLock") == 0 and #Logs.Snapshot("uiProbe") == 0,
    "full diagnostic clear left a durable history behind")
assert(NexusDB.settings == settingsRef and NexusDB.communityBuilds == buildsRef
    and NexusDB.dpsCapture == dpsRef and NexusDB.chars == charsRef,
    "diagnostic clear changed settings, builds, DPS data, or safety state")
assert(Nexus.Sync.WorkState().outbound == queuedBeforeClear,
    "diagnostic clear changed queued Sync traffic")
assert(#Nexus.Errors.History() == 0,
    "existing full-clear behavior no longer clears structured errors")
print("Main tabs/export/clear preserve format, data, safety, and Sync traffic -- OK")
