-- Nexus: core/Main.lua
-- Thin bootstrap/coordinator. Internal owners retain diagnostics, display
-- projection, commands, automation, and lifecycle/event state.
-- SCOPING RULE: every closure-captured local is declared here, before
-- any closure that reads it.

Nexus = Nexus or {}
Nexus.VERSION = (Nexus.Release and Nexus.Release.version) or "1.20.0-beta.1"

local Model, Policy, Ratchet, Strategy, Store, Adapter
local Readout, Panel, JournalTab, DefaultProfile
local AutomationRuntime, MainLifecycle, MainCommands, MainDiagnostics, MainViewModel
local EnsureAutomationRuntime, EnsureMainLifecycle, EnsureMainCommands
local EnsureMainDiagnostics, EnsureMainViewModel

-- ARM state
local EH  -- event frame
local lastPanelInput = nil
local panelProgressCache = {valid=false}
local selectedPreviewCache = {valid=false}
local activeFingerprintCache = {valid=false}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff7fd5ffNexus:|r " .. tostring(msg))
end

local function ErrorText(value)
    local errors = Nexus and Nexus.Errors
    if errors and type(errors.SafeText) == "function" then
        local ok, text = pcall(errors.SafeText, value)
        if ok and type(text) == "string" then return text end
    end
    local ok, text = pcall(tostring, value)
    return ok and text or "<unprintable error>"
end

local function RecordError(source, value)
    local errors = Nexus and Nexus.Errors
    if errors and type(errors.Record) == "function" then
        local ok = pcall(errors.Record, source, value)
        if ok then return end
    end
    Nexus.lastError = ErrorText(value)
end

-- Store failure means persistence authority is unresolved. Keep that error in
-- session memory only: persistent diagnostic fallbacks may otherwise replace a
-- malformed root before Store can preserve it for recovery.
local function RecordStoreError(value)
    Nexus.lastError = ErrorText(value)
end

EnsureMainViewModel = function()
    if MainViewModel then return MainViewModel end
    local internals = Nexus.MainInternals
    local factory = internals and internals.ViewModel
    if not (factory and type(factory.New) == "function") then return nil end
    local ratchet = Ratchet or Nexus.Ratchet
    if not ratchet then return nil end
    MainViewModel = factory.New({ratchet=ratchet,model=Model or Nexus.Model})
    return MainViewModel
end

local function Automation()
    return EnsureAutomationRuntime and EnsureAutomationRuntime()
end

local function Lifecycle()
    return EnsureMainLifecycle and EnsureMainLifecycle()
end

local function StatusLine()
    local runtime = Automation()
    return runtime and runtime.StatusLine() or "loading"
end

local function RequestRecompute()
    local runtime = Automation()
    return runtime and runtime.RequestRecompute() or false
end

Nexus.RequestRecompute = RequestRecompute

local function RetryAutoLock()
    local runtime = Automation()
    return runtime and runtime.RetryAutoLock() or false
end

Nexus.RetryAutoLock = RetryAutoLock

function Nexus.RecomputeStats()
    local runtime = Automation()
    return runtime and runtime.RecomputeStats()
        or {polls=0,fullSteps=0,skipped=0,forced=0,dirty=0,
            deadlines=0,fallbacks=0,explicit=0,nextStepAt=nil,
            nextAutoLockAt=nil,lastFullStepAt=-math.huge,
            lastStaticProbeAt=-math.huge,fallbackSeconds=5,
            planCompiles=0,planReuses=0,staticProbes=0,
            wishlistFingerprints=0,lockContextRebuilds=0,
            autoLockEvaluations=0,pollFailures=0,autoEnabled=false,
            autoLockLifecycle={prepared=0,submitted=0,
                awaitingConfirmation=0,confirmed=0,rejected=0,expired=0,
                superseded=0,spacingRetries=0,explicitRetries=0,
                postExpiryBlocked=0},
            lastAutoLockLifecycle={state="idle",reason="none",error="none",
                spellId=0,replaces=0,lockedRevision=0,adapterAttempts=0,
                preparedAt=0,submittedAt=0,expiresAt=0,resolvedAt=0},
            autoLockCapacity={used=0,maximum=0,known=false,
                source="unavailable",synced=false}}
end

local function AppendAudit(kind, fields)
    local diagnostics = EnsureMainDiagnostics and EnsureMainDiagnostics()
    return diagnostics and diagnostics.AppendAudit(kind, fields) or false
end
Nexus.AppendAudit = AppendAudit

local function AppendAutoLockEvent(fields)
    local diagnostics = EnsureMainDiagnostics and EnsureMainDiagnostics()
    return diagnostics and diagnostics.AppendAutoLockEvent(fields) or false
end

local function EffectiveFlags()
    local runtime = Automation()
    return runtime and runtime.EffectiveFlags() or {}
end

local function AutoAllowed()
    local runtime = Automation()
    if not runtime then return false, "manual mode" end
    return runtime.AutoAllowed()
end

local function LockDesignTargetsFor(wishlist)
    local runtime = Automation()
    return runtime and runtime.LockDesignTargetsFor(wishlist) or nil
end

local function WishlistWithLockTargets(wishlist, catalog)
    local runtime = Automation()
    return runtime and runtime.WishlistWithLockTargets(wishlist, catalog)
        or wishlist
end

local function WishlistProgress(plan, owned, catalog, lockOnlyFamilies, wishlist)
    local runtime = Automation()
    if not runtime then return 0, 0, {}, {} end
    return runtime.WishlistProgress(plan, owned, catalog, lockOnlyFamilies, wishlist)
