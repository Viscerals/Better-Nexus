-- Peer Test diagnostics stay opt-in, bounded, sanitized, session-only, and
-- read only while explaining one selected build from narrow cached readers.
local now = 100
function GetTime() return now end
function UnitClass() return "Mage", "MAGE" end
function UnitName() return "Hero" end
function GetNormalizedRealmName() return "Ebonhold" end

local providerCalls = {work=0,stats=0,build=0,dps=0,lookup=0,virtual=0,
    leaderboard=0,rejections=0,outbound=0,explain=0}
local revisionCallbacks, revisionAdvances = {}, 0
local builds = {
    selected={id="selected",class="MAGE",title="Arcane",description="steady",
        author="Hero",ownerKey="hero@ebonhold",fingerprint="1x1",
        fingerprintHash="abc"},
    wrong={id="wrong",class="WARRIOR",title="Wrong",fingerprint="2x1"},
    unknown={id="unknown",class="UNKNOWN",title="Unknown",fingerprint="3x1"},
    remote={id="remote",class="MAGE",title="Remote",author="Peer",
        ownerKey="peer@ebonhold",fingerprint="4x1"},
    search={id="search",class="MAGE",title="Other",description="none",
        author="Peer",fingerprint="5x1"},
}
local qualification = {
    selected={dummy=100,lk=90},wrong={dummy=1,lk=1},unknown={dummy=1,lk=1},
    remote={dummy=1,lk=1},search={dummy=1,lk=1},
}
local authoritativeSelected = "included on current page"

NexusDB = {buildFilters={scope="all",search=""},sentinel=true}
Nexus = {
    VERSION="1.20-test",
    RuntimeBuildLabel=function() return "source" end,
    Sync={
        WorkState=function() providerCalls.work=providerCalls.work+1
            return {outbound=3,buildInflight=1,dpsInflight=0} end,
        Stats=function() providerCalls.stats=providerCalls.stats+1
            return {sent=11,received=12,dpsRequestsReceived=2,
                dpsRelayOffered=1,dpsDirectAccepted=3,dpsRelayAccepted=1,
                dpsDirectRejected=2,dpsRelayRejected=4,
                requestId="400-1234",useful=true,requestNew=1,
                requestUpdated=2,requestShares=3,requestDuplicates=4,
                requestRejected=5,requestBaseline=6,requestUnrelated=7,
                terminalReason="peer_state_unconfirmed",queueOutcome="sent",
                requestLastReason="schema"} end,
        ChannelName=function() return "wrbuildssync" end,
        ChannelIndex=function() return 2 end,
        IsConnected=function() return true end,
        IsReceiving=function() return true end,
        ReceiveTimeLeft=function() return 4.5 end,
    },
    BuildHashCache={Stats=function() providerCalls.build=providerCalls.build+1
        return {initialized=true,buildRows=5,tombstoneRows=1,buckets=8,
            dirtyBuckets=1,digest="a,b,c,d,e,f,10,11"} end},
    DpsCapture={
        HashCacheStats=function() providerCalls.dps=providerCalls.dps+1
            return {initialized=true,rows=10,storedRows=12,
                durationIneligibleRows=1,scoreIneligibleRows=1,
                schemaIneligibleRows=0,buckets=8,
                dirtyBuckets=0,digest="1,2,3,4,5,6,7,8"} end,
        RejectionStats=function()
            providerCalls.rejections=providerCalls.rejections+1
            return {duration=1,owner_sender=2,relay_authorization=3,
                schema=4,stale_record=5,duplicate_not_better=6,
                invalid_category=7,integrity=8,outside_request=9}
        end,
        OutboundStats=function()
            providerCalls.outbound=providerCalls.outbound+1
            return {considered=12,eligible=10,offered_direct=2,
                offered_relay=1,peer_current=1,outside_bucket=1,
                duration=1,score=1,owner_sender=2,relay_authorization=3,
                schema=4,stale_record=5,duplicate_not_better=6,
                invalid_category=7,integrity=8,outside_request=9,other=0,
                queue_deferred=2,wire_deferred=3}
        end,
        ProtocolVersion=function() return 7 end,
        GetCachedCommunityQualification=function(id)
            providerCalls.lookup=providerCalls.lookup+1
            local row = qualification[id]
            return row and {dummy=row.dummy or 0,lk=row.lk or 0} or nil
        end,
        GetRecordForIdentity=function()
            error("Peer Test must not warm the DPS identity index")
        end,
    },
    BuildCatalog={
        GetSummary=function(id) providerCalls.lookup=providerCalls.lookup+1
            return builds[id] end,
        All=function() error("Peer Test must not walk BuildCatalog.All") end,
        Summaries=function() error("Peer Test must not walk BuildCatalog.Summaries") end,
    },
    ViewProjections={ExplainBuild=function(id, filters)
        providerCalls.explain=providerCalls.explain+1
        filters=type(filters)=="table" and filters or {}
        local build=builds[id]
        if not build then return "not stored" end
        if filters.currentClassOnly~=false then
            if build.class=="UNKNOWN" then return "unknown class" end
            if build.class~="MAGE" then return "current class filter" end
        end
        if filters.scope=="mine" and build.ownerKey~="hero@ebonhold" then
            return "scope filter: not mine"
        end
        local search=tostring(filters.search or ""):lower()
        if search~="" and not tostring(build.title or ""):lower():find(search,1,true)
            and not tostring(build.author or ""):lower():find(search,1,true)
            and not tostring(build.description or ""):lower():find(search,1,true) then
            return "search filter"
        end
        local row=qualification[id]
        if not row or not row.dummy then return "qualification missing: Dummy" end
        if not row.lk then return "qualification missing: LK" end
        return authoritativeSelected
    end},
    CommunityBuilds={VirtualStats=function()
        providerCalls.virtual=providerCalls.virtual+1
        return {refreshDirty=false,results=20}
    end},
    Leaderboard={VirtualStats=function()
        providerCalls.leaderboard=providerCalls.leaderboard+1
        return {publishedRows=10,displayedRows=5}
    end},
    Revisions={
        BUILD_LIBRARY_CHANGED="build",DPS_CHANGED="dps",
        Get=function(kind) return kind=="build" and 4 or 6 end,
        Subscribe=function(kind, callback) revisionCallbacks[kind]=callback end,
        Advance=function() revisionAdvances=revisionAdvances+1 end,
    },
}

