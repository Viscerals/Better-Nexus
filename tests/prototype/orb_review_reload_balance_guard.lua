-- Review 2 note G4 (mutant c2). NEW test. Real OrbRuntime/OrbAdapter; mocked
-- game services; no native evidence.
--
-- The offer of the saved action was matched in this session. Then the Orb
-- balance no longer equals "one Orb less than the receipt" while the same three
-- cards are still shown. A manual choice in that state is never recorded for the
-- saved action, and it never settles. Every SelectPerk call is a player call.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan();H.Approve(2,false);check(M.Stop(),'stop before the offer');H.Offer()
local source=O.source
H.Fire('PLAYER_LOGOUT')
if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
local calls={select=0,spend=0,player=0}
do
 local rawSelect=H.service.SelectPerk
 H.service.SelectPerk=function(...)calls.select=calls.select+1;return rawSelect(...)end
 local orb=ProjectEbonhold.OrbService;local rawSpend=orb.ConfirmSpend
 orb.ConfirmSpend=function(...)calls.spend=calls.spend+1;return rawSpend(...)end
end
local function playerSelect(id)calls.player=calls.player+1;return H.service.SelectPerk(id)end
M=Nexus.OrbRuntime;check(M.Status().state=='RECOVERY','passive recovery');H.Advance(.5)
check(M.Status().recovery.kind=='OFFER_OPEN' and M.Status().recovery.observing,'matched offer under observation')
-- A second Orb is gone; the same three cards are shown.
O.charges=O.charges-1
check(playerSelect(410002)==true,'manual choice while the balance is two Orbs below the receipt')
local receipt=Nexus.Store.State().orbRefinement.pending
check(receipt and not receipt.choiceObserved and not receipt.selectionAttempted,'the choice is not recorded for the saved action')
H.Advance(.5)
receipt=Nexus.Store.State().orbRefinement.pending
check(not receipt.choiceObserved and not receipt.selectionAttempted,'a later timed read does not record it either')
check(M.Status().recovery.kind=='OFFER_UNMATCHED','classified as unmatched')
local out=H.Clone(H.granted);local removed=false
for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
assert(removed);out['Desired A']={{spellId=410002,quality=2}};H.granted=out
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false;H.Notify();A.Poll();H.Advance(1)
for i=1,3 do H.now=H.now+4;M.Recheck();M.Pump() end
local s=M.Status()
check(s.pending and s.spent+s.reserved==1 and Nexus.Store.State().orbRefinement.pending~=nil,'never settles; receipt and exposure kept')
check(not M.Resume() and not M.Prepare() and M.BlocksOrdinary(),'no resume, no new run, blocks stay')
check(calls.select==calls.player and calls.player==1,'every SelectPerk call is a scripted player call (calls='..calls.select..')')
check(calls.spend==0,'no ConfirmSpend call after the reload')
print('PASS G4 a choice at a wrong Orb balance is never recorded, also on a matched offer checks='..checks)
