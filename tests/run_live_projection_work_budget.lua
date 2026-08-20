-- Live test.2 view regression: Community and Leaderboard callbacks must start
-- O(1), retain last-good data, and advance real production jobs in deterministic
-- small units. Fixture providers expose 1,000 builds and 1,200 DPS rows; wrappers
-- count returned work and comparisons without replacing projection algorithms.
local H = dofile("tests/harness.lua")
dofile("ui/Theme.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

UnitName = function() return "LiveBudgetMage" end
UnitClass = function() return "Mage", "MAGE" end
GetNormalizedRealmName = function() return "Ebonhold" end

NexusDB = {
    settingsVersion=2,settings={},chars={},buildFilters={
        scope="all",search="",sortMode="recent",classFilter="MAGE",
    },
    communityBuilds={},
    dpsCapture={characterBest={dummy={},lk={}},personalBest={},buildBest={}},
}

for index = 1, 1000 do
    local id = string.format("live-budget-%04d", index)
    local fingerprint = tostring(720000 + index) .. "x1"
    NexusDB.communityBuilds[id] = {
        id=id,title=string.format("Live Build %04d", 1001-index),
        description=index % 11 == 0 and "needle" or "",
        author=index % 10 == 0 and "LiveBudgetMage" or "Peer",
        ownerKey=index % 10 == 0
            and "livebudgetmage@ebonhold" or "peer@ebonhold",
        ownerVerified=index % 10 == 0 and true or nil,
        realm=index % 10 == 0 and "ebonhold" or nil,
        isMine=index % 10 == 0,
        class=index % 5 == 0 and "WARRIOR" or "MAGE",
        postedAt=index,lastModified=index,fingerprint=fingerprint,
        echoes={{spellId=720000+index,quality=3,stacks=1}},
    }
    if index <= 600 then
        for _, category in ipairs({"dummy", "lk"}) do
            NexusDB.dpsCapture.characterBest[category]
                [category .. "@" .. index] = {
                player=string.format("Player%03d", index),
                ownerKey=string.format("player%03d@ebonhold", index),
                ownerVerified=true,realm="ebonhold",
                dps=(category == "dummy" and 30000000 or 28000000)-index,
                level=80,ts=index,duration=60,class="MAGE",
                buildId=id,fingerprint=fingerprint,
                echoes={{spellId=720000+index,count=1}},protocolVersion=7,
            }
        end
    end
end

Nexus.Store.Init()
dofile("core/DpsCapture.lua")
local Adapter = {
    Slots=function() return {bySlot={},activeSlot=0} end,
    GetWishlistCandidates=function() return {} end,
    Catalog=function() return {rows={}} end,
    Owned=function() return {bySpell={},total=0,synced=true} end,
    LockedOwned=function() return {bySpell={}} end,
    Wishlist=function() return nil end,
}
local receiving, remaining = false, 0
Nexus.Sync = {
    IsReceiving=function() return receiving end,
    ReceiveTimeLeft=function() return receiving and remaining or 0 end,
    LastSyncNewCount=function() return 0 end,
    Stats=function() return {received=0} end,
    GetLeaderboardSyncStatus=function()
        return receiving and "syncing" or "idle",0,0,{}
    end,
    RequestSync=function() return true end,
    RequestLoadout=function() return true end,
    BroadcastBuildSummary=function() return true end,
}
Nexus.DpsCapture.Init(Adapter, Nexus.Sync)

-- BuildCatalog normalization owns the canonical fingerprint. Keep stored DPS
-- rows exact before the identity index is first materialized.
for _, category in ipairs({"dummy", "lk"}) do
    for _, row in pairs(NexusDB.dpsCapture.characterBest[category]) do
        local build = Nexus.BuildCatalog.Get(row.buildId)
        row.fingerprint = assert(build and build.fingerprint)
    end
end

local phases, activePhase = {}, nil
local function CountRows(rows)
    local count = 0
    for _ in pairs(type(rows) == "table" and rows or {}) do count = count + 1 end
    return count
end
local function Begin(name)
    assert(not activePhase, "nested work phase: " .. tostring(name))
    activePhase = {
        name=name,acquisitions=0,sourceRows=0,joins=0,comparisons=0,
        copies=0,publications=0,binds=0,
    }
end
local function SafeVirtual(owner)
    local ok, stats = pcall(owner and owner.VirtualStats or function() return {} end)
    return ok and type(stats) == "table" and stats or {}
end
local function PublicationSnapshot()
    local community = SafeVirtual(Nexus.CommunityBuilds)
    local leaderboard = SafeVirtual(Nexus.Leaderboard)
    return {
        publications=(tonumber(community.dataRefreshes) or 0)
            + (tonumber(leaderboard.dataRefreshes) or 0),
        binds=(tonumber(community.dataBinds) or 0)
            + (tonumber(leaderboard.dataBinds) or 0),
        communityPublications=tonumber(community.dataRefreshes) or 0,
        leaderboardPublications=tonumber(leaderboard.dataRefreshes) or 0,
        communityBinds=tonumber(community.dataBinds) or 0,
        leaderboardBinds=tonumber(leaderboard.dataBinds) or 0,
    }
end
local phaseBefore, phaseClock
local function Start(name)
    phaseBefore = PublicationSnapshot()
    phaseClock = os.clock and os.clock() or nil
    Begin(name)
end
local function Finish()
    local after = PublicationSnapshot()
    activePhase.cpuSeconds = phaseClock and os.clock
        and math.max(0, os.clock() - phaseClock) or 0
    activePhase.publications = after.publications - phaseBefore.publications
    activePhase.binds = after.binds - phaseBefore.binds
    phases[#phases + 1] = activePhase
    activePhase = nil
end

local function WrapRows(owner, name)
    local original = assert(owner[name], "missing production reader: " .. name)
    owner[name] = function(...)
        local rows, second, third = original(...)
        if activePhase then
            activePhase.acquisitions = activePhase.acquisitions + 1
            activePhase.sourceRows = activePhase.sourceRows + CountRows(rows)
        end
        return rows, second, third
    end
end
WrapRows(Nexus.BuildCatalog, "Summaries")
WrapRows(Nexus.DpsCapture, "GetCommunityEligibility")
WrapRows(Nexus.DpsCapture, "GetDpsBoard")

local realSort = table.sort
table.sort = function(rows, comparator)
    if not (activePhase and type(comparator) == "function") then
        return realSort(rows, comparator)
    end
    return realSort(rows, function(left, right)
        activePhase.comparisons = activePhase.comparisons + 1
        return comparator(left, right)
    end)
end

local projections = Nexus.ViewProjections
local realBuilds = assert(projections.Builds)
projections.Builds = function(...)
    local rows, summary, err = realBuilds(...)
    if activePhase then activePhase.copies = activePhase.copies + CountRows(rows) end
    return rows, summary, err
end
local realLeaderboard = assert(projections.Leaderboard)
projections.Leaderboard = function(category, ...)
    local rows, summary, err = realLeaderboard(category, ...)
    if activePhase then
        local count = CountRows(rows)
        activePhase.copies = activePhase.copies + count
        if category == "combined" then activePhase.joins = activePhase.joins + count end
    end
    return rows, summary, err
end

local instances = {}
for name, factory in pairs({
    controller=Nexus.CommunityInternals.Controller,
    renderer=Nexus.CommunityInternals.Renderer,
}) do
    local original = assert(factory.New)
    factory.New = function(options)
        local instance = original(options)
        instances[name] = instance
        return instance
    end
end

Nexus.Panel = {
    AttachMenuFrame=function() return true end,
    CloseOtherWindows=function() return true end,
    Refresh=function() return true end,
}
dofile("ui/CommunityBuilds.lua")
dofile("ui/Leaderboard.lua")
Nexus.CommunityBuilds.Init(Adapter, nil)
Nexus.Leaderboard.Init(Adapter)
Nexus.Scheduler.Init()
Nexus.ViewRefresh.Init()

local C, L = Nexus.CommunityBuilds, Nexus.Leaderboard
Start("community.show") C.Show() Finish()
Start("leaderboard.show.combined") L.Show("combined") Finish()

-- Capture both current synchronous owners before additional navigation. The
-- baseline must fail here quickly; after the resumable cutover these starts
-- are O(1) and the remainder exercises churn, fairness, and publication.
local initialSource, initialComparisons, initialCpu = 0, 0, 0
local initialSourcePhase, initialComparisonPhase, initialCpuPhase
for _, phase in ipairs(phases) do
    if phase.sourceRows > initialSource then
        initialSource, initialSourcePhase = phase.sourceRows, phase.name
    end
    if phase.comparisons > initialComparisons then
        initialComparisons, initialComparisonPhase =
            phase.comparisons, phase.name
    end
    if phase.cpuSeconds > initialCpu then
        initialCpu, initialCpuPhase = phase.cpuSeconds, phase.name
    end
end
print(string.format(
    "live projection cold-start characterization: sourceMax=%d@%s compareMax=%d@%s cpuMax=%.3fs@%s",
    initialSource,tostring(initialSourcePhase),initialComparisons,
    tostring(initialComparisonPhase),initialCpu,tostring(initialCpuPhase)))
assert(initialSource <= 25,
    string.format("one cold UI callback materialized %d source rows in %s (budget 25)",
        initialSource, tostring(initialSourcePhase)))
assert(initialComparisons <= 500,
    string.format("one cold UI callback performed %d comparisons (budget 500)",
        initialComparisons))

local function PumpOne(elapsed)
    H.now = H.now + elapsed
    Nexus.Scheduler.Tick(H.now)
    local communityFrame = H.frames.NexusCommunityBuildsFrame
    local communityUpdate = communityFrame
        and communityFrame:GetScript("OnUpdate")
    if communityUpdate then communityUpdate(communityFrame, elapsed) end
    local leaderboardFrame = H.frames.NexusLeaderboardFrame
    local leaderboardUpdate = leaderboardFrame
        and leaderboardFrame:GetScript("OnUpdate")
    if leaderboardUpdate then leaderboardUpdate(leaderboardFrame, elapsed) end
end

Start("community.search")
local communitySearch = assert(H.frames.NexusBuildsSearch,
    "real Community search box unavailable")
communitySearch:SetText("needle")
assert(communitySearch:GetScript("OnTextChanged"),
    "real Community search callback unavailable")(communitySearch)
Finish()
Start("community.scope")
instances.controller.SetFilter("scope", "mine")
Finish()
Start("community.sort")
instances.controller.SetFilter("sortMode", "dps")
Finish()
Start("community.selection") C.Select("live-budget-0010") Finish()
Start("leaderboard.category") L.SetCategory("dummy") Finish()
Start("leaderboard.class") L.SetClassFilter("MAGE") Finish()
Start("leaderboard.search")
local leaderboardSearch = assert(H.frames.NexusLeaderboardSearch,
    "real Leaderboard search box unavailable")
leaderboardSearch:SetText("Player 01")
assert(leaderboardSearch:GetScript("OnTextChanged"),
    "real Leaderboard search callback unavailable")(leaderboardSearch)
Finish()

-- Revision-driven work and Community churn remain deferred during active
-- Sync, but an explicit Leaderboard category/class/search request must finish
-- through the same bounded pumps instead of leaving stale rows indefinitely.
receiving, remaining = true, 3
local beforeReceive = PublicationSnapshot()
local beforeCommunityRows = C.VirtualStats().results
Start("active-sync.invalidate")
for index = 1, 100 do
    Nexus.Revisions.Advance(Nexus.Revisions.BUILD_LIBRARY_CHANGED,
        {source="live-budget",index=index})
    Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,
        {source="live-budget",index=index})
end
instances.controller.SetFilter("search", "Live Build")
instances.controller.SetFilter("currentClassOnly", false)
instances.controller.SetFilter("qualifiedOnly", false)
local activeCommunityFrame = assert(H.frames.NexusCommunityBuildsFrame)
assert(activeCommunityFrame._nextPageBtn:GetScript("OnClick"),
    "real Community next-page callback unavailable")(
        activeCommunityFrame._nextPageBtn)
L.SetCategory("combined")
L.SetClassFilter("ALL")
leaderboardSearch:SetText("")
assert(leaderboardSearch:GetScript("OnTextChanged"))(
    leaderboardSearch)
Finish()
for index = 1, 600 do
    Start("active-sync.pump." .. index)
    PumpOne(0.05)
    Finish()
    if index == 2 then
        Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,
            {source="interactive-sync-restart"})
    end
    if not L.VirtualStats().interactivePending then break end
