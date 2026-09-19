local H=dofile('tests/prototype/orbs_support.lua');local M,A=H.M,H.A
H.perks.serverBuildSlots={[1]={name='One',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}},
 [2]={name='Two',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}}}
H.perks.serverActiveSlot=1;H.Notify();A.Poll()
assert(A.SetLoadoutWishlistIdentity(1,'First',{{spellId=410002,quality=2,stacks=2}}))
assert(A.SetLoadoutWishlistIdentity(2,'Second',{{spellId=410004,quality=3,stacks=2}}))
assert(M.Start(3));H.Offer();assert(H.Count('take')==1)
H.perks.serverActiveSlot=2;H.Notify();A.Poll();M.Pump()
assert(M.Status().state=='PAUSED' and M.Status().pending and not M.Resume(),'active loadout change pauses further mutation')
H.Result(410002,2)
assert(not M.Status().pending and M.Status().spent==1,'original result settles passively after loadout change')
assert(M.Resume());assert(H.Count('orb-spend')==2 and M.Status().limit==3 and M.Status().spent==1)
assert(M.Status().config.name=='Second','explicit Resume adopts the newly assigned target')
M.Stop();H.Offer();assert(H.Count('take')==1,'Stop retains pending receipt without new selection')
print('PASS active loadout change, passive original settlement and explicit same-budget Resume')
