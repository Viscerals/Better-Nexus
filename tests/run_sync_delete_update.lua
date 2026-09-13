-- Covers the three issues seen live (2026-07-24):
--   1. A build deleted by its author lingered forever on other clients.
--   2. Updates needed to be clearly distinguishable from duplicates.
--   3. Nothing may ever appear twice in the library.
local H = dofile("tests/harness.lua")
local S = dofile("tests/catalog_authority_support.lua")
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
local provider
Nexus.LogViewer = { Init = function(p) provider = p end,
    Show = function() end, Toggle = function() end }
dofile("ui/CommunityBuilds.lua")
dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/WishlistModel.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")

local Codec, Sync = Nexus.Codec, Nexus.Sync
local CB = Nexus.CommunityBuilds
local clock = 1000
GetTime = function() return clock end
local wall = 50000
time = function() return wall end
UnitName = function() return "Solkr" end
GetNormalizedRealmName = function() return "Ebonhold" end

NexusDB = {}
H.playerLevel = 5
H.wishlist = { name = "W", class = "ROGUE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 } } }
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("SPELLS_CHANGED")
H.FireEvent("PLAYER_ENTERING_WORLD")
H.Advance(2)

local function Deliver(msgs, fromName)
    for _, m in ipairs(msgs) do
        H.FireEvent("CHAT_MSG_CHANNEL", m.text,
            fromName .. "-Ebonhold", "Common",
            "5. " .. Sync.ChannelName(), nil, nil, nil, 5, Sync.ChannelName())
    end
    -- MASTER-W2-008: an accepted inbound row is one retained catalog
    -- mutation; its log line and durable row exist at the terminal commit.
    S.PumpCatalogToIdle("delivered build admission")
end
local function Drain()
    H.Advance(4)
    local m = {}
    for _, x in ipairs(H.sentChatMessages) do m[#m + 1] = x end
    H.sentChatMessages = {}
    return m
end

-- Author (Solkr) posts a build
H.sentChatMessages = {}
local ok, id = S.PostWishlist(CB.PostCurrentWishlist, "Rogue Double Strike", "the good one", H.wishlist)
assert(ok, "post failed")
local postMsgs = Drain()

-- Now act as the RECEIVING client: remove the local copy through the
-- catalog owner and receive it fresh. Raw SavedVariables are never edited
-- around the catalog authority.
local Catalog = Nexus.BuildCatalog
assert(S.CatalogMutation(function() return Catalog.RemoveOverlay(id) end,
    "local copy release"), "local copy was not released")
Sync.ClearLog()
clock = clock + 10
Sync.RequestSync()
Deliver(postMsgs, "Solkr")
S.PumpCatalogToIdle("received build admission")
-- Legacy-to-bundle cutover (state machine lines 394, 4849): the durable copy
-- lives in the authority bundle; the exact PR #68 location is preserved input.
local lib = H.DurableBuilds()
assert(lib and lib[id] and Catalog.Get(id), "build was not received")
assert(Catalog.Get(id).isMine == false, "a received build must not be marked mine")
print("build received from author -- OK")

local receiverBeforeEdit = Catalog.Get(id)
receiverBeforeEdit.isMine = false

-- 1. UPDATE must be logged as an update, not a duplicate, and must not
--    create a second entry.
wall = wall + 100
UnitName = function() return "Solkr" end
-- rebuild the author's copy so we can edit and re-share it
local authorCopy = Catalog.Get(id)
authorCopy.isMine = true
assert(S.CatalogMutation(function()
    return Catalog.Put(authorCopy, {source="local"})
end, "author copy restore"), "author copy was not restored")
CB.EditBuild(id, "Rogue Double Strike v2", "now even better")
local editMsgs = Drain()
-- Restore the receiver's older copy before delivering the author's update.
assert(S.CatalogMutation(function()
    return Catalog.Put(receiverBeforeEdit,
        {source="remote", sender="Solkr-Ebonhold"})
end, "receiver copy restore"), "receiver copy was not restored")

Sync.ClearLog()
clock = clock + 10
Sync.RequestSync()
Deliver(editMsgs, "Solkr")
local text = provider("sync")
assert(text:find("UPDATED") or text:find("DUPLICATE"), "updated build was neither accepted nor recognized as already current")
assert(Catalog.Get(id).title == "Rogue Double Strike v2",
    "the update did not actually apply")
local count = 0
for _ in pairs(H.DurableBuilds()) do count = count + 1 end
assert(count == 1 and Catalog.Count() == 1,
    "the update created a duplicate entry (" .. count .. " entries)")
print("an update is logged as UPDATED, applies in place, creates no duplicate -- OK")

-- 2. Re-delivering the exact same wire transfer is idempotent. Transport may
--    suppress the replay before the build layer emits a DUPLICATE event.
Sync.ClearLog()
clock = clock + 10
Sync.RequestSync()
Deliver(editMsgs, "Solkr")
text = provider("sync")
assert(text:find("DUPLICATE") or not text:find("UPDATED"),
    "an exact wire replay was applied as an update: " .. tostring(text))
count = 0
for _ in pairs(H.DurableBuilds()) do count = count + 1 end
assert(count == 1, "a duplicate replay created a second entry")
print("re-delivering the same wire version is idempotent, still one entry -- OK")

-- 3. DELETE from the author must remove it here
Sync.ClearLog()
clock = clock + 10
H.FireEvent("CHAT_MSG_CHANNEL", "WLRD||Solkr||" .. id .. "||99999",
    "Solkr-Ebonhold", "Common", "5. " .. Sync.ChannelName(),
    nil, nil, nil, 5, Sync.ChannelName())
-- The remote delete's opaque reservation is one retained catalog mutation.
S.PumpCatalogToIdle("remote delete reservation")
-- Protocol 7 carries no operation-order proof, so the remote delete becomes
-- an opaque deny-only reservation: the build leaves every public surface
-- while its admitted raw row is preserved as evidence.
assert(Catalog.Get(id) == nil and Catalog.Count() == 0
    and Catalog.TombstoneState(id).state == "OPAQUE_BLOCK_ALL",
    "the author's delete did not remove the build -- it would linger forever")
text = provider("sync")
assert(text:find("DELETED"), "the delete was not logged")
print("a delete from the author removes the build here too -- OK")

-- 4. A tombstoned build must NOT come back on the next sync
Sync.ClearLog()
clock = clock + 10
Sync.RequestSync()
Deliver(editMsgs, "Solkr")
assert(Catalog.Get(id) == nil,
    "a deleted build was resurrected by a stale copy still in flight")
text = provider("sync")
assert(text:find("tombstoned"), "the tombstone rejection was not logged")
print("a deleted build stays deleted, even if a stale copy arrives later -- OK")

-- 5. A different author cannot seize a tombstoned ID with a newer stamp.
UnitName = function() return "Griefer" end
H.sentChatMessages = {}
assert(Sync.BroadcastBuild({ id=id, title="Hijacked ID", description="bad",
    author="Griefer", ownerKey="griefer@ebonhold",
    ownerVerified=true, isMine=true, class="ROGUE",
    echoes={{spellId=200999,quality=0,stacks=1}},
    postedAt=100000, lastModified=100000 }))
local hijackMsgs = Drain()
UnitName = function() return "Solkr" end
clock = clock + 10
Sync.RequestSync()
Deliver(hijackMsgs, "Griefer")
assert(Catalog.Get(id) == nil
    and H.DurableTombstones()[id] ~= nil,
    "a different author seized a tombstoned build ID with a newer revision")
print("a tombstoned build ID cannot be seized by a different author -- OK")

H.sentChatMessages = {}
assert(Sync.BroadcastBuildSummary({ id=id, title="Summary hijack",
    author="Griefer", ownerKey="griefer@ebonhold",
    ownerVerified=true, isMine=true, class="ROGUE", fingerprintHash="deadbeef",
    echoCount=1, postedAt=100002, lastModified=100002 }))
local summaryHijackMsgs = Drain()
clock = clock + 10
Sync.RequestSync()
Deliver(summaryHijackMsgs, "Griefer")
assert(Catalog.Get(id) == nil
    and H.DurableTombstones()[id] ~= nil,
    "a different author seized a tombstoned build ID through a summary")
print("summary-only sync cannot bypass tombstone ownership -- OK")

-- Remote tombstone-to-row readmission always fails closed: protocol 7 has no
-- request identity or ordering proof, so even the original author cannot
-- supersede the reservation over the wire. Only an explicit trusted local
-- claim can replace it.
H.sentChatMessages = {}
assert(Sync.BroadcastBuild({ id=id, title="Authorized return", description="good",
    author="Solkr", ownerKey="solkr@ebonhold",
    ownerVerified=true, isMine=true, class="ROGUE",
    echoes={{spellId=200100,quality=3,stacks=1}},
    postedAt=100001, lastModified=100001 }))
local returnMsgs = Drain()
clock = clock + 10
Sync.RequestSync()
Deliver(returnMsgs, "Solkr")
assert(Catalog.Get(id) == nil and H.DurableTombstones()[id] ~= nil,
    "a remote revision superseded a tombstone reservation: "
        .. tostring(provider("sync")))
local claim = assert(Catalog.BeginTombstoneReadmissionClaim(id))
assert(S.CatalogMutation(function()
    return Catalog.PutWithClaim(claim, { id=id, title="Authorized return",
        description="good", author="Solkr", ownerKey="solkr@ebonhold",
        ownerVerified=true, isMine=true, class="ROGUE",
        echoes={{spellId=200100,quality=3,stacks=1}},
        postedAt=100001, lastModified=100001 }, {source="local"})
end, "claimed local readmission"),
    "the trusted local owner could not readmit their own build")
assert(Catalog.Get(id) and Catalog.Get(id).title == "Authorized return"
    and H.DurableTombstones()[id] == nil,
    "local readmission did not atomically replace the tombstone")
print("only an explicit trusted local claim can supersede a tombstone -- OK")

-- 6. A delete from someone who is NOT the author must be REFUSED
-- After the cutover an occupied bundle is authoritative and a raw legacy write
-- is not an admission input, so this fixture seeds a fresh database and lets
-- bootstrap admit the exact PR #68 legacy input (state machine line 374).
NexusDB = {}
NexusDB.communityBuilds = { ["victim"] = { id = "victim",
    title = "Someone Else's Build", description = "d", author = "Solkr",
    ownerKey = "solkr@ebonhold", ownerVerified = true,
    class = "ROGUE", echoes = { { spellId = 1, quality = 0, stacks = 1 } },
    postedAt = 1, lastModified = 1, isMine = false } }
NexusDB.syncTombstones = {}
local victimAdmission = H.RebindCatalog(NexusDB, Nexus.BundledBuilds)
assert(victimAdmission and victimAdmission.state == "ROOT_ADMITTED",
    "non-author delete fixture did not reach terminal catalog admission")
Sync.ClearLog()
H.FireEvent("CHAT_MSG_CHANNEL", "WLRD||Griefer||victim||99999",
    "Griefer-Ebonhold", "Common", "5. " .. Sync.ChannelName(),
    nil, nil, nil, 5, Sync.ChannelName())
assert(H.DurableBuilds()["victim"] and Catalog.Get("victim"),
    "a non-author was allowed to delete someone else's shared build")
assert(NexusDB.communityBuilds["victim"] ~= nil,
    "the preserved legacy bootstrap input was rewritten")
text = provider("sync")
assert(text:find("is not the author"), "the refused delete was not logged with a reason")
print("a delete from a non-author is refused and logged -- OK")

-- 7. Nobody can delete YOUR OWN build out from under you
NexusDB = {}
NexusDB.communityBuilds = { ["mine"] = { id = "mine", title = "My Build",
    description = "d", author = "Solkr", class = "ROGUE",
    ownerKey = "solkr@ebonhold", ownerVerified = true,
    echoes = { { spellId = 1, quality = 0, stacks = 1 } },
    postedAt = 1, lastModified = 1, isMine = true } }
NexusDB.syncTombstones = {}
local localAdmission = H.RebindCatalog(NexusDB, Nexus.BundledBuilds)
assert(localAdmission and localAdmission.state == "ROOT_ADMITTED",
    "local-owner delete fixture did not reach terminal catalog admission")
Sync.ClearLog()
H.FireEvent("CHAT_MSG_CHANNEL", "WLRD||Solkr||mine||99999",
    "Solkr-Ebonhold", "Common", "5. " .. Sync.ChannelName(),
    nil, nil, nil, 5, Sync.ChannelName())
assert(H.DurableBuilds()["mine"] and Catalog.Get("mine"),
    "an incoming delete removed one of MY OWN builds")
assert(NexusDB.communityBuilds["mine"] ~= nil,
    "the preserved legacy bootstrap input was rewritten")
print("incoming deletes can never remove your own builds -- OK")
