-- Diagnostic comparison, not a native timing guarantee or acceptance threshold.
local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua')
local n,pool=tonumber(os.getenv('NX_ROWS')) or 100,tonumber(os.getenv('NX_POOL')) or 5000
NexusDB=T.Profile(n,pool);T.Load()
local evidenceCalls,evidenceCPU=0,0;local init=Nexus.LoadoutEvidence.Init
Nexus.LoadoutEvidence.Init=function(...)
 local began=os.clock();evidenceCalls=evidenceCalls+1;local result=init(...)
 evidenceCPU=evidenceCPU+os.clock()-began;return result
end
local began=os.clock();local coreTurns,coreCPU,sharedTurns,sharedCPU
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
for i=1,100000 do
 H.Advance(.05,.05)
 if not coreTurns and Nexus.startupTiming.readyAt then coreTurns,coreCPU=i,os.clock()-began end
 local done=type(Nexus.StartupStatus)=='function' and Nexus.StartupStatus().state=='ready'
  or type(Nexus.StartupStatus)~='function' and coreTurns~=nil
 if done then sharedTurns,sharedCPU=i,os.clock()-began;break end
end
assert(sharedTurns,'bounded benchmark did not complete')
local root=Nexus.BuildCatalog.RootState();assert(root.state=='ROOT_ADMITTED')
local cursor=assert(Nexus.BuildCatalog.BeginRecordCursor());local rows={}
for i=1,200000 do
 local page,why=Nexus.BuildCatalog.RecordCursorNext(cursor);assert(page and not why)
 if page.record then
  local tokens={}
  for _,echo in ipairs(page.record.echoes or {})do
   tokens[#tokens+1]=echo.spellId..':'..tostring(echo.quality)..':'..echo.stacks..':'..tostring(echo.locked)
  end
  table.sort(tokens);rows[#rows+1]=tostring(page.id)..'='..table.concat(tokens,',')
 end
 if page.done then break end
end
table.sort(rows);assert(#rows==n,'benchmark lost build rows')
local bundle=NexusDB.authorityBundle
for i=1,n do assert(bundle.communityBuilds['synthetic-startup-'..i].customUnknown.keep==i)end
for i=1,pool do assert(bundle.loadoutEvidence.entries['synthetic-preserved-'..i].keep==i)end
local function hash(s)local h=5381;for i=1,#s do h=(h*33+s:byte(i))%2147483648 end;return h end
print(string.format('METRIC rows=%d pool=%d core_turns=%d core_cpu=%.6f shared_turns=%d shared_cpu=%.6f evidence_calls=%d evidence_cpu=%.6f semantic_hash=%d',n,pool,coreTurns,coreCPU,sharedTurns,sharedCPU,evidenceCalls,evidenceCPU,hash(table.concat(rows,'\n'))))
print('NOTE intervals=0.05 simulated seconds; CPU measured under stated offline interpreter; not native WoW timing')
