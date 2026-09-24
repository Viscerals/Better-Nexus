-- R3 (review of main eadff8a), report scenario F1: a satisfied Wishlist target
-- on the board stopped a permitted Reroll. This is a PROPOSED strategy change,
-- not a proven bug: the earlier behaviour follows the named reference strategy.
-- NEW test written from the report's stated scenario; not a rerun of the
-- review's original probe. It uses the maintained production-policy adapter
-- (real pure modules in TOC order). The scripted board sequences below are
-- fixed fixtures. They model no draw odds and prove no general efficiency gain.
local P=dofile('tests/prototype/policy_adapter.lua');P.Load()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local catalog=P.Catalog({a={[0]=101},b={[0]=102},x={[0]=901},y={[0]=902},z={[0]=903},w={[0]=904}})
local plan=P.Plan(catalog,{{spellId=101,stacks=1},{spellId=102,stacks=1}})
local REROLLS={trustworthy=true,banish=0,freeze=0,reroll=5}
local function F1(extra)
 local input={catalog=catalog,plan=plan,horizon=1,cards={{spellId=101},{spellId=901},{spellId=902}},
  owned=P.Owned(catalog,{[101]=1}),charges=REROLLS,allowReroll=true}
 for k,v in pairs(extra or {})do input[k]=v end
 return input
end
-- F1: 101 is satisfied, only 102 is missing, five Rerolls are permitted.
local a=P.Decide(F1())
check(a.planner=='echoweaver' and a.type=='reroll','F1 searches instead of taking a surplus copy: '..P.Line(a))
check(a.reasonCode=='REROLL_NO_OUTSTANDING_ON_BOARD','F1 has its own reason code')
check(not a.reason:find('no requested',1,true),'the reason does not claim that no requested Echo is on the board')
dofile('core/UserText.lua')
check(Nexus.UserText.Message(a.reason)=='Reroll: no Echo on this board is still needed','the visible text is truthful for this board')
-- Control from the report: only filler on the board. Unchanged reference decision and reason.
a=P.Decide(F1({cards={{spellId=903},{spellId=901},{spellId=902}}}))
check(a.type=='reroll' and a.reasonCode=='REROLL_COMMON_UNWANTED_BOARD','filler-only control keeps the reference Reroll and reason')

-- Actual settings and resources stay authoritative.
a=P.Decide(F1({allowReroll=false}))
check(a.type=='take' and a.spellId==101,'Reroll preference OFF: no Reroll: '..P.Line(a))
a=P.Decide(F1({charges={trustworthy=true,banish=0,freeze=0,reroll=0}}))
check(a.type=='take','no Reroll charge: no Reroll')
a=P.Decide(F1({charges={trustworthy=false,banish=0,freeze=0,reroll=5}}))
check(a.type=='take','untrusted resource state: no Reroll')
a=P.Decide(F1({pending=true}));check(a.type=='wait','pending action guard still waits')
a=P.Decide(F1({pendingAction={kind='reroll'}}));check(a.type=='wait','pending submitted action still waits')
a=P.Decide(F1({ordinaryBoardAllowed=false}));check(a.type=='wait','ordinary-board gate still waits')
a=P.Decide(F1({cards={{spellId=101,isFrozen=true},{spellId=901,isFrozen=true},{spellId=902}}}))
check(a.type~='reroll','two frozen offers still prohibit Reroll')

