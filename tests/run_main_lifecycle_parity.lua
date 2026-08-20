-- MainLifecycle owns initialized state, boot/event routing, and ordered
-- per-frame coordination while Main retains only registrations and delegates.
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
local Store = {
    Init=function()
        Note("Store.Init")
        activeRoot = adoptedRoot
        return true
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
assert(#trace==0, "pre-init update reached services")

lifecycle.OnEvent("ADDON_LOADED", "Nexus")
assert(table.concat(trace,",")=="Store.Init,DiagnosticLogs.Init"
    and logRoots[1]==adoptedRoot,
    "ADDON_LOADED order or post-Store database identity changed")
local beforeWorld = #trace
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
assert(lifecycle.IsInitialized() and bindCount==1 and logRoots[2]==adoptedRoot
    and #recorded==0 and #storeErrors==0 and stutterRegistrationAttempts==1,
    "world init lost idempotence, database identity, or failure containment")

local lateLoadTrace = #trace
lifecycle.OnEvent("ADDON_LOADED", "StutterAlert")
assert(stutterRegistrationAttempts==2 and #trace==lateLoadTrace,
    "late optional-provider registration failure escaped or changed lifecycle work")

local initTraceEnd = #trace
lifecycle.OnEvent("PLAYER_ENTERING_WORLD")
assert(bindCount==1 and table.concat(trace,",",initTraceEnd+1)==table.concat({
    "Adapter.OnEvent:PLAYER_ENTERING_WORLD","Store.Settings",
    "Adapter.SetSoloPicker","Adapter.RequestSlots","JournalTab.TryInstall",
    "Sync.OnWorldEntry",
}, ","), "repeated world event duplicated lifecycle initialization")

local updateStart = #trace
lifecycle.OnUpdate(0.2)
assert(table.concat(trace,",",updateStart+1)==table.concat({
    "Adapter.Ready","Sync.OnUpdate:0.2","DpsCapture.OnUpdate:0.2",
    "Automation.OnUpdate:0.2",
}, ","), "per-frame owner order changed")
local lagStart = #trace
lifecycle.OnUpdate(2)
assert(Nexus.lastLagElapsed==2 and #trace==lagStart+4,
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
    "DpsCapture.OnCombatEnd","Sync.HandleStatusRequest:Dev:request-9",
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
assert(runtimeAt < lifecycleAt and lifecycleAt < mainAt,
    "MainLifecycle TOC order changed")

print("Main lifecycle boot, identity, idempotence, events, updates, and ownership -- OK")
