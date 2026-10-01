-- Lifecycle and HUD sub-step timings and the StutterAlert timing summary
-- (HUD and lifecycle cost, 2026-10-01). The owner's test.9050 timings showed
-- lifecycle.update at 39,205 ms with 3,877 ms in automation.update and 130 ms
-- in sync.update: the rest had no named timer. The sub-steps of an update and
-- of a HUD preparation are now aggregate timers, a slow update names its
-- largest sub-step, and the StutterAlert provider can return a bounded summary.
--
-- Required: every sub-step is timed once per update it runs in; sub-steps are
-- inside their parent (no sub-step exceeds it, the sequential sub-steps of an
-- update add up to no more than it); a slow update's recent entry names its
-- largest sub-step and the v1 hitch output carries it; the HUD sub-steps are
-- timed inside hud.prepare; disabled timing reads no clock; the provider is a
-- table the v1 consumer accepts, and its summary is bounded, versioned, uses
-- only fixed names and declares nesting; without Performance it is nil.
local H=dofile('tests/prototype/harness.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.Boot()
for _=1,40 do H.Advance(.05) end
check(Nexus.StartupStatus().state=='ready','fixture: start-up completed')
local Perf=Nexus.Performance
local PHASES={'lifecycle.phase.rebind','lifecycle.phase.store','lifecycle.phase.maintenance',
 'lifecycle.phase.catalog','lifecycle.phase.hashes','lifecycle.phase.share'}
local function Stats(name) return Perf.Stats(name) end

-- 1. One timing of each sub-step per update.
Perf.Reset()
local N=30
for _=1,N do H.Advance(.05) end
local update=Stats('lifecycle.update')
check(update.count==N,'lifecycle.update once per frame: '..update.count)
local sum=0
for _,name in ipairs(PHASES) do
 local s=Stats(name)
 check(s and s.count==N,name..' once per update: '..tostring(s and s.count))
 check(s.maximum<=update.maximum+1e-6 and s.total<=update.total+1e-6,name..' is inside lifecycle.update')
 check(Perf.ParentOf(name)=='lifecycle.update',name..' declares its parent')
 sum=sum+s.total
end
local transport=Stats('lifecycle.phase.transport')
check(transport.count<=N,'transport runs at most once per update: '..transport.count)
sum=sum+transport.total
check(sum<=update.total+1e-6,'the sequential sub-steps add up to no more than the update: '..sum..' of '..update.total)
check(Stats('lifecycle.loading-status').count==N and Perf.ParentOf('lifecycle.loading-status')==nil,
 'loading status: once per frame, declared outside lifecycle.update')
check(Stats('automation.update').count==N and Perf.ParentOf('automation.update')=='lifecycle.update','automation.update inside the update')
check(Perf.ParentOf('automation.step')==nil and Perf.ParentOf('hud.prepare')==nil,'paths with several callers declare no parent')
local window=Perf.Window()
check(type(window.startedAt)=='number' and type(window.lastLifecycleAt)=='number'
 and window.startedAt<=window.lastLifecycleAt and window.lastLifecycleAt<=GetTime(),'the observation window is recorded')

-- 2. A slow update names its largest sub-step; the v1 hitch output carries it.
local now=0
check(Perf.SetClock(function() return now end),'fixture: injected clock')
local community=Nexus.CommunityBuilds
local rawShare=community.PumpPendingShare
community.PumpPendingShare=function(...) now=now+25;return rawShare(...) end
local started=GetTime()
H.Advance(.05)
community.PumpPendingShare=rawShare
local ops=Perf.RecentOperations(started-1,GetTime()+1,GetTime())
local slow
-- Newest first: the first lifecycle.update is the update just run.
for _,op in ipairs(ops) do if op.name=='lifecycle.update' and not slow then slow=op end end
check(slow and slow.durationMs>=25,'the slow update is a recent operation: '..tostring(slow and slow.durationMs))
local fields={};for _,f in ipairs(slow.fields) do fields[f.key]=f.value end
check(fields.mode=='lifecycle.phase.share' and fields.outcome==25,'it names its largest sub-step: '..tostring(fields.mode)..' '..tostring(fields.outcome))
local hitch=Nexus.StutterAlertIntegration.Collect({addonName='Nexus',hitchStartTime=started,hitchEndTime=GetTime()})
local carried
for _,op in ipairs(hitch.operations or {}) do
 if op.name=='lifecycle.update' then
  for _,f in ipairs(op.fields) do if f.key=='mode' and f.value=='lifecycle.phase.share' then carried=true end end
 end
end
check(carried,'the v1 hitch output carries the largest sub-step')
Perf.SetClock(nil)

-- 3. HUD sub-steps inside hud.prepare.
Perf.Reset()
check(Nexus.RefreshHudView()~=false,'the HUD refreshes')
local prepare=Stats('hud.prepare')
check(prepare.count==1,'one HUD preparation: '..prepare.count)
for _,name in ipairs({'hud.phase.assignment','hud.phase.projection','hud.phase.view-model'}) do
 local s=Stats(name)
 check(s.count==1 and s.total<=prepare.total+1e-6,name..' once, inside hud.prepare: '..s.count)
 check(Perf.ParentOf(name)=='hud.prepare',name..' declares hud.prepare')
end

-- 4. Disabled timing reads no clock; enabled timing reads a bounded number.
local reads=0
Perf.SetClock(function() reads=reads+1;return os.clock()*1000 end)
Perf.SetEnabled(false)
Perf.Reset()
for _=1,10 do H.Advance(.05) end
check(reads==0 and Stats('lifecycle.update').count==0,'disabled: no clock read and no aggregate: '..reads)
Perf.SetEnabled(true)
reads=0
for _=1,10 do H.Advance(.05) end
local perUpdate=reads/10
check(perUpdate<=32,'enabled: clock reads per idle update are bounded: '..perUpdate)
Perf.SetClock(nil)

-- 5. The provider: a table the v1 consumer accepts, and the summary.
local captured
_G.StutterAlert={DIAGNOSTIC_PROVIDER_API=1,
 RegisterDiagnosticProvider=function(name,provider) if name=='Nexus' then captured=provider end return true end,
 UnregisterDiagnosticProvider=function() captured=nil;return true end}
check(Nexus.StutterAlertIntegration.Register()==true,'registration with the v1 API')
check(type(captured)=='table' and type(rawget(captured,'Collect'))=='function','a table with Collect (v1 accepts it)')
local v1=rawget(captured,'Collect')(captured,{addonName='Nexus',hitchStartTime=GetTime()-1,hitchEndTime=GetTime()})
check(type(v1)=='table','the v1 call returns a table')
local summary=captured.CollectTimingSummary(captured)
check(type(summary)=='table' and summary.timingSummaryVersion==1,'summary version 1')
local allowed={timingSummaryVersion=1,units=1,nesting=1,windowClock=1,version=1,buildLabel=1,enabled=1,
 clockAvailable=1,windowStart=1,windowEnd=1,lastUpdate=1,rows=1,counters=1}
for k,v in pairs(summary) do check(allowed[k],'only declared summary fields: '..tostring(k)) end
check(summary.units=='ms' and summary.nesting=='inclusive' and summary.windowClock=='GetTime','units, nesting and clock are declared')
check(summary.windowStart<=summary.windowEnd and summary.lastUpdate<=summary.windowEnd,'window order')
check(#summary.rows>=20 and #summary.rows<=24,'bounded rows: '..#summary.rows)
local seen={}
for _,row in ipairs(summary.rows) do
 for k in pairs(row) do check(k=='name' or k=='parent' or k=='count' or k=='totalMs' or k=='maxMs','row field '..k) end
 check(type(row.name)=='string' and #row.name<=48 and Perf.Stats(row.name)~=nil,'row names are Performance paths: '..row.name)
 check(row.parent==nil or seen[row.parent],'a parent is listed before its child: '..row.name)
 check(row.count>=0 and row.totalMs>=0 and row.maxMs>=0,'non-negative values')
 seen[row.name]=true
end
check(#summary.counters<=8,'bounded counters')
for _,c in ipairs(summary.counters) do
 check(type(c.name)=='string' and c.name:match('^[%l%.%-]+$') and type(c.value)=='number' and c.value>=0,'counter '..tostring(c.name))
end
local function Size(v) if type(v)~='table' then return #tostring(v) end local n=0 for k,x in pairs(v) do n=n+Size(k)+Size(x)+2 end return n end
check(Size(summary)<2500,'summary is small: '..Size(summary)..' bytes')
local keep=Nexus.Performance;Nexus.Performance=nil
check(captured.CollectTimingSummary(captured)==nil,'without Performance: no summary, no error')
Nexus.Performance=keep
_G.StutterAlert=nil
Nexus.StutterAlertIntegration.Register()

print('PASS lifecycle and HUD sub-steps timed inside their parents; summary bounded; '..checks..' checks (clock reads per idle update '..perUpdate..')')
