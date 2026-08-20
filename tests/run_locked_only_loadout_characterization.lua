-- Stage 35.6 green regression: locked Echo evidence is supplemental. It must not
-- independently authorize ordinary completeness, navigation, Copy/EBH1,
-- qualification, build manufacture, storage, or Sync publication.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/WishlistModel.lua")
local WishlistModel = Nexus.WishlistModel.New()

local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, child in pairs(value) do out[Copy(key, seen)] = Copy(child, seen) end
    return out
end

local function Signature(value, seen)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    seen = seen or {}
    if seen[value] then return "cycle" end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        return type(left) .. ":" .. tostring(left)
            < type(right) .. ":" .. tostring(right)
    end)
    local out = {"{"}
    for _, key in ipairs(keys) do
        out[#out + 1] = Signature(key, seen)
        out[#out + 1] = "="
        out[#out + 1] = Signature(value[key], seen)
        out[#out + 1] = ";"
    end
    out[#out + 1] = "}"
    seen[value] = nil
    return table.concat(out)
end

local function EchoKey(echoes)
    local counts = {}
    for _, echo in ipairs(type(echoes) == "table" and echoes or {}) do
        local id = tonumber(echo.spellId or echo.id)
        local stacks = tonumber(echo.stacks or echo.count) or 1
        if id and stacks > 0 then counts[id] = (counts[id] or 0) + stacks end
    end
    local ids = {}
    for id in pairs(counts) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        parts[#parts + 1] = tostring(id) .. "x" .. tostring(counts[id])
    end
    return #parts > 0 and table.concat(parts, ",") or nil
end

local locked, crossRole = {}, {}
for index = 1, 6 do
    locked[index] = {
        spellId=710000 + index,quality=index % 4,stacks=1,locked=true,
    }
    -- This array represents the same locked-only source after a legacy/cross-
    -- role path lost the marker. Current consumers cannot prove its role.
    crossRole[index] = {
        spellId=locked[index].spellId,quality=locked[index].quality,stacks=1,
    }
end
local lockedFingerprint = assert(EchoKey(crossRole))

NexusDB = {
    settings={},chars={},buildFilters={},syncTombstones={},
    communityBuilds={},futureRoot={keep=true},
}
Nexus.LoadoutEvidence.Init(NexusDB)

local function LockedSubset(count)
    local out = {}
    for index = 1, count do out[index] = Copy(locked[index]) end
    return out
end

local function Record(id, lockCount, fields)
    local recordLocks = LockedSubset(lockCount)
    local recordLockedKey = assert(Nexus.LoadoutEvidence.Intern(
        recordLocks, nil, {forceLocked=true}))
    local row = {
        id=id,title="Locked-only " .. id,author="Fixture",ownerKey="fixture@ebonhold",
        class="MAGE",postedAt=1,lastModified=1,autoDps=true,
        fingerprint="fingerprint-" .. id,lockedEchoes=recordLocks,
        lockedEvidenceKey=recordLockedKey,
    }
    for key, value in pairs(fields or {}) do row[key] = value end
    return row
end

local cases = {
    absent=Record("absent", 1, {loadoutAvailable=true,echoCount=1}),
    empty=Record("empty", 2, {echoes={},echoCount=2}),
    unresolved=Record("unresolved", 3,
        {evidenceKey="v1|unresolved",echoCount=0}),
    malformed=Record("malformed", 4,
        {echoes={{spellId="bad",stacks=1}}}),
    later=Record("later", 5, {loadoutAvailable=true,echoCount=5}),
    cross=Record("cross", 6, {echoes=Copy(locked),
        fingerprint=lockedFingerprint,loadoutAvailable=true}),
}
for id, row in pairs(cases) do NexusDB.communityBuilds[id] = row end

local expectedReasons = {
    absent="absent",empty="empty",unresolved="unresolved",
    malformed="malformed",later="absent",cross="cross-role",
}
for id, reason in pairs(expectedReasons) do
    local verdict = Nexus.LoadoutEvidence.OrdinaryCompleteness(cases[id])
    Check(verdict.complete == false and verdict.reason == reason
            and verdict.lockedOnly == true,
        "shared completeness misclassified " .. id .. ": "
            .. tostring(verdict.reason))
end
local truthyLocked = {{spellId=719999,quality=1,stacks=1,locked=1}}
local truthyVerdict = Nexus.LoadoutEvidence.OrdinaryCompleteness({
    echoes=truthyLocked,fingerprint=EchoKey(truthyLocked),
})
Check(truthyVerdict.complete == false
        and truthyVerdict.reason == "cross-role"
        and truthyVerdict.lockedOnly == true,
    "truthy legacy lock marker became ordinary completeness")

local ordinaryControl = {{spellId=720001,quality=2,stacks=1}}
local ordinaryFingerprint = assert(EchoKey(ordinaryControl))
local ordinaryExact = Copy(crossRole)
for _, row in ipairs(ordinaryExact) do row.sourceRole = "ordinary" end
local bundle = {
    schemaVersion=1,catalogVersion="locked-only-red",sourceVersion="test",
    builds={
        ["ordinary-control"]={id="ordinary-control",title="Ordinary control",
            author="Fixture",class="MAGE",fingerprint=ordinaryFingerprint,
            echoes=Copy(ordinaryControl),postedAt=1,lastModified=1},
        ["exact-recovery"]={id="exact-recovery",title="Exact recovery",
            author="Fixture",class="MAGE",fingerprint=lockedFingerprint,
            echoes=ordinaryExact,postedAt=1,lastModified=1},
    },
}
Nexus.BuildCatalog.Init(NexusDB, bundle)
local readBefore = Signature({db=NexusDB,cases=cases})

local summaries = Nexus.BuildCatalog.Summaries()
local falselyReady = 0
for id in pairs(cases) do
    if summaries[id] and summaries[id].loadoutAvailable == true then
        falselyReady = falselyReady + 1
    end
end
Check(falselyReady == 0,
    "catalog summary accepted incomplete ordinary evidence")

Nexus.DpsCapture = {
    GetCommunityEligibility=function()
        return {[lockedFingerprint]={dummy=111,lk=222,best=222,average=166.5,count=2}}
    end,
    GetDpsBoard=function() return {} end,
    IsDurationEligible=function() return true end,
    GetEchoKey=EchoKey,
    GetEchoHash=EchoKey,
}
Nexus.ViewProjections.Reset()
local communityRows, communitySummary = Nexus.ViewProjections.Builds({
    scope="all",classFilter="MAGE",currentClassOnly=false,
    qualifiedOnly=false,search="",sortMode="recent",page=1,
})
Check(type(communityRows) == "table" and communitySummary.total == 2,
    "real Community projection did not publish only complete catalog rows")
Check(communitySummary.ready == 2 and communitySummary.pending == 6,
    string.format("Community counted incomplete overlay rows as public or pending: ready=%s pending=%s",
        tostring(communitySummary.ready),tostring(communitySummary.pending)))

local delta = Nexus.BuildCatalog.DeltaSnapshot()
local broadcastable = 0
for id in pairs(cases) do if delta[id] then broadcastable = broadcastable + 1 end end
Check(broadcastable == 0,
    "Sync delta admitted incomplete ordinary evidence")
Check(Signature({db=NexusDB,cases=cases}) == readBefore,
    "catalog/projection/Sync reads rewrote locked-only fixture state")

-- Exact catalog recovery is the allowed control: a current exact ordinary
-- row can be found without blessing the incomplete record itself.
local recoveredId = Nexus.BuildCatalog.ResolveFingerprintIdentity(
    "missing-legacy-id", lockedFingerprint)
Check(recoveredId == "exact-recovery",
    "exact catalog recovery control did not resolve uniquely")

-- Candidate validation rejects an incoming locked marker when a caller places
-- that row in the ordinary parameter, including truthy legacy markers.
local candidate, candidateReason = Nexus.CandidateEvidence.Build({
    title="Cross-role candidate",ordinaryEchoes=Copy(locked),lockedEchoes={},
    sourceIdentity="cross-role",sourceRevision="1",
})
Check(candidate == nil and tostring(candidateReason):find("locked%-role"),
    "candidate accepted or erased locked-role ordinary evidence")
local legacyCandidate = Nexus.CandidateEvidence.Build({
    title="Truthy cross-role candidate",
    ordinaryEchoes={{spellId=710001,quality=1,stacks=1,locked=1}},
    lockedEchoes={},sourceIdentity="truthy-cross-role",sourceRevision="1",
})
Check(legacyCandidate == nil,
    "candidate erased a truthy legacy locked-role marker")

local catalog = {rows={}}
for _, echo in ipairs(locked) do
    catalog.rows[echo.spellId] = {
        spellId=echo.spellId,quality=echo.quality,
        groupId=echo.spellId,maxStack=1,
    }
end
Check(candidate == nil,
    "EBH1 boundary retained a candidate for locked-role ordinary rows")

-- Real Leaderboard binding keeps both actions disabled for the cross-role row.
local leaderboardRow = {
    player="Fixture",class="MAGE",dps=999,duration=60,level=60,ts=1,
    category="dummy",protocolVersion=7,buildId="cross",
    fingerprint="fingerprint-cross",echoes=Copy(locked),lockedEchoes=Copy(locked),
    build={id="cross",title="Record Loadout",author="Fixture",class="MAGE",
        fingerprint="fingerprint-cross"},
}
Nexus.DpsCapture.GetDpsBoard = function(category)
    return category == "dummy" and {leaderboardRow} or {}
end
local openedCandidate, openedBuild
Nexus.WishlistEditor = {OpenForCandidate=function(value)
    openedCandidate=value; return true
end}
Nexus.CommunityBuilds = {ShowBuild=function(id)
    openedBuild=id; return true
end}
local loadoutRequests = 0
Nexus.Sync = {RequestLoadout=function()
    loadoutRequests = loadoutRequests + 1
    return false,"queued"
end}
dofile("ui/Theme.lua")
dofile("ui/Leaderboard.lua")
Nexus.ViewProjections.Reset()
Nexus.Leaderboard.Init(nil)
Nexus.Leaderboard.Show("dummy")
for _ = 1, 20 do
    Nexus.Leaderboard.RefreshData()
    NexusLeaderboardFrame:GetScript("OnUpdate")(
        NexusLeaderboardFrame, 0.05)
end
Check(not Nexus.Leaderboard.SelectKey("fixture|string:fingerprint-cross")
        and Nexus.Leaderboard.VirtualStats().publishedRows == 0,
    "real Leaderboard published a locked-only row")
Check(openedCandidate == nil and openedBuild == nil,
    "filtered Leaderboard row reached editor or Community")
Check(loadoutRequests <= 2,
    "Leaderboard escaped its bounded recovery-request path: "
        .. tostring(loadoutRequests))

-- Legacy qualification refuses a matching fingerprint until both DPS rows
-- prove their ordinary pools independently; both carry locked markers here.
dofile("core/LegacyQualificationRepair.lua")
local function DpsRow(category)
    return {
        player="Fixture",class="MAGE",category=category,dps=123,
        duration=60,protocolVersion=6,fingerprint=lockedFingerprint,
        echoes=Copy(locked),lockedEchoes=Copy(locked),
    }
end
local qualified = Nexus.LegacyQualificationRepair.Classify({
    catalogAvailable=true,
    build={id="cross",fingerprint=lockedFingerprint},
    dummy=DpsRow("dummy"),lk=DpsRow("lk"),
})
Check(qualified.qualified == false
        and qualified.reason == "insufficient-evidence",
    "legacy qualification accepted locked-only evidence")

-- EnsureDpsBuildForEchoes refuses a semantic locked pool supplied through its
-- ordinary parameter and must not store or offer a Record Loadout to Sync.
local broadcasts = 0
Nexus.Sync = {
    BroadcastBuild=function() broadcasts = broadcasts + 1; return true end,
    RequestLoadout=function() return true end,
}
local controller = Nexus.CommunityInternals.Controller.New({
    catalog=function() return Nexus.BuildCatalog end,
    notify=function() end,
})
local beforePuts = Nexus.BuildCatalog.DebugStats().putChanges
local manufactureRows, manufactureLocks = {}, {}
for index = 1, 5 do
    manufactureRows[index] = Copy(locked[index])
    manufactureLocks[index] = Copy(locked[index])
end
local manufacturedId, manufactured = controller.EnsureDpsBuildForEchoes(
    manufactureRows,"dummy",{player="Other",class="MAGE",
        lockedEchoes=manufactureLocks})
local afterPuts = Nexus.BuildCatalog.DebugStats().putChanges
Check(manufacturedId == nil and manufactured == nil
        and afterPuts == beforePuts and broadcasts == 0,
    "EnsureDps manufactured or broadcast locked-only ordinary evidence")

-- A poisoned existing auto-build cannot win reuse by its claimed fingerprint.
local poisoned = {
    id="poisoned-auto",title="Poisoned",author="Fixture",
    ownerKey="fixture@ebonhold",class="MAGE",autoDps=true,
    fingerprint=ordinaryFingerprint,echoes={{
        spellId=ordinaryControl[1].spellId,quality=2,stacks=1,locked=true,
    }},postedAt=2,lastModified=2,
}
assert(Nexus.BuildCatalog.Put(poisoned))
local safeId, safeBuild = controller.EnsureDpsBuildForEchoes(
    Copy(ordinaryControl),"dummy",{
        player="Fixture",class="MAGE",ownerKey="fixture@ebonhold",
    })
local safeVerdict = safeBuild
    and Nexus.LoadoutEvidence.OrdinaryCompleteness(safeBuild)
Check(safeId ~= nil and safeId ~= poisoned.id
        and safeVerdict and safeVerdict.complete == true,
    "EnsureDps reused an incomplete auto-build by claimed fingerprint")

-- A later valid ordinary pool publishes one pending-to-complete edge.
local beforeLater = assert(Nexus.BuildCatalog.GetSummary("later"))
local laterEpoch, laterRevision = Nexus.BuildCatalog.RecordRevision("later")
local laterPutChanges = Nexus.BuildCatalog.DebugStats().putChanges
local completed = Copy(cases.later)
completed.echoes = Copy(ordinaryControl)
completed.fingerprint = ordinaryFingerprint
completed.echoCount = 1
completed.loadoutAvailable = true
completed.needsFullBuild = false
assert(Nexus.BuildCatalog.Put(completed))
local afterLater = assert(Nexus.BuildCatalog.GetSummary("later"))
local afterLaterEpoch, afterLaterRevision =
    Nexus.BuildCatalog.RecordRevision("later")
local afterLaterPuts = Nexus.BuildCatalog.DebugStats().putChanges
Check(afterLaterEpoch == laterEpoch and afterLaterRevision == laterRevision + 1
        and afterLaterPuts == laterPutChanges + 1,
    "later ordinary completion did not publish exactly once: "
        .. tostring(laterEpoch) .. ":" .. tostring(laterRevision) .. "->"
        .. tostring(afterLaterEpoch) .. ":" .. tostring(afterLaterRevision)
        .. " puts=" .. tostring(laterPutChanges) .. "->" .. tostring(afterLaterPuts)
        .. " count=" .. tostring(afterLater.echoCount)
        .. " fp=" .. tostring(afterLater.fingerprint))
Check(beforeLater.loadoutAvailable == false
        and afterLater.loadoutAvailable == true,
    "later completion did not publish one pending-to-complete edge")

Check(type(Nexus.LoadoutEvidence.OrdinaryCompleteness) == "function",
    "shared ordinary-completeness owner is unavailable")
local completenessStats = Nexus.LoadoutEvidence.Stats().completeness
Check(type(completenessStats) == "table"
        and completenessStats.complete > 0
        and completenessStats.lockedOnly >= 6
        and completenessStats.unresolved > 0
        and completenessStats.crossRole > 0,
    "sanitized completeness diagnostics lost required outcome classes")
Check(NexusDB.futureRoot.keep == true,
    "locked-only characterization rewrote unrelated SavedVariables state")
print(string.format(
    "locked-only loadout characterization: cases=6 locks=1-6 catalog_ready=%d community_ready=%d sync=%d copy=disabled open=disabled ebh1=no qualification=refused writes=1 expected_red=0 checks=%d -- OK",
    falselyReady,communitySummary.ready,broadcastable,checks))
