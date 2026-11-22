-- Review findings F7 and N2 on range eadff8a..578c77e. NEW test written from the
-- independent review's reproductions. Text and classification only. Real
-- OrbRuntime/OrbAdapter/GameAdapter; mocked game services; no native evidence.
--
-- F7: a restored receipt holds a proposed key that was refused before
-- SelectPerk. The instruction must say that only that same Echo can be
-- confirmed. After a different choice the text must not say "Resolve it
-- manually", because nothing can resolve it.
-- N2: for a restored receipt the blocked reasons of the real mutators must not
-- say "owns the current action" or "Stop and settle". They must say what the
-- conditional exit is: the player's explicit Continue (035) applies only to its
-- bounded class, not every restored record. (Before
-- 035 they said that no exit exists and that a settlement path is only a proposal.)
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan({{spellId=410002,quality=2,stacks=2}});H.Approve(3,false)
H.Offer({{spellId=410002,quality=2},{spellId=410002,quality=1},{spellId=410004,quality=3}})
local receipt=Nexus.Store.State().orbRefinement.pending
check(receipt.selectionRefused and receipt.selectedKey=='410002:2' and not receipt.choiceMayHaveBeenSent,'checkpoint: proposed key refused before SelectPerk')
local source=O.source
H.Fire('PLAYER_LOGOUT')
if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
M=Nexus.OrbRuntime;check(M.Status().state=='RECOVERY','passive recovery');H.Advance(.5)
local s=M.Status()
check(s.reason:find('Desired A',1,true)~=nil,'the instruction names the proposed Echo: '..s.reason)
check(s.reason:find('only if you choose that same Echo',1,true)~=nil,'the instruction limits what can be confirmed')
check(s.reason:find('different Echo',1,true)~=nil and s.reason:find('Continue is available only after a reload',1,true)~=nil
 and s.reason:find('client-observed spend',1,true)~=nil and s.reason:find('no usable recorded choice and no open offer',1,true)~=nil
 and s.reason:find('/nexus orbs',1,true)~=nil and not s.reason:find('only exit',1,true),
 'the instruction states the different-choice consequence and conditional Continue eligibility')
check(s.recovery.kind=='OFFER_OPEN' and s.recovery.proposed==true,'open offer with a proposed key')
-- While the action can still progress, the blocked reasons say so.
local function reasons()
 local out={}
 out.take=select(2,A.Take(410002));out.reroll=select(2,A.Reroll());out.banish=select(2,A.Banish(1));out.freeze=select(2,A.Freeze(1))
 out.lock=select(2,A.LockPerk(410001));out.unlock=select(2,A.UnlockPerk(410001));out.save=select(2,A.Save(1,'x'))
 out.activate=select(2,A.Activate(1));out.upload=select(2,A.UploadWishlist(0,'x',{{spellId=410002,quality=2,stacks=1}}))
 return out
end
local n=#H.actions
for name,why in pairs(reasons())do
 check(type(why)=='string' and why:find('only observes',1,true)~=nil,name..': progress block reason: '..tostring(why))
 check(not why:find('owns the current action',1,true) and not why:find('Stop and settle',1,true),name..': no false instruction')
