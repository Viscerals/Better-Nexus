-- Review finding F4, negative controls. NEW test. Real OrbRuntime/OrbAdapter;
-- mocked game services; no native evidence.
--
-- The event-driven observation adopts an offer at the moment of a choice only
-- on the same exact evidence as a timed read. A choice on an offer whose Orb
-- balance does not match the saved action is never recorded for it, and a
-- choice made while another host action is in flight does not adopt the offer.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan();H.Approve(2,false)
local source=O.source
H.Fire('PLAYER_LOGOUT')
if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
M=Nexus.OrbRuntime;check(M.Status().state=='RECOVERY','passive recovery');H.Advance(70,.05)
local reads=0;local realRead=A.Orbs.Read;A.Orbs.Read=function(...)reads=reads+1;return realRead(...)end
local guard=0;while reads==0 do H.Advance(.05,.05);guard=guard+1;assert(guard<400)end
-- 1. Another host action (a Reroll latch) is in flight with the choice.
O.charges=O.charges-1;O.offer=true
H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}});H.Notify();A.Poll()
H.perks.pendingReroll=true
check(H.service.SelectPerk(410002)==true,'choice while another host action is pending')
local receipt=Nexus.Store.State().orbRefinement.pending
check(receipt and not receipt.offerKey and not receipt.choiceObserved,'not adopted: the choice is not the single host action')
H.perks.pendingReroll=nil;H.perks.pendingSelectSpellId=nil
-- 2. The Orb balance no longer matches the saved action (a second Orb is gone).
O.charges=O.charges-1;H.Notify();A.Poll()
check(H.service.SelectPerk(410002)==true,'choice on an offer with a different Orb balance')
receipt=Nexus.Store.State().orbRefinement.pending
check(receipt and not receipt.offerKey and not receipt.choiceObserved,'not adopted: balance differs from the receipt')
local out=H.Clone(H.granted);local removed=false
for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
assert(removed);out['Desired A']={{spellId=410002,quality=2}};H.granted=out
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false;H.Notify();A.Poll();H.Advance(6,.05)
for i=1,3 do H.now=H.now+4;M.Recheck();M.Pump() end
local s=M.Status()
check(s.pending and s.spent+s.reserved==1 and Nexus.Store.State().orbRefinement.pending~=nil,'never settles; receipt and exposure kept')
check(H.Count('orb-spend')==1 and H.Count('take')==2 and not M.Resume() and not M.Prepare() and M.BlocksOrdinary(),'only the two manual choices reached the game; blocks stay')
print('PASS F4 negative: event-driven observation keeps the exact-evidence rules checks='..checks)
