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

local function Fresh(rows)
    Nexus.BundledBuilds=S.Bundle({})
    NexusDB=S.Database(rows,nil,{settings={},chars={},futureRoot={keep=true}})
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
