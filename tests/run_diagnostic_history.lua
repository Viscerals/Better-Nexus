-- Bounded session diagnostics must stay chronological and defensive without
-- ever owning or clearing Sync transport/backpressure work.
local H = dofile("tests/harness.lua")

local DiagnosticHistory = Nexus.DiagnosticHistory
local history = DiagnosticHistory.New({
    cap=3, trimAt=5, maxTextBytes=16, maxDepth=4,
})
for index = 1, 8 do
    history.Append({index=index, text="entry-" .. index,
        nested={value="value-" .. index}})
end
local snapshot = history.Snapshot()
local historyStats = history.Stats()
assert(#snapshot == 3 and snapshot[1].index == 6 and snapshot[3].index == 8,
    "history did not retain the newest chronological window")
assert(historyStats.cap == 3 and historyStats.trimAt == 5
    and historyStats.retained == 3 and historyStats.appended == 8
    and historyStats.dropped == 5 and historyStats.compactions == 2,
    "history cap/trim statistics are not deterministic")
snapshot[1].index = -1
snapshot[1].nested.value = "mutated"
historyStats.retained = -1
local retained = history.Snapshot()
assert(retained[1].index == 6 and retained[1].nested.value == "value-6"
    and history.Stats().retained == 3,
    "history snapshot or statistics leaked mutable state")
local source = {label="source", nested={value="original"}}
local aliasHistory = DiagnosticHistory.New({cap=2, trimAt=4})
aliasHistory.Append(source)
source.label, source.nested.value = "mutated", "mutated"
assert(aliasHistory.Snapshot()[1].label == "source"
    and aliasHistory.Snapshot()[1].nested.value == "original",
    "append retained caller-owned table aliases")
local cyclic = {label="cycle"}
cyclic.self = cyclic
aliasHistory.Append(cyclic)
assert(aliasHistory.Snapshot()[2].self == "<cycle>",
    "cyclic diagnostic entry was not bounded deterministically")

local hostile = setmetatable({}, {__tostring=function() error("hostile") end})
local safe = DiagnosticHistory.SafeText(hostile, 24)
assert(safe == "<unprintable:table>", "hostile tostring was not isolated")
local bounded = DiagnosticHistory.SafeText("line\n" .. string.rep("x", 40), 16)
assert(#bounded == 16 and not bounded:find("[%c]"),
    "diagnostic text was not control-safe and byte-bounded")
assert(DiagnosticHistory.Format(16, "%d", "not-a-number") == "%d",
    "failed diagnostic formatting was not isolated deterministically")
history.Clear()
assert(#history.Snapshot() == 0 and history.Stats().dropped == 0
    and history.Stats().appended == 0 and history.Stats().compactions == 0,
    "clear did not reset retained history and its session counters")
local previousHistory = history
dofile("core/DiagnosticHistory.lua")
local reloaded = Nexus.DiagnosticHistory.New({cap=3, trimAt=5})
assert(#reloaded.Snapshot() == 0 and #previousHistory.Snapshot() == 0,
    "module reload did not start a deterministic empty history")
print("bounded primitive order, trim, hostile text, copies, clear, reload -- OK")

dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
dofile("core/DpsCapture.lua")
local Sync, DPS, Revisions = Nexus.Sync, Nexus.DpsCapture, Nexus.Revisions
local clock = 1000
GetTime = function() return clock end
UnitName = function() return "Observer" end
NexusDB = {communityBuilds={
    ["pending-build"] = {
        id="pending-build", title="Pending Build", author="Observer",
        class="MAGE", lastModified=1, postedAt=1,
        echoes={{spellId=200100, quality=3, stacks=1}},
    },
}, syncTombstones={}, dpsCapture={}}
Sync.Init(Nexus.Codec, {})

