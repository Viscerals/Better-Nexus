local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan({{spellId=410002,quality=2,stacks=1},{spellId=410007,quality=2,stacks=1,locked=true}})
check(M.Status().progress.permanentMissing==1 and M.Status().progress.rolledMissing==1,'planned role deficits separate')
H.Approve(3,false);H.Offer();H.Result(410002,2)
check(M.Status().state=='ROLLED_COMPLETE' and not M.Status().running,'rolled completion stops without claiming permanent completion')
check(M.Status().progress.permanentMissing==1 and M.Status().progress.rolledMissing==0,'missing permanent target preserved unchanged')
check(H.Count('orb-spend')==1,'no Orbs spent trying to acquire permanent slots')
check(not M.Prepare(),'permanent-only deficit cannot start another Orb run')
check(H.Count('lock')==0 and H.Count('unlock')==0,'no permanent write attempted')
print('PASS Orb role-specific completion/permanent-target controls='..checks)
