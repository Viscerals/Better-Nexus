-- Covers the three issues seen live (2026-07-24):
--   1. A build deleted by its author lingered forever on other clients.
--   2. Updates needed to be clearly distinguishable from duplicates.
--   3. Nothing may ever appear twice in the library.
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
local provider
Nexus.LogViewer = { Init = function(p) provider = p end,
    Show = function() end, Toggle = function() end }
dofile("ui/CommunityBuilds.lua")
dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
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
local ok, id = CB.PostCurrentWishlist("Rogue Double Strike", "the good one", H.wishlist)
assert(ok, "post failed")
local postMsgs = Drain()

-- Now act as the RECEIVING client: clear the library, receive it fresh
NexusDB.communityBuilds = nil
Sync.ClearLog()
clock = clock + 10
Sync.RequestSync()
Deliver(postMsgs, "Solkr")
local lib = NexusDB.communityBuilds
assert(lib and lib[id], "build was not received")
assert(lib[id].isMine == false, "a received build must not be marked mine")
print("build received from author -- OK")

local receiverBeforeEdit = {}
for k, v in pairs(lib[id]) do receiverBeforeEdit[k] = v end
receiverBeforeEdit.isMine = false

-- 1. UPDATE must be logged as an update, not a duplicate, and must not
--    create a second entry.
wall = wall + 100
UnitName = function() return "Solkr" end
-- rebuild the author's copy so we can edit and re-share it
NexusDB.communityBuilds[id].isMine = true
CB.EditBuild(id, "Rogue Double Strike v2", "now even better")
local editMsgs = Drain()
-- Restore the receiver's older copy before delivering the author's update.
NexusDB.communityBuilds[id] = receiverBeforeEdit

Sync.ClearLog()
clock = clock + 10
Sync.RequestSync()
Deliver(editMsgs, "Solkr")
local text = provider("sync")
assert(text:find("UPDATED") or text:find("DUPLICATE"), "updated build was neither accepted nor recognized as already current")
assert(NexusDB.communityBuilds[id].title == "Rogue Double Strike v2",
    "the update did not actually apply")
local count = 0
for _ in pairs(NexusDB.communityBuilds) do count = count + 1 end
assert(count == 1, "the update created a duplicate entry (" .. count .. " entries)")
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
for _ in pairs(NexusDB.communityBuilds) do count = count + 1 end
assert(count == 1, "a duplicate replay created a second entry")
print("re-delivering the same wire version is idempotent, still one entry -- OK")

-- 3. DELETE from the author must remove it here
Sync.ClearLog()
clock = clock + 10
H.FireEvent("CHAT_MSG_CHANNEL", "WLRD||Solkr||" .. id .. "||99999",
    "Solkr-Ebonhold", "Common", "5. " .. Sync.ChannelName(),
    nil, nil, nil, 5, Sync.ChannelName())
assert(NexusDB.communityBuilds[id] == nil,
    "the author's delete did not remove the build -- it would linger forever")
text = provider("sync")
assert(text:find("DELETED"), "the delete was not logged")
print("a delete from the author removes the build here too -- OK")

-- 4. A tombstoned build must NOT come back on the next sync
Sync.ClearLog()
clock = clock + 10
Sync.RequestSync()
Deliver(editMsgs, "Solkr")
assert(NexusDB.communityBuilds[id] == nil,
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
assert(NexusDB.communityBuilds[id] == nil
    and NexusDB.syncTombstones[id] ~= nil,
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
assert(NexusDB.communityBuilds[id] == nil
    and NexusDB.syncTombstones[id] ~= nil,
    "a different author seized a tombstoned build ID through a summary")
print("summary-only sync cannot bypass tombstone ownership -- OK")

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
assert(NexusDB.communityBuilds[id]
    and NexusDB.communityBuilds[id].title == "Authorized return"
    and NexusDB.syncTombstones[id] == nil,
    "the original author could not explicitly supersede their tombstone: "
        .. tostring(provider("sync")))
print("the original author can supersede their tombstone with a newer revision -- OK")

-- 6. A delete from someone who is NOT the author must be REFUSED
NexusDB.communityBuilds = { ["victim"] = { id = "victim",
    title = "Someone Else's Build", description = "d", author = "Solkr",
    ownerKey = "solkr@ebonhold", ownerVerified = true,
    class = "ROGUE", echoes = { { spellId = 1, quality = 0, stacks = 1 } },
    postedAt = 1, lastModified = 1, isMine = false } }
Sync.ClearLog()
H.FireEvent("CHAT_MSG_CHANNEL", "WLRD||Griefer||victim||99999",
    "Griefer-Ebonhold", "Common", "5. " .. Sync.ChannelName(),
    nil, nil, nil, 5, Sync.ChannelName())
assert(NexusDB.communityBuilds["victim"],
    "a non-author was allowed to delete someone else's shared build")
text = provider("sync")
assert(text:find("is not the author"), "the refused delete was not logged with a reason")
print("a delete from a non-author is refused and logged -- OK")

-- 7. Nobody can delete YOUR OWN build out from under you
NexusDB.communityBuilds = { ["mine"] = { id = "mine", title = "My Build",
    description = "d", author = "Solkr", class = "ROGUE",
    ownerKey = "solkr@ebonhold", ownerVerified = true,
    echoes = { { spellId = 1, quality = 0, stacks = 1 } },
    postedAt = 1, lastModified = 1, isMine = true } }
Sync.ClearLog()
H.FireEvent("CHAT_MSG_CHANNEL", "WLRD||Solkr||mine||99999",
    "Solkr-Ebonhold", "Common", "5. " .. Sync.ChannelName(),
    nil, nil, nil, 5, Sync.ChannelName())
assert(NexusDB.communityBuilds["mine"],
    "an incoming delete removed one of MY OWN builds")
print("incoming deletes can never remove your own builds -- OK")
