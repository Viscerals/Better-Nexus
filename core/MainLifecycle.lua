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

        local okStore, errStore = pcall(Store.Init)
        if not okStore then
            RecordStoreError(errStore)
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

    local function OnEvent(event, arg1, arg2, arg3, arg4,
                           arg5, arg6, arg7, arg8, arg9)
        if event == "ADDON_LOADED" then
            if arg1 == "Nexus" then
                local storeReady = false
                if Nexus.Store and Nexus.Store.Init then
                    local okStore, errStore = pcall(Nexus.Store.Init)
                    storeReady = okStore
                    if not okStore then RecordStoreError(errStore) end
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
            Initialize()
            if initialized then
                local Adapter = dependencies.Adapter
                local Store = dependencies.Store
                Adapter.OnEvent(event)
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
        elseif event == "CHAT_MSG_WHISPER" then
            if initialized and Nexus.Sync and type(arg1) == "string"
                and arg1:sub(1,5) == "WLRQ|" then
                local code, _, token, mode =
                    arg1:match("^([^|]+)|([^|]*)|([^|]*)|([^|]*)$")
                if code == "WLRQ" and mode == "dev"
                    and token ~= "" and Nexus.Sync.HandleStatusRequest then
                    pcall(Nexus.Sync.HandleStatusRequest, arg2, token)
                end
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
        if not initialized then return end
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
