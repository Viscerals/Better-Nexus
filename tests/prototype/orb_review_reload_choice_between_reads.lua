-- R2 control (review of main eadff8a). NEW test; not a rerun of an original
-- probe. Real OrbRuntime/OrbAdapter; mocked game services; no native evidence.
--
-- The manual choice and its result can both arrive between two recovery reads.
-- The choice that the observer recorded on the matched offer is still consumed,
-- and only the exact result settles the action.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan();H.Approve(2,false);check(M.Stop(),'stop before the offer');H.Offer()
local source=O.source
H.Fire('PLAYER_LOGOUT')
if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:Hide() end
assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
M=Nexus.OrbRuntime;check(M.Status().state=='RECOVERY','passive recovery');H.Advance(.5)
check(M.Status().recovery.kind=='OFFER_OPEN' and M.Status().recovery.observing,'matched open offer under observation')
-- Choice and result with no recovery read in between.
check(H.service.SelectPerk(410002)==true,'manual native choice')
local out=H.Clone(H.granted);local removed=false
for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
assert(removed);out['Desired A']={{spellId=410002,quality=2}};H.granted=out
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false;H.Notify();A.Poll()
H.Advance(.5)
local s=M.Status()
check(not s.pending and s.state=='STOPPED' and s.spent==1 and s.reserved==0,'observed choice is consumed after the offer closed; exact result settles')
check(H.Count('orb-spend')==1 and H.Count('take')==1,'no recovery mutation')
print('PASS R2 choice and result between two recovery reads checks='..checks)