dofile("core/Identity.lua")
dofile("core/PeerDebug.lua")
local Peer = assert(Nexus.PeerDebug)
local disabled = Peer.Report()
assert(disabled:find("status=disabled",1,true)
    and providerCalls.work==0 and providerCalls.stats==0
    and providerCalls.build==0 and providerCalls.dps==0
    and providerCalls.lookup==0 and providerCalls.virtual==0
    and providerCalls.leaderboard==0 and providerCalls.rejections==0
    and providerCalls.outbound==0
    and providerCalls.explain==0,
    "disabled Peer Test performed provider or represented-data work")
assert(NexusDB.sentinel and NexusDB.peerDebug==nil,
    "disabled Peer Test wrote SavedVariables")

assert(Peer.Init() and Peer.Init()
    and type(revisionCallbacks.build)=="function"
    and type(revisionCallbacks.dps)=="function",
    "Peer Test revision observation was not idempotent")
assert(Peer.Start("Peer-Realm") and Peer.IsEnabled()
    and Peer.Stats().peer=="Peer",
    "Peer Test start or optional-peer normalization failed")
assert(not Peer.Record("receiver_commit", {peer="Other-Realm",id="ignored"})
    and Peer.Record("receiver_commit", {peer="Peer-Other",id="selected",
        outcome="stored"}),
    "optional peer filter did not fail closed")

local secret = "TOP-SECRET-PAYLOAD"
assert(Peer.Record("share_created", {id="selected",class="MAGE",echoes=79,
    outcome="created",raw=secret,payload=secret,packet=secret,title=secret,
    author=secret,account=secret,echoList={{spellId=1}}}))
