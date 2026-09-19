local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
H.OrbPlan({{spellId=410002,quality=2,stacks=3}})
local charges=ProjectEbonhold.OrbService.GetCharges;local changed=false
ProjectEbonhold.OrbService.GetCharges=function()
 if not changed and Nexus.Store.State().orbRefinement and Nexus.Store.State().orbRefinement.pending then
  changed=true;assert(A.SetFirstLoadoutWishlistIdentity('Changed during source read',{{spellId=410004,quality=3,stacks=2}}))
 end
 return charges()
end
assert(M.Start(3));assert(H.Count('orb-spend')==0 and not M.Status().pending,'last adapter read cannot spend after assignment drift')
assert(M.Status().reserved==0 and M.Status().state=='PAUSED','pre-call refusal reserves no exposure')
ProjectEbonhold.OrbService.GetCharges=charges;assert(M.Resume());assert(H.Count('orb-spend')==1)
local selected=false
ProjectEbonhold.OrbService.GetCharges=function()
 local p=Nexus.Store.State().orbRefinement.pending
 if p and p.selectionAttempted and not selected then
  selected=true;assert(A.SetFirstLoadoutWishlistIdentity('Changed during choice read',{{spellId=410002,quality=2,stacks=3}}))
 end
 return charges()
end
H.Offer({{spellId=410004,quality=3},{spellId=410002,quality=2},{spellId=410008,quality=1}})
assert(H.Count('take')==0 and M.Status().pending and M.Status().spent==1,'pre-call choice refusal keeps original spending exposure')
assert(not M.Resume() and H.Count('orb-spend')==1,'no repeated selection or spend to resolve the race')
print('PASS assignment races through real source/choice adapter reads, refusal and retained pending exposure')
