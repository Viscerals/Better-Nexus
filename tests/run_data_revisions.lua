local H = dofile("tests/harness.lua")

-- The bus starts deterministically, dispatches in subscription order, and
-- isolates a failing callback. Subscribers added mid-dispatch start next time.
dofile("core/Revisions.lua")
local R = Nexus.Revisions
for _, event in ipairs(R.Events()) do assert(R.Get(event) == 0) end
local order = {}
R.Subscribe(R.BUILD_LIBRARY_CHANGED, function()
    order[#order + 1] = "first"
    R.Subscribe(R.BUILD_LIBRARY_CHANGED, function()
        order[#order + 1] = "late"
    end)
end)
R.Subscribe(R.BUILD_LIBRARY_CHANGED, function()
    order[#order + 1] = "failing"
    error("subscriber failure")
end)
R.Subscribe(R.BUILD_LIBRARY_CHANGED, function()
    order[#order + 1] = "last"
end)
assert(R.Advance(R.BUILD_LIBRARY_CHANGED, "direct") == 1)
assert(table.concat(order, ",") == "first,failing,last",
    "subscriber order changed or mid-dispatch subscriber ran early")
order = {}
assert(R.Advance(R.BUILD_LIBRARY_CHANGED, "second") == 2)
assert(table.concat(order, ",") == "first,failing,last,late",
    "subscriber order was not deterministic on the next event")

-- Build-library revisions observe merged represented data, not writes that
-- leave the selected row identical or hidden.
dofile("core/Revisions.lua")
R = Nexus.Revisions
dofile("core/BuildCatalog.lua")
local Catalog = Nexus.BuildCatalog
local baseline = {
    id="base",title="Baseline",description="",author="Release",class="MAGE",
    postedAt=1,lastModified=1,echoes={{spellId=1,quality=3,stacks=1}},
}
NexusDB = {communityBuilds={},syncTombstones={}}
local bundle = {
    schemaVersion=1,catalogVersion="revision-test",sourceVersion="test",
    builds={base=baseline},
}
Catalog.Init(NexusDB, bundle)
assert(R.Get(R.BUILD_LIBRARY_CHANGED) == 1,
    "initial represented build library did not advance once")
Catalog.Init(NexusDB, bundle)
Catalog.Get("base"); Catalog.All(); Catalog.Count()
assert(R.Get(R.BUILD_LIBRARY_CHANGED) == 1,
    "catalog reads or same-content initialization advanced the revision")
assert(Catalog.Put(baseline))
assert(R.Get(R.BUILD_LIBRARY_CHANGED) == 1,
    "baseline-equivalent put advanced the build revision")

local callbacks = {}
R.Subscribe(R.BUILD_LIBRARY_CHANGED, function()
    callbacks[#callbacks + 1] = "bad"
    error("build subscriber failure")
end)
R.Subscribe(R.BUILD_LIBRARY_CHANGED, function(_, revision)
    callbacks[#callbacks + 1] = "good-" .. revision
end)
local changed = {
    id="base",title="Changed",description="",author="Release",class="MAGE",
    postedAt=1,lastModified=2,echoes={{spellId=1,quality=3,stacks=1}},
}
assert(Catalog.Put(changed))
assert(Catalog.Get("base").title == "Changed"
    and R.Get(R.BUILD_LIBRARY_CHANGED) == 2
    and table.concat(callbacks, ",") == "bad,good-2",
    "subscriber failure broke or reordered the originating build mutation")
assert(Catalog.Put(changed) and R.Get(R.BUILD_LIBRARY_CHANGED) == 2,
    "duplicate build put advanced the revision")
assert(Catalog.SetTombstone("base", {stamp=3,author="Release"})
    and R.Get(R.BUILD_LIBRARY_CHANGED) == 3,
    "visible tombstone did not advance once")
assert(Catalog.SetTombstone("base", {stamp=4,author="Release"})
    and R.Get(R.BUILD_LIBRARY_CHANGED) == 4,
    "newer tombstone metadata did not advance Sync-facing build data")
assert(Catalog.SetTombstone("base", {stamp=4,author="Release"})
    and R.Get(R.BUILD_LIBRARY_CHANGED) == 4,
    "duplicate tombstone metadata advanced the build revision")
assert(Catalog.ClearTombstone("base")
    and R.Get(R.BUILD_LIBRARY_CHANGED) == 5,
    "clearing a baseline tombstone did not restore one visible revision")
assert(not Catalog.RemoveOverlay("missing")
    and R.Get(R.BUILD_LIBRARY_CHANGED) == 5,
    "missing overlay removal advanced the revision")

-- A release catalog token is Sync-facing represented identity even when its
-- visible rows are byte-identical.
dofile("core/Revisions.lua")
R = Nexus.Revisions
Catalog.Init(NexusDB, bundle)
assert(R.Get(R.BUILD_LIBRARY_CHANGED) == 0)
local retokened = {
    schemaVersion=1,catalogVersion="revision-test-2",sourceVersion="test",
    builds={base=baseline},
}
Catalog.Init(NexusDB, retokened)
assert(R.Get(R.BUILD_LIBRARY_CHANGED) == 1,
    "catalog identity change did not advance the build revision")

-- DPS revisions advance for a winning row and later metadata enrichment,
-- never for duplicates, rejects, timers, or debug visibility.
dofile("core/Revisions.lua")
R = Nexus.Revisions
dofile("core/DpsCapture.lua")
local DPS = Nexus.DpsCapture
time = function() return 50000 end
UnitName = function() return "Local" end
GetNormalizedRealmName = function() return "Ebonhold" end
NexusDB.dpsCapture = {}
Nexus.CommunityBuilds = nil
DPS.Init({}, {})
assert(R.Get(R.DPS_CHANGED) == 0, "empty DPS initialization advanced revision")
local echoes = {{spellId=200200,stacks=2}}
local fingerprint = DPS.GetEchoKey(echoes)
local record = {
    v=7,f=fingerprint,h=DPS.GetEchoHash(echoes),e=echoes,
    c="dummy",d=25000,u=60,t=40000,p="Peer",l=80,k="MAGE",
}
assert(DPS.ReceiveRecord(record, "Peer")
    and R.Get(R.DPS_CHANGED) == 1,
    "winning DPS record did not advance once")
local identityRows = DPS.GetLeaderboardForIdentity(
    "unrelated-id", fingerprint, DPS.GetEchoHash(echoes), "dummy")
assert(identityRows[1] and identityRows[1].dps == 25000,
    "lightweight DPS identity lookup changed exact fingerprint matching")
local identityStats = DPS.IdentityLookupStats()
assert(identityStats.rebuilds == 1 and identityStats.rowsScanned == 1
    and identityStats.lookups == 1 and identityStats.candidateChecks <= 1,
    "first DPS identity lookup did not build one bounded revision index")
for _ = 1, 100 do
    local repeated = DPS.GetLeaderboardForIdentity(
        "unrelated-id", fingerprint, DPS.GetEchoHash(echoes), "dummy")
    assert(repeated[1] and repeated[1].dps == 25000)
end
local repeatedStats = DPS.IdentityLookupStats()
assert(repeatedStats.rebuilds == identityStats.rebuilds
    and repeatedStats.rowsScanned == identityStats.rowsScanned
    and repeatedStats.lookups == identityStats.lookups + 100,
    "repeated DPS identity lookups rescanned the leaderboard store")
assert(not DPS.ReceiveRecord(record, "Peer")
    and R.Get(R.DPS_CHANGED) == 1,
    "duplicate DPS record advanced the revision")
local enriched = {}
for key, value in pairs(record) do enriched[key] = value end
enriched.o, enriched.r = "peer@ebonhold", "ebonhold"
enriched.lk = {{spellId=200999,stacks=1}}
assert(DPS.ReceiveRecord(enriched, "Peer")
    and R.Get(R.DPS_CHANGED) == 2,
    "same-record metadata enrichment did not advance once")
local enrichedRows = DPS.GetLeaderboardForIdentity(
    "unrelated-id", fingerprint, DPS.GetEchoHash(echoes), "dummy")
local enrichedStats = DPS.IdentityLookupStats()
assert(enrichedRows[1] and enrichedRows[1].dps == 25000
    and enrichedStats.rebuilds == repeatedStats.rebuilds + 1
    and enrichedStats.rowsScanned == repeatedStats.rowsScanned + 1,
    "DPS identity index did not invalidate exactly once after a revision")
assert(not DPS.ReceiveRecord(enriched, "Peer")
    and R.Get(R.DPS_CHANGED) == 2,
    "duplicate enriched DPS record advanced the revision")
local rejected = {}
for key, value in pairs(record) do rejected[key] = value end
rejected.u = 0
assert(not DPS.ReceiveRecord(rejected, "Peer"))
DPS.ClearDebugLog()
local dpsBeforeTimer = R.Get(R.DPS_CHANGED)
DPS.OnCombatStart()
DPS.OnUpdate(5)
DPS.OnCombatEnd()
assert(R.Get(R.DPS_CHANGED) == 2,
    "rejected DPS, timers, or debug visibility advanced the revision")
assert(dpsBeforeTimer == 2)

-- Additive local identity repair is represented DPS data even when class was
-- already correct; owner/realm fills must invalidate consumers exactly once.
dofile("core/Revisions.lua")
R = Nexus.Revisions
dofile("core/DpsCapture.lua")
DPS = Nexus.DpsCapture
local localRow = {
    dps=30000,level=80,ts=40001,duration=60,player="Local",class="MAGE",
    ownerKey="local@ebonhold",realm="ebonhold",fingerprint="200200x2",
    ownerVerified=true,echoes={{spellId=200200,count=2}},protocolVersion=7,
}
local personalRow = {
    dps=30000,level=80,ts=40001,duration=60,player="Local",class="MAGE",
    ownerKey="local@ebonhold",ownerVerified=true,
    fingerprint="200200x2",echoes={{spellId=200200,count=2}},protocolVersion=7,
}
NexusDB.dpsCapture = {
    characterBest={dummy={["local"]=localRow},lk={}},
    personalBest={["200200x2"]={dummy=personalRow}},
    buildBest={},
}
DPS.Init({}, {})
assert(R.Get(R.DPS_CHANGED) == 1
    and personalRow.ownerKey == "local@ebonhold"
    and personalRow.realm == "ebonhold",
    "local DPS owner/realm repair changed data without one revision")

-- Sync revisions represent peer identity/version changes; last-seen timers,
-- duplicate packets, logs, queue work, and rejected traffic are status only.
dofile("core/Revisions.lua")
R = Nexus.Revisions
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
local Sync = Nexus.Sync
NexusDB.communityBuilds = NexusDB.communityBuilds or {}
NexusDB.syncTombstones = NexusDB.syncTombstones or {}
Sync.Init(Nexus.Codec, {})
assert(Sync.HandleIncoming("WLNP|Peer|1.0.0", "Peer")
    and R.Get(R.SYNC_CHANGED) == 1,
    "new accepted peer did not advance Sync revision")
assert(Sync.HandleIncoming("WLNP|Peer|1.0.0", "Peer")
    and R.Get(R.SYNC_CHANGED) == 1,
    "duplicate presence/last-seen update advanced Sync revision")
assert(Sync.HandleIncoming("WLNP|Peer|1.1.0", "Peer")
    and R.Get(R.SYNC_CHANGED) == 2,
    "peer version change did not advance Sync revision")
assert(not Sync.HandleIncoming("WLNP|Peer|1..2", "Peer")
    and not Sync.HandleIncoming("WLNP|Declared|2.0.0", "Different"))
Sync.LogRaw("status only")
Sync.OnUpdate(1)
assert(R.Get(R.SYNC_CHANGED) == 2,
    "rejected traffic, logs, queues, or timers advanced Sync revision")
assert(R.Get(R.BUILD_LIBRARY_CHANGED) == 0
    and R.Get(R.DPS_CHANGED) == 0 and R.Get(R.CATALOG_CHANGED) == 0,
    "presence/status traffic advanced an unrelated data revision")

-- The Project Ebonhold Echo catalog advances exactly on its first successful
-- represented build, not on repeated reads.
dofile("core/Revisions.lua")
R = Nexus.Revisions
dofile("core/GameAdapter.lua")
local Adapter = Nexus.GameAdapter
local firstCatalog = Adapter.Catalog()
assert(firstCatalog and R.Get(R.CATALOG_CHANGED) == 1,
    "first Echo catalog build did not advance once")
assert(Adapter.Catalog() == firstCatalog
    and R.Get(R.CATALOG_CHANGED) == 1,
    "cached Echo catalog read advanced the revision")

print("build, DPS, Sync, and Echo-catalog revisions advance only on represented changes -- OK")
