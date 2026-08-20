-- DPS-to-Community ownership must consume verified canonical record authority.
local H = dofile("tests/harness.lua")
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
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/CommunityBuilds.lua")

local DPS = Nexus.DpsCapture
local Community = Nexus.CommunityBuilds
local Adapter = Nexus.GameAdapter
local now = 70000
time = function() return now end
UnitClass = function() return "Mage", "MAGE" end

local localName, localRealm
UnitName = function() return localName end
GetNormalizedRealmName = function() return localRealm end

local function Reset(name, realm)
    localName, localRealm = name, realm
    NexusDB = {communityBuilds={}, syncTombstones={}, dpsCapture={}}
    DPS.Init(Adapter, nil)
    Community.Init(Adapter, Nexus.Model)
end

local function Wire(player, realm, ownerKey, echoes, stamp, buildId)
    local fingerprint = assert(DPS.GetEchoKey(echoes))
    return {
        v=7, f=fingerprint, h=DPS.GetEchoHash(echoes), e=echoes,
        c="dummy", d=24000000, u=65, t=stamp,
        p=player, k="MAGE", o=ownerKey, r=realm, l=80, b=buildId,
    }
end

local function BoardRow(category, fingerprint, realm)
    for _, row in ipairs(DPS.GetDpsBoard(category)) do
        if row.fingerprint == fingerprint and row.realm == realm then
            return row
        end
    end
end

local function DurableRow(category, fingerprint, realm)
    local capture = NexusDB.dpsCapture or {}
    local store = capture.characterBest and capture.characterBest[category] or {}
    for _, row in pairs(store or {}) do
        if row.fingerprint == fingerprint and row.realm == realm then
            return row
        end
    end
end

local function StoredBuild(id)
    return id and Nexus.BuildCatalog.Get(id) or nil
end

local function ReloadCommunity()
    dofile("ui/CommunityBuilds.lua")
    Community = Nexus.CommunityBuilds
    Community.Init(Adapter, Nexus.Model)
end

local function Detail(id)
    local projection = Nexus.CommunityInternals.Projection.New({
        builds=function() return {}, {} end,
        buildsCurrent=function() return true end,
        loadBuild=function(buildId) return StoredBuild(buildId) end,
        revisionSnapshot=function() return {build=1, dps=1} end,
        dpsBoard=function() return {} end,
        dpsRecord=function() return nil end,
        leaderboard=function() return {} end,
        personalBest=function() return nil end,
    })
    return projection.Detail(id, {
        ownerKey=Nexus.Identity.OwnerKey(localName, localRealm),
        player=Nexus.Identity.PlayerKey(localName),
        isAdmin=false, ownedBySpell={}, detailsAvailable=false,
    })
end

local function AssertNotMineInLibrary(id)
    Nexus.ViewProjections.Reset()
    local rows, summary = Nexus.ViewProjections.Builds({
        scope="mine", currentClassOnly=false, qualifiedOnly=false,
        sortMode="title",
    })
    for _, row in ipairs(rows or {}) do
        assert(row.id ~= id, "unverified build entered the My Builds projection")
    end
    assert((summary and summary.mine or 0) == 0,
        "unverified build incremented the owned projection count")
end

-- A same-short-name packet from another realm is retained as public evidence,
-- but it must never borrow the logged-in character's owner key or actions.
Reset("Twin", "RealmA")
local crossEchoes = {{spellId=720001, quality=3, stacks=1}}
assert(DPS.ReceiveRecord(
    Wire("Twin", "RealmA", "twin@realma", crossEchoes, now),
    "Twin-RealmB"), "same-name cross-realm DPS evidence was not retained")
local crossFingerprint = DPS.GetEchoKey(crossEchoes)
local crossRow = assert(BoardRow("dummy", crossFingerprint, "realmb"),
    "cross-realm DPS evidence was not exposed with actual transport provenance")
assert(crossRow.buildId == nil and crossRow.build == nil,
    "unverified cross-realm evidence exposed a public build association")
local crossDurable = assert(DurableRow("dummy", crossFingerprint, "realmb"),
    "cross-realm DPS evidence was not retained durably")
local crossId = assert(crossDurable.buildId,
    "cross-realm evidence lost its non-authoritative promotion page")
