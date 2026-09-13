-- Full integration: posting a build through the real CommunityBuilds UI
-- actually broadcasts via Sync, and CHAT_MSG_CHANNEL events get routed
-- to Sync.HandleIncoming only when they're really our sync channel (not
-- some unrelated channel a player happens to be in).
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Relay.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/Readout.lua")
dofile("ui/Panel.lua")
Nexus.LogViewer = { Init = function() end }
dofile("ui/CommunityBuilds.lua")
dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/WishlistModel.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")

NexusDB = {}
H.wishlist = { name = "MyBuild", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 },
} }
H.playerLevel = 5
UnitName = function() return "Alice" end

H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("SPELLS_CHANGED")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.RequireStarted()
H.Advance(2)

assert(Nexus.Sync.IsConnected(), "sync channel should be connected after PLAYER_ENTERING_WORLD")
print("sync channel connects automatically on login -- OK")

-- Post through the real UI-facing function
for turns = 0, 200000 do
    local root = Nexus.BuildCatalog.RootState()
    if not root.candidate then break end
    assert(turns < 200000,
        "pre-post catalog work did not reach terminal state")
    H.Advance(0.1, 0.1)
end
local CB = Nexus.CommunityBuilds
local ok, id, postOutcome = CB.PostCurrentWishlist(
    "My Shared Build", "Check this out", H.wishlist)
if type(postOutcome) == "table" and postOutcome.localSaved ~= true then
    -- The retained pending save is accepted once and reports its state on
    -- the same outcome table until the terminal ticket completes it.
    assert(ok == true and postOutcome.queueReason == "ROOT_MUTATION_PENDING"
            and type(postOutcome.id) == "string" and id == postOutcome.id,
        "posting returned neither terminal success nor one retained catalog write")
    for turns = 0, 200000 do
        if postOutcome.localSaved == true then break end
        assert(turns < 200000,
            "posted wishlist did not reach terminal catalog state")
        H.Advance(0.1, 0.1)
    end
    ok = postOutcome.localSaved == true
end
assert(ok, "posting should succeed")
H.Advance(3)  -- let the send queue pump
assert(#H.sentChatMessages >= 1, "posting did not actually broadcast anything")
print("posting a wishlist through the real UI genuinely broadcasts it -- OK")

-- Simulate CHAT_MSG_CHANNEL from an UNRELATED channel -- must be ignored
local before = Nexus.Sync.Stats().received
local sentMsg = H.sentChatMessages[1].text
H.FireEvent("CHAT_MSG_CHANNEL", sentMsg, "Alice", "Common", "general")
assert(Nexus.Sync.Stats().received == before,
    "a message from an unrelated channel must NOT be processed as sync data")
print("messages from unrelated channels are correctly ignored -- OK")

-- Now simulate it arriving on the REAL sync channel (as another client
-- receiving Alice's broadcast) -- must be processed
-- Legacy-to-bundle cutover: after occupancy the durable payload is the bundle,
-- so a fresh client is a fresh database, not a cleared legacy location.
NexusDB = {}  -- pretend this is Bob's fresh client
H.RebindCatalog()
-- Receiving is opt-in: Bob must request a sync first.
Nexus.Sync.RequestSync()
for _, msg in ipairs(H.sentChatMessages) do
    H.FireEvent("CHAT_MSG_CHANNEL", msg.text, "Alice-Ebonhold", "Common",
        Nexus.Sync.ChannelName())
end
for turns = 0, 200000 do
    if H.DurableBuilds()[id] then break end
    assert(turns < 200000,
        "inbound integration mutation did not reach terminal state")
    H.Advance(0.1, 0.1)
end
assert(H.DurableBuilds()[id],
    "a message on the real sync channel should have been processed and stored")
assert(H.DurableBuilds()[id].title == "My Shared Build")
assert(rawget(NexusDB, "communityBuilds") == nil,
    "receiving wrote a legacy payload location")
print("messages on the real sync channel are correctly processed end-to-end -- OK")
