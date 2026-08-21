-- Public identity presentation keeps authoritative realms distinct, shadows
-- ambiguous duplicates without erasing them, and uses the same labels for
-- Leaderboard and Community projections.
local H = dofile("tests/harness.lua")

Nexus = {}
dofile("core/Revisions.lua")
dofile("core/Identity.lua")
dofile("core/LoadoutEvidence.lua")
Nexus.LoadoutEvidence.Init({})
dofile("core/CandidateEvidence.lua")
dofile("core/DiagnosticHistory.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua")
dofile("core/SyncTransport.lua")
dofile("core/SyncCompatibility.lua")
dofile("core/SyncReconciler.lua")
dofile("core/SyncInbound.lua")
dofile("core/SyncDiagnostics.lua")
dofile("core/SyncSession.lua")
dofile("core/Sync.lua")
dofile("core/DpsCapture.lua")

UnitName = function(unit) return unit == "player" and "Viewer" or nil end
UnitClass = function() return "Mage", "MAGE" end
GetNormalizedRealmName = function() return "ViewerRealm" end

local DPS, Codec, Sync = Nexus.DpsCapture, Nexus.Codec, Nexus.Sync
local Identity = Nexus.Identity
local function Echoes(spellId)
    return {{spellId=spellId,quality=3,stacks=1}}
end
local function Row(player, ownerKey, realm, spellId, dps, stamp, category)
    local echoes = Echoes(spellId)
    return {
        player=player,ownerKey=ownerKey,realm=realm,
        ownerVerified=ownerKey and true or false,
        dps=dps,level=80,ts=stamp,duration=category == "lk" and 240 or 65,
        class="MAGE",category=category,
        echoes=echoes,fingerprint=DPS.GetEchoKey(echoes),
        loadoutHash=DPS.GetEchoHash(echoes),
        lockedEchoes={{spellId=spellId+1000,quality=4,stacks=1}},
        buildId="build-"..spellId,protocolVersion=7,
    }
end

local aDummy = Row("Twin", "twin@realma", "realma", 810001,
    25000000, 10, "dummy")
local aBetter = Row("Twin", "twin@realma", "realma", 810002,
    27000000, 11, "dummy")
local bDummy = Row("Twin", "twin@realmb", "realmb", 810003,
    26000000, 12, "dummy")
local aLk = Row("Twin", "twin@realma", "realma", 810002,
    19000000, 13, "lk")
local bLk = Row("Twin", "twin@realmb", "realmb", 810003,
    21000000, 14, "lk")

NexusDB = {
    communityBuilds={},syncTombstones={},
    dpsCapture={characterBest={
        dummy={
            ["twin@realma"]=aBetter,
            ["legacy-case-alias"]=aDummy,
            ["twin@realmb"]=bDummy,
        },
        lk={
            ["twin@realma"]=aLk,
            ["twin@realmb"]=bLk,
        },
    }},
}

Sync.Init(Codec, {})
DPS.Init({}, Sync)

