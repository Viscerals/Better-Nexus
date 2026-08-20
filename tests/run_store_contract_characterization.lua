-- Characterize Store ownership and retry behavior before legacy retirement or
-- persistence extraction. This fixture intentionally does not change either
-- SavedVariables global.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

local Store = Nexus.Store

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, child in pairs(value) do out[Copy(key, seen)] = Copy(child, seen) end
    return out
end

local function Equal(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    seen = seen or {}
    if seen[left] then return seen[left] == right end
    seen[left] = right
    for key, value in pairs(left) do
        if not Equal(value, right[key], seen) then return false end
    end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

NexusDB = nil
WishlistRealizerDB = nil
UnitName = function() return "Unknown" end
local transientSettings = Store.Settings()
local transientState = Store.State()
assert(type(transientSettings) == "table" and type(transientState) == "table"
    and Store.Settings() == transientSettings and Store.State() == transientState
    and NexusDB == nil,
    "pre-init Store access latched or created persisted state")

local settings = {
    autoPick=false, autoActivate=false, updateNotifications=false,
    anchorNames={}, futurePreference={keep=true},
}
local hero = {
    tomeTogglePending={}, priorAutoAccept=false, flagDemotions={},
    recordedPicks={}, loadoutWishlists={}, futureSafety={keep=true},
}
local chars = {Hero=hero}
local builds = {preserved={future=true}}
local dps = {preserved={future=true}}
local tombstones = {preserved={stamp=1, author="Hero", future=true}}
local diagnostics = {preserved={future=true}}
local evidence = {preserved={future=true}}
local root = {
    settingsVersion=99,
    settings=settings,
    chars=chars,
    communityBuilds=builds,
    dpsCapture=dps,
    syncTombstones=tombstones,
    diagnosticLogs=diagnostics,
    loadoutEvidence=evidence,
    futureRoot={keep=true},
}
local futureSettingsBefore = Copy(settings)
local futureCharsBefore = Copy(chars)
NexusDB = root
UnitName = function() return "Hero" end

local calls = {}
local bundle = {marker="bundle"}
Nexus.BundledBuilds = bundle
Nexus.LoadoutEvidence = {Init=function(db)
    calls[#calls + 1] = "evidence"
    assert(db == root, "evidence initializer received a replacement root")
end}
Nexus.BuildCatalog = {Init=function(db, receivedBundle)
    calls[#calls + 1] = "catalog"
    assert(db == root and receivedBundle == bundle,
        "catalog initializer received a replacement dependency")
    return {readOnly=false}
end}
Nexus.DataCompaction = {Init=function(db)
    calls[#calls + 1] = "compaction"
    assert(db == root, "compaction initializer received a replacement root")
end}

Store.Init()
assert(table.concat(calls, ",") == "evidence,catalog,compaction",
    "Store additive owners initialized out of order")
assert(NexusDB == root and NexusDB.settings == settings
    and NexusDB.chars == chars and NexusDB.chars.Hero == hero,
    "Store initialization replaced root, settings, chars, or character state")
assert(NexusDB.settingsVersion == 99 and settings.autoPick == false
    and settings.autoSave == nil and #settings.anchorNames == 0
    and settings.futurePreference.keep and hero.priorAutoAccept == false
    and hero.futureSafety.keep and NexusDB.futureRoot.keep
    and Equal(settings, futureSettingsBefore)
    and Equal(chars, futureCharsBefore),
    "Store mutated future settings or character ownership")
assert(NexusDB.communityBuilds == builds and NexusDB.dpsCapture == dps
    and NexusDB.syncTombstones == tombstones
    and NexusDB.diagnosticLogs == diagnostics
    and NexusDB.loadoutEvidence == evidence,
    "Store initialization replaced another SavedVariables owner")
assert(Store.SettingsVersion() == 2 and Store.Settings() == transientSettings
    and Store.State() == transientState
    and Store.Settings() ~= settings and Store.State() ~= hero
    and Equal(settings, futureSettingsBefore)
    and Equal(chars, futureCharsBefore),
    "Store public accessors exposed or mutated a future owner")

calls = {}
Store.Init()
assert(table.concat(calls, ",") == "evidence,catalog,compaction"
    and NexusDB == root and Store.Settings() == transientSettings
    and Store.State() == transientState
    and Equal(settings, futureSettingsBefore)
    and Equal(chars, futureCharsBefore),
    "repeat initialization changed order or live-table identity")

calls = {}
Nexus.BuildCatalog.Init = function(db, receivedBundle)
    calls[#calls + 1] = "catalog"
    assert(db == root and receivedBundle == bundle)
    return {readOnly=true}
end
Store.Init()
assert(table.concat(calls, ",") == "evidence,catalog",
    "read-only catalog path ran data compaction")

calls = {}
Nexus.LoadoutEvidence.Init = function(db)
    calls[#calls + 1] = "evidence"
    assert(db == root)
end
Nexus.BuildCatalog.Init = function(db, receivedBundle)
    calls[#calls + 1] = "catalog-fail"
    assert(db == root and receivedBundle == bundle)
    error("injected catalog failure")
end
local catalogOk, catalogWhy = pcall(Store.Init)
assert(not catalogOk and tostring(catalogWhy):find("injected catalog failure", 1, true)
    and table.concat(calls, ",") == "evidence,catalog-fail",
    "Store swallowed catalog failure or invoked compaction afterward")
assert(NexusDB == root and NexusDB.settings == settings
    and NexusDB.chars == chars and NexusDB.chars.Hero == hero,
    "mid-order initialization failure replaced persistence identity")

-- A dependency failure propagates without replacing persistence or invoking
-- later owners. A later retry reuses the same root and completes in order.
calls = {}
Nexus.LoadoutEvidence.Init = function(db)
    calls[#calls + 1] = "evidence-fail"
    assert(db == root)
    error("injected evidence failure")
end
local ok, why = pcall(Store.Init)
assert(not ok and tostring(why):find("injected evidence failure", 1, true)
    and table.concat(calls, ",") == "evidence-fail",
    "Store swallowed failure or invoked a later persistence owner")
assert(NexusDB == root and NexusDB.settings == settings
    and NexusDB.chars == chars and NexusDB.chars.Hero == hero
    and NexusDB.communityBuilds == builds and NexusDB.dpsCapture == dps
    and NexusDB.syncTombstones == tombstones
    and NexusDB.diagnosticLogs == diagnostics
    and NexusDB.loadoutEvidence == evidence
    and NexusDB.settingsVersion == 99 and NexusDB.futureRoot.keep,
    "failed initialization replaced or downgraded SavedVariables data")

calls = {}
Nexus.LoadoutEvidence.Init = function(db)
    calls[#calls + 1] = "evidence"
    assert(db == root)
end
Nexus.BuildCatalog.Init = function(db, receivedBundle)
    calls[#calls + 1] = "catalog"
    assert(db == root and receivedBundle == bundle)
    return {readOnly=false}
end
Nexus.DataCompaction.Init = function(db)
    calls[#calls + 1] = "compaction"
    assert(db == root)
end
Store.Init()
assert(table.concat(calls, ",") == "evidence,catalog,compaction"
    and NexusDB == root and Store.Settings() == transientSettings
    and Store.State() == transientState
    and Equal(settings, futureSettingsBefore)
    and Equal(chars, futureCharsBefore),
    "Store retry did not complete against the preserved live root")

print("Store order, identity, future fields, failure, and retry behavior -- OK")