local crossBuild = assert(StoredBuild(crossId),
    "cross-realm Community page was not stored")
assert(crossRow.ownerVerified == false and crossRow.ownerKey == nil,
    "DPS ingress regained authority before the Community boundary")
assert(crossBuild.ownerVerified == false and crossBuild.ownerKey == nil
        and crossBuild.claimedOwnerKey == "twin@realmb"
        and crossBuild.isMine ~= true,
    "same-name cross-realm evidence borrowed local Community ownership")
assert(crossBuild.loadoutAvailable == true and #crossBuild.echoes == 1,
    "unverified Community evidence was hidden instead of kept copyable")
assert(not Community.IsOwnBuild(crossId),
    "unverified cross-realm Community evidence exposed owner actions")
local edited, editWhy = Community.EditBuild(crossId, "Forged edit", "no")
assert(not edited and editWhy == "not your build",
    "unverified cross-realm Community evidence passed edit authority")
local retryable, retryWhy = Community.CanRetryShare(crossId)
assert(not retryable and retryWhy == "not your build",
    "unverified cross-realm Community evidence passed retry authority")
local replaced, replaceWhy = Community.UpdateFromWishlist(crossId)
assert(not replaced and replaceWhy == "not your build",
    "unverified cross-realm Community evidence passed Wishlist authority")
local deleted, deleteWhy = Community.DeleteBuild(crossId)
assert(not deleted and deleteWhy == "not your build",
    "unverified cross-realm Community evidence passed delete authority")
local crossDetail = assert(Detail(crossId))
assert(not crossDetail.mine and not crossDetail.showEdit
        and not crossDetail.showDelete and not crossDetail.canSaveLink,
    "unverified cross-realm evidence exposed owner-only detail controls")
AssertNotMineInLibrary(crossId)

-- Persisted canonical-looking metadata is still not authority when its flag is
-- explicitly false, even if an older producer also left isMine=true.
local staleEchoes = {{spellId=720003, quality=1, stacks=1}}
local staleFingerprint = DPS.GetEchoKey(staleEchoes)
assert(Nexus.BuildCatalog.Put({
    id="stale-local-looking", title="Stale", description="evidence",
    author="Twin", ownerKey="twin@realma", ownerVerified=false,
    isMine=true, autoDps=true, class="MAGE", echoes=staleEchoes,
    fingerprint=staleFingerprint, fingerprintHash=DPS.GetEchoHash(staleEchoes),
    echoCount=1, loadoutAvailable=true, needsFullBuild=false,
    postedAt=1, lastModified=1,
}), "stale canonical-looking control was not stored")
assert(not Community.IsOwnBuild("stale-local-looking"),
    "explicitly unverified canonical metadata regained controller ownership")
local staleDetail = assert(Detail("stale-local-looking"))
assert(not staleDetail.mine and not staleDetail.showEdit
        and not staleDetail.showDelete and not staleDetail.canSaveLink,
    "explicitly unverified metadata regained projection ownership")
assert(not Community.IsOwnBuild({author="Other", ownerKey="twin@realma",
        ownerVerified=true, isMine=true}),
    "author-incoherent verified metadata gained local authority")
assert(not Community.IsOwnBuild({author="Twin", ownerKey="twin@unknown",
        ownerVerified=true, isMine=true}),
    "unknown-realm verified metadata gained local authority")
assert(not Community.IsOwnBuild({author="Twin", ownerKey="malformed",
        isMine=true}),
    "malformed legacy owner metadata fell through to local authority")
assert(not Community.IsOwnBuild({author="Twin", ownerKey="twin@realma",
        realm="RealmB", isMine=true}),
    "cross-realm legacy metadata fell through to local authority")
assert(not Community.IsOwnBuild({author="Twin", ownerKey="twin@realma",
        ownerVerified=true, claimedOwnerKey="twin@realmb", isMine=true}),
    "verified metadata with a conflicting retained claim gained authority")
assert(not Community.IsOwnBuild({author="Twin", ownerKey="twin@realma",
        ownerVerified=true, relaySender="Relay-RealmB", isMine=true}),
    "verified relay provenance gained local authority")
assert(not Community.IsOwnBuild({author="Twin-RealmB",
        ownerKey="twin@realma", ownerVerified=true, isMine=true}),
    "realm-qualified author conflict collapsed into local authority")
