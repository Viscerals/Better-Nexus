-- MainLifecycle owns initialized state, boot/event routing, and ordered
-- per-frame coordination while Main retains only registrations and delegates.
--
-- Repair Wave 1, amendment 3. This fixture enforces the ACCEPTED readiness
-- boundary rather than the superseded PR #68 call sequence. Architecture
-- 3b5de54f, docs/SYNC_TRUST_CATALOG_AUTHORITY_STATE_MACHINE.md:
--   line 1206  Store.Init returns the explicit detached authority result and
--              "a successful pcall is never interpreted as readiness".
--   line 1519  Store "enters STORE_READY and releases dependents" -- and only
--              after its terminal WishlistRealizerDB disposition completes.
--   line 4850  DPS-01 RED criteria include "a dependent initializer/Sync
--              handler runs while pending" and "pcall success means ready".
-- INTENTIONAL COMPATIBILITY BREAK: the superseded fixture drove a Store stub
-- whose Init returned `true` and read that truthy value as readiness. V1 must
-- never do so. That stub is retained below as an explicit negative control,
-- and four withholding states (pending, truthy, future schema, invalid) are
-- new coverage this file did not previously have. Every ordering, identity,
-- idempotence, isolation and static-ownership assertion is retained unchanged.
--
-- The bounded resumable slice graph itself -- one slice per pump, ordered
-- release at STORE_READY, no repeated release, and withholding on the
-- architecture's failure and future-schema paths -- is proven against
-- AuthorityBootstrapCoordinatorV1 in tests/run_store_legacy_retirement.lua.
Nexus = {VERSION="test", MainInternals={}}
dofile("core/MainLifecycle.lua")

local factory = Nexus.MainInternals.Lifecycle
assert(factory and type(factory.New)=="function",
    "MainLifecycle internal constructor is unavailable")
assert(not pcall(factory.New, {}),
    "MainLifecycle accepted a missing dependency graph")

