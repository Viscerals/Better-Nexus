local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")
dofile("core/DiagnosticHistory.lua")
dofile("core/Codec.lua")
dofile("core/SyncPolicy.lua")
dofile("core/Sync.lua")

time = function() return 50000 end
NexusDB = { settings={syncMode="off"}, chars={} }
Nexus.Store.Init()
local Sync = Nexus.Sync
Sync.Init(Nexus.Codec, nil)

assert(Sync.Mode() == "off" and not Sync.IsConnected()
    and H.joinedChannels[Sync.ChannelName()] == nil,
    "Off joined the Sync channel")
assert(not Sync.BroadcastDps("build", "Boganic", 1000, 80, "dummy")
    and Sync.WorkState().outbound == 0,
    "Off admitted outbound traffic")
assert(not Sync.HandleIncoming("WLNP|Peer|1.20.0", "Peer"),
    "Off accepted inbound traffic")

Sync.SetMode("manual")
assert(Sync.GetEffectiveState().key == "manual-idle" and not Sync.IsConnected(),
    "Manual mode did background transport work")
local manualBuild = {
    id="manual-local", title="Manual Local", author="Boganic",
    ownerKey="boganic@ebonhold", class="MAGE", isMine=true,
    postedAt=50000, lastModified=50000,
    echoes={{spellId=200100,quality=3,stacks=1}},
}
assert(Nexus.BuildCatalog.Put(manualBuild),
    "Manual publication fixture was not stored durably")
assert(not Sync.BroadcastBuild(manualBuild),
    "Manual idle unexpectedly sent an immediate build broadcast")
local deletedBuild = {
    id="manual-delete", title="Manual Delete", author="Boganic",
    ownerKey="boganic@ebonhold", class="MAGE", isMine=true,
    postedAt=50001, lastModified=50001,
    echoes={{spellId=200101,quality=3,stacks=1}},
}
assert(Nexus.BuildCatalog.Put(deletedBuild),
    "Manual delete fixture was not stored durably")
assert(not Sync.BroadcastDelete(deletedBuild),
    "Manual idle unexpectedly sent an immediate delete")
H.resting = false
assert(not Sync.RequestSync() and not Sync.IsConnected(),
    "Manual Sync started while not resting")
H.resting = true
assert(Sync.RequestSync() and Sync.IsConnected()
    and Sync.WorkState().outbound > 0,
    "Manual Sync did not start after an explicit safe request")
H.sentChatMessages = {}
for _ = 1, 12 do
    H.now = H.now + 1.2
    Sync.OnUpdate(1.2)
end
local sentBuild, sentDelete = false, false
for _, message in ipairs(H.sentChatMessages) do
    sentBuild = sentBuild or message.text:find("WLBI||Boganic||", 1, true) ~= nil
    sentDelete = sentDelete
        or message.text:find("WLRD||Boganic||manual-delete||", 1, true) ~= nil
end
assert(sentBuild and sentDelete,
    "Manual Sync Now did not publish durable local build/delete deltas")

H.inCombat = true
Sync.ContextChanged("combat")
assert(not Sync.IsConnected() and Sync.WorkState().outbound == 0
    and not Sync.WorkState().manualPublishing
    and Sync.GetEffectiveState().key == "suspended",
    "combat suspension retained a channel or queued burst")

Sync.SetMode("automatic")
assert(not Sync.IsConnected(), "Automatic joined while combat-blocked")
H.inCombat = false
H.resting = false
Sync.ContextChanged("left combat")
assert(not Sync.IsConnected()
    and Sync.GetEffectiveState().reason == "not resting",
    "Automatic did not wait for a resting area")
H.resting = true
Sync.ContextChanged("resting")
assert(Sync.IsConnected(), "Automatic did not connect after entering a resting area")
H.Advance(7)
Sync.OnUpdate(6.1)
assert(Sync.WorkState().outbound > 0,
    "Automatic did not schedule one safe convergence pass")

H.inInstance, H.instanceType = true, "party"
Sync.ContextChanged("instance")
assert(not Sync.IsConnected() and Sync.WorkState().outbound == 0,
    "configured instance suspension retained queued transport")

H.instanceType = "housing"
Sync.ContextChanged("unconfigured instance")
assert(Sync.IsConnected(), "unconfigured instance type suspended Sync")

Sync.SetMode("off")
H.inInstance, H.instanceType = false, "none"
Sync.ContextChanged("left instance")
assert(not Sync.IsConnected() and Sync.GetEffectiveState().key == "off",
    "Off resumed after a context transition")

print("Off, Manual, Automatic, resting, combat, and instance Sync policy -- OK")
