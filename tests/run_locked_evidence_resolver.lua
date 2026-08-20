-- Stage 36.5 expected red: Community, Leaderboard/Wishlist Copy, and Peer
-- Debug must consume one category-aware locked-Echo resolver. Locked evidence
-- is supplemental: it never supplies missing ordinary-loadout authority.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

local Controller = assert(Nexus.CommunityInternals.Controller)
local Projection = assert(Nexus.CommunityInternals.Projection)
local CandidateEvidence = assert(Nexus.CandidateEvidence)
local Catalog = assert(Nexus.BuildCatalog)

local failures = {}
local desiredChecks, controls = 0, 0
local groupRed = {
    owner=0, community=0, projection=0, recovered=0,
    integrity=0, warm=0, peer=0,
}

local function Desired(group, ok, label)
    desiredChecks = desiredChecks + 1
    if not ok then
        failures[#failures + 1] = group .. ": " .. label
        groupRed[group] = (groupRed[group] or 0) + 1
    end
end

local function Control(ok, label)
    controls = controls + 1
    assert(ok, "green control failed: " .. tostring(label))
end

local function Clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[Clone(key, seen)] = Clone(child, seen)
    end
    return out
end

local function Signature(value, seen)
    if type(value) ~= "table" then
        return type(value) .. ":" .. tostring(value)
    end
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

local function EchoKey(rows)
    local counts, ids = {}, {}
    for _, row in ipairs(rows or {}) do
        local id = tonumber(row.spellId or row.id)
        local stacks = tonumber(row.stacks or row.count) or 1
        if id then counts[id] = (counts[id] or 0) + stacks end
    end
    for id in pairs(counts) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        parts[#parts + 1] = tostring(id) .. "x" .. tostring(counts[id])
    end
    return table.concat(parts, ",")
end

local function SamePool(left, right)
    return Signature(left) == Signature(right)
end

local ordinary = {
    {spellId=736501,quality=3,stacks=2,future={ordinary=1}},
    {spellId=736502,quality=4,stacks=1,future={ordinary=2}},
    {spellId=736503,quality=2,stacks=1,future={ordinary=3}},
}
local dummyLocked = {
    {spellId=736601,quality=4,stacks=1,future={locked="dummy-1"}},
    {spellId=736602,quality=3,stacks=2,future={locked="dummy-2"}},
}
local lkLocked = {
    {spellId=736601,quality=4,stacks=1,future={locked="lk-1"}},
    {spellId=736603,quality=2,stacks=1,future={locked="lk-2"}},
}
local build = {
    id="stage36-locked-resolver", title="Locked Resolver Fixture",
    author="Fixture", ownerKey="fixture@ebonhold", class="MAGE",
    echoes=Clone(ordinary), fingerprint=EchoKey(ordinary),
    postedAt=1, lastModified=1,
}

NexusDB = {
    settingsVersion=2,settings={},chars={},buildFilters={},dpsCapture={},
    communityBuilds={[build.id]=Clone(build)},syncTombstones={},
    futureRoot={keep=true},
}
Nexus.Store.Init()
Catalog.Init(NexusDB, Nexus.BundledBuilds)

local resolvedId, resolvedBy = Catalog.ResolveFingerprintIdentity(
    "historical-stage36-id", build.fingerprint)
Control(resolvedId == build.id and resolvedBy == "fingerprint",
    "exact catalog identity did not resolve the recovered raw build ID")

local function Record(category, locked, overrides)
    local row = {
        player="Fixture",class="MAGE",category=category,
        dps=category == "dummy" and 410000 or 390000,
        duration=category == "dummy" and 30 or 180,
        level=80,ts=100,protocolVersion=7,
        buildId=build.id,fingerprint=build.fingerprint,
        echoes=Clone(ordinary),lockedEchoes=Clone(locked),
        lockedFingerprint=EchoKey(locked),
        build=Clone(build),resolvedBuildId=build.id,
    }
    for key, value in pairs(overrides or {}) do row[key] = value end
    return row
end

local boards = {dummy={},lk={}}
local records = {dummy=nil,lk=nil}
local boardReads, identityReads = 0, 0

local function InstallRecords(dummy, lk, boardDummy, boardLk)
    records.dummy, records.lk = dummy, lk
    boards.dummy = boardDummy or (dummy and {dummy} or {})
    boards.lk = boardLk or (lk and {lk} or {})
    boardReads, identityReads = 0, 0
    Nexus.DpsCapture = {
        GetDpsBoard=function(category)
            boardReads = boardReads + 1
            return boards[category] or {}
        end,
        GetRecordForIdentity=function(_, _, _, category)
            identityReads = identityReads + 1
            return records[category]
        end,
        GetCommunityEligibility=function() return {} end,
        GetCachedCommunityQualification=function()
            return {dummy=records.dummy and 1 or 0,
                lk=records.lk and 1 or 0}
        end,
        GetLeaderboard=function() return {} end,
        GetLeaderboardForEchoes=function() return {} end,
        GetPersonalBest=function() return nil end,
        HashCacheStats=function() return {initialized=true,rows=2} end,
        RejectionStats=function() return {} end,
        OutboundStats=function() return {} end,
        ProtocolVersion=function() return 7 end,
    }
end

local controller = Controller.New({catalog=function() return Catalog end})

------------------------------------------------------------------------
-- Existing single-category behavior is retained, but two-category evidence
-- must be compared instead of accepting the first board row encountered.
------------------------------------------------------------------------

local dummy = Record("dummy", dummyLocked)
InstallRecords(dummy, nil)
local resolved = controller.LockedEchoesForBuild(build)
Control(SamePool(resolved, dummyLocked),
    "Dummy-only locked evidence did not retain its exact identities")

local lk = Record("lk", lkLocked)
InstallRecords(nil, lk)
resolved = controller.LockedEchoesForBuild(build)
Control(SamePool(resolved, lkLocked),
    "Lich-King-only locked evidence did not retain its exact identities")

dummy = Record("dummy", dummyLocked)
lk = Record("lk", dummyLocked)
InstallRecords(dummy, lk)
resolved = controller.LockedEchoesForBuild(build)
Control(SamePool(resolved, dummyLocked),
    "matching Dummy/Lich King evidence changed locked identities")

local disagreeReason = "record categories disagree on locked Echo evidence"
dummy = Record("dummy", dummyLocked)
lk = Record("lk", lkLocked)
InstallRecords(dummy, lk)
local conflict, conflictReason = controller.LockedEchoesForBuild(build)
Desired("community", conflict == nil,
    "Community accepted the first category when locked evidence disagreed")
Desired("community", conflictReason == disagreeReason
        and #conflictReason <= 96,
    "Community did not return the bounded category-disagreement reason")

------------------------------------------------------------------------
-- The current Leaderboard/Wishlist Copy path already refuses this combined
-- row. Preserve that green refusal while moving ownership to the shared pure
-- resolver rather than keeping Leaderboard's private parallel implementation.
------------------------------------------------------------------------

Nexus.ViewProjections.Reset()
dofile("ui/Theme.lua")
dofile("ui/Leaderboard.lua")
Nexus.Sync = {
    IsReceiving=function() return false end,
    ReceiveTimeLeft=function() return 0 end,
    LastSyncNewCount=function() return 0 end,
    Stats=function() return {received=0} end,
    RequestSync=function() return true end,
}
Nexus.Leaderboard.Init({})
Nexus.Leaderboard.Show("combined")
Nexus.Leaderboard.RefreshData()
local combinedKey = "fixture|string:" .. build.fingerprint
Control(Nexus.Leaderboard.SelectKey(combinedKey),
    "real combined Leaderboard row was not selectable")
local leaderboardDetail = assert(NexusLeaderboardFrame._leaderboardDetail,
    "real Leaderboard detail panel was not assembled")
Control(not leaderboardDetail.copy:IsEnabled()
        and leaderboardDetail.more:GetText():find(disagreeReason,1,true),
    "Leaderboard/Wishlist Copy did not refuse conflicting locked evidence")

local recoveredDummy = Record("dummy", dummyLocked, {
    buildId="historical-dummy-stage36",resolvedBuildId=build.id,build=nil,
    protocolVersion=6,
})
local recoveredLk = Record("lk", dummyLocked, {
    buildId="historical-lk-stage36",resolvedBuildId=build.id,build=nil,
    protocolVersion=6,
})
recoveredDummy.build, recoveredLk.build = nil, nil
InstallRecords(recoveredDummy, recoveredLk)
Nexus.DpsCapture.GetCharacterBest = function(category)
    local current = Clone(records[category])
    if current then current.resolvedBuildId = nil end
    return current
end
Nexus.ViewProjections.Reset()
Nexus.Leaderboard.Show("combined")
Nexus.Leaderboard.RefreshData()
local recoveredSelected = Nexus.Leaderboard.SelectKey(combinedKey)
Control(recoveredSelected
        and NexusLeaderboardFrame._leaderboardDetail.copy:IsEnabled(),
    "matching recovered category records did not remain copyable")
Nexus.DpsCapture.GetCharacterBest = nil
InstallRecords(dummy, lk)

local lockedOnly, lockedOnlyReason = CandidateEvidence.Build({
    title="locked only",sourceIdentity="locked-only",sourceRevision="1",
    ordinaryEchoes={},lockedEchoes=dummyLocked,
})
Control(lockedOnly == nil
        and tostring(lockedOnlyReason):find("ordinary",1,true),
    "locked-only evidence gained ordinary-loadout authority")

------------------------------------------------------------------------
-- Community detail uses the same real record readers. It currently stops at
-- Dummy and displays evidence that the assembled Leaderboard refuses.
------------------------------------------------------------------------

local projectionReads = 0
local projection = Projection.New({
    builds=function() return {},{} end,
    buildsCurrent=function() return true end,
    loadBuild=function(id) return id == build.id and build or nil end,
    revisionSnapshot=function() return {build=1,dps=1} end,
    dpsRecord=function(_, category)
        projectionReads = projectionReads + 1
        return records[category]
    end,
    leaderboard=function() return {} end,
    personalBest=function() return nil end,
})
local detail = assert(projection.Detail(build.id, {}))
local projectionStats = projection.Stats()
Desired("projection", detail.lockedEchoes == nil
        and detail.lockedEvidenceReason == disagreeReason,
    "Community detail projected the first category instead of the conflict")
Desired("projection", projectionReads == 2
        and projectionStats.detail.boardReads == 2,
    "Community detail stopped before comparing both narrow category records")
local readsBeforeWarm = projectionReads
Control(projection.Detail(build.id, {}) == detail
        and projectionReads == readsBeforeWarm,
    "warm Community detail repeated locked-evidence record reads")

-- Exercise the assembled Community Copy button as a second Wishlist entry
-- point. A conflict must stop before the editor opens, with the same bounded
-- reason that the Leaderboard already presents.
dofile("ui/CommunityBuilds.lua")
local communityOpened
Nexus.WishlistEditor = {
    OpenForCandidate=function(candidate)
        communityOpened = candidate
        return true
    end,
}
Nexus.CommunityBuilds.Init(nil, nil)
Nexus.CommunityBuilds.Show()
Nexus.CommunityBuilds.Select(build.id)
local communityDetail = assert(NexusCommunityBuildsFrame._detailPanel,
    "real Community detail panel was not assembled")
local messages, originalPrint = {}, print
print = function(...)
    local fields = {}
    for index = 1, select("#", ...) do
        fields[index] = tostring(select(index, ...))
    end
    messages[#messages + 1] = table.concat(fields, " ")
end
communityDetail.lockBtn:GetScript("OnClick")()
print = originalPrint
local communityRefusal = false
for _, message in ipairs(messages) do
    if message:find(disagreeReason,1,true) then communityRefusal = true end
end
Desired("community", communityOpened == nil,
    "Community Copy opened Wishlist Editor with conflicting locked evidence")
Desired("community", communityRefusal,
    "Community Copy did not present the shared bounded conflict reason")

------------------------------------------------------------------------
-- Claimed locked fingerprints are untrusted. The shared owner must recompute
-- them and return defensive materializations, preserving unknown row fields.
------------------------------------------------------------------------

local mismatched = Record("dummy", dummyLocked, {
    lockedFingerprint="736699x1",
})
InstallRecords(mismatched, nil)
local invalid, invalidReason = controller.LockedEchoesForBuild(build)
Desired("integrity", invalid == nil,
    "Community trusted a claimed locked fingerprint over the locked pool")
Desired("integrity", invalidReason ==
        "locked Echo fingerprint does not match its evidence"
        and #invalidReason <= 96,
    "claimed-fingerprint refusal was missing or unbounded")

local defensiveSource = Record("dummy", dummyLocked)
InstallRecords(defensiveSource, nil)
local defensive = controller.LockedEchoesForBuild(build)
local sourceBeforeMutation = Signature(defensiveSource.lockedEchoes)
if type(defensive) == "table" and type(defensive[1]) == "table" then
    defensive[1].spellId = 736999
    defensive[1].future.locked = "consumer mutation"
end
Desired("integrity",
    Signature(defensiveSource.lockedEchoes) == sourceBeforeMutation,
    "Community returned mutable DPS locked-evidence storage")

local falseCategory = CandidateEvidence.ResolveLocked({
    build=build,dummyRecord=false,
})
Desired("integrity", falseCategory.status == "invalid",
    "false category evidence was treated as an absent record")
for _, malformedEchoes in ipairs({false,"malformed",37}) do
    local malformedRecord = Record("dummy", dummyLocked)
    malformedRecord.echoes = malformedEchoes
    local malformedResult = CandidateEvidence.ResolveLocked({
        build=build,dummyRecord=malformedRecord,
    })
    Desired("integrity", malformedResult.status == "invalid",
        "non-table ordinary record evidence was accepted")
end
local invertedIdentity = Record("dummy", dummyLocked, {
    buildId=build.id,resolvedBuildId="other-stage36-id",
})
local invertedResult = CandidateEvidence.ResolveLocked({
    build=build,dummyRecord=invertedIdentity,
})
Desired("integrity", invertedResult.status == "invalid",
    "conflicting raw and resolved build identities were accepted")

------------------------------------------------------------------------
-- A protocol-recovered raw ID is acceptable only through the catalog's exact
-- fingerprint identity. The consumer must use the narrow indexed record API;
-- board traversal is forbidden on both cold and warm detail paths.
------------------------------------------------------------------------

local recovered = Record("dummy", dummyLocked, {
    buildId="historical-stage36-id",resolvedBuildId=build.id,
    build=nil,protocolVersion=6,
})
InstallRecords(recovered, nil)
local recoveredLocks = controller.LockedEchoesForBuild(build)
Desired("recovered", SamePool(recoveredLocks, dummyLocked),
    "exact recovered/catalog identity lost its locked evidence")
Desired("recovered", boardReads == 0 and identityReads > 0,
    "recovered locked evidence traversed DPS boards instead of its identity index")

-- The real narrow DPS owner must derive that recovered identity itself; a
-- consumer fixture is not allowed to manufacture resolvedBuildId.
local injectedDps = Nexus.DpsCapture
local originalDpsDb = NexusDB.dpsCapture
local originalFingerprintHash = build.fingerprintHash
build.fingerprintHash = "stage36-shared-hash"
NexusDB.dpsCapture = {characterBest={dummy={fixture={
    player="Fixture",class="MAGE",category="dummy",dps=410000,
    duration=30,level=80,ts=100,protocolVersion=6,
    buildId="historical-stage36-id",fingerprint=build.fingerprint,
    loadoutHash=build.fingerprintHash,
    echoes=Clone(ordinary),lockedEchoes=Clone(dummyLocked),
},collision={
    player="Collision",class="MAGE",category="dummy",dps=999999,
    duration=30,level=80,ts=101,protocolVersion=6,
    buildId="collision-stage36-id",fingerprint="736699x1",
    loadoutHash=build.fingerprintHash,
    echoes={{spellId=736699,stacks=1}},
    lockedEchoes={{spellId=736698,stacks=1}},
}},lk={}},personalBest={},buildBest={}}
dofile("core/DpsCapture.lua")
local realDps = Nexus.DpsCapture
realDps.Init({}, {})
local realController = Controller.New({catalog=function() return Catalog end})
local realRecord = realDps.GetRecordForIdentity(
    build.id, build.fingerprint, build.fingerprintHash, "dummy")
local realRecovered, realRecoveredReason =
    realController.LockedEchoesForBuild(build)
Desired("recovered", realRecoveredReason == nil
        and realRecord and realRecord.fingerprint == build.fingerprint
        and realRecord.resolvedBuildId == build.id
        and type(realRecovered) == "table"
        and #realRecovered == #dummyLocked
        and EchoKey(realRecovered) == EchoKey(dummyLocked),
    "real indexed DPS owner did not publish the exact recovered identity")
Nexus.DpsCapture = injectedDps
NexusDB.dpsCapture = originalDpsDb
build.fingerprintHash = originalFingerprintHash

local largeBoard = {}
for index = 1, 200 do
    largeBoard[index] = Record("dummy", {{spellId=737000 + index,stacks=1}}, {
        player="Decoy" .. tostring(index),buildId="decoy-" .. tostring(index),
        fingerprint=tostring(737000 + index) .. "x1",build=nil,
        resolvedBuildId=nil,
    })
end
largeBoard[201] = Record("dummy", dummyLocked)
InstallRecords(largeBoard[201], nil, largeBoard, {})
local warmOne = controller.LockedEchoesForBuild(build)
local warmTwo = controller.LockedEchoesForBuild(build)
Desired("warm", SamePool(warmOne, dummyLocked)
        and SamePool(warmTwo, dummyLocked)
        and boardReads == 0 and identityReads > 0 and identityReads <= 4,
    "warm resolution repeated full-board traversal or exceeded fixed record reads")

Desired("owner", type(CandidateEvidence.ResolveLocked) == "function",
    "CandidateEvidence does not expose the shared pure locked resolver")

------------------------------------------------------------------------
-- Peer Debug must report only a bounded scalar outcome/reason from the same
-- resolution. It must not serialize the locked spell IDs themselves.
------------------------------------------------------------------------

dummy = Record("dummy", dummyLocked)
lk = Record("lk", lkLocked)
InstallRecords(dummy, lk)
Nexus.DpsCapture.GetCachedLockedEvidence = function(id)
    if id ~= build.id then return nil end
    return {dummy=Clone(dummy),lk=Clone(lk)}
end
Nexus.BuildHashCache = {Stats=function() return {} end}
Nexus.RuntimeBuildLabel = function() return "source" end
Nexus.VERSION = "1.20.0-beta.1"
dofile("core/PeerDebug.lua")
Nexus.PeerDebug.Start()
Nexus.PeerDebug.SelectBuild(build.id)
local peerStatus, peerReason
if type(Nexus.PeerDebug.ExplainLockedEvidence) == "function" then
    peerStatus, peerReason = Nexus.PeerDebug.ExplainLockedEvidence(build.id)
end
Desired("peer", peerStatus == "conflict"
        and peerReason == disagreeReason and #peerReason <= 96,
    "Peer Debug lacks the bounded shared locked-evidence explanation")
local peerReport = Nexus.PeerDebug.Report()
Desired("peer", peerReport:find("locked_evidence=conflict",1,true)
        and peerReport:find("locked_reason=" .. disagreeReason,1,true),
    "Peer Test report omits the locked-evidence conflict outcome/reason")
Control(not peerReport:find("736601",1,true)
        and not peerReport:find("736603",1,true),
    "Peer Test report disclosed raw locked Echo identities")
Control(NexusDB.futureRoot.keep == true,
    "read-only characterization changed unknown SavedVariables state")

local summary = string.format(
    "desired=%d expected_red=%d controls=%d owner=%d community=%d projection=%d recovered=%d integrity=%d warm=%d peer=%d",
    desiredChecks,#failures,controls,groupRed.owner,groupRed.community,
    groupRed.projection,groupRed.recovered,groupRed.integrity,
    groupRed.warm,groupRed.peer)
if #failures > 0 then
    error("EXPECTED RED [Stage 36.5 locked evidence resolver]: " .. summary
        .. "\n - " .. table.concat(failures, "\n - "))
end
print("Stage 36.5 locked evidence resolver: " .. summary .. " -- OK")
