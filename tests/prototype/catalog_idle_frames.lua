-- Idle catalog frames (HUD and lifecycle cost, 2026-10-01, test.9053). With
-- the catalog admitted and nothing pending, every lifecycle update still ran
-- one admission slice to learn that: four preparation-status tables, one pump
-- result and one root-state table per frame. Measured on the reporter's saved
-- data: about a fifth of the idle lifecycle time and 5.6 KB per frame.
--
-- Required: an idle update pumps nothing and reads no root state; Sync still
-- sees the catalog ready; the idle observation shown by /nexus peer debug is
-- the same; a received build is still admitted through the same slices and
-- committed, and the update after it is idle again.
local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
NexusDB=T.Profile(40,60);T.Load()
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready'end,200000)
for _=1,100 do H.Advance(.05) end
local C=Nexus.BuildCatalog
check(C.Count()==40,'fixture: the saved catalog is admitted: '..C.Count())
check(C.RootState().state=='ROOT_ADMITTED' and C.RootState().candidate==false,'fixture: the catalog is admitted and idle')

-- The lifecycle's admission batch, through the update's shared upvalues.
local function upvalue(fn,name)
 for i=1,255 do local n,v=debug.getupvalue(fn,i);if not n then break end;if n==name then return v end end
end
local frame
for _,f in ipairs(H.frames) do local s=f.scripts.OnUpdate;if s and upvalue(s,'Lifecycle') then frame=f end end
local lifecycle=frame and upvalue(frame.scripts.OnUpdate,'Lifecycle')()
local runUpdate=lifecycle and upvalue(upvalue(lifecycle.OnUpdate,'OnUpdate'),'RunUpdate')
local batch=runUpdate and upvalue(runUpdate,'PumpCatalogAdmissionBatch')
check(type(batch)=='function','the lifecycle admission batch is found')
local slice=upvalue(batch,'PumpCatalogRootAdmissionSlice')
check(type(slice)=='function','the lifecycle admission slice is found')

-- status and root count only the batch's own reads (other modules read them
-- too); pump counts every admission slice.
local calls={status=0,root=0,pump=0}
local wrapped={ManualPreparationStatus='status',RootState='root',PumpRootAdmission='pump'}
local raw={}
for name,key in pairs(wrapped) do
 raw[name]=C[name]
 C[name]=function(...)
  local caller=debug.getinfo(2,'f')
  local mine=key=='pump' or (key=='status' and caller and caller.func==batch)
   or (key=='root' and caller and caller.func==slice)
  if mine then calls[key]=calls[key]+1 end
  return raw[name](...)
 end
end
local function Frames(n)
 for k in pairs(calls) do calls[k]=0 end
 for _=1,n do H.Advance(.05) end
end

-- 1. Idle frames.
Frames(40)
check(calls.pump==0,'idle: no admission slice (test.9053: one per frame): '..calls.pump..' in 40 frames')
check(calls.root==0,'idle: no root-state read (test.9053: one per frame): '..calls.root)
check(calls.status==40,'idle: the batch reads the status once per frame (test.9053: three): '..calls.status)
local status=Nexus.StartupStatus()
check(status.syncGateCatalogReady==true,'Sync sees the catalog ready: '..tostring(status.syncGate))
local timing=Nexus.manualSyncTiming
check(timing.catalogPhase==nil and timing.catalogKind==nil and timing.catalogPumps==0 and timing.catalogWork==0,
 'the idle observation is recorded: '..tostring(timing.catalogKind)..' '..tostring(timing.catalogPumps))
-- Each idle update records it again (as the idle slice did), so an older
-- observation never stays on /nexus peer debug.
timing.catalogPhase,timing.catalogKind,timing.catalogPumps,timing.catalogWork='rows','mutation',7,9
H.Advance(.05)
check(timing.catalogPhase==nil and timing.catalogKind==nil and timing.catalogPumps==0 and timing.catalogWork==0,
 'one idle update replaces an older observation: '..tostring(timing.catalogKind)..' '..tostring(timing.catalogPumps))

-- 2. A received build: still admitted through slices and committed.
local donor
donor=C.Get('synthetic-startup-7')
check(donor~=nil,'fixture: a stored build to copy')
local record=H.Clone(donor);record.id='received-idle-1';record.title='Received idle';record.author='Remote-Realm'
local before=C.Count()
local ok,why,ticket=C.Put(record)
check(ok==nil and why=='ROOT_MUTATION_PENDING' and type(ticket)=='table','the write starts a catalog mutation: '..tostring(why))
for k in pairs(calls) do calls[k]=0 end
local frames=0
while ticket.state=='pending' and frames<4000 do H.Advance(.05);frames=frames+1 end
check(ticket.state=='committed','the write commits: '..tostring(ticket.state)..' after '..frames..' frames')
check(C.Count()==before+1 and C.Get('received-idle-1')~=nil,'the build is stored: '..C.Count())
check(calls.pump>0,'pending frames pump admission slices: '..calls.pump)
Frames(20)
check(calls.pump==0 and calls.root==0,'after the commit the frames are idle again: '..calls.pump..' '..calls.root)
check(Nexus.StartupStatus().syncGateCatalogReady==true and timing.catalogKind==nil,'idle again: ready, no catalog work shown')

-- 3. The allowance still decides first. A write commits inside this update's
-- preparation window (before the batch runs), and that window takes 5 ms, over
-- the 2 ms allowance. As on test.9053, the update does not report the catalog
-- ready; the next update does.
local storeIndex,rawStore
for i=1,255 do local n,v=debug.getupvalue(runUpdate,i);if not n then break end
 if n=='PumpStoreMutationSlice' then storeIndex,rawStore=i,v end end
check(storeIndex~=nil,'the lifecycle store slice is found')
local second=H.Clone(donor);second.id='received-idle-2';second.title='Received idle 2';second.author='Remote-Realm'
local ok2,why2,ticket2=C.Put(second)
check(ok2==nil and why2=='ROOT_MUTATION_PENDING','fixture: a second write is pending: '..tostring(why2))
local realClock,offset=debugprofilestop,0
check(type(realClock)=='function','fixture: a profiler clock')
debugprofilestop=function() return realClock()+offset end
debug.setupvalue(runUpdate,storeIndex,function(...)
 rawStore(...)
 local guard=0
 while ticket2.state=='pending' and guard<100000 do raw.PumpRootAdmission();guard=guard+1 end
 offset=offset+5
end)
H.Advance(.05)
debug.setupvalue(runUpdate,storeIndex,rawStore)
debugprofilestop=realClock
check(ticket2.state=='committed','fixture: the write committed inside the preparation window')
check(Nexus.StartupStatus().syncGateCatalogReady==false,
 'over the allowance: not reported ready in this update (as on test.9053): '..tostring(Nexus.StartupStatus().syncGate))
H.Advance(.05)
check(Nexus.StartupStatus().syncGateCatalogReady==true,'the next update reports the catalog ready')

for name in pairs(wrapped) do C[name]=raw[name] end
print('PASS idle catalog frames pump nothing; a received build is still admitted; '..checks..' checks')
