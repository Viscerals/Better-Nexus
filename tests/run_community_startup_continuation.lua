-- Actual Community initialization, populated reference independent of release seed.
local H = dofile("tests/harness.lua")
local S = dofile("tests/catalog_authority_support.lua")
dofile("data/DefaultProfile.lua")
dofile("tests/fixtures/BundledBuilds-1.19.4-reference.lua")
dofile("core/Store.lua")
dofile("ui/CommunityBuilds.lua")
NexusDB = {settings={},chars={},communityBuilds={},syncTombstones={},dpsCapture={}}
H.BootstrapStore()
local C, CB = Nexus.BuildCatalog, Nexus.CommunityBuilds
S.PumpCatalogToIdle("bootstrap maintenance")
local admittedBefore=C.Count()
local calls, total, original = 0, 0, C.RecordCursorNext
C.RecordCursorNext = function(...)
    calls, total = calls + 1, total + 1
    return original(...)
end
local result = CB.Init({}, {})
assert(calls <= 32, "Community.Init drains the populated cursor in one callback: "..calls)
assert(type(result)=="table" and result.state=="pending",
    "populated Community startup must explicitly retain pending work")
local turns = 0
while result.state == "pending" and turns < 30000 do
    C.PumpRootAdmission()
    calls=0
    result=CB.Init({}, {})
    assert(calls<=32,"continuation drained the cursor in one callback")
    turns=turns+1
end
assert(result.state=="ready", "startup did not complete: "..tostring(result.reason))
assert(total>500 and turns>1, "populated workload disappeared")
local before=total
assert(CB.Init({},{}).state=="ready" and total==before,"completed initialization repeated")
assert(admittedBefore>0 and C.Count()==admittedBefore,
    "startup discarded admitted historical test rows")
print("Community populated startup continuation: turns="..turns.." cursorCalls="..total.." PASS")

local function Fresh(rows,compacted)
    Nexus.BundledBuilds=S.Bundle({})
    NexusDB=S.Database(rows,nil,{settings={},chars={},futureRoot={keep=true}})
    if compacted then
        NexusDB.dataCompaction={schemaVersion=1,version=1,last={migrationVersion=1}}
    end
    H.BootstrapStoreReady()
    S.PumpCatalogToIdle("fixture bootstrap")
end
local function Finish()
    local r
    for i=1,30000 do
        C.PumpRootAdmission()
        r=CB.Init({}, {})
        if r.state~="pending" then return r end
    end
    error("Community continuation did not terminate")
end
Fresh({})
assert(Finish().state=="ready" and C.Count()==0,"fresh empty seed failed")
local row=S.LocalBuild("personal",79,{futureField={keep="yes"}})
local legacy=S.Build("retired",79,0,{author="WR Team",ownerKey="wr team@ebonhold"})
Fresh({personal=row,retired=legacy})
assert(C.Get("personal") and C.Get("retired"),"required repair fixtures not admitted")
local completions=0
local bind=C.BindMutationCompletion
C.BindMutationCompletion=function(ticket, callback)
    return bind(ticket,function(outcome) completions=completions+1;callback(outcome) end)
end
assert(Finish().state=="ready","existing-profile repair failed")
local repaired=C.Get("personal")
assert(not C.Get("retired") and repaired and repaired.echoCount==79
    and repaired.loadoutAvailable==true and repaired.needsFullBuild==false,
    "cleanup or identity repair outcome lost")
assert(S.Durable().personal.futureField.keep=="yes" and row.futureField.keep=="yes"
    and NexusDB.futureRoot.keep,"unknown source fields changed")
assert(completions>=1,"fixture never exercised a pending mutation")
local once=completions
for i=1,8 do assert(CB.Init({},{}).state=="ready") end
assert(completions==once,"completion callback repeated")
assert(S.CatalogMutation(function() return C.Put(S.LocalBuild("later",79)) end))
assert(C.Get("later") and C.Get("personal"),"normal later growth lost data")

Fresh({retired=legacy})
local pending
for i=1,10000 do
    pending=CB.Init({}, {})
    if C.RootState().candidate then break end
end
assert(C.RootState().candidate,"cancellation fixture did not retain mutation")
C.CancelRootAdmission()
assert(CB.Init({},{}).state=="failed","cancelled mutation reported ready")
Fresh({})
assert(Finish().state=="ready","replacement database did not abandon cancelled job")