end

local function LoadoutCoverage(activeRow, plan, catalog)
    local viewModel = EnsureMainViewModel and EnsureMainViewModel()
    if not viewModel then return {}, nil, {} end
    return viewModel.LoadoutCoverage(activeRow, plan, catalog)
end

-- Builds the one progress table every render site feeds to the panel:
-- this run's gains, the active loadout's convergence toward the ideal
-- wishlist, and the loadout's specific missing echoes (what "close to
-- ideal" actually means, not just a percentage).
local function BuildProgress(plan, owned, slots, catalog, wishlistOverride,
    previewBuildId, staticContext, lockedOverride)
    local viewModel = EnsureMainViewModel and EnsureMainViewModel()
    if not viewModel then return {} end
    -- A static snapshot may intentionally contain no wishlist. Preserve that
    -- known-nil result instead of turning it into an uncached Adapter read on
    -- every panel render.
    local wishlist = wishlistOverride
    if wishlist == nil then
        if type(staticContext) == "table" then
            wishlist = staticContext.wishlist
        else
            wishlist = Adapter.Wishlist()
        end
    end
    local lockedOwned = lockedOverride
    if lockedOwned == nil and Adapter.LockedOwned then
        lockedOwned = Adapter.LockedOwned()
    end
    local designTargets
    if not wishlistOverride and type(staticContext) == "table" then
        designTargets = staticContext.targets
    else
        designTargets = LockDesignTargetsFor(wishlist)
    end
    local matchedBuildId = nil
    local capture = Nexus.DpsCapture
    if capture and capture.FindMatchingBuildPublic and wishlist then
        matchedBuildId = capture.FindMatchingBuildPublic(wishlist)
    end
    local wishlistEchoes = wishlist and (wishlist.echoes or wishlist.entries) or nil
    local tomeEchoes = viewModel.TomeEchoes(wishlistEchoes, designTargets)
    local unknownTomes = Adapter.UnknownTomesForEchoes
        and Adapter.UnknownTomesForEchoes(tomeEchoes) or {}
    return viewModel.BuildProgress({
        plan=plan,owned=owned,slots=slots,catalog=catalog,wishlist=wishlist,
        lockedOwned=lockedOwned,designTargets=designTargets,
        unknownTomes=unknownTomes,matchedBuildId=matchedBuildId,
        previewBuildId=previewBuildId,
    })
end

local function ExactEchoFingerprint(echoes)
    local capture = Nexus and Nexus.DpsCapture
    if not (capture and type(capture.GetEchoKey) == "function") then
        return nil
    end
    local ok, fingerprint = pcall(capture.GetEchoKey, echoes)
    return ok and type(fingerprint) == "string" and fingerprint or nil
end

local function ReadSelectedPanelKey()
    local community = Nexus and Nexus.CommunityBuilds
    local reader = community and community.GetSelectedBuildForPanelKey
    if type(reader) ~= "function" then return false end
    local ok, id, epoch, revision = pcall(reader)
    if not ok or type(epoch) ~= "number" then return false end
    return true, id, epoch, tonumber(revision) or 0
end

local function ReadPanelRevisions()
    local reader = Adapter and Adapter.PresentationRevisions
    if type(reader) ~= "function" then return false end
    local ok, slotsRevision, activeRevision, grantedRevision,
        ownedRevision, wishlistRevision, catalogRevision,
        lockedRevision, lockedLocalRevision, discoveryRevision,
        leverRevision, levelBoundary = pcall(reader)
    if not ok then return false end
    if type(slotsRevision) ~= "number"
        or type(activeRevision) ~= "number"
        or type(grantedRevision) ~= "number"
        or type(ownedRevision) ~= "number"
        or type(wishlistRevision) ~= "number"
        or type(catalogRevision) ~= "number"
        or type(lockedRevision) ~= "number"
        or type(lockedLocalRevision) ~= "number"
        or type(discoveryRevision) ~= "number"
        or type(leverRevision) ~= "number"
        or type(levelBoundary) ~= "number" then
        return false
    end
    return true,slotsRevision,activeRevision,grantedRevision,ownedRevision,
        wishlistRevision,catalogRevision,lockedRevision,lockedLocalRevision,
        discoveryRevision,leverRevision,levelBoundary
end

local function ReadExactRevision(fingerprint)
    local catalogOwner = Nexus and Nexus.BuildCatalog
    local reader = catalogOwner and catalogOwner.ExactFingerprintRevision
    if type(reader) ~= "function" then return false end
    local ok, epoch, revision = pcall(reader, fingerprint)
    if not ok or type(epoch) ~= "number" or type(revision) ~= "number" then
        return false
    end
    return true, epoch, revision
end

local function ActiveFingerprint(staticContext)
    if type(staticContext) ~= "table" or staticContext.key == nil then
        return nil
    end
    if activeFingerprintCache.valid
        and activeFingerprintCache.key == staticContext.key then
        return activeFingerprintCache.fingerprint
    end
    local wishlist = staticContext.wishlist
    local echoes = wishlist and (wishlist.echoes or wishlist.entries) or nil
    activeFingerprintCache.valid = true
    activeFingerprintCache.key = staticContext.key
    activeFingerprintCache.fingerprint = ExactEchoFingerprint(echoes)
    return activeFingerprintCache.fingerprint
end

