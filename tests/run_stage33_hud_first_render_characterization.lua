-- Stage 33.1 expected red: the real HUD constructor must never become visible
-- before one complete immutable display model has been applied.  Keep this
-- assembled fixture green after the source repair; do not replace the owners
-- below with a recreated panel or lifecycle.
local H = dofile("tests/harness.lua")

local checks, failures = 0, {}
local function Check(condition, message)
    checks = checks + 1
    if not condition then failures[#failures + 1] = message end
end

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do out[Copy(key, seen)] = Copy(child, seen) end
    return out
end

local function Signature(value, seen)
    local kind = type(value)
    if kind ~= "table" then return kind .. ":" .. tostring(value) end
    seen = seen or {}
    if seen[value] then return "cycle" end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        return type(left) .. ":" .. tostring(left)
            < type(right) .. ":" .. tostring(right)
    end)
    local out = {"{"}
    for _, key in ipairs(keys) do
        out[#out + 1] = Signature(key, seen)
        out[#out + 1] = "="
        out[#out + 1] = Signature(value[key], seen)
        out[#out + 1] = ";"
    end
    out[#out + 1] = "}"
    seen[value] = nil
    return table.concat(out)
end

local function ChangedPaths(before, after, prefix, out)
    out = out or {}
    prefix = prefix or "NexusDB"
    if #out >= 8 then return out end
    if type(before) ~= type(after) then
        out[#out + 1] = prefix
        return out
    end
    if type(before) ~= "table" then
        if before ~= after then out[#out + 1] = prefix end
        return out
    end
    local keys = {}
    for key in pairs(before) do keys[key] = true end
    for key in pairs(after) do keys[key] = true end
    for key in pairs(keys) do
        ChangedPaths(before[key], after[key],
            prefix .. "." .. tostring(key), out)
        if #out >= 8 then break end
    end
    return out
end

local function DurableSavedState(root)
    local out = Copy(root)
    -- Fixed diagnostic histories are observed separately; they are not
    -- gameplay, configuration, association, catalog, or automation state.
    out.decisionLog = nil
    out.runAudit = nil
    out.syncLog = nil
    out.diagnosticMeta = nil
    return out
end

-- Observe the actual widgets built by Panel.EnsureFrame without replacing its
-- implementation.  The header is the first font string created on NexusPanel;
-- button identity is read from the real constructor labels.
local realCreateFrame = CreateFrame
local panelRegions, panelButtons = {}, {}
CreateFrame = function(kind, name, parent, template)
    local created = realCreateFrame(kind, name, parent, template)
    if kind == "Button" then panelButtons[#panelButtons + 1] = created end
    if name == "NexusPanel" then
        local createFontString = created.CreateFontString
        created.CreateFontString = function(self, ...)
            local region = createFontString(self, ...)
            panelRegions[#panelRegions + 1] = region
            return region
        end
    end
    return created
end

dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Relay.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/Theme.lua")
dofile("ui/LayoutMetrics.lua")
dofile("ui/Readout.lua")
dofile("ui/Panel.lua")
dofile("ui/JournalTab.lua")

local refreshRequests = 0
NexusDB = {settings={autoPick=false,autoLockEchoes=false}}
Nexus.Panel.Init({
    ToggleAuto=function() return false end,
    RefreshDisplay=function()
        refreshRequests = refreshRequests + 1
        return false
    end,
})

local function FindButton(label)
    for _, button in ipairs(panelButtons) do
        if button:GetText() == label then return button end
    end
end

local function ShowFrame(target)
    target:Show()
    local callback = target:GetScript("OnShow")
    if callback then callback(target) end
end

local function HideFrame(target)
    target:Hide()
    local callback = target:GetScript("OnHide")
    if callback then callback(target) end
end

local observations = {
    rawShow=0,rawToggle=0,rawMenuRestore=0,firstWidgetFailure=0,
    laterWidgetFailure=0,layoutFaults=0,recoveries=0,providerFaults=0,
    setupFaults=0,
    activeModels=0,idleModels=0,actions=0,uploads=0,syncUploads=0,
    commits=0,renderFailures=0,renderRecoveries=0,mainRecoveryRequests=0,
}

-- Real pre-render Show and Toggle paths.  A visible frame with no last model,
-- no completed layout, an empty header, and Auto: -- is the constructor shell.
Nexus.Panel.Show()
local frame = assert(_G.NexusPanel, "Panel.Show did not materialize the real HUD")
local header = assert(panelRegions[1], "Panel header region was not observed")
local autoButton = assert(FindButton("Auto: --"), "raw Auto button was not observed")
local buildsButton = assert(FindButton("Builds"), "Builds navigation was not observed")
local leaderboardButton = assert(FindButton("Leaderboard"),
    "Leaderboard navigation was not observed")
if frame:IsShown() and Nexus.Panel._lastModel == nil
    and Nexus.Panel.RenderStats().layouts == 0
    and header:GetText() == "" and autoButton:GetText() == "Auto: --" then
    observations.rawShow = observations.rawShow + 1
end
Nexus.Panel.Hide()
Nexus.Panel.Toggle()
if frame:IsShown() and Nexus.Panel._lastModel == nil
    and header:GetText() == "" and autoButton:GetText() == "Auto: --" then
    observations.rawToggle = observations.rawToggle + 1
end
Check(refreshRequests == 2,
    "pre-render Show/Toggle did not request the Main-owned HUD model exactly once each")
Check(buildsButton:GetText() == "Builds"
    and leaderboardButton:GetText() == "Leaderboard",
    "constructor lost required navigation widgets")

-- Menu restoration is a separate visibility owner.  It must not restore an
-- uncommitted shell, while explicit hide intent must remain authoritative.
local menu = CreateFrame("Frame", "NexusStage33Menu", UIParent)
Nexus.Panel.AttachMenuFrame(menu)
ShowFrame(menu)
Check(not frame:IsShown(), "menu did not suppress the pre-render HUD")
HideFrame(menu)
if frame:IsShown() and Nexus.Panel._lastModel == nil then
    observations.rawMenuRestore = observations.rawMenuRestore + 1
end
Nexus.Panel.Hide()
ShowFrame(menu)
HideFrame(menu)
Check(not frame:IsShown(), "menu restoration overrode explicit hide intent")

-- Panel.Refresh owns a local last-model fallback when Main has not installed
-- its callback yet.  Stop the pre-show acquisition probe from shadowing that
-- real recovery path.
Nexus.Panel.Init({ToggleAuto=function() return false end})

local noBoardModel = {
    status="idle",cards={},recommendation="",auto=false,version="test",
    progress={wishlistName=nil,owned=0,total=0,missing={},shed={},toLock={}},
}
local activeModel = Copy(noBoardModel)
activeModel.status = "active"
activeModel.cards = {{text="Alpha"},{text="Beta"},{text="Gamma"}}
activeModel.recommendation = "Choose Alpha"
activeModel.progress = {
    wishlistName="Stage 33",owned=1,total=3,missing={"Beta","Gamma"},
    shed={},toLock={},activeSlot=1,
}

-- A first widget failure after materialization currently leaves the raw frame
-- visible.  Mutation-before-error also proves this is a real partial apply.
Nexus.Panel.Show()
local rawHeader = header:GetText()
local originalHeaderSetText = header.SetText
header.SetText = function(self, value)
    originalHeaderSetText(self, value)
    error("stage33:first-widget")
end
local firstOk, firstError = pcall(Nexus.Panel.Render, noBoardModel)
header.SetText = originalHeaderSetText
Check(not firstOk and tostring(firstError):find("stage33:first-widget", 1, true),
    "first widget fault did not escape from the real Panel owner")
if frame:IsShown() and header:GetText() ~= rawHeader
    and autoButton:GetText() == "Auto: --" then
    observations.firstWidgetFailure = observations.firstWidgetFailure + 1
end
ShowFrame(menu)
HideFrame(menu)
Check(not frame:IsShown(),
    "menu restoration exposed the failed first-render tree")
Check(Nexus.Panel.Render(noBoardModel) == true,
    "ordinary owner retry did not recover after first widget fault")
observations.recoveries = observations.recoveries + 1
Check(header:GetText():find("Nexus", 1, true) ~= nil
    and (not autoButton:IsShown() or autoButton:GetText() ~= "Auto: --"),
    "first successful recovery did not replace constructor defaults")

local originalApplyOwnedFonts = Nexus.Panel.ApplyOwnedFonts
Nexus.Panel.ApplyOwnedFonts = function()
    observations.setupFaults = observations.setupFaults + 1
    error("stage33:font-setup")
end
local setupOk, setupError = pcall(Nexus.Panel.Render, activeModel)
Nexus.Panel.ApplyOwnedFonts = originalApplyOwnedFonts
Check(not setupOk and tostring(setupError):find("stage33:font-setup", 1, true)
    and not frame:IsShown(),
    "pre-layout widget setup escaped the atomic visibility boundary")
ShowFrame(menu)
HideFrame(menu)
Check(not frame:IsShown(),
    "menu restoration exposed the failed widget-setup tree")
Check(Nexus.Panel.Refresh() == true,
    "Panel did not recover after widget-setup fault")
observations.recoveries = observations.recoveries + 1

-- Layout computation failure is deliberately contained by the real fallback.
-- A later widget failure must not expose a partially applied replacement over
-- the already complete last-good display.
local originalLayout = assert(Nexus.LayoutMetrics.Panel)
Nexus.LayoutMetrics.Panel = function()
    observations.layoutFaults = observations.layoutFaults + 1
    error("stage33:layout")
end
Check(Nexus.Panel.Render(activeModel) == true,
    "contained layout computation fault prevented fallback rendering")
Nexus.LayoutMetrics.Panel = originalLayout
Check(observations.layoutFaults == 1,
    "real layout computation fault was not exercised exactly once")

local lastGoodHeader = header:GetText()
local changedModel = Copy(activeModel)
changedModel.progress.wishlistName = "Stage 33 Replacement"
header.SetText = function(self, value)
    originalHeaderSetText(self, value)
    error("stage33:later-widget")
end
local laterOk, laterError = pcall(Nexus.Panel.Render, changedModel)
header.SetText = originalHeaderSetText
Check(not laterOk and tostring(laterError):find("stage33:later-widget", 1, true),
    "later widget fault did not escape from the real Panel owner")
if frame:IsShown() and header:GetText() ~= lastGoodHeader then
    observations.laterWidgetFailure = observations.laterWidgetFailure + 1
end
ShowFrame(menu)
HideFrame(menu)
Check(not frame:IsShown(),
    "menu restoration exposed the failed replacement tree")
Check(Nexus.Panel.Refresh() == true, "Panel did not recover after later widget fault")
observations.recoveries = observations.recoveries + 1
local directRenderStats = Nexus.Panel.RenderStats()
observations.commits = directRenderStats.commits
observations.renderFailures = directRenderStats.failures
observations.renderRecoveries = directRenderStats.recoveries
Check(directRenderStats.commits == 4 and directRenderStats.failures == 3
    and directRenderStats.recoveries == 3
    and directRenderStats.recoveryRequests == 3,
    "Panel commit/failure/recovery counters lost exact first-render ownership")

-- Re-load the real Panel module to give Main a genuinely unmaterialized HUD;
-- the direct constructor/fault observations above remain captured separately.
_G.NexusPanel = nil
panelRegions, panelButtons = {}, {}
dofile("ui/Panel.lua")

-- Boot the real Main/lifecycle owners on the same Panel.  The first provider
-- read fails transiently; DisplayCall contains it, and an ordinary recompute
-- must later publish the recovered immutable model without gameplay work.
local providerCalls = 0
local recordedErrors = {}
Nexus.Errors = {
    Init=function() return true end,
    SafeText=function(value) return tostring(value) end,
    Record=function(source, value)
        recordedErrors[#recordedErrors + 1] = {
            source=tostring(source),message=tostring(value),
        }
    end,
}
Nexus.ServerStatus = {
    Init=function() end,
    IsUsingNexusHud=function() return true end,
    GetSummary=function()
        providerCalls = providerCalls + 1
        if providerCalls == 1 then
            observations.providerFaults = observations.providerFaults + 1
            error("stage33:provider")
        end
        return {tier="Torment",ash="1234",gain="+5%",intensity=120}
    end,
}
Nexus.DpsCapture = {
    Init=function() end,OnUpdate=function() end,
    GetCharacterBest=function() return nil end,
    GetPlayerInfo=function() return nil end,
    GetPersonalBestForEchoes=function() return nil end,
    GetLeaderboardForEchoes=function() return {} end,
}
Nexus.Release = {
    version="1.20.0-beta.1",baseVersion="1.20.0-beta.1",published=false,
    releasesUrl="https://github.com/Viscerals/Better-Nexus/releases",
}
H.playerLevel = 5
H.granted = {}
H.wishlist = nil

local uploadCalls = 0
local originalUpload = assert(Nexus.GameAdapter.UploadWishlist)
Nexus.GameAdapter.UploadWishlist = function(...)
    uploadCalls = uploadCalls + 1
    return originalUpload(...)
end
dofile("core/AutomationRuntime.lua")
local diagnosticAttempts = 0
local automationFactory = assert(Nexus.MainInternals.AutomationRuntime.New)
Nexus.MainInternals.AutomationRuntime.New = function(options)
    -- Fixed diagnostics are observed without writing test-only history into
    -- the SavedVariables graph whose immutability this fixture verifies.
    options.appendAudit = function() diagnosticAttempts = diagnosticAttempts + 1 end
    options.appendAutoLockEvent = function()
        diagnosticAttempts = diagnosticAttempts + 1
    end
    return automationFactory(options)
end
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/WishlistModel.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")
Nexus.Panel.Show()
local mainFrame = assert(_G.NexusPanel,
    "manual Main-owned first show did not materialize the HUD")
Check(not mainFrame:IsShown(),
    "manual Main-owned first show exposed an uncommitted frame")
observations.mainRecoveryRequests = Nexus.Panel.RenderStats().recoveryRequests
Check(observations.mainRecoveryRequests == 1,
    "manual first show did not request exactly one bounded Main recovery")
H.Advance(0.4, 0.2)
Check(mainFrame:IsShown(),
    "ordinary automation tick did not reveal the committed first HUD model")

local idleSnapshot = assert(Nexus.Panel._lastModel,
    "Main did not publish an initial immutable HUD model")
if type(idleSnapshot.cards) == "table" and #idleSnapshot.cards == 0 then
    observations.idleModels = observations.idleModels + 1
end
Check(observations.providerFaults == 1,
    "transient provider failure was not exercised exactly once")
Check(Nexus.RequestRecompute(), "ordinary provider recovery recompute was refused")
H.Advance(0.2, 0.2)
local recoveredSnapshot = assert(Nexus.Panel._lastModel)
Check(recoveredSnapshot.serverStatus
    and recoveredSnapshot.serverStatus.tier == "Torment",
    "ordinary refresh did not recover the transient provider value")
observations.recoveries = observations.recoveries + 1

-- Preparation and Panel application failures have distinct Main attribution,
-- remain hidden/failed for that call, and recover without reopening the HUD.
Nexus.Performance = {
    Measure=function(path, fn, ...)
        if path == "hud.prepare" then error("stage33:main-prepare") end
        return fn(...)
    end,
}
Check(Nexus.RefreshHudView() == false,
    "Main reported successful HUD preparation after an injected fault")
Check(recordedErrors[#recordedErrors]
    and recordedErrors[#recordedErrors].source == "Main.RefreshHudView.Prepare",
    "Main did not attribute the preparation-stage fault")
Nexus.Performance = nil
Check(Nexus.RefreshHudView() == true,
    "manual HUD refresh did not recover after preparation fault")
observations.recoveries = observations.recoveries + 1

local mainPanelRender = Nexus.Panel.Render
Nexus.Panel.Render = function() error("stage33:main-render") end
Check(Nexus.RefreshHudView() == false,
    "Main reported successful Panel application after an injected fault")
Check(recordedErrors[#recordedErrors]
    and recordedErrors[#recordedErrors].source == "Main.RefreshHudView.Render",
    "Main did not attribute the render-stage fault")
Nexus.Panel.Render = mainPanelRender
Check(Nexus.RefreshHudView() == true,
    "manual HUD refresh did not recover after render fault")
observations.recoveries = observations.recoveries + 1

local baselineDbCopy = Copy(NexusDB)
local baselineDb = Signature(DurableSavedState(NexusDB))
local baselineCatalog = Signature(H.db)
local baselineWire = #H.wire
local baselineAssociations = Nexus.JournalTab.RefreshStats
    and Signature(Nexus.JournalTab.RefreshStats()) or "none"
local baselineMessages = #H.sentChatMessages
local baselineActions = #H.selectCalls + #H.banishCalls + #H.freezeCalls
    + H.rerollCalls + #H.activateCalls + #H.saveCalls
local baselineUploads = uploadCalls

H.wishlist = {
    name="Stage 33 Active",class="MAGE",
    echoes={{spellId=200100,quality=3,stacks=1}},
}
H.DeliverBoard({
    {spellId=200100,quality=3},
    {spellId=200102,quality=2},
    {spellId=200104,quality=1},
})
Check(Nexus.RequestRecompute(), "active-board recompute was refused")
H.Advance(0.2, 0.2)
local activeSnapshot = assert(Nexus.Panel._lastModel)
if type(activeSnapshot.cards) == "table" and #activeSnapshot.cards > 0 then
    observations.activeModels = observations.activeModels + 1
end
H.Perks.currentChoice = nil
Check(Nexus.RequestRecompute(), "no-board recovery recompute was refused")
H.Advance(0.2, 0.2)
local finalSnapshot = assert(Nexus.Panel._lastModel)
if type(finalSnapshot.cards) == "table" and #finalSnapshot.cards == 0 then
    observations.idleModels = observations.idleModels + 1
end

local finalActions = #H.selectCalls + #H.banishCalls + #H.freezeCalls
    + H.rerollCalls + #H.activateCalls + #H.saveCalls
observations.actions = finalActions - baselineActions
observations.uploads = uploadCalls - baselineUploads
for index = baselineMessages + 1, #H.sentChatMessages do
    local text = tostring(H.sentChatMessages[index].text or "")
    if text:find("^WLRB|") or text:find("^WLBI|") then
        observations.syncUploads = observations.syncUploads + 1
    end
end
Check(observations.activeModels == 1 and observations.idleModels >= 2,
    "real Main pipeline missed active-board or no-board immutable models")
Check(observations.actions == 0 and observations.uploads == 0
    and observations.syncUploads == 0 and #H.wire == baselineWire,
    "HUD characterization performed gameplay, upload, Sync, or lever work")
Check(Signature(H.db) == baselineCatalog,
    "HUD characterization mutated the source catalog")
local finalDb = Signature(DurableSavedState(NexusDB))
Check(finalDb == baselineDb,
    "HUD characterization mutated durable SavedVariables after the boot baseline: "
        .. table.concat(ChangedPaths(
            DurableSavedState(baselineDbCopy), DurableSavedState(NexusDB)), ","))
Check(diagnosticAttempts <= 4,
    "ordinary HUD recovery amplified fixed diagnostic attempts")
if Nexus.JournalTab.RefreshStats then
    Check(Signature(Nexus.JournalTab.RefreshStats()) == baselineAssociations,
        "HUD characterization changed association refresh state")
end

print(string.format(
    "Stage 33 observations checks=%d raw_show=%d raw_toggle=%d raw_menu=%d first_partial=%d later_partial=%d setup_faults=%d layout_faults=%d provider_faults=%d recoveries=%d commits=%d render_failures=%d render_recoveries=%d main_requests=%d active=%d idle=%d actions=%d uploads=%d sync_uploads=%d",
    checks, observations.rawShow, observations.rawToggle,
    observations.rawMenuRestore, observations.firstWidgetFailure,
    observations.laterWidgetFailure, observations.setupFaults,
    observations.layoutFaults,
    observations.providerFaults, observations.recoveries,
    observations.commits, observations.renderFailures,
    observations.renderRecoveries, observations.mainRecoveryRequests,
    observations.activeModels, observations.idleModels,
    observations.actions, observations.uploads, observations.syncUploads))

if observations.rawShow > 0 or observations.rawToggle > 0
    or observations.rawMenuRestore > 0
    or observations.firstWidgetFailure > 0
    or observations.laterWidgetFailure > 0 then
    failures[#failures + 1] = string.format(
        "visible uncommitted HUD shell (show=%d toggle=%d menu=%d first_partial=%d later_partial=%d header=%q auto=%q)",
        observations.rawShow, observations.rawToggle,
        observations.rawMenuRestore, observations.firstWidgetFailure,
        observations.laterWidgetFailure, header:GetText(), autoButton:GetText())
end

if #failures > 0 then
    error(string.format("Stage 33.1 expected red (%d): %s",
        #failures, table.concat(failures, " | ")))
end
print("Stage 33 HUD first-render and bounded recovery characterization -- OK")
