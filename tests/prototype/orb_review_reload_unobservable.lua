-- R2 (review of main eadff8a), report scenario F5: a legitimate checkpoint from
-- before selection is restored after a reload. The operation was then finished
-- in the game while Nexus could not observe it. This is a NEW test written from
-- the report's stated scenario. It is not a rerun of the review's original probe.
-- Real OrbRuntime and OrbAdapter; mocked game services; no native evidence.
--
-- Expected: the action stays unresolved (fail closed). The ownership delta alone
-- is never accepted. The receipt, the exposure and the blocks stay. The visible
-- instruction must not promise that "manually finish + Recheck" can settle it.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan();H.Approve(2,false)
check(H.Count('orb-spend')==1 and H.Count('take')==0 and M.Status().pending,'one spend submitted; no offer and no selection yet')
local receipt=Nexus.Store.State().orbRefinement.pending
check(receipt and receipt.removed and not receipt.offerKey and not receipt.selectionAttempted,'checkpoint is from before offer and selection')
local source=O.source
H.Fire('PLAYER_LOGOUT')
if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:Hide() end
assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
M=Nexus.OrbRuntime
check(M.Status().state=='RECOVERY' and M.Status().pending and not M.Status().running,'reload starts passive recovery')
-- The player finished the operation in the game while nothing observed it:
-- one Orb spent, the source replaced by the wanted Echo, no pending offer.
O.charges=O.charges-1;O.offer=false
local out=H.Clone(H.granted);local removed=false
for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
assert(removed);out['Desired A']={{spellId=410002,quality=2}};H.granted=out
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;H.Notify();A.Poll()
local actions=#H.actions
for i=1,4 do H.now=H.now+4;check(M.Recheck(),'Recheck '..i..' accepted');M.Pump();H.Notify();A.Poll() end
H.Advance(3)
local s=M.Status()
check(s.pending,'ownership delta alone never settles the earlier action')
check(s.spent+s.reserved==1,'unresolved spending exposure is retained')
check(Nexus.Store.State().orbRefinement.pending~=nil,'pending receipt is not erased')
check(#H.actions==actions and H.Count('orb-spend')==1 and H.Count('take')==0,'recovery sent no spend and no selection')
check(not M.Resume() and not M.Prepare() and M.BlocksOrdinary(),'no resume, no new run, ordinary actions stay blocked')
M.Stop();check(M.Status().pending and M.BlocksOrdinary(),'Stop keeps the record and the block')
H.now=H.now+4;M.Recheck();M.Pump();s=M.Status()
-- Truthful instruction: the code cannot observe this history any more.
check(not s.reason:find('then Recheck',1,true),'the text does not promise that a manual finish plus Recheck settles it')
check(s.reason:find('cannot confirm',1,true)~=nil,'the text says that the earlier action cannot be confirmed')
check(s.reason:find('kept',1,true)~=nil,'the text says that the record and exposure are kept')
check(type(s.recovery)=='table' and s.recovery.kind=='UNOBSERVABLE','status reports the unobservable-history recovery kind')
print('PASS R2 unobservable history stays unresolved with truthful instructions checks='..checks)