local nonStringRealm = {
    author="Twin", ownerKey="twin@123", ownerVerified=true,
    realm=123, isMine=true,
}
assert(Nexus.Identity.VerifiedOwnerKey(nonStringRealm) == nil
        and not Nexus.Identity.LocalOwnsRecord(nonStringRealm, "twin@123"),
    "non-string durable realm metadata gained canonical owner authority")
for _, mixed in ipairs({
    {author="Twin", ownerKey="twin@realma", o="twin@realmb",
        ownerVerified=true, isMine=true},
    {author="Twin", p="Other", ownerKey="twin@realma",
        ownerVerified=true, isMine=true},
    {author="Twin", player="Other", ownerKey="twin@realma",
        ownerVerified=true, isMine=true},
    {author="Twin", realm="RealmA", r="RealmB",
        ownerKey="twin@realma", ownerVerified=true, isMine=true},
    {author="Twin", ownerKey="twin@realma", o="twin@realmb",
        isMine=true},
    {author="Twin", p="Other", ownerKey="twin@realma", isMine=true},
    {author="Twin", player="Other", ownerKey="twin@realma", isMine=true},
    {author="Twin", realm="RealmA", r="RealmB",
        ownerKey="twin@realma", isMine=true},
    {author="Twin", ownerKey="twin@realmb", o="twin@realma",
        ownerVerified=true, isMine=true},
    {author="Other", p="Twin", ownerKey="twin@realma",
        ownerVerified=true, isMine=true},
    {author="Twin", realm="RealmB", r="RealmA",
        ownerKey="twin@realma", ownerVerified=true, isMine=true},
    {author="Twin", a="Other-RealmX", ownerKey="twin@realma",
        ownerVerified=true, isMine=true},
}) do
    assert(not Community.IsOwnBuild(mixed),
        "mixed compact/durable identity aliases gained local authority")
end

-- My Builds consumes catalog summaries, so every field used by the shared
-- authority policy must survive that projection.
for _, row in ipairs({
    {
        id="summary-provenance", title="Claimed summary", author="Twin",
        ownerKey="twin@realma", claimedOwnerKey="twin@realmb",
        relaySender="Relay-RealmB", isMine=true, class="MAGE",
        echoes={{spellId=720005, quality=2, stacks=1}},
        postedAt=1, lastModified=1,
    },
    {
        id="summary-realm", title="Conflicting realm", author="Twin",
        ownerKey="twin@realma", ownerVerified=true, realm="RealmB",
        isMine=true, class="MAGE",
        echoes={{spellId=720006, quality=2, stacks=1}},
        postedAt=1, lastModified=1,
    },
    {
        id="summary-alias-owner", title="Alias owner", author="Twin",
        ownerKey="twin@realma", o="twin@realmb", ownerVerified=true,
        isMine=true, class="MAGE",
        echoes={{spellId=720007, quality=2, stacks=1}},
        postedAt=1, lastModified=1,
    },
    {
        id="summary-alias-p", title="Compact player alias", author="Twin",
        ownerKey="twin@realma", p="Other",
        ownerVerified=true, isMine=true, class="MAGE",
        echoes={{spellId=720008, quality=2, stacks=1}},
        postedAt=1, lastModified=1,
    },
    {
        id="summary-alias-player", title="Durable player alias", author="Twin",
        ownerKey="twin@realma", player="Other",
        ownerVerified=true, isMine=true, class="MAGE",
        echoes={{spellId=720018, quality=2, stacks=1}},
        postedAt=1, lastModified=1,
    },
    {
        id="summary-alias-realm", title="Alias realm", author="Twin",
        ownerKey="twin@realma", realm="RealmA", r="RealmB",
        ownerVerified=true, isMine=true, class="MAGE",
        echoes={{spellId=720009, quality=2, stacks=1}},
        postedAt=1, lastModified=1,
    },
    {
        id="summary-legacy-alias", title="Legacy compact alias", author="Twin",
        ownerKey="twin@realma", p="Twin", isMine=true, class="MAGE",
        echoes={{spellId=720019, quality=2, stacks=1}},
        postedAt=1, lastModified=1,
    },
    {
        id="summary-inverse-owner", title="Inverse owner aliases", author="Twin",
        ownerKey="twin@realmb", o="twin@realma", ownerVerified=true,
        isMine=true, class="MAGE",
        echoes={{spellId=720020, quality=2, stacks=1}},
        postedAt=1, lastModified=1,
    },
    {
        id="summary-alias-author", title="Compact author alias", author="Twin",
        a="Other-RealmX", ownerKey="twin@realma", ownerVerified=true,
        isMine=true, class="MAGE",
        echoes={{spellId=720022, quality=2, stacks=1}},
        postedAt=1, lastModified=1,
    },
}) do
    assert(Nexus.BuildCatalog.Put(row), "summary authority control was not stored")
    assert(not Community.IsOwnBuild(row.id),
        "full catalog row unexpectedly granted summary-control authority")
