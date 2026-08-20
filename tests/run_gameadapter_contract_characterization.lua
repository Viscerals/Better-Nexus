-- Characterize GameAdapter as the sole automation-side Project Ebonhold
-- boundary before any internal extraction.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")

local Store, A = Nexus.Store, Nexus.GameAdapter
UnitName = function() return "Hero" end
NexusDB = {
    settingsVersion=2,
    settings={autoPick=false, autoActivate=false},
    chars={Hero={futureSafety={keep=true}}},
    futureRoot={keep=true},
}
Store.Init()

local function Read(path)
    local handle, why = io.open(path, "rb")
    assert(handle, "unable to read " .. tostring(path) .. ": " .. tostring(why))
    local value = handle:read("*a")
    handle:close()
    return value
end

local function ExecutableText(source)
    local lines = {}
    for line in source:gmatch("[^\r\n]+") do
        -- The target files use only ordinary one-line strings/comments for
        -- these references. Remove those before rejecting executable access,
        -- so documentation may still name the boundary it promises.
        line = line:gsub('".-"', '""'):gsub("'.-'", "''")
        line = line:gsub("%-%-.*$", "")
        lines[#lines + 1] = line
    end
    return table.concat(lines, "\n")
end
assert(not ExecutableText('-- ProjectEbonhold\nlocal label = "ProjectEbonhold"')
        :find("ProjectEbonhold", 1, true)
    and ExecutableText("local service = ProjectEbonhold")
        :find("ProjectEbonhold", 1, true),
    "Project Ebonhold boundary scanner did not distinguish prose from code")

-- The automation coordinator and pure policy stack cannot reach Ebonhold
-- globals directly. UI frame integration is outside this automation boundary.
for _, path in ipairs({
    "core/Main.lua", "core/AutomationRuntime.lua", "core/MainLifecycle.lua",
    "logic/Model.lua", "logic/Strategy.lua",
    "logic/Ratchet.lua", "logic/Policy.lua", "logic/Relay.lua",
}) do
    local source = Read(path)
    assert(not ExecutableText(source):find("ProjectEbonhold", 1, true),
        path .. " bypasses the GameAdapter automation boundary")
end

local serviceOrder = {}
local function TraceService(name)
    local original = H.service[name]
    assert(type(original) == "function", "missing harness service " .. name)
    H.service[name] = function(...)
        serviceOrder[#serviceOrder + 1] = name
        return original(...)
    end
end
for _, name in ipairs({
    "ToggleTomeEcho", "SelectPerk", "BanishPerk", "RequestReroll",
    "FreezePerk", "ActivateServerBuildSlot", "SaveServerBuildSlot",
}) do
    TraceService(name)
end

local statusMessages = {}
A.Init({OnStatus=function(text) statusMessages[#statusMessages + 1] = text end}, Store)
H.playerLevel = 5
H.PushRunData({
    remainingBanishes=3, totalRerolls=3, usedRerolls=0,
    totalFreezes=3, usedFreezes=0,
})
H.DeliverDiscovery({})
H.DeliverSlots({
    [1]={slot=1, name="Saved Loadout", verified=true,
        echoes={{spellId=200100, stacks=1}}},
    [6]={slot=6, name="Designed Wishlist", verified=false,
        echoes={{spellId=200102, stacks=1, locked=true}}},
}, 1)
H.DeliverBoard({
    {spellId=200100, quality=3},
    {spellId=200102, quality=2},
    {spellId=200104, quality=2},
})
H.locked = {{spellId=200104,quality=2,stack=1}}
H.service.GetMaximumPermanentEchoes = function() return 3 end

local function MutationSnapshot()
    return table.concat({
        #H.wire, #H.selectCalls, #H.banishCalls, H.rerollCalls,
        #H.freezeCalls, #H.activateCalls, #H.saveCalls,
        H.optSettings.autoAcceptLoadoutEchoes and 1 or 0,
    }, ":")
end

-- Public reads return defensive values and never call a gameplay mutator.
serviceOrder = {}
local mutationBeforeReads = MutationSnapshot()
local board = A.Board()
local slots = A.Slots()
local owned = A.Owned()
local candidates = A.GetWishlistCandidates()
local charges = A.Charges()
local catalog = A.Catalog()
local locked = A.LockedOwned()
local rawLocked = A.DumpLockedPerksRaw()
local permanentMaximum, capacitySource = A.MaxPermanentEchoes()
assert(board and slots and owned and #candidates == 1 and charges.arrived
    and catalog and type(locked) == "table" and type(rawLocked) == "string",
    string.format("GameAdapter read facade shape mismatch: board=%s slots=%s owned=%s candidates=%d charges=%s catalog=%s locked=%s raw=%s",
        type(board), type(slots), type(owned), #candidates,
        tostring(charges and charges.arrived), type(catalog), type(locked),
        type(rawLocked)))
assert(locked.synced and locked.bySpell[200104] == 1
    and permanentMaximum == 3 and capacitySource == "service",
    "GameAdapter lost authoritative runtime capacity evidence (expected 1/3)")
local capacityReader = H.service.GetMaximumPermanentEchoes
H.service.GetMaximumPermanentEchoes = function() return nil end
local unknownMaximum, unknownSource = A.MaxPermanentEchoes()
assert(unknownMaximum == nil and unknownSource == "unavailable",
    "missing runtime capacity guessed from the editor's six design cells")
H.service.GetMaximumPermanentEchoes = capacityReader
local validLocked = H.locked
H.locked = {malformed=1}
assert(A.LockedOwned().synced == false,
    "malformed locked evidence remained authoritative")
H.locked = validLocked
board.cards[1].spellId = -1
slots.bySlot[1].name = "mutated"
candidates[1].name = "mutated"
assert(A.Board().cards[1].spellId == 200100
    and A.Slots().bySlot[1].name == "Saved Loadout"
    and A.GetWishlistCandidates()[1].name == "Designed Wishlist",
    "GameAdapter read facade leaked mutable service tables")
assert(#serviceOrder == 0 and MutationSnapshot() == mutationBeforeReads,
    "GameAdapter read facade submitted gameplay work")

-- Association writes stay in Store and exact-loadout resolution follows the
-- immutable Echo identity without touching Project Ebonhold mutations.
local heroState = Store.State()
assert(A.SetLoadoutWishlist(1, 6), "loadout association fixture failed")
local association = A.GetLoadoutWishlist(1)
local wishlist = A.Wishlist()
assert(association and association.name == "Designed Wishlist"
    and wishlist and wishlist.name == "Designed Wishlist"
    and wishlist.source == "loadout-association"
    and heroState.loadoutWishlists[1].key == A.WishlistKey(association.echoes)
    and heroState.futureSafety.keep and NexusDB.futureRoot.keep
    and #serviceOrder == 0 and MutationSnapshot() == mutationBeforeReads,
    "association resolution bypassed Store identity or gameplay ownership")

-- Event hooks expose one bounded dirty set, and the owned-data retry deadline
-- stops after five attempts instead of polling forever.
H.granted = nil
A.OnEvent("PLAYER_ENTERING_WORLD")
local boardDirty, slotsDirty = A.ConsumeDirty()
assert(boardDirty and slotsDirty and not select(1, A.ConsumeDirty()),
    "PLAYER_ENTERING_WORLD dirty state was missing or not consumed once")
for _ = 1, 8 do
    H.now = H.now + 6
    A.Poll()
end
local ownedSync = A.OwnedSyncInfo()
assert(ownedSync.retries == 5 and H.grantedRequests == 5,
    "owned-data retry did not stop at its established bound")
ownedSync.retries = -1
H.now = H.now + 30
A.Poll()
assert(A.OwnedSyncInfo().retries == 5 and H.grantedRequests == 5,
    "owned-data retry snapshot leaked or resumed after expiry")

-- Passive diagnostics block every gameplay mutator before reaching the
-- external service, while read-only diagnostics and association state remain.
local passiveBefore = MutationSnapshot()
serviceOrder = {}
A.DIAGNOSTIC_PASSIVE = true
for _, result in ipairs({
    {A.ToggleLever(300400, true)}, {A.Take(200100)}, {A.Banish(0)},
    {A.Reroll()}, {A.Freeze(0)}, {A.Activate(1)}, {A.Save(2, "blocked")},
    {A.UploadWishlist(0, "blocked", {{spellId=200100, stacks=1}})},
    {A.LockPerk(200100)}, {A.UnlockPerk(200100)}, {A.SetSoloPicker()},
    {A.RestoreAutoAccept()}, {A.SetLoadoutWishlist(1, 6)},
    {A.ClearLoadoutWishlist(1)},
}) do
    assert(result[1] == false, "passive diagnostic allowed a gameplay mutation")
end
assert(#serviceOrder == 0 and MutationSnapshot() == passiveBefore
    and heroState.loadoutWishlists[1] ~= nil,
    "passive diagnostic changed service, options, or association state")
A.DIAGNOSTIC_PASSIVE = false

-- Accepted actions reach exactly one external mutation in call order. Retry,
-- latch, and spacing rejections leave those counters unchanged.
serviceOrder = {}
H.playerLevel = 1
assert(A.ToggleLever(300400, true), "conformant lever mutation was refused")
H.playerLevel = 5
H.DeliverBoard({
    {spellId=200100, quality=3}, {spellId=200102, quality=2},
    {spellId=200104, quality=2},
})
assert(A.Take(200100) and not A.Take(200102),
    "select in-flight gate changed")
H.ResolveSelect(false)
A.Poll()

H.PushRunData({remainingBanishes=3, totalRerolls=3, usedRerolls=0,
    totalFreezes=3, usedFreezes=0})
H.DeliverBoard({
    {spellId=200100, quality=3}, {spellId=200102, quality=2},
    {spellId=200104, quality=2},
})
assert(A.Banish(0), "banish mutation was refused")
H.ResolveBanish(200200, 1)
A.Poll()

H.DeliverBoard({
    {spellId=200100, quality=3}, {spellId=200102, quality=2},
    {spellId=200104, quality=2},
})
assert(A.Reroll(), "reroll mutation was refused")
H.DeliverBoard({
    {spellId=200102, quality=2}, {spellId=200104, quality=2},
    {spellId=200200, quality=1},
})
A.Poll()

H.PushRunData({remainingBanishes=3, totalRerolls=3, usedRerolls=0,
    totalFreezes=3, usedFreezes=0})
H.DeliverBoard({
    {spellId=200100, quality=3}, {spellId=200102, quality=2},
    {spellId=200104, quality=2},
})
assert(A.Freeze(0), "freeze mutation was refused")
H.Perks.pendingFreezeIndex = nil
A.Poll()

H.playerLevel = 1
H.now = H.now + 4
assert(A.Activate(1), "activate mutation was refused")
local activates = #H.activateCalls
assert(not A.Activate(1) and #H.activateCalls == activates,
    "build spacing rejection reached the service")
H.playerLevel = 80
H.now = H.now + 4
assert(A.Save(2, "Saved Contract"), "save mutation was refused")

assert(table.concat(serviceOrder, ",") == table.concat({
    "ToggleTomeEcho", "SelectPerk", "BanishPerk", "RequestReroll",
    "FreezePerk", "ActivateServerBuildSlot", "SaveServerBuildSlot",
}, ","), "GameAdapter changed ordered external mutation calls")

-- A direct user action is captured by the hook and consumed exactly once;
-- adapter-originated calls above are not misclassified as user actions.
assert(A.ConsumeUserAction() == nil,
    "adapter-originated action leaked into the user-action latch")
H.playerLevel = 5
H.DeliverBoard({
    {spellId=200100, quality=3}, {spellId=200102, quality=2},
    {spellId=200104, quality=2},
})
assert(H.service.SelectPerk(200100), "external action fixture failed")
local userAction = A.ConsumeUserAction()
assert(userAction and userAction.kind == "SelectPerk" and userAction.arg == 200100
    and A.ConsumeUserAction() == nil,
    "external user action was not captured and consumed exactly once")
H.ResolveSelect(false)

print("GameAdapter reads, associations, dirty/retry state, passive safety, and ordered mutations -- OK")
