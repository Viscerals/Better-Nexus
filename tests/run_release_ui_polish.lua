local H=dofile("tests/harness.lua")
local S = dofile("tests/catalog_authority_support.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
dofile("data/DefaultProfile.lua"); dofile("logic/Model.lua"); dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua"); dofile("logic/Policy.lua"); dofile("core/Store.lua")
dofile("core/GameAdapter.lua"); dofile("ui/CommunityBuilds.lua"); dofile("ui/Leaderboard.lua")
NexusDB={communityBuilds={},dpsCapture={}}
local D=Nexus.DpsCapture
-- MASTER-RC-001 (architecture 1207-1211): Sync.Init and DpsCapture.Init no
-- longer admit the catalog root as a side effect. The same admission is
-- performed explicitly here, before the call, because the removed side
-- effect ran inside Init ahead of Init's own dependent steps. No assertion
-- or expected value in this fixture is changed.
H.AdmitCatalogV1(NexusDB)
D.Init({},nil)
local echoes={{spellId=200100,stacks=1}}
local id="verified-build"
NexusDB.communityBuilds[id]={id=id,title="Verified Mage",author="Mageone",class="MAGE",echoes=echoes,postedAt=1,lastModified=1}
-- Raw seeding grants no authority: readmit the complete root once.
H.RebindCatalog(NexusDB)
local fp=D.GetEchoKey(echoes)
assert(not D.ReceiveRecord({v=7,f=fp,e=echoes,c="dummy",d=1000000,u=29,t=1,p="Mageone",k="MAGE",l=80,b=id}),"29 second current record accepted")
assert(D.ReceiveRecord({v=7,f=fp,e=echoes,c="dummy",d=1000000,u=30,t=2,p="Mageone",k="MAGE",l=80,b=id}),"30 second record rejected")
S.PumpCatalogToIdle("verified record page work")
local verified=D.GetBuildVerification(id)
assert(verified and verified.duration==30,"verified build stamp missing")
Nexus.CommunityBuilds.Init(Nexus.GameAdapter,Nexus.Model)
Nexus.CommunityBuilds.Show()
assert(_G.NexusCommunityBuildsFrame._sortToggle:GetText()=="Sort: Highest DPS",
    "1.19.3 evidence-first default sort changed")
print("release UI polish and Details verification -- OK")
