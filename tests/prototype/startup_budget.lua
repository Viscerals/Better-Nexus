local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(30,80);T.Load()
local clock,cost,calls=0,0,0
local factory=Nexus.MainInternals.AuthorityBootstrap
local make=factory.New
factory.New=function(...)
 local coordinator=make(...);local step=coordinator.PumpAuthorityBootstrap
 coordinator.PumpAuthorityBootstrap=function(self,...)
  calls=calls+1;clock=clock+cost;return step(self,...)
 end
 return coordinator
end
debugprofilestop=function()return clock end
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
local first=calls;H.Advance(.05,.05)
assert(calls-first>0 and calls-first<=32,'zero-time clock still respects hard 32-slice cap')
cost=.6;first=calls;H.Advance(.05,.05)
assert(calls-first>0 and calls-first<=4,'soft deadline yields between slices')
cost=3;first=calls;H.Advance(.05,.05)
assert(calls-first==1,'overshooting slice cannot start another slice')
debugprofilestop=nil;first=calls;H.Advance(.05,.05)
assert(calls-first==1,'missing clock retains one-slice fallback')
debugprofilestop=function()return 0/0 end;first=calls;H.Advance(.05,.05)
assert(calls-first==1,'invalid clock retains one-slice fallback')
assert(not Nexus.StartupStatus().coreReady,'no budget exhaustion may fabricate readiness')
debugprofilestop=function()return os.clock()*1000 end
T.Until(H,function()return Nexus.StartupStatus().state=='ready'end)
assert(Nexus.StartupStatus().coreReady,'valid unfinished work resumes normally')
print('PASS shared deadline, hard cap, overshoot, missing/invalid clock and genuine resumption')
