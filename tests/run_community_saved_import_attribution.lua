-- Bounded aggregate attribution for the live-scale Community saved-import
-- path. This fixture observes ownership only; it does not optimize cadence,
-- force collection, retain packet/frame samples, or mutate Sync semantics.
local H = dofile("tests/harness.lua")
dofile("ui/Theme.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

UnitName = function() return "AttributionMage" end
GetNormalizedRealmName = function() return "Ebonhold" end

local function BuildEchoes(index, count, shared)
    local rows = {}
    if shared then
        for offset = 1, math.min(6, count) do
            rows[#rows + 1] = {
                spellId=910000 + offset,quality=3,stacks=1,
            }
        end
    end
    while #rows < count do
        rows[#rows + 1] = {
            spellId=1000000 + (index * 100) + #rows,
            quality=(index + #rows) % 4,stacks=1,
        }
    end
    return rows
end

NexusDB = {
    communityBuilds={},buildFilters={scope="all",sortMode="title"},
    dpsCapture={characterBest={dummy={},lk={}},personalBest={},buildBest={}},
}
local projectedEchoRows = 0
for index = 1, 568 do
    local echoCount = index <= 428 and 66 or 65
    local collision = index <= 80
    local id = string.format("attribution-%04d", index)
    local echoes = BuildEchoes(index, echoCount, collision)
    projectedEchoRows = projectedEchoRows + #echoes
    NexusDB.communityBuilds[id] = {
        id=id,
        title=collision and "Saved Collision"
            or string.format("Attribution Build %04d", index),
        author=collision and "AttributionMage" or "Other",
        ownerKey=collision and "attributionmage@ebonhold"
            or "other@ebonhold",
        ownerVerified=collision and true or nil,
        realm=collision and "ebonhold" or nil,
        class="MAGE",postedAt=index,lastModified=index,echoes=echoes,
    }
end
assert(projectedEchoRows == 37348,
    "attribution fixture did not preserve the anonymized Echo-row scale")

for index = 1, 595 do
    local category = index <= 568 and "dummy" or "lk"
    local buildIndex = ((index - 1) % 568) + 1
    local buildId = string.format("attribution-%04d", buildIndex)
    NexusDB.dpsCapture.characterBest[category][category.."player"..index] = {
        player=category.."Player"..index,dps=100000+index,
        level=80,ts=index,duration=60,class="MAGE",buildId=buildId,
        echoes={{spellId=910001,count=1}},protocolVersion=7,
    }
end

Nexus.Store.Init()
dofile("core/DpsCapture.lua")
Nexus.DpsCapture.Init({}, {})
for _, category in ipairs({"dummy", "lk"}) do
    for _, row in pairs(NexusDB.dpsCapture.characterBest[category]) do
        local build = assert(Nexus.BuildCatalog.Get(row.buildId))
        row.fingerprint = assert(build.fingerprint
            or Nexus.DpsCapture.GetEchoKey(build.echoes))
    end
end
-- Stage 36.6 makes first-run evidence compaction resumable. This fixture
-- characterizes the already-migrated saved-import path, so finish that bounded
-- owner before capturing catalog compaction/reference attribution.
local compactionGuard = 0
while Nexus.DataCompaction.Stats().pending do
    local state = Nexus.DataCompaction.Pump()
    assert(state.lastPumpWork <= state.workBudget,
        "saved-import setup exceeded the compaction work budget")
    compactionGuard = compactionGuard + 1
    assert(compactionGuard < 10000,
        "saved-import setup compaction did not converge")
end

local slots = {activeSlot=1,bySlot={}}
for slot = 1, 4 do
    local echoes = {}
    for offset = 1, 6 do
        echoes[#echoes + 1] = {
            spellId=(slot == 1 and 910000 or 920000 + slot * 100) + offset,
            quality=3,stacks=1,locked=false,
        }
    end
    slots.bySlot[slot] = {
        name=slot == 1 and "Saved Collision" or ("Saved Scale " .. slot),
        class="MAGE",echoes=echoes,
    }
end

local wishlistEchoes = {}
for index = 1, 79 do
    wishlistEchoes[#wishlistEchoes + 1] = {
        spellId=930000+index,quality=index%4,stacks=1,locked=false,
    }
end
for index = 1, 6 do
    wishlistEchoes[#wishlistEchoes + 1] = {
        spellId=931000+index,quality=3,stacks=1,locked=true,
    }
end
local wishlist = {
    slot=102,name="Scale Wishlist",echoes=wishlistEchoes,
    lockEvidenceVersion=1,
}

local slotGeneration = 1
local Adapter = {
    Slots=function() return slots end,
    EchoReconcileStats=function()
        return {generations={slots=slotGeneration}}
    end,
    GetLoadoutWishlist=function(slot)
        return tonumber(slot) == 1 and wishlist or nil
    end,
    Owned=function() return {bySpell={}} end,
}

local receiving, receiveCount = true, 0
Nexus.Sync = {
    IsReceiving=function() return receiving end,
    LastSyncNewCount=function() return receiveCount end,
    ReceiveTimeLeft=function() return receiving and 3 or 0 end,
    Stats=function() return {received=receiveCount} end,
    RequestSync=function() return true end,
}

local fullReads = 0
local originalAll = Nexus.BuildCatalog.All
Nexus.BuildCatalog.All = function(...)
    fullReads = fullReads + 1
    return originalAll(...)
end

dofile("ui/CommunityBuilds.lua")
local Community = Nexus.CommunityBuilds
Community.Init(Adapter, nil)
Nexus.Performance.Reset()
local clock = 0
Nexus.Performance.SetClock(function()
    clock = clock + 2
    return clock
end)
Nexus.Performance.InstallDefaults()
fullReads = 0

local function CopyStats()
    local source = Community.VirtualStats().savedImport
    local out = {}
    for key, value in pairs(source) do out[key] = value end
    return out
end

local function Delta(after, before, key)
    return (tonumber(after[key]) or 0) - (tonumber(before[key]) or 0)
end

local zero = CopyStats()
Community.Show()
local frame = assert(NexusCommunityBuildsFrame,
    "Community frame was not assembled for attribution")
local onUpdate = assert(frame:GetScript("OnUpdate"),
    "Community frame did not expose its bounded pump")
local deferred = CopyStats()
assert(deferred.pending and Delta(deferred, zero, "syncDeferrals") >= 1
    and Delta(deferred, zero, "workUnits") == 0,
    "active Sync was not a zero-work saved-import deferral")

-- A Sync-owned library revision lands while the saved import is deferred.
-- The saved-import job must attribute its later restart to that indirect
-- source revision without claiming Sync performed the import work.
assert(Nexus.BuildCatalog.Put({
    id="sync-attribution",title="Synced Attribution",author="Peer",
    ownerKey="peer@ebonhold",class="MAGE",postedAt=9000,
    lastModified=9000,echoes={{spellId=990001,quality=3,stacks=1}},
}))
receiveCount = 1
receiving = false
onUpdate(frame, 0.25)
assert(Community.VirtualStats().savedImport.pending,
    "collision-heavy source completed before restart attribution")

-- A later semantic slot generation changes independently. This is a second
-- source restart, not a packet log and not direct Sync ownership.
slotGeneration = slotGeneration + 1
onUpdate(frame, 0.25)
local pumps = 2
while Community.VirtualStats().savedImport.pending and pumps < 40 do
    onUpdate(frame, 0.25)
    pumps = pumps + 1
end
for _ = 1, 160 do
    if (Community.VirtualStats().dataBinds or 0) >= 1 then break end
    onUpdate(frame, 0.05)
end

local cold = CopyStats()
local virtual = Community.VirtualStats()
local savedTiming = Nexus.Performance.Stats("community.saved-import")
assert(not cold.pending and cold.pendingPhase == nil
    and cold.jobs == 1 and cold.jobStarts == 3
    and cold.sourceRevisionRestarts == 2
    and cold.buildRevisionRestarts == 1
    and cold.slotGenerationRestarts == 1
    and cold.cursorRestarts == 0
    and cold.maxCandidatesPerPump <= 25
    and cold.maxWorkPerPump <= 25
    and cold.slotPreparations >= 4
    and cold.wishlistDiscoveryReads == cold.slotPreparations
    and cold.wishlistDiscoveries >= 1
    and cold.wishlistDiscoveries < cold.wishlistDiscoveryReads
    and cold.candidateAdvances >= cold.candidates
    and cold.finalizations == 4
    and cold.catalogPuts == 4 and cold.catalogPutCalls == 4
    and cold.catalogPutChanges == 4 and cold.writes == 4
    and cold.compactionCalls == 4
    and cold.compactionWrites == 0
    and cold.referenceCalls == 0 and cold.referenceStores == 0
    and cold.relatedIndexUpdates == 4
    and cold.cleanupEnumerations == 1
    and cold.cleanupCandidates == 4
    and cold.cleanupExamined == 4
    and cold.cleanupRemovals == 0
    and cold.completions == 1,
    string.format("saved-import attribution mismatch: jobs=%s starts=%s source=%s/%s/%s cursor=%s pumps=%s max=%s/%s prep=%s discovery=%s/%s advances=%s candidates=%s final=%s puts=%s/%s/%s writes=%s compaction=%s/%s references=%s/%s index=%s cleanup=%s/%s/%s/%s complete=%s pending=%s",
        tostring(cold.jobs),tostring(cold.jobStarts),
        tostring(cold.sourceRevisionRestarts),
        tostring(cold.buildRevisionRestarts),
        tostring(cold.slotGenerationRestarts),tostring(cold.cursorRestarts),
        tostring(cold.pumps),tostring(cold.maxCandidatesPerPump),
        tostring(cold.maxWorkPerPump),tostring(cold.slotPreparations),
        tostring(cold.wishlistDiscoveryReads),
        tostring(cold.wishlistDiscoveries),tostring(cold.candidateAdvances),
        tostring(cold.candidates),tostring(cold.finalizations),
        tostring(cold.catalogPuts),tostring(cold.catalogPutCalls),
        tostring(cold.catalogPutChanges),tostring(cold.writes),
        tostring(cold.compactionCalls),tostring(cold.compactionWrites),
        tostring(cold.referenceCalls),tostring(cold.referenceStores),
        tostring(cold.relatedIndexUpdates),
        tostring(cold.cleanupEnumerations),
        tostring(cold.cleanupCandidates),tostring(cold.cleanupExamined),
        tostring(cold.cleanupRemovals),tostring(cold.completions),
        tostring(cold.pending)))
assert(fullReads == 0 and virtual.dataRefreshes >= 1
    and virtual.dataBinds >= 1 and virtual.results <= 20
    and savedTiming.count >= cold.pumps,
    string.format("attribution added a full read or missed saved-import/view boundaries: fullReads=%s refreshes=%s binds=%s results=%s savedTiming=%s pumps=%s",
        tostring(fullReads),tostring(virtual.dataRefreshes),
        tostring(virtual.dataBinds),tostring(virtual.results),
        tostring(savedTiming.count),tostring(cold.pumps)))

local beforeWarm = CopyStats()
local revisionBeforeWarm = Nexus.Revisions.Get(
    Nexus.Revisions.BUILD_LIBRARY_CHANGED)
Community.Show()
local warmPumps = 0
while Community.VirtualStats().savedImport.pending and warmPumps < 40 do
    onUpdate(frame, 0.25)
    warmPumps = warmPumps + 1
end
local warm = CopyStats()
assert(Delta(warm, beforeWarm, "jobs") == 1
    and Delta(warm, beforeWarm, "sourceRevisionRestarts") == 0
    and Delta(warm, beforeWarm, "catalogPuts") == 0
    and Delta(warm, beforeWarm, "writes") == 0
    and Delta(warm, beforeWarm, "compactionCalls") == 0
    and Delta(warm, beforeWarm, "cleanupEnumerations") == 1
    and not warm.pending
    and Nexus.Revisions.Get(Nexus.Revisions.BUILD_LIBRARY_CHANGED)
        == revisionBeforeWarm and fullReads == 0,
    "warm unchanged import hid a restart, write, compaction, revision, or full read")

-- Outside the compacted saved-import path, distinguish a fallback reference
-- call from a newly stored canonical entry. Reusing identical evidence must
-- add a second call without claiming a second store.
local fallbackBefore = Nexus.BuildCatalog.DebugStats()
NexusDB.dataCompaction = nil
local fallbackEchoes = {{spellId=999991,quality=3,stacks=1}}
assert(Nexus.BuildCatalog.Put({
    id="fallback-reference-a",title="Fallback Reference A",author="Peer",
    ownerKey="peer@ebonhold",class="MAGE",postedAt=9100,
    lastModified=9100,echoes=fallbackEchoes,
}))
assert(Nexus.BuildCatalog.Put({
    id="fallback-reference-b",title="Fallback Reference B",author="Peer",
    ownerKey="peer@ebonhold",class="MAGE",postedAt=9101,
    lastModified=9101,echoes=fallbackEchoes,
}))
local fallbackAfter = Nexus.BuildCatalog.DebugStats()
assert((fallbackAfter.referenceCalls - fallbackBefore.referenceCalls) == 2
    and (fallbackAfter.referenceStores - fallbackBefore.referenceStores) == 1,
    "fallback reference reuse was counted as a second canonical store")

print(string.format(
    "saved-import attribution: builds=568 dps=595 echoes=37348 jobs=%d starts=%d pumps=%d work=%d maxWork=%d restarts=%d source=%d(build=%d slots=%d) candidates=%d maxCandidates=%d finalizations=%d puts=%d writes=%d compaction=%d/%d references=%d/%d cleanup=%d/%d/%d completions=%d syncDeferrals=%d viewRefreshes=%d warmWrites=0 fullReads=0 -- OK",
    cold.jobs,cold.jobStarts,cold.pumps,cold.workUnits,cold.maxWorkPerPump,
    cold.restarts,cold.sourceRevisionRestarts,cold.buildRevisionRestarts,
    cold.slotGenerationRestarts,cold.candidates,cold.maxCandidatesPerPump,
    cold.finalizations,cold.catalogPuts,cold.writes,cold.compactionCalls,
    cold.compactionWrites,cold.referenceCalls,cold.referenceStores,
    cold.cleanupEnumerations,
    cold.cleanupCandidates,cold.cleanupExamined,cold.completions,
    cold.syncDeferrals,virtual.dataRefreshes))
