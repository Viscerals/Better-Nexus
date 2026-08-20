-- Stage 26.4 expected red: cheap controls and bounded diagnostics must stay
-- responsive while heavy Community/Leaderboard projection work is deferred.
local function Read(path)
    local file = assert(io.open(path, "rb"))
    local value = file:read("*a")
    file:close()
    return value
end

local failures = {}
local function Check(ok, message)
    if not ok then failures[#failures + 1] = message end
end

local community = Read("ui/CommunityRenderer.lua")
local controlAt = community:find("-- Update control labels", 1, true)
local importAt = community:find(
    "local importPending = fs.scope == \"mine\"", 1, true)
Check(controlAt and importAt and controlAt < importAt,
    "Community import-pending path freezes cheap control labels")

local peer = Read("core/PeerDebug.lua")
local explainAt = peer:find("function PeerDebug.ExplainBuild", 1, true)
local formatAt = peer:find("local function FormatFields", explainAt or 1, true)
local explanation = explainAt and formatAt
    and peer:sub(explainAt, formatAt - 1) or ""
Check(explanation:find("Nexus.ViewProjections", 1, true)
        and not explanation:find("CachedQualification", 1, true),
    "Peer Debug still owns a divergent Community exclusion algorithm")
Check(peer:find("RejectionStats", 1, true)
        and peer:find("dps_reject", 1, true),
    "Peer Debug omits bounded DPS rejection reason counters")

local diagnostics = Read("core/MainDiagnostics.lua")
local syncAt = diagnostics:find("local function LogText_Sync", 1, true)
local errorsAt = diagnostics:find("local function LogText_Errors", syncAt or 1,
    true)
local syncPage = syncAt and errorsAt
    and diagnostics:sub(syncAt, errorsAt - 1) or ""
Check(syncPage:find("catalog.Count", 1, true)
        and syncPage:find("BeginSummaryCursor", 1, true)
        and syncPage:find("SummaryCursorNext", 1, true)
        and not syncPage:find("catalog.All", 1, true),
    "Sync diagnostic still deep-copies the complete build catalog")

local viewer = Read("ui/LogViewer.lua")
Check(viewer:find("peerRefreshElapsed", 1, true)
        and viewer:find("debugOwner.IsEnabled", 1, true),
    "visible active Peer Test has no bounded age refresh owner")

-- The Peer Test refresh owner performs work once per visible active second,
-- and no recurring provider work while hidden or disabled.
local H = dofile("tests/harness.lua")
local peerEnabled, peerReports = true, 0
Nexus = {
    Panel={AttachMenuFrame=function() end,CloseOtherWindows=function() end},
    Theme={StyleWindow=function() end},
    PeerDebug={
        IsEnabled=function() return peerEnabled end,
        Start=function() peerEnabled=true return true end,
        Stop=function() peerEnabled=false return true end,
        Clear=function() peerEnabled=false return true end,
    },
}
dofile("ui/LogViewer.lua")
Nexus.LogViewer.Init(function(tab)
    peerReports=peerReports+1
    return "bounded "..tostring(tab).." report"
end, function() return true end)
Nexus.LogViewer.Show("peer")
local logFrame = H.frames.NexusLogViewer
local peerTicker = logFrame and logFrame:GetScript("OnUpdate")
Check(type(peerTicker)=="function",
    "Peer Test window did not install its visible refresh ticker")
if type(peerTicker)=="function" then
    peerTicker(logFrame,0.9)
    Check(peerReports==0,"Peer Test refreshed before its one-second bound")
    peerTicker(logFrame,0.2)
    Check(peerReports==1,"visible active Peer Test did not refresh once")
    logFrame:Hide()
    peerTicker(logFrame,3)
    Check(peerReports==1,"hidden Peer Test performed recurring provider work")
    peerEnabled=false
    Nexus.LogViewer.Show("peer")
    peerTicker(logFrame,3)
    Check(peerReports==1,"disabled Peer Test performed recurring provider work")
end

-- A large Sync diagnostic reads only count plus at most 100 summaries. The
-- complete catalog and nested Echo rows remain available to full export but
-- are never copied into this interactive page.
local catalogCalls = {all=0,count=0,begin=0,next=0}
Nexus = {VERSION="stage26.4",MainInternals={}}
Nexus.Sync = {
    ChannelName=function() return "Nexus" end,
    IsConnected=function() return true end,
    ChannelIndex=function() return 1 end,
    IsReceiving=function() return false end,
    ReceiveTimeLeft=function() return 0 end,
    LastSyncNewCount=function() return 0 end,
    Stats=function() return {} end,
    TombstoneCount=function() return 0 end,
    EventLog=function() return {} end,
}
Nexus.BuildCatalog = {
    All=function() catalogCalls.all=catalogCalls.all+1
        error("unbounded catalog copy") end,
    Count=function() catalogCalls.count=catalogCalls.count+1 return 1109 end,
    BeginSummaryCursor=function()
        catalogCalls.begin=catalogCalls.begin+1 return {index=0}
    end,
    SummaryCursorNext=function(cursor)
        catalogCalls.next=catalogCalls.next+1
        cursor.index=cursor.index+1
        if cursor.index>1109 then return nil,true end
        return {id="build-"..cursor.index,title="Build "..cursor.index,
            author="Peer",isMine=cursor.index%2==0,echoCount=79,
            lastModified=cursor.index},false
    end,
}
dofile("core/MainDiagnostics.lua")
local diagnosticOwner = Nexus.MainInternals.Diagnostics.New({
    nexus=Nexus,adapter={},model={},strategy={},store={},
    wishlistWithLockTargets=function(value) return value end,
    lockDesignTargetsFor=function() return {} end,
    effectiveFlags=function() return {} end,
})
local syncText = diagnosticOwner.GetPageText("sync")
Check(catalogCalls.all==0 and catalogCalls.count==1
        and catalogCalls.begin==1 and catalogCalls.next==100,
    "1,109-build Sync diagnostic exceeded its bounded summary reads")
Check(syncText:find("library total: 1109",1,true)
        and syncText:find("list capped at 100 summary reads",1,true),
    "bounded Sync diagnostic did not report total and truncation truthfully")

-- A diagnostic provider fault must degrade inside the page instead of
-- escaping through the copy window. Exercise both cursor ownership edges.
local beginSummaryCursor = Nexus.BuildCatalog.BeginSummaryCursor
local summaryCursorNext = Nexus.BuildCatalog.SummaryCursorNext
Nexus.BuildCatalog.BeginSummaryCursor = function()
    error("cursor construction failed")
end
local beginOk, beginText = pcall(diagnosticOwner.GetPageText, "sync")
Check(beginOk and tostring(beginText):find("library total: 1109",1,true),
    "Sync diagnostic escaped a summary-cursor construction failure")

Nexus.BuildCatalog.BeginSummaryCursor = beginSummaryCursor
Nexus.BuildCatalog.SummaryCursorNext = function()
    error("cursor read failed")
end
local readOk, readText = pcall(diagnosticOwner.GetPageText, "sync")
Check(readOk and tostring(readText):find("bounded summary unavailable",1,true),
    "Sync diagnostic escaped or hid a bounded summary read failure")
Check(catalogCalls.all==0,
    "diagnostic failure fallback copied the complete build catalog")
Nexus.BuildCatalog.SummaryCursorNext = summaryCursorNext

if #failures > 0 then
    error("EXPECTED RED [Stage 26.4 Sync UI responsiveness]:\n - "
        .. table.concat(failures, "\n - "))
end
print("Stage 26.4 Sync UI responsiveness and bounded diagnostics -- OK")