revisionCallbacks.build("build",5,{scope="record",id="selected"})
revisionCallbacks.dps("dps",7,{scope="record",category="dummy"})
assert(revisionAdvances==0, "Peer Test revision subscribers advanced data")
assert(Peer.Record("community_result", {id="selected",outcome="included",
    rows=20,page=1}))

local report = Peer.Report()
assert(report:find("queue=3",1,true)
    and report:find("event_scope=observation peer_filter=Peer peer_events=filtered global_events=included routing=unchanged",1,true)
    and report:find("counter_scope=addon_session event_history=peer_test_session",1,true)
    and report:find("build_rows_cached=5",1,true)
    and report:find("dps_rows_hash_eligible=10",1,true)
    and report:find("sync_request id=400-1234 useful=true new=1 updated=2 share=3 duplicate=4 rejected=5 baseline=6 unrelated=7",1,true)
    and report:find("sync_terminal reason=peer_state_unconfirmed queue=sent last_reason=schema",1,true)
    and report:find("dps_counts stored=12 hash_eligible=10 published_board=10 displayed_rows=5",1,true)
    and report:find("dps_local_ineligible duration=1 score=1 schema=0",1,true)
    and report:find("dps_sync requested=2 offered=1 direct_ok=3 relay_ok=1 rejected=6",1,true)
    and report:find("dps_reject duration=1 owner_sender=2 relay_auth=3 schema=4 stale=5 duplicate=6 category=7 integrity=8 outside_request=9",1,true)
    and report:find("dps_outbound considered=12 eligible=10 direct=2 relay=1 peer_current=1 outside_bucket=1",1,true)
    and report:find("dps_outbound_skip duration=1 score=1 owner_sender=2 relay_auth=3 schema=4 stale=5 duplicate=6 category=7 integrity=8 outside_request=9 other=0",1,true)
    and report:find("dps_outbound_deferred queue=2 wire=3",1,true)
    and report:find("version=1.20-test build=source protocol=7",1,true)
    and report:find("protocol=7",1,true)
    and report:find("build_digest=a,b,c,d,e,f,10,11",1,true)
    and report:find("buckets=8 state=dirty:1",1,true)
    and report:find("dps_digest=1,2,3,4,5,6,7,8 buckets=8 state=current",1,true)
    and report:find("selected_build=selected community=included on current page",1,true)
    and not report:find(secret,1,true),
    "active report lost cached state, selected outcome, or privacy bounds")
assert(providerCalls.work==1 and providerCalls.stats==1
    and providerCalls.build==1 and providerCalls.dps==1
    and providerCalls.leaderboard==1 and providerCalls.rejections==1
    and providerCalls.outbound==1
    and providerCalls.explain==1,
    "one report did not perform exactly one bounded aggregate snapshot")

assert(Peer.ExplainBuild("missing")=="not stored")
assert(Peer.ExplainBuild("wrong")=="current class filter")
assert(Peer.ExplainBuild("unknown")=="unknown class")
assert(Peer.ExplainBuild("remote",{scope="mine"})=="scope filter: not mine")
assert(Peer.ExplainBuild("search",{scope="all",search="arcane"})=="search filter")
qualification.selected.lk=nil
assert(Peer.ExplainBuild("selected")=="qualification missing: LK")
qualification.selected.lk=90
authoritativeSelected="projection result not yet published"
assert(Peer.SelectBuild("selected") == "selected"
    and Peer.ExplainBuild("selected")=="projection result not yet published")
authoritativeSelected="projection pending"
Nexus.CommunityBuilds.VirtualStats=function() return {refreshDirty=true} end
assert(Peer.ExplainBuild("selected")=="projection pending")
Nexus.CommunityBuilds.VirtualStats=function() return {refreshDirty=false} end
authoritativeSelected="outside current page"
Peer.Record("community_result", {id="selected",outcome="outside_page",rows=20,page=1})
assert(Peer.ExplainBuild("selected")=="outside current page",
    "stored-build exclusion reasons were not deterministic")

