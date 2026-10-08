-- R2 negative controls (review of main eadff8a). NEW test written from the
-- report's R2 requirements; not a rerun of an original probe. Real OrbRuntime
-- and OrbAdapter; mocked game services; no native evidence.
--
-- After a reload, an open Orb offer that does not match the saved action exactly
-- is never adopted, even if the player then chooses and ownership changes.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan();H.Approve(2,false)
local source=O.source
H.Fire('PLAYER_LOGOUT')
if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:Hide() end
assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
M=Nexus.OrbRuntime;check(M.Status().state=='RECOVERY','passive recovery')
-- Two Orbs are gone, not one: another Orb action happened while unobserved.
O.charges=O.charges-2;O.offer=true
H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
H.Notify();A.Poll();H.Advance(.5)
local receipt=Nexus.Store.State().orbRefinement.pending
check(receipt and not receipt.offerKey,'an offer with a different Orb balance is not tied to the saved action')
local s=M.Status()
check(s.recovery and s.recovery.kind=='OFFER_UNMATCHED','status reports the unmatched offer')
check(s.reason:find('cannot',1,true)~=nil and s.reason:find('kept',1,true)~=nil,'text: cannot confirm; record kept')
check(H.service.SelectPerk(410002)==true,'the player resolves that offer in the game');H.Advance(.5)
local out=H.Clone(H.granted);local removed=false
for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
assert(removed);out['Desired A']={{spellId=410002,quality=2}};H.granted=out
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false;H.Notify();A.Poll();H.Advance(.5)
for i=1,3 do H.now=H.now+4;M.Recheck();M.Pump() end
s=M.Status()
check(s.pending and s.spent+s.reserved==1,'unmatched evidence never settles; exposure retained')
check(Nexus.Store.State().orbRefinement.pending~=nil,'receipt retained')
check(H.Count('orb-spend')==1 and H.Count('take')==1,'only the original spend and the manual choice reached the game')
check(not M.Resume() and not M.Prepare() and M.BlocksOrdinary(),'no resume, no new run, ordinary stays blocked')
print('PASS R2 unmatched offer after reload is never adopted checks='..checks)
