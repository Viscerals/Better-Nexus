-- Shared real-owner fixture for Stage 18 Echo-refresh characterization.
-- It instruments fixed aggregate counters only; production code stays unchanged.
local F = {}
local H = dofile("tests/harness.lua")
F.H = H

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
dofile("ui/JournalTab.lua")

local counts = {
    compiles=0,wishlistKeys=0,catalog=0,wishlist=0,slots=0,owned=0,
    locked=0,disabled=0,boards=0,policy=0,progress=0,hudModels=0,
    panelRenders=0,statusUpdates=0,associationRefreshes=0,uploads=0,
}
F.counts = counts

local function Wrap(owner, name, key)
    local original = assert(owner[name], "missing production owner: " .. name)
    owner[name] = function(...)
        counts[key] = counts[key] + 1
        return original(...)
    end
    return original
end

Wrap(Nexus.Strategy, "Compile", "compiles")
Wrap(Nexus.GameAdapter, "WishlistKey", "wishlistKeys")
local realCatalog = assert(Nexus.GameAdapter.Catalog)
Nexus.GameAdapter.Catalog = function(...)
    local trace = debug and debug.traceback and debug.traceback("", 2) or ""
    local runtimeAt = trace:find("AutomationRuntime.lua", 1, true)
    local adapterAt = trace:find("GameAdapter.lua", 1, true)
    if runtimeAt and (not adapterAt or runtimeAt < adapterAt) then
        counts.catalog = counts.catalog + 1
    end
    return realCatalog(...)
end
Wrap(Nexus.GameAdapter, "Wishlist", "wishlist")
Wrap(Nexus.GameAdapter, "Slots", "slots")
Wrap(Nexus.GameAdapter, "Owned", "owned")
Wrap(Nexus.GameAdapter, "LockedOwned", "locked")
Wrap(Nexus.GameAdapter, "DisabledLevers", "disabled")
Wrap(Nexus.GameAdapter, "Board", "boards")
Wrap(Nexus.GameAdapter, "UploadWishlist", "uploads")
Wrap(Nexus.Policy, "Decide", "policy")
Wrap(Nexus.Panel, "Render", "panelRenders")

local statusValue
local realSetStatus = assert(Nexus.Panel.SetStatus)
Nexus.Panel.SetStatus = function(value, ...)
    counts.statusUpdates = counts.statusUpdates + 1
    statusValue = tostring(value or "")
    return realSetStatus(value, ...)
end

local realAssociations = assert(Nexus.JournalTab.RefreshAssociations)
Nexus.JournalTab.RefreshAssociations = function(...)
    counts.associationRefreshes = counts.associationRefreshes + 1
    return realAssociations(...)
end

local signatureFields = {
    "service", "level", "slots", "activeSlot", "granted", "locked",
    "discovery", "tomeSafety", "state", "settings", "associations",
    "association", "firstRun", "catalogRevision",
}
local signatureMismatches = {}
for _, field in ipairs(signatureFields) do signatureMismatches[field] = 0 end
local lastSignature, lastMismatchReason
local realAutomationSignature = assert(Nexus.GameAdapter.AutomationSignature)
Nexus.GameAdapter.AutomationSignature = function(...)
    local signature = realAutomationSignature(...)
    local observed
    if type(signature) == "table" then
        observed = {}
        for _, field in ipairs(signatureFields) do
            observed[field] = signature[field]
        end
        local revisions = Nexus and Nexus.Revisions
        observed.catalogRevision = revisions and revisions.Get
            and revisions.Get(revisions.CATALOG_CHANGED) or 0
    end
    if lastSignature and observed then
        for _, field in ipairs(signatureFields) do
            if lastSignature[field] ~= observed[field] then
                signatureMismatches[field] = signatureMismatches[field] + 1
                lastMismatchReason = "fallback:" .. field
            end
        end
    end
    lastSignature = observed
    return signature
end

local dirtyReasons = {board=0,slots=0,data=0,autoLock=0}
local lastDirtyReason
local realConsumeDirty = assert(Nexus.GameAdapter.ConsumeDirty)
Nexus.GameAdapter.ConsumeDirty = function(...)
    local board, slots, data, autoLock,
        slotsRevision, activeSlotRevision, grantedRevision, ownedRevision,
        lockedRevision, lockedLocalRevision, discoveryRevision, leverRevision,
        staticDirty, levelEvents, runBoundaryGeneration = realConsumeDirty(...)
    for _, row in ipairs({
        {"board",board},{"slots",slots},{"data",data},{"autoLock",autoLock},
    }) do
        if row[2] then
            dirtyReasons[row[1]] = dirtyReasons[row[1]] + 1
            lastDirtyReason = "dirty:" .. row[1]
        end
    end
    return board, slots, data, autoLock,
        slotsRevision, activeSlotRevision, grantedRevision, ownedRevision,
        lockedRevision, lockedLocalRevision, discoveryRevision, leverRevision,
        staticDirty, levelEvents, runBoundaryGeneration
end

