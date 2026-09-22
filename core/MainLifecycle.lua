-- Nexus: core/MainLifecycle.lua
-- Stateful boot, event routing, and ordered per-frame coordination owner.

Nexus = Nexus or {}
if type(Nexus.MainInternals) ~= "table" then Nexus.MainInternals = {} end

local Lifecycle = {}
Nexus.MainInternals.Lifecycle = Lifecycle

-- Root refusals that are purely about saved capacity: the data is complete
-- and untouched, and only the shared catalog cannot be admitted. Local tools
-- continue; every other refusal keeps the previous all-or-nothing behavior.
local CAPACITY_REFUSALS = {
    ROOT_SLOT_LIMIT=true, TOMBSTONE_SET_LIMIT=true, BARRIER_SET_LIMIT=true,
    ROOT_MAP_LIMIT=true,
}

function Lifecycle.New(options)
    options = options or {}
    local Nexus = assert(options.nexus, "MainLifecycle requires Nexus")
    local BindDependencies = assert(options.bindDependencies,
        "MainLifecycle requires dependency binding")
    local EnsureAutomation = assert(options.ensureAutomation,
        "MainLifecycle requires automation binding")
    local Print = assert(options.print, "MainLifecycle requires print")
    local RecordError = assert(options.recordError,
        "MainLifecycle requires error recording")
    local RecordStoreError = assert(options.recordStoreError,
        "MainLifecycle requires Store error recording")
    local ErrorText = assert(options.errorText,
        "MainLifecycle requires safe error text")
    local RequestRecompute = assert(options.requestRecompute,
        "MainLifecycle requires recompute routing")
    local RefreshHud = assert(options.refreshHud,
        "MainLifecycle requires HUD refresh routing")
    local RequestFirstHud = options.requestFirstHud or RefreshHud
    local Database = assert(options.database,
        "MainLifecycle requires database access")
    local GetTime = assert(options.now, "MainLifecycle requires clock")

    local initialized = false
    local preparedDatabase
    local communityFailure
    local communityMutationTicket
    local communityReady = false
    local sharedWorldEntryPending = false
    local rebindEvidenceDb, rebindEvidenceSource, rebindEvidenceOwner, rebindEvidenceInit
    local maintenanceFailureRecorded=false
    local syncInitialized = false
    local dpsInitialized = false
    local dependencies = nil
    -- Architecture line 1201: AuthorityBootstrapCoordinatorV1 is the sole
    -- startup sequencing owner, created here before Store.Init (line 1202).
    local bootstrapCoordinator = nil
    local bootstrapFailureRecorded = false
    -- World entry can legitimately arrive while authority is still pending,
    -- because bootstrap advances bounded work across scheduler turns.
    local worldEntryPending = false
    local bootstrapPumping = false
    local bootstrapTerminal = nil
    local STARTUP_MS, STARTUP_SLICES = 2, 32
    -- Session-only scalar observations, like lastLagElapsed below. Never saved,
    -- never used as readiness, and no samples or player content are retained.
    local startupTiming = {updates=0, slices=0, maxBatchMs=0, maxUpdateMs=0, overshoots=0,
        maxOvershootMs=0, fallbackUpdates=0}
    Nexus.startupTiming = startupTiming
    -- Last observed state of the full Sync turn gate: the exact booleans the
    -- gate below decided with, its reason, and whether a manual request
    -- owned that update's preparation. Session-only scalars for the
    -- diagnostic report, "unknown" until the gate is first reached. No
    -- history, no counter, never read by any decision.
    local syncGate = {reason="unknown", owner="unknown"}
    -- The step the existing owners are on now, with a completed/total pair
    -- only when that owner already holds both. Reads scalar state only: no
    -- pump, drift check, cursor advance or extra scan sizes a step.
    local function CurrentStep()
        local catalog=Nexus.BuildCatalog
        if not initialized then
            local okState,store=false,nil
            if bootstrapCoordinator and type(bootstrapCoordinator.State)=="function" then
                okState,store=pcall(bootstrapCoordinator.State,bootstrapCoordinator)
            end
            store=okState and store or nil
            if store=="STORE_CHAR_MIGRATION_PENDING"
                or store=="STORE_DURABLE_BUNDLE_ADMISSION_PENDING" then
                return "store-characters"
            elseif store=="STORE_COMPACTION_PENDING" or store=="STORE_FINAL_COMMIT_PENDING"
                or store=="STORE_LEGACY_DISPOSITION_PENDING"
                or store=="STORE_SERVING_PUBLICATION_PENDING" then
                return "store-finish"
            elseif store=="STORE_READY" then return "local-setup"
            elseif store~="STORE_AUTHORITY_PENDING" then return "store-validation" end
        elseif communityReady then return "complete" end
        local okPrep,prep=false,nil
        if catalog and type(catalog.ManualPreparationStatus)=="function" then
            okPrep,prep=pcall(catalog.ManualPreparationStatus)
        end
        if okPrep and type(prep)=="table" and prep.phase~=nil then
            return "catalog-"..tostring(prep.phase),prep.stepDone,prep.stepTotal
        end
        if not initialized then return "catalog" end
        return startupTiming.communityPhase or "community",
            startupTiming.communityProgressDone,startupTiming.communityProgressTotal
    end
    -- Read-only, session-only facts the failed Store result already holds:
    -- stage, cause, detail, owner, a bounded one-line error, the selection
    -- row, and the settings-format verdict. Reads the retained result and a
    -- pure classification only; never binds, pumps or retries.
    local function FailureFacts()
        local r = bootstrapTerminal
        if type(r) ~= "table" or r.state ~= "failed" then
            -- The catalog refused its root after the Store finished: the
            -- catalog's own session-only refusal record, when it matches.
            local reason = startupTiming.coreFailure
            if reason == nil then return nil end
            local catalog = Nexus.BuildCatalog
            local ok, last = false, nil
            if catalog and type(catalog.LastLimitSummary) == "function" then
                ok, last = pcall(catalog.LastLimitSummary)
            end
            if not ok or type(last) ~= "table" or last.reason ~= reason
                or last.mode ~= "admission" then
                return {component="catalog"}
            end
            return {component="catalog", phase=last.phase, map=last.map,
                counter=last.counter, count=tonumber(last.count),
                limit=tonumber(last.limit), source=last.source}
        end
        local function Token(value, limit)
            if value == nil then return nil end
            local okText, text = pcall(tostring, value)
            if not okText or type(text) ~= "string" then text = "<unprintable>" end
            text = text:gsub("[%c|]", " ")
            if #text > limit then text = text:sub(1, limit) .. "..." end
            return text
        end
        local facts = {stage=Token(r.stage, 48), cause=Token(r.cause, 48),
            detail=Token(r.detail, 48), owner=Token(r.owner, 64),
            error=Token(r.error, 160), row=tonumber(r.row),
            legacyClass=Token(r.legacyClass, 32)}
        local internals = Nexus.MainInternals
        local classify = type(internals) == "table" and internals.SavedFormatClassV1
        if type(classify) == "function" then
            local ok, class, version, field = pcall(classify)
            if ok then
                facts.formatClass = Token(class, 16)
                facts.formatVersion = tonumber(version)
                facts.formatField = Token(field, 64)
            end
        end
        return facts
    end
    -- Read-only scalar snapshot. This does not pump, admit or authorize data.
    Nexus.StartupStatus = function()
        local failure=startupTiming.coreFailure or communityFailure
            or (bootstrapTerminal and bootstrapTerminal.state=="failed"
                and (bootstrapTerminal.detail or bootstrapTerminal.reason or "STORE_INVALID"))
        local step,stepDone,stepTotal=CurrentStep()
        return {coreReady=initialized, state=failure and "failed"
            or communityReady and "ready" or "pending",
            phase=not initialized and "store-validation"
                or startupTiming.communityPhase or "community",
            reason=failure, syncReady=syncInitialized, dpsReady=dpsInitialized,
            progressDone=startupTiming.communityProgressDone,
            progressTotal=startupTiming.communityProgressTotal,
            recordsSeen=startupTiming.communityRecordsSeen or 0,
            step=step,stepDone=stepDone,stepTotal=stepTotal,
            failure=FailureFacts(),
            coreSlices=startupTiming.slices or 0,
            syncGate=syncGate.reason, syncGateOwner=syncGate.owner,
            syncGateAdapterReady=syncGate.adapterReady,
            syncGateCatalogReady=syncGate.catalogReady,
            syncGateHashesReady=syncGate.hashesReady}
    end
    local MANUAL_MS, MANUAL_SLICES = 2, 32
    local manualTiming = {updates=0,slices=0,maxBatchMs=0,maxUpdateMs=0,
        overshoots=0,fallbackUpdates=0}
    Nexus.manualSyncTiming = manualTiming
    local observedManualOwner, manualUpdateActive
    local CompleteWorldEntry
    local lagWarnedAt = -math.huge
    local LAG_THRESHOLD = 1.5
    local LAG_WARN_COOLDOWN = 60
    local isolatedFailures = {
        ["LoadingStatus.Update"]={active=false,message=nil},
        ["Sync.Init"]={active=false,message=nil},
        ["Sync.OnWorldEntry"]={active=false,message=nil},
        ["Sync.OnUpdate"]={active=false,message=nil},
        ["Sync.Housekeep"]={active=false,message=nil},
        ["Sync.PumpPreparedShare"]={active=false,message=nil},
        ["Sync.UpdatePendingRequestStatus"]={active=false,message=nil},
        ["CommunityBuilds.PumpPendingShare"]={active=false,message=nil},
        ["DpsCapture.Init"]={active=false,message=nil},
        ["DpsCapture.OnUpdate"]={active=false,message=nil},
        ["DpsCapture.OnCombatStart"]={active=false,message=nil},
        ["DpsCapture.OnCombatEnd"]={active=false,message=nil},
    }

    local function RunIsolatedOwner(source, callback, ...)
        local state = isolatedFailures[source]
        local ok, value, detail = pcall(callback, ...)
        if ok then
            state.active, state.message = false, nil
            return true, value, detail
        end
        local message = tostring(ErrorText(value))
        if not state.active or state.message ~= message then
            RecordError(source, value)
        end
        state.active, state.message = true, message
        return false, value
    end

    -- Architecture 3b5de54f,
    -- docs/SYNC_TRUST_CATALOG_AUTHORITY_STATE_MACHINE.md line 1206: Store.Init
    -- returns the explicit detached authority result and "a successful pcall is
    -- never interpreted as readiness". Line 1519 releases dependents only once
    -- Store authority has reached STORE_READY. Neither a completed call nor a
    -- truthy return may stand in for that result.
    local function StoreResultIsReady(result)
        return type(result) == "table" and result.state == "ready"
    end

    -- Architecture line 1206: Store.Init "returns the explicit detached result
    -- {state=\"pending\"} until the coordinator reaches STORE_READY". Pending is
    -- the ordinary startup steady state, not a fault. It withholds dependents
    -- but must never be reported as a Store error, or every login would raise
    -- one. Only a result that is neither ready nor pending is a fault.
    local function StoreResultIsPending(result)
        return type(result) == "table" and result.state == "pending"
    end

    local function StoreResultReason(result)
        if type(result) ~= "table" then return "STORE_NOT_READY" end
        return result.error or result.reason or result.state or "STORE_NOT_READY"
    end

    -- Architecture lines 1202-1204. MainLifecycle creates the coordinator
    -- before calling Store.Init, then initializes only the scheduler's
    -- bounded bootstrap-pump core. It never drives bootstrap to readiness
    -- inside an event: continuation scheduling is the scheduler's.
    local function EnsureBootstrapCoordinator(Store)
        if bootstrapCoordinator ~= nil then return bootstrapCoordinator end
        if type(Store) ~= "table" then return nil end
        -- Line 1202: MainLifecycle creates the coordinator. Line 1912 keeps the
        -- public Store inventory at nine, so the factory is reached through the
        -- Nexus.MainInternals seam rather than a Store export. The owner check
        -- binds it to this exact Store: a stub Store resolves no coordinator.
        local internals = Nexus.MainInternals
        local factory = type(internals) == "table" and internals.AuthorityBootstrap
        if type(factory) ~= "table" or type(factory.New) ~= "function"
            or factory.owner ~= Store then
            return nil
        end
        local community=Nexus.CommunityBuilds
        local ok, coordinator = pcall(factory.New,{deferAutomaticMaintenance=
            type(community)=="table" and type(community.Init)=="function"})
        if not ok or type(coordinator) ~= "table" then return nil end
        bootstrapCoordinator = coordinator
        return coordinator
    end

    -- Each call still advances exactly one existing bounded coordinator slice.
    local function PumpBootstrapSlice()
        local coordinator = bootstrapCoordinator
        if coordinator == nil then return nil end
        local ok, result = pcall(coordinator.PumpAuthorityBootstrap, coordinator)
        if not ok then
            if not bootstrapFailureRecorded then
                bootstrapFailureRecorded = true
                RecordStoreError(result)
            end
            return nil
        end
        return result
    end

    local function StartupClock()
        if type(debugprofilestop) ~= "function" then return nil end
        local ok, value = pcall(debugprofilestop)
        if not ok or type(value) ~= "number" or value ~= value
            or value < 0 or value == math.huge then return nil end
        return value
    end

    -- Native startup amendment: one shared soft deadline across all phases,
    -- plus an unconditional slice cap. Missing/broken clocks retain one slice.
    local function PumpBootstrapBatch(updateStarted)
        if bootstrapPumping then return nil end
        -- Keep the terminal result for a world-entry request that arrives
        -- after the final pump. Stopping work must not discard its refusal.
        if bootstrapTerminal then return bootstrapTerminal end
        bootstrapPumping = true
        local started = updateStarted or StartupClock()
        local previous = started
        local result
        startupTiming.updates = startupTiming.updates + 1
        for slice = 1, STARTUP_SLICES do
            result = PumpBootstrapSlice()
            startupTiming.slices = startupTiming.slices + 1
            local finished = StartupClock()
            local timed = started ~= nil and finished ~= nil
                and finished >= previous
            local elapsed = timed and (finished - started) or nil
            if timed then
                previous = finished
                startupTiming.maxBatchMs = math.max(startupTiming.maxBatchMs, elapsed)
                if elapsed > STARTUP_MS then
                    startupTiming.overshoots = startupTiming.overshoots + 1
                    startupTiming.maxOvershootMs = math.max(
                        startupTiming.maxOvershootMs, elapsed - STARTUP_MS)
                end
            else
                startupTiming.fallbackUpdates = startupTiming.fallbackUpdates + 1
            end
            if type(result) == "table"
                and (result.state == "ready" or result.state == "failed") then
                bootstrapTerminal = result
                break
            end
            if not timed or elapsed >= STARTUP_MS
                or type(result) ~= "table" or result.progressed ~= true then
                break
            end
        end
        bootstrapPumping = false
        return result
    end

    -- MASTER-RC-009. A read never binds, admits, or re-admits; on owner drift
    -- it records one explicit rebind request and refuses read-only. The
    -- scheduler turn is the dispatch point that satisfies that request, the
    -- same way it dispatches one bootstrap slice (lines 1203-1204), and it is
    -- the lifecycle rebind pump the read gate depends on. Exactly one pump per
    -- turn; never a loop, and never driven from a read.
    local function PumpAuthorityRebind()
        local catalog = Nexus.BuildCatalog
        if type(catalog) ~= "table"
            or type(catalog.RebindRequired) ~= "function"
            or type(catalog.PumpAuthorityRebindV1) ~= "function" then
            return
        end
        local okRequired, required = pcall(catalog.RebindRequired)
        if not okRequired or not required then
            rebindEvidenceDb,rebindEvidenceSource,rebindEvidenceOwner,rebindEvidenceInit=nil,nil,nil,nil
            return
        end
        -- AUTHORITY-COORDINATOR-DRIVE BEGIN. MASTER-RC-001: this scheduler
        -- turn is a coordinator dispatch point, not a dependent. It admits the
        -- evidence pool before the catalog on the rebind path, the order
        -- Catalog.Init used to enforce by driving LoadoutEvidence directly.
        if type(catalog.PendingRebindDatabaseV1) == "function" then
            local okTarget, target = pcall(catalog.PendingRebindDatabaseV1)
            if okTarget and type(target) == "table"
                and Nexus.LoadoutEvidence
                and type(Nexus.LoadoutEvidence.Init) == "function" then
                local evidence=Nexus.LoadoutEvidence
                local source=rawget(target,"authorityBundle") or target
                if rebindEvidenceDb~=target or rebindEvidenceSource~=source
                    or rebindEvidenceOwner~=evidence or rebindEvidenceInit~=evidence.Init then
                    local okEvidence,evidenceError=pcall(evidence.Init,target)
                    if not okEvidence then
                        RecordError("LoadoutEvidence.Init",evidenceError)
                        return
                    end
                    rebindEvidenceDb,rebindEvidenceSource=target,source
                    rebindEvidenceOwner,rebindEvidenceInit=evidence,evidence.Init
                end
            end
        end
        -- AUTHORITY-COORDINATOR-DRIVE END
        local okPump, pumpError = pcall(catalog.PumpAuthorityRebindV1)
        if not okPump then
            RecordError("BuildCatalog.PumpAuthorityRebindV1", pumpError)
        end
    end

    local function BootstrapCoordinatorIsReady()
        local coordinator = bootstrapCoordinator
        if coordinator == nil or type(coordinator.IsReady) ~= "function" then
            return false
        end
        local ok, ready = pcall(coordinator.IsReady, coordinator)
        return ok and ready == true
    end

    -- Store.Init(coordinator) binds the exact database and returns the
    -- explicit detached authority result (line 1206). A Store without the
    -- coordinator factory keeps the plain call; readiness is still decided
    -- only by StoreResultIsReady, never by the call having completed.
    local function BindStoreAuthority(Store)
        local coordinator = EnsureBootstrapCoordinator(Store)
        local ok, result
        if coordinator ~= nil then
            ok, result = pcall(Store.Init, coordinator)
        else
            ok, result = pcall(Store.Init)
        end
        return ok, result
    end

    local function RegisterStutterAlertProvider()
        local integration = Nexus.StutterAlertIntegration
        if integration and type(integration.Register) == "function" then
            pcall(integration.Register)
        end
    end

    local function Initialize(updateStarted)
        if initialized then return true end
        dependencies = BindDependencies()
        if not dependencies then return false end

        local Store = dependencies.Store
        local Adapter = dependencies.Adapter
        local Panel = dependencies.Panel
        local Model = dependencies.Model

        local okStore, storeResult = BindStoreAuthority(Store)
        if not okStore then
            RecordStoreError(storeResult)
            return false
        end
        if not StoreResultIsReady(storeResult) then
            RecordStoreError(StoreResultReason(storeResult))
            return false
        end
        local catalog=Nexus.BuildCatalog
        local root=catalog and type(catalog.RootState)=="function" and catalog.RootState()
        if root and root.state~="ROOT_ADMITTED" then
            startupTiming.coreFailure=root.reason or root.state
            RecordStoreError(startupTiming.coreFailure)
            -- A capacity refusal is a complete, deterministic verdict on data
            -- this build leaves exactly as it found it: the saved maps hold
            -- more keys than the root admits. Local Wishlist and Echo tools do
            -- not need the shared catalog, so they continue; Community,
            -- Leaderboard and Sync stay unavailable (their own owners refuse
            -- against the same refused root), the failure and its reason stay
            -- reported, and nothing is written, evicted or migrated.
            if not CAPACITY_REFUSALS[startupTiming.coreFailure] then
                return false
            end
        end
        local db = Database()
        local automation = EnsureAutomation()
        if not automation then return false end
        if preparedDatabase ~= db then
            communityFailure,communityReady=nil,false
            local okLogs, initializedLogs, errLogs =
                pcall(Nexus.DiagnosticLogs.Init, db)
            if not okLogs or initializedLogs == false then
                RecordError("DiagnosticLogs.Init", okLogs and errLogs or initializedLogs)
            end
            if Nexus.Errors and Nexus.Errors.Init then
                local okErrors, initializedErrors, errErrors = pcall(Nexus.Errors.Init)
                if not okErrors or initializedErrors == false then
                    RecordError("Errors.Init", okErrors and errErrors or initializedErrors)
                end
            end
            if Nexus.Scheduler and Nexus.Scheduler.Init then
                local okScheduler, schedulerFrame = pcall(Nexus.Scheduler.Init)
                if not okScheduler or not schedulerFrame then
                    RecordError("Scheduler.Init",
                        okScheduler and "frame unavailable" or schedulerFrame)
                end
            end
            if Nexus.PeerDebug and Nexus.PeerDebug.Init then
                local okPeerDebug, peerDebugError = pcall(Nexus.PeerDebug.Init)
                if not okPeerDebug then
                    RecordError("PeerDebug.Init", peerDebugError)
                end
            end
            if Nexus.Updates and Nexus.Updates.Init then
                Nexus.Updates.Init({
                    -- A capacity-refused start-up leaves every saved key as it
                    -- found it, so the update module reads its stored notice
                    -- without rewriting, quarantining or removing it.
                    persist=not CAPACITY_REFUSALS[startupTiming.coreFailure],
                    notify=function(version, _, message)
                        Print(type(message) == "string" and message
                            or ("Nexus build " .. tostring(version) .. ": see /nexus update. Installation is manual."))
                    end,
                    refresh=function()
                        if Nexus.Panel and Nexus.Panel.Refresh then Nexus.Panel.Refresh() end
                    end,
                })
            end

            automation.Initialize()
            Adapter.Init({OnStatus=Print}, Store)
            if Nexus.LogViewer and Nexus.LogViewer.Init then
                Nexus.LogViewer.Init(options.logViewerProvider,
                    options.clearDiagnosticLogs)
            end
            if Nexus.WishlistEditor and Nexus.WishlistEditor.Init then
                Nexus.WishlistEditor.Init(Adapter, Model)
            end
            if Nexus.WishlistOverlay and Nexus.WishlistOverlay.Init then
                Nexus.WishlistOverlay.Init(Adapter, Model)
                if db.overlayShown then Nexus.WishlistOverlay.Show() end
            end
            preparedDatabase=db
        end
        if Nexus.Leaderboard and Nexus.Leaderboard.Init then
            Nexus.Leaderboard.Init(Adapter, Model)
        end
        if Nexus.Performance
            and type(Nexus.Performance.InstallDefaults) == "function" then
            local okPerformance, performanceError =
                pcall(Nexus.Performance.InstallDefaults)
            if not okPerformance then
                RecordError("Performance.InstallDefaults", performanceError)
            end
        end
        if Nexus.ViewRefresh and Nexus.ViewRefresh.Init then
            local okRefresh, refreshReady = pcall(Nexus.ViewRefresh.Init)
            if not okRefresh or refreshReady == false then
                RecordError("ViewRefresh.Init",
                    okRefresh and "initialization failed" or refreshReady)
            end
        end
        if Nexus.Nameplate and Nexus.Nameplate.Init then Nexus.Nameplate.Init() end
        if Nexus.ServerStatus and Nexus.ServerStatus.Init then
            Nexus.ServerStatus.Init()
        end
        Panel.Init({
            ToggleAuto=function()
                local enabled = automation.ToggleAuto()
                Print("auto " .. (enabled and "ON" or "OFF"))
                return enabled
            end,
            RefreshDisplay=function() return RefreshHud() end,
            RequestFirstDisplay=function() return RequestFirstHud() end,
        })
        initialized = true
        RegisterStutterAlertProvider()
        RequestRecompute()
        Print("v" .. Nexus.VERSION .. " -- type /nexus for commands.")
        if Adapter.RivalDetected() then
            Print("|cffff6060EchoOptimizer detected -- it conflicts with Nexus's board hook. Disable EchoOptimizer; Nexus replaces its functionality.|r")
        end
        return true
    end

    -- The ordered world-entry sequence. Unchanged in content and order; it is
    -- a named routine only so it can run on the scheduler turn that reaches
    -- STORE_READY instead of only inside the event that requested it.
    -- MASTER-RC-001, architecture 1198-1206: "MainLifecycle does not initialize
    -- ordinary account registration ... while that result is pending." Ordinary
    -- (non-bootstrap) account registration is therefore MainLifecycle's to
    -- trigger, and only once the coordinator is no longer pending. It used to
    -- happen as a side effect of every Store.State() read, which made a
    -- DURABLE_READ perform a DURABLE_MUTATION (line ~1888).
    --
    -- This submits through Store's PUBLIC mutation export. MainLifecycle must
    -- never call the coordinator's private mutation entries itself:
    -- Store.RegisterCurrentCharacter() is what submits, and the coordinator owns
    -- completion.
    -- The readiness gate is CompleteWorldEntry itself: OnEvent reaches it only
    -- when the coordinator is absent or already ready, and RunUpdate only after
    -- Initialize succeeded. A second BootstrapCoordinatorIsReady() gate here
    -- would be wrong, not merely redundant -- with a Store that exposes no
    -- coordinator factory, bootstrapCoordinator is nil, and that gate would mean
    -- registration NEVER happens in that configuration. Store's own export
    -- decides submit-versus-synchronous from the coordinator IT is bound to.
    local function SubmitOrdinaryRegistration()
        local Store = dependencies and dependencies.Store
        if type(Store) ~= "table"
            or type(Store.RegisterCurrentCharacter) ~= "function" then
            return
        end
        local ok, err = pcall(Store.RegisterCurrentCharacter)
        if not ok then RecordError("Store.RegisterCurrentCharacter", err) end
    end

    -- Exactly ONE post-ready Store mutation slice per scheduler turn, before any
    -- consumer reads this frame -- the same one-slice-per-turn discipline
    -- architecture line 1204 sets for the bootstrap pump, applied to the
    -- post-ready machine. Never a loop, and never driven from a read.
    local function PumpStoreMutationSlice()
        local coordinator = bootstrapCoordinator
        if coordinator == nil
            or type(coordinator.PumpStoreMutationV1) ~= "function" then
            return
        end
        local ok, err = pcall(coordinator.PumpStoreMutationV1, coordinator)
        if not ok then RecordError("Store.PumpStoreMutationV1", err) end
    end

    -- MASTER-RC-006: a max-root catalog mutation returns an explicit pending
    -- ticket. Drive exactly one bounded construction slice per scheduler turn,
    -- before any consumer reads the catalog. The catalog owns the candidate;
    -- MainLifecycle only owns the scheduler dispatch.
    -- AUTHORITY-COORDINATOR-DRIVE BEGIN. The lifecycle scheduler advances the
    -- catalog-owned pending candidate once before dependent consumers run.
    local function PumpCatalogRootAdmissionSlice(expectedPreparation)
        local catalog = Nexus and Nexus.BuildCatalog
        if type(catalog) ~= "table"
            or type(catalog.PumpRootAdmission) ~= "function" then
            return true
        end
        local ok, result, progressed = pcall(catalog.PumpRootAdmission, expectedPreparation)
        if not ok then
            RecordError("BuildCatalog.PumpRootAdmission", result)
            return false
        end
        local root = type(catalog.RootState) == "function"
            and catalog.RootState() or nil
        if type(root) == "table" then
            return root.state == "ROOT_ADMITTED" and root.candidate ~= true, progressed == true
        end
        return not (type(result) == "table" and result.state == "pending"), progressed == true
    end
    -- AUTHORITY-COORDINATOR-DRIVE END

    -- Compatibility hashes can require a retained summary/tombstone walk and
    -- an incremental bucket sort. Advance exactly one cache-owned slice after
    -- catalog admission and before Sync consumes those hashes.
    local function PumpBuildHashCacheSlice()
        local cache = Nexus and Nexus.BuildHashCache
        if type(cache) ~= "table"
            or type(cache.Pump) ~= "function" then
            return true
        end
        local ok, ready, progressed = pcall(cache.Pump)
        if not ok then
            RecordError("BuildHashCache.Pump", ready)
            return false
        end
        return ready == true, progressed == true
    end

    -- Only the retained manual operation receives one shared allowance. A
    -- same-root catalog commit is a prerequisite; rebind/foreign work is not.
    -- This is one batch per lifecycle update, shared by all command/UI entries.
    local function PumpManualPreparationBatch(owner, preparationElapsed, preparationPumps)
        local started, previous = StartupClock(), nil
        local ready, catalogReady = false, false
        local catalog = Nexus.BuildCatalog
        local describe = catalog and catalog.ManualPreparationStatus
        if type(describe) ~= "function" then
            catalogReady = PumpCatalogRootAdmissionSlice()
            return catalogReady and PumpBuildHashCacheSlice(), catalogReady
        end
        local initial, prerequisite = describe()
        -- Starting ordinary maintenance can already consume a catalog slice.
        -- Count it in this update's shared allowance, not as a second budget.
        local priorSlices = math.max(0, initial.totalPumps - preparationPumps)
        if priorSlices > 0 then
            started = started and preparationElapsed and started-preparationElapsed or nil
            -- The initial slice can exhaust the allowance before the loop.
            -- Record its cost even when no additional slice may run.
            if preparationElapsed ~= nil then
                manualTiming.maxBatchMs = math.max(manualTiming.maxBatchMs,preparationElapsed)
                if preparationElapsed > MANUAL_MS then
                    manualTiming.overshoots = manualTiming.overshoots + 1
                end
            end
        end
        previous = started
        manualTiming.slices = manualTiming.slices + priorSlices
        for slice=1,math.max(0,MANUAL_SLICES-priorSlices) do
            local ok, _, current = RunIsolatedOwner("Sync.UpdatePendingRequestStatus",
                Nexus.Sync.UpdatePendingRequestStatus)
            if not ok or current ~= owner then break end
            local before = StartupClock()
            local timed = started ~= nil and before ~= nil and before >= previous
            if timed and before-started >= MANUAL_MS then break end
            if not timed and priorSlices+slice > 1 then break end
            local status, currentPrerequisite = describe()
            -- Even our own completed publication ends this generation's batch.
            -- The next update may prepare hashes against the new generation.
            if status.binding ~= initial.binding or status.generation ~= initial.generation then break end
            if currentPrerequisite ~= nil and currentPrerequisite ~= prerequisite then break end
            local progressed
            local ordinaryOnly = not status.ready and not status.relevant
            if status.ready then
                catalogReady = true
                ready, progressed = PumpBuildHashCacheSlice()
            elseif status.relevant then
                catalogReady, progressed = PumpCatalogRootAdmissionSlice(prerequisite)
            elseif slice == 1 then
                -- Preserve the ordinary allowance, but never accelerate a
                -- different binding, rebind or unrelated pending operation.
                catalogReady = PumpCatalogRootAdmissionSlice()
            else break end
            local observed = describe()
            manualTiming.catalogPhase, manualTiming.catalogKind = observed.phase, observed.kind
            manualTiming.catalogPumps, manualTiming.catalogWork = observed.pumps, observed.work
            manualTiming.waitReason = observed.reason
            manualTiming.slices = manualTiming.slices + 1
            local finished = StartupClock()
            timed = timed and finished ~= nil and finished >= before
            if timed then
                manualTiming.maxBatchMs = math.max(manualTiming.maxBatchMs,finished-started)
                if finished-started > MANUAL_MS then
                    manualTiming.overshoots = manualTiming.overshoots + 1
                end
                previous = finished
            else manualTiming.fallbackUpdates = manualTiming.fallbackUpdates + 1 end
            if ready or ordinaryOnly or not progressed or not timed or finished-started >= MANUAL_MS then break end
        end
        return ready, catalogReady
    end

    function CompleteWorldEntry(event)
        local Adapter = dependencies.Adapter
        local Store = dependencies.Store
        Adapter.OnEvent(event)
        -- Ordinary account registration, gated on readiness (1198-1206).
        SubmitOrdinaryRegistration()
        if Store.Settings().autoPick then Adapter.SetSoloPicker() end
        Adapter.RequestSlots()
        local automation = EnsureAutomation()
        if dependencies.JournalTab then
            dependencies.JournalTab.TryInstall(automation.JournalData)
        end
        sharedWorldEntryPending = true
    end

    local function CompleteSharedWorldEntry()
        if not communityReady or not sharedWorldEntryPending then return end
        sharedWorldEntryPending = false
        local Adapter=dependencies.Adapter
        if Nexus.Sync and Nexus.Codec then
            if not syncInitialized
                and type(Nexus.Sync.Init) == "function" then
                syncInitialized = RunIsolatedOwner("Sync.Init",
                    Nexus.Sync.Init, Nexus.Codec, Adapter)
            elseif syncInitialized
                and type(Nexus.Sync.OnWorldEntry) == "function" then
                RunIsolatedOwner("Sync.OnWorldEntry",
                    Nexus.Sync.OnWorldEntry)
            end
        end
        if Nexus.DpsCapture and not dpsInitialized
            and type(Nexus.DpsCapture.Init) == "function" then
            dpsInitialized = RunIsolatedOwner("DpsCapture.Init",
                Nexus.DpsCapture.Init, Adapter, Nexus.Sync)
        end
        if Nexus.LegacyQualificationRepair
            and Nexus.LegacyQualificationRepair.Init then
            local okRepair, repairReady, repairError = pcall(
                Nexus.LegacyQualificationRepair.Init)
            if not okRepair or repairReady == false then
                RecordError("LegacyQualificationRepair.Init",
                    okRepair and repairError or repairReady)
            end
        end
    end

    -- Community preparation is optional for local Wishlist/Echo use, but is
    -- still required before shared services can mutate, send, or publish.
    -- Automatic maintenance stays deferred until this job completes, retaining
    -- its cursor's stable-source assumptions. Reads never drive initialization.
    local function PumpCommunityStartup(updateStarted)
        if communityReady then CompleteSharedWorldEntry();return true end
        if communityFailure then return false end
        local community=Nexus.CommunityBuilds
        if not (community and type(community.Init)=="function") then
            communityReady=true
            startupTiming.communityPhase="complete"
            CompleteSharedWorldEntry()
            return true
        end
        local started=updateStarted or StartupClock()
        local previous=started
        local ticket=communityMutationTicket
        local sliceCount=0
        for slice=1,(ticket and STARTUP_SLICES or 1) do
            if ticket and ticket.state~="pending" then break end
            local before=StartupClock()
            if started and before and before>=started
                and before-started>=STARTUP_MS then return false end
            local _,progressed=PumpCatalogRootAdmissionSlice()
            sliceCount=sliceCount+1
            if ticket and ticket.state~="pending" then break end
            local finished=StartupClock()
            if not progressed or not started or not finished or finished<previous
                or finished-started>=STARTUP_MS then break end
            previous=finished
        end
        -- Do not touch a cursor while an unrelated mutation is in flight.
        local catalog=Nexus.BuildCatalog
        local root=catalog and type(catalog.RootState)=="function" and catalog.RootState()
        if root and (root.state=="ROOT_ADMISSION_PENDING" or root.candidate)
            and not (ticket and ticket.state~="pending") then
            -- The catalog work may replace the root under the Community
            -- cursor. Its last position is not shown again until Init reports.
            startupTiming.communityProgressDone,startupTiming.communityProgressTotal=nil,nil
            startupTiming.communityRecordsSeen=nil
            return false
        end
        local before=StartupClock()
        if started and before and before>=started
            and before-started>=STARTUP_MS then return false end
        local ok,result=pcall(community.Init,dependencies.Adapter,dependencies.Model,
            started,math.max(0,STARTUP_SLICES-sliceCount))
        local finished=StartupClock()
        if before and finished and finished>=before then
            startupTiming.communityMaxMs=math.max(
                startupTiming.communityMaxMs or 0,finished-before)
            startupTiming.communityTotalMs=(startupTiming.communityTotalMs or 0)
                +finished-before
        end
        startupTiming.communityPhase=type(result)=="table" and result.phase or nil
        startupTiming.communityProgressDone=type(result)=="table" and result.progressDone or nil
        startupTiming.communityProgressTotal=type(result)=="table" and result.progressTotal or nil
        startupTiming.communityRecordsSeen=type(result)=="table" and result.recordsSeen or nil
        communityMutationTicket=type(result)=="table" and result.mutationTicket or nil
        if not ok or type(result)=="table" and result.state=="failed" then
            communityFailure=not ok and ErrorText(result) or result.reason
                or "COMMUNITY_STARTUP_FAILED"
            startupTiming.communityState="failed"
            RecordError("CommunityBuilds.Init",communityFailure)
            return false
        end
        if type(result)=="table" and result.state=="pending" then return false end
        communityReady=true
        communityMutationTicket=nil
        startupTiming.communityState="ready"
        startupTiming.communityReadyAt=GetTime()
        CompleteSharedWorldEntry()
        return true
    end

    local function OnEvent(event, arg1, arg2, arg3, arg4,
                           arg5, arg6, arg7, arg8, arg9)
        if event == "ADDON_LOADED" then
            if arg1 == "Nexus" then
                local storeReady = false
                if Nexus.Store and Nexus.Store.Init then
                    local okStore, storeResult =
                        BindStoreAuthority(Nexus.Store)
                    storeReady = okStore and StoreResultIsReady(storeResult)
                    -- The bind slice legitimately returns pending here: the
                    -- coordinator has further slices to run and the scheduler
                    -- owns dispatching them (lines 1203-1204), so on a real
                    -- login this is the ordinary path and recording it would
                    -- raise an initialization error on every single login.
                    -- Pending is only a normal steady state when something
                    -- owns advancing it: with no coordinator, a pending result
                    -- never resolves and is still reported. Dependents stay
                    -- withheld in both cases.
                    if not okStore then
                        RecordStoreError(storeResult)
                    elseif not storeReady
                        and not (StoreResultIsPending(storeResult)
                            and bootstrapCoordinator ~= nil) then
                        RecordStoreError(StoreResultReason(storeResult))
                    end
                end
                if storeReady and Nexus.DiagnosticLogs and Nexus.DiagnosticLogs.Init then
                    local okLogs, initializedLogs, errLogs =
                        pcall(Nexus.DiagnosticLogs.Init, Database())
                    if not okLogs or initializedLogs == false then
                        RecordError("DiagnosticLogs.Init",
                            okLogs and errLogs or initializedLogs)
                    end
                end
            elseif arg1 == "StutterAlert" and initialized then
                RegisterStutterAlertProvider()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Bootstrap advances bounded work per scheduler turn, so
            -- world entry can arrive while authority is still pending. The
            -- request is recorded and completed on the turn the coordinator
            -- reaches STORE_READY; it is never driven to readiness here.
            worldEntryPending = true
            if startupTiming.worldEnteredAt == nil then
                startupTiming.worldEnteredAt = GetTime()
            end
            -- A still-pending bootstrap is the normal startup path, not a
            -- fault, so it is not reported as a Store error here. With no
            -- coordinator (a Store stub) behaviour is unchanged: Initialize
            -- runs now and its explicit result alone decides readiness.
            if bootstrapCoordinator == nil or BootstrapCoordinatorIsReady() then
                local started=StartupClock()
                Initialize()
                if initialized then
                    worldEntryPending = false
                    CompleteWorldEntry(event)
                    startupTiming.readyAt=GetTime()
                    startupTiming.readySeconds=startupTiming.readyAt
                        - startupTiming.worldEnteredAt
                end
                local finished=StartupClock()
                if started and finished and finished>=started then
                    startupTiming.maxUpdateMs=math.max(
                        startupTiming.maxUpdateMs,finished-started)
                end
            end
        elseif event == "PLAYER_LEVEL_UP" then
            if initialized then dependencies.Adapter.OnEvent(event) end
        elseif event == "PLAYER_REGEN_DISABLED" then
            if initialized and dpsInitialized and Nexus.DpsCapture then
                RunIsolatedOwner("DpsCapture.OnCombatStart",
                    Nexus.DpsCapture.OnCombatStart)
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if initialized and dpsInitialized and Nexus.DpsCapture then
                RunIsolatedOwner("DpsCapture.OnCombatEnd",
                    Nexus.DpsCapture.OnCombatEnd)
            end
        elseif event == "CHAT_MSG_CHANNEL" then
            if initialized and syncInitialized and Nexus.Sync then
                local want = Nexus.Sync.ChannelName()
                local bare = type(arg9) == "string" and arg9:lower() or nil
                local numbered = nil
                if type(arg4) == "string" then
                    numbered = (arg4:lower():gsub("^%s*%d+%.%s*", ""))
                end
                if bare == want or numbered == want then
                    local ok, err = pcall(Nexus.Sync.HandleIncoming, arg1, arg2)
                    if not ok then
                        RecordError("Sync.HandleIncoming", err)
                        Nexus.Sync.LogEvent("RX", "handler ERROR: %s", ErrorText(err))
                    end
                elseif type(arg1) == "string" and arg1:find("^WLR") then
                    Nexus.Sync.LogEvent("RX",
                        "MISMATCH arg4=%q arg9=%q (wanted %q)",
                        tostring(arg4), tostring(arg9), want)
                end
            end
        end
    end

    local function RunUpdate(elapsed,updateStarted)
        if elapsed and elapsed > LAG_THRESHOLD then
            local now = GetTime and GetTime() or 0
            if now - lagWarnedAt > LAG_WARN_COOLDOWN then
                lagWarnedAt = now
                Nexus.lastLagElapsed = elapsed
            end
        end
        if not initialized then
            -- Only startup uses the amended timed batch. Rebind, maintenance,
            -- and post-ready mutation scheduling below remain one-slice paths.
            -- Dependents are released only when the coordinator itself reaches
            -- STORE_READY (line 1519), never because this call completed.
            if bootstrapCoordinator ~= nil or worldEntryPending then
                if bootstrapPumping then return end
                local result = bootstrapCoordinator and PumpBootstrapBatch(updateStarted)
                local failed = type(result) == "table"
                    and result.state == "failed"
                if worldEntryPending
                    and (failed or bootstrapCoordinator==nil or BootstrapCoordinatorIsReady()) then
                    Initialize(updateStarted)
                    if initialized then
                        worldEntryPending = false
                        CompleteWorldEntry("PLAYER_ENTERING_WORLD")
                        startupTiming.readyAt = GetTime()
                        if startupTiming.worldEnteredAt ~= nil then
                            startupTiming.readySeconds = startupTiming.readyAt
                                - startupTiming.worldEnteredAt
                        end
                    elseif failed then
                        -- Terminal authority failure. Initialize recorded the
                        -- attributed reason once; dependents stay withheld and
                        -- the coordinator never retries (line 1519).
                        worldEntryPending = false
                    end
                end
            end
            return
        end
        local preparationPumps = 0
        if Nexus.BuildCatalog and type(Nexus.BuildCatalog.ManualPreparationStatus)=="function" then
            preparationPumps = Nexus.BuildCatalog.ManualPreparationStatus().totalPumps
        end
        local preparationStarted = StartupClock()
        -- One authority rebind slice per scheduler turn, before any consumer
        -- reads this frame, so a character-identity change is re-proved by the
        -- coordinator rather than by a read.
        PumpAuthorityRebind()
        -- One post-ready Store mutation slice per turn, before consumer reads.
        PumpStoreMutationSlice()
        if not communityReady then
            -- Early return before the catalog, hash and adapter gate: those
            -- three were not evaluated in this update.
            syncGate.reason, syncGate.owner = "community-startup", "none"
            syncGate.adapterReady, syncGate.catalogReady, syncGate.hashesReady = nil, nil, nil
            PumpCommunityStartup(updateStarted)
            local adapter=dependencies.Adapter
            if adapter.Ready() then
                local automation=EnsureAutomation()
                if automation then automation.OnUpdate(elapsed) end
            end
            return
        end
        CompleteSharedWorldEntry()
        if bootstrapCoordinator and bootstrapCoordinator.StartAutomaticMaintenance then
            local ok,result=pcall(bootstrapCoordinator.StartAutomaticMaintenance,bootstrapCoordinator)
            if (not ok or type(result)=="table" and result.state=="failed")
                and not maintenanceFailureRecorded then
                maintenanceFailureRecorded=true
                RecordStoreError(ok and StoreResultReason(result) or result)
            end
        end
        local preparationFinished = StartupClock()
        local preparationElapsed = preparationStarted and preparationFinished
            and preparationFinished >= preparationStarted
            and preparationFinished-preparationStarted or nil
        -- MASTER-W2-006/W2-008: Sync is the only frame owner that consumes
        -- catalog and compatibility-hash state, so it alone waits for the
        -- pending catalog slice and the one cache slice. DPS capture and
        -- automation keep their per-frame turn; their own catalog writes are
        -- retained pending tickets and never block the frame.
        local manualOwner
        if syncInitialized and Nexus.Sync and type(Nexus.Sync.UpdatePendingRequestStatus)=="function" then
            local ok, _, owner = RunIsolatedOwner("Sync.UpdatePendingRequestStatus",
                Nexus.Sync.UpdatePendingRequestStatus)
            if ok then manualOwner = owner end
        end
        if manualOwner then
            manualUpdateActive = true
            manualTiming.updates = manualTiming.updates + 1
            if observedManualOwner ~= manualOwner then
                observedManualOwner = manualOwner
                manualTiming.startedAt, manualTiming.readyAt, manualTiming.sentAt = GetTime(), nil, nil
            end
        end
        local catalogReady, buildHashesReady
        if manualOwner then
            buildHashesReady, catalogReady = PumpManualPreparationBatch(manualOwner, preparationElapsed, preparationPumps)
        else
            catalogReady = PumpCatalogRootAdmissionSlice()
            if catalogReady then buildHashesReady = PumpBuildHashCacheSlice() end
        end
        -- Give one explicitly approved Share the next normal admission turn
        -- before Sync can start another incoming write. This does not pump or
        -- bypass catalog work. A new write invalidates the prepared hash view.
        local community = Nexus.CommunityBuilds
        local shareGate
        if community and type(community.PumpPendingShare) == "function" then
            local ok, pending, submitted = RunIsolatedOwner("CommunityBuilds.PumpPendingShare",
                community.PumpPendingShare)
            if not ok or pending then catalogReady = false end
            if not ok or pending or submitted then buildHashesReady = false end
            -- This one pump serves a pending Share and a pending local removal;
            -- the label names the shared gate, not which of the two is pending.
            shareGate = not ok and "community-operation-error"
                or pending and "community-operation-pending"
                or submitted and "community-operation-submitted" or nil
        end
        if catalogReady then
            if manualOwner and buildHashesReady and manualTiming.readyAt == nil then
                manualTiming.readyAt = GetTime()
            end
        end
        local Adapter = dependencies.Adapter
        local adapterReady = Adapter.Ready()
        syncGate.owner = manualOwner and "manual-request" or "none"
        syncGate.adapterReady = adapterReady == true
        syncGate.catalogReady, syncGate.hashesReady = catalogReady == true, buildHashesReady == true
        syncGate.reason = not adapterReady and "adapter-not-ready"
            or not (syncInitialized and Nexus.Sync) and "sync-not-initialized"
            or shareGate or not catalogReady and "catalog-not-ready"
            or not buildHashesReady and "hashes-not-ready" or "open"
        if not (adapterReady and catalogReady and buildHashesReady)
            and syncInitialized and Nexus.Sync and type(Nexus.Sync.Housekeep)=="function" then
            -- One transport turn per frame. Prepared manual Share bytes do
            -- not depend on a later catalog/hash candidate. Everything else
            -- retains the full readiness gate and passive expiry handling.
            if adapterReady and type(Nexus.Sync.PumpPreparedShare)=="function" then
                RunIsolatedOwner("Sync.PumpPreparedShare", Nexus.Sync.PumpPreparedShare, elapsed)
            else
                RunIsolatedOwner("Sync.Housekeep", Nexus.Sync.Housekeep)
            end
        end
        if not adapterReady then return end
        if syncInitialized and Nexus.Sync and catalogReady and buildHashesReady then
            RunIsolatedOwner("Sync.OnUpdate", Nexus.Sync.OnUpdate, elapsed)
            if manualOwner and manualTiming.sentAt==nil and type(Nexus.Sync.Stats)=="function"
                and Nexus.Sync.Stats().queueOutcome=="sent" then manualTiming.sentAt=GetTime() end
        end
        if dpsInitialized and Nexus.DpsCapture then
            RunIsolatedOwner("DpsCapture.OnUpdate",
                Nexus.DpsCapture.OnUpdate, elapsed)
        end
        local automation = EnsureAutomation()
        if automation then automation.OnUpdate(elapsed) end
    end

    local function FinishStartupUpdate(started, wasStartup, ...)
        -- Presentation never drives readiness. The module throttles snapshots;
        -- any UI failure is isolated from the already executed lifecycle work.
        if Nexus.LoadingStatus and type(Nexus.LoadingStatus.Update)=="function" then
            RunIsolatedOwner("LoadingStatus.Update",Nexus.LoadingStatus.Update)
        end
        if started ~= nil then
            local finished = StartupClock()
            if finished ~= nil and finished >= started then
                if manualUpdateActive then
                    manualTiming.maxUpdateMs = math.max(manualTiming.maxUpdateMs,finished-started)
                elseif wasStartup then
                    startupTiming.maxUpdateMs = math.max(
                        startupTiming.maxUpdateMs, finished - started)
                end
            end
        end
        return ...
    end

    local function OnUpdate(elapsed)
        -- Include dependent initialization and world-entry completion in the
        -- observed full update cost, not just the soft-budget coordinator loop.
        local started
        local wasStartup = not initialized and not bootstrapPumping
        manualUpdateActive = false
        if not bootstrapPumping then started = StartupClock() end
        local performance = Nexus and Nexus.Performance
        if performance and type(performance.Measure) == "function" then
            return FinishStartupUpdate(started, wasStartup,
                performance.Measure("lifecycle.update", RunUpdate, elapsed,started))
        end
        return FinishStartupUpdate(started, wasStartup, RunUpdate(elapsed,started))
    end

    local M = {}
    function M.Initialize() return Initialize() end
    function M.IsInitialized() return initialized end
    function M.OnEvent(...) return OnEvent(...) end
    function M.OnUpdate(elapsed) return OnUpdate(elapsed) end
    function M.RefreshPanel()
        if not initialized or not dependencies.Adapter.Ready() then return false end
        local automation = EnsureAutomation()
        return automation
            and automation.RunFullStep("explicit", "RefreshPanel.Step") or false
    end
    return M
end
