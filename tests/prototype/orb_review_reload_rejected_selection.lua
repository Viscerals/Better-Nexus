-- R2 / B2 preservation control (review of main eadff8a). NEW test; not a rerun
-- of an original probe. Real OrbRuntime/OrbAdapter; mocked game services.
--
-- B2: an adapter rejection before SelectPerk cannot establish a choice lifecycle.
-- That must also hold across a reload with the new passive recovery path: the
-- proposed key in the receipt plus a matching ownership snapshot never settles.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan({{spellId=410002,quality=2,stacks=2}});H.Approve(3,false)
H.Offer({{spellId=410002,quality=2},{spellId=410002,quality=1},{spellId=410004,quality=3}})
local receipt=Nexus.Store.State().orbRefinement.pending
check(H.Count('take')==0 and receipt.selectionRefused and receipt.selectedKey and not receipt.choiceMayHaveBeenSent,
 'checkpoint: selection proposed, rejected before SelectPerk')
local source=O.source
H.Fire('PLAYER_LOGOUT')
if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:Hide() end
assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
M=Nexus.OrbRuntime;check(M.Status().state=='RECOVERY','passive recovery');H.Advance(.5)
check(M.Status().recovery.kind=='OFFER_OPEN','the offer is open; no choice evidence exists')
-- A matching ownership snapshot arrives with no SelectPerk call at all.
local out=H.Clone(H.granted);local removed=false
for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
assert(removed);out['Desired A']={{spellId=410002,quality=2}};H.granted=out
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false;H.Notify();A.Poll();H.Advance(.5)
for i=1,3 do H.now=H.now+4;M.Recheck();M.Pump() end
local s=M.Status()
check(s.pending and s.spent+s.reserved==1,'B2 across reload: a proposed key plus an ownership delta is not a choice lifecycle')
check(Nexus.Store.State().orbRefinement.pending~=nil and H.Count('take')==0 and H.Count('orb-spend')==1,'receipt kept; nothing sent')
check(not M.Resume() and not M.Prepare() and M.BlocksOrdinary(),'no resume, no new run, ordinary stays blocked')
print('PASS R2 keeps B2 across reload: rejected selection never becomes proof checks='..checks)