end
local duringReceive = PublicationSnapshot()
local activeCommunity = C.VirtualStats()
local activeLeaderboard = L.VirtualStats()
local communityFrame = activeCommunityFrame
assert(duringReceive.publications == beforeReceive.publications + 1
    and duringReceive.binds == beforeReceive.binds + 1,
    "active Sync did not publish exactly one explicit Leaderboard query")
assert(activeCommunity.results == beforeCommunityRows
    and activeLeaderboard.publishedRows > 0
    and activeLeaderboard.category == "combined"
    and activeLeaderboard.classFilter == "ALL"
    and activeLeaderboard.interactivePending == false
    and communityFrame._classDropBtn:GetText() == "All Classes"
    and communityFrame._qualifiedBtn:GetText() == "All Shared",
    "active Sync changed Community data or left Leaderboard controls stale")
assert(communityFrame._pageText:GetText():find("2 / ",1,true)==1,
    "active Sync froze the visible Community page state")

receiving, remaining = false, 0
for index = 1, 600 do
    Start("quiet.pump." .. index)
    PumpOne(0.05)
    Finish()
end
local afterQuiet = PublicationSnapshot()
assert(afterQuiet.publications == beforeReceive.publications + 2
    and afterQuiet.binds == beforeReceive.binds + 2,
    string.format(
        "post-Sync quiet window did not publish Community and Leaderboard exactly once each (total publications %d->%d, binds %d->%d; Community %d/%d, Leaderboard %d/%d)",
        beforeReceive.publications, afterQuiet.publications,
        beforeReceive.binds, afterQuiet.binds,
        afterQuiet.communityPublications, afterQuiet.communityBinds,
        afterQuiet.leaderboardPublications, afterQuiet.leaderboardBinds))

