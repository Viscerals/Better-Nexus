-- Stage 36.6 expected red: durable fixed-cap diagnostics must not allocate and
-- rebind their SavedVariables array for every append after the cap. The
-- logical window stays chronological and exactly capped while physical
-- storage remains bounded, reload-compatible, defensive, and observational.
local H = dofile("tests/harness.lua")
dofile("core/SyncDiagnostics.lua")

local Logs = assert(Nexus.DiagnosticLogs)
local History = assert(Nexus.DiagnosticHistory)
local SyncDiagnostics = assert(Nexus.SyncInternals
    and Nexus.SyncInternals.Diagnostics)
local Revisions = assert(Nexus.Revisions)

local failures, desiredChecks, controls = {}, 0, 0
local function Desired(ok, label)
    desiredChecks = desiredChecks + 1
    if not ok then failures[#failures + 1] = label end
end
local function Control(ok, label)
    controls = controls + 1
    assert(ok, "green control failed: " .. tostring(label))
end

local function NumericShape(source)
    local count, maximum = 0, 0
    for key in pairs(type(source) == "table" and source or {}) do
        if type(key) == "number" and key >= 1
            and key == math.floor(key) then
            count = count + 1
            if key > maximum then maximum = key end
        end
    end
    return count, maximum
end

local function StableBytes(value, seen)
    local kind = type(value)
    if kind ~= "table" then
        return kind .. ":" .. tostring(value)
    end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local rows = {}
    for key, child in pairs(value) do
        rows[#rows + 1] = StableBytes(key, seen)
            .. "=" .. StableBytes(child, seen)
    end
    table.sort(rows)
    seen[value] = nil
    return "{" .. table.concat(rows, ",") .. "}"
end

local function RevisionSnapshot()
    return {
        build=Revisions.Get(Revisions.BUILD_LIBRARY_CHANGED),
        dps=Revisions.Get(Revisions.DPS_CHANGED),
        sync=Revisions.Get(Revisions.SYNC_CHANGED),
        catalog=Revisions.Get(Revisions.CATALOG_CHANGED),
    }
end

local function SameRevisions(left, right)
    return left.build == right.build and left.dps == right.dps
        and left.sync == right.sync and left.catalog == right.catalog
end

NexusDB = {
    decisionLog={
        [2]={seq=2,unknown={keep="two"}},
        [5]={seq=5,unknown={keep="five"}},
        extension={future="keep-array-extension"},
    },
    runAudit={extension={future="keep-run-extension"}},
    autoLockLog={},uiProbeLog={
        [3]={seq=3,future={keep="three"}},
        [8]={seq=8,future={keep="eight"}},
        extension={future="keep-future-array"},
    },
    diagnosticMeta={
        schemaVersion=9,future="keep-meta",
        histories={
            decision={future="keep-decision-meta"},
            runAudit={future="keep-run-meta"},
            uiProbe={
                storageSchema=99,storageHead=8,storageTail=3,
                storageRetained=2,future={keep="future-history-meta"},
            },
        },
    },
    settings={keep=true},communityBuilds={keep={id="keep"}},
    dpsCapture={keep=true},chars={Observer={keep=true}},
}

local futureHistory = NexusDB.uiProbeLog
local futureMeta = NexusDB.diagnosticMeta.histories.uiProbe
local futureThree, futureEight = futureHistory[3], futureHistory[8]
local futureHistoryBytes = StableBytes(futureHistory)
local futureMetaBytes = StableBytes(futureMeta)

Control(Logs.Init(NexusDB), "legacy diagnostic arrays did not initialize")
local legacy = Logs.Snapshot("decision")
Control(#legacy == 2 and legacy[1].seq == 2 and legacy[2].seq == 5
        and legacy[1].unknown.keep == "two"
        and legacy.extension.future == "keep-array-extension",
    "legacy sparse order or unknown array fields were not preserved")
Control(NexusDB.diagnosticMeta.schemaVersion == 9
        and NexusDB.diagnosticMeta.future == "keep-meta"
        and NexusDB.diagnosticMeta.histories.decision.future
            == "keep-decision-meta"
        and NexusDB.diagnosticMeta.histories.runAudit.future
            == "keep-run-meta",
    "future diagnostic metadata was overwritten")

local futureSnapshot, futureSnapshotWhy = Logs.Snapshot("uiProbe")
local futureAppend, futureAppendWhy = Logs.Append("uiProbe", {seq=99})
local futureClear, futureClearWhy = Logs.Clear("uiProbe")
local futureStats = Logs.Stats("uiProbe")
Desired(NexusDB.uiProbeLog == futureHistory
        and NexusDB.diagnosticMeta.histories.uiProbe == futureMeta
        and futureHistory[3] == futureThree and futureHistory[8] == futureEight
        and futureHistory[1] == nil and futureHistory[2] == nil
        and StableBytes(futureHistory) == futureHistoryBytes
        and StableBytes(futureMeta) == futureMetaBytes,
    "future per-history schema was downgraded, reordered, or replaced")
Desired(futureAppend == false and futureClear == false
        and tostring(futureAppendWhy):find("future diagnostic history",1,true)
        and tostring(futureClearWhy):find("future diagnostic history",1,true)
        and type(futureSnapshot) == "table" and next(futureSnapshot) == nil
        and tostring(futureSnapshotWhy):find("future diagnostic history",1,true)
        and futureStats.readOnly == true,
    "future per-history schema was exposed as writable or interpreted storage")

-- A supported history can become future-owned after initialization. Both a
-- metadata-table replacement and an in-place schema upgrade must invalidate
-- the writable cache before Append observes or changes either owner.
local replacedHistory = NexusDB.autoLockLog
local replacedMeta = {
    storageSchema=77,storageHead=41,storageTail=9,storageRetained=3,
    future={keep="post-init-replacement"},
}
NexusDB.diagnosticMeta.histories.autoLock = replacedMeta
local replacedHistoryBytes = StableBytes(replacedHistory)
local replacedMetaBytes = StableBytes(replacedMeta)

local upgradedHistory = NexusDB.decisionLog
local upgradedMeta = NexusDB.diagnosticMeta.histories.decision
upgradedMeta.storageSchema = 88
upgradedMeta.storageHead = 90
upgradedMeta.storageTail = 12
upgradedMeta.storageRetained = 4
upgradedMeta.futureUpgrade = {keep="post-init-in-place"}
local upgradedHistoryBytes = StableBytes(upgradedHistory)
local upgradedMetaBytes = StableBytes(upgradedMeta)

local replacedAppend, replacedWhy = Logs.Append("autoLock", {seq=77})
local upgradedAppend, upgradedWhy = Logs.Append("decision", {seq=88})
Desired(replacedAppend == false and upgradedAppend == false
        and tostring(replacedWhy):find("future diagnostic history",1,true)
        and tostring(upgradedWhy):find("future diagnostic history",1,true)
        and NexusDB.autoLockLog == replacedHistory
        and NexusDB.diagnosticMeta.histories.autoLock == replacedMeta
        and StableBytes(replacedHistory) == replacedHistoryBytes
        and StableBytes(replacedMeta) == replacedMetaBytes
        and NexusDB.decisionLog == upgradedHistory
        and NexusDB.diagnosticMeta.histories.decision == upgradedMeta
        and StableBytes(upgradedHistory) == upgradedHistoryBytes
        and StableBytes(upgradedMeta) == upgradedMetaBytes,
    "cached writable history ignored a post-init future metadata owner")

local definitions = Logs.Definitions()
local cap = assert(definitions.runAudit.cap)
local total = cap * 20 + 17
local historyIdentity = NexusDB.runAudit
local replacements = 0
local revisionsBefore = RevisionSnapshot()
for index = 1, total do
    local record = {
        seq=index,kind="RUN",summary="bounded-" .. tostring(index),
        nested={value=index},
    }
    Control(Logs.Append("runAudit", record),
        "durable append failed at " .. tostring(index))
    record.seq, record.nested.value = -1, -1
    if NexusDB.runAudit ~= historyIdentity then
        replacements = replacements + 1
        historyIdentity = NexusDB.runAudit
    end
end

local stats = Logs.Stats("runAudit")
local retained = Logs.Snapshot("runAudit")
local numericCount, maximumIndex = NumericShape(NexusDB.runAudit)
local expectedDropped = total - cap
local batch = tonumber(stats.trimAt) and stats.trimAt - cap or 0
local expectedCompactions = batch > 0
    and math.floor(expectedDropped / batch) or -1

Control(#retained == cap
        and retained[1].seq == total - cap + 1
        and retained[cap].seq == total
        and retained[cap].nested.value == total,
    "overflow snapshot lost exact newest chronological order")
Control(retained.extension.future == "keep-run-extension"
        and NexusDB.runAudit.extension.future == "keep-run-extension",
    "overflow retention lost unknown SavedVariables extensions")
Control(stats.retained == cap and stats.appended == total
        and stats.dropped == expectedDropped,
    "overflow counters or exact cap changed")
Control(numericCount == cap,
    "physical durable storage retained more than the logical cap")
Control(SameRevisions(revisionsBefore, RevisionSnapshot()),
    "diagnostic overflow advanced a represented-data revision")

Desired(replacements == 0,
    "overflow rebuilt and rebound the SavedVariables array per append: "
        .. tostring(replacements))
Desired(type(stats.trimAt) == "number" and stats.trimAt > cap
        and type(stats.compactions) == "number"
        and stats.compactions == expectedCompactions
        and stats.compactions < stats.dropped,
    "bounded-batch compaction policy is absent or nondeterministic")
Desired(stats.storageSlots == cap and stats.maxIndex == maximumIndex
        and stats.head >= 1 and stats.tail == maximumIndex
        and maximumIndex < stats.trimAt,
    "logical window does not expose bounded physical-storage evidence")

-- Update failure must not publish a partially changed last row.
local lastBefore = Logs.Snapshot("runAudit")[cap]
local updated, updateReason = Logs.UpdateLast("runAudit", function(entry)
    entry.seq = -999
    error("forced diagnostic updater failure")
end)
Control(updated == false
        and tostring(updateReason):find("forced diagnostic updater failure",1,true)
        and Logs.Snapshot("runAudit")[cap].seq == lastBefore.seq,
    "failed last-row update escaped or published partial state")

-- The sparse bounded window must remain readable after a module reload, and
-- reload normalization must preserve the established SavedVariables table.
local identityBeforeReload = NexusDB.runAudit
dofile("core/DiagnosticLogs.lua")
Logs = Nexus.DiagnosticLogs
Control(Logs.Init(NexusDB) and NexusDB.runAudit == identityBeforeReload,
    "module reload replaced the compatible durable history table")
local reloaded = Logs.Snapshot("runAudit")
local reloadedStats = Logs.Stats("runAudit")
Control(#reloaded == cap and reloaded[1].seq == total - cap + 1
        and reloaded[cap].seq == total
        and reloadedStats.compactions == stats.compactions,
    "module reload changed logical order or compaction accounting")

-- Actual Sync diagnostics accept raw caller values only through SafeText and
-- retain a fixed scalar event, never the caller's packet/chat/payload table.
local clock = 100
local session = SyncDiagnostics.New({
    history=History,now=function() clock = clock + 1; return clock end,
    logCap=7,logTrimAt=9,logTextBytes=48,
})
local raw = {
    packet=string.rep("P", 200),chat="private-chat",
    payload={secret="never-retain-the-table"},
}
session.LogRaw(raw)
raw.payload.secret = "mutated"
local rawEvent = session.EventLog()[1]
local rawEventFields = 0
for _ in pairs(rawEvent or {}) do rawEventFields = rawEventFields + 1 end
Control(rawEventFields == 4 and type(rawEvent.text) == "string"
        and #rawEvent.text <= 48 and rawEvent.packet == nil
        and rawEvent.chat == nil and rawEvent.payload == nil
        and not rawEvent.text:find("private-chat",1,true)
        and not rawEvent.text:find("never-retain-the-table",1,true),
    "Sync raw-table input escaped its fixed sanitized scalar projection")
for index = 2, 80 do session.LogRaw("event-" .. tostring(index)) end
local events, sessionStats = session.EventLog(), session.LogStats()
local eventFields = 0
for _ in pairs(events[#events] or {}) do eventFields = eventFields + 1 end
Control(#events == 7 and events[1].seq == 74 and events[7].seq == 80
        and sessionStats.retained == 7 and sessionStats.dropped == 73,
    "session diagnostic ring lost its cap or chronology")
Control(eventFields == 4 and type(events[7].text) == "string"
        and #events[7].text <= 48
        and events[7].packet == nil and events[7].chat == nil
        and events[7].payload == nil,
    "Sync diagnostics retained a raw payload instead of fixed scalars")

local hostile = setmetatable({}, {
    __tostring=function() error("hostile diagnostic tostring") end,
})
Control(pcall(session.LogRaw, hostile)
        and session.EventLog()[#session.EventLog()].text
            == "<unprintable:table>",
    "hostile raw diagnostic input escaped failure isolation")

-- ClearAll is atomic across independently versioned histories. One future
-- storage owner blocks the operation before any supported sibling is cleared,
-- normalized, rebound, or otherwise changed.
local allHistoryNames = {"decisionLog","runAudit","autoLockLog","uiProbeLog"}
local allHistoryBefore = {}
for _, key in ipairs(allHistoryNames) do
    allHistoryBefore[key] = {
        identity=NexusDB[key],bytes=StableBytes(NexusDB[key]),
    }
end
local allMetaIdentity = NexusDB.diagnosticMeta
local allMetaBytes = StableBytes(NexusDB.diagnosticMeta)
local clearedAll, clearedAllWhy = Logs.ClearAll()
local allPreserved = clearedAll == false
    and tostring(clearedAllWhy):find("future diagnostic history",1,true)
    and NexusDB.diagnosticMeta == allMetaIdentity
    and StableBytes(NexusDB.diagnosticMeta) == allMetaBytes
for _, key in ipairs(allHistoryNames) do
    local before = allHistoryBefore[key]
    allPreserved = allPreserved and NexusDB[key] == before.identity
        and StableBytes(NexusDB[key]) == before.bytes
end
Desired(allPreserved,
    "ClearAll partially changed supported histories before a future owner blocked it")

local summary = string.format(
    "desired=%d expected_red=%d controls=%d cap=%d appended=%d dropped=%d replacements=%d compactions=%s slots=%d maxIndex=%d export=chronological rawPayload=none mutations=0",
    desiredChecks,#failures,controls,cap,total,expectedDropped,replacements,
    tostring(stats.compactions),numericCount,maximumIndex)
if #failures > 0 then
    for index, label in ipairs(failures) do
        print(string.format("EXPECTED RED %02d: %s", index, label))
    end
    error("EXPECTED RED [Stage 36.6 diagnostic history overflow]: "
        .. summary .. "\n - " .. table.concat(failures, "\n - "))
end
print("diagnostic history overflow: " .. summary .. " -- OK")