local function SelectedPreview(selectionId, selectionEpoch,
    selectionRevision, catalog, staticContext)
    if selectionId == nil then return nil, nil, nil end
    local staticKey = type(staticContext) == "table" and staticContext.key or nil
    if selectedPreviewCache.valid
        and selectedPreviewCache.id == selectionId
        and selectedPreviewCache.epoch == selectionEpoch
        and selectedPreviewCache.revision == selectionRevision
        and selectedPreviewCache.catalog == catalog
        and selectedPreviewCache.staticKey == staticKey then
        return selectedPreviewCache.plan, selectedPreviewCache.wishlist,
            selectedPreviewCache.fingerprint
    end
    local community = Nexus and Nexus.CommunityBuilds
    local getter = community and community.GetSelectedBuildForPanel
    local build = type(getter) == "function" and getter() or nil
    local wishlist, plan, fingerprint
    if build and type(build.echoes) == "table" and #build.echoes > 0 then
        wishlist = {
            name=build.title or "Community Build", entries=build.echoes,
        }
        plan = Strategy.Compile(catalog, wishlist, Store.Settings())
        fingerprint = ExactEchoFingerprint(build.echoes)
    end
    selectedPreviewCache.valid = true
    selectedPreviewCache.id = selectionId
    selectedPreviewCache.epoch = selectionEpoch
    selectedPreviewCache.revision = selectionRevision
    selectedPreviewCache.catalog = catalog
    selectedPreviewCache.staticKey = staticKey
    selectedPreviewCache.plan = plan
    selectedPreviewCache.wishlist = wishlist
    selectedPreviewCache.fingerprint = fingerprint
    return plan, wishlist, fingerprint
end

local function SamePanelProgressKey(cache, activePlan, catalog, staticKey,
    selectionId, selectionEpoch, selectionRevision,
    slotsRevision, activeRevision, grantedRevision, ownedRevision,
    wishlistRevision, catalogRevision, lockedRevision, lockedLocalRevision,
    discoveryRevision, leverRevision, levelBoundary,
    exactEpoch, exactRevision)
    return cache.valid and cache.activePlan == activePlan
        and cache.catalog == catalog and cache.staticKey == staticKey
        and cache.selectionId == selectionId
        and cache.selectionEpoch == selectionEpoch
        and cache.selectionRevision == selectionRevision
        and cache.slotsRevision == slotsRevision
        and cache.activeRevision == activeRevision
        and cache.grantedRevision == grantedRevision
        and cache.ownedRevision == ownedRevision
        and cache.wishlistRevision == wishlistRevision
        and cache.catalogRevision == catalogRevision
        and cache.lockedRevision == lockedRevision
        and cache.lockedLocalRevision == lockedLocalRevision
        and cache.discoveryRevision == discoveryRevision
        and cache.leverRevision == leverRevision
        and cache.levelBoundary == levelBoundary
        and cache.exactEpoch == exactEpoch
        and cache.exactRevision == exactRevision
end

local function StorePanelProgressKey(cache, value, activePlan, catalog,
    staticKey, selectionId, selectionEpoch, selectionRevision,
    slotsRevision, activeRevision, grantedRevision, ownedRevision,
    wishlistRevision, catalogRevision, lockedRevision, lockedLocalRevision,
    discoveryRevision, leverRevision, levelBoundary,
    exactEpoch, exactRevision)
    cache.valid, cache.value = true, value
    cache.activePlan, cache.catalog, cache.staticKey = activePlan, catalog, staticKey
    cache.selectionId = selectionId
    cache.selectionEpoch, cache.selectionRevision = selectionEpoch, selectionRevision
    cache.slotsRevision, cache.activeRevision = slotsRevision, activeRevision
    cache.grantedRevision, cache.ownedRevision = grantedRevision, ownedRevision
    cache.wishlistRevision, cache.catalogRevision = wishlistRevision, catalogRevision
    cache.lockedRevision, cache.lockedLocalRevision = lockedRevision, lockedLocalRevision
    cache.discoveryRevision, cache.leverRevision = discoveryRevision, leverRevision
    cache.levelBoundary = levelBoundary
    cache.exactEpoch, cache.exactRevision = exactEpoch, exactRevision
end

