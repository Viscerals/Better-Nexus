-- Durable owner authority is derived from the actual realm-qualified
-- transport sender. Display-name resemblance is never ownership proof.
local H = dofile("tests/harness.lua")

local Identity = Nexus.Identity

assert(Identity.CanonicalOwnerFromTransport("Twin-RealmA") == "twin@realma",
    "realm-qualified transport did not produce its canonical owner")
assert(Identity.CanonicalOwnerFromTransport("Twin") == nil,
    "realm-less transport produced durable owner authority")
assert(Identity.TransportOwns("twin@realma", "Twin-RealmA") == true,
    "exact canonical transport owner was not verified")
assert(Identity.TransportOwns("twin@realma", "Twin-RealmB") == false,
    "same-name cross-realm transport gained owner authority")

dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua")
dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua")
dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua")
dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
dofile("core/DpsCapture.lua")

local Codec, Sync, DPS = Nexus.Codec, Nexus.Sync, Nexus.DpsCapture

local function SettleCatalog()
    local catalog = Nexus.BuildCatalog
    for _ = 1, catalog.Budget().maximumPumps do
        if not catalog.RootState().candidate then break end
        catalog.PumpRootAdmission()
    end
    local state = catalog.RootState()
    assert(not state.candidate and state.state == "ROOT_ADMITTED",
        state.reason or "fixture catalog did not settle")
end

local rawHandleIncoming = Sync.HandleIncoming
Sync.HandleIncoming = function(...)
    SettleCatalog()
    local ok, why = rawHandleIncoming(...)
    if why == "ROOT_MUTATION_PENDING"
        or Nexus.BuildCatalog.RootState().candidate then
        SettleCatalog()
        return true, why
    end
    return ok, why
end

local function PutTerminal(record, options)
    SettleCatalog()
    local ok, why, ticket = Nexus.BuildCatalog.Put(record, options)
    if ok == nil and why == "ROOT_MUTATION_PENDING" then
        SettleCatalog()
        return ticket.committed, ticket.storedAs or ticket.reason, ticket
    end
    return ok, why, ticket
end

local rawBroadcastDelete = Sync.BroadcastDelete
Sync.BroadcastDelete = function(build)
    SettleCatalog()
    local ok, why, status = rawBroadcastDelete(build)
    if why == "ROOT_MUTATION_PENDING" then
        SettleCatalog()
        status = Sync.GetDeleteStatus(build and build.id)
        return status and status.accepted or false,
            status and status.reason or why, status
    end
    return ok, why, status
end

time = function() return 50000 end
NexusDB = {communityBuilds={},syncTombstones={},dpsCapture={}}
-- MASTER-RC-001 (architecture 1207-1211): Sync.Init and DpsCapture.Init no
-- longer admit the catalog root as a side effect. The same admission is
-- performed explicitly here, before the call, because the removed side
-- effect ran inside Init ahead of Init's own dependent steps. No assertion
-- or expected value in this fixture is changed.
H.AdmitCatalogV1(NexusDB)
Sync.Init(Codec, {})

local function BuildPacket(sender, id, ownerKey, stamp)
    local payload = {
        id=id,t="Twin Build",a="Twin",o=ownerKey,c="MAGE",m=stamp,
        e={{200100,3,1}},
    }
    return table.concat({"WLRB",sender,id,tostring(stamp),"1/1",
        Codec.Base64Encode(Codec.JSONEncode(payload))}, "|")
end

assert(Sync.HandleIncoming(
    BuildPacket("Twin-RealmA", "twin-a", "twin@realma", 10),
    "Twin-RealmA"), "exact realm-qualified owner build was rejected")
local exact = H.DurableBuilds()["twin-a"]
assert(exact and exact.ownerVerified == true
        and exact.ownerKey == "twin@realma",
    "exact realm-qualified owner build was not verified")

assert(Sync.HandleIncoming(
    BuildPacket("Twin-RealmA", "qualified-delete", "twin@realma", 10),
    "Twin-RealmA"), "qualified delete fixture was not stored")
assert(not Sync.HandleIncoming(
        "WLRD|Twin-RealmA|qualified-delete|11|Twin-RealmB", "Twin-RealmA")
        and H.DurableBuilds()["qualified-delete"]
        and H.DurableTombstones()["qualified-delete"] == nil,
    "EXPECTED RED: qualified delete author contradicted the exact sender owner")

local aliasConflictPayload = {
    id="build-alias-conflict",t="Alias Conflict",a="Twin",
    o="twin@realma",c="MAGE",m=10,e={{200101,3,1}},
    author="Mallory",ownerKey="mallory@realmx",
}
local aliasConflictPacket = table.concat({"WLRB","Twin-RealmA",
    aliasConflictPayload.id,"10","1/1",
    Codec.Base64Encode(Codec.JSONEncode(aliasConflictPayload))}, "|")
assert(not Sync.HandleIncoming(aliasConflictPacket,"Twin-RealmA")
        and H.DurableBuilds()[aliasConflictPayload.id] == nil,
    "EXPECTED RED: conflicting build aliases gained canonical authority")

assert(Sync.HandleIncoming(
    BuildPacket("Twin-RealmB", "twin-mismatch", "twin@realma", 11),
    "Twin-RealmB"), "cross-realm evidence was not retained")
local mismatch = H.DurableBuilds()["twin-mismatch"]
assert(mismatch and mismatch.ownerVerified == false
        and mismatch.ownerKey == nil
        and mismatch.claimedOwnerKey == "twin@realma"
        and mismatch.relaySender == "Twin-RealmB",
    "same-name cross-realm build gained durable owner authority")

local function SummaryPacket(sender, id, ownerKey, stamp)
    local payload = {
        id=id,t="Twin Summary",a="Twin",o=ownerKey,c="MAGE",m=stamp,
        h="1a2b",n=1,
    }
    return table.concat({"WLBI",sender,
        Codec.Base64Encode(Codec.JSONEncode(payload))}, "|")
end

assert(Sync.HandleIncoming(
    SummaryPacket("Twin-RealmA", "summary-a", "twin@realma", 20),
    "Twin-RealmA"), "exact realm-qualified summary was rejected")
local summary = H.DurableBuilds()["summary-a"]
assert(summary and summary.ownerVerified == true
        and summary.ownerKey == "twin@realma",
    "exact realm-qualified summary was not verified")

assert(not Sync.HandleIncoming(
    SummaryPacket("Twin-RealmB", "summary-mismatch", "twin@realma", 21),
    "Twin-RealmB"),
    "same-name cross-realm summary was accepted as direct-owner input")
assert(H.DurableBuilds()["summary-mismatch"] == nil,
    "same-name cross-realm summary entered durable state")

assert(Sync.HandleIncoming(
    BuildPacket("Twin", "twin-short", "twin@realma", 22), "Twin"),
    "realm-less build evidence was not retained")
local realmLess = H.DurableBuilds()["twin-short"]
assert(realmLess and realmLess.ownerVerified == false
        and realmLess.ownerKey == nil,
    "realm-less transport gained current-realm owner authority")

assert(Sync.HandleIncoming(
    BuildPacket("Twin-RealmB", "twin-b", "twin@realmb", 23),
    "Twin-RealmB"), "exact RealmB build was rejected")
assert(H.DurableBuilds()["twin-a"].ownerKey == "twin@realma"
        and H.DurableBuilds()["twin-b"].ownerKey == "twin@realmb",
    "same-name verified realm builds did not coexist")

assert(not Sync.HandleIncoming(
    BuildPacket("Twin-RealmB", "twin-mismatch", "twin@realmb", 25),
    "Twin-RealmB"),
    "RealmB replaced a retained RealmA owner claim")
