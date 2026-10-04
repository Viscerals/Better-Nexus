-- Startup displays the loaded identity once, with the existing command hint.
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end
local cases={
 {label='test.9999-abcdef0',channel='public-test',expected='test.9999-abcdef0'},
 {label='test.9999-abcdef1',channel='internal',expected='test.9999-abcdef1 internal'},
 {label='source',channel='development',expected='source'},
 {label='invalid',channel='internal',expected='source'},
 {missing=true,expected='source'},
}
for _,case in ipairs(cases)do
 local H=dofile('tests/prototype/harness.lua')
 dofile('tests/prototype/startup_support.lua').Load()
 Nexus.Release.buildLabel=case.label
 Nexus.Release.channel=case.channel
 if case.missing then Nexus.RuntimeBuildLabel=nil;Nexus.ReleaseIdentity=nil end
 H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD');H.Advance(20)
 check(Nexus.StartupStatus().coreReady,'startup completed')
 local function bannerCount()
  local count=0
  for _,line in ipairs(H.chat)do
   if line:find(' -- type /nexus for commands.',1,true)then
    count=count+1
    check(line:find('v1.20.0-beta.1 build='..case.expected..' -- type /nexus for commands.',1,true),'exact loaded stamp and hint')
   end
  end
  return count
 end
 check(bannerCount()==1,'single startup banner')
 H.Fire('PLAYER_ENTERING_WORLD');H.Advance(1)
 check(bannerCount()==1,'world reentry does not duplicate banner')
end
print('PASS startup build identity checks='..checks)
