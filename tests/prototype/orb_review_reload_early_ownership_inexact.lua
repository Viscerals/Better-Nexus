-- Review finding F3, negative control. NEW test written from the
-- independent review's reproduction (early-ownership order after a reload). Real
-- OrbRuntime/OrbAdapter; mocked game services; no native evidence.
--
-- The player chooses on the matched offer. The exact result ownership arrives
-- before the next recovery read, while the game still flags the offer as
-- pending. The observed choice must not be discarded. Settlement stays as
-- strict as before: it still needs the closed offer and the exact fresh result.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan();H.Approve(2,false);check(M.Stop(),'stop before the offer');H.Offer()
local source=O.source
H.Fire('PLAYER_LOGOUT')
if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
M=Nexus.OrbRuntime;check(M.Status().state=='RECOVERY','passive recovery');H.Advance(.5)
check(M.Status().recovery.kind=='OFFER_OPEN' and M.Status().recovery.observing,'matched offer under observation')
local function result(id,q,name)
 local out=H.Clone(H.granted);local removed=false
 for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
 assert(removed);out[name]=out[name] or {};table.insert(out[name],{spellId=id,quality=q});return out
end
-- Between two recovery reads: the choice, then early exact ownership. The offer
-- flag and the board are still up.
-- The event-driven pump is suppressed here (as when it cannot run), so the next
-- timed read alone meets: recorded observer choice + early ownership + open flag.
local realPump=M.Pump;M.Pump=function()end
check(H.service.SelectPerk(410002)==true,'manual native choice')
M.Pump=realPump
local wrong=result(410002,2,'Desired A');table.insert(wrong['Desired A'],{spellId=410004,quality=3})
H.granted=wrong;H.Notify();A.Poll()
H.Advance(.5)
local receipt=Nexus.Store.State().orbRefinement.pending
check(receipt and not receipt.choiceObserved and not receipt.selectionAttempted,'ownership that is not the exact single gain: the choice is not consumed')
check(M.Status().recovery.kind=='OFFER_UNMATCHED','classified as unmatched')
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false;H.Notify();A.Poll();H.Advance(.5)
for i=1,3 do H.now=H.now+4;M.Recheck();M.Pump() end
local s=M.Status()
check(s.pending and s.spent+s.reserved==1 and Nexus.Store.State().orbRefinement.pending~=nil,'never settles; receipt and exposure kept')
check(H.Count('orb-spend')==1 and H.Count('take')==1 and not M.Resume() and not M.Prepare(),'no recovery mutation, no resume, no new run')
print('PASS F3 negative: inexact early ownership is still fail-closed checks='..checks)
