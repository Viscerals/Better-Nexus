-- The adaptive rolling policy (adaptive-0-settle-live1) through the production decision
-- seam: Policy.Decide -> EchoWeaver.DecideNexus. Real pure modules in TOC order, built
-- states shaped as the runtime shapes them. Expected values are written out from the
-- rules (see docs/ADAPTIVE_ROLLING.md), never taken from a product helper. Fixtures
-- only: no draw odds, no efficacy claim.
local P=dofile('tests/prototype/policy_adapter.lua');P.Load()
local W=Nexus.EchoWeaver
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local catalog=P.Catalog({a={[0]=101,[1]=111},b={[0]=102},c={[0]=103},d={[0]=104,[1]=114},x={[0]=901},y={[0]=902},z={[0]=903}})
local function Plan(entries) return P.Plan(catalog,entries) end
local base=Plan({{spellId=101,stacks=1},{spellId=102,stacks=1}})
local function Line(a) return string.format('%s:%s:%s',a.type,tostring(a.index),tostring(a.spellId)) end
local function Decide(o)
 local input={catalog=o.catalog or catalog,plan=o.plan or base,horizon=o.horizon or 30,cards=o.cards,
  charges=o.charges or {trustworthy=true,banish=2,freeze=1,reroll=2},
  allowBanish=o.allowBanish~=false,allowReroll=o.allowReroll~=false,allowFreeze=o.allowFreeze~=false,
  owned=o.owned,locked=o.locked,level=o.level,pending=o.pending,ordinaryBoardAllowed=o.ordinaryBoardAllowed,
  rollingPolicy=o.rollingPolicy}
 return P.Decide(input)
end
local function Cards(...) local out={};for i,v in ipairs({...})do out[i]=type(v)=='table' and v or {spellId=v}end return out end

-- 0. Identity, selector, fallback labelling.
local sample=Cards(101,102,901)
local a=Decide({cards=sample})
check(a.policyId=='adaptive-0-settle-live1' and a.policyProfile=='group-protected-neutral-1' and a.policyRequested=='adaptive' and a.fallbackReason==nil,'the default is the adaptive policy, with its profile identified')
check(W.POLICY.ADAPTIVE=='adaptive-0-settle-live1' and W.POLICY.RELEASED=='released-nexus-1' and W.POLICY.PROFILE=='group-protected-neutral-1','policy and profile ids are published')
a=Decide({cards=sample,rollingPolicy='adaptive'});check(a.policyId==W.POLICY.ADAPTIVE,'explicit adaptive')
a=Decide({cards=sample,rollingPolicy='released'})
check(a.policyId=='released-nexus-1' and a.policyRequested=='released' and a.fallbackReason==nil and a.policyProfile=='none','explicit rollback selector runs the released policy and is not called a fallback')
a=Decide({cards=sample,rollingPolicy='banana'})
check(a.policyId=='released-nexus-1' and a.fallbackReason=='SELECTOR_UNKNOWN','an unknown selector runs the released policy and says why')
local selected,note=W.PolicySelection(nil);check(selected=='adaptive' and note==nil,'nil selects the default')
selected,note=W.PolicySelection(42);check(selected=='released' and note=='SELECTOR_UNKNOWN','a non-string selector is not guessed')

