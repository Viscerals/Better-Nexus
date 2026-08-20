-- Community-specific projection composes the established list cache and owns
-- only immutable selected-detail preparation.
Nexus = {}
dofile("core/Revisions.lua")
dofile("core/Identity.lua")
dofile("core/LoadoutEvidence.lua")
Nexus.LoadoutEvidence.Init({})
dofile("core/CandidateEvidence.lua")
dofile("core/ViewProjections.lua")
dofile("core/CommunityProjection.lua")

UnitName = function() return "ProjectionMage" end
UnitClass = function() return "Mage", "MAGE" end
GetNormalizedRealmName = function() return "Ebonhold" end

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, child in pairs(value) do out[Copy(key, seen)] = Copy(child, seen) end
    return out
end

local function Equal(left, right, leftSeen, rightSeen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    leftSeen, rightSeen = leftSeen or {}, rightSeen or {}
    if leftSeen[left] then return leftSeen[left] == right end
    if rightSeen[right] then return rightSeen[right] == left end
    leftSeen[left], rightSeen[right] = right, left
    for key, value in pairs(left) do
        if not Equal(value, right[key], leftSeen, rightSeen) then return false end
    end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

local builds, exact, score = {}, {}, {}
local boards = {dummy={},lk={}}
for index = 1, 1000 do
    local id = string.format("community-%04d", index)
    local spellId = 800000 + index
    builds[id] = {
        id=id,title=string.format("Build %04d", 1001-index),
        description=index % 7 == 0 and "needle" or "",
        author=index % 10 == 0 and "ProjectionMage" or "Peer",
        ownerKey=index % 10 == 0
            and "projectionmage@ebonhold" or "peer@ebonhold",
        ownerVerified=true,
        class=index % 2 == 0 and "MAGE" or "WARRIOR",
        postedAt=index,lastModified=index,
        importedSavedBuild=index <= 10 and true or nil,
        fingerprint=tostring(spellId).."x1,"..tostring(spellId+10000).."x1",
        fingerprintHash="hash-"..index,ordinaryComplete=true,
        echoCount=2,loadoutAvailable=true,
    }
    exact[id] = Copy(builds[id])
    exact[id].echoes = {
        {spellId=spellId,quality=3,stacks=1,locked=index==500 and true or nil},
        {spellId=spellId+10000,quality=2,stacks=1},
    }
    if index == 200 then exact[id].link = "https://discord.com/channels/1/2/3" end
    if index <= 250 then
        score[id] = {
            dummy={{player="Dummy"..index,dps=100000+index*100}},
            lk={{player="Lk"..index,dps=200000+index*100}},
        }
        for _, category in ipairs({"dummy", "lk"}) do
            boards[category][#boards[category]+1] = {
                buildId=id,player="Player"..index,
                dps=score[id][category][1].dps,
                lockedEchoes=index==200 and {{spellId=999001}} or nil,
            }
        end
    end
end

local catalogWalks, eligibilityReads = 0, 0
local failList = false
Nexus.BuildCatalog = {Summaries=function()
    catalogWalks = catalogWalks + 1
    if failList then error("forced list failure") end
    return Copy(builds)
end}
Nexus.DpsCapture = {
    GetCommunityEligibility=function()
        eligibilityReads = eligibilityReads + 1
        local out = {}
        for id, categories in pairs(score) do
            local build = builds[id]
            local dummy = categories.dummy and categories.dummy[1]
            local lk = categories.lk and categories.lk[1]
            if build and dummy and lk then
                out[build.fingerprint] = {
                    dummy=dummy.dps,lk=lk.dps,best=math.max(dummy.dps,lk.dps),
                    average=(dummy.dps+lk.dps)/2,count=2,
                }
            end
        end
        return out
    end,
}

local P, R = Nexus.ViewProjections, Nexus.Revisions
local filters = {scope="all",classFilter="MAGE",sortMode="recent"}
P.Reset()
local oldRows, oldSummary = P.Builds(filters)
assert(type(oldRows) == "table" and #oldRows == 20,
    "established large Community list fixture changed")
P.Reset(); catalogWalks, eligibilityReads = 0, 0

local loadCalls, boardReads, leaderboardReads, personalReads = 0, 0, 0, 0
local recordIds, publishedIds = {}, {}
local failLoad, failDetailDps = false, false
local factory = assert(Nexus.CommunityInternals
    and Nexus.CommunityInternals.Projection)
local projection = factory.New({
    builds=function(value) return P.Builds(value) end,
    buildsCurrent=function(value) return P.BuildsCurrent(value) end,
    loadBuild=function(id)
        loadCalls = loadCalls + 1
        if failLoad then error("forced detail failure") end
        return Copy(exact[id])
    end,
    recordBuildId=function(build)
        if not build then return nil end
        if build.importedSavedBuild then return recordIds[build.id] end
        return build.id
    end,
    publishedBuildId=function(build)
        return build and publishedIds[build.id] or nil
    end,
    savedProjection=function(build)
        if not build then return nil end
        local projected = Copy(build)
        if build.ownerVerified == true then
            projected.recordBuildId = recordIds[build.id]
            projected.publishedBuildId = publishedIds[build.id]
        else
            projected.recordBuildId, projected.publishedBuildId = nil, nil
            projected.class = "UNKNOWN"
        end
        return projected
    end,
    revisionSnapshot=function()
        return {build=R.Get(R.BUILD_LIBRARY_CHANGED),dps=R.Get(R.DPS_CHANGED)}
    end,
    dpsBoard=function(category)
        boardReads = boardReads + 1
        if failDetailDps then error("forced detail DPS failure") end
        return Copy(boards[category])
    end,
    leaderboard=function(id, category)
        leaderboardReads = leaderboardReads + 1
        return Copy(score[id] and score[id][category] or {})
    end,
    personalBest=function(id, category)
        personalReads = personalReads + 1
        local row = score[id] and score[id][category]
            and score[id][category][1] or nil
        return row and {player="ProjectionMage",dps=row.dps-1000,level=80} or nil
    end,
})

local rows, summary = projection.List(filters)
assert(Equal(rows, oldRows),
    "new Community list changed established filtered/sorted rows")
assert(Equal(summary, oldSummary),
    "new Community list changed established summary")
assert(catalogWalks == 1 and eligibilityReads == 1,
    string.format("new Community list work changed: walks=%d eligibility=%d",
        catalogWalks, eligibilityReads))
local viewAfterFirst = P.Stats().builds
local sameRows, sameSummary = projection.List(filters)
local viewAfterHit = P.Stats().builds
assert(sameRows == rows and sameSummary == summary
    and catalogWalks == 1 and eligibilityReads == 1
    and viewAfterHit.sorts == viewAfterFirst.sorts
    and viewAfterHit.defensiveCopies == viewAfterFirst.defensiveCopies,
    "unchanged Community read copied, walked, joined, or sorted again")
assert(projection.ListCurrent(filters),
    "warm Community projection did not report current")

local legacyFilter = {scope="all",sortMode="class"}
assert(type(projection.List(legacyFilter)) == "table"
    and legacyFilter.sortMode == "class",
    "pure filter normalization mutated caller/SavedVariables state")
local beforeRevision = projection.Stats().list
R.Advance(R.DPS_CHANGED, {scope="fixture"})
assert(not projection.ListCurrent(legacyFilter),
    "DPS revision left Community projection current")
assert(type(projection.List(legacyFilter)) == "table")
local afterRevision = projection.Stats().list
assert(afterRevision.rebuilds == beforeRevision.rebuilds + 1,
    "one relevant revision did not rebuild exactly once")

R.Advance(R.BUILD_LIBRARY_CHANGED, {scope="failure"})
failList = true
local failedRows, _, listErr = projection.List(legacyFilter)
assert(failedRows == nil and tostring(listErr):find("forced list failure",1,true),
    "failed list construction published partial data")
failList = false
assert(type(projection.List(legacyFilter)) == "table",
    "Community list did not recover after dependency failure")

local selected = "community-0200"
local context = {
    ownerKey="projectionmage@ebonhold",player="projectionmage",
    isAdmin=false,detailsAvailable=true,
    ownedBySpell={[800200]=1,[810200]=0},
}
local detail = assert(projection.Detail(selected, context),
    "selected complete detail was filtered")
assert(detail.build.id == selected and detail.mine and not detail.admin
    and detail.hasLink and detail.showLink and detail.canSaveLink
    and detail.showEdit and detail.showDelete
    and detail.deleteText == "Stop Sharing"
    and detail.hasLoadout and not detail.needsLoadout
    and detail.missing == 1 and detail.totalSlots == 2
    and detail.lockedEchoes[1].spellId == 999001
    and detail.loadoutLocked
    and detail.actionText == "Copy into Editor"
    and detail.dummyRecord:find("120k",1,true)
    and detail.dummyRecord:find("Your best 119k",1,true),
    "selected detail, ownership, exact-loadout, missing, or DPS labels changed")
local detailCalls = {load=loadCalls,board=boardReads,
    leaderboard=leaderboardReads,personal=personalReads}
assert(projection.Detail(selected, context) == detail
    and loadCalls == detailCalls.load and boardReads == detailCalls.board
    and leaderboardReads == detailCalls.leaderboard
    and personalReads == detailCalls.personal,
    "unchanged selected detail repeated load/DPS work")
context.ownedBySpell[810200] = 1
local ownedChanged = assert(projection.Detail(selected, context))
assert(ownedChanged ~= detail and ownedChanged.missing == 0
    and loadCalls == detailCalls.load + 1,
    "relevant captured owned state did not invalidate detail once")

R.Advance(R.DPS_CHANGED, {scope="detail"})
local revised = assert(projection.Detail(selected, context))
assert(revised ~= ownedChanged and loadCalls == detailCalls.load + 2,
    "DPS revision did not invalidate selected detail once")

R.Advance(R.BUILD_LIBRARY_CHANGED, {scope="detail-failure"})
failLoad = true
local failedDetail, detailErr = projection.Detail(selected, context)
assert(failedDetail == nil and tostring(detailErr):find("forced detail failure",1,true),
    "failed detail construction published partial state")
failLoad = false
assert(projection.Detail(selected, context),
    "selected detail did not recover after exact-reader failure")

R.Advance(R.DPS_CHANGED, {scope="detail-dps-failure"})
failDetailDps = true
local failedDpsDetail, dpsDetailErr = projection.Detail(selected, context)
assert(failedDpsDetail == nil
    and tostring(dpsDetailErr):find("forced detail DPS failure",1,true),
    "failed detail DPS dependency published partial state")
failDetailDps = false
assert(projection.Detail(selected, context),
    "selected detail did not recover after DPS dependency failure")

local incompleteId = "community-incomplete"
exact[incompleteId] = {
    id=incompleteId,title="Incomplete",author="Peer",
    ownerKey="peer@ebonhold",class="MAGE",echoes={},
}
R.Advance(R.BUILD_LIBRARY_CHANGED, {scope="incomplete"})
local incomplete = projection.Detail(incompleteId, context)
assert(incomplete == nil,
    "incomplete exact loadout remained public")

local mirrorId, publishedId = "community-mirror", "community-published"
exact[mirrorId] = {
    id=mirrorId,recordBuildId=publishedId,publishedBuildId=publishedId,
    importedSavedBuild=true,title="Mirror",author="ProjectionMage",
    ownerKey="projectionmage@ebonhold",ownerVerified=true,realm="ebonhold",
    isMine=true,
    class="MAGE",echoes={{spellId=900001,stacks=1}},
}
recordIds[mirrorId] = publishedId
publishedIds[mirrorId] = publishedId
score[publishedId] = {dummy={{player="Published",dps=250000}}}
R.Advance(R.BUILD_LIBRARY_CHANGED, {scope="mirror"})
local mirror = assert(projection.Detail(mirrorId, context))
assert(mirror.mine and mirror.showEdit and not mirror.showDelete
    and not mirror.loadoutLocked
    and mirror.actionText == "Update Upload"
    and mirror.dummyRecord:find("250k",1,true),
    "verified owner, saved-mirror actions, or distinct record identity changed")

local unverifiedMirrorId = "community-unverified-mirror"
exact[unverifiedMirrorId] = {
    id=unverifiedMirrorId,recordBuildId=publishedId,
    publishedBuildId=publishedId,importedSavedBuild=true,
    title="Unverified Mirror",author="ProjectionMage",
    ownerKey="projectionmage@ebonhold",ownerVerified=false,realm="ebonhold",
    isMine=true,class="MAGE",echoes={{spellId=900003,stacks=1}},
}
score[unverifiedMirrorId] = {
    dummy={{player="Private Mirror",dps=990000}},
}
R.Advance(R.BUILD_LIBRARY_CHANGED, {scope="unverified-mirror"})
local unverifiedMirror = assert(projection.Detail(unverifiedMirrorId, context))
assert(not unverifiedMirror.mine and not unverifiedMirror.showEdit
    and #unverifiedMirror.dummyRows == 0
    and not unverifiedMirror.dummyRecord:find("990k", 1, true),
    "projection restored authority or DPS after resolver rejected Saved relation")

local adminId = "community-admin"
exact[adminId] = {
    id=adminId,title="Peer",author="Peer",ownerKey="peer@ebonhold",
    class="MAGE",echoes={{spellId=900002,stacks=1}},
}
local adminContext = Copy(context); adminContext.isAdmin = true
R.Advance(R.BUILD_LIBRARY_CHANGED, {scope="admin"})
local admin = assert(projection.Detail(adminId, adminContext))
assert(not admin.mine and admin.admin and not admin.showEdit
    and admin.showDelete and admin.deleteText == "Remove"
    and admin.canSaveLink,
    "admin/non-owner detail actions changed")

local sourceHandle = assert(io.open("core/CommunityProjection.lua", "rb"))
local source = sourceHandle:read("*a"); sourceHandle:close()
for _, forbidden in ipairs({"CreateFrame", "NexusDB", "ProjectEbonhold",
    "GameAdapter", "Nexus.Sync", "BuildCatalog.Put", "Transport"}) do
    assert(not source:find(forbidden, 1, true),
        "Community projection acquired authority: " .. forbidden)
end
print(string.format(
    "community projection: rows=%d dps=%d listReads=%d detailLoads=%d boardReads=%d -- OK",
    #rows, 500, projection.Stats().list.readerCalls,
    loadCalls, boardReads))