local trace, logRoots, bindCount = {}, {}, 0
local function Note(value) trace[#trace + 1] = value end
local oldRoot, adoptedRoot = {old=true}, {overlayShown=true, adopted=true}
local activeRoot = oldRoot

-- The fixture, not the call, decides what authority result Store reports.
local storeState, storeInitCalls = "pending", 0
local Store = {
    Init=function()
        Note("Store.Init")
        storeInitCalls = storeInitCalls + 1
        activeRoot = adoptedRoot
        if storeState == "truthy" then return true end
        if storeState == "ready" then
            return {state="ready", result="BOOTSTRAP_COMMITTED"}
        end
        if storeState == "future" then
            return {state="failed", reason="FUTURE_SCHEMA"}
        end
        if storeState == "invalid" then
            return {state="failed", reason="STORE_INVALID"}
        end
        return {state="pending"}
    end,
    Settings=function() Note("Store.Settings"); return {autoPick=true} end,
}
local Adapter = {
    Init=function() Note("Adapter.Init") end,
    OnEvent=function(event) Note("Adapter.OnEvent:" .. tostring(event)) end,
    SetSoloPicker=function() Note("Adapter.SetSoloPicker") end,
    RequestSlots=function() Note("Adapter.RequestSlots") end,
    Ready=function() Note("Adapter.Ready"); return true end,
    RivalDetected=function() Note("Adapter.RivalDetected"); return false end,
}
local panelCallbacks
local Panel = {
    Init=function(callbacks) Note("Panel.Init"); panelCallbacks=callbacks end,
}
local JournalTab = {
    TryInstall=function(callback) Note("JournalTab.TryInstall");
        assert(type(callback)=="function") end,
}
local automation = {
    Initialize=function() Note("Automation.Initialize") end,
    ToggleAuto=function() Note("Automation.ToggleAuto"); return true end,
    JournalData=function() return {} end,
    OnUpdate=function(elapsed) Note("Automation.OnUpdate:"..tostring(elapsed)) end,
    RunFullStep=function(trigger, source)
        Note("Automation.RunFullStep:"..trigger..":"..source)
        return true
    end,
}
local dependencies = {
    Model={}, Policy={}, Ratchet={}, Strategy={}, Store=Store,
    Adapter=Adapter, Readout={}, Panel=Panel, JournalTab=JournalTab,
    DefaultProfile={},
}

Nexus.Store = Store
Nexus.DiagnosticLogs = {Init=function(root)
    Note("DiagnosticLogs.Init")
    logRoots[#logRoots + 1] = root
    return true
end}
Nexus.Errors = {Init=function() Note("Errors.Init"); return true end}
Nexus.Scheduler = {Init=function() Note("Scheduler.Init"); return {} end}
Nexus.PeerDebug = {Init=function() Note("PeerDebug.Init") end}
Nexus.Updates = {Init=function() Note("Updates.Init") end}
Nexus.LogViewer = {Init=function() Note("LogViewer.Init") end}
Nexus.WishlistEditor = {Init=function() Note("WishlistEditor.Init") end}
Nexus.WishlistOverlay = {
    Init=function() Note("WishlistOverlay.Init") end,
    Show=function() Note("WishlistOverlay.Show") end,
}
Nexus.CommunityBuilds = {Init=function() Note("CommunityBuilds.Init") end}
Nexus.Leaderboard = {Init=function() Note("Leaderboard.Init") end}
Nexus.Performance = {InstallDefaults=function() Note("Performance.InstallDefaults") end}
Nexus.ViewRefresh = {Init=function() Note("ViewRefresh.Init"); return true end}
Nexus.Nameplate = {Init=function() Note("Nameplate.Init") end}
Nexus.ServerStatus = {Init=function() Note("ServerStatus.Init") end}
local stutterRegistrationAttempts = 0
Nexus.StutterAlertIntegration = {Register=function()
    stutterRegistrationAttempts = stutterRegistrationAttempts + 1
    error("simulated optional-provider registration failure")
end}
Nexus.Codec = {}
Nexus.Sync = {
    Init=function() Note("Sync.Init") end,
    OnWorldEntry=function() Note("Sync.OnWorldEntry") end,
    OnUpdate=function(elapsed) Note("Sync.OnUpdate:"..tostring(elapsed)) end,
    ChannelName=function() Note("Sync.ChannelName"); return "wrbuildssync" end,
    HandleIncoming=function(text, sender)
        Note("Sync.HandleIncoming:"..tostring(text)..":"..tostring(sender))
    end,
    HandleStatusRequest=function(sender, token)
        Note("Sync.HandleStatusRequest:"..tostring(sender)..":"..tostring(token))
    end,
    LogEvent=function() Note("Sync.LogEvent") end,
}
Nexus.DpsCapture = {
    Init=function() Note("DpsCapture.Init") end,
    OnUpdate=function(elapsed) Note("DpsCapture.OnUpdate:"..tostring(elapsed)) end,
    OnCombatStart=function() Note("DpsCapture.OnCombatStart") end,
    OnCombatEnd=function() Note("DpsCapture.OnCombatEnd") end,
}
local rootAdmissionPumps = 0
Nexus.BuildCatalog = {
    PumpRootAdmission=function()
        rootAdmissionPumps = rootAdmissionPumps + 1
        Note("BuildCatalog.PumpRootAdmission")
        return {state="pending"}
    end,
}

local printed, recorded, storeErrors = {}, {}, {}
local lifecycle = factory.New({
    nexus=Nexus,
    bindDependencies=function()
        bindCount = bindCount + 1
        Note("BindDependencies")
        return dependencies
    end,
    ensureAutomation=function() return automation end,
    print=function(value) printed[#printed + 1] = tostring(value) end,
    recordError=function(source, value)
        recorded[#recorded + 1] = tostring(source)..":"..tostring(value)
    end,
    recordStoreError=function(value) storeErrors[#storeErrors + 1]=value end,
    errorText=tostring,
    requestRecompute=function() Note("RequestRecompute") end,
    refreshHud=function() Note("RefreshHud"); return true end,
    database=function() return activeRoot end,
    logViewerProvider=function() end,
    clearDiagnosticLogs=function() end,
    now=function() return 100 end,
})

assert(lifecycle.IsInitialized()==false and lifecycle.RefreshPanel()==false,
    "pre-init lifecycle state or refresh gate changed")
lifecycle.OnUpdate(0.2)
assert(#trace==0 and rootAdmissionPumps==0,
    "pre-init update reached services or pumped root admission")

-- ======================================================================
-- Readiness boundary. Only the explicit STORE_READY authority result may
-- release a dependent initializer. Four distinct non-ready results are
-- exercised, including the negative control the superseded fixture used as
-- its positive one.
-- ======================================================================
lifecycle.OnEvent("ADDON_LOADED", "Nexus")
assert(table.concat(trace,",")=="Store.Init" and #logRoots==0,
    "ADDON_LOADED bound the diagnostic root while Store authority was pending: "
    .. table.concat(trace,","))

local withheldStates = {"pending", "truthy", "future", "invalid"}
for _, state in ipairs(withheldStates) do
    storeState = state
    local before = #trace
    lifecycle.OnEvent("PLAYER_ENTERING_WORLD")
    local observed = table.concat(trace, ",", before + 1)
    assert(observed=="BindDependencies,Store.Init",
        "a dependent initializer ran while Store authority reported '"
        .. state .. "': " .. observed)
    assert(lifecycle.IsInitialized()==false and #logRoots==0
        and lifecycle.RefreshPanel()==false,
        "Store authority '" .. state .. "' released dependents or initialized")
end
-- The truthy control is the whole point: a stub whose Init returns `true`
-- completed successfully under pcall and still granted nothing.
assert(#storeErrors==#withheldStates + 1,
    "a withheld Store authority result was not recorded exactly once")
assert(storeInitCalls==#withheldStates + 1,
    "Store.Init call count drifted across the withheld states")

-- ======================================================================
-- Readiness reached. Every retained ordering, identity, idempotence and
-- isolation assertion below is unchanged from the superseded fixture.
-- ======================================================================
storeState = "ready"
local readyErrors, readyRecorded = #storeErrors, #recorded
local addonAt = #trace
lifecycle.OnEvent("ADDON_LOADED", "Nexus")
assert(table.concat(trace,",",addonAt+1)=="Store.Init,DiagnosticLogs.Init"
    and logRoots[1]==adoptedRoot,
    "ADDON_LOADED order or post-Store database identity changed")
local beforeWorld = #trace
local bindsBefore = bindCount
lifecycle.OnEvent("PLAYER_ENTERING_WORLD")
local worldTrace = table.concat(trace, ",", beforeWorld + 1)
local expectedWorld = table.concat({
    "BindDependencies","Store.Init","DiagnosticLogs.Init","Errors.Init",
    "Scheduler.Init","PeerDebug.Init","Updates.Init","Automation.Initialize","Adapter.Init",
    "LogViewer.Init","WishlistEditor.Init","WishlistOverlay.Init",
    "WishlistOverlay.Show","CommunityBuilds.Init","Leaderboard.Init",
    "Performance.InstallDefaults","ViewRefresh.Init","Nameplate.Init",
    "ServerStatus.Init","Panel.Init","RequestRecompute",
    "Adapter.RivalDetected","Adapter.OnEvent:PLAYER_ENTERING_WORLD",
    "Store.Settings","Adapter.SetSoloPicker","Adapter.RequestSlots",
    "JournalTab.TryInstall","Sync.Init","DpsCapture.Init",
}, ",")
assert(worldTrace==expectedWorld,
    "world initialization/event order changed: " .. worldTrace)
assert(lifecycle.IsInitialized() and bindCount==bindsBefore+1
    and logRoots[2]==adoptedRoot
    and #recorded==readyRecorded and #storeErrors==readyErrors
    and stutterRegistrationAttempts==1,
    "world init lost idempotence, database identity, or failure containment")

local lateLoadTrace = #trace
lifecycle.OnEvent("ADDON_LOADED", "StutterAlert")
assert(stutterRegistrationAttempts==2 and #trace==lateLoadTrace,
    "late optional-provider registration failure escaped or changed lifecycle work")

-- Repeated startup does not repeat dependent initialization.
local initTraceEnd = #trace
local repeatBinds = bindCount
lifecycle.OnEvent("PLAYER_ENTERING_WORLD")
assert(bindCount==repeatBinds and table.concat(trace,",",initTraceEnd+1)==table.concat({
    "Adapter.OnEvent:PLAYER_ENTERING_WORLD","Store.Settings",
    "Adapter.SetSoloPicker","Adapter.RequestSlots","JournalTab.TryInstall",
    "Sync.OnWorldEntry",
}, ","), "repeated world event duplicated lifecycle initialization")

local updateStart = #trace
lifecycle.OnUpdate(0.2)
assert(table.concat(trace,",",updateStart+1)==table.concat({
    "BuildCatalog.PumpRootAdmission","Adapter.Ready",
    "Sync.OnUpdate:0.2","DpsCapture.OnUpdate:0.2",
    "Automation.OnUpdate:0.2",
}, ",") and rootAdmissionPumps==1,
    "per-frame root-admission or owner order changed")
local lagStart = #trace
lifecycle.OnUpdate(2)
assert(Nexus.lastLagElapsed==2 and #trace==lagStart+5
    and rootAdmissionPumps==2,
    "lifecycle lost bounded lag observation or changed update continuation")

local eventStart = #trace
lifecycle.OnEvent("PLAYER_LEVEL_UP", 6)
lifecycle.OnEvent("PLAYER_REGEN_DISABLED")
lifecycle.OnEvent("PLAYER_REGEN_ENABLED")
lifecycle.OnEvent("CHAT_MSG_WHISPER", "WLRQ|Dev|request-9|dev", "Dev")
lifecycle.OnEvent("CHAT_MSG_CHANNEL", "WLNP|Peer|1.20.0", "Peer", "Common",
    "5. wrbuildssync", nil, nil, nil, 5, "wrbuildssync")
assert(table.concat(trace,",",eventStart+1)==table.concat({
    "Adapter.OnEvent:PLAYER_LEVEL_UP","DpsCapture.OnCombatStart",
    "DpsCapture.OnCombatEnd",
    "Sync.ChannelName","Sync.HandleIncoming:WLNP|Peer|1.20.0:Peer",
}, ","), "level/combat/whisper/channel routing order changed: "
    .. table.concat(trace, ",", eventStart + 1))

assert(panelCallbacks and panelCallbacks.ToggleAuto()==true
    and panelCallbacks.RefreshDisplay()==true,
    "Panel callbacks stopped routing through established owners")
assert(lifecycle.RefreshPanel()==true
    and trace[#trace-1]=="Adapter.Ready"
    and trace[#trace]=="Automation.RunFullStep:explicit:RefreshPanel.Step",
    "explicit RefreshPanel gate/action changed")

-- Sync and DPS initialization own independent success latches. Repeated
-- identical failures are retained once, successful owners never restart, and
-- later world entry reaches only the nondestructive Sync revalidation path.
local savedSync, savedDps = Nexus.Sync, Nexus.DpsCapture
local retrySyncCalls, retryWorldCalls, retryDpsCalls = 0, 0, 0
local retryErrors = {}
Nexus.Sync = {
    Init=function()
        retrySyncCalls = retrySyncCalls + 1
        if retrySyncCalls <= 2 then error("repeat sync init failure") end
    end,
    OnWorldEntry=function() retryWorldCalls = retryWorldCalls + 1 end,
}
Nexus.DpsCapture = {
    Init=function()
        retryDpsCalls = retryDpsCalls + 1
        if retryDpsCalls == 1 then error("one dps init failure") end
    end,
}
local retryLifecycle = factory.New({
    nexus=Nexus,bindDependencies=function() return dependencies end,
    ensureAutomation=function() return automation end,print=function() end,
    recordError=function(source, value)
        retryErrors[#retryErrors + 1] = tostring(source)..":"..tostring(value)
    end,
    recordStoreError=function(value) error(value) end,errorText=tostring,
    requestRecompute=function() end,refreshHud=function() return true end,
    database=function() return activeRoot end,logViewerProvider=function() end,
    clearDiagnosticLogs=function() end,now=function() return 100 end,
})
for _ = 1, 4 do retryLifecycle.OnEvent("PLAYER_ENTERING_WORLD") end
assert(retrySyncCalls == 3 and retryWorldCalls == 1 and retryDpsCalls == 2
    and #retryErrors == 2
    and retryErrors[1]:find("Sync.Init",1,true)
    and retryErrors[2]:find("DpsCapture.Init",1,true),
    "independent Sync/DPS init retry, suppression, or revalidation changed")
Nexus.Sync, Nexus.DpsCapture = savedSync, savedDps

local function Read(path)
    local file=assert(io.open(path,"r")); local value=file:read("*a"); file:close()
    return value
end
local main, source = Read("core/Main.lua"), Read("core/MainLifecycle.lua")
for _, pattern in ipairs({"local initialized", "local lagWarnedAt",
    "local function Init", "Adapter.OnEvent(event)",
    "Nexus.Sync.HandleIncoming", "Nexus.DpsCapture.OnCombatStart"}) do
    assert(not main:find(pattern,1,true),
        "Main retained lifecycle ownership: " .. pattern)
end
for _, pattern in ipairs({"local initialized", "local lagWarnedAt",
    "local function Initialize", "Nexus.Sync.HandleIncoming",
    "Nexus.DpsCapture.OnCombatStart"}) do
    assert(source:find(pattern,1,true),
        "MainLifecycle lost extracted ownership: " .. pattern)
end
-- Line 1652 requires the static startup call-site test itself to cover the
-- accepted graph: readiness is read from the explicit authority result at
-- every lifecycle entry, and never from pcall success.
assert(source:find("local function StoreResultIsReady(result)", 1, true)
    and source:find('result.state == "ready"', 1, true),
    "MainLifecycle lost the explicit STORE_READY authority gate")
assert(source:find("if not StoreResultIsReady(storeResult) then", 1, true),
    "MainLifecycle initialization no longer gates on the authority result")
assert(source:find(
    "storeReady = okStore and StoreResultIsReady(storeResult)", 1, true),
    "MainLifecycle ADDON_LOADED no longer gates on the authority result")
assert(not source:find("storeReady = okStore\r", 1, true)
    and not source:find("storeReady = okStore\n", 1, true),
    "MainLifecycle still reads pcall success as Store readiness")
for _, forbidden in ipairs({"CreateFrame", "SlashCmdList", "SLASH_NEXUS",
    "ProjectEbonhold.", "_G.ProjectEbonhold"}) do
    assert(not source:find(forbidden,1,true),
        "MainLifecycle acquired registration/service authority: " .. forbidden)
end
assert(select(2,main:gsub('EH:RegisterEvent%(',''))==7
    and select(2,main:gsub('EH:SetScript%(',''))==2
    and main:find('SlashCmdList["NEXUS"]',1,true),
    "Main stopped owning exact frame/event/slash registrations")
local toc=Read("Nexus.toc")
local runtimeAt=assert(toc:find("core\\AutomationRuntime.lua",1,true))
local lifecycleAt=assert(toc:find("core\\MainLifecycle.lua",1,true))
local mainAt=assert(toc:find("core\\Main.lua",1,true))
local storeAt=assert(toc:find("core\\Store.lua",1,true))
assert(runtimeAt < lifecycleAt and lifecycleAt < mainAt and storeAt < lifecycleAt,
    "MainLifecycle TOC order changed")

-- ======================================================================
-- SMT-REGISTER-TRIGGER-01  (MASTER-RC-001, sixth consultation)
--
-- Architecture 1198-1206: "MainLifecycle does not initialize ordinary account
-- registration ... while that result is pending." Ordinary (non-bootstrap)
-- account registration is therefore MainLifecycle's to trigger, and only after
-- readiness. It used to happen as a side effect of every Store.State() read,
-- which made a DURABLE_READ perform a DURABLE_MUTATION (line ~1888).
--
-- This section builds its own dependency graph and its own lifecycle instance
-- so that every assertion above -- including the exact world-entry trace
-- strings -- is left completely untouched.
--
-- It drives the REAL core/MainLifecycle.lua. The Store and coordinator are
-- stubs because the claim under test is MainLifecycle's own behaviour: when it
-- triggers registration, and how many mutation slices it pumps per turn.
-- ======================================================================
do
    local registrations, pumps = 0, 0
    local rState = "pending"
    local RStore
    RStore = {
        Init=function()
            if rState == "ready" then
                return {state="ready", result="BOOTSTRAP_COMMITTED"}
            end
            return {state="pending"}
        end,
        Settings=function() return {autoPick=false} end,
        RegisterCurrentCharacter=function()
            registrations = registrations + 1
            return {state="pending"}
        end,
    }
    -- The coordinator factory must be owner-bound to this exact Store, exactly
    -- as core/Store.lua binds the real one (MainLifecycle rejects any other).
    local coordinator = {
        State=function() return rState == "ready" and "STORE_READY" or "STORE_UNBOUND" end,
        IsReady=function() return rState == "ready" end,
        Result=function() return RStore.Init() end,
        Settle=function() return RStore.Init() end,
        BindAuthorityDatabase=function() return RStore.Init() end,
        PumpAuthorityBootstrap=function() return RStore.Init() end,
        PumpStoreMutationV1=function() pumps = pumps + 1; return {state="pending"} end,
    }
    Nexus.MainInternals.AuthorityBootstrap =
        {owner=RStore, New=function() return coordinator end}

    -- Reuse the graph the assertions above already exercised, with only the
    -- Store swapped, so this section adds no new dependency-shape assumptions.
    local rdeps = {}
    for key, value in pairs(dependencies) do rdeps[key] = value end
    rdeps.Store = RStore
    local priorNexusStore = Nexus.Store
    Nexus.Store = RStore

    local rlife = factory.New({
        nexus=Nexus,
        bindDependencies=function() return rdeps end,
        ensureAutomation=function() return automation end,
        print=function() end,
        recordError=function() end,
        recordStoreError=function() end,
        errorText=tostring,
        requestRecompute=function() end,
        refreshHud=function() return true end,
        database=function() return activeRoot end,
        now=function() return 100 end,
    })

    -- 1. While the authority result is PENDING, no registration is submitted.
    rlife.OnEvent("ADDON_LOADED", "Nexus")
    rlife.OnEvent("PLAYER_ENTERING_WORLD")
    assert(registrations == 0,
        "MainLifecycle submitted ordinary account registration while the Store "
        .. "authority result was still pending (architecture 1198-1206); "
        .. "registrations=" .. tostring(registrations))

    -- 2. After STORE_READY it submits, through Store's PUBLIC export.
    rState = "ready"
    rlife.OnEvent("ADDON_LOADED", "Nexus")
    rlife.OnEvent("PLAYER_ENTERING_WORLD")
    assert(rlife.IsInitialized(),
        "the fixture never reached an initialized lifecycle, so the assertions "
        .. "below would be vacuous")
    assert(registrations >= 1,
        "MainLifecycle never submitted ordinary account registration after "
        .. "STORE_READY; registrations=" .. tostring(registrations))

    -- 3. At most ONE post-ready mutation slice per scheduler turn, never a loop.
    local basePumps = pumps
    rlife.OnUpdate(0.2)
    assert(pumps == basePumps + 1,
        "one scheduler turn pumped " .. tostring(pumps - basePumps)
        .. " post-ready Store mutation slices; architecture 1204 allows exactly "
        .. "one per turn")
    rlife.OnUpdate(0.2)
    rlife.OnUpdate(0.2)
    assert(pumps == basePumps + 3,
        "post-ready mutation slices are not one-per-turn across turns; pumps="
        .. tostring(pumps - basePumps) .. " over 3 turns")

    -- 4. MainLifecycle never reaches for the coordinator's private mutation
    --    ADMISSION entry itself; Store's export is what submits.
    local source = Read("core/MainLifecycle.lua")
    assert(not source:find("BeginStoreMutationV1", 1, true),
        "core/MainLifecycle.lua calls the coordinator's private mutation "
        .. "admission entry directly; only Store.RegisterCurrentCharacter may "
        .. "submit")
    Nexus.Store = priorNexusStore
    Nexus.MainInternals.AuthorityBootstrap = nil
    print("SMT-REGISTER-TRIGGER-01 -- registration gated on readiness, one "
        .. "mutation slice per turn -- OK")
end

print("Main lifecycle readiness boundary, boot, identity, idempotence, events, updates, and ownership -- OK")