local function ScalarCopy(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        if type(value) ~= "table" and key ~= "oldestValidAge" then
            copy[key] = value
        end
    end
    return copy
end

local function AssertSameScalars(expected, actual, label)
    for key, value in pairs(expected) do
        assert(actual[key] == value,
            label .. " changed " .. tostring(key) .. " from "
            .. tostring(value) .. " to " .. tostring(actual[key]))
    end
    for key, value in pairs(actual) do
        if type(value) ~= "table" and key ~= "oldestValidAge" then
            assert(expected[key] == value, label .. " added/changed " .. tostring(key))
        end
    end
end

assert(Sync.BroadcastDps("retained-a", "Observer", 1001, 80, "dummy"))
assert(Sync.BroadcastDps("retained-b", "Observer", 1002, 80, "dummy"))
assert(Sync.HandleIncoming("WLLQ|Requester|pending-build", "Requester"),
    "test setup could not retain a pending loadout response")
Sync.HandleIncoming("WLRB|ChunkPeer|partial-build|1|1/2|A", "ChunkPeer")
local workBefore = ScalarCopy(Sync.WorkState())
assert(workBefore.sending == 2 and workBefore.pendingLoadouts == 1
    and workBefore.buildInflight == 1,
    "queue-independence fixture did not populate outbound, pending, and inflight work")
local transportStatsBefore = ScalarCopy(Sync.Stats())
local syncRevisionBefore = Revisions.Get(Revisions.SYNC_CHANGED)
Sync.ClearLog()
AssertSameScalars(workBefore, Sync.WorkState(), "Sync log clear")
for index = 1, 240 do
    clock = clock + 0.01
    Sync.LogRaw("event-" .. index)
end
assert(Sync.WorkState().oldestValidAge >= 2.39,
    "oldest valid queued-packet age did not remain truthful while logging")
AssertSameScalars(workBefore, Sync.WorkState(), "Sync log overflow")
AssertSameScalars(transportStatsBefore, Sync.Stats(), "Sync diagnostics")
assert(Revisions.Get(Revisions.SYNC_CHANGED) == syncRevisionBefore,
    "Sync diagnostics advanced represented-data revision")

local events = Sync.EventLog()
local rawEvents = Sync.RawLog()
local logStats = Sync.LogStats()
assert(#events == 160 and #rawEvents == 160
    and events[1].seq == 81 and events[160].seq == 240,
    "Sync history cap or chronological sequence is wrong")
assert(logStats.cap == 160 and logStats.trimAt == 200
    and logStats.retained == 160 and logStats.dropped == 80
    and logStats.compactions == 2,
    "Sync history statistics do not match its explicit retention policy")
events[1].text = "mutated"
events[1].nested = {bad=true}
rawEvents[160].seq = -1
logStats.retained = -1
assert(Sync.EventLog()[1].text == "event-81"
    and Sync.RawLog()[160].seq == 240 and Sync.LogStats().retained == 160,
    "Sync public diagnostic reads leaked mutable history state")

assert(pcall(Sync.LogRaw, hostile), "hostile raw log value escaped diagnostics")
local hostileEntry = Sync.EventLog()[#Sync.EventLog()]
assert(hostileEntry.text == "<unprintable:table>",
    "hostile raw log value lost its safe diagnostic marker")
assert(pcall(Sync.LogEvent, "RX", "%d", "not-a-number"),
    "malformed Sync log formatting escaped diagnostics")
assert(Sync.EventLog()[#Sync.EventLog()].text == "%d",
    "malformed Sync log formatting did not retain deterministic fallback text")
Sync.LogRaw("line\n" .. string.rep("x", 3000))
local boundedEntry = Sync.EventLog()[#Sync.EventLog()]
assert(#boundedEntry.text <= 2048 and not boundedEntry.text:find("[%c]"),
    "Sync diagnostic entry exceeded its text bound or retained controls")
Sync.ClearLog()
AssertSameScalars(workBefore, Sync.WorkState(), "second Sync log clear")
Sync.LogRaw("after-clear")
assert(#Sync.EventLog() == 1 and Sync.EventLog()[1].seq == 1,
    "Sync clear did not reset visible sequence behavior")
print("Sync defensive history and queue/backpressure independence -- OK")

DPS.Init({}, Sync)
DPS.ClearDebugLog()
local dpsRevisionBefore = Revisions.Get(Revisions.DPS_CHANGED)
for _ = 1, 50 do
    clock = clock + 1
    DPS.OnCombatStart()
    DPS.OnCombatEnd()
end
local dpsStats = DPS.DebugLogStats()
local dpsText = DPS.GetDebugLog()
assert(dpsStats.cap == 120 and dpsStats.trimAt == 150
    and dpsStats.retained == 120 and dpsStats.dropped == 30
    and dpsStats.compactions == 1,
    "DPS debug history does not use its explicit bounded policy")
assert(dpsText:find("^Nexus DPS capture log\n\n")
    and dpsText:find("ignored: target was not", 1, true),
    "DPS debug export header or established activity text changed")
assert(Revisions.Get(Revisions.DPS_CHANGED) == dpsRevisionBefore,
    "DPS diagnostic activity advanced represented-data revision")
dpsStats.retained = -1
assert(DPS.DebugLogStats().retained == 120,
    "DPS debug statistics leaked mutable state")
DPS.ClearDebugLog()
assert(DPS.GetDebugLog()
    == "Nexus DPS capture log\n\nNo DPS activity logged this session.",
    "DPS clear/no-activity export compatibility changed")
AssertSameScalars(workBefore, Sync.WorkState(), "DPS diagnostic activity")
print("DPS bounded debug history, export compatibility, and revision isolation -- OK")
