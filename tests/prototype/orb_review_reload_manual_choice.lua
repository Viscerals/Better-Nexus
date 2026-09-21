-- R2 (review of main eadff8a): passive recovery after reload while the original
-- Orb offer is still open. NEW test written from the review report's R2 text
-- ("record a manual choice after reload when still pending"). It is not a rerun
-- of an original probe. Real OrbRuntime and OrbAdapter; mocked game services.
--
-- The checkpoint holds the observed offer and no selection. After reload the
-- same offer is still pending. The player chooses in the game. Recovery must
-- record that choice passively and settle only on the exact matching result.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan();H.Approve(2,false)
check(M.Stop(),'operator stops before the offer arrives')
H.Offer();check(H.Count('take')==0,'stopped run never selects')
local receipt=Nexus.Store.State().orbRefinement.pending
check(receipt and receipt.offerKey and receipt.spendConfirmed and not receipt.selectionAttempted,
 'checkpoint holds the observed offer, the confirmed spend, and no selection')
local offerKey,source=receipt.offerKey,O.source
H.Fire('PLAYER_LOGOUT')
if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:Hide() end
assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
M=Nexus.OrbRuntime
check(M.Status().state=='RECOVERY' and M.Status().pending,'reload starts passive recovery')
check(not A.Orbs.IsOwned(),'recovery does not acquire Orb action ownership')
local actions=#H.actions
H.Advance(1)
check(#H.actions==actions,'passive observation sends nothing')
local s=M.Status()
check(s.recovery and s.recovery.kind=='OFFER_OPEN' and s.recovery.observing==true,'status reports the open original offer under observation')
check(s.reason:find('game',1,true)~=nil and s.reason:find('will not choose',1,true)~=nil,'instruction: choose in the game; Nexus will not choose')
-- Ownership delta alone, before any observed choice, must not settle.
check(not M.Resume() and not M.Prepare(),'no resume and no new run during recovery')
-- The player chooses in the game's own offer window.
check(H.service.SelectPerk(410002)==true,'manual native choice accepted by the game')
H.Advance(.5)
receipt=Nexus.Store.State().orbRefinement.pending
check(receipt and receipt.choiceObserved and receipt.selectedKey=='410002:2' and receipt.offerKey==offerKey,
 'the manual choice is recorded against the original offer')
check(M.Status().pending and M.Status().spent+M.Status().reserved==1,'choice alone does not settle; exposure retained')
-- The matching result arrives.
local out=H.Clone(H.granted);local removed=false
for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
assert(removed);out['Desired A']={{spellId=410002,quality=2}};H.granted=out
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false;H.Notify();A.Poll()
H.Advance(.5)
s=M.Status()
check(not s.pending and s.state=='STOPPED','observed choice plus exact fresh result settles the earlier action')
check(s.spent==1 and s.reserved==0,'exact usage: one Orb, no refund')
check(H.Count('orb-spend')==1 and H.Count('take')==1,'only the original spend and the one manual choice reached the game')
check(not Nexus.Store.State().orbRefinement.pending,'settled receipt cleared only after confirmation')
check(not M.Resume(),'a settled recovered run never resumes; a new run needs a new review')
check(not M.BlocksOrdinary(),'ordinary actions resume only after the confirmed settlement')
print('PASS R2 manual choice after reload is observed passively and settles on exact evidence checks='..checks)