assert(H.DurableBuilds()["twin-mismatch"].ownerVerified == false
        and H.DurableBuilds()["twin-mismatch"].claimedOwnerKey
            == "twin@realma"
        and H.DurableBuilds()["twin-mismatch"].relaySender
            == "Twin-RealmB",
    "failed wrong-owner promotion changed retained provenance")
assert(Sync.HandleIncoming(
    BuildPacket("Twin-RealmA", "twin-mismatch", "twin@realma", 25),
    "Twin-RealmA"),
    "the exact claimed owner could not promote retained evidence")
assert(H.DurableBuilds()["twin-mismatch"].ownerVerified == true
        and H.DurableBuilds()["twin-mismatch"].ownerKey
            == "twin@realma"
        and H.DurableBuilds()["twin-mismatch"].claimedOwnerKey == nil,
    "exact claimed-owner promotion did not establish canonical ownership")

assert(Sync.HandleIncoming(
    BuildPacket("Mallory-RealmX", "relayed-twin", "twin@realma", 25),
    "Mallory-RealmX"),
    "ordinary third-party relay evidence was not retained")
assert(H.DurableBuilds()["relayed-twin"].ownerVerified == false
        and H.DurableBuilds()["relayed-twin"].claimedOwnerKey
            == "twin@realma"
        and H.DurableBuilds()["relayed-twin"].relaySender
            == "Mallory-RealmX",
    "ordinary relay unexpectedly gained owner authority")
assert(Sync.HandleIncoming(
    BuildPacket("Twin-RealmA", "relayed-twin", "twin@realma", 25),
    "Twin-RealmA"),
    "exact owner could not promote matching third-party relay evidence")
assert(H.DurableBuilds()["relayed-twin"].ownerVerified == true
        and H.DurableBuilds()["relayed-twin"].ownerKey
            == "twin@realma",
    "exact owner promotion left relay evidence unverified")

assert(Sync.HandleIncoming(
    BuildPacket("Mallory-RealmX", "relayed-summary", "twin@realma", 30),
    "Mallory-RealmX"),
    "summary-promotion relay evidence was not retained")
local pendingBeforeSummary = Sync.WorkState().pendingReplacements
assert(Sync.HandleIncoming(
    SummaryPacket("Twin-RealmA", "relayed-summary", "twin@realma", 31),
    "Twin-RealmA"),
    "exact owner summary could not supersede relayed evidence")
assert(Sync.WorkState().pendingReplacements == pendingBeforeSummary + 1,
    "exact owner summary did not queue a verified replacement")

H.DurableBuilds()["legacy-nil-full"] = {
    id="legacy-nil-full",title="Legacy Nil Full",author="Twin",
    ownerKey="twin@realma",isMine=false,class="MAGE",lastModified=31,
    echoes={{spellId=200100,quality=3,stacks=1}},
}
H.RebindCatalog()
assert(not Sync.HandleIncoming(
    BuildPacket("Twin-RealmB", "legacy-nil-full", "twin@realmb", 32),
    "Twin-RealmB"),
    "wrong realm promoted a legacy nil-verification owner claim")
assert(Sync.HandleIncoming(
    BuildPacket("Twin-RealmA", "legacy-nil-full", "twin@realma", 32),
    "Twin-RealmA"),
    "exact owner could not refresh a legacy nil-verification claim")
assert(H.DurableBuilds()["legacy-nil-full"].ownerVerified == true,
    "fresh exact full packet did not verify the legacy owner claim")

H.DurableBuilds()["legacy-nil-summary"] = {
    id="legacy-nil-summary",title="Legacy Nil Summary",author="Twin",
    ownerKey="twin@realma",isMine=false,class="MAGE",lastModified=32,
}
H.RebindCatalog()
assert(Sync.HandleIncoming(
    SummaryPacket("Twin-RealmA", "legacy-nil-summary", "twin@realma", 33),
    "Twin-RealmA"),
    "exact owner summary could not refresh a legacy nil-verification claim")
assert(H.DurableBuilds()["legacy-nil-summary"].ownerVerified == true,
    "fresh exact summary did not verify the legacy owner claim")

H.DurableBuilds()["stale-mine-full"] = {
    id="stale-mine-full",title="Stale Mine Full",author="Twin",
    ownerKey="twin@realma",ownerVerified=false,isMine=true,class="MAGE",
    lastModified=33,echoes={{spellId=200101,quality=3,stacks=1}},
}
H.RebindCatalog()
assert(Sync.HandleIncoming(
    BuildPacket("Twin-RealmA", "stale-mine-full", "twin@realma", 34),
    "Twin-RealmA"),
    "EXPECTED RED: stale isMine blocked exact-owner full promotion")
assert(H.DurableBuilds()["stale-mine-full"].ownerVerified == true
        and H.DurableBuilds()["stale-mine-full"].isMine ~= true,
    "exact remote owner promotion retained stale local ownership")

H.DurableBuilds()["stale-mine-summary"] = {
    id="stale-mine-summary",title="Stale Mine Summary",author="Twin",
    ownerKey="twin@realma",ownerVerified=false,isMine=true,class="MAGE",
    lastModified=34,
}
H.RebindCatalog()
assert(Sync.HandleIncoming(
    SummaryPacket("Twin-RealmA", "stale-mine-summary", "twin@realma", 35),
    "Twin-RealmA"),
    "EXPECTED RED: stale isMine blocked exact-owner summary promotion")
assert(H.DurableBuilds()["stale-mine-summary"].ownerVerified == true
        and H.DurableBuilds()["stale-mine-summary"].isMine ~= true,
    "exact remote owner summary retained stale local ownership")

H.DurableBuilds()["stale-mine-delete"] = {
    id="stale-mine-delete",title="Stale Mine Delete",author="Twin",
    ownerKey="twin@realma",ownerVerified=false,isMine=true,class="MAGE",
    lastModified=35,echoes={{spellId=200102,quality=3,stacks=1}},
}
H.RebindCatalog()
assert(Sync.HandleIncoming(
    "WLRD|Twin-RealmA|stale-mine-delete|36|Twin", "Twin-RealmA"),
    "EXPECTED RED: stale isMine blocked exact-owner delete")
-- Protocol 7 proves no operation order, so the delete publishes a deny-only
-- reservation: the row leaves every public surface, its admitted raw evidence
-- is preserved, and the reservation records the exact owner claim.
assert(Nexus.BuildCatalog.Get("stale-mine-delete") == nil
        and H.DurableBuilds()["stale-mine-delete"] ~= nil
        and H.DurableTombstones()["stale-mine-delete"]
        and H.DurableTombstones()["stale-mine-delete"].ownerKey
            == "twin@realma",
    "exact remote delete did not replace stale local evidence with a tomb")

-- A historical raw true flag is not durable authority when its tuple is
-- malformed. It also must not pin the ID forever: only the fresh exact owner
-- transport may replace or delete the constrained claim.
local function MalformedTrue(id, stamp, complete)
    return {
        id=id,title="Malformed True",author="Twin",
        ownerKey="twin@realma",ownerVerified=true,realm="realma",
        -- A compact alias that contradicts its verbose field is refused at
        -- admission, so the retained claim is stated coherently here.
        o="twin@realma",claimedOwnerKey="twin@realma",
        class="MAGE",lastModified=stamp,
        echoes=complete and {{spellId=200103,quality=3,stacks=1}} or nil,
    }
end
H.DurableBuilds()["malformed-true-full"] =
    MalformedTrue("malformed-true-full",36,true)