end
AssertNotMineInLibrary("summary-provenance")
AssertNotMineInLibrary("summary-realm")
AssertNotMineInLibrary("summary-alias-owner")
AssertNotMineInLibrary("summary-alias-p")
AssertNotMineInLibrary("summary-alias-player")
AssertNotMineInLibrary("summary-alias-realm")
AssertNotMineInLibrary("summary-legacy-alias")
AssertNotMineInLibrary("summary-inverse-owner")
AssertNotMineInLibrary("summary-alias-author")

-- The DPS producer must not stamp verified authority before the durable
-- Community consumer gets a chance to reject contradictory identity.
local qualifiedEchoes = {{spellId=720010, quality=2, stacks=1}}
local qualifiedWire = Wire(
    "Twin-RealmB", nil, "twin@realma", qualifiedEchoes, now)
assert(not DPS.HasCanonicalOwnerIdentity(qualifiedWire),
    "DPS canonical identity collapsed a realm-qualified player conflict")
assert(DPS.ReceiveRecord(qualifiedWire, "Twin-RealmA"),
    "qualified-author conflict was not retained as ambient evidence")
local qualifiedRow = assert(BoardRow(
    "dummy", DPS.GetEchoKey(qualifiedEchoes), "realma"))
assert(qualifiedRow.buildId == nil and qualifiedRow.build == nil,
    "qualified-author conflict exposed a public build association")
local qualifiedDurable = assert(DurableRow(
    "dummy", DPS.GetEchoKey(qualifiedEchoes), "realma"),
    "qualified-author conflict was not retained durably")
local qualifiedId = assert(qualifiedDurable.buildId,
    "qualified-author conflict lost its non-authoritative promotion page")
local qualifiedBuild = assert(StoredBuild(qualifiedId),
    "qualified-author ambient Community page was not stored")
assert(qualifiedRow.ownerVerified == false and qualifiedRow.ownerKey == nil
        and qualifiedBuild.ownerVerified == false
            and qualifiedBuild.ownerKey == nil
            and qualifiedBuild.isMine ~= true
            and not Community.IsOwnBuild(qualifiedBuild),
    "qualified-author conflict was stamped as verified Community authority")
qualifiedBuild.o = "twin@realmb"
qualifiedBuild.p = "Other"
qualifiedBuild.r = "RealmB"
qualifiedBuild.player = "Other"
assert(Nexus.BuildCatalog.Put(qualifiedBuild),
    "explicit promotion alias control was not persisted")

-- Later exact evidence may promote the same retained page, but it must replace
-- every stale identity component rather than only flipping the verified flag.
now = now + 1
local exactQualified = Wire(
    "Twin-RealmA", nil, "twin@realma", qualifiedEchoes, now,
    qualifiedId)
assert(DPS.HasCanonicalOwnerIdentity(exactQualified),
    "qualified exact DPS tuple was rejected as incoherent")
assert(DPS.ReceiveRecord(exactQualified, "Twin-RealmA"),
    "qualified exact owner could not promote retained ambient evidence")
local promotedQualified = assert(StoredBuild(qualifiedId),
    "qualified exact promotion replaced the stable Community identity")
assert(promotedQualified.ownerVerified == true
        and promotedQualified.ownerKey == "twin@realma"
        and promotedQualified.author == "Twin-RealmA"
        and promotedQualified.realm == "realma"
        and promotedQualified.player == nil
        and promotedQualified.o == nil and promotedQualified.p == nil
        and promotedQualified.r == nil
        and promotedQualified.isMine == true
        and Nexus.Identity.VerifiedOwnerKey(promotedQualified)
            == "twin@realma"
        and Community.IsOwnBuild(promotedQualified),
    "qualified exact promotion retained contradictory identity metadata")

