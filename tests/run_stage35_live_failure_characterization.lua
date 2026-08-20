-- Stage 35 staged characterization: each repaired category turns green while
-- the remaining test.15 failures stay source-anchored expected red until their
-- owning checkpoints.
local H = dofile("tests/harness.lua")

local checks, expectedReds = 0, {}
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end

local function ExpectedRed(value, token)
    checks = checks + 1
    assert(value, "expected red did not reproduce: " .. token)
    expectedReds[#expectedReds + 1] = token
end

local function Read(path)
    local handle = assert(io.open(path, "rb"))
    local value = assert(handle:read("*a"))
    handle:close()
    return value:gsub("\r\n", "\n")
end

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do out[Copy(key, seen)] = Copy(child, seen) end
    return out
end

local CURRENT_FINGERPRINT = "400001x1"
local RECOVERED_FINGERPRINT = "400002x1"

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

local communitySource = Read("ui/CommunityRenderer.lua")
local leaderboardSource = Read("ui/Leaderboard.lua")
local wishlistSource = Read("ui/WishlistRenderer.lua")
local wishlistControllerSource = Read("core/WishlistController.lua")
local communityControllerSource = Read("core/CommunityController.lua")
local sessionSource = Read("core/SyncSession.lua")
local diagnosticsSource = Read("core/SyncDiagnostics.lua")

------------------------------------------------------------------------
-- A. Community now keeps ordinary and locked evidence as separate immutable
-- roles through the shared candidate contract. The remaining categories stay
-- expected red until their owning checkpoints.
------------------------------------------------------------------------

local ordinary, locked = {}, {}
for index = 1, 79 do
    ordinary[index] = {
        spellId=310000 + index,quality=index % 5,stacks=1,
        future={ordinary=index},
    }
end
for index = 1, 6 do
    locked[index] = {
        spellId=320000 + index,quality=index % 5,stacks=1,
        future={locked=index},
    }
end
locked[1].spellId = ordinary[79].spellId
local evidenceBefore = Signature({ordinary=ordinary,locked=locked})

local typed = assert(Nexus.CandidateEvidence.Build({
    title="Stage 35 fixture", ordinaryEchoes=ordinary, lockedEchoes=locked,
    sourceIdentity="stage35-typed", sourceRevision="1",
}))
local validated = assert(Nexus.CandidateEvidence.Validate(typed))
Check(#ordinary == 79 and #locked == 6
        and #validated.ordinaryEchoes == 79
        and #validated.lockedEchoes == 6,
    "typed-evidence fixture boundary drifted")
Check(Signature({ordinary=ordinary,locked=locked}) == evidenceBefore,
    "typed Community assembly mutated its source fixture")
Check(validated.ordinaryEchoes[79].spellId
        == validated.lockedEchoes[1].spellId
        and not validated.ordinaryEchoes[79].locked
        and validated.lockedEchoes[1].locked == true,
    "shared spell identity lost one of its two typed roles")
Check(communitySource:find("CandidateEvidence.Build",1,true)
        and communitySource:find("ordinaryEchoes=source.ordinary",1,true)
        and communitySource:find("selectedEvidence=source.selected",1,true)
        and communitySource:find("currentEvidence=function",1,true)
        and wishlistControllerSource:find("evidence.Validate(candidate)",1,true)
        and not wishlistControllerSource:find(
            'candidate.evidenceKind == "leaderboard-typed-v1"',1,true),
    "Community/Leaderboard candidate ownership did not centralize")

------------------------------------------------------------------------
-- B. The existing catalog already resolves exact fingerprint identity in O(1)
-- revision-owned buckets, but Leaderboard Open Build still forwards raw ID.
------------------------------------------------------------------------

dofile("data/BundledBuilds.lua")
dofile("core/BuildCatalog.lua")
local collisionDb = {communityBuilds={},syncTombstones={}}
local navigationBundle = {
    schemaVersion=1,catalogVersion="stage35-navigation",sourceVersion="test",
    builds={
        ["collision-current"]={id="collision-current",title="Current collision",
            class="WARRIOR",fingerprint=CURRENT_FINGERPRINT,
            echoes={{spellId=400001,stacks=1}}},
        ["recovered-exact"]={id="recovered-exact",title="Recovered exact",
            class="PALADIN",fingerprint=RECOVERED_FINGERPRINT,
            echoes={{spellId=400002,stacks=1}}},
    },
}
Nexus.BuildCatalog.Init(collisionDb, navigationBundle)
local resolvedId, resolvedBuild =
    Nexus.BuildCatalog.FindExactFingerprint(RECOVERED_FINGERPRINT)
local fingerprintEpoch, fingerprintRevision =
    Nexus.BuildCatalog.ExactFingerprintRevision(RECOVERED_FINGERPRINT)
local recoveredRow = {
    protocolVersion=6,buildId="collision-current",
    fingerprint=RECOVERED_FINGERPRINT,build=resolvedBuild,
    resolvedBuildId=resolvedId,
}
Check(resolvedId == "recovered-exact"
        and resolvedBuild and resolvedBuild.fingerprint == recoveredRow.fingerprint
        and type(fingerprintEpoch) == "number"
        and type(fingerprintRevision) == "number",
    "exact-fingerprint catalog lookup did not identify recovered build")
local publishedId = Nexus.BuildCatalog.ResolveFingerprintIdentity(
    recoveredRow.buildId, recoveredRow.fingerprint)
Check(publishedId == resolvedId and recoveredRow.buildId == "collision-current"
        and leaderboardSource:find(
            "local id,reason=ResolveOpenBuildId(detail.row)",1,true)
        and leaderboardSource:find(
            "Nexus.CommunityBuilds.ShowBuild(id)",1,true),
    "Leaderboard did not preserve raw identity while opening the resolved ID")

------------------------------------------------------------------------
-- C. The live screenshot concerns Leaderboard class icons, not Echo spell
-- icons. Bind real rows through the current projection/UI path and distinguish
-- provable class metadata from genuinely unavailable or mismatched evidence.
------------------------------------------------------------------------

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local NEUTRAL = "Interface\\Icons\\INV_Misc_Note_01"
local classRows = {
    {player="Protocolmage",class="MAGE",dps=900,ts=1,duration=60,
        fingerprint="410001x1",echoes={{spellId=410001,stacks=1}},
        buildId="protocol-class"},
    {player="Exactwarrior",dps=800,ts=2,duration=60,ordinaryComplete=true,
        fingerprint=CURRENT_FINGERPRINT,buildId="collision-current",
        build=Copy(navigationBundle.builds["collision-current"])},
    {player="Currentplayer",class="DRUID",dps=700,ts=3,duration=60,
        fingerprint="410003x1",echoes={{spellId=410003,stacks=1}},
        buildId="current-player-repair"},
    {player="Recoveredpaladin",dps=600,ts=4,duration=60,ordinaryComplete=true,
        fingerprint=RECOVERED_FINGERPRINT,buildId="missing-legacy-id"},
    {player="Unknownlegacy",dps=500,ts=5,duration=60,
        fingerprint="410005x1",echoes={{spellId=410005,stacks=1}},
        buildId="unknown-class"},
    {player="Invalidlegacy",class="NOT_A_CLASS",dps=400,ts=6,duration=60,
        fingerprint="410006x1",echoes={{spellId=410006,stacks=1}},
        buildId="invalid-class"},
    {player="Mismatchedrow",dps=300,ts=7,duration=60,
        fingerprint="mismatch-fingerprint",buildId="mismatch-id",
        buildIdentityMismatch=true,
        build={id="other",fingerprint="other",class="WARLOCK"}},
    {player="Laterrogue",dps=200,ts=8,duration=60,
        fingerprint="410008x1",echoes={{spellId=410008,stacks=1}},
        buildId="later-class"},
}
Nexus.DpsCapture={GetDpsBoard=function(category)
    return category=="dummy" and classRows or {}
end}
Nexus.Sync={GetLeaderboardSyncStatus=function() return "idle",0,0,{} end}
Nexus.ViewProjections.Reset()
local madeFrames={}
local realCreateFrame=CreateFrame
CreateFrame=function(...)
    local made=realCreateFrame(...)
    madeFrames[#madeFrames+1]=made
    return made
end
dofile("ui/Theme.lua")
dofile("ui/Leaderboard.lua")
Nexus.Leaderboard.Init(nil)
Nexus.Leaderboard.Show("dummy")

local function BoundRows()
    local out={}
    for _, made in ipairs(madeFrames) do
        if type(made.data)=="table" and made.icon then
            out[tostring(made.data.player)]=made
        end
    end
    return out
end
local firstBound=BoundRows()
Check(firstBound.Protocolmage.icon:GetTexture()
        == "Interface\\Icons\\Spell_Frost_Frostbolt02",
    "current-protocol class did not bind its exact class icon")
Check(firstBound.Exactwarrior.icon:GetTexture()
        == "Interface\\Icons\\Ability_Warrior_Charge",
    "exact row.build class did not bind its exact class icon")
Check(firstBound.Currentplayer.icon:GetTexture()
        == "Interface\\Icons\\Spell_Nature_NaturesBlessing",
    "safe current-player class repair was not honored by row binding")
Check(firstBound.Recoveredpaladin.icon:GetTexture()
        == "Interface\\Icons\\Spell_Holy_HolyBolt",
    "exact-fingerprint class did not resolve before binding")
Check(firstBound.Unknownlegacy.icon:GetTexture()==NEUTRAL
        and firstBound.Unknownlegacy.classLabel=="Class unavailable",
    "unknown class did not use the neutral unavailable presentation")
Nexus.Leaderboard.ScrollTo(math.huge)
local lastBound=BoundRows()
Check(lastBound.Invalidlegacy.icon:GetTexture()==NEUTRAL
        and lastBound.Invalidlegacy.classLabel=="Class unavailable",
    "invalid class did not use the neutral unavailable presentation")
Check(lastBound.Mismatchedrow==nil,
    "mismatched build metadata remained public")
Check(QUESTION~=NEUTRAL,
    "neutral class-unavailable fixture aliases the broken question mark")

Nexus.Leaderboard.SetClassFilter("PALADIN")
Check(Nexus.Leaderboard.VirtualStats().results==1,
    "exact recovered class did not pass its specific filter")
Nexus.Leaderboard.SetClassFilter("ALL")
classRows[8].class="ROGUE"
Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{source="class enrichment"})
Nexus.Leaderboard.RefreshData()
Nexus.Leaderboard.ScrollTo(math.huge)
lastBound=BoundRows()
Check(lastBound.Laterrogue.icon:GetTexture()
        == "Interface\\Icons\\Ability_BackStab",
    "same-record current-protocol class enrichment did not refresh once")
Check(leaderboardSource:find("CLASS_ICON[class] or NEUTRAL_CLASS_ICON",1,true)
        and leaderboardSource:find("Class unavailable",1,true),
    "class-icon fallback characterization is no longer source-anchored")

------------------------------------------------------------------------
-- D. The bundled baseline is present before Sync. Existing projection/filter
-- behavior can narrow it honestly, but public status exposes only one catalog
-- count and cannot name bundled/overlay/filter/qualification states separately.
------------------------------------------------------------------------

local bundled = assert(Nexus.BundledBuilds)
local buildCount, echoRows = 0, 0
for _, build in pairs(bundled.builds or {}) do
    buildCount = buildCount + 1
    echoRows = echoRows + #(build.echoes or {})
end
Check(buildCount == 504 and echoRows == 36187
        and bundled.generation.included == 504
        and bundled.generation.echoRows == 36187
        and bundled.catalogVersion == "1.19.4-05efb360ae5b"
        and bundled.sourceVersion == "1.19.4",
    "immutable bundled catalog receipt drifted")

local baselineDb = {communityBuilds={},syncTombstones={}}
local baselineSummary = Nexus.BuildCatalog.Init(baselineDb, bundled)
Check(baselineSummary.bundled == 504 and baselineSummary.overlay == 0
        and baselineSummary.merged == 504 and Nexus.BuildCatalog.Count() == 504,
    "bundled baseline was not available before Sync")

dofile("core/CommunityProjection.lua")
local rows = Nexus.BuildCatalog.Summaries()
local revisions = {build=1,dps=1}
local function Project(filters)
    local search = tostring(filters.search or ""):lower()
    local qualified = filters.qualifiedOnly ~= false
    local out, total = {}, 0
    for _, row in pairs(rows) do
        total = total + 1
        local haystack = table.concat({tostring(row.title or ""),
            tostring(row.author or ""),tostring(row.description or "")}, " "):lower()
        local searchMatch = search == "" or haystack:find(search, 1, true) ~= nil
        local qualifiedMatch = not qualified
        if searchMatch and qualifiedMatch then out[#out + 1] = Copy(row) end
    end
    table.sort(out, function(left, right) return tostring(left.id) < tostring(right.id) end)
    return out, {total=total,filteredTotal=#out,page=1,pages=math.max(1,
        math.ceil(#out / 20))}
end
local projection = Nexus.CommunityInternals.Projection.New({
    builds=Project,buildsCurrent=function() return false end,
    loadBuild=function(id) return Nexus.BuildCatalog.Get(id) end,
    revisionSnapshot=function() return revisions end,
})
local blankFilters = {scope="all",classFilter="ALL",currentClassOnly=false,
    qualifiedOnly=false,search="",sortMode="title",page=1}
local blankBefore = Signature(blankFilters)
local allRows, allStatus = projection.List(blankFilters)
Check(#allRows == 504 and allStatus.total == 504
        and Signature(blankFilters) == blankBefore,
    "blank Community filters did not expose the immutable baseline")
local searchTerm = tostring(allRows[1].title or allRows[1].author or ""):lower()
local searchFilters = Copy(blankFilters); searchFilters.search = searchTerm
local narrowed = projection.List(searchFilters)
Check(#narrowed > 0 and #narrowed <= 504
        and Signature(blankFilters) == blankBefore,
    "search did not narrow honestly or changed caller filters")
local qualifiedFilters = Copy(blankFilters); qualifiedFilters.qualifiedOnly = true
local qualifiedRows = projection.List(qualifiedFilters)
Check(#qualifiedRows == 0 and Signature(blankFilters) == blankBefore,
    "qualification exclusion did not remain distinct from baseline availability")
Check(communityControllerSource:find("bundledCount=bundledCount", 1, true)
        and communityControllerSource:find("overlayCount=overlayCount", 1, true)
        and communityControllerSource:find("availableCount=availableCount", 1, true)
        and communityControllerSource:find("catalogVersion=tostring", 1, true),
    "Community status did not expose fixed catalog provenance")
Check(communitySource:find("Clear Search", 1, true)
        and communitySource:find('SetFilter("search", "")', 1, true),
    "Community search did not expose an explicit owner-routed clear action")

------------------------------------------------------------------------
-- E. Two real SyncSession instances accept protocol-7 fixture traffic. The
-- current request surface records any inbound as peer progress and only counts
-- new rows; updated/useful/duplicate/rejected/terminal reason are not request-
-- scoped, so very different outcomes collapse to the same status snapshot.
------------------------------------------------------------------------

dofile("core/DiagnosticHistory.lua")
dofile("core/SyncDiagnostics.lua")
dofile("core/SyncSession.lua")
local SessionFactory = assert(Nexus.SyncInternals.Session)
local DiagnosticsFactory = assert(Nexus.SyncInternals.Diagnostics)
local clock = 100
local function NewPeer(name)
    local state = {queued={},name=name}
    state.session = SessionFactory.New({
        receiveWindow=30,inflightGrace=10,requestCooldown=0,
        autoSyncDelay=0,autoSyncMinPass=1,autoSyncQuiet=1,
        maxConvergenceAge=60,maxReceiveAge=45,maxPasses=2,
        joinRetryInterval=10,joinMaxAttempts=2,maxRecoveryQueue=8,
        maxKnownPeers=8,chatLimit=255,requestCode="WLRQ",
        loadoutRequestCode="WLLQ",now=function() return clock end,
        myName=function() return name end,
        normalizePeerName=function(value) return tostring(value):lower() end,
        log=function() end,validIdentifier=function() return true end,
        catalogGet=function() return nil end,getCatalog=function() return nil end,
        getDpsCapture=function() return nil end,getAdapter=function() return nil end,
        getCodec=function() return nil end,playerLevel=function() return 80 end,
        requestVersion=function() return "1.20.0-beta.1" end,
        statusVersion=function() return "test.15" end,
        currentBuildHash=function() return "0,0,0,0,0,0,0,0,catalog" end,
        currentClaimBuildHash=function() return "0,0,0,0,0,0,0,0,catalog" end,
        currentDpsHash=function() return "0,0,0,0,0,0,0,0" end,
        enqueue=function(message, metadata)
            state.queued[#state.queued + 1] = {message=message,metadata=Copy(metadata)}
            return true
        end,
        enqueueControl=function(message, metadata)
            state.queued[#state.queued + 1] = {message=message,metadata=Copy(metadata)}
            return true
        end,
        transportSnapshot=function() return {bulk=0,control=0} end,
        transportHasPending=function() return false end,
        inboundHasPending=function() return false end,
        reconcilerHasPending=function() return false end,
        pendingDeleteCount=function() return 0 end,
        isConnected=function() return true end,ensureChannel=function() return true end,
        sendWhisper=function() end,
    })
    assert(state.session.RequestSync())
    local request = assert(state.queued[1])
    assert(state.session.HandleTransportEvent("send_attempted", {}, request.metadata))
    state.requestId = request.metadata.requestId
    return state
end

local peerA, peerB = NewPeer("Alice"), NewPeer("Bob")
Check(peerA.requestId ~= peerB.requestId
        and peerA.session.AcceptsResponse(peerA.requestId)
        and peerB.session.AcceptsResponse(peerB.requestId),
    "two-peer request identity fixture did not start")

local outcomes = {
    {kind="baseline",protocolVersion=7,useful=false},
    {kind="overlay_new",protocolVersion=7,useful=true,new=1},
    {kind="overlay_updated",protocolVersion=7,useful=true,updated=1},
    {kind="share",protocolVersion=7,useful=true,share=1},
    {kind="duplicate",protocolVersion=7,useful=false,duplicate=1},
    {kind="malformed",protocolVersion=7,useful=false,rejected=1},
    {kind="mixed",protocolVersion=7,useful=true,new=1,duplicate=1,rejected=1},
    {kind="unrelated",protocolVersion=7,useful=false,unrelated=1},
    {kind="queue_full",protocolVersion=7,useful=false,queue="full"},
    {kind="terminal_no_progress",protocolVersion=7,useful=false,
        terminal="no peer progress"},
}
local useful, nonUseful = 0, 0
for _, outcome in ipairs(outcomes) do
    Check(outcome.protocolVersion == 7,
        "two-peer fixture left the current protocol")
    if outcome.useful then useful = useful + 1 else nonUseful = nonUseful + 1 end
    peerA.session.NoteInbound(peerA.requestId)
    if outcome.kind == "baseline" then
        peerA.session.NoteOutcome(peerA.requestId, "baseline", "bundled")
    elseif outcome.kind == "overlay_new" or outcome.kind == "mixed" then
        peerA.session.NoteOutcome(peerA.requestId, "new", "accepted")
    elseif outcome.kind == "overlay_updated" then
        peerA.session.NoteOutcome(peerA.requestId, "updated", "accepted")
    elseif outcome.kind == "share" then
        peerA.session.NoteOutcome(peerA.requestId, "share", "accepted")
    elseif outcome.kind == "duplicate" then
        peerA.session.NoteOutcome(peerA.requestId, "duplicate", "duplicate")
    elseif outcome.kind == "malformed" then
        peerA.session.NoteOutcome(peerA.requestId, "rejected", "malformed")
    elseif outcome.kind == "unrelated" then
        peerA.session.NoteOutcome(peerB.requestId, "new", "accepted")
    end
    if outcome.kind == "mixed" then
        peerA.session.NoteOutcome(peerA.requestId, "duplicate", "duplicate")
        peerA.session.NoteOutcome(peerA.requestId, "rejected", "schema")
    end
end
Check(useful == 4 and nonUseful == 6,
    "useful-progress fixture classification drifted")
local sessionStatus = peerA.session.StatusSnapshot()
Check(sessionStatus.peerProgress == true and sessionStatus.useful == true
        and peerA.session.LastSyncNewCount() == 3,
    "request-scoped useful outcome did not retain accepted overlay totals")

local diagnostics = DiagnosticsFactory.New({
    history=Nexus.DiagnosticHistory,now=function() return clock end,
    logCap=16,logTrimAt=24,logTextBytes=256,
})
local aggregate = diagnostics.Stats()
aggregate.updated = 1
aggregate.duplicatesSkipped = 2
aggregate.malformedRejected = 3
diagnostics.UpdateRequestOutcome(sessionStatus)
Check(aggregate.updated == 1 and aggregate.duplicatesSkipped == 2
        and aggregate.malformedRejected == 3,
    "existing strict aggregate counters disappeared")
Check(sessionStatus.requestId == peerA.requestId
        and sessionStatus.new == 2 and sessionStatus.updated == 1
        and sessionStatus.shares == 1 and sessionStatus.duplicates == 2
        and sessionStatus.rejected == 2 and sessionStatus.unrelated == 1,
    "sync request useful/non-useful outcome matrix is not request-scoped")
Check(aggregate.requestId == peerA.requestId and aggregate.useful == true
        and aggregate.requestNew == 2 and aggregate.requestUpdated == 1
        and aggregate.requestDuplicates == 2
        and aggregate.requestRejected == 2
        and aggregate.terminalReason == "none"
        and aggregate.queueOutcome == "sent",
    "sync diagnostics did not retain the request-scoped scalar outcome")
local noteInboundBody = sessionSource:match(
    "function M%.NoteInbound%b()%s*(.-)\n    end") or ""
Check(not noteInboundBody:find("peerProgress", 1, true)
        and sessionSource:find("function M.NoteOutcome", 1, true)
        and diagnosticsSource:find("duplicatesSkipped=0", 1, true)
        and diagnosticsSource:find("requestRejected=0", 1, true),
    "non-useful inbound traffic still counts as useful peer progress")

------------------------------------------------------------------------

Check(#expectedReds == 0,
    "Stage 35 expected-red inventory changed without an explicit update")
print(string.format(
    "Stage 35 live-failure characterization: checks=%d expected_red=%d typed=green navigation=green class=green catalog=green sync=green baseline=504 echoes=36187 protocol=7 peers=2 -- OK",
    checks, #expectedReds))
