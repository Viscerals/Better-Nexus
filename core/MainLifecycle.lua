-- Nexus: core/MainLifecycle.lua
-- Stateful boot, event routing, and ordered per-frame coordination owner.

Nexus = Nexus or {}
if type(Nexus.MainInternals) ~= "table" then Nexus.MainInternals = {} end

local Lifecycle = {}
Nexus.MainInternals.Lifecycle = Lifecycle

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
    local syncInitialized = false
    local dpsInitialized = false
    local dependencies = nil
    -- Architecture line 1201: AuthorityBootstrapCoordinatorV1 is the sole
    -- startup sequencing owner, created here before Store.Init (line 1202).
    local bootstrapCoordinator = nil
    local bootstrapFailureRecorded = false
    -- World entry can legitimately arrive while authority is still pending,
    -- because bootstrap advances one slice per scheduler turn (line 1204).
    local worldEntryPending = false
    local CompleteWorldEntry
    local lagWarnedAt = -math.huge
    local LAG_THRESHOLD = 1.5
    local LAG_WARN_COOLDOWN = 60
    local isolatedFailures = {
        ["Sync.Init"]={active=false,message=nil},
        ["Sync.OnWorldEntry"]={active=false,message=nil},
        ["Sync.OnUpdate"]={active=false,message=nil},
        ["DpsCapture.Init"]={active=false,message=nil},
        ["DpsCapture.OnUpdate"]={active=false,message=nil},
        ["DpsCapture.OnCombatStart"]={active=false,message=nil},
        ["DpsCapture.OnCombatEnd"]={active=false,message=nil},
    }

    local function RunIsolatedOwner(source, callback, ...)
        local state = isolatedFailures[source]
        local ok, value = pcall(callback, ...)
        if ok then
            state.active, state.message = false, nil
            return true, value
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
        local ok, coordinator = pcall(factory.New)
        if not ok or type(coordinator) ~= "table" then return nil end
        bootstrapCoordinator = coordinator
        return coordinator
    end

    -- Exactly one PumpAuthorityBootstrap slice, never a loop (line 1204).
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
        if not okRequired or not required then return end
        -- AUTHORITY-COORDINATOR-DRIVE BEGIN. MASTER-RC-001: this scheduler
        -- turn is a coordinator dispatch point, not a dependent. It admits the
        -- evidence pool before the catalog on the rebind path, the order
        -- Catalog.Init used to enforce by driving LoadoutEvidence directly.
        if type(catalog.PendingRebindDatabaseV1) == "function" then
            local okTarget, target = pcall(catalog.PendingRebindDatabaseV1)
            if okTarget and type(target) == "table"
                and Nexus.LoadoutEvidence
                and type(Nexus.LoadoutEvidence.Init) == "function" then
                local okEvidence, evidenceError =
                    pcall(Nexus.LoadoutEvidence.Init, target)
                if not okEvidence then
                    RecordError("LoadoutEvidence.Init", evidenceError)
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

    local function Initialize()
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
        local db = Database()
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
                notify=function(version)
                    Print("Update " .. tostring(version)
                        .. " is available. Installation is manual; open the Nexus update notice to copy the releases page.")
                end,
                refresh=function()
                    if Nexus.Panel and Nexus.Panel.Refresh then Nexus.Panel.Refresh() end
                end,
            })
        end

        local automation = EnsureAutomation()
        if not automation then return false end
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
        if Nexus.CommunityBuilds and Nexus.CommunityBuilds.Init then
            Nexus.CommunityBuilds.Init(Adapter, Model)
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
    local function PumpCatalogRootAdmissionSlice()
        local catalog = Nexus and Nexus.BuildCatalog
        if type(catalog) ~= "table"
            or type(catalog.PumpRootAdmission) ~= "function" then
            return
        end
        local ok, err = pcall(catalog.PumpRootAdmission)
        if not ok then RecordError("BuildCatalog.PumpRootAdmission", err) end
    end
    -- AUTHORITY-COORDINATOR-DRIVE END

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
            -- Bootstrap advances one slice per scheduler turn (line 1204), so
            -- world entry can arrive while authority is still pending. The
            -- request is recorded and completed on the turn the coordinator
            -- reaches STORE_READY; it is never driven to readiness here.
            worldEntryPending = true
            -- A still-pending bootstrap is the normal startup path, not a
            -- fault, so it is not reported as a Store error here. With no
            -- coordinator (a Store stub) behaviour is unchanged: Initialize
            -- runs now and its explicit result alone decides readiness.
            if bootstrapCoordinator == nil or BootstrapCoordinatorIsReady() then
                Initialize()
                if initialized then
                    worldEntryPending = false
                    CompleteWorldEntry(event)
                end
            end
        elseif event == "PLAYER_LEVEL_UP" then
            if initialized then dependencies.Adapter.OnEvent(event) end
        elseif event == "PLAYER_REGEN_DISABLED" then
            if initialized and Nexus.DpsCapture then
                RunIsolatedOwner("DpsCapture.OnCombatStart",
                    Nexus.DpsCapture.OnCombatStart)
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if initialized and Nexus.DpsCapture then
                RunIsolatedOwner("DpsCapture.OnCombatEnd",
                    Nexus.DpsCapture.OnCombatEnd)
            end
        elseif event == "CHAT_MSG_CHANNEL" then
            if initialized and Nexus.Sync then
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

    local function RunUpdate(elapsed)
        if elapsed and elapsed > LAG_THRESHOLD then
            local now = GetTime and GetTime() or 0
            if now - lagWarnedAt > LAG_WARN_COOLDOWN then
                lagWarnedAt = now
                Nexus.lastLagElapsed = elapsed
            end
        end
        if not initialized then
            -- The scheduler's bounded bootstrap-pump core: at most ONE
            -- PumpAuthorityBootstrap slice per scheduler turn (lines 1203-1204).
            -- Dependents are released only when the coordinator itself reaches
            -- STORE_READY (line 1519), never because this call completed.
            if bootstrapCoordinator ~= nil then
                local result = PumpBootstrapSlice()
                local failed = type(result) == "table"
                    and result.state == "failed"
                if worldEntryPending
                    and (failed or BootstrapCoordinatorIsReady()) then
                    Initialize()
                    if initialized then
                        worldEntryPending = false
                        CompleteWorldEntry("PLAYER_ENTERING_WORLD")
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
        -- One authority rebind slice per scheduler turn, before any consumer
        -- reads this frame, so a character-identity change is re-proved by the
        -- coordinator rather than by a read.
        PumpAuthorityRebind()
        -- One post-ready Store mutation slice per turn, before consumer reads.
        PumpStoreMutationSlice()
        PumpCatalogRootAdmissionSlice()
        local Adapter = dependencies.Adapter
        if not Adapter.Ready() then return end
        if Nexus.Sync then
            RunIsolatedOwner("Sync.OnUpdate", Nexus.Sync.OnUpdate, elapsed)
        end
        if Nexus.DpsCapture then
            RunIsolatedOwner("DpsCapture.OnUpdate",
                Nexus.DpsCapture.OnUpdate, elapsed)
        end
        local automation = EnsureAutomation()
        if automation then automation.OnUpdate(elapsed) end
    end

    local function OnUpdate(elapsed)
        local performance = Nexus and Nexus.Performance
        if performance and type(performance.Measure) == "function" then
            return performance.Measure("lifecycle.update", RunUpdate, elapsed)
        end
        return RunUpdate(elapsed)
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
