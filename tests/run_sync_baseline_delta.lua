-- Same-release, legacy, and different-release peers exchange bounded overlay
-- deltas. Immutable bundled rows remain available by exact loadout request.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")

local Sync = Nexus.Sync
local Catalog = Nexus.BuildCatalog
local clock = 1000
GetTime = function() return clock end
time = function() return 50000 end
local playerName = "Alice"
UnitName = function() return playerName end
GetNormalizedRealmName = function() return "Ebonhold" end

local function Pump(steps)
    for _ = 1, steps do
        clock = clock + 0.2
        Sync.OnUpdate(0.2)
    end
end

local function BuildIds(messages)
    local ids = {}
    for _, message in ipairs(messages) do
        local wire = message.text:gsub("||", "|")
        local id = wire:match("^WLRB|[^|]+|([^|]+)|")
            or wire:match("^WLBI|[^|]+|([^|]+)|")
        if id then ids[id] = true end
    end
    return ids
end

local bundle = {
    schemaVersion=1, catalogVersion="sync-delta-test-1", sourceVersion="1.19.4",
    builds={
        ["baseline-a"]={id="baseline-a",title="Baseline A",author="Alice",
            ownerKey="alice@ebonhold",class="MAGE",description="A",
            postedAt=10,lastModified=10,
            echoes={{spellId=200101,quality=3,stacks=1}}},
        ["baseline-b"]={id="baseline-b",title="Baseline B",author="Alice",
            ownerKey="alice@ebonhold",class="MAGE",description="B",
            postedAt=20,lastModified=20,
            echoes={{spellId=200102,quality=3,stacks=1}}},
    },
}
Nexus.BundledBuilds = bundle
NexusDB = {communityBuilds={},syncTombstones={}}
Sync.Init(Nexus.Codec,{})
Pump(100)
H.sentChatMessages = {}

