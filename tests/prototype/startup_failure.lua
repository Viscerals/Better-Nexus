local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua');T.Load()
local calls=0
Nexus.CommunityBuilds.Init=function()calls=calls+1;error('synthetic shared preparation failure')end
local syncInit,dpsInit=0,0
Nexus.Sync.Init=function()syncInit=syncInit+1 end
Nexus.DpsCapture.Init=function()dpsInit=dpsInit+1 end
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD');H.Advance(10)
local st=Nexus.StartupStatus()
assert(st.coreReady and st.state=='failed','shared failure must not hold local controls hostage')
assert(calls==1 and syncInit==0 and dpsInit==0,'failed owner must not be retried/spawn dependents')
Nexus.WishlistEditor.Show();SlashCmdList.NEXUS('status')
assert(table.concat(H.chat,'\n'):find('shared data preparation failed',1,true),'clear failure status')
Nexus.CommunityBuilds.Show()
assert(NexusSharedStartupFrame:IsShown(),'failed shared feature shows status rather than importing')
local frames=#H.frames;H.Advance(20)
assert(calls==1 and #H.frames==frames,'failure cannot make an initialization retry/frame storm')
local ok=Nexus.Sync.RequestSync()
assert(ok==false and #H.sent==0,'failure cannot admit manual network work')
local holder=Nexus.StartupStatus();holder.reason=nil;holder.state='ready'
assert(Nexus.StartupStatus().state=='failed','status writes cannot grant readiness')
print('PASS shared startup fault isolation and no silent auto-retry')

-- B-02: a dependent Init that raises an error during the one-time core
-- initialization is attempted once and recorded under its owner. An optional
-- view never holds the core back; a required owner is a terminal failure.
-- No frame may keep raising errors afterwards. Real TOC boot; synthetic data.
local function Boot(prepare)
 Nexus=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 H=dofile('tests/prototype/harness.lua')
 NexusDB=T.Profile(3,0)
 T.Load()
 if prepare then prepare() end
 local errors=0
 if not pcall(H.Fire,'ADDON_LOADED','Nexus') then errors=errors+1 end
 if not pcall(H.Fire,'PLAYER_ENTERING_WORLD') then errors=errors+1 end
 return errors
end
-- Up to n scheduler turns, stopping early once stop() holds; the number of
-- turns that raised an error.
local function Drive(n,stop)
 local errors=0
 for i=1,n do
  if not pcall(H.Advance,.05,.05) then errors=errors+1 end
  if stop and stop() then break end
 end
 return errors
end
local function Recorded(text)
 local list={}
 for _,entry in ipairs(Nexus.Errors.History()) do
  if type(entry.message)=='string' and entry.message:find(text,1,true) then list[#list+1]=entry end
 end
 return list
end

-- 1. Ordinary start-up: each owner is initialized once and nothing is recorded.
local panelCalls,boardCalls=0,0
local bootErrors=Boot(function()
 local panel,board=Nexus.Panel.Init,Nexus.Leaderboard.Init
 Nexus.Panel.Init=function(...)panelCalls=panelCalls+1;return panel(...)end
 Nexus.Leaderboard.Init=function(...)boardCalls=boardCalls+1;return board(...)end
end)
local frameErrors=Drive(20000,function()return Nexus.StartupStatus().state~='pending' end)
st=Nexus.StartupStatus()
assert(bootErrors==0 and frameErrors==0,'control: an ordinary start-up raises no error: '..bootErrors..'/'..frameErrors)
assert(st.coreReady and st.state=='ready','control: an ordinary start-up is ready: '..tostring(st.state))
assert(panelCalls==1 and boardCalls==1,'control: each owner is initialized once: '..panelCalls..'/'..boardCalls)
print('PASS ordinary start-up initializes each owner once')

-- 2. Optional views raise errors: each is attempted once and recorded under
-- its own owner; the core still becomes ready and later turns raise nothing.
local OPTIONAL={'Leaderboard','Nameplate','ServerStatus','CallboardStatus','LogViewer'}
local optionalCalls={}
panelCalls=0
bootErrors=Boot(function()
 local panel=Nexus.Panel.Init
 Nexus.Panel.Init=function(...)panelCalls=panelCalls+1;return panel(...)end
 for _,name in ipairs(OPTIONAL) do
  if type(Nexus[name])=='table' and type(Nexus[name].Init)=='function' then
   optionalCalls[name]=0
   Nexus[name].Init=function()optionalCalls[name]=optionalCalls[name]+1;error('synthetic optional init failure '..name)end
  end
 end
end)
assert(optionalCalls.Leaderboard,'fixture: the Leaderboard view exists and raises')
-- Until the core is initialized (or, before this repair, the second attempt).
frameErrors=Drive(20000,function()return Nexus.StartupStatus().coreReady or optionalCalls.Leaderboard>1 end)
frameErrors=frameErrors+Drive(400)
st=Nexus.StartupStatus()
assert(bootErrors==0 and frameErrors==0,'a failing optional view raises no error out of start-up or a later turn: '..bootErrors..'/'..frameErrors)
assert(st.coreReady and st.state~='failed','a failing optional view does not block or fail the core: '..tostring(st.state)..' '..tostring(st.reason))
for name,count in pairs(optionalCalls) do
 assert(count==1,name..'.Init is attempted exactly once: '..count)
 local list=Recorded('synthetic optional init failure '..name)
 assert(#list==1 and list[1].source:find(name..'.Init',1,true),name..'.Init: one error recorded under its owner: '..#list..' '..tostring(list[1] and list[1].source))
end
assert(panelCalls==1,'the core panel is initialized once: '..panelCalls)
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
assert(Drive(200)==0,'no later turn raises an error')
for name,count in pairs(optionalCalls) do assert(count==1 and #Recorded('synthetic optional init failure '..name)==1,name..'.Init is never retried') end
print('PASS failing optional views are isolated once and the core becomes ready')

-- 3. A required owner raises an error: one attempt, a terminal failed status
-- naming the owner, no retry on later turns or world entries, and the gates
-- that wait for initialization stay closed.
panelCalls=0
local syncCalls=0
bootErrors=Boot(function()
 Nexus.Panel.Init=function()panelCalls=panelCalls+1;error('synthetic required init failure')end
 local sync=Nexus.Sync.Init
 Nexus.Sync.Init=function(...)syncCalls=syncCalls+1;return sync(...)end
end)
-- Until the first attempt, then further turns.
frameErrors=Drive(20000,function()return panelCalls>0 end)
frameErrors=frameErrors+Drive(400)
st=Nexus.StartupStatus()
assert(bootErrors==0 and frameErrors==0,'a failing required owner raises no error out of start-up or a later turn: '..bootErrors..'/'..frameErrors)
assert(panelCalls==1,'Panel.Init is attempted exactly once: '..panelCalls)
assert(not st.coreReady and st.state=='failed' and st.reason=='CORE_INIT_FAILED','a required owner failure is a terminal failed start-up: '..tostring(st.state)..' '..tostring(st.reason))
assert(type(st.failure)=='table' and st.failure.owner=='Panel.Init' and type(st.failure.error)=='string'
 and st.failure.error:find('synthetic required init failure',1,true),'the failure names its owner and error: '..tostring(st.failure and st.failure.owner))
local list=Recorded('synthetic required init failure')
assert(#list==1 and list[1].source:find('Panel.Init',1,true),'one error recorded under its owner: '..#list)
assert(syncCalls==0,'no dependent is released after a required owner failed')
if not pcall(H.Fire,'PLAYER_ENTERING_WORLD') then frameErrors=frameErrors+1 end
frameErrors=frameErrors+Drive(200)
assert(frameErrors==0 and panelCalls==1 and #Recorded('synthetic required init failure')==1,'a later world entry or turn never retries it: '..frameErrors..'/'..panelCalls)
local chat=#H.chat;SlashCmdList.NEXUS('status')
local said=table.concat(H.chat,'\n',chat+1)
assert(said:find('Startup stopped: CORE_INIT_FAILED',1,true),'/nexus status states the terminal failure: '..said)
local okSync,requested=pcall(Nexus.Sync.RequestSync)
assert(not(okSync and requested) and #H.sent==0,'manual network work stays refused')
local okOrb,started=pcall(Nexus.OrbRuntime.Start,1)
assert(not(okOrb and started),'Orb Start stays refused')
holder=Nexus.StartupStatus();holder.reason=nil;holder.state='ready';holder.coreReady=true
st=Nexus.StartupStatus()
assert(st.state=='failed' and not st.coreReady,'status writes cannot grant readiness')
print('PASS a failing required owner latches a terminal failed start-up without retries')

-- 4. B-03: an adapter call of the world entry that follows initialization
-- raises an error. The shared entry is still owned and settles once: Sync and
-- DPS start exactly once, the error is recorded once under its owner and named
-- in the start-up status, no error escapes into a frame or event, and a later
-- world entry starts nothing twice. Each site, and the ordinary entry as the
-- control. The throw is armed only for the lifecycle's own world-entry calls:
-- Adapter.OnEvent('PLAYER_ENTERING_WORLD') once the core is initialized, and
-- the next Adapter.RequestSlots call after it returns (or raises), so a call
-- the adapter makes inside its own OnEvent is never the one counted.
local function WorldEntry(site)
 local c={sync=0,dps=0,entries=0,slots=0}
 local armed=false
 local errors=Boot(function()
  local adapter=Nexus.GameAdapter
  local onEvent,slots=adapter.OnEvent,adapter.RequestSlots
  assert(type(onEvent)=='function' and type(slots)=='function','fixture: the adapter has both world-entry calls')
  adapter.OnEvent=function(event,...)
   local entry=event=='PLAYER_ENTERING_WORLD' and Nexus.StartupStatus().coreReady
   if entry then
    c.entries=c.entries+1
    if site=='OnEvent' then armed=true;error('synthetic world entry failure OnEvent') end
   end
   local function pass(...) if entry then armed=true end return ... end
   return pass(onEvent(event,...))
  end
  adapter.RequestSlots=function(...)
   if armed then
    armed=false;c.slots=c.slots+1
    if site=='RequestSlots' then error('synthetic world entry failure RequestSlots') end
   end
   return slots(...)
  end
  local sync,dps=Nexus.Sync.Init,Nexus.DpsCapture.Init
  Nexus.Sync.Init=function(...)c.sync=c.sync+1;return sync(...)end
  Nexus.DpsCapture.Init=function(...)c.dps=c.dps+1;return dps(...)end
 end)
 errors=errors+Drive(20000,function()return Nexus.StartupStatus().state~='pending' end)
 errors=errors+Drive(200)
 return c,errors,Nexus.StartupStatus()
end
for _,site in ipairs({false,'OnEvent','RequestSlots'})do
 local label=site and ('Adapter.'..site) or 'control'
 local c,errors,s=WorldEntry(site)
 assert(errors==0,label..': no error escapes start-up or a later turn: '..errors)
 assert(c.entries==1 and c.slots==1,label..': the world entry ran once with both adapter calls: '..c.entries..'/'..c.slots)
 assert(s.coreReady and s.state=='ready',label..': start-up is ready: '..tostring(s.state)..' '..tostring(s.reason))
 assert(s.syncReady and s.dpsReady and c.sync==1 and c.dps==1,
  label..': the shared entry is not stranded; Sync and DPS start once: '..tostring(s.syncReady)..'/'..tostring(s.dpsReady)..' '..c.sync..'/'..c.dps)
 local recorded=site and Recorded('synthetic world entry failure '..site) or {}
 if site then
  assert(type(s.worldEntryFailure)=='table' and s.worldEntryFailure.owner==label and type(s.worldEntryFailure.error)=='string'
   and s.worldEntryFailure.error:find('synthetic world entry failure '..site,1,true),
   label..': the status names the failed world-entry call: '..tostring(s.worldEntryFailure and s.worldEntryFailure.owner))
  assert(#recorded==1 and recorded[1].source:find(label,1,true),label..': one error recorded under its owner: '..#recorded)
  s.worldEntryFailure.owner='edited'
  assert(Nexus.StartupStatus().worldEntryFailure.owner==label,label..': a status write cannot change the report')
 else
  assert(s.worldEntryFailure==nil,'control: an ordinary world entry reports no failure')
 end
 -- A later loading screen: the same entry again, with the same call failing.
 local again=0
 if not pcall(H.Fire,'PLAYER_ENTERING_WORLD') then again=again+1 end
 again=again+Drive(200)
 s=Nexus.StartupStatus()
 assert(again==0 and c.entries==2 and c.slots==2,label..': a later world entry raises nothing and runs once: '..again..' '..c.entries..'/'..c.slots)
 assert(c.sync==1 and c.dps==1 and s.syncReady and s.dpsReady,label..': a later world entry starts nothing twice: '..c.sync..'/'..c.dps)
 if site then
  assert(#Recorded('synthetic world entry failure '..site)==1,label..': the same error is not recorded again')
  assert(s.worldEntryFailure and s.worldEntryFailure.owner==label,label..': the later entry reports its own failure')
 else
  assert(s.worldEntryFailure==nil,'control: a later ordinary world entry reports no failure')
 end
end
print('PASS a world-entry adapter error is isolated, reported and cannot strand the shared entry')