Fresh({personal=row})
assert(CB.Init({},{}).state=="pending")
assert(S.CatalogMutation(function() return C.Put(S.LocalBuild("concurrent",79)) end))
local refused=CB.Init({}, {})
assert(refused.state=="failed" and refused.reason=="COMMUNITY_SOURCE_CHANGED",
    "stale startup candidate survived source generation change")
assert(C.Get("concurrent"),"generation refusal lost external write")
print("Community fresh/existing, growth, unknown fields, pending, cancellation and rebind PASS")

-- The real startup consumer must not reconstruct the complete catalog for
-- each eligible identity-only row. This is a transaction-count oracle, not
-- an invented native timing threshold.
do
    local rows={}
    for i=1,20 do rows["repair-"..i]=S.LocalBuild("repair-"..i,79,{futureBuild={keep=i}}) end
    Fresh(rows,true)
    local stats,root=C.DebugStats(),C.RootState()
    local result=Finish()
    assert(result.state=="ready","identity batch did not finish: "..tostring(result.reason))
    local after,current=C.DebugStats(),C.RootState()
    assert(after.maintenanceCommits==stats.maintenanceCommits+1
        and after.putChanges==stats.putChanges
        and current.servingGeneration==root.servingGeneration+1,
        "identity startup reconstructs the entire root separately for each repaired row")
    for id,input in pairs(rows) do
        local durable,public=S.Durable()[id],C.Get(id)
        assert(durable.futureBuild.keep==input.futureBuild.keep
            and public.echoCount==79 and public.needsFullBuild==false,
            "identity batch lost unknown data or required repair")
        for i,echo in ipairs(input.echoes) do
            assert(public.echoes[i].spellId==echo.spellId
                and public.echoes[i].stacks==echo.stacks
                and public.echoes[i].quality==echo.quality,"identity batch changed Echoes")
        end
    end
    local freshController=Nexus.CommunityInternals.Controller.New()
    local bundle=Nexus.BundledBuilds
    local repeated
    for i=1,1000 do
        repeated=freshController.Initialize({},bundle)
        assert(not C.RootState().candidate,"repeat initialization opened a root replacement")
        if repeated.state~="pending" then break end
    end
    local repeatedStats,repeatedRoot=C.DebugStats(),C.RootState()
    assert(repeated.state=="ready"
        and repeatedStats.maintenanceCommits==after.maintenanceCommits
        and repeatedStats.putChanges==after.putChanges
        and repeatedRoot.generation==current.generation
        and repeatedRoot.servingGeneration==current.servingGeneration,
        "fresh controller repeated completed identity writes")
    print("Community identity repair uses one atomic root replacement for 20 rows PASS")

    Fresh(rows,true)
    local replace,cancel=C.MaintenanceReplaceRow,C.CancelMaintenance
    local staged,cancelled=0,0
    local beforeFailure=C.RootState()
    C.MaintenanceReplaceRow=function(...)
        staged=staged+1
        if staged==2 then return false,"TEST_STAGING_REFUSAL" end
        return replace(...)
    end
    C.CancelMaintenance=function(...)
        local ok=cancel(...)
        if ok then cancelled=cancelled+1 end
        return ok
    end
    local failed=Finish()
    C.MaintenanceReplaceRow,C.CancelMaintenance=replace,cancel
    assert(failed.state=="failed" and failed.reason=="TEST_STAGING_REFUSAL"
        and staged==2 and cancelled==1,"failed staging did not cancel its exact handle")
    assert(C.RootState().generation==beforeFailure.generation
        and C.RootState().servingGeneration==beforeFailure.servingGeneration,
        "failed batch published partial changes")
    local available,why=C.BeginCatalogMaintenance({database=NexusDB,operation="test-after-cancel"})
    assert(available,"failed startup leaked an open handle: "..tostring(why))
    assert(C.CancelMaintenance(available))
    for id,input in pairs(rows) do
        assert(S.Durable()[id].futureBuild.keep==input.futureBuild.keep,
            "failed batch lost existing data")
    end
    print("Community staged batch refusal preserves root and releases its handle PASS")
end

-- Real lifecycle + real Store/catalog/Community. Readiness must include the
-- retained work, its writes, and final dependent initialization exactly once.
Fresh({personal=row})
dofile("core/MainLifecycle.lua")
local clock,adapterInits,panelInits,entries=0,0,0,0
debugprofilestop=function() return clock end
local nextPage=C.RecordCursorNext
C.RecordCursorNext=function(...) clock=clock+0.2;return nextPage(...) end
local lastCommunity
local init=CB.Init
CB.Init=function(...)
    lastCommunity=init(...)
    return lastCommunity
