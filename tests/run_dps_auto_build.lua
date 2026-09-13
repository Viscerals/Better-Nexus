-- Personal-best workflow: capture -> exact loadout -> auto build -> single public record.
--
-- Legacy-to-bundle cutover observation repoint (MASTER-RC-001, architecture
-- 3b5de54f). State machine line 394 gives the exact PR #68 payload locations
-- "No Package B writer | Legacy admission only | Preserved legacy input when
-- the bundle is absent. Never used as fallback after bundle occupancy", and
-- line 4849 (RAW-01) requires "one complete `authorityBundle` pointer is the
-- sole durable payload write ... legacy payload locations are read-only
-- inputs". This fixture picked the automatic build the capture had just
-- created by enumerating `NexusDB.communityBuilds`; after the cutover a
-- runtime-created build never appears there by construction. The row is
-- therefore selected from the durable bundle payload through
-- `H.DurableBuilds()`, and the same row is additionally required to be the one
-- the public read seam serves. The behaviour under test is unchanged -- one
-- automatic shareable build with a deterministic `dps-` id, dual-written exact
-- evidence, one broadcast, no bloat on a lower pull -- and the preserved
-- legacy input is now additionally asserted to keep its table identity and to
-- take no write.
local H = dofile("tests/harness.lua")
local S = dofile("tests/catalog_authority_support.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
dofile("data/DefaultProfile.lua"); dofile("logic/Model.lua"); dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua"); dofile("logic/Policy.lua"); dofile("core/Store.lua")
dofile("core/GameAdapter.lua"); dofile("ui/CommunityBuilds.lua")

local DPS = Nexus.DpsCapture
local Adapter = Nexus.GameAdapter
local CB = Nexus.CommunityBuilds
local clock, wall = 1000, 50000
GetTime=function() return clock end; time=function() wall=wall+1 return wall end
UnitName=function() return "Recordmage" end
UnitLevel=function() return 80 end
UnitClass=function() return "Mage", "MAGE" end
local stubDps=24000000
Details={GetCurrentCombat=function() return {GetActor=function() return {total=stubDps*30,Tempo=function() return 30 end} end} end}
DETAILS_ATTRIBUTE_DAMAGE=1
UnitExists=function(u) return u=="target" end
UnitGUID=function(u) return u=="target" and "Creature-0-1-0-1-36476-ABC" or nil end
UnitName=function(unit) if unit=="player" then return "Recordmage" elseif unit=="target" then return "Training Dummy" end end

NexusDB={communityBuilds={},syncTombstones={},dpsCapture={}}
local legacyBuilds=NexusDB.communityBuilds
-- Line 394: the legacy payload location is preserved input, never a Package B
-- write target. Seeded empty here, it must stay the same empty table.
local function legacyUntouched(what)
    local n=0; for _ in pairs(rawget(NexusDB,"communityBuilds") or {}) do n=n+1 end
    assert(rawget(NexusDB,"communityBuilds")==legacyBuilds and n==0,
        "Package B wrote a legacy payload location ("..what..")")
end
H.playerLevel=5
H.wishlist={name="Record Set",class="MAGE",echoes={{spellId=200100,quality=3,stacks=2},{spellId=200101,quality=3,stacks=1}}}
H.granted={A={{spellId=200100,stack=2,maxStack=2,quality=3}},B={{spellId=200101,stack=1,maxStack=1,quality=3}}}
H.FireEvent("SPELLS_CHANGED"); H.FireEvent("PLAYER_ENTERING_WORLD"); H.Advance(2)
local sent={}
local sync={BroadcastDpsRecord=function(r) sent[#sent+1]=r return true end,BroadcastBuild=function() return true end}
-- MASTER-RC-001 (architecture 1207-1211): Sync.Init and DpsCapture.Init no
-- longer admit the catalog root as a side effect. The same admission is
-- performed explicitly here, before the call, because the removed side
-- effect ran inside Init ahead of Init's own dependent steps. No assertion
-- or expected value in this fixture is changed.
H.AdmitCatalogV1(NexusDB)
DPS.Init(Adapter,sync)

DPS.OnCombatStart(); clock=clock+35; DPS.OnUpdate(10); DPS.OnCombatEnd()
-- MASTER-W2-004: the automatic page is one retained catalog mutation that
-- completes through the record's terminal callback. Settle it through the
-- public scheduler seam before any durable, served, or broadcast assertion.
S.PumpCatalogToIdle("automatic build admission")
local count, buildId, build=0
for id,b in pairs(H.DurableBuilds()) do count=count+1; buildId=id; build=b end
assert(count==1 and build and build.autoDps, "a new exact loadout should create one automatic shareable build")
assert(buildId:find("^dps%-"), "automatic build id should be deterministic")
legacyUntouched("automatic build creation")
local servedAuto=Nexus.BuildCatalog.Get(buildId)
assert(servedAuto and servedAuto.autoDps and servedAuto.fingerprint==build.fingerprint,
    "the durable automatic build is not the record the public seam serves")
local fp=DPS.GetEchoKey(build.echoes)
-- Same cutover repoint as the build count above, applied to the evidence
-- payload location. State machine line 394 gives the exact PR #68
-- `loadoutEvidence` location no Package B writer and forbids it as a fallback
-- after bundle occupancy; RAW-01 (line 4849) makes one complete
-- `authorityBundle` pointer the sole durable payload write. The dual-write the
-- test proves is unchanged -- the automatic page still carries an exact
-- `evidenceKey` and that key still resolves in the durable evidence pool --
-- only the pool's location moved into the bundle.
local durableEvidence = H.DurablePayload("loadoutEvidence")
assert(build.evidenceKey and type(durableEvidence) == "table"
    and type(durableEvidence.entries) == "table"
    and durableEvidence.entries[build.evidenceKey],
    "automatic page did not dual-write exact evidence")
assert(rawget(NexusDB, "loadoutEvidence") == nil,
    "Package B wrote the legacy evidence payload location")
assert(NexusDB.dpsCapture.personalBest[fp].dummy.evidenceKey
    and NexusDB.dpsCapture.characterBest.dummy["recordmage@ebonhold"].evidenceKey,
    "personal/public DPS rows did not dual-write exact evidence")
local lb=DPS.GetLeaderboard(buildId,"dummy")
assert(#lb==1 and lb[1].dps==24000000 and lb[1].player=="Recordmage", "captured personal best should become the public build record")
assert(#sent==1 and sent[1].fingerprint==DPS.GetEchoKey(build.echoes), "the exact record should be broadcast once")

-- Lower pull: no new build, no public update, no additional broadcast.
stubDps=20000000; DPS.OnCombatStart(); clock=clock+35; DPS.OnUpdate(10); DPS.OnCombatEnd()
S.PumpCatalogToIdle("lower pull catalog work")
local n=0; for _ in pairs(H.DurableBuilds()) do n=n+1 end
assert(n==1 and DPS.GetLeaderboard(buildId,"dummy")[1].dps==24000000 and #sent==1, "lower pull must change nothing")
legacyUntouched("lower pull")

-- Higher pull: same build, replacement record.
stubDps=26000000; DPS.OnCombatStart(); clock=clock+35; DPS.OnUpdate(10); DPS.OnCombatEnd()
S.PumpCatalogToIdle("higher pull catalog work")
assert(DPS.GetLeaderboard(buildId,"dummy")[1].dps==26000000 and #sent==2, "higher pull should replace and rebroadcast the same build record")

-- Higher remote record replaces; lower stale data is rejected.
local echoes=build.echoes
assert(DPS.ReceiveRecord({v=3,f=fp,e=echoes,c="dummy",d=27000000,u=65,t=60000,p="Othermage",k="MAGE",l=80,b=buildId}), "higher remote record should be accepted")
S.PumpCatalogToIdle("higher remote record catalog work")
assert(DPS.ReceiveRecord({v=3,f=fp,e=echoes,c="dummy",d=25000000,u=65,t=60001,p="Oldmage",k="MAGE",l=80,b=buildId}), "a different character should keep its own best entry")
S.PumpCatalogToIdle("second character record catalog work")
assert(not DPS.ReceiveRecord({v=3,f=fp,e=echoes,c="dummy",d=24000000,u=65,t=60002,p="Oldmage",k="MAGE",l=80,b=buildId}), "a lower record for the same character should be rejected")
assert(DPS.GetLeaderboard(buildId,"dummy")[1].player=="Othermage", "highest exact-loadout holder should remain authoritative")

-- A current-character pull may share an exact fingerprint with another
-- verified owner. The content match is useful for display, but it cannot bind
-- this character's durable DPS row to that foreign Community identity.
local collisionEchoes={
    {spellId=200110,quality=3,stacks=1},
}
H.wishlist={name="Collision Set",class="MAGE",echoes=collisionEchoes}
H.granted={
    A={{spellId=200110,stack=1,maxStack=1,quality=3}},
    B={},
}
H.FireEvent("SPELLS_CHANGED"); H.Advance(2)
local collisionFp=DPS.GetEchoKey(collisionEchoes)
local foreignId="foreign-exact-owner"
assert(S.CatalogMutation(function()
    return Nexus.BuildCatalog.Put({
        id=foreignId,title="Foreign Exact",author="Othermage",
        ownerKey="othermage@ebonhold",ownerVerified=true,realm="ebonhold",
        class="MAGE",echoes=collisionEchoes,fingerprint=collisionFp,
        fingerprintHash=DPS.GetEchoHash(collisionEchoes),echoCount=1,
        loadoutAvailable=true,lastModified=70000,
    })
end, "foreign exact-fingerprint fixture admission"), "foreign exact-fingerprint fixture was not stored")
local foreignBefore=Nexus.BuildCatalog.Get(foreignId)
stubDps=30000000
DPS.OnCombatStart(); clock=clock+35; DPS.OnUpdate(10); DPS.OnCombatEnd()
S.PumpCatalogToIdle("collision capture page admission")
local localCollision=NexusDB.dpsCapture.characterBest.dummy["recordmage@ebonhold"]
local foreignAfter=Nexus.BuildCatalog.Get(foreignId)
assert(localCollision and localCollision.fingerprint==collisionFp
    and localCollision.buildId and localCollision.buildId~=foreignId
    and Nexus.BuildCatalog.Get(localCollision.buildId),
    "EXPECTED RED: local capture associated with a foreign exact-fingerprint build: "
        .. tostring(localCollision and localCollision.buildId) .. "/"
        .. tostring(localCollision and localCollision.fingerprint) .. "/"
        .. tostring(collisionFp) .. "/"
        .. tostring(localCollision and Nexus.BuildCatalog.Get(localCollision.buildId)))
assert(foreignAfter and foreignBefore
    and foreignAfter.ownerKey==foreignBefore.ownerKey
    and foreignAfter.title==foreignBefore.title,
    "local capture mutated the foreign exact-fingerprint build")

-- Imported Saved mirrors are private local projections, not public DPS build
-- identities. Even an exact verified local mirror requires a distinct ordinary
-- record page before its ID can enter the DPS mesh.
local savedEchoes={{spellId=200112,quality=3,stacks=1}}
H.wishlist={name="Saved Collision",class="MAGE",echoes=savedEchoes}
H.granted={A={{spellId=200112,stack=1,maxStack=1,quality=3}},B={}}
H.FireEvent("SPELLS_CHANGED"); H.Advance(2)
local savedFp=DPS.GetEchoKey(savedEchoes)
local savedId="private-saved-recordmage"
assert(S.CatalogMutation(function()
    return Nexus.BuildCatalog.Put({
        id=savedId,title="Private Saved Recordmage",author="Recordmage",
        ownerKey="recordmage@ebonhold",ownerVerified=true,realm="ebonhold",
        importedSavedBuild=true,isMine=true,class="MAGE",echoes=savedEchoes,
        fingerprint=savedFp,fingerprintHash=DPS.GetEchoHash(savedEchoes),
        echoCount=1,loadoutAvailable=true,lastModified=71000,
    })
end, "private Saved collision fixture admission"), "private Saved collision fixture was not stored")
stubDps=32000000
DPS.OnCombatStart(); clock=clock+35; DPS.OnUpdate(10); DPS.OnCombatEnd()
S.PumpCatalogToIdle("Saved collision capture page admission")
local savedCollision=NexusDB.dpsCapture.characterBest.dummy["recordmage@ebonhold"]
local savedMirror=Nexus.BuildCatalog.Get(savedId)
assert(savedCollision and savedCollision.fingerprint==savedFp
    and savedCollision.buildId and savedCollision.buildId~=savedId
    and Nexus.Identity.SavedMirrorKind(
        Nexus.BuildCatalog.Get(savedCollision.buildId))=="ordinary",
    "EXPECTED RED: local DPS capture reused a private Saved mirror ID")
assert(savedMirror and savedMirror.importedSavedBuild==true
    and savedMirror.title=="Private Saved Recordmage"
    and sent[#sent] and sent[#sent].buildId~=savedId,
    "private Saved collision was mutated or disclosed through DPS egress")
print("automatic exact-loadout build and single-record DPS workflow -- OK")
