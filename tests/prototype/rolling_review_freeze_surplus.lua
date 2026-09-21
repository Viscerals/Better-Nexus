-- R5 (review of main eadff8a), report scenario F3: Freeze reserved a copy that
-- the next selection made surplus. This is a PROPOSED strategy change, not a
-- proven bug: the earlier behaviour follows the named reference strategy.
-- NEW test written from the report's stated scenario; not a rerun of the
-- review's original probe. It uses the maintained production-policy adapter
-- (real pure modules in TOC order). Fixtures only; no draw odds; no general
-- efficiency claim.
local P=dofile('tests/prototype/policy_adapter.lua');P.Load()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local catalog=P.Catalog({a={[0]=101},b={[0]=102},x={[0]=901},y={[0]=902}})
local plan=P.Plan(catalog,{{spellId=101,stacks=1},{spellId=102,stacks=1}})
local function F3(extra)
 local input={catalog=catalog,plan=plan,horizon=2,cards={{spellId=101},{spellId=101},{spellId=901}},
  charges={trustworthy=true,banish=1,freeze=1,reroll=0},allowFreeze=true,allowBanish=true}
 for k,v in pairs(extra or {})do input[k]=v end
 return input
end
-- F3: need 101 x1 and 102 x1; the board shows 101 twice.
local a=P.Decide(F3())
check(a.planner=='pilot103' and a.type=='take' and a.spellId==101 and a.index==1,'F3: take one 101; do not Freeze a copy the next pick makes surplus: '..P.Line(a))
check(a.reasonCode=='SELECT_OUTSTANDING_WISHLIST','existing reason code')
-- The Freeze rule itself is kept where the held copy stays needed.
a=P.Decide(F3({cards={{spellId=101},{spellId=102},{spellId=901}}}))
check(a.type=='freeze' and a.spellId==101,'two different needed Echoes: reference Freeze kept: '..P.Line(a))
a=P.Decide(F3({cards={{spellId=101},{spellId=901},{spellId=902}}}))
check(a.type=='freeze' and a.spellId==101,'single needed copy with search available: reference Freeze kept')
local two=P.Plan(catalog,{{spellId=101,stacks=2},{spellId=102,stacks=1}})
a=P.Decide(F3({plan=two,horizon=3}))
check(a.type=='freeze' and a.spellId==101,'exact copies: 101 x2 needed, two on board: the held copy stays needed, Freeze kept')
a=P.Decide(F3({plan=two,horizon=3,owned=P.Owned(catalog,{[101]=1})}))
check(a.type=='take' and a.spellId==101,'exact copies: 101 x2 requested, one owned: the second board copy would be surplus, no Freeze')
a=P.Decide(F3({plan=two,horizon=3,locked=P.Owned(catalog,{[101]=1})}))
check(a.type=='take' and a.spellId==101,'a permanent copy counts too')
-- Settings, resources and guards unchanged.
a=P.Decide(F3({allowFreeze=false}));check(a.type=='take' and a.spellId==101,'Freeze preference OFF: take')
a=P.Decide(F3({charges={trustworthy=true,banish=1,freeze=0,reroll=0}}));check(a.type=='take','no Freeze charge: take')
a=P.Decide(F3({pending=true}));check(a.type=='wait','pending guard waits')
a=P.Decide(F3({ordinaryBoardAllowed=false}));check(a.type=='wait','ordinary-board gate waits')
-- An already frozen offer is respected exactly as before.
a=P.Decide(F3({cards={{spellId=101,isFrozen=true},{spellId=101},{spellId=901}},charges={trustworthy=true,banish=1,freeze=0,reroll=0}}))
check(a.type=='take' and a.index==2,'observed frozen copy: the unfrozen needed copy is taken (unchanged)')

-- The pure planner without the explicit option keeps the reference decision.
local function Pure(policy)
 return Nexus.WishlistPilot.Decide({objective={requestedCounts={[101]=1,[102]=1},outstandingCounts={[101]=1,[102]=1},outstandingTotal=2},
  remainingPicks=2,board={choices={{echoID=101,quality=0},{echoID=101,quality=0},{echoID=901,quality=0}},
   capabilities={canSelect=true,canBanish=true,canFreeze=true,canReroll=false}},
  resources={banishesRemaining=1,freezesRemaining=1,rerollsRemaining=0},commonBoardRerollEnabled=false,policy=policy})
end
local ref=Pure(nil)
check(ref.action=='FREEZE' and ref.index==1 and ref.reasonCode=='FREEZE_OUTSTANDING_FOR_HIGH_PRESSURE_SEARCH','without the option: reference Freeze')
local new=Pure({freezeMustStayNeeded=true})
check(new.action=='SELECT' and new.echoID==101 and new.index==1,'with the option: select')
check(Nexus.WishlistPilot.NEXUS_POLICY.freezeMustStayNeeded==true,'DecideNexus uses the explicit option')
-- A duplicate that cannot be selected is not the next selection. The production
-- board projection carries no selectable field, so this uses the pure planner.
local function PureUnselectable(policy)
 return Nexus.WishlistPilot.Decide({objective={requestedCounts={[101]=1,[102]=1},outstandingCounts={[101]=1,[102]=1},outstandingTotal=2},
  remainingPicks=2,board={choices={{echoID=101,quality=0},{echoID=101,quality=0,selectable=false},{echoID=901,quality=0}},
   capabilities={canSelect=true,canBanish=true,canFreeze=true,canReroll=false}},
  resources={banishesRemaining=1,freezesRemaining=1,rerollsRemaining=0},commonBoardRerollEnabled=false,policy=policy})
end
check(PureUnselectable({freezeMustStayNeeded=true}).action=='FREEZE','unselectable duplicate: reference Freeze kept')

-- Fixed two-step replay of F3. After a Freeze the held card stays on the next
-- board; after a Take the next board is the scripted fresh board.
local function Replay(policy)
 local saved=Nexus.WishlistPilot.NEXUS_POLICY;Nexus.WishlistPilot.NEXUS_POLICY=policy
 local first=P.Decide(F3())
 local freezes,owned,second=0,{},nil
 if first.type=='freeze' then
  freezes=1
  second=P.Decide(F3({cards={{spellId=101,isFrozen=true},{spellId=101},{spellId=901}},charges={trustworthy=true,banish=1,freeze=0,reroll=0}}))
 end
 Nexus.WishlistPilot.NEXUS_POLICY=saved
 return first,second,freezes
end
local r1,r2,rf=Replay({})
check(r1.type=='freeze' and r2 and r2.type=='take' and r2.index==2 and rf==1,
 'reference rule on F3: Freeze spent, the other 101 taken next, the held 101 is then surplus and keeps one offer slot')
local n1,n2,nf=Replay({freezeMustStayNeeded=true})
check(n1.type=='take' and n2==nil and nf==0,'R5 rule on F3: 101 taken at once, Freeze kept, next board has three fresh offers')
print('PASS R5 no Freeze of a copy the next selection makes surplus; reference Freeze kept elsewhere checks='..checks)