end
check(#H.actions==n,'every mutator stayed blocked')
-- The player chooses a different Echo than the proposal.
check(H.service.SelectPerk(410004)==true,'manual choice of another Echo');H.Advance(.5)
s=M.Status()
check(s.pending and s.state=='PAUSED','the action pauses unresolved')
check(not s.reason:find('Resolve it manually',1,true),'the text does not tell the player to resolve what cannot be resolved')
check(s.reason:find('cannot confirm',1,true)~=nil and s.reason:find('kept',1,true)~=nil
 and s.reason:find('Continue is available only after a reload',1,true)~=nil
 and s.reason:find('client-observed spend',1,true)~=nil and s.reason:find('no usable recorded choice and no open offer',1,true)~=nil
 and not s.reason:find('only exit',1,true) and not s.reason:find('only a proposal',1,true),
 'the text states: cannot confirm, record kept, Continue is conditional')
local out=H.Clone(H.granted);local removed=false
for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
assert(removed);out['Desired B']={{spellId=410004,quality=3}};H.granted=out
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false;H.Notify();A.Poll();H.Advance(.5)
for i=1,3 do H.now=H.now+4;M.Recheck();M.Pump() end
s=M.Status()
check(s.pending and s.spent+s.reserved==1 and Nexus.Store.State().orbRefinement.pending~=nil,'classification unchanged: still unresolved, exposure and receipt kept')
n=#H.actions
-- EXPECT semantic replacement (2026-11-19, user decision on the 9106 field
-- report): saved history from an earlier session never blocks an actionable
-- ordinary pick while the live Orb service shows no offer. The ordinary-roll
-- mutators (Take, Reroll, Banish, Freeze) are therefore admitted here; every
-- other mutator keeps its truthful refusal below. The ordinary-roll mutators
-- act or refuse exactly as without the receipt (here no choice is open; a
-- Reroll needs none). The attribution guard of a Take with an open choice is
-- in orb_restored_ordinary_release.
local rolling={take=true,reroll=true,banish=true,freeze=true}
local savedBefore=H.Clone(Nexus.Store.State().orbRefinement.pending)
check(M.BlocksOrdinaryRolling()==false and A.OrdinaryBoardAllowed()==true,'ordinary rolling is not blocked by the restored receipt')
for name,why in pairs(reasons())do
 if rolling[name] then
  check(why==nil or (type(why)=='string' and not why:find('cannot be confirmed',1,true) and not why:find('Orb',1,true)),name..': not blocked by the receipt: '..tostring(why))
 else
  check(type(why)=='string' and why:find('cannot be confirmed',1,true)~=nil and why:find('Continue in /nexus orbs',1,true)~=nil
   and why:find('does not clear it by itself',1,true)~=nil and not why:find('only a proposal',1,true),name..': block reason names the exit: '..tostring(why))
  check(not why:find('owns the current action',1,true) and not why:find('Stop and settle',1,true),name..': no false instruction')
 end
end
check(H.Count('orb-spend')==1,'no Orb was spent')
local savedAfter=Nexus.Store.State().orbRefinement.pending
local same=savedAfter~=nil
for k,v in pairs(savedBefore) do if type(v)~='table' and savedAfter[k]~=v then same=false end end
check(same and M.Status().pending,'the receipt is kept unchanged: nothing is attributed to it')
check(M.BlocksOrdinary() and not M.Resume() and not M.Prepare(),'the loadout, lock and upload block and the Resume and Start refusals are unchanged')
for name,call in pairs({Prepare=function()return M.Prepare()end,UseAssignedWishlist=function()return M.UseAssignedWishlist()end,SuggestSources=function()return M.SuggestSources()end})do
 local ok,refusal=call()
 check(not ok and type(refusal)=='string' and refusal:find('Continue in /nexus orbs',1,true)~=nil
  and not refusal:find('settle it',1,true) and not refusal:find('Stop and settle',1,true),name..': refusal names the only exit: '..tostring(refusal))
end
local allowed,why=A.Activate(1)
check(allowed~=true and Nexus.UserText.Message(why)==why,'the visible blocked reason is the same truthful sentence')
-- Missing retained spend history is outside Continue, not proof the client
-- never observed it or the server spent nothing. Opening the explanation sends
-- nothing and every mutator remains blocked for this class too.
local R=dofile('tests/prototype/orb_recovery_support.lua');local S=R.S
local HU,MU,AU,OU=R.Class({latch=false,edit=function(row,state)row.spendConfirmed=false;state.spendConfirmed=false end})
OU.charges=OU.charges-2;S.Pass(HU,MU,AU,1)
local vu=MU.ContinueView();local su=MU.Status()
check(su.recovery.kind=='UNOBSERVABLE' and vu.reason=='spend_unconfirmed' and not vu.eligible,'missing retained history is not Continue class')
check(su.reason:find('no retained observation',1,true) and su.reason:find('does not prove that the server spent nothing',1,true)
 and not su.reason:find('never observed',1,true) and not su.reason:find('only exit',1,true),'missing history stays unknown with no universal exit promise')
local base=HU.Clone(R.Saved());local actions=#HU.actions;local sends=#HU.sent;local reqs=OU.requests
Nexus.OrbPanel.Show();Nexus.OrbPanel.Refresh();NexusOrbPanel.cont:Click()
check(not NexusOrbContinue.check:IsEnabled() and not NexusOrbContinue.go:IsEnabled(),'explanation does not enable a check or consent')
-- EXPECT semantic replacement (2026-11-19, user-authorized 9101 lockout fix ce49e85b): this class has its
-- offer recorded and no recorded choice, so ordinary rolling (Take, Reroll, Banish, Freeze through the
-- ordinary-board gate) is no longer blocked by it. Every other mutator below keeps its refusal unchanged.
check(MU.BlocksOrdinaryRolling()==false and AU.OrdinaryBoardAllowed()==true and MU.BlocksOrdinary(),
 'ordinary-board gate permits; the loadout, lock and upload block is kept')
for name,call in pairs({lock=function()return AU.LockPerk(410001)end,
 unlock=function()return AU.UnlockPerk(410001)end,save=function()return AU.Save(1,'x')end,activate=function()return AU.Activate(1)end,
 upload=function()return AU.UploadWishlist(0,'x',{{spellId=410002,quality=2,stacks=1}})end})do
 local ok,refusal=call();check(not ok and type(refusal)=='string',name..': missing history still blocks mutation')
 check(refusal:find('this record retains an observation',1,true) and refusal:find('no offer is open',1,true)
  and refusal:find('check passes',1,true) and not refusal:find('if this client observed',1,true)
  and not refusal:find('only exit',1,true),name..': refusal conditions Continue on retained evidence and a passing check')
end
check(#HU.actions==actions and #HU.sent==sends and OU.requests==reqs and R.Same(R.Saved(),base),
 'explanation and refused mutators make no action/request/receipt changes')
check(MU.Status().pending and MU.Status().spent==su.spent and MU.Status().reserved==su.reserved and su.reserved==1 and MU.BlocksOrdinary()
 and not MU.Resume() and not MU.Prepare(),'original unobserved spending exposure and block retained')
print('PASS F7/N2 instructions and blocked reasons state what the code can and cannot do checks='..checks)
