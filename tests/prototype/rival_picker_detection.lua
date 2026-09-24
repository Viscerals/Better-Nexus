-- Rival-picker protection. While another Echo picker is loaded, Nexus
-- automation stays paused. The keys are the exact addon name and slash-command
-- key of a separately distributed picker, and the EchoOptimizer global: they
-- are compatibility detection identifiers, not Nexus names (THIRD_PARTY.md).
-- Real TOC boot and automation; the game answers are synthetic.
local H=dofile('tests/prototype/harness.lua');H.pendingRolls=2;H.Boot()
local A=Nexus.GameAdapter;local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
check(A.RivalDetected()==false,'no other picker: nothing detected')
local plainLoaded=IsAddOnLoaded
IsAddOnLoaded=function(name) return name=='LoadoutPilot' or plainLoaded(name) end
check(A.RivalDetected()==true,'the separate picker is detected by its exact addon name')
IsAddOnLoaded=plainLoaded
SlashCmdList.LOADOUTPILOT=function() end
check(A.RivalDetected()==true,'the separate picker is detected by its exact slash-command key')
SlashCmdList.LOADOUTPILOT=nil
EchoOptimizer={}
check(A.RivalDetected()==true,'EchoOptimizer is detected')
EchoOptimizer=nil
check(A.RivalDetected()==false,'detection clears when no other picker is loaded')
-- The protection reaches automation: nothing is submitted while one is loaded.
check(A.SetFirstLoadoutWishlistIdentity('Rival check',{ {spellId=200001,quality=1,stacks=2} }),'set a plan')
H.Board({{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200021,quality=1}})
H.Notify();H.Advance(.5)
SlashCmdList.LOADOUTPILOT=function() end
SlashCmdList.NEXUS('auto');H.Advance(1.2)
check(#H.actions==0,'automation submits nothing while the separate picker is loaded: '..#H.actions)
SlashCmdList.LOADOUTPILOT=nil;H.Advance(1.2)
local freeze
for _,a in ipairs(H.actions)do if a[1]=='freeze' then freeze=a end end
check(freeze~=nil,'when it is gone, the same board gets its ordinary decision (positive control)')
print('PASS rival_picker_detection: exact compatibility keys detected; automation paused while present checks='..checks)
