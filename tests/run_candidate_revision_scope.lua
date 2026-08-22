-- Stage 36.5 expected red: an open Community candidate must follow only its
-- selected ordinary record and exact locked authority. Unrelated represented
-- build/DPS churn must not invalidate the draft, while a relevant identity,
-- locked fingerprint, owner, or build association change must fail before the
-- Wishlist write boundary.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")
dofile("core/WishlistModel.lua")
dofile("core/WishlistController.lua")

local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[Copy(key, seen)] = Copy(child, seen)
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
        local count = tonumber(row.stacks or row.count) or 1
        if id and count > 0 then counts[id] = (counts[id] or 0) + count end
    end
    for id in pairs(counts) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        parts[#parts + 1] = tostring(id) .. "x" .. tostring(counts[id])
    end
    return table.concat(parts, ",")
end

local ordinary = {
    {spellId=710001,quality=1,stacks=20},
    {spellId=710002,quality=2,stacks=30},
    {spellId=710003,quality=3,stacks=29},
}
local locked = {
    {spellId=720001,quality=3,stacks=1},
    {spellId=720002,quality=4,stacks=1},
}
local editorCatalog = {rows={}}
for _, row in ipairs(ordinary) do
    editorCatalog.rows[row.spellId] = {
        id=row.spellId,name="Ordinary " .. tostring(row.spellId),
        quality=row.quality,maxStack=row.stacks,
    }
end
for _, row in ipairs(locked) do
    editorCatalog.rows[row.spellId] = {
        id=row.spellId,name="Locked " .. tostring(row.spellId),
        quality=row.quality,maxStack=1,
    }
end
local build = {
    id="stage36-candidate",title="Scoped Candidate",author="Fixture",
    ownerKey="fixture@ebonhold",ownerVerified=true,class="MAGE",
    fingerprint=EchoKey(ordinary),echoes=ordinary,
    lockedEchoes=Copy(locked),
    postedAt=1,lastModified=1,loadoutAvailable=true,
}

local function NewDpsRow(category)
    return {
        player="Fixture",ownerKey="fixture@ebonhold",ownerVerified=true,
        category=category,buildId=build.id,fingerprint=build.fingerprint,
        dps=category == "dummy" and 1000 or 900,duration=60,ts=1,
        echoes=Copy(ordinary),lockedEchoes=Copy(locked),protocolVersion=7,
    }
end

local dpsRows = {
    dummy={NewDpsRow("dummy")},
    lk={NewDpsRow("lk")},
}

local function FindDpsRow(category, player, buildId, fingerprint)
    for _, row in ipairs(dpsRows[category] or {}) do
        local playerOk = player == nil
            or tostring(row.player):lower() == tostring(player):lower()
        local buildOk = buildId == nil
            or (type(row.buildId) == type(buildId)
                and tostring(row.buildId) == tostring(buildId))
        local fingerprintOk = fingerprint == nil
            or tostring(row.fingerprint or "") == tostring(fingerprint)
        if playerOk and buildOk and fingerprintOk then return Copy(row) end
    end
    return nil
end

NexusDB = {
    settingsVersion=2,settings={},chars={},buildFilters={},dpsCapture={},
    communityBuilds={[build.id]=Copy(build)},futureRoot={keep=true},
}
Nexus.Store.Init()

-- Supply every existing exact/public lookup shape so the regression remains
-- attached to the real Community producer while its locked resolver is
-- centralized during this checkpoint.
Nexus.DpsCapture = {
    GetCommunityEligibility=function() return {} end,
    GetLeaderboard=function() return {} end,
    GetLeaderboardForEchoes=function() return {} end,
    GetLeaderboardForIdentity=function() return {} end,
    GetPersonalBest=function() return nil end,
    GetDpsBoard=function(category) return Copy(dpsRows[category] or {}) end,
    GetRecordForIdentity=function(buildId, fingerprint, _, category)
        return FindDpsRow(category, nil, buildId, fingerprint)
    end,
    GetCharacterBest=function(category, player)
        return FindDpsRow(category, player)
    end,
    IsDetailsAvailable=function() return false end,
}
Nexus.Sync = {
    IsReceiving=function() return false end,
    ReceiveTimeLeft=function() return 0 end,
    LastSyncNewCount=function() return 0 end,
    Stats=function() return {received=0} end,
    RequestSync=function() return true end,
}

dofile("ui/Theme.lua")
dofile("ui/CommunityBuilds.lua")

local captured
Nexus.WishlistEditor = {
    OpenForCandidate=function(candidate)
        captured = candidate
        return false
    end,
}
Nexus.CommunityBuilds.Init(nil, nil)
Nexus.CommunityBuilds.Show()
Nexus.CommunityBuilds.Select(build.id)
local detail = assert(NexusCommunityBuildsFrame._detailPanel,
    "real Community detail panel was not assembled")

local function OpenCandidate()
    captured = nil
    Nexus.CommunityBuilds.Select(build.id)
    detail.lockBtn:GetScript("OnClick")()
    Check(type(captured) == "table"
            and captured.evidenceKind == "candidate-typed-v1",
        "real Community Copy did not produce typed candidate evidence")
    return captured
end

local function NewSession(candidate)
    local writes = {upload=0,association=0,payload=nil}
    local adapter = {
        Catalog=function() return editorCatalog end,
        LockedOwned=function() return {bySpell={}} end,
        WishlistKey=function() return 0 end,
        PresentationRevisions=function() return 0,0,0,0,0,0 end,
        UploadWishlist=function(slot, name, echoes)
            writes.upload = writes.upload + 1
            writes.payload = {slot=slot,name=name,echoes=Copy(echoes)}
            return true
        end,
        SetFirstLoadoutWishlistIdentity=function()
            writes.association = writes.association + 1
            return true
        end,
    }
    local controller = Nexus.WishlistInternals.Controller.New({
        model=Nexus.WishlistModel.New(),store=Nexus.Store,
        accountRoot=function() return NexusDB end,
        notify=function() end,
    })
    controller.Initialize(adapter)
    local name = controller.BeginCandidate(candidate)
    Check(name == build.title,
        "typed Community candidate did not open in the real Wishlist owner: name="
            .. tostring(name))
    return controller, writes
end

local Catalog = assert(Nexus.BuildCatalog, "BuildCatalog unavailable")
local Revisions = assert(Nexus.Revisions, "Revisions unavailable")

local function RestoreBuild()
    local ok = Catalog.Put(Copy(build))
    Check(ok == true, "selected build fixture could not be restored")
end

local function RestoreDps()
    dpsRows.dummy = {NewDpsRow("dummy")}
    dpsRows.lk = {NewDpsRow("lk")}
    Revisions.Advance(Revisions.DPS_CHANGED, {
        scope="record",reason="restore selected DPS fixture",
    })
end

-- Copy/validation/draft preparation must never alias or mutate the represented
-- catalog/DPS/SavedVariables sources.
local before = Signature({
    build=Catalog.Get(build.id),dps=dpsRows,
    stored=NexusDB.communityBuilds[build.id],future=NexusDB.futureRoot,
})
local defensive = OpenCandidate()
local represented = assert(Catalog.Get(build.id),
    "represented candidate build unavailable")
Check(defensive.ordinaryEchoes ~= represented.echoes
        and defensive.ordinaryEchoes[1]
            ~= represented.echoes[1]
        and defensive.lockedEchoes ~= dpsRows.dummy[1].lockedEchoes
        and defensive.lockedEchoes[1] ~= dpsRows.dummy[1].lockedEchoes[1],
    "Community candidate retained mutable source aliases")
local defensiveController = NewSession(defensive)
Check(Signature({
        build=Catalog.Get(build.id),dps=dpsRows,
        stored=NexusDB.communityBuilds[build.id],future=NexusDB.futureRoot,
    }) == before,
    "Community-to-Copy draft preparation mutated represented source data")
defensive.ordinaryEchoes[1].spellId = 799991
defensive.lockedEchoes[1].spellId = 799992
represented = assert(Catalog.Get(build.id))
Check(represented.echoes[1].spellId == ordinary[1].spellId
        and dpsRows.dummy[1].lockedEchoes[1].spellId == locked[1].spellId,
    "candidate mutation escaped its defensive copy")

-- The pre-Stage-36 `leaderboard-typed-v1` contract remains readable.
local legacy = OpenCandidate()
legacy.evidenceKind = "leaderboard-typed-v1"
local legacyValid, legacyReason = Nexus.CandidateEvidence.Validate(legacy)
Check(legacyValid ~= nil and legacyReason == nil,
    "legacy typed candidate compatibility was lost")

-- Relevant selected ordinary evidence change: current source must reject the
-- still-open draft before UploadWishlist.
local selectedCandidate = OpenCandidate()
local selectedController, selectedWrites = NewSession(selectedCandidate)
local changedBuild = Copy(build)
changedBuild.echoes[1].spellId = 710099
changedBuild.fingerprint = EchoKey(changedBuild.echoes)
changedBuild.lastModified = 2
Check(Catalog.Put(changedBuild) == true,
    "selected-record change did not enter the catalog fixture")
local selectedData, selectedReason = selectedController.PrepareApply("Selected")
Check(selectedData == nil and selectedReason == "stale_candidate"
        and selectedWrites.upload == 0 and selectedWrites.association == 0,
    "selected ordinary identity change reached the Wishlist write boundary")
RestoreBuild()

-- Relevant exact locked fingerprint change.
local lockedCandidate = OpenCandidate()
local lockedController, lockedWrites = NewSession(lockedCandidate)
dpsRows.dummy[1].lockedEchoes[1].spellId = 720099
dpsRows.lk[1].lockedEchoes[1].spellId = 720099
Revisions.Advance(Revisions.DPS_CHANGED, {
    scope="record",reason="selected locked fingerprint changed",
})
local lockedData, lockedReason = lockedController.PrepareApply("Locked")
Check(lockedData ~= nil and lockedReason == "create"
        and lockedWrites.upload == 0 and lockedWrites.association == 0,
    "historical DPS mutation invalidated exact current build authority: "
        .. tostring(lockedReason))
RestoreDps()

-- Relevant owner authority change after preview preparation must be refused at
-- the immediate AcceptApply boundary.
local ownerCandidate = OpenCandidate()
local ownerController, ownerWrites = NewSession(ownerCandidate)
local ownerData = assert(ownerController.PrepareApply("Owner"))
local changedOwner = Copy(build)
changedOwner.ownerKey = "other@ebonhold"
changedOwner.ownerVerified = false
changedOwner.lastModified = 3
Check(Catalog.Put(changedOwner) == true,
    "selected owner change did not enter the catalog fixture")
local ownerOk, ownerReason = ownerController.AcceptApply(ownerData)
Check(ownerOk == false and ownerReason == "stale_candidate"
        and ownerWrites.upload == 0 and ownerWrites.association == 0,
    "selected ownership change crossed immediate pre-write authorization")
RestoreBuild()

-- Historical DPS-to-build association churn cannot replace or invalidate the
-- exact current build authority captured by the candidate.
local associationCandidate = OpenCandidate()
local associationController, associationWrites = NewSession(associationCandidate)
local associationData = assert(associationController.PrepareApply("Association"))
dpsRows.dummy[1].buildId = "different-build"
dpsRows.lk[1].buildId = "different-build"
Revisions.Advance(Revisions.DPS_CHANGED, {
    scope="record",reason="selected association changed",
})
local associationOk, associationReason =
    associationController.AcceptApply(associationData)
Check(associationOk == true and associationReason == nil
        and associationWrites.upload == 1
        and associationWrites.association == 1,
    "historical association churn invalidated exact current build authority")
RestoreDps()

local expectedRed = {}
local function RecordUnrelatedResult(label, controller, writes)
    local data, reason = controller.PrepareApply(label)
    if not data then
        expectedRed[#expectedRed + 1] = label .. "=" .. tostring(reason)
        return
    end
    local ok, applyReason = controller.AcceptApply(data)
    Check(ok == true and applyReason == nil and writes.upload == 1
            and writes.association == 1 and writes.payload
            and EchoKey(writes.payload.echoes) == build.fingerprint,
        label .. " did not preserve the exact authorized Wishlist save")
end

-- Expected red #1: a different catalog ID advances the broad build revision
-- but cannot change this selected candidate's evidence or authority.
local unrelatedBuildCandidate = OpenCandidate()
local unrelatedBuildController, unrelatedBuildWrites =
    NewSession(unrelatedBuildCandidate)
Check(Catalog.Put({
    id="stage36-unrelated",title="Unrelated",author="Other",
    ownerKey="other@ebonhold",ownerVerified=true,class="WARRIOR",
    echoes={{spellId=730001,quality=1,stacks=1}},
    fingerprint="730001x1",postedAt=1,lastModified=1,
}) == true, "unrelated build churn did not enter the catalog fixture")
RecordUnrelatedResult("unrelated_build", unrelatedBuildController,
    unrelatedBuildWrites)

-- Expected red #2: an unrelated player's different exact DPS record advances
-- the broad DPS revision but leaves the selected locked fingerprint, owner,
-- and build association unchanged.
local unrelatedDpsCandidate = OpenCandidate()
local unrelatedDpsController, unrelatedDpsWrites = NewSession(unrelatedDpsCandidate)
dpsRows.dummy[#dpsRows.dummy + 1] = {
    player="Other",ownerKey="other@ebonhold",ownerVerified=true,
    category="dummy",buildId="other-build",fingerprint="730001x1",
    dps=500,duration=60,ts=2,
    echoes={{spellId=730001,quality=1,stacks=1}},
    lockedEchoes={{spellId=730099,quality=1,stacks=1}},protocolVersion=7,
}
Revisions.Advance(Revisions.DPS_CHANGED, {
    scope="record",reason="unrelated DPS record changed",
})
RecordUnrelatedResult("unrelated_dps", unrelatedDpsController,
    unrelatedDpsWrites)

print(string.format(
    "candidate revision scope: current=record/owner guarded historical=locked/association isolated defensive=yes legacy=yes expected_red=%d checks=%d",
    #expectedRed, checks))
Check(#expectedRed == 0,
    "EXPECTED RED: unrelated represented revisions invalidated the selected candidate: "
        .. table.concat(expectedRed, ","))

print("candidate revision scope and immediate Wishlist save guard -- OK")
