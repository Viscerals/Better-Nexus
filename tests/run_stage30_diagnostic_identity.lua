-- Stage 30 bounded view diagnostics and private runtime identity. Diagnostic
-- snapshots are fixed-shape scalar state, remain idle in the background, and
-- the private label is display-only: public version, protocol, and wire bytes
-- do not change with it.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

local failures = {}
local function Check(name, condition, detail)
    if not condition then
        failures[#failures + 1] = name .. ": " .. tostring(detail)
    end
end

local function Read(path)
    local file = assert(io.open(path, "r"))
    local value = file:read("*a")
    file:close()
    return value
end

Nexus.VERSION = Nexus.Release and Nexus.Release.version or "missing"
local publicVersion = Nexus.VERSION
local labelReader = Nexus.RuntimeBuildLabel
Check("central_runtime_label_accessor", type(labelReader) == "function",
    "Nexus.RuntimeBuildLabel is unavailable")
local function RuntimeLabel()
    return type(labelReader) == "function" and labelReader() or "missing"
end
Check("source_runtime_label", RuntimeLabel() == "source",
    "label=" .. RuntimeLabel())
if Nexus.Release then Nexus.Release.buildLabel = "test.13-abcdef0" end
Check("private_runtime_label", RuntimeLabel() == "test.13-abcdef0",
    "label=" .. RuntimeLabel())
for _, invalidLabel in ipairs({"unsafe|private title", "development",
    "test.13-ABCDEF0", "test.13-abcdef", "test.13-abcdef0123456"}) do
    if Nexus.Release then Nexus.Release.buildLabel = invalidLabel end
    Check("invalid_runtime_label_fails_closed_" .. invalidLabel,
        RuntimeLabel() == "source", "label=" .. RuntimeLabel())
end
if Nexus.Release then Nexus.Release.buildLabel = "source" end

NexusDB = {
    settingsVersion=2,settings={},chars={},communityBuilds={},
    buildFilters={
        scope="all",classFilter="MAGE",currentClassOnly=true,
        qualifiedOnly=false,search="private title",sortMode="title",
        page=2,pageSize=20,
    },
    dpsCapture={characterBest={dummy={},lk={}},personalBest={},buildBest={}},
}
Nexus.Store.Init()
UnitName = function() return "DiagnosticMage" end
GetNormalizedRealmName = function() return "Ebonhold" end
UnitClass = function() return "Mage", "MAGE" end

Nexus.Sync = {
    WorkState=function() return {outbound=0} end,
    Stats=function() return {sent=0,received=0} end,
    ChannelName=function() return "wrbuildssync" end,
    ChannelIndex=function() return 1 end,
    IsConnected=function() return true end,
    IsReceiving=function() return true end,
    ReceiveTimeLeft=function() return 10 end,
    LastSyncNewCount=function() return 0 end,
    GetLeaderboardSyncStatus=function()
        return "syncing",0,0,{receiving=1}
    end,
}
Nexus.DpsCapture = {
    ProtocolVersion=function() return 7 end,
    HashCacheStats=function() return {initialized=false} end,
    RejectionStats=function() return {} end,
    OutboundStats=function() return {} end,
    GetDpsBoard=function() return {} end,
    GetDebugLog=function() return "DPS FIXTURE" end,
}

local Adapter = {
    Slots=function() return {bySlot={},activeSlot=0,maxSlots=5} end,
    GetLoadoutWishlist=function() return nil end,
    GetWishlistCandidates=function() return {} end,
    Catalog=function() return {rows={},familyName={}} end,
    Owned=function() return {bySpell={},byFamily={},distinct=0,synced=true} end,
    LockedOwned=function() return {bySpell={},byFamily={}} end,
    Wishlist=function() return nil end,
    WishlistNote=function() return nil end,
    Charges=function()
        return {banish=0,reroll=0,freeze=0,trustworthy=true}
    end,
    Level=function() return 80 end,
    PresentationRevisions=function() return 0,0,0,0,0,0,0,0,0,0,0 end,
}

dofile("ui/CommunityBuilds.lua")
dofile("ui/Leaderboard.lua")
Nexus.CommunityBuilds.Init(Adapter, nil)
Nexus.Leaderboard.Init(Adapter)

local snapshotKeys = {
    blockedReason=true,catalogCount=true,filterCategory=true,
    filterClass=true,filterCurrentClassOnly=true,
    filterQualifiedOnly=true,filterScope=true,filterSearchActive=true,
    filterSort=true,lastPublicationAge=true,pageCount=true,
    projectionCurrent=true,projectionDirty=true,projectionPending=true,
    publishedPage=true,publishedRows=true,requestedPage=true,schema=true,
    savedImportPending=true,savedImportPhase=true,syncReceiving=true,view=true,
}
local communityStatusKeys = {
    bundledCount=true,overlayCount=true,availableCount=true,
    filterMatchedCount=true,qualifyingCount=true,resultCount=true,
    displayedCount=true,searchActive=true,catalogVersion=true,
}
local snapshotKeyCount = 0
for _ in pairs(snapshotKeys) do snapshotKeyCount = snapshotKeyCount + 1 end

local function Snapshot(ownerName, owner)
    local reader = owner and owner.DiagnosticSnapshot
    Check(ownerName .. "_snapshot_reader", type(reader) == "function",
        "DiagnosticSnapshot is unavailable")
    if type(reader) ~= "function" then return nil end
    local ok, snapshot = pcall(reader)
    Check(ownerName .. "_snapshot_call", ok and type(snapshot) == "table",
        snapshot)
    if not ok or type(snapshot) ~= "table" then return nil end
    local expectedKeys = {}
    for key in pairs(snapshotKeys) do expectedKeys[key] = true end
    if ownerName:find("community",1,true) == 1 then
        for key in pairs(communityStatusKeys) do expectedKeys[key] = true end
    end
    local count = 0
    for key, value in pairs(snapshot) do
        count = count + 1
        Check(ownerName .. "_known_key_" .. tostring(key), expectedKeys[key],
            "unexpected key")
        local kind = type(value)
        Check(ownerName .. "_scalar_" .. tostring(key),
            kind == "string" or kind == "number" or kind == "boolean",
            "kind=" .. kind)
    end
    for key in pairs(expectedKeys) do
        Check(ownerName .. "_required_key_" .. key, snapshot[key] ~= nil,
            "missing")
    end
    local expectedCount = snapshotKeyCount
        + (ownerName:find("community",1,true) == 1 and 9 or 0)
    Check(ownerName .. "_fixed_key_count", count == expectedCount,
        string.format("count=%d expected=%d", count, expectedCount))
    local serialized = {}
    for key, value in pairs(snapshot) do
        serialized[#serialized + 1] = tostring(key) .. "=" .. tostring(value)
    end
    serialized = table.concat(serialized, "|")
    for _, forbidden in ipairs({"private title", "DiagnosticMage", "Ebonhold",
        "spellId", "echoes", "packet", "payload", "NexusDB", "C:\\"}) do
        Check(ownerName .. "_privacy_" .. forbidden,
            not serialized:find(forbidden, 1, true), "leaked " .. forbidden)
    end
    return snapshot
end

local communitySnapshot = Snapshot("community", Nexus.CommunityBuilds)
local leaderboardSnapshot = Snapshot("leaderboard", Nexus.Leaderboard)
if communitySnapshot then
    Check("community_hidden_reason", communitySnapshot.blockedReason == "hidden",
        communitySnapshot.blockedReason)
    Check("community_filter_is_sanitized",
        communitySnapshot.filterSearchActive == true
            and communitySnapshot.filterClass == "MAGE"
            and communitySnapshot.requestedPage == 2,
        "filter state is incomplete")
end
if leaderboardSnapshot then
    Check("leaderboard_hidden_reason",
        leaderboardSnapshot.blockedReason == "hidden",
        leaderboardSnapshot.blockedReason)
end

local savedBuildFilters = NexusDB.buildFilters
NexusDB.buildFilters = nil
local readOnlyFilterSnapshot = Snapshot("community_read_only", Nexus.CommunityBuilds)
Check("diagnostic_snapshot_does_not_initialize_savedvariables",
    NexusDB.buildFilters == nil and readOnlyFilterSnapshot ~= nil,
    "diagnostic acquisition mutated NexusDB.buildFilters")
NexusDB.buildFilters = savedBuildFilters

local diagnosticReads = 0
local communityReader = Nexus.CommunityBuilds.DiagnosticSnapshot
local leaderboardReader = Nexus.Leaderboard.DiagnosticSnapshot
if type(communityReader) == "function" then
    Nexus.CommunityBuilds.DiagnosticSnapshot = function()
        diagnosticReads = diagnosticReads + 1
        return communityReader()
    end
end
if type(leaderboardReader) == "function" then
    Nexus.Leaderboard.DiagnosticSnapshot = function()
        diagnosticReads = diagnosticReads + 1
        return leaderboardReader()
    end
end
H.Advance(1, 0.2)
Check("hidden_diagnostics_zero_background_reads", diagnosticReads == 0,
    "reads=" .. diagnosticReads)

Nexus.DiagnosticLogs = {
    Snapshot=function() return {} end,
    Append=function() return true end,
    ClearAll=function() return true end,
}
Nexus.Errors = Nexus.Errors or {}
Nexus.Errors.History = function() return {} end
Nexus.Performance = Nexus.Performance or {}
Nexus.Performance.Snapshot = function()
    return {enabled=true,clockAvailable=true,clockFailures=0,rows={}}
end

dofile("core/MainDiagnostics.lua")
local diagnostics
local pageProvider
diagnostics = Nexus.MainInternals.Diagnostics.New({
    nexus=Nexus,adapter=Adapter,model={},strategy={Compile=function() return {} end},
    store=Nexus.Store,wishlistWithLockTargets=function(value) return value end,
    lockDesignTargetsFor=function() return {} end,effectiveFlags=function() return {} end,
    now=function() return H.now end,getAutoEnabled=function() return false end,
    getDatabase=function() return NexusDB end,ensureDatabase=function() return NexusDB end,
    getPageProvider=function() return pageProvider end,
})
pageProvider = function(key) return diagnostics.GetPageText(key) end

if Nexus.Release then Nexus.Release.buildLabel = "test.13-abcdef0" end
local stateText = diagnostics.GetPageText("state")
Check("explicit_state_reads_both_views", diagnosticReads == 2,
    "reads=" .. diagnosticReads)
Check("state_runtime_label", stateText:find("build=test.13-abcdef0",1,true),
    stateText)
for _, field in ipairs({"PERSISTED VIEW DIAGNOSTICS",
    "community ","leaderboard ","blocked=hidden","catalog=0",
    "projection="}) do
    Check("state_field_" .. field,
        stateText:find(field,1,true) ~= nil, "missing field")
end
Check("state_diagnostic_privacy",
    not stateText:find("private title",1,true)
        and not stateText:find("DiagnosticMage",1,true),
    "state page leaked unrestricted filter/player data")

local function Drain(job)
    local result
    while coroutine.status(job) ~= "dead" do
        local ok, value = coroutine.resume(job)
        assert(ok, "diagnostic export failed: " .. tostring(value))
        if coroutine.status(job) == "dead" then result = value end
    end
    return result or ""
end
local exportText = Drain(diagnostics.NewAIExportCoroutine())
Check("export_runtime_label",
    exportText:find("version=" .. publicVersion
        .. "|build=test.13-abcdef0|",1,true) ~= nil,
    "full export did not identify the private runtime")

local visibleProviderCalls = 0
local originalCreateFrame = CreateFrame
local logViewerFrames = {}
CreateFrame = function(...)
    local created = originalCreateFrame(...)
    logViewerFrames[#logViewerFrames + 1] = created
    return created
end
dofile("ui/LogViewer.lua")
Nexus.LogViewer.Init(function(key)
    visibleProviderCalls = visibleProviderCalls + 1
    return diagnostics.GetPageText(key)
end)
local function TickLogViewer(seconds, step)
    local elapsed = 0
    step = step or 0.05
    while elapsed < seconds - 1e-9 do
        H.now = H.now + step
        elapsed = elapsed + step
        for _, candidate in ipairs(logViewerFrames) do
            local handler = candidate.scripts and candidate.scripts.OnUpdate
            if handler then handler(candidate, step) end
        end
    end
end
TickLogViewer(0.2)
Check("unopened_log_viewer_zero_reads", visibleProviderCalls == 0,
    "calls=" .. visibleProviderCalls)
Nexus.LogViewer.Show("state")
TickLogViewer(0.2)
Check("visible_log_viewer_explicit_state_refresh",
    visibleProviderCalls == 1 and diagnosticReads >= 6,
    string.format("provider=%d snapshots=%d",
        visibleProviderCalls, diagnosticReads))
local logFrame = H.frames.NexusLogViewer
if logFrame then logFrame:Hide() end
local hiddenProviderCalls = visibleProviderCalls
TickLogViewer(1.2, 0.2)
Check("hidden_log_viewer_zero_recurring_reads",
    visibleProviderCalls == hiddenProviderCalls,
    string.format("before=%d after=%d",
        hiddenProviderCalls, visibleProviderCalls))
CreateFrame = originalCreateFrame

dofile("core/PeerDebug.lua")
Nexus.PeerDebug.Init()
Nexus.PeerDebug.Start("")
local peerText = Nexus.PeerDebug.Report()
Check("peer_runtime_label",
    peerText:find("version=" .. publicVersion
        .. " build=test.13-abcdef0 protocol=7",1,true) ~= nil,
    "Peer Test did not identify the private runtime")

dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua")
local protocol = Nexus.SyncInternals.Protocol.New({
    limits={maxTransferIdBytes=160,maxHashBytes=192,maxVersionBytes=32,
        maxBuildIdBytes=96,maxBuildEchoes=256,maxWireFields=8},
    parseVersion=Nexus.Version.Parse,
    ownerKeyMatchesAuthor=function() return true end,
    isSafeTree=Nexus.Codec.IsSafeTree,
})
local wireBuild = {id="wire-1",title="Build",author="Peer",class="MAGE",
    lastModified=1,echoes={{spellId=200100,quality=3,stacks=1}}}
Nexus.Release.buildLabel = "source"
local sourceWire = Nexus.Codec.JSONEncode(protocol.CompactEncode(wireBuild))
Nexus.Release.buildLabel = "test.13-abcdef0"
local privateWire = Nexus.Codec.JSONEncode(protocol.CompactEncode(wireBuild))
Check("runtime_label_is_not_wire_input", sourceWire == privateWire,
    "compact Sync bytes changed")
Check("runtime_label_is_not_update_input",
    Nexus.VERSION == publicVersion
        and Nexus.Version.Compare(publicVersion, Nexus.Release.version) == 0,
    "public semantic version changed")
Check("protocol_stays_seven", Nexus.DpsCapture.ProtocolVersion() == 7,
    "protocol=" .. tostring(Nexus.DpsCapture.ProtocolVersion()))

local mainSource = Read("core/Main.lua")
Check("status_runtime_label_accessor",
    mainSource:find("Nexus.RuntimeBuildLabel()",1,true)
        and mainSource:find("build=",1,true),
    "/nexus status does not use the central runtime label")

Nexus.Release.buildLabel = "source"
if #failures > 0 then
    error("Stage 30 diagnostic/identity regression failed ("
        .. #failures .. "):\n - " .. table.concat(failures, "\n - "))
end
print("Stage 30 bounded view diagnostics, explicit refresh, runtime identity, and compatibility isolation -- OK")
