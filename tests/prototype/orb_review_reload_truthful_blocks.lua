-- Review findings F7 and N2 on range eadff8a..578c77e. NEW test written from the
-- independent review's reproductions. Text and classification only. Real
-- OrbRuntime/OrbAdapter/GameAdapter; mocked game services; no native evidence.
--
-- F7: a restored receipt holds a proposed key that was refused before
-- SelectPerk. The instruction must say that only that same Echo can be
-- confirmed. After a different choice the text must not say "Resolve it
-- manually", because nothing can resolve it.
-- N2: for a restored receipt the blocked reasons of the real mutators must not
-- say "owns the current action" or "Stop and settle". They must say that no
-- exit exists yet and that the settlement path is only a proposal.
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
check(s.reason:find('different Echo',1,true)~=nil and s.reason:find('No exit',1,true)~=nil,'the instruction states the consequence of a different choice')
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
check(s.reason:find('cannot confirm',1,true)~=nil and s.reason:find('kept',1,true)~=nil and s.reason:find('No exit',1,true)~=nil
 and s.reason:find('only a proposal',1,true)~=nil,'the text states: cannot confirm, record kept, no exit yet, settlement is only a proposal')
local out=H.Clone(H.granted);local removed=false
for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
assert(removed);out['Desired B']={{spellId=410004,quality=3}};H.granted=out
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false;H.Notify();A.Poll();H.Advance(.5)
for i=1,3 do H.now=H.now+4;M.Recheck();M.Pump() end
s=M.Status()
check(s.pending and s.spent+s.reserved==1 and Nexus.Store.State().orbRefinement.pending~=nil,'classification unchanged: still unresolved, exposure and receipt kept')
n=#H.actions
for name,why in pairs(reasons())do
 check(type(why)=='string' and why:find('cannot be confirmed',1,true)~=nil and why:find('no way to clear this block yet',1,true)~=nil
  and why:find('only a proposal',1,true)~=nil,name..': no-exit block reason: '..tostring(why))
 check(not why:find('owns the current action',1,true) and not why:find('Stop and settle',1,true),name..': no false instruction')
end
check(#H.actions==n and M.BlocksOrdinary() and not M.Resume() and not M.Prepare(),'the block itself is unchanged')
for name,call in pairs({Prepare=function()return M.Prepare()end,UseAssignedWishlist=function()return M.UseAssignedWishlist()end,SuggestSources=function()return M.SuggestSources()end})do
 local ok,refusal=call()
 check(not ok and type(refusal)=='string' and refusal:find('no way to clear this block yet',1,true)~=nil
  and not refusal:find('settle it',1,true) and not refusal:find('Stop and settle',1,true),name..': refusal states that no exit exists: '..tostring(refusal))
end
local allowed,why=A.OrdinaryBoardAllowed()
check(allowed==false and Nexus.UserText.Message(why)==why,'the visible ordinary reason is the same truthful sentence')
print('PASS F7/N2 instructions and blocked reasons state what the code can and cannot do checks='..checks)
