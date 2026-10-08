-- R2 control (review of main eadff8a). NEW test written from the report's R2
-- requirement that recovery instructions match what the code can observe. Not a
-- rerun of an original probe. Real OrbRuntime/OrbAdapter; mocked game services.
--
-- When the client cannot supply the choice observation (no hooksecurefunc), the
-- text must say so, and a manual choice plus a matching ownership delta must
-- still not settle the earlier action.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan();H.Approve(2,false);check(M.Stop(),'stop before the offer');H.Offer()
local source=O.source
check(Nexus.Store.State().orbRefinement.pending.offerKey~=nil,'checkpoint holds the observed offer')
H.Fire('PLAYER_LOGOUT')
if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:Hide() end
hooksecurefunc=nil
assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
M=Nexus.OrbRuntime;check(M.Status().state=='RECOVERY','passive recovery');H.Advance(.5)
local s=M.Status()
check(s.recovery.kind=='OFFER_OPEN' and s.recovery.observing==false,'open offer, observation unavailable')
check(s.reason:find('cannot observe',1,true)~=nil and s.reason:find('kept',1,true)~=nil,'text: cannot observe a manual choice; record kept')
check(not s.reason:find('will record',1,true),'text does not promise to record the choice')
check(H.service.SelectPerk(410002)==true,'manual native choice');H.Advance(.5)
local out=H.Clone(H.granted);local removed=false
for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
assert(removed);out['Desired A']={{spellId=410002,quality=2}};H.granted=out
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false;H.Notify();A.Poll();H.Advance(.5)
for i=1,3 do H.now=H.now+4;M.Recheck();M.Pump() end
s=M.Status()
check(s.pending and s.spent+s.reserved==1 and Nexus.Store.State().orbRefinement.pending~=nil,'unobserved choice never settles; receipt and exposure kept')
check(s.recovery.kind=='UNOBSERVABLE' and s.reason:find('cannot confirm',1,true)~=nil,'text: the earlier action cannot be confirmed')
check(H.Count('orb-spend')==1 and H.Count('take')==1 and not M.Resume() and not M.Prepare(),'no recovery mutation, no resume, no new run')
print('PASS R2 no choice observer: truthful text and no settlement checks='..checks)