local function BuildPanelProgress(activePlan, owned, slots, catalog,
    staticContext, lockedOverride)
    local selectedOK, selectionId, selectionEpoch, selectionRevision =
        ReadSelectedPanelKey()
    local revisionsOK, slotsRevision, activeRevision, grantedRevision,
        ownedRevision, wishlistRevision, catalogRevision,
        lockedRevision, lockedLocalRevision, discoveryRevision,
        leverRevision, levelBoundary = ReadPanelRevisions()
    local staticKey = type(staticContext) == "table" and staticContext.key or nil
    if selectedOK and revisionsOK and staticKey ~= nil then
        local previewPlan, previewWishlist, fingerprint = SelectedPreview(
            selectionId, selectionEpoch, selectionRevision, catalog,
            staticContext)
        fingerprint = fingerprint or ActiveFingerprint(staticContext)
        local exactOK, exactEpoch, exactRevision =
            ReadExactRevision(fingerprint)
        if exactOK and SamePanelProgressKey(panelProgressCache,
            activePlan, catalog, staticKey, selectionId, selectionEpoch,
            selectionRevision, slotsRevision, activeRevision,
            grantedRevision, ownedRevision, wishlistRevision,
            catalogRevision, lockedRevision, lockedLocalRevision,
            discoveryRevision, leverRevision, levelBoundary,
            exactEpoch, exactRevision) then
            return panelProgressCache.value
        end
        if exactOK then
            local value
            if previewPlan and previewWishlist then
                value = BuildProgress(previewPlan, owned, slots, catalog,
                    previewWishlist, selectionId, nil, lockedOverride)
            else
                value = BuildProgress(activePlan, owned, slots, catalog,
                    nil, nil, staticContext, lockedOverride)
            end
            StorePanelProgressKey(panelProgressCache, value,
                activePlan, catalog, staticKey, selectionId, selectionEpoch,
                selectionRevision, slotsRevision, activeRevision,
                grantedRevision, ownedRevision, wishlistRevision,
                catalogRevision, lockedRevision, lockedLocalRevision,
                discoveryRevision, leverRevision, levelBoundary,
                exactEpoch, exactRevision)
            return value
        end
    end

    -- Compatibility path for partial/injected facades without the complete
    -- scalar revision contract. It retains the established defensive reads.
    local community = Nexus.CommunityBuilds
    local build = community and community.GetSelectedBuildForPanel
        and community.GetSelectedBuildForPanel()
    if build and type(build.echoes) == "table" and #build.echoes > 0 then
        local wishlist = {
            name=build.title or "Community Build", entries=build.echoes,
        }
        local previewPlan = Strategy.Compile(catalog, wishlist, Store.Settings())
        return BuildProgress(previewPlan, owned, slots, catalog, wishlist,
            build.id, nil, lockedOverride)
    end
    return BuildProgress(activePlan, owned, slots, catalog,
        nil, nil, staticContext, lockedOverride)
end

local function CopyDisplay(value)
    local viewModel = EnsureMainViewModel and EnsureMainViewModel()
    return viewModel and viewModel.Copy(value) or value
end

local function DisplayCall(callback, ...)
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, ...)
    return ok and value or nil
end

-- Main owns every service read used by the adaptive HUD. Panel receives only
-- this defensive display snapshot and never reaches back into data services
-- while rendering it.
local function BuildHudDisplayModel(base)
    local viewModel = EnsureMainViewModel and EnsureMainViewModel()
    if not viewModel then return type(base) == "table" and base or {} end
    -- Preserve the old snapshot boundary: the panel input and each service
    -- result are copied when read, before a later provider can mutate them.
    local baseSnapshot = viewModel.Copy(type(base) == "table" and base or {})
    local input = {base=baseSnapshot,status=StatusLine()}
    if baseSnapshot.level == nil then
        input.level = DisplayCall(Adapter and Adapter.Level) or 0
    end

    local updates = Nexus.Updates
    input.updateNotice = viewModel.Copy(
        updates and DisplayCall(updates.GetVisibleNotice))
    if input.updateNotice and updates then input.releaseUrl = DisplayCall(updates.ReleaseUrl) end

    local server = Nexus.ServerStatus
    input.useServerStatus = server and DisplayCall(server.IsUsingNexusHud) and true or false
    if input.useServerStatus then
        input.serverStatus = viewModel.Copy(DisplayCall(server.GetSummary))
    end

    local capture = Nexus.DpsCapture
    local player = UnitName and UnitName("player") or nil
    input.bestDps = {
        dummy=viewModel.Copy(capture and DisplayCall(
            capture.GetCharacterBest, "dummy", player)),
        lk=viewModel.Copy(capture and DisplayCall(
            capture.GetCharacterBest, "lk", player)),
        info=viewModel.Copy(capture and DisplayCall(capture.GetPlayerInfo, player)),
    }
    local progress = type(baseSnapshot.progress) == "table"
        and baseSnapshot.progress or {}
    local echoes = type(progress.dpsEchoes) == "table" and progress.dpsEchoes or nil
    input.performance = {dummy={},lk={}}
    if capture and echoes then
        input.performance.dummy.personal = viewModel.Copy(DisplayCall(
            capture.GetPersonalBestForEchoes, echoes, "dummy"))
        input.performance.lk.personal = viewModel.Copy(DisplayCall(
            capture.GetPersonalBestForEchoes, echoes, "lk"))
        local dummyRows = DisplayCall(capture.GetLeaderboardForEchoes, echoes, "dummy")
        local lkRows = DisplayCall(capture.GetLeaderboardForEchoes, echoes, "lk")
        input.performance.dummy.global = viewModel.Copy(
            type(dummyRows) == "table" and dummyRows[1] or nil)
        input.performance.lk.global = viewModel.Copy(
            type(lkRows) == "table" and lkRows[1] or nil)
    end
    return viewModel.BuildHudDisplayModel(input)
end

local function PrepareHudDisplayModel(base)
    local performance = Nexus and Nexus.Performance
    if performance and type(performance.Measure) == "function" then
        return performance.Measure("hud.prepare", BuildHudDisplayModel, base)
    end
    return BuildHudDisplayModel(base)
end

local function PreparePanelModel(base, source)
    local ok, prepared = pcall(PrepareHudDisplayModel, base)
    if not ok then
        RecordError(source .. ".Prepare", prepared)
        return nil, prepared
    end
    return prepared
end

local function RenderPreparedPanel(prepared, source)
    local ok, result = pcall(Panel.Render, prepared)
    if not ok then
        RecordError(source .. ".Render", result)
        return false, result
    end
    return result ~= false
end

