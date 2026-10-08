-- R2 (review of main eadff8a): the reload happens after the spend and before
-- any offer was observed. The offer is first seen after the reload. NEW test
-- written from the review report's R2 scenario; not a rerun of an original probe.
-- Real OrbRuntime and OrbAdapter; mocked game services; no native evidence.
--
-- Recovery may tie a still-pending offer to the saved action only with the same
-- evidence the live path uses, checked exactly: one Orb less than the receipt,
-- ownership equal to the receipt (with or without the named source), unchanged
-- permanent Echoes, the original loadout, and no host action in flight.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan();H.Approve(2,false)
local receipt=Nexus.Store.State().orbRefinement.pending
check(receipt and not receipt.offerKey and not receipt.spendConfirmed,'checkpoint: spend submitted, nothing observed')
local source=O.source
H.Fire('PLAYER_LOGOUT')
if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:Hide() end
assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
M=Nexus.OrbRuntime
check(M.Status().state=='RECOVERY' and M.Status().reserved==1 and M.Status().spent==0,'exposure restored as unresolved')
-- The owed offer is delivered after the reload.
O.charges=O.charges-1;O.offer=true
H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
H.Notify();A.Poll();H.Advance(.5)
receipt=Nexus.Store.State().orbRefinement.pending
check(receipt and receipt.offerKey and receipt.offerSeenAfterReload==true,'the still-pending offer is recorded, and marked as first seen after reload')
check(M.Status().spent+M.Status().reserved==1,'exposure is never refunded or doubled')
check(H.Count('take')==0 and H.Count('orb-spend')==1,'recovery never selects and never spends')
check(M.Status().recovery.kind=='OFFER_OPEN','the player is told to choose in the game')
-- A matching ownership snapshot without any observed choice must not settle.
local function resultSnapshot()
 local out=H.Clone(H.granted);local removed=false
 for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
 assert(removed);out['Desired A']={{spellId=410002,quality=2}};return out
end
local kept=H.granted
H.granted=resultSnapshot();H.Notify();A.Poll();H.Advance(.5)
check(M.Status().pending,'ownership delta without an observed choice does not settle')
H.granted=kept;H.Notify();A.Poll();H.Advance(.5)
-- Manual choice in the game, then the exact result.
check(H.service.SelectPerk(410002)==true,'manual native choice');H.Advance(.5)
check(Nexus.Store.State().orbRefinement.pending.choiceObserved,'choice observed passively')
H.granted=resultSnapshot();H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false
H.Notify();A.Poll();H.Advance(.5)
local s=M.Status()
check(not s.pending and s.state=='STOPPED' and s.spent==1 and s.reserved==0,'settled with exact usage')
check(H.Count('orb-spend')==1 and H.Count('take')==1,'no recovery mutation')
print('PASS R2 offer first seen after reload, manual choice, exact settlement checks='..checks)