H.RebindCatalog()
assert(not Sync.HandleIncoming(BuildPacket("Twin-RealmB",
        "malformed-true-full","twin@realmb",37),"Twin-RealmB"),
    "wrong realm repaired malformed raw-true build evidence")
assert(Sync.HandleIncoming(BuildPacket("Twin-RealmA",
        "malformed-true-full","twin@realma",37),"Twin-RealmA"),
    "EXPECTED RED: exact owner could not repair malformed raw-true build evidence")
assert(Identity.VerifiedOwnerKey(
        H.DurableBuilds()["malformed-true-full"])=="twin@realma"
        and H.DurableBuilds()["malformed-true-full"].o==nil
        and H.DurableBuilds()["malformed-true-full"].claimedOwnerKey==nil,
    "exact full repair retained malformed owner aliases")

H.DurableBuilds()["malformed-true-summary"] =
    MalformedTrue("malformed-true-summary",37,false)
H.RebindCatalog()
assert(Sync.HandleIncoming(SummaryPacket("Twin-RealmA",
        "malformed-true-summary","twin@realma",38),"Twin-RealmA"),
    "EXPECTED RED: exact owner summary could not repair malformed raw-true evidence")
assert(Identity.VerifiedOwnerKey(
        H.DurableBuilds()["malformed-true-summary"])=="twin@realma",
    "exact summary repair did not establish coherent owner authority")

H.DurableBuilds()["malformed-true-delete"] =
    MalformedTrue("malformed-true-delete",38,true)
H.RebindCatalog()
assert(Sync.HandleIncoming(
        "WLRD|Twin-RealmA|malformed-true-delete|39|Twin","Twin-RealmA")
        and Nexus.BuildCatalog.Get("malformed-true-delete")==nil
        and H.DurableBuilds()["malformed-true-delete"]~=nil
        and H.DurableTombstones()["malformed-true-delete"].ownerKey
            =="twin@realma",
    "EXPECTED RED: exact owner delete could not replace malformed raw-true evidence")

assert(Sync.HandleIncoming(
    BuildPacket("Mallory-RealmX", "relayed-delete", "twin@realma", 34),
    "Mallory-RealmX"),
    "delete-promotion relay evidence was not retained")
assert(Sync.HandleIncoming(
    "WLRD|Twin-RealmA|relayed-delete|35|Twin", "Twin-RealmA"),
    "exact owner could not delete its third-party relayed evidence")
assert(Nexus.BuildCatalog.Get("relayed-delete") == nil
        and H.DurableBuilds()["relayed-delete"] ~= nil
        and H.DurableTombstones()["relayed-delete"]
        and H.DurableTombstones()["relayed-delete"].ownerKey
            == "twin@realma",
    "relayed-evidence delete did not persist exact owner authority")

assert(Sync.HandleIncoming(
    BuildPacket("Twin-RealmB", "mismatch-delete", "twin@realma", 36),
    "Twin-RealmB"),
    "cross-realm delete fixture evidence was not retained")
assert(not Sync.HandleIncoming(
    "WLRD|Twin-RealmB|mismatch-delete|37|Twin", "Twin-RealmB"),
    "wrong realm deleted a retained RealmA owner claim")
assert(Sync.HandleIncoming(
    "WLRD|Twin-RealmA|mismatch-delete|37|Twin", "Twin-RealmA"),
    "exact claimed owner could not delete cross-realm retained evidence")

assert(not Sync.HandleIncoming(
    BuildPacket("Twin-RealmB", "twin-a", "twin@realmb", 26),
    "Twin-RealmB"),
    "same-name RealmB seized RealmA's verified build ID")
assert(H.DurableBuilds()["twin-a"].ownerKey == "twin@realma",
    "cross-realm owner change overwrote RealmA's verified build")

assert(not Sync.HandleIncoming(
    SummaryPacket("Twin-RealmB", "summary-a", "twin@realmb", 27),
    "Twin-RealmB"),
    "same-name RealmB summary seized RealmA's verified build ID")
assert(H.DurableBuilds()["summary-a"].ownerKey == "twin@realma",
    "cross-realm summary changed the verified owner")

assert(not Sync.HandleIncoming(
    BuildPacket("Twin-RealmA", "envelope-spoof", "twin@realma", 24),
    "Twin-RealmB"), "realm-mismatched envelope bypassed transport binding")
assert(H.DurableBuilds()["envelope-spoof"] == nil,
    "realm-mismatched envelope entered durable state")

assert(Sync.HandleIncoming("WLNP|Twin-RealmA|1.20.0", "Twin-RealmA")
        and Sync.HandleIncoming("WLNP|Twin-RealmB|1.20.1", "Twin-RealmB"),
    "realm-qualified presence fixtures were rejected")
local realmAPeer = Sync.GetPeerInfo("Twin-RealmA")
local realmBPeer = Sync.GetPeerInfo("Twin-RealmB")
assert(realmAPeer and realmBPeer and realmAPeer ~= realmBPeer
        and realmAPeer.version == "1.20.0"
        and realmBPeer.version == "1.20.1",
    "same-name realms collided in known-peer accounting")

UnitName = function() return "LocalTwin" end
GetNormalizedRealmName = function() return "RealmA" end
assert(Sync.HandleIncoming(
        "WLNP|LocalTwin-RealmA|1.20.0", "LocalTwin-RealmA")
        and Sync.HandleIncoming(
            "WLNP|LocalTwin-RealmB|1.20.1", "LocalTwin-RealmB"),
    "local-realm presence fixtures were rejected")
assert(Sync.GetPeerInfo("LocalTwin-RealmA") == nil,
    "exact local realm was retained as a remote peer")
assert(Sync.GetPeerInfo("LocalTwin-RealmB") ~= nil,
    "same-name foreign realm was discarded as local self traffic")
UnitName = function() return "Boganic" end
GetNormalizedRealmName = function() return "Ebonhold" end

H.AdmitCatalogV1(NexusDB)
DPS.Init({}, Sync)
local function DpsRecord(spellId, ownerKey, realm, dps, stamp)
    local echoes = {{spellId=spellId,stacks=1}}
    return {
        v=7,f=DPS.GetEchoKey(echoes),h=DPS.GetEchoHash(echoes),e=echoes,
        c="dummy",d=dps,u=65,t=stamp,p="Twin",l=80,k="MAGE",
        o=ownerKey,r=realm,
    }
end

