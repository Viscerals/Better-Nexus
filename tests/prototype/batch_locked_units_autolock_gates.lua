-- Group 3 (S1-C1): refusal gates that the occupied-record AutoLock
-- arithmetic must keep. Companion of batch_locked_units_autolock.lua (which
-- holds the EXPECT cases); every check here is a GUARD that holds at 8c and
-- must keep holding after the repair, with the same fixture shape.
-- GUARD: no LockPerk when
--   E capacity 5 is fully occupied by five records (no free slot);
--   F the permanent capacity is unknown (getter 0: unavailable, fails closed);
--   G six records exceed a capacity of 5 (a retained or stale capacity is
--     never turned into a free slot);
--   H an Echo action is still pending (reroll latch), and the same state
--     locks once the latch clears (the latch was the only reason);
--   I the locked records are malformed (trust refused).
-- None of these makes an unlock either.
-- SETUP: as batch_locked_units_autolock.lua: real TOC boot per scenario,
-- real Store owner for the bucket, synthetic services only.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_locked_units_autolock_gates')
local ROLLED={{spellId=200001,quality=1,stacks=1}}
local T=200050

local H,A,K
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
local function NoMutation(label)
 C.guard(Locks()==0,label..': no lock is submitted',Locks())
 C.guard(B.Count(H,'unlock')==0,label..': no unlock is submitted')
end

C.scenario('E full occupancy',function()
 Boot('E',5,Records({1,1,1,1,1}));Step()
 NoMutation('E')
end)
C.scenario('F unknown capacity',function()
 Boot('F',0,Records({1,1,1,1}));Step()
 C.setup(A.MaxPermanentEchoes()==nil,'F: the capacity getter answers 0 (unknown)')
 NoMutation('F')
end)
C.scenario('G records above capacity',function()
 Boot('G',5,Records({1,1,1,1,1,1}));Step()
 NoMutation('G')
end)
C.scenario('H pending Echo action, then cleared',function()
 Boot('H',6,Records({1,1,1,1,1}))
 H.perks.pendingReroll=true
 C.setup(A.InFlight()==true,'H: the reroll latch is an Echo action in flight')
 Step()
 NoMutation('H pending')
 H.perks.pendingReroll=nil
 Step(2)
 C.guard(Locks()==1,'H: once the latch clears the same state locks once (the latch was the only reason)',Locks())
end)
C.scenario('I malformed locked records',function()
 Boot('I',6,{{spellId=200060,stack=1},{spellId=200061,stack=0}});Step()
 C.setup(A.LockedOwned().synced==false,'I: the malformed locked state is refused by the trust boundary')
 NoMutation('I')
end)

C.finish('(no consequential call without a free occupied-record slot and settled, trusted state)')