-- Fingerprint-based promotion follows the same atomic identity normalization
-- as the explicit build-ID path.
local reuseEchoes = {{spellId=720021, quality=2, stacks=1}}
local reuseId, reuseBuild = Community.EnsureDpsBuildForEchoes(
    reuseEchoes, "dummy", {
        player="Twin", class="MAGE", realm="RealmA",
        ownerVerified=false, relaySender="Twin-RealmA",
    })
assert(reuseId and reuseBuild and reuseBuild.ownerVerified == false,
    "fingerprint promotion control was not retained as ambient evidence")
reuseBuild.o = "twin@realmb"
reuseBuild.p = "Twin"
reuseBuild.r = "RealmB"
reuseBuild.a = "Other-RealmX"
assert(Nexus.BuildCatalog.Put(reuseBuild),
    "fingerprint promotion alias control was not persisted")
local reusedId, promotedReuse = Community.EnsureDpsBuildForEchoes(
    reuseEchoes, "dummy", {
        player="Twin", class="MAGE", ownerKey="twin@realma",
        realm="RealmA", ownerVerified=true,
    })
assert(reusedId == reuseId and promotedReuse
        and promotedReuse.ownerVerified == true
        and promotedReuse.ownerKey == "twin@realma"
        and promotedReuse.player == nil
        and promotedReuse.a == nil and promotedReuse.o == nil
        and promotedReuse.p == nil
        and promotedReuse.r == nil
        and Nexus.Identity.VerifiedOwnerKey(promotedReuse) == "twin@realma"
        and Community.IsOwnBuild(promotedReuse),
    "fingerprint exact promotion retained contradictory identity metadata")

for index, provenance in ipairs({
    {relaySender="Relay-RealmB"},
    {claimedOwnerKey="twin@realmb"},
}) do
    local echoes = {{spellId=720010 + index, quality=2, stacks=1}}
    local record = {
        player="Twin", class="MAGE", ownerKey="twin@realma",
        realm="RealmA", ownerVerified=true,
    }
    for key, value in pairs(provenance) do record[key] = value end
    assert(DPS.HasCanonicalOwnerIdentity(record),
        "authority provenance incorrectly invalidated a coherent DPS tuple")
    assert(DPS.VerifiedOwnerKey(record) == nil,
        "retained DPS provenance remained verified owner authority")
    local id, build = Community.EnsureDpsBuildForEchoes(
        echoes, "dummy", record)
    assert(id and build and build.ownerVerified == false
            and build.ownerKey == nil and build.isMine ~= true
            and not Community.IsOwnBuild(build),
        "contradictory DPS provenance was laundered into local ownership")
end

-- A verified RealmA record cannot promote the page retained from RealmB.
local wrongId = Community.EnsureDpsBuildForEchoes(crossEchoes, "dummy", {
    player="Twin", class="MAGE", ownerKey="twin@realma", realm="realma",
    ownerVerified=true, buildId=crossId,
})
assert(wrongId == nil and StoredBuild(crossId).ownerVerified == false,
    "wrong-realm verified evidence promoted the retained Community page")

-- Reload cannot recompute ownership from the matching short display name.
ReloadCommunity()
assert(not Community.IsOwnBuild(crossId)
        and StoredBuild(crossId).ownerKey == nil,
    "reload converted cross-realm presentation identity into ownership")

-- The exact RealmB owner may later promote only its retained evidence. It is
-- still remote to the RealmA viewer and therefore remains non-editable here.
now = now + 1
assert(DPS.ReceiveRecord(
    Wire("Twin", "RealmB", "twin@realmb", crossEchoes, now),
    "Twin-RealmB"), "exact owner could not promote retained DPS evidence")
local promotedCross = assert(StoredBuild(crossId),
    "exact owner promotion replaced the stable Community identity")
assert(promotedCross.ownerVerified == true
        and promotedCross.ownerKey == "twin@realmb"
        and promotedCross.claimedOwnerKey == nil
        and promotedCross.isMine ~= true
        and not Community.IsOwnBuild(promotedCross),
    "exact remote promotion acquired the RealmA viewer's owner actions")