-- Hidden dirty work must remain cheap until the view is shown again.
C.Hide(); L.Hide()
local beforeHidden = PublicationSnapshot()
Start("hidden.invalidate")
Nexus.Revisions.Advance(Nexus.Revisions.BUILD_LIBRARY_CHANGED,
    {source="hidden-live-budget"})
Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,
    {source="hidden-live-budget"})
PumpOne(0.05)
PumpOne(0.05)
Finish()
local afterHidden = PublicationSnapshot()
assert(afterHidden.publications == beforeHidden.publications
    and afterHidden.binds == beforeHidden.binds,
    "hidden dirty views performed heavy publication")
Start("community.reshow") C.Show() Finish()
Start("leaderboard.reshow") L.Show("combined") Finish()
for index = 1, 600 do
    Start("reshow.pump." .. index)
    PumpOne(0.05)
    Finish()
end
local afterReshow = PublicationSnapshot()
assert(afterReshow.publications == beforeHidden.publications + 2
    and afterReshow.binds == beforeHidden.binds + 2,
    "reshown dirty views did not each publish once after bounded construction")

table.sort = realSort

local maxima = {
    sourceRows=0,comparisons=0,joins=0,copies=0,publications=0,binds=0,
}
local worst = {}
for _, phase in ipairs(phases) do
    for key in pairs(maxima) do
        if phase[key] > maxima[key] then
            maxima[key], worst[key] = phase[key], phase.name
        end
    end