local emptyReleaseHash, dpsHash = Sync.GetCompatibilityHashes()
local hashParts = {}
for part in emptyReleaseHash:gmatch("([^,]+)") do
    hashParts[#hashParts + 1] = part
end
assert(#hashParts == 9 and hashParts[9] ~= "0",
    "current compatibility hash lacks the release-catalog token")

assert(Sync.HandleIncoming("WLRQ|Current|" .. emptyReleaseHash .. "|"
    .. dpsHash .. "|same-release", "Current"))
Pump(40)
local stateReceipts, statePayloads = 0, 0
for _, message in ipairs(H.sentChatMessages) do
    local wire = message.text:gsub("||", "|")
    if wire:find("^WLRC|[^|]+|Current|same%-release|") then
        stateReceipts = stateReceipts + 1
    elseif wire:find("^WLRB|") or wire:find("^WLD2|") then
        statePayloads = statePayloads + 1
    end
end
assert(stateReceipts == 1 and statePayloads == 0,
    "matching release did not produce one payload-free state receipt")

local changed = {id="overlay-change",title="Overlay Change",author="Alice",
    ownerKey="alice@ebonhold",ownerVerified=true,realm="ebonhold",
    class="MAGE",description="Changed",
    postedAt=30,lastModified=30,isMine=true,
    echoes={{spellId=200103,quality=3,stacks=1}}}
assert(Catalog.Put(changed))
H.sentChatMessages = {}
assert(Sync.HandleIncoming("WLRQ|Current|" .. emptyReleaseHash .. "|"
    .. dpsHash .. "|one-overlay", "Current"))
Pump(100)
local deltaIds = BuildIds(H.sentChatMessages)
assert(deltaIds["overlay-change"] and not deltaIds["baseline-a"]
    and not deltaIds["baseline-b"],
    "same-release response sent baseline rows instead of only the overlay")
assert((Sync.Stats().overlaySent or 0) == 1,
    "overlay send metric did not record the admitted delta")

-- Exact on-demand lookup must resolve immutable rows through BuildCatalog;
-- this remains useful to summary-only 1.19.4 peers during mixed rollout.
clock = clock + 10
H.sentChatMessages = {}
assert(Sync.HandleIncoming("WLLQ|ExactPeer|baseline-a", "ExactPeer"))
Pump(80)
local exactMessages = H.sentChatMessages
local exactIds = BuildIds(exactMessages)
assert(exactIds["baseline-a"] and not exactIds["baseline-b"],
    "exact loadout recovery did not resolve the requested bundled row")

-- An eight-bucket requester is an older peer. It receives the mutable overlay
-- only; bundled loadouts remain explicit on-demand transfers.
clock = clock + 10
H.sentChatMessages = {}
local emptyLegacy = "0,0,0,0,0,0,0,0"
assert(Sync.HandleIncoming("WLRQ|Legacy|" .. emptyLegacy
    .. "|0|legacy-full|1.19.3", "Legacy"))
Pump(180)
local legacyMessages = H.sentChatMessages
local legacyIds = BuildIds(legacyMessages)
assert(legacyIds["overlay-change"] and not legacyIds["baseline-a"]
    and not legacyIds["baseline-b"],
    "legacy requester did not receive only the bounded overlay delta")

-- A current-format peer with a different release token uses the same bounded
-- compatibility delta instead of a complete bundled-baseline fallback.
clock = clock + 10
H.sentChatMessages = {}
local differentRelease = emptyLegacy .. ",deadbeef"
assert(Sync.HandleIncoming("WLRQ|OtherRelease|" .. differentRelease
    .. "|0|different-release|1.19.4", "OtherRelease"))
Pump(180)
local differentIds = BuildIds(H.sentChatMessages)
assert(differentIds["overlay-change"] and not differentIds["baseline-a"]
    and not differentIds["baseline-b"],
    "different-release peer did not receive only the compatibility delta")

-- Feed the exact requested baseline payload back into a clean current install.
-- It is valid, but the immutable row must not be copied into SavedVariables.
local baselinePackets = {}
for _, message in ipairs(exactMessages) do
    if message.text:gsub("||", "|"):find("^WLRB|Alice|baseline%-a|") then
        baselinePackets[#baselinePackets + 1] = message.text
    end
end
assert(#baselinePackets > 0, "exact-loadout fixture did not capture baseline payload")
playerName = "Receiver"
clock = clock + 100
NexusDB = {communityBuilds={},syncTombstones={}}
Sync.Init(Nexus.Codec,{})
for _, packet in ipairs(baselinePackets) do
    assert(Sync.HandleIncoming(packet, "Alice"),
        "current peer rejected a valid legacy baseline packet")
end
assert(NexusDB.communityBuilds["baseline-a"] == nil,
    "legacy baseline duplicate was persisted in the overlay")
local recovered, source = Catalog.Get("baseline-a")
assert(recovered and source == "bundled" and #recovered.echoes == 1,
    "exact bundled loadout was unavailable after legacy recovery")
assert((Sync.Stats().baselineSkipped or 0) >= 1,
    "baseline skip metric did not record the legacy duplicate")

-- Tombstones participate in the same release-aware delta without dragging
-- any immutable baseline build into the response. Only the author may send it.
playerName = "Alice"
clock = clock + 100
NexusDB = {communityBuilds={},syncTombstones={}}
Sync.Init(Nexus.Codec,{})
Pump(100)
H.sentChatMessages = {}
local beforeDeleteHash, beforeDeleteDps = Sync.GetCompatibilityHashes()
assert(Catalog.SetTombstone("baseline-b", {
    stamp=40,author="Alice",ownerKey="alice@ebonhold",ownerVerified=true,
}))
assert(Sync.HandleIncoming("WLRQ|DeletePeer|" .. beforeDeleteHash .. "|"
    .. beforeDeleteDps .. "|one-delete", "DeletePeer"))
Pump(100)
local sawDelete = false
for _, message in ipairs(H.sentChatMessages) do
    local wire = message.text:gsub("||", "|")
    if wire:find("^WLRD|Alice|baseline%-b|40|Alice$") then
        sawDelete = true
    end
end
assert(sawDelete and next(BuildIds(H.sentChatMessages)) == nil,
    "same-release tombstone delta omitted the delete or resent baseline rows")

print("release-aware bounded deltas and exact bundled recovery -- OK")
