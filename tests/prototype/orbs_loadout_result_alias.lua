-- Independent negative probe: a different loadout's coincidentally matching ownership is not original completion proof.
local H=dofile('tests/prototype/orbs_support.lua')
local A,M,O=H.A,H.M,H.O
local entries1={{spellId=410002,quality=2,stacks=2}}
local entries2={{spellId=410004,quality=3,stacks=2}}
H.perks.serverBuildSlots={
 [1]={name='Original owner',verified=true,echoes={{spellId=410001,quality=1,stacks=1},{spellId=410003,quality=0,stacks=1}}},
 [2]={name='Other owner',verified=true,echoes={{spellId=410001,quality=1,stacks=1},{spellId=410002,quality=2,stacks=1}}}}
H.perks.serverActiveSlot=1;H.Notify();A.Poll()
assert(A.SetLoadoutWishlistIdentity(1,'Original target',entries1))
assert(A.SetLoadoutWishlistIdentity(2,'Other target',entries2))
assert(M.Start(3));assert(O.source==410003,'known original sacrifice')
H.Offer();assert(H.Count('take')==1 and M.Status().pending)
-- No H.Result and no evidence from the original operation. Switch publishes
-- the other loadout's own list, which happens to equal the expected replacement.
H.perks.serverActiveSlot=2
H.granted={['Disposable A']={{spellId=410001,quality=1}},['Desired A']={{spellId=410002,quality=2}}}
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false
H.Notify();A.Poll();M.Pump()
local s=M.Status()
print('AFTER_DIFFERENT_LOADOUT_SNAPSHOT',s.state,'pending',s.pending,'spent',s.spent,'targetChanged',s.targetChanged,'spends',H.Count('orb-spend'))
local resumed,why=M.Resume()
print('RESUME',tostring(resumed),tostring(why),'spends',H.Count('orb-spend'))
assert(s.pending,'different loadout ownership must not prove the original operation completed')
assert(not resumed and H.Count('orb-spend')==1,'unresolved original receipt must block further spend on new loadout')
print('PASS different-loadout matching snapshot retains original pending exposure')