end
print(string.format(
    "live projection characterization: phases=%d sourceMax=%d@%s compareMax=%d@%s joinsMax=%d copiesMax=%d publicationsMax=%d bindsMax=%d",
    #phases,maxima.sourceRows,tostring(worst.sourceRows),
    maxima.comparisons,tostring(worst.comparisons),maxima.joins,
    maxima.copies,maxima.publications,maxima.binds))

assert(Nexus.BuildCatalog.Count() == 1000
    and Nexus.DpsCapture.IdentityLookupStats().indexedRows == 1200,
    "large fixture capped or lost catalog/DPS source data")
assert(maxima.sourceRows <= 25,
    string.format("one UI callback/OnUpdate materialized %d source rows in %s (budget 25)",
        maxima.sourceRows, tostring(worst.sourceRows)))
assert(maxima.comparisons <= 500,
    string.format("one UI callback/OnUpdate performed %d comparisons in %s (budget 500)",
        maxima.comparisons, tostring(worst.comparisons)))

local workStats = assert(type(projections.WorkStats) == "function"
    and projections.WorkStats(),
    "resumable Community/Leaderboard work counters are unavailable")
for _, key in ipairs({
    "acquisitions","sourceRows","joins","comparisons","copies","sortMoves",
    "publications","cancellations","binds",
}) do
    assert(type(workStats[key]) == "number",
        "resumable work counter unavailable: " .. key)