local function RenderPanel(base)
    lastPanelInput = CopyDisplay(base)
    local prepared, prepareError = PreparePanelModel(
        lastPanelInput, "Main.RenderPanel")
    if not prepared then error(prepareError, 0) end
    local rendered, renderError = RenderPreparedPanel(
        prepared, "Main.RenderPanel")
    if renderError then error(renderError, 0) end
    return rendered
end

function Nexus.RefreshHudView()
    if not Panel or type(Panel.Render) ~= "function" then
        return false
    end
    if not lastPanelInput then return false end
    local viewModel = EnsureMainViewModel and EnsureMainViewModel()
    if viewModel then viewModel.NoteRefresh() end
    local prepared = PreparePanelModel(lastPanelInput, "Main.RefreshHudView")
    if not prepared then return false end
    return RenderPreparedPanel(prepared, "Main.RefreshHudView")
end

local function RequestFirstHudView()
    if lastPanelInput then return Nexus.RefreshHudView() end
    -- Manual Show/Toggle can precede the first ordinary automation snapshot.
    -- Request that existing bounded owner and keep Panel hidden; never run a
    -- second provider loop or a stateful full Step from a visibility callback.
    RequestRecompute()
    return false
end

function Nexus.HudSnapshotStats()
    local viewModel = EnsureMainViewModel and EnsureMainViewModel()
    return viewModel and viewModel.Stats()
        or {builds=0,refreshes=0,rebuilds=0,skipped=0}
end

-- Renders the panel with just status + progress, no board cards. Used at
-- every point in Step() where StepRun isn't running this tick (level 1,
-- level 80 with no board, or catalog not yet loaded) -- otherwise the
-- panel only ever refreshes while an echo board is live and freezes
-- showing stale leveling-era content the rest of the time, which breaks
-- both "check status at level 80" and "alt-tab between characters".
-- All args may be nil; WishlistProgress/LoadoutCoverage are null-safe.
local function RenderIdlePanel(plan, owned, slots, catalog, staticContext,
    lockedOverride)
    local settings = Store.Settings()
    local okAuto = AutoAllowed()
    RenderPanel({
        status = StatusLine(),
        cards = {},
        recommendation = "",
        progress = BuildPanelProgress(plan, owned, slots, catalog,
            staticContext, lockedOverride),
        level = Adapter.Level(),
        auto = (Automation() and Automation().AutoEnabled()) or false,
        version = Nexus.VERSION,
    })
end

------------------------------------------------------------------------
-- Init + events + slash
------------------------------------------------------------------------


EnsureAutomationRuntime = function()
    if AutomationRuntime then return AutomationRuntime end
    local internals = Nexus.MainInternals
    local factory = internals and internals.AutomationRuntime
    if not (factory and type(factory.New) == "function") then return nil end
    local viewModel = EnsureMainViewModel and EnsureMainViewModel()
    if not viewModel then return nil end
    AutomationRuntime = factory.New({
        nexus=Nexus,model=Model or Nexus.Model,policy=Policy or Nexus.Policy,
        ratchet=Ratchet or Nexus.Ratchet,strategy=Strategy or Nexus.Strategy,
        store=Store or Nexus.Store,adapter=Adapter or Nexus.GameAdapter,
        readout=Readout or Nexus.Readout,
        defaultProfile=DefaultProfile or Nexus.DefaultProfile,
        wishlistModel=assert(Nexus.WishlistModel,
            "WishlistModel unavailable").New(),
        viewModel=viewModel,renderPanel=RenderPanel,renderIdlePanel=RenderIdlePanel,
        buildProgress=BuildProgress,buildPanelProgress=BuildPanelProgress,
        appendAudit=AppendAudit,appendAutoLockEvent=AppendAutoLockEvent,
        print=Print,recordError=RecordError,now=GetTime,
        onStatus=function(value)
            if Panel and Panel.SetStatus then Panel.SetStatus(value) end
        end,
    })
    return AutomationRuntime
end

-- Main retains the public facades while one passive internal owner constructs
-- diagnostic pages, retained audit entries, clear routing, and export jobs.
EnsureMainDiagnostics = function()
    if MainDiagnostics then return MainDiagnostics end
    local internals = Nexus.MainInternals
    local factory = internals and internals.Diagnostics
    if not (factory and type(factory.New) == "function") then return nil end
    MainDiagnostics = factory.New({
        nexus=Nexus,
        adapter={
            Catalog=function(...) return (Adapter or Nexus.GameAdapter).Catalog(...) end,
            Wishlist=function(...) return (Adapter or Nexus.GameAdapter).Wishlist(...) end,
            WishlistNote=function(...) return (Adapter or Nexus.GameAdapter).WishlistNote(...) end,
            LockedOwned=function(...) return (Adapter or Nexus.GameAdapter).LockedOwned(...) end,
            Owned=function(...) return (Adapter or Nexus.GameAdapter).Owned(...) end,
            Slots=function(...) return (Adapter or Nexus.GameAdapter).Slots(...) end,
            Charges=function(...) return (Adapter or Nexus.GameAdapter).Charges(...) end,
            Level=function(...) return (Adapter or Nexus.GameAdapter).Level(...) end,
            LevelBurstStats=function(...)
                local owner = Adapter or Nexus.GameAdapter
                return owner.LevelBurstStats and owner.LevelBurstStats(...) or nil
            end,
        },
        model=Model or Nexus.Model,
        strategy=Strategy or Nexus.Strategy,
        store=Store or Nexus.Store,
        wishlistWithLockTargets=WishlistWithLockTargets,
        lockDesignTargetsFor=LockDesignTargetsFor,
        effectiveFlags=EffectiveFlags,
        errorText=ErrorText,
        now=GetTime,
        getAutoEnabled=function() local r=Automation(); return r and r.AutoEnabled() or false end,
        getAutoLockTrace=function() local r=Automation(); return r and r.LastAutoLockTrace() or {at=0,lines={}} end,
        getAuditRunId=function() local r=Automation(); return r and r.AuditRunId() or 0 end,
        getDatabase=function() return NexusDB end,
        ensureDatabase=function()
            NexusDB = NexusDB or {}
            return NexusDB
        end,
        resetAuditState=function()
            local runtime=Automation(); if runtime then runtime.ResetAuditState() end
        end,
        getPageProvider=function() return Nexus.GetDiagnosticPageText end,
    })
    return MainDiagnostics
