-- Stage 36.6 expected red: idle Scheduler polls built and sorted a
-- fresh due array on every frame.  Keep the work probe deterministic while
-- preserving the scheduler's established timing and mutation contracts.

local H = dofile("tests/harness.lua")

NexusDB = {}
Nexus.Errors.Init()
H.now = 1000
dofile("core/Scheduler.lua")
local Scheduler = Nexus.Scheduler

local failures, controls, desiredCount = {}, 0, 0
local function Desired(ok, message)
    desiredCount = desiredCount + 1
    if not ok then failures[#failures + 1] = message end
end
local function Control(ok, message)
    controls = controls + 1
    if not ok then error("CONTROL FAILURE: " .. message, 0) end
end

local function Upvalue(owner, wanted)
    if not (debug and type(debug.getupvalue) == "function") then
        return nil, false
    end
    for index = 1, 64 do
        local name, value = debug.getupvalue(owner, index)
        if not name then break end
        if name == wanted then return value, true end
    end
    return nil, false
end

local sourceFile = assert(io.open("core/Scheduler.lua", "rb"))
local source = sourceFile:read("*a")
sourceFile:close()
local tickStart = assert(source:find(
    "function Scheduler.Tick(now)", 1, true))
local pendingStart = assert(source:find(
    "function Scheduler.Pending", tickStart, true))
local tickBody = source:sub(tickStart, pendingStart - 1)
Desired(type(tickBody) == "string"
        and not tickBody:find("local due = {}", 1, true),
    "Tick still constructs a per-poll due table")

local readyBefore, hasReady = Upvalue(Scheduler.Tick, "ready")
local _, hasNextDue = Upvalue(Scheduler.Tick, "nextDue")
Desired(hasReady and type(readyBefore) == "table",
    "Tick has no reusable bounded due storage")
Desired(hasNextDue,
    "Tick has no cached next-deadline fast path")

local realPairs, realSort = pairs, table.sort
local captureWork, scans, sorts = false, 0, 0
pairs = function(...)
    if captureWork then scans = scans + 1 end
    return realPairs(...)
end
table.sort = function(...)
    if captureWork then sorts = sorts + 1 end
    return realSort(...)
end

captureWork = true
for _ = 1, 256 do
    Control(Scheduler.Tick(H.now) == 0,
        "empty scheduler reported callback work")
end
captureWork = false
local idleScans, idleSorts = scans, sorts
Desired(idleScans == 0,
    "no-task polls traversed the task table")
Desired(idleSorts == 0,
    "no-task polls sorted an empty due set")

local futureRuns = 0
Control(Scheduler.After("future", 100, function()
    futureRuns = futureRuns + 1
end), "future task was rejected")
scans, sorts = 0, 0
captureWork = true
for _ = 1, 512 do
    Control(Scheduler.Tick(H.now + 99.5) == 0,
        "not-due scheduler reported callback work")
end
captureWork = false
local futureScans, futureSorts = scans, sorts
Desired(futureScans == 0,
    "not-due polls traversed the task table")
Desired(futureSorts == 0,
    "not-due polls sorted an empty due set")
Control(futureRuns == 0 and Scheduler.Pending("future").due == H.now + 100,
    "not-due fast path changed the scheduled deadline")
Control(Scheduler.Cancel("future"), "future task did not cancel")

local readyAfter, stillHasReady = Upvalue(Scheduler.Tick, "ready")
Desired(stillHasReady and type(readyAfter) == "table"
        and readyAfter == readyBefore and #readyAfter == 0,
    "idle polls did not retain one empty reusable due buffer")

pairs, table.sort = realPairs, realSort

-- Due callbacks retain exact due/key ordering, replacement generation, and
-- the explicit Tick time passed to callbacks.
H.now = 200
local ordered, callbackTimes = {}, {}
local function Ordered(key, now)
    ordered[#ordered + 1] = key
    callbackTimes[#callbackTimes + 1] = now
end
Control(Scheduler.After("replace", 1, function()
    ordered[#ordered + 1] = "replace-old"
end), "old replacement task was rejected")
Control(Scheduler.After("replace", 8, function(_, now)
    ordered[#ordered + 1] = "replace-new"
    callbackTimes[#callbackTimes + 1] = now
end), "new replacement task was rejected")
Control(Scheduler.After("b.same", 10, Ordered),
    "same-time B task was rejected")
Control(Scheduler.After("a.same", 10, Ordered),
    "same-time A task was rejected")
Control(Scheduler.After("early", 5, Ordered),
    "early task was rejected")
Control(Scheduler.Tick(210) == 4,
    "ordered due batch ran the wrong callback count")
Control(table.concat(ordered, ",") ==
        "early,replace-new,a.same,b.same",
    "due/key/generation ordering changed: " .. table.concat(ordered, ","))
Control(#callbackTimes == 4 and callbackTimes[1] == 210
        and callbackTimes[2] == 210 and callbackTimes[3] == 210
        and callbackTimes[4] == 210,
    "callback time no longer matches the Tick time")

-- A callback may cancel or replace a later ready key.  Its old generation is
-- skipped, while the newly scheduled generation waits for the next Tick.
H.now = 300
local mutation = {}
Control(Scheduler.After("a.mutate", 0, function()
    mutation[#mutation + 1] = "mutate"
    Scheduler.Cancel("z.cancelled")
    Scheduler.After("z.replaced", 0, function()
        mutation[#mutation + 1] = "replacement"
    end)
end), "mutation callback was rejected")
Control(Scheduler.After("z.cancelled", 0, function()
    mutation[#mutation + 1] = "cancelled"
end), "cancellation target was rejected")
Control(Scheduler.After("z.replaced", 0, function()
    mutation[#mutation + 1] = "old-generation"
end), "replacement target was rejected")
Control(Scheduler.Tick(300) == 1
        and table.concat(mutation, ",") == "mutate",
    "same-Tick cancellation or generation isolation changed")
Control(Scheduler.Tick(300) == 1
        and table.concat(mutation, ",") == "mutate,replacement",
    "replacement generation did not run on the next Tick")

-- Reentrant Tick retains the historical nested-snapshot behavior without
-- corrupting the outer reusable ready buffer. The nested call consumes the
-- remaining old-generation due tasks; the outer call then skips their removed
-- snapshots and returns only its own callback count.
H.now = 350
local reentrant = {}
Control(Scheduler.After("a.reentrant",0,function()
    reentrant[#reentrant + 1] = "a"
    local nested = Scheduler.Tick(H.now)
    reentrant[#reentrant + 1] = "inner:" .. tostring(nested)
end),"reentrant callback was rejected")
Control(Scheduler.After("b.reentrant",0,function()
    reentrant[#reentrant + 1] = "b"
end),"reentrant B callback was rejected")
Control(Scheduler.After("c.reentrant",0,function()
    reentrant[#reentrant + 1] = "c"
end),"reentrant C callback was rejected")
local reentrantOk, reentrantRan = pcall(Scheduler.Tick,H.now)
Control(reentrantOk and reentrantRan == 1
        and table.concat(reentrant,",") == "a,b,c,inner:2"
        and #Scheduler.Pending() == 0,
    "nested Tick corrupted or changed the outer due snapshot")

-- A same-time generation scheduled by one ready callback remains visible when
-- a later repeating callback advances away from that shared old deadline.
H.now = 375
local deferredGeneration = {}
Control(Scheduler.After("a.defer",5,function()
    deferredGeneration[#deferredGeneration + 1] = "schedule"
    Scheduler.After("m.deferred",0,function()
        deferredGeneration[#deferredGeneration + 1] = "deferred"
    end)
end),"same-time scheduling callback was rejected")
Control(Scheduler.Every("z.repeat",5,function()
    deferredGeneration[#deferredGeneration + 1] = "repeat"
end),"same-time repeating callback was rejected")
H.now = 380
Control(Scheduler.Tick(H.now) == 2
        and table.concat(deferredGeneration,",") == "schedule,repeat",
    "same-time source callbacks changed order")
Control(Scheduler.Tick(H.now) == 1
        and table.concat(deferredGeneration,",") ==
            "schedule,repeat,deferred",
    "repeating cadence hid a deferred same-time generation")
Control(Scheduler.Cancel("z.repeat"),
    "same-time repeating callback did not cancel")

-- Delayed repeating work runs once and advances from its original cadence.
H.now = 400
local repeats = 0
Control(Scheduler.Every("cadence", 5, function(key, now)
    Control(key == "cadence" and now == 422,
        "repeating callback key/time changed")
    repeats = repeats + 1
end), "repeating task was rejected")
Control(Scheduler.Tick(422) == 1 and repeats == 1
        and Scheduler.Pending("cadence").due == 425,
    "delayed repeating cadence drifted")
Control(Scheduler.Tick(424.9) == 0,
    "repeating callback ran before its retained cadence")
Control(Scheduler.Cancel("cadence"), "repeating task did not cancel")

-- Failure isolation is unchanged and later due keys still execute.
local continued = false
Control(Scheduler.After("a.failure", 0, function()
    error("stage36 scheduled failure")
end), "failing callback was rejected")
Control(Scheduler.After("b.continue", 0, function()
    continued = true
end), "post-failure callback was rejected")
Control(Scheduler.Tick(H.now) == 2 and continued,
    "callback failure suppressed later due work")
local latest = Nexus.Errors.Latest()
Control(latest and latest.source == "Scheduler.a.failure"
        and latest.message:find("stage36 scheduled failure", 1, true),
    "callback failure was not retained")

-- The due buffer stays bounded to the established 32-callback cap.  The
-- earliest keys run first and the remainder survives for the next Tick.
H.now = 500
local capped = {}
local function CapCallback(key) capped[#capped + 1] = key end
for index = 1, 40 do
    Control(Scheduler.After(string.format("cap.%02d", index), 0, CapCallback),
        "cap task was rejected")
end
Control(Scheduler.Tick(H.now) == Scheduler.MaxCallbacksPerTick()
        and #capped == 32 and capped[1] == "cap.01"
        and capped[32] == "cap.32",
    "32-callback cap or earliest-key ordering changed")
Control(#Scheduler.Pending() == 8,
    "callback cap discarded remaining due work")
Control(Scheduler.Tick(H.now) == 8 and #capped == 40
        and capped[40] == "cap.40" and #Scheduler.Pending() == 0,
    "remaining due work did not continue deterministically")

-- Cancellation inside a saturated snapshot does not lower the cap while
-- other callbacks from that same Tick snapshot remain due. Newly scheduled
-- generations are still deferred, but the next old-generation keys fill the
-- available callback window exactly as the former complete due list did.
H.now = 600
local saturated = {}
for index = 1, 40 do
    local key = string.format("fill.%02d", index)
    Control(Scheduler.After(key, 0, function(callbackKey)
        saturated[#saturated + 1] = callbackKey
        if callbackKey == "fill.01" then
            for cancelled = 2, 6 do
                Scheduler.Cancel(string.format("fill.%02d", cancelled))
            end
        end
    end), "saturated cancellation task was rejected")
end
Control(Scheduler.Tick(H.now) == Scheduler.MaxCallbacksPerTick()
        and #saturated == 32 and saturated[1] == "fill.01"
        and saturated[2] == "fill.07" and saturated[32] == "fill.37",
    "same-snapshot cancellation stopped before the 32-callback cap")
Control(#Scheduler.Pending() == 3,
    "saturated cancellation lost or duplicated remaining due work")
Control(Scheduler.Tick(H.now) == 3 and #saturated == 35
        and saturated[35] == "fill.40" and #Scheduler.Pending() == 0,
    "saturated cancellation remainder did not continue in order")
local readyFinal, hasReadyFinal = Upvalue(Scheduler.Tick, "ready")
Control(hasReadyFinal and readyFinal == readyBefore and #readyFinal == 0,
    "due batches replaced, leaked, or retained the reusable due buffer")

-- First-run evidence compaction shares the same noncritical scheduler owner.
-- Initialization performs only one fixed work slice; subsequent pumps are
-- resumable, tolerate a represented-data revision during the walk, and stamp
-- completion only after every retained row is exact.
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")
local Store = Nexus.Store
local Catalog = Nexus.BuildCatalog
local Compaction = Nexus.DataCompaction

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do out[Copy(key,seen)] = Copy(child,seen) end
    return out
end

local function Equal(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    seen = seen or {}
    if seen[left] then return seen[left] == right end
    seen[left] = right
    for key, value in pairs(left) do
        if not Equal(value,right[key],seen) then return false end
    end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

local overlay = {}
for index = 1, 160 do
    local id = string.format("budget-%03d",index)
    overlay[id] = {
        id=id,title="Budget " .. index,author="BudgetOwner",
        ownerKey="budgetowner@ebonhold",class="MAGE",
        postedAt=index,lastModified=index,
        fingerprint=tostring(910000 + index) .. "x1",
        echoes={{spellId=910000 + index,quality=3,stacks=1}},
        futureRow={keep="row-" .. index},
    }
end
local dpsRows = {}
for index = 1, 40 do
    dpsRows["player-" .. index] = {
        dps=1000000 + index,duration=60,ts=index,
        player="Player" .. index,class="MAGE",level=80,
        fingerprint=tostring(920000 + index) .. "x1",
        echoes={{spellId=920000 + index,count=1}},
        ownerVerified=true,futureRow={keep="dps-" .. index},
    }
end
local filters = {scope="mine",futureFilter={keep=true}}
local tombstones = {gone={stamp=700,author="BudgetOwner",future="keep"}}
local opaque = {nested={keep="opaque"}}
Nexus.BundledBuilds = {
    schemaVersion=1,catalogVersion="stage36-allocation",
    sourceVersion="test",builds={},
}
NexusDB = {
    settingsVersion=2,settings={},chars={},communityBuilds=overlay,
    dpsCapture={characterBest={dummy=dpsRows,lk={}}},
    buildFilters=filters,syncTombstones=tombstones,
    futureRoot=opaque,
}
UnitName = function() return "BudgetOwner" end
GetNormalizedRealmName = function() return "Ebonhold" end
H.now = 700
Store.Init()
local cold = Compaction.Stats()
Desired(cold.pending == true and cold.lastPumpWork <= cold.workBudget,
    "large first-run compaction was not deferred after one bounded pump")
Desired(cold.overlayRecordsBefore < 160,
    "large first-run compaction traversed the complete overlay during Init")
Desired(Scheduler.Pending("data-compaction") ~= nil,
    "pending compaction was not retained by the keyed scheduler")

local edited = assert(Catalog.Get("budget-001"))
edited.title,edited.lastModified = "Edited during compaction",800
Control(Catalog.Put(edited),
    "represented-data edit was refused during incremental compaction")
local pumpGuard = 0
while Compaction.Stats().pending do
    local state = Compaction.Pump()
    pumpGuard = pumpGuard + 1
    Control(state.lastPumpWork <= state.workBudget,
        "compaction pump exceeded its fixed work budget")
    Control(pumpGuard < 2000,"incremental compaction did not converge")
end
local compacted = Compaction.Stats()
Control(compacted.pending == false and compacted.maxPumpWork <= 32
        and compacted.overlayRecordsBefore == 160
        and compacted.overlayRecordsAfter == 160
        and compacted.dpsRecordsBefore == 40
        and compacted.dpsRecordsAfter == 40
        and compacted.restarts >= 1,
    "incremental compaction counters or revision restart were not exact")
Control(NexusDB.dataCompaction.version == 1
        and Scheduler.Pending("data-compaction") == nil,
    "completed compaction retained pending scheduler ownership")
Control(NexusDB.buildFilters == filters
        and NexusDB.syncTombstones == tombstones
        and NexusDB.futureRoot == opaque
        and opaque.nested.keep == "opaque",
    "compaction replaced filters, tombstones, or unknown root ownership")
for index = 1, 160 do
    local id = string.format("budget-%03d",index)
    local raw, hydrated = NexusDB.communityBuilds[id],Catalog.Get(id)
    Control(raw and raw.echoes == nil and raw.futureRow.keep == "row-" .. index
            and raw.ownerKey == "budgetowner@ebonhold"
            and hydrated and hydrated.echoes[1].spellId == 910000 + index,
        "build compaction lost exact evidence, ownership, or unknown fields")
end
for index = 1, 40 do
    local raw = dpsRows["player-" .. index]
    local resolved = Nexus.LoadoutEvidence.ResolveDpsEchoes(raw)
    Control(raw.echoes == nil and raw.ownerVerified == true
            and raw.futureRow.keep == "dps-" .. index
            and resolved and resolved[1].spellId == 920000 + index,
        "DPS compaction lost exact evidence, provenance, or unknown fields")
end
Control(Catalog.Get("budget-001").title == "Edited during compaction",
    "revision restart lost the concurrent exact catalog edit")

local stable = Copy(NexusDB)
Store.Init()
Control(Equal(stable,NexusDB),
    "completed first-run compaction changed bytes on repeated initialization")

local future = {
    loadoutEvidence={schemaVersion=1,entries={}},
    dataCompaction={schemaVersion=99,version=0,future={keep=true}},
    communityBuilds={future={future=true}},futureRoot={keep=true},
}
local futureBefore = Copy(future)
local futureResult = Compaction.Init(future)
Control(futureResult.blocked and Equal(futureBefore,future),
    "future compaction schema was mutated or treated as writable")

local futureCatalog = {
    buildCatalog={schemaVersion=99,future={keep="catalog"}},
    communityBuilds={},dpsCapture={},
    loadoutEvidence={schemaVersion=1,entries={}},
    futureRoot={keep="root"},
}
local futureCatalogBefore = Copy(futureCatalog)
local futureCatalogOwner = futureCatalog.buildCatalog
local futureCatalogResult = Compaction.Init(futureCatalog)
Control(futureCatalogResult.blocked
        and futureCatalogResult.reason == "future catalog schema is read-only"
        and futureCatalog.buildCatalog == futureCatalogOwner
        and rawget(futureCatalog,"dataCompaction") == nil
        and Equal(futureCatalogBefore,futureCatalog),
    "future catalog schema was annotated before read-only refusal")

-- Replacing canonical owner tables between slices must rebind the migration,
-- restart its cursors, and compact the replacement rather than stamping work
-- completed against the abandoned tables.
do
    local initial = {}
    for index = 1,96 do
        local id = "owner-old-" .. index
        initial[id] = {
            id=id,title=id,author="Owner",class="MAGE",
            postedAt=index,lastModified=index,
            fingerprint=tostring(930000+index).."x1",
            echoes={{spellId=930000+index,quality=3,stacks=1}},
        }
    end
    local ownerDb = {
        settingsVersion=2,settings={},chars={},communityBuilds=initial,
        dpsCapture={},futureRoot={keep="owner-root"},
    }
    NexusDB = ownerDb
    Nexus.BundledBuilds = {schemaVersion=1,catalogVersion="owner-rebind",
        sourceVersion="test",builds={}}
    Store.Init()
    Desired(Compaction.Stats().pending == true,
        "owner replacement fixture completed before its bounded yield")

    local replacement = {}
    for index = 1,48 do
        local id = "owner-new-" .. index
        replacement[id] = {
            id=id,title=id,author="Owner",class="MAGE",
            postedAt=index,lastModified=index,
            fingerprint=tostring(940000+index).."x1",
            echoes={{spellId=940000+index,quality=3,stacks=1}},
            futureRow={keep="replacement-"..index},
        }
    end
    local replacementDpsRow = {
        dps=123456,duration=60,ts=1,player="Replacement",class="MAGE",
        fingerprint="950001x1",echoes={{spellId=950001,count=1}},
        ownerVerified=true,futureRow={keep="replacement-dps"},
    }
    local replacementDps = {characterBest={
        dummy={replacement=replacementDpsRow},lk={},
    },futureOwner={keep=true}}
    local replacementEvidence = {
        schemaVersion=1,entries={},futureOwner={keep=true},
    }
    ownerDb.communityBuilds = replacement
    ownerDb.dpsCapture = replacementDps
    ownerDb.loadoutEvidence = replacementEvidence
    Nexus.Revisions.Advance(Nexus.Revisions.BUILD_LIBRARY_CHANGED,
        {scope="owner replacement"})
    Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,
        {scope="owner replacement"})
    local guard = 0
    while Compaction.Stats().pending do
        Compaction.Pump()
        guard = guard + 1
        Control(guard < 1000,"owner replacement migration did not converge")
    end
    local rebound = Compaction.Stats()
    local hydrated = Catalog.Get("owner-new-48")
    Desired(rebound.restarts >= 1 and rebound.overlayRecordsAfter == 48
            and rebound.dpsRecordsAfter == 1,
        "canonical owner replacement was not rebound and restarted")
    Desired(ownerDb.communityBuilds == replacement
            and ownerDb.dpsCapture == replacementDps
            and ownerDb.loadoutEvidence == replacementEvidence
            and replacement["owner-new-48"].echoes == nil
            and replacement["owner-new-48"].futureRow.keep == "replacement-48"
            and hydrated and hydrated.echoes[1].spellId == 940048
            and replacementDpsRow.echoes == nil
            and Nexus.LoadoutEvidence.ResolveDpsEchoes(replacementDpsRow)[1].spellId
                == 950001,
        "rebound owners lost exact evidence, identity, or unknown fields")
end

-- Reference providers are an external callback boundary. Even a provider that
-- mutates an owner without using Catalog/Revisions is captured by the one
-- bounded post-provider verification traversal before the version stamp.
do
    local providerDb = {settingsVersion=2,settings={},chars={},
        communityBuilds={},dpsCapture={},futureRoot={keep="provider"}}
    local inserted = false
    Nexus.LoadoutEvidence.RegisterReferenceProvider(
        "stage36.raw-provider",function()
            if not inserted then
                inserted = true
                providerDb.communityBuilds["provider-row"] = {
                    id="provider-row",title="Provider Row",author="Provider",
                    class="MAGE",postedAt=1,lastModified=1,
                    fingerprint="955001x1",
                    echoes={{spellId=955001,quality=3,stacks=1}},
                }
            end
            return {}
        end)
    NexusDB = providerDb
    Nexus.BundledBuilds = {schemaVersion=1,catalogVersion="provider-boundary",
        sourceVersion="test",builds={}}
    Store.Init()
    local providerGuard = 0
    while Compaction.Stats().pending do
        Compaction.Pump()
        providerGuard = providerGuard + 1
        Control(providerGuard < 1000,"provider verification did not converge")
    end
    Nexus.LoadoutEvidence.RegisterReferenceProvider(
        "stage36.raw-provider",nil)
    local providerRaw = providerDb.communityBuilds["provider-row"]
    local providerHydrated = Catalog.Get("provider-row")
    Desired(inserted and providerDb.dataCompaction.version == 1
            and providerRaw and providerRaw.echoes == nil
            and providerRaw.evidenceKey
            and providerHydrated and providerHydrated.echoes[1].spellId == 955001,
        "post-provider verification stamped an unvisited owner row complete")
end

-- Provider membership is itself versioned. A callback that replaces its own
-- registry entry cannot make one health pass describe a different currently
-- registered provider set and then permit a completion stamp.
do
    local providerDb = {settingsVersion=2,settings={},chars={},
        communityBuilds={},dpsCapture={},futureRoot={keep="provider-generation"}}
    local replaced = false
    Nexus.LoadoutEvidence.RegisterReferenceProvider(
        "stage36.self-replace",function()
            replaced = true
            Nexus.LoadoutEvidence.RegisterReferenceProvider(
                "stage36.self-replace",function()
                    error("replacement provider failure")
                end)
            return {}
        end)
    NexusDB = providerDb
    Nexus.BundledBuilds = {schemaVersion=1,
        catalogVersion="provider-generation",sourceVersion="test",builds={}}
    Store.Init()
    Desired(replaced and not providerDb.dataCompaction.version
            and string.find(tostring(providerDb.dataCompaction.lastError or ""),
                "providers changed",1,true),
        "changing provider registry was stamped from a stale health pass")
    Nexus.LoadoutEvidence.RegisterReferenceProvider(
        "stage36.self-replace",nil)
    Compaction.Init(providerDb)
    local providerGuard = 0
    while Compaction.Stats().pending do
        Compaction.Pump()
        providerGuard = providerGuard + 1
        Control(providerGuard < 1000,
            "provider-generation recovery did not converge")
    end
    Control(providerDb.dataCompaction.version == 1,
        "stable provider registry did not resume to completion")
end

-- A failing provider may itself hand compaction metadata to a future owner.
-- The failure path must revalidate ownership before recording lastError or
-- clearing the in-progress marker in that now read-only table.
do
    local rows = {}
    for index = 1,48 do
        local id = "provider-future-" .. index
        rows[id] = {id=id,title=id,author="Provider",class="MAGE",
            postedAt=index,lastModified=index,fingerprint="",
            futureRow={keep=index}}
    end
    local providerDb = {settingsVersion=2,settings={},chars={},
        communityBuilds=rows,dpsCapture={},futureRoot={keep="provider-future"}}
    local futureSnapshot, futureMeta
    Nexus.LoadoutEvidence.RegisterReferenceProvider(
        "stage36.provider-future",function()
            providerDb.dataCompaction.schemaVersion = 99
            providerDb.dataCompaction.future = {keep="provider-owned"}
            futureMeta = providerDb.dataCompaction
            futureSnapshot = Copy(providerDb)
            error("provider promoted compaction metadata")
        end)
    NexusDB = providerDb
    Nexus.BundledBuilds = {schemaVersion=1,
        catalogVersion="provider-future",sourceVersion="test",builds={}}
    Store.Init()
    local futureGuard = 0
    while not futureSnapshot and Compaction.Stats().pending do
        Compaction.Pump()
        futureGuard = futureGuard + 1
        Control(futureGuard < 1000,
            "future-provider failure did not reach its health boundary")
    end
    Nexus.LoadoutEvidence.RegisterReferenceProvider(
        "stage36.provider-future",nil)
    Desired(futureSnapshot and providerDb.dataCompaction == futureMeta
            and providerDb.dataCompaction.schemaVersion == 99
            and providerDb.dataCompaction.future.keep == "provider-owned"
            and providerDb.dataCompaction.lastError == nil
            and Equal(providerDb,futureSnapshot),
        "provider failure mutated future compaction metadata")
end

-- The provider registry can also change while the bounded verification scan is
-- yielding after a successful health check. Its generation is revalidated on
-- every pump, so a newly failing provider prevents the later completion stamp.
do
    local rows = {}
    for index = 1,96 do
        local id = "provider-late-" .. index
        rows[id] = {
            id=id,title=id,author="Provider",class="MAGE",
            postedAt=index,lastModified=index,
            fingerprint=tostring(956000+index).."x1",
            echoes={{spellId=956000+index,quality=3,stacks=1}},
        }
    end
    local providerDb = {settingsVersion=2,settings={},chars={},
        communityBuilds=rows,dpsCapture={},futureRoot={keep="provider-late"}}
    local healthChecks = 0
    Nexus.LoadoutEvidence.RegisterReferenceProvider(
        "stage36.provider-stable",function()
            healthChecks = healthChecks + 1
            return {}
        end)
    NexusDB = providerDb
    Nexus.BundledBuilds = {schemaVersion=1,catalogVersion="provider-late",
        sourceVersion="test",builds={}}
    Store.Init()
    local firstGuard = 0
    while healthChecks == 0 do
        Compaction.Pump()
        firstGuard = firstGuard + 1
        Control(firstGuard < 1000,
            "provider verification did not reach its health boundary")
    end
    Control(Compaction.Stats().pending == true,
        "provider verification did not yield after its health boundary")
    Nexus.LoadoutEvidence.RegisterReferenceProvider(
        "stage36.provider-late-failure",function()
            error("late provider failure")
        end)
    local lateGuard = 0
    while Compaction.Stats().pending do
        Compaction.Pump()
        lateGuard = lateGuard + 1
        Control(lateGuard < 1000,
            "late provider mutation did not reach a terminal result")
    end
    Desired(not providerDb.dataCompaction.version
            and string.find(tostring(providerDb.dataCompaction.lastError or ""),
                "provider failed",1,true),
        "provider registered after health was omitted from the completion gate")
    Nexus.LoadoutEvidence.RegisterReferenceProvider(
        "stage36.provider-stable",nil)
    Nexus.LoadoutEvidence.RegisterReferenceProvider(
        "stage36.provider-late-failure",nil)
    Compaction.Init(providerDb)
    local recoveryGuard = 0
    while Compaction.Stats().pending do
        Compaction.Pump()
        recoveryGuard = recoveryGuard + 1
        Control(recoveryGuard < 1000,
            "late provider recovery did not converge")
    end
    Control(providerDb.dataCompaction.version == 1,
        "stable provider generation did not resume to completion")
end

-- A future owner appearing between slices is a non-mutating stop, not a
-- partially completed migration stamp. Restoring the supported schema can
-- resume the already-idempotent rows to completion.
do
    local function Rows(prefix)
        local rows = {}
        for index = 1,96 do
            local id = prefix .. index
            rows[id] = {
                id=id,title=id,author="Future",class="MAGE",
                postedAt=index,lastModified=index,
                fingerprint=tostring(960000+index).."x1",
                echoes={{spellId=960000+index,quality=3,stacks=1}},
            }
        end
        return rows
    end
    local schemaDb = {settingsVersion=2,settings={},chars={},
        communityBuilds=Rows("future-meta-"),dpsCapture={},
        futureRoot={keep="future-meta"}}
    NexusDB = schemaDb
    Nexus.BundledBuilds = {schemaVersion=1,catalogVersion="future-midflight",
        sourceVersion="test",builds={}}
    Store.Init()
    Control(Compaction.Stats().pending == true,
        "future metadata fixture completed before its bounded yield")
    schemaDb.dataCompaction.schemaVersion = 99
    schemaDb.dataCompaction.futureOwner = {keep=true}
    local metaAtBoundary = Copy(schemaDb)
    local stoppedMeta = Compaction.Pump()
    Desired(stoppedMeta.blocked and not schemaDb.dataCompaction.version
            and Equal(metaAtBoundary,schemaDb),
        "mid-flight future compaction owner was mutated or stamped complete")
    schemaDb.dataCompaction.schemaVersion = 1
    Compaction.Init(schemaDb)
    local metaGuard = 0
    while Compaction.Stats().pending do
        Compaction.Pump()
        metaGuard = metaGuard + 1
        Control(metaGuard < 1000,"restored compaction owner did not resume")
    end
    Control(schemaDb.dataCompaction.version == 1,
        "restored compaction owner did not complete")

    local evidenceDb = {settingsVersion=2,settings={},chars={},
        communityBuilds=Rows("future-evidence-"),dpsCapture={},
        futureRoot={keep="future-evidence"}}
    NexusDB = evidenceDb
    Nexus.BundledBuilds = {schemaVersion=1,catalogVersion="future-evidence",
        sourceVersion="test",builds={}}
    Store.Init()
    Control(Compaction.Stats().pending == true,
        "future evidence fixture completed before its bounded yield")
    evidenceDb.loadoutEvidence.schemaVersion = 99
    evidenceDb.loadoutEvidence.futureOwner = {keep=true}
    local evidenceAtBoundary = Copy(evidenceDb)
    local stoppedEvidence = Compaction.Pump()
    Desired(stoppedEvidence.blocked and not evidenceDb.dataCompaction.version
            and Equal(evidenceAtBoundary,evidenceDb),
        "mid-flight future evidence owner was mutated or stamped complete")
end

-- Exhausting a deeply nested DFS stack is charged one edge/pop per work unit.
-- The former inner unwind loop could perform hundreds of next() calls while
-- reporting a small bounded slice.
do
    local nested, cursor = {}, nil
    cursor = nested
    for _ = 1,400 do
        cursor.child = {}
        cursor = cursor.child
    end
    local deepDb = {settingsVersion=2,settings={},chars={},
        communityBuilds={},dpsCapture=nested,futureRoot={keep="deep"}}
    NexusDB = deepDb
    Nexus.BundledBuilds = {schemaVersion=1,catalogVersion="deep-budget",
        sourceVersion="test",builds={}}
    Store.Init()
    local realNext, maxNextCalls, deepGuard = next,0,0
    while Compaction.Stats().pending do
        local calls = 0
        next = function(...)
            calls = calls + 1
            return realNext(...)
        end
        local ok, state = pcall(Compaction.Pump)
        next = realNext
        Control(ok,"deep compaction pump escaped its failure boundary")
        Control(state.lastPumpWork <= state.workBudget,
            "deep compaction reported work above its budget")
        maxNextCalls = math.max(maxNextCalls,calls)
        deepGuard = deepGuard + 1
        Control(deepGuard < 1000,"deep compaction did not converge")
    end
    next = realNext
    Desired(maxNextCalls <= 32
            and deepDb.dataCompaction.version == 1,
        "deep DFS traversal exceeded its declared per-pump work budget")
end

local summary = string.format(
    "desired=%d expected_red=%d controls=%d idle_scans=%d idle_sorts=%d not_due_scans=%d not_due_sorts=%d cap=%d compaction_pumps=%d max_work=%d restarts=%d",
    desiredCount,#failures,controls,idleScans,idleSorts,
    futureScans,futureSorts,Scheduler.MaxCallbacksPerTick(),
    compacted.pumps,compacted.maxPumpWork,compacted.restarts)
if #failures > 0 then
    error("EXPECTED RED [Stage 36.6 scheduler allocation]: "
        .. table.concat(failures, "; ") .. " -- " .. summary, 0)
end
print("stage36 scheduler allocation budget: " .. summary .. " -- OK")