-- Realm-less local-looking evidence is also non-authoritative. A later exact
-- transport receipt may promote the same evidence deterministically.
Reset("Solo", "RealmA")
now = now + 1
local soloEchoes = {{spellId=720002, quality=2, stacks=2}}
local soloFingerprint = DPS.GetEchoKey(soloEchoes)
local soloWire = Wire("Solo", nil, nil, soloEchoes, now)
soloWire.k = "WARLOCK"
assert(DPS.ReceiveRecord(soloWire, "Solo"),
    "realm-less DPS compatibility evidence was not retained")
local soloRow = assert(BoardRow("dummy", soloFingerprint, nil),
    "realm-less DPS evidence was not retained as ambiguous evidence")
assert(soloRow.buildId == nil and soloRow.build == nil,
    "realm-less DPS evidence exposed a public build association")
local soloDurable = assert(DurableRow("dummy", soloFingerprint, nil),
    "realm-less DPS evidence was not retained durably")
local soloId = assert(soloDurable.buildId,
    "realm-less evidence lost its non-authoritative promotion page")
local soloBuild = assert(StoredBuild(soloId))
assert(soloBuild.ownerVerified == false and soloBuild.ownerKey == nil
        and soloBuild.isMine ~= true and not Community.IsOwnBuild(soloBuild),
    "realm-less evidence acquired durable local Community ownership")

soloWire.o = "solo@realma"
soloWire.r = "RealmA"
soloWire.k = "MAGE"
assert(DPS.ReceiveRecord(soloWire, "Solo-RealmA"),
    "exact local transport could not promote realm-less evidence")
local promotedSolo = assert(StoredBuild(soloId),
    "exact local promotion replaced the stable Community identity")
assert(promotedSolo.ownerVerified == true
        and promotedSolo.ownerKey == "solo@realma"
        and promotedSolo.claimedOwnerKey == nil
        and promotedSolo.class == "MAGE"
        and promotedSolo.title == "Mage Record Loadout"
        and promotedSolo.isMine == true
        and Community.IsOwnBuild(promotedSolo),
    "exact local authority did not restore legitimate owner actions")

local claimlessId = Community.EnsureDpsBuildForEchoes(
    soloEchoes, "dummy", {player="Solo", class="WARLOCK"})
local afterClaimless = assert(StoredBuild(soloId))
assert(claimlessId == nil and afterClaimless.ownerVerified == true
        and afterClaimless.ownerKey == "solo@realma"
        and afterClaimless.class == "MAGE"
        and afterClaimless.title == "Mage Record Loadout",
    "claimless realm-less evidence overwrote a verified Community page")

local unchangedId = Community.EnsureDpsBuildForEchoes(
    soloEchoes, "dummy", {
        player="Solo", class="WARLOCK", ownerKey="solo@realma",
        realm="realma", ownerVerified=false,
    })
local unchangedSolo = assert(StoredBuild(soloId))
assert(unchangedId == soloId and unchangedSolo.class == "MAGE"
        and unchangedSolo.ownerVerified == true
        and unchangedSolo.ownerKey == "solo@realma",
    "unverified metadata mutated or replaced a verified local auto page")

ReloadCommunity()
assert(Community.IsOwnBuild(soloId),
    "verified exact local ownership did not survive reload")

-- A canonical-looking key without a positive verification decision remains a
-- claim only, even when the player and current character names match exactly.
Reset("Nilowner", "RealmA")
local nilEchoes = {{spellId=720004, quality=2, stacks=1}}
local nilId, nilBuild = Community.EnsureDpsBuildForEchoes(
    nilEchoes, "dummy", {
        player="Nilowner", class="MAGE", ownerKey="nilowner@realma",
        realm="realma",
    })
assert(nilId and nilBuild and nilBuild.ownerVerified == false
        and nilBuild.ownerKey == nil
        and nilBuild.claimedOwnerKey == "nilowner@realma"
        and nilBuild.isMine ~= true
        and not Community.IsOwnBuild(nilBuild),
    "nil verification was treated as canonical local Community authority")

