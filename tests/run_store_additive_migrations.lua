local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

local Store = Nexus.Store

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do out[Copy(key, seen)] = Copy(child, seen) end
    return out
end

local function Equal(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then
        if type(left) == "number" and left ~= left and right ~= right then return true end
        return left == right
    end
    seen = seen or {}
    if seen[left] then return seen[left] == right end
    seen[left] = right
    for key, value in pairs(left) do
        if not Equal(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

-- Old-name-only saves move as the same table, then upgrade additively. Every
-- preference, safety field, and unrelated subsystem remains owned by the save.
local settings = {
    autoPick=false,
    autoActivate=false,
    updateNotifications=false,
    leverOptOut={[17]=true, futureLeverValue="keep"},
    futurePreference={nested="preserve"},
}
local pending = {
    [17]=123.5,
    [18]={t=124,want=false,futurePendingField="keep"},
}
local demotions = {DISABLE_SUPPRESSES_GUARANTEE="observed"}
local picks = {[200100]=2}
local wishlists = {[3]="stable-wishlist"}
local state = {
    tomeTogglePending=pending,
    priorAutoAccept=false,
    flagDemotions=demotions,
    recordedPicks=picks,
    loadoutWishlists=wishlists,
    futureSafetyState={token="keep"},
}
local filters = {classFilter="MAGE",futureFilter="keep"}
local dps = {personalBest={keep=true}}
local notice = {version="9.9.9",source="Peer"}
local legacy = {
    settingsVersion=1,
    settings=settings,
    chars={
        Hero=state,
        Partial={
            tomeTogglePending="malformed", flagDemotions={custom="keep"},
            recordedPicks=false, loadoutWishlists=7, futureSafety="keep",
        },
        Broken="malformed",
    },
    buildFilters=filters,
    dpsCapture=dps,
    updateNotice=notice,
    unrelatedRoot={future=true},
}
WishlistRealizerDB = legacy
NexusDB = nil
Store.Init()

assert(NexusDB == legacy and WishlistRealizerDB == nil,
    "old SavedVariables name was not adopted exactly once")
assert(NexusDB.settings == settings and NexusDB.chars.Hero == state,
    "migration replaced live settings or character tables")
assert(NexusDB.settingsVersion == Store.SettingsVersion()
    and NexusDB.settingsVersion == 2, "ordered migration version was not recorded")
assert(settings.autoPick == false and settings.autoActivate == false
    and settings.updateNotifications == false,
    "existing false preferences were overwritten by defaults")
assert(settings.autoSave == true and settings.autoBanish == true
    and settings.anchorNames[1] == "Adaptive Power",
    "missing defaults were not filled additively")
assert(settings.leverOptOut.futureLeverValue == "keep"
    and settings.futurePreference.nested == "preserve",
    "unknown preference fields were not preserved")
assert(NexusDB.buildFilters == filters and NexusDB.dpsCapture == dps
    and NexusDB.updateNotice == notice and NexusDB.unrelatedRoot.future,
    "unrelated NexusDB subsystems changed during settings migration")
assert(state.tomeTogglePending == pending
    and type(pending[17]) == "table" and pending[17].t == 123.5
    and pending[17].want == true,
    "legacy pending toggle was not converted in place")
assert(pending[18].want == false and pending[18].futurePendingField == "keep",
    "current pending toggle or its unknown field changed")
assert(state.priorAutoAccept == false and state.flagDemotions == demotions
    and state.recordedPicks == picks and state.loadoutWishlists == wishlists
    and state.futureSafetyState.token == "keep",
    "character safety or unknown state was rebuilt")
assert(type(NexusDB.chars.Partial.tomeTogglePending) == "table"
    and type(NexusDB.chars.Partial.recordedPicks) == "table"
    and type(NexusDB.chars.Partial.loadoutWishlists) == "table"
    and NexusDB.chars.Partial.flagDemotions.custom == "keep"
    and NexusDB.chars.Partial.futureSafety == "keep"
    and type(NexusDB.chars.Broken) == "table"
    and type(NexusDB.chars.Broken.flagDemotions) == "table",
    "partial character state was not filled additively")

local originalUnitName = UnitName
UnitName = function() return "Hero" end
local canonicalState = Store.State()
assert(canonicalState ~= state
    and NexusDB.chars["hero@ebonhold"] == canonicalState
    and NexusDB.chars.Hero == state and state.futureSafetyState.token == "keep"
    and Store.Settings() == settings,
    "Store accessors claimed ambiguous short state or lost canonical persistence")
UnitName = originalUnitName

local converted = pending[17]
local afterFirst = Copy(NexusDB)
Store.Init()
assert(Equal(NexusDB, afterFirst),
    "repeat initialization changed a completed current-version save")
assert(pending[17] == converted,
    "completed pending-toggle migration ran more than once")

-- WoW or an earlier bootstrap may materialize the new variable as an empty
-- table. It is still the first-upgrade path and must adopt the legacy save.
local emptyCurrent = {}
local emptyPathLegacy = {
    settingsVersion=1, settings={autoPick=false,legacyPreference="keep"},
    chars={},legacyRoot="keep",
}
NexusDB = emptyCurrent
WishlistRealizerDB = emptyPathLegacy
Store.Init()
assert(NexusDB == emptyPathLegacy and WishlistRealizerDB == nil
    and NexusDB.settings.autoPick == false
    and NexusDB.settings.legacyPreference == "keep"
    and NexusDB.legacyRoot == "keep",
    "empty current SavedVariables path did not adopt the legacy save")

-- When both names exist, the current Nexus save remains authoritative. The
-- legacy global is released only after the completed current-wins decision;
-- the distinct table itself is never mutated or merged speculatively.
local current = {
    settingsVersion=2,
    settings={autoPick=false,currentOnly="keep",anchorNames={}},
    chars={},currentRoot=true,
}
local staleLegacy = {settings={autoPick=true},legacyOnly="keep"}
NexusDB = current
WishlistRealizerDB = staleLegacy
Store.Init()
assert(NexusDB == current and WishlistRealizerDB == nil
    and NexusDB.currentRoot and NexusDB.settings.currentOnly == "keep"
    and next(NexusDB.settings.anchorNames) == nil
    and staleLegacy.legacyOnly == "keep"
    and NexusDB.nexusStoreMigrations.wishlistRealizerDB.completed == true
    and NexusDB.nexusStoreMigrations.wishlistRealizerDB.decision == "keptCurrent",
    "current and legacy SavedVariables collision clobbered one owner or stayed pending")

-- Future settings/character owners are opaque. Runtime callers receive
-- transient current defaults without any init-time or read-time writes into
-- the newer persisted tables.
WishlistRealizerDB = nil
NexusDB = {
    settingsVersion=99,
    settings={autoPick=false,futurePreference="keep"},
    chars={Future={futureSafety="keep",tomeTogglePending={[1]=55}}},
    futureRoot="keep",
}
local futureSettingsBefore = Copy(NexusDB.settings)
local futureCharsBefore = Copy(NexusDB.chars)
Store.Init()
assert(NexusDB.settingsVersion == 99 and NexusDB.settings.autoPick == false
    and NexusDB.settings.autoSave == nil
    and NexusDB.settings.futurePreference == "keep"
    and NexusDB.chars.Future.futureSafety == "keep"
    and NexusDB.chars.Future.tomeTogglePending[1] == 55
    and NexusDB.futureRoot == "keep"
    and Equal(NexusDB.settings, futureSettingsBefore)
    and Equal(NexusDB.chars, futureCharsBefore),
    "future settings or character owner was mutated")
local savedUnitName = UnitName
UnitName = function() return "Future" end
local futureRuntimeSettings = Store.Settings()
local futureRuntimeState = Store.State()
assert(futureRuntimeSettings ~= NexusDB.settings
    and futureRuntimeSettings.autoSave == true
    and futureRuntimeState ~= NexusDB.chars.Future
    and Equal(NexusDB.settings, futureSettingsBefore)
    and Equal(NexusDB.chars, futureCharsBefore),
    "future owner was exposed or mutated by a runtime accessor")
UnitName = savedUnitName
local futureOnce = Copy(NexusDB)
Store.Init()
assert(Equal(NexusDB, futureOnce),
    "repeat initialization changed a future-version save")

print("additive settings migrations preserve preferences, safety state, rename paths, and future fields -- OK")
