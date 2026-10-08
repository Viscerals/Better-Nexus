-- Group 3 (S1-C1, NX-01): occupied locked records versus held copies at the
-- current-ownership trust boundary and its direct consumers.
-- Native contract (static data, never executed): SS18 keeps ONE locked record
-- per Echo with its full `stack` (perks_service.lua 308-315); the journal's
-- lock gate compares #lockedPerks (records) to GetMaximumPermanentEchoes
-- (echo_journal.lua 4533-4535); LockPerk sends the spellId only.
-- Nexus today sums held copies and refuses above six (GameAdapter
-- ReadLockedPerks over_cap; Model.LockedProjection; OrbAdapter totalL>6), so
-- five records holding 1,1,1,3,1 copies poison seven-copy ownership.
-- EXPECT (fails at 8c): five records 1,1,1,3,1 (capacity 6, 5 and unknown)
-- are trusted (LockedOwned synced, trust view synced/none); the Wishlist
-- model projection and spell counts accept them with every copy (410005 x3,
-- 7 copies); the Orb read is not refused at trust_locked or limits and keeps
-- 410005:0 = 3; a refusal above six records names records/slots, not copies.
-- GUARD (holds at 8c): six single records trusted; seven records refused,
-- also when two share a spellId (records are not deduplicated); duplicate
-- records sum their copies; malformed counts (0, -1, 1.5, text, NaN, inf),
-- an absurd single stack (1e6), a conflicting alias, a cycle and depth stay
-- refused; held copies stay unclamped in bySpell; unknown capacity stays
-- unavailable to actions; no consequential call is made by any read.
-- SETUP: real TOC boot with the synthetic Orb/Perk services of orbs_support;
-- capacity comes only from the synthetic GetMaximumPermanentEchoes.
-- A record's own maxStack (standards review r1, STD-R1-03): the native SS18
-- parser stores `stack` and `maxStack` independently (perks_service.lua
-- 300-314) and whether the server holds one to the other is unknown
-- (EBH-Q05), so a stated maxStack is data, not a trust bound.
-- EXPECT (fails at 3bc6d88): X a record holding 2 copies that states
-- maxStack 1, at capacity 6, is trusted with both copies (trust view, model
-- projection in one record, Orb read).
-- GUARD (holds at 3bc6d88): X121 a 121-copy record stays refused although it
-- states maxStack 200 (the 120-copy row ceiling); X7 the same 2-copy record as
-- a seventh record at capacity 6 stays refused (capacity).
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_locked_units_trust')
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

local function Record(id,stack,quality) return {spellId=id,stack=stack,maxStack=4,quality=quality or 0} end
local FIVE={Record(410001,1,1),Record(410003,1,0),Record(410004,1,3),Record(410005,3,0),Record(410007,1,2)}
local function Copies(bySpell) local n=0;for _,c in pairs(bySpell or {}) do n=n+(tonumber(c) or 0) end;return n end
local function Read(records)
 H.locked=H.Clone(records)
 local l=A.LockedOwned();local t=A.OwnershipTrustView()
 return l,t
end

C.scenario('S5 five records 1,1,1,3,1 with capacity 6',function()
 capacity=6
 local l,t=Read(FIVE)
 print('OBSERVED','S5 synced='..printable(l.synced),'rejection='..printable(t.lockedRejection),'copies='..printable(t.lockedCopies))
 C.expect(l.synced==true,'S5: five occupied records holding seven copies are trusted')
 C.expect(t.lockedSynced==true and t.lockedRejection=='none','S5: the passive trust view says synced/none',t.lockedRejection)
 C.guard(l.bySpell[410005]==3 and Copies(l.bySpell)==7,'S5: every held copy stays in bySpell (no clamp)',Copies(l.bySpell))
 C.guard(t.lockedCopies==7,'S5: the trust view keeps the seven held copies',t.lockedCopies)
 local p=model.LockedProjection(l,A.Catalog())
 C.expect(p~=nil and p.bySpell[410005]==3 and p.total==7,
  'S5: the Wishlist model projection accepts the records with every copy',p and p.total)
 local counts=model.LockedSpellCounts(l)
 C.expect(counts~=nil and counts[410005]==3,'S5: the spell counts used by AutoLock accept them',counts and counts[410005])
 local s,e,stage=O.Read()
 print('OBSERVED','S5 orb read stage='..printable(stage),'error='..printable(e))
 C.expect(s~=nil and stage==nil,'S5: the actual Orb read is not refused (no trust_locked/limits stage)',stage)
 C.expect(s~=nil and s.locked and s.locked['410005:0']==3,'S5: the Orb read keeps the three stacked copies',
  s and s.locked and s.locked['410005:0'])
end)

C.scenario('F5 full occupancy: five records with capacity 5',function()
 capacity=5
 local l=Read(FIVE)
 C.expect(l.synced==true,'F5: five records at capacity 5 are trusted (full occupancy is not over capacity)')
 local s,_,stage=O.Read()
 C.expect(s~=nil,'F5: the Orb read is not refused',stage)
end)