end
local errors={}
local N={VERSION="test",MainInternals=Nexus.MainInternals,Store=Nexus.Store,
    CommunityBuilds=CB,BuildCatalog=C,LoadoutEvidence=Nexus.LoadoutEvidence,
    DiagnosticLogs={Init=function() return true end}}
local A={Init=function() adapterInits=adapterInits+1 end,
    RivalDetected=function() return false end,Ready=function() return false end,
    OnEvent=function() entries=entries+1;clock=clock+40 end,
    RequestSlots=function() end,SetSoloPicker=function() end}
local L=Nexus.MainInternals.Lifecycle.New({nexus=N,
    bindDependencies=function() return {Store=Nexus.Store,Adapter=A,Model={},
        Panel={Init=function() panelInits=panelInits+1 end}} end,
    ensureAutomation=function() return {Initialize=function() end} end,
    print=function() end,recordError=function(_,e) errors[#errors+1]=e end,
    recordStoreError=function(e) errors[#errors+1]=e end,errorText=tostring,
    requestRecompute=function() end,refreshHud=function() return true end,
    database=function() return NexusDB end,now=GetTime})
L.OnEvent("ADDON_LOADED","Nexus")
L.OnEvent("PLAYER_ENTERING_WORLD")
local pendingTurns=0
for i=1,100000 do
    L.OnUpdate(0.01)
    if lastCommunity and lastCommunity.state=="pending" then
        pendingTurns=pendingTurns+1
        assert(not L.IsInitialized() and panelInits==0 and entries==0,
            "lifecycle reported ready or released later dependents before Community completion")
    end
    if L.IsInitialized() or #errors>0 then break end
end
assert(#errors==0,"lifecycle failed: "..table.concat(errors,","))
assert(L.IsInitialized() and pendingTurns>0 and adapterInits==1
    and panelInits==1 and entries==1,"lifecycle continuation/release count wrong")
assert(N.startupTiming.maxUpdateMs>=40 and N.startupTiming.communityMaxMs>0
    and N.startupTiming.readySeconds~=nil,"timing excludes full completion update")
L.OnUpdate(0.01)
assert(adapterInits==1 and panelInits==1 and entries==1,"ready initialization repeated")
print("Real lifecycle Community readiness, exactly-once release and complete-update timing PASS")

-- No fixture predrain: exercise actual startup, ordinary registration, and
-- the real scheduler before automatic retention publishes its replacement.
do
    Nexus={VERSION="test"}
    local H=dofile("tests/harness.lua")
    local S=dofile("tests/catalog_authority_support.lua")
    dofile("data/DefaultProfile.lua")
    dofile("data/BundledBuilds.lua")
    dofile("core/Store.lua")
    dofile("core/DpsCapture.lua")
    dofile("ui/CommunityBuilds.lua")
    dofile("core/MainLifecycle.lua")
    local rows={}
    for i=1,100 do
        local row=S.LocalBuild("retained-"..i,79,{futureBuild={keep=i}})
        row.fingerprint=Nexus.DpsCapture.GetEchoKey(row.echoes)
        row.fingerprintHash=Nexus.DpsCapture.GetEchoHash(row.echoes)
        row.echoCount,row.loadoutAvailable,row.needsFullBuild=79,true,false
        rows[row.id]=row
    end
    NexusDB=S.Database(rows,nil,{settings={},chars={},futureRoot={keep=true},
        dataCompaction={schemaVersion=1,version=1,last={migrationVersion=1}}})
    debugprofilestop=function() return 0 end
    local coordinator,life,errors,ownerCalls=nil,nil,{},{}
    local factory=Nexus.MainInternals.AuthorityBootstrap.New
    Nexus.MainInternals.AuthorityBootstrap.New=function(...)
        coordinator=factory(...);return coordinator
    end
    for _,name in ipairs({"DataCompaction","DataRetention"}) do
        local original=Nexus[name].Init
        Nexus[name].Init=function(database)
            assert(life.IsInitialized() and Nexus.startupTiming.communityPhase=="complete",
                "automatic maintenance ran before required Community startup")
            assert(database==NexusDB and coordinator:IsReady()
                and coordinator:Result().result=="MUTATION_COMMITTED",
                "automatic maintenance overtook ordinary registration or rebound database")
            ownerCalls[name]=(ownerCalls[name] or 0)+1
            return original(database)
        end
    end
    local A={Init=function() end,Ready=function() return false end,
        RivalDetected=function() return false end,OnEvent=function() end,
        RequestSlots=function() end,SetSoloPicker=function() end}
    life=Nexus.MainInternals.Lifecycle.New({nexus=Nexus,
        bindDependencies=function() return {Store=Nexus.Store,Adapter=A,Model={},
            Panel={Init=function() end}} end,
        ensureAutomation=function() return {Initialize=function() end} end,
        print=function() end,errorText=tostring,requestRecompute=function() end,
        recordError=function(_,e) errors[#errors+1]=e end,
        recordStoreError=function(e) errors[#errors+1]=e end,
        refreshHud=function() return true end,database=function() return NexusDB end,now=GetTime})
    life.OnEvent("ADDON_LOADED","Nexus")
    life.OnEvent("PLAYER_ENTERING_WORLD")
    local readyTurn
    for turn=1,10000 do
        H.now=H.now+1/60
        life.OnUpdate(1/60)
        if Nexus.Scheduler.IsInitialized() then Nexus.Scheduler.Tick(H.now) end
        if life.IsInitialized() and not readyTurn then
            readyTurn=turn
            assert(not next(ownerCalls),"maintenance was not deferred")
        end
        if readyTurn and Nexus.BuildCatalog.DebugStats().maintenanceCommits==1
            and not Nexus.BuildCatalog.RootState().candidate then break end
    end
    assert(#errors==0,"real startup/maintenance errors: "..table.concat(errors,","))
    assert(readyTurn and readyTurn<1000,"startup serialized behind background maintenance")
    assert(ownerCalls.DataCompaction==1 and ownerCalls.DataRetention==1,
        "automatic owners did not initialize exactly once")
    assert(Nexus.BuildCatalog.DebugStats().maintenanceCommits==1,
        "deferred maintenance work disappeared")
    assert(NexusDB.futureRoot.keep and Nexus.BuildCatalog.Count()==100,
        "startup or maintenance lost retained data")
    for id,input in pairs(rows) do
        local row=S.Durable()[id]
        assert(row.futureBuild.keep==input.futureBuild.keep and row.fingerprint==input.fingerprint
            and #row.echoes==79,"build identity or unknown fields changed")
        for i,echo in ipairs(input.echoes) do
            assert(row.echoes[i].spellId==echo.spellId and row.echoes[i].quality==echo.quality
                and row.echoes[i].stacks==echo.stacks,"retained Echo data changed")
        end
    end
    print("Real no-predrain startup, registration, deferred one-shot maintenance and data parity PASS")
end

-- Scheduler ownership: batching must stop at this exact startup ticket even
-- when its completion subscriber starts another catalog candidate.
do
    local function Scenario(cost,settle,noClock)
        local clock,pumps=0,0
        local ticket={state="pending"}
        local db={}
        local store={Init=function() return {state="ready"} end,
            Settings=function() return {} end}
        local N={VERSION="test",Store=store,
            DiagnosticLogs={Init=function() return true end},
            CommunityBuilds={Init=function() return {state="pending",phase="identities",
                mutationTicket=ticket} end},
            BuildCatalog={PumpRootAdmission=function()
                pumps=pumps+1;clock=clock+cost
                if pumps==settle then ticket.state="committed" end
                return {state="pending"}
            end,RootState=function() return {state="ROOT_ADMITTED",candidate=true} end}}
        local A={Init=function() end,Ready=function() return false end,
            RivalDetected=function() return false end}
        debugprofilestop=function() return clock end
        if noClock then debugprofilestop=nil end
        local life=Nexus.MainInternals.Lifecycle.New({nexus=N,
            bindDependencies=function() return {Store=store,Adapter=A,Model={},Panel={}} end,
            ensureAutomation=function() return {Initialize=function() end} end,
            print=function() end,errorText=tostring,requestRecompute=function() end,
            recordError=function(_,e) error(e) end,recordStoreError=function(e) error(e) end,
            refreshHud=function() return true end,database=function() return db end,now=GetTime})
        life.OnEvent("PLAYER_ENTERING_WORLD")
        life.OnUpdate(0.01)
        return pumps
    end
    assert(Scenario(0,nil,false)==32,"Community startup exceeded or lost hard slice cap")
    assert(Scenario(0.75,nil,false)==3,"Community startup reset its soft deadline")
    assert(Scenario(0,nil,true)==1,"Community startup lost missing-clock fallback")
    assert(Scenario(0,3,false)==3,"Community startup batched a subscriber's foreign candidate")
    print("Community ticket-only cap, deadline, fallback and replacement-owner stop PASS")
end