end

function Nexus.NewAIExportCoroutine()
    local diagnostics = EnsureMainDiagnostics()
    if diagnostics then return diagnostics.NewAIExportCoroutine() end
    return coroutine.create(function() return "" end)
end

local function LogViewerProvider(tabKey)
    local diagnostics = EnsureMainDiagnostics()
    return diagnostics and diagnostics.GetPageText(tabKey)
        or ("unknown tab: " .. tostring(tabKey))
end

local function ClearDiagnosticLogs(tabKey)
    local diagnostics = EnsureMainDiagnostics()
    return diagnostics and diagnostics.Clear(tabKey) or false
end

function Nexus.GetDiagnosticPageText(tabKey)
    return LogViewerProvider(tabKey)
end

function Nexus.RefreshPanel()
    local lifecycle = Lifecycle()
    return lifecycle and lifecycle.RefreshPanel() or false
end

local function BindLifecycleDependencies()
    Model = Nexus.Model
    Policy = Nexus.Policy
    Ratchet = Nexus.Ratchet
    Strategy = Nexus.Strategy
    Store = Nexus.Store
    Adapter = Nexus.GameAdapter
    Readout = Nexus.Readout
    Panel = Nexus.Panel
    JournalTab = Nexus.JournalTab
    DefaultProfile = Nexus.DefaultProfile
    local internals = Nexus.MainInternals
    local automationFactory = internals and internals.AutomationRuntime
    local commandsFactory = internals and internals.Commands
    local diagnosticsFactory = internals and internals.Diagnostics
    local viewModelFactory = internals and internals.ViewModel
    if not (Model and Policy and Ratchet and Strategy and Store
        and Adapter and Readout and Panel and DefaultProfile
        and Nexus.DiagnosticLogs and diagnosticsFactory
        and type(diagnosticsFactory.New) == "function"
        and automationFactory and type(automationFactory.New) == "function"
        and commandsFactory and type(commandsFactory.New) == "function"
        and viewModelFactory and type(viewModelFactory.New) == "function") then
        return nil
    end
    return {
        Model=Model, Policy=Policy, Ratchet=Ratchet, Strategy=Strategy,
        Store=Store, Adapter=Adapter, Readout=Readout, Panel=Panel,
        JournalTab=JournalTab, DefaultProfile=DefaultProfile,
    }
end

EnsureMainLifecycle = function()
    if MainLifecycle then return MainLifecycle end
    local internals = Nexus.MainInternals
    local factory = internals and internals.Lifecycle
    if not (factory and type(factory.New) == "function") then return nil end
    MainLifecycle = factory.New({
        nexus=Nexus,
        bindDependencies=BindLifecycleDependencies,
        ensureAutomation=function() return Automation() end,
        print=Print,
        recordError=RecordError,
        recordStoreError=RecordStoreError,
        errorText=ErrorText,
        requestRecompute=RequestRecompute,
        refreshHud=function() return Nexus.RefreshHudView() end,
        requestFirstHud=RequestFirstHudView,
        database=function() return NexusDB end,
        logViewerProvider=LogViewerProvider,
        clearDiagnosticLogs=ClearDiagnosticLogs,
        now=GetTime,
    })
    return MainLifecycle
end

EH = CreateFrame("Frame")
EH:RegisterEvent("ADDON_LOADED")
EH:RegisterEvent("PLAYER_ENTERING_WORLD")
EH:RegisterEvent("PLAYER_LEVEL_UP")
EH:RegisterEvent("CHAT_MSG_CHANNEL")
EH:RegisterEvent("PLAYER_REGEN_DISABLED")
EH:RegisterEvent("PLAYER_REGEN_ENABLED")
EH:SetScript("OnEvent", function(_, ...)
    local lifecycle = Lifecycle()
    if lifecycle then return lifecycle.OnEvent(...) end
end)
EH:RegisterEvent("CHAT_MSG_WHISPER")
EH:SetScript("OnUpdate", function(_, elapsed)
    local lifecycle = Lifecycle()
    if lifecycle then return lifecycle.OnUpdate(elapsed) end
end)

local function CommandAuto()
    local runtime = Automation()
    local enabled = runtime and runtime.ToggleAuto() or false
    Print("auto " .. (enabled and "ON" or "OFF"))
    if Panel.SetAuto then Panel.SetAuto(enabled) end
end

local function CommandRestore()
    Print(Adapter.RestoreAutoAccept() and "client auto-accept restored"
        or "nothing to restore")
    RequestRecompute()
end

local function CommandFlags()
    for k, v in pairs(EffectiveFlags()) do Print(k .. " = " .. tostring(v)) end
    local state = Store.State()
    for k, why in pairs(state.flagDemotions or {}) do
        Print("demoted " .. k .. ": " .. tostring(why))
    end
