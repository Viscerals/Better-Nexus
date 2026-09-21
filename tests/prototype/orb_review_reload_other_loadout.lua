-- R2 / B2 preservation control (review of main eadff8a). NEW test; not a rerun
-- of an original probe. Real OrbRuntime/OrbAdapter; mocked game services.
--
-- A manual choice made while another loadout is active is never recorded for
-- the saved action. The loadout boundary stays in the receipt, and returning to
-- the old loadout never settles it.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.perks.serverBuildSlots={[1]={name='One',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}},
 [2]={name='Two',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}}}
H.perks.serverActiveSlot=1;H.Notify();A.Poll()
assert(A.SetLoadoutWishlistIdentity(1,'First',{{spellId=410002,quality=2,stacks=2}}))
assert(A.SetLoadoutWishlistIdentity(2,'Second',{{spellId=410004,quality=3,stacks=2}}))
assert(M.Start(3));check(M.Stop(),'stop before the offer');H.Offer()
check(H.Count('take')==0 and Nexus.Store.State().orbRefinement.pending.offerKey~=nil,'checkpoint: offer observed, no selection')
local source=O.source
H.Fire('PLAYER_LOGOUT')
if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:Hide() end
assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
M=Nexus.OrbRuntime;check(M.Status().state=='RECOVERY','passive recovery')
-- The player is on another loadout when choosing.
H.perks.serverActiveSlot=2;H.Notify();A.Poll();H.Advance(.5)
check(M.Status().pending and M.Status().reason:find('original loadout',1,true)~=nil,'loadout boundary is reported')
check(H.service.SelectPerk(410002)==true,'choice while another loadout is active')
H.Advance(.5)
local receipt=Nexus.Store.State().orbRefinement.pending
check(receipt and not receipt.choiceObserved and not receipt.selectionAttempted,'a choice on another loadout is not recorded for the saved action')
check(receipt.loadoutChanged==true,'the loadout boundary is kept in the receipt')
H.perks.serverActiveSlot=1;H.perks.pendingSelectSpellId=nil;H.Notify();A.Poll();H.Advance(.5)
local out=H.Clone(H.granted);local removed=false
for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
assert(removed);out['Desired A']={{spellId=410002,quality=2}};H.granted=out
H.perks.currentChoice=nil;O.offer=false;H.Notify();A.Poll();H.Advance(.5)
for i=1,2 do H.now=H.now+4;M.Recheck();M.Pump() end
check(M.Status().pending and M.Status().spent+M.Status().reserved==1 and not M.Resume(),'returning to the old loadout never settles it; exposure kept')
check(H.Count('orb-spend')==1 and H.Count('take')==1,'only the original spend and the manual choice reached the game')
print('PASS R2 loadout boundary keeps B2 across reload checks='..checks)
