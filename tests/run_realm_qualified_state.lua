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
local realmA = Store.State()
realmA.loadoutWishlists[1] = "realm-a-wishlist"
realmA.flagDemotions.REALM_A = "kept"
realmA.tomeTogglePending[11] = {t=1,want=true}
realmA.recordedPicks[22] = 3
realmA.lockDesignTargetsBySlot = { [1]={owner="realm-a"} }
realmA.autoLockAttempts = { [33]={attempts=1} }
realmA.firstRunWishlist = {name="Realm A First"}
realmA.priorAutoAccept = true
realmA.rerollHoldViolations = 2
realmA.futureSafety = {owner="realm-a",keep=true}

currentRealm = "RealmB"
local realmB = Store.State()
Check(realmA ~= realmB, "RealmA and RealmB shared one mutable state table")
Check(NexusDB.chars["twin@realma"] == realmA,
    "RealmA state was not stored under its canonical owner key")
Check(NexusDB.chars["twin@realmb"] == realmB,
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
Check(Store.State() == realmA and realmA.futureSafety.keep,
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
        and durableAfterRealm.loadoutWishlists[1] == nil
        and NexusDB.chars["twin@realma"] == durableAfterRealm,
    "transient name-only state was promoted into durable RealmA state")

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
Check(Store.State() == canonicalA,
    "legacy short-key state displaced an existing canonical destination")
currentRealm = "RealmB"
local freshB = Store.State()
Check(freshB ~= legacy and freshB ~= canonicalA
        and NexusDB.chars["twin@realmb"] == freshB,
    "RealmB login claimed legacy or RealmA state")
Check(NexusDB.chars.Twin == legacy
        and legacy.loadoutWishlists[1] == "legacy-wishlist"
        and legacy.futureSafety.keep,
    "ambiguous legacy state or unknown fields were deleted or rewritten")

if #failures > 0 then
    error("EXPECTED RED realm-qualified Store state:\n - "
        .. table.concat(failures, "\n - "))
end

print("Store canonical state, transient login, legacy preservation, and realm isolation -- OK")
