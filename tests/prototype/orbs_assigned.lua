-- Approved one-Start workflow through the actual controller, adapter and UI.
local H=dofile('tests/prototype/orbs_support.lua')
local A,M,O=H.A,H.M,H.O
local target={{spellId=410002,quality=2,stacks=2},{spellId=410007,quality=2,stacks=1,locked=true}}
assert(A.SetFirstLoadoutWishlistIdentity('Assigned plan',target))
Nexus.OrbPanel.Show()
assert(NexusOrbPanel.snapshot.config.name=='Assigned plan','idle Orb UI must resolve the assigned Wishlist without a second selection')
assert(#H.actions==0,'opening the assigned plan cannot start spending')
assert(M.SetLimit(3));assert(M.Start())
assert(H.Count('orb-spend')==1,'one explicit Start automatically approves a safe source')
H.Offer();H.Result(410002,2);M.Pump()
assert(H.Count('orb-spend')==2,'a confirmed result continues from one Start')
H.Offer();H.Result(410002,2);M.Pump()
assert(M.Status().state=='ROLLED_COMPLETE' and H.Count('orb-spend')==2,'stop at rolled completion with permanent limitation')
assert(M.Status().spent==2 and M.Status().reserved==0,'confirmed usage retained')
print('PASS automatic assigned target, protected source approval, continuous attempts and rolled completion')
