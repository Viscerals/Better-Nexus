local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan({{spellId=410004,quality=3,stacks=1}});H.Approve(2,true)
local source=O.source;local q=H.db[source].quality
H.Offer({{spellId=source,quality=q},{spellId=410008,quality=1},{spellId=410001,quality=1}})
check(M.Status().state=='WAIT_RESULT','same-source fallback submitted')
-- Old pre-request snapshot and disappearing UI are insufficient confirmation.
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false
M.Pump();check(M.Status().pending and H.Count('orb-spend')==1,'closed UI plus old unchanged snapshot cannot confirm same-ID result')
H.Result(source,q,true)
check(M.Status().pending and H.Count('orb-spend')==1,'same-reference equal-content snapshot remains unproven')
H.holdGrantedResponse=false;H.now=H.now+3.1
check(M.Recheck(),'bounded explicit refresh allowed')
check(not M.Status().pending and M.Status().spent==1,'fresh authoritative response plus exact diff confirms same-ID replacement')
M.Pump();check(H.Count('orb-spend')==2 and O.source==source,'confirmed safe recycled source used only after result proof')
M.Stop();H.Offer({{spellId=410004,quality=3},{spellId=410008,quality=1},{spellId=410001,quality=1}})
H.service.SelectPerk(410004);H.Result(410004,3)
check(H.Count('orb-spend')==2 and not M.Status().pending,'terminal passive settlement does not overspend')
-- A different-ID result cannot be accepted as the selected target.
H.OrbPlan({{spellId=410002,quality=2,stacks=1}});H.Approve(1,false);H.Offer()
H.Result(410008,1)
check(M.Status().state=='PAUSED' and M.Status().pending,'unexpected replacement remains unresolved')
check(H.Count('orb-spend')==3,'mismatch stops additional mutation')
print('PASS Orb same-ID/fresh-response and unexpected-result controls='..checks)
