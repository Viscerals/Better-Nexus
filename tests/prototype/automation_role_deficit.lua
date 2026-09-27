-- Automation counts a current lock only against the plan's locked targets.
--
-- A plan with explicit roles can ask for an ORDINARY copy of an Echo that the
-- character also holds LOCKED. The HUD (explicit-role progress) lists that
-- ordinary copy as missing. The automation's deficit added every current
-- lock to the ordinary count, so it treated the copy as held, annotated the
-- offered card "target satisfied" and rerolled the board it was on.
--
-- Expected outcomes are written out per case below; no product helper is used
-- as the oracle. Real TOC boot (harness), real association writer, real
-- A.Wishlist/compiler/runtime/EchoWeaver path, real submitted action, real
-- HUD model. SYNTHETIC ids: X=200001, Y=200002 (Y is wanted and never offered,
-- so the plan stays incomplete).
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local X,Y=200001,200002

local function Run(label,spec)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 local H=dofile('tests/prototype/harness.lua');H.pendingRolls=2
 H.locked=spec.locked
 H.granted={}
 if (spec.ordinaryOwned or 0)>0 then
  H.granted[H.names[X]]={}
  for _=1,spec.ordinaryOwned do table.insert(H.granted[H.names[X]],{spellId=X,quality=X%4}) end
 end
 H.Boot()
 local A=Nexus.GameAdapter
 check(A.SetFirstLoadoutWishlistIdentity('Synthetic Deficit',spec.echoes,spec.design)==true,label..': fixture: the plan is set')
 H.Board({{spellId=X,quality=X%4},{spellId=200020,quality=0},{spellId=200021,quality=1}})
 H.Notify();H.Advance(.5)
 Nexus.Panel.Refresh();H.Advance(.5)
 local p=(Nexus.Panel._lastModel or {}).progress or {}
 local hudMissing=table.concat(p.missing or {},' | '):find(H.names[X],1,true)~=nil
 local a0=#H.actions
 SlashCmdList.NEXUS('auto');H.Advance(1.2)
 local first=H.actions[a0+1]
 local log=Nexus.DiagnosticLogs.Snapshot('decision')
 local card=(log[#log] or {}).cards and log[#log].cards[1] or {}
 return {action=first and first[1],index=first and first[2],ann=card.ann,hudMissing=hudMissing,actions=#H.actions-a0,H=H}
end
local function row(id,stacks,locked) local r={spellId=id,quality=id%4,stacks=stacks or 1};if locked~=nil then r.locked=locked end;return r end
local lockX={[X]={version=1,copies=1,rows={{spellId=X,quality=X%4,stacks=1,locked=true,sourceRole='locked'}}}}
local oneLock={{spellId=X,stacks=1}}
local function Kept(r) return r.action=='freeze' or r.action=='take' end

-- 1. Explicit ordinary X is requested; one X is locked and no ordinary X is
-- held. The ordinary copy is still needed: the offered X is wanted and kept,
-- and the HUD agrees.
do
 local r=Run('ordinary-only',{echoes={row(X,1,false),row(Y,1,false)},design={},locked=oneLock})
 check(r.hudMissing,'fixture: the HUD lists the ordinary X as missing')
 check(r.ann=='wanted','the offered X is wanted, not "target satisfied": '..tostring(r.ann))
 check(Kept(r),'and it is kept on the board, not rerolled away: '..tostring(r.action))
end

-- 2. Ordinary X and a locked target X; one X is locked. The lock satisfies
-- only the locked target; the ordinary X is still needed.
do
 local r=Run('ordinary-and-locked',{echoes={row(X,1,false),row(Y,1,false)},design=lockX,locked=oneLock})
 check(r.hudMissing,'fixture: the HUD lists the ordinary X as missing')
 check(r.ann=='wanted' and Kept(r),'the ordinary X is still wanted: '..tostring(r.ann)..' / '..tostring(r.action))
end

-- 3. A locked target X only, and X is already locked: no ordinary deficit.
do
 local r=Run('locked-only',{echoes={row(Y,1,false)},design=lockX,locked=oneLock})
 check(not r.hudMissing,'fixture: nothing of X is missing in the HUD')
 check(r.ann=='target satisfied','the offered X is not wanted: '..tostring(r.ann))
 check(r.action=='reroll','and the board is searched further: '..tostring(r.action))
end

-- 4. Enough ordinary copies satisfy the ordinary target, whatever the locks.
do
 local r=Run('ordinary-held',{echoes={row(X,1,false),row(Y,1,false)},design={},locked=oneLock,ordinaryOwned=1})
 check(not r.hudMissing,'fixture: the ordinary X is held')
 check(r.ann=='target satisfied' and r.action=='reroll','an X already held ordinarily is not wanted again: '..tostring(r.ann))
end

-- 5. Two ordinary copies requested, one held ordinarily, one X locked: one
-- ordinary copy is still needed (stacks count; the lock is not a copy).
do
 local r=Run('ordinary-stacks',{echoes={row(X,2,false),row(Y,1,false)},design={},locked=oneLock,ordinaryOwned=1})
 check(r.ann=='wanted' and Kept(r),'the second ordinary copy is still wanted: '..tostring(r.ann))
end

-- 6. A locked target X that is not locked yet, with one rolled X held: that
-- copy is the one Auto-Lock will lock. It is not ALSO an ordinary copy, and no
-- further X is needed (the lock acquisition is preserved, not doubled).
do
 local r=Run('future-lock',{echoes={row(Y,1,false)},design=lockX,locked={},ordinaryOwned=1})
 check(r.ann=='target satisfied' and r.action=='reroll','the held rolled X serves the locked target: '..tostring(r.ann))
end
do
 local r=Run('future-lock-and-ordinary',{echoes={row(X,1,false),row(Y,1,false)},design=lockX,locked={},ordinaryOwned=1})
 check(r.ann=='wanted' and Kept(r),'with an ordinary X requested too, one more X is still needed: '..tostring(r.ann))
end

-- 7. Legacy untyped plan (no roles known): the established reading stays, a
-- current lock counts for it.
do
 local r=Run('untyped',{echoes={row(X,1,nil),row(Y,1,nil)},design=nil,locked=oneLock})
 check(not r.hudMissing,'fixture: the untyped HUD credits the lock')
 check(r.ann=='target satisfied' and r.action=='reroll','and so does automation, as before: '..tostring(r.ann))
end

-- 8. Locked ownership not known yet: no decision is made on a guess.
do
 local r=Run('locks-unknown',{echoes={row(X,1,false),row(Y,1,false)},design={},locked=nil})
 check(r.actions==0,'nothing is submitted while current locks are unknown: '..r.actions)
end

print('PASS automation_role_deficit checks='..checks)
