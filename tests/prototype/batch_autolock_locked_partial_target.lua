-- Group 3 supplement: an AutoLock target that asks for more copies of a spell
-- that is ALREADY locked.
-- Native contract (static data, never executed): LockPerk sends the spellId
-- only and its count is ignored (perks_service.lua 802-811, EBH-Q21); the
-- journal's TryLockEcho refuses an Echo that is already locked
-- (echo_journal.lua 4532: `button.isLocked` returns) and one locked record
-- keeps the full stack it was locked with (perks_service.lua 308-315). A
-- second LockPerk of a locked spell therefore cannot add copies to its record.
-- core/AutomationRuntime.lua TryAutoLock treats a locked spell below its
-- target copies as "not locked" and submits LockPerk(spellId) for the copy
-- deficit (isLocked = lockedBySpell[id] >= copies; neededCopies).
-- EXPECT (fails at 8c): with spell T locked as one record of 1 copy, a target
-- of 2 copies of T, 2 owned copies of T and free capacity, no LockPerk is
-- submitted, no attempt is held as awaiting-confirmation, and repeated
-- evaluations submit none either.
-- GUARD (holds at 8c): the same target with T not locked yet locks T once
-- (one argument, awaiting-confirmation, not resubmitted); T locked as one
-- record holding the 2 target copies makes no LockPerk; no unlock anywhere.
-- The pending, authority, trust and capacity refusal gates are covered,
-- unchanged, by batch_locked_units_autolock_gates.lua.
-- SETUP: real TOC boot per scenario, real Store owner for the counted target
-- (the shape batch_locked_units_autolock.lua scenario C writes), synthetic
-- services only. A submission is never confirmation.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_autolock_locked_partial_target')
local printable=B.printable
local ROLLED={{spellId=200001,quality=1,stacks=1}}
local T=200050
local TARGET={[T]={version=1,copies=2,rows={{spellId=T,stacks=2}}}}

local H,A,K,lockArgs
local function Boot(label,locked)
 Nexus=nil;SlashCmdList=nil;NexusDB=nil;WishlistRealizerDB=nil
 H=dofile('tests/prototype/harness.lua');H.pendingRolls=40;H.playerLevel=30
 H.locked=locked
 H.Boot()
 A=Nexus.GameAdapter
 ProjectEbonhold.PerkService.GetMaximumPermanentEchoes=function() return 6 end
 lockArgs={}
 local nativeLock=ProjectEbonhold.PerkService.LockPerk
 ProjectEbonhold.PerkService.LockPerk=function(...)
  lockArgs[#lockArgs+1]=select('#',...)
  return nativeLock(...)
 end
 C.setup(A.SetFirstLoadoutWishlistIdentity('Synthetic AutoLock plan',ROLLED),label..': a Wishlist with no design of its own')
 K=A.WishlistKey(ROLLED)
 Nexus.Store.Settings().autoLockEchoes=true
 local granted=H.Clone(H.granted or {})
 granted['Echo 50']={{spellId=T,quality=(T-200000)%4},{spellId=T,quality=(T-200000)%4}}
 H.granted=granted
 SlashCmdList.NEXUS('reroll off');SlashCmdList.NEXUS('freeze off');SlashCmdList.NEXUS('banish off')
 H.Notify();H.Advance(1)
 SlashCmdList.NEXUS('auto');H.Advance(2)
 C.setup(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(state)
  state.lockDesignTargetsBySlot=state.lockDesignTargetsBySlot or {}
  state.lockDesignTargetsBySlot[K]=H.Clone(TARGET)
 end),label..': the counted two-copy target is written through the store owner')
 local l=A.LockedOwned()
 C.setup(l.synced==true,label..': the locked records are trusted')
 C.setup(A.Owned().bySpell[T]==2,label..': two copies of the target spell are owned',A.Owned().bySpell[T])
end
local function Step(seconds) Nexus.RequestRecompute();H.Advance(seconds or 1.5) end
local function Locks() return B.Count(H,'lock') end
local function AttemptStates()
 local out={}
 Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(state)
  local attempts=state.autoLockAttempts
  for _,record in pairs(type(attempts)=='table' and type(attempts.records)=='table' and attempts.records or {}) do
   out[#out+1]=tostring(record.state)
  end
 end)
 table.sort(out)
 return table.concat(out,',')
end

C.scenario('L target spell already locked with 1 of 2 copies',function()
 Boot('L',{{spellId=T,stack=1},{spellId=200061,stack=1},{spellId=200062,stack=1}})
 Step()
 local first,states=Locks(),AttemptStates()
 Step(4)
 print('OBSERVED','L locks='..first..' then '..Locks(),'attempts='..printable(states),'lock arguments='..table.concat(lockArgs,','))
 C.expect(first==0 and states:find('awaiting',1,true)==nil,
  'L: no LockPerk is submitted for the already-locked spell, and nothing waits for a confirmation',first..' '..states)
 C.expect(Locks()==0,'L: repeated evaluations submit no LockPerk either',Locks())
 C.guard(B.Count(H,'unlock')==0,'L: no unlock')
end)

C.scenario('N positive control: target spell not locked yet',function()
 Boot('N',{{spellId=200061,stack=1},{spellId=200062,stack=1},{spellId=200063,stack=1}})
 Step()
 C.guard(Locks()==1 and H.actions[#H.actions][2]==T,'N: the unlocked target spell is locked once',Locks())
 C.guard(#lockArgs==1 and lockArgs[1]==1,'N: the native LockPerk receives exactly one argument (the spellId)',table.concat(lockArgs,','))
 C.guard(AttemptStates()=='awaiting-confirmation','N: the submitted lock is held as awaiting-confirmation, not confirmed',AttemptStates())
 Step(4)
 C.guard(Locks()==1,'N: the awaiting attempt is not resubmitted',Locks())
 C.guard(B.Count(H,'unlock')==0,'N: no unlock')
end)

C.scenario('F target spell locked with both target copies',function()
 Boot('F',{{spellId=T,stack=2},{spellId=200061,stack=1},{spellId=200062,stack=1}})
 Step()
 C.guard(Locks()==0,'F: a fulfilled target makes no LockPerk',Locks())
 C.guard(B.Count(H,'unlock')==0,'F: no unlock')
end)

C.finish('(no LockPerk can add copies to an already-locked spell; ordinary locking unchanged)')
