-- Independent fail-capable review probe. Services are synthetic; product code is unchanged.
local H=dofile('tests/prototype/orbs_support.lua');local M,O=H.M,H.O
H.OrbPlan({{spellId=410002,quality=2,stacks=2}});H.Approve(3,false)
H.Offer({{spellId=410002,quality=2},{spellId=410002,quality=1},{spellId=410004,quality=3}})
local receipt=Nexus.Store.State().orbRefinement.pending
assert(H.Count('take')==0 and M.Status().pending and receipt.selectionRefused)
print('PRECALL_REJECTION',M.Status().state,'takes',H.Count('take'),'selectedKey',receipt.selectedKey,'selectionRefused',receipt.selectionRefused)
-- A matching ownership notification arrives, with no SelectPerk call or observed choice.
H.Result(410002,2)
print('MATCHING_UNOBSERVED_SNAPSHOT','pending',M.Status().pending,'state',M.Status().state,'takes',H.Count('take'),'spent',M.Status().spent)
local pending=M.Status().pending
local resumed,reason=M.Resume()
print('RESUME_AFTER_REJECTED_SELECTION',resumed,reason,'spends',H.Count('orb-spend'),'takes',H.Count('take'))
assert(pending and not resumed and H.Count('orb-spend')==1,'SAFETY: a pre-call rejected selection and unobserved snapshot must retain pending exposure and refuse a next spend')
print('PASS pre-call rejection never becomes proof of selection')