-- Every DPS egress owner consumes the same provenance-aware authority verdict.
-- Neither direct sends nor derived response candidates may erase retained
-- claim/relay evidence and re-emit it as verified owner traffic.
Reset("Twin", "RealmA")
Nexus.Sync.Init(Nexus.Codec, Adapter)
local outboundEchoes = {{spellId=720030, quality=2, stacks=1}}
local outboundFingerprint = DPS.GetEchoKey(outboundEchoes)
local outboundBase = {
    protocolVersion=7, fingerprint=outboundFingerprint,
    loadoutHash=DPS.GetEchoHash(outboundEchoes), echoes=outboundEchoes,
    category="dummy", dps=29000000, duration=65, ts=now + 1,
    player="Twin", level=80, class="MAGE", ownerKey="twin@realma",
    realm="realma", ownerVerified=true, buildId="provenance-build",
}
for _, provenance in ipairs({
    {relaySender="Relay-RealmB"},
    {claimedOwnerKey="twin@realmb"},
}) do
    local record = {}
    for key, value in pairs(outboundBase) do record[key] = value end
    for key, value in pairs(provenance) do record[key] = value end
    assert(DPS.VerifiedOwnerKey(record) == nil,
        "outbound provenance control unexpectedly retained verified authority")
    local sent, why = Nexus.Sync.BroadcastDpsRecord(record)
    assert(sent == false and why == "owner_sender",
        "DPS direct egress stripped retained provenance into owner authority")
end

local storedProvenance = {}
for key, value in pairs(outboundBase) do storedProvenance[key] = value end
storedProvenance.relaySender = "Relay-RealmB"
NexusDB.dpsCapture.characterBest.dummy["twin@realma"] = storedProvenance
local bucket = assert(DPS.SyncBucket("dummy", "Twin"))
assert(not DPS.LocalOwnsDpsBucket(bucket),
    "retained DPS provenance regained local bucket ownership")
assert(Nexus.BuildCatalog.Put({
    id="provenance-build", title="Provenance", author="Twin",
    ownerKey="twin@realma", ownerVerified=true, class="MAGE",
    echoes=outboundEchoes, fingerprint=outboundFingerprint,
    fingerprintHash=DPS.GetEchoHash(outboundEchoes),
    postedAt=1, lastModified=1,
}), "DPS provenance build control was not stored")
local copied = 0
DPS.Init(Adapter, {
    BroadcastDpsRecord=function()
        copied = copied + 1
        return true
    end,
})
assert(not DPS.BroadcastBestForBuild("provenance-build") and copied == 0,
    "build-best egress stripped retained DPS provenance")
local offered, complete, _, _, _, _, _, claimSafe =
    DPS.BroadcastAllBuildBests("0", bucket, {}, 100)
assert(offered == 0 and complete == true and copied == 0
        and claimSafe == false,
    string.format("response candidate egress stripped retained DPS provenance: offered=%s complete=%s copied=%s claimSafe=%s",
        tostring(offered), tostring(complete), tostring(copied),
        tostring(claimSafe)))

-- Community, direct Sync egress, response egress, and deletion must consume
-- the same durable-build authority verdict. Wire encoders cannot be allowed to
-- erase a rejected alias or provenance conflict into a clean owner assertion.
Reset("Twin", "RealmA")
local buildEchoes = {{spellId=720040, quality=2, stacks=1}}
local function BuildVariant(id, changes)
    local build = {
        id=id, title="Authority " .. id, author="Twin",
        ownerKey="twin@realma", ownerVerified=true, realm="realma",
        isMine=true, class="MAGE", echoes=buildEchoes,
        postedAt=1, lastModified=1,
    }
    for key, value in pairs(changes or {}) do build[key] = value end
    return build
end

