-- Group 3 (S1-C1): AutoLock capacity arithmetic in occupied records.
-- Native contract (static data, never executed): the lock gate compares the
-- number of locked RECORDS to GetMaximumPermanentEchoes (echo_journal.lua
-- 4533-4535); LockPerk(spellId) sends the spellId only and a locked record
-- keeps its full stack (perks_service.lua 308-315). One lock therefore
-- occupies one record slot, whatever its copies. core/AutomationRuntime.lua
-- (TryAutoLock) compares held copies plus the target's copy deficit with the
-- capacity instead, and the copy-based trust boundary hides stacked records.
-- EXPECT (fails at 8c): exactly one LockPerk of the owned target when
--   A capacity 6, five records holding 1,1,1,3,1 copies (5+1 <= 6);
--   B capacity 5, four records holding 1,1,3,1 copies (4+1 <= 5);
--   C capacity 5, four single records, target of 2 owned copies (4+1 <= 5).
-- GUARD (holds at 8c): D capacity 6, five single records locks once (positive
-- control of this fixture); every lock passes exactly one argument (the
-- spellId) to the native LockPerk; the submitted attempt is held as
-- awaiting-confirmation, never as confirmed, and is not resubmitted; no
-- unlock.
-- SETUP: real TOC boot per scenario, real Store owner for the locked-target
-- bucket (the legacy sidecar path of auto_lock_absent_empty_bucket.lua),
-- synthetic capacity/locked/granted services. Refusal gates are in
-- batch_locked_units_autolock_gates.lua. No live server confirmation claim.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_locked_units_autolock')
local printable=B.printable
local ROLLED={{spellId=200001,quality=1,stacks=1}}
local T=200050

local H,A,K,lockArgs
local function Records(stacks)
 local t={}
 for i,s in ipairs(stacks) do t[i]={spellId=200059+i,stack=s} end
 return t
end
local function Boot(label,capacity,locked,ownedCopies,target)
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
 local copies={}
 for i=1,ownedCopies do copies[i]={spellId=T,quality=(T-200000)%4} end
 granted['Echo 50']=copies
 H.granted=granted
 SlashCmdList.NEXUS('reroll off');SlashCmdList.NEXUS('freeze off');SlashCmdList.NEXUS('banish off')
 H.Notify();H.Advance(1)
 SlashCmdList.NEXUS('auto');H.Advance(2)
 C.setup(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(state)
  state.lockDesignTargetsBySlot=state.lockDesignTargetsBySlot or {}
  state.lockDesignTargetsBySlot[K]=target
 end),label..': the locked-target bucket is written through the store owner')
 C.setup(A.LockedOwned().bySpell~=nil,label..': the locked records are readable')
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

C.scenario('A capacity 6, five records 1,1,1,3,1',function()
 Boot('A',6,Records({1,1,1,3,1}),1,{[T]=true})
 Step()
 print('OBSERVED','A locks='..Locks(),'attempts='..AttemptStates())
 C.expect(Locks()==1,'A: one lock is submitted (five occupied records + one <= capacity 6)',Locks())
 Lifecycle('A')
end)

C.scenario('B capacity 5, four records 1,1,3,1',function()
 Boot('B',5,Records({1,1,3,1}),1,{[T]=true})
 C.setup(A.LockedOwned().synced==true,'B: six held copies are trusted at 8c too (the arithmetic, not trust, is under test)')
 Step()
 print('OBSERVED','B locks='..Locks(),'attempts='..AttemptStates())
 C.expect(Locks()==1,'B: one lock is submitted (four occupied records + one <= capacity 5)',Locks())
 Lifecycle('B')
end)

C.scenario('C capacity 5, four single records, two-copy target',function()
 Boot('C',5,Records({1,1,1,1}),2,{[T]={version=1,copies=2,rows={{spellId=T,stacks=2}}}})
 Step()
 print('OBSERVED','C locks='..Locks(),'attempts='..AttemptStates())
 C.expect(Locks()==1,'C: one lock is submitted; a two-copy target needs one record slot, not two',Locks())
 Lifecycle('C')
end)

C.scenario('D positive control: capacity 6, five single records',function()
 Boot('D',6,Records({1,1,1,1,1}),1,{[T]=true})
 Step()
 C.guard(Locks()==1,'D: this fixture locks an owned target into a free slot',Locks())
 Lifecycle('D')
end)

C.finish('(AutoLock counts occupied records; one native spellId call; submission is not confirmation)')
