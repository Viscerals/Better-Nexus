-- Login sync opens one bounded receive window automatically. Outside that
-- window, unsolicited build traffic is ignored; manual Sync Now reopens it.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
local Codec, Sync = Nexus.Codec, Nexus.Sync
local clock = 1000
GetTime = function() return clock end
time = function() return 50000 end
local currentName = "Alice"
UnitName = function() return currentName end
GetNormalizedRealmName = function() return "Ebonhold" end
local function Pump(steps) for _=1,steps do clock=clock+0.2; Sync.OnUpdate(0.2) end end

local function EncodeBob(id, title, stamp)
    local saved = H.sentChatMessages
    H.sentChatMessages = {}
    local prior = currentName; currentName = "Bob"
    Sync.BroadcastBuild({ id=id, title=title, description="d", author="Bob",
        ownerKey="bob@ebonhold", ownerVerified=true, isMine=true, class="ROGUE",
        echoes={{spellId=200100,quality=3,stacks=1}}, postedAt=stamp,lastModified=stamp })
    Pump(100)
    currentName = prior
    local msgs=H.sentChatMessages; H.sentChatMessages=saved
    return msgs
end

NexusDB = {}
Sync.Init(Codec,nil)
-- Generate payload before the automatic receive window fires.
local msgs=EncodeBob("bob-1","Bob's Build",100)
-- Login-time sync fires within the bounded 8-16 second startup delay above.
assert(Sync.IsReceiving(),"automatic login sync should open the receive window")
for _,m in ipairs(msgs) do Sync.HandleIncoming(m.text,"Bob-Ebonhold") end
assert(NexusDB.communityBuilds and NexusDB.communityBuilds["bob-1"],
    "automatic login sync did not accept current build metadata")
print("automatic login sync receives current mesh metadata -- OK")

-- Once the status window expires, direct-author traffic is still accepted.
clock=clock+70
assert(not Sync.IsReceiving(),"automatic receive window should expire")
local msgs2=EncodeBob("bob-2","Bob's Second",200)
for _,m in ipairs(msgs2) do Sync.HandleIncoming(m.text,"Bob-Ebonhold") end
assert(NexusDB.communityBuilds["bob-2"],"direct-author data was dropped outside a sync window")
print("direct-author updates remain accepted after the status window -- OK")

-- Manual Sync Now reopens convergence.
clock=clock+10
assert(Sync.RequestSync(),"manual sync should succeed")
for _,m in ipairs(msgs2) do Sync.HandleIncoming(m.text,"Bob-Ebonhold") end
assert(NexusDB.communityBuilds["bob-2"],"manual sync lost existing metadata")
print("manual sync reconciles already accepted metadata -- OK")

-- Convergence may run several bounded passes. Once it reports idle it must stop.
Pump(20)
clock=clock+70
H.sentChatMessages={}
for i=1,500 do clock=clock+1; Sync.OnUpdate(1.0) end
local phase=Sync.GetLeaderboardSyncStatus()
assert(phase=="idle","bounded convergence did not reach idle")
H.sentChatMessages={}
Pump(100)
for _,m in ipairs(H.sentChatMessages) do
    assert(not m.text:find("^WLRQ"),"idle addon restarted convergence")
end
print("bounded convergence reaches idle and stays quiet -- OK")