-- Two stored rows with the same proven owner reconcile through the existing
-- per-category better-row rule and retain the exact winning evidence.
local dummy = DPS.GetDpsBoard("dummy")
assert(#dummy == 2, "same canonical owner did not reconcile to one row")
local byOwner = {}
for _, row in ipairs(dummy) do byOwner[row.ownerKey] = row end
assert(byOwner["twin@realma"] and byOwner["twin@realma"].dps == 27000000
        and byOwner["twin@realma"].fingerprint == aBetter.fingerprint
        and byOwner["twin@realma"].lockedEchoes[1].spellId == 811002,
    "canonical reconciliation did not retain the strongest historical row")
local storedA = NexusDB.dpsCapture.characterBest.dummy["twin@realma"]
assert(storedA and storedA.buildId == aBetter.buildId
        and storedA.fingerprint == aBetter.fingerprint
        and storedA.lockedEchoes[1].spellId == 811002,
    "canonical reconciliation rewrote the winning stored evidence")
assert(byOwner["twin@realma"].displayPlayer ~= byOwner["twin@realmb"].displayPlayer
        and byOwner["twin@realma"].displayPlayer:find("realma",1,true)
        and byOwner["twin@realmb"].displayPlayer:find("realmb",1,true),
    "different verified realms are not visibly distinguishable")

local function WireRecord(player, spellId, dps, stamp, category,
        ownerKey, realm, extras)
    local echoes = Echoes(spellId)
    local record = {
        v=7,f=DPS.GetEchoKey(echoes),h=DPS.GetEchoHash(echoes),e=echoes,
        c=category,d=dps,u=category == "lk" and 240 or 65,t=stamp,
        p=player,l=80,k="MAGE",o=ownerKey,r=realm,
        lk={{spellId=spellId+1000,quality=4,stacks=1}},
    }
    for key, value in pairs(extras or {}) do record[key] = value end
    return record
end
local function Deliver(sender, transferId, record)
    local encoded = Codec.Base64Encode(Codec.JSONEncode(record))
    local chunkSize, result = 120, false
    local total = math.ceil(#encoded/chunkSize)
    for index=1,total do
        local packet=string.format("WLD2|%s|%s|%d/%d|%s",sender,
            transferId,index,total,encoded:sub(
                (index-1)*chunkSize+1,index*chunkSize))
        assert(#packet <= 255, "identity fixture exceeded wire limit")
        result = Sync.HandleIncoming(packet,sender) or result
    end
    return result
end

-- A realm carried only by the durable player field is still part of the
-- ambiguity tuple. It must not collapse with a different raw realm, and the
-- resulting public labels must remain distinct without granting authority.
local qualifiedA = {player="Twin-RealmA",ownerVerified=false}
local qualifiedB = {player="Twin-RealmB",ownerVerified=false}
assert(Identity.PublicRecordKey(qualifiedA, "player")
        ~= Identity.PublicRecordKey(qualifiedB, "player"),
    "qualified ambiguous players collapsed to the same public identity")
local qualifiedRows = Identity.PresentPublicRecords(
    {qualifiedA,qualifiedB}, "player", {shadowAmbiguous=true})
assert(#qualifiedRows == 2
        and qualifiedRows[1].displayPlayer ~= qualifiedRows[2].displayPlayer,
    "qualified ambiguous realms rendered as one public identity")

-- Presentation rejects malformed batch elements and sanitizes hostile durable
-- text for display without mutating the raw evidence.
local hostile = {id="hostile",author="Twin\n|cffff0000Spoof|r",
    ownerVerified=false}
local safeRows = Identity.PresentPublicRecords({"bad",42,hostile}, "author")
assert(#safeRows == 1 and safeRows[1] == hostile
        and hostile.author == "Twin\n|cffff0000Spoof|r"
        and type(hostile.displayAuthor) == "string"
        and not hostile.displayAuthor:find("\n",1,true)
        and not hostile.displayAuthor:find("|c",1,true),
    "malformed public identity text escaped validation or crashed presentation")
local explosive = setmetatable({}, {__tostring=function()
    error("hostile tostring")
end})
local malformedA, malformedB = {player=explosive}, {player={}}
local malformedOk, malformedRows = pcall(Identity.PresentPublicRecords,
    {malformedA,malformedB}, "player")
assert(malformedOk and #malformedRows == 0,
    "unsupported identity values invoked tostring or entered public rows")
local invalidA, invalidB = {player="Bad\nA"}, {player="Bad\nB"}
local invalidRows = Identity.PresentPublicRecords(
    {invalidA,invalidB}, "player")
assert(#invalidRows == 2
        and invalidA.publicIdentityKey ~= invalidB.publicIdentityKey
        and invalidA.displayPlayer ~= invalidB.displayPlayer,
    "distinct bounded malformed identities collapsed in presentation")
local oversized = {player=string.rep("x", 4096),ownerVerified=false}
local oversizedKey = Identity.PublicRecordKey(oversized, "player")
local oversizedRows = Identity.PresentPublicRecords({oversized}, "player")
assert(#oversizedKey < 256 and #oversizedRows == 0
        and oversizedKey:find(":4096:oversized",1,true),
    "oversized malformed identity escaped bounded quarantine")

-- A stronger realm-less Sync record remains durable evidence but cannot
-- displace or visually duplicate either proven Twin.
local ambiguous = WireRecord("Twin", 810004, 40000000, 20, "dummy",
    "twin@realma", "realma")
assert(Deliver("Twin", "ambiguous-twin", ambiguous),
    "realm-less Sync evidence was not retained")
assert(NexusDB.dpsCapture.characterBest.dummy.twin
        and NexusDB.dpsCapture.characterBest.dummy.twin.dps == 40000000,
    "ambiguous stronger evidence was erased or assigned")
dummy = DPS.GetDpsBoard("dummy")
assert(#dummy == 2, "ambiguous Twin was counted as a public duplicate")
for _, row in ipairs(dummy) do
    assert(row.ownerVerified == true and row.displayPlayer ~= "Twin",
        "verified Twin lost public precedence or realm qualification")
end

-- A later exact copy may promote only the identical ambiguous evidence.
local bridge = WireRecord("Bridge", 810005, 23000000, 21, "dummy",
    "bridge@realmc", "realmc")
assert(Deliver("Bridge", "bridge-short", bridge),
    "ambiguous bridge evidence was not retained")
assert(Deliver("Bridge-RealmC", "bridge-exact", bridge),
    "exact bridge did not promote matching evidence")
assert(not NexusDB.dpsCapture.characterBest.dummy.bridge
        and NexusDB.dpsCapture.characterBest.dummy["bridge@realmc"]
        and NexusDB.dpsCapture.characterBest.dummy["bridge@realmc"].ownerVerified,
    "exact bridge did not atomically promote only its matching row")

-- Historical short rows may predate derived metadata.  Missing duration/hash,
-- build ID, or locked evidence can be enriched only when every represented
-- identity and score field is otherwise exact.
local missing = WireRecord("MissingBridge", 810009, 22500000, 22, "dummy",
    "missingbridge@realmc", "realmc")
assert(Deliver("MissingBridge", "missing-short", missing),
    "historical missing-metadata fixture was not retained")
local missingRow = NexusDB.dpsCapture.characterBest.dummy.missingbridge
missingRow.duration,missingRow.loadoutHash,missingRow.buildId,
    missingRow.lockedEchoes = nil,nil,nil,nil
missing.b = "new-build-id"
assert(Deliver("MissingBridge-RealmC", "missing-exact", missing),
    "exact historical bridge was not accepted")
local missingCanonical =
    NexusDB.dpsCapture.characterBest.dummy["missingbridge@realmc"]
assert(not NexusDB.dpsCapture.characterBest.dummy.missingbridge
        and missingCanonical and missingCanonical.ownerVerified == true
        and missingCanonical.duration == 65
        and type(missingCanonical.loadoutHash) == "string"
        and missingCanonical.loadoutHash ~= ""
        and missingCanonical.buildId == "new-build-id"
        and type(missingCanonical.lockedEchoes) == "table",
    "missing historical metadata blocked or weakened exact promotion")

local function AssertMalformedHistorical(name, spellId, field, value)
    local short = WireRecord(name, spellId, 22400000, spellId, "dummy",
        name:lower().."@realmc", "realmc")
    assert(Deliver(name, name.."-malformed-short", short),
        name.." malformed fixture was not retained")
    NexusDB.dpsCapture.characterBest.dummy[name:lower()][field] = value
    assert(Deliver(name.."-RealmC", name.."-malformed-exact", short),
        name.." exact evidence was not retained separately")
    local bucket = NexusDB.dpsCapture.characterBest.dummy
    assert(bucket[name:lower()] and bucket[name:lower().."@realmc"],
        name.." malformed represented metadata was treated as missing")
end
AssertMalformedHistorical("MalformedDuration", 810010,
    "duration", "not-a-duration")
AssertMalformedHistorical("MalformedHash", 810011,
    "loadoutHash", {future=true})
AssertMalformedHistorical("MalformedLocked", 810012,
    "lockedEchoes", {future=true})
AssertMalformedHistorical("MalformedDurationType", 810013,
    "duration", false)
AssertMalformedHistorical("MalformedLockedType", 810014,
    "lockedEchoes", false)
AssertMalformedHistorical("MalformedBuildId", 810015,
    "buildId", {future=true})
AssertMalformedHistorical("MalformedBuildText", 810018,
    "buildId", "bad\nid")
AssertMalformedHistorical("UnresolvedLockedReference", 810016,
    "lockedEvidenceKey", "future-or-missing-reference")
AssertMalformedHistorical("ConflictingLockedReference", 810017,
    "lockedEvidenceKey", NexusDB.dpsCapture.characterBest.dummy[
        "bridge@realmc"].lockedEvidenceKey)

-- A direct exact sender may promote only a byte-for-byte equivalent public
-- evidence set. Equal headline score metadata is insufficient when duration,
-- build identity, or locked evidence differs.
local function AssertDivergentBridge(name, spellId, shortExtras, exactExtras)
    local short = WireRecord(name, spellId, 22000000, spellId, "dummy",
        name:lower().."@realmc", "realmc", shortExtras)
    assert(Deliver(name, name.."-short", short),
        name.." ambiguous evidence was not retained")
    local exact = WireRecord(name, spellId, 22000000, spellId, "dummy",
        name:lower().."@realmc", "realmc", exactExtras)
    assert(Deliver(name.."-RealmC", name.."-exact", exact),
        name.." direct evidence was not retained")
    local bucket = NexusDB.dpsCapture.characterBest.dummy
    assert(bucket[name:lower()] and bucket[name:lower().."@realmc"],
        name.." distinct ambiguous evidence was destructively promoted")
end
AssertDivergentBridge("DurationBridge", 810006, {u=65}, {u=66})
AssertDivergentBridge("BuildBridge", 810007, {b="build-a"}, {b="build-b"})
AssertDivergentBridge("LockedBridge", 810008,
    {lk={{spellId=811008,quality=4,stacks=1}}},
    {lk={{spellId=811009,quality=4,stacks=1}}})

-- Reload retains both proven realms and the shadowed ambiguous evidence.
Sync.Init(Codec, {})
DPS.Init({}, Sync)
assert(NexusDB.dpsCapture.characterBest.dummy.twin,
    "reload erased ambiguous historical evidence")
dummy = DPS.GetDpsBoard("dummy")
assert(#dummy == 16, "reload changed public identity reconciliation")

-- The shared projection policy applies to Dummy, LK, Combined, and Community
-- before sorting/counting/paging. Community builds remain distinct records,
-- but their authors can never render as indistinguishable Twin labels.
local builds = {
    a={id="a",title="Realm A",author="Twin",ownerKey="twin@realma",
        realm="realma",ownerVerified=true,class="MAGE",ordinaryComplete=true,
        echoes=Echoes(820001),fingerprint=DPS.GetEchoKey(Echoes(820001))},
    b={id="b",title="Realm B",author="Twin",ownerKey="twin@realmb",
        realm="realmb",ownerVerified=true,class="MAGE",ordinaryComplete=true,
        echoes=Echoes(820002),fingerprint=DPS.GetEchoKey(Echoes(820002))},
    legacy={id="legacy",title="Legacy",author="Twin",class="MAGE",
        ownerVerified=false,ordinaryComplete=true,
        echoes=Echoes(820003),fingerprint=DPS.GetEchoKey(Echoes(820003))},
    [1]={id=1,title="Numeric identity",author="Other",class="MAGE",
        ownerVerified=false,ordinaryComplete=true,buildId="shared",
        echoes=Echoes(820004),fingerprint=DPS.GetEchoKey(Echoes(820004))},
    ["1"]={id="1",title="String identity",author="Other",class="MAGE",
        ownerVerified=false,ordinaryComplete=true,buildId="shared",
        echoes=Echoes(820005),fingerprint=DPS.GetEchoKey(Echoes(820005))},
    oversized={id="oversized",title="Quarantined identity",
        author=string.rep("x",4096),class="MAGE",ownerVerified=false,
        ordinaryComplete=true,echoes=Echoes(820006),
        fingerprint=DPS.GetEchoKey(Echoes(820006))},
}
Nexus.BuildCatalog = {
    Summaries=function() return builds end,
    Status=function() return {availableCount=6} end,
}
dofile("core/ViewProjections.lua")
local P = Nexus.ViewProjections
local function Board(category)
    local rows, summary = P.Leaderboard(category,
        {classFilter="ALL",search=""})
    assert(rows and summary and summary.filtered == #rows,
        category.." public count did not match reconciled rows")
    return rows
end
local projectedDummy, projectedLk, combined =
    Board("dummy"), Board("lk"), Board("combined")
assert(#projectedDummy == 16 and #projectedLk == 2 and #combined == 2,
    "Dummy/LK/Combined did not share canonical identity policy")
for _, rows in ipairs({projectedDummy,projectedLk,combined}) do
    local labels = {}
    for _, row in ipairs(rows) do
        assert(not labels[row.displayPlayer],
            "public leaderboard rendered indistinguishable identity labels")
        labels[row.displayPlayer] = true
    end
end

local community, summary = P.Builds({currentClassOnly=false,
    qualifiedOnly=false,scope="all",sortMode="title",page=1})
assert(#community == 5 and summary.filteredTotal == 5
        and summary.displayedCount == 5 and summary.total == 5
        and summary.ready == 5 and summary.availableCount == 5
        and summary.filterMatchedCount == 5,
    "Community public counts included quarantined identity evidence")
local authorLabels = {}
for _, build in ipairs(community) do
    assert(type(build.displayAuthor) == "string"
            and not authorLabels[build.displayAuthor],
        "Community rendered indistinguishable Twin identities")
    authorLabels[build.displayAuthor] = true
end
local legacyLabel
for label in pairs(authorLabels) do
    if label:find("Twin (legacy/unverified ",1,true) == 1 then
        legacyLabel = label
    end
end
assert(legacyLabel,
    "ambiguous Community evidence lacks an explicit diagnostic label")

local reversed = Identity.PresentPublicRecords(
    {builds["1"],builds[1]}, "author")
local stableById = {}
for _, build in ipairs(community) do
    if build.id == 1 or build.id == "1" then
        stableById[type(build.id)..":"..tostring(build.id)] = build.displayAuthor
    end
end
for _, build in ipairs(reversed) do
    local key = type(build.id)..":"..tostring(build.id)
    assert(stableById[key] == build.displayAuthor,
        "ambiguous public label changed with input order")
end

-- Equal headline scores use the stable public identity as the final rank key.
local tieA = Row("Tie", "tie@realma", "realma", 830001,
    18000000, 30, "dummy")
local tieB = Row("Tie", "tie@realmb", "realmb", 830002,
    18000000, 30, "dummy")
local tieBucket = NexusDB.dpsCapture.characterBest.dummy
tieBucket["tie@realma"],tieBucket["tie@realmb"] = tieA,tieB
local tieRows = {}
for _, row in ipairs(DPS.GetDpsBoard("dummy")) do
    if row.player == "Tie" then tieRows[#tieRows + 1] = row end
end
assert(#tieRows == 2 and tieRows[1].publicIdentityKey
        < tieRows[2].publicIdentityKey,
    "equal-score realm identities retained hash-order ranking")

print("canonical public reconciliation, realm labels, ambiguity shadowing, reload, and Sync -- OK")
