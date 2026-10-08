-- Group 3 supplement (NX-01; root audit question 1): the live permanent
-- capacity is a dynamic positive server value, not a universal six.
-- Native contract (static data, never executed): the SS18 handler takes the
-- capacity only from a positive first field and keeps ONE locked record per
-- Echo with its full stack (perks_service.lua 308-315); the journal's lock gate
-- compares #lockedPerks (records) with GetMaximumPermanentEchoes
-- (echo_journal.lua 4533-4535); the six journal discs are display only.
-- Nexus today sums held copies against six at the current-ownership trust
-- boundary (GameAdapter ReadLockedPerks over_cap), in the Wishlist model
-- projection (MAX_LOCK_SLOTS) and in the Orb read (totalL>6).
-- EXPECT (fails at 8c): with capacity 7, seven single records are trusted
-- (LockedOwned synced, trust view synced/none); the model projection and the
-- AutoLock spell counts accept all seven copies; the actual Orb read is not
-- refused and keeps all seven locked keys. With an unknown capacity (getter
-- 0) the same structurally valid records stay trusted.
-- GUARD (holds at 8c): held copies stay unclamped in bySpell; capacity 6 with
-- the same seven records is refused, also by the Orb read at trust_locked;
-- capacity 7 with eight records is refused; an unknown capacity stays
-- unavailable to actions (MaxPermanentEchoes nil); the authored design-target
-- limit stays six copies whatever the live capacity (seven single targets or
-- one seven-copy target refused, six single targets admitted); no read makes
-- a lock, unlock, choice or spend call.
-- SETUP: real TOC boot with the synthetic Orb/Perk services of orbs_support;
-- capacity comes only from the synthetic GetMaximumPermanentEchoes; the Orb
-- read passes this fixture with six single records (positive control).
-- A trusted record set is a representation verdict only: no claim is made
-- that the server grants a seventh slot, and capacity freshness stays
-- unproven (a zero SS18 header keeps the last positive value).
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_locked_capacity_trust')
local printable=B.printable
local H=dofile('tests/prototype/orbs_support.lua')
local A=H.A;local O=A.Orbs;local R=H.M
H.playerLevel=80;H.O.charges=89
H.perks.serverBuildSlots={[1]={name='Artificial loadout',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}}}
H.perks.serverActiveSlot=1;H.Notify();A.Poll()
C.setup(A.SetLoadoutWishlistIdentity(1,'Artificial Orb target',{{spellId=410002,quality=2,stacks=1}}),
 'an artificial assignment exists')
C.setup(R.UseAssignedWishlist(),'the Orb runtime uses it')
C.setup(A.Owned().synced==true,'ordinary ownership is trusted')
local model=Nexus.WishlistModel.New()
local actions=#H.actions
local capacity=6
ProjectEbonhold.PerkService.GetMaximumPermanentEchoes=function() return capacity end

-- Catalog quality of each synthetic Echo of orbs_support.lua, so every record
-- is an exact catalog key.
local QUALITY={[410001]=1,[410002]=2,[410003]=0,[410004]=3,[410005]=0,[410006]=3,[410007]=2,[410008]=1}
local function Records(ids)
 local t={}
 for i,id in ipairs(ids) do t[i]={spellId=id,stack=1,maxStack=4,quality=QUALITY[id]} end
 return t
end
local SIX={410001,410002,410003,410004,410005,410006}
local SEVEN={410001,410002,410003,410004,410005,410006,410007}
local EIGHT={410001,410002,410003,410004,410005,410006,410007,410008}
local function Copies(bySpell) local n=0;for _,c in pairs(bySpell or {}) do n=n+(tonumber(c) or 0) end;return n end
local function Keys(map) local n=0;for _ in pairs(map or {}) do n=n+1 end;return n end
local function Read(ids)
 H.locked=Records(ids)
 return A.LockedOwned(),A.OwnershipTrustView()
end

