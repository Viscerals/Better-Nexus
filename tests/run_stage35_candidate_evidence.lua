-- Stage 35.2: Community and Leaderboard share one immutable typed candidate
-- evidence contract while the Wishlist controller remains the sole draft and
-- action-lifecycle owner.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

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

local ordinary, locked = {}, {}
for index = 1, 79 do
    ordinary[index] = {
        spellId=610000 + index, quality=index % 5, stacks=1,
        future={ordinary=index},
    }
end
for index = 1, 6 do
    locked[index] = {
        spellId=620000 + index, quality=index % 5, stacks=1,
        future={locked=index},
    }
end
locked[1].spellId = ordinary[79].spellId

local function EchoKey(rows)
    local counts, ids = {}, {}
    for _, row in ipairs(rows) do
        counts[row.spellId] = (counts[row.spellId] or 0) + row.stacks
    end
    for id in pairs(counts) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        parts[#parts + 1] = tostring(id) .. "x" .. tostring(counts[id])
    end
    return table.concat(parts, ",")
end

local build = {
    id="stage35-community", title="Stage 35 Community Candidate",
    author="Fixture", ownerKey="fixture@ebonhold", class="MAGE",
    fingerprint=EchoKey(ordinary),
    echoes=ordinary, postedAt=1, lastModified=1,
}
NexusDB = {
    settingsVersion=2, settings={}, chars={}, buildFilters={}, dpsCapture={},
    communityBuilds={[build.id]=build}, futureRoot={keep=true},
}
Nexus.Store.Init()

local validDpsRecord = {
    buildId=build.id,resolvedBuildId=build.id,
    fingerprint=build.fingerprint,player="Fixture",category="dummy",dps=1,
    echoes=Copy(ordinary),lockedEchoes=Copy(locked),
}
Nexus.DpsCapture = {
    GetCommunityEligibility=function() return {} end,
    GetLeaderboard=function() return {} end,
    GetLeaderboardForEchoes=function() return {} end,
    GetPersonalBest=function() return nil end,
    GetRecordForIdentity=function(id, fingerprint, _, category)
        if id == build.id and fingerprint == build.fingerprint
            and category == "dummy" then return Copy(validDpsRecord) end
        return nil
    end,
    GetDpsBoard=function(category)
        return category == "dummy" and {
            {
                buildId=build.id, fingerprint="colliding-fingerprint",
                player="Collision", category="dummy", dps=2,
                lockedEchoes={{spellId=699998,stacks=1}},
            },
            Copy(validDpsRecord),
        } or {}
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
local opened
Nexus.WishlistEditor = {
    OpenForCandidate=function(candidate)
        opened = candidate
        return true
    end,
}
Nexus.CommunityBuilds.Init(nil, nil)
Nexus.CommunityBuilds.Show()
Nexus.CommunityBuilds.Select(build.id)
local detail = assert(NexusCommunityBuildsFrame._detailPanel,
    "real Community detail panel was not assembled")
local before = Signature({build=build,ordinary=ordinary,locked=locked,db=NexusDB})
detail.lockBtn:GetScript("OnClick")()

Check(type(opened) == "table" and opened.evidenceKind == "candidate-typed-v1",
    "Community Copy did not delegate to the shared typed candidate contract")
Check(#opened.ordinaryEchoes == 79 and #opened.lockedEchoes == 6,
    "Community Copy changed the exact 79+6 role boundary")
Check(opened.ordinaryEchoes[79].spellId == opened.lockedEchoes[1].spellId,
    "Community Copy deduplicated a spell shared by ordinary and locked roles")
Check(Signature({build=build,ordinary=ordinary,locked=locked,db=NexusDB}) == before,
    "Community Copy mutated source/catalog/SavedVariables evidence")

local Evidence = assert(Nexus.CandidateEvidence,
    "shared CandidateEvidence module did not load")
local valid, reason = Evidence.Validate(opened)
Check(valid and reason == nil and #valid.ordinaryEchoes == 79
        and #valid.lockedEchoes == 6,
    "shared validator rejected the exact Community candidate")

local eighty = Copy(ordinary)
eighty[80] = {spellId=630080,quality=0,stacks=1}
local rejected80, reason80 = Evidence.Build({
    title="80 ordinary", sourceIdentity="80", sourceRevision="1",
    ordinaryEchoes=eighty, lockedEchoes={},
})
Check(rejected80 == nil and tostring(reason80):find("79",1,true),
    "ambiguous 80-plus ordinary evidence did not fail closed")

local seven = Copy(locked)
seven[7] = {spellId=630007,quality=0,stacks=1}
local rejected7, reason7 = Evidence.Build({
    title="seven locked", sourceIdentity="seven", sourceRevision="1",
    ordinaryEchoes=ordinary, lockedEchoes=seven,
})
Check(rejected7 == nil and tostring(reason7):find("six",1,true),
    "seven explicit locked identities did not fail closed")

local sparse = Copy(ordinary)
sparse[40] = nil
local rejectedSparse, sparseReason = Evidence.Build({
    title="sparse", sourceIdentity="sparse", sourceRevision="1",
    ordinaryEchoes=sparse, lockedEchoes=locked,
})
Check(rejectedSparse == nil and tostring(sparseReason):find("dense",1,true),
    "sparse candidate evidence did not fail closed")

local future, futureReason = Evidence.Validate({
    evidenceKind="candidate-typed-v2", ordinaryEchoes={}, lockedEchoes={},
})
Check(future == nil and tostring(futureReason):find("unsupported",1,true),
    "future-owned candidate evidence did not fail closed")

local legacy = Copy(opened)
legacy.evidenceKind = "leaderboard-typed-v1"
local legacyValid, legacyReason = Evidence.Validate(legacy)
Check(legacyValid and legacyReason == nil,
    "existing leaderboard-typed-v1 candidate lost compatibility")

local altered = Copy(opened)
altered.ordinaryEchoes[1].spellId = 699999
local alteredValid, alteredReason = Evidence.Validate(altered)
Check(alteredValid == nil and tostring(alteredReason):find("changed",1,true),
    "mutated candidate evidence retained preview authority")

print(string.format(
    "stage35 candidate evidence: community=79+6 shared-role=yes rejected=80/7/sparse/future legacy=yes mutations=0 checks=%d -- OK",
    checks))
