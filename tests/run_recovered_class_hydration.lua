-- Stage 36.5 expected red: a legacy DPS row with complete inline ordinary
-- Echo evidence already has a bounded exact catalog identity, but the
-- projection currently returns that inline verdict before hydrating the
-- resolved catalog class. Exercise the real incremental DPS/projection/UI
-- path so filters and icons cannot be repaired by a test-only provider.

local H = dofile("tests/harness.lua")
dofile("core/DpsCapture.lua")

local Catalog = assert(Nexus.BuildCatalog)
local Projections = assert(Nexus.ViewProjections)
local DPS = assert(Nexus.DpsCapture)
local Identity = assert(Nexus.Identity)

local failures = {}
local desiredChecks, controls = 0, 0

local function Desired(ok, label)
    desiredChecks = desiredChecks + 1
    if not ok then failures[#failures + 1] = label end
end

local function Control(ok, label)
    controls = controls + 1
    assert(ok, "green control failed: " .. tostring(label))
end

local function Equal(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    seen = seen or {}
    if seen[left] then return seen[left] == right end
    seen[left] = right
    for key, value in pairs(left) do
        if not Equal(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function Echoes(spellId)
    return {{spellId=spellId,quality=3,stacks=1}}
end

local function Fingerprint(spellId)
    return tostring(spellId) .. "x1"
end

local accented = "Valentin" .. string.char(0xC3, 0xA9)
local remoteAccented = "Paladin" .. string.char(0xC3, 0xA9)
local realm = "Realm-Cluster"
local liveClass = "MAGE"
UnitName = function() return accented end
UnitClass = function()
    return liveClass == "PALADIN" and "Paladin" or "Mage", liveClass
end
GetNormalizedRealmName = function() return realm end

local TARGET_SPELL = 930001
local RAW_COLLISION_SPELL = 930099
local CURRENT_SPELL = 930002
local UNKNOWN_SPELL = 930003
local INVALID_SPELL = 930004
local AMBIGUOUS_SPELL = 930005
local MISMATCH_SPELL = 930006
local MISMATCH_INLINE_SPELL = 930096
local CONFLICT_SPELL = 930007
local INCOMPLETE_SPELL = 930008
local NOCLASS_SPELL = 930009
local SAME_PLAYER_SPELL = 930010
local LEGACY_HASH_SPELL = 930011
local LEGACY_STALE_HASH_SPELL = 930012

local targetFingerprint = Fingerprint(TARGET_SPELL)
local rawId = "stage36-class-raw-collision"
local resolvedId = "stage36-class-resolved-paladin"
local invalidId = "stage36-class-invalid"
local mismatchId = "stage36-class-mismatch"
local noClassId = "stage36-class-no-class-evidence"
local incompleteId = "stage36-class-incomplete-build"
local legacyHashId = "stage36-class-legacy-hash"
local legacyStoredHashId = "stage36-class-legacy-stored-hash"
local legacyFingerprint = Fingerprint(LEGACY_HASH_SPELL)
local legacyHash = assert(Nexus.LoadoutEvidence.CompatibilityHash(
    legacyFingerprint))
local ambiguousLegacyHash = assert(Nexus.LoadoutEvidence.CompatibilityHash(
    Fingerprint(AMBIGUOUS_SPELL)))
local maliciousStoredHash = "deadbeef"

local bundle = {
    schemaVersion=1,catalogVersion="stage36-class-red",sourceVersion="test",
    generatedAt=0,builds={
        [rawId]={
            id=rawId,title="Unrelated raw collision",author="Other",
            class="WARRIOR",fingerprint=Fingerprint(RAW_COLLISION_SPELL),
            echoes=Echoes(RAW_COLLISION_SPELL),lastModified=20,
        },
        [resolvedId]={
            id=resolvedId,title="Recovered Paladin",author=remoteAccented,
            ownerKey=Identity.OwnerKey(remoteAccented, realm),class="PALADIN",
            fingerprint=targetFingerprint,echoes=Echoes(TARGET_SPELL),
            autoDps=true,legacyRecovered=true,lastModified=10,
        },
        [invalidId]={
            id=invalidId,title="Invalid class",author="Invalidlegacy",
            class="NOT_A_CLASS",fingerprint=Fingerprint(INVALID_SPELL),
            echoes=Echoes(INVALID_SPELL),autoDps=true,lastModified=10,
        },
        ["stage36-class-ambiguous-a"]={
            id="stage36-class-ambiguous-a",title="Ambiguous A",
            author="Ambiguous",class="SHAMAN",
            fingerprint=Fingerprint(AMBIGUOUS_SPELL),
            echoes=Echoes(AMBIGUOUS_SPELL),lastModified=10,
        },
        ["stage36-class-ambiguous-b"]={
            id="stage36-class-ambiguous-b",title="Ambiguous B",
            author="Ambiguous",class="SHAMAN",
            fingerprint=Fingerprint(AMBIGUOUS_SPELL),
            echoes=Echoes(AMBIGUOUS_SPELL),lastModified=10,
        },
        [mismatchId]={
            id=mismatchId,title="Mismatched record",author="Mismatch",
            class="DRUID",fingerprint=Fingerprint(MISMATCH_SPELL),
            echoes=Echoes(MISMATCH_SPELL),lastModified=10,
        },
        [noClassId]={
            id=noClassId,title="No class evidence",author="Classless",
            fingerprint=Fingerprint(NOCLASS_SPELL),echoes=Echoes(NOCLASS_SPELL),
            autoDps=true,lastModified=10,
        },
        [incompleteId]={
            id=incompleteId,title="Recovered but incomplete",author="Incomplete",
            ownerKey=Identity.OwnerKey("Incomplete", realm),class="DRUID",
            fingerprint=Fingerprint(INCOMPLETE_SPELL),
            autoDps=true,lastModified=10,
        },
        [legacyHashId]={
            id=legacyHashId,title="Legacy hash record",author="Legacyhash",
            class="PRIEST",fingerprint=legacyFingerprint,
            fingerprintHash=legacyHash,echoes=Echoes(LEGACY_HASH_SPELL),
            autoDps=true,lastModified=10,
        },
        [legacyStoredHashId]={
            id=legacyStoredHashId,title="Untrusted stored hash",author="Storedhash",
            class="WARLOCK",fingerprint=Fingerprint(LEGACY_STALE_HASH_SPELL),
            fingerprintHash=maliciousStoredHash,
            echoes=Echoes(LEGACY_STALE_HASH_SPELL),autoDps=true,lastModified=10,
        },
    },
}

local targetPlayer = remoteAccented .. "-" .. realm
local currentPlayer = accented .. "-" .. realm
local asciiLookalike = "Valentine-" .. realm
local characterBest = {dummy={},lk={}}

characterBest.dummy.target = {
    player=targetPlayer,ownerKey=Identity.OwnerKey(remoteAccented, realm),
    ownerVerified=true,dps=900000,duration=60,level=80,ts=1,
    protocolVersion=6,buildId=rawId,fingerprint=targetFingerprint,
    echoes=Echoes(TARGET_SPELL),
}
characterBest.dummy.current = {
    player=currentPlayer,ownerKey=Identity.OwnerKey(accented, realm),
    ownerVerified=true,dps=890000,duration=60,level=80,ts=2,
    protocolVersion=6,buildId="stage36-class-current-missing",
    fingerprint=Fingerprint(CURRENT_SPELL),echoes=Echoes(CURRENT_SPELL),
}
characterBest.dummy.lookalike = {
    player=asciiLookalike,ownerKey=Identity.OwnerKey("Valentine", realm),
    ownerVerified=true,dps=880000,duration=60,level=80,ts=3,
    protocolVersion=6,buildId="stage36-class-lookalike-missing",
    fingerprint=Fingerprint(UNKNOWN_SPELL),echoes=Echoes(UNKNOWN_SPELL),
}
characterBest.dummy.samePlayerIncomplete = {
    player="Incompletetest",ownerKey=Identity.OwnerKey("Incomplete", realm),
    ownerVerified=true,dps=870400,duration=60,level=80,ts=3.6,
    protocolVersion=6,buildId=incompleteId,fingerprint=Fingerprint(INCOMPLETE_SPELL),
}
characterBest.dummy.invalid = {
    player="Invalidlegacy",dps=870000,duration=60,level=80,ts=4,
    protocolVersion=6,buildId="stage36-class-invalid-raw",
    fingerprint=Fingerprint(INVALID_SPELL),echoes=Echoes(INVALID_SPELL),
}
characterBest.dummy.ambiguous = {
    player="Ambiguouslegacy",dps=860000,duration=60,level=80,ts=5,
    protocolVersion=6,buildId="stage36-class-ambiguous-raw",
    fingerprint=Fingerprint(AMBIGUOUS_SPELL),echoes=Echoes(AMBIGUOUS_SPELL),
}
characterBest.dummy.mismatch = {
    player="Mismatchedlegacy",dps=850000,duration=60,level=80,ts=6,
    protocolVersion=6,buildId=mismatchId,
    fingerprint=Fingerprint(MISMATCH_SPELL),
    echoes=Echoes(MISMATCH_INLINE_SPELL),
}
characterBest.dummy.conflict = {
    player="Categoryconflict",class="MAGE",dps=840000,duration=60,
    level=80,ts=7,protocolVersion=6,
    buildId="stage36-class-conflict",
    fingerprint=Fingerprint(CONFLICT_SPELL),echoes=Echoes(CONFLICT_SPELL),
}
characterBest.dummy.noClassEvidence = {
    player="Classless",dps=839000,duration=60,level=80,ts=7.5,
    protocolVersion=6,buildId=noClassId,fingerprint=Fingerprint(NOCLASS_SPELL),
    echoes=Echoes(NOCLASS_SPELL),
}
characterBest.dummy.legacyHash = {
    player="Legacyhash",dps=838000,duration=60,level=80,ts=7.6,
    protocolVersion=6,buildId=legacyHashId,
    fingerprint="@" .. legacyHash,loadoutHash=legacyHash,
    echoes=Echoes(LEGACY_HASH_SPELL),
}
characterBest.dummy.legacyHashSummary = {
    player="Legacyhashsummary",dps=837900,duration=60,level=80,ts=7.61,
    protocolVersion=6,buildId=legacyHashId,
    fingerprint="@" .. legacyHash,loadoutHash=legacyHash,
}
characterBest.dummy.legacyHashMismatch = {
    player="Legacyhashmismatch",dps=837000,duration=60,level=80,ts=7.7,
    protocolVersion=6,buildId=legacyHashId,
    fingerprint="@deadbeef",loadoutHash="deadbeef",
}
characterBest.dummy.legacyStoredHash = {
    player="Legacystoredhash",dps=836900,duration=60,level=80,ts=7.71,
    protocolVersion=6,buildId=legacyStoredHashId,
    fingerprint="@"..maliciousStoredHash,loadoutHash=maliciousStoredHash,
    echoes=Echoes(LEGACY_STALE_HASH_SPELL),
}
characterBest.dummy.legacyLoadoutHashMismatch = {
    player="Legacyloadoutmismatch",dps=836800,duration=60,level=80,ts=7.72,
    protocolVersion=6,buildId=legacyHashId,
    fingerprint="@"..legacyHash,loadoutHash=maliciousStoredHash,
    echoes=Echoes(LEGACY_HASH_SPELL),
}
characterBest.dummy.legacyInlineMismatch = {
    player="Legacyinlinemismatch",dps=836700,duration=60,level=80,ts=7.73,
    protocolVersion=6,buildId=legacyHashId,
    fingerprint="@"..legacyHash,loadoutHash=legacyHash,
    echoes=Echoes(MISMATCH_INLINE_SPELL),
}
characterBest.dummy.legacyIdMismatch = {
    player="Legacyidmismatch",dps=836600,duration=60,level=80,ts=7.74,
    protocolVersion=6,buildId=mismatchId,
    fingerprint="@"..legacyHash,loadoutHash=legacyHash,
    echoes=Echoes(LEGACY_HASH_SPELL),
}
characterBest.dummy.legacyAmbiguous = {
    player="Legacyambiguous",dps=836500,duration=60,level=80,ts=7.75,
    protocolVersion=6,buildId="stage36-class-ambiguous-missing",
    fingerprint="@"..ambiguousLegacyHash,loadoutHash=ambiguousLegacyHash,
    echoes=Echoes(AMBIGUOUS_SPELL),
}
characterBest.lk.conflict = {
    player="Categoryconflict",class="ROGUE",dps=830000,duration=30,
    level=80,ts=8,protocolVersion=6,
    buildId="stage36-class-conflict",
    fingerprint=Fingerprint(CONFLICT_SPELL),echoes=Echoes(CONFLICT_SPELL),
}

Nexus.BundledBuilds = bundle
NexusDB = {
    communityBuilds={},syncTombstones={},
    dpsCapture={characterBest=characterBest,personalBest={},buildBest={}},
}
Catalog.Init(NexusDB, bundle)
DPS.Init({}, {})
local savedBefore = H.CloneValue(NexusDB)

-- The real incremental source may perform exact scalar/index lookups, but no
-- class repair may materialize or scan the complete catalog.
local allCalls, summariesCalls, exactCalls = 0, 0, 0
local originalAll = Catalog.All
local originalSummaries = Catalog.Summaries
local originalGetSummary = Catalog.GetSummary
local originalResolve = Catalog.ResolveFingerprintIdentity
Catalog.All = function()
    allCalls = allCalls + 1
    error("full catalog traversal is forbidden")
end
Catalog.Summaries = function()
    summariesCalls = summariesCalls + 1
    error("summary catalog traversal is forbidden")
end
Catalog.GetSummary = function(id)
    exactCalls = exactCalls + 1
    return originalGetSummary(id)
end
Catalog.ResolveFingerprintIdentity = function(rawBuildId, fingerprint, options)
    exactCalls = exactCalls + 1
    return originalResolve(rawBuildId, fingerprint, options)
end

local function Project(category, classFilter)
    local rows, summary, reason = Projections.RequestLeaderboard(
        category,{classFilter=classFilter,search=""})
    if type(rows) == "table" then return rows, summary, 0 end
    Control(reason == "pending", "cold projection entered bounded pending state")
    local pumps = 0
    while true do
        local published, pumpError = Projections.PumpLeaderboard()
        pumps = pumps + 1
        assert(not pumpError, tostring(pumpError))
        assert(pumps < 200, "bounded projection did not terminate")
        if published then break end
    end
    rows, summary, reason = Projections.RequestLeaderboard(
        category,{classFilter=classFilter,search=""})
    Control(type(rows) == "table" and reason == nil,
        "published projection was retrievable")
    return rows, summary, pumps
end

local function ByPlayer(rows)
    local out = {}
    for _, row in ipairs(rows or {}) do out[row.player] = row end
    return out
end
local function ByPlayerRows(rows)
    local out = {}
    for _, row in ipairs(rows or {}) do
        local player = tostring(row.player or "")
        local bucket = out[player]
        if bucket == nil then bucket = {} ; out[player] = bucket end
        bucket[#bucket + 1] = row
    end
    return out
end
local function FindByPlayerBuild(rows, player, buildId)
    for _, row in ipairs(rows or {}) do
        if row.player == player and row.buildId == buildId then
            return row
        end
    end
    return nil
end

Projections.Reset()
local allRows, allSummary, allPumps = Project("dummy", "ALL")
local allByPlayer = ByPlayer(allRows)
local allByPlayerRows = ByPlayerRows(allRows)
local target = allByPlayer[targetPlayer]
local current = allByPlayer[currentPlayer]
local lookalike = allByPlayer[asciiLookalike]
local invalid = allByPlayer.Invalidlegacy
local ambiguous = allByPlayer.Ambiguouslegacy
local mismatched = allByPlayer.Mismatchedlegacy
local targetPlayerRows = allByPlayerRows[targetPlayer] or {}
local classless = allByPlayer.Classless
local incompleteRecovered = allByPlayer.Incompletetest
local incompletePlayer = "Incompletetest"
local legacyHashRow = allByPlayer.Legacyhash
local legacyHashSummary = allByPlayer.Legacyhashsummary
local legacyHashMismatch = allByPlayer.Legacyhashmismatch
local legacyStoredHash = allByPlayer.Legacystoredhash
local legacyLoadoutHashMismatch = allByPlayer.Legacyloadoutmismatch
local legacyInlineMismatch = allByPlayer.Legacyinlinemismatch
local legacyIdMismatch = allByPlayer.Legacyidmismatch
local legacyAmbiguous = allByPlayer.Legacyambiguous
local targetResolvedByPlayer = FindByPlayerBuild(targetPlayerRows, targetPlayer, rawId)
local targetByResolvedMap = targetResolvedByPlayer or target

Control(#allRows == 9 and allSummary.filtered == 9,
    "All Classes did not retain exactly the complete accepted rows")
Control(targetByResolvedMap and targetByResolvedMap.buildId == rawId
        and targetByResolvedMap.resolvedBuildId == resolvedId
        and targetByResolvedMap.buildIdentityMismatch == true,
    "real exact index did not preserve raw and resolved identities")
Control(targetByResolvedMap and targetByResolvedMap.resolvedClass ~= "WARRIOR",
    "raw colliding catalog class gained authority")
Control(current and current.resolvedClass == "MAGE"
        and current.classSource == "record",
    "accented realm-qualified current identity did not normalize exactly: class="
        .. tostring(current and current.resolvedClass) .. " source="
        .. tostring(current and current.classSource) .. " player="
        .. tostring(current and current.player))
Control(lookalike and lookalike.resolvedClass == nil,
    "ASCII lookalike gained accented current-player class authority")
Control(invalid and invalid.resolvedClass == nil
        and ambiguous and ambiguous.resolvedClass == nil
        and mismatched == nil,
    "invalid or ambiguous class evidence gained authority, or mismatched ordinary evidence became public")
Control(classless and classless.resolvedClass == nil,
    "no evidence classless row gained class authority")
Control(incompleteRecovered == nil,
    "pending/incomplete recovered row reached the public Leaderboard")
Desired(targetByResolvedMap and targetByResolvedMap.resolvedClass == "PALADIN",
    "inline recovered exact class was not hydrated before return")
Desired(targetByResolvedMap and targetByResolvedMap.classSource == "exact-build",
    "inline recovered class did not retain exact-build provenance")
Desired(legacyHashRow and legacyHashRow.resolvedClass == "PRIEST"
        and legacyHashRow.classSource == "exact-build",
    "legacy @hash with inline evidence did not recover its exact build class")
Desired(legacyHashSummary and legacyHashSummary.resolvedClass == "PRIEST"
        and legacyHashSummary.classSource == "exact-build",
    "summary-only legacy @hash did not recover its exact build class")
for label, row in pairs({
    alias=legacyHashMismatch,storedHash=legacyStoredHash,
    loadoutHash=legacyLoadoutHashMismatch,inline=legacyInlineMismatch,
    buildId=legacyIdMismatch,ambiguous=legacyAmbiguous,
}) do
    Control(row == nil,
        "hostile legacy "..label.." claim reached the public Leaderboard")
end

local currentToken = select(2, UnitClass("player"))
local currentRows = Project("dummy", currentToken)
local currentByPlayer = ByPlayer(currentRows)
Control(currentByPlayer[currentPlayer] ~= nil
        and currentByPlayer[asciiLookalike] == nil,
    "current-class filtering changed exact accented identity behavior")

liveClass = "PALADIN"
local paladinRows = Project("dummy", select(2, UnitClass("player")))
local paladinByPlayerRows = ByPlayerRows(paladinRows)
local paladinByTarget = FindByPlayerBuild(
    paladinByPlayerRows[targetPlayer] or {}, targetPlayer, rawId)
Desired(paladinByTarget ~= nil,
    "current class filter excluded the inline recovered PALADIN")
local druidRows = Project("dummy", "DRUID")
local druidByPlayerRows = ByPlayerRows(druidRows)
local druidByTarget = FindByPlayerBuild(
    druidByPlayerRows.Incompletetest or {}, "Incompletetest", incompleteId)
Control(druidByTarget == nil,
    "class filter exposed the recovered-but-incomplete DRUID")
liveClass = "MAGE"

local priestRows = Project("dummy", "PRIEST")
local priestByPlayer = ByPlayer(priestRows)
Control(#priestRows == 2 and priestByPlayer.Legacyhash
        and priestByPlayer.Legacyhashsummary,
    "legacy hash recovery or unknown/mismatched class filtering changed")

local combinedRows = Project("combined", "ALL")
local combined = ByPlayer(combinedRows).Categoryconflict
Control(combined and combined.resolvedClass == nil
        and combined.classUnavailable == true,
    "Dummy/Lich King class disagreement did not fail closed")

-- Return to the All Classes key, then prove an identical warm request and UI
-- bind add no board/index/summary work.
allRows = Project("dummy", "ALL")
allByPlayer = ByPlayer(allRows)
local workBeforeWarm = Projections.WorkStats()
local exactBeforeWarm = exactCalls
local warmRows = Project("dummy", "ALL")
local workAfterWarm = Projections.WorkStats()
Control(Equal(warmRows, allRows)
        and exactCalls == exactBeforeWarm
        and workAfterWarm.sourceRows == workBeforeWarm.sourceRows
        and workAfterWarm.copies == workBeforeWarm.copies,
    "warm projection repeated source, copy, or exact catalog work")
Control(allCalls == 0 and summariesCalls == 0
        and workAfterWarm.maxSourceRowsPerPump <= 25,
    "class hydration used a broad or unbounded catalog path")

local madeFrames = {}
local realCreateFrame = CreateFrame
CreateFrame = function(...)
    local frame = realCreateFrame(...)
    madeFrames[#madeFrames + 1] = frame
    return frame
end
dofile("ui/Theme.lua")
dofile("ui/Leaderboard.lua")
Nexus.Sync = {
    IsReceiving=function() return false end,
    GetLeaderboardSyncStatus=function() return "idle",0,0,{} end,
}
Nexus.Leaderboard.Init(nil)
local exactBeforeUi = exactCalls
Nexus.Leaderboard.Show("dummy")
local boundByPlayer = {}
local boundByPlayerBuild = {}
for _, frame in ipairs(madeFrames) do
    if type(frame.data) == "table" and frame.icon then
        boundByPlayer[frame.data.player] = frame
        local key = tostring(frame.data.player or "") .. "|" .. tostring(frame.data.buildId or "")
        boundByPlayerBuild[key] = frame
    end
end
local targetPaladinBound = boundByPlayerBuild[tostring(targetPlayer) .. "|" .. tostring(rawId)]
local targetDruidBound = boundByPlayerBuild[tostring(incompletePlayer) .. "|" .. tostring(incompleteId)]
local lookalikeBound = boundByPlayer[asciiLookalike]
local currentBound = boundByPlayer[currentPlayer]
local PALADIN_ICON = "Interface\\Icons\\Spell_Holy_HolyBolt"
local MAGE_ICON = "Interface\\Icons\\Spell_Frost_Frostbolt02"
local NEUTRAL_ICON = "Interface\\Icons\\INV_Misc_Note_01"
Desired(targetPaladinBound
        and targetPaladinBound.icon:GetTexture() == PALADIN_ICON
        and targetPaladinBound.classLabel == "Paladin",
    "inline recovered class did not bind the PALADIN icon and label")
Control(targetDruidBound == nil,
    "incomplete recovered row bound a public class label")
Control(currentBound
        and currentBound.icon:GetTexture() == MAGE_ICON
        and lookalikeBound
        and lookalikeBound.icon:GetTexture() == NEUTRAL_ICON
        and lookalikeBound.classLabel == "Class unavailable",
    "current or unknown class icon presentation changed")
Control(exactCalls == exactBeforeUi,
    "warm UI binding repeated exact catalog work")
Control(Equal(NexusDB, savedBefore),
    "class projection or icon binding mutated SavedVariables")

Catalog.All = originalAll
Catalog.Summaries = originalSummaries
Catalog.GetSummary = originalGetSummary
Catalog.ResolveFingerprintIdentity = originalResolve

local summary = string.format(
    "desired=%d expected_red=%d controls=%d rows=%d pumps=%d exact=%d scans=%d mutations=0",
    desiredChecks,#failures,controls,#allRows,allPumps,exactCalls,
    allCalls + summariesCalls)
if #failures > 0 then
    for index, label in ipairs(failures) do
        print(string.format("EXPECTED RED %02d: %s", index, label))
    end
    error("EXPECTED RED [Stage 36.5 recovered class hydration]: "
        .. summary .. "\n - " .. table.concat(failures, "\n - "))
end
print("recovered class hydration: " .. summary .. " -- OK")
