-- Stage 32.2: recover complete legacy exact identities without rewriting a
-- reused build ID or granting authority. The fixture exceeds 200 recoveries
-- so implementation limits cannot silently become storage caps.
local H = dofile("tests/harness.lua")

UnitName = function() return "LocalFixture" end
GetNormalizedRealmName = function() return "FixtureRealm" end
UnitClass = function() return "Mage", "MAGE" end

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, child in pairs(value) do out[Copy(key, seen)] = Copy(child, seen) end
    return out
end

local function Snapshot(value, seen)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local keys, out = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        if type(left) ~= type(right) then return type(left) < type(right) end
        return tostring(left) < tostring(right)
    end)
    for _, key in ipairs(keys) do
        out[#out + 1] = Snapshot(key, seen) .. "=" .. Snapshot(value[key], seen)
    end
    seen[value] = nil
    return "{" .. table.concat(out, ",") .. "}"
end

local function Count(source)
    local total = 0
    for _ in pairs(source or {}) do total = total + 1 end
    return total
end

local function Echoes(base)
    return {{spellId=base,count=1},{spellId=base+1,count=2}}
end

local function Fingerprint(base)
    return tostring(base) .. "x1," .. tostring(base+1) .. "x2"
end

local function HashText(value, seed)
    local hash = seed
    for index = 1, #value do
        hash = (hash * 33 + value:byte(index)) % 2147483648
    end
    return string.format("%x", hash)
end

local function HistoricalId(fingerprint)
    return "legacy-dps-" .. HashText(fingerprint, 5381)
        .. "-" .. HashText(fingerprint, 216613626)
end

local function Build(id, fingerprint, echoes, fields)
    local row = {
        id=id,title="Current collision",description="current data",
        author="CurrentPeer",ownerKey="currentpeer@fixturerealm",
        ownerVerified=true,class="MAGE",fingerprint=fingerprint,
        echoes=Copy(echoes),echoCount=3,loadoutAvailable=true,
        postedAt=5000,lastModified=5000,futureBuildField={keep=true},
    }
    for key, value in pairs(fields or {}) do row[key] = value end
    return row
end

local function DpsRow(player, category, buildId, fingerprint, echoes, fields)
    local row = {
        player=player,category=category,buildId=buildId,
        fingerprint=fingerprint,echoes=echoes and Copy(echoes) or nil,
        dps=category == "dummy" and 220000 or 200000,
        duration=category == "dummy" and 30 or 20,
        ts=1000,level=80,class="MAGE",protocolVersion=6,
        futureDpsField={keep=true},
    }
    for key, value in pairs(fields or {}) do row[key] = value end
    return row
end

local builds, dummy, lk = {}, {}, {}
local collisionIds = {}
local RECOVERY_COUNT = 225
local utf8Player = "L" .. string.char(195, 169) .. "gacy001"
local utf8Fingerprint, relayFingerprint, verifiedFingerprint
for index = 1, RECOVERY_COUNT do
    local historicalBase = 820000 + index * 10
    local currentBase = 830000 + index * 10
    local id = string.format("collision-%03d", index)
    local historical = Fingerprint(historicalBase)
    local class = index == RECOVERY_COUNT and "WARRIOR" or "MAGE"
    builds[id] = Build(id, Fingerprint(currentBase), Echoes(currentBase), {
        class=class,
    })
    collisionIds[#collisionIds + 1] = id
    local player = index == 1 and utf8Player
        or index == 3 and "VerifiedPeer"
        or string.format("Legacy%03d", index)
    if index == 1 then utf8Fingerprint = historical end
    local fields = {ts=1000+index,class=class}
    if index == 2 then
        fields.relaySender = "RelayHop-FixtureRealm"
        relayFingerprint = historical
    elseif index == 3 then
        fields.ownerVerified = true
        fields.ownerKey = "verifiedpeer@fixturerealm"
        verifiedFingerprint = historical
    end
    dummy[player:lower()] = DpsRow(player,"dummy",id,historical,
        Echoes(historicalBase), fields)
    lk[player:lower()] = DpsRow(player,"lk",id,historical,
        Echoes(historicalBase), fields)
end

local collisionSlotFingerprint = Fingerprint(820040)
local collisionSlotBase = HistoricalId(collisionSlotFingerprint)
builds[collisionSlotBase] = Build(collisionSlotBase,
    Fingerprint(899000),Echoes(899000))

local exactBase = 840100
builds["exact-current"] = Build("exact-current", Fingerprint(exactBase),
    Echoes(exactBase), {title="Exact current",author="LocalFixture",
        ownerKey="localfixture@fixturerealm",isMine=true})
dummy.exact = DpsRow("LocalFixture","dummy","exact-current",
    Fingerprint(exactBase),Echoes(exactBase),{protocolVersion=7,
        ownerVerified=true,ownerKey="localfixture@fixturerealm"})
lk.exact = DpsRow("LocalFixture","lk","exact-current",
    Fingerprint(exactBase),Echoes(exactBase),{protocolVersion=7,
        ownerVerified=true,ownerKey="localfixture@fixturerealm"})

local reusedBase = 840200
builds["manual-historical"] = Build("manual-historical",
    Fingerprint(reusedBase),Echoes(reusedBase),{title="Manual historical"})
dummy.reused = DpsRow("ReusePeer","dummy","old-reused",
    Fingerprint(reusedBase),Echoes(reusedBase))
lk.reused = DpsRow("ReusePeer","lk","old-reused",
    Fingerprint(reusedBase),Echoes(reusedBase))

local unauthorizedBase = 840300
builds.unauthorized = Build("unauthorized",Fingerprint(840301),Echoes(840301))
dummy.unauthorized = DpsRow("AuthorityOne","dummy","unauthorized",
    Fingerprint(unauthorizedBase),Echoes(unauthorizedBase),{
        ownerVerified=true,ownerKey="authorityone@fixturerealm"})
lk.unauthorized = DpsRow("AuthorityTwo","lk","unauthorized",
    Fingerprint(unauthorizedBase),Echoes(unauthorizedBase),{
        ownerVerified=true,ownerKey="authoritytwo@fixturerealm"})

local mismatchBase = 840400
builds.mismatch = Build("mismatch",Fingerprint(840401),Echoes(840401))
dummy.mismatch = DpsRow("MismatchPeer","dummy","mismatch",
    Fingerprint(mismatchBase),Echoes(mismatchBase))
lk.mismatch = DpsRow("MismatchPeer","lk","mismatch",
    Fingerprint(mismatchBase),Echoes(840450))

local noSnapshotBase = 840425
builds.nosnapshot = Build("nosnapshot",Fingerprint(840426),Echoes(840426))
dummy.nosnapshot = DpsRow("NoSnapshotPeer","dummy","nosnapshot",
    Fingerprint(noSnapshotBase),nil)
lk.nosnapshot = DpsRow("NoSnapshotPeer","lk","nosnapshot",
    Fingerprint(noSnapshotBase),nil)

local staleBase = 840500
builds.stale = Build("stale",Fingerprint(840501),Echoes(840501))
dummy.stale = DpsRow("StalePeer","dummy","stale",
    Fingerprint(staleBase),Echoes(staleBase))
lk.stale = DpsRow("StalePeer","lk","stale",
    Fingerprint(staleBase),Echoes(staleBase))

local currentOrphanBase = 840600
dummy.currentorphan = DpsRow("CurrentOrphan","dummy","missing-current",
    Fingerprint(currentOrphanBase),Echoes(currentOrphanBase),{protocolVersion=7})
lk.currentorphan = DpsRow("CurrentOrphan","lk","missing-current",
    Fingerprint(currentOrphanBase),Echoes(currentOrphanBase),{protocolVersion=7})

local oneBase = 840700
dummy.onesided = DpsRow("OneSided","dummy","one-sided",
    Fingerprint(oneBase),Echoes(oneBase))
local durationBase = 840800
dummy.duration = DpsRow("ShortPeer","dummy","short",
    Fingerprint(durationBase),Echoes(durationBase),{duration=29})
lk.duration = DpsRow("ShortPeer","lk","short",
    Fingerprint(durationBase),Echoes(durationBase))

local initialBuildCount = Count(builds)

NexusDB = {
    communityBuilds=builds,
    syncTombstones={stale={ownerKey="stalepeer@fixturerealm",ts=9000},
        [collisionSlotBase .. "-1"]={ownerKey="old@fixturerealm",ts=20},
        untouched={ownerKey="other@fixturerealm",ts=10,future=true}},
    buildAssociations={future={keep=true}},
    dpsCapture={characterBest={dummy=dummy,lk=lk},personalBest={},buildBest={}},
    dataCompaction={schemaVersion=1,version=1,future={keep=true}},
    futureRoot={keep=true},
}

dofile("core/DpsCapture.lua")
Nexus.DpsCapture.Init({}, {})
dofile("core/LegacyQualificationRepair.lua")

local R, Catalog = Nexus.Revisions, Nexus.BuildCatalog
local Repair = Nexus.LegacyQualificationRepair
local buildRevision = R.BUILD_LIBRARY_CHANGED
local dpsRevision = R.DPS_CHANGED
local strictDummy = Copy(dummy[utf8Player:lower()])
local strictLk = Copy(lk[utf8Player:lower()])
strictDummy.dps = math.huge
assert(Repair.Classify({catalogAvailable=true,dummy=strictDummy,lk=strictLk}).reason
        == "insufficient-evidence",
    "non-finite legacy DPS was accepted as trustworthy evidence")
strictDummy = Copy(dummy[utf8Player:lower()])
strictDummy.protocolVersion = 6.5
assert(Repair.Classify({catalogAvailable=true,dummy=strictDummy,lk=strictLk}).reason
        == "insufficient-evidence",
    "fractional legacy protocol metadata was accepted")
builds["opaque-future-id"] = "preserve opaque SavedVariables value"
local opaqueOk = Catalog.PutDeferred({id="opaque-future-id"})
assert(opaqueOk == false
        and builds["opaque-future-id"] == "preserve opaque SavedVariables value",
    "deferred repair overwrote a non-table occupied SavedVariables identity")
builds["opaque-future-id"] = nil
local originals, dpsBefore = {}, Snapshot(NexusDB.dpsCapture)
for _, id in ipairs(collisionIds) do originals[id] = Snapshot(builds[id]) end
local identityCollisionBefore = Snapshot(builds[collisionSlotBase])
local staleBefore = Snapshot(NexusDB.syncTombstones)
local associationsBefore = Snapshot(NexusDB.buildAssociations)
local futureBefore = Snapshot(NexusDB.futureRoot)
local framesBefore = Count(H.frames)
local deltaBefore = Count(Catalog.DeltaSummaries())
local buildRevisionBefore = R.Get(buildRevision)
Nexus.ViewProjections.Reset()
local _, collisionLibraryBeforeSummary = Nexus.ViewProjections.Builds({
    scope="all",currentClassOnly=false,qualifiedOnly=false,
    search="Current collision",sortMode="title",page=1,
})
local collisionLibraryBefore = collisionLibraryBeforeSummary.filteredTotal
Nexus.ViewProjections.Reset()
local catalogBefore = Catalog.DebugStats()
local originalCatalogAll = Catalog.All
local catalogAllCalls = 0
Catalog.All = function()
    catalogAllCalls = catalogAllCalls + 1
    error("full catalog copy is forbidden during legacy repair")
end

local requested, why = Repair.Request("login")
assert(requested and why == "scheduled", "initial repair was not scheduled")
local partialPumps, partialRecovered = 0, 0
repeat
    assert(Repair.Pump(25) == false,
        "partial repair unexpectedly completed before reload")
    partialPumps = partialPumps + 1
    partialRecovered = 0
    for _, row in pairs(NexusDB.communityBuilds) do
        if row.legacyRecovered then partialRecovered = partialRecovered + 1 end
    end
    assert(partialPumps < 1000, "repair never reached a persisted write")
until partialRecovered >= 12
local interruptedMeta = NexusDB.legacyQualificationRepair
local interruptedWorkUnits = interruptedMeta.workUnits
assert(interruptedMeta.inProgress and interruptedMeta.cursorVersion == 1
        and interruptedWorkUnits > 0
        and interruptedMeta.pendingWrites == partialRecovered
        and R.Get(buildRevision) == buildRevisionBefore,
    "bounded writes were not persisted without early publication")
local completedBuildEpochBefore = Catalog.RecordRevision("exact-current")
local firstRecoveredId
for id, row in pairs(NexusDB.communityBuilds) do
    if row.legacyRecovered then firstRecoveredId = id; break end
end
local pendingEpochBefore, pendingRecordBefore =
    Catalog.RecordRevision(firstRecoveredId)

-- Reload the owner while work is incomplete. The cursor restarts from source,
-- retaining only bounded progress scalars and producing the same final result.
dofile("core/LegacyQualificationRepair.lua")
Repair = Nexus.LegacyQualificationRepair
local resumed, resumedWhy = Repair.Request("reload")
assert(resumed and resumedWhy == "scheduled"
        and interruptedWorkUnits > 0
        and NexusDB.legacyQualificationRepair.workUnits == 0,
    "reload did not resume safely from versioned incomplete state")
local pumps = 0
while (tonumber(NexusDB.legacyQualificationRepair.pendingWrites) or 0)
        <= partialRecovered do
    assert(Repair.Pump(25) == false,
        "resumed repair completed before exercising write interruption")
    pumps = pumps + 1
    assert(pumps < 1000, "resumed repair never reached another staged write")
end
local pendingBeforeRevisionRestart =
    NexusDB.legacyQualificationRepair.pendingWrites
assert(R.Advance(dpsRevision,{scope="metadata",reason="partial write interrupt"}))
assert(Repair.Pump(1) == false
        and NexusDB.legacyQualificationRepair.pendingWrites
            == pendingBeforeRevisionRestart
        and Repair.Stats().restarts == 1,
    "revision restart lost or published already staged writes")
while not Repair.Pump(25) do
    pumps = pumps + 1
    assert(pumps < 1000, "bounded legacy repair did not terminate")
end
Nexus.Scheduler.Cancel("legacy-qualification-repair")

local stats = Repair.Stats()
Catalog.All = originalCatalogAll
local catalogAfter = Catalog.DebugStats()
assert(stats.recovered == RECOVERY_COUNT
        and stats.recoverable == RECOVERY_COUNT
        and stats.published == 1 and stats.rejected == 7
        and stats.reused >= 2 + partialRecovered and stats.restarts == 1
        and stats.maxWork <= 25,
    string.format("unexpected repair totals recovered=%d recoverable=%d published=%d rejected=%d reused=%d max=%d",
        stats.recovered,stats.recoverable,stats.published,
        stats.rejected,stats.reused,stats.maxWork))
assert(catalogAllCalls == 0
        and catalogAfter.summarySnapshots == catalogBefore.summarySnapshots,
    "repair copied the complete catalog instead of using indexed lookups")
assert(R.Get(buildRevision) == buildRevisionBefore + 1,
    "recovered identities did not publish exactly one build revision")
local completedBuildEpochAfter = Catalog.RecordRevision("exact-current")
local pendingEpochAfter, pendingRecordAfter = Catalog.RecordRevision(firstRecoveredId)
assert(completedBuildEpochAfter == completedBuildEpochBefore + 1
        and pendingEpochAfter == pendingEpochBefore + 1
        and pendingRecordAfter == pendingRecordBefore,
    "deferred publication exposed a partial per-record revision")
assert(NexusDB.communityBuilds == builds
        and Count(NexusDB.communityBuilds) == initialBuildCount + RECOVERY_COUNT,
    "repair replaced the build store or produced the wrong row count")

local recovered, recoveredIds = 0, {}
local sawUtf8, sawRelay, sawVerified = false, false, false
for id, raw in pairs(NexusDB.communityBuilds) do
    if raw.legacyRecovered then
        recovered = recovered + 1
        recoveredIds[id] = true
        assert(raw.ownerKey == nil and raw.isMine == nil
                and raw.ownerVerified == nil and raw.relaySender == nil
                and (raw.legacyOwnership == "unverified"
                    or raw.legacyOwnership == "verified"),
            "recovered content gained edit/delete/tombstone/relay authority")
        assert(raw.echoes == nil and type(raw.evidenceKey) == "string",
            "recovered content duplicated compactable inline Echo evidence")
        local public = Catalog.Get(id)
        assert(public and public.fingerprint == raw.fingerprint
                and type(public.echoes) == "table" and #public.echoes == 2,
            "pooled recovered evidence did not materialize exactly")
        if public.fingerprint == utf8Fingerprint then
            assert(public.author == utf8Player,
                "UTF-8 legacy identity was not preserved byte-for-byte")
            sawUtf8 = true
        elseif public.fingerprint == relayFingerprint then
            assert(public.legacySource == "relay"
                    and public.legacyOwnership == "unverified"
                    and public.relaySender == nil,
                "relayed history gained authority or lost its source limit")
            sawRelay = true
        elseif public.fingerprint == verifiedFingerprint then
            assert(public.legacySource == "direct-or-unknown"
                    and public.legacyOwnership == "verified"
                    and public.ownerKey == nil and public.ownerVerified == nil,
                "direct verified evidence was converted into build authority")
            sawVerified = true
        end
    end
end
assert(recovered == RECOVERY_COUNT and sawUtf8 and sawRelay and sawVerified,
    "more-than-200 recovery or direct/relay/UTF-8 coverage was lost")
assert(NexusDB.communityBuilds[collisionSlotBase .. "-2"]
        and NexusDB.communityBuilds[collisionSlotBase .. "-2"].fingerprint
            == collisionSlotFingerprint
        and Snapshot(NexusDB.communityBuilds[collisionSlotBase])
            == identityCollisionBefore,
    "deterministic identity collision/tombstone fallback was unsafe")
for _, id in ipairs(collisionIds) do
    assert(Snapshot(NexusDB.communityBuilds[id]) == originals[id],
        "repair rewrote colliding current build " .. id)
end
assert(Snapshot(NexusDB.dpsCapture) == dpsBefore
        and Snapshot(NexusDB.syncTombstones) == staleBefore
        and Snapshot(NexusDB.buildAssociations) == associationsBefore
        and Snapshot(NexusDB.futureRoot) == futureBefore
        and NexusDB.dataCompaction.future.keep
        and Count(H.frames) == framesBefore,
    "repair changed DPS, tombstones, associations, unknown fields, or UI")

-- Recovered unverified content participates in local exact qualification but
-- is excluded from Sync delta/relay surfaces until independent ownership proof.
assert(Count(Catalog.DeltaSummaries()) == deltaBefore,
    "unverified recovered identities entered the Sync delta digest")
local deltaSnapshot = Catalog.DeltaSnapshot()
assert(deltaSnapshot[firstRecoveredId] == nil
        and Catalog.SyncState(firstRecoveredId).delta == nil,
    "unverified recovered identity entered a fallback Sync delta reader")
local cursor, syncRecovered = nil, 0
while true do
    local id, row, done = Catalog.SyncDeltaNext(cursor)
    if done then break end
    cursor = id
    if row and row.legacyRecovered then syncRecovered = syncRecovered + 1 end
end
assert(syncRecovered == 0,
    "unverified recovered identity entered the Sync relay cursor")

-- Every outgoing path, including an exact-ID response, rejects recovered
-- content without independent build-owner verification.
dofile("core/Codec.lua")
dofile("core/PeerDebug.lua")
dofile("core/SyncProtocol.lua")
dofile("core/SyncTransport.lua")
dofile("core/SyncCompatibility.lua")
dofile("core/SyncReconciler.lua")
dofile("core/SyncInbound.lua")
dofile("core/SyncDiagnostics.lua")
dofile("core/SyncSession.lua")
dofile("core/Sync.lua")
Nexus.Sync.Init(Nexus.Codec,{})
H.sentChatMessages = {}
local recoveredForRelay = Catalog.Get(firstRecoveredId)
local summaryOk, summaryWhy = Nexus.Sync.BroadcastBuildSummary(
    recoveredForRelay)
local buildOk, buildWhy = Nexus.Sync.BroadcastBuild(recoveredForRelay)
assert(summaryOk == false and summaryWhy == "relay unauthorized"
        and buildOk == false and buildWhy == "relay unauthorized"
        and #H.sentChatMessages == 0,
    "an exact-ID or direct outgoing path relayed unverified recovered content")

Nexus.ViewProjections.Reset()
local pageOne, pageOneSummary = Nexus.ViewProjections.Builds({
    scope="all",currentClassOnly=true,qualifiedOnly=true,
    search="Historical Record Loadout",sortMode="title",page=1,
})
local pageTwelve, pageTwelveSummary = Nexus.ViewProjections.Builds({
    scope="all",currentClassOnly=true,qualifiedOnly=true,
    search="Historical Record Loadout",sortMode="title",page=12,
})
assert(#pageOne == 20 and #pageTwelve == 4
        and pageOneSummary.filteredTotal == RECOVERY_COUNT - 1
        and pageTwelveSummary.first == 221
        and pageTwelveSummary.last == RECOVERY_COUNT - 1,
    "recovered identities did not qualify through normal 20-row paging")
Nexus.ViewProjections.Reset()
local allClasses, allClassSummary = Nexus.ViewProjections.Builds({
    scope="all",currentClassOnly=false,qualifiedOnly=true,
    search="Historical Record Loadout",sortMode="dps",page=12,
})
Nexus.ViewProjections.Reset()
local mine, mineSummary = Nexus.ViewProjections.Builds({
    scope="mine",currentClassOnly=false,qualifiedOnly=true,
    search="Historical Record Loadout",sortMode="recent",page=1,
})
Nexus.ViewProjections.Reset()
local unqualifiedCollisions, collisionSummary = Nexus.ViewProjections.Builds({
    scope="all",currentClassOnly=false,qualifiedOnly=false,
    search="Current collision",sortMode="title",page=1,
})
Nexus.ViewProjections.Reset()
local qualifiedCollisions, qualifiedCollisionSummary = Nexus.ViewProjections.Builds({
    scope="all",currentClassOnly=false,qualifiedOnly=true,
    search="Current collision",sortMode="title",page=1,
})
assert(#allClasses == 5 and allClassSummary.filteredTotal == RECOVERY_COUNT
        and #mine == 0 and mineSummary.filteredTotal == 0
        and #unqualifiedCollisions == 20
        and collisionSummary.filteredTotal == collisionLibraryBefore
        and #qualifiedCollisions == 0
        and qualifiedCollisionSummary.filteredTotal == 0,
    string.format("class/scope/Qualified Only/search/sort projection controls regressed all=%d/%d mine=%d/%d off=%d/%d on=%d/%d",
        #allClasses,allClassSummary.filteredTotal,#mine,mineSummary.filteredTotal,
        #unqualifiedCollisions,collisionSummary.filteredTotal,
        #qualifiedCollisions,qualifiedCollisionSummary.filteredTotal))

local firstResult = Copy(NexusDB.legacyQualificationRepair.lastResult)
assert(firstResult.recoverable == RECOVERY_COUNT
        and firstResult.recovered == RECOVERY_COUNT
        and firstResult.rejected == 7 and firstResult.published == 1
        and firstResult.deferredOneCategory == 1
        and firstResult.deferredDurationOrCategory == 1
        and firstResult.deferredBuildIdCollision == 1
        and firstResult.deferredInsufficientEvidence == 2
        and firstResult.deferredUnauthorizedOwner == 1
        and firstResult.deferredStaleOrSuperseded == 1,
    "bounded first-pass result did not preserve deferred reason counts")

-- A represented DPS revision invalidates the cursor. Restart is bounded and a
-- no-data-change replay publishes no second build revision or duplicate row.
Nexus.ViewRefresh.Init()
local requestsBeforeRefresh = Repair.Stats().requested
assert(R.Advance(dpsRevision,{scope="metadata",reason="interrupt fixture"}))
H.Advance(0.06, 0.06)
local refreshRequested = Repair.Stats()
assert(refreshRequested.requested == requestsBeforeRefresh + 1
        and refreshRequested.pending,
    "coalesced post-receive refresh did not schedule legacy repair")
assert(Repair.Pump(5) == false)
assert(R.Advance(dpsRevision,{scope="metadata",reason="interrupt again"}))
assert(Repair.Pump(5) == false)
while not Repair.Pump(25) do
    pumps = pumps + 1
    assert(pumps < 2000, "revision-restarted repair did not terminate")
end
Nexus.Scheduler.Cancel("legacy-qualification-repair")
local afterRestart = Repair.Stats()
assert(afterRestart.restarts == 2
        and afterRestart.recovered == RECOVERY_COUNT
        and afterRestart.published == 1
        and R.Get(buildRevision) == buildRevisionBefore + 1
        and NexusDB.communityBuilds == builds
        and Count(NexusDB.communityBuilds)
            == initialBuildCount + RECOVERY_COUNT,
    string.format("interrupted replay duplicated identities or published another revision restarts=%d recovered=%d published=%d revision=%d expected=%d rows=%d expectedRows=%d",
        afterRestart.restarts,afterRestart.recovered,afterRestart.published,
        R.Get(buildRevision),buildRevisionBefore+1,
        Count(NexusDB.communityBuilds),initialBuildCount+RECOVERY_COUNT))

for _, reason in ipairs({"refresh","import","migration","sync"}) do
    local ok, state = Repair.Request(reason)
    assert(ok and state == "current",
        "same-revision request was not idempotent for " .. reason)
end
local meta = NexusDB.legacyQualificationRepair
assert(meta.schemaVersion == 1 and meta.version == 1
        and meta.cursorVersion == 1 and not meta.inProgress
        and meta.completedDpsRevision == R.Get(dpsRevision)
        and type(meta.lastResult) == "table"
        and meta.lastResult.schema == 1
        and meta.lastResult.recovered == 0
        and meta.lastResult.published == 0
        and meta.lastResult.reason == "complete",
    "durable completion state is missing, unbounded, or stale")

-- A fresh module instance must not trust a persisted in-session revision from
-- an older login. It runs one scheduled bounded pass, reuses every identity,
-- and publishes nothing when represented data is unchanged.
local loginRowsBefore = Count(NexusDB.communityBuilds)
local loginBuildRevisionBefore = R.Get(buildRevision)
dofile("core/LegacyQualificationRepair.lua")
Repair = Nexus.LegacyQualificationRepair
local loginOk, loginState = Repair.Request("login")
assert(loginOk and loginState == "scheduled",
    "fresh login trusted a stale durable revision counter")
local loginTicks = 0
while Repair.Stats().pending do
    H.Advance(0.01, 0.01)
    loginTicks = loginTicks + 1
    assert(loginTicks < 2000, "scheduled login repair did not terminate")
end
local loginStats = Repair.Stats()
assert(loginStats.recovered == 0 and loginStats.published == 0
        and loginStats.maxWork <= 25
        and R.Get(buildRevision) == loginBuildRevisionBefore
        and Count(NexusDB.communityBuilds) == loginRowsBefore,
    "repeated login duplicated rows or published unchanged data")

local currentDb = NexusDB
local futureDb = {legacyQualificationRepair={
    schemaVersion=2,version=9,cursorVersion=9,future={keep=true},
}}
NexusDB = futureDb
local futureBefore = Snapshot(futureDb)
local futureOk, futureWhy = Repair.Request("future")
NexusDB = currentDb
assert(futureOk == false
        and futureWhy == "future legacy repair schema is read-only"
        and Snapshot(futureDb) == futureBefore,
    "future repair metadata was not preserved read-only")
for key, value in pairs(Repair.Stats()) do
    assert(type(key) == "string" and type(value) ~= "table",
        "repair diagnostics retained identity or payload data")
end

print(string.format(
    "Stage 32.2 legacy repair: recovered=%d (>200) reused=%d rejected=%d restarts=%d publications=%d maxWork=%d pages=20+5 -- OK",
    afterRestart.recovered,afterRestart.reused,afterRestart.rejected,
    afterRestart.restarts,afterRestart.published,afterRestart.maxWork))