-- 1. Pair Freeze: keep a second useful offer. Never the surplus copy of one needed Echo.
a=Decide({cards=Cards(101,102,901),horizon=50})
check(Line(a)=='freeze:1:101' and a.reasonCode=='PAIR_FREEZE_SECOND_NEEDED','two needed offers, nothing held, many picks left: Freeze the first: '..Line(a))
a=Decide({cards=Cards(101,102,901),horizon=50,rollingPolicy='released'})
check(a.type=='take','the released policy does not Freeze at low pressure: '..Line(a))
a=Decide({cards=Cards(101,101,901),horizon=50});check(a.type=='take' and a.index==1,'two copies of an Echo needed once: take, no surplus Freeze: '..Line(a))
local two=Plan({{spellId=101,stacks=2},{spellId=102,stacks=1}})
a=Decide({plan=two,cards=Cards(101,101,901),horizon=50});check(Line(a)=='freeze:1:101','two copies needed twice: Freeze one: '..Line(a))
a=Decide({cards=Cards({spellId=101,isGuaranteed=true},102,901),horizon=50})
check(Line(a)=='freeze:2:102','a guaranteed offer is never frozen; the other needed offer is: '..Line(a))
a=Decide({cards=Cards({spellId=101,isGuaranteed=true},{spellId=102,isGuaranteed=true},901),horizon=50})
check(a.type=='take','both needed offers guaranteed: nothing can be frozen, take: '..Line(a))
a=Decide({cards=Cards({spellId=101,isFrozen=true},102,901),horizon=50});check(Line(a)=='take:2:102','one needed offer already held: no second Freeze, take the other: '..Line(a))
a=Decide({cards=Cards({spellId=101,isCarried=true},102,901),horizon=50});check(Line(a)=='take:2:102','a carried offer counts as held')
a=Decide({cards=Cards(101,{spellId=102,justFrozen=true},901),horizon=50});check(Line(a)=='take:1:101','a just-frozen offer counts as held')
for label,o in pairs({['no Freeze charge']={charges={trustworthy=true,banish=2,freeze=0,reroll=2}},['untrusted charges']={charges={trustworthy=false,banish=2,freeze=2,reroll=2}},
 ['Freeze not allowed']={allowFreeze=false},['one pick left']={horizon=1}})do
 o.cards=Cards(101,102,901);o.horizon=o.horizon or 50
 a=Decide(o);check(a.type=='take','pair Freeze is off with '..label..': '..Line(a))
end

-- 2. Scarcity: take or freeze the offer with the most missing copies; ties go to the first offer.
local scarce=Plan({{spellId=101,stacks=1},{spellId=102,stacks=3}})
a=Decide({plan=scarce,cards=Cards(101,102,901),charges={trustworthy=true,banish=0,freeze=0,reroll=0}});check(Line(a)=='take:2:102','take the offer with 3 missing copies over the one with 1: '..Line(a))
a=Decide({plan=scarce,cards=Cards(101,102,901),horizon=50});check(Line(a)=='freeze:2:102','Freeze the scarcer offer: '..Line(a))
local tiers=Plan({{spellId=102,stacks=1},{spellId=111,stacks=1}})
a=Decide({plan=tiers,cards=Cards(102,111,901),charges={trustworthy=true,banish=0,freeze=0,reroll=0}})
check(Line(a)=='take:1:102','equal need: the first offer, not the higher quality: '..Line(a))
a=Decide({plan=tiers,cards=Cards(102,111,901),charges={trustworthy=true,banish=0,freeze=0,reroll=0},rollingPolicy='released'})
check(Line(a)=='take:2:111','the released policy prefers the higher quality at equal need (documented divergence): '..Line(a))

-- 3. Banish before Reroll on a board with nothing needed; group protection; protected cards.
a=Decide({cards=Cards(901,902,903)});check(Line(a)=='banish:1:901' and a.reasonCode=='BANISH_BEFORE_REROLL','nothing needed: Banish before Reroll: '..Line(a))
a=Decide({cards=Cards(901,902,903),rollingPolicy='released'});check(a.type=='reroll','the released policy rerolls first')
a=Decide({cards=Cards(901,902,903),charges={trustworthy=true,banish=0,freeze=0,reroll=2}});check(a.type=='reroll','no Banish charge: Reroll as before: '..Line(a))
a=Decide({cards=Cards(901,902,903),allowBanish=false});check(a.type=='reroll','Banish not allowed: Reroll')
a=Decide({cards=Cards(901,902,903),allowBanish=false,allowReroll=false,horizon=40});check(a.type=='take','neither allowed, many picks left: take filler: '..Line(a))
a=Decide({cards=Cards(901,902,903),charges={trustworthy=false,banish=2,freeze=1,reroll=2}});check(a.type=='take','untrusted charges: no search action: '..Line(a))
a=Decide({cards=Cards(111,901,902)});check(Line(a)=='banish:2:901','the other quality of a missing target is protected: Banish the next offer: '..Line(a))
local both=Plan({{spellId=101,stacks=1},{spellId=104,stacks=1}})
a=Decide({plan=both,cards=Cards(111,114,111)});check(a.type=='reroll','every offer shares a group with a missing target: no Banish, Reroll: '..Line(a))
a=Decide({plan=both,cards=Cards(111,114,111),allowReroll=false,horizon=40});check(a.type=='take','and with Reroll off too: take filler: '..Line(a))
a=Decide({cards=Cards({spellId=901,isFrozen=true},{spellId=902,isGuaranteed=true},903)});check(Line(a)=='banish:3:903','frozen and guaranteed offers are never the Banish victim: '..Line(a))
a=Decide({cards=Cards({spellId=901,isFrozen=true},{spellId=902,isGuaranteed=true},{spellId=903,isFrozen=true})})
check(a.type=='take','two held offers: Reroll is prohibited and nothing is banishable: '..Line(a))
a=Decide({cards=Cards({spellId=101,isFrozen=true},{spellId=102,isFrozen=true},901),charges={trustworthy=true,banish=0,freeze=0,reroll=2}})
check(a.type=='take','two held offers never Reroll: '..Line(a))
local met=P.Owned(catalog,{[101]=1})
a=Decide({plan=Plan({{spellId=101,stacks=1},{spellId=102,stacks=1}}),owned=met,cards=Cards(101,901,902)})
check(Line(a)=='banish:1:101','an offer of a met target is not needed: it can be the Banish victim: '..Line(a))

