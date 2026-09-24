Nexus={}
dofile('logic/EchoWeaver.lua')
local ref={}
local reference=os.getenv('LOADOUTPILOT_ROOT') or '../reference/LoadoutPilot'
assert(loadfile(reference..'/Domain/EchoSelectionPolicy.lua'))('LoadoutPilot',ref)
assert(loadfile(reference..'/Engine/WishlistPlanner.lua'))('LoadoutPilot',ref)
math.randomseed(20260918)
local function same(a,b,field,case)
 assert(a[field]==b[field], 'case '..case..' '..field..' actual='..tostring(a[field])..' reference='..tostring(b[field]))
end
local count=0
for case=1,10000 do
 local objective={requestedCounts={},outstandingCounts={},outstandingTotal=0,banlistedEchoes={},sortedEchoIDs={}}
 for id=1,8 do
  local n=math.random(0,5)
  if n>0 then objective.sortedEchoIDs[#objective.sortedEchoIDs+1]=id; objective.requestedCounts[id]=n; objective.outstandingCounts[id]=math.random(0,n); objective.outstandingTotal=objective.outstandingTotal+objective.outstandingCounts[id] end
  if math.random(1,7)==1 then objective.banlistedEchoes[id]=true end
 end
 local board={choices={},capabilities={canSelect=math.random(1,15)>1,canFreeze=math.random(1,4)>1,
  canBanish=math.random(1,4)>1,canReroll=math.random(1,4)>1},twoFrozenRerollProhibited=math.random(1,10)==1}
 for i=1,3 do board.choices[i]={echoID=math.random(1,10),quality=math.random(0,4),frozen=math.random(1,5)==1,
  selectable=math.random(1,15)>1,freezeEligible=math.random(1,4)>1,banishEligible=math.random(1,4)>1} end
 local input={objective=objective,board=board,remainingPicks=math.random(0,79),
  resources={freezesRemaining=math.random(0,9),banishesRemaining=math.random(0,10),rerollsRemaining=math.random(0,9)},
  commonBoardRerollEnabled=math.random(0,1)==1,pending=math.random(1,20)==1}
 if case%29==0 then board.boardType='ORB_LOST_MEMORIES' end
 local a,b=Nexus.EchoWeaver.Decide(input),ref.WishlistPlanner.Decide(input)
 if a.action~=b.action or a.echoID~=b.echoID then
  print('DIFF',case,a.action,a.echoID,a.reasonCode,b.action,b.echoID,b.reasonCode,'left',input.remainingPicks,'total',objective.outstandingTotal,'special',board.boardType)
  for i,c in ipairs(board.choices) do print(i,c.echoID,c.quality,c.frozen,c.selectable,c.freezeEligible,c.banishEligible,'requested',objective.requestedCounts[c.echoID],'need',objective.outstandingCounts[c.echoID],'ban',objective.banlistedEchoes[c.echoID]) end
 end
 for _,field in ipairs({'action','echoID','index','reasonCode','remainingPicks','outstandingTotal','completionFeasibleByCount'}) do same(a,b,field,case) end
 count=count+1
end
-- Exact tier, permanent locks, user reroll choice and 1-based action indices.
local state={level=40,owned={synced=true,bySpell={[11]=1}},locked={synced=true,bySpell={[12]=1}},
 plan={requestedCounts={[11]=2,[12]=1,[13]=1}},horizon=3,charges={banish=5,freeze=3,reroll=2,trustworthy=true},
 board={cards={{spellId=11,quality=2},{spellId=14,quality=3},{spellId=15,quality=1}}}}
local out=Nexus.EchoWeaver.DecideNexus(state)
assert(out.type=='freeze' and out.index==1 and out.spellId==11)
assert(out.outstanding==2)
state.board.cards[1].isFrozen=true
out=Nexus.EchoWeaver.DecideNexus(state); assert(out.type=='banish' and out.index==2)
state.owned.synced=false; assert(Nexus.EchoWeaver.DecideNexus(state).type=='wait')
state.owned.synced=true;state.ordinaryBoardAllowed=false
assert(Nexus.EchoWeaver.DecideNexus(state).type=='wait')
print('PASS reference differential decisions='..count..'; exact-copy/safety bridge controls=4')