end

local function CommandStatus()
    local catalog = Adapter.Catalog()
    local wishlist = Adapter.Wishlist()
    local slots = Adapter.Slots()
    local owned = Adapter.Owned()
    Print("v" .. Nexus.VERSION .. " build=" .. Nexus.RuntimeBuildLabel()
        .. " -- level " .. Adapter.Level()
        .. ", auto " .. ((Automation() and Automation().AutoEnabled()) and "ON" or "OFF"))
    if wishlist then
        local source = (wishlist.source == "designed" and "Echo Wishlist build")
            or (wishlist.source == "active" and "active loadout") or "wishlist"
        Print(string.format("TARGET: |cff7fff7f'%s'|r (your %s) -- %d echoes",
            (wishlist.name ~= "" and wishlist.name) or "(unnamed)",
            source, #wishlist.entries))
    else
        local note = Adapter.WishlistNote and Adapter.WishlistNote()
        Print("TARGET: none -- advisor only" .. (note and ("  (" .. note .. ")") or ""))
    end
    if not slots then
        Print("LOADOUTS: slot data not loaded yet (waiting on the server).")
    else
        local snapshots, designs = 0, 0
        for _, slot in pairs(slots.bySlot) do
            if type(slot.echoes) == "table" and #slot.echoes > 0 then
                if slot.verified then snapshots = snapshots + 1 else designs = designs + 1 end
            end
        end
        local active = slots.activeSlot
        if active ~= 0 and slots.bySlot[active] then
            local slot = slots.bySlot[active]
            Print(string.format("ACTIVE slot %d '%s': %s, %d echoes", active,
                (slot.name ~= "" and slot.name) or "?",
                slot.verified and "snapshot (arms the guarantee)"
                    or "designed build (highlight only -- not a guarantee)",
                #slot.echoes))
        else
            Print("ACTIVE: no build activated right now.")
        end
        Print(string.format("READABLE: %d loadout snapshot(s), %d designed wishlist build(s)",
            snapshots, designs))
        if wishlist and Ratchet and Ratchet.BestSlot then
            local plan = Strategy.Compile(catalog, wishlist, Store.Settings())
            local best = Ratchet.BestSlot(slots, plan, catalog)
            Print(best and ("Would arm snapshot slot " .. best .. " at level 1.")
                or "No verified snapshot to arm -- first run seeds one.")
        end
    end
    Print(string.format("OWNED this run: %d echoes (%s).", owned.distinct or 0,
        owned.synced and "synced" or "not synced yet"))
end

local function CommandWishlist()
    local wishlist = Adapter.Wishlist()
    if not wishlist then
        local note = Adapter.WishlistNote and Adapter.WishlistNote()
        if note then
            Print(note)
        else
            Print("no wishlist detected -- running as advisor only.")
            Print("Design one in the Echo Journal: 'New Wishlist' (the 'Echo Wishlist'")
            Print("section), pick its echoes, and save it. The addon reads that build.")
        end
        return
    end
    local catalog = Adapter.Catalog()
    local source = (wishlist.source == "designed" and "your Echo Wishlist build")
        or (wishlist.source == "active" and "your active loadout")
        or "your wishlist"
    local families = {}
    for _, echo in ipairs(wishlist.entries) do families[echo.family] = true end
    local familyCount = 0
    for _ in pairs(families) do familyCount = familyCount + 1 end
    Print(string.format("reading |cff7fff7f'%s'|r (from %s) -- %d echoes, %d families",
        (wishlist.name ~= "" and wishlist.name) or "(unnamed)", source,
        #wishlist.entries, familyCount))
    local names = {}
    for _, echo in ipairs(wishlist.entries) do
        local row = catalog and catalog.rows[echo.spellId]
        names[#names + 1] = (row and row.name or ("spell " .. echo.spellId))
            .. (echo.stacks > 1 and (" x" .. echo.stacks) or "")
    end
    table.sort(names)
    Print("  " .. table.concat(names, ", "))
end

local function CommandProgress(showMissing)
    local catalog = Adapter.Catalog()
    local wishlist = Adapter.Wishlist()
    local owned = Adapter.Owned()
    if not wishlist then
        Print("no wishlist set -- advisor only, nothing to track.")
        return
    end
    local plan = Strategy.Compile(catalog,
        WishlistWithLockTargets(wishlist, catalog), Store.Settings())
    local have, total, missing = WishlistProgress(plan, owned, catalog)
    local percent = (total > 0) and math.floor(have / total * 100 + 0.5) or 0
    Print(string.format("this run: |cff7fff7f%d/%d|r echoes (%d%%) -- %d still short",
        have, total, percent, #missing))
    if showMissing and #missing > 0 then Print("  " .. table.concat(missing, ", ")) end
end

local function CommandDps()
    local capture = Nexus.DpsCapture
    if not capture then Print("DPS capture module not loaded"); return end
    if capture.IsDetailsAvailable() then
        Print("|cff4dff80DPS capture is active.|r")
        Print("Fight the Lich King or hit a training dummy to record your best.")
    else
        Print("|cffff9040Details! damage meter is not installed.|r")
        Print("Install Details! to enable DPS tracking on your builds.")
    end
    if Nexus.lastDpsNote then Print("Last session: " .. Nexus.lastDpsNote) end
    local wishlist = Adapter.Wishlist()
    if wishlist and capture.GetEchoKey then
        Print("Selected wishlist key: " .. tostring(capture.GetEchoKey(wishlist.entries)))
    end
    if capture.GetCurrentEchoKey then
        Print("Current tracked Echo key: " .. tostring(capture.GetCurrentEchoKey()))
    end
    Print("Open /nexus log and select DPS for the full capture trace.")
end

local function CommandSync()
    if Nexus.Sync then
        local ok, err = Nexus.Sync.RequestSync()
        Print(ok and "asking other players for their builds -- results appear in /nexus builds"
            or tostring(err))
    else
        Print("sync unavailable")
    end
end

local function CommandErr()
    local latest
    if Nexus.Errors and type(Nexus.Errors.Latest) == "function" then
        local ok, retained = pcall(Nexus.Errors.Latest)
        if ok then latest = retained end
    end
    Print(latest and latest.message or ErrorText(Nexus.lastError))
end

local function CommandAnchor(settings, argument)
    if argument == "off" or argument == nil then
        settings.anchorSpellId = nil
        Print("anchor cleared")
    else
        settings.anchorSpellId = tonumber(argument)
        Print("anchor set to " .. tostring(settings.anchorSpellId))
    end
    RequestRecompute()
end

local function CommandHelp()
    RequestRecompute()
    Print("v" .. Nexus.VERSION .. " -- " .. StatusLine())
    Print("|cffffd200Nexus v" .. Nexus.VERSION .. "|r  --  /nexus (or /nx, /wr)")
    Print("|cffffd200Setup:|r  builds  |  leaderboard  |  editor  |  sync  |  overlay")
    Print("|cffffd200Run:|r    auto  |  panel  |  status  |  wishlist  |  progress")
    Print("|cffffd200Data:|r   log  |  perf  |  dps  |  nameplate  |  logclear")
    Print("|cffffd200Fixes:|r  flags  |  undemote  |  anchor <id|off>  |  restore  |  err")
end

EnsureMainCommands = function()
    if MainCommands then return MainCommands end
    local internals = Nexus.MainInternals
    local factory = internals and internals.Commands
    if not (factory and type(factory.New) == "function") then return nil end
    MainCommands = factory.New({
        isInitialized=function()
            local lifecycle = Lifecycle()
            return lifecycle and lifecycle.IsInitialized() or false
        end,
        notInitialized=function() Print("not initialized yet") end,
        prepare=function() return Store.Settings() end,
        callbacks={
            auto=function() CommandAuto() end,
            panel=function() Panel.Toggle() end,
            restore=function() CommandRestore() end,
            flags=function() CommandFlags() end,
            status=function() CommandStatus() end,
            wishlist=function() CommandWishlist() end,
            progress=function() CommandProgress(false) end,
            missing=function() CommandProgress(true) end,
            editor=function()
                if Nexus.WishlistEditor then Nexus.WishlistEditor.Toggle()
                else Print("wishlist editor unavailable") end
            end,
            syncdebug=function()
                if Nexus.LogViewer then Nexus.LogViewer.Show("sync")
                else Print("log viewer unavailable") end
            end,
            probe=function(_, _, target)
                if target ~= "" and Nexus.Sync and Nexus.Sync.SendStatusTo then
                    pcall(Nexus.Sync.SendStatusTo, target)
                end
            end,
            nameplate=function()
                if Nexus.Nameplate then
                    Print("Mouseover tooltip: active.")
                    Print("Nexus users seen on the sync mesh are tagged, with leaderboard data when available.")
                else Print("Nameplate module not loaded.") end
            end,
            dps=function() CommandDps() end,
            sync=function() CommandSync() end,
            builds=function()
                if Nexus.CommunityBuilds then Nexus.CommunityBuilds.Toggle()
                else Print("Nexus Builds unavailable") end
            end,
            leaderboard=function()
                if Nexus.Leaderboard then Nexus.Leaderboard.Toggle()
                else Print("Nexus Leaderboard unavailable") end
            end,
            errors=function()
                if Nexus.LogViewer then Nexus.LogViewer.Show("errors")
                else Print("log viewer unavailable") end
            end,
            performance=function()
                if Nexus.LogViewer then Nexus.LogViewer.Show("perf")
                else Print("performance diagnostics unavailable") end
            end,
            logclear=function()
                local ok, cleared = pcall(ClearDiagnosticLogs, "state")
                Print(ok and cleared and "diagnostic history cleared"
                    or "could not clear diagnostic history")
            end,
            log=function()
                if Nexus.LogViewer then Nexus.LogViewer.Toggle()
                else Print("log viewer unavailable") end
            end,
            err=function() CommandErr() end,
            undemote=function()
                local state = Store.State()
                state.flagDemotions = {}
                RequestRecompute()
                Print("flag demotions cleared (they re-arm on fresh evidence)")
            end,
            overlay=function()
                if Nexus.WishlistOverlay then Nexus.WishlistOverlay.Toggle()
                else Print("overlay unavailable") end
            end,
            anchor=function(settings, _, argument)
                CommandAnchor(settings, argument)
            end,
            help=function() CommandHelp() end,
        },
    })
    return MainCommands
end

SLASH_NEXUS1 = "/nexus"
SLASH_NEXUS2 = "/nx"
SLASH_NEXUS3 = "/wr"   -- legacy alias kept for muscle memory
SlashCmdList["NEXUS"] = function(message)
    local commands = EnsureMainCommands and EnsureMainCommands()
    if commands then return commands.Dispatch(message) end
    Print("not initialized yet")
end