Peer.Clear()
Peer.Start("")
local wide = {
    id=string.rep("i",56),class=string.rep("c",96),outcome=string.rep("o",96),
    reason=string.rep("r",96),scope=string.rep("s",96),peer=string.rep("p",40),
    category=string.rep("g",96),chunks=999,bytes=99999,queue=999,
    revision=999,page=999,rows=999,builds=999,dps=999,quiet=999,
    sent=999,received=999,duplicate=true,tombstone=true,
}
for index=1,160 do assert(Peer.Record("wide",wide)) end
local wideReport = Peer.Report()
assert(#wideReport < 60000 and Peer.Limits().eventReport==220,
    "worst-case bounded events exceeded the copy-safe report limit")

Peer.Clear()
Peer.Start("")
for index=1,190 do
    assert(Peer.Record("bounded", {id="id-"..index,outcome="kept"}))
end
local bounded = Peer.Stats()
assert(bounded.retained==160 and bounded.dropped==31 and bounded.cap==160
    and bounded.maxAge==900,
    "Peer Test ring or age contract changed")
now = 1001
assert(not Peer.IsEnabled() and Peer.Stats().expired==1
    and Peer.Stats().retained==0 and Peer.Stats().dropped==0,
    "Peer Test session did not expire at its absolute age bound")
assert(Peer.Clear() and Peer.Stats().retained==0 and Peer.Stats().dropped==0
    and Peer.Stats().expired==0 and not Peer.IsEnabled(),
    "Peer Test clear did not reset all session state")
now = 1010
assert(Peer.Start("") and Peer.Stop())
now = 1911
assert(Peer.Stats().expired==1 and Peer.Stats().retained==0,
    "stopped Peer Test data outlived the absolute session bound")
Peer.Clear()

Nexus.BuildHashCache.Stats=function() error("cache read failure") end
Nexus.DpsCapture.HashCacheStats=function() error("cache read failure") end
Nexus.Sync.WorkState=function() error("work read failure") end
Nexus.BuildCatalog.GetSummary=function() error("lookup failure") end
Nexus.ViewProjections.ExplainBuild=function() error("projection failure") end
now = 1100
Peer.Start("")
Peer.SelectBuild("selected")
local okFailure, failureReport = pcall(Peer.Report)
assert(okFailure and failureReport:find("build_cache=cold",1,true)
    and failureReport:find("community=projection explanation failed",1,true)
    and revisionAdvances==0 and NexusDB.sentinel and NexusDB.peerDebug==nil,
    "diagnostic dependency failure escaped or authorized state changes")

local function Read(path)
    local file = assert(io.open(path, "r"))
    local value = file:read("*a")
    file:close()
    return value
end
local viewer, diagnostics, toc = Read("ui/LogViewer.lua"),
    Read("core/MainDiagnostics.lua"), Read("Nexus.toc")
assert(viewer:find('{ key = "peer",     label = "Peer Test" }',1,true)
    and viewer:find('"NexusPeerTestTarget"',1,true)
    and viewer:find('peerLabel:SetText("Peer event filter (optional)")',1,true)
    and viewer:find('pcall(debugOwner.Start, peerEdit:GetText())',1,true)
    and viewer:find('pcall(debugOwner.Stop)',1,true)
    and diagnostics:find('if tabKey == "peer" then',1,true),
    "Peer Test tab or deterministic session controls are not wired")
local diagnosticAt = assert(toc:find("core\\DiagnosticLogs.lua",1,true))
local peerAt = assert(toc:find("core\\PeerDebug.lua",1,true))
local lifecycleAt = assert(toc:find("core\\MainLifecycle.lua",1,true))
assert(diagnosticAt < peerAt and peerAt < lifecycleAt,
    "Peer Test TOC ownership order is unsafe")

print("Peer Test opt-in bounds, privacy, cached state, exclusion reasons, and failure isolation -- OK")