C.scenario('P positive control: six single records with capacity 6',function()
 capacity=6
 local l=Read(SIX)
 C.setup(l.synced==true,'P: six single records are trusted at capacity 6')
 local s,e,stage=O.Read()
 C.setup(s~=nil and stage==nil,'P: the actual Orb read passes this fixture',printable(stage)..' '..printable(e))
end)

C.scenario('T7 seven single records with capacity 7',function()
 capacity=7
 local l,t=Read(SEVEN)
 print('OBSERVED','T7 capacity='..printable(A.MaxPermanentEchoes()),'synced='..printable(l.synced),
  'rejection='..printable(t.lockedRejection),'copies='..printable(t.lockedCopies))
 C.setup(A.MaxPermanentEchoes()==7,'T7: the synthetic service reports capacity 7')
 C.expect(l.synced==true,'T7: seven single records at capacity 7 are trusted')
 C.expect(t.lockedSynced==true and t.lockedRejection=='none','T7: the passive trust view says synced/none',t.lockedRejection)
 C.guard(Copies(l.bySpell)==7 and Keys(l.bySpell)==7,'T7: every held copy stays in bySpell (no clamp)',Copies(l.bySpell))
 local p=model.LockedProjection(l,A.Catalog())
 C.expect(p~=nil and p.total==7,'T7: the Wishlist model projection accepts all seven copies',p and p.total)
 local counts=model.LockedSpellCounts(l)
 C.expect(counts~=nil and Keys(counts)==7,'T7: the spell counts used by AutoLock accept all seven',counts and Keys(counts))
 local s,e,stage=O.Read()
 print('OBSERVED','T7 orb read stage='..printable(stage),'error='..printable(e))
 C.expect(s~=nil and stage==nil,'T7: the actual Orb read is not refused (no trust_locked/limits stage)',stage)
 C.expect(s~=nil and Keys(s.locked)==7,'T7: the Orb read keeps all seven locked keys',s and Keys(s.locked))
end)

C.scenario('K6 the same seven records with capacity 6',function()
 capacity=6
 local l=Read(SEVEN)
 C.guard(l.synced==false,'K6: seven records above capacity 6 are refused')
 local s,_,stage=O.Read()
 C.guard(s==nil and stage=='trust_locked','K6: the Orb read refuses at trust_locked',stage)
end)

C.scenario('K8 eight records with capacity 7',function()
 capacity=7
 local l=Read(EIGHT)
 C.guard(l.synced==false,'K8: eight records above capacity 7 are refused')
end)

C.scenario('U7 unknown capacity',function()
 capacity=0
 local l=Read(SEVEN)
 print('OBSERVED','U7 capacity='..printable(A.MaxPermanentEchoes()),'synced='..printable(l.synced))
 C.expect(l.synced==true,'U7: structurally valid records stay trusted while the capacity is unknown')
 C.guard(A.MaxPermanentEchoes()==nil,'U7: the unknown capacity stays unavailable to actions (fails closed)')
 capacity=6
end)

C.scenario('D authored design targets keep the six-copy policy',function()
 capacity=7
 local seven,six={},{}
 for i,id in ipairs(SEVEN) do seven[id]=true;if i<=6 then six[id]=true end end
 C.guard(model.TargetMapEntries(seven,nil)==nil,'D: seven single design targets stay refused at live capacity 7')
 C.guard(model.TargetMapEntries({[410001]={version=1,copies=7,rows={{spellId=410001,stacks=7}}}},nil)==nil,
  'D: one seven-copy design target stays refused')
 local entries,total=model.TargetMapEntries(six,nil)
 C.guard(entries~=nil and total==6,'D: six single design targets are admitted',total)
 capacity=6
end)

H.locked=Records(SIX)
C.guard(#H.actions==actions,'no read made a lock, unlock, choice or spend call',#H.actions-actions)
C.finish('(the live capacity bounds occupied records; unknown capacity is not structural invalidity; design targets stay six)')