local wishlistEchoes, savedEchoes = {}, {}
for index = 1, 85 do
    local spellId = ({200100,200102,200104})[(index - 1) % 3 + 1]
    wishlistEchoes[index] = {spellId=spellId,quality=3,stacks=1}
    savedEchoes[index] = {spellId=spellId,quality=3,stacks=1}
end

local slots = {}
for slot = 1, 5 do
    local echoes = {}
    for index, echo in ipairs(savedEchoes) do
        echoes[index] = {
            spellId=echo.spellId,quality=echo.quality,stacks=echo.stacks,
        }
    end
    slots[slot] = {
        slot=slot,name="Echo Refresh Slot " .. slot,verified=true,echoes=echoes,
    }
end

NexusDB = {
    settings={autoPick=true,autoLockEchoes=true},
    chars={},communityBuilds={},buildFilters={},dpsCapture={},
}
H.playerLevel = 80
H.wishlist = {name="Echo Refresh Fixture",class="MAGE",echoes=wishlistEchoes}
H.granted = {
    ["Alpha Strike"]={{spellId=200100,quality=3}},
    ["Beta Guard"]={{spellId=200102,quality=2}},
}
H.locked = {{spellId=200104,quality=2,stack=1}}
H.discovered = {[200100]=true,[200102]=true,[200104]=true}
H.DeliverSlots(slots, 1)

dofile("core/AutomationRuntime.lua")
local runtimeFactory = assert(Nexus.MainInternals.AutomationRuntime.New)
Nexus.MainInternals.AutomationRuntime.New = function(options)
    local runtime = runtimeFactory(options)
    F.runtime = runtime
    return runtime
end
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/MainViewModel.lua")
local viewFactory = assert(Nexus.MainInternals.ViewModel.New)
Nexus.MainInternals.ViewModel.New = function(options)
    local viewModel = viewFactory(options)
    local progress = assert(viewModel.BuildProgress)
    viewModel.BuildProgress = function(...)
        counts.progress = counts.progress + 1
        return progress(...)
    end
    local hud = assert(viewModel.BuildHudDisplayModel)
    viewModel.BuildHudDisplayModel = function(...)
        counts.hudModels = counts.hudModels + 1
        return hud(...)
    end
    return viewModel
end
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")

-- Establish a current baseline immediately before each test's measured work.
H.Advance(1, 0.2)
assert(Nexus.RequestRecompute())
H.Advance(0.2, 0.2)

local recomputeKeys = {
    "polls","fullSteps","fallbacks","dirty","deadlines","forced","explicit",
    "staticProbes","planCompiles","wishlistFingerprints",
    "lockContextRebuilds","autoLockEvaluations",
}

local function CopyFixed(source)
    local out = {}
    for key, value in pairs(source) do out[key] = value end
    return out
end

function F.Snapshot()
    local out = {}
    for key, value in pairs(counts) do out[key] = value end
    local recompute = Nexus.RecomputeStats()
    for _, key in ipairs(recomputeKeys) do
        out[key] = tonumber(recompute[key]) or 0
    end
    out.actions = #H.selectCalls + #H.banishCalls + #H.freezeCalls
        + H.rerollCalls + #H.activateCalls + #H.saveCalls
    out.characterMutations = out.actions + #H.wire
    out.uploads = counts.uploads
    out.syncBuildUploads = 0
    for _, message in ipairs(H.sentChatMessages) do
        local text = tostring(message.text or "")
        if text:find("^WLRB|") or text:find("^WLBI|") then
            out.syncBuildUploads = out.syncBuildUploads + 1
        end
    end
    out.slotRequests = H.slotRequests or 0
    out.echoNotifications = H.echoDataChangeNotifications or 0
    out.fallbackChecks = Nexus.Performance.Stats("automation.fallback.check").count
    out.fallbackRepairs = Nexus.Performance.Stats("automation.fallback.repair").count
    out.signatureMismatches = CopyFixed(signatureMismatches)
    out.dirtyReasons = CopyFixed(dirtyReasons)
    out.runtimeMismatchFields = CopyFixed(recompute.fallbackMismatchFields or {})
    out.runtimeFullStepTriggers = CopyFixed(recompute.fullStepTriggers or {})
    local echo = recompute.echoReconcile or Nexus.GameAdapter.EchoReconcileStats()
    out.echoReconcile = {}
    for _, key in ipairs({
        "slotRequests","notifications","reconciliations","scans","cacheHits",
        "equivalentNotifications","equivalentFallbacks","semanticChanges",
        "failures","associationRefreshes",
    }) do
        out.echoReconcile[key] = tonumber(echo[key]) or 0
    end
    out.echoReconcile.lastReason = tostring(echo.lastReason or "")
    out.echoGenerations = CopyFixed(echo.generations or {})
    out.echoFieldChanges = CopyFixed(echo.fieldChanges or {})
    out.echoDirtyReasons = CopyFixed(echo.dirtyReasons or {})
    out.lastReason = lastDirtyReason or lastMismatchReason
    out.statusValue = statusValue
    return out
end

function F.Delta(after, before, key)
    return (after[key] or 0) - (before[key] or 0)
end

function F.FixedDelta(after, before, group, key)
    return ((after[group] or {})[key] or 0)
        - ((before[group] or {})[key] or 0)
end

return F
