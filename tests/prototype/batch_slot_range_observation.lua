-- Group 10c (S1-C4): bounded association observation uses the declared,
-- validated Saved Build range. core/GameAdapter.lua
-- RememberLoadoutWishlistState drops every loadout slot above a literal 5,
-- although the adapter elsewhere uses the declared GetServerMaxSlots range
-- (A.Slots().maxSlots, validated by the reconcile as an integer >= 1). With a
-- declared sixth slot the evidence-pending -> actionable edge is never
-- observed, so the Wishlist presentation revision does not advance.
-- EXPECT (fails at 8c): with six declared slots, the edge in slot 6 advances
-- the presentation revision exactly once.
-- GUARD (holds at 8c): the same edge in slot 5 advances it once; slot 6 with
-- the default five declared slots is not observed, even when the permanent
-- Echo capacity reports 6 (a separate cap, not the slot range); the
-- association becomes actionable in every case; no game action.
-- SETUP: real TOC boot per scenario with an injected store, as the root
-- fixture section1_slot_observation_v2.lua. Whether the live server offers
-- more than five Saved Builds is not claimed.
-- Mismatch path (standards review r1, STD-R1-05): a stored association whose
-- record does not resolve (its stored key names other rows: invalid-schema,
-- with that key) is observed too, and its stored key's live mirror then moves
-- the observation. A semantic slot change records it pending; the locks that
-- complete it are the pending -> actionable edge.
-- EXPECT (fails at 3bc6d88): M6 with six declared slots the edge in slot 6
-- advances the presentation revision once.
-- GUARD (holds at 3bc6d88): M5 the same edge in slot 5 advances it once; MO6
-- slot 6 outside five declared slots is not observed; no game action.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_slot_range_observation')

local function Scenario(label,slot,maxSlots,permanent)
 Nexus=nil;SlashCmdList=nil;NexusDB=nil;WishlistRealizerDB=nil
 local H=dofile('tests/prototype/harness.lua')
 local total,locks={},{}
 for i=1,79 do total[#total+1]={spellId=200000+i,quality=i%4,stacks=1,locked=false} end
 for i=80,85 do
  total[#total+1]={spellId=200000+i,quality=i%4,stacks=1,locked=false}
  locks[#locks+1]={spellId=200000+i,stack=1}
 end
 H.perks.serverActiveSlot=slot
 H.perks.serverBuildSlots[slot]={name='Artificial Saved Build',verified=true,echoes=H.Clone(total)}
 H.perks.serverBuildSlots[101]={name='Artificial native plan',verified=false,echoes=H.Clone(total)}
 ProjectEbonhold.PerkService.GetServerMaxSlots=function() return maxSlots end
 ProjectEbonhold.PerkService.GetMaximumPermanentEchoes=function() return permanent end
 H.locked=nil;H.Boot()
 local A=Nexus.GameAdapter
 local state={loadoutWishlists={[slot]={slot=101,name='Artificial native plan',key=A.WishlistKey(total),echoes=H.Clone(total)}}}
 A.Init({},{State=function() return state end,Settings=function() return {} end})
 local _,status=A.GetLoadoutWishlistState(slot)
 C.setup(status=='evidence-pending',label..': the exact-active association starts evidence-pending',status)
 local before=select(5,A.PresentationRevisions())
 H.locked=H.Clone(locks);H.now=H.now+0.1;A.AutomationSignature()
 local after=select(5,A.PresentationRevisions())
 local _,resolved=A.GetLoadoutWishlistState(slot)
 C.setup(resolved=='actionable',label..': exactly matching locks make it actionable',resolved)
 C.guard(#H.actions==0,label..': the observation makes no game write',#H.actions)
 print('OBSERVED',label,'slot='..slot,'declared='..maxSlots,'revision '..tostring(before)..' -> '..tostring(after))
 return (tonumber(after) or 0)-(tonumber(before) or 0)
end

C.scenario('S5 control',function()
 local delta=Scenario('S5',5,6,6)
 C.guard(delta==1,'S5: the edge in slot 5 advances the presentation revision once',delta)
end)
C.scenario('S6 declared sixth slot',function()
 local delta=Scenario('S6',6,6,6)
 C.expect(delta==1,'S6: the edge in declared slot 6 advances the presentation revision once',delta)
end)
C.scenario('O6 outside the declared range',function()
 local delta=Scenario('O6',6,5,6)
 C.guard(delta==0,'O6: slot 6 outside five declared slots is not observed; permanent capacity is a separate cap',delta)
end)

-- The same world with a stored association that does not resolve: its key
-- names the native plan, its rows are other rows.
local function Mismatch(label,slot,maxSlots)
 Nexus=nil;SlashCmdList=nil;NexusDB=nil;WishlistRealizerDB=nil
 local H=dofile('tests/prototype/harness.lua')
 local total,locks={},{}
 for i=1,79 do total[#total+1]={spellId=200000+i,quality=i%4,stacks=1,locked=false} end
 for i=80,85 do
  total[#total+1]={spellId=200000+i,quality=i%4,stacks=1,locked=false}
  locks[#locks+1]={spellId=200000+i,stack=1}
 end
 H.perks.serverActiveSlot=slot
 H.perks.serverBuildSlots[slot]={name='Artificial Saved Build',verified=true,echoes=H.Clone(total)}
 H.perks.serverBuildSlots[101]={name='Artificial native plan',verified=false,echoes=H.Clone(total)}
 ProjectEbonhold.PerkService.GetServerMaxSlots=function() return maxSlots end
 ProjectEbonhold.PerkService.GetMaximumPermanentEchoes=function() return 6 end
 H.locked=nil;H.Boot()
 local A=Nexus.GameAdapter
 local key=A.WishlistKey(total)
 local other=H.Clone(total);table.remove(other)
 local state={loadoutWishlists={[slot]={slot=101,name='Artificial native plan',key=key,echoes=other}}}
 A.Init({},{State=function() return state end,Settings=function() return {} end})
 local candidate,status,read=A.GetLoadoutWishlistState(slot)
 C.setup(candidate==nil and status=='invalid-schema' and read==key,
  label..': the stored association does not resolve (invalid-schema with its stored key)',status)
 -- A semantic slot change while the native plan still waits for locks.
 H.perks.serverBuildSlots[102]={name='Unrelated plan',verified=false,echoes={{spellId=200010,quality=2,stacks=1}}}
 H.now=H.now+0.1;A.AutomationSignature()
 local before=select(5,A.PresentationRevisions())
 H.locked=H.Clone(locks);H.now=H.now+0.1;A.AutomationSignature()
 local after=select(5,A.PresentationRevisions())
 C.guard(#H.actions==0,label..': the observation makes no game write',#H.actions)
 print('OBSERVED',label,'slot='..slot,'declared='..maxSlots,'revision '..tostring(before)..' -> '..tostring(after))
 return (tonumber(after) or 0)-(tonumber(before) or 0)
end

C.scenario('M5 mismatch control',function()
 local delta=Mismatch('M5',5,6)
 C.guard(delta==1,'M5: the edge in slot 5 on the mismatch path advances the presentation revision once',delta)
end)
C.scenario('M6 mismatch in the declared sixth slot',function()
 local delta=Mismatch('M6',6,6)
 C.expect(delta==1,'M6: the edge in declared slot 6 on the mismatch path advances the presentation revision once',delta)
end)
C.scenario('MO6 mismatch outside the declared range',function()
 local delta=Mismatch('MO6',6,5)
 C.guard(delta==0,'MO6: slot 6 outside five declared slots is not observed on the mismatch path',delta)
end)

C.finish('(bounded observation follows the declared Saved Build range)')
