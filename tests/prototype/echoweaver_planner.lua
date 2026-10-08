-- EchoWeaver ordinary engine: the Nexus bridge controls, self-contained.
-- Exact tier and locked copies, 1-based action indices, and refusals while
-- ownership or the ordinary board is not available. No outside source.
Nexus={}
dofile('logic/EchoWeaver.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local E=Nexus.EchoWeaver
local state={level=40,owned={synced=true,bySpell={[11]=1}},locked={synced=true,bySpell={[12]=1}},
 plan={requestedCounts={[11]=2,[12]=1,[13]=1}},horizon=3,charges={banish=5,freeze=3,reroll=2,trustworthy=true},
 board={cards={{spellId=11,quality=2},{spellId=14,quality=3},{spellId=15,quality=1}}}}
local out=E.DecideNexus(state)
check(out.type=='freeze' and out.index==1 and out.spellId==11,
 'a needed exact copy on the board is frozen before searching: '..tostring(out.type)..' '..tostring(out.index))
check(out.outstanding==2,'owned and locked copies are subtracted from the exact targets: '..tostring(out.outstanding))
check(out.planner=='echoweaver','the decision names its engine')
state.board.cards[1].isFrozen=true
out=E.DecideNexus(state)
check(out.type=='banish' and out.index==2,'with the needed copy frozen, a board without targets is banished by its 1-based index')
state.owned.synced=false
check(E.DecideNexus(state).type=='wait','unsynchronized ownership waits')
state.owned.synced=true;state.ordinaryBoardAllowed=false
check(E.DecideNexus(state).type=='wait','an ordinary board that Orb state does not allow waits')
-- An Orb board never searches: the same board that an ordinary run rerolls
-- is answered with a plain Select, for either Orb board marker.
local function Board(marker)
 local b={choices={{echoID=5,index=1,quality=1},{echoID=6,index=2,quality=1},{echoID=7,index=3,quality=1}},
  capabilities={canSelect=true,canBanish=true,canFreeze=true,canReroll=true}}
 if marker=='type' then b.boardType='ORB_LOST_MEMORIES' elseif marker=='flag' then b.isOrb=true end
 return {objective={requestedCounts={[1]=1},outstandingCounts={[1]=1},outstandingTotal=1},board=b,remainingPicks=10,
  resources={banishesRemaining=5,freezesRemaining=5,rerollsRemaining=5},commonBoardRerollEnabled=true}
end
check(E.Decide(Board()).action=='REROLL','control: an ordinary board without targets is rerolled')
for _,marker in ipairs({'type','flag'})do
 local d=E.Decide(Board(marker))
 check(d.action=='SELECT' and d.index==1 and d.reasonCode=='SPECIAL_BOARD_FALLBACK',
  'an Orb board ('..marker..') gets a plain Select, never a search: '..tostring(d.action))
end
print('PASS echoweaver_planner: exact-copy and safety bridge controls, Orb boards never search checks='..checks)
