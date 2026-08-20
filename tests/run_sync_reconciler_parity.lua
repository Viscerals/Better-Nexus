-- Characterize bounded pending-work ownership, fairness, expiry, and claims.
Nexus = nil
dofile("core/SyncReconciler.lua")

local Factory = assert(Nexus.SyncInternals.Reconciler)

local function AssertEqual(actual, expected, label)
    assert(actual == expected, string.format("%s: expected %s, got %s",
        tostring(label), tostring(expected), tostring(actual)))
end

local function Split(text)
    local out = {}
    for part in tostring(text or ""):gmatch("[^,]+") do
        out[#out + 1] = part
    end
    return out
end

local function ZeroHash(count)
    local out = {}
    for i = 1, count do out[i] = "0" end
    return table.concat(out, ",")
end

local function NewHarness(overrides)
    overrides = overrides or {}
    local state = {
        now=0, bulkDepth=0, queueFull=false, calls={}, claims={}, logs={},
        syncStats={}, successfulAdmissions=0, workOrder={}, builds={},
        claimable={}, snapshotCurrent=true,
    }
    local function Count(name)
        state.calls[name] = (state.calls[name] or 0) + 1
    end
    local buckets = overrides.bucketCount or 8
    local deltaHash = overrides.deltaHash or
        "11,12,13,14,15,16,17,18"
    local dpsHash = overrides.dpsHash or ZeroHash(buckets)
    local reconciler = Factory.New({
        bucketCount=buckets,
        maxPendingResponses=overrides.maxPendingResponses or 128,
        maxPendingLoadouts=overrides.maxPendingLoadouts or 128,
        pendingTtl=overrides.pendingTtl or 30,
        pendingMaxAge=overrides.pendingMaxAge or 90,
        claimDelayMin=0,
        claimDelayMax=1,
        bucketClaimMax=0,
        sendInterval=0.01,responseElectionDelay=0.01,
        now=function() return state.now end,
        myName=function() return "Me" end,
        stableDelay=function() return 0 end,
        splitHashes=Split,
        deltaBuildHash=function() Count("deltaHash"); return deltaHash end,
        currentBuildHash=function()
            Count("currentBuildHash")
            return overrides.currentBuildHash or deltaHash
        end,
        currentDpsHash=function() Count("dpsHash"); return dpsHash end,
        catalogToken=function() Count("catalogToken"); return "catalog-v2" end,
        buildCandidateSnapshot=function(hash)
            Count("candidateSnapshot")
            assert(hash == deltaHash, "candidate snapshot uses delta hash")
            if overrides.snapshot then return overrides.snapshot end
            local claimSafeByBucket = {}
            for bucket = 1, buckets do claimSafeByBucket[bucket] = true end
            return {revision=1,complete=true,
                candidates={{id="overlay-only"}},
                claimSafeByBucket=claimSafeByBucket}
        end,
        snapshotCurrent=function()
            Count("snapshotCurrent")
            return state.snapshotCurrent
        end,
        bucketClaimable=function(bucket)
            Count("claimable")
            if state.claimable[bucket] ~= nil then
                return state.claimable[bucket]
            end
            return bucket ~= 8
        end,
        backpressured=function()
            Count("backpressureProbe")
            return state.bulkDepth >= 8190
        end,
        catalogGet=function(id)
            Count("catalogGet")
            return state.builds[id]
        end,
        prepareBuild=function(build)
            Count("prepareBuild")
            state.workOrder[#state.workOrder + 1] = "prepare:" .. build.id
            return {build=build, messages={"payload:" .. build.id}}
        end,
        admitBuild=function(prepared)
            Count("admitBuild")
            if state.stalePrepared then
                state.stalePrepared = false
                return false, "stale prepared build"
            end
            if state.queueFull then return false, "sync queue full" end
            state.successfulAdmissions = state.successfulAdmissions + 1
            state.workOrder[#state.workOrder + 1] =
                "admit:" .. prepared.build.id
            return true
        end,
        sendNextBuild=function(bucket)
            Count("sendNextBuild")
            state.workOrder[#state.workOrder + 1] =
                "bucket:" .. tostring(bucket.bucket)
            return 1, true, true, true
        end,
        sendDpsBucket=function()
            Count("sendDpsBucket")
            return true, true, 1, true, true
        end,
        publishLoadoutClaim=function(entry)
            Count("loadoutClaim")
            state.claims[#state.claims + 1] = "L:" .. entry.requester
            return true
        end,
        publishBucketClaim=function(entry, bucket)
            Count("bucketClaim")
            state.claims[#state.claims + 1] = "B:" .. entry.requester
                .. ":" .. bucket.kind .. tostring(bucket.bucket)
            return true
        end,
        publishResponseClaim=overrides.publishResponseClaim and function(entry)
            Count("responseClaim")
            return overrides.publishResponseClaim(entry)
        end or nil,
        supportsRequestContext=function()
            return overrides.supportsRequestContext == true
        end,
        localOwnsDpsBucket=function()
            return overrides.localOwnsDpsBucket ~= false
        end,
        dpsBucketClaimInfo=function()
            return overrides.dpsClaimSafe == true
        end,
        noteSyncStat=function(name, amount)
            state.syncStats[name] = (state.syncStats[name] or 0)
                + (tonumber(amount) or 1)
        end,
        log=function(...)
            state.logs[#state.logs + 1] = {...}
        end,
    })
    return reconciler, state, deltaHash, dpsHash
end

-- An approximately full 8192-packet transport must produce a cheap yield.
local saturated, sat = NewHarness({pendingTtl=3, pendingMaxAge=5})
sat.bulkDepth = 8190
sat.builds["known"] = {id="known", echoes={1}}
assert(saturated.ScheduleRequest({requester="Alice", requestId="r1",
    peerBuildHash="legacy-token", peerDpsHash="0"}))
assert(saturated.ScheduleLoadout({requester="Bob", buildId="known"}))
for turn = 1, 3 do
    sat.now = turn
    saturated.Process(1)
end
for _, name in ipairs({"deltaHash", "dpsHash", "candidateSnapshot",
        "catalogGet", "prepareBuild", "admitBuild", "sendNextBuild",
        "sendDpsBucket", "snapshotCurrent", "claimable", "loadoutClaim",
        "bucketClaim"}) do
    AssertEqual(sat.calls[name] or 0, 0,
        "no expensive work while backpressured: " .. name)
end
AssertEqual(saturated.Counts().total, 2, "saturated work retained")
AssertEqual(saturated.Stats().backpressureDeferrals, 3,
    "cheap saturation deferrals")

-- Duplicate requests do not refresh absolute age; saturated work expires.
sat.now = 4
assert(saturated.ScheduleRequest({requester="Alice", requestId="r1",
    peerBuildHash="legacy-token", peerDpsHash="0"}))
sat.now = 6
saturated.Process(1)
AssertEqual(saturated.Counts().total, 0, "absolute expiry under saturation")

-- Cap rejection is deterministic and does not evict accepted work.
local capped, cap = NewHarness({maxPendingResponses=1, maxPendingLoadouts=1})
assert(capped.ScheduleRequest({requester="Alice", requestId="one",
    peerBuildHash="0", peerDpsHash="0"}))
assert(not capped.ScheduleRequest({requester="Bob", requestId="two",
    peerBuildHash="0", peerDpsHash="0"}))
assert(capped.ScheduleLoadout({requester="Carol", buildId="a"}))
assert(not capped.ScheduleLoadout({requester="Dave", buildId="b"}))
AssertEqual(capped.Counts().total, 2, "accepted work survives cap rejection")
AssertEqual(cap.syncStats.pendingOverflowRejected, 2,
    "response and loadout cap accounting")

-- Fair scheduling processes one unit per update across multiple requesters.
local fair, fs, fairDelta, fairDps = NewHarness()
local currentWire = fairDelta .. ",catalog-v2"
for _, requester in ipairs({"Alice", "Bob", "Carol"}) do
    assert(fair.ScheduleRequest({requester=requester, requestId="ready",
        peerBuildHash=ZeroHash(8), peerDpsHash=fairDps}))
end
for turn = 1, 3 do
    local before = fair.Stats().workUnits
    fair.Process(1)
    AssertEqual(fair.Stats().workUnits, before + 1,
        "one preparation unit per update")
end
AssertEqual(fair.Stats().entryPreparations, 3,
    "all requesters prepared fairly")
AssertEqual(fs.calls.candidateSnapshot, 3,
    "one immutable snapshot request per requester")
AssertEqual(fs.calls.claimable or 0, 0,
    "preparation does not scan or cache mutable claimability")
local preparedOrder = {}
local seenPrepared = {}
for turn = 1, 3 do
    local before = fs.calls.sendNextBuild or 0
    fair.Process(1)
    AssertEqual((fs.calls.sendNextBuild or 0) - before, 1,
        "one bucket send per update")
    preparedOrder[#preparedOrder + 1] = fair.Stats().lastRequester
    seenPrepared[fair.Stats().lastRequester] = true
end
AssertEqual(#preparedOrder, 3, "three fair resumptions")
AssertEqual(seenPrepared.Alice and 1 or 0, 1, "Alice resumed")
AssertEqual(seenPrepared.Bob and 1 or 0, 1, "Bob resumed")
AssertEqual(seenPrepared.Carol and 1 or 0, 1, "Carol resumed")

-- Current-token peers complete without building compatibility candidates.
local current, cs = NewHarness()
assert(current.ScheduleRequest({requester="Current", requestId="same",
    peerBuildHash=currentWire, peerDpsHash=ZeroHash(8)}))
current.Process(1)
AssertEqual(cs.calls.candidateSnapshot or 0, 0,
    "current peer avoids candidate snapshot when hashes match")
AssertEqual(current.Counts().responses, 0, "up-to-date peer completes")

-- Legacy and token-mismatch peers use only the injected bounded delta snapshot.
local compat, compatState = NewHarness()
assert(compat.ScheduleRequest({requester="Legacy", requestId="legacy",
    peerBuildHash="old-catalog-token", peerDpsHash=ZeroHash(8)}))
compat.Process(1)
AssertEqual(compatState.calls.candidateSnapshot, 1,
    "mismatch builds one bounded candidate snapshot")
AssertEqual(compatState.calls.catalogGet or 0, 0,
    "compatibility planning never scans catalog through loadout lookup")
AssertEqual(compat.Stats().compatRequests, 1,
    "compatibility request accounted")

-- Loadout preparation is retained across queue-full retry; claim follows admit.
local loadouts, ls = NewHarness()
ls.builds["known"] = {id="known", echoes={1}}
ls.queueFull = true
assert(loadouts.ScheduleLoadout({requester="Alice", buildId="known"}))
loadouts.Process(1)
AssertEqual(ls.calls.prepareBuild, 1, "loadout prepared once")
AssertEqual(ls.calls.admitBuild, 1, "first admission attempted")
AssertEqual(ls.successfulAdmissions, 0, "full queue admits nothing")
AssertEqual(#ls.claims, 0, "no claim before admission")
ls.queueFull = false
loadouts.Process(1)
AssertEqual(ls.calls.prepareBuild, 1, "retry reuses prepared payload")
AssertEqual(ls.calls.admitBuild, 2, "retry admission attempted once")
AssertEqual(ls.successfulAdmissions, 1, "exactly one successful admission")
AssertEqual(#ls.claims, 1, "claim follows successful admission")
loadouts.Process(1)
AssertEqual(ls.calls.admitBuild, 2, "completed loadout never readmitted")

-- A prepared loadout is only a serialization cache. If its catalog authority
-- changes before admission, the reconciler discards it and re-prepares the
-- current record before publishing a claim.
local staleLoadout, staleLoadoutState = NewHarness()
staleLoadoutState.builds["known"] = {id="known",echoes={1}}
staleLoadoutState.stalePrepared = true
assert(staleLoadout.ScheduleLoadout({requester="Alice",buildId="known"}))
staleLoadout.Process(1)
AssertEqual(staleLoadoutState.calls.prepareBuild, 1,
    "stale loadout initial preparation")
AssertEqual(staleLoadout.Counts().loadouts, 1,
    "stale prepared loadout was dropped instead of retained for repair")
AssertEqual(#staleLoadoutState.claims, 0,
    "stale prepared loadout published a claim")
staleLoadout.Process(1)
AssertEqual(staleLoadoutState.calls.prepareBuild, 2,
    "stale prepared loadout was not regenerated")
AssertEqual(staleLoadoutState.successfulAdmissions, 1,
    "regenerated loadout was not admitted exactly once")
AssertEqual(#staleLoadoutState.claims, 1,
    "regenerated loadout did not publish its post-admission claim")

-- A matching peer claim uses current candidate and ownership state.
local claims, claimState = NewHarness()
local oneBucketMismatch = "0,12,13,14,15,16,17,18,catalog-v2"
assert(claims.ScheduleRequest({requester="Alice", requestId="claimable",
    peerBuildHash=oneBucketMismatch, peerDpsHash=ZeroHash(8)}))
claims.Process(1)
claims.HandleLegacyClaim({responder="Other", requester="Alice",
    requestId="claimable"})
AssertEqual(claims.Counts().responses, 1,
    "legacy whole-state claim cannot suppress owner work")
claimState.claimable[1] = false
claims.HandleBucketClaim({responder="Other", requester="Alice",
    requestId="claimable", kind="B", bucket=1, hash="11"})
AssertEqual(claims.Counts().responses, 1,
    "new tombstone prevents stale peer-claim suppression")
claimState.claimable[1] = true
claims.HandleBucketClaim({responder="Other", requester="Alice",
    requestId="claimable", kind="B", bucket=1, hash="11"})
AssertEqual(claims.Counts().responses, 0,
    "current claimable bucket accepts matching peer claim")

local unsafeClaim = NewHarness({snapshot={revision=1,complete=true,
    candidates={{id="unverified"}},claimSafeByBucket={[1]=false}}})
assert(unsafeClaim.ScheduleRequest({requester="Alice",requestId="unsafe",
    peerBuildHash=oneBucketMismatch,peerDpsHash=ZeroHash(8)}))
unsafeClaim.Process(1)
unsafeClaim.HandleBucketClaim({responder="Other",requester="Alice",
    requestId="unsafe",kind="B",bucket=1,hash="11"})
AssertEqual(unsafeClaim.Counts().responses, 1,
    "relay-ineligible snapshot rejects matching peer suppression")

local pendingClaim = NewHarness({snapshot={revision=1,complete=false,
    candidates={},claimSafeByBucket={[1]=true}}})
assert(pendingClaim.ScheduleRequest({requester="Alice",requestId="pending",
    peerBuildHash=oneBucketMismatch,peerDpsHash=ZeroHash(8)}))
pendingClaim.Process(1)
pendingClaim.HandleBucketClaim({responder="Other",requester="Alice",
    requestId="pending",kind="B",bucket=1,hash="11"})
AssertEqual(pendingClaim.Counts().responses, 1,
    "incomplete snapshot rejects early peer suppression")

local unsafeDpsHash = "21,0,0,0,0,0,0,0"
local unsafeDps = NewHarness({dpsHash=unsafeDpsHash,
    supportsRequestContext=true,localOwnsDpsBucket=false,dpsClaimSafe=false})
assert(unsafeDps.ScheduleRequest({requester="Alice",requestId="dps-unsafe",
    peerBuildHash=currentWire,peerDpsHash=ZeroHash(8)}))
unsafeDps.Process(1)
unsafeDps.HandleBucketClaim({responder="Other",requester="Alice",
    requestId="dps-unsafe",kind="D",bucket=1,hash="21"})
AssertEqual(unsafeDps.Counts().responses, 1,
    "unverified DPS bucket rejects matching peer suppression")

-- A stale immutable candidate is reset instead of trusting its old hash.
local stale, staleState = NewHarness()
assert(stale.ScheduleRequest({requester="Alice", requestId="stale",
    peerBuildHash=oneBucketMismatch, peerDpsHash=ZeroHash(8)}))
stale.Process(1)
staleState.snapshotCurrent = false
stale.HandleBucketClaim({responder="Other", requester="Alice",
    requestId="stale", kind="B", bucket=1, hash="11"})
AssertEqual(stale.Counts().responses, 1,
    "stale candidate claim retains authoritative work")
staleState.snapshotCurrent = true
stale.Process(1)
AssertEqual(stale.Stats().entryPreparations, 2,
    "stale candidate is prepared again before progress")

-- Publication also rechecks live ownership after payload completion.
local publication, publicationState = NewHarness()
assert(publication.ScheduleRequest({requester="Alice", requestId="publish",
    peerBuildHash=oneBucketMismatch, peerDpsHash=ZeroHash(8)}))
publication.Process(1)
publicationState.claimable[1] = false
publication.Process(1)
AssertEqual(publicationState.calls.sendNextBuild, 1,
    "payload completes before live claimability decision")
AssertEqual(#publicationState.claims, 0,
    "new tombstone prevents responder claim publication")

-- A field-valid but wire-oversize WLRC is permanently unavailable. It must
-- fall back to the independently bounded response instead of refreshing the
-- pending entry until its absolute expiry.
local oversizedClaim, oversizedState = NewHarness({
    supportsRequestContext=true,
    snapshot={revision=1,complete=true,candidates={{id="overlay-only"}},
        claimSafeByBucket={[1]=true}},
    publishResponseClaim=function() return false, "invalid packet" end,
})
assert(oversizedClaim.ScheduleRequest({requester="Alice",
    requestId="c1-oversize-claim",peerBuildHash=oneBucketMismatch,
    peerDpsHash=ZeroHash(8)}))
oversizedClaim.Process(1)
oversizedClaim.Process(1)
AssertEqual(oversizedState.calls.responseClaim, 1,
    "permanent response-claim refusal attempted once")
AssertEqual(oversizedState.calls.sendNextBuild, 1,
    "oversize response claim falls back to bounded data")
AssertEqual(oversizedClaim.Counts().responses, 0,
    "oversize response claim does not starve pending work")

-- Stats snapshots are defensive and reset clears only reconciler session state.
local snapshot = claims.Stats()
snapshot.workUnits = 9999
assert(claims.Stats().workUnits ~= 9999, "stats snapshot is defensive")
claims.Reset()
AssertEqual(claims.Counts().total, 0, "reset clears pending work")
AssertEqual(claims.Stats().workUnits, 0, "reset clears response stats")

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local reconcilerSource = Read("core/SyncReconciler.lua")
local syncSource = Read("core/Sync.lua")
assert(reconcilerSource:find(
    "local pendingResponses, pendingLoadouts, continuations = {}, {}, {}",
    1, true),
    "Reconciler owns both pending work tables and bounded continuations")
assert(not syncSource:find("local pendingResponses", 1, true),
    "Sync no longer owns pending responses")
assert(not syncSource:find("local pendingLoadouts", 1, true),
    "Sync no longer owns pending loadouts")
assert(not syncSource:find("Responder.fairCursor", 1, true),
    "Sync no longer owns fair cursor")
assert(not syncSource:find("Responder.stats", 1, true),
    "Sync no longer owns response statistics")
assert(not reconcilerSource:find("claimable=bucketClaimable", 1, true),
    "Reconciler does not cache mutable claimability")
for _, forbidden in ipairs({"BuildCatalog.All", "Codec.", "JSONEncode",
        "Base64Encode", "SendChatMessage", "NexusDB", "GameAdapter",
        "StoreReceivedBuild", "tombstones["}) do
    assert(not reconcilerSource:find(forbidden, 1, true),
        "Reconciler boundary excludes " .. forbidden)
end

print("bounded Sync reconciler ownership, fairness, expiry, and claims -- OK")
