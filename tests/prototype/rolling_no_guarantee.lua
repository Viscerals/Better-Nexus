-- Current-game contract: there are no guaranteed future Echo rolls.
-- Real pure modules in production TOC order through the maintained adapter.
local P=dofile('tests/prototype/policy_adapter.lua')
P.Load()
assert(table.concat(P.order,','):find('WishlistPilot.lua,logic\\OrbPolicy.lua,logic\\Policy.lua',1,true),'WishlistPilot loads before Policy, as in the TOC')
local catalog=P.Catalog({f1={[0]=1001,[1]=1011},f2={[0]=1002},f3={[0]=1003},f4={[0]=1004}})
local plan=P.Plan(catalog,{{spellId=1001,stacks=1},{spellId=1002,stacks=1}})
local saved={verified=true,echoes={{spellId=1001,family='f1',quality=0,stacks=1}}}
local unsaved={verified=false,echoes=saved.echoes}
local search={trustworthy=true,banish=1,freeze=1,reroll=0}
local function Base(extra)
 local input={catalog=catalog,plan=plan,horizon=2,charges=search,allowFreeze=true,allowBanish=true,
  cards={{spellId=1001},{spellId=1002},{spellId=1003}}}
 for k,v in pairs(extra or {})do input[k]=v end
 return input
end

-- 1. Dispatch and useful progress. A targetless Wait is not adapter success.
local action=P.Decide(Base({activeRow=unsaved}))
assert(action.planner=='pilot103' and action.type~='wait' and plan.requestedCounts[action.spellId]==1,'ordinary Wishlist board reaches the intended planner and acts on a requested Echo')
local reference=P.Line(action)
assert(reference=='freeze|1001|1|pilot103|Freeze wanted Echo before search (Pilot)','exact diagnostic fixture decision: '..reference)
print('PASS real TOC-order dispatch makes useful progress: '..reference)

