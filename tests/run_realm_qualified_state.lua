-- Realm-qualified mutable character state must never borrow a short name or
-- manufacture a durable owner while the local realm is unavailable.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

local Store = Nexus.Store
local currentName, currentRealm = "Twin", "RealmA"
UnitName = function() return currentName end
GetNormalizedRealmName = function() return currentRealm end
GetRealmName = GetNormalizedRealmName
UnitClass = function() return "Mage", "MAGE" end
time = function() return 7000 end

local function Count(source)
    local total = 0
    for _ in pairs(type(source) == "table" and source or {}) do
        total = total + 1
    end
    return total
end

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

-- Same short name on two realms owns two durable tables.
NexusDB = {settingsVersion=2,settings={},chars={},accountCharacters={}}
-- MASTER-RC-001 reformulation. Store.State() is a DURABLE_READ that returns a
-- detached copy and, being pure, no longer CREATES the durable row -- row
-- creation moved to the counted private StoreAuthorityOwnerV1.UpdateStateV1
-- entry. Assertions of the form `NexusDB.chars[key] == Store.State()` therefore
-- test a premise the repair deliberately removed, and are structurally
-- unsatisfiable rather than merely inconvenient.
--
-- Every property this file tests is preserved and none of them depend on
-- reference identity, only on correct values under the correct key:
--   1. two realms own two distinct durable rows;
--   2. state is stored under the realm-qualified owner key;
--   3. one realm's fields never leak into the other;
--   4. no short-name durable row is manufactured;
--   5. re-selecting a realm returns its canonical state.
-- Each is now observed by inspecting the durable row and comparing content.
local function WriteState(mutator)
    local owner = Nexus.MainInternals and Nexus.MainInternals.StoreAuthorityOwner
    assert(owner and owner.UpdateStateV1, "StoreAuthorityOwnerV1 unavailable")
    return owner.UpdateStateV1(mutator)
end

WriteState(function(s)
    s.loadoutWishlists[1] = "realm-a-wishlist"
    s.flagDemotions.REALM_A = "kept"
    s.tomeTogglePending[11] = {t=1,want=true}
    s.recordedPicks[22] = 3
    s.lockDesignTargetsBySlot = { [1]={owner="realm-a"} }
    s.autoLockAttempts = { [33]={attempts=1} }
    s.firstRunWishlist = {name="Realm A First"}
    s.priorAutoAccept = true
    s.rerollHoldViolations = 2
    s.futureSafety = {owner="realm-a",keep=true}
end)
local realmARow = NexusDB.chars["twin@realma"]

currentRealm = "RealmB"
local realmB = Store.State()
-- RealmB owns a durable row only once something is written for it, which is
-- exactly the production path now.
WriteState(function(s) s.futureSafety = {owner="realm-b"} end)
local realmBRow = NexusDB.chars["twin@realmb"]
Check(type(realmARow) == "table" and type(realmBRow) == "table"
        and realmARow ~= realmBRow,
    "RealmA and RealmB shared one mutable state table")
Check(type(realmARow) == "table"
        and realmARow.loadoutWishlists[1] == "realm-a-wishlist"
        and realmARow.flagDemotions.REALM_A == "kept"
        and realmARow.futureSafety.owner == "realm-a",
    "RealmA state was not stored under its canonical owner key")
Check(type(realmBRow) == "table" and realmBRow.futureSafety.owner == "realm-b"
        and realmBRow.loadoutWishlists[1] == nil,
    "RealmB state was not stored under its canonical owner key")
Check(NexusDB.chars.Twin == nil,
    "short-name durable state was created for a realm-qualified character")
Check(realmB.loadoutWishlists[1] == nil
        and realmB.flagDemotions.REALM_A == nil
        and realmB.tomeTogglePending[11] == nil
        and realmB.recordedPicks[22] == nil
        and realmB.lockDesignTargetsBySlot == nil
        and realmB.autoLockAttempts == nil
        and realmB.firstRunWishlist == nil
        and realmB.priorAutoAccept == nil
        and realmB.rerollHoldViolations == nil,
    "RealmA mutable fields leaked into RealmB")