end
assert((tonumber(workStats.cancellations) or 0) >= 2
    and (tonumber(workStats.publications) or 0) >= 2
    and (tonumber(workStats.communityPumps) or 0) > 0
    and (tonumber(workStats.leaderboardPumps) or 0) > 0
    and (tonumber(workStats.maxSourceRowsPerPump) or math.huge) <= 25
    and (tonumber(workStats.maxComparisonsPerPump) or math.huge) <= 500
    and (tonumber(workStats.maxSortMovesPerPump) or math.huge) <= 500
    and (tonumber(workStats.maxJoinsPerPump) or math.huge) <= 25
    and (tonumber(workStats.maxCopiesPerPump) or math.huge) <= 25,
    "resumable work counters lost cancellation, publication, or unit bounds")
print(string.format(
    "resumable work counters: sourceMax=%d compareMax=%d sortMoveMax=%d joinMax=%d copyMax=%d cancellations=%d publications=%d binds=%d communityPumps=%d leaderboardPumps=%d",
    tonumber(workStats.maxSourceRowsPerPump) or -1,
    tonumber(workStats.maxComparisonsPerPump) or -1,
    tonumber(workStats.maxSortMovesPerPump) or -1,
    tonumber(workStats.maxJoinsPerPump) or -1,
    tonumber(workStats.maxCopiesPerPump) or -1,
    tonumber(workStats.cancellations) or -1,
    tonumber(workStats.publications) or -1,
    tonumber(workStats.binds) or -1,
    tonumber(workStats.communityPumps) or -1,
    tonumber(workStats.leaderboardPumps) or -1))
local communityVirtual, leaderboardVirtual = C.VirtualStats(), L.VirtualStats()
local communityStatus = C.DiagnosticSnapshot()
assert(communityVirtual.results <= 20 and communityVirtual.active <= 7
    and leaderboardVirtual.results == 600
    and leaderboardVirtual.active <= 7,
    "bounded construction lost the public Community limit or fixed row pools")
assert(communityStatus.bundledCount == 0
    and communityStatus.overlayCount == 1000
    and communityStatus.availableCount == 1000
    and communityStatus.filterMatchedCount > 0
    and communityStatus.filterMatchedCount <= communityStatus.availableCount
    and communityStatus.resultCount == communityStatus.filterMatchedCount
    and communityStatus.displayedCount == 20
    and communityStatus.searchActive == true,
    string.format("resumable Community status lost baseline/overlay/filter/display facts: bundled=%s overlay=%s available=%s matched=%s result=%s displayed=%s search=%s",
        tostring(communityStatus.bundledCount),
        tostring(communityStatus.overlayCount),
        tostring(communityStatus.availableCount),
        tostring(communityStatus.filterMatchedCount),
        tostring(communityStatus.resultCount),
        tostring(communityStatus.displayedCount),
        tostring(communityStatus.searchActive)))
local finalLeaderboard, finalSummary, finalReason = projections.RequestLeaderboard("combined", {
    classFilter="ALL",search="",
})
local finalPumps = 0
while type(finalLeaderboard) ~= "table" and finalPumps < 600 do
    finalPumps = finalPumps + 1
    local _, pumpError = projections.PumpLeaderboard()
    assert(pumpError == nil, "final combined pump failed: " .. tostring(pumpError))
    finalLeaderboard, finalSummary, finalReason =
        projections.RequestLeaderboard("combined", {
            classFilter="ALL",search="",
        })
end
assert(type(finalLeaderboard) == "table" and type(finalSummary) == "table",
    "final combined cache unavailable: " .. tostring(finalReason))
assert(#finalLeaderboard == 600,
    "uncapped combined Leaderboard lost qualifying rows")
local repeatedLeaderboard, repeatedSummary = projections.RequestLeaderboard(
    "combined", {classFilter="ALL",search=""})
assert(repeatedLeaderboard == finalLeaderboard
    and repeatedSummary == finalSummary
    and type(finalSummary.rowByKey) == "table",
    "immutable async Leaderboard cache was copied or lost its selection index")
for index = 2, #finalLeaderboard do
    assert(finalLeaderboard[index - 1].average >= finalLeaderboard[index].average,
        "resumable Leaderboard merge lost exact descending order")
end
assert(#H.selectCalls == 0 and #H.banishCalls == 0
    and #H.freezeCalls == 0 and H.rerollCalls == 0
    and #H.activateCalls == 0 and #H.saveCalls == 0,
    "data-view navigation submitted an automation mutation")

print("live projection work budget: all callbacks and OnUpdate units bounded -- OK")