-- A refused search action is not repeated on the same board.
local refusedState=P.State({catalog=catalog,plan=base,horizon=30,cards=Cards(901,902,903),charges={trustworthy=true,banish=2,freeze=1,reroll=2},allowBanish=true,allowReroll=true,allowFreeze=true})
refusedState.searchRefused.banish=true
a=Nexus.Policy.Decide(refusedState);check(a.type=='reroll','Banish refused on this board: Reroll: '..Line(a))
refusedState.searchRefused.reroll=true
a=Nexus.Policy.Decide(refusedState);check(a.type=='take','Banish and Reroll refused: take filler: '..Line(a))
refusedState.searchRefused.banish=false
a=Nexus.Policy.Decide(refusedState);check(a.type=='take','Reroll refused, many picks left: Banish-before-Reroll lives inside the Reroll branch, so the low-pressure fallback takes filler (as in the study): '..Line(a))
refusedState.horizon=4
a=Nexus.Policy.Decide(refusedState);check(a.type=='banish','Reroll refused, few picks left: the pressure rule Banishes: '..Line(a))

-- 4. Settle: only held offers are needed -> take the held one instead of searching.
local one=Plan({{spellId=101,stacks=1}})
a=Decide({plan=one,cards=Cards({spellId=101,isFrozen=true},901,902),horizon=2})
check(Line(a)=='take:1:101' and a.reasonCode=='SETTLE_HELD_WANTED','held needed offer, few picks left: take it instead of banishing: '..Line(a))
a=Decide({plan=one,cards=Cards({spellId=101,isFrozen=true},901,902),horizon=2,rollingPolicy='released'})
check(a.type=='banish','the released policy banishes here: '..Line(a))
a=Decide({cards=Cards({spellId=101,isFrozen=true},102,901),horizon=2});check(Line(a)=='take:2:102','an unheld needed offer is taken before the held one: '..Line(a))

-- Only held offers are needed and there are several: the first held one is taken (study: heldWanted[1]).
local twoHeld=Plan({{spellId=101,stacks=1},{spellId=114,stacks=1}})
a=Decide({plan=twoHeld,cards=Cards({spellId=101,isFrozen=true},{spellId=114,isFrozen=true},901),horizon=30})
check(Line(a)=='take:1:101','two held needed offers, no unheld one: take the first held offer: '..Line(a))

-- 5. Locked and ordinary coverage: a lock covers only the plan's locked targets.
local roles=Plan({{spellId=101,stacks=2}});roles.explicitRoles=true;roles.lockedRequestedCounts={[101]=1}
a=Decide({plan=roles,cards=Cards(101,901,902),locked=P.Owned(catalog,{[101]=1}),charges={trustworthy=true,banish=0,freeze=0,reroll=0}})
check(a.outstanding==1 and a.type=='take','101 x2 with one locked target: one lock leaves 1 ordinary copy needed: '..tostring(a.outstanding))
a=Decide({plan=roles,cards=Cards(101,901,902),locked=P.Owned(catalog,{[101]=3}),charges={trustworthy=true,banish=0,freeze=0,reroll=0}})
check(a.outstanding==1,'extra locked copies do not cover the ordinary target: '..tostring(a.outstanding))
a=Decide({plan=roles,cards=Cards(101,901,902),owned=P.Owned(catalog,{[101]=1}),locked=P.Owned(catalog,{[101]=1})})
check(a.outstanding==0,'one ordinary copy and one lock cover both targets')
local plain=Plan({{spellId=101,stacks=2}})
a=Decide({plan=plain,cards=Cards(101,901,902),locked=P.Owned(catalog,{[101]=1}),charges={trustworthy=true,banish=0,freeze=0,reroll=0}})
check(a.outstanding==1,'without explicit roles a lock counts as before: '..tostring(a.outstanding))
a=Decide({plan=roles,cards=Cards(101,901,902),locked={synced=false,bySpell={}}});check(a.type=='wait','unsynced locked state waits: '..Line(a))

