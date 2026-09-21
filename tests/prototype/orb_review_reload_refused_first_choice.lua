-- Review 2 note G4 (mutant i). NEW test written from the second independent
-- review's scenario e4. Real OrbRuntime/OrbAdapter; mocked game services; no
-- native evidence.
--
-- A first manual choice is made while another host action is in flight on an
-- offer that was not adopted yet. That observation is discarded. When both
-- latches clear with the offer still open (the first select was refused), the
-- offer is adopted with no recorded choice. A second, real choice is recorded
-- and settles from the exact result. Every SelectPerk call is a player call.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan();H.Approve(2,false)
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
check(M.Status().recovery.kind=='WAIT_OFFER' and M.Status().recovery.observing,'observer installed, no offer yet')
-- The offer opens with a Banish latch already in flight; the player chooses 410004 at once.
H.perks.pendingBanishIndex=1
O.charges=O.charges-1;O.offer=true
H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
check(playerSelect(410004)==true,'first choice, with another host action in flight')
local receipt=Nexus.Store.State().orbRefinement.pending
check(receipt and not receipt.offerKey and not receipt.choiceObserved,'not adopted and not recorded')
-- Both latches clear; the offer is still open: the first select was refused by the game.
H.perks.pendingBanishIndex=nil;H.perks.pendingSelectSpellId=nil;H.Notify();A.Poll();H.Advance(.5)
receipt=Nexus.Store.State().orbRefinement.pending
check(receipt and receipt.offerKey~=nil,'the still-open matching offer is adopted by the timed read')
check(not receipt.choiceObserved and not receipt.selectionAttempted and receipt.selectedKey==nil,'the discarded first observation is not counted as a choice')
check(M.Status().recovery.kind=='OFFER_OPEN','the player is told to choose')
-- The real choice.
check(playerSelect(410002)==true,'second choice')
receipt=Nexus.Store.State().orbRefinement.pending
check(receipt.choiceObserved and receipt.selectedKey=='410002:2','the second choice is recorded')
local out=H.Clone(H.granted);local removed=false
for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
assert(removed);out['Desired A']={{spellId=410002,quality=2}};H.granted=out
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false;H.Notify();A.Poll();H.Advance(1)
local s=M.Status()
check(not s.pending and s.state=='STOPPED' and s.spent==1 and s.reserved==0,'settled from the real choice and the exact result')
check(calls.select==calls.player and calls.player==2,'every SelectPerk call is a scripted player call (calls='..calls.select..')')
check(calls.spend==0,'no ConfirmSpend call after the reload')
print('PASS G4 a refused first choice on an unadopted offer is discarded; the real choice settles checks='..checks)
