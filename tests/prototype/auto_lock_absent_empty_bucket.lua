-- Absent versus empty locked-target bucket in the automatic lock step.
--
-- W4 stopped creating an empty `lockDesignTargetsBySlot[<key>]` bucket when an
-- ordinary-only Wishlist is opened or saved. For a Wishlist without its own
-- design (legacy sidecar path) the lock step reads that bucket: a MISSING one
-- returns before any bookkeeping ("table missing"); an EMPTY one (what older
-- builds left behind) runs the step with zero targets, which supersedes every
-- stored attempt record. Neither reaches LockPerk or UnlockPerk without targets.
-- This test pins the transition with real runtime, real Store and counted
-- adapter sends. Scope: the offline harness only; no native confirmation.
local checks=0
local function check(ok,msg) checks=checks+1; assert(ok,msg) end
local W,L1,L2=200001,200050,200051
local ROLLED={{spellId=W,quality=1,stacks=1}}
local NAME='Synthetic ordinary-only plan'

local H,A,K
local function boot(design)
 Nexus=nil;SlashCmdList=nil;NexusDB=nil;WishlistRealizerDB=nil
 H=dofile('tests/prototype/harness.lua');H.pendingRolls=40;H.playerLevel=30;H.Boot()
 A=Nexus.GameAdapter
 ProjectEbonhold.PerkService.GetMaximumPermanentEchoes=function() return 6 end
 if design==nil then
  check(A.SetFirstLoadoutWishlistIdentity(NAME,ROLLED),'fixture: a Wishlist with no design of its own')
 else
  check(A.SetFirstLoadoutWishlistIdentity(NAME,ROLLED,design),'fixture: a Wishlist with an explicit design')
 end
 K=A.WishlistKey(ROLLED)
 Nexus.Store.Settings().autoLockEchoes=true
 local granted=H.Clone(H.granted or {})
 granted['Echo 50']={{spellId=L1,quality=2}}
 granted['Echo 51']={{spellId=L2,quality=2}}
 H.granted=granted
 SlashCmdList.NEXUS('reroll off');SlashCmdList.NEXUS('freeze off');SlashCmdList.NEXUS('banish off')
 H.Notify();H.Advance(1)
 SlashCmdList.NEXUS('auto');H.Advance(2)
end
local function bucket(value)
 check(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(state)
  state.lockDesignTargetsBySlot=state.lockDesignTargetsBySlot or {}
  state.lockDesignTargetsBySlot[K]=value
 end),'fixture: the sidecar bucket is written through the store owner')
end
local function step(seconds) Nexus.RequestRecompute();H.Advance(seconds or 1.5) end
local function sends()
 local n=0
 for _,action in ipairs(H.actions) do if action[1]=='lock' or action[1]=='unlock' then n=n+1 end end
 return n
end
local function records()
 -- Read through the store owner: the live table, not a cached snapshot.
 local out,count={},0
 Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(state)
  local attempts=state.autoLockAttempts
  if type(attempts)=='table' and type(attempts.records)=='table' then
   for key,record in pairs(attempts.records) do
    local copy={}
    for field,value in pairs(record) do copy[field]=value end
    out[key]=copy;count=count+1
   end
  end
 end)
 return out,count
end
local function only()
 local out,count=records()
 check(count==1,'exactly one attempt record: '..count)
 local _,record=next(out)
 return {state=record.state,identity=record.identity,preparedAt=record.preparedAt,
  expiresAt=record.expiresAt,adapterAttempts=record.adapterAttempts,spellId=record.spellId}
end
local function same(a,b)
 return a.state==b.state and a.identity==b.identity and a.preparedAt==b.preparedAt
  and a.expiresAt==b.expiresAt and a.adapterAttempts==b.adapterAttempts and a.spellId==b.spellId
end

-- 1. Target -> missing bucket -> same target. One send, ever; the record is kept as it was.
boot()
step()
check(sends()==0 and select(2,records())==0,'no bucket, no targets: no send, no record')
bucket({[L1]=true});step()
check(sends()==1 and H.actions[#H.actions][1]=='lock' and H.actions[#H.actions][2]==L1,'the designed target is locked once')
local first=only()
check(first.state=='awaiting-confirmation' and first.spellId==L1,'its attempt awaits confirmation: '..tostring(first.state))
bucket(nil);step()
check(sends()==1,'a missing bucket sends nothing')
check(same(first,only()),'and leaves the pending attempt record exactly as it was')
bucket({[L1]=true});step(4)
check(sends()==1,'the same target back does not send a duplicate while its attempt is pending')
check(same(first,only()),'and the record keeps its identity and lifetime')
check(H.actions[#H.actions][1]~='unlock','no unlock was sent at any point')

-- 2. A different target after the missing bucket supersedes the record of the old one.
boot()
bucket({[L1]=true});step()
check(sends()==1,'fixture: first target locked')
bucket(nil);step()
bucket({[L2]=true});step(4)
local second=only()
check(second.spellId==L2,'the record now belongs to the new target')
check(sends()==2 and H.actions[#H.actions][2]==L2,'and the new target is locked once')

-- 3. The empty bucket older builds left behind: same inputs, the historical result.
boot()
bucket({[L1]=true});step()
check(sends()==1,'fixture: first target locked')
bucket({});step()
check(sends()==1,'an empty bucket sends nothing')
check(select(2,records())==0,'but clears every stored attempt record')
bucket({[L1]=true});step(4)
check(sends()==2,'so the same target returning sends again while the first attempt was unresolved: '..sends())

-- 4. An explicit empty design on the assignment keeps the empty-table behavior as well.
boot({})
bucket({[L1]=true})
step()
check(sends()==0,'an assignment that carries an empty design sends nothing, whatever the sidecar holds')
check(select(2,records())==0,'and keeps no record')

print('PASS auto_lock_absent_empty_bucket: '..checks..' checks (missing vs empty bucket, same/different target, explicit empty design, counted sends)')