-- 6. Refusals are unchanged for both policies.
for _,mode in ipairs({'adaptive','released'})do
 local function R(o)o.rollingPolicy=mode;o.cards=o.cards or Cards(101,102,901);return Decide(o)end
 check(R({ordinaryBoardAllowed=false}).type=='wait','['..mode..'] Orb gate waits')
 check(R({pending=true}).type=='wait','['..mode..'] pending action waits')
 check(R({cards=Cards(101,102)}).type=='wait','['..mode..'] two-card board waits')
 local unsynced=P.Decide({catalog=catalog,plan=base,horizon=30,cards=Cards(101,102,901),owned=P.Owned(catalog,{},false),level=20,rollingPolicy=mode,
  charges={trustworthy=true,banish=2,freeze=1,reroll=2}})
 check(unsynced.type=='wait' and unsynced.reason=='unsynced','['..mode..'] unsynced ownership waits: '..tostring(unsynced.reason))
 local noPlan=P.Decide({catalog=catalog,plan={advisorOnly=true,requestedCounts={}},horizon=30,cards=Cards(101,102,901),rollingPolicy=mode,charges={trustworthy=true,banish=2,freeze=1,reroll=2}})
 check(noPlan.type=='wait','['..mode..'] advisor-only plan waits')
end
local nilHorizon=P.State({catalog=catalog,plan=base,horizon=nil,cards=Cards(101,102,901),charges={trustworthy=true,banish=2,freeze=1,reroll=2}})
check(Nexus.Policy.Decide(nilHorizon).type=='wait','a missing pending-pick count waits')

-- 7. Required inputs missing: documented released fallback with the reason, never a guess.
local noFamilies={rows=catalog.rows,familyOf={},familyMembers=catalog.familyMembers,familyName=catalog.familyName,levers=catalog.levers}
a=Decide({catalog=noFamilies,cards=Cards(101,102,901),horizon=50})
check(a.policyId=='released-nexus-1' and a.fallbackReason=='FAMILY_UNKNOWN' and a.policyRequested=='adaptive','unknown quality group of a needed Echo: released policy, reason FAMILY_UNKNOWN: '..tostring(a.fallbackReason))
local fallbackLine=Line(a)
a=Decide({catalog=noFamilies,cards=Cards(101,102,901),horizon=50,rollingPolicy='released'});check(fallbackLine==Line(a),'the fallback decision equals the released decision')
local partial={rows=catalog.rows,familyOf={[101]=catalog.familyOf[101],[102]=catalog.familyOf[102]},levers={}}
a=Decide({catalog=partial,cards=Cards(901,902,903)})
check(a.policyId==W.POLICY.ADAPTIVE and a.type=='reroll','families known for needed Echoes, unknown for offers: adaptive runs; an offer whose group is unknown is not Banished, so it Rerolls: '..Line(a)..' '..tostring(a.fallbackReason))
check(a.fallbackReason==nil,'no fallback')
a=Decide({catalog=partial,cards=Cards(901,902,903),allowReroll=false,horizon=40})
check(a.type=='take','no offer has a known group: none is Banished: '..Line(a))
-- Every adaptive action is validated again; an invalid one falls back with a reason.
local realDecide=W.Decide
local calls=0
W.Decide=function(input)
 calls=calls+1
 if calls==1 then return {action='FREEZE',echoID=101,index=1,reasonCode='FREEZE_OUTSTANDING_FOR_HIGH_PRESSURE_SEARCH',pressure='HIGH'} end
 return realDecide(input)
end
a=Decide({cards=Cards({spellId=101,isGuaranteed=true},901,902)})
W.Decide=realDecide
check(a.policyId=='released-nexus-1' and a.fallbackReason=='ACTION_INVALID' and a.type~='freeze','a Freeze of a guaranteed offer is refused: '..Line(a)..' '..tostring(a.fallbackReason))
-- Identity, selectability and the two-held Reroll rule are checked by the final validation too.
local function Forced(response,cards)
 local first=true
 W.Decide=function(input) if first then first=false;return response end;return realDecide(input) end
 local got=Decide({cards=cards})
 W.Decide=realDecide
 return got