local invalidBuilds = {
    BuildVariant("authority-relay", {relaySender="Relay-RealmB"}),
    BuildVariant("authority-claim", {claimedOwnerKey="twin@realmb"}),
    BuildVariant("authority-o", {o="twin@realmb"}),
    BuildVariant("authority-p", {p="Other"}),
    BuildVariant("authority-r", {r="realmb"}),
    BuildVariant("authority-a", {a="Other-RealmX"}),
    BuildVariant("authority-player", {player="Other"}),
    BuildVariant("authority-realm", {realm="realmb"}),
    BuildVariant("authority-realm-type", {realm=123}),
}
for _, build in ipairs(invalidBuilds) do
    assert(Nexus.Identity.VerifiedOwnerKey(build) == nil
            and not Nexus.Identity.LocalOwnsRecord(build, "twin@realma")
            and not Community.IsOwnBuild(build),
        "invalid build authority control unexpectedly verified: " .. build.id)
    Nexus.Sync.Init(Nexus.Codec, {})
    local summarized, summaryWhy = Nexus.Sync.BroadcastBuildSummary(build)
    assert(summarized == false and summaryWhy == "relay unauthorized",
        "summary egress laundered rejected build authority: " .. build.id)
    local sent, sendWhy = Nexus.Sync.BroadcastBuild(build)
    assert(sent == false and sendWhy == "relay unauthorized",
        "full-build egress laundered rejected build authority: " .. build.id)
    assert(not Nexus.Sync.BroadcastDelete(build)
            and NexusDB.syncTombstones[build.id] == nil,
        "delete egress laundered rejected build authority: " .. build.id)

    assert(Nexus.BuildCatalog.Put(build),
        "response authority control was not stored: " .. build.id)
    Nexus.Sync.Init(Nexus.Codec, {})
    H.sentChatMessages = {}
    assert(Nexus.Sync.HandleIncoming(
        "WLLQ|Requester-RealmQ|" .. build.id, "Requester-RealmQ"),
        "response authority request was rejected: " .. build.id)
    for _ = 1, 180 do Nexus.Sync.OnUpdate(0.2) end
    for _, message in ipairs(H.sentChatMessages) do
        local wire = tostring(message.text or ""):gsub("||", "|")
        assert(not wire:find(build.id, 1, true),
            "response egress laundered rejected build authority: " .. build.id)
    end
end

local verifiedRemote = BuildVariant("authority-remote", {
    author="Remote-RealmB", ownerKey="remote@realmb",
    realm="realmb", isMine=false,
})
assert(Nexus.Identity.VerifiedOwnerKey(verifiedRemote) == "remote@realmb",
    "verified remote build control lost canonical authority")
Nexus.Sync.Init(Nexus.Codec, {})
assert(Nexus.Sync.BroadcastBuildSummary(verifiedRemote)
        and Nexus.Sync.BroadcastBuild(verifiedRemote)
        and not Nexus.Sync.BroadcastDelete(verifiedRemote),
    "coherent verified remote build lost relay-only compatibility")

local legacyLocal = BuildVariant("authority-local-legacy", {})
legacyLocal.ownerVerified = nil
assert(Nexus.BuildCatalog.Put(legacyLocal),
    "coherent local legacy evidence was not retained")
assert(not Nexus.Identity.LocalOwnsRecord(legacyLocal, "twin@realma")
        and not Community.IsOwnBuild(legacyLocal.id),
    "EXPECTED RED: unverified ordinary legacy evidence gained local authority")
local legacyEdited, legacyEditWhy = Community.EditBuild(
    legacyLocal.id, "Legacy edit", "blocked")
local legacyUpdated, legacyUpdateWhy = Community.UpdateFromWishlist(
    legacyLocal.id)
local legacyDeleted, legacyDeleteWhy = Community.DeleteBuild(legacyLocal.id)
assert(not legacyEdited and legacyEditWhy == "not your build"
        and not legacyUpdated and legacyUpdateWhy == "not your build"
        and not legacyDeleted and legacyDeleteWhy == "not your build"
        and Nexus.BuildCatalog.Get(legacyLocal.id) ~= nil,
    "EXPECTED RED: unverified ordinary legacy evidence mutated or associated")
Nexus.Sync.Init(Nexus.Codec, {})
local legacySummary, legacySummaryWhy =
    Nexus.Sync.BroadcastBuildSummary(legacyLocal)
local legacyFull, legacyFullWhy = Nexus.Sync.BroadcastBuild(legacyLocal)
assert(not legacySummary and legacySummaryWhy == "relay unauthorized"
        and not legacyFull and legacyFullWhy == "relay unauthorized"
        and not Nexus.Sync.BroadcastDelete(legacyLocal)
        and NexusDB.syncTombstones[legacyLocal.id] == nil,
    "EXPECTED RED: unverified ordinary legacy evidence relayed or tombstoned")

print("Community owner authority -- OK")
