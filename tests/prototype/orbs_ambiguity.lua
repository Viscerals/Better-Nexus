local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan();O.mode='throw';H.Approve(2,false)
check(M.Status().state=='PAUSED' and M.Status().pending,'ambiguous call pauses and retains pending receipt')
check(M.Status().reserved==1 and H.Count('orb-spend')==1,'unresolved exposure counts against budget')
for i=1,5 do M.Pump()end
check(H.Count('orb-spend')==1,'ambiguous spend never replayed')
check(not M.Resume(),'cannot resume an unconfirmed spend')
local persisted=Nexus.Store.State().orbRefinement.pending
check(persisted and persisted.ambiguous and persisted.removed,'recovery receipt persisted')
O.mode='accept';H.Offer()
check(M.Status().spent==1 and M.Status().reserved==0,'later charge/offer settles exposure')
check(H.Count('take')==0,'ambiguous operation requires an explicit resume before selection')
check(M.Resume(),'explicit resume after spend outcome becomes known')
H.Result(410002,2)
check(M.Status().state=='COMPLETE' and H.Count('orb-spend')==1,'original ambiguous operation can settle without replay')
-- Explicit pre-result rejection creates no irreversible exposure.
H.OrbPlan({{spellId=410004,quality=3,stacks=1}});O.mode='refuse';H.Approve(2,false)
check(not M.Status().pending and M.Status().reserved==0,'explicitly refused spend clears exposure')
local count=H.Count('orb-spend');M.Pump();check(H.Count('orb-spend')==count,'refusal does not auto-retry')
check(M.Stop(),'operator may stop a refused run')
-- An accepted offer followed by ambiguous selection is never submitted again.
O.mode='accept';H.OrbPlan({{spellId=410004,quality=3,stacks=1}});H.Approve(2,false)
local select=H.service.SelectPerk
H.service.SelectPerk=function(id)select(id);error('synthetic post-submit error')end
H.Offer({{spellId=410004,quality=3},{spellId=410001,quality=1},{spellId=410008,quality=1}})
local chosen=H.Count('take')
check(M.Status().state=='PAUSED' and M.Status().pending,'ambiguous selection holds original operation')
check(not M.Resume(),'submitted selection cannot be replayed with Resume')
M.Pump();check(H.Count('take')==chosen,'no repeat SelectPerk')
H.service.SelectPerk=select;H.Result(410004,3)
check(M.Status().state=='COMPLETE' and not M.Status().pending,'fresh matching result settles ambiguous selection')
print('PASS Orb refused/ambiguous spending and selection controls='..checks)