end
a=Forced({action='SELECT',echoID=999,index=1,reasonCode='SELECT_OUTSTANDING_WISHLIST'},Cards(101,901,902))
check(a.fallbackReason=='ACTION_INVALID','a Take whose Echo is not the offer at its index is refused: '..tostring(a.fallbackReason))
a=Forced({action='REROLL',reasonCode='REROLL_COMMON_UNWANTED_BOARD'},Cards({spellId=901,isFrozen=true},{spellId=902,isFrozen=true},903))
check(a.fallbackReason=='ACTION_INVALID','a Reroll with two held offers is refused: '..tostring(a.fallbackReason))
a=Forced({action='REROLL',reasonCode='REROLL_COMMON_UNWANTED_BOARD'},Cards(901,902,903))
check(a.fallbackReason==nil and a.type=='reroll','a valid forced Reroll passes the final validation: '..Line(a))
local unselectable=P.State({catalog=catalog,plan=base,horizon=50,cards=Cards(101,102,901),charges={trustworthy=true,banish=2,freeze=1,reroll=2},allowBanish=true,allowReroll=true,allowFreeze=true})
unselectable.board.cards[1].selectable=false
a=Nexus.Policy.Decide(unselectable)
check(a.type=='take' and a.spellId==102 and a.policyId==W.POLICY.ADAPTIVE and a.fallbackReason==nil,'an unselectable needed offer is not useful: the adaptive policy itself takes the selectable one, no pair Freeze: '..Line(a)..' '..tostring(a.fallbackReason))
W.Decide=function(input) calls=calls+1;if calls%2==1 then error('boom') end;return realDecide(input) end
calls=0
a=Decide({cards=Cards(101,102,901)})
W.Decide=realDecide
check(a.policyId=='released-nexus-1' and a.fallbackReason=='ADAPTIVE_ERROR','an error inside the adaptive path falls back to the released policy with a reason: '..tostring(a.fallbackReason))