-- Useful offers are never rerolled away.
a=P.Decide(F1({cards={{spellId=101},{spellId=102},{spellId=902}}}))
check(a.type=='take' and a.spellId==102,'a still-needed Echo on the board is taken')
a=P.Decide(F1({cards={{spellId=101},{spellId=102,isFrozen=true},{spellId=902}}}))
check(a.type=='take' and a.spellId==102,'a frozen still-needed Echo is kept and taken, not rerolled')
-- Exact copies: 101 x2 requested, one owned: 101 is still needed.
local two=P.Plan(catalog,{{spellId=101,stacks=2},{spellId=102,stacks=1}})
a=P.Decide(F1({plan=two}));check(a.type=='take' and a.spellId==101,'exact copy count: a partly met target is still taken')
-- Permanent ownership counts, as in the production state.
a=P.Decide(F1({owned=P.Owned(catalog,{}),locked=P.Owned(catalog,{[101]=1})}))
check(a.type=='reroll','a target met by a locked copy is satisfied too')
-- Wishlist complete: unchanged fallback, no Reroll.
a=P.Decide(F1({owned=P.Owned(catalog,{[101]=1,[102]=1})}))
check(a.type=='take' and a.reasonCode=='OBJECTIVE_COMPLETE_FALLBACK','complete Wishlist never rerolls')

-- The pure planner without the explicit option keeps the reference decision.
local function Pure(policy)
 return Nexus.EchoWeaver.Decide({objective={requestedCounts={[101]=1,[102]=1},outstandingCounts={[101]=0,[102]=1},outstandingTotal=1},
  remainingPicks=1,board={choices={{echoID=101,quality=0},{echoID=901,quality=0},{echoID=902,quality=0}},
   capabilities={canSelect=true,canBanish=false,canFreeze=false,canReroll=true}},
  resources={banishesRemaining=0,freezesRemaining=0,rerollsRemaining=5},commonBoardRerollEnabled=true,policy=policy})
end
local ref=Pure(nil)
check(ref.action=='SELECT' and ref.echoID==101 and ref.reasonCode=='RESOURCE_EXHAUSTED_FALLBACK','without the option: reference decision')
check(Pure({rerollIgnoresSatisfiedTargets=true}).action=='REROLL','with the option: Reroll')
check(Nexus.EchoWeaver.NEXUS_POLICY.rerollIgnoresSatisfiedTargets==true,'DecideNexus uses the explicit option')

-- Fixed-fixture replays: one pick left, five Rerolls. Each Reroll shows the next
-- scripted board. Counts are outcomes on these fixtures only.
local function Replay(boards,policy)
 local saved=Nexus.EchoWeaver.NEXUS_POLICY
 Nexus.EchoWeaver.NEXUS_POLICY=policy
 local rerolls,i,taken=5,1,nil
 while true do
  local d=P.Decide(F1({cards=boards[i],charges={trustworthy=true,banish=0,freeze=0,reroll=rerolls}}))
  if d.type=='reroll' then rerolls=rerolls-1;i=i+1;assert(boards[i],'fixture long enough')
  else taken=d.spellId;break end
 end
 Nexus.EchoWeaver.NEXUS_POLICY=saved
 return taken,5-rerolls
end
local found={{{spellId=101},{spellId=901},{spellId=902}},{{spellId=902},{spellId=903},{spellId=904}},{{spellId=102},{spellId=901},{spellId=903}}}
local never={};for i=1,6 do never[i]={{spellId=101},{spellId=901},{spellId=902}} end
local takenNew,spentNew=Replay(found,{rerollIgnoresSatisfiedTargets=true})
local takenRef,spentRef=Replay(found,{})
check(takenRef==101 and spentRef==0,'fixture A, reference rule: surplus 101 taken, 0 Rerolls, 102 still missing')
check(takenNew==102 and spentNew==2,'fixture A, R3 rule: 102 taken after 2 Rerolls')
takenNew,spentNew=Replay(never,{rerollIgnoresSatisfiedTargets=true})
takenRef,spentRef=Replay(never,{})
check(takenRef==101 and spentRef==0,'fixture B, reference rule: surplus 101 taken, 0 Rerolls')
check(takenNew==101 and spentNew==5,'fixture B, R3 rule: all 5 Rerolls spent, same final pick (the cost side of the trade-off)')
print('PASS R3 reroll considers outstanding need; settings, resources, guards and useful offers kept checks='..checks)
