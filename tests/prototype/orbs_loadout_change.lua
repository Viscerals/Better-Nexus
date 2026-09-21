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
assert(M.Status().pending and M.Status().spent==1,'a result after a loadout boundary cannot be attributed to the original action')
assert(not M.Resume() and M.Status().limit==3 and H.Count('orb-spend')==1,'ambiguity retains the same allowance without further spend')
assert(M.Status().reason:find('original loadout',1,true),'specific correlation limitation is visible')
H.perks.serverActiveSlot=1;H.Notify();A.Poll();M.Recheck();M.Pump()
assert(M.Status().pending and not M.Resume(),'returning to the old slot does not identify an uncorrelated response')
M.Stop();M.Recheck();assert(M.Status().pending and H.Count('take')==1,'Stop and Recheck preserve unresolved receipt without new selection')
local receipt=Nexus.Store.State().orbRefinement.pending
assert(receipt.loadoutChanged and receipt.originalSlot==1 and receipt.spent==1 and receipt.limit==3)
if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:Hide() end
assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
M=Nexus.OrbRuntime;M.Recheck();M.Pump()
assert(M.Status().pending and M.Status().spent==1 and M.Status().limit==3 and not M.Resume(),'reload keeps loadout ambiguity and exposure')
assert(H.Count('orb-spend')==1 and H.Count('take')==1,'no mutation used to resolve ambiguity')
print('PASS loadout change retains pending exposure across result, return, Stop, Recheck and reload')