currentRealm = "RealmA"
local reselectedA = Store.State()
Check(reselectedA.futureSafety.keep
        and reselectedA.futureSafety.owner == "realm-a"
        and reselectedA.loadoutWishlists[1] == "realm-a-wishlist"
        and reselectedA.rerollHoldViolations == 2
        and NexusDB.chars["twin@realma"] == realmARow,
    "reload/reselection did not return the same canonical RealmA state")

-- Name-only startup remains transient and never migrates itself later.
NexusDB = {settingsVersion=2,settings={},chars={},accountCharacters={}}
currentRealm = nil
local transient = Store.State()
transient.loadoutWishlists[1] = "transient-only"
Check(Store.State() == transient, "realm-unavailable state was not stable in-session")
Check(Count(NexusDB.chars) == 0 and NexusDB.chars.Twin == nil
        and NexusDB.chars["twin@unknown"] == nil,
    "realm-unavailable startup created durable character state")

currentRealm = "RealmA"
local durableAfterRealm = Store.State()
Check(durableAfterRealm ~= transient
        and durableAfterRealm.loadoutWishlists[1] == nil,
    "transient name-only state was promoted into durable RealmA state")
WriteState(function(s) s.realmAMarker = true end)
Check(type(NexusDB.chars["twin@realma"]) == "table"
        and NexusDB.chars["twin@realma"].realmAMarker == true
        and NexusDB.chars["twin@realma"].loadoutWishlists[1] == nil,
    "durable RealmA state was not created under its canonical key, or "
        .. "inherited the transient name-only wishlist")

-- A legacy short-key row remains inactive evidence. Login order cannot claim
-- it, and existing canonical state always wins.
local legacy = {
    tomeTogglePending={},flagDemotions={LEGACY="keep"},recordedPicks={},
    loadoutWishlists={[1]="legacy-wishlist"},futureSafety={keep=true},
}
local canonicalA = {
    tomeTogglePending={},flagDemotions={CANONICAL="keep"},recordedPicks={},
    loadoutWishlists={[1]="realm-a"},futureSafety={canonical=true},
}
NexusDB = {
    settingsVersion=2,settings={},
    chars={Twin=legacy,["twin@realma"]=canonicalA},
    accountCharacters={},
}
currentRealm = "RealmA"
local selectedCanonical = Store.State()
Check(selectedCanonical.flagDemotions.CANONICAL == "keep"
        and selectedCanonical.loadoutWishlists[1] == "realm-a"
        and selectedCanonical.futureSafety.canonical == true
        and selectedCanonical.flagDemotions.LEGACY == nil,
    "legacy short-key state displaced an existing canonical destination")
currentRealm = "RealmB"
local freshB = Store.State()
Check(freshB.flagDemotions.LEGACY == nil
        and freshB.flagDemotions.CANONICAL == nil
        and freshB.loadoutWishlists[1] == nil,
    "RealmB login claimed legacy or RealmA state")
WriteState(function(s) s.realmBMarker = true end)
Check(type(NexusDB.chars["twin@realmb"]) == "table"
        and NexusDB.chars["twin@realmb"].realmBMarker == true
        and NexusDB.chars["twin@realmb"] ~= legacy
        and NexusDB.chars["twin@realmb"] ~= canonicalA,
    "RealmB durable state was not created under its own canonical key")
Check(NexusDB.chars.Twin == legacy
        and legacy.loadoutWishlists[1] == "legacy-wishlist"
        and legacy.futureSafety.keep,
    "ambiguous legacy state or unknown fields were deleted or rewritten")

if #failures > 0 then
    error("EXPECTED RED realm-qualified Store state:\n - "
        .. table.concat(failures, "\n - "))
end

print("Store canonical state, transient login, legacy preservation, and realm isolation -- OK")