C.scenario('U5 unknown capacity',function()
 capacity=0
 local l=Read(FIVE)
 C.expect(l.synced==true,'U5: trust of the records does not depend on a retained capacity value')
 C.guard(A.MaxPermanentEchoes()==nil,'U5: unknown capacity stays unavailable for actions (fails closed)')
 capacity=6
end)

C.scenario('K controls: six single records, seven records',function()
 local six={Record(410001,1,1),Record(410003,1,0),Record(410004,1,3),Record(410005,1,0),Record(410007,1,2),Record(410008,1,1)}
 local l=Read(six)
 C.guard(l.synced==true,'K6: six single-copy records are trusted')
 local seven=H.Clone(six);seven[7]=Record(410002,1,2)
 l=Read(seven)
 C.guard(l.synced==false,'K7: seven records are refused')
 local s,e,stage=O.Read()
 C.guard(s==nil and stage=='trust_locked','K7: the Orb read refuses at trust_locked',stage)
 print('OBSERVED','K7 refusal text='..printable(e))
 local text=tostring(e or ''):lower()
 C.expect(text:find('locked copies',1,true)==nil and (text:find('record',1,true)~=nil or text:find('slot',1,true)~=nil),
  'K7: the refusal names the limit in occupied records/slots, not copies',e)
end)

C.scenario('D duplicate records are kept as records',function()
 local dup={Record(410001,1,1),Record(410001,1,1),Record(410003,1,0),Record(410004,1,3),Record(410005,1,0),Record(410007,1,2)}
 local l=Read(dup)
 C.guard(l.synced==true and l.bySpell[410001]==2,'D6: two records of one spell sum their copies; six records trusted',l.bySpell[410001])
 local dup7=H.Clone(dup);dup7[7]=Record(410008,1,1)
 l=Read(dup7)
 C.guard(l.synced==false,'D7: seven records with six distinct spells stay refused (records are not deduplicated)')
end)

C.scenario('M malformed counts and shapes',function()
 local cases={{'zero',0},{'negative',-1},{'fraction',1.5},{'text','x'},{'nan',0/0},{'infinite',math.huge},{'absurd',1000000}}
 for _,case in ipairs(cases) do
  local l=Read({Record(410001,1,1),{spellId=410003,stack=case[2],maxStack=4,quality=0}})
  C.guard(l.synced==false,'M: a '..case[1]..' stack stays refused',case[1])
 end
 local l=Read({{spellId=410001,id=410003,stack=1}})
 C.guard(l.synced==false,'M: a conflicting id alias stays refused')
 local cyc={spellId=410001,stack=1};cyc.child={spellId=410003,stack=1,back=nil};cyc.child.back=cyc
 H.locked={cyc};l=A.LockedOwned()
 C.guard(l.synced==false,'M: a cycle stays refused')
 local deep={};local node=deep
 for _=1,10 do node.next={};node=node.next end
 node.spellId,node.stack=410001,1
 H.locked={deep};l=A.LockedOwned()
 C.guard(l.synced==false,'M: nesting deeper than eight stays refused')
end)

C.scenario('X a record above its own stated maxStack',function()
 capacity=6
 local over={spellId=410005,stack=2,maxStack=1,quality=0}
 local l,t=Read({Record(410001,1,1),over})
 print('OBSERVED','X synced='..printable(l.synced),'rejection='..printable(t.lockedRejection),'copies='..printable(t.lockedCopies))
 C.expect(l.synced==true and t.lockedSynced==true and t.lockedRejection=='none',
  'X: a record holding 2 copies that states maxStack 1 is trusted',t.lockedRejection)
 C.expect(l.bySpell[410005]==2 and Copies(l.bySpell)==3 and t.lockedCopies==3,
  'X: both copies of that record are kept',Copies(l.bySpell))
 local p=model.LockedProjection(l,A.Catalog())
 C.expect(p~=nil and p.bySpell[410005]==2 and p.recordsBySpell[410005]==1 and p.occupied==2,
  'X: the model projection keeps them in one occupied record',p and p.occupied)
 local s,_,stage=O.Read()
 C.expect(s~=nil and stage==nil and s.locked and s.locked['410005:0']==2,'X: the Orb read keeps the two copies',stage)
 l=Read({Record(410001,1,1),{spellId=410005,stack=121,maxStack=200,quality=0}})
 C.guard(l.synced==false,'X121: a 121-copy record stays refused although it states maxStack 200 (row ceiling)')
 local seven={Record(410001,1,1),Record(410002,1,2),Record(410003,1,0),Record(410004,1,3),Record(410007,1,2),Record(410008,1,1),over}
 l=Read(seven)
 C.guard(l.synced==false,'X7: the same record as a seventh record at capacity 6 stays refused (capacity)')
end)

H.locked=H.Clone(FIVE)
C.guard(#H.actions==actions,'no read made a lock, unlock, choice or spend call',#H.actions-actions)
C.finish('(occupied records bound trust; held copies preserved; defenses unchanged)')
