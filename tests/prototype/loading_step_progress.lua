-- Real producer -> StartupStatus -> loading window, from saved-data checks to
-- shared readiness. Synthetic profile only. No clock: every scheduler turn runs
-- the existing one-slice fallback, so each owner's own counters can be sampled.
-- The window must show "Current step: <description>; d / t (p%)" only where the
-- owner already holds d and t, and an in-progress step with no bar otherwise.
local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(150,40);T.Load()
debugprofilestop=nil
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
SlashCmdList.NEXUS('loading')
local f=assert(NexusLoadingStatusFrame,'loading window exists')
local L=Nexus.LoadingStatus

local samples={}
local function Sample()
 L.Update(nil,true) -- the window's own snapshot read; no status is injected
 local s=Nexus.StartupStatus()
 local text=f.detail:GetText()
 samples[#samples+1]={status=s,text=text,bar=f.bar:IsShown(),value=f.bar:GetValue(),title=f.title:GetText()}
 return samples[#samples]
end
local function Fields(x)return tostring(x.status.step)..' '..tostring(x.status.stepDone)..'/'..tostring(x.status.stepTotal)..' | '..tostring(x.text)end

-- Passivity: repeated status and window reads at a pending point change no work.
local catalog=Nexus.BuildCatalog
local passiveChecked=false
local function Passive()
 local prep=catalog.ManualPreparationStatus()
 local before={Nexus.startupTiming.slices,prep.totalPumps,prep.pumps,prep.row,prep.index,prep.phase,
  Nexus.StartupStatus().coreReady,Nexus.StartupStatus().step,#H.sent}
 for i=1,40 do Nexus.StartupStatus();L.Update(nil,true);L.Progress(Nexus.StartupStatus())end
 local after=catalog.ManualPreparationStatus()
 local now={Nexus.startupTiming.slices,after.totalPumps,after.pumps,after.row,after.index,after.phase,
  Nexus.StartupStatus().coreReady,Nexus.StartupStatus().step,#H.sent}
 for i=1,#before do check(before[i]==now[i],'status and window reads are passive, field '..i) end
 passiveChecked=true
end

Sample()
for i=1,20000 do
 H.Advance(.05,.05)
 local x=Sample()
 if not passiveChecked and x.status.step=='catalog-rows' and x.status.coreReady==false
  and (x.status.stepDone or 0)>0 then Passive() end
 if x.status.state=='ready' then break end
end
local last=samples[#samples]
check(last.status.state=='ready','startup reaches readiness through its existing owner')
check(passiveChecked,'a pending local catalog step was sampled for passivity')

local measuredLocal,measuredScan,unknown,cleared={}, {}, 0, 0
for i,x in ipairs(samples)do
 local s=x.status
 check(not x.text:find('not yet measurable',1,true) and not x.text:find('total startup',1,true),'no generic wording: '..Fields(x))
 if s.state=='pending' then
  check(x.title=='Nexus loading','pending title while the owner is pending: '..Fields(x))
  check(x.text:find('\nCurrent step: ',1,true),'the step line is labelled as the current step: '..Fields(x))
  local d,t=s.stepDone,s.stepTotal
  if d and t and t>0 then -- an empty list has no size to show
   local p=math.floor(d*100/t)
   local want=string.format('Current step: %s; %d / %d (%d%%)',L.PhaseText(s),d,t,p)
   check(x.text:find(want,1,true),'exact step progress text: '..Fields(x))
   check(x.bar and x.value==p,'bar shows the same step percentage: '..Fields(x))
   if not s.coreReady and s.step=='catalog-rows' then measuredLocal[p]=true end
   if s.coreReady and s.step=='scan' then measuredScan[d]=true;check(t==150,'scan total is the root row count') end
  else
   unknown=unknown+1
   check(not x.bar,'unknown size hides the bar: '..Fields(x))
   check(not x.text:find('%',1,true),'unknown size shows no percentage: '..Fields(x))
   check(x.text:find('(in progress)',1,true),'unknown size shows an in-progress indicator: '..Fields(x))
   check(L.PhaseText(s)~='Preparing Community data' or s.step=='community','a specific step description: '..Fields(x))
   check(tostring(s.step):sub(1,8)~='catalog-' or L.PhaseText(s)~=L.PhaseText({state='pending',phase=s.phase}) or s.phase=='community','catalog work is not described as a Community step: '..Fields(x))
   local prev=samples[i-1]
   if prev and (prev.status.stepTotal or 0)>0 then cleared=cleared+1 end
  end
 end
end
local function Count(t)local n=0;for _ in pairs(t)do n=n+1 end;return n end
local steps={};for _,x in ipairs(samples)do local k=tostring(x.status.step)..(x.status.stepTotal and '#' or '');steps[k]=(steps[k] or 0)+1 end
for k,n in pairs(steps)do print('step',k,n)end
check(Count(measuredLocal)>=3,'local catalog rows show several changing percentages before local readiness: '..Count(measuredLocal))
check(Count(measuredScan)>=2,'Community scan shows its own changing cursor position: '..Count(measuredScan))
check(unknown>0,'unknown-size steps occur and are shown as in progress')
check(cleared>0,'a measured step followed by an unknown-size step clears the old percentage')
-- Saved-data checks before the catalog are named, not a generic line.
local named={}
for _,x in ipairs(samples)do if not x.status.coreReady then named[x.status.step]=true end end
check(named['catalog-rows'] and (named['store-characters'] or named['store-validation']),'local steps are named')
-- Readiness belongs to StartupStatus; the window only reflects it.
check(last.title=='Nexus ready' and last.bar and last.value==100,'final window reflects owner readiness')
for i=1,#samples-1 do check(samples[i].status.state~='ready','no earlier ready sample') end
local copy=Nexus.StartupStatus();copy.state='pending';copy.stepDone=1;copy.stepTotal=2
check(Nexus.StartupStatus().state=='ready' and Nexus.StartupStatus().stepTotal==nil,'snapshot is detached')
print('PASS loading_step_progress: samples='..#samples..' local%='..Count(measuredLocal)..' scan='..Count(measuredScan)..' unknown='..unknown..' cleared='..cleared..' checks='..checks)