-- 8. Purity: no global change, no input change, same input same output.
local policyBefore={};for k,v in pairs(W.NEXUS_POLICY)do policyBefore[k]=v end
local function Dump(v) if type(v)~='table' then return tostring(v) end local k={};for key in pairs(v)do k[#k+1]=key end table.sort(k,function(x,y)return tostring(x)<tostring(y) end)
 local out={};for _,key in ipairs(k)do out[#out+1]=tostring(key)..'='..Dump(v[key])end return '{'..table.concat(out,',')..'}' end
local state=P.State({catalog=catalog,plan=base,horizon=50,cards=Cards(101,102,901),charges={trustworthy=true,banish=2,freeze=1,reroll=2},allowFreeze=true,allowBanish=true,allowReroll=true})
local before=Dump(state);local x,y=Nexus.Policy.Decide(state),Nexus.Policy.Decide(state)
check(Dump(state)==before,'the decision state is not modified')
check(Line(x)==Line(y) and x.reasonCode==y.reasonCode,'same input, same decision')
for k,v in pairs(W.NEXUS_POLICY)do check(policyBefore[k]==v,'the shared policy table is unchanged: '..k)end
check(W.NEXUS_POLICY.banishBeforeReroll==nil,'the adaptive option is never written to the shared policy table')
local pure=W.Decide({objective={requestedCounts={[101]=1},outstandingCounts={[101]=0},outstandingTotal=0},remainingPicks=30,
 board={choices={{echoID=901,quality=0},{echoID=902,quality=0},{echoID=903,quality=0}},capabilities={canSelect=true,canBanish=true,canFreeze=true,canReroll=true}},
 resources={banishesRemaining=2,freezesRemaining=1,rerollsRemaining=2},commonBoardRerollEnabled=true,policy=W.NEXUS_POLICY})
check(pure.action=='SELECT','the pure planner without the adaptive option is unchanged')
pure=W.Decide({objective={requestedCounts={[101]=1},outstandingCounts={[101]=1},outstandingTotal=1},remainingPicks=30,
 board={choices={{echoID=901,quality=0},{echoID=902,quality=0},{echoID=903,quality=0}},capabilities={canSelect=true,canBanish=true,canFreeze=true,canReroll=true}},
 resources={banishesRemaining=2,freezesRemaining=1,rerollsRemaining=2},commonBoardRerollEnabled=true,policy=W.NEXUS_POLICY})
check(pure.action=='REROLL','without the option an unwanted board still Rerolls first')
local withOption={};for k,v in pairs(W.NEXUS_POLICY)do withOption[k]=v end;withOption.banishBeforeReroll=true
pure=W.Decide({objective={requestedCounts={[101]=1},outstandingCounts={[101]=1},outstandingTotal=1},remainingPicks=30,
 board={choices={{echoID=901,quality=0},{echoID=902,quality=0},{echoID=903,quality=0}},capabilities={canSelect=true,canBanish=true,canFreeze=true,canReroll=true}},
 resources={banishesRemaining=2,freezesRemaining=1,rerollsRemaining=2},commonBoardRerollEnabled=true,policy=withOption})
check(pure.action=='BANISH' and pure.reasonCode=='BANISH_BEFORE_REROLL','with the option it Banishes first through the same gates')
withOption.banishBeforeReroll=true
pure=W.Decide({objective={requestedCounts={[101]=1},outstandingCounts={[101]=1},outstandingTotal=1},remainingPicks=30,
 board={choices={{echoID=901,quality=0},{echoID=902,quality=0},{echoID=903,quality=0}},capabilities={canSelect=true,canBanish=false,canFreeze=true,canReroll=true}},
 resources={banishesRemaining=2,freezesRemaining=1,rerollsRemaining=2},commonBoardRerollEnabled=true,policy=withOption})
check(pure.action=='REROLL','the option cannot override a Banish permission')

-- 9. Independent safety invariants over the replay vectors and a larger random sweep.
local function Safe(input,got,label)
 local cards,ch=input.cards,input.charges
 local frozen=0;for _,c in ipairs(cards)do if c.isFrozen or c.isCarried or c.justFrozen then frozen=frozen+1 end end
 local card=got.index and cards[got.index]
 if got.type=='take' then check(card and card.spellId==got.spellId,label..': take names an offered Echo') end
 if got.type=='banish' then
  check(card and not card.isGuaranteed and not card.isFrozen and not card.isCarried and not card.justFrozen,label..': Banish never aims at a protected offer')
  check(ch.trustworthy and (ch.banish or 0)>0 and input.allowBanish,label..': Banish needs a trusted charge and permission')
 elseif got.type=='freeze' then
  check(card and not card.isGuaranteed and not card.isFrozen and not card.isCarried and not card.justFrozen,label..': Freeze never aims at a protected offer')
  check(ch.trustworthy and (ch.freeze or 0)>0 and input.allowFreeze and input.horizon>=2,label..': Freeze needs a trusted charge, permission and two picks')
 elseif got.type=='reroll' then
  check(ch.trustworthy and (ch.reroll or 0)>0 and input.allowReroll and frozen<2,label..': Reroll needs a trusted charge, permission and fewer than two held offers')
 end
end
local V=dofile('tests/prototype/fixtures/adaptive_parity_vectors.lua')
local function FromVector(v)
 local families={}
 for f,members in ipairs(v.F)do local fam={};for q,id in ipairs(members)do fam[q-1]=id end;families['f'..f]=fam end
 local cat=P.Catalog(families)
 local targets={};for i,t in ipairs(v.T)do targets[i]={spellId=t[1],stacks=t[2]}end
 local owned={};for id,n in pairs(v.O)do owned[id]=n end
 local cards={}
 for i,c in ipairs(v.C)do cards[i]={spellId=c[1],isFrozen=c[2]:find('F',1,true)~=nil,isCarried=c[2]:find('C',1,true)~=nil,justFrozen=c[2]:find('J',1,true)~=nil,isGuaranteed=c[2]:find('G',1,true)~=nil}end
 return {catalog=cat,plan=P.Plan(cat,targets),owned=P.Owned(cat,owned),cards=cards,horizon=v.H,charges={banish=v.R[1],reroll=v.R[2],freeze=v.R[3],trustworthy=v.R[4]},
  allowBanish=v.A[1],allowReroll=v.A[2],allowFreeze=v.A[3]}
end
local sweep=0
for _,set in ipairs({V.parity,V.divergence})do
 for n,v in ipairs(set)do
  local input=FromVector(v);local got=P.Decide(input);sweep=sweep+1
  check(got.fallbackReason==nil,'sweep '..sweep..': no fallback on a complete state')
  Safe(input,got,'sweep '..sweep)
 end
end
print('PASS adaptive policy rules checks='..checks..' sweep='..sweep)
