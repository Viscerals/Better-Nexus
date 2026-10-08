-- Group 3 supplement (NX-01; root audit questions 1 and 2): AutoLock against a
-- dynamic live capacity and against the native record partition.
-- Native contract (static data, never executed): the lock gate compares the
-- number of locked RECORDS with GetMaximumPermanentEchoes, a dynamic positive
-- server value (echo_journal.lua 4533-4535; perks_service.lua SS18); the six
-- journal discs are display only. One lock occupies one record slot.
-- core/AutomationRuntime.lua TryAutoLock adds copy deficits to held copies
-- (LockedSpellCounts) and keys its locked token on the aggregate bySpell map;
-- core/GameAdapter.lua LockedFingerprint is the same aggregate, so a new record
-- partition with equal per-spell copies is not seen as a change.
-- EXPECT (fails at 8c):
--   C7b capacity 7, five records holding 1,1,1,3,1: one LockPerk (5+1 <= 7);
--   PS  capacity 3, two records holding 2 and 1 (same copies as three
--       records): one LockPerk (2+1 <= 3);
--   PA  capacity 3: three single records (two of one spell) fill every slot;
--       the game then reports the SAME per-spell copies as two records (A x2,
--       B x1) in fresh tables, announced by its data notification only (no
--       forced recompute): AutoLock reacts and submits one LockPerk.
-- GUARD (holds at 8c): capacity 7 with six single records locks once (the
-- seventh live slot is usable: no universal six-record cap); capacity 7 with
-- seven records, capacity 6 with seven records, an unknown capacity with seven
-- records, and PA's first state (three records at capacity 3, only two
-- distinct spells: no distinct-spell occupancy) make no LockPerk; every lock
-- passes exactly one argument (the spellId); a submitted lock is held as
-- awaiting-confirmation and not resubmitted; no unlock anywhere.
-- SETUP: real TOC boot per scenario, real Store owner for the locked-target
-- bucket (as batch_locked_units_autolock.lua), synthetic services only.
-- A submission is never confirmation; no server capacity claim is made.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_locked_capacity_autolock')
local printable=B.printable
local ROLLED={{spellId=200001,quality=1,stacks=1}}
local T=200050

local H,A,K,lockArgs
local function Records(stacks)
 local t={}
 for i,s in ipairs(stacks) do t[i]={spellId=200059+i,stack=s} end
 return t
