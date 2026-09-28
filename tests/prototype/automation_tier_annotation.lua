-- Card explanations for quality tiers. Echoes come in quality tiers of one
-- family, each tier its own exact id. The plan asks for exact tiers, and a
-- different tier of the same family is not taken in its place (tier policy,
-- unchanged here). The card explanation, however, said "Not on Wishlist" for
-- such an offer, although the Echo's family IS on the Wishlist, only at
-- another quality. It now says "Different quality from target". Decisions,
-- deltas and actions are unchanged; a card whose family is not wished still
-- says "Not on Wishlist".
--
-- Real runtime and submitted action; the text is the player-facing
-- UserText.Annotation. SYNTHETIC family 'Tiered Blade': T1 q1, T2 q2, T3 q3.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local T1,T2,T3,T3b,Y,F=290101,290102,290103,290104,200002,200020

local function Run(label,spec)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 local H=dofile('tests/prototype/harness.lua');H.pendingRolls=2
 H.AddEcho(T1,'Tiered Blade',1,5,901);H.AddEcho(T2,'Tiered Blade',2,5,901);H.AddEcho(T3,'Tiered Blade',3,5,901)
 -- A second id at the same quality as T3 (a variant, not a quality tier).
 H.AddEcho(T3b,'Tiered Blade',3,5,901)
 H.locked={}
 H.granted={}
 for _,id in ipairs(spec.owned or {}) do H.granted['Tiered Blade']=H.granted['Tiered Blade'] or {};table.insert(H.granted['Tiered Blade'],{spellId=id,quality=H.db[id].quality}) end
 H.Boot()
 local A=Nexus.GameAdapter
 local echoes={}
 for _,id in ipairs(spec.requested) do echoes[#echoes+1]={spellId=id,quality=H.db[id].quality,stacks=1,locked=false} end
 echoes[#echoes+1]={spellId=Y,quality=Y%4,stacks=1,locked=false}
 check(A.SetFirstLoadoutWishlistIdentity('Synthetic Tiers',echoes,{})==true,label..': fixture: plan set')
 H.Board({{spellId=spec.offer,quality=H.db[spec.offer].quality},{spellId=F,quality=0},{spellId=200021,quality=1}})
 H.Notify();H.Advance(.5)
 local a0=#H.actions
 SlashCmdList.NEXUS('auto');H.Advance(1.2)
 local first=H.actions[a0+1]
 local log=Nexus.DiagnosticLogs.Snapshot('decision')
 local cards=(log[#log] or {}).cards or {}
 local text=function(i) return Nexus.UserText.Annotation(cards[i] and cards[i].ann) end
 return {action=first and first[1],ann=cards[1] and cards[1].ann,text=text(1),fillerText=text(2),delta=cards[1] and cards[1].delta}
end

-- 1. The plan asks for T3; the board offers the lower tier T1 of the same
-- family. It is not taken in T3's place, and it is not called "Not on
-- Wishlist" either.
do
 local r=Run('higher-target',{requested={T3},offer=T1})
 check(r.action=='reroll','the lower tier is not taken in place of T3 (tier policy): '..tostring(r.action))
 check(r.delta==-15,'its value is unchanged: '..tostring(r.delta))
 check(r.text=='Different quality from target','the card says the quality differs: '..tostring(r.text))
 check(r.fillerText=='Not on Wishlist','an Echo whose family is not wished still says Not on Wishlist: '..tostring(r.fillerText))
end

-- 2. The plan explicitly asks for the lower tier T1 and needs it: T1 is wanted.
do
 local r=Run('exact-lower',{requested={T1},offer=T1})
 check(r.ann=='wanted' and (r.action=='freeze' or r.action=='take'),'an explicitly requested lower tier is wanted: '..tostring(r.ann))
end

-- 3. Mixed tiers with separate counts: T1 and T3 requested, T1 held.
do
 local r1=Run('mixed-held-tier',{requested={T1,T3},owned={T1},offer=T1})
 check(r1.ann=='target satisfied' and r1.action=='reroll','a held tier is not wanted again: '..tostring(r1.ann))
 local r3=Run('mixed-missing-tier',{requested={T1,T3},owned={T1},offer=T3})
 check(r3.ann=='wanted','the missing tier is wanted: '..tostring(r3.ann))
 local r2=Run('mixed-other-tier',{requested={T1,T3},owned={T1},offer=T2})
 check(r2.action=='reroll' and r2.text=='Different quality from target',
  'a tier between them is neither taken nor called Not on Wishlist: '..tostring(r2.text))
end

-- 4. The plan asks for T1 only and holds it; the board offers the higher T3.
-- A higher tier is not credited for the lower target, and it is not taken.
do
 local r=Run('higher-offer',{requested={T1},owned={T1},offer=T3})
 check(r.action=='reroll' and r.text=='Different quality from target','a higher tier is explained, not taken: '..tostring(r.text))
end

-- 5. A second id of the family at the SAME quality as the requested T3 is
-- not a quality difference: it is not explained as one.
do
 local r=Run('same-quality-variant',{requested={T3},offer=T3b})
 check(r.action=='reroll','the variant is not taken in place of T3: '..tostring(r.action))
 check(r.text~='Different quality from target','and it is not called a different quality: '..tostring(r.text))
end

print('PASS automation_tier_annotation checks='..checks)
