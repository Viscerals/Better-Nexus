-- Dedicated leaderboard is separate from Builds and renders dense ranked rows.
local H=dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
dofile("data/DefaultProfile.lua"); dofile("logic/Model.lua"); dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua"); dofile("logic/Policy.lua"); dofile("core/Store.lua")
dofile("core/GameAdapter.lua"); dofile("ui/CommunityBuilds.lua"); dofile("ui/Leaderboard.lua")
UnitName=function(unit) return unit=="player" and "Viewer" or nil end
UnitClass=function() return "Mage","MAGE" end
NexusDB={communityBuilds={},syncTombstones={},dpsCapture={}}
local DPS=Nexus.DpsCapture
DPS.Init({}, {BroadcastBuild=function() return true end})
local a={{spellId=200001,stacks=2},{spellId=200002,stacks=1}}
local b={{spellId=200010,stacks=1},{spellId=200011,stacks=3}}
assert(DPS.ReceiveRecord({v=4,f=DPS.GetEchoKey(a),e=a,c="dummy",d=24000000,u=65,t=100,p="Alpha",k="MAGE",l=80}))
assert(DPS.ReceiveRecord({v=4,f=DPS.GetEchoKey(b),e=b,c="dummy",d=28000000,u=65,t=101,p="Bravo",k="MAGE",l=80}))
Nexus.CommunityBuilds.Init(Nexus.GameAdapter,Nexus.Model)
Nexus.Leaderboard.Init(Nexus.GameAdapter)
Nexus.Leaderboard.Show("dummy")
assert(H.frames.NexusLeaderboardFrame and H.frames.NexusLeaderboardFrame:IsShown(),"leaderboard window did not open")
-- Refreshing a selected record must use WoW 3.3.5 Button:Enable/Disable, not modern SetEnabled.
Nexus.Leaderboard.Refresh()
assert(not H.frames.NexusCommunityBuildsFrame or not H.frames.NexusCommunityBuildsFrame:IsShown(),"build browser should not be required for leaderboard")
Nexus.CommunityBuilds.SetViewMode("lk")
assert(Nexus.Leaderboard.IsShown(),"legacy leaderboard route did not open dedicated window")
print("dedicated dense leaderboard window and legacy routing -- OK")