-- 2. Metadata invariance: only saved verification, old flags or a stale
-- prefilled queue change. Ownership, board, resources and horizon are fixed.
local stale={entries={{spellId=1001,family='f1',wanted=true,quality=0},{spellId=1002,family='f2',wanted=true,quality=0}}}
local oldFlags={DISABLE_SUPPRESSES_GUARANTEE=true,REROLL_HOLDS_GUARANTEED=true}
local variants={
 {'verified saved row',{activeRow=saved}},
 {'verified flag forced true',{activeRow=saved,forceVerifiedFlag=true}},
 {'verified flag forced false',{activeRow=saved,forceVerifiedFlag=false}},
 {'old truthy guarantee flags',{activeRow=saved,forceVerifiedFlag=true,flags=oldFlags}},
 {'stale prefilled queue',{activeRow=saved,forceVerifiedFlag=true,flags=oldFlags,prefilledQueue=stale}},
 {'test.9020 runtime preparation',{activeRow=saved,runtime='test9020',flags=oldFlags}},
}
for _,variant in ipairs(variants)do
 local got,state=P.Decide(Base(variant[2]))
 assert(P.Line(got)==reference,variant[1]..' changed the ordinary board decision: '..P.Line(got))
 for i=1,3 do assert(got.annotations[i]~='returns later','no card is said to return: '..variant[1])end
 if variant[2].runtime=='test9020' then assert(#state.queue.entries==0,'even the old runtime preparation obtains no inferred queue')end
end
print('PASS decision is invariant under saved verification, old flags, and a stale prefilled queue')

-- 3. No inferred future offer and no estimate from the old queue.
local owned=P.Owned(catalog,{})
local queue=Nexus.Ratchet.PredictQueue(saved.echoes,owned,plan,oldFlags,{},catalog)
assert(type(queue.entries)=='table' and #queue.entries==0 and queue.inferred==false,'valid saved contents infer no future offer')
local plain=Nexus.Ratchet.RunsEstimate(plan,owned,nil,nil,catalog)
local withStale=Nexus.Ratchet.RunsEstimate(plan,owned,stale,nil,catalog)
assert(plain.text==withStale.text and plain.unknown==true,'estimate ignores any supplied queue')
assert(plain.text:find('2 wishlist echoes pending',1,true) and not plain.text:lower():find('guaranteed',1,true) and not plain.text:find('queue',1,true),'estimate reports known deficits only: '..plain.text)
local historical=Nexus.Ratchet.HistoricalGuaranteeQueue(saved.echoes,owned,plan,{}, {},catalog)
assert(#historical.entries==1,'historical fixture stays available under its explicit name only')
print('PASS no inferred queue; estimate: '..plain.text)

-- 4. Exact quality and requested copies; no double count of permanent copies.
local copies=P.Plan(catalog,{{spellId=1001,stacks=2},{spellId=1002,stacks=1}})
local function Copies(ownedBySpell,lockedBySpell,cards)
 return P.Decide({catalog=catalog,plan=copies,horizon=10,cards=cards or {{spellId=1001},{spellId=1003},{spellId=1004}},
  owned=P.Owned(catalog,ownedBySpell),locked=P.Owned(catalog,lockedBySpell),activeRow=saved})
end
local one=Copies({[1001]=1},{})
assert(one.type=='take' and one.spellId==1001 and one.outstanding==2,'one rolled copy of two leaves one copy and the other target outstanding')
local both=Copies({[1001]=1},{[1001]=1})
assert(both.outstanding==1 and both.annotations[1]=='target satisfied' and both.reasonCode~='SELECT_OUTSTANDING_WISHLIST','one rolled plus one permanent copy satisfies exactly two; the card is no longer a wanted Echo')
local doubled=Copies({[1001]=2},{[1001]=2})
assert(doubled.outstanding==1,'surplus copies never reduce another target')
local sibling=Copies({[1011]=2},{},{{spellId=1011},{spellId=1003},{spellId=1004}})
assert(sibling.outstanding==3 and sibling.annotations[1]=='filler','a different-quality sibling neither satisfies nor counts as the requested exact Echo')
print('PASS exact copies and quality; rolled and permanent ownership each subtract once')

-- 5. Observed board state is kept; it is not an inferred future roll.
local held=P.Decide(Base({activeRow=saved,cards={{spellId=1001,isFrozen=true},{spellId=1002},{spellId=1003}}}))
assert(held.annotations[1]=='frozen' and held.type=='take' and held.spellId==1002,'an observed held wanted offer is protected while the other wanted Echo is taken')
local marked=P.Decide(Base({activeRow=saved,cards={{spellId=1003,isGuaranteed=true},{spellId=1004},{spellId=1004}},horizon=2}))
assert(marked.annotations[1]=='guaranteed' and not (marked.type=='banish' and marked.index==1) and not (marked.type=='freeze' and marked.index==1),'a server-marked current offer is never banished or frozen')
print('PASS observed Freeze and guaranteed-offer flags are respected')

-- 6. Safe refusals are retained for verified rows too.
local function Refusal(label,extra,expected)
 local got=P.Decide(Base(extra))
 assert(got.type=='wait' and got.reason==expected,label..': '..P.Line(got))
end
Refusal('pending transaction',{activeRow=saved,pending=true},'waiting for action confirmation')
Refusal('pending action',{activeRow=saved,pendingAction={type='freeze'}},'waiting for action confirmation')
Refusal('unsynchronized ownership',{activeRow=saved,owned=P.Owned(catalog,{},false)},'unsynced')
Refusal('unreadable locked state',{activeRow=saved,locked=P.Owned(catalog,{},false)},'waiting for locked Echo state')
Refusal('invalid horizon',{activeRow=saved,horizon=false},'waiting for pending-pick count')
Refusal('Orb state',{activeRow=saved,ordinaryBoardAllowed=false},'Orb state active or unknown')
Refusal('incomplete board',{activeRow=saved,cards={{spellId=1001},{spellId=1002}}},'waiting for three-card board')
local advisor=P.Decide({catalog=catalog,plan={advisorOnly=true},horizon=2,cards=Base().cards,activeRow=saved})
assert(advisor.type=='wait' and advisor.reason=='assign a Wishlist','missing targets refuse instead of acting')
print('PASS incomplete-state refusals are unchanged by saved verification')

-- 7. Resource limits and permissions.
local function Resource(label,extra,forbidden)
 local got=P.Decide(Base(extra))
 assert(got.type~=forbidden and got.type=='take' and plan.requestedCounts[got.spellId],label..': '..P.Line(got))
end
Resource('no Freeze charge',{activeRow=saved,charges={trustworthy=true,banish=1,freeze=0,reroll=0}},'freeze')
Resource('Freeze disabled',{activeRow=saved,allowFreeze=false},'freeze')
Resource('untrusted charges',{activeRow=saved,charges={trustworthy=false,banish=9,freeze=9,reroll=9}},'freeze')
local noSearch=P.Decide(Base({activeRow=saved,cards={{spellId=1003},{spellId=1004},{spellId=1004}},charges={trustworthy=true,banish=0,freeze=0,reroll=0}}))
assert(noSearch.type=='take' and noSearch.reasonCode=='RESOURCE_EXHAUSTED_FALLBACK','zero resources never produce a Banish or Reroll')
local noReroll=P.Decide(Base({activeRow=saved,cards={{spellId=1003},{spellId=1004},{spellId=1004}},charges={trustworthy=true,banish=0,freeze=0,reroll=5},allowReroll=false}))
assert(noReroll.type~='reroll','a disabled Reroll preference is never overridden')
print('PASS resource limits and disabled actions are respected')

-- 8. Determinism for repeated identical inputs.
local lines={}
for round=1,3 do
 local set={}
 for _,variant in ipairs(variants)do set[#set+1]=P.Line((P.Decide(Base(variant[2]))))end
 lines[round]=P.Fingerprint(set)
end
assert(lines[1]==lines[2] and lines[2]==lines[3],'repeated identical inputs give one fingerprint')
print('PASS deterministic fingerprint '..lines[1])
