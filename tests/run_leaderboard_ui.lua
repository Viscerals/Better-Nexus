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

-- The projection-free Combined compatibility path carries the same public
-- identity presentation and deterministic equal-score tie used by the normal
-- ViewProjections owner.
local function Upvalue(fn, wanted)
    for index=1,40 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then return value end
    end
end
local rowsReader = assert(Upvalue(Nexus.Leaderboard.RefreshData, "Rows"),
    "projection-free Rows reader was not inspectable")
local combinedReader = assert(Upvalue(rowsReader, "CombinedRows"),
    "projection-free Combined reader was not inspectable")
local function PublicRow(ownerKey, category, spellId)
    return {
        player="Twin",displayPlayer="Twin-"..ownerKey:match("@(.+)$"),
        publicIdentityKey="verified:"..ownerKey,
        publicIdentityVerified=true,ownerKey=ownerKey,ownerVerified=true,
        realm=ownerKey:match("@(.+)$"),category=category,
        dps=20000000,ts=200,duration=65,level=80,class="MAGE",
        fingerprint=tostring(spellId).."x1",
        echoes={{spellId=spellId,count=1}},protocolVersion=7,
    }
end
local fallback = {dummy={},lk={}}
for _, realm in ipairs({"realmb","realma"}) do
    local owner = "twin@"..realm
    local spellId = realm == "realma" and 840001 or 840002
    fallback.dummy[#fallback.dummy+1] = PublicRow(owner,"dummy",spellId)
    fallback.lk[#fallback.lk+1] = PublicRow(owner,"lk",spellId)
end
local originalBoard = DPS.GetDpsBoard
DPS.GetDpsBoard = function(category) return fallback[category] or {} end
local fallbackCombined = combinedReader()
DPS.GetDpsBoard = originalBoard
assert(#fallbackCombined == 2
        and fallbackCombined[1].displayPlayer == "Twin-realma"
        and fallbackCombined[2].displayPlayer == "Twin-realmb"
        and fallbackCombined[1].publicIdentityVerified == true
        and fallbackCombined[1].publicIdentityKey
            < fallbackCombined[2].publicIdentityKey,
    "projection-free Combined lost identity presentation or stable realm order")
print("dedicated dense leaderboard window and legacy routing -- OK")
