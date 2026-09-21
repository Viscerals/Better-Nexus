local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan();M.SuggestSources();local p=assert(M.Prepare())
H.now=H.now+61;check(not M.Confirm(p.token) and H.Count('orb-spend')==0,'old confirmation expires')
p=assert(M.Prepare());M.SetSource('410003:0',0)
check(not M.Confirm(p.token) and H.Count('orb-spend')==0,'source change invalidates approval')
H.Approve(2,false);local calls=H.Count('orb-spend')
H.playerLevel=H.playerLevel+1;M.Pump()
check(M.Status().state=='PAUSED' and M.Status().pending,'run/generation context change keeps unresolved transaction')
check(not M.Resume() and H.Count('orb-spend')==calls,'cannot resume with another level/run context')
H.playerLevel=H.playerLevel-1;M.Stop()
H.Offer();H.service.SelectPerk(410002);H.Result(410002,2)
check(not M.Status().pending and H.Count('orb-spend')==calls,'passive exact operation can settle when original context is observable again')
-- An incomplete permanent-role requirement is not treated as spendable progress.
H.OrbPlan({{spellId=410002,quality=2,stacks=1},{spellId=410007,quality=2,stacks=1,locked=true}})
local start,why=M.Prepare();check(not start and why:find('permanent',1,true),'cannot spend trying to manufacture permanent targets')
H.OrbPlan({{spellId=410004,quality=3,stacks=1}});H.disabled[410004]=true
check(not M.Prepare(),'currently disabled target blocks approval');H.disabled[410004]=false
check(H.Count('orb-spend')==calls,'context/read-only tests never repeat spend')
print('PASS Orb approval binding, session interruption and permanent-target eligibility checks='..checks)