end
local function Boot(label,capacity,locked)
 Nexus=nil;SlashCmdList=nil;NexusDB=nil;WishlistRealizerDB=nil
 H=dofile('tests/prototype/harness.lua');H.pendingRolls=40;H.playerLevel=30
 H.locked=locked
 H.Boot()
 A=Nexus.GameAdapter
 ProjectEbonhold.PerkService.GetMaximumPermanentEchoes=function() return capacity end
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
 granted['Echo 50']={{spellId=T,quality=(T-200000)%4}}
 H.granted=granted
 SlashCmdList.NEXUS('reroll off');SlashCmdList.NEXUS('freeze off');SlashCmdList.NEXUS('banish off')
 H.Notify();H.Advance(1)
 SlashCmdList.NEXUS('auto');H.Advance(2)
 C.setup(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(state)
  state.lockDesignTargetsBySlot=state.lockDesignTargetsBySlot or {}
  state.lockDesignTargetsBySlot[K]={[T]=true}
 end),label..': the locked-target bucket is written through the store owner')
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
local function Lifecycle(label)
 C.guard(#lockArgs==Locks() and (lockArgs[1]==nil or lockArgs[1]==1),
  label..': the native LockPerk receives exactly one argument (the spellId)',table.concat(lockArgs,','))
 if Locks()>0 then
  C.guard(H.actions[#H.actions][1]=='lock' and H.actions[#H.actions][2]==T,label..': the lock names the target spell')
  C.guard(AttemptStates()=='awaiting-confirmation',label..': the submitted lock is held as awaiting-confirmation, not confirmed',AttemptStates())
  local before=Locks()
  Step(4)
  C.guard(Locks()==before,label..': the awaiting attempt is not resubmitted',Locks())
 end
 C.guard(B.Count(H,'unlock')==0,label..': no unlock')
end
local function Observe(label)
 local l=A.LockedOwned()
 print('OBSERVED',label,'locks='..Locks(),'capacity='..printable(A.MaxPermanentEchoes()),
  'synced='..printable(l.synced),'attempts='..AttemptStates())
end

C.scenario('C7a capacity 7, six single records',function()
 Boot('C7a',7,Records({1,1,1,1,1,1}))
 Step();Observe('C7a')
 C.guard(Locks()==1,'C7a: the seventh live slot is used: one lock (no universal six-record cap)',Locks())
 Lifecycle('C7a')
end)

C.scenario('C7b capacity 7, five records 1,1,1,3,1',function()
 Boot('C7b',7,Records({1,1,1,3,1}))
 Step();Observe('C7b')
 C.expect(Locks()==1,'C7b: one lock is submitted (five occupied records + one <= capacity 7)',Locks())
 Lifecycle('C7b')
end)

C.scenario('C7c capacity 7, seven single records',function()
 Boot('C7c',7,Records({1,1,1,1,1,1,1}))
 Step();Observe('C7c')
 C.guard(Locks()==0,'C7c: seven records fill capacity 7: no lock',Locks())
 C.guard(B.Count(H,'unlock')==0,'C7c: no unlock')
end)

C.scenario('K6 capacity 6, seven single records',function()
 Boot('K6',6,Records({1,1,1,1,1,1,1}))
 Step();Observe('K6')
 C.guard(Locks()==0,'K6: seven records above capacity 6: no lock',Locks())
 C.guard(B.Count(H,'unlock')==0,'K6: no unlock')
end)

C.scenario('U7 unknown capacity, seven single records',function()
 Boot('U7',0,Records({1,1,1,1,1,1,1}))
 C.setup(A.MaxPermanentEchoes()==nil,'U7: the capacity getter answers 0 (unknown)')
 Step();Observe('U7')
 C.guard(Locks()==0,'U7: an unknown capacity is unavailable to actions: no lock',Locks())
 C.guard(B.Count(H,'unlock')==0,'U7: no unlock')
end)

-- Two partitions of the same per-spell copies {200060 x2, 200061 x1}.
local function ThreeRecords() return {{spellId=200060,stack=1},{spellId=200060,stack=1},{spellId=200061,stack=1}} end
local function TwoRecords() return {{spellId=200060,stack=2},{spellId=200061,stack=1}} end

C.scenario('PS capacity 3, two records holding 2 and 1',function()
 Boot('PS',3,TwoRecords())
 Step();Observe('PS')
 C.expect(Locks()==1,'PS: one lock is submitted (two occupied records + one <= capacity 3)',Locks())
 Lifecycle('PS')
end)

C.scenario('PA capacity 3, the record partition changes with equal copies',function()
 Boot('PA',3,ThreeRecords())
 Step();Observe('PA three records')
 C.guard(Locks()==0,'PA: three records (two distinct spells) fill capacity 3: no lock, no distinct-spell occupancy',Locks())
 local before=A.LockedOwned().bySpell
 H.locked=TwoRecords()
 local after=A.LockedOwned().bySpell
 C.setup(before[200060]==2 and before[200061]==1 and after[200060]==2 and after[200061]==1,
  'PA: both partitions hold the same per-spell copies')
 H.Notify();H.Advance(3)
 Observe('PA two records')
 C.expect(Locks()==1,'PA: after the game reports two records, AutoLock reacts with one lock (no forced recompute)',Locks())
 Lifecycle('PA')
end)

C.finish('(AutoLock uses the live record capacity and reacts to a new record partition; refusals unchanged)')