local function DeliverDps(sender, transferId, record)
    local encoded = Codec.Base64Encode(Codec.JSONEncode(record))
    local chunkSize = 120
    local total = math.ceil(#encoded / chunkSize)
    local result = false
    for index = 1, total do
        local packet = string.format("WLD2|%s|%s|%d/%d|%s", sender,
            transferId,index,total,encoded:sub(
                (index - 1) * chunkSize + 1,index * chunkSize))
        assert(#packet <= 255, "DPS authority fixture exceeded wire limit")
        result = Sync.HandleIncoming(packet, sender) or result
    end
    return result
end

assert(DeliverDps("Twin-RealmA", "dps-a",
    DpsRecord(200200, "twin@realma", "realma", 25000000, 30)),
    "exact realm-qualified DPS owner was rejected")
assert(DeliverDps("Twin-RealmB", "dps-mismatch",
    DpsRecord(200201, "twin@realma", "realma", 26000000, 31)),
    "same-name cross-realm DPS evidence was not retained")

local rows = DPS.GetDpsBoard("dummy")
local byFingerprint = {}
for _, row in ipairs(rows) do byFingerprint[row.fingerprint] = row end
local exactDps = byFingerprint[DPS.GetEchoKey({{spellId=200200,stacks=1}})]
assert(#rows == 1 and exactDps and exactDps.ownerVerified == true
        and exactDps.ownerKey == "twin@realma",
    "cross-realm DPS input displaced the exact RealmA owner record")
local mismatchDps
for _, candidate in pairs(NexusDB.dpsCapture.characterBest.dummy) do
    if candidate.fingerprint == DPS.GetEchoKey({{spellId=200201,stacks=1}}) then
        mismatchDps = candidate
    end
end
assert(mismatchDps and mismatchDps.ownerVerified == false
        and mismatchDps.ownerKey == nil and mismatchDps.realm == "realmb",
    "shadowed cross-realm evidence was erased, authorized, or reassigned")

assert(DeliverDps("Twin-RealmB", "dps-b-exact",
    DpsRecord(200201, "twin@realmb", "realmb", 26000000, 31)),
    "later exact RealmB DPS owner could not promote its own evidence")
rows = DPS.GetDpsBoard("dummy")
byFingerprint = {}
for _, row in ipairs(rows) do byFingerprint[row.fingerprint] = row end
local promoted = byFingerprint[DPS.GetEchoKey({{spellId=200201,stacks=1}})]
assert(promoted and promoted.ownerVerified == true
        and promoted.ownerKey == "twin@realmb" and promoted.realm == "realmb",
    "later exact owner did not promote only its matching realm evidence")

assert(DeliverDps("Twin", "dps-short",
    DpsRecord(200202, "twin@realma", "realma", 24000000, 32)),
    "realm-less DPS evidence was not retained")
rows = DPS.GetDpsBoard("dummy")
byFingerprint = {}
for _, row in ipairs(rows) do byFingerprint[row.fingerprint] = row end
local shortDps
for _, candidate in pairs(NexusDB.dpsCapture.characterBest.dummy) do
    if candidate.fingerprint == DPS.GetEchoKey({{spellId=200202,stacks=1}}) then
        shortDps = candidate
    end
end
assert(shortDps and shortDps.ownerVerified == false
        and shortDps.ownerKey == nil and shortDps.realm == nil,
    "shadowed realm-less evidence was erased or borrowed payload realm authority")

H.AdmitCatalogV1(NexusDB)
Sync.Init(Codec, {})
H.AdmitCatalogV1(NexusDB)
DPS.Init({}, Sync)
assert(H.DurableBuilds()["twin-a"].ownerVerified == true
        and H.DurableBuilds()["twin-b"].ownerVerified == true
        and H.DurableBuilds()["twin-short"].ownerVerified == false,
    "reload recomputed build ownership from short-name resemblance")
rows = DPS.GetDpsBoard("dummy")
local verifiedRealms = {}
for _, row in ipairs(rows) do
    if row.ownerVerified == true then verifiedRealms[row.ownerKey] = true end
end
assert(verifiedRealms["twin@realma"] and verifiedRealms["twin@realmb"]
        and #rows == 2,
    "reload collapsed or re-authorized realm-qualified DPS evidence")
local retainedUnverified = 0
for _, candidate in pairs(NexusDB.dpsCapture.characterBest.dummy) do
    if candidate.ownerVerified ~= true then
        retainedUnverified = retainedUnverified + 1
    end
end
assert(retainedUnverified >= 1,
    "reload erased shadowed ambiguous DPS evidence")

local nilAuthority = {
    id="nil-authority",title="Unverified",author="Twin",
    ownerKey="twin@realma",class="MAGE",lastModified=40,
    echoes={{spellId=200300,quality=3,stacks=1}},
}
local relayed, relayWhy = Sync.BroadcastBuild(nilAuthority)
assert(relayed == false and relayWhy == "relay unauthorized",
    "ownerVerified=nil build remained relay-eligible")

local verifiedMissingOwner = {
    id="verified-missing-owner",title="Missing Owner",author="Twin",
    ownerVerified=true,class="MAGE",lastModified=40,
    echoes={{spellId=200302,quality=3,stacks=1}},
}
local missingOwnerRelayed, missingOwnerWhy =
    Sync.BroadcastBuild(verifiedMissingOwner)
assert(missingOwnerRelayed == false and missingOwnerWhy == "relay unauthorized",
    "ownerVerified=true without a canonical key retained relay authority")

local verifiedMismatchedOwner = {
    id="verified-mismatched-owner",title="Mismatched Owner",author="Twin",
    ownerKey="other@realma",ownerVerified=true,class="MAGE",lastModified=40,
    echoes={{spellId=200303,quality=3,stacks=1}},
}
local mismatchedOwnerRelayed, mismatchedOwnerWhy =
    Sync.BroadcastBuild(verifiedMismatchedOwner)
assert(mismatchedOwnerRelayed == false
        and mismatchedOwnerWhy == "relay unauthorized",
    "schema-mismatched verified metadata retained relay authority")

UnitName = function() return "Twin" end
GetNormalizedRealmName = function() return "RealmA" end
local falseLocalAuthority = {
    id="false-local-authority",title="Unverified Local-Looking",author="Twin",
    ownerKey="twin@realma",ownerVerified=false,isMine=true,class="MAGE",
    lastModified=40,echoes={{spellId=200301,quality=3,stacks=1}},
}
local falseLocalRelayed, falseLocalWhy =
    Sync.BroadcastBuild(falseLocalAuthority)
assert(falseLocalRelayed == false and falseLocalWhy == "relay unauthorized",
    "ownerVerified=false build regained authority through isMine")
assert(not Sync.BroadcastDelete(falseLocalAuthority),
    "ownerVerified=false build regained delete authority through isMine")

-- Saved-loadout mirrors remain pre-adoption evidence until the exact live-slot
-- reconciliation verifies them. Generic local legacy ownership must not let
-- Sync disclose, advertise, or tombstone that private evidence first.
local preAdoptionSaved = {
    id="pre-adoption-saved",title="Pre-adoption Saved",author="Twin",
    ownerKey="twin@realma",realm="realma",isMine=true,
    importedSavedBuild=true,class="MAGE",lastModified=41,
    echoes={{spellId=200305,quality=3,stacks=1}},
}
local claimlessSaved = {
    id="claimless-saved",title="Claimless Saved",author="Twin",isMine=true,
    importedSavedBuild=true,class="MAGE",lastModified=42,
    echoes={{spellId=200306,quality=3,stacks=1}},
}
local malformedSaved = {
    id="malformed-saved",title="Malformed Saved",author="Twin",
    ownerKey="twin@realma",realm="realma",isMine=true,
    importedSavedBuild="true",class="MAGE",lastModified=43,
    echoes={{spellId=200307,quality=3,stacks=1}},
}
local malformedSavedNumber = {
    id="malformed-saved-number",title="Malformed Saved Number",author="Twin",
    ownerKey="twin@realma",realm="realma",isMine=true,
    importedSavedBuild=1,class="MAGE",lastModified=44,
    echoes={{spellId=200308,quality=3,stacks=1}},
}
local malformedSavedZero = {
    id="malformed-saved-zero",title="Malformed Saved Zero",author="Twin",
    ownerKey="twin@realma",realm="realma",isMine=true,
    importedSavedBuild=0,class="MAGE",lastModified=45,
    echoes={{spellId=200309,quality=3,stacks=1}},
}
local malformedSavedTable = {
    id="malformed-saved-table",title="Malformed Saved Table",author="Twin",
    ownerKey="twin@realma",realm="realma",isMine=true,
    importedSavedBuild={future=true},class="MAGE",lastModified=46,
    echoes={{spellId=200310,quality=3,stacks=1}},
}
local foreignVerifiedSaved = {
    id="foreign-verified-saved",title="Foreign Verified Saved",author="Twin",
    ownerKey="twin@realmb",ownerVerified=true,realm="realmb",isMine=false,
    importedSavedBuild=true,class="ROGUE",lastModified=47,
    echoes={{spellId=200311,quality=3,stacks=1}},
}
local deniedSaved = {
    preAdoptionSaved,claimlessSaved,malformedSaved,malformedSavedNumber,
    malformedSavedZero,malformedSavedTable,foreignVerifiedSaved,
}
assert(not Identity.LocalOwnsRecord(preAdoptionSaved, "twin@realma")
    and not Identity.LocalOwnsBuild(preAdoptionSaved, "twin@realma")
    and Identity.CanAdoptSavedMirror(preAdoptionSaved, "twin@realma")
    and not Identity.LocalOwnsRecord(malformedSaved, "twin@realma")
    and not Identity.LocalOwnsBuild(malformedSaved, "twin@realma"),
    "typed Saved ownership or adoption dispatch changed")
for _, build in ipairs(deniedSaved) do
    local summaryQueued, summaryWhy = Sync.BroadcastBuildSummary(build)
    local fullQueued, fullWhy = Sync.BroadcastBuild(build)
    assert(not summaryQueued and summaryWhy == "relay unauthorized"
        and not fullQueued and fullWhy == "relay unauthorized"
        and not Sync.BroadcastDelete(build)
        and H.DurableTombstones()[build.id] == nil,
        "EXPECTED RED: pre-adoption or malformed Saved evidence crossed Sync: "
            .. build.id)
end

local inboundSummarySaved = {}
for key, value in pairs(preAdoptionSaved) do inboundSummarySaved[key] = value end
inboundSummarySaved.id = "inbound-saved-summary"
inboundSummarySaved.lastModified = 50
H.DurableBuilds()[inboundSummarySaved.id] = inboundSummarySaved
H.RebindCatalog()
assert(not Sync.HandleIncoming(SummaryPacket("Twin-RealmA",
        inboundSummarySaved.id,"twin@realma",51),"Twin-RealmA")
        and H.DurableBuilds()[inboundSummarySaved.id]
            .importedSavedBuild == true,
    "EXPECTED RED: exact owner summary converted private Saved evidence")

local inboundFullSaved = {}
for key, value in pairs(foreignVerifiedSaved) do inboundFullSaved[key] = value end
inboundFullSaved.id = "inbound-saved-full"
inboundFullSaved.lastModified = 51
H.DurableBuilds()[inboundFullSaved.id] = inboundFullSaved
H.RebindCatalog()
assert(not Sync.HandleIncoming(BuildPacket("Twin-RealmB",
        inboundFullSaved.id,"twin@realmb",52),"Twin-RealmB")
        and H.DurableBuilds()[inboundFullSaved.id]
            .importedSavedBuild == true,
    "EXPECTED RED: exact owner full packet converted private Saved evidence")

local inboundDeleteSaved = {}
for key, value in pairs(foreignVerifiedSaved) do inboundDeleteSaved[key] = value end
inboundDeleteSaved.id = "inbound-saved-delete"
inboundDeleteSaved.lastModified = 52
H.DurableBuilds()[inboundDeleteSaved.id] = inboundDeleteSaved
H.RebindCatalog()
assert(not Sync.HandleIncoming(
        "WLRD|Twin-RealmB|inbound-saved-delete|53|Twin","Twin-RealmB")
        and H.DurableBuilds()[inboundDeleteSaved.id]
        and H.DurableTombstones()[inboundDeleteSaved.id] == nil,
    "EXPECTED RED: exact owner delete tombstoned private Saved evidence")

local verifiedLocalSaved = {
    id="verified-local-saved",title="Verified Local Saved",author="Twin",
    ownerKey="twin@realma",ownerVerified=true,realm="realma",isMine=true,
    importedSavedBuild=true,class="MAGE",lastModified=48,
    echoes={{spellId=200312,quality=3,stacks=1}},
}
local explicitFalseOrdinary = {
    id="explicit-false-sync",title="Explicit False Sync",author="Twin",
    ownerKey="twin@realma",ownerVerified=true,realm="realma",isMine=true,
    importedSavedBuild=false,class="MAGE",lastModified=49,
    echoes={{spellId=200313,quality=3,stacks=1}},
}
local savedSummary, savedSummaryWhy =
    Sync.BroadcastBuildSummary(verifiedLocalSaved)
local savedFull, savedFullWhy = Sync.BroadcastBuild(verifiedLocalSaved)
assert(Identity.LocalOwnsBuild(verifiedLocalSaved, "twin@realma")
    and not savedSummary and savedSummaryWhy == "relay unauthorized"
    and not savedFull and savedFullWhy == "relay unauthorized"
    and not Sync.BroadcastDelete(verifiedLocalSaved)
    and H.DurableTombstones()[verifiedLocalSaved.id] == nil,
    "EXPECTED RED: private verified Saved mirror crossed direct Sync egress")
assert(Identity.SavedMirrorKind(explicitFalseOrdinary) == "ordinary"
    and Identity.LocalOwnsRecord(explicitFalseOrdinary, "twin@realma")
    and Sync.BroadcastBuildSummary(explicitFalseOrdinary)
    and Sync.BroadcastBuild(explicitFalseOrdinary),
    "explicit false ordinary build lost compatible Sync behavior")
local dedupeAuthority = {
    id="dedupe-authority",title="Dedupe Authority",author="Twin",
    ownerKey="twin@realma",ownerVerified=true,realm="realma",isMine=true,
    class="MAGE",lastModified=50,
    echoes={{spellId=200314,quality=3,stacks=1}},
}
assert(Sync.BroadcastBuild(dedupeAuthority),
    "dedupe authority positive control did not enter the queue")
local dedupeSaved = {}
for key, value in pairs(preAdoptionSaved) do dedupeSaved[key] = value end
dedupeSaved.id = dedupeAuthority.id
local dedupeQueued, dedupeWhy = Sync.BroadcastBuild(dedupeSaved)
assert(not dedupeQueued and dedupeWhy == "relay unauthorized",
    "dedupe suppression bypassed Saved authority admission")

local retainedDatabase = NexusDB
-- Legacy-to-bundle cutover (state machine lines 374, 394): clearing the exact
-- PR #68 location no longer resets durable state, so this exact store is seeded
-- as legacy input on a fresh database and admitted by bootstrap.
local deniedOverlay = {}
for _, build in ipairs(deniedSaved) do deniedOverlay[build.id] = build end
NexusDB = {communityBuilds=deniedOverlay, syncTombstones={}}
H.RebindCatalog()
H.AdmitCatalogV1(NexusDB)
Sync.Init(Codec, {})
H.sentChatMessages = {}
assert(Sync.BroadcastMine() == 0,
    "EXPECTED RED: BroadcastMine advertised pre-adoption Saved evidence")
for index, build in ipairs(deniedSaved) do
    assert(Sync.HandleIncoming(table.concat({"WLLQ","Requester-RealmQ",
            build.id,"c1-saved-private-" .. index}, "|"),
            "Requester-RealmQ"),
        "Saved authority-denial request was not handled deterministically: "
            .. build.id)
end
for _ = 1, 600 do Sync.OnUpdate(0.2) end
for _, message in ipairs(H.sentChatMessages) do
    for _, build in ipairs(deniedSaved) do
        assert(not tostring(message.text):find("|" .. build.id .. "|", 1, true),
            "EXPECTED RED: peer request disclosed denied Saved evidence: "
                .. build.id)
    end
end
NexusDB = {communityBuilds={
    [verifiedLocalSaved.id]=verifiedLocalSaved,
    [explicitFalseOrdinary.id]=explicitFalseOrdinary,
}, syncTombstones={}}
H.RebindCatalog()
H.AdmitCatalogV1(NexusDB)
Sync.Init(Codec, {})
H.sentChatMessages = {}
assert(Sync.BroadcastMine() == 1,
    "private Saved mirror was advertised or ordinary build left BroadcastMine")
for index, build in ipairs({verifiedLocalSaved, explicitFalseOrdinary}) do
    assert(Sync.HandleIncoming(table.concat({"WLLQ","Requester-RealmQ",
            build.id,"c1-saved-positive-" .. index}, "|"),
            "Requester-RealmQ"),
        "authorized exact loadout request was rejected: " .. build.id)
end
for _ = 1, 600 do Sync.OnUpdate(0.2) end
for _, build in ipairs({verifiedLocalSaved, explicitFalseOrdinary}) do
    local disclosed = false
    for _, message in ipairs(H.sentChatMessages) do
        if tostring(message.text):find("|" .. build.id .. "|", 1, true) then
            disclosed = true
        end
    end
    if build == verifiedLocalSaved then
        assert(not disclosed,
            "EXPECTED RED: peer request disclosed private verified Saved mirror")
    else
        assert(disclosed,
            "authorized exact ordinary loadout was not available to Sync: "
                .. build.id)
    end
end
-- MASTER-RC-019 SUPERSEDED EXPECTATION, architecture justification recorded.
-- Line 4856 and the mixed-client tombstone rows make a local row-to-tombstone
-- operation an UNCONDITIONAL zero-wire refusal with
-- REMOTE_TOMBSTONE_ORDER_UNPROVEN: it "is not a Sync message". The truthy
-- return this fixture required was the queued-to-wire result the architecture
-- forbids. The local tombstone is still committed through the central owner,
-- so every assertion about the durable tombstone below is unchanged; only the
-- wire-success half is replaced, by the strictly stronger named refusal.
local ordinaryDeleteOk, ordinaryDeleteWhy =
    Sync.BroadcastDelete(explicitFalseOrdinary)
assert(ordinaryDeleteOk == false
    and ordinaryDeleteWhy == "REMOTE_TOMBSTONE_ORDER_UNPROVEN"
    and H.DurableTombstones()[explicitFalseOrdinary.id]
    and H.DurableTombstones()[explicitFalseOrdinary.id].ownerKey
        == "twin@realma",
    "verified exact local ordinary build lost owner-authorized deletion")
NexusDB = retainedDatabase
H.RebindCatalog()
H.AdmitCatalogV1(NexusDB)
Sync.Init(Codec, {})

NexusDB.dpsCapture = {}
H.AdmitCatalogV1(NexusDB)
Sync.Init(Codec, {})
H.AdmitCatalogV1(NexusDB)
DPS.Init({}, Sync)
H.sentChatMessages = {}
local injectedEchoes = {{spellId=200304,stacks=1}}
local injected = DpsRecord(
    200304, "twin@realma", "realma", 28000000, 42)
injected.protocolVersion = injected.v
injected.fingerprint = injected.f
injected.loadoutHash = injected.h
injected.echoes = injected.e
injected.category = injected.c
injected.dps = injected.d
injected.duration = injected.u
injected.ts = injected.t
injected.player = injected.p
injected.level = injected.l
injected.class = injected.k
injected.ownerKey = injected.o
injected.realm = injected.r
injected.ownerVerified = true
injected._originVerified = true
assert(not DeliverDps("Twin-RealmB", "dps-injected-authority", injected),
    "payload-supplied DPS authority fields crossed protocol validation")
local injectedStored
for _, row in ipairs(DPS.GetDpsBoard("dummy")) do
    if row.fingerprint == DPS.GetEchoKey(injectedEchoes) then
        injectedStored = row
    end
end
assert(injectedStored == nil,
    "payload-supplied authority fields reached durable DPS state")
for _ = 1, 80 do Sync.OnUpdate(0.2) end
for _, message in ipairs(H.sentChatMessages) do
    assert(not message.text:find("^WLD2|"),
        "payload-supplied DPS authority was automatically re-broadcast")
end

local shortBroadcast = {}
for key, value in pairs(shortDps) do shortBroadcast[key] = value end
shortBroadcast.category = "dummy"
local sentUnverifiedDps, unverifiedDpsWhy =
    Sync.BroadcastDpsRecord(shortBroadcast)
assert(sentUnverifiedDps == false and unverifiedDpsWhy == "owner_sender",
    "realm-less unverified DPS row remained owner-broadcast eligible: "
        ..tostring(sentUnverifiedDps).."/"..tostring(unverifiedDpsWhy))
local sentExactDps = Sync.BroadcastDpsRecord(exactDps)
assert(sentExactDps == true,
    "exact verified local-realm DPS row lost owner-broadcast authority")

local ghostEchoes = {{spellId=200400,stacks=1}}
local ghostFingerprint = DPS.GetEchoKey(ghostEchoes)
local ghost = {
    player="Ghost",ownerKey="ghost@realma",realm="realma",
    ownerVerified=false,category="dummy",dps=27000000,duration=65,
    ts=41,level=80,class="MAGE",echoes=ghostEchoes,
    fingerprint=ghostFingerprint,loadoutHash=DPS.GetEchoHash(ghostEchoes),
    protocolVersion=7,
}
NexusDB.dpsCapture = {
    characterBest={dummy={["ghost@realma"]=ghost},lk={}},
    personalBest={},buildBest={},
}
UnitName = function() return "Ghost" end
H.AdmitCatalogV1(NexusDB)
DPS.Init({}, Sync)
local ghostBucket = DPS.SyncBucket("dummy", "Ghost")
local ghostClaimable = DPS.ResponseBucketClaimInfo(ghostBucket)
assert(ghostClaimable == false and not DPS.LocalOwnsDpsBucket(ghostBucket),
    "unverified same-name DPS row retained response-claim authority")

local malformedEchoes = {{spellId=200401,stacks=1}}
local malformedDps = {
    player="Bob",ownerKey="bob@realma",realm="realmb",
    ownerVerified=true,category="dummy",dps=27500000,duration=65,
    ts=43,level=80,class="MAGE",echoes=malformedEchoes,
    fingerprint=DPS.GetEchoKey(malformedEchoes),
    loadoutHash=DPS.GetEchoHash(malformedEchoes),protocolVersion=7,
}
NexusDB.dpsCapture = {
    characterBest={dummy={["bob@realma"]=malformedDps},lk={}},
    personalBest={},buildBest={},
}
UnitName = function() return "Bob" end
GetNormalizedRealmName = function() return "RealmA" end
H.AdmitCatalogV1(NexusDB)
DPS.Init({}, Sync)
local malformedBucket = DPS.SyncBucket("dummy", "Bob")
assert(DPS.ResponseBucketClaimInfo(malformedBucket) == false,
    "ownerKey/realm-mismatched DPS row retained response-claim authority")
local malformedSent, malformedWhy = Sync.BroadcastDpsRecord(malformedDps)
assert(malformedSent == false and malformedWhy == "owner_sender",
    "ownerKey/realm-mismatched DPS row remained outbound-authoritative")

assert(DPS.ReceiveRecord({
        v=7,f=malformedDps.fingerprint,h=malformedDps.loadoutHash,
        e=malformedEchoes,c="dummy",d=28000000,u=65,t=44,p="Bob",
        l=80,k="MAGE",o="bob@realma",r="realma",
    }, "Bob-RealmA"),
    "coherent exact DPS owner could not replace mismatched saved metadata")
local coherentDps = DPS.GetCharacterBest("dummy", "Bob")
coherentDps.category = "dummy"
local coherentClaimable = DPS.ResponseBucketClaimInfo(malformedBucket)
assert(coherentClaimable == true,
    "coherent verified DPS row lost response-claim eligibility")
local coherentSent, coherentWhy = Sync.BroadcastDpsRecord(coherentDps)
assert(coherentSent == true,
    "coherent exact-local DPS row lost outbound authority: "
        .. tostring(coherentWhy))

UnitName = function() return "Twin" end
GetNormalizedRealmName = function() return "RealmB" end
-- MASTER-RC-019. Both the non-owner and the owner path now return false,
-- because a local row-to-tombstone operation is an unconditional zero-wire
-- refusal (architecture 4856). The return value alone therefore no longer
-- discriminates ownership, so the discrimination is asserted where it is
-- actually observable and stronger: the non-owner is refused for lack of
-- ownership BEFORE the tombstone store is reached, so it carries no reason and
-- writes no tombstone, while the exact owner reaches the named
-- REMOTE_TOMBSTONE_ORDER_UNPROVEN refusal and does commit its local tombstone.
local foreignDeleteOk, foreignDeleteWhy =
    Sync.BroadcastDelete(H.DurableBuilds()["summary-a"])
assert(foreignDeleteOk == false
    and foreignDeleteWhy ~= "REMOTE_TOMBSTONE_ORDER_UNPROVEN",
    "same-name RealmB reached the owner tombstone path for RealmA's row")
assert(H.DurableBuilds()["summary-a"]
        and H.DurableTombstones()["summary-a"] == nil,
    "cross-realm local delete changed RealmA's durable state")
GetNormalizedRealmName = function() return "RealmA" end
H.RebindAuthorityOwner()
local realmADeleteOk, realmADeleteWhy =
    Sync.BroadcastDelete(H.DurableBuilds()["summary-a"])
assert(realmADeleteOk == false
    and realmADeleteWhy == "REMOTE_TOMBSTONE_ORDER_UNPROVEN",
    "exact local RealmA owner did not reach the named zero-wire refusal: "
        .. tostring(realmADeleteWhy))
assert(H.DurableTombstones()["summary-a"]
        and H.DurableTombstones()["summary-a"].ownerKey
            == "twin@realma",
    "local delete did not persist canonical tombstone authority")

H.AdmitCatalogV1(NexusDB)
Sync.Init(Codec, {})
H.sentChatMessages = {}
GetNormalizedRealmName = function() return "RealmB" end
assert(Sync.HandleIncoming(
    "WLRQ|Requester|0|0|realm-b-tomb", "Requester"),
    "cross-realm tombstone response request was rejected")
for _ = 1, 160 do Sync.OnUpdate(0.2) end
for _, message in ipairs(H.sentChatMessages) do
    assert(not (message.text:find("^WLRD|")
            and message.text:find("summary%-a")),
        "RealmB re-broadcast RealmA's owner-only tombstone")
end
GetNormalizedRealmName = function() return "RealmA" end

assert(not Sync.HandleIncoming(
    "WLRD|Twin-RealmB|twin-a|100|Twin", "Twin-RealmB"),
    "same-name RealmB transport deleted RealmA's verified build")
assert(H.DurableBuilds()["twin-a"] ~= nil,
    "cross-realm delete removed verified RealmA state")

assert(Sync.HandleIncoming(
    "WLRD|Twin-RealmA|twin-a|101|Twin", "Twin-RealmA"),
    "exact RealmA transport could not delete its verified build")
assert(Nexus.BuildCatalog.Get("twin-a") == nil
        and H.DurableBuilds()["twin-a"] ~= nil
        and H.DurableTombstones()["twin-a"]
        and H.DurableTombstones()["twin-a"].ownerKey == "twin@realma",
    "exact delete did not persist canonical tombstone authority")

H.AdmitCatalogV1(NexusDB)
Sync.Init(Codec, {})
H.sentChatMessages = {}
assert(Sync.RequestSync(), "canonical claim fixture could not start a request")
for _ = 1, 20 do Sync.OnUpdate(0.2) end
local activeRequestId
for _, message in ipairs(H.sentChatMessages) do
    local wire = message.text:gsub("||", "|")
    activeRequestId = activeRequestId or wire:match(
        "^WLRQ|[^|]+|[^|]+|[^|]+|([^|]+)|")
end
assert(type(activeRequestId) == "string" and activeRequestId ~= "",
    "canonical claim fixture did not expose its active request ID")
assert(not Sync.HandleIncoming(table.concat({"WLRC","Relay-RealmX",
        "Twin-RealmB",activeRequestId,"0","0"}, "|"), "Relay-RealmX"),
    "RealmB claim was accepted against RealmA's active request")
assert(not Sync.HandleIncoming(table.concat({"WLBC","Relay-RealmX",
        "Twin-RealmB",activeRequestId,"B","1","0"}, "|"),
        "Relay-RealmX"),
    "RealmB bucket claim was accepted against RealmA's active request")
assert(not Sync.HandleIncoming(table.concat({"WLBC","Relay-RealmX",
        "Twin",activeRequestId,"B","1","0"}, "|"),
        "Relay-RealmX"),
    "realm-less bucket claim borrowed RealmA request authority")
assert(not Sync.HandleIncoming(table.concat({"WLLC","Relay-RealmX",
        "Twin-RealmB","missing-build",activeRequestId}, "|"),
        "Relay-RealmX"),
    "RealmB loadout claim was accepted against RealmA's active request")
assert(Sync.HandleIncoming(table.concat({"WLLC","Relay-RealmX",
        "Twin-RealmA","missing-build",activeRequestId}, "|"),
        "Relay-RealmX"),
    "exact RealmA request context lost compatible loadout-claim handling")
assert(not Sync.HandleIncoming(
    BuildPacket("Twin-RealmB", "twin-a", "twin@realmb", 100),
    "Twin-RealmB"),
    "cross-realm stale build was accepted against RealmA's tombstone")
assert(not Sync.HandleIncoming(
    SummaryPacket("Twin-RealmB", "twin-a", "twin@realmb", 100),
    "Twin-RealmB"),
    "cross-realm stale summary was accepted against RealmA's tombstone")
assert(not Sync.HandleIncoming(
    "WLRD|Twin-RealmB|twin-a|100|Twin", "Twin-RealmB"),
    "cross-realm stale delete was accepted as RealmA's tombstone duplicate")
assert(not Sync.HandleIncoming(
    BuildPacket("Twin-RealmB", "twin-a", "twin@realma", 102),
    "Twin-RealmB"),
    "same-name RealmB transport resurrected RealmA's tombstoned build")
assert(Nexus.BuildCatalog.Get("twin-a") == nil,
    "cross-realm resurrection changed durable state after reload")

Nexus.BundledBuilds = {
    schemaVersion=1,catalogVersion="canonical-owner-baseline",
    sourceVersion="test",generatedAt=0,builds={
        ["bundled-owner"]={
            id="bundled-owner",title="Bundled Owner",author="Twin",
            ownerKey="twin@realma",class="MAGE",lastModified=1,postedAt=1,
            echoes={{spellId=200500,quality=3,stacks=1}},
        },
    },
}
H.AdmitCatalogV1(NexusDB)
Sync.Init(Codec, {})
-- MASTER-RC-004. This previously asserted that a sender whose transport
-- identity matches a BUNDLED row's author text may tombstone it. Architecture
-- 3b5de54f line 193 admits from a bundled row "Content fields and immutable
-- bundled source position only" and states that "Bundled author text never
-- proves local ownership", and line 202 requires internally coherent tuples to
-- obtain "zero verified-owner or mutation privilege". A bundled row's ownerKey
-- is content, not an owner claim a sender can prove, so the delete is refused
-- and no durable tombstone is written.
--
-- The guarantee this case exists for -- that only an exact canonical owner may
-- delete, and that a same-name or cross-realm sender may not -- is unchanged
-- and is still proven by the cross-realm cases immediately above. This is the
-- SPEC lane's remote route from the preserved disagreement "Severity and
-- reachable routes for bundled text becoming mutation authority"; the
-- disagreement itself is recorded, not resolved, by this repair.
assert(not Sync.HandleIncoming(
    "WLRD|Twin-RealmA|bundled-owner|200|Twin", "Twin-RealmA"),
    "bundled author text still proved remote delete authority")
assert(H.DurableTombstones()["bundled-owner"] == nil,
    "a refused bundled delete still wrote a durable tombstone")

UnitName = function() return "Relay" end
GetNormalizedRealmName = function() return "RealmX" end
Nexus.BundledBuilds = nil
NexusDB = {
    communityBuilds={
        ["nil-claim-row"]={
            id="nil-claim-row",title="Ambiguous Legacy",author="Bob",
            ownerKey="bob@otherrealm",isMine=false,class="MAGE",
            lastModified=300,
            echoes={{spellId=200600,quality=3,stacks=1}},
        },
    },
    syncTombstones={},dpsCapture={},
}
H.AdmitCatalogV1(NexusDB)
Sync.Init(Codec, {})
H.AdmitCatalogV1(NexusDB)
DPS.Init({}, Sync)
H.sentChatMessages = {}
local emptyBuildHash, emptyDpsHash = Sync.GetCompatibilityHashes()
assert(Sync.HandleIncoming(table.concat({"WLRQ","Requester-RealmQ",
        emptyBuildHash,emptyDpsHash,"c1-nil-owner-claim","1.20.0"}, "|"),
        "Requester-RealmQ"),
    "nil-owner response-claim fixture was rejected")
for _ = 1, 220 do Sync.OnUpdate(0.2) end
for _, message in ipairs(H.sentChatMessages) do
    assert(not message.text:find("^WLRB|")
            and not message.text:find("^WLBI|"),
        "relay-ineligible nil owner emitted an authoritative payload: "
            .. tostring(message.text))
end

NexusDB = {
    communityBuilds={},dpsCapture={},
    syncTombstones={
        ["foreign-tomb"]={stamp=301,author="Origin",
            ownerKey="origin@realmy",ownerVerified=true},
    },
}
H.AdmitCatalogV1(NexusDB)
Sync.Init(Codec, {})
H.AdmitCatalogV1(NexusDB)
DPS.Init({}, Sync)
H.sentChatMessages = {}
local _, tombDpsHash = Sync.GetCompatibilityHashes()
assert(Sync.HandleIncoming(table.concat({"WLRQ","Requester-RealmQ",
        "0",tombDpsHash,"c1-foreign-tomb-claim","1.20.0"}, "|"),
        "Requester-RealmQ"),
    "foreign-tomb response-claim fixture was rejected")
for _ = 1, 220 do Sync.OnUpdate(0.2) end
for _, message in ipairs(H.sentChatMessages) do
    assert(not message.text:find("^WLRC|")
            and not message.text:find("^WLBC|")
            and not message.text:find("^WLRD|"),
        "non-owner foreign tomb suppressed an authoritative response")
end

-- Reloaded tombstones are durable authority records too. A canonical-looking
-- local owner flag must not hide conflicting durable or compact provenance and
-- turn that persisted evidence into an outbound delete.
NexusDB = {
    communityBuilds={},dpsCapture={},
    syncTombstones={
        ["tomb-author-conflict"]={stamp=302,author="Other",
            ownerKey="relay@realmx",ownerVerified=true,pending=true},
        ["tomb-claim-conflict"]={stamp=303,author="Relay",
            ownerKey="relay@realmx",ownerVerified=true,pending=true,
            claimedOwnerKey="other@realmx"},
        ["tomb-relay-conflict"]={stamp=304,author="Relay",
            ownerKey="relay@realmx",ownerVerified=true,pending=true,
            relaySender="Other-RealmX"},
        ["tomb-compact-conflict"]={stamp=305,author="Relay",
            ownerKey="relay@realmx",ownerVerified=true,pending=true,
            o="other@realmx"},
    },
}
H.AdmitCatalogV1(NexusDB)
Sync.Init(Codec, {})
H.AdmitCatalogV1(NexusDB)
DPS.Init({}, Sync)
H.sentChatMessages = {}
local _, malformedTombDpsHash = Sync.GetCompatibilityHashes()
assert(Sync.HandleIncoming(table.concat({"WLRQ","Requester-RealmQ",
        "0",malformedTombDpsHash,"c1-malformed-tomb","1.20.0"}, "|"),
        "Requester-RealmQ"),
    "malformed-tomb response fixture was rejected")
for _ = 1, 220 do Sync.OnUpdate(0.2) end
for _, message in ipairs(H.sentChatMessages) do
    for id in pairs(NexusDB.syncTombstones) do
        assert(not tostring(message.text):find("|" .. id .. "|", 1, true),
            "EXPECTED RED: contradictory reloaded tomb regained delete authority: "
                .. id)
    end
end

-- Prepared full-build bytes cannot outlive the catalog record whose verified
-- authority produced them. Mutate the selected ID after revision capture but
-- before admission and prove the old ordinary payload never enters transport.
local Catalog = Nexus.BuildCatalog
local stalePrepared = {
    id="stale-prepared-authority",title="Prepared Ordinary",author="Relay",
    ownerKey="relay@realmx",ownerVerified=true,realm="realmx",isMine=true,
    class="MAGE",postedAt=400,lastModified=400,
    echoes={{spellId=200700,quality=3,stacks=1}},
}
assert(PutTerminal(stalePrepared),
    "stale prepared-build control could not seed its ordinary record")
stalePrepared = assert(Catalog.Get(stalePrepared.id))
local realRecordRevision = Catalog.RecordRevision
local swapped = false
Catalog.RecordRevision = function(id)
    local epoch, revision = realRecordRevision(id)
    if id == stalePrepared.id and not swapped then
        swapped = true
        local private = {}
        for key, value in pairs(stalePrepared) do private[key] = value end
        private.importedSavedBuild = true
        private.serverSlot = 77
        assert(PutTerminal(private),
            "stale prepared-build control could not install its private replacement")
    end
    return epoch, revision
end
local sendingBeforePrepared = Sync.WorkState().sending
local admittedPrepared, preparedWhy = Sync.BroadcastBuild(stalePrepared)
Catalog.RecordRevision = realRecordRevision
assert(swapped and admittedPrepared == false
        and preparedWhy == "stale prepared build"
        and Sync.WorkState().sending == sendingBeforePrepared,
    "prepared ordinary bytes survived a same-ID private authority replacement")
-- The removal is one retained catalog mutation; settle it to its exact
-- terminal ticket instead of treating the pending acknowledgement as removal.
local removedStale, removedStaleWhy, removedStaleTicket =
    Catalog.RemoveOverlay(stalePrepared.id)
if removedStale == nil and removedStaleWhy == "ROOT_MUTATION_PENDING" then
    SettleCatalog()
    assert(type(removedStaleTicket) == "table"
            and removedStaleTicket.state ~= "pending",
        "stale prepared-build removal did not reach a terminal ticket")
    removedStale, removedStaleWhy = removedStaleTicket.committed,
        removedStaleTicket.reason
end
assert(removedStale,
    "stale prepared-build control could not be removed: "
        .. tostring(removedStaleWhy))
assert(Catalog.Get(stalePrepared.id) == nil,
    "stale prepared-build control remained readable after removal")

print("canonical transport owner authority -- OK")
