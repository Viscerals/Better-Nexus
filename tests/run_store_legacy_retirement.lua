local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

local Store = Nexus.Store

local function Marker(db)
    local migrations = type(db) == "table" and db.nexusStoreMigrations
    return type(migrations) == "table" and migrations.wishlistRealizerDB or nil
end

local function StubOwners(options)
    options = options or {}
    local calls = options.calls
    Nexus.BundledBuilds = options.bundle or {}
    Nexus.LoadoutEvidence = {Init=function(db)
        if calls then calls[#calls + 1] = "evidence" end
        if options.fail == "evidence" then error("injected evidence failure") end
        return db
    end}
    Nexus.BuildCatalog = {Init=function(db)
        if calls then calls[#calls + 1] = "catalog" end
        if options.fail == "catalog" then error("injected catalog failure") end
        return {readOnly=options.readOnly == true}
    end}
    Nexus.DataCompaction = {Init=function(db)
        if calls then calls[#calls + 1] = "compaction" end
        if options.fail == "compaction" then error("injected compaction failure") end
        return db
    end}
end

local function BasicRoot(label, version)
    return {
        settingsVersion=version or 2,
        settings={autoPick=false,owner=label,anchorNames={}},
        chars={Hero={
            tomeTogglePending={}, flagDemotions={}, recordedPicks={},
            loadoutWishlists={}, futureSafety={owner=label},
        }},
        communityBuilds={one={author=label}},
        dpsCapture={owner=label},
        syncTombstones={one={author=label,stamp=1}},
        diagnosticLogs={owner=label},
        loadoutEvidence={owner=label},
        futureRoot={owner=label},
    }
end

-- Legacy-only: adopt the exact root, run every owner, then publish and clear.
local legacyOnly = BasicRoot("legacy")
local legacySettings = legacyOnly.settings
local legacyHero = legacyOnly.chars.Hero
local legacyBuilds = legacyOnly.communityBuilds
local legacyDps = legacyOnly.dpsCapture
local legacyTombstones = legacyOnly.syncTombstones
local legacyDiagnostics = legacyOnly.diagnosticLogs
local legacyEvidence = legacyOnly.loadoutEvidence
local legacyUnknown = legacyOnly.futureRoot
local calls = {}
NexusDB = nil
WishlistRealizerDB = legacyOnly
StubOwners({calls=calls})
Store.Init()
local adoptedMarker = Marker(NexusDB)
assert(NexusDB == legacyOnly and WishlistRealizerDB == nil,
    "legacy-only save was not adopted by table identity then released")
assert(table.concat(calls, ",") == "evidence,catalog,compaction",
    "legacy completion did not follow ordered Store owners")
assert(adoptedMarker and adoptedMarker.version == 1
    and adoptedMarker.completed == true
    and adoptedMarker.decision == "adoptedLegacy",
    "legacy adoption did not publish the durable completed marker")
assert(NexusDB.settings == legacySettings and NexusDB.chars.Hero == legacyHero
    and NexusDB.communityBuilds == legacyBuilds and NexusDB.dpsCapture == legacyDps
    and NexusDB.syncTombstones == legacyTombstones
    and NexusDB.diagnosticLogs == legacyDiagnostics
    and NexusDB.loadoutEvidence == legacyEvidence
    and NexusDB.futureRoot == legacyUnknown
    and NexusDB.settings.autoPick == false and #NexusDB.settings.anchorNames == 0,
    "legacy adoption replaced preferences, subsystem data, or unknown fields")

-- Current-only/future: current stays authoritative and its future version is
-- not downgraded. The additive marker is the only new Store-owned namespace.
local futureCurrent = BasicRoot("future-current", 99)
local futureSettings = futureCurrent.settings
local futureUnknown = futureCurrent.futureRoot
local futureNamespace = {futureOwner={keep=true}}
futureCurrent.nexusStoreMigrations = futureNamespace
NexusDB = futureCurrent
WishlistRealizerDB = nil
StubOwners({readOnly=true})
Store.Init()
local futureMarker = Marker(futureCurrent)
assert(NexusDB == futureCurrent and WishlistRealizerDB == nil
    and NexusDB.settingsVersion == 99 and NexusDB.settings == futureSettings
    and NexusDB.futureRoot == futureUnknown
    and NexusDB.nexusStoreMigrations == futureNamespace
    and futureNamespace.futureOwner.keep
    and futureMarker and futureMarker.decision == "keptCurrent",
    "current-only future save was replaced, downgraded, or left undecided")

-- Deep equality never provides merge authority: distinct identical roots use
-- the current table, just like distinct different roots.
local identicalCurrent = BasicRoot("identical")
local identicalLegacy = BasicRoot("identical")
NexusDB = identicalCurrent
WishlistRealizerDB = identicalLegacy
StubOwners()
Store.Init()
assert(NexusDB == identicalCurrent and WishlistRealizerDB == nil
    and Marker(identicalCurrent).decision == "keptCurrent"
    and identicalLegacy.settings.owner == "identical",
    "both-identical databases did not preserve current table authority")

local differentCurrent = BasicRoot("current")
local differentLegacy = BasicRoot("stale-legacy")
local differentCurrentSettings = differentCurrent.settings
local differentLegacySettings = differentLegacy.settings
NexusDB = differentCurrent
WishlistRealizerDB = differentLegacy
StubOwners()
Store.Init()
assert(NexusDB == differentCurrent and WishlistRealizerDB == nil
    and NexusDB.settings == differentCurrentSettings
    and NexusDB.settings.owner == "current"
    and differentLegacy.settings == differentLegacySettings
    and differentLegacy.settings.owner == "stale-legacy"
    and Marker(differentCurrent).decision == "keptCurrent",
    "both-different databases merged or replaced current authority")

local emptyCurrent = {}
local emptyLegacy = {}
NexusDB = emptyCurrent
WishlistRealizerDB = emptyLegacy
StubOwners()
Store.Init()
assert(NexusDB == emptyCurrent and WishlistRealizerDB == nil
    and Marker(emptyCurrent).decision == "ignoredEmptyLegacy"
    and next(emptyLegacy) == nil,
    "empty legacy data replaced the current root or remained undecided")

-- A malformed value under either name blocks an unmarked decision without
-- mutating either root. Only absent/empty current data may adopt legacy data.
local malformedLegacyCurrent = BasicRoot("current-before-malformed")
NexusDB = malformedLegacyCurrent
WishlistRealizerDB = "malformed legacy"
StubOwners()
local malformedLegacyOk, malformedLegacyWhy = pcall(Store.Init)
assert(not malformedLegacyOk
    and tostring(malformedLegacyWhy):find("preserving it for recovery", 1, true)
    and NexusDB == malformedLegacyCurrent
    and WishlistRealizerDB == "malformed legacy"
    and Marker(malformedLegacyCurrent) == nil,
    "malformed legacy input was cleared, marked, or silently accepted")

local malformedCurrent = "malformed current"
local preservedLegacy = BasicRoot("preserved-legacy")
NexusDB = malformedCurrent
WishlistRealizerDB = preservedLegacy
StubOwners()
local malformedCurrentOk, malformedCurrentWhy = pcall(Store.Init)
assert(not malformedCurrentOk
    and tostring(malformedCurrentWhy):find("NexusDB is malformed", 1, true)
    and NexusDB == malformedCurrent and WishlistRealizerDB == preservedLegacy
    and Marker(preservedLegacy) == nil,
    "malformed current data was replaced, marked, or allowed to clear legacy")

NexusDB = 42
WishlistRealizerDB = nil
StubOwners()
local loneMalformedOk = pcall(Store.Init)
assert(not loneMalformedOk and NexusDB == 42 and WishlistRealizerDB == nil,
    "malformed current-only data was replaced by a fresh database")

local repairableCurrent = BasicRoot("repairable")
repairableCurrent.settings = "malformed settings"
repairableCurrent.chars = "malformed chars"
local repairableLegacy = BasicRoot("must-not-win")
NexusDB = repairableCurrent
WishlistRealizerDB = repairableLegacy
StubOwners()
Store.Init()
assert(NexusDB == repairableCurrent and WishlistRealizerDB == nil
    and type(repairableCurrent.settings) == "table"
    and type(repairableCurrent.chars) == "table"
    and Marker(repairableCurrent).decision == "keptCurrent",
    "repairable current table did not retain authority")

-- A completed decision is not rewritten. Reintroduced stale data is released
-- only after the normal ordered owners succeed again.
local repeatedRoot = BasicRoot("repeat")
NexusDB = repeatedRoot
WishlistRealizerDB = nil
StubOwners()
Store.Init()
local repeatedMarker = Marker(repeatedRoot)
local repeatedDecision = repeatedMarker.decision
local reintroducedLegacy = BasicRoot("reintroduced")
WishlistRealizerDB = reintroducedLegacy
calls = {}
StubOwners({calls=calls})
Store.Init()
assert(NexusDB == repeatedRoot and WishlistRealizerDB == nil
    and Marker(repeatedRoot) == repeatedMarker
    and repeatedMarker.decision == repeatedDecision
    and table.concat(calls, ",") == "evidence,catalog,compaction"
    and reintroducedLegacy.futureRoot.owner == "reintroduced",
    "repeat initialization repeated the decision or changed table identity")

-- A valid marker from a future Store owner is read but never downgraded or
-- replaced. Unknown marker and namespace fields remain represented.
local futureMarkedRoot = BasicRoot("future-marker")
local futureCompleted = {
    version=9, completed=true, decision="futureDecision", futureField="keep",
}
local futureMarkedNamespace = {
    wishlistRealizerDB=futureCompleted, futureOwner={keep=true},
}
futureMarkedRoot.nexusStoreMigrations = futureMarkedNamespace
NexusDB = futureMarkedRoot
WishlistRealizerDB = BasicRoot("stale-after-future-marker")
StubOwners()
Store.Init()
assert(NexusDB == futureMarkedRoot and WishlistRealizerDB == nil
    and futureMarkedRoot.nexusStoreMigrations == futureMarkedNamespace
    and Marker(futureMarkedRoot) == futureCompleted
    and futureCompleted.version == 9 and futureCompleted.futureField == "keep"
    and futureMarkedNamespace.futureOwner.keep,
    "future migration marker or unknown namespace fields were overwritten")

-- Failure in the last ordered owner proves the marker/clear boundary. Retry
-- recognizes the shared adopted root and finishes against the same table.
local interrupted = BasicRoot("interrupted")
NexusDB = nil
WishlistRealizerDB = interrupted
StubOwners({fail="compaction"})
local interruptedOk, interruptedWhy = pcall(Store.Init)
assert(not interruptedOk
    and tostring(interruptedWhy):find("injected compaction failure", 1, true)
    and NexusDB == interrupted and WishlistRealizerDB == interrupted
    and Marker(interrupted) == nil,
    "failed migration published completion or lost the recovery reference")
StubOwners()
Store.Init()
assert(NexusDB == interrupted and WishlistRealizerDB == nil
    and Marker(interrupted).decision == "adoptedLegacy",
    "interrupted same-root adoption did not resume idempotently")

-- Unknown ownership of the dedicated namespace fails closed before normal
-- Store mutation and never destroys either database.
local conflictedCurrent = BasicRoot("conflicted")
conflictedCurrent.nexusStoreMigrations = "future-owner"
local conflictedLegacy = BasicRoot("conflicted-legacy")
NexusDB = conflictedCurrent
WishlistRealizerDB = conflictedLegacy
StubOwners()
local conflictOk, conflictWhy = pcall(Store.Init)
assert(not conflictOk
    and tostring(conflictWhy):find("incompatible value", 1, true)
    and NexusDB == conflictedCurrent
    and WishlistRealizerDB == conflictedLegacy
    and conflictedCurrent.nexusStoreMigrations == "future-owner",
    "incompatible migration namespace was overwritten or released")

local malformedMarkerCurrent = BasicRoot("malformed-marker")
local malformedMarkerNamespace = {
    wishlistRealizerDB={version=1,completed=false,futureField="keep"},
}
malformedMarkerCurrent.nexusStoreMigrations = malformedMarkerNamespace
local malformedMarkerLegacy = BasicRoot("marker-legacy")
NexusDB = malformedMarkerCurrent
WishlistRealizerDB = malformedMarkerLegacy
StubOwners()
local malformedMarkerOk, malformedMarkerWhy = pcall(Store.Init)
assert(not malformedMarkerOk
    and tostring(malformedMarkerWhy):find("marker is malformed", 1, true)
    and NexusDB == malformedMarkerCurrent
    and WishlistRealizerDB == malformedMarkerLegacy
    and malformedMarkerCurrent.nexusStoreMigrations == malformedMarkerNamespace
    and malformedMarkerNamespace.wishlistRealizerDB.completed == false,
    "malformed completion marker was overwritten or treated as complete")

-- The compatibility declaration remains until a separate product decision.
local tocFile = assert(io.open("Nexus.toc", "r"))
local toc = tocFile:read("*a")
tocFile:close()
assert(toc:find("## SavedVariables: NexusDB WishlistRealizerDB", 1, true),
    "Nexus.toc no longer declares both SavedVariables names")

-- Store is the sole legacy completion owner across every TOC-loaded runtime
-- file. Existing direct NexusDB fallback initializers remain characterized but
-- none may acquire legacy/marker ownership.
local storeFile = assert(io.open("core/Store.lua", "r"))
local source = storeFile:read("*a")
storeFile:close()
local runtimeSource = ""
local runtimeFiles = {}
for line in toc:gmatch("[^\r\n]+") do
    local path = line:match("^%s*(.-%.lua)%s*$")
    if path then
        path = path:gsub("\\", "/")
        local runtimeFile = assert(io.open(path, "r"))
        local runtimeText = runtimeFile:read("*a")
        runtimeFiles[path] = runtimeText
        runtimeSource = runtimeSource .. "\n" .. runtimeText
        runtimeFile:close()
    end
end
local _, legacyClearWrites = runtimeSource:gsub(
    "WishlistRealizerDB%s*=%s*[^=]", "")
local _, storeCurrentBindWrites = source:gsub("NexusDB%s*=%s*db", "")
local _, markerNamespaceWrites = runtimeSource:gsub(
    "db%[LEGACY_MIGRATION_NAMESPACE%]%s*=%s*[^=]", "")
local _, markerKeyWrites = runtimeSource:gsub(
    "migrations%[LEGACY_MIGRATION_KEY%]%s*=%s*[^=]", "")
local compactionCall = assert(source:find("Nexus.DataCompaction.Init(db)", 1, true))
local completionCall = assert(source:find(
    "CompleteLegacyMigration(db, legacyDecision)", compactionCall, true))
local expectedCurrentWrites = {
    ["core/DiagnosticLogs.lua"]=1, ["core/DpsCapture.lua"]=2,
    ["core/Errors.lua"]=3, ["core/LoadoutEvidence.lua"]=1,
    ["core/Main.lua"]=1, ["core/Store.lua"]=1, ["core/Sync.lua"]=1,
    ["core/Updates.lua"]=2, ["ui/Panel.lua"]=4, ["ui/QuickStart.lua"]=2,
    ["ui/ServerStatus.lua"]=3,
}
for path, runtimeText in pairs(runtimeFiles) do
    local _, writes = runtimeText:gsub("NexusDB%s*=%s*[^=]", "")
    assert(writes == (expectedCurrentWrites[path] or 0),
        "unexpected direct NexusDB write count in " .. path)
end
assert(legacyClearWrites == 1 and storeCurrentBindWrites == 1
    and markerNamespaceWrites == 1 and markerKeyWrites == 1
    and completionCall > compactionCall,
    "runtime has another bind/marker/clear owner or completes before owners")

-- Real bootstrap must honor Store's failure boundary. These overwrite-capable
-- stubs prove neither persistent error nor diagnostic ownership runs after the
-- malformed-current decision fails during either lifecycle event.
local errorWrites, diagnosticWrites = 0, 0
Nexus.Errors = {
    SafeText=function(value) return tostring(value) end,
    Record=function()
        errorWrites = errorWrites + 1
        NexusDB = {}
        return true
    end,
}
Nexus.DiagnosticLogs = {Init=function()
    diagnosticWrites = diagnosticWrites + 1
    NexusDB = {}
    return true
end}
Nexus.Model, Nexus.Policy, Nexus.Ratchet, Nexus.Strategy = {}, {}, {}, {}
Nexus.GameAdapter, Nexus.Readout, Nexus.Panel, Nexus.JournalTab = {}, {}, {}, {}
dofile("ui/Changelog.lua")
local changelogEvent = H.eventHandlers[#H.eventHandlers]
local changelogUpdate = H.updateHandlers[#H.updateHandlers]
dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")
local mainEvent = H.eventHandlers[#H.eventHandlers]
assert(type(changelogEvent) == "function" and type(changelogUpdate) == "function"
    and type(mainEvent) == "function", "bootstrap handlers were not registered")
local bootstrapCurrent = false
local bootstrapLegacy = BasicRoot("bootstrap-legacy")
NexusDB = bootstrapCurrent
WishlistRealizerDB = bootstrapLegacy
mainEvent(nil, "ADDON_LOADED", "Nexus")
changelogEvent(nil, "PLAYER_ENTERING_WORLD")
mainEvent(nil, "PLAYER_ENTERING_WORLD")
changelogUpdate(nil, 2.1)
assert(NexusDB == bootstrapCurrent and WishlistRealizerDB == bootstrapLegacy
    and Marker(bootstrapLegacy) == nil
    and errorWrites == 0 and diagnosticWrites == 0
    and tostring(Nexus.lastError):find("NexusDB is malformed", 1, true),
    "bootstrap diagnostics or delayed Changelog bypassed Store failure preservation")

print("legacy SavedVariables retirement is ordered, lossless, and idempotent -- OK")
