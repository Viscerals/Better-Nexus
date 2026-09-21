local H=dofile('tests/prototype/orbs_support.lua');local A,M=H.A,H.M
H.perks.serverBuildSlots={[1]={name='One',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}},
 [2]={name='Two',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}}}
H.perks.serverActiveSlot=1;H.Notify();A.Poll()
assert(A.SetLoadoutWishlistIdentity(1,'First',{{spellId=410002,quality=2,stacks=2}}))
assert(A.SetLoadoutWishlistIdentity(2,'Second',{{spellId=410004,quality=3,stacks=2}}))
assert(M.Start(3));assert(M.Status().spent==0 and M.Status().reserved==1)
H.perks.serverActiveSlot=2;H.Notify();A.Poll();M.Recheck()
assert(M.Status().pending and not M.Status().running)
H.Offer()
assert(H.Count('take')==0,'a late offer after loadout change cannot trigger a selection')
assert(M.Status().spent==0 and M.Status().reserved==1,'uncorrelated charge and offer cannot relabel unresolved exposure')
H.service.SelectPerk(410002);H.Result(410002,2)
assert(M.Status().pending and not M.Resume(),'manual choice on the other loadout cannot confirm the original action')
M.Stop();H.perks.serverActiveSlot=1;H.Notify();A.Poll();M.Recheck()
assert(M.Status().pending and M.Status().spent+M.Status().reserved==1 and M.Status().limit==3)
assert(H.Count('orb-spend')==1 and H.Count('take')==1,'only the explicit synthetic manual choice was sent')
print('PASS pre-offer loadout change, delayed charge/offer, unrelated manual selection and retained reservation')
