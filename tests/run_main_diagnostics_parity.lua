-- Main diagnostics retain exact page/export text, isolated coroutine state,
-- selective clear ownership, and a passive dependency boundary after extraction.
Nexus = {
    VERSION="test.13.1",
    MainInternals={},
    RuntimeBuildLabel=function() return "source" end,
}

local decisions = {{
    t="01:02:03", level=5, horizon=2, gIndex=1, activeSlot=1, run=7, queueN=1,
    charges={b=1,r=2,f=3,ok=true},
    proposal={type="take",spellId=101,reason="target",endgame=false},
    cards={{name="Alpha",id=101,fam=10,cardQ=3,catQ=3,wishQ=3,
        maxStack=1,owned=1,delta=0,ann="take",wished=true,g=true}},
    user={{kind="SelectPerk",arg=101}}, pending="queue",
    queueHead={{id=101,fam=10,wished=true}},
}}
local audits = {{kind="RUN_START",t="01:02:03",run=7}}
local probes = {{t="01:02:03",event="shown",detail="fixture"}}
local locks = {{t="01:02:03",action="lock",name="Alpha",spellId=101,ok=true}}
local snapshots = {decision=decisions,runAudit=audits,uiProbe=probes,autoLock=locks}
local appendCalls, durableClears = {}, 0
Nexus.DiagnosticLogs = {
    Snapshot=function(key) return snapshots[key] or {} end,
    Append=function(key, value)
        appendCalls[#appendCalls + 1] = {key=key,value=value}
        return true
    end,
    ClearAll=function() durableClears=durableClears+1; return true end,
}

local errorClears, perfClears, syncClears, dpsClears, peerClears = 0, 0, 0, 0, 0
Nexus.Errors = {
    History=function() return {{timestamp="01:02:04",source="fixture",message="kept"}} end,
    Format=function() return "ERROR HISTORY\n  fixture: kept" end,
    Clear=function() errorClears=errorClears+1; return true end,
}
local performanceRows = {
    {name="automation.step",count=2,total=3.5,maximum=2.5,last=1},
    {name="sync.incoming",count=1,total=4,maximum=4,last=4},
    {name="views.refresh",count=0,total=0,maximum=0,last=0},
    {name="hud.prepare",count=3,total=1.5,maximum=0.75,last=0.5},
}
Nexus.Performance = {
    Snapshot=function() return {enabled=true,clockAvailable=true,clockFailures=0,
        rows=performanceRows} end,
    Reset=function() perfClears=perfClears+1; return true end,
}
Nexus.Sync = {
    ChannelName=function() return "Nexus" end,
    IsConnected=function() return true end,
    ChannelIndex=function() return 4 end,
    IsReceiving=function() return false end,
    ReceiveTimeLeft=function() return 0 end,
    LastSyncNewCount=function() return 1 end,
    Stats=function() return {sent=2,received=3,updated=1,skippedUpToDate=4,
        duplicatesSkipped=5,malformedRejected=6,ignoredOutsideWindow=7,
        oversizeDropped=8,requestId="100-1234",useful=true,
        requestNew=1,requestUpdated=2,requestShares=3,
        requestDuplicates=4,requestRejected=5,requestBaseline=6,
        requestUnrelated=7,requestLastReason="schema",
        terminalReason="peer_state_unconfirmed",queueOutcome="sent",
        operationQueued=10,operationAttempted=11,operationRequeued=12,
        operationSentAttempted=13,operationExpired=14,operationDropped=15,
        operationSuperseded=16,operationReset=17,
        operationThrottleExhausted=18,operationAccepted=0,
        operationRejected=19} end,
    TombstoneCount=function() return 9 end,
    EventLog=function() return {{t=10,cat="RX",text="fixture"}} end,
    ClearLog=function() syncClears=syncClears+1; return true end,
}
local diagnosticBuilds = {{title="Golden",echoCount=1,
    isMine=true,lastModified=9}}
Nexus.BuildCatalog = {
    All=function() error("Sync diagnostics must not deep-copy BuildCatalog.All") end,
    Count=function() return #diagnosticBuilds end,
    BeginSummaryCursor=function() return {index=0} end,
    SummaryCursorNext=function(cursor)
        cursor.index=cursor.index+1
        local row=diagnosticBuilds[cursor.index]
        return row,row==nil
    end,
}
Nexus.DpsCapture = {
    GetDebugLog=function() return "DPS FIXTURE" end,
    ClearDebugLog=function() dpsClears=dpsClears+1; return true end,
}
Nexus.PeerDebug = {
    Report=function() return "PEER TEST FIXTURE" end,
    Clear=function() peerClears=peerClears+1; return true end,
}
Nexus.CommunityBuilds = {DiagnosticSnapshot=function() return {
    schema=1,view="community",catalogCount=1,requestedPage=2,
    bundledCount=504,overlayCount=1,availableCount=505,
    filterMatchedCount=42,qualifyingCount=7,resultCount=7,
    displayedCount=7,searchActive=true,
    catalogVersion="1.19.4-05efb360ae5b",
    publishedPage=1,pageCount=3,publishedRows=20,filterScope="all",
    filterClass="MAGE",filterCurrentClassOnly=true,
    filterQualifiedOnly=false,filterSearchActive=true,filterSort="title",
    filterCategory="builds",projectionCurrent=false,
    projectionPending=true,projectionDirty=true,savedImportPending=true,
    savedImportPhase="slots",syncReceiving=true,lastPublicationAge=1.2,
    blockedReason="projection-pending",
} end}
Nexus.Leaderboard = {DiagnosticSnapshot=function() return {
    schema=1,view="leaderboard",catalogCount=1,requestedPage=1,
    publishedPage=1,pageCount=1,publishedRows=4,filterScope="all",
    filterClass="ALL",filterCurrentClassOnly=false,
    filterQualifiedOnly=false,filterSearchActive=false,filterSort="dps",
    filterCategory="lk",projectionCurrent=true,projectionPending=false,
    projectionDirty=false,savedImportPending=false,savedImportPhase="idle",
    syncReceiving=false,lastPublicationAge=0.5,blockedReason="none",
} end}

local catalog = {
    rows={[101]={name="Alpha",quality=3,family=10}},
    familyName={[10]="Ten"}, familyMembers={[10]={101}},
}
local wishlist = {name="Golden",source="fixture",entries={{spellId=101,
    family=10,quality=3,stacks=1}}}
local adapter = {
    Catalog=function() return catalog end,
    Wishlist=function() return wishlist end,
    WishlistNote=function() return "fixture note" end,
    LockedOwned=function() return {bySpell={[101]=1}} end,
    Owned=function() return {byFamily={[10]=1},bySpell={[101]=1},synced=true} end,
    Slots=function() return {activeSlot=1,bySlot={[1]={name="Active",verified=true,
        echoes={{spellId=101,family=10,quality=3,stacks=1,locked=true}}}}} end,
    Charges=function() return {banish=1,reroll=2,freeze=3,trustworthy=true} end,
    Level=function() return 5 end,
}
local settings = {autoPick=true,autoActivate=false,autoBanish=true,
    autoSave=false,autoDisable=false,autoLockEchoes=true}
local database = {lastSaveRefusal=nil,lastSaveStatus={keep=true},auditRunCounter=7,
    settings=settings,future={keep=true}}
local resetAuditCalls, ensureDatabaseCalls = 0, 0
local owner
local pageProvider
UnitName = function() return "Hero" end
date = function() return "04:05:06" end

dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
owner = Nexus.MainInternals.Diagnostics.New({
    nexus=Nexus,adapter=adapter,
    model={EffectiveWishedQuality=function() return 3 end},
    strategy={Compile=function() return {wishedFamilies={[10]=true}} end},
    store={Settings=function() return settings end},
    wishlistWithLockTargets=function(value) return value end,
    lockDesignTargetsFor=function() return {[101]=true} end,
    effectiveFlags=function() return {safe=true} end,
    errorText=function(value) return tostring(value) end,
    now=function() return 10 end,
    getAutoEnabled=function() return true end,
    getAutoLockTrace=function() return {at=9,lines={"trace line"}} end,
    getAuditRunId=function() return 7 end,
    getDatabase=function() return database end,
    ensureDatabase=function()
        ensureDatabaseCalls=ensureDatabaseCalls+1
        return database
    end,
    resetAuditState=function() resetAuditCalls=resetAuditCalls+1 end,
    getPageProvider=function() return pageProvider end,
})
pageProvider = function(key) return owner.GetPageText(key) end

local expected = {
    boards=table.concat({
        "DECISION LOG -- 1 boards (vtest.13.1)","",
        "== #1 [01:02:03] L5 H:2  charges B:1 R:2 F:3",
        "  1[G] Alpha id=101 fam=10 q=3/cat:3 wishQ=3 max=1 own=1 d=0 take",
        "  proposal: take 101 (target)","  USER: SelectPerk(101)",
        "  pending guarantee: queue","",
    },"\n"),
    mismatch="MISMATCHES -- boards where your manual play differed\n\n(none recorded yet)",
    ai_export="Press Copy Full Diagnostic Log. Nexus builds the complete export gradually to avoid a frame hitch.",
    locked=table.concat({
        "LOCKED ECHOES -- 1 total (permanent; Nexus can only read these, never lock/unlock them)",
        "  Alpha (id=101)","","WISHLIST 'Golden' -- 1 total Echo copies (1 distinct entries)","",
        "Every locked Echo is also on this wishlist -- no obvious swap candidates.","",
        "No overflow -- everything on this wishlist fits within the 79-slot cap.",
    },"\n"),
    wishlist=table.concat({
        "WISHLIST 'Golden' source=fixture -- 1 entries","plan.wishedFamilies: 1 families","",
        "Alpha id=101 q=3 stacks=1 fam=10 'Ten' effWishQ=3 own=1",
        "    variants: 101:q3","","all wishlist entries resolved into the plan",
    },"\n"),
    state=table.concat({
        "vtest.13.1  build=source  level=5  auto=true","charges B:1 R:2 F:3 trustworthy=true",
        "flag safe = true",
        "settings: autoPick=true autoActivate=false autoBanish=true autoSave=false autoDisable=false autoLockEchoes=true",
        "","PERSISTED VIEW DIAGNOSTICS (bounded sanitized scalars):",
        "community catalog=1 page=requested:2 published:1 count:3 rows:20",
        "  catalog_status bundled=504 overlay=1 available=505 filter_matched=42 qualifying=7 results=7 displayed=7 search=true version=1.19.4-05efb360ae5b",
        "  filters scope=all class=MAGE current=true qualified=false search=true sort=title category=builds",
        "  projection=current:false pending:true dirty:true import=pending:true phase:slots receiving=true publication_age=1.2s blocked=projection-pending",
        "leaderboard catalog=1 page=requested:1 published:1 count:1 rows:4",
        "  filters scope=all class=ALL current=false qualified=false search=false sort=dps category=lk",
        "  projection=current:true pending:false dirty:false import=pending:false phase:idle receiving=false publication_age=0.5s blocked=none",
        "","SLOTS (activeSlot=1):","  slot 1 'Active' verified=true echoes=1",
        "      id=101 fam=10 q=3 stacks=1 locked wished=true","","OWNED byFamily:",
        "  10 'Ten' x1","owned synced=true",
    },"\n"),
    dps="DPS FIXTURE",
    errors="ERROR HISTORY\n  fixture: kept",
    autolock=table.concat({
        "AUTO-LOCK TRACE (last run 1.0s ago)","","trace line","",
        "COMMITTED LOCK-DESIGN TARGETS (what TryAutoLock is actually working from):",
        "  Alpha (id=101) -- fresh target, no replacement pairing [FULFILLED -- already locked]","",
        "LOCK/UNLOCK EVENT HISTORY (actual write attempts only, oldest first):",
        "  [01:02:03] LOCK Alpha (id=101) ok=true",
    },"\n"),
    sync=table.concat({
        "SYNC DIAGNOSTICS -- Nexus vtest.13.1","","-- connection --",
        "channel name   : Nexus","connected      : true","channel index  : 4",
        "my name        : Hero","receiving now  : false (0s left)",
        "last sync new  : 1 build(s)",
        "request outcome: id=100-1234 useful=true new=1 updated=2 share=3",
        "request non-useful: baseline=6 duplicate=4 rejected=5 unrelated=7",
        "request terminal: reason=peer_state_unconfirmed queue=sent last=schema",
        "operation flow: queued=10 attempted=11 requeued=12 sent-attempted=13",
        "operation terminal: expired=14 dropped=15 superseded=16 reset=17 throttle-exhausted=18 accepted=0 rejected=19",
        "","-- counters --",
        "messages sent          : 2","builds stored (new)    : 2",
        "builds updated         : 1","skipped (peer up2date) : 4",
        "duplicates skipped     : 5","malformed rejected     : 6",
        "storage rejected       : 0",
        "ignored (no sync open) : 7","oversize dropped       : 8",
        "deleted (tombstoned)   : 9","","-- builds in my library --",
        string.format("  [MINE]  %-28s %2d echoes  stamp=%s","Golden",1,9),
        "  library total: 1; listed: 1 mine, 0 from others","","-- event log (newest last) --",
        string.format("  [%7.2fs] %-5s %s",0,"RX","fixture"),
    },"\n"),
    perf=table.concat({
        "PERFORMANCE AGGREGATES -- this session only",
        "Observational milliseconds; no per-call samples or SavedVariables history.",
        "enabled=true clockAvailable=true clockFailures=0","",
        "path                         count    total ms      max ms     last ms",
        string.format("%-28s %7d %11.3f %11.3f %11.3f",
            "automation.step",2,3.5,2.5,1),
        string.format("%-28s %7d %11.3f %11.3f %11.3f",
            "sync.incoming",1,4,4,4),
        string.format("%-28s %7d %11.3f %11.3f %11.3f",
            "views.refresh",0,0,0,0),
        string.format("%-28s %7d %11.3f %11.3f %11.3f",
            "hud.prepare",3,1.5,0.75,0.5),
    },"\n"),
    peer="PEER TEST FIXTURE",
}
for key, golden in pairs(expected) do
    local actual = owner.GetPageText(key)
    assert(actual == golden, "diagnostic page bytes changed for " .. key
        .. "\nEXPECTED:\n" .. golden .. "\nACTUAL:\n" .. tostring(actual))
end
assert(owner.GetPageText("missing") == "unknown tab: missing",
    "unknown diagnostic tab fallback changed")
print("all diagnostic pages retain golden bytes -- OK")

local sourceFile = assert(io.open("core/Main.lua","r"))
local source = sourceFile:read("*a")
sourceFile:close()
assert(not source:find("local function LogText_",1,true)
    and not source:find("local function DiagnosticTable",1,true)
    and source:find("function Nexus.NewAIExportCoroutine()",1,true)
    and source:find("function Nexus.GetDiagnosticPageText(tabKey)",1,true),
    "Main still owns diagnostic construction or lost its public delegates")
assert(source:find("type(diagnosticsFactory.New) == \"function\"",1,true),
    "Main does not fail closed when its required diagnostics owner is unavailable")

assert(owner.AppendAudit("PARITY",{value="kept"})
    and appendCalls[#appendCalls].key == "runAudit"
    and appendCalls[#appendCalls].value.kind == "PARITY"
    and appendCalls[#appendCalls].value.t == "04:05:06"
    and appendCalls[#appendCalls].value.run == 7,
    "audit formatting or retained-history routing changed")

for index=2,10 do decisions[index]=decisions[1] end
for index=2,8 do audits[index]=audits[1] end
for index=2,10 do probes[index]=probes[1] end
local function Drain(job)
    local yields, result = {}, nil
    while coroutine.status(job) ~= "dead" do
        local ok, value = coroutine.resume(job)
        assert(ok, "diagnostic export failed: " .. tostring(value))
        if coroutine.status(job) == "dead" then result=value else yields[#yields+1]=value end
    end
    return table.concat(yields,"\n"), result
end
local yieldTrace, exportText = Drain(owner.NewAIExportCoroutine())
local yieldTraceAgain, exportTextAgain = Drain(owner.NewAIExportCoroutine())
local expectedYieldTrace = table.concat({
    "Encoding decisions 5/10",
    "Encoding decisions 10/10",
    "Encoding run audits 8/8",
    "Encoding UI probes 10/10",
    "Encoding boards page line 40",
    "Encoding performance aggregates 4/4",
    "Encoding dictionary 40/108",
    "Encoding dictionary 80/108",
    "Finalizing copy text",
}, "\n")
assert(yieldTrace == yieldTraceAgain and exportText == exportTextAgain
    and yieldTrace == expectedYieldTrace
    and exportText:find("version=test.13.1|build=source|boards=10|audits=8|probes=10|errors=1",1,true)
    and exportText:find("END|boards=10|audits=8|probes=10|errors=1",1,true),
    "export bytes, yield order, or coroutine-local state changed\nEXPECTED YIELDS:\n"
        .. expectedYieldTrace .. "\nACTUAL YIELDS:\n" .. yieldTrace)
print("exact export bytes/yield order and isolated concurrent cursors -- OK")

local jobA, jobB = owner.NewAIExportCoroutine(), owner.NewAIExportCoroutine()
local yieldsA, yieldsB, resultA, resultB = {}, {}, nil, nil
while coroutine.status(jobA) ~= "dead" or coroutine.status(jobB) ~= "dead" do
    for index, job in ipairs({jobA,jobB}) do
        if coroutine.status(job) ~= "dead" then
            local ok, value = coroutine.resume(job)
            assert(ok, "interleaved export failed")
            if coroutine.status(job) == "dead" then
                if index == 1 then resultA=value else resultB=value end
            elseif index == 1 then yieldsA[#yieldsA+1]=value else yieldsB[#yieldsB+1]=value end
        end
    end
end
assert(table.concat(yieldsA,"\n") == table.concat(yieldsB,"\n")
    and resultA == resultB and resultA == exportText,
    "concurrent exports shared dictionary or cursor state")

pageProvider = function(key)
    if key == "dps" then error("provider failed") end
    return owner.GetPageText(key)
end
local _, hostileExport = Drain(owner.NewAIExportCoroutine())
assert(hostileExport:find("provider failed",1,true),
    "page-provider failure escaped the bounded export fallback")
pageProvider = function(key) return owner.GetPageText(key) end

local settingsIdentity, futureIdentity = database.settings, database.future
assert(owner.Clear("perf") and perfClears == 1 and errorClears == 0
    and durableClears == 0 and syncClears == 0 and dpsClears == 0,
    "Perf clear escaped its selective owner")
assert(owner.Clear("errors") and errorClears == 1 and perfClears == 1
    and durableClears == 0 and syncClears == 0 and dpsClears == 0,
    "Errors clear escaped its selective owner")
assert(owner.Clear("peer") and peerClears == 1 and durableClears == 0
    and syncClears == 0 and dpsClears == 0,
    "Peer Test clear escaped its session-only owner")
assert(owner.Clear("state") and durableClears == 1 and syncClears == 1
    and dpsClears == 1 and errorClears == 2 and resetAuditCalls == 1
    and database.lastSaveStatus == nil and database.auditRunCounter == 0
    and database.settings == settingsIdentity and database.future == futureIdentity,
    "full clear changed routing, unknown fields, or retained user data")

-- A future durable history owns the all-history clear boundary. Refusal must
-- happen before database lookup/reset or any other diagnostic owner changes.
local refusal = {reason="keep-refusal",nested={token="refusal"}}
local saveStatus = {reason="keep-status",nested={token="status"}}
database.lastSaveRefusal = refusal
database.lastSaveStatus = saveStatus
database.auditRunCounter = 73
local countersBeforeRefusal = {
    durable=durableClears,errors=errorClears,perf=perfClears,
    sync=syncClears,dps=dpsClears,peer=peerClears,
    audit=resetAuditCalls,database=ensureDatabaseCalls,
}
local durableRefusals = 0
local successfulDurableClear = Nexus.DiagnosticLogs.ClearAll
Nexus.DiagnosticLogs.ClearAll = function()
    durableRefusals=durableRefusals+1
    return false,"future diagnostic history storage schema is read-only"
end
local refused = owner.Clear("state")
Nexus.DiagnosticLogs.ClearAll = successfulDurableClear
assert(refused == false and durableRefusals == 1
    and durableClears == countersBeforeRefusal.durable
    and errorClears == countersBeforeRefusal.errors
    and perfClears == countersBeforeRefusal.perf
    and syncClears == countersBeforeRefusal.sync
    and dpsClears == countersBeforeRefusal.dps
    and peerClears == countersBeforeRefusal.peer
    and resetAuditCalls == countersBeforeRefusal.audit
    and ensureDatabaseCalls == countersBeforeRefusal.database
    and database.lastSaveRefusal == refusal
    and database.lastSaveStatus == saveStatus
    and database.auditRunCounter == 73
    and refusal.nested.token == "refusal"
    and saveStatus.nested.token == "status"
    and database.settings == settingsIdentity and database.future == futureIdentity,
    "durable ClearAll refusal partially reset another diagnostic owner")
print("export isolation, provider fallback, and exact clear routing -- OK")
