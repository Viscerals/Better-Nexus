-- Full TOC/lifecycle regression for per-frame accounting cost. Synthetic data.
local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(40,60); T.Load()
if Nexus.BuildCatalog.PreparationPumpCount then
    assert(Nexus.BuildCatalog.PreparationPumpCount()==Nexus.BuildCatalog.DebugStats().rootPumps,
        'counter is available before authority admission')
end
H.Fire('ADDON_LOADED','Nexus'); H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function() return Nexus.StartupStatus().state=='ready' end,200000)
for _=1,120 do H.Advance(.05) end
local checks=0
local function check(v,m) assert(v,m); checks=checks+1 end
local C=Nexus.BuildCatalog
local real=C.ManualPreparationStatus
local reads=0
C.ManualPreparationStatus=function(...)
    local caller=debug.getinfo(2,'S')
    if caller and caller.source:match('core/MainLifecycle%.lua$') then reads=reads+1 end
    return real(...)
end
local before=C.DebugStats()
for _=1,80 do H.Advance(.0025) end
local after=C.DebugStats()
C.ManualPreparationStatus=real
check(reads==80,'one fresh lifecycle status check per settled frame, not a second accounting query: '..reads..'/80')
for _,key in ipairs({'rootAdmissions','rootPumps','rowWalks','commits','driftInvalidations'}) do
    check(after[key]==before[key],'settled cost fixture changes no catalog work: '..key)
end
check(NexusDB.settings.autoPick==false,'Automation stays OFF')
check(type(C.PreparationPumpCount)=='function','scalar counter capability exists')

-- The scalar is passive and fresh. It must not ask for authority/readiness,
-- pump work, read player identity, create a candidate or change public state.
local originalCount=C.PreparationPumpCount()
local originalStats, originalStatus=C.DebugStats(),real()
local saved={}
for _,name in ipairs({'ManualPreparationStatus','Status','RootState','PumpRootAdmission','BoundDatabase'}) do
    saved[name]=C[name]; C[name]=function() error('counter queried '..name) end
end
local unitName,realm=UnitName,GetRealmName
UnitName=function() error('counter queried player identity') end
GetRealmName=function() error('counter queried realm identity') end
for _=1,1000 do check(C.PreparationPumpCount()==originalCount,'read-only scalar counter') end
UnitName,GetRealmName=unitName,realm
for name,fn in pairs(saved) do C[name]=fn end
check(T.Equal(C.DebugStats(),originalStats),'counter reads change no debug state')
check(T.Equal(real(),originalStatus),'counter reads change no readiness or candidate state')

local stored=C.Get('synthetic-startup-7')
check(type(stored)=='table','stored donor exists')
local donor=H.Clone(stored)
donor.id='counter-accounting-received';donor.author='Remote-Realm'
local ok,why,ticket=C.Put(donor)
check(ok==nil and why=='ROOT_MUTATION_PENDING' and type(ticket)=='table','real pending mutation')
local count=C.PreparationPumpCount()
check(count==C.DebugStats().rootPumps,'counter includes the latest direct mutation slice')
C.PumpRootAdmission()
check(C.PreparationPumpCount()==count+1,'counter observes the next real root pump immediately')
T.Until(H,function() return ticket.state=='committed' end,4000)
check(C.Get(donor.id)~=nil,'pending mutation still publishes')

-- Mixed/older optional catalog modules retain the original accounting path.
-- Zero would subtract the session-total root pumps and exhaust every batch.
local counter=C.PreparationPumpCount; C.PreparationPumpCount=nil
reads=0; C.ManualPreparationStatus=function(...)
    local caller=debug.getinfo(2,'S')
    if caller and caller.source:match('core/MainLifecycle%.lua$') then reads=reads+1 end
    return real(...)
end
H.Advance(.0025)
C.PreparationPumpCount=counter; C.ManualPreparationStatus=real
check(reads==2,'missing getter preserves both legacy lifecycle queries: '..reads)
check(Nexus.StartupStatus().syncGateCatalogReady==true,'legacy getter fallback retains readiness')

-- Optional module and timing absence retain the lifecycle's supported paths.
local performance=Nexus.Performance
Nexus.Performance=nil
H.Advance(.0025)
Nexus.Performance=performance
check(Nexus.StartupStatus().syncGateCatalogReady==true,'counter works without timing instrumentation')
Nexus.BuildCatalog=nil
local noCatalogOk,noCatalogError=pcall(H.Advance,.0025)
Nexus.BuildCatalog=C
check(noCatalogOk,'missing optional catalog keeps existing lifecycle behavior: '..tostring(noCatalogError))
H.Advance(.0025)

-- An owner change inside preparation must be seen by the later full query.
-- Direct upvalues are checked before descending, so the holder is the nearest
-- closure that names the seam.
local function find(fn,name,seen)
    if type(fn)~='function' or seen[fn] then return end;seen[fn]=true
    for i=1,255 do
        local n,v=debug.getupvalue(fn,i);if not n then break end
        if n==name then return v,fn,i end
    end
    for i=1,255 do
        local n,v=debug.getupvalue(fn,i);if not n then break end
        if type(v)=='function' then local a,b,c=find(v,name,seen);if a then return a,b,c end end
    end
end
local store,holder,index
for _,frame in ipairs(H.frames) do
    local fn=frame.scripts.OnUpdate
    local getLifecycle=fn and find(fn,'Lifecycle',{})
    local lifecycle=getLifecycle and getLifecycle()
    if lifecycle then
        store,holder,index=find(lifecycle.OnUpdate,'PumpStoreMutationSlice',{})
        if store then break end
    end
end
check(type(store)=='function','real lifecycle preparation seam exists')
-- LuaJIT may compile an assigned-once local function into a trace as a
-- constant, so a compiled caller keeps calling it after debug.setupvalue.
-- Discard compiled traces after each rewrite; plain Lua has no jit table.
local function setSeam(fn)
    debug.setupvalue(holder,index,fn)
    if type(jit)=='table' and type(jit.flush)=='function' then jit.flush() end
    local _,live=debug.getupvalue(holder,index)
    return live==fn
end
local boundRoot,replacement=NexusDB,nil
local entries,gateRefused=0,false
C.ManualPreparationStatus=function(...)
    local status,identity=real(...)
    local caller=debug.getinfo(2,'S')
    if caller and caller.source:match('core/MainLifecycle%.lua$') and not status.ownerAgrees
        and replacement~=nil and NexusDB==replacement then
        gateRefused=true
    end
    return status,identity
end
local injected=setSeam(function(...)
    entries=entries+1
    local result=store(...)
    replacement=T.Profile(0,0); NexusDB=replacement
    return result
end)
H.Advance(.0025)
local restored=setSeam(store)
C.ManualPreparationStatus=real
check(injected and restored,'preparation seam rewrite is installed and restored')
check(entries==1,'the lifecycle update ran the injected preparation slice once: '..entries)
check(replacement~=nil and replacement~=boundRoot and NexusDB==replacement,'the bound root was replaced inside preparation')
check(gateRefused,'later full lifecycle query observes a root replaced after counter read')
check(Nexus.StartupStatus().syncGateHashesReady==false,'fresh hash gate prevents Sync from consuming the replaced source')
check(Nexus.BuildHashCache.Legacy()==nil,'no old digest served after replaced root')
NexusDB=boundRoot
print('PASS lifecycle scalar counter cost, purity, pending work, legacy fallback and fresh refusal; '..checks..' checks')
